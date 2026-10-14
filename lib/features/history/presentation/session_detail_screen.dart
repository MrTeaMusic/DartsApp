import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../board/presentation/dartboard_view.dart';
import '../../games/data/game_repository.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/domain/game_catalog.dart';
import '../../games/presentation/game_texts.dart';
import '../../matches/domain/match_format.dart';
import '../../stats/presentation/stats_charts.dart';
import '../../stats/presentation/stats_widgets.dart';
import '../data/history_repository.dart';
import '../domain/session_history.dart';
import 'history_screen.dart';

/// Eine Session im Detail: Kopf, Kennzahlen, Verlauf, Heatmap und jede
/// Aufnahme; bei Matches Ergebnis aller Teilnehmer und die Legs. Eine falsch
/// gespeicherte Session lässt sich hier löschen.
class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});
  final int sessionId;

  @override
  ConsumerState<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  bool _deleting = false;

  Future<void> _delete(SessionDetail d) async {
    final l10n = context.l10n;
    final e = d.entry;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('session-delete-dialog'),
        title: Text(l10n.histDeleteTitle),
        content: Text(l10n.histDeleteText(l10n.gameTitle(e.gameId), formatDate(e.startedAt), e.darts)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.gameCancelShort)),
          FilledButton(
            key: const Key('session-delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: context.dartColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.histDeleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(gameRepositoryProvider).deleteSession(e.id);
    if (!mounted) return;
    context.go(Routes.history);
    messenger.showSnackBar(SnackBar(content: Text(l10n.histDeleted)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(sessionDetailProvider(widget.sessionId));
    final d = async.value;
    if (d == null) {
      return Scaffold(
        appBar: AppPageBar(maxWidth: kHistoryMaxWidth, title: Text(l10n.histTitle)),
        body: async.isLoading || _deleting ? const SizedBox.shrink() : Center(child: Text(l10n.histNotFound)),
      );
    }
    final e = d.entry;
    final canReplay = !e.isMatch && GameCatalog.byId(e.gameId) != null;
    return Scaffold(
      appBar: AppPageBar(
        maxWidth: kHistoryMaxWidth,
        title: Text(l10n.histTitle),
        actions: [
          IconButton(
            key: const Key('session-delete-action'),
            tooltip: l10n.histDelete,
            onPressed: _deleting ? null : () => _delete(d),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 900;
        return AppPage(
          maxWidth: kHistoryMaxWidth,
          listKey: const Key('session-detail'),
          children: [
            _Header(detail: d),
            const SectionGap(factor: 0.8),
            if (e.isMatch) _MatchResultCard(detail: d),
            // Bei Matches stehen die eigenen Kennzahlen schon im Ergebnis.
            if (!e.isMatch) ...[
              SectionHeader(l10n.histKeyMetrics),
              TileGrid(
                minTileWidth: 170,
                children: [
                  for (final s in d.summary.take(8)) StatTile(label: l10n.statLabel(s.key), value: s.value),
                ],
              ),
            ],
            if (d.visits.isNotEmpty) ...[
              const SectionGap(factor: 0.8),
              _ChartAndHeat(detail: d, wide: wide),
              const SectionGap(factor: 0.8),
              _Visits(detail: d),
            ] else ...[
              const SizedBox(height: AppSpacing.l),
              Text(l10n.histNoThrows, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SectionGap(),
            Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.m,
              children: [
                if (canReplay)
                  FilledButton.icon(
                    key: const Key('session-play-again'),
                    onPressed: () => context.go(Routes.gameSetup(e.gameId)),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text(l10n.histPlayAgain),
                  ),
                OutlinedButton.icon(
                  key: const Key('session-delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.dartColors.danger,
                    side: BorderSide(color: context.dartColors.danger.withValues(alpha: 0.6)),
                  ),
                  onPressed: _deleting ? null : () => _delete(d),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(l10n.histDelete),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// Spiel, Datum, Status, Dauer, Profil und Darts.
class _Header extends StatelessWidget {
  const _Header({required this.detail});
  final SessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final e = detail.entry;
    final minutes = e.duration?.inMinutes;
    final won = e.won;
    final (String status, Color statusColor) = e.isMatch && won != null
        ? (won ? l10n.histWon : l10n.histLost, won ? colors.success : colors.danger)
        : e.finished
            ? (l10n.histFinished, colors.success)
            : (l10n.histAborted, colors.textMuted);
    final format = e.isMatch ? MatchFormat.fromJson(e.details['format'] ?? e.config) : null;
    final me = detail.players.isEmpty ? null : detail.players[detail.me].name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconBadge(icon: gameIcon(e.gameId), size: 52),
            const SizedBox(width: AppSpacing.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Kicker('${historyDayLabel(l10n, DateTime(e.startedAt.year, e.startedAt.month, e.startedAt.day))} · '
                      '${historyTime(e.startedAt)}'),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    e.isMatch && e.opponents.isNotEmpty ? l10n.histVs(e.opponents.join(', ')) : l10n.gameTitle(e.gameId),
                    key: const Key('session-title'),
                    style: theme.textTheme.headlineSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.m),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusPill(key: const Key('session-status'), label: status, color: statusColor),
            if (e.tournament) _Info(icon: Icons.account_tree_rounded, text: l10n.histTournament),
            if (format != null)
              _Info(
                icon: Icons.scoreboard_rounded,
                text: '${format.startScore} · ${format.usesSets ? l10n.matchFormatSets(format.setsToWin, format.legsToWin) : l10n.matchFormatLegs(format.legsToWin, format.bestOf)}',
              ),
            _Info(icon: Icons.adjust_rounded, text: '${e.darts} ${l10n.statDarts}'),
            if (minutes != null) _Info(icon: Icons.schedule_rounded, text: formatMinutes(minutes < 1 ? 1 : minutes)),
            if (me != null && me.isNotEmpty) _Info(icon: Icons.person_rounded, text: me),
          ],
        ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: colors.textMuted),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textMuted))),
        const SizedBox(width: AppSpacing.s),
      ],
    );
  }
}

/// Endstand und Kennzahlen aller Teilnehmer, soweit gespeichert.
class _MatchResultCard extends StatelessWidget {
  const _MatchResultCard({required this.detail});
  final SessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final e = detail.entry;
    final players = detail.players;
    final format = MatchFormat.fromJson(e.details['format'] ?? e.config);
    final sets = format.usesSets;
    final known = players.every((p) => p.stats.isNotEmpty);
    String score;
    if (known && players.length > 1) {
      score = players.map((p) => '${(sets ? p.stats['sets'] : p.stats['legs'])?.round() ?? 0}').join(' : ');
    } else {
      score = '${e.legsWon} : ${e.legsLost}';
    }
    String v(MatchPlayerResult p, String key, String Function(num) f) {
      final x = p.stats[key];
      return x == null ? '–' : f(x);
    }

    final rows = <(String, List<String>)>[
      if (sets) (l10n.matchStatSets, [for (final p in players) v(p, 'sets', (x) => '${x.round()}')]),
      (l10n.matchStatLegs, [for (final p in players) v(p, 'legs', (x) => '${x.round()}')]),
      (l10n.matchStatAverage, [for (final p in players) v(p, 'average', formatDecimal)]),
      (l10n.matchStatFirst9, [for (final p in players) v(p, 'first9', formatDecimal)]),
      (l10n.matchStatCheckout, [for (final p in players) v(p, 'checkoutRate', formatPercent)]),
      (l10n.matchStatHighFinish, [for (final p in players) v(p, 'highestFinish', (x) => x == 0 ? '–' : '${x.round()}')]),
      (l10n.matchStatBestLeg, [for (final p in players) v(p, 'bestLegDarts', (x) => '${x.round()}')]),
      (
        l10n.matchStatScores,
        [
          for (final p in players)
            p.stats.isEmpty ? '–' : '${v(p, 'count100', (x) => '${x.round()}')} / ${v(p, 'count140', (x) => '${x.round()}')} / ${v(p, 'count180', (x) => '${x.round()}')}',
        ],
      ),
      (l10n.matchStatDarts, [for (final p in players) v(p, 'darts', (x) => '${x.round()}')]),
    ];
    final won = e.won;
    final winner = won == null ? null : (won ? detail.me : null);
    return AppCard(
      key: const Key('session-match-result'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Kicker(l10n.matchResultTitle),
          const SizedBox(height: AppSpacing.s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  score,
                  key: const Key('session-match-score'),
                  style: look.scoreMedium.copyWith(
                    color: won == null ? theme.colorScheme.onSurface : (won ? colors.success : colors.danger),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(sets ? l10n.matchSets : l10n.matchLegs, style: theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Table(
                columnWidths: const {0: FlexColumnWidth(1.4)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    children: [
                      const SizedBox.shrink(),
                      for (final (i, p) in players.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s),
                          child: Text(
                            p.name,
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: winner == i || (won == false && i != detail.me && players.length == 2) ? colors.success : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (final (label, values) in rows)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                          child: Text(label, style: theme.textTheme.bodySmall),
                        ),
                        for (final value in values)
                          Text(
                            value,
                            textAlign: TextAlign.end,
                            style: look.chipNumber.copyWith(fontSize: 15, color: theme.colorScheme.onSurface),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (!known) ...[
            const SizedBox(height: AppSpacing.s),
            Text(l10n.histOpponentsUnknown, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// Verlauf der Aufnahmen und, wenn Positionen gespeichert sind, die Heatmap.
class _ChartAndHeat extends StatelessWidget {
  const _ChartAndHeat({required this.detail, required this.wide});
  final SessionDetail detail;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final values = detail.chartValues;
    final scores = [for (final v in detail.visits) if (!v.bust) v.score];
    final average = detail.chart == VisitChart.score && detail.visits.isNotEmpty
        ? detail.visits.fold<int>(0, (a, v) => a + v.score) / detail.visits.length
        : null;
    final chart = ChartCard(
      key: const Key('session-chart'),
      title: switch (detail.chart) {
        VisitChart.score => l10n.histChartScore,
        VisitChart.total => l10n.histChartTotal,
        VisitChart.hits => l10n.histChartHits,
        VisitChart.marks => l10n.histChartMarks,
      },
      trailing: average == null || scores.isEmpty ? null : Text(l10n.histChartAverage(formatDecimal(average))),
      child: SizedBox(
        height: 220,
        child: VisitValuesChart(
          values: values,
          line: detail.chart == VisitChart.total,
          average: average,
          maxY: detail.chart == VisitChart.hits ? 3 : null,
          highlight: {
            for (final (i, v) in detail.visits.indexed)
              if (v.checkout) i,
          },
        ),
      ),
    );
    if (detail.positions.isEmpty) return chart;
    final heat = ChartCard(
      key: const Key('session-heatmap'),
      title: l10n.statsHeatmap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: AspectRatio(aspectRatio: 1, child: DartboardView(heat: detail.positions, showHeat: true)),
      ),
    );
    return TwoColumns(wide: wide, left: chart, right: heat);
  }
}

/// Jede Aufnahme, bei Matches und X01 mit mehreren Legs je Leg.
class _Visits extends StatelessWidget {
  const _Visits({required this.detail});
  final SessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final attempts = detail.finishAttempts;
    final ignored = detail.visits.any((v) => v.darts.any((d) => !d.counted));
    return Column(
      key: const Key('session-visits'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          l10n.histVisits,
          trailing: Text(l10n.histVisitsCount(detail.visits.length), style: theme.textTheme.bodySmall),
        ),
        if (attempts > 0) ...[
          Text(
            l10n.histFinishAttempts(detail.finishHits, attempts),
            key: const Key('session-finish-attempts'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (attempts > 0 || ignored) ...[
          Wrap(
            spacing: AppSpacing.l,
            runSpacing: AppSpacing.xs,
            children: [
              if (attempts > 0) ...[
                _Legend(color: colors.success, label: l10n.histLegendFinishHit),
                _Legend(color: colors.danger, label: l10n.histLegendFinishMiss),
              ],
              if (ignored)
                Text(
                  l10n.histLegendIgnored,
                  style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough, color: colors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
        ],
        if (detail.entry.isMatch) ...[
          Text(
            detail.legsKnown ? l10n.histOwnThrowsOnly : '${l10n.histOwnThrowsOnly} ${l10n.histLegsUnknown}',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.m),
        ],
        for (final (i, leg) in detail.legs.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.l),
          if (leg.number > 0) _LegHeader(detail: detail, leg: leg),
          AppCard(
            key: Key('session-leg-${leg.number}'),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                _VisitRow.header(afterKey: detail.afterKey, value: detail.value),
                for (final v in leg.visits) _VisitRow(visit: v, afterKey: detail.afterKey, value: detail.value),
                if (leg.visits.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    child: Text(l10n.histOwnThrowsOnly, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(context.look.radiusS.clamp(2, 4).toDouble()),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

/// „Leg 2“ mit Sieger und Checkout.
class _LegHeader extends StatelessWidget {
  const _LegHeader({required this.detail, required this.leg});
  final SessionDetail detail;
  final HistoryLeg leg;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final format = detail.entry.isMatch ? MatchFormat.fromJson(detail.entry.details['format'] ?? detail.entry.config) : null;
    final title = format != null && format.usesSets ? l10n.matchLegSetNumber(leg.set, leg.number) : l10n.matchLegNumber(leg.number);
    final w = leg.winner;
    final mine = w == null ? null : w == detail.me || !detail.entry.isMatch;
    final name = w == null || detail.players.length <= w ? null : detail.players[w].name;
    final String info;
    if (w == null) {
      info = l10n.histLegOpen;
    } else if (name != null && leg.checkout != null && leg.winnerDarts != null) {
      info = l10n.histLegWon(name, leg.checkout!, leg.winnerDarts!);
    } else {
      info = name ?? '';
    }
    final color = mine == null ? colors.textMuted : (mine ? colors.success : colors.danger);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Row(
        children: [
          Container(width: 4, height: 18, color: color),
          const SizedBox(width: AppSpacing.s),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text(
              info,
              key: Key('session-leg-info-${leg.number}'),
              style: theme.textTheme.bodySmall?.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Aufnahme: Nummer, drei Darts, Punkte und Stand danach.
class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.visit, this.afterKey, this.value = VisitValue.points}) : isHeader = false;
  const _VisitRow.header({this.afterKey, this.value = VisitValue.points})
      : visit = null,
        isHeader = true;

  final HistoryVisit? visit;
  final String? afterKey;
  final VisitValue value;
  final bool isHeader;

  static const double _numberWidth = 30;
  static const double _valueWidth = 54;

  /// Breiter, damit „Treffer“ als Überschrift passt.
  static const double _scoreWidth = 66;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final pad = EdgeInsets.symmetric(horizontal: look.cardPadding * 0.75, vertical: isHeader ? AppSpacing.xs : AppSpacing.xxs + 1);
    final v = visit;
    if (v == null) {
      return Padding(
        padding: pad,
        child: Row(
          children: [
            const SizedBox(width: _numberWidth),
            Expanded(child: Kicker(l10n.statDarts)),
            SizedBox(
              width: _scoreWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: Kicker(switch (value) {
                  VisitValue.points => l10n.statPoints,
                  VisitValue.hits => l10n.statHitsOnTarget,
                  VisitValue.marks => l10n.statsMetricMarks,
                }),
              ),
            ),
            if (afterKey != null)
              SizedBox(width: _valueWidth, child: Align(alignment: Alignment.centerRight, child: Kicker(l10n.statLabel(afterKey!)))),
          ],
        ),
      );
    }
    final number = look.chipNumber.copyWith(fontSize: 15, color: theme.colorScheme.onSurface);
    return Padding(
      padding: pad,
      child: Row(
        children: [
          SizedBox(width: _numberWidth, child: Text('${v.number}', style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted))),
          Expanded(
            child: Row(
              children: [
                for (final d in v.darts.take(4)) ...[
                  _DartCell(dart: d),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ],
            ),
          ),
          SizedBox(
            width: _scoreWidth,
            child: Text(
              v.bust ? l10n.histBust : '${v.valueOf(value)}',
              textAlign: TextAlign.right,
              style: v.bust
                  ? number.copyWith(color: colors.danger)
                  : value == VisitValue.points && v.score >= 100
                      ? number.copyWith(color: colors.record)
                      : number,
            ),
          ),
          if (afterKey != null)
            SizedBox(
              width: _valueWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: v.checkout
                    ? Icon(Icons.check_circle_rounded, size: 18, color: colors.success)
                    : v.failed
                        ? Icon(Icons.cancel_rounded, size: 18, color: colors.textMuted)
                        : Text(v.after ?? '', style: number.copyWith(color: colors.textMuted)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ein Dart als kurzes Feld („T20“), Darts aufs Finish mit Rahmen.
class _DartCell extends StatelessWidget {
  const _DartCell({required this.dart});
  final HistoryDart dart;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final look = context.look;
    final s = dart.segment;
    final Color? frame = dart.finishAttempt ? (dart.hit ? colors.success : colors.danger) : null;
    final color = dart.counted ? segmentColor(context, s) : colors.textMuted.withValues(alpha: 0.6);
    return Container(
      width: 50,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: frame?.withValues(alpha: 0.12) ?? (dart.counted ? colors.surfaceHigh.withValues(alpha: 0.6) : null),
        border: frame == null ? null : Border.all(color: frame, width: 1.5),
        borderRadius: BorderRadius.circular(look.radiusS.clamp(2, 8).toDouble()),
      ),
      child: Text(
        s.name,
        style: look.chipNumber.copyWith(
          fontSize: 14,
          color: color,
          decoration: dart.counted ? null : TextDecoration.lineThrough,
        ),
      ),
    );
  }
}
