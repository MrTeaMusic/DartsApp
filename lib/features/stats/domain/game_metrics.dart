/// Wie eine Kennzahl dargestellt wird.
enum MetricFormat { percent, decimal, integer }

/// Die Hauptkennzahl eines Spiels für Verlauf und Rekorde.
class PrimaryMetric {
  const PrimaryMetric(this.key, {this.higherIsBetter = true, this.format = MetricFormat.decimal, this.onlyCompleted = false});

  /// Schlüssel in `GameResult.metrics`.
  final String key;
  final bool higherIsBetter;
  final MetricFormat format;

  /// Nur vollständig gespielte Sessions zählen (z. B. benötigte Darts).
  final bool onlyCompleted;

  /// Hauptkennzahl je Spiel-ID. Neue Spiele hier eintragen, sonst gibt es
  /// für sie keinen Verlauf.
  static const Map<String, PrimaryMetric> byGame = {
    'checkout': PrimaryMetric('checkoutRate', format: MetricFormat.percent),
    'around_the_clock': PrimaryMetric('darts', higherIsBetter: false, format: MetricFormat.integer, onlyCompleted: true),
    'bull_drill': PrimaryMetric('bullRate', format: MetricFormat.percent),
    'target_practice': PrimaryMetric('average'),
    'score_target': PrimaryMetric('successRate', format: MetricFormat.percent),
    'highscore_hunt': PrimaryMetric('average'),
    'cricket': PrimaryMetric('mpr'),
    'one_twenty_one': PrimaryMetric('highestCheckout', format: MetricFormat.integer),
    'bobs_27': PrimaryMetric('score', format: MetricFormat.integer),
    'three_hits': PrimaryMetric('darts', higherIsBetter: false, format: MetricFormat.integer, onlyCompleted: true),
    'skip_world': PrimaryMetric('points', format: MetricFormat.integer),
  };

  /// Hauptkennzahl eines Spiels. Spiele ohne Eintrag (z. B. neu
  /// hinzugekommene) nutzen ihren 3-Dart-Average, falls sie einen melden.
  static PrimaryMetric forGame(String gameId) => byGame[gameId] ?? fallback;

  static const PrimaryMetric fallback = PrimaryMetric('average');
}

/// Spiele, deren Würfe in den 3-Dart-Average eingehen (dort wird auf Punkte
/// geworfen, nicht auf bestimmte Felder).
const Set<String> scoringGames = {'target_practice', 'score_target', 'highscore_hunt'};

/// Spiele, deren volle Aufnahmen in die Punkteverteilung und Konstanz
/// eingehen: die Scoring-Spiele und X01-Varianten.
bool isVisitScoringGame(String gameId) => scoringGames.contains(gameId) || gameId.startsWith('x01');

/// Kennzahlen, die keinen sinnvollen Verlauf ergeben.
const Set<String> nonTrendMetrics = {'completed'};
