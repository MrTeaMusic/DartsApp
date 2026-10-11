import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../domain/dart_event.dart';
import '../domain/dart_source.dart';
import 'dart_source_providers.dart';

extension DartSourceKindLabel on DartSourceKind {
  String label(AppLocalizations l10n) => switch (this) {
        DartSourceKind.simulator => l10n.sourceSimulator,
        DartSourceKind.manual => l10n.sourceManual,
        DartSourceKind.autodartsLocal => l10n.sourceAutodarts,
      };

  IconData get icon => switch (this) {
        DartSourceKind.simulator => Icons.touch_app_rounded,
        DartSourceKind.manual => Icons.dialpad_rounded,
        DartSourceKind.autodartsLocal => Icons.videocam_rounded,
      };
}

/// Zeigt Quelle und Verbindungsstatus. Tippen öffnet die Debug-Ansicht.
class SourceStatusBadge extends ConsumerWidget {
  const SourceStatusBadge({super.key, this.compact = false});

  /// Nur der Status ohne Quelle, für schmale Kopfzeilen.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final source = ref.watch(dartSourceProvider);
    final status = ref.watch(sourceStatusProvider).value ?? source.status;
    final (label, color, pulsing) = describe(status, l10n, colors);
    return StatusPill(
      key: const Key('source-status'),
      label: compact ? label : '${source.kind.label(l10n)} · $label',
      color: color,
      pulsing: pulsing,
      onTap: () => context.go(Routes.debug),
    );
  }

  static (String, Color, bool) describe(SourceStatus status, AppLocalizations l10n, DartColors colors) {
    return switch (status.phase) {
      SourcePhase.idle => (l10n.statusIdle, colors.textMuted, false),
      SourcePhase.connecting => (l10n.statusConnecting, colors.warning, true),
      SourcePhase.connected => (l10n.statusConnected, colors.success, false),
      SourcePhase.polling => (l10n.statusPolling, colors.success, false),
      SourcePhase.reconnecting => (
          l10n.statusReconnecting(
            status.nextRetry == null
                ? 0
                : status.nextRetry!.difference(DateTime.now()).inSeconds.clamp(0, 999),
          ),
          colors.warning,
          true,
        ),
      SourcePhase.error => (l10n.statusError, colors.danger, false),
    };
  }
}
