import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/challenges/presentation/challenge_run_controller.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/progress/domain/daily_goal.dart';
import 'package:dartlab/features/progress/presentation/progress_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Laufende Spiele animieren dauerhaft: feste Frames statt pumpAndSettle.
Future<void> frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('Startseite: Tagesziel-Ring, Serie, Ziel ändern', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    expect(find.byKey(const Key('daily-goal-card')), findsOneWidget);
    expect(find.text('Heute 0 / 200 Darts'), findsOneWidget);
    expect(find.text('0 Tage'), findsOneWidget);

    await tester.tap(find.byKey(const Key('daily-goal-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minuten').last);
    await tester.pumpAndSettle();
    expect(find.text('30 Minuten'), findsOneWidget);
    await tester.tap(find.byKey(const Key('daily-goal-save')));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).dailyGoal, const DailyGoal(DailyGoalUnit.minutes, 30));
    expect(c.read(sharedPreferencesProvider).getString('goals.dailyUnit'), 'minutes');
    expect(find.text('Heute 0 / 30 Minuten'), findsOneWidget);
  });

  testWidgets('Optionen: Tagesziel öffnet denselben Editor', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Optionen').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('settings-daily-goal')), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('200 Darts pro Tag'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-daily-goal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('daily-goal-slider')), findsOneWidget);
  });

  testWidgets('Statistik: Reiter Erfolge mit gesperrten Erfolgen und Fortschritt', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Statistik').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('stats-tab-achievements')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stats-tab-achievements')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('achievements-summary')), findsOneWidget);
    expect(find.textContaining('von 49 Stufen erreicht'), findsOneWidget);
    expect(find.byKey(const Key('achievement-first_100')), findsOneWidget);
    expect(find.text('0 / 1'), findsWidgets);
    // Zeitraum und Spiel gelten hier nicht.
    expect(find.byKey(const Key('period-week')), findsNothing);
  });

  testWidgets('Challenge: Kapitel, Aufgabe, Spiel mit Live-Sternen, Wertung, Übersicht', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.text('Training').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-challenges')));
    await tester.pumpAndSettle();
    expect(find.text('0 von 120 Sternen'), findsOneWidget);
    expect(find.byKey(const Key('chapter-amateur-locked')), findsOneWidget);

    await tester.tap(find.byKey(const Key('challenge-c1-1')));
    await tester.pumpAndSettle();
    expect(find.text('Rund um die Uhr'), findsOneWidget);
    expect(find.text('höchstens 35 Darts'), findsOneWidget);
    await tester.tap(find.byKey(const Key('challenge-start')));
    await frames(tester);

    expect(find.byKey(const Key('game-board')), findsOneWidget);
    expect(find.byKey(const Key('challenge-task')), findsOneWidget);
    expect(c.read(activeGameProvider)!.gameId, 'around_the_clock');

    final sim = c.read(dartSourceProvider) as SimulatorSource;
    for (var n = 1; n <= 20; n++) {
      sim.throwAt(BoardGeometry.centerOf(Segment.single(n)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    sim.throwAt(BoardGeometry.centerOf(Segment.bull));
    await frames(tester, 20);

    expect(c.read(challengeRunProvider)!.outcome!.stars, 3);
    expect(find.byKey(const Key('challenge-result')), findsOneWidget);
    expect(find.text('3 Sterne'), findsOneWidget);
    expect(find.text('Neuer Bestwert'), findsOneWidget);
    expect(find.text('Freigeschaltet: Erster Checkout'), findsOneWidget);
    expect(find.byKey(const Key('challenge-next')), findsOneWidget);
    expect(find.byKey(const Key('game-again')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('challenge-overview')));
    await tester.tap(find.byKey(const Key('challenge-overview')));
    await tester.pumpAndSettle();
    expect(c.read(activeGameProvider), isNull);
    expect(c.read(challengeRunProvider), isNull);
    expect(find.text('3 von 120 Sternen'), findsOneWidget);
    expect(find.text('Bestwert: 21 Darts'), findsOneWidget);
  });

  testWidgets('Challenge verlassen: zurück zur Aufgabe, ohne Wertung', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    c.read(routerProvider).go('/training/challenges/c1-1');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('challenge-start')), 200, scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.byKey(const Key('challenge-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('challenge-start')));
    await frames(tester);
    expect(find.byKey(const Key('challenge-task')), findsOneWidget);

    await tester.tap(find.byKey(const Key('leave-game')));
    await frames(tester, 3);
    await tester.tap(find.byKey(const Key('confirm-end')));
    await tester.pumpAndSettle();
    expect(c.read(challengeRunProvider), isNull);
    expect(find.byKey(const Key('challenge-name')), findsOneWidget);
    expect(c.read(challengeResultsProvider).value, isEmpty);
  });
}
