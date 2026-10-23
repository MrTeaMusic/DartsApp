# DartLab für Autodarts (Browser-Skript)

Nach einem Online-Match auf **play.autodarts.com** schickt dieses kleine Skript das fertige Match an deine
**DartLab-Desktop-App** (Windows oder macOS). Dort erscheint es mit Gegner, Legs und allen Aufnahmen im
Verlauf und in der Statistik „Online“.

> **Wichtig vorab**
> Das Skript liest nur mit, was die Autodarts-Seite in deinem Browser ohnehin bekommt. Die AGB von
> Autodarts verbieten Drittsoftware ohne ihre Zustimmung. Du nutzt das Skript auf eigenes Risiko.
>
> **Stand:** Das Skript wurde noch nicht an einer echten Autodarts-Antwort ausprobiert. Wenn bei dir etwas
> nicht ankommt, hilft der Weg über „Match kopieren“ (unten) und ein Blick in `docs/autodarts-import.md`.

## Was du brauchst

* Die **DartLab-Desktop-App** auf demselben Rechner, auf dem dein Browser läuft.
* Einen Browser (Chrome, Edge oder Firefox) mit der Erweiterung **Tampermonkey** oder **Violentmonkey**.

## Einrichten (5 Schritte)

1. **In DartLab** die Optionen öffnen und zur Karte **„Online-Matches (Browser-Skript)“** gehen.
   „Empfänger einschalten“ anklicken. Es erscheint ein sechsstelliger **Code**. Notiere ihn oder kopiere
   ihn (Symbol daneben). Der Port steht auf 3191; er muss nur geändert werden, wenn der Platz schon belegt
   ist (dann zeigt die Karte „Port … ist belegt“).
2. **Tampermonkey** (oder Violentmonkey) im Browser installieren.
3. Die Datei **`dartlab-autodarts.user.js`** aus diesem Ordner öffnen („Raw“ auf GitHub oder die Datei in den
   Browser ziehen). Die Erweiterung fragt, ob sie das Skript installieren soll: **Installieren**.
4. Auf **play.autodarts.com** das Tampermonkey-Symbol anklicken und **„DartLab einrichten“** wählen.
   Zuerst die Adresse (der Vorschlag `http://127.0.0.1:3191` passt, wenn du den Port nicht geändert hast),
   dann den **Code** aus DartLab eintragen.
5. **„DartLab: Verbindung testen“** wählen. Unten rechts auf der Seite erscheint ein kleiner Punkt:
   grün mit Haken heißt „DartLab antwortet“.

Danach genügt es, ein Match zu spielen. Öffnest du es nach dem Ende (oder schaut sich die Seite die
Statistik an), erscheint unten rechts kurz **„In DartLab gespeichert …“**.

**Welcher Spieler bist du?** Beim ersten Match fragt DartLab nach (Fenster in der App). Die Antwort wird
als „Mein Autodarts-Name“ in den Optionen gemerkt; danach fragt DartLab nicht mehr. Du kannst den Namen
dort auch gleich selbst eintragen.

## Das kleine Symbol unten rechts

| Symbol | Bedeutung |
|---|---|
| grün, Haken | Match ist in DartLab (oder war schon da) |
| gelb, „i“ | Hinweis, z. B. „kein X01-Match“ oder „DartLab fragt nach, wer du bist“ |
| rot, „!“ | Das Senden hat nicht geklappt; ein Klick zeigt den Grund |
| grau | Es wird gerade gesendet |

## Die Menüpunkte (Tampermonkey-Symbol)

* **DartLab einrichten**: Adresse und Code der App eintragen.
* **DartLab: Match kopieren**: legt das zuletzt gesehene fertige Match in die Zwischenablage. In DartLab:
  Optionen › „Match-JSON einfügen“ › „Zwischenablage“ › „Importieren“. Das ist der Ausweg, wenn der
  Empfänger nicht läuft oder der Browser das Senden blockiert.
* **DartLab: Verbindung testen**: prüft Adresse und Code.
* **DartLab: letztes Match erneut senden**: schickt das zuletzt gesehene Match noch einmal.

## Wenn es nicht klappt

* **Rot, „nicht erreichbar“**: Läuft DartLab? Ist „Empfänger einschalten“ an? Stimmt der Port in
  „DartLab einrichten“ mit dem in der App überein?
* **Rot, „Falscher Code“**: Code in der App ansehen und im Menü neu eintragen. Ein „Neuer Code“ in der App
  macht den alten ungültig.
* **Der Browser fragt nach „Zugriff auf Geräte im lokalen Netzwerk“** (Chrome/Edge): Erlauben. Gemeint ist
  nur dein eigener Rechner (127.0.0.1).
* **Tampermonkey fragt bei der ersten Sendung nach einer Verbindung zu 127.0.0.1**: „Immer erlauben“.
* **Gar nichts passiert**: „DartLab: Match kopieren“ zeigt, ob das Skript überhaupt ein fertiges Match gesehen
  hat („Noch kein fertiges Match gesehen“ = die Seite hat die Statistik nicht geladen; öffne das Match in
  deinem Verlauf, dann lädt sie die Daten).
* **Das Match fehlt in der Statistik**: Es werden nur **X01**-Matches mit **zwei Spielern** übernommen.

## Was das Skript liest und was nicht

**Liest:** Nur die Antworten der Autodarts-Seite auf `/as/v0/matches/<id>/stats` und, wenn das Match zu
Ende ist, `/gs/v0/matches/<id>/state` – und nur, wenn darin `players` und `games` stehen.

**Liest nie:** Header, Cookies, Token, Passwörter, `localStorage`, `Authorization`.

**Schickt:** Den JSON-Text dieser Antwort per POST an die eingestellte Adresse, und nur an `127.0.0.1`
oder `localhost` (alles andere verweigert das Skript). Kein Telemetrie-Dienst, keine fremden Skripte, keine
eigenen Anfragen an Autodarts.

Die Rechte, die das Skript anfordert, und wofür sie gebraucht werden, stehen am Anfang der Skriptdatei.

## Für Entwickler

Test ohne Browser (Node 20 oder neuer): `node --test tools/autodarts-userscript/test`.
Das Skript hat keine Abhängigkeiten und keinen Build-Schritt.
