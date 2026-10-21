# Wurftempo

Das Wurftempo zeigt, wie schnell man wirft: als **leise Zeile** in den Spielansichten und als eigener Reiter
**Statistik → Tempo**. Es gibt keinen Zähler, keine Uhr, kein Limit und keine Warnfarben. Das Tempo ist
eine Beobachtung, keine Vorgabe.

Berechnet wird alles aus `Throws.timestamp`, es gibt **keine Schemaänderung** (drift bleibt bei Version 7) und
**kein neues Sync-Format**: Die Zeitstempel reisen ohnehin mit den Würfen. Die Rechenlogik steht in
`lib/features/stats/domain/tempo_stats.dart` (reine Dart-Funktionen mit Unit-Tests), die Oberfläche in
`lib/features/stats/presentation/tempo_tab.dart` und `tempo_hint.dart`.

## Begriffe

| Begriff | Bedeutung |
|---|---|
| **Wurfabstand** | Zeit zwischen zwei aufeinanderfolgenden Darts **derselben** Aufnahme (Dart 1 → 2, Dart 2 → 3). |
| **Aufnahmezeit** | Zeit vom ersten bis zum dritten Dart einer **vollen** 3-Dart-Aufnahme. Das Ziehen der Darts ist nicht enthalten. |
| **Mit Takeout** | Zeit vom ersten Dart einer Aufnahme bis zum ersten Dart der nächsten: Werfen plus Darts ziehen. Nur im **Training** (siehe unten). |

Überall gilt der **Median**, nie der Mittelwert. Eine einzelne vergessene Pause oder ein Ausreißer verschiebt
den Median kaum. Der Mittelwert würde dadurch sofort verfälscht.

Die Datenbank speichert Zeitstempel in **ganzen Sekunden**. Der Median wird deshalb bei ganzzahligen Messwerten
innerhalb der mittleren Klasse interpoliert (k − 0,5 … k + 0,5), sonst zeigte der Verlauf nur Stufen
(genau 3,0 s, genau 4,0 s). Einzelne Abstände sind also auf etwa eine Sekunde genau, der Median über viele
Darts deutlich besser.

## Was zählt, was nicht

Eine Aufnahme zählt nur, wenn die Zeiten **verlässlich** sind. Gezählt wird je Dart und je Aufnahme:

* Nur Darts von der **Autodarts-Hardware** (`source = autodartsLocal`, lokal und Autodarts Live). Beim
  Simulator misst man Mausklicks, bei manueller Eingabe das Tippen, beides sagt nichts über das Werfen.
* Der Zeitstempel darf nicht mehr als **5 s vor dem Start der Session** liegen (nachträglich eingetragen,
  wieder aufgenommen oder importiert).
* Eine Aufnahme fällt **ganz** heraus, wenn ein Dart ohne verlässliche Zeit dabei ist, ein Abstand unter
  **0,5 s** liegt (gleichzeitig oder rückwärts, das ist kein Wurf) oder über **60 s** (Pause mitten in der
  Aufnahme).
* Im **Live-Modus** macht eine manuelle Korrektur (`source = manual`) die Aufnahme unbrauchbar. Im Training
  und im Match behält `correct()` Quelle und Zeitstempel des ersten Wurfs, die Aufnahme bleibt damit gültig.
* Rückgängig gemachte Darts sind gelöscht und fehlen im Ergebnis. Die verbleibenden Darts zählen normal.

Was verwendet und was übersprungen wurde, steht unten im Reiter in der Karte **Was zählt**: Anzahl der
berücksichtigten und der übersprungenen Sessions, dazu die Regeln. Ohne einen einzigen verwertbaren Dart zeigt
der Reiter einen Leerzustand und sagt, wie viele Sessions wegen unsicherer Zeiten fehlen.

## Schwellen

* **Mindestens 10 Messwerte** je Zahl, je Woche und je Tempoklasse. Darunter steht kein Wert, sondern
  „Zu wenig Daten (x von 10)“. Ein Tag mit zwei, drei Aufnahmen liefert also nie eine Zahl.
* Der **Verlauf** zeigt die letzten **12 Wochen**, unabhängig vom oben gewählten Zeitraum. Eine Woche
  mit zu wenigen Messwerten bekommt keinen Punkt. Unter zwei Wochen mit Daten steht ein Hinweis statt der Linie.
* **Tempoklassen** nach der Aufnahmezeit (erster bis dritter Dart): **schnell** unter 6 s, **mittel** 6 bis
  12 s, **langsam** über 12 s. Die Grenzen sind bewusst klein gewählt, weil die Aufnahmezeit ohne das Ziehen der
  Darts gemessen wird.

## Reiter Statistik → Tempo

Eigener Reiter, weil er eigene Regeln hat (nur Darts vom Board), auch ohne Punkte lesbar ist und eine
Erklärung braucht. Alles folgt dem Zeitraum- und Spielfilter oben wie die anderen Reiter.

1. **Vier Kacheln:** Median je Dart, Median je Aufnahme, Median mit Takeout, und wie viele Aufnahmen gemessen wurden.
2. **Verlauf:** Median je Dart pro Woche als Linie (`fl_chart`, derselbe Linienchart wie bei den Averages).
3. **Tempo und Punkte:** Je Tempoklasse der Durchschnitt der Punkte je Aufnahme (nur Spiele mit Punkten,
   nur Aufnahmen mit drei gezählten Darts). Darunter ein Satz, ob langsamere Aufnahmen mehr oder weniger punkten.
   Das ist ein Zusammenhang, kein Beweis: Wer vor einem Finish länger zielt, wirft auch andere Felder.
4. **Training, Match, Online:** Median je Dart und je Aufnahme, im Training zusätzlich mit Takeout.
5. **Was zählt:** die Regeln dieser Seite in Kurzform und die Zahl der berücksichtigten Sessions.

Zuordnung der Spielart: `x01_match` ist **Match**, `x01_live` und `autodarts_live` sind **Live**, alles
andere ist **Training**.

**Warum „mit Takeout“ nur im Training:** Im Match und im Live-Modus wirft der Gegner zwischen zwei eigenen
Aufnahmen, außerdem speichert ein Match nur die Darts der Menschen. Der Abstand von Aufnahme zu Aufnahme
enthielte also fremde Zeit und wäre keine eigene Größe. Im Training wirft man allein, dort ist er aussagekräftig.
Pausen über 60 s fallen heraus.

## Die leise Zeile beim Spielen

Eine Zeile in gedämpfter Schrift mit kleinem Uhr-Symbol, zum Beispiel **„Aufnahme 9 s · Ø 3,1 s je Dart“**.

* Sie zeigt die Zeit der **letzten Aufnahme mit mindestens zwei Darts** (erster bis letzter Dart) und den
  Median je Dart der letzten Aufnahmen, sobald dafür **10 Abstände** vorliegen.
* Sie ändert sich **nur, wenn ein Dart dazukommt**. Es läuft kein Zähler mit, nichts tickt hoch.
* Sie erscheint dort, wo gespielt wird: Arena (Match, X01-Solo, alle Trainingsspiele, Autodarts Live) unter den
  Meldungen am Board, in den Looks TV, Clean und Lab in der Karte der aktuellen Aufnahme.
* Sie fehlt, wenn die Zeiten nicht verlässlich sind (Simulator, manuell eingegebene Darts) oder die
  Einstellung aus ist. Eine Aufnahme mit manuell nachgetragenem Dart blendet sie aus.
* Im Match wird die Aufnahme des Menschen gezeigt, der gerade dran ist (oder der einzige Mensch gegen Bots).

**Optionen → Wurftempo anzeigen** schaltet die Zeile ein oder aus (Standard: **an**; gespeichert als
`settings.tempoHint`). Der Schalter betrifft nur die Spielansichten. Der Reiter in der Statistik bleibt immer
verfügbar. Die Aufnahmen werden unabhängig davon gespeichert, es ändert sich nichts an den Daten.

## Caching

`StatsCalculator` bewertet jede Session einmal (`tempoOf`, `_tempoCache`) und übernimmt das Ergebnis bei
unveränderten Sessions in den nächsten Rechner (`take(previous._tempoCache, …)`). Berichte liegen je
(Zeitraum, Spiel) in `_tempoReports`. `build()` rechnet nichts, die Oberfläche liest nur den fertigen Bericht.
Der Verlauf nutzt dieselben Sessions und einen eigenen Berichtsschlüssel, der nicht vom Zeitraum abhängt.

## Grenzen

* Gemessen wird, wann das Board den Dart meldet, nicht wann er die Hand verlässt. Die Meldung kommt wenige
  hundert Millisekunden später; der Abstand bleibt davon fast unberührt, weil die Verzögerung in beiden
  Messpunkten steckt.
* Ganze Sekunden: Einzelabstände unter etwa 2 s sind ungenau. Deshalb Median und Mindestmenge.
* Alte Sessions ohne Autodarts-Darts erscheinen nicht, auch wenn sie Zeitstempel haben.
