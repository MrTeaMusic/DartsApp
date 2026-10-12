import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/presentation/active_game_controller.dart';
import 'plan_routes.dart';
import 'plan_run_controller.dart';

/// Einhängepunkt für den Spielbildschirm: zeigt im Plan-Durchlauf den
/// Fortschritt („Schritt 2 von 5“) und nach Spielende „Nächster Schritt“
/// bzw. „Plan abschließen“. Ohne laufenden Plan nimmt er keinen Platz ein.
class PlanRunPanel extends ConsumerStatefulWidget {
  const PlanRunPanel({super.key});

  @override
  ConsumerState<PlanRunPanel> createState() => _PlanRunPanelState();
}

class _PlanRunPanelState extends ConsumerState<PlanRunPanel> {
  bool _busy = false;

  Future<void> _next() async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = ref.read(planRunProvider.notifier);
    final started = await controller.next();
    if (!started) {
      final runId = await controller.finish();
      if (mounted && runId != null) context.go(PlanRoutes.run(runId));
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(planRunProvider);
    final active = ref.watch(activeGameProvider);
    if (run == null || active == null || run.stepIndex == null || run.sessionId != active.sessionId) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final index = run.stepIndex!;
    final note = run.run.steps[index].note;
    final last = run.isLastStep;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: AppCard(
        key: const Key('plan-run-panel'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Kicker('${l10n.planLabel} · ${run.run.planName}'),
                ),
                Text(l10n.planProgress(index + 1, run.total), key: const Key('plan-progress'), style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            LookProgressBar(value: (index + (active.ended ? 1 : 0)) / run.total),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.s),
              Text(note, style: theme.textTheme.bodySmall),
            ],
            if (active.ended) ...[
              const SizedBox(height: AppSpacing.m),
              FilledButton.icon(
                key: Key(last ? 'plan-finish' : 'plan-next'),
                onPressed: _busy ? null : _next,
                icon: Icon(last ? Icons.flag_rounded : Icons.skip_next_rounded),
                label: Text(last ? l10n.planFinish : l10n.planNextStep),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
