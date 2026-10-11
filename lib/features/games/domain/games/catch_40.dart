import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';
import 'checkout/checkout_calculator.dart';
import 'checkout/checkout_rules.dart';

/// Catch 40: Finishes von [min] bis [max] der Reihe nach, ein Versuch pro Ziel.
///
/// Regeln:
/// * Pro Ziel [visitsPerTarget] Aufnahmen. Ein Checkout beendet den Versuch
///   sofort, das nächste Ziel beginnt mit der nächsten Aufnahme.
/// * Bust und Double-Out wie beim Checkout-Training.
/// * Punkte: Sei m = max(2, minimale Dartzahl des Ziels). Checkout mit ≤ m
///   Darts = 3, sonst mit ≤ 3 Darts = 2, sonst geschafft = 1, nicht
///   geschafft = 0.
/// * Nicht checkbare Werte werden übersprungen.
class Catch40 extends TrainingGame {
  Catch40({
    required super.seed,
    this.min = 61,
    this.max = 100,
    this.visitsPerTarget = 2,
    this.doubleOut = true,
    this.showSuggestion = true,
  });

  static const String id = 'catch_40';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'min': 61, 'max': 100, 'dartsPerTarget': 6, 'doubleOut': true, 'showSuggestion': true},
    options: const [
      IntOption('min', min: 2, max: 170),
      IntOption('max', min: 2, max: 170),
      IntChoiceOption('dartsPerTarget', [3, 6, 9]),
      BoolOption('doubleOut'),
      BoolOption('showSuggestion'),
    ],
    normalize: (c) {
      final a = c.intOf('min', 61).clamp(2, 170);
      final b = c.intOf('max', 100).clamp(2, 170);
      return {...c, 'min': a < b ? a : b, 'max': a < b ? b : a};
    },
    create: (c, seed) => Catch40(
      seed: seed,
      min: c.intOf('min', 61),
      max: c.intOf('max', 100),
      visitsPerTarget: (c.intOf('dartsPerTarget', 6) ~/ TrainingGame.dartsPerVisit).clamp(1, 3),
      doubleOut: c.boolOf('doubleOut', true),
      showSuggestion: c.boolOf('showSuggestion', true),
    ),
  );

  final int min;
  final int max;
  final int visitsPerTarget;
  final bool doubleOut;
  final bool showSuggestion;

  late final List<int> pool;
  final List<({int target, int darts, int points})> results = [];

  int index = 0;
  int remaining = 0;
  int _visitStartRemaining = 0;
  int _visitsUsed = 0;
  bool _justAdvanced = false;

  OutMode get _out => OutMode.fromDoubleOut(doubleOut);
  int get target => pool[index.clamp(0, pool.length - 1)];
  int get points => results.fold(0, (s, r) => s + r.points);
  int get maxPoints => pool.length * 3;

  @override
  void onStart() {
    pool = CheckoutCalculator.checkoutTargets(min: min, max: max, doubleOut: doubleOut);
    if (pool.isEmpty) pool.add(doubleOut ? 40 : 20);
    _setTarget();
  }

  void _setTarget() {
    remaining = target;
    _visitStartRemaining = target;
    _visitsUsed = 0;
  }

  @override
  void onVisitStart() => _visitStartRemaining = remaining;

  /// Punkte für einen Checkout von [target] mit [darts] Darts.
  int pointsFor(int target, int darts) {
    final minDarts = CheckoutRules.suggest(target, darts: 3, out: _out)?.length ?? 3;
    final m = minDarts < 2 ? 2 : minDarts;
    if (darts <= m) return 3;
    if (darts <= 3) return 2;
    return 1;
  }

  @override
  void handleDart(DartThrow dart) {
    if (CheckoutRules.isBust(remaining, dart.segment, _out)) {
      remaining = _visitStartRemaining;
      events.add(GameEvent(GameEventType.bust, value: target));
      closeVisit();
      return;
    }
    remaining -= dart.score;
    if (remaining == 0) {
      final darts = _visitsUsed * TrainingGame.dartsPerVisit + visit.length;
      final p = pointsFor(target, darts);
      results.add((target: target, darts: darts, points: p));
      events.add(GameEvent(GameEventType.checkout, value: target));
      _next(closing: true);
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
    results.add((target: target, darts: _visitsUsed * TrainingGame.dartsPerVisit, points: 0));
    events.add(GameEvent(GameEventType.failed, value: target));
    _next();
  }

  void _next({bool closing = false}) {
    index++;
    if (index >= pool.length) {
      finish();
      return;
    }
    _setTarget();
    if (closing) {
      _justAdvanced = true;
      closeVisit();
    }
  }

  List<Segment>? get suggestion =>
      showSuggestion && !finished ? CheckoutRules.suggest(remaining, darts: dartsLeftInVisit, out: _out) : null;

  int get checkouts => results.where((r) => r.points > 0).length;

  @override
  Set<Segment> get targets {
    final s = suggestion;
    return s == null || s.isEmpty ? const {} : {s.first};
  }

  @override
  GameDisplay get display => GameDisplay(
        headline: '$remaining',
        headlineKey: 'remaining',
        suggestion: suggestion,
        progress: results.length / pool.length,
        progressLabel: '${finished ? pool.length : results.length + 1}/${pool.length}',
        stats: [
          GameStat('target', '$target'),
          GameStat('points', '$points/$maxPoints'),
          GameStat('attemptDarts',
              '${_visitsUsed * TrainingGame.dartsPerVisit + (visitClosed ? 0 : visit.length)}/${visitsPerTarget * TrainingGame.dartsPerVisit}'),
        ],
      );

  @override
  GameResult get result {
    final ok = results.where((r) => r.points > 0).toList();
    final rate = results.isEmpty ? null : ok.length / results.length;
    final dartsPer = ok.isEmpty ? null : ok.fold<int>(0, (s, r) => s + r.darts) / ok.length;
    final three = results.where((r) => r.points == 3).length;
    return GameResult(
      metrics: {
        'points': points,
        'maxPoints': maxPoints,
        'checkouts': ok.length,
        'checkoutRate': rate ?? 0,
        'dartsPerCheckout': ?dartsPer,
        'threePointers': three,
        'darts': dartsThrown,
        'completed': results.length >= pool.length ? 1 : 0,
      },
      summary: [
        GameStat('points', '$points/$maxPoints'),
        GameStat('checkouts', '${ok.length}/${results.length}'),
        GameStat('checkoutRate', formatPercent(rate)),
        GameStat('avgDartsPerCheckout', formatDecimal(dartsPer)),
        GameStat('threePointers', '$three'),
      ],
      details: {
        'targets': [for (final r in results) {'target': r.target, 'darts': r.darts, 'points': r.points}],
      },
    );
  }
}
