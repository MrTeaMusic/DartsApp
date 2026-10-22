import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/router/app_router.dart';
import 'package:dartlab/features/autodarts_live/presentation/autodarts_live_routes.dart';
import 'package:dartlab/features/challenges/presentation/challenge_routes.dart';
import 'package:dartlab/features/matches/presentation/match_routes.dart';
import 'package:dartlab/features/plans/presentation/plan_routes.dart';
import 'package:dartlab/features/quiz/presentation/quiz_routes.dart';
import 'package:dartlab/features/second_screen/presentation/second_screen_page.dart';
import 'package:dartlab/features/stats/domain/goals.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cloud.dart';
import '../helpers/lite_app.dart';
import '../helpers/pump_app.dart';

/// Jeder Pfad der App, den es mit Parametern gibt, einmal.
final allRoutes = <String>[
  Routes.home,
  Routes.games,
  Routes.board,
  Routes.stats,
  Routes.history,
  Routes.session(1),
  Routes.session(999999),
  Routes.settings,
  Routes.debug,
  Routes.play,
  Routes.gameSetup('x01'),
  Routes.gameSetup('gibt-es-nicht'),
  MatchRoutes.hub,
  MatchRoutes.opponent,
  MatchRoutes.tournament,
  MatchRoutes.tournamentNew,
  MatchRoutes.cpuPlayers,
  MatchRoutes.play,
  QuizRoutes.setup,
  QuizRoutes.play,
  ChallengeRoutes.list,
  ChallengeRoutes.detail('x'),
  PlanRoutes.list,
  PlanRoutes.create,
  PlanRoutes.auto,
  PlanRoutes.plan('x'),
  PlanRoutes.edit('x'),
  PlanRoutes.run(1),
  AutodartsLiveRoutes.live,
  secondScreenRoute,
  '/willkommen',
  '/gibt-es-nicht',
  '/statistik/gibt-es-nicht/auch-nicht',
];

Finder get errorPage => find.textContaining(RegExp(r'Exception|no routes|Page Not Found', caseSensitive: false));

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('Navigation', () {
    testWidgets('Handy: genau zwei Ziele, Statistik und Optionen', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations, hasLength(2));
      expect(
        find.descendant(of: find.byType(NavigationBar), matching: find.byType(NavigationDestination)),
        findsNWidgets(2),
      );
      for (final label in ['Statistik', 'Optionen']) {
        expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)), findsOneWidget);
      }
      for (final label in ['Start', 'Training', 'Board']) {
        expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)), findsNothing);
      }
      expect(bar.selectedIndex, 0);

      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Optionen')));
      await tester.pumpAndSettle();
      expect(currentPath(c), '/einstellungen');
      expect(find.byKey(const Key('lite-settings')), findsOneWidget);
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);

      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Statistik')));
      await tester.pumpAndSettle();
      expect(currentPath(c), '/statistik');
      expect(find.byKey(const Key('stats-tabs')), findsOneWidget);
      await shutdownApp(tester, c);
    });

    testWidgets('breit (Tablet): Seitenleiste mit zwei Zielen', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester, size: const Size(1280, 900));
      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.destinations, hasLength(2));
      expect(rail.selectedIndex, 0);
      await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Optionen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lite-settings')), findsOneWidget);
      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 1);
      await shutdownApp(tester, c);
    });

    testWidgets('die volle App behält ihre fünf Ziele', (tester) async {
      await pumpApp(tester, size: const Size(360, 800));
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations, hasLength(5));
    });
  });

  group('Gesperrte Pfade', () {
    testWidgets('eingerichtet: jeder Pfad endet auf Statistik oder Optionen, nie auf der Fehlerseite', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      final router = c.read(routerProvider);
      for (final path in allRoutes) {
        router.go(path);
        await tester.pumpAndSettle();
        final now = currentPath(c);
        final allowed = now == '/einstellungen' || now == '/statistik' || now.startsWith('/statistik/');
        expect(allowed, isTrue, reason: '$path → $now');
        expect(errorPage, findsNothing, reason: path);
        expect(find.byType(NavigationBar), findsOneWidget, reason: path);
        if (path == Routes.settings) {
          expect(find.byKey(const Key('lite-settings')), findsOneWidget);
        } else if (path == Routes.history) {
          expect(find.byKey(const Key('history-list')), findsOneWidget);
        } else if (path.startsWith('${Routes.history}/')) {
          // Eine Session, die es nicht gibt, bekommt ihre eigene Meldung.
          if (path == Routes.session(999999)) expect(find.text('Diese Session gibt es nicht mehr.'), findsOneWidget);
        } else {
          // Alles andere, auch alles Gesperrte, zeigt die Statistik.
          expect(now, '/statistik', reason: '$path wird zur Statistik umgeleitet');
          expect(find.byKey(const Key('stats-tabs')), findsOneWidget, reason: path);
        }
      }
      await shutdownApp(tester, c);
    });

    testWidgets('nicht eingerichtet: jeder Pfad endet in der Einrichtung', (tester) async {
      final c = await pumpLite(tester, cloud: FakeCloud());
      final router = c.read(routerProvider);
      for (final path in allRoutes) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(currentPath(c), '/willkommen', reason: path);
        expect(find.byKey(const Key('lite-setup')), findsOneWidget, reason: path);
        expect(errorPage, findsNothing, reason: path);
        expect(find.byType(NavigationBar), findsNothing, reason: path);
      }
    });

    testWidgets('Zurück-Taste führt nie aus der Statistik in einen gesperrten Bereich', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      c.read(routerProvider).go(Routes.games);
      await tester.pumpAndSettle();
      expect(currentPath(c), '/statistik');
      expect(c.read(routerProvider).canPop(), isFalse);
      await shutdownApp(tester, c);
    });
  });

  group('Nur lesen', () {
    Future<List<SessionRow>> sessions(WidgetTester tester, ProviderContainer c) async {
      final db = c.read(appDatabaseProvider);
      return (await tester.runAsync(() => db.select(db.sessions).get()))!;
    }

    testWidgets('Verlauf und Details: nichts löschen, nichts noch einmal spielen', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      final rows = await sessions(tester, c);
      expect(rows.length, greaterThanOrEqualTo(6));

      await tester.tap(find.byKey(const Key('stats-history')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-list')), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
      expect(find.byKey(Key('history-${rows.first.id}')), findsOneWidget);

      for (final row in rows) {
        c.read(routerProvider).go(Routes.session(row.id));
        await tester.pumpAndSettle();
        expect(currentPath(c), Routes.session(row.id));
        expect(find.byKey(const Key('session-detail')), findsOneWidget, reason: row.gameId);
        expect(find.byKey(const Key('session-delete-action')), findsNothing);
        expect(find.byKey(const Key('session-delete')), findsNothing);
        expect(find.byKey(const Key('session-play-again')), findsNothing);
        expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
        expect(find.byIcon(Icons.replay_rounded), findsNothing);
        expect(find.text('Nochmal spielen'), findsNothing);
        expect(find.text('Löschen'), findsNothing);
        // Ganz nach unten: auch dort kein Knopf.
        await tester.drag(find.byKey(const Key('session-detail')), const Offset(0, -5000));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('session-play-again')), findsNothing);
        expect(find.byKey(const Key('session-delete')), findsNothing);
      }
      // Es ist noch alles da.
      expect(await sessions(tester, c), hasLength(rows.length));
      await shutdownApp(tester, c);
    });

    testWidgets('Statistik: keine Ziele anlegen, keine Wege zu Spielen und Plänen', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      const forbidden = [
        Key('goal-add'),
        Key('online-open-live'),
        Key('online-auto-plan'),
        Key('session-play-again'),
      ];
      // Ohne Ziele gibt es keine Zielekarte; Bens Serie bleibt.
      expect(find.byKey(const Key('goals-card')), findsNothing);
      expect(find.byKey(const Key('streak-card')), findsOneWidget);
      for (final key in ['overview', 'online', 'scoring', 'doubles', 'scatter', 'tempo', 'games', 'records', 'achievements']) {
        final tab = find.byKey(Key('stats-tab-$key'));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        for (final k in forbidden) {
          expect(find.byKey(k), findsNothing, reason: '$key: $k');
        }
        expect(errorPage, findsNothing, reason: key);
      }
      // Auch die leeren Reiter fordern nicht zum Spielen auf.
      expect(find.textContaining('Trainier'), findsNothing);
      await shutdownApp(tester, c);
    });

    testWidgets('Ziele von Ben werden gezeigt, lassen sich aber nicht ändern', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester, prepare: (ben) async {
        await ben.device.stats.addGoal(await ben.device.me(), GoalKind.weeklySessions, 5);
      });
      expect(find.byKey(const Key('goals-card')), findsOneWidget);
      expect(find.byKey(const Key('goal-weeklySessions')), findsOneWidget);
      expect(find.byKey(const Key('goal-add')), findsNothing);
      await tester.tap(find.byKey(const Key('goal-weeklySessions')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await shutdownApp(tester, c);
    });

    testWidgets('Optionen: weder Löschen noch Profile verwalten noch Spieloptionen', (tester) async {
      final (:c, :cloud, :ben) = await pumpLiteWithBen(tester);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Optionen')));
      await tester.pumpAndSettle();
      for (final key in ['profile-add', 'open-debug', 'sync-role-off', 'sync-role-hub', 'sync-role-client', 'source-simulator', 'theme-selector']) {
        expect(find.byKey(Key(key), skipOffstage: false), findsNothing, reason: key);
      }
      for (final text in ['Backup', 'Sicherung', 'Autodarts', 'Sound', 'Ansage', 'Profile']) {
        expect(find.textContaining(text, skipOffstage: false), findsNothing, reason: text);
      }
      await shutdownApp(tester, c);
    });
  });
}
