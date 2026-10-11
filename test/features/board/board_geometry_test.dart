import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoardGeometry.segmentAt', () {
    test('Mitte ist Bullseye, knapp daneben Single Bull', () {
      expect(BoardGeometry.segmentAt(BoardPoint.center), Segment.bull);
      expect(BoardGeometry.segmentAt(const BoardPoint(0, 0.06)), Segment.outerBull);
    });

    test('Himmelsrichtungen: 20 oben, 6 rechts, 3 unten, 11 links', () {
      expect(BoardGeometry.segmentAt(const BoardPoint(0, 0.5)), Segment.single(20, inner: true));
      expect(BoardGeometry.segmentAt(const BoardPoint(0.5, 0)), Segment.single(6, inner: true));
      expect(BoardGeometry.segmentAt(const BoardPoint(0, -0.5)), Segment.single(3, inner: true));
      expect(BoardGeometry.segmentAt(const BoardPoint(-0.5, 0)), Segment.single(11, inner: true));
    });

    test('Ringe von innen nach außen', () {
      Segment at(double r) => BoardGeometry.segmentAt(BoardPoint(0, r));
      expect(at(0.4), Segment.single(20, inner: true));
      expect(at(0.61), Segment.triple(20));
      expect(at(0.8), Segment.single(20));
      expect(at(0.98), Segment.double(20));
      expect(at(1.01), Segment.miss);
    });

    test('Segmentgrenze bei 9° zwischen 20 und 1', () {
      expect(BoardGeometry.segmentAt(BoardGeometry.polar(0.8, 8.9)).number, 20);
      expect(BoardGeometry.segmentAt(BoardGeometry.polar(0.8, 9.1)).number, 1);
      expect(BoardGeometry.segmentAt(BoardGeometry.polar(0.8, 351.1)).number, 20);
      expect(BoardGeometry.segmentAt(BoardGeometry.polar(0.8, 350.9)).number, 5);
    });

    test('centerOf liegt immer im eigenen Feld', () {
      final all = <Segment>[
        for (final n in BoardGeometry.numbers) ...[
          Segment.single(n),
          Segment.single(n, inner: true),
          Segment.double(n),
          Segment.triple(n),
        ],
        Segment.bull,
        Segment.outerBull,
        Segment.miss,
      ];
      for (final s in all) {
        expect(BoardGeometry.segmentAt(BoardGeometry.centerOf(s)), s, reason: s.name);
      }
    });

    test('Winkel und Polarkoordinaten', () {
      expect(BoardGeometry.angleOf(20), 0);
      expect(BoardGeometry.angleOf(6), 90);
      expect(BoardGeometry.angleOf(3), 180);
      expect(BoardGeometry.polar(1, 90).x, closeTo(1, 1e-9));
      expect(const BoardPoint(-1, 0).angleDegrees, closeTo(270, 1e-9));
    });
  });
}
