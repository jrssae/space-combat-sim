#!/usr/bin/env bash
# The GPU test behind the class budgets (M10-T05, Q38; docs/assets-capital.md, "Class budgets"): a fleet of stand-in hulls, each
# at its class's ceiling, in view on this machine's GPU (scripts/class_budget_probe_node.gd).
#
# Usage: scripts/class_budget_probe.sh <out_dir> [scale]     scale multiplies every class's triangles (2: twice the budget)
# Environment: PROBE_RES (1920x1080), PROBE_CLASSES and PROBE_PHASES (the node's `classes` and `phases`), GODOT_BIN.
# Prints one line a phase and saves <out_dir>/<phase>.png. The window runs through X11 without vsync, as the hull sheets do.
# Run it under the locks: scripts/godot_lock.sh read --gpu -- scripts/class_budget_probe.sh ...
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"

OUT="${1:?output folder}"
SCALE="${2:-1}"
RES="${PROBE_RES:-1920x1080}"
mkdir -p "${OUT}"

# name:length_m:triangles:atlas_px:atlases, the proposal of tools/procgen/core/budgets.py.
CLASSES="${PROBE_CLASSES:-fighter:12:$((40000 * SCALE)):2048:1,small_craft:30:$((30000 * SCALE)):2048:1,cruiser:400:$((60000 * SCALE)):4096:1,capital:1200:$((100000 * SCALE)):4096:2,dreadnought:3000:$((150000 * SCALE)):4096:4}"
# class:types:copies of each. The fleet: 2 dreadnoughts, 6 capitals, 12 cruisers, 16 small craft and 60 fighters.
FLEET="dreadnought:2:1;capital:3:2;cruiser:4:3;small_craft:4:4;fighter:4:15"
PHASES="${PROBE_PHASES:-empty,asset:capital_test_cruiser,capitals|dreadnought:2:1;capital:3:2;cruiser:4:3|lod,fleet|${FLEET}|lod,fleet_close|${FLEET}|lod|close,fleet_full_detail|${FLEET}|full|close}"

timeout 900 "${GODOT}" --path . --resolution "${RES}" --display-driver x11 --disable-vsync --audio-driver Dummy -s res://scripts/class_budget_probe.gd -- \
    "out=${OUT}" "classes=${CLASSES}" "phases=${PHASES}" 2>&1 | grep -E '^\[budget\]|SCRIPT ERROR|ERROR:' || true
