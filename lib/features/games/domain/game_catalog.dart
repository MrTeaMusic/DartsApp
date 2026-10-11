import 'engine/game_definition.dart';
import 'games/around_the_clock.dart';
import 'games/bull_drill.dart';
import 'games/checkout/checkout_training.dart';
import 'games/scoring_drills.dart';

/// Alle spielbaren Trainings. Ein neues Spiel wird hier eingetragen.
abstract final class GameCatalog {
  static final List<GameDefinition> all = [
    CheckoutTraining.definition,
    AroundTheClock.definition,
    BullDrill.definition,
    TargetPractice.definition,
    ScoreTarget.definition,
    HighscoreHunt.definition,
  ];

  static GameDefinition? byId(String id) {
    for (final d in all) {
      if (d.id == id) return d;
    }
    return null;
  }
}
