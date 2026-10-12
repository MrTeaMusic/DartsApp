import 'package:flutter/material.dart';

import 'tokens.dart';

/// App-spezifische Farben, die Material nicht abdeckt. Abrufbar über
/// `context.dartColors`. Jeder Look (siehe `looks.dart`) liefert eigene Werte;
/// die Bedeutungen bleiben gleich: [highlight] = geplanter Checkout-Weg,
/// [tripleHit] = Triple (lila), [doubleHit] = Double (grün).
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
    required this.tripleHit,
    required this.doubleHit,
    required this.panel,
    required this.panelHeader,
    required this.onPanelHeader,
    required this.record,
    required this.chartPrimary,
    required this.chartSecondary,
    required this.chartGrid,
    required this.heroStart,
    required this.heroEnd,
  });

  final Color boardBlack;
  final Color boardCream;
  final Color boardRed;
  final Color boardGreen;
  final Color boardWire;
  final Color boardSurround;
  final Color boardNumbers;
  final Color hitGlow;

  /// Empfohlener Wurf (Checkout-Weg) und Zielhinweise: gelb.
  final Color highlight;
  final Color success;
  final Color warning;
  final Color danger;
  final Color textMuted;
  final Color surfaceHigh;
  final Color heatCold;
  final Color heatHot;

  /// Treffer im Triple-Ring (lila, damit es nicht wie ein Fehler aussieht).
  final Color tripleHit;

  /// Treffer im Double-Ring.
  final Color doubleHit;

  /// Fläche großer Anzeigen (Restpunkte, Aufnahme), z. B. die
  /// Scoreboard-Tafel im Look „TV“.
  final Color panel;

  /// Kopfleiste großer Anzeigen (TV: Akzentbalken).
  final Color panelHeader;
  final Color onPanelHeader;

  /// Rekorde, Serie, Bestwerte.
  final Color record;

  /// Diagramme: Hauptreihe, zweite Reihe (z. B. gleitender Schnitt), Raster.
  final Color chartPrimary;
  final Color chartSecondary;
  final Color chartGrid;

  /// Verlauf der Startseiten-Kachel.
  final Color heroStart;
  final Color heroEnd;

  /// Look „TV“ (Standard). Bleibt als Name erhalten, damit Tests und
  /// ältere Stellen weiter funktionieren.
  static const DartColors dark = DartColors(
    boardBlack: AppPalette.boardBlack,
    boardCream: AppPalette.boardCream,
    boardRed: AppPalette.boardRed,
    boardGreen: AppPalette.boardGreen,
    boardWire: AppPalette.boardWire,
    boardSurround: Color(0xFF05070B),
    boardNumbers: Color(0xFFF5F6FA),
    hitGlow: Color(0xFF2EE59D),
    highlight: Color(0xFFFFD23F),
    success: Color(0xFF2EE59D),
    warning: Color(0xFFFFA62B),
    danger: Color(0xFFFF4D4F),
    textMuted: Color(0xFF8F98AD),
    surfaceHigh: Color(0xFF1C2232),
    heatCold: Color(0xFF3D8BEF),
    heatHot: Color(0xFFFF4D3D),
    tripleHit: Color(0xFFB98CFF),
    doubleHit: Color(0xFF2EE59D),
    panel: Color(0xFF0B0E16),
    panelHeader: Color(0xFFE3122C),
    onPanelHeader: Colors.white,
    record: Color(0xFFFFC23D),
    chartPrimary: Color(0xFFE3122C),
    chartSecondary: Color(0xFFFFD23F),
    chartGrid: Color(0xFF1C2232),
    heroStart: Color(0xFF1A0A12),
    heroEnd: Color(0xFF0B0E16),
  );

  /// Look „Clean“, hell.
  static const DartColors light = DartColors(
    boardBlack: AppPalette.boardBlack,
    boardCream: AppPalette.boardCream,
    boardRed: AppPalette.boardRed,
    boardGreen: AppPalette.boardGreen,
    boardWire: AppPalette.boardWire,
    boardSurround: Color(0xFF1C1C1E),
    boardNumbers: Color(0xFFF4F5F2),
    hitGlow: Color(0xFF1FA855),
    highlight: Color(0xFFD99400),
    success: Color(0xFF1FA855),
    warning: Color(0xFFC77700),
    danger: Color(0xFFE5352B),
    textMuted: Color(0xFF6E6E73),
    surfaceHigh: Color(0xFFEDEDF2),
    heatCold: Color(0xFF2A78D6),
    heatHot: Color(0xFFE5392B),
    tripleHit: Color(0xFF8B46E6),
    doubleHit: Color(0xFF1FA855),
    panel: Colors.white,
    panelHeader: Color(0x00000000),
    onPanelHeader: Color(0xFF6E6E73),
    record: Color(0xFFF2A100),
    chartPrimary: Color(0xFF0A7AFF),
    chartSecondary: Color(0xFFFF9F0A),
    chartGrid: Color(0xFFEDEDF2),
    heroStart: Color(0xFFE6F0FF),
    heroEnd: Colors.white,
  );

  @override
  DartColors copyWith({
    Color? hitGlow,
    Color? highlight,
    Color? success,
    Color? warning,
    Color? danger,
    Color? textMuted,
    Color? surfaceHigh,
    Color? tripleHit,
    Color? doubleHit,
    Color? panel,
    Color? panelHeader,
    Color? onPanelHeader,
    Color? record,
    Color? chartPrimary,
    Color? chartSecondary,
    Color? chartGrid,
    Color? heroStart,
    Color? heroEnd,
    Color? boardSurround,
  }) =>
      DartColors(
        boardBlack: boardBlack,
        boardCream: boardCream,
        boardRed: boardRed,
        boardGreen: boardGreen,
        boardWire: boardWire,
        boardSurround: boardSurround ?? this.boardSurround,
        boardNumbers: boardNumbers,
        hitGlow: hitGlow ?? this.hitGlow,
        highlight: highlight ?? this.highlight,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        textMuted: textMuted ?? this.textMuted,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        heatCold: heatCold,
        heatHot: heatHot,
        tripleHit: tripleHit ?? this.tripleHit,
        doubleHit: doubleHit ?? this.doubleHit,
        panel: panel ?? this.panel,
        panelHeader: panelHeader ?? this.panelHeader,
        onPanelHeader: onPanelHeader ?? this.onPanelHeader,
        record: record ?? this.record,
        chartPrimary: chartPrimary ?? this.chartPrimary,
        chartSecondary: chartSecondary ?? this.chartSecondary,
        chartGrid: chartGrid ?? this.chartGrid,
        heroStart: heroStart ?? this.heroStart,
        heroEnd: heroEnd ?? this.heroEnd,
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
      tripleHit: l(tripleHit, other.tripleHit),
      doubleHit: l(doubleHit, other.doubleHit),
      panel: l(panel, other.panel),
      panelHeader: l(panelHeader, other.panelHeader),
      onPanelHeader: l(onPanelHeader, other.onPanelHeader),
      record: l(record, other.record),
      chartPrimary: l(chartPrimary, other.chartPrimary),
      chartSecondary: l(chartSecondary, other.chartSecondary),
      chartGrid: l(chartGrid, other.chartGrid),
      heroStart: l(heroStart, other.heroStart),
      heroEnd: l(heroEnd, other.heroEnd),
    );
  }
}

extension DartColorsContext on BuildContext {
  DartColors get dartColors => Theme.of(this).extension<DartColors>() ?? DartColors.dark;
}
