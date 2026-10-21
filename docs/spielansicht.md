# Spielansicht

Es gibt zwei Spielansichten für X01 (Match und X01-Solo). Welche gezeigt wird,
stellt man in den Optionen unter Darstellung > Spielansicht ein:

- **Arena** (Standard): ein eigenes Erscheinungsbild nach dem Vorbild der
  Autodarts-Match-Ansicht, unabhängig vom gewählten Look (TV, Clean, Lab).
- **Wie das gewählte Design**: die bisherige Ansicht in den Farben und Formen
  des Looks, mit der Aufnahmen-Tabelle unter dem Namen (weiter unten).

Die Einstellung heißt `settings.playView` (`arena` oder `look`). Ist der Look
„Arena“ gewählt (siehe [design.md](design.md)), zeigt auch „Wie das gewählte
Design“ die Arena-Spielansicht (`AppSettings.arenaPlay`). Andere Spiele
(Checkout, Drills usw.) sind davon nicht betroffen.

## Arena

Code: `lib/core/design/arena/` (`arena_palette`, `arena_background`,
`arena_player_panel`, `arena_chrome`, `arena_screen`). Match und Solo füllen
dasselbe `ArenaScreen`; die Aufnahmen werden wie immer nur aus den
Aufzeichnungen abgeleitet (siehe "Woher die Zeilen kommen"), daher stimmen
Rückgängig, Korrektur und Legwechsel von selbst.

### Maße (breit, ab 640 px Breite und Seitenverhältnis 5:4)

- Drei Spalten: Tafel links 26,5 % der Breite, Mitte 39,25 %, Tafel rechts
  26,5 %. Die Tafeln sind etwa 68,7 % so hoch wie der Bildschirm und beginnen
  unter der Kopfzeile (mindestens 9,8 % der Höhe); unter ihnen bleibt Luft.
- Mitte von oben nach unten: Wurfleiste (drei Dart-Plätze und Summe der
  Aufnahme), Schalterleiste (Korrigieren, Rückgängig, Weiter; immer sichtbar),
  Board, Hinweise (Checkout-Weg, wer dran ist). Das Board ist so breit wie die
  Wurfleiste, bei sehr breiten Fenstern begrenzt die Höhe.
- Oben links "Verlassen" mit den Schildern für Spiel, Format und Ein-/Ausstieg
  (z. B. "501", "Erster bis 1 Leg", "SI-DO"), oben rechts Verbindung, Ansage
  und Vollbild.
- Die Tafeln sind in Vorlagenmaßen gezeichnet und skaliert
  (`min(Breite/Vorlagenbreite, Höhe/Vorlagenhöhe)`); Zeilenhöhe 52 und
  Schriftgröße 28 jeweils mal Skalierung. Getestet: 1440x900, 1920x1080,
  1180x820 (Tablet quer) ohne Überlauf.

### Tafel

Oben: Namensschild mit Avatar und Startpunkt (weißer Punkt beim Spieler, der das
Leg anwirft), riesiger Rest, schwarzes Schild mit den Punkten der letzten
Aufnahme, "Leg x / Match y" (Schnitt), Dart-Symbol mit der Zahl der Darts im
Leg, gewonnene Legs (Sets). Der Spieler am Zug hat den Verlauf Violett nach
Rot-Rosa, der Sieger Grün, alle anderen flaches Anthrazit.

Unten: Tabelle mit zwei Spalten (Punkte | Rest), getrennt durch eine dünne
Linie. Die Startzeile steht zuerst (Rest ohne Punkte), darunter die Aufnahmen
in zeitlicher Reihenfolge, die neueste mit hellem Schild um den Rest. Es passen
so viele Zeilen hinein, wie die Höhe zulässt (etwa neun); sind es mehr, bleiben
die neuesten sichtbar. Bust: rote 0 mit "BUST", Aufnahme ab 100 gelb, Checkout
mit Pokal und grünem Schild.

### Farben

Streifen oben #01040F; Grund Marineblau #001137 / #02153E / #001743 mit kaum
sichtbaren Dreiecken; Flächen #17181C, flach #181A1E; Trennlinie #505158;
Verlauf #802E90, #A6266F, #D63756; Schilder #2C2C37 / #292E37; Blau #0955DF,
Schalterleiste #002E8B; Namensschild #04050C; helles Schild #FCFBFC. Wiederverwendete
Widgets (Ergebnis, Doppel-Zoom, Tastenfeld) laufen in der Arena unter einem
dunklen Theme mit blauem Akzent (`ArenaPalette.theme`).

### Mehrere Spieler und Solo

- Ab drei Spieler teilen sich die Seiten die Tafeln, übereinander und etwas
  kompakter (links die erste Hälfte, rechts der Rest).
- Solo: nur die linke Tafel; die rechte Seite bleibt bewusst leer.
- Doppel-Zoom: auf dem Rechner in der freien Fläche unter der rechten Tafel, am
  Telefon als flacher Streifen über dem Board (nur wenn er ein Ziel zeigt).
- Nach Ende von Leg und Match erscheint das Ergebnis in der Mitte statt Board
  und Wurfleiste; die Tafeln bleiben stehen.

### Telefon und Hochformat

Unter 640 px Breite oder flacher als 5:4: Kopfzeile, Wurfleiste, die Tafeln
nebeneinander (je Spieler gleich breit, kompakter oberer Teil, Tabelle darunter),
dann das Board und darunter die Schalterleiste und der Hinweis. Was nicht in
die Höhe passt, wird kleiner gezeichnet; reicht auch das nicht (Telefon quer),
scrollt die Seite. Manuelle Eingabe zeigt das Tastenfeld statt der Schalterleiste.

Screenshots der Entwürfe liegen unter `screens/entwurf-spielansicht-arena/`.

### Dialoge und Blätter

`showDialog` und `showModalBottomSheet` übernehmen das Theme des Kontexts, mit
dem sie aufgerufen werden. Die Arena-Spielansichten (Match, X01-Solo, Autodarts
Live) legen deshalb `Theme(ArenaPalette.theme)` **über** das `Scaffold` und
rufen Dialoge und Blätter mit dem Kontext darunter (`Builder`) auf. Sonst waren
Verlassen-Dialog und Dart-Korrektur in einem hellen Look (Clean hell) weiß auf
dem dunklen Spielfeld. `test/widgets/arena_test.dart` prüft das im hellen Look.
Auf dem Telefon fehlt in der alten Kopfzeile der Vollbild-Knopf, und der
Spieltitel schrumpft, statt abgeschnitten zu werden.

### Autodarts Live in der Arena

Code: `lib/features/autodarts_live/presentation/arena_live_view.dart`. Gilt für
`autodarts_live` und `x01_live`, sobald `settings.arenaPlay` wahr ist und die
Session läuft (oder beendet ist). Mit „Wie das gewählte Design“ und einem
anderen Look bleibt die bisherige Live-Seite (mit Navigation) unverändert.

* Gleiche Maße wie das Match: Kopfzeile, Wurfleiste, Board in der Mitte, links
  **eine** Tafel. Einen Gegner erfindet die Ansicht nicht: Autodarts meldet
  nur die eigenen Darts (siehe [autodarts-live.md](autodarts-live.md)).
* **Wurfleiste:** die drei Darts der laufenden Aufnahme. Antippen öffnet das
  Korrekturblatt, das „+“ im ersten freien Feld fügt einen Dart hinzu, ein
  Stift markiert von Hand gesetzte oder geänderte Darts. Nach dem Takeout steht
  ohne X01 die letzte Aufnahme gedämpft in der Leiste.
* **Tafel mit „X01 mitzählen“:** große Zahl = Rest, Schild = Punkte der
  Aufnahme, darunter Leg-Durchschnitt, Darts im Leg und gewonnene Legs. Die
  Tabelle zeigt Punkte | Rest je Aufnahme des laufenden Legs (Bust rot mit
  Hinweis, Checkout hell). Nach einem Checkout bleibt das gewonnene Leg
  stehen, bis die nächste Aufnahme beginnt (`LiveX01.legRows`).
* **Tafel ohne X01:** große Zahl = Ø der Session (3-Dart-Durchschnitt der
  rohen Darts), Tabelle Punkte | laufender Ø nach jeder Aufnahme.
* **Board:** die echten Positionen der Darts der laufenden Aufnahme; die
  Heatmap der Session lässt sich zuschalten.
* **Schalterleiste:** „Leg verloren“ (nur X01), „Beenden“, Korrekturen
  (letzte Aufnahmen), Heatmap, „Leg neu“ (nur X01). Es gibt kein Start, Stopp
  oder Zurücksetzen zum Board Manager: die Ansicht ist rein passiv.
* **Session:** breit in der rechten Spalte (X01-Schalter und Einstellungen,
  Statistik, Treffer nach Feld, letzte Aufnahmen, Hinweise); auf dem Telefon
  hinter dem Symbol oben rechts in einem Blatt. Die Kennzahlen darin gelten
  für die ganze Session, nicht nur für das Leg.
* Während die Arena-Live-Ansicht offen ist, blendet `AdaptiveScaffold` Seiten-
  und Navigationsleiste aus (wie Match und Solo); „Verlassen“ geht zurück zur
  Spielauswahl.
* Nach „Beenden“ steht statt Board und Wurfleiste die Zusammenfassung der
  gespeicherten Session in der Mitte.

Bausteine: `ArenaDartSlot` (`edited`, `addHint`), `ArenaPlayer` (`heroText`,
`caption`, `scoreRows`, `scoreHeaders`, `stats`) und `ArenaScreen.sidePanel`
für die rechte Spalte neben einer einzelnen Tafel.

Screenshots der Entwürfe liegen unter `screens/entwurf-arena-live/`.

# Spielansicht der Looks: Aufnahmen-Tabelle

Im Match und im X01-Solo steht unter dem Rest eine kleine Tabelle der **letzten Aufnahmen**
des laufenden Legs: links die Punkte der Aufnahme, rechts der Rest danach. Sie ersetzt die
frühere Kennzahl „Letzte“ (das ist jetzt die oberste Zeile).

## Aufbau der Tabelle

| Punkte | Rest |
| --- | --- |
| **10 ✓** (Checkout, grün) | **0** |
| **0 Bust** (rot) | 10 |
| 30 | 10 |
| 125 (gelb, ab 100) | 176 |
| Start | 301 |

* **Neueste Aufnahme oben**, sie ist hervorgehoben (Spieler am Zug in der Akzentfarbe des
  Looks, im Look TV neutral hell, weil Rot dort „am Zug“ und „Bust“ bedeutet). Ganz unten steht
  die **Startzeile** mit dem Startwert, sobald alle Aufnahmen des Legs mit ihr in die Tabelle
  passen; sonst fallen die ältesten Zeilen unten heraus.
* **Bust**: die Punkte stehen als rote 0 mit kleiner „Bust“-Marke, der Rest bleibt auf dem Stand
  vor der Aufnahme. Bei drei Spielern auf dem Telefon entfällt die Marke (zu schmal); die rote 0
  und die rote Zeile bleiben.
* **Checkout**: grüne Zeile mit Pokal, Rest 0. Nach einem gewonnenen Leg bleibt das Leg in der
  Tabelle stehen, bis der erste Dart des nächsten Legs fällt – so ist das Finish noch zu sehen,
  obwohl die Tafeln schon wieder beim Startwert stehen.
* **100+** (100, 140, 180 …) stehen in der Farbe `record`.
* Eine noch laufende Aufnahme steht **nicht** in der Tabelle (ihre Darts stehen auf der
  Aufnahme-Karte); sie erscheint, sobald sie abgeschlossen ist (drei Darts, Bust, Checkout oder
  Takeout/„Weiter“).
* Die **Höhe ist fest** (Kopfzeile plus 4 bis 8 Zeilen, je nach Breite und Spielerzahl), damit
  Board und Darts nicht springen, wenn Aufnahmen dazukommen. Es gibt kein Scrollen in der Tabelle.

## Match

Jede Spielerkarte der Anzeigetafel trägt ihre eigene Tabelle (Schlüssel `match-visits-<Spieler>`,
Zeilen `match-visits-<Spieler>-row-<Aufnahme>`, Startzeile `match-visits-<Spieler>-start`;
`<Aufnahme>` ist die laufende Nummer der Aufnahme im Match, ab 0). Die Karten sind gleich hoch,
Kennzahlen und Tabellen sitzen am unteren Rand und stehen nebeneinander auf einer Höhe.

| Breite | Layout |
| --- | --- |
| Telefon (< 900) | Anzeigetafel mit den Tabellen oben (5 Zeilen, bei 3+ Spielern 4 und engere Karte), darunter Aufnahme-Karte, Board, Knöpfe. Die Kennzahlen (Legs, Avg, Darts) stehen in einer Zeile. |
| Breit (≥ 900) | Board links, rechts ein 500 px breites Panel mit der Anzeigetafel (7 Zeilen, bei 3+ Spielern 6, unter 1000 px Höhe 5), Aufnahme-Karte und Doppel-Zoom; das Panel scrollt (bei 900 px Höhe ist der Doppel-Zoom nur zur Hälfte sichtbar), **Rückgängig / Weiter / Korrigieren** stehen fest am unteren Rand der Seitenleiste (nicht beim Tastenfeld der manuellen Eingabe). Nach dem Match zeigt das Panel statt der Tabellen die Ergebnis-Karte, damit **Fertig** und **Revanche** ohne Scrollen sichtbar bleiben (auf dem Telefon bleiben die Tabellen stehen). |

## X01-Solo

Nur X01 (`x01`) bekommt die Tabelle; alle anderen Trainingsspiele sehen aus wie vorher. Der
Stand-Panel hat **eine** Tabelle (Schlüssel `solo-visits…`, Zeilen
`solo-visits-row-<Aufnahme>`) mit einer zusätzlichen Spalte **Darts**: die einzelnen Felder der
Aufnahme („T20 · S5 · S1“), Double und Triple in ihrer Farbe. Telefon 6 Zeilen, breit 8 (unter 1000 px Höhe 5 und kleinere Zahl); auch im Solo stehen die Knöpfe breit fest unten. Bei
mehreren Legs beginnt die Tabelle mit jedem Leg neu; nach dem Spiel bleibt das letzte Leg stehen.

## Woher die Zeilen kommen

Es gibt keinen eigenen Zustand. `VisitHistory` (`lib/features/matches/domain/visit_history.dart`)
leitet die Zeilen bei jedem Neuzeichnen aus den Dart-Aufzeichnungen ab:

* Match: `MatchSession.records` (`MatchDartRecord`), Solo: `GameSession.records` (`DartRecord`).
* Die **Regeln stecken allein in den Engines.** Sie melden pro Dart den Rest danach und ob der
  Dart ein Bust war (`MatchDartOutcome.remaining/bust`, `X01DartInfo` über
  `TrainingGame.lastDartInfo`). `VisitHistory` zieht nur die Punkte einer Aufnahme aus Rest
  davor und danach ab (Bust = 0, Double-In vor dem ersten Double = 0) und rechnet nichts nach.
* **Rückgängig und Korrekturen** bauen die Aufzeichnungen neu auf, die Tabelle folgt von selbst.
* **Legwechsel**: Aufnahmen tragen ihre Leg-Nummer, gezeigt wird das Leg des letzten gezählten
  Darts (`VisitHistory.currentLeg`).
* Ignorierte Darts (nach Bust oder Checkout) erscheinen nicht.

Die Komponente `VisitTable` (`lib/core/design/components/visit_table.dart`) zeichnet die Zeilen
und sieht in jedem Look anders aus: TV flach mit Farbbalken links, Clean mit runden Flächen,
Lab mit feinen Linien und Ziffern mit durchgestrichener Null.

## Live-Ansicht

Die Autodarts-Live-Ansicht (`autodarts_live`) zeigt in den Looks ihre eigene, bearbeitbare Liste der
letzten Aufnahmen mit den einzelnen Darts. Sie bleibt, wie sie ist; die Tabelle gibt es dort nicht.
In der Arena-Spielansicht hat sie dagegen eine eigene Ansicht mit Tafel und Wurfleiste (siehe oben,
„Autodarts Live in der Arena“).
