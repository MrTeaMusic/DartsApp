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
* **Korrekturen am Board:** Meldet der Board Manager in der laufenden Aufnahme ein anderes Feld oder weniger
  Darts, übernimmt DartLab das. Abgeschlossene Aufnahmen bleiben davon unberührt. Wie eine Korrektur am Board im
  Detail aussieht, ist nicht geprüft (siehe unten); Korrekturen im Autodarts-Web (Online-Matches) sieht DartLab
  womöglich gar nicht. Deshalb gibt es die Korrektur von Hand (nächster Abschnitt).
* **Korrektur von Hand:** siehe „Darts von Hand korrigieren“.
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

## Darts von Hand korrigieren

Im Live-Bildschirm lassen sich die Darts der **laufenden Session** korrigieren, auch in abgeschlossenen
Aufnahmen (ältere, schon gespeicherte Sessions nicht). Dafür gibt es keine Meldung vom Board: DartLab
korrigiert allein, die Autodarts-Seite bleibt unberührt (kein Befehl, keine Abfrage).

* **Dart korrigieren oder entfernen:** Dart antippen (in der aktuellen bzw. letzten Aufnahme oder in der
  Liste „Letzte Aufnahmen“, die jetzt bis zu acht Aufnahmen zeigt). Es öffnet sich dieselbe Feldauswahl wie in
  den Spielen; zusätzlich „Dart entfernen“ und „Aufnahme löschen“ (mit Rückfrage).
* **Dart ergänzen:** das „+“ hinter den Darts einer Aufnahme mit weniger als drei Darts (in der Liste) bzw. der
  erste freie Platz der aktuellen Aufnahme. Der Dart kommt ans Ende der Aufnahme, höchstens drei je Aufnahme.
* **Markierung:** Von Hand gesetzte oder ergänzte Darts tragen einen kleinen Stift. Gespeichert wird die Quelle
  `manual` (statt `autodartsLocal`); sie bleibt in der Datenbank erhalten.
* **Koordinaten:** Ein von Hand geänderter oder ergänzter Dart hat **keine Position** (und keine Rohdaten vom
  Board). Er erscheint nicht in der Streuungs-Analyse; die Heatmap und die Trefferstatistik zählen ihn wie
  jeden Dart ohne Position mit der Feldmitte. Die anderen Darts behalten ihre Position. Wer nur eine Aufnahme
  löscht, verliert nur diese Darts. Wählt man dasselbe Feld wie bisher, ändert sich nichts (der Dart wird
  nicht festgehalten).
* **Festhalten (Pin):** Ein von Hand gesetzter Dart ist festgehalten. Meldet das Board später eine Korrektur
  für diese Stelle oder ein „Rückgängig“, das gerade diesen letzten Dart träfe, wird es ignoriert. Wird in der
  laufenden Aufnahme ein Dart von Hand **gelöscht oder ergänzt**, passen die Stellen des Boards nicht mehr zu
  denen von DartLab: Diese Aufnahme ignoriert dann Korrekturen, „Rückgängig“ und die Stellenangabe des Boards
  bis zum Takeout; neue Darts des Boards werden weiter angehängt (drei Darts oder Takeout beenden die
  Aufnahme). Danach folgt die nächste Aufnahme wieder dem Board. Abgeschlossene Aufnahmen ändert das Board nie.
* **Nummern:** Aufnahmen und Darts werden nach jeder Korrektur neu durchnummeriert (Stelle `seq` und
  `visitIndex` in der Datenbank sind lückenlos). Eine gelöschte Aufnahme verschwindet, spätere rücken nach.
  Wird der letzte Dart der Session gelöscht, verschwindet die Session wie eine gelöschte Session im Verlauf;
  der nächste Dart beginnt eine neue.
* **Speichern:** Jede Korrektur schreibt alle Würfe der Session neu (`replaceThrows`) und speichert das
  Ergebnis mit Dartzahl und Ende (letzter Dart) sofort, auch das „gezählt“ je Dart.
* **X01 mitzählen:** Rest, Busts, Checkouts, Legs, Average und First 9 werden nach jeder Korrektur aus den
  Darts neu gerechnet (auch „gezählt“: Darts nach Bust oder Checkout einer Aufnahme zählen nicht).
  **Leg-Markierungen** („Leg verloren“, „Leg neu starten“) bedeuten „nach Dart N“ und bleiben zwischen denselben
  Darts: Wird davor ein Dart entfernt, rückt die Marke um eins vor; ein ergänztes Dart am Ende einer
  abgeschlossenen Aufnahme vor der Marke bleibt vor ihr (gehört noch ins alte Leg); ein Dart in der laufenden
  Aufnahme nach der Marke gehört ins neue Leg, wie ein Dart vom Board. Löscht man alle Darts eines Legs vor der
  Marke, ist die Marke wirkungslos.
* Die Markierung „von Hand“ überlebt einen Absturz (Quelle in der Datenbank), nicht aber das Festhalten:
  Nach einem Neustart beginnt ohnehin eine neue Session.

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
* Ob und wie sich eine Korrektur **im Autodarts-Web** (z. B. in einem Online-Match) lokal beim Board Manager
  zeigt, ist unbekannt. Möglich, dass DartLab davon nichts sieht; dann hilft nur die Korrektur von Hand. Wie
  sich eine Korrektur am Board zu den gemeldeten Stellen verhält, wenn DartLab schon von Hand umgebaut hat
  (gelöschter/ergänzter Dart), wurde nicht an einem echten Board geprüft: DartLab ignoriert dann die Stellen
  und Korrekturen des Boards für diese Aufnahme (siehe oben).

## Grenzen

* Ohne „X01 mitzählen“ kein Rest, keine Busts, keine Checkouts, keine Legs, kein Gegner.
* Mit „X01 mitzählen“ kennt DartLab das Match nur aus deinen Darts: Gegner, Bull-Off, Match-Ende und
  Legs des Gegners musst du selbst mit „Leg verloren“ nachtragen.
* Der vollständige Match-Import aus dem Autodarts-Konto (Schritt „B“: Gegner, Legs, offizieller Average)
  ist nicht möglich: Die Anmeldung für Drittanbieter ist abgeschaltet und bräuchte eine offizielle
  Client-ID, also eine Freigabe durch Autodarts.
