import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../../games/domain/engine/game_display.dart';
import '../data/recording_analysis.dart';
import '../domain/coordinate_calibration.dart';

/// Zeigt die Auswertung eines Autodarts-Mitschnitts.
Future<void> showRecordingAnalysis(BuildContext context, String jsonLines) {
  final analysis = RecordingAnalysis.analyze(jsonLines);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: RecordingAnalysisView(analysis: analysis)),
  );
}

class RecordingAnalysisView extends ConsumerWidget {
  const RecordingAnalysisView({super.key, required this.analysis});
  final RecordingAnalysis analysis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final a = analysis;
    final current = ref.watch(settingsProvider.select((s) => s.coordCalibration));
    final agreement = a.agreement(current);
    final suggestion = a.suggestCalibration();
    final suggestionAgreement = suggestion == null ? null : a.agreement(suggestion);
    final better = suggestion != null && suggestion != current && (suggestionAgreement ?? 0) > (agreement ?? 0) + 0.05;

    Widget line(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(value, style: theme.textTheme.titleSmall?.copyWith(color: color)),
          ]),
        );

    return ListView(
      key: const Key('recording-analysis'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.page),
      children: [
        Text(l10n.recTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.m),
        AppCard(
          child: Column(children: [
            line(l10n.recLines, '${a.lines}'),
            line(l10n.recStates, '${a.states}'),
            line(l10n.recDarts, '${a.darts.length}'),
            line(l10n.recTakeouts, '${a.takeouts}'),
            line(l10n.recCorrections, '${a.corrections}'),
            if (a.messageTypes.isNotEmpty)
              line(l10n.recTypes, [for (final e in a.messageTypes.entries) '${e.key} ×${e.value}'].join(', ')),
            line(
              l10n.recThrowsField,
              a.sawThrowsField ? l10n.recYes : l10n.recNo,
              color: a.sawThrowsField ? colors.success : colors.danger,
            ),
            line(
              l10n.recAgreement,
              formatPercent(agreement),
              color: agreement == null ? null : (agreement >= 0.9 ? colors.success : colors.warning),
            ),
            if (a.warnings.isNotEmpty) line(l10n.recWarnings, '${a.warnings.length}', color: colors.warning),
          ]),
        ),
        if (!a.sawThrowsField && a.states > 0) ...[
          const SizedBox(height: AppSpacing.m),
          Text(l10n.diagMissingThrows, style: theme.textTheme.bodySmall?.copyWith(color: colors.danger)),
        ],
        if (better) ...[
          const SizedBox(height: AppSpacing.m),
          AppCard(
            key: const Key('calibration-suggestion'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.recSuggestion(formatPercent(suggestionAgreement)), style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(describeCalibration(l10n, suggestion), style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.s),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const Key('apply-calibration'),
                    onPressed: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(coordCalibration: suggestion)),
                    child: Text(l10n.recApply),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.l),
        SectionHeader(l10n.recDartList),
        if (a.darts.isEmpty) Text(l10n.recNoDarts, style: theme.textTheme.bodySmall),
        for (final (i, d) in a.darts.indexed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Text('${i + 1}', style: theme.textTheme.labelMedium),
            title: Text(d.segment.name),
            subtitle: d.rawPoint == null
                ? Text(l10n.recNoCoords)
                : Text('x ${d.rawPoint!.x.toStringAsFixed(3)}, y ${d.rawPoint!.y.toStringAsFixed(3)} → ${d.fieldFrom(current)!.name}'),
            trailing: switch (d.matches(current)) {
              true => Icon(Icons.check_rounded, color: colors.success),
              false => Icon(Icons.close_rounded, color: colors.danger),
              null => null,
            },
          ),
        if (a.warnings.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.l),
          SectionHeader(l10n.recWarnings),
          for (final w in a.warnings) Text(w, style: theme.textTheme.bodySmall?.copyWith(color: colors.warning)),
        ],
      ],
    );
  }
}

/// Lesbare Beschreibung einer Kalibrierung.
String describeCalibration(AppLocalizations l10n, CoordinateCalibration c) {
  if (c.isIdentity) return l10n.calibNone;
  return [
    if (c.swapAxes) l10n.calibSwap,
    if (c.mirrorX) l10n.calibMirrorX,
    if (c.mirrorY) l10n.calibMirrorY,
    if (c.scale != 1.0) l10n.calibScale(c.scale.toStringAsPrecision(4)),
  ].join(' · ');
}
