import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../games/domain/engine/game_display.dart';

/// Spiel-ID der mitgeschriebenen Autodarts-Sessions (Autodarts Live).
const String autodartsLiveGameId = 'autodarts_live';

/// Spiel-ID mitgeschriebener Sessions mit „X01 mitzählen“. Beginnt mit
/// „x01“, damit Aufnahmen wie bei X01 in Punkteverteilung und Konstanz
/// eingehen; der Average kommt aus der Kennzahl `average`.
const String autodartsLiveX01GameId = 'x01_live';

/// Ein Dart, wie ihn die Live-Statistik braucht: Feld und, falls bekannt,
/// die Position auf dem Board.
typedef LiveDart = ({Segment segment, BoardPoint? position});

/// Kennzahlen einer mitgeschriebenen Session.
///
/// DartLab sieht im Live-Modus nur die Darts, nicht das Spiel dahinter
/// (kein Restwert, kein Bust, kein Checkout, keine Legs). Deshalb gibt es
/// hier nur Scoring-Werte: Der Schnitt zählt die Rohpunkte aller Darts, auch
/// Darts auf ein Doppel oder in einer überworfenen Aufnahme. Er ist also
/// kein offizieller X01-Average.
class LiveStats {
  const LiveStats._({
    required this.darts,
    required this.visits,
    required this.points,
    required this.bestVisit,
    required this.count100,
    required this.count140,
    required this.count180,
    required this.triples,
    required this.doubles,
    required this.singles,
    required this.misses,
    required this.heat,
  });

  static const LiveStats empty = LiveStats._(
    darts: 0,
    visits: 0,
    points: 0,
    bestVisit: 0,
    count100: 0,
    count140: 0,
    count180: 0,
    triples: 0,
    doubles: 0,
    singles: 0,
    misses: 0,
    heat: [],
  );

  /// Berechnet die Kennzahlen aus den Aufnahmen (je Aufnahme 1–3 Darts).
  factory LiveStats.of(Iterable<List<LiveDart>> visits) {
    var darts = 0, count = 0, points = 0, best = 0;
    var c100 = 0, c140 = 0, c180 = 0;
    var t = 0, d = 0, s = 0, m = 0;
    final heat = <BoardPoint>[];
    for (final v in visits) {
      if (v.isEmpty) continue;
      count++;
      var score = 0;
      for (final dart in v) {
        final seg = dart.segment;
        darts++;
        score += seg.score;
        if (seg.isMiss) {
          m++;
        } else if (seg.isTriple) {
          t++;
        } else if (seg.isDouble) {
          d++;
        } else {
          s++;
        }
        final p = dart.position ?? (seg.isMiss ? null : BoardGeometry.centerOf(seg));
        if (p != null) heat.add(p);
      }
      points += score;
      if (score > best) best = score;
      // Wie bei X01: Bänder schließen sich aus (100–139, 140–179, 180).
      if (score == 180) {
        c180++;
      } else if (score >= 140) {
        c140++;
      } else if (score >= 100) {
        c100++;
      }
    }
    return LiveStats._(
      darts: darts,
      visits: count,
      points: points,
      bestVisit: best,
      count100: c100,
      count140: c140,
      count180: c180,
      triples: t,
      doubles: d,
      singles: s,
      misses: m,
      heat: heat,
    );
  }

  final int darts;
  final int visits;

  /// Rohpunkte aller Darts.
  final int points;
  final int bestVisit;

  /// Aufnahmen mit 100–139, 140–179 und 180 Punkten.
  final int count100;
  final int count140;
  final int count180;

  /// Darts nach getroffenem Feld (Bull zählt als Doppel, 25 als Single).
  final int triples;
  final int doubles;
  final int singles;
  final int misses;

  /// Positionen aller Darts für die Heatmap (ohne Koordinaten: Feldmitte).
  final List<BoardPoint> heat;

  bool get isEmpty => darts == 0;

  /// Rohpunkte je drei Darts, `null` ohne Darts.
  double? get rawAverage => darts == 0 ? null : points / darts * 3;

  double? _share(int n) => darts == 0 ? null : n / darts;
  double? get tripleShare => _share(triples);
  double? get doubleShare => _share(doubles);
  double? get singleShare => _share(singles);
  double? get missShare => _share(misses);

  /// Ergebnis zum Speichern. Bewusst ohne `average`, `first9` oder
  /// Checkout-Werte, damit nichts mit einem echten X01-Average verwechselt
  /// wird. Die Statistik rechnet die Live-Darts trotzdem in den
  /// Scoring-Average ein (siehe `scoringGames`).
  GameResult toResult() => GameResult(
        metrics: {
          'rawAverage': double.parse((rawAverage ?? 0).toStringAsFixed(2)),
          'darts': darts,
          'visits': visits,
          'points': points,
          'bestVisit': bestVisit,
          'count100': count100,
          'count140': count140,
          'count180': count180,
          'triplesRate': tripleShare ?? 0,
          'doublesRate': doubleShare ?? 0,
          'singlesRate': singleShare ?? 0,
          'missRate': missShare ?? 0,
        },
        summary: const [],
        details: const {'source': 'autodartsLocal', 'mode': 'listen'},
      );
}
