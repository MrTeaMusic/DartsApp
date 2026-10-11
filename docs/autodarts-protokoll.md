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

**Board Manager 2** hat zusätzlich `/api/system`, `/api/host`, `/api/version`, `/api/config`.
Achtung: Diese Antworten enthalten den Board-API-Key. DartLab ruft sie deshalb nicht ab und
loggt sie nicht.

## Wie DartLab das umsetzt (`AutodartsLocalSource`)

1. WebSocket `/api/events` öffnen, `state`-Nachrichten auswerten.
2. Klappt das nicht: HTTP-Polling auf `/api/state` alle 500 ms.
3. Klappt beides nicht: neuer Versuch nach 1 s, 2 s, 4 s … bis 30 s (plus Zufall).
4. Der erste Zustand nach jeder (Neu-)Verbindung ist die Ausgangslage. Bereits steckende Darts
   werden nicht als neue Würfe gemeldet.
5. Jede Nachricht landet roh im Debug-Bildschirm und optional in
   `Dokumente/DartLab/logs/autodarts-*.jsonl`.

## Offene Punkte (am echten Board klären)

1. **Kommen bei deiner Board-Manager-Version überhaupt Würfe lokal an?** Die ioBroker-Doku sagt, ab
   Autodarts v2.0 liefere die lokale API keine `throws` mehr (nur noch Cloud). Die
   Home-Assistant-Integration von Dennis-Otto wertet dagegen lokal Würfe von Board Manager 2.0.x aus.
   Widersprüchlich, also unbedingt testen. Falls lokal nichts kommt, wäre die Cloud-Anbindung
   (Phase 5, optional) der Weg.
2. Schickt der WebSocket bei jeder Änderung ein `state`, oder nur gelegentlich? Falls nur
   gelegentlich, zusätzlich pollen.
3. Koordinaten: Maßstab und Ausrichtung wie oben beschrieben? Prüfen mit Darts auf T20 (oben),
   D6 (rechts), D3 (unten).
4. Wie sieht eine **Korrektur** am Board aus (Segment eines Darts ändert sich, oder Liste wird neu
   aufgebaut)? DartLab meldet derzeit `DartCorrected`, wenn sich das Feld an einer Position ändert.
5. Wie heißen Bull und Single Bull genau (`bed`, `name`)? DartLab verlässt sich primär auf
   `number` (25) und `multiplier` (1/2).
6. Verlangt der WebSocket bei manchen Versionen eine Anmeldung (HTTP 401/403)?
7. Passen die Befehlspfade (`/api/reset` usw.) zu deiner Version?

## So sammelst du Testdaten

1. Einstellungen → Datenquelle **Autodarts (lokal)**, Host/IP und Port 3180 eintragen.
2. **Rohdaten in Datei mitschreiben** einschalten.
3. Ein paar Aufnahmen werfen: T20, D6, D3, Bull, 25, einen Dart daneben, einmal Darts ziehen,
   einmal am Board korrigieren.
4. Debug-Bildschirm → **Alles kopieren** oder die `.jsonl`-Datei schicken. Damit schärfen wir das
   Mapping nach.
