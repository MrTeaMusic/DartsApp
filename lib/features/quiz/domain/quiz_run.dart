import '../../board/domain/segment.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import '../../games/domain/games/checkout/setup_advisor.dart';
import 'checkout_route.dart';
import 'quiz_answer.dart';
import 'quiz_config.dart';
import 'quiz_scheduler.dart';

/// Abschnitt einer Frage.
enum QuizPhase {
  /// Weg eingeben oder „Nicht möglich“ wählen.
  route,

  /// Nach richtigem „Nicht möglich“: Stell-Darts eingeben.
  setup,

  /// Auflösung (nur im Training, sonst geht es sofort weiter).
  feedback,

  /// Durchgang vorbei.
  finished,
}

/// Eine gestellte Frage mit ihrer Lösung.
class QuizQuestion {
  QuizQuestion(this.key, this.out);
  final QuizKey key;
  final OutMode out;

  int get score => key.score;
  int get darts => key.darts;

  late final bool possible = CheckoutRoutes.possible(score, darts, out);
  late final List<Segment>? recommended = CheckoutRoutes.recommended(score, darts, out);
  late final List<List<Segment>> alternatives = CheckoutRoutes.alternatives(score, darts, out);
  late final SetupPlan? setup = possible ? null : CheckoutRoutes.setupAdvice(score, darts, out);
}

/// Auflösung einer Frage für die Anzeige.
class QuizFeedback {
  const QuizFeedback({required this.question, required this.answer, this.routeCheck, this.setupCheck});
  final QuizQuestion question;
  final QuizAnswer answer;

  /// Prüfung des eingegebenen Wegs (ohne „Nicht möglich“).
  final RouteCheck? routeCheck;

  /// Prüfung der Stell-Darts (nach richtigem „Nicht möglich“).
  final SetupCheck? setupCheck;

  bool get correct => answer.correct;
}

/// Ablauf eines Quiz-Durchgangs, ohne UI und ohne Datenbank.
///
/// Training: Frage → Antwort → Auflösung → [next]. Zeit: nach jeder Antwort
/// sofort die nächste Frage, bis die Zeit um ist ([tick]). Die Uhr wird
/// übergeben, damit Tests die Antwortzeiten bestimmen können.
class QuizRun {
  QuizRun({required this.config, required this.scheduler, required DateTime Function() clock})
      : _clock = clock,
        startedAt = clock() {
    deadline = config.timed ? startedAt.add(Duration(seconds: config.seconds)) : null;
    _ask();
  }

  final QuizConfig config;
  final QuizScheduler scheduler;
  final DateTime Function() _clock;
  final DateTime startedAt;
  late final DateTime? deadline;
  DateTime? endedAt;

  QuizPhase phase = QuizPhase.route;

  /// Aktuelle Frage (`null` nur bei leerem Pool, dann ist der Durchgang
  /// sofort vorbei).
  QuizQuestion? question;
  DateTime _askedAt = DateTime(0);

  /// Eingabe der laufenden Phase (Weg bzw. Stell-Darts).
  final List<Segment> input = [];

  /// Weg der Frage (bleibt nach dem Wechsel in die Stell-Phase leer).
  final List<QuizAnswer> answers = [];

  /// Auflösung der letzten Antwort.
  QuizFeedback? last;

  int streak = 0;

  /// Antworten im Modus Zeit, die beim Ablauf noch offen waren, zählen nicht.
  bool get ended => phase == QuizPhase.finished;

  QuizSummary get summary => QuizSummary.of(answers);

  Duration? remainingTime([DateTime? now]) {
    final d = deadline;
    if (d == null) return null;
    final left = d.difference(now ?? _clock());
    return left.isNegative ? Duration.zero : left;
  }

  /// Darts, die in der laufenden Phase eingegeben werden dürfen.
  int get maxInput => question?.darts ?? 0;

  bool get canSubmit => (phase == QuizPhase.route || phase == QuizPhase.setup) && input.isNotEmpty;

  void _ask() {
    final key = scheduler.next();
    if (key == null) {
      _finish();
      return;
    }
    question = QuizQuestion(key, config.out);
    input.clear();
    phase = QuizPhase.route;
    _askedAt = _clock();
  }

  /// Feld antippen.
  void tap(Segment s) {
    if (phase != QuizPhase.route && phase != QuizPhase.setup) return;
    if (s.isMiss || input.length >= maxInput) return;
    input.add(s);
  }

  void undo() {
    if (input.isNotEmpty && (phase == QuizPhase.route || phase == QuizPhase.setup)) input.removeLast();
  }

  void clearInput() {
    if (phase == QuizPhase.route || phase == QuizPhase.setup) input.clear();
  }

  /// Eingegebenen Weg als Checkout prüfen.
  void submitRoute() {
    final q = question;
    if (q == null || phase != QuizPhase.route || input.isEmpty || _expired()) return;
    final check = CheckoutRoutes.check(q.score, q.darts, List.of(input), config.out);
    _answer(QuizFeedback(
      question: q,
      routeCheck: check,
      answer: QuizAnswer(
        score: q.score,
        darts: q.darts,
        correct: check.valid,
        ms: _elapsed(),
        route: check.route,
        recommended: check.recommended,
      ),
    ));
  }

  /// „Nicht möglich“: richtig, wenn der Rest mit den übrigen Darts nicht
  /// checkbar ist. Dann (falls eingestellt) weiter zum Stellen.
  void declareImpossible() {
    final q = question;
    if (q == null || phase != QuizPhase.route || _expired()) return;
    if (!q.possible && config.askSetup && q.setup != null) {
      input.clear();
      phase = QuizPhase.setup;
      return;
    }
    _answer(QuizFeedback(
      question: q,
      answer: QuizAnswer(score: q.score, darts: q.darts, correct: !q.possible, ms: _elapsed(), impossible: true),
    ));
  }

  /// Stell-Darts prüfen.
  void submitSetup() {
    final q = question;
    if (q == null || phase != QuizPhase.setup || input.isEmpty || _expired()) return;
    final check = CheckoutRoutes.checkSetup(q.score, q.darts, List.of(input), config.out);
    _answer(QuizFeedback(
      question: q,
      setupCheck: check,
      answer: QuizAnswer(
        score: q.score,
        darts: q.darts,
        correct: check.good,
        ms: _elapsed(),
        impossible: true,
        setup: check.route,
        recommended: check.recommended,
      ),
    ));
  }

  void _answer(QuizFeedback f) {
    answers.add(f.answer);
    scheduler.record(f.answer);
    streak = f.correct ? streak + 1 : 0;
    last = f;
    input.clear();
    if (config.timed) {
      _ask();
    } else {
      phase = QuizPhase.feedback;
    }
  }

  /// Nach der Auflösung zur nächsten Frage.
  void next() {
    if (phase != QuizPhase.feedback) return;
    _ask();
  }

  /// Zeit prüfen; `true`, wenn der Durchgang gerade dadurch endete.
  bool tick() {
    if (ended || deadline == null) return false;
    if (_clock().isBefore(deadline!)) return false;
    _finish(at: deadline);
    return true;
  }

  bool _expired() => tick() || ended;

  /// Durchgang beenden (Training: „Beenden“, Zeit: vorzeitig aufhören).
  void finish() {
    if (!ended) _finish();
  }

  void _finish({DateTime? at}) {
    phase = QuizPhase.finished;
    input.clear();
    endedAt = at ?? _clock();
  }

  /// Regulär zu Ende: im Training immer, im Modus Zeit nur, wenn die Zeit
  /// abgelaufen ist (vorzeitig beendet zählt nicht für den Rekord).
  bool get completed {
    if (!ended) return false;
    final d = deadline;
    return d == null || !endedAt!.isBefore(d);
  }

  int _elapsed() => _clock().difference(_askedAt).inMilliseconds;
}
