# Match teilen (`.dartlab`-Datei)

Ein Match (oder Training) als Datei weitergeben. Beim Empfänger öffnet sie sich in DartLab oder
DartLab Lite und zeigt dieselbe Ansicht wie im eigenen Verlauf, nur zum Ansehen: Die Datei wird
nur im Speicher gelesen. Nichts davon landet in der Datenbank, im Abgleich oder in der
Statistik des Empfängers.

## Teilen

Detailansicht einer Session › Teilen-Symbol oben rechts:

* **Als DartLab-Datei teilen**: iPhone, iPad und Android öffnen das Teilen-Menü (WhatsApp, Mail,
  AirDrop …). Windows, macOS und Linux zeigen den Speichern-Dialog.
* **Als PDF exportieren**: wie bisher, siehe `match-pdf.md`.

Dateiname: `dartlab-ben-vs-robo-60-2026-11-05.dartlab`.

## Öffnen

| Plattform | Wie |
|---|---|
| Windows | Doppelklick. DartLab trägt `.dartlab` beim Start selbst für den Benutzer ein (HKCU, ohne Administrator). Wird der Ordner verschoben, stimmt der Eintrag nach dem nächsten Start wieder. |
| macOS | Doppelklick oder „Öffnen mit“ (Dokumenttyp in `Info.plist`). |
| iPhone/iPad | In Mail, WhatsApp, Nachrichten, Dateien antippen › „In DartLab öffnen“ (Dokumenttyp in `Info.plist`). |
| Android (Lite) | Datei antippen oder Teilen › DartLab Lite. WhatsApp liefert nur einen content-Link; die App liest die Datei selbst. |
| Linux | Pfad als Startargument (`dartlab datei.dartlab`). Keine Zuordnung im Dateimanager. |
| Überall | Verlauf › Symbol „Geteilte Datei öffnen“ wählt die Datei von Hand. |

Lite zeigt die Datei auch vor der Einrichtung (Route `/geteilt`).

## Format

JSON, UTF-8:

```json
{ "format": "dartlab-match", "version": 1, "app": "0.10.0", "createdAt": "…", "player": "Ben",
  "elo": {"before": 1486, "after": 1499}, "session": {…}, "throws": […] }
```

`session` und `throws` sind die gespeicherten Zeilen, ohne interne Nummern (`id`, `playerId`,
`sessionId` sind 0) und ohne Rohdaten der Würfe (`rawJson`). Der Empfänger baut die Ansicht daraus mit
demselben Code wie der Verlauf. Die Elo ist die des Absenders. Eine neuere `version` zeigt den Hinweis
„DartLab ist zu alt“, eine fremde oder kaputte Datei „Datei lässt sich nicht öffnen“.

Medientyp `application/vnd.dartlab.match+json`, Apple-Typ `de.dartlab.match`.

## Code

* `lib/features/history/share/shared_match.dart`: Format, Lesen, Schreiben.
* `lib/features/history/share/shared_match_opener.dart`: nimmt Dateien vom System an (Startargument,
  Kanal `de.dartlab/open_file` mit `ready` und `open`).
* `lib/features/history/share/windows_file_type.dart`: Dateizuordnung unter Windows.
* `lib/features/history/export/session_file_export.dart`: Teilen bzw. Speichern.
* `lib/features/history/presentation/shared_match_screen.dart` und `SessionDetailBody` in
  `session_detail_screen.dart`: die Ansicht.
* Nativ: `android/…/MainActivity.kt` + `AndroidManifest.xml`, `ios/Runner/{AppDelegate,SceneDelegate}.swift`
  + `Info.plist`, `macos/Runner/AppDelegate.swift` + `Info.plist`.
* Tests: `test/features/history/shared_match_test.dart`.

Das Öffnen per Doppelklick und Teilen-Menü hängt am Betriebssystem und ist nur auf echten Geräten
prüfbar (Dart-Seite und Datei sind getestet).
