#!/usr/bin/env bash
# Epsilon III's look sheet (M6-T11): the planet on the scaled-space layer from the station's rail, a 400 km orbit, 1 000 km and
# 10 000 km up, day, terminator, night and the limb, on this machine's GPU with the game's sky and light and no ships
# (scripts/planet_sheet_node.gd). One PNG per view in references/screenshots/M6-T11 planet/ (or SHEET_OUT).
#
# Usage: scripts/planet_sheet.sh [view,view,...]          (every view by default; the names are in planet_sheet_node.gd)
# Environment: SHEET_OUT, SHEET_RES (1200x675), GODOT_BIN. Runs under the Godot (read) and GPU locks.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
source "${ROOT}/scripts/lib_locks.sh"
OUT="${SHEET_OUT:-references/screenshots/M6-T11 planet}"
ARGS=("shots=${OUT}" "flare=${SHEET_FLARE:-on}" "layer=${SHEET_LAYER:-on}")
if [[ $# -gt 0 ]]; then
    ARGS+=("views=$1")
fi
"${GODOT_LOCK_SH}" read --gpu -- timeout 900 "${GODOT}" --path . --resolution "${SHEET_RES:-1200x675}" \
    -s res://scripts/planet_sheet.gd -- "${ARGS[@]}" 2>&1 | grep -E '^\[planet_sheet\]|SCRIPT ERROR|ERROR'
