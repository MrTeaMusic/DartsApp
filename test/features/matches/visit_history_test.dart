import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/engine/game_session.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/matches/domain/visit_history.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

MatchSession match({
  int start = 301,
  int legs = 2,
  bool doubleIn = false,
  int players = 2,
}) => MatchSession(
  MatchSetup(
    format: MatchFormat(startScore: start, legsToWin: legs, doubleIn: doubleIn),
    players: [for (var i = 0; i < players; i++) MatchPlayer.human('P$i')],
  ),
);

/// Wirft eine Aufnahme und beendet sie mit dem Takeout.
void visit(MatchSession s, List<String> darts) {
  for (final n in darts) {
    s.addDart(d(n));
  }
  s.endVisit();
}

List<(int, int)> pr(List<VisitRow> rows) => [for (final r in rows) (r.points, r.remaining)];

void main() {
  group('VisitHistory im Match', () {
    test('Aufnahmen je Spieler: Punkte und Rest danach, älteste zuerst', () {
      final s = match();
      visit(s, ['T20', 'T20', 'S5']); // P0 125
      visit(s, ['S20', 'S1', 'S5']); // P1 26
      visit(s, ['S20', 'S20', 'S19']); // P0 59
      final h = VisitHistory.ofMatch(s);
      expect(pr(h.legRowsOf(0)), [(125, 176), (59, 117)]);
      expect(pr(h.legRowsOf(1)), [(26, 275)]);
      expect(h.currentLeg, 1);
      expect(h.legRowsOf(0).first.darts.map((x) => x.name), ['T20', 'T20', 'S5']);
      expect(h.legRowsOf(0).map((r) => r.visit), [0, 2]);
      expect(h.legRowsOf(0).every((r) => !r.bust && !r.checkout), isTrue);
    });

    test('die laufende Aufnahme steht noch nicht in der Tabelle', () {
      final s = match();
      visit(s, ['T20', 'T20', 'S5']);
      visit(s, ['S20', 'S1', 'S5']);
      s.addDart(d('T19'));
      s.addDart(d('T19'));
      expect(VisitHistory.ofMatch(s).legRowsOf(0), hasLength(1));
      // Dritter Dart schließt die Aufnahme (Takeout steht noch aus): jetzt zählt sie.
      s.addDart(d('S19'));
      expect(pr(VisitHistory.ofMatch(s).legRowsOf(0)), [(125, 176), (133, 43)]);
    });

    test('vorzeitiges Ende per Takeout: Aufnahme mit weniger als drei Darts', () {
      final s = match();
      visit(s, ['T20', 'S5']);
      final row = VisitHistory.ofMatch(s).legRowsOf(0).single;
      expect(row.darts, hasLength(2));
      expect((row.points, row.remaining), (65, 236));
    });

    test('Bust: 0 Punkte, Rest bleibt, ignorierte Darts fehlen in der Aufnahme', () {
      final s = match(start: 101);
      visit(s, ['T20', 'S20', 'S1']); // P0 81 -> 20
      visit(s, ['S1', 'S1', 'S1']); // P1
      s.addDart(d('S10'));
      s.addDart(d('S15')); // 20 - 10 - 15: Bust
      s.addDart(d('D10')); // zählt nicht mehr
      s.endVisit();
      final rows = VisitHistory.ofMatch(s).legRowsOf(0);
      expect(rows, hasLength(2));
      final bust = rows.last;
      expect(bust.bust, isTrue);
      expect(bust.points, 0);
      expect(bust.remaining, 20, reason: 'der Rest vor der Aufnahme bleibt stehen');
      expect(bust.darts.map((x) => x.name), ['S10', 'S15']);
      expect(bust.checkout, isFalse);
      // Der Rest des Spielers bleibt auch in der Engine bei 20.
      expect(s.match.players[0].remaining, 20);
    });

    test('Double-Out: Single auf 0 und Rest 1 sind Bust', () {
      final s = match(start: 40);
      visit(s, ['S20', 'S20']); // 0 mit Single = Bust
      expect(VisitHistory.ofMatch(s).legRowsOf(0).single.bust, isTrue);
      visit(s, ['S19', 'S20']); // Rest 1 = Bust
      final p1 = VisitHistory.ofMatch(s).legRowsOf(1).single;
      expect((p1.bust, p1.points, p1.remaining), (true, 0, 40));
    });

    test('Straight-Out: Single auf 0 ist ein Checkout', () {
      final s = MatchSession(
        const MatchSetup(
          format: MatchFormat(startScore: 40, outMode: OutMode.straight, legsToWin: 1),
          players: [MatchPlayer.human('A'), MatchPlayer.human('B')],
        ),
      );
      visit(s, ['S20', 'S20']);
      final row = VisitHistory.ofMatch(s).legRowsOf(0).single;
      expect((row.checkout, row.bust, row.points, row.remaining), (true, false, 40, 0));
    });

    test('Checkout: Zeile mit Rest 0, Leg bleibt bis zum nächsten Dart sichtbar', () {
      final s = match(start: 101);
      visit(s, ['S20', 'S20', 'S1']); // P0 41 -> 60
      visit(s, ['S1', 'S1', 'S1']); // P1
      s.addDart(d('S20'));
      s.addDart(d('D20')); // 60 -> 0: Leg
      var h = VisitHistory.ofMatch(s);
      expect(s.match.legs, hasLength(1));
      expect(h.currentLeg, 1, reason: 'das gewonnene Leg bleibt stehen');
      final last = h.legRowsOf(0).last;
      expect((last.checkout, last.points, last.remaining), (true, 60, 0));
      expect(last.bust, isFalse);
      // Die Engine ist schon im nächsten Leg: alle wieder auf 101.
      expect(s.match.players.map((p) => p.remaining), [101, 101]);
      // Erst der erste Dart des neuen Legs setzt die Tabelle zurück.
      s.endVisit();
      expect(VisitHistory.ofMatch(s).currentLeg, 1);
      s.addDart(d('T20'));
      s.addDart(d('S1'));
      s.addDart(d('S1'));
      h = VisitHistory.ofMatch(s);
      expect(h.currentLeg, 2);
      expect(pr(h.legRowsOf(1)), [(62, 39)]);
      expect(h.legRowsOf(0), isEmpty, reason: 'P0 hat im neuen Leg noch nichts geworfen');
      // Die Aufnahmen des alten Legs bleiben in rows (für spätere Auswertungen).
      expect(h.rows.where((r) => r.leg == 1), hasLength(3));
    });

    test('Legwechsel: die erste Aufnahme im neuen Leg rechnet vom Startwert, nicht vom alten Rest', () {
      final s = match(start: 101, legs: 3);
      visit(s, ['T20', 'S9', 'D16']); // P0: Leg 1 in einer Aufnahme, Rest 0
      visit(s, ['T20', 'S1', 'S1']); // P1 beginnt Leg 2
      visit(s, ['S20', 'S20', 'S20']); // P0: 60 vom Startwert 101
      final h = VisitHistory.ofMatch(s);
      expect(h.currentLeg, 2);
      expect(pr(h.legRowsOf(1)), [(62, 39)]);
      expect(pr(h.legRowsOf(0)), [(60, 41)]);
    });

    test('Double-In: Darts vor dem ersten Double zählen 0 Punkte', () {
      final s = match(doubleIn: true);
      visit(s, ['T20', 'S5', 'S1']); // kein Double: 0 Punkte
      visit(s, ['T20', 'D10', 'S5']); // P1: D10 öffnet, S5 zählt
      final h = VisitHistory.ofMatch(s);
      expect((h.legRowsOf(0).single.points, h.legRowsOf(0).single.remaining, h.legRowsOf(0).single.bust), (0, 301, false));
      expect(h.legRowsOf(1).single.points, 25);
      expect(h.legRowsOf(1).single.remaining, 276);
      // Die nächste Aufnahme von P1 rechnet vom Rest 276.
      visit(s, ['S1', 'S1', 'S1']);
      visit(s, ['T20', 'S1', 'S1']);
      expect(pr(VisitHistory.ofMatch(s).legRowsOf(1)), [(25, 276), (62, 214)]);
    });

    test('Rückgängig: die Aufnahme verschwindet, die Tabelle folgt den Aufzeichnungen', () {
      final s = match();
      visit(s, ['T20', 'T20', 'S5']);
      s.addDart(d('S20'));
      s.addDart(d('S20'));
      s.addDart(d('S20'));
      expect(VisitHistory.ofMatch(s).legRowsOf(1), hasLength(1));
      expect(s.undoLastDart(), isTrue);
      expect(VisitHistory.ofMatch(s).legRowsOf(1), isEmpty, reason: 'wieder offene Aufnahme');
      s.addDart(d('S19'));
      expect(pr(VisitHistory.ofMatch(s).legRowsOf(1)), [(59, 242)]);
    });

    test('Korrektur eines früheren Darts rechnet alle folgenden Zeilen neu', () {
      final s = match();
      visit(s, ['S20', 'S20', 'S20']); // P0 60
      visit(s, ['S1', 'S1', 'S1']);
      visit(s, ['S20', 'S20', 'S20']); // P0 60
      expect(pr(VisitHistory.ofMatch(s).legRowsOf(0)), [(60, 241), (60, 181)]);
      expect(s.correctAt(0, d('T20')), isTrue);
      expect(pr(VisitHistory.ofMatch(s).legRowsOf(0)), [(100, 201), (60, 141)]);
    });

    test('Korrektur macht aus einer Aufnahme einen Bust', () {
      final s = match(start: 101);
      visit(s, ['T20', 'S20', 'S1']); // 81 -> 20
      visit(s, ['S1', 'S1', 'S1']);
      visit(s, ['S10', 'S5', 'S1']); // 20 -> 4
      expect(pr(VisitHistory.ofMatch(s).legRowsOf(0)), [(81, 20), (16, 4)]);
      // Der erste Dart der zweiten Aufnahme war ein T20: 20 - 60 ist Bust.
      expect(s.correctAt(6, d('T20')), isTrue);
      final rows = VisitHistory.ofMatch(s).legRowsOf(0);
      expect(pr(rows), [(81, 20), (0, 20)]);
      expect(rows.last.bust, isTrue);
      expect(rows.last.darts.map((x) => x.name), ['T20']);
    });

    test('Drei Spieler: Zeilen bleiben beim eigenen Spieler', () {
      final s = match(players: 3);
      visit(s, ['S20', 'S20', 'S20']);
      visit(s, ['S19', 'S19', 'S19']);
      visit(s, ['S18', 'S18', 'S18']);
      visit(s, ['T20', 'S1', 'S1']);
      final h = VisitHistory.ofMatch(s);
      expect([for (var i = 0; i < 3; i++) pr(h.legRowsOf(i))], [
        [(60, 241), (62, 179)],
        [(57, 244)],
        [(54, 247)],
      ]);
    });

    test('Ohne Darts: leere Tabelle in Leg 1', () {
      final h = VisitHistory.ofMatch(match());
      expect(h.rows, isEmpty);
      expect(h.currentLeg, 1);
      expect(h.legRowsOf(0), isEmpty);
      expect(VisitHistory.empty.currentLeg, 1);
    });

    test('Match gewonnen: das letzte Leg bleibt mit der Checkout-Zeile stehen', () {
      final s = match(start: 101, legs: 1);
      visit(s, ['T20', 'S9', 'D16']);
      expect(s.match.finished, isTrue);
      final h = VisitHistory.ofMatch(s);
      expect(h.legRowsOf(0).single.checkout, isTrue);
      expect(h.currentLeg, 1);
    });
  });

  group('Dart-Ergebnis der Engine', () {
    test('remaining und bust kommen aus der Engine', () {
      final s = match(start: 101, legs: 3);
      s.addDart(d('T20'));
      s.addDart(d('S20'));
      s.addDart(d('S1'));
      expect(s.records.map((r) => r.outcome.remaining), [41, 21, 20]);
      expect(s.records.map((r) => r.outcome.bust), [false, false, false]);
      s.endVisit();
      s.addDart(d('S1'));
      s.endVisit();
      s.addDart(d('S10'));
      s.addDart(d('S15'));
      s.addDart(d('D10')); // ignoriert
      final tail = s.records.skip(4).toList();
      expect(tail.map((r) => r.outcome.remaining), [10, 20, 20]);
      expect(tail.map((r) => r.outcome.bust), [false, true, false]);
      expect(tail.map((r) => r.counted), [true, true, false]);
    });

    test('der Checkout-Dart meldet Rest 0, obwohl die Engine schon das nächste Leg vorbereitet', () {
      final s = match(start: 40, legs: 2);
      s.addDart(d('D20'));
      expect(s.records.single.outcome.remaining, 0);
      expect(s.match.players[0].remaining, 40);
    });
  });

  group('VisitHistory im X01-Solo', () {
    GameSession solo({int start = 101, bool doubleIn = false, int legs = 1, int limit = 0}) => GameSession(
      definition: X01Solo.definition,
      config: {'startScore': start, 'legs': legs, 'dartLimit': limit, 'inMode': doubleIn ? 'double' : 'straight'},
      seed: 1,
    );

    void throwVisit(GameSession s, List<String> darts, {bool end = true}) {
      for (final n in darts) {
        s.addDart(d(n));
      }
      if (end) s.endVisit();
    }

    VisitHistory history(GameSession s) => VisitHistory.ofSolo(s, s.game as X01Solo);

    test('Aufnahmen mit Punkten, Darts, Rest und Bust', () {
      final s = solo();
      throwVisit(s, ['T20', 'S20', 'S1']); // 81 -> 20
      throwVisit(s, ['S10', 'S15']); // Bust
      throwVisit(s, ['S5', 'S5', 'S5']); // 15 -> 5
      final rows = history(s).legRowsOf(0);
      expect(pr(rows), [(81, 20), (0, 20), (15, 5)]);
      expect(rows.map((r) => r.bust), [false, true, false]);
      expect(rows[1].darts.map((x) => x.name), ['S10', 'S15']);
      expect(rows.map((r) => r.visit), [0, 1, 2]);
    });

    test('Checkout beendet das Leg, nächstes Leg setzt zurück', () {
      final s = solo(start: 41, legs: 2);
      throwVisit(s, ['S1', 'S20', 'D10']); // Checkout 41
      var h = history(s);
      expect(h.legRowsOf(0).single.checkout, isTrue);
      expect(h.currentLeg, 1);
      throwVisit(s, ['S20', 'S1']);
      h = history(s);
      expect(h.currentLeg, 2);
      expect(pr(h.legRowsOf(0)), [(21, 20)]);
    });

    test('Double-In: Darts vor dem ersten Double zählen 0', () {
      final s = solo(doubleIn: true);
      throwVisit(s, ['T20', 'S5', 'S1']);
      throwVisit(s, ['T20', 'D10', 'S5']);
      expect(pr(history(s).legRowsOf(0)), [(0, 101), (25, 76)]);
    });

    test('Rückgängig und Korrektur', () {
      final s = solo();
      throwVisit(s, ['T20', 'S20', 'S1'], end: false);
      expect(history(s).legRowsOf(0), hasLength(1));
      expect(s.undoLastDart(), isTrue);
      expect(history(s).legRowsOf(0), isEmpty);
      s.addDart(d('S2'));
      expect(pr(history(s).legRowsOf(0)), [(82, 19)]);
      expect(s.correctAt(0, d('S20')), isTrue);
      expect(pr(history(s).legRowsOf(0)), [(42, 59)]);
    });

    test('Dart-Limit: verlorenes Leg beendet die Zeile ohne Checkout', () {
      final s = solo(start: 301, legs: 2, limit: 3);
      throwVisit(s, ['S1', 'S1', 'S1']);
      final h = history(s);
      final row = h.legRowsOf(0).single;
      expect((row.checkout, row.points, row.remaining), (false, 3, 298));
      expect(h.currentLeg, 1);
    });
  });

  test('VisitHistory.from: nur gezählte Darts, offene Aufnahme wird übersprungen', () {
    VisitDart dart(int visit, String name, int remaining, {bool counted = true, bool bust = false, int player = 0}) =>
        VisitDart(
          player: player,
          leg: 1,
          visit: visit,
          counted: counted,
          segment: Segment.tryParse(name)!,
          remaining: remaining,
          bust: bust,
        );
    final h = VisitHistory.from(
      [dart(0, 'S20', 481), dart(0, 'S20', 461), dart(0, 'S20', 441, counted: false), dart(1, 'T20', 401)],
      startScore: 501,
      openVisit: 1,
    );
    expect(pr(h.legRowsOf(0)), [(40, 461)]);
    expect(h.rows.single.darts, hasLength(2));
    final closed = VisitHistory.from([dart(1, 'T20', 401)], startScore: 501);
    expect(pr(closed.legRowsOf(0)), [(100, 401)]);
  });
}
