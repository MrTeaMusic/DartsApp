# Trainingsspiele: Regeln und Optionen

Alle Optionen stellst du vor dem Start ein; die letzte Wahl pro Spiel wird gemerkt.
Eine Aufnahme hat 3 Darts. Bei Autodarts beginnt die nächste Aufnahme mit dem Takeout,
im Simulator und bei manueller Eingabe über „Weiter“ oder automatisch nach dem dritten Dart.
Darts, die nach dem vorzeitigen Ende einer Aufnahme (Bust, Checkout) noch geworfen werden,
zählen nicht und werden in der Datenbank als „nicht gezählt“ markiert.

## Checkout-Training

* Pro Versuch bekommst du einen Restwert und versuchst, ihn auszuchecken.
* **Modus:** zufällig, absteigend (vom Höchstwert abwärts) oder „schwache Werte“.
  „Schwache Werte“ nimmt zu 70 % Werte mit deiner schlechtesten Quote aus früheren Sessions
  (mindestens 2 Versuche pro Wert), sonst einen zufälligen.
* **Bereich:** Minimum und Maximum (2 bis 170). Es werden nur Werte gestellt, die sich mit
  3 Darts auschecken lassen (bei Double-Out also z. B. nie 169, 168, 166, 165, 163, 162, 159).
* **Darts pro Versuch:** 3, 6 oder 9 (1 bis 3 Aufnahmen).
* **Double-Out** (an/aus): Bei „an“ muss der letzte Dart ein Double oder das Bullseye sein.
* **Bust:** Rest unter 0, genau 0 ohne Double (bei Double-Out) oder Rest 1. Der Rest springt
  auf den Stand vor der Aufnahme zurück, die Aufnahme ist vorbei.
* **Checkout-Vorschlag** (an/aus): zeigt einen Weg mit den verbleibenden Darts. Bei Double-Out
  ist das der Weg aus der üblichen Checkout-Tabelle (`CheckoutTable`, z. B. 121 T20 T11 D14,
  61 T15 D8, 170 T20 T20 Bull), sonst sucht eine Kostenfunktion: wenige Darts, dann gängige
  Doubles (D20, D16, D8 …), kleine ungerade Doubles (D1, D3, D5 …) nur, wenn es nicht anders geht.
* Wertung: Checkout-Quote, Darts pro Checkout, höchster Checkout.

## Around the Clock

* **Reihenfolge:** 1 bis 20, im Uhrzeigersinn (20, 1, 18, …) oder zufällig.
* **Bull am Ende** (an/aus): 25 oder Bullseye zählen.
* **Ring:** beliebig, nur Single, nur Double oder nur Triple.
* **Mehrfach springt weiter** (an/aus): Ein Double rückt 2 Zahlen vor, ein Triple 3.
* Ende, wenn alle Ziele getroffen sind. Wertung: benötigte Darts und Trefferquote.

## Bullseye-Drill

* **Aufnahmen:** 1 bis 50. Jeder Dart zählt: 25 = 25 Punkte, Bullseye = 50 Punkte.
* Wertung: Punkte, Anzahl Bullseye und 25, Bull-Quote.

## Scoring-Drills

### T20-Training (Zahl wählbar)

* **Zahl:** 20, 19, 18, 17, 16 oder 15. **Aufnahmen:** 1 bis 50.
* Wertung: Average (3 Darts), Triple-Quote und Trefferquote auf die Zahl.

### Score-Ziel (100 / 140 / 180 …)

* **Ziel:** 60, 81, 100, 121, 140 oder 180 Punkte pro Aufnahme. **Aufnahmen:** 1 bis 50.
* Eine Aufnahme ist erfolgreich, wenn sie das Ziel erreicht oder übertrifft.
* Wertung: Erfolge, Erfolgsquote, Average.

### Highscore-Jagd

* **Aufnahmen:** 1 bis 50. Ziel: möglichst viele Punkte.
* Eine neue beste Aufnahme innerhalb der Session wird angezeigt.
* Wertung: Gesamtpunkte, Average, beste Aufnahme, Anzahl 100+.

## Cricket (Solo-Training)

* Zahlen 20 bis 15, optional **Bull**. Single = 1 Mark, Double = 2, Triple = 3; bei Bull 25 = 1,
  Bullseye = 2.
* **Marks zum Schließen:** 1 bis 9 (Standard 3). Marks über das Schließen hinaus verfallen, ohne
  Gegner gibt es keine Punkte.
* **Zahlen:** frei (jede offene Zahl zählt) oder der Reihe nach (20, 19, … 15, Bull).
* Ende, wenn alles geschlossen ist. Wertung: Darts und Marks pro Aufnahme (MPR).

## 121

* Start bei **Startwert** (Standard 121). Pro Ziel **3, 6 oder 9 Darts** (Standard 9).
* Geschafft: Das nächste Ziel ist eins höher, der geschaffte Wert gilt als „sicher“.
* **Bei Fehlversuch:** zurück zum letzten Erfolg (Standard), gleiches Ziel oder eins runter
  (nie unter den Startwert).
* Bust und **Double-Out** wie beim Checkout-Training, Wurfvorschlag abschaltbar.
* Ende nach der eingestellten Zahl an **Zielen** oder nach einem Checkout von 170.
* Wertung: höchstes Finish, Checkouts, Checkout-Quote. Diese Finishes zählen nur in der eigenen
  Wertung von 121 und in der Doppel-Statistik, nicht zu Rekord „Höchstes Finish“, Checkout-Quote, Zielen
  und Erfolgen (siehe `docs/statistik-und-daten.md`).

## Bob's 27

* Start mit **Startpunkten** (Standard 27). Eine Aufnahme pro Double: D1, D2, … D20, dann
  optional **Bull**.
* Jeder Treffer auf das aktuelle Double bringt dessen Wert (D7 = 14, Bullseye = 50).
* Keine Treffer in der Aufnahme: Der Wert des Doubles wird einmal abgezogen.
* Unter 0 ist das Spiel vorbei, außer **Unter 0 weiterspielen** ist an.
* Wertung: Endstand, Double-Treffer, Double-Quote.

## Drei-Treffer-Runde und Around the World mit Überspringen

Deine zwei eigenen Spiele, siehe [spielregeln.md](spielregeln.md).

## Weitere Spiele

X01-Solo, Halve-It, Catch 40, JDC-Challenge, Shanghai, Darts-Golf, 420, Frustration, Ziel-Wechsel,
Doppel-Leiter, Genau 100, Drei im Bett und Stellen: siehe [trainingsspiele-erweitert.md](trainingsspiele-erweitert.md).
