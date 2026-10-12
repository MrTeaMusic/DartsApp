import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../progress/presentation/progress_providers.dart';
import '../domain/challenge.dart';
import '../domain/challenge_catalog.dart';
import 'challenge_routes.dart';
import 'challenge_texts.dart';
import 'challenge_widgets.dart';

/// Kapitel des Challenge-Modus mit ihren Aufgaben und Sternen.
class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final results = ref.watch(challengeResultsProvider).value ?? const <ChallengeBest>[];
    final progress = ChallengeProgress(results);
    final total = ChallengeCatalog.all.length * 3;

    return Scaffold(
      appBar: AppPageBar(maxWidth: 1040, title: Text(l10n.chalTitle)),
      body: AppPage(
        maxWidth: 1040,
        listKey: const Key('challenges-list'),
        children: [
          AppCard(
            key: const Key('challenges-summary'),
            child: Row(
              children: [
                Icon(Icons.star_rounded, size: 44, color: colors.record),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.chalStarsTotal(progress.totalStars, total),
                        key: const Key('challenges-total'),
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(l10n.chalEntryText, style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted)),
                      const SizedBox(height: AppSpacing.s),
                      LookProgressBar(value: progress.totalStars / total, color: colors.record),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final ch in ChallengeChapter.values) ...[
            const SectionGap(factor: 0.8),
            _Chapter(chapter: ch, progress: progress),
          ],
        ],
      ),
    );
  }
}

class _Chapter extends StatelessWidget {
  const _Chapter({required this.chapter, required this.progress});
  final ChallengeChapter chapter;
  final ChallengeProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final open = progress.chapterUnlocked(chapter);
    final header = SectionHeader(
      '${l10n.chalChapterLabel(chapter.index + 1)} · ${l10n.chapterName(chapter)}',
      trailing: open
          ? ChapterStars(stars: progress.chapterStars(chapter), total: ChallengeProgress.maxStars(chapter))
          : Icon(Icons.lock_rounded, size: 18, color: colors.textMuted),
    );
    if (!open) {
      final previous = ChallengeChapter.values[chapter.index - 1];
      final have = progress.chapterStars(previous);
      const need = ChallengeCatalog.starsToUnlockNext;
      return Column(
        key: Key('chapter-${chapter.name}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          AppCard(
            key: Key('chapter-${chapter.name}-locked'),
            child: Row(
              children: [
                IconBadge(icon: Icons.lock_rounded, color: colors.textMuted),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.chalChapterLocked(need, l10n.chapterName(previous)),
                        style: theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      Row(
                        children: [
                          Expanded(child: LookProgressBar(value: have / need, color: colors.record)),
                          const SizedBox(width: AppSpacing.m),
                          Text(l10n.chalStarsOf(have > need ? need : have, need), style: look.kicker.copyWith(color: colors.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      key: Key('chapter-${chapter.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        LayoutBuilder(builder: (context, c) {
          final columns = c.maxWidth >= 880 ? 4 : 2;
          final gap = look.gridGap;
          final width = (c.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final ch in ChallengeCatalog.ofChapter(chapter))
                SizedBox(width: width, child: _ChallengeTile(challenge: ch, progress: progress)),
            ],
          );
        }),
      ],
    );
  }
}

class _ChallengeTile extends StatelessWidget {
  const _ChallengeTile({required this.challenge, required this.progress});
  final Challenge challenge;
  final ChallengeProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final c = challenge;
    final unlocked = progress.unlocked(c);
    final best = progress.best[c.id];
    final stars = best?.stars ?? 0;
    final caption = !unlocked
        ? l10n.chalLocked
        : best?.best != null
            ? '${l10n.chalBest}: ${l10n.challengeValueWithUnit(c, best!.best!)}'
            : best == null
                ? l10n.chalNoAttempt
                : l10n.chalAttempts(best.attempts);
    return Opacity(
      opacity: unlocked ? 1 : 0.55,
      child: AppCard(
        key: Key('challenge-${c.id}'),
        onTap: () => context.go(ChallengeRoutes.detail(c.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stars == 3 ? colors.record.withValues(alpha: 0.18) : colors.surfaceHigh,
                  ),
                  child: unlocked
                      ? Text('${c.number}', style: look.kicker.copyWith(color: theme.colorScheme.onSurface))
                      : Icon(Icons.lock_rounded, size: 15, color: colors.textMuted),
                ),
                const Spacer(),
                StarRow(count: stars, size: 20),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  l10n.challengeName(c),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
