import 'package:dartlab/core/design/dart_look.dart';
import 'package:dartlab/core/design/looks.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/plans/presentation/plan_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/pump_app.dart';
import 'stats_profiles_test.dart' show seed, seedBobs;

ThemeData themeOf(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).first));

Future<void> frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('Standard ist TV, dunkel, ohne Helligkeitswahl', (tester) async {
    await pumpApp(tester);
    final theme = themeOf(tester);
    expect(theme.extension<DartLook>()!.id, DartLookId.tv);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, LookPalettes.tv.primary);

    await tester.tap(find.text('Optionen').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('look-tv')), findsOneWidget);
    expect(find.byKey(const Key('theme-selector')), findsNothing);
    expect(find.byKey(const Key('theme-fixed')), findsOneWidget);
  });

  testWidgets('Look-Auswahl: Wechsel wirkt sofort und wird gespeichert', (tester) async {
    final container = await pumpApp(tester);
    await tester.tap(find.text('Optionen').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('look-clean')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).look, DartLookId.clean);
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getString('settings.look'), 'clean');
    var theme = themeOf(tester);
    expect(theme.extension<DartLook>()!.id, DartLookId.clean);
    // Clean folgt der Systemhelligkeit (im Test hell).
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.primary, LookPalettes.cleanLight.primary);
    expect(find.byKey(const Key('theme-selector')), findsOneWidget);

    // Manuell auf dunkel.
    await tester.tap(find.text('Dunkel'));
    await tester.pumpAndSettle();
    theme = themeOf(tester);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, LookPalettes.cleanDark.primary);

    await tester.tap(find.byKey(const Key('look-lab')));
    await tester.pumpAndSettle();
    expect(prefs.getString('settings.look'), 'lab');
    theme = themeOf(tester);
    expect(theme.extension<DartLook>()!.id, DartLookId.lab);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, LookPalettes.lab.primary);
    expect(find.byKey(const Key('theme-selector')), findsNothing);
  });

  testWidgets('Gespeicherter Look wird beim Start geladen', (tester) async {
    await pumpApp(tester, prefs: {'settings.look': 'lab'});
    expect(themeOf(tester).extension<DartLook>()!.id, DartLookId.lab);
  });

  testWidgets('Unbekannter Look fällt auf TV zurück', (tester) async {
    SharedPreferences.setMockInitialValues({'settings.look': 'gibt-es-nicht'});
    final prefs = await SharedPreferences.getInstance();
    expect(AppSettings.load(prefs).look, DartLookId.tv);
  });

  testWidgets('Farbbedeutungen bleiben in allen Looks unterscheidbar', (tester) async {
    for (final id in DartLookId.values) {
      for (final b in Brightness.values) {
        final c = LookPalettes.of(id, b).colors;
        expect({c.highlight, c.tripleHit, c.doubleHit}.length, 3, reason: '$id $b');
      }
    }
  });

  // Alle Hauptbildschirme in jedem Look auf Telefonbreite: keine Überläufe.
  for (final look in DartLookId.values) {
    testWidgets('Look ${look.name}: alle Bildschirme bei 390 px ohne Fehler', (tester) async {
      final c = await pumpApp(tester, size: const Size(390, 844), prefs: {'settings.look': look.name});
      await seed(c);
      await seedBobs(c);
      final router = c.read(routerProvider);

      Future<void> visit(String route) async {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
      }

      await visit(Routes.home);
      await visit(Routes.games);
      await visit(Routes.gameSetup('checkout'));
      await visit(Routes.gameSetup('x01_solo'));
      await visit(PlanRoutes.list);
      await visit(Routes.board);
      await visit(Routes.settings);
      await visit(Routes.stats);
      for (final tab in ['scoring', 'doubles', 'games', 'records', 'overview']) {
        await tester.tap(find.byKey(Key('stats-tab-$tab')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'stats-$tab');
      }

      // Spielansicht mit Checkout-Weg, danach das Ergebnis.
      await c.read(activeGameProvider.notifier).start(GameCatalog.byId('checkout')!, const {}, seed: 7);
      router.go(Routes.play);
      await frames(tester);
      final route = c.read(activeGameProvider)!.game.display.suggestion!;
      (c.read(dartSourceProvider) as SimulatorSource).throwAt(BoardGeometry.centerOf(route.first));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'play');
      await c.read(activeGameProvider.notifier).end();
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'result');
      await c.read(activeGameProvider.notifier).close();
      await frames(tester, 3);
    });
  }
}
