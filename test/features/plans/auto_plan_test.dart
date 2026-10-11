import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/plans/domain/auto_plan.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Viele Darts, alle Doubles bei rund 25 %, D16 bei 18 %.
AutoPlanInput weakD16({Map<int, HitCount>? extraDoubles}) => AutoPlanInput(
      days: 30,
      sessions: 12,
      darts: 1500,
      doubles: {
        for (var n = 1; n <= 20; n++) n: const HitCount(40, 10),
        16: const HitCount(60, 11),
        ...?extraDoubles,
      },
      doubleRate: 0.24,
      doubleAttempts: 860,
      trebles: {20: const HitCount(300, 36), 19: const HitCount(60, 7)},
      trebleRate: 0.12,
      trebleAttempts: 360,
      checkoutByRange: {CheckoutRange.low: const HitCount(40, 18), CheckoutRange.mid: const HitCount(20, 7)},
      scoringAverage: 62,
      scoringDarts: 600,
      first9Average: 66,
      scoringVisits: 200,
      scoringMean: 62,
      scoringStdDev: 25,
    );

void main() {
  group('Schwächen', () {
    test('schwaches D16 wird erkannt, mit Begründung', () {
      final w = AutoPlanGenerator.weaknesses(weakD16());
      expect(w.first.kind, WeaknessKind.double);
      expect(w.first.number, 16);
      expect(w.first.reason, 'D16 triffst du nur zu 18 %, Ziel: 25 %');
      // Andere Doubles liegen bei 25 % und sind nicht schwach.
      expect(w.where((x) => x.kind == WeaknessKind.double), hasLength(1));
    });

    test('Doubles mit zu wenigen Versuchen zählen nicht', () {
      final w = AutoPlanGenerator.weaknesses(weakD16(extraDoubles: {3: const HitCount(5, 0)}));
      expect(w.where((x) => x.number == 3), isEmpty);
    });

    test('schwacher Checkout-Bereich, Triple, Scoring und Konstanz', () {
      const input = AutoPlanInput(
        days: 30,
        sessions: 10,
        darts: 1200,
        trebles: {20: HitCount(300, 30), 18: HitCount(60, 2)},
        trebleRate: 0.10,
        trebleAttempts: 360,
        checkoutByRange: {CheckoutRange.low: HitCount(40, 16), CheckoutRange.mid: HitCount(20, 2)},
        scoringAverage: 42,
        scoringDarts: 600,
        scoringVisits: 200,
        scoringMean: 42,
        scoringStdDev: 30,
      );
      final w = AutoPlanGenerator.weaknesses(input);
      final kinds = w.map((x) => x.kind).toSet();
      expect(kinds, containsAll([WeaknessKind.checkout, WeaknessKind.treble, WeaknessKind.scoring, WeaknessKind.consistency]));
      expect(w.firstWhere((x) => x.kind == WeaknessKind.checkout).range, CheckoutRange.mid);
      expect(w.firstWhere((x) => x.kind == WeaknessKind.treble).number, 18);
      expect(w.firstWhere((x) => x.kind == WeaknessKind.scoring).reason, 'Dein 3-Dart-Average liegt bei 42,0, Ziel: 45');
    });
  });

  test('Eingabe aus einem leeren Statistik-Bericht ergibt den Startplan', () {
    final report = StatsCalculator(sessions: const [], throws: const []).report(StatsPeriod.month);
    final input = AutoPlanInput.fromReport(report, days: 30);
    expect(input.darts, 0);
    expect(AutoPlanGenerator.generate(input).enoughData, isFalse);
  });

  group('Plan', () {
    test('schwaches D16 ergibt einen D16-Schwerpunkt', () {
      final plan = AutoPlanGenerator.generate(weakD16());
      expect(plan.enoughData, isTrue);
      final focus = plan.steps.where((s) => s.role == AutoStepRole.focus).toList();
      final d16 = focus.firstWhere((s) => s.weakness?.number == 16);
      expect(d16.step.gameId, 'checkout');
      expect(d16.step.config['min'], 32);
      expect(d16.step.config['max'], 32);
      expect(d16.reason, startsWith('D16 triffst du nur zu 18 %, Ziel: 25 %'));
      expect(plan.plan.name, contains('D16'));
      expect(plan.plan.id, AutoPlanGenerator.planId);
    });

    test('Reihenfolge: Aufwärmen, Schwerpunkte, Abschluss; jeder Schritt mit Begründung', () {
      for (final minutes in AutoPlanGenerator.lengths) {
        final plan = AutoPlanGenerator.generate(weakD16(), minutes: minutes);
        expect(plan.steps.first.role, AutoStepRole.warmup);
        expect(plan.steps.last.role, AutoStepRole.finish);
        expect(plan.steps.sublist(1, plan.steps.length - 1).every((s) => s.role == AutoStepRole.focus), isTrue);
        expect(plan.steps.where((s) => s.role == AutoStepRole.focus), hasLength(AutoPlanGenerator.focusSlots(minutes)));
        for (final s in plan.steps) {
          expect(s.reason, isNotEmpty);
          expect(GameCatalog.byId(s.step.gameId), isNotNull, reason: s.step.gameId);
        }
      }
    });

    test('zu wenig Daten: ausgewogener Startplan mit Hinweis', () {
      const input = AutoPlanInput(days: 30, sessions: 1, darts: 40, doubles: {16: HitCount(12, 0)}, doubleRate: 0, doubleAttempts: 12);
      final plan = AutoPlanGenerator.generate(input);
      expect(plan.enoughData, isFalse);
      expect(plan.weaknesses, isEmpty);
      expect(plan.notice, contains('zu wenig Daten'));
      expect(plan.plan.name, startsWith('Startplan'));
      expect(plan.steps.every((s) => s.weakness == null), isTrue);
      expect(plan.steps.length, greaterThanOrEqualTo(4));
    });

    test('genug Daten, aber keine Schwäche: ausgewogen', () {
      const input = AutoPlanInput(days: 30, sessions: 10, darts: 1000, scoringAverage: 70, scoringDarts: 500);
      final plan = AutoPlanGenerator.generate(input);
      expect(plan.enoughData, isTrue);
      expect(plan.notice, contains('Keine klare Schwäche'));
    });

    test('Länge wird eingehalten', () {
      final inputs = [
        weakD16(),
        const AutoPlanInput(sessions: 1, darts: 10),
        const AutoPlanInput(
          sessions: 10,
          darts: 1200,
          checkoutByRange: {CheckoutRange.big: HitCount(20, 0), CheckoutRange.low: HitCount(30, 3)},
          doubleRate: 0.08,
          doubleAttempts: 300,
          scoringAverage: 38,
          scoringDarts: 600,
        ),
      ];
      for (final input in inputs) {
        for (final minutes in AutoPlanGenerator.lengths) {
          for (var variant = 0; variant < 4; variant++) {
            final plan = AutoPlanGenerator.generate(input, minutes: minutes, variant: variant);
            expect(plan.minutes, inInclusiveRange(minutes * 0.8, minutes * 1.2),
                reason: '$minutes min, Variante $variant: ${plan.minutes}');
          }
        }
        final short = AutoPlanGenerator.generate(input, minutes: 20);
        final long = AutoPlanGenerator.generate(input, minutes: 60);
        expect(long.steps.length, greaterThan(short.steps.length));
      }
    });

    test('deterministisch bei gleicher Eingabe, andere Variante ändert den Plan', () {
      final a = AutoPlanGenerator.generate(weakD16(), minutes: 40);
      final b = AutoPlanGenerator.generate(weakD16(), minutes: 40);
      expect(a.plan.steps, b.plan.steps);
      expect(a.plan.name, b.plan.name);
      final c = AutoPlanGenerator.generate(weakD16(), minutes: 40, variant: 1);
      expect(c.plan.steps, isNot(a.plan.steps));
      // Der D16-Schwerpunkt bleibt.
      expect(c.steps.any((s) => s.weakness?.number == 16), isTrue);
    });

    test('kein Spiel doppelt im Plan', () {
      // Schwache T20: Das Aufwärmen auf die 20 darf sie nicht verdoppeln.
      const weakT20 = AutoPlanInput(
        sessions: 10,
        darts: 1200,
        trebles: {20: HitCount(300, 15), 19: HitCount(100, 15), 18: HitCount(100, 15)},
        trebleRate: 0.09,
        trebleAttempts: 500,
      );
      for (final input in [weakD16(), weakT20]) {
        for (var variant = 0; variant < 4; variant++) {
          final plan = AutoPlanGenerator.generate(input, minutes: 60, variant: variant);
          final keys = [for (final s in plan.plan.steps) '${s.gameId}/${s.config['number']}/${s.config['min']}'];
          expect(keys.toSet(), hasLength(keys.length), reason: keys.join(', '));
        }
      }
      final t20 = AutoPlanGenerator.generate(weakT20);
      expect(t20.steps.any((s) => s.weakness?.number == 20 && s.step.gameId == 'target_practice'), isTrue);
    });

    test('Configs liegen in den Grenzen der Spiele', () {
      final plan = AutoPlanGenerator.generate(weakD16(), minutes: 60);
      for (final s in plan.plan.steps) {
        final resolved = s.resolvedConfig;
        for (final key in s.config.keys) {
          expect(resolved[key], s.config[key], reason: '${s.gameId}.$key');
        }
      }
    });
  });
}
