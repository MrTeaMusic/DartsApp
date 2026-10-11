import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';
import 'around_the_clock.dart';

NumberOrder _orderOf(Map<String, Object?> c) =>
    NumberOrder.values.firstWhere((v) => v.name == c.stringOf('order', 'ascending'), orElse: () => NumberOrder.ascending);

Set<Segment> _numberSegments(int n) => n == 25
    ? {Segment.outerBull, Segment.bull}
    : {Segment.single(n), Segment.single(n, inner: true), Segment.double(n), Segment.triple(n)};

String _label(int n) => n == 25 ? 'BULL' : '$n';

/// Drei-Treffer-Runde (Around the World mit Pflicht).
///
/// Regeln:
/// * Reihenfolge 1–20 (oder im Uhrzeigersinn bzw. zufällig), optional Bull
///   am Ende.
/// * Pro Zahl braucht es [hitsRequired] Treffer (Standard 3). Single, Double
///   und Triple zählen je 1, mit [multiplierCounts] Double 2 und Triple 3.
///   Bull: 25 und Bullseye je 1 (mit [multiplierCounts] Bullseye 2).
/// * Treffer sammeln sich über Aufnahmen hinweg. Jeder Dart zählt auf die
///   Zahl, die in dem Moment aktuell ist; überzählige Treffer verfallen.
/// * Ende nach der letzten Zahl. Wertung: benötigte Darts.
class ThreeHitsRound extends TrainingGame {
  ThreeHitsRound({
    required super.seed,
    this.order = NumberOrder.ascending,
    this.includeBull = true,
    this.hitsRequired = 3,
    this.multiplierCounts = false,
  });

  static const String id = 'three_hits';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'order': 'ascending', 'includeBull': true, 'hitsRequired': 3, 'multiplierCounts': false},
    options: const [
      ChoiceOption('order', ['ascending', 'clockwise', 'random']),
      IntOption('hitsRequired', min: 1, max: 9),
      BoolOption('multiplierCounts'),
      BoolOption('includeBull'),
    ],
    create: (c, seed) => ThreeHitsRound(
      seed: seed,
      order: _orderOf(c),
      includeBull: c.boolOf('includeBull', true),
      hitsRequired: c.intOf('hitsRequired', 3),
      multiplierCounts: c.boolOf('multiplierCounts', false),
    ),
  );

  final NumberOrder order;
  final bool includeBull;
  final int hitsRequired;
  final bool multiplierCounts;

  late final List<int> sequence;
  int index = 0;

  /// Treffer auf die aktuelle Zahl.
  int progressHits = 0;

  /// Darts, die die aktuelle Zahl getroffen haben.
  int hitDarts = 0;

  /// Benötigte Darts je erledigter Zahl.
  final List<int> dartsPerNumber = [];
  int _dartsOnCurrent = 0;

  int get current => sequence[index.clamp(0, sequence.length - 1)];

  @override
  void onStart() {
    sequence = buildNumberOrder(order, includeBull: includeBull, shuffle: (l) => l..shuffle(random));
  }

  int _value(Segment s) => multiplierCounts ? s.multiplier : 1;

  @override
  void handleDart(DartThrow dart) {
    _dartsOnCurrent++;
    if (dart.segment.number != current) return;
    hitDarts++;
    progressHits += _value(dart.segment);
    if (progressHits < hitsRequired) {
      events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
      return;
    }
    dartsPerNumber.add(_dartsOnCurrent);
    _dartsOnCurrent = 0;
    progressHits = 0;
    index++;
    if (index >= sequence.length) {
      finish();
    } else {
      events.add(GameEvent(GameEventType.advanced, value: _label(sequence[index - 1])));
    }
  }

  double? get hitRate => dartsThrown == 0 ? null : hitDarts / dartsThrown;

  @override
  Set<Segment> get targets => finished ? const {} : _numberSegments(current);

  @override
  GameDisplay get display => GameDisplay(
        headline: finished ? '✓' : _label(current),
        headlineKey: 'target',
        progress: (index + progressHits / hitsRequired) / sequence.length,
        progressLabel: '$index/${sequence.length}',
        stats: [
          GameStat('hitsOnTarget', '$progressHits/$hitsRequired'),
          GameStat('darts', '$dartsThrown'),
          GameStat('hitRate', formatPercent(hitRate)),
          if (!finished && index + 1 < sequence.length) GameStat('next', _label(sequence[index + 1])),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'darts': dartsThrown,
          'hitRate': hitRate ?? 0,
          'completed': finished ? 1 : 0,
          'progress': index / sequence.length,
        },
        summary: [
          GameStat('darts', '$dartsThrown'),
          GameStat('hitRate', formatPercent(hitRate)),
          GameStat('progress', '$index/${sequence.length}'),
        ],
        details: {'sequence': sequence, 'dartsPerNumber': dartsPerNumber},
      );
}

/// Around the World mit Überspringen.
///
/// Regeln:
/// * Reihenfolge wie bei der Drei-Treffer-Runde, optional Bull am Ende.
/// * Genau eine Aufnahme pro Zahl, danach geht es immer weiter.
/// * Punkte nur auf die aktuelle Zahl: Single 1, Double 2, Triple 3,
///   Bull: 25 = 1, Bullseye = 2.
/// * Mindestens [skipThreshold] Punkte in einer Aufnahme: die nächste Zahl
///   wird übersprungen (0 Punkte).
/// * Bull wird nie übersprungen, außer [bullSkippable] ist an; dann endet
///   das Spiel mit dem Sprung.
/// * Wertung: Gesamtpunkte und Anzahl Sprünge.
class SkipAroundTheWorld extends TrainingGame {
  SkipAroundTheWorld({
    required super.seed,
    this.order = NumberOrder.ascending,
    this.includeBull = true,
    this.skipThreshold = 4,
    this.bullSkippable = false,
  });

  static const String id = 'skip_world';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'order': 'ascending', 'includeBull': true, 'skipThreshold': 4, 'bullSkippable': false},
    options: const [
      ChoiceOption('order', ['ascending', 'clockwise', 'random']),
      IntOption('skipThreshold', min: 1, max: 9),
      BoolOption('includeBull'),
      BoolOption('bullSkippable'),
    ],
    create: (c, seed) => SkipAroundTheWorld(
      seed: seed,
      order: _orderOf(c),
      includeBull: c.boolOf('includeBull', true),
      skipThreshold: c.intOf('skipThreshold', 4),
      bullSkippable: c.boolOf('bullSkippable', false),
    ),
  );

  final NumberOrder order;
  final bool includeBull;
  final int skipThreshold;
  final bool bullSkippable;

  late final List<int> sequence;
  int index = 0;
  int points = 0;
  int skips = 0;
  int _visitPoints = 0;

  /// Punkte je Zahl; übersprungene Zahlen stehen mit `null` drin.
  final Map<int, int?> pointsByNumber = {};

  int get current => sequence[index.clamp(0, sequence.length - 1)];

  @override
  void onStart() {
    sequence = buildNumberOrder(order, includeBull: includeBull, shuffle: (l) => l..shuffle(random));
  }

  @override
  void onVisitStart() => _visitPoints = 0;

  @override
  void handleDart(DartThrow dart) {
    if (dart.segment.number != current) return;
    final p = dart.segment.multiplier;
    _visitPoints += p;
    points += p;
    events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    pointsByNumber[current] = _visitPoints;
    final skip = _visitPoints >= skipThreshold;
    _visitPoints = 0;
    index++;
    if (skip && index < sequence.length) {
      final next = sequence[index];
      if (next != 25 || bullSkippable) {
        pointsByNumber[next] = null;
        skips++;
        index++;
        events.add(GameEvent(GameEventType.skipped, value: _label(next)));
      }
    }
    if (index >= sequence.length) finish();
  }

  /// Gespielte (nicht übersprungene) Zahlen.
  int get played => pointsByNumber.values.where((v) => v != null).length;

  @override
  Set<Segment> get targets => finished ? const {} : _numberSegments(current);

  @override
  GameDisplay get display => GameDisplay(
        headline: finished ? '$points' : _label(current),
        headlineKey: finished ? 'points' : 'target',
        progress: index / sequence.length,
        progressLabel: '${index.clamp(0, sequence.length)}/${sequence.length}',
        stats: [
          GameStat('points', '$points'),
          GameStat('visitScore', '$_visitPoints/$skipThreshold'),
          GameStat('skips', '$skips'),
          if (!finished && index + 1 < sequence.length) GameStat('next', _label(sequence[index + 1])),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'points': points,
          'skips': skips,
          'darts': dartsThrown,
          'pointsPerNumber': played == 0 ? 0 : points / played,
          'completed': finished ? 1 : 0,
        },
        summary: [
          GameStat('points', '$points'),
          GameStat('skips', '$skips'),
          GameStat('pointsPerNumber', formatDecimal(played == 0 ? null : points / played)),
        ],
        details: {
          'sequence': sequence,
          'points': {for (final e in pointsByNumber.entries) '${e.key}': e.value},
        },
      );
}
