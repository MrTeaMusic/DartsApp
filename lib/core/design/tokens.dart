import 'package:flutter/material.dart';

/// Zentrale Design-Tokens. Farben, Abstände, Radien und Animationszeiten
/// werden nur hier definiert, damit das Aussehen an einer Stelle anpassbar ist.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Innenabstand großer Flächen (Seitenrand).
  static const double page = 20;
  static const double pageWide = 32;
}

abstract final class AppRadii {
  static const double s = 8;
  static const double m = 14;
  static const double l = 20;
  static const double xl = 28;
  static const double pill = 999;
}

abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration hit = Duration(milliseconds: 900);
}

/// Breakpoints für das adaptive Layout.
abstract final class AppBreakpoints {
  /// Ab hier Seitenleiste statt Bottom-Navigation.
  static const double sidebar = 840;

  /// Ab hier ausgeklappte Seitenleiste mit Beschriftung.
  static const double sidebarExtended = 1200;
}

/// Grundpalette. Light und Dark teilen sich die Akzentfarben.
abstract final class AppPalette {
  // Akzente
  static const Color green = Color(0xFF1FB57F);
  static const Color greenBright = Color(0xFF35D69C);
  static const Color red = Color(0xFFE5483D);
  static const Color amber = Color(0xFFF0A92E);
  static const Color blue = Color(0xFF3D8BEF);

  // Dark
  static const Color darkBackground = Color(0xFF0D100F);
  static const Color darkSurface = Color(0xFF151918);
  static const Color darkSurfaceHigh = Color(0xFF1E2321);
  static const Color darkOutline = Color(0xFF2D3431);
  static const Color darkText = Color(0xFFF4F5F2);
  static const Color darkTextMuted = Color(0xFF9AA39F);

  // Light
  static const Color lightBackground = Color(0xFFF3F2EE);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHigh = Color(0xFFEAE9E4);
  static const Color lightOutline = Color(0xFFD7D5CD);
  static const Color lightText = Color(0xFF101211);
  static const Color lightTextMuted = Color(0xFF5E605B);

  // Dartboard
  static const Color boardBlack = Color(0xFF1A1A1A);
  static const Color boardCream = Color(0xFFEFE4C8);
  static const Color boardRed = Color(0xFFD23B30);
  static const Color boardGreen = Color(0xFF14915F);
  static const Color boardWire = Color(0xFFB9BCC0);
  static const Color boardSurround = Color(0xFF0A0A0A);
}
