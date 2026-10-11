import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';

/// Reihenfolge beim Cricket-Training.
enum CricketOrder {
  /// Jede offene Zahl zählt.
  free,

  /// Erst 20 schließen, dann 19, … 15, dann Bull.
  sequential,
}

/// Cricket als Solo-Training: die Zahlen 20 bis 15 und Bull schließen.
///
/// Regeln:
/// * Single = 1 Mark, Double = 2, Triple = 3. Bei Bull: 25 = 1, Bullseye = 2.
/// * Eine Zahl ist mit [marksToClose] Marks geschlossen. Marks darüber
///   hinaus verfallen (ohne Gegner gibt es keine Punkte).
/// * [order] frei: jede offene Zahl zählt. Der Reihe nach: nur die aktuelle.
/// * Ende, wenn alle Zahlen geschlossen sind. Wertung: Darts und
///   Marks pro Aufnahme (MPR).
class CricketTraining extends TrainingGame {
  CricketTraining({
    required super.seed,
    this.order = CricketOrder.free,
    this.marksToClose = 3,
    this.includeBull = true,
  });

  static const String id = 'cricket';

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'cricketOrder': 'free', 'marksToClose': 3, 'includeBull': true},
    options: const [
      ChoiceOption('cricketOrder', ['free', 'sequential']),
      IntOption('marksToClose', min: 1, max: 9),
      BoolOption('includeBull'),
    ],
    create: (c, seed) => CricketTraining(
      seed: seed,
      order: c.stringOf('cricketOrder', 'free') == 'sequential' ? CricketOrder.sequential : CricketOrder.free,
      marksToClose: c.intOf('marksToClose', 3),
      includeBull: c.boolOf('includeBull', true),
    ),
  );

  final CricketOrder order;
  final int marksToClose;
  final bool includeBull;

  late final List<int> numbers = [20, 19, 18, 17, 16, 15, if (includeBull) 25];
  late final Map<int, int> marks = {for (final n in numbers) n: 0};

  /// Marks, die zum Schließen beigetragen haben.
  int countedMarks = 0;

  bool isClosed(int n) => (marks[n] ?? 0) >= marksToClose;

  List<int> get open => [for (final n in numbers) if (!isClosed(n)) n];

  /// Zahlen, auf die gerade Marks zählen.
  List<int> get active {
    final o = open;
    if (o.isEmpty) return const [];
    return order == CricketOrder.sequential ? [o.first] : o;
  }

  static int marksOf(Segment s) => s.isMiss ? 0 : s.multiplier;

  @override
  void handleDart(DartThrow dart) {
    final n = dart.segment.number;
    if (!active.contains(n)) return;
    final before = marks[n]!;
    final add = marksOf(dart.segment).clamp(0, marksToClose - before);
    marks[n] = before + add;
    countedMarks += add;
    if (isClosed(n)) {
      events.add(GameEvent(GameEventType.closed, value: n == 25 ? 'BULL' : '$n'));
      if (open.isEmpty) finish();
    } else {
      events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
    }
  }

  /// Abgeschlossene oder angefangene Aufnahmen.
  int get visitsPlayed => dartsThrown == 0 ? 0 : visitIndex + 1;

  double? get mpr => visitsPlayed == 0 ? null : countedMarks / visitsPlayed;

  @override
  Set<Segment> get targets => {
        for (final n in active)
          ...(n == 25
              ? [Segment.outerBull, Segment.bull]
              : [Segment.single(n), Segment.single(n, inner: true), Segment.double(n), Segment.triple(n)]),
      };

  String _label(int n) => n == 25 ? 'BULL' : '$n';

  /// Marks einer Zahl für die Anzeige: "✓" oder ein Punkt pro Mark.
  String markText(int n) => isClosed(n) ? '✓' : (marks[n] == 0 ? '–' : '•' * marks[n]!);

  @override
  GameDisplay get display {
    final a = active;
    return GameDisplay(
      headline: finished ? '✓' : (order == CricketOrder.sequential ? _label(a.first) : '${open.length}'),
      headlineKey: order == CricketOrder.sequential ? 'target' : 'openNumbers',
      progress: countedMarks / (numbers.length * marksToClose),
      progressLabel: '${numbers.length - open.length}/${numbers.length}',
      stats: [
        GameStat('darts', '$dartsThrown'),
        GameStat('mpr', formatDecimal(mpr)),
        // Schlüssel ist die Zahl selbst, die Oberfläche zeigt ihn unverändert.
        for (final n in numbers) GameStat(_label(n), markText(n)),
      ],
    );
  }

  @override
  GameResult get result => GameResult(
        metrics: {
          'darts': dartsThrown,
          'marks': countedMarks,
          'mpr': mpr ?? 0,
          'closedNumbers': numbers.length - open.length,
          'completed': finished ? 1 : 0,
        },
        summary: [
          GameStat('darts', '$dartsThrown'),
          GameStat('mpr', formatDecimal(mpr)),
          GameStat('closedNumbers', '${numbers.length - open.length}/${numbers.length}'),
        ],
        details: {'marks': {for (final n in numbers) '$n': marks[n]}},
      );
}
