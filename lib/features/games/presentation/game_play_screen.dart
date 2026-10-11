import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_theme.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../board/presentation/dartboard_view.dart';
import '../../board/presentation/live_visit_controller.dart';
import '../../dart_source/data/manual_source.dart';
import '../../dart_source/data/simulator_source.dart';
import '../../dart_source/presentation/dart_source_providers.dart';
import '../../dart_source/presentation/source_status_badge.dart';
import '../../plans/presentation/plan_run_panel.dart';
import '../../simulator/presentation/manual_keypad.dart';
import '../../simulator/presentation/segment_picker.dart';
import '../../../core/widgets/fullscreen_button.dart';
import '../domain/engine/game_display.dart';
import 'active_game_controller.dart';
import 'game_texts.dart';

/// Spielansicht. Große Zahlen, lesbar aus 2–3 m Abstand.
class GamePlayScreen extends ConsumerWidget {
  const GamePlayScreen({super.key});

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final active = ref.read(activeGameProvider);
    if (active != null && !active.ended) {
      final l10n = context.l10n;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.gameEndTitle),
          content: Text(l10n.gameEndText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.gameCancel)),
            FilledButton(
              key: const Key('confirm-end'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.gameEnd),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(activeGameProvider.notifier).close();
    if (context.mounted) context.go(Routes.games);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final active = ref.watch(activeGameProvider);
    if (active == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: FilledButton(onPressed: () => context.go(Routes.games), child: Text(l10n.gamesTitle)),
        ),
      );
    }
    final source = ref.watch(dartSourceProvider);
    final live = ref.watch(liveVisitProvider);
    final game = active.game;

    final board = DartboardView(
      key: const Key('game-board'),
      hits: [for (final d in live.visit) if (d.position != null) d.position!],
      lastSegment: live.lastDart?.segment,
      hitSerial: live.history.length,
      highlighted: active.ended ? const {} : game.targets,
      onTap: active.ended
          ? null
          : switch (source) {
              SimulatorSource() => (point, _) => source.throwAt(point),
              ManualSource() => (_, segment) => source.enter(segment),
              _ => null,
            },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave(context, ref));
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('leave-game'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _leave(context, ref),
          ),
          title: Text(l10n.gameTitle(active.gameId)),
          actions: [
            SourceStatusBadge(compact: MediaQuery.sizeOf(context).width < 600),
            const SizedBox(width: AppSpacing.xs),
            const FullscreenButton(),
            const SizedBox(width: AppSpacing.s),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final panel = _GamePanel(active: active, large: wide);
            if (wide) {
              return Row(
                children: [
                  Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: board))),
                  SizedBox(
                    width: 440,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(0, AppSpacing.l, AppSpacing.xl, AppSpacing.xl),
                      child: panel,
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.page),
              children: [
                _Headline(active: active, large: false),
                const SizedBox(height: AppSpacing.m),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: c.maxHeight * 0.5),
                  child: Center(child: board),
                ),
                const SizedBox(height: AppSpacing.m),
                _GamePanel(active: active, large: false, showHeadline: false),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.active, required this.large});
  final ActiveGame active;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final display = active.game.display;
    final style = large ? AppTypography.scoreHuge.copyWith(fontSize: 140) : AppTypography.scoreLarge;
    // Nach dem Spiel steht die wichtigste Kennzahl oben statt des Spielstands.
    final summary = active.ended ? active.game.result.summary : const <GameStat>[];
    final label = summary.isNotEmpty ? '${l10n.gameResult} · ${l10n.statLabel(summary.first.key)}' : l10n.statLabel(display.headlineKey);
    final headline = summary.isNotEmpty ? summary.first.value : display.headline;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label.toUpperCase(), style: theme.textTheme.labelMedium)),
              if (display.progressLabel != null) Text(display.progressLabel!, style: theme.textTheme.titleMedium),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: AppDurations.medium,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a), child: child),
              ),
              child: Text(
                headline,
                key: ValueKey(headline),
                style: style.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          ),
          if (display.progress != null) ...[
            const SizedBox(height: AppSpacing.s),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: display.progress!.clamp(0, 1)),
                duration: AppDurations.medium,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  backgroundColor: context.dartColors.surfaceHigh,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GamePanel extends ConsumerWidget {
  const _GamePanel({required this.active, required this.large, this.showHeadline = true});
  final ActiveGame active;
  final bool large;
  final bool showHeadline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final source = ref.watch(dartSourceProvider);
    final controller = ref.read(activeGameProvider.notifier);
    final display = active.game.display;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeadline) ...[
          _Headline(active: active, large: large),
          const SizedBox(height: AppSpacing.m),
        ],
        _EventBanner(active: active),
        _VisitCard(active: active, large: large),
        const SizedBox(height: AppSpacing.m),
        _StatsGrid(stats: active.ended ? active.game.result.summary : display.stats),
        const SizedBox(height: AppSpacing.m),
        const PlanRunPanel(),
        if (active.ended)
          _ResultActions(active: active)
        else if (source is ManualSource)
          ManualKeypad(source: source)
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('game-undo'),
                  onPressed: controller.undo,
                  icon: const Icon(Icons.undo_rounded),
                  label: Text(l10n.boardUndo),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('game-next'),
                  onPressed: controller.nextVisit,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text(l10n.boardNext),
                ),
              ),
            ],
          ),
        if (!active.ended) ...[
          const SizedBox(height: AppSpacing.s),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.s,
            children: [
              if (active.session.records.isNotEmpty)
                TextButton.icon(
                  key: const Key('open-corrections'),
                  onPressed: () => showCorrectionsSheet(context),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(l10n.fixOpen),
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurfaceVariant),
                ),
              TextButton.icon(
                key: const Key('end-game'),
                onPressed: controller.end,
                icon: const Icon(Icons.flag_outlined),
                label: Text(l10n.gameEnd),
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _EventBanner extends StatelessWidget {
  const _EventBanner({required this.active});
  final ActiveGame active;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final event = active.events.isEmpty ? null : active.events.last;
    final color = switch (event == null ? EventTone.neutral : eventTone(event.type)) {
      EventTone.positive => colors.success,
      EventTone.negative => colors.danger,
      EventTone.neutral => Theme.of(context).colorScheme.primary,
    };
    return AnimatedSwitcher(
      duration: AppDurations.medium,
      transitionBuilder: (child, a) => SizeTransition(sizeFactor: a, child: FadeTransition(opacity: a, child: child)),
      child: event == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              key: ValueKey(active.revision),
              padding: const EdgeInsets.only(bottom: AppSpacing.m),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.m),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadii.m),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  l10n.eventText(event),
                  key: const Key('game-event'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color),
                ),
              ),
            ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});
  final List<GameStat> stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.m,
        children: [
          for (final s in stats)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.statLabel(s.key), style: theme.textTheme.labelMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(s.value, style: theme.textTheme.headlineSmall?.copyWith(fontFeatures: AppTypography.tabular)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultActions extends ConsumerWidget {
  const _ResultActions({required this.active});
  final ActiveGame active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('game-done'),
            onPressed: () async {
              await ref.read(activeGameProvider.notifier).close();
              if (context.mounted) context.go(Routes.games);
            },
            icon: const Icon(Icons.check_rounded),
            label: Text(l10n.gameDone),
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: FilledButton.icon(
            key: const Key('game-again'),
            onPressed: () {
              final config = Map<String, Object?>.of(active.session.config);
              unawaited(ref.read(activeGameProvider.notifier).start(active.session.definition, config));
            },
            icon: const Icon(Icons.replay_rounded),
            label: Text(l10n.gameAgain),
          ),
        ),
      ],
    );
  }
}

/// Die drei Darts der laufenden Aufnahme. Noch offene Plätze zeigen bei
/// Checkout-Spielen den besten Weg in Gelb. Geworfene Darts lassen sich
/// antippen und korrigieren.
class _VisitCard extends ConsumerWidget {
  const _VisitCard({required this.active, required this.large});
  final ActiveGame active;
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final live = ref.watch(liveVisitProvider);
    final game = active.game;
    final thrown = live.visit.length;
    // Nach Bust/Checkout gilt der Weg erst wieder für die nächste Aufnahme.
    final route = active.ended || (game.visitClosed && thrown > 0) ? null : game.display.suggestion;
    final records = active.session.records;
    final liveStart = records.length - thrown;

    Future<void> fix(int slot) async {
      final index = liveStart + slot;
      if (index < 0 || index >= records.length) return;
      final picked = await showSegmentPicker(
        context,
        title: l10n.fixTitle(slot + 1),
        subtitle: l10n.fixCurrent(records[index].dart.segment.name),
      );
      if (picked != null) ref.read(activeGameProvider.notifier).correct(index, picked);
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.m, AppSpacing.m, AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Row(
              children: [
                Text(l10n.visitLabel.toUpperCase(), style: theme.textTheme.labelMedium),
                const SizedBox(width: AppSpacing.s),
                if (route != null && route.isNotEmpty)
                  Flexible(
                    child: Text(
                      l10n.visitRoute,
                      key: const Key('checkout-route-label'),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(color: colors.highlight),
                    ),
                  )
                else if (route != null && thrown == 0)
                  Flexible(
                    child: Text(l10n.gameNoCheckout, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ),
                const Spacer(),
                Text(
                  '${live.visitScore}',
                  key: const Key('visit-score'),
                  style: theme.textTheme.titleLarge?.copyWith(fontFeatures: AppTypography.tabular),
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
                        key: Key('dart-slot-$i'),
                        segment: i < thrown ? live.visit[i].segment : null,
                        planned: route != null && i >= thrown && i - thrown < route.length ? route[i - thrown] : null,
                        label: '${i + 1}',
                        large: true,
                        onTap: !active.ended && i < thrown ? () => fix(i) : null,
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

/// Liste der Aufnahmen dieses Spiels; jeder Dart lässt sich korrigieren.
Future<void> showCorrectionsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => const _CorrectionsSheet(),
  );
}

class _CorrectionsSheet extends ConsumerWidget {
  const _CorrectionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final active = ref.watch(activeGameProvider);
    if (active == null) return const SizedBox.shrink();
    final records = active.session.records;
    final visits = <int, List<int>>{};
    for (var i = 0; i < records.length; i++) {
      visits.putIfAbsent(records[i].visitIndex, () => []).add(i);
    }
    final order = visits.keys.toList()..sort((a, b) => b.compareTo(a));

    Future<void> fix(int index) async {
      final picked = await showSegmentPicker(
        context,
        title: l10n.fixTitleAny,
        subtitle: l10n.fixCurrent(records[index].dart.segment.name),
      );
      if (picked != null) ref.read(activeGameProvider.notifier).correct(index, picked);
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
              child: Text(l10n.fixHint, style: theme.textTheme.bodySmall),
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
                            width: 72,
                            child: Text(l10n.fixVisit(v + 1), style: theme.textTheme.labelMedium),
                          ),
                          for (final i in visits[v]!)
                            Padding(
                              padding: const EdgeInsets.only(right: AppSpacing.s),
                              child: Opacity(
                                opacity: records[i].counted ? 1 : 0.45,
                                child: DartChip(
                                  key: Key('fix-dart-$i'),
                                  segment: records[i].dart.segment,
                                  onTap: () => fix(i),
                                ),
                              ),
                            ),
                          const Spacer(),
                          Text(
                            '${visits[v]!.where((i) => records[i].counted).fold<int>(0, (s, i) => s + records[i].dart.score)}',
                            style: theme.textTheme.titleMedium?.copyWith(fontFeatures: AppTypography.tabular),
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
