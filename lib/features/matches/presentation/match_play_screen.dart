import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_theme.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/widgets/fullscreen_button.dart';
import '../../board/domain/segment.dart';
import '../../board/presentation/dartboard_view.dart';
import '../../dart_source/data/manual_source.dart';
import '../../dart_source/data/simulator_source.dart';
import '../../dart_source/presentation/dart_source_providers.dart';
import '../../dart_source/presentation/source_status_badge.dart';
import '../../games/domain/engine/game_display.dart';
import '../../simulator/presentation/manual_keypad.dart';
import '../../simulator/presentation/segment_picker.dart';
import '../domain/match_session.dart';
import '../domain/x01_match.dart';
import 'match_controller.dart';
import 'match_routes.dart';
import 'match_texts.dart';

/// Spielansicht eines Matches: Anzeigetafel je Spieler, Board mit den Darts
/// der laufenden Aufnahme (auch denen des Bots) und die Aufnahme-Karte.
class MatchPlayScreen extends ConsumerWidget {
  const MatchPlayScreen({super.key});

  static Future<void> leave(BuildContext context, WidgetRef ref) async {
    final state = ref.read(matchControllerProvider);
    final inTournament = state?.setup.tournamentMatch != null;
    if (state != null && !state.ended) {
      final l10n = context.l10n;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(inTournament ? l10n.matchPauseTitle : l10n.matchLeaveTitle),
          content: Text(inTournament ? l10n.matchPauseText : l10n.matchLeaveText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.matchStay)),
            FilledButton(
              key: const Key('confirm-leave-match'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(inTournament ? l10n.matchPause : l10n.matchLeave),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(matchControllerProvider.notifier).close(keepForResume: inTournament);
    if (context.mounted) context.go(inTournament ? MatchRoutes.tournament : MatchRoutes.hub);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(matchControllerProvider);
    if (state == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: FilledButton(onPressed: () => context.go(MatchRoutes.hub), child: Text(l10n.matchesTitle)),
        ),
      );
    }
    final source = ref.watch(dartSourceProvider);
    final match = state.match;
    final visit = [for (final i in state.session.currentVisitIndexes) state.session.records[i]];
    final route = state.humanTurn && !match.visitClosed ? match.suggestion : null;

    final board = DartboardView(
      key: const Key('match-board'),
      hits: [for (final r in visit) ?r.dart.position],
      lastSegment: visit.isEmpty ? null : visit.last.dart.segment,
      hitSerial: state.session.records.length,
      highlighted: route == null || route.isEmpty ? const {} : {route.first},
      onTap: !state.acceptsHumanDarts
          ? null
          : switch (source) {
              SimulatorSource() => (point, _) => source.throwAt(point),
              ManualSource() => (_, segment) => source.enter(segment),
              _ => null,
            },
    );

    final format = state.setup.format;
    final legLabel = format.usesSets
        ? l10n.matchLegSetNumber(match.setNumber, match.legNumber)
        : l10n.matchLegNumber(match.legNumber);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave(context, ref));
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('leave-match'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => leave(context, ref),
          ),
          title: Text(state.ended ? l10n.matchResultTitle : legLabel),
          actions: [
            SourceStatusBadge(compact: MediaQuery.sizeOf(context).width < 600),
            const SizedBox(width: AppSpacing.xs),
            const FullscreenButton(),
            const SizedBox(width: AppSpacing.s),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 900;
              if (wide) {
                return Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: board),
                      ),
                    ),
                    SizedBox(
                      width: 460,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(0, AppSpacing.l, AppSpacing.xl, AppSpacing.xl),
                        child: _Panel(state: state, route: route),
                      ),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.page),
                children: [
                  _Scoreboard(state: state, route: route),
                  const SizedBox(height: AppSpacing.m),
                  if (!state.ended) ...[
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: c.maxHeight * 0.45),
                      child: Center(child: board),
                    ),
                    const SizedBox(height: AppSpacing.m),
                  ],
                  _Panel(state: state, route: route, showScoreboard: false),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({required this.state, required this.route, this.showScoreboard = true});
  final MatchState state;
  final List<Segment>? route;
  final bool showScoreboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final source = ref.watch(dartSourceProvider);
    final controller = ref.read(matchControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showScoreboard) ...[_Scoreboard(state: state, route: route), const SizedBox(height: AppSpacing.m)],
        _EventBanner(state: state),
        if (state.ended) ...[
          _ResultCard(state: state),
          const SizedBox(height: AppSpacing.m),
          _ResultActions(state: state),
        ] else ...[
          _VisitCard(state: state, route: route),
          const SizedBox(height: AppSpacing.m),
          if (state.acceptsHumanDarts && source is ManualSource)
            ManualKeypad(source: source)
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('match-undo'),
                    onPressed: state.session.canUndo ? controller.undo : null,
                    icon: const Icon(Icons.undo_rounded),
                    label: Text(l10n.boardUndo),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('match-next'),
                    onPressed: state.humanTurn && state.match.physicalDartsInVisit > 0 ? controller.nextVisit : null,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: Text(l10n.boardNext),
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.s),
          Center(
            child: TextButton.icon(
              key: const Key('match-corrections'),
              onPressed: () => _showCorrections(context),
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(l10n.fixOpen),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}

/// Anzeigetafel: eine Karte je Spieler.
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.state, required this.route});
  final MatchState state;
  final List<Segment>? route;

  @override
  Widget build(BuildContext context) {
    final players = state.setup.players;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < players.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.m),
            Expanded(
              child: _PlayerCard(state: state, index: i, route: i == state.match.current ? route : null),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.state, required this.index, required this.route});
  final MatchState state;
  final int index;
  final List<Segment>? route;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final match = state.match;
    final player = state.setup.players[index];
    final p = match.players[index];
    final active = !state.ended && match.current == index;
    final won = match.winner == index;
    final accent = won ? colors.success : theme.colorScheme.primary;
    final format = state.setup.format;
    final starter = !state.ended && match.legStarter == index;

    Widget stat(String label, String value, {Key? key}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: colors.textMuted)),
        Text(
          value,
          key: key,
          style: theme.textTheme.titleMedium?.copyWith(fontFeatures: AppTypography.tabular),
        ),
      ],
    );

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Markierung, wer am Zug ist (bzw. gewonnen hat).
          AnimatedContainer(
            key: Key('match-active-$index-$active'),
            duration: AppDurations.medium,
            height: 4,
            margin: const EdgeInsets.only(bottom: AppSpacing.s),
            decoration: BoxDecoration(
              color: active || won ? accent : colors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          ),
          Row(
            children: [
              Icon(
                player.isBot ? Icons.smart_toy_outlined : Icons.person_rounded,
                size: 18,
                color: active ? accent : colors.textMuted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(player.name, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              ),
              if (starter)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: colors.highlight, shape: BoxShape.circle),
                ),
              if (won) Icon(Icons.emoji_events_rounded, size: 18, color: colors.success),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${p.remaining}',
              key: Key('match-remaining-$index'),
              style: AppTypography.scoreLarge.copyWith(color: active ? theme.colorScheme.onSurface : colors.textMuted),
            ),
          ),
          SizedBox(
            height: 20,
            child: route != null && route!.isNotEmpty
                ? Text(
                    route!.map((s) => s.name).join(' · '),
                    key: Key('match-route-$index'),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(color: colors.highlight),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.l,
            runSpacing: AppSpacing.xs,
            children: [
              if (format.usesSets) stat(l10n.matchSets, '${p.sets}', key: Key('match-sets-$index')),
              stat(l10n.matchLegs, '${format.usesSets ? p.legs : p.totalLegs}', key: Key('match-legs-$index')),
              stat(l10n.matchAvg, formatDecimal(p.average)),
              stat(l10n.matchDarts, '${p.darts}', key: Key('match-darts-$index')),
              if (p.lastVisit != null) stat(l10n.matchLastVisit, '${p.lastVisit}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventBanner extends StatelessWidget {
  const _EventBanner({required this.state});
  final MatchState state;

  static const _priority = [
    MatchEventType.matchWon,
    MatchEventType.setWon,
    MatchEventType.legWon,
    MatchEventType.bust,
    MatchEventType.max,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    MatchEvent? event;
    for (final t in _priority) {
      event ??= state.events.where((e) => e.type == t).firstOrNull;
    }
    final color = switch (event?.type) {
      MatchEventType.bust => colors.danger,
      null => Theme.of(context).colorScheme.primary,
      _ => colors.success,
    };
    final names = [for (final p in state.setup.players) p.name];
    return AnimatedSwitcher(
      duration: AppDurations.medium,
      transitionBuilder: (child, a) => SizeTransition(
        sizeFactor: a,
        child: FadeTransition(opacity: a, child: child),
      ),
      child: event == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              key: ValueKey(state.revision),
              padding: const EdgeInsets.only(bottom: AppSpacing.m),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.m),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadii.m),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  l10n.matchEventText(event, names),
                  key: const Key('match-event'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color),
                ),
              ),
            ),
    );
  }
}

/// Die Darts der laufenden Aufnahme. Bei Menschen zeigen offene Plätze den
/// Checkout-Weg in Gelb, geworfene Darts lassen sich antippen und korrigieren.
class _VisitCard extends ConsumerWidget {
  const _VisitCard({required this.state, required this.route});
  final MatchState state;
  final List<Segment>? route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final match = state.match;
    final session = state.session;
    final indexes = session.currentVisitIndexes;
    final thrown = indexes.length;
    final player = state.setup.players[match.current];
    final next = state.setup.players[match.nextPlayer];
    final status = match.visitClosed && match.nextPlayer != match.current
        ? l10n.matchWaitTakeout(next.name)
        : player.isBot
        ? l10n.matchBotThrowing(player.name)
        : l10n.matchTurnOf(player.name);

    Future<void> fix(int slot) async {
      final index = indexes[slot];
      final picked = await showSegmentPicker(
        context,
        title: l10n.fixTitle(slot + 1),
        subtitle: l10n.fixCurrent(session.records[index].dart.segment.name),
      );
      if (picked != null) ref.read(matchControllerProvider.notifier).correct(index, picked);
    }

    final r = route;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    key: const Key('match-status'),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: player.isBot ? colors.textMuted : theme.colorScheme.primary,
                    ),
                  ),
                ),
                Text(
                  match.visitBust ? 'BUST' : '${match.visitScore}',
                  key: const Key('match-visit-score'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFeatures: AppTypography.tabular,
                    color: match.visitBust ? colors.danger : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                    child: FittedBox(
                      child: DartChip(
                        key: Key('match-dart-$i'),
                        segment: i < thrown ? session.records[indexes[i]].dart.segment : null,
                        planned: r != null && i >= thrown && i - thrown < r.length ? r[i - thrown] : null,
                        label: '${i + 1}',
                        large: true,
                        onTap: i < thrown && !player.isBot ? () => fix(i) : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.state});
  final MatchState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final match = state.match;
    final players = state.setup.players;
    final format = state.setup.format;
    final ps = match.players;
    final score = format.usesSets ? ps.map((p) => p.sets).join(' : ') : ps.map((p) => p.totalLegs).join(' : ');

    final rows = <(String, List<String>)>[
      if (format.usesSets) (l10n.matchStatSets, [for (final p in ps) '${p.sets}']),
      (l10n.matchStatLegs, [for (final p in ps) '${p.totalLegs}']),
      (l10n.matchStatAverage, [for (final p in ps) formatDecimal(p.average)]),
      (l10n.matchStatFirst9, [for (final p in ps) formatDecimal(p.first9Average)]),
      (l10n.matchStatCheckout, [for (final p in ps) formatPercent(p.checkoutRate)]),
      (l10n.matchStatHighFinish, [for (final p in ps) p.highestFinish == 0 ? '–' : '${p.highestFinish}']),
      (l10n.matchStatBestLeg, [for (final p in ps) p.bestLegDarts == null ? '–' : '${p.bestLegDarts}']),
      (l10n.matchStatScores, [for (final p in ps) '${p.count100} / ${p.count140} / ${p.count180}']),
      (l10n.matchStatDarts, [for (final p in ps) '${p.darts}']),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.matchResultTitle.toUpperCase(), style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.s),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              score,
              key: const Key('match-final-score'),
              style: AppTypography.scoreLarge.copyWith(color: colors.success),
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          Table(
            columnWidths: const {0: FlexColumnWidth(1.4)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  const SizedBox.shrink(),
                  for (var i = 0; i < players.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s),
                      child: Text(
                        players[i].name,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(color: match.winner == i ? colors.success : null),
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
                    for (final v in values)
                      Text(
                        v,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.titleSmall?.copyWith(fontFeatures: AppTypography.tabular),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultActions extends ConsumerWidget {
  const _ResultActions({required this.state});
  final MatchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final inTournament = state.setup.tournamentMatch != null;
    final controller = ref.read(matchControllerProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('match-done'),
            onPressed: () async {
              await controller.close();
              if (context.mounted) context.go(inTournament ? MatchRoutes.tournament : MatchRoutes.hub);
            },
            icon: const Icon(Icons.check_rounded),
            label: Text(l10n.matchDone),
          ),
        ),
        if (inTournament) ...[
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: FilledButton.icon(
              key: const Key('match-to-tournament'),
              onPressed: () async {
                await controller.close();
                if (context.mounted) context.go(MatchRoutes.tournament);
              },
              icon: const Icon(Icons.account_tree_rounded),
              label: Text(l10n.matchBackToTournament),
            ),
          ),
        ] else ...[
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: FilledButton.icon(
              key: const Key('match-rematch'),
              onPressed: () {
                final s = state.setup;
                // Revanche: der andere fängt an.
                final rematch = MatchSetup(
                  format: s.format,
                  players: s.players,
                  firstStarter: (s.firstStarter + 1) % s.players.length,
                );
                unawaited(controller.start(rematch));
              },
              icon: const Icon(Icons.replay_rounded),
              label: Text(l10n.matchRematch),
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> _showCorrections(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (context) => const _CorrectionsSheet(),
);

/// Eigene Darts im laufenden Leg, je Aufnahme; jeder lässt sich korrigieren.
class _CorrectionsSheet extends ConsumerWidget {
  const _CorrectionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(matchControllerProvider);
    if (state == null) return const SizedBox.shrink();
    final records = state.session.records;
    final leg = state.match.legNumber;
    final visits = <int, List<int>>{};
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      if (r.leg != leg || state.setup.players[r.player].isBot) continue;
      visits.putIfAbsent(r.visitSerial, () => []).add(i);
    }
    final order = visits.keys.toList()..sort((a, b) => b.compareTo(a));

    Future<void> fix(int index) async {
      final picked = await showSegmentPicker(
        context,
        title: l10n.fixTitleAny,
        subtitle: l10n.fixCurrent(records[index].dart.segment.name),
      );
      if (picked != null) ref.read(matchControllerProvider.notifier).correct(index, picked);
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xs),
              child: Text(l10n.fixOpen, style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.m),
              child: Text(
                order.isEmpty ? l10n.matchNoCorrections : l10n.matchCorrectHint,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.l),
                children: [
                  for (final v in order)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              state.setup.players[records[visits[v]!.first].player].name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                          for (final i in visits[v]!)
                            Padding(
                              padding: const EdgeInsets.only(right: AppSpacing.s),
                              child: Opacity(
                                opacity: records[i].counted ? 1 : 0.45,
                                child: DartChip(
                                  key: Key('match-fix-$i'),
                                  segment: records[i].dart.segment,
                                  onTap: () => fix(i),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
