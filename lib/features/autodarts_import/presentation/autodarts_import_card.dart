import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../../sync/presentation/sync_card.dart' show formatSyncTime;
import 'autodarts_import_controller.dart';
import 'import_dialogs.dart';

/// Optionen › Online-Matches (Browser-Skript): Empfänger an/aus, Port, Code,
/// Status, „Mein Autodarts-Name“ und der Weg über eingefügtes JSON.
///
/// Auf iOS/Android gibt es den Empfänger nicht; dort bleiben Name und
/// JSON-Import. In Lite wird die Karte gar nicht gebaut (eigene Optionen).
class AutodartsImportCard extends ConsumerStatefulWidget {
  const AutodartsImportCard({super.key});

  @override
  ConsumerState<AutodartsImportCard> createState() => _AutodartsImportCardState();
}

class _AutodartsImportCardState extends ConsumerState<AutodartsImportCard> {
  late final TextEditingController _port;
  late final TextEditingController _name;
  final _portKey = GlobalKey<FormFieldState<String>>();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _port = TextEditingController(text: '${settings.autodartsImportPort}');
    _name = TextEditingController(text: settings.autodartsMyName);
  }

  @override
  void dispose() {
    _port.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _applyPort() async {
    if (!(_portKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref.read(settingsProvider.notifier).update((x) => x.copyWith(autodartsImportPort: int.parse(_port.text.trim())));
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name == ref.read(settingsProvider).autodartsMyName) return;
    await ref.read(settingsProvider.notifier).update((x) => x.copyWith(autodartsMyName: name));
  }

  Future<void> _copyCode(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = context.l10n.impCodeCopied;
    await Clipboard.setData(ClipboardData(text: code));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _answerPending(PendingImport pending) async {
    final me = await showWhoAreYouDialog(context, pending.match);
    if (me == null || !mounted) return;
    await ref.read(autodartsImportControllerProvider.notifier).resolve(pending, me);
    if (mounted) setState(() => _name.text = ref.read(settingsProvider).autodartsMyName);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final settings = ref.watch(settingsProvider);
    final state = ref.watch(autodartsImportControllerProvider);
    final supported = ref.watch(importReceiverSupportedProvider);
    final enabled = supported && settings.autodartsImportEnabled;

    Widget statusLine() {
      final (String text, Color? color) = state.problem == ReceiverProblem.portBusy
          ? (l10n.impStatusPortBusy(settings.autodartsImportPort), colors.danger)
          : state.problem != null
              ? (l10n.impStatusError(state.problemDetail ?? ''), colors.danger)
              : state.running
                  ? (l10n.impStatusRunning(state.port ?? settings.autodartsImportPort), colors.success)
                  : (l10n.impStatusStarting, null);
      return Row(
        children: [
          Icon(
            state.problem != null ? Icons.error_outline_rounded : (state.running ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded),
            size: 18,
            color: color ?? colors.textMuted,
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(text, key: const Key('import-status'), style: theme.textTheme.bodyMedium?.copyWith(color: color))),
        ],
      );
    }

    /// Der letzte Import, auch wenn er über „Match-JSON einfügen“ kam.
    Widget lastLine() {
      final last = state.last;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            last == null ? l10n.impStatusNone : l10n.impLast(last.opponent, last.legs, formatSyncTime(last.at)),
            key: const Key('import-last'),
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
          if (last != null && last.overlap) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.impOverlap(formatSyncTime(last.at)),
              key: const Key('import-overlap'),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.warning),
            ),
          ],
        ],
      );
    }

    Widget receiver() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: KeyedSubtree(
                    key: const Key('import-port-field'),
                    child: TextFormField(
                    key: _portKey,
                    controller: _port,
                    decoration: InputDecoration(labelText: l10n.impPort),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final p = int.tryParse(v?.trim() ?? '');
                      return (p == null || p < 1024 || p > 65535) ? l10n.impPortInvalid : null;
                    },
                    onFieldSubmitted: (_) => _applyPort(),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton(
                    key: const Key('import-port-apply'),
                    onPressed: _applyPort,
                    child: Text(l10n.impPortApply),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            Text(l10n.impCode, style: theme.textTheme.bodySmall),
            Row(
              children: [
                Expanded(
                  child: Text(
                    settings.autodartsImportKey,
                    key: const Key('import-code'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 4,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('import-code-copy'),
                  tooltip: l10n.impCodeCopy,
                  onPressed: settings.autodartsImportKey.isEmpty ? null : () => _copyCode(settings.autodartsImportKey),
                  icon: const Icon(Icons.copy_rounded),
                ),
                TextButton(
                  key: const Key('import-code-new'),
                  onPressed: () =>
                      ref.read(settingsProvider.notifier).update((x) => x.copyWith(autodartsImportKey: newImportKey())),
                  child: Text(l10n.impCodeNew),
                ),
              ],
            ),
            Text(l10n.impCodeHint, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.m),
            statusLine(),
            const SizedBox(height: AppSpacing.xs),
          ],
        );

    return AppCard(
      key: const Key('import-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.impIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.m),
          if (supported) ...[
            SwitchListTile(
              key: const Key('import-receiver-switch'),
              contentPadding: EdgeInsets.zero,
              value: settings.autodartsImportEnabled,
              onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(autodartsImportEnabled: v)),
              title: Text(l10n.impReceiver),
              subtitle: Text(l10n.impReceiverHint),
              secondary: const Icon(Icons.cloud_download_rounded),
            ),
            if (enabled) ...[
              const SizedBox(height: AppSpacing.s),
              receiver(),
            ],
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.desktop_windows_rounded, size: 20, color: colors.textMuted),
                const SizedBox(width: AppSpacing.s),
                Expanded(child: Text(l10n.impDesktopOnly, key: const Key('import-desktop-only'), style: theme.textTheme.bodyMedium)),
              ],
            ),
          if (enabled || state.last != null) ...[
            const SizedBox(height: AppSpacing.xs),
            lastLine(),
          ],
          const Divider(height: AppSpacing.xl),
          Focus(
            onFocusChange: (focused) {
              if (!focused) _saveName();
            },
            child: TextField(
              key: const Key('import-my-name'),
              controller: _name,
              decoration: InputDecoration(labelText: l10n.impMyName, helperText: l10n.impMyNameHint, helperMaxLines: 3),
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveName(),
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          if (state.pending.isNotEmpty) ...[
            Row(
              key: const Key('import-pending'),
              children: [
                Icon(Icons.help_outline_rounded, size: 20, color: colors.warning),
                const SizedBox(width: AppSpacing.s),
                Expanded(child: Text(l10n.impPending, style: theme.textTheme.bodyMedium)),
                TextButton(
                  key: const Key('import-pending-answer'),
                  onPressed: () => _answerPending(state.pending.first),
                  child: Text(l10n.impPendingAnswer),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('import-paste'),
              onPressed: () => showImportJsonDialog(context),
              icon: const Icon(Icons.content_paste_go_rounded),
              label: Text(l10n.impPasteButton),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          Container(
            key: const Key('import-tos'),
            padding: const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
              color: colors.surfaceHigh.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.warning.withValues(alpha: 0.45)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: colors.warning),
                const SizedBox(width: AppSpacing.s),
                Expanded(child: Text(l10n.impTosNote, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(l10n.impGuide, key: const Key('import-guide'), style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }
}
