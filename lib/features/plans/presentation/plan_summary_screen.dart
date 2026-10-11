import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/presentation/game_texts.dart';
import '../domain/training_plan.dart';
import 'plan_routes.dart';
import 'plan_texts.dart';

/// Zusammenfassung eines Plan-Durchlaufs: Status und Ergebnis jedes Schritts.
class PlanSummaryScreen extends ConsumerWidget {
  const PlanSummaryScreen({super.key, required this.runId});
  final int runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final async = ref.watch(planRunByIdProvider(runId));
    final run = async.value;
    if (run == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading ? const SizedBox.shrink() : Center(child: Text(l10n.planNotFound)),
      );
    }
    final played = run.results.where((r) => r.status == StepStatus.done).length;
    final darts = run.results.fold<int>(0, (sum, r) => sum + r.darts);
    return Scaffold(
      appBar: AppPageBar(maxWidth: 640, title: Text(l10n.planSummaryTitle)),
      body: AppPage(
        maxWidth: 640,
        children: [
              Text(run.planName, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${l10n.planSummaryPlayed(played, run.steps.length)} · $darts ${l10n.statDarts}',
                key: const Key('plan-summary-played'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              for (final (i, step) in run.steps.indexed) ...[
                _StepResultCard(index: i, step: step, result: run.resultOf(i)),
                const SizedBox(height: AppSpacing.m),
              ],
              const SizedBox(height: AppSpacing.m),
              FilledButton.icon(
                key: const Key('plan-summary-done'),
                onPressed: () => context.go(PlanRoutes.list),
                icon: const Icon(Icons.check_rounded),
                label: Text(l10n.planBackToPlans),
              ),
            ],
      ),
    );
  }
}

class _StepResultCard extends StatelessWidget {
  const _StepResultCard({required this.index, required this.step, required this.result});
  final int index;
  final PlanStep step;
  final StepResult? result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final status = result?.status;
    final color = switch (status) {
      StepStatus.done => colors.success,
      StepStatus.aborted || StepStatus.unavailable => colors.warning,
      null => colors.textMuted,
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${index + 1}.', style: theme.textTheme.titleMedium),
              const SizedBox(width: AppSpacing.s),
              Expanded(child: Text(l10n.stepTitle(step), style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
              StatusPill(label: l10n.stepStatus(status), color: color),
            ],
          ),
          if (result != null && result!.summary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.m),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.s,
              children: [
                for (final (key, value) in result!.summary)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.statLabel(key), style: theme.textTheme.labelMedium),
                      Text(value, style: theme.textTheme.titleLarge),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
