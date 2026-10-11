import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';

/// Gemeinsame Basis der Scoring-Drills: feste Anzahl Aufnahmen,
/// Punkte und Averages.
abstract class VisitScoringGame extends TrainingGame {
  VisitScoringGame({required super.seed, required this.visits});

  final int visits;
  final List<int> visitScores = [];
  int total = 0;

  int get currentVisitScore => visit.fold(0, (s, d) => s + d.score);

  double? get average => dartsThrown == 0 ? null : total / dartsThrown * 3;
  int get bestVisit => visitScores.isEmpty ? 0 : visitScores.reduce((a, b) => a > b ? a : b);

  @override
  void handleDart(DartThrow dart) => total += dart.score;

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    final score = visitDarts.fold(0, (s, d) => s + d.score);
    onVisitScored(score);
    visitScores.add(score);
    if (visitScores.length >= visits) finish();
  }

  /// Vor dem Speichern der Aufnahme in [visitScores].
  void onVisitScored(int score) {}

  String get visitLabel => '${(visitScores.length + (finished ? 0 : 1)).clamp(1, visits)}/$visits';
}

/// T20-Training (oder eine andere Zahl): möglichst viele Treffer auf das
/// Triple einer Zahl.
class TargetPractice extends VisitScoringGame {
  TargetPractice({required super.seed, super.visits = 10, this.number = 20});

  static const String id = 'target_practice';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'number': 20, 'visits': 10},
    options: const [
      IntChoiceOption('number', [20, 19, 18, 17, 16, 15]),
      IntOption('visits', min: 1, max: 50),
    ],
    create: (c, seed) => TargetPractice(seed: seed, number: c.intOf('number', 20), visits: c.intOf('visits', 10)),
  );

  final int number;
  int numberHits = 0;
  int trebles = 0;

  @override
  void handleDart(DartThrow dart) {
    super.handleDart(dart);
    if (dart.segment.number == number) {
      numberHits++;
      if (dart.segment.isTriple) {
        trebles++;
        events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
      }
    }
  }

  double? get trebleRate => dartsThrown == 0 ? null : trebles / dartsThrown;
  double? get numberRate => dartsThrown == 0 ? null : numberHits / dartsThrown;

  @override
  Set<Segment> get targets => finished ? const {} : {Segment.triple(number)};

  @override
  GameDisplay get display => GameDisplay(
        headline: '$total',
        headlineKey: 'points',
        progress: visitScores.length / visits,
        progressLabel: visitLabel,
        stats: [
          GameStat('average', formatDecimal(average)),
          GameStat('trebleRate', formatPercent(trebleRate)),
          GameStat('numberRate', formatPercent(numberRate)),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'points': total,
          'darts': dartsThrown,
          'average': average ?? 0,
          'trebles': trebles,
          'trebleRate': trebleRate ?? 0,
          'numberRate': numberRate ?? 0,
          'bestVisit': bestVisit,
        },
        summary: [
          GameStat('average', formatDecimal(average)),
          GameStat('trebleRate', formatPercent(trebleRate)),
          GameStat('numberRate', formatPercent(numberRate)),
          GameStat('bestVisit', '$bestVisit'),
        ],
      );
}

/// Score-Aufgabe: jede Aufnahme soll mindestens [target] Punkte bringen.
class ScoreTarget extends VisitScoringGame {
  ScoreTarget({required super.seed, super.visits = 10, this.target = 100});

  static const String id = 'score_target';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'target': 100, 'visits': 10},
    options: const [
      IntChoiceOption('target', [60, 81, 100, 121, 140, 180]),
      IntOption('visits', min: 1, max: 50),
    ],
    create: (c, seed) => ScoreTarget(seed: seed, target: c.intOf('target', 100), visits: c.intOf('visits', 10)),
  );

  final int target;
  int successes = 0;

  @override
  void onVisitScored(int score) {
    if (score >= target) {
      successes++;
      events.add(GameEvent(GameEventType.visitSuccess, value: score));
    } else {
      events.add(GameEvent(GameEventType.visitMissed, value: score));
    }
  }

  double? get successRate => visitScores.isEmpty ? null : successes / visitScores.length;

  @override
  Set<Segment> get targets => finished ? const {} : {Segment.triple(20)};

  @override
  GameDisplay get display => GameDisplay(
        headline: '${visitClosed ? (visitScores.isEmpty ? 0 : visitScores.last) : currentVisitScore}',
        headlineKey: 'visitScore',
        progress: visitScores.length / visits,
        progressLabel: visitLabel,
        stats: [
          GameStat('scoreTarget', '≥ $target'),
          GameStat('successes', '$successes/${visitScores.length}'),
          GameStat('average', formatDecimal(average)),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'successes': successes,
          'successRate': successRate ?? 0,
          'darts': dartsThrown,
          'points': total,
          'average': average ?? 0,
          'bestVisit': bestVisit,
        },
        summary: [
          GameStat('successes', '$successes/${visitScores.length}'),
          GameStat('successRate', formatPercent(successRate)),
          GameStat('average', formatDecimal(average)),
          GameStat('bestVisit', '$bestVisit'),
        ],
      );
}

/// Highscore-Jagd: in [visits] Aufnahmen so viele Punkte wie möglich.
class HighscoreHunt extends VisitScoringGame {
  HighscoreHunt({required super.seed, super.visits = 10});

  static const String id = 'highscore_hunt';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'visits': 10},
    options: const [IntOption('visits', min: 1, max: 50)],
    create: (c, seed) => HighscoreHunt(seed: seed, visits: c.intOf('visits', 10)),
  );

  @override
  void onVisitScored(int score) {
    if (visitScores.isNotEmpty && score > bestVisit) {
      events.add(GameEvent(GameEventType.best, value: score));
    }
  }

  @override
  Set<Segment> get targets => finished ? const {} : {Segment.triple(20)};

  @override
  GameDisplay get display => GameDisplay(
        headline: '$total',
        headlineKey: 'points',
        progress: visitScores.length / visits,
        progressLabel: visitLabel,
        stats: [
          GameStat('average', formatDecimal(average)),
          GameStat('bestVisit', '$bestVisit'),
          GameStat('visitScore', '$currentVisitScore'),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'points': total,
          'darts': dartsThrown,
          'average': average ?? 0,
          'bestVisit': bestVisit,
          'tons': visitScores.where((s) => s >= 100).length,
        },
        summary: [
          GameStat('points', '$total'),
          GameStat('average', formatDecimal(average)),
          GameStat('bestVisit', '$bestVisit'),
          GameStat('tons', '${visitScores.where((s) => s >= 100).length}'),
        ],
      );
}
