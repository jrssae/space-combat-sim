#!/usr/bin/env bash
# Opt-in: installs Godot's Linux x86_64 export templates into .tools/godot/templates/ so the game can be measured as a
# release build (editor builds are slower at GDScript). Not part of setup_godot.sh or CI. Idempotent; the 1.28 GB archive is
# downloaded to a temporary folder, verified by SHA-512, and deleted again. Only the two Linux x86_64 templates are kept.
#
# Repeat a release run. A template cannot open a project folder (no --path), so export the project once, then run the export:
#   scripts/setup_export_templates.sh
#   an export_presets.cfg with a "Linux release" preset: export_filter="all_resources", include_filter="*.json,*.ply,*.light,*.txt,*.cfg,*.obj,*.mtl",
#     custom_template/release=".tools/godot/templates/linux_release.x86_64" (absolute), binary_format/embed_pck=true
#   .tools/godot/godot --headless --path . --import && .tools/godot/godot --headless --path . --export-release "Linux release"
#   <export> --headless -- --console-strict --console-exec="scenario combat_sandbox; wait 30; bench furball 50 10 seed=1; quit"
# A bench run writes its report next to the export (<export dir>/reports/perf/), because res:// is the pack there. Measure
# from a snapshot (git archive) so edits in the working tree never reach the numbers.
set -euo pipefail

GODOT_VERSION="4.7.2-stable"
TPZ="Godot_v${GODOT_VERSION}_export_templates.tpz"
TPZ_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${TPZ}"
TPZ_SHA512="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
KEEP=(linux_release.x86_64 linux_debug.x86_64)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT}/.tools/godot/templates"

have_all() {
    local t
    for t in "${KEEP[@]}"; do
        [[ -x "${DEST}/${t}" ]] || return 1
    done
    grep -qx "${GODOT_VERSION}" "${DEST}/version.txt" 2> /dev/null
}

if have_all; then
    echo "Export templates ${GODOT_VERSION} already installed at ${DEST}"
    exit 0
fi

mkdir -p "${DEST}"
TMP="$(mktemp -d "${ROOT}/.tools/templates-dl.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

echo "Downloading ${TPZ_URL} (1.28 GB)"
curl -fsSL --retry 4 --retry-delay 2 -o "${TMP}/${TPZ}" "${TPZ_URL}"
echo "${TPZ_SHA512}  ${TMP}/${TPZ}" | sha512sum -c -
for t in "${KEEP[@]}"; do
    unzip -q -o -j "${TMP}/${TPZ}" "templates/${t}" -d "${DEST}"
    chmod +x "${DEST}/${t}"
done
echo "${GODOT_VERSION}" > "${DEST}/version.txt"
"${DEST}/linux_release.x86_64" --version || true
echo "Installed export templates ${GODOT_VERSION} at ${DEST}"
