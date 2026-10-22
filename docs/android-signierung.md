# Android: Signierschlüssel einrichten

Diese Anleitung ist für den Besitzer des Repositories (einmalig, ca. 10 Minuten). Ohne sie
enthält das GitHub-Release keine Android-App. Windows und macOS werden davon nicht berührt.

## Wozu der Schlüssel dient

Jede Android-App ist mit einem **Schlüssel** unterschrieben. Android installiert ein Update nur
dann über eine vorhandene App, wenn beide mit **demselben** Schlüssel unterschrieben sind.
Deshalb gibt es genau einen Schlüssel für DartLab Lite, und der muss für immer derselbe bleiben.

* Der Schlüssel ist die Datei `dartlab-release.jks` plus ihr Passwort.
* Er liegt **nicht** im Repository (das ist öffentlich), sondern als geheimer Wert bei GitHub.
  Der Release-Workflow baut damit die APK und unterschreibt sie.
* Ohne die vier Werte baut der Workflow **keine** Release-APK. Das ist Absicht: Eine APK mit
  einem Wegwerf-Schlüssel (Debug-Schlüssel) ließe sich nie durch ein späteres Update ersetzen.
  Man müsste die App erst löschen und neu installieren, und die Daten in ihr wären weg.

Der Schlüssel wurde schon erzeugt. Die Dateien liegen im Projektordner unter
`dartlab/android-signing/`:

| Datei | Inhalt |
|---|---|
| `dartlab-release.jks` | der Schlüssel selbst |
| `keystore-base64.txt` | derselbe Schlüssel als Text in einer Zeile (für GitHub) |
| `geheimnisse.txt` | die Namen und Werte der vier GitHub-Geheimnisse |

## Schritte bei GitHub

1. Im Repository `MrTeaMusic/DartsApp` auf **Settings** gehen (Zahnrad-Reiter ganz rechts).
2. Links **Secrets and variables › Actions** öffnen.
3. **New repository secret** anklicken und **viermal** wiederholen. Der Name steht jeweils
   links, der Wert kommt aus den Dateien:

   | Name (genau so schreiben) | Wert |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | der gesamte Inhalt von `keystore-base64.txt` (eine lange Zeile, ohne Leerzeichen am Rand) |
   | `ANDROID_KEYSTORE_PASSWORD` | der Wert dahinter in `geheimnisse.txt` |
   | `ANDROID_KEY_ALIAS` | `dartlab` |
   | `ANDROID_KEY_PASSWORD` | der Wert dahinter in `geheimnisse.txt` |

   Beim Kopieren darauf achten, dass nichts fehlt und kein Zeilenumbruch oder Leerzeichen
   dazukommt. Die Passwörter enthalten Buchstaben, Ziffern und `+`, `/`, `=`.
4. Zum Prüfen: unter **Actions › Release › Run workflow** (Branch `main`) einmal manuell starten.
   Im Job „android“ steht dann „Release-Schlüssel gefunden“, und das neue Release enthält
   `DartLab-Lite-android.apk`. Steht dort stattdessen eine gelbe Warnung, fehlt ein Geheimnis.

## Danach aufräumen und sichern

1. **Sichern:** `dartlab-release.jks` und die Passwörter (aus `geheimnisse.txt`) an einem sicheren
   Ort ablegen, am besten im Passwort-Manager (Datei als Anhang, Passwörter als Einträge).
   Eine zweite Kopie auf einem USB-Stick, der im Schrank liegt, schadet nicht.
2. **Löschen:** Danach die Dateien im Projektordner `dartlab/android-signing/` löschen. Die Datei
   `keystore-base64.txt` ist so gut wie der Schlüssel selbst: Wer sie hat, kann Apps in
   DartLabs Namen unterschreiben.
3. Den Schlüssel **nie** ins Repository legen, nie per Mail oder Chat verschicken. (`.gitignore`
   schließt `*.jks`, `*.keystore` und `key.properties` zwar aus, aber verlassen sollte man sich
   darauf nicht.)

## Wenn der Schlüssel verloren geht

Dann lassen sich **nie wieder Updates über die alte App installieren**. Es hilft nur ein neuer
Schlüssel, und alle Nutzer müssen die App einmal **deinstallieren** und neu installieren. Dabei
gehen die Daten in der App verloren. Deshalb ist die Sicherung oben wichtig.

Dagegen ist es unkritisch, wenn nur die GitHub-Geheimnisse gelöscht werden: Mit den gesicherten
Dateien lassen sie sich jederzeit neu anlegen.

## Für Entwickler: lokal bauen

* Ohne Schlüssel baut `flutter build apk --release --dart-define=DARTLAB_LITE=true` mit dem
  Debug-Schlüssel. Das reicht zum Testen auf dem eigenen Gerät. Diese APK nie weitergeben.
* Mit Schlüssel: Datei `android/key.properties` anlegen (wird nicht eingecheckt):

  ```properties
  storeFile=/pfad/zu/dartlab-release.jks
  storePassword=...
  keyAlias=dartlab
  keyPassword=...
  ```

  Alternativ die Umgebungsvariablen `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS` und `ANDROID_KEY_PASSWORD` setzen. Sind nur einige gesetzt, bricht der
  Build mit einer Fehlermeldung ab.
* Versionsnummer: `--build-name=x.y.z` wird zum `versionName`, `--build-number=n` zum
  `versionCode`. Der Release-Workflow setzt beides selbst; der `versionCode` steigt mit jedem
  Lauf, deshalb gilt jede neue Release-APK für Android als Update.
