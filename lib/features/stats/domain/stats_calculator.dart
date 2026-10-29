import 'dart:convert';
import 'dart:math' as math;

import '../../../core/database/app_database.dart';
import '../../autodarts_live/domain/live_stats.dart';
import '../../autodarts_live/domain/live_x01.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../games/domain/game_catalog.dart';
import '../../matches/domain/match_format.dart';
import '../../matches/domain/match_result.dart';
import 'double_stats.dart';
import 'game_metrics.dart';
import 'house_elo.dart';
import 'online_stats.dart';
import 'scatter_stats.dart';
import 'stats_models.dart';
import 'target_replay.dart';
import 'tempo_stats.dart';

export 'double_stats.dart';
export 'house_elo.dart';
export 'online_stats.dart';
export 'scatter_stats.dart';
export 'stats_models.dart';
export 'tempo_stats.dart';

/// Alle Kennzahlen eines Zeitraums. Reine Berechnung aus Sessions und
/// Würfen, ohne Datenbankzugriff, damit sie leicht testbar ist.
class StatsReport {
  StatsReport._({
    required this.sessions,
    required this.darts,
    required this.practiceDays,
    required this.trainingTime,
    required this.scoringAverage,
    required this.scoringDarts,
    required this.first9Average,
    required this.checkoutRate,
    required this.checkoutAttempts,
    required this.checkoutByRange,
    required this.doubleRate,
    required this.doubleAttempts,
    required this.trebleRate,
    required this.trebleAttempts,
    required this.doubles,
    required this.trebles,
    required this.accuracy,
    required this.scoring,
    required this.games,
    required this.heat,
    required this.numberHits,
    required this.dailyDarts,
    required this.weekly,
    required this.weekdays,
    required this.dayParts,
    required this.averageTrend,
    required this.streak,
  });

  final int sessions;
  final int darts;
  final int practiceDays;

  /// Summe der Session-Dauern (je Session höchstens drei Stunden).
  final Duration trainingTime;

  /// 3-Dart-Average: Scoring-Spiele aus den Würfen, andere Spiele (z. B.
  /// X01) über ihre gemeldete Kennzahl `average`.
  final double? scoringAverage;
  final int scoringDarts;

  /// Durchschnitt der Kennzahl `first9` (X01), falls Spiele sie melden.
  final double? first9Average;

  /// Checkout-Quote aus dem Checkout-Training. 121 zählt nicht mit (siehe
  /// [StatsCalculator.multiVisitFinishGames]).
  final double? checkoutRate;
  final int checkoutAttempts;
  final Map<CheckoutRange, HitCount> checkoutByRange;

  /// Double-Quote: Darts mit genau einem Double als Ziel. Ohne solche Darts
  /// die Quote aus Bob's 27.
  final double? doubleRate;
  final int doubleAttempts;

  /// Triple-Quote: Darts mit genau einem Triple als Ziel. Ohne solche
  /// Darts die Quote aus dem T20-Training.
  final double? trebleRate;
  final int trebleAttempts;

  /// Versuche und Treffer je Double (1–20, 25 = Bullseye).
  final Map<int, HitCount> doubles;

  /// Versuche und Treffer je Triple (1–20).
  final Map<int, HitCount> trebles;

  /// Alle Darts mit bekanntem Ziel und Treffer darauf.
  final HitCount accuracy;

  /// Volle Aufnahmen aus Scoring-Spielen und X01; `null` ohne Aufnahmen.
  final ScoringStats? scoring;

  /// Überblick je Spiel, meistgespielt zuerst.
  final List<GameSummary> games;

  /// Positionen gezählter Darts für die Heatmap. Darts ohne Koordinaten
  /// (manuelle Eingabe) liegen in der Mitte ihres Feldes.
  final List<BoardPoint> heat;

  /// Treffer je Zahl (1–20, 25 für Bull), ohne Fehlwürfe.
  final Map<int, int> numberHits;

  /// Darts je Kalendertag im Zeitraum, ältester zuerst.
  final List<({DateTime day, int darts})> dailyDarts;

  /// Darts und Sessions je Kalenderwoche, älteste zuerst.
  final List<WeekVolume> weekly;

  /// Aktivität je Wochentag, Index 0 = Montag.
  final List<ActivityBucket> weekdays;

  /// Aktivität je Tageszeit, Index = [DayPart.index].
  final List<ActivityBucket> dayParts;

  /// 3-Dart-Average je Trainingstag mit Scoring-Darts.
  final List<TrendPoint> averageTrend;

  /// Streak über alle Daten (unabhängig vom Zeitraum).
  final Streak streak;

  bool get isEmpty => sessions == 0;
}

/// Berechnet [StatsReport], Verläufe und Rekorde.
class StatsCalculator {
  /// Mit [previous] übernimmt der Rechner dessen Zwischenergebnisse (Würfe je
  /// Session, dekodierte Ergebnisse, Ziele je Dart …) für die Sessions in
  /// [unchanged]: Sie und ihre Würfe müssen in beiden Rechnern gleich sein.
  StatsCalculator({
    required List<SessionRow> sessions,
    required this.throws,
    DateTime? now,
    StatsCalculator? previous,
    Set<int> unchanged = const {},
  })  : _sessions = sessions.where((s) => s.endedAt != null).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt)),
        now = now ?? DateTime.now() {
    if (previous == null || unchanged.isEmpty) return;
    void take<V>(Map<int, V> from, Map<int, V> to) {
      for (final id in unchanged) {
        if (from[id] case final v?) to[id] = v;
      }
    }

    take(previous._bySession, _reused);
    take(previous._countedCache, _countedCache);
    take(previous._aimedCache, _aimedCache);
    take(previous._metricsCache, _metricsCache);
    take(previous._resultCache, _resultCache);
    take(previous._perDayCache, _perDayCache);
    take(previous._liveDoublesCache, _liveDoublesCache);
    take(previous._onlineMatchCache, _onlineMatchCache);
    // „Zählt nicht“ (`null`) ist hier ein Ergebnis, das ebenfalls übernommen wird.
    for (final id in unchanged) {
      if (previous._eloMatchCache.containsKey(id)) _eloMatchCache[id] = previous._eloMatchCache[id];
    }
    take(previous._scatterCache, _scatterCache);
    take(previous._tempoCache, _tempoCache);
    _days.addAll(previous._days);
  }

  final List<SessionRow> _sessions;
  final List<ThrowRow> throws;
  final DateTime now;

  /// Abgeschlossene Sessions, älteste zuerst.
  List<SessionRow> get sessions => _sessions;

  /// Gleitender Durchschnitt über so viele Punkte.
  static const int movingWindow = 5;

  /// Höchstdauer einer Session für die Trainingszeit (vergessene Sessions).
  static const Duration maxSessionDuration = Duration(hours: 3);

  static DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Wie [dayOf], aber zwischengespeichert: Ein lokales Datum zu bauen ist
  /// teuer, und es gibt viele Würfe, aber wenige Tage.
  DateTime _dayOf(DateTime t) => _days.putIfAbsent(t.year * 10000 + t.month * 100 + t.day, () => dayOf(t));

  final Map<int, DateTime> _days = {};
  static DateTime weekOf(DateTime t) {
    final d = dayOf(t);
    return DateTime(d.year, d.month, d.day - (d.weekday - 1));
  }

  late final Map<int, List<ThrowRow>> _bySession = () {
    final m = <int, List<ThrowRow>>{};
    for (final t in throws) {
      if (_reused.containsKey(t.sessionId)) continue;
      m.putIfAbsent(t.sessionId, () => []).add(t);
    }
    for (final l in m.values) {
      l.sort((a, b) => a.seq.compareTo(b.seq));
    }
    return m..addAll(_reused);
  }();

  /// Bereits sortierte Würfe unveränderter Sessions aus dem vorigen Rechner.
  final Map<int, List<ThrowRow>> _reused = {};

  final Map<int, List<ThrowRow>> _countedCache = {};
  final Map<int, List<AimedDart>> _aimedCache = {};
  final Map<int, Map<String, num>> _metricsCache = {};

  /// Alle Würfe einer Session (auch nicht gezählte) in Wurfreihenfolge.
  List<ThrowRow> throwsOf(SessionRow s) => _bySession[s.id] ?? const [];

  /// Gespeichertes Ergebnis einer Session (Kennzahlen und Details).
  Map<String, Object?> resultOf(SessionRow s) => _result(s);

  /// Kennzahlen einer Session (einmal dekodiert).
  Map<String, num> metricsOfSession(SessionRow s) => _metrics(s);

  /// Gezählte Würfe einer Session in Wurfreihenfolge.
  List<ThrowRow> countedOf(SessionRow s) =>
      _countedCache.putIfAbsent(s.id, () => [for (final t in _bySession[s.id] ?? const <ThrowRow>[]) if (t.counted) t]);

  /// Gezählte Würfe einer Session je Kalendertag (in der Reihenfolge der
  /// Würfe), z. B. fürs Tagesziel.
  Map<DateTime, int> countedPerDayOf(SessionRow s) => _perDayCache.putIfAbsent(s.id, () {
        final m = <DateTime, int>{};
        for (final t in countedOf(s)) {
          final d = _dayOf(t.timestamp);
          m[d] = (m[d] ?? 0) + 1;
        }
        return m;
      });
  final Map<int, Map<DateTime, int>> _perDayCache = {};

  /// Gezählte Würfe mit dem Ziel, das das Spiel vorgab (siehe [replayTargets]).
  List<AimedDart> aimedOf(SessionRow s) =>
      _aimedCache.putIfAbsent(s.id, () => replayTargets(s, _bySession[s.id] ?? const [], decode(s.configJson)));

  final Map<int, Map<String, Object?>> _resultCache = {};

  /// Gespeichertes Ergebnis einer Session (einmal dekodiert).
  Map<String, Object?> _result(SessionRow s) => _resultCache.putIfAbsent(s.id, () => decode(s.resultJson));
  Map<String, num> _metrics(SessionRow s) => _metricsCache.putIfAbsent(s.id, () => _numbers(_result(s)['metrics']));

  /// Erster Tag des Zeitraums (heute eingeschlossen); `null` bei „Alles“.
  DateTime? periodStart(StatsPeriod p) => _since(p);

  DateTime? _since(StatsPeriod p) => p.days == null ? null : dayOf(now).subtract(Duration(days: p.days! - 1));

  List<SessionRow> _between(DateTime? from, DateTime? to, String? gameId) => [
        for (final s in _sessions)
          if ((from == null || !s.startedAt.isBefore(from)) &&
              (to == null || s.startedAt.isBefore(to)) &&
              (gameId == null || s.gameId == gameId))
            s,
      ];

  List<SessionRow> sessionsIn(StatsPeriod period, {String? gameId}) => _between(_since(period), null, gameId);

  /// Spiel-IDs mit Daten, meistgespielt zuerst (auch unbekannte Spiele).
  List<String> get playedGames {
    final count = <String, int>{};
    for (final s in _sessions) {
      count[s.gameId] = (count[s.gameId] ?? 0) + 1;
    }
    return count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
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

  static Map<String, num> metricsOf(SessionRow s) => _numbers(decode(s.resultJson)['metrics']);

  static Map<String, num> _numbers(Object? m) =>
      m is Map ? {for (final e in m.entries) if (e.value is num) '${e.key}': e.value as num} : const {};

  /// Wert der Hauptkennzahl einer Session, falls sie zählt.
  double? primaryValue(SessionRow s) {
    final pm = PrimaryMetric.forGame(s.gameId);
    final m = _metrics(s);
    if (pm.onlyCompleted && m['completed'] != 1) return null;
    final v = m[pm.key];
    return v?.toDouble();
  }

  // Ergebnisse je Zeitraum und Spiel. Ein Rechner gehört zu genau einem
  // Datenstand (und einem Tag), deshalb rechnen die Reiter, der Plan-
  // Vorschlag und die Ziele jede Auswertung nur einmal; ein Neuaufbau eines
  // Reiters liest sie nur noch. Die Ergebnisse werden nicht verändert.
  final Map<(StatsPeriod, String?), StatsReport> _reports = {};
  final Map<(StatsPeriod, String?), StatsReport?> _previousReports = {};
  final Map<(StatsPeriod, String?), DoubleStats> _doubleStats = {};
  final Map<(String, StatsPeriod), List<TrendPoint>> _trends = {};
  final Map<(String, String, StatsPeriod), List<TrendPoint>> _metricTrends = {};
  final Map<(String, StatsPeriod), List<String>> _metricKeys = {};
  final Map<StatsPeriod, OnlineReport> _onlineReports = {};
  final Map<StatsPeriod, OnlineComparison> _comparisons = {};
  late final List<PersonalRecord> _records = _computeRecords();
  late final Streak _streak = _computeStreak();

  /// Verlauf der Hauptkennzahl eines Spiels.
  List<TrendPoint> trend(String gameId, StatsPeriod period) => _trends.putIfAbsent(
      (gameId, period),
      () => [
            for (final s in sessionsIn(period, gameId: gameId))
              if (primaryValue(s) case final v?) TrendPoint(s.id, s.startedAt, v),
          ]);

  /// Verlauf einer beliebigen Kennzahl [key] eines Spiels. Für die
  /// Hauptkennzahl gilt dieselbe Regel wie in [trend] (nur vollständige
  /// Sessions, wo nötig).
  List<TrendPoint> metricTrend(String gameId, String key, StatsPeriod period) {
    final pm = PrimaryMetric.forGame(gameId);
    if (key == pm.key) return trend(gameId, period);
    return _metricTrends.putIfAbsent(
        (gameId, key, period),
        () => [
              for (final s in sessionsIn(period, gameId: gameId))
                if (_metrics(s)[key] case final v?) TrendPoint(s.id, s.startedAt, v.toDouble()),
            ]);
  }

  /// Kennzahlen eines Spiels, die im Zeitraum vorkommen; Hauptkennzahl zuerst.
  List<String> metricKeys(String gameId, StatsPeriod period) =>
      _metricKeys.putIfAbsent((gameId, period), () => _computeMetricKeys(gameId, period));

  List<String> _computeMetricKeys(String gameId, StatsPeriod period) {
    final keys = <String>{};
    for (final s in sessionsIn(period, gameId: gameId)) {
      keys.addAll(_metrics(s).keys.where((k) => !nonTrendMetrics.contains(k)));
    }
    final primary = PrimaryMetric.forGame(gameId).key;
    return [if (keys.remove(primary)) primary, ...keys.toList()..sort()];
  }

  /// Nachlaufender gleitender Durchschnitt über bis zu [window] Werte.
  static List<double> movingAverage(List<double> values, [int window = movingWindow]) {
    final out = <double>[];
    var sum = 0.0;
    for (var i = 0; i < values.length; i++) {
      sum += values[i];
      if (i >= window) sum -= values[i - window];
      out.add(sum / math.min(i + 1, window));
    }
    return out;
  }

  /// Punkte und Darts einer Session für den 3-Dart-Average.
  ({double points, int darts})? scoringOf(SessionRow s) {
    if (scoringGames.contains(s.gameId)) {
      final c = countedOf(s);
      if (c.isEmpty) return null;
      return (points: c.fold<int>(0, (a, t) => a + t.score).toDouble(), darts: c.length);
    }
    final m = _metrics(s);
    final avg = m['average'];
    if (avg == null) return null;
    final darts = (m['darts'] ?? countedOf(s).length).toInt();
    if (darts <= 0) return null;
    return (points: avg * darts / 3, darts: darts);
  }

  /// Gezählte Darts je Aufnahme einer Session.
  List<List<ThrowRow>> visitsOf(SessionRow s) {
    final out = <List<ThrowRow>>[];
    int? current;
    for (final t in countedOf(s)) {
      if (t.visitIndex != current) {
        out.add([]);
        current = t.visitIndex;
      }
      out.last.add(t);
    }
    return out;
  }

  /// Kennzahlen des gewählten Zeitraums.
  StatsReport report(StatsPeriod period, {String? gameId}) => _reports.putIfAbsent((period, gameId), () {
        final since = _since(period);
        return _report(_between(since, null, gameId), from: since, to: null);
      });

  /// Kennzahlen des gleich langen Zeitraums davor (für den Vergleich);
  /// `null` bei "Alles".
  StatsReport? previousReport(StatsPeriod period, {String? gameId}) {
    final key = (period, gameId);
    if (_previousReports.containsKey(key)) return _previousReports[key];
    return _previousReports[key] = _computePreviousReport(period, gameId);
  }

  StatsReport? _computePreviousReport(StatsPeriod period, String? gameId) {
    final since = _since(period);
    if (since == null) return null;
    final from = DateTime(since.year, since.month, since.day - period.days!);
    return _report(_between(from, since, gameId), from: from, to: since);
  }

  /// Spiele, deren Darts aufs Doppel Checkout-Darts sind (Doppel-Statistik:
  /// Checkout gegen Training). Hier zählt 121 mit, denn dort wird wirklich
  /// aufs Doppel geworfen.
  static const Set<String> checkoutGames = {'checkout', 'one_twenty_one'};

  /// Spiele, in denen ein Ziel mehrere Aufnahmen (3, 6 oder 9 Darts) hat. Ihre
  /// Finishes sind keine normalen 3-Dart-Finishes und zählen deshalb nicht
  /// zu Rekord „Höchstes Finish“, Checkout-Quote, Ziel „Checkout-Quote“,
  /// Auto-Plan-Schwächen und Erfolgen. Sie bleiben in der Doppel-Statistik
  /// ([checkoutGames]) und in der eigenen Wertung des Spiels. Auch mit nur
  /// einer Aufnahme je Ziel zählt 121 nie als normales Finish: einfach und
  /// vorhersehbar statt je nach Einstellung.
  static const Set<String> multiVisitFinishGames = {'one_twenty_one'};

  /// X01-Spiele: Checkout-Darts und gewonnene Legs kommen aus den
  /// Kennzahlen `checkoutDarts` und `legsWon` (Matches speichern nur die
  /// eigenen Darts, deshalb lässt sich dort kein Ziel je Dart nachbauen).
  static const Set<String> x01Games = {'x01', 'x01_match', 'x01_live'};

  /// Doppel-Auswertung des Zeitraums: je Doppel Quote, Daneben-Richtung und
  /// Streubild, dazu der Verlauf (letzte 30 Tage gegen die 30 davor) und
  /// Checkout gegen Training.
  DoubleStats doubleStats(StatsPeriod period, {String? gameId}) =>
      _doubleStats.putIfAbsent((period, gameId), () => _computeDoubleStats(period, gameId));

  DoubleStats _computeDoubleStats(StatsPeriod period, String? gameId) {
    DoubleSource sourceOf(String id) => checkoutGames.contains(id)
        ? DoubleSource.checkout
        : (x01Games.contains(id) ? DoubleSource.none : DoubleSource.training);
    Iterable<DoubleAttempt> attemptsOf(List<SessionRow> sessions) sync* {
      for (final s in sessions) {
        final source = sourceOf(s.gameId);
        for (final a in aimedOf(s)) {
          final n = a.aimedDouble;
          if (n == null) continue;
          final x = a.row.x, y = a.row.y;
          yield DoubleAttempt(
            target: n,
            landed: a.segment,
            time: a.row.timestamp,
            position: x == null || y == null ? null : BoardPoint(x, y),
            source: source,
          );
        }
      }
    }

    final sessions = sessionsIn(period, gameId: gameId);
    var x01 = HitCount.zero;
    for (final s in sessions) {
      if (!x01Games.contains(s.gameId)) continue;
      final m = _metrics(s);
      final darts = (m['checkoutDarts'] ?? 0).toInt();
      if (darts > 0) x01 += HitCount(darts, math.min(darts, (m['legsWon'] ?? 0).toInt()));
    }
    final trendFrom = DateTime(now.year, now.month, now.day - 2 * DoubleStats.trendDays + 1);
    return DoubleStats.build(
      attempts: attemptsOf(sessions),
      trendAttempts: attemptsOf(_between(trendFrom, null, gameId)),
      now: now,
      extraCheckout: x01,
    );
  }

  StatsReport _report(List<SessionRow> sessions, {required DateTime? from, required DateTime? to}) {
    final counted = [for (final s in sessions) ...countedOf(s)];

    // 3-Dart-Average.
    var points = 0.0;
    var scoringDarts = 0;
    for (final s in sessions) {
      if (scoringOf(s) case final sc?) {
        points += sc.points;
        scoringDarts += sc.darts;
      }
    }
    final first9 = [for (final s in sessions) ?_metrics(s)['first9']];

    // Checkouts aus dem Checkout-Training (121 zählt nicht).
    var checkouts = HitCount.zero;
    final byRange = <CheckoutRange, HitCount>{};
    for (final a in _checkoutAttempts(sessions)) {
      final h = HitCount(1, a.success ? 1 : 0);
      checkouts += h;
      if (CheckoutRange.of(a.target) case final r?) byRange[r] = (byRange[r] ?? HitCount.zero) + h;
    }

    // Darts mit bekanntem Ziel.
    final doubles = <int, HitCount>{};
    final trebles = <int, HitCount>{};
    final accuracyByGame = <String, HitCount>{};
    var accuracy = HitCount.zero;
    for (final s in sessions) {
      for (final a in aimedOf(s)) {
        if (a.targets.isEmpty) continue;
        final h = HitCount(1, a.onTarget ? 1 : 0);
        accuracy += h;
        accuracyByGame[s.gameId] = (accuracyByGame[s.gameId] ?? HitCount.zero) + h;
        if (a.aimedDouble case final n?) doubles[n] = (doubles[n] ?? HitCount.zero) + h;
        if (a.aimedTreble case final n?) trebles[n] = (trebles[n] ?? HitCount.zero) + h;
      }
    }
    final doubleTotal = doubles.values.fold(HitCount.zero, (a, b) => a + b);
    final trebleTotal = trebles.values.fold(HitCount.zero, (a, b) => a + b);
    final doubleFallback = _metricRate(sessions, 'bobs_27', 'hits');
    final trebleFallback = _metricRate(sessions, 'target_practice', 'trebles');

    // Überblick je Spiel.
    final byGame = <String, List<SessionRow>>{};
    for (final s in sessions) {
      byGame.putIfAbsent(s.gameId, () => []).add(s);
    }
    final games = [
      for (final e in byGame.entries) _gameSummary(e.key, e.value, accuracyByGame[e.key] ?? HitCount.zero),
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
      final d = _dayOf(t.timestamp);
      perDay[d] = (perDay[d] ?? 0) + 1;
    }
    final lastDay = to == null ? dayOf(now) : DateTime(to.year, to.month, to.day - 1);
    final firstDay = from ?? (perDay.isEmpty ? lastDay : perDay.keys.reduce((a, b) => a.isBefore(b) ? a : b));
    final daily = <({DateTime day, int darts})>[];
    for (var d = firstDay; !d.isAfter(lastDay); d = DateTime(d.year, d.month, d.day + 1)) {
      daily.add((day: d, darts: perDay[d] ?? 0));
    }

    // Wochen, Wochentage, Tageszeiten (nach Session-Beginn).
    final weekMap = <DateTime, ActivityBucket>{};
    final weekdays = List.filled(7, const ActivityBucket());
    final dayParts = List.filled(DayPart.values.length, const ActivityBucket());
    final avgPerDay = <DateTime, ({double points, int darts})>{};
    var trainingTime = Duration.zero;
    for (final s in sessions) {
      final sc = scoringOf(s);
      ActivityBucket add(ActivityBucket b) =>
          b.add(sessions: 1, darts: countedOf(s).length, points: sc?.points ?? 0, scoringDarts: sc?.darts ?? 0);
      final w = weekOf(s.startedAt);
      weekMap[w] = add(weekMap[w] ?? const ActivityBucket());
      weekdays[s.startedAt.weekday - 1] = add(weekdays[s.startedAt.weekday - 1]);
      final part = DayPart.of(s.startedAt).index;
      dayParts[part] = add(dayParts[part]);
      if (sc != null) {
        final d = dayOf(s.startedAt);
        final prev = avgPerDay[d];
        avgPerDay[d] = (points: (prev?.points ?? 0) + sc.points, darts: (prev?.darts ?? 0) + sc.darts);
      }
      final dur = s.endedAt!.difference(s.startedAt);
      trainingTime += dur.isNegative ? Duration.zero : (dur > maxSessionDuration ? maxSessionDuration : dur);
    }
    final weekly = <WeekVolume>[];
    for (var w = weekOf(firstDay); !w.isAfter(lastDay); w = DateTime(w.year, w.month, w.day + 7)) {
      weekly.add(WeekVolume(w, weekMap[w] ?? const ActivityBucket()));
    }
    final averageTrend = [
      for (final e in avgPerDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        TrendPoint(0, e.key, e.value.points / e.value.darts * 3),
    ];

    return StatsReport._(
      sessions: sessions.length,
      darts: counted.length,
      practiceDays: {for (final s in sessions) dayOf(s.startedAt)}.length,
      trainingTime: trainingTime,
      scoringAverage: scoringDarts == 0 ? null : points / scoringDarts * 3,
      scoringDarts: scoringDarts,
      first9Average: first9.isEmpty ? null : first9.fold<num>(0, (a, b) => a + b) / first9.length,
      checkoutRate: checkouts.rate,
      checkoutAttempts: checkouts.attempts,
      checkoutByRange: byRange,
      doubleRate: doubleTotal.attempts > 0 ? doubleTotal.rate : doubleFallback?.rate,
      doubleAttempts: doubleTotal.attempts > 0 ? doubleTotal.attempts : doubleFallback?.attempts ?? 0,
      trebleRate: trebleTotal.attempts > 0 ? trebleTotal.rate : trebleFallback?.rate,
      trebleAttempts: trebleTotal.attempts > 0 ? trebleTotal.attempts : trebleFallback?.attempts ?? 0,
      doubles: doubles,
      trebles: trebles,
      accuracy: accuracy,
      scoring: _scoringStats(sessions),
      games: games,
      heat: heat,
      numberHits: numberHits,
      dailyDarts: daily,
      weekly: weekly,
      weekdays: weekdays,
      dayParts: dayParts,
      averageTrend: averageTrend,
      streak: streak(),
    );
  }

  /// Quote aus zwei Kennzahlen eines Spiels, z. B. Treffer / Darts.
  HitCount? _metricRate(List<SessionRow> sessions, String gameId, String hitsKey) {
    var darts = 0;
    var hits = 0;
    for (final s in sessions) {
      if (s.gameId != gameId) continue;
      final m = _metrics(s);
      darts += (m['darts'] ?? 0).toInt();
      hits += (m[hitsKey] ?? 0).toInt();
    }
    return darts == 0 ? null : HitCount(darts, hits);
  }

  /// Checkout-Versuche aus dem Checkout-Training. 121 zählt nicht: Dort hat
  /// ein Ziel mehrere Aufnahmen ([multiVisitFinishGames]).
  Iterable<({int target, bool success, DateTime time})> _checkoutAttempts(List<SessionRow> sessions) sync* {
    for (final s in sessions) {
      final details = _result(s)['details'];
      if (details is! Map) continue;
      final list = s.gameId == 'checkout' ? details['attempts'] : null;
      if (list is! List) continue;
      for (final a in list) {
        if (a is! Map) continue;
        final t = a['target'];
        yield (target: t is num ? t.toInt() : 0, success: a['success'] == true, time: s.startedAt);
      }
    }
  }

  ScoringStats? _scoringStats(List<SessionRow> sessions) {
    final scores = <int>[];
    for (final s in sessions) {
      if (!isVisitScoringGame(s.gameId)) continue;
      for (final v in visitsOf(s)) {
        if (v.length == 3) scores.add(v.fold(0, (a, t) => a + t.score));
      }
    }
    if (scores.isEmpty) return null;
    final mean = scores.fold(0, (a, b) => a + b) / scores.length;
    final variance = scores.fold<double>(0, (a, b) => a + (b - mean) * (b - mean)) / scores.length;
    final bands = <ScoreBand, int>{};
    for (final sc in scores) {
      final b = ScoreBand.of(sc);
      bands[b] = (bands[b] ?? 0) + 1;
    }
    return ScoringStats(
      visits: scores.length,
      mean: mean,
      stdDev: math.sqrt(variance),
      highest: scores.reduce(math.max),
      bands: bands,
    );
  }

  GameSummary _gameSummary(String gameId, List<SessionRow> sessions, HitCount accuracy) {
    final pm = PrimaryMetric.forGame(gameId);
    double? best;
    DateTime? bestAt;
    double? last;
    for (final s in sessions) {
      final v = primaryValue(s);
      if (v == null) continue;
      last = v;
      if (best == null || (pm.higherIsBetter ? v > best : v < best)) {
        best = v;
        bestAt = s.startedAt;
      }
    }
    return GameSummary(
      gameId: gameId,
      sessions: sessions.length,
      darts: sessions.fold(0, (a, s) => a + s.dartCount),
      best: best,
      bestAt: bestAt,
      last: last,
      accuracy: accuracy,
    );
  }

  /// Persönliche Rekorde über alle Daten des Profils. Arten ohne Daten
  /// fehlen in der Liste.
  List<PersonalRecord> records() => _records;

  List<PersonalRecord> _computeRecords() {
    final out = <PersonalRecord>[];
    PersonalRecord? bestOf(Iterable<PersonalRecord> candidates) {
      PersonalRecord? best;
      for (final c in candidates) {
        if (best == null || c.value > best.value) best = c;
      }
      return best;
    }

    void add(PersonalRecord? r) {
      if (r != null && r.value > 0) out.add(r);
    }

    add(bestOf([
      for (final s in _sessions)
        if (scoringOf(s) case final sc? when sc.darts >= 9)
          PersonalRecord(RecordKind.bestAverage, sc.points / sc.darts * 3, date: s.startedAt, gameId: s.gameId),
    ]));
    add(bestOf([
      for (final s in _sessions)
        if (_metrics(s)['first9'] case final v?)
          PersonalRecord(RecordKind.bestFirst9, v.toDouble(), date: s.startedAt, gameId: s.gameId),
    ]));
    add(bestOf([
      for (final s in _sessions)
        if (isVisitScoringGame(s.gameId))
          for (final v in visitsOf(s))
            PersonalRecord(RecordKind.highestVisit, v.fold<int>(0, (a, t) => a + t.score).toDouble(),
                date: v.first.timestamp, gameId: s.gameId),
    ]));
    add(bestOf([
      for (final a in _checkoutAttempts(_sessions))
        if (a.success) PersonalRecord(RecordKind.highestCheckout, a.target.toDouble(), date: a.time),
      for (final s in _sessions)
        if (!multiVisitFinishGames.contains(s.gameId))
          if (_metrics(s)['highestCheckout'] case final v?)
            PersonalRecord(RecordKind.highestCheckout, v.toDouble(), date: s.startedAt, gameId: s.gameId),
    ]));
    add(bestOf([
      for (final s in _sessions)
        if (isVisitScoringGame(s.gameId))
          PersonalRecord(
            RecordKind.most180s,
            visitsOf(s).where((v) => v.length == 3 && v.fold(0, (a, t) => a + t.score) == 180).length.toDouble(),
            date: s.startedAt,
            gameId: s.gameId,
          ),
    ]));
    final perDay = <DateTime, int>{};
    for (final s in _sessions) {
      for (final t in countedOf(s)) {
        final d = _dayOf(t.timestamp);
        perDay[d] = (perDay[d] ?? 0) + 1;
      }
    }
    add(bestOf([
      for (final e in perDay.entries) PersonalRecord(RecordKind.mostDartsDay, e.value.toDouble(), date: e.key),
    ]));
    final st = streak();
    if (st.longest > 1) out.add(PersonalRecord(RecordKind.longestStreak, st.longest.toDouble(), date: st.longestEnd));
    return out;
  }

  /// Aufeinanderfolgende Trainingstage. Die aktuelle Serie zählt auch, wenn
  /// heute noch nicht trainiert wurde, aber gestern.
  Streak streak() => _streak;

  Streak _computeStreak() {
    final days = {for (final s in _sessions) dayOf(s.startedAt)}.toList()..sort();
    if (days.isEmpty) return const Streak(current: 0, longest: 0, trainedToday: false);
    var longest = 1;
    var longestEnd = days.first;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      run = _isNextDay(days[i - 1], days[i]) ? run + 1 : 1;
      if (run > longest) {
        longest = run;
        longestEnd = days[i];
      }
    }
    final today = dayOf(now);
    final last = days.last;
    final trainedToday = last == today;
    final current = trainedToday || _isNextDay(last, today) ? run : 0;
    return Streak(current: current, longest: longest, trainedToday: trainedToday, longestEnd: longestEnd);
  }

  static bool _isNextDay(DateTime a, DateTime b) => DateTime(a.year, a.month, a.day + 1) == b;

  // -------------------------------------------------------------------------
  // Online-Matches (Autodarts Live) und Training gegen Match
  // -------------------------------------------------------------------------

  final Map<int, Map<int, HitCount>> _liveDoublesCache = {};
  final Map<int, OnlineMatch> _onlineMatchCache = {};

  /// Darts aufs Finish-Doppel einer Live-Session mit „X01 mitzählen“, je
  /// Doppel. Die Session wird mit ihren gespeicherten Darts und Leg-
  /// Markierungen noch einmal abgespielt ([LiveX01.replay]); ein Dart zählt,
  /// wenn der Checkout-Weg für die restlichen Darts der Aufnahme genau ein
  /// Doppel war (wie bei X01-Solo). Ohne X01 leer.
  Map<int, HitCount> liveDoublesOf(SessionRow s) => _liveDoublesCache.putIfAbsent(s.id, () {
        final x = _liveX01Of(s);
        if (x == null) return const {};
        final visits = _visitsOf(throwsOf(s));
        final out = <int, HitCount>{};
        var i = 0;
        for (final v in visits) {
          for (final seg in v) {
            final n = i < x.aimedDoubles.length ? x.aimedDoubles[i] : null;
            i++;
            if (n == null) continue;
            out[n] = (out[n] ?? HitCount.zero) + HitCount(1, classifyDoubleMiss(n, seg) == null ? 1 : 0);
          }
        }
        return out;
      });

  /// Alle Würfe einer Session als Aufnahmen (Segmente).
  static List<List<Segment>> _visitsOf(List<ThrowRow> rows) {
    final visits = <List<Segment>>[];
    int? current;
    for (final t in rows) {
      if (t.visitIndex != current || visits.isEmpty) {
        visits.add([]);
        current = t.visitIndex;
      }
      visits.last.add(segmentOf(t) ?? Segment.miss);
    }
    return visits;
  }

  /// Eine Live-Session mit „X01 mitzählen“, mit ihren gespeicherten Darts
  /// und Leg-Markierungen nachgespielt; `null` für andere Sessions.
  LiveX01? _liveX01Of(SessionRow s) {
    if (s.gameId != autodartsLiveX01GameId) return null;
    final config = LiveX01Config.fromJson(decode(s.configJson)['x01']);
    final rows = throwsOf(s);
    if (config == null || rows.isEmpty) return null;
    final details = _result(s)['details'];
    return LiveX01.replay(config, _visitsOf(rows), legMarksFromJson(details is Map ? details['marks'] : null), visitOpen: false);
  }

  /// Eine Live-Session als Match-Eintrag (`null` für andere Spiele).
  OnlineMatch? onlineMatchOf(SessionRow s) {
    if (!isOnlineGame(s.gameId)) return null;
    return _onlineMatchCache.putIfAbsent(s.id, () {
      final m = _metrics(s);
      final x01 = s.gameId == autodartsLiveX01GameId;
      int n(String k) => (m[k] ?? 0).toInt();
      final details = _result(s)['details'];
      final rawLegs = x01 && details is Map ? details['legs'] : null;
      final legs = <OnlineLeg>[
        if (rawLegs is List)
          for (final l in rawLegs)
            if (l is Map && (l['darts'] as num? ?? 0) > 0)
              OnlineLeg(
                darts: (l['darts'] as num).toInt(),
                points: (l['points'] as num? ?? 0).toInt(),
                first9: switch (l['first9']) {
                  final num v when v > 0 => v.toDouble(),
                  _ => null,
                },
                checkout: (l['checkout'] as num? ?? 0).toInt(),
                won: l['won'] == true,
              ),
      ];
      final sc = scoringOf(s);
      final dur = (s.endedAt ?? s.startedAt).difference(s.startedAt);
      final checkoutDarts = x01 ? n('checkoutDarts') : 0;
      final rawOpponents = details is Map ? details['opponents'] : null;
      final opponents = rawOpponents is List ? rawOpponents : const [];
      return OnlineMatch(
        sessionId: s.id,
        startedAt: s.startedAt,
        duration: dur.isNegative ? Duration.zero : dur,
        x01: x01,
        darts: sc?.darts ?? countedOf(s).length,
        average: sc == null ? null : sc.points / sc.darts * 3,
        first9: x01 ? m['first9']?.toDouble() : null,
        legsWon: x01 ? n('legsWon') : 0,
        legsLost: x01 ? n('legsLost') : 0,
        checkout: HitCount(checkoutDarts, math.min(checkoutDarts, x01 ? n('legsWon') : 0)),
        highestFinish: x01 ? n('highestFinish') : 0,
        count100: n('count100'),
        count140: n('count140'),
        count180: n('count180'),
        legs: legs,
        opponent: opponents.isEmpty ? null : '${opponents.first}',
        won: m['won'] == null ? null : m['won'] == 1,
      );
    });
  }

  /// Online-Matches im Zeitraum: Liste, Summen und Wochen.
  OnlineReport onlineReport(StatsPeriod period) => _onlineReports.putIfAbsent(period, () {
        final matches = [
          for (final s in sessionsIn(period)) ?onlineMatchOf(s),
        ];
        var totals = const OnlineTotals();
        final weeks = <DateTime, OnlineTotals>{};
        for (final m in matches) {
          totals = totals.add(m);
          final w = weekOf(m.startedAt);
          weeks[w] = (weeks[w] ?? const OnlineTotals()).add(m);
        }
        return OnlineReport(
          matches: matches.reversed.toList(),
          totals: totals,
          weeks: [
            for (final w in weeks.keys.toList()..sort()) (weekStart: w, totals: weeks[w]!),
          ],
        );
      });

  // -------------------------------------------------------------------------
  // Haus-Elo
  // -------------------------------------------------------------------------

  /// Gewertete Matches je Session (`null` = zählt nicht), einmal dekodiert und
  /// für unveränderte Sessions aus dem vorigen Rechner übernommen.
  final Map<int, EloMatch?> _eloMatchCache = {};

  /// Die Session als gewertetes Match fürs Haus-Elo; `null`, wenn sie nicht
  /// zählt (Regel in [EloMatch.fromSession]). Trainings-Sessions werden nicht
  /// einmal dekodiert.
  EloMatch? eloMatchOf(SessionRow s) {
    if (s.gameId != matchGameId && s.gameId != autodartsLiveX01GameId) return null;
    if (_eloMatchCache.containsKey(s.id)) return _eloMatchCache[s.id];
    return _eloMatchCache[s.id] = EloMatch.fromSession(
      sessionId: s.id,
      uid: s.uid,
      gameId: s.gameId,
      startedAt: s.startedAt,
      finished: s.finished,
      config: decode(s.configJson),
      result: _result(s),
    );
  }

  /// Haus-Elo über **alle** Matches des Profils, unabhängig vom Zeitraum
  /// (siehe `docs/haus-elo.md`). Ein Lauf je Rechner.
  late final HouseEloReport houseElo = HouseElo.compute([
    for (final s in _sessions) ?eloMatchOf(s),
  ]);

  /// Training gegen Match im Zeitraum. Welche Spiele für welche Kennzahl
  /// als Training zählen, steht in [TrainingSources].
  OnlineComparison onlineComparison(StatsPeriod period) =>
      _comparisons.putIfAbsent(period, () => _computeComparison(sessionsIn(period)));

  OnlineComparison _computeComparison(List<SessionRow> sessions) {
    final online = [for (final s in sessions) if (isOnlineGame(s.gameId)) s];
    bool training(SessionRow s, Set<String> ids) => ids.contains(s.gameId);

    // Average: Punkte und Darts wie im StatsReport.
    CompareSide averageOf(Iterable<SessionRow> list) {
      var points = 0.0;
      var darts = 0;
      for (final s in list) {
        if (scoringOf(s) case final sc?) {
          points += sc.points;
          darts += sc.darts;
        }
      }
      return CompareSide(darts == 0 ? null : points / darts * 3, darts);
    }

    // First 9 je abgeschlossenem Leg (aus den gespeicherten Legs).
    CompareSide first9Of(Iterable<SessionRow> list) {
      var sum = 0.0;
      var legs = 0;
      for (final s in list) {
        final raw = _result(s)['details'];
        final list = raw is Map ? raw['legs'] : null;
        if (list is! List) continue;
        for (final l in list) {
          if (l is! Map || (l['darts'] as num? ?? 0) <= 0) continue;
          if (l['first9'] case final num v when v > 0) {
            sum += v;
            legs++;
          }
        }
      }
      return CompareSide(legs == 0 ? null : sum / legs, legs);
    }

    // Checkout-Quote: gewonnene Legs je Dart aufs Finish.
    CompareSide checkoutOf(Iterable<SessionRow> list) {
      var h = HitCount.zero;
      for (final s in list) {
        final m = _metrics(s);
        final darts = (m['checkoutDarts'] ?? 0).toInt();
        if (darts > 0) h += HitCount(darts, math.min(darts, (m['legsWon'] ?? 0).toInt()));
      }
      return CompareSide(h.rate, h.attempts);
    }

    // Volle Aufnahmen (drei gezählte Darts) je Punktebereich.
    Map<ScoreBand, int> bandsOf(Iterable<SessionRow> list) {
      final bands = <ScoreBand, int>{};
      for (final s in list) {
        for (final v in visitsOf(s)) {
          if (v.length != 3) continue;
          final b = ScoreBand.of(v.fold(0, (a, t) => a + t.score));
          bands[b] = (bands[b] ?? 0) + 1;
        }
      }
      return bands;
    }

    CompareSide tonsOf(Map<ScoreBand, int> bands) {
      final total = OnlineComparison.bandTotal(bands);
      final tons = [for (final b in ScoreBand.values) if (b.min >= 100) bands[b] ?? 0].fold(0, (a, b) => a + b);
      return CompareSide(total == 0 ? null : tons / total, total);
    }

    // Doppel: online aus dem nachgespielten X01, im Training die Darts mit
    // genau einem Doppel als Ziel.
    final onlineDoubles = <int, HitCount>{};
    for (final s in online) {
      for (final e in liveDoublesOf(s).entries) {
        onlineDoubles[e.key] = (onlineDoubles[e.key] ?? HitCount.zero) + e.value;
      }
    }
    final trainingDoubles = <int, HitCount>{};
    for (final s in sessions) {
      if (!TrainingSources.doubles(s.gameId)) continue;
      for (final a in aimedOf(s)) {
        final n = a.aimedDouble;
        if (n == null) continue;
        trainingDoubles[n] = (trainingDoubles[n] ?? HitCount.zero) + HitCount(1, a.onTarget ? 1 : 0);
      }
    }
    HitCount sum(Map<int, HitCount> m) => m.values.fold(HitCount.zero, (a, b) => a + b);
    final od = sum(onlineDoubles);
    final td = sum(trainingDoubles);

    final x01Online = [for (final s in online) if (s.gameId == autodartsLiveX01GameId) s];
    final scoringTraining = [for (final s in sessions) if (training(s, TrainingSources.scoring)) s];
    final legTraining = [for (final s in sessions) if (training(s, TrainingSources.legs)) s];
    final onlineBands = bandsOf(online);
    final trainingBands = bandsOf(scoringTraining);

    return OnlineComparison(
      average: MetricComparison(CompareMetric.average, averageOf(online), averageOf(scoringTraining)),
      first9: MetricComparison(CompareMetric.first9, first9Of(x01Online), first9Of(legTraining)),
      checkout: MetricComparison(CompareMetric.checkoutRate, checkoutOf(x01Online), checkoutOf(legTraining)),
      doubles: MetricComparison(
        CompareMetric.doubleRate,
        CompareSide(od.rate, od.attempts),
        CompareSide(td.rate, td.attempts),
      ),
      scoring: MetricComparison(CompareMetric.scoring, tonsOf(onlineBands), tonsOf(trainingBands)),
      perDouble: {
        for (final n in {...onlineDoubles.keys, ...trainingDoubles.keys})
          n: DoubleComparison(n, onlineDoubles[n] ?? HitCount.zero, trainingDoubles[n] ?? HitCount.zero),
      },
      onlineBands: onlineBands,
      trainingBands: trainingBands,
    );
  }

  // -------------------------------------------------------------------------
  // Streuungs-Analyse
  // -------------------------------------------------------------------------

  final Map<int, ({List<ScatterDart> darts, int positioned})> _scatterCache = {};
  final Map<(StatsPeriod, String?, ScatterScope), ScatterReport> _scatterReports = {};

  /// Match statt Training: Bot-/Mensch-Matches und Online-Matches.
  static bool isMatchSession(String gameId) => gameId == matchGameId || isOnlineGame(gameId);

  /// Darts einer Session mit Position und Zielfeld (siehe
  /// docs/streuungs-analyse.md) und die Zahl ihrer Darts mit Position.
  ///
  /// * Trainingsspiele: Ziel aus dem nachgespielten Spiel ([aimedOf]); genau
  ///   ein Feld ist exakt, sonst werden T20/T19/Bull geschätzt.
  /// * Online-Matches mit X01 und Matches: Rest nachgerechnet; Finish-Doppel
  ///   und Scoring-Darts (T20/T19) geschätzt.
  /// * Sonst (Autodarts Live ohne X01): T20/T19/Bull geschätzt.
  ({List<ScatterDart> darts, int positioned}) scatterOf(SessionRow s) =>
      _scatterCache.putIfAbsent(s.id, () => _computeScatter(s));

  ({List<ScatterDart> darts, int positioned}) _computeScatter(SessionRow s) {
    var positioned = 0;
    for (final t in throwsOf(s)) {
      if (t.counted && t.x != null && t.y != null && t.source != 'manual') positioned++;
    }
    // Ohne Positionen (manuelle Eingabe) nichts nachspielen.
    if (positioned == 0) return (darts: const [], positioned: 0);
    final out = <ScatterDart>[];
    void add(ThrowRow t, Segment? landed, DartAim? aim) {
      if (aim == null || landed == null) return;
      if (scatterDartOf(t, landed, aim) case final d?) out.add(d);
    }

    final live = _liveX01Of(s);
    if (GameCatalog.byId(s.gameId) != null) {
      final aimed = aimedOf(s);
      if (aimed.isNotEmpty) {
        for (final a in aimed) {
          add(a.row, a.segment, TargetsAim(a.targets));
        }
      } else {
        // Nachspielen fehlgeschlagen: wie ohne bekanntes Ziel.
        for (final t in countedOf(s)) {
          add(t, segmentOf(t), const UnknownAim());
        }
      }
    } else if (live != null) {
      final x = live;
      final rows = throwsOf(s);
      for (var i = 0; i < rows.length && i < x.counted.length; i++) {
        if (!x.counted[i]) continue;
        final n = x.aimedDoubles[i];
        add(
          rows[i],
          segmentOf(rows[i]),
          n != null
              ? RuleAim(n == 25 ? Segment.bull : Segment.double(n))
              : (x.remainingBefore[i] >= ScatterRules.scoringRemaining ? const ScoringAim() : null),
        );
      }
    } else if (s.gameId == matchGameId) {
      final counted = countedOf(s);
      final format = MatchFormat.fromJson(decode(s.configJson));
      final details = _result(s)['details'];
      final legs = details is Map ? details['legs'] : null;
      final aims = x01AimsOf(
        counted,
        startScore: format.startScore,
        out: format.outMode,
        doubleIn: format.doubleIn,
        legEnds: [
          if (legs is List)
            for (final l in legs)
              if (l is Map && l['visit'] is num) (l['visit'] as num).toInt(),
        ]..sort(),
      );
      for (var i = 0; i < counted.length; i++) {
        add(counted[i], segmentOf(counted[i]), aims[i]);
      }
    } else {
      for (final t in countedOf(s)) {
        add(t, segmentOf(t), const UnknownAim());
      }
    }
    return (darts: out, positioned: positioned);
  }

  /// Streuungs-Analyse des Zeitraums (je Zeitraum, Spiel und Auswahl
  /// Training/Match zwischengespeichert).
  ScatterReport scatterReport(StatsPeriod period, {String? gameId, ScatterScope scope = ScatterScope.all}) =>
      _scatterReports.putIfAbsent((period, gameId, scope), () {
        var positioned = 0;
        final darts = <ScatterDart>[];
        for (final s in sessionsIn(period, gameId: gameId)) {
          final match = isMatchSession(s.gameId);
          if ((scope == ScatterScope.training && match) || (scope == ScatterScope.match && !match)) continue;
          final sc = scatterOf(s);
          positioned += sc.positioned;
          darts.addAll(sc.darts);
        }
        return ScatterReport.build(darts, positioned: positioned);
      });

  // -------------------------------------------------------------------------
  // Wurftempo
  // -------------------------------------------------------------------------

  final Map<int, SessionTempo> _tempoCache = {};
  final Map<(StatsPeriod, String?), TempoReport> _tempoReports = {};

  /// Zeiten einer Session (einmal berechnet, wie die anderen Zwischenstände
  /// für unveränderte Sessions aus dem vorigen Rechner übernommen).
  SessionTempo tempoOf(SessionRow s) => _tempoCache.putIfAbsent(s.id, () => SessionTempo.of(s, throwsOf(s)));

  /// Wurftempo des Zeitraums (siehe docs/wurftempo.md), je Zeitraum und Spiel
  /// zwischengespeichert. Der Verlauf deckt immer die letzten
  /// [TempoRules.trendWeeks] Wochen ab, auch bei kurzem Zeitraum.
  TempoReport tempoReport(StatsPeriod period, {String? gameId}) => _tempoReports.putIfAbsent((period, gameId), () {
        final trendFrom = weekOf(DateTime(now.year, now.month, now.day - 7 * (TempoRules.trendWeeks - 1)));
        final perWeek = <DateTime, List<TempoVisit>>{};
        for (final s in _between(trendFrom, null, gameId)) {
          for (final v in tempoOf(s).visits) {
            perWeek.putIfAbsent(weekOf(v.start), () => []).add(v);
          }
        }
        final weeks = perWeek.keys.toList()..sort();
        return TempoReport.build(
          sessions: [for (final s in sessionsIn(period, gameId: gameId)) tempoOf(s)],
          trend: [for (final w in weeks) if (!w.isBefore(trendFrom)) (w, perWeek[w]!)],
        );
      });

  /// Beginn der aktuellen Woche (Montag).
  DateTime get weekStart => weekOf(now);

  /// Sessions und Darts seit Wochenbeginn.
  ({int sessions, int darts}) thisWeek() {
    final ws = weekStart;
    final s = [for (final x in _sessions) if (!x.startedAt.isBefore(ws)) x];
    return (sessions: s.length, darts: s.fold(0, (a, x) => a + x.dartCount));
  }
}
