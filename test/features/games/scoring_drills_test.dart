import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/engine/game_display.dart';
import 'package:dartlab/features/games/domain/games/scoring_drills.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

void main() {
  test('T20-Training: Triple- und Zahlquote, Average', () {
    final g = TargetPractice(seed: 1, visits: 2)..prepare();
    expect(g.targets, {Segment.triple(20)});
    throwAll(g, ['T20', 'S20', 'S1', 'T20', 'T20', 'D20']);
    expect(g.finished, isTrue);
    expect(g.total, 60 + 20 + 1 + 60 + 60 + 40);
    expect(g.result.metrics['trebleRate'], 0.5);
    expect(g.result.metrics['numberRate'], closeTo(5 / 6, 1e-9));
    expect(g.result.metrics['average'], closeTo(241 / 6 * 3, 1e-9));
    expect(g.result.metrics['bestVisit'], 160);
  });

  test('T19-Training zählt nur die 19', () {
    final g = TargetPractice(seed: 1, number: 19)..prepare();
    throwAll(g, ['T20', 'T19']);
    expect(g.trebles, 1);
    expect(g.numberHits, 1);
  });

  test('Score-Aufgabe: Erfolg bei mindestens Zielscore', () {
    final g = ScoreTarget(seed: 1, visits: 3, target: 100)..prepare();
    throwAll(g, ['T20', 'S20', 'S20']); // 100
    expect(g.events.last, const GameEvent(GameEventType.visitSuccess, value: 100));
    throwAll(g, ['T20', 'S1', 'S1']); // 62
    expect(g.events.last.type, GameEventType.visitMissed);
    throwAll(g, ['T20', 'T20', 'T20']);
    expect(g.finished, isTrue);
    expect(g.result.metrics['successes'], 2);
    expect(g.result.metrics['successRate'], closeTo(2 / 3, 1e-9));
  });

  test('Score-Aufgabe: Takeout nach zwei Darts wertet die Aufnahme', () {
    final g = ScoreTarget(seed: 1, visits: 2, target: 100)..prepare();
    throwAll(g, ['T20', 'T20']);
    g.endVisit();
    expect(g.successes, 1);
    expect(g.display.headline, '120');
  });

  test('Highscore-Jagd: Bestwert-Ereignis und Tons', () {
    final g = HighscoreHunt(seed: 1, visits: 3)..prepare();
    throwAll(g, ['S20', 'S20', 'S20']);
    expect(g.events.where((e) => e.type == GameEventType.best), isEmpty, reason: 'erste Aufnahme');
    throwAll(g, ['T20', 'T20', 'S20']);
    expect(g.events.last, const GameEvent(GameEventType.best, value: 140));
    throwAll(g, ['S1', 'S1', 'S1']);
    expect(g.finished, isTrue);
    expect(g.result.metrics['points'], 60 + 140 + 3);
    expect(g.result.metrics['tons'], 1);
    expect(g.result.metrics['bestVisit'], 140);
  });
}
