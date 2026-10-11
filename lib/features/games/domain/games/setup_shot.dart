import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';
import 'checkout/checkout_rules.dart';

/// Eine Aufgabe beim Stellen.
class SetupTask {
  const SetupTask({required this.rest, required this.dart, required this.leave, required this.success});
  final int rest;
  final String dart;
  final int leave;
  final bool success;

  Map<String, Object?> toJson() => {'rest': rest, 'dart': dart, 'leave': leave, 'success': success};
}

/// Stellen (Setup-Dart): mit einem Dart den Rest auf ein Lieblings-Double
/// stellen.
///
/// Regeln:
/// * Jeder gezählte Dart ist eine Aufgabe mit einem Rest R aus [min]–[max].
/// * Erfolg, wenn R − Dartwert in der Rest-Liste liegt; der erste Eintrag
///   ist das Ideal.
/// * Gestellt werden nur Reste, die mit einem Dart auf einen Listenwert
///   gestellt werden können und nicht selbst mit einem Dart checkbar sind.
/// * Ende nach [taskCount] gezählten Darts.
class SetupShot extends TrainingGame {
  SetupShot({
    required super.seed,
    this.min = 41,
    this.max = 100,
    this.leavesKey = 'good',
    this.taskCount = 30,
    this.showSuggestion = true,
    this.fixedRests = const [],
  });

  static const String id = 'setup_shot';

  static final Map<String, List<int>> leaveLists = {
    'classic': const [40, 32, 16],
    'good': const [40, 32, 36, 24, 16, 20, 8],
    'anyDouble': [for (var v = 2; v <= 40; v += 2) v, 50],
  };

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'min': 41, 'max': 100, 'leaves': 'good', 'darts': 30, 'showSuggestion': true},
    options: const [
      IntOption('min', min: 41, max: 170),
      IntOption('max', min: 41, max: 170),
      ChoiceOption('leaves', ['classic', 'good', 'anyDouble']),
      IntOption('darts', min: 3, max: 90, step: 3),
      BoolOption('showSuggestion'),
    ],
    normalize: (c) {
      final a = c.intOf('min', 41).clamp(41, 170);
      final b = c.intOf('max', 100).clamp(41, 170);
      return {...c, 'min': a < b ? a : b, 'max': a < b ? b : a};
    },
    create: (c, seed) => SetupShot(
      seed: seed,
      min: c.intOf('min', 41),
      max: c.intOf('max', 100),
      leavesKey: c.stringOf('leaves', 'good'),
      taskCount: c.intOf('darts', 30),
      showSuggestion: c.boolOf('showSuggestion', true),
    ),
  );

  final int min;
  final int max;
  final String leavesKey;

  /// Anzahl Aufgaben (gezählte Darts).
  final int taskCount;
  final bool showSuggestion;

  /// Feste Reste für Tests, danach geht es zufällig weiter.
  final List<int> fixedRests;

  late final List<int> leaves = leaveLists[leavesKey] ?? leaveLists['good']!;
  late final List<int> pool;
  final List<SetupTask> tasks = [];
  int rest = 0;

  /// Alle Felder, sortiert nach Vorliebe beim Stellen: Single, Triple,
  /// Double, 25, Bullseye.
  static final List<Segment> _setupSegments = [
    for (var n = 20; n >= 1; n--) Segment.single(n),
    for (var n = 20; n >= 1; n--) Segment.triple(n),
    for (var n = 20; n >= 1; n--) Segment.double(n),
    Segment.outerBull,
    Segment.bull,
  ];

  /// Kann [r] mit einem Dart auf einen Listenwert gestellt werden und ist
  /// selbst nicht mit einem Dart checkbar?
  bool isValidRest(int r) =>
      !CheckoutRules.isCheckout(r, darts: 1, out: OutMode.double) && bestSetup(r) != null;

  /// Der Dart, der [r] auf den bestmöglichen Listenwert bringt, bevorzugt
  /// Single. `null`, wenn keiner passt.
  Segment? bestSetup(int r) {
    for (final leave in leaves) {
      for (final s in _setupSegments) {
        if (r - s.score == leave) return s;
      }
    }
    return null;
  }

  @override
  void onStart() {
    pool = [for (var r = min; r <= max; r++) if (isValidRest(r)) r];
    if (pool.isEmpty) pool.add(57);
    _nextRest();
  }

  void _nextRest() {
    final i = tasks.length;
    if (i < fixedRests.length) {
      rest = fixedRests[i];
      return;
    }
    if (pool.length == 1) {
      rest = pool.first;
      return;
    }
    final previous = rest;
    while (true) {
      final v = pool[random.nextInt(pool.length)];
      if (v != previous) {
        rest = v;
        return;
      }
    }
  }

  @override
  void handleDart(DartThrow dart) {
    final leave = rest - dart.score;
    final success = leaves.contains(leave);
    tasks.add(SetupTask(rest: rest, dart: dart.segment.name, leave: leave, success: success));
    if (leave == leaves.first) {
      events.add(GameEvent(GameEventType.best, value: leave));
    } else if (success) {
      events.add(GameEvent(GameEventType.hit, value: leave));
    } else {
      events.add(GameEvent(GameEventType.failed, value: leave));
    }
    if (tasks.length >= taskCount) {
      finish();
      return;
    }
    _nextRest();
  }

  int get successes => tasks.where((t) => t.success).length;
  int get ideal => tasks.where((t) => t.leave == leaves.first).length;

  List<Segment>? get suggestion {
    if (!showSuggestion || finished) return null;
    final s = bestSetup(rest);
    return s == null ? null : [s];
  }

  @override
  Set<Segment> get targets => suggestion?.toSet() ?? const {};

  @override
  GameDisplay get display => GameDisplay(
        headline: '$rest',
        headlineKey: 'remaining',
        suggestion: suggestion,
        progress: tasks.length / taskCount,
        progressLabel: '${(tasks.length + (finished ? 0 : 1)).clamp(1, taskCount)}/$taskCount',
        stats: [
          GameStat('successes', '$successes/${tasks.length}'),
          GameStat('ideal', '$ideal'),
          GameStat('successRate', formatPercent(tasks.isEmpty ? null : successes / tasks.length)),
        ],
      );

  @override
  GameResult get result {
    final n = tasks.length;
    return GameResult(
      metrics: {
        'successes': successes,
        'successRate': n == 0 ? 0 : successes / n,
        'ideal': ideal,
        'idealRate': n == 0 ? 0 : ideal / n,
        'darts': dartsThrown,
        'completed': n >= taskCount ? 1 : 0,
      },
      summary: [
        GameStat('successes', '$successes/$n'),
        GameStat('successRate', formatPercent(n == 0 ? null : successes / n)),
        GameStat('ideal', '$ideal'),
        GameStat('idealRate', formatPercent(n == 0 ? null : ideal / n)),
      ],
      details: {'tasks': [for (final t in tasks) t.toJson()]},
    );
  }
}
