import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../board/presentation/live_visit_controller.dart';
import '../../dart_source/presentation/source_status_badge.dart';
import '../../games/data/game_repository.dart';
import '../../games/presentation/game_texts.dart';
import '../../profiles/presentation/active_player.dart';
import '../../progress/presentation/daily_goal_card.dart';

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

    final look = context.look;
    final sessionStats = [
      (l10n.homeSessionDarts, '$darts', Icons.adjust_rounded),
      (l10n.homeSessionAverage, average, Icons.show_chart_rounded),
      (l10n.homeLastDart, live.history.isEmpty ? '–' : live.history.last.segment.name, Icons.history_rounded),
    ];

    final recentSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          l10n.gameRecent,
          trailing: TextButton(
            key: const Key('home-open-history'),
            onPressed: () => context.go(Routes.history),
            child: Text(l10n.histTitle),
          ),
        ),
        if (recent.isEmpty)
          AppCard(child: Text(l10n.gameRecentEmpty, style: theme.textTheme.bodySmall))
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (final (i, s) in recent.indexed) ...[
                  if (i > 0) Divider(indent: look.cardPadding + 52, endIndent: look.cardPadding),
                  ListTile(
                    key: Key('home-recent-${s.id}'),
                    leading: IconBadge(icon: gameIcon(s.gameId), size: 38),
                    title: Text(l10n.gameTitle(s.gameId), overflow: TextOverflow.ellipsis),
                    subtitle: Text(_when(s.startedAt, l10n)),
                    trailing: Text(
                      l10n.sessionAmount(s.gameId, s.dartCount, s.metrics),
                      style: look.kicker.copyWith(color: context.dartColors.textMuted),
                    ),
                    onTap: () => context.go(Routes.session(s.id)),
                  ),
                ],
              ],
            ),
          ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= kWidePage;
          final twoColumns = c.maxWidth >= 1000;
          final pad = look.pagePadding(wide);
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 1120 + 2 * pad),
              child: ListView(
                padding: EdgeInsets.fromLTRB(pad, wide ? AppSpacing.xl : AppSpacing.l, pad, pad),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (player != null) ...[
                              Kicker(l10n.homeHello(player.name)),
                              const SizedBox(height: AppSpacing.xxs),
                            ],
                            Text(l10n.appTitle, style: theme.textTheme.headlineLarge),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.m),
                      Flexible(child: Align(alignment: Alignment.centerRight, child: SourceStatusBadge(compact: !wide))),
                    ],
                  ),
                  SizedBox(height: look.sectionGap * 0.75),
                  _Hero(last: recent.isEmpty ? null : recent.first, wide: wide),
                  SizedBox(height: look.gridGap),
                  DailyGoalCard(wide: wide),
                  const SectionGap(),
                  if (twoColumns)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: recentSection),
                        SizedBox(width: look.sectionGap),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SectionHeader(l10n.homeSession),
                              for (final (i, (label, value, icon)) in sessionStats.indexed) ...[
                                if (i > 0) SizedBox(height: look.gridGap),
                                StatTile(label: label, value: value, icon: icon),
                              ],
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    SectionHeader(l10n.homeSession),
                    _SessionStrip(stats: sessionStats),
                    const SectionGap(),
                    recentSection,
                  ],
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

/// Drei Kennzahlen der laufenden Sitzung in einer Karte (schmal).
class _SessionStrip extends StatelessWidget {
  const _SessionStrip({required this.stats});
  final List<(String, String, IconData)> stats;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.symmetric(vertical: look.cardPadding),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (final (i, (label, value, _)) in stats.indexed) ...[
              if (i > 0) VerticalDivider(width: 1, color: theme.colorScheme.outline),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: look.cardPadding * 0.75),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Kicker(label, maxLines: 2),
                      const Spacer(),
                      const SizedBox(height: AppSpacing.s),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value, style: look.statValue.copyWith(color: theme.colorScheme.onSurface)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Knöpfe der Startkachel: nebeneinander, auf schmalen Bildschirmen
/// untereinander in voller Breite.
class _Buttons extends StatelessWidget {
  const _Buttons({required this.wide, required this.children});
  final bool wide;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (wide) return Wrap(spacing: AppSpacing.m, runSpacing: AppSpacing.m, children: children);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s + 2),
          c,
        ],
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.last, required this.wide});
  final SessionSummary? last;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final last = this.last;
    final pad = wide ? AppSpacing.xxl + (look.id == DartLookId.clean ? 8 : 0) : AppSpacing.xl;
    return HeroBackdrop(
      padding: EdgeInsets.fromLTRB(pad + (look.id == DartLookId.tv ? 6 : 0), pad, pad, pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (look.id == DartLookId.tv) ...[
            Kicker(l10n.navGames, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.xs),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.homeGreeting,
                  style: (wide ? theme.textTheme.headlineLarge : theme.textTheme.headlineMedium)
                      ?.copyWith(fontSize: look.id == DartLookId.tv && wide ? 48 : null),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(l10n.homeSubtitle, style: theme.textTheme.bodyLarge?.copyWith(color: colors.textMuted)),
              ],
            ),
          ),
          SizedBox(height: wide ? AppSpacing.xl + 4 : AppSpacing.xl),
          _Buttons(
            wide: wide,
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
