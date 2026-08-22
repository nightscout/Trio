#!/bin/sh
#  capture-release-notes.sh
#  Trio
#
#  Bundles GitHub release notes for the version line being built, so the release notes
#  list still works when the device is offline or GitHub is unreachable.
#
#  Every stable release back to the last major or minor bump is kept: building 0.8.4
#  bundles 0.8.0 through 0.8.4. At runtime Trio still prefers a live fetch, because
#  release notes are sometimes edited after publishing. This is only the fallback.
#
#  This never fails the build. No network, no releases, no GitHub - the app falls back
#  to a live fetch, and shows nothing if that fails too.

set -u

RESOURCE_DIR="${BUILT_PRODUCTS_DIR:-}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}"
OUTPUT="${RESOURCE_DIR}/BundledReleaseNotes.json"
REPO="nightscout/Trio"

warn() {
  echo "warning: capture-release-notes: ${*}" >&2
}

# Always start from a clean slate so a stale file from a previous version cannot
# survive into this build.
rm -f "${OUTPUT}"

if [ ! -d "${RESOURCE_DIR}" ]; then
  warn "resource directory not found, skipping"
  exit 0
fi

# APP_VERSION comes from Config.xcconfig. Fall back to the built Info.plist value.
version="${APP_VERSION:-}"
if [ -z "${version}" ]; then
  version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "${BUILT_PRODUCTS_DIR:-}/${INFOPLIST_PATH:-}" 2>/dev/null || echo "")
fi

# PlistBuddy reports failures on stdout rather than stderr, so an unreadable plist
# would otherwise be treated as the version string. Insist on a dotted numeric
# version before it is used.
if ! echo "${version}" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
  warn "could not determine a valid app version, skipping"
  exit 0
fi

major_minor=$(echo "${version}" | awk -F. '{print $1"."$2}')
echo "capture-release-notes: collecting ${REPO} releases in the ${major_minor}.x line up to ${version}"

# GitHub allows 60 unauthenticated API calls per hour per IP, and CI runners share
# egress addresses, so an unauthenticated build can be refused because of traffic it
# has nothing to do with. GH_PAT is already in the workflow environment.
token="${GH_PAT:-${GITHUB_TOKEN:-}}"
if [ -n "${token}" ]; then
  set -- -H "Authorization: Bearer ${token}"
else
  set --
fi

fetch_releases() {
  curl --fail --silent --show-error --location \
    --connect-timeout 5 --max-time 30 \
    -H "Accept: application/vnd.github+json" \
    "$@" \
    "https://api.github.com/repos/${REPO}/releases?per_page=100" \
    -o "${OUTPUT}.raw" 2>/dev/null
}

if ! fetch_releases "$@"; then
  # An expired or malformed token would otherwise do worse than no token at all, so
  # fall back to an unauthenticated call before giving up.
  if [ "$#" -gt 0 ] && fetch_releases; then
    warn "token was rejected; fetched release notes unauthenticated"
  else
    warn "could not reach GitHub; building without bundled notes"
    rm -f "${OUTPUT}.raw"
    exit 0
  fi
fi

# Keep only the fields the app reads, so the bundle does not carry whole release objects.
if ! /usr/bin/python3 - "${OUTPUT}.raw" "${OUTPUT}" "${version}" <<'PY'
import json, sys

src, dst, version = sys.argv[1], sys.argv[2], sys.argv[3]


def parts(tag):
    return [int(piece) for piece in tag.lstrip("v").split(".")]


try:
    with open(src, encoding="utf-8") as handle:
        releases = json.load(handle)

    current = parts(version)
    line = current[:2]
    kept = []

    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        tag = release.get("tag_name") or ""
        try:
            numbers = parts(tag)
        except ValueError:
            continue
        if numbers[:2] != line or numbers > current:
            continue
        kept.append({
            "tagName": tag,
            "name": release.get("name") or tag,
            "body": release.get("body") or "",
            "htmlURL": release["html_url"],
            "publishedAt": release.get("published_at") or "",
        })

    if not kept:
        raise SystemExit(2)

    kept.sort(key=lambda item: parts(item["tagName"]), reverse=True)
    with open(dst, "w", encoding="utf-8") as handle:
        json.dump(kept, handle, ensure_ascii=False)
    print("kept " + ", ".join(item["tagName"] for item in kept), file=sys.stderr)
except SystemExit:
    raise
except Exception as error:  # noqa: BLE001 - build step must never hard-fail
    print(f"could not parse release payload: {error}", file=sys.stderr)
    raise SystemExit(1)
PY
then
  warn "no published releases found in the ${major_minor}.x line; building without bundled notes"
  rm -f "${OUTPUT}" "${OUTPUT}.raw"
  exit 0
fi

rm -f "${OUTPUT}.raw"
echo "capture-release-notes: bundled release notes for the ${major_minor}.x line"
