import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/plans/data/plan_repository.dart';
import 'package:dartlab/features/plans/domain/training_plan.dart';
import 'package:dartlab/features/plans/presentation/plan_run_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/pump_app.dart';

void main() {
  late ProviderContainer container;
  late AppDatabase db;
  late SimulatorSource sim;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(db),
      dartSourceFactoryProvider.overrideWithValue(testSourceFactory),
    ]);
    container.listen(activeGameProvider, (_, _) {});
    container.listen(planRunProvider, (_, _) {});
    sim = container.read(dartSourceProvider) as SimulatorSource;
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  PlanRunController controller() => container.read(planRunProvider.notifier);
  ActiveGame game() => container.read(activeGameProvider)!;

  Future<void> bulls(int n) async {
    for (var i = 0; i < n; i++) {
      sim.throwAt(BoardGeometry.centerOf(Segment.bull));
      await pumpEventQueue();
    }
  }

  test('überspringt unbekannte Spiele, merkt den Fortschritt, setzt fort', () async {
    final repo = PlanRepository(db);
    final id = await repo.create(name: 'Test', steps: const [
      PlanStep(gameId: 'game_from_the_future'),
      PlanStep(gameId: 'bull_drill', config: {'visits': 1}),
      PlanStep(gameId: 'highscore_hunt', config: {'visits': 2}, note: 'Vollgas'),
    ]);
    final plan = (await repo.byId(id))!;

    expect(await controller().start(plan), isTrue);
    var s = container.read(planRunProvider)!;
    expect(s.stepIndex, 1);
    expect(s.run.resultOf(0)!.status, StepStatus.unavailable);
    expect(game().gameId, 'bull_drill');
    expect(controller().owns(game()), isTrue);

    // Regulär beendet: zählt sofort.
    await bulls(3);
    expect(game().ended, isTrue);
    await controller().pending;
    s = container.read(planRunProvider)!;
    expect(s.recorded, isTrue);
    expect(s.run.currentStep, 2);
    final first = s.run.resultOf(1)!;
    expect(first.status, StepStatus.done);
    expect(first.darts, 3);
    expect(first.sessionUid, (await db.select(db.sessions).get()).single.uid);
    expect(first.summary.map((e) => e.$1), contains('points'));

    // Plan verlassen, später fortsetzen: es geht mit Schritt 3 weiter.
    await container.read(activeGameProvider.notifier).close();
    container.invalidate(planRunProvider);
    expect(await controller().start(plan, resume: true), isTrue);
    expect(container.read(planRunProvider)!.stepIndex, 2);
    expect(game().gameId, 'highscore_hunt');

    // Vorzeitig beendet: zählt erst mit „Nächster Schritt“.
    await bulls(1);
    await container.read(activeGameProvider.notifier).end();
    await controller().pending;
    expect(container.read(planRunProvider)!.recorded, isFalse);
    expect(await controller().next(), isFalse, reason: 'letzter Schritt');
    final runId = await controller().finish();
    expect(container.read(planRunProvider), isNull);
    expect(container.read(activeGameProvider), isNull);

    final run = (await repo.run(runId!))!;
    expect(run.finished, isTrue);
    expect(run.results.map((r) => r.status), [StepStatus.unavailable, StepStatus.done, StepStatus.aborted]);
    expect(await repo.openRun(id, playerId: run.playerId), isNull);
  });

  test('„Nochmal“ während eines Plans gehört nicht mehr zum Plan', () async {
    final repo = PlanRepository(db);
    final id = await repo.create(name: 'Kurz', steps: const [
      PlanStep(gameId: 'bull_drill', config: {'visits': 1}),
      PlanStep(gameId: 'bull_drill', config: {'visits': 1}),
    ]);
    await controller().start((await repo.byId(id))!);
    await bulls(3);
    await controller().pending;
    final def = game().session.definition;
    await container.read(activeGameProvider.notifier).start(def, const {'visits': 1});
    expect(controller().owns(game()), isFalse);
    await bulls(3);
    await controller().pending;
    expect(container.read(planRunProvider)!.run.currentStep, 1);
    // Weiter mit dem Plan.
    expect(await controller().next(), isTrue);
    expect(container.read(planRunProvider)!.stepIndex, 1);
  });
}
