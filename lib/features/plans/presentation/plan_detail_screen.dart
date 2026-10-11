import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../data/plan_repository.dart';
import '../domain/training_plan.dart';
import 'plan_routes.dart';
import 'plan_run_controller.dart';
import 'plan_texts.dart';

/// Ein Plan mit seinen Schritten: starten, fortsetzen, bearbeiten,
/// kopieren, löschen.
class PlanDetailScreen extends ConsumerStatefulWidget {
  const PlanDetailScreen({super.key, required this.planId});
  final String planId;

  @override
  ConsumerState<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends ConsumerState<PlanDetailScreen> {
  bool _busy = false;

  Future<void> _run(TrainingPlan plan, {required bool resume}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = ref.read(planRunProvider.notifier);
    final started = await controller.start(plan, resume: resume);
    if (!mounted) return;
    setState(() => _busy = false);
    if (started) {
      context.go(Routes.play);
    } else {
      final runId = await controller.finish();
      if (mounted && runId != null) context.go(PlanRoutes.run(runId));
    }
  }

  Future<void> _duplicate(TrainingPlan plan) async {
    final id = await ref.read(planRepositoryProvider).duplicate(plan, name: context.l10n.planCopyName(plan.name));
    if (mounted) context.go(PlanRoutes.edit(id));
  }

  Future<void> _delete(TrainingPlan plan) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.planDeleteTitle),
        content: Text(l10n.planDeleteText(plan.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.gameCancelShort)),
          FilledButton(key: const Key('plan-delete-confirm'), onPressed: () => Navigator.pop(context, true), child: Text(l10n.planDelete)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(planRepositoryProvider).delete(plan.id);
    if (mounted) context.go(PlanRoutes.list);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final async = ref.watch(planByIdProvider(widget.planId));
    final plan = async.value;
    if (plan == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading ? const SizedBox.shrink() : Center(child: Text(l10n.planNotFound)),
      );
    }
    final open = ref.watch(openPlanRunProvider(plan.id)).value;
    final resumable = open != null && open.currentStep > 0 && !open.allStepsDone;

    return Scaffold(
      appBar: AppBar(
        title: Text(plan.name),
        actions: [
          if (!plan.builtIn)
            IconButton(
              key: const Key('plan-edit'),
              tooltip: l10n.planEdit,
              onPressed: () => context.go(PlanRoutes.edit(plan.id)),
              icon: const Icon(Icons.edit_rounded),
            ),
          PopupMenuButton<String>(
            key: const Key('plan-menu'),
            onSelected: (v) => switch (v) {
              'duplicate' => _duplicate(plan),
              'delete' => _delete(plan),
              _ => null,
            },
            itemBuilder: (_) => [
              PopupMenuItem(key: const Key('plan-duplicate'), value: 'duplicate', child: Text(l10n.planDuplicate)),
              if (!plan.builtIn) PopupMenuItem(key: const Key('plan-delete'), value: 'delete', child: Text(l10n.planDelete)),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              if (plan.description.isNotEmpty) ...[
                Text(plan.description, style: theme.textTheme.bodyLarge),
                const SizedBox(height: AppSpacing.xl),
              ],
              SectionHeader('${l10n.planSteps} · ${l10n.planStepCount(plan.steps.length)}'),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  children: [
                    for (final (i, s) in plan.steps.indexed)
                      PlanStepTile(
                        index: i,
                        step: s,
                        status: resumable && i < open.currentStep ? l10n.stepStatus(open.resultOf(i)?.status) : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (resumable) ...[
                FilledButton.icon(
                  key: const Key('plan-resume'),
                  onPressed: _busy ? null : () => _run(plan, resume: true),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(l10n.planResume(open.currentStep + 1, open.steps.length)),
                ),
                const SizedBox(height: AppSpacing.m),
                OutlinedButton.icon(
                  key: const Key('plan-restart'),
                  onPressed: _busy ? null : () => _run(plan, resume: false),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(l10n.planRestart),
                ),
              ] else
                FilledButton.icon(
                  key: const Key('plan-start'),
                  onPressed: _busy || !plan.playable ? null : () => _run(plan, resume: false),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(l10n.planStart),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
