import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';

/// Wertet eine Shanghai-Aufnahme auf eine Zahl: Punkte der Treffer und ob
/// Single, Double und Triple dabei sind.
class ShanghaiTracker {
  bool hasSingle = false;
  bool hasDouble = false;
  bool hasTriple = false;

  void reset() => hasSingle = hasDouble = hasTriple = false;

  /// Nimmt einen Treffer auf. Gibt `true` zurück, wenn damit gerade ein
  /// Shanghai komplett ist.
  bool add(Segment s) {
    final before = isShanghai;
    if (s.isTriple) {
      hasTriple = true;
    } else if (s.isDouble) {
      hasDouble = true;
    } else if (s.isSingle) {
      hasSingle = true;
    }
    return !before && isShanghai;
  }

  bool get isShanghai => hasSingle && hasDouble && hasTriple;
}

/// JDC-Challenge: Prüfungsroutine der Junior Darts Corporation, 57 Darts.
///
/// Regeln:
/// * Teil 1: Shanghai 10–15, je eine Aufnahme. Treffer zählen Zahl ×
///   Multiplikator, Single + Double + Triple in einer Aufnahme = +100.
/// * Teil 2: je ein Dart auf D1 … D20, dann Bullseye. Treffer = 50, Bullseye
///   = 100. Das Ziel wechselt nach jedem Dart.
/// * Teil 3: Shanghai 15–20 wie Teil 1.
class JdcChallenge extends TrainingGame {
  JdcChallenge({required super.seed});

  static const String id = 'jdc_challenge';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {},
    options: const [],
    create: (c, seed) => JdcChallenge(seed: seed),
  );

  static const int totalDarts = 57;
  static const int shanghaiBonus = 100;
  static const List<int> part1Numbers = [10, 11, 12, 13, 14, 15];
  static const List<int> part3Numbers = [15, 16, 17, 18, 19, 20];

  /// Teil 1–3.
  int part = 1;

  /// Index innerhalb des Teils (Zahl bzw. Double).
  int index = 0;
  final List<int> partScores = [0, 0, 0];
  int shanghais = 0;
  int doubleHits = 0;
  int part2Darts = 0;
  final ShanghaiTracker _tracker = ShanghaiTracker();
  bool _skipVisitEnd = false;

  int get score => partScores.fold(0, (a, b) => a + b);

  List<int> get _numbers => part == 1 ? part1Numbers : part3Numbers;

  /// Aktuelle Zahl in Teil 1/3.
  int get currentNumber => _numbers[index.clamp(0, 5)];

  /// Aktuelles Ziel in Teil 2.
  Segment get currentDouble => index >= 20 ? Segment.bull : Segment.double(index + 1);

  String get targetLabel => part == 2 ? currentDouble.name : '$currentNumber';

  @override
  void onVisitStart() => _tracker.reset();

  @override
  void handleDart(DartThrow dart) {
    final s = dart.segment;
    if (part == 2) {
      part2Darts++;
      if (s == currentDouble) {
        doubleHits++;
        final points = s.isBull ? 100 : 50;
        partScores[1] += points;
        events.add(GameEvent(GameEventType.hit, value: s.name));
      }
      index++;
      if (index > 20) {
        events.add(const GameEvent(GameEventType.partComplete, value: 2));
        part = 3;
        index = 0;
        _skipVisitEnd = true;
        closeVisit();
      }
      return;
    }
    if (s.number != currentNumber) return;
    partScores[part - 1] += s.score;
    events.add(GameEvent(GameEventType.hit, value: s.name));
    if (_tracker.add(s)) {
      shanghais++;
      partScores[part - 1] += shanghaiBonus;
      events.add(GameEvent(GameEventType.shanghai, value: currentNumber));
    }
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished) return;
    if (_skipVisitEnd) {
      _skipVisitEnd = false;
      return;
    }
    // In Teil 2 wechselt das Ziel nur pro Dart.
    if (part == 2) return;
    _tracker.reset();
    index++;
    if (index < 6) return;
    events.add(GameEvent(GameEventType.partComplete, value: part));
    if (part == 1) {
      part = 2;
      index = 0;
    } else {
      finish();
    }
  }

  /// Position des nächsten Darts in der Routine (1–57).
  int get dartNumber {
    final inVisit = visitClosed ? 0 : visit.length;
    final n = switch (part) {
      1 => index * 3 + inVisit,
      2 => 18 + index,
      _ => 39 + index * 3 + inVisit,
    };
    return (n + 1).clamp(1, totalDarts);
  }

  double? get doubleRate => part2Darts == 0 ? null : doubleHits / part2Darts;

  @override
  Set<Segment> get targets {
    if (finished) return const {};
    if (part == 2) return {currentDouble};
    final n = currentNumber;
    return {Segment.single(n), Segment.single(n, inner: true), Segment.double(n), Segment.triple(n)};
  }

  @override
  GameDisplay get display => GameDisplay(
        headline: '$score',
        headlineKey: 'points',
        progress: finished ? 1 : (dartNumber - 1) / totalDarts,
        progressLabel: 'Dart ${finished ? totalDarts : dartNumber}/$totalDarts',
        stats: [
          GameStat('part', '$part/3'),
          GameStat('target', finished ? '–' : targetLabel),
          GameStat('partPoints', '${partScores[part - 1]}'),
        ],
      );

  @override
  GameResult get result => GameResult(
        metrics: {
          'score': score,
          'part1': partScores[0],
          'part2': partScores[1],
          'part3': partScores[2],
          'shanghais': shanghais,
          'doubleHits': doubleHits,
          'doubleRate': doubleRate ?? 0,
          'darts': dartsThrown,
          'completed': finished ? 1 : 0,
        },
        summary: [
          GameStat('points', '$score'),
          GameStat('part1', '${partScores[0]}'),
          GameStat('part2', '${partScores[1]}'),
          GameStat('part3', '${partScores[2]}'),
          GameStat('shanghais', '$shanghais'),
          GameStat('doubleRate', formatPercent(doubleRate)),
        ],
      );
}
