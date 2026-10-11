import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/design/app_theme.dart';
import '../../../core/design/dart_colors.dart';
import '../domain/board_geometry.dart';
import '../domain/segment.dart';

/// Ein Treffer, der auf dem Board markiert wird.
@immutable
class HitMarker {
  const HitMarker(this.position, {this.latest = false});
  final BoardPoint position;
  final bool latest;
}

/// Zeichnet ein Steeldartboard samt Treffern, Hervorhebungen und Heatmap.
///
/// Koordinaten: siehe [BoardPoint]. Radius 1.0 = Außenkante Double-Ring.
class DartboardPainter extends CustomPainter {
  DartboardPainter({
    required this.colors,
    this.hits = const [],
    this.hitProgress = 1,
    this.highlighted = const {},
    this.highlightStrength = 0,
    this.flash,
    this.flashStrength = 0,
    this.hover,
    this.heat = const [],
    this.heatOpacity = 0.0,
    this.showNumbers = true,
  });

  /// Außenradius des Boards (inkl. Zahlenring) relativ zum Double-Ring.
  static const double outerExtent = 1.24;

  final DartColors colors;
  final List<HitMarker> hits;

  /// 0 → 1: Fortschritt der Trefferanimation des neuesten Darts.
  final double hitProgress;

  /// Dauerhaft hervorgehobene Felder (z. B. Ziel im Training).
  final Set<Segment> highlighted;
  final double highlightStrength;

  /// Kurz aufleuchtendes Feld (zuletzt getroffen).
  final Segment? flash;
  final double flashStrength;

  /// Feld unter dem Mauszeiger (Desktop).
  final Segment? hover;

  final List<BoardPoint> heat;
  final double heatOpacity;
  final bool showNumbers;

  /// Radius des Double-Rings in Pixeln für eine gegebene Größe.
  static double ringRadius(Size size) => size.shortestSide / 2 / outerExtent;

  /// Pixelposition → Board-Koordinate.
  static BoardPoint toBoard(Offset local, Size size) {
    final r = ringRadius(size);
    final c = size.center(Offset.zero);
    return BoardPoint((local.dx - c.dx) / r, -(local.dy - c.dy) / r);
  }

  /// Board-Koordinate → Pixelposition.
  static Offset toCanvas(BoardPoint p, Size size) {
    final r = ringRadius(size);
    final c = size.center(Offset.zero);
    return Offset(c.dx + p.x * r, c.dy - p.y * r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = ringRadius(size);

    // Umrandung
    canvas.drawCircle(c, r * outerExtent, Paint()..color = colors.boardSurround);

    // Felder
    for (var i = 0; i < 20; i++) {
      final number = BoardGeometry.numbers[i];
      final even = i.isEven;
      final single = even ? colors.boardBlack : colors.boardCream;
      final ring = even ? colors.boardRed : colors.boardGreen;
      final start = _canvasAngle(i * 18.0 - 9);
      const sweep = 18 * math.pi / 180;
      void fill(double r1, double r2, Color color) =>
          canvas.drawPath(_sector(c, r1 * r, r2 * r, start, sweep), Paint()..color = color);
      fill(BoardGeometry.outerBullR, BoardGeometry.tripleInnerR, single);
      fill(BoardGeometry.tripleInnerR, BoardGeometry.tripleOuterR, ring);
      fill(BoardGeometry.tripleOuterR, BoardGeometry.doubleInnerR, single);
      fill(BoardGeometry.doubleInnerR, BoardGeometry.doubleOuterR, ring);
      if (showNumbers) _number(canvas, c, r, i, number);
    }
    canvas.drawCircle(c, BoardGeometry.outerBullR * r, Paint()..color = colors.boardGreen);
    canvas.drawCircle(c, BoardGeometry.innerBullR * r, Paint()..color = colors.boardRed);

    _wires(canvas, c, r);

    // Heatmap
    if (heatOpacity > 0 && heat.isNotEmpty) _heat(canvas, size, r);

    // Hover
    if (hover != null && !hover!.isMiss) {
      canvas.drawPath(segmentPath(hover!, c, r), Paint()..color = Colors.white.withValues(alpha: 0.18));
    }

    // Hervorhebungen
    if (highlighted.isNotEmpty && highlightStrength > 0) {
      for (final s in highlighted) {
        _glow(canvas, segmentPath(s, c, r), colors.highlight, highlightStrength);
      }
    }
    if (flash != null && !flash!.isMiss && flashStrength > 0) {
      _glow(canvas, segmentPath(flash!, c, r), colors.hitGlow, flashStrength);
    }

    // Treffer
    for (final hit in hits) {
      _hit(canvas, toCanvas(hit.position, size), r, hit.latest);
    }
  }

  /// Canvas-Winkel (Radiant, im Uhrzeigersinn ab +x) für einen Board-Winkel
  /// (Grad, im Uhrzeigersinn ab oben).
  static double _canvasAngle(double boardDegrees) => (boardDegrees - 90) * math.pi / 180;

  static Path _sector(Offset c, double r1, double r2, double start, double sweep) {
    final outer = Rect.fromCircle(center: c, radius: r2);
    final inner = Rect.fromCircle(center: c, radius: r1);
    return Path()
      ..arcTo(outer, start, sweep, true)
      ..arcTo(inner, start + sweep, -sweep, false)
      ..close();
  }

  /// Umriss eines Felds, z. B. zum Hervorheben.
  static Path segmentPath(Segment s, Offset c, double r) {
    if (s.bed == Bed.innerBull) {
      return Path()..addOval(Rect.fromCircle(center: c, radius: BoardGeometry.innerBullR * r));
    }
    if (s.bed == Bed.outerBull) {
      return Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: c, radius: BoardGeometry.outerBullR * r))
        ..addOval(Rect.fromCircle(center: c, radius: BoardGeometry.innerBullR * r));
    }
    if (s.isMiss) return Path();
    final i = BoardGeometry.numbers.indexOf(s.number);
    final start = _canvasAngle(i * 18.0 - 9);
    const sweep = 18 * math.pi / 180;
    final (r1, r2) = switch (s.bed) {
      Bed.singleInner => (BoardGeometry.outerBullR, BoardGeometry.tripleInnerR),
      Bed.triple => (BoardGeometry.tripleInnerR, BoardGeometry.tripleOuterR),
      Bed.singleOuter => (BoardGeometry.tripleOuterR, BoardGeometry.doubleInnerR),
      _ => (BoardGeometry.doubleInnerR, BoardGeometry.doubleOuterR),
    };
    return _sector(c, r1 * r, r2 * r, start, sweep);
  }

  void _wires(Canvas canvas, Offset c, double r) {
    final wire = Paint()
      ..color = colors.boardWire.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, r * 0.006);
    for (final radius in const [
      BoardGeometry.innerBullR,
      BoardGeometry.outerBullR,
      BoardGeometry.tripleInnerR,
      BoardGeometry.tripleOuterR,
      BoardGeometry.doubleInnerR,
      BoardGeometry.doubleOuterR,
    ]) {
      canvas.drawCircle(c, radius * r, wire);
    }
    for (var i = 0; i < 20; i++) {
      final a = _canvasAngle(i * 18.0 - 9);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (BoardGeometry.outerBullR * r), c + dir * r, wire);
    }
  }

  void _number(Canvas canvas, Offset c, double r, int index, int number) {
    final a = _canvasAngle(index * 18.0);
    final pos = c + Offset(math.cos(a), math.sin(a)) * (r * 1.12);
    final tp = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          fontFamily: AppTypography.family,
          color: colors.boardNumbers,
          fontSize: r * 0.115,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  void _glow(Canvas canvas, Path path, Color color, double strength) {
    final s = strength.clamp(0.0, 1.0);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.55 * s)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.45 * s));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.9 * s),
    );
  }

  void _heat(Canvas canvas, Size size, double r) {
    final radius = r * 0.09;
    canvas.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: heatOpacity));
    for (final p in heat) {
      final o = toCanvas(p, size);
      final shader = RadialGradient(colors: [
        colors.heatHot.withValues(alpha: 0.55),
        colors.heatCold.withValues(alpha: 0.12),
        colors.heatCold.withValues(alpha: 0),
      ], stops: const [0, 0.55, 1]).createShader(Rect.fromCircle(center: o, radius: radius));
      canvas.drawCircle(o, radius, Paint()..shader = shader..blendMode = BlendMode.plus);
    }
    canvas.restore();
  }

  void _hit(Canvas canvas, Offset o, double r, bool latest) {
    final base = r * 0.028;
    if (latest && hitProgress < 1) {
      final t = Curves.easeOutCubic.transform(hitProgress);
      canvas.drawCircle(
        o,
        base + r * 0.16 * t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.012 * (1 - t) + 0.5
          ..color = colors.hitGlow.withValues(alpha: 1 - t),
      );
    }
    final scale = latest ? (hitProgress < 1 ? 1 + 0.5 * (1 - Curves.easeOutBack.transform(hitProgress)) : 1.0) : 0.8;
    canvas.drawCircle(o, base * 1.6 * scale, Paint()..color = Colors.black.withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(o, base * scale, Paint()..color = latest ? colors.hitGlow : colors.hitGlow.withValues(alpha: 0.7));
    canvas.drawCircle(
      o,
      base * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, r * 0.006)
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(DartboardPainter old) =>
      old.colors != colors ||
      old.hits != hits ||
      old.hitProgress != hitProgress ||
      old.highlighted != highlighted ||
      old.highlightStrength != highlightStrength ||
      old.flash != flash ||
      old.flashStrength != flashStrength ||
      old.hover != hover ||
      old.heat != heat ||
      old.heatOpacity != heatOpacity ||
      old.showNumbers != showNumbers;
}
