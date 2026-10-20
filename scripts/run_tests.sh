#!/usr/bin/env bash
# Runs every automated check that works without a GPU: Python generator tests, a headless Godot import that
# must be free of script errors, a compile check of every project script, the GUT suites, and two debug-console
# smoke runs that drive a live headless build through --console-exec.
# Exits non-zero on any failure. Logs and the GUT JUnit XML land in reports/ (gitignored; CI uploads it).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
REPORTS="${ROOT}/reports"
SCRIPT_ERRORS="SCRIPT ERROR|Parse Error|Failed to load script"

mkdir -p "${REPORTS}"
# reports/ must only describe this run.
rm -f "${REPORTS}"/*.log "${REPORTS}/gut.xml"

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

if [[ ! -x "${GODOT}" ]]; then
    fail "Godot not found at ${GODOT}; run scripts/setup_godot.sh (or set GODOT_BIN)."
fi

if [[ -d tools/procgen/tests ]]; then
    echo "== Python tests"
    python3 -m unittest discover -s tools/procgen/tests -t . -v
fi

# --import imports resources but does not compile scripts, hence the separate compile check below.
echo "== Godot import"
run_logged "${REPORTS}/import.log" timeout 600 "${GODOT}" --headless --path . --import \
    || fail "Godot import failed (see reports/import.log)."
if grep -E "${SCRIPT_ERRORS}" "${REPORTS}/import.log"; then
    fail "Import reported script errors (see reports/import.log)."
fi

# GUT silently skips a test file that does not parse, so compile everything explicitly.
echo "== Compile check"
run_logged "${REPORTS}/check_scripts.log" timeout 300 "${GODOT}" --headless --path . -s res://scripts/check_scripts.gd \
    || fail "Scripts failed to compile (see reports/check_scripts.log)."
if grep -E "${SCRIPT_ERRORS}" "${REPORTS}/check_scripts.log"; then
    fail "Scripts failed to compile (see reports/check_scripts.log)."
fi

echo "== GUT"
gut_status=0
run_logged "${REPORTS}/gut.log" timeout 600 "${GODOT}" --headless --path . -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=reports/gut.xml \
    || gut_status=$?
if (( gut_status != 0 )); then
    echo "run_tests.sh: GUT failed with exit code ${gut_status} (see reports/gut.log)." >&2
fi

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
reject_text() {
    if grep -qF -- "$2" "$1"; then
        echo "run_tests.sh: unexpected text in $1: $2" >&2
        return 1
    fi
}

echo "== Console smoke run: strict script that succeeds"
log="${REPORTS}/console_smoke.log"
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

echo "== Console smoke run: strict script with an out-of-range value must exit 1"
log="${REPORTS}/console_strict.log"
console_run "${log}" 1 --console-strict --console-exec="set settings.stick_deadzone 0.9; quit 0" || smoke_status=1
expect_line "${log}" "[console] error: settings.stick_deadzone must be in 0.0..0.3, got 0.9" || smoke_status=1
reject_text "${log}" "[console] > quit 0" || smoke_status=1

echo "== Console smoke run: control profiles"
# M2-T11 / AC13: bind is session-only, `controls save` writes user://controls/<name>.cfg, `controls use default`
# drops the unsaved bind, and only `save` may touch settings.cfg. The scratch profile is deleted at the end.
log="${REPORTS}/console_controls.log"
settings_before="$(settings_fingerprint)"
console_run "${log}" 0 --console-strict \
    --console-exec="controls save smoke_test; bind fire key:K; controls show fire; controls use default; controls show fire; controls use m1_classic; controls show yaw_left; controls use default; controls delete smoke_test; quit 0" \
    || smoke_status=1
expect_line "${log}" "[console] fire: pad:button:0 key:Space mouse:1 key:K (deadzone 0.50)" || smoke_status=1
expect_line "${log}" "[console] fire: pad:button:0 key:Space mouse:1 (deadzone 0.50)" || smoke_status=1
expect_line "${log}" "[console] yaw_left: pad:axis:2- key:J (deadzone 0.15)" || smoke_status=1
expect_line "${log}" "[console] deleted control profile 'smoke_test'" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
if [[ "$(settings_fingerprint)" != "${settings_before}" ]]; then
    echo "run_tests.sh: control profile commands changed ${SETTINGS_CFG}; only 'save' may write it." >&2
    smoke_status=1
fi

echo "== Console smoke run: binding the console key must exit 1"
log="${REPORTS}/console_controls_strict.log"
console_run "${log}" 1 --console-strict --console-exec="bind fire key:QuoteLeft; quit 0" || smoke_status=1
expect_text "${log}" "[console] error: bind fire: key:QuoteLeft is the console key" || smoke_status=1
reject_text "${log}" "[console] > quit 0" || smoke_status=1

echo "== Console smoke run: the real main scene"
# M1-T15 / AC10: the game itself (project main scene) must boot headless, register every subsystem's provider and
# answer through the console without engine errors.
log="${REPORTS}/console_main.log"
main_status=0
timeout 180 "${GODOT}" --headless --path . -- --console-strict \
    --console-exec="wait 30; state; state ship; get render.splat_backend; quit" > "${log}" 2>&1 || main_status=$?
cat "${log}"
if (( main_status != 0 )); then
    echo "run_tests.sh: main scene smoke run exited ${main_status}, expected 0 (see ${log})." >&2
    smoke_status=1
fi
if grep -E "${SCRIPT_ERRORS}" "${log}"; then
    echo "run_tests.sh: main scene smoke run reported script errors (see ${log})." >&2
    smoke_status=1
fi
expect_line "${log}" "[console] providers: camera, combat, controls, debug, hull, input, raiders, render, settings, ship, targeting, time, weapons, world" \
    || smoke_status=1
expect_line "${log}" "[console] ship.assist_on = true" || smoke_status=1
expect_line "${log}" "[console] render.splat_backend = headless" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: god mode and damage on the real main scene"
# M2-T03 / AC8: with god on the player's hull does not change; with god off it does.
log="${REPORTS}/console_damage.log"
damage_status=0
timeout 180 "${GODOT}" --headless --path . -- --console-strict \
    --console-exec="wait 30; god on; damage 50 player; get hull.hp; god off; damage 50 player; get hull.hp; quit" \
    > "${log}" 2>&1 || damage_status=$?
cat "${log}"
if (( damage_status != 0 )); then
    echo "run_tests.sh: damage smoke run exited ${damage_status}, expected 0 (see ${log})." >&2
    smoke_status=1
fi
expect_line "${log}" "[console] hull.hp = 300.00" || smoke_status=1
expect_line "${log}" "[console] hull.hp = 250.00" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1

if (( smoke_status != 0 )); then
    echo "run_tests.sh: console smoke runs failed (see reports/console_*.log)." >&2
fi
if (( gut_status != 0 )); then
    exit "${gut_status}"
fi
exit "${smoke_status}"
