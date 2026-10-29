/// Aufbereitung der Legs für den Spielverlauf: je Leg und Spieler der Rest
/// nach jeder Aufnahme (für das Diagramm), die Aufnahmen für die Tabelle und
/// die Darts aufs Doppel. Reine Berechnung aus [SessionDetail], ohne
/// Datenbank und ohne Oberfläche.
///
/// Ein „Doppel-Versuch“ ist genau das, was die Statistik als Checkout-Dart
/// zählt (`HistoryDart.finishAttempt`, siehe `X01Match.checkoutDarts`): ein
/// gezählter Dart bei einem Rest, der mit einem Dart checkbar ist. Er ist
/// getroffen, wenn damit das Leg endet. Deshalb passen „Doppelquote: x von y“
/// hier und `checkoutDarts`/`checkoutRate` in der Statistik zusammen.
library;

import '../../board/domain/segment.dart';
import '../../stats/domain/stats_models.dart';
import 'session_history.dart';

/// Name eines Doppels: `D16`, `Bull` für 25.
String doubleName(int number) => number == 25 ? 'Bull' : 'D$number';

/// Ein Doppel-Versuch einer Aufnahme: auf welches Feld und ob es getroffen
/// wurde.
class DoubleTry {
  const DoubleTry(this.target, this.hit);

  /// Das Feld des Wegvorschlags (meist ein Doppel).
  final Segment target;
  final bool hit;

  /// Kurzname, z. B. `D16` oder `Bull`.
  String get label => target.isDouble ? doubleName(target.number) : target.name;
}

/// Die Doppel-Versuche einer Aufnahme (leer ohne Versuch). Darts nach Bust
/// oder Checkout zählen nicht.
List<DoubleTry> doubleTriesOf(HistoryVisit v) => [
      for (final d in v.darts)
        if (d.finishAttempt && d.counted) DoubleTry(d.aimed ?? d.segment, d.hit),
    ];

/// Verfehlte Doppel einer Aufnahme.
List<DoubleTry> missedDoublesOf(HistoryVisit v) => [for (final t in doubleTriesOf(v)) if (!t.hit) t];

/// Quote aufs Doppel mit Aufschlüsselung je Doppel.
class DoubleTally {
  const DoubleTally(this.total, this.perDouble);
  static const DoubleTally empty = DoubleTally(HitCount.zero, {});

  /// Alle Versuche (auch Master-Out-Versuche auf ein Triple).
  final HitCount total;

  /// Versuche je Doppel (1–20, 25 = Bull), nur Felder, die ein Doppel sind.
  final Map<int, HitCount> perDouble;

  bool get isEmpty => total.attempts == 0;
  int get attempts => total.attempts;
  int get hits => total.hits;
  int get misses => total.attempts - total.hits;

  /// Doppel, auf die geworfen wurde: die meistgeworfenen zuerst, bei
  /// Gleichstand das höhere Doppel.
  List<MapEntry<int, HitCount>> get ranked => perDouble.entries.toList()
    ..sort((a, b) {
      final c = b.value.attempts.compareTo(a.value.attempts);
      return c != 0 ? c : b.key.compareTo(a.key);
    });

  DoubleTally operator +(DoubleTally o) {
    final map = {...perDouble};
    for (final e in o.perDouble.entries) {
      map[e.key] = (map[e.key] ?? HitCount.zero) + e.value;
    }
    return DoubleTally(total + o.total, map);
  }

  factory DoubleTally.of(Iterable<HistoryVisit> visits) {
    var total = HitCount.zero;
    final per = <int, HitCount>{};
    for (final v in visits) {
      for (final t in doubleTriesOf(v)) {
        final h = HitCount(1, t.hit ? 1 : 0);
        total += h;
        if (t.target.isDouble) per[t.target.number] = (per[t.target.number] ?? HitCount.zero) + h;
      }
    }
    return DoubleTally(total, per);
  }
}

/// Ein Spieler in einem Leg: seine Aufnahmen, Rest nach jeder Aufnahme und
/// die Darts aufs Doppel.
class LegBoardSide {
  LegBoardSide({required this.player, required this.name, required this.visits, required this.startScore})
      : doubles = DoubleTally.of(visits);

  /// Index in `SessionDetail.players` (0 bei Training ohne Gegner).
  final int player;
  final String name;
  final List<HistoryVisit> visits;
  final int startScore;
  final DoubleTally doubles;

  /// Rest vor der ersten Aufnahme und nach jeder weiteren: Länge
  /// `visits.length + 1`. Ein Bust lässt den Rest stehen, ein Checkout
  /// endet auf 0.
  late final List<int> rests = _rests();

  List<int> _rests() {
    final out = <int>[startScore];
    for (final v in visits) {
      final prev = out.last;
      out.add(v.checkout ? 0 : (int.tryParse(v.after ?? '') ?? prev));
    }
    return out;
  }

  /// Hat das Leg mit 0 beendet.
  bool get finished => visits.isNotEmpty && visits.last.checkout;

  /// Verfehlte Doppel in diesem Leg.
  int get missedDoubles => doubles.misses;
}

/// Ein Leg mit allen Spielern, deren Aufnahmen bekannt sind.
class LegBoard {
  const LegBoard({required this.leg, required this.startScore, required this.sides});

  final HistoryLeg leg;
  final int startScore;

  /// Eigene Seite zuerst, dann die Gegner, soweit ihre Würfe gespeichert sind.
  final List<LegBoardSide> sides;

  /// Nummer ab 1, 0 = ganze Session ohne Legs (Training).
  int get number => leg.number;

  /// Zeilen der Tabelle: die längste Seite.
  int get rows => sides.fold(0, (m, s) => s.visits.length > m ? s.visits.length : m);

  /// Seite mit diesem Spieler.
  LegBoardSide? sideOf(int player) => sides.where((s) => s.player == player).firstOrNull;

  /// Sieger-Seite, falls bekannt und seine Aufnahmen gespeichert sind.
  LegBoardSide? get winnerSide => leg.winner == null ? null : sideOf(leg.winner!);
}

/// Alle Legs einer Session, wie die Oberfläche sie zeigt.
class LegBoards {
  const LegBoards({required this.legs, required this.startScore, required this.players});

  final List<LegBoard> legs;
  final int startScore;

  /// Spieler in der Reihenfolge der Spalten (eigener zuerst).
  final List<({int player, String name})> players;

  /// Es gibt Aufnahmen von mindestens zwei Spielern (Gegner gespeichert).
  bool get hasOpponent => players.length > 1;

  /// Doppel-Versuche eines Spielers über alle Legs.
  DoubleTally doublesOf(int player) {
    var t = DoubleTally.empty;
    for (final l in legs) {
      final s = l.sideOf(player);
      if (s != null) t += s.doubles;
    }
    return t;
  }

  /// Gibt es irgendwo Doppel-Versuche (Voraussetzung für die Doppel-Zeile)?
  bool get anyDoubles => players.any((p) => !doublesOf(p.player).isEmpty);

  /// Aufnahmen des längsten Legs (Achse der Diagramme).
  int get maxVisits => legs.fold(0, (m, l) => l.rows > m ? l.rows : m);
}

/// Baut die Legs für [d]; `null`, wenn es für diese Session keinen
/// Aufnahmenverlauf mit Rest gibt (andere Spiele, ältere Matches ohne
/// Leg-Angaben, Importe ohne Würfe).
LegBoards? legBoardsOf(SessionDetail d) {
  if (d.afterKey != 'remaining' || d.legs.isEmpty) return null;
  final e = d.entry;
  if (!(e.isMatch || e.isImported || e.gameId == 'x01')) return null;
  final start = _startScore(d);
  final names = d.players.isEmpty ? <String>[] : [for (final p in d.players) p.name];
  String nameOf(int i) => i < names.length && names[i].isNotEmpty ? names[i] : '';
  final legs = <LegBoard>[];
  final seen = <int>{};
  for (final leg in d.legs) {
    if (leg.visits.isEmpty && leg.others.every((o) => o.visits.isEmpty)) continue;
    final sides = [
      LegBoardSide(player: d.me, name: nameOf(d.me), visits: leg.visits, startScore: start),
      for (final o in leg.others)
        if (o.visits.isNotEmpty) LegBoardSide(player: o.player, name: nameOf(o.player), visits: o.visits, startScore: start),
    ];
    seen.addAll([for (final s in sides) s.player]);
    legs.add(LegBoard(leg: leg, startScore: start, sides: sides));
  }
  if (legs.isEmpty) return null;
  final order = [d.me, ...seen.where((p) => p != d.me).toList()..sort()];
  return LegBoards(
    legs: legs,
    startScore: start,
    players: [for (final p in order) (player: p, name: nameOf(p))],
  );
}

int _startScore(SessionDetail d) {
  final e = d.entry;
  final format = e.details['format'];
  final v = (format is Map ? format['startScore'] : null) ?? e.config['startScore'];
  return v is num && v > 0 ? v.toInt() : 501;
}
