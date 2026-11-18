#!/usr/bin/env bash
# The Cobra-bay interior's look sheet (M7-T09): the front end with its hangar backdrop on this machine's GPU, three moments of
# the slow camera move behind the menu, a wide and a close view of the racks without it, then one sheet with the frames, a strip
# of the maintainer's references and the paints' swatches (scripts/interior_sheet_node.gd). Each frame prints the `render`
# provider's numbers and the card's VRAM.
#
# Usage: scripts/interior_sheet.sh <out dir>        Environment: SHEET_RES (1920x1080), SHEET_SETTLE (120 frames), SHEET_DISPLAY
# (x11 or wayland), GODOT_BIN. It takes the Godot (read) and GPU locks itself (scripts/godot_lock.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
OUT="$(realpath -m "${1:?usage: scripts/interior_sheet.sh <out dir>}")"
mkdir -p "${OUT}"
"${ROOT}/scripts/godot_lock.sh" read --gpu -- timeout 600 "${GODOT}" --path . --resolution "${SHEET_RES:-1920x1080}" --disable-vsync ${SHEET_DISPLAY:+--display-driver "${SHEET_DISPLAY}"} -s res://scripts/interior_sheet.gd -- \
    out="${OUT}" settle="${SHEET_SETTLE:-120}" 2>&1 | tee "${OUT}/sheet.log" | grep -E '^\[interior_sheet\]|SCRIPT ERROR|ERROR' || true
