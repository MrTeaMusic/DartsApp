# Statistiken, Ziele, Profile und Daten

## Statistik

Alle Werte gelten für das **aktive Profil** und den gewählten **Zeitraum** (7, 30, 90 Tage oder alles),
optional gefiltert auf ein Spiel. Grundlage sind abgeschlossene Sessions und ihre gezählten Darts;
Darts, die nach einem Bust oder Checkout noch fielen, zählen nicht. Die Berechnung steckt komplett im
`StatsCalculator` (reine Dart-Klasse ohne Datenbank, mit Unit-Tests).

Die Statistik hat zehn Reiter:

* **Überblick:** Serie und Ziele, Kennzahlen mit Vergleich zum Vorzeitraum, Darts pro Tag (bis 30
  Tage) bzw. pro Woche (90 Tage, alles), Trainingsmuster nach Wochentag und Tageszeit.
* **Online:** Matches aus Autodarts Live mit Legs, Verlauf je Woche und der Vergleich Training gegen
  Match (Average, First 9, Checkout, Doppel einzeln, Punkteverteilung). Siehe `docs/online-matches.md`.
* **Elo:** „Haus-Elo“ aus den Matches (Bot, Mitspieler, Turnier, Autodarts-Import): Elo mit Trend und
  Rekord, Verlauf, Gegner mit Haus-Rating, größte Siege und bitterste Niederlagen. Immer über alle
  Matches, ohne Spielfilter. Siehe `docs/haus-elo.md`.
* **Scoring:** 3-Dart-Average, First 9, Streuung, Punkteverteilung der Aufnahmen, Average-Verlauf,
  Triple-Quote je Zahl, Heatmap, Treffer je Zahl.
* **Doppel & Finish:** Checkout- und Double-Quote, stärkstes und schwächstes Double, „Doppel im
  Fokus“ (Streubild, Daneben-Richtung, Verlauf), Checkout gegen Training, Tipp, Quote je Double
  (D1–D20, Bull) mit Verlaufspfeilen, Checkout-Quote nach Rest. Siehe „Doppel im Detail“.
* **Streuung:** aus den Positionen (Autodarts, Simulator) je Zielfeld die mittlere Abweichung,
  Streuung (1-Sigma-Ellipse), Quote und ein Tipp, dazu die Tendenz insgesamt; Auswahl Training/Match.
  Siehe `docs/streuungs-analyse.md`.
* **Tempo:** Median der Zeit je Dart und je Aufnahme (nur Darts vom Board, mit Mindestmenge), Verlauf
  über 12 Wochen, Tempo gegen Punkte und Training/Match/Live. Siehe `docs/wurftempo.md`.
* **Spiele:** Verlauf jeder Kennzahl eines Spiels mit gleitendem Durchschnitt, Bestwert, letzter Wert,
  Durchschnitt der letzten fünf, Liste aller Spiele mit Trefferquote aufs Ziel.
* **Rekorde:** persönliche Rekorde und Bestwerte je Spiel mit Datum, immer über alle Zeiträume.
* **Erfolge:** freigeschaltete Erfolge (ohne Zeitraum).

### Kennzahlen

| Kennzahl | Berechnung |
|---|---|
| 3-Dart-Average | Punkte pro Dart × 3. T20-Training, Score-Ziel und Highscore-Jagd aus den Würfen; andere Spiele (z. B. X01) über ihre gemeldete Kennzahl `average`, gewichtet mit ihren Darts. Spiele wie Around the Clock zählen nicht, dort wirft man auf Felder statt auf Punkte. |
| First 9 | Durchschnitt der Kennzahl `first9` der Sessions, die sie melden (X01). |
| Checkout-Quote | geschaffte Versuche / alle Versuche aus dem Checkout-Training. 121 zählt nicht mit (siehe „121 zählt nicht zu normalen Finishes“). |
| Checkout-Quote nach Rest | dieselben Versuche (ohne 121), aufgeteilt nach Zielwert: 2–40, 41–60, 61–100, 101–130, 131–170 |
| Double-Quote | Treffer / Darts, bei denen genau ein Double (oder das Bullseye) das Ziel war, siehe „Ziel je Dart“. Gibt es keine solchen Darts, die Quote aus Bob's 27. |
| Triple-Quote | Treffer / Darts mit genau einem Triple als Ziel (T20-Training, Highscore-Jagd, Score-Ziel, Checkout-Wege über ein Triple). Ohne solche Darts die Quote aus dem T20-Training. |
| Trefferquote aufs Ziel | alle Darts, für die das Spiel ein Ziel vorgab, und wie viele davon im Ziel landeten |
| Trainingstage | Kalendertage mit mindestens einer Session |
| Sessions ohne Würfe | Das [Checkout-Quiz](checkout-quiz.md) speichert Sessions ohne Würfe. Sie zählen bei Sessions, Trainingstagen, Trainingszeit und Serie, aber nicht bei Darts, Average, Quoten und Heatmap. |
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

### Doppel im Detail

Grundlage sind die Darts mit genau einem Doppel als Ziel (siehe „Ziel je Dart“) im gewählten Zeitraum
und mit dem gewählten Spielfilter. Die Berechnung steckt in `DoubleStats` (`double_stats.dart`, reine
Dart-Klasse mit Unit-Tests), aufgerufen über `StatsCalculator.doubleStats`.

* **Doppel im Fokus:** Chips D1–D20 und Bull; vorausgewählt ist das meistgeworfene Doppel (bei
  Gleichstand ein Zahlen-Doppel vor dem Bull, dann das höhere). Darunter ein vergrößerter Ausschnitt
  der Scheibe wie beim Doppel-Zoom mit allen Darts aufs Doppel als Punkte: Treffer grün, Fehlwürfe
  grau. Punkte gibt es nur für Würfe mit Position (Simulator, Autodarts); der Hinweis darunter nennt,
  wie viele Darts das sind.
* **Daneben-Richtung** (nur aus dem getroffenen Feld, ohne Koordinaten): *außen* = neben der
  Scheibe, *innen* = Single oder Triple derselben Zahl (auch Bull), *seitlich* = eine andere Zahl.
  Beim Bull: *Single* = Single-Bull, *Zahlen* = ein Zahlenfeld, *außen* = neben der Scheibe. Die
  Anteile beziehen sich auf alle Darts aufs Doppel, Treffer und die drei Richtungen ergeben 100 %.
  Die häufigste Richtung steht im Satz darüber („D16: 41 % Treffer, daneben meist außen (32 %)“).
* **Verlauf:** je Doppel die letzten 30 Tage (heute eingeschlossen) gegen die 30 Tage davor,
  unabhängig vom gewählten Zeitraum. Pfeil nur, wenn beide Zeiträume mindestens fünf Versuche haben;
  unter zwei Prozentpunkten Unterschied gilt der Wert als gleich. Die Pfeile stehen auch im Raster
  „Doubles im Detail“.
* **Checkout gegen Training:** Checkout = Darts aufs vorgeschlagene Doppel in Checkout-Training und
  121 plus die Checkout-Darts aus X01 und Matches (Kennzahlen `checkoutDarts` und `legsWon`, denn
  Matches speichern nur die eigenen Darts, dort lässt sich kein Ziel je Dart nachbauen). Training =
  alle übrigen Darts aufs Doppel (Bob's 27, Doppel-Spiele, Around the Clock auf Doubles …).
* **Tipp:** das Doppel mit der besten Quote ab fünf Versuchen, sobald mindestens zwei Doppel so viele
  Versuche haben („Dein bestes Doppel ist D20 (52 %). Stell dich beim Stellen lieber darauf.“).

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
Scoring-Darts), beste First 9, höchste Aufnahme, höchstes Finish (Checkout-Training und die
Kennzahl `highestCheckout` anderer Spiele, aber nicht 121), meiste 180er in einer Session, meiste Darts an einem
Tag, längste Serie. Dazu der Bestwert der Hauptkennzahl je Spiel.

### 121 zählt nicht zu normalen Finishes

Beim Training „121“ hat jedes Ziel mehrere Aufnahmen (3, 6 oder 9 Darts); ein Finish dort ist kein
normales 3-Dart-Finish. Deshalb zählen Finishes aus 121 nicht zu:

* Rekord „Höchstes Finish“,
* Checkout-Quote und Checkout-Quote nach Rest (damit auch nicht zum Ziel „Checkout-Quote“ und zu den
  Checkout-Schwächen im Auto-Plan),
* den Erfolgen „Ton-Plus-Finish“, „Big Fish“, „Bull-Finish“ und „Checkout-Routine“.

Sie bleiben erhalten in der eigenen Wertung von 121 (höchstes Finish, Checkouts, Checkout-Quote, Verlauf und
Bestwert des Spiels, die Challenge „Leiter ab 121“) und in der Doppel-Statistik, denn dort wurde wirklich
aufs Doppel geworfen. Das gilt auch, wenn nur eine Aufnahme je Ziel eingestellt ist: 121 ist nie ein normales
Finish, unabhängig von der Einstellung. Alles wird aus den gespeicherten Sessions neu berechnet; bereits
angezeigte Werte ändern sich ohne Datenbankänderung. Die Liste der betroffenen Spiele steht in
`StatsCalculator.multiVisitFinishGames`.

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

## Spielverlauf

Unter **Statistik › Verlauf**, über „Verlauf“ bei „Zuletzt gespielt“ (Start und Training) oder durch
Antippen einer Session dort. Die Liste zeigt alle abgeschlossenen Sessions des aktiven Profils nach Tag,
neueste oben, filterbar nach Alle, Training und Matches (Bot-Matches und Online-Matches aus Autodarts
Live). Jede Zeile: Spiel, Uhrzeit, Darts, Dauer,
„abgebrochen“ und die Hauptkennzahl (siehe unten); fehlt sie (abgebrochen bei Kennzahlen, die nur vollständige
Spiele haben), stehen die geworfenen Darts. Bei Matches Gegner, Sieg oder Niederlage und die
Legs (eigene : verlorene).

Die **Detailansicht** einer Session zeigt:

* Kopf mit Spiel, Datum, Status, Dauer, Profil und Darts; bei Matches Format und Turnier.
* Kennzahlen wie im Ergebnis des Spiels. Dafür wird die Session aus Config, Startwert und Würfen noch
  einmal durchgespielt (wie bei „Ziel je Dart“); unbekannte Spiele zeigen die gespeicherten Kennzahlen.
* Diagramm je Aufnahme: Punkte (Scoring-Spiele, X01, Matches, mit Schnitt als gestrichelter Linie),
  Punktestand (z. B. Bob's 27), Marks (Cricket) oder Treffer aufs Ziel (z. B. Around the Clock).
  Checkout-Aufnahmen sind grün.
* Heatmap, wenn Würfe mit Position gespeichert sind (Simulator, Autodarts).
* Jede Aufnahme mit ihren Darts, dem Wert der Aufnahme und – bei Spielen mit Rest oder Punktestand – dem
  Stand danach. Der Wert sind Punkte bei Scoring-Spielen, X01 und Matches, Marks bei Cricket und Treffer
  aufs Ziel bei den übrigen Zielspielen (Around the Clock, Bob's 27 …).
  Bust steht rot, ein geschafftes Finish als Haken. **Darts aufs Finish** haben einen Rahmen: grün
  getroffen, rot verfehlt. Gemeint sind Darts, bei denen das Spiel genau ein Double (oder Bull) als Ziel
  vorgab, im Match Darts bei einem mit einem Dart checkbaren Rest (wie die Checkout-Quote). Darts, die
  nach Bust oder Checkout nicht mehr zählten, sind durchgestrichen.

**Matches:** Gespeichert sind nur die eigenen Würfe. Seit dem Spielverlauf enthält das Ergebnis eines
Matches zusätzlich die Kennzahlen aller Teilnehmer und je Leg Sieger, Checkout, Darts und die Aufnahme,
mit der es endete. Daraus zeigt die Detailansicht den Endstand, die Tabelle aller Teilnehmer und die
Aufnahmen je Leg mit Rest. Ältere Matches haben das nicht: Von den Gegnern stehen dann nur die Namen da;
wurden alle Legs selbst gewonnen, lassen sich die Legs trotzdem trennen, sonst stehen die Aufnahmen ohne
Rest und Bust in einer Liste.

**Löschen:** In der Detailansicht (Papierkorb oben oder „Session löschen“ unten), mit Rückfrage. Die
Würfe werden entfernt, die Session bleibt als Löschmarkierung (`deletedAt`) stehen, damit der
[Sync](sync.md) das Löschen an alle Geräte weitergibt. Statistik, Ziele, Tagesziel und Rekorde rechnen
sofort ohne sie. Bereits freigeschaltete Erfolge und Challenge-Bestwerte bleiben (sie werden beim
Freischalten gespeichert).

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

* **Backup (JSON):** alle Profile, Sessions, Würfe (mit Rohdaten), Ziele und eigenen
  [Trainingspläne](trainingsplaene.md), dazu gelöschte Sessions als Markierung (`deletedSessions`).
  Format `{"format": "dartlab-backup", "version": 5, …}`, dasselbe Datenformat wie beim
  [Sync zwischen Geräten](sync.md).
* **Import:** führt ein Backup mit den vorhandenen Daten zusammen, nach denselben Regeln wie der
  Sync. Sessions mit bekannter ID werden übersprungen, außer die Datei hat einen neueren Stand
  (`updatedAt`, z. B. eine weitergewachsene Live-Session); ein zweiter Import derselben Datei ändert
  also nichts. Das Feld `updatedAt` ist optional, Dateien ohne es und ältere App-Versionen
  funktionieren weiter. Backups der Version 2 (ohne Trainingspläne) und 1 (ohne IDs) lassen sich weiter
  importieren. Bei Version 1 werden Profile über den Namen zugeordnet, Sessions mit gleichem
  Profil, Spiel, Startzeit und Seed gelten als vorhanden.
* **Würfe als CSV / Sessions als CSV:** Komma-getrennt, UTF-8 mit BOM, Dezimalpunkt, Zeiten im
  ISO-Format. Die Sessions-Tabelle hat eine Spalte je Kennzahl.
