# App-Icons

Alle Icons (DartLab für Windows, macOS und iOS, DartLab Lite für Android) kommen
aus einem Skript. Das Motiv ist eigene Zeichnung: drei verdrehte Zielbögen im
Verlauf Koralle, Magenta, Violett um einen hellen Punkt, bei DartLab mit dem
Schriftzug "DartLab" darunter.

| Plattform | Dateien | Aussehen |
| --- | --- | --- |
| Windows | `windows/runner/resources/app_icon.ico` (16, 24, 32, 48, 64, 128, 256 px, PNG eingebettet) | abgerundetes Quadrat, dunkle Violettplatte |
| macOS | `macos/Runner/Assets.xcassets/AppIcon.appiconset` (`app_icon_16` bis `app_icon_1024`) | abgerundetes Quadrat (824 von 1024 px) mit Rand und Schatten |
| iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset` (alle Größen aus `Contents.json`) | volles Quadrat, ohne Rundung und ohne Alphakanal, iOS maskiert selbst |
| Android (Lite) | `android/app/src/main/res`: `mipmap-anydpi-v26/ic_launcher.xml`, `drawable-*dpi/ic_launcher_{background,foreground,monochrome}.png`, `mipmap-*dpi/ic_launcher.png` | Türkis-Blau-Platte, weiße Bögen, Auge-Abzeichen ("nur ansehen"), ohne Schriftzug |

## Neu erzeugen

```
node tools/app_icons/generate.mjs   # schreibt alle Dateien oben und tools/app_icons/master/*.svg
node tools/app_icons/verify.mjs     # prüft Dateien, Größen, iOS ohne Alpha, ICO-Größen
```

Voraussetzung: Node 18 oder neuer und Playwright mit Chromium (global
installiert oder über `NODE_PATH`). Das Skript rendert die SVGs in Chromium zu
PNG, schreibt die ICO und entfernt bei iOS den Alphakanal (alles mit
`node:zlib`). Es kommt keine Abhängigkeit in `pubspec.yaml`. Im Repo liegen nur
die Erzeugungsskripte und drei SVG-Master, keine Zwischenstände.

Dateien in `tools/app_icons/`:

* `icon_svg.mjs`: die Zeichnung (Farben, Platten, Bögen, Abzeichen, Schriftzug).
  Hier ändern, wenn sich das Aussehen ändern soll.
* `generate.mjs`, `png.mjs`, `verify.mjs`: Erzeugung, PNG/ICO-Helfer, Prüfung.
* `master/dartlab.svg`, `master/dartlab-bogen.svg`, `master/lite.svg`: Master
  bei 1024 px, zum Ansehen und Weiterverwenden (z. B. Store-Grafik). Sie werden
  vom Skript neu geschrieben.
* `text_paths.mjs`, `text_to_paths.py`: der Schriftzug (siehe unten).

## Größenabhängige Vereinfachung

Das Icon wird nicht einfach herunterskaliert, sondern je Größe neu gezeichnet:

* ab 150 px: mit weichem Glühen,
* 44 bis 149 px: ohne Glühen,
* darunter (16, 24, 32 px): zwei dicke Bögen mit großem Punkt.

**Schriftzug nur, wenn er lesbar bleibt.** Schwelle `TEXT_MIN_PX = 100` in
`icon_svg.mjs`, gemessen an der Symbolgröße (bei macOS an den 80 %, die das
Quadrat ausmacht). Das ergibt Text bei Windows 128 und 256, macOS ab 128, iOS ab
120 px. Alles darunter (Taskleiste, Datei-Symbole, kleine iOS-Größen) zeigt nur
die Bögen. Zur Orientierung: ab etwa 128 px ist die Schrift gut lesbar, bei 96
px knapp, bei 64 px und darunter nicht mehr. Android Lite trägt nie den
Schriftzug: Er passt nicht in die Safe-Zone (66 von 108 dp), und der Launcher
zeigt den App-Namen ohnehin unter dem Symbol.

## Schrift

Der Schriftzug steckt als SVG-Pfade in `text_paths.mjs` (Inter ExtraBold,
SIL Open Font License 1.1, (c) The Inter Project Authors). So hängt die Erzeugung
nicht von einer installierten Schrift ab. Nur wenn Wortlaut oder Schrift
geändert werden, braucht man `text_to_paths.py` (Python mit `fontTools`): Es
liest die Zeichenpositionen aus dem Browser (`getStartPositionOfChar` eines
SVG-Texts, damit Kerning und Zeichenabstand stimmen) und schreibt die Pfade.
Für die normale Icon-Erzeugung ist das nicht nötig.

## Android

* Adaptives Icon (ab Android 8): Hintergrund `ic_launcher_background` (Verlauf
  als PNG, 108 dp), Vordergrund `ic_launcher_foreground` (Bögen und Abzeichen
  im 66-dp-Kreis der Safe-Zone), `monochrome` für das Themed-Icon ab Android 13
  (einfarbige Bögen ohne Abzeichen).
* Android vor 8 nutzt `mipmap-*dpi/ic_launcher.png` (abgerundetes Quadrat,
  48 bis 192 px). Das Manifest verweist unverändert auf `@mipmap/ic_launcher`;
  ein eigenes Rund-Icon ist nicht nötig, die Maske setzt das System.
* Die frühere Farbdatei `values/ic_launcher_background.xml` entfällt, der
  Hintergrund ist jetzt ein Drawable gleichen Namens.
