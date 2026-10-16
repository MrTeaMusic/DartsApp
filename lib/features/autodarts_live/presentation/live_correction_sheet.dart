import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../board/domain/segment.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../simulator/presentation/segment_picker.dart';
import '../domain/live_recorder.dart';
import 'autodarts_live_controller.dart';

/// Was im Korrektur-Blatt gewählt wurde.
sealed class LiveFixResult {
  const LiveFixResult();
}

/// Neues Feld für den Dart.
class LiveFixPick extends LiveFixResult {
  const LiveFixPick(this.segment);
  final Segment segment;
}

/// Den Dart aus der Aufnahme entfernen.
class LiveFixRemoveDart extends LiveFixResult {
  const LiveFixRemoveDart();
}

/// Die ganze Aufnahme löschen.
class LiveFixRemoveVisit extends LiveFixResult {
  const LiveFixRemoveVisit();
}

/// Blatt mit der Feldauswahl der Spiele ([SegmentPicker]); mit [removable]
/// zusätzlich „Dart entfernen“ und „Aufnahme löschen“.
Future<LiveFixResult?> showLiveFixSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  String? note,
  bool removable = false,
}) {
  return showModalBottomSheet<LiveFixResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) {
      final l10n = context.l10n;
      final theme = Theme.of(context);
      final colors = context.dartColors;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, key: const Key('live-fix-title'), style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle, key: const Key('live-fix-subtitle'), style: theme.textTheme.bodySmall),
              const SizedBox(height: AppSpacing.l),
              SegmentPicker(keyPrefix: 'fix', onPick: (s) => Navigator.pop(context, LiveFixPick(s))),
              const SizedBox(height: AppSpacing.m),
              if (note != null) Text(note, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
              if (removable) ...[
                const SizedBox(height: AppSpacing.l),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('live-fix-remove-dart'),
                        onPressed: () => Navigator.pop(context, const LiveFixRemoveDart()),
                        icon: const Icon(Icons.backspace_outlined),
                        label: Text(l10n.liveFixRemoveDart),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('live-fix-remove-visit'),
                        style: OutlinedButton.styleFrom(foregroundColor: colors.danger),
                        onPressed: () => Navigator.pop(context, const LiveFixRemoveVisit()),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(l10n.liveFixRemoveVisit),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Dart [dart] der Aufnahme [visit] (Nummer ab 0, siehe
/// [LiveViewState.closedCount]) korrigieren: Feld ändern, Dart entfernen oder
/// die ganze Aufnahme löschen.
Future<void> fixLiveDart(
  BuildContext context,
  WidgetRef ref, {
  required int visit,
  required int dart,
  required DartThrow current,
  required int visitLength,
}) async {
  final l10n = context.l10n;
  final result = await showLiveFixSheet(
    context,
    title: l10n.liveFixTitle(visit + 1, dart + 1),
    subtitle: LiveRecorder.isManual(current)
        ? l10n.liveFixManual(current.segment.name)
        : l10n.liveFixDetected(current.segment.name),
    note: l10n.liveFixNote,
    removable: true,
  );
  if (result == null || !context.mounted) return;
  final controller = ref.read(autodartsLiveProvider.notifier);
  switch (result) {
    case LiveFixPick(:final segment):
      controller.correctDart(visit, dart, segment);
    case LiveFixRemoveDart():
      controller.removeDart(visit, dart);
    case LiveFixRemoveVisit():
      final messenger = ScaffoldMessenger.of(context);
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('live-fix-remove-visit-dialog'),
          title: Text(l10n.liveFixRemoveVisitTitle(visit + 1)),
          content: Text(l10n.liveFixRemoveVisitText(visitLength)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.gameCancelShort)),
            FilledButton(
              key: const Key('live-fix-remove-visit-confirm'),
              style: FilledButton.styleFrom(backgroundColor: context.dartColors.danger, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.histDeleteConfirm),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (controller.removeVisit(visit)) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.liveFixVisitRemoved(visit + 1))));
      }
  }
}

/// Einen vergessenen Dart ans Ende der Aufnahme [visit] ergänzen.
Future<void> addLiveDart(BuildContext context, WidgetRef ref, {required int visit}) async {
  final l10n = context.l10n;
  final result = await showLiveFixSheet(
    context,
    title: l10n.liveFixAddTitle(visit + 1),
    subtitle: l10n.liveFixAddNote(LiveRecorder.dartsPerVisit),
  );
  if (result is LiveFixPick) ref.read(autodartsLiveProvider.notifier).addDart(visit, result.segment);
}
