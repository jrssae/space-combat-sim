#!/usr/bin/env bash
# Runs every automated check that works without a GPU: Python generator tests, a headless Godot import that
# must be free of script errors, a compile check of every project script, and the GUT suites.
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
exit "${gut_status}"
