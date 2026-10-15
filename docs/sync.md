# Sync im Heimnetz

DartLab gleicht Profile, Sessions (mit allen Würfen), Ziele und eigene Trainingspläne zwischen den
Geräten ab, ohne Cloud
und ohne Konto. Ein Rechner ist der **Hub**, normalerweise der Windows-PC am Board. iPhone, iPad und
weitere Rechner sind **Clients** und gleichen mit dem Hub ab, sobald sie im selben WLAN sind.

## Einrichten

1. Am PC: **Optionen › Sync im Heimnetz › Dieses Gerät ist der Hub**. Die App zeigt einen
   sechsstelligen Code und die Adresse(n) des PCs.
2. Auf iPhone/iPad: **Optionen › Sync im Heimnetz › Mit dem Hub abgleichen**, Adresse und Code
   eintragen, **Jetzt abgleichen**. Ist Autodarts schon mit der PC-Adresse eingerichtet, lässt sie
   sich mit einem Tipp übernehmen.
3. Windows fragt beim ersten Start des Hubs, ob DartLab im Netzwerk erreichbar sein darf: für
   **private Netzwerke** erlauben. Ohne die Frage hilft eine eingehende Firewall-Regel für TCP-Port
   3190.

Der Hub nimmt Abgleiche nur an, solange DartLab dort geöffnet ist. Derselbe Hub versorgt auch den
[zweiten Bildschirm](zweiter-bildschirm.md) mit dem Spielstand.

## Wann abgeglichen wird

Clients gleichen automatisch ab: beim Öffnen der App, beim Zurückkehren in die App, kurz nach jeder
Änderung (Spielende, Profil oder Ziel geändert) und alle 5 Minuten. Ist der Hub nicht erreichbar,
zeigt die Karte den Grund; der nächste Versuch kommt von selbst.

Weil alle Clients über den Hub abgleichen, landen Einträge vom iPhone auch auf dem iPad, sobald
beide einmal abgeglichen haben.

## Regeln

* **Sessions** werden nach dem Abschluss nicht mehr verändert. Jede hat eine eindeutige ID; fehlende
  werden übernommen, vorhandene übersprungen. Laufende Sessions werden nicht abgeglichen.
* **Gelöschte Sessions** (Spielverlauf) bleiben ohne Würfe als Markierung stehen. Das Manifest führt sie
  in `sessions` (damit kein Gerät sie für fehlend hält) und als `deletedSessions`; wer sie noch hat,
  löscht sie, wer sie nie hatte, merkt sich nur die Markierung. Löschen gewinnt immer. Geräte mit einer
  älteren Version behalten die Session, schicken sie aber auch nicht zurück.
* **Eigene Trainingspläne** werden wie Ziele behandelt: die neuere Änderung gewinnt, bei gleicher
  Zeit das Löschen bzw. der größere Inhalt. Zwei gleich benannte Pläne bleiben zwei Pläne.
  Plan-Durchläufe (wo man in einem Plan gerade steht) bleiben auf dem Gerät.
* **Profile und Ziele:** die neuere Änderung gewinnt. Gelöschte Profile und Ziele bleiben als
  Markierung erhalten, damit das Löschen auf allen Geräten ankommt und nichts über ein anderes Gerät
  zurückkommt. Ein gelöschtes Profil nimmt seine Sessions auf allen Geräten mit.
* **„Ich“** ist auf allen Geräten dasselbe Profil. Gleich benannte Profile, die auf zwei Geräten
  getrennt angelegt wurden, werden beim ersten Abgleich zu einem.
* Die Uhren der Geräte sollten ungefähr stimmen (automatische Zeit), sonst gewinnt bei
  gleichzeitigen Änderungen am selben Profil die falsche.

## Protokoll

HTTP auf Port 3190 (änderbar), JSON, jede Anfrage mit dem Code im Header `X-DartLab-Key`.

| Anfrage | Inhalt | Antwort |
|---|---|---|
| `GET /hello` | – | `{"app": "dartlab-sync", "version": 1, "keyOk": …, "screen": 1}` |
| `POST /manifest` | Manifest des Clients: Profile, Ziele, Trainingspläne, IDs der abgeschlossenen Sessions | Manifest des Hubs; der Hub hat Profile, Ziele und Pläne schon übernommen |
| `POST /push` | Paket mit den Sessions, die dem Hub fehlen | Ergebnis der Übernahme |
| `POST /pull` | `{"sessions": [IDs]}` | Paket mit diesen Sessions |
| `GET /screen`, `GET /screen/ws` | – | Zweiter Bildschirm, nur lesen (siehe [zweiter-bildschirm.md](zweiter-bildschirm.md)); hier ist der Code auch als `?key=` erlaubt |

Sessions gehen in Teilen zu je 200. Das Paketformat ist dasselbe wie im JSON-Backup (Version 3). Ältere Geräte ohne Trainingspläne
ignorieren das Feld `plans` und gleichen den Rest weiter ab.
Der Code schützt nur vor versehentlichen Zugriffen im eigenen Netz; die Verbindung ist nicht
verschlüsselt. Für den Einsatz in fremden Netzen ist der Sync nicht gedacht.

Code: `lib/features/sync/` (Zusammenführen in `data/sync_store.dart`, Server und Client daneben,
Steuerung in `presentation/sync_controller.dart`).
