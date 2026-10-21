import 'dart:async';

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
import '../../board/presentation/live_visit_controller.dart';
import '../../dart_source/data/autodarts_local_source.dart';
import '../../dart_source/data/local_dart_source.dart';
import '../../dart_source/data/manual_source.dart';
import '../../dart_source/data/simulator_source.dart';
import '../../dart_source/presentation/dart_source_providers.dart';
import '../../dart_source/presentation/source_status_badge.dart';
import 'manual_keypad.dart';

/// Live-Board: zeigt die Würfe der aktiven Quelle. Im Simulator ist das Board
/// klickbar, bei manueller Eingabe gibt es zusätzlich ein Tastenfeld.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  double _spread = 0;
  bool _showHeat = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final source = ref.watch(dartSourceProvider);
    final live = ref.watch(liveVisitProvider);

    final board = DartboardView(
      key: const Key('dartboard'),
      hits: [for (final d in live.visit) if (d.position != null) d.position!],
      lastSegment: live.lastDart?.segment,
      hitSerial: live.history.length,
      heat: [for (final d in live.history) if (d.position != null) d.position!],
      showHeat: _showHeat,
      onTap: switch (source) {
        SimulatorSource() => (point, _) => source.throwNear(point, spread: _spread),
        ManualSource() => (_, segment) => source.enter(segment),
        _ => null,
      },
    );

    final panel = _SidePanel(
      spread: _spread,
      onSpread: (v) => setState(() => _spread = v),
      showHeat: _showHeat,
      onShowHeat: (v) => setState(() => _showHeat = v),
    );

    return Scaffold(
      appBar: AppPageBar(
        title: Text(l10n.boardTitle),
        actions: const [SourceStatusBadge()],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 900) {
            return Row(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: board),
                  ),
                ),
                SizedBox(
                  width: 380,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(0, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl),
                    child: panel,
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: c.maxHeight * 0.55),
                child: Center(child: board),
              ),
              const SizedBox(height: AppSpacing.l),
              panel,
            ],
          );
        }),
      ),
    );
  }
}

class _SidePanel extends ConsumerWidget {
  const _SidePanel({
    required this.spread,
    required this.onSpread,
    required this.showHeat,
    required this.onShowHeat,
  });

  final double spread;
  final ValueChanged<double> onSpread;
  final bool showHeat;
  final ValueChanged<bool> onShowHeat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final source = ref.watch(dartSourceProvider);
    final live = ref.watch(liveVisitProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScorePanel(
          label: l10n.boardVisit,
          badge: AnimatedOpacity(
            opacity: live.takeoutInProgress ? 1 : 0,
            duration: AppDurations.fast,
            child: StatusPill(label: l10n.boardTakeout, color: colors.warning, pulsing: live.takeoutInProgress),
          ),
          value: TweenAnimationBuilder<double>(
            tween: Tween(end: live.visitScore.toDouble()),
            duration: AppDurations.medium,
            builder: (context, v, _) => Text(
              v.round().toString(),
              key: const Key('visit-score'),
              style: ScorePanel.valueStyle(context, hero: false),
            ),
          ),
          footer: Row(
            children: [
              for (var i = 0; i < LocalDartSource.dartsPerVisit; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                    child: FittedBox(
                      child: DartChip(segment: i < live.visit.length ? live.visit[i].segment : null, large: true),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: context.look.gridGap * 1.5),
        switch (source) {
          SimulatorSource() => _SimulatorControls(
              source: source,
              spread: spread,
              onSpread: onSpread,
            ),
          ManualSource() => ManualKeypad(source: source),
          AutodartsLocalSource() => _AutodartsControls(source: source),
          _ => const SizedBox.shrink(),
        },
        SizedBox(height: context.look.gridGap * 1.5),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              SwitchListTile(
                key: const Key('heatmap-toggle'),
                value: showHeat,
                onChanged: source.providesCoordinates ? onShowHeat : null,
                title: Text(l10n.boardHeatmap),
                subtitle: Text(l10n.boardHeatmapHint(live.history.where((d) => d.position != null).length)),
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: Text(l10n.boardClearSession),
                onTap: () => ref.read(liveVisitProvider.notifier).clearHistory(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SimulatorControls extends StatelessWidget {
  const _SimulatorControls({required this.source, required this.spread, required this.onSpread});

  final SimulatorSource source;
  final double spread;
  final ValueChanged<double> onSpread;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final mm = (spread * 170).round();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.boardTapHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.l),
          Text(spread == 0 ? l10n.boardScatterOff : l10n.boardScatter(mm), style: theme.textTheme.labelMedium),
          Slider(
            key: const Key('scatter-slider'),
            value: spread,
            max: 0.2,
            divisions: 20,
            onChanged: onSpread,
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: source.undoLast,
                  icon: const Icon(Icons.undo_rounded),
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(l10n.boardUndo, maxLines: 1)),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: FilledButton.icon(
                  onPressed: source.finishTakeout,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(l10n.boardNext, maxLines: 1)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AutodartsControls extends StatelessWidget {
  const _AutodartsControls({required this.source});
  final AutodartsLocalSource source;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.boardLiveHint('${source.host}:${source.port}'), style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.s),
          Text(l10n.autodartsUnverified, style: theme.textTheme.bodySmall?.copyWith(color: context.dartColors.warning)),
          const SizedBox(height: AppSpacing.l),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(source.send(AutodartsCommand.reset)),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(l10n.debugCmdReset),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.go(Routes.debug),
                  icon: const Icon(Icons.terminal_rounded),
                  label: Text(l10n.debugShort),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
