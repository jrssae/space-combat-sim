#!/usr/bin/env bash
# The Babylon 5 station's look sheet shots (M7-T04): the station on this machine's GPU from 50 m off a Cobra bay and off the
# docking aperture, 200 m, 1 km, 10 km and 100 km, lit from over the camera's shoulder, each shot with the `render` provider's
# numbers (scripts/station_sheet_node.gd). The station's maps are measured first (their bytes and the card's VRAM delta).
#
# Usage: scripts/station_sheet.sh <out dir>        Environment: SHEET_RES (1920x1080), SHEET_SETTLE (90 frames), SHEET_VIEWS
# (t19, fly or doors: M7-T19's sets; t05 or markers: M7-T05's; empty: the look sheet), SHEET_DISPLAY, GODOT_BIN.
# It takes the Godot (read) and GPU locks itself (scripts/godot_lock.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
OUT="$(realpath -m "${1:?usage: scripts/station_sheet.sh <out dir>}")"
mkdir -p "${OUT}"
"${ROOT}/scripts/godot_lock.sh" read --gpu -- timeout 600 "${GODOT}" --path . --resolution "${SHEET_RES:-1920x1080}" --fullscreen --disable-vsync ${SHEET_DISPLAY:+--display-driver "${SHEET_DISPLAY}"} -s res://scripts/station_sheet.gd -- \
    out="${OUT}" settle="${SHEET_SETTLE:-90}" views="${SHEET_VIEWS:-}" 2>&1 | tee "${OUT}/sheet.log" | grep -E '^\[station_sheet\]|SCRIPT ERROR|ERROR' || true
