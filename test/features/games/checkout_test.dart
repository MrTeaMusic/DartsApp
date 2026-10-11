import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_calculator.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_training.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

List<String> names(List<Segment>? s) => [for (final x in s ?? const <Segment>[]) x.name];

void main() {
  group('CheckoutCalculator', () {
    test('klassische Finishes', () {
      expect(names(CheckoutCalculator.suggest(170)), ['T20', 'T20', 'BULL']);
      expect(names(CheckoutCalculator.suggest(167)), ['T20', 'T19', 'BULL']);
      expect(names(CheckoutCalculator.suggest(160)), ['T20', 'T20', 'D20']);
      expect(names(CheckoutCalculator.suggest(100)), ['T20', 'D20']);
      expect(names(CheckoutCalculator.suggest(60)), ['S20', 'D20']);
      expect(names(CheckoutCalculator.suggest(40)), ['D20']);
      expect(names(CheckoutCalculator.suggest(32)), ['D16']);
      expect(names(CheckoutCalculator.suggest(50)), ['BULL']);
      expect(names(CheckoutCalculator.suggest(3)), ['S1', 'D1']);
    });

    test('keine Finishes für Bogey-Zahlen und Rest 1', () {
      for (final v in [169, 168, 166, 165, 163, 162, 159, 171, 1, 0]) {
        expect(CheckoutCalculator.suggest(v), isNull, reason: '$v');
      }
    });

    test('jeder Vorschlag ist gültig und minimal', () {
      for (var v = 2; v <= 170; v++) {
        final s = CheckoutCalculator.suggest(v);
        if (s == null) continue;
        expect(s.fold<int>(0, (a, b) => a + b.score), v, reason: '$v');
        expect(s.last.isDouble, isTrue, reason: '$v');
        expect(s.length, lessThanOrEqualTo(3));
        if (s.length > 1) {
          expect(CheckoutCalculator.suggest(v, darts: s.length - 1), isNull, reason: '$v geht mit weniger Darts');
        }
      }
    });

    test('weniger Darts übrig schränkt ein', () {
      expect(CheckoutCalculator.suggest(100, darts: 1), isNull);
      expect(names(CheckoutCalculator.suggest(36, darts: 1)), ['D18']);
      expect(CheckoutCalculator.isCheckout(121, darts: 2), isFalse);
      expect(CheckoutCalculator.isCheckout(121, darts: 3), isTrue);
    });

    test('Single-Out erlaubt jedes Feld als letzten Dart', () {
      expect(names(CheckoutCalculator.suggest(1, doubleOut: false)), ['S1']);
      expect(names(CheckoutCalculator.suggest(60, doubleOut: false)), ['T20']);
      expect(CheckoutCalculator.suggest(180, doubleOut: false), isNotNull);
    });

    test('Zielliste', () {
      final t = CheckoutCalculator.checkoutTargets();
      expect(t.first, 2);
      expect(t.last, 170);
      expect(t, isNot(contains(169)));
      expect(t, hasLength(169 - 7));
    });
  });

  group('CheckoutTraining', () {
    CheckoutTraining game({int min = 40, int max = 40, int attempts = 3, int visits = 1, bool doubleOut = true}) =>
        CheckoutTraining(seed: 1, min: min, max: max, attempts: attempts, visitsPerAttempt: visits, doubleOut: doubleOut)..prepare();

    test('Checkout mit Doppel', () {
      final g = game();
      expect(g.target, 40);
      throwAll(g, ['S20', 'D10']);
      expect(g.results.single.success, isTrue);
      expect(g.results.single.darts, 2);
      expect(g.events.first.type, GameEventType.checkout);
      expect(g.remaining, 40, reason: 'nächstes Ziel');
    });

    test('Rest 0 ohne Doppel ist Bust, Rest springt zurück', () {
      final g = game();
      throwAll(g, ['S20', 'S20']);
      expect(g.events.map((e) => e.type), contains(GameEventType.bust));
      expect(g.results.single.success, isFalse);
      expect(g.results.single.darts, 3);
    });

    test('Rest 1 und Überwerfen sind Bust', () {
      final g = game(visits: 2);
      throwAll(g, ['S19', 'S20']);
      expect(g.remaining, 40);
      expect(g.results, isEmpty, reason: 'zweite Aufnahme bleibt');
      throwAll(g, ['MISS']); // ignoriert, Aufnahme war schon zu
      throwAll(g, ['T20']); // neue Aufnahme
      expect(g.remaining, 40);
      expect(g.results.single.success, isFalse);
      expect(g.results.single.darts, 6);
    });

    test('mehrere Aufnahmen pro Versuch, Darts werden gezählt', () {
      final g = game(min: 81, max: 81, visits: 2);
      throwAll(g, ['S1', 'S1', 'S1']);
      expect(g.remaining, 78);
      throwAll(g, ['T20', 'D9']);
      expect(g.results.single.success, isTrue);
      expect(g.results.single.darts, 5);
    });

    test('Spiel endet nach allen Versuchen, Ergebnis', () {
      final g = game(attempts: 2);
      throwAll(g, ['D20', 'S20']);
      expect(g.ignoredDarts, 1, reason: 'nach dem Checkout zählt die Aufnahme nicht weiter');
      g.endVisit();
      throwAll(g, ['MISS', 'MISS', 'MISS']);
      expect(g.finished, isTrue);
      final r = g.result;
      expect(r.metrics['attempts'], 2);
      expect(r.metrics['checkouts'], 1);
      expect(r.metrics['checkoutRate'], 0.5);
      expect(r.metrics['highestCheckout'], 40);
      expect((r.details['attempts']! as List).length, 2);
    });

    test('Vorschlag passt sich an die restlichen Darts an', () {
      final g = game(min: 100, max: 100);
      expect(names(g.suggestion), ['T20', 'D20']);
      expect(g.targets, {Segment.triple(20)});
      throwAll(g, ['S20']);
      expect(names(g.suggestion), ['T20', 'D10']);
      throwAll(g, ['S20']);
      expect(g.suggestion, isNull, reason: '60 mit einem Dart geht nicht');
      expect(g.targets, isEmpty);
    });

    test('Zufallsziele liegen im Bereich und wiederholen sich nicht direkt', () {
      final g = game(min: 100, max: 110, attempts: 20);
      final seen = <int>[];
      for (var i = 0; i < 10; i++) {
        seen.add(g.target);
        throwAll(g, ['MISS', 'MISS', 'MISS']);
      }
      expect(seen.every((v) => v >= 100 && v <= 110), isTrue);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], isNot(seen[i - 1]));
      }
    });

    test('absteigender Modus und schwache Werte', () {
      final desc = CheckoutTraining(seed: 1, mode: CheckoutMode.descending, min: 158, max: 161)..prepare();
      final order = <int>[];
      for (var i = 0; i < 3; i++) {
        order.add(desc.target);
        throwAll(desc, ['MISS', 'MISS', 'MISS']);
      }
      expect(order, [161, 160, 158]);

      final weak = CheckoutTraining(seed: 3, mode: CheckoutMode.weak, min: 2, max: 170, attempts: 50, weakTargets: const [87])..prepare();
      var hits = 0;
      for (var i = 0; i < 20; i++) {
        if (weak.target == 87) hits++;
        throwAll(weak, ['MISS', 'MISS', 'MISS']);
      }
      expect(hits, greaterThan(5));
    });

    test('Definition bereinigt min/max', () {
      final c = CheckoutTraining.definition.resolve({'min': 120, 'max': 60});
      expect(c['min'], 60);
      expect(c['max'], 120);
      final g = CheckoutTraining.definition.start({'dartsPerAttempt': 9}, 1) as CheckoutTraining;
      expect(g.visitsPerAttempt, 3);
    });
  });
}
