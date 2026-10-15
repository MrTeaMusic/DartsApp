import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_calculator.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/quiz/domain/checkout_route.dart';
import 'package:flutter_test/flutter_test.dart';

List<Segment> r(String names) => [for (final n in names.split(' ')) Segment.tryParse(n)!];

/// Alle treffbaren Felder (ohne Miss).
final List<Segment> allFields = [
  for (var n = 1; n <= 20; n++) ...[Segment.single(n), Segment.double(n), Segment.triple(n)],
  Segment.outerBull,
  Segment.bull,
];

void main() {
  const d = OutMode.double;

  group('Mögliche Reste', () {
    test('mit drei Darts gehen alle Reste 2–170 außer den Bogeys', () {
      final impossible = [for (var s = 2; s <= 170; s++) if (!CheckoutRoutes.possible(s, 3, d)) s];
      expect(impossible, [159, 162, 163, 165, 166, 168, 169]);
    });

    test('mit zwei Darts höchstens 110, mit einem nur Doppel und Bull', () {
      expect(CheckoutRoutes.possible(110, 2, d), isTrue);
      expect(CheckoutRoutes.possible(111, 2, d), isFalse);
      expect(CheckoutRoutes.possible(99, 2, d), isFalse);
      final one = [for (var s = 2; s <= 170; s++) if (CheckoutRoutes.possible(s, 1, d)) s];
      expect(one, [for (var v = 2; v <= 40; v += 2) v, 50]);
    });
  });

  group('Wege prüfen', () {
    test('Vorschlag und Alternativen sind für jeden Rest 2–170 gültig', () {
      for (var darts = 1; darts <= 3; darts++) {
        for (var s = 2; s <= 170; s++) {
          final rec = CheckoutRoutes.recommended(s, darts, d);
          if (rec == null) continue;
          final check = CheckoutRoutes.check(s, darts, rec, d);
          expect(check.valid, isTrue, reason: '$s/$darts $rec');
          expect(check.recommended, isTrue, reason: '$s/$darts');
          for (final alt in CheckoutRoutes.alternatives(s, darts, d)) {
            final c = CheckoutRoutes.check(s, darts, alt, d);
            expect(c.valid, isTrue, reason: '$s/$darts alt $alt');
            expect(c.recommended, isFalse, reason: '$s/$darts alt $alt');
          }
        }
      }
    });

    test('jeder Zwei-Dart-Weg wird wie eine unabhängige Regel bewertet', () {
      for (var s = 2; s <= 170; s++) {
        for (final a in allFields) {
          for (final b in allFields) {
            final expected = a.score + b.score == s && b.isDouble && s - a.score >= 2;
            expect(CheckoutRoutes.check(s, 2, [a, b], d).valid, expected, reason: '$s: $a $b');
          }
        }
      }
    });

    test('jeder gültige Weg zählt, nicht nur der Vorschlag', () {
      final c = CheckoutRoutes.check(40, 3, r('S20 D10'), d);
      expect(c.valid, isTrue);
      expect(c.recommended, isFalse);
      expect(CheckoutRoutes.check(40, 3, r('D20'), d).recommended, isTrue);
      expect(CheckoutRoutes.check(121, 3, r('T17 T18 D8'), d).valid, isTrue);
    });

    test('Reihenfolge der Aufbau-Darts ist egal, das Finish nicht', () {
      final rec = CheckoutRoutes.recommended(170, 3, d)!;
      expect(rec.map((s) => s.name), ['T20', 'T20', 'BULL']);
      expect(CheckoutRoutes.check(167, 3, r('T19 T20 BULL'), d).recommended, isTrue);
      expect(CheckoutRoutes.check(167, 3, r('T20 T19 BULL'), d).recommended, isTrue);
      expect(CheckoutRoutes.check(170, 3, r('BULL T20 T20'), d).problem, RouteProblem.finish);
    });

    test('Bull-Finish', () {
      expect(CheckoutRoutes.check(50, 1, r('BULL'), d).valid, isTrue);
      expect(CheckoutRoutes.check(75, 2, r('25 BULL'), d).valid, isTrue);
      expect(CheckoutRoutes.check(25, 1, r('25'), d).problem, RouteProblem.finish);
      expect(CheckoutRoutes.check(100, 2, r('BULL BULL'), d).valid, isTrue);
    });

    test('falsche Summe, Bust, Single-Finish, zu viele Darts', () {
      final total = CheckoutRoutes.check(100, 3, r('T20 D19'), d);
      expect(total.problem, RouteProblem.total);
      expect(total.sum, 98);
      expect(CheckoutRoutes.check(32, 3, r('T20 D16'), d).problem, RouteProblem.bust);
      // Rest 1 nach dem zweiten Dart ist ein Bust.
      expect(CheckoutRoutes.check(41, 3, r('S20 S20 S1'), d).problem, RouteProblem.bust);
      expect(CheckoutRoutes.check(60, 3, r('S20 S20 S20'), d).problem, RouteProblem.finish);
      expect(CheckoutRoutes.check(40, 3, r('D10 D10 D10'), d).problem, RouteProblem.bust);
      expect(CheckoutRoutes.check(100, 1, r('T20 D20'), d).problem, RouteProblem.tooManyDarts);
      expect(CheckoutRoutes.check(40, 3, const [], d).problem, RouteProblem.empty);
      expect(CheckoutRoutes.check(40, 3, [Segment.miss, Segment.double(20)], d).problem, RouteProblem.miss);
    });

    test('Bogeys lassen sich nicht checken', () {
      for (final s in [159, 162, 163, 165, 166, 168, 169]) {
        expect(CheckoutRoutes.check(s, 3, r('T20 T20 BULL'), d).valid, isFalse);
        expect(CheckoutRoutes.recommended(s, 3, d), isNull);
        expect(CheckoutRoutes.alternatives(s, 3, d), isEmpty);
      }
    });

    test('Master-Out erlaubt ein Triple als letzten Dart', () {
      expect(CheckoutRoutes.check(60, 1, r('T20'), OutMode.master).valid, isTrue);
      expect(CheckoutRoutes.check(60, 1, r('T20'), d).valid, isFalse);
      expect(CheckoutRoutes.possible(180, 3, OutMode.master), isTrue);
    });

    test('sameRoute vergleicht Felder ohne Reihenfolge der Aufbau-Darts', () {
      expect(CheckoutRoutes.sameRoute(r('T20 T19 D12'), r('T19 T20 D12')), isTrue);
      expect(CheckoutRoutes.sameRoute(r('T20 T19 D12'), r('T20 D12 T19')), isFalse);
      expect(CheckoutRoutes.sameRoute([Segment.single(20, inner: true), Segment.double(10)], r('S20 D10')), isTrue);
    });

    test('Alternativen füllen mit einem Dart mehr auf', () {
      final alts = CheckoutRoutes.alternatives(40, 3, d);
      expect(alts, isNotEmpty);
      expect(alts.every((a) => a.length == 2), isTrue);
      final calc = CheckoutCalculator.routes(121, darts: 3);
      expect(calc.first.map((s) => s.name), CheckoutRoutes.recommended(121, 3, d)!.map((s) => s.name));
    });
  });

  group('Stellen', () {
    test('169 mit drei Darts: guter Rest ist gut, schlechter nicht', () {
      final good = CheckoutRoutes.checkSetup(169, 3, r('T20 T20 S9'), d);
      expect(good.valid, isTrue);
      expect(good.leave, 40);
      expect(good.tier, 1);
      expect(good.good, isTrue);
      // Rest 42 braucht zwei Darts, der Vorschlag lässt ein Doppel stehen.
      expect(CheckoutRoutes.checkSetup(169, 3, r('T20 T19 S10'), d).good, isFalse);
      final weak = CheckoutRoutes.checkSetup(169, 3, r('S1'), d);
      expect(weak.leave, 168);
      expect(weak.good, isFalse);
      final bust = CheckoutRoutes.checkSetup(169, 3, r('T20 T20 T20'), d);
      expect(bust.problem, RouteProblem.bust);
      expect(bust.good, isFalse);
    });

    test('Vorschlag des Setup-Beraters gilt als empfohlen', () {
      final advice = CheckoutRoutes.setupAdvice(41, 1, d)!;
      final check = CheckoutRoutes.checkSetup(41, 1, advice.darts, d);
      expect(check.recommended, isTrue);
      expect(check.good, isTrue);
      expect(CheckoutRoutes.checkSetup(41, 1, r('S1'), d).good, isTrue, reason: 'Rest 40 ist ebenso ein Ein-Dart-Finish');
      expect(CheckoutRoutes.checkSetup(41, 1, r('S20'), d).good, isFalse, reason: 'Rest 21 braucht zwei Darts');
      expect(CheckoutRoutes.checkSetup(41, 1, r('S1 S1'), d).problem, RouteProblem.tooManyDarts);
    });

    test('Jeder nicht checkbare Rest 2–170 hat einen Stell-Vorschlag', () {
      for (var darts = 1; darts <= 3; darts++) {
        for (var s = 3; s <= 170; s++) {
          if (CheckoutRoutes.possible(s, darts, d)) continue;
          final advice = CheckoutRoutes.setupAdvice(s, darts, d);
          expect(advice, isNotNull, reason: '$s/$darts');
          expect(CheckoutRoutes.checkSetup(s, darts, advice!.darts, d).good, isTrue, reason: '$s/$darts');
        }
      }
    });

    test('leaveTier', () {
      expect(leaveTier(32, d), 1);
      expect(leaveTier(50, d), 1);
      expect(leaveTier(61, d), 2);
      expect(leaveTier(121, d), 3);
      expect(leaveTier(169, d), 4);
    });
  });
}
