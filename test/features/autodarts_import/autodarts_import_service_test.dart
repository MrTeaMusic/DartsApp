import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/autodarts_import/data/autodarts_import_repository.dart';
import 'package:dartlab/features/autodarts_import/data/autodarts_import_service.dart';
import 'package:dartlab/features/autodarts_import/domain/imported_match.dart';
import 'package:dartlab/features/autodarts_import/domain/import_plan.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_controller.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/history/domain/session_history.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/autodarts_match_fixture.dart';
import '../../helpers/online_seed.dart';

// Alle Match-Daten sind synthetisch (siehe autodarts_match_fixture.dart).

Object? wire(Map<String, Object?> m) => jsonDecode(jsonEncode(m));

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late AppDatabase db;
  late int me;
  late AutodartsImportService service;
  late String name;
  final remembered = <String>[];
  final clock = DateTime(2026, 10, 21, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    me = await ProfileRepository(db).resolve(null);
    name = '';
    remembered.clear();
    service = AutodartsImportService(
      repository: AutodartsImportRepository(db),
      playerId: () async => me,
      myName: () => name,
      rememberName: (n) async {
        name = n;
        remembered.add(n);
      },
      clock: () => clock,
    );
  });
  tearDown(() => db.close());

  Future<List<SessionRow>> sessions() => (db.select(db.sessions)..where((s) => s.deletedAt.isNull())).get();
  Future<List<ThrowRow>> throwsOf(int sid) => (db.select(db.throws)..where((t) => t.sessionId.equals(sid))).get();

  group('Name bekannt', () {
    setUp(() => name = 'Ben');

    test('Import legt eine x01_live-Session mit nur Bens Darts an', () async {
      final r = await service.importJson(wire(syntheticMatch()), origin: 'browserScript');
      expect(r.status, ImportStatus.imported);
      expect(r.id, 'synthetic-0001');
      expect(r.opponent, 'Gegner');
      expect(r.plan!.legsMe, 3);
      final all = await sessions();
      expect(all, hasLength(1));
      final s = all.single;
      expect(s.gameId, importGameId);
      expect(s.finished, isTrue);
      expect(s.endedAt, isNotNull);
      expect(s.dartCount, r.plan!.darts.length);
      final t = await throwsOf(s.id);
      expect(t, hasLength(r.plan!.darts.length));
      expect(t.map((e) => e.source).toSet(), {importThrowSource});
      expect(t.where((e) => e.x != null), hasLength(t.length));
      final cfg = jsonDecode(s.configJson) as Map;
      expect((cfg['import'] as Map)['id'], 'synthetic-0001');
      expect((cfg['import'] as Map)['origin'], 'browserScript');
      expect(remembered, isEmpty, reason: 'Name war schon gesetzt');
    });

    test('zweiter Import desselben Matches: duplicate, nichts doppelt', () async {
      await service.importJson(wire(syntheticMatch()));
      final again = await service.importJson(wire(syntheticMatch()));
      expect(again.status, ImportStatus.duplicate);
      expect(await sessions(), hasLength(1));
      expect(await db.select(db.throws).get(), hasLength((await sessions()).single.dartCount));
    });

    test('Id aus der Adresse genügt als Kennung', () async {
      final json = syntheticMatch(id: null);
      final a = await service.importJson(wire(json), externalId: 'url-id-1');
      final b = await service.importJson(wire(json), externalId: 'url-id-1');
      final c = await service.importJson(wire(json), externalId: 'url-id-2');
      expect([a.status, b.status, c.status], [ImportStatus.imported, ImportStatus.duplicate, ImportStatus.imported]);
    });

    test('Ersetzen behält die Session und tauscht die Darts', () async {
      final first = await service.importJson(wire(syntheticMatch()));
      final changed = syntheticMatch(coords: false);
      final r = await service.importJson(wire(changed), replace: true);
      expect(r.status, ImportStatus.imported);
      expect(r.replaced, isTrue);
      expect(r.sessionId, first.sessionId);
      expect(await sessions(), hasLength(1));
      final t = await throwsOf(first.sessionId!);
      expect(t, hasLength(first.plan!.darts.length));
      expect(t.where((e) => e.x != null), isEmpty);
    });

    test('ein unfertiges Match wird vom fertigen derselben Id ersetzt, ein fertiges nicht', () async {
      final open = syntheticMatch(finished: false, finishedAt: null);
      (open['games']! as List).removeLast();
      final first = await service.importJson(wire(open));
      expect(first.plan!.finished, isFalse);
      final done = await service.importJson(wire(syntheticMatch()));
      expect(done.status, ImportStatus.imported);
      expect(done.replaced, isTrue);
      expect(done.sessionId, first.sessionId);
      expect(await sessions(), hasLength(1));
      expect((await sessions()).single.finished, isTrue);
      final again = await service.importJson(wire(open));
      expect(again.status, ImportStatus.duplicate, reason: 'ein fertiges Match wird nicht durch einen älteren Stand überschrieben');
    });

    test('nach dem Löschen lässt sich dasselbe Match erneut importieren', () async {
      final first = await service.importJson(wire(syntheticMatch()));
      await GameRepository(db).deleteSession(first.sessionId!);
      final again = await service.importJson(wire(syntheticMatch()));
      expect(again.status, ImportStatus.imported);
      expect(await sessions(), hasLength(1));
    });

    test('Cricket wird ignoriert, ohne Spuren', () async {
      final r = await service.importJson(wire(syntheticMatch(variant: 'Cricket')));
      expect(r.status, ImportStatus.ignored);
      expect(r.message, contains('X01'));
      expect(await sessions(), isEmpty);
    });

    test('Unbrauchbares wirft einen klaren Fehler', () async {
      expect(() => service.importJson(<String, Object?>{'foo': 1}), throwsA(isA<AutodartsImportException>()));
      expect(() => service.importJson('Text'), throwsA(isA<AutodartsImportException>()));
      expect(await sessions(), isEmpty);
    });

    test('spielt Ben als zweiter Spieler, wird er trotzdem erkannt', () async {
      final r = await service.importJson(wire(syntheticMatch(ben: 'Gegner', opponent: 'Ben')));
      expect(r.status, ImportStatus.imported);
      expect(r.plan!.me, 1);
      expect(r.plan!.legsMe, 2, reason: 'Ben ist hier der zweite Spieler und gewinnt die Legs 2 und 4');
      expect(r.plan!.won, isFalse);
      expect(r.opponent, 'Gegner');
    });
  });

  group('Name unbekannt', () {
    test('pending, nichts gespeichert', () async {
      final r = await service.importJson(wire(syntheticMatch()));
      expect(r.status, ImportStatus.pending);
      expect(r.match!.players.map((p) => p.name), ['Ben', 'Gegner']);
      expect(await sessions(), isEmpty);
    });

    test('Antwort „ich bin Spieler 0“ importiert und merkt sich den Namen', () async {
      final pending = await service.importJson(wire(syntheticMatch()));
      final r = await service.importMatch(pending.match!, me: 0);
      expect(r.status, ImportStatus.imported);
      expect(remembered, ['Ben']);
      // Beim nächsten Match fragt niemand mehr.
      final next = await service.importJson(wire(syntheticMatch(id: 'synthetic-0002')));
      expect(next.status, ImportStatus.imported);
    });

    test('bereits importiertes Match fragt nicht erneut', () async {
      final pending = await service.importJson(wire(syntheticMatch()));
      await service.importMatch(pending.match!, me: 0);
      name = '';
      final r = await service.importJson(wire(syntheticMatch()));
      expect(r.status, ImportStatus.duplicate);
    });
  });

  group('Überschneidung mit Live', () {
    setUp(() => name = 'Ben');

    test('Live-Aufzeichnung im selben Zeitraum wird gemeldet, nicht gelöscht', () async {
      final live = await seedOnlineMatch(GameRepository(db), me, DateTime.utc(2026, 10, 20, 19, 2), legs: 2);
      final r = await service.importJson(wire(syntheticMatch()));
      expect(r.status, ImportStatus.imported);
      expect(r.overlapStartedAt, isNotNull);
      expect(await sessions(), hasLength(2));
      expect((await sessions()).any((s) => s.id == live), isTrue);
    });

    test('Live-Aufzeichnung an einem anderen Tag ist keine Überschneidung', () async {
      await seedOnlineMatch(GameRepository(db), me, DateTime.utc(2026, 9, 1, 19), legs: 2);
      final r = await service.importJson(wire(syntheticMatch()));
      expect(r.overlapStartedAt, isNull);
    });
  });

  group('Auswertung', () {
    late int sid;
    setUp(() async {
      name = 'Ben';
      sid = (await service.importJson(wire(syntheticMatch()))).sessionId!;
    });

    Future<StatsCalculator> calc() async => StatsCalculator(
          sessions: await (db.select(db.sessions)..where((s) => s.endedAt.isNotNull())).get(),
          throws: await db.select(db.throws).get(),
        );

    test('Statistik „Online“ kennt Gegner, Legs und Sieg', () async {
      final c = await calc();
      final m = c.onlineMatchOf(c.sessions.single)!;
      expect(m.opponent, 'Gegner');
      expect(m.won, isTrue);
      expect(m.legsWon, 3);
      expect(m.legsLost, 2);
      expect(m.x01, isTrue);
    });

    test('Bens Darts mit Position fließen in die Streuung, die des Gegners nicht', () async {
      final c = await calc();
      final dartsOfBen = (await throwsOf(sid)).length;
      expect(c.scatterOf(c.sessions.single).positioned, dartsOfBen);
    });

    test('Wurftempo bleibt unberührt (Import-Zeiten sind keine Wurfzeiten)', () async {
      final c = await calc();
      expect(c.sessions.single.id, sid);
      final rows = await throwsOf(sid);
      expect(rows.where((t) => t.source == 'autodartsLocal'), isEmpty);
    });

    test('Verlauf: Ergebnis, Gegner und Aufnahmen beider Spieler je Leg', () async {
      final s = (await sessions()).single;
      final entry = HistoryEntry(s);
      expect(entry.isImported, isTrue);
      expect(entry.hasOpponent, isTrue);
      expect(entry.won, isTrue);
      final detail = buildSessionDetail(s, await throwsOf(sid), playerName: 'Ben');
      expect(detail.players.map((p) => p.name), ['Ben', 'Gegner']);
      expect(detail.legs, hasLength(5));
      expect([for (final l in detail.legs) l.winner], [0, 1, 0, 1, 0]);
      expect(detail.legs.every((l) => l.others.isNotEmpty), isTrue);
      expect(detail.legs[1].others.single.player, 1);
    });

    test('Reparatur der Live-Sessions lässt den Import in Ruhe', () async {
      final before = (await sessions()).single.resultJson;
      final fixed = await repairLiveSessions(db);
      expect(fixed, 0);
      expect((await sessions()).single.resultJson, before);
    });
  });
}
