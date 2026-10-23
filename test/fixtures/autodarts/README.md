# Autodarts-Mitschnitte für Tests

Jede `.jsonl`-Datei hier wird von `test/features/dart_source/recording_and_diagnostics_test.dart` durch
den Mapper gespielt. Der Test prüft, dass es keine Mapping-Warnungen gibt und dass Feld und
Koordinaten bei mindestens 90 % der Darts zusammenpassen.

* `synthetisch-community-format.jsonl` ist **künstlich** erzeugt, nach dem Format aus
  `docs/autodarts-protokoll.md`. Er beweist nichts über ein echtes Board.
* `board-manager-2.0.2-windows.jsonl` ist **echt**: Bens Board, Board Manager 2.0.2 unter
  Windows, WebSocket, 11.10.2026. Zwei Aufnahmen: T20, T20, T5 und S12, daneben (M12), S20.
* Echte Mitschnitte (Debug-Bildschirm › Alles kopieren, oder die Datei aus
  `Dokumente/DartLab/logs`) einfach hier ablegen. Dann laufen sie bei jedem Test mit.
* `match-stats-501-online.json` ist eine **echte, anonymisierte** `/stats`-Antwort der Autodarts-Cloud
  (Online-Match 501, Double-Out, 3:2 in fünf Legs, 22.10.2026). Namen sind „Ben“ und „Gegner“, alle Ids
  erfunden, Avatar und Nutzerdaten entfernt; Würfe, Felder, Koordinaten und Zeiten sind unverändert.
  Der Import-Test ist `test/features/autodarts_import/autodarts_real_format_test.dart` (kein Mitschnitt des
  Board Managers, wird vom Mapper-Test oben nicht gelesen). Die Original-Datei liegt nicht im Repository.
