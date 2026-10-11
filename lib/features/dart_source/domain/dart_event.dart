import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';

/// Woher ein Wurf kommt.
enum DartSourceKind { simulator, manual, autodartsLocal }

/// Ein einzelner Dart, unabhängig von der Quelle.
class DartThrow {
  const DartThrow({
    required this.segment,
    required this.timestamp,
    required this.source,
    this.position,
    this.raw,
  });

  final Segment segment;

  /// Normierte Position auf dem Board, falls die Quelle sie liefert.
  final BoardPoint? position;
  final DateTime timestamp;
  final DartSourceKind source;

  /// Rohdaten der Quelle (z. B. das JSON-Objekt von Autodarts), damit
  /// Statistiken später neu berechnet werden können.
  final Map<String, Object?>? raw;

  int get score => segment.score;

  @override
  String toString() => 'DartThrow(${segment.name}, $position)';
}

/// Alles, was eine [DartSource] an die Spiele meldet.
sealed class DartEvent {
  const DartEvent(this.timestamp);
  final DateTime timestamp;
}

/// Ein neuer Dart wurde erkannt oder eingegeben.
class DartThrown extends DartEvent {
  DartThrown(this.dart, {this.index}) : super(dart.timestamp);
  final DartThrow dart;

  /// Position innerhalb der Aufnahme (0–2), falls die Quelle sie kennt.
  final int? index;
}

/// Ein bereits gemeldeter Dart wurde nachträglich geändert
/// (z. B. Korrektur am Board). Spiele sollten den Dart an [index] ersetzen.
class DartCorrected extends DartEvent {
  DartCorrected(this.index, this.dart) : super(dart.timestamp);
  final int index;
  final DartThrow dart;
}

/// Der letzte Dart der Aufnahme wurde zurückgenommen.
class DartUndone extends DartEvent {
  const DartUndone(super.timestamp);
}

/// Spieler zieht die Darts (Takeout beginnt).
class TakeoutStarted extends DartEvent {
  const TakeoutStarted(super.timestamp);
}

/// Board ist leer, die nächste Aufnahme kann beginnen.
class TakeoutFinished extends DartEvent {
  const TakeoutFinished(super.timestamp);
}

/// Die Aufnahme wurde verworfen (Reset am Board oder "Rückgängig").
class TurnReset extends DartEvent {
  const TurnReset(super.timestamp);
}
