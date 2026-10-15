import 'dart:math' as math;

import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/domain/games/checkout/checkout_rules.dart';
import 'package:dartlab/features/quiz/domain/quiz_answer.dart';
import 'package:dartlab/features/quiz/domain/quiz_config.dart';
import 'package:dartlab/features/quiz/domain/quiz_run.dart';
import 'package:dartlab/features/quiz/domain/quiz_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

List<Segment> r(String names) => [for (final n in names.split(' ')) Segment.tryParse(n)!];

/// Uhr, die nur auf Anweisung weiterläuft.
class FakeClock {
  DateTime now = DateTime(2026, 10, 15, 18);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

QuizRun runOf(List<QuizKey> pool, {QuizConfig config = const QuizConfig(), FakeClock? clock, List<QuizAnswer> history = const []}) =>
    QuizRun(
      config: config,
      scheduler: QuizScheduler(pool: pool, history: history, random: math.Random(1)),
      clock: (clock ?? FakeClock()).call,
    );

void enter(QuizRun run, String names) {
  for (final s in r(names)) {
    run.tap(s);
  }
}

QuizAnswer answer(int score, int darts, {bool correct = true, int ms = 3000}) =>
    QuizAnswer(score: score, darts: darts, correct: correct, ms: ms);

void main() {
  group('Konfiguration', () {
    test('Pool nach Bereich, Darts und nur checkbaren Resten', () {
      expect(const QuizConfig(range: QuizRange.low).pool().length, 39);
      expect(const QuizConfig(range: QuizRange.high).pool().map((k) => k.score), containsAll([159, 169, 170]));
      final checkable = const QuizConfig(range: QuizRange.high, onlyCheckable: true).pool().map((k) => k.score);
      expect(checkable, isNot(contains(169)));
      expect(checkable, contains(170));
      expect(const QuizConfig(range: QuizRange.high, darts: QuizDarts.one, onlyCheckable: true).pool(), isEmpty);
      final mixed = const QuizConfig(darts: QuizDarts.mixed).pool();
      expect(mixed, contains(const QuizKey(57, 1)));
      expect(mixed, isNot(contains(const QuizKey(61, 1))));
      expect(mixed, contains(const QuizKey(120, 2)));
      expect(mixed, isNot(contains(const QuizKey(121, 2))));
    });

    test('JSON hin und zurück', () {
      const c = QuizConfig(mode: QuizMode.timed, range: QuizRange.mid, darts: QuizDarts.two, onlyCheckable: true, out: OutMode.master);
      expect(QuizConfig.fromJson(c.toJson()), c);
      expect(QuizConfig.fromJson(const {}), const QuizConfig());
    });
  });

  group('Ablauf Training', () {
    test('richtiger Weg: Auflösung, Serie, dann nächste Frage', () {
      final clock = FakeClock();
      final run = runOf(const [QuizKey(121, 3)], clock: clock);
      expect(run.phase, QuizPhase.route);
      expect(run.question!.score, 121);
      enter(run, 'T20 T11 D14');
      clock.advance(const Duration(milliseconds: 4200));
      run.submitRoute();
      expect(run.phase, QuizPhase.feedback);
      expect(run.last!.correct, isTrue);
      expect(run.last!.answer.ms, 4200);
      expect(run.last!.routeCheck!.recommended, isTrue);
      expect(run.streak, 1);
      run.next();
      expect(run.phase, QuizPhase.route);
      expect(run.input, isEmpty);
    });

    test('anderer gültiger Weg ist richtig, aber nicht empfohlen', () {
      final run = runOf(const [QuizKey(121, 3)]);
      enter(run, 'T20 T19 D2');
      run.submitRoute();
      expect(run.last!.correct, isTrue);
      expect(run.last!.answer.recommended, isFalse);
    });

    test('falscher Weg setzt die Serie zurück', () {
      final run = runOf(const [QuizKey(40, 3), QuizKey(32, 3)]);
      for (var i = 0; i < 2; i++) {
        enter(run, run.question!.score == 40 ? 'D20' : 'D16');
        run.submitRoute();
        run.next();
      }
      expect(run.streak, 2);
      enter(run, 'S20');
      run.submitRoute();
      expect(run.last!.correct, isFalse);
      expect(run.streak, 0);
      expect(run.summary.bestStreak, 2);
      expect(run.summary.correct, 2);
      expect(run.summary.answered, 3);
    });

    test('Eingabe: höchstens so viele Darts wie übrig, Rückgängig, Miss ignoriert', () {
      final run = runOf(const [QuizKey(80, 2)]);
      enter(run, 'T20 D10 D10');
      expect(run.input.length, 2);
      run.tap(Segment.miss);
      expect(run.input.length, 2);
      run.undo();
      expect(run.input.map((s) => s.name), ['T20']);
      run.clearInput();
      expect(run.canSubmit, isFalse);
      run.submitRoute();
      expect(run.answers, isEmpty);
    });

    test('„Nicht möglich“ bei checkbarem Rest ist falsch', () {
      final run = runOf(const [QuizKey(170, 3)]);
      run.declareImpossible();
      expect(run.phase, QuizPhase.feedback);
      expect(run.last!.correct, isFalse);
      expect(run.last!.answer.impossible, isTrue);
    });

    test('Bogey: „Nicht möglich“, dann stellen', () {
      final run = runOf(const [QuizKey(169, 3)]);
      expect(run.question!.possible, isFalse);
      expect(run.question!.setup, isNotNull);
      run.declareImpossible();
      expect(run.phase, QuizPhase.setup);
      expect(run.answers, isEmpty);
      enter(run, 'T20 T20 S9');
      run.submitSetup();
      expect(run.phase, QuizPhase.feedback);
      expect(run.last!.correct, isTrue);
      expect(run.last!.setupCheck!.leave, 40);
      expect(run.last!.answer.setup.length, 3);
    });

    test('schlecht gestellt zählt als falsch', () {
      final run = runOf(const [QuizKey(169, 3)]);
      run.declareImpossible();
      enter(run, 'S1');
      run.submitSetup();
      expect(run.last!.correct, isFalse);
    });

    test('ohne Stellen reicht „Nicht möglich“', () {
      final run = runOf(const [QuizKey(169, 3)], config: const QuizConfig(askSetup: false));
      run.declareImpossible();
      expect(run.phase, QuizPhase.feedback);
      expect(run.last!.correct, isTrue);
    });

    test('ein Weg für einen Bogey ist falsch', () {
      final run = runOf(const [QuizKey(169, 3)]);
      enter(run, 'T20 T20 BULL');
      run.submitRoute();
      expect(run.last!.correct, isFalse);
    });

    test('Beenden im Training ist ein regulärer Abschluss', () {
      final run = runOf(const [QuizKey(40, 3)]);
      enter(run, 'D20');
      run.submitRoute();
      run.finish();
      expect(run.ended, isTrue);
      expect(run.completed, isTrue);
      run.next();
      run.tap(Segment.double(20));
      expect(run.input, isEmpty);
    });

    test('leerer Pool endet sofort', () {
      final run = runOf(const []);
      expect(run.ended, isTrue);
      expect(run.question, isNull);
    });
  });

  group('Ablauf Zeit', () {
    test('nach jeder Antwort sofort die nächste Frage, Ende nach 60 s', () {
      final clock = FakeClock();
      final run = runOf(const [QuizKey(40, 3), QuizKey(32, 3)], config: const QuizConfig(mode: QuizMode.timed), clock: clock);
      expect(run.remainingTime(), const Duration(seconds: 60));
      enter(run, run.question!.score == 40 ? 'D20' : 'D16');
      clock.advance(const Duration(seconds: 2));
      run.submitRoute();
      expect(run.phase, QuizPhase.route);
      expect(run.last!.correct, isTrue);
      clock.advance(const Duration(seconds: 57));
      expect(run.tick(), isFalse);
      clock.advance(const Duration(seconds: 2));
      enter(run, 'D20');
      run.submitRoute();
      // Nach Ablauf zählt keine Antwort mehr.
      expect(run.ended, isTrue);
      expect(run.answers.length, 1);
      expect(run.completed, isTrue);
      expect(run.endedAt, run.deadline);
    });

    test('vorzeitig beendet zählt nicht als vollständig', () {
      final clock = FakeClock();
      final run = runOf(const [QuizKey(40, 3)], config: const QuizConfig(mode: QuizMode.timed), clock: clock);
      clock.advance(const Duration(seconds: 10));
      run.finish();
      expect(run.completed, isFalse);
    });
  });

  group('Ergebnis', () {
    test('Kennzahlen ohne Wurf-Kennzahlen', () {
      final result = quizResult(const QuizConfig(), [
        answer(40, 3, ms: 2000),
        answer(169, 3, correct: false, ms: 6000),
        answer(121, 3, ms: 4000),
      ]);
      expect(result.metrics['answered'], 3);
      expect(result.metrics['correct'], 2);
      expect(result.metrics['correctRate'], closeTo(2 / 3, 1e-9));
      expect(result.metrics['bestStreak'], 1);
      expect(result.metrics['avgSeconds'], 4.0);
      for (final k in ['darts', 'average', 'highestCheckout', 'checkoutRate', 'first9']) {
        expect(result.metrics.containsKey(k), isFalse, reason: k);
      }
      final back = quizAnswersOf(result.toJson());
      expect(back.length, 3);
      expect(back[1].correct, isFalse);
    });

    test('Antworten hin und zurück', () {
      final a = QuizAnswer(score: 169, darts: 3, correct: true, ms: 5100, impossible: true, setup: r('T20 T20 S17'), recommended: true);
      final b = QuizAnswer.fromJson(a.toJson())!;
      expect(b.impossible, isTrue);
      expect(b.setup.map((s) => s.name), ['T20', 'T20', 'S17']);
      expect(b.recommended, isTrue);
      expect(QuizAnswer.fromJson({'x': 1}), isNull);
    });
  });

  group('Wiederholung schwacher Reste', () {
    test('oft falsche Reste kommen deutlich öfter', () {
      final pool = [for (var s = 2; s <= 40; s += 2) QuizKey(s, 3)];
      final history = [for (var i = 0; i < 4; i++) answer(32, 3, correct: false, ms: 9000)];
      final s = QuizScheduler(pool: pool, history: history, random: math.Random(3));
      var weak = 0;
      for (var i = 0; i < 2000; i++) {
        if (s.next() == const QuizKey(32, 3)) weak++;
      }
      // Gleichverteilt wären es 100; höchstens jede fünfte Frage kann es
      // sein, weil die letzten vier nicht sofort wiederkommen.
      expect(weak, greaterThan(200));
      expect(s.weakest(3).first, const QuizKey(32, 3));
    });

    test('sichere Reste werden seltener, langsame öfter', () {
      final s = QuizScheduler(pool: const [QuizKey(40, 3), QuizKey(32, 3), QuizKey(50, 3)], history: [
        for (var i = 0; i < 3; i++) answer(40, 3, ms: 1500),
        answer(32, 3, ms: 12000),
      ]);
      expect(s.statsOf(const QuizKey(40, 3))!.mastered, isTrue);
      expect(s.weightOf(const QuizKey(40, 3)), lessThan(QuizScheduler.unseenWeight));
      expect(s.weightOf(const QuizKey(32, 3)), greaterThan(QuizScheduler.unseenWeight));
      expect(s.weakest(), [const QuizKey(32, 3)]);
    });

    test('nach ein paar richtigen Antworten sinkt das Gewicht wieder', () {
      final s = QuizScheduler(pool: const [QuizKey(32, 3)], history: [answer(32, 3, correct: false)]);
      final before = s.weightOf(const QuizKey(32, 3));
      for (var i = 0; i < 4; i++) {
        s.record(answer(32, 3, ms: 2000));
      }
      expect(s.weightOf(const QuizKey(32, 3)), lessThan(before / 2));
    });

    test('falsche Frage kommt im Durchgang nach drei anderen wieder', () {
      final pool = [for (var s = 2; s <= 40; s += 2) QuizKey(s, 3)];
      final s = QuizScheduler(pool: pool, random: math.Random(5));
      final first = s.next()!;
      s.record(answer(first.score, 3, correct: false));
      final seen = <QuizKey>[];
      for (var i = 0; i < 4; i++) {
        final k = s.next()!;
        seen.add(k);
        if (k != first) s.record(answer(k.score, 3));
      }
      expect(seen.sublist(0, 3), isNot(contains(first)));
      expect(seen[3], first);
    });

    test('keine direkte Wiederholung', () {
      final s = QuizScheduler(pool: const [QuizKey(40, 3), QuizKey(32, 3)], random: math.Random(9));
      QuizKey? prev;
      for (var i = 0; i < 50; i++) {
        final k = s.next();
        expect(k, isNot(prev));
        s.record(answer(k!.score, 3));
        prev = k;
      }
    });
  });
}
