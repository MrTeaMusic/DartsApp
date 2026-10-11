import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';

/// Doppel-Leiter („Doubles Snakes and Ladders“).
///
/// Regeln:
/// * Stufen D1 … D20, optional Bullseye. Eine Aufnahme pro Versuch.
/// * `pro`: 3 Treffer = hoch, 2 = bleiben, 1 = eine runter, 0 = zwei runter.
///   `normal`: ≥ 2 Treffer = hoch, 1 = bleiben, 0 = eine runter. Nie unter D1.
/// * Fertig beim Aufstieg über die letzte Stufe oder nach [maxVisits].
class DoublesLadder extends TrainingGame {
  DoublesLadder({required super.seed, this.pro = false, this.includeBull = true, this.maxVisits = 100});

  static const String id = 'doubles_ladder';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'difficulty': 'normal', 'includeBull': true, 'maxVisits': 100},
    options: const [
      ChoiceOption('difficulty', ['normal', 'pro']),
      BoolOption('includeBull'),
      IntOption('maxVisits', min: 10, max: 300, step: 10),
    ],
    create: (c, seed) => DoublesLadder(
      seed: seed,
      pro: c.stringOf('difficulty', 'normal') == 'pro',
      includeBull: c.boolOf('includeBull', true),
      maxVisits: c.intOf('maxVisits', 100),
    ),
  );

  final bool pro;
  final bool includeBull;
  final int maxVisits;

  late final List<int> levels = [for (var n = 1; n <= 20; n++) n, if (includeBull) 25];
  int level = 0;
  int highest = 0;
  int visits = 0;
  int hits = 0;
  int _visitHits = 0;

  int get current => levels[level.clamp(0, levels.length - 1)];
  Segment get currentSegment => _segmentOf(current);
  static Segment _segmentOf(int n) => n == 25 ? Segment.bull : Segment.double(n);
  bool get completed => level >= levels.length;

  @override
  void onVisitStart() => _visitHits = 0;

  @override
  void handleDart(DartThrow dart) {
    if (dart.segment != currentSegment) return;
    hits++;
    _visitHits++;
    events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    visits++;
    final step = pro
        ? switch (_visitHits) { 3 => 1, 2 => 0, 1 => -1, _ => -2 }
        : switch (_visitHits) { >= 2 => 1, 1 => 0, _ => -1 };
    _visitHits = 0;
    final next = (level + step).clamp(0, levels.length);
    if (next > level) {
      events.add(const GameEvent(GameEventType.advanced));
    } else if (next < level) {
      events.add(GameEvent(GameEventType.levelDown, value: _segmentOf(levels[next]).name));
    }
    level = next;
    if (level > highest) highest = level;
    if (completed || visits >= maxVisits) finish();
  }

  /// Höchste erreichte Stufe, 1-basiert (D1 = 1, Bullseye = 21).
  int get highestLevel => (highest + 1).clamp(1, levels.length);

  @override
  Set<Segment> get targets => finished ? const {} : {currentSegment};

  @override
  GameDisplay get display => GameDisplay(
        headline: completed ? '✓' : currentSegment.name,
        headlineKey: 'target',
        progress: level / levels.length,
        progressLabel: '$visits/$maxVisits',
        stats: [
          GameStat('level', '${(level + 1).clamp(1, levels.length)}/${levels.length}'),
          GameStat('highestLevel', _segmentOf(levels[highestLevel - 1]).name),
          GameStat('doubleRate', formatPercent(dartsThrown == 0 ? null : hits / dartsThrown)),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'visits': visits,
          'highestLevel': highestLevel,
          'doubleRate': dartsThrown == 0 ? 0 : hits / dartsThrown,
          'darts': dartsThrown,
          'completed': completed ? 1 : 0,
        },
        summary: [
          GameStat('visits', '$visits'),
          GameStat('highestLevel', '$highestLevel/${levels.length}'),
          GameStat('doubleRate', formatPercent(dartsThrown == 0 ? null : hits / dartsThrown)),
        ],
      );
}
