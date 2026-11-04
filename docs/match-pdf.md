# Match als PDF

Die ausführliche Auswertung eines einzelnen Matches (oder Trainings) als PDF, zum Verschicken. Wer
es liest, braucht weder die App noch ein Konto.

## Wo

In der Detailansicht einer Session (Verlauf › Session antippen) oben rechts das PDF-Symbol. Es
gibt es für jede Session mit Würfen, nicht fürs Checkout-Quiz.

Windows/macOS/Linux: Speichern-Dialog. iPhone/iPad: Ablage im Ordner der App (Dateien-App).

## Inhalt (wie in der Detailansicht)

1. Kopf: Gegner bzw. Spiel, Datum, Ergebnis-Status, Format, Darts, Dauer, Profil.
2. Matches: Endstand und Kennzahlen beider Spieler (Legs, Average, First 9, Checkout-Quote, höchstes
   Finish, bestes Leg, 100+/140+/180, Darts) und das Haus-Elo, falls das Match gewertet wird.
   Training: die Kennzahlen des Spiels.
3. Doppel: Doppelquote je Spieler und auf welche Doppel geworfen wurde.
4. Legs: je Leg Sieger und Checkout, Verlauf des Rests beider Spieler und die Tabelle aller
   Aufnahmen mit Wurfbild, Rest, verpassten Doppeln. 100 und mehr gelb, Checkout grün, Bust rot.
   Spiele ohne Rest-Verlauf zeigen stattdessen die Aufnahmenliste.
5. Punkte je Aufnahme (bzw. Treffer, Marks, Stand) und, falls Positionen gespeichert sind, das
   Wurfbild der Darts auf dem Board.

## Code

- `lib/features/history/export/session_pdf.dart`: baut das Dokument aus `SessionDetail` und
  `LegBoards` (Paket `pdf`, Schrift Inter aus den Assets für Umlaute und „Ø“).
- `lib/features/history/export/session_pdf_export.dart`: Schrift laden, erzeugen, über
  `BackupFiles.saveBytes` speichern, Meldung zeigen.
- Test: `test/features/history/session_pdf_test.dart`. Mit `PDF_OUT_DIR=/pfad` schreibt er die
  erzeugten PDFs dorthin, zum Anschauen.
