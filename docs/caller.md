# Caller

Eine Stimme sagt Punkte und Rest an, wie bei einem Turnier. Standard ist Englisch wie im
Fernsehen („One hundred and eighty!“), Deutsch ist wählbar.

## Was angesagt wird

| Situation | Englisch | Deutsch |
|---|---|---|
| Spielbeginn | „Game on!“ | „Los geht's!“ |
| Aufnahme | „Sixty“, „One hundred and forty“ | „Sechzig“, „Hundertvierzig“ |
| 180 (betont: etwas langsamer, höher) | „One hundred and eighty!“ | „Hundertachtzig!“ |
| 0 Punkte | „No score“ | „Keine Punkte“ |
| Überworfen | „Bust“ | „Überworfen“ |
| Rest auf einem Finish (≤ 170, mit 3 Darts checkbar) | „You require thirty-two“ | „Du brauchst zweiunddreißig“ |
| Checkout im Training | „Game shot!“ | „Ausgecheckt!“ |
| Checkout, es folgen weitere Legs | „Game shot, and the leg!“ | „Ausgecheckt, Leg gewonnen!“ |
| Checkout im letzten Leg | „Game shot, and the match!“ | „Ausgecheckt, Match gewonnen!“ |

Zahlen werden ausgeschrieben, damit die Stimme sie britisch spricht („one hundred *and*
forty“). Angesagt wird nach jeder abgeschlossenen Aufnahme (drei Darts, Bust, Checkout oder
„Weiter“), nie nach Rückgängig oder Korrekturen. Wird eine Aufnahme korrigiert und erneut
abgeschlossen, kommt die Ansage noch einmal mit dem richtigen Wert.

### Welche Spiele

Der Caller kennt keine Spiel-IDs, er liest die Daten, die jedes Spiel ohnehin liefert:

* **3-Dart-Average** in den Kennzahlen (X01, T20-Training, Score-Ziel, Highscore-Jagd):
  jeder Dart zählt seinen Wert, also werden die Punkte der Aufnahme angesagt.
* **Checkout-Quote** und Anzeige „Rest“ (X01, 121, Checkout-Training, Catch 40): zusätzlich
  „Bust“, „You require …“ und „Game shot“. Bei 121 & Co. kommen auch die Punkte der Aufnahme.
* Alle anderen (Around the Clock, Cricket, Shanghai, Bob's 27, …) bleiben still, weil dort
  die Summe einer Aufnahme nichts aussagt.

Ein neues Spiel bekommt den Caller also automatisch, wenn es `average` bzw. `checkoutRate`
in `GameResult.metrics` meldet. Bei X01 mit Double-In zählt vor dem Einstieg nur, was vom
Rest abgezogen wurde.

## Einstellungen

Optionen › **Caller**:

* **Caller an** (Standard: an). Der Knopf mit dem Sprecher-Symbol in der App-Leiste der
  Spielansicht schaltet genau diese Einstellung um (stumm/an) und bricht eine laufende Ansage ab.
* **Sprache**: Englisch (wie im TV) oder Deutsch.
* **Lautstärke** und **Tempo**.
* **Ansagen** einzeln: Punkte jeder Aufnahme, Rest auf einem Finish, Checkout, Spielbeginn.
* **Probe hören** spielt „One hundred and eighty!“ und „You require thirty-two“.

Gespeichert wird unter eigenen Schlüsseln `caller.*` in den SharedPreferences.

## Stimmen

Die Sprachausgabe kommt von der Plattform (Paket `flutter_tts`): AVSpeechSynthesizer auf
macOS und iOS, Windows.Media.SpeechSynthesis auf Windows. DartLab wählt beim ersten Sprechen
die beste verfügbare Stimme der gewählten Sprache: zuerst nach Qualität (Apple: Premium vor
Erweitert vor Standard; Windows: „Natural“-Stimmen zuerst), dann britisches vor
amerikanischem Englisch bzw. Deutschland vor Österreich/Schweiz. Spaßstimmen von macOS
(Zarvox, Bubbles, …) kommen nur zum Zug, wenn nichts anderes da ist. Fehlt eine Stimme der
Sprache, spricht die Standardstimme; geht gar nichts, bleibt der Caller still, ohne Fehler.

Bessere Stimmen nachladen:

* **macOS**: Systemeinstellungen › Bedienungshilfen › Gesprochene Inhalte › Systemstimme ›
  Stimmen verwalten, z. B. „Englisch (Vereinigtes Königreich)“ › Daniel/Serena (Premium).
* **iOS/iPadOS**: Einstellungen › Bedienungshilfen › Gesprochene Inhalte › Stimmen ›
  Englisch › Stimme mit „Erweitert“/„Premium“ laden.
* **Windows**: Einstellungen › Zeit und Sprache › Sprache und Region › Sprache hinzufügen
  (Englisch (Vereinigtes Königreich), Sprachausgabe mit installieren). Die neuen
  „natürlichen“ Stimmen der Sprachausgabe sind für Apps nicht immer verfügbar; dann nimmt
  DartLab die beste klassische Stimme (z. B. Hazel, George).

Nach dem Laden einer Stimme die App neu starten.

Auf iOS spielt der Caller auch neben Musik (andere Audioquellen werden kurz leiser) und
auch bei eingeschaltetem Stummschalter. Leiser bzw. aus geht es über Lautstärke oder den
Stumm-Knopf in der Spielansicht.

## Für Entwickler

Öffentliche API (`lib/features/caller/caller.dart`), auch für Match-/Turniermodus gedacht:

```dart
final caller = ref.read(callerProvider);
caller.gameOn();
caller.visit(score: 140, remaining: 32); // remaining nur, wenn auscheckbar
caller.visit(bust: true, remaining: 40);
caller.gameShot(GameShotKind.leg);
caller.announce([const ScoreCall(180)]);
caller.stop();
```

Jeder Aufruf beachtet die Einstellungen. Der Anschluss ans Trainingsspiel steckt an genau
einer Stelle: `lib/features/caller/presentation/training_game_caller.dart` hört auf
`activeGameProvider` und entscheidet über `TrainingCallPlanner`, was gesagt wird. Er ist in
`app.dart` neben dem Dart-Feedback aktiviert.

In Tests wird `speechEngineProvider` überschrieben (`pumpApp` setzt automatisch eine
`FakeSpeechEngine`, die nur mitschreibt), damit das echte Plugin nie angesprochen wird.

### Plattform-Konfiguration

* **macOS/iOS**: keine Entitlements und keine Info.plist-Einträge nötig (nur Ausgabe, kein
  Mikrofon, keine Spracherkennung). `flutter_tts` unterstützt noch kein Swift Package
  Manager, deshalb baut Flutter dieses eine Plugin über CocoaPods. Dafür liegen
  `ios/Podfile` und `macos/Podfile` im Repo, und die `Flutter/*.xcconfig` binden die
  Pods-Konfiguration ein. Beim ersten Build auf dem Mac läuft `pod install` und trägt die Pods
  ins Xcode-Projekt ein (Änderungen an `Runner.xcodeproj`, neue `Podfile.lock`): beides
  einfach mit einchecken. Voraussetzung ist CocoaPods (siehe Build-Anleitung).
* **Windows**: Das Plugin holt beim Build das NuGet-Paket `Microsoft.Windows.CppWinRT`.
  Dafür muss `nuget.exe` im PATH liegen (siehe Build-Anleitung).

### Grenzen

* Klang, Stimmwahl und Betonung lassen sich nur auf echten Geräten prüfen; die Tests prüfen
  Sätze und Ablauf mit einer Fake-Sprachausgabe.
* Betonung ist plattformneutral über Tempo und Tonhöhe gelöst, nicht über SSML.
* „Game shot, and the leg“ nennt (noch) nicht die Leg-Nummer („the first leg“).
