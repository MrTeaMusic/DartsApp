import '../../games/domain/games/checkout/checkout_rules.dart';

/// Spielformat eines X01-Matches: Startwert, Ein-/Ausstieg und wie viele
/// Legs bzw. Sätze zum Sieg nötig sind.
class MatchFormat {
  const MatchFormat({
    this.startScore = 501,
    this.outMode = OutMode.double,
    this.doubleIn = false,
    this.legsToWin = 3,
    this.setsToWin = 0,
  }) : assert(legsToWin >= 1),
       assert(setsToWin >= 0);

  /// Wählbare Startwerte.
  static const List<int> startScores = [101, 301, 501, 701];

  final int startScore;
  final OutMode outMode;
  final bool doubleIn;

  /// Gewonnene Legs für den Sieg (im Satz, wenn mit Sätzen gespielt wird).
  final int legsToWin;

  /// Gewonnene Sätze für den Sieg, 0 = ohne Sätze.
  final int setsToWin;

  bool get usesSets => setsToWin > 0;

  /// „Best of“: höchstmögliche Zahl Legs (bzw. Sätze bei Satzmodus).
  int get bestOf => usesSets ? setsToWin * 2 - 1 : legsToWin * 2 - 1;

  /// Legs pro Satz als „Best of“.
  int get legsBestOf => legsToWin * 2 - 1;

  /// First-to aus „Best of“ (gerade Werte werden aufgerundet).
  static int firstTo(int bestOf) => (bestOf + 2) ~/ 2;

  MatchFormat copyWith({int? startScore, OutMode? outMode, bool? doubleIn, int? legsToWin, int? setsToWin}) =>
      MatchFormat(
        startScore: startScore ?? this.startScore,
        outMode: outMode ?? this.outMode,
        doubleIn: doubleIn ?? this.doubleIn,
        legsToWin: legsToWin ?? this.legsToWin,
        setsToWin: setsToWin ?? this.setsToWin,
      );

  Map<String, Object?> toJson() => {
    'startScore': startScore,
    'outMode': outMode.name,
    'doubleIn': doubleIn,
    'legsToWin': legsToWin,
    'setsToWin': setsToWin,
  };

  factory MatchFormat.fromJson(Object? json) {
    if (json is! Map) return const MatchFormat();
    int intOf(String k, int fallback) => switch (json[k]) {
      final num v => v.toInt(),
      _ => fallback,
    };
    final out = OutMode.values.where((m) => m.name == json['outMode']).firstOrNull ?? OutMode.double;
    return MatchFormat(
      startScore: intOf('startScore', 501).clamp(2, 1001),
      outMode: out,
      doubleIn: json['doubleIn'] == true,
      legsToWin: intOf('legsToWin', 3).clamp(1, 50),
      setsToWin: intOf('setsToWin', 0).clamp(0, 20),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MatchFormat &&
      other.startScore == startScore &&
      other.outMode == outMode &&
      other.doubleIn == doubleIn &&
      other.legsToWin == legsToWin &&
      other.setsToWin == setsToWin;

  @override
  int get hashCode => Object.hash(startScore, outMode, doubleIn, legsToWin, setsToWin);
}
