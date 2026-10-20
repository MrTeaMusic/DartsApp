import 'package:dartlab/core/design/app_theme.dart';
import 'package:dartlab/core/design/arena/arena_background.dart';
import 'package:dartlab/core/design/arena/arena_palette.dart';
import 'package:dartlab/core/design/arena/arena_screen.dart';
import 'package:dartlab/core/design/dart_look.dart';
import 'package:dartlab/core/design/looks.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:dartlab/features/matches/presentation/match_routes.dart';
import 'package:dartlab/features/plans/presentation/plan_routes.dart';
import 'package:dartlab/features/quiz/presentation/quiz_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

ThemeData themeOf(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).first));

void main() {
  group('Look Arena: Theme und Einstellung', () {
    test('byName kennt "arena", unbekannte Namen fallen auf TV zurück', () {
      expect(DartLookId.byName('arena'), DartLookId.arena);
      expect(DartLookId.byName('gibt-es-nicht'), DartLookId.tv);
      expect(DartLookId.arena.supportsLight, isFalse);
    });

    test('Theme baut dunkel, auch bei heller Anfrage, mit den Farben der Spielansicht', () {
      for (final b in Brightness.values) {
        final t = AppTheme.build(DartLookId.arena, b);
        expect(t.brightness, Brightness.dark);
        expect(t.extension<DartLook>()!.id, DartLookId.arena);
        expect(t.colorScheme.surface, ArenaPalette.surface);
        expect(t.colorScheme.primary, LookPalettes.arena.primary);
        // Durchsichtig: der Grund mit den Dreiecken liegt hinter der App.
        expect(t.scaffoldBackgroundColor, Colors.transparent);
      }
      expect(ArenaPalette.theme.extension<DartLook>()!.id, DartLookId.arena);
      expect(DartLooks.arena.radiusL, 28);
      expect(DartLooks.arena.pill, isTrue);
      expect(DartLooks.tv.pill, isFalse);
    });

    test('Palette: Textfarben haben auf allen Flächen genug Kontrast', () {
      double lum(Color c) => c.computeLuminance();
      double contrast(Color a, Color b) {
        final l1 = lum(a), l2 = lum(b);
        return (l1 > l2 ? l1 + 0.05 : l2 + 0.05) / (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
      }

      const p = LookPalettes.arena;
      for (final bg in [p.background, p.surface, p.surfaceHigh]) {
        expect(contrast(p.text, bg), greaterThan(7), reason: 'Text auf $bg');
        expect(contrast(p.muted, bg), greaterThan(4.5), reason: 'gedämpfter Text auf $bg');
      }
      expect(contrast(p.primary, p.surface), greaterThan(3), reason: 'Akzent als Schrift auf Tafeln');
      expect(contrast(Colors.white, ArenaPalette.gradientStart), greaterThan(4.5));
      expect(contrast(Colors.white, ArenaPalette.gradientEnd), greaterThan(4));
    });

    testWidgets('Auswahl in den Optionen: vier Looks, Arena wirkt sofort und wird gespeichert', (tester) async {
      final c = await pumpApp(tester);
      c.read(routerProvider).go(Routes.settings);
      await tester.pumpAndSettle();
      for (final id in DartLookId.values) {
        await tester.scrollUntilVisible(find.byKey(Key('look-${id.name}')), 200, scrollable: find.byType(Scrollable).first);
        expect(find.byKey(Key('look-${id.name}')), findsOneWidget);
      }
      expect(DartLookId.values.length, 4);
      await tester.ensureVisible(find.byKey(const Key('look-arena')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('look-arena')));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).look, DartLookId.arena);
      expect(c.read(sharedPreferencesProvider).getString('settings.look'), 'arena');
      expect(themeOf(tester).extension<DartLook>()!.id, DartLookId.arena);
      expect(themeOf(tester).brightness, Brightness.dark);
      // Der Grund liegt hinter der ganzen App.
      expect(find.byType(ArenaBackground), findsWidgets);
      // Kein Hell/Dunkel-Schalter wie bei TV und Lab.
      expect(find.byKey(const Key('theme-selector')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Der Hintergrund der App ist nur bei Arena gesetzt', (tester) async {
      await pumpApp(tester, prefs: {'settings.look': 'tv'});
      // Die Spielansicht-Arena bringt ihren eigenen Grund mit; sonst keiner.
      expect(find.byType(ArenaBackground), findsNothing);
    });

    testWidgets('Look Arena: "Spielansicht wie das gewählte Design" zeigt die Arena-Spielansicht', (tester) async {
      final c = await pumpApp(tester, size: const Size(1440, 900), prefs: {'settings.look': 'arena', 'settings.playView': 'look'});
      expect(c.read(settingsProvider).arenaPlay, isTrue);
      await c.read(matchControllerProvider.notifier).start(const MatchSetup(
        format: MatchFormat(startScore: 501, legsToWin: 2),
        players: [MatchPlayer.human('Ben'), MatchPlayer.human('Gast')],
      ));
      c.read(routerProvider).go(MatchRoutes.play);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ArenaScreen), findsOneWidget);
      expect(find.byKey(const Key('match-visits-0-start')), findsOneWidget);
    });

    testWidgets('Anderer Look + "wie das gewählte Design": bisherige Ansicht', (tester) async {
      final c = await pumpApp(tester, size: const Size(1440, 900), prefs: {'settings.look': 'clean', 'settings.playView': 'look'});
      expect(c.read(settingsProvider).arenaPlay, isFalse);
    });
  });

  for (final size in [const Size(390, 844), const Size(1440, 900), const Size(820, 1180)]) {
    testWidgets('Look Arena: Hauptbildschirme ohne Überlauf (${size.width.toInt()}x${size.height.toInt()})', (tester) async {
      final c = await pumpApp(tester, size: size, prefs: {'settings.look': 'arena'});
      final router = c.read(routerProvider);

      Future<void> visit(String route) async {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
      }

      await visit(Routes.home);
      await visit(Routes.games);
      await visit(Routes.gameSetup('x01'));
      await visit(Routes.gameSetup('checkout'));
      await visit(MatchRoutes.hub);
      await visit(MatchRoutes.opponent);
      await visit(MatchRoutes.tournamentNew);
      await visit(PlanRoutes.list);
      await visit(QuizRoutes.setup);
      await visit(Routes.board);
      await visit(Routes.settings);
      await visit(Routes.stats);
      for (final tab in ['online', 'scoring', 'doubles', 'scatter', 'games', 'records', 'achievements', 'overview']) {
        await tester.ensureVisible(find.byKey(Key('stats-tab-$tab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('stats-tab-$tab')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'stats-$tab');
      }
    });
  }
}
