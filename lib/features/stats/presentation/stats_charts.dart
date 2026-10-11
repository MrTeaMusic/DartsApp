import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../domain/stats_calculator.dart';
import '../../games/domain/engine/game_display.dart';
import 'stats_widgets.dart';

TextStyle? _axis(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall
    ?.copyWith(fontSize: 11, color: context.dartColors.textMuted, fontFeatures: DartLooks.tabular);

TextStyle _tooltip(BuildContext context) =>
    (Theme.of(context).textTheme.titleSmall ?? const TextStyle()).copyWith(fontSize: 12, height: 1.35);

/// Rasterlinien aller Diagramme.
FlLine _gridLine(BuildContext context) => FlLine(color: context.dartColors.chartGrid, strokeWidth: 1);

/// Hintergrund der Tooltips.
Color _tooltipColor(BuildContext context) => context.dartColors.surfaceHigh;

/// Radius der Säulen je Look (TV eckig, Clean rund, Lab fein).
BorderRadius _barRadius(BuildContext context, double width) {
  final r = context.look.barRadius.clamp(0, width / 2).toDouble();
  return BorderRadius.vertical(top: Radius.circular(r));
}

/// Säulen mit Beschriftung darunter, z. B. Darts pro Tag oder Woche.
class VolumeChart extends StatelessWidget {
  const VolumeChart({super.key, required this.labels, required this.values, this.color, this.highlightLast = false});
  final List<String> labels;
  final List<double> values;
  final Color? color;

  /// Letzte Säule (laufender Tag / laufende Woche) hervorheben.
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    final base = color ?? context.dartColors.chartPrimary;
    final maxY = values.fold(0.0, math.max);
    final barWidth = (260 / values.length).clamp(3, 22).toDouble();
    // Bei vielen Säulen nur jede n-te Beschriftung, von rechts gezählt.
    final every = (values.length / 8).ceil().clamp(1, 1000);
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.15,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => _gridLine(context),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _tooltipColor(context),
            getTooltipItem: (group, _, rod, _) =>
                BarTooltipItem('${labels[group.x]}\n${rod.toY.round()}', _tooltip(context)),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, meta) =>
                  v == meta.max ? const SizedBox.shrink() : Text(v.round().toString(), style: _axis(context)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= labels.length || (labels.length - 1 - i) % every != 0) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 4), child: Text(labels[i], style: _axis(context)));
              },
            ),
          ),
        ),
        barGroups: [
          for (final (i, v) in values.indexed)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: v,
                color: highlightLast && i < values.length - 1 ? base.withValues(alpha: 0.7) : base,
                width: barWidth,
                borderRadius: _barRadius(context, barWidth),
              ),
            ]),
        ],
      ),
    );
  }
}

/// Treffer je Zahl 1–20 und Bull.
class NumberHitsChart extends StatelessWidget {
  const NumberHitsChart({super.key, required this.hits});
  final Map<int, int> hits;

  @override
  Widget build(BuildContext context) {
    final color = context.dartColors.chartPrimary;
    final numbers = [for (var n = 1; n <= 20; n++) n, 25];
    final maxY = numbers.fold(0, (a, n) => math.max(a, hits[n] ?? 0)).toDouble();
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.15,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _tooltipColor(context),
            getTooltipItem: (group, _, rod, _) => BarTooltipItem('${rod.toY.round()}', _tooltip(context)),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= numbers.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(numbers[i] == 25 ? 'B' : '${numbers[i]}', style: _axis(context)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (final (i, n) in numbers.indexed)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: (hits[n] ?? 0).toDouble(),
                color: n == 25 ? context.dartColors.boardRed : color,
                width: 10,
                borderRadius: _barRadius(context, 10),
              ),
            ]),
        ],
      ),
    );
  }
}

/// Quote je Zahl (z. B. Triples), nur Zahlen mit Versuchen.
class RatePerNumberChart extends StatelessWidget {
  const RatePerNumberChart({super.key, required this.counts, this.color, this.minAttempts = 1});
  final Map<int, HitCount> counts;
  final Color? color;

  /// Zahlen mit weniger Versuchen fehlen (ein einzelner Treffer wären 100 %).
  final int minAttempts;

  @override
  Widget build(BuildContext context) {
    // Triples behalten ihre Farbe (lila) in allen Looks.
    final base = color ?? context.dartColors.tripleHit;
    final barWidth = (220 / math.max(1, counts.length)).clamp(6, 22).toDouble();
    final numbers = counts.keys.where((n) => counts[n]!.attempts >= minAttempts).toList()..sort();
    return BarChart(
      BarChartData(
        maxY: 100,
        minY: 0,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => _gridLine(context),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _tooltipColor(context),
            getTooltipItem: (group, _, rod, _) {
              final c = counts[numbers[group.x]]!;
              return BarTooltipItem('${formatPercent(c.rate)}\n${c.hits}/${c.attempts}', _tooltip(context));
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: 25,
              getTitlesWidget: (v, meta) => Text('${v.round()} %', style: _axis(context)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= numbers.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(numbers[i] == 25 ? 'B' : '${numbers[i]}', style: _axis(context)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (final (i, n) in numbers.indexed)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: (counts[n]!.rate ?? 0) * 100,
                color: base,
                width: barWidth,
                borderRadius: _barRadius(context, barWidth),
              ),
            ]),
        ],
      ),
    );
  }
}

/// Verlauf mit gleitendem Durchschnitt.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.points,
    required this.format,
    this.percent = false,
    this.emptyText,
  });

  final List<TrendPoint> points;

  /// Formatiert einen Wert für den Tooltip.
  final String Function(double v) format;

  /// Werte sind Quoten (0–1) und werden in Prozent gezeichnet.
  final bool percent;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (points.isEmpty) return NoDataHint(text: emptyText ?? l10n.statsTrendEmpty, height: 200);
    final color = context.dartColors.chartPrimary;
    final maColor = context.dartColors.chartSecondary;
    final values = [for (final p in points) percent ? p.value * 100 : p.value];
    final ma = StatsCalculator.movingAverage(values);
    final showMa = values.length >= 3;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = hi - lo == 0 ? (hi == 0 ? 1 : hi.abs() * 0.2) : hi - lo;
    final every = (points.length / 5).ceil().clamp(1, 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: lo - span * 0.15,
              maxY: hi + span * 0.15,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => _gridLine(context),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => _tooltipColor(context),
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        s.barIndex == 0
                            ? '${formatDayMonth(points[s.x.round()].time)}  ${format(points[s.x.round()].value)}'
                            : 'Ø ${format(percent ? s.y / 100 : s.y)}',
                        _tooltip(context).copyWith(color: s.barIndex == 0 ? null : maColor),
                      ),
                  ],
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (v != i || i < 0 || i >= points.length || (points.length - 1 - i) % every != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(formatDayMonth(points[i].time), style: _axis(context)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, meta) => v == meta.max || v == meta.min
                        ? const SizedBox.shrink()
                        : Text(v.toStringAsFixed(span < 5 ? 1 : 0).replaceAll('.', ','), style: _axis(context)),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (final (i, v) in values.indexed) FlSpot(i.toDouble(), v)],
                  isCurved: false,
                  color: color.withValues(alpha: showMa ? 0.55 : 1),
                  barWidth: showMa ? 2 : 3,
                  dotData: FlDotData(show: points.length <= 40),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.0)],
                    ),
                  ),
                ),
                if (showMa)
                  LineChartBarData(
                    spots: [for (final (i, v) in ma.indexed) FlSpot(i.toDouble(), v)],
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: maColor,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Wrap(
          spacing: AppSpacing.l,
          runSpacing: AppSpacing.xs,
          children: [
            LegendItem(color: color, label: l10n.statsLegendValue),
            if (showMa) LegendItem(color: maColor, label: l10n.statsMovingAverage(StatsCalculator.movingWindow), line: true),
          ],
        ),
      ],
    );
  }
}

/// Raster aller Doubles mit Quote; die Farbe zeigt stark (grün) oder
/// schwach (rot) im Vergleich zur eigenen Gesamtquote.
class DoublesGrid extends StatelessWidget {
  const DoublesGrid({super.key, required this.doubles, required this.overall});
  final Map<int, HitCount> doubles;
  final double? overall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final numbers = [for (var n = 1; n <= 20; n++) n, 25];
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 76).floor().clamp(3, 7);
      final w = (c.maxWidth - (cols - 1) * AppSpacing.s) / cols;
      return Wrap(
        spacing: AppSpacing.s,
        runSpacing: AppSpacing.s,
        children: [
          for (final n in numbers)
            Builder(builder: (context) {
              final h = doubles[n] ?? HitCount.zero;
              final rate = h.rate;
              final Color tint;
              if (rate == null) {
                tint = colors.textMuted;
              } else if (overall == null || h.attempts < 3) {
                tint = theme.colorScheme.primary;
              } else {
                tint = rate >= overall! * 1.15
                    ? colors.success
                    : (rate <= overall! * 0.85 ? colors.danger : colors.warning);
              }
              return Container(
                key: Key('double-$n'),
                width: w,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s, horizontal: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: rate == null ? 0.06 : 0.14),
                  borderRadius: BorderRadius.circular(context.look.radiusS),
                  border: Border.all(color: tint.withValues(alpha: rate == null ? 0.2 : 0.5)),
                ),
                child: Column(
                  children: [
                    Text(n == 25 ? 'BULL' : 'D$n', style: theme.textTheme.labelMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      rate == null ? '–' : '${(rate * 100).round()} %',
                      style: theme.textTheme.titleMedium?.copyWith(color: rate == null ? colors.textMuted : tint),
                    ),
                    Text(h.attempts == 0 ? ' ' : '${h.hits}/${h.attempts}', style: theme.textTheme.bodySmall),
                  ],
                ),
              );
            }),
        ],
      );
    });
  }
}
