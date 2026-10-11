# Build- und Installationsanleitung

DartLab wird aus einer Flutter-Codebasis für Windows, macOS und iOS gebaut. Jede Plattform
muss auf ihrem eigenen Betriebssystem gebaut werden: Windows-Builds auf Windows, macOS- und
iOS-Builds auf einem Mac.

## Gemeinsame Voraussetzungen

1. Flutter (stable, 3.47 oder neuer) installieren: <https://docs.flutter.dev/get-started/install>.
2. Repository klonen und Abhängigkeiten holen:
   ```bash
   git clone https://github.com/MrTeaMusic/DartsApp.git
   cd DartsApp
   flutter pub get
   ```
3. `flutter doctor` ausführen. Für die gewünschte Plattform sollte dort alles grün sein.

## Windows

**Voraussetzung:** Visual Studio 2022 (die kostenlose Community-Version reicht) mit der
Arbeitslast **„Desktopentwicklung mit C++“**. Visual Studio Code reicht nicht.

```powershell
flutter run -d windows             # zum Ausprobieren (Debug)
flutter build windows --release    # fertige App
```

Die fertige App liegt in `build\windows\x64\runner\Release\`. Der ganze Ordner gehört dazu
(`dartlab.exe` plus DLLs und `data\`). Zum Weitergeben den Ordner zippen. Beim ersten Start
kann die Windows-Firewall fragen, ob DartLab ins lokale Netzwerk darf: Für Autodarts
„Private Netzwerke“ erlauben.

## macOS

**Voraussetzung:** Xcode aus dem App Store, danach einmal
`sudo xcodebuild -runFirstLaunch` und `sudo gem install cocoapods` (oder `brew install cocoapods`).

```bash
flutter run -d macos               # zum Ausprobieren
flutter build macos --release      # fertige App
```

Ergebnis: `build/macos/Build/Products/Release/DartLab.app`. Nach `/Programme` ziehen.

**Gatekeeper:** Die App ist nicht notarisiert. Auf dem eigenen Mac startet sie normal. Auf einem
anderen Mac (oder nach dem Herunterladen aus GitHub Actions) blockiert macOS den ersten Start.
Dann: Rechtsklick auf die App › „Öffnen“, oder in den Systemeinstellungen unter
„Datenschutz & Sicherheit“ auf „Dennoch öffnen“. Für eine Weitergabe ohne Warnung braucht es
einen bezahlten Apple-Developer-Account (Developer ID + Notarisierung).

Netzwerkzugriff (für Autodarts) und Dateidialoge (Export/Import) sind in den Entitlements
freigeschaltet (`macos/Runner/*.entitlements`).

## iOS (iPhone und iPad)

**Voraussetzung:** ein Mac mit Xcode, ein iPhone/iPad mit USB-Kabel, eine Apple-ID.
Ein kostenloser Account reicht für die eigenen Geräte.

1. iPhone per Kabel anschließen, entsperren und dem Mac vertrauen.
2. Auf dem iPhone den **Entwicklermodus** einschalten: Einstellungen › Datenschutz & Sicherheit ›
   Entwicklermodus (erscheint, nachdem das Gerät einmal mit Xcode verbunden war). Neustart.
3. `open ios/Runner.xcworkspace` öffnen (die `.xcworkspace`, nicht `.xcodeproj`).
4. Links „Runner“ wählen › Target „Runner“ › **Signing & Capabilities**:
   * „Automatically manage signing“ an,
   * bei **Team** die eigene Apple-ID wählen (ggf. erst unter Xcode › Settings › Accounts hinzufügen),
   * die **Bundle Identifier** auf etwas Eigenes ändern, z. B. `de.<deinname>.dartlab`.
     Die Vorgabe `de.dartlab.dartlab` kann schon vergeben sein.
5. Im Terminal:
   ```bash
   flutter run -d <iPhone-Name> --release
   ```
   (`flutter devices` zeigt den Namen.)
6. Beim ersten Start: Einstellungen › Allgemein › VPN & Geräteverwaltung › dem eigenen
   Entwicklerzertifikat vertrauen.
7. Für Autodarts fragt iOS beim ersten Verbindungsversuch nach **„Lokales Netzwerk“**: erlauben.
   Wurde das abgelehnt: Einstellungen › DartLab › Lokales Netzwerk einschalten.

**Wichtig bei kostenlosem Account:** Das Profil läuft nach **7 Tagen** ab. Danach startet die App
nicht mehr, bis sie erneut per `flutter run` installiert wird. Die Daten bleiben dabei erhalten.
Mit einem bezahlten Developer-Account (99 €/Jahr) gilt das Profil ein Jahr, und TestFlight wird möglich.

Exportierte Dateien (Backup, CSV) liegen auf iOS in der Dateien-App unter
„Auf meinem iPhone › DartLab“.

## Automatische Builds (GitHub Actions)

* `.github/workflows/flutter.yml`: `flutter analyze` und alle Tests, bei jedem Pull Request und auf `main`.
* `.github/workflows/build.yml`: baut Windows, macOS und iOS (iOS ohne Signatur) bei jedem
  Pull Request; manuell startbar unter „Actions › Native Builds › Run workflow“.
  Die Windows- und macOS-App hängen als Artefakte am Lauf und lassen sich dort herunterladen
  (für macOS gilt der Gatekeeper-Hinweis oben). Für iOS prüft der Lauf nur, dass der Build
  durchgeht; auf ein Gerät kommt die App über Xcode wie oben beschrieben.

## Häufige Probleme

| Problem | Lösung |
|---|---|
| `Unable to find suitable Visual Studio toolchain` | In Visual Studio Installer die Arbeitslast „Desktopentwicklung mit C++“ hinzufügen. |
| `CocoaPods not installed` | `brew install cocoapods`, dann `flutter clean && flutter pub get`. |
| iOS: „No profiles for … were found“ | In Xcode bei Signing ein Team wählen und eine eigene Bundle-ID eintragen. |
| iOS: App startet nach einer Woche nicht mehr | Kostenloses Profil abgelaufen, neu mit `flutter run` installieren. |
| Autodarts verbindet nicht | In DartLab unter Optionen › Autodarts „Verbindung testen“. Die Hinweise dort nennen die wahrscheinliche Ursache. Mehr in [autodarts-protokoll.md](autodarts-protokoll.md). |
