#!/usr/bin/env bash
# Opt-in: installs Godot's Linux x86_64 export templates into .tools/godot/templates/ so the game can be measured as a
# release build (editor builds are slower at GDScript). Not part of setup_godot.sh or CI. Idempotent; the 1.28 GB archive is
# downloaded to a temporary folder, verified by SHA-512, and deleted again. Only the two Linux x86_64 templates are kept.
#
# Repeat a release run (M4-T03r). A template cannot open a project folder (it rejects --path), so measure an export:
#   1. Snapshot the commit so working-tree edits never reach the numbers: git archive <commit> | tar -x -C <snap>, copy
#      assets/generated/ into it, then .tools/godot/godot --headless --path <snap> --import.
#   2. In <snap>, an export_presets.cfg with one preset, name="Linux release", platform="Linux", export_filter="all_resources",
#      include_filter="*.json,*.ply,*.light,*.txt,*.cfg,*.obj,*.mtl",
#      exclude_filter="tests/*, docs/*, tools/*, scripts/*, addons/gut/*, reports/*", binary_format/embed_pck=true, and
#      custom_template/release set to this script's linux_release.x86_64 as an absolute path.
#   3. .tools/godot/godot --headless --path <snap> --export-release "Linux release" <build>/scs_release.x86_64
#   4. A bench run writes to <build>/reports/perf/ (res:// is the pack), so link <build>/reports to <snap>/reports.
#   5. For scripts/bench_quick.sh, set GODOT_BIN to a wrapper that drops "--path <dir>" and execs the export with the rest:
#        args=(); while (( $# )); do [[ $1 == --path ]] && { shift 2; continue; }; args+=("$1"); shift; done
#        exec <build>/scs_release.x86_64 "${args[@]}"
#      and run the snapshot's copy: GODOT_BIN=<wrapper> <snap>/scripts/bench_quick.sh <label>.
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
# The archive is 1.28 GB, too big for a tmpfs /tmp, so it is staged beside the templates.
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
