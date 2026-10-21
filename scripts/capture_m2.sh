#!/usr/bin/env bash
# Runs the M2 capture set P1-P4 (docs/milestones/m2-combat-sandbox.md, "Capture pre-checks") and writes PNGs to reports/m2/.
# By default it renders with software Vulkan through scripts/capture.sh (llvmpipe in xvfb; GDGS falls back to Raster there).
# On a desktop with a real GPU use CAPTURE_REAL_GPU=1 to open a window on it instead (GDGS Compute, real frame rate).
# Usage: scripts/capture_m2.sh [WxH]          e.g.  CAPTURE_REAL_GPU=1 scripts/capture_m2.sh 1920x1080
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIZE="${1:-1280x720}"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
OUT="${ROOT}/reports/m2"
mkdir -p "${OUT}"
cd "${ROOT}"

run() {  # run "<console commands>"
    if [[ "${CAPTURE_REAL_GPU:-0}" == "1" ]]; then
        timeout 600 "${GODOT}" --path . --resolution "${SIZE}" -- --console-strict --console-exec="$1; quit"
    else
        scripts/capture.sh "$1" "${SIZE}"
    fi
}

# The sandbox starts wave 1's countdown at load; stop it so the captures show only what they spawn.
PRE='wave stop'

echo "== P1 raider turntable (AC15)"
run "${PRE}; god on; camera cockpit; spawn raider idle 30 0 0; wait 30; screenshot reports/m2/p1_front.png; despawn all; spawn raider idle 30 90 0; wait 30; screenshot reports/m2/p1_side.png; despawn all; spawn raider idle 30 0 90; wait 30; screenshot reports/m2/p1_top.png; despawn all; spawn raider idle 30 35 20; wait 30; screenshot reports/m2/p1_three_quarter.png; fallback on; wait 10; screenshot reports/m2/p1_fallback.png"

echo "== P2 HUD (AC10, AC17)"
run "${PRE}; god on; spawn raider patrol 1500; wait 60; set targeting.selected \"RAIDER 1\"; wait 30; screenshot reports/m2/p2_chase.png; camera cockpit; wait 10; screenshot reports/m2/p2_cockpit.png; spawn raider idle 800 0 0; set targeting.selected \"RAIDER 2\"; wait 10; screenshot reports/m2/p2_box.png"

echo "== P3 destruction (AC16)"
run "${PRE}; god on; camera cockpit; spawn raider idle 120 30 0; wait 10; set targeting.selected \"RAIDER 1\"; timescale 0.1; kill target; wait 4; screenshot reports/m2/p3_flash.png; wait 20; screenshot reports/m2/p3_fireball.png; timescale 1; wait 90; screenshot reports/m2/p3_debris.png"

echo "== P4 combat overview (AC18 scene sanity)"
run "god on; wave start 3; wait 600; screenshot reports/m2/p4.png; state raiders"

echo "== done: $(ls "${OUT}"/*.png | wc -l) images in reports/m2/"
