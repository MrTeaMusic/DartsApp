#!/bin/bash
# DartLab auf iPhone/iPad aktualisieren, ohne die eigene App-Kennung zu
# verlieren (sonst startet die App ohne Daten und Einstellungen).
#
#   tools/ios/update.sh "Bens iPhone"
#
# Ablauf:
#  1. Eigene Kennung sichern: steht sie noch als lokale Änderung im
#     Xcode-Projekt (alte Anleitung), wandert sie in
#     ios/Flutter/Signing.local.xcconfig (nicht in git).
#  2. Lokale Änderungen, die ein git pull blockieren würden, beiseitelegen:
#     pubspec.lock und das Xcode-Projekt werden zurückgesetzt (beides
#     erzeugt Flutter/Xcode neu), alles andere kommt in git stash und ist
#     dort wiederherstellbar.
#  3. git pull, flutter pub get, flutter run --release auf dem Gerät.

set -eu
cd "$(dirname "$0")/../.."

device="${1:-}"
LOCAL=ios/Flutter/Signing.local.xcconfig
PBX=ios/Runner.xcodeproj/project.pbxproj

if [ -z "$device" ]; then
  echo "Gerät angeben, z. B.: tools/ios/update.sh \"Bens iPhone\""
  echo "Verbundene Geräte:"
  flutter devices || true
  exit 1
fi

# 1. Kennung sichern, bevor irgendetwas zurückgesetzt wird.
if [ ! -f "$LOCAL" ]; then
  echo "Noch keine eigene Kennung eingetragen."
  tools/ios/signing.sh --geraet "$device"
fi
if [ ! -f "$LOCAL" ]; then
  echo "Ohne eigene Kennung breche ich ab, damit keine zweite, leere App entsteht." >&2
  exit 1
fi
echo "App-Kennung: $(sed -n 's/^PRODUCT_BUNDLE_IDENTIFIER *= *//p' "$LOCAL" | tail -1)"

# 2. Was einen git pull blockiert.
git checkout -- pubspec.lock "$PBX" 2>/dev/null || true
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Weitere lokale Änderungen gefunden, lege sie in git stash ab:"
  git status --short --untracked-files=no
  git stash push -m "DartLab-Update $(date '+%Y-%m-%d %H:%M')"
fi

# 3. Aktualisieren und installieren.
git pull --ff-only
flutter pub get
flutter run -d "$device" --release
