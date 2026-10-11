import 'package:flutter/material.dart';

import 'tokens.dart';

/// App-spezifische Farben, die Material nicht abdeckt. Abrufbar über
/// `context.dartColors`.
@immutable
class DartColors extends ThemeExtension<DartColors> {
  const DartColors({
    required this.boardBlack,
    required this.boardCream,
    required this.boardRed,
    required this.boardGreen,
    required this.boardWire,
    required this.boardSurround,
    required this.boardNumbers,
    required this.hitGlow,
    required this.highlight,
    required this.success,
    required this.warning,
    required this.danger,
    required this.textMuted,
    required this.surfaceHigh,
    required this.heatCold,
    required this.heatHot,
  });

  final Color boardBlack;
  final Color boardCream;
  final Color boardRed;
  final Color boardGreen;
  final Color boardWire;
  final Color boardSurround;
  final Color boardNumbers;
  final Color hitGlow;
  final Color highlight;
  final Color success;
  final Color warning;
  final Color danger;
  final Color textMuted;
  final Color surfaceHigh;
  final Color heatCold;
  final Color heatHot;

  static const DartColors dark = DartColors(
    boardBlack: AppPalette.boardBlack,
    boardCream: AppPalette.boardCream,
    boardRed: AppPalette.boardRed,
    boardGreen: AppPalette.boardGreen,
    boardWire: AppPalette.boardWire,
    boardSurround: AppPalette.boardSurround,
    boardNumbers: Color(0xFFF4F5F2),
    hitGlow: AppPalette.greenBright,
    highlight: Color(0xFFFFD45C),
    success: AppPalette.greenBright,
    warning: AppPalette.amber,
    danger: AppPalette.red,
    textMuted: AppPalette.darkTextMuted,
    surfaceHigh: AppPalette.darkSurfaceHigh,
    heatCold: Color(0xFF3D8BEF),
    heatHot: Color(0xFFFF4D3D),
  );

  static const DartColors light = DartColors(
    boardBlack: AppPalette.boardBlack,
    boardCream: AppPalette.boardCream,
    boardRed: AppPalette.boardRed,
    boardGreen: AppPalette.boardGreen,
    boardWire: AppPalette.boardWire,
    boardSurround: Color(0xFF1C1C1C),
    boardNumbers: Color(0xFFF4F5F2),
    hitGlow: AppPalette.green,
    highlight: Color(0xFFFFC21F),
    success: AppPalette.green,
    warning: Color(0xFFB27600),
    danger: Color(0xFFC4352C),
    textMuted: AppPalette.lightTextMuted,
    surfaceHigh: AppPalette.lightSurfaceHigh,
    heatCold: Color(0xFF2A78D6),
    heatHot: Color(0xFFE5392B),
  );

  @override
  DartColors copyWith({Color? hitGlow, Color? highlight}) => DartColors(
        boardBlack: boardBlack,
        boardCream: boardCream,
        boardRed: boardRed,
        boardGreen: boardGreen,
        boardWire: boardWire,
        boardSurround: boardSurround,
        boardNumbers: boardNumbers,
        hitGlow: hitGlow ?? this.hitGlow,
        highlight: highlight ?? this.highlight,
        success: success,
        warning: warning,
        danger: danger,
        textMuted: textMuted,
        surfaceHigh: surfaceHigh,
        heatCold: heatCold,
        heatHot: heatHot,
      );

  @override
  DartColors lerp(DartColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return DartColors(
      boardBlack: l(boardBlack, other.boardBlack),
      boardCream: l(boardCream, other.boardCream),
      boardRed: l(boardRed, other.boardRed),
      boardGreen: l(boardGreen, other.boardGreen),
      boardWire: l(boardWire, other.boardWire),
      boardSurround: l(boardSurround, other.boardSurround),
      boardNumbers: l(boardNumbers, other.boardNumbers),
      hitGlow: l(hitGlow, other.hitGlow),
      highlight: l(highlight, other.highlight),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      textMuted: l(textMuted, other.textMuted),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      heatCold: l(heatCold, other.heatCold),
      heatHot: l(heatHot, other.heatHot),
    );
  }
}

extension DartColorsContext on BuildContext {
  DartColors get dartColors =>
      Theme.of(this).extension<DartColors>() ?? DartColors.dark;
}
