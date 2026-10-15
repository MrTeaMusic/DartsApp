import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../domain/engine/game_display.dart';
import '../domain/games/around_the_clock.dart';
import '../domain/games/bobs_27.dart';
import '../domain/games/bull_drill.dart';
import '../domain/games/catch_40.dart';
import '../domain/games/checkout/checkout_training.dart';
import '../domain/games/cricket.dart';
import '../domain/games/doubles_420.dart';
import '../domain/games/doubles_ladder.dart';
import '../domain/games/exact_score.dart';
import '../domain/games/frustration.dart';
import '../domain/games/golf.dart';
import '../domain/games/halve_it.dart';
import '../domain/games/jdc_challenge.dart';
import '../domain/games/one_twenty_one.dart';
import '../domain/games/own_games.dart';
import '../domain/games/scoring_drills.dart';
import '../domain/games/setup_shot.dart';
import '../domain/games/shanghai.dart';
import '../domain/games/switch_drill.dart';
import '../domain/games/three_in_a_bed.dart';
import '../domain/games/x01_solo.dart';
import '../../matches/domain/match_result.dart';
import '../../autodarts_live/domain/live_stats.dart';
import '../../quiz/domain/quiz_config.dart';
import '../../stats/domain/game_metrics.dart';

/// Übersetzt die stabilen Schlüssel der Spiel-Domäne in Text und Icons.
/// Unbekannte Schlüssel erscheinen unverändert, damit nichts verschwindet.
extension GameTexts on AppLocalizations {
  String gameTitle(String id) => switch (id) {
        CheckoutTraining.id => gameCheckout,
        AroundTheClock.id => gameAroundClock,
        BullDrill.id => gameBullDrill,
        TargetPractice.id => gameTargetPractice,
        ScoreTarget.id => gameScoreTarget,
        HighscoreHunt.id => gameHighscore,
        CricketTraining.id => gameCricket,
        OneTwentyOne.id => game121,
        Bobs27.id => gameBobs27,
        ThreeHitsRound.id => gameThreeHits,
        SkipAroundTheWorld.id => gameSkip,
        X01Solo.id => gameX01,
        HalveIt.id => gameHalveIt,
        Catch40.id => gameCatch40,
        JdcChallenge.id => gameJdc,
        Shanghai.id => gameShanghai,
        DartsGolf.id => gameGolf,
        Doubles420.id => gameDoubles420,
        Frustration.id => gameFrustration,
        SwitchDrill.id => gameSwitchDrill,
        DoublesLadder.id => gameDoublesLadder,
        ExactScore.id => gameExactScore,
        ThreeInABed.id => gameThreeInABed,
        SetupShot.id => gameSetupShot,
        matchGameId => gameMatchX01,
        autodartsLiveGameId => liveTitle,
        autodartsLiveX01GameId => liveTitleX01,
        checkoutQuizGameId => quizTitle,
        _ => id,
      };

  /// Umfang einer Session für Listen: die Darts, bei Spielen ohne Würfe
  /// (Checkout-Quiz) die Zahl der Fragen aus den Kennzahlen.
  String sessionAmount(String gameId, int darts, Map<String, num> metrics) => throwlessGames.contains(gameId)
      ? quizQuestions((metrics['answered'] ?? 0).toInt())
      : '$darts $statDarts';

  String gameDescription(String id) => switch (id) {
        CheckoutTraining.id => gameCheckoutDesc,
        AroundTheClock.id => gameAroundClockDesc,
        BullDrill.id => gameBullDrillDesc,
        TargetPractice.id => gameTargetPracticeDesc,
        ScoreTarget.id => gameScoreTargetDesc,
        HighscoreHunt.id => gameHighscoreDesc,
        CricketTraining.id => gameCricketDesc,
        OneTwentyOne.id => game121Desc,
        Bobs27.id => gameBobs27Desc,
        ThreeHitsRound.id => gameThreeHitsDesc,
        SkipAroundTheWorld.id => gameSkipDesc,
        X01Solo.id => gameX01Desc,
        HalveIt.id => gameHalveItDesc,
        Catch40.id => gameCatch40Desc,
        JdcChallenge.id => gameJdcDesc,
        Shanghai.id => gameShanghaiDesc,
        DartsGolf.id => gameGolfDesc,
        Doubles420.id => gameDoubles420Desc,
        Frustration.id => gameFrustrationDesc,
        SwitchDrill.id => gameSwitchDrillDesc,
        DoublesLadder.id => gameDoublesLadderDesc,
        ExactScore.id => gameExactScoreDesc,
        ThreeInABed.id => gameThreeInABedDesc,
        SetupShot.id => gameSetupShotDesc,
        checkoutQuizGameId => quizEntryText,
        _ => '',
      };

  /// Beschriftung einer Option. Mit [gameId] gelten spielspezifische
  /// Beschriftungen für Schlüssel, die mehrere Spiele unterschiedlich nutzen.
  String optionLabel(String key, [String? gameId]) => switch ((gameId, key)) {
        (X01Solo.id, 'startScore') => optStart,
        (ThreeInABed.id, 'mode') => optBedMode,
        (ExactScore.id, 'target') => optExactTarget,
        (SwitchDrill.id, 'rounds') => optSwitchRounds,
        (SetupShot.id, 'min') => optMinRest,
        (SetupShot.id, 'max') => optMaxRest,
        _ => _optionLabel(key),
      };

  String _optionLabel(String key) => switch (key) {
        'mode' => optMode,
        'min' => optMin,
        'max' => optMax,
        'attempts' => optAttempts,
        'dartsPerAttempt' => optDartsPerAttempt,
        'showSuggestion' => optShowSuggestion,
        'doubleOut' => optDoubleOut,
        'order' => optOrder,
        'ring' => optRing,
        'includeBull' => optIncludeBull,
        'multiplierAdvances' => optMultiplierAdvances,
        'visits' => optVisits,
        'number' => optNumber,
        'target' => optTarget,
        'cricketOrder' => optCricketOrder,
        'marksToClose' => optMarksToClose,
        'start' => optStart,
        'rounds' => optRounds,
        'failRule' => optFailRule,
        'startScore' => optStartScore,
        'allowNegative' => optAllowNegative,
        'hitsRequired' => optHitsRequired,
        'multiplierCounts' => optMultiplierCounts,
        'skipThreshold' => optSkipThreshold,
        'bullSkippable' => optBullSkippable,
        'inMode' => optInMode,
        'outMode' => optOutMode,
        'legs' => optLegs,
        'dartLimit' => optDartLimit,
        'preset' => optPreset,
        'rounding' => optRounding,
        'dartsPerTarget' => optDartsPerTarget,
        'from' => optFrom,
        'to' => optTo,
        'shanghaiWins' => optShanghaiWins,
        'shanghaiBonus' => optShanghaiBonus,
        'holes' => optHoles,
        'scoring' => optScoring,
        'counts' => optCounts,
        'sequence' => optSequence,
        'setupMin' => optSetupMin,
        'maxVisits' => optMaxVisits,
        'difficulty' => optDifficulty,
        'visitsPerAttempt' => optVisitsPerAttempt,
        'overshoot' => optOvershoot,
        'leaves' => optLeaves,
        'darts' => optDarts,
        _ => key,
      };

  /// Beschriftung eines Auswahlwerts. Mit [key] (Options-Schlüssel) gelten
  /// Beschriftungen für Werte, die je nach Option etwas anderes bedeuten.
  String optionValue(String value, {String? key}) => switch ((key, value)) {
        ('rounding', 'down') => valRoundDown,
        ('rounding', 'up') => valRoundUp,
        ('preset', 'short') => valShortHalveIt,
        ('sequence', 'short') => valShortFrustration,
        ('scoring', 'classic') => valClassicGolf,
        ('leaves', 'classic') => valClassicLeaves,
        ('overshoot', 'bust') => valBust,
        _ => _optionValue(value),
      };

  String _optionValue(String value) => switch (value) {
        'random' => valRandom,
        'descending' => valDescending,
        'weak' => valWeak,
        'ascending' => valAscending,
        'clockwise' => valClockwise,
        'any' => valAny,
        'single' => single,
        'double' => this.double,
        'triple' => triple,
        'free' => valFree,
        'sequential' => valSequential,
        'back' => valBack,
        'stay' => valStay,
        'down' => valDown,
        'straight' => valStraight,
        'master' => valMaster,
        'bermuda' => valBermuda,
        'simple' => valSimple,
        'last' => valLast,
        'best' => valBest,
        'full' => valFull,
        'normal' => valNormal,
        'pro' => valPro,
        'fail' => valFail,
        'good' => valGood,
        'anyDouble' => valAnyDouble,
        'wedge' => valWedge,
        'segment' => valSegment,
        '167' => val167,
        'trebles' => valTrebles,
        'doubles' => valDoubles,
        'scoring' => valScoring,
        _ => value,
      };

  String statLabel(String key) => switch (key) {
        'target' => statTarget,
        'checkouts' => statCheckouts,
        'checkoutRate' => statCheckoutRate,
        'avgDartsPerCheckout' => statAvgDartsPerCheckout,
        'highestCheckout' => statHighestCheckout,
        'darts' => statDarts,
        'hitRate' => statHitRate,
        'next' => statNext,
        'progress' => statProgress,
        'points' => statPoints,
        'bullHits' => statBullHits,
        'outerBullHits' => statOuterBullHits,
        'bullRate' => statBullRate,
        'average' => statAverage,
        'trebleRate' => statTrebleRate,
        'numberRate' => statNumberRate,
        'bestVisit' => statBestVisit,
        'scoreTarget' => statScoreTarget,
        'successes' => statSuccesses,
        'successRate' => statSuccessRate,
        'visitScore' => statVisitScore,
        'tons' => statTons,
        'remaining' => statRemaining,
        'openNumbers' => statOpenNumbers,
        'mpr' => statMpr,
        'closedNumbers' => statClosedNumbers,
        'attemptDarts' => statAttemptDarts,
        'doubleHits' => statDoubleHits,
        'doubleRate' => statDoubleRate,
        'hitsOnTarget' => statHitsOnTarget,
        'skips' => statSkips,
        'pointsPerNumber' => statPointsPerNumber,
        'legDarts' => statLegDarts,
        'legsWon' => statLegsWon,
        'first9Average' => statFirst9Average,
        'bestLegDarts' => statBestLegDarts,
        'highestFinish' => statHighestFinish,
        'scores100' => statScores100,
        'doubleToStart' => statDoubleToStart,
        'halvings' => statHalvings,
        'bestRound' => statBestRound,
        'cleanRounds' => statCleanRounds,
        'threePointers' => statThreePointers,
        'part' => statPart,
        'partPoints' => statPartPoints,
        'part1' => statPart1,
        'part2' => statPart2,
        'part3' => statPart3,
        'shanghais' => statShanghais,
        'triples' => statTriples,
        'hole' => statHole,
        'strokes' => statStrokes,
        'toPar' => statToPar,
        'holeValue' => statHoleValue,
        'holesInOne' => statHolesInOne,
        'averagePerHole' => statAveragePerHole,
        'missedDoubles' => statMissedDoubles,
        'visits' => statVisits,
        'setupScore' => statSetupScore,
        'setupRate' => statSetupRate,
        'perfectRounds' => statPerfectRounds,
        'rateOf' => statRateOf,
        'level' => statLevel,
        'highestLevel' => statHighestLevel,
        'visitsLeft' => statVisitsLeft,
        'averageDarts' => statAverageDarts,
        'averageGap' => statAverageGap,
        'ideal' => statIdeal,
        'idealRate' => statIdealRate,
        'rawAverage' => statRawAverage,
        'triplesRate' => statTriplesRate,
        'doublesRate' => statDoublesRate,
        'singlesRate' => statSinglesRate,
        'missRate' => statMissRate,
        'count100' => statCount100,
        'count140' => statCount140,
        'count180' => statCount180,
        'quizCorrect' => statQuizCorrect,
        'correct' => statCorrect,
        'correctRate' => statCorrectRate,
        'answered' => statAnswered,
        'bestStreak' => statBestStreak,
        'avgSeconds' => statAvgSeconds,
        'quizPace' => statQuizPace,
        _ => key,
      };

  String eventText(GameEvent e) => switch (e.type) {
        GameEventType.bust => evBust,
        GameEventType.checkout => evCheckout('${e.value ?? ''}'),
        GameEventType.failed => evFailed,
        GameEventType.hit => evHit('${e.value ?? ''}'),
        GameEventType.advanced => evAdvanced,
        GameEventType.visitSuccess => evVisitSuccess('${e.value ?? ''}'),
        GameEventType.visitMissed => evVisitMissed('${e.value ?? ''}'),
        GameEventType.best => evBest('${e.value ?? ''}'),
        GameEventType.finished => evFinished,
        GameEventType.closed => evClosed('${e.value ?? ''}'),
        GameEventType.skipped => evSkipped('${e.value ?? ''}'),
        GameEventType.shanghai => evShanghai('${e.value ?? ''}'),
        GameEventType.halved => evHalved('${e.value ?? ''}'),
        GameEventType.levelDown => evLevelDown('${e.value ?? ''}'),
        GameEventType.partComplete => evPartComplete('${e.value ?? ''}'),
        GameEventType.legComplete => evLegComplete('${e.value ?? ''}'),
      };
}

IconData gameIcon(String id) => switch (id) {
      CheckoutTraining.id => Icons.flag_rounded,
      AroundTheClock.id => Icons.av_timer_rounded,
      BullDrill.id => Icons.trip_origin_rounded,
      TargetPractice.id => Icons.gps_fixed_rounded,
      ScoreTarget.id => Icons.trending_up_rounded,
      HighscoreHunt.id => Icons.emoji_events_rounded,
      CricketTraining.id => Icons.grid_on_rounded,
      OneTwentyOne.id => Icons.stairs_rounded,
      Bobs27.id => Icons.looks_two_rounded,
      ThreeHitsRound.id => Icons.repeat_rounded,
      SkipAroundTheWorld.id => Icons.fast_forward_rounded,
      X01Solo.id => Icons.scoreboard_rounded,
      HalveIt.id => Icons.content_cut_rounded,
      Catch40.id => Icons.done_all_rounded,
      JdcChallenge.id => Icons.school_rounded,
      Shanghai.id => Icons.filter_3_rounded,
      DartsGolf.id => Icons.golf_course_rounded,
      Doubles420.id => Icons.hourglass_bottom_rounded,
      Frustration.id => Icons.sentiment_dissatisfied_rounded,
      SwitchDrill.id => Icons.swap_horiz_rounded,
      DoublesLadder.id => Icons.height_rounded,
      ExactScore.id => Icons.ads_click_rounded,
      ThreeInABed.id => Icons.bed_rounded,
      SetupShot.id => Icons.tune_rounded,
      matchGameId => Icons.people_alt_rounded,
      autodartsLiveGameId || autodartsLiveX01GameId => Icons.hearing_rounded,
      checkoutQuizGameId => Icons.quiz_rounded,
      _ => Icons.sports_esports_rounded,
    };

/// Wichtigkeit eines Ereignisses für die Banner-Farbe.
enum EventTone { positive, negative, neutral }

EventTone eventTone(GameEventType t) => switch (t) {
      GameEventType.checkout ||
      GameEventType.visitSuccess ||
      GameEventType.best ||
      GameEventType.advanced ||
      GameEventType.closed ||
      GameEventType.skipped ||
      GameEventType.shanghai ||
      GameEventType.partComplete ||
      GameEventType.legComplete =>
        EventTone.positive,
      GameEventType.bust ||
      GameEventType.failed ||
      GameEventType.visitMissed ||
      GameEventType.halved ||
      GameEventType.levelDown =>
        EventTone.negative,
      _ => EventTone.neutral,
    };
