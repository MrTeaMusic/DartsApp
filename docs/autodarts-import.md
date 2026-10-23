# Online-Matches aus dem Autodarts-Konto importieren

**Stand:** neu, noch nicht an einer echten Autodarts-Antwort geprüft (siehe „Was nicht geprüft ist“).

Der lokale Weg über den Board Manager ([Autodarts Live](autodarts-live.md)) sieht nur **deine** Darts: kein
Gegner, keine Legs des Gegners, kein Match-Ende. Der Import holt das **fertige Match** aus deinem
Autodarts-Konto in den Verlauf und die Statistik, mit Gegnername, Legs und den Aufnahmen **beider**
Spieler.

## So funktioniert es

```
Autodarts-Seite im Browser ──(Antwort auf /stats)──> Browser-Skript ──POST──> DartLab (127.0.0.1:3191)
```

* Ein kleines **Browser-Skript** (`tools/autodarts-userscript/`, Tampermonkey/Violentmonkey) liest mit, was
  die Autodarts-Seite in deinem Browser ohnehin lädt, und schickt die fertige Match-Antwort an die lokale
  DartLab-Desktop-App.
* Die App nimmt sie in einem **Empfänger** an, der nur auf diesem Rechner (127.0.0.1) lauscht.
* Ohne Skript oder ohne Desktop-App geht derselbe Import von Hand: **Optionen › Online-Matches ›
  „Match-JSON einfügen“** (Zwischenablage oder Datei, mit Vorschau).
* Es gibt **keinen Login** bei Autodarts, kein Konto, kein Token und keinen Serverkontakt von DartLab zu
  Autodarts. Der Weg über die Cloud-Schnittstelle ist ohne Freigabe von Autodarts nicht vorgesehen
  (Anmeldung für Drittanbieter nur mit eigener Client-ID); deshalb liest das Skript nur mit.

## Einrichten

Kurzfassung in 5 Schritten (ausführlich in `tools/autodarts-userscript/README.md`):

1. DartLab (Desktop): **Optionen › Online-Matches (Browser-Skript) › „Empfänger einschalten“**. Der
   sechsstellige **Code** erscheint.
2. Tampermonkey oder Violentmonkey im Browser installieren.
3. `tools/autodarts-userscript/dartlab-autodarts.user.js` im Browser öffnen und installieren.
4. Auf play.autodarts.com im Skript-Menü **„DartLab einrichten“**: Adresse (`http://127.0.0.1:3191`) und Code.
5. **„DartLab: Verbindung testen“**: grüner Haken unten rechts.

Der Empfänger ist **standardmäßig aus**. In **Lite** und auf **iOS/Android** gibt es ihn nicht (siehe
„Entscheidungen“).

## Was passiert mit einem Match

| Antwort des Empfängers | Bedeutung |
|---|---|
| `imported` | Neu gespeichert (oder ein unfertiger Stand durch das fertige Match ersetzt). |
| `duplicate` | Dieses Match (Autodarts-Id) ist schon da, nichts geändert. |
| `ignored` | Kein X01-Match, sonst nichts zu tun. Wird nicht gespeichert. |
| `pending` | Gelesen, aber DartLab weiß nicht, welcher der beiden Spieler du bist. Die App fragt (Dialog „Welcher Spieler bist du?“). Gespeichert wird erst nach deiner Antwort. |

Fehler: `401` falscher Code, `403` falscher Host oder Origin, `405` falsche Methode, `413` größer als 2 MB,
`415` kein JSON, `400` kein gültiges JSON, `422` Format unbekannt, `429` zu viele Anfragen.

Die Antwort ist `{"ok": true, "status": "imported", "id": "<Match-Id>"}`, dazu bei Importen `opponent`,
`legs` (aus deiner Sicht, z. B. `3:2`), bei Hinweisen `message` und bei Überschneidung mit einer
Live-Aufzeichnung `overlap: true`.

## Wie DartLab speichert (kein neues Datenbankschema)

Ein importiertes Match ist eine ganz normale Session mit dem Spiel `x01_live` – dasselbe wie bei Autodarts
Live mit „X01 mitzählen“. Deshalb arbeiten Verlauf, Statistik „Online“, Doppelquote und Streuung ohne
Änderung.

* **Gespeichert werden nur deine eigenen Darts** (mit Feld, Position und Zeit), Aufnahme für Aufnahme. Die
  Quelle ist `autodartsImport`; die Zeiten eines Imports zählen deshalb **nicht** in die Wurftempo-Auswertung.
* **Legs, die der Gegner gewinnt**, werden wie bei Live als „Leg verloren“ nach deinen Darts des Legs
  eingetragen. So rechnet DartLab dieselben Legs, Checkouts und Busts nach wie sonst.
* **Der Gegner steht nur im Ergebnis** der Session (`result_json`): Name, Kennzahlen (Average, Darts,
  Checkout-Quote, 100+/140+/180), Sieger je Leg und seine Aufnahmen. Seine Darts landen **nie** in der
  Tabelle `throws` und zählen in **keiner** Statistik, auch nicht in Streuung oder Doppelquote.
* **Die Autodarts-Match-Id** steht in `config_json` unter `import.id`. Daran erkennt DartLab Duplikate.
  Fehlt sie in der Antwort, nimmt DartLab die Id aus der Adresse (`?id=`), sonst einen Abdruck des Inhalts.
* **Sync und Backup** nehmen importierte Sessions wie alle anderen mit; dafür war nichts zu ändern.

### Wer bist du?

Reihenfolge: (1) „Mein Autodarts-Name“ in den Optionen (Groß-/Kleinschreibung egal, muss genau einen der
beiden Spieler treffen); (2) sonst fragt DartLab einmal („Welcher Spieler bist du?“) und merkt sich die
Antwort als Namen. Heißen beide Spieler gleich, fragt DartLab immer.

### Duplikate, Ersetzen, Löschen

* Gleiche Match-Id → `duplicate`, nichts wird doppelt gespeichert.
* Ein **unfertiger** Stand (Match noch am Laufen) wird automatisch durch das fertige Match ersetzt.
* Im Dialog „Match-JSON einfügen“ gibt es bei einem bekannten Match **„Ersetzen“**. Das überschreibt die
  gespeicherten Darts dieses Matches, auch Korrekturen von dir.
* Löschst du die Session im Verlauf, lässt sich dasselbe Match danach neu importieren.

### Überschneidung mit Autodarts Live

Hast du dasselbe Match zusätzlich mit **Autodarts Live** mitgeschrieben, zählen die Darts doppelt. DartLab
**löscht nichts selbst**, zeigt aber in der Karte (und beim Einfügen) einen Hinweis mit dem Zeitpunkt der
Live-Aufzeichnung. Lösche dann eine der beiden Sessions im Verlauf.

### Was ausgewertet wird

* Nur **X01** mit **zwei Spielern**. Andere Varianten (Cricket, Shanghai …) werden mit `ignored` übergangen.
* Startwert und Out-Modus (Straight, Double, Master) kommen aus den Match-Einstellungen. **Double-In** wird
  nicht ausgewertet (Hinweis in der Vorschau).
* **Sets** werden nicht ausgewertet; sie zählen als Legs.
* Position der Darts nur, wenn die Antwort `coords` liefert; passen die Werte nicht zu einer Scheibe mit
  Radius 1, werden sie verworfen (Hinweis), das Match bleibt.
* Feldnamen der Antwort stehen **an einer einzigen Stelle**:
  `lib/features/autodarts_import/domain/autodarts_match_mapping.dart`. Stimmt ein Name nicht, wird nur diese
  Datei angepasst.

## Sicherheit des Empfängers

* Lauscht nur auf **127.0.0.1** (nicht im Netzwerk, keine Freigabe in der Firewall nötig), Port **3191**
  (einstellbar; der Sync-Hub nutzt 3190). Unabhängig vom Hub und vom Sync-Server.
* Jede Anfrage braucht den **Code** im Header `X-DartLab-Key`. Er wird zufällig erzeugt und lässt sich in der
  Karte erneuern.
* `Host` muss `127.0.0.1` oder `localhost` sein (Schutz vor DNS-Rebinding).
* **CORS** nur für `https://play.autodarts.com` und `https://play.autodarts.io`; ein anderer Origin bekommt
  403 ohne Freigabe-Header. Der Preflight beantwortet auch die „Private Network Access“-Frage von Chrome.
* Nur `POST /import/autodarts` (und `GET /import/ping` für den Test), nur JSON, höchstens 2 MB, Begrenzung
  auf 30 Anfragen in 10 Sekunden (zählt auch falsche Codes).
* **Nichts wird protokolliert**; Fehler gehen ohne Einzelheiten nach außen.

## Was das Skript liest – und was nicht

Liest nur die **Antworten** auf `/as/v0/matches/<id>/stats` und (bei beendetem Match)
`/gs/v0/matches/<id>/state`, nur mit `players` und `games`. Liest **nie** Header, Cookies, Token,
`localStorage` oder `Authorization`. Stellt **keine eigenen Anfragen** an Autodarts. Sendet nur an
127.0.0.1/localhost. Ein Node-Test (`node --test tools/autodarts-userscript/test`) prüft das mit einer
nachgebauten Seite, auch am Quelltext.

## Datenschutz

Mit dem Match kommt der **Name des Gegners** in deine DartLab-Datenbank, in Sync und Backup. Das ist eine
personenbezogene Angabe eines Dritten. Sie bleibt auf deinen Geräten; DartLab schickt nichts an Dritte. Wer
das nicht will, importiert nicht oder löscht die Session.

## Nutzungsbedingungen

> Das Skript liest nur, was die Autodarts-Seite in deinem Browser ohnehin bekommt. Die AGB von Autodarts
> verbieten Drittsoftware ohne Zustimmung; du nutzt es auf eigenes Risiko.

Dieser Hinweis steht auch in der Karte. Der offizielle Weg wäre eine Freigabe von Autodarts (eigene
Client-ID mit Device Flow, schriftliche Zustimmung nach AGB §6.1). Solange es die nicht gibt, baut DartLab
**keinen** eigenen Login und stellt **keine** Anfragen an die Autodarts-Server.

## Entscheidungen

* **Empfänger nur Desktop (Windows, macOS; Linux zum Entwickeln).** Auf iOS/Android gibt es keine
  Hintergrundserver, die verlässlich laufen, und ein Handy ist selten der Rechner mit dem Browser. Dort
  bleibt der **Import von Hand** (JSON einfügen oder Datei wählen) und „Mein Autodarts-Name“. In **Lite**
  fehlt die Karte ganz (eigene Optionen) und der Empfänger startet nie.
* **Port 3191**, damit er nicht mit dem Sync-Hub (3190) und dem Board Manager (3180) kollidiert.
* **Kein neues Schema:** alles in `sessions`/`throws` plus JSON. Dadurch Sync, Backup, Verlauf und Statistik
  ohne Änderung.
* **Zufällige Session-Ids bleiben:** Die Autodarts-Id steckt in `config_json`, nicht in der Spalte `uid`.
  Eine feste `uid` würde „Löschen und neu importieren“ verhindern.
* **`unsafeWindow`** im Skript: Ohne diese Freigabe kann ein Skript im Sandbox-Modus die Antworten der
  Seite (`fetch`, `XMLHttpRequest`) nicht mitlesen.

## Was nicht geprüft ist

Alles hier ist mit **selbst gebauten Daten** getestet. Nicht geprüft:

* **Form der echten Antwort.** Die Feldnamen stammen aus Community-Quellcode. Ob `/stats` genau so aussieht
  (`games`, `turns`, `throws`, `segment`, `coords`, `winnerPlayerId`, `finishedAt`), ist offen.
* **Koordinaten der Cloud.** Ob dieselbe Skala (Radius 1 = Außenkante Double, y zur 20) gilt wie beim lokalen
  Board Manager, ist offen. DartLab verwirft offensichtlich unpassende Werte.
* **Das Skript im echten Browser.** Nicht ausprobiert in Chrome/Edge/Firefox mit Tampermonkey/Violentmonkey:
  das Einhängen in `fetch`/`XMLHttpRequest` über `unsafeWindow` (in Firefox über `exportFunction`),
  Seitenregeln (CSP) der Autodarts-Seite, die Erlaubnis-Abfragen für den lokalen Zugriff („Local Network
  Access“) und die Verbindungsfreigabe von Tampermonkey.
* **Ob die Seite die Statistik am Matchende überhaupt lädt.** Wenn nicht, kommt nichts an; dann hilft „Match
  kopieren“ nach dem Öffnen des Matches im Verlauf.
* **Ob `/gs/.../state` am Ende vollständige Legs enthält.** Deshalb wartet das Skript auf `/stats`.

**Was zum Prüfen gebraucht wird:** eine echte, **fertige** `/stats`-Antwort eines Online-Matches (aus den
DevTools der Autodarts-Seite, nur der Antworttext, **ohne** Header, Cookies oder HAR-Datei; Namen dürfen
geschwärzt werden), möglichst auch die `/state`-Antwort am Matchende und eine kurze Notiz, wie Bull,
Single Bull und ein Fehlwurf heißen. Das Vorgehen dafür steht als „Test 1“ in der Recherche zum Autodarts-Konto.

## Fehlersuche

| Beobachtung | Ursache / Abhilfe |
|---|---|
| Karte zeigt „Port … ist belegt“ | Anderes Programm nutzt den Port: in der Karte einen anderen Port wählen und im Skript dieselbe Adresse eintragen. |
| Skript: „nicht erreichbar“ | App läuft nicht, Empfänger aus oder falscher Port. |
| Skript: „Falscher Code“ | Code in der Karte ansehen, im Skript-Menü neu eintragen. |
| Skript sendet nichts | Die Seite hat die Statistik nicht geladen: Match im Verlauf öffnen. Ausweg „DartLab: Match kopieren“. |
| Antwort `422` | Format der Antwort unbekannt: JSON (ohne Namen) schicken, Feldnamen anpassen. |
| Vorschau: „Koordinaten wirken unplausibel“ | Die Cloud liefert eine andere Skala; das Match wird ohne Positionen importiert. |
| Darts doppelt in der Statistik | Match auch mit Autodarts Live mitgeschrieben: eine der beiden Sessions löschen. |
