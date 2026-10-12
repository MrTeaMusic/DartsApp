import 'package:flutter/material.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../board/domain/segment.dart';
import '../../board/presentation/dartboard_view.dart';
import '../domain/double_stats.dart';
import '../domain/stats_models.dart';
import 'stats_widgets.dart';

/// Name eines Doppels in der Statistik.
String doubleName(int n) => n == 25 ? 'BULL' : 'D$n';

/// Quote als ganze Prozent, z. B. „41 %“ (geschütztes Leerzeichen, damit
/// das Prozentzeichen nicht allein in die nächste Zeile rutscht).
String wholePercent(double? rate) => rate == null ? '–' : '${(rate * 100).round()}\u00a0%';

/// Pfeil und Farbe eines Verlaufs.
(IconData, Color) trendStyle(BuildContext context, TrendDirection d) {
  final colors = context.dartColors;
  return switch (d) {
    TrendDirection.up => (Icons.arrow_upward_rounded, colors.success),
    TrendDirection.down => (Icons.arrow_downward_rounded, colors.danger),
    TrendDirection.flat => (Icons.trending_flat_rounded, colors.textMuted),
  };
}

/// „Doppel im Fokus“: Auswahl eines Doppels, Streubild im vergrößerten
/// Ausschnitt der Scheibe, Trefferquote mit Daneben-Richtung und Verlauf.
class DoubleFocusCard extends StatefulWidget {
  const DoubleFocusCard({super.key, required this.stats, required this.wide});
  final DoubleStats stats;
  final bool wide;

  @override
  State<DoubleFocusCard> createState() => _DoubleFocusCardState();
}

class _DoubleFocusCardState extends State<DoubleFocusCard> {
  int? _picked;

  /// Gewählter Chip in der seitlich scrollbaren Reihe (Telefon): wird beim
  /// ersten Anzeigen in die Mitte geholt.
  final _selectedChip = GlobalKey();
  int? _centeredFor;

  static final _numbers = [for (var n = 1; n <= 20; n++) n, 25];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stats = widget.stats;
    final picked = _picked;
    final number = picked != null && stats[picked] != null ? picked : stats.mostThrown;
    return ChartCard(
      key: const Key('stats-double-focus'),
      title: l10n.statsDoubleFocus,
      child: number == null
          ? const NoDataHint()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _chips(context, number),
                SizedBox(height: context.look.gridGap + AppSpacing.xs),
                _body(context, stats[number]!, stats.trends[number]),
              ],
            ),
    );
  }

  Widget _chips(BuildContext context, int selected) {
    if (!widget.wide && _centeredFor != selected) {
      _centeredFor = selected;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _selectedChip.currentContext;
        if (ctx == null || !ctx.mounted) return;
        // Nur die Chip-Reihe scrollen, nicht die ganze Seite.
        final box = ctx.findRenderObject();
        if (box != null) Scrollable.of(ctx).position.ensureVisible(box, alignment: 0.5);
      });
    }
    final chips = [
      for (final n in _numbers)
        KeyedSubtree(
          key: n == selected ? _selectedChip : null,
          child: ChoiceChip(
            key: Key('double-chip-$n'),
            label: Text(doubleName(n)),
            selected: n == selected,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            onSelected: widget.stats[n] == null ? null : (_) => setState(() => _picked = n),
          ),
        ),
    ];
    if (widget.wide) return Wrap(spacing: AppSpacing.xs + 2, runSpacing: AppSpacing.xs + 2, children: chips);
    return SingleChildScrollView(
      key: const Key('double-chips'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, c) in chips.indexed) ...[if (i > 0) const SizedBox(width: AppSpacing.xs + 2), c],
        ],
      ),
    );
  }

  Widget _body(BuildContext context, DoubleDetail d, DoubleTrend? trend) {
    final board = _Scatter(detail: d);
    final facts = _Facts(detail: d, trend: trend);
    if (!widget.wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          board,
          const SizedBox(height: AppSpacing.l),
          facts,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 11, child: board),
        SizedBox(width: context.look.sectionGap),
        Expanded(flex: 9, child: facts),
      ],
    );
  }
}

/// Streubild: vergrößerter Ausschnitt rund um das Doppel mit allen Darts,
/// die eine Position haben.
class _Scatter extends StatelessWidget {
  const _Scatter({required this.detail});
  final DoubleDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final look = context.look;
    final colors = context.dartColors;
    final theme = Theme.of(context);
    final n = detail.number;
    final points = [for (final a in detail.scatter) ScatterMarker(a.position!, hit: a.hit)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(look.radiusM),
          child: ColoredBox(
            color: colors.boardSurround,
            child: Stack(
              children: [
                DartboardView(
                  key: const Key('double-scatter'),
                  semanticsLabel: l10n.statsDoubleFocus,
                  focus: n == 25 ? Segment.bull : Segment.double(n),
                  focusWidth: n == 25 ? 0.6 : 0.9,
                  aspectRatio: 1.55,
                  scatter: points,
                ),
                if (points.isEmpty)
                  Positioned.fill(
                    child: Container(
                      color: colors.boardSurround.withValues(alpha: 0.72),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(AppSpacing.l),
                      child: Text(
                        l10n.statsDoubleNoPositions,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Wrap(
          spacing: AppSpacing.m,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            LegendItem(color: colors.success, label: l10n.statsDoubleHits),
            LegendItem(color: const Color(0xFFB4B9C0), label: l10n.statsDoubleMissed),
            Text(
              l10n.statsDoubleScatterHint(points.length, detail.count.attempts),
              key: const Key('double-scatter-hint'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

/// Quote, Daneben-Richtung und Verlauf des gewählten Doppels.
class _Facts extends StatelessWidget {
  const _Facts({required this.detail, required this.trend});
  final DoubleDetail detail;
  final DoubleTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final d = detail;
    final bull = d.number == 25;
    String dir(DoubleMiss m) => switch (m) {
      DoubleMiss.outside => l10n.statsDoubleDirOutside,
      DoubleMiss.inside => bull ? l10n.statsBullDirInside : l10n.statsDoubleDirInside,
      DoubleMiss.side => bull ? l10n.statsBullDirSide : l10n.statsDoubleDirSide,
    };
    String label(DoubleMiss m) => switch (m) {
      DoubleMiss.outside => l10n.statsDoubleOutside,
      DoubleMiss.inside => bull ? l10n.statsBullInside : l10n.statsDoubleInside,
      DoubleMiss.side => bull ? l10n.statsBullSide : l10n.statsDoubleSide,
    };
    final main = d.mainMiss;
    final summary = main == null
        ? l10n.statsDoubleSummaryNoMiss(doubleName(d.number), wholePercent(d.count.rate))
        : l10n.statsDoubleSummary(
            doubleName(d.number),
            wholePercent(d.count.rate),
            dir(main),
            wholePercent(d.share(main)),
          );
    final order = bull
        ? const [DoubleMiss.inside, DoubleMiss.side, DoubleMiss.outside]
        : const [DoubleMiss.outside, DoubleMiss.inside, DoubleMiss.side];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(summary, key: const Key('double-summary'), style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.s),
        BarRow(
          label: l10n.statsDoubleHits,
          ratio: d.count.rate ?? 0,
          value: wholePercent(d.count.rate),
          detail: '${d.count.hits}/${d.count.attempts}',
          color: colors.success,
        ),
        for (final m in order)
          BarRow(
            key: Key('double-miss-${m.name}'),
            label: label(m),
            ratio: d.share(m),
            value: wholePercent(d.share(m)),
            detail: '${d.missesOf(m)}',
            color: m == main ? colors.warning : colors.textMuted,
          ),
        const SizedBox(height: AppSpacing.xs),
        Text(bull ? l10n.statsBullMissLegend : l10n.statsDoubleMissLegend, style: theme.textTheme.bodySmall),
        SizedBox(height: look.gridGap + AppSpacing.xs),
        Kicker(l10n.statsDoubleTrend),
        const SizedBox(height: AppSpacing.xs),
        _TrendLine(trend: trend),
      ],
    );
  }
}

class _TrendLine extends StatelessWidget {
  const _TrendLine({required this.trend});
  final DoubleTrend? trend;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = trend;
    final dir = t?.direction;
    if (t == null || dir == null) {
      return Text(
        l10n.statsDoubleTrendTooFew(DoubleStats.trendMinAttempts),
        key: const Key('double-trend'),
        style: theme.textTheme.bodySmall,
      );
    }
    final (icon, color) = trendStyle(context, dir);
    String part(HitCount h) => '${wholePercent(h.rate)} (${h.hits}/${h.attempts})';
    return Row(
      key: const Key('double-trend'),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xxs + 1),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(l10n.statsDoubleTrendValue(part(t.recent), part(t.before)), style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

/// Zwei Zahlen nebeneinander: Doppel-Quote im Checkout und im Training.
class CheckoutVsTrainingCard extends StatelessWidget {
  const CheckoutVsTrainingCard({super.key, required this.stats});
  final DoubleStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final co = stats.checkout;
    final tr = stats.training;
    String? verdict;
    if (co.rate != null && tr.rate != null) {
      final diff = co.rate! - tr.rate!;
      final pp = (diff.abs() * 100).round();
      verdict = pp == 0
          ? l10n.statsCheckoutSame
          : (diff > 0 ? l10n.statsCheckoutBetter(pp) : l10n.statsCheckoutWorse(pp));
    }
    return ChartCard(
      key: const Key('stats-checkout-vs-training'),
      title: l10n.statsCheckoutVsTraining,
      hint: l10n.statsCheckoutVsTrainingHint,
      child: co.attempts == 0 && tr.attempts == 0
          ? const NoDataHint(height: 96)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _BigRate(
                        key: const Key('double-rate-checkout'),
                        label: l10n.statsCheckoutDarts,
                        count: co,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.l),
                    Expanded(
                      child: _BigRate(
                        key: const Key('double-rate-training'),
                        label: l10n.statsTrainingDarts,
                        count: tr,
                      ),
                    ),
                  ],
                ),
                if (verdict != null) ...[
                  const SizedBox(height: AppSpacing.m),
                  Text(verdict, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
    );
  }
}

class _BigRate extends StatelessWidget {
  const _BigRate({super.key, required this.label, required this.count});
  final String label;
  final HitCount count;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Kicker(label),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(wholePercent(count.rate), style: look.statValue.copyWith(color: theme.colorScheme.onSurface)),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(context.l10n.statsDoubleDarts(count.hits, count.attempts), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Tipp: aufs beste Doppel stellen.
class DoubleTipCard extends StatelessWidget {
  const DoubleTipCard({super.key, required this.stats, required this.minAttempts});
  final DoubleStats stats;
  final int minAttempts;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final best = stats.bestFor(minAttempts);
    return ChartCard(
      key: const Key('stats-double-tip'),
      title: l10n.statsDoubleTipTitle,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.s),
            decoration: BoxDecoration(
              color: colors.highlight.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(context.look.radiusM),
            ),
            child: Icon(Icons.lightbulb_outline_rounded, color: colors.highlight, size: 22),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text(
              best == null
                  ? l10n.statsDoubleTipTooFew(minAttempts)
                  : l10n.statsDoubleTip(doubleName(best.number), wholePercent(best.count.rate)),
              key: const Key('double-tip'),
              style: best == null
                  ? theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted)
                  : theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}
