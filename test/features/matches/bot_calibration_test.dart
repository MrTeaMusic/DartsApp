import 'dart:math' as math;

import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/matches/domain/bot_calibration.dart';
import 'package:dartlab/features/matches/domain/dart_bot.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/x01_match.dart';
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

    test('Tabelle ist monoton, außerhalb wird begrenzt', () {
      const t = BotCalibration.table;
      for (var i = 1; i < t.length; i++) {
        expect(t[i].$1, lessThan(t[i - 1].$1));
        expect(t[i].$2, greaterThanOrEqualTo(t[i - 1].$2));
        expect(t[i].$3, greaterThanOrEqualTo(t[i - 1].$3));
      }
      expect(BotCalibration.sigmaFor(500), t.first.$2);
      expect(BotCalibration.sigmaFor(1), t.last.$2);
      expect(BotCalibration.finishSigmaFor(1), t.last.$3);
    });

    // Bei 30 % Turnier-Stärke haben die CPUs einen Average um 28. Vorher
    // standen sie im Schnitt acht Aufnahmen auf dem Finish, manchmal über 50.
    for (final target in [28.0, 50.0]) {
      test('Bot mit Average $target steht nicht ewig auf dem Finish', () {
        final bot = DartBot.forAverage(target, random: math.Random(5));
        const legs = 400;
        final visits = <int>[];
        for (var i = 0; i < legs; i++) {
          final m = X01Match(format: const MatchFormat(startScore: 501, legsToWin: 1), playerCount: 1);
          var onFinish = 0;
          while (!m.finished) {
            if (m.visitClosed) m.endVisit();
            if (m.dartsLeft == X01Match.dartsPerVisit && m.currentPlayer.remaining <= 40) onFinish++;
            m.throwDart(bot.next(m, at: DateTime(2026)));
          }
          visits.add(onFinish);
        }
        visits.sort();
        final mean = visits.reduce((a, b) => a + b) / legs;
        expect(mean, lessThan(target < 40 ? 3 : 2.2), reason: 'Aufnahmen auf dem Finish im Schnitt');
        expect(visits[(legs * 0.95).floor()], lessThanOrEqualTo(target < 40 ? 8 : 6), reason: '95 % der Legs');
      });
    }
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

    test('Finish-Darts mit eigener Streuung', () {
      final bot = DartBot(sigma: 5, finishSigma: 0.0001, random: math.Random(1));
      X01Match leave(int rest) => X01Match(format: MatchFormat(startScore: rest, legsToWin: 1), playerCount: 1);
      expect(bot.next(leave(40)).segment, Segment.double(20));
      expect(bot.next(leave(3)).segment, Segment.single(1), reason: 'Stellen im Finish-Bereich');
      final doubleIn = X01Match(format: const MatchFormat(doubleIn: true, legsToWin: 1), playerCount: 1);
      expect(bot.next(doubleIn).segment, Segment.double(20));
      // Scoren mit der weiten Streuung: landet fast nie in T20.
      final scoring = [for (var i = 0; i < 50; i++) bot.next(leave(501)).segment];
      expect(scoring.where((s) => s == Segment.triple(20)).length, lessThan(5));
    });

    test('Würfe landen in der Nähe des Ziels', () {
      final bot = DartBot(sigma: 0.0001, random: math.Random(1));
      expect(bot.throwAt(Segment.triple(20)).segment, Segment.triple(20));
      expect(bot.throwAt(Segment.double(16)).segment, Segment.double(16));
      expect(bot.throwAt(Segment.triple(20)).position, isNotNull);
    });
  });
}
