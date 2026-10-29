import 'package:dartlab/core/lite.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_routes.dart';
import 'package:dartlab/features/board/presentation/dartboard_view.dart';
import 'package:dartlab/features/dart_source/domain/board_control.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_live_source.dart';
import '../helpers/pump_app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const phone = Size(390, 844);
const desktop = Size(1280, 800);

String snack(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('board-help-result'))).data!;

void main() {
  late FakeLiveSource live;

  DartSource factory(DartSourceKind kind, String host, int port) =>
      kind == DartSourceKind.autodartsLocal ? live = FakeLiveSource() : testSourceFactory(kind, host, port);

  Future<ProviderContainer> open(
    WidgetTester tester,
    String route, {
    Size size = desktop,
    Map<String, Object> prefs = const {'settings.sourceKind': 'autodartsLocal'},
    List<Override> overrides = const [],
  }) async {
    final c = await pumpApp(tester, size: size, factory: factory, prefs: prefs, overrides: [...overrides]);
    c.read(routerProvider).go(route);
    await settle(tester);
    return c;
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('board-help')));
    await settle(tester);
  }

  group('Menü im Autodarts-Live-Bildschirm', () {
    testWidgets('Knopf ist da, Menü zeigt die drei Aktionen und den Hinweis zu ungeprüften Pfaden', (tester) async {
      await open(tester, AutodartsLiveRoutes.live);
      expect(find.byKey(const Key('board-help')), findsOneWidget);
      await openMenu(tester);
      expect(find.text('Board-Hilfe'), findsOneWidget);
      expect(find.text('Neu kalibrieren'), findsOneWidget);
      expect(find.text('Dartboard stoppen'), findsOneWidget);
      expect(find.text('Dartboard starten'), findsNothing);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.byKey(const Key('board-help-unverified')), findsOneWidget);
      expect(find.textContaining('noch nicht bestätigt'), findsOneWidget);
      // Ein bloßes Öffnen schickt nichts.
      expect(live.commands, isEmpty);
    });

    testWidgets('ist die Erkennung angehalten, heißt der Eintrag „Dartboard starten“', (tester) async {
      await open(tester, AutodartsLiveRoutes.live);
      live.setBoardRunning(false);
      await settle(tester);
      await openMenu(tester);
      expect(find.text('Dartboard starten'), findsOneWidget);
      expect(find.text('Dartboard stoppen'), findsNothing);
      await tester.tap(find.byKey(const Key('board-help-start')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('board-help-send')));
      await settle(tester);
      expect(live.commands.single.$1, BoardAction.start);
    });

    testWidgets('fragt vorher nach: Abbrechen sendet nichts, Senden sendet als Knopfdruck', (tester) async {
      await open(tester, AutodartsLiveRoutes.live);
      await openMenu(tester);
      await tester.tap(find.byKey(const Key('board-help-recalibrate')));
      await settle(tester);
      expect(find.byKey(const Key('board-help-confirm')), findsOneWidget);
      expect(find.textContaining('automatischen Kalibrierung'), findsOneWidget);
      expect(live.commands, isEmpty);

      await tester.tap(find.byKey(const Key('board-help-cancel')));
      await settle(tester);
      expect(find.byKey(const Key('board-help-confirm')), findsNothing);
      expect(live.commands, isEmpty);
      expect(find.byKey(const Key('board-help-result')), findsNothing);

      await openMenu(tester);
      await tester.tap(find.byKey(const Key('board-help-recalibrate')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('board-help-send')));
      await settle(tester);
      expect(live.commands, hasLength(1));
      expect(live.commands.single.$1, BoardAction.recalibrate);
      expect(live.commands.single.userInitiated, isTrue);
      expect(snack(tester), 'Neu kalibrieren: Das Board hat mit HTTP 200 geantwortet. Ob es gewirkt hat, siehst du am Board.');
    });

    testWidgets('Fehler: HTTP-Status, Rückfall und Fehlertext werden gezeigt', (tester) async {
      await open(tester, AutodartsLiveRoutes.live);

      Future<void> run(String key) async {
        await openMenu(tester);
        await tester.tap(find.byKey(Key(key)));
        await settle(tester);
        await tester.tap(find.byKey(const Key('board-help-send')));
        // Der alte Hinweis blendet erst aus, dann kommt der neue.
        await settle(tester);
        await settle(tester);
      }

      live.nextResult = const BoardCommandResult(statusCode: 404, path: '/api/config/calibration/auto');
      await run('board-help-recalibrate');
      expect(snack(tester), contains('HTTP 404'));
      expect(snack(tester), contains('nicht angenommen'));
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      live.nextResult = const BoardCommandResult(
          statusCode: 200, path: '/api/reset', fellBackFrom: '/api/restart', fallbackStatusCode: 405);
      await run('board-help-refresh');
      expect(snack(tester), contains('HTTP 405'));
      expect(snack(tester), contains('Reset'));
      expect(snack(tester), contains('HTTP 200'));

      live.nextResult = const BoardCommandResult(error: 'Zeitüberschreitung', path: '/api/stop');
      await run('board-help-stop');
      expect(snack(tester), 'Dartboard stoppen: Das Board wurde nicht erreicht (Zeitüberschreitung).');
    });

    testWidgets('im Mithör-Modus warnt der Dialog vor Online-Matches, der Knopf darf trotzdem senden', (tester) async {
      await open(tester, AutodartsLiveRoutes.live);
      live.listenOnly = true;
      await openMenu(tester);
      await tester.tap(find.byKey(const Key('board-help-refresh')));
      await settle(tester);
      expect(find.byKey(const Key('board-help-live-warning')), findsOneWidget);
      await tester.tap(find.byKey(const Key('board-help-send')));
      await settle(tester);
      expect(live.commands.single.userInitiated, isTrue);
      expect(snack(tester), contains('HTTP 200'));
    });

    testWidgets('ohne Mithör-Modus keine Warnung', (tester) async {
      await open(tester, AutodartsLiveRoutes.live);
      await openMenu(tester);
      await tester.tap(find.byKey(const Key('board-help-refresh')));
      await settle(tester);
      expect(find.byKey(const Key('board-help-live-warning')), findsNothing);
    });

    testWidgets('Telefon: Menü, Dialog und Hinweis laufen nicht über', (tester) async {
      await open(tester, AutodartsLiveRoutes.live, size: phone);
      await openMenu(tester);
      expect(find.byKey(const Key('board-help-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('board-help-refresh')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('board-help-send')));
      await settle(tester);
      expect(find.byKey(const Key('board-help-result')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('klassische Ansicht (Spielansicht „Look“) hat den Knopf in der Kopfzeile', (tester) async {
      await open(tester, AutodartsLiveRoutes.live,
          prefs: {'settings.sourceKind': 'autodartsLocal', 'settings.playView': 'look', 'settings.look': 'tv'});
      expect(find.byKey(const Key('live-heatmap')), findsOneWidget);
      expect(find.byKey(const Key('board-help')), findsOneWidget);
      await openMenu(tester);
      expect(find.text('Neu kalibrieren'), findsOneWidget);
    });
  });

  group('Wo das Menü nicht erscheint', () {
    testWidgets('Boardansicht mit lokalem Autodarts-Board: Knopf da', (tester) async {
      await open(tester, Routes.board);
      expect(find.byKey(const Key('board-help')), findsOneWidget);
    });

    testWidgets('Spielansicht mit Autodarts: Knopf und Rahmen', (tester) async {
      await open(tester, Routes.games, prefs: {
        'settings.sourceKind': 'autodartsLocal',
        'game.config.bull_drill': '{"visits":1}',
      });
      await tester.scrollUntilVisible(find.byKey(const Key('game-bull_drill')), 200, scrollable: find.byType(Scrollable).last);
      await tester.ensureVisible(find.byKey(const Key('game-bull_drill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('game-bull_drill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-game')));
      await settle(tester);
      expect(find.byKey(const Key('game-board')), findsOneWidget);
      expect(find.byKey(const Key('board-help')), findsOneWidget);
      expect(find.byKey(const Key('board-frame-ready')), findsOneWidget);
    });

    testWidgets('Simulator: weder Knopf noch Rahmen', (tester) async {
      await open(tester, Routes.board, prefs: const {});
      expect(find.byKey(const Key('dartboard')), findsOneWidget);
      expect(find.byKey(const Key('board-help')), findsNothing);
      expect(find.byKey(const Key('board-frame')), findsNothing);
    });

    testWidgets('manuelle Eingabe: weder Knopf noch Rahmen', (tester) async {
      await open(tester, Routes.board, prefs: {'settings.sourceKind': 'manual'});
      expect(find.byKey(const Key('board-help')), findsNothing);
      expect(find.byKey(const Key('board-frame')), findsNothing);
    });

    testWidgets('Lite: weder Knopf noch Rahmen', (tester) async {
      await open(tester, Routes.board, overrides: [liteProvider.overrideWithValue(true)]);
      expect(find.byKey(const Key('board-help')), findsNothing);
      expect(find.byKey(const Key('board-frame')), findsNothing);
    });

    testWidgets('ohne Verbindung: kein Knopf, aber roter Rahmen', (tester) async {
      await open(tester, AutodartsLiveRoutes.live);
      expect(find.byKey(const Key('board-help')), findsOneWidget);
      live.setStatus(const SourceStatus(SourcePhase.reconnecting, message: 'weg'));
      await settle(tester);
      expect(find.byKey(const Key('board-help')), findsNothing);
      expect(find.byKey(const Key('board-frame-offline')), findsOneWidget);
      live.setStatus(SourceStatus.ready);
      await settle(tester);
      expect(find.byKey(const Key('board-help')), findsOneWidget);
    });
  });

  group('Rahmen um die Scheibe', () {
    Future<void> expectFrame(WidgetTester tester, BoardReadiness r, String word) async {
      expect(find.byKey(Key('board-frame-${r.name}')), findsOneWidget, reason: r.name);
      expect(find.descendant(of: find.byKey(const Key('board-frame')), matching: find.text(word)), findsOneWidget);
      expect(find.bySemanticsLabel('Dartboard: $word'), findsOneWidget);
    }

    testWidgets('grün bereit, gelb im Takeout, grau gestoppt, rot offline', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, AutodartsLiveRoutes.live);
      await expectFrame(tester, BoardReadiness.ready, 'Bereit');

      live.emit(TakeoutStarted(DateTime.now()));
      await settle(tester);
      await expectFrame(tester, BoardReadiness.takeout, 'Takeout');

      live.emit(TakeoutFinished(DateTime.now()));
      await settle(tester);
      await expectFrame(tester, BoardReadiness.ready, 'Bereit');

      live.setBoardRunning(false);
      await settle(tester);
      await expectFrame(tester, BoardReadiness.stopped, 'Gestoppt');
      live.setBoardRunning(true);

      live.setStatus(const SourceStatus(SourcePhase.connecting));
      await settle(tester);
      await expectFrame(tester, BoardReadiness.connecting, 'Verbinde');

      live.setStatus(const SourceStatus(SourcePhase.reconnecting));
      await settle(tester);
      await expectFrame(tester, BoardReadiness.offline, 'Offline');
      handle.dispose();
    });

    testWidgets('verschiebt das Layout nicht: Rahmen und Scheibe haben dieselbe Fläche, in jedem Zustand', (tester) async {
      await open(tester, AutodartsLiveRoutes.live);
      final board = find.byType(DartboardView).first;
      final before = tester.getRect(board);
      for (final s in [
        const SourceStatus(SourcePhase.reconnecting),
        SourceStatus.ready,
      ]) {
        live.setStatus(s);
        await settle(tester);
        expect(tester.getRect(board), before);
        expect(tester.getRect(find.byKey(const Key('board-frame'))), before);
      }
    });

    for (final look in ['tv', 'arena', 'clean', 'lab']) {
      testWidgets('Look $look auf dem Telefon ohne Überlauf', (tester) async {
        await open(tester, AutodartsLiveRoutes.live,
            size: phone, prefs: {'settings.sourceKind': 'autodartsLocal', 'settings.look': look});
        live.emit(TakeoutStarted(DateTime.now()));
        await settle(tester);
        expect(find.byKey(const Key('board-frame-takeout')), findsOneWidget);
        expect(find.byKey(const Key('board-help')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
