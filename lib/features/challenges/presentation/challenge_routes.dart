import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import 'challenge_detail_screen.dart';
import 'challenges_screen.dart';

/// Pfade des Challenge-Modus (unterhalb von [Routes.games]).
abstract final class ChallengeRoutes {
  static const list = '${Routes.games}/challenges';
  static String detail(String id) => '$list/$id';
}

/// Unterrouten für die Spielauswahl. Müssen vor `:gameId` stehen.
final List<RouteBase> challengeRoutes = [
  GoRoute(
    path: 'challenges',
    builder: (_, _) => const ChallengesScreen(),
    routes: [
      GoRoute(path: ':challengeId', builder: (_, state) => ChallengeDetailScreen(challengeId: state.pathParameters['challengeId']!)),
    ],
  ),
];
