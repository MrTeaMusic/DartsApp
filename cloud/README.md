# DartLab Cloud-Sync: eigener Speicher bei Cloudflare

Diese Anleitung ist für dich, Ben. Du brauchst **kein Terminal** und keine Programmierkenntnisse. Alles passiert im Browser auf der Cloudflare-Webseite. Plane etwa 15 Minuten ein.

Der ganze Server besteht aus einer einzigen Datei: `worker.js` (in diesem Ordner).

---

## 1. Was der Server tut (und was nicht)

Der Server ist ein **Schließfach-Raum**. Deine App legt dort verschlüsselte Pakete ab und holt sie wieder ab, zum Beispiel damit mehrere Geräte denselben Stand haben.

- Die Verschlüsselung passiert **in der App**, bevor etwas hochgeladen wird. Der Schlüssel verlässt dein Gerät nie.
- Der Server bekommt nur unlesbaren Datensalat ("Ciphertext") und kann ihn nicht öffnen.

**Was der Server sieht:**

- die verschlüsselten Pakete und wie groß sie sind,
- den Zeitstempel jeder Session und bei Live-Sessions die Anzahl der Darts,
- wann zuletzt ein Live-Paket (siehe Abschnitt 3) kam und wie groß es ist, aber nie, was drinsteht,
- eine **Tresor-ID**. Das ist eine Art Fingerabdruck (Hash) deines Zugangsschlüssels. Aus der ID lässt sich der Schlüssel nicht zurückrechnen,
- wann und wie oft Anfragen kommen.

**Was der Server nie sieht:**

- Klartext: keine Spielernamen, keine Würfe, keine Ergebnisse,
- deinen Zugangsschlüssel selbst. Er wird weder gespeichert noch in Protokolle geschrieben.

---

## 2. Einrichten im Cloudflare-Dashboard

Die Menünamen bei Cloudflare ändern sich manchmal ein wenig. Wenn etwas anders heißt: such den Punkt, der am ähnlichsten klingt.

### Schritt 1: Konto anlegen

1. Öffne <https://dash.cloudflare.com/sign-up> und lege ein kostenloses Konto an (E-Mail und Passwort, E-Mail bestätigen).
2. Du brauchst keine Bezahldaten und keine eigene Internet-Adresse (Domain).

### Schritt 2: Den Worker anlegen

Ein "Worker" ist ein kleines Programm, das bei Cloudflare läuft.

1. Links im Menü: **Workers & Pages** (bei neuen Konten manchmal unter "Compute").
2. **Create** (Erstellen) und dann **Hello World** (Worker) wählen.
3. Als Namen **`dartlab-sync`** eingeben und **Deploy** klicken.
4. Auf der nächsten Seite auf **Edit code** (Code bearbeiten) klicken. Der Editor öffnet sich.

### Schritt 3: Den Code einfügen

1. Öffne die Datei `worker.js` aus diesem Ordner (zum Beispiel auf GitHub im Browser) und kopiere den **gesamten** Inhalt (alles markieren, kopieren).
2. Im Cloudflare-Editor den vorhandenen Beispielcode **komplett löschen** und deinen kopierten Code einfügen.
3. Oben rechts auf **Deploy** klicken (und bestätigen).

### Schritt 4: Die Datenbank anlegen

Der Worker speichert die Pakete in einer Datenbank namens "D1".

1. Im linken Menü: **Storage & Databases** und dann **D1 SQL Database**.
2. **Create database** (Datenbank erstellen).
3. Name: **`dartlab-sync`**. Den Standort kannst du auf "Automatic" lassen. Dann **Create**.
4. Du musst **keine Tabellen anlegen**. Der Worker erledigt das beim ersten Aufruf selbst.

### Schritt 5: Datenbank mit dem Worker verbinden

1. Zurück zu **Workers & Pages** und deinen Worker `dartlab-sync` öffnen.
2. Reiter **Settings** (Einstellungen), dort den Bereich **Bindings** suchen.
3. **Add** (Hinzufügen) und **D1 database** wählen.
4. Bei **Variable name** genau **`DB`** eintragen (Großbuchstaben, sonst nichts).
5. Bei **D1 database** die Datenbank `dartlab-sync` auswählen und speichern/**Deploy**.

### Schritt 6: Testen

1. Deine Adresse sieht so aus: `https://dartlab-sync.<dein-konto>.workers.dev`. Den genauen Namen zeigt Cloudflare oben auf der Seite deines Workers.
2. Hänge `/v1/hello` an und öffne die Adresse im Browser, also:

   `https://dartlab-sync.<dein-konto>.workers.dev/v1/hello`

3. Es muss genau das erscheinen:

   ```
   {"app":"dartlab-cloud","version":1,"live":1}
   ```

   Dann läuft der Worker. (Steht dort kein `"live":1`, ist es eine ältere Fassung: Abschnitt 3 zeigt, wie du sie aktualisierst.) Diese Test-Seite prüft nur den Worker, nicht die Datenbank. Ob die Verbindung zur Datenbank stimmt, zeigt sich, sobald die App zum ersten Mal synchronisiert. Meldet der Server dort den Fehler `db-missing`, dann ist Schritt 5 nicht richtig gespeichert (Variablenname genau `DB`?).

### Schritt 7: In der App einrichten

1. In DartLab: **Optionen › Sync zwischen Geräten › Über die Cloud abgleichen**.
2. Bei **Adresse des Cloud-Speichers** deine Adresse eintragen (ohne `/v1/hello`, das `https://` kann weg).
3. Auf dem **ersten** Gerät **Neues Geheimnis erzeugen** tippen. Das sind 26 Zeichen, die gleich die Daten verschlüsseln. **Kopiere sie und bewahre sie gut auf** (Notiz, Passwort-Manager). Geht das Geheimnis verloren, sind die Daten in der Cloud nicht mehr lesbar. Auf den Geräten bleiben sie.
4. **Jetzt abgleichen** tippen.
5. Auf jedem weiteren Gerät (iPhone, iPad, PC) dieselbe Adresse und **dasselbe Geheimnis** eintragen und abgleichen. Stimmt das Geheimnis nicht, sagt die App es und speichert nichts.

---

## 3. Den Worker aktualisieren (zum Beispiel für "Live")

Manchmal bekommt `worker.js` etwas Neues. Zuletzt war das **Live**: Dein Vater kann dir beim Spielen zuschauen. Die App merkt selbst, wenn der Worker noch die alte Fassung ist, und sagt dann **"Der Cloud-Speicher muss aktualisiert werden"** (bei dir in der Sync-Karte, bei deinem Vater im Reiter Live). Bis dahin läuft alles andere wie gewohnt weiter. Du brauchst auch hier **kein Terminal**, und die Datenbank bleibt, wie sie ist: Es gehen keine Daten verloren, und du musst nichts neu einrichten.

1. Öffne die Datei `worker.js` aus diesem Ordner (zum Beispiel auf GitHub im Browser) und kopiere den **gesamten** Inhalt (alles markieren, kopieren).
2. Gehe zu <https://dash.cloudflare.com>, links auf **Workers & Pages** und öffne deinen Worker `dartlab-sync`.
3. Oben auf **Edit code** (Code bearbeiten) klicken. Der Editor öffnet sich.
4. Den vorhandenen Code **komplett löschen** (im Editor einmal klicken, dann alles markieren und löschen) und den kopierten Code einfügen.
5. Oben rechts auf **Deploy** klicken (und bestätigen).
6. Prüfen: Öffne `https://dartlab-sync.<dein-konto>.workers.dev/v1/hello` im Browser. Jetzt muss `{"app":"dartlab-cloud","version":1,"live":1}` dort stehen, mit `"live":1` am Ende.

Die Variable `DB` (Abschnitt 2, Schritt 5) und alle Einstellungen bleiben beim Einfügen erhalten. Danach in DartLab unter **Optionen › Sync zwischen Geräten** den Schalter **Live übers Internet zeigen** einschalten, wenn du willst (er ist standardmäßig aus). Dein Vater muss in seiner App nichts tun.

**Live im Überblick:** Mit dem Schalter schickt deine App den laufenden Spielstand verschlüsselt an deinen Cloud-Speicher, und DartLab Lite zeigt ihn im Reiter Live. Lesen kann ihn nur, wer dein Geheimnis kennt. Ist der Schalter aus, verlässt nichts das Gerät. Wie viele Anfragen das kostet, steht in [docs/live-internet.md](../docs/live-internet.md): rund 10 Prozent der Gratis-Grenze an einem Abend.

---

## 4. Gratis-Grenzen

Alles hier läuft im kostenlosen Tarif. Stand der Cloudflare-Dokumentation vom **22.10.2026**:

| Was | Gratis-Grenze |
| --- | --- |
| Anfragen an den Worker | 100.000 pro Tag |
| Rechenzeit | 10 Millisekunden pro Aufruf (reicht hier locker) |
| Datenbank: gelesene Zeilen | 5 Millionen pro Tag |
| Datenbank: geschriebene Zeilen | 100.000 pro Tag |
| Datenbank: Speicherplatz | 5 GB |

**Wichtig:** Seit dem 1.9.2026 gilt: Wird ein Tageslimit überschritten, **schlagen weitere Anfragen fehl, bis um 00:00 Uhr UTC** (in Deutschland 01:00 oder 02:00 Uhr, je nach Sommerzeit). Du zahlst dann nichts extra, es geht nur eben nichts mehr durch.

Für eine private Gruppe ist das mehr als genug. Auch ein Abend mit **Live** und einem Zuschauer braucht nur etwa ein Zehntel davon (Rechnung in [docs/live-internet.md](../docs/live-internet.md)). Falls es trotzdem passiert: Die App merkt sich, was noch hochgeladen werden muss, und **versucht es später einfach weiter**. Es geht nichts verloren, es dauert nur bis zum nächsten Tag.

Der Server selbst begrenzt außerdem, damit nichts aus dem Ruder läuft:

- ein Paket darf höchstens 1,5 MB groß sein (genauer: 1,5 Mio. Zeichen im base64-Format),
- pro Tresor sind höchstens 50.000 Sessions erlaubt.

---

## 5. Alles wieder löschen

Du kannst jederzeit alles entfernen. Danach ist beim Server nichts mehr von dir vorhanden.

1. **Worker löschen:** Workers & Pages › `dartlab-sync` › **Settings** › ganz unten **Delete** (Löschen) und bestätigen.
2. **Datenbank löschen:** Storage & Databases › D1 › `dartlab-sync` › **Settings** › **Delete database** und bestätigen. Das löscht alle gespeicherten Pakete unwiderruflich.
3. Wer ganz sicher gehen will, kann zum Schluss auch das Cloudflare-Konto löschen (Konto-Einstellungen).

Deine Daten auf deinen Geräten bleiben davon unberührt. Nur die Cloud-Kopie verschwindet.

---

## 6. Optional: Setup-Key als Sicherheitsnetz (die App kann ihn noch nicht senden)

Die Adresse deines Workers ist nicht geheim. Wer sie errät, könnte theoretisch Müll hochladen und so deinen Gratis-Speicher belegen. Lesen kann er nichts, denn ohne dein Geheimnis findet er keine Daten und könnte sie auch nicht entschlüsseln.

Der Server kennt dafür einen **Setup-Key**, eine Art zweites Passwort für den ganzen Server (Variable `SETUP_KEY`, standardmäßig aus). **Schalte ihn nicht ein:** Die DartLab-App schickt ihn noch nicht mit, der Abgleich würde mit der Meldung "Zugang abgelehnt" scheitern. Er ist für den Fall gedacht, dass die App ihn später unterstützt. Ist er aus Versehen eingeschaltet: Workers & Pages › `dartlab-sync` › **Settings** › **Variables and Secrets** › `SETUP_KEY` löschen.

---

## Für Neugierige: technische Eckdaten

- Eine Tabelle `objects` in der D1-Datenbank. Der Worker legt sie bei Bedarf selbst an.
- Schnittstelle unter `/v1`: `hello` (meldet auch `"live": 1`), `meta` (mit Versionsprüfung gegen gleichzeitiges Überschreiben), `s/<uid>` (Sessions, es gewinnt immer der neuere Stand) und `live` (ein verschlüsseltes Paket pro Tresor, der letzte gewinnt, höchstens 16 KB; `GET /v1/live?since=<Zähler>` antwortet bei unverändertem Stand mit 304). Das Live-Paket liegt in derselben Tabelle `objects` unter dem Schlüssel `live`, die Datenbank braucht also keine Änderung.
- Weitere optionale Einstellung `MAX_SESSIONS` (Variable, Standard 50000): Höchstzahl Sessions pro Tresor.
- Tests ohne Cloudflare (Node 22): `node --test cloud/test`
