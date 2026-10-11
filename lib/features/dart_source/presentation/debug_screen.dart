import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../data/autodarts_local_source.dart';
import '../domain/dart_source.dart';
import 'dart_source_providers.dart';
import 'source_status_badge.dart';

/// Zeigt rohe eingehende Nachrichten der aktiven Quelle live an.
/// Dient dazu, das Autodarts-Mapping am echten Board nachzuschärfen.
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  String _filter = '';
  bool _paused = false;
  bool _pretty = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final source = ref.watch(dartSourceProvider);
    final entries = ref.watch(rawLogProvider);
    final logNotifier = ref.read(rawLogProvider.notifier);
    final file = logNotifier.log.file;
    final filtered = [
      for (final m in entries.reversed)
        if (_filter.isEmpty || m.payload.toLowerCase().contains(_filter) || m.channel.toLowerCase().contains(_filter)) m,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.debugTitle),
        actions: [
          IconButton(
            tooltip: _paused ? l10n.debugResume : l10n.debugPause,
            icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
            onPressed: () {
              setState(() => _paused = !_paused);
              logNotifier.setPaused(_paused);
            },
          ),
          IconButton(
            tooltip: l10n.debugCopy,
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: logNotifier.log.exportJsonLines()));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.debugCopied(entries.length))));
            },
          ),
          IconButton(
            tooltip: l10n.debugClear,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: logNotifier.clear,
          ),
          const SizedBox(width: AppSpacing.s),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.m),
            child: Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const SourceStatusBadge(),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(dartSourceProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.debugReconnect),
                ),
                if (source is AutodartsLocalSource) ...[
                  OutlinedButton.icon(
                    onPressed: () => unawaited(source.send(AutodartsCommand.reset)),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(l10n.debugCmdReset),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(source.send(AutodartsCommand.start)),
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: Text(l10n.debugCmdStart),
                  ),
                ],
                FilterChip(
                  label: Text(l10n.debugPretty),
                  selected: _pretty,
                  onSelected: (v) => setState(() => _pretty = v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: l10n.debugFilter,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
            ),
          ),
          if (file != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.s, AppSpacing.page, 0),
              child: SelectableText(l10n.debugLogFile(file.path), style: theme.textTheme.bodySmall),
            ),
          if (source is AutodartsLocalSource && source.mappingWarnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.s, AppSpacing.page, 0),
              child: Text(
                l10n.debugWarnings(source.mappingWarnings.length),
                style: theme.textTheme.bodySmall?.copyWith(color: colors.warning),
              ),
            ),
          const SizedBox(height: AppSpacing.m),
          Expanded(
            child: filtered.isEmpty
                ? ComingSoon(icon: Icons.podcasts_rounded, title: l10n.debugEmptyTitle, text: l10n.debugEmpty)
                : ListView.separated(
                    key: const Key('raw-log'),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.page),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (context, i) => _RawTile(message: filtered[i], pretty: _pretty),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RawTile extends StatelessWidget {
  const _RawTile({required this.message, required this.pretty});
  final RawMessage message;
  final bool pretty;

  static const _encoder = JsonEncoder.withIndent('  ');

  String _format(String payload) {
    if (!pretty) return payload;
    try {
      return _encoder.convert(jsonDecode(payload));
    } on FormatException {
      return payload;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final t = message.timestamp;
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
    final color = message.channel == 'info'
        ? colors.textMuted
        : message.incoming
            ? colors.success
            : colors.warning;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadii.s),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$time  ${message.incoming ? '⇣' : '⇡'} ${message.channel}', style: theme.textTheme.labelSmall?.copyWith(color: color)),
          if (message.payload.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              _format(message.payload),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier'],
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
