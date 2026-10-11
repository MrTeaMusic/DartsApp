import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';
import 'jdc_challenge.dart';

/// Shanghai: Zahlen von [from] bis [to], eine Aufnahme pro Zahl.
///
/// Regeln:
/// * Treffer auf die aktuelle Zahl zählen Zahl × Multiplikator.
/// * Single, Double und Triple der Zahl in einer Aufnahme = Shanghai. Mit
///   [shanghaiWins] endet das Spiel sofort, sonst gibt es [shanghaiBonus].
/// * Optional Bull am Ende (25 = 25, Bullseye = 50, kein Shanghai).
class Shanghai extends TrainingGame {
  Shanghai({
    required super.seed,
    this.from = 1,
    this.to = 7,
    this.includeBull = false,
    this.shanghaiWins = true,
    this.shanghaiBonus = 100,
  });

  static const String id = 'shanghai';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'from': 1, 'to': 7, 'includeBull': false, 'shanghaiWins': true, 'shanghaiBonus': 100},
    options: const [
      IntOption('from', min: 1, max: 20),
      IntOption('to', min: 1, max: 20),
      BoolOption('includeBull'),
      BoolOption('shanghaiWins'),
      IntOption('shanghaiBonus', min: 0, max: 200, step: 50),
    ],
    normalize: (c) {
      final a = c.intOf('from', 1).clamp(1, 20);
      final b = c.intOf('to', 7).clamp(1, 20);
      return {...c, 'from': a < b ? a : b, 'to': a < b ? b : a};
    },
    create: (c, seed) => Shanghai(
      seed: seed,
      from: c.intOf('from', 1),
      to: c.intOf('to', 7),
      includeBull: c.boolOf('includeBull', false),
      shanghaiWins: c.boolOf('shanghaiWins', true),
      shanghaiBonus: c.intOf('shanghaiBonus', 100),
    ),
  );

  final int from;
  final int to;
  final bool includeBull;
  final bool shanghaiWins;
  final int shanghaiBonus;

  late final List<int> sequence = [for (var n = from; n <= to; n++) n, if (includeBull) 25];
  int index = 0;
  int score = 0;
  int hits = 0;
  int triples = 0;
  int shanghais = 0;
  bool wonByShanghai = false;
  final ShanghaiTracker _tracker = ShanghaiTracker();

  int get current => sequence[index.clamp(0, sequence.length - 1)];

  @override
  void onVisitStart() => _tracker.reset();

  @override
  void handleDart(DartThrow dart) {
    final s = dart.segment;
    if (s.number != current) return;
    hits++;
    if (s.isTriple) triples++;
    score += s.score;
    events.add(GameEvent(GameEventType.hit, value: s.name));
    if (current != 25 && _tracker.add(s)) {
      shanghais++;
      events.add(GameEvent(GameEventType.shanghai, value: current));
      if (shanghaiWins) {
        wonByShanghai = true;
        finish();
      } else {
        score += shanghaiBonus;
      }
    }
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    _tracker.reset();
    index++;
    if (index >= sequence.length) finish();
  }

  bool get completed => wonByShanghai || index >= sequence.length;

  @override
  Set<Segment> get targets {
    if (finished) return const {};
    final n = current;
    if (n == 25) return {Segment.outerBull, Segment.bull};
    return {Segment.single(n), Segment.single(n, inner: true), Segment.double(n), Segment.triple(n)};
  }

  @override
  GameDisplay get display => GameDisplay(
        headline: '$score',
        headlineKey: 'points',
        progress: completed ? 1 : index / sequence.length,
        progressLabel: '${(index + 1).clamp(1, sequence.length)}/${sequence.length}',
        stats: [
          GameStat('target', finished ? '–' : (current == 25 ? 'BULL' : '$current')),
          GameStat('shanghais', '$shanghais'),
          GameStat('hitRate', formatPercent(dartsThrown == 0 ? null : hits / dartsThrown)),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'score': score,
          'shanghais': shanghais,
          'hits': hits,
          'hitRate': dartsThrown == 0 ? 0 : hits / dartsThrown,
          'triples': triples,
          'darts': dartsThrown,
          'completed': completed ? 1 : 0,
        },
        summary: [
          GameStat('points', '$score'),
          GameStat('shanghais', '$shanghais'),
          GameStat('hitRate', formatPercent(dartsThrown == 0 ? null : hits / dartsThrown)),
          GameStat('triples', '$triples'),
        ],
      );
}
