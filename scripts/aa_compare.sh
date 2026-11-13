#!/usr/bin/env bash
# Compares the anti-aliasing modes in one process (M4-T38): a bench layout fullscreen, vsync off, frozen after a warm-up (or live
# with pause=off), the modes taking turns for several rounds so the GPU's clock changes cancel. Prints the GPU ms and FPS per mode
# and saves a screenshot per mode. Runs under the Godot (read), GPU and bench locks.
#
# Usage: scripts/aa_compare.sh <label> [option=value ...]   e.g. scripts/aa_compare.sh battle300_1080 layout=battle n=300 scale3d=1080p
# Options (scripts/aa_compare_node.gd): layout n seed warmup pause modes rounds frames settle scale3d camera exec.
# Writes reports/perf/aa_compare/<label>.log and reports/perf/aa_compare/<label>/<mode>.png.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
source "${ROOT}/scripts/lib_locks.sh"
LABEL="${1:?usage: scripts/aa_compare.sh <label> [option=value ...]}"
shift
OUT="reports/perf/aa_compare"
mkdir -p "${OUT}"
touch reports/.gdignore
"${GODOT_LOCK_SH}" read --gpu --bench -- timeout 900 "${GODOT}" --path . --fullscreen --disable-vsync \
    -s res://scripts/aa_compare.gd -- "$@" shots="${OUT}/${LABEL}" > "${OUT}/${LABEL}.log" 2>&1
grep -E '^\[aa_compare\]|SCRIPT ERROR' "${OUT}/${LABEL}.log"
