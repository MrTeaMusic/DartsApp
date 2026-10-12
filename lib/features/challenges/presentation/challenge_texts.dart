import '../../../core/l10n.dart';
import '../../games/domain/engine/game_display.dart';
import '../domain/challenge.dart';

/// Texte des Challenge-Modus.
extension ChallengeTexts on AppLocalizations {
  String chapterName(ChallengeChapter c) => switch (c) {
        ChallengeChapter.beginner => chalChapterBeginner,
        ChallengeChapter.amateur => chalChapterAmateur,
        ChallengeChapter.league => chalChapterLeague,
        ChallengeChapter.pro => chalChapterPro,
        ChallengeChapter.worldClass => chalChapterWorldClass,
      };

  String challengeName(Challenge c) => switch (c.id) {
        'c1-1' => chal1x1Name,
        'c1-2' => chal1x2Name,
        'c1-3' => chal1x3Name,
        'c1-4' => chal1x4Name,
        'c1-5' => chal1x5Name,
        'c1-6' => chal1x6Name,
        'c1-7' => chal1x7Name,
        'c1-8' => chal1x8Name,
        'c2-1' => chal2x1Name,
        'c2-2' => chal2x2Name,
        'c2-3' => chal2x3Name,
        'c2-4' => chal2x4Name,
        'c2-5' => chal2x5Name,
        'c2-6' => chal2x6Name,
        'c2-7' => chal2x7Name,
        'c2-8' => chal2x8Name,
        'c3-1' => chal3x1Name,
        'c3-2' => chal3x2Name,
        'c3-3' => chal3x3Name,
        'c3-4' => chal3x4Name,
        'c3-5' => chal3x5Name,
        'c3-6' => chal3x6Name,
        'c3-7' => chal3x7Name,
        'c3-8' => chal3x8Name,
        'c4-1' => chal4x1Name,
        'c4-2' => chal4x2Name,
        'c4-3' => chal4x3Name,
        'c4-4' => chal4x4Name,
        'c4-5' => chal4x5Name,
        'c4-6' => chal4x6Name,
        'c4-7' => chal4x7Name,
        'c4-8' => chal4x8Name,
        'c5-1' => chal5x1Name,
        'c5-2' => chal5x2Name,
        'c5-3' => chal5x3Name,
        'c5-4' => chal5x4Name,
        'c5-5' => chal5x5Name,
        'c5-6' => chal5x6Name,
        'c5-7' => chal5x7Name,
        'c5-8' => chal5x8Name,
        _ => c.id,
      };

  String challengeTask(Challenge c) => switch (c.id) {
        'c1-1' => chal1x1Task,
        'c1-2' => chal1x2Task,
        'c1-3' => chal1x3Task,
        'c1-4' => chal1x4Task,
        'c1-5' => chal1x5Task,
        'c1-6' => chal1x6Task,
        'c1-7' => chal1x7Task,
        'c1-8' => chal1x8Task,
        'c2-1' => chal2x1Task,
        'c2-2' => chal2x2Task,
        'c2-3' => chal2x3Task,
        'c2-4' => chal2x4Task,
        'c2-5' => chal2x5Task,
        'c2-6' => chal2x6Task,
        'c2-7' => chal2x7Task,
        'c2-8' => chal2x8Task,
        'c3-1' => chal3x1Task,
        'c3-2' => chal3x2Task,
        'c3-3' => chal3x3Task,
        'c3-4' => chal3x4Task,
        'c3-5' => chal3x5Task,
        'c3-6' => chal3x6Task,
        'c3-7' => chal3x7Task,
        'c3-8' => chal3x8Task,
        'c4-1' => chal4x1Task,
        'c4-2' => chal4x2Task,
        'c4-3' => chal4x3Task,
        'c4-4' => chal4x4Task,
        'c4-5' => chal4x5Task,
        'c4-6' => chal4x6Task,
        'c4-7' => chal4x7Task,
        'c4-8' => chal4x8Task,
        'c5-1' => chal5x1Task,
        'c5-2' => chal5x2Task,
        'c5-3' => chal5x3Task,
        'c5-4' => chal5x4Task,
        'c5-5' => chal5x5Task,
        'c5-6' => chal5x6Task,
        'c5-7' => chal5x7Task,
        'c5-8' => chal5x8Task,
        _ => '',
      };

  /// Kürzel wie „Einsteiger · 3“.
  String challengeCode(Challenge c) => chalCode(chapterName(c.chapter), c.number);

  String challengeUnit(ChallengeUnit u) => switch (u) {
        ChallengeUnit.darts => chalUnitDarts,
        ChallengeUnit.points => chalUnitPoints,
        ChallengeUnit.checkouts => chalUnitCheckouts,
        ChallengeUnit.successes => chalUnitSuccesses,
        ChallengeUnit.hits => chalUnitHits,
        ChallengeUnit.strokes => chalUnitStrokes,
        ChallengeUnit.visits => chalUnitVisits,
        ChallengeUnit.level => chalUnitLevel,
        ChallengeUnit.average => chalUnitAverage,
      };

  /// Bedingung für den Stern [star] (1–3), z. B. „höchstens 45 Darts“.
  String starRule(Challenge c, int star) {
    final m = c.match;
    if (m != null) {
      return switch (star) {
        1 => chalMatchStar1,
        2 => chalMatchStar2,
        _ => chalMatchStar3(m.average.round()),
      };
    }
    final v = challengeValue(c, c.thresholds[star - 1]);
    if (c.unit == ChallengeUnit.level) return chalAtLeastLevel(v);
    final u = challengeUnit(c.unit);
    return c.lowerIsBetter ? chalAtMost(v, u) : chalAtLeast(v, u);
  }

  /// Wert mit Einheit, z. B. „45 Darts“ oder „Stufe 8“.
  String challengeValueWithUnit(Challenge c, num v) {
    final s = challengeValue(c, v);
    if (c.unit == ChallengeUnit.level) return '$chalUnitLevel $s';
    return '$s ${challengeUnit(c.unit)}';
  }
}

/// Zahl einer Wertung: Average mit Nachkommastelle, sonst ganzzahlig.
String challengeValue(Challenge c, num v) =>
    c.unit == ChallengeUnit.average ? formatDecimal(v) : v.round().toString();
