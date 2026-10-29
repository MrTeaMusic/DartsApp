import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Zeichenstile des Dart-Symbols. Vorläufig stehen drei Varianten zur Wahl
/// (Entwurf); nach der Entscheidung bleibt eine übrig.
enum DartIconStyle {
  /// Gefüllte Silhouette mit klaren Details (Rillen, Flight-Kante).
  a,

  /// Linienstil, passend zu den ausgeschnittenen Material-Symbolen.
  b,

  /// Gefüllt, die Flight in der Akzentfarbe.
  c,
}

/// Das Dart-Symbol der App: ein klassischer Dart schräg im Quadrat, Spitze
/// unten links, Flight oben rechts. Es steht für „Darts“ (Anzahl, Aufnahme,
/// Wurf), nicht für die Scheibe.
///
/// Gezeichnet wird mit dem Zeichenstift statt mit einer Symbolschrift, damit
/// es in jeder Größe scharf ist und die Farbe des Looks übernimmt. Es wird
/// nicht nur skaliert: ab etwa 22 px bekommt der Barrel eine Rille, die Spitze
/// eine Fuge und die Flight eine Kante, ab etwa 36 px kommen weitere Rillen dazu.
/// Darunter bleiben die klaren Formen (feine Spitze, schlanker Barrel,
/// dünner Schaft, große Flight) mit Mindeststärken in Pixeln, damit sie auch
/// bei 16 px noch zu erkennen sind.
class DartIcon extends StatelessWidget {
  const DartIcon({super.key, this.size = 24, this.color, this.style, this.accent});

  /// Stil, den alle Symbole der App ohne eigene Angabe verwenden. Nur der
  /// Entwurf der Varianten stellt das um.
  static DartIconStyle standard = DartIconStyle.a;

  /// Kantenlänge des Quadrats.
  final double size;

  /// Standard: Farbe des umgebenden Icon-Themes.
  final Color? color;

  /// Standard: [DartIcon.standard].
  final DartIconStyle? style;

  /// Farbe der Flight bei [DartIconStyle.c]; Standard: Akzent des Themes.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    final st = style ?? standard;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: DartIconPainter(c, style: st, accent: st == DartIconStyle.c ? (accent ?? Theme.of(context).colorScheme.primary) : null),
      ),
    );
  }
}

/// Zeichnet das Dart-Symbol in die Fläche (quadratisch, es zählt die
/// kürzere Seite). Siehe [DartIcon].
class DartIconPainter extends CustomPainter {
  const DartIconPainter(this.color, {this.style = DartIconStyle.a, this.accent});
  final Color color;
  final DartIconStyle style;
  final Color? accent;

  // Maße als Anteil der Gesamtlänge des Darts, von der Spitze (0) zum
  // Ende des Flights (1).
  static const double _tipEnd = 0.11;
  static const double _barrelStart = 0.125;
  static const double _barrelEnd = 0.565;
  static const double _shaftEnd = 0.68;
  static const double _flightRoot = 0.615;
  static const double _flightHalf = 0.175;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    if (s <= 0) return;
    // Der Dart liegt auf der Diagonalen: Länge und Flight-Breite bestimmen,
    // wie groß er im Quadrat werden darf.
    final nominal = _Parts(style, s, 0);
    final rot = Matrix4.rotationZ(-math.pi / 4);
    final bounds = nominal.silhouette.transform(rot.storage).getBounds();
    final pad = math.max(0.5, s * 0.03);
    final k = (s - 2 * pad) / math.max(bounds.width, bounds.height);
    final parts = _Parts(style, s, k);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(k);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    canvas.rotate(-math.pi / 4);
    parts.paint(canvas, color, accent ?? color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DartIconPainter old) => old.color != color || old.style != style || old.accent != accent;
}

/// Die Teile des Darts in Längsrichtung (x von der Spitze zur Flight, y quer).
/// [px] ist die Zahl der Pixel je Längeneinheit; damit werden Mindeststärken
/// umgerechnet (0 = ohne Mindeststärke, nur zum Ausmessen).
class _Parts {
  _Parts(this.style, this.size, this.px) {
    final small = size < 22;
    final outline = style == DartIconStyle.b;
    grooves = small ? 0 : (size >= 56 ? 3 : (size >= 36 ? 2 : 1));
    fold = !small;
    gap = !small;
    // Linienbreite des Linienstils in Längeneinheiten.
    stroke = px > 0 ? math.max(1.15, size * 0.055) / px : 0.04;
    tipHalf = _min(0.026, 0.6);
    final base = outline ? 0.06 : 0.034;
    final back = outline ? 0.064 : 0.04;
    barrelFront = _min(base, small ? 1.05 : 0.9);
    barrelBack = _min(back, small ? 1.2 : 0.95);
    shaftHalf = _min(0.02, small ? 0.5 : 0.6);
    _h = small ? 0.2 : DartIconPainter._flightHalf;
    // Der Linienstil ist ab 22 px innen hohl, darunter voll.
    hollow = outline && !small;
  }

  final DartIconStyle style;
  final double size;
  final double px;
  late final int grooves;
  late final bool fold;
  late final bool gap;
  late final double stroke;
  late final double tipHalf;
  late final double barrelFront;
  late final double barrelBack;
  late final double shaftHalf;
  late final bool hollow;

  double _min(double local, double minPx) => px > 0 ? math.max(local, minPx / px) : local;

  static const double _tipEnd = DartIconPainter._tipEnd;
  static const double _barrelStart = DartIconPainter._barrelStart;
  static const double _barrelEnd = DartIconPainter._barrelEnd;
  static const double _shaftEnd = DartIconPainter._shaftEnd;
  static const double _root = DartIconPainter._flightRoot;
  late final double _h;

  double _barrelHalf(double x) => barrelFront + (barrelBack - barrelFront) * (x - _barrelStart) / (_barrelEnd - _barrelStart);

  Path get _tip {
    final end = gap ? _tipEnd : _barrelStart + 0.01;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(end, -tipHalf)
      ..lineTo(end, tipHalf)
      ..close();
  }

  Path _barrelPiece(double a, double b, {double inset = 0}) => Path()
    ..moveTo(a, -(_barrelHalf(a) - inset))
    ..lineTo(b, -(_barrelHalf(b) - inset))
    ..lineTo(b, _barrelHalf(b) - inset)
    ..lineTo(a, _barrelHalf(a) - inset)
    ..close();

  /// Barrel in Stücken zwischen den Rillen (gefüllte Stile).
  List<Path> get _barrel {
    if (grooves == 0) return [_barrelPiece(_barrelStart, _barrelEnd)];
    final w = math.max(size >= 36 ? 0.016 : 0.013, px > 0 ? 0.85 / px : 0.0);
    const first = _barrelStart + 0.105;
    const last = _barrelEnd - 0.075;
    final out = <Path>[];
    var from = _barrelStart;
    for (var i = 0; i < grooves; i++) {
      final f = grooves == 1 ? (first + last) / 2 : first + (last - first) * i / (grooves - 1);
      out.add(_barrelPiece(from, f - w / 2));
      from = f + w / 2;
    }
    out.add(_barrelPiece(from, _barrelEnd));
    return out;
  }

  Rect get _shaft => Rect.fromLTRB(_barrelEnd - 0.01, -shaftHalf, _shaftEnd, shaftHalf);

  /// Eine Flügelhälfte der Flight; [sign] -1 oben, +1 unten. Gerade Kanten
  /// mit klarer Ecke außen: so liest sich die Flight auch klein als Flight
  /// und nicht als runder Kopf.
  Path _wing(double sign, {double offset = 0}) => Path()
    ..moveTo(_root, sign * offset)
    ..lineTo(_cornerX, sign * _h)
    ..lineTo(1.0, sign * _h * _tailRatio)
    ..lineTo(1.0, sign * offset)
    ..close();

  static const double _cornerX = 0.875;
  static const double _tailRatio = 0.58;

  Path get _flightOutline => Path()
    ..moveTo(_root, 0)
    ..lineTo(_cornerX, -_h)
    ..lineTo(1.0, -_h * _tailRatio)
    ..lineTo(1.0, _h * _tailRatio)
    ..lineTo(_cornerX, _h)
    ..close();

  /// Alles zusammen, zum Ausmessen.
  Path get silhouette => Path()
    ..addPath(_tip, Offset.zero)
    ..addPath(_barrelPiece(_barrelStart, _barrelEnd), Offset.zero)
    ..addRect(_shaft)
    ..addPath(_flightOutline, Offset.zero);

  void paint(Canvas canvas, Color color, Color accent) {
    if (style == DartIconStyle.b) {
      _paintOutline(canvas, color);
    } else {
      _paintFilled(canvas, color, style == DartIconStyle.c ? accent : color);
    }
  }

  void _paintFilled(Canvas canvas, Color color, Color flight) {
    final body = Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas.drawPath(_tip, body);
    for (final b in _barrel) {
      canvas.drawPath(b, body);
    }
    canvas.drawRect(_shaft, body);
    final off = fold ? math.max(0.008, px > 0 ? 0.35 / px : 0.0) : 0.0;
    // Obere Hälfte voll, untere etwas zurückgenommen: wirkt räumlich.
    canvas.drawPath(_wing(-1, offset: off), Paint()..color = flight..isAntiAlias = true);
    canvas.drawPath(_wing(1, offset: off), Paint()..color = flight.withValues(alpha: flight.a * 0.6)..isAntiAlias = true);
  }

  void _paintOutline(Canvas canvas, Color color) {
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(_tip, fill);
    if (hollow) {
      canvas.drawPath(_barrelPiece(_barrelStart + stroke / 2, _barrelEnd - stroke / 2, inset: stroke / 2), line);
      if (grooves > 0 && size >= 40) {
        for (var i = 0; i < grooves; i++) {
          final f = _barrelStart + 0.1 + (_barrelEnd - _barrelStart - 0.19) * i / math.max(1, grooves - 1);
          final hw = _barrelHalf(f) - stroke / 2;
          canvas.drawLine(Offset(f, -hw), Offset(f, hw), line..strokeWidth = stroke * 0.8);
          line.strokeWidth = stroke;
        }
      }
    } else {
      canvas.drawPath(_barrelPiece(_barrelStart, _barrelEnd), fill);
    }
    canvas.drawRect(_shaft, fill);
    if (!hollow) canvas.drawPath(_flightOutline, Paint()..color = color.withValues(alpha: color.a * 0.4)..isAntiAlias = true);
    canvas.drawPath(_flightOutline, line);
    if (fold) canvas.drawLine(const Offset(_root, 0), const Offset(0.985, 0), line);
  }
}

/// Symbole der App, die nicht aus der Material-Schrift kommen. Sie stehen
/// als [IconData] da, damit sie in Kacheln, Kennzahlen und Plaketten wie
/// jedes andere Symbol übergeben werden können; angezeigt werden sie mit
/// [AppIcon].
abstract final class AppIcons {
  /// Darts (Anzahl, Aufnahme, Wurf), siehe [DartIcon]. Nur über [AppIcon]
  /// anzeigen, nicht mit `Icon`.
  static const IconData dart = IconData(0xE9D0, fontFamily: 'DartLabIcons');
}

/// Wie `Icon`, zeichnet aber [AppIcons.dart] selbst.
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color});
  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (icon == AppIcons.dart) {
      final iconTheme = IconTheme.of(context);
      return DartIcon(size: size ?? iconTheme.size ?? 24, color: color);
    }
    return Icon(icon, size: size, color: color);
  }
}
