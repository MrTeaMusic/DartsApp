import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import '../helpers/scatter_seed.dart';

Future<Finder> openScatterTab(WidgetTester tester) async {
  await tester.tap(find.text('Statistik').first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('stats-tab-scatter')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('stats-tab-scatter')));
  await tester.pumpAndSettle();
  return find.descendant(of: find.byKey(const Key('stats-list-scatter')), matching: find.byType(Scrollable)).first;
}

void main() {
  testWidgets('Zu wenig Positionen: Hinweis auf Autodarts und Simulator, Felder mit Fortschritt', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    final player = await c.read(profileRepositoryProvider).resolve(null);
    final repo = c.read(gameRepositoryProvider);
    await seedBiasedTraining(repo, player, 'bull_drill', const {'visits': 4}, DateTime.now().subtract(const Duration(hours: 5)),
        BiasedThrower());
    await openScatterTab(tester);
    expect(find.byKey(const Key('scatter-empty')), findsOneWidget);
    expect(find.text('Noch zu wenig Positionen'), findsOneWidget);
    expect(find.textContaining('Autodarts oder aus dem Simulator'), findsOneWidget);
    expect(find.textContaining('Im Zeitraum: 12 Darts mit Position.'), findsOneWidget);
    expect(find.textContaining('Bull (12/30)'), findsOneWidget);
    expect(find.byKey(const Key('scatter-board')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ohne Daten: Hinweis statt Auswertung', (tester) async {
    await pumpApp(tester);
    await openScatterTab(tester);
    expect(find.byKey(const Key('scatter-empty')), findsOneWidget);
    expect(find.textContaining('Im Zeitraum: 0 Darts mit Position.'), findsOneWidget);
  });

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets('Streuung: Tendenz, Scheibe, Feld im Fokus, Liste mit Tipps (${size.width.toInt()} px)', (tester) async {
      final c = await pumpApp(tester, size: size);
      final player = await c.read(profileRepositoryProvider).resolve(null);
      final repo = c.read(gameRepositoryProvider);
      await seedScatter(repo, player, DateTime.now(), scale: 0.5);
      final list = await openScatterTab(tester);

      expect(find.byKey(const Key('scatter-empty')), findsNothing);
      expect(find.byKey(const Key('scatter-overall')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('scatter-board-view')), 300, scrollable: list);
      expect(find.byKey(const Key('scatter-board-view')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('scatter-focus-summary')), 300, scrollable: list);
      // T20 hat die meisten Darts und steht zuerst im Fokus: links unten.
      expect(find.text('T20: eher links unten'), findsOneWidget);
      expect(find.textContaining('Richtung 5'), findsWidgets);

      // Bull im Fokus wählen.
      await tester.ensureVisible(find.byKey(const Key('scatter-chip-BULL')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scatter-chip-BULL')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bull: '), findsOneWidget);
      expect(find.textContaining('Bull-Quote (25/50)'), findsWidgets);

      // Liste: T20 exakt mit Tipp, T19 nur geschätzt; Zeile antippen wählt das Feld.
      await tester.scrollUntilVisible(find.byKey(const Key('scatter-row-T20')), 300, scrollable: list);
      await tester.ensureVisible(find.byKey(const Key('scatter-row-T20')));
      await tester.pumpAndSettle();
      final row = find.byKey(const Key('scatter-row-T20'));
      expect(find.descendant(of: row, matching: find.text('EXAKT')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('zu flach')), findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('scatter-focus-summary')), -300, scrollable: list);
      expect(find.text('T20: eher links unten'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Auswahl Matches: nur Online-Matches mit geschätztem Ziel, Training exakt', (tester) async {
    final c = await pumpApp(tester);
    final player = await c.read(profileRepositoryProvider).resolve(null);
    final repo = c.read(gameRepositoryProvider);
    await seedScatter(repo, player, DateTime.now(), scale: 0.5);
    final list = await openScatterTab(tester);
    await tester.tap(find.byKey(const Key('scatter-scope-match')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('scatter-row-T20')), 300, scrollable: list);
    expect(find.descendant(of: find.byKey(const Key('scatter-row-T20')), matching: find.text('GESCHÄTZT')), findsOneWidget);
    expect(find.byKey(const Key('scatter-row-BULL')), findsNothing);

    // Training: Bull wieder da, T20 exakt.
    await tester.scrollUntilVisible(find.byKey(const Key('scatter-scope-training')), -300, scrollable: list);
    await tester.tap(find.byKey(const Key('scatter-scope-training')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('scatter-row-BULL')), 300, scrollable: list);
    expect(find.descendant(of: find.byKey(const Key('scatter-row-T20')), matching: find.text('EXAKT')), findsOneWidget);
  });
}
