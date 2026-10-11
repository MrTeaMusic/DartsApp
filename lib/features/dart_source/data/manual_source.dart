import '../../board/domain/segment.dart';
import '../domain/dart_event.dart';
import 'local_dart_source.dart';

/// Manuelle Eingabe als Fallback: Feld antippen, "Weiter" für die nächste
/// Aufnahme, "Rückgängig" für den letzten Dart.
class ManualSource extends LocalDartSource {
  ManualSource({super.clock});

  @override
  DartSourceKind get kind => DartSourceKind.manual;

  @override
  bool get providesCoordinates => false;

  DartThrow enter(Segment segment) => emitThrow(segment);

  /// Restliche Darts der Aufnahme als Miss werten und weiterschalten.
  void nextVisit({bool fillWithMisses = false}) {
    if (fillWithMisses) {
      while (!visitComplete) {
        emitThrow(Segment.miss);
      }
    }
    finishTakeout();
  }
}
