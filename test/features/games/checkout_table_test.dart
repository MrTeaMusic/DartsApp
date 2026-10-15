import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_calculator.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_table.dart';
import 'package:flutter_test/flutter_test.dart';

String names(List<Segment>? r) => r?.map((s) => s.name).join(' ') ?? '-';

/// Kleinste Dartzahl für ein Double-Out-Finish, unabhängig von der Tabelle.
int? minDarts(int score) {
  for (var d = 1; d <= 3; d++) {
    if (CheckoutCalculator.routes(score, darts: d, limit: 1).isNotEmpty) return d;
  }
  return null;
}

void main() {
  group('Checkout-Tabelle', () {
    test('jeder Eintrag ist ein gültiges Finish mit der kleinsten Dartzahl', () {
      for (final e in CheckoutTable.all.entries) {
        final route = e.value;
        expect(route, isNotEmpty, reason: '${e.key}');
        expect(route.length, lessThanOrEqualTo(3), reason: '${e.key}');
        expect(route.fold<int>(0, (s, d) => s + d.score), e.key, reason: '${e.key}: ${names(route)}');
        expect(route.last.isDouble, isTrue, reason: '${e.key}: ${names(route)}');
        expect(route.any((s) => s.isMiss), isFalse, reason: '${e.key}');
        expect(route.length, minDarts(e.key), reason: '${e.key}: ${names(route)}');
      }
    });

    test('alle checkbaren Reste 2–170 stehen drin, die Bogey-Zahlen nicht', () {
      for (var r = 2; r <= 170; r++) {
        final checkable = minDarts(r) != null;
        expect(CheckoutTable.all.containsKey(r), checkable, reason: '$r');
        expect(CheckoutCalculator.suggest(r), checkable ? isNotNull : isNull, reason: '$r');
      }
      for (final bogey in [159, 162, 163, 165, 166, 168, 169]) {
        expect(CheckoutCalculator.suggest(bogey), isNull);
      }
    });

    test('Stichproben wie auf dem Checkout-Chart', () {
      const expected = {
        170: 'T20 T20 BULL',
        167: 'T20 T19 BULL',
        164: 'T20 T18 BULL',
        161: 'T20 T17 BULL',
        160: 'T20 T20 D20',
        141: 'T20 T19 D12',
        121: 'T20 T11 D14',
        100: 'T20 D20',
        81: 'T19 D12',
        61: 'T15 D8',
        50: 'BULL',
        40: 'D20',
        32: 'D16',
        3: 'S1 D1',
      };
      for (final e in expected.entries) {
        expect(names(CheckoutCalculator.suggest(e.key)), e.value, reason: '${e.key}');
      }
    });

    test('Zwei-Dart-Vorschläge kommen aus der Tabelle, sonst kein Vorschlag', () {
      expect(names(CheckoutCalculator.suggest(100, darts: 2)), 'T20 D20');
      expect(names(CheckoutCalculator.suggest(110, darts: 2)), 'T20 BULL');
      expect(names(CheckoutCalculator.suggest(61, darts: 2)), 'T15 D8');
      expect(CheckoutCalculator.suggest(99, darts: 2), isNull);
      expect(CheckoutCalculator.suggest(121, darts: 2), isNull);
      expect(names(CheckoutCalculator.suggest(40, darts: 1)), 'D20');
      expect(CheckoutCalculator.suggest(61, darts: 1), isNull);
    });

    test('routes(): Tabellenweg zuerst, ohne Doppel', () {
      final r = CheckoutCalculator.routes(121, darts: 3);
      expect(names(r.first), 'T20 T11 D14');
      final keys = r.map((x) => [...x.take(x.length - 1).map((s) => s.name).toList()..sort(), x.last.name].join()).toList();
      expect(keys.toSet().length, keys.length);
      // Mit genau drei Darts hat 100 keinen Tabellenweg (der hat zwei Darts).
      expect(CheckoutCalculator.routes(100, darts: 3).first.length, 3);
    });

    test('Kostensuche meidet kleine ungerade Doppel, wenn es gängige gibt', () {
      for (var r = 41; r <= 170; r++) {
        for (var d = 2; d <= 3; d++) {
          final best = CheckoutCalculator.routes(r, darts: d, limit: 1);
          if (best.isEmpty) continue;
          final hasGood = CheckoutCalculator.routes(r, darts: d, limit: 400)
              .any((x) => const {20, 16, 8, 10, 12, 18, 25}.contains(x.last.number));
          if (hasGood) {
            expect(const {1, 2, 3, 5, 7, 9}.contains(best.first.last.number), isFalse, reason: '$r/$d: ${names(best.first)}');
          }
        }
      }
    });

    test('Master-Out und Straight-Out bleiben bei der Kostensuche', () {
      expect(names(CheckoutCalculator.suggest(60, darts: 1, masterOut: true)), 'T20');
      expect(names(CheckoutCalculator.suggest(60, darts: 1, doubleOut: false)), 'T20');
    });
  });
}
