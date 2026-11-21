#!/usr/bin/env bash
# A capital hull's look sheet and surface option sheet (M12-T19), photographed on this machine's GPU through the `sheet`
# command (scripts/hull_sheet_node.gd), then laid out with labels (tools/refview/hull_sheets.py; needs Pillow in .venv).
#
# Usage: scripts/hull_sheet.sh <asset_id> <out_dir> [options]     options: the surface options built under
#        assets/generated/<asset_id>_options/<option>/ (e.g. "b c"); the asset's own build is the first option, "a".
# Environment: SHEET_TITLES ("a=A: show green|b=..." names the options on the sheet), SHEET_NOTE (added to the title lines, e.g.
#              the machine), SHEET_RES (1920x1080), SHEET_SETTLE (50 frames a shot), GODOT_BIN.
# Writes <out_dir>/shots/*.png, <out_dir>/look_sheet.png and, with options, <out_dir>/option_sheet.png.
# The window runs through X11 without vsync: a Wayland window that is covered or on a blanked screen stops drawing, and every
# later shot repeats the first.
# Run it under the locks: flock /tmp/gpu.lock flock /tmp/m12-godot.lock scripts/hull_sheet.sh ...
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"

ASSET="${1:?asset id}"
OUT="${2:?output folder}"
OPTIONS="${3:-}"
RES="${SHEET_RES:-1920x1080}"
mkdir -p "${OUT}/shots"

# The look sheet: three quarters on from 50 m, 500 m and 5 km (the nearest corner's distance), then port, top and front.
shots="empty|-|0|three_quarter|high,look_50m|${ASSET}|50|three_quarter|high,look_500m|${ASSET}|500|three_quarter|high,look_5km|${ASSET}|5000|three_quarter|high"
shots+=",look_port|${ASSET}|130|side|high,look_top|${ASSET}|130|top|high,look_front|${ASSET}|130|front|high"
# The option sheet: each option's low and high texture set, close and whole.
if [[ -n "${OPTIONS}" ]]; then
    for option in a ${OPTIONS}; do
        id="${ASSET}"
        [[ "${option}" != "a" ]] && id="${ASSET}:${option}"
        for detail in low high; do
            shots+=",option_${option}_${detail}_close|${id}|8|side|${detail},option_${option}_${detail}_whole|${id}|60|three_quarter|${detail}"
        done
    done
fi
timeout 900 "${GODOT}" --path . --resolution "${RES}" --display-driver x11 --disable-vsync -s res://scripts/hull_sheet.gd -- "out=${OUT}/shots" \
    "settle=${SHEET_SETTLE:-50}" "shots=${shots}" 2>&1 | grep -E '^\[hull sheet\]|SCRIPT ERROR' || true
.venv/bin/python3 tools/refview/hull_sheets.py "${ASSET}" "${OUT}" ${OPTIONS} --titles "${SHEET_TITLES:-}" --note "${SHEET_NOTE:-}"
