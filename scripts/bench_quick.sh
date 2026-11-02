#!/usr/bin/env bash
# Quick performance check (M4): ramps the ship count, one short seeded run per count, and prints how the tick grows. Done in
# under 10 minutes; indicative only. Max N and the milestone's numbers come from scripts/bench.sh.
# A layout stops at the first count where the simulation can no longer keep real time (tick median over one 60 Hz frame), or
# when its next run would not fit in its share of the time budget.
#
# Usage: scripts/bench_quick.sh [label] [layout...]   (furball and spread by default, the headline's two; or transit)
# Environment: QUICK_NS ("10 15 20 25 30 40 50 75 100 150 200 300 400 500"), QUICK_SECONDS (6), QUICK_WARMUP (2),
#              QUICK_SEED (1), QUICK_BUDGET_S (540), BENCH_CPUS (0-11; empty for no pinning), GODOT_BIN.
# Writes reports/perf/<label>/quick.md and each run's summary under runs/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"

LABEL="${1:-quick_$(date +%Y%m%d-%H%M%S)}"
shift || true
LAYOUTS=("$@")
if (( ${#LAYOUTS[@]} == 0 )); then
    LAYOUTS=(furball spread)
fi
read -r -a NS <<< "${QUICK_NS:-10 15 20 25 30 40 50 75 100 150 200 300 400 500}"
SECONDS_MEASURED="${QUICK_SECONDS:-6}"
WARMUP="${QUICK_WARMUP:-2}"
SEED="${QUICK_SEED:-1}"
BUDGET_S="${QUICK_BUDGET_S:-540}"
CPUS="${BENCH_CPUS-0-11}"
OUT="reports/perf/${LABEL}"
REPORT="${OUT}/quick.md"
FRAME_US=16667

if [[ ! -x "${GODOT}" ]]; then
    echo "bench_quick.sh: Godot not found at ${GODOT}; run scripts/setup_godot.sh (or set GODOT_BIN)." >&2
    exit 1
fi
for layout in "${LAYOUTS[@]}"; do
    case "${layout}" in furball|spread|transit) ;; *) echo "bench_quick.sh: unknown layout '${layout}'" >&2; exit 2 ;; esac
done
mkdir -p "${OUT}/runs"
touch reports/.gdignore  # or the next --import takes the reports for game files
PIN=()
if [[ -n "${CPUS}" ]] && command -v taskset > /dev/null; then
    PIN=(taskset -c "${CPUS}")
fi
COMMIT="$(git rev-parse --short HEAD 2> /dev/null || echo unknown)"

# row <summary.json>: one table row, then the tick median in microseconds and whether the run passed, for the shell.
row() {
    python3 -I - "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
if d.get("missing"):
    print("| %d | run died | | | | | | | fail |" % d["n"]); print("0 0"); sys.exit()
s, ms = d["stages"], lambda us: "%.2f" % (us / 1000.0)
mean = lambda k: s.get(k, {}).get("mean_us", 0.0)
ok = d["verdict"]["pass"]
print("| %d | %s | %s | %s | %.1f %% | %s | %s | %s | %s |" % (d["n"], ms(s["tick"]["median_us"]), ms(s["tick"]["p99_us"]),
      ms(d["rebase"]["tick_max_us"]) if d["rebase"]["count"] else "none", 100.0 * d["lag"], ms(mean("targeting")),
      ms(mean("ai")), ms(mean("resolvers")), "pass" if ok else "fail" + (" (cut short)" if d.get("aborted") else "")))
print("%d %d" % (s["tick"]["median_us"], 1 if ok else 0))
EOF
}

START=$(date +%s)
{
    echo "# Quick check ${LABEL}: ${LAYOUTS[*]}, seed ${SEED}, ${WARMUP} s + ${SECONDS_MEASURED} s per count"
    echo
    echo "Commit ${COMMIT}, $(date -Iseconds), load $(cut -d' ' -f1-3 /proc/loadavg). One short run per count: indicative, not the verdict."
} | tee "${REPORT}"

# ramp <layout> <seconds it may use>: one table, from the smallest count up.
ramp() {
    local layout="$1" budget="$2" t_start passed=0 kept=0 last_wall=0 stop="every count ran"
    t_start=$(date +%s)
    {
        echo
        echo "## ${layout}"
        echo
        echo "| N | tick median ms | p99 ms | worst rebase tick ms | behind real time | targeting ms | ai ms | resolvers ms | budget |"
        echo "|---|---|---|---|---|---|---|---|---|"
    } | tee -a "${REPORT}"
    for n in "${NS[@]}"; do
        local elapsed=$(( $(date +%s) - t_start ))
        # The next count costs at least what the last one did; skip it if that would break the budget.
        if (( last_wall > 0 && elapsed + 2 * last_wall > budget )); then
            stop="time budget (${budget} s) reached before ${n}"
            break
        fi
        local name="${layout}_${n}_s${SEED}" t0 lines median_us ok
        rm -rf "${OUT:?}/runs/${name}"
        t0=$(date +%s)
        "${PIN[@]}" timeout $(( budget - elapsed + 30 )) "${GODOT}" --headless --path . -- --console-strict \
            --console-exec="scenario combat_sandbox; wait 30; bench ${layout} ${n} ${SECONDS_MEASURED} warmup=${WARMUP} seed=${SEED} label=${LABEL}/runs/${name}; quit" \
            > "${OUT}/runs/${name}.log" 2>&1 || true
        last_wall=$(( $(date +%s) - t0 ))
        if [[ ! -f "${OUT}/runs/${name}/summary.json" ]]; then
            mkdir -p "${OUT}/runs/${name}"
            printf '{"n": %d, "missing": true}\n' "${n}" > "${OUT}/runs/${name}/summary.json"
        fi
        mapfile -t lines < <(row "${OUT}/runs/${name}/summary.json")
        if (( ${#lines[@]} < 2 )); then
            lines=("| ${n} | report unreadable | | | | | | | fail |" "0 0")
        fi
        echo "${lines[0]}" | tee -a "${REPORT}"
        read -r median_us ok <<< "${lines[1]}"
        (( ok == 1 )) && passed=${n}
        if (( median_us == 0 )); then
            stop="the run at ${n} ships gave no numbers; see ${OUT}/runs/${name}.log"
            break
        fi
        if (( median_us > FRAME_US )); then
            stop="the tick passed one frame at ${n} ships: the simulation no longer keeps real time"
            break
        fi
        kept=${n}
    done
    {
        echo
        echo "- Inside the budget (median 8 ms, p99 12 ms, rebase tick 16.7 ms, real time): up to **${passed}** ships (largest passing count)."
        echo "- Keeps real time (tick median under 16.7 ms): up to **${kept}** ships."
        echo "- Stopped: ${stop}. Took $(( $(date +%s) - t_start )) s."
    } | tee -a "${REPORT}"
}

left=${#LAYOUTS[@]}
for layout in "${LAYOUTS[@]}"; do
    # Each layout gets an even share of what is left, so an early one that ends quickly leaves more for the rest.
    ramp "${layout}" $(( (BUDGET_S - ($(date +%s) - START)) / left ))
    left=$(( left - 1 ))
done
echo | tee -a "${REPORT}"
echo "Total $(( $(date +%s) - START )) s. Report: ${REPORT}" | tee -a "${REPORT}"
