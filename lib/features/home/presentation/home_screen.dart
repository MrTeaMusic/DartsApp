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
import '../../games/data/game_repository.dart';
import '../../games/presentation/game_texts.dart';
import '../../profiles/presentation/active_player.dart';

final _homeRecentProvider = StreamProvider<List<SessionSummary>>(
  (ref) => ref.watch(gameRepositoryProvider).watchRecent(limit: 5, playerId: ref.watch(activePlayerProvider)?.id),
);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final live = ref.watch(liveVisitProvider);
    final player = ref.watch(activePlayerProvider);
    final recent = ref.watch(_homeRecentProvider).value ?? const [];
    final darts = live.history.length;
    final total = live.history.fold<int>(0, (s, d) => s + d.score);
    final average = darts == 0 ? '–' : (total / darts * 3).toStringAsFixed(1).replaceAll('.', ',');

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 720;
          final pad = wide ? AppSpacing.pageWide : AppSpacing.page;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: EdgeInsets.all(pad),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.appTitle, style: theme.textTheme.headlineLarge),
                            if (player != null)
                              Text(l10n.homeHello(player.name), style: theme.textTheme.bodyMedium?.copyWith(color: context.dartColors.textMuted)),
                          ],
                        ),
                      ),
                      const SourceStatusBadge(),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _Hero(last: recent.isEmpty ? null : recent.first),
                  const SizedBox(height: AppSpacing.xl),
                  SectionHeader(l10n.homeSession),
                  Row(
                    children: [
                      Expanded(child: _MiniStat(label: l10n.homeSessionDarts, value: '$darts', icon: Icons.adjust_rounded)),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(child: _MiniStat(label: l10n.homeSessionAverage, value: average, icon: Icons.show_chart_rounded)),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(
                        child: _MiniStat(
                          label: l10n.homeLastDart,
                          value: live.history.isEmpty ? '–' : live.history.last.segment.name,
                          icon: Icons.history_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SectionHeader(
                    l10n.gameRecent,
                    trailing: TextButton(onPressed: () => context.go(Routes.stats), child: Text(l10n.homeAllStats)),
                  ),
                  if (recent.isEmpty)
                    AppCard(child: Text(l10n.gameRecentEmpty, style: theme.textTheme.bodySmall))
                  else
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Column(
                        children: [
                          for (final s in recent)
                            ListTile(
                              key: Key('home-recent-${s.id}'),
                              leading: Icon(gameIcon(s.gameId)),
                              title: Text(l10n.gameTitle(s.gameId)),
                              subtitle: Text(_when(s.startedAt, l10n)),
                              trailing: Text('${s.dartCount} ${l10n.statDarts}', style: theme.textTheme.bodySmall),
                              onTap: () => context.go(Routes.gameSetup(s.gameId)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  static String _when(DateTime t, AppLocalizations l10n) {
    String two(int v) => v.toString().padLeft(2, '0');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final time = '${two(t.hour)}:${two(t.minute)}';
    if (day == today) return l10n.homeToday(time);
    if (day == today.subtract(const Duration(days: 1))) return l10n.homeYesterday(time);
    return '${two(t.day)}.${two(t.month)}. $time';
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: context.dartColors.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(label, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: theme.textTheme.displayMedium),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.last});
  final SessionSummary? last;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final last = this.last;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.20),
            colors.tripleHit.withValues(alpha: 0.10),
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
              if (last != null)
                FilledButton.icon(
                  key: const Key('home-continue'),
                  onPressed: () => context.go(Routes.gameSetup(last.gameId)),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(l10n.homeContinue(l10n.gameTitle(last.gameId))),
                ),
              (last == null ? FilledButton.icon : OutlinedButton.icon)(
                key: const Key('home-open-games'),
                onPressed: () => context.go(Routes.games),
                icon: const Icon(Icons.sports_esports_rounded),
                label: Text(l10n.homeOpenGames),
              ),
              OutlinedButton.icon(
                key: const Key('home-open-board'),
                onPressed: () => context.go(Routes.board),
                icon: const Icon(Icons.adjust_rounded),
                label: Text(l10n.homeOpenBoard),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
