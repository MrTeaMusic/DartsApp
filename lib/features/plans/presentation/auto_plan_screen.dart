import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../stats/data/stats_repository.dart';
import '../../stats/domain/stats_calculator.dart';
import '../data/plan_repository.dart';
import '../domain/auto_plan.dart';
import '../domain/training_plan.dart';
import 'plan_routes.dart';
import 'plan_run_controller.dart';
import 'plan_texts.dart';

/// Kennzahlen für den automatischen Plan: die letzten 30 Tage, bei zu
/// wenig Daten 90 Tage, dann alles. Dazu der Vergleich Training gegen
/// Online-Match im selben Zeitraum.
final autoPlanInputProvider = Provider<AutoPlanInput?>((ref) {
  final calc = ref.watch(statsCalculatorProvider).value;
  if (calc == null) return null;
  late AutoPlanInput input;
  for (final period in const [StatsPeriod.month, StatsPeriod.quarter, StatsPeriod.all]) {
    input = AutoPlanInput.fromReport(calc.report(period), days: period.days, online: calc.onlineComparison(period));
    if (AutoPlanGenerator.hasEnoughData(input)) break;
  }
  return input;
});

/// „Plan für mich“: Vorschlag aus der Statistik mit Begründung je Schritt.
/// Direkt starten, als eigenen Plan speichern oder neu vorschlagen lassen.
class AutoPlanScreen extends ConsumerStatefulWidget {
  const AutoPlanScreen({super.key});

  @override
  ConsumerState<AutoPlanScreen> createState() => _AutoPlanScreenState();
}

class _AutoPlanScreenState extends ConsumerState<AutoPlanScreen> {
  int _minutes = AutoPlanGenerator.defaultMinutes;
  int _variant = 0;
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

  Future<void> _save(TrainingPlan plan) async {
    if (_busy) return;
    setState(() => _busy = true);
    final id = await ref
        .read(planRepositoryProvider)
        .create(name: plan.name, description: plan.description, steps: plan.steps);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.autoPlanSaved)));
    context.go(PlanRoutes.plan(id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final input = ref.watch(autoPlanInputProvider);
    final auto = input == null ? null : AutoPlanGenerator.generate(input, minutes: _minutes, variant: _variant);
    final open = ref.watch(openPlanRunProvider(AutoPlanGenerator.planId)).value;
    final resumable = open != null && open.currentStep > 0 && !open.allStepsDone;

    return Scaffold(
      appBar: AppPageBar(
        maxWidth: 640,
        title: Text(l10n.autoPlanTitle),
        actions: [
          IconButton(
            key: const Key('auto-plan-regenerate'),
            tooltip: l10n.autoPlanRegenerate,
            onPressed: auto == null ? null : () => setState(() => _variant++),
            icon: const Icon(Icons.autorenew_rounded),
          ),
        ],
      ),
      body: auto == null
          ? const SizedBox.shrink()
          : AppPage(
              maxWidth: 640,
              listKey: const Key('auto-plan-list'),
              children: [
                _Notice(plan: auto),
                const SectionGap(),
                SectionHeader(l10n.autoPlanLength),
                SegmentedButton<int>(
                  segments: [
                    for (final m in AutoPlanGenerator.lengths)
                      ButtonSegment(
                        value: m,
                        label: Text(l10n.autoPlanMinutes(m), key: Key('auto-plan-length-$m')),
                      ),
                  ],
                  selected: {_minutes},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _minutes = s.first),
                ),
                if (_focus(auto).isNotEmpty) ...[
                  const SectionGap(),
                  SectionHeader(l10n.autoPlanFocus),
                  _FocusTiles(weaknesses: _focus(auto)),
                ],
                const SectionGap(),
                SectionHeader('${l10n.planSteps} · ${l10n.autoPlanAbout(auto.minutes.round())}'),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    children: [
                      for (final (i, s) in auto.steps.indexed)
                        PlanStepTile(
                          key: Key('auto-plan-step-$i'),
                          index: i,
                          step: s.step,
                          status: _role(l10n, s.role),
                          trailing: Text(
                            l10n.autoPlanMinutes(s.minutes.round()),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                    ],
                  ),
                ),
                const SectionGap(),
                if (resumable) ...[
                  FilledButton.icon(
                    key: const Key('auto-plan-resume'),
                    onPressed: _busy
                        ? null
                        : () =>
                              _run(TrainingPlan(id: open.planId, name: open.planName, steps: open.steps), resume: true),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(l10n.planResume(open.currentStep + 1, open.steps.length)),
                  ),
                  const SizedBox(height: AppSpacing.m),
                ],
                if (resumable)
                  OutlinedButton.icon(
                    key: const Key('auto-plan-start'),
                    onPressed: _busy ? null : () => _run(auto.plan, resume: false),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(l10n.planRestart),
                  )
                else
                  FilledButton.icon(
                    key: const Key('auto-plan-start'),
                    onPressed: _busy ? null : () => _run(auto.plan, resume: false),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(l10n.planStart),
                  ),
                const SizedBox(height: AppSpacing.m),
                OutlinedButton.icon(
                  key: const Key('auto-plan-save'),
                  onPressed: _busy ? null : () => _save(auto.plan),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(l10n.autoPlanSave),
                ),
              ],
            ),
    );
  }

  /// Schwächen, die im Plan einen Schritt haben.
  static List<Weakness> _focus(AutoPlan plan) => [for (final s in plan.steps) ?s.weakness];

  static String _role(AppLocalizations l10n, AutoStepRole role) => switch (role) {
    AutoStepRole.warmup => l10n.autoPlanRoleWarmup,
    AutoStepRole.focus => l10n.autoPlanRoleFocus,
    AutoStepRole.finish => l10n.autoPlanRoleFinish,
  };
}

class _Notice extends StatelessWidget {
  const _Notice({required this.plan});
  final AutoPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.dartColors;
    return AppCard(
      key: const Key('auto-plan-notice'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(
            icon: plan.enoughData ? Icons.insights_rounded : Icons.info_outline_rounded,
            color: plan.enoughData ? theme.colorScheme.primary : colors.warning,
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.plan.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(plan.notice, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusTiles extends StatelessWidget {
  const _FocusTiles({required this.weaknesses});
  final List<Weakness> weaknesses;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, c) {
        final gap = context.look.gridGap;
        final columns = (c.maxWidth / 150).floor().clamp(1, 4);
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final w in weaknesses)
              SizedBox(
                width: width,
                child: StatTile(label: w.label, value: w.value, caption: l10n.autoPlanGoal(w.goal)),
              ),
          ],
        );
      },
    );
  }
}

/// Eintrag in der Planübersicht: führt zum automatischen Plan.
class AutoPlanCard extends StatelessWidget {
  const AutoPlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    return AppCard(
      key: const Key('auto-plan-card'),
      highlight: true,
      onTap: () => context.go(PlanRoutes.auto),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(context.look.pill ? 16 : context.look.radiusM),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: theme.colorScheme.onPrimary),
          ),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.autoPlanCardTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.autoPlanCardText,
                  style: theme.textTheme.bodySmall?.copyWith(color: context.look.isArena ? Colors.white.withValues(alpha: 0.9) : null),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.look.isArena ? Colors.white : colors.textMuted),
        ],
      ),
    );
  }
}

/// Kleiner Hinweis für andere Bildschirme (Statistik): Link zum Plan.
class AutoPlanHint extends StatelessWidget {
  const AutoPlanHint({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Icon(Icons.auto_awesome_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: AppSpacing.s),
        Expanded(child: Text(l10n.autoPlanHint, style: Theme.of(context).textTheme.bodySmall)),
        TextButton(
          key: const Key('auto-plan-hint'),
          onPressed: () => context.go(PlanRoutes.auto),
          child: Text(l10n.autoPlanHintAction),
        ),
      ],
    );
  }
}
