import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dart_source/presentation/debug_screen.dart';
import '../../features/games/presentation/game_play_screen.dart';
import '../../features/games/presentation/game_setup_screen.dart';
import '../../features/games/presentation/games_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/simulator/presentation/board_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';
import '../widgets/adaptive_scaffold.dart';

abstract final class Routes {
  static const home = '/';
  static const games = '/training';
  static const board = '/board';
  static const stats = '/statistik';
  static const settings = '/einstellungen';
  static const debug = '/einstellungen/debug';
  static const play = '/spiel';
  static String gameSetup(String gameId) => '$games/$gameId';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: Routes.home,
    routes: [
      // Spielansicht ohne Navigation, damit das Board möglichst groß ist.
      GoRoute(path: Routes.play, builder: (_, _) => const GamePlayScreen()),
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
            GoRoute(path: Routes.stats, builder: (_, _) => const StatsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.settings,
              builder: (_, _) => const SettingsScreen(),
              routes: [
                GoRoute(path: 'debug', builder: (_, _) => const DebugScreen()),
              ],
            ),
          ]),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(body: Center(child: Text('${state.error}'))),
  );
  ref.onDispose(router.dispose);
  return router;
});
