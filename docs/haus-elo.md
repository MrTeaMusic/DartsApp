# Haus-Elo: Bens Wertung aus seinen Matches

Der Statistik-Reiter **Elo** zeigt, wie sich das aktive Profil im Zeitverlauf gegen unterschiedlich starke
Gegner schlägt. Die Zahl heißt **Haus-Elo**, weil es für die Gegner keinen echten Elo-Wert gibt: DartLab
schätzt ihn selbst (siehe „Warum kein echter Elo“). Die Rechnung steckt in
`lib/features/stats/domain/house_elo.dart` (reine Dart-Klasse ohne Datenbank, mit Unit-Tests), die
Oberfläche in `lib/features/stats/presentation/elo_tab.dart`.

## Was ist Elo?

Elo ist ein Punktesystem aus dem Schach. Jeder Spieler hat eine Zahl. Vor einem Match rechnet man aus dem
Unterschied der beiden Zahlen aus, wie oft jeder gewinnen sollte. Wer **mehr** erreicht als erwartet,
bekommt Punkte, wer weniger erreicht, verliert welche. Ein Sieg gegen einen Stärkeren bringt also viel,
eine Niederlage gegen einen Schwächeren kostet viel. Gegen einen gleich starken Gegner geht es um 16
Punkte (bei K = 32).

Die **1000** am Anfang ist nur ein Ankerpunkt für die Skala. Die absolute Zahl bedeutet nichts, nur
Unterschiede und der Verlauf zählen.

## Welche Matches zählen

Eine Session zählt als gewertetes Match, wenn alles zutrifft (die Regel steht an **einer** Stelle,
`EloMatch.fromSession`):

* Spiel `x01_match` (Match gegen Bot, gegen Mitspieler am selben Board, Turnier) **oder** ein
  **importiertes** Online-Match (`x01_live` mit `import`, siehe [autodarts-import.md](autodarts-import.md)).
* Regulär zu Ende gespielt (`finished`), also nicht abgebrochen.
* Der **Ausgang ist bekannt** (Kennzahl `won`, sonst `details.won`). Ein importiertes Match ohne Sieger
  (Gleichstand, offen) zählt nicht.
* Es gibt genau einen Gegner (DartLab-Matches sind immer zu zweit).

Nicht gewertet werden Training, Solo-X01, Quiz, mitgeschriebene Live-Sessions ohne Gegner
(`x01_live` ohne Import, `autodarts_live`: dort kennt DartLab weder Gegner noch Ausgang) und abgebrochene
Matches.

## Die Rechnung

1. Alle gewerteten Matches des Profils werden **nach Startzeit** sortiert (bei gleicher Startzeit nach der
   Session-Uid, die auf jedem Gerät gleich ist).
2. Ben startet bei **1000**. Für jedes Match:
   * Erwartung `E = 1 / (1 + 10^((R_Gegner − R_Ben) / 400))`.
   * Ergebnis `S`: Sieg 1, Niederlage 0.
   * `R_Ben ← R_Ben + K · (S − E)` mit **K = 32** in den ersten 20 Matches, danach **K = 24**.
   * Der Gegner bekommt das Gegenstück: `R_Gegner ← R_Gegner + 24 · (E − S)` (K = 24 immer). Das ist
     Nullsumme, solange Ben ebenfalls mit K = 24 rechnet; in den ersten 20 Matches ist Bens K größer, der
     Gegner bewegt sich also etwas weniger. Das ist gewollt: Gegnerwerte sollen träger sein.
3. Rechnet man „Leg-Marge zählt“ (ein 3:0 als stärkerer Sieg als ein 3:2), wäre `S` statt 1/0 der Anteil
   der gewonnenen Legs. Das ist nicht eingebaut, in der Rechnung aber eine Zeile.

## Wie die Gegner geschätzt werden

Jeder Gegner hat ein eigenes **Haus-Rating**, das beim ersten Auftreten geschätzt und danach mitgeführt
wird:

```
R_Gegner = R_Ben_vor_dem_Match + 12 × (Average_Gegner − Average_Ben_gleitend)     begrenzt auf ±300 um R_Ben
```

* **Average_Ben_gleitend:** Mittel der 3-Dart-Averages aus Bens letzten 10 gewerteten Matches davor. Im
  allerersten Match der Average dieses Matches.
* **Average_Gegner:** bei **Bots** der eingestellte (nominale) Average; bei **Online-Gegnern** und
  **Mitspielern** der Average, den sie in diesem Match erzielt haben.
* Fehlt ein Average (ältere Matches ohne Gegnerdaten, kein Wurf), startet der Gegner bei Bens Rating.
* **Wiedererkennen:** Online-Gegner am Autodarts-Namen (klein geschrieben), Bots an Name **und** Stufe
  (`cpu 55@55`), Mitspieler am Namen. Die Art steht mit in der Kennung: Ein Online-Gegner „Anna“ und
  ein Mitspieler „Anna“ sind verschiedene Gegner. Ändert jemand seinen Namen, ist es für DartLab ein neuer
  Gegner.
* Ab dem zweiten Match zählt nur noch das mitgeführte Rating. Ein anderer Average im neuen Match
  verändert es nicht.

## Der Reiter

* **Kennzahlen:** aktuelles Elo mit der Veränderung der letzten 30 Tage, Rekord mit Datum, Zahl der
  gewerteten Matches (nach Art), Bilanz Siege–Niederlagen. Sie gelten für **alle** Matches, unabhängig
  vom Zeitraum.
* **Elo-Verlauf:** Stand nach jedem Match, im gewählten Zeitraum (7/30/90 Tage, alles), mit dem
  gleitenden Durchschnitt wie die anderen Verläufe.
* **Gegner:** je Gegner Matches, Bilanz, Haus-Rating und die Elo-Änderung insgesamt, die meisten Matches
  zuerst; Filter Alle, Online, Bots, Mitspieler. Zählt die Matches im gewählten Zeitraum, das Rating ist
  der Stand nach dem letzten dieser Matches.
* **Größte Siege / Bitterste Niederlagen:** die drei Siege über Gegner mit dem höchsten Rating bzw. die
  drei Niederlagen gegen Gegner mit dem niedrigsten (Rating vor dem Match), im gewählten Zeitraum.
* **Wie wird das berechnet?** öffnet eine kurze Erklärung.
* Unter **drei** gewerteten Matches zeigt der Reiter statt des Verlaufs einen freundlichen Hinweis, die
  Kennzahlen stehen auf „–“.
* Der **Spielfilter** der Statistik ist dort ausgeblendet (wie bei „Online“).
* Im **Spielverlauf** zeigt ein gewertetes Match in der Detailansicht eine Zeile „Haus-Elo 1002 → 1018
  (+16)“.
* **Lite** zeigt den Reiter wie die Haupt-App (dieselbe Statistik). Er hat keine schreibenden Knöpfe.

## Nichts wird gespeichert

Es gibt kein neues Datenbankschema, keine Migration und kein gespeichertes Elo. Bei jedem neuen
`StatsCalculator` (also nach jeder Änderung an den abgeschlossenen Sessions des Profils: Spielende,
Import, Löschen, Abgleich) rechnet DartLab beim ersten Lesen **alle** gewerteten Matches in
Zeitreihenfolge neu (`StatsCalculator.houseElo`, ein Lauf je Rechner). Dadurch bleibt das Ergebnis
stimmig, wenn ein Match gelöscht oder nachimportiert wird oder der Abgleich Sessions von einem anderen
Gerät bringt: Gleicher Datenstand ergibt auf jedem Gerät dasselbe Elo.

**Rechenzeit:** Der Rechner und seine Ergebnisse je Session (dekodiertes Ergebnis, Gewertet-Entscheidung)
werden für unveränderte Sessions übernommen; nur Match-Sessions werden überhaupt dekodiert. Der Lauf
selbst ist ein Durchgang über die Matches. Im Test dauern 3000 Matches (Dekodieren und Rechnen zusammen)
unter einer Sekunde, bei Bens Datenmenge (Hunderte Matches) sind es Millisekunden. Deshalb braucht es
keinen eigenen Isolate; das Laden der Würfe läuft weiter wie bisher über den `CalculatorLoader`.

## Warum kein „echter“ Elo und Grenzen

* Die Gegner haben keinen echten Elo. Ihr Rating ist DartLabs Schätzung aus dem Average, nicht ihre
  wirkliche Spielstärke. Ein Online-Gegner, der an einem schwachen Abend schlecht wirft, wird zu niedrig
  geschätzt, bis weitere Matches ihn zurechtrücken.
* Mit **wenigen Matches** oder wenigen verschiedenen Gegnern ist der Verlauf grob. Bots mit nominalem
  Average sind verlässlicher als Online-Gegner.
* Das Rating neuer Gegner hängt an Bens Rating zu diesem Zeitpunkt. Bens Zahl kann deshalb langsam
  „mitwandern“; sie taugt für den **Verlauf**, nicht für den Vergleich mit anderen Spielern.
* Sets zählen wie Legs (nur Sieg oder Niederlage des Matches). Die Spielart (Startwert, Out-Modus) wird
  nicht unterschieden.
* Ein Mitspieler wird am **Namen** erkannt, nicht am Profil: Das Ergebnis einer Session speichert die
  Profil-Id des Mitspielers nicht. Wird ein Profil umbenannt, gilt es ab dann als neuer Gegner.
* Alles beruht auf deinen eigenen Sessions. Fehlen Matches (nicht importiert, nicht mitgeschrieben),
  fehlen sie auch hier.

## Datenschutz

Namen von Gegnern kommen aus deinen Sessions und bleiben auf deinen Geräten und im verschlüsselten
Cloud-Sync, wie alle Session-Daten (siehe [autodarts-import.md](autodarts-import.md), „Datenschutz“).
Das Haus-Elo wird nicht gespeichert und nirgends hin geschickt. DartLab zeigt es nur in deiner Statistik.

## Tests

* `test/features/stats/house_elo_test.dart`: Rechnung (Start 1000, +K/2 bei Gleichstand, symmetrische
  Niederlage, K-Wechsel nach 20, Gegner-Schätzung samt Grenze und Rückfallwerten, Wiederkehrer,
  Reihenfolge, Neuberechnung nach Löschen), die Entscheidung, welche Sessions zählen (auch an einer echten
  Import-Antwort), Rechner und Rechenzeit.
* `test/features/stats/house_elo_provider_test.dart`: über den Lade-Weg (`CalculatorLoader`, Provider),
  Löschen und Nachimport.
* `test/widgets/elo_stats_test.dart`, `elo_history_test.dart`, `lite_elo_test.dart`: Reiter, Leerzustand,
  Filter, Erklärung, Zeile im Spielverlauf, Lite ohne schreibende Knöpfe.
