import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/quiz/domain/checkout_route.dart';
import 'package:dartlab/features/quiz/domain/quiz_config.dart';
import 'package:dartlab/features/quiz/presentation/quiz_controller.dart';
import 'package:dartlab/features/quiz/presentation/quiz_routes.dart';
import 'package:dartlab/features/quiz/presentation/quiz_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Tippt ein Feld auf dem Quiz-Tastenfeld.
Future<void> tapSegment(WidgetTester tester, Segment s) async {
  if (s == Segment.bull) {
    await tester.tap(find.byKey(const Key('quiz-key-bull')));
  } else if (s == Segment.outerBull) {
    await tester.tap(find.byKey(const Key('quiz-key-25')));
  } else {
    if (s.multiplier > 1) await tester.tap(find.byKey(Key('quiz-mult-${s.multiplier}')));
    await tester.pump();
    await tester.tap(find.byKey(Key('quiz-key-${s.number}')));
  }
  await tester.pump();
}

/// Beantwortet die aktuelle Frage richtig (Vorschlag der App bzw. „Nicht
/// möglich“ und der Stell-Vorschlag).
Future<void> answerCorrectly(WidgetTester tester, ProviderContainer c) async {
  final q = c.read(quizProvider)!.run.question!;
  if (q.possible) {
    for (final s in q.recommended!) {
      await tapSegment(tester, s);
    }
  } else {
    await tester.tap(find.byKey(const Key('quiz-impossible')));
    await tester.pump();
    for (final s in q.setup!.darts) {
      await tapSegment(tester, s);
    }
  }
  await tester.tap(find.byKey(const Key('quiz-check')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Quiz aus den Modi starten, richtig und falsch antworten, speichern', (tester) async {
    // Nur checkbare Reste: die zweite Antwort ist sicher falsch.
    final c = await pumpApp(tester, size: const Size(390, 844), prefs: {quizPrefsKey: '{"onlyCheckable":true}'});
    c.read(routerProvider).go(Routes.games);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('open-checkout-quiz')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-checkout-quiz')));
    await tester.pumpAndSettle();
    expect(find.byType(QuizSetupScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('quiz-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quiz-score')), findsOneWidget);
    // Telefon: Tastenfeld und Knöpfe ohne Scrollen sichtbar.
    final check = tester.getRect(find.byKey(const Key('quiz-check')));
    expect(check.bottom, lessThanOrEqualTo(844));

    // 1. Frage richtig.
    final first = c.read(quizProvider)!.run.question!;
    expect(find.text('${first.score}'), findsWidgets);
    await answerCorrectly(tester, c);
    expect(find.byKey(const Key('quiz-feedback')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('quiz-verdict'))).data, 'Richtig');
    expect(tester.widget<Text>(find.byKey(const Key('quiz-correct'))).data, '1 / 1');
    await tester.tap(find.byKey(const Key('quiz-next')));
    await tester.pumpAndSettle();

    // 2. Frage falsch: „Nicht möglich“ bei einem checkbaren Rest.
    expect(c.read(quizProvider)!.run.question!.possible, isTrue);
    await tester.tap(find.byKey(const Key('quiz-impossible')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('quiz-verdict'))).data, 'Falsch');
    // Die Auflösung nennt den Vorschlag der App.
    expect(find.textContaining(RegExp('empfohlen|vorschlag', caseSensitive: false)), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('quiz-finish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quiz-finish')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('quiz-result-score'))).data, '1 / 2');

    final db = c.read(appDatabaseProvider);
    final sessions = await db.select(db.sessions).get();
    expect(sessions.single.gameId, checkoutQuizGameId);
    expect(sessions.single.dartCount, 0);
    expect(await db.select(db.throws).get(), isEmpty);

    await tester.ensureVisible(find.byKey(const Key('quiz-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quiz-done')));
    await tester.pumpAndSettle();
    expect(find.byType(QuizSetupScreen), findsOneWidget);
    expect(c.read(quizProvider), isNull);

    // Im Spielverlauf mit Fragen statt Darts.
    c.read(routerProvider).go(Routes.history);
    await tester.pumpAndSettle();
    expect(find.textContaining('2 Fragen'), findsOneWidget);
    await tester.tap(find.byKey(Key('history-${sessions.single.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-quiz-answers')), findsOneWidget);
  });

  testWidgets('falscher Weg wird erklärt, Eingabe lässt sich korrigieren', (tester) async {
    final c = await pumpApp(tester, size: const Size(1280, 900), prefs: {
      quizPrefsKey: '{"mode":"training","range":"low","darts":"three","onlyCheckable":true}',
    });
    await c.read(quizProvider.notifier).start(const QuizConfig(range: QuizRange.low, onlyCheckable: true), seed: 4);
    c.read(routerProvider).go(QuizRoutes.play);
    await tester.pumpAndSettle();
    final q = c.read(quizProvider)!.run.question!;
    expect(q.possible, isTrue);
    await tapSegment(tester, Segment.triple(20));
    await tapSegment(tester, Segment.triple(20));
    expect(c.read(quizProvider)!.run.input.length, 2);
    await tester.tap(find.byKey(const Key('quiz-undo')));
    await tester.pump();
    expect(c.read(quizProvider)!.run.input.length, 1);
    await tester.tap(find.byKey(const Key('quiz-check')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('quiz-verdict'))).data, 'Falsch');
    final check = CheckoutRoutes.check(q.score, 3, [Segment.triple(20)], c.read(quizProvider)!.run.config.out);
    expect(check.valid, isFalse);
    expect(find.textContaining('Überworfen'), findsOneWidget);
  });

  testWidgets('nicht checkbar: „Nicht möglich“, stellen, Auflösung', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    // 101–170 mit einem Dart: nie checkbar, immer eine Stell-Frage.
    await c.read(quizProvider.notifier).start(const QuizConfig(range: QuizRange.high, darts: QuizDarts.one), seed: 1);
    c.read(routerProvider).go(QuizRoutes.play);
    await tester.pumpAndSettle();
    final q = c.read(quizProvider)!.run.question!;
    expect(q.possible, isFalse);
    await answerCorrectly(tester, c);
    expect(tester.widget<Text>(find.byKey(const Key('quiz-verdict'))).data, 'Richtig');
    expect(c.read(quizProvider)!.run.last!.setupCheck!.recommended, isTrue);
    await tester.ensureVisible(find.byKey(const Key('quiz-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quiz-next')));
    await tester.pumpAndSettle();
    // Ein Weg für einen nicht checkbaren Rest ist falsch.
    await tapSegment(tester, Segment.double(1));
    await tester.tap(find.byKey(const Key('quiz-check')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('quiz-verdict'))).data, 'Falsch');
    expect(find.textContaining('nicht checkbar'), findsWidgets);
  });

  testWidgets('Modus Zeit endet nach 60 Sekunden', (tester) async {
    var now = DateTime(2026, 10, 15, 18);
    final c = await pumpApp(tester, size: const Size(390, 844), overrides: [
      quizClockProvider.overrideWithValue(() => now),
    ]);
    await c.read(quizProvider.notifier).start(const QuizConfig(mode: QuizMode.timed, range: QuizRange.low), seed: 2);
    c.read(routerProvider).go(QuizRoutes.play);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quiz-timer')), findsOneWidget);
    await answerCorrectly(tester, c);
    // Im Modus Zeit geht es ohne Auflösung weiter.
    expect(find.byKey(const Key('quiz-feedback')), findsNothing);
    expect(find.byKey(const Key('quiz-last')), findsOneWidget);
    now = now.add(const Duration(seconds: 61));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quiz-result')), findsOneWidget);
    expect(c.read(quizProvider)!.run.completed, isTrue);
    final db = c.read(appDatabaseProvider);
    final row = (await db.select(db.sessions).get()).single;
    expect(row.finished, isTrue);
    await tester.tap(find.byKey(const Key('quiz-leave')));
    await tester.pumpAndSettle();
    expect(find.byType(QuizSetupScreen), findsOneWidget);
    // Bestwert steht jetzt auf der Einstiegsseite.
    await tester.scrollUntilVisible(find.byKey(const Key('quiz-best-timed')), 200,
        scrollable: find.descendant(of: find.byKey(const Key('quiz-setup')), matching: find.byType(Scrollable)).first);
    expect(find.descendant(of: find.byKey(const Key('quiz-best-timed')), matching: find.text('1')), findsOneWidget);
  });
}
