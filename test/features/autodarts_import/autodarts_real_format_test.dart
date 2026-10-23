import 'dart:convert';
import 'dart:io';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/autodarts_import/data/autodarts_import_repository.dart';
import 'package:dartlab/features/autodarts_import/data/autodarts_import_service.dart';
import 'package:dartlab/features/autodarts_import/domain/autodarts_match_mapping.dart';
import 'package:dartlab/features/autodarts_import/domain/import_plan.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Das Fixture `match-stats-501-online.json` ist eine ECHTE `/stats`-Antwort
/// eines Online-Matches (501, Double-Out, 3:2 in fünf Legs, Stand 22.10.2026),
/// ANONYMISIERT: Namen sind „Ben“ (Index 1) und „Gegner“ (Index 0), alle Ids
/// erfunden, Avatar und Nutzerdaten entfernt. Würfe, Felder, Koordinaten und
/// Zeiten sind unverändert. Das Match hat ein Spieler mit Index 0 gewonnen,
/// also der Gegner (Ben verliert 2:3).
const _fixture = 'test/fixtures/autodarts/match-stats-501-online.json';

Map<String, Object?> _load() => jsonDecode(File(_fixture).readAsStringSync()) as Map<String, Object?>;

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  final raw = _load();
  final match = parseAutodartsMatch(raw);

  int dartsOf(int player) => match.legs.expand((l) => l.turns).where((t) => t.player == player).fold(0, (a, t) => a + t.darts.length);
  int turnsOf(int player) => match.legs.expand((l) => l.turns).where((t) => t.player == player).length;

  group('Lesen der echten Form', () {
    test('Kopf: Id aus dem Body, Spieler, 501, Double-Out, fertig, ohne Hinweise', () {
      expect(match.id, raw['id']);
      expect([for (final p in match.players) p.name], ['Gegner', 'Ben']);
      expect(match.startScore, 501);
      expect(match.outMode, OutMode.double);
      expect(match.doubleIn, isFalse);
      expect(match.finished, isTrue);
      expect(match.finishedAt!.isAtSameMomentAs(DateTime.parse('2026-10-22T20:49:03.609993Z')), isTrue);
      expect(match.warnings, isEmpty);
    });

    test('fünf Legs; Sieger über winnerPlayerId (nicht über das Feld winner je Leg)', () {
      expect(match.legs, hasLength(5));
      // games[].winner zählt nach Wurfreihenfolge (0,0,1,1,1) und wäre falsch.
      expect([for (final l in match.legs) l.winner], [1, 0, 0, 1, 0]);
      expect([for (final l in match.legs) l.leg], [1, 2, 3, 4, 5], reason: 'die Daten zählen ab 0, DartLab ab 1');
      final head = (raw['scores']! as List).map((s) => (s as Map)['legs']).toList();
      expect(head, [3, 2], reason: 'Match-Kopf nach Spielerindex');
      expect([for (var i = 0; i < 2; i++) match.legs.where((l) => l.winner == i).length], [3, 2]);
    });

    test('Aufnahmen und Darts je Spieler stimmen mit matchStats überein', () {
      final stats = (raw['matchStats']! as List).cast<Map<String, Object?>>();
      final players = (raw['players']! as List).cast<Map<String, Object?>>();
      for (final (i, p) in players.indexed) {
        final s = stats.firstWhere((x) => x['playerId'] == p['id']);
        expect(dartsOf(i), s['dartsThrown'], reason: 'Spieler $i');
      }
      expect([turnsOf(0), turnsOf(1)], [64, 64]);
      expect([dartsOf(0), dartsOf(1)], [186, 191]);
    });

    test('Fehlwürfe: „M<n>“ (Outside) mit Position, „Miss“ ohne Position; Eingabeart egal', () {
      final darts = match.legs.expand((l) => l.turns).expand((t) => t.darts).toList();
      final rawThrows = [for (final g in raw['games']! as List) for (final t in (g as Map)['turns'] as List) ...((t as Map)['throws'] as List)];
      expect(darts, hasLength(rawThrows.length));
      final fills = [for (final (i, t) in rawThrows.indexed) if ((t as Map)['entry'] == 'fill_miss') i];
      expect(fills, hasLength(14));
      for (final i in fills) {
        expect(darts[i].segment, Segment.miss);
        expect(darts[i].position, isNull, reason: 'fill_miss hat keine coords');
      }
      final outside = [for (final (i, t) in rawThrows.indexed) if (((t as Map)['segment'] as Map)['bed'] == 'Outside' && t['entry'] != 'fill_miss') i];
      expect(outside, hasLength(42));
      for (final i in outside) {
        expect(darts[i].segment, Segment.miss);
        expect(darts[i].position, isNotNull);
      }
      // Eine nachträglich korrigierte Dart (entry „corrected“) wird wie jeder andere gelesen.
      expect(rawThrows.where((t) => (t as Map)['entry'] == 'corrected'), hasLength(1));
      expect(darts.where((d) => d.position == null), hasLength(14));
    });

    test('Single innen und außen werden unterschieden, Triple und Double stimmen', () {
      final darts = match.legs.expand((l) => l.turns).expand((t) => t.darts).toList();
      expect(darts.where((d) => d.segment.bed == Bed.singleInner), hasLength(80));
      expect(darts.where((d) => d.segment.bed == Bed.singleOuter), hasLength(199));
      expect(darts.where((d) => d.segment.isTriple), hasLength(33));
      expect(darts.where((d) => d.segment.isDouble), hasLength(9));
    });

    test('Koordinaten haben dieselbe Skala wie der Board Manager (Radius 1 = Außenkante Double)', () {
      double median(Iterable<double> v) {
        final s = v.toList()..sort();
        return s[s.length ~/ 2];
      }

      final darts = match.legs.expand((l) => l.turns).expand((t) => t.darts).where((d) => d.position != null).toList();
      final doubles = median([for (final d in darts) if (d.segment.isDouble) d.position!.distance]);
      final triples = median([for (final d in darts) if (d.segment.isTriple) d.position!.distance]);
      expect(doubles, inInclusiveRange(0.93, 1.0));
      expect(triples, inInclusiveRange(0.57, 0.65));
    });
  });

  group('Plan aus Sicht von Ben (Index 1)', () {
    final plan = buildImportPlan(match, me: 1, now: DateTime.utc(2026, 10, 23));

    test('Ergebnis 2:3, nicht gewonnen, Gegner heißt „Gegner“', () {
      expect(plan.opponent.name, 'Gegner');
      expect(plan.myPlayer.name, 'Ben');
      expect([plan.legsMe, plan.legsOpponent], [2, 3]);
      expect(plan.won, isFalse);
      expect(plan.finished, isTrue);
      expect(plan.warnings, isEmpty);
    });

    test('nur Bens Darts: 64 Aufnahmen, 191 Darts, davon 183 mit Position', () {
      expect(plan.ownVisits, 64);
      expect(plan.darts, hasLength(191));
      expect(plan.darts.where((d) => d.position != null), hasLength(183));
      expect(plan.darts.where((d) => d.position == null && d.segment.isMiss), hasLength(8), reason: '„Miss“ ohne Koordinaten bleibt ein Fehlwurf');
    });

    test('Kennzahlen decken sich mit denen von Autodarts (Punkte, First 9, Busts, Legs)', () {
      final stats = (raw['matchStats']! as List).cast<Map<String, Object?>>();
      final players = (raw['players']! as List).cast<Map<String, Object?>>();
      final s = stats.firstWhere((x) => x['playerId'] == players[1]['id']);
      final m = plan.result.metrics;
      final points = (s['average']! as num) * (s['dartsThrown']! as num) / 3;
      // „average“ zählt Bust-Aufnahmen als 0 Punkte und nur gewertete Darts (Live-Regel).
      expect((m['average']! * m['darts']! / 3).round(), points.round(), reason: 'abgezogene Punkte, Bust zählt 0');
      expect(m['points'], 2507, reason: 'Summe aller Dart-Werte, auch der Bust-Aufnahmen');
      expect(m['first9']!, closeTo((s['first9Average']! as num).toDouble(), 0.01));
      expect(m['busts'], 8);
      expect([m['legsWon'], m['legsLost']], [2, 3]);
      expect(m['won'], 0);
    });

    test('Darts nach einem Bust zählt DartLab wie bei Live nicht mit (Autodarts zählt sie)', () {
      // 8 Busts mit je einem Dart nach dem Bust; Ergebnis: 183 gewertete statt 191 geworfene Darts.
      expect(plan.result.metrics['darts'], 183);
      expect(plan.darts.where((d) => !d.counted), hasLength(8));
    });

    test('Legs, die Ben gewonnen hat, haben ein Finish; die des Gegners stehen nur mit seinen Aufnahmen', () {
      final legs = plan.result.details['matchLegs']! as List;
      expect(legs, hasLength(5));
      expect([for (final l in legs) (l as Map)['winner']], [0, 1, 1, 0, 1], reason: '0 = Ben (aus seiner Sicht)');
      for (final l in legs.cast<Map<String, Object?>>()) {
        expect(l['checkout'], isNotNull, reason: 'Leg ${l['leg']}');
        expect((l['opp']! as List), isNotEmpty);
      }
      expect(plan.result.metrics['highestFinish'], greaterThan(0));
    });
  });

  test('Plan aus Sicht des Gegners (Index 0): 3:2, gewonnen, 186 Darts', () {
    final plan = buildImportPlan(match, me: 0, now: DateTime.utc(2026, 10, 23));
    expect([plan.legsMe, plan.legsOpponent], [3, 2]);
    expect(plan.won, isTrue);
    expect(plan.darts, hasLength(186));
    expect(plan.ownVisits, 64);
  });

  group('über den Service in die Datenbank', () {
    late AppDatabase db;
    late AutodartsImportService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final me = await ProfileRepository(db).resolve(null);
      service = AutodartsImportService(
        repository: AutodartsImportRepository(db),
        playerId: () async => me,
        myName: () => 'ben',
        rememberName: (_) async {},
      );
    });
    tearDown(() => db.close());

    test('Import, Duplikat, Statistik: Streuung nur mit Bens Darts, Doppelquote plausibel', () async {
      final r = await service.importJson(raw, origin: 'file');
      expect(r.status, ImportStatus.imported);
      expect(r.opponent, 'Gegner');
      expect(r.plan!.legsMe, 2);
      expect((await service.importJson(raw)).status, ImportStatus.duplicate);

      final calc = StatsCalculator(
        sessions: await (db.select(db.sessions)..where((s) => s.endedAt.isNotNull())).get(),
        throws: await db.select(db.throws).get(),
      );
      final s = calc.sessions.single;
      expect(calc.throwsOf(s), hasLength(191), reason: 'nur Bens Darts in der Datenbank');
      expect(calc.scatterOf(s).positioned, 183);

      final m = calc.onlineMatchOf(s)!;
      expect(m.opponent, 'Gegner');
      expect([m.legsWon, m.legsLost], [2, 3]);
      expect(m.won, isFalse);

      final doubles = calc.liveDoublesOf(s);
      final attempts = doubles.values.fold<int>(0, (a, h) => a + h.attempts);
      final hits = doubles.values.fold<int>(0, (a, h) => a + h.hits);
      expect(attempts, greaterThan(5));
      expect(hits, lessThan(attempts));
      expect(hits / attempts, lessThan(0.5), reason: 'Ben trifft die Doppel selten (2 Checkouts)');
    });
  });
}
