import 'dart:async';
import 'dart:math' as math;

import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../domain/dart_event.dart';
import 'local_dart_source.dart';

/// Virtuelles Board zum Testen ohne Hardware.
///
/// Ein Tipp auf das gezeichnete Board ruft [throwAt] mit der exakten Position
/// auf. Mit [aimAt] lässt sich ein Wurf mit Streuung simulieren, damit
/// Heatmap und Statistiken realistische Daten bekommen.
class SimulatorSource extends LocalDartSource {
  SimulatorSource({
    super.clock,
    math.Random? random,
    this.autoTakeout = true,
    this.takeoutDelay = const Duration(milliseconds: 1200),
  }) : _random = random ?? math.Random();

  final math.Random _random;

  /// Nach dem dritten Dart automatisch Takeout melden.
  bool autoTakeout;
  Duration takeoutDelay;
  Timer? _takeoutTimer;

  @override
  DartSourceKind get kind => DartSourceKind.simulator;

  @override
  bool get providesCoordinates => true;

  /// Wurf an eine exakte Position.
  DartThrow throwAt(BoardPoint position) {
    _takeoutTimer?.cancel();
    final dart = emitThrow(BoardGeometry.segmentAt(position), position: position);
    if (autoTakeout && visitComplete) _scheduleTakeout();
    return dart;
  }

  /// Wurf auf [target] mit normalverteilter Streuung.
  /// [spread] ist die Standardabweichung in normierten Einheiten
  /// (0.05 ≈ 8,5 mm, ein guter Amateur liegt etwa bei 0.1).
  DartThrow aimAt(Segment target, {double spread = 0.08}) =>
      throwNear(BoardGeometry.centerOf(target), spread: spread);

  /// Wurf auf einen Zielpunkt mit Streuung (0 = exakt).
  DartThrow throwNear(BoardPoint aim, {double spread = 0.08}) {
    if (spread <= 0) return throwAt(aim);
    return throwAt(aim + BoardPoint(_gaussian() * spread, _gaussian() * spread));
  }

  void _scheduleTakeout() {
    startTakeout();
    if (takeoutDelay == Duration.zero) {
      finishTakeout();
      return;
    }
    _takeoutTimer = Timer(takeoutDelay, finishTakeout);
  }

  // Box-Muller.
  double _gaussian() {
    final u1 = 1.0 - _random.nextDouble();
    final u2 = _random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  @override
  Future<void> stop() async {
    _takeoutTimer?.cancel();
    await super.stop();
  }

  @override
  Future<void> dispose() async {
    _takeoutTimer?.cancel();
    await super.dispose();
  }
}
