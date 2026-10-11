import 'dart:convert';

import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/matches/data/match_store.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_result.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/matches/domain/x01_match.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

/// Wirft eine ganze Aufnahme und meldet danach den Takeout.
void visit(X01Match m, List<String> darts) {
  for (final n in darts) {
    m.throwDart(d(n));
  }
  m.endVisit();
}

/// 101 Double-Out in einer Aufnahme: T20, S9, D16.
const checkout101 = ['T20', 'S9', 'D16'];

void main() {
  group('X01Match', () {
    test('Spieler wechseln sich ab, Rest wird pro Spieler geführt', () {
      final m = X01Match(format: const MatchFormat(legsToWin: 1), playerCount: 2);
      expect(m.current, 0);
      visit(m, ['T20', 'T20', 'T20']);
      expect(m.players[0].remaining, 321);
      expect(m.current, 1);
      visit(m, ['S20', 'S1', 'S5']);
      expect(m.players[1].remaining, 475);
      expect(m.current, 0);
      expect(m.players[0].count180, 1);
      expect(m.players[0].average, 180);
      expect(m.players[1].average, 26);
    });

    test('Bust setzt den Rest zurück, beendet die Aufnahme und zählt 0 Punkte', () {
      final m = X01Match(format: const MatchFormat(startScore: 101, legsToWin: 1), playerCount: 2);
      visit(m, ['T20', 'S20', 'S1']); // 20 Rest
      visit(m, ['S1', 'S1', 'S1']);
      m.throwDart(d('S10'));
      final o = m.throwDart(d('S15')); // 20 - 10 - 15 < 0
      expect(o.counted, isTrue);
      expect(m.players[0].remaining, 20);
      expect(m.players[0].busts, 1);
      expect(m.visitClosed, isTrue);
      expect(m.visitBust, isTrue);
      expect(m.nextPlayer, 1);
      // Weitere Darts vor dem Takeout zählen nicht.
      expect(m.throwDart(d('D10')).counted, isFalse);
      expect(m.players[0].remaining, 20);
      m.endVisit();
      expect(m.current, 1);
      expect(m.players[0].points, 81);
      expect(m.players[0].darts, 5);
    });

    test('Double-Out: Rest 1 und Single auf 0 sind Bust, Double checkt', () {
      final m = X01Match(format: const MatchFormat(startScore: 40, legsToWin: 1), playerCount: 2);
      m.throwDart(d('S20'));
      m.throwDart(d('S20')); // 0 mit Single = Bust
      expect(m.players[0].remaining, 40);
      m.endVisit();
      visit(m, ['S19', 'S20']); // Rest 1 = Bust beim zweiten Dart
      expect(m.players[1].remaining, 40);
      m.throwDart(d('D20'));
      expect(m.finished, isTrue);
      expect(m.winner, 0);
      expect(m.players[0].highestFinish, 40);
    });

    test('Straight-Out erlaubt jedes Feld, Master-Out auch Triples', () {
      final s = X01Match(
        format: const MatchFormat(startScore: 20, outMode: OutMode.straight, legsToWin: 1),
        playerCount: 2,
      );
      s.throwDart(d('S20'));
      expect(s.winner, 0);
      final ms = X01Match(
        format: const MatchFormat(startScore: 60, outMode: OutMode.master, legsToWin: 1),
        playerCount: 2,
      );
      ms.throwDart(d('T20'));
      expect(ms.winner, 0);
    });

    test('Double-In: Punkte erst ab dem ersten Double', () {
      final m = X01Match(format: const MatchFormat(doubleIn: true, legsToWin: 1), playerCount: 2);
      visit(m, ['T20', 'D10', 'T20']);
      expect(m.players[0].remaining, 501 - 20 - 60);
      expect(m.players[0].darts, 3);
    });

    test('Legs: Anwurf wechselt, Sieger nach first to N', () {
      final m = X01Match(format: const MatchFormat(startScore: 101, legsToWin: 2), playerCount: 2);
      visit(m, checkout101);
      expect(m.events.isEmpty, isTrue);
      expect(m.players[0].legs, 1);
      expect(m.players[0].remaining, 101);
      // Leg 2: Spieler 1 hat Anwurf.
      expect(m.current, 1);
      expect(m.legStarter, 1);
      expect(m.legNumber, 2);
      visit(m, checkout101);
      expect(m.players[1].legs, 1);
      // Leg 3: wieder Spieler 0.
      expect(m.current, 0);
      m.throwDart(d('T20'));
      m.throwDart(d('S9'));
      m.throwDart(d('D16'));
      expect(m.events.map((e) => e.type), containsAll([MatchEventType.legWon, MatchEventType.matchWon]));
      expect(m.finished, isTrue);
      expect(m.winner, 0);
      expect(m.legs.length, 3);
      expect(m.players[0].bestLegDarts, 3);
      // Nach dem Sieg zählt nichts mehr.
      expect(m.throwDart(d('T20')).counted, isFalse);
      expect(m.endVisit(), isFalse);
    });

    test('Sätze: Legs je Satz, Anwurf je Satz wechselt, Sieger nach Sätzen', () {
      final m = X01Match(format: const MatchFormat(startScore: 101, legsToWin: 2, setsToWin: 2), playerCount: 2);
      // Satz 1: Spieler 0 gewinnt Leg 1 (eigener Anwurf) und Leg 3.
      visit(m, checkout101); // P0 1:0
      expect(m.current, 1);
      visit(m, ['S1', 'S1', 'S1']);
      visit(m, checkout101); // P0 2:0 -> Satz
      expect(m.players[0].sets, 1);
      expect(m.players[0].legs, 0);
      expect(m.players[1].legs, 0);
      expect(m.setNumber, 2);
      // Satz 2: Anwurf Spieler 1.
      expect(m.current, 1);
      visit(m, checkout101); // P1 1:0
      expect(m.current, 0); // Leg-Anwurf wechselt im Satz
      visit(m, checkout101); // P0 1:1
      expect(m.current, 1);
      visit(m, checkout101); // P1 2:1 -> Satz
      expect(m.players[1].sets, 1);
      // Satz 3: Anwurf wieder Spieler 0.
      expect(m.current, 0);
      visit(m, checkout101);
      visit(m, ['S1', 'S1', 'S1']);
      m.throwDart(d('T20'));
      m.throwDart(d('S9'));
      m.throwDart(d('D16'));
      expect(m.winner, 0);
      expect(m.players[0].sets, 2);
      expect(m.events.map((e) => e.type), containsAll([MatchEventType.setWon, MatchEventType.matchWon]));
    });

    test('Vergessener Takeout: vierter Dart gehört dem nächsten Spieler', () {
      final m = X01Match(format: const MatchFormat(legsToWin: 1), playerCount: 2);
      for (final n in ['S20', 'S20', 'S20']) {
        m.throwDart(d(n));
      }
      final o = m.throwDart(d('T20'));
      expect(o.player, 1);
      expect(o.visitSerial, 1);
      expect(m.players[1].remaining, 441);
    });

    test('Weiter nach einem Dart beendet die Aufnahme, Darts zählen nur geworfen', () {
      final m = X01Match(format: const MatchFormat(legsToWin: 1), playerCount: 2);
      m.throwDart(d('T20'));
      expect(m.endVisit(), isTrue);
      expect(m.current, 1);
      expect(m.players[0].darts, 1);
      expect(m.endVisit(), isFalse, reason: 'leere Aufnahme beendet nichts');
    });

    test('Checkout-Vorschlag kommt aus dem CheckoutCalculator', () {
      final m = X01Match(format: const MatchFormat(startScore: 170, legsToWin: 1), playerCount: 2);
      expect(m.suggestion, CheckoutRules.suggest(170, darts: 3, out: OutMode.double));
      m.throwDart(d('T20'));
      expect(m.suggestion, CheckoutRules.suggest(110, darts: 2, out: OutMode.double));
    });
  });

  group('MatchSession', () {
    const setup = MatchSetup(
      format: MatchFormat(startScore: 101, legsToWin: 1),
      players: [MatchPlayer.human('Ben', profileId: 1), MatchPlayer.bot('CPU', average: 60)],
    );

    test('Rückgängig nur für eigene Darts der laufenden Aufnahme', () {
      final s = MatchSession(setup);
      s.addDart(d('T20'));
      expect(s.canUndo, isTrue);
      expect(s.undoLastDart(), isTrue);
      expect(s.match.players[0].remaining, 101);
      s.addDart(d('S1'));
      s.addDart(d('S1'));
      s.addDart(d('S1'));
      s.endVisit();
      expect(s.canUndo, isFalse, reason: 'nach dem Takeout');
      s.addDart(d('S20')); // Bot
      expect(s.currentPlayer.isBot, isTrue);
      expect(s.canUndo, isFalse);
    });

    test('Korrektur rechnet das Match neu, Bot-Darts bleiben unverändert', () {
      final s = MatchSession(setup);
      for (final n in ['S20', 'S1', 'S1']) {
        s.addDart(d(n));
      }
      s.endVisit();
      for (final n in ['S5', 'S5', 'S5']) {
        s.addDart(d(n));
      }
      s.endVisit();
      expect(s.correctAt(3, d('T20')), isFalse, reason: 'Bot-Dart');
      expect(s.correctAt(0, d('T20')), isTrue);
      expect(s.match.players[0].remaining, 101 - 62);
      expect(s.match.players[1].remaining, 86);
      expect(s.records.where((r) => r.player == 1).length, 3);
    });

    test('Speichern und Wiederherstellen ergibt denselben Stand', () {
      final s = MatchSession(setup);
      for (final n in ['T20', 'S1', 'S1']) {
        s.addDart(d(n));
      }
      s.endVisit();
      s.addDart(d('T19'));
      final saved = SavedMatch(setup: setup, inputs: s.inputs, sessionIds: const {0: 7});
      final back = SavedMatch.fromJson(jsonDecode(jsonEncode(saved.toJson())))!;
      expect(back.sessionIds, {0: 7});
      expect(back.setup.players[1].botAverage, 60);
      final r = MatchSession.restore(back.setup, back.inputs);
      expect(r.match.players[0].remaining, s.match.players[0].remaining);
      expect(r.match.players[1].remaining, 101 - 57);
      expect(r.match.current, 1);
      expect(r.records.length, 4);
    });

    test('Ergebnis enthält nur die eigenen Darts', () {
      final s = MatchSession(setup);
      for (final n in ['T20', 'S1', 'S1']) {
        s.addDart(d(n));
      }
      s.endVisit();
      for (final n in ['S5', 'S5', 'S5']) {
        s.addDart(d(n));
      }
      s.endVisit();
      for (final n in ['S19', 'D10']) {
        s.addDart(d(n));
      }
      final result = matchResultFor(s.match, 0, setup);
      expect(result.metrics['darts'], 5);
      expect(result.metrics['average'], closeTo(101 / 5 * 3, 0.001));
      expect(result.metrics['won'], 1);
      expect(result.metrics['highestCheckout'], 39);
      expect(result.details['opponents'], ['CPU']);
      expect(matchResultFor(s.match, 1, setup).metrics['darts'], 3);
    });
  });
}
