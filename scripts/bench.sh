#!/usr/bin/env bash
# The many-ships benchmark sweep (M4-T01, docs/milestones/m4-performance-and-scale.md): every layout at each ship count, three
# seeded runs each (5 s of warm-up, 30 s measured), headless on the real main scene. A layout stops after two failing ship
# counts in a row. Each run is its own Godot process, pinned to the performance cores, with a hard timeout, so one stuck run
# cannot hold up the sweep. Take a baseline with nothing else heavy running (no test suite, no GPU work).
#
# Writes reports/perf/<label>/: runs/<layout>_<n>_s<seed>/summary.{json,md} for every run, sweep.log, and the sweep's own
# summary.json and summary.md (max N per layout, the headline, the stage breakdown at 50 and 100 ships).
#
# Usage: scripts/bench.sh [label] [layout...]        (layouts: furball spread transit, all three by default)
# Environment: BENCH_NS ("25 50 100 150 200 300 400 500"), BENCH_SEEDS ("1 2 3"), BENCH_SECONDS (30), BENCH_WARMUP (5),
#              BENCH_CPUS (0-11, the i5-13600KF's performance cores; empty for no pinning), BENCH_SCENARIO (combat_sandbox),
#              BENCH_EXTRA (more bench options, e.g. "probe=paired"), GODOT_BIN.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"

LABEL="${1:-sweep_$(date +%Y%m%d-%H%M%S)}"
shift || true
LAYOUTS=("$@")
if (( ${#LAYOUTS[@]} == 0 )); then
    LAYOUTS=(furball spread transit)
fi
read -r -a NS <<< "${BENCH_NS:-25 50 100 150 200 300 400 500}"
read -r -a SEEDS <<< "${BENCH_SEEDS:-1 2 3}"
SECONDS_MEASURED="${BENCH_SECONDS:-30}"
WARMUP="${BENCH_WARMUP:-5}"
CPUS="${BENCH_CPUS-0-11}"
SCENARIO="${BENCH_SCENARIO:-combat_sandbox}"
EXTRA="${BENCH_EXTRA:-}"
OUT="reports/perf/${LABEL}"
LOG="${OUT}/sweep.log"
# Boot, scene load and pool growth, plus the run itself at a tenth of real time (the runner cuts a slower one short).
RUN_TIMEOUT=$(( 240 + 11 * (${SECONDS_MEASURED%.*} + ${WARMUP%.*} + 1) ))

if [[ ! -x "${GODOT}" ]]; then
    echo "bench.sh: Godot not found at ${GODOT}; run scripts/setup_godot.sh (or set GODOT_BIN)." >&2
    exit 1
fi
mkdir -p "${OUT}/runs"
touch reports/.gdignore  # or the next --import takes the reports for game files
PIN=()
if [[ -n "${CPUS}" ]] && command -v taskset > /dev/null; then
    PIN=(taskset -c "${CPUS}")
fi
COMMIT="$(git rev-parse --short HEAD 2> /dev/null || echo unknown)"
DIRTY="$(git status --porcelain 2> /dev/null | grep -v '^??' | head -c1 || true)"
[[ -n "${DIRTY}" ]] && COMMIT="${COMMIT}+dirty"

{
    echo "== bench.sh ${LABEL} $(date -Iseconds), commit ${COMMIT}, layouts ${LAYOUTS[*]}, N ${NS[*]}, seeds ${SEEDS[*]}, ${WARMUP} s + ${SECONDS_MEASURED} s, cpus ${CPUS:-all}, scenario ${SCENARIO} ${EXTRA}"
    echo "   load $(cut -d' ' -f1-3 /proc/loadavg); other Godot processes:"
    pgrep -a godot | cut -c1-160 || echo "   none"
} | tee -a "${LOG}"

# one <layout> <n> <seed>: one run in its own process; prints its [bench] line.
one() {
    local layout="$1" n="$2" seed="$3" status=0
    local name="${layout}_${n}_s${seed}"
    local run_log="${OUT}/runs/${name}.log"
    rm -rf "${OUT:?}/runs/${name}"  # a summary left from an earlier sweep under this label must not stand in for this run
    "${PIN[@]}" timeout "${RUN_TIMEOUT}" "${GODOT}" --headless --path . -- --console-strict \
        --console-exec="scenario ${SCENARIO}; wait 30; bench ${layout} ${n} ${SECONDS_MEASURED} warmup=${WARMUP} seed=${seed} label=${LABEL}/runs/${name} ${EXTRA}; quit" \
        > "${run_log}" 2>&1 || status=$?
    grep -E '^\[bench\]|SCRIPT ERROR|^\[console\] error' "${run_log}" | tee -a "${LOG}" || true
    if (( status != 0 )); then
        echo "bench.sh: ${name} exited ${status} (124 is the timeout); see ${run_log}" | tee -a "${LOG}" >&2
    fi
    if [[ ! -f "${OUT}/runs/${name}/summary.json" ]]; then
        echo "bench.sh: ${name} wrote no summary; the sweep counts it as a failed run" | tee -a "${LOG}" >&2
    fi
}

summarise() {
    "${GODOT}" --headless --path . -s res://scripts/bench_sweep.gd -- "res://${OUT}" "runs=${#SEEDS[@]}" "commit=${COMMIT}" "label=${LABEL}" \
        2> /dev/null | grep '^\[bench-sweep\]' || true
}

for layout in "${LAYOUTS[@]}"; do
    for n in "${NS[@]}"; do
        for seed in "${SEEDS[@]}"; do
            one "${layout}" "${n}" "${seed}"
        done
        verdicts="$(summarise)"
        echo "${verdicts}" | grep -E "^\[bench-sweep\] ${layout} ${n} " | tee -a "${LOG}" || true
        if echo "${verdicts}" | grep -qE "^\[bench-sweep\] ${layout} max_n [0-9]+ stop$"; then
            echo "bench.sh: ${layout} stops after two failing ship counts in a row" | tee -a "${LOG}"
            break
        fi
    done
done
summarise | grep -E 'max_n|headline' | tee -a "${LOG}"
echo "== done $(date -Iseconds): ${OUT}/summary.md" | tee -a "${LOG}"
