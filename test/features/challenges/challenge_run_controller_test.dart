import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/challenges/data/challenge_repository.dart';
import 'package:dartlab/features/challenges/domain/challenge_catalog.dart';
import 'package:dartlab/features/challenges/presentation/challenge_run_controller.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/progress/data/achievement_repository.dart';
import 'package:dartlab/features/progress/presentation/celebrations.dart';
import 'package:dartlab/features/progress/presentation/progress_providers.dart';
import 'package:dartlab/features/stats/data/stats_repository.dart';
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
    SharedPreferences.setMockInitialValues({'goals.dailyUnit': 'darts', 'goals.dailyAmount': 30});
    final sp = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(db),
      dartSourceFactoryProvider.overrideWithValue(testSourceFactory),
    ]);
    container
      ..listen(activeGameProvider, (_, _) {})
      ..listen(matchControllerProvider, (_, _) {})
      ..listen(challengeRunProvider, (_, _) {})
      ..listen(achievementRecorderProvider, (_, _) {})
      ..listen(celebrationsProvider, (_, _) {});
    sim = container.read(dartSourceProvider) as SimulatorSource;
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  ChallengeRunController controller() => container.read(challengeRunProvider.notifier);

  Future<void> throwAt(Segment s, int n) async {
    for (var i = 0; i < n; i++) {
      sim.throwAt(BoardGeometry.centerOf(s));
      await pumpEventQueue();
    }
  }

  test('Bull-Training: 30 Bullseyes bringen 3 Sterne, Bestwert und schalten die nächste frei', () async {
    final c = ChallengeCatalog.byId('c1-4')!;
    await controller().start(c);
    final run = container.read(challengeRunProvider)!;
    expect(run.ownsGame(container.read(activeGameProvider)), isTrue);

    await throwAt(Segment.bull, 30);
    await controller().pending;
    final outcome = container.read(challengeRunProvider)!.outcome!;
    expect(outcome.stars, 3);
    expect(outcome.score, 1500);
    expect(outcome.newBest, isTrue);
    expect(outcome.unlockedChallenge?.id, 'c1-5');

    final me = await ProfileRepository(db).resolve(null);
    final saved = (await ChallengeRepository(db).result(me, c.id))!;
    expect(saved.stars, 3);
    expect(saved.best, 1500);
  });

  test('vorzeitig beendet: keine Wertung, nichts gespeichert', () async {
    final c = ChallengeCatalog.byId('c1-3')!;
    await controller().start(c);
    await throwAt(Segment.triple(20), 3);
    await container.read(activeGameProvider.notifier).end();
    await pumpEventQueue();
    expect(container.read(challengeRunProvider)!.aborted, isTrue);
    expect(container.read(challengeRunProvider)!.outcome, isNull);
    final me = await ProfileRepository(db).resolve(null);
    expect(await ChallengeRepository(db).results(me), isEmpty);
  });

  test('Match-Challenge startet ein Match gegen den Computer', () async {
    final c = ChallengeCatalog.byId('c2-1')!;
    await controller().start(c);
    final state = container.read(matchControllerProvider)!;
    expect(container.read(challengeRunProvider)!.ownsMatch(state), isTrue);
    expect(state.setup.players.where((p) => p.isBot), hasLength(1));
    expect(state.setup.format.legsToWin, 2);
    await container.read(matchControllerProvider.notifier).close();
  });

  test('Tagesziel und Erfolge: Einblendung im Spiel, je Erfolg einmal, Stufen werden gespeichert', () async {
    // Erst den ersten (stillen) Lauf abwarten.
    await container.read(statsCalculatorProvider.future);
    await container.read(achievementRecorderProvider.notifier).pending;

    final batches = <CelebrationBatch>[];
    container.listen(celebrationsProvider, (_, next) {
      if (next != null) batches.add(next);
    });
    await controller().start(ChallengeCatalog.byId('c3-4')!); // 10 Aufnahmen Highscore
    await throwAt(Segment.triple(20), 30);
    await controller().pending;
    expect(container.read(challengeRunProvider)!.outcome!.stars, 3);

    final items = [for (final b in batches) ...b.items];
    expect(items.whereType<GoalCelebration>(), hasLength(1));
    final ids = [for (final c in items.whereType<AchievementCelebration>()) c.def.id];
    expect(ids, containsAll(['first_180', 'many_180', 'average']));
    expect(ids.toSet(), hasLength(ids.length));

    // Nach dem Speichern der Session landen die Stufen in der Datenbank.
    final me = await ProfileRepository(db).resolve(null);
    var keys = <String>{};
    for (var i = 0; i < 50 && !keys.contains('many_180#1'); i++) {
      await pumpEventQueue();
      await container.read(achievementRecorderProvider.notifier).pending;
      keys = {for (final r in await AchievementRepository(db).unlocks(me)) '${r.achievementId}#${r.tier}'};
    }
    expect(keys, containsAll(['first_180#1', 'many_180#1', 'average#3']));
    // Bereits eingeblendet: das Speichern bringt keine zweite Einblendung.
    final after = [for (final b in batches) ...b.items].whereType<AchievementCelebration>().length;
    expect(after, ids.length);
  });
}
