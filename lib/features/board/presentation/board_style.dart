import 'package:flutter/material.dart';

import '../../../core/design/dart_colors.dart';

/// Wählbare Optik der Dartscheibe (Optionen → Darstellung → Scheibe).
///
/// Die Geometrie der Felder ist bei allen gleich, nur Rand, Zahlenring,
/// Farben und Oberfläche unterscheiden sich.
enum BoardStyle {
  /// Turnierscheibe: breiter schwarzer Fangring, silberne Zahlen, Sisal.
  tournament,

  /// Schwarzer Fangring mit großen türkisen Zahlen und türkisem Außenring.
  turquoise,

  /// Flache, grafische Scheibe in den Farben des Looks.
  classic;

  static BoardStyle byName(String? name) => values.where((s) => s.name == name).firstOrNull ?? tournament;

  BoardSpec get spec => switch (this) {
        tournament => BoardSpec.tournament,
        turquoise => BoardSpec.turquoise,
        classic => BoardSpec.classic,
      };
}

/// Maße und Farben einer [BoardStyle]. Radien relativ zur Außenkante des
/// Double-Rings (= 1.0).
@immutable
class BoardSpec {
  const BoardSpec({
    required this.outerExtent,
    required this.frameExtent,
    required this.numberRadius,
    required this.numberSize,
    this.numberWeight = FontWeight.w600,
    this.numberFamily,
    this.numberColor,
    this.rotateNumbers = false,
    this.black,
    this.cream,
    this.red,
    this.green,
    this.wire,
    this.surround,
    this.edge,
    this.edgeMetal = false,
    this.realistic = true,
    this.spiderOverhang = 1.045,
  });

  /// Außenkante des Fangrings.
  final double outerExtent;

  /// Platz, den die Scheibe samt Schatten in ihrer Fläche belegt.
  final double frameExtent;

  final double numberRadius;

  /// Schriftgröße der Zahlen relativ zum Radius des Double-Rings.
  final double numberSize;
  final FontWeight numberWeight;

  /// null = Schrift der App.
  final String? numberFamily;

  /// null = Farbe des Looks.
  final Color? numberColor;

  /// Zahlen entlang des Rings drehen (unten bleiben sie lesbar).
  final bool rotateNumbers;

  /// Feldfarben; null = Farbe des Looks.
  final Color? black;
  final Color? cream;
  final Color? red;
  final Color? green;
  final Color? wire;
  final Color? surround;

  /// Farbe des schmalen Außenrings; null = kein Ring.
  final Color? edge;

  /// Außenring als gebürstetes Metall statt einfarbig.
  final bool edgeMetal;

  /// Schatten, Licht und Sisal-Struktur.
  final bool realistic;

  /// Wie weit die Drähte des Spiders über den Double-Ring hinausragen.
  final double spiderOverhang;

  Color blackOf(DartColors c) => black ?? c.boardBlack;
  Color creamOf(DartColors c) => cream ?? c.boardCream;
  Color redOf(DartColors c) => red ?? c.boardRed;
  Color greenOf(DartColors c) => green ?? c.boardGreen;
  Color wireOf(DartColors c) => wire ?? c.boardWire;
  Color surroundOf(DartColors c) => surround ?? c.boardSurround;
  Color numbersOf(DartColors c) => numberColor ?? c.boardNumbers;

  static const tournament = BoardSpec(
    outerExtent: 1.24,
    frameExtent: 1.32,
    numberRadius: 1.145,
    numberSize: 0.115,
    numberColor: Color(0xFFCFD2D6),
    black: Color(0xFF151515),
    cream: Color(0xFFF0E2C0),
    red: Color(0xFFDA1F26),
    green: Color(0xFF1E8A3C),
    wire: Color(0xFFD5D9DD),
    surround: Color(0xFF0A0A0A),
    edge: Color(0xFFB8BCC0),
    edgeMetal: true,
  );

  static const turquoise = BoardSpec(
    outerExtent: 1.34,
    frameExtent: 1.41,
    numberRadius: 1.215,
    numberSize: 0.19,
    numberWeight: FontWeight.w600,
    numberFamily: 'Barlow Condensed',
    numberColor: Color(0xFF6CC5D3),
    rotateNumbers: true,
    black: Color(0xFF131313),
    cream: Color(0xFFE8DCC2),
    red: Color(0xFFE2261C),
    green: Color(0xFF07A35A),
    wire: Color(0xFFC9CDD1),
    surround: Color(0xFF111111),
    edge: Color(0xFF6CC5D3),
    spiderOverhang: 1.03,
  );

  static const classic = BoardSpec(
    outerExtent: 1.24,
    frameExtent: 1.24,
    numberRadius: 1.12,
    numberSize: 0.115,
    numberWeight: FontWeight.w700,
    realistic: false,
    spiderOverhang: 1.0,
  );
}
