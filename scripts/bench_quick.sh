#!/usr/bin/env bash
# Quick performance check (M4): ramps the ship count, one short seeded run per count, and reports which counts held the budget
# and where the frame rate gave out. Done in under 10 minutes; indicative only. Max N comes from scripts/bench.sh.
# FPS here is simulation ticks per wall-clock second (60 while the simulation keeps real time). A layout stops at the first
# count under the FPS floor, or when its next run would not fit in its share of the time budget.
#
# Usage: scripts/bench_quick.sh [label] [layout...]   (furball and spread by default; or transit, battle, typical (M4-T07))
# Environment: QUICK_NS ("10 15 20 25 30 40 50 75 100 150 200 300 400 500"), QUICK_MIN_FPS (30), QUICK_SECONDS (6),
#              QUICK_WARMUP (2), QUICK_SEED (1), QUICK_BUDGET_S (540), BENCH_CPUS (0-11; empty for no pinning), GODOT_BIN,
#              QUICK_OPTIONS (more bench options, e.g. "arrive=placed"; battle and typical arrive through jump points by default).
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
MIN_FPS="${QUICK_MIN_FPS:-30}"
SECONDS_MEASURED="${QUICK_SECONDS:-6}"
WARMUP="${QUICK_WARMUP:-2}"
SEED="${QUICK_SEED:-1}"
EXTRA="${QUICK_OPTIONS:-}"
BUDGET_S="${QUICK_BUDGET_S:-540}"
CPUS="${BENCH_CPUS-0-11}"
OUT="reports/perf/${LABEL}"
REPORT="${OUT}/quick.md"

if [[ ! -x "${GODOT}" ]]; then
    echo "bench_quick.sh: Godot not found at ${GODOT}; run scripts/setup_godot.sh (or set GODOT_BIN)." >&2
    exit 1
fi
for layout in "${LAYOUTS[@]}"; do
    case "${layout}" in furball|spread|transit|battle|typical) ;; *) echo "bench_quick.sh: unknown layout '${layout}'" >&2; exit 2 ;; esac
done
mkdir -p "${OUT}/runs"
touch reports/.gdignore  # or the next --import takes the reports for game files
PIN=()
if [[ -n "${CPUS}" ]] && command -v taskset > /dev/null; then
    PIN=(taskset -c "${CPUS}")
fi
COMMIT="$(git rev-parse --short HEAD 2> /dev/null || echo unknown)"

# read_run <summary.json>: three lines for the shell: the table row; FPS times ten and 1 if the budget held; why it failed.
read_run() {
    python3 -I - "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
if d.get("missing"):
    print("| %d | run died | | | | | | | | fail |" % d["n"]); print("0 0"); print("the run died without a report"); sys.exit()
s, ms = d["stages"], lambda us: "%.2f" % (us / 1000.0)
mean = lambda k: s.get(k, {}).get("mean_us", 0.0)
ok = d["verdict"]["pass"]
fps = d["ticks"] / d["wall_s"] if d.get("wall_s", 0) > 0 else 0.0
print("| %d | %.1f | %s | %s | %s | %s | %s | %s | %s | %s |" % (d["n"], fps, ms(s["tick"]["median_us"]), ms(s["tick"]["p99_us"]),
      ms(d["rebase"]["tick_max_us"]) if d["rebase"]["count"] else "none", ms(mean("targeting")), ms(mean("ai")),
      ms(mean("resolvers")), ms(mean("standins")), "pass" if ok else "fail" + (" (cut short)" if d.get("aborted") else "")))
print("%d %d" % (round(fps * 10), 1 if ok else 0))
print("; ".join(d["verdict"]["failures"]) or "none")
EOF
}

START=$(date +%s)
{
    echo "# Quick check ${LABEL}: ${LAYOUTS[*]}, seed ${SEED}, ${WARMUP} s + ${SECONDS_MEASURED} s per count, floor ${MIN_FPS} FPS${EXTRA:+, options: ${EXTRA}}"
    echo
    echo "Commit ${COMMIT}, $(date -Iseconds), load $(cut -d' ' -f1-3 /proc/loadavg). One short run per count: indicative, not the verdict."
    echo "FPS is simulation ticks per wall-clock second (60 while it keeps real time). The budget is the milestone's: tick median"
    echo "8 ms, p99 12 ms, no rebase tick over 16.7 ms, real time kept."
} | tee "${REPORT}"

RESULTS=()  # one block of result lines per layout, printed together at the end

# ramp <layout> <seconds it may use>: one table, from the smallest count up, then the layout's result.
ramp() {
    local layout="$1" budget="$2" t_start last_wall=0 stop="" failed_at=""
    local -a passed=() over=()
    t_start=$(date +%s)
    {
        echo
        echo "## ${layout}"
        echo
        echo "| N | FPS | tick median ms | p99 ms | worst rebase tick ms | targeting ms | ai ms | resolvers ms | stand-ins ms | budget |"
        echo "|---|---|---|---|---|---|---|---|---|---|"
    } | tee -a "${REPORT}"
    for n in "${NS[@]}"; do
        local elapsed=$(( $(date +%s) - t_start ))
        # The next count costs at least what the last one did; skip it if that would break the budget.
        if (( last_wall > 0 && elapsed + 2 * last_wall > budget )); then
            stop="time budget (${budget} s) ran out before ${n} ships"
            break
        fi
        local name="${layout}_${n}_s${SEED}" t0 lines fps10 ok why fps
        rm -rf "${OUT:?}/runs/${name}"
        t0=$(date +%s)
        "${PIN[@]}" timeout $(( budget - elapsed + 30 )) "${GODOT}" --headless --path . -- --console-strict \
            --console-exec="scenario combat_sandbox; wait 30; bench ${layout} ${n} ${SECONDS_MEASURED} warmup=${WARMUP} seed=${SEED} ${EXTRA} label=${LABEL}/runs/${name}; quit" \
            > "${OUT}/runs/${name}.log" 2>&1 || true
        last_wall=$(( $(date +%s) - t0 ))
        if [[ ! -f "${OUT}/runs/${name}/summary.json" ]]; then
            mkdir -p "${OUT}/runs/${name}"
            printf '{"n": %d, "missing": true}\n' "${n}" > "${OUT}/runs/${name}/summary.json"
        fi
        mapfile -t lines < <(read_run "${OUT}/runs/${name}/summary.json")
        if (( ${#lines[@]} < 3 )); then
            lines=("| ${n} | report unreadable | | | | | | | | fail |" "0 0" "its report could not be read")
        fi
        echo "${lines[0]}" | tee -a "${REPORT}"
        read -r fps10 ok <<< "${lines[1]}"
        why="${lines[2]}"
        fps="$(( fps10 / 10 )).$(( fps10 % 10 ))"
        if (( fps10 < MIN_FPS * 10 )); then
            failed_at="${n} ships at ${fps} FPS (${why})"
            stop="under ${MIN_FPS} FPS at ${n} ships"
            break
        fi
        if (( ok == 1 )); then
            passed+=("${n}")
        else
            over+=("${n} (${fps} FPS: ${why})")
        fi
    done
    [[ -z "${stop}" ]] && stop="every count ran"
    local list="none"
    if (( ${#passed[@]} > 0 )); then
        list="$(printf '%s, ' "${passed[@]}")"
        list="${list%, } ships"
    fi
    local -a result=("**${layout}**: stopped: ${stop}; took $(( $(date +%s) - t_start )) s.")
    result+=("- Passed the budget: ${list}")
    if (( ${#over[@]} > 0 )); then
        result+=("- Over budget, still ${MIN_FPS} FPS or more:")
        local o
        for o in "${over[@]}"; do
            result+=("  - ${o}")
        done
    else
        result+=("- Over budget, still ${MIN_FPS} FPS or more: none")
    fi
    result+=("- Failed at: ${failed_at:-no count fell under ${MIN_FPS} FPS}")
    { echo; printf '%s\n' "${result[@]}"; } | tee -a "${REPORT}"
    local best="no" fell="no count fell under ${MIN_FPS} FPS"
    (( ${#passed[@]} > 0 )) && best="${passed[${#passed[@]}-1]}"
    [[ -n "${failed_at}" ]] && fell="failed at ${failed_at%% (*}"
    RESULTS+=("- ${layout}: budget held up to ${best} ships; ${fell}.")
}

left=${#LAYOUTS[@]}
for layout in "${LAYOUTS[@]}"; do
    # Each layout gets an even share of what is left, so an early one that ends quickly leaves more for the rest.
    ramp "${layout}" $(( (BUDGET_S - ($(date +%s) - START)) / left ))
    left=$(( left - 1 ))
done
{
    echo
    echo "## Result"
    echo
    printf '%s\n' "${RESULTS[@]}"
    echo
    echo "Total $(( $(date +%s) - START )) s. Report: ${REPORT}"
} | tee -a "${REPORT}"
