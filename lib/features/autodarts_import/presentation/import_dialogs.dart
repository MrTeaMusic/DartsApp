import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/background_json.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../backup/data/backup_files.dart';
import '../../matches/presentation/match_texts.dart';
import '../../sync/presentation/sync_card.dart' show formatSyncTime;
import '../data/autodarts_import_service.dart';
import '../domain/imported_match.dart';
import '../domain/import_plan.dart';
import 'autodarts_import_controller.dart';

/// Frage „Welcher Spieler bist du?“. Gibt den Index des gewählten Spielers
/// zurück, `null` bei „Später“.
Future<int?> showWhoAreYouDialog(BuildContext context, ImportedMatch match, {bool useRootNavigator = true}) {
  return showDialog<int>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (context) {
      final l10n = context.l10n;
      final theme = Theme.of(context);
      final colors = context.dartColors;
      return AlertDialog(
        key: const Key('import-who-dialog'),
        title: Text(l10n.impWhoTitle),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.impWhoText, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.m),
              for (final (i, p) in match.players.indexed) ...[
                if (i > 0) const SizedBox(height: AppSpacing.s),
                OutlinedButton.icon(
                  key: Key('import-who-$i'),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.m),
                  ),
                  onPressed: () => Navigator.pop(context, i),
                  icon: Icon(Icons.person_rounded, color: colors.textMuted),
                  label: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(key: const Key('import-who-later'), onPressed: () => Navigator.pop(context), child: Text(l10n.impWhoLater)),
        ],
      );
    },
  );
}

/// Dialog „Match-JSON einfügen“ mit Vorschau. Importiert mit denselben
/// Regeln wie der Empfänger.
Future<void> showImportJsonDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _ImportJsonDialog());
}

sealed class _Preview {
  const _Preview();
}

class _Empty extends _Preview {
  const _Empty();
}

class _Failed extends _Preview {
  const _Failed(this.message);
  final String message;
}

class _Ready extends _Preview {
  const _Ready({required this.match, required this.me, required this.plan, required this.existing});

  final ImportedMatch match;

  /// Eigener Spieler, `null`: Frage beim Importieren.
  final int? me;
  final ImportPlan plan;

  /// Das Match ist schon importiert.
  final bool existing;
}

class _ImportJsonDialog extends ConsumerStatefulWidget {
  const _ImportJsonDialog();

  @override
  ConsumerState<_ImportJsonDialog> createState() => _ImportJsonDialogState();
}

class _ImportJsonDialogState extends ConsumerState<_ImportJsonDialog> {
  final _text = TextEditingController();
  _Preview _preview = const _Empty();
  int _run = 0;
  bool _busy = false;
  String? _clipboardNote;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    final run = ++_run;
    final raw = _text.text.trim();
    if (raw.isEmpty) {
      setState(() => _preview = const _Empty());
      return;
    }
    _Preview next;
    try {
      final json = await BackgroundJson.decode(raw);
      final service = ref.read(autodartsImportServiceProvider);
      final match = service.read(json);
      final known = identifyMe(match, service.myName());
      final plan = buildImportPlan(match, me: known ?? 0);
      final existing = await ref.read(autodartsImportRepositoryProvider).findByMatchId(match.id);
      next = _Ready(match: match, me: known, plan: plan, existing: existing != null);
    } on AutodartsImportException catch (e) {
      next = _Failed(e.message);
    } on FormatException {
      next = const _Failed('Kein gültiges JSON.');
    } on Object {
      next = const _Failed('Format unbekannt.');
    }
    if (!mounted || run != _run) return;
    setState(() => _preview = next);
  }

  Future<void> _fromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _clipboardNote = context.l10n.impClipboardEmpty);
      return;
    }
    _clipboardNote = null;
    _text.text = text;
    await _update();
  }

  Future<void> _fromFile() async {
    final text = await ref.read(backupFilesProvider).openText();
    if (!mounted || text == null) return;
    _clipboardNote = null;
    _text.text = text;
    await _update();
  }

  Future<void> _import() async {
    final p = _preview;
    if (p is! _Ready || _busy) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    var me = p.me;
    if (me == null) {
      me = await showWhoAreYouDialog(context, p.match);
      if (me == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final reply = await ref.read(autodartsImportServiceProvider).importMatch(p.match, me: me, origin: 'file', replace: p.existing);
      // Die Namenswahl aus der Frage steht jetzt in den Optionen; die Anzeige
      // der Karte aktualisiert sich über die Einstellungen.
      ref.read(autodartsImportControllerProvider.notifier).recordManual(reply);
      final plan = reply.plan;
      var text = switch (reply.status) {
        ImportStatus.imported when reply.replaced => l10n.impReplacedDone(plan!.opponent.name, '${plan.legsMe}:${plan.legsOpponent}'),
        ImportStatus.imported => l10n.impImported(plan!.opponent.name, '${plan.legsMe}:${plan.legsOpponent}'),
        ImportStatus.duplicate => l10n.impDuplicateDone,
        ImportStatus.ignored => l10n.impIgnoredDone(reply.message ?? ''),
        ImportStatus.pending => l10n.impPreviewAsk,
      };
      if (reply.overlapStartedAt != null) {
        text = '$text\n${l10n.impOverlapNote(formatSyncTime(reply.overlapStartedAt!))}';
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 8)));
      navigator.pop();
    } on AutodartsImportException catch (e) {
      if (mounted) setState(() => _preview = _Failed(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final p = _preview;
    final ready = p is _Ready ? p : null;

    Widget previewBox() {
      final (IconData icon, Color color, List<String> lines) = switch (p) {
        _Empty() => (Icons.data_object_rounded, colors.textMuted, [l10n.impPreviewEmpty]),
        _Failed(:final message) => (Icons.error_outline_rounded, colors.danger, [message]),
        _Ready() => (
            p.existing ? Icons.info_outline_rounded : Icons.check_circle_rounded,
            p.existing ? colors.warning : colors.success,
            [
              if (p.me != null)
                l10n.impPreview(
                  p.plan.myPlayer.name,
                  p.plan.opponent.name,
                  '${p.plan.legsMe}:${p.plan.legsOpponent}',
                  p.plan.ownVisits,
                )
              else
                l10n.impPreviewPlayers(p.match.players[0].name, p.match.players[1].name, '${p.plan.legsMe}:${p.plan.legsOpponent}'),
              l10n.impPreviewFormat(p.match.startScore, l10n.outModeLabel(p.match.outMode)),
              if (p.me == null) l10n.impPreviewAsk,
              if (!p.match.finished) l10n.impPreviewOpen,
              if (p.existing) l10n.impAlready,
              if (p.existing) l10n.impReplaceHint,
              ...p.plan.warnings,
            ],
          ),
      };
      return Container(
        key: const Key('import-preview'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.m),
        decoration: BoxDecoration(
          color: colors.surfaceHigh.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, line) in lines.indexed)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.xxs),
                      child: Text(
                        line,
                        key: i == 0 ? const Key('import-preview-title') : null,
                        style: i == 0 ? theme.textTheme.titleSmall : theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      key: const Key('import-json-dialog'),
      title: Text(l10n.impPasteTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.impPasteText, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.m),
              TextField(
                key: const Key('import-json-field'),
                controller: _text,
                minLines: 4,
                maxLines: 6,
                autocorrect: false,
                enableSuggestions: false,
                style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                decoration: InputDecoration(labelText: l10n.impPasteField, alignLabelWithHint: true),
                onChanged: (_) => _update(),
              ),
              const SizedBox(height: AppSpacing.s),
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  OutlinedButton.icon(
                    key: const Key('import-json-clipboard'),
                    onPressed: _fromClipboard,
                    icon: const Icon(Icons.content_paste_rounded),
                    label: Text(l10n.impPasteClipboard),
                  ),
                  OutlinedButton.icon(
                    key: const Key('import-json-file'),
                    onPressed: _fromFile,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(l10n.impPasteFile),
                  ),
                ],
              ),
              if (_clipboardNote != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(_clipboardNote!, style: theme.textTheme.bodySmall?.copyWith(color: colors.danger)),
              ],
              const SizedBox(height: AppSpacing.m),
              previewBox(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(key: const Key('import-json-close'), onPressed: () => Navigator.pop(context), child: Text(l10n.impClose)),
        FilledButton(
          key: const Key('import-json-import'),
          onPressed: ready == null || _busy ? null : _import,
          child: Text(ready?.existing == true ? l10n.impReplace : l10n.impImport),
        ),
      ],
    );
  }
}
