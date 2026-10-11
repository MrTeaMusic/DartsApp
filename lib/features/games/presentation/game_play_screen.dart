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
import '../../simulator/presentation/manual_keypad.dart';
import '../../board/domain/segment.dart';
import '../domain/engine/game_display.dart';
import '../domain/games/checkout/checkout_training.dart';
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
          actions: const [
            Padding(padding: EdgeInsets.only(right: AppSpacing.l), child: SourceStatusBadge()),
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.statLabel(display.headlineKey).toUpperCase(), style: theme.textTheme.labelMedium)),
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
                display.headline,
                key: ValueKey(display.headline),
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
    final live = ref.watch(liveVisitProvider);
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
        if (!active.ended && active.game is CheckoutTraining && (active.game as CheckoutTraining).showSuggestion) ...[
          _Suggestion(suggestion: display.suggestion),
          const SizedBox(height: AppSpacing.m),
        ],
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                  child: FittedBox(child: DartChip(segment: i < live.visit.length ? live.visit[i].segment : null, large: true)),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.m),
        _StatsGrid(stats: active.ended ? active.game.result.summary : display.stats),
        const SizedBox(height: AppSpacing.m),
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
          const SizedBox(height: AppSpacing.m),
          TextButton.icon(
            key: const Key('end-game'),
            onPressed: controller.end,
            icon: const Icon(Icons.flag_outlined),
            label: Text(l10n.gameEnd),
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.suggestion});
  final List<Segment>? suggestion;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = suggestion;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.m),
      child: Row(
        children: [
          Text(l10n.gameSuggestion.toUpperCase(), style: theme.textTheme.labelMedium),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: s == null || s.isEmpty
                ? Text(l10n.gameNoCheckout, style: theme.textTheme.bodySmall)
                : Text(
                    s.map((e) => e.name).join('  ·  '),
                    key: const Key('checkout-suggestion'),
                    style: theme.textTheme.headlineSmall?.copyWith(color: context.dartColors.highlight),
                  ),
          ),
        ],
      ),
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
