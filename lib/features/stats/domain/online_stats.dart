/// Online-Matches (Autodarts Live) und der Vergleich Training gegen Match.
/// Reine Werte, berechnet im `StatsCalculator`; siehe
/// `docs/online-matches.md` für die genauen Regeln.
library;

import '../../autodarts_live/domain/live_stats.dart';
import '../../matches/domain/match_result.dart';
import 'stats_models.dart';

/// Spiele, deren Sessions Online-Matches sind: mitgeschriebene Darts vom
/// eigenen Board, mit oder ohne „X01 mitzählen“.
const Set<String> onlineGameIds = {autodartsLiveGameId, autodartsLiveX01GameId};

bool isOnlineGame(String gameId) => onlineGameIds.contains(gameId);

/// Welche Spiele im Vergleich als Training zählen, je Kennzahl. Online-
/// Matches und Bot-Matches zählen nie als Training (Bot-Matches sind auch
/// kein Online-Match und fehlen im Vergleich ganz).
abstract final class TrainingSources {
  /// X01-Solo: Average, First 9, Checkout-Quote und Aufnahmen wie im Match.
  static const String x01 = 'x01';

  /// Average und Punkteverteilung: X01-Solo und die Scoring-Drills (dort
  /// zählen die Rohpunkte aller Darts).
  static const Set<String> scoring = {x01, 'target_practice', 'score_target', 'highscore_hunt'};

  /// First 9 und Checkout-Quote gibt es nur in X01-Solo.
  static const Set<String> legs = {x01};

  /// Doppelquote: jedes Trainingsspiel, in dem ein Dart genau ein Doppel als
  /// Ziel hatte (Checkout-Training, 121, X01-Solo auf dem Finish, Bob's 27,
  /// Doppel-Spiele, Around the Clock auf Doppel …).
  static bool doubles(String gameId) => !isOnlineGame(gameId) && gameId != matchGameId;
}

/// Ein Leg eines Online-Matches (nur mit „X01 mitzählen“).
class OnlineLeg {
  const OnlineLeg({required this.darts, required this.points, required this.first9, required this.checkout, required this.won});

  final int darts;

  /// Abgezogene Punkte (Bust-Aufnahmen zählen 0).
  final int points;
  final double? first9;

  /// Gecheckter Rest, 0 ohne Checkout.
  final int checkout;
  final bool won;

  double? get average => darts == 0 ? null : points / darts * 3;
}

/// Eine Live-Session als Match-Eintrag.
class OnlineMatch {
  const OnlineMatch({
    required this.sessionId,
    required this.startedAt,
    required this.duration,
    required this.x01,
    required this.darts,
    required this.average,
    required this.first9,
    required this.legsWon,
    required this.legsLost,
    required this.checkout,
    required this.highestFinish,
    required this.count100,
    required this.count140,
    required this.count180,
    required this.legs,
    this.opponent,
    this.won,
  });

  final int sessionId;
  final DateTime startedAt;
  final Duration duration;

  /// Mit „X01 mitzählen“ (`x01_live`): Legs, First 9 und Checkouts bekannt.
  /// Sonst ist [average] der Rohschnitt aller Darts.
  final bool x01;
  final int darts;
  final double? average;
  final double? first9;
  final int legsWon;
  final int legsLost;

  /// Darts auf ein Finish (Rest mit einem Dart checkbar) und gewonnene Legs.
  final HitCount checkout;
  final int highestFinish;
  final int count100;
  final int count140;
  final int count180;

  /// Abgeschlossene Legs in Reihenfolge (leer ohne X01).
  final List<OnlineLeg> legs;

  /// Name des Gegners bei einem importierten Match (aus dem Autodarts-Konto),
  /// sonst `null`: Live-Sessions kennen ihn nicht.
  final String? opponent;

  /// Gewonnen (nur importierte, beendete Matches).
  final bool? won;

  /// Aufnahmen mit 100 oder mehr.
  int get tons => count100 + count140 + count180;
  bool get hasLegs => legsWon + legsLost > 0;
}

/// Online-Matches einer Kalenderwoche (ab Montag) oder eines Zeitraums.
class OnlineTotals {
  const OnlineTotals({
    this.matches = 0,
    this.darts = 0,
    this.points = 0,
    this.averageDarts = 0,
    this.first9Sum = 0,
    this.first9Legs = 0,
    this.legsWon = 0,
    this.legsLost = 0,
    this.checkout = HitCount.zero,
    this.highestFinish = 0,
    this.tons = 0,
    this.maxes = 0,
  });

  final int matches;
  final int darts;

  /// Punkte und Darts für den Average (X01-Average bzw. Rohschnitt).
  final double points;
  final int averageDarts;

  /// Summe der First-9-Werte und Zahl der Legs mit First 9.
  final double first9Sum;
  final int first9Legs;
  final int legsWon;
  final int legsLost;
  final HitCount checkout;
  final int highestFinish;
  final int tons;
  final int maxes;

  double? get average => averageDarts == 0 ? null : points / averageDarts * 3;
  double? get first9 => first9Legs == 0 ? null : first9Sum / first9Legs;
  double? get checkoutRate => checkout.rate;
  int get legs => legsWon + legsLost;

  OnlineTotals add(OnlineMatch m) => OnlineTotals(
        matches: matches + 1,
        darts: darts + m.darts,
        points: points + (m.average == null ? 0 : m.average! * m.darts / 3),
        averageDarts: averageDarts + (m.average == null ? 0 : m.darts),
        first9Sum: first9Sum + m.legs.fold(0.0, (a, l) => a + (l.first9 ?? 0)),
        first9Legs: first9Legs + m.legs.where((l) => l.first9 != null).length,
        legsWon: legsWon + m.legsWon,
        legsLost: legsLost + m.legsLost,
        checkout: checkout + m.checkout,
        highestFinish: m.highestFinish > highestFinish ? m.highestFinish : highestFinish,
        tons: tons + m.tons,
        maxes: maxes + m.count180,
      );
}

/// Kennzahlen im Verlauf der Online-Matches.
enum OnlineTrendMetric { average, first9, checkoutRate }

/// Online-Matches eines Zeitraums.
class OnlineReport {
  const OnlineReport({required this.matches, required this.totals, required this.weeks});

  /// Neueste zuerst.
  final List<OnlineMatch> matches;
  final OnlineTotals totals;

  /// Wochen mit mindestens einem Match, älteste zuerst.
  final List<({DateTime weekStart, OnlineTotals totals})> weeks;

  /// Ab so vielen Wochen mit Matches zeigt der Verlauf Wochen, sonst die
  /// einzelnen Matches.
  static const int minWeeks = 3;

  bool get isEmpty => matches.isEmpty;
  bool get byWeek => weeks.length >= minWeeks;

  /// Verlauf einer Kennzahl: je Woche (siehe [byWeek]) oder je Match,
  /// älteste zuerst. Punkte ohne Wert fehlen.
  List<TrendPoint> trend(OnlineTrendMetric metric) {
    double? of(OnlineTotals t) => switch (metric) {
          OnlineTrendMetric.average => t.average,
          OnlineTrendMetric.first9 => t.first9,
          OnlineTrendMetric.checkoutRate => t.checkout.attempts == 0 ? null : t.checkoutRate,
        };
    if (byWeek) {
      return [
        for (final w in weeks)
          if (of(w.totals) case final v?) TrendPoint(0, w.weekStart, v),
      ];
    }
    return [
      for (final m in matches.reversed)
        if (of(const OnlineTotals().add(m)) case final v?) TrendPoint(m.sessionId, m.startedAt, v),
    ];
  }
}

/// Kennzahlen im Vergleich Training gegen Match.
enum CompareMetric { average, first9, checkoutRate, doubleRate, scoring }

/// Eine Seite des Vergleichs: Wert und wie viel Daten dahinterstehen.
class CompareSide {
  const CompareSide(this.value, this.amount);
  static const CompareSide none = CompareSide(null, 0);

  final double? value;

  /// Darts, Legs oder Aufnahmen, je nach [CompareMetric] (siehe
  /// [OnlineComparison.minimum]).
  final int amount;
}

/// Eine Kennzahl online und im Training.
class MetricComparison {
  const MetricComparison(this.metric, this.online, this.training);

  final CompareMetric metric;
  final CompareSide online;
  final CompareSide training;

  int get minimum => OnlineComparison.minimum[metric]!;
  bool get onlineReady => online.value != null && online.amount >= minimum;
  bool get trainingReady => training.value != null && training.amount >= minimum;

  /// Beide Seiten haben genug Daten.
  bool get ready => onlineReady && trainingReady;

  /// Online minus Training; `null`, solange nicht [ready].
  double? get diff => ready ? online.value! - training.value! : null;
}

/// Ein Doppel online und im Training.
class DoubleComparison {
  const DoubleComparison(this.number, this.online, this.training);

  /// 1–20, 25 = Bull.
  final int number;
  final HitCount online;
  final HitCount training;

  bool get ready =>
      online.attempts >= OnlineComparison.minDoubleAttempts && training.attempts >= OnlineComparison.minDoubleAttempts;

  /// Wie viel die Quote online niedriger ist (Training minus online, 0–1);
  /// negativ, wenn es online besser läuft. `null`, solange nicht [ready].
  double? get drop => ready ? training.rate! - online.rate! : null;

  /// Online deutlich schlechter (siehe [OnlineComparison.notableDrop]).
  bool get notable => (drop ?? 0) >= OnlineComparison.notableDrop;
}

/// Training gegen Match im gewählten Zeitraum.
class OnlineComparison {
  const OnlineComparison({
    required this.average,
    required this.first9,
    required this.checkout,
    required this.doubles,
    required this.scoring,
    required this.perDouble,
    required this.onlineBands,
    required this.trainingBands,
  });

  /// Mindestmenge je Kennzahl und Seite, damit verglichen wird:
  /// Average 90 Darts (30 Aufnahmen), First 9 fünf Legs, Checkout-Quote
  /// 15 Darts aufs Finish, Doppelquote 20 Darts aufs Doppel,
  /// Punkteverteilung 30 volle Aufnahmen.
  static const Map<CompareMetric, int> minimum = {
    CompareMetric.average: 90,
    CompareMetric.first9: 5,
    CompareMetric.checkoutRate: 15,
    CompareMetric.doubleRate: 20,
    CompareMetric.scoring: 30,
  };

  /// Mindestdarts je Doppel und Seite für den Vergleich je Doppel.
  static const int minDoubleAttempts = 8;

  /// Ab so vielen Prozentpunkten weniger online gilt ein Doppel (oder die
  /// Doppelquote insgesamt) als deutlich schlechter.
  static const double notableDrop = 0.10;

  /// Ab so viel niedrigeren First 9 online gilt der Start als deutlich
  /// schlechter.
  static const double notableFirst9Drop = 5;

  final MetricComparison average;
  final MetricComparison first9;
  final MetricComparison checkout;
  final MetricComparison doubles;
  final MetricComparison scoring;

  /// Alle Doppel mit mindestens einem Dart auf einer der beiden Seiten.
  final Map<int, DoubleComparison> perDouble;

  /// Volle Aufnahmen je Punktebereich.
  final Map<ScoreBand, int> onlineBands;
  final Map<ScoreBand, int> trainingBands;

  List<MetricComparison> get metrics => [average, first9, checkout, doubles, scoring];

  /// Mindestens eine Kennzahl lässt sich vergleichen.
  bool get ready => metrics.any((m) => m.ready);

  /// Doppel mit genug Darts auf beiden Seiten, größter Einbruch online
  /// zuerst (bei Gleichstand mehr Online-Darts, dann die Zahl).
  List<DoubleComparison> get ranked => [
        for (final d in perDouble.values)
          if (d.ready) d,
      ]..sort((a, b) {
          final r = b.drop!.compareTo(a.drop!);
          if (r != 0) return r;
          final n = b.online.attempts.compareTo(a.online.attempts);
          return n != 0 ? n : a.number.compareTo(b.number);
        });

  /// Doppel, die online deutlich schlechter laufen, größter Einbruch zuerst.
  List<DoubleComparison> get notableDrops => [for (final d in ranked) if (d.notable) d];

  /// Doppelquote insgesamt online deutlich schlechter?
  bool get doublesNotable => (doubles.diff ?? 0) <= -notableDrop;

  /// First 9 online deutlich schlechter?
  bool get first9Notable => (first9.diff ?? 0) <= -notableFirst9Drop;

  static int bandTotal(Map<ScoreBand, int> bands) => bands.values.fold(0, (a, b) => a + b);
}
