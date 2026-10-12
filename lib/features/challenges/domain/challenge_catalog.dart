import '../../matches/domain/match_result.dart';
import 'challenge.dart';

/// Alle Challenges: fünf Kapitel mit je acht festen Aufgaben. Texte stehen
/// in `challenge_texts.dart`, die Regeln in `docs/ziele-und-challenges.md`.
abstract final class ChallengeCatalog {
  /// Sterne in einem Kapitel, die das nächste freischalten.
  static const int starsToUnlockNext = 12;

  static const List<Challenge> all = [
    // ---------------------------------------------------------- Einsteiger
    Challenge(
      id: 'c1-1',
      chapter: ChallengeChapter.beginner,
      gameId: 'around_the_clock',
      config: {'order': 'ascending', 'includeBull': true, 'ring': 'any', 'multiplierAdvances': false},
      scoreKey: 'darts',
      thresholds: [60, 45, 35],
      lowerIsBetter: true,
      needsCompleted: true,
      unit: ChallengeUnit.darts,
    ),
    Challenge(
      id: 'c1-2',
      chapter: ChallengeChapter.beginner,
      gameId: 'x01',
      config: {'startScore': 101, 'inMode': 'straight', 'outMode': 'double', 'legs': 1, 'dartLimit': 0, 'showSuggestion': true},
      scoreKey: 'bestLegDarts',
      liveKey: 'darts',
      thresholds: [15, 12, 9],
      lowerIsBetter: true,
      unit: ChallengeUnit.darts,
    ),
    Challenge(
      id: 'c1-3',
      chapter: ChallengeChapter.beginner,
      gameId: 'target_practice',
      config: {'number': 20, 'visits': 10},
      scoreKey: 'points',
      thresholds: [300, 400, 500],
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c1-4',
      chapter: ChallengeChapter.beginner,
      gameId: 'bull_drill',
      config: {'visits': 10},
      scoreKey: 'points',
      thresholds: [75, 150, 250],
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c1-5',
      chapter: ChallengeChapter.beginner,
      gameId: 'score_target',
      config: {'target': 60, 'visits': 10},
      scoreKey: 'successes',
      thresholds: [4, 6, 8],
      unit: ChallengeUnit.successes,
    ),
    Challenge(
      id: 'c1-6',
      chapter: ChallengeChapter.beginner,
      gameId: 'shanghai',
      config: {'from': 1, 'to': 7, 'includeBull': false, 'shanghaiWins': false, 'shanghaiBonus': 100},
      scoreKey: 'score',
      thresholds: [40, 70, 100],
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c1-7',
      chapter: ChallengeChapter.beginner,
      gameId: 'golf',
      config: {'holes': 9, 'scoring': 'simple', 'counts': 'last'},
      scoreKey: 'strokes',
      thresholds: [40, 36, 32],
      lowerIsBetter: true,
      needsCompleted: true,
      unit: ChallengeUnit.strokes,
    ),
    Challenge(
      id: 'c1-8',
      chapter: ChallengeChapter.beginner,
      gameId: 'three_hits',
      config: {'order': 'ascending', 'includeBull': true, 'hitsRequired': 2, 'multiplierCounts': true},
      scoreKey: 'darts',
      thresholds: [120, 95, 75],
      lowerIsBetter: true,
      needsCompleted: true,
      unit: ChallengeUnit.darts,
    ),
    // ------------------------------------------------------------- Amateur
    Challenge(
      id: 'c2-1',
      chapter: ChallengeChapter.amateur,
      gameId: matchGameId,
      match: MatchChallenge(botAverage: 50, legsToWin: 2, average: 50),
      scoreKey: 'average',
      unit: ChallengeUnit.average,
    ),
    Challenge(
      id: 'c2-2',
      chapter: ChallengeChapter.amateur,
      gameId: 'x01',
      config: {'startScore': 301, 'inMode': 'straight', 'outMode': 'double', 'legs': 1, 'dartLimit': 0, 'showSuggestion': true},
      scoreKey: 'bestLegDarts',
      liveKey: 'darts',
      thresholds: [24, 18, 15],
      lowerIsBetter: true,
      unit: ChallengeUnit.darts,
    ),
    Challenge(
      id: 'c2-3',
      chapter: ChallengeChapter.amateur,
      gameId: 'checkout',
      config: {'mode': 'random', 'min': 2, 'max': 40, 'attempts': 10, 'dartsPerAttempt': 3, 'showSuggestion': true, 'doubleOut': true},
      scoreKey: 'checkouts',
      thresholds: [3, 5, 7],
      unit: ChallengeUnit.checkouts,
    ),
    Challenge(
      id: 'c2-4',
      chapter: ChallengeChapter.amateur,
      gameId: 'cricket',
      config: {'cricketOrder': 'free', 'marksToClose': 3, 'includeBull': true},
      scoreKey: 'darts',
      thresholds: [75, 60, 48],
      lowerIsBetter: true,
      needsCompleted: true,
      unit: ChallengeUnit.darts,
    ),
    Challenge(
      id: 'c2-5',
      chapter: ChallengeChapter.amateur,
      gameId: 'skip_world',
      config: {'order': 'ascending', 'includeBull': true, 'skipThreshold': 4, 'bullSkippable': false},
      scoreKey: 'points',
      thresholds: [30, 40, 50],
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c2-6',
      chapter: ChallengeChapter.amateur,
      gameId: 'halve_it',
      config: {'preset': 'bermuda', 'rounding': 'down', 'startScore': 0},
      scoreKey: 'score',
      thresholds: [120, 200, 300],
      trend: LiveTrend.mixed,
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c2-7',
      chapter: ChallengeChapter.amateur,
      gameId: 'bobs_27',
      config: {'startScore': 27, 'includeBull': true, 'allowNegative': false},
      scoreKey: 'score',
      thresholds: [1, 100, 200],
      needsCompleted: true,
      trend: LiveTrend.mixed,
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c2-8',
      chapter: ChallengeChapter.amateur,
      gameId: 'one_twenty_one',
      config: {'start': 121, 'dartsPerAttempt': 9, 'rounds': 10, 'failRule': 'back', 'doubleOut': true, 'showSuggestion': true},
      scoreKey: 'checkouts',
      thresholds: [2, 4, 6],
      unit: ChallengeUnit.checkouts,
    ),
    // --------------------------------------------------------- Ligaspieler
    Challenge(
      id: 'c3-1',
      chapter: ChallengeChapter.league,
      gameId: 'x01',
      config: {'startScore': 501, 'inMode': 'straight', 'outMode': 'double', 'legs': 1, 'dartLimit': 0, 'showSuggestion': true},
      scoreKey: 'bestLegDarts',
      liveKey: 'darts',
      thresholds: [30, 24, 21],
      lowerIsBetter: true,
      unit: ChallengeUnit.darts,
    ),
    Challenge(
      id: 'c3-2',
      chapter: ChallengeChapter.league,
      gameId: 'checkout',
      config: {'mode': 'random', 'min': 61, 'max': 80, 'attempts': 10, 'dartsPerAttempt': 6, 'showSuggestion': true, 'doubleOut': true},
      scoreKey: 'checkouts',
      thresholds: [3, 5, 7],
      unit: ChallengeUnit.checkouts,
    ),
    Challenge(
      id: 'c3-3',
      chapter: ChallengeChapter.league,
      gameId: matchGameId,
      match: MatchChallenge(botAverage: 65, legsToWin: 3, average: 65),
      scoreKey: 'average',
      unit: ChallengeUnit.average,
    ),
    Challenge(
      id: 'c3-4',
      chapter: ChallengeChapter.league,
      gameId: 'highscore_hunt',
      config: {'visits': 10},
      scoreKey: 'points',
      thresholds: [550, 650, 750],
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c3-5',
      chapter: ChallengeChapter.league,
      gameId: 'around_the_clock',
      config: {'order': 'ascending', 'includeBull': true, 'ring': 'double', 'multiplierAdvances': false},
      scoreKey: 'darts',
      thresholds: [120, 90, 65],
      lowerIsBetter: true,
      needsCompleted: true,
      unit: ChallengeUnit.darts,
    ),
    Challenge(
      id: 'c3-6',
      chapter: ChallengeChapter.league,
      gameId: 'jdc_challenge',
      config: {},
      scoreKey: 'score',
      thresholds: [300, 450, 600],
      needsCompleted: true,
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c3-7',
      chapter: ChallengeChapter.league,
      gameId: 'doubles_420',
      config: {'includeBull': false, 'order': 'ascending'},
      scoreKey: 'score',
      thresholds: [250, 170, 100],
      lowerIsBetter: true,
      needsCompleted: true,
      trend: LiveTrend.falling,
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c3-8',
      chapter: ChallengeChapter.league,
      gameId: 'catch_40',
      config: {'min': 61, 'max': 100, 'dartsPerTarget': 6, 'doubleOut': true, 'showSuggestion': true},
      scoreKey: 'points',
      thresholds: [30, 45, 60],
      needsCompleted: true,
      unit: ChallengeUnit.points,
    ),
    // --------------------------------------------------------------- Profi
    Challenge(
      id: 'c4-1',
      chapter: ChallengeChapter.pro,
      gameId: 'x01',
      config: {'startScore': 170, 'inMode': 'straight', 'outMode': 'double', 'legs': 1, 'dartLimit': 0, 'showSuggestion': true},
      scoreKey: 'bestLegDarts',
      liveKey: 'darts',
      thresholds: [9, 6, 3],
      lowerIsBetter: true,
      unit: ChallengeUnit.darts,
    ),
    Challenge(
      id: 'c4-2',
      chapter: ChallengeChapter.pro,
      gameId: 'checkout',
      config: {'mode': 'random', 'min': 81, 'max': 120, 'attempts': 10, 'dartsPerAttempt': 3, 'showSuggestion': true, 'doubleOut': true},
      scoreKey: 'checkouts',
      thresholds: [2, 4, 6],
      unit: ChallengeUnit.checkouts,
    ),
    Challenge(
      id: 'c4-3',
      chapter: ChallengeChapter.pro,
      gameId: matchGameId,
      match: MatchChallenge(botAverage: 80, legsToWin: 3, average: 80),
      scoreKey: 'average',
      unit: ChallengeUnit.average,
    ),
    Challenge(
      id: 'c4-4',
      chapter: ChallengeChapter.pro,
      gameId: 'score_target',
      config: {'target': 140, 'visits': 10},
      scoreKey: 'successes',
      thresholds: [1, 2, 4],
      unit: ChallengeUnit.successes,
    ),
    Challenge(
      id: 'c4-5',
      chapter: ChallengeChapter.pro,
      gameId: 'switch_drill',
      config: {'preset': '167', 'rounds': 10},
      scoreKey: 'hits',
      thresholds: [6, 9, 12],
      unit: ChallengeUnit.hits,
    ),
    Challenge(
      id: 'c4-6',
      chapter: ChallengeChapter.pro,
      gameId: 'bobs_27',
      config: {'startScore': 27, 'includeBull': true, 'allowNegative': false},
      scoreKey: 'score',
      thresholds: [300, 500, 700],
      needsCompleted: true,
      trend: LiveTrend.mixed,
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c4-7',
      chapter: ChallengeChapter.pro,
      gameId: 'doubles_ladder',
      config: {'difficulty': 'normal', 'includeBull': true, 'maxVisits': 60},
      scoreKey: 'highestLevel',
      thresholds: [5, 8, 12],
      unit: ChallengeUnit.level,
    ),
    Challenge(
      id: 'c4-8',
      chapter: ChallengeChapter.pro,
      gameId: 'setup_shot',
      config: {'min': 41, 'max': 100, 'leaves': 'classic', 'darts': 30, 'showSuggestion': true},
      scoreKey: 'successes',
      thresholds: [18, 22, 26],
      unit: ChallengeUnit.successes,
    ),
    // ---------------------------------------------------------- Weltklasse
    Challenge(
      id: 'c5-1',
      chapter: ChallengeChapter.worldClass,
      gameId: 'x01',
      config: {'startScore': 501, 'inMode': 'straight', 'outMode': 'double', 'legs': 1, 'dartLimit': 0, 'showSuggestion': true},
      scoreKey: 'bestLegDarts',
      liveKey: 'darts',
      thresholds: [15, 12, 9],
      lowerIsBetter: true,
      unit: ChallengeUnit.darts,
    ),
    Challenge(
      id: 'c5-2',
      chapter: ChallengeChapter.worldClass,
      gameId: matchGameId,
      match: MatchChallenge(botAverage: 100, legsToWin: 4, average: 100),
      scoreKey: 'average',
      unit: ChallengeUnit.average,
    ),
    Challenge(
      id: 'c5-3',
      chapter: ChallengeChapter.worldClass,
      gameId: 'highscore_hunt',
      config: {'visits': 10},
      scoreKey: 'points',
      thresholds: [900, 1050, 1200],
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c5-4',
      chapter: ChallengeChapter.worldClass,
      gameId: 'checkout',
      config: {'mode': 'random', 'min': 121, 'max': 170, 'attempts': 10, 'dartsPerAttempt': 3, 'showSuggestion': true, 'doubleOut': true},
      scoreKey: 'checkouts',
      thresholds: [2, 3, 5],
      unit: ChallengeUnit.checkouts,
    ),
    Challenge(
      id: 'c5-5',
      chapter: ChallengeChapter.worldClass,
      gameId: 'three_in_a_bed',
      config: {'mode': 'wedge', 'order': 'ascending', 'includeBull': false, 'maxVisits': 0},
      scoreKey: 'visits',
      thresholds: [80, 60, 45],
      lowerIsBetter: true,
      needsCompleted: true,
      unit: ChallengeUnit.visits,
    ),
    Challenge(
      id: 'c5-6',
      chapter: ChallengeChapter.worldClass,
      gameId: 'frustration',
      config: {'sequence': 'full', 'setupMin': 80, 'maxVisits': 0},
      scoreKey: 'visits',
      thresholds: [150, 110, 85],
      lowerIsBetter: true,
      needsCompleted: true,
      unit: ChallengeUnit.visits,
    ),
    Challenge(
      id: 'c5-7',
      chapter: ChallengeChapter.worldClass,
      gameId: 'jdc_challenge',
      config: {},
      scoreKey: 'score',
      thresholds: [600, 750, 900],
      needsCompleted: true,
      unit: ChallengeUnit.points,
    ),
    Challenge(
      id: 'c5-8',
      chapter: ChallengeChapter.worldClass,
      gameId: 'exact_score',
      config: {'target': 100, 'visitsPerAttempt': 2, 'overshoot': 'fail', 'attempts': 5},
      scoreKey: 'successes',
      thresholds: [3, 4, 5],
      unit: ChallengeUnit.successes,
    ),
  ];

  static Challenge? byId(String id) => all.where((c) => c.id == id).firstOrNull;

  static List<Challenge> ofChapter(ChallengeChapter chapter) => [for (final c in all) if (c.chapter == chapter) c];
}

/// Fortschritt im Challenge-Modus aus den besten Ergebnissen.
///
/// Regeln:
/// * Kapitel 1 ist offen. Ein Kapitel öffnet sich mit
///   [ChallengeCatalog.starsToUnlockNext] Sternen im vorherigen.
/// * In einem offenen Kapitel ist die erste Challenge offen; jede weitere,
///   sobald eine der beiden davor mindestens einen Stern hat (eine
///   schwere Aufgabe lässt sich also überspringen).
class ChallengeProgress {
  ChallengeProgress(Iterable<ChallengeBest> results) : best = {for (final r in results) r.challengeId: r};

  final Map<String, ChallengeBest> best;

  int starsOf(Challenge c) => best[c.id]?.stars ?? 0;

  int chapterStars(ChallengeChapter chapter) =>
      ChallengeCatalog.ofChapter(chapter).fold(0, (a, c) => a + starsOf(c));

  static int maxStars(ChallengeChapter chapter) => ChallengeCatalog.ofChapter(chapter).length * 3;

  int get totalStars => ChallengeCatalog.all.fold(0, (a, c) => a + starsOf(c));

  bool chapterUnlocked(ChallengeChapter chapter) {
    if (chapter.index == 0) return true;
    final previous = ChallengeChapter.values[chapter.index - 1];
    return chapterUnlocked(previous) && chapterStars(previous) >= ChallengeCatalog.starsToUnlockNext;
  }

  bool unlocked(Challenge c) {
    if (!chapterUnlocked(c.chapter)) return false;
    final list = ChallengeCatalog.ofChapter(c.chapter);
    final i = list.indexOf(c);
    if (i <= 0) return true;
    return starsOf(list[i - 1]) > 0 || (i >= 2 && starsOf(list[i - 2]) > 0);
  }

  /// Nächste offene Challenge nach [c] (im Kapitel, sonst erste des
  /// nächsten Kapitels), falls freigeschaltet.
  Challenge? nextAfter(Challenge c) {
    final i = ChallengeCatalog.all.indexOf(c);
    for (var j = i + 1; j < ChallengeCatalog.all.length; j++) {
      final n = ChallengeCatalog.all[j];
      if (unlocked(n)) return n;
      if (n.chapter != c.chapter) return null;
    }
    return null;
  }
}
