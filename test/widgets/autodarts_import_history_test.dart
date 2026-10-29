import 'dart:convert';

import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/autodarts_import/presentation/autodarts_import_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/autodarts_match_fixture.dart';
import '../helpers/pump_app.dart';

// Alle Match-Daten sind synthetisch (siehe autodarts_match_fixture.dart).

Future<(ProviderContainer, int)> _imported(WidgetTester tester, {Size size = const Size(1280, 900)}) async {
  final c = await pumpApp(tester, size: size, prefs: {'import.myName': 'Ben'});
  final reply = await tester.runAsync(
    () => c.read(autodartsImportServiceProvider).importJson(jsonDecode(jsonEncode(syntheticMatch())), origin: 'file'),
  );
  await tester.pumpAndSettle();
  return (c, reply!.sessionId!);
}

Future<void> _openHistory(WidgetTester tester, ProviderContainer c) async {
  c.read(routerProvider).go(Routes.stats);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('stats-history')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Verlauf: importiertes Match als „Online-Match“ gegen Gegner, 3:2, gewonnen', (tester) async {
    final (c, id) = await _imported(tester);
    await _openHistory(tester, c);
    final tile = find.byKey(Key('history-$id'));
    expect(tile, findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Online-Match')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.textContaining('gegen Gegner')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.textContaining('3:2')), findsWidgets);
  });

  testWidgets('Detail: Ergebnis beider Spieler, Aufnahmen je Leg für Ben und den Gegner, Hinweis zur Statistik', (tester) async {
    final (c, id) = await _imported(tester);
    await _openHistory(tester, c);
    await tester.tap(find.byKey(Key('history-$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-detail')), findsOneWidget);
    expect(find.byKey(const Key('session-title')), findsOneWidget);
    expect(find.text('gegen Gegner'), findsWidgets);

    final list = find.descendant(of: find.byKey(const Key('session-detail')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const Key('session-leg-1')), 300, scrollable: list);
    await tester.pumpAndSettle();
    // Eine Tabelle je Leg mit beiden Spielern: Ben links, der Gegner rechts.
    expect(find.byKey(const Key('session-leg-1')), findsOneWidget);
    expect(find.byKey(const Key('session-leg-1-chart')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('session-leg-1')), matching: find.text('Ben')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('session-leg-1')), matching: find.text('Gegner')), findsOneWidget);
    expect(find.byKey(const Key('leg-1-p1-v1')), findsOneWidget, reason: 'erste Aufnahme des Gegners');
    expect(find.byKey(const Key('session-visits-note')), findsOneWidget);
    expect(find.textContaining('zählen nur deine eigenen Darts'), findsOneWidget);
  });

  testWidgets('Statistik „Online“ zeigt das Match mit Gegner', (tester) async {
    final (c, _) = await _imported(tester);
    c.read(routerProvider).go(Routes.stats);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('stats-tab-online')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stats-tab-online')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('online-matches')), findsOneWidget);
    final list = find.descendant(of: find.byKey(const Key('stats-list-online')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const Key('online-match-list')), 300, scrollable: list);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('online-match-list')), matching: find.textContaining('gegen Gegner')), findsOneWidget);
  });
}
