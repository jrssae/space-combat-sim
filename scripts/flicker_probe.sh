#!/usr/bin/env bash
# The flicker check from outside (M7): films the turning drum from 50 m, 300 m, 1 km and 3 km off a Cobra arm's door row on this
# machine's GPU (scripts/flicker_probe_node.gd), every frame saved, then measures each view with scripts/flicker_metric.py: how
# much the picture changes and changes straight back from one frame to the next (a light that z-fights, pops or glints).
#
# Usage: scripts/flicker_probe.sh <out dir> [fps] [frames per view]      Environment: PROBE_PATH (the project, default .),
# PROBE_VIEWS (50m,300m,1km,3km), PROBE_SET (setting:value,...), PROBE_SUN (on|off), PROBE_RES (1280x720), PROBE_DISPLAY, GODOT_BIN.
# At 60 fps a frame is a physics tick; 144 shows what the drum's drawing between ticks does. 660 frames at 60 fps turn the drum a
# quarter turn, so every view sees an arm pass. It takes the Godot (read) and GPU locks itself (scripts/godot_lock.sh).
# Frames are screenshots: give an out dir under references/screenshots/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
OUT="$(realpath -m "${1:?usage: scripts/flicker_probe.sh <out dir> [fps] [frames per view]}")"
FPS="${2:-60}"
FRAMES="${3:-660}"
mkdir -p "${OUT}"
"${ROOT}/scripts/godot_lock.sh" read --gpu -- timeout 1200 "${GODOT}" --path "${PROBE_PATH:-.}" --resolution "${PROBE_RES:-1280x720}" \
    ${PROBE_DISPLAY:+--display-driver "${PROBE_DISPLAY}"} --fixed-fps "${FPS}" -s res://scripts/flicker_probe.gd -- \
    out="${OUT}" frames="${FRAMES}" views="${PROBE_VIEWS:-}" set="${PROBE_SET:-}" sun="${PROBE_SUN:-on}" 2>&1 \
    | tee "${OUT}/probe.log" | grep -E '^\[flicker_probe\] [0-9a-z]+: |SCRIPT ERROR|ERROR' || true
for view in "${OUT}"/*/; do
    [[ -f "${view}f00000002.png" ]] || continue
    name="$(basename "${view}")"
    python3 "${ROOT}/scripts/flicker_metric.py" "${view%/}" --heat "${OUT}/heat_${name}.png" --strip "${OUT}/strip_${name}.png"
done | tee "${OUT}/metric.log"
