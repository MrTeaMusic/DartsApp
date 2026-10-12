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
  Ring während eines Spiels, erscheint oben eine kurze Einblendung. Sie
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
- Wird im Spiel eine neue Stufe erreicht, erscheint oben eine
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

### Alle Challenges

### Kapitel 1 · Einsteiger

| Nr. | Name | Spiel | Aufgabe | ★ | ★★ | ★★★ |
|---|---|---|---|---|---|---|
| 1 | Rund um die Uhr | Around the Clock | Triff 1 bis 20 und das Bull der Reihe nach, jedes Feld zählt. So wenige Darts wie möglich. | ≤ 60 Darts | ≤ 45 Darts | ≤ 35 Darts |
| 2 | Erster Checkout | X01-Solo | Spiele 101 mit Double-Out aus. So wenige Darts wie möglich. | ≤ 15 Darts | ≤ 12 Darts | ≤ 9 Darts |
| 3 | Auf die 20 | T20-Training | 10 Aufnahmen auf die 20. Sammle so viele Punkte wie möglich. | ≥ 300 Punkte | ≥ 400 Punkte | ≥ 500 Punkte |
| 4 | Bull-Training | Bullseye-Drills | 10 Aufnahmen aufs Bull: Single Bull 25, Bullseye 50 Punkte. | ≥ 75 Punkte | ≥ 150 Punkte | ≥ 250 Punkte |
| 5 | Sechzig plus | Score-Aufgabe | 10 Aufnahmen: Wie oft schaffst du mindestens 60 Punkte? | ≥ 4 Erfolge | ≥ 6 Erfolge | ≥ 8 Erfolge |
| 6 | Kleines Shanghai | Shanghai | Shanghai auf 1 bis 7, eine Aufnahme pro Zahl. Sammle so viele Punkte wie möglich. | ≥ 40 Punkte | ≥ 70 Punkte | ≥ 100 Punkte |
| 7 | Neun Löcher | Darts-Golf | Darts-Golf über 9 Löcher. So wenige Schläge wie möglich. | ≤ 40 Schläge | ≤ 36 Schläge | ≤ 32 Schläge |
| 8 | Doppelt hält besser | Drei-Treffer-Runde | Triff jede Zahl von 1 bis 20 und das Bull zweimal, Double und Triple zählen mehrfach. So wenige Darts wie möglich. | ≤ 120 Darts | ≤ 95 Darts | ≤ 75 Darts |

### Kapitel 2 · Amateur

| Nr. | Name | Spiel | Aufgabe | ★ | ★★ | ★★★ |
|---|---|---|---|---|---|---|
| 1 | Erster Gegner | X01-Match | Gewinne ein Best of 3 (501, Double-Out) gegen den Computer mit Average 50. | Sieg | Sieg ohne Leg-Verlust | ohne Leg-Verlust, Average ≥ 50 |
| 2 | 301 sauber | X01-Solo | Spiele 301 mit Double-Out aus. So wenige Darts wie möglich. | ≤ 24 Darts | ≤ 18 Darts | ≤ 15 Darts |
| 3 | Kleine Finishes | Checkout-Training | 10 zufällige Checkouts von 2 bis 40, je 3 Darts. Wie viele schaffst du? | ≥ 3 Checkouts | ≥ 5 Checkouts | ≥ 7 Checkouts |
| 4 | Cricket solo | Cricket | Schließe 20 bis 15 und das Bull. So wenige Darts wie möglich. | ≤ 75 Darts | ≤ 60 Darts | ≤ 48 Darts |
| 5 | Mit Sprüngen um die Welt | Around the World mit Überspringen | S=1, D=2, T=3 Punkte; ab 4 Punkten in einer Aufnahme springst du eine Zahl weiter. Sammle so viele Punkte wie möglich. | ≥ 30 Punkte | ≥ 40 Punkte | ≥ 50 Punkte |
| 6 | Bermuda-Dreieck | Halve-It | Halve-It: Verfehlst du ein Ziel, halbiert sich dein Stand. Sammle so viele Punkte wie möglich. | ≥ 120 Punkte | ≥ 200 Punkte | ≥ 300 Punkte |
| 7 | Bob's 27 | Bob's 27 | Start mit 27 Punkten, Doppel 1 bis 20 und Bull. Überstehe das Spiel, ohne unter 0 zu fallen. | ≥ 1 Punkte | ≥ 100 Punkte | ≥ 200 Punkte |
| 8 | Leiter ab 121 | 121 | Checke ab 121 mit je 9 Darts, geschafft heißt eins höher. Wie viele Checkouts in 10 Runden? | ≥ 2 Checkouts | ≥ 4 Checkouts | ≥ 6 Checkouts |

### Kapitel 3 · Ligaspieler

| Nr. | Name | Spiel | Aufgabe | ★ | ★★ | ★★★ |
|---|---|---|---|---|---|---|
| 1 | Liga-Leg | X01-Solo | Spiele 501 mit Double-Out aus. So wenige Darts wie möglich. | ≤ 30 Darts | ≤ 24 Darts | ≤ 21 Darts |
| 2 | Zwei Aufnahmen | Checkout-Training | 10 zufällige Checkouts von 61 bis 80, je 6 Darts. Wie viele schaffst du? | ≥ 3 Checkouts | ≥ 5 Checkouts | ≥ 7 Checkouts |
| 3 | Ligaabend | X01-Match | Gewinne ein Best of 5 (501, Double-Out) gegen den Computer mit Average 65. | Sieg | Sieg ohne Leg-Verlust | ohne Leg-Verlust, Average ≥ 65 |
| 4 | Punktejagd | Highscore-Jagd | 10 Aufnahmen: Sammle so viele Punkte wie möglich. | ≥ 550 Punkte | ≥ 650 Punkte | ≥ 750 Punkte |
| 5 | Doppelrunde | Around the Clock | Triff die Doppel von 1 bis 20 und das Bull der Reihe nach. So wenige Darts wie möglich. | ≤ 120 Darts | ≤ 90 Darts | ≤ 65 Darts |
| 6 | JDC-Prüfung | JDC-Challenge | Shanghai 10–15, alle Doppel, Shanghai 15–20: Sammle so viele Punkte wie möglich. | ≥ 300 Punkte | ≥ 450 Punkte | ≥ 600 Punkte |
| 7 | Countdown 420 | 420 | Start bei 420, jeder Treffer auf das aktuelle Doppel zieht ab. So wenige Restpunkte wie möglich. | ≤ 250 Punkte | ≤ 170 Punkte | ≤ 100 Punkte |
| 8 | Catch 40 | Catch 40 | Finishes von 61 bis 100 der Reihe nach, je 6 Darts. Schnelle Checkouts bringen mehr Punkte. | ≥ 30 Punkte | ≥ 45 Punkte | ≥ 60 Punkte |

### Kapitel 4 · Profi

| Nr. | Name | Spiel | Aufgabe | ★ | ★★ | ★★★ |
|---|---|---|---|---|---|---|
| 1 | Die 170 | X01-Solo | Spiele 170 mit Double-Out aus. Drei Darts für drei Sterne. | ≤ 9 Darts | ≤ 6 Darts | ≤ 3 Darts |
| 2 | Ton-Plus-Checkouts | Checkout-Training | 10 zufällige Checkouts von 81 bis 120, je 3 Darts. Wie viele schaffst du? | ≥ 2 Checkouts | ≥ 4 Checkouts | ≥ 6 Checkouts |
| 3 | Profi-Duell | X01-Match | Gewinne ein Best of 5 (501, Double-Out) gegen den Computer mit Average 80. | Sieg | Sieg ohne Leg-Verlust | ohne Leg-Verlust, Average ≥ 80 |
| 4 | Ton-Forty-Serie | Score-Aufgabe | 10 Aufnahmen: Wie oft schaffst du mindestens 140 Punkte? | ≥ 1 Erfolge | ≥ 2 Erfolge | ≥ 4 Erfolge |
| 5 | Wechselspiel | Ziel-Wechsel | Triple 20, Triple 19, Bullseye im Wechsel, 10 Runden. Wie viele Treffer? | ≥ 6 Treffer | ≥ 9 Treffer | ≥ 12 Treffer |
| 6 | Bob's 27 Profi | Bob's 27 | Bob's 27 überstehen und dabei möglichst viele Punkte sammeln. | ≥ 300 Punkte | ≥ 500 Punkte | ≥ 700 Punkte |
| 7 | Doppelleiter | Doppel-Leiter | Doppel von D1 aufwärts, genug Treffer heißt eine Stufe höher. Welche Stufe erreichst du in 60 Aufnahmen? | Stufe ≥ 5 | Stufe ≥ 8 | Stufe ≥ 12 |
| 8 | Stellen | Stellen | Mit einem Dart einen Rest von 41 bis 100 auf ein klassisches Doppel stellen. Wie oft gelingt es in 30 Darts? | ≥ 18 Erfolge | ≥ 22 Erfolge | ≥ 26 Erfolge |

### Kapitel 5 · Weltklasse

| Nr. | Name | Spiel | Aufgabe | ★ | ★★ | ★★★ |
|---|---|---|---|---|---|---|
| 1 | Neun-Darter-Jagd | X01-Solo | Spiele 501 mit Double-Out aus. Neun Darts für drei Sterne. | ≤ 15 Darts | ≤ 12 Darts | ≤ 9 Darts |
| 2 | Weltmeister | X01-Match | Gewinne ein Best of 7 (501, Double-Out) gegen den Computer mit Average 100. | Sieg | Sieg ohne Leg-Verlust | ohne Leg-Verlust, Average ≥ 100 |
| 3 | Maximum | Highscore-Jagd | 10 Aufnahmen: Sammle so viele Punkte wie möglich. | ≥ 900 Punkte | ≥ 1050 Punkte | ≥ 1200 Punkte |
| 4 | Große Finishes | Checkout-Training | 10 zufällige Checkouts von 121 bis 170, je 3 Darts. Wie viele schaffst du? | ≥ 2 Checkouts | ≥ 3 Checkouts | ≥ 5 Checkouts |
| 5 | Drei in einem Bett | Drei im Bett | Alle drei Darts einer Aufnahme ins gleiche Segment, für jede Zahl von 1 bis 20. So wenige Aufnahmen wie möglich. | ≤ 80 Aufnahmen | ≤ 60 Aufnahmen | ≤ 45 Aufnahmen |
| 6 | Frustration | Frustration | Mit zwei Darts mindestens 80 scoren, dann mit dem dritten das Doppel, D1 bis Bull. So wenige Aufnahmen wie möglich. | ≤ 150 Aufnahmen | ≤ 110 Aufnahmen | ≤ 85 Aufnahmen |
| 7 | JDC-Meister | JDC-Challenge | Shanghai 10–15, alle Doppel, Shanghai 15–20: ein Ergebnis auf Weltklasse-Niveau. | ≥ 600 Punkte | ≥ 750 Punkte | ≥ 900 Punkte |
| 8 | Genau 100 | Genau 100 | Genau 100 Punkte mit höchstens 2 Aufnahmen, Überwerfen ist ein Fehlversuch. Wie oft in 5 Versuchen? | ≥ 3 Erfolge | ≥ 4 Erfolge | ≥ 5 Erfolge |

## Daten, Abgleich und Sicherung

- Datenbank-Schema Version 5. Neu sind die Tabellen `achievements`
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
