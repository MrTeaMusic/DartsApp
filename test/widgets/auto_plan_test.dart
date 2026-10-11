import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/plans/data/plan_repository.dart';
import 'package:dartlab/features/plans/domain/auto_plan.dart';
import 'package:dartlab/features/plans/presentation/auto_plan_screen.dart';
import 'package:dartlab/features/plans/presentation/plan_routes.dart';
import 'package:dartlab/features/profiles/presentation/active_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/plans/auto_plan_test.dart' show weakD16;
import '../helpers/pump_app.dart';
import 'training_plans_test.dart' show pumpFrames;

Future<void> openAutoPlan(WidgetTester tester) async {
  await tester.tap(find.text('Training').first);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-plans')));
  await tester.pumpAndSettle();
  expect(find.text('Plan für mich erstellen'), findsOneWidget);
  await tester.tap(find.byKey(const Key('auto-plan-card')));
  await tester.pumpAndSettle();
}

/// Die Liste baut nur, was sichtbar ist: erst hinscrollen, dann tippen.
Future<void> tapInList(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.scrollUntilVisible(f, 200,
      scrollable: find.descendant(of: find.byKey(const Key('auto-plan-list')), matching: find.byType(Scrollable)));
  await tester.pump();
  await tester.tap(f);
}

int stepCount(WidgetTester tester) =>
    find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('auto-plan-step-')).evaluate().length;

void main() {
  testWidgets('Ohne Daten: Startplan erzeugen, Länge ändern, speichern, erscheint bei den eigenen Plänen', (tester) async {
    final container = await pumpApp(tester, size: const Size(390, 844));
    await openAutoPlan(tester);

    expect(find.textContaining('Noch zu wenig Daten'), findsOneWidget);
    expect(find.text('Startplan (40 min)'), findsOneWidget);
    expect(stepCount(tester), 5);

    // Kürzer: weniger Schritte.
    await tester.tap(find.byKey(const Key('auto-plan-length-20')));
    await tester.pumpAndSettle();
    expect(find.text('Startplan (20 min)'), findsOneWidget);
    expect(stepCount(tester), 4);

    // Neu vorschlagen ändert die Spiele.
    final before = AutoPlanGenerator.generate(container.read(autoPlanInputProvider)!, minutes: 20);
    await tester.tap(find.byKey(const Key('auto-plan-regenerate')));
    await tester.pumpAndSettle();
    final after = AutoPlanGenerator.generate(container.read(autoPlanInputProvider)!, minutes: 20, variant: 1);
    expect(after.plan.steps, isNot(before.plan.steps));

    await tapInList(tester, 'auto-plan-save');
    await tester.pumpAndSettle();

    final saved = (await PlanRepository(container.read(appDatabaseProvider)).custom()).single;
    expect(saved.name, 'Startplan (20 min)');
    expect(saved.steps, after.plan.steps);
    expect(saved.steps.every((s) => s.note != null && s.note!.isNotEmpty), isTrue);
    // Detailansicht des gespeicherten Plans, dort bearbeitbar.
    expect(find.byKey(const Key('plan-edit')), findsOneWidget);
    expect(find.textContaining('Als eigener Plan gespeichert'), findsOneWidget);

    container.read(routerProvider).go(PlanRoutes.list);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(Key('plan-${saved.id}')), 200,
        scrollable: find.descendant(of: find.byKey(const Key('plans-list')), matching: find.byType(Scrollable)).first);
    expect(find.descendant(of: find.byKey(Key('plan-${saved.id}')), matching: find.text('Startplan (20 min)')), findsOneWidget);
  });

  testWidgets('Schwaches D16: Schwerpunkt mit Begründung, direkt starten, Durchlauf bleibt offen', (tester) async {
    final container = await pumpApp(tester, overrides: [autoPlanInputProvider.overrideWithValue(weakD16())]);
    await openAutoPlan(tester);

    expect(find.text('Für mich: D16'), findsOneWidget);
    expect(find.textContaining('D16 triffst du nur zu 18 %, Ziel: 25 %'), findsOneWidget);
    expect(find.text('Ziel: 25 %'), findsOneWidget);

    await tapInList(tester, 'auto-plan-start');
    await pumpFrames(tester);
    expect(container.read(activeGameProvider)?.gameId, 'around_the_clock');
    expect(find.text('Schritt 1 von 5'), findsOneWidget);

    // Spiel schließen, ohne weiterzugehen: Der Durchlauf bleibt offen (Fortsetzen erst ab Schritt 2).
    await container.read(activeGameProvider.notifier).close();
    container.read(routerProvider).go(PlanRoutes.auto);
    await pumpFrames(tester);
    expect(find.byKey(const Key('auto-plan-resume')), findsNothing);
    final open = await PlanRepository(container.read(appDatabaseProvider)).openRun(AutoPlanGenerator.planId, playerId: container.read(activePlayerProvider)!.id);
    expect(open?.planName, 'Für mich: D16');
  });
}
