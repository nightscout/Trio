#!/usr/bin/env bash
# Update all three TestFlight tracks when nightscout/Trio has new commits.
#
#   main              vanilla Trio Main — fast-forward to upstream/main;
#                     if an overlay commit blocks ff, merge upstream/main
#                     (never rebase/force this branch).
#   dev               vanilla Trio Dev — same policy against upstream/dev.
#   upgrade/trio-1.0  custom clinic app — rebase custom commits onto
#                     upstream/main. Force-with-lease only after a clean
#                     rebase that still has clinic/overlay files.
#
# Overlay files on vanilla branches (flavor map, apply script, Sunday
# workflow, checklist, flavor bits in Build Trio / Add Identifiers) are
# restored if a fast-forward would drop them.

set -euo pipefail

: "${UPSTREAM_REPO:?UPSTREAM_REPO is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY is required}"

CUSTOM_BRANCH="upgrade/trio-1.0"
MAIN_UPDATED=false
DEV_UPDATED=false
CUSTOM_UPDATED=false
CUSTOM_FAILED=false
VANILLA_FAILED=false
CUSTOM_CONFLICT_FILES=""
CUSTOM_BEFORE_SHA=""
UPSTREAM_MAIN_SHA=""
UPSTREAM_DEV_SHA=""

OVERLAY_FILES=(
  ".github/app-flavors.yml"
  ".github/scripts/apply_app_flavor.sh"
  ".github/scripts/sunday_sync_all_tracks.sh"
  ".github/workflows/sunday_sync_all_tracks.yml"
  ".github/workflows/build_trio.yml"
  ".github/workflows/add_identifiers.yml"
  "DeveloperDocs/three_trio_apps_apple_checklist.md"
)

CUSTOM_MUST_KEEP=(
  ".github/app-flavors.yml"
  ".github/scripts/apply_app_flavor.sh"
  ".github/scripts/sunday_sync_all_tracks.sh"
  ".github/workflows/sunday_sync_all_tracks.yml"
  "Trio/Sources/Services/Network/OpenSourceClinic/OpenSourceClinicAPI.swift"
  "Trio/Sources/Modules/OpenSourceClinicConfig/OpenSourceClinicConfigProvider.swift"
)

write_outputs() {
  {
    echo "MAIN_UPDATED=${MAIN_UPDATED}"
    echo "DEV_UPDATED=${DEV_UPDATED}"
    echo "CUSTOM_UPDATED=${CUSTOM_UPDATED}"
    echo "CUSTOM_FAILED=${CUSTOM_FAILED}"
    echo "CUSTOM_CONFLICT_FILES<<EOF"
    printf '%s\n' "${CUSTOM_CONFLICT_FILES}"
    echo "EOF"
    echo "CUSTOM_BEFORE_SHA=${CUSTOM_BEFORE_SHA}"
    echo "UPSTREAM_MAIN_SHA=${UPSTREAM_MAIN_SHA}"
    echo "UPSTREAM_DEV_SHA=${UPSTREAM_DEV_SHA}"
  } >> "${GITHUB_OUTPUT}"
}

trap write_outputs EXIT

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git remote add upstream "https://github.com/${UPSTREAM_REPO}.git" 2>/dev/null || true
git fetch --no-tags origin main dev "${CUSTOM_BRANCH}"
git fetch --no-tags upstream main dev

UPSTREAM_MAIN_SHA="$(git rev-parse refs/remotes/upstream/main)"
UPSTREAM_DEV_SHA="$(git rev-parse refs/remotes/upstream/dev)"

snapshot_files() {
  local dest="$1"
  shift
  local file
  mkdir -p "${dest}"
  for file in "$@"; do
    if git cat-file -e "HEAD:${file}" 2>/dev/null; then
      mkdir -p "${dest}/$(dirname "${file}")"
      git show "HEAD:${file}" > "${dest}/${file}"
    fi
  done
}

overlay_needs_restore() {
  local file="$1"
  local backup="$2"
  [[ -f "${backup}/${file}" ]] || return 1
  if ! git cat-file -e "HEAD:${file}" 2>/dev/null; then
    return 0
  fi
  case "${file}" in
    .github/workflows/build_trio.yml|.github/workflows/add_identifiers.yml)
      ! grep -q 'apply_app_flavor.sh' "${file}"
      ;;
    *)
      return 1
      ;;
  esac
}

restore_overlay_if_needed() {
  local backup="$1"
  local restored=false
  local file
  for file in "${OVERLAY_FILES[@]}"; do
    if overlay_needs_restore "${file}" "${backup}"; then
      echo "Restoring overlay file ${file}"
      mkdir -p "$(dirname "${file}")"
      cp "${backup}/${file}" "${file}"
      git add -- "${file}"
      restored=true
    fi
  done
  if [[ "${restored}" == true ]]; then
    git commit -m "Keep clinic flavor overlay after Nightscout sync"
  fi
}

resolve_vanilla_conflicts() {
  local backup="$1"
  local file
  local unresolved
  for file in "${OVERLAY_FILES[@]}"; do
    if [[ -f "${backup}/${file}" ]] && git diff --name-only --diff-filter=U | grep -Fxq "${file}"; then
      echo "Keeping overlay version of conflicted ${file}"
      mkdir -p "$(dirname "${file}")"
      cp "${backup}/${file}" "${file}"
      git add -- "${file}"
    fi
  done
  unresolved="$(git diff --name-only --diff-filter=U || true)"
  if [[ -n "${unresolved}" ]]; then
    echo "::error::Merge conflicts on vanilla branch (not auto-resolved):"
    echo "${unresolved}"
    git merge --abort || true
    return 1
  fi
  git commit --no-edit
}

mark_vanilla_updated() {
  case "$1" in
    main) MAIN_UPDATED=true ;;
    dev) DEV_UPDATED=true ;;
    *)
      echo "::error::Unknown vanilla branch $1"
      return 1
      ;;
  esac
}

sync_vanilla() {
  local branch="$1"
  local upstream_ref="$2"
  local local_sha upstream_sha backup

  local_sha="$(git rev-parse "refs/remotes/origin/${branch}")"
  upstream_sha="$(git rev-parse "${upstream_ref}")"

  echo "## ${branch}" >> "${GITHUB_STEP_SUMMARY}"
  echo >> "${GITHUB_STEP_SUMMARY}"
  echo "- Local: \`${local_sha}\`" >> "${GITHUB_STEP_SUMMARY}"
  echo "- Upstream: \`${upstream_sha}\`" >> "${GITHUB_STEP_SUMMARY}"

  if git merge-base --is-ancestor "${upstream_sha}" "${local_sha}"; then
    echo "- Already contains upstream; no update." >> "${GITHUB_STEP_SUMMARY}"
    echo >> "${GITHUB_STEP_SUMMARY}"
    echo "${branch} already contains ${upstream_ref}"
    return 0
  fi

  git branch -f "sync/${branch}" "refs/remotes/origin/${branch}"
  git switch "sync/${branch}"

  backup="$(mktemp -d)"
  snapshot_files "${backup}" "${OVERLAY_FILES[@]}"

  if git merge --ff-only "${upstream_ref}"; then
    echo "Fast-forwarded ${branch} to ${upstream_sha}"
    echo "- Fast-forwarded to \`${upstream_sha}\`." >> "${GITHUB_STEP_SUMMARY}"
  else
    echo "Fast-forward blocked on ${branch} (overlay commit); merging ${upstream_ref}"
    if ! git merge --no-ff --no-edit "${upstream_ref}"; then
      if ! resolve_vanilla_conflicts "${backup}"; then
        echo "- Merge failed; conflicts left unresolved." >> "${GITHUB_STEP_SUMMARY}"
        echo >> "${GITHUB_STEP_SUMMARY}"
        return 1
      fi
    fi
    echo "- Merged \`${upstream_sha}\` to keep flavor overlay." >> "${GITHUB_STEP_SUMMARY}"
  fi

  restore_overlay_if_needed "${backup}"
  git push origin "HEAD:refs/heads/${branch}"
  git fetch --no-tags origin "${branch}"
  mark_vanilla_updated "${branch}"
  echo "- Pushed \`${branch}\` (no force)." >> "${GITHUB_STEP_SUMMARY}"
  echo >> "${GITHUB_STEP_SUMMARY}"
  return 0
}

custom_files_present() {
  local file
  for file in "${CUSTOM_MUST_KEEP[@]}"; do
    if ! git cat-file -e "HEAD:${file}" 2>/dev/null; then
      echo "::error::Custom rebase dropped required file: ${file}"
      return 1
    fi
  done
  return 0
}

sync_custom() {
  local local_sha upstream_sha

  local_sha="$(git rev-parse "refs/remotes/origin/${CUSTOM_BRANCH}")"
  upstream_sha="$(git rev-parse refs/remotes/upstream/main)"
  CUSTOM_BEFORE_SHA="${local_sha}"

  echo "## ${CUSTOM_BRANCH}" >> "${GITHUB_STEP_SUMMARY}"
  echo >> "${GITHUB_STEP_SUMMARY}"
  echo "- Local: \`${local_sha}\`" >> "${GITHUB_STEP_SUMMARY}"
  echo "- Upstream main: \`${upstream_sha}\`" >> "${GITHUB_STEP_SUMMARY}"

  if git merge-base --is-ancestor "${upstream_sha}" "${local_sha}"; then
    echo "- Already contains nightscout/Trio main; no rebase." >> "${GITHUB_STEP_SUMMARY}"
    echo >> "${GITHUB_STEP_SUMMARY}"
    echo "${CUSTOM_BRANCH} already contains upstream/main"
    return 0
  fi

  git branch -f sync/custom "refs/remotes/origin/${CUSTOM_BRANCH}"
  git switch sync/custom
  # Submodule pointer commits (LibreTransmitter, etc.) conflict as
  # "not checked out" unless the submodule is present before rebase.
  git submodule update --init --recursive

  if git rebase refs/remotes/upstream/main; then
    if ! custom_files_present; then
      echo "::error::Rebase succeeded but clinic/overlay files are missing. Not pushing."
      git reset --hard "${local_sha}"
      CUSTOM_FAILED=true
      echo "- Rebase dropped required clinic/overlay files. Branch was not force-pushed." >> "${GITHUB_STEP_SUMMARY}"
      echo >> "${GITHUB_STEP_SUMMARY}"
      return 1
    fi
    git push --force-with-lease="refs/heads/${CUSTOM_BRANCH}:${local_sha}" \
      origin "HEAD:refs/heads/${CUSTOM_BRANCH}"
    git fetch --no-tags origin "${CUSTOM_BRANCH}"
    CUSTOM_UPDATED=true
    echo "- Rebased custom commits onto \`${upstream_sha}\` and force-with-lease pushed." >> "${GITHUB_STEP_SUMMARY}"
    echo >> "${GITHUB_STEP_SUMMARY}"
    return 0
  fi

  CUSTOM_CONFLICT_FILES="$(git diff --name-only --diff-filter=U || true)"
  git rebase --abort || true
  CUSTOM_FAILED=true
  echo "::error::Rebase of ${CUSTOM_BRANCH} onto nightscout/Trio main conflicted. Not force-pushing."
  echo "- Rebase conflicted. Branch was left unchanged (no force-push)." >> "${GITHUB_STEP_SUMMARY}"
  if [[ -n "${CUSTOM_CONFLICT_FILES}" ]]; then
    echo "- Conflicted files:" >> "${GITHUB_STEP_SUMMARY}"
    echo >> "${GITHUB_STEP_SUMMARY}"
    echo '```' >> "${GITHUB_STEP_SUMMARY}"
    printf '%s\n' "${CUSTOM_CONFLICT_FILES}" >> "${GITHUB_STEP_SUMMARY}"
    echo '```' >> "${GITHUB_STEP_SUMMARY}"
  fi
  echo >> "${GITHUB_STEP_SUMMARY}"
  return 1
}

{
  echo "# Sunday Sync All Tracks"
  echo
  echo "Policy: vanilla \`main\`/\`dev\` fast-forward or merge (no force)."
  echo "Custom \`${CUSTOM_BRANCH}\` rebases onto nightscout/Trio main; force-with-lease only after a clean rebase."
  echo
} >> "${GITHUB_STEP_SUMMARY}"

if ! sync_vanilla main refs/remotes/upstream/main; then
  VANILLA_FAILED=true
fi
if ! sync_vanilla dev refs/remotes/upstream/dev; then
  VANILLA_FAILED=true
fi

custom_status=0
sync_custom || custom_status=$?

if [[ "${CUSTOM_FAILED}" == true || "${custom_status}" -ne 0 || "${VANILLA_FAILED}" == true ]]; then
  echo "::error::Sunday sync finished with failures (see job summary)."
  exit 1
fi
