import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/stats/data/stats_repository.dart';
import 'package:dartlab/features/sync/data/sync_store.dart';
import 'package:drift/native.dart';

import 'darts.dart';

/// Ein Gerät mit eigener Datenbank.
class Device {
  Device() : db = AppDatabase(NativeDatabase.memory());
  final AppDatabase db;
  late final profiles = ProfileRepository(db);
  late final games = GameRepository(db);
  late final stats = StatsRepository(db);
  late final store = SyncStore(db);

  Future<int> me() => profiles.resolve(null);

  Future<String> play(int player, {int minute = 0, bool end = true}) async {
    final sid = await games.startSession(
      playerId: player,
      gameId: 'highscore_hunt',
      config: const {'visits': 1},
      seed: minute,
      startedAt: DateTime(2026, 10, 1, 12, minute),
    );
    for (final (i, n) in ['T20', 'S5', 'MISS'].indexed) {
      await games.addThrow(sessionId: sid, playerId: player, gameId: 'highscore_hunt', seq: i, visitIndex: 0, counted: true, dart: d(n));
    }
    if (end) {
      await games.endSession(sid, result: const GameResult(metrics: {'points': 65}, summary: []), finished: true);
    }
    return (await (db.select(db.sessions)..where((s) => s.id.equals(sid))).getSingle()).uid;
  }

  Future<List<Player>> active() => profiles.players();
  Future<List<SessionRow>> sessions() => db.select(db.sessions).get();
}

