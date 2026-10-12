import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../data/game_repository.dart';
import '../domain/engine/game_display.dart';
import '../domain/game_catalog.dart';
import '../../challenges/presentation/challenge_routes.dart';
import '../../matches/presentation/match_routes.dart';
import '../../plans/presentation/plan_routes.dart';
import '../../stats/domain/game_metrics.dart';
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
      appBar: AppPageBar(title: Text(l10n.gamesTitle)),
      body: LayoutBuilder(
        builder: (context, c) {
          final look = context.look;
          final page = look.pagePadding(c.maxWidth >= kWidePage);
          final columns = ((c.maxWidth - 2 * page) / 340).floor().clamp(1, 4);
          SliverGrid grid(List<Widget> children) => SliverGrid(
            delegate: SliverChildListDelegate(children),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: look.gridGap,
              crossAxisSpacing: look.gridGap,
              mainAxisExtent: look.id == DartLookId.lab ? 104 : (look.id == DartLookId.clean ? 132 : 120),
            ),
          );
          return CustomScrollView(
            slivers: [
              // Pläne, Challenges und Matches nebeneinander statt je eine
              // eigene Rubrik mit nur einer Karte.
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, AppSpacing.s, page, 0),
                sliver: SliverToBoxAdapter(child: SectionHeader(l10n.gamesModes)),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: page),
                sliver: grid([
                  _GameCard(
                    key: const Key('open-plans'),
                    icon: Icons.event_note_rounded,
                    title: l10n.plansTitle,
                    description: l10n.plansEntryText,
                    onTap: () => context.go(PlanRoutes.list),
                  ),
                  _GameCard(
                    key: const Key('open-challenges'),
                    icon: Icons.star_rounded,
                    title: l10n.chalTitle,
                    description: l10n.chalEntryText,
                    onTap: () => context.go(ChallengeRoutes.list),
                  ),
                  _GameCard(
                    key: const Key('open-matches'),
                    icon: Icons.people_alt_rounded,
                    title: l10n.matchesTitle,
                    description: l10n.matchesEntryText,
                    onTap: () => context.go(MatchRoutes.hub),
                  ),
                ]),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, look.sectionGap, page, 0),
                sliver: SliverToBoxAdapter(child: SectionHeader(l10n.gamesPlayable)),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: page),
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
                padding: EdgeInsets.fromLTRB(page, look.sectionGap, page, 0),
                sliver: SliverToBoxAdapter(child: SectionHeader(l10n.gameRecent)),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, 0, page, page),
                sliver: SliverToBoxAdapter(
                  child: recent.isEmpty
                      ? AppCard(child: Text(l10n.gameRecentEmpty, style: Theme.of(context).textTheme.bodySmall))
                      : AppCard(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                          child: Column(children: [
                            for (final (i, s) in recent.indexed) ...[
                              if (i > 0) Divider(indent: look.cardPadding + 52, endIndent: look.cardPadding),
                              _RecentTile(summary: s),
                            ],
                          ]),
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
    final look = context.look;
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, size: look.id == DartLookId.lab ? 36 : 44),
          SizedBox(width: look.id == DartLookId.lab ? AppSpacing.m : AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: look.id == DartLookId.tv ? theme.textTheme.titleLarge?.copyWith(fontSize: 20) : theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  maxLines: look.id == DartLookId.lab ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.textMuted),
        ],
      ),
    );
  }
}

/// Hauptkennzahl laut [PrimaryMetric.byGame], sonst die Punkte.
String _primaryText(String gameId, Map<String, num> m) {
  final pm = PrimaryMetric.byGame[gameId];
  final v = m[pm?.key ?? 'points'];
  if (v == null) return '–';
  return switch (pm?.format) {
    MetricFormat.percent => formatPercent(v),
    MetricFormat.decimal => formatDecimal(v),
    _ => '${v.round()}',
  };
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
      _ => _primaryText(summary.gameId, m),
    };
    final look = context.look;
    return ListTile(
      leading: IconBadge(icon: gameIcon(summary.gameId), size: 38),
      title: Text(l10n.gameTitle(summary.gameId), overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$date · ${summary.dartCount} ${l10n.statDarts}${summary.finished ? '' : ' · ${l10n.gameAborted}'}',
      ),
      trailing: Text(headline, style: look.chipNumber.copyWith(color: Theme.of(context).colorScheme.onSurface)),
    );
  }
}
