import 'package:dartlab/features/board/domain/segment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Segment', () {
    test('Punkte und Multiplikatoren', () {
      expect(Segment.triple(20).score, 60);
      expect(Segment.double(16).score, 32);
      expect(Segment.single(5).score, 5);
      expect(Segment.single(5, inner: true).score, 5);
      expect(Segment.outerBull.score, 25);
      expect(Segment.bull.score, 50);
      expect(Segment.miss.score, 0);
    });

    test('Bullseye zählt als Double, Single Bull nicht', () {
      expect(Segment.bull.isDouble, isTrue);
      expect(Segment.outerBull.isDouble, isFalse);
      expect(Segment.double(1).isDouble, isTrue);
      expect(Segment.triple(1).isDouble, isFalse);
    });

    test('Namen', () {
      expect(Segment.triple(19).name, 'T19');
      expect(Segment.double(3).name, 'D3');
      expect(Segment.single(7, inner: true).name, 'S7');
      expect(Segment.outerBull.name, '25');
      expect(Segment.bull.name, 'BULL');
      expect(Segment.miss.name, 'MISS');
    });

    test('tryParse liest gängige Schreibweisen', () {
      expect(Segment.tryParse('T20'), Segment.triple(20));
      expect(Segment.tryParse('d16'), Segment.double(16));
      expect(Segment.tryParse('S1'), Segment.single(1));
      expect(Segment.tryParse('25'), Segment.outerBull);
      expect(Segment.tryParse('Bull'), Segment.bull);
      expect(Segment.tryParse('D25'), Segment.bull);
      expect(Segment.tryParse('M'), Segment.miss);
      expect(Segment.tryParse('T21'), isNull);
      expect(Segment.tryParse('X5'), isNull);
      expect(Segment.tryParse(''), isNull);
    });

    test('fromNumber', () {
      expect(Segment.fromNumber(20, 3), Segment.triple(20));
      expect(Segment.fromNumber(25, 2), Segment.bull);
      expect(Segment.fromNumber(25, 1), Segment.outerBull);
      expect(Segment.fromNumber(7, 0), Segment.miss);
      expect(Segment.fromNumber(0, 1), Segment.miss);
      expect(() => Segment.fromNumber(25, 3), throwsArgumentError);
      expect(() => Segment.fromNumber(21, 1), throwsArgumentError);
    });

    test('sameField ignoriert innere/äußere Single-Fläche', () {
      expect(Segment.single(4, inner: true).sameField(Segment.single(4)), isTrue);
      expect(Segment.single(4, inner: true) == Segment.single(4), isFalse);
      expect(Segment.single(4).sameField(Segment.double(4)), isFalse);
    });
  });
}
