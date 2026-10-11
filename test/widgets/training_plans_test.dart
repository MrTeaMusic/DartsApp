import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/plans/data/plan_repository.dart';
import 'package:dartlab/features/plans/domain/training_plan.dart';
import 'package:dartlab/features/plans/presentation/plan_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Im laufenden Spiel pulsieren die Zielfelder dauerhaft, daher feste Frames
/// statt pumpAndSettle.
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

Future<void> addStep(WidgetTester tester, String gameId, {int minus = 0}) async {
  await tapVisible(tester, find.byKey(const Key('plan-add-step')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('step-game-$gameId')));
  await tester.pumpAndSettle();
  for (var i = 0; i < minus; i++) {
    await tester.tap(find.byKey(const Key('opt-visits-minus')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('step-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Plan anlegen und zwei Schritte durchspielen', (tester) async {
    final container = await pumpApp(tester);
    await tester.tap(find.text('Training').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-plans')));
    await tester.pumpAndSettle();
    expect(find.text('Aufwärmen'), findsOneWidget);

    // Neuer Plan: ohne Namen und Schritte gibt es Hinweise.
    await tester.tap(find.byKey(const Key('plan-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();
    expect(find.text('Bitte einen Namen eingeben.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('plan-name')), 'Mein Plan');
    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();
    expect(find.text('Mindestens einen Schritt hinzufügen.'), findsOneWidget);

    await addStep(tester, 'highscore_hunt', minus: 9);
    await addStep(tester, 'bull_drill', minus: 9);
    expect(find.byKey(const Key('plan-step-1')), findsOneWidget);
    // Reihenfolge ändern: Bullseye nach vorn.
    await tester.tap(find.byKey(const Key('plan-step-1-up')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(const Key('plan-step-0')), matching: find.text('Bullseye-Drills')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();

    final saved = (await PlanRepository(container.read(appDatabaseProvider)).custom()).single;
    expect(saved.name, 'Mein Plan');
    expect(saved.steps.map((s) => s.gameId), ['bull_drill', 'highscore_hunt']);
    expect(saved.steps.map((s) => s.config['visits']), [1, 1]);

    // Detailansicht, Plan starten.
    expect(find.byKey(const Key('plan-start')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('plan-start')));
    await pumpFrames(tester);
    expect(container.read(activeGameProvider)?.gameId, 'bull_drill');
    expect(find.text('Schritt 1 von 2'), findsOneWidget);

    final board = find.byKey(const Key('game-board'));
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(tester.getCenter(board));
      await pumpFrames(tester);
    }
    expect(container.read(activeGameProvider)!.ended, isTrue);
    await tapVisible(tester, find.byKey(const Key('plan-next')));
    await pumpFrames(tester);
    expect(container.read(activeGameProvider)?.gameId, 'highscore_hunt');
    expect(container.read(activeGameProvider)!.ended, isFalse);
    expect(find.text('Schritt 2 von 2'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tapAt(tester.getCenter(board));
      await pumpFrames(tester);
    }
    expect(container.read(activeGameProvider)!.ended, isTrue);
    expect(find.byKey(const Key('plan-next')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('plan-finish')));
    await tester.pumpAndSettle();

    // Zusammenfassung.
    expect(container.read(activeGameProvider), isNull);
    expect(find.textContaining('2 von 2 Schritten gespielt · 6 Darts'), findsOneWidget);
    expect(find.text('gespielt'), findsNWidgets(2));
    await tapVisible(tester, find.byKey(const Key('plan-summary-done')));
    await tester.pumpAndSettle();
    expect(find.text('Mein Plan'), findsOneWidget);
  });

  testWidgets('Festen Plan kopieren, unbekanntes Spiel als nicht verfügbar, Fortsetzen', (tester) async {
    final container = await pumpApp(tester, size: const Size(390, 844));
    final repo = PlanRepository(container.read(appDatabaseProvider));
    final id = await repo.create(name: 'Mit Zukunft', steps: const [
      PlanStep(gameId: 'bull_drill', config: {'visits': 1}),
      PlanStep(gameId: 'game_from_the_future'),
    ]);

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Training')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-plans')));
    await tester.pumpAndSettle();

    // Fester Plan: kopieren führt in den Editor der Kopie.
    await tester.tap(find.byKey(const Key('plan-builtin-warmup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-edit')), findsNothing);
    await tester.tap(find.byKey(const Key('plan-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-delete')), findsNothing);
    await tester.tap(find.byKey(const Key('plan-duplicate')));
    await tester.pumpAndSettle();
    expect(find.text('Aufwärmen (Kopie)'), findsOneWidget);
    expect(await repo.custom(), hasLength(2));

    // Plan mit unbekanntem Spiel.
    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();
    container.read(routerProvider).go(PlanRoutes.plan(id));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nicht verfügbar: game_from_the_future'), findsOneWidget);
    expect(find.textContaining('wird beim Spielen übersprungen'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('plan-start')));
    await pumpFrames(tester);
    final board = find.byKey(const Key('game-board'));
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(tester.getCenter(board));
      await pumpFrames(tester);
    }
    // Verlassen statt weiter: der Fortschritt bleibt.
    await tapVisible(tester, find.byKey(const Key('game-done')));
    await tester.pumpAndSettle();
    container.read(routerProvider).go(PlanRoutes.plan(id));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-resume')), findsOneWidget);
    expect(find.text('Fortsetzen (Schritt 2 von 2)'), findsOneWidget);

    // Fortsetzen: nur noch der unbekannte Schritt, also direkt zur Zusammenfassung.
    await tapVisible(tester, find.byKey(const Key('plan-resume')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 von 2 Schritten gespielt'), findsOneWidget);
    expect(find.text('nicht verfügbar'), findsOneWidget);
  });
}
