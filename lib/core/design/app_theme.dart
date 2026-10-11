import 'package:flutter/material.dart';

import 'dart_colors.dart';
import 'tokens.dart';

/// Typografie: große, gut lesbare Zahlen mit festen Ziffernbreiten,
/// damit Scores aus 2–3 m Abstand lesbar sind und nicht "springen".
abstract final class AppTypography {
  /// Mitgelieferte Schrift (assets/fonts), damit alle Plattformen gleich aussehen.
  static const String family = 'Inter';

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Riesige Zahl, z. B. Restpunkte in der Spielansicht.
  static const TextStyle scoreHuge = TextStyle(
    fontFamily: family,
    fontSize: 112,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -3,
    fontFeatures: tabular,
  );

  static const TextStyle scoreLarge = TextStyle(
    fontFamily: family,
    fontSize: 64,
    height: 1.05,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.5,
    fontFeatures: tabular,
  );

  static const TextStyle scoreMedium = TextStyle(
    fontFamily: family,
    fontSize: 36,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    fontFeatures: tabular,
  );

  static TextTheme textTheme(Color text, Color muted) => TextTheme(
        displayLarge: scoreLarge.copyWith(color: text),
        displayMedium: scoreMedium.copyWith(color: text),
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: text, letterSpacing: -0.5),
        headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.3),
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: text),
        titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: text),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: text),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: text),
        bodySmall: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: text),
        labelMedium: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.4),
        labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.6),
      );
}

abstract final class AppTheme {
  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        background: AppPalette.darkBackground,
        surface: AppPalette.darkSurface,
        surfaceHigh: AppPalette.darkSurfaceHigh,
        outline: AppPalette.darkOutline,
        text: AppPalette.darkText,
        muted: AppPalette.darkTextMuted,
        primary: AppPalette.greenBright,
        onPrimary: const Color(0xFF04140D),
        colors: DartColors.dark,
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        background: AppPalette.lightBackground,
        surface: AppPalette.lightSurface,
        surfaceHigh: AppPalette.lightSurfaceHigh,
        outline: AppPalette.lightOutline,
        text: AppPalette.lightText,
        muted: AppPalette.lightTextMuted,
        primary: const Color(0xFF128A5F),
        onPrimary: Colors.white,
        colors: DartColors.light,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceHigh,
    required Color outline,
    required Color text,
    required Color muted,
    required Color primary,
    required Color onPrimary,
    required DartColors colors,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: AppPalette.red,
      onSecondary: Colors.white,
      tertiary: AppPalette.amber,
      onTertiary: Colors.black,
      error: colors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
      outline: outline,
      outlineVariant: outline,
    );
    final textTheme = AppTypography.textTheme(text, muted).apply(fontFamily: AppTypography.family);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m));

    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.family,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      extensions: [colors],
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        foregroundColor: text,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.l),
          side: BorderSide(color: outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: shape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: shape,
          side: BorderSide(color: outline),
          foregroundColor: text,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: shape, textStyle: textTheme.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.m),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.m),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: shape,
          side: BorderSide(color: outline),
          selectedBackgroundColor: primary.withValues(alpha: 0.18),
          selectedForegroundColor: primary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withValues(alpha: 0.18),
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? primary : muted),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: primary),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(color: primary),
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(color: muted),
      ),
      listTileTheme: ListTileThemeData(
        shape: shape,
        iconColor: muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(outline),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHigh,
        contentTextStyle: textTheme.bodyMedium,
        shape: shape,
      ),
    );
  }
}
