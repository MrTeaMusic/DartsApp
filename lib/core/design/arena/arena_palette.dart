import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../dart_look.dart';

/// Farben der Arena-Spielansicht. Die Ansicht ist unabhängig vom gewählten
/// Look: dunkelblauer Grund, fast schwarze Flächen, blauer Akzent und für den
/// Spieler am Zug ein Verlauf von Violett nach Rot-Rosa.
abstract final class ArenaPalette {
  /// Schmaler, fast schwarzer Streifen ganz oben.
  static const Color stripe = Color(0xFF01040F);

  /// Grund (Marineblau) und die etwas helleren Töne der Dreiecke.
  static const Color background = Color(0xFF001137);
  static const Color backgroundMid = Color(0xFF02153E);
  static const Color backgroundLight = Color(0xFF001743);
  static const Color shape = Color(0xFF1B3F9A);

  /// Tafeln, Wurfleiste und Tabelle.
  static const Color surface = Color(0xFF17181C);

  /// Obere Fläche des Spielers, der nicht am Zug ist.
  static const Color surfaceFlat = Color(0xFF181A1E);
  static const Color separator = Color(0xFF505158);

  /// Verlauf der Tafel des Spielers am Zug (oben links nach unten rechts).
  static const Color gradientStart = Color(0xFF802E90);
  static const Color gradientMid = Color(0xFFA6266F);
  static const Color gradientEnd = Color(0xFFD63756);

  /// Der Verlauf als Füllung (Tafel am Zug, wichtigste Karte, aktiver Reiter).
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientMid, gradientEnd],
  );

  /// Verlauf der Tafel des Siegers.
  static const Color wonStart = Color(0xFF0E6B4D);
  static const Color wonMid = Color(0xFF13885F);
  static const Color wonEnd = Color(0xFF1FA874);

  /// Kleine Schilder (Spiel, Format, Ein-/Ausstieg).
  static const Color chip = Color(0xFF2C2C37);
  static const Color chipAlt = Color(0xFF292E37);

  /// Blau der Schaltflächen und der Schalterleiste dahinter.
  static const Color blue = Color(0xFF0955DF);

  /// Helleres Blau für kleine Symbole auf dunkler Fläche (Stift, „+“).
  static const Color blueLight = Color(0xFF6FA2FF);
  static const Color pill = Color(0xFF002E8B);

  /// Schwarzes Schild (Name, Punkte der letzten Aufnahme).
  static const Color badge = Color(0xFF04050C);

  /// Helle Fläche für den aktuellen Stand in der Tabelle.
  static const Color light = Color(0xFFFCFBFC);
  static const Color onLight = Color(0xFF17181C);

  static const Color text = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFFA3A7B7);

  /// Bedeutung: Checkout/Sieg, Bust/Fehler, Aufnahme ab 100, Hinweis.
  static const Color success = Color(0xFF35D69C);
  static const Color danger = Color(0xFFFF5D73);
  static const Color record = Color(0xFFFFC23D);
  static const Color hint = Color(0xFFFFD54F);

  static ThemeData? _theme;

  /// Dunkles Theme der Arena (Look „Arena“), auch für die Spielansicht, wenn
  /// ein anderer Look gewählt ist: Pfeile, Pillen, Karten, Doppel-Zoom.
  static ThemeData get theme => _theme ??= AppTheme.build(DartLookId.arena, Brightness.dark);
}
