import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../data/game_repository.dart';
import '../domain/engine/game_display.dart';
import '../domain/game_catalog.dart';
import '../../profiles/presentation/active_player.dart';
import 'game_texts.dart';

final recentSessionsProvider = StreamProvider<List<SessionSummary>>(
  (ref) => ref.watch(gameRepositoryProvider).watchRecent(limit: 10, playerId: ref.watch(activePlayerProvider)?.id),
);

/// Übersicht der Trainingsspiele.
class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final recent = ref.watch(recentSessionsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gamesTitle)),
      body: LayoutBuilder(
        builder: (context, c) {
          final columns = (c.maxWidth / 360).floor().clamp(1, 3);
          SliverGrid grid(List<Widget> children) => SliverGrid(
            delegate: SliverChildListDelegate(children),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AppSpacing.m,
              crossAxisSpacing: AppSpacing.m,
              mainAxisExtent: 124,
            ),
          );
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.s, AppSpacing.page, 0),
                sliver: SliverToBoxAdapter(child: SectionHeader(l10n.gamesPlayable)),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                sliver: grid([
                  for (final def in GameCatalog.all)
                    _GameCard(
                      key: Key('game-${def.id}'),
                      icon: gameIcon(def.id),
                      title: l10n.gameTitle(def.id),
                      description: l10n.gameDescription(def.id),
                      onTap: () => context.go(Routes.gameSetup(def.id)),
                    ),
                ]),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, 0),
                sliver: SliverToBoxAdapter(child: SectionHeader(l10n.gameRecent)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.page),
                sliver: SliverToBoxAdapter(
                  child: recent.isEmpty
                      ? Text(l10n.gameRecentEmpty, style: Theme.of(context).textTheme.bodySmall)
                      : AppCard(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                          child: Column(children: [for (final s in recent) _RecentTile(summary: s)]),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({super.key, required this.icon, required this.title, required this.description, this.onTap});

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final accent = theme.colorScheme.primary;
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadii.m),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpacing.xs),
                Text(description, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.textMuted),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.summary});
  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final m = summary.metrics;
    final t = summary.startedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(t.day)}.${two(t.month)}. ${two(t.hour)}:${two(t.minute)}';
    final headline = switch (summary.gameId) {
      'checkout' => formatPercent(m['checkoutRate']),
      'around_the_clock' => '${m['darts'] ?? '–'} ${l10n.statDarts}',
      'score_target' => formatPercent(m['successRate']),
      'target_practice' || 'highscore_hunt' => formatDecimal(m['average']),
      'cricket' => '${formatDecimal(m['mpr'])} MPR',
      'one_twenty_one' => '${m['highestCheckout'] ?? '–'}',
      'bobs_27' => '${m['score'] ?? '–'}',
      'three_hits' => '${m['darts'] ?? '–'} ${l10n.statDarts}',
      _ => '${m['points'] ?? '–'}',
    };
    return ListTile(
      leading: Icon(gameIcon(summary.gameId)),
      title: Text(l10n.gameTitle(summary.gameId)),
      subtitle: Text(
        '$date · ${summary.dartCount} ${l10n.statDarts}${summary.finished ? '' : ' · ${l10n.gameAborted}'}',
      ),
      trailing: Text(headline, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
