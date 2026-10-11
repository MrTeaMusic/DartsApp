import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../data/plan_repository.dart';
import '../domain/builtin_plans.dart';
import '../domain/training_plan.dart';
import 'plan_routes.dart';

/// Übersicht: feste und eigene Trainingspläne.
class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final custom = ref.watch(customPlansProvider).value ?? const <TrainingPlan>[];
    return Scaffold(
      appBar: AppPageBar(title: Text(l10n.plansTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('plan-new'),
        onPressed: () => context.go(PlanRoutes.create),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.planNew),
      ),
      body: LayoutBuilder(builder: (context, c) {
        final look = context.look;
        final page = look.pagePadding(c.maxWidth >= kWidePage);
        final columns = ((c.maxWidth - 2 * page) / 340).floor().clamp(1, 4);
        Widget grid(List<TrainingPlan> plans) => GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: look.gridGap,
              crossAxisSpacing: look.gridGap,
              childAspectRatio: ((c.maxWidth - 2 * page - (columns - 1) * look.gridGap) / columns) / 132,
              children: [for (final p in plans) PlanCard(plan: p)],
            );
        return ListView(
          padding: EdgeInsets.fromLTRB(page, AppSpacing.s, page, 96),
          children: [
            SectionHeader(l10n.plansBuiltin),
            grid(BuiltinPlans.all),
            const SectionGap(),
            SectionHeader(l10n.plansCustom),
            if (custom.isEmpty)
              AppCard(child: Text(l10n.plansCustomEmpty, style: Theme.of(context).textTheme.bodySmall))
            else
              grid(custom),
          ],
        );
      }),
    );
  }
}

class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.plan});
  final TrainingPlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final missing = plan.steps.length - plan.availableSteps;
    return AppCard(
      key: Key('plan-${plan.id}'),
      onTap: () => context.go(PlanRoutes.plan(plan.id)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: plan.builtIn ? Icons.event_note_rounded : Icons.edit_note_rounded),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  missing > 0 ? l10n.planSomeUnavailable(missing) : l10n.planStepCount(plan.steps.length),
                  style: theme.textTheme.labelMedium?.copyWith(color: missing > 0 ? colors.warning : null),
                ),
                if (plan.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(plan.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.textMuted),
        ],
      ),
    );
  }
}
