import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../domain/stats_calculator.dart';
import '../../games/domain/engine/game_display.dart';
import 'double_insights.dart';
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
    return _BarChart(
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
    return _BarChart(
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
    return _BarChart(
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
          child: _LineChart(
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
  const DoublesGrid({super.key, required this.doubles, required this.overall, this.trends = const {}});
  final Map<int, HitCount> doubles;
  final double? overall;

  /// Verlauf je Doppel (Pfeil neben dem Namen), nur wo genug Versuche sind.
  final Map<int, TrendDirection> trends;

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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(n == 25 ? 'BULL' : 'D$n', style: theme.textTheme.labelMedium),
                        if (trends[n] case final d?)
                          Builder(builder: (context) {
                            final (icon, color) = trendStyle(context, d);
                            return Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: Icon(icon, key: Key('double-trend-$n'), size: 13, color: color),
                            );
                          }),
                      ],
                    ),
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

/// Ein Wert je Aufnahme einer Session (Spielverlauf): Säulen, z. B. Punkte
/// oder Treffer, oder eine Linie für einen Punktestand. `NaN` = kein Wert.
class VisitValuesChart extends StatelessWidget {
  const VisitValuesChart({
    super.key,
    required this.values,
    this.line = false,
    this.average,
    this.maxY,
    this.highlight = const {},
  });

  final List<double> values;
  final bool line;

  /// Gestrichelte Linie, z. B. der Schnitt je Aufnahme.
  final double? average;

  /// Feste Obergrenze (z. B. 3 Treffer), sonst aus den Werten.
  final double? maxY;

  /// Aufnahmen (Index), deren Säule grün ist, z. B. ein Checkout.
  final Set<int> highlight;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final base = colors.chartPrimary;
    final finite = [for (final v in values) if (v.isFinite) v];
    if (finite.isEmpty) return const NoDataHint(height: 180);
    final every = (values.length / 10).ceil().clamp(1, 1000);
    final bottom = AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: 1,
        getTitlesWidget: (v, meta) {
          final i = v.round();
          if (v != i || i < 0 || i >= values.length || i % every != 0) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.only(top: 4), child: Text('${i + 1}', style: _axis(context)));
        },
      ),
    );
    final left = AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 36,
        getTitlesWidget: (v, meta) => v == meta.max || v != v.roundToDouble()
            ? const SizedBox.shrink()
            : Text(v.round().toString(), style: _axis(context)),
      ),
    );
    final extra = average == null
        ? null
        : ExtraLinesData(horizontalLines: [
            HorizontalLine(y: average!, color: colors.chartSecondary, strokeWidth: 2, dashArray: const [6, 4]),
          ]);
    if (line) {
      final lo = math.min(0.0, finite.reduce(math.min));
      final hi = finite.reduce(math.max);
      final span = hi - lo == 0 ? 1.0 : hi - lo;
      return _LineChart(
        LineChartData(
          minY: lo == 0 ? 0 : lo - span * 0.1,
          maxY: hi + span * 0.12,
          minX: 0,
          maxX: math.max(1, values.length - 1).toDouble(),
          gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => _gridLine(context)),
          borderData: FlBorderData(show: false),
          extraLinesData: extra,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => _tooltipColor(context),
              getTooltipItems: (spots) => [
                for (final s in spots) LineTooltipItem('${s.x.round() + 1}: ${s.y.round()}', _tooltip(context)),
              ],
            ),
          ),
          titlesData: FlTitlesData(topTitles: const AxisTitles(), rightTitles: const AxisTitles(), bottomTitles: bottom, leftTitles: left),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final (i, v) in values.indexed)
                  if (v.isFinite) FlSpot(i.toDouble(), v),
              ],
              color: base,
              barWidth: 3,
              dotData: FlDotData(show: values.length <= 30),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [base.withValues(alpha: 0.18), base.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ],
        ),
      );
    }
    final double top = maxY ?? finite.fold<double>(0, math.max);
    return LayoutBuilder(builder: (context, c) {
      final barWidth = ((c.maxWidth - 40) / values.length * 0.62).clamp(2, 18).toDouble();
      return _BarChart(
        BarChartData(
          maxY: top == 0 ? 1 : (maxY ?? top * 1.12),
          gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => _gridLine(context)),
          borderData: FlBorderData(show: false),
          extraLinesData: extra,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => _tooltipColor(context),
              getTooltipItem: (group, _, rod, _) => BarTooltipItem('${group.x + 1}: ${rod.toY.round()}', _tooltip(context)),
            ),
          ),
          titlesData: FlTitlesData(topTitles: const AxisTitles(), rightTitles: const AxisTitles(), bottomTitles: bottom, leftTitles: left),
          barGroups: [
            for (final (i, v) in values.indexed)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: v.isFinite ? v : 0,
                  color: highlight.contains(i) ? colors.success : base,
                  width: barWidth,
                  borderRadius: _barRadius(context, barWidth),
                ),
              ]),
          ],
        ),
      );
    });
  }
}

/// Animationsdauer von fl_chart zwischen zwei Datenständen (Standard des
/// Pakets).
const Duration _chartSwap = Duration(milliseconds: 150);

/// Werte eines Diagramms, die fl_chart beim Wechsel animiert. fl_chart
/// selbst vergleicht die ganzen Daten samt Callbacks (Beschriftung,
/// Tooltips), die bei jedem `build` neu entstehen, und startet deshalb bei
/// jedem Neuaufbau eine Animation, auch wenn sich nichts geändert hat.
List<Object?> _gridAndTitles(FlGridData g, FlTitlesData t) => [
      g.show,
      g.drawHorizontalLine,
      g.horizontalInterval,
      g.drawVerticalLine,
      g.verticalInterval,
      t.show,
      for (final a in [t.leftTitles, t.topTitles, t.rightTitles, t.bottomTitles]) ...[
        a.axisNameSize,
        a.sideTitles.showTitles,
        a.sideTitles.reservedSize,
        a.sideTitles.interval,
      ],
    ];

List<Object?> _barValues(BarChartData d) => [
      d.minY,
      d.maxY,
      d.baselineY,
      d.groupsSpace,
      d.alignment,
      d.backgroundColor,
      d.borderData,
      d.extraLinesData,
      d.rangeAnnotations,
      ..._gridAndTitles(d.gridData, d.titlesData),
      d.barGroups.length,
      ...d.barGroups,
    ];

List<Object?> _lineValues(LineChartData d) => [
      d.minX,
      d.maxX,
      d.baselineX,
      d.minY,
      d.maxY,
      d.baselineY,
      d.backgroundColor,
      d.borderData,
      d.extraLinesData,
      d.rangeAnnotations,
      ..._gridAndTitles(d.gridData, d.titlesData),
      d.lineBarsData.length,
      ...d.lineBarsData,
      ...d.betweenBarsData,
    ];

/// Gleiche Werte; nicht gesetzte Grenzen sind bei fl_chart `NaN`.
bool _sameValues(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x != y && !(x is double && y is double && x.isNaN && y.isNaN)) return false;
  }
  return true;
}

/// Animiert wie fl_chart, aber nicht, wenn ein Neuaufbau dieselben Werte
/// zeigt (Dauer null statt einer Animation ohne sichtbare Änderung). Läuft
/// gerade eine Animation, bleibt alles wie bei fl_chart.
abstract class _ChartState<W extends StatefulWidget> extends State<W> {
  Duration duration = _chartSwap;
  final Stopwatch _sinceChange = Stopwatch();

  List<Object?> valuesOf(W widget);

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    final same = _sameValues(valuesOf(oldWidget), valuesOf(widget));
    if (!same) {
      _sinceChange
        ..reset()
        ..start();
    }
    final animating = _sinceChange.isRunning && _sinceChange.elapsed < _chartSwap;
    duration = same && !animating ? Duration.zero : _chartSwap;
  }
}

class _BarChart extends StatefulWidget {
  const _BarChart(this.data);
  final BarChartData data;

  @override
  State<_BarChart> createState() => _BarChartState();
}

class _BarChartState extends _ChartState<_BarChart> {
  @override
  List<Object?> valuesOf(_BarChart widget) => _barValues(widget.data);

  @override
  Widget build(BuildContext context) => BarChart(widget.data, duration: duration);
}

class _LineChart extends StatefulWidget {
  const _LineChart(this.data);
  final LineChartData data;

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends _ChartState<_LineChart> {
  @override
  List<Object?> valuesOf(_LineChart widget) => _lineValues(widget.data);

  @override
  Widget build(BuildContext context) => LineChart(widget.data, duration: duration);
}
