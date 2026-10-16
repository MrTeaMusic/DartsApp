import 'dart:convert';
import 'dart:io';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/backup/data/backup_service.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/history/data/history_repository.dart';
import 'package:dartlab/features/history/domain/session_history.dart';
import 'package:dartlab/features/matches/domain/match_result.dart';
import 'package:dartlab/features/sync/data/sync_client.dart';
import 'package:dartlab/features/sync/data/sync_server.dart';
import 'package:dartlab/features/sync/data/sync_store.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';
import '../../helpers/history_seed.dart';
import '../../helpers/online_seed.dart';
import '../../helpers/sync_device.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Device a;
  setUp(() => a = Device());
  tearDown(() => a.db.close());

  Future<SessionDetail> detail(Device dev, int id) async {
    final row = (await HistoryRepository(dev.db).session(id))!;
    return buildSessionDetail(row, await dev.games.throwsOf(id), playerName: 'Ich');
  }

  Future<int> x01(Device dev, List<List<String>> visits, {int start = 101}) async {
    final me = await dev.me();
    final sid = await dev.games.startSession(playerId: me, gameId: 'x01', config: {'startScore': start}, seed: 1);
    var seq = 0;
    for (final (v, names) in visits.indexed) {
      for (final n in names) {
        await dev.games.addThrow(sessionId: sid, playerId: me, gameId: 'x01', seq: seq++, visitIndex: v, counted: true, dart: d(n));
      }
    }
    await dev.games.endSession(sid, result: const GameResult(metrics: {'average': 50}, summary: []), finished: true);
    return sid;
  }

  Future<int> x01Session(Device dev) => x01(dev, [
        ['T20', 'T20', 'S1'],
      ]);

  test('X01-Training: Rest je Aufnahme, Bust und Darts aufs Finish', () async {
    final id = await x01(a, [
      ['T20', 'S1', 'S20'], // 81, Rest 20 (S20 auf Rest 40 = verfehltes D20)
      ['S20', 'MISS', 'MISS'], // auf Rest 20 ohne Double: Bust
      ['S2', 'D9'], // Rest 20 → 18 → Checkout
    ]);
    final dt = await detail(a, id);
    expect(dt.afterKey, 'remaining');
    expect(dt.legs.single.number, 0, reason: 'ein Leg braucht keine Überschrift');
    final v = dt.visits;
    expect(v, hasLength(3));
    expect(v[0].score, 81);
    expect(v[0].after, '20');
    expect(v[1].bust, isTrue);
    expect(v[1].score, 0);
    expect(v[1].after, '20');
    expect(v[1].darts.first.finishAttempt, isTrue, reason: 'Rest 20 = D10');
    expect(v[1].darts.first.hit, isFalse);
    expect(v[1].darts.skip(1).every((d) => !d.counted), isTrue);
    expect(v[2].checkout, isTrue);
    expect(v[2].darts.last.finishAttempt && v[2].darts.last.hit, isTrue);
    expect(dt.finishAttempts, 4);
    expect(dt.finishHits, 1);
    expect(dt.chart, VisitChart.score);
    expect(dt.summary.map((s) => s.key), contains('average'), reason: 'Zusammenfassung des Spiels');
  });

  test('Zielspiele: Marks (Cricket) bzw. Treffer statt Punkten je Aufnahme', () async {
    final me = await a.me();
    final cricket = await detail(a, await seedTraining(a.games, me, 'cricket', const {}, DateTime(2026, 10, 1, 18), seed: 6));
    expect(cricket.value, VisitValue.marks);
    expect(cricket.chart, VisitChart.marks);
    expect(cricket.visits.fold<int>(0, (s, v) => s + v.marks), cricket.entry.metrics['marks']);

    final atc = await detail(a,
        await seedTraining(a.games, me, 'around_the_clock', const {}, DateTime(2026, 10, 1, 19), seed: 7, stopAfter: 14));
    expect(atc.value, VisitValue.hits);
    expect(atc.chart, VisitChart.hits);
    expect(atc.entry.keyMetric, isNull, reason: 'abgebrochen: die Liste zeigt die Darts');

    final x01 = await detail(a, await seedTraining(a.games, me, 'x01', const {'startScore': 501}, DateTime(2026, 10, 1, 20)));
    expect(x01.value, VisitValue.points);
  });

  test('Match: Legs mit Sieger, Rest und Ergebnis des Gegners', () async {
    final id = await seedMatch(a.games, await a.me(), DateTime(2026, 10, 1, 19));
    final dt = await detail(a, id);
    expect(dt.entry.isMatch, isTrue);
    expect(dt.entry.won, isTrue);
    expect(dt.players.map((p) => p.name), ['Ich', 'Robo']);
    expect(dt.players[1].stats['average'], isNotNull);
    expect(dt.legs, hasLength(3));
    expect(dt.legs.where((l) => l.winner == 0), hasLength(2));
    expect(dt.legs.where((l) => l.winner == 1), hasLength(1));
    for (final leg in dt.legs.where((l) => l.winner == 0)) {
      expect(leg.visits.last.checkout, isTrue);
      expect(leg.visits.last.darts.where((d) => d.counted).last.hit, isTrue);
    }
    final lost = dt.legs.firstWhere((l) => l.winner == 1);
    expect(lost.visits.any((v) => v.checkout), isFalse);
    expect(lost.visits.first.number, 1);
    // Die Darts pro Leg passen zur gespeicherten Kennzahl.
    final countedDarts = dt.visits.expand((v) => v.darts).where((d) => d.counted).length;
    expect(countedDarts, dt.entry.metrics['darts']);
  });

  test('Online-Matches (Autodarts Live) stehen unter „Matches“, ohne Match-Detail', () async {
    final me = await a.me();
    final live = await seedOnlineMatch(a.games, me, DateTime(2026, 10, 2, 20), legs: 3, opponentMin: 9, opponentMax: 14);
    final raw = await seedOnlineMatch(a.games, me, DateTime(2026, 10, 2, 21), x01: false, legs: 1);
    final bot = await seedMatch(a.games, me, DateTime(2026, 10, 1, 19));
    final x01 = await x01Session(a);
    final entries = {for (final id in [live, raw, bot, x01]) id: (await detail(a, id)).entry};

    expect(entries[live]!.isOnline, isTrue);
    expect(entries[live]!.isMatch, isFalse);
    expect(entries[live]!.hasLiveLegs, isTrue);
    expect(entries[raw]!.hasLiveLegs, isFalse);
    expect([for (final e in entries.entries) if (e.value.matches(HistoryFilter.matches)) e.key], [live, raw, bot]);
    expect([for (final e in entries.entries) if (e.value.matches(HistoryFilter.training)) e.key], [x01]);
    // Bot-Match behält die Match-Detailansicht, Live-Sessions nicht.
    expect((await detail(a, bot)).players, hasLength(2));
    expect((await detail(a, live)).players, isEmpty);
  });

  test('ältere Matches ohne Leg-Angaben', () async {
    final me = await a.me();
    Future<int> old(Map<String, num> metrics, List<List<String>> visits) async {
      final sid = await a.games.startSession(
          playerId: me, gameId: matchGameId, config: const {'startScore': 101, 'opponents': ['CPU'], 'vsBot': true}, seed: 0);
      var seq = 0;
      for (final (v, names) in visits.indexed) {
        for (final n in names) {
          await a.games.addThrow(sessionId: sid, playerId: me, gameId: matchGameId, seq: seq++, visitIndex: v * 2, counted: true, dart: d(n));
        }
      }
      await a.games.endSession(sid, result: GameResult(metrics: metrics, summary: const []), finished: true);
      return sid;
    }

    // Alle Legs gewonnen: jedes endet mit dem eigenen Checkout.
    final won = await detail(a, await old({'won': 1, 'legsWon': 2, 'legsLost': 0, 'darts': 12}, [
      ['T20', 'S1', 'D20'],
      ['T20', 'S1', 'D20'],
    ]));
    expect(won.legsKnown, isTrue);
    expect(won.legs, hasLength(2));
    expect(won.players.map((p) => p.name), ['Ich', 'CPU']);
    expect(won.players[1].stats, isEmpty, reason: 'keine erfundenen Gegnerwerte');

    // Ein Leg verloren: ohne Leg-Grenzen keine Reste.
    final lost = await detail(a, await old({'won': 0, 'legsWon': 0, 'legsLost': 1}, [
      ['S20', 'S20', 'S20'],
    ]));
    expect(lost.legsKnown, isFalse);
    expect(lost.afterKey, isNull);
    expect(lost.visits.single.score, 60);
  });

  test('Löschen: Würfe weg, Markierung bleibt, Statistik und Verlauf ohne sie', () async {
    final me = await a.me();
    final keep = await x01(a, [['T20', 'T20', 'T20']], start: 501);
    final gone = await x01(a, [['S1', 'S1', 'S1']], start: 501);
    await a.games.deleteSession(gone);

    expect((await a.db.select(a.db.throws).get()).map((t) => t.sessionId).toSet(), {keep});
    final row = await (a.db.select(a.db.sessions)..where((s) => s.id.equals(gone))).getSingle();
    expect(row.deletedAt, isNotNull);
    expect(await HistoryRepository(a.db).session(gone), isNull);
    expect((await HistoryRepository(a.db).watchSessions(me).first).map((s) => s.id), [keep]);
    final calc = await a.stats.watchCalculator(me).first;
    expect(calc.sessions.map((s) => s.id), [keep]);
    expect((await a.games.watchRecent(playerId: me).first).map((s) => s.id), [keep]);
  });

  group('Abgleich', () {
    late Device b;
    setUp(() => b = Device());
    tearDown(() => b.db.close());

    Future<void> sync(Device x, Device y) async {
      await y.store.merge(await x.store.bundle());
      await x.store.merge(await y.store.bundle());
    }

    Future<List<SessionRow>> alive(Device dev) => (dev.db.select(dev.db.sessions)..where((s) => s.deletedAt.isNull())).get();

    test('gelöschte Session verschwindet auf dem anderen Gerät und kommt nicht zurück', () async {
      final uid = await a.play(await a.me(), minute: 1);
      await a.play(await a.me(), minute: 2);
      await sync(a, b);
      expect(await alive(b), hasLength(2));

      final id = (await (a.db.select(a.db.sessions)..where((s) => s.uid.equals(uid))).getSingle()).id;
      final before = await a.store.signature();
      await a.games.deleteSession(id);
      expect(await a.store.signature(), isNot(before), reason: 'löst einen Abgleich aus');

      await sync(a, b);
      await sync(a, b);
      for (final dev in [a, b]) {
        expect((await alive(dev)).map((s) => s.uid), isNot(contains(uid)));
        expect(await dev.db.select(dev.db.throws).get(), hasLength(3));
      }
      // Ein drittes Gerät mit der alten Session bekommt die Markierung.
      final c = Device();
      addTearDown(c.db.close);
      final copy = (await a.store.bundle()).toJson();
      expect((copy['deletedSessions'] as List).single['uid'], uid);
      await c.store.merge(SyncBundle.fromJson(jsonDecode(jsonEncode(copy)) as Map<String, Object?>));
      expect((await alive(c)).map((s) => s.uid), isNot(contains(uid)));
    });

    test('Löschen über das Netzwerk: Hub und zweiter Client', () async {
      final hub = Device();
      final ipad = Device();
      addTearDown(hub.db.close);
      addTearDown(ipad.db.close);
      final server = SyncServer(hub.store, key: '123456');
      await server.start(port: 0, address: InternetAddress.loopbackIPv4);
      addTearDown(server.dispose);
      SyncClient client(Device dev) => SyncClient(dev.store, host: '127.0.0.1', port: server.port!, key: '123456');

      final uid = await a.play(await a.me(), minute: 1);
      await client(a).sync();
      await client(ipad).sync();
      expect(await alive(ipad), hasLength(1));

      await a.games.deleteSession((await alive(a)).single.id);
      final r = await client(a).sync();
      expect(r.remote.updated, greaterThan(0));
      await client(ipad).sync();
      for (final dev in [a, hub, ipad]) {
        expect(await alive(dev), isEmpty, reason: 'gelöscht überall');
      }
      // Nichts kommt zurück, nichts wird mehr geschickt.
      final again = await client(ipad).sync();
      expect(again.sent + again.received, 0);
      expect(await alive(hub), isEmpty);
      expect((await hub.db.select(hub.db.sessions).get()).single.uid, uid);

      // Vor dem ersten Abgleich gelöscht: der Hub merkt sich nur die Markierung.
      await a.play(await a.me(), minute: 5);
      await a.games.deleteSession((await alive(a)).single.id);
      await client(a).sync();
      expect(await alive(hub), isEmpty);
      expect(await hub.db.select(hub.db.sessions).get(), hasLength(2));
      final last = await client(a).sync();
      expect(last.sent + last.received, 0);
    });

    test('Sicherung enthält gelöschte Sessions als Markierung', () async {
      final uid = await a.play(await a.me(), minute: 1);
      await sync(a, b);
      await a.games.deleteSession((await alive(a)).single.id);
      final json = await BackupService(a.db).exportJson();
      final data = jsonDecode(json) as Map<String, Object?>;
      expect(data['version'], 5);
      expect(data['sessions'], isEmpty);
      expect((data['deletedSessions'] as List).single['uid'], uid);
      await BackupService(b.db).importJson(json);
      expect(await alive(b), isEmpty);
    });
  });

  test('Migration von Version 5 ergänzt die Löschmarkierung, wiederholbar', () async {
    final dir = Directory.systemTemp.createTempSync('dartlab_v5');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final v5 = AppDatabase(NativeDatabase(file));
    final dev = await v5.select(v5.players).get();
    expect(dev, hasLength(1));
    await v5.customStatement('ALTER TABLE sessions DROP COLUMN deleted_at');
    await v5.customStatement('PRAGMA user_version = 5');
    await v5.close();

    final v6 = AppDatabase(NativeDatabase(file));
    final cols = await v6.customSelect('PRAGMA table_info(sessions)').get();
    expect(cols.map((r) => r.read<String>('name')), contains('deleted_at'));
    await v6.customStatement('PRAGMA user_version = 5');
    await v6.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect((await again.customSelect('PRAGMA user_version').getSingle()).data.values.single, 7);
  });
}
