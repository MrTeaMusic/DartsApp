import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/autodarts_live/presentation/autodarts_live_routes.dart';
import '../../features/challenges/presentation/challenge_routes.dart';
import '../../features/dart_source/presentation/debug_screen.dart';
import '../../features/games/presentation/game_play_screen.dart';
import '../../features/games/presentation/game_setup_screen.dart';
import '../../features/games/presentation/games_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/history/presentation/session_detail_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/lite/domain/lite_gate.dart';
import '../../features/live_remote/presentation/live_tab.dart';
import '../../features/lite/presentation/lite_settings_screen.dart';
import '../../features/lite/presentation/lite_setup_screen.dart';
import '../../features/matches/presentation/match_routes.dart';
import '../../features/plans/presentation/plan_routes.dart';
import '../../features/quiz/presentation/quiz_routes.dart';
import '../../features/second_screen/presentation/second_screen_page.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/simulator/presentation/board_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';
import '../../features/dart_source/domain/dart_event.dart';
import '../lite.dart';
import '../settings/app_settings.dart';
import '../widgets/adaptive_scaffold.dart';

abstract final class Routes {
  static const home = '/';
  static const games = '/training';
  static const board = '/board';
  static const stats = '/statistik';
  static const history = '/statistik/verlauf';
  static String session(int id) => '$history/$id';
  static const settings = '/einstellungen';

  /// Live-Reiter der Lite-App (Zuschauen). Die volle App hat ihn nicht.
  static const watch = '/zuschauen';
  static const debug = '/einstellungen/debug';
  static const play = '/spiel';
  static String gameSetup(String gameId) => '$games/$gameId';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Optionen › Autodarts: beim Start direkt in Autodarts Live.
  final settings = ref.read(settingsProvider);
  final liveOnStart = settings.autodartsLiveAutoStart && settings.sourceKind == DartSourceKind.autodartsLocal;
  // Lite: nur Statistik und Optionen, davor die Einrichtung. Die vollständige
  // Routentabelle bleibt; alles andere führt per Weiterleitung zur Statistik.
  final lite = ref.read(liteProvider);
  final connected = ValueNotifier(liteIsConnected(settings));
  if (lite) ref.listen(settingsProvider, (_, next) => connected.value = liteIsConnected(next));
  final router = GoRouter(
    initialLocation: lite ? Routes.stats : (liveOnStart ? AutodartsLiveRoutes.live : Routes.home),
    refreshListenable: lite ? connected : null,
    redirect: lite
        ? (_, state) => liteRedirect(state.uri.path, connected: connected.value)
        // Der Live-Reiter gehört nur zu Lite: In der vollen App führt der Pfad nach Hause.
        : (_, state) => state.uri.path == Routes.watch ? Routes.home : null,
    routes: [
      if (lite) GoRoute(path: LiteRoutes.welcome, builder: (_, _) => const LiteSetupScreen()),
      // Spielansicht ohne Navigation, damit das Board möglichst groß ist.
      GoRoute(path: Routes.play, builder: (_, _) => const GamePlayScreen()),
      matchPlayRoute,
      quizPlayRoute,
      // Zweiter Bildschirm: Spielstand vom PC, ebenfalls ohne Navigation.
      secondScreenGoRoute,
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AdaptiveScaffold(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.games,
              builder: (_, _) => const GamesScreen(),
              routes: [
                // Trainingspläne vor :gameId, damit "plaene" kein Spiel ist.
                ...planRoutes,
                ...matchRoutes,
                ...challengeRoutes,
                ...autodartsLiveRoutes,
                ...quizRoutes,
                GoRoute(
                  path: ':gameId',
                  builder: (_, state) => GameSetupScreen(gameId: state.pathParameters['gameId']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.board, builder: (_, _) => const BoardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.stats,
              builder: (_, _) => const StatsScreen(),
              routes: [
                GoRoute(
                  path: 'verlauf',
                  builder: (_, _) => const HistoryScreen(),
                  routes: [
                    GoRoute(
                      path: ':sessionId',
                      builder: (_, state) =>
                          SessionDetailScreen(sessionId: int.tryParse(state.pathParameters['sessionId']!) ?? -1),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.settings,
              builder: (_, _) => lite ? const LiteSettingsScreen() : const SettingsScreen(),
              routes: [
                GoRoute(path: 'debug', builder: (_, _) => const DebugScreen()),
              ],
            ),
          ]),
          // Nur Lite zeigt diesen Zweig (Live-Reiter, Zweig 5).
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.watch, builder: (_, _) => const LiveTab()),
          ]),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(body: Center(child: Text('${state.error}'))),
  );
  ref.onDispose(() {
    router.dispose();
    connected.dispose();
  });
  return router;
});
