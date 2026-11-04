import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/l10n.dart';
import '../../backup/data/backup_files.dart';
import '../../stats/data/stats_repository.dart';
import '../../stats/presentation/elo_tab.dart';
import '../domain/leg_board.dart';
import '../domain/session_history.dart';
import 'session_pdf.dart';

/// Erzeugt das PDF mit der ausführlichen Auswertung von [detail] und
/// speichert es. Meldet das Ergebnis per Snackbar.
Future<void> exportSessionPdf(BuildContext context, WidgetRef ref, SessionDetail detail) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  void show(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  try {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    final elo = ref.read(houseEloProvider)?.stepOf(detail.entry.id);
    final now = DateTime.now();
    final bytes = await SessionPdf.build(
      SessionPdfInput(
        l10n: l10n,
        detail: detail,
        boards: legBoardsOf(detail),
        createdAt: now,
        eloLine: elo == null ? null : l10n.eloHistoryValue(elo.before.round(), elo.after.round(), formatEloChange(elo.change)),
      ),
      regular: regular,
      bold: bold,
    );
    String two(int v) => v.toString().padLeft(2, '0');
    final s = detail.entry.startedAt;
    final name = 'dartlab-match-${s.year}-${two(s.month)}-${two(s.day)}-${two(s.hour)}${two(s.minute)}.pdf';
    final path = await ref.read(backupFilesProvider).saveBytes(name, bytes, mimeType: 'application/pdf', extension: 'pdf');
    if (path != null) show(l10n.backupSaved(path));
  } on Exception catch (e) {
    show(l10n.backupFailed('$e'));
  }
}
