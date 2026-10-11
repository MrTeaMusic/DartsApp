import '../../../../board/domain/segment.dart';

/// Berechnet Wurfvorschläge für Finishes.
///
/// Bevorzugt werden: so wenige Darts wie möglich, Aufbau über T20/T19,
/// beliebte Doppel (D20, D16, D8, D10 …). Das Ergebnis ist ein Vorschlag,
/// keine absolute Wahrheit; die Gewichte stehen in [_setupCost] und
/// [_finishCost] und lassen sich leicht anpassen.
class CheckoutCalculator {
  CheckoutCalculator._();

  /// Größtes Finish mit Double-Out in drei Darts.
  static const int maxCheckout = 170;

  /// Alle treffbaren Felder (ohne Miss), innere/äußere Single zusammengefasst.
  static final List<Segment> _all = [
    for (var n = 20; n >= 1; n--) ...[Segment.triple(n), Segment.double(n), Segment.single(n)],
    Segment.bull,
    Segment.outerBull,
  ];

  static final Map<(int, int, bool, bool), List<Segment>?> _cache = {};

  /// Bester Weg für [remaining] Punkte mit höchstens [darts] Darts.
  /// `null`, wenn kein Finish möglich ist.
  ///
  /// [masterOut] erlaubt zusätzlich Triples als letzten Dart (Master-Out)
  /// und hat Vorrang vor [doubleOut].
  static List<Segment>? suggest(int remaining, {int darts = 3, bool doubleOut = true, bool masterOut = false}) {
    if (remaining <= 0 || darts <= 0) return null;
    if ((doubleOut || masterOut) && remaining < 2) return null;
    final d = darts > 3 ? 3 : darts;
    return _cache.putIfAbsent(
      (remaining, d, doubleOut, masterOut),
      () => _search(remaining, d, doubleOut: doubleOut, masterOut: masterOut),
    );
  }

  /// Kann [remaining] mit [darts] Darts gecheckt werden?
  static bool isCheckout(int remaining, {int darts = 3, bool doubleOut = true, bool masterOut = false}) =>
      suggest(remaining, darts: darts, doubleOut: doubleOut, masterOut: masterOut) != null;

  /// Alle checkbaren Werte bis 170 (für Zufallsziele).
  static List<int> checkoutTargets({int min = 2, int max = maxCheckout, bool doubleOut = true}) => [
        for (var v = min; v <= max; v++)
          if (isCheckout(v, doubleOut: doubleOut)) v,
      ];

  static List<Segment>? _search(int remaining, int maxDarts, {required bool doubleOut, required bool masterOut}) {
    bool finisher(Segment s) => masterOut ? s.isDouble || s.isTriple : (doubleOut ? s.isDouble : true);
    final finishers = _all.where(finisher).toList();

    for (var n = 1; n <= maxDarts; n++) {
      List<Segment>? best;
      var bestCost = double.infinity;
      void consider(List<Segment> setups, Segment last) {
        final cost = setups.fold<double>(0, (c, s) => c + _setupCost(s)) + _finishCost(last, doubleOut: doubleOut, masterOut: masterOut);
        if (cost < bestCost) {
          bestCost = cost;
          best = [...setups, last];
        }
      }

      if (n == 1) {
        for (final f in finishers) {
          if (f.score == remaining) consider(const [], f);
        }
      } else if (n == 2) {
        for (final a in _all) {
          final rest = remaining - a.score;
          for (final f in finishers) {
            if (f.score == rest) consider([a], f);
          }
        }
      } else {
        for (var i = 0; i < _all.length; i++) {
          // Reihenfolge der Aufbau-Darts egal: nur i ≤ j betrachten.
          for (var j = i; j < _all.length; j++) {
            final a = _all[i];
            final b = _all[j];
            final rest = remaining - a.score - b.score;
            if (rest <= 0) continue;
            for (final f in finishers) {
              if (f.score == rest) consider(_ordered(a, b), f);
            }
          }
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  /// Höherer Aufbau-Dart zuerst.
  static List<Segment> _ordered(Segment a, Segment b) =>
      _setupCost(a) <= _setupCost(b) ? [a, b] : [b, a];

  static double _setupCost(Segment s) {
    if (s.bed == Bed.outerBull) return 6;
    if (s.bed == Bed.innerBull) return 7;
    final n = s.number;
    if (s.isTriple) {
      return switch (n) {
        20 => 0,
        19 => 1,
        18 => 2.5,
        17 => 3,
        16 => 3.5,
        15 => 4,
        _ => 5 + (20 - n) * 0.05,
      };
    }
    if (s.isDouble) return 5.5 + (20 - n) * 0.05;
    return switch (n) {
      20 => 1.5,
      19 => 2,
      _ => 2.5 + (20 - n) * 0.03,
    };
  }

  static double _finishCost(Segment s, {required bool doubleOut, bool masterOut = false}) {
    // Master-Out: Doubles wie beim Double-Out, Triples etwas teurer.
    if (masterOut && s.isTriple) return 1.5 + (20 - s.number) * 0.05;
    if (!doubleOut && !masterOut) return s.isTriple ? 1 : 0;
    if (s.bed == Bed.innerBull) return 2.5;
    return switch (s.number) {
      20 => 0,
      16 => 0.2,
      8 => 0.6,
      10 => 0.7,
      12 => 0.8,
      18 => 1.0,
      4 => 1.1,
      6 => 1.3,
      14 => 1.4,
      2 => 1.6,
      1 => 3,
      _ => 2,
    };
  }
}
