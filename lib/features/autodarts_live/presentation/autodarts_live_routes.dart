import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import 'autodarts_live_screen.dart';

/// Pfad von Autodarts Live (unterhalb von [Routes.games]).
abstract final class AutodartsLiveRoutes {
  static const live = '${Routes.games}/autodarts-live';
}

/// Unterroute für die Spielauswahl. Muss vor `:gameId` stehen.
final List<RouteBase> autodartsLiveRoutes = [
  GoRoute(path: 'autodarts-live', builder: (_, _) => const AutodartsLiveScreen()),
];
