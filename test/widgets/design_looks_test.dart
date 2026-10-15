import 'package:dartlab/core/design/dart_look.dart';
import 'package:dartlab/core/design/looks.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/board/domain/board_geometry.dart';
import 'package:dartlab/features/challenges/domain/challenge_catalog.dart';
import 'package:dartlab/features/challenges/presentation/challenge_routes.dart';
import 'package:dartlab/features/challenges/presentation/challenge_run_controller.dart';
import 'package:dartlab/features/dart_source/data/simulator_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/games/domain/game_catalog.dart';
import 'package:dartlab/features/games/presentation/active_game_controller.dart';
import 'package:dartlab/features/board/domain/segment.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:dartlab/features/matches/presentation/match_routes.dart';
import 'package:dartlab/features/matches/presentation/tournament_bracket.dart';
import 'package:dartlab/features/matches/presentation/tournament_controller.dart';
import 'package:dartlab/features/plans/presentation/plan_routes.dart';
import 'package:flutter/material.dart';
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
    await tester.ensureVisible(find.byKey(const Key('look-tv')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('look-tv')), findsOneWidget);
    expect(find.byKey(const Key('theme-selector')), findsNothing);
    expect(find.byKey(const Key('theme-fixed')), findsOneWidget);
  });

  testWidgets('Look-Auswahl: Wechsel wirkt sofort und wird gespeichert', (tester) async {
    final container = await pumpApp(tester);
    await tester.tap(find.text('Optionen').first);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('look-clean')));
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
    await tester.ensureVisible(find.text('Dunkel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dunkel'));
    await tester.pumpAndSettle();
    theme = themeOf(tester);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, LookPalettes.cleanDark.primary);

    await tester.scrollUntilVisible(find.byKey(const Key('look-lab')), -200, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
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
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'settings.look': look.name},
        overrides: [
          botTimingProvider.overrideWithValue(const BotTiming(
            firstDart: Duration(milliseconds: 100),
            betweenDarts: Duration(milliseconds: 100),
            takeout: Duration(milliseconds: 100),
          )),
        ],
      );
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
      await visit(PlanRoutes.auto);
      await visit(ChallengeRoutes.list);
      await visit(ChallengeRoutes.detail('c1-1'));
      await visit(ChallengeRoutes.detail('c2-1'));
      await visit(Routes.board);
      await visit(Routes.settings);
      await visit(MatchRoutes.hub);
      await visit(MatchRoutes.opponent);
      await visit(MatchRoutes.tournamentNew);
      await visit(MatchRoutes.cpuPlayers);
      await c.read(tournamentControllerProvider.notifier).create(
            humanName: 'Ich',
            difficulty: 0.5,
            bestOf: const [3, 3, 5, 7],
            seed: 3,
          );
      await visit(MatchRoutes.tournament);
      await visit(Routes.stats);
      for (final tab in ['online', 'scoring', 'doubles', 'games', 'records', 'achievements', 'overview']) {
        await tester.ensureVisible(find.byKey(Key('stats-tab-$tab')));
        await tester.pumpAndSettle();
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

      // Challenge: Aufgabe über dem Spiel, am Ende die Wertung mit Sternen.
      await c.read(challengeRunProvider.notifier).start(ChallengeCatalog.byId('c1-4')!);
      router.go(Routes.play);
      await frames(tester);
      expect(find.byKey(const Key('challenge-task')), findsOneWidget);
      for (var i = 0; i < 30; i++) {
        (c.read(dartSourceProvider) as SimulatorSource).throwAt(BoardGeometry.centerOf(Segment.bull));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await frames(tester, 20);
      expect(find.byKey(const Key('challenge-result')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'challenge');
      c.read(challengeRunProvider.notifier).clear();
      await c.read(activeGameProvider.notifier).close();
      await frames(tester, 3);

      // Match gegen die CPU: Anzeigetafel, Checkout-Weg und Aufnahme.
      await c.read(matchControllerProvider.notifier).start(const MatchSetup(
        format: MatchFormat(startScore: 501, legsToWin: 3),
        players: [MatchPlayer.human('Ich'), MatchPlayer.bot('Robo', average: 60)],
      ));
      router.go(MatchRoutes.play);
      await frames(tester);
      final src = c.read(dartSourceProvider) as SimulatorSource;
      src.throwAt(BoardGeometry.centerOf(Segment.triple(20)));
      src.throwAt(BoardGeometry.centerOf(Segment.fromNumber(19, 3)));
      await frames(tester);
      expect(find.byKey(const Key('match-board')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'match');
      await c.read(matchControllerProvider.notifier).close();
      await frames(tester, 3);
    });
  }

  // Turnierbaum mit Linien in jedem Look, auf dem Telefon und am Desktop.
  for (final look in DartLookId.values) {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      testWidgets('Look ${look.name}: Turnierbaum bei ${size.width.toInt()} px', (tester) async {
        final c = await pumpApp(tester, size: size, prefs: {'settings.look': look.name});
        final ctrl = c.read(tournamentControllerProvider.notifier);
        await ctrl.create(humanName: 'Ich', difficulty: 0.5, bestOf: const [3, 3, 5, 7], seed: 3);
        final t = c.read(tournamentControllerProvider)!;
        final h = t.humanIndex;
        // Achtelfinale und Viertelfinale gespielt, Halbfinale offen.
        for (var r = 0; r < 2; r++) {
          final m = t.humanMatch!;
          t.record(m, winner: h, scoreA: m.a == h ? 2 : 1, scoreB: m.a == h ? 1 : 2);
          await ctrl.simulateRound();
        }
        c.read(routerProvider).go(MatchRoutes.tournament);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.byKey(const Key('tournament-bracket-lines')), findsOneWidget);
        final paint = tester.widget<CustomPaint>(find.byKey(const Key('tournament-bracket-lines')));
        final painter = paint.painter! as BracketConnectorPainter;
        final segments = painter.segments();
        // 4 + 2 + 1 Treffpunkte mit je drei Linien, dazu die Linie zum Sieger.
        expect(segments.length, 7 * 3 + 1);
        expect(segments.where((s) => s.tier == BracketLineTier.human).length, 4);
        expect(segments.where((s) => s.tier == BracketLineTier.open), isNotEmpty);
        expect(find.byKey(const Key('tournament-champion-slot')), findsOneWidget);
        expect(find.byKey(Key('tournament-winner-${t.rounds[1][0].id}')), findsOneWidget);

        // Spiele der zweiten Runde sitzen mittig zwischen ihren Zubringern.
        for (var slot = 0; slot < 4; slot++) {
          final y = tester.getCenter(find.byKey(Key('tournament-match-r1-m$slot'))).dy;
          final a = tester.getCenter(find.byKey(Key('tournament-match-r0-m${slot * 2}'))).dy;
          final b = tester.getCenter(find.byKey(Key('tournament-match-r0-m${slot * 2 + 1}'))).dy;
          expect(y, moreOrLessEquals((a + b) / 2, epsilon: 0.5));
          expect(y, greaterThan(a));
          expect(y, lessThan(b));
        }
        final finalY = tester.getCenter(find.byKey(const Key('tournament-match-r3-m0'))).dy;
        expect(tester.getCenter(find.byKey(const Key('tournament-champion-slot'))).dy, moreOrLessEquals(finalY, epsilon: 0.5));

        // Am Desktop hat „Spielen“ seine eigene Breite statt der ganzen Zeile.
        final play = tester.getSize(find.byKey(const Key('tournament-play')));
        if (size.width > 1000) {
          expect(play.width, lessThan(320));
        }

        // Der Baum lässt sich horizontal scrollen, ohne Fehler.
        await tester.drag(find.byKey(const Key('tournament-bracket-scroll')), const Offset(-600, 0));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('tournament-champion-slot')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
