# Zweiter Bildschirm

Ein Tablet, ein zweites Handy oder ein Fernseher zeigt groß den Spielstand von dem, was gerade am
PC läuft: Trainingsspiel, X01-Match (auch gegen den Bot und im Turnier) oder das Mitschreiben vom
Board. Der PC ist dafür der Sync-Hub (siehe [sync.md](sync.md)); der zweite Bildschirm liest nur mit.

## Einrichten

1. Am PC: **Optionen › Sync im Heimnetz › Dieses Gerät ist der Hub**. Die Karte zeigt Code, Adresse
   und, sobald einer zuschaut, „Zweiter Bildschirm: 1 Gerät verbunden“.
2. Auf Tablet oder Handy: unter **Optionen › Sync im Heimnetz** Adresse und Code des PCs eintragen
   und **Zweiter Bildschirm** antippen. Ist das Gerät als Client eingerichtet, gibt es den Eintrag
   auch auf der Startseite. Der Sync selbst muss dafür nicht eingeschaltet sein; Adresse und Code
   reichen.
3. Gerät quer hinstellen. Der Bildschirm bleibt an, solange die Ansicht offen ist.

**Fernseher:** iPad oder iPhone per AirPlay spiegeln oder per HDMI-Adapter anschließen; die Ansicht
füllt dann den Fernseher. Alternativ kann jeder Browser im Heimnetz (Smart-TV, Laptop) die
schlichte Seite `http://<PC-Adresse>:3190/screen` öffnen; sie fragt einmal nach dem Code. Die
genaue Adresse steht am PC auf der Sync-Karte.

## Was angezeigt wird

* Titel und Untertitel (z. B. „501 · X01-Match“, Format und Leg; im Turnier Turniername und Runde)
* Spieler mit Restpunkten bzw. Fortschritt, Legs/Sets, Average, wer gerade wirft, Sieger
* aktuelle Aufnahme (drei Felder mit Summe, Bust), letzte Aufnahme, Checkout-Weg
* die letzten Treffer auf der Scheibe, Statistikzeilen (Average, Darts, Quoten je nach Spiel)
* Hinweise wie „Bust“, „Leg gewonnen“, „Bitte Darts ziehen“
* „Warte auf Spiel am PC“, wenn nichts läuft, und „Verbindung verloren“ mit dem letzten Stand
  abgeblendet im Hintergrund

Läuft mehreres, gilt: Match vor Trainingsspiel vor Mitschreiben vom Board.

## Verbindung

Die Ansicht verbindet sich von selbst und versucht es nach einer Unterbrechung nach 1, 2, 4 und
dann alle 5 Sekunden erneut; **Erneut verbinden** startet sofort einen Versuch. Bei falschem Code,
einem fremden Gerät unter der Adresse oder einem PC mit älterer DartLab-Version zeigt sie den Grund
und versucht es nur noch alle 10 Sekunden.

## Technik

**Transport: WebSocket** auf dem vorhandenen Sync-Server (gleicher Port, gleicher Code).
Begründung: Der Hub schickt jede Änderung sofort (kein Abfrage-Takt), beide Seiten erkennen über
Pings eine tote Verbindung binnen Sekunden, `dart:io` kann WebSocket ohne Zusatzpaket, und jeder
Browser ebenfalls, was die `/screen`-Seite klein hält. Server-Sent Events hätten auf der App-Seite
einen eigenen Parser und keine Erkennung toter Verbindungen in Gegenrichtung gebraucht.

| Anfrage | Zweck |
|---|---|
| `GET /hello` | enthält zusätzlich `"screen": 1`; fehlt das Feld, ist der PC zu alt |
| `GET /screen/ws` (WebSocket) | Stand als JSON-Text, bei jeder Änderung |
| `GET /screen` | schlichte Browserseite (HTML, ohne Code: nur Code-Eingabe) |

* Code im Header `X-DartLab-Key`. Weil Browser bei WebSocket keine eigenen Header setzen können,
  gilt nur für die beiden `/screen`-Pfade auch `?key=<Code>`. Alle anderen Anfragen brauchen
  weiterhin den Header.
* **Nur lesen:** `/screen` kennt nur `GET`; ein Viewer, der etwas über den WebSocket schickt, wird
  getrennt. Höchstens 8 Viewer gleichzeitig.
* **Drosselung:** Änderungen werden 80 ms gesammelt und nur verschickt, wenn sich das JSON
  geändert hat. Alle 2 Sekunden wird der Stand neu berechnet (fängt Änderungen ohne eigenes
  Ereignis ab), der Server pingt alle 5 Sekunden.
* **Keine Arbeit ohne Zuschauer:** Erst wenn sich ein Viewer verbindet, hängt sich der Hub an
  Match, Training und Mitschreiben; beim letzten Trennen hängt er sich wieder ab. Er hält dabei
  keinen dieser Zustände am Leben (schwache Listener; das Mitschreiben wird über einen eigenen
  Spiegel gelesen, damit es nicht ungewollt neu startet).
* Die Browserseite setzt die Inhalte nur als Text (kein HTML aus dem Stand), hat eine strenge
  Content-Security-Policy, `no-store` und keinen Referrer.
* Die Beschriftungen kommen fertig auf Deutsch vom Hub, damit Ansicht und Browserseite nichts über
  die Spiele wissen müssen.

JSON (Version 1, leere Felder entfallen), gekürzt:

```json
{"v": 1, "kind": "match", "title": "501 · X01-Match", "subtitle": "Best of 3 Legs · Leg 2",
 "status": "Ben ist dran",
 "players": [{"name": "Ben", "score": "141", "active": true, "legs": 1, "average": "62,4"},
             {"name": "Bot", "score": "220", "bot": true, "legs": 0}],
 "visit": ["T20", "T19"], "visitScore": 117, "route": ["T20", "T7", "D10"],
 "lastVisit": ["20", "5", "1"], "lastVisitScore": 26,
 "hits": [{"s": "T20", "x": 0.012, "y": -0.598}], "banner": "Bust", "bannerTone": "negative"}
```

`kind` ist `idle`, `training`, `match` oder `live`. Ohne laufendes Spiel: `{"v": 1, "kind": "idle"}`.

Bildschirm-an hält das Paket `wakelock_plus`, nur solange die Ansicht offen ist.

## Noch nicht im echten Netz getestet

Alles ist mit Tests auf einem echten lokalen Server geprüft, aber noch nicht in Bens Heimnetz:

* **Windows-Firewall:** Der Hub-Port 3190 muss für private Netzwerke offen sein (wie beim Sync).
* **iOS:** Beim ersten Verbinden fragt iOS nach dem Zugriff auf das lokale Netzwerk; ohne „Erlauben“
  bleibt es bei „Verbindung verloren“ (zurücksetzen unter Einstellungen › Datenschutz › Lokales
  Netzwerk).
* Bildschirm-an auf echten Geräten, AirPlay/HDMI und die Browserseite auf einem Smart-TV.
* Für macOS/iOS muss nach dem neuen Paket einmal `pod install` laufen (macht `flutter build` mit).

Code: `lib/features/second_screen/` (Zustand und JSON in `domain/screen_state.dart`, Server-Teil in
`data/screen_hub.dart`, Browserseite in `data/screen_page.dart`, Verbindung in
`data/screen_client.dart`, Ansicht in `presentation/second_screen_page.dart`).
