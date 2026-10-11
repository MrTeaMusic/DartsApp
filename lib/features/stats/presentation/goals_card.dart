import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/domain/engine/game_display.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/stats_repository.dart';
import '../domain/goals.dart';

extension GoalTexts on AppLocalizations {
  String goalLabel(GoalKind k) => switch (k) {
        GoalKind.weeklySessions => goalWeeklySessions,
        GoalKind.weeklyDarts => goalWeeklyDarts,
        GoalKind.streakDays => goalStreakDays,
        GoalKind.scoringAverage => goalScoringAverage,
        GoalKind.checkoutRate => goalCheckoutRate,
        GoalKind.doubleRate => goalDoubleRate,
      };
}

String _value(GoalKind k, double? v) {
  if (v == null) return '–';
  if (k.isPercent) return '${formatDecimal(v)} %';
  if (k == GoalKind.scoringAverage) return formatDecimal(v);
  return v.round().toString();
}

/// Ziele mit Fortschritt; Antippen zum Ändern, Plus zum Hinzufügen.
class GoalsCard extends ConsumerWidget {
  const GoalsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final progress = ref.watch(goalProgressProvider);
    final used = {for (final p in progress) p.kind};
    final free = [for (final k in GoalKind.values) if (!used.contains(k)) k];

    return AppCard(
      key: const Key('goals-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            l10n.goalsTitle,
            trailing: free.isEmpty
                ? null
                : IconButton(
                    key: const Key('goal-add'),
                    tooltip: l10n.goalsAdd,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_rounded),
                    onPressed: () => _edit(context, ref, kinds: free),
                  ),
          ),
          if (progress.isEmpty) Text(l10n.goalsEmpty, style: theme.textTheme.bodySmall),
          for (final p in progress)
            InkWell(
              key: Key('goal-${p.kind.name}'),
              borderRadius: BorderRadius.circular(AppRadii.s),
              onTap: () => _edit(context, ref, existing: p),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (p.reached) ...[
                          Icon(Icons.check_circle_rounded, size: 18, color: colors.success),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Expanded(child: Text(l10n.goalLabel(p.kind), style: theme.textTheme.titleSmall)),
                        Text('${_value(p.kind, p.current)} / ${_value(p.kind, p.target)}', style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      child: LinearProgressIndicator(
                        value: p.ratio,
                        minHeight: 6,
                        backgroundColor: colors.surfaceHigh,
                        color: p.reached ? colors.success : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, {List<GoalKind>? kinds, GoalProgress? existing}) async {
    final playerId = ref.read(activePlayerProvider)?.id;
    if (playerId == null) return;
    final result = await showDialog<_GoalEdit>(
      context: context,
      builder: (_) => _GoalDialog(kinds: kinds ?? [existing!.kind], existing: existing),
    );
    if (result == null) return;
    final repo = ref.read(statsRepositoryProvider);
    if (existing != null) {
      result.delete ? await repo.deleteGoal(existing.goal.id) : await repo.updateGoal(existing.goal.id, result.target);
    } else {
      await repo.addGoal(playerId, result.kind, result.target);
    }
  }
}

class _GoalEdit {
  const _GoalEdit(this.kind, this.target, {this.delete = false});
  final GoalKind kind;
  final double target;
  final bool delete;
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({required this.kinds, this.existing});
  final List<GoalKind> kinds;
  final GoalProgress? existing;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late GoalKind _kind = widget.kinds.first;
  late double _target = widget.existing?.target ?? _kind.defaultTarget;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final divisions = ((_kind.max - _kind.min) / _kind.step).round();
    return AlertDialog(
      title: Text(widget.existing == null ? l10n.goalsAdd : l10n.goalLabel(_kind)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.existing == null)
              DropdownButton<GoalKind>(
                key: const Key('goal-kind'),
                isExpanded: true,
                value: _kind,
                items: [
                  for (final k in widget.kinds) DropdownMenuItem(value: k, child: Text(l10n.goalLabel(k))),
                ],
                onChanged: (k) => setState(() {
                  _kind = k ?? _kind;
                  _target = _kind.defaultTarget;
                }),
              ),
            const SizedBox(height: AppSpacing.l),
            Text('${l10n.goalTarget}: ${_value(_kind, _target)}', style: theme.textTheme.titleMedium),
            Slider(
              key: const Key('goal-slider'),
              value: _target.clamp(_kind.min, _kind.max),
              min: _kind.min,
              max: _kind.max,
              divisions: divisions,
              onChanged: (v) => setState(() => _target = v),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            key: const Key('goal-delete'),
            onPressed: () => Navigator.pop(context, _GoalEdit(_kind, _target, delete: true)),
            child: Text(l10n.goalsDelete),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.gameCancelShort)),
        FilledButton(
          key: const Key('goal-save'),
          onPressed: () => Navigator.pop(context, _GoalEdit(_kind, _target)),
          child: Text(l10n.goalsSave),
        ),
      ],
    );
  }
}
