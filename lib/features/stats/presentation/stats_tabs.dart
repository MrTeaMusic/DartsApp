import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../board/presentation/dartboard_view.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/presentation/game_texts.dart';
import '../../plans/presentation/auto_plan_screen.dart';
import '../domain/game_metrics.dart';
import '../domain/stats_calculator.dart';
import 'double_insights.dart';
import 'goals_card.dart';
import 'stats_charts.dart';
import 'stats_screen.dart';
import 'stats_widgets.dart';

/// Mindestzahl an Versuchen, damit ein Double als stark oder schwach gilt.
const int _minDoubleAttempts = 5;

/// Mindestzahl an Versuchen, damit ein Triple im Diagramm erscheint.
const int _minTrebleAttempts = 3;

/// Gemeinsamer Rahmen eines Reiters: scrollbare Liste mit Seitenrand.
class _TabList extends StatelessWidget {
  const _TabList({required this.name, required this.pad, required this.children});
  final String name;
  final double pad;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: Key('stats-list-$name'),
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.m, pad, AppSpacing.xxl),
      children: children,
    );
  }
}

/// Zahl rechts in Listen (Rekorde, Bestwerte).
TextStyle _trailingValue(BuildContext context) =>
    context.look.chipNumber.copyWith(color: Theme.of(context).colorScheme.onSurface, fontSize: (context.look.chipNumber.fontSize ?? 18) + 2);

Widget _empty(BuildContext context) =>
    ComingSoon(icon: Icons.insights_rounded, title: context.l10n.statsEmptyTitle, text: context.l10n.statsEmptyText);

const _gap = SectionGap(factor: 0.8);

// ---------------------------------------------------------------------------
// Überblick
// ---------------------------------------------------------------------------

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key, required this.view, required this.wide, required this.pad});
  final StatsView view;
  final bool wide;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = view.report;
    final p = view.previous;
    return _TabList(
      name: 'overview',
      pad: pad,
      children: [
        _StreakAndGoals(streak: view.calc.streak(), wide: wide),
        _gap,
        if (r.isEmpty)
          _empty(context)
        else ...[
          SectionHeader(l10n.statsKeyFigures),
          TileGrid(children: [
            KpiTile(
              label: l10n.statsSessions,
              value: '${r.sessions}',
              icon: Icons.event_note_rounded,
              delta: MetricDelta.of(r.sessions.toDouble(), p?.sessions.toDouble(), ValueKind.count),
            ),
            KpiTile(
              label: l10n.statDarts,
              value: '${r.darts}',
              icon: Icons.adjust_rounded,
              delta: MetricDelta.of(r.darts.toDouble(), p?.darts.toDouble(), ValueKind.count),
            ),
            KpiTile(
              label: l10n.statsPracticeDays,
              value: '${r.practiceDays}',
              icon: Icons.calendar_month_rounded,
              delta: MetricDelta.of(r.practiceDays.toDouble(), p?.practiceDays.toDouble(), ValueKind.count),
            ),
            KpiTile(
              label: l10n.statsTrainingTime,
              value: formatMinutes(r.trainingTime.inMinutes),
              icon: Icons.timer_outlined,
              delta: MetricDelta.of(
                  r.trainingTime.inMinutes.toDouble(), p?.trainingTime.inMinutes.toDouble(), ValueKind.minutes),
            ),
            if (r.scoringAverage != null)
              KpiTile(
                key: const Key('stat-average'),
                label: l10n.statAverage,
                value: formatDecimal(r.scoringAverage),
                caption: l10n.statsAverageCaption,
                icon: Icons.speed_rounded,
                delta: MetricDelta.of(r.scoringAverage, p?.scoringAverage, ValueKind.decimal),
              ),
            if (r.checkoutRate != null)
              KpiTile(
                label: l10n.statCheckoutRate,
                value: formatPercent(r.checkoutRate),
                caption: l10n.statsAttempts(r.checkoutAttempts),
                icon: Icons.flag_rounded,
                delta: MetricDelta.of(r.checkoutRate, p?.checkoutRate, ValueKind.percent),
              ),
            if (r.doubleRate != null)
              KpiTile(
                label: l10n.statDoubleRate,
                value: formatPercent(r.doubleRate),
                caption: l10n.statsDoubleCaption(r.doubleAttempts),
                icon: Icons.looks_two_rounded,
                delta: MetricDelta.of(r.doubleRate, p?.doubleRate, ValueKind.percent),
              ),
            if (r.trebleRate != null)
              KpiTile(
                label: l10n.statTrebleRate,
                value: formatPercent(r.trebleRate),
                caption: l10n.statsTrebleCaption(r.trebleAttempts),
                icon: Icons.gps_fixed_rounded,
                delta: MetricDelta.of(r.trebleRate, p?.trebleRate, ValueKind.percent),
              ),
            if (r.accuracy.attempts > 0)
              KpiTile(
                label: l10n.statsAccuracy,
                value: formatPercent(r.accuracy.rate),
                caption: l10n.statsAccuracyCaption(r.accuracy.attempts),
                icon: Icons.center_focus_strong_rounded,
                delta: MetricDelta.of(r.accuracy.rate, p?.accuracy.rate, ValueKind.percent),
              ),
          ]),
          if (p != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(l10n.statsCompareHint(view.period.days!), style: Theme.of(context).textTheme.bodySmall),
          ],
          const AutoPlanHint(),
          _gap,
          _ActivityCard(report: r, period: view.period),
          _gap,
          TwoColumns(
            wide: wide,
            left: ChartCard(
              title: '${l10n.statsPattern} · ${l10n.statsWeekdays}',
              child: SizedBox(
                height: 180,
                child: VolumeChart(
                  labels: l10n.statsWeekdayNames.split(','),
                  values: [for (final b in r.weekdays) b.darts.toDouble()],
                ),
              ),
            ),
            right: ChartCard(
              title: '${l10n.statsPattern} · ${l10n.statsDayParts}',
              child: _DayParts(buckets: r.dayParts),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.report, required this.period});
  final StatsReport report;
  final StatsPeriod period;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final daily = period.days != null && period.days! <= 30;
    return ChartCard(
      key: const Key('stats-activity'),
      title: daily ? l10n.statsActivity : l10n.statsActivityWeekly,
      child: SizedBox(
        height: 180,
        child: daily
            ? VolumeChart(
                labels: [for (final d in report.dailyDarts) formatDayMonth(d.day)],
                values: [for (final d in report.dailyDarts) d.darts.toDouble()],
              )
            : VolumeChart(
                labels: [for (final w in report.weekly) formatDayMonth(w.weekStart)],
                values: [for (final w in report.weekly) w.bucket.darts.toDouble()],
              ),
      ),
    );
  }
}

class _DayParts extends StatelessWidget {
  const _DayParts({required this.buckets});
  final List<ActivityBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    String name(DayPart p) => switch (p) {
          DayPart.morning => l10n.statsDayMorning,
          DayPart.afternoon => l10n.statsDayAfternoon,
          DayPart.evening => l10n.statsDayEvening,
          DayPart.night => l10n.statsDayNight,
        };
    final maxDarts = buckets.fold(0, (a, b) => b.darts > a ? b.darts : a);
    final withAvg = [for (final p in DayPart.values) if (buckets[p.index].average != null) p];
    final best = withAvg.length < 2
        ? null
        : withAvg.reduce((a, b) => buckets[a.index].average! >= buckets[b.index].average! ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in DayPart.values) ...[
          Row(
            children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: name(p), style: theme.textTheme.bodyMedium),
                  TextSpan(text: '  ${l10n.statsHours(p.fromHour, p.toHour)}', style: theme.textTheme.bodySmall),
                ])),
              ),
              if (buckets[p.index].average case final avg?)
                Text('Ø ${formatDecimal(avg)}', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          LookProgressBar(
            value: maxDarts == 0 ? 0 : buckets[p.index].darts / maxDarts,
            color: p == best ? colors.success : colors.chartPrimary,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(l10n.statsSessionsDarts(buckets[p.index].sessions, buckets[p.index].darts), style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.s),
        ],
        if (best != null)
          Text(
            l10n.statsBestDayPart(name(best), formatDecimal(buckets[best.index].average)),
            style: theme.textTheme.bodySmall?.copyWith(color: colors.success),
          ),
      ],
    );
  }
}

class _StreakAndGoals extends StatelessWidget {
  const _StreakAndGoals({required this.streak, required this.wide});
  final Streak streak;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final flame = streak.current > 0 ? colors.record : colors.textMuted;
    final streakCard = AppCard(
      key: const Key('streak-card'),
      child: Row(
        children: [
          IconBadge(icon: Icons.local_fire_department_rounded, color: flame, size: 56),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Kicker(l10n.statsStreak),
                const SizedBox(height: AppSpacing.xxs),
                Text(l10n.statsDays(streak.current), style: context.look.statValue.copyWith(color: theme.colorScheme.onSurface)),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${streak.trainedToday ? l10n.statsTrainedToday : l10n.statsNotTrainedToday} · ${l10n.statsLongest(streak.longest)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [streakCard, SizedBox(height: context.look.gridGap * 1.5), const GoalsCard()],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: streakCard),
        SizedBox(width: context.look.sectionGap * 0.75),
        const Expanded(flex: 3, child: GoalsCard()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

class ScoringTab extends StatelessWidget {
  const ScoringTab({super.key, required this.view, required this.wide, required this.pad});
  final StatsView view;
  final bool wide;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = view.report;
    final p = view.previous;
    if (r.isEmpty) return _TabList(name: 'scoring', pad: pad, children: [_empty(context)]);
    final sc = r.scoring;
    final heat = ChartCard(
      title: l10n.statsHeatmap,
      hint: l10n.statsHeatmapHint,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 380),
        child: AspectRatio(
          aspectRatio: 1,
          child: DartboardView(key: const Key('stats-heatmap'), heat: r.heat, showHeat: true),
        ),
      ),
    );
    final numbers = ChartCard(
      title: l10n.statsNumbers,
      child: SizedBox(height: 220, child: NumberHitsChart(hits: r.numberHits)),
    );
    return _TabList(
      name: 'scoring',
      pad: pad,
      children: [
        TileGrid(children: [
          KpiTile(
            key: const Key('stat-scoring-average'),
            label: l10n.statAverage,
            value: formatDecimal(r.scoringAverage),
            caption: l10n.statsAverageCaption,
            icon: Icons.speed_rounded,
            delta: MetricDelta.of(r.scoringAverage, p?.scoringAverage, ValueKind.decimal),
          ),
          if (r.first9Average != null)
            KpiTile(
              label: l10n.statsFirst9,
              value: formatDecimal(r.first9Average),
              caption: l10n.statsFirst9Caption,
              icon: Icons.looks_one_rounded,
              delta: MetricDelta.of(r.first9Average, p?.first9Average, ValueKind.decimal),
            ),
          if (sc != null) ...[
            KpiTile(
              label: l10n.statsSpread,
              value: '± ${formatDecimal(sc.stdDev)}',
              caption: l10n.statsSpreadCaption,
              icon: Icons.stacked_line_chart_rounded,
              delta: MetricDelta.of(sc.stdDev, p?.scoring?.stdDev, ValueKind.decimal, higherIsBetter: false),
            ),
            StatTile(label: l10n.statsHighestVisit, value: '${sc.highest}', icon: Icons.emoji_events_rounded),
            StatTile(
              label: l10n.statsTons,
              value: '${sc.tons}',
              caption: l10n.statsRateOfVisits(formatPercent(sc.rate(sc.tons))),
              icon: Icons.filter_1_rounded,
            ),
            StatTile(
              label: l10n.statsTon40s,
              value: '${sc.ton40s}',
              caption: l10n.statsRateOfVisits(formatPercent(sc.rate(sc.ton40s))),
              icon: Icons.local_fire_department_rounded,
            ),
            StatTile(
              key: const Key('stat-180s'),
              label: l10n.statsMaxes,
              value: '${sc.maxes}',
              caption: l10n.statsRateOfVisits(formatPercent(sc.rate(sc.maxes))),
              icon: Icons.star_rounded,
            ),
            StatTile(
              label: l10n.statsUnder40,
              value: '${sc.under40}',
              caption: l10n.statsRateOfVisits(formatPercent(sc.rate(sc.under40))),
              icon: Icons.south_rounded,
            ),
          ],
        ]),
        _gap,
        ChartCard(
          key: const Key('stats-average-trend'),
          title: l10n.statsAverageTrend,
          child: TrendLineChart(points: r.averageTrend, format: formatDecimal, emptyText: l10n.statsNoData),
        ),
        _gap,
        TwoColumns(
          wide: wide,
          left: ChartCard(
            key: const Key('stats-distribution'),
            title: l10n.statsDistribution,
            hint: sc == null ? null : l10n.statsDistributionHint(sc.visits),
            child: sc == null ? const NoDataHint() : _Distribution(stats: sc),
          ),
          right: ChartCard(
            title: l10n.statsTreblesPerNumber,
            hint: l10n.statsTreblesHint,
            child: r.trebles.values.every((h) => h.attempts < _minTrebleAttempts)
                ? const NoDataHint()
                : SizedBox(height: 200, child: RatePerNumberChart(counts: r.trebles, minAttempts: _minTrebleAttempts)),
          ),
        ),
        _gap,
        TwoColumns(wide: wide, left: heat, right: numbers),
      ],
    );
  }
}

class _Distribution extends StatelessWidget {
  const _Distribution({required this.stats});
  final ScoringStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final max = ScoreBand.values.fold(0, (a, b) => stats.count(b) > a ? stats.count(b) : a);
    String label(ScoreBand b) => b == ScoreBand.maximum ? '180' : (b == ScoreBand.under40 ? '< 40' : '${b.min}–${b.max}');
    Color color(ScoreBand b) => switch (b) {
          ScoreBand.under40 => colors.danger,
          ScoreBand.from40 || ScoreBand.from60 => Theme.of(context).colorScheme.primary,
          _ => colors.success,
        };
    return Column(
      children: [
        for (final b in ScoreBand.values.reversed)
          BarRow(
            label: label(b),
            ratio: max == 0 ? 0 : stats.count(b) / max,
            value: '${stats.count(b)}',
            detail: formatPercent(stats.rate(stats.count(b))),
            color: color(b),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Doppel & Finish
// ---------------------------------------------------------------------------

class DoublesTab extends StatelessWidget {
  const DoublesTab({super.key, required this.view, required this.wide, required this.pad});
  final StatsView view;
  final bool wide;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = view.report;
    final p = view.previous;
    if (r.isEmpty) return _TabList(name: 'doubles', pad: pad, children: [_empty(context)]);
    final ranked = [
      for (final e in r.doubles.entries)
        if (e.value.attempts >= _minDoubleAttempts) e,
    ]..sort((a, b) => b.value.rate!.compareTo(a.value.rate!));
    String name(int n) => n == 25 ? 'BULL' : 'D$n';
    String detail(HitCount h) => '${formatPercent(h.rate)} · ${h.hits}/${h.attempts}';
    return _TabList(
      name: 'doubles',
      pad: pad,
      children: [
        TileGrid(children: [
          KpiTile(
            label: l10n.statCheckoutRate,
            value: formatPercent(r.checkoutRate),
            caption: l10n.statsAttempts(r.checkoutAttempts),
            icon: Icons.flag_rounded,
            delta: MetricDelta.of(r.checkoutRate, p?.checkoutRate, ValueKind.percent),
          ),
          KpiTile(
            key: const Key('stat-double-rate'),
            label: l10n.statDoubleRate,
            value: formatPercent(r.doubleRate),
            caption: l10n.statsDoubleCaption(r.doubleAttempts),
            icon: Icons.looks_two_rounded,
            delta: MetricDelta.of(r.doubleRate, p?.doubleRate, ValueKind.percent),
          ),
          if (ranked.length >= 2) ...[
            StatTile(
              key: const Key('stat-strongest-double'),
              label: l10n.statsStrongestDouble,
              value: name(ranked.first.key),
              caption: detail(ranked.first.value),
              icon: Icons.thumb_up_alt_outlined,
            ),
            StatTile(
              key: const Key('stat-weakest-double'),
              label: l10n.statsWeakestDouble,
              value: name(ranked.last.key),
              caption: detail(ranked.last.value),
              icon: Icons.fitness_center_rounded,
            ),
          ],
        ]),
        _gap,
        DoubleFocusCard(stats: view.doubles, wide: wide),
        _gap,
        TwoColumns(
          wide: wide,
          left: CheckoutVsTrainingCard(stats: view.doubles),
          right: DoubleTipCard(stats: view.doubles, minAttempts: _minDoubleAttempts),
        ),
        _gap,
        ChartCard(
          title: l10n.statsDoublesPerNumber,
          hint: '${l10n.statsDoublesHint} ${l10n.statsDoublesLegend(_minDoubleAttempts)} '
              '${l10n.statsDoublesTrendLegend(DoubleStats.trendMinAttempts)}',
          child: r.doubles.isEmpty
              ? const NoDataHint()
              : DoublesGrid(
                  doubles: r.doubles,
                  overall: r.doubleRate,
                  trends: {for (final e in view.doubles.trends.entries) e.key: ?e.value.direction},
                ),
        ),
        _gap,
        ChartCard(
          key: const Key('stats-checkout-ranges'),
          title: l10n.statsCheckoutByRange,
          child: r.checkoutByRange.isEmpty
              ? const NoDataHint()
              : Column(
                  children: [
                    for (final range in CheckoutRange.values)
                      if (r.checkoutByRange[range] case final h?)
                        BarRow(
                          label: '${range.min}–${range.max}',
                          ratio: h.rate ?? 0,
                          value: formatPercent(h.rate),
                          detail: '${h.hits}/${h.attempts}',
                          color: context.dartColors.doubleHit,
                        ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Spiele
// ---------------------------------------------------------------------------

class GamesTab extends ConsumerWidget {
  const GamesTab({super.key, required this.view, required this.wide, required this.pad});
  final StatsView view;
  final bool wide;
  final double pad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final r = view.report;
    if (r.isEmpty) return _TabList(name: 'games', pad: pad, children: [_empty(context)]);
    final played = [for (final g in r.games) g.gameId];
    final chosen = ref.watch(statsTrendGameProvider);
    final game = view.gameId ?? (played.contains(chosen) ? chosen! : played.first);
    final keys = view.calc.metricKeys(game, view.period);
    final chosenMetric = ref.watch(statsTrendMetricProvider);
    final metric = keys.contains(chosenMetric) ? chosenMetric! : (keys.isEmpty ? PrimaryMetric.forGame(game).key : keys.first);
    final points = view.calc.metricTrend(game, metric, view.period);
    final percent = metricIsPercent(game, metric);
    String fmt(double v) => formatMetricKey(game, metric, v);

    return _TabList(
      name: 'games',
      pad: pad,
      children: [
        ChartCard(
          key: const Key('stats-game-trend'),
          title: l10n.statsTrend,
          trailing: view.gameId != null || played.length < 2
              ? null
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: DropdownButton<String>(
                    key: const Key('stats-trend-game'),
                    value: game,
                    isExpanded: true,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final id in played)
                        DropdownMenuItem(value: id, child: Text(l10n.gameTitle(id), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      ref.read(statsTrendGameProvider.notifier).set(v);
                      ref.read(statsTrendMetricProvider.notifier).set(null);
                    },
                  ),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(gameIcon(game), size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(child: Text(l10n.gameTitle(game), style: Theme.of(context).textTheme.titleMedium)),
                ],
              ),
              if (keys.length > 1) ...[
                const SizedBox(height: AppSpacing.m),
                Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  children: [
                    for (final k in keys)
                      ChoiceChip(
                        key: Key('metric-$k'),
                        label: Text(metricLabel(l10n, k)),
                        selected: k == metric,
                        onSelected: (_) => ref.read(statsTrendMetricProvider.notifier).set(k),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.l),
              TrendLineChart(points: points, format: fmt, percent: percent),
              if (points.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.l),
                _TrendFacts(game: game, metric: metric, points: points, format: fmt),
              ],
            ],
          ),
        ),
        _gap,
        SectionHeader(l10n.statsGames),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(children: [for (final g in r.games) _GameRow(summary: g)]),
        ),
      ],
    );
  }
}

/// Ist die Kennzahl eine Quote (0–1)?
bool metricIsPercent(String gameId, String key) {
  final pm = PrimaryMetric.forGame(gameId);
  if (key == pm.key) return pm.format == MetricFormat.percent;
  return key.endsWith('Rate') || key == 'progress';
}

class _TrendFacts extends StatelessWidget {
  const _TrendFacts({required this.game, required this.metric, required this.points, required this.format});
  final String game;
  final String metric;
  final List<TrendPoint> points;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pm = PrimaryMetric.forGame(game);
    final lowerBetter = metric == pm.key ? !pm.higherIsBetter : (metric == 'darts' || metric == 'avgDartsPerCheckout' || metric == 'avgSeconds');
    final values = [for (final p in points) p.value];
    final best = values.reduce((a, b) => (lowerBetter ? a < b : a > b) ? a : b);
    final lastFive = values.sublist(values.length > 5 ? values.length - 5 : 0);
    final avg5 = lastFive.reduce((a, b) => a + b) / lastFive.length;
    Widget fact(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Kicker(label),
              const SizedBox(height: AppSpacing.xxs),
              Text(value, style: _trailingValue(context).copyWith(fontSize: (_trailingValue(context).fontSize ?? 18) + 4)),
            ],
          ),
        );
    return Row(
      children: [
        fact(l10n.statsBest, format(best)),
        fact(l10n.statsLast, format(values.last)),
        fact(l10n.statsLastFive, format(avg5)),
      ],
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.summary});
  final GameSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final acc = summary.accuracy;
    return ListTile(
      leading: IconBadge(icon: gameIcon(summary.gameId), size: 38),
      title: Text(l10n.gameTitle(summary.gameId)),
      subtitle: Text([
        throwlessGames.contains(summary.gameId)
            ? '${summary.sessions} ${l10n.statsSessions}'
            : '${summary.sessions} ${l10n.statsSessions} · ${summary.darts} ${l10n.statDarts}',
        if (acc.attempts > 0) '${l10n.statsAccuracy}: ${formatPercent(acc.rate)}',
      ].join('\n')),
      isThreeLine: acc.attempts > 0,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatMetric(summary.gameId, summary.best), style: _trailingValue(context)),
          Text(
            summary.bestAt == null ? l10n.statsBest : '${l10n.statsBest} · ${formatDayMonth(summary.bestAt!)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rekorde
// ---------------------------------------------------------------------------

class RecordsTab extends StatelessWidget {
  const RecordsTab({super.key, required this.view, required this.wide, required this.pad});
  final StatsView view;
  final bool wide;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final records = view.calc.records();
    final games = [
      for (final g in view.calc.report(StatsPeriod.all).games)
        if (g.best != null) g,
    ];
    String label(RecordKind k) => switch (k) {
          RecordKind.bestAverage => l10n.statsRecordBestAverage,
          RecordKind.bestFirst9 => l10n.statsRecordBestFirst9,
          RecordKind.highestVisit => l10n.statsRecordHighestVisit,
          RecordKind.highestCheckout => l10n.statsRecordHighestCheckout,
          RecordKind.most180s => l10n.statsRecordMost180s,
          RecordKind.mostDartsDay => l10n.statsRecordMostDartsDay,
          RecordKind.longestStreak => l10n.statsRecordLongestStreak,
        };
    IconData icon(RecordKind k) => switch (k) {
          RecordKind.bestAverage => Icons.speed_rounded,
          RecordKind.bestFirst9 => Icons.looks_one_rounded,
          RecordKind.highestVisit => Icons.emoji_events_rounded,
          RecordKind.highestCheckout => Icons.flag_rounded,
          RecordKind.most180s => Icons.star_rounded,
          RecordKind.mostDartsDay => Icons.adjust_rounded,
          RecordKind.longestStreak => Icons.local_fire_department_rounded,
        };
    String value(PersonalRecord r) => switch (r.kind) {
          RecordKind.bestAverage || RecordKind.bestFirst9 => formatDecimal(r.value),
          RecordKind.longestStreak => l10n.statsDays(r.value.round()),
          _ => r.value.round().toString(),
        };
    return _TabList(
      name: 'records',
      pad: pad,
      children: [
        Text(l10n.statsRecordsHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.m),
        if (records.isEmpty && games.isEmpty)
          ComingSoon(icon: Icons.emoji_events_rounded, title: l10n.statsTabRecords, text: l10n.statsRecordsEmpty)
        else ...[
          if (records.isNotEmpty)
            AppCard(
              key: const Key('stats-records'),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: [
                  for (final r in records)
                    ListTile(
                      key: Key('record-${r.kind.name}'),
                      leading: IconBadge(icon: icon(r.kind), color: context.dartColors.record, size: 38),
                      title: Text(label(r.kind)),
                      subtitle: Text([
                        if (r.date != null) formatDate(r.date!),
                        if (r.gameId != null) l10n.gameTitle(r.gameId!),
                      ].join(' · ')),
                      trailing: Text(value(r), style: _trailingValue(context)),
                    ),
                ],
              ),
            ),
          if (games.isNotEmpty) ...[
            _gap,
            SectionHeader(l10n.statsGameBests),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: [
                  for (final g in games)
                    ListTile(
                      leading: IconBadge(icon: gameIcon(g.gameId), size: 38),
                      title: Text(l10n.gameTitle(g.gameId)),
                      subtitle: Text([
                        metricLabel(l10n, PrimaryMetric.forGame(g.gameId).key),
                        if (g.bestAt != null) l10n.statsBestOn(formatDate(g.bestAt!)),
                      ].join(' · ')),
                      trailing: Text(formatMetric(g.gameId, g.best), style: _trailingValue(context)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
