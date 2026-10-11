import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';
import 'around_the_clock.dart';

/// Drei im Bett: eine Zahl ist geschafft, wenn alle drei Darts einer
/// Aufnahme auf ihr landen.
///
/// Regeln:
/// * `wedge`: Single, Double, Triple der Zahl beliebig gemischt (Bull: 25
///   und Bullseye gemischt). `segment`: alle drei im selben Feld.
/// * Aufnahmen mit weniger als 3 Darts zählen als Fehlversuch. Treffer
///   sammeln sich nicht über mehrere Aufnahmen.
/// * Ende nach der letzten Zahl oder nach [maxVisits] (0 = unbegrenzt).
class ThreeInABed extends TrainingGame {
  ThreeInABed({
    required super.seed,
    this.strict = false,
    this.order = NumberOrder.ascending,
    this.includeBull = false,
    this.maxVisits = 0,
  });

  static const String id = 'three_in_a_bed';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'mode': 'wedge', 'order': 'ascending', 'includeBull': false, 'maxVisits': 0},
    options: const [
      ChoiceOption('mode', ['wedge', 'segment']),
      ChoiceOption('order', ['ascending', 'clockwise', 'random']),
      BoolOption('includeBull'),
      IntOption('maxVisits', min: 0, max: 300, step: 10),
    ],
    create: (c, seed) => ThreeInABed(
      seed: seed,
      strict: c.stringOf('mode', 'wedge') == 'segment',
      order: NumberOrder.values.firstWhere((v) => v.name == c.stringOf('order', 'ascending'), orElse: () => NumberOrder.ascending),
      includeBull: c.boolOf('includeBull', false),
      maxVisits: c.intOf('maxVisits', 0),
    ),
  );

  /// `segment`-Modus: alle drei im selben Feld.
  final bool strict;
  final NumberOrder order;
  final bool includeBull;
  final int maxVisits;

  late final List<int> sequence;
  int index = 0;
  int visits = 0;

  int get current => sequence[index.clamp(0, sequence.length - 1)];
  bool get completed => index >= sequence.length;

  @override
  void onStart() {
    sequence = buildNumberOrder(order, includeBull: includeBull, shuffle: (l) => l..shuffle(random));
  }

  /// Sind [darts] ein „Bett“ auf [number]?
  bool isBed(List<DartThrow> darts, int number) {
    if (darts.length < TrainingGame.dartsPerVisit) return false;
    final first = darts.first.segment;
    if (first.number != number) return false;
    return darts.every((d) => strict ? d.segment.sameField(first) : d.segment.number == number);
  }

  @override
  void handleDart(DartThrow dart) {
    if (dart.segment.number == current) events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    visits++;
    if (isBed(visitDarts, current)) {
      index++;
      events.add(const GameEvent(GameEventType.advanced));
    } else {
      events.add(const GameEvent(GameEventType.failed));
    }
    if (completed || (maxVisits > 0 && visits >= maxVisits)) finish();
  }

  @override
  Set<Segment> get targets {
    if (finished) return const {};
    final n = current;
    if (n == 25) return {Segment.outerBull, Segment.bull};
    return {Segment.single(n), Segment.single(n, inner: true), Segment.double(n), Segment.triple(n)};
  }

  String get _label => current == 25 ? 'BULL' : '$current';

  @override
  GameDisplay get display => GameDisplay(
        headline: completed ? '✓' : _label,
        headlineKey: 'target',
        progress: index / sequence.length,
        progressLabel: '${(index + (finished ? 0 : 1)).clamp(1, sequence.length)}/${sequence.length}',
        stats: [
          GameStat('visits', maxVisits > 0 ? '$visits/$maxVisits' : '$visits'),
          GameStat('successRate', formatPercent(visits == 0 ? null : index / visits)),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'visits': visits,
          'reached': index,
          'successRate': visits == 0 ? 0 : index / visits,
          'darts': dartsThrown,
          'completed': completed ? 1 : 0,
        },
        summary: [
          GameStat('visits', '$visits'),
          GameStat('progress', '$index/${sequence.length}'),
          GameStat('successRate', formatPercent(visits == 0 ? null : index / visits)),
        ],
      );
}
