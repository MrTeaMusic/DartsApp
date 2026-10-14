import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/board/presentation/dartboard_painter.dart';
import 'package:dartlab/features/board/presentation/dartboard_view.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Painter der Ebenen der großen Scheibe: (Scheibe, Bewegtes).
(CustomPainter, CustomPainter) layers(WidgetTester tester) {
  final paints = tester
      .widgetList<CustomPaint>(find.descendant(of: find.byKey(const Key('game-board')), matching: find.byType(CustomPaint)))
      .where((p) => p.painter != null)
      .toList();
  return (paints.first.painter!, paints.last.painter!);
}

bool _inside(RenderObject o, Iterable<RenderObject> roots) {
  for (RenderObject? p = o; p != null; p = p.parent) {
    if (roots.any((r) => identical(p, r))) return true;
  }
  return false;
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
    expect(overlay.animation, isNotNull);

    // Große Scheibe und Doppel-Zoom (D20) pulsieren beide.
    final boards = tester.renderObjectList(find.byType(DartboardView)).toList();
    expect(boards, hasLength(2));
    final painted = <RenderObject>[];
    var rebuilds = 0;
    debugOnProfilePaint = painted.add;
    debugOnRebuildDirtyWidget = (_, _) => rebuilds++;
    addTearDown(() {
      debugOnProfilePaint = null;
      debugOnRebuildDirtyWidget = null;
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    debugOnProfilePaint = null;
    debugOnRebuildDirtyWidget = null;

    // Der Puls läuft (die obere Ebene wird gezeichnet), aber ohne Neuaufbau
    // und ohne irgendetwas außerhalb der Scheiben neu zu zeichnen.
    expect(painted.whereType<RenderCustomPaint>().where((p) => identical(p.painter, overlay)), hasLength(10));
    expect([for (final o in painted) if (!_inside(o, boards)) o], isEmpty);
    expect(rebuilds, 0);
    final (base2, overlay2) = layers(tester);
    // Die gerasterte Scheibe bleibt dieselbe.
    expect(identical(base, base2), isTrue);
    expect(identical(overlay, overlay2), isTrue);
  });
}
