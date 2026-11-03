#!/usr/bin/env bash
# The fullscreen render check (M4-T07, maintainer Q20): a bench layout in a fullscreen 1920x1080 window on this machine's GPU,
# under the GPU lock, measured for 20 s after a warm-up by scripts/measure_fight.gd (the chase camera on the player at the
# player's fight). Records FPS, frame time, GPU time, VRAM, draw calls and the 3D scale, with the verdict: the battle's floor is
# 30 FPS and its target 60; typical must hold 60 with headroom (frame mean 12 ms or under). Vsync is off so headroom shows.
#
# Usage: scripts/fullscreen_check.sh <layout> <n> [label]      e.g. scripts/fullscreen_check.sh typical 58
# Environment: FULLSCREEN_WARMUP (8), FULLSCREEN_WINDOW (20), FULLSCREEN_SEED (1), FULLSCREEN_RES (1920x1080),
#              FULLSCREEN_EXEC (more console statements after the bench starts), GODOT_BIN.
# Writes reports/perf/<label>/fullscreen.md and fullscreen.log, and a screenshot. Opens a window for about a minute.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"

LAYOUT="${1:?usage: scripts/fullscreen_check.sh <layout> <n> [label]}"
N="${2:?usage: scripts/fullscreen_check.sh <layout> <n> [label]}"
LABEL="${3:-fullscreen_${LAYOUT}_${N}_$(date +%Y%m%d-%H%M%S)}"
WARMUP="${FULLSCREEN_WARMUP:-8}"
WINDOW="${FULLSCREEN_WINDOW:-20}"
SEED="${FULLSCREEN_SEED:-1}"
RES="${FULLSCREEN_RES:-1920x1080}"
EXTRA="${FULLSCREEN_EXEC:-}"
OUT="reports/perf/${LABEL}"
LOG="${OUT}/fullscreen.log"
REPORT="${OUT}/fullscreen.md"
case "${LAYOUT}" in furball|spread|transit|battle|typical) ;; *) echo "fullscreen_check.sh: unknown layout '${LAYOUT}'" >&2; exit 2 ;; esac
if [[ ! -x "${GODOT}" ]]; then
    echo "fullscreen_check.sh: Godot not found at ${GODOT}; run scripts/setup_godot.sh (or set GODOT_BIN)." >&2
    exit 1
fi
mkdir -p "${OUT}"
touch reports/.gdignore  # or the next --import takes the screenshot for a game texture
# The bench outlives the measured window; the measure quits the game when its window ends.
BENCH_S=$(( WARMUP + WINDOW + 30 ))
EXEC="bench ${LAYOUT} ${N} ${BENCH_S} warmup=0 seed=${SEED} label=${LABEL}/bench"
[[ -n "${EXTRA}" ]] && EXEC="${EXEC}; ${EXTRA}"
status=0
flock /tmp/scs-gpu.lock timeout $(( WARMUP + WINDOW + 240 )) "${GODOT}" --path . --resolution "${RES}" --fullscreen --disable-vsync \
    -s res://scripts/measure_fight.gd -- scene=quiet camera=chase warmup="${WARMUP}" window="${WINDOW}" label="${LAYOUT}_${N}" \
    exec="${EXEC}" shot="${OUT}/fullscreen.png" > "${LOG}" 2>&1 || status=$?
grep -E '^\[measure\]|^\[bench\]|SCRIPT ERROR' "${LOG}" || true
if (( status != 0 )); then
    echo "fullscreen_check.sh: the run exited ${status} (124 is the timeout); see ${LOG}" >&2
fi

python3 -I - "${LOG}" "${LAYOUT}" "${N}" "${REPORT}" "$(git rev-parse --short HEAD 2> /dev/null || echo unknown)" <<'PY'
import re, sys
log, layout, n, report, commit = sys.argv[1:6]
text = open(log, errors="replace").read()
lines = [l for l in text.splitlines() if l.startswith("[measure]") or l.startswith("[bench]")]
scale = next((l for l in lines if "3d scale" in l), "")
def num(pattern, line):
    m = re.search(pattern, line)
    return float(m.group(1)) if m else None
fps = num(r"fps mean ([0-9.]+)", scale)
frame = num(r"frame ms mean ([0-9.]+)", scale)
if fps is None:
    verdict = "no measurement: the run printed no summary (see fullscreen.log)"
elif layout == "typical":
    verdict = "pass" if frame <= 12.0 else ("60 FPS but without the headroom (frame mean %.2f ms > 12 ms)" % frame if fps >= 60.0 else "fail: under 60 FPS")
    verdict = "typical: %s (target 60 FPS with headroom: frame mean 12 ms or under; %.1f FPS, %.2f ms)" % (verdict, fps, frame)
else:
    floor = "holds" if fps >= 30.0 else "misses"
    target = "holds" if fps >= 60.0 else "misses"
    verdict = "%s: the 30 FPS floor %s, the 60 FPS target %s (%.1f FPS, frame mean %.2f ms)" % (layout, floor, target, fps, frame)
with open(report, "w") as f:
    f.write("# Fullscreen check: %s %s\n\nCommit %s. Fullscreen 1920x1080, vsync off, chase camera, the bench's own layout.\n\n" % (layout, n, commit))
    f.write("**Verdict:** %s\n\n```\n%s\n```\n" % (verdict, "\n".join(lines)))
print("[fullscreen] %s -> %s" % (verdict, report))
PY
