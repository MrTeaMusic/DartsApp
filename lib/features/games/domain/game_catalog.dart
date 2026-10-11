import 'engine/game_definition.dart';
import 'games/around_the_clock.dart';
import 'games/bobs_27.dart';
import 'games/bull_drill.dart';
import 'games/catch_40.dart';
import 'games/checkout/checkout_training.dart';
import 'games/cricket.dart';
import 'games/doubles_420.dart';
import 'games/doubles_ladder.dart';
import 'games/exact_score.dart';
import 'games/frustration.dart';
import 'games/golf.dart';
import 'games/halve_it.dart';
import 'games/jdc_challenge.dart';
import 'games/one_twenty_one.dart';
import 'games/own_games.dart';
import 'games/scoring_drills.dart';
import 'games/setup_shot.dart';
import 'games/shanghai.dart';
import 'games/switch_drill.dart';
import 'games/three_in_a_bed.dart';
import 'games/x01_solo.dart';

/// Alle spielbaren Trainings. Ein neues Spiel wird hier eingetragen.
abstract final class GameCatalog {
  static final List<GameDefinition> all = [
    CheckoutTraining.definition,
    AroundTheClock.definition,
    BullDrill.definition,
    TargetPractice.definition,
    ScoreTarget.definition,
    HighscoreHunt.definition,
    CricketTraining.definition,
    OneTwentyOne.definition,
    Bobs27.definition,
    ThreeHitsRound.definition,
    SkipAroundTheWorld.definition,
    X01Solo.definition,
    HalveIt.definition,
    Catch40.definition,
    JdcChallenge.definition,
    Shanghai.definition,
    DartsGolf.definition,
    Doubles420.definition,
    Frustration.definition,
    SwitchDrill.definition,
    DoublesLadder.definition,
    ExactScore.definition,
    ThreeInABed.definition,
    SetupShot.definition,
  ];

  static GameDefinition? byId(String id) {
    for (final d in all) {
      if (d.id == id) return d;
    }
    return null;
  }
}
