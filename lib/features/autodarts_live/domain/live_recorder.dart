import '../../board/domain/segment.dart';
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

  /// Darts wurden geändert, entfernt oder von Hand ergänzt (Korrektur am
  /// Board oder in der App): alle Würfe der Session neu schreiben.
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
///   Abgeschlossene Aufnahmen bleiben von Board-Meldungen unverändert.
/// * Von Hand korrigieren ([correctDart], [removeDart], [addDart],
///   [removeVisit]) geht in allen aufgezeichneten Aufnahmen der Session, auch
///   den abgeschlossenen. Ein von Hand gesetzter Dart (Quelle
///   [DartSourceKind.manual]) ist „festgehalten“: Eine Korrektur oder ein
///   Rückgängig vom Board fasst ihn nicht an. Ändert oder löscht man in der
///   laufenden Aufnahme Darts von Hand oder ergänzt einen, passen die Stellen
///   des Boards nicht mehr zu unseren; dann ignoriert diese Aufnahme
///   Korrekturen, Rückgängig und Stellenangaben des Boards, bis sie endet.
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

  /// Die laufende Aufnahme wurde von Hand umgebaut (Dart gelöscht oder
  /// ergänzt): Stellen des Boards passen nicht mehr.
  bool _detached = false;

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
    _detached = false;
    _fresh = true;
    return old;
  }

  /// Ist der Dart von Hand gesetzt (korrigiert oder ergänzt)?
  static bool isManual(DartThrow d) => d.source == DartSourceKind.manual;

  /// Anzahl Aufnahmen der Session inklusive der laufenden, solange sie Darts
  /// hat. Die Nummer einer Aufnahme (`visit` unten) ist ihre Stelle von 0.
  int get visitCount => _closed.length + (_current.isEmpty ? 0 : 1);

  /// Zahl abgeschlossener Aufnahmen; die laufende hat diese Nummer.
  int get closedCount => _closed.length;

  /// Darts der Aufnahme [visit] (abgeschlossen oder laufend), sonst `null`.
  /// Die laufende Aufnahme hat die Nummer [closedCount], auch wenn sie leer ist.
  List<DartThrow>? visitAt(int visit) {
    if (visit < 0) return null;
    if (visit < _closed.length) return _closed[visit];
    return visit == _closed.length ? _current : null;
  }

  /// Zahl der Darts vor Dart [dart] der Aufnahme [visit] (Stelle des Darts in
  /// der Session). Für [dart] = Länge der Aufnahme: die Stelle direkt dahinter.
  int seqOf(int visit, int dart) {
    var n = dart;
    for (var i = 0; i < visit && i < _closed.length; i++) {
      n += _closed[i].length;
    }
    return n;
  }

  /// Ersetzt Dart [dart] der Aufnahme [visit] durch [segment]. Der Dart gilt
  /// danach als von Hand gesetzt: ohne Position und Rohdaten des Boards, mit
  /// der alten Zeit. Dasselbe Feld wie bisher ändert nichts.
  LiveUpdate correctDart(int visit, int dart, Segment segment) {
    final v = visitAt(visit);
    if (v == null || dart < 0 || dart >= v.length || v[dart].segment == segment) return LiveUpdate.none;
    v[dart] = DartThrow(segment: segment, timestamp: v[dart].timestamp, source: DartSourceKind.manual);
    return const LiveUpdate(rewritten: true);
  }

  /// Entfernt Dart [dart] der Aufnahme [visit]. War es der letzte der
  /// Aufnahme, verschwindet die Aufnahme; die Nummern späterer rücken nach.
  LiveUpdate removeDart(int visit, int dart) {
    final v = visitAt(visit);
    if (v == null || dart < 0 || dart >= v.length) return LiveUpdate.none;
    v.removeAt(dart);
    if (visit == _closed.length) {
      _detached = v.isNotEmpty;
    } else if (v.isEmpty) {
      _closed.removeAt(visit);
    }
    _refreshLast();
    return const LiveUpdate(rewritten: true);
  }

  /// Hängt einen von Hand ergänzten Dart ans Ende der Aufnahme [visit]
  /// (höchstens [dartsPerVisit]). [at] ist die Zeit für eine leere laufende
  /// Aufnahme; sonst erbt der Dart die Zeit des letzten Darts der Aufnahme.
  LiveUpdate addDart(int visit, Segment segment, DateTime at) {
    final v = visitAt(visit);
    if (v == null || v.length >= dartsPerVisit) return LiveUpdate.none;
    final isCurrent = visit == _closed.length;
    if (isCurrent && v.isEmpty && _fresh) {
      _fresh = false;
      _sessions++;
    }
    v.add(DartThrow(segment: segment, timestamp: v.isEmpty ? at : v.last.timestamp, source: DartSourceKind.manual));
    if (isCurrent) _detached = true;
    _refreshLast();
    return const LiveUpdate(rewritten: true);
  }

  /// Löscht die ganze Aufnahme [visit] (z. B. eine versehentlich
  /// aufgezeichnete). Die laufende Aufnahme wird geleert.
  LiveUpdate removeVisit(int visit) {
    final v = visitAt(visit);
    if (v == null || v.isEmpty) return LiveUpdate.none;
    if (visit == _closed.length) {
      _current.clear();
      _detached = false;
    } else {
      _closed.removeAt(visit);
    }
    _refreshLast();
    return const LiveUpdate(rewritten: true);
  }

  /// Zeit des letzten Darts nach einer Änderung von Hand neu bestimmen
  /// (ohne Darts: keine, damit eine leere Session keine Pause auslöst).
  void _refreshLast() {
    DateTime? last;
    for (final d in darts) {
      if (last == null || d.dart.timestamp.isAfter(last)) last = d.dart.timestamp;
    }
    _lastDartAt = last;
  }

  LiveUpdate apply(DartEvent event) {
    switch (event) {
      case DartThrown(:final dart, :final index):
        return _add(dart, index);
      case DartCorrected(:final index, :final dart):
        if (_detached || index < 0 || index >= _current.length) return LiveUpdate.none;
        // Von Hand gesetzte Darts bleiben, wie sie sind.
        if (isManual(_current[index])) return LiveUpdate.none;
        if (_current[index].segment == dart.segment && _current[index].position == dart.position) return LiveUpdate.none;
        _current[index] = dart;
        return const LiveUpdate(rewritten: true);
      case DartUndone():
        if (_detached || _current.isEmpty || isManual(_current.last)) return LiveUpdate.none;
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
    if (_current.length >= dartsPerVisit || (!_detached && index != null && index < _current.length)) {
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
    _detached = false;
    return true;
  }
}
