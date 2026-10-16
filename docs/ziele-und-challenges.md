# Tagesziel, Erfolge und Challenges

Drei Dinge, die zum Weitertrainieren motivieren sollen: ein Tagesziel mit
Serie, Erfolge mit Stufen und ein Challenge-Modus mit festen Aufgaben.
Alles läuft offline und wird für jedes Profil getrennt berechnet.

## Tagesziel

- Das Ziel gilt für jeden Tag. Standard sind **200 Darts**. Alternativ
  zählen **Minuten** (5–240, Standard 30) oder **Sessions** (1–20,
  Standard 3). Darts lassen sich von 30 bis 1500 in Zehnerschritten
  einstellen.
- Ändern lässt es sich in den Optionen (Abschnitt „Tagesziel“) und über
  das Regler-Symbol auf der Startseiten-Karte. Die Einstellung liegt in
  den App-Einstellungen (`goals.dailyUnit`, `goals.dailyAmount`).
- Was zählt:
  - **Darts**: gezählte Darts nach dem Zeitpunkt des Wurfs.
  - **Minuten**: Dauer der Sessions, die an dem Tag begonnen haben, je
    Session höchstens drei Stunden.
  - **Sessions**: abgeschlossene Sessions, die an dem Tag begonnen haben.
- Die Startseite zeigt einen Ring „Heute 120 / 200 Darts“. Füllt sich der
  Ring während eines Spiels, erscheint unten eine kurze Einblendung. Sie
  kommt einmal pro Tag.
- Ändert man das Ziel, wird die Vergangenheit mit dem neuen Ziel
  bewertet. Serie und Erfolge können sich dadurch ändern. Schon
  gespeicherte Erfolgs-Stufen bleiben erhalten.

### Serie

- Die Serie zählt Tage mit erreichtem Tagesziel am Stück.
- Pro Kalenderwoche (Montag bis Sonntag) ist **ein** verpasster Tag frei.
  Die Serie bleibt dann stehen, wächst an dem Tag aber nicht. Der zweite
  verpasste Tag derselben Woche beendet sie.
- Heute zählt erst mit, wenn das Ziel erreicht ist. Ein noch offener Tag
  bricht nichts ab.
- Die Karte zeigt die aktuelle Serie (Flamme), den Bestwert und ob der
  freie Tag dieser Woche schon genutzt ist.
- Die bisherige Kennzahl „Trainingstage am Stück“ in der Statistik bleibt
  unverändert. Sie zählt jeden Tag mit Training, unabhängig vom Ziel.

## Erfolge

- 25 Erfolge in fünf Gruppen. Die meisten haben drei Stufen (Bronze,
  Silber, Gold), einige nur eine. Zusammen sind es 49 Stufen.
- Alle Erfolge werden **rückwirkend** aus den vorhandenen Daten berechnet.
  Als Datum gilt das Ende der Session, mit der die Stufe erreicht wurde.
  Bei Tagesziel-Erfolgen ist es der Tag selbst, bei Sternen das
  Challenge-Ergebnis.
- Erreichte Stufen werden mit Datum in der Tabelle `achievements`
  gespeichert. Gespeicherte Stufen bleiben, auch wenn die Daten sie
  später nicht mehr hergeben, zum Beispiel nach dem Löschen von
  Sessions oder einem anderen Tagesziel.
- Wird im Spiel eine neue Stufe erreicht, erscheint unten eine
  Einblendung, je Erfolg nur mit der höchsten neuen Stufe. Was beim
  ersten Start rückwirkend dazukommt, wird still gespeichert.
- Anzeige: Statistik → Reiter **Erfolge**. Gesperrte Erfolge sind grau
  und zeigen ihren Fortschritt, z. B. „7 / 10“. Erreichte zeigen das
  Datum.

| Gruppe | Erfolg | Bedingung | Stufen (Bronze / Silber / Gold) |
|---|---|---|---|
| Scoring | Die erste Tonne | eine Aufnahme mit mindestens 100 Punkten | 1 |
| Scoring | Ton-Forty | eine Aufnahme mit mindestens 140 Punkten | 1 |
| Scoring | Die erste 180 | eine 180 | 1 |
| Scoring | 180er-Sammler | 180er insgesamt | 10 / 50 / 100 |
| Scoring | Tonnen-Maschine | Aufnahmen mit 100+ insgesamt | 25 / 100 / 500 |
| Scoring | Scoring-Average | bester 3-Dart-Average einer Session (ab 18 Darts) | 50 / 70 / 90 |
| Finish | Ton-Plus-Finish | ein Checkout über 100 | 101 |
| Finish | Big Fish | Checkout 170 | 170 |
| Finish | Bull-Finish | ein Checkout mit dem Bullseye | 1 |
| Finish | Checkout-Routine | Checkouts insgesamt | 25 / 100 / 500 |
| Finish | Schnelles Leg | 501 (Double- oder Master-Out) in höchstens … Darts | 30 / 21 / 15 |
| Doppel | Bob's 200 | mindestens 200 Punkte in Bob's 27 (Start 27, überstanden) | 200 |
| Doppel | Überlebt | Bob's 27 überstanden | 1 |
| Doppel | Doppel-Serie | 5 Doppel-Ziele hintereinander getroffen | 5 |
| Doppel | Doppel-Treffer | getroffene Doppel-Ziele insgesamt | 100 / 500 / 2000 |
| Ausdauer | Fleißig | geworfene Darts insgesamt | 1.000 / 10.000 / 100.000 |
| Ausdauer | Am Ball | längste Tagesziel-Serie (Tage) | 7 / 30 / 100 |
| Ausdauer | Zielstrebig | Tage mit erreichtem Tagesziel | 10 / 50 / 200 |
| Ausdauer | Trainingsstunden | Trainingszeit insgesamt (Stunden) | 10 / 50 / 200 |
| Spiele | Allrounder | jedes Trainingsspiel einmal regulär zu Ende gespielt | alle Spiele des Katalogs |
| Spiele | Gegen den Computer | gewonnene Matches gegen den Computer | 1 / 10 / 50 |
| Spiele | Turniersieger | ein Turnier gewonnen (Finale) | 1 |
| Spiele | Neun-Darter | ein 501-Leg mit 9 Darts | 1 |
| Spiele | Shanghai! | ein Shanghai (Shanghai oder JDC-Challenge) | 1 |
| Spiele | Sternesammler | Challenge-Sterne insgesamt | 30 / 60 / 120 |

Hinweise zur Berechnung:

- Aufnahmen mit 100/140/180 zählen in allen X01-Spielen und Matches sowie
  in den Scoring-Spielen (T20-Training, Score-Aufgabe, Highscore-Jagd).
- Checkouts zählen im Checkout-Training, in 121, Catch 40, X01-Solo und
  in Matches (gewonnene Legs). Ein Bull-Finish im Match wird nur am
  letzten Dart des Matches erkannt.
- „Doppel-Ziele“ sind Darts, deren Ziel genau ein Doppel war (z. B. in
  Bob's 27, Around the Clock auf Doppel, Doppel-Leiter).
- Trainingszeit: Dauer jeder Session, höchstens drei Stunden je Session.

## Challenge-Modus

- 40 feste Aufgaben in fünf Kapiteln: Einsteiger, Amateur, Ligaspieler,
  Profi, Weltklasse. Jede bringt 1–3 Sterne. Die Definitionen stehen im
  Code (`lib/features/challenges/domain/challenge_catalog.dart`).
- Ablauf: Training → Karte **Challenges** → Kapitel mit Sternen →
  Aufgabe antippen (Aufgabe, Sterne-Schwellen, Bestwert) → **Challenge
  starten**. Gespielt wird in der normalen Spielansicht. Oben stehen die
  Aufgabe und die Live-Sterne:
  - voll: sicher erreicht
  - blass: im Moment erreicht, kann wieder verloren gehen
  - offen
  - verblasst: nicht mehr zu schaffen
- Am Ende erscheinen die Sterne mit einer kurzen Animation, das Ergebnis,
  ein neuer Bestwert und was neu frei ist. Danach geht es weiter mit
  „Nächste“, „Übersicht“ oder „Nochmal“.

### Regeln

- Nur ein **regulär beendetes** Spiel wird gewertet. Wer vorher aufhört
  oder das Spiel verlässt, bekommt keine Sterne, und es wird nichts
  gespeichert. Aufgaben, die ein vollständiges Spiel verlangen (z. B.
  Around the Clock, Bob's 27, Cricket), zählen nur, wenn das Spiel bis
  zum Ende gespielt wurde.
- Gespeichert wird je Profil und Challenge das Beste: die meisten Sterne,
  der beste Wert, die Zahl der Versuche und das Datum des besten
  Ergebnisses. Die Werte werden nur besser, nie schlechter. Tabelle:
  `challenge_results`.
- Kapitel 1 ist offen. Ein Kapitel öffnet sich mit **12 von 24 Sternen**
  im Kapitel davor.
- In einem offenen Kapitel ist die erste Challenge offen. Jede weitere
  öffnet sich, sobald eine der **beiden** davor mindestens einen Stern
  hat. Eine schwere Aufgabe lässt sich also überspringen.
- Matches gegen den Computer (501, Double-Out) geben Sterne so:
  - ★: Match gewonnen
  - ★★: ohne Leg-Verlust gewonnen
  - ★★★: zusätzlich mindestens der angegebene eigene Average
- Ein Test spielt jede Trainings-Challenge mit perfekten Würfen durch und
  prüft, dass drei Sterne möglich sind. Nur Fehlwürfe bringen keinen
  Stern.

### Wie die Sterne-Schwellen eingestellt sind

Die Schwellen sind mit Computergegnern (`DartBot.forAverage`) auf
Average 40, 60 und 80 eingestellt, je Challenge und Stufe 1000 Versuche
mit festen Zufallsstartwerten. Ziel:

- ★ schafft ein 40er in den meisten Versuchen,
- ★★ ist für einen 60er der Normalfall,
- ★★★ braucht etwa 80er-Niveau: ein 80er schafft sie in einem guten Teil
  der Versuche, ein 60er selten.

Frühe Kapitel sind großzügiger (Einsteiger: ★ für einen 40er in rund
90 % der Versuche, ★★ auch für ihn ab und zu, damit er mit 12 Sternen
weiterkommt), Weltklasse strenger (★★★ für einen 80er in rund 30 %).
Kommt ein Spiel doppelt vor (501, Highscore-Jagd, JDC, Bob's 27), beginnt
die spätere Challenge etwa dort, wo die frühere ★★ hat.

Wie der Bot spielt: Er zielt wie ein vernünftiger Spieler, also beim
Scoren auf T20, bei Zahlen-Zielen auf das Triple (dort ist das Segment am
breitesten), bei Doppel-Zielen aufs Doppel und bei Finishes auf den
Checkout-Weg. Doppel und Finish-Darts wirft er mit der Finish-Streuung
(sie folgt echten Doppelquoten), alles andere, auch Bull, mit der
Scoring-Streuung. Beim Darts-Golf hört er auf, sobald ein weiterer Dart
im Schnitt nichts mehr bringt. Matches spielt er gegen den CPU-Gegner der
Challenge und beginnt das erste Leg.

Ausnahmen, bei denen ein 40er ★ bewusst selten schafft: Bob's 27 (★
heißt überstehen), die Matches ab Kapitel 3, Ton-Plus-Checkouts,
Ton-Forty-Serie, Große Finishes, Drei in einem Bett, Frustration und die
späteren der doppelt vorkommenden Spiele. Frustration ist erst ab etwa
einem 60er sinnvoll.

Gemessene Quoten mit den aktuellen Schwellen (Anteil der Versuche):

| Nr. | 40er ★ | 60er ★★ | 60er ★★★ | 80er ★★★ |
|---|---|---|---|---|
| 1.1 | 91 % | 100 % | 15 % | 94 % |
| 1.2 | 91 % | 75 % | 32 % | 50 % |
| 1.3 | 89 % | 98 % | 12 % | 90 % |
| 1.4 | 88 % | 100 % | 11 % | 99 % |
| 1.5 | 77 % | 95 % | 6 % | 71 % |
| 1.6 | 91 % | 88 % | 17 % | 64 % |
| 1.7 | 91 % | 75 % | 43 % | 68 % |
| 1.8 | 93 % | 100 % | 3 % | 90 % |
| 2.1 | 75 % | 94 % | 13 % | 84 % |
| 2.2 | 79 % | 73 % | 19 % | 59 % |
| 2.3 | 73 % | 77 % | 12 % | 33 % |
| 2.4 | 87 % | 89 % | 18 % | 90 % |
| 2.5 | 74 % | 89 % | 4 % | 75 % |
| 2.6 | 83 % | 77 % | 16 % | 59 % |
| 2.7 | 26 % | 56 % | 17 % | 53 % |
| 2.8 | 82 % | 80 % | 11 % | 47 % |
| 3.1 | 69 % | 58 % | 10 % | 61 % |
| 3.2 | 73 % | 73 % | 22 % | 56 % |
| 3.3 | 23 % | 62 % | 3 % | 73 % |
| 3.4 | 70 % | 61 % | 1 % | 62 % |
| 3.5 | 72 % | 55 % | 11 % | 50 % |
| 3.6 | 72 % | 73 % | 7 % | 62 % |
| 3.7 | 70 % | 60 % | 14 % | 47 % |
| 3.8 | 83 % | 67 % | 1 % | 55 % |
| 4.1 | 62 % | 53 % | 12 % | 33 % |
| 4.2 | 22 % | 22 % | 6 % | 29 % |
| 4.3 | 3 % | 26 % | 0 % | 47 % |
| 4.4 | 4 % | 9 % | 1 % | 32 % |
| 4.5 | 45 % | 43 % | 1 % | 45 % |
| 4.6 | 15 % | 36 % | 5 % | 28 % |
| 4.7 | 52 % | 50 % | 3 % | 35 % |
| 4.8 | 65 % | 45 % | 6 % | 32 % |
| 5.1 | 26 % | 31 % | 2 % | 27 % |
| 5.2 | 0 % | 7 % | 0 % | 20 % |
| 5.3 | 23 % | 23 % | 0 % | 28 % |
| 5.4 | 49 % | 45 % | 2 % | 32 % |
| 5.5 | 36 % | 41 % | 0 % | 50 % |
| 5.6 | 0 % | 0 % | 0 % | 32 % |
| 5.7 | 11 % | 30 % | 1 % | 28 % |
| 5.8 | 75 % | 72 % | 32 % | 75 % |

Der Test `challenge_fairness_test.dart` spielt jede Challenge mit 60
Versuchen je Stufe und prüft grobe Leitplanken (★★★ für einen 80er
mindestens 15 %, für einen 60er höchstens 50 %, in den Kapiteln 1–3 ★
für einen 40er mindestens 60 % und ★★ für einen 60er mindestens 40 %).
Die volle Simulation mit 1000 Versuchen liegt nicht im Repository; sie
nutzt dieselben Hilfsfunktionen aus `test/helpers/challenge_sim.dart`.

### Alle Challenges

### Kapitel 1 · Einsteiger

| Nr. | Name | Spiel | Aufgabe | ★ | ★★ | ★★★ |
|---|---|---|---|---|---|---|
| 1 | Rund um die Uhr | Around the Clock | Triff 1 bis 20 und das Bull der Reihe nach, jedes Feld zählt. So wenige Darts wie möglich. | ≤ 60 Darts | ≤ 40 Darts | ≤ 25 Darts |
| 2 | Erster Checkout | X01-Solo | Spiele 101 mit Double-Out aus. So wenige Darts wie möglich. | ≤ 18 Darts | ≤ 9 Darts | ≤ 5 Darts |
| 3 | Auf die 20 | T20-Training | 10 Aufnahmen auf die 20. Sammle so viele Punkte wie möglich. | ≥ 350 Punkte | ≥ 500 Punkte | ≥ 800 Punkte |
| 4 | Bull-Training | Bullseye-Drills | 10 Aufnahmen aufs Bull: Single Bull 25, Bullseye 50 Punkte. | ≥ 100 Punkte | ≥ 200 Punkte | ≥ 550 Punkte |
| 5 | Sechzig plus | Score-Aufgabe | 10 Aufnahmen: Wie oft schaffst du mindestens 60 Punkte? | ≥ 2 Erfolge | ≥ 4 Erfolge | ≥ 9 Erfolge |
| 6 | Kleines Shanghai | Shanghai | Shanghai auf 1 bis 7, eine Aufnahme pro Zahl. Sammle so viele Punkte wie möglich. | ≥ 30 Punkte | ≥ 70 Punkte | ≥ 200 Punkte |
| 7 | Neun Löcher | Darts-Golf | Darts-Golf über 9 Löcher. So wenige Schläge wie möglich. | ≤ 33 Schläge | ≤ 25 Schläge | ≤ 20 Schläge |
| 8 | Doppelt hält besser | Drei-Treffer-Runde | Triff jede Zahl von 1 bis 20 und das Bull zweimal, Double und Triple zählen mehrfach. So wenige Darts wie möglich. | ≤ 110 Darts | ≤ 80 Darts | ≤ 42 Darts |

### Kapitel 2 · Amateur

| Nr. | Name | Spiel | Aufgabe | ★ | ★★ | ★★★ |
|---|---|---|---|---|---|---|
| 1 | Erster Gegner | X01-Match | Gewinne ein Best of 3 (501, Double-Out) gegen den Computer mit Average 35. | Sieg | Sieg ohne Leg-Verlust | ohne Leg-Verlust, Average ≥ 70 |
| 2 | 301 sauber | X01-Solo | Spiele 301 mit Double-Out aus. So wenige Darts wie möglich. | ≤ 28 Darts | ≤ 18 Darts | ≤ 12 Darts |
| 3 | Kleine Finishes | Checkout-Training | 10 zufällige Checkouts von 2 bis 40, je 3 Darts. Wie viele schaffst du? | ≥ 3 Checkouts | ≥ 4 Checkouts | ≥ 7 Checkouts |
| 4 | Cricket solo | Cricket | Schließe 20 bis 15 und das Bull. So wenige Darts wie möglich. | ≤ 60 Darts | ≤ 30 Darts | ≤ 20 Darts |
| 5 | Mit Sprüngen um die Welt | Around the World mit Überspringen | S=1, D=2, T=3 Punkte; ab 4 Punkten in einer Aufnahme springst du eine Zahl weiter. Sammle so viele Punkte wie möglich. | ≥ 30 Punkte | ≥ 45 Punkte | ≥ 57 Punkte |
| 6 | Bermuda-Dreieck | Halve-It | Halve-It: Verfehlst du ein Ziel, halbiert sich dein Stand. Sammle so viele Punkte wie möglich. | ≥ 30 Punkte | ≥ 175 Punkte | ≥ 450 Punkte |
| 7 | Bob's 27 | Bob's 27 | Start mit 27 Punkten, Doppel 1 bis 20 und Bull. Überstehe das Spiel, ohne unter 0 zu fallen. | ≥ 1 Punkte | ≥ 100 Punkte | ≥ 300 Punkte |
| 8 | Leiter ab 121 | 121 | Checke ab 121 mit je 9 Darts, geschafft heißt eins höher. Wie viele Checkouts in 10 Runden? | ≥ 3 Checkouts | ≥ 6 Checkouts | ≥ 9 Checkouts |

### Kapitel 3 · Ligaspieler

| Nr. | Name | Spiel | Aufgabe | ★ | ★★ | ★★★ |
|---|---|---|---|---|---|---|
| 1 | Liga-Leg | X01-Solo | Spiele 501 mit Double-Out aus. So wenige Darts wie möglich. | ≤ 40 Darts | ≤ 25 Darts | ≤ 19 Darts |
| 2 | Zwei Aufnahmen | Checkout-Training | 10 zufällige Checkouts von 61 bis 80, je 6 Darts. Wie viele schaffst du? | ≥ 4 Checkouts | ≥ 6 Checkouts | ≥ 8 Checkouts |
| 3 | Ligaabend | X01-Match | Gewinne ein Best of 5 (501, Double-Out) gegen den Computer mit Average 45. | Sieg | Sieg ohne Leg-Verlust | ohne Leg-Verlust, Average ≥ 75 |
| 4 | Punktejagd | Highscore-Jagd | 10 Aufnahmen: Sammle so viele Punkte wie möglich. | ≥ 400 Punkte | ≥ 650 Punkte | ≥ 900 Punkte |
| 5 | Doppelrunde | Around the Clock | Triff die Doppel von 1 bis 20 und das Bull der Reihe nach. So wenige Darts wie möglich. | ≤ 130 Darts | ≤ 85 Darts | ≤ 65 Darts |
| 6 | JDC-Prüfung | JDC-Challenge | Shanghai 10–15, alle Doppel, Shanghai 15–20: Sammle so viele Punkte wie möglich. | ≥ 450 Punkte | ≥ 800 Punkte | ≥ 1200 Punkte |
| 7 | Countdown 420 | 420 | Start bei 420, jeder Treffer auf das aktuelle Doppel zieht ab. So wenige Restpunkte wie möglich. | ≤ 220 Punkte | ≤ 110 Punkte | ≤ 0 Punkte |
| 8 | Catch 40 | Catch 40 | Finishes von 61 bis 100 der Reihe nach, je 6 Darts. Schnelle Checkouts bringen mehr Punkte. | ≥ 15 Punkte | ≥ 30 Punkte | ≥ 45 Punkte |

### Kapitel 4 · Profi

| Nr. | Name | Spiel | Aufgabe | ★ | ★★ | ★★★ |
|---|---|---|---|---|---|---|
| 1 | Die 170 | X01-Solo | Spiele 170 mit Double-Out aus. So wenige Darts wie möglich. | ≤ 15 Darts | ≤ 10 Darts | ≤ 6 Darts |
| 2 | Ton-Plus-Checkouts | Checkout-Training | 10 zufällige Checkouts von 81 bis 120, je 3 Darts. Wie viele schaffst du? | ≥ 1 Checkouts | ≥ 2 Checkouts | ≥ 3 Checkouts |
| 3 | Profi-Duell | X01-Match | Gewinne ein Best of 5 (501, Double-Out) gegen den Computer mit Average 55. | Sieg | Sieg ohne Leg-Verlust | ohne Leg-Verlust, Average ≥ 80 |
| 4 | Ton-Forty-Serie | Score-Aufgabe | 10 Aufnahmen: Wie oft schaffst du mindestens 140 Punkte? | ≥ 1 Erfolge | ≥ 2 Erfolge | ≥ 3 Erfolge |
| 5 | Wechselspiel | Ziel-Wechsel | Triple 20, Triple 19, Bullseye im Wechsel, 10 Runden. Wie viele Treffer? | ≥ 2 Treffer | ≥ 5 Treffer | ≥ 9 Treffer |
| 6 | Bob's 27 Profi | Bob's 27 | Bob's 27 überstehen und dabei möglichst viele Punkte sammeln. | ≥ 100 Punkte | ≥ 200 Punkte | ≥ 400 Punkte |
| 7 | Doppelleiter | Doppel-Leiter | Doppel von D1 aufwärts, genug Treffer heißt eine Stufe höher. Welche Stufe erreichst du in 60 Aufnahmen? | Stufe ≥ 3 | Stufe ≥ 4 | Stufe ≥ 7 |
| 8 | Stellen | Stellen | Mit einem Dart einen Rest von 41 bis 100 auf ein klassisches Doppel stellen. Wie oft gelingt es in 30 Darts? | ≥ 10 Erfolge | ≥ 15 Erfolge | ≥ 19 Erfolge |

### Kapitel 5 · Weltklasse

| Nr. | Name | Spiel | Aufgabe | ★ | ★★ | ★★★ |
|---|---|---|---|---|---|---|
| 1 | Weltklasse-Leg | X01-Solo | Spiele 501 mit Double-Out aus, schneller als im Liga-Leg. So wenige Darts wie möglich. | ≤ 32 Darts | ≤ 22 Darts | ≤ 16 Darts |
| 2 | Weltmeister | X01-Match | Gewinne ein Best of 7 (501, Double-Out) gegen den Computer mit Average 60. | Sieg | Sieg ohne Leg-Verlust | ohne Leg-Verlust, Average ≥ 85 |
| 3 | Maximum | Highscore-Jagd | 10 Aufnahmen: Sammle so viele Punkte wie möglich. | ≥ 500 Punkte | ≥ 750 Punkte | ≥ 1000 Punkte |
| 4 | Große Finishes | Checkout-Training | 10 zufällige Checkouts von 121 bis 170, je 6 Darts. Wie viele schaffst du? | ≥ 1 Checkouts | ≥ 3 Checkouts | ≥ 6 Checkouts |
| 5 | Drei in einem Bett | Drei im Bett | Alle drei Darts einer Aufnahme ins gleiche Segment, für jede Zahl von 1 bis 20. So wenige Aufnahmen wie möglich. | ≤ 180 Aufnahmen | ≤ 45 Aufnahmen | ≤ 25 Aufnahmen |
| 6 | Frustration | Frustration | Mit zwei Darts mindestens 80 scoren, dann mit dem dritten das Doppel, D1 bis Bull. So wenige Aufnahmen wie möglich. | ≤ 400 Aufnahmen | ≤ 200 Aufnahmen | ≤ 125 Aufnahmen |
| 7 | JDC-Meister | JDC-Challenge | Shanghai 10–15, alle Doppel, Shanghai 15–20: ein Ergebnis auf Weltklasse-Niveau. | ≥ 700 Punkte | ≥ 1000 Punkte | ≥ 1400 Punkte |
| 8 | Genau 100 | Genau 100 | Genau 100 Punkte mit höchstens 2 Aufnahmen, Überwerfen ist ein Fehlversuch. Wie oft in 5 Versuchen? | ≥ 2 Erfolge | ≥ 4 Erfolge | ≥ 5 Erfolge |

## Daten, Abgleich und Sicherung

- Datenbank-Schema Version 5 (inzwischen 7: `sessions.updated_at` für den
  [Abgleich](sync.md)). Neu in Version 5 sind die Tabellen `achievements`
  (Profil, Erfolg, Stufe, Datum; eindeutig je Profil/Erfolg/Stufe) und
  `challenge_results` (Profil, Challenge, Sterne, Bestwert, Versuche,
  Datum, geändert; eindeutig je Profil/Challenge). Die Migration legt
  beide mit `IF NOT EXISTS` an und lässt sich wiederholen.
- Abgleich zwischen Geräten:
  - Erfolge: fehlende Stufen kommen dazu, bei doppelten gilt das frühere
    Datum.
  - Challenges: von beiden Seiten jeweils das Bessere, also mehr Sterne,
    der bessere Bestwert und mehr Versuche.
- Die JSON-Sicherung (Version 4) enthält beide Tabellen. Ältere
  Sicherungen lassen sich weiter einlesen.
- Löschen eines Profils löscht auch seine Erfolge und Challenge-Ergebnisse.
