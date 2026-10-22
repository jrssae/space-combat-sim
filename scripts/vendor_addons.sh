#!/usr/bin/env bash
# Vendors the pinned third-party Godot addons into addons/. Run once per version bump and commit the
# result together with docs/third-party.md. Only the addon directories (and their licences) are copied.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# name | git url | tag | addon dir inside the repo | licence files to keep (relative to the repo root)
ADDONS=(
    "gut|https://github.com/bitwes/Gut|v9.7.1|addons/gut|LICENSE.md"
    "gdgs|https://github.com/ReconWorldLab/godot-gaussian-splatting|v3.3.0|addons/gdgs|LICENSE"
)

for entry in "${ADDONS[@]}"; do
    IFS='|' read -r name url tag addon_dir licences <<< "${entry}"
    echo "== ${name} ${tag}"
    git -c advice.detachedHead=false clone -q --depth 1 --branch "${tag}" "${url}" "${TMP}/${name}"
    commit="$(git -C "${TMP}/${name}" rev-parse HEAD)"
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
