import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/presentation/live_visit_controller.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('Desktop: Seitenleiste, Start-Bildschirm mit Status', (tester) async {
    await pumpApp(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Bereit fürs Training?'), findsOneWidget);
    expect(find.textContaining('Simulator · Verbunden'), findsOneWidget);
  });

  testWidgets('Mobil: Bottom-Navigation', (tester) async {
    await pumpApp(tester, size: const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.text('Training').last);
    await tester.pumpAndSettle();
    // Unter den Modi-Karten (Pläne … Checkout-Quiz) folgen die Spiele.
    await tester.scrollUntilVisible(find.text('Checkout-Training'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Checkout-Training'), findsOneWidget);
  });

  testWidgets('Simulator: Tippen aufs Board wirft einen Dart', (tester) async {
    final container = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('home-open-board')));
    await tester.pumpAndSettle();
    final board = find.byKey(const Key('dartboard'));
    expect(board, findsOneWidget);

    // Mitte des Boards = Bullseye.
    await tester.tapAt(tester.getCenter(board));
    await tester.pumpAndSettle();
    expect(container.read(liveVisitProvider).visit.single.segment.name, 'BULL');
    expect(find.text('BULL'), findsWidgets);
    final score = tester.widget<Text>(find.byKey(const Key('visit-score')));
    expect(score.data, '50');
  });

  testWidgets('Manuelle Eingabe über das Tastenfeld', (tester) async {
    final container = await pumpApp(tester, prefs: {'settings.sourceKind': DartSourceKind.manual.name});
    await tester.tap(find.text('Board').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Triple'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('key-20')));
    await tester.pumpAndSettle();
    expect(container.read(liveVisitProvider).visit.single.segment.name, 'T20');

    await tester.ensureVisible(find.byKey(const Key('manual-next')));
    await tester.tap(find.byKey(const Key('manual-next')));
    await tester.pumpAndSettle();
    expect(container.read(liveVisitProvider).visit, isEmpty);
    expect(container.read(liveVisitProvider).history.map((d) => d.segment.name), ['T20', 'MISS', 'MISS']);
  });

  testWidgets('Einstellungen: Quelle wechseln und Theme umschalten', (tester) async {
    final container = await pumpApp(tester);
    await tester.tap(find.text('Optionen').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('source-manual')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).sourceKind, DartSourceKind.manual);
    expect(find.textContaining('Manuelle Eingabe · Verbunden'), findsWidgets);

    // Hell/Dunkel gibt es nur im Look Clean (TV und Lab sind immer dunkel).
    await tester.ensureVisible(find.byKey(const Key('look-clean')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('look-clean')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hell'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).themeMode, ThemeMode.light);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.light);
  });

  testWidgets('Debug-Bildschirm ist erreichbar', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Optionen').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('open-debug')), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const Key('open-debug')));
    await tester.pumpAndSettle();
    expect(find.text('Debug: Rohdaten'), findsWidgets);
    expect(find.text('Noch keine Nachrichten'), findsOneWidget);
  });
}
