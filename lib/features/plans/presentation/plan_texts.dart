import 'package:flutter/material.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/domain/engine/game_definition.dart';
import '../../games/presentation/game_texts.dart';
import '../domain/training_plan.dart';

extension PlanTexts on AppLocalizations {
  /// Einstellungen eines Schritts, die von den Standardwerten des Spiels
  /// abweichen, z. B. „Ring: Double · Bull: aus“.
  String stepSettings(PlanStep step) {
    final def = step.definition;
    if (def == null) return planStepUnavailable;
    final config = def.resolve(step.config);
    final defaults = def.resolve(const {});
    final parts = <String>[];
    for (final o in def.options) {
      final v = config[o.key];
      if ('$v' == '${defaults[o.key]}') continue;
      final value = switch (o) {
        BoolOption() => v == true ? optOn : optOff,
        ChoiceOption() => optionValue('$v'),
        IntOption() || IntChoiceOption() => '$v',
      };
      parts.add('${optionLabel(o.key)}: $value');
    }
    return parts.isEmpty ? planStepDefaults : parts.join(' · ');
  }

  String stepTitle(PlanStep step) => step.available ? gameTitle(step.gameId) : '$planStepUnavailable: ${step.gameId}';

  String stepStatus(StepStatus? status) => switch (status) {
        StepStatus.done => planStatusDone,
        StepStatus.aborted => planStatusAborted,
        StepStatus.unavailable => planStatusUnavailable,
        null => planStatusOpen,
      };
}

/// Zeile eines Schritts in Plan-Ansicht und Editor.
class PlanStepTile extends StatelessWidget {
  const PlanStepTile({super.key, required this.index, required this.step, this.trailing, this.onTap, this.status});

  final int index;
  final PlanStep step;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Status des Schritts im Durchlauf oder seine Rolle im automatischen
  /// Plan („Aufwärmen“).
  final String? status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final available = step.available;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: (available ? theme.colorScheme.primary : colors.warning).withValues(alpha: 0.14),
        child: available
            ? Text('${index + 1}', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary))
            : Icon(Icons.warning_amber_rounded, size: 18, color: colors.warning),
      ),
      title: Row(
        children: [
          if (available) ...[
            Icon(gameIcon(step.gameId), size: 18, color: colors.textMuted),
            const SizedBox(width: AppSpacing.s),
          ],
          Expanded(child: Text(l10n.stepTitle(step), overflow: TextOverflow.ellipsis)),
          if (status != null) ...[
            const SizedBox(width: AppSpacing.s),
            Flexible(
              child: Text(status!, style: theme.textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          available ? l10n.stepSettings(step) : l10n.planStepUnavailableText(step.gameId),
          if (step.note != null) step.note!,
        ].join('\n'),
      ),
      isThreeLine: step.note != null || !available,
      trailing: trailing,
    );
  }
}
