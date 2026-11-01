# DartLab unter Linux und auf dem Raspberry Pi

Stand: Vorbereitung für ein späteres Installationsskript (Raspberry Pi mit
Raspberry Pi OS). Das Skript selbst gibt es noch nicht.

## Builds

* Der Release-Workflow legt bei jedem Release zwei Archive dazu:
  `DartLab-linux-x64.tar.gz` (PC) und `DartLab-linux-arm64.tar.gz`
  (Raspberry Pi 4/5 mit **64-Bit**-Raspberry-Pi-OS). 32-Bit-Systeme werden
  nicht gebaut.
* Jedes Archiv enthält einen Ordner `dartlab/`: ausführbare Datei
  `dartlab/dartlab`, Bibliotheken in `lib/`, Daten in `data/`, dazu
  `data/dartlab.png` (Symbol) und `data/dartlab.desktop` (Vorlage für
  Startmenü und Autostart, `@BUNDLE@` durch den Installationsordner ersetzen).
* Die arm64-Version wird auf einem arm64-Runner von GitHub nativ gebaut, weil
  es für Linux-arm64 kein fertiges Flutter-Archiv gibt (Flutter per git).
* Selbst bauen: `flutter build linux --release` auf einem Linux-Rechner mit
  `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`.

## Laufzeit-Pakete auf dem Zielgerät

Auf Raspberry Pi OS mit Desktop sind GTK 3 und GStreamer meist schon da. Für
die Caller-Sounddateien (mp3) braucht GStreamer die Plugins
`gstreamer1.0-plugins-base` und `gstreamer1.0-plugins-good`
(mp3: `gstreamer1.0-plugins-good` enthält `mpg123`), Audio-Ausgabe über
PipeWire/PulseAudio (`gstreamer1.0-pulseaudio` bzw. `gstreamer1.0-pipewire`).

## Startargumente

* `--fullscreen`: startet direkt im Vollbild (Kiosk am Board). F11 und Esc
  funktionieren wie sonst.

## Wo die Daten liegen

* Datenbank, Einstellungen, Caller-Sounds:
  `~/.local/share/de.dartlab.dartlab/` (`dartlab.sqlite`,
  `shared_preferences.json`). Unter Linux bewusst nicht im Dokumente-Ordner,
  weil es den auf einem frisch eingerichteten Pi nicht immer gibt (die App
  startete dann nicht).
* Autodarts-Mitschnitte (Logs): `~/Documents/DartLab/logs`, nur wenn es den
  Dokumente-Ordner gibt.

## Was unter Linux geht und was nicht

| Funktion | Stand |
| --- | --- |
| Start, Datenbank, Einstellungen | auf x64 (Ubuntu 24.04, ohne Grafikkarte) gestartet und geprüft |
| Heimnetz-Hub (Port 3190) | startet, antwortet (auf x64 geprüft) |
| Autodarts-Import-Empfänger (Port 3191) | startet, antwortet (auf x64 geprüft) |
| Autodarts lokal (Port 3180) | wie auf Windows über `http://<host>:3180`, auf Linux nicht geprüft |
| Caller-Sounddateien | über GStreamer (audioplayers), nicht hörbar geprüft |
| Caller-Stimme (Text-to-Speech) | **fehlt**: `flutter_tts` kann kein Linux, die Stimme schweigt still. Sounddateien gehen |
| Vollbild | `--fullscreen` und F11 über window_manager; hängt vom Fenstermanager ab, auf dem Pi nicht geprüft |
| In-App-Update | Linux bekommt keinen Download-Knopf, Updates soll das Skript übernehmen |
| arm64 / Raspberry Pi | nur im CI gebaut, auf echter Pi-Hardware nicht getestet |
