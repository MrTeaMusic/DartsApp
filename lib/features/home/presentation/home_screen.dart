import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../board/presentation/live_visit_controller.dart';
import '../../dart_source/presentation/source_status_badge.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final live = ref.watch(liveVisitProvider);
    final darts = live.history.length;
    final total = live.history.fold<int>(0, (s, d) => s + d.score);
    final average = darts == 0 ? '–' : (total / darts * 3).toStringAsFixed(1).replaceAll('.', ',');

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 720;
          final pad = wide ? AppSpacing.pageWide : AppSpacing.page;
          return ListView(
            padding: EdgeInsets.all(pad),
            children: [
              Row(
                children: [
                  Expanded(child: Text(l10n.appTitle, style: theme.textTheme.headlineLarge)),
                  const SourceStatusBadge(),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _Hero(onOpenBoard: () => context.go(Routes.board)),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(l10n.homeSession),
              GridView.count(
                crossAxisCount: wide ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.m,
                crossAxisSpacing: AppSpacing.m,
                childAspectRatio: wide ? 1.9 : 1.35,
                children: [
                  StatTile(label: l10n.homeSessionDarts, value: '$darts', icon: Icons.adjust_rounded),
                  StatTile(label: l10n.homeSessionAverage, value: average, icon: Icons.show_chart_rounded),
                  if (wide)
                    StatTile(
                      label: l10n.homeLastDart,
                      value: live.history.isEmpty ? '–' : live.history.last.segment.name,
                      icon: Icons.history_rounded,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: context.dartColors.textMuted),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(child: Text(l10n.homePhaseNote, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onOpenBoard});
  final VoidCallback onOpenBoard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.22),
            colors.boardRed.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.homeGreeting, style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.s),
          Text(l10n.homeSubtitle, style: theme.textTheme.bodyLarge?.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.m,
            runSpacing: AppSpacing.m,
            children: [
              FilledButton.icon(
                key: const Key('home-open-board'),
                onPressed: onOpenBoard,
                icon: const Icon(Icons.adjust_rounded),
                label: Text(l10n.homeOpenBoard),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go(Routes.games),
                icon: const Icon(Icons.sports_esports_rounded),
                label: Text(l10n.homeOpenGames),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
