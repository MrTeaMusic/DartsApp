# iPhone/iPad: Daten nach einem Update wieder holen

## Was passiert ist

iOS ordnet alle Daten einer App (Datenbank mit Sessions, Einstellungen) ihrer **App-Kennung**
(Bundle Identifier) zu. Mit kostenloser Apple-ID braucht DartLab eine eigene Kennung, z. B.
`de.ben.dartlab`. Die alte Anleitung ließ sie in Xcode eintragen. Damit stand sie nur als lokale
Änderung im Xcode-Projekt (`ios/Runner.xcodeproj/project.pbxproj`).

Ändert ein Release `pubspec.lock` (zum ersten Mal wieder am 04.11.2026 mit dem PDF-Export), bricht
`git pull` ab, sobald die lokale `pubspec.lock` anders aussieht. Wurde das mit `git reset`,
`git checkout .`, `git stash` oder einem neuen Klon gelöst, war auch die eigene Kennung weg. Der
nächste Build hatte wieder `de.dartlab.dartlab` (oder eine neu gewählte Kennung). Für iOS ist das
eine **andere App**: Sie startet ohne Daten und ohne Einstellungen.

**Die alten Daten sind nicht gelöscht.** Sie liegen in der App mit der alten Kennung, solange
diese App auf dem Gerät ist, auch wenn sie nach 7 Tagen nicht mehr startet.

Seit diesem Fix steht die Kennung in `ios/Flutter/Signing.local.xcconfig`. Die Datei ist von git
ausgenommen, `git pull` fasst sie nicht an. Updates laufen über `tools/ios/update.sh`.

## Zurückholen

1. Auf dem Mac den neuen Stand holen. Falls `git pull` wieder abbricht, die lokalen Änderungen
   beiseitelegen (nicht wegwerfen, die alte Kennung steckt vielleicht darin):
   ```bash
   cd ~/DartsApp
   git stash
   git pull
   ```
2. iPhone anschließen und nachsehen, welche Kennung die alte App hat:
   ```bash
   tools/ios/signing.sh --geraet "Bens iPhone"
   ```
   Das Skript zeigt die Kennungen aus dem Xcode-Projekt, aus `git stash` und die DartLab-Apps auf dem
   Gerät. Alternativ: Xcode › Window › Devices and Simulators › das iPhone › „Installed Apps“.
   Zwei DartLab-Icons auf dem iPhone heißen: Die alte App ist noch da.
3. Die **alte** Kennung eintragen (Enter übernimmt den Vorschlag) oder direkt:
   ```bash
   tools/ios/signing.sh de.ben.dartlab
   ```
4. Installieren:
   ```bash
   tools/ios/update.sh "Bens iPhone"
   ```
   Das installiert über die alte App. Sie startet mit allen alten Sessions und Einstellungen.
5. Die leere App vom letzten Update kann danach weg (Icon lange drücken › App entfernen). Was seit dem
   Update nur dort gespielt wurde, geht damit verloren, außer es ist schon per Sync auf dem PC oder in
   der Cloud.

## Wenn die alte App nicht mehr auf dem Gerät ist

Dann sind die Daten auf dem iPhone selbst weg. Was per Sync (PC-Hub oder Cloud) abgeglichen war,
kommt zurück: In DartLab unter **Optionen › Sync zwischen Geräten** dieselbe Rolle, Adresse und denselben Schlüssel
wie vorher eintragen. Die Sessions holt der nächste Abgleich. Die übrigen Einstellungen (Look,
Autodarts-Host, Caller usw.) müssen neu gesetzt werden. Ein Backup aus **Optionen › Daten** (JSON)
lässt sich ebenfalls wieder einspielen.
