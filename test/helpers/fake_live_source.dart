import 'dart:async';

import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/board_control.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';

/// Quelle, die sich wie der lokale Board Manager meldet (Art Autodarts),
/// deren Ereignisse der Test aber selbst auslöst. Ohne Timer und Netzwerk.
class FakeLiveSource implements DartSource, BoardControl {
  FakeLiveSource({SourceStatus? status, DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    if (status != null) _status = status;
  }

  final _events = StreamController<DartEvent>.broadcast(sync: true);
  final _statusCtrl = StreamController<SourceStatus>.broadcast();
  final DateTime Function() _clock;
  SourceStatus _status = SourceStatus.ready;
  int _inVisit = 0;
  final _runningCtrl = StreamController<bool?>.broadcast();
  bool? _boardRunning;

  /// Befehle der Board-Hilfe, in der Reihenfolge ihres Eintreffens.
  final commands = <(BoardAction, {bool userInitiated})>[];

  /// Antwort auf den nächsten Befehl; null = HTTP 200.
  BoardCommandResult? nextResult;

  @override
  bool listenOnly = false;

  @override
  String get boardAddress => '127.0.0.1:3180';

  @override
  bool? get boardRunning => _boardRunning;

  @override
  Stream<bool?> get boardRunningChanges => _runningCtrl.stream;

  void setBoardRunning(bool? v) {
    _boardRunning = v;
    _runningCtrl.add(v);
  }

  @override
  Future<BoardCommandResult> run(BoardAction action, {bool userInitiated = false}) async {
    commands.add((action, userInitiated: userInitiated));
    if (listenOnly && !userInitiated) return const BoardCommandResult.blocked();
    return nextResult ?? const BoardCommandResult(statusCode: 200, path: '/fake');
  }

  @override
  DartSourceKind get kind => DartSourceKind.autodartsLocal;

  @override
  bool get providesCoordinates => true;

  @override
  Stream<DartEvent> get events => _events.stream;

  @override
  Stream<SourceStatus> get statusChanges => _statusCtrl.stream;

  @override
  SourceStatus get status => _status;

  @override
  Stream<RawMessage> get rawMessages => const Stream.empty();

  void setStatus(SourceStatus s) {
    _status = s;
    _statusCtrl.add(s);
  }

  /// Ein Dart wie vom Board Manager (Position: Feldmitte, leicht versetzt).
  void dart(String name, {BoardPoint? at, DateTime? time}) {
    final s = Segment.tryParse(name)!;
    final c = s.isMiss ? const BoardPoint(0.8, 1.2) : BoardGeometry.centerOf(s);
    _events.add(DartThrown(
      DartThrow(segment: s, position: at ?? c, timestamp: time ?? _clock(), source: DartSourceKind.autodartsLocal),
      index: _inVisit++,
    ));
  }

  void visit(List<String> names, {bool takeout = true}) {
    for (final n in names) {
      dart(n);
    }
    if (takeout) this.takeout();
  }

  void takeout() {
    _inVisit = 0;
    _events.add(TakeoutStarted(_clock()));
    _events.add(TakeoutFinished(_clock()));
  }

  void emit(DartEvent e) => _events.add(e);

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _events.close();
    await _statusCtrl.close();
    await _runningCtrl.close();
  }
}
