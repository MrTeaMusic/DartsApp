import 'package:dartlab/core/design/components/components.dart';
import 'package:dartlab/core/design/dart_colors.dart';
import 'package:dartlab/core/fullscreen.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/board/presentation/live_visit_controller.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class FakeFullscreen implements FullscreenPlatform {
  final calls = <bool>[];
  @override
  Future<void> set(bool fullscreen) async => calls.add(fullscreen);
  @override
  Future<bool> get current async => calls.isNotEmpty && calls.last;
}

Future<ProviderContainer> startGame(WidgetTester tester, String id, {Map<String, Object?> config = const {}, List<Override> overrides = const []}) async {
  final c = await pumpApp(tester, overrides: overrides);
  await c.read(activeGameProvider.notifier).start(GameCatalog.all.firstWhere((g) => g.id == id), config, seed: 7);
  c.read(routerProvider).go(Routes.play);
  await pumpFrames(tester);
  return c;
}

String slotText(WidgetTester tester, int i) =>
    tester.widget<DartChip>(find.byKey(Key('dart-slot-$i'))).segment?.name ??
    'planned:${tester.widget<DartChip>(find.byKey(Key('dart-slot-$i'))).planned?.name}';

void main() {
  testWidgets('Checkout-Spiel zeigt den Weg gelb in den freien Feldern und rechnet nach jedem Dart neu', (tester) async {
    final c = await startGame(tester, 'checkout');
    final route = c.read(activeGameProvider)!.game.display.suggestion!;
    expect(route, isNotEmpty);
    for (var i = 0; i < route.length; i++) {
      expect(slotText(tester, i), 'planned:${route[i].name}');
    }
    expect(find.byKey(const Key('checkout-route-label')), findsOneWidget);

    // Ein Dart daneben: Platz 1 zeigt den Dart, der Rest den neuen Weg.
    final source = c.read(dartSourceProvider) as SimulatorSource;
    source.throwAt(const BoardPoint(0, 1.3));
    await pumpFrames(tester);
    expect(slotText(tester, 0), 'MISS');
    final next = c.read(activeGameProvider)!.game.display.suggestion!;
    for (var i = 0; i < next.length; i++) {
      expect(slotText(tester, i + 1), 'planned:${next[i].name}');
    }
    final planned = tester.widget<Text>(find.descendant(of: find.byKey(const Key('dart-slot-1')), matching: find.byType(Text)).last);
    expect(planned.style?.color, DartColors.dark.highlight);
  });

  testWidgets('Geht kein Finish mehr, zeigen die freien Felder blau, wie man sich stellt', (tester) async {
    final c = await startGame(tester, 'x01', config: {'startScore': 170});
    expect(find.byKey(const Key('checkout-route-label')), findsOneWidget);
    expect(find.byKey(const Key('setup-route-label')), findsNothing);

    // Daneben: 170 geht mit zwei Darts nicht mehr, also stellen.
    final source = c.read(dartSourceProvider) as SimulatorSource;
    source.throwAt(const BoardPoint(0, 1.3));
    await pumpFrames(tester);
    final game = c.read(activeGameProvider)!.game;
    expect(game.display.suggestion, isNull);
    final setup = game.display.setup!;
    expect(find.byKey(const Key('checkout-route-label')), findsNothing);
    expect(find.text('STELLEN AUF ${setup.leave}'), findsOneWidget);
    for (var i = 0; i < setup.darts.length; i++) {
      expect(slotText(tester, i + 1), 'planned:${setup.darts[i].name}');
    }
    final planned = tester.widget<Text>(find.descendant(of: find.byKey(const Key('dart-slot-1')), matching: find.byType(Text)).last);
    expect(planned.style?.color, DartColors.dark.setupHint);
  });

  testWidgets('Triple-Treffer sind lila, Doubles grün', (tester) async {
    final c = await startGame(tester, 'highscore_hunt');
    final source = c.read(dartSourceProvider) as SimulatorSource;
    source.throwAt(BoardGeometry.centerOf(Segment.triple(20)));
    source.throwAt(BoardGeometry.centerOf(Segment.fromNumber(16, 2)));
    await pumpFrames(tester);
    Color? colorOf(String text) =>
        tester.widget<Text>(find.descendant(of: find.byType(DartChip), matching: find.text(text)).first).style?.color;
    expect(colorOf('T20'), DartColors.dark.tripleHit);
    expect(colorOf('D16'), DartColors.dark.doubleHit);
  });

  testWidgets('Dart in der laufenden Aufnahme antippen und korrigieren', (tester) async {
    final c = await startGame(tester, 'highscore_hunt');
    final source = c.read(dartSourceProvider) as SimulatorSource;
    source.throwAt(BoardGeometry.centerOf(Segment.fromNumber(1, 1)));
    await pumpFrames(tester);
    expect(slotText(tester, 0), 'S1');

    await tester.tap(find.byKey(const Key('dart-slot-0')));
    await pumpFrames(tester);
    expect(find.text('Erkannt: S1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fix-triple')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('fix-20')));
    await pumpFrames(tester);

    expect(slotText(tester, 0), 'T20');
    expect(c.read(liveVisitProvider).visit.single.segment.name, 'T20');
    expect(c.read(activeGameProvider)!.session.records.single.dart.segment.name, 'T20');
    expect(find.byKey(const Key('visit-score')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('visit-score'))).data, '60');
  });

  testWidgets('Dart einer früheren Aufnahme über die Liste korrigieren', (tester) async {
    final c = await startGame(tester, 'highscore_hunt');
    final source = c.read(dartSourceProvider) as SimulatorSource;
    for (var i = 0; i < 3; i++) {
      source.throwAt(BoardGeometry.centerOf(Segment.fromNumber(5, 1)));
    }
    source.finishTakeout();
    source.throwAt(BoardGeometry.centerOf(Segment.fromNumber(20, 1)));
    await pumpFrames(tester);

    await tester.ensureVisible(find.byKey(const Key('open-corrections')));
    await tester.tap(find.byKey(const Key('open-corrections')));
    await pumpFrames(tester);
    await tester.tap(find.byKey(const Key('fix-dart-0')));
    await pumpFrames(tester);
    await tester.tap(find.byKey(const Key('fix-bull')));
    await pumpFrames(tester);

    final records = c.read(activeGameProvider)!.session.records;
    expect(records.map((r) => r.dart.segment.name), ['BULL', 'S5', 'S5', 'S20']);
    // Die laufende Aufnahme bleibt unverändert.
    expect(c.read(liveVisitProvider).visit.single.segment.name, 'S20');
  });

  testWidgets('Vollbild per Knopf und F11, Esc beendet es', (tester) async {
    final fake = FakeFullscreen();
    final c = await startGame(tester, 'bull_drill', overrides: [fullscreenPlatformProvider.overrideWithValue(fake)]);
    await tester.tap(find.byKey(const Key('fullscreen-toggle')));
    await pumpFrames(tester);
    expect(c.read(fullscreenProvider), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    expect(c.read(fullscreenProvider), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await pumpFrames(tester);
    expect(fake.calls, [true, false, true]);
  });
}
