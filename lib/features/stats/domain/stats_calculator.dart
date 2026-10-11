import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import 'game_metrics.dart';

/// Zeitraum der Auswertung.
enum StatsPeriod {
  week(7),
  month(30),
  quarter(90),
  all(null);

  const StatsPeriod(this.days);
  final int? days;
}

/// Ein Punkt im Verlauf: Wert einer Session.
class TrendPoint {
  const TrendPoint(this.sessionId, this.time, this.value);
  final int sessionId;
  final DateTime time;
  final double value;
}

/// Rekord und Überblick eines Spiels.
class GameSummary {
  const GameSummary({required this.gameId, required this.sessions, required this.darts, this.best, this.last});
  final String gameId;
  final int sessions;
  final int darts;
  final double? best;
  final double? last;
}

/// Trainingstage am Stück.
class Streak {
  const Streak({required this.current, required this.longest, required this.trainedToday});
  final int current;
  final int longest;
  final bool trainedToday;
}

/// Alle Kennzahlen eines Zeitraums. Reine Berechnung aus Sessions und
/// Würfen, ohne Datenbankzugriff, damit sie leicht testbar ist.
class StatsReport {
  StatsReport._({
    required this.sessions,
    required this.darts,
    required this.practiceDays,
    required this.scoringAverage,
    required this.checkoutRate,
    required this.checkoutAttempts,
    required this.doubleRate,
    required this.trebleRate,
    required this.games,
    required this.heat,
    required this.numberHits,
    required this.dailyDarts,
    required this.streak,
  });

  final int sessions;
  final int darts;
  final int practiceDays;

  /// 3-Dart-Average in den Scoring-Spielen.
  final double? scoringAverage;

  /// Checkout-Quote aus Checkout-Training und 121.
  final double? checkoutRate;
  final int checkoutAttempts;

  /// Double-Quote aus Bob's 27.
  final double? doubleRate;

  /// Triple-Quote im T20-Training.
  final double? trebleRate;

  /// Überblick je Spiel, meistgespielt zuerst.
  final List<GameSummary> games;

  /// Positionen gezählter Darts für die Heatmap. Darts ohne Koordinaten
  /// (manuelle Eingabe) liegen in der Mitte ihres Feldes.
  final List<BoardPoint> heat;

  /// Treffer je Zahl (1–20, 25 für Bull), ohne Fehlwürfe.
  final Map<int, int> numberHits;

  /// Darts je Kalendertag im Zeitraum, ältester zuerst.
  final List<({DateTime day, int darts})> dailyDarts;

  /// Streak über alle Daten (unabhängig vom Zeitraum).
  final Streak streak;

  bool get isEmpty => sessions == 0;
}

/// Berechnet [StatsReport] und Verläufe.
class StatsCalculator {
  StatsCalculator({required List<SessionRow> sessions, required this.throws, DateTime? now})
      : _sessions = sessions.where((s) => s.endedAt != null).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt)),
        now = now ?? DateTime.now();

  final List<SessionRow> _sessions;
  final List<ThrowRow> throws;
  final DateTime now;

  static DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  DateTime? _since(StatsPeriod p) => p.days == null ? null : dayOf(now).subtract(Duration(days: p.days! - 1));

  List<SessionRow> sessionsIn(StatsPeriod period, {String? gameId}) {
    final since = _since(period);
    return [
      for (final s in _sessions)
        if ((since == null || !s.startedAt.isBefore(since)) && (gameId == null || s.gameId == gameId)) s,
    ];
  }

  static Map<String, Object?> decode(String? json) {
    if (json == null) return const {};
    try {
      final v = jsonDecode(json);
      return v is Map<String, Object?> ? v : const {};
    } on FormatException {
      return const {};
    }
  }

  static Map<String, num> metricsOf(SessionRow s) {
    final m = decode(s.resultJson)['metrics'];
    return m is Map ? {for (final e in m.entries) if (e.value is num) '${e.key}': e.value as num} : const {};
  }

  /// Wert der Hauptkennzahl einer Session, falls sie zählt.
  static double? primaryValue(SessionRow s) {
    final pm = PrimaryMetric.byGame[s.gameId];
    if (pm == null) return null;
    final m = metricsOf(s);
    if (pm.onlyCompleted && m['completed'] != 1) return null;
    final v = m[pm.key];
    return v?.toDouble();
  }

  /// Verlauf der Hauptkennzahl eines Spiels.
  List<TrendPoint> trend(String gameId, StatsPeriod period) => [
        for (final s in sessionsIn(period, gameId: gameId))
          if (primaryValue(s) case final v?) TrendPoint(s.id, s.startedAt, v),
      ];

  StatsReport report(StatsPeriod period, {String? gameId}) {
    final sessions = sessionsIn(period, gameId: gameId);
    final ids = {for (final s in sessions) s.id};
    final counted = [for (final t in throws) if (t.counted && ids.contains(t.sessionId)) t];

    // 3-Dart-Average in Scoring-Spielen.
    final scoring = [for (final t in counted) if (scoringGames.contains(t.gameId)) t];
    final scoringAverage = scoring.isEmpty ? null : scoring.fold<int>(0, (a, t) => a + t.score) / scoring.length * 3;

    // Checkouts aus Checkout-Training und 121.
    var attempts = 0;
    var successes = 0;
    for (final s in sessions) {
      final details = decode(s.resultJson)['details'];
      if (details is! Map) continue;
      final list = s.gameId == 'checkout' ? details['attempts'] : (s.gameId == 'one_twenty_one' ? details['rounds'] : null);
      if (list is! List) continue;
      for (final a in list) {
        if (a is! Map) continue;
        attempts++;
        if (a['success'] == true) successes++;
      }
    }

    // Doubles aus Bob's 27: Treffer auf das aktuelle Double je Dart.
    final bobs = [for (final s in sessions) if (s.gameId == 'bobs_27') metricsOf(s)];
    final bobsDarts = bobs.fold<num>(0, (a, m) => a + (m['darts'] ?? 0));
    final bobsHits = bobs.fold<num>(0, (a, m) => a + (m['hits'] ?? 0));

    // Triples im T20-Training.
    final tp = [for (final s in sessions) if (s.gameId == 'target_practice') metricsOf(s)];
    final tpDarts = tp.fold<num>(0, (a, m) => a + (m['darts'] ?? 0));
    final tpTrebles = tp.fold<num>(0, (a, m) => a + (m['trebles'] ?? 0));

    // Überblick je Spiel.
    final byGame = <String, List<SessionRow>>{};
    for (final s in sessions) {
      byGame.putIfAbsent(s.gameId, () => []).add(s);
    }
    final games = [
      for (final e in byGame.entries) _gameSummary(e.key, e.value),
    ]..sort((a, b) => b.sessions.compareTo(a.sessions));

    // Heatmap und Trefferverteilung.
    final heat = <BoardPoint>[];
    final numberHits = <int, int>{};
    for (final t in counted) {
      final seg = Segment.tryParse(t.segment);
      if (t.x != null && t.y != null) {
        heat.add(BoardPoint(t.x!, t.y!));
      } else if (seg != null && !seg.isMiss) {
        heat.add(BoardGeometry.centerOf(seg));
      }
      if (t.number > 0) numberHits[t.number] = (numberHits[t.number] ?? 0) + 1;
    }

    // Darts pro Tag.
    final perDay = <DateTime, int>{};
    for (final t in counted) {
      final d = dayOf(t.timestamp);
      perDay[d] = (perDay[d] ?? 0) + 1;
    }
    final firstDay = _since(period) ?? (perDay.isEmpty ? dayOf(now) : perDay.keys.reduce((a, b) => a.isBefore(b) ? a : b));
    final daily = <({DateTime day, int darts})>[];
    for (var d = firstDay; !d.isAfter(dayOf(now)); d = DateTime(d.year, d.month, d.day + 1)) {
      daily.add((day: d, darts: perDay[d] ?? 0));
    }

    return StatsReport._(
      sessions: sessions.length,
      darts: counted.length,
      practiceDays: {for (final s in sessions) dayOf(s.startedAt)}.length,
      scoringAverage: scoringAverage,
      checkoutRate: attempts == 0 ? null : successes / attempts,
      checkoutAttempts: attempts,
      doubleRate: bobsDarts == 0 ? null : bobsHits / bobsDarts,
      trebleRate: tpDarts == 0 ? null : tpTrebles / tpDarts,
      games: games,
      heat: heat,
      numberHits: numberHits,
      dailyDarts: daily,
      streak: streak(),
    );
  }

  GameSummary _gameSummary(String gameId, List<SessionRow> sessions) {
    final pm = PrimaryMetric.byGame[gameId];
    final values = [for (final s in sessions) ?primaryValue(s)];
    double? best;
    if (pm != null && values.isNotEmpty) {
      best = values.reduce((a, b) => (pm.higherIsBetter ? a > b : a < b) ? a : b);
    }
    return GameSummary(
      gameId: gameId,
      sessions: sessions.length,
      darts: sessions.fold(0, (a, s) => a + s.dartCount),
      best: best,
      last: values.isEmpty ? null : values.last,
    );
  }

  /// Aufeinanderfolgende Trainingstage. Die aktuelle Serie zählt auch, wenn
  /// heute noch nicht trainiert wurde, aber gestern.
  Streak streak() {
    final days = {for (final s in _sessions) dayOf(s.startedAt)}.toList()..sort();
    if (days.isEmpty) return const Streak(current: 0, longest: 0, trainedToday: false);
    var longest = 1;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      run = _isNextDay(days[i - 1], days[i]) ? run + 1 : 1;
      if (run > longest) longest = run;
    }
    final today = dayOf(now);
    final last = days.last;
    final trainedToday = last == today;
    final current = trainedToday || _isNextDay(last, today) ? run : 0;
    return Streak(current: current, longest: longest, trainedToday: trainedToday);
  }

  static bool _isNextDay(DateTime a, DateTime b) => DateTime(a.year, a.month, a.day + 1) == b;

  /// Beginn der aktuellen Woche (Montag).
  DateTime get weekStart {
    final d = dayOf(now);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  /// Sessions und Darts seit Wochenbeginn.
  ({int sessions, int darts}) thisWeek() {
    final ws = weekStart;
    final s = [for (final x in _sessions) if (!x.startedAt.isBefore(ws)) x];
    return (sessions: s.length, darts: s.fold(0, (a, x) => a + x.dartCount));
  }
}
