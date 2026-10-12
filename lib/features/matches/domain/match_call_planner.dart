import '../../caller/domain/caller_phrases.dart';
import '../../caller/domain/training_call_planner.dart';
import 'x01_match.dart';

/// Entscheidet, was der Caller in einem Match ausruft. Menschen und Bots
/// werden gleich behandelt.
abstract final class MatchCallPlanner {
  /// Ausrufe für die gerade abgeschlossene Aufnahme (3 Darts, Bust oder
  /// Checkout; [X01Match.visitClosed] ist `true`).
  static List<CallerCall> forClosedVisit(X01Match m) {
    final events = m.events.map((e) => e.type).toSet();
    if (events.contains(MatchEventType.legWon)) {
      final kind = events.contains(MatchEventType.matchWon)
          ? GameShotKind.match
          : events.contains(MatchEventType.setWon)
          ? GameShotKind.set
          : GameShotKind.leg;
      return [GameShotCall(kind)];
    }
    return [if (m.visitBust) const BustCall() else ScoreCall(m.visitScore), ?requireFor(m, m.nextPlayer)];
  }

  /// Aufnahme, die per Takeout bzw. „Weiter“ vor dem dritten Dart beendet
  /// wurde: Punkte von [player], danach der Rest des Spielers am Zug.
  static List<CallerCall> forEndedVisit(X01Match m, int player) => [
    ScoreCall(m.players[player].lastVisit ?? 0),
    ?requireFor(m, m.current),
  ];

  /// „You require N“ für [player], wenn sein Rest auscheckbar ist.
  static RequireCall? requireFor(X01Match m, int player) {
    if (m.finished) return null;
    final p = m.players[player];
    if (!p.opened || !TrainingCallPlanner.isFinishable(p.remaining, out: m.format.outMode)) return null;
    return RequireCall(p.remaining);
  }
}
