import 'training_plan.dart';

/// Feste Trainingspläne. Nur Spiele, die es im [GameCatalog] gibt; die Config
/// nennt nur Abweichungen von den Standardwerten des Spiels.
///
/// Die IDs sind stabil (Durchläufe verweisen darauf), Namen und Texte dürfen
/// sich ändern.
abstract final class BuiltinPlans {
  static const List<TrainingPlan> all = [
    TrainingPlan(
      id: 'builtin-warmup',
      builtIn: true,
      name: 'Aufwärmen',
      description: 'Rund 10 Minuten: einmal ums Board, ein paar Aufnahmen auf die 20, dann aufs Bull.',
      steps: [
        PlanStep(gameId: 'around_the_clock', config: {'order': 'ascending', 'ring': 'any', 'includeBull': false}, note: 'Locker werfen, Rhythmus finden.'),
        PlanStep(gameId: 'target_practice', config: {'number': 20, 'visits': 5}),
        PlanStep(gameId: 'bull_drill', config: {'visits': 5}),
      ],
    ),
    TrainingPlan(
      id: 'builtin-scoring',
      builtIn: true,
      name: 'Scoring',
      description: 'Triple 20 und 19, dann Aufnahmen über 100 und die Highscore-Jagd. Für den Average.',
      steps: [
        PlanStep(gameId: 'target_practice', config: {'number': 20, 'visits': 10}),
        PlanStep(gameId: 'target_practice', config: {'number': 19, 'visits': 10}, note: 'Ausweichziel, wenn die 20 zu ist.'),
        PlanStep(gameId: 'score_target', config: {'target': 100, 'visits': 10}),
        PlanStep(gameId: 'highscore_hunt', config: {'visits': 10}),
      ],
    ),
    TrainingPlan(
      id: 'builtin-doubles',
      builtIn: true,
      name: 'Doppel',
      description: 'Alle Doppel der Reihe nach, Bob\'s 27 und kurze Checkouts bis 40.',
      steps: [
        PlanStep(gameId: 'around_the_clock', config: {'ring': 'double', 'includeBull': false}),
        PlanStep(gameId: 'bobs_27', config: {'startScore': 27, 'includeBull': true}),
        PlanStep(gameId: 'checkout', config: {'mode': 'random', 'min': 2, 'max': 40, 'attempts': 10, 'dartsPerAttempt': 3}, note: 'Lieblingsdoppel üben: D16, D20, D8.'),
      ],
    ),
    TrainingPlan(
      id: 'builtin-checkout',
      builtIn: true,
      name: 'Checkout',
      description: 'Mittlere Finishes, 121 mit 9 Darts und zum Schluss die großen Zahlen.',
      steps: [
        PlanStep(gameId: 'checkout', config: {'mode': 'random', 'min': 41, 'max': 100, 'attempts': 10, 'dartsPerAttempt': 3}),
        PlanStep(gameId: 'one_twenty_one', config: {'start': 121, 'dartsPerAttempt': 9, 'rounds': 10}),
        PlanStep(gameId: 'checkout', config: {'mode': 'random', 'min': 101, 'max': 170, 'attempts': 5, 'dartsPerAttempt': 6}, note: 'Den Weg vor dem ersten Dart planen.'),
      ],
    ),
    TrainingPlan(
      id: 'builtin-allround30',
      builtIn: true,
      name: 'Allround in 30 Minuten',
      description: 'Ein bisschen von allem: Treffsicherheit, Scoring, Doppel, Checkout und Cricket.',
      steps: [
        PlanStep(gameId: 'around_the_clock', config: {'ring': 'any', 'includeBull': true}),
        PlanStep(gameId: 'target_practice', config: {'number': 20, 'visits': 8}),
        PlanStep(gameId: 'bobs_27', config: {'includeBull': false}),
        PlanStep(gameId: 'checkout', config: {'mode': 'random', 'min': 2, 'max': 100, 'attempts': 8, 'dartsPerAttempt': 3}),
        PlanStep(gameId: 'cricket', config: {'cricketOrder': 'sequential', 'marksToClose': 3, 'includeBull': true}),
      ],
    ),
    TrainingPlan(
      id: 'builtin-beginner',
      builtIn: true,
      name: 'Einsteiger',
      description: 'Für den Anfang: Zahlen treffen, ein paar Aufnahmen zählen und einfache Checkouts ohne Doppelpflicht.',
      steps: [
        PlanStep(gameId: 'around_the_clock', config: {'ring': 'any', 'includeBull': false}, note: 'Jedes Feld der Zahl zählt.'),
        PlanStep(gameId: 'three_hits', config: {'hitsRequired': 1, 'includeBull': false}),
        PlanStep(gameId: 'highscore_hunt', config: {'visits': 5}),
        PlanStep(gameId: 'checkout', config: {'mode': 'random', 'min': 2, 'max': 40, 'attempts': 5, 'doubleOut': false, 'showSuggestion': true}),
      ],
    ),
  ];

  static TrainingPlan? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}
