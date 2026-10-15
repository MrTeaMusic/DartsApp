import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../autodarts_live/presentation/autodarts_live_routes.dart';
import '../../games/domain/engine/game_display.dart';
import '../../history/presentation/history_screen.dart';
import '../../plans/presentation/plan_routes.dart';
import '../domain/stats_calculator.dart';
import 'double_insights.dart';
import 'stats_charts.dart';
import 'stats_screen.dart';
import 'stats_widgets.dart';

/// Gewählte Kennzahl im Verlauf der Online-Matches.
final onlineTrendMetricProvider =
    NotifierProvider<_TrendMetricNotifier, OnlineTrendMetric>(_TrendMetricNotifier.new);

class _TrendMetricNotifier extends Notifier<OnlineTrendMetric> {
  @override
  OnlineTrendMetric build() => OnlineTrendMetric.average;
  void set(OnlineTrendMetric m) => state = m;
}

const _gap = SectionGap(factor: 0.8);

/// Reiter „Online“: Matches aus Autodarts Live, Verlauf und der Vergleich
/// Training gegen Match. Alle Zahlen kommen fertig aus dem
/// [StatsCalculator] (je Zeitraum zwischengespeichert).
class OnlineTab extends StatelessWidget {
  const OnlineTab({super.key, required this.view, required this.wide, required this.pad});
  final StatsView view;
  final bool wide;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final report = view.calc.onlineReport(view.period);
    final compare = view.calc.onlineComparison(view.period);
    final t = report.totals;
    return ListView(
      key: const Key('stats-list-online'),
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.m, pad, AppSpacing.xxl),
      children: [
        if (report.isEmpty)
          ComingSoon(
            key: const Key('online-empty'),
            icon: Icons.public_rounded,
            title: l10n.onlineEmptyTitle,
            text: l10n.onlineEmptyText,
            action: FilledButton.icon(
              key: const Key('online-open-live'),
              onPressed: () => context.go(AutodartsLiveRoutes.live),
              icon: const Icon(Icons.sensors_rounded),
              label: Text(l10n.onlineOpenLive),
            ),
          )
        else ...[
          TileGrid(children: [
            StatTile(
              key: const Key('online-matches'),
              label: l10n.onlineMatches,
              value: '${t.matches}',
              caption: l10n.onlineMatchesCaption(t.darts, t.legs == 0 ? l10n.onlineNoLegs : l10n.onlineLegs(t.legsWon, t.legsLost)),
              icon: Icons.public_rounded,
            ),
            StatTile(
              key: const Key('online-average'),
              label: l10n.statAverage,
              value: formatDecimal(t.average),
              caption: l10n.onlineAverageCaption,
              icon: Icons.speed_rounded,
            ),
            if (t.first9 != null)
              StatTile(
                label: l10n.statsFirst9,
                value: formatDecimal(t.first9),
                caption: l10n.onlineFirst9Caption,
                icon: Icons.looks_one_rounded,
              ),
            if (t.checkout.attempts > 0)
              StatTile(
                key: const Key('online-checkout'),
                label: l10n.statCheckoutRate,
                value: formatPercent(t.checkoutRate),
                caption: l10n.onlineCheckoutCaption(t.checkout.hits, t.checkout.attempts),
                icon: Icons.flag_rounded,
              ),
            if (t.highestFinish > 0)
              StatTile(label: l10n.onlineHighestFinish, value: '${t.highestFinish}', icon: Icons.emoji_events_rounded),
            StatTile(
              label: l10n.onlineTons,
              value: '${t.tons} / ${t.maxes}',
              caption: l10n.onlineTonsCaption,
              icon: Icons.star_rounded,
            ),
          ]),
          _gap,
          TwoColumns(
            wide: wide,
            left: _TrendCard(report: report),
            right: compare.ready ? _CompareCard(compare: compare) : _CompareEmpty(compare: compare),
          ),
          if (compare.ready) ...[
            _gap,
            TwoColumns(
              wide: wide,
              left: _DoublesCompareCard(compare: compare),
              right: _DistributionCard(compare: compare),
            ),
          ],
          _gap,
          SectionHeader(l10n.onlineMatchList),
          AppCard(
            key: const Key('online-match-list'),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (final (i, m) in report.matches.indexed) ...[
                  if (i > 0) Divider(indent: context.look.cardPadding, endIndent: context.look.cardPadding),
                  _MatchTile(key: Key('online-match-${m.sessionId}'), match: m),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Verlauf
// ---------------------------------------------------------------------------

class _TrendCard extends ConsumerWidget {
  const _TrendCard({required this.report});
  final OnlineReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final metric = ref.watch(onlineTrendMetricProvider);
    final percent = metric == OnlineTrendMetric.checkoutRate;
    String label(OnlineTrendMetric m) => switch (m) {
          OnlineTrendMetric.average => l10n.statAverage,
          OnlineTrendMetric.first9 => l10n.statsFirst9,
          OnlineTrendMetric.checkoutRate => l10n.statCheckoutRate,
        };
    return ChartCard(
      key: const Key('online-trend'),
      title: report.byWeek ? l10n.onlineTrendWeekly : l10n.onlineTrendPerMatch,
      hint: report.byWeek ? null : l10n.onlineTrendPerMatchHint(OnlineReport.minWeeks),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              for (final m in OnlineTrendMetric.values)
                ChoiceChip(
                  key: Key('online-trend-${m.name}'),
                  label: Text(label(m)),
                  selected: m == metric,
                  onSelected: (_) => ref.read(onlineTrendMetricProvider.notifier).set(m),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),
          TrendLineChart(
            points: report.trend(metric),
            format: percent ? formatPercent : formatDecimal,
            percent: percent,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Training gegen Match
// ---------------------------------------------------------------------------

String _metricLabel(AppLocalizations l10n, CompareMetric m) => switch (m) {
      CompareMetric.average => l10n.statAverage,
      CompareMetric.first9 => l10n.statsFirst9,
      CompareMetric.checkoutRate => l10n.statCheckoutRate,
      CompareMetric.doubleRate => l10n.statDoubleRate,
      CompareMetric.scoring => l10n.statsTons,
    };

String _unit(AppLocalizations l10n, CompareMetric m) => switch (m) {
      CompareMetric.average => l10n.onlineUnitDarts,
      CompareMetric.first9 => l10n.onlineUnitLegs,
      CompareMetric.checkoutRate => l10n.onlineUnitFinishDarts,
      CompareMetric.doubleRate => l10n.onlineUnitDoubleDarts,
      CompareMetric.scoring => l10n.onlineUnitVisits,
    };

bool _isRate(CompareMetric m) => m != CompareMetric.average && m != CompareMetric.first9;

String _value(CompareMetric m, double? v) => _isRate(m) ? wholePercent(v) : formatDecimal(v);

/// Unterschied online minus Training: Punkte bzw. Prozentpunkte.
String _diffText(double diff, {required bool rate}) {
  final text = rate ? '${(diff.abs() * 100).round()} Pp' : formatDecimal(diff.abs());
  // Gerundet null: kein Vorzeichen-Rauschen („−0 Pp“).
  final zero = rate ? (diff.abs() * 100).round() == 0 : formatDecimal(diff.abs()) == '0,0';
  final sign = zero ? '±' : (diff > 0 ? '+' : '−');
  return '$sign$text';
}

/// Farbe eines Unterschieds; kleine Unterschiede bleiben grau.
Color _diffColor(BuildContext context, double diff, {required bool rate}) {
  final colors = context.dartColors;
  final flat = rate ? diff.abs() < 0.02 : diff.abs() < 1;
  if (flat) return colors.textMuted;
  return diff < 0 ? colors.danger : colors.success;
}

class _DiffPill extends StatelessWidget {
  const _DiffPill({required this.diff, required this.rate});
  final double diff;
  final bool rate;

  @override
  Widget build(BuildContext context) {
    final color = _diffColor(context, diff, rate: rate);
    final look = context.look;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s - 2, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(look.id == DartLookId.clean ? 99 : look.radiusS),
      ),
      child: Text(
        _diffText(diff, rate: rate),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontFeatures: DartLooks.tabular),
        maxLines: 1,
      ),
    );
  }
}

/// Spaltenbreiten der Vergleichstabelle.
const double _valueWidth = 62;
const double _diffWidth = 64;

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.compare});
  final OnlineComparison compare;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final notable = [
      for (final d in compare.notableDrops) doubleName(d.number),
      if (compare.doublesNotable) l10n.statDoubleRate,
      if (compare.first9Notable) l10n.statsFirst9,
    ];
    Widget head(String text) => SizedBox(
          width: _valueWidth,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(fit: BoxFit.scaleDown, child: Kicker(text)),
          ),
        );
    return AppCard(
      key: const Key('online-compare'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(l10n.onlineCompareTitle),
          Row(
            children: [
              const Spacer(),
              head(l10n.onlineCompareTraining),
              head(l10n.onlineCompareOnline),
              const SizedBox(width: _diffWidth, child: Align(alignment: Alignment.centerRight, child: Kicker('±'))),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final m in compare.metrics) ...[
            const Divider(height: AppSpacing.l),
            _CompareRow(key: Key('online-compare-${m.metric.name}'), comparison: m),
          ],
          const Divider(height: AppSpacing.l),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  notable.isEmpty ? Icons.check_circle_outline_rounded : Icons.auto_awesome_rounded,
                  size: 16,
                  color: notable.isEmpty ? context.dartColors.success : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  notable.isEmpty ? l10n.onlineNotableNone : l10n.onlineNotable(notable.join(', ')),
                  key: const Key('online-notable'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (notable.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('online-auto-plan'),
                onPressed: () => context.go(PlanRoutes.auto),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(l10n.autoPlanHintAction),
              ),
            )
          else
            const SizedBox(height: AppSpacing.s),
          Text(l10n.onlineCompareHint, style: theme.textTheme.bodySmall?.copyWith(color: context.dartColors.textMuted)),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({super.key, required this.comparison});
  final MetricComparison comparison;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final c = comparison;
    final rate = _isRate(c.metric);
    final diff = c.diff;
    Widget value(CompareSide side, bool ready) => SizedBox(
          width: _valueWidth,
          child: Text(
            _value(c.metric, side.value),
            textAlign: TextAlign.right,
            style: theme.textTheme.titleSmall?.copyWith(
              color: ready ? theme.colorScheme.onSurface : colors.textMuted,
              fontFeatures: DartLooks.tabular,
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(_metricLabel(l10n, c.metric), style: theme.textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            value(c.training, c.trainingReady),
            value(c.online, c.onlineReady),
            SizedBox(
              width: _diffWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: diff == null
                    ? Text('–', style: theme.textTheme.titleSmall?.copyWith(color: colors.textMuted))
                    : _DiffPill(diff: diff, rate: rate),
              ),
            ),
          ],
        ),
        if (!c.ready) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.onlineCompareMissing(c.online.amount, c.training.amount, c.minimum, _unit(l10n, c.metric)),
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ],
      ],
    );
  }
}

class _CompareEmpty extends StatelessWidget {
  const _CompareEmpty({required this.compare});
  final OnlineComparison compare;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    return AppCard(
      key: const Key('online-compare-empty'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(l10n.onlineCompareTitle),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: Icons.compare_arrows_rounded, color: colors.warning),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.onlineCompareEmptyTitle, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(l10n.onlineCompareEmptyText, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          for (final m in compare.metrics)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${_metricLabel(l10n, m.metric)}: ', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  TextSpan(
                    text: l10n.onlineCompareAmounts(m.online.amount, m.training.amount, m.minimum, _unit(l10n, m.metric)),
                    style: theme.textTheme.bodySmall,
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Zwei Balken (Training, online) mit Werten rechts.
class _PairRow extends StatelessWidget {
  const _PairRow({
    super.key,
    required this.label,
    required this.training,
    required this.online,
    required this.trainingText,
    required this.onlineText,
    this.trailing,
    this.alert = false,
  });

  final String label;

  /// Balkenlängen 0–1.
  final double training;
  final double online;
  final String trainingText;
  final String onlineText;
  final Widget? trailing;

  /// Beschriftung rot (online deutlich schwächer).
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final barHeight = context.look.barHeight;
    final small = theme.textTheme.bodySmall?.copyWith(fontFeatures: DartLooks.tabular);
    Widget bar(double v, Color c, String text) => Row(
          children: [
            Expanded(child: LookProgressBar(value: v.clamp(0, 1), height: barHeight, color: c)),
            SizedBox(width: 44, child: Text(text, textAlign: TextAlign.right, style: small, maxLines: 1)),
          ],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 1),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(label, style: theme.textTheme.labelLarge?.copyWith(color: alert ? colors.danger : null)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bar(training, colors.chartSecondary, trainingText),
                const SizedBox(height: 3),
                bar(online, colors.chartPrimary, onlineText),
              ],
            ),
          ),
          if (trailing != null) SizedBox(width: _diffWidth, child: Align(alignment: Alignment.centerRight, child: trailing)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Wrap(
        spacing: AppSpacing.l,
        children: [
          LegendItem(color: colors.chartSecondary, label: l10n.onlineCompareTraining),
          LegendItem(color: colors.chartPrimary, label: l10n.onlineCompareOnline),
        ],
      ),
    );
  }
}

class _DoublesCompareCard extends StatelessWidget {
  const _DoublesCompareCard({required this.compare});
  final OnlineComparison compare;

  /// Höchstens so viele Doppel (die mit dem größten Einbruch).
  static const int maxRows = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ranked = compare.ranked.take(maxRows).toList();
    final top = ranked.fold(0.0, (m, d) {
      final r = d.training.rate! > d.online.rate! ? d.training.rate! : d.online.rate!;
      return r > m ? r : m;
    });
    return ChartCard(
      key: const Key('online-doubles'),
      title: l10n.onlineDoublesTitle,
      hint: l10n.onlineDoublesHint(OnlineComparison.minDoubleAttempts, (OnlineComparison.notableDrop * 100).round()),
      child: ranked.isEmpty
          ? NoDataHint(text: l10n.onlineDoublesEmpty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Legend(),
                for (final d in ranked)
                  _PairRow(
                    key: Key('online-double-${d.number}'),
                    label: doubleName(d.number),
                    training: top == 0 ? 0 : d.training.rate! / top,
                    online: top == 0 ? 0 : d.online.rate! / top,
                    trainingText: wholePercent(d.training.rate),
                    onlineText: wholePercent(d.online.rate),
                    alert: d.notable,
                    trailing: _DiffPill(diff: -d.drop!, rate: true),
                  ),
              ],
            ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.compare});
  final OnlineComparison compare;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final on = OnlineComparison.bandTotal(compare.onlineBands);
    final tr = OnlineComparison.bandTotal(compare.trainingBands);
    final ready = compare.scoring.ready;
    double share(Map<ScoreBand, int> m, int total, ScoreBand b) => total == 0 ? 0 : (m[b] ?? 0) / total;
    final top = [
      for (final b in ScoreBand.values) ...[share(compare.onlineBands, on, b), share(compare.trainingBands, tr, b)],
    ].fold(0.0, (a, b) => b > a ? b : a);
    String label(ScoreBand b) => b == ScoreBand.maximum ? '180' : (b == ScoreBand.under40 ? '< 40' : '${b.min}+');
    return ChartCard(
      key: const Key('online-distribution'),
      title: l10n.onlineDistributionTitle,
      hint: l10n.onlineDistributionHint(on, tr),
      child: !ready
          ? NoDataHint(
              text: l10n.onlineCompareMissing(on, tr, compare.scoring.minimum, l10n.onlineUnitVisits),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Legend(),
                for (final b in ScoreBand.values.reversed)
                  _PairRow(
                    label: label(b),
                    training: top == 0 ? 0 : share(compare.trainingBands, tr, b) / top,
                    online: top == 0 ? 0 : share(compare.onlineBands, on, b) / top,
                    trainingText: wholePercent(share(compare.trainingBands, tr, b)),
                    onlineText: wholePercent(share(compare.onlineBands, on, b)),
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Matches
// ---------------------------------------------------------------------------

class _MatchTile extends StatefulWidget {
  const _MatchTile({super.key, required this.match});
  final OnlineMatch match;

  @override
  State<_MatchTile> createState() => _MatchTileState();
}

class _MatchTileState extends State<_MatchTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final m = widget.match;
    final minutes = m.duration.inMinutes;
    final subtitle = [
      historyTime(m.startedAt),
      if (m.hasLegs) l10n.onlineLegs(m.legsWon, m.legsLost) else if (!m.x01) l10n.onlineRaw,
      '${m.darts} ${l10n.statDarts}',
      if (minutes > 0) formatMinutes(minutes),
    ].join(' · ');
    final facts = [
      if (m.first9 != null) (l10n.statsFirst9, formatDecimal(m.first9)),
      if (m.checkout.attempts > 0) (l10n.statCheckoutRate, wholePercent(m.checkout.rate)),
      if (m.highestFinish > 0) ('Finish', '${m.highestFinish}'),
      ('100+', '${m.tons}'),
      if (m.count180 > 0) ('180', '${m.count180}'),
    ];
    final canOpen = m.legs.isNotEmpty;
    return InkWell(
      onTap: canOpen ? () => setState(() => _open = !_open) : () => context.go(Routes.session(m.sessionId)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: look.cardPadding, vertical: AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(builder: (context, c) {
              // Breit: Kennzahlen in derselben Zeile wie Datum und Average.
              final wide = c.maxWidth >= 720;
              final head = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(historyDayLabel(l10n, StatsCalculator.dayOf(m.startedAt)), style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted), maxLines: 2),
                ],
              );
              final chips = Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.xs,
                children: [for (final (k, v) in facts) _Fact(label: k, value: v)],
              );
              final row = Row(
                children: [
                  if (wide) ...[
                    SizedBox(width: 280, child: head),
                    const SizedBox(width: AppSpacing.l),
                    Expanded(child: chips),
                  ] else
                    Expanded(child: head),
                  const SizedBox(width: AppSpacing.m),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatDecimal(m.average), style: look.chipNumber.copyWith(color: theme.colorScheme.onSurface)),
                      const SizedBox(height: AppSpacing.xxs),
                      Kicker(m.x01 ? l10n.onlineAverageShort : l10n.onlineAverageRaw),
                    ],
                  ),
                  if (canOpen) ...[
                    const SizedBox(width: AppSpacing.s),
                    Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: colors.textMuted),
                  ] else if (wide)
                    const SizedBox(width: AppSpacing.s + 24),
                ],
              );
              if (wide) return row;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [row, const SizedBox(height: AppSpacing.s), chips],
              );
            }),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: !_open
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.m),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, leg) in m.legs.indexed) _LegRow(key: Key('online-leg-${m.sessionId}-${i + 1}'), number: i + 1, leg: leg),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: Key('online-match-open-${m.sessionId}'),
                              onPressed: () => context.go(Routes.session(m.sessionId)),
                              icon: const Icon(Icons.list_alt_rounded, size: 18),
                              label: Text(l10n.onlineAllVisits),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = context.look;
    final colors = context.dartColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: AppSpacing.xxs + 1),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(look.id == DartLookId.clean ? 99 : look.radiusS),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label ', style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
          TextSpan(text: value, style: theme.textTheme.labelLarge?.copyWith(fontFeatures: DartLooks.tabular)),
        ]),
      ),
    );
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({super.key, required this.number, required this.leg});
  final int number;
  final OnlineLeg leg;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final details = [
      l10n.onlineLegDarts(leg.darts),
      'Ø ${formatDecimal(leg.average)}',
      if (leg.first9 != null) '${l10n.statsFirst9} ${formatDecimal(leg.first9)}',
      if (leg.won && leg.checkout > 0) 'Finish ${leg.checkout}',
    ].join(' · ');
    final result = Text(
      leg.won ? l10n.onlineLegWon : l10n.onlineLegLost,
      style: theme.textTheme.labelLarge?.copyWith(color: leg.won ? colors.success : colors.danger),
    );
    final info = Text(details, style: theme.textTheme.bodySmall);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs + 1),
      child: LayoutBuilder(builder: (context, c) {
        final title = SizedBox(width: 56, child: Kicker(l10n.onlineLegTitle(number)));
        // Schmal: Kennzahlen unter Leg und Ergebnis, sonst in einer Zeile.
        if (c.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [title, result]),
              const SizedBox(height: 2),
              info,
            ],
          );
        }
        return Row(
          children: [
            title,
            SizedBox(width: 76, child: result),
            Expanded(child: info),
          ],
        );
      }),
    );
  }
}
