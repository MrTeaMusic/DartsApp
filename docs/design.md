# Design: Looks, Tokens und neue Bildschirme

DartLab hat drei wählbare Looks (Optionen → Darstellung). Die Wahl wird in
den Einstellungen gespeichert (`settings.look`) und gilt sofort in der ganzen
App. Alle Looks sind reine Daten: Bildschirme kennen keine Farben oder
Schriftgrößen, sondern nur Theme-Tokens und die gemeinsamen Komponenten.

## Die drei Looks

| Look | Charakter | Helligkeit |
| --- | --- | --- |
| **TV** (Standard) | Wie eine Darts-Übertragung: Studio-Schwarz, Signalrot, Scoreboard-Tafeln mit roter Beschriftungsleiste (Bauchbinde), schmale fette Überschriften und Zahlen (Barlow Condensed), flache Tafeln mit kleinen Radien. | immer dunkel |
| **Clean** | Ruhig wie eine Fitness-App: viel Weißraum, weiße Karten mit weichem Schatten (hell) bzw. dunkelgraue Karten (dunkel), große Radien, Pillen-Knöpfe, Überschriften in normaler Schreibweise, ruhiges Blau. | folgt dem System, manuell Hell/Dunkel |
| **Lab** | Technisch und datendicht: Graphit, feine 1-px-Linien, kleine Versalien mit Linie als Abschnittstitel, kompakte Abstände, Ziffern mit festen Breiten und durchgestrichener Null, elektrisches Blau. | immer dunkel |

Feste Farbbedeutungen in allen Looks (nur der Ton wird je Look angepasst):

* **Gelb** (`highlight`): geplanter Wurf / Checkout-Weg in den freien Dart-Feldern.
* **Lila** (`tripleHit`): Triple-Treffer, auch Triple-Quoten in der Statistik.
* **Grün** (`doubleHit`): Double-Treffer, auch Checkout-Bereiche.
* `success` / `danger` / `warning`: besser / schlechter / Achtung.

## Wo was steht

```
lib/core/design/
  dart_look.dart     DartLookId (tv, clean, lab), DartLook (Schriften, Radien,
                     Abstände, Kartenstil, Zahlenstile) und DartLooks (die Werte)
  looks.dart         LookPalette je Look und Helligkeit (Grundfarben + DartColors)
  dart_colors.dart   DartColors: App-Farben (highlight, tripleHit, panel, chart…)
  app_theme.dart     AppTheme.build(look, brightness) → ThemeData mit beiden
                     Extensions; Typografie je Look (AppTypography.textTheme)
  tokens.dart        AppSpacing (Grundraster 4/8/12/16/24/32), AppRadii,
                     AppDurations, AppBreakpoints, Board-Farben
  components/        gemeinsame Bausteine (siehe unten)
```

Zugriff im Widget:

* `Theme.of(context).colorScheme` und `textTheme` für Material-Farben und Text.
* `context.dartColors` für App-Farben (`highlight`, `tripleHit`, `doubleHit`,
  `record`, `panel`, `chartPrimary`, `chartSecondary`, `chartGrid`, …).
* `context.look` für Strukturtokens: `pagePadding(wide)`, `sectionGap`,
  `gridGap`, `cardPadding`, `radiusS/M/L/XL`, `barRadius`, `barHeight` und die
  Zahlenstile `scoreHero`, `scoreLarge`, `scoreMedium`, `statValue`,
  `chipNumber`, `kicker`, `sectionTitle`. `look.caps(text)` setzt kleine
  Beschriftungen in Versalien (außer bei Clean).

## Komponenten

| Baustein | Wofür |
| --- | --- |
| `AppPage` + `AppPageBar` | Einspaltige Seite mit Seitenrand und Höchstbreite des Looks; die Kopfzeile steht bündig mit dem Inhalt. |
| `SectionGap` | Abstand zwischen Abschnitten (Rhythmus des Looks). |
| `SectionHeader` | Abschnittstitel (TV: roter Balken, Clean: ruhig, Lab: Versalien mit Linie). Optionaler Zusatz rechts (Knopf, Statusschild), höchstens 200 px breit. |
| `AppCard` | Jede Karte. Rahmen/Schatten/Radius kommen vom Look. |
| `ScorePanel` | Große Zahl mit Beschriftung, optional Fortschritt und Inhalt darunter (Restpunkte, Aufnahme, Ergebnis). Mit `active` für mehrere Tafeln nebeneinander (Spieler im Match): `true` hervorgehoben, `false` zurückgenommen. |
| `LookBanner` | Einblendung eines Ereignisses (Checkout, Bust, 180, Leg gewonnen) im Stil des Looks; optional kleine Beschriftung davor. |
| `StatTile` | Kennzahl-Kachel (Beschriftung, große Zahl, Zusatz). |
| `Kicker` | Kleine Beschriftung über einer Zahl. |
| `DartChip` + `segmentColor` | Dart-Feld, eingefärbt nach Bedeutung. |
| `IconBadge` | Symbol in getönter Fläche (Spiel-, Plan-, Rekordlisten). |
| `LookProgressBar` | Fortschrittsbalken in Höhe und Radius des Looks. |
| `StatusPill` | Statusschild mit Punkt. |
| `HeroBackdrop` | Hintergrund großer Kopfflächen (Startseite). |
| `ComingSoon` | Leerer Zustand mit Symbol, Titel und Text. |
| `LookPickerTile` | Auswahlkachel mit echter Miniatur des Looks. |

## Einen Bildschirm richtig anlegen

1. **Gerüst:** `Scaffold(appBar: AppPageBar(title: …, maxWidth: 640), body: AppPage(maxWidth: 640, children: […]))`.
   Für Raster/volle Breite den Rand mit `context.look.pagePadding(breite >= kWidePage)` bestimmen.
2. **Abschnitte:** `SectionHeader('Titel')`, darunter Inhalt in `AppCard`, zwischen
   Abschnitten `const SectionGap()`. Kacheln im Raster mit `context.look.gridGap`.
3. **Zahlen:** große Werte mit `ScorePanel` oder `StatTile`; eigene Zahlen mit
   den Stilen aus `context.look` und Farbe aus `colorScheme.onSurface`.
4. **Farben:** nie `Color(0x…)` oder `Colors.*` im Bildschirm. Bedeutungen über
   `context.dartColors` (Triple, Double, Weg, Erfolg, Gefahr), Akzent über
   `colorScheme.primary`, Diagramme über `chartPrimary`/`chartSecondary`/`chartGrid`.
5. **Text:** Stile aus `textTheme`; kleine Beschriftungen über `Kicker`. Texte, die
   in schmalen Kacheln stehen, mit `maxLines`/`overflow` oder `FittedBox`
   absichern (Telefonbreite 390 px).
6. **Prüfen:** Der Test `test/widgets/design_looks_test.dart` öffnet die
   Hauptbildschirme in allen drei Looks bei 390 px; neue Routen dort ergänzen.

## Einen Look ändern oder ergänzen

* Strukturwerte in `DartLooks` (dart_look.dart), Farben in `LookPalettes`
  (looks.dart), Material-Details (Knöpfe, Chips, Navigation) in `AppTheme._build`.
* Neuer Look: Wert in `DartLookId`, `DartLook` in `DartLooks`, Palette(n) in
  `LookPalettes`, Typografie-Zweig in `AppTypography.textTheme`, Name/Text in
  `app_de.arb` und eine Kachel in der Auswahl der Optionen.

## Schriften

* **Inter** (Fließtext, Clean, Lab) und **Barlow Condensed** (Überschriften und
  Zahlen im Look TV) liegen in `assets/fonts`, beide unter der SIL Open Font
  License (Lizenzdateien daneben).
