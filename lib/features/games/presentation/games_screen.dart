import 'package:flutter/material.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';

/// Übersicht der Trainingsspiele. In Phase 1 nur Vorschau, die Regel-Engine
/// kommt in Phase 2 und 3.
class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final games = [
      (Icons.flag_rounded, l10n.gameCheckout, l10n.gameCheckoutDesc, 2),
      (Icons.av_timer_rounded, l10n.gameAroundClock, l10n.gameAroundClockDesc, 2),
      (Icons.trip_origin_rounded, l10n.gameBullDrill, l10n.gameBullDrillDesc, 2),
      (Icons.trending_up_rounded, l10n.gameScoring, l10n.gameScoringDesc, 2),
      (Icons.grid_on_rounded, l10n.gameCricket, l10n.gameCricketDesc, 3),
      (Icons.filter_1_rounded, l10n.game121, l10n.game121Desc, 3),
      (Icons.looks_two_rounded, l10n.gameBobs27, l10n.gameBobs27Desc, 3),
      (Icons.repeat_rounded, l10n.gameThreeHits, l10n.gameThreeHitsDesc, 3),
      (Icons.fast_forward_rounded, l10n.gameSkip, l10n.gameSkipDesc, 3),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.gamesTitle)),
      body: LayoutBuilder(builder: (context, c) {
        final columns = (c.maxWidth / 360).floor().clamp(1, 3);
        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.page),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.m,
            crossAxisSpacing: AppSpacing.m,
            mainAxisExtent: 128,
          ),
          itemCount: games.length,
          itemBuilder: (context, i) {
            final (icon, title, desc, phase) = games[i];
            return _GameCard(icon: icon, title: title, description: desc, phase: phase);
          },
        );
      }),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.icon, required this.title, required this.description, required this.phase});

  final IconData icon;
  final String title;
  final String description;
  final int phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.dartColors;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadii.m),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                    StatusPill(label: context.l10n.gamesPhase(phase), color: colors.textMuted),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
