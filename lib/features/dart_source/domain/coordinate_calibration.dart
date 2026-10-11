import '../../board/domain/board_geometry.dart';

/// Umrechnung der Autodarts-Koordinaten in DartLabs [BoardPoint].
///
/// Erwartet wird: Radius 1.0 = Außenkante Double, y zeigt zur 20. Falls ein
/// echtes Board anders liefert (gespiegelt, gedreht, anderer Maßstab), lässt
/// sich das hier korrigieren, ohne Code zu ändern. Die Werte schlägt die
/// Mitschnitt-Prüfung im Debug-Bildschirm vor.
class CoordinateCalibration {
  const CoordinateCalibration({this.swapAxes = false, this.mirrorX = false, this.mirrorY = false, this.scale = 1.0});

  static const CoordinateCalibration identity = CoordinateCalibration();

  /// x und y tauschen (vor dem Spiegeln).
  final bool swapAxes;
  final bool mirrorX;
  final bool mirrorY;

  /// Faktor, mit dem die Rohwerte multipliziert werden.
  final double scale;

  bool get isIdentity => !swapAxes && !mirrorX && !mirrorY && scale == 1.0;

  BoardPoint apply(BoardPoint p) {
    var x = swapAxes ? p.y : p.x;
    var y = swapAxes ? p.x : p.y;
    if (mirrorX) x = -x;
    if (mirrorY) y = -y;
    return BoardPoint(x * scale, y * scale);
  }

  /// Alle acht Drehungen/Spiegelungen, Maßstab 1.
  static List<CoordinateCalibration> get orientations => [
        for (final swap in [false, true])
          for (final mx in [false, true])
            for (final my in [false, true]) CoordinateCalibration(swapAxes: swap, mirrorX: mx, mirrorY: my),
      ];

  CoordinateCalibration withScale(double s) =>
      CoordinateCalibration(swapAxes: swapAxes, mirrorX: mirrorX, mirrorY: mirrorY, scale: s);

  /// Kompakte Form für die Einstellungen, z. B. "swap,mx;1.000".
  String encode() {
    final flags = [if (swapAxes) 'swap', if (mirrorX) 'mx', if (mirrorY) 'my'].join(',');
    return '$flags;${scale.toStringAsFixed(4)}';
  }

  static CoordinateCalibration decode(String? text) {
    if (text == null || !text.contains(';')) return identity;
    final [flags, scaleText, ...] = text.split(';');
    final f = flags.split(',');
    final s = double.tryParse(scaleText) ?? 1.0;
    return CoordinateCalibration(
      swapAxes: f.contains('swap'),
      mirrorX: f.contains('mx'),
      mirrorY: f.contains('my'),
      scale: s > 0 ? s : 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CoordinateCalibration &&
      other.swapAxes == swapAxes &&
      other.mirrorX == mirrorX &&
      other.mirrorY == mirrorY &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(swapAxes, mirrorX, mirrorY, scale);

  @override
  String toString() => 'CoordinateCalibration(${encode()})';
}
