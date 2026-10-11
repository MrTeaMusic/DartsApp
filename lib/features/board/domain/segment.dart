/// Das getroffene Feld eines Darts. Reine Dart-Klasse ohne UI-Abhängigkeit.
library;

/// Welcher Bereich des Boards getroffen wurde.
enum Bed {
  /// Innere Single-Fläche (zwischen Bull und Triple-Ring).
  singleInner,

  /// Äußere Single-Fläche (zwischen Triple- und Double-Ring).
  singleOuter,
  double,
  triple,

  /// Single Bull (25 Punkte).
  outerBull,

  /// Bullseye (50 Punkte, zählt als Double).
  innerBull,

  /// Daneben oder außerhalb des Double-Rings.
  miss,
}

/// Ein Feld auf dem Board, z. B. T20, D16, 25, BULL oder MISS.
class Segment {
  const Segment._(this.number, this.bed);

  /// Single auf [number] (1–20). [inner] wählt die innere Single-Fläche.
  factory Segment.single(int number, {bool inner = false}) {
    _checkNumber(number);
    return Segment._(number, inner ? Bed.singleInner : Bed.singleOuter);
  }

  factory Segment.double(int number) {
    _checkNumber(number);
    return Segment._(number, Bed.double);
  }

  factory Segment.triple(int number) {
    _checkNumber(number);
    return Segment._(number, Bed.triple);
  }

  static const Segment outerBull = Segment._(25, Bed.outerBull);
  static const Segment bull = Segment._(25, Bed.innerBull);
  static const Segment miss = Segment._(0, Bed.miss);

  /// Baut ein Segment aus Zahl und Multiplikator (0 = Miss, 1–3).
  /// Für Bull ist [number] 25 und [multiplier] 1 oder 2.
  factory Segment.fromNumber(int number, int multiplier) {
    if (multiplier == 0 || number == 0) return miss;
    if (number == 25) {
      return switch (multiplier) {
        1 => outerBull,
        2 => bull,
        _ => throw ArgumentError('Bull hat kein Triple'),
      };
    }
    return switch (multiplier) {
      1 => Segment.single(number),
      2 => Segment.double(number),
      3 => Segment.triple(number),
      _ => throw ArgumentError('Ungültiger Multiplikator: $multiplier'),
    };
  }

  /// Liest Kurznamen wie "S20", "D16", "T19", "25", "BULL", "MISS".
  /// Gibt `null` zurück, wenn der Name nicht erkannt wird.
  static Segment? tryParse(String name) {
    final n = name.trim().toUpperCase();
    if (n.isEmpty) return null;
    if (n == 'MISS' || n == 'M' || n == 'OUT') return miss;
    if (n == 'BULL' || n == 'DB' || n == 'D25' || n == '50') return bull;
    if (n == '25' || n == 'SB' || n == 'S25') return outerBull;
    final prefix = n[0];
    final value = int.tryParse(n.substring(1));
    if (value == null || value < 1 || value > 20) return null;
    return switch (prefix) {
      'S' => Segment.single(value),
      'D' => Segment.double(value),
      'T' => Segment.triple(value),
      _ => null,
    };
  }

  static void _checkNumber(int number) {
    if (number < 1 || number > 20) {
      throw ArgumentError.value(number, 'number', 'muss zwischen 1 und 20 liegen');
    }
  }

  /// 1–20, 25 für Bull, 0 für Miss.
  final int number;
  final Bed bed;

  int get multiplier => switch (bed) {
        Bed.miss => 0,
        Bed.singleInner || Bed.singleOuter || Bed.outerBull => 1,
        Bed.double || Bed.innerBull => 2,
        Bed.triple => 3,
      };

  int get score => number * multiplier;

  bool get isMiss => bed == Bed.miss;
  bool get isSingle => multiplier == 1;

  /// Double-Out-tauglich: Doubles und Bullseye.
  bool get isDouble => multiplier == 2;
  bool get isTriple => bed == Bed.triple;
  bool get isBull => number == 25;

  /// Kurzname, z. B. "T20", "S5", "25", "BULL", "MISS".
  String get name => switch (bed) {
        Bed.miss => 'MISS',
        Bed.outerBull => '25',
        Bed.innerBull => 'BULL',
        Bed.double => 'D$number',
        Bed.triple => 'T$number',
        Bed.singleInner || Bed.singleOuter => 'S$number',
      };

  /// Vergleicht ohne Unterscheidung innere/äußere Single-Fläche.
  bool sameField(Segment other) =>
      number == other.number && multiplier == other.multiplier;

  @override
  bool operator ==(Object other) =>
      other is Segment && other.number == number && other.bed == bed;

  @override
  int get hashCode => Object.hash(number, bed);

  @override
  String toString() => name;
}
