import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/plan_repository.dart';
import '../domain/training_plan.dart';
import 'plan_detail_screen.dart';
import 'plan_editor_screen.dart';
import 'plan_summary_screen.dart';
import 'plans_screen.dart';

/// Pfade der Trainingspläne (unterhalb von [Routes.games]).
abstract final class PlanRoutes {
  static const list = '${Routes.games}/plaene';
  static const create = '$list/neu';
  static String plan(String id) => '$list/$id';
  static String edit(String id) => '$list/$id/bearbeiten';
  static String run(int runId) => '$list/lauf/$runId';
}

/// Unterrouten für die Spielauswahl. Müssen vor `:gameId` stehen.
final List<RouteBase> planRoutes = [
  GoRoute(
    path: 'plaene',
    builder: (_, _) => const PlansScreen(),
    routes: [
      GoRoute(path: 'neu', builder: (_, _) => const PlanEditorScreen()),
      GoRoute(
        path: 'lauf/:runId',
        builder: (_, state) => PlanSummaryScreen(runId: int.tryParse(state.pathParameters['runId']!) ?? -1),
      ),
      GoRoute(
        path: ':planId',
        builder: (_, state) => PlanDetailScreen(planId: state.pathParameters['planId']!),
        routes: [
          GoRoute(path: 'bearbeiten', builder: (_, state) => PlanEditorScreen(planId: state.pathParameters['planId'])),
        ],
      ),
    ],
  ),
];

final planByIdProvider = StreamProvider.family<TrainingPlan?, String>(
  (ref, id) => ref.watch(planRepositoryProvider).watchById(id),
);

/// Offener Durchlauf eines Plans für das aktive Profil.
final openPlanRunProvider = StreamProvider.family<PlanRun?, String>((ref, planId) {
  final playerId = ref.watch(activePlayerProvider)?.id;
  if (playerId == null) return Stream.value(null);
  return ref.watch(planRepositoryProvider).watchOpenRun(planId, playerId: playerId);
});

final planRunByIdProvider = StreamProvider.family<PlanRun?, int>(
  (ref, id) => ref.watch(planRepositoryProvider).watchRun(id),
);
