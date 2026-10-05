#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
APP="$ROOT/.build/Medtrum Pump Simulator.app"

cd "$ROOT"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BIN_DIR/MedtrumPumpBLESimulator"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXECUTABLE" "$APP/Contents/MacOS/MedtrumPumpBLESimulator"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signing is sufficient for local supervised training. Set SIGN_IDENTITY
# to an Apple Development identity for a persistent team signature.
codesign --force --deep --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

print "Built and signed: $APP"
