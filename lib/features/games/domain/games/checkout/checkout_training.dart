import '../../../../board/domain/segment.dart';
import '../../../../dart_source/domain/dart_event.dart';
import '../../engine/game_definition.dart';
import '../../engine/game_display.dart';
import '../../engine/training_game.dart';
import 'checkout_calculator.dart';

/// Wie die Zielwerte gewählt werden.
enum CheckoutMode {
  /// Zufällig aus allen checkbaren Werten zwischen min und max.
  random,

  /// Der Reihe nach von max abwärts bis min.
  descending,

  /// Bevorzugt Werte mit schlechter Quote aus früheren Sessions.
  weak,
}

/// Ein Versuch im Checkout-Training.
class CheckoutAttempt {
  const CheckoutAttempt({required this.target, required this.success, required this.darts});
  final int target;
  final bool success;

  /// Benötigte bzw. verbrauchte Darts (Busts zählen als volle Aufnahme).
  final int darts;

  Map<String, Object?> toJson() => {'target': target, 'success': success, 'darts': darts};

  static CheckoutAttempt? fromJson(Object? json) {
    if (json is! Map) return null;
    final t = json['target'];
    final s = json['success'];
    final d = json['darts'];
    if (t is! int || s is! bool || d is! int) return null;
    return CheckoutAttempt(target: t, success: s, darts: d);
  }
}

/// Checkout-Training: Finishes von 170 bis 2 mit Double-Out.
///
/// Regeln:
/// * Pro Versuch ein Zielwert, dafür [visitsPerAttempt] Aufnahmen.
/// * Bust (unter 0, Rest 1 oder 0 ohne Doppel) beendet die Aufnahme, der Rest
///   springt auf den Stand vor der Aufnahme zurück.
/// * Checkout beendet den Versuch sofort; danach kommt der nächste Zielwert.
class CheckoutTraining extends TrainingGame {
  CheckoutTraining({
    required super.seed,
    this.mode = CheckoutMode.random,
    this.min = 2,
    this.max = 170,
    this.attempts = 10,
    this.visitsPerAttempt = 1,
    this.showSuggestion = true,
    this.doubleOut = true,
    this.weakTargets = const [],
  });

  static const String id = 'checkout';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {
      'mode': 'random',
      'min': 2,
      'max': 170,
      'attempts': 10,
      'dartsPerAttempt': 3,
      'showSuggestion': true,
      'doubleOut': true,
      'weakTargets': <int>[],
    },
    options: const [
      ChoiceOption('mode', ['random', 'descending', 'weak']),
      IntOption('min', min: 2, max: 170),
      IntOption('max', min: 2, max: 170),
      IntOption('attempts', min: 1, max: 50),
      IntChoiceOption('dartsPerAttempt', [3, 6, 9]),
      BoolOption('showSuggestion'),
      BoolOption('doubleOut'),
    ],
    normalize: (c) {
      final a = c.intOf('min', 2).clamp(2, 170);
      final b = c.intOf('max', 170).clamp(2, 170);
      return {...c, 'min': a < b ? a : b, 'max': a < b ? b : a};
    },
    create: (c, seed) => CheckoutTraining(
      seed: seed,
      mode: CheckoutMode.values.firstWhere((m) => m.name == c.stringOf('mode', 'random'), orElse: () => CheckoutMode.random),
      min: c.intOf('min', 2),
      max: c.intOf('max', 170),
      attempts: c.intOf('attempts', 10),
      visitsPerAttempt: (c.intOf('dartsPerAttempt', 3) / 3).ceil().clamp(1, 3),
      showSuggestion: c.boolOf('showSuggestion', true),
      doubleOut: c.boolOf('doubleOut', true),
      weakTargets: c.intListOf('weakTargets'),
    ),
  );

  final CheckoutMode mode;
  final int min;
  final int max;
  final int attempts;
  final int visitsPerAttempt;
  final bool showSuggestion;
  final bool doubleOut;

  /// Vorab aus der Datenbank ermittelte schwache Werte (für [CheckoutMode.weak]).
  final List<int> weakTargets;

  late final List<int> _pool;
  final List<CheckoutAttempt> results = [];

  int target = 0;
  int remaining = 0;
  int _visitStartRemaining = 0;
  int _visitsUsed = 0;
  int _descendingIndex = 0;

  @override
  void onStart() {
    _pool = CheckoutCalculator.checkoutTargets(min: min, max: max, doubleOut: doubleOut);
    if (_pool.isEmpty) {
      _pool.add(doubleOut ? 40 : 20);
    }
    _nextTarget();
  }

  void _nextTarget() {
    final previous = target;
    target = switch (mode) {
      CheckoutMode.descending => _pool[_pool.length - 1 - (_descendingIndex++ % _pool.length)],
      CheckoutMode.weak => _pickWeak(previous),
      CheckoutMode.random => _pickRandom(previous),
    };
    remaining = target;
    _visitStartRemaining = target;
    _visitsUsed = 0;
  }

  int _pickRandom(int previous) {
    if (_pool.length == 1) return _pool.first;
    while (true) {
      final v = _pool[random.nextInt(_pool.length)];
      if (v != previous) return v;
    }
  }

  int _pickWeak(int previous) {
    final weak = weakTargets.where(_pool.contains).toList();
    // 70 % schwache Werte, sonst zufällig, damit es abwechslungsreich bleibt.
    if (weak.isEmpty || random.nextDouble() >= 0.7) return _pickRandom(previous);
    final candidates = weak.where((v) => v != previous).toList();
    return candidates.isEmpty ? _pickRandom(previous) : candidates[random.nextInt(candidates.length)];
  }

  int get attemptNumber => results.length + 1;

  @override
  void onVisitStart() => _visitStartRemaining = remaining;

  @override
  void handleDart(DartThrow dart) {
    final next = remaining - dart.score;
    final bust = doubleOut ? (next < 0 || next == 1 || (next == 0 && !dart.segment.isDouble)) : next < 0;
    if (bust) {
      remaining = _visitStartRemaining;
      events.add(GameEvent(GameEventType.bust, value: target));
      closeVisit();
      return;
    }
    remaining = next;
    if (remaining == 0) {
      final darts = _visitsUsed * TrainingGame.dartsPerVisit + visit.length;
      results.add(CheckoutAttempt(target: target, success: true, darts: darts));
      events.add(GameEvent(GameEventType.checkout, value: target));
      _afterAttempt();
    } else if (!dart.segment.isMiss) {
      events.add(GameEvent(GameEventType.hit, value: dart.score));
    }
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    // Nach einem Checkout wurde schon das nächste Ziel gesetzt.
    if (_justAdvanced) {
      _justAdvanced = false;
      return;
    }
    _visitsUsed++;
    if (_visitsUsed >= visitsPerAttempt) {
      results.add(CheckoutAttempt(target: target, success: false, darts: _visitsUsed * TrainingGame.dartsPerVisit));
      events.add(GameEvent(GameEventType.failed, value: target));
      _afterAttempt(closing: false);
    } else {
      _visitStartRemaining = remaining;
    }
  }

  bool _justAdvanced = false;

  void _afterAttempt({bool closing = true}) {
    if (results.length >= attempts) {
      finish();
      return;
    }
    _nextTarget();
    if (closing) {
      _justAdvanced = true;
      closeVisit();
    }
  }

  int get _dartsLeftInVisit => visitClosed ? TrainingGame.dartsPerVisit : TrainingGame.dartsPerVisit - visit.length;

  List<Segment>? get suggestion => showSuggestion
      ? CheckoutCalculator.suggest(remaining, darts: _dartsLeftInVisit, doubleOut: doubleOut)
      : null;

  int get successes => results.where((r) => r.success).length;

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
        progress: results.length / attempts,
        progressLabel: '${finished ? attempts : attemptNumber}/$attempts',
        stats: [
          GameStat('target', '$target'),
          GameStat('checkouts', '$successes/${results.length}'),
          GameStat('checkoutRate', formatPercent(results.isEmpty ? null : successes / results.length)),
        ],
      );

  @override
  GameResult get result {
    final ok = results.where((r) => r.success).toList();
    final rate = results.isEmpty ? 0.0 : ok.length / results.length;
    final avgDarts = ok.isEmpty ? null : ok.fold<int>(0, (s, r) => s + r.darts) / ok.length;
    return GameResult(
      metrics: {
        'attempts': results.length,
        'checkouts': ok.length,
        'checkoutRate': rate,
        'darts': dartsThrown,
        'avgDartsPerCheckout': ?avgDarts,
        if (ok.isNotEmpty) 'highestCheckout': ok.map((r) => r.target).reduce((a, b) => a > b ? a : b),
      },
      summary: [
        GameStat('checkouts', '${ok.length}/${results.length}'),
        GameStat('checkoutRate', formatPercent(results.isEmpty ? null : rate)),
        GameStat('avgDartsPerCheckout', formatDecimal(avgDarts)),
        GameStat('highestCheckout', ok.isEmpty ? '–' : '${ok.map((r) => r.target).reduce((a, b) => a > b ? a : b)}'),
      ],
      details: {'attempts': [for (final r in results) r.toJson()]},
    );
  }
}
