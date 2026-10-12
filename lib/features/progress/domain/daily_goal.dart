import '../../stats/domain/stats_calculator.dart';

/// Einheit des Tagesziels.
enum DailyGoalUnit {
  darts(min: 30, max: 1500, step: 10, defaultAmount: 200),
  minutes(min: 5, max: 240, step: 5, defaultAmount: 30),
  sessions(min: 1, max: 20, step: 1, defaultAmount: 3);

  const DailyGoalUnit({required this.min, required this.max, required this.step, required this.defaultAmount});
  final int min;
  final int max;
  final int step;
  final int defaultAmount;

  static DailyGoalUnit byName(String? name) => values.where((v) => v.name == name).firstOrNull ?? darts;

  /// Bringt [amount] in den erlaubten Bereich und auf das Raster.
  int clamp(int amount) {
    final c = amount.clamp(min, max);
    return (min + ((c - min) / step).round() * step).clamp(min, max);
  }
}

/// Das Tagesziel: z. B. 200 Darts am Tag.
class DailyGoal {
  const DailyGoal(this.unit, this.amount);
  static const DailyGoal standard = DailyGoal(DailyGoalUnit.darts, 200);

  final DailyGoalUnit unit;
  final int amount;

  @override
  bool operator ==(Object other) => other is DailyGoal && other.unit == unit && other.amount == amount;

  @override
  int get hashCode => Object.hash(unit, amount);
}

/// Training eines Kalendertags.
class DayActivity {
  const DayActivity({this.darts = 0, this.minutes = 0, this.sessions = 0});
  static const DayActivity zero = DayActivity();

  /// Gezählte Darts (nach Zeitpunkt des Wurfs).
  final int darts;

  /// Trainingszeit in Minuten (Dauer der Sessions, die an dem Tag begannen,
  /// je Session höchstens drei Stunden).
  final double minutes;

  /// Abgeschlossene Sessions, die an dem Tag begannen.
  final int sessions;

  double valueOf(DailyGoalUnit unit) => switch (unit) {
        DailyGoalUnit.darts => darts.toDouble(),
        DailyGoalUnit.minutes => minutes,
        DailyGoalUnit.sessions => sessions.toDouble(),
      };

  DayActivity operator +(DayActivity o) =>
      DayActivity(darts: darts + o.darts, minutes: minutes + o.minutes, sessions: sessions + o.sessions);
}

/// Training je Kalendertag aus allen abgeschlossenen Sessions.
Map<DateTime, DayActivity> dailyActivity(StatsCalculator calc) {
  final darts = <DateTime, int>{};
  final minutes = <DateTime, double>{};
  final sessions = <DateTime, int>{};
  for (final s in calc.sessions) {
    final day = StatsCalculator.dayOf(s.startedAt);
    sessions[day] = (sessions[day] ?? 0) + 1;
    var dur = s.endedAt!.difference(s.startedAt);
    if (dur.isNegative) dur = Duration.zero;
    if (dur > StatsCalculator.maxSessionDuration) dur = StatsCalculator.maxSessionDuration;
    minutes[day] = (minutes[day] ?? 0) + dur.inSeconds / 60;
    for (final t in calc.countedOf(s)) {
      final d = calc.cachedDayOf(t.timestamp);
      darts[d] = (darts[d] ?? 0) + 1;
    }
  }
  return {
    for (final d in {...darts.keys, ...minutes.keys, ...sessions.keys})
      d: DayActivity(darts: darts[d] ?? 0, minutes: minutes[d] ?? 0, sessions: sessions[d] ?? 0),
  };
}

/// Serie der Tage mit erreichtem Tagesziel.
class GoalStreak {
  const GoalStreak({
    required this.current,
    required this.best,
    required this.freeDayUsedThisWeek,
    required this.reachedDays,
    this.timeline = const [],
  });

  static const GoalStreak empty = GoalStreak(current: 0, best: 0, freeDayUsedThisWeek: false, reachedDays: []);

  /// Aktuelle Serie (Tage mit erreichtem Ziel); 0 = keine laufende Serie.
  final int current;

  /// Längste Serie.
  final int best;

  /// Der freie Tag dieser Kalenderwoche ist schon verbraucht.
  final bool freeDayUsedThisWeek;

  /// Alle Tage mit erreichtem Ziel, ältester zuerst.
  final List<DateTime> reachedDays;

  /// Serienstand nach jedem Tag mit erreichtem Ziel (für das Datum, an dem
  /// eine Serie eine bestimmte Länge erreichte).
  final List<({DateTime day, int run})> timeline;
}

/// Berechnet die Serie aus den Tagen mit erreichtem Ziel.
///
/// Regeln:
/// * Jeder Tag mit erreichtem Ziel verlängert die Serie um eins.
/// * Ein verpasster Tag pro Kalenderwoche (Montag bis Sonntag) ist frei: die
///   Serie bleibt stehen, wächst aber nicht. Der zweite verpasste Tag einer
///   Woche beendet sie.
/// * Heute zählt erst, wenn das Ziel erreicht ist; ein noch offener Tag
///   bricht nichts ab.
GoalStreak goalStreak(Iterable<DateTime> reached, DateTime now) {
  final days = {for (final d in reached) StatsCalculator.dayOf(d)}.toList()..sort();
  final today = StatsCalculator.dayOf(now);
  if (days.isEmpty) return GoalStreak.empty;
  final reachedSet = days.toSet();
  final freeUsed = <DateTime>{};
  final timeline = <({DateTime day, int run})>[];
  var run = 0;
  var best = 0;
  for (var d = days.first; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1)) {
    if (reachedSet.contains(d)) {
      run++;
      timeline.add((day: d, run: run));
      if (run > best) best = run;
    } else if (d == today) {
      // Heute ist noch offen.
    } else if (run > 0 && freeUsed.add(StatsCalculator.weekOf(d))) {
      // Freier Tag der Woche: Serie bleibt stehen.
    } else {
      run = 0;
    }
  }
  return GoalStreak(
    current: run,
    best: best,
    freeDayUsedThisWeek: freeUsed.contains(StatsCalculator.weekOf(today)),
    reachedDays: days.where((d) => !d.isAfter(today)).toList(),
    timeline: timeline,
  );
}

/// Stand des Tagesziels für die Startseite.
class DailyGoalStatus {
  const DailyGoalStatus({required this.goal, required this.today, required this.streak});
  final DailyGoal goal;

  /// Heutiger Wert in der Einheit des Ziels.
  final double today;
  final GoalStreak streak;

  double get ratio => goal.amount <= 0 ? 0 : (today / goal.amount).clamp(0, 1).toDouble();
  bool get reached => today >= goal.amount;
}

/// Tage, an denen [goal] erreicht wurde.
Iterable<DateTime> reachedDaysOf(Map<DateTime, DayActivity> activity, DailyGoal goal) sync* {
  for (final e in activity.entries) {
    if (e.value.valueOf(goal.unit) >= goal.amount) yield e.key;
  }
}

/// Stand des Tagesziels; [extraToday] zählt zusätzlich zu heute (z. B. das
/// laufende Spiel).
DailyGoalStatus dailyGoalStatus(
  Map<DateTime, DayActivity> activity,
  DailyGoal goal,
  DateTime now, {
  DayActivity extraToday = DayActivity.zero,
}) {
  final today = StatsCalculator.dayOf(now);
  final todayActivity = (activity[today] ?? DayActivity.zero) + extraToday;
  final merged = {...activity, today: todayActivity};
  return DailyGoalStatus(
    goal: goal,
    today: todayActivity.valueOf(goal.unit),
    streak: goalStreak(reachedDaysOf(merged, goal), now),
  );
}
