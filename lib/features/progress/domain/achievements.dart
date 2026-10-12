import '../../games/domain/game_catalog.dart';

/// Gruppen der Erfolge (Reihenfolge der Anzeige).
enum AchievementGroup { scoring, finish, doubles, endurance, games }

/// Wert, an dem ein Erfolg gemessen wird. Den Stand liefert der
/// `AchievementTracker`.
enum AchievementMetric {
  /// Aufnahmen mit mindestens 100 / 140 Punkten, 180er.
  tons,
  visits140,
  max180,

  /// Bester 3-Dart-Average einer Session (mindestens 18 Darts).
  bestAverage,

  /// Höchstes Finish, Zahl der Finishes, Bull-Finishes.
  highestCheckout,
  checkouts,
  bullFinishes,

  /// Wenigste Darts für ein gewonnenes 501-Leg (mit Double- oder Master-Out).
  fastest501,

  /// Bester Endstand in Bob's 27 (überstanden, Start 27), überstandene Spiele.
  bobsScore,
  bobsSurvived,

  /// Doppel in Folge (Darts mit einem Doppel als Ziel), Doppeltreffer gesamt.
  doubleRun,
  doubleHits,

  /// Gezählte Darts, Trainingsstunden.
  darts,
  hours,

  /// Längste Serie mit erreichtem Tagesziel, Tage mit erreichtem Tagesziel.
  goalStreak,
  goalDays,

  /// Verschiedene Trainingsspiele, regulär beendet.
  gamesPlayed,

  /// Gewonnene Matches gegen den Computer, Turniersiege, Neun-Darter.
  cpuWins,
  tournamentWins,
  nineDarters,

  /// Shanghais (Shanghai, JDC-Challenge).
  shanghais,

  /// Sterne aus Challenges.
  challengeStars,
}

/// Ein Erfolg mit einer oder drei Stufen (Bronze, Silber, Gold).
class AchievementDef {
  const AchievementDef(this.id, this.group, this.metric, this.thresholds, {this.lowerIsBetter = false});

  /// Stabile Kennung, wird in der Datenbank gespeichert.
  final String id;
  final AchievementGroup group;
  final AchievementMetric metric;

  /// Schwellen je Stufe, aufsteigend schwerer.
  final List<num> thresholds;

  /// Weniger ist besser (z. B. Darts für ein Leg).
  final bool lowerIsBetter;

  bool get tiered => thresholds.length > 1;
  int get maxTier => thresholds.length;

  /// Erreichte Stufe (0 = keine) bei Wert [value].
  int tierFor(num? value) {
    if (value == null) return 0;
    var tier = 0;
    for (final t in thresholds) {
      if (lowerIsBetter ? value <= t : value >= t) tier++;
    }
    return tier;
  }
}

/// Alle Erfolge. Neue hier eintragen und Texte in `progress_texts.dart`.
abstract final class AchievementCatalog {
  static final List<AchievementDef> all = [
    // Scoring
    const AchievementDef('first_100', AchievementGroup.scoring, AchievementMetric.tons, [1]),
    const AchievementDef('first_140', AchievementGroup.scoring, AchievementMetric.visits140, [1]),
    const AchievementDef('first_180', AchievementGroup.scoring, AchievementMetric.max180, [1]),
    const AchievementDef('many_180', AchievementGroup.scoring, AchievementMetric.max180, [10, 50, 100]),
    const AchievementDef('tons', AchievementGroup.scoring, AchievementMetric.tons, [25, 100, 500]),
    const AchievementDef('average', AchievementGroup.scoring, AchievementMetric.bestAverage, [50, 70, 90]),
    // Finish
    const AchievementDef('finish_100', AchievementGroup.finish, AchievementMetric.highestCheckout, [101]),
    const AchievementDef('finish_170', AchievementGroup.finish, AchievementMetric.highestCheckout, [170]),
    const AchievementDef('finish_bull', AchievementGroup.finish, AchievementMetric.bullFinishes, [1]),
    const AchievementDef('checkouts', AchievementGroup.finish, AchievementMetric.checkouts, [25, 100, 500]),
    const AchievementDef('fast_leg', AchievementGroup.finish, AchievementMetric.fastest501, [30, 21, 15], lowerIsBetter: true),
    // Doppel
    const AchievementDef('bobs_200', AchievementGroup.doubles, AchievementMetric.bobsScore, [200]),
    const AchievementDef('bobs_survive', AchievementGroup.doubles, AchievementMetric.bobsSurvived, [1]),
    const AchievementDef('double_run', AchievementGroup.doubles, AchievementMetric.doubleRun, [5]),
    const AchievementDef('double_hits', AchievementGroup.doubles, AchievementMetric.doubleHits, [100, 500, 2000]),
    // Ausdauer
    const AchievementDef('darts', AchievementGroup.endurance, AchievementMetric.darts, [1000, 10000, 100000]),
    const AchievementDef('goal_streak', AchievementGroup.endurance, AchievementMetric.goalStreak, [7, 30, 100]),
    const AchievementDef('goal_days', AchievementGroup.endurance, AchievementMetric.goalDays, [10, 50, 200]),
    const AchievementDef('hours', AchievementGroup.endurance, AchievementMetric.hours, [10, 50, 200]),
    // Spiele
    AchievementDef('all_games', AchievementGroup.games, AchievementMetric.gamesPlayed, [GameCatalog.all.length]),
    const AchievementDef('cpu_wins', AchievementGroup.games, AchievementMetric.cpuWins, [1, 10, 50]),
    const AchievementDef('tournament', AchievementGroup.games, AchievementMetric.tournamentWins, [1]),
    const AchievementDef('nine_darter', AchievementGroup.games, AchievementMetric.nineDarters, [1]),
    const AchievementDef('shanghai', AchievementGroup.games, AchievementMetric.shanghais, [1]),
    const AchievementDef('stars', AchievementGroup.games, AchievementMetric.challengeStars, [30, 60, 120]),
  ];

  static AchievementDef? byId(String id) => all.where((a) => a.id == id).firstOrNull;

  /// Alle Stufen zusammen (eine Medaille je Stufe).
  static int get totalTiers => all.fold(0, (a, d) => a + d.maxTier);
}

/// Schlüssel einer Stufe, z. B. `many_180#2`.
String tierKey(String id, int tier) => '$id#$tier';
