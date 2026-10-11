import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
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

void main() {
  testWidgets('Spielablauf: Auswahl, Einstellungen, Spiel, Ergebnis, Verlauf', (tester) async {
    final container = await pumpApp(tester, prefs: {'game.config.bull_drill': '{"visits":1}'});
    await tester.tap(find.text('Training').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('game-bull_drill')));
    await tester.pumpAndSettle();

    // Gemerkte Einstellung wird geladen.
    expect(find.text('1'), findsWidgets);
    await tester.tap(find.byKey(const Key('start-game')));
    await pumpFrames(tester);
    expect(find.byKey(const Key('game-board')), findsOneWidget);
    expect(container.read(activeGameProvider)?.gameId, 'bull_drill');

    // Drei Darts ins Bullseye beenden die einzige Aufnahme.
    final board = find.byKey(const Key('game-board'));
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(tester.getCenter(board));
      await pumpFrames(tester);
    }
    expect(container.read(activeGameProvider)!.ended, isTrue);
    expect(find.text('150'), findsWidgets);
    expect(find.byKey(const Key('game-done')), findsOneWidget);

    await tester.tap(find.byKey(const Key('game-done')));
    await tester.pumpAndSettle();
    expect(container.read(activeGameProvider), isNull);
    await tester.scrollUntilVisible(find.textContaining('3 Darts'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('3 Darts'), findsOneWidget);
  });

  testWidgets('Spiel verlassen fragt vorher nach', (tester) async {
    final container = await pumpApp(tester, size: const Size(390, 844));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Training')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('game-around_the_clock')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('start-game')), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const Key('start-game')));
    await pumpFrames(tester);

    await tester.tap(find.byKey(const Key('leave-game')));
    await pumpFrames(tester);
    await tester.tap(find.byKey(const Key('confirm-end')));
    await tester.pumpAndSettle();
    expect(container.read(activeGameProvider), isNull);
    expect(find.byKey(const Key('game-around_the_clock')), findsOneWidget);
  });

  testWidgets('Cricket: Spiel startet, Schließen erscheint als Banner', (tester) async {
    final container = await pumpApp(tester, prefs: {'game.config.cricket': '{"cricketOrder":"sequential"}'});
    await tester.tap(find.text('Training').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('game-cricket')), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const Key('game-cricket')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start-game')));
    await pumpFrames(tester);
    expect(container.read(activeGameProvider)?.gameId, 'cricket');
    expect(find.text('20'), findsWidgets);

    final source = container.read(dartSourceProvider) as SimulatorSource;
    source.throwAt(BoardGeometry.centerOf(Segment.triple(20)));
    await pumpFrames(tester);
    expect(find.text('20 geschlossen!'), findsOneWidget);
    expect(find.text('19'), findsWidgets);
  });
}
