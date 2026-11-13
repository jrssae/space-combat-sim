#!/usr/bin/env bash
# One lock for every Godot run on this machine, so parallel agents overlap where it is safe and queue where it is not.
# Readers (tests, compile check, smokes, renders) share the lock; writers (the import into .godot/, asset builds into
# assets/generated/, the native build) hold it alone. A turnstile gate keeps a waiting writer from being starved by new readers.
# Fixed order, never reversed: gate, Godot lock, GPU lock (/tmp/gpu.lock), bench lock.
#
# Usage: scripts/godot_lock.sh <read|write> [--gpu] [--bench] [--timeout SECONDS] -- <command...>
#        scripts/godot_lock.sh status
#   read     shared; any number of readers at once
#   write    exclusive; waits for readers to finish and blocks new ones
#   --gpu    also take the GPU lock (anything that opens a window), after the Godot lock
#   --bench  also take the bench lock (timing runs), after the GPU lock
#   --timeout  give up waiting after this many seconds (exit 75); the holders are named every 30 s while waiting
#   status   who holds and who waits right now, and the last 20 lines of the log
# The command's exit code passes through. SCS_NO_LOCK=1 skips locking (CI). Hold a lock per command, never around a long script.
# SCS_LOCK_LABEL=<task id> names the run in the waiting messages, in status and in reports/locks.log (one line per finished run).
# Environment: SCS_GODOT_LOCK, SCS_GPU_LOCK, SCS_BENCH_LOCK, SCS_LOCK_LOG override the paths.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
GODOT_LOCK="${SCS_GODOT_LOCK:-/tmp/scs-godot.lock}"
GATE_LOCK="${GODOT_LOCK}.gate"
GPU_LOCK="${SCS_GPU_LOCK:-/tmp/gpu.lock}"
BENCH_LOCK="${SCS_BENCH_LOCK:-/tmp/scs-bench.lock}"
HOLDERS_DIR="${GODOT_LOCK%.lock}.holders"
LOCK_LOG="${SCS_LOCK_LOG:-${ROOT}/reports/locks.log}"
REPORT_EVERY=30

usage() {
    echo "usage: scripts/godot_lock.sh <read|write> [--gpu] [--bench] [--timeout SECONDS] -- <command...> | status" >&2
    exit 2
}

# Holder records: one small file per running wrapper (label, mode, command, state, times), so waits can name who is in the way.
# Records of dead wrappers (killed without cleanup) are removed whenever the records are listed.
record_alive() {
    local pid="$1"
    [[ -r "/proc/${pid}/cmdline" ]] && tr '\0' ' ' < "/proc/${pid}/cmdline" 2> /dev/null | grep -q "godot_lock.sh"
}

# list_records: prints "pid|state|label|mode|since|cmd" per live record, dropping the stale ones.
list_records() {
    local f pid state label mode since cmd k v
    for f in "${HOLDERS_DIR}"/*; do
        [[ -f "${f}" ]] || continue
        pid="$(basename "${f}")"
        if ! record_alive "${pid}"; then rm -f "${f}"; continue; fi
        state="" label="" mode="" since="" cmd=""
        while IFS='=' read -r k v; do
            case "${k}" in
                state) state="${v}" ;; label) label="${v}" ;; mode) mode="${v}" ;; since) since="${v}" ;; cmd) cmd="${v}" ;;
            esac
        done < "${f}"
        echo "${pid}|${state}|${label}|${mode}|${since}|${cmd}"
    done
}

# print_holders: the live records as text, holders first; falls back to lslocks for holders that are not this wrapper.
print_holders() {
    local now rec pid state label mode since cmd shown=0 pids=" "
    now="$(date +%s)"
    for state in holding waiting; do
        while IFS='|' read -r pid st label mode since cmd; do
            [[ "${st}" == "${state}" ]] || continue
            pids+="${pid} "
            if [[ "${state}" == "holding" ]]; then
                echo "    holds ${mode} for $(( now - since )) s: [${label}] ${cmd}"
            else
                echo "    queued ${mode} for $(( now - since )) s: [${label}] ${cmd}"
            fi
            shown=1
        done < <(list_records)
    done
    local lpid line
    for p in "${GODOT_LOCK}" "${GATE_LOCK}" "${GPU_LOCK}" "${BENCH_LOCK}"; do
        while read -r lpid; do
            [[ "${pids}" == *" ${lpid} "* ]] && continue
            pids+="${lpid} "
            line="$(tr '\0' ' ' < "/proc/${lpid}/cmdline" 2> /dev/null | cut -c1-200)"
            [[ "${line}" == "flock "* ]] && continue  # a wrapper's own waiting flock, already listed through its record
            echo "    other holder of ${p}: pid ${lpid}: ${line:-?}"
            shown=1
        done < <(lslocks -n -r -o PID,PATH 2> /dev/null | awk -v p="${p}" '$2 == p {print $1}')
    done
    (( shown == 1 )) || echo "    (nobody found)"
}

if [[ "${1:-}" == "status" ]]; then
    echo "Godot lock ${GODOT_LOCK}, GPU lock ${GPU_LOCK}, bench lock ${BENCH_LOCK}"
    print_holders | sed 's/^    /  /'
    echo "last 20 lines of ${LOCK_LOG}:"
    if [[ -f "${LOCK_LOG}" ]]; then tail -n 20 "${LOCK_LOG}" | sed 's/^/  /'; else echo "  (no log yet)"; fi
    exit 0
fi

(( $# >= 1 )) || usage
mode="$1"
shift
[[ "${mode}" == "read" || "${mode}" == "write" ]] || usage
want_gpu=0
want_bench=0
timeout_s=0
while (( $# > 0 )); do
    case "$1" in
        --gpu) want_gpu=1 ;;
        --bench) want_bench=1 ;;
        --timeout) shift; timeout_s="${1:?--timeout needs seconds}" ;;
        --) shift; break ;;
        *) usage ;;
    esac
    shift
done
(( $# >= 1 )) || usage

if [[ "${SCS_NO_LOCK:-0}" == "1" ]]; then
    exec "$@"
fi

# A command that runs inside a lock this script already holds must not ask again: a read cannot become a write.
if [[ "${SCS_LOCK_MODE:-}" == "read" && "${mode}" == "write" ]]; then
    echo "godot_lock.sh: a write lock was asked for inside a held read lock; that would deadlock. Take the write lock outside." >&2
    exit 3
fi
have_godot=0
[[ -n "${SCS_LOCK_MODE:-}" ]] && have_godot=1
have_gpu="${SCS_LOCK_GPU:-0}"
have_bench="${SCS_LOCK_BENCH:-0}"
if [[ "${have_godot}" == "0" && ( "${have_gpu}" == "1" || "${have_bench}" == "1" ) ]]; then
    echo "godot_lock.sh: the GPU or bench lock is held without the Godot lock; the order is Godot, then GPU." >&2
    exit 3
fi

label="${SCS_LOCK_LABEL:-?}"
mode_text="${mode}"
(( want_gpu == 1 )) && mode_text+="+gpu"
(( want_bench == 1 )) && mode_text+="+bench"
cmd_text="$(printf '%s ' "$@" | tr '\n\t' '  ')"
cmd_text="${cmd_text% }"
started="$(date +%s)"
acquired=""
record="${HOLDERS_DIR}/$$"

# write_record <state> <since>: replaces this wrapper's record in one rename, so a reader never sees half of it.
write_record() {
    mkdir -p "${HOLDERS_DIR}" 2> /dev/null || return 0
    printf 'state=%s\nlabel=%s\nmode=%s\nsince=%s\ncmd=%s\n' "$1" "${label}" "${mode_text}" "$2" "${cmd_text:0:200}" \
        > "${HOLDERS_DIR}/.$$.tmp" 2> /dev/null && mv -f "${HOLDERS_DIR}/.$$.tmp" "${record}" 2> /dev/null
    return 0
}

# finish: one log line per run (the line is appended under the log's own lock so parallel runs do not interleave), then the record goes.
finish() {
    local rc=$? now wait hold stamp
    trap - EXIT
    now="$(date +%s)"
    wait=$(( ${acquired:-${now}} - started ))
    hold=$(( ${acquired:+${now} - ${acquired}} + 0 ))
    stamp="$(date -Iseconds)"
    mkdir -p "$(dirname "${LOCK_LOG}")" 2> /dev/null
    { flock 9; printf '%s label=%s mode=%s wait=%ss hold=%ss exit=%s cmd=%s\n' "${stamp}" "${label}" "${mode_text}" "${wait}" "${hold}" "${rc}" "${cmd_text:0:160}" >&9; } 9>> "${LOCK_LOG}" 2> /dev/null
    rm -f "${record}" "${HOLDERS_DIR}/.$$.tmp"
    exit "${rc}"
}

# acquire <fd> <flock mode> <lock file> <label>: waits for the lock, naming the holders every REPORT_EVERY seconds.
acquire() {
    local fd="$1" kind="$2" path="$3" what="$4" waited=0 step
    while true; do
        step="${REPORT_EVERY}"
        if (( timeout_s > 0 )); then
            (( waited < timeout_s )) || break
            (( timeout_s - waited < step )) && step=$(( timeout_s - waited ))
        fi
        flock -w "${step}" "${kind}" "${fd}" && return 0
        waited=$(( waited + step ))
        echo "godot_lock.sh: [${label}] waiting ${waited} s for the ${what} lock (${path}); in the way:" >&2
        print_holders >&2
    done
    echo "godot_lock.sh: [${label}] gave up after ${timeout_s} s waiting for the ${what} lock." >&2
    exit 75
}

trap finish EXIT
trap 'exit 143' TERM
trap 'exit 130' INT HUP
write_record waiting "${started}"

if (( have_godot == 0 )); then
    exec {gate_fd}> "${GATE_LOCK}" || exit 1
    exec {main_fd}> "${GODOT_LOCK}" || exit 1
    # Everyone passes the gate; a writer keeps it until it has the lock, a reader lets go as soon as it has a share.
    acquire "${gate_fd}" -x "${GATE_LOCK}" "queue"
    if [[ "${mode}" == "write" ]]; then
        acquire "${main_fd}" -x "${GODOT_LOCK}" "Godot (write)"
    else
        acquire "${main_fd}" -s "${GODOT_LOCK}" "Godot (read)"
        flock -u "${gate_fd}"
        exec {gate_fd}>&-
    fi
fi
if (( want_gpu == 1 && have_gpu == 0 )); then
    exec {gpu_fd}> "${GPU_LOCK}" || exit 1
    acquire "${gpu_fd}" -x "${GPU_LOCK}" "GPU"
fi
if (( want_bench == 1 && have_bench == 0 )); then
    exec {bench_fd}> "${BENCH_LOCK}" || exit 1
    acquire "${bench_fd}" -x "${BENCH_LOCK}" "bench"
fi
acquired="$(date +%s)"
write_record holding "${acquired}"

# Not exec: this shell keeps the locks until the command is done, and the command passes its status back.
export SCS_LOCK_MODE="${SCS_LOCK_MODE:-${mode}}"
(( want_gpu == 1 )) && export SCS_LOCK_GPU=1
(( want_bench == 1 )) && export SCS_LOCK_BENCH=1
"$@"
exit $?
