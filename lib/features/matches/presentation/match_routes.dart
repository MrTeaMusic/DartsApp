import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import 'cpu_players_screen.dart';
import 'match_play_screen.dart';
import 'match_setup_screen.dart';
import 'matches_screen.dart';
import 'tournament_screen.dart';
import 'tournament_setup_screen.dart';

/// Pfade des Match-Bereichs.
abstract final class MatchRoutes {
  static const hub = '${Routes.games}/match';
  static const opponent = '$hub/gegner';
  static const tournament = '$hub/turnier';
  static const tournamentNew = '$hub/turnier/neu';
  static const cpuPlayers = '$hub/cpu';

  /// Spielansicht ohne Navigation.
  static const play = '/match';
}

/// Unterrouten der Spielauswahl. Müssen vor `:gameId` stehen.
final List<RouteBase> matchRoutes = [
  GoRoute(
    path: 'match',
    builder: (_, _) => const MatchesScreen(),
    routes: [
      GoRoute(path: 'gegner', builder: (_, _) => const MatchSetupScreen()),
      GoRoute(
        path: 'turnier',
        builder: (_, _) => const TournamentScreen(),
        routes: [GoRoute(path: 'neu', builder: (_, _) => const TournamentSetupScreen())],
      ),
      GoRoute(path: 'cpu', builder: (_, _) => const CpuPlayersScreen()),
    ],
  ),
];

/// Vollbild-Route der Spielansicht (oberste Ebene).
final GoRoute matchPlayRoute = GoRoute(path: MatchRoutes.play, builder: (_, _) => const MatchPlayScreen());
