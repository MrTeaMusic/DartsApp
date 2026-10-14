import '../../dart_source/domain/dart_event.dart';
import 'live_stats.dart';

/// Ein Dart der Session mit seiner Stelle in der Datenbank.
typedef RecordedDart = ({DartThrow dart, int visitIndex});

/// Was ein Ereignis an der Session geändert hat. Der Controller leitet
/// daraus die Schreibvorgänge ab.
class LiveUpdate {
  const LiveUpdate({
    this.closedSession,
    this.added,
    this.rewritten = false,
    this.visitClosed = false,
  });

  static const LiveUpdate none = LiveUpdate();

  /// Wegen einer langen Pause abgeschlossene Session (alle ihre Darts).
  /// Der neue Dart gehört schon zur nächsten Session.
  final List<RecordedDart>? closedSession;

  /// Neuer Dart am Ende der Session (Stelle = Länge der Session - 1).
  final RecordedDart? added;

  /// Darts der laufenden Aufnahme wurden geändert oder entfernt
  /// (Korrektur am Board): alle Würfe der Session neu schreiben.
  final bool rewritten;

  /// Eine Aufnahme wurde abgeschlossen.
  final bool visitClosed;

  bool get changed => closedSession != null || added != null || rewritten || visitClosed;
}

/// Schreibt die Darts vom eigenen Board mit und fasst sie zu Aufnahmen
/// zusammen. Rein passiv: bekommt nur [DartEvent]s, schickt nichts zurück.
///
/// Regeln:
/// * Eine Aufnahme endet mit dem Takeout (Darts gezogen), einem Reset am
///   Board oder spätestens nach drei Darts (vergessener Takeout).
/// * Meldet die Quelle für den neuen Dart eine Stelle, die schon belegt ist
///   (z. B. Stelle 0 bei laufender Aufnahme nach einer Neuverbindung),
///   beginnt eine neue Aufnahme.
/// * Korrekturen und entfernte Darts der laufenden Aufnahme werden
///   übernommen, damit sie dem Stand des Board Managers entspricht.
///   Abgeschlossene Aufnahmen bleiben unverändert.
/// * Nach [pauseLimit] ohne Dart beginnt mit dem nächsten Dart eine neue
///   Session.
class LiveRecorder {
  LiveRecorder({this.pauseLimit = defaultPauseLimit});

  /// Pause, nach der eine neue Session beginnt.
  static const Duration defaultPauseLimit = Duration(minutes: 20);

  static const int dartsPerVisit = 3;

  final Duration pauseLimit;

  final List<List<DartThrow>> _closed = [];
  final List<DartThrow> _current = [];
  DateTime? _lastDartAt;
  int _sessions = 0;
  bool _fresh = true;

  /// Abgeschlossene Aufnahmen der laufenden Session, älteste zuerst.
  List<List<DartThrow>> get closedVisits => [for (final v in _closed) List.unmodifiable(v)];

  /// Darts der laufenden Aufnahme (0–3).
  List<DartThrow> get currentVisit => List.unmodifiable(_current);

  /// Zuletzt abgeschlossene Aufnahme dieser Session.
  List<DartThrow>? get lastClosedVisit => _closed.isEmpty ? null : List.unmodifiable(_closed.last);

  /// Zeitpunkt des letzten Darts.
  DateTime? get lastDartAt => _lastDartAt;

  /// Wie viele Sessions schon begonnen haben (0 = noch kein Dart).
  int get sessionCount => _sessions;

  /// Alle Darts der laufenden Session in Wurfreihenfolge.
  List<RecordedDart> get darts => [
        for (final (i, v) in [..._closed, _current].indexed)
          for (final d in v) (dart: d, visitIndex: i),
      ];

  int get dartCount => _closed.fold(_current.length, (a, v) => a + v.length);

  /// Kennzahlen der laufenden Session (inklusive laufender Aufnahme).
  LiveStats get stats => LiveStats.of([
        for (final v in [..._closed, _current]) [for (final d in v) (segment: d.segment, position: d.position)],
      ]);

  /// Beginnt von Hand eine neue Session (z. B. „X01 mitzählen“ umgeschaltet).
  /// Gibt die Darts der bisherigen Session zurück; der nächste Dart gehört
  /// zur neuen.
  List<RecordedDart> startNewSession() {
    final old = darts;
    _closed.clear();
    _current.clear();
    _fresh = true;
    return old;
  }

  LiveUpdate apply(DartEvent event) {
    switch (event) {
      case DartThrown(:final dart, :final index):
        return _add(dart, index);
      case DartCorrected(:final index, :final dart):
        if (index < 0 || index >= _current.length) return LiveUpdate.none;
        if (_current[index].segment == dart.segment && _current[index].position == dart.position) return LiveUpdate.none;
        _current[index] = dart;
        return const LiveUpdate(rewritten: true);
      case DartUndone():
        if (_current.isEmpty) return LiveUpdate.none;
        _current.removeLast();
        return const LiveUpdate(rewritten: true);
      case TakeoutFinished() || TurnReset():
        return LiveUpdate(visitClosed: _closeVisit());
      case TakeoutStarted():
        return LiveUpdate.none;
    }
  }

  LiveUpdate _add(DartThrow dart, int? index) {
    List<RecordedDart>? closedSession;
    var visitClosed = false;
    final last = _lastDartAt;
    if (last != null && dart.timestamp.difference(last) >= pauseLimit) {
      _closeVisit();
      closedSession = startNewSession();
    }
    if (_current.length >= dartsPerVisit || (index != null && index < _current.length)) {
      visitClosed = _closeVisit();
    }
    if (_fresh) {
      _fresh = false;
      _sessions++;
    }
    _current.add(dart);
    _lastDartAt = dart.timestamp;
    return LiveUpdate(
      closedSession: closedSession,
      added: (dart: dart, visitIndex: _closed.length),
      visitClosed: visitClosed,
    );
  }

  bool _closeVisit() {
    if (_current.isEmpty) return false;
    _closed.add([..._current]);
    _current.clear();
    return true;
  }
}
