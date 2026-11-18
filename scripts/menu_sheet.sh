#!/usr/bin/env bash
# The start menu's and pause menu's pages on this machine's GPU (M7-T31), one PNG per page, for the maintainer's before/after sheet
# (scripts/menu_sheet_node.gd). Usage: scripts/menu_sheet.sh <out dir> <tag>   (tag: before or after; the files are <tag>_<page>.png)
# Environment: SHEET_RES (the project's 1920x1080), SHEET_SETTLE (frames per page, 20), SHEET_DISPLAY (x11), GODOT_BIN.
# It takes the Godot (read) and GPU locks itself (scripts/godot_lock.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
OUT="$(realpath -m "${1:?usage: scripts/menu_sheet.sh <out dir> <tag>}")"
TAG="${2:?usage: scripts/menu_sheet.sh <out dir> <tag>}"
mkdir -p "${OUT}"
"${ROOT}/scripts/godot_lock.sh" read --gpu -- timeout 300 "${GODOT}" --path . ${SHEET_RES:+--resolution "${SHEET_RES}"} --disable-vsync --display-driver "${SHEET_DISPLAY:-x11}" -s res://scripts/menu_sheet.gd -- \
    out="${OUT}" tag="${TAG}" settle="${SHEET_SETTLE:-20}" 2>&1 | tee "${OUT}/${TAG}.log" | grep -E '^\[menu_sheet\]|SCRIPT ERROR|ERROR' || true
