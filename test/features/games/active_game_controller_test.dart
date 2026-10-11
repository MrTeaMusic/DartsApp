import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_training.dart';
import 'package:dartlab/features/games/domain/games/scoring_drills.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
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
    sim = container.read(dartSourceProvider) as SimulatorSource;
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  ActiveGameController controller() => container.read(activeGameProvider.notifier);
  ActiveGame game() => container.read(activeGameProvider)!;

  Future<void> hit(Segment s) async {
    sim.throwAt(BoardGeometry.centerOf(s));
    await pumpEventQueue();
  }

  test('Würfe der Quelle landen im Spiel und in der Datenbank', () async {
    await controller().start(HighscoreHunt.definition, const {'visits': 2}, seed: 1);
    await hit(Segment.triple(20));
    await hit(Segment.triple(20));
    await hit(Segment.triple(20));
    expect((game().game as HighscoreHunt).visitScores, [180]);
    await hit(Segment.single(1));
    await hit(Segment.single(1));
    await hit(Segment.single(1));
    expect(game().ended, isTrue);
    expect(game().events.map((e) => e.type), contains(GameEventType.finished));
    await controller().pendingWrites;

    final repo = container.read(gameRepositoryProvider);
    final throws = await repo.throwsOf(game().sessionId);
    expect(throws.map((t) => t.segment), ['T20', 'T20', 'T20', 'S1', 'S1', 'S1']);
    expect(throws.map((t) => t.visitIndex), [0, 0, 0, 1, 1, 1]);
    expect(throws.first.x, isNotNull, reason: 'Simulator liefert Koordinaten');
    final recent = await repo.watchRecent().first;
    expect(recent.single.finished, isTrue);
    expect(recent.single.metrics['points'], 183);
  });

  test('Rückgängig über die Quelle korrigiert Spiel und Datenbank', () async {
    await controller().start(HighscoreHunt.definition, const {'visits': 3}, seed: 1);
    await hit(Segment.triple(20));
    await hit(Segment.single(5));
    controller().undo();
    await pumpEventQueue();
    expect((game().game as HighscoreHunt).total, 60);
    await controller().pendingWrites;
    final throws = await container.read(gameRepositoryProvider).throwsOf(game().sessionId);
    expect(throws.map((t) => t.segment), ['T20']);
  });

  test('Checkout gibt die Aufnahme im Simulator sofort frei', () async {
    await controller().start(CheckoutTraining.definition, const {'min': 40, 'max': 40, 'attempts': 2}, seed: 1);
    await hit(Segment.double(20));
    expect(game().events.first.type, GameEventType.checkout);
    // Ohne Freigabe würde der nächste Dart ignoriert.
    await hit(Segment.double(20));
    expect((game().game as CheckoutTraining).results.map((r) => r.success), [true, true]);
    expect(game().ended, isTrue);
  });

  test('Abbrechen speichert den Zwischenstand als nicht beendet', () async {
    await controller().start(HighscoreHunt.definition, const {'visits': 10}, seed: 1);
    await hit(Segment.single(20));
    await controller().close();
    expect(container.read(activeGameProvider), isNull);
    final recent = await container.read(gameRepositoryProvider).watchRecent().first;
    expect(recent.single.finished, isFalse);
    expect(recent.single.dartCount, 1);
  });

  test('Weiter-Knopf beendet die Aufnahme', () async {
    await controller().start(ScoreTarget.definition, const {'visits': 2, 'target': 60}, seed: 1);
    await hit(Segment.triple(20));
    controller().nextVisit();
    await pumpEventQueue();
    expect((game().game as ScoreTarget).successes, 1);
  });
}
