#!/usr/bin/env bash
#
# Build and run the Trio unit tests, mirroring the CI workflow (.github unit_tests.yml).
#
# Usage:
#   scripts/run_unit_tests.sh                                  # run every test
#   scripts/run_unit_tests.sh PumpHistoryNativeConversionTests # run a single suite/class
#
# The optional first argument is a test class/@Suite name in TrioTests.
#
# See installed runtimes with:  xcrun simctl list runtimes | grep iOS
set -euo pipefail

# Run from the repo root regardless of the caller's working directory.
cd "$(dirname "$0")/.."

DEST='platform=iOS Simulator,name=iPhone 17'
ONLY="${1:+-only-testing:TrioTests/$1}"

xcodebuild test \
  -workspace Trio.xcworkspace \
  -scheme "Trio Tests" \
  -destination "$DEST" \
  $ONLY \
  2>&1 | tee xcodebuild.log
