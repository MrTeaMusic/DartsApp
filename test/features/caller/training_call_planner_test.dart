import 'package:dartlab/features/caller/domain/caller_phrases.dart';
import 'package:dartlab/features/caller/domain/training_call_planner.dart';
import 'package:dartlab/features/games/domain/engine/training_game.dart';
import 'package:dartlab/features/games/domain/games/around_the_clock.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_training.dart';
import 'package:dartlab/features/games/domain/games/cricket.dart';
import 'package:dartlab/features/games/domain/games/scoring_drills.dart';
import 'package:dartlab/features/games/domain/games/x01_solo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/darts.dart';

/// Wirft eine Aufnahme und liefert, was der Caller danach sagen würde.
List<CallerCall> visit(TrainingGame game, List<String> darts) {
  final before = game.display;
  throwAll(game, darts);
  expect(game.visitClosed || game.finished, isTrue, reason: 'Aufnahme sollte abgeschlossen sein');
  return TrainingCallPlanner.forVisit(game, before: before);
}

void main() {
  group('X01', () {
    test('180 ohne Finish-Rest', () {
      final g = X01Solo(seed: 1)..prepare();
      expect(TrainingCallPlanner.isCallable(g), isTrue);
      expect(visit(g, ['T20', 'T20', 'T20']), [const ScoreCall(180)]);
    });

    test('Rest auf einem Finish wird angesagt', () {
      final g = X01Solo(seed: 1)..prepare();
      visit(g, ['T20', 'T20', 'T20']);
      expect(visit(g, ['T20', 'T20', 'T20']), [const ScoreCall(180), const RequireCall(141)]);
      expect(visit(g, ['T20', 'S1', 'M']), [const ScoreCall(61), const RequireCall(80)]);
    });

    test('No score und Bogey-Zahlen ohne „You require“', () {
      final g = X01Solo(seed: 1, startScore: 169)..prepare();
      expect(visit(g, ['M', 'M', 'M']), [const ScoreCall(0)]);
    });

    test('Bust: „Bust“ und der alte Rest', () {
      final g = X01Solo(seed: 1, startScore: 40)..prepare();
      expect(visit(g, ['T20']), [const BustCall(), const RequireCall(40)]);
    });

    test('Checkout im einzigen Leg: Game shot and the match', () {
      final g = X01Solo(seed: 1, startScore: 40)..prepare();
      expect(visit(g, ['D20']), [const GameShotCall(GameShotKind.match)]);
    });

    test('Checkout mit weiteren Legs: Game shot and the leg', () {
      final g = X01Solo(seed: 1, startScore: 40, legs: 2)..prepare();
      expect(visit(g, ['S20', 'D10']), [const GameShotCall(GameShotKind.leg)]);
      g.endVisit(); // Takeout nach vorzeitigem Ende.
      expect(visit(g, ['D20']), [const GameShotCall(GameShotKind.match)]);
    });

    test('Double-In: nur Punkte ab dem Einstieg zählen', () {
      final g = X01Solo(seed: 1, doubleIn: true)..prepare();
      expect(visit(g, ['S20', 'D20', 'S20']), [const ScoreCall(60)]);
    });
  });

  test('Checkout-Training: Game shot ohne Leg', () {
    final g = CheckoutTraining(seed: 1, mode: CheckoutMode.descending, min: 40, max: 41, attempts: 5)..prepare();
    expect(g.display.headline, '41');
    expect(visit(g, ['S1', 'D20']), [const GameShotCall()]);
    g.endVisit();
    // Nächstes Ziel 40: verfehlte Aufnahme sagt Punkte und das neue Ziel an.
    final calls = visit(g, ['S5', 'M', 'M']);
    expect(calls.first, const ScoreCall(5));
    expect(calls.last, isA<RequireCall>());
  });

  test('Scoring-Drill: Punkte, kein Rest', () {
    final g = HighscoreHunt(seed: 1)..prepare();
    expect(TrainingCallPlanner.isCallable(g), isTrue);
    expect(visit(g, ['T20', 'S20', 'T19']), [const ScoreCall(137)]);
  });

  test('Spiele ohne Aufnahme-Punkte bleiben still', () {
    final atc = AroundTheClock(seed: 1)..prepare();
    expect(TrainingCallPlanner.isCallable(atc), isFalse);
    expect(visit(atc, ['S1', 'S2', 'S3']), isEmpty);

    final cricket = CricketTraining(seed: 1)..prepare();
    expect(TrainingCallPlanner.isCallable(cricket), isFalse);
  });
}
