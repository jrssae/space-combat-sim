#!/usr/bin/env bash
# Runs every automated check that works without a GPU: Python generator tests, a headless Godot import that
# must be free of script errors, and the GUT suites. Exits non-zero on any failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
REPORTS="${ROOT}/reports"
mkdir -p "${REPORTS}"

if [[ ! -x "${GODOT}" ]]; then
    echo "Godot not found at ${GODOT}; run scripts/setup_godot.sh (or set GODOT_BIN)." >&2
    exit 1
fi

if [[ -d tools/procgen/tests ]]; then
    echo "== Python tests"
    python3 -m unittest discover -s tools/procgen/tests -t . -v
fi

echo "== Godot import"
"${GODOT}" --headless --path . --import 2>&1 | tee "${REPORTS}/import.log"
if grep -E "SCRIPT ERROR|Parse Error|Failed to load script" "${REPORTS}/import.log"; then
    echo "Import reported script errors (see reports/import.log)." >&2
    exit 1
fi

echo "== Compile check"
timeout 300 "${GODOT}" --headless --path . -s res://scripts/check_scripts.gd 2>&1 | tee "${REPORTS}/check_scripts.log"
if grep -E "SCRIPT ERROR|Parse Error" "${REPORTS}/check_scripts.log"; then
    echo "Scripts failed to compile (see reports/check_scripts.log)." >&2
    exit 1
fi

echo "== GUT"
"${GODOT}" --headless --path . -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=res://reports/gut.xml
