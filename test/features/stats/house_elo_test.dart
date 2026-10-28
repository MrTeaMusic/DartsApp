import 'dart:convert';

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/autodarts_import/domain/autodarts_match_mapping.dart';
import 'package:dartlab/features/autodarts_import/domain/import_plan.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/autodarts_match_fixture.dart';
import '../../helpers/elo_seed.dart';

// Alle Daten sind synthetisch (Ben, Anna, Gegner, Bots).

var _n = 0;

/// Ein gewertetes Match direkt (ohne Session).
EloMatch m(
  bool won, {
  int day = 0,
  EloOpponentKind kind = EloOpponentKind.bot,
  String id = 'bot:x@50',
  String name = 'X',
  double? mine = 50,
  double? theirs = 50,
  String? sortKey,
  DateTime? at,
}) {
  _n++;
  return EloMatch(
    sessionId: _n,
    sortKey: sortKey ?? 'k${_n.toString().padLeft(5, '0')}',
    at: at ?? DateTime(2026, 9, 1 + day, 19),
    kind: kind,
    opponentId: id,
    opponentName: name,
    won: won,
    myAverage: mine,
    opponentAverage: theirs,
  );
}

void main() {
  group('Rechnung', () {
    test('ohne Matches: Startwert 1000, nichts gewertet', () {
      final r = HouseElo.compute(const []);
      expect(r.current, 1000);
      expect(r.isEmpty, isTrue);
      expect(r.peak, isNull);
      expect(r.hasHistory, isFalse);
    });

    test('Sieg gegen gleich starken Gegner: +K/2 (K = 32 am Anfang)', () {
      final r = HouseElo.compute([m(true)]);
      expect(r.steps.single.expected, closeTo(0.5, 1e-12));
      expect(r.steps.single.k, 32);
      expect(r.current, closeTo(1016, 1e-9));
      expect(r.steps.single.change, closeTo(16, 1e-9));
    });

    test('Niederlage gegen gleich starken Gegner: symmetrisch -K/2', () {
      final r = HouseElo.compute([m(false)]);
      expect(r.current, closeTo(984, 1e-9));
    });

    test('Erwartung: 400 Punkte mehr heißt 10:1', () {
      expect(HouseElo.expected(1000, 1000), closeTo(0.5, 1e-12));
      expect(HouseElo.expected(1000, 1400), closeTo(1 / 11, 1e-12));
      expect(HouseElo.expected(1400, 1000), closeTo(10 / 11, 1e-12));
    });

    test('Sieg als klarer Außenseiter bringt fast K', () {
      // 25 Average mehr = +300 (Grenze): Erwartung 1 / (1 + 10^0,75), Sieg bringt 32 * (1 - E).
      final r = HouseElo.compute([m(true, theirs: 75, mine: 50)]);
      const e = 1 / (1 + 5.623413251903491);
      expect(r.steps.single.opponentBefore, closeTo(1300, 1e-9));
      expect(r.steps.single.expected, closeTo(e, 1e-9));
      expect(r.steps.single.change, closeTo(32 * (1 - e), 1e-9));
    });

    test('K wechselt nach 20 Matches von 32 auf 24', () {
      final r = HouseElo.compute([for (var i = 0; i < 22; i++) m(true, day: i, id: 'bot:g$i@50')]);
      expect({for (final s in r.steps) s.k}, {32.0, 24.0});
      expect(r.steps[19].k, 32);
      expect(r.steps[20].k, 24);
      // Gegner sind alle neu und gleich stark geschätzt (Ben hält 50 Average):
      // erwartet ist 0,5, also +K/2 je Sieg.
      expect(r.steps[20].change, closeTo(12, 1e-9));
      expect(r.steps[19].change, closeTo(16, 1e-9));
    });

    test('Gegner-Schätzung: 12 Punkte je Average-Punkt, auf Bens Rating bezogen', () {
      final r = HouseElo.compute([
        m(true, id: 'a', theirs: 50, mine: 50), // Ben 1016
        m(true, id: 'b', day: 1, theirs: 55, mine: 50), // +5 Average = +60
      ]);
      expect(r.steps[1].opponentBefore, closeTo(r.steps[1].before + 60, 1e-9));
      expect(r.steps[1].opponentEstimated, isTrue);
      final r2 = HouseElo.compute([m(true, theirs: 44, mine: 50)]);
      expect(r2.steps.single.opponentBefore, closeTo(1000 - 72, 1e-9));
    });

    test('Gegner-Schätzung ist auf ±300 begrenzt', () {
      final up = HouseElo.compute([m(true, theirs: 120, mine: 40)]);
      expect(up.steps.single.opponentBefore, closeTo(1300, 1e-9));
      final down = HouseElo.compute([m(true, theirs: 20, mine: 90)]);
      expect(down.steps.single.opponentBefore, closeTo(700, 1e-9));
    });

    test('Fallbacks: ohne Gegner-Average startet er bei Bens Rating', () {
      final r = HouseElo.compute([m(true, theirs: null), m(false, id: 'o', day: 1, theirs: null)]);
      expect(r.steps[0].opponentBefore, 1000);
      expect(r.steps[1].opponentBefore, r.steps[1].before);
    });

    test('Fallbacks: ohne eigenen Average im Match und davor ebenso', () {
      final r = HouseElo.compute([m(true, mine: null, theirs: 70)]);
      expect(r.steps.single.opponentBefore, 1000);
    });

    test('Bens gleitender Average stammt aus den Matches davor (letzte 10)', () {
      // Elf Matches mit Average 40, dann eins mit 60 gegen einen Gegner mit 52:
      // Fenster = letzte zehn davor = 40, also +12 * (52 - 40) = +144.
      final list = [
        for (var i = 0; i < 11; i++) m(true, day: i, id: 'x$i', mine: 40, theirs: 40),
        m(true, day: 11, id: 'neu', mine: 60, theirs: 52),
      ];
      final r = HouseElo.compute(list);
      final last = r.steps.last;
      expect(last.opponentBefore, closeTo(last.before + 144, 1e-9));
    });

    test('Wiederkehrer wird mitgeführt, nicht neu geschätzt', () {
      final r = HouseElo.compute([
        m(true, id: 'a', theirs: 50),
        m(true, id: 'b', day: 1, theirs: 50),
        m(false, id: 'a', day: 2, theirs: 99), // ein anderer Average zählt nicht mehr
      ]);
      expect(r.steps[2].opponentEstimated, isFalse);
      expect(r.steps[2].opponentBefore, closeTo(r.steps[0].opponentAfter, 1e-12));
      // Das Rating des Gegners läuft in Gegenrichtung: Ben gewann, der Gegner fiel (K = 24).
      expect(r.steps[0].opponentAfter, closeTo(r.steps[0].opponentBefore - 24 * 0.5, 1e-9));
    });

    test('Gegner-Update ist Nullsumme mit K = 24 für den Gegner', () {
      final r = HouseElo.compute([m(false)]);
      final s = r.steps.single;
      expect(s.opponentAfter - s.opponentBefore, closeTo(12, 1e-9));
      expect(s.change, closeTo(-16, 1e-9));
    });

    test('Reihenfolge: nach Startzeit, bei Gleichstand nach Uid, unabhängig von der Eingabe', () {
      final same = DateTime(2026, 9, 5, 20);
      final a = m(true, at: same, sortKey: 'a', id: 'a');
      final b = m(false, at: same, sortKey: 'b', id: 'b');
      final c = m(true, at: DateTime(2026, 9, 1), sortKey: 'z', id: 'c');
      final one = HouseElo.compute([a, b, c]);
      final two = HouseElo.compute([c, b, a]);
      final three = HouseElo.compute([b, c, a]);
      expect([for (final s in one.steps) s.match.opponentId], ['c', 'a', 'b']);
      for (final r in [two, three]) {
        expect([for (final s in r.steps) s.match.opponentId], ['c', 'a', 'b']);
        expect(r.current, one.current);
      }
    });

    test('Peak, Bilanz, Zähler und Änderung seit einem Datum', () {
      final r = HouseElo.compute([
        m(true, day: 0, id: 'a'),
        m(true, day: 10, id: 'b'),
        m(false, day: 40, id: 'c'),
        m(false, day: 50, id: 'd'),
      ]);
      expect(r.matches, 4);
      expect(r.wins, 2);
      expect(r.losses, 2);
      expect(r.peakStep!.match.opponentId, 'b');
      expect(r.peak, greaterThan(r.current));
      final from = DateTime(2026, 9, 1 + 30);
      expect(r.ratingBefore(from), closeTo(r.steps[1].after, 1e-12));
      expect(r.changeSince(from), closeTo(r.current - r.steps[1].after, 1e-12));
      // Alles liegt nach dem Datum: Veränderung seit dem Start.
      expect(r.changeSince(DateTime(2026, 1, 1)), closeTo(r.current - 1000, 1e-12));
      // Nichts danach: keine Veränderung.
      expect(r.changeSince(DateTime(2027, 1, 1)), 0);
    });

    test('Neuberechnung nach Löschen: Verlauf passt sich an, nichts bleibt hängen', () {
      final all = [for (var i = 0; i < 6; i++) m(i.isEven, day: i, id: 'g${i % 3}', theirs: 50.0 + i)];
      final full = HouseElo.compute(all);
      final without = HouseElo.compute([...all]..removeAt(2));
      expect(without.matches, 5);
      expect(without.current, isNot(closeTo(full.current, 1e-6)));
      // Gleicher Datenstand, gleiches Ergebnis (deterministisch).
      final again = HouseElo.compute(all);
      expect([for (final s in again.steps) s.after], [for (final s in full.steps) s.after]);
      // Nach „Löschen und Wiederherstellen“ ist alles wieder wie vorher.
      final restored = HouseElo.compute([...all]..removeAt(2)..insert(2, all[2]));
      expect(restored.current, closeTo(full.current, 1e-12));
    });

    test('Gegner: Bilanz, Rating, Änderung; Filter nach Art und Zeitraum', () {
      final r = HouseElo.compute([
        m(true, day: 0, id: 'bot:a@40', name: 'A', kind: EloOpponentKind.bot, theirs: 40),
        m(true, day: 1, id: 'bot:a@40', name: 'A', kind: EloOpponentKind.bot, theirs: 40),
        m(false, day: 2, id: 'online:l', name: 'L', kind: EloOpponentKind.online, theirs: 60),
        m(true, day: 40, id: 'local:z', name: 'Z', kind: EloOpponentKind.local, theirs: 45),
      ]);
      final all = r.opponents();
      expect(all.first.name, 'A');
      expect(all.first.matches, 2);
      expect(all.first.wins, 2);
      expect(all.first.change, closeTo(r.steps[0].change + r.steps[1].change, 1e-12));
      expect(all.first.rating, closeTo(r.steps[1].opponentAfter, 1e-12));
      expect(r.opponents(kind: EloOpponentKind.online).single.name, 'L');
      expect(r.opponents(kind: EloOpponentKind.local).single.name, 'Z');
      expect(r.opponents(from: DateTime(2026, 9, 1 + 30)).single.name, 'Z');
    });

    test('Größte Siege und bitterste Niederlagen nach Gegner-Rating', () {
      final r = HouseElo.compute([
        m(true, day: 0, id: 'schwach', name: 'Schwach', theirs: 30),
        m(true, day: 1, id: 'stark', name: 'Stark', theirs: 70),
        m(true, day: 2, id: 'mittel', name: 'Mittel', theirs: 52),
        m(true, day: 3, id: 'm2', name: 'Mittel2', theirs: 48),
        m(false, day: 4, id: 'x', name: 'Stark2', theirs: 80),
        m(false, day: 5, id: 'y', name: 'Schwach2', theirs: 35),
        m(false, day: 6, id: 'z', name: 'Mittel3', theirs: 45),
        m(false, day: 7, id: 'w', name: 'Egal', theirs: 55),
      ]);
      expect([for (final s in r.bestWins()) s.match.opponentName], ['Stark', 'Mittel', 'Mittel2']);
      expect([for (final s in r.worstLosses()) s.match.opponentName], ['Schwach2', 'Mittel3', 'Egal']);
      expect(r.bestWins(count: 1), hasLength(1));
    });
  });

  group('Welche Sessions zählen', () {
    final t = DateTime(2026, 10, 1, 19);

    EloMatch? of(SessionRow row) => EloMatch.fromSession(
          sessionId: row.id,
          uid: row.uid,
          gameId: row.gameId,
          startedAt: row.startedAt,
          finished: row.finished,
          config: StatsCalculator.decode(row.configJson),
          result: StatsCalculator.decode(row.resultJson),
        );

    test('Bot-Match: Bot mit nominalem Average, stabile Kennung', () {
      final e = of(eloRow(EloKind.bot, t, opponent: 'CPU 55', botAverage: 55, opponentAverage: 53.2, myAverage: 51))!;
      expect(e.kind, EloOpponentKind.bot);
      expect(e.opponentId, 'bot:cpu 55@55');
      expect(e.opponentAverage, 55);
      expect(e.botAverage, 55);
      expect(e.myAverage, 51);
      expect(e.won, isTrue);
      expect(e.legsWon, 3);
    });

    test('Mitspieler: Kennung nach Name (klein), Average aus dem Match', () {
      final e = of(eloRow(EloKind.local, t, opponent: 'Anna', opponentAverage: 44.5))!;
      expect(e.kind, EloOpponentKind.local);
      expect(e.opponentId, 'local:anna');
      expect(e.opponentAverage, 44.5);
      expect(of(eloRow(EloKind.local, t, opponent: 'ANNA'))!.opponentId, 'local:anna');
    });

    test('Online-Import: Autodarts-Name klein, Match-Average des Gegners', () {
      final e = of(eloRow(EloKind.online, t, opponent: 'Gegner', opponentAverage: 61.2, won: false))!;
      expect(e.kind, EloOpponentKind.online);
      expect(e.opponentId, 'online:gegner');
      expect(e.opponentAverage, 61.2);
      expect(e.won, isFalse);
      // Derselbe Name als Mitspieler ist ein anderer Gegner.
      expect(of(eloRow(EloKind.local, t, opponent: 'Gegner'))!.opponentId, isNot(e.opponentId));
    });

    test('echter Import aus dem Test-Match: Sieger, Name, Averages', () {
      final plan = buildImportPlan(parseAutodartsMatch(jsonDecode(jsonEncode(syntheticMatch()))), me: 0, now: t);
      final e = EloMatch.fromSession(
        sessionId: 1,
        uid: 'u',
        gameId: importGameId,
        startedAt: t,
        finished: plan.finished,
        config: jsonDecode(jsonEncode(plan.config)) as Map<String, Object?>,
        result: jsonDecode(jsonEncode(plan.result.toJson())) as Map<String, Object?>,
      )!;
      expect(e.kind, EloOpponentKind.online);
      expect(e.opponentName, 'Gegner');
      expect(e.won, isTrue);
      expect(e.myAverage, isNotNull);
      expect(e.opponentAverage, isNotNull);
      expect(e.legsWon, 3);
      expect(e.legsLost, 2);
    });

    test('Turnier-Match zählt wie ein Bot-Match', () {
      final d = eloMatchData(EloKind.bot, opponent: 'CPU 70', tournament: true);
      final e = EloMatch.fromSession(
        sessionId: 1,
        uid: 'u',
        gameId: d.gameId,
        startedAt: t,
        finished: true,
        config: d.config,
        result: d.result,
      );
      expect(e, isNotNull);
      expect(e!.kind, EloOpponentKind.bot);
    });

    test('nicht gewertet: Training, Solo, Quiz, Live ohne Gegner', () {
      for (final game in ['x01', 'checkout', 'highscore_hunt', 'bobs_27', 'checkout_quiz', 'autodarts_live']) {
        expect(of(eloRow(EloKind.bot, t, gameId: game)), isNull, reason: game);
      }
      // x01_live ohne Import (mitgeschriebene Live-Session) hat keinen Gegner.
      final live = eloRow(EloKind.bot, t, gameId: 'x01_live');
      expect(of(live), isNull);
    });

    test('nicht gewertet: abgebrochene Matches', () {
      expect(of(eloRow(EloKind.bot, t, finished: false)), isNull);
      expect(of(eloRow(EloKind.online, t, finished: false)), isNull);
    });

    test('nicht gewertet: Ausgang unbekannt (Import ohne Sieger)', () {
      final d = eloMatchData(EloKind.online, opponent: 'Gegner');
      (d.result['metrics'] as Map).remove('won');
      (d.result['details'] as Map).remove('won');
      final e = EloMatch.fromSession(
        sessionId: 1,
        uid: 'u',
        gameId: d.gameId,
        startedAt: t,
        finished: true,
        config: d.config,
        result: d.result,
      );
      expect(e, isNull);
    });

    test('ältere Matches ohne Teilnehmerliste: Gegner aus den Namen, Bot an vsBot erkannt', () {
      final e = EloMatch.fromSession(
        sessionId: 1,
        uid: 'u',
        gameId: 'x01_match',
        startedAt: t,
        finished: true,
        config: {'opponents': ['Alter Bot'], 'vsBot': true},
        result: {
          'metrics': {'won': 0, 'average': 40, 'completed': 1},
          'details': {'opponents': ['Alter Bot']},
        },
      )!;
      expect(e.kind, EloOpponentKind.bot);
      expect(e.opponentId, 'bot:alter bot');
      expect(e.opponentAverage, isNull);
      expect(e.won, isFalse);
    });

    test('kaputte oder leere Ergebnisse stürzen nicht ab', () {
      expect(EloMatch.fromSession(sessionId: 1, uid: 'u', gameId: 'x01_match', startedAt: t, finished: true, config: const {}, result: const {}), isNull);
      expect(
        EloMatch.fromSession(
          sessionId: 1,
          uid: 'u',
          gameId: 'x01_match',
          startedAt: t,
          finished: true,
          config: const {},
          result: const {'metrics': {'won': 1}, 'details': {'players': 'kaputt'}},
        ),
        isNull,
      );
    });
  });

  group('StatsCalculator', () {
    test('houseElo wertet nur Matches, ignoriert Training und Abgebrochenes', () {
      final t = DateTime(2026, 10, 1, 19);
      final calc = eloCalc([
        eloRow(EloKind.bot, t, opponent: 'CPU 40', botAverage: 40, opponentAverage: 40, myAverage: 50),
        eloRow(EloKind.local, t.add(const Duration(days: 1)), opponent: 'Anna', won: false),
        eloRow(EloKind.online, t.add(const Duration(days: 2)), opponent: 'Gegner'),
        eloRow(EloKind.bot, t.add(const Duration(days: 3)), finished: false),
        eloRow(EloKind.bot, t.add(const Duration(days: 4)), gameId: 'x01'),
        eloRow(EloKind.bot, t.add(const Duration(days: 5)), gameId: 'highscore_hunt'),
      ]);
      expect(calc.houseElo.matches, 3);
      expect(calc.houseElo.wins, 2);
      expect(calc.houseElo.steps.map((s) => s.match.kind), [EloOpponentKind.bot, EloOpponentKind.local, EloOpponentKind.online]);
      // Zweimal gelesen, derselbe Lauf.
      expect(identical(calc.houseElo, calc.houseElo), isTrue);
    });

    test('Neuberechnung nach Löschen: ein neuer Rechner ohne die Session', () {
      final t = DateTime(2026, 10, 1, 19);
      final rows = [for (var i = 0; i < 5; i++) eloRow(EloKind.bot, t.add(Duration(days: i)), opponent: 'CPU ${40 + i}', botAverage: 40.0 + i, won: i != 2)];
      final full = eloCalc(rows).houseElo;
      final after = eloCalc([...rows]..removeAt(1)).houseElo;
      expect(full.matches, 5);
      expect(after.matches, 4);
      expect(after.steps.map((s) => s.sessionId), isNot(contains(rows[1].id)));
    });

    test('Reihenfolge unabhängig von der Reihenfolge der Sessions; gleiche Startzeit nach Uid', () {
      final t = DateTime(2026, 10, 1, 19);
      final a = eloRow(EloKind.bot, t, opponent: 'CPU 40', botAverage: 40, uid: 'aaa');
      final b = eloRow(EloKind.bot, t, opponent: 'CPU 60', botAverage: 60, won: false, uid: 'bbb');
      final c = eloRow(EloKind.local, t.add(const Duration(hours: 1)), opponent: 'Anna', uid: 'ccc');
      final one = eloCalc([a, b, c]).houseElo;
      final two = eloCalc([c, b, a]).houseElo;
      expect([for (final s in one.steps) s.match.sortKey], ['aaa', 'bbb', 'ccc']);
      expect([for (final s in two.steps) s.after], [for (final s in one.steps) s.after]);
    });

    test('Rechenzeit: 3000 Matches bleiben weit unter einer Sekunde', () {
      final t = DateTime(2020, 1, 1, 19);
      final rows = [
        for (var i = 0; i < 3000; i++)
          eloRow(EloKind.values[i % 3], t.add(Duration(hours: i)), opponent: 'Gegner ${i % 40}', botAverage: 40.0 + i % 40, won: i % 3 != 0, myAverage: 50 + i % 7),
      ];
      final calc = eloCalc(rows);
      final sw = Stopwatch()..start();
      final report = calc.houseElo;
      sw.stop();
      expect(report.matches, 3000);
      expect(sw.elapsedMilliseconds, lessThan(1000), reason: 'Dekodieren und Rechnen: ${sw.elapsedMilliseconds} ms');
    });
  });
}
