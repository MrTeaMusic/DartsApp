import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Das Dart-Symbol der App: ein Dart schräg im Quadrat, Spitze unten links,
/// Flight oben rechts. Es steht für „Darts“ (Anzahl, Aufnahme, Wurf), nicht
/// für die Scheibe.
///
/// Gezeichnet wird mit dem Zeichenstift statt mit einer Symbolschrift, damit
/// es in jeder Größe scharf ist und die Farbe des Looks übernimmt. Ab etwa
/// 18 px bekommt der Barrel Rillen, ab etwa 44 px mehr davon und eine Kante
/// im Flight; darunter bleiben nur die klaren Formen (Spitze, Barrel, Schaft,
/// Flight), die auch bei 16 px noch erkennbar sind.
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
  static const double _pointEnd = 0.17;
  static const double _barrelEnd = 0.53;
  static const double _shaftEnd = 0.70;
  static const double _flightStart = 0.60;

  static const double _pointHalf = 0.04;
  static const double _barrelHalfFront = 0.075;
  static const double _barrelHalfBack = 0.098;
  static const double _shaftHalf = 0.042;
  static const double _flightHalf = 0.175;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    if (s <= 0) return;
    // Länge so, dass der schräge Dart samt Flight im Quadrat bleibt.
    final length = s * 1.04;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    // Die Achse zeigt von der Spitze nach rechts oben (45°).
    canvas.rotate(-math.pi / 4);
    canvas.translate(-length / 2, 0);

    double x(double f) => f * length;
    double y(double f) => f * length;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final soft = Paint()
      ..color = color.withValues(alpha: 0.62)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final grooves = s >= 44 ? 4 : (s >= 18 ? 2 : 0);
    final fold = s >= 44;
    if (grooves > 0 || fold) {
      // Rillen und Kante werden ausgespart: Ebene, in der „löschen“ geht.
      canvas.saveLayer(Rect.fromLTWH(-length, -length, length * 3, length * 2), Paint());
    }

    // Spitze: schlanker Kegel, am Ende leicht breiter als an der Spitze.
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(x(_pointEnd), -y(_pointHalf))
        ..lineTo(x(_pointEnd), y(_pointHalf))
        ..close(),
      fill,
    );

    // Barrel: vorn schmaler, hinten breiter, leicht gerundete Enden.
    final r = length * 0.012;
    canvas.drawPath(
      Path()
        ..moveTo(x(_pointEnd), -y(_barrelHalfFront))
        ..lineTo(x(_barrelEnd), -y(_barrelHalfBack))
        ..lineTo(x(_barrelEnd), y(_barrelHalfBack))
        ..lineTo(x(_pointEnd), y(_barrelHalfFront))
        ..close(),
      fill,
    );
    canvas.drawCircle(Offset(x(_pointEnd), 0), math.max(r, y(_barrelHalfFront) * 0.35), fill);

    // Schaft: dünn, zwischen Barrel und Flight.
    canvas.drawRect(Rect.fromLTRB(x(_barrelEnd) - 0.5, -y(_shaftHalf), x(_shaftEnd), y(_shaftHalf)), fill);

    // Flight: schmal am Schaft, breit am Ende; die untere Hälfte etwas
    // heller, damit er räumlich wirkt.
    final top = Path()
      ..moveTo(x(_flightStart), 0)
      ..lineTo(x(0.80), -y(_flightHalf))
      ..lineTo(x(1.0), -y(_flightHalf * 0.82))
      ..lineTo(x(1.0), 0)
      ..close();
    final bottom = Path()
      ..moveTo(x(_flightStart), 0)
      ..lineTo(x(0.80), y(_flightHalf))
      ..lineTo(x(1.0), y(_flightHalf * 0.82))
      ..lineTo(x(1.0), 0)
      ..close();
    canvas.drawPath(top, fill);
    canvas.drawPath(bottom, soft);

    if (grooves > 0 || fold) {
      final clear = Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, length * 0.018)
        ..isAntiAlias = true;
      const first = _pointEnd + 0.07;
      const last = _barrelEnd - 0.06;
      for (var i = 0; i < grooves; i++) {
        final f = grooves == 1 ? (first + last) / 2 : first + (last - first) * i / (grooves - 1);
        final half = _barrelHalfFront + (_barrelHalfBack - _barrelHalfFront) * (f - _pointEnd) / (_barrelEnd - _pointEnd);
        canvas.drawLine(Offset(x(f), -y(half) - 1), Offset(x(f), y(half) + 1), clear);
      }
      if (fold) {
        canvas.drawLine(Offset(x(_flightStart + 0.07), 0), Offset(x(1.0), 0), clear..strokeWidth = math.max(0.8, length * 0.012));
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DartIconPainter old) => old.color != color;
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
