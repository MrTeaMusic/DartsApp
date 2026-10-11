import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_training.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

void main() {
  late AppDatabase db;
  late GameRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = GameRepository(db);
  });
  tearDown(() => db.close());

  test('Standardprofil "Ich" wird beim Anlegen erzeugt', () async {
    final id = await repo.defaultPlayerId();
    final players = await db.select(db.players).get();
    expect(players.single.id, id);
    expect(players.single.name, 'Ich');
    expect(players.single.isDefault, isTrue);
  });

  test('Session mit Würfen speichern und abschließen', () async {
    final player = await repo.defaultPlayerId();
    final sid = await repo.startSession(playerId: player, gameId: 'highscore_hunt', config: const {'visits': 1}, seed: 3);
    for (final (i, n) in ['T20', 'S5', 'MISS'].indexed) {
      await repo.addThrow(sessionId: sid, playerId: player, gameId: 'highscore_hunt', seq: i, visitIndex: 0, counted: true, dart: d(n));
    }
    await repo.endSession(sid, result: const GameResult(metrics: {'points': 65, 'average': 65}, summary: []), finished: true);

    final throws = await repo.throwsOf(sid);
    expect(throws.map((t) => t.segment), ['T20', 'S5', 'MISS']);
    expect(throws.first.score, 60);
    expect(throws.first.multiplier, 3);
    expect(throws.first.bed, 'triple');

    final recent = await repo.watchRecent().first;
    expect(recent.single.dartCount, 3);
    expect(recent.single.metrics['points'], 65);
    expect(await repo.bestMetric('highscore_hunt', 'points'), 65);
  });

  test('Session ohne Würfe wird beim Beenden gelöscht', () async {
    final player = await repo.defaultPlayerId();
    final sid = await repo.startSession(playerId: player, gameId: 'checkout', config: const {}, seed: 1);
    await repo.endSession(sid, result: const GameResult(metrics: {}, summary: []), finished: false);
    expect(await db.select(db.sessions).get(), isEmpty);
  });

  test('replaceThrows ersetzt alle Würfe einer Session', () async {
    final player = await repo.defaultPlayerId();
    final sid = await repo.startSession(playerId: player, gameId: 'x', config: const {}, seed: 1);
    await repo.addThrow(sessionId: sid, playerId: player, gameId: 'x', seq: 0, visitIndex: 0, counted: true, dart: d('S1'));
    await repo.replaceThrows(sessionId: sid, playerId: player, gameId: 'x', darts: [
      (dart: d('D20'), visitIndex: 0, counted: true),
      (dart: d('S3'), visitIndex: 0, counted: false),
    ]);
    final throws = await repo.throwsOf(sid);
    expect(throws.map((t) => (t.segment, t.seq, t.counted)), [('D20', 0, true), ('S3', 1, false)]);
  });

  test('schwache Checkout-Werte aus früheren Versuchen', () async {
    final player = await repo.defaultPlayerId();
    Future<void> session(List<CheckoutAttempt> attempts) async {
      final sid = await repo.startSession(playerId: player, gameId: CheckoutTraining.id, config: const {}, seed: 1);
      await repo.addThrow(sessionId: sid, playerId: player, gameId: CheckoutTraining.id, seq: 0, visitIndex: 0, counted: true, dart: d('S1'));
      await repo.endSession(
        sid,
        result: GameResult(metrics: const {}, summary: const [], details: {'attempts': [for (final a in attempts) a.toJson()]}),
        finished: true,
      );
    }

    await session(const [
      CheckoutAttempt(target: 40, success: true, darts: 1),
      CheckoutAttempt(target: 40, success: true, darts: 2),
      CheckoutAttempt(target: 87, success: false, darts: 3),
      CheckoutAttempt(target: 61, success: true, darts: 3),
    ]);
    await session(const [
      CheckoutAttempt(target: 87, success: false, darts: 3),
      CheckoutAttempt(target: 61, success: false, darts: 3),
      CheckoutAttempt(target: 120, success: false, darts: 3),
    ]);
    // 120 hat nur einen Versuch und fällt raus.
    expect(await repo.weakCheckoutTargets(), [87, 61, 40]);
    expect(await repo.weakCheckoutTargets(limit: 1), [87]);
  });
}
