import 'dart:math' as math;

import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/matches/domain/bot_calibration.dart';
import 'package:dartlab/features/matches/domain/dart_bot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bot-Kalibrierung', () {
    for (final target in [30.0, 45.0, 60.0, 80.0, 100.0]) {
      test('Bot mit Ziel-Average $target trifft ihn ungefähr', () {
        final bot = DartBot.forAverage(target, random: math.Random(target.round()));
        final avg = BotCalibration.simulateAverage(bot, legs: 600);
        expect(avg, closeTo(target, target * 0.05 + 1), reason: 'gemessen ${avg.toStringAsFixed(1)}');
      });
    }

    test('Tabelle ist monoton, Umkehrung passt', () {
      const t = BotCalibration.table;
      for (var i = 1; i < t.length; i++) {
        expect(t[i].$1, greaterThan(t[i - 1].$1));
        expect(t[i].$2, lessThan(t[i - 1].$2));
      }
      for (final a in [25.0, 50.0, 75.0, 99.0]) {
        expect(BotCalibration.averageFor(BotCalibration.sigmaFor(a)), closeTo(a, 0.01));
      }
      // Außerhalb der Tabelle wird begrenzt.
      expect(BotCalibration.sigmaFor(500), t.first.$1);
      expect(BotCalibration.sigmaFor(1), t.last.$1);
    });
  });

  group('Zielwahl', () {
    test('Scoring auf T20, Finish über den Checkout-Weg', () {
      expect(DartBot.aim(501, 3, OutMode.double), Segment.triple(20));
      expect(DartBot.aim(40, 3, OutMode.double), Segment.double(20));
      expect(DartBot.aim(170, 3, OutMode.double), Segment.triple(20));
      expect(DartBot.aim(50, 1, OutMode.double), Segment.bull);
      expect(DartBot.aim(32, 2, OutMode.double), Segment.double(16));
    });

    test('Ohne Finish: Aufbau auf einen guten Rest statt Bust', () {
      // 100 mit einem Dart: T20 lässt 40 (D20).
      expect(DartBot.aim(100, 1, OutMode.double), Segment.triple(20));
      // 159 (kein Finish): nicht auf einen Rest ohne Finish stellen.
      final aim = DartBot.aim(159, 3, OutMode.double);
      expect(CheckoutRules.isCheckout(159 - aim.score, out: OutMode.double), isTrue);
      // 3 mit Double-Out und einem Dart: S1 lässt D1.
      expect(DartBot.aim(3, 1, OutMode.double).score, 1);
    });

    test('Double-In: erst aufs Double', () {
      expect(DartBot.aim(501, 3, OutMode.double, opened: false), Segment.double(20));
    });

    test('Würfe landen in der Nähe des Ziels', () {
      final bot = DartBot(sigma: 0.0001, random: math.Random(1));
      expect(bot.throwAt(Segment.triple(20)).segment, Segment.triple(20));
      expect(bot.throwAt(Segment.double(16)).segment, Segment.double(16));
      expect(bot.throwAt(Segment.triple(20)).position, isNotNull);
    });
  });
}
