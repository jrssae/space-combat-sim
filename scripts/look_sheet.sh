#!/usr/bin/env bash
# The look sheet (M4-T30a, checkpoint 1b): one ship photographed on this machine's GPU, fullscreen with the 3D at 1 080 lines, as
# its textured mesh, at 8, 30, 150 and 600 m, lit from behind the camera and from behind the ship, plus the cockpit view; every
# shot at /tmp/m4_t30a_<asset>_textured_<m>m_<light>.png and the sheet at /tmp/m4_t30_<asset>_sheet.png,
# each tile labelled with its GPU time (scripts/look_sheet_node.gd).
#
# Usage: scripts/look_sheet.sh [asset_id] [label]        (starfury_aurora by default)
# Environment: SHEET_OUT (/tmp), SHEET_DISTANCES (8,30,150,600), SHEET_LIGHTS (lit,dark),
#              SHEET_SETTLE (40 frames a shot), SHEET_RES (1920x1080), GODOT_BIN.
#              M4-T30b (checkpoint 1c): SHEET_LIVERIES (wing:number,... a column each), SHEET_COMPARE (a pattern of
#              earlier shots, %d metres and %s lit or dark, as one more column), SHEET_COMPARE_LABEL, SHEET_PREFIX (m4_t30a), SHEET_PATH.
#              M4-T30d: SHEET_COCKPIT (1; 0 leaves the cockpit view out, for the props: nav_buoy, raider_fighter_chunks,
#              starfury_aurora_chunks, capital_cruiser, capital_destroyer, capital_carrier, b5_station).
# Run it under the bench locks: flock /tmp/m5-godot.lock flock /tmp/scs-bench.lock scripts/look_sheet.sh ...
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
source "${ROOT}/scripts/lib_locks.sh"

ASSET="${1:-starfury_aurora}"
LABEL="${2:-m4_t30a_sheet_${ASSET}}"
OUT_DIR="${SHEET_OUT:-/tmp}"
RES="${SHEET_RES:-1920x1080}"
OUT="reports/perf/${LABEL}"
LOG="${OUT}/sheet.log"
if [[ ! -x "${GODOT}" ]]; then
    echo "look_sheet.sh: Godot not found at ${GODOT}; run scripts/setup_godot.sh (or set GODOT_BIN)." >&2
    exit 1
fi
mkdir -p "${OUT}"
touch reports/.gdignore
status=0
flock "${GPU_LOCK}" timeout 900 "${GODOT}" --path . --resolution "${RES}" --fullscreen --disable-vsync \
    -s res://scripts/look_sheet.gd -- asset="${ASSET}" out="${OUT_DIR}" distances="${SHEET_DISTANCES:-8,30,150,600}" \
    lights="${SHEET_LIGHTS:-lit,dark}" settle="${SHEET_SETTLE:-40}" scale3d=1080p \
    liveries="${SHEET_LIVERIES:-}" compare="${SHEET_COMPARE:-}" compare_label="${SHEET_COMPARE_LABEL:-T30A}" prefix="${SHEET_PREFIX:-m4_t30a}" \
    sheet="${SHEET_PATH:-}" cockpit="${SHEET_COCKPIT:-1}" \
    > "${LOG}" 2>&1 || status=$?
grep -E '^\[sheet\]|SCRIPT ERROR|console error' "${LOG}" || true
if (( status != 0 )); then
    echo "look_sheet.sh: the run exited ${status} (124 is the timeout); see ${LOG}" >&2
fi
exit "${status}"
