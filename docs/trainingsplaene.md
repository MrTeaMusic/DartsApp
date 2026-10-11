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
