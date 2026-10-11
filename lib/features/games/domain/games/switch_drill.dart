import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';

/// Ziel-Wechsel (167): pro Aufnahme ein festes Ziel je Dart-Position.
///
/// Regeln:
/// * Preset `167`: T20, T19, Bullseye. Weitere: `trebles` (T20, T19, T18),
///   `doubles` (D20, D16, D8), `scoring` (T20, T19, T20).
/// * Ein Treffer zählt nur im exakten Feld, 1 Punkt pro Treffer.
/// * Ende nach [rounds] Aufnahmen. Nicht geworfene Darts zählen als Fehlwurf.
class SwitchDrill extends TrainingGame {
  SwitchDrill({required super.seed, this.preset = '167', this.rounds = 10});

  static const String id = 'switch_drill';

  static final Map<String, List<Segment>> presets = {
    '167': [Segment.triple(20), Segment.triple(19), Segment.bull],
    'trebles': [Segment.triple(20), Segment.triple(19), Segment.triple(18)],
    'doubles': [Segment.double(20), Segment.double(16), Segment.double(8)],
    'scoring': [Segment.triple(20), Segment.triple(19), Segment.triple(20)],
  };

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'preset': '167', 'rounds': 10},
    options: const [
      ChoiceOption('preset', ['167', 'trebles', 'doubles', 'scoring']),
      IntOption('rounds', min: 1, max: 30),
    ],
    create: (c, seed) => SwitchDrill(seed: seed, preset: c.stringOf('preset', '167'), rounds: c.intOf('rounds', 10)),
  );

  final String preset;
  final int rounds;

  late final List<Segment> sequence = presets[preset] ?? presets['167']!;
  int roundsPlayed = 0;
  int hits = 0;
  int perfectRounds = 0;
  final List<int> hitsByPosition = [0, 0, 0];
  int _visitHits = 0;

  @override
  void onVisitStart() => _visitHits = 0;

  @override
  void handleDart(DartThrow dart) {
    final pos = visit.length - 1;
    if (dart.segment != sequence[pos]) return;
    hits++;
    _visitHits++;
    hitsByPosition[pos]++;
    events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    roundsPlayed++;
    if (_visitHits == 3) {
      perfectRounds++;
      events.add(const GameEvent(GameEventType.visitSuccess, value: 3));
    }
    _visitHits = 0;
    if (roundsPlayed >= rounds) finish();
  }

  int get maxHits => rounds * TrainingGame.dartsPerVisit;
  double? get hitRate => roundsPlayed == 0 ? null : hits / (roundsPlayed * TrainingGame.dartsPerVisit);
  double? _positionRate(int i) => roundsPlayed == 0 ? null : hitsByPosition[i] / roundsPlayed;

  /// Feld der nächsten Dart-Position.
  Segment get nextTarget => sequence[visitClosed ? 0 : visit.length.clamp(0, 2)];

  @override
  Set<Segment> get targets => finished ? const {} : {nextTarget};

  @override
  GameDisplay get display => GameDisplay(
        headline: finished ? '$hits' : nextTarget.name,
        headlineKey: finished ? 'hitsOnTarget' : 'target',
        progress: roundsPlayed / rounds,
        progressLabel: '${(roundsPlayed + (finished ? 0 : 1)).clamp(1, rounds)}/$rounds',
        stats: [
          GameStat('hitsOnTarget', '$hits'),
          GameStat('hitRate', formatPercent(hitRate)),
          GameStat('perfectRounds', '$perfectRounds'),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'hits': hits,
          'maxHits': maxHits,
          'hitRate': hitRate ?? 0,
          'hitRateTarget0': _positionRate(0) ?? 0,
          'hitRateTarget1': _positionRate(1) ?? 0,
          'hitRateTarget2': _positionRate(2) ?? 0,
          'perfectRounds': perfectRounds,
          'darts': dartsThrown,
          'completed': roundsPlayed >= rounds ? 1 : 0,
        },
        summary: [
          GameStat('hitsOnTarget', '$hits/$maxHits'),
          GameStat('hitRate', formatPercent(hitRate)),
          for (var i = 0; i < 3; i++) GameStat('rateOf', '${sequence[i].name}: ${formatPercent(_positionRate(i))}'),
          GameStat('perfectRounds', '$perfectRounds'),
        ],
      );
}
