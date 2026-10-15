# Checkout-Quiz

Checkout-Wege auswendig lernen, ganz ohne zu werfen. Gedacht fürs Handy (Bus, Couch, Pause), läuft
aber auch auf dem Desktop. Zu finden unter **Training › Modi › Checkout-Quiz**.

Code in `lib/features/quiz/`, Tests in `test/features/quiz/` und `test/widgets/checkout_quiz_test.dart`.

## Ablauf

Jede Frage zeigt einen Rest (2–170) und wie viele Darts noch übrig sind (3, 2 oder 1). Die Antwort
wird über eine kleine Tastatur eingegeben: erst **S**, **D** oder **T** (Single ist voreingestellt und
springt nach jedem Dart zurück), dann die Zahl; dazu **25** und **Bull**. Darüber (auf dem Desktop
links daneben) stehen die Slots der Darts und die Summe.

* **Prüfen** wertet den eingegebenen Weg aus.
* **Nicht möglich** sagt: Mit diesen Darts gibt es kein Finish. Stimmt das und ist „Danach stellen“
  an, folgt eine zweite Frage: Mit welchen Darts stellst du dir einen guten Rest?
* Nach der Auflösung geht es mit **Weiter** zur nächsten Frage, mit **Beenden** zum Ergebnis.

### Was als richtig zählt

* **Finish:** jeder gültige Weg mit höchstens so vielen Darts wie übrig, der genau auf 0 geht und mit
  einem Double endet (Bull zählt als Double). Bei Master-Out darf der letzte Dart auch ein Triple sein.
  Es muss nicht der Weg der App sein. Stimmt er mit dem empfohlenen Weg überein (gleiche Darts, beim
  Setup-Dart egal in welcher Reihenfolge), steht das dabei.
* **Nicht möglich:** richtig, wenn es mit diesen Darts wirklich kein Finish gibt (z. B. 169, Bogey-Zahlen
  wie 159, oder 61 mit einem Dart).
* **Stellen:** Die Stell-Darts (alle übrigen Darts, kein Finish) werden mit dem Vorschlag des
  `SetupAdvisor` verglichen. Jeder Rest bekommt eine Stufe: 1 = mit einem Dart checkbar, 2 = mit zwei,
  3 = mit drei, 4 = gar nicht oder Bust. Richtig ist jeder Weg, dessen Rest mindestens so gut ist wie
  der Rest des Vorschlags. Ein schlechterer Rest zählt als falsch.

### Auflösung

Die Auflösung zeigt immer: deine Antwort, den empfohlenen Weg der App, bei „Nicht möglich“ den
Vorschlag zum Stellen und bis zu drei weitere mögliche Wege (ohne die eigene Antwort). Der empfohlene
Weg kommt bei Double-Out aus der üblichen Checkout-Tabelle (`CheckoutTable` in
`lib/features/games/domain/games/checkout/`), wie auf Checkout-Charts, und ist derselbe wie im
Checkout-Training und im Match. Die weiteren Wege sortiert die Kostensuche des `CheckoutCalculator`. Im Modus Training gibt es dazu eine kurze Erklärung, warum ein Weg nicht geht
(Bust, Summe stimmt nicht, kein Double am Ende, zu viele Darts, Bogey-Zahl, Höchstwert je Dartzahl).

## Modi

| Modus | Ablauf |
|---|---|
| Training | ohne Zeitlimit, nach jeder Antwort die Auflösung mit Erklärung |
| Zeit (60 s) | so viele richtige Antworten wie möglich; nach einer Antwort kommt sofort die nächste Frage, die letzte Auflösung steht klein darüber |

## Einstellungen

* **Bereich:** 2–40, 41–100, 101–170 oder alle.
* **Darts:** 3, 2, 1 oder gemischt (1 Dart bis 60, 2 Darts bis 120, sonst 3).
* **Out:** Double-Out (Standard) oder Master-Out.
* **Nur checkbare Reste:** lässt Reste ohne Finish weg (z. B. die Bogey-Zahlen 159, 162, 163, 165,
  166, 168, 169 bei drei Darts).
* **Danach stellen:** fragt nach „Nicht möglich“ den Stell-Weg ab.

Die Einstellungen werden gemerkt (`SharedPreferences`, Schlüssel `quiz.config`).

## Schwache Reste kommen öfter

Die Auswahl ist zufällig, aber gewichtet. Grundlage sind alle gespeicherten Antworten aus dem Verlauf
(es gibt keine eigene Tabelle dafür). Je Frage (Rest + Darts) führt `QuizScheduler` ein gleitendes Mittel
(Faktor 0,4) über falsche Antworten und Antwortzeit:

* Gewicht = 1 + 3 × Anteil falsch + Zuschlag für langsame Antworten (ab 5 s) + 1,5, wenn die letzte
  Antwort falsch war.
* Sicher (mindestens 3 Antworten, fast nie falsch, unter 4 s): Gewicht 0,4.
* Noch nie gestellt: Gewicht 1,2, damit Neues drankommt.
* Im Durchgang kommt eine falsche Frage nach drei anderen Fragen noch einmal; die letzten vier Fragen
  werden nicht sofort wiederholt.

Der Setup-Screen zeigt die schwächsten Reste als Chips.

## Wertung und Bestwerte

Während des Quiz: richtige Antworten, laufende Serie, im Zeit-Modus die Restzeit. Am Ende: Quote,
beste Serie, Ø Antwortzeit und die Fehler mit dem empfohlenen Weg.

Persönliche Bestwerte (aus dem Verlauf berechnet):

* **Zeit-Rekord:** meiste richtige Antworten in einem vollen 60-s-Durchgang. Wer vorher beendet, stellt
  keinen Rekord auf.
* **Beste Serie:** längste Serie richtiger Antworten in einer Session, beide Modi.
* **Bestes Tempo:** kleinste Ø Antwortzeit einer Session mit mindestens 10 Antworten und mindestens
  der Hälfte richtig.

Neue Bestwerte werden im Ergebnis hervorgehoben.

## Speicherung und Statistik

Jedes Quiz wird als normale Session mit der Spiel-ID `checkout_quiz` gespeichert, ohne Würfe
(`dartCount` 0). Im Ergebnis (`resultJson`) stehen die Einstellungen, die Kennzahlen (`answered`,
`correct`, `correctRate`, `bestStreak`, `avgSeconds`) und alle Antworten (Rest, Darts, richtig, Zeit,
eingegebener Weg). Ein Quiz ohne Antwort wird nicht gespeichert. Sync und Backup übernehmen die
Session wie jede andere.

* Zählt mit: Sessions, Trainingstage, Trainingszeit, Serie, Tagesziel (Sessions und Minuten), Verlauf,
  Spielliste in der Statistik (Hauptkennzahl `correctRate`, höher besser).
* Zählt nicht mit: Darts, 3-Dart-Average, Checkout- und Double-Quote, Heatmap, Rekorde aus Würfen.
  Es gibt keine erfundenen Würfe. In Listen steht „N Fragen“ statt „N Darts“
  (`throwlessGames` in `game_metrics.dart`).
* Die Session-Detailseite zeigt alle Antworten; **Nochmal** öffnet den Setup-Screen.

Das Quiz ist kein Eintrag im `GameCatalog` (es gibt keine Würfe zum Durchspielen) und kann darum
nicht in Trainingsplänen oder Matches vorkommen.
