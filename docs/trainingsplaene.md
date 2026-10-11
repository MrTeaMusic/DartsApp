# Trainingspläne

Ein Trainingsplan ist eine feste Reihenfolge von Spielen, jedes mit eigenen Einstellungen und
einem optionalen Hinweis. Man startet den Plan einmal, danach geht es nach jedem Spiel mit
**Nächster Schritt** weiter. Zu finden unter **Training › Trainingspläne**.

## Feste Pläne

| Plan | Schritte |
|---|---|
| Aufwärmen | Around the Clock (ohne Bull), T20 × 5 Aufnahmen, Bullseye × 5 |
| Scoring | T20 × 10, T19 × 10, Score-Ziel 100 × 10, Highscore-Jagd × 10 |
| Doppel | Around the Clock nur Doppel, Bob's 27, Checkout 2–40 |
| Checkout | Checkout 41–100, 121 mit 9 Darts, Checkout 101–170 mit 6 Darts |
| Allround in 30 Minuten | Around the Clock, T20 × 8, Bob's 27 (ohne Bull), Checkout 2–100, Cricket der Reihe nach |
| Einsteiger | Around the Clock (ohne Bull), Drei-Treffer-Runde mit 1 Treffer, Highscore-Jagd × 5, Checkout 2–40 ohne Doppelpflicht |

Feste Pläne lassen sich nicht ändern, aber über das Menü **Als eigenen Plan kopieren** und dann
anpassen.

## Eigene Pläne

**Neuer Plan**: Name, optional eine Beschreibung, dann Schritte hinzufügen. Für jeden Schritt das
Spiel wählen, die Einstellungen setzen (dieselben wie vor einem normalen Spielstart) und bei Bedarf
einen Hinweis eintragen, der während des Spiels angezeigt wird. Schritte lassen sich antippen und
ändern, nach oben oder unten schieben und entfernen. Eigene Pläne können bearbeitet, kopiert und
gelöscht werden.

## Plan für mich (automatisch)

Oben in der Planübersicht steht **Plan für mich erstellen** (auch verlinkt im Statistik-Überblick
unter den Kennzahlen).
Die App schlägt dann einen Plan aus der eigenen Statistik vor, z. B. mehr D16, wenn das das
schwächste Doppel ist. Jeder Schritt hat eine kurze Begründung („D16 triffst du nur zu 18 %,
Ziel: 25 %“), die als Hinweis auch im Spiel erscheint.

* **Dauer** 20, 40 oder 60 Minuten. Die Länge der Schritte ist grob geschätzt (etwa 20 Sekunden
  pro Aufnahme, Spiele ohne festen Umfang wie Bob's 27 mit festen Minuten); Aufnahmen und Versuche
  werden so gewählt, dass die Summe ungefähr die gewählte Dauer ergibt.
* **Neu vorschlagen** wählt für dieselben Schwerpunkte andere Spiele, ein anderes Aufwärmen und
  einen anderen Abschluss. Gleiche Daten, gleiche Dauer und gleicher Vorschlag ergeben immer
  denselben Plan.
* **Plan starten** spielt ihn sofort, ohne ihn zu speichern. Ein angefangener Durchlauf lässt
  sich im selben Bildschirm fortsetzen; ein neuer Start verwirft ihn.
* **Als eigenen Plan speichern** legt ihn unter „Eigene Pläne“ ab (mit den Begründungen als
  Hinweise). Danach ist er wie jeder eigene Plan bearbeitbar.

### Grundlage

Die Statistik des aktiven Profils der letzten 30 Tage. Sind es dort weniger als 150 Darts oder
weniger als 3 Sessions, nimmt die App 90 Tage, dann alle Daten. Reicht auch das nicht, gibt es
einen **ausgewogenen Startplan** mit dem Hinweis, dass noch zu wenig Daten da sind. Mit genug
Daten, aber ohne klare Schwäche gibt es einen ausgewogenen Plan mit entsprechendem Hinweis.

### Welche Schwächen erkannt werden

| Schwäche | Bedingung | Ziel | Spiel |
|---|---|---|---|
| Einzelnes Double (D1–D20, Bull) | ab 10 Versuchen; Quote mindestens 15 % unter der eigenen Double-Quote (wie das Rot im Doubles-Raster). Höchstens zwei Doubles. | eigene Double-Quote, mindestens +5 Prozentpunkte, auf 5 % aufgerundet | Checkout-Training mit festem Rest (D16 → immer 32, Bull → 50) |
| Doppel insgesamt | Double-Quote unter 20 % (ab 30 Darts) | +3 Prozentpunkte, auf 5 % aufgerundet | Around the Clock nur Doppel, Doubles 420 oder Checkout 2–40 |
| Triple (T15–T20) | ab 15 Darts; Quote mindestens 15 % unter der eigenen Triple-Quote | eigene Triple-Quote, mindestens +3 Prozentpunkte | T20-Training auf diese Zahl |
| Checkout-Bereich | ab 8 Versuchen; Quote mindestens 15 % unter dem Richtwert (2–40: 40 %, 41–60: 30 %, 61–100: 20 %, 101–130: 10 %, 131–170: 5 %). Nur der schwächste Bereich. | +5 Prozentpunkte, mindestens die Hälfte des Richtwerts, höchstens der Richtwert | Checkout-Training im Bereich (ab 101 mit 6 Darts); alternativ der Bereich absteigend oder 121 |
| Scoring | 3-Dart-Average unter 60 (ab 90 Scoring-Darts) | Average +3, auf 5 aufgerundet | T20-Training, Score-Ziel 60 oder Highscore-Jagd |
| First 9 | First 9 mehr als 3 % unter dem Average | der eigene Average | Score-Ziel 100 oder T20-Training |
| Konstanz | Streuung der Aufnahmen über 55 % des Schnitts (ab 30 Aufnahmen) | jede Aufnahme über dem höchsten Score-Ziel bis zum Schnitt | Score-Ziel oder T19-Training |

Die Stärke einer Schwäche ist der relative Abstand zum Vergleichswert (z. B. 1 − D16-Quote /
Double-Quote). In den Plan kommen die stärksten, je Art eine (Doubles: zwei).

### Aufbau

1. **Aufwärmen** (ca. 12 % der Zeit): Around the Clock ohne Bull, ein paar Aufnahmen auf die 20
   oder Bullseye, je nach Vorschlag und so, dass es keinen Schwerpunkt wiederholt.
2. **Schwerpunkte**: 2 bei 20 Minuten, 3 bei 40, 4 bei 60. Erst Scoring, dann Triple, dann Doppel
   und Checkouts. Sind es weniger Schwächen als Plätze, wird mit ausgewogenen Schritten aufgefüllt
   (T20, Checkout 2–40, Score-Ziel 100, Checkout 41–100). Schwerpunkte aus der Statistik bekommen
   anderthalbmal so viel Zeit wie Auffüllschritte. Kein Spiel kommt mit gleichem Ziel doppelt vor.
3. **Abschluss unter Druck** passend zur stärksten Schwäche: Bob's 27 oder 121 bei Doppeln, 121
   oder 501 bei Checkouts, sonst 501.

Code: `lib/features/plans/domain/auto_plan.dart` (reine Berechnung mit Unit-Tests),
Bildschirm in `presentation/auto_plan_screen.dart`.

## Einen Plan spielen

* **Plan starten** beginnt mit Schritt 1. Im Spiel steht „Trainingsplan · Name“ und
  „Schritt x von n“.
* Ist ein Spiel regulär zu Ende, ist der Schritt erledigt. Auf dem Ergebnis-Bildschirm führt
  **Nächster Schritt** zum nächsten Spiel, beim letzten Schritt **Plan abschließen** zur
  Zusammenfassung mit dem Ergebnis jedes Schritts.
* Ein vorzeitig beendetes Spiel zählt als „abgebrochen“, sobald man **Nächster Schritt** tippt.
* **Fertig** oder das Schließen des Spiels verlässt den Plan. Der Fortschritt bleibt gespeichert:
  In der Plan-Ansicht steht dann **Fortsetzen (Schritt x von n)** und **Neu starten**. Ein
  angefangenes, aber nicht beendetes Spiel wird beim Fortsetzen noch einmal gespielt.
* **Nochmal** auf dem Ergebnis-Bildschirm spielt das Spiel außerhalb des Plans noch einmal; mit
  dem Plan geht es danach über die Plan-Ansicht weiter.
* Jedes Spiel eines Plans ist eine normale Session und zählt in Statistik und Zielen.

Ein Durchlauf merkt sich die Schritte vom Start. Wird der Plan währenddessen geändert, läuft der
angefangene Durchlauf mit den alten Schritten zu Ende. Durchläufe gehören zum aktiven Profil.

## Unbekannte Spiele

Ein Plan kann Spiele enthalten, die diese App-Version nicht kennt, etwa wenn er von einem Gerät
mit neuerer Version kommt. Solche Schritte erscheinen als **Nicht verfügbar**, bleiben beim
Bearbeiten unverändert erhalten und werden beim Spielen übersprungen.

## Daten und Sync

Eigene Pläne liegen in der Tabelle `training_plans` (Schritte als JSON
`[{"gameId": …, "config": {…}, "note": …}]`), mit `uid`, `createdAt`, `updatedAt` und
Löschmarkierung `deletedAt`. Sie gehören keinem Profil. Beim [Sync](sync.md) und im JSON-Backup
(ab Version 3) werden sie wie Ziele behandelt: die neuere Änderung gewinnt, Löschungen werden
weitergegeben.

Durchläufe liegen in `plan_runs` (Plan, Profil, Start, Ende, aktueller Schritt, Ergebnisse mit
den `uid`s der Sessions) und bleiben auf dem Gerät.

Code: `lib/features/plans/` (feste Pläne in `domain/builtin_plans.dart`, Ablauf in
`presentation/plan_run_controller.dart`).
