#!/usr/bin/env bash
# Shots of a generated model the game has no ShipSpec or catalogue entry for (M10-T50), photographed on this machine's GPU
# with the game's scene, light and materials (scripts/model_sheet_node.gd), for option and look sheets.
#
# Usage: scripts/model_sheet.sh <out_dir> <shot> [<shot> ...]
#        a shot: name|asset[:option]|distance_m|view|low or high|lit or dark|aim x;y;z|wing:number   (the last two may be empty)
#        views: three_quarter rear_quarter top bottom side (port) starboard front; an option is read from <asset>_options/<option>/<asset>/;
#        an asset of - is the empty scene (its video memory is the baseline: each shot's is printed).
# Environment: SHEET_PATH (the Godot project, default the repo; a scratch project holds the options), SHEET_RES (1920x1080),
#              SHEET_SETTLE (50 frames a shot), GODOT_BIN.
# Writes <out_dir>/<name>.png. The window runs through X11 without vsync and without sound; it takes the Godot (read) and GPU
# locks itself (scripts/godot_lock.sh). Lay the shots out with tools/refview/model_sheets.py.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
source "${ROOT}/scripts/lib_locks.sh"

OUT="${1:?output folder}"
shift
mkdir -p "${OUT}"
shots="$(IFS=,; echo "$*")"
"${GODOT_LOCK_SH}" read --gpu -- timeout 900 "${GODOT}" --path "${SHEET_PATH:-.}" --resolution "${SHEET_RES:-1920x1080}" --display-driver x11 \
    --disable-vsync --audio-driver Dummy -s res://scripts/model_sheet.gd -- "out=${OUT}" "settle=${SHEET_SETTLE:-50}" "shots=${shots}" 2>&1 \
    | grep -E '^\[model sheet\]|SCRIPT ERROR' || true
