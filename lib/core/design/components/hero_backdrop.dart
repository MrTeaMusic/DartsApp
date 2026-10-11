import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dart_colors.dart';
import '../dart_look.dart';

/// Hintergrund großer Kopfflächen (Startseite): TV mit Streifen und
/// Board-Ringen, Clean mit weichen Ringen, Lab mit feinem Raster.
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({super.key, required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final colors = context.dartColors;
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final radius = BorderRadius.circular(look.id == DartLookId.clean ? look.radiusXL : look.radiusL);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: look.id == DartLookId.clean && light ? look.shadow : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.heroStart, colors.heroEnd],
            ),
            border: look.card == CardTreatment.outlined ? Border.all(color: theme.colorScheme.outline) : null,
            borderRadius: radius,
          ),
          child: CustomPaint(
            painter: _BackdropPainter(look: look.id, accent: theme.colorScheme.primary, line: theme.colorScheme.onSurface, light: light),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.look, required this.accent, required this.line, required this.light});
  final DartLookId look;
  final Color accent;
  final Color line;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    switch (look) {
      case DartLookId.tv:
        // Akzentkante links wie eine Bauchbinde.
        canvas.drawRect(Rect.fromLTWH(0, 0, 6, size.height), Paint()..color = accent);
        // Schräge Streifen rechts.
        final stripe = Paint()..color = line.withValues(alpha: 0.035);
        for (var i = 0; i < 9; i++) {
          final x = size.width * 0.55 + i * 34.0;
          canvas.drawPath(
            Path()
              ..moveTo(x, size.height)
              ..lineTo(x + 16, size.height)
              ..lineTo(x + 16 + size.height * 0.6, 0)
              ..lineTo(x + size.height * 0.6, 0)
              ..close(),
            stripe,
          );
        }
        _rings(canvas, Offset(size.width - size.height * 0.15, size.height * 0.5), size.height * 0.95, accent.withValues(alpha: 0.22), 2);
      case DartLookId.clean:
        final c = Offset(size.width - size.height * 0.25, size.height * 0.15);
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            c,
            size.height * (0.55 + i * 0.28),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 18
              ..color = accent.withValues(alpha: (light ? 0.07 : 0.10) - i * 0.02),
          );
        }
      case DartLookId.lab:
        final grid = Paint()
          ..color = line.withValues(alpha: 0.05)
          ..strokeWidth = 1;
        const step = 24.0;
        for (var x = step; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
        }
        for (var y = step; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
        }
        final c = Offset(size.width - size.height * 0.55, size.height * 0.5);
        _rings(canvas, c, size.height * 0.42, accent.withValues(alpha: 0.35), 1);
        final cross = Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..strokeWidth = 1;
        canvas.drawLine(c - Offset(size.height * 0.5, 0), c + Offset(size.height * 0.5, 0), cross);
        canvas.drawLine(c - Offset(0, size.height * 0.5), c + Offset(0, size.height * 0.5), cross);
    }
  }

  /// Konzentrische Ringe in den Proportionen eines Dartboards.
  void _rings(Canvas canvas, Offset c, double r, Color color, double width) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    for (final f in const [1.0, 0.94, 0.63, 0.57, 0.09, 0.037]) {
      canvas.drawCircle(c, r * f, p);
    }
    for (var i = 0; i < 20; i++) {
      final a = (i * 18 + 9) * math.pi / 180;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r * 0.09, c + Offset(math.cos(a), math.sin(a)) * r, p..strokeWidth = width * 0.5);
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.look != look || old.accent != accent || old.light != light || old.line != line;
}
