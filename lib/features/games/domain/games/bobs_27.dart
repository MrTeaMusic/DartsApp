import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';

/// Bob's 27: Doppel-Training von D1 bis D20 (optional Bull).
///
/// Regeln:
/// * Start mit [startScore] Punkten (Standard 27).
/// * Eine Aufnahme pro Double, der Reihe nach D1, D2, … D20, dann Bull.
/// * Jeder Treffer auf das Double bringt dessen Wert (D7 = 14, Bull = 50).
/// * Kein Treffer in der Aufnahme: der Wert eines Doubles wird abgezogen.
/// * Fällt der Stand unter 0, ist das Spiel vorbei, außer
///   [allowNegative] ist an.
class Bobs27 extends TrainingGame {
  Bobs27({required super.seed, this.startScore = 27, this.includeBull = true, this.allowNegative = false});

  static const String id = 'bobs_27';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'startScore': 27, 'includeBull': true, 'allowNegative': false},
    options: const [
      IntOption('startScore', min: 0, max: 100),
      BoolOption('includeBull'),
      BoolOption('allowNegative'),
    ],
    create: (c, seed) => Bobs27(
      seed: seed,
      startScore: c.intOf('startScore', 27),
      includeBull: c.boolOf('includeBull', true),
      allowNegative: c.boolOf('allowNegative', false),
    ),
  );

  final int startScore;
  final bool includeBull;
  final bool allowNegative;

  late final List<int> sequence = [for (var n = 1; n <= 20; n++) n, if (includeBull) 25];
  late int score = startScore;
  int index = 0;
  int hits = 0;
  int _visitHits = 0;
  int bestScore = 0;

  /// Treffer pro Double, für Statistik und Heatmap.
  final Map<int, int> hitsByNumber = {};

  int get current => sequence[index.clamp(0, sequence.length - 1)];
  Segment get currentSegment => current == 25 ? Segment.bull : Segment.double(current);
  int get _value => current == 25 ? 50 : current * 2;

  @override
  void onStart() => bestScore = startScore;

  @override
  void onVisitStart() => _visitHits = 0;

  @override
  void handleDart(DartThrow dart) {
    if (dart.segment != currentSegment) return;
    _visitHits++;
    hits++;
    hitsByNumber[current] = (hitsByNumber[current] ?? 0) + 1;
    score += _value;
    events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    if (_visitHits == 0) {
      score -= _value;
      events.add(GameEvent(GameEventType.failed, value: currentSegment.name));
    }
    _visitHits = 0;
    if (score > bestScore) bestScore = score;
    index++;
    if (score < 0 && !allowNegative) {
      finish();
    } else if (index >= sequence.length) {
      finish();
    }
  }

  bool get survived => index >= sequence.length && (allowNegative || score >= 0);

  @override
  Set<Segment> get targets => finished ? const {} : {currentSegment};

  @override
  GameDisplay get display => GameDisplay(
        headline: '$score',
        headlineKey: 'points',
        progress: index / sequence.length,
        progressLabel: '${finished ? sequence.length : index + 1}/${sequence.length}',
        stats: [
          GameStat('target', finished ? '–' : currentSegment.name),
          GameStat('doubleHits', '$hits'),
          GameStat('doubleRate', formatPercent(dartsThrown == 0 ? null : hits / dartsThrown)),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'score': score,
          'hits': hits,
          'hitRate': dartsThrown == 0 ? 0 : hits / dartsThrown,
          'darts': dartsThrown,
          'reached': index,
          'bestScore': bestScore,
          'completed': survived ? 1 : 0,
        },
        summary: [
          GameStat('points', '$score'),
          GameStat('doubleHits', '$hits'),
          GameStat('doubleRate', formatPercent(dartsThrown == 0 ? null : hits / dartsThrown)),
          GameStat('progress', '$index/${sequence.length}'),
        ],
        details: {'hitsByNumber': {for (final e in hitsByNumber.entries) '${e.key}': e.value}},
      );
}
