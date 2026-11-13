#!/usr/bin/env bash
# The Starfury's finish sheet shots (M7-T17): one Starfury in a wing's livery, a sun grazing its decks, the three-quarter view and a
# close view at ~7 m, in both texture sets, on this machine's GPU (scripts/starfury_metal_sheet_node.gd). For a before and after,
# build each version into its own scratch project (scripts/scratch_project.sh) and run this once per project with its own prefix.
#
# Usage: scripts/starfury_metal_sheet.sh <out dir> [prefix] [project dir]     (prefix "shot", project the repo)
# Environment: SHEET_RES (1600x900), SHEET_SETTLE (50 drawn frames), SHEET_LIVERY (alpha:1), GODOT_BIN.
# Runs on X11 (XWayland): Wayland stops drawing a window it does not show, which leaves stale frames.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
OUT="$(realpath -m "${1:?usage: scripts/starfury_metal_sheet.sh <out dir> [prefix] [project dir]}")"
PREFIX="${2:-shot}"
PROJECT="$(realpath "${3:-${ROOT}}")"
mkdir -p "${OUT}"
SCS_LOCK_LABEL="${SCS_LOCK_LABEL:-starfury_metal_sheet}" "${ROOT}/scripts/godot_lock.sh" read --gpu -- \
    timeout 600 "${GODOT}" --path "${PROJECT}" --display-driver x11 --resolution "${SHEET_RES:-1600x900}" \
    -s res://scripts/starfury_metal_sheet.gd -- out="${OUT}" prefix="${PREFIX}" settle="${SHEET_SETTLE:-50}" \
    livery="${SHEET_LIVERY:-alpha:1}" 2>&1 | tee "${OUT}/${PREFIX}.log" | grep -E '^\[starfury_metal_sheet\]|SCRIPT ERROR' || true
