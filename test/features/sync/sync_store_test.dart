import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/backup/data/backup_service.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/stats/data/stats_repository.dart';
import 'package:dartlab/features/stats/domain/goals.dart';
import 'package:dartlab/features/sync/data/sync_store.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

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

/// Beide Richtungen, wie ein vollständiger Abgleich.
Future<void> sync(Device a, Device b) async {
  await b.store.merge(await a.store.bundle());
  await a.store.merge(await b.store.bundle());
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Device a;
  late Device b;
  setUp(() {
    a = Device();
    b = Device();
  });
  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  test('Sessions beider Geräte landen überall, „Ich“ ist dasselbe Profil', () async {
    await a.play(await a.me(), minute: 1);
    await a.play(await a.me(), minute: 2);
    await b.play(await b.me(), minute: 3);

    await sync(a, b);
    for (final dev in [a, b]) {
      expect((await dev.active()).map((p) => p.name), ['Ich']);
      expect(await dev.sessions(), hasLength(3));
      expect(await dev.db.select(dev.db.throws).get(), hasLength(9));
    }
    expect((await a.sessions()).map((s) => s.uid).toSet(), (await b.sessions()).map((s) => s.uid).toSet());

    // Ein zweiter Abgleich ändert nichts.
    final again = await b.store.merge(await a.store.bundle());
    expect(again.changedAnything, isFalse);
    expect(again.skipped, 3);
  });

  test('laufende Sessions werden nicht abgeglichen', () async {
    await a.play(await a.me(), minute: 1, end: false);
    await sync(a, b);
    expect(await b.sessions(), isEmpty);
  });

  test('gleich benanntes Profil auf zwei Geräten wird eins', () async {
    final la = await a.profiles.create('Lisa');
    final lb = await b.profiles.create('Lisa');
    await a.play(la, minute: 1);
    await b.play(lb, minute: 2);

    await sync(a, b);
    await sync(a, b);
    final pa = (await a.active()).firstWhere((p) => p.name == 'Lisa');
    final pb = (await b.active()).firstWhere((p) => p.name == 'Lisa');
    expect(pa.uid, pb.uid);
    expect((await a.active()).length, 2);
    expect((await a.sessions()).where((s) => s.playerId == pa.id), hasLength(2));
    expect((await b.sessions()).where((s) => s.playerId == pb.id), hasLength(2));
  });

  test('Umbenennen: die neuere Änderung gewinnt', () async {
    await a.profiles.create('Lisa');
    await sync(a, b);
    final lisaA = (await a.active()).firstWhere((p) => p.name == 'Lisa');
    final lisaB = (await b.active()).firstWhere((p) => p.name == 'Lisa');
    await (a.db.update(a.db.players)..where((p) => p.id.equals(lisaA.id)))
        .write(PlayersCompanion(name: const Value('Lisa M.'), updatedAt: Value(DateTime(2026, 10, 2))));
    await (b.db.update(b.db.players)..where((p) => p.id.equals(lisaB.id)))
        .write(PlayersCompanion(name: const Value('Lisa Alt'), updatedAt: Value(DateTime(2026, 10, 1))));

    await sync(a, b);
    expect((await a.active()).map((p) => p.name), contains('Lisa M.'));
    expect((await b.active()).map((p) => p.name), contains('Lisa M.'));
  });

  test('Löschen eines Profils kommt auf dem anderen Gerät an, samt Sessions', () async {
    final lisa = await a.profiles.create('Lisa');
    await a.play(lisa, minute: 1);
    await sync(a, b);
    expect(await b.sessions(), hasLength(1));

    expect(await a.profiles.delete(lisa, at: DateTime.now().add(const Duration(seconds: 5))), isTrue);
    await sync(a, b);
    expect((await b.active()).map((p) => p.name), ['Ich']);
    expect(await b.sessions(), isEmpty);
    // Und sie kommen auch nicht über einen dritten Weg zurück.
    final c = Device();
    addTearDown(c.db.close);
    await sync(b, c);
    expect((await c.active()).map((p) => p.name), ['Ich']);
  });

  test('Ziele: neuere Änderung gewinnt, Löschen wird weitergegeben', () async {
    final meA = await a.me();
    final meB = await b.me();
    await a.stats.addGoal(meA, GoalKind.weeklyDarts, 500);
    await b.stats.addGoal(meB, GoalKind.weeklyDarts, 300);
    await (b.db.update(b.db.goals)).write(GoalsCompanion(updatedAt: Value(DateTime.now().add(const Duration(minutes: 1)))));

    await sync(a, b);
    await sync(a, b);
    final ga = await a.db.select(a.db.goals).get();
    final gb = await b.db.select(b.db.goals).get();
    expect(ga.single.target, 300);
    expect(gb.single.target, 300);
    expect(ga.single.uid, gb.single.uid);

    await b.stats.deleteGoal(gb.single.id);
    await (b.db.update(b.db.goals)).write(GoalsCompanion(updatedAt: Value(DateTime.now().add(const Duration(minutes: 2)))));
    await sync(a, b);
    expect((await a.db.select(a.db.goals).get()).single.deletedAt, isNotNull);
  });

  test('Manifest nennt nur abgeschlossene Sessions, Paket liefert gezielt', () async {
    final done = await a.play(await a.me(), minute: 1);
    await a.play(await a.me(), minute: 2, end: false);
    final m = await a.store.manifest();
    expect(m.sessionUids, {done});
    expect(m.players.single['uid'], defaultPlayerUid);
    final bundle = await a.store.bundle(sessionUids: {done});
    expect(bundle.sessions.single['uid'], done);
    expect(bundle.throws, hasLength(3));
    expect((await a.store.bundle(sessionUids: const {})).sessions, isEmpty);
    // Über JSON hin und zurück.
    final copy = SyncBundle.fromJson(jsonDecode(jsonEncode(bundle.toJson())) as Map<String, Object?>);
    expect((await b.store.merge(copy)).sessions, 1);
  });

  test('altes Backup (Version 1) lässt sich weiter importieren', () async {
    final v1 = {
      'format': 'dartlab-backup',
      'version': 1,
      'players': [
        {'id': 1, 'name': 'Ich', 'isDefault': true, 'createdAt': 1759300000000},
        {'id': 2, 'name': 'Gast', 'isDefault': false, 'createdAt': 1759300000000},
      ],
      'sessions': [
        {
          'id': 7,
          'playerId': 2,
          'gameId': 'checkout',
          'configJson': '{}',
          'seed': 3,
          'startedAt': 1759300100000,
          'endedAt': 1759300200000,
          'finished': true,
          'resultJson': null,
          'dartCount': 1,
        },
      ],
      'throws': [
        {
          'id': 1,
          'sessionId': 7,
          'playerId': 2,
          'gameId': 'checkout',
          'seq': 0,
          'visitIndex': 0,
          'counted': true,
          'segment': 'D20',
          'number': 20,
          'multiplier': 2,
          'bed': 'double',
          'score': 40,
          'x': null,
          'y': null,
          'source': 'manual',
          'timestamp': 1759300150000,
          'rawJson': null,
        },
      ],
      'goals': [
        {'id': 1, 'playerId': 2, 'kind': 'weeklySessions', 'target': 3.0, 'createdAt': 1759300000000},
      ],
    };
    final backup = BackupService(a.db);
    final r = await backup.importJson(jsonEncode(v1));
    expect(r.players, 1);
    expect(r.sessions, 1);
    expect(r.throws, 1);
    expect(r.goals, 1);
    expect((await backup.importJson(jsonEncode(v1))).skipped, 1);
    final gast = (await a.active()).firstWhere((p) => p.name == 'Gast');
    expect(gast.uid, hasLength(32));
  });
}
