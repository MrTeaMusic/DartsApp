import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/l10n.dart';
import '../../backup/data/backup_files.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/stats_repository.dart';
import '../domain/stats_models.dart';
import '../presentation/period_picker.dart';
import 'online_stats_pdf.dart';

/// Erzeugt das PDF mit der Online-Statistik für [period] und speichert es.
/// [focusSessionId] hebt ein Match samt Legs hervor (Export aus der
/// Match-Ansicht). Meldet das Ergebnis per Snackbar.
Future<void> exportOnlinePdf(
  BuildContext context,
  WidgetRef ref, {
  StatsPeriod period = StatsPeriod.all,
  int? focusSessionId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  void show(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  try {
    final calc = ref.read(statsCalculatorProvider).value;
    if (calc == null) return;
    final report = calc.onlineReport(period);
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    final today = calc.now;
    final periodLabel = switch (period.name) {
      'week' => l10n.statsPeriodWeek,
      'month' => l10n.statsPeriodMonth,
      'quarter' => l10n.statsPeriodQuarter,
      'custom' => formatPeriodRange(period, today),
      _ => l10n.statsPeriodAll,
    };
    final bytes = await OnlineStatsPdf.build(
      OnlineStatsPdfInput(
        l10n: l10n,
        playerName: ref.read(activePlayerProvider)?.name ?? '',
        periodLabel: periodLabel,
        createdAt: DateTime.now(),
        report: report,
        compare: calc.onlineComparison(period),
        focus: focusSessionId == null ? null : report.matches.where((m) => m.sessionId == focusSessionId).firstOrNull,
      ),
      regular: regular,
      bold: bold,
    );
    String two(int v) => v.toString().padLeft(2, '0');
    final n = DateTime.now();
    final stamp = '${n.year}-${two(n.month)}-${two(n.day)}';
    final name = focusSessionId == null ? 'dartlab-online-statistik-$stamp.pdf' : 'dartlab-match-$stamp.pdf';
    final path = await ref.read(backupFilesProvider).saveBytes(name, bytes, mimeType: 'application/pdf', extension: 'pdf');
    if (path != null) show(l10n.backupSaved(path));
  } on Exception catch (e) {
    show(l10n.backupFailed('$e'));
  }
}
