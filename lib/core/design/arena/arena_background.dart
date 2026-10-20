import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'arena_palette.dart';

/// Grund der Arena: Marineblau mit großen, kaum sichtbaren Dreiecken und
/// einem fast schwarzen Streifen am oberen Rand.
class ArenaBackground extends StatelessWidget {
  const ArenaBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(child: CustomPaint(painter: _BackgroundPainter())),
        child,
      ],
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ArenaPalette.backgroundMid, ArenaPalette.background, ArenaPalette.backgroundLight],
        ).createShader(Offset.zero & size),
    );

    void shape(List<Offset> pts, double opacity) {
      final path = Path()..moveTo(pts.first.dx * w, pts.first.dy * h);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx * w, p.dy * h);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = ArenaPalette.shape.withValues(alpha: opacity));
    }

    // Große Dreiecke wie im Vorbild: links oben, links unten, in der Mitte
    // und rechts unten, jeweils nur ein Hauch heller als der Grund.
    shape(const [Offset(0.11, 0), Offset(0.19, 0), Offset(0.06, 0.26)], 0.10);
    shape(const [Offset(0, 0.76), Offset(0.24, 1), Offset(0, 1)], 0.12);
    shape(const [Offset(0.26, 0.57), Offset(0.35, 0.57), Offset(0.35, 0.73), Offset(0.26, 0.71)], 0.07);
    shape(const [Offset(1, 0.64), Offset(1, 1), Offset(0.74, 1)], 0.06);

    // Schmaler dunkler Streifen ganz oben.
    final strip = math.min(26.0, h * 0.02);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, strip), Paint()..color = ArenaPalette.stripe);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
