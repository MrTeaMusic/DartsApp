import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';

/// Bullseye-Drill: feste Anzahl Aufnahmen nur auf Bull.
/// Punkte: Single Bull 25, Bullseye 50, alles andere 0.
class BullDrill extends TrainingGame {
  BullDrill({required super.seed, this.visits = 10});

  static const String id = 'bull_drill';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'visits': 10},
    options: const [IntOption('visits', min: 1, max: 50)],
    create: (c, seed) => BullDrill(seed: seed, visits: c.intOf('visits', 10)),
  );

  final int visits;
  int points = 0;
  int bulls = 0;
  int outerBulls = 0;
  int completedVisits = 0;

  @override
  void handleDart(DartThrow dart) {
    final s = dart.segment;
    if (s.bed == Bed.innerBull) {
      bulls++;
      points += 50;
      events.add(const GameEvent(GameEventType.hit, value: 50));
    } else if (s.bed == Bed.outerBull) {
      outerBulls++;
      points += 25;
      events.add(const GameEvent(GameEventType.hit, value: 25));
    }
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    completedVisits++;
    if (completedVisits >= visits) finish();
  }

  double? get hitRate => dartsThrown == 0 ? null : (bulls + outerBulls) / dartsThrown;
  double? get bullRate => dartsThrown == 0 ? null : bulls / dartsThrown;

  @override
  Set<Segment> get targets => finished ? const {} : {Segment.bull, Segment.outerBull};

  @override
  GameDisplay get display => GameDisplay(
        headline: '$points',
        headlineKey: 'points',
        progress: completedVisits / visits,
        progressLabel: '${(completedVisits + (finished ? 0 : 1)).clamp(1, visits)}/$visits',
        stats: [
          GameStat('bullHits', '$bulls'),
          GameStat('outerBullHits', '$outerBulls'),
          GameStat('hitRate', formatPercent(hitRate)),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'points': points,
          'darts': dartsThrown,
          'bulls': bulls,
          'outerBulls': outerBulls,
          'hitRate': hitRate ?? 0,
          'bullRate': bullRate ?? 0,
        },
        summary: [
          GameStat('points', '$points'),
          GameStat('hitRate', formatPercent(hitRate)),
          GameStat('bullRate', formatPercent(bullRate)),
        ],
      );
}
