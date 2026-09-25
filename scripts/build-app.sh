#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/Hunter.app"
CONTENTS="$APP/Contents"

rm -rf "$APP" "$ROOT/dist/WattHound.app"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/Hunter" "$CONTENTS/MacOS/Hunter"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

ICON="$ROOT/Resources/Hunter.icns"
HOUND_SVG="$ROOT/Sources/Hunter/Resources/BloodhoundMenuBar.svg"
if [[ ! -f "$ICON" || "$HOUND_SVG" -nt "$ICON" || "$ROOT/scripts/make-icon.swift" -nt "$ICON" ]]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  swift "$ROOT/scripts/make-icon.swift" "$WORK/icon-1024.png" "$HOUND_SVG"
  mkdir -p "$WORK/Hunter.iconset"
  for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    read -r pixels name <<< "$spec"
    sips -z "$pixels" "$pixels" "$WORK/icon-1024.png" --out "$WORK/Hunter.iconset/icon_${name}.png" >/dev/null
  done
  iconutil -c icns "$WORK/Hunter.iconset" -o "$ICON"
fi
cp "$ICON" "$CONTENTS/Resources/Hunter.icns"
cp -R "$BIN_DIR/Hunter_Hunter.bundle" "$CONTENTS/Resources/"

SIGNING_IDENTITY="${HUNTER_SIGNING_IDENTITY:-Local Self-Signed}"
if security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP" >/dev/null
else
  codesign --force --deep --sign - "$APP" >/dev/null
fi
printf 'Built %s\n' "$APP"
