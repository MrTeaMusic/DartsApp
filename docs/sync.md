# Sync zwischen Geräten

DartLab gleicht Profile, Sessions (mit allen Würfen), Ziele, eigene Trainingspläne, Erfolge und
Challenge-Ergebnisse zwischen den Geräten ab. Es gibt zwei Wege, die sich die Regeln unten teilen:

* **Über die Cloud** ([siehe unten](#über-die-cloud)): ein eigener, kostenloser Speicher bei
  Cloudflare, Ende-zu-Ende verschlüsselt. Kein Rechner muss laufen, und der Abgleich geht auch
  unterwegs.
* **Im Heimnetz**: Ein Rechner ist der **Hub**, normalerweise der Windows-PC am Board. iPhone, iPad und
  weitere Rechner sind **Clients** und gleichen mit dem Hub ab, sobald sie im selben WLAN sind. Ohne
  Cloud und ohne Konto. Nur der Hub liefert auch den [zweiten Bildschirm](zweiter-bildschirm.md).

Alle Geräte eines Bestands sollten denselben Weg nehmen. Die [Regeln](#regeln) unten gelten für beide.

## Über die Cloud

### Einrichten

1. Einmal den Speicher bei Cloudflare anlegen: [cloud/README.md](../cloud/README.md) führt Schritt für
   Schritt durch (Konto, ein Worker, eine kleine Datenbank, etwa 15 Minuten, kein Terminal).
2. Auf dem ersten Gerät: **Optionen › Sync zwischen Geräten › Über die Cloud abgleichen**, Adresse des
   Speichers eintragen, **Neues Geheimnis erzeugen** (26 Zeichen), aufbewahren, **Jetzt abgleichen**.
3. Auf jedem weiteren Gerät dieselbe Adresse und dasselbe Geheimnis eintragen. Die App prüft vor dem
   Speichern, ob unter der Adresse ein DartLab-Speicher antwortet und ob es zum Geheimnis schon einen
   Tresor gibt (Tippfehler im Geheimnis legen so keinen leeren zweiten Tresor an).

Abgeglichen wird wie beim Hub: beim Öffnen, beim Zurückkehren in die App, kurz nach jeder Änderung und
alle 5 Minuten.

### Wie es funktioniert

Der Speicher ist ein reiner Ablageplatz und führt nichts zusammen. Das Zusammenführen macht jedes
Gerät selbst mit denselben Regeln wie unten.

* Aus dem **Geheimnis** (128 zufällige Bit) leitet die App per HKDF-SHA256 zwei Schlüssel ab: ein
  Zugangs-Token, das als `Authorization: Bearer` an den Speicher geht, und den Datenschlüssel. Der
  Speicher bekommt nur das Token (er legt je Tresor die SHA-256-Summe davon an) und kann daraus weder
  Geheimnis noch Datenschlüssel berechnen.
* Je **Session** liegt ein Block im Speicher (Session, ihre Würfe, ihr Profil), dazu eine **Meta**: das
  Manifest mit Profilen, Zielen, Plänen, Erfolgen, Challenges, Session-IDs samt Ständen und Löschmarkierungen.
  Alles wird gepackt (gzip) und mit AES-256-GCM verschlüsselt; der Name des Blocks (`meta`, `s:<uid>`) ist an
  die Verschlüsselung gebunden, ein vertauschter Block fällt beim Öffnen auf.
* Ein Abgleich liest die Meta, übernimmt sie wie ein Hub-Manifest, holt fehlende oder neuere Sessions
  und schickt die, die dem Speicher fehlen oder dort älter sind. Zum Schluss schreibt er die
  zusammengeführte Meta zurück, und zwar nur, wenn sie noch in der gelesenen Version steht
  (Compare-and-set auf einem Versionszähler). Hat ein anderes Gerät dazwischen geschrieben, läuft der
  Abgleich noch einmal (bis zu 4 Durchläufe). Hat sich nichts geändert, wird nichts geschrieben; ein
  Leerlauf kostet eine Leseanfrage.
* Löscht ein Gerät eine Session, verschwindet auch ihr Block aus dem Speicher (die Markierung in der
  Meta bleibt).

### Was der Speicher sieht

Verschlüsselte Blöcke und ihre Größe, den Zeitstempel (Stand) jeder Session und bei
Autodarts-Live-Sessions die Dartzahl (damit er nicht ältere über neuere Stände schreibt), die Zahl der
Sessions, die Tresor-ID (Hash) und wann Anfragen kommen. Keine Namen, Würfe oder Ergebnisse.

### Grenzen

* **Geheimnis verloren = Cloud-Daten unlesbar.** Auf den Geräten bleibt alles. Dann auf einem Gerät ein
  neues Geheimnis erzeugen: Es legt einen neuen Tresor an und lädt alles erneut hoch.
* Das Geheimnis liegt wie der Hub-Code in den Einstellungen des Geräts (nicht im JSON-Backup).
* Die Gratis-Grenzen von Cloudflare (Stand 22.10.2026: 100.000 Worker-Anfragen und 100.000 geschriebene
  Datenbankzeilen pro Tag) reichen für den privaten Gebrauch weit. Bei Überschreitung scheitern
  Anfragen bis 00:00 UTC; die App zeigt den Fehler und versucht es später von selbst.
* Die Meta enthält alle Session-IDs und Stände. Der Speicher nimmt Blöcke bis 1,5 MB (als base64) an; bei
  sehr vielen tausend Sessions könnte die Meta dieses Limit erreichen (nicht gemessen).
* Der erste Abgleich eines großen Bestands braucht einige Sekunden (150 Sessions mit je 300 Darts
  rund 2 Sekunden lokal gemessen; auf dem Handy länger).

Code: `lib/features/sync/data/cloud_*.dart` (Verschlüsselung, Server-Schnittstelle, Abgleich); der Speicher
selbst in `cloud/worker.js` mit Tests unter `cloud/test`.

## Im Heimnetz

### Einrichten

1. Am PC: **Optionen › Sync zwischen Geräten › Dieses Gerät ist der Hub**. Die App zeigt einen
   sechsstelligen Code und die Adresse(n) des PCs.
2. Auf iPhone/iPad: **Optionen › Sync zwischen Geräten › Mit dem Hub abgleichen**, Adresse und Code
   eintragen, **Jetzt abgleichen**. Ist Autodarts schon mit der PC-Adresse eingerichtet, lässt sie
   sich mit einem Tipp übernehmen.
3. Windows fragt beim ersten Start des Hubs, ob DartLab im Netzwerk erreichbar sein darf: für
   **private Netzwerke** erlauben. Ohne die Frage hilft eine eingehende Firewall-Regel für TCP-Port
   3190.

Der Hub nimmt Abgleiche nur an, solange DartLab dort geöffnet ist. Derselbe Hub versorgt auch den
[zweiten Bildschirm](zweiter-bildschirm.md) mit dem Spielstand.

## Wann abgeglichen wird

Clients (Hub und Cloud) gleichen automatisch ab: beim Öffnen der App, beim Zurückkehren in die App, kurz nach jeder
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

## Protokoll im Heimnetz

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
