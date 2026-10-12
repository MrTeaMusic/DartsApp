import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../games/presentation/active_game_controller.dart';
import '../../matches/domain/match_result.dart';
import '../../matches/presentation/match_controller.dart';
import '../../matches/presentation/match_routes.dart';
import '../../progress/presentation/progress_providers.dart';
import '../domain/challenge.dart';
import 'challenge_routes.dart';
import 'challenge_run_controller.dart';
import 'challenge_texts.dart';

/// Startet [c] und öffnet die passende Spielansicht.
Future<void> launchChallenge(BuildContext context, WidgetRef ref, Challenge c) async {
  final router = GoRouter.of(context);
  await ref.read(challengeRunProvider.notifier).start(c);
  router.go(c.isMatch ? MatchRoutes.play : Routes.play);
}

/// Beendet das Spiel bzw. Match der Challenge und geht zu [location].
Future<void> leaveChallenge(BuildContext context, WidgetRef ref, String location) async {
  final router = GoRouter.of(context);
  final run = ref.read(challengeRunProvider);
  ref.read(challengeRunProvider.notifier).clear();
  if (run?.match != null) {
    await ref.read(matchControllerProvider.notifier).close();
  } else {
    await ref.read(activeGameProvider.notifier).close();
  }
  router.go(location);
}

/// Die laufende Challenge, falls ihr das gezeigte Spiel gehört, mit den
/// Kennzahlen des Spiels.
({ChallengeRun run, Map<String, num> metrics, bool over})? _current(WidgetRef ref) {
  final run = ref.watch(challengeRunProvider);
  if (run == null) return null;
  final game = ref.watch(activeGameProvider);
  if (run.ownsGame(game)) return (run: run, metrics: game!.game.result.metrics, over: game.ended);
  final match = ref.watch(matchControllerProvider);
  if (run.ownsMatch(match)) {
    final human = match!.setup.players.indexWhere((p) => !p.isBot);
    return (run: run, metrics: matchResultFor(match.match, human, match.setup).metrics, over: match.ended);
  }
  return null;
}

/// Drei Sterne, die ersten [count] gefüllt.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.count, this.size = 18, this.max = 3});
  final int count;
  final int max;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < max; i++)
          Icon(
            i < count ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i < count ? colors.record : colors.textMuted.withValues(alpha: 0.6),
          ),
      ],
    );
  }
}

/// Live-Sterne: sicher, vorläufig, offen oder verloren.
class LiveStarRow extends StatelessWidget {
  const LiveStarRow({super.key, required this.states, this.size = 26});
  final List<StarState> states;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, s) in states.indexed)
          AnimatedSwitcher(
            duration: AppDurations.medium,
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: Icon(
              switch (s) {
                StarState.reached || StarState.provisional => Icons.star_rounded,
                _ => Icons.star_outline_rounded,
              },
              key: ValueKey('star-$i-${s.name}'),
              size: size,
              color: switch (s) {
                StarState.reached => colors.record,
                StarState.provisional => colors.record.withValues(alpha: 0.5),
                StarState.open => colors.textMuted,
                StarState.lost => colors.textMuted.withValues(alpha: 0.3),
              },
            ),
          ),
      ],
    );
  }
}

/// Aufgabe der laufenden Challenge über dem Spielstand, mit Live-Sternen.
class ChallengeTaskBar extends ConsumerWidget {
  const ChallengeTaskBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = _current(ref);
    // Nach dem Ende zeigt die Wertung alles Nötige.
    if (current == null || current.over) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final c = current.run.challenge;
    final states = c.liveStars(current.metrics, over: current.over);
    final live = c.isMatch ? current.metrics['average'] : current.metrics[c.liveKey ?? c.scoreKey];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: AppCard(
        key: const Key('challenge-task'),
        padding: EdgeInsets.symmetric(horizontal: context.look.cardPadding, vertical: AppSpacing.m),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Kicker('${l10n.chalTitle} · ${l10n.challengeCode(c)}', color: colors.record),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.challengeTask(c),
                    key: const Key('challenge-task-text'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                LiveStarRow(key: const Key('challenge-live-stars'), states: states),
                if (live != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.chalNow(l10n.challengeValueWithUnit(c, live)),
                    style: context.look.kicker.copyWith(color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Wertung am Ende einer Challenge: Sterne mit Animation, Ergebnis,
/// Bestwert, was neu frei ist, und die nächsten Schritte.
class ChallengeResultPanel extends ConsumerWidget {
  const ChallengeResultPanel({super.key});

  /// Gehört das gezeigte, beendete Spiel einer Challenge? Dann ersetzt die
  /// Wertung die normalen Knöpfe.
  static bool shows(WidgetRef ref) {
    final run = ref.watch(challengeRunProvider);
    if (run == null) return false;
    final game = ref.watch(activeGameProvider);
    if (run.ownsGame(game)) return game!.ended;
    final match = ref.watch(matchControllerProvider);
    return run.ownsMatch(match) && match!.ended;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = _current(ref);
    if (current == null || !current.over) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final run = current.run;
    final c = run.challenge;
    final outcome = run.outcome;
    final results = ref.watch(challengeResultsProvider).value ?? const <ChallengeBest>[];
    final next = outcome == null ? null : nextChallenge(c, results);

    // Hauptaktion oben in voller Breite, darunter die beiden anderen.
    final again = next == null;
    final buttons = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: Key(again ? 'challenge-again' : 'challenge-next'),
          onPressed: () => launchChallenge(context, ref, next ?? c),
          icon: Icon(again ? Icons.replay_rounded : Icons.arrow_forward_rounded),
          label: Text(next == null ? l10n.chalAgain : '${l10n.chalNext}: ${l10n.challengeName(next)}',
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(height: AppSpacing.s),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('challenge-overview'),
                onPressed: () => leaveChallenge(context, ref, ChallengeRoutes.list),
                icon: const Icon(Icons.grid_view_rounded),
                label: Text(l10n.chalOverview),
              ),
            ),
            if (!again) ...[
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('challenge-again'),
                  onPressed: () => launchChallenge(context, ref, c),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(l10n.chalAgain),
                ),
              ),
            ],
          ],
        ),
      ],
    );

    if (run.aborted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.m),
        child: AppCard(
          key: const Key('challenge-result'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Kicker(l10n.challengeCode(c)),
              const SizedBox(height: AppSpacing.xs),
              Text(l10n.chalAborted, key: const Key('challenge-aborted'), style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.l),
              buttons,
            ],
          ),
        ),
      );
    }
    if (outcome == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.m),
        child: AppCard(child: Text(l10n.chalSaving, style: theme.textTheme.bodyMedium)),
      );
    }

    final score = outcome.score;
    final previous = outcome.previous;
    final notes = <(IconData, String, Color)>[
      if (outcome.newBest && (previous != null || outcome.stars > 0))
        (Icons.emoji_events_rounded, l10n.chalNewBest, colors.record)
      else if (previous?.best != null)
        (Icons.history_rounded, l10n.chalBestSoFar(l10n.challengeValueWithUnit(c, previous!.best!)), colors.textMuted),
      if (outcome.unlockedChapter case final ch?)
        (Icons.lock_open_rounded, l10n.chalUnlockedChapter(l10n.chapterName(ch)), colors.success)
      else if (outcome.unlockedChallenge case final u?)
        (Icons.lock_open_rounded, l10n.chalUnlockedChallenge(l10n.challengeName(u)), colors.success),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: AppCard(
        key: const Key('challenge-result'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Kicker('${l10n.chalTitle} · ${l10n.challengeCode(c)}', color: colors.record),
            const SizedBox(height: AppSpacing.xxs),
            Text(l10n.challengeName(c), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.l),
            Center(child: AnimatedStars(key: const Key('challenge-stars'), count: outcome.stars)),
            const SizedBox(height: AppSpacing.m),
            Text(
              outcome.stars == 0 ? l10n.chalResultNone : l10n.chalResultStars(outcome.stars),
              key: const Key('challenge-result-text'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (score != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                l10n.chalResultScore(l10n.challengeValueWithUnit(c, score)),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted),
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.m),
              for (final (icon, text, color) in notes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: color),
                      const SizedBox(width: AppSpacing.s),
                      Flexible(
                        child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.l),
            buttons,
          ],
        ),
      ),
    );
  }
}

/// Drei große Sterne, die nacheinander aufploppen.
class AnimatedStars extends StatefulWidget {
  const AnimatedStars({super.key, required this.count, this.size = 56});
  final int count;
  final double size;

  @override
  State<AnimatedStars> createState() => _AnimatedStarsState();
}

class _AnimatedStarsState extends State<AnimatedStars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            () {
              final on = i < widget.count;
              final start = 0.1 + i * 0.25;
              final t = on ? Curves.elasticOut.transform(((_c.value - start) / 0.45).clamp(0, 1).toDouble()) : 1.0;
              final big = i == 1 ? 1.2 : 1.0;
              return Padding(
                padding: EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.xs, bottom: i == 1 ? AppSpacing.s : 0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.star_rounded, size: widget.size * big, color: colors.surfaceHigh),
                    if (on)
                      Transform.scale(
                        scale: t,
                        child: Icon(Icons.star_rounded, size: widget.size * big, color: colors.record),
                      ),
                  ],
                ),
              );
            }(),
        ],
      ),
    );
  }
}

/// Wo eine abgebrochene oder beendete Challenge hinführt.
String challengeLeaveLocation(ChallengeRun run) => ChallengeRoutes.detail(run.challenge.id);

/// Sterne im Kapitel als kleine Kennzeichnung, z. B. „★ 14 / 24“.
class ChapterStars extends StatelessWidget {
  const ChapterStars({super.key, required this.stars, required this.total});
  final int stars;
  final int total;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final colors = context.dartColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 18, color: colors.record),
        const SizedBox(width: AppSpacing.xxs),
        Text(context.l10n.chalStarsOf(stars, total), style: look.kicker.copyWith(color: colors.textMuted)),
      ],
    );
  }
}
