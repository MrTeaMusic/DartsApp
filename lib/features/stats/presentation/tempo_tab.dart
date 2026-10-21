import 'package:flutter/material.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/domain/engine/game_display.dart';
import '../domain/stats_calculator.dart';
import 'stats_charts.dart';
import 'stats_screen.dart';
import 'stats_widgets.dart';

const _gap = SectionGap(factor: 0.8);

/// Reiter „Tempo“: Median der Wurfabstände und der Aufnahmezeit, Verlauf über
/// die Wochen, Punkte je Tempoklasse und der Vergleich Training, Match und
/// Online. Die Zahlen kommen fertig aus dem [StatsCalculator]
/// ([StatsCalculator.tempoReport], je Zeitraum und Spiel zwischengespeichert);
/// die Regeln stehen in `docs/wurftempo.md`.
///
/// Eigener Reiter statt Abschnitt im Scoring-Reiter, weil das Tempo ohne
/// Punkte lesbar sein soll (nicht jede Session hat welche), eigene Regeln hat
/// (nur Darts vom Board) und eine Erklärung braucht.
class TempoTab extends StatelessWidget {
  const TempoTab({super.key, required this.view, required this.wide, required this.pad});
  final StatsView view;
  final bool wide;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final report = view.calc.tempoReport(view.period, gameId: view.gameId);
    return ListView(
      key: const Key('stats-list-tempo'),
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.m, pad, AppSpacing.xxl),
      children: [
        if (report.all.isEmpty) ...[
          ComingSoon(
            key: const Key('tempo-empty'),
            icon: Icons.timer_outlined,
            title: l10n.tempoEmptyTitle,
            text: l10n.tempoEmptyText,
          ),
          if (report.sessionsSkipped > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.m),
              child: Text(
                l10n.tempoEmptySkipped(report.sessionsSkipped),
                key: const Key('tempo-empty-skipped'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ] else ...[
          SectionHeader(l10n.tempoFigures),
          _Figures(report: report, wide: wide),
          _gap,
          TwoColumns(
            wide: wide,
            left: _TrendCard(report: report),
            right: _BandsCard(report: report),
          ),
          _gap,
          _GroupsCard(report: report),
        ],
        _gap,
        _RulesCard(report: report),
      ],
    );
  }
}

/// Zahl oder „–“ mit „zu wenig Daten“ in der Beschriftung.
class _Figures extends StatelessWidget {
  const _Figures({required this.report, required this.wide});
  final TempoReport report;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final a = report.all;
    String caption(double? value, int count, String ok) =>
        value == null ? l10n.tempoTooLittleCount(count, TempoRules.minSamples) : ok;
    return TileGrid(
      minTileWidth: wide ? 220 : 170,
      children: [
        StatTile(
          key: const Key('tempo-per-dart'),
          label: l10n.tempoPerDart,
          value: a.perDart == null ? '–' : formatSeconds(a.perDart!),
          caption: caption(a.perDart, a.gapCount, l10n.tempoPerDartCaption(a.gapCount)),
          icon: Icons.adjust_rounded,
        ),
        StatTile(
          key: const Key('tempo-per-visit'),
          label: l10n.tempoPerVisit,
          value: a.perVisit == null ? '–' : formatSeconds(a.perVisit!),
          caption: caption(a.perVisit, a.fullVisits, l10n.tempoPerVisitCaption(a.fullVisits)),
          icon: Icons.timer_outlined,
        ),
        StatTile(
          key: const Key('tempo-with-takeout'),
          label: l10n.tempoWithTakeout,
          value: a.withTakeout == null ? '–' : formatSeconds(a.withTakeout!),
          caption: a.cycleCount == 0
              ? l10n.tempoTrainingOnly
              : caption(a.withTakeout, a.cycleCount, l10n.tempoWithTakeoutCaption(a.cycleCount)),
          icon: Icons.swap_horiz_rounded,
        ),
        StatTile(
          key: const Key('tempo-measured'),
          label: l10n.tempoMeasured,
          value: '${a.visits}',
          caption: l10n.tempoMeasuredCaption(report.sessionsUsed),
          icon: Icons.fact_check_outlined,
        ),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.report});
  final TempoReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enough = report.weeks.length >= 2;
    return ChartCard(
      key: const Key('tempo-trend'),
      title: l10n.tempoTrendTitle,
      hint: enough ? l10n.tempoTrendHint(TempoRules.trendWeeks, TempoRules.minSamples) : null,
      child: enough
          ? TrendLineChart(
              points: [for (final w in report.weeks) TrendPoint(0, w.weekStart, w.perDart)],
              format: (v) => l10n.tempoTrendValue(formatSeconds(v)),
            )
          : NoDataHint(
              key: const Key('tempo-trend-empty'),
              text: l10n.tempoTrendEmpty(TempoRules.minSamples),
              height: 200,
            ),
    );
  }
}

class _BandsCard extends StatelessWidget {
  const _BandsCard({required this.report});
  final TempoReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final best = report.bands.fold<double>(0, (a, b) => b.averagePoints == null || b.averagePoints! < a ? a : b.averagePoints!);
    final diff = report.slowMinusFast;
    String label(TempoBand b) => switch (b) {
          TempoBand.fast => l10n.tempoBandFast(TempoRules.fastLimit.round()),
          TempoBand.medium => l10n.tempoBandMedium(TempoRules.fastLimit.round(), TempoRules.slowLimit.round()),
          TempoBand.slow => l10n.tempoBandSlow(TempoRules.slowLimit.round()),
        };
    return AppCard(
      key: const Key('tempo-bands'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(l10n.tempoScoringTitle),
          for (final b in report.bands)
            Padding(
              key: Key('tempo-band-${b.band.name}'),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(width: 72, child: Text(label(b.band), style: theme.textTheme.labelMedium)),
                  Expanded(
                    child: LookProgressBar(
                      value: b.averagePoints == null || best == 0 ? 0 : b.averagePoints! / best,
                      height: context.look.barHeight + 4,
                      color: colors.chartPrimary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  SizedBox(
                    width: 110,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          b.averagePoints == null ? l10n.tempoBandTooLittle : l10n.tempoBandValue(formatDecimal(b.averagePoints)),
                          maxLines: 2,
                          textAlign: TextAlign.end,
                          style: b.averagePoints == null
                              ? theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)
                              : theme.textTheme.titleSmall,
                        ),
                        Text(l10n.tempoBandVisits(b.visits), style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (diff != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              diff.abs() < 0.5
                  ? l10n.tempoSlowSame
                  : diff > 0
                      ? l10n.tempoSlowMore(TempoRules.slowLimit.round(), TempoRules.fastLimit.round(), formatDecimal(diff.abs()))
                      : l10n.tempoSlowLess(TempoRules.slowLimit.round(), TempoRules.fastLimit.round(), formatDecimal(diff.abs())),
              key: const Key('tempo-slow-diff'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: AppSpacing.s),
          Text(l10n.tempoScoringHint, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _GroupsCard extends StatelessWidget {
  const _GroupsCard({required this.report});
  final TempoReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    String name(TempoGroup g) => switch (g) {
          TempoGroup.training => l10n.tempoGroupTraining,
          TempoGroup.match => l10n.tempoGroupMatch,
          TempoGroup.live => l10n.tempoGroupLive,
        };
    Widget cell(double? value, {required bool measured, Key? key}) => Text(
          key: key,
          value != null ? formatSeconds(value) : (measured ? l10n.tempoTooLittle : '–'),
          textAlign: TextAlign.right,
          maxLines: 2,
          style: value != null
              ? theme.textTheme.titleSmall
              : theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
        );
    Widget head(String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(text, textAlign: TextAlign.right, style: theme.textTheme.labelMedium?.copyWith(color: colors.textMuted)),
        );
    return AppCard(
      key: const Key('tempo-groups'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(l10n.tempoGroupsTitle),
          Table(
            columnWidths: const {0: FlexColumnWidth(1.2)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [
                const SizedBox.shrink(),
                head(l10n.tempoPerDart),
                head(l10n.tempoPerVisit),
                head(l10n.tempoWithTakeout),
              ]),
              for (final g in TempoGroup.values)
                TableRow(
                  children: [
                    Padding(
                      key: Key('tempo-group-${g.name}'),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name(g), style: theme.textTheme.titleSmall),
                          Text(l10n.tempoGroupVisits(report.group(g).visits), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    cell(report.group(g).perDart, measured: report.group(g).visits > 0),
                    cell(report.group(g).perVisit, measured: report.group(g).visits > 0),
                    // Mit Takeout wird nur im Training gemessen.
                    cell(report.group(g).withTakeout,
                        measured: g == TempoGroup.training && report.group(g).visits > 0, key: Key('tempo-group-${g.name}-takeout')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Text(l10n.tempoGroupsHint, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.report});
  final TempoReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      key: const Key('tempo-rules'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(l10n.tempoUsedTitle),
          if (report.sessions > 0) ...[
            Text(l10n.tempoUsed(report.sessionsUsed, report.sessions), key: const Key('tempo-used'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.s),
          ],
          Text(l10n.tempoRules, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
