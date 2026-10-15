import '../../board/domain/segment.dart';
import '../../games/domain/engine/game_display.dart';
import 'quiz_config.dart';

/// Eine beantwortete Frage, so wie sie gespeichert wird.
class QuizAnswer {
  const QuizAnswer({
    required this.score,
    required this.darts,
    required this.correct,
    required this.ms,
    this.impossible = false,
    this.route = const [],
    this.setup = const [],
    this.recommended = false,
  });

  final int score;
  final int darts;

  /// Richtig beantwortet: gültiger Checkout, bzw. bei nicht checkbaren
  /// Resten „Nicht möglich“ und (falls gefragt) gut gestellt.
  final bool correct;

  /// Antwortzeit in Millisekunden (Frage gezeigt bis Antwort fertig).
  final int ms;

  /// „Nicht möglich“ gewählt.
  final bool impossible;

  /// Eingegebener Checkout-Weg (leer bei „Nicht möglich“).
  final List<Segment> route;

  /// Eingegebene Stell-Darts (nur nach „Nicht möglich“).
  final List<Segment> setup;

  /// Weg bzw. Rest wie von der App vorgeschlagen.
  final bool recommended;

  QuizKey get key => QuizKey(score, darts);

  Map<String, Object?> toJson() => {
        'score': score,
        'darts': darts,
        'correct': correct,
        'ms': ms,
        if (impossible) 'impossible': true,
        if (route.isNotEmpty) 'route': [for (final s in route) s.name],
        if (setup.isNotEmpty) 'setup': [for (final s in setup) s.name],
        if (recommended) 'recommended': true,
      };

  static List<Segment> _segments(Object? list) => [
        if (list is List)
          for (final n in list)
            ?Segment.tryParse('$n'),
      ];

  /// `null` bei unlesbaren Einträgen.
  static QuizAnswer? fromJson(Object? j) {
    if (j is! Map) return null;
    final score = j['score'], darts = j['darts'], ms = j['ms'];
    if (score is! num || darts is! num) return null;
    return QuizAnswer(
      score: score.toInt(),
      darts: darts.toInt(),
      correct: j['correct'] == true,
      ms: ms is num ? ms.toInt() : 0,
      impossible: j['impossible'] == true,
      route: _segments(j['route']),
      setup: _segments(j['setup']),
      recommended: j['recommended'] == true,
    );
  }
}

/// Kennzahlen eines Durchgangs.
class QuizSummary {
  const QuizSummary({
    required this.answered,
    required this.correct,
    required this.bestStreak,
    required this.averageMs,
    required this.recommended,
  });

  factory QuizSummary.of(List<QuizAnswer> answers) {
    var correct = 0, run = 0, best = 0, ms = 0, rec = 0;
    for (final a in answers) {
      ms += a.ms;
      if (a.recommended) rec++;
      if (a.correct) {
        correct++;
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return QuizSummary(
      answered: answers.length,
      correct: correct,
      bestStreak: best,
      averageMs: answers.isEmpty ? null : ms / answers.length,
      recommended: rec,
    );
  }

  final int answered;
  final int correct;
  final int bestStreak;
  final double? averageMs;

  /// Antworten wie der Vorschlag der App.
  final int recommended;

  double? get rate => answered == 0 ? null : correct / answered;
  double? get averageSeconds => averageMs == null ? null : averageMs! / 1000;

  /// Kennzahlen für Verlauf und Statistik. Bewusst ohne `darts`,
  /// `average` oder `highestCheckout`: das Quiz wirft keine Darts und darf
  /// in keine Wurf-Kennzahl eingehen.
  Map<String, num> get metrics => {
        'answered': answered,
        'correct': correct,
        'correctRate': ?rate,
        'bestStreak': bestStreak,
        if (averageSeconds != null) 'avgSeconds': double.parse(averageSeconds!.toStringAsFixed(2)),
      };
}

/// Ergebnis zum Speichern (Session ohne Würfe).
GameResult quizResult(QuizConfig config, List<QuizAnswer> answers) {
  final s = QuizSummary.of(answers);
  return GameResult(
    metrics: s.metrics,
    summary: quizStats(s),
    details: {
      'mode': config.mode.name,
      'answers': [for (final a in answers) a.toJson()],
    },
  );
}

/// Kennzahlen-Zeilen (Schlüssel siehe `GameTexts.statLabel`).
List<GameStat> quizStats(QuizSummary s) => [
      GameStat('quizCorrect', '${s.correct} / ${s.answered}'),
      GameStat('correctRate', formatPercent(s.rate)),
      GameStat('bestStreak', '${s.bestStreak}'),
      GameStat('quizPace', s.averageSeconds == null ? '–' : '${formatDecimal(s.averageSeconds)} s'),
    ];

/// Liest die Antworten aus dem gespeicherten Ergebnis einer Quiz-Session.
List<QuizAnswer> quizAnswersOf(Map<String, Object?> result) {
  final details = result['details'];
  final list = details is Map ? details['answers'] : null;
  return [
    if (list is List)
      for (final j in list)
        ?QuizAnswer.fromJson(j),
  ];
}
