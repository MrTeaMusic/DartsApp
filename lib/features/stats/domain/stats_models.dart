/// Datenklassen der Statistik. Reine Werte, berechnet im `StatsCalculator`.
library;

/// Zeitraum der Auswertung: die festen Zeiträume bis heute (7, 30, 90 Tage,
/// Alles) oder ein eigener Zeitraum von [from] bis [to] (ganze Tage, beide
/// eingeschlossen, mindestens ein Tag).
class StatsPeriod {
  const StatsPeriod._(this.name, this._days) : from = null, to = null;

  StatsPeriod._custom(DateTime a, DateTime b)
      : name = 'custom',
        from = DateTime(a.year, a.month, a.day),
        to = DateTime(b.year, b.month, b.day),
        _days = null;

  /// Eigener Zeitraum; die Reihenfolge von [a] und [b] ist egal, die Uhrzeit
  /// wird ignoriert. Ein Tag ist der kürzeste Zeitraum (von = bis).
  factory StatsPeriod.custom(DateTime a, DateTime b) => a.isAfter(b) ? StatsPeriod._custom(b, a) : StatsPeriod._custom(a, b);

  static const StatsPeriod week = StatsPeriod._('week', 7);
  static const StatsPeriod month = StatsPeriod._('month', 30);
  static const StatsPeriod quarter = StatsPeriod._('quarter', 90);
  static const StatsPeriod all = StatsPeriod._('all', null);

  /// Die festen Zeiträume in der Reihenfolge der Auswahl.
  static const List<StatsPeriod> values = [week, month, quarter, all];

  /// `week`, `month`, `quarter`, `all` oder `custom`.
  final String name;
  final int? _days;

  /// Erster und letzter Tag eines eigenen Zeitraums (sonst `null`).
  final DateTime? from;
  final DateTime? to;

  bool get isCustom => from != null;

  /// Länge in Tagen; `null` bei „Alles“.
  int? get days {
    if (from case final f?) {
      // Über Kalendertage gezählt, damit die Zeitumstellung nicht stört.
      return DateTime.utc(to!.year, to!.month, to!.day).difference(DateTime.utc(f.year, f.month, f.day)).inDays + 1;
    }
    return _days;
  }

  /// Ein eigener Zeitraum mit denselben Tagen wie [preset] bis [today].
  static StatsPeriod resolved(StatsPeriod preset, DateTime today) {
    if (preset.isCustom || preset.days == null) return preset;
    final t = DateTime(today.year, today.month, today.day);
    return StatsPeriod.custom(DateTime(t.year, t.month, t.day - preset.days! + 1), t);
  }

  /// Der gleich lange Zeitraum direkt vor diesem; `null` bei „Alles“.
  StatsPeriod? before(DateTime today) {
    final r = resolved(this, today);
    if (!r.isCustom) return null;
    final f = r.from!;
    return StatsPeriod.custom(DateTime(f.year, f.month, f.day - r.days!), DateTime(f.year, f.month, f.day - 1));
  }

  @override
  bool operator ==(Object other) => other is StatsPeriod && other.name == name && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(name, from, to);

  @override
  String toString() => isCustom ? 'StatsPeriod($from–$to)' : 'StatsPeriod.$name';
}

/// Ein Punkt im Verlauf: Wert einer Session (oder eines Tages, dann ist
/// [sessionId] 0).
class TrendPoint {
  const TrendPoint(this.sessionId, this.time, this.value);
  final int sessionId;
  final DateTime time;
  final double value;
}

/// Versuche und Treffer, z. B. Darts aufs D16 und Treffer im D16.
class HitCount {
  const HitCount(this.attempts, this.hits);
  static const HitCount zero = HitCount(0, 0);

  final int attempts;
  final int hits;

  double? get rate => attempts == 0 ? null : hits / attempts;
  HitCount operator +(HitCount o) => HitCount(attempts + o.attempts, hits + o.hits);
}

/// Rekord und Überblick eines Spiels.
class GameSummary {
  const GameSummary({
    required this.gameId,
    required this.sessions,
    required this.darts,
    this.best,
    this.bestAt,
    this.last,
    this.accuracy = HitCount.zero,
  });
  final String gameId;
  final int sessions;
  final int darts;
  final double? best;

  /// Datum des Bestwerts.
  final DateTime? bestAt;
  final double? last;

  /// Darts aufs vom Spiel vorgegebene Ziel und Treffer darauf.
  final HitCount accuracy;
}

/// Trainingstage am Stück.
class Streak {
  const Streak({required this.current, required this.longest, required this.trainedToday, this.longestEnd});
  final int current;
  final int longest;
  final bool trainedToday;

  /// Letzter Tag der längsten Serie.
  final DateTime? longestEnd;
}

/// Punktebereiche einer vollen Aufnahme (3 Darts).
enum ScoreBand {
  under40(0, 39),
  from40(40, 59),
  from60(60, 99),
  ton(100, 139),
  ton40(140, 179),
  maximum(180, 180);

  const ScoreBand(this.min, this.max);
  final int min;
  final int max;

  static ScoreBand of(int score) => values.lastWhere((b) => score >= b.min, orElse: () => under40);
}

/// Aufnahmen aus den Spielen, in denen auf Punkte geworfen wird.
class ScoringStats {
  const ScoringStats({
    required this.visits,
    required this.mean,
    required this.stdDev,
    required this.highest,
    required this.bands,
  });

  /// Volle Aufnahmen mit drei gezählten Darts.
  final int visits;

  /// Durchschnitt pro Aufnahme.
  final double mean;

  /// Standardabweichung der Aufnahmen: je kleiner, desto konstanter.
  final double stdDev;
  final int highest;
  final Map<ScoreBand, int> bands;

  int count(ScoreBand b) => bands[b] ?? 0;

  /// Aufnahmen ab [min] Punkten.
  int atLeast(int min) => [for (final b in ScoreBand.values) if (b.min >= min) count(b)].fold(0, (a, b) => a + b);
  int get tons => atLeast(100);
  int get ton40s => atLeast(140);
  int get maxes => count(ScoreBand.maximum);
  int get under40 => count(ScoreBand.under40);

  double rate(int n) => visits == 0 ? 0 : n / visits;
}

/// Aktivität in einer Gruppe (Wochentag, Tageszeit, Woche).
class ActivityBucket {
  const ActivityBucket({this.sessions = 0, this.darts = 0, this.scoringPoints = 0, this.scoringDarts = 0});
  final int sessions;
  final int darts;
  final double scoringPoints;
  final int scoringDarts;

  /// 3-Dart-Average der Scoring-Darts in dieser Gruppe.
  double? get average => scoringDarts == 0 ? null : scoringPoints / scoringDarts * 3;

  ActivityBucket add({int sessions = 0, int darts = 0, double points = 0, int scoringDarts = 0}) => ActivityBucket(
        sessions: this.sessions + sessions,
        darts: this.darts + darts,
        scoringPoints: scoringPoints + points,
        scoringDarts: this.scoringDarts + scoringDarts,
      );
}

/// Tageszeiten für das Trainingsmuster.
enum DayPart {
  morning(5, 12),
  afternoon(12, 17),
  evening(17, 22),
  night(22, 5);

  const DayPart(this.fromHour, this.toHour);

  /// Beginn (einschließlich) und Ende (ausschließlich) in vollen Stunden.
  final int fromHour;
  final int toHour;

  static DayPart of(DateTime t) => values.firstWhere(
        (p) => p.fromHour < p.toHour ? t.hour >= p.fromHour && t.hour < p.toHour : t.hour >= p.fromHour || t.hour < p.toHour,
      );
}

/// Darts und Sessions einer Kalenderwoche (ab Montag).
class WeekVolume {
  const WeekVolume(this.weekStart, this.bucket);
  final DateTime weekStart;
  final ActivityBucket bucket;
}

/// Bereiche der Checkout-Ziele.
enum CheckoutRange {
  low(2, 40),
  mid(41, 60),
  high(61, 100),
  big(101, 130),
  huge(131, 170);

  const CheckoutRange(this.min, this.max);
  final int min;
  final int max;

  static CheckoutRange? of(int target) {
    for (final r in values) {
      if (target >= r.min && target <= r.max) return r;
    }
    return null;
  }
}

/// Arten persönlicher Rekorde.
enum RecordKind {
  /// Bester 3-Dart-Average einer Session (mindestens 9 Scoring-Darts).
  bestAverage,

  /// Beste First-9 einer Session (z. B. X01).
  bestFirst9,

  /// Höchste Aufnahme.
  highestVisit,

  /// Höchstes Finish.
  highestCheckout,

  /// Meiste 180er in einer Session.
  most180s,

  /// Meiste Darts an einem Tag.
  mostDartsDay,

  /// Längste Serie in Tagen.
  longestStreak,
}

/// Ein persönlicher Rekord mit Datum.
class PersonalRecord {
  const PersonalRecord(this.kind, this.value, {this.date, this.gameId});
  final RecordKind kind;
  final double value;
  final DateTime? date;
  final String? gameId;
}
