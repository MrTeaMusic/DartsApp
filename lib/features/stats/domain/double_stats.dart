/// Auswertung der Darts aufs Doppel: Streubild, Daneben-Richtung, Verlauf
/// und Checkout gegen Training. Reine Berechnung ohne Datenbank.
library;

import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import 'stats_models.dart';

/// Wohin ein Dart aufs Doppel danebenging.
enum DoubleMiss {
  /// Außerhalb der Scheibe.
  outside,

  /// Innen: Single oder Triple derselben Zahl. Beim Bull das Single-Bull.
  inside,

  /// Seitlich: eine andere Zahl, meist die Nachbarzahl.
  side,
}

/// Wie ein Dart aufs Doppel [target] (1–20, 25 = Bull) gelandet ist;
/// `null` bei einem Treffer. Braucht nur das Feld, keine Koordinaten.
DoubleMiss? classifyDoubleMiss(int target, Segment landed) {
  if (target == 25) {
    if (landed.bed == Bed.innerBull) return null;
    if (landed.isMiss) return DoubleMiss.outside;
    if (landed.bed == Bed.outerBull) return DoubleMiss.inside;
    return DoubleMiss.side;
  }
  if (landed.isDouble && landed.number == target) return null;
  if (landed.isMiss) return DoubleMiss.outside;
  if (landed.number == target || landed.isBull) return DoubleMiss.inside;
  return DoubleMiss.side;
}

/// Woher ein Dart aufs Doppel stammt, für den Vergleich Checkout gegen Training.
enum DoubleSource {
  /// Checkout-Training und 121: Dart aufs vorgeschlagene Doppel.
  checkout,

  /// Trainingsspiele mit Doppel als Ziel (Bob's 27, Doppel-Spiele …).
  training,

  /// Zählt im Vergleich nicht einzeln (X01: dort kommen die Checkout-Darts
  /// aus den Kennzahlen der Session).
  none,
}

/// Ein Dart, bei dem genau ein Doppel das Ziel war.
class DoubleAttempt {
  const DoubleAttempt({
    required this.target,
    required this.landed,
    required this.time,
    this.position,
    this.source = DoubleSource.training,
  });

  /// Zahl des Doppels (1–20, 25 = Bull).
  final int target;
  final Segment landed;
  final DateTime time;

  /// Nur bei Quellen mit Koordinaten (Simulator, Autodarts).
  final BoardPoint? position;
  final DoubleSource source;

  DoubleMiss? get miss => classifyDoubleMiss(target, landed);
  bool get hit => miss == null;
}

/// Alle Darts auf ein Doppel im Zeitraum.
class DoubleDetail {
  DoubleDetail._(this.number, this.count, this.misses, this.scatter);

  final int number;
  final HitCount count;

  /// Fehlwürfe je Richtung.
  final Map<DoubleMiss, int> misses;

  /// Darts mit Position, ältester zuerst.
  final List<DoubleAttempt> scatter;

  int missesOf(DoubleMiss m) => misses[m] ?? 0;

  /// Anteil einer Richtung an allen Darts aufs Doppel (0–1).
  double share(DoubleMiss m) => count.attempts == 0 ? 0 : missesOf(m) / count.attempts;

  /// Häufigste Richtung der Fehlwürfe; `null` ohne Fehlwurf. Bei Gleichstand
  /// gewinnt die Reihenfolge außen, innen, seitlich.
  DoubleMiss? get mainMiss {
    DoubleMiss? best;
    for (final m in DoubleMiss.values) {
      if (missesOf(m) > 0 && (best == null || missesOf(m) > missesOf(best))) best = m;
    }
    return best;
  }
}

/// Richtung der Veränderung.
enum TrendDirection { up, down, flat }

/// Quote eines Doppels in den letzten [DoubleStats.trendDays] Tagen und in
/// den gleich vielen Tagen davor.
class DoubleTrend {
  const DoubleTrend(this.recent, this.before);
  final HitCount recent;
  final HitCount before;

  /// Nur wenn beide Zeiträume genug Versuche haben, sonst `null`.
  TrendDirection? get direction {
    if (recent.attempts < DoubleStats.trendMinAttempts || before.attempts < DoubleStats.trendMinAttempts) return null;
    final diff = recent.rate! - before.rate!;
    if (diff.abs() < DoubleStats.flatThreshold) return TrendDirection.flat;
    return diff > 0 ? TrendDirection.up : TrendDirection.down;
  }
}

/// Doppel-Auswertung eines Zeitraums.
class DoubleStats {
  DoubleStats._({required this.perDouble, required this.trends, required this.checkout, required this.training});

  /// Länge der beiden Zeiträume im Verlauf.
  static const int trendDays = 30;

  /// Mindestversuche je Zeitraum, damit ein Verlauf gezeigt wird.
  static const int trendMinAttempts = 5;

  /// Unterschiede unter zwei Prozentpunkten gelten als gleich.
  static const double flatThreshold = 0.02;

  /// Doppel mit mindestens einem Dart im Zeitraum.
  final Map<int, DoubleDetail> perDouble;

  /// Verlauf je Doppel (unabhängig vom gewählten Zeitraum).
  final Map<int, DoubleTrend> trends;

  /// Checkout-Darts aufs Doppel und Treffer.
  final HitCount checkout;

  /// Darts aufs Doppel in Trainingsspielen und Treffer.
  final HitCount training;

  /// Fasst die Darts zusammen.
  ///
  /// * [attempts]: Darts im gewählten Zeitraum.
  /// * [trendAttempts]: Darts der letzten 2 × [trendDays] Tage vor [now].
  /// * [extraCheckout]: Checkout-Darts, die nicht als einzelne Darts
  ///   vorliegen (X01-Kennzahlen).
  factory DoubleStats.build({
    required Iterable<DoubleAttempt> attempts,
    Iterable<DoubleAttempt> trendAttempts = const [],
    required DateTime now,
    HitCount extraCheckout = HitCount.zero,
  }) {
    final counts = <int, HitCount>{};
    final misses = <int, Map<DoubleMiss, int>>{};
    final scatter = <int, List<DoubleAttempt>>{};
    var checkout = extraCheckout;
    var training = HitCount.zero;
    for (final a in attempts) {
      final h = HitCount(1, a.hit ? 1 : 0);
      counts[a.target] = (counts[a.target] ?? HitCount.zero) + h;
      if (a.miss case final m?) {
        final map = misses.putIfAbsent(a.target, () => {});
        map[m] = (map[m] ?? 0) + 1;
      }
      if (a.position != null) scatter.putIfAbsent(a.target, () => []).add(a);
      switch (a.source) {
        case DoubleSource.checkout:
          checkout += h;
        case DoubleSource.training:
          training += h;
        case DoubleSource.none:
          break;
      }
    }

    final recentStart = DateTime(now.year, now.month, now.day - trendDays + 1);
    final beforeStart = DateTime(recentStart.year, recentStart.month, recentStart.day - trendDays);
    final recent = <int, HitCount>{};
    final before = <int, HitCount>{};
    for (final a in trendAttempts) {
      if (a.time.isAfter(now) || a.time.isBefore(beforeStart)) continue;
      final map = a.time.isBefore(recentStart) ? before : recent;
      map[a.target] = (map[a.target] ?? HitCount.zero) + HitCount(1, a.hit ? 1 : 0);
    }

    return DoubleStats._(
      perDouble: {
        for (final e in counts.entries)
          e.key: DoubleDetail._(
            e.key,
            e.value,
            misses[e.key] ?? const {},
            [...?scatter[e.key]]..sort((a, b) => a.time.compareTo(b.time)),
          ),
      },
      trends: {
        for (final n in {...recent.keys, ...before.keys})
          n: DoubleTrend(recent[n] ?? HitCount.zero, before[n] ?? HitCount.zero),
      },
      checkout: HitCount(checkout.attempts, checkout.hits.clamp(0, checkout.attempts)),
      training: training,
    );
  }

  bool get isEmpty => perDouble.isEmpty;

  DoubleDetail? operator [](int number) => perDouble[number];

  /// Das am häufigsten geworfene Doppel. Bei Gleichstand (z. B. nur
  /// Bob's 27) ein Zahlen-Doppel vor dem Bull, dann das höhere.
  int? get mostThrown {
    int rank(DoubleDetail d) => d.count.attempts * 100 + (d.number == 25 ? 0 : d.number);
    DoubleDetail? best;
    for (final d in perDouble.values) {
      if (best == null || rank(d) > rank(best)) best = d;
    }
    return best?.number;
  }

  /// Doppel ab [minAttempts] Versuchen, beste Quote zuerst (bei Gleichstand
  /// mehr Versuche zuerst).
  List<DoubleDetail> ranked(int minAttempts) => [
        for (final d in perDouble.values)
          if (d.count.attempts >= minAttempts) d,
      ]..sort((a, b) {
          final r = b.count.rate!.compareTo(a.count.rate!);
          return r != 0 ? r : b.count.attempts.compareTo(a.count.attempts);
        });

  /// Bestes Doppel für den Tipp, sobald mindestens zwei Doppel genug
  /// Versuche haben; sonst `null`.
  DoubleDetail? bestFor(int minAttempts) {
    final r = ranked(minAttempts);
    return r.length >= 2 ? r.first : null;
  }
}
