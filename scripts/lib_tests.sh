#!/usr/bin/env bash
# Helpers shared by the tiers of scripts/run_tests.sh (sourced, never run): paths, logging, the compile check, the Rust tests
# and the two console smokes that the quick tier shares with the standard one.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
REPORTS="${ROOT}/reports"
SCRIPT_ERRORS="SCRIPT ERROR|Parse Error|Failed to load script"

fail() {
    echo "run_tests.sh: $*" >&2
    exit 1
}

# run_logged <log file> <command...>: runs the command, mirrors its output into the log, returns its exit code.
run_logged() {
    local log="$1"
    shift
    local status=0
    "$@" 2>&1 | tee "${log}" || status=$?
    return "${status}"
}

require_godot() {
    if [[ ! -x "${GODOT}" ]]; then
        fail "Godot not found at ${GODOT}; run scripts/setup_godot.sh (or set GODOT_BIN)."
    fi
}

# The generator's tests need NumPy, which the project's virtualenv has and the system Python may not.
python_bin() {
    if [[ -x "${ROOT}/.venv/bin/python" ]]; then
        echo "${ROOT}/.venv/bin/python"
    else
        echo python3
    fi
}

# The library is required, so a failed build stops the run.
build_native_or_fail() {
    echo "== Native library"
    scripts/build_native.sh || fail "The native library failed to build (see the output above)."
    [[ -f bin/libscs_native.so ]] || fail "No native library at bin/libscs_native.so after the build."
}

# GUT silently skips a test file that does not parse, so compile everything explicitly. <log> names where the output goes.
compile_check() {
    echo "== Compile check"
    run_logged "$1" timeout 300 "${GODOT}" --headless --path . -s res://scripts/check_scripts.gd \
        || fail "Scripts failed to compile (see $1)."
    if grep -E "${SCRIPT_ERRORS}" "$1"; then
        fail "Scripts failed to compile (see $1)."
    fi
}

# The engine-free kernels' own tests; no run called them before M6-T17. <log> names where the output goes.
rust_tests() {
    echo "== Rust kernel tests"
    # rustup's default install may be missing from a non-login shell's PATH (build_native.sh does the same).
    if ! command -v cargo > /dev/null && [[ -x "${HOME}/.cargo/bin/cargo" ]]; then
        export PATH="${HOME}/.cargo/bin:${PATH}"
    fi
    if ! command -v cargo > /dev/null; then
        echo "run_tests.sh: cargo not found, skipping the Rust kernel tests." >&2
        return 0
    fi
    export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${ROOT}/.tools/native-target}"
    (cd native && run_logged "$1" cargo test --release --lib) || fail "The Rust kernel tests failed (see $1)."
}

# Debug console smoke runs (architecture §6.4, AC21): a live headless build driven by --console-exec must print the
# expected [console] lines and exit with the requested code. console_host.tscn is an empty scene, so only the
# console's own providers (settings, debug, time) exist. `set` must not touch user://settings.cfg (only `save` does).
CONSOLE_HOST="res://tests/fixtures/console_host.tscn"
SETTINGS_CFG="${XDG_DATA_HOME:-${HOME}/.local/share}/godot/app_userdata/space-combat-sim/settings.cfg"
smoke_status=0

settings_fingerprint() {
    if [[ -f "${SETTINGS_CFG}" ]]; then
        sha256sum "${SETTINGS_CFG}" | cut -d' ' -f1
    else
        echo "absent"
    fi
}

# console_run <log> <expected exit code> <user args...>: runs the host scene with the args after --.
console_run() {
    local log="$1" expected="$2"
    shift 2
    local status=0
    timeout 120 "${GODOT}" --headless --path . "${CONSOLE_HOST}" -- "$@" > "${log}" 2>&1 || status=$?
    cat "${log}"
    if (( status != expected )); then
        echo "run_tests.sh: console smoke run exited ${status}, expected ${expected} (see ${log})." >&2
        return 1
    fi
    if grep -E "${SCRIPT_ERRORS}" "${log}"; then
        echo "run_tests.sh: console smoke run reported script errors (see ${log})." >&2
        return 1
    fi
}

# expect_line <log> <exact line>; expect_text <log> <substring>; reject_text <log> <substring>
expect_line() {
    grep -qxF -- "$2" "$1" || { echo "run_tests.sh: missing line in $1: $2" >&2; return 1; }
}
expect_text() {
    grep -qF -- "$2" "$1" || { echo "run_tests.sh: missing text in $1: $2" >&2; return 1; }
}
# The providers line lists every registered state provider. New subsystems add providers, so the check is that the ones named
# here are all present, not that the list is exactly this one (an exact list failed CI every time a task added a provider).
expect_providers() {
    local line
    line="$(grep -m1 -F -- "[console] providers: " "$1" || true)"
    if [[ -z "${line}" ]]; then
        echo "run_tests.sh: missing providers line in $1" >&2
        return 1
    fi
    local have=",${line#*providers: },"
    have="${have// /}"
    local missing=0 name
    for name in ${2//,/ }; do
        if [[ "${have}" != *",${name},"* ]]; then
            echo "run_tests.sh: provider ${name} missing in $1" >&2
            missing=1
        fi
    done
    return "${missing}"
}
reject_text() {
    if grep -qF -- "$2" "$1"; then
        echo "run_tests.sh: unexpected text in $1: $2" >&2
        return 1
    fi
}

# main_run <log> <timeout s> <expected exit code> <label> <godot args...>: one headless run of the project (the real main scene
# unless a scene is named) for a smoke block; returns 1 when the exit code is not the expected one.
main_run() {
    local log="$1" limit="$2" expected="$3" label="$4"
    shift 4
    local status=0
    timeout "${limit}" "${GODOT}" --headless --path . "$@" > "${log}" 2>&1 || status=$?
    cat "${log}"
    if (( status != expected )); then
        echo "run_tests.sh: ${label} smoke run exited ${status}, expected ${expected} (see ${log})." >&2
        return 1
    fi
}

# smoke_console_host <log>: a strict script that succeeds on the empty console host; returns 1 on any failed check.
smoke_console_host() {
    local smoke_status=0 log="$1"
settings_before="$(settings_fingerprint)"
console_run "${log}" 0 --console-strict \
    --console-exec="help; set settings.stick_deadzone 0.2; get settings.stick_deadzone; god on; get debug.invulnerable; quit 0" \
    || smoke_status=1
expect_line "${log}" "[console] > help" || smoke_status=1
expect_text "${log}" "[console]   set <path> <value>" || smoke_status=1
expect_text "${log}" "[console]   quit [code]" || smoke_status=1
expect_line "${log}" "[console] > set settings.stick_deadzone 0.2" || smoke_status=1
expect_line "${log}" "[console] > get settings.stick_deadzone" || smoke_status=1
expect_line "${log}" "[console] settings.stick_deadzone = 0.20" || smoke_status=1
expect_line "${log}" "[console] > god on" || smoke_status=1
expect_line "${log}" "[console] debug.invulnerable = true" || smoke_status=1
expect_line "${log}" "[console] > quit 0" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
if [[ "$(settings_fingerprint)" != "${settings_before}" ]]; then
    echo "run_tests.sh: 'set' changed ${SETTINGS_CFG}; only 'save' may write it." >&2
    smoke_status=1
fi
    return "${smoke_status}"
}

# smoke_main_scene <log>: the real main scene boots headless, registers its providers and answers through the console.
smoke_main_scene() {
    local smoke_status=0 log="$1"
# M1-T15 / AC10: the game itself (project main scene) must boot headless, register every subsystem's provider and
# answer through the console without engine errors.
main_status=0
timeout 180 "${GODOT}" --headless --path . -- --console-strict \
    --console-exec="wait 30; state; state ship; get render.renderer; quit" > "${log}" 2>&1 || main_status=$?
cat "${log}"
if (( main_status != 0 )); then
    echo "run_tests.sh: main scene smoke run exited ${main_status}, expected 0 (see ${log})." >&2
    smoke_status=1
fi
if grep -E "${SCRIPT_ERRORS}" "${log}"; then
    echo "run_tests.sh: main scene smoke run reported script errors (see ${log})." >&2
    smoke_status=1
fi
expect_providers "${log}" "ai, allies, audio, camera, combat, controls, debris, debug, factions, flight, fx, game, hud, hull, input, lights, livery, perf, post, raiders, ram, render, screens, settings, ship, sky, targeting, time, waves, weapons, wing, world" \
    || smoke_status=1
expect_line "${log}" "[console] ship.assist_on = true" || smoke_status=1
expect_line "${log}" "[console] render.renderer = headless" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1
    return "${smoke_status}"
}
