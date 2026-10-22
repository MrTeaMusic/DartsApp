# DartLab Lite für Android

## Was ist das?

**DartLab Lite** ist eine kleine Android-App, mit der man die **Statistiken ansehen** kann.
Sie ist nur zum Ansehen gedacht: Spielen, Trainieren und Einstellungen wie in der großen App
gibt es hier nicht. Die App kommt als **APK-Datei** (so heißen Android-Installationsdateien)
aus dem GitHub-Release. Im Play Store gibt es sie nicht.

Die App heißt auf dem Handy „DartLab Lite“ und läuft im Hoch- und im Querformat.

## APK bekommen

1. Die Seite <https://github.com/MrTeaMusic/DartsApp/releases/latest> öffnen (am Handy geht das
   direkt im Browser).
2. Unter „Assets“ auf **`DartLab-Lite-android.apk`** tippen und die Datei herunterladen.

Die APK ist nur dabei, wenn der Signierschlüssel bei GitHub hinterlegt ist
(siehe [android-signierung.md](android-signierung.md)). Fehlt `DartLab-Lite-android.apk` im
Release, ist das noch nicht geschehen oder der Android-Bau ist fehlgeschlagen. Windows und
macOS sind trotzdem im Release. Die Details stehen im Lauf unter „Actions › Release“.

## Installieren (einmalig)

1. Die heruntergeladene Datei öffnen (Benachrichtigung „Download abgeschlossen“ antippen oder in
   der Dateien-App unter „Downloads“).
2. Beim ersten Mal fragt Android, ob der Browser (oder die Dateien-App) **Apps installieren**
   darf. **„Einstellungen“** antippen und **„Installation aus dieser Quelle erlauben“**
   einschalten, dann zurück und **„Installieren“** antippen.
3. Es kann ein Hinweis von **Google Play Protect** erscheinen, etwa „App nicht aus dem Play
   Store“ oder „Unbekannter Entwickler“. Das ist normal, weil die App nicht im Play Store liegt.
   Auf **„Trotzdem installieren“** (bei manchen Geräten erst „Weitere Details“) tippen.
4. **„Öffnen“** antippen. Die App liegt jetzt auch auf dem Startbildschirm.

Wer die Installation aus dieser Quelle nicht mehr erlaubt haben möchte, schaltet es nach dem
Installieren in den Einstellungen wieder aus.

## Update

Neue Version = neue APK. Der Ablauf ist derselbe wie bei der Installation:

1. Im neuesten GitHub-Release `DartLab-Lite-android.apk` herunterladen.
2. Öffnen und **„Aktualisieren“** (oder „Installieren“) antippen.

Die vorhandene App wird dabei **ersetzt, nicht doppelt installiert**, und ihre Daten bleiben
erhalten. Das klappt, weil jede APK mit demselben Schlüssel unterschrieben ist und eine höhere
Versionsnummer hat. **Nicht** vorher deinstallieren, sonst sind die Daten weg.

Zeigt Android „App nicht installiert“ oder „Konflikt mit einem vorhandenen Paket“, wurde die alte
App mit einem anderen Schlüssel installiert (z. B. mit einer Test-APK). Dann hilft nur die alte
App zu deinstallieren und die neue zu installieren.

## Hinweise

* Die App braucht nur die Berechtigung **Internet**, keine weiteren.
* Zugriff auf unverschlüsselte (http) Adressen ist gesperrt, es werden nur https-Verbindungen
  benutzt.
* Die Version steht in den Android-Einstellungen unter Apps › DartLab Lite.

## Für Entwickler

* Die Lite-Variante wird mit `--dart-define=DARTLAB_LITE=true` gebaut:
  `flutter build apk --release --dart-define=DARTLAB_LITE=true`.
  Für die Android-Tools (SDK, JDK 17) siehe <https://docs.flutter.dev/platform-integration/android/setup>.
* Paketname (`applicationId`): `de.dartlab.lite`, damit die Lite-App nicht mit einer späteren
  Vollversion kollidiert.
* Bei jedem Pull Request baut `build.yml` die Lite-APK als Test (mit Debug-Schlüssel, Artefakt
  `dartlab-lite-android-test`). Der Release-Workflow baut sie mit dem Release-Schlüssel und legt
  sie nur dann ins Release. Fehlen die Geheimnisse, gibt der Job eine Warnung aus und legt eine
  Test-APK als Artefakt `android-test-unsigned` ab, die nicht ins Release kommt.
* Der Android-Job kann das Release nie blockieren: Es wird auch ohne APK veröffentlicht.
