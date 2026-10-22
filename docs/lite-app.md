# DartLab Lite (nur Ansicht)

DartLab Lite ist dieselbe App mit einem anderen Schalter beim Bauen: Sie zeigt nur Bens Statistik
und seine Sessions. Spielen, Trainieren und Eintragen gibt es dort nicht, das bleibt der Haupt-App.
Gedacht ist sie für Menschen, die Bens Fortschritt sehen sollen, ohne selbst zu spielen.

## Bauen

```
flutter build apk --dart-define=DARTLAB_LITE=true
```

Ohne `--dart-define=DARTLAB_LITE=true` bleibt die App, wie sie ist. Der Schalter steht in
`lib/core/lite.dart` (`kLiteBuild`). Gelesen wird er über `liteProvider`; Tests können ihn mit
`liteProvider.overrideWithValue(true)` setzen.

## Was Lite zeigt

* **Unten zwei Reiter:** Statistik und Optionen. Die übrigen Seiten der App gibt es als Routen
  weiter, aber jeder Pfad außerhalb von Statistik, Verlauf, Session-Detail und Optionen leitet auf
  `/statistik` um (`lib/features/lite/domain/lite_gate.dart`).
* **Nur lesen:** Löschen, Bearbeiten, Importieren, „Nochmal spielen“, Zielanlage, Live- und
  Planlinks sind ausgeblendet. Die Statistik-Reiter, der Verlauf und die Session-Details sind
  dieselben wie in der Haupt-App.
* **Welches Profil:** Gezeigt wird Bens Standardprofil (`default-player`). Hat es keine Session,
  nimmt Lite das Profil mit den meisten Sessions. Gibt es mehrere Profile, lässt sich unter
  Optionen „Statistik von“ umstellen.

## Erster Start

Ohne Einrichtung öffnet sich `/willkommen` (ohne Navigationsleiste):

1. Adresse des Cloud-Speichers und Geheimnis eintragen (dieselbe Eingabeprüfung wie in der
   Haupt-App, das Geheimnis lässt sich einfügen). Beides gibt es bei Ben.
2. „Verbinden“ prüft den Server (`hello`) und ob es zum Geheimnis einen Tresor gibt. Lite legt
   **nie** einen Tresor an. Fehlt er, steht eine klare Meldung da, und es wird nichts gespeichert.
3. Dann wird einmal abgeglichen („Daten werden geladen …“). Erst danach speichert Lite Adresse und
   Geheimnis (Rolle Cloud) und öffnet die Statistik.

Fehler (nicht erreichbar, falsches Geheimnis, Serverfehler, kein Tresor, Tresor nicht lesbar)
bekommen je eine eigene Meldung. Die Einrichtung bleibt nach einem Neustart erhalten.

Bens umbenanntes Profil gewinnt beim ersten Abgleich nur, weil Lite das leere lokale Platzhalter-
profil „Ich“ vorher auf das Jahr 2000 zurückdatiert. Sonst würde der Platzhalter nach der
Abgleichsregel „neuere Änderung gewinnt“ Bens Namen überschreiben.

## Optionen

* **Verbindung:** Adresse und Geheimnis ändern, Status des letzten Abgleichs, „Jetzt abgleichen“.
  Kein Hub und kein Heimnetz.
* **Verbindung neu einrichten:** fragt nach, vergisst nur Adresse und Geheimnis und führt zurück
  zur Einrichtung. Die schon geladenen Daten bleiben auf dem Gerät.
* **Update:** wie in der Haupt-App, siehe unten.
* **Über:** Version und Build, dazu „Nur Ansicht. Spielen und Eintragen geschieht in der
  Haupt-App.“

## Updates auf Android

Lite sucht beim Start höchstens einmal am Tag nach einer neuen Version, außerdem auf Knopfdruck
unter Optionen. Eine Version mit Build 0 meldet nie etwas. Auf Android sucht Lite im Release das
Asset `DartLab-Lite-android.apk`, „Herunterladen“ öffnet dessen Link im Browser. Dazu stehen drei
Schritte da: 1 Herunterladen, 2 Datei öffnen, 3 Installieren. Beim ersten Mal muss Android das
Installieren aus dieser Quelle erlauben. Auf iOS bleibt der Hinweis wie in der Haupt-App.

## Tests

Die Tests liegen in `test/features/lite`, `test/features/update/update_android_test.dart` und
`test/widgets/lite_*_test.dart`. Sie nutzen `test/helpers/fake_cloud.dart` und den
`cloudHttpClientProvider`, es geht also nie ins echte Netz. `lite_navigation_test.dart` besucht alle
Routen der App im Lite-Modus und prüft, dass keine Fehlerseite erscheint.
