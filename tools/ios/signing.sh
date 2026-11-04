#!/bin/bash
# Legt die eigene App-Kennung (Bundle Identifier) und das Team für den
# iPhone/iPad-Build fest, in ios/Flutter/Signing.local.xcconfig.
#
# Die Datei ist von git ausgenommen. Früher stand die Kennung als lokale
# Änderung im Xcode-Projekt; ein git pull mit Konflikt, ein git checkout
# oder ein neuer Klon hat sie still auf de.dartlab.dartlab zurückgesetzt.
# iOS hält eine App mit anderer Kennung für eine andere App: sie startet
# ohne Daten und ohne Einstellungen (die alten liegen weiter in der alten
# App auf dem Gerät).
#
#   tools/ios/signing.sh                       zeigt, was gefunden wurde, und fragt
#   tools/ios/signing.sh de.ben.dartlab        Kennung setzen (Team sucht Flutter selbst)
#   tools/ios/signing.sh de.ben.dartlab ABCDE12345   Kennung und Team setzen
#   tools/ios/signing.sh --geraet "Bens iPhone"      zeigt zusätzlich die DartLab-Apps auf dem Gerät
#
# Funktioniert mit der Standard-Bash von macOS (3.2).

set -u
cd "$(dirname "$0")/../.." || exit 1

LOCAL=ios/Flutter/Signing.local.xcconfig
PBX=ios/Runner.xcodeproj/project.pbxproj
DEFAULT_ID=de.dartlab.dartlab

device=""
if [ "${1:-}" = "--geraet" ]; then
  device="${2:-}"
  shift 2 || shift $#
fi

current_local_id() {
  [ -f "$LOCAL" ] && sed -n 's/^PRODUCT_BUNDLE_IDENTIFIER *= *\([^ ;]*\).*/\1/p' "$LOCAL" | tail -1
}

# Kennungen, die irgendwo noch auftauchen: im Arbeitsstand des Projekts (alte
# Anleitung), in git stash (falls ein git pull die Änderung weggeräumt hat).
found_ids() {
  {
    [ -f "$PBX" ] && sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = "\{0,1\}\([^";]*\)"\{0,1\};/\1/p' "$PBX"
    git stash list --format=%gd 2>/dev/null | while read -r s; do
      git diff "$s^1" "$s" -- "$PBX" 2>/dev/null | sed -n 's/^+.*PRODUCT_BUNDLE_IDENTIFIER = "\{0,1\}\([^";]*\)"\{0,1\};/\1/p'
    done
  } | grep -v -e '^\$(' -e 'RunnerTests$' -e "^${DEFAULT_ID}\$" | sort -u
}

found_team() {
  [ -f "$PBX" ] && sed -n 's/.*DEVELOPMENT_TEAM = "\{0,1\}\([A-Z0-9]*\)"\{0,1\};/\1/p' "$PBX" | head -1
}

write_local() {
  local id="$1" team="${2:-}"
  {
    echo "// Eigene App-Kennung für iPhone/iPad (tools/ios/signing.sh)."
    echo "// Nicht in git. Nicht ändern, solange die App mit ihren Daten auf dem Gerät bleiben soll."
    echo "PRODUCT_BUNDLE_IDENTIFIER = $id"
    if [ -n "$team" ]; then echo "DEVELOPMENT_TEAM = $team"; fi
  } > "$LOCAL"
  echo "Gespeichert in $LOCAL: Kennung $id${team:+, Team $team}"
}

valid_id() {
  echo "$1" | grep -E -q '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$'
}

if [ $# -ge 1 ]; then
  if ! valid_id "$1"; then
    echo "Das ist keine gültige Kennung: $1 (Beispiel: de.ben.dartlab)" >&2
    exit 1
  fi
  write_local "$1" "${2:-$(found_team)}"
  exit 0
fi

echo "Eigene App-Kennung für DartLab auf iPhone/iPad"
echo
now="$(current_local_id)"
if [ -n "$now" ]; then
  echo "Eingetragen ist schon: $now"
fi
ids="$(found_ids)"
if [ -n "$ids" ]; then
  echo "Gefunden (Xcode-Projekt oder git stash):"
  echo "$ids" | sed 's/^/  /'
fi
if [ -n "$device" ] && command -v xcrun >/dev/null 2>&1; then
  echo "DartLab-Apps auf \"$device\":"
  xcrun devicectl device info apps --device "$device" 2>/dev/null | grep -i -E 'dartlab|runner' | sed 's/^/  /' \
    || echo "  (keine gefunden oder Gerät nicht verbunden)"
fi
echo
echo "Wichtig: Nimm die Kennung, mit der die App bisher installiert war. Eine neue"
echo "Kennung ergibt auf dem Gerät eine zweite, leere App."
suggest="${now:-$(echo "$ids" | head -1)}"
printf "Kennung%s: " "${suggest:+ [$suggest]}"
read -r answer
answer="${answer:-$suggest}"
if [ -z "$answer" ] || ! valid_id "$answer"; then
  echo "Keine gültige Kennung, nichts geändert." >&2
  exit 1
fi
write_local "$answer" "$(found_team)"
