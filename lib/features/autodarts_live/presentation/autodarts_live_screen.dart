import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/widgets/fullscreen_button.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/presentation/dartboard_view.dart';
import '../../dart_source/domain/dart_event.dart';
import '../../dart_source/domain/dart_source.dart';
import '../../dart_source/presentation/dart_source_providers.dart';
import '../../dart_source/presentation/source_status_badge.dart';
import '../../games/domain/engine/game_display.dart';
import '../domain/live_recorder.dart';
import '../domain/live_stats.dart';
import '../domain/live_x01.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import 'autodarts_live_controller.dart';
import 'live_correction_sheet.dart';

/// Autodarts Live: DartLab läuft neben dem Browser (play.autodarts.io) und
/// schreibt die Darts vom eigenen Board mit.
class AutodartsLiveScreen extends ConsumerWidget {
  const AutodartsLiveScreen({super.key});

  Future<void> _end(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final darts = ref.read(autodartsLiveProvider).stats.darts;
    await ref.read(autodartsLiveProvider.notifier).end();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(darts > 0 ? l10n.liveSaved(darts) : l10n.liveNothingSaved)));
    context.go(Routes.games);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final live = ref.watch(autodartsLiveProvider);
    final narrow = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      appBar: AppPageBar(
        title: Text(l10n.liveTitle),
        actions: [
          if (live.listening) SourceStatusBadge(compact: narrow),
          if (!narrow) const FullscreenButton(),
        ],
      ),
      body: !live.listening && !live.ended
          ? ComingSoon(
              key: const Key('live-needs-autodarts'),
              icon: Icons.videocam_rounded,
              title: l10n.liveNeedsAutodarts,
              text: l10n.liveNeedsAutodartsText,
              action: FilledButton.icon(
                key: const Key('live-switch-source'),
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .update((s) => s.copyWith(sourceKind: DartSourceKind.autodartsLocal)),
                icon: const Icon(Icons.videocam_rounded),
                label: Text(l10n.liveSwitchSource),
              ),
            )
          : LayoutBuilder(builder: (context, c) {
              final look = context.look;
              final wide = c.maxWidth >= 900;
              final page = look.pagePadding(c.maxWidth >= kWidePage);
              final gap = look.gridGap;
              final end = SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('live-end'),
                  onPressed: live.ended ? null : () => _end(context, ref),
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(l10n.liveEnd),
                ),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ListView(
                        key: const Key('live-left'),
                        padding: EdgeInsets.fromLTRB(page, look.page * 0.5, gap / 2, page),
                        children: [
                          _HintCard(x01: live.x01 != null),
                          SizedBox(height: gap),
                          _VisitPanel(live: live, large: true),
                          SizedBox(height: gap),
                          _StatsCard(live: live),
                          SizedBox(height: gap),
                          _RecentCard(live: live),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: (c.maxWidth * 0.4).clamp(360, 520),
                      child: ListView(
                        key: const Key('live-right'),
                        padding: EdgeInsets.fromLTRB(gap / 2, look.page * 0.5, page, page),
                        children: [
                          _X01Card(live: live),
                          SizedBox(height: gap),
                          _HeatCard(live: live, maxHeight: 300),
                          SizedBox(height: gap),
                          _DistributionCard(stats: live.stats),
                          SizedBox(height: gap),
                          end,
                        ],
                      ),
                    ),
                  ],
                );
              }
              return ListView(
                key: const Key('live-list'),
                padding: EdgeInsets.fromLTRB(page, AppSpacing.s, page, page),
                children: [
                  _HintCard(x01: live.x01 != null),
                  SizedBox(height: gap),
                  _VisitPanel(live: live, large: false),
                  SizedBox(height: gap),
                  _StatsCard(live: live),
                  SizedBox(height: gap),
                  _X01Card(live: live),
                  SizedBox(height: gap),
                  _HeatCard(live: live),
                  SizedBox(height: gap),
                  _DistributionCard(stats: live.stats),
                  SizedBox(height: gap),
                  _RecentCard(live: live),
                  SizedBox(height: gap),
                  end,
                ],
              );
            }),
    );
  }
}

String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Hinweis, wie der Modus gedacht ist, und Verbindungsprobleme.
class _HintCard extends ConsumerWidget {
  const _HintCard({required this.x01});

  /// Mit „X01 mitzählen“ entfällt der Hinweis „kein Restwert“.
  final bool x01;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final status = ref.watch(sourceStatusProvider).value ?? ref.watch(dartSourceProvider).status;
    final (host, port) = ref.watch(settingsProvider.select((s) => (s.autodartsHost, s.autodartsPort)));
    final offline = !status.isLive && status.phase != SourcePhase.idle;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: Icons.hearing_rounded, size: context.look.id == DartLookId.lab ? 36 : 44),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.liveHint, key: const Key('live-hint'), style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.liveHintDetail, style: theme.textTheme.bodySmall),
                if (!x01) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(l10n.liveLimits, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.liveFixHint, key: const Key('live-fix-hint'), style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
                if (offline) ...[
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    l10n.liveNotConnected('$host:$port'),
                    key: const Key('live-offline'),
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.warning),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// „X01 mitzählen“: Schalter, Startwert und Ausstieg.
class _X01Card extends ConsumerWidget {
  const _X01Card({required this.live});
  final LiveViewState live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final config = live.x01Config;
    final controller = ref.read(autodartsLiveProvider.notifier);
    return AppCard(
      padding: EdgeInsets.symmetric(horizontal: context.look.cardPadding, vertical: AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('live-x01-switch'),
            contentPadding: EdgeInsets.zero,
            value: config != null,
            onChanged: live.ended ? null : (on) => controller.setX01(on ? const LiveX01Config() : null),
            title: Text(l10n.liveX01, style: theme.textTheme.titleMedium),
            subtitle: Text('${config == null ? l10n.liveX01Off : l10n.liveX01Hint} ${l10n.liveX01NewSession}'),
          ),
          if (config != null) ...[
            Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.s,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<int>(
                  key: const Key('live-x01-start'),
                  showSelectedIcon: false,
                  segments: [
                    for (final v in LiveX01Config.startScores) ButtonSegment(value: v, label: Text('$v')),
                  ],
                  selected: {config.startScore},
                  onSelectionChanged: live.ended
                      ? null
                      : (v) => controller.setX01(LiveX01Config(startScore: v.first, outMode: config.outMode)),
                ),
                SegmentedButton<OutMode>(
                  key: const Key('live-x01-out'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: OutMode.straight, label: Text(l10n.matchOutStraight)),
                    ButtonSegment(value: OutMode.double, label: Text(l10n.matchOutDouble)),
                    ButtonSegment(value: OutMode.master, label: Text(l10n.matchOutMaster)),
                  ],
                  selected: {config.outMode},
                  onSelectionChanged: live.ended
                      ? null
                      : (v) => controller.setX01(LiveX01Config(startScore: config.startScore, outMode: v.first)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
          ],
        ],
      ),
    );
  }
}

/// Aktuelle (oder letzte) Aufnahme mit drei Plätzen; mit X01 der Rest,
/// der Checkout-Weg und die Knöpfe fürs Leg-Ende.
class _VisitPanel extends ConsumerWidget {
  const _VisitPanel({required this.live, required this.large});
  final LiveViewState live;
  final bool large;

  void _legEnd(BuildContext context, WidgetRef ref, LegMarkKind kind) {
    ref.read(autodartsLiveProvider.notifier).markLeg(kind);
    final start = live.x01Config?.startScore ?? 501;
    if (kind == LegMarkKind.lost) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.liveLegLostDone(start))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final x01 = live.x01;
    final showLast = x01 == null && live.current.isEmpty && live.lastVisit != null;
    final darts = showLast ? live.lastVisit! : live.current;
    final score = darts.fold<int>(0, (a, d) => a + d.score);
    final waiting = live.current.isEmpty && live.lastVisit == null;
    // Weg bzw. Stell-Vorschlag nur, solange die Aufnahme noch Darts hat.
    final open = x01 != null && x01.dartsLeft > 0;
    final route = open ? x01.suggestion : null;
    final setup = open && route == null ? x01.setup : null;
    final plan = route ?? setup?.darts;
    final planColor = route != null ? colors.highlight : colors.setupHint;
    final event = x01?.lastEvent;
    // Nummer (ab 0) der angezeigten Aufnahme für die Korrektur.
    final shownVisit = showLast ? live.closedCount - 1 : live.closedCount;
    final fixable = !live.ended;
    final String label;
    final String value;
    if (x01 != null) {
      label = l10n.statRemaining;
      value = '${x01.remaining}';
    } else {
      label = showLast ? l10n.liveVisitLast : l10n.liveVisitCurrent;
      value = waiting ? '–' : '$score';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScorePanel(
          label: label,
          trailing: x01 != null
              ? l10n.liveLegInfo(x01.legs.length + 1, x01.legsWon, x01.legsLost)
              : (live.stats.visits == 0 ? null : '#${live.stats.visits}'),
          value: Text(
            value,
            key: const Key('live-visit-score'),
            style: ScorePanel.valueStyle(context, hero: false, compact: x01 == null || !large),
          ),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (x01 != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.s),
                  child: Row(
                    children: [
                      Kicker(l10n.visitLabel),
                      const SizedBox(width: AppSpacing.s),
                      if (route != null && route.isNotEmpty)
                        Expanded(
                          child: Text(
                            context.look.caps(l10n.visitRoute),
                            key: const Key('live-route-label'),
                            overflow: TextOverflow.ellipsis,
                            style: context.look.kicker.copyWith(color: colors.highlight),
                          ),
                        )
                      else if (setup != null)
                        Expanded(
                          child: Text(
                            context.look.caps(l10n.visitSetup(setup.leave)),
                            overflow: TextOverflow.ellipsis,
                            style: context.look.kicker.copyWith(color: colors.setupHint),
                          ),
                        )
                      else
                        const Spacer(),
                      Text(
                        '$score',
                        style: context.look.chipNumber.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontSize: (context.look.chipNumber.fontSize ?? 18) + 4,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < LiveRecorder.dartsPerVisit; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                        child: Opacity(
                          opacity: showLast ? 0.6 : 1,
                          child: FittedBox(
                            child: DartChip(
                              key: Key('live-slot-$i'),
                              segment: i < darts.length ? darts[i].segment : null,
                              planned: plan != null && i >= darts.length && i - darts.length < plan.length
                                  ? plan[i - darts.length]
                                  : null,
                              plannedColor: planColor,
                              label: '${i + 1}',
                              large: true,
                              edited: i < darts.length && LiveRecorder.isManual(darts[i]),
                              editedTooltip: l10n.liveFixEdited,
                              onTap: !fixable
                                  ? null
                                  : i < darts.length
                                      ? () => fixLiveDart(
                                            context,
                                            ref,
                                            visit: shownVisit,
                                            dart: i,
                                            current: darts[i],
                                            visitLength: darts.length,
                                          )
                                      : i == darts.length
                                          ? () => addLiveDart(context, ref, visit: shownVisit)
                                          : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (waiting && x01 == null) ...[
                const SizedBox(height: AppSpacing.s),
                Text(l10n.liveWaiting, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (event != null) ...[
          const SizedBox(height: AppSpacing.m),
          LookBanner(
            text: event == GameEventType.bust ? l10n.evBust : l10n.evCheckout('${x01!.legs.lastOrNull?.checkout ?? ''}'),
            textKey: const Key('live-event'),
            color: event == GameEventType.bust ? colors.danger : colors.success,
          ),
        ],
        if (x01 != null) ...[
          const SizedBox(height: AppSpacing.m),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('live-leg-lost'),
                  onPressed: live.ended || x01.legDarts == 0 ? null : () => _legEnd(context, ref, LegMarkKind.lost),
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(l10n.liveLegLost),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              TextButton.icon(
                key: const Key('live-leg-restart'),
                onPressed: live.ended || x01.legDarts == 0 ? null : () => _legEnd(context, ref, LegMarkKind.restart),
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(l10n.liveLegRestart),
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Kennzahlen der laufenden Session.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.live});
  final LiveViewState live;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final look = context.look;
    final colors = context.dartColors;
    final s = live.stats;
    final since = live.sessionStartedAt;
    final valueStyle = look.statValue.copyWith(
      color: theme.colorScheme.onSurface,
      fontSize: (look.statValue.fontSize ?? 30) * (look.id == DartLookId.tv ? 0.72 : 0.75),
    );
    final x = live.x01;
    final cells = [
      if (x != null) ...[
        (l10n.statAverage, formatDecimal(x.average), const Key('live-x01-average')),
        (l10n.statFirst9Average, formatDecimal(x.first9), const Key('live-first9')),
        (l10n.statCheckoutRate, formatPercent(x.checkoutRate), const Key('live-checkout-rate')),
        (l10n.liveLegs, l10n.liveLegsValue(x.legsWon, x.legsLost), const Key('live-legs')),
      ],
      (l10n.statDarts, '${s.darts}', const Key('live-darts')),
      (l10n.statRawAverage, formatDecimal(s.rawAverage), const Key('live-average')),
      if (x == null) (l10n.statVisits, '${s.visits}', const Key('live-visits')),
      (l10n.statBestVisit, s.visits == 0 ? '–' : '${s.bestVisit}', const Key('live-best')),
      (l10n.liveScores, '${s.count100} / ${s.count140} / ${s.count180}', const Key('live-scores')),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Kicker(l10n.liveStatsTitle)),
              if (since != null)
                Text(
                  l10n.liveSessionSince(_clock(since)),
                  key: const Key('live-since'),
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth < 300 ? 2 : (c.maxWidth < 520 ? 3 : (cells.length > 5 ? 4 : 5));
            final w = (c.maxWidth - (cols - 1) * AppSpacing.m) / cols;
            return Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.m + 2,
              children: [
                for (final (label, value, key) in cells)
                  SizedBox(
                    width: w,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Kicker(label, maxLines: 2),
                        const SizedBox(height: AppSpacing.xs),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(value, key: key, style: valueStyle),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: AppSpacing.m),
          Text(l10n.liveRawAverageHint, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
          Text(
            l10n.livePauseRule(LiveRecorder.defaultPauseLimit.inMinutes),
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Heatmap der Session, darüber die Darts der laufenden Aufnahme.
class _HeatCard extends StatelessWidget {
  const _HeatCard({required this.live, this.maxHeight = 420});
  final LiveViewState live;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hits = <BoardPoint>[for (final d in live.current) ?d.position];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Kicker(l10n.liveHeatmap),
          const SizedBox(height: AppSpacing.m),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: AspectRatio(
              aspectRatio: 1,
              child: DartboardView(
                key: const Key('live-heatmap'),
                heat: live.stats.heat,
                showHeat: true,
                hits: hits,
                lastSegment: live.current.isEmpty ? null : live.current.last.segment,
                hitSerial: live.dartSerial,
                semanticsLabel: l10n.liveHeatmap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Anteil Triple / Doppel / Single / Daneben.
class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.stats});
  final LiveStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final rows = [
      (l10n.liveTriple, stats.triples, stats.tripleShare, colors.tripleHit),
      (l10n.liveDouble, stats.doubles, stats.doubleShare, colors.doubleHit),
      (l10n.liveSingle, stats.singles, stats.singleShare, theme.colorScheme.primary),
      (l10n.liveMiss, stats.misses, stats.missShare, colors.textMuted),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Kicker(l10n.liveDistribution),
          const SizedBox(height: AppSpacing.m),
          for (final (i, (label, count, share, color)) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s + 2),
            Row(
              children: [
                SizedBox(width: 72, child: Text(label, style: theme.textTheme.bodyMedium)),
                Expanded(child: LookProgressBar(value: share ?? 0, color: color)),
                SizedBox(
                  width: 92,
                  child: Text(
                    '${formatPercent(share)} · $count',
                    key: Key('live-share-$i'),
                    textAlign: TextAlign.right,
                    style: look.chipNumber.copyWith(fontSize: 14, color: theme.colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Die letzten abgeschlossenen Aufnahmen zum Abgleich mit dem Match.
class _RecentCard extends ConsumerWidget {
  const _RecentCard({required this.live});
  final LiveViewState live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final look = context.look;
    final colors = context.dartColors;
    final style = look.chipNumber.copyWith(fontSize: 16);
    final visits = live.recentVisits;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Kicker(l10n.liveRecent),
          const SizedBox(height: AppSpacing.s),
          if (visits.isEmpty)
            Text('–', style: theme.textTheme.bodySmall)
          else
            for (final (i, v) in visits.indexed)
              Builder(builder: (context) {
                // Nummer der Aufnahme: die neueste abgeschlossene steht oben.
                final visit = live.closedCount - 1 - i;
                return Padding(
                  key: Key('live-recent-$i'),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text('#${visit + 1}', style: style.copyWith(color: colors.textMuted, fontSize: 13)),
                      ),
                      for (var d = 0; d < LiveRecorder.dartsPerVisit; d++)
                        SizedBox(
                          width: 64,
                          child: d < v.length
                              ? _RecentDart(
                                  key: Key('live-recent-$i-dart-$d'),
                                  dart: v[d],
                                  style: style,
                                  onTap: live.ended
                                      ? null
                                      : () => fixLiveDart(
                                            context,
                                            ref,
                                            visit: visit,
                                            dart: d,
                                            current: v[d],
                                            visitLength: v.length,
                                          ),
                                )
                              : d == v.length && !live.ended
                                  ? _RecentAdd(
                                      key: Key('live-recent-$i-add'),
                                      onTap: () => addLiveDart(context, ref, visit: visit),
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                                      child: Text('–', style: style.copyWith(color: colors.textMuted)),
                                    ),
                        ),
                      const Spacer(),
                      Text('${v.fold<int>(0, (a, t) => a + t.score)}', style: style.copyWith(color: theme.colorScheme.onSurface)),
                    ],
                  ),
                );
              }),
        ],
      ),
    );
  }
}

/// Ein Dart in der Liste der letzten Aufnahmen; antippen zum Korrigieren.
/// Von Hand gesetzte Darts tragen einen kleinen Stift.
class _RecentDart extends StatelessWidget {
  const _RecentDart({super.key, required this.dart, required this.style, required this.onTap});
  final DartThrow dart;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final primary = Theme.of(context).colorScheme.primary;
    final edited = LiveRecorder.isManual(dart);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.s),
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                dart.segment.name,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: segmentColor(context, dart.segment)),
              ),
            ),
            if (edited) ...[
              const SizedBox(width: 3),
              Tooltip(message: l10n.liveFixEdited, child: Icon(Icons.edit_rounded, size: 12, color: primary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// „+“ hinter den Darts einer Aufnahme mit weniger als drei Darts.
class _RecentAdd extends StatelessWidget {
  const _RecentAdd({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.s),
      onTap: onTap,
      child: Tooltip(
        message: context.l10n.liveFixAddDart,
        child: SizedBox(
          height: 36,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Icon(Icons.add_rounded, size: 18, color: context.dartColors.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
