import 'dart:math' as math;

import 'dart_bot.dart';
import 'match_format.dart';
import 'x01_match.dart';

/// Zusammenhang zwischen Streuung und 3-Dart-Average des [DartBot].
///
/// Ein Bot hat zwei Streuungen: eine fürs Scoren und eine genauere für den
/// Weg zum Finish ([DartBot.finishSigma]). Die Finish-Streuung folgt einer
/// Checkout-Quote wie bei echten Spielern ([checkoutRateFor]); die
/// Scoring-Streuung ist dazu so gewählt, dass der Bot seinen Average trifft.
/// Die Tabelle wurde mit [calibrate] ermittelt; der Test
/// `bot_calibration_test.dart` prüft, dass simulierte Bots den gewünschten
/// Average treffen.
abstract final class BotCalibration {
  /// (3-Dart-Average, Scoring-Streuung, Finish-Streuung), Average absteigend.
  ///
  /// Streuung je Achse in normierten Board-Einheiten: 0,04 entspricht etwa
  /// 6,8 mm, 0,1 etwa 17 mm. Gemessen mit je 4000 Legs 501 Double-Out.
  static const List<(double, double, double)> table = [
    (140.0, 0.0141, 0.0350),
    (130.0, 0.0185, 0.0350),
    (120.0, 0.0230, 0.0377),
    (110.0, 0.0286, 0.0410),
    (100.0, 0.0350, 0.0450),
    (95.0, 0.0389, 0.0473),
    (90.0, 0.0434, 0.0497),
    (85.0, 0.0487, 0.0525),
    (80.0, 0.0542, 0.0554),
    (75.0, 0.0608, 0.0584),
    (70.0, 0.0673, 0.0617),
    (65.0, 0.0741, 0.0655),
    (60.0, 0.0830, 0.0693),
    (55.0, 0.0928, 0.0738),
    (50.0, 0.1053, 0.0785),
    (45.0, 0.1238, 0.0839),
    (40.0, 0.1517, 0.0896),
    (35.0, 0.2112, 0.0934),
    (30.0, 0.3200, 0.0934),
  ];

  static const double minAverage = 15;
  static const double maxAverage = 120;

  /// Mehr Scoring-Streuung bekommt kein Bot, sonst ginge gut jeder sechste
  /// Dart neben die Scheibe. Bots unter einem 30er spielen deshalb wie ein
  /// 30er (die Tabelle endet dort).
  static const double maxScoringSigma = 0.32;

  /// Scoring-Streuung für den gewünschten Average (linear interpoliert).
  static double sigmaFor(double average) => _lookup(average, (r) => r.$2);

  /// Finish-Streuung für den gewünschten Average (linear interpoliert).
  static double finishSigmaFor(double average) => _lookup(average, (r) => r.$3);

  static double _lookup(double average, double Function((double, double, double)) value) {
    final a = average.clamp(table.last.$1, table.first.$1);
    for (var i = 0; i < table.length - 1; i++) {
      final a0 = table[i].$1;
      final a1 = table[i + 1].$1;
      if (a <= a0 && a >= a1) {
        final t = a0 == a1 ? 0 : (a0 - a) / (a0 - a1);
        return value(table[i]) + (value(table[i + 1]) - value(table[i])) * t;
      }
    }
    return value(a >= table.first.$1 ? table.first : table.last);
  }

  /// Gewünschte Trefferquote je Dart aufs Doppel, angelehnt an echte
  /// Spieler: 22 % bei einem 50er und 40 % bei einem 100er Average. Unter
  /// einem 37er bleibt sie bei 18 %, sonst stünden schwache Bots (etwa im
  /// Turnier mit 30 %) oft zehn Aufnahmen auf dem Finish, vor allem auf D1.
  /// Ihre Punkte verlieren sie dafür beim Scoren.
  static double checkoutRateFor(double average) => (0.05 + 0.0035 * average).clamp(0.18, 0.5);

  /// (Streuung je Achse, Trefferquote je Dart auf ein Doppel), gemessen über
  /// D1 bis D20 mit je 20 000 Darts.
  static const List<(double, double)> doubleHitTable = [
    (0.015, 0.8825),
    (0.020, 0.7591),
    (0.025, 0.6523),
    (0.030, 0.5669),
    (0.035, 0.4997),
    (0.040, 0.4443),
    (0.045, 0.3999),
    (0.050, 0.3624),
    (0.060, 0.3028),
    (0.070, 0.2570),
    (0.080, 0.2193),
    (0.090, 0.1887),
    (0.100, 0.1633),
    (0.120, 0.1250),
    (0.140, 0.0978),
    (0.160, 0.0781),
  ];

  /// Streuung, mit der ein Dart ein Doppel mit Quote [rate] trifft.
  static double sigmaForDoubleRate(double rate) {
    const t = doubleHitTable;
    if (rate >= t.first.$2) return t.first.$1;
    for (var i = 0; i < t.length - 1; i++) {
      final (s0, r0) = t[i];
      final (s1, r1) = t[i + 1];
      if (rate <= r0 && rate >= r1) return s0 + (s1 - s0) * (r0 - rate) / (r0 - r1);
    }
    return t.last.$1;
  }

  /// Spielt [legs] Legs allein und liefert den 3-Dart-Average über alle Darts
  /// (Bust-Aufnahmen zählen 0 Punkte).
  static double simulateAverage(DartBot bot, {int legs = 200, MatchFormat format = const MatchFormat()}) {
    var points = 0;
    var darts = 0;
    for (var i = 0; i < legs; i++) {
      final m = X01Match(format: format.copyWith(legsToWin: 1, setsToWin: 0), playerCount: 1);
      var guard = 0;
      while (!m.finished && guard++ < 3000) {
        if (m.visitClosed) {
          m.endVisit();
          continue;
        }
        m.throwDart(bot.next(m, at: _epoch));
      }
      points += m.players.first.points;
      darts += m.players.first.darts;
    }
    return darts == 0 ? 0 : points / darts * 3;
  }

  static final DateTime _epoch = DateTime(2026);

  /// Hilfsfunktion zum Neuberechnen der [table]: sucht für jeden Average
  /// die Scoring-Streuung, mit der ein Bot mit der Finish-Streuung aus
  /// [checkoutRateFor] ihn erreicht, höchstens [maxScoringSigma].
  static List<(double, double, double)> calibrate(List<double> averages, {int legs = 4000, int seed = 1}) => [
    for (final a in averages) _calibrateOne(a, legs, seed),
  ];

  static (double, double, double) _calibrateOne(double average, int legs, int seed) {
    final finish = sigmaForDoubleRate(checkoutRateFor(average));
    var lo = 0.005;
    var hi = 0.9;
    for (var i = 0; i < 14; i++) {
      final mid = (lo + hi) / 2;
      final bot = DartBot(sigma: mid, finishSigma: finish, random: math.Random(seed));
      if (simulateAverage(bot, legs: legs) > average) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (average, math.min((lo + hi) / 2, maxScoringSigma), finish);
  }
}
