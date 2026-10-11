import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/games/around_the_clock.dart';
import 'package:dartlab/features/games/domain/games/bull_drill.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

void main() {
  group('AroundTheClock', () {
    test('aufsteigend mit Bull, jeder Ring zählt', () {
      final g = AroundTheClock(seed: 1)..prepare();
      expect(g.sequence, [for (var n = 1; n <= 20; n++) n, 25]);
      throwAll(g, ['S2', 'T1', 'D2']);
      expect(g.current, 3);
      expect(g.hits, 2);
      for (var n = 3; n <= 20; n++) {
        throwAll(g, ['S$n']);
      }
      expect(g.current, 25);
      expect(g.targets, {Segment.bull, Segment.outerBull});
      throwAll(g, ['25']);
      expect(g.finished, isTrue);
      expect(g.result.metrics['completed'], 1);
      expect(g.result.metrics['darts'], 22);
    });

    test('nur Doubles, Bull dann nur Bullseye', () {
      final g = AroundTheClock(seed: 1, ring: RingRule.double, includeBull: true)..prepare();
      throwAll(g, ['S1', 'T1']);
      expect(g.current, 1);
      throwAll(g, ['D1']);
      expect(g.current, 2);
      expect(g.display.headline, 'D2');
      expect(g.counts(Segment.outerBull, 25), isFalse);
      expect(g.counts(Segment.bull, 25), isTrue);
    });

    test('Multiplikator springt weiter, aber nicht über das Ende hinaus', () {
      final g = AroundTheClock(seed: 1, multiplierAdvances: true, includeBull: false)..prepare();
      throwAll(g, ['T1']);
      expect(g.current, 4);
      for (final n in ['D4', 'T6', 'T9', 'T12', 'T15', 'T18']) {
        throwAll(g, [n]);
      }
      expect(g.finished, isTrue);
    });

    test('Uhrzeigersinn und Zufall', () {
      final c = AroundTheClock(seed: 1, order: NumberOrder.clockwise, includeBull: false)..prepare();
      expect(c.sequence.take(3), [20, 1, 18]);
      final r1 = AroundTheClock(seed: 5, order: NumberOrder.random)..prepare();
      final r2 = AroundTheClock(seed: 5, order: NumberOrder.random)..prepare();
      expect(r1.sequence, r2.sequence, reason: 'gleicher Startwert, gleiche Folge');
      expect(r1.sequence.last, 25);
      expect(r1.sequence.toSet(), hasLength(21));
    });
  });

  group('BullDrill', () {
    test('Punkte und Ende nach Anzahl Aufnahmen', () {
      final g = BullDrill(seed: 1, visits: 2)..prepare();
      throwAll(g, ['BULL', '25', 'S20']);
      expect(g.points, 75);
      throwAll(g, ['MISS', 'MISS', 'BULL']);
      expect(g.finished, isTrue);
      expect(g.result.metrics['hitRate'], 0.5);
      expect(g.result.metrics['bullRate'], closeTo(2 / 6, 1e-9));
    });
  });
}
