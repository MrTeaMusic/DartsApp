import '../../games/domain/engine/game_definition.dart';
import '../../games/domain/game_catalog.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../../matches/domain/match_format.dart';
import '../../matches/domain/match_result.dart';
import '../../matches/domain/match_session.dart';

/// Kapitel des Challenge-Modus, leichteste zuerst.
enum ChallengeChapter { beginner, amateur, league, pro, worldClass }

/// Einheit der Wertungs-Kennzahl (für die Anzeige der Schwellen).
enum ChallengeUnit { darts, points, checkouts, successes, hits, strokes, visits, level, average }

/// Gegner und Format einer Challenge gegen den Computer.
class MatchChallenge {
  const MatchChallenge({required this.botAverage, required this.legsToWin, this.startScore = 501, required this.average});

  /// Ziel-Average des Computers.
  final double botAverage;
  final int legsToWin;
  final int startScore;

  /// Eigener Average für den dritten Stern.
  final double average;

  MatchFormat get format => MatchFormat(startScore: startScore, outMode: OutMode.double, legsToWin: legsToWin);
  int get bestOf => format.bestOf;
}

/// Wie eine Challenge-Sterne-Schwelle gerade steht (für die Live-Anzeige).
enum StarState {
  /// Noch offen.
  open,

  /// Im Moment erreicht, kann aber wieder verloren gehen (Halve-It, Bob's 27).
  provisional,

  /// Sicher erreicht.
  reached,

  /// Nicht mehr zu schaffen.
  lost,
}

/// Wie sich die Live-Kennzahl im Spiel entwickelt.
enum LiveTrend {
  /// Steigt nur (Darts, Aufnahmen, Punkte).
  rising,

  /// Fällt nur (Restpunkte bei 420).
  falling,

  /// Kann steigen und fallen (Halve-It, Bob's 27).
  mixed,
}

/// Eine Challenge: feste Aufgabe in einem Trainingsspiel oder ein Match
/// gegen den Computer, 1–3 Sterne nach Schwellen.
class Challenge {
  const Challenge({
    required this.id,
    required this.chapter,
    required this.gameId,
    this.config = const {},
    this.match,
    required this.scoreKey,
    this.liveKey,
    this.thresholds = const [],
    this.lowerIsBetter = false,
    this.needsCompleted = false,
    this.trend = LiveTrend.rising,
    required this.unit,
  });

  /// Stabile Kennung, z. B. `c1-1` (Kapitel 1, Aufgabe 1).
  final String id;
  final ChallengeChapter chapter;

  /// Trainingsspiel aus dem Katalog oder [matchGameId] für ein Match.
  final String gameId;

  /// Feste Einstellungen des Spiels.
  final Map<String, Object?> config;

  /// Gegner und Format, nur bei Matches.
  final MatchChallenge? match;

  /// Kennzahl aus dem Spielergebnis, nach der gewertet und der Bestwert
  /// gespeichert wird.
  final String scoreKey;

  /// Kennzahl für die Live-Anzeige, falls [scoreKey] erst am Ende feststeht
  /// (z. B. `bestLegDarts` → `darts`).
  final String? liveKey;

  /// Schwellen für 1, 2 und 3 Sterne.
  final List<num> thresholds;
  final bool lowerIsBetter;

  /// Nur gültig, wenn das Spiel die Kennzahl `completed` = 1 meldet
  /// (z. B. Bob's 27 überstanden).
  final bool needsCompleted;

  /// Wie sich die Live-Kennzahl entwickelt; bestimmt, ob ein Stern im Spiel
  /// sicher, vorläufig oder schon verloren ist.
  final LiveTrend trend;
  final ChallengeUnit unit;

  bool get isMatch => match != null;

  /// Nummer innerhalb des Kapitels (1–8).
  int get number => int.parse(id.split('-').last);

  GameDefinition? get definition => isMatch ? null : GameCatalog.byId(gameId);

  /// Das Match-Setup gegen den Computer.
  MatchSetup matchSetup({required String playerName, int? profileId}) => MatchSetup(
        format: match!.format,
        players: [
          MatchPlayer.human(playerName, profileId: profileId),
          MatchPlayer.bot('CPU ${match!.botAverage.round()}', average: match!.botAverage),
        ],
      );

  /// Wertungs-Wert eines Ergebnisses; `null`, wenn es keinen gültigen gibt.
  num? scoreOf(Map<String, num> metrics) {
    if (needsCompleted && metrics['completed'] != 1) return null;
    return metrics[scoreKey];
  }

  /// Sterne eines regulär beendeten Spiels.
  int starsFor(Map<String, num> metrics) {
    final m = match;
    if (m != null) {
      if (metrics['won'] != 1) return 0;
      if ((metrics['legsLost'] ?? 0) > 0) return 1;
      return (metrics['average'] ?? 0) >= m.average ? 3 : 2;
    }
    final v = scoreOf(metrics);
    if (v == null) return 0;
    var stars = 0;
    for (final t in thresholds) {
      if (lowerIsBetter ? v <= t : v >= t) stars++;
    }
    return stars;
  }

  /// Ist [a] ein besserer Wert als [b]?
  bool better(num a, num? b) => b == null || (lowerIsBetter ? a < b : a > b);

  /// Zustand der drei Sterne während des Spiels.
  List<StarState> liveStars(Map<String, num> metrics, {required bool over}) {
    final m = match;
    if (m != null) {
      final lostMatch = over && metrics['won'] != 1;
      final lostLeg = (metrics['legsLost'] ?? 0) > 0;
      final avg = metrics['average'] ?? 0;
      final won = metrics['won'] == 1;
      return [
        won ? StarState.reached : (lostMatch ? StarState.lost : StarState.open),
        lostMatch || lostLeg ? StarState.lost : (won ? StarState.reached : StarState.open),
        lostMatch || lostLeg
            ? StarState.lost
            : won
                ? (avg >= m.average ? StarState.reached : StarState.lost)
                : StarState.open,
      ];
    }
    if (over) {
      final stars = starsFor(metrics);
      return [for (var i = 0; i < 3; i++) i < stars ? StarState.reached : StarState.lost];
    }
    final v = metrics[liveKey ?? scoreKey];
    StarState state(num t) {
      if (v == null) return StarState.open;
      final meets = lowerIsBetter ? v <= t : v >= t;
      final improving = lowerIsBetter ? trend == LiveTrend.falling : trend == LiveTrend.rising;
      final worsening = lowerIsBetter ? trend == LiveTrend.rising : trend == LiveTrend.falling;
      if (meets) {
        if (improving) return StarState.reached;
        // Steigende Darts unter der Schwelle: noch offen.
        return worsening ? StarState.open : StarState.provisional;
      }
      return worsening ? StarState.lost : StarState.open;
    }

    return [for (final t in thresholds) state(t)];
  }
}

/// Bestes Ergebnis einer Challenge.
class ChallengeBest {
  const ChallengeBest({required this.challengeId, required this.stars, this.best, required this.attempts, required this.achievedAt});
  final String challengeId;
  final int stars;
  final num? best;
  final int attempts;
  final DateTime achievedAt;
}

/// Ausgang eines Versuchs.
class ChallengeOutcome {
  const ChallengeOutcome({
    required this.challenge,
    required this.stars,
    required this.score,
    required this.previous,
    required this.newBest,
    this.unlockedChallenge,
    this.unlockedChapter,
  });
  final Challenge challenge;
  final int stars;
  final num? score;

  /// Bestes Ergebnis vor diesem Versuch.
  final ChallengeBest? previous;

  /// Neue beste Sternezahl oder neuer Bestwert.
  final bool newBest;

  /// Durch diesen Versuch neu freigeschaltet.
  final Challenge? unlockedChallenge;
  final ChallengeChapter? unlockedChapter;
}

/// Spiel-ID des Matches (für Texte und Symbole).
const String challengeMatchGameId = matchGameId;
