import 'dart:convert';
import 'dart:io';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/backup/data/backup_service.dart';
import 'package:dartlab/features/autodarts_live/domain/live_stats.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/progress/domain/daily_goal.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:dartlab/features/sync/data/sync_client.dart';
import 'package:dartlab/features/sync/data/sync_server.dart';
import 'package:dartlab/features/sync/data/sync_store.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sync_device.dart';

/// Live-Sessions (Autodarts-Modus) wachsen nach dem ersten Zwischenspeichern
/// weiter: Der Abgleich muss die späteren Darts und Korrekturen nachtragen.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Device hub;
  late Device phone;
  late SyncServer server;

  setUp(() async {
    hub = Device();
    phone = Device();
    server = SyncServer(hub.store, key: '123456');
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  });
  tearDown(() async {
    await server.dispose();
    await hub.db.close();
    await phone.db.close();
  });

  SyncClient client(Device d, {int chunk = 25}) =>
      SyncClient(d.store, host: '127.0.0.1', port: server.port!, key: '123456', chunk: chunk);

  final day = DateTime(2026, 10, 12, 20);
  const names = ['T20', 'T20', 'S5', 'T19', 'S19', 'S3', 'D20', 'S1', 'T20'];
  DartThrow dart(int i) => DartThrow(
        segment: Segment.tryParse(names[i % names.length])!,
        timestamp: day.add(Duration(seconds: 10 * i)),
        source: DartSourceKind.autodartsLocal,
      );

  Future<int> start(Device dev, int player, {String gameId = autodartsLiveGameId}) => dev.games.startSession(
        playerId: player,
        gameId: gameId,
        config: const {'mode': 'listen'},
        seed: 0,
        startedAt: day,
      );

  Future<void> add(Device dev, int sid, int player, int from, int to) async {
    for (var i = from; i < to; i++) {
      await dev.games.addThrow(
        sessionId: sid,
        playerId: player,
        gameId: autodartsLiveGameId,
        seq: i,
        visitIndex: i ~/ 3,
        counted: true,
        dart: dart(i),
      );
    }
  }

  /// Zwischenspeichern wie der Live-Modus: Ende = letzter Dart.
  Future<void> checkpoint(Device dev, int sid, int darts) => dev.games.endSession(
        sid,
        result: GameResult(metrics: {'darts': darts.toDouble()}, summary: const []),
        finished: true,
        endedAt: dart(darts - 1).timestamp,
      );

  Future<void> rewrite(Device dev, int sid, int player, List<int> keep) => dev.games.replaceThrows(
        sessionId: sid,
        playerId: player,
        gameId: autodartsLiveGameId,
        darts: [for (final (n, i) in keep.indexed) (dart: dart(i), visitIndex: n ~/ 3, counted: true)],
      );

  Future<List<String>> segments(Device dev) async {
    final rows = await dev.games.throwsOf((await dev.sessions()).single.id);
    return [for (final t in rows) '${t.seq}:${t.segment}:${t.timestamp.millisecondsSinceEpoch}'];
  }

  Future<int> dartsOfDay(Device dev) async {
    final calc = StatsCalculator(sessions: await dev.sessions(), throws: await dev.db.select(dev.db.throws).get());
    return dailyActivity(calc)[StatsCalculator.dayOf(day)]?.darts ?? 0;
  }

  test('Phone nimmt auf: spätere Darts und Korrekturen kommen am Hub an', () async {
    final me = await phone.me();
    final sid = await start(phone, me);
    await add(phone, sid, me, 0, 3);
    await checkpoint(phone, sid, 3);
    await client(phone).sync();
    expect(await hub.db.select(hub.db.throws).get(), hasLength(3));

    // Die Session wächst weiter, dazwischen eine Korrektur, dann Zwischenspeichern.
    await add(phone, sid, me, 3, 40);
    await checkpoint(phone, sid, 40);
    final r = await client(phone).sync();
    expect(r.sent, 1);
    expect(await hub.sessions(), hasLength(1));
    expect(await hub.db.select(hub.db.throws).get(), hasLength(40));

    await rewrite(phone, sid, me, [for (var i = 0; i < 41; i++) if (i != 7) i]);
    await checkpoint(phone, sid, 40);
    await client(phone).sync();

    expect(await segments(hub), await segments(phone));
    final h = (await hub.sessions()).single;
    final p = (await phone.sessions()).single;
    expect(h.uid, p.uid);
    expect(h.dartCount, p.dartCount);
    expect(h.endedAt, p.endedAt);
    expect(h.resultJson, p.resultJson);
    expect(await dartsOfDay(hub), 40);
    expect(await dartsOfDay(hub), await dartsOfDay(phone));

    // Danach ist alles gleich: nichts mehr zu tun.
    final again = await client(phone).sync();
    expect(again.sent + again.received, 0);
  });

  test('Hub nimmt auf (PC am Board): der Client holt spätere Darts nach', () async {
    final me = await hub.me();
    final sid = await start(hub, me, gameId: autodartsLiveX01GameId);
    await add(hub, sid, me, 0, 3);
    await checkpoint(hub, sid, 3);
    await client(phone).sync();
    expect(await phone.db.select(phone.db.throws).get(), hasLength(3));

    await add(hub, sid, me, 3, 25);
    await checkpoint(hub, sid, 25);
    final r = await client(phone).sync();
    expect(r.received, 1);
    expect(await segments(phone), await segments(hub));
    expect((await phone.sessions()).single.dartCount, 25);
    expect(await dartsOfDay(phone), 25);
    expect(await dartsOfDay(phone), await dartsOfDay(hub));
  });

  /// Zustand vor dem Stand: Hub mit abgeschnittener Kopie und ohne `updatedAt`.
  Future<void> truncatedOnHub({required DateTime hubEnd, required DateTime clientEnd, bool clientStamp = true}) async {
    final p = await phone.me();
    final sid = await start(phone, p);
    await add(phone, sid, p, 0, 40);
    await checkpoint(phone, sid, 40);
    await phone.db.customStatement(
      'UPDATE sessions SET ended_at = ?, updated_at = ?',
      [clientEnd.millisecondsSinceEpoch ~/ 1000, clientStamp ? clientEnd.millisecondsSinceEpoch ~/ 1000 : null],
    );

    // Der Hub bekommt zuerst nur die ersten drei Darts (wie beim ersten Zwischenspeichern).
    final first = await phone.store.bundle();
    final uid = (await phone.sessions()).single.uid;
    final cut = SyncBundle.fromJson({
      ...first.toJson(),
      'sessions': [
        for (final s in first.sessions)
          {...s, 'updatedAt': null, 'dartCount': 3, 'endedAt': hubEnd.toUtc().toIso8601String()},
      ],
      'throws': [for (final t in first.throws) if ((t['seq'] as int) < 3) t],
    });
    expect((await hub.store.merge(cut)).sessions, 1);
    final h = (await hub.sessions()).single;
    expect(h.uid, uid);
    expect(h.updatedAt, isNull);
    expect(await hub.db.select(hub.db.throws).get(), hasLength(3));
  }

  test('Altbestand: abgeschnittene Kopie ohne Stand wird durch die vollständige ersetzt', () async {
    await truncatedOnHub(hubEnd: day.add(const Duration(seconds: 20)), clientEnd: day.add(const Duration(minutes: 7)));
    final r = await client(phone).sync();
    expect(r.sent, 1);
    expect(await segments(hub), await segments(phone));
    expect((await hub.sessions()).single.dartCount, 40);
    expect(await dartsOfDay(hub), 40);
    expect((await client(phone).sync()).sent, 0);
  });

  test('Altbestand: gleiches Ende, beide ohne Stand: mehr Darts gewinnt (nur Live)', () async {
    final end = day.add(const Duration(seconds: 20));
    await truncatedOnHub(hubEnd: end, clientEnd: end, clientStamp: false);
    await phone.db.customStatement('UPDATE sessions SET updated_at = NULL');
    final r = await client(phone).sync();
    expect(r.sent, 1);
    expect(await segments(hub), await segments(phone));
    expect((await client(phone).sync()).sent, 0);
  });

  test('Altbestand: Hub kopiert (Stand aus Migration) hat gleiches Ende wie der Client', () async {
    final end = day.add(const Duration(seconds: 20));
    await truncatedOnHub(hubEnd: end, clientEnd: end);
    // Wie nach der Migration: Stand = Ende auf beiden Seiten.
    await hub.db.customStatement('UPDATE sessions SET updated_at = ended_at');
    await client(phone).sync();
    expect(await segments(hub), await segments(phone));
  });

  test('Altbestand: in der Gegenrichtung holt der Client die vollständige Kopie vom Hub', () async {
    final p = await hub.me();
    final sid = await start(hub, p);
    await add(hub, sid, p, 0, 40);
    await checkpoint(hub, sid, 40);
    await client(phone).sync();
    // Der Client hat nur eine alte, abgeschnittene Kopie ohne Stand.
    final uid = (await phone.sessions()).single.uid;
    await phone.db.customStatement('DELETE FROM throws WHERE seq >= 3');
    await phone.db.customStatement('UPDATE sessions SET dart_count = 3, updated_at = NULL');
    final r = await client(phone).sync();
    expect(r.received, 1);
    expect((await phone.sessions()).single.uid, uid);
    expect(await segments(phone), await segments(hub));
  });

  test('Stand: gleicher Stand behält die vorhandene, ältere Pakete ersetzen nichts', () async {
    final me = await phone.me();
    final sid = await start(phone, me);
    await add(phone, sid, me, 0, 6);
    await checkpoint(phone, sid, 6);
    final old = await phone.store.bundle();
    await hub.store.merge(old);
    await add(phone, sid, me, 6, 9);
    await checkpoint(phone, sid, 9);

    final newer = await phone.store.bundle();
    final r1 = await hub.store.merge(newer);
    expect((r1.updated, r1.sessions), (1, 0));
    expect(await hub.db.select(hub.db.throws).get(), hasLength(9));
    // Dasselbe Paket noch einmal und das ältere danach: nichts ändert sich.
    expect((await hub.store.merge(newer)).changedAnything, isFalse);
    expect((await hub.store.merge(old)).changedAnything, isFalse);
    expect(await hub.db.select(hub.db.throws).get(), hasLength(9));
  });

  test('Stand wächst bei jedem Schreiben um mindestens eine Sekunde, auch in derselben Sekunde', () async {
    final me = await phone.me();
    final sid = await start(phone, me);
    await add(phone, sid, me, 0, 3);
    expect((await phone.sessions()).single.updatedAt, isNull, reason: 'offene Sessions haben noch keinen Stand');
    await checkpoint(phone, sid, 3);
    var last = (await phone.sessions()).single.updatedAt!;
    for (var i = 3; i < 8; i++) {
      await add(phone, sid, me, i, i + 1);
      final now = (await phone.sessions()).single.updatedAt!;
      expect(now.isAfter(last), isTrue);
      last = now;
    }
    await checkpoint(phone, sid, 8);
    expect((await phone.sessions()).single.updatedAt!.isAfter(last), isTrue);
  });

  test('Fingerabdruck ändert sich, wenn Darts zu einer abgeschlossenen Session kommen', () async {
    final me = await phone.me();
    final sid = await start(phone, me);
    await add(phone, sid, me, 0, 3);
    await checkpoint(phone, sid, 3);
    final before = await phone.store.signature();
    await add(phone, sid, me, 3, 4);
    expect(await phone.store.signature(), isNot(before));
    final mid = await phone.store.signature();
    await rewrite(phone, sid, me, [0, 1, 2]);
    expect(await phone.store.signature(), isNot(mid));
  });

  test('Manifest: Stände nur mit Wert, Live-Darts nur für Live-Sessions; JSON-Rundlauf', () async {
    final me = await phone.me();
    final live = await start(phone, me);
    await add(phone, live, me, 0, 4);
    await checkpoint(phone, live, 4);
    final normal = await phone.play(me, minute: 5);
    final m = await phone.store.manifest();
    final liveUid = (await phone.sessions()).firstWhere((s) => s.gameId == autodartsLiveGameId).uid;
    expect(m.sessionRevisions!.keys, {liveUid, normal});
    expect(m.liveDarts, {liveUid: 4});
    final copy = SyncManifest.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, Object?>);
    expect(copy.sessionRevisions, m.sessionRevisions);
    expect(copy.liveDarts, m.liveDarts);
    expect(copy.sessionUids, m.sessionUids);
  });

  test('Ältere Geräte: Manifest ohne Stände ändert nichts, Pakete ohne Stand verhalten sich wie früher', () async {
    final me = await phone.me();
    final sid = await start(phone, me);
    await add(phone, sid, me, 0, 3);
    await checkpoint(phone, sid, 3);
    await client(phone).sync();

    // Manifest eines alten Hubs: kein `sessionRevisions`.
    final json = (await hub.store.manifest()).toJson()..remove('sessionRevisions')..remove('sessionDarts');
    final old = SyncManifest.fromJson(json);
    expect(old.sessionRevisions, isNull);
    await add(phone, sid, me, 3, 9);
    await checkpoint(phone, sid, 9);
    expect((await phone.store.manifest()).newerThan(old), isEmpty);
    expect(old.newerThan(await phone.store.manifest()), isEmpty);

    // Paket eines alten Geräts (ohne `updatedAt`, fremde Felder werden ignoriert).
    final b = (await phone.store.bundle()).toJson();
    final legacy = SyncBundle.fromJson({
      ...b,
      'zukunft': 1,
      'sessions': [for (final s in (b['sessions'] as List)) {...(s as Map<String, Object?>)..remove('updatedAt'), 'neu': true}],
    });
    final r = await hub.store.merge(legacy);
    expect(r.updated, 0);
    expect(r.skipped, 1);
    expect(await hub.db.select(hub.db.throws).get(), hasLength(3));
  });

  test('Gelöscht gewinnt: eine geänderte Session kehrt nicht zurück', () async {
    final me = await phone.me();
    final sid = await start(phone, me);
    await add(phone, sid, me, 0, 3);
    await checkpoint(phone, sid, 3);
    await client(phone).sync();
    await hub.games.deleteSession((await hub.sessions()).single.id);

    await add(phone, sid, me, 3, 9);
    await checkpoint(phone, sid, 9);
    final r = await client(phone).sync();
    expect(r.sent, 0);
    expect((await phone.sessions()).single.deletedAt, isNotNull);
    expect(await hub.db.select(hub.db.throws).get(), isEmpty);
    expect((await hub.sessions()).single.deletedAt, isNotNull);
  });

  test('Gewöhnliche Sessions werden nach dem Abschluss nicht erneut übertragen', () async {
    await phone.play(await phone.me(), minute: 1);
    await hub.play(await hub.me(), minute: 2);
    await client(phone).sync();
    final again = await client(phone).sync();
    expect(again.sent + again.received, 0);
    expect(again.local.changedAnything || again.remote.changedAnything, isFalse);
  });

  test('Sicherung (Version 5) enthält den Stand, alte Dateien ohne Stand lassen sich importieren', () async {
    final me = await phone.me();
    final sid = await start(phone, me);
    await add(phone, sid, me, 0, 5);
    await checkpoint(phone, sid, 5);
    final json = await BackupService(phone.db).exportJson();
    final data = jsonDecode(json) as Map<String, Object?>;
    expect(data['version'], 5);
    expect(((data['sessions'] as List).single as Map)['updatedAt'], isNotNull);
    await BackupService(hub.db).importJson(json);
    expect((await hub.sessions()).single.updatedAt, (await phone.sessions()).single.updatedAt);

    for (final s in data['sessions'] as List) {
      (s as Map<String, Object?>).remove('updatedAt');
    }
    final fresh = Device();
    addTearDown(fresh.db.close);
    await BackupService(fresh.db).importJson(jsonEncode(data));
    expect((await fresh.sessions()).single.updatedAt, isNull);
    expect(await fresh.db.select(fresh.db.throws).get(), hasLength(5));
  });

  test('Migration von Version 6 ergänzt den Stand aus dem Ende, wiederholbar', () async {
    final dir = Directory.systemTemp.createTempSync('dartlab_v6');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final v6 = AppDatabase(NativeDatabase(file));
    final me = (await v6.select(v6.players).get()).single.id;
    final at = DateTime(2026, 10, 1, 12);
    await v6.into(v6.sessions).insert(SessionsCompanion.insert(
        playerId: me, gameId: 'highscore_hunt', configJson: '{}', seed: 1, startedAt: at, endedAt: Value(at.add(const Duration(minutes: 5)))));
    await v6.into(v6.sessions).insert(SessionsCompanion.insert(playerId: me, gameId: 'highscore_hunt', configJson: '{}', seed: 2, startedAt: at));
    await v6.customStatement('ALTER TABLE sessions DROP COLUMN updated_at');
    await v6.customStatement('PRAGMA user_version = 6');
    await v6.close();

    final v7 = AppDatabase(NativeDatabase(file));
    final cols = await v7.customSelect('PRAGMA table_info(sessions)').get();
    expect(cols.map((r) => r.read<String>('name')), contains('updated_at'));
    final rows = await (v7.select(v7.sessions)..orderBy([(s) => OrderingTerm.asc(s.seed)])).get();
    expect(rows[0].updatedAt, rows[0].endedAt);
    expect(rows[1].updatedAt, isNull, reason: 'offene Session bleibt ohne Stand');
    await v7.customStatement('PRAGMA user_version = 6');
    await v7.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect((await again.select(again.sessions).get()).first.updatedAt, isNotNull);
    expect((await again.customSelect('PRAGMA user_version').getSingle()).data.values.single, 7);
  });
}
