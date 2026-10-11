# Statistiken, Ziele, Profile und Daten

## Statistik

Alle Werte gelten für das **aktive Profil** und den gewählten **Zeitraum** (7, 30, 90 Tage oder alles),
optional gefiltert auf ein Spiel. Grundlage sind abgeschlossene Sessions und ihre gezählten Darts;
Darts, die nach einem Bust oder Checkout noch fielen, zählen nicht. Die Berechnung steckt komplett im
`StatsCalculator` (reine Dart-Klasse ohne Datenbank, mit Unit-Tests).

Die Statistik hat fünf Reiter:

* **Überblick:** Serie und Ziele, Kennzahlen mit Vergleich zum Vorzeitraum, Darts pro Tag (bis 30
  Tage) bzw. pro Woche (90 Tage, alles), Trainingsmuster nach Wochentag und Tageszeit.
* **Scoring:** 3-Dart-Average, First 9, Streuung, Punkteverteilung der Aufnahmen, Average-Verlauf,
  Triple-Quote je Zahl, Heatmap, Treffer je Zahl.
* **Doppel & Finish:** Checkout- und Double-Quote, Quote je Double (D1–D20, Bull) mit stärkstem und
  schwächstem Double, Checkout-Quote nach Rest.
* **Spiele:** Verlauf jeder Kennzahl eines Spiels mit gleitendem Durchschnitt, Bestwert, letzter Wert,
  Durchschnitt der letzten fünf, Liste aller Spiele mit Trefferquote aufs Ziel.
* **Rekorde:** persönliche Rekorde und Bestwerte je Spiel mit Datum, immer über alle Zeiträume.

### Kennzahlen

| Kennzahl | Berechnung |
|---|---|
| 3-Dart-Average | Punkte pro Dart × 3. T20-Training, Score-Ziel und Highscore-Jagd aus den Würfen; andere Spiele (z. B. X01) über ihre gemeldete Kennzahl `average`, gewichtet mit ihren Darts. Spiele wie Around the Clock zählen nicht, dort wirft man auf Felder statt auf Punkte. |
| First 9 | Durchschnitt der Kennzahl `first9` der Sessions, die sie melden (X01). |
| Checkout-Quote | geschaffte Versuche / alle Versuche aus Checkout-Training und 121 |
| Checkout-Quote nach Rest | dieselben Versuche, aufgeteilt nach Zielwert: 2–40, 41–60, 61–100, 101–130, 131–170 |
| Double-Quote | Treffer / Darts, bei denen genau ein Double (oder das Bullseye) das Ziel war, siehe „Ziel je Dart“. Gibt es keine solchen Darts, die Quote aus Bob's 27. |
| Triple-Quote | Treffer / Darts mit genau einem Triple als Ziel (T20-Training, Highscore-Jagd, Score-Ziel, Checkout-Wege über ein Triple). Ohne solche Darts die Quote aus dem T20-Training. |
| Trefferquote aufs Ziel | alle Darts, für die das Spiel ein Ziel vorgab, und wie viele davon im Ziel landeten |
| Trainingstage | Kalendertage mit mindestens einer Session |
| Trainingszeit | Summe von Start bis Ende jeder Session, höchstens drei Stunden je Session |
| Serie | Tage am Stück mit Training. Sie läuft weiter, wenn gestern trainiert wurde und heute noch nicht. |
| Heatmap | Position jedes gezählten Darts. Ohne Koordinaten (manuelle Eingabe) liegt der Dart in der Mitte seines Feldes. |

**Vergleich mit dem Vorzeitraum:** Bei 7, 30 und 90 Tagen zeigen die Kennzahlen einen Pfeil mit der
Veränderung gegenüber den gleich vielen Tagen davor (Quoten in Prozentpunkten). Grün heißt besser,
rot schlechter; bei der Streuung ist weniger besser. Ohne Training im Vorzeitraum fehlt der Pfeil.

### Aufnahmen: Verteilung und Konstanz

Grundlage sind volle Aufnahmen (drei gezählte Darts) aus T20-Training, Score-Ziel, Highscore-Jagd und
X01-Spielen (Spiel-ID beginnt mit `x01`). Aufnahmen, die durch Bust, Checkout oder Takeout kürzer
waren, zählen nicht.

* Bereiche: unter 40, 40–59, 60–99, 100–139, 140–179, 180; dazu Anzahl und Anteil von 100+, 140+, 180.
* **Streuung:** Standardabweichung der Aufnahmen in Punkten. Je kleiner, desto konstanter.
* **Höchste Aufnahme:** höchste volle Aufnahme im Zeitraum.

### Ziel je Dart

Gespeichert ist zu jedem Dart nur, was getroffen wurde. Weil Spiele deterministisch aus Config,
Startwert und Würfen sind, spielt die Statistik jede Session noch einmal durch und merkt sich vor
jedem Dart die hervorgehobenen Ziele des Spiels. Dafür braucht es keine zusätzlichen Spalten.
Aufnahmen, die vor dem dritten Dart beendet wurden (Takeout, „Weiter“), erkennt sie am Sprung im
Aufnahme-Index.

* Genau ein Double als Ziel: Bob's 27, Around the Clock mit Ring „Double“, Checkout-Training und 121,
  wenn der Wegvorschlag mit einem Double beginnt. Daraus entstehen die Quoten je Double.
  Ohne Wegvorschlag (Option aus) gibt es dort kein Ziel.
* Genau ein Triple als Ziel: T20-Training, Score-Ziel, Highscore-Jagd, Around the Clock mit Ring
  „Triple“, Checkout-Wege über ein Triple.
* Mehrere Ziele (z. B. alle Felder einer Zahl in Around the Clock oder Cricket) zählen nur für die
  Trefferquote aufs Ziel.
* Unbekannte Spiele (nicht im Katalog) oder Sessions, die sich nicht abspielen lassen, liefern keine
  Ziele; alle anderen Kennzahlen funktionieren trotzdem.

Im Raster „Doubles im Detail“ ist ein Double grün, wenn seine Quote mindestens 15 % über der eigenen
Double-Quote liegt, rot bei mindestens 15 % darunter (ab drei Versuchen). Stärkstes und schwächstes
Double zählen ab fünf Versuchen; im Triple-Diagramm erscheinen Zahlen ab drei Versuchen.

### Trainingsmuster

Sessions, Darts und 3-Dart-Average je Wochentag und Tageszeit, jeweils nach Session-Beginn:
Morgen 5–12 Uhr, Nachmittag 12–17 Uhr, Abend 17–22 Uhr, Nacht 22–5 Uhr. Die Tageszeit mit dem
besten Average wird hervorgehoben, sobald es in mindestens zwei Tageszeiten Scoring-Darts gibt.

### Verläufe

* **3-Dart-Average pro Trainingstag:** alle Scoring-Darts eines Tages zusammen.
* **Spiele:** jede Kennzahl, die ein Spiel meldet, je Session. Die Hauptkennzahl ist vorausgewählt.
* Die orange Linie ist der gleitende Durchschnitt der letzten fünf Werte; sie erscheint ab drei Werten.

### Rekorde

Über alle Daten des aktiven Profils, jeweils mit Datum: bester Average einer Session (ab 9
Scoring-Darts), beste First 9, höchste Aufnahme, höchstes Finish (Checkout-Training, 121 und die
Kennzahl `highestCheckout` anderer Spiele), meiste 180er in einer Session, meiste Darts an einem
Tag, längste Serie. Dazu der Bestwert der Hauptkennzahl je Spiel.

### Hauptkennzahl je Spiel

Für Verlauf und Bestwert:

| Spiel | Kennzahl |
|---|---|
| Checkout-Training | Checkout-Quote |
| Around the Clock, Drei-Treffer-Runde | benötigte Darts (weniger ist besser, nur vollständige Spiele) |
| Bullseye-Drill | Bullseye-Quote |
| T20-Training, Highscore-Jagd | 3-Dart-Average |
| Score-Ziel | Erfolgsquote |
| Cricket | Marks pro Aufnahme |
| 121 | höchstes Finish |
| Bob's 27 | Endstand |
| Around the World mit Überspringen | Punkte |
| Spiele ohne Eintrag (z. B. X01) | `average`, falls das Spiel ihn meldet; sonst gibt es keinen Bestwert |

## Ziele

Pro Art gibt es ein Ziel je Profil. Antippen ändert oder löscht es.

* Sessions pro Woche, Darts pro Woche (Montag bis Sonntag)
* Tage am Stück (aktuelle Serie)
* 3-Dart-Average, Checkout-Quote, Double-Quote (jeweils letzte 30 Tage, berechnet wie in der Statistik)

## Profile

Unter Optionen › Profile. Jedes Spiel wird dem aktiven Profil zugeordnet, Statistik, Ziele und
„Zuletzt gespielt“ zeigen nur dessen Daten. Löschen entfernt alle Sessions, Würfe und Ziele des
Profils; das letzte Profil lässt sich nicht löschen.

## Export und Import

Unter Optionen › Daten. Auf Windows und macOS öffnet sich ein Speichern-Dialog. Auf iOS landen die
Dateien im Dokumente-Ordner der App (Dateien-App › Auf meinem iPhone › DartLab).

* **Backup (JSON):** alle Profile, Sessions, Würfe (mit Rohdaten) und Ziele. Format
  `{"format": "dartlab-backup", "version": 2, …}`, dasselbe Datenformat wie beim
  [Sync im Heimnetz](sync.md).
* **Import:** führt ein Backup mit den vorhandenen Daten zusammen, nach denselben Regeln wie der
  Sync. Sessions mit bekannter ID werden übersprungen, ein zweiter Import derselben Datei ändert
  also nichts. Backups der Version 1 (ohne IDs) lassen sich weiter importieren: Profile werden dann
  über den Namen zugeordnet, Sessions mit gleichem Profil, Spiel, Startzeit und Seed gelten als
  vorhanden.
* **Würfe als CSV / Sessions als CSV:** Komma-getrennt, UTF-8 mit BOM, Dezimalpunkt, Zeiten im
  ISO-Format. Die Sessions-Tabelle hat eine Spalte je Kennzahl.
