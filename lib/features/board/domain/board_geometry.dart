import 'dart:math' as math;

import 'segment.dart';

/// Ein Punkt auf dem Board in normierten Koordinaten.
///
/// Konvention (wie vom Autodarts Board Manager vermutlich geliefert, siehe
/// docs/autodarts-protokoll.md): Mittelpunkt ist (0, 0), Radius 1.0 ist die
/// Außenkante des Double-Rings (170 mm), y zeigt nach oben zur 20.
class BoardPoint {
  const BoardPoint(this.x, this.y);

  static const BoardPoint center = BoardPoint(0, 0);

  final double x;
  final double y;

  double get distance => math.sqrt(x * x + y * y);

  /// Winkel im Uhrzeigersinn ab "oben" (zur 20), in Grad 0–360.
  double get angleDegrees {
    final deg = math.atan2(x, y) * 180 / math.pi;
    return deg < 0 ? deg + 360 : deg;
  }

  BoardPoint operator +(BoardPoint o) => BoardPoint(x + o.x, y + o.y);

  @override
  bool operator ==(Object other) =>
      other is BoardPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() =>
      'BoardPoint(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// Maße eines Standard-Steeldartboards (WDF/PDC) und die Abbildung zwischen
/// Koordinaten und Feldern. Reine Dart-Klasse, gut testbar.
class BoardGeometry {
  const BoardGeometry._();

  /// Zahlen im Uhrzeigersinn, beginnend oben.
  static const List<int> numbers = [
    20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5, //
  ];

  /// Radius der Double-Außenkante in Millimetern (= 1.0 normiert).
  static const double boardRadiusMm = 170;

  static const double innerBullR = 6.35 / boardRadiusMm;
  static const double outerBullR = 15.9 / boardRadiusMm;
  static const double tripleInnerR = 99 / boardRadiusMm;
  static const double tripleOuterR = 107 / boardRadiusMm;
  static const double doubleInnerR = 162 / boardRadiusMm;
  static const double doubleOuterR = 1.0;

  static const double segmentAngle = 18;

  /// Welches Feld liegt an [p]?
  static Segment segmentAt(BoardPoint p) {
    final r = p.distance;
    if (r <= innerBullR) return Segment.bull;
    if (r <= outerBullR) return Segment.outerBull;
    if (r > doubleOuterR) return Segment.miss;
    final number = numberAtAngle(p.angleDegrees);
    if (r <= tripleInnerR) return Segment.single(number, inner: true);
    if (r <= tripleOuterR) return Segment.triple(number);
    if (r <= doubleInnerR) return Segment.single(number);
    return Segment.double(number);
  }

  /// Zahl für einen Winkel (Grad, im Uhrzeigersinn ab oben).
  static int numberAtAngle(double degrees) {
    final normalized = ((degrees + segmentAngle / 2) % 360 + 360) % 360;
    return numbers[(normalized ~/ segmentAngle) % 20];
  }

  /// Mittelwinkel einer Zahl (Grad, im Uhrzeigersinn ab oben).
  static double angleOf(int number) {
    final index = numbers.indexOf(number);
    if (index < 0) throw ArgumentError.value(number, 'number');
    return index * segmentAngle;
  }

  /// Mittelpunkt eines Felds, z. B. als Zielpunkt im Simulator.
  static BoardPoint centerOf(Segment segment) {
    final (double r, int number) = switch (segment.bed) {
      Bed.innerBull => (0, 20),
      Bed.outerBull => ((innerBullR + outerBullR) / 2, 20),
      Bed.singleInner => ((outerBullR + tripleInnerR) / 2, segment.number),
      Bed.triple => ((tripleInnerR + tripleOuterR) / 2, segment.number),
      Bed.singleOuter => ((tripleOuterR + doubleInnerR) / 2, segment.number),
      Bed.double => ((doubleInnerR + doubleOuterR) / 2, segment.number),
      Bed.miss => (1.12, 20),
    };
    return polar(r, angleOf(number));
  }

  /// Punkt aus Radius (normiert) und Winkel (Grad, im Uhrzeigersinn ab oben).
  static BoardPoint polar(double r, double degrees) {
    final rad = degrees * math.pi / 180;
    return BoardPoint(r * math.sin(rad), r * math.cos(rad));
  }
}
