import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/board/presentation/board_style.dart';
import 'package:dartlab/features/board/presentation/dartboard_painter.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/pump_app.dart';

/// Painter der großen Scheibe auf dem Board-Bildschirm.
DartboardPainter boardPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<DartboardPainter>()
    .first;

void main() {
  testWidgets('Standard ist die Turnierscheibe, Unbekanntes fällt darauf zurück', (tester) async {
    SharedPreferences.setMockInitialValues({'settings.boardStyle': 'gibt-es-nicht'});
    final prefs = await SharedPreferences.getInstance();
    expect(AppSettings.load(prefs).boardStyle, BoardStyle.tournament);
    expect(const AppSettings().boardStyle, BoardStyle.tournament);
  });

  testWidgets('Scheiben-Auswahl: Wechsel wirkt sofort auf dem Board und wird gespeichert', (tester) async {
    final container = await pumpApp(tester);
    container.read(routerProvider).go(Routes.board);
    await tester.pumpAndSettle();
    expect(boardPainter(tester).style, BoardStyle.tournament);

    container.read(routerProvider).go(Routes.settings);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('board-style-turquoise')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('board-style-turquoise')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).boardStyle, BoardStyle.turquoise);
    expect(container.read(sharedPreferencesProvider).getString('settings.boardStyle'), 'turquoise');

    container.read(routerProvider).go(Routes.board);
    await tester.pumpAndSettle();
    expect(boardPainter(tester).style, BoardStyle.turquoise);
  });

  for (final style in BoardStyle.values) {
    test('${style.name}: Pixel und Board-Koordinaten passen zusammen', () {
      const size = Size(500, 500);
      for (final s in [Segment.triple(20), Segment.fromNumber(16, 2), Segment.outerBull, Segment.fromNumber(11, 1)]) {
        final p = BoardGeometry.centerOf(s);
        final pixel = DartboardPainter.toCanvas(p, size, style);
        final back = DartboardPainter.toBoard(pixel, size, style);
        expect(BoardGeometry.segmentAt(back), s);
      }
      // Die ganze Scheibe samt Fangring passt in die Fläche.
      expect(DartboardPainter.ringRadius(size, style) * style.spec.outerExtent, lessThanOrEqualTo(250));
    });
  }

  for (final style in BoardStyle.values) {
    testWidgets('${style.name}: Treffer per Antippen landet im richtigen Feld', (tester) async {
      final container = await pumpApp(tester, prefs: {'settings.boardStyle': style.name});
      container.read(routerProvider).go(Routes.board);
      await tester.pumpAndSettle();
      final board = find.bySemanticsLabel('Dartboard');
      final box = tester.getRect(board);
      final local = DartboardPainter.toCanvas(BoardGeometry.centerOf(Segment.triple(19)), box.size, style);
      final source = container.read(dartSourceProvider) as SimulatorSource;
      final seen = <Segment>[];
      final sub = source.events.listen((e) {
        if (e is DartThrown) seen.add(e.dart.segment);
      });
      addTearDown(sub.cancel);
      await tester.tapAt(box.topLeft + local);
      await tester.pump(const Duration(milliseconds: 100));
      expect(seen.last, Segment.triple(19));
    });
  }
}
