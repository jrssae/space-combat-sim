#!/usr/bin/env bash
# The scene measurer (M4-T27, maintainer Q24): one scene, fullscreen with the 3D at 1 080 lines, on this machine's GPU, under the GPU
# lock, measured for 20 s after a warm-up by scripts/measure_fight.gd, in the fullscreen check's form (Q20, Q25), and a screenshot for
# the maintainer at /tmp/m4_scene_<scene>[_vsync][_frozen].png.
#
# Scenes: battle (the battle layout at RC_N ships, 500 by default, the chase camera in the player's fight), station_near and
# station_far (`station near|far`: the Babylon 5 stand-in, 10 capitals, 80 fighters, the planet), hundred_view (100 idle ships in view).
#
# Usage: scripts/render_compare.sh <scene> [label]
# Environment: RC_N (500), RC_WARMUP (8), RC_WINDOW (20), RC_VSYNC (off|on), RC_FROZEN (0|1: pause the game 2 s before the window,
#              so it measures the drawing alone), RC_EXEC (more console statements), RC_BENCH_OPTS (more bench options), GODOT_BIN.
# It takes the Godot (read), GPU and bench locks itself (scripts/godot_lock.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
source "${ROOT}/scripts/lib_locks.sh"

SCENE="${1:?usage: scripts/render_compare.sh <scene> [label]}"
N="${RC_N:-500}"
WARMUP="${RC_WARMUP:-8}"
WINDOW="${RC_WINDOW:-20}"
VSYNC="${RC_VSYNC:-off}"
FROZEN="${RC_FROZEN:-0}"
SUFFIX=""
[[ "${VSYNC}" == "on" ]] && SUFFIX="${SUFFIX}_vsync"
[[ "${FROZEN}" == "1" ]] && SUFFIX="${SUFFIX}_frozen"
LABEL="${2:-m4_scene_${SCENE}${SUFFIX}}"
OUT="reports/perf/${LABEL}"
LOG="${OUT}/compare.log"
SHOT="/tmp/m4_scene_${SCENE}${SUFFIX}.png"
SCENE_ARG="quiet"
case "${SCENE}" in
    battle) EXEC="bench battle ${N} $(( WARMUP + WINDOW + 30 )) warmup=0 seed=1 label=${LABEL}/bench ${RC_BENCH_OPTS:-}" ;;
    station_near) EXEC="station near" ;;
    station_far) EXEC="station far" ;;
    hundred_view) SCENE_ARG="hundred_view"; EXEC="" ;;
    *) echo "render_compare.sh: unknown scene '${SCENE}'" >&2; exit 2 ;;
esac
[[ -n "${RC_EXEC:-}" ]] && EXEC="${EXEC:+${EXEC}; }${RC_EXEC}"
if [[ ! -x "${GODOT}" ]]; then
    echo "render_compare.sh: Godot not found at ${GODOT}; run scripts/setup_godot.sh (or set GODOT_BIN)." >&2
    exit 1
fi
mkdir -p "${OUT}"
touch reports/.gdignore
VSYNC_FLAG=(--disable-vsync)
[[ "${VSYNC}" == "on" ]] && VSYNC_FLAG=()
PAUSE_AT=""
[[ "${FROZEN}" == "1" ]] && PAUSE_AT="pause_at=$(( WARMUP - 2 ))"
status=0
"${GODOT_LOCK_SH}" read --gpu --bench -- timeout $(( WARMUP + WINDOW + 240 )) "${GODOT}" --path . --resolution 1920x1080 --fullscreen "${VSYNC_FLAG[@]}" \
    -s res://scripts/measure_fight.gd -- scene="${SCENE_ARG}" camera=chase warmup="${WARMUP}" window="${WINDOW}" label="${SCENE}" \
    exec="${EXEC}" scale3d=1080p ${PAUSE_AT} shot="${SHOT}" > "${LOG}" 2>&1 || status=$?
grep -E '^\[measure\]|^\[bench\]|SCRIPT ERROR|console error' "${LOG}" | grep -v "over 25 ms at" || true
{
    echo "# Scene measure: ${SCENE}, vsync ${VSYNC}, frozen ${FROZEN}"
    echo
    echo "Commit $(git rev-parse --short HEAD 2> /dev/null || echo unknown). Fullscreen, the 3D at 1 080 lines, chase camera. Screenshot ${SHOT}."
    echo
    echo '```'
    grep -E '^\[measure\]' "${LOG}" | grep -v "over 25 ms at" || true
    echo '```'
} > "${OUT}/compare.md"
if (( status != 0 )); then
    echo "render_compare.sh: the run exited ${status} (124 is the timeout); see ${LOG}" >&2
fi
exit "${status}"
