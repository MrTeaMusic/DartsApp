import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/history/domain/session_history.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/progress/domain/achievement_tracker.dart';
import 'package:dartlab/features/progress/domain/achievements.dart';
import 'package:dartlab/features/progress/domain/daily_goal.dart';
import 'package:dartlab/features/progress/domain/session_facts.dart';
import 'package:dartlab/features/quiz/data/quiz_repository.dart';
import 'package:dartlab/features/quiz/domain/quiz_answer.dart';
import 'package:dartlab/features/quiz/domain/quiz_config.dart';
import 'package:dartlab/features/stats/data/stats_repository.dart';
import 'package:dartlab/features/stats/domain/game_metrics.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/history_seed.dart';

QuizAnswer a(int score, {bool correct = true, int ms = 3000, int darts = 3}) =>
    QuizAnswer(score: score, darts: darts, correct: correct, ms: ms, route: score <= 40 ? [Segment.double(score ~/ 2)] : const []);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late AppDatabase db;
  late int me;
  late QuizRepository quiz;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    me = await ProfileRepository(db).resolve(null);
    quiz = QuizRepository(db);
  });
  tearDown(() => db.close());

  Future<StatsCalculator> calc() async {
    final rows = await (db.select(db.sessions)..where((s) => s.endedAt.isNotNull() & s.deletedAt.isNull())).get();
    return (await CalculatorLoader(db, me).next(rows))!;
  }

  test('Spiel-ID stimmt mit der Hauptkennzahl überein', () {
    expect(PrimaryMetric.byGame.containsKey(checkoutQuizGameId), isTrue);
    expect(PrimaryMetric.forGame(checkoutQuizGameId).key, 'correctRate');
    expect(throwlessGames, contains(checkoutQuizGameId));
  });

  test('speichert eine Session ohne Würfe, mit Antworten und Bestwerten', () async {
    final start = DateTime(2026, 10, 15, 18);
    final id = await quiz.save(
      playerId: me,
      config: const QuizConfig(mode: QuizMode.timed),
      answers: [a(40), a(32), a(169, correct: false, ms: 8000), a(16)],
      startedAt: start,
      endedAt: start.add(const Duration(seconds: 60)),
      finished: true,
    );
    final row = await (db.select(db.sessions)..where((s) => s.id.equals(id!))).getSingle();
    expect(row.gameId, checkoutQuizGameId);
    expect(row.dartCount, 0);
    expect(row.finished, isTrue);
    expect(row.endedAt, isNotNull);
    expect(await db.select(db.throws).get(), isEmpty);
    final m = StatsCalculator.metricsOf(row);
    expect(m['correct'], 3);
    expect(m['answered'], 4);
    expect(m['bestStreak'], 2);
    expect(QuizConfig.fromJson(StatsCalculator.decode(row.configJson)).timed, isTrue);

    final history = await quiz.history(me);
    expect(history.map((x) => x.score), [40, 32, 169, 16]);
    final bests = await quiz.bests(me);
    expect(bests.timedCorrect, 3);
    expect(bests.bestStreak, 2);
    expect(bests.fastestSeconds, isNull, reason: 'erst ab 10 Antworten');

    // Erscheint wie andere Sessions in „Zuletzt gespielt“.
    final recent = await (db.select(db.sessions)..where((s) => s.endedAt.isNotNull())).get();
    expect(recent.single.id, id);
  });

  test('ohne Antworten wird nichts gespeichert', () async {
    final id = await quiz.save(
      playerId: me,
      config: const QuizConfig(),
      answers: const [],
      startedAt: DateTime(2026),
      endedAt: DateTime(2026),
      finished: false,
    );
    expect(id, isNull);
    expect(await db.select(db.sessions).get(), isEmpty);
  });

  test('vorzeitig beendetes Zeit-Quiz zählt nicht für den Zeit-Rekord', () async {
    final start = DateTime(2026, 10, 15, 18);
    await quiz.save(
      playerId: me,
      config: const QuizConfig(mode: QuizMode.timed),
      answers: [for (var i = 0; i < 12; i++) a(40, ms: 2000)],
      startedAt: start,
      endedAt: start.add(const Duration(seconds: 30)),
      finished: false,
    );
    final bests = await quiz.bests(me);
    expect(bests.timedCorrect, isNull);
    expect(bests.bestStreak, 12);
    expect(bests.fastestSeconds, 2.0);
  });

  test('Statistik: Quiz zählt als Session, aber in keine Wurf-Kennzahl', () async {
    final repo = GameRepository(db);
    final day = DateTime.now().subtract(const Duration(days: 1));
    await seedTraining(repo, me, 'highscore_hunt', const {'visits': 10}, day.subtract(const Duration(hours: 3)));
    await seedTraining(repo, me, 'checkout', const {'attempts': 10}, day.subtract(const Duration(hours: 2)), seed: 3);
    final before = await calc();

    await quiz.save(
      playerId: me,
      config: const QuizConfig(),
      answers: [a(170, ms: 4000), a(121, correct: false), a(50)],
      startedAt: day,
      endedAt: day.add(const Duration(minutes: 5)),
      finished: true,
    );
    final after = await calc();

    for (final p in StatsPeriod.values) {
      final b = before.report(p), x = after.report(p);
      expect(x.sessions, b.sessions + 1, reason: '$p');
      expect(x.darts, b.darts);
      expect(x.scoringAverage, b.scoringAverage);
      expect(x.scoringDarts, b.scoringDarts);
      expect(x.checkoutRate, b.checkoutRate);
      expect(x.checkoutAttempts, b.checkoutAttempts);
      expect(x.doubleAttempts, b.doubleAttempts);
      expect(x.accuracy.attempts, b.accuracy.attempts);
      expect(x.heat.length, b.heat.length);
      expect([for (final d in x.dailyDarts) d.darts], [for (final d in b.dailyDarts) d.darts]);
      expect(after.doubleStats(p).checkout.attempts, before.doubleStats(p).checkout.attempts);
    }
    // Rekorde: kein 170er-Checkout aus dem Quiz.
    expect(after.records().map((r) => '${r.kind} ${r.value}'), before.records().map((r) => '${r.kind} ${r.value}'));

    final session = after.sessions.firstWhere((s) => s.gameId == checkoutQuizGameId);
    expect(after.scoringOf(session), isNull);
    expect(after.aimedOf(session), isEmpty);
    expect(after.primaryValue(session), closeTo(2 / 3, 1e-9));
    expect(after.trend(checkoutQuizGameId, StatsPeriod.all).single.value, closeTo(2 / 3, 1e-9));
    expect(after.metricKeys(checkoutQuizGameId, StatsPeriod.all).first, 'correctRate');
    final summary = after.report(StatsPeriod.all).games.firstWhere((g) => g.gameId == checkoutQuizGameId);
    expect(summary.darts, 0);
    expect(summary.best, closeTo(2 / 3, 1e-9));

    // Erfolge und Tagesziel: keine Darts, keine Finishes.
    final facts = sessionFacts(after, session);
    expect(facts.darts, 0);
    expect(facts.checkouts, 0);
    expect(facts.highestCheckout, 0);
    expect(facts.average, isNull);
    final tracker = AchievementTracker.fromCalculator(after);
    expect(tracker.value(AchievementMetric.highestCheckout), AchievementTracker.fromCalculator(before).value(AchievementMetric.highestCheckout));
    expect(tracker.value(AchievementMetric.darts), AchievementTracker.fromCalculator(before).value(AchievementMetric.darts));
    final activity = dailyActivity(after)[StatsCalculator.dayOf(day)]!;
    expect(activity.darts, dailyActivity(before)[StatsCalculator.dayOf(day)]!.darts);
  });

  test('Spielverlauf: Detailansicht zeigt die Antworten statt Aufnahmen', () async {
    final start = DateTime(2026, 10, 15, 18);
    final id = await quiz.save(
      playerId: me,
      config: const QuizConfig(range: QuizRange.high),
      answers: [a(170), QuizAnswer(score: 169, darts: 3, correct: true, ms: 5000, impossible: true, setup: [Segment.triple(20), Segment.triple(20), Segment.single(17)])],
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 2)),
      finished: true,
    );
    final row = await (db.select(db.sessions)..where((s) => s.id.equals(id!))).getSingle();
    final detail = buildSessionDetail(row, const []);
    expect(detail.entry.isQuiz, isTrue);
    expect(detail.entry.quizConfig.range, QuizRange.high);
    expect(detail.visits, isEmpty);
    expect(detail.quizAnswers.length, 2);
    expect(detail.quizAnswers[1].impossible, isTrue);
    expect(detail.summary.first.key, 'quizCorrect');
    expect(detail.summary.first.value, '2 / 2');
    expect(detail.entry.keyMetric!.value, 1.0);
  });

  test('Löschen markiert die Quiz-Session wie andere', () async {
    final start = DateTime(2026, 10, 15, 18);
    final id = await quiz.save(
      playerId: me,
      config: const QuizConfig(),
      answers: [a(40)],
      startedAt: start,
      endedAt: start,
      finished: true,
    );
    await GameRepository(db).deleteSession(id!);
    expect(await quiz.history(me), isEmpty);
    expect((await StatsRepository(db).watchCalculator(me).first).sessions, isEmpty);
  });
}
