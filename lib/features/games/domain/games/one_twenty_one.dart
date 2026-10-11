import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';
import 'checkout/checkout_calculator.dart';
import 'checkout/checkout_rules.dart';

/// Was nach einem verpassten Checkout passiert.
enum FailRule {
  /// Das Ziel bleibt gleich.
  stay,

  /// Zurück zum zuletzt geschafften Ziel (am Anfang zum Startwert).
  back,

  /// Ein Ziel runter (nie unter den Startwert).
  down,
}

/// 121: aufsteigendes Checkout-Training.
///
/// Regeln:
/// * Start bei [start] (Standard 121). Pro Ziel hast du [visitsPerTarget]
///   Aufnahmen (3, 6 oder 9 Darts).
/// * Geschafft: nächstes Ziel ist eins höher. Der geschaffte Wert wird zum
///   „sicheren“ Wert.
/// * Nicht geschafft: je nach [failRule] gleich bleiben, zurück zum sicheren
///   Wert oder eins runter.
/// * Bust wie beim Checkout: Rest auf den Stand vor der Aufnahme, Aufnahme
///   vorbei. Double-Out ist abschaltbar.
/// * Ende nach [rounds] Zielen oder wenn 170 ausgecheckt ist.
class OneTwentyOne extends TrainingGame {
  OneTwentyOne({
    required super.seed,
    this.start = 121,
    this.visitsPerTarget = 3,
    this.rounds = 10,
    this.failRule = FailRule.back,
    this.doubleOut = true,
    this.showSuggestion = true,
  });

  static const String id = 'one_twenty_one';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {
      'start': 121,
      'dartsPerAttempt': 9,
      'rounds': 10,
      'failRule': 'back',
      'doubleOut': true,
      'showSuggestion': true,
    },
    options: const [
      IntOption('start', min: 2, max: 170),
      IntChoiceOption('dartsPerAttempt', [3, 6, 9]),
      IntOption('rounds', min: 1, max: 50),
      ChoiceOption('failRule', ['back', 'stay', 'down']),
      BoolOption('doubleOut'),
      BoolOption('showSuggestion'),
    ],
    create: (c, seed) => OneTwentyOne(
      seed: seed,
      start: c.intOf('start', 121),
      visitsPerTarget: (c.intOf('dartsPerAttempt', 9) ~/ TrainingGame.dartsPerVisit).clamp(1, 3),
      rounds: c.intOf('rounds', 10),
      failRule: FailRule.values.firstWhere((v) => v.name == c.stringOf('failRule', 'back'), orElse: () => FailRule.back),
      doubleOut: c.boolOf('doubleOut', true),
      showSuggestion: c.boolOf('showSuggestion', true),
    ),
  );

  final int start;
  final int visitsPerTarget;
  final int rounds;
  final FailRule failRule;
  final bool doubleOut;
  final bool showSuggestion;

  late int target = _valid(start);
  late int remaining = target;
  late int safe = target;
  late int highest = 0;
  int _visitStartRemaining = 0;
  int _visitsUsed = 0;
  bool _justAdvanced = false;

  /// (Ziel, geschafft, Darts) je Runde.
  final List<({int target, bool success, int darts})> history = [];

  int get _min => doubleOut ? 2 : 1;
  int _valid(int v) => v.clamp(_min, CheckoutCalculator.maxCheckout);

  @override
  void onStart() => _visitStartRemaining = remaining;

  @override
  void onVisitStart() => _visitStartRemaining = remaining;

  @override
  void handleDart(DartThrow dart) {
    if (CheckoutRules.isBust(remaining, dart.segment, OutMode.fromDoubleOut(doubleOut))) {
      remaining = _visitStartRemaining;
      events.add(GameEvent(GameEventType.bust, value: target));
      closeVisit();
      return;
    }
    remaining -= dart.score;
    if (remaining == 0) {
      history.add((target: target, success: true, darts: _visitsUsed * TrainingGame.dartsPerVisit + visit.length));
      events.add(GameEvent(GameEventType.checkout, value: target));
      if (target > highest) highest = target;
      safe = target;
      _next(target + 1, closing: true);
    } else if (!dart.segment.isMiss) {
      events.add(GameEvent(GameEventType.hit, value: dart.score));
    }
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    if (_justAdvanced) {
      _justAdvanced = false;
      return;
    }
    _visitsUsed++;
    if (_visitsUsed < visitsPerTarget) {
      _visitStartRemaining = remaining;
      return;
    }
    history.add((target: target, success: false, darts: _visitsUsed * TrainingGame.dartsPerVisit));
    events.add(GameEvent(GameEventType.failed, value: target));
    _next(switch (failRule) {
      FailRule.stay => target,
      FailRule.back => safe,
      FailRule.down => target - 1 < start ? start : target - 1,
    });
  }

  void _next(int value, {bool closing = false}) {
    if (history.length >= rounds || (history.last.success && target >= CheckoutCalculator.maxCheckout)) {
      finish();
      return;
    }
    target = _valid(value);
    remaining = target;
    _visitStartRemaining = target;
    _visitsUsed = 0;
    if (closing) {
      _justAdvanced = true;
      closeVisit();
    }
  }

  int get successes => history.where((h) => h.success).length;

  int get _dartsLeftInVisit => visitClosed ? TrainingGame.dartsPerVisit : TrainingGame.dartsPerVisit - visit.length;

  List<Segment>? get suggestion =>
      showSuggestion ? CheckoutCalculator.suggest(remaining, darts: _dartsLeftInVisit, doubleOut: doubleOut) : null;

  @override
  Set<Segment> get targets {
    final s = suggestion;
    return finished || s == null || s.isEmpty ? const {} : {s.first};
  }

  @override
  GameDisplay get display => GameDisplay(
        headline: '$remaining',
        headlineKey: 'remaining',
        suggestion: finished ? null : suggestion,
        progress: history.length / rounds,
        progressLabel: '${finished ? rounds : history.length + 1}/$rounds',
        stats: [
          GameStat('target', '$target'),
          GameStat('highestCheckout', highest == 0 ? '–' : '$highest'),
          GameStat('checkouts', '$successes/${history.length}'),
          GameStat('attemptDarts', '${_visitsUsed * TrainingGame.dartsPerVisit + (visitClosed ? 0 : visit.length)}/${visitsPerTarget * TrainingGame.dartsPerVisit}'),
        ],
      );

  @override
  GameResult get result {
    final rate = history.isEmpty ? null : successes / history.length;
    return GameResult(
      metrics: {
        'rounds': history.length,
        'checkouts': successes,
        'checkoutRate': rate ?? 0,
        'highestCheckout': highest,
        'endTarget': target,
        'darts': dartsThrown,
      },
      summary: [
        GameStat('highestCheckout', highest == 0 ? '–' : '$highest'),
        GameStat('checkouts', '$successes/${history.length}'),
        GameStat('checkoutRate', formatPercent(rate)),
      ],
      details: {
        'rounds': [for (final h in history) {'target': h.target, 'success': h.success, 'darts': h.darts}],
      },
    );
  }
}
