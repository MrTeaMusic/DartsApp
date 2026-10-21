import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/autodarts_live/domain/live_stats.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_controller.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_routes.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_live_source.dart';
import '../helpers/pump_app.dart';

Finder scrollableOf(String key) => find.descendant(of: find.byKey(Key(key)), matching: find.byType(Scrollable)).first;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeLiveSource live;

  DartSource factory(DartSourceKind kind, String host, int port) =>
      kind == DartSourceKind.autodartsLocal ? live = FakeLiveSource() : testSourceFactory(kind, host, port);

  Future<ProviderContainer> open(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
    final c = await pumpApp(tester, size: size, factory: factory, prefs: {'settings.sourceKind': 'autodartsLocal', 'settings.playView': 'look'});
    c.read(routerProvider).go(Routes.games);
    await settle(tester);
    await tester.tap(find.byKey(const Key('open-autodarts-live')));
    await settle(tester);
    return c;
  }

  testWidgets('Einstieg unter Modi, Darts erscheinen live, Beenden speichert', (tester) async {
    final c = await open(tester);
    expect(find.byKey(const Key('live-hint')), findsOneWidget);
    expect(find.text('Spiel dein Match wie gewohnt auf play.autodarts.io – DartLab schreibt mit.'), findsOneWidget);
    expect(find.byKey(const Key('source-status')), findsOneWidget);
    expect(find.byKey(const Key('live-heatmap')), findsOneWidget);

    live.dart('T20');
    live.dart('T20');
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('live-visit-score'))).data, '120');
    expect(tester.widget<Text>(find.byKey(const Key('live-darts'))).data, '2');

    live.dart('T20');
    live.takeout();
    live.visit(['S1', 'MISS', 'S5']);
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('live-darts'))).data, '6');
    expect(tester.widget<Text>(find.byKey(const Key('live-scores'))).data, '0 / 0 / 1');
    // Nach dem Takeout steht die letzte Aufnahme da.
    expect(find.text('Letzte Aufnahme'.toUpperCase()), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('live-recent-1')), 200,
        scrollable: find.descendant(of: find.byKey(const Key('live-left')), matching: find.byType(Scrollable)).first);
    expect(find.byKey(const Key('live-recent-1')), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const Key('live-end')), 200, scrollable: scrollableOf('live-right'));
    await tester.tap(find.byKey(const Key('live-end')));
    await settle(tester);
    expect(find.text('Session gespeichert: 6 Darts'), findsOneWidget);
    expect(find.byKey(const Key('open-autodarts-live')), findsOneWidget);
    final db = c.read(appDatabaseProvider);
    final sessions = await db.select(db.sessions).get();
    expect(sessions.single.gameId, autodartsLiveGameId);
    expect(sessions.single.dartCount, 6);
  });

  testWidgets('X01 mitzählen: Rest, Checkout-Weg und Leg verloren', (tester) async {
    final c = await open(tester, size: const Size(390, 844));
    await tester.scrollUntilVisible(find.byKey(const Key('live-x01-switch')), 200, scrollable: scrollableOf('live-list'));
    await tester.tap(find.byKey(const Key('live-x01-switch')));
    await settle(tester);
    await tester.drag(find.byKey(const Key('live-list')), const Offset(0, 2000));
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('live-visit-score'))).data, '501');

    live.visit(['T20', 'T20', 'T20']);
    live.visit(['T20', 'T20', 'T20']);
    live.dart('T20');
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('live-visit-score'))).data, '81');
    expect(find.byKey(const Key('live-route-label')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('live-leg-lost')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('live-leg-lost')));
    await settle(tester);
    expect(c.read(autodartsLiveProvider).x01!.legsLost, 1);
    expect(tester.widget<Text>(find.byKey(const Key('live-visit-score'))).data, '501');
    expect(find.text('Leg verloren – neues Leg ab 501'), findsOneWidget);
  });

  testWidgets('andere Datenquelle: Hinweis und Umstellen', (tester) async {
    final c = await pumpApp(tester, factory: factory);
    c.read(routerProvider).go(AutodartsLiveRoutes.live);
    await settle(tester);
    expect(find.byKey(const Key('live-needs-autodarts')), findsOneWidget);
    await tester.tap(find.byKey(const Key('live-switch-source')));
    await settle(tester);
    expect(c.read(settingsProvider).sourceKind, DartSourceKind.autodartsLocal);
    expect(find.byKey(const Key('live-hint')), findsOneWidget);
  });

  testWidgets('Verbindung weg: Hinweis mit Adresse', (tester) async {
    await open(tester);
    live.setStatus(SourceStatus(SourcePhase.reconnecting, nextRetry: DateTime.now().add(const Duration(seconds: 4))));
    await settle(tester);
    expect(find.textContaining('127.0.0.1:3180'), findsOneWidget);
  });

  testWidgets('Optionen: automatisch mitschreiben öffnet Autodarts Live beim Start', (tester) async {
    await pumpApp(tester, factory: factory, prefs: {
      'settings.sourceKind': 'autodartsLocal',
      'settings.autodartsLiveAutoStart': true,
    });
    await settle(tester);
    expect(find.byKey(const Key('live-hint')), findsOneWidget);
  });
}
