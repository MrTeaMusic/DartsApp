import 'dart:math' as math;

import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/board/presentation/double_zoom.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:dartlab/features/matches/presentation/match_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// X01 ab 76, erster Dart T20: danach ist D8 dran.
Future<ProviderContainer> x01OnD8(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  final c = await pumpApp(tester, prefs: prefs);
  await c.read(activeGameProvider.notifier).start(GameCatalog.byId('x01')!, const {'startScore': 76}, seed: 7);
  c.read(routerProvider).go(Routes.play);
  await pumpFrames(tester);
  (c.read(dartSourceProvider) as SimulatorSource).throwAt(BoardGeometry.centerOf(Segment.triple(20)));
  await pumpFrames(tester);
  return c;
}

/// Bildschirmpunkt im Zoom für einen Punkt auf dem Doppel-Ring: [offset] Grad
/// neben dem Zielfeld (negativ = gegen den Uhrzeigersinn). Der Ausschnitt ist
/// gedreht, das Zielfeld liegt oben in der Mitte.
Offset zoomPoint(WidgetTester tester, {double offset = 0}) {
  final rect = tester.getRect(find.byKey(const Key('double-zoom-board')));
  const width = 0.9;
  final px = rect.width / width;
  final height = width * rect.height / rect.width;
  final centerR = 1.2 - height / 2;
  const r = (BoardGeometry.doubleInnerR + BoardGeometry.doubleOuterR) / 2;
  final a = offset * math.pi / 180;
  return rect.center + Offset(r * math.sin(a) * px, -(r * math.cos(a) - centerR) * px);
}

void main() {
  group('doubleZoomTarget', () {
    test('Checkout-Weg: nur wenn der nächste Dart ein Doppel ist', () {
      expect(doubleZoomTarget(route: [Segment.triple(20), Segment.double(8)]), isNull);
      expect(doubleZoomTarget(route: [Segment.double(8)]), Segment.double(8));
      expect(doubleZoomTarget(route: [Segment.double(20), Segment.double(10)]), Segment.double(20));
      expect(doubleZoomTarget(route: [Segment.bull]), Segment.bull);
      expect(doubleZoomTarget(route: [Segment.bull, Segment.double(20)]), isNull);
      expect(doubleZoomTarget(route: const []), isNull);
    });

    test('ohne Weg: genau ein Doppel als Ziel', () {
      expect(doubleZoomTarget(targets: {Segment.double(16)}), Segment.double(16));
      expect(doubleZoomTarget(targets: {Segment.triple(20)}), isNull);
      expect(doubleZoomTarget(targets: {Segment.single(20), Segment.double(20), Segment.triple(20)}), isNull);
    });
  });

  testWidgets('Zoom erscheint erst, wenn das Doppel dran ist, und verschwindet nach dem Checkout', (tester) async {
    final c = await pumpApp(tester);
    await c.read(activeGameProvider.notifier).start(GameCatalog.byId('x01')!, const {'startScore': 76}, seed: 7);
    c.read(routerProvider).go(Routes.play);
    await pumpFrames(tester);
    // T20 · D8: zuerst kein Zoom.
    expect(find.byKey(const Key('double-zoom')), findsNothing);

    (c.read(dartSourceProvider) as SimulatorSource).throwAt(BoardGeometry.centerOf(Segment.triple(20)));
    await pumpFrames(tester);
    expect(find.byKey(const Key('double-zoom')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('double-zoom-target'))).data, 'D8');

    // Antippen im Zoom wirft auf die Stelle, die man dort sieht.
    await tester.tapAt(zoomPoint(tester));
    await pumpFrames(tester);
    final game = c.read(activeGameProvider)!;
    expect(game.session.records.last.dart.segment, Segment.double(8));
    expect(game.ended, isTrue);
    expect(find.byKey(const Key('double-zoom')), findsNothing);
  });

  testWidgets('Zoom ist gedreht: links neben dem Ziel liegt das Nachbarfeld gegen den Uhrzeigersinn', (tester) async {
    final c = await x01OnD8(tester);
    await tester.tapAt(zoomPoint(tester, offset: -18));
    await pumpFrames(tester);
    // Neben der 8 liegt gegen den Uhrzeigersinn die 16.
    expect(c.read(activeGameProvider)!.session.records.last.dart.segment, Segment.double(16));
  });

  testWidgets('Am Telefon steht der Zoom als flacher Streifen über der Scheibe', (tester) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    await c.read(activeGameProvider.notifier).start(GameCatalog.byId('x01')!, const {'startScore': 40}, seed: 7);
    c.read(routerProvider).go(Routes.play);
    await pumpFrames(tester);
    final zoom = tester.getRect(find.byKey(const Key('double-zoom-board')));
    expect(zoom.width / zoom.height, closeTo(2.4, 0.01));
    expect(zoom.bottom, lessThan(tester.getRect(find.byKey(const Key('game-board'))).top));
  });

  testWidgets('In den Optionen abgeschaltet: kein Zoom', (tester) async {
    await x01OnD8(tester, prefs: {'settings.doubleZoom': false});
    expect(find.byKey(const Key('double-zoom')), findsNothing);
  });

  testWidgets('Schalter in den Optionen wird gespeichert', (tester) async {
    final c = await pumpApp(tester);
    c.read(routerProvider).go(Routes.settings);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('double-zoom-switch')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('double-zoom-switch')));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).doubleZoom, isFalse);
    expect(c.read(sharedPreferencesProvider).getBool('settings.doubleZoom'), isFalse);
  });

  testWidgets('Match: Zoom auf das Doppel des Spielers am Zug', (tester) async {
    final c = await pumpApp(tester);
    await c.read(matchControllerProvider.notifier).start(const MatchSetup(
      format: MatchFormat(startScore: 40, legsToWin: 1),
      players: [MatchPlayer.human('Ich'), MatchPlayer.bot('Robo', average: 60)],
    ));
    c.read(routerProvider).go(MatchRoutes.play);
    await pumpFrames(tester);
    expect(tester.widget<Text>(find.byKey(const Key('double-zoom-target'))).data, 'D20');
  });
}
