# Statistiken, Ziele, Profile und Daten

## Statistik

Alle Werte gelten für das **aktive Profil** und den gewählten **Zeitraum** (7, 30, 90 Tage oder alles),
optional gefiltert auf ein Spiel. Grundlage sind abgeschlossene Sessions und ihre gezählten Darts;
Darts, die nach einem Bust oder Checkout noch fielen, zählen nicht.

| Kennzahl | Berechnung |
|---|---|
| 3-Dart-Average | Punkte pro Dart × 3, nur aus T20-Training, Score-Ziel und Highscore-Jagd. In Spielen wie Around the Clock wirft man auf Felder statt auf Punkte, das würde den Wert verfälschen. |
| Checkout-Quote | geschaffte Versuche / alle Versuche aus Checkout-Training und 121 |
| Double-Quote | Treffer auf das aktuelle Double / Darts in Bob's 27 |
| Triple-Quote | Triples auf die Zielzahl / Darts im T20-Training |
| Trainingstage | Kalendertage mit mindestens einer Session |
| Serie | Tage am Stück mit Training. Sie läuft weiter, wenn gestern trainiert wurde und heute noch nicht. |
| Verlauf | Hauptkennzahl des Spiels je Session (siehe unten) |
| Heatmap | Position jedes gezählten Darts. Ohne Koordinaten (manuelle Eingabe) liegt der Dart in der Mitte seines Feldes. |

Hauptkennzahl je Spiel (für Verlauf und Bestwert):

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

## Ziele

Pro Art gibt es ein Ziel je Profil. Antippen ändert oder löscht es.

* Sessions pro Woche, Darts pro Woche (Montag bis Sonntag)
* Tage am Stück (aktuelle Serie)
* 3-Dart-Average, Checkout-Quote, Double-Quote (jeweils letzte 30 Tage)

## Profile

Unter Optionen › Profile. Jedes Spiel wird dem aktiven Profil zugeordnet, Statistik, Ziele und
„Zuletzt gespielt“ zeigen nur dessen Daten. Löschen entfernt alle Sessions, Würfe und Ziele des
Profils; das letzte Profil lässt sich nicht löschen.

## Export und Import

Unter Optionen › Daten. Auf Windows und macOS öffnet sich ein Speichern-Dialog. Auf iOS landen die
Dateien im Dokumente-Ordner der App (Dateien-App › Auf meinem iPhone › DartLab).

* **Backup (JSON):** alle Profile, Sessions, Würfe (mit Rohdaten) und Ziele. Format
  `{"format": "dartlab-backup", "version": 1, …}`.
* **Import:** führt ein Backup mit den vorhandenen Daten zusammen. Profile werden über den Namen
  zugeordnet, fehlende angelegt. Sessions mit gleichem Profil, Spiel, Startzeit und Seed gelten als
  vorhanden und werden übersprungen, ein zweiter Import derselben Datei ändert also nichts.
* **Würfe als CSV / Sessions als CSV:** Komma-getrennt, UTF-8 mit BOM, Dezimalpunkt, Zeiten im
  ISO-Format. Die Sessions-Tabelle hat eine Spalte je Kennzahl.
