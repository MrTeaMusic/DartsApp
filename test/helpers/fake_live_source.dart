import 'dart:async';

import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';

/// Quelle, die sich wie der lokale Board Manager meldet (Art Autodarts),
/// deren Ereignisse der Test aber selbst auslöst. Ohne Timer und Netzwerk.
class FakeLiveSource implements DartSource {
  FakeLiveSource({SourceStatus? status, DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    if (status != null) _status = status;
  }

  final _events = StreamController<DartEvent>.broadcast(sync: true);
  final _statusCtrl = StreamController<SourceStatus>.broadcast();
  final DateTime Function() _clock;
  SourceStatus _status = SourceStatus.ready;
  int _inVisit = 0;

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
  }
}
