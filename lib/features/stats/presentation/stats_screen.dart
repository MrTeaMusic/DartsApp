import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../board/presentation/dartboard_view.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/domain/game_catalog.dart';
import '../../games/presentation/game_texts.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/stats_repository.dart';
import '../domain/game_metrics.dart';
import '../domain/stats_calculator.dart';
import 'goals_card.dart';

/// Gewählter Zeitraum und Spielfilter der Statistik.
final statsPeriodProvider = NotifierProvider<_PeriodNotifier, StatsPeriod>(_PeriodNotifier.new);
final statsGameProvider = NotifierProvider<_GameNotifier, String?>(_GameNotifier.new);

class _PeriodNotifier extends Notifier<StatsPeriod> {
  @override
  StatsPeriod build() => StatsPeriod.month;
  void set(StatsPeriod p) => state = p;
}

class _GameNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

/// Formatiert die Hauptkennzahl eines Spiels.
String formatMetric(String gameId, double? v) {
  if (v == null) return '–';
  return switch (PrimaryMetric.byGame[gameId]?.format) {
    MetricFormat.percent => formatPercent(v),
    MetricFormat.integer => v.round().toString(),
    _ => v.toStringAsFixed(v.abs() < 10 ? 2 : 1).replaceAll('.', ','),
  };
}

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final calc = ref.watch(statsCalculatorProvider).value;
    final period = ref.watch(statsPeriodProvider);
    final gameId = ref.watch(statsGameProvider);
    final player = ref.watch(activePlayerProvider);

    final report = calc?.report(period, gameId: gameId);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.statsTitle),
        actions: [
          if (player != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.l),
              child: Chip(avatar: const Icon(Icons.person_rounded, size: 18), label: Text(player.name)),
            ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final pad = wide ? AppSpacing.pageWide : AppSpacing.page;
        return ListView(
          key: const Key('stats-list'),
          padding: EdgeInsets.all(pad),
          children: [
            _Filters(period: period, gameId: gameId),
            const SizedBox(height: AppSpacing.l),
            if (calc == null)
              const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.xxl), child: CircularProgressIndicator()))
            else ...[
              _StreakAndGoals(streak: calc.streak(), wide: wide),
              const SizedBox(height: AppSpacing.xl),
              if (report == null || report.isEmpty)
                ComingSoon(icon: Icons.insights_rounded, title: l10n.statsEmptyTitle, text: l10n.statsEmptyText)
              else
                ..._content(context, calc, report, period, gameId, wide),
            ],
          ],
        );
      }),
    );
  }

  List<Widget> _content(
      BuildContext context, StatsCalculator calc, StatsReport r, StatsPeriod period, String? gameId, bool wide) {
    final l10n = context.l10n;
    final tiles = <Widget>[
      StatTile(label: l10n.statsSessions, value: '${r.sessions}', icon: Icons.event_note_rounded),
      StatTile(label: l10n.statDarts, value: '${r.darts}', icon: Icons.adjust_rounded),
      StatTile(label: l10n.statsPracticeDays, value: '${r.practiceDays}', icon: Icons.calendar_month_rounded),
      if (r.scoringAverage != null)
        StatTile(
          key: const Key('stat-average'),
          label: l10n.statAverage,
          value: formatDecimal(r.scoringAverage),
          caption: l10n.statsAverageCaption,
          icon: Icons.speed_rounded,
        ),
      if (r.checkoutRate != null)
        StatTile(
          label: l10n.statCheckoutRate,
          value: formatPercent(r.checkoutRate),
          caption: l10n.statsAttempts(r.checkoutAttempts),
          icon: Icons.flag_rounded,
        ),
      if (r.doubleRate != null)
        StatTile(label: l10n.statDoubleRate, value: formatPercent(r.doubleRate), caption: l10n.gameBobs27, icon: Icons.looks_two_rounded),
      if (r.trebleRate != null)
        StatTile(label: l10n.statTrebleRate, value: formatPercent(r.trebleRate), caption: l10n.gameTargetPractice, icon: Icons.gps_fixed_rounded),
    ];

    final trendGame = gameId ?? (r.games.isEmpty ? null : r.games.first.gameId);
    final heat = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(l10n.statsHeatmap),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: AspectRatio(
              aspectRatio: 1,
              child: DartboardView(key: const Key('stats-heatmap'), heat: r.heat, showHeat: true),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(l10n.statsHeatmapHint, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
    final numbers = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [SectionHeader(l10n.statsNumbers), SizedBox(height: 220, child: _NumberChart(hits: r.numberHits))],
      ),
    );

    return [
      LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / 220).floor().clamp(2, 4);
        final w = (c.maxWidth - (cols - 1) * AppSpacing.m) / cols;
        return Wrap(
          spacing: AppSpacing.m,
          runSpacing: AppSpacing.m,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      }),
      const SizedBox(height: AppSpacing.xl),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(l10n.statsActivity),
            SizedBox(height: 180, child: _ActivityChart(days: r.dailyDarts)),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      if (trendGame != null) ...[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader('${l10n.statsTrend} · ${l10n.gameTitle(trendGame)}'),
              SizedBox(height: 220, child: _TrendChart(gameId: trendGame, points: calc.trend(trendGame, period))),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heat),
            const SizedBox(width: AppSpacing.xl),
            Expanded(child: numbers),
          ],
        )
      else ...[
        heat,
        const SizedBox(height: AppSpacing.xl),
        numbers,
      ],
      const SizedBox(height: AppSpacing.xl),
      SectionHeader(l10n.statsGames),
      AppCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(children: [for (final g in r.games) _GameRow(summary: g)]),
      ),
    ];
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.period, required this.gameId});
  final StatsPeriod period;
  final String? gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    String label(StatsPeriod p) => switch (p) {
          StatsPeriod.week => l10n.statsPeriodWeek,
          StatsPeriod.month => l10n.statsPeriodMonth,
          StatsPeriod.quarter => l10n.statsPeriodQuarter,
          StatsPeriod.all => l10n.statsPeriodAll,
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            for (final p in StatsPeriod.values)
              ChoiceChip(
                key: Key('period-${p.name}'),
                label: Text(label(p)),
                selected: p == period,
                onSelected: (_) => ref.read(statsPeriodProvider.notifier).set(p),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DropdownButton<String?>(
            key: const Key('stats-game'),
            value: gameId,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.statsAllGames)),
              for (final d in GameCatalog.all)
                DropdownMenuItem(value: d.id, child: Text(l10n.gameTitle(d.id), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => ref.read(statsGameProvider.notifier).set(v),
          ),
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
    final streakCard = AppCard(
      key: const Key('streak-card'),
      child: Row(
        children: [
          Icon(Icons.local_fire_department_rounded, size: 48, color: streak.current > 0 ? AppPalette.amber : colors.textMuted),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.statsStreak.toUpperCase(), style: theme.textTheme.labelMedium),
                Text(l10n.statsDays(streak.current), style: theme.textTheme.headlineMedium),
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
        children: [streakCard, const SizedBox(height: AppSpacing.l), const GoalsCard()],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: streakCard),
        const SizedBox(width: AppSpacing.xl),
        const Expanded(flex: 3, child: GoalsCard()),
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
    return ListTile(
      leading: Icon(gameIcon(summary.gameId)),
      title: Text(l10n.gameTitle(summary.gameId)),
      subtitle: Text('${summary.sessions} ${l10n.statsSessions} · ${summary.darts} ${l10n.statDarts}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatMetric(summary.gameId, summary.best), style: theme.textTheme.titleMedium),
          Text(l10n.statsBest, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

TextStyle? _axis(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11, color: context.dartColors.textMuted);

class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.days});
  final List<({DateTime day, int darts})> days;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final maxY = days.fold(0, (a, d) => math.max(a, d.darts)).toDouble();
    // Bei vielen Tagen nur jede n-te Beschriftung.
    final every = (days.length / 8).ceil().clamp(1, 1000);
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.15,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: const BarTouchData(enabled: true),
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
                if (i < 0 || i >= days.length || (days.length - 1 - i) % every != 0) return const SizedBox.shrink();
                final d = days[i].day;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${d.day}.${d.month}.', style: _axis(context)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (final (i, d) in days.indexed)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: d.darts.toDouble(),
                color: color,
                width: (240 / days.length).clamp(2, 18).toDouble(),
                borderRadius: BorderRadius.circular(3),
              ),
            ]),
        ],
      ),
    );
  }
}

class _NumberChart extends StatelessWidget {
  const _NumberChart({required this.hits});
  final Map<int, int> hits;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final numbers = [for (var n = 1; n <= 20; n++) n, 25];
    final maxY = numbers.fold(0, (a, n) => math.max(a, hits[n] ?? 0)).toDouble();
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.15,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
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
                borderRadius: BorderRadius.circular(3),
              ),
            ]),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.gameId, required this.points});
  final String gameId;
  final List<TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (points.isEmpty) {
      return Center(child: Text(l10n.statsTrendEmpty, style: Theme.of(context).textTheme.bodySmall));
    }
    final color = Theme.of(context).colorScheme.primary;
    final percent = PrimaryMetric.byGame[gameId]?.format == MetricFormat.percent;
    final values = [for (final p in points) percent ? p.value * 100 : p.value];
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = hi - lo == 0 ? (hi == 0 ? 1 : hi.abs() * 0.2) : hi - lo;
    return LineChart(
      LineChartData(
        minY: lo - span * 0.15,
        maxY: hi + span * 0.15,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: context.dartColors.surfaceHigh, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  formatMetric(gameId, points[s.x.round()].value),
                  TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: const AxisTitles(),
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
            isCurved: points.length > 2,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 3,
            dotData: FlDotData(show: points.length <= 30),
            belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }
}
