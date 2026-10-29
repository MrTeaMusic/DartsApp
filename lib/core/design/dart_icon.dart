import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  const DartIcon({super.key, this.size = 24, this.color});

  /// Kantenlänge des Quadrats.
  final double size;

  /// Standard: Farbe des umgebenden Icon-Themes.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: DartIconPainter(c)),
    );
  }
}

/// Zeichnet das Dart-Symbol in die Fläche (quadratisch, es zählt die
/// kürzere Seite). Siehe [DartIcon].
class DartIconPainter extends CustomPainter {
  const DartIconPainter(this.color);
  final Color color;

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
    final nominal = _Parts(s, 0);
    final rot = Matrix4.rotationZ(-math.pi / 4);
    final bounds = nominal.silhouette.transform(rot.storage).getBounds();
    final pad = math.max(0.5, s * 0.03);
    final k = (s - 2 * pad) / math.max(bounds.width, bounds.height);
    final parts = _Parts(s, k);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(k);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    canvas.rotate(-math.pi / 4);
    parts.paint(canvas, color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DartIconPainter old) => old.color != color;
}

/// Die Teile des Darts in Längsrichtung (x von der Spitze zur Flight, y quer).
/// [px] ist die Zahl der Pixel je Längeneinheit; damit werden Mindeststärken
/// umgerechnet (0 = ohne Mindeststärke, nur zum Ausmessen).
class _Parts {
  _Parts(this.size, this.px) {
    final small = size < 22;
    grooves = small ? 0 : (size >= 56 ? 3 : (size >= 36 ? 2 : 1));
    fold = !small;
    tipHalf = _min(0.026, 0.6);
    barrelFront = _min(0.034, small ? 1.05 : 0.9);
    barrelBack = _min(0.04, small ? 1.2 : 0.95);
    shaftHalf = _min(0.02, small ? 0.5 : 0.6);
    _h = small ? 0.2 : DartIconPainter._flightHalf;
  }

  final double size;
  final double px;
  late final int grooves;
  late final bool fold;
  late final double tipHalf;
  late final double barrelFront;
  late final double barrelBack;
  late final double shaftHalf;
  late final double _h;

  double _min(double local, double minPx) => px > 0 ? math.max(local, minPx / px) : local;

  static const double _tipEnd = DartIconPainter._tipEnd;
  static const double _barrelStart = DartIconPainter._barrelStart;
  static const double _barrelEnd = DartIconPainter._barrelEnd;
  static const double _shaftEnd = DartIconPainter._shaftEnd;
  static const double _root = DartIconPainter._flightRoot;
  static const double _cornerX = 0.875;
  static const double _tailRatio = 0.58;

  double _barrelHalf(double x) => barrelFront + (barrelBack - barrelFront) * (x - _barrelStart) / (_barrelEnd - _barrelStart);

  /// Die Spitze hat ab 22 px eine Fuge zum Barrel.
  Path get _tip {
    final end = fold ? _tipEnd : _barrelStart + 0.01;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(end, -tipHalf)
      ..lineTo(end, tipHalf)
      ..close();
  }

  Path _barrelPiece(double a, double b) => Path()
    ..moveTo(a, -_barrelHalf(a))
    ..lineTo(b, -_barrelHalf(b))
    ..lineTo(b, _barrelHalf(b))
    ..lineTo(a, _barrelHalf(a))
    ..close();

  /// Barrel in Stücken zwischen den Rillen.
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

  void paint(Canvas canvas, Color color) {
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
    canvas.drawPath(_wing(-1, offset: off), body);
    canvas.drawPath(_wing(1, offset: off), Paint()..color = color.withValues(alpha: color.a * 0.6)..isAntiAlias = true);
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
