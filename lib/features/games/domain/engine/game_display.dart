import '../../../board/domain/segment.dart';

/// Was im Spiel gerade passiert ist. Die UI übersetzt den Typ in Text.
enum GameEventType {
  /// Überworfen (Checkout-Training).
  bust,

  /// Finish geschafft.
  checkout,

  /// Aufgabe nicht geschafft (Darts aufgebraucht).
  failed,

  /// Ziel getroffen.
  hit,

  /// Zahl bzw. Aufgabe erledigt, weiter zur nächsten.
  advanced,

  /// Aufnahme hat die Vorgabe erreicht (Score-Aufgabe).
  visitSuccess,

  /// Aufnahme hat die Vorgabe verfehlt.
  visitMissed,

  /// Neuer Bestwert in diesem Spiel.
  best,

  /// Spiel ist vorbei.
  finished,
}

class GameEvent {
  const GameEvent(this.type, {this.value});
  final GameEventType type;

  /// Optionaler Wert, z. B. die erzielten Punkte.
  final Object? value;

  @override
  bool operator ==(Object other) => other is GameEvent && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);

  @override
  String toString() => 'GameEvent($type${value == null ? '' : ', $value'})';
}

/// Kennzahl mit stabilem Schlüssel. Die UI übersetzt den Schlüssel.
class GameStat {
  const GameStat(this.key, this.value);
  final String key;
  final String value;

  @override
  bool operator ==(Object other) => other is GameStat && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(key, value);

  @override
  String toString() => '$key=$value';
}

/// Daten für die Spielansicht.
class GameDisplay {
  const GameDisplay({
    required this.headline,
    required this.headlineKey,
    this.stats = const [],
    this.suggestion,
    this.progress,
    this.progressLabel,
  });

  /// Große Anzeige, z. B. Restpunkte "121", Ziel "T20" oder "17".
  final String headline;

  /// Schlüssel für die Beschriftung der großen Anzeige, z. B. "remaining".
  final String headlineKey;
  final List<GameStat> stats;

  /// Wurfvorschlag (Checkout).
  final List<Segment>? suggestion;

  /// Fortschritt 0–1.
  final double? progress;

  /// z. B. "7/21".
  final String? progressLabel;
}

/// Ergebnis eines Spiels.
class GameResult {
  const GameResult({required this.metrics, required this.summary, this.details = const {}});

  /// Zahlen für Statistiken und Rekorde, z. B. {"darts": 54, "hitRate": 0.39}.
  final Map<String, num> metrics;

  /// Zeilen für den Ergebnis-Bildschirm.
  final List<GameStat> summary;

  /// Spielspezifische Details, z. B. die einzelnen Checkout-Versuche.
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => {'metrics': metrics, 'details': details};
}

/// Formatiert eine Quote als "38,5 %".
String formatPercent(num? ratio) =>
    ratio == null ? '–' : '${(ratio * 100).toStringAsFixed(1).replaceAll('.', ',')} %';

/// Formatiert einen Durchschnitt mit einer Nachkommastelle, deutsch.
String formatDecimal(num? value) => value == null ? '–' : value.toStringAsFixed(1).replaceAll('.', ',');
