import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dart_colors.dart';
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

/// Legt einen weichen runden Leuchtring mit Statuswort um die Scheibe, solange
/// die Quelle ein lokales Autodarts-Board ist. Die Scheibe wird dafür leicht
/// verkleinert gezeichnet ([discScale]), der Glow läuft in dem frei werdenden
/// Rand aus. Das Layout bleibt gleich groß: Die Fläche ändert sich nicht, der
/// Glow wird nie abgeschnitten. Die Farbe ist nie allein: Icon und Wort stehen
/// dabei, dazu eine Semantics-Beschriftung für Screenreader.
class BoardStatusFrame extends ConsumerWidget {
  const BoardStatusFrame({super.key, required this.child});
  final Widget child;

  /// Anteil der Fläche, den die Scheibe mit Glow einnimmt (Rest ist Glow).
  static const double discScale = 0.88;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(boardReadinessProvider);
    // Feste Plätze, damit der Zustand der Scheibe beim Ein- und Ausblenden erhalten bleibt.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        readiness == null ? const SizedBox.shrink() : Positioned.fill(child: _Glow(readiness: readiness)),
        Transform.scale(scale: readiness == null ? 1 : discScale, child: child),
        readiness == null ? const SizedBox.shrink() : Positioned.fill(child: _StatusChip(readiness: readiness)),
      ],
    );
  }
}

/// Kreisförmiger Glow, der dem Umriss der Scheibe folgt und nach außen weich ausläuft.
class _Glow extends StatelessWidget {
  const _Glow({required this.readiness});
  final BoardReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final color = readiness.color(context.dartColors);
    return IgnorePointer(
      key: const Key('board-frame'),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: AppDurations.medium,
        builder: (context, animated, _) => CustomPaint(painter: _GlowPainter(animated ?? color)),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    const d = BoardStatusFrame.discScale;
    // Kräftig direkt am Scheibenrand (unter der Scheibe verdeckt), dann weich auslaufend.
    const alphas = [0.95, 0.9, 0.62, 0.4, 0.2, 0.07, 0.0];
    final shader = RadialGradient(
      colors: [for (final a in alphas) color.withValues(alpha: color.a * a)],
      stops: const [d - 0.08, d, d + 0.02, d + 0.04, d + 0.07, d + 0.1, 1],
    ).createShader(rect);
    canvas.drawCircle(rect.center, r, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.color != color;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.readiness});
  final BoardReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final c = readiness.color(context.dartColors);
    final label = readiness.label(l10n);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
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
      ),
    );
  }
}
