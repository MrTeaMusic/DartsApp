import 'dart_event.dart';

/// Verbindungszustand einer Quelle.
enum SourcePhase {
  /// Nicht gestartet.
  idle,
  connecting,

  /// Live-Verbindung steht (WebSocket bzw. lokale Quelle bereit).
  connected,

  /// Nur HTTP-Polling, kein WebSocket.
  polling,

  /// Verbindung verloren, nächster Versuch ist geplant.
  reconnecting,
  error,
}

class SourceStatus {
  const SourceStatus(this.phase, {this.message, this.nextRetry});

  static const SourceStatus idle = SourceStatus(SourcePhase.idle);
  static const SourceStatus ready = SourceStatus(SourcePhase.connected);

  final SourcePhase phase;

  /// Technischer Hinweis, z. B. die letzte Fehlermeldung.
  final String? message;

  /// Wann der nächste Verbindungsversuch stattfindet.
  final DateTime? nextRetry;

  bool get isLive =>
      phase == SourcePhase.connected || phase == SourcePhase.polling;

  @override
  bool operator ==(Object other) =>
      other is SourceStatus &&
      other.phase == phase &&
      other.message == message &&
      other.nextRetry == nextRetry;

  @override
  int get hashCode => Object.hash(phase, message, nextRetry);

  @override
  String toString() => 'SourceStatus($phase${message == null ? '' : ', $message'})';
}

/// Eine rohe Nachricht, wie sie von der Quelle ankam. Für den Debug-Bildschirm.
class RawMessage {
  const RawMessage({
    required this.timestamp,
    required this.channel,
    required this.payload,
    this.incoming = true,
  });

  final DateTime timestamp;

  /// z. B. "ws", "http GET /api/state", "info".
  final String channel;
  final String payload;
  final bool incoming;
}

/// Die einzige Schnittstelle, über die Spiele Würfe bekommen.
///
/// Spiele sprechen nie direkt mit Autodarts. Ändert sich das Protokoll,
/// muss nur die jeweilige Implementierung angepasst werden.
abstract class DartSource {
  DartSourceKind get kind;

  /// Würfe, Korrekturen und Takeouts.
  Stream<DartEvent> get events;

  Stream<SourceStatus> get statusChanges;
  SourceStatus get status;

  /// Rohe Nachrichten (nur bei echten Hardware-Quellen interessant).
  Stream<RawMessage> get rawMessages => const Stream.empty();

  /// Liefert die Quelle Wurfkoordinaten (für die Heatmap)?
  bool get providesCoordinates;

  Future<void> start();
  Future<void> stop();

  /// Gibt alle Ressourcen frei. Danach darf die Quelle nicht mehr genutzt werden.
  Future<void> dispose();
}
