# Weitere Trainingsspiele: Regeln, Optionen, Wertung

13 Spiele, die zu den Spielen aus [trainingsspiele.md](trainingsspiele.md) dazugekommen sind. Diese Seite
beschreibt sie so, wie sie gebaut sind (Code in `lib/features/games/domain/games/`, Tests in
`test/features/games/new_games_test.dart`). Abweichungen von der ursprünglichen Spezifikation stehen
jeweils unter **Umsetzung**.

Schreibweise der Testfälle: `|` trennt Aufnahmen (dort `game.endVisit()`), `MISS` ist daneben, `25` das
Single-Bull, `BULL` das Bullseye. Optionen in **fett** stehen im Setup-Screen. Wie überall gilt: Darts
nach einem vorzeitigen Aufnahme-Ende (Bust, Checkout, verpasstes Setup …) zählen nicht
(`closeVisit()` → `ignoredDarts`).

## Übersicht

| # | Spiel | id | Trainiert | Hauptkennzahl (Statistik) |
|---|---|---|---|---|
| 1 | X01-Solo (501 & Co.) | `x01` | alles, Match-Realität | `average` (höher besser) |
| 2 | Halve-It / Bermuda-Dreieck | `halve_it` | Zielwechsel, Druck | `score` |
| 3 | Catch 40 | `catch_40` | Finishes 61–100 | `points` (nur fertige Spiele) |
| 4 | JDC-Challenge | `jdc_challenge` | Shanghai + Doubles, Leistungstest | `score` (nur fertige Spiele) |
| 5 | Shanghai | `shanghai` | Single/Double/Triple einer Zahl | `score` |
| 6 | Darts-Golf | `golf` | Doubles, Risikoentscheidung | `averagePerHole` (niedriger besser) |
| 7 | 420 (Doppel-Countdown) | `doubles_420` | alle Doubles | `score` (niedriger besser, nur fertige) |
| 8 | Frustration (80 + Double) | `frustration` | Scoren, dann Double unter Druck | `visits` (niedriger besser, nur fertige) |
| 9 | Ziel-Wechsel (167) | `switch_drill` | Wechsel T20/T19/Bull pro Dart | `hitRate` |
| 10 | Doppel-Leiter | `doubles_ladder` | Doubles mit Rückfall | `highestLevel` |
| 11 | Genau 100 | `exact_score` | Punktekontrolle | `successRate` |
| 12 | Drei im Bett | `three_in_a_bed` | Gruppierung | `visits` (niedriger besser, nur fertige) |
| 13 | Stellen (Setup-Dart) | `setup_shot` | Rest auf Lieblings-Double stellen | `successRate` |


Die Hauptkennzahl steht in `PrimaryMetric.byGame` (`lib/features/stats/domain/game_metrics.dart`).
„Nur fertige“ heißt: abgebrochene Sessions (Metrik `completed` ≠ 1) zählen dort nicht.

### Bewusst nicht aufgenommen

* **Baseball, PAW, 180 Around the Clock:** eine Aufnahme pro Zahl, S/D/T = 1/2/3 Punkte. Das ist
  „Around the World mit Überspringen“ ohne Skip; besser als Option dort (`skipThreshold` = aus).
* **Count-Up:** entspricht der Highscore-Jagd mit 8 Aufnahmen.
* **Priestley Trebles (T10–T20):** entspricht Around the Clock mit Ring „Triple“; ggf. Option
  „Bereich von/bis“ dort ergänzen.
* **Checkout Challenge (Start 21, +10/−1), Finishing Pyramid:** decken 121 und Checkout-Training ab.
* **Neighbours, Bull 500, Master 501:** brauchen Auswahl-Dialoge mitten im Wurf, Extra-Darts oder
  einen virtuellen Gegner; passt nicht ohne Engine-Erweiterung.

## Engine-Ergänzungen

* **Neue `GameEventType`-Werte:** `shanghai` (Shanghai, JDC), `halved` (Halve-It), `levelDown`
  (Doppel-Leiter), `partComplete` (JDC), `legComplete` (X01). Texte in der arb (`evShanghai` …),
  Banner-Farbe in `eventTone` (`halved`/`levelDown` negativ, die anderen positiv).
* **Gemeinsame Finish-Regeln:** `games/checkout/checkout_rules.dart` mit `OutMode` (straight, double,
  master) und `CheckoutRules.isBust`, `isFinisher`, `suggest`, `isCheckout`. Checkout-Training, 121,
  X01 und Catch 40 nutzen dieselbe Bust-Prüfung; das Verhalten der alten Spiele ist unverändert.
* **Master-Out im `CheckoutCalculator`:** `suggest(..., masterOut: true)` erlaubt Triples als letzten Dart
  (Triple-Finish etwas teurer als ein Double). Double- und Straight-Out rechnen wie vorher.
* **Wurfvorschlag (`GameDisplay.suggestion`):** X01, Catch 40, Frustration (Double-Phase), Genau 100 und
  Stellen setzen ihn. Er wird bei jedem Abruf aus dem aktuellen Rest und den Darts berechnet, die in der
  laufenden Aufnahme noch übrig sind (`TrainingGame.dartsLeftInVisit`, nach einem vorzeitigen Ende 3),
  ändert sich also nach jedem Dart. Muster wie bei Checkout-Training und 121.
* **„Beliebiges Double/Triple“ als Ziel** (Halve-It): `targets` liefert alle 20 Doubles + Bullseye bzw.
  alle 20 Triples. Das Board hebt alle gleichzeitig hervor.
* **Ziel pro Dart** (JDC Teil 2, Ziel-Wechsel, Frustration, Stellen): das Spiel wechselt `targets` in
  `handleDart`; die Spielansicht baut `display`/`targets` nach jedem Dart neu.
* **Inneres vs. äußeres Single** (Golf): `Segment` unterscheidet `singleInner`/`singleOuter`. Manuelle
  Eingabe liefert immer `singleOuter`, deshalb ist bei Golf `simple` der Standard.
* **Spielspezifische Beschriftungen im Setup:** `optionLabel(key, gameId)` und
  `optionValue(value, key: …)` in `game_texts.dart`, weil z. B. `down` bei Halve-It „Abrunden“ heißt,
  bei 121 aber „Eins runter“.

---

## 1. X01-Solo

Datei `games/x01_solo.dart`, Klasse `X01Solo`, id `x01`.

### Regeln

* Start bei **Startwert**, jeder gezählte Dart zieht seine Punkte ab. Ziel ist 0.
* **In:** `straight` (jeder Dart zählt) oder `double` (Punkte zählen erst ab dem ersten Double oder
  Bullseye; dieser Dart zählt mit). Darts davor werden als geworfen gezählt, ziehen aber nichts ab.
* **Out:** `straight` (jeder Dart darf auf 0), `double` (letzter Dart Double oder Bullseye) oder
  `master` (Double, Triple oder Bullseye).
* **Bust:** Rest unter 0, Rest 1 (bei Double-/Master-Out; bei Master-Out ist Rest 1 ebenfalls Bust,
  weil kein Feld 1 als Master-Finish erlaubt) oder 0 mit unerlaubtem Dart. Der Rest springt auf den
  Stand vor der Aufnahme, die Aufnahme ist vorbei (`closeVisit()`), Event `bust`.
* Checkout: Event `checkout`, Leg vorbei, Aufnahme geschlossen. Das nächste Leg beginnt mit der
  nächsten Aufnahme wieder beim Startwert (und wieder „nicht eingestiegen“ bei Double-In).
* **Dart-Limit** (optional): Wird das Limit im Leg erreicht, ohne zu checken, ist das Leg verloren
  (Event `failed`) und das nächste beginnt.

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `startScore` | `IntChoiceOption` | 101, 170, 301, 501, 701, 1001 | 501 |
| `inMode` | `ChoiceOption` | straight, double | straight |
| `outMode` | `ChoiceOption` | straight, double, master | double |
| `legs` | `IntOption` | 1–20 | 1 |
| `dartLimit` | `IntOption` | 0–99, Schritt 3 (0 = aus) | 0 |
| `showSuggestion` | `BoolOption` | | true |

### Ende und Wertung

* Ende nach `legs` Legs (geschafft oder am Limit gescheitert).
* `metrics`: `darts`, `average` (Punkte ÷ Darts × 3; Bust-Aufnahmen zählen mit 0 Punkten, ihre
  gezählten Darts zählen mit), `first9Average` (Schnitt der ersten 9 gezählten Darts je Leg, gemittelt),
  `bestLegDarts`, `legsWon`, `highestFinish`, `checkoutDarts` (Darts, die bei einem Rest geworfen
  wurden, der mit einem Dart checkbar war: `CheckoutCalculator.isCheckout(rest, darts: 1, …)`),
  `checkoutRate` (`legsWon ÷ checkoutDarts`), `count100`, `count140`, `count180`, `busts`.
* `details`: `legs: [{darts, average, first9, checkout, won}]`.
* `display`: headline = Rest, `headlineKey: 'remaining'`, `suggestion` aus
  `CheckoutCalculator.suggest(rest, darts: 3 - visit.length, doubleOut: …)` (bei Master-Out bis zur
  Erweiterung des Calculators keinen Vorschlag zeigen), `progressLabel` „Leg 2/5“, stats: Average,
  Darts im Leg, bei Double-In vor dem Einstieg „Double zum Einstieg“.
* `targets`: bei Double-In vor dem Einstieg alle Doubles + Bullseye, sonst die Felder des Vorschlags,
  sonst leer.

### Sonderfälle

* Bust nach dem Double-In-Dart: Der Stand inklusive Einstiegs-Status springt auf den Stand vor der
  Aufnahme zurück. Wer in der Bust-Aufnahme eingestiegen ist, muss also erneut ein Double zum Einstieg werfen.
* Startwerte 101 und 170 dienen als schnelle Finish-Drills; der Average ist dort wenig aussagekräftig.

### Testfälle

1. 501, straight in, double out: `T20 T20 T20 | T20 T20 T20 | T20 T19 D12` → Checkout, 9 Darts,
   `average` 167.0, `finished`.
2. Bust über 0: Start 40 (Konstruktor), `T20` → Rest 40, Event `bust`, `visitClosed`; ein weiterer Dart
   erhöht `ignoredDarts`.
3. Rest 1: Start 41, `S20 S20` → Bust nach dem zweiten Dart, Rest 41.
4. Master-Out: Start 60, `T20` → Checkout. Gleiches mit Double-Out → Bust.
5. Double-In: 501, `S20 S20 D20` → Rest 461, `darts` 3.
6. Zwei Legs: nach Checkout in Leg 1 steht der Rest beim nächsten Dart wieder auf dem Startwert.
7. Dart-Limit 9 bei Start 501 ohne Checkout nach 9 Darts → Event `failed`, `legsWon` 0.

### Umsetzung

* Vor dem Double-In zeigt die große Anzeige den Rest mit der Beschriftung „Double zum Einstieg“
  (`headlineKey: 'doubleToStart'`) statt eines eigenen Stats; Stats: Average, Darts im Leg (bei Limit
  „7/30“), bei mehreren Legs „Legs gewonnen“.
* Master-Out hat einen Vorschlag (Calculator erweitert, siehe oben). Beim Dart-Limit rechnet der Vorschlag
  höchstens mit den Darts, die im Leg noch erlaubt sind.
* `highestFinish` ist der Rest zu Beginn der Checkout-Aufnahme. `count100`/`count140`/`count180` zählen
  getrennt: 100–139, 140–179, 180.
* Nach einem Checkout zeigt das Spiel sofort den Startwert des nächsten Legs; restliche Darts der
  Checkout-Aufnahme zählen nicht.
* Zusätzliche Metriken: `legs` (gespielte Legs), `completed`.

---

## 2. Halve-It / Bermuda-Dreieck

Datei `games/halve_it.dart`, Klasse `HalveIt`, id `halve_it`.

### Regeln

* Feste Folge von Runden-Zielen, **eine Aufnahme pro Runde**.
* Jeder Dart auf das Runden-Ziel zählt seinen normalen Wert (T20 = 60, D7 = 14, Bullseye = 50).
* **Trifft keiner der Darts** der Aufnahme das Ziel, wird der Gesamtstand halbiert (Event `halved`).
* Ziel-Arten: Zahl *n* (jedes Feld der *n*), „beliebiges Double“ (D1–D20 und Bullseye),
  „beliebiges Triple“, „Bull“ (25 und Bullseye), „Bullseye“ (nur 50).
* **Folge (Preset):**
  * `bermuda` (13 Runden): 12, 13, 14, beliebiges Double, 15, 16, 17, beliebiges Triple, 18, 19, 20,
    Bull, Bullseye.
  * `short` (9 Runden, eigene Zusammenstellung, weil die Quellen hier stark variieren): 20, 19,
    beliebiges Double, 18, 17, beliebiges Triple, 16, 15, Bull.

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `preset` | `ChoiceOption` | bermuda, short | bermuda |
| `rounding` | `ChoiceOption` | down, up | down |
| `startScore` | `IntOption` | 0–100, Schritt 10 | 0 |

### Ende und Wertung

* Ende nach der letzten Runde. Höherer Stand ist besser.
* `metrics`: `score`, `halvings`, `hits` (Darts aufs Ziel), `hitRate`, `bestRound`, `cleanRounds`
  (Runden ohne Halbierung).
* `details`: `rounds: [{target, points, halved}]`.
* `display`: headline = Stand (`points`), Ziel als Stat, `progressLabel` „5/13“.

### Sonderfälle

* Halbieren bei 0 bleibt 0. Ungerade Stände: `rounding`.
* Vorzeitiges Aufnahme-Ende ohne Treffer (Takeout nach 1 Dart) halbiert ebenfalls.
* In der Bull-Runde zählt 25 mit 25 und Bullseye mit 50 (eine Quelle wertet beide mit 25; wir bleiben
  bei den normalen Werten).

### Testfälle (bermuda)

1. `S12 S12 S12` → 36.
2. danach `MISS MISS MISS` (Ziel 13) → 18, Event `halved`.
3. danach `MISS MISS S14` → 32.
4. danach `D5 MISS MISS` (beliebiges Double) → 42; `T5` in dieser Runde zählt nicht.
5. `rounding: up`, Stand 37, leere Runde → 19; `down` → 18.

### Umsetzung

* Ziel-Kurznamen in der Anzeige: Zahl, `D` (beliebiges Double), `T` (beliebiges Triple), `25` (Bull),
  `BULL` (Bullseye). Stats: Ziel, Halbierungen, Trefferquote.

---

## 3. Catch 40

Datei `games/catch_40.dart`, Klasse `Catch40`, id `catch_40`.

### Regeln

* Ziele der Reihe nach von **von** bis **bis** (Standard 61 bis 100 = 40 Ziele), ein Versuch pro Ziel.
* Pro Ziel **Darts** (Standard 6 = 2 Aufnahmen). Ein Checkout beendet den Versuch sofort
  (`closeVisit()`), das nächste Ziel beginnt mit der nächsten Aufnahme.
* Bust und **Double-Out** wie beim Checkout-Training (Rest auf Stand vor der Aufnahme, Aufnahme vorbei).
* **Punkte pro Ziel:** Sei *m* = max(2, minimale Dartzahl für das Ziel laut `CheckoutCalculator`).
  Checkout mit ≤ *m* Darts = 3 Punkte, sonst mit ≤ 3 Darts = 2 Punkte, sonst geschafft = 1 Punkt,
  nicht geschafft = 0. Das bildet die Originalregel ab (2 Darts = 3, 3 Darts = 2, 4–6 = 1, Ausnahme
  99 in 3 Darts = 3, weil 99 kein 2-Dart-Finish ist).

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `min` | `IntOption` | 2–170 | 61 |
| `max` | `IntOption` | 2–170 | 100 |
| `dartsPerTarget` | `IntChoiceOption` | 3, 6, 9 | 6 |
| `doubleOut` | `BoolOption` | | true |
| `showSuggestion` | `BoolOption` | | true |

`normalize` wie beim Checkout-Training (min ≤ max). Nicht checkbare Werte (z. B. 169) werden übersprungen.

### Ende und Wertung

* Ende nach dem letzten Ziel. Maximum = 3 × Zahl der Ziele (Standard 120).
* `metrics`: `points`, `maxPoints`, `checkouts`, `checkoutRate`, `dartsPerCheckout`, `threePointers`.
* `details`: `targets: [{target, darts, points}]` (für eine spätere Heatmap „schwache Finishes“).
* `display`: headline = Rest, Stat „Ziel 73“, „Punkte 41/120“, Wurfvorschlag wie Checkout-Training.

### Testfälle

1. Ziel 61: `T15 D8` → Checkout mit 2 Darts, 3 Punkte, nächstes Ziel 62.
2. Ziel 61: `T20` → Rest 1, Bust, Rest 61.
3. Ziel 99: `T19 S10 D16` → 3 Punkte (Ausnahme).
4. Ziel 100: `T20 S20 D10` → 2 Punkte.
5. Ziel 61, 6 × `MISS` → 0 Punkte, nächstes Ziel 62.

### Umsetzung

* Stats: Ziel, „Punkte 41/120“, Darts für dieses Ziel. `dartsPerCheckout` nur, wenn es mindestens einen
  Checkout gab. Fehlversuche speichern als `darts` die volle Zahl der Darts pro Ziel.

---

## 4. JDC-Challenge

Datei `games/jdc_challenge.dart`, Klasse `JdcChallenge`, id `jdc_challenge`. Prüfungsroutine der
Junior Darts Corporation, 57 Darts in drei Teilen.

### Regeln

* **Teil 1, Shanghai 10–15:** je eine Aufnahme auf 10, 11, … 15. Jeder Treffer auf die Zahl zählt
  Zahl × Multiplikator. Single + Double + Triple der Zahl in derselben Aufnahme = **Shanghai,
  +100** (Event `shanghai`).
* **Teil 2, Doubles:** je **ein Dart** auf D1, D2, … D20, dann Bullseye. Treffer auf das aktuelle
  Double = 50 Punkte, Bullseye = 100. Das Ziel wechselt nach jedem Dart (auch innerhalb einer Aufnahme).
* **Teil 3, Shanghai 15–20:** wie Teil 1.
* Nach dem letzten Bullseye-Dart von Teil 2 wird die Aufnahme geschlossen, Teil 3 beginnt mit einer
  neuen Aufnahme. Event `partComplete` an jedem Teil-Ende.
* Vorzeitiges Aufnahme-Ende in Teil 1/3: Zahl ist vorbei. In Teil 2 gehen keine Doubles verloren
  (Ziel wechselt nur pro geworfenem Dart).

### Optionen

Keine (feste Prüfungsroutine). Optional später `parts` (alle / nur Teil 2) als `ChoiceOption`.

### Ende und Wertung

* Ende nach Teil 3. Theoretisches Maximum 3380 (Teil 1: 1050, Teil 2: 1100, Teil 3: 1230).
* `metrics`: `score`, `part1`, `part2`, `part3`, `shanghais`, `doubleHits`, `doubleRate` (Teil 2).
* Die JDC vergibt Noten (A–F, „Black“ ab 850). Die genauen Grenzen sind nicht verlässlich
  belegt; deshalb vorerst ohne Note.
* `display`: headline = Gesamtpunkte, Stats: Teil, Ziel, Teilpunkte; `progressLabel` „Dart 23/57“.

### Testfälle

1. `S10 D10 T10` → 60 + 100 = 160, Event `shanghai`, Ziel 11.
2. `T10 T10 T10` → 90, kein Shanghai.
3. Nach 6 Aufnahmen `MISS` ist das Ziel D1; `D1 D5 D3` → 100 (D5 auf Ziel D2 zählt nicht), Ziel D4.
4. Alle 21 Teil-2-Darts getroffen → `part2` 1100, danach Ziel 15 und neue Aufnahme.

### Umsetzung

* Endet Teil 2 mitten in einer Aufnahme (nach einem vorzeitigen Aufnahme-Ende in Teil 2), zählen die
  restlichen Darts dieser Aufnahme nicht; Teil 3 beginnt mit der nächsten Aufnahme.
* Noch ohne Noten. `progressLabel` zählt die Position in der Routine („Dart 23/57“).

---

## 5. Shanghai

Datei `games/shanghai.dart`, Klasse `Shanghai`, id `shanghai`.

### Regeln

* Zahlen von **von** bis **bis**, eine Aufnahme pro Zahl. Optional **Bull** am Ende.
* Treffer auf die aktuelle Zahl zählen Zahl × Multiplikator, alles andere 0.
* **Shanghai:** Single, Double und Triple der Zahl in derselben Aufnahme (Reihenfolge egal; inneres
  und äußeres Single zählen beide als Single). Event `shanghai`.
* **Shanghai beendet das Spiel** (an, klassisch: sofortiger Sieg) oder gibt **Bonus** und es geht weiter.
* Bull-Runde: 25 = 25, Bullseye = 50, kein Shanghai möglich.

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `from` | `IntOption` | 1–20 | 1 |
| `to` | `IntOption` | 1–20 | 7 |
| `includeBull` | `BoolOption` | | false |
| `shanghaiWins` | `BoolOption` | | true |
| `shanghaiBonus` | `IntOption` | 0–200, Schritt 50 | 100 |

### Ende und Wertung

* Ende nach der letzten Zahl oder beim Shanghai mit `shanghaiWins`.
* `metrics`: `score`, `shanghais`, `hits`, `hitRate`, `triples`, `completed`.
* `display`: headline = Punkte, Ziel als Stat, Fortschritt „3/7“.

### Testfälle

1. `S1 D1 T1` → 6 Punkte, Event `shanghai`, mit `shanghaiWins` `finished`.
2. Gleiches mit `shanghaiWins: false` → 106, Ziel 2.
3. `T2 T2 T2` auf Ziel 2 → 18, kein Shanghai.
4. `S1 T1 MISS` → 4, kein Shanghai.

### Umsetzung

* Shanghai mit `shanghaiWins` beendet das Spiel sofort, ohne Bonus (Testfall 1: 6 Punkte).

---

## 6. Darts-Golf

Datei `games/golf.dart`, Klasse `DartsGolf`, id `golf`.

### Regeln

* **Löcher** 9 oder 18; Loch *n* hat die Zahl *n* als Ziel. Eine Aufnahme pro Loch.
* Man darf **nach jedem Dart aufhören** („Weiter“ bzw. Takeout → `endVisit()`). Es zählt der **letzte**
  geworfene Dart (Option: der beste Dart der Aufnahme).
* Schläge pro Dart (Wertung `classic`): Double = 1, Triple = 2, inneres Single = 3, äußeres Single = 4,
  daneben oder andere Zahl = 5. Wertung `simple` (für Quellen ohne inner/outer, z. B. manuelle Eingabe):
  Double = 1, Triple = 3, Single = 4, sonst 5.
* Par = 3 pro Loch. Weniger Schläge sind besser.

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `holes` | `IntChoiceOption` | 9, 18 | 9 |
| `scoring` | `ChoiceOption` | classic, simple | simple |
| `counts` | `ChoiceOption` | last, best | last |

Standard `simple`, solange Simulator und manuelle Eingabe kein inneres Single liefern (prüfen; bei
Autodarts ist die Position bekannt).

### Ende und Wertung

* Ende nach dem letzten Loch.
* `metrics`: `strokes`, `par`, `toPar` (Schläge − Par), `holesInOne`, `averagePerHole`.
* `display`: headline = Loch-Ziel (z. B. „7“), Stats: Schläge, „+2“ zum Par, aktueller Lochwert
  (Wert des letzten Darts, damit man entscheiden kann, ob man aufhört).

### Testfälle (`classic`, `last`)

1. Loch 1: `D1 |` → 1.
2. Loch 2: `S2 T2 |` → 2.
3. Loch 3: `MISS MISS MISS` → 5. Summe 8, `toPar` −1.
4. `D4 MISS` auf Loch 4 mit `last` → 5, mit `best` → 1.
5. `S5` auf Loch 6 → 5 (falsche Zahl).

### Umsetzung

* `par` und `toPar` beziehen sich auf die gespielten Löcher (nach 3 Löchern Par 9). Am Board wird das
  Double des Lochs hervorgehoben. Nach dem Spiel zeigt die große Anzeige die Schläge.

---

## 7. 420 (Doppel-Countdown)

Datei `games/doubles_420.dart`, Klasse `Doubles420`, id `doubles_420`.

### Regeln

* Start bei der Summe aller Ziel-Doubles: D1–D20 = 420, mit **Bull** 470. Dann bedeutet 0
  „jedes Double genau einmal getroffen“.
* Eine Aufnahme pro Double. Jeder Treffer auf das aktuelle Double zieht seinen Wert ab
  (D7 = 14, Bullseye = 50). Kein Bust, Stand darf negativ werden. Nach jeder Aufnahme geht es weiter.

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `includeBull` | `BoolOption` | | false |
| `order` | `ChoiceOption` | ascending, descending, random | ascending |

### Ende und Wertung

* Ende nach dem letzten Double. Niedriger ist besser.
* `metrics`: `score`, `doubleHits`, `doubleRate`, `missedDoubles` (Doubles ohne Treffer).
* `details`: `hitsByNumber` wie bei Bob's 27 (gleiche Heatmap nutzbar).

### Testfälle

1. `D1 D1 MISS` → 416, Ziel D2.
2. `D2 D2 D2` → 408.
3. 20 Aufnahmen mit je einem Treffer → 0.

### Umsetzung

* Die große Anzeige ist der Rest („Rest 416“). `order: ascending` heißt im Setup „1 bis 20“.
* Testfall 2 gilt im Anschluss an Testfall 1: drei Treffer auf D2 ziehen 12 ab, 416 → 404 (in der
  ursprünglichen Spezifikation stand 408).

---

## 8. Frustration (80 + Double)

Datei `games/frustration.dart`, Klasse `Frustration`, id `frustration`.

### Regeln

* Ziele: D1 … D20, dann Bullseye (`full`), oder D20 abwärts bis D10 (`short`).
* Pro Aufnahme: Dart 1 + Dart 2 müssen zusammen mindestens **Setup-Minimum** (Standard 80) ergeben.
* Nicht geschafft: Aufnahme sofort vorbei (`closeVisit()` nach Dart 2), der dritte Dart zählt nicht.
* Geschafft: Dart 3 muss das aktuelle Double treffen (Bull-Ziel = nur Bullseye) → nächstes Ziel.
* Jede Aufnahme zählt als Versuch. Vorzeitiges Ende (Takeout nach 1–2 Darts) = Fehlversuch.

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `sequence` | `ChoiceOption` | full, short | full |
| `setupMin` | `IntOption` | 40–120, Schritt 10 | 80 |
| `maxVisits` | `IntOption` | 0–200, Schritt 10 (0 = unbegrenzt) | 0 |

### Ende und Wertung

* Ende nach dem letzten Ziel (oder `maxVisits`). Wertung: Aufnahmen (weniger ist besser, perfekt = 21).
* `metrics`: `visits`, `reached`, `setupRate` (Aufnahmen mit ≥ Minimum), `doubleRate` (Dart 3 getroffen
  ÷ Dart 3 geworfen), `completed`.
* `targets`: bei Dart 1 und 2 T20 (nur als Hilfe), bei Dart 3 das aktuelle Double.

### Testfälle

1. Ziel D1: `S20 T20 D1` → 80, Treffer, Ziel D2, `visits` 1.
2. Ziel D2: `T20 S19` → 79, Aufnahme vorbei; ein weiterer `D2` → `ignoredDarts` 1, Ziel bleibt D2.
3. Ziel D2: `T20 S20 D3` → kein Fortschritt.

### Umsetzung

* Große Anzeige: das aktuelle Double. Im Double-Dart zeigt `suggestion` das Double (Weg für den Rest =
  Wert des Doubles mit einem Dart). Banner nach Dart 2: geschafft / „Nur 79“.

---

## 9. Ziel-Wechsel (167)

Datei `games/switch_drill.dart`, Klasse `SwitchDrill`, id `switch_drill`.

### Regeln

* Pro Aufnahme ein festes Ziel je Dart-Position. Preset `167`: T20, T19, Bullseye.
  Weitere Presets: `trebles` (T20, T19, T18), `doubles` (D20, D16, D8), `scoring` (T20, T19, T20).
* Ein Treffer zählt nur im exakten Feld (Bull-Ziel = Bullseye). 1 Punkt pro Treffer.
* **Runden** = Aufnahmen. Bei vorzeitigem Ende gelten die nicht geworfenen Darts als Fehlwurf.

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `preset` | `ChoiceOption` | 167, trebles, doubles, scoring | 167 |
| `rounds` | `IntOption` | 1–30 | 10 |

### Ende und Wertung

* Ende nach `rounds`. Maximum = 3 × Runden.
* `metrics`: `hits`, `maxHits`, `hitRate`, `hitRateTarget0..2` (Quote pro Position), `perfectRounds`.
* `targets`: nur das Feld der nächsten Dart-Position (`visit.length`).

### Testfälle (167)

1. `T20 T19 BULL` → 3, `perfectRounds` 1.
2. `T19 T20 BULL` → 1.
3. `T20 25 MISS` → 1 (25 zählt nicht als Bullseye).

### Umsetzung

* Große Anzeige: das Feld der nächsten Dart-Position. Kein Wurfvorschlag (kein Finish).

---

## 10. Doppel-Leiter

Datei `games/doubles_ladder.dart`, Klasse `DoublesLadder`, id `doubles_ladder`
(„Doubles Snakes and Ladders“).

### Regeln

* Stufen D1 … D20, dann Bullseye (optional). Eine Aufnahme pro Versuch auf die aktuelle Stufe.
* Bewegung nach der Aufnahme, Schwierigkeit `pro` (Original): 3 Treffer = eine Stufe hoch,
  2 = bleiben, 1 = eine runter, 0 = zwei runter. Schwierigkeit `normal`: ≥ 2 Treffer = hoch,
  1 = bleiben, 0 = eine runter. Nie unter D1.
* Fertig, wenn über die letzte Stufe hinaus aufgestiegen wird.

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `difficulty` | `ChoiceOption` | normal, pro | normal |
| `includeBull` | `BoolOption` | | true |
| `maxVisits` | `IntOption` | 10–300, Schritt 10 | 100 |

`normal` als Standard, weil drei Doubles in einer Aufnahme für die meisten zu selten ist.

### Ende und Wertung

* Ende beim Aufstieg über die letzte Stufe oder nach `maxVisits`.
* `metrics`: `visits`, `highestLevel`, `doubleRate`, `completed`. Events `advanced` / `levelDown`.

### Testfälle (`pro`)

1. `D1 D1 D1` → Stufe D2.
2. `D2 MISS MISS` → zurück auf D1.
3. `MISS MISS MISS` auf D1 → bleibt D1.
4. `normal`: `D1 D1 MISS` → D2.

### Umsetzung

* `highestLevel` ist 1-basiert (D1 = 1, Bullseye = 21). `progressLabel` zählt Aufnahmen gegen `maxVisits`.

---

## 11. Genau 100

Datei `games/exact_score.dart`, Klasse `ExactScore`, id `exact_score` („Nine Dart Century“).

### Regeln

* Pro Versuch genau das **Ziel** (Standard 100) erreichen, mit höchstens **Aufnahmen** (Standard 3 = 9 Darts).
* Alle Treffer zählen ihren normalen Wert. Genau das Ziel = Erfolg, auch vor dem letzten Dart
  (Versuch sofort vorbei, `closeVisit()`).
* **Überworfen:** `fail` (Original: Versuch gescheitert) oder `bust` (Aufnahme zählt nicht, Stand
  zurück auf vor der Aufnahme, die Aufnahme ist trotzdem verbraucht).

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `target` | `IntChoiceOption` | 60, 100, 150, 200 | 100 |
| `visitsPerAttempt` | `IntChoiceOption` | 2, 3 | 3 |
| `overshoot` | `ChoiceOption` | fail, bust | fail |
| `attempts` | `IntOption` | 1–20 | 5 |

### Ende und Wertung

* Ende nach `attempts` Versuchen.
* `metrics`: `successes`, `successRate`, `averageDarts` (bei Erfolg), `averageGap` (Abstand zum Ziel
  bei Misserfolg).

### Testfälle

1. `T20 S20 S20` → Erfolg mit 3 Darts.
2. `T20 T20` → 120, mit `fail` gescheitert, nächster Versuch.
3. `T20 T20` mit `bust` → Stand 0, Aufnahme vorbei, noch 2 Aufnahmen.

### Umsetzung

* Große Anzeige: Rest bis zum Ziel. `suggestion` ist der Straight-Out-Weg für den Rest mit den Darts der
  Aufnahme (z. B. Rest 40 mit 2 Darts → D20).
* `averageGap`: beim Überwerfen mit `fail` der Überschuss, sonst der fehlende Rest nach der letzten Aufnahme.

---

## 12. Drei im Bett

Datei `games/three_in_a_bed.dart`, Klasse `ThreeInABed`, id `three_in_a_bed`.

### Regeln

* Zahlen der Reihe nach (1–20, optional Bull). Eine Zahl ist geschafft, wenn **alle drei Darts einer
  Aufnahme** auf ihr landen. Sonst bleibt sie für die nächste Aufnahme.
* Modus `wedge`: Single, Double, Triple der Zahl beliebig gemischt. Modus `segment` (streng): alle drei
  im selben Feld (`Segment.sameField`, inneres und äußeres Single gelten als gleich).
* Bull: `wedge` = 25 und Bullseye gemischt, `segment` = dreimal dasselbe.
* Aufnahmen mit weniger als 3 Darts (vorzeitiges Ende) zählen als Fehlversuch.
* Unterschied zur Drei-Treffer-Runde: Treffer sammeln sich hier **nicht** über mehrere Aufnahmen.

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `mode` | `ChoiceOption` | wedge, segment | wedge |
| `order` | `ChoiceOption` | ascending, clockwise, random | ascending |
| `includeBull` | `BoolOption` | | false |
| `maxVisits` | `IntOption` | 0–300, Schritt 10 (0 = unbegrenzt) | 0 |

### Ende und Wertung

* Ende nach der letzten Zahl oder `maxVisits`. Wertung: Aufnahmen (weniger ist besser, perfekt = 20).
* `metrics`: `visits`, `reached`, `successRate`, `completed`.

### Testfälle

1. `S1 S1 D1` → `wedge` geschafft (Ziel 2); `segment` nicht.
2. `S1 S1 |` → Fehlversuch.
3. `T1 T1 T1` → in beiden Modi geschafft.

### Umsetzung

* Kurze Aufnahmen und Nicht-Treffer erzeugen das Event `failed`, ein geschafftes Bett `advanced`.

---

## 13. Stellen (Setup-Dart)

Datei `games/setup_shot.dart`, Klasse `SetupShot`, id `setup_shot`. Eigene Idee: übt den Dart vor dem
Finish, also den Rest auf ein Lieblings-Double zu stellen.

### Regeln

* Jeder gezählte Dart ist eine eigene Aufgabe. Angezeigt wird ein Rest *R* (zufällig aus **von**–**bis**).
* Erfolg, wenn *R* − Dartwert in der **Rest-Liste** liegt. Der erste Eintrag der Liste ist das
  Ideal (Event `best`), jeder Listeneintrag ist ein Erfolg (Event `hit`), alles andere `failed`.
* Rest-Listen: `classic` = 40, 32, 16; `good` = 40, 32, 36, 24, 16, 20, 8; `anyDouble` = alle geraden
  Werte 2–40 und 50.
* Gestellt werden nur Reste, die (a) mit einem Dart auf einen Listenwert gestellt werden können und
  (b) **nicht** selbst mit einem Dart auscheckbar sind. Zufall nur über `random` (Replay-sicher).
* Nach jedem Dart neuer Rest, unabhängig von der Aufnahme.

### Optionen

| Schlüssel | Typ | Werte | Standard |
|---|---|---|---|
| `min` | `IntOption` | 41–170 | 41 |
| `max` | `IntOption` | 41–170 | 100 |
| `leaves` | `ChoiceOption` | classic, good, anyDouble | good |
| `darts` | `IntOption` | 3–90, Schritt 3 | 30 |
| `showSuggestion` | `BoolOption` | | true |

### Ende und Wertung

* Ende nach `darts` gezählten Darts.
* `metrics`: `successes`, `successRate`, `ideal` (Treffer auf den ersten Listenwert), `idealRate`.
* `display`: headline = *R*, `headlineKey: 'remaining'`, `suggestion` = der Dart, der *R* auf den
  bestmöglichen Listenwert bringt (bevorzugt Single, z. B. 57 → S17 → 40).
* `details`: `tasks: [{rest, dart, leave, success}]`.

### Testfälle

Rest über `game.current` lesen oder per Konstruktor-Parameter feste Reste vorgeben (wie `weakTargets`
beim Checkout-Training):

1. Rest 57, `classic`: `S17` → 40, Erfolg und Ideal.
2. Rest 57: `S20` → 37, kein Erfolg.
3. Rest 72: `T16` → 24, Erfolg bei `good`, kein Erfolg bei `classic`.
4. Pool-Test: bei `classic`, Bereich 41–100 enthält der Pool nie 50 oder Werte ≤ 40.

### Umsetzung

* Die Option `darts` heißt im Konstruktor `taskCount` (`darts` ist in `TrainingGame` die Liste der Darts).
  Für Tests gibt `fixedRests` die ersten Reste vor.
* Wurfvorschlag: für den ersten erreichbaren Listenwert der erste passende Dart in der Reihenfolge
  Single, Triple, Double, 25, Bullseye.

---

## Quellen

* Spielesammlung für Solo-Training: [dolfdarts.com/games?players=1](https://dolfdarts.com/games?players=1)
* [JDC Challenge](https://dolfdarts.com/games/jdc-challenge), [Catch 40](https://dolfdarts.com/games/catch-40),
  [Frustration](https://dolfdarts.com/games/frustration), [420](https://dolfdarts.com/games/420),
  [167](https://dolfdarts.com/games/167),
  [Doubles Snakes and Ladders](https://dolfdarts.com/games/doubles-snakes-and-ladders),
  [Nine Dart Century](https://dolfdarts.com/games/nine-dart-century),
  [Three in a Bed](https://dolfdarts.com/games/three-in-a-bed)
* [Bermuda Triangle (darthelp)](https://darthelp.com/games/how-to-play-bermuda-triangle-darts/),
  [Halve it (Wikipedia)](https://en.wikipedia.org/wiki/Halve_it)
* [Golf Darts (darthelp)](https://darthelp.com/games/how-to-play-golf-darts/),
  [Dart golf (Wikipedia)](https://en.wikipedia.org/wiki/Dart_golf)
