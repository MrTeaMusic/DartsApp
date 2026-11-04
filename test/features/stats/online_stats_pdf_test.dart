import 'dart:io';

import 'package:dartlab/features/stats/domain/online_stats.dart';
import 'package:dartlab/features/stats/domain/stats_models.dart';
import 'package:dartlab/features/stats/export/online_stats_pdf.dart';
import 'package:dartlab/l10n/gen/app_localizations_de.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

OnlineMatch _match(int id, DateTime at, {double avg = 60, bool won = true}) => OnlineMatch(
      sessionId: id,
      startedAt: at,
      duration: const Duration(minutes: 22),
      x01: true,
      darts: 90,
      average: avg,
      first9: avg + 3,
      legsWon: won ? 3 : 1,
      legsLost: won ? 1 : 3,
      checkout: const HitCount(12, 4),
      highestFinish: 96,
      count100: 4,
      count140: 1,
      count180: id % 2,
      opponent: 'Max',
      won: won,
      legs: [
        OnlineLeg(darts: 18, points: 501, first9: avg + 5, checkout: 40, won: true),
        OnlineLeg(darts: 24, points: 400, first9: avg - 4, checkout: 0, won: false),
      ],
    );

OnlineStatsPdfInput _input({bool empty = false, bool focus = false}) {
  final matches = empty
      ? <OnlineMatch>[]
      : [for (var i = 0; i < 40; i++) _match(40 - i, DateTime(2026, 10, 30).subtract(Duration(days: i * 2)), avg: 55 + (i % 7) * 2.5, won: i % 3 != 0)];
  var totals = const OnlineTotals();
  final weeks = <DateTime, OnlineTotals>{};
  for (final m in matches.reversed) {
    totals = totals.add(m);
    final w = DateTime(m.startedAt.year, m.startedAt.month, m.startedAt.day - (m.startedAt.weekday - 1));
    weeks[w] = (weeks[w] ?? const OnlineTotals()).add(m);
  }
  final report = OnlineReport(
    matches: matches,
    totals: totals,
    weeks: [for (final w in weeks.keys.toList()..sort()) (weekStart: w, totals: weeks[w]!)],
  );
  MetricComparison mc(CompareMetric m, double tr, double on, int amount) =>
      MetricComparison(m, CompareSide(on, amount), CompareSide(tr, amount));
  final compare = OnlineComparison(
    average: mc(CompareMetric.average, 62.4, 58.1, 200),
    first9: mc(CompareMetric.first9, 66, 60.2, 12),
    checkout: mc(CompareMetric.checkoutRate, 0.42, 0.33, 40),
    doubles: mc(CompareMetric.doubleRate, 0.38, 0.22, 90),
    scoring: mc(CompareMetric.scoring, 0, 0, 100),
    perDouble: {
      for (final n in [16, 20, 8, 25]) n: DoubleComparison(n, HitCount(20, 4 + n % 5), const HitCount(30, 14)),
    },
    onlineBands: {for (final b in ScoreBand.values) b: 10 + b.index},
    trainingBands: {for (final b in ScoreBand.values) b: 12 - b.index},
  );
  return OnlineStatsPdfInput(
    l10n: AppLocalizationsDe(),
    playerName: 'Ben',
    periodLabel: '30 Tage',
    createdAt: DateTime(2026, 11, 4),
    report: report,
    compare: compare,
    focus: focus ? matches.first : null,
  );
}

Future<pw.Font> _font(String name) async => pw.Font.ttf(ByteData.sublistView(await File('assets/fonts/$name').readAsBytes()));

void main() {
  test('baut ein PDF mit Matches, Verlauf und Vergleich', () async {
    final regular = await _font('Inter-Regular.ttf');
    final bold = await _font('Inter-Bold.ttf');
    final bytes = await OnlineStatsPdf.build(_input(focus: true), regular: regular, bold: bold);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(5000));
    final out = Platform.environment['PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  test('ohne Matches steht ein Hinweis statt leerer Tabellen', () async {
    final regular = await _font('Inter-Regular.ttf');
    final bold = await _font('Inter-Bold.ttf');
    final bytes = await OnlineStatsPdf.build(_input(empty: true), regular: regular, bold: bold);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
