# Online-Statistik als PDF

Die gesamte Online-Statistik als PDF, zum Verschicken (z. B. an einen Freund). Die Datei braucht
keine App und kein Konto zum Lesen.

## Wo

- **Statistik > Online > „Als PDF exportieren“**: Statistik für den gewählten Zeitraum.
- **Match-Ansicht eines Online-Matches > PDF-Symbol oben**: Statistik über alle Zeiträume, das
  Match steht vorn mit seinen Legs und ist in der Match-Liste markiert.

Windows/macOS/Linux: Speichern-Dialog. iPhone/iPad: Ablage im Ordner der App (Dateien-App).

## Inhalt

1. Kopf mit Profil, Zeitraum und Erstelldatum, Kennzahlen (Matches, Darts, Average, First 9,
   Checkout-Quote, höchstes Finish, 100+/180, Legs).
2. Nur beim Match-Export: das Match mit Gegner, Kennzahlen und einer Zeile je Leg.
3. Verlauf von Average, First 9 und Checkout-Quote (je Woche oder je Match, wie im Reiter).
4. Training gegen Match, Doppel im Vergleich und Punkteverteilung (nur mit genug Daten, Regeln wie
   im Reiter „Online“).
5. Alle Matches im Zeitraum als Tabelle.

## Code

- `lib/features/stats/export/online_stats_pdf.dart`: baut das Dokument aus `OnlineReport` und
  `OnlineComparison` (Paket `pdf`, Schrift Inter aus den Assets für Umlaute und „Ø“).
- `lib/features/stats/export/online_pdf_export.dart`: Schrift laden, erzeugen, über
  `BackupFiles.saveBytes` speichern, Meldung zeigen.
- Test: `test/features/stats/online_stats_pdf_test.dart` (setzt man `PDF_OUT=/pfad/probe.pdf`,
  schreibt der Test das Beispiel-PDF dorthin).
