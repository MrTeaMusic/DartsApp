import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../data/match_store.dart';
import 'match_controller.dart';
import 'match_routes.dart';
import 'match_texts.dart';
import 'tournament_controller.dart';

/// Gespeichertes, unterbrochenes Match außerhalb eines Turniers. Wird neu
/// gelesen, wenn ein Match startet oder endet.
final savedFreeMatchProvider = Provider<SavedMatch?>((ref) {
  final running = ref.watch(matchControllerProvider.select((s) => s != null && !s.ended));
  if (running) return null;
  final saved = ref.watch(matchStoreProvider).currentMatch();
  return saved == null || saved.setup.tournamentMatch != null ? null : saved;
});

/// Einstieg in Gegner-Modus, Turnier und die CPU-Spielerliste.
class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final saved = ref.watch(savedFreeMatchProvider);
    final tournament = ref.watch(tournamentControllerProvider);
    final cpus = ref.watch(cpuPlayersProvider);
    final running = tournament != null && !tournament.finished;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.matchesTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: [
              if (saved != null) ...[
                MatchEntryCard(
                  key: const Key('match-resume'),
                  icon: Icons.play_circle_outline_rounded,
                  title: l10n.matchResume,
                  description: l10n.matchResumeText(saved.setup.players[0].name, saved.setup.players[1].name),
                  highlight: true,
                  onTap: () async {
                    await ref.read(matchControllerProvider.notifier).start(saved.setup, resume: saved);
                    if (context.mounted) context.go(MatchRoutes.play);
                  },
                ),
                const SizedBox(height: AppSpacing.m),
              ],
              MatchEntryCard(
                key: const Key('open-opponent-mode'),
                icon: Icons.people_alt_rounded,
                title: l10n.matchOpponentTitle,
                description: l10n.matchOpponentText,
                onTap: () => context.go(MatchRoutes.opponent),
              ),
              const SizedBox(height: AppSpacing.m),
              MatchEntryCard(
                key: const Key('open-tournament'),
                icon: Icons.emoji_events_rounded,
                title: l10n.tournamentTitle,
                description: running
                    ? l10n.tournamentRunning(l10n.tourRoundName(tournament.currentRound))
                    : l10n.tournamentText,
                highlight: running,
                onTap: () => context.go(tournament != null ? MatchRoutes.tournament : MatchRoutes.tournamentNew),
              ),
              const SizedBox(height: AppSpacing.m),
              MatchEntryCard(
                key: const Key('open-cpu-players'),
                icon: Icons.smart_toy_outlined,
                title: l10n.cpuPlayersTitle,
                description: '${l10n.cpuPlayersText} ${l10n.cpuCount(cpus.length)}.',
                onTap: () => context.go(MatchRoutes.cpuPlayers),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Karte mit Icon, Titel und Beschreibung (wie die Spielkarten).
class MatchEntryCard extends StatelessWidget {
  const MatchEntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final accent = highlight ? colors.success : theme.colorScheme.primary;
    return AppCard(
      onTap: onTap,
      child: Row(
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
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.textMuted),
        ],
      ),
    );
  }
}
