/// PDF mit der gesamten Online-Statistik (Matches aus Autodarts Live und
/// importierte Online-Matches), optional mit einem hervorgehobenen Match samt
/// Legs. Reine Dart-Logik ohne Widgets: Zahlen kommen fertig aus
/// [OnlineReport] und [OnlineComparison], Texte aus [AppLocalizations].
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../l10n/gen/app_localizations.dart';
import '../../games/domain/engine/game_display.dart';
import '../domain/online_stats.dart';
import '../domain/stats_models.dart';

/// Alles, was ins PDF kommt.
class OnlineStatsPdfInput {
  const OnlineStatsPdfInput({
    required this.l10n,
    required this.playerName,
    required this.periodLabel,
    required this.createdAt,
    required this.report,
    required this.compare,
    this.focus,
  });

  final AppLocalizations l10n;
  final String playerName;

  /// Zeitraum in Worten („30 Tage“, „1.10.2026 – 31.10.2026“).
  final String periodLabel;
  final DateTime createdAt;
  final OnlineReport report;
  final OnlineComparison compare;

  /// Match, das mit seinen Legs eigens aufgeführt wird.
  final OnlineMatch? focus;
}

abstract final class OnlineStatsPdf {
  static const _ink = PdfColor.fromInt(0xFF14161C);
  static const _muted = PdfColor.fromInt(0xFF6B7280);
  static const _line = PdfColor.fromInt(0xFFE5E7EB);
  static const _tint = PdfColor.fromInt(0xFFF3F4F6);
  static const _accent = PdfColor.fromInt(0xFF7C3AED);
  static const _teal = PdfColor.fromInt(0xFF0E9F8E);
  static const _good = PdfColor.fromInt(0xFF16A34A);
  static const _bad = PdfColor.fromInt(0xFFDC2626);

  static String _dec(num? v) => formatDecimal(v);
  static String _pct(double? v) => v == null ? '–' : '${(v * 100).round()} %';
  static String _date(DateTime d) => '${d.day}.${d.month}.${d.year}';
  static String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  static String _double(int n) => n == 25 ? 'Bull' : 'D$n';

  /// Baut das Dokument. [regular] und [bold] müssen Umlaute und „Ø“ können
  /// (die mitgelieferte Inter).
  static Future<Uint8List> build(OnlineStatsPdfInput input, {required pw.Font regular, required pw.Font bold}) {
    final doc = pw.Document(
      title: input.l10n.onlinePdfTitle,
      author: 'DartLab',
      theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: regular, boldItalic: bold),
    );
    final l10n = input.l10n;
    final t = input.report.totals;
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 42),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('DartLab', style: const pw.TextStyle(fontSize: 8, color: _muted)),
            pw.Text(l10n.onlinePdfPage(ctx.pageNumber, ctx.pagesCount), style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ],
        ),
        build: (ctx) => [
          _title(input),
          pw.SizedBox(height: 14),
          if (input.report.isEmpty)
            pw.Text(l10n.onlinePdfNoData, style: const pw.TextStyle(fontSize: 11, color: _muted))
          else ...[
            _tiles(l10n, t),
            if (input.focus != null) ...[
              _heading(l10n.onlinePdfThisMatch),
              ..._focus(l10n, input.focus!),
            ],
            _heading(l10n.onlinePdfTrend),
            _trends(input),
            _heading(l10n.onlineCompareTitle),
            _compareTable(input),
            ..._doubles(input),
            ..._distribution(input),
            _heading('${l10n.onlinePdfAllMatches} (${input.report.matches.length})'),
            _matchTable(input),
          ],
        ],
      ),
    );
    return doc.save();
  }

  // -------------------------------------------------------------------------
  // Bausteine
  // -------------------------------------------------------------------------

  static pw.Widget _title(OnlineStatsPdfInput i) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: pw.BoxDecoration(color: _ink, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(i.l10n.onlinePdfTitle, style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            pw.SizedBox(height: 4),
            pw.Text(
              i.l10n.onlinePdfMeta(i.playerName, i.periodLabel, _date(i.createdAt)),
              style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFFD1D5DB)),
            ),
          ],
        ),
      );

  static pw.Widget _heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
        child: pw.Row(children: [
          pw.Container(width: 3, height: 12, color: _accent),
          pw.SizedBox(width: 6),
          pw.Text(text, style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
        ]),
      );

  static pw.Widget _tile(String label, String value, {String? caption}) => pw.Container(
        width: 118,
        padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: pw.BoxDecoration(color: _tint, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: _muted, letterSpacing: 0.6)),
            pw.SizedBox(height: 3),
            pw.Text(value, style: const pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _ink)),
            if (caption != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(caption, style: const pw.TextStyle(fontSize: 7, color: _muted)),
            ],
          ],
        ),
      );

  static pw.Widget _tiles(AppLocalizations l10n, OnlineTotals t) => pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _tile(l10n.onlineMatches, '${t.matches}', caption: '${t.darts} ${l10n.statDarts}'),
          _tile(l10n.statAverage, _dec(t.average)),
          if (t.first9 != null) _tile(l10n.statsFirst9, _dec(t.first9)),
          if (t.checkout.attempts > 0)
            _tile(l10n.statCheckoutRate, _pct(t.checkoutRate), caption: '${t.checkout.hits} / ${t.checkout.attempts}'),
          if (t.highestFinish > 0) _tile(l10n.onlineHighestFinish, '${t.highestFinish}'),
          _tile(l10n.onlineTons, '${t.tons} / ${t.maxes}'),
          if (t.legs > 0) _tile('Legs', '${t.legsWon} : ${t.legsLost}'),
        ],
      );

  // -- Verlauf ---------------------------------------------------------------

  static pw.Widget _trends(OnlineStatsPdfInput i) {
    final l10n = i.l10n;
    final specs = [
      (l10n.statAverage, OnlineTrendMetric.average, false, _accent),
      (l10n.statsFirst9, OnlineTrendMetric.first9, false, _teal),
      (l10n.statCheckoutRate, OnlineTrendMetric.checkoutRate, true, const PdfColor.fromInt(0xFFF59E0B)),
    ];
    final charts = <pw.Widget>[];
    for (final (title, metric, percent, color) in specs) {
      final points = i.report.trend(metric);
      if (points.length < 2) continue;
      charts.add(_trendChart(title, points, percent: percent, color: color, weekly: i.report.byWeek));
    }
    if (charts.isEmpty) {
      return pw.Text(
        i.report.byWeek ? l10n.onlineTrendWeekly : l10n.onlineTrendPerMatch,
        style: const pw.TextStyle(fontSize: 9, color: _muted),
      );
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text(
        i.report.byWeek ? l10n.onlineTrendWeekly : l10n.onlineTrendPerMatch,
        style: const pw.TextStyle(fontSize: 8, color: _muted),
      ),
      pw.SizedBox(height: 6),
      for (final c in charts) ...[c, pw.SizedBox(height: 10)],
    ]);
  }

  static pw.Widget _trendChart(String title, List<TrendPoint> points,
      {required bool percent, required PdfColor color, required bool weekly}) {
    final values = [for (final p in points) percent ? p.value * 100 : p.value];
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.15;
    lo = (lo - pad).clamp(0, double.infinity);
    hi += pad;
    final step = _niceStep((hi - lo) / 4);
    final yMin = (lo / step).floor() * step;
    final yMax = (hi / step).ceil() * step;
    final yTicks = <double>[for (var v = yMin; v <= yMax + 1e-9; v += step) v];
    final xEvery = (points.length / 7).ceil();
    final xTicks = <double>[for (var k = 0; k < points.length; k += xEvery) k.toDouble()];
    String xLabel(num x) => _shortDate(points[x.toInt()].time);
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title, style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.SizedBox(height: 4),
        pw.SizedBox(
          height: 110,
          child: pw.Chart(
            grid: pw.CartesianGrid(
              xAxis: pw.FixedAxis(xTicks, format: xLabel, textStyle: const pw.TextStyle(fontSize: 7, color: _muted), margin: 6),
              yAxis: pw.FixedAxis(
                yTicks,
                format: (v) => percent ? '${v.round()} %' : v.toStringAsFixed(step < 1 ? 1 : 0).replaceAll('.', ','),
                textStyle: const pw.TextStyle(fontSize: 7, color: _muted),
                divisions: true,
                divisionsDashed: true,
                margin: 6,
              ),
            ),
            datasets: [
              pw.LineDataSet(
                data: [for (final (k, v) in values.indexed) pw.PointChartValue(k.toDouble(), v)],
                color: color,
                lineWidth: 1.6,
                drawPoints: false,
              ),
            ],
          ),
        ),
      ]),
    );
  }

  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    for (final s in const [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0]) {
      if (raw <= s) return s;
    }
    return 100;
  }

  static String _shortDate(DateTime d) => '${d.day}.${d.month}.';

  // -- Training gegen Match --------------------------------------------------

  static String _metricLabel(AppLocalizations l10n, CompareMetric m) => switch (m) {
        CompareMetric.average => l10n.statAverage,
        CompareMetric.first9 => l10n.statsFirst9,
        CompareMetric.checkoutRate => l10n.statCheckoutRate,
        CompareMetric.doubleRate => l10n.statDoubleRate,
        CompareMetric.scoring => l10n.statsTons,
      };

  static bool _isRate(CompareMetric m) => m != CompareMetric.average && m != CompareMetric.first9;

  static String _value(CompareMetric m, double? v) => _isRate(m) ? _pct(v) : _dec(v);

  static (String, PdfColor) _diff(MetricComparison c) {
    final d = c.diff;
    if (d == null) return ('–', _muted);
    final rate = _isRate(c.metric);
    final shown = rate ? (d.abs() * 100).round() : double.parse(d.abs().toStringAsFixed(1));
    final zero = shown == 0;
    final sign = zero ? '±' : (d > 0 ? '+' : '−');
    final text = rate ? '$sign$shown Pp' : '$sign${_dec(d.abs())}';
    final flat = rate ? d.abs() < 0.02 : d.abs() < 1;
    return (text, flat ? _muted : (d < 0 ? _bad : _good));
  }

  static pw.Widget _cell(String text, {bool right = false, bool bold = false, PdfColor color = _ink, double size = 9}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(
          text,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
        ),
      );

  static pw.TableRow _headRow(List<String> labels, {int firstLeft = 1}) => pw.TableRow(
        decoration: const pw.BoxDecoration(color: _tint),
        children: [
          for (final (k, l) in labels.indexed) _cell(l, right: k >= firstLeft, bold: true, color: _muted, size: 8),
        ],
      );

  static const _rowBorder = pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5), bottom: pw.BorderSide(color: _line, width: 0.5));

  static pw.Widget _compareTable(OnlineStatsPdfInput i) {
    final l10n = i.l10n;
    final c = i.compare;
    final notable = [
      for (final d in c.notableDrops) _double(d.number),
      if (c.doublesNotable) l10n.statDoubleRate,
      if (c.first9Notable) l10n.statsFirst9,
    ];
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Table(
        border: _rowBorder,
        columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.4), 2: pw.FlexColumnWidth(1.4), 3: pw.FlexColumnWidth(1.4)},
        children: [
          _headRow(['', l10n.onlineCompareTraining, l10n.onlineCompareOnline, '±']),
          for (final m in c.metrics)
            pw.TableRow(children: [
              _cell(_metricLabel(l10n, m.metric)),
              _cell(_value(m.metric, m.trainingReady ? m.training.value : null), right: true),
              _cell(_value(m.metric, m.onlineReady ? m.online.value : null), right: true, bold: true),
              () {
                final (text, color) = _diff(m);
                return _cell(text, right: true, bold: true, color: color);
              }(),
            ]),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        c.ready ? (notable.isEmpty ? l10n.onlineNotableNone : l10n.onlineNotable(notable.join(', '))) : l10n.onlineCompareEmptyText,
        style: const pw.TextStyle(fontSize: 8.5, color: _muted),
      ),
    ]);
  }

  static List<pw.Widget> _doubles(OnlineStatsPdfInput i) {
    final ranked = i.compare.ranked.take(10).toList();
    if (ranked.isEmpty) return const [];
    final l10n = i.l10n;
    return [
      _heading(l10n.onlineDoublesTitle),
      pw.Table(
        border: _rowBorder,
        columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1.4), 2: pw.FlexColumnWidth(1.4), 3: pw.FlexColumnWidth(1.4)},
        children: [
          _headRow(['', l10n.onlineCompareTraining, l10n.onlineCompareOnline, '±']),
          for (final d in ranked)
            pw.TableRow(children: [
              _cell(_double(d.number), bold: d.notable, color: d.notable ? _bad : _ink),
              _cell('${_pct(d.training.rate)}  (${d.training.attempts})', right: true),
              _cell('${_pct(d.online.rate)}  (${d.online.attempts})', right: true, bold: true),
              _cell(
                _signedPp(-d.drop!),
                right: true,
                bold: true,
                color: d.drop!.abs() < 0.02 ? _muted : (d.drop! > 0 ? _bad : _good),
              ),
            ]),
        ],
      ),
    ];
  }

  static String _signedPp(double v) {
    final n = (v.abs() * 100).round();
    return '${n == 0 ? '±' : (v > 0 ? '+' : '−')}$n Pp';
  }

  static List<pw.Widget> _distribution(OnlineStatsPdfInput i) {
    final c = i.compare;
    if (!c.scoring.ready) return const [];
    final on = OnlineComparison.bandTotal(c.onlineBands);
    final tr = OnlineComparison.bandTotal(c.trainingBands);
    double share(Map<ScoreBand, int> m, int total, ScoreBand b) => total == 0 ? 0 : (m[b] ?? 0) / total;
    String label(ScoreBand b) => b == ScoreBand.maximum ? '180' : (b == ScoreBand.under40 ? '< 40' : '${b.min}+');
    final l10n = i.l10n;
    return [
      _heading(l10n.onlineDistributionTitle),
      pw.Table(
        border: _rowBorder,
        columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1.4), 2: pw.FlexColumnWidth(1.4)},
        children: [
          _headRow(['', l10n.onlineCompareTraining, l10n.onlineCompareOnline]),
          for (final b in ScoreBand.values.reversed)
            pw.TableRow(children: [
              _cell(label(b)),
              _cell(_pct(share(c.trainingBands, tr, b)), right: true),
              _cell(_pct(share(c.onlineBands, on, b)), right: true, bold: true),
            ]),
        ],
      ),
    ];
  }

  // -- Matches ----------------------------------------------------------------

  static List<pw.Widget> _focus(AppLocalizations l10n, OnlineMatch m) {
    final minutes = m.duration.inMinutes;
    final facts = [
      if (m.opponent != null) l10n.histVs(m.opponent!),
      '${_date(m.startedAt)} ${_time(m.startedAt)}',
      if (m.hasLegs) l10n.onlineLegs(m.legsWon, m.legsLost),
      '${m.darts} ${l10n.statDarts}',
      if (minutes > 0) '$minutes min',
    ].join('  ·  ');
    return [
      pw.Text(facts, style: const pw.TextStyle(fontSize: 10, color: _muted)),
      pw.SizedBox(height: 8),
      pw.Wrap(spacing: 8, runSpacing: 8, children: [
        _tile(m.x01 ? l10n.onlineAverageShort : l10n.onlineAverageRaw, _dec(m.average)),
        if (m.first9 != null) _tile(l10n.statsFirst9, _dec(m.first9)),
        if (m.checkout.attempts > 0) _tile(l10n.statCheckoutRate, _pct(m.checkout.rate), caption: '${m.checkout.hits} / ${m.checkout.attempts}'),
        if (m.highestFinish > 0) _tile(l10n.onlineHighestFinish, '${m.highestFinish}'),
        _tile(l10n.onlineTons, '${m.tons} / ${m.count180}'),
      ]),
      if (m.legs.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Table(
          border: _rowBorder,
          columnWidths: const {
            0: pw.FlexColumnWidth(1.2),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(1),
            4: pw.FlexColumnWidth(1),
            5: pw.FlexColumnWidth(1),
          },
          children: [
            _headRow(['Leg', '', l10n.statDarts, 'Ø', l10n.statsFirst9, 'Finish']),
            for (final (k, leg) in m.legs.indexed)
              pw.TableRow(children: [
                _cell(l10n.onlineLegTitle(k + 1)),
                _cell(leg.won ? l10n.onlineLegWon : l10n.onlineLegLost, bold: true, color: leg.won ? _good : _bad),
                _cell('${leg.darts}', right: true),
                _cell(_dec(leg.average), right: true),
                _cell(_dec(leg.first9), right: true),
                _cell(leg.won && leg.checkout > 0 ? '${leg.checkout}' : '–', right: true),
              ]),
          ],
        ),
      ],
    ];
  }

  static pw.Widget _matchTable(OnlineStatsPdfInput i) {
    final l10n = i.l10n;
    return pw.Table(
      border: _rowBorder,
      columnWidths: const {
        0: pw.FlexColumnWidth(2.1),
        1: pw.FlexColumnWidth(1.9),
        2: pw.FlexColumnWidth(0.9),
        3: pw.FlexColumnWidth(0.9),
        4: pw.FlexColumnWidth(0.9),
        5: pw.FlexColumnWidth(1.1),
        6: pw.FlexColumnWidth(0.8),
        7: pw.FlexColumnWidth(0.8),
        8: pw.FlexColumnWidth(0.8),
        9: pw.FlexColumnWidth(0.9),
      },
      children: [
        _headRow(['Datum', 'Gegner', 'Legs', 'Ø', l10n.statsFirst9, l10n.statCheckoutRate, 'HF', '100+', '180', l10n.statDarts], firstLeft: 2),
        for (final m in i.report.matches)
          pw.TableRow(
            decoration: m.sessionId == i.focus?.sessionId ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEDE9FE)) : null,
            children: [
              _cell('${_date(m.startedAt)} ${_time(m.startedAt)}', size: 8),
              _cell(m.opponent ?? '–', size: 8),
              _cell(m.hasLegs ? '${m.legsWon}:${m.legsLost}' : '–', right: true, size: 8, bold: m.won == true, color: m.won == null ? _ink : (m.won! ? _good : _bad)),
              _cell(_dec(m.average), right: true, bold: true, size: 8),
              _cell(_dec(m.first9), right: true, size: 8),
              _cell(m.checkout.attempts > 0 ? _pct(m.checkout.rate) : '–', right: true, size: 8),
              _cell(m.highestFinish > 0 ? '${m.highestFinish}' : '–', right: true, size: 8),
              _cell('${m.tons}', right: true, size: 8),
              _cell('${m.count180}', right: true, size: 8),
              _cell('${m.darts}', right: true, size: 8),
            ],
          ),
      ],
    );
  }
}
