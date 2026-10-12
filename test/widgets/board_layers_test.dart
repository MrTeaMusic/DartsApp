import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/board/presentation/dartboard_painter.dart';
import 'package:dartlab/features/board/presentation/dartboard_view.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Painter der beiden Ebenen der großen Scheibe: (Scheibe, Bewegtes).
(CustomPainter, CustomPainter) layers(WidgetTester tester) {
  final paints = tester
      .widgetList<CustomPaint>(find.descendant(of: find.byKey(const Key('game-board')), matching: find.byType(CustomPaint)))
      .where((p) => p.painter != null)
      .toList();
  return (paints.first.painter!, paints.last.painter!);
}

void main() {
  testWidgets('Während das Ziel pulsiert, wird nur die obere Ebene neu gezeichnet', (tester) async {
    final c = await pumpApp(tester);
    await c.read(activeGameProvider.notifier).start(GameCatalog.byId('x01')!, const {'startScore': 40}, seed: 7);
    c.read(routerProvider).go(Routes.play);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget(find.byKey(const Key('game-board'))), isA<DartboardView>());
    final (base, overlay) = layers(tester);
    expect(overlay, isA<DartboardPainter>().having((p) => p.layer, 'layer', BoardLayer.overlay));
    expect((overlay as DartboardPainter).highlighted, isNotEmpty);

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final (base2, overlay2) = layers(tester);
    // Die gerasterte Scheibe bleibt dieselbe, der Puls läuft weiter.
    expect(identical(base, base2), isTrue);
    expect(identical(overlay, overlay2), isFalse);
  });
}
