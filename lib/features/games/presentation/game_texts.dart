import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../domain/engine/game_display.dart';
import '../domain/games/around_the_clock.dart';
import '../domain/games/bobs_27.dart';
import '../domain/games/bull_drill.dart';
import '../domain/games/checkout/checkout_training.dart';
import '../domain/games/cricket.dart';
import '../domain/games/one_twenty_one.dart';
import '../domain/games/own_games.dart';
import '../domain/games/scoring_drills.dart';

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
        _ => id,
      };

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
        _ => '',
      };

  String optionLabel(String key) => switch (key) {
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
        _ => key,
      };

  String optionValue(String value) => switch (value) {
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
      GameEventType.skipped =>
        EventTone.positive,
      GameEventType.bust || GameEventType.failed || GameEventType.visitMissed => EventTone.negative,
      _ => EventTone.neutral,
    };
