import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/design/arena/arena_screen.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_controller.dart';
import 'package:dartlab/features/board/presentation/dartboard_view.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_live_source.dart';
import '../helpers/pump_app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const phone = Size(390, 844);
const desktop = Size(1440, 900);

String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

/// Autodarts Live in der Arena-Spielansicht (Standard der Spielansicht).
void main() {
  late FakeLiveSource live;

  DartSource factory(DartSourceKind kind, String host, int port) =>
      kind == DartSourceKind.autodartsLocal ? live = FakeLiveSource() : testSourceFactory(kind, host, port);

  Future<ProviderContainer> open(
    WidgetTester tester, {
    Size size = desktop,
    bool x01 = false,
    Map<String, Object> prefs = const {},
  }) async {
    final c = await pumpApp(tester, size: size, factory: factory, prefs: {
      'settings.sourceKind': 'autodartsLocal',
      if (x01) 'live.x01': '501;double',
      ...prefs,
    });
    c.read(routerProvider).go(Routes.games);
    await settle(tester);
    await tester.tap(find.byKey(const Key('open-autodarts-live')));
    await settle(tester);
    return c;
  }

  group('ohne X01', () {
    testWidgets('wartet auf den ersten Dart: Arena ohne Navigation, eine Tafel, keine Gegnertafel', (tester) async {
      await open(tester);
      expect(find.byType(ArenaScreen), findsOneWidget);
      // Vollbild wie Match und Solo: weder Seitenleiste noch Navigationsleiste.
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const Key('live-leave')), findsOneWidget);
      expect(find.byKey(const Key('source-status')), findsOneWidget);
      expect(find.text('Warte auf den ersten Dart …'), findsOneWidget);
      expect(find.text('Nur Darts'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('live-slot-$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('live-board')), findsOneWidget);
      // Nur eine Tafel: links, die rechte Spalte gehört der Session.
      final panel = tester.getRect(find.byKey(const Key('live-remaining')));
      expect(panel.center.dx, lessThan(desktop.width / 2));
      expect(find.byKey(const Key('live-session-panel')), findsOneWidget);
      expect(find.byKey(const Key('live-x01-switch')), findsOneWidget);
      // Keine Leg-Knöpfe ohne X01.
      expect(find.byKey(const Key('live-leg-lost')), findsNothing);
      expect(find.byKey(const Key('live-leg-restart')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Darts erscheinen in der Wurfleiste, nach dem Takeout steht die Aufnahme in der Tabelle', (tester) async {
      await open(tester);
      live.dart('T20');
      live.dart('S5');
      await settle(tester);
      expect(text(tester, 'live-visit-score'), '65');
      expect(find.descendant(of: find.byKey(const Key('live-slot-0')), matching: find.text('T20')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('live-slot-1')), matching: find.text('S5')), findsOneWidget);
      expect(find.text('Aktuelle Aufnahme'), findsOneWidget);

      live.dart('S1');
      live.takeout();
      live.visit(['T20', 'T20', 'T20']);
      await settle(tester);
      // Nach dem Takeout: die letzte Aufnahme bleibt stehen (gedämpft).
      expect(text(tester, 'live-visit-score'), '180');
      expect(find.text('Letzte Aufnahme'), findsOneWidget);
      // Tafel: Rohschnitt = (66 + 180) / 6 * 3, Punkte und laufender Schnitt je Aufnahme.
      expect(text(tester, 'live-remaining'), '123,0');
      expect(find.descendant(of: find.byKey(const Key('live-visits-row-0')), matching: find.text('66')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('live-visits-row-0')), matching: find.text('66,0')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('live-visits-row-1')), matching: find.text('180')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('live-visits-row-1')), matching: find.text('123,0')), findsOneWidget);
      expect(text(tester, 'live-leg-darts'), '6');
      expect(find.byKey(const Key('live-visits-start')), findsNothing);
    });

    testWidgets('Dart von Hand korrigieren: Stift, Position weg, Korrektur-Blatt im Arena-Theme', (tester) async {
      final c = await open(tester);
      live.dart('T20');
      live.dart('S5');
      await settle(tester);
      expect(find.byIcon(Icons.edit_rounded), findsNothing);
      await tester.tap(find.byKey(const Key('live-slot-1')));
      await settle(tester);
      expect(find.byKey(const Key('live-fix-title')), findsOneWidget);
      // Das Blatt läuft im dunklen Arena-Theme (nicht im hellen Look der App).
      final sheet = find.byKey(const Key('live-fix-title'));
      expect(Theme.of(tester.element(sheet)).brightness, Brightness.dark);
      await tester.tap(find.byKey(const Key('fix-triple')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('fix-19')));
      await settle(tester);
      expect(find.descendant(of: find.byKey(const Key('live-slot-1')), matching: find.text('T19')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('live-slot-1')), matching: find.byIcon(Icons.edit_rounded)), findsOneWidget);
      expect(text(tester, 'live-visit-score'), '117');
      expect(c.read(autodartsLiveProvider).current[1].position, isNull);
    });

    testWidgets('„+“ am ersten freien Platz ergänzt einen vergessenen Dart', (tester) async {
      await open(tester);
      live.dart('T20');
      await settle(tester);
      await tester.tap(find.byKey(const Key('live-slot-1')));
      await settle(tester);
      expect(find.byKey(const Key('live-fix-title')), findsOneWidget);
      await tester.tap(find.byKey(const Key('fix-19')));
      await settle(tester);
      expect(find.descendant(of: find.byKey(const Key('live-slot-1')), matching: find.text('S19')), findsOneWidget);
      expect(text(tester, 'live-visit-score'), '79');
    });

    testWidgets('Heatmap lässt sich auf dem Board einblenden', (tester) async {
      await open(tester);
      live.visit(['T20', 'S5', 'S1']);
      await settle(tester);
      bool heat() => tester.widget<DartboardView>(find.byKey(const Key('live-board'))).showHeat;
      expect(heat(), isFalse);
      await tester.tap(find.byKey(const Key('live-heat-toggle')));
      await settle(tester);
      expect(heat(), isTrue);
    });

    testWidgets('Beenden speichert, zeigt den Hinweis und geht zurück zur Spielauswahl', (tester) async {
      final c = await open(tester);
      live.visit(['T20', 'S5', 'S1']);
      await settle(tester);
      await tester.tap(find.byKey(const Key('live-end')));
      await settle(tester);
      expect(find.text('Session gespeichert: 3 Darts'), findsOneWidget);
      expect(find.byKey(const Key('open-autodarts-live')), findsOneWidget);
      final db = c.read(appDatabaseProvider);
      expect((await db.select(db.sessions).get()).single.dartCount, 3);
    });

    testWidgets('Verlassen führt zurück zur Spielauswahl', (tester) async {
      await open(tester);
      live.visit(['T20', 'S5', 'S1']);
      await settle(tester);
      await tester.tap(find.byKey(const Key('live-leave')));
      await settle(tester);
      expect(find.byKey(const Key('open-autodarts-live')), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('Session beendet (Controller): Ergebnis in der Mitte, nichts mehr bedienbar', (tester) async {
      final c = await open(tester);
      live.visit(['T20', 'S5', 'S1']);
      await settle(tester);
      await c.read(autodartsLiveProvider.notifier).end();
      await settle(tester);
      expect(find.byKey(const Key('live-ended')), findsOneWidget);
      expect(text(tester, 'live-ended-saved'), 'Session gespeichert: 3 Darts');
      expect(find.byKey(const Key('live-board')), findsNothing);
      expect(find.byKey(const Key('live-end')), findsNothing);
      expect(find.byKey(const Key('live-leave')), findsOneWidget);
    });
  });

  group('mit X01 mitzählen', () {
    testWidgets('Rest, Tabelle mit Bust, Weg und Legs wie im Vorbild', (tester) async {
      await open(tester, x01: true);
      expect(find.text('SI-DO'), findsOneWidget);
      expect(find.text('501'), findsWidgets);
      expect(text(tester, 'live-remaining'), '501');
      live.visit(['T20', 'T20', 'T20']);
      live.visit(['T20', 'T20', 'T20']);
      live.visit(['T20', 'T20', 'T20']);
      live.dart('T20');
      await settle(tester);
      // 501 → 321 → 141 → Bust (bleibt 141); in der laufenden Aufnahme T20 → Rest 81.
      expect(text(tester, 'live-remaining'), '81');
      expect(find.byKey(const Key('live-visits-start')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('live-visits-row-0')), matching: find.text('321')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('live-visits-row-2')), matching: find.text('141')), findsOneWidget);
      expect(find.byKey(const Key('visit-bust-2')), findsOneWidget);
      expect(find.byKey(const Key('live-route-label')), findsOneWidget);
      expect(text(tester, 'live-route-label').startsWith('Checkout-Weg'), isTrue);
      expect(text(tester, 'live-visit-score'), '60');
      expect(find.text('Leg 1 · 0:0'), findsOneWidget);
      expect(find.byKey(const Key('live-leg-lost')), findsOneWidget);
    });

    testWidgets('Bust zeigt BUST in der Wurfleiste und die Meldung', (tester) async {
      await open(tester, x01: true);
      live.visit(['T20', 'T20', 'T20']);
      live.visit(['T20', 'T20', 'T20']);
      live.dart('T20');
      live.dart('T20');
      live.dart('T20');
      await settle(tester);
      expect(text(tester, 'live-visit-score'), 'BUST');
      expect(text(tester, 'live-event'), 'Bust!');
      expect(text(tester, 'live-remaining'), '141');
    });

    testWidgets('Leg verloren: Rest zurück, Hinweis, Legs 0:1', (tester) async {
      final c = await open(tester, x01: true);
      live.visit(['T20', 'T20', 'T20']);
      await settle(tester);
      expect(text(tester, 'live-remaining'), '321');
      await tester.tap(find.byKey(const Key('live-leg-lost')));
      await settle(tester);
      expect(c.read(autodartsLiveProvider).x01!.legsLost, 1);
      expect(text(tester, 'live-remaining'), '501');
      expect(text(tester, 'live-legs-won'), '0:1');
      expect(find.text('Leg verloren – neues Leg ab 501'), findsOneWidget);
      expect(find.byKey(const Key('live-visits-row-0')), findsNothing);
    });

    testWidgets('Leg neu starten: Rest zurück auf den Startwert', (tester) async {
      await open(tester, x01: true);
      live.visit(['T20', 'T20', 'T20']);
      await settle(tester);
      await tester.tap(find.byKey(const Key('live-leg-restart')));
      await settle(tester);
      expect(text(tester, 'live-remaining'), '501');
    });

    testWidgets('Letzte Aufnahmen im Blatt: Dart einer älteren Aufnahme korrigieren, Tabelle rechnet neu', (tester) async {
      await open(tester, size: phone, x01: true);
      live.visit(['T20', 'T20', 'T20']);
      live.visit(['S1', 'S1', 'S1']);
      await settle(tester);
      expect(text(tester, 'live-remaining'), '318');
      await tester.tap(find.byKey(const Key('live-corrections')));
      await settle(tester);
      expect(find.byKey(const Key('live-recent-0')), findsOneWidget);
      // Das Blatt zeigt nur die Aufnahmen, nicht die ganze Session.
      expect(find.byKey(const Key('live-x01-switch')), findsNothing);
      await tester.tap(find.byKey(const Key('live-recent-0-dart-0')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('fix-20')));
      await settle(tester);
      Navigator.of(tester.element(find.byKey(const Key('live-recent-0')))).pop();
      await settle(tester);
      // S1 → S20 in der zweiten Aufnahme: 20 + 1 + 1 = 22 statt 3.
      expect(text(tester, 'live-remaining'), '299');
      expect(find.descendant(of: find.byKey(const Key('live-visits-row-1')), matching: find.text('299')), findsOneWidget);
    });

    testWidgets('Breit stehen die letzten Aufnahmen in der rechten Spalte und sind antippbar', (tester) async {
      await open(tester, x01: true);
      live.visit(['T20', 'T20', 'T20']);
      live.visit(['S1', 'S1', 'S1']);
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('live-recent-0-dart-0')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('live-recent-0-dart-0')));
      await settle(tester);
      expect(find.byKey(const Key('live-fix-title')), findsOneWidget);
      expect(find.text('Aufnahme 2 · Dart 1'), findsOneWidget);
    });

    testWidgets('Umschalten im Seitenfeld: X01 an, Tafel zeigt den Rest', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('live-leg-lost')), findsNothing);
      await tester.tap(find.byKey(const Key('live-x01-switch')));
      await settle(tester);
      expect(text(tester, 'live-remaining'), '501');
      expect(find.byKey(const Key('live-leg-lost')), findsOneWidget);
    });
  });

  group('Telefon', () {
    testWidgets('Arena in einer Spalte, Session im Blatt, X01 dort umschaltbar', (tester) async {
      final c = await open(tester, size: phone);
      expect(find.byType(ArenaScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      // Keine rechte Spalte; die Session liegt hinter dem Symbol oben rechts.
      expect(find.byKey(const Key('live-session-panel')), findsNothing);
      live.visit(['T20', 'S5', 'S1']);
      await settle(tester);
      await tester.tap(find.byKey(const Key('live-session-open')));
      await settle(tester);
      expect(find.byKey(const Key('live-session-sheet')), findsOneWidget);
      final sheet = find.byKey(const Key('live-x01-switch'));
      expect(Theme.of(tester.element(sheet)).brightness, Brightness.dark);
      await tester.tap(sheet);
      await settle(tester);
      expect(c.read(autodartsLiveProvider).x01Config, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('X01 auf dem Telefon: Tabelle, Weg und Leg-Knöpfe ohne Überlauf', (tester) async {
      await open(tester, size: phone, x01: true);
      live.visit(['T20', 'T20', 'T20']);
      live.visit(['T20', 'S5', 'S1']);
      live.dart('T20');
      await settle(tester);
      expect(text(tester, 'live-remaining'), '195');
      expect(find.byKey(const Key('live-leg-lost')), findsOneWidget);
      expect(find.byKey(const Key('live-end')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('andere Spielansicht', () {
    testWidgets('„Wie das gewählte Design“: die bisherige Seite mit Navigation', (tester) async {
      await open(tester, prefs: {'settings.playView': 'look'});
      expect(find.byType(ArenaScreen), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byKey(const Key('live-hint')), findsOneWidget);
    });

    testWidgets('Look Arena zeigt die Arena-Ansicht auch bei „Wie das gewählte Design“', (tester) async {
      await open(tester, prefs: {'settings.playView': 'look', 'settings.look': 'arena'});
      expect(find.byType(ArenaScreen), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('Datenquelle ist nicht Autodarts: Hinweis mit Navigation, keine Arena', (tester) async {
      final c = await pumpApp(tester, factory: factory);
      c.read(routerProvider).go('/training/autodarts-live');
      await settle(tester);
      expect(find.byKey(const Key('live-needs-autodarts')), findsOneWidget);
      expect(find.byType(ArenaScreen), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
    });
  });
}
