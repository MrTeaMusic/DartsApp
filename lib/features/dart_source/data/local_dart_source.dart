import 'dart:async';

import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../domain/dart_event.dart';
import '../domain/dart_source.dart';

/// Gemeinsame Basis für Quellen, die im Gerät selbst entstehen
/// (Simulator, manuelle Eingabe). Sie verhalten sich wie ein echtes Board:
/// maximal drei Darts pro Aufnahme, danach Takeout.
abstract class LocalDartSource implements DartSource {
  LocalDartSource({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _events = StreamController<DartEvent>.broadcast();
  final _status = StreamController<SourceStatus>.broadcast();
  SourceStatus _current = SourceStatus.idle;
  bool _disposed = false;

  /// Darts der laufenden Aufnahme.
  final List<DartThrow> _visit = [];

  List<DartThrow> get currentVisit => List.unmodifiable(_visit);

  static const int dartsPerVisit = 3;

  bool get visitComplete => _visit.length >= dartsPerVisit;

  @override
  Stream<DartEvent> get events => _events.stream;

  @override
  Stream<SourceStatus> get statusChanges => _status.stream;

  @override
  SourceStatus get status => _current;

  @override
  Stream<RawMessage> get rawMessages => const Stream.empty();

  @override
  Future<void> start() async => _setStatus(SourceStatus.ready);

  @override
  Future<void> stop() async => _setStatus(SourceStatus.idle);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _events.close();
    await _status.close();
  }

  DateTime now() => _clock();

  /// Meldet einen Dart. Ist die Aufnahme schon voll, wird erst automatisch
  /// eine neue begonnen (wie ein vergessener Takeout am echten Board).
  DartThrow emitThrow(Segment segment, {BoardPoint? position}) {
    if (visitComplete) finishTakeout();
    final dart = DartThrow(
      segment: segment,
      position: position,
      timestamp: now(),
      source: kind,
    );
    _visit.add(dart);
    _emit(DartThrown(dart, index: _visit.length - 1));
    return dart;
  }

  /// Nimmt den letzten Dart der Aufnahme zurück.
  bool undoLast() {
    if (_visit.isEmpty) return false;
    _visit.removeLast();
    _emit(DartUndone(now()));
    return true;
  }

  void startTakeout() => _emit(TakeoutStarted(now()));

  /// Schließt die Aufnahme ab, die nächste beginnt leer.
  void finishTakeout() {
    _visit.clear();
    _emit(TakeoutFinished(now()));
  }

  void resetVisit() {
    _visit.clear();
    _emit(TurnReset(now()));
  }

  void _emit(DartEvent event) {
    if (!_disposed) _events.add(event);
  }

  void _setStatus(SourceStatus s) {
    _current = s;
    if (!_disposed) _status.add(s);
  }
}
