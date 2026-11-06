#!/usr/bin/env bash
# The fullscreen render check (M4-T07, maintainer Q20): a bench layout fullscreen, the 3D at 1080p, on this machine's GPU,
# under the GPU lock, measured for 20 s after a warm-up by scripts/measure_fight.gd (the chase camera on the player at the
# player's fight). Records FPS, frame time, GPU time, VRAM, draw calls and the 3D scale, with the verdict: the battle's floor is
# 30 FPS and its target 60; typical must hold 60 with headroom (frame mean 12 ms or under). Vsync is off so headroom shows.
# The window is fullscreen at the screen's own size (3840x2160 on this machine); the 3D is rendered at 1 080 lines
# (FULLSCREEN_SCALE, `1080p` by default; 1 for the screen's own resolution), the HUD at the screen's.
#
# Usage: scripts/fullscreen_check.sh <layout> <n> [label]      e.g. scripts/fullscreen_check.sh typical 58
# Environment: FULLSCREEN_WARMUP (8), FULLSCREEN_WINDOW (20), FULLSCREEN_SEED (1), FULLSCREEN_RES (1920x1080),
#              FULLSCREEN_EXEC (more console statements after the bench starts), FULLSCREEN_SCALE (1080p, a bilinear stretch;
#              `setting` leaves the 3D to the upscaler settings, M4-T40, e.g. with FULLSCREEN_EXEC="upscale fsr2 quality"),
#              FULLSCREEN_BENCH_OPTS (more bench options, e.g. "rocks=0"), FULLSCREEN_PAUSE_AT (seconds after the start at which the
#              game is paused, so the window measures the drawing alone, as render_compare.sh's frozen runs do), GODOT_BIN.
# Writes reports/perf/<label>/fullscreen.md (a verdict and, since M4-P2, Q48's row: average FPS, the 1 % low, the p99 frame time) and
# fullscreen.log, and a screenshot. Opens a window for about a minute.
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
PAUSE_AT="${FULLSCREEN_PAUSE_AT:-}"
SCALE="${FULLSCREEN_SCALE:-1080p}"
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
EXEC="bench ${LAYOUT} ${N} ${BENCH_S} warmup=0 seed=${SEED} label=${LABEL}/bench ${FULLSCREEN_BENCH_OPTS:-}"
[[ -n "${EXTRA}" ]] && EXEC="${EXEC}; ${EXTRA}"
status=0
flock /tmp/scs-gpu.lock timeout $(( WARMUP + WINDOW + 240 )) "${GODOT}" --path . --resolution "${RES}" --fullscreen --disable-vsync \
    -s res://scripts/measure_fight.gd -- scene=quiet camera=chase warmup="${WARMUP}" window="${WINDOW}" label="${LAYOUT}_${N}" \
    exec="${EXEC}" scale3d="${SCALE}" pause_at="${PAUSE_AT}" shot="${OUT}/fullscreen.png" > "${LOG}" 2>&1 || status=$?
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
frame = num(r"frame mean ms ([0-9.]+)", scale)
p99 = num(r"frame p99 ms ([0-9.]+)", scale)
low = num(r"fps 1% low ([0-9.]+)", scale)
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
    f.write("# Fullscreen check: %s %s\n\nCommit %s. Fullscreen, the 3D at 1 080 lines unless the log says otherwise, vsync off, chase camera, the bench's own layout.\n\n" % (layout, n, commit))
    f.write("**Verdict:** %s\n\n" % verdict)
    if fps is not None and low is not None:
        # Q48's row: the average FPS, the 1 % low (the slowest 1 % of the window's frames) and the p99 frame time.
        gpu = num(r"gpu ms mean ([0-9.]+)", next((l for l in lines if "gpu ms mean" in l), ""))
        calls = next((num(r"draw calls mean ([0-9.]+)", l) for l in lines if "draw calls mean" in l), None)
        speed = next((num(r"\(([0-9.]+) of real time", l) for l in lines if "of real time" in l), None)
        vram = num(r"process's VRAM before [0-9.]+ MB, peak ([0-9.]+) MB", next((l for l in lines if "process's VRAM" in l), ""))
        f.write("| layout | N | average FPS | 1 % low FPS | p99 frame ms | frame mean ms | sim speed | GPU ms mean | draw calls | game VRAM peak MB |\n|---|---|---|---|---|---|---|---|---|---|\n")
        f.write("| %s | %s | %.1f | %.1f | %.2f | %.2f | %s | %s | %s | %s |\n\n" % (layout, n, fps, low, p99 if p99 is not None else float("nan"), frame,
                "%.2f" % speed if speed is not None else "?",
                "%.2f" % gpu if gpu is not None else "?", "%.0f" % calls if calls is not None else "?", "%.0f" % vram if vram is not None else "?"))
    f.write("```\n%s\n```\n" % "\n".join(lines))
print("[fullscreen] %s -> %s" % (verdict, report))
PY
