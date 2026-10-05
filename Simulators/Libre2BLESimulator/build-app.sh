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

# A running copy keeps the old executable mapped even after its bundle is
# replaced. Stop it before replacing the visible app.
pkill -x Libre2BLESimulator 2>/dev/null || true
mkdir -p "${VISIBLE_APP:h}"
rm -rf "$VISIBLE_APP"
ditto "$APP" "$VISIBLE_APP"
codesign --verify --deep --strict --verbose=2 "$VISIBLE_APP"

echo "$VISIBLE_APP"
