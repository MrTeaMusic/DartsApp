# Autodarts Live: Online-Matches mitschreiben

Stand: 14.10.2026.

Du spielst deine Matches wie gewohnt im Browser auf **play.autodarts.io** gegen Gegner an deren eigenen
Boards. DartLab läuft parallel auf demselben Windows-PC, hört beim lokalen Autodarts Board Manager mit und
speichert deine Darts als normale Sessions. Sie zählen dann in Statistik, Tagesziel und Erfolgen.

## So geht's

1. Optionen › Datenquelle: **Autodarts (lokal)** wählen. Host `127.0.0.1` (DartLab läuft auf dem PC des
   Board Managers), Port `3180`. „Verbindung testen“ prüft das.
2. Training › Modi › **Autodarts Live** öffnen. Oben rechts muss „Verbunden“ stehen.
3. Match auf play.autodarts.io starten und normal spielen. DartLab zeigt die laufende Aufnahme, die
   Kennzahlen der Session, eine Heatmap und die letzten Aufnahmen.
4. Nach dem Spielen **Beenden** drücken. Vergisst du das, ist trotzdem alles gespeichert (siehe unten).

Optional: Optionen › Datenquelle › „Beim Öffnen von DartLab automatisch mitschreiben“. Dann startet DartLab
direkt in Autodarts Live (nur mit der Datenquelle Autodarts).

**Wichtig: Nur du darfst auf das Board werfen.** DartLab ordnet jeden Dart, den der Board Manager meldet,
dem aktiven Profil zu. Bei Online-Matches passt das, weil die Darts deines Gegners nie auf deinem Board
landen. Spielt jemand anderes an deinem Board mit, landen seine Darts in deiner Statistik.

## Rein passiv: DartLab sendet nichts

Ein Start/Stop/Reset an den Board Manager würde das laufende Online-Match stören. Deshalb:

* Autodarts Live liest nur den WebSocket `/api/events` (bzw. bei Ausfall `GET /api/state`).
* Solange der Live-Bildschirm offen ist, steht die Verbindung auf **nur mithören**
  (`AutodartsLocalSource.listenOnly`): Jeder Befehl (`PUT /api/start`, `PUT /api/stop`,
  `POST /api/reset`) wird verweigert, auch die Knöpfe im Debug-Bildschirm. Im Rohdaten-Log steht dann
  „nicht gesendet: Autodarts Live hört nur mit“.
* `/api/system` und `/api/config` (enthalten den API-Schlüssel des Boards) werden nie abgefragt.
* Ein Test spielt den echten Mitschnitt über einen nachgebauten Board Manager ab und prüft, dass nur
  `GET /api/events` bzw. `GET /api/state` ankommt.

## Was aufgezeichnet wird

* Jeder Dart mit Feld, Position (für die Heatmap) und Zeit, sofort beim Eintreffen gespeichert.
* **Aufnahmen:** Eine Aufnahme endet mit dem Takeout (Darts gezogen), einem Reset am Board oder nach drei
  Darts. Bust oder Checkout im Match beendet eine Aufnahme also erst mit dem Ziehen der Darts.
* **Korrekturen:** Meldet der Board Manager in der laufenden Aufnahme ein anderes Feld oder weniger Darts,
  übernimmt DartLab das. Abgeschlossene Aufnahmen bleiben, wie sie sind.
* **Kennzahlen ohne X01:** Darts, „Ø 3 Darts (roh)“, Aufnahmen, beste Aufnahme, 100+/140+/180,
  Triple/Doppel/Single/Daneben und die Heatmap. Der Rohschnitt zählt die Punkte aller Darts, auch in
  überworfenen Aufnahmen und Darts aufs Doppel. Er ist **kein offizieller X01-Average**. Gespeichert als
  Spiel `autodarts_live`; in der Statistik zählen diese Darts wie die Scoring-Drills zum 3-Dart-Average.
  Einen First-9-Average gibt es ohne X01 nicht (DartLab kennt keine Legs).

### Optional: „X01 mitzählen“

Mit dem Schalter im Live-Bildschirm rechnet DartLab aus deinen Darts deinen Rest mit (Startwert 301/501/701,
Straight/Double/Master-Out, Standard 501 Double-Out), mit den gleichen Regeln wie X01-Solo:

* Bust setzt den Rest auf den Stand vor der Aufnahme zurück; weitere Darts dieser Aufnahme zählen nicht.
* Checkout beendet das Leg (gewonnen), das nächste beginnt wieder beim Startwert.
* Der Live-Bildschirm zeigt Rest, Checkout-Weg bzw. Stell-Vorschlag, Leg-Nummer und Legs gewonnen:verloren.
* **„Leg verloren“:** Die Darts deines Gegners sieht DartLab nicht. Checkt er, tippst du darauf; das Leg
  zählt als verloren, dein Rest springt auf den Startwert.
* **„Leg neu starten“:** Wenn der Rest nicht stimmt (z. B. ein Dart wurde nicht erkannt). Rest zurück auf
  den Startwert, das Leg wird nicht gewertet (die Darts zählen aber weiter im Average).

Diese Sessions heißen `x01_live` und speichern dieselben Kennzahlen wie ein Match (Average mit Bust = 0,
First 9, Legs, Checkout-Darts und -Quote, höchstes Finish, 100+/140+/180). Die Statistik wertet sie wie
X01 aus. Umschalten (an/aus, Startwert, Ausstieg) beginnt eine neue Session. DartLab weiß nicht, wann
das Match wirklich beginnt oder endet; stimmt der Rest nicht, hilft „Leg neu starten“.

Auswertung der Live-Sessions als Matches (Reiter „Online“ in der Statistik, Vergleich mit dem
Training, Plan-Vorschlag): `docs/online-matches.md`.

## Sessions

* Jedes Öffnen des Live-Bildschirms ist eine eigene Session. Sie entsteht mit dem ersten Dart; ohne Darts
  wird nichts gespeichert.
* Nach **20 Minuten ohne Dart** beginnt mit dem nächsten Dart eine neue Session (Ende der alten = letzter
  Dart). So wird ein Abend mit Pause nicht zu einer Riesen-Session, und die Trainingszeit enthält keine
  Leerlaufzeit.
* Spielt gerade ein Trainingsspiel oder Match in DartLab, schreibt Autodarts Live nicht mit (sonst
  zählten die Darts doppelt).

**App geschlossen ohne „Beenden“?** Jeder Dart steht sofort in der Datenbank. Nach der ersten Aufnahme
und dann höchstens alle zwei Minuten wird die Session zusätzlich als abgeschlossen zwischengespeichert,
damit sie in der Statistik erscheint. Beim nächsten Öffnen von Autodarts Live werden nicht sauber
beendete Live-Sessions aus den gespeicherten Darts fertig gerechnet.

Weil die Session nach dem Zwischenspeichern weiterwächst, trägt jeder Schreibvorgang einen neuen Stand
(`sessions.updated_at`). Der [Sync im Heimnetz](sync.md) überträgt die Session deshalb erneut und
ersetzt die ältere Kopie auf dem anderen Gerät, so kommen auch spätere Darts und Korrekturen
(z. B. bei den Tagesdarts auf dem Hub) an.

## Was am echten Board geprüft ist und was nicht

Geprüft (Board Manager 2.0.2, Windows, siehe `docs/autodarts-protokoll.md`): Würfe kommen lokal an, je
Dart und beim Takeout eine Statusmeldung, ohne Darts fehlt `throws`, daneben = `bed: "Outside"` /
Multiplikator 0. Der echte Mitschnitt läuft als Test durch Autodarts Live.

**Nicht am echten Board geprüft:**

* Wie Bull und Single Bull heißen. DartLab nutzt Zahl (25) und Multiplikator, zur Sicherheit auch die Zahl
  50 und die Namen „Bull“/„25“.
* Wie eine Korrektur am Board aussieht. DartLab übernimmt geänderte Felder an einer Position und entfernte
  Darts am Ende. Entfernt eine Korrektur **alle** Darts der Aufnahme, sieht das aus wie ein Takeout: Die
  Darts bleiben dann gezählt.
* `bouncer: true` (abgeprallter Dart) wird nicht ausgewertet.

## Grenzen

* Ohne „X01 mitzählen“ kein Rest, keine Busts, keine Checkouts, keine Legs, kein Gegner.
* Mit „X01 mitzählen“ kennt DartLab das Match nur aus deinen Darts: Gegner, Bull-Off, Match-Ende und
  Legs des Gegners musst du selbst mit „Leg verloren“ nachtragen.
* Der vollständige Match-Import aus dem Autodarts-Konto (Schritt „B“: Gegner, Legs, offizieller Average)
  ist nicht möglich: Die Anmeldung für Drittanbieter ist abgeschaltet und bräuchte eine offizielle
  Client-ID, also eine Freigabe durch Autodarts.
