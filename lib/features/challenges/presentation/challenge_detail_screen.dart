import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../games/presentation/game_texts.dart';
import '../../progress/presentation/progress_providers.dart';
import '../../progress/presentation/progress_texts.dart';
import '../domain/challenge.dart';
import '../domain/challenge_catalog.dart';
import 'challenge_texts.dart';
import 'challenge_widgets.dart';

/// Eine Challenge: Aufgabe, Sterne-Schwellen, Bestwert und Start.
class ChallengeDetailScreen extends ConsumerStatefulWidget {
  const ChallengeDetailScreen({super.key, required this.challengeId});
  final String challengeId;

  @override
  ConsumerState<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends ConsumerState<ChallengeDetailScreen> {
  bool _busy = false;

  Future<void> _start(Challenge c) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await launchChallenge(context, ref, c);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final c = ChallengeCatalog.byId(widget.challengeId);
    if (c == null) return Scaffold(appBar: AppBar());
    final results = ref.watch(challengeResultsProvider).value ?? const <ChallengeBest>[];
    final progress = ChallengeProgress(results);
    final best = progress.best[c.id];
    final stars = best?.stars ?? 0;
    final unlocked = progress.unlocked(c);
    final m = c.match;

    return Scaffold(
      appBar: AppPageBar(maxWidth: 640, title: Text(l10n.challengeCode(c))),
      body: AppPage(
        maxWidth: 640,
        listKey: const Key('challenge-detail'),
        children: [
          Text(l10n.challengeName(c), key: const Key('challenge-name'), style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.s),
          StarRow(count: stars, size: 28),
          const SectionGap(factor: 0.8),
          SectionHeader(l10n.chalTask),
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(icon: gameIcon(c.gameId)),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Kicker(l10n.gameTitle(c.gameId)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(l10n.challengeTask(c), key: const Key('challenge-task-detail'), style: theme.textTheme.bodyLarge),
                      if (m != null) ...[
                        const SizedBox(height: AppSpacing.s),
                        Text(l10n.chalMatchFormat(m.bestOf), style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
                        Text(l10n.chalOpponent(m.botAverage.round()), style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          if (!unlocked) ...[
            Row(
              children: [
                Icon(Icons.lock_rounded, size: 18, color: colors.textMuted),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    progress.chapterUnlocked(c.chapter)
                        ? l10n.chalLockedHint
                        : l10n.chalChapterLocked(
                            ChallengeCatalog.starsToUnlockNext, l10n.chapterName(ChallengeChapter.values[c.chapter.index - 1])),
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
          ],
          FilledButton.icon(
            key: const Key('challenge-start'),
            onPressed: unlocked && !_busy ? () => _start(c) : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(l10n.chalStart),
          ),
          const SectionGap(factor: 0.8),
          SectionHeader(l10n.chalStarsTitle),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 1; i <= 3; i++)
                  ListTile(
                    key: Key('challenge-star-$i'),
                    leading: SizedBox(width: 72, child: Align(alignment: Alignment.centerLeft, child: StarRow(count: i, max: i, size: 22))),
                    title: Text(
                      l10n.starRule(c, i),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: stars >= i ? FontWeight.w700 : null,
                        color: stars >= i ? theme.colorScheme.onSurface : null,
                      ),
                    ),
                    trailing: stars >= i ? Icon(Icons.check_circle_rounded, color: colors.success) : null,
                  ),
              ],
            ),
          ),
          const SectionGap(factor: 0.8),
          SectionHeader(l10n.chalBest),
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        best == null
                            ? l10n.chalNoAttempt
                            : best.best == null
                                ? l10n.chalResultStars(best.stars)
                                : l10n.challengeValueWithUnit(c, best.best!),
                        key: const Key('challenge-best'),
                        style: look.statValue.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontSize: best == null ? theme.textTheme.titleMedium?.fontSize : null,
                        ),
                      ),
                      if (best != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          '${l10n.chalAttempts(best.attempts)} · ${shortDate(best.achievedAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          Text(l10n.chalRules, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }
}
