import 'package:flutter/material.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/presentation/game_texts.dart';
import '../domain/game_metrics.dart';

/// Wie eine Kennzahl und ihre Veränderung formatiert werden.
enum ValueKind {
  /// Ganze Zahl, Veränderung absolut (+120).
  count,

  /// Dezimalzahl, Veränderung mit einer Nachkommastelle (+2,3).
  decimal,

  /// Quote 0–1, Veränderung in Prozentpunkten (+4,1 Pp).
  percent,

  /// Minuten, Veränderung in Minuten oder Stunden.
  minutes,
}

String formatValue(ValueKind kind, double? v) {
  if (v == null) return '–';
  return switch (kind) {
    ValueKind.count => v.round().toString(),
    ValueKind.decimal => formatDecimal(v),
    ValueKind.percent => formatPercent(v),
    ValueKind.minutes => formatMinutes(v.round()),
  };
}

String formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  // Ab zehn Stunden reicht die volle Stunde, sonst wird die Kachel zu breit.
  return m == 0 || h >= 10 ? '$h h' : '$h h $m min';
}

String formatDate(DateTime d) => '${d.day}.${d.month}.${d.year}';
String formatDayMonth(DateTime d) => '${d.day}.${d.month}.';

/// Beschriftung einer Kennzahl aus `GameResult.metrics`. Ergänzt die
/// Spieltexte um Schlüssel, die nur in der Statistik auftauchen; unbekannte
/// Schlüssel erscheinen unverändert.
String metricLabel(AppLocalizations l10n, String key) => switch (key) {
      'score' => l10n.statPoints,
      'hits' => l10n.statHitsOnTarget,
      'bulls' => l10n.statBullHits,
      'outerBulls' => l10n.statOuterBullHits,
      'bestScore' => l10n.statsMetricBestScore,
      'marks' => l10n.statsMetricMarks,
      'reached' => l10n.statsMetricReached,
      'trebles' => l10n.statsMetricTrebles,
      'rounds' => l10n.statsMetricRounds,
      'attempts' => l10n.statsMetricAttempts,
      'endTarget' => l10n.statsMetricEndTarget,
      'first9' => l10n.statsFirst9,
      _ => l10n.statLabel(key),
    };

/// Formatiert eine beliebige Kennzahl eines Spiels anhand ihres Schlüssels.
String formatMetricKey(String gameId, String key, double? v) {
  if (v == null) return '–';
  final pm = PrimaryMetric.forGame(gameId);
  final format = key == pm.key
      ? pm.format
      : (key.endsWith('Rate') || key == 'progress')
          ? MetricFormat.percent
          : (v == v.roundToDouble() ? MetricFormat.integer : MetricFormat.decimal);
  return switch (format) {
    MetricFormat.percent => formatPercent(v),
    MetricFormat.integer => v.round().toString(),
    MetricFormat.decimal => v.toStringAsFixed(v.abs() < 10 ? 2 : 1).replaceAll('.', ','),
  };
}

/// Veränderung einer Kennzahl gegenüber dem Zeitraum davor.
class MetricDelta {
  const MetricDelta(this.current, this.previous, this.kind, {this.higherIsBetter = true});
  final double current;
  final double previous;
  final ValueKind kind;
  final bool higherIsBetter;

  double get diff => current - previous;

  /// Ist die Veränderung so klein, dass sie als gleich gilt?
  bool get flat => switch (kind) {
        ValueKind.percent => diff.abs() < 0.0005,
        ValueKind.decimal => diff.abs() < 0.05,
        _ => diff.abs() < 0.5,
      };

  bool get improved => !flat && (higherIsBetter ? diff > 0 : diff < 0);

  String get text {
    final sign = diff > 0 ? '+' : (diff < 0 ? '−' : '±');
    final a = diff.abs();
    return switch (kind) {
      ValueKind.count => '$sign${a.round()}',
      ValueKind.decimal => '$sign${formatDecimal(a)}',
      ValueKind.percent => '$sign${(a * 100).toStringAsFixed(1).replaceAll('.', ',')} Pp',
      ValueKind.minutes => '$sign${formatMinutes(a.round())}',
    };
  }

  /// Nur wenn beide Werte bekannt sind.
  static MetricDelta? of(double? current, double? previous, ValueKind kind, {bool higherIsBetter = true}) =>
      current == null || previous == null ? null : MetricDelta(current, previous, kind, higherIsBetter: higherIsBetter);
}

/// Kennzahl mit großer Zahl und optionaler Veränderung zum Vorzeitraum.
/// Gleicher Aufbau wie [StatTile], ergänzt um die Veränderung.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.caption, this.icon, this.delta});

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final MetricDelta? delta;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    if (d == null) return StatTile(label: label, value: value, caption: caption, icon: icon);
    final colors = context.dartColors;
    final look = context.look;
    final color = d.flat ? colors.textMuted : (d.improved ? colors.success : colors.danger);
    final arrow = d.flat
        ? Icons.trending_flat_rounded
        : (d.diff > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded);
    final deltaStyle = (look.id == DartLookId.tv ? look.kicker.copyWith(letterSpacing: 0.6) : Theme.of(context).textTheme.labelMedium)
        ?.copyWith(color: color);
    return StatTile(
      label: label,
      value: value,
      caption: caption,
      icon: icon,
      footer: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Tooltip(
          message: context.l10n.statsPrevious(formatValue(d.kind, d.previous)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s - 2, vertical: AppSpacing.xxs),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(look.id == DartLookId.clean ? 99 : look.radiusS),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(arrow, size: 13, color: color),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(child: Text(d.text, style: deltaStyle, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kacheln in einem Raster mit 2–4 Spalten, je nach Breite.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 200});
  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final gap = context.look.gridGap;
      final cols = (c.maxWidth / minTileWidth).floor().clamp(2, 4);
      final w = (c.maxWidth - (cols - 1) * gap) / cols;
      // Zeilenweise mit gleicher Höhe, damit Kacheln mit und ohne
      // Zusatztext bündig abschließen.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var r = 0; r < children.length; r += cols) ...[
            if (r > 0) SizedBox(height: gap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = r; i < r + cols && i < children.length; i++) ...[
                    if (i > r) SizedBox(width: gap),
                    SizedBox(width: w, child: children[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

/// Karte mit Überschrift, Inhalt und optionalem Hinweis darunter.
class ChartCard extends StatelessWidget {
  const ChartCard({super.key, required this.title, required this.child, this.hint, this.trailing});
  final String title;
  final Widget child;
  final String? hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title, trailing: trailing),
          child,
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(hint!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Zwei Karten nebeneinander (breit) oder untereinander (schmal).
class TwoColumns extends StatelessWidget {
  const TwoColumns({super.key, required this.wide, required this.left, required this.right});
  final bool wide;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final gap = context.look.sectionGap * 0.75;
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, SizedBox(height: gap), right],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          SizedBox(width: gap),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// Leerer Bereich innerhalb einer Karte.
class NoDataHint extends StatelessWidget {
  const NoDataHint({super.key, this.text, this.height = 120});
  final String? text;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          text ?? context.l10n.statsNoData,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

/// Legendeneintrag: farbiger Strich oder Punkt mit Text.
class LegendItem extends StatelessWidget {
  const LegendItem({super.key, required this.color, required this.label, this.line = false});
  final Color color;
  final String label;
  final bool line;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: line ? 16 : 8,
          height: line ? 3 : 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(context.look.barRadius.clamp(0, 4).toDouble()),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Waagerechter Balken mit Beschriftung links und Wert rechts.
class BarRow extends StatelessWidget {
  const BarRow({super.key, required this.label, required this.ratio, required this.value, this.color, this.detail});
  final String label;
  final double ratio;
  final String value;
  final String? detail;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.dartColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: theme.textTheme.labelMedium)),
          Expanded(
            child: LookProgressBar(
              value: ratio,
              height: context.look.barHeight + 4,
              color: color ?? colors.chartPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          SizedBox(
            width: 112,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: value, style: theme.textTheme.titleSmall),
                if (detail != null) TextSpan(text: '  $detail', style: theme.textTheme.bodySmall),
              ]),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
