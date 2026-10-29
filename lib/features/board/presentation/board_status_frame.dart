import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../dart_source/domain/board_control.dart';
import '../../dart_source/presentation/board_help.dart';
import '../../dart_source/presentation/dart_source_providers.dart';
import 'live_visit_controller.dart';

/// Zustand des Autodarts-Boards für den Rahmen um die Scheibe; null bei allen
/// anderen Quellen und in Lite (dann gibt es keinen Rahmen).
final boardReadinessProvider = Provider<BoardReadiness?>((ref) {
  final control = ref.watch(boardControlProvider);
  if (control == null) return null;
  final source = ref.watch(dartSourceProvider);
  final status = ref.watch(sourceStatusProvider).value ?? source.status;
  final takeout = ref.watch(liveVisitProvider.select((s) => s.takeoutInProgress));
  final running = ref.watch(boardRunningProvider).value;
  return boardReadiness(status, takeout: takeout, running: running);
});

extension BoardReadinessLook on BoardReadiness {
  String label(AppLocalizations l10n) => switch (this) {
        BoardReadiness.ready => l10n.boardStateReady,
        BoardReadiness.takeout => l10n.boardStateTakeout,
        BoardReadiness.stopped => l10n.boardStateStopped,
        BoardReadiness.connecting => l10n.boardStateConnecting,
        BoardReadiness.offline => l10n.boardStateOffline,
      };

  IconData get icon => switch (this) {
        BoardReadiness.ready => Icons.check_circle_rounded,
        BoardReadiness.takeout => Icons.back_hand_rounded,
        BoardReadiness.stopped => Icons.pause_circle_rounded,
        BoardReadiness.connecting => Icons.sync_rounded,
        BoardReadiness.offline => Icons.cloud_off_rounded,
      };

  /// Grün bereit, gelb Takeout, rot offline; „Verbinde“ ist gedämpftes Rot,
  /// „Gestoppt“ grau.
  Color color(DartColors c) => switch (this) {
        BoardReadiness.ready => c.success,
        BoardReadiness.takeout => c.warning,
        BoardReadiness.stopped => c.textMuted,
        BoardReadiness.connecting => c.danger.withValues(alpha: 0.55),
        BoardReadiness.offline => c.danger,
      };
}

/// Legt einen dünnen farbigen Rahmen mit Statuswort um die Scheibe, solange
/// die Quelle ein lokales Autodarts-Board ist. Der Rahmen liegt über dem Kind
/// (innerhalb seiner Fläche) und verschiebt das Layout nicht. Die Farbe ist nie
/// allein: Icon und Wort stehen dabei, und eine Semantics-Beschriftung für
/// Screenreader.
class BoardStatusFrame extends ConsumerWidget {
  const BoardStatusFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(boardReadinessProvider);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (readiness != null) Positioned.fill(child: _Frame(readiness: readiness)),
      ],
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.readiness});
  final BoardReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final color = readiness.color(context.dartColors);
    final radius = BorderRadius.circular(context.look.radiusL.clamp(8, 22));
    final label = readiness.label(l10n);
    return IgnorePointer(
      key: const Key('board-frame'),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: AppDurations.medium,
        builder: (context, animated, _) {
          final c = animated ?? color;
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: c, width: 3)),
                ),
              ),
              Positioned(
                left: AppSpacing.s,
                top: AppSpacing.s,
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  label: l10n.boardStateSemantics(label),
                  child: ExcludeSemantics(
                    child: Container(
                      key: Key('board-frame-${readiness.name}'),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(color: c, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(readiness.icon, size: 15, color: c),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            label,
                            maxLines: 1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
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
