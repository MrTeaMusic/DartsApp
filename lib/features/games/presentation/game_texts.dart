import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../domain/engine/game_display.dart';
import '../domain/games/around_the_clock.dart';
import '../domain/games/bull_drill.dart';
import '../domain/games/checkout/checkout_training.dart';
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
        _ => id,
      };

  String gameDescription(String id) => switch (id) {
        CheckoutTraining.id => gameCheckoutDesc,
        AroundTheClock.id => gameAroundClockDesc,
        BullDrill.id => gameBullDrillDesc,
        TargetPractice.id => gameTargetPracticeDesc,
        ScoreTarget.id => gameScoreTargetDesc,
        HighscoreHunt.id => gameHighscoreDesc,
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
      };
}

IconData gameIcon(String id) => switch (id) {
      CheckoutTraining.id => Icons.flag_rounded,
      AroundTheClock.id => Icons.av_timer_rounded,
      BullDrill.id => Icons.trip_origin_rounded,
      TargetPractice.id => Icons.gps_fixed_rounded,
      ScoreTarget.id => Icons.trending_up_rounded,
      HighscoreHunt.id => Icons.emoji_events_rounded,
      _ => Icons.sports_esports_rounded,
    };

/// Wichtigkeit eines Ereignisses für die Banner-Farbe.
enum EventTone { positive, negative, neutral }

EventTone eventTone(GameEventType t) => switch (t) {
      GameEventType.checkout || GameEventType.visitSuccess || GameEventType.best || GameEventType.advanced => EventTone.positive,
      GameEventType.bust || GameEventType.failed || GameEventType.visitMissed => EventTone.negative,
      _ => EventTone.neutral,
    };
