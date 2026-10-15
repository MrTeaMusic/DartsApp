import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import 'quiz_play_screen.dart';
import 'quiz_setup_screen.dart';

/// Pfade des Checkout-Quiz.
abstract final class QuizRoutes {
  /// Einstellungen und Bestwerte (unterhalb von [Routes.games]).
  static const setup = '${Routes.games}/checkout-quiz';

  /// Quiz ohne Navigation, damit Frage und Tastenfeld Platz haben.
  static const play = '/quiz';
}

/// Unterroute der Spielauswahl. Muss vor `:gameId` stehen.
final List<RouteBase> quizRoutes = [
  GoRoute(path: 'checkout-quiz', builder: (_, _) => const QuizSetupScreen()),
];

/// Vollbild-Route des Quiz (oberste Ebene).
final GoRoute quizPlayRoute = GoRoute(path: QuizRoutes.play, builder: (_, _) => const QuizPlayScreen());
