import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/design/app_theme.dart';
import '../../../core/design/dart_colors.dart';
import '../domain/board_geometry.dart';
import '../domain/segment.dart';
import 'board_style.dart';

/// Ein Treffer, der auf dem Board markiert wird.
@immutable
class HitMarker {
  const HitMarker(this.position, {this.latest = false});
  final BoardPoint position;
  final bool latest;
}

/// Ein Punkt im Streubild (Statistik): Treffer farbig, Fehlwurf grau. Anders
/// als [HitMarker] ohne Animation und kleiner, damit viele Punkte passen.
@immutable
class ScatterMarker {
  const ScatterMarker(this.position, {required this.hit});
  final BoardPoint position;
  final bool hit;
}

/// Ruhende Zusatz-Zeichnung in Board-Koordinaten über der Scheibe, z. B. die
/// Streuungs-Ellipsen der Statistik. Sie liegt in der Ebene der Treffer und
/// wird nur neu gezeichnet, wenn sich die Dekoration ändert (`==`); im
/// Ausschnitt (Doppel-Zoom) wird sie mit der Scheibe gedreht und vergrößert.
@immutable
abstract class BoardDecoration {
  const BoardDecoration();

  /// [toCanvas] rechnet Board-Koordinaten in Pixel um, [ringRadius] ist der
  /// Radius des Double-Rings in Pixeln, [markerScale] die Größe von Markern
  /// (im Ausschnitt kleiner).
  void paint(Canvas canvas, Offset Function(BoardPoint p) toCanvas, double ringRadius, double markerScale);
}

/// Welche Teile [DartboardPainter] zeichnet.
enum BoardLayer {
  /// Alles.
  all,

  /// Nur die Scheibe selbst (Felder, Struktur, Drähte, Zahlen). Ändert sich
  /// nur mit Größe, Optik und Farben und kann deshalb zwischengespeichert
  /// werden.
  base,

  /// Nur, was sich bewegt: Treffer, Hervorhebungen, Heatmap, Streubild.
  overlay,

  /// Nur die Heatmap (eigene Ebene bzw. zwischengespeichertes Bild).
  heat,
}

/// Werte der laufenden Animationen. [DartboardPainter] liest sie erst beim
/// Zeichnen, damit eine Animation nur die Ebene neu zeichnet, ohne Neuaufbau
/// und Layout.
abstract interface class BoardAnimation implements Listenable {
  /// 0 → 1: Fortschritt der Trefferanimation des neuesten Darts.
  double get hitProgress;

  /// Stärke der Hervorhebung der Zielfelder.
  double get highlightStrength;

  /// Stärke des Aufleuchtens des zuletzt getroffenen Felds.
  double get flashStrength;
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
    this.scatter = const [],
    this.decoration,
    this.showNumbers = true,
    this.style = BoardStyle.tournament,
    this.markerScale = 1,
    this.viewRotation = 0,
    this.layer = BoardLayer.all,
    this.animation,
  }) : super(repaint: animation);

  /// Liefert [hitProgress], [highlightStrength] und [flashStrength] beim
  /// Zeichnen; ohne gelten die festen Werte.
  final BoardAnimation? animation;

  double get _hitProgress => animation?.hitProgress ?? hitProgress;
  double get _highlightStrength => animation?.highlightStrength ?? highlightStrength;
  double get _flashStrength => animation?.flashStrength ?? flashStrength;

  final BoardLayer layer;

  final DartColors colors;

  /// Optik der Scheibe (Rand, Zahlen, Oberfläche).
  final BoardStyle style;
  BoardSpec get _spec => style.spec;
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

  /// Streubild-Punkte, Fehlwürfe unter den Treffern.
  final List<ScatterMarker> scatter;

  /// Zusatz-Zeichnung über dem Streubild (siehe [BoardDecoration]).
  final BoardDecoration? decoration;
  final bool showNumbers;

  /// Größe der Treffer-Marker; im Zoom kleiner, damit sie nicht mitwachsen.
  final double markerScale;

  /// Um wie viel (Radiant, im Uhrzeigersinn) die Scheibe auf dem Bildschirm
  /// gedreht erscheint; die Zahlen bleiben trotzdem lesbar.
  final double viewRotation;

  /// Radius des Double-Rings in Pixeln für eine gegebene Größe.
  static double ringRadius(Size size, [BoardStyle style = BoardStyle.tournament]) =>
      size.shortestSide / 2 / style.spec.frameExtent;

  /// Pixelposition → Board-Koordinate.
  static BoardPoint toBoard(Offset local, Size size, [BoardStyle style = BoardStyle.tournament]) {
    final r = ringRadius(size, style);
    final c = size.center(Offset.zero);
    return BoardPoint((local.dx - c.dx) / r, -(local.dy - c.dy) / r);
  }

  /// Board-Koordinate → Pixelposition.
  static Offset toCanvas(BoardPoint p, Size size, [BoardStyle style = BoardStyle.tournament]) {
    final r = ringRadius(size, style);
    final c = size.center(Offset.zero);
    return Offset(c.dx + p.x * r, c.dy - p.y * r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = ringRadius(size, style);
    if (layer == BoardLayer.heat) {
      if (heatOpacity > 0 && heat.isNotEmpty) _heat(canvas, size, r);
      return;
    }
    if (layer != BoardLayer.overlay) _paintBase(canvas, c, r);
    if (layer != BoardLayer.base) _paintOverlay(canvas, size, c, r);
  }

  void _paintBase(Canvas canvas, Offset c, double r) {
    final spec = _spec;
    _stage(canvas, c, r);

    // Felder
    for (var i = 0; i < 20; i++) {
      final even = i.isEven;
      final single = even ? spec.blackOf(colors) : spec.creamOf(colors);
      final ring = even ? spec.redOf(colors) : spec.greenOf(colors);
      final start = _canvasAngle(i * 18.0 - 9);
      const sweep = 18 * math.pi / 180;
      void fill(double r1, double r2, Color color) =>
          canvas.drawPath(_sector(c, r1 * r, r2 * r, start, sweep), Paint()..color = color);
      fill(BoardGeometry.outerBullR, BoardGeometry.tripleInnerR, single);
      fill(BoardGeometry.tripleInnerR, BoardGeometry.tripleOuterR, ring);
      fill(BoardGeometry.tripleOuterR, BoardGeometry.doubleInnerR, single);
      fill(BoardGeometry.doubleInnerR, BoardGeometry.doubleOuterR, ring);
    }
    canvas.drawCircle(c, BoardGeometry.outerBullR * r, Paint()..color = spec.greenOf(colors));
    canvas.drawCircle(c, BoardGeometry.innerBullR * r, Paint()..color = spec.redOf(colors));

    if (spec.realistic) _sisal(canvas, c, r);
    _wires(canvas, c, r);
    if (spec.realistic) _light(canvas, c, r);
    if (showNumbers) {
      for (var i = 0; i < 20; i++) {
        _number(canvas, c, r, i, BoardGeometry.numbers[i]);
      }
    }
  }

  void _paintOverlay(Canvas canvas, Size size, Offset c, double r) {
    // Heatmap
    if (heatOpacity > 0 && heat.isNotEmpty) _heat(canvas, size, r);

    if (scatter.isNotEmpty) _scatter(canvas, size, r);

    decoration?.paint(canvas, (p) => toCanvas(p, size, style), r, markerScale);

    // Hover
    if (hover != null && !hover!.isMiss) {
      canvas.drawPath(segmentPath(hover!, c, r), Paint()..color = Colors.white.withValues(alpha: 0.18));
    }

    // Hervorhebungen
    final highlightStrength = _highlightStrength;
    if (highlighted.isNotEmpty && highlightStrength > 0) {
      for (final s in highlighted) {
        _glow(canvas, segmentPath(s, c, r), colors.highlight, highlightStrength);
      }
    }
    final flashStrength = _flashStrength;
    if (flash != null && !flash!.isMiss && flashStrength > 0) {
      _glow(canvas, segmentPath(flash!, c, r), colors.hitGlow, flashStrength);
    }

    // Treffer
    final hitProgress = _hitProgress;
    for (final hit in hits) {
      _hit(canvas, toCanvas(hit.position, size, style), r, hit.latest, hitProgress);
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

  /// Schatten, Lichtkranz, Fangring und Außenring: hebt das Board von
  /// jedem Hintergrund ab, ob hell oder dunkel.
  void _stage(Canvas canvas, Offset c, double r) {
    final spec = _spec;
    final outer = r * spec.outerExtent;
    final surround = spec.surroundOf(colors);
    if (!spec.realistic) {
      canvas.drawCircle(c, outer, Paint()..color = surround);
      return;
    }
    canvas.drawCircle(
      c + Offset(0, r * 0.025),
      outer,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.035),
    );
    canvas.drawCircle(
      c,
      outer + r * 0.01,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.03),
    );
    canvas.drawCircle(
      c,
      outer,
      Paint()
        ..shader = RadialGradient(
          colors: [Color.lerp(surround, Colors.white, 0.04)!, surround],
          stops: const [0.8, 1],
        ).createShader(Rect.fromCircle(center: c, radius: outer)),
    );
    final edge = spec.edge;
    if (edge == null) return;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * 0.01);
    if (spec.edgeMetal) {
      ring.shader = const SweepGradient(
        colors: [Color(0xFF5E6266), Color(0xFFD9DCDF), Color(0xFF6E7276), Color(0xFFB8BCC0), Color(0xFF5E6266)],
        transform: GradientRotation(-math.pi / 3),
      ).createShader(Rect.fromCircle(center: c, radius: outer));
    } else {
      ring.color = edge;
    }
    canvas.drawCircle(c, outer - r * 0.02, ring);
  }

  /// Feine Sisal-Struktur. Aufgezeichnet wird je Größenstufe (Viertel-
  /// Oktaven) einmal und passend skaliert, damit beim Ändern der Größe nicht
  /// ständig neue, große Aufzeichnungen entstehen.
  void _sisal(Canvas canvas, Offset c, double r) {
    final step = (math.log(math.max(r, 16)) / math.ln2 * 4).round();
    final recorded = math.pow(2, step / 4).toDouble();
    var picture = _sisalCache.remove(step);
    if (picture == null) {
      picture = _recordSisal(recorded, 1.45);
      if (_sisalCache.length >= _sisalCacheSize) _sisalCache.remove(_sisalCache.keys.first)?.dispose();
    }
    _sisalCache[step] = picture;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * _spec.outerExtent)));
    canvas.translate(c.dx, c.dy);
    canvas.scale(r / recorded);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  /// Zuletzt benutzte Aufzeichnungen, älteste zuerst.
  static final Map<int, ui.Picture> _sisalCache = {};
  static const int _sisalCacheSize = 6;

  static ui.Picture _recordSisal(double r, double extent) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final random = math.Random(180);
    // Kurze, radial laufende Fasern wie bei gepresstem Sisal.
    final dark = Paint()
      ..color = Colors.black.withValues(alpha: 0.07)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.4, r * 0.0022);
    final light = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.4, r * 0.0022);
    final count = (r * r * 0.4 * extent * extent / 1.6).clamp(1200, 40000).toInt();
    for (var i = 0; i < count; i++) {
      final d = math.sqrt(random.nextDouble()) * r * extent;
      final a = random.nextDouble() * 2 * math.pi;
      final p = Offset(math.cos(a) * d, math.sin(a) * d);
      final fibre = Offset(math.cos(a), math.sin(a)) * (r * (0.004 + random.nextDouble() * 0.008));
      canvas.drawLine(p - fibre, p + fibre, i.isEven ? dark : light);
    }
    return recorder.endRecording();
  }

  /// Weiches Licht von oben links, Schatten unten rechts.
  void _light(Canvas canvas, Offset c, double r) {
    final rect = Rect.fromCircle(center: c, radius: r * _spec.outerExtent);
    canvas.drawCircle(
      c,
      r * _spec.outerExtent,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.55),
          radius: 1.15,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.22),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  void _wires(Canvas canvas, Offset c, double r) {
    final spec = _spec;
    if (!spec.realistic) {
      _flatWires(canvas, c, r);
      return;
    }
    final width = math.max(0.8, r * 0.0055);
    final shade = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 1.6;
    final wire = Paint()
      ..color = spec.wireOf(colors)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final shadow = Offset(width * 0.6, width * 0.8);
    const radii = [
      BoardGeometry.innerBullR,
      BoardGeometry.outerBullR,
      BoardGeometry.tripleInnerR,
      BoardGeometry.tripleOuterR,
      BoardGeometry.doubleInnerR,
      BoardGeometry.doubleOuterR,
    ];
    for (final pass in [(shade, shadow), (wire, Offset.zero)]) {
      for (final radius in radii) {
        canvas.drawCircle(c + pass.$2, radius * r, pass.$1);
      }
      for (var i = 0; i < 20; i++) {
        final a = _canvasAngle(i * 18.0 - 9);
        final dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + pass.$2 + dir * (BoardGeometry.outerBullR * r), c + pass.$2 + dir * (r * spec.spiderOverhang), pass.$1);
      }
    }
  }

  void _flatWires(Canvas canvas, Offset c, double r) {
    final wire = Paint()
      ..color = _spec.wireOf(colors).withValues(alpha: 0.55)
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
    final spec = _spec;
    final degrees = index * 18.0;
    final a = _canvasAngle(degrees);
    final pos = c + Offset(math.cos(a), math.sin(a)) * (r * spec.numberRadius);
    final tp = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          fontFamily: spec.numberFamily ?? AppTypography.family,
          color: spec.numbersOf(colors),
          fontSize: r * spec.numberSize,
          fontWeight: spec.numberWeight,
          height: 1,
          shadows: spec.realistic
              ? const [Shadow(color: Color(0x99000000), offset: Offset(0.6, 1), blurRadius: 1.5)]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (!spec.rotateNumbers && viewRotation == 0) {
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      return;
    }
    // Oben stehen die Zahlen mit dem Kopf nach außen, unten mit dem Kopf zur
    // Mitte, damit keine auf dem Kopf steht. Maßgeblich ist die Lage auf dem
    // Bildschirm.
    final screen = (degrees + viewRotation * 180 / math.pi) % 360;
    final upper = screen <= 90 || screen >= 270;
    final turn = spec.rotateNumbers ? (upper ? screen : screen - 180) * math.pi / 180 - viewRotation : -viewRotation;
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(turn);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
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

  void _scatter(Canvas canvas, Size size, double r) {
    final radius = r * 0.017 * markerScale;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, radius * 0.3)
      ..color = Colors.black.withValues(alpha: 0.55);
    final miss = Paint()..color = const Color(0xFFB4B9C0).withValues(alpha: 0.9);
    final hit = Paint()..color = colors.success;
    // Erst die Fehlwürfe, dann die Treffer obenauf.
    for (final pass in [false, true]) {
      for (final p in scatter) {
        if (p.hit != pass) continue;
        final o = toCanvas(p.position, size, style);
        canvas.drawCircle(o, radius, pass ? hit : miss);
        canvas.drawCircle(o, radius, outline);
      }
    }
  }

  void _hit(Canvas canvas, Offset o, double r, bool latest, double hitProgress) {
    final base = r * 0.028 * markerScale;
    if (latest && hitProgress < 1) {
      final t = Curves.easeOutCubic.transform(hitProgress);
      canvas.drawCircle(
        o,
        base + r * 0.16 * markerScale * t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.012 * markerScale * (1 - t) + 0.5
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
        ..strokeWidth = math.max(1, r * 0.006 * markerScale)
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
      old.scatter != scatter ||
      old.decoration != decoration ||
      old.showNumbers != showNumbers ||
      old.markerScale != markerScale ||
      old.viewRotation != viewRotation ||
      old.style != style ||
      old.layer != layer ||
      old.animation != animation;
}
