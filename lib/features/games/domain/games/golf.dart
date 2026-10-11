import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import '../engine/game_definition.dart';
import '../engine/game_display.dart';
import '../engine/training_game.dart';

/// Darts-Golf: Loch n hat die Zahl n als Ziel, eine Aufnahme pro Loch.
///
/// Regeln:
/// * Nach jedem Dart darf man aufhören („Weiter“). Es zählt der letzte
///   Dart ([countBest] = der beste der Aufnahme).
/// * Schläge `classic`: Double 1, Triple 2, inneres Single 3, äußeres
///   Single 4, sonst 5. `simple` (ohne inner/outer): Double 1, Triple 3,
///   Single 4, sonst 5.
/// * Par 3 pro Loch, weniger ist besser.
class DartsGolf extends TrainingGame {
  DartsGolf({required super.seed, this.holes = 9, this.classic = false, this.countBest = false});

  static const String id = 'golf';
  static const int parPerHole = 3;

  static final GameDefinition definition = GameDefinition(
    id: id,
    defaults: const {'holes': 9, 'scoring': 'simple', 'counts': 'last'},
    options: const [
      IntChoiceOption('holes', [9, 18]),
      ChoiceOption('scoring', ['classic', 'simple']),
      ChoiceOption('counts', ['last', 'best']),
    ],
    create: (c, seed) => DartsGolf(
      seed: seed,
      holes: c.intOf('holes', 9) >= 18 ? 18 : 9,
      classic: c.stringOf('scoring', 'simple') == 'classic',
      countBest: c.stringOf('counts', 'last') == 'best',
    ),
  );

  final int holes;
  final bool classic;
  final bool countBest;

  int hole = 1;
  final List<int> holeStrokes = [];

  int get strokes => holeStrokes.fold(0, (a, b) => a + b);
  int get par => holeStrokes.length * parPerHole;
  int get toPar => strokes - par;

  /// Schläge für einen Dart auf Loch [hole].
  int strokesFor(Segment s, int hole) {
    if (s.number != hole) return 5;
    if (s.isDouble) return 1;
    if (s.isTriple) return classic ? 2 : 3;
    if (classic && s.bed == Bed.singleInner) return 3;
    return 4;
  }

  /// Wert der laufenden Aufnahme nach der gewählten Wertung, `null` ohne Dart.
  int? get currentHoleValue {
    if (visitClosed || visit.isEmpty) return null;
    return _valueOf(visit);
  }

  int _valueOf(List<DartThrow> darts) {
    final values = [for (final d in darts) strokesFor(d.segment, hole)];
    return countBest ? values.reduce((a, b) => a < b ? a : b) : values.last;
  }

  @override
  void handleDart(DartThrow dart) {
    final v = strokesFor(dart.segment, hole);
    if (v < 5) events.add(GameEvent(GameEventType.hit, value: dart.segment.name));
  }

  @override
  void handleVisitEnd(List<DartThrow> visitDarts) {
    if (finished || visitDarts.isEmpty) return;
    holeStrokes.add(_valueOf(visitDarts));
    hole++;
    if (holeStrokes.length >= holes) finish();
  }

  static String formatToPar(int v) => v > 0 ? '+$v' : '$v';

  @override
  Set<Segment> get targets => finished ? const {} : {Segment.double(hole)};

  @override
  GameDisplay get display {
    final v = currentHoleValue;
    return GameDisplay(
      headline: finished ? '$strokes' : '$hole',
      headlineKey: finished ? 'strokes' : 'hole',
      progress: holeStrokes.length / holes,
      progressLabel: '${(holeStrokes.length + (finished ? 0 : 1)).clamp(1, holes)}/$holes',
      stats: [
        GameStat('strokes', '$strokes'),
        GameStat('toPar', formatToPar(toPar)),
        GameStat('holeValue', v == null ? '–' : '$v'),
      ],
    );
  }

  @override
  GameResult get result {
    final avg = holeStrokes.isEmpty ? null : strokes / holeStrokes.length;
    final aces = holeStrokes.where((s) => s == 1).length;
    return GameResult(
      metrics: {
        'strokes': strokes,
        'par': par,
        'toPar': toPar,
        'holesInOne': aces,
        'averagePerHole': avg ?? 0,
        'holes': holeStrokes.length,
        'darts': dartsThrown,
        'completed': holeStrokes.length >= holes ? 1 : 0,
      },
      summary: [
        GameStat('strokes', '$strokes'),
        GameStat('toPar', formatToPar(toPar)),
        GameStat('holesInOne', '$aces'),
        GameStat('averagePerHole', formatDecimal(avg)),
      ],
      details: {'holes': holeStrokes},
    );
  }
}
