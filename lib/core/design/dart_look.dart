import 'package:flutter/material.dart';

/// Die wählbaren Looks der App (Optionen → Darstellung).
enum DartLookId {
  /// Dunkel, Scoreboard und Bauchbinden wie bei einer TV-Übertragung.
  tv,

  /// Ruhig, viel Weißraum, runde Karten; hell und dunkel.
  clean,

  /// Dunkel, datendicht, technisch.
  lab;

  /// Gibt es eine helle Variante? Sonst ist der Look immer dunkel.
  bool get supportsLight => this == clean;

  static DartLookId byName(String? name) => values.where((v) => v.name == name).firstOrNull ?? tv;
}

/// Wie Karten vom Hintergrund abgesetzt werden.
enum CardTreatment {
  /// Flache Fläche ohne Rahmen (TV-Tafeln).
  flat,

  /// Dünner Rahmen (technisch).
  outlined,

  /// Weicher Schatten (hell) bzw. flach (dunkel).
  elevated,
}

/// Wie Abschnittsüberschriften aussehen.
enum HeaderTreatment {
  /// Akzentbalken + Versalien (Bauchbinde).
  bar,

  /// Ruhige Überschrift in normaler Schreibweise.
  plain,

  /// Kleine Versalien mit Linie bis zum Rand.
  rule,
}

/// Strukturelle Design-Tokens eines Looks: Schriften, Radien, Abstände,
/// Kartenstil und die großen Zahlenstile. Farben stehen in `DartColors`
/// und im `ColorScheme`. Abrufbar über `context.look`.
@immutable
class DartLook extends ThemeExtension<DartLook> {
  const DartLook({
    required this.id,
    required this.displayFamily,
    required this.bodyFamily,
    required this.card,
    required this.header,
    required this.radiusS,
    required this.radiusM,
    required this.radiusL,
    required this.radiusXL,
    required this.page,
    required this.pageWide,
    required this.cardPadding,
    required this.sectionGap,
    required this.gridGap,
    required this.shadow,
    required this.scoreHero,
    required this.scoreLarge,
    required this.scoreMedium,
    required this.statValue,
    required this.kicker,
    required this.sectionTitle,
    required this.chipNumber,
    required this.barRadius,
    required this.barHeight,
  });

  final DartLookId id;

  /// Schrift für Überschriften und große Zahlen.
  final String displayFamily;

  /// Schrift für Fließtext und Bedienelemente.
  final String bodyFamily;

  final CardTreatment card;
  final HeaderTreatment header;

  final double radiusS;
  final double radiusM;
  final double radiusL;
  final double radiusXL;

  /// Seitenrand schmal / breit.
  final double page;
  final double pageWide;

  /// Innenabstand von Karten.
  final double cardPadding;

  /// Abstand zwischen Abschnitten einer Seite.
  final double sectionGap;

  /// Abstand zwischen Kacheln eines Rasters.
  final double gridGap;

  /// Schatten von Karten (leer = keiner).
  final List<BoxShadow> shadow;

  /// Restpunkte in der Spielansicht (ohne Farbe).
  final TextStyle scoreHero;

  /// Große Zahl, z. B. Aufnahme im Board.
  final TextStyle scoreLarge;

  /// Zahl in den Dart-Feldern.
  final TextStyle scoreMedium;

  /// Wert einer Kennzahl-Kachel.
  final TextStyle statValue;

  /// Kleine Beschriftung über Zahlen („REST“, „AUFNAHME“).
  final TextStyle kicker;

  /// Abschnittsüberschrift.
  final TextStyle sectionTitle;

  /// Zahl in kleinen Dart-Feldern.
  final TextStyle chipNumber;

  /// Radius von Balken (Fortschritt, Diagramme).
  final double barRadius;

  /// Höhe von Fortschrittsbalken.
  final double barHeight;

  double pagePadding(bool wide) => wide ? pageWide : page;

  /// Text für kleine Beschriftungen ([kicker], Abschnitte): außer bei
  /// „Clean“ in Versalien.
  String caps(String text) => header == HeaderTreatment.plain ? text : text.toUpperCase();

  @override
  DartLook copyWith() => this;

  @override
  DartLook lerp(DartLook? other, double t) => other == null || t < 0.5 ? this : other;
}

extension DartLookContext on BuildContext {
  DartLook get look => Theme.of(this).extension<DartLook>() ?? DartLooks.tv;
}

/// Die drei Looks als Daten. Paletten stehen in `looks.dart`.
abstract final class DartLooks {
  static const String inter = 'Inter';
  static const String condensed = 'Barlow Condensed';
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static DartLook of(DartLookId id) => switch (id) {
        DartLookId.tv => tv,
        DartLookId.clean => clean,
        DartLookId.lab => lab,
      };

  static const DartLook tv = DartLook(
    id: DartLookId.tv,
    displayFamily: condensed,
    bodyFamily: inter,
    card: CardTreatment.flat,
    header: HeaderTreatment.bar,
    radiusS: 3,
    radiusM: 4,
    radiusL: 6,
    radiusXL: 8,
    page: 16,
    pageWide: 32,
    cardPadding: 16,
    sectionGap: 28,
    gridGap: 10,
    shadow: [],
    scoreHero: TextStyle(
      fontFamily: condensed,
      fontSize: 168,
      height: 0.9,
      fontWeight: FontWeight.w800,
      letterSpacing: -2,
      fontFeatures: tabular,
    ),
    scoreLarge: TextStyle(
      fontFamily: condensed,
      fontSize: 112,
      height: 0.95,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      fontFeatures: tabular,
    ),
    scoreMedium: TextStyle(
      fontFamily: condensed,
      fontSize: 44,
      height: 1,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
      fontFeatures: tabular,
    ),
    statValue: TextStyle(
      fontFamily: condensed,
      fontSize: 44,
      height: 1,
      fontWeight: FontWeight.w800,
      fontFeatures: tabular,
    ),
    kicker: TextStyle(
      fontFamily: condensed,
      fontSize: 15,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
    ),
    sectionTitle: TextStyle(
      fontFamily: condensed,
      fontSize: 17,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
    ),
    chipNumber: TextStyle(
      fontFamily: condensed,
      fontSize: 24,
      height: 1,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
      fontFeatures: tabular,
    ),
    barRadius: 0,
    barHeight: 6,
  );

  static const DartLook clean = DartLook(
    id: DartLookId.clean,
    displayFamily: inter,
    bodyFamily: inter,
    card: CardTreatment.elevated,
    header: HeaderTreatment.plain,
    radiusS: 10,
    radiusM: 14,
    radiusL: 22,
    radiusXL: 30,
    page: 20,
    pageWide: 44,
    cardPadding: 20,
    sectionGap: 36,
    gridGap: 14,
    shadow: [
      BoxShadow(color: Color(0x0F000000), blurRadius: 24, offset: Offset(0, 6)),
      BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
    ],
    scoreHero: TextStyle(
      fontFamily: inter,
      fontSize: 132,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -5,
      fontFeatures: tabular,
    ),
    scoreLarge: TextStyle(
      fontFamily: inter,
      fontSize: 96,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -3.5,
      fontFeatures: tabular,
    ),
    scoreMedium: TextStyle(
      fontFamily: inter,
      fontSize: 34,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
      fontFeatures: tabular,
    ),
    statValue: TextStyle(
      fontFamily: inter,
      fontSize: 32,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
      fontFeatures: tabular,
    ),
    kicker: TextStyle(
      fontFamily: inter,
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
    sectionTitle: TextStyle(
      fontFamily: inter,
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    chipNumber: TextStyle(
      fontFamily: inter,
      fontSize: 18,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      fontFeatures: tabular,
    ),
    barRadius: 999,
    barHeight: 8,
  );

  static const List<FontFeature> _labNumbers = [FontFeature.tabularFigures(), FontFeature.slashedZero()];

  static const DartLook lab = DartLook(
    id: DartLookId.lab,
    displayFamily: inter,
    bodyFamily: inter,
    card: CardTreatment.outlined,
    header: HeaderTreatment.rule,
    radiusS: 4,
    radiusM: 6,
    radiusL: 8,
    radiusXL: 10,
    page: 14,
    pageWide: 24,
    cardPadding: 14,
    sectionGap: 20,
    gridGap: 8,
    shadow: [],
    scoreHero: TextStyle(
      fontFamily: inter,
      fontSize: 120,
      height: 1,
      fontWeight: FontWeight.w600,
      letterSpacing: -4,
      fontFeatures: _labNumbers,
    ),
    scoreLarge: TextStyle(
      fontFamily: inter,
      fontSize: 88,
      height: 1,
      fontWeight: FontWeight.w600,
      letterSpacing: -3,
      fontFeatures: _labNumbers,
    ),
    scoreMedium: TextStyle(
      fontFamily: inter,
      fontSize: 30,
      height: 1.1,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      fontFeatures: _labNumbers,
    ),
    statValue: TextStyle(
      fontFamily: inter,
      fontSize: 26,
      height: 1.1,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.6,
      fontFeatures: _labNumbers,
    ),
    kicker: TextStyle(
      fontFamily: inter,
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.1,
    ),
    sectionTitle: TextStyle(
      fontFamily: inter,
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
    ),
    chipNumber: TextStyle(
      fontFamily: inter,
      fontSize: 16,
      height: 1.1,
      fontWeight: FontWeight.w600,
      fontFeatures: _labNumbers,
    ),
    barRadius: 2,
    barHeight: 4,
  );
}
