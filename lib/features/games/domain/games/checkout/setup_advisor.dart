import '../../../../board/domain/segment.dart';
import 'checkout_rules.dart';

/// Vorschlag zum Stellen: welche Darts werfen, damit für die nächste
/// Aufnahme ein guter Rest [leave] stehen bleibt.
class SetupPlan {
  const SetupPlan(this.darts, this.leave);

  final List<Segment> darts;

  /// Rest nach diesen Darts.
  final int leave;

  @override
  bool operator ==(Object other) =>
      other is SetupPlan && other.leave == leave && other.darts.length == darts.length && _same(other.darts);

  bool _same(List<Segment> o) {
    for (var i = 0; i < darts.length; i++) {
      if (o[i] != darts[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(leave, Object.hashAll(darts));

  @override
  String toString() => 'SetupPlan(${darts.map((s) => s.name).join(' ')} → $leave)';
}

/// Berechnet, wie man sich stellt, wenn mit den restlichen Darts kein Finish
/// mehr geht.
///
/// Bewertet wird nur der Rest nach den Darts dieser Aufnahme: am besten ein
/// Lieblings-Double (32, 40, 16 …), dann jedes andere Ein-Dart-Finish, dann
/// Zwei- und Drei-Dart-Finishes. Reste ohne Finish (z. B. 169, 159) oder über
/// 170 sind schlecht. Dazu kommt, wie schwer die Stell-Darts sind: große
/// Single-Felder kosten fast nichts, Triples mehr, das Bull am meisten.
/// Wie beim [CheckoutRules.suggest] ist das ein Vorschlag, keine Wahrheit;
/// die Gewichte stehen in [_leaveCost] und [_dartCost].
abstract final class SetupAdvisor {
  static final List<Segment> _segments = [
    for (var n = 20; n >= 1; n--) Segment.single(n),
    for (var n = 20; n >= 1; n--) Segment.triple(n),
    // Doubles zum Stellen sind selten sinnvoll und kosten Rechenzeit.
    Segment.outerBull,
    Segment.bull,
  ];

  static final Map<(int, int, OutMode), SetupPlan?> _cache = {};

  /// Stell-Vorschlag für [remaining] mit [darts] Darts. `null`, wenn ein
  /// Finish möglich ist, kein sinnvoller Rest erreichbar ist oder es nur ums
  /// Punkten geht: Rest über 170, und selbst mit maximalen Punkten bleibt
  /// höchstens ein Drei-Dart-Finish.
  static SetupPlan? suggest(int remaining, {required int darts, required OutMode out}) {
    if (darts <= 0 || remaining <= 1) return null;
    final d = darts > 3 ? 3 : darts;
    if (remaining - 60 * d > 170) return null;
    if (CheckoutRules.isCheckout(remaining, darts: d, out: out)) return null;
    return _cache.putIfAbsent((remaining, d, out), () {
      final plan = _search(remaining, d, out);
      if (plan == null) return null;
      if (remaining > 170 && !CheckoutRules.isCheckout(plan.leave, darts: 2, out: out)) return null;
      return plan;
    });
  }

  static final Map<OutMode, List<double>> _leaveCostTable = {};

  static SetupPlan? _search(int remaining, int darts, OutMode out) {
    // Reste reichen höchstens bis 170 + 3 × 60 (siehe [suggest]).
    final leaveCosts = _leaveCostTable[out] ??= [for (var l = 0; l <= 350; l++) l < 1 ? 0.0 : _leaveCost(l, out)];
    SetupPlan? best;
    var bestCost = double.infinity;
    void consider(List<Segment> plan) {
      var sum = 0;
      var cost = 0.0;
      for (final s in plan) {
        sum += s.score;
        cost += _dartCost(s);
      }
      final leave = remaining - sum;
      if (leave < (out == OutMode.straight ? 1 : 2)) return;
      cost += leaveCosts[leave];
      if (cost < bestCost) {
        bestCost = cost;
        best = SetupPlan(plan, leave);
      }
    }

    final n = _segments.length;
    // Reihenfolge egal: nur i ≤ j ≤ k betrachten.
    for (var i = 0; i < n; i++) {
      if (darts == 1) {
        consider([_segments[i]]);
        continue;
      }
      for (var j = i; j < n; j++) {
        if (darts == 2) {
          consider(_ordered([_segments[i], _segments[j]]));
          continue;
        }
        for (var k = j; k < n; k++) {
          consider(_ordered([_segments[i], _segments[j], _segments[k]]));
        }
      }
    }
    return best;
  }

  /// Punkte zuerst: Triples vor Singles, damit der Plan nach jedem Dart neu
  /// berechnet werden kann und das Feinstellen am Ende steht.
  static List<Segment> _ordered(List<Segment> plan) => [...plan]..sort((a, b) => b.score.compareTo(a.score));

  /// Wie gut ist [leave] für die nächste Aufnahme? Kleiner ist besser.
  static double _leaveCost(int leave, OutMode out) {
    if (out == OutMode.double || out == OutMode.master) {
      final favourite = switch (leave) {
        32 => 0.0,
        40 => 0.15,
        16 => 0.3,
        36 => 0.45,
        24 => 0.5,
        20 => 0.55,
        8 => 0.7,
        _ => null,
      };
      if (favourite != null) return favourite;
    }
    if (CheckoutRules.isCheckout(leave, darts: 1, out: out)) return leave == 50 ? 2.0 : 1.0;
    final two = CheckoutRules.suggest(leave, darts: 2, out: out);
    if (two != null) {
      // Single + Double ist leicht, ein Triple oder das Bull im Weg schwerer.
      var cost = 3.0;
      if (two.any((s) => s.isTriple)) cost += 1.0;
      if (two.any((s) => s.bed == Bed.innerBull || s.bed == Bed.outerBull)) cost += 1.5;
      return cost + leave * 0.002;
    }
    if (CheckoutRules.isCheckout(leave, darts: 3, out: out)) return 7.0 + leave * 0.03;
    return 12.0 + (leave > 170 ? (leave - 170) * 0.03 : 0);
  }

  static double _dartCost(Segment s) {
    if (s.bed == Bed.outerBull) return 1.3;
    if (s.bed == Bed.innerBull) return 2.2;
    if (s.isTriple) {
      return switch (s.number) {
        20 => 1.0,
        19 => 1.05,
        18 => 1.15,
        _ => 1.3 + (20 - s.number) * 0.02,
      };
    }
    return 0.1;
  }
}
