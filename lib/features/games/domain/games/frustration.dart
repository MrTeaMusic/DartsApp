import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';
import 'checkout/checkout_rules.dart';

/// Frustration (80 + Double): erst scoren, dann das Double unter Druck.
///
/// Regeln:
/// * Ziele D1 … D20, dann Bullseye (`full`) oder D20 abwärts bis D10
///   (`short`).
/// * Dart 1 + 2 müssen zusammen mindestens [setupMin] ergeben, sonst ist
///   die Aufnahme nach Dart 2 vorbei.
/// * Geschafft: Dart 3 muss das aktuelle Double treffen → nächstes Ziel.
/// * Jede Aufnahme ist ein Versuch. Ende nach dem letzten Ziel oder nach
///   [maxVisits] Aufnahmen (0 = unbegrenzt).
class Frustration extends TrainingGame {
  Frustration({required super.seed, this.short = false, this.setupMin = 80, this.maxVisits = 0});

  static const String id = 'frustration';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'sequence': 'full', 'setupMin': 80, 'maxVisits': 0},
    options: const [
      ChoiceOption('sequence', ['full', 'short']),
      IntOption('setupMin', min: 40, max: 120, step: 10),
      IntOption('maxVisits', min: 0, max: 200, step: 10),
    ],
    create: (c, seed) => Frustration(
      seed: seed,
      short: c.stringOf('sequence', 'full') == 'short',
      setupMin: c.intOf('setupMin', 80),
      maxVisits: c.intOf('maxVisits', 0),
    ),
  );

  final bool short;
  final int setupMin;
  final int maxVisits;

  late final List<int> sequence = short
      ? [for (var n = 20; n >= 10; n--) n]
      : [for (var n = 1; n <= 20; n++) n, 25];

  int index = 0;
  int visits = 0;
  int setups = 0;
  int doubleDarts = 0;
  int doubleHits = 0;

  int get current => sequence[index.clamp(0, sequence.length - 1)];
  Segment get currentSegment => current == 25 ? Segment.bull : Segment.double(current);
  int get _setupScore => visit.take(2).fold(0, (s, d) => s + d.score);

  /// Ist die laufende Aufnahme in der Double-Phase (Dart 3)?
  bool get inDoublePhase => !finished && !visitClosed && visit.length == 2 && _setupScore >= setupMin;

  @override
  void handleDart(DartThrow dart) {
    if (visit.length == 1) visits++;
    if (visit.length == 2) {
      if (_setupScore >= setupMin) {
        setups++;
        events.add(GameEvent(GameEventType.visitSuccess, value: _setupScore));
      } else {
        events.add(GameEvent(GameEventType.visitMissed, value: _setupScore));
        closeVisit();
      }
      return;
    }
    if (visit.length == 3) {
      doubleDarts++;
      if (dart.segment == currentSegment) {
        doubleHits++;
        events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
        index++;
        if (index >= sequence.length) {
          finish();
          return;
        }
        events.add(const GameEvent(GameEventType.advanced));
      }
    }
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    if (maxVisits > 0 && visits >= maxVisits) finish();
  }

  bool get completed => index >= sequence.length;

  /// Im Double-Phase-Dart der Weg für den Rest (das aktuelle Double).
  List<Segment>? get suggestion =>
      inDoublePhase ? CheckoutRules.suggest(current == 25 ? 50 : current * 2, darts: 1, out: OutMode.double) : null;

  @override
  Set<Segment> get targets {
    if (finished) return const {};
    return inDoublePhase ? {currentSegment} : {Segment.triple(20)};
  }

  @override
  GameDisplay get display => GameDisplay(
        headline: finished ? '$visits' : currentSegment.name,
        headlineKey: finished ? 'visits' : 'target',
        suggestion: suggestion,
        progress: index / sequence.length,
        progressLabel: '${(index + (finished ? 0 : 1)).clamp(1, sequence.length)}/${sequence.length}',
        stats: [
          GameStat('visits', maxVisits > 0 ? '$visits/$maxVisits' : '$visits'),
          GameStat('setupScore', '${visitClosed ? 0 : _setupScore}/$setupMin'),
          GameStat('doubleRate', formatPercent(doubleDarts == 0 ? null : doubleHits / doubleDarts)),
        ],
      );

  @override
  GameResult get result {
    final setupRate = visits == 0 ? null : setups / visits;
    final doubleRate = doubleDarts == 0 ? null : doubleHits / doubleDarts;
    return GameResult(
      metrics: {
        'visits': visits,
        'reached': index,
        'setupRate': setupRate ?? 0,
        'doubleRate': doubleRate ?? 0,
        'darts': dartsThrown,
        'completed': completed ? 1 : 0,
      },
      summary: [
        GameStat('visits', '$visits'),
        GameStat('progress', '$index/${sequence.length}'),
        GameStat('setupRate', formatPercent(setupRate)),
        GameStat('doubleRate', formatPercent(doubleRate)),
      ],
    );
  }
}
