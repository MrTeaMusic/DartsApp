import 'dart:math' as math;

import 'dart_bot.dart';
import 'match_format.dart';
import 'x01_match.dart';

/// Zusammenhang zwischen Streuung und 3-Dart-Average des [DartBot].
///
/// Die Tabelle wurde durch Simulation vieler 501-Legs (Double-Out) mit
/// [simulateAverage] ermittelt; der Test `bot_calibration_test.dart` prüft,
/// dass simulierte Bots den gewünschten Average treffen.
abstract final class BotCalibration {
  /// (Streuung je Achse, gemessener 3-Dart-Average), Streuung aufsteigend.
  ///
  /// Gemessen mit je 4000 Legs. 0,04 entspricht etwa 6,8 mm Streuung je
  /// Achse (≈ 97er Average), 0,1 etwa 17 mm (≈ 48er Average).
  static const List<(double, double)> table = [
    (0.020, 137.4),
    (0.025, 123.8),
    (0.030, 113.3),
    (0.035, 104.1),
    (0.040, 96.8),
    (0.045, 90.7),
    (0.050, 84.6),
    (0.055, 79.7),
    (0.060, 75.3),
    (0.070, 66.5),
    (0.080, 59.3),
    (0.090, 53.5),
    (0.100, 48.1),
    (0.110, 44.4),
    (0.120, 40.9),
    (0.140, 35.3),
    (0.160, 31.1),
    (0.180, 28.4),
    (0.200, 25.7),
    (0.230, 22.4),
    (0.260, 19.9),
    (0.300, 16.7),
    (0.350, 13.7),
  ];

  static const double minAverage = 15;
  static const double maxAverage = 120;

  /// Streuung für den gewünschten Average (linear interpoliert).
  static double sigmaFor(double average) {
    final a = average.clamp(table.last.$2, table.first.$2);
    for (var i = 0; i < table.length - 1; i++) {
      final (s0, a0) = table[i];
      final (s1, a1) = table[i + 1];
      if (a <= a0 && a >= a1) {
        final t = a0 == a1 ? 0 : (a0 - a) / (a0 - a1);
        return s0 + (s1 - s0) * t;
      }
    }
    return a >= table.first.$2 ? table.first.$1 : table.last.$1;
  }

  /// Erwarteter Average für eine Streuung (Umkehrung von [sigmaFor]).
  static double averageFor(double sigma) {
    if (sigma <= table.first.$1) return table.first.$2;
    for (var i = 0; i < table.length - 1; i++) {
      final (s0, a0) = table[i];
      final (s1, a1) = table[i + 1];
      if (sigma >= s0 && sigma <= s1) return a0 + (a1 - a0) * (sigma - s0) / (s1 - s0);
    }
    return table.last.$2;
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

  /// Hilfsfunktion zum Neuberechnen der [table].
  static List<(double, double)> measure(List<double> sigmas, {int legs = 400, int seed = 1}) => [
    for (final s in sigmas)
      (
        s,
        simulateAverage(
          DartBot(sigma: s, random: math.Random(seed)),
          legs: legs,
        ),
      ),
  ];
}
