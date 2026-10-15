# Streuungs-Analyse

Der Reiter **Statistik → Streuung** zeigt aus den Positionen der Darts, wohin man je Zielfeld
verzieht („bei T20 eher links unten“), wie stark es streut und gibt dazu einen vorsichtigen Tipp.
Die Berechnung steckt in `lib/features/stats/domain/scatter_stats.dart` (reine Dart-Funktionen mit
Unit-Tests) und im `StatsCalculator` (`scatterOf`, `scatterReport`), die Oberfläche in
`lib/features/stats/presentation/scatter_tab.dart`.

## Welche Darts zählen

* Nur Darts **mit Position**: von Autodarts (lokal oder Autodarts Live) und aus dem Simulator.
  Manuell eingegebene Darts (`source = manual`) zählen nie, auch wenn eine Position gespeichert wäre.
* Nur **gezählte** Darts (nicht die nach Bust oder Checkout) aus abgeschlossenen Sessions.
* Zeitraum und Spielfilter oben in der Statistik gelten wie in den anderen Reitern. Dazu wählt man im
  Reiter **Alle Darts**, **Training** oder **Matches** (Bot-/Mensch-Matches und Online-Matches).
* Koordinaten: normiert, Mitte (0, 0), Radius 1 = Außenkante Double-Ring (170 mm), y zeigt zur 20,
  x nach rechts. Simulator und Bots erzeugen dieselbe Konvention (`BoardGeometry`); bei Autodarts ist
  sie mit sechs echten Darts bestätigt (siehe `docs/autodarts-protokoll.md`).

## Ziel je Dart

Die Datenbank speichert nicht, wohin gezielt wurde. Das Ziel wird deshalb hergeleitet:

| Quelle | Ziel | Badge |
|---|---|---|
| Trainingsspiel, das in dem Moment **genau ein Feld** vorgab (T20-Training, Bob's 27, Checkout-Training, Doppel-Spiele, X01-Solo mit einem Doppel als Finish …) | dieses Feld; das Spiel wird mit seinen Würfen nachgespielt (`replayTargets`, wie bei der Double-Quote) | **exakt** |
| Spiel gibt „25 oder 50“ vor (Bull-Training, Around the Clock auf Bull, Cricket-Bull) | Bull | **exakt** |
| Spiel gibt mehrere Felder vor (Cricket, Shanghai, Halve-It …) | T20, T19 oder Bull nur, wenn das Feld zu den Zielen gehört und der Dart im Bereich unten liegt | geschätzt |
| Spiel gibt nichts vor (X01-Solo über 170 oder ohne Weg) | T20, T19 oder Bull nach Bereich | geschätzt |
| Match gegen Bot/Mensch | Rest wird mit Bust-Regel und Leg-Enden nachgerechnet: Ist der Weg für die restlichen Darts genau ein Doppel, galt der Dart diesem Doppel; ab Rest 100 ist er ein Scoring-Dart (T20/T19 nach Bereich) | geschätzt |
| Online-Match mit „X01 mitzählen“ | wie Match, nachgespielt mit `LiveX01.replay` (inkl. Leg-Markierungen) | geschätzt |
| Online-Match ohne X01 | T20, T19 oder Bull nach Bereich | geschätzt |

Singles als einziges Ziel (z. B. „S20“ beim Stellen) zählen nicht: Ob innen oder außen gezielt wurde,
ist offen, ein Mittelpunkt wäre geraten.

**Bereiche für die Schätzung** (nach Position, nicht nach getroffenem Feld):

* **Bull:** höchstens 32 mm von der Mitte.
* **T20:** Sektoren 20, 1 oder 5, zwischen 45 mm und 187 mm von der Mitte.
* **T19:** Sektoren 19, 7 oder 3, ebenso.
* Zwischen 32 und 45 mm ist unklar, ob der Dart dem Bull oder dem Triple galt: zählt nicht.

**Ausreißer:** Darts weiter als 100 mm vom Feldmittelpunkt zählen nicht (Abpraller, falsches Ziel).

**Was „geschätzt“ bedeutet:** Das Ziel wurde nicht angezeigt, sondern aus Lage und Spielstand
erschlossen. Das hat Grenzen:

* Bei T20/T19 fehlen Darts, die in die Nachbarsektoren außerhalb von 20/1/5 bzw. 19/7/3 gingen. Die
  seitliche Streuung wird dadurch eher unterschätzt, eine starke seitliche Tendenz eher abgeschwächt.
* Ein Dart aufs S20 (Stellen) im Match kann als T20 zählen, wenn er im Scoring-Bereich (Rest ≥ 100)
  fiel. Matches speichern nur die eigenen Würfe; die Leg-Enden kommen aus dem gespeicherten Ergebnis.
* Finish-Doppel im Match sind „vermutlich“: Wer bei Rest 32 auf D8 stellt, statt D16 zu werfen, wird
  falsch zugeordnet (selten, und dann meist weit genug weg, um als Ausreißer zu fallen).

**Exakt vor geschätzt:** Hat ein Feld mindestens 30 exakte Darts, zählen nur diese. Sonst werden
exakte und geschätzte Darts zusammen ausgewertet, und das Feld trägt das Badge „geschätzt“.

## Kennzahlen je Feld

Ein Feld erscheint ab **30 Darts** (`ScatterRules.minDarts`); darunter steht es unter „Noch zu wenig
Darts“ mit Fortschritt (z. B. „D16 (12/30)“).

* **Richtungen im Feld:** als stünde das Feld oben, wie in der Doppel-Ansicht. **Oben** = vom Bull weg
  entlang der Mittellinie, **unten** = Richtung Bull, **rechts** = im Uhrzeigersinn (zur nächsten
  Zahl), **links** = dagegen. Die Liste nennt die Nachbarzahl dazu („3 mm links (Richtung 5)“), weil
  „links“ bei Feldern unten auf der Scheibe an der Scheibe rechts ist. Beim **Bull** gelten die
  Richtungen der Scheibe, wie sie hängt.
* **Mittlere Abweichung** vom Feldmittelpunkt in mm, zerlegt in seitlich und Höhe.
* **Streuung:** Standardabweichung seitlich und in der Höhe (mm, Stichprobe). Auf der Scheibe als
  **1-Sigma-Ellipse** (große Achse aus der Kovarianz); sie enthält bei Normalverteilung rund 39 % der
  Darts.
* **Quote:** Anteil der Darts im Zielfeld; beim Bull zählen 25 und 50.
* **Richtung:** acht Richtungen oder **mittig**. Mittig heißt: Die Abweichung ist kleiner als das
  Größte aus 3 mm, einem Viertel der Streuung (je Achse gemittelt) und zwei Standardfehlern des
  Mittelwerts (Streuung / √n). So wird eine kleine Abweichung bei großer Streuung oder wenigen Darts
  nicht als Tendenz gemeldet.
* **Tendenz insgesamt:** Mittelwert der Abweichungen aller ausgewerteten Felder (in den Achsen der
  Felder, nach Darts gewichtet), mit derselben Mittig-Regel.

## Tipps

`scatterTips` (rein, mit Unit-Tests) liefert höchstens zwei Hinweise je Feld, wichtigster zuerst. Sie
sind bewusst als Hinweise formuliert („vielleicht“, „könnte helfen“): Eine Abweichung allein sagt nicht
sicher, woran es liegt.

| Muster | Hinweis |
|---|---|
| Streuung ≤ 9 mm und mittig | Mittig und eng gruppiert, so weitermachen. |
| Streuung ≤ 9 mm, aber daneben | Gruppierung gut: eher Zielpunkt oder Stand leicht verschieben. |
| Streuung ≥ 22 mm | Erst einen gleichmäßigen Ablauf festigen (steht dann vorn). |
| Zu tief, Feld oben (bis 45° neben der 20, und Bull) | Wurf vielleicht zu flach: Abwurfpunkt etwas höher / mehr Bogen. |
| Zu hoch, Feld oben | Vielleicht zu viel Kraft oder zu spät gelöst. |
| Zu tief/hoch, andere Felder | Landet eher Richtung Bull bzw. zu weit außen: Zielpunkt anpassen. |
| Seitlich daneben | Zieht Richtung der Nachbarzahl: Auge, Dart und Ellbogen auf einer Linie? |
| Eine Achse streut 1,35-mal so stark | An der Scheibe waagerecht: Ellbogen/Schulter ruhig; senkrecht: Abwurfpunkt und Tempo gleichmäßig. |
| Nichts davon | Im Mittel auf dem Feld: Gruppierung enger bekommen. |

„Zu tief/hoch“ und „seitlich“ gelten ab derselben Schwelle wie „mittig“; die größere Abweichung kommt
zuerst. Trajektorie-Hinweise („zu flach“) gibt es nur für Felder oben, weil nur dort „unten im Feld“
auch „unten an der Scheibe“ ist. Die Streuungsform wird in die Achsen der Scheibe übersetzt: Bei
seitlichen Feldern (D11, D6 …) ist „seitlich im Feld“ an der Scheibe senkrecht.

## Darstellung

* **Kennzahlen:** Tendenz insgesamt, Streuung (Ø je Achse), ausgewertete Felder, Darts mit Position.
* **Streubild je Feld:** ganze Scheibe, maßstabsgetreu, je Feld Ellipse, Kreuz im Feldmittelpunkt
  und Linie zur mittleren Position; gewähltes Feld gelb, geschätzte Felder gestrichelt.
* **Feld im Fokus:** Ausschnitt mit dem Feld oben (Doppel-Zoom), bis zu 300 neueste Darts als Punkte
  (Treffer grün), Ellipse, Abweichung, Streuung, Quote und Tipps. Auswahl über Chips oder die Liste.
* **Alle Felder:** je Feld Richtung, Abweichung, Streuung, Quote, Darts, Badge und erster Tipp.

Die Zeichnung auf der Scheibe ist eine ruhende `BoardDecoration` in der Ebene über der gerasterten
Scheibe: Sie wird nur neu gezeichnet, wenn sich Felder oder Auswahl ändern, nie je Frame. Die Darts
je Session werden im `StatsCalculator` zwischengespeichert und von einem neuen Rechner für
unveränderte Sessions übernommen; Sessions ohne Positionen werden gar nicht erst nachgespielt.

## Was noch nicht geprüft ist

* Echte Autodarts-Daten gab es bisher nur aus Tests mit einzelnen Feldern (sechs Darts, siehe
  `docs/autodarts-protokoll.md`). Die Auswertung ist mit Simulator- und Bot-Darts getestet.
* **Bull/25** am echten Board: Wie Autodarts Bull und Single Bull benennt (`bed`, `name`), ist noch
  nicht gesehen. DartLab liest Zahl 25 und Multiplikator; für die Streuung zählt die Position, für die
  Bull-Quote das gespeicherte Feld.
* Ob echte Koordinaten bei Darts am Draht oder bei Abprallern (`bouncer`) brauchbar sind, ist offen.
* Die Schwellen (30 Darts, 9/22 mm, 1,35, Bereiche der Schätzung) sind begründete Startwerte, nicht
  an echten Spielern kalibriert.
