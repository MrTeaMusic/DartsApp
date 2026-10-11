import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';

/// Art eines Runden-Ziels.
enum RoundTargetKind { number, anyDouble, anyTriple, bull, bullseye }

/// Ein Ziel einer Runde, z. B. „14“, „beliebiges Double“ oder „Bull“.
class RoundTarget {
  const RoundTarget.number(this.number) : kind = RoundTargetKind.number;
  const RoundTarget._(this.kind) : number = 0;

  static const RoundTarget anyDouble = RoundTarget._(RoundTargetKind.anyDouble);
  static const RoundTarget anyTriple = RoundTarget._(RoundTargetKind.anyTriple);
  static const RoundTarget bull = RoundTarget._(RoundTargetKind.bull);
  static const RoundTarget bullseye = RoundTarget._(RoundTargetKind.bullseye);

  final RoundTargetKind kind;
  final int number;

  bool matches(Segment s) => switch (kind) {
        RoundTargetKind.number => s.number == number,
        RoundTargetKind.anyDouble => s.isDouble,
        RoundTargetKind.anyTriple => s.isTriple,
        RoundTargetKind.bull => s.isBull,
        RoundTargetKind.bullseye => s.bed == Bed.innerBull,
      };

  /// Felder für die Hervorhebung auf dem Board.
  Set<Segment> get segments => switch (kind) {
        RoundTargetKind.number => {
            Segment.single(number),
            Segment.single(number, inner: true),
            Segment.double(number),
            Segment.triple(number),
          },
        RoundTargetKind.anyDouble => {for (var n = 1; n <= 20; n++) Segment.double(n), Segment.bull},
        RoundTargetKind.anyTriple => {for (var n = 1; n <= 20; n++) Segment.triple(n)},
        RoundTargetKind.bull => {Segment.outerBull, Segment.bull},
        RoundTargetKind.bullseye => {Segment.bull},
      };

  /// Stabiler Kurzname, z. B. "14", "D", "T", "25", "BULL".
  String get label => switch (kind) {
        RoundTargetKind.number => '$number',
        RoundTargetKind.anyDouble => 'D',
        RoundTargetKind.anyTriple => 'T',
        RoundTargetKind.bull => '25',
        RoundTargetKind.bullseye => 'BULL',
      };
}

/// Halve-It / Bermuda-Dreieck: feste Ziel-Folge, eine Aufnahme pro Runde.
///
/// Regeln:
/// * Jeder Dart aufs Runden-Ziel zählt seinen normalen Wert.
/// * Trifft keiner der Darts der Aufnahme, wird der Stand halbiert
///   (ungerade Stände nach [roundUp]).
/// * Ende nach der letzten Runde.
class HalveIt extends TrainingGame {
  HalveIt({required super.seed, this.preset = 'bermuda', this.roundUp = false, this.startScore = 0});

  static const String id = 'halve_it';

  static const Map<String, List<RoundTarget>> presets = {
    'bermuda': [
      RoundTarget.number(12),
      RoundTarget.number(13),
      RoundTarget.number(14),
      RoundTarget.anyDouble,
      RoundTarget.number(15),
      RoundTarget.number(16),
      RoundTarget.number(17),
      RoundTarget.anyTriple,
      RoundTarget.number(18),
      RoundTarget.number(19),
      RoundTarget.number(20),
      RoundTarget.bull,
      RoundTarget.bullseye,
    ],
    'short': [
      RoundTarget.number(20),
      RoundTarget.number(19),
      RoundTarget.anyDouble,
      RoundTarget.number(18),
      RoundTarget.number(17),
      RoundTarget.anyTriple,
      RoundTarget.number(16),
      RoundTarget.number(15),
      RoundTarget.bull,
    ],
  };

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'preset': 'bermuda', 'rounding': 'down', 'startScore': 0},
    options: const [
      ChoiceOption('preset', ['bermuda', 'short']),
      ChoiceOption('rounding', ['down', 'up']),
      IntOption('startScore', min: 0, max: 100, step: 10),
    ],
    create: (c, seed) => HalveIt(
      seed: seed,
      preset: c.stringOf('preset', 'bermuda'),
      roundUp: c.stringOf('rounding', 'down') == 'up',
      startScore: c.intOf('startScore', 0),
    ),
  );

  final String preset;
  final bool roundUp;
  final int startScore;

  late final List<RoundTarget> sequence = presets[preset] ?? presets['bermuda']!;
  late int score = startScore;
  int index = 0;
  int hits = 0;
  int halvings = 0;
  int _roundPoints = 0;
  int _roundHits = 0;
  final List<({String target, int points, bool halved})> rounds = [];

  RoundTarget get current => sequence[index.clamp(0, sequence.length - 1)];

  @override
  void onVisitStart() {
    _roundPoints = 0;
    _roundHits = 0;
  }

  @override
  void handleDart(DartThrow dart) {
    if (!current.matches(dart.segment)) return;
    hits++;
    _roundHits++;
    _roundPoints += dart.score;
    score += dart.score;
    events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    final halved = _roundHits == 0;
    if (halved) {
      score = roundUp ? (score + 1) ~/ 2 : score ~/ 2;
      halvings++;
      events.add(GameEvent(GameEventType.halved, value: score));
    }
    rounds.add((target: current.label, points: _roundPoints, halved: halved));
    _roundPoints = 0;
    _roundHits = 0;
    index++;
    if (index >= sequence.length) finish();
  }

  int get _bestRound => rounds.fold(0, (m, r) => r.points > m ? r.points : m);
  int get _cleanRounds => rounds.where((r) => !r.halved).length;

  @override
  Set<Segment> get targets => finished ? const {} : current.segments;

  @override
  GameDisplay get display => GameDisplay(
        headline: '$score',
        headlineKey: 'points',
        progress: index / sequence.length,
        progressLabel: '${finished ? sequence.length : index + 1}/${sequence.length}',
        stats: [
          GameStat('target', finished ? '–' : current.label),
          GameStat('halvings', '$halvings'),
          GameStat('hitRate', formatPercent(dartsThrown == 0 ? null : hits / dartsThrown)),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'score': score,
          'halvings': halvings,
          'hits': hits,
          'hitRate': dartsThrown == 0 ? 0 : hits / dartsThrown,
          'bestRound': _bestRound,
          'cleanRounds': _cleanRounds,
          'darts': dartsThrown,
          'completed': index >= sequence.length ? 1 : 0,
        },
        summary: [
          GameStat('points', '$score'),
          GameStat('halvings', '$halvings'),
          GameStat('hitRate', formatPercent(dartsThrown == 0 ? null : hits / dartsThrown)),
          GameStat('bestRound', '$_bestRound'),
          GameStat('cleanRounds', '$_cleanRounds/${rounds.length}'),
        ],
        details: {
          'rounds': [for (final r in rounds) {'target': r.target, 'points': r.points, 'halved': r.halved}],
        },
      );
}
