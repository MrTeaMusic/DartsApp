import 'package:flutter/material.dart';

import 'dart_look.dart';
import 'looks.dart';
import 'tokens.dart';

/// Typografie: große, gut lesbare Zahlen mit festen Ziffernbreiten,
/// damit Scores aus 2–3 m Abstand lesbar sind und nicht "springen".
///
/// Die Stile hier sind die des Standard-Looks; look-abhängige Zahlenstile
/// liefert `context.look` (z. B. `context.look.scoreHero`).
abstract final class AppTypography {
  /// Mitgelieferte Schrift (assets/fonts), damit alle Plattformen gleich aussehen.
  static const String family = 'Inter';

  /// Schmale Schrift für Überschriften und Zahlen im Look „TV“.
  static const String condensed = DartLooks.condensed;

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

  /// Schriftgrößen und -schnitte je Look.
  static TextTheme textTheme(DartLook look, Color text, Color muted) {
    final d = look.displayFamily;
    final b = look.bodyFamily;
    switch (look.id) {
      case DartLookId.tv:
        return TextTheme(
          displayLarge: look.scoreLarge.copyWith(color: text, fontSize: 72),
          displayMedium: look.statValue.copyWith(color: text),
          displaySmall: TextStyle(fontFamily: d, fontSize: 32, fontWeight: FontWeight.w800, color: text),
          headlineLarge: TextStyle(fontFamily: d, fontSize: 38, height: 1.05, fontWeight: FontWeight.w800, color: text, letterSpacing: 0.2),
          headlineMedium: TextStyle(fontFamily: d, fontSize: 30, height: 1.1, fontWeight: FontWeight.w800, color: text, letterSpacing: 0.2),
          headlineSmall: TextStyle(fontFamily: d, fontSize: 24, height: 1.15, fontWeight: FontWeight.w700, color: text, letterSpacing: 0.3),
          titleLarge: TextStyle(fontFamily: d, fontSize: 22, height: 1.2, fontWeight: FontWeight.w700, color: text, letterSpacing: 0.3),
          titleMedium: TextStyle(fontFamily: b, fontSize: 15.5, fontWeight: FontWeight.w600, color: text),
          titleSmall: TextStyle(fontFamily: b, fontSize: 14, fontWeight: FontWeight.w600, color: text),
          bodyLarge: TextStyle(fontFamily: b, fontSize: 16, height: 1.45, color: text),
          bodyMedium: TextStyle(fontFamily: b, fontSize: 14, height: 1.45, color: text),
          bodySmall: TextStyle(fontFamily: b, fontSize: 12.5, height: 1.4, color: muted),
          labelLarge: TextStyle(fontFamily: d, fontSize: 17, fontWeight: FontWeight.w700, color: text, letterSpacing: 0.6),
          labelMedium: TextStyle(fontFamily: d, fontSize: 14, fontWeight: FontWeight.w700, color: muted, letterSpacing: 1.1),
          labelSmall: TextStyle(fontFamily: d, fontSize: 12, fontWeight: FontWeight.w700, color: muted, letterSpacing: 1.1),
        );
      case DartLookId.clean:
        return TextTheme(
          displayLarge: look.scoreLarge.copyWith(color: text, fontSize: 64),
          displayMedium: look.statValue.copyWith(color: text),
          displaySmall: TextStyle(fontFamily: d, fontSize: 28, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.8),
          headlineLarge: TextStyle(fontFamily: d, fontSize: 34, height: 1.15, fontWeight: FontWeight.w700, color: text, letterSpacing: -1),
          headlineMedium: TextStyle(fontFamily: d, fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.7),
          headlineSmall: TextStyle(fontFamily: d, fontSize: 22, height: 1.25, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.4),
          titleLarge: TextStyle(fontFamily: d, fontSize: 19, height: 1.3, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.3),
          titleMedium: TextStyle(fontFamily: b, fontSize: 16, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.2),
          titleSmall: TextStyle(fontFamily: b, fontSize: 14, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.1),
          bodyLarge: TextStyle(fontFamily: b, fontSize: 16, height: 1.5, color: text, letterSpacing: -0.1),
          bodyMedium: TextStyle(fontFamily: b, fontSize: 14.5, height: 1.5, color: text, letterSpacing: -0.1),
          bodySmall: TextStyle(fontFamily: b, fontSize: 13, height: 1.45, color: muted),
          labelLarge: TextStyle(fontFamily: b, fontSize: 15, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.1),
          labelMedium: TextStyle(fontFamily: b, fontSize: 13, fontWeight: FontWeight.w500, color: muted),
          labelSmall: TextStyle(fontFamily: b, fontSize: 11.5, fontWeight: FontWeight.w500, color: muted),
        );
      case DartLookId.lab:
        return TextTheme(
          displayLarge: look.scoreLarge.copyWith(color: text, fontSize: 56),
          displayMedium: look.statValue.copyWith(color: text),
          displaySmall: TextStyle(fontFamily: d, fontSize: 24, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.5),
          headlineLarge: TextStyle(fontFamily: d, fontSize: 24, height: 1.2, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.5),
          headlineMedium: TextStyle(fontFamily: d, fontSize: 20, height: 1.25, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.3),
          headlineSmall: TextStyle(fontFamily: d, fontSize: 18, height: 1.3, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.2),
          titleLarge: TextStyle(fontFamily: d, fontSize: 16, height: 1.3, fontWeight: FontWeight.w600, color: text),
          titleMedium: TextStyle(fontFamily: b, fontSize: 14, fontWeight: FontWeight.w600, color: text),
          titleSmall: TextStyle(fontFamily: b, fontSize: 13, fontWeight: FontWeight.w600, color: text),
          bodyLarge: TextStyle(fontFamily: b, fontSize: 14.5, height: 1.45, color: text),
          bodyMedium: TextStyle(fontFamily: b, fontSize: 13, height: 1.45, color: text),
          bodySmall: TextStyle(fontFamily: b, fontSize: 12, height: 1.4, color: muted),
          labelLarge: TextStyle(fontFamily: b, fontSize: 13.5, fontWeight: FontWeight.w600, color: text, letterSpacing: 0.1),
          labelMedium: TextStyle(fontFamily: b, fontSize: 11, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.9),
          labelSmall: TextStyle(fontFamily: b, fontSize: 10, fontWeight: FontWeight.w600, color: muted, letterSpacing: 1),
        );
    }
  }
}

abstract final class AppTheme {
  /// Standard-Look „TV“ (dunkel).
  static ThemeData dark() => build(DartLookId.tv, Brightness.dark);

  /// Look „Clean“ hell.
  static ThemeData light() => build(DartLookId.clean, Brightness.light);

  /// ThemeData für einen Look. Looks ohne helle Variante liefern immer die
  /// dunkle.
  static ThemeData build(DartLookId id, Brightness brightness) {
    final look = DartLooks.of(id);
    final palette = LookPalettes.of(id, id.supportsLight ? brightness : Brightness.dark);
    return _build(look, palette);
  }

  static ThemeData _build(DartLook look, LookPalette p) {
    final colors = p.colors;
    final isTv = look.id == DartLookId.tv;
    final isClean = look.id == DartLookId.clean;
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: p.primary.withValues(alpha: 0.16),
      onPrimaryContainer: p.text,
      secondary: p.secondary,
      onSecondary: p.onSecondary,
      secondaryContainer: p.primary.withValues(alpha: 0.16),
      onSecondaryContainer: p.text,
      tertiary: colors.highlight,
      onTertiary: Colors.black,
      error: colors.danger,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.text,
      onSurfaceVariant: p.muted,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceHigh,
      surfaceContainerHighest: p.surfaceHigh,
      outline: p.outline,
      outlineVariant: p.outline,
      inverseSurface: p.text,
      onInverseSurface: p.background,
      shadow: Colors.black,
      surfaceTint: Colors.transparent,
    );
    final textTheme = AppTypography.textTheme(look, p.text, p.muted);
    RoundedRectangleBorder rounded(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
    final OutlinedBorder buttonShape = isClean ? const StadiumBorder() : rounded(look.radiusM);
    final buttonHeight = switch (look.id) {
      DartLookId.tv => 52.0,
      DartLookId.clean => 50.0,
      DartLookId.lab => 44.0,
    };
    final cardSide = look.card == CardTreatment.outlined ? BorderSide(color: p.outline) : BorderSide.none;
    final indicatorShape = isClean ? const StadiumBorder() : rounded(look.radiusM);
    final indicator = isTv ? p.primary : p.primary.withValues(alpha: isClean ? 0.14 : 0.18);
    final selectedNav = isTv ? p.onPrimary : p.primary;

    return ThemeData(
      useMaterial3: true,
      fontFamily: look.bodyFamily,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      textTheme: textTheme,
      extensions: [colors, look],
      visualDensity: look.id == DartLookId.lab ? VisualDensity.compact : VisualDensity.standard,
      splashFactory: isClean ? InkSparkle.splashFactory : InkRipple.splashFactory,
      dividerTheme: DividerThemeData(color: p.outline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.text, size: look.id == DartLookId.lab ? 20 : 24),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: look.id == DartLookId.lab ? 52 : (isClean ? 64 : 60),
        titleSpacing: look.page,
        titleTextStyle: switch (look.id) {
          DartLookId.tv => textTheme.headlineMedium?.copyWith(fontSize: 28),
          DartLookId.clean => textTheme.headlineMedium,
          DartLookId.lab => textTheme.titleLarge?.copyWith(fontSize: 17),
        },
        foregroundColor: p.text,
        shape: look.id == DartLookId.lab ? Border(bottom: BorderSide(color: p.outline)) : null,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(look.radiusL), side: cardSide),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(48, buttonHeight),
          padding: EdgeInsets.symmetric(horizontal: isClean ? AppSpacing.xl : AppSpacing.l + 4),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
          disabledBackgroundColor: p.surfaceHigh,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(48, buttonHeight),
          padding: EdgeInsets.symmetric(horizontal: isClean ? AppSpacing.xl : AppSpacing.l + 4),
          shape: buttonShape,
          // Clean: getönte Fläche statt Rahmen.
          side: isClean ? BorderSide.none : BorderSide(color: isTv ? p.text.withValues(alpha: 0.35) : p.outline, width: isTv ? 1.5 : 1),
          backgroundColor: isClean ? p.surfaceHigh : (look.id == DartLookId.lab ? p.surface : null),
          foregroundColor: p.text,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: buttonShape, textStyle: textTheme.labelLarge),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: isClean ? const CircleBorder() : rounded(look.radiusM)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        elevation: isClean ? 2 : 0,
        highlightElevation: isClean ? 4 : 0,
        shape: isClean ? const StadiumBorder() : rounded(look.radiusM),
        extendedTextStyle: textTheme.labelLarge,
      ),
      chipTheme: ChipThemeData(
        shape: isClean ? const StadiumBorder() : rounded(look.radiusS),
        side: WidgetStateBorderSide.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return BorderSide(color: isTv ? p.primary : p.primary.withValues(alpha: 0.6));
          return isClean ? BorderSide.none : BorderSide(color: p.outline);
        }),
        color: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return isTv ? p.primary : p.primary.withValues(alpha: isClean ? 0.14 : 0.16);
          return isClean ? p.surfaceHigh : p.surface;
        }),
        // Die Chip-Beschriftung löst nur die Farbe nach Zustand auf.
        labelStyle: textTheme.labelLarge?.copyWith(
          fontSize: isTv ? 16 : (isClean ? 14 : 13),
          color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? (isTv ? p.onPrimary : p.primary) : p.text,
          ),
        ),
        checkmarkColor: isTv ? p.onPrimary : p.primary,
        showCheckmark: isClean,
        padding: EdgeInsets.symmetric(horizontal: look.id == DartLookId.lab ? AppSpacing.xs : AppSpacing.s, vertical: AppSpacing.xs),
        iconTheme: IconThemeData(color: p.muted, size: 18),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: look.id == DartLookId.lab ? p.background : p.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(look.radiusM),
          borderSide: look.id == DartLookId.lab ? BorderSide(color: p.outline) : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(look.radiusM),
          borderSide: look.id == DartLookId.lab ? BorderSide(color: p.outline) : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(look.radiusM),
          borderSide: BorderSide(color: p.primary, width: 2),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: isClean ? const StadiumBorder() : rounded(look.radiusM),
          side: BorderSide(color: p.outline),
          backgroundColor: isClean ? p.surface : null,
          selectedBackgroundColor: isTv ? p.primary : p.primary.withValues(alpha: 0.16),
          selectedForegroundColor: isTv ? p.onPrimary : p.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: isTv ? p.text : p.primary,
        unselectedLabelColor: p.muted,
        labelStyle: isTv ? textTheme.labelLarge?.copyWith(fontSize: 18) : textTheme.labelLarge,
        unselectedLabelStyle: isTv ? textTheme.labelLarge?.copyWith(fontSize: 18) : textTheme.labelLarge,
        dividerColor: p.outline,
        indicatorSize: isClean ? TabBarIndicatorSize.label : TabBarIndicatorSize.tab,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: p.primary, width: isTv ? 4 : (isClean ? 3 : 2)),
          borderRadius: isClean ? const BorderRadius.vertical(top: Radius.circular(3)) : BorderRadius.zero,
        ),
        overlayColor: WidgetStatePropertyAll(p.primary.withValues(alpha: 0.06)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isTv ? colors.panel : p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: indicator,
        indicatorShape: indicatorShape,
        height: look.id == DartLookId.lab ? 60 : 68,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final sel = s.contains(WidgetState.selected);
          final base = isTv ? textTheme.labelMedium?.copyWith(fontSize: 13, letterSpacing: 0.6) : textTheme.labelMedium?.copyWith(letterSpacing: 0.2);
          return base?.copyWith(color: sel ? p.text : p.muted);
        }),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? selectedNav : p.muted, size: 24),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isTv ? colors.panel : (isClean ? p.background : p.surface),
        indicatorColor: indicator,
        indicatorShape: indicatorShape,
        selectedIconTheme: IconThemeData(color: selectedNav),
        unselectedIconTheme: IconThemeData(color: p.muted),
        selectedLabelTextStyle: (isTv ? textTheme.labelLarge : textTheme.titleSmall)?.copyWith(color: p.text),
        unselectedLabelTextStyle: (isTv ? textTheme.labelLarge : textTheme.titleSmall)?.copyWith(color: p.muted, fontWeight: FontWeight.w500),
      ),
      listTileTheme: ListTileThemeData(
        shape: rounded(look.radiusM),
        iconColor: p.muted,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        dense: look.id == DartLookId.lab,
        contentPadding: EdgeInsets.symmetric(horizontal: look.cardPadding),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(isClean ? Colors.transparent : p.outline),
        thumbColor: isClean
            ? WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : Colors.white)
            : null,
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? (isClean ? colors.success : p.primary) : p.surfaceHigh,
        ),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary : p.muted)),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.primary,
        inactiveTrackColor: p.surfaceHigh,
        thumbColor: isClean ? Colors.white : p.primary,
        trackHeight: look.id == DartLookId.lab ? 3 : 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.surfaceHigh,
        circularTrackColor: p.surfaceHigh,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded(look.radiusXL),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: p.outline,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(look.radiusXL))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: rounded(look.radiusM),
        textStyle: textTheme.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: p.text, borderRadius: BorderRadius.circular(look.radiusS)),
        textStyle: textTheme.bodySmall?.copyWith(color: p.background),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceHigh,
        contentTextStyle: textTheme.bodyMedium,
        shape: rounded(look.radiusM),
      ),
    );
  }
}
