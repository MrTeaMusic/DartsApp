import 'package:flutter/material.dart';

import 'dart_colors.dart';
import 'dart_look.dart';
import 'tokens.dart';

/// Grundfarben eines Looks in einer Helligkeit. Daraus entstehen
/// `ColorScheme` und `DartColors` (siehe `AppTheme.build`).
@immutable
class LookPalette {
  const LookPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.outline,
    required this.text,
    required this.muted,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.colors,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color outline;
  final Color text;
  final Color muted;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final DartColors colors;
}

abstract final class LookPalettes {
  static LookPalette of(DartLookId id, Brightness b) => switch (id) {
        DartLookId.tv => tv,
        DartLookId.clean => b == Brightness.light ? cleanLight : cleanDark,
        DartLookId.lab => lab,
      };

  /// TV: Studio-Schwarz mit Signalrot, weiße Zahlen.
  static const LookPalette tv = LookPalette(
    brightness: Brightness.dark,
    background: Color(0xFF07090F),
    surface: Color(0xFF11151F),
    surfaceHigh: Color(0xFF1C2232),
    outline: Color(0xFF242B3C),
    text: Color(0xFFF5F6FA),
    muted: Color(0xFF8F98AD),
    primary: Color(0xFFE3122C),
    onPrimary: Colors.white,
    secondary: Color(0xFFF5F6FA),
    onSecondary: Color(0xFF07090F),
    colors: DartColors.dark,
  );

  /// Clean hell: Systemgrau, weiße Karten, ruhiges Blau.
  static const LookPalette cleanLight = LookPalette(
    brightness: Brightness.light,
    background: Color(0xFFF2F2F7),
    surface: Colors.white,
    surfaceHigh: Color(0xFFEDEDF2),
    outline: Color(0xFFE2E2E8),
    text: Color(0xFF1C1C1E),
    muted: Color(0xFF6E6E73),
    primary: Color(0xFF0A7AFF),
    onPrimary: Colors.white,
    secondary: Color(0xFF1C1C1E),
    onSecondary: Colors.white,
    colors: DartColors.light,
  );

  /// Clean dunkel: tiefes Schwarz, dunkelgraue Karten.
  static const LookPalette cleanDark = LookPalette(
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceHigh: Color(0xFF2C2C2E),
    outline: Color(0xFF2C2C2E),
    text: Color(0xFFF5F5F7),
    muted: Color(0xFF98989F),
    primary: Color(0xFF0A84FF),
    onPrimary: Colors.white,
    secondary: Color(0xFFF5F5F7),
    onSecondary: Colors.black,
    colors: DartColors(
      boardBlack: AppPalette.boardBlack,
      boardCream: AppPalette.boardCream,
      boardRed: AppPalette.boardRed,
      boardGreen: AppPalette.boardGreen,
      boardWire: AppPalette.boardWire,
      boardSurround: Color(0xFF0A0A0A),
      boardNumbers: Color(0xFFF4F5F2),
      hitGlow: Color(0xFF30D158),
      highlight: Color(0xFFFFD60A),
      success: Color(0xFF30D158),
      warning: Color(0xFFFF9F0A),
      danger: Color(0xFFFF453A),
      textMuted: Color(0xFF98989F),
      surfaceHigh: Color(0xFF2C2C2E),
      heatCold: Color(0xFF3D8BEF),
      heatHot: Color(0xFFFF4D3D),
      tripleHit: Color(0xFFBF5AF2),
      doubleHit: Color(0xFF30D158),
      panel: Color(0xFF1C1C1E),
      panelHeader: Color(0x00000000),
      onPanelHeader: Color(0xFF98989F),
      record: Color(0xFFFFD60A),
      chartPrimary: Color(0xFF0A84FF),
      chartSecondary: Color(0xFFFF9F0A),
      chartGrid: Color(0xFF2C2C2E),
      heroStart: Color(0xFF0B2547),
      heroEnd: Color(0xFF1C1C1E),
    ),
  );

  /// Lab: Graphit, feine Linien, elektrisches Blau.
  static const LookPalette lab = LookPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0C0F14),
    surface: Color(0xFF131820),
    surfaceHigh: Color(0xFF1B222C),
    outline: Color(0xFF252D39),
    text: Color(0xFFE6EAF0),
    muted: Color(0xFF8792A5),
    primary: Color(0xFF4C9EFF),
    onPrimary: Color(0xFF04101F),
    secondary: Color(0xFFE6EAF0),
    onSecondary: Color(0xFF0C0F14),
    colors: DartColors(
      boardBlack: AppPalette.boardBlack,
      boardCream: AppPalette.boardCream,
      boardRed: AppPalette.boardRed,
      boardGreen: AppPalette.boardGreen,
      boardWire: AppPalette.boardWire,
      boardSurround: Color(0xFF080A0E),
      boardNumbers: Color(0xFFE6EAF0),
      hitGlow: Color(0xFF3DDC97),
      highlight: Color(0xFFFFCC33),
      success: Color(0xFF3DDC97),
      warning: Color(0xFFFBBF24),
      danger: Color(0xFFF87171),
      textMuted: Color(0xFF8792A5),
      surfaceHigh: Color(0xFF1B222C),
      heatCold: Color(0xFF3D8BEF),
      heatHot: Color(0xFFFF4D3D),
      tripleHit: Color(0xFFA78BFA),
      doubleHit: Color(0xFF3DDC97),
      panel: Color(0xFF0F131A),
      panelHeader: Color(0xFF1B222C),
      onPanelHeader: Color(0xFF8792A5),
      record: Color(0xFFFBBF24),
      chartPrimary: Color(0xFF4C9EFF),
      chartSecondary: Color(0xFFFBBF24),
      chartGrid: Color(0xFF1E2530),
      heroStart: Color(0xFF0F2036),
      heroEnd: Color(0xFF131820),
    ),
  );
}
