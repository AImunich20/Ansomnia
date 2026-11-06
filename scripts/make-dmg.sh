#!/bin/bash
# Build Ansomnia.app with scripts/build-app.sh and package it as a DMG.
# .github/workflows/release.yml runs this on every push to main whose
# version (CFBundleShortVersionString in Resources/Info.plist) has no
# release yet; it works the same on any Mac with Xcode.
#
# Usage: scripts/make-dmg.sh --output DIR
#   Writes DIR/Ansomnia-<version>.dmg, DIR/Ansomnia.dmg (the same bytes
#   under a fixed name, for the README's download link) and DIR/SHA256SUMS.
#
# The DMG holds Ansomnia.app, install.sh, uninstall.sh and
# "Install Ansomnia.command", which runs install.sh on the app beside it.
# The in-app updater (UpdateInstaller.swift) mounts the DMG and runs the
# same install.sh.
set -euo pipefail

HDIUTIL=/usr/bin/hdiutil
PLUTIL=/usr/bin/plutil
SHASUM=/usr/bin/shasum
DITTO=/usr/bin/ditto
CP=/bin/cp
RM=/bin/rm
MKDIR=/bin/mkdir
CHMOD=/bin/chmod
MKTEMP=/usr/bin/mktemp

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() { echo "usage: $0 --output DIR" >&2; }
OUTPUT=""
while (( $# )); do
  case "$1" in
    --output) [[ $# -ge 2 ]] || { usage; exit 2; }; OUTPUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -n "$OUTPUT" ]] || { usage; exit 2; }
"$MKDIR" -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"

VERSION="$("$PLUTIL" -extract CFBundleShortVersionString raw -o - "$ROOT/Resources/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Resources/Info.plist has no major.minor.patch version ('$VERSION')" >&2; exit 1; }

STAGE="$("$MKTEMP" -d "${TMPDIR:-/tmp}/ansomnia-dmg.XXXXXX")"
trap '"$RM" -rf "$STAGE"' EXIT
VOLUME="$STAGE/Ansomnia"
"$MKDIR" -p "$VOLUME"
"$CHMOD" 755 "$VOLUME"

"$ROOT/scripts/build-app.sh" --output "$STAGE/build"
"$DITTO" "$STAGE/build/Ansomnia.app" "$VOLUME/Ansomnia.app"
"$CP" "$ROOT/scripts/install.sh" "$ROOT/scripts/uninstall.sh" "$VOLUME/"
"$CHMOD" 755 "$VOLUME/install.sh" "$VOLUME/uninstall.sh"
cat > "$VOLUME/Install Ansomnia.command" <<'COMMAND'
#!/bin/bash
# Installs the Ansomnia.app beside this file into ~/Applications, with its
# recovery agent and sudoers rule (install.sh asks for your password once).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
/bin/bash "$SCRIPT_DIR/install.sh" --allow-unverified-origin --app "$SCRIPT_DIR/Ansomnia.app"
/usr/bin/open "$HOME/Applications/Ansomnia.app"
echo
echo "Ansomnia is installed. You can close this window and eject the disk image."
COMMAND
"$CHMOD" 755 "$VOLUME/Install Ansomnia.command"

DMG="$OUTPUT/Ansomnia-$VERSION.dmg"
"$RM" -f "$DMG" "$OUTPUT/Ansomnia.dmg" "$OUTPUT/SHA256SUMS"
"$HDIUTIL" create -volname "Ansomnia" -srcfolder "$VOLUME" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
"$CP" "$DMG" "$OUTPUT/Ansomnia.dmg"
(cd "$OUTPUT" && "$SHASUM" -a 256 "Ansomnia-$VERSION.dmg" "Ansomnia.dmg" > SHA256SUMS)
cat "$OUTPUT/SHA256SUMS"
echo "$DMG"
