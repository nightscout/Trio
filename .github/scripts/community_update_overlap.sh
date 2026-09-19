#!/usr/bin/env bash

set -euo pipefail

: "${UPSTREAM_REPO:?UPSTREAM_REPO is required}"
: "${UPSTREAM_BRANCH:?UPSTREAM_BRANCH is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY is required}"

git remote add upstream "https://github.com/${UPSTREAM_REPO}.git" 2>/dev/null || true
git fetch --no-tags upstream "${UPSTREAM_BRANCH}:refs/remotes/upstream/${UPSTREAM_BRANCH}"

local_sha="$(git rev-parse HEAD)"
upstream_ref="refs/remotes/upstream/${UPSTREAM_BRANCH}"
upstream_sha="$(git rev-parse "${upstream_ref}")"

echo "local_sha=${local_sha}" >> "${GITHUB_OUTPUT}"
echo "upstream_sha=${upstream_sha}" >> "${GITHUB_OUTPUT}"

if git merge-base --is-ancestor "${upstream_sha}" "${local_sha}"; then
  echo "has_update=false" >> "${GITHUB_OUTPUT}"
  echo "Your fork already includes upstream ${upstream_sha}." >> "${GITHUB_STEP_SUMMARY}"
  exit 0
fi

echo "has_update=true" >> "${GITHUB_OUTPUT}"

merge_base="$(git merge-base "${local_sha}" "${upstream_ref}")"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

git diff --name-only "${merge_base}..${local_sha}" | sort -u > "${work_dir}/local-files"
git diff --name-only "${merge_base}..${upstream_ref}" | sort -u > "${work_dir}/upstream-files"
comm -12 "${work_dir}/local-files" "${work_dir}/upstream-files" > "${work_dir}/overlap-files"

git log --oneline --no-merges "${local_sha}..${upstream_ref}" | head -30 > "${work_dir}/commits" || true
git cherry "${upstream_ref}" "${local_sha}" "${merge_base}" \
  | awk '$1 == "-" { print $2 }' \
  | while read -r commit; do
      git show -s --format='%h %s' "${commit}"
    done > "${work_dir}/equivalent-commits"

medtrum_status="Niet van toepassing: de Medtrum-pin veranderde niet."
medtrum_base_sha="$(git rev-parse "${merge_base}:MedtrumKit" 2>/dev/null || true)"
medtrum_upstream_sha="$(git rev-parse "${upstream_ref}:MedtrumKit" 2>/dev/null || true)"
if [[ -f patches/medtrum-fill-indicator.patch && -n "${medtrum_upstream_sha}" && "${medtrum_base_sha}" != "${medtrum_upstream_sha}" ]]; then
  git submodule update --init --depth 1 MedtrumKit
  git -C MedtrumKit fetch --no-tags --depth 1 origin "${medtrum_base_sha}"
  git -C MedtrumKit fetch --no-tags --depth 1 origin "${medtrum_upstream_sha}"

  git -C MedtrumKit diff --name-only "${medtrum_base_sha}..${medtrum_upstream_sha}" | sort -u > "${work_dir}/medtrum-upstream-files"
  awk '/^\+\+\+ b\// { sub(/^\+\+\+ b\//, ""); print }' patches/medtrum-fill-indicator.patch \
    | sort -u > "${work_dir}/medtrum-patch-files"
  comm -12 "${work_dir}/medtrum-patch-files" "${work_dir}/medtrum-upstream-files" > "${work_dir}/medtrum-overlap-files"

  git -C MedtrumKit checkout --detach "${medtrum_upstream_sha}"

  if git apply --reverse --check patches/medtrum-fill-indicator.patch --directory=MedtrumKit 2>/dev/null; then
    medtrum_status="VOLLEDIG OVERGENOMEN DOOR UPSTREAM: verwijder de lokale patch en de apply-stap."
  elif [[ -s "${work_dir}/medtrum-overlap-files" ]]; then
    medtrum_overlap="$(awk 'BEGIN { separator = "" } { printf "%s%s", separator, $0; separator = ", " } END { print "" }' "${work_dir}/medtrum-overlap-files")"
    medtrum_status="MOGELIJKE FUNCTIONELE OVERLAP in ${medtrum_overlap}: vergelijk de upstream-versie inhoudelijk en vervang overlappende lokale delen door upstream."
  elif git apply --check patches/medtrum-fill-indicator.patch --directory=MedtrumKit 2>/dev/null; then
    medtrum_status="GEEN EXACTE OVERNAME: de lokale fill-indicatorpatch is nog toepasbaar en blijft voorlopig nodig."
  else
    medtrum_status="MOGELIJKE GEDEELTELIJKE OVERLAP: de patch past niet schoon; vergelijk het fill-scherm, de 70U-grens, fill guide, batterijweergave en vertalingen semantisch."
  fi
fi

libre_status="Niet van toepassing: de LibreTransmitter-pin veranderde niet."
libre_base_sha="$(git rev-parse "${merge_base}:LibreTransmitter" 2>/dev/null || true)"
libre_upstream_sha="$(git rev-parse "${upstream_ref}:LibreTransmitter" 2>/dev/null || true)"
if [[ -n "${libre_upstream_sha}" && "${libre_base_sha}" != "${libre_upstream_sha}" ]]; then
  libre_status="REVIEW NODIG: vergelijk de nieuwe officiële LibreTransmitter-pin met de lokale warmup/NFC-aanpassingen. Neem officiële implementaties over en behoud alleen aantoonbaar ontbrekende delta."
fi

write_multiline_output() {
  local name="$1"
  local file="$2"
  {
    echo "${name}<<EOF"
    cat "${file}"
    echo "EOF"
  } >> "${GITHUB_OUTPUT}"
}

write_multiline_output commits "${work_dir}/commits"
write_multiline_output local_custom_files "${work_dir}/local-files"
write_multiline_output overlap_files "${work_dir}/overlap-files"
write_multiline_output equivalent_commits "${work_dir}/equivalent-commits"

{
  echo "medtrum_status<<EOF"
  echo "${medtrum_status}"
  echo "EOF"
  echo "libre_status<<EOF"
  echo "${libre_status}"
  echo "EOF"
} >> "${GITHUB_OUTPUT}"

{
  echo "## Community update available"
  echo
  echo "- Local fork: \`${local_sha}\`"
  echo "- Upstream: \`${upstream_sha}\`"
  echo "- Gemeenschappelijke basis: \`${merge_base}\`"
  echo
  echo "### Overlapcontrole"
  if [[ -s "${work_dir}/overlap-files" ]]; then
    echo "Upstream wijzigt ook bestanden waarin de fork eigen aanpassingen heeft."
    echo
    sed 's/^/- `/' "${work_dir}/overlap-files" | sed 's/$/`/'
  else
    echo "Geen overlap op bestandsniveau gevonden."
  fi
  echo
  echo "- Medtrum: ${medtrum_status}"
  echo "- Libre: ${libre_status}"
  echo
  echo "Bij overlap geldt: gebruik de officiële upstream-implementatie, verwijder de dubbele lokale implementatie en behoud alleen functionaliteit die upstream aantoonbaar nog mist."
} >> "${GITHUB_STEP_SUMMARY}"
