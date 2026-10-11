import '../../../board/domain/board_geometry.dart';
import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';

/// Reihenfolge der Zahlen.
enum NumberOrder { ascending, clockwise, random }

/// Welcher Ring zählt.
enum RingRule { any, single, double, triple }

/// Baut die Zielreihenfolge 1–20 (+ optional Bull, immer am Ende).
List<int> buildNumberOrder(NumberOrder order, {required bool includeBull, required List<int> Function(List<int>) shuffle}) {
  final numbers = switch (order) {
    NumberOrder.ascending => [for (var n = 1; n <= 20; n++) n],
    NumberOrder.clockwise => List<int>.of(BoardGeometry.numbers),
    NumberOrder.random => shuffle([for (var n = 1; n <= 20; n++) n]),
  };
  return [...numbers, if (includeBull) 25];
}

/// Around the Clock: alle Zahlen der Reihe nach treffen.
///
/// Regeln:
/// * Ein Treffer im erlaubten Ring ([ring]) bringt dich zur nächsten Zahl.
/// * Mit [multiplierAdvances] springt ein Double 2, ein Triple 3 Zahlen weiter.
/// * Bull (falls aktiv) kommt immer am Ende. Beim Ring "Double" zählt nur das
///   Bullseye, sonst beide Bull-Felder.
/// * Das Spiel endet, wenn alle Ziele erledigt sind.
class AroundTheClock extends TrainingGame {
  AroundTheClock({
    required super.seed,
    this.order = NumberOrder.ascending,
    this.includeBull = true,
    this.ring = RingRule.any,
    this.multiplierAdvances = false,
  });

  static const String id = 'around_the_clock';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'order': 'ascending', 'includeBull': true, 'ring': 'any', 'multiplierAdvances': false},
    options: const [
      ChoiceOption('order', ['ascending', 'clockwise', 'random']),
      ChoiceOption('ring', ['any', 'single', 'double', 'triple']),
      BoolOption('includeBull'),
      BoolOption('multiplierAdvances'),
    ],
    create: (c, seed) => AroundTheClock(
      seed: seed,
      order: NumberOrder.values.firstWhere((v) => v.name == c.stringOf('order', 'ascending'), orElse: () => NumberOrder.ascending),
      includeBull: c.boolOf('includeBull', true),
      ring: RingRule.values.firstWhere((v) => v.name == c.stringOf('ring', 'any'), orElse: () => RingRule.any),
      multiplierAdvances: c.boolOf('multiplierAdvances', false),
    ),
  );

  final NumberOrder order;
  final bool includeBull;
  final RingRule ring;
  final bool multiplierAdvances;

  late final List<int> sequence;
  int index = 0;
  int hits = 0;

  int get current => sequence[index.clamp(0, sequence.length - 1)];

  @override
  void onStart() {
    sequence = buildNumberOrder(order, includeBull: includeBull, shuffle: (l) => l..shuffle(random));
  }

  /// Zählt [s] als Treffer auf [number]?
  bool counts(Segment s, int number) {
    if (s.number != number) return false;
    if (number == 25) return ring == RingRule.double || ring == RingRule.triple ? s.bed == Bed.innerBull : true;
    return switch (ring) {
      RingRule.any => true,
      RingRule.single => s.isSingle,
      RingRule.double => s.isDouble,
      RingRule.triple => s.isTriple,
    };
  }

  @override
  void handleDart(DartThrow dart) {
    if (!counts(dart.segment, current)) return;
    hits++;
    final step = multiplierAdvances && current != 25 ? dart.segment.multiplier : 1;
    index += step;
    events.add(GameEvent(GameEventType.advanced, value: dart.segment.name));
    if (index >= sequence.length) {
      index = sequence.length;
      finish();
    }
  }

  Segment _targetSegment(int number) {
    if (number == 25) return ring == RingRule.double || ring == RingRule.triple ? Segment.bull : Segment.outerBull;
    return switch (ring) {
      RingRule.double => Segment.double(number),
      RingRule.triple => Segment.triple(number),
      _ => Segment.single(number),
    };
  }

  @override
  Set<Segment> get targets {
    if (finished) return const {};
    final n = current;
    if (n == 25) return ring == RingRule.double || ring == RingRule.triple ? {Segment.bull} : {Segment.bull, Segment.outerBull};
    return switch (ring) {
      RingRule.any => {Segment.single(n), Segment.single(n, inner: true), Segment.double(n), Segment.triple(n)},
      RingRule.single => {Segment.single(n), Segment.single(n, inner: true)},
      RingRule.double => {Segment.double(n)},
      RingRule.triple => {Segment.triple(n)},
    };
  }

  String _label(int n) {
    if (n == 25) return 'BULL';
    return switch (ring) {
      RingRule.any || RingRule.single => '$n',
      _ => _targetSegment(n).name,
    };
  }

  double? get hitRate => dartsThrown == 0 ? null : hits / dartsThrown;

  @override
  GameDisplay get display => GameDisplay(
        headline: finished ? '✓' : _label(current),
        headlineKey: 'target',
        progress: index / sequence.length,
        progressLabel: '$index/${sequence.length}',
        stats: [
          GameStat('darts', '$dartsThrown'),
          GameStat('hitRate', formatPercent(hitRate)),
          if (!finished && index + 1 < sequence.length) GameStat('next', _label(sequence[index + 1])),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'darts': dartsThrown,
          'hits': hits,
          'hitRate': hitRate ?? 0,
          'completed': finished ? 1 : 0,
          'progress': index / sequence.length,
        },
        summary: [
          GameStat('darts', '$dartsThrown'),
          GameStat('hitRate', formatPercent(hitRate)),
          GameStat('progress', '$index/${sequence.length}'),
        ],
      );
}
