# Autodarts: Was wir über die lokale Schnittstelle wissen

Stand: 11.10.2026. Es gibt **keine offizielle Dokumentation**. Alles hier stammt aus dem Quellcode von
Community-Projekten, **nicht** aus Tests an einem echten Board. Das Mapping in
`lib/features/dart_source/data/autodarts_state_mapper.dart` gilt als **ungetestet**, bis es mit
Mitschnitten vom echten Board abgeglichen ist.

## Quellen

| Projekt | Was es nutzt |
|---|---|
| [Dennis-Otto/ha-autodarts](https://github.com/Dennis-Otto/ha-autodarts) (Home Assistant, aktiv 2026) | Lokal: `GET /api/state`, WebSocket `/api/events`, Board Manager 1 und 2 |
| [Mastershort/ha-autodarts-local](https://github.com/Mastershort/ha-autodarts-local) | Lokal: Polling `GET /api/state` |
| [inventwo/ioBroker.autodarts](https://github.com/inventwo/ioBroker.autodarts) | Lokal `GET /api/state` (vor v2), sonst Cloud |
| [lbormann/darts-caller](https://github.com/lbormann/darts-caller) | Cloud-WebSocket `wss://api.autodarts.io/ms/v0/subscribe`, lokal nur Befehle |
| [creazy231/tools-for-autodarts](https://github.com/creazy231/tools-for-autodarts) | Browser-Erweiterung, liest den Cloud-WebSocket der Webseite mit |

## Was mehrere Projekte übereinstimmend nutzen

**HTTP `GET http://<host>:3180/api/state`** liefert den Board-Zustand:

```json
{
  "connected": true,
  "running": true,
  "status": "Throw",
  "event": "Throw detected",
  "numThrows": 2,
  "throws": [
    {
      "segment": {"name": "T20", "number": 20, "bed": "Triple", "multiplier": 3},
      "coords": {"x": 0.012, "y": 0.611}
    }
  ]
}
```

* `throws` enthält immer **alle Darts der laufenden Aufnahme**, nicht nur den neuesten. Neue Darts
  erkennt man am Vergleich mit dem vorherigen Zustand.
* `bed`-Werte im Code der Projekte: `Single`, `SingleInner`, `SingleOuter`, `Double`, `Triple`, `Outside`.
* Status-/Event-Texte: `Throw`, `Throw detected`, `Takeout started`, `Takeout in progress`,
  `Takeout finished`, `Manual reset`, `Started`, `Stopped`, `Calibration started`, `Calibration finished`.
* Koordinaten (laut Kommentar in ha-autodarts `positions.py`): normiert, **1.0 = Außenkante des
  Double-Rings (170 mm)**, **y zeigt zur 20**. Werte bis etwa 3.0 kommen vor (Darts neben dem Board).

**WebSocket `ws://<host>:3180/api/events`** (ha-autodarts): Nachrichten der Form
`{"type": "...", "data": {...}}` mit den Typen `state`, `motion_state`, `cam_state`, `stats`,
`cam_stats`. `state` hat dasselbe Format wie `/api/state`. Keine Anmeldung oder Subscription nötig.

**Befehle** (ha-autodarts): `PUT /api/start`, `PUT /api/stop`, `POST /api/reset`, `POST /api/restart`,
`POST /api/config/calibration/auto`. Ältere Versionen (darts-caller): `PUT /api/detection/start|stop`.

**Ungeprüft:** `POST /api/restart` und `POST /api/config/calibration/auto` stammen nur aus der Home-Assistant-Integration
und sind am Board Manager 2.0.2 **noch nicht bestätigt**. DartLab nutzt sie für die Board-Hilfe (siehe unten) und
zeigt dort den HTTP-Status, den das Board antwortet.

**Board Manager 2** hat zusätzlich `/api/system`, `/api/host`, `/api/version`, `/api/config`.
Achtung: Diese Antworten enthalten den Board-API-Key. DartLab ruft sie deshalb nicht ab und
loggt sie nicht.

## Neueres Format (Mitschnitt vom 29.10.2026)

Nach einer Aktualisierung des Board Managers kam ein anderes Format an (Mitschnitt:
`test/fixtures/autodarts/board-manager-neues-format-2026-10-29.jsonl`, läuft als Regressionstest). Welche Version das ist,
steht nicht im Mitschnitt. Der WebSocket verpackt es weiter als `{"type": "state", "data": {...}}`:

* Wurf-Felder flach statt verschachtelt: `segmentName` (z. B. `"S12"`), `segmentNumber`, `multiplier`, `bed`,
  `coordsX`, `coordsY`, dazu `bouncer`, `failed`, `method`. Kein Objekt `segment`, kein Objekt `coords`.
* `event` und `status` in camelCase: `throwDetected`, `takeoutStarted`, `takeoutFinished`, `takeoutInProgress`,
  `throw`, `takeout`. Kein `numThrows`.
* `event` bleibt nach einem Takeout stehen, bis der nächste Wurf es ändert: der erste Dart danach kommt noch mit
  `event: "takeoutFinished"`. Das darf den Dart nicht wieder löschen.
* Koordinaten wie zuvor (y zur 20, x nach rechts). Fehlwürfe und Bull in diesem Format sind **nicht** mitgeschnitten und
  deshalb ungeprüft.

DartLab liest beide Formate (`AutodartsStateMapper.parseThrowSegment` und `parseThrowCoords`).

## Bestätigt am echten Board (Board Manager 2.0.2, Windows, 11.10.2026)

Mitschnitt: `test/fixtures/autodarts/board-manager-2.0.2-windows.jsonl` (läuft als Regressionstest).

* **Würfe kommen lokal an.** Der WebSocket `/api/events` schickt bei jedem Dart und beim Takeout
  eine `state`-Nachricht mit der vollständigen `throws`-Liste. Die Cloud wird dafür nicht gebraucht.
* Ablauf einer Aufnahme: `Throw detected` (numThrows 1, 2, 3; beim dritten `status: "Takeout"`),
  dann `Takeout started` / `Takeout in progress`, dann `Takeout finished` mit `numThrows: 0`.
* **Ohne Dart im Board fehlt das Feld `throws` ganz** (nicht leere Liste). Das ist normal.
* Ohne Änderung am Board sendet der WebSocket nichts. Stille heißt nicht Fehler.
* Jeder Wurf hat `segment` (`name`, `number`, `bed`, `multiplier`), `coords` (`x`, `y`) und `bouncer`.
* Daneben: `bed: "Outside"`, `multiplier: 0`, `name` z. B. `"M12"` (Zahl des Sektors). DartLab wertet das als Fehlwurf.
* `bed` unterscheidet `SingleInner` und `SingleOuter`.
* **Koordinaten bestätigt:** Mitte (0, 0), Radius 1 = Außenkante Double-Ring, y zeigt zur 20,
  x nach rechts (T5 und S12 haben negatives x). 6 von 6 Darts passen, Kalibrierung nicht nötig.

Noch nicht gesehen: Bull/25, Doubles, eine Korrektur am Board, ein Dart mit `bouncer: true`.

## Autodarts Live (Online-Matches mitschreiben)

Siehe `docs/autodarts-live.md`. Der Modus hört nur zu: Solange er läuft, verweigert die Quelle jeden Befehl
(`listenOnly`), damit kein Start/Stop/Reset ein laufendes Online-Match stört.

## Board-Hilfe (Befehle bei hängendem Board)

Menü „Board-Hilfe“ in Live-Bildschirm, Spielansicht und Board (Details: `docs/autodarts-live.md`):

| Eintrag | Befehl | Status |
|---|---|---|
| Neu kalibrieren | `POST /api/config/calibration/auto` | **nicht bestätigt** (BM 2.0.2) |
| Dartboard stoppen | `PUT /api/stop` | nicht bestätigt |
| Dartboard starten | `PUT /api/start` | nicht bestätigt |
| Refresh | `POST /api/restart`, bei 404/405 ersatzweise `POST /api/reset` | nicht bestätigt |

Jede Aktion fragt vorher nach und zeigt danach den HTTP-Status des Boards (oder den Fehlertext). 2xx heißt
„angenommen“, nicht „hat gewirkt“. Antwort-Bodys werden nicht gelesen und nicht geloggt. Die Sperre
`listenOnly` bleibt für Automatisches bestehen; nur ein Knopfdruck (`userInitiated`) umgeht sie.

## Wie DartLab das umsetzt (`AutodartsLocalSource`)

1. WebSocket `/api/events` öffnen, `state`-Nachrichten auswerten.
2. Klappt das nicht: HTTP-Polling auf `/api/state` alle 500 ms.
3. Klappt beides nicht: neuer Versuch nach 1 s, 2 s, 4 s … bis 30 s (plus Zufall).
4. Der erste Zustand nach jeder (Neu-)Verbindung ist die Ausgangslage. Bereits steckende Darts
   werden nicht als neue Würfe gemeldet.
5. Jede Nachricht landet roh im Debug-Bildschirm und optional in
   `Dokumente/DartLab/logs/autodarts-*.jsonl`.

## Offene Punkte (am echten Board klären)

1. ~~Kommen bei deiner Board-Manager-Version überhaupt Würfe lokal an?~~ **Ja, bei 2.0.2 bestätigt**
   (siehe oben). Die ioBroker-Doku behauptet für v2.0+ das Gegenteil; das trifft hier nicht zu.
2. ~~Schickt der WebSocket bei jeder Änderung ein `state`?~~ **Ja**, bei jedem Dart und Takeout.
3. ~~Koordinaten: Maßstab und Ausrichtung?~~ **Bestätigt**, keine Kalibrierung nötig. Die
   Kalibrierung bleibt für andere Board-Manager-Versionen.
4. Wie sieht eine **Korrektur** am Board aus (Segment eines Darts ändert sich, oder Liste wird neu
   aufgebaut)? DartLab meldet derzeit `DartCorrected`, wenn sich das Feld an einer Position ändert.
5. Wie heißen Bull und Single Bull genau (`bed`, `name`)? DartLab verlässt sich primär auf
   `number` (25) und `multiplier` (1/2).
6. Verlangt der WebSocket bei manchen Versionen eine Anmeldung (HTTP 401/403)? Bei 2.0.2 nicht.
7. Passen die Befehlspfade (`/api/reset`, `/api/restart`, `/api/config/calibration/auto` usw.) zu deiner Version? Die Board-Hilfe zeigt dafür den HTTP-Status; 404/405 heißt „Pfad unbekannt“.
8. Was bedeutet `bouncer: true` (abgeprallter Dart)? DartLab ignoriert das Feld derzeit und zählt das gemeldete Feld.

## Werkzeuge in DartLab

**Verbindungstest** (Optionen › Autodarts › „Verbindung testen“) prüft nacheinander:

| Prüfung | Was passiert |
|---|---|
| Board Manager erreichbar | `GET /api/state` mit Zeitlimit. Bei Fehlern ein Hinweis: abgelehnt (läuft der BM? Port?), Zeitüberschreitung (IP, Netz, iOS „Lokales Netzwerk“), Adresse unbekannt, Anmeldung verlangt. |
| Statusformat erkannt | Antwort ist JSON mit den erwarteten Feldern. |
| Würfe im Status enthalten | Gibt es das Feld `throws`? Fehlt es, liefert die Version Würfe vermutlich nur über die Cloud. |
| Erkennung läuft | `running` ist `true` (der `status` wird mit angezeigt). |
| Live-Verbindung | WebSocket `/api/events` öffnen und kurz auf eine Nachricht warten. Ohne Nachricht nutzt DartLab automatisch Polling. |

Der Test liest nur `/api/state` und `/api/events`. `/api/system` und `/api/config` werden nie
abgefragt oder mitgeschrieben, weil dort der API-Schlüssel des Boards steht.

**Mitschnitt prüfen** (Debug-Bildschirm › „Mitschnitt prüfen“ für die aktuellen Rohdaten,
„Datei prüfen…“ für eine `.jsonl`-Datei) zählt Statusmeldungen, Darts, Takeouts und Korrekturen,
zeigt die Nachrichtentypen und vergleicht bei jedem Dart das gemeldete Feld mit dem Feld, das
sich aus den Koordinaten ergibt („Koordinaten passen zum Feld“).

**Koordinaten-Kalibrierung:** Passen die Koordinaten schlecht, probiert die Prüfung alle acht
Ausrichtungen (Achsen tauschen, x/y spiegeln) und schätzt den Maßstab (z. B. Millimeter statt
Radius 1). Ist eine Variante deutlich besser, erscheint sie als Vorschlag mit „Übernehmen“.
Die aktive Kalibrierung steht unter Optionen › Autodarts und lässt sich dort zurücksetzen.
Die Kalibrierung betrifft nur die Position (Heatmap, Treffer-Animation). Gezählt wird immer das
Feld, das Autodarts meldet.

**Regressionstests:** Jede `.jsonl`-Datei in `test/fixtures/autodarts/` wird bei `flutter test`
ausgewertet und muss ohne Mapping-Warnung durchlaufen. Echte Mitschnitte dort ablegen.

## So sammelst du Testdaten

1. Einstellungen → Datenquelle **Autodarts (lokal)**, Host/IP und Port 3180 eintragen.
2. **Rohdaten in Datei mitschreiben** einschalten.
3. Ein paar Aufnahmen werfen: T20, D6, D3, Bull, 25, einen Dart daneben, einmal Darts ziehen,
   einmal am Board korrigieren.
4. Debug-Bildschirm → **Mitschnitt prüfen**. Stimmen Dart-Anzahl und Felder, passt das Mapping.
5. Die `.jsonl`-Datei oder **Alles kopieren** schicken. Damit schärfen wir das Mapping nach, und
   die Datei wird ein Regressionstest.
