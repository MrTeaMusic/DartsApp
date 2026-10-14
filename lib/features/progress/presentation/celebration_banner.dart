import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import 'celebrations.dart';
import 'progress_texts.dart';

/// Kurze Einblendung im Spiel, wenn das Tagesziel erreicht oder ein Erfolg
/// freigeschaltet wurde. Schwebt unten über dem Spiel (siehe
/// [CelebrationOverlay]), verschwindet nach [duration] von selbst oder beim
/// Antippen.
class CelebrationBanner extends ConsumerStatefulWidget {
  const CelebrationBanner({super.key, this.duration = const Duration(seconds: 5)});
  final Duration duration;

  @override
  ConsumerState<CelebrationBanner> createState() => _CelebrationBannerState();
}

class _CelebrationBannerState extends ConsumerState<CelebrationBanner> {
  CelebrationBatch? _shown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ref.listenManual(celebrationsProvider, (_, next) {
      if (next == null || identical(next, _shown)) return;
      _timer?.cancel();
      setState(() => _shown = next);
      _timer = Timer(widget.duration, () {
        if (mounted) setState(() => _shown = null);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final batch = _shown;
    final theme = Theme.of(context);
    final look = context.look;
    Widget card(Widget banner, {required bool first}) => Padding(
          padding: EdgeInsets.only(top: first ? 0 : AppSpacing.s),
          // Deckende Fläche, damit die Einblendung über dem Spiel lesbar ist.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(look.radiusL),
              boxShadow: [BoxShadow(color: theme.colorScheme.shadow.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6))],
            ),
            child: banner,
          ),
        );
    final Widget child = batch == null
        ? const SizedBox(width: double.infinity)
        : GestureDetector(
            key: ValueKey(batch.serial),
            onTap: () => setState(() => _shown = null),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, item) in batch.items.take(3).indexed)
                  card(first: i == 0, switch (item) {
                    GoalCelebration(:final goal) => LookBanner(
                        key: const Key('celebration-goal'),
                        kicker: l10n.dgReached,
                        text: l10n.dgCelebration(goal.amount, l10n.goalUnit(goal.unit)),
                        color: colors.success,
                      ),
                    AchievementCelebration(:final def, :final tier) => LookBanner(
                        key: Key('celebration-${def.id}'),
                        kicker: l10n.achCelebration,
                        text: [l10n.achievementTitle(def.id), ?l10n.tierName(def, tier)].join(' · '),
                        color: tierColor(colors, def, tier),
                      ),
                  }),
              ],
            ),
          );
    return IgnorePointer(
      ignoring: batch == null,
      child: AnimatedSwitcher(
        duration: AppDurations.medium,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a), child: child),
        ),
        child: child,
      ),
    );
  }
}

/// Legt die [CelebrationBanner]-Einblendung unten über [child]. Oben stehen
/// Spielstand und Aufgabe, die bleiben sichtbar.
///
/// Ab [wideWidth] steht rechts eine Seitenleiste mit [sideWidth]; die
/// Einblendung steht dann mittig unter dem Board, damit sie keine Knöpfe der
/// Leiste verdeckt.
class CelebrationOverlay extends StatelessWidget {
  const CelebrationOverlay({super.key, required this.child, this.sideWidth = 0, this.wideWidth = 900});
  final Widget child;
  final double sideWidth;
  final double wideWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth >= wideWidth ? sideWidth : 0.0;
      return Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            bottom: AppSpacing.l,
            left: AppSpacing.l,
            right: AppSpacing.l + side,
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: const CelebrationBanner()),
            ),
          ),
        ],
      );
    });
  }
}
