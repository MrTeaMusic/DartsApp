# Trainingsspiele (Phase 2): Regeln und Optionen

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
* **Checkout-Vorschlag** (an/aus): zeigt einen Weg mit den verbleibenden Darts, bevorzugt
  wenige Darts, dann gängige Doubles (D20, D16, D8 …).
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
