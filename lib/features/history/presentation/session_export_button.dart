import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/l10n.dart';
import '../domain/session_history.dart';
import '../export/session_file_export.dart';
import '../export/session_pdf_export.dart';

/// Teilen-Knopf der Detailansicht: als DartLab-Datei (öffnet sich beim
/// Empfänger in DartLab bzw. DartLab Lite) oder als PDF.
class SessionExportButton extends ConsumerWidget {
  const SessionExportButton({super.key, required this.detail});
  final SessionDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final muted = context.dartColors.textMuted;
    return PopupMenuButton<String>(
      key: const Key('session-export'),
      tooltip: l10n.sharedMatchMenuTooltip,
      icon: const Icon(Icons.ios_share_rounded),
      position: PopupMenuPosition.under,
      onSelected: (v) {
        if (v == 'file') {
          final box = context.findRenderObject() as RenderBox?;
          final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
          shareSessionFile(context, ref, detail, origin: origin);
        } else {
          exportSessionPdf(context, ref, detail);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const Key('session-export-file'),
          value: 'file',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.send_rounded),
            title: Text(l10n.sharedMatchShareFile),
            subtitle: Text(l10n.sharedMatchShareFileHint, style: TextStyle(color: muted)),
          ),
        ),
        PopupMenuItem(
          key: const Key('session-export-pdf'),
          value: 'pdf',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.picture_as_pdf_rounded),
            title: Text(l10n.histExportPdf),
            subtitle: Text(l10n.sharedMatchPdfHint, style: TextStyle(color: muted)),
          ),
        ),
      ],
    );
  }
}
