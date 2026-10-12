import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../domain/tournament.dart';
import 'match_controller.dart';
import 'match_routes.dart';
import 'match_texts.dart';
import 'tournament_controller.dart';

/// Turnierbaum mit dem nächsten eigenen Spiel.
class TournamentScreen extends ConsumerWidget {
  const TournamentScreen({super.key});

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tourDiscardTitle),
        content: Text(l10n.tourDiscardText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cpuCancel)),
          FilledButton(
            key: const Key('confirm-discard-tournament'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.tourDiscard),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(tournamentControllerProvider.notifier).discard();
    if (context.mounted) context.go(MatchRoutes.hub);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = ref.watch(tournamentControllerProvider);
    // Nach einem Spiel neu zeichnen (Ergebnis wurde eingetragen).
    ref.watch(matchControllerProvider.select((s) => s?.ended));

    return Scaffold(
      appBar: AppPageBar(
        title: Text(l10n.tournamentTitle),
        actions: [
          if (t != null)
            PopupMenuButton<String>(
              key: const Key('tournament-menu'),
              onSelected: (v) => switch (v) {
                'new' => context.go(MatchRoutes.tournamentNew),
                _ => _discard(context, ref),
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'new', child: Text(l10n.tourNew)),
                PopupMenuItem(value: 'discard', key: const Key('tournament-discard'), child: Text(l10n.tourDiscard)),
              ],
            ),
        ],
      ),
      body: t == null
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(context.look.page),
                child: ComingSoon(
                  icon: Icons.emoji_events_rounded,
                  title: l10n.tournamentTitle,
                  text: l10n.tourNone,
                  action: FilledButton.icon(
                    onPressed: () => context.go(MatchRoutes.tournamentNew),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l10n.tourNew),
                  ),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 1000;
                final look = context.look;
                final page = look.pagePadding(c.maxWidth >= kWidePage);
                return ListView(
                  padding: EdgeInsets.fromLTRB(page, look.page * 0.5, page, page),
                  children: [
                    _StatusCard(tournament: t),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      l10n.tourInfo(t.startScore, (t.difficulty * 100).round()),
                      style: theme.textTheme.bodySmall?.copyWith(color: context.dartColors.textMuted),
                    ),
                    const SectionGap(factor: 0.8),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var r = 0; r < t.rounds.length; r++) ...[
                            if (r > 0) SizedBox(width: look.gridGap + AppSpacing.xs),
                            Expanded(
                              child: _RoundColumn(tournament: t, round: r),
                            ),
                          ],
                        ],
                      )
                    else
                      for (var r = 0; r < t.rounds.length; r++) _RoundColumn(tournament: t, round: r),
                  ],
                );
              },
            ),
    );
  }
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.tournament});
  final Tournament tournament;

  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(tournamentControllerProvider.notifier);
    final saved = controller.savedMatch();
    final setup = saved?.setup ?? controller.nextMatchSetup();
    if (setup == null) return;
    await ref.read(matchControllerProvider.notifier).start(setup, resume: saved);
    if (context.mounted) context.go(MatchRoutes.play);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final t = tournament;
    final controller = ref.read(tournamentControllerProvider.notifier);
    final h = t.humanIndex;

    if (t.finished) {
      final won = t.champion == h;
      return AppCard(
        child: Row(
          children: [
            IconBadge(icon: Icons.emoji_events_rounded, size: 52, color: won ? colors.record : theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.l),
            Expanded(
              child: Text(
                won ? l10n.tourYouWon : l10n.tourChampion(t.entrants[t.champion!].name),
                key: const Key('tournament-champion'),
                style: theme.textTheme.headlineSmall,
              ),
            ),
          ],
        ),
      );
    }

    final m = t.humanMatch;
    if (m != null) {
      final opponent = m.a == h ? m.b! : m.a!;
      final saved = controller.savedMatch();
      final look = context.look;
      return HeroBackdrop(
        padding: EdgeInsets.all(look.cardPadding + AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Kicker(l10n.tourNextMatch, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.s),
            Text(
              '${l10n.tourRoundName(m.round)} · ${l10n.tourBestOf(t.bestOf[m.round])}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${t.entrants[h].name} ${l10n.tourVs} ${t.entrants[opponent].name}',
              key: const Key('tournament-next'),
              style: look.sectionTitle.copyWith(
                fontSize: look.id == DartLookId.tv ? 34 : 26,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              l10n.tourCpuAverage(t.botAverage(opponent).round()),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.l),
            FilledButton.icon(
              key: const Key('tournament-play'),
              onPressed: () => _play(context, ref),
              icon: Icon(saved != null ? Icons.play_circle_outline_rounded : Icons.play_arrow_rounded),
              label: Text(saved != null ? l10n.tourResumeMatch : l10n.tourPlay),
            ),
          ],
        ),
      );
    }

    // Ausgeschieden: Rest simulieren.
    final out = t.rounds.expand((r) => r).where((x) => x.played && x.involves(h) && x.winner != h).firstOrNull;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (out != null) Text(l10n.tourEliminated(l10n.tourRoundName(out.round)), style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.m),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('tournament-sim-round'),
                  onPressed: controller.simulateRound,
                  child: Text(l10n.tourSimRound, textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: FilledButton(
                  key: const Key('tournament-sim-all'),
                  onPressed: controller.simulateToEnd,
                  child: Text(l10n.tourSimAll, textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundColumn extends StatelessWidget {
  const _RoundColumn({required this.tournament, required this.round});
  final Tournament tournament;
  final int round;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          l10n.tourRoundName(round),
          trailing: Kicker(l10n.tourBestOf(tournament.bestOf[round])),
        ),
        for (final m in tournament.rounds[round]) ...[
          _MatchTile(tournament: tournament, match: m),
          SizedBox(height: context.look.gridGap * 0.8),
        ],
        const SectionGap(factor: 0.6),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.tournament, required this.match});
  final Tournament tournament;
  final TournamentMatch match;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final h = tournament.humanIndex;
    final look = context.look;
    final mine = match.involves(h);

    Widget line(int? entrant, int score) {
      final name = entrant == null ? l10n.tourTbd : tournament.entrants[entrant].name;
      final winner = match.played && match.winner == entrant;
      final human = entrant == h;
      final style = theme.textTheme.bodyMedium?.copyWith(
        fontWeight: winner || human ? FontWeight.w700 : null,
        color: entrant == null
            ? colors.textMuted
            : match.played && !winner
            ? colors.textMuted
            : human
            ? theme.colorScheme.primary
            : null,
      );
      return Row(
        children: [
          Expanded(
            child: Text(name, overflow: TextOverflow.ellipsis, style: style),
          ),
          if (match.played)
            Text(
              '$score',
              style: look.chipNumber.copyWith(
                fontSize: 16,
                color: winner ? theme.colorScheme.onSurface : colors.textMuted,
              ),
            ),
        ],
      );
    }

    final tile = Column(
      children: [
        line(match.a, match.scoreA),
        const SizedBox(height: AppSpacing.xxs),
        line(match.b, match.scoreB),
      ],
    );
    return AppCard(
      key: Key('tournament-match-${match.id}'),
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Eigene Spiele mit Akzentkante.
            Container(width: 3, color: mine ? theme.colorScheme.primary : Colors.transparent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.m - 3, AppSpacing.s, AppSpacing.m, AppSpacing.s),
                child: tile,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
