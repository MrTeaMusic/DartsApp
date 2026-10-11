import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../data/autodarts_diagnostics.dart';

/// Erzeugt den Verbindungstest. In Tests überschreibbar.
final diagnosticsFactoryProvider = Provider<AutodartsDiagnostics Function(String host, int port)>(
  (ref) => (host, port) => AutodartsDiagnostics(host: host, port: port),
);

extension DiagnosticTexts on AppLocalizations {
  String checkTitle(CheckKind k) => switch (k) {
        CheckKind.http => diagHttp,
        CheckKind.stateFormat => diagFormat,
        CheckKind.throwsField => diagThrows,
        CheckKind.detection => diagDetection,
        CheckKind.webSocket => diagWebSocket,
      };

  String? checkHint(DiagnosticCheck c) => switch (c.reason) {
        CheckReason.none => null,
        CheckReason.refused => diagRefused,
        CheckReason.timeout => diagTimeout,
        CheckReason.hostNotFound => diagHostNotFound,
        CheckReason.unauthorized => diagUnauthorized,
        CheckReason.httpStatus => diagHttpStatus(c.detail),
        CheckReason.notJson => diagNotJson,
        CheckReason.missingThrows => diagMissingThrows,
        CheckReason.stopped => diagStopped,
        CheckReason.noMessages => diagNoMessages,
        CheckReason.other => diagOther(c.detail),
      };
}

Future<void> showDiagnosticsDialog(BuildContext context, {required String host, required int port}) =>
    showDialog<void>(context: context, builder: (_) => _DiagnosticsDialog(host: host, port: port));

class _DiagnosticsDialog extends ConsumerStatefulWidget {
  const _DiagnosticsDialog({required this.host, required this.port});
  final String host;
  final int port;

  @override
  ConsumerState<_DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends ConsumerState<_DiagnosticsDialog> {
  List<DiagnosticCheck>? _checks;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _checks = null);
    final checks = await ref.read(diagnosticsFactoryProvider)(widget.host, widget.port).run();
    if (mounted) setState(() => _checks = checks);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final checks = _checks;
    return AlertDialog(
      title: Text(l10n.diagTitle('${widget.host}:${widget.port}')),
      content: SizedBox(
        width: 480,
        child: checks == null
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [const CircularProgressIndicator(), const SizedBox(height: AppSpacing.l), Text(l10n.diagRunning)],
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final c in checks) _CheckTile(check: c)],
                ),
              ),
      ),
      actions: [
        TextButton(key: const Key('diag-again'), onPressed: checks == null ? null : _run, child: Text(l10n.diagAgain)),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(l10n.gameDone)),
      ],
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check});
  final DiagnosticCheck check;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final (icon, color) = switch (check.result) {
      CheckResult.ok => (Icons.check_circle_rounded, colors.success),
      CheckResult.warning => (Icons.warning_amber_rounded, colors.warning),
      CheckResult.failed => (Icons.cancel_rounded, colors.danger),
      CheckResult.skipped => (Icons.remove_circle_outline_rounded, colors.textMuted),
    };
    final hint = l10n.checkHint(check);
    return Padding(
      key: Key('check-${check.kind.name}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.checkTitle(check.kind), style: theme.textTheme.titleSmall),
                if (check.detail.isNotEmpty && check.reason != CheckReason.other && check.reason != CheckReason.httpStatus)
                  Text(check.detail, style: theme.textTheme.bodySmall),
                if (hint != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: color)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
