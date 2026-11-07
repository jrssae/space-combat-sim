#!/usr/bin/env bash
# Vendors the pinned third-party Godot addons into addons/. Run once per version bump and commit the
# result together with docs/third-party.md. Only the addon directories (and their licences) are copied.
# Usage: scripts/vendor_addons.sh [name ...]; with no name, all of them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# name | git url | tag or full 40-character commit | addon dir inside the repo | licence files to keep (relative to the repo root)
# A repo with no tags is pinned by commit.
ADDONS=(
    "gut|https://github.com/bitwes/Gut|v9.7.1|addons/gut|LICENSE.md"
    "lens_effects|https://github.com/ARez2/compositor-effect-lens-effects|0ce061271f672f05fbb9aed08a61e019a875c1ad|addons/lens_effects|LICENSE"
)

for entry in "${ADDONS[@]}"; do
    IFS='|' read -r name url tag addon_dir licences <<< "${entry}"
    if (( $# > 0 )) && [[ " $* " != *" ${name} "* ]]; then
        continue
    fi
    echo "== ${name} ${tag}"
    if [[ "${tag}" =~ ^[0-9a-f]{40}$ ]]; then
        git init -q "${TMP}/${name}"
        git -C "${TMP}/${name}" fetch -q --depth 1 "${url}" "${tag}"
        git -C "${TMP}/${name}" -c advice.detachedHead=false checkout -q FETCH_HEAD
    else
        git -c advice.detachedHead=false clone -q --depth 1 --branch "${tag}" "${url}" "${TMP}/${name}"
    fi
    commit="$(git -C "${TMP}/${name}" rev-parse HEAD)"
    if [[ "${tag}" =~ ^[0-9a-f]{40}$ && "${commit}" != "${tag}" ]]; then
        echo "pinned commit ${tag} resolved to ${commit}" >&2
        exit 1
    fi
    rm -rf "${ROOT:?}/${addon_dir}"
    mkdir -p "$(dirname "${ROOT}/${addon_dir}")"
    cp -R "${TMP}/${name}/${addon_dir}" "${ROOT}/${addon_dir}"
    for lic in ${licences}; do
        if [[ -f "${TMP}/${name}/${lic}" && ! -f "${ROOT}/${addon_dir}/$(basename "${lic}")" ]]; then
            cp "${TMP}/${name}/${lic}" "${ROOT}/${addon_dir}/"
        fi
    done
    echo "${name} ${tag} ${commit}"
done
