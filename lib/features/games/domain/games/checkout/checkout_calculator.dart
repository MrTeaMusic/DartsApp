import '../../../../board/domain/segment.dart';
import 'checkout_table.dart';

/// Berechnet Wurfvorschläge für Finishes.
///
/// Bei Double-Out kommt der Vorschlag aus der üblichen Checkout-Tabelle
/// ([CheckoutTable]). Ohne Tabelleneintrag (Master-Out, Straight-Out, Wege
/// mit genau n Darts in [routes]) sucht eine Kostenfunktion den Weg.
/// Bevorzugt werden dort: so wenige Darts wie möglich, Aufbau über T20/T19,
/// beliebte Doppel (D20, D16, D8, D10 …), kleine ungerade Doppel nur, wenn
/// es nicht anders geht. Das Ergebnis ist ein Vorschlag, keine absolute
/// Wahrheit; die Gewichte stehen in [_setupCost] und [_finishCost].
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
      () =>
          (doubleOut && !masterOut ? CheckoutTable.route(remaining, darts: d) : null) ??
          _search(remaining, d, doubleOut: doubleOut, masterOut: masterOut),
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

  /// Alle Wege mit genau [darts] Darts für [remaining], bester zuerst: bei
  /// Double-Out der Weg aus der [CheckoutTable] (wenn er genau [darts] Darts
  /// hat), danach die übrigen nach den Gewichten der Kostensuche. Wege, die
  /// sich nur in der Reihenfolge der Aufbau-Darts unterscheiden, stehen nur
  /// einmal da. Höchstens [limit] Einträge.
  static List<List<Segment>> routes(int remaining,
      {required int darts, bool doubleOut = true, bool masterOut = false, int limit = 10}) {
    if (remaining <= 0 || darts <= 0 || darts > 3) return const [];
    bool finisher(Segment s) => masterOut ? s.isDouble || s.isTriple : (doubleOut ? s.isDouble : true);
    final finishers = _all.where(finisher).toList();
    final found = <(double, List<Segment>)>[];
    void add(List<Segment> setups, Segment last) {
      final cost = setups.fold<double>(0, (c, s) => c + _setupCost(s)) + _finishCost(last, doubleOut: doubleOut, masterOut: masterOut);
      found.add((cost, [...setups, last]));
    }

    if (darts == 1) {
      for (final f in finishers) {
        if (f.score == remaining) add(const [], f);
      }
    } else if (darts == 2) {
      for (final a in _all) {
        for (final f in finishers) {
          if (a.score + f.score == remaining) add([a], f);
        }
      }
    } else {
      for (var i = 0; i < _all.length; i++) {
        for (var j = i; j < _all.length; j++) {
          final rest = remaining - _all[i].score - _all[j].score;
          if (rest <= 0) continue;
          for (final f in finishers) {
            if (f.score == rest) add(_ordered(_all[i], _all[j]), f);
          }
        }
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    final table = doubleOut && !masterOut ? CheckoutTable.route(remaining, darts: darts) : null;
    if (table == null || table.length != darts) return [for (final f in found.take(limit)) f.$2];
    return [
      table,
      for (final f in found)
        if (!_sameRoute(f.$2, table)) f.$2,
    ].take(limit).toList();
  }

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

  /// Gleicher Weg, Aufbau-Darts in beliebiger Reihenfolge.
  static bool _sameRoute(List<Segment> a, List<Segment> b) {
    if (a.length != b.length || a.isEmpty || !a.last.sameField(b.last)) return false;
    final rest = [...b.sublist(0, b.length - 1)];
    for (final s in a.sublist(0, a.length - 1)) {
      final i = rest.indexWhere(s.sameField);
      if (i < 0) return false;
      rest.removeAt(i);
    }
    return true;
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
    // Kleine ungerade Doppel (und D2) lassen nach einem Fehlwurf kaum einen
    // zweiten Versuch; sie sind so teuer, dass ein Weg mit schwererem
    // Aufbau-Dart auf ein gängiges Doppel meist gewinnt.
    return switch (s.number) {
      20 => 0,
      16 => 0.2,
      8 => 0.6,
      10 => 0.7,
      12 => 0.8,
      18 => 1.0,
      14 => 1.4,
      4 => 1.8,
      6 => 2.0,
      2 => 6,
      1 || 3 || 5 || 7 || 9 => 7,
      _ => 2.5,
    };
  }
}
