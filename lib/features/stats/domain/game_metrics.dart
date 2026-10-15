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
    'x01': PrimaryMetric('average'),
    'x01_match': PrimaryMetric('average'),
    'halve_it': PrimaryMetric('score', format: MetricFormat.integer),
    'catch_40': PrimaryMetric('points', format: MetricFormat.integer, onlyCompleted: true),
    'jdc_challenge': PrimaryMetric('score', format: MetricFormat.integer, onlyCompleted: true),
    'shanghai': PrimaryMetric('score', format: MetricFormat.integer),
    'golf': PrimaryMetric('averagePerHole', higherIsBetter: false),
    'doubles_420': PrimaryMetric('score', higherIsBetter: false, format: MetricFormat.integer, onlyCompleted: true),
    'frustration': PrimaryMetric('visits', higherIsBetter: false, format: MetricFormat.integer, onlyCompleted: true),
    'switch_drill': PrimaryMetric('hitRate', format: MetricFormat.percent),
    'doubles_ladder': PrimaryMetric('highestLevel', format: MetricFormat.integer),
    'exact_score': PrimaryMetric('successRate', format: MetricFormat.percent),
    'three_in_a_bed': PrimaryMetric('visits', higherIsBetter: false, format: MetricFormat.integer, onlyCompleted: true),
    'setup_shot': PrimaryMetric('successRate', format: MetricFormat.percent),
    // Autodarts Live: Rohpunkte aller Darts bzw. mit „X01 mitzählen“ der
    // Average wie im Match (Bust-Aufnahmen zählen 0).
    'autodarts_live': PrimaryMetric('rawAverage'),
    'x01_live': PrimaryMetric('average'),
    // Checkout-Quiz: Anteil richtiger Antworten (vergleichbar über beide
    // Modi und jede Länge).
    'checkout_quiz': PrimaryMetric('correctRate', format: MetricFormat.percent),
  };

  /// Hauptkennzahl eines Spiels. Spiele ohne Eintrag (z. B. neu
  /// hinzugekommene) nutzen ihren 3-Dart-Average, falls sie einen melden.
  static PrimaryMetric forGame(String gameId) => byGame[gameId] ?? fallback;

  static const PrimaryMetric fallback = PrimaryMetric('average');
}

/// Spiele, deren Würfe in den 3-Dart-Average eingehen (dort wird auf Punkte
/// geworfen, nicht auf bestimmte Felder).
///
/// Autodarts Live ohne X01: DartLab kennt dort nur die Felder, gezählt
/// werden die Rohpunkte aller Darts.
const Set<String> scoringGames = {'target_practice', 'score_target', 'highscore_hunt', 'autodarts_live'};

/// Spiele, deren volle Aufnahmen in die Punkteverteilung und Konstanz
/// eingehen: die Scoring-Spiele und X01-Varianten.
bool isVisitScoringGame(String gameId) => scoringGames.contains(gameId) || gameId.startsWith('x01');

/// Spiele ohne Würfe (Checkout-Quiz): Ihre Sessions zählen als Training
/// (Sessions, Trainingstage, Trainingszeit), haben aber keine Darts und
/// gehen in keine Wurf-Kennzahl ein. Die Oberfläche zeigt bei ihnen die Zahl
/// der Fragen statt der Darts.
const Set<String> throwlessGames = {'checkout_quiz'};

/// Kennzahlen, die keinen sinnvollen Verlauf ergeben.
const Set<String> nonTrendMetrics = {'completed'};
