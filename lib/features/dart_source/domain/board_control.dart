import 'dart_source.dart';

/// Was der Nutzer am hängenden Board anstoßen kann („Board-Hilfe“).
enum BoardAction {
  /// Kalibrierung neu starten.
  recalibrate,

  /// Erkennung anhalten.
  stop,

  /// Erkennung wieder starten.
  start,

  /// Board neu laden: erst Neustart, ersatzweise Reset.
  refresh,
}

/// Ausgang eines Befehls an das Board. Enthält bewusst nur den Statuscode,
/// nie den Antwort-Body (er könnte Schlüssel oder Konfiguration enthalten).
class BoardCommandResult {
  const BoardCommandResult({
    this.statusCode,
    this.error,
    this.blocked = false,
    this.path = '',
    this.fellBackFrom,
    this.fallbackStatusCode,
  });

  /// Nicht gesendet, weil DartLab nur mithören soll und der Befehl nicht
  /// ausdrücklich vom Nutzer kam.
  const BoardCommandResult.blocked() : this(blocked: true);

  /// HTTP-Status der Antwort des Boards; null, wenn keine kam.
  final int? statusCode;

  /// Fehlertext, wenn das Board nicht erreicht wurde (Zeitlimit, Verbindung).
  final String? error;
  final bool blocked;

  /// Pfad des Befehls, dessen Antwort [statusCode] ist.
  final String path;

  /// Beim Refresh: Pfad, den das Board nicht kannte (404/405), bevor
  /// ersatzweise [path] gesendet wurde. Dessen Antwort steht in [fallbackStatusCode].
  final String? fellBackFrom;
  final int? fallbackStatusCode;

  /// Das Board hat den Befehl mit 2xx angenommen. Das heißt noch nicht, dass
  /// er am Board etwas bewirkt hat.
  bool get ok => statusCode != null && statusCode! >= 200 && statusCode! < 300;

  /// Das Board hat überhaupt geantwortet.
  bool get answered => statusCode != null;
}

/// Eine Datenquelle, an die sich Befehle für das Board schicken lassen
/// (der lokale Autodarts Board Manager).
abstract interface class BoardControl {
  /// Nur mithören: Befehle gehen nur raus, wenn der Nutzer sie ausdrücklich
  /// ausgelöst hat (`userInitiated`).
  bool get listenOnly;

  /// Läuft die Erkennung am Board? Null, solange der Board Manager es nicht
  /// gemeldet hat.
  bool? get boardRunning;
  Stream<bool?> get boardRunningChanges;

  /// Adresse des Board Managers für Hinweise („host:port“).
  String get boardAddress;

  /// Führt [action] aus. Automatische Aufrufer lassen [userInitiated] auf
  /// `false`: dann bleibt die Sperre [listenOnly] wirksam.
  Future<BoardCommandResult> run(BoardAction action, {bool userInitiated = false});
}

/// Wie bereit das Board gerade ist, abgeleitet aus Verbindung und Takeout.
enum BoardReadiness {
  /// Verbunden, Darts können geworfen werden.
  ready,

  /// Darts werden gerade entfernt.
  takeout,

  /// Verbunden, aber die Erkennung ist angehalten.
  stopped,

  /// Verbindung wird aufgebaut.
  connecting,

  /// Keine Verbindung zum Board Manager (inkl. Wartezeit bis zum nächsten Versuch).
  offline,
}

/// Leitet [BoardReadiness] ab. Ohne Verbindung zählt der Takeout nicht: ein
/// alter Takeout-Zustand soll nach dem Wiederverbinden nicht gelb hängen bleiben.
BoardReadiness boardReadiness(SourceStatus status, {bool takeout = false, bool? running}) {
  return switch (status.phase) {
    SourcePhase.connected || SourcePhase.polling => running == false
        ? BoardReadiness.stopped
        : takeout
            ? BoardReadiness.takeout
            : BoardReadiness.ready,
    SourcePhase.connecting => BoardReadiness.connecting,
    SourcePhase.reconnecting || SourcePhase.error || SourcePhase.idle => BoardReadiness.offline,
  };
}
