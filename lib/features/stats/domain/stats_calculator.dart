import 'dart:convert';
import 'dart:math' as math;

import '../../../core/database/app_database.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import 'game_metrics.dart';
import 'stats_models.dart';
import 'target_replay.dart';

export 'stats_models.dart';

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

  /// Checkout-Quote aus Checkout-Training und 121.
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
  StatsCalculator({required List<SessionRow> sessions, required this.throws, DateTime? now})
      : _sessions = sessions.where((s) => s.endedAt != null).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt)),
        now = now ?? DateTime.now();

  final List<SessionRow> _sessions;
  final List<ThrowRow> throws;
  final DateTime now;

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
      m.putIfAbsent(t.sessionId, () => []).add(t);
    }
    for (final l in m.values) {
      l.sort((a, b) => a.seq.compareTo(b.seq));
    }
    return m;
  }();

  final Map<int, List<ThrowRow>> _countedCache = {};
  final Map<int, List<AimedDart>> _aimedCache = {};
  final Map<int, Map<String, num>> _metricsCache = {};

  /// Gezählte Würfe einer Session in Wurfreihenfolge.
  List<ThrowRow> countedOf(SessionRow s) =>
      _countedCache.putIfAbsent(s.id, () => [for (final t in _bySession[s.id] ?? const <ThrowRow>[]) if (t.counted) t]);

  /// Gezählte Würfe mit dem Ziel, das das Spiel vorgab (siehe [replayTargets]).
  List<AimedDart> aimedOf(SessionRow s) =>
      _aimedCache.putIfAbsent(s.id, () => replayTargets(s, _bySession[s.id] ?? const [], decode(s.configJson)));

  final Map<int, Map<String, Object?>> _resultCache = {};

  /// Gespeichertes Ergebnis einer Session (einmal dekodiert).
  Map<String, Object?> _result(SessionRow s) => _resultCache.putIfAbsent(s.id, () => decode(s.resultJson));
  Map<String, num> _metrics(SessionRow s) => _metricsCache.putIfAbsent(s.id, () => _numbers(_result(s)['metrics']));

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

  /// Verlauf der Hauptkennzahl eines Spiels.
  List<TrendPoint> trend(String gameId, StatsPeriod period) => [
        for (final s in sessionsIn(period, gameId: gameId))
          if (primaryValue(s) case final v?) TrendPoint(s.id, s.startedAt, v),
      ];

  /// Verlauf einer beliebigen Kennzahl [key] eines Spiels. Für die
  /// Hauptkennzahl gilt dieselbe Regel wie in [trend] (nur vollständige
  /// Sessions, wo nötig).
  List<TrendPoint> metricTrend(String gameId, String key, StatsPeriod period) {
    final pm = PrimaryMetric.forGame(gameId);
    if (key == pm.key) return trend(gameId, period);
    return [
      for (final s in sessionsIn(period, gameId: gameId))
        if (_metrics(s)[key] case final v?) TrendPoint(s.id, s.startedAt, v.toDouble()),
    ];
  }

  /// Kennzahlen eines Spiels, die im Zeitraum vorkommen; Hauptkennzahl zuerst.
  List<String> metricKeys(String gameId, StatsPeriod period) {
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
  StatsReport report(StatsPeriod period, {String? gameId}) {
    final since = _since(period);
    return _report(_between(since, null, gameId), from: since, to: null);
  }

  /// Kennzahlen des gleich langen Zeitraums davor (für den Vergleich);
  /// `null` bei "Alles".
  StatsReport? previousReport(StatsPeriod period, {String? gameId}) {
    final since = _since(period);
    if (since == null) return null;
    final from = DateTime(since.year, since.month, since.day - period.days!);
    return _report(_between(from, since, gameId), from: from, to: since);
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

    // Checkouts aus Checkout-Training und 121.
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

  /// Checkout-Versuche aus Checkout-Training und 121.
  Iterable<({int target, bool success, DateTime time})> _checkoutAttempts(List<SessionRow> sessions) sync* {
    for (final s in sessions) {
      final details = _result(s)['details'];
      if (details is! Map) continue;
      final list = s.gameId == 'checkout' ? details['attempts'] : (s.gameId == 'one_twenty_one' ? details['rounds'] : null);
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
  List<PersonalRecord> records() {
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
  Streak streak() {
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

  /// Beginn der aktuellen Woche (Montag).
  DateTime get weekStart => weekOf(now);

  /// Sessions und Darts seit Wochenbeginn.
  ({int sessions, int darts}) thisWeek() {
    final ws = weekStart;
    final s = [for (final x in _sessions) if (!x.startedAt.isBefore(ws)) x];
    return (sessions: s.length, darts: s.fold(0, (a, x) => a + x.dartCount));
  }
}
