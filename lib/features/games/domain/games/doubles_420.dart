import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';

/// Reihenfolge der Doubles.
enum DoubleOrder { ascending, descending, random }

/// 420: Doppel-Countdown von der Summe aller Ziel-Doubles.
///
/// Regeln:
/// * Start bei 420 (D1–D20), mit Bull 470. Eine Aufnahme pro Double.
/// * Jeder Treffer auf das aktuelle Double zieht seinen Wert ab. Kein Bust,
///   der Stand darf negativ werden. Niedriger ist besser.
class Doubles420 extends TrainingGame {
  Doubles420({required super.seed, this.includeBull = false, this.order = DoubleOrder.ascending});

  static const String id = 'doubles_420';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'includeBull': false, 'order': 'ascending'},
    options: const [
      BoolOption('includeBull'),
      ChoiceOption('order', ['ascending', 'descending', 'random']),
    ],
    create: (c, seed) => Doubles420(
      seed: seed,
      includeBull: c.boolOf('includeBull', false),
      order: DoubleOrder.values.firstWhere((v) => v.name == c.stringOf('order', 'ascending'), orElse: () => DoubleOrder.ascending),
    ),
  );

  final bool includeBull;
  final DoubleOrder order;

  late final List<int> sequence;
  late int score = includeBull ? 470 : 420;
  int index = 0;
  int hits = 0;
  int missedDoubles = 0;
  int _visitHits = 0;
  final Map<int, int> hitsByNumber = {};

  @override
  void onStart() {
    final numbers = [for (var n = 1; n <= 20; n++) n];
    sequence = [
      ...switch (order) {
        DoubleOrder.ascending => numbers,
        DoubleOrder.descending => numbers.reversed,
        DoubleOrder.random => numbers..shuffle(random),
      },
      if (includeBull) 25,
    ];
  }

  int get current => sequence[index.clamp(0, sequence.length - 1)];
  Segment get currentSegment => current == 25 ? Segment.bull : Segment.double(current);

  @override
  void onVisitStart() => _visitHits = 0;

  @override
  void handleDart(DartThrow dart) {
    if (dart.segment != currentSegment) return;
    hits++;
    _visitHits++;
    score -= dart.score;
    hitsByNumber[current] = (hitsByNumber[current] ?? 0) + 1;
    events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    if (_visitHits == 0) {
      missedDoubles++;
      events.add(GameEvent(GameEventType.failed, value: currentSegment.name));
    }
    _visitHits = 0;
    index++;
    if (index >= sequence.length) finish();
  }

  double? get doubleRate => dartsThrown == 0 ? null : hits / dartsThrown;

  @override
  Set<Segment> get targets => finished ? const {} : {currentSegment};

  @override
  GameDisplay get display => GameDisplay(
        headline: '$score',
        headlineKey: 'remaining',
        progress: index / sequence.length,
        progressLabel: '${finished ? sequence.length : index + 1}/${sequence.length}',
        stats: [
          GameStat('target', finished ? '–' : currentSegment.name),
          GameStat('doubleHits', '$hits'),
          GameStat('doubleRate', formatPercent(doubleRate)),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'score': score,
          'doubleHits': hits,
          'doubleRate': doubleRate ?? 0,
          'missedDoubles': missedDoubles,
          'darts': dartsThrown,
          'completed': index >= sequence.length ? 1 : 0,
        },
        summary: [
          GameStat('remaining', '$score'),
          GameStat('doubleHits', '$hits'),
          GameStat('doubleRate', formatPercent(doubleRate)),
          GameStat('missedDoubles', '$missedDoubles'),
        ],
        details: {'hitsByNumber': {for (final e in hitsByNumber.entries) '${e.key}': e.value}},
      );
}
