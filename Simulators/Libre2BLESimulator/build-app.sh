#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
CONFIGURATION="${CONFIGURATION:-release}"
APP="$ROOT/.build/Libre 2 BLE Simulator.app"
VISIBLE_APP="$ROOT/../Apps/Libre 2 BLE Simulator.app"
SCRATCH="$ROOT/.build/swiftpm-app"

cd "$ROOT"
swift build --scratch-path "$SCRATCH" -c "$CONFIGURATION" --product Libre2BLESimulator

BIN_DIR="$(swift build --scratch-path "$SCRATCH" -c "$CONFIGURATION" --show-bin-path)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Libre2BLESimulator" "$APP/Contents/MacOS/Libre2BLESimulator"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Produces a locally signed bundle without requiring a paid Apple team.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "${VISIBLE_APP:h}"
rm -rf "$VISIBLE_APP"
ditto "$APP" "$VISIBLE_APP"
codesign --verify --deep --strict --verbose=2 "$VISIBLE_APP"

echo "$VISIBLE_APP"
