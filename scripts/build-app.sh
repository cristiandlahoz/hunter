#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/WattHound.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/WattHound" "$CONTENTS/MacOS/WattHound"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

if [[ ! -f "$ROOT/Resources/WattHound.icns" ]]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  swift "$ROOT/scripts/make-icon.swift" "$WORK/icon-1024.png"
  mkdir -p "$WORK/WattHound.iconset"
  for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    read -r pixels name <<< "$spec"
    sips -z "$pixels" "$pixels" "$WORK/icon-1024.png" --out "$WORK/WattHound.iconset/icon_${name}.png" >/dev/null
  done
  iconutil -c icns "$WORK/WattHound.iconset" -o "$ROOT/Resources/WattHound.icns"
fi
cp "$ROOT/Resources/WattHound.icns" "$CONTENTS/Resources/WattHound.icns"
cp -R "$BIN_DIR/WattHound_WattHound.bundle" "$CONTENTS/Resources/"

codesign --force --deep --sign - "$APP" >/dev/null
printf 'Built %s\n' "$APP"
