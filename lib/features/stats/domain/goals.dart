import '../../../core/database/app_database.dart';
import 'stats_calculator.dart';

/// Arten persönlicher Ziele.
enum GoalKind {
  /// Sessions pro Woche (Montag bis Sonntag).
  weeklySessions(min: 1, max: 30, step: 1, defaultTarget: 5),

  /// Darts pro Woche.
  weeklyDarts(min: 100, max: 5000, step: 100, defaultTarget: 1000),

  /// Trainingstage am Stück.
  streakDays(min: 2, max: 60, step: 1, defaultTarget: 7),

  /// 3-Dart-Average in den Scoring-Spielen, letzte 30 Tage.
  scoringAverage(min: 20, max: 120, step: 1, defaultTarget: 60),

  /// Checkout-Quote in Prozent, letzte 30 Tage.
  checkoutRate(min: 5, max: 80, step: 1, defaultTarget: 30),

  /// Double-Quote in Prozent (Bob's 27), letzte 30 Tage.
  doubleRate(min: 5, max: 60, step: 1, defaultTarget: 20);

  const GoalKind({required this.min, required this.max, required this.step, required this.defaultTarget});
  final double min;
  final double max;
  final double step;
  final double defaultTarget;

  /// Ziel in Prozent angegeben.
  bool get isPercent => this == checkoutRate || this == doubleRate;

  static GoalKind? byName(String name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

/// Fortschritt eines Ziels.
class GoalProgress {
  const GoalProgress({required this.goal, required this.kind, required this.current});
  final GoalRow goal;
  final GoalKind kind;

  /// Aktueller Wert in der Einheit des Ziels (Prozent bei Quoten);
  /// `null`, wenn es noch keine Daten gibt.
  final double? current;

  double get target => goal.target;
  double get ratio => current == null || target <= 0 ? 0 : (current! / target).clamp(0, 1).toDouble();
  bool get reached => current != null && current! >= target;
}

/// Berechnet den Fortschritt aller [goals] aus den Statistiken.
List<GoalProgress> goalProgress(List<GoalRow> goals, StatsCalculator calc) {
  final week = calc.thisWeek();
  final month = calc.report(StatsPeriod.month);
  final streak = calc.streak();
  return [
    for (final g in goals)
      if (GoalKind.byName(g.kind) case final kind?)
        GoalProgress(
          goal: g,
          kind: kind,
          current: switch (kind) {
            GoalKind.weeklySessions => week.sessions.toDouble(),
            GoalKind.weeklyDarts => week.darts.toDouble(),
            GoalKind.streakDays => streak.current.toDouble(),
            GoalKind.scoringAverage => month.scoringAverage,
            GoalKind.checkoutRate => month.checkoutRate == null ? null : month.checkoutRate! * 100,
            GoalKind.doubleRate => month.doubleRate == null ? null : month.doubleRate! * 100,
          },
        ),
  ];
}
