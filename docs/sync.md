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

* **Sessions** haben eine eindeutige ID; fehlende werden übernommen. Laufende Sessions werden nicht
  abgeglichen. Normale Sessions ändern sich nach dem Abschluss nicht mehr, vorhandene werden dann
  übersprungen.
* **Sessions, die nach dem Abschluss weiterwachsen** (Autodarts Live speichert die Session zwischen und
  schreibt danach weiter, auch mit Korrekturen): Jede Session hat einen Stand (`updatedAt`, Schema
  Version 7). Er ändert sich bei jedem Schreiben in eine abgeschlossene Session, um mindestens eine
  Sekunde. Das Manifest nennt ihn je Session (`sessionRevisions`, ID → Millisekunden; `sessionDarts`
  nennt die Dartzahl der Live-Sessions). Hat ein Gerät den neueren Stand, schickt bzw. holt der Client
  die Session erneut, und das andere Gerät **ersetzt** sie samt allen Würfen: die neueste Fassung
  gewinnt, ohne Stand gilt als älteste, bei gleichem Stand bleibt die vorhandene. Der Fingerabdruck
  für den automatischen Abgleich enthält den größten Stand, neue Darts lösen also einen Abgleich aus.
* **Altbestand:** Die Migration setzt den Stand abgeschlossener Sessions auf ihr Ende. Eine Live-Session,
  die der Hub früher nur mit den ersten Darts bekam, hat dort denselben oder keinen Stand wie die
  vollständige Fassung. Bei gleichem oder fehlendem Stand gewinnt bei Live-Sessions (`autodarts_live`,
  `x01_live`) die mit mehr Darts; so wird die abgeschnittene Kopie beim nächsten Abgleich ersetzt.
* **Ältere Geräte:** Ein Gerät ohne Stände (Manifest ohne `sessionRevisions`) bekommt weiter nur
  fehlende Sessions; unbekannte Felder werden ignoriert. Live-Sessions, die dort schon mit den ersten
  Darts angekommen sind, wachsen erst nach dem Update des Geräts nach.
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
| `POST /manifest` | Manifest des Clients: Profile, Ziele, Trainingspläne, IDs der abgeschlossenen Sessions, Stände (`sessionRevisions`, `sessionDarts`) | Manifest des Hubs; der Hub hat Profile, Ziele und Pläne schon übernommen |
| `POST /push` | Paket mit den Sessions, die dem Hub fehlen oder auf dem Hub älter sind | Ergebnis der Übernahme |
| `POST /pull` | `{"sessions": [IDs]}` | Paket mit diesen Sessions |
| `GET /screen`, `GET /screen/ws` | – | Zweiter Bildschirm, nur lesen (siehe [zweiter-bildschirm.md](zweiter-bildschirm.md)); hier ist der Code auch als `?key=` erlaubt |

Sessions gehen in Teilen zu je 25 (der Client kann das ändern); große Pakete werden im Hintergrund-Isolat
in JSON umgewandelt. Das Paketformat ist dasselbe wie im JSON-Backup (Format-Version 5, bleibt gleich):
Das Feld `updatedAt` einer Session ist neu und optional. Ältere Geräte ohne Trainingspläne
ignorieren das Feld `plans` und gleichen den Rest weiter ab, ebenso ignorieren sie `updatedAt`,
`sessionRevisions` und `sessionDarts`. Ältere Sicherungen ohne `updatedAt` lassen sich weiter importieren.
Der Code schützt nur vor versehentlichen Zugriffen im eigenen Netz; die Verbindung ist nicht
verschlüsselt. Für den Einsatz in fremden Netzen ist der Sync nicht gedacht.

Code: `lib/features/sync/` (Zusammenführen in `data/sync_store.dart`, Server und Client daneben,
Steuerung in `presentation/sync_controller.dart`).
