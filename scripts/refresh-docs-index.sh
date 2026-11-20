#!/bin/sh
#  refresh-docs-index.sh
#  Trio
#
#  Rebuilds the Trio Docs index that the on-device docs assistant answers from, so every
#  build ships the documentation as it is on https://triodocs.org at build time rather
#  than the snapshot committed in Trio/Resources/json/docs.
#
#  The fresh index is written straight into the built app bundle, after the Resources
#  phase has copied the committed copy there. The working tree is never touched.
#
#  This never fails the build. No network, no python3, a changed site format - the
#  committed copy stays in place and the assistant uses that.
set -u

RESOURCE_DIR="${BUILT_PRODUCTS_DIR:-}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}"
OUTPUT="${RESOURCE_DIR}/json/docs/trio-docs-index.json"
GENERATOR="${SRCROOT:-.}/scripts/build-docs-index.py"

warn() {
  echo "warning: refresh-docs-index: ${*}" >&2
}

if [ ! -f "${OUTPUT}" ]; then
  warn "bundled index not found at ${OUTPUT}, skipping"
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  warn "python3 not available, keeping the committed index"
  exit 0
fi

# -I ignores the environment, -B avoids writing bytecode next to the script (read-only under the build sandbox).
if python3 -I -B "${GENERATOR}" --output "${OUTPUT}.tmp"; then
  mv -f "${OUTPUT}.tmp" "${OUTPUT}"
  echo "refresh-docs-index: bundled Trio Docs index refreshed from triodocs.org"
else
  rm -f "${OUTPUT}.tmp"
  warn "could not refresh the Trio Docs index, keeping the committed copy"
fi

exit 0
