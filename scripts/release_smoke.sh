#!/usr/bin/env bash
# Export smoke test (M8-T15, AC10): runs the exported binary headless, plays a scenario through the loading screen, waits some
# ticks and quits. Fails on a non-zero exit, any "ERROR:" line, or a log that never shows the scenario loading. Usage: release_smoke.sh [binary]
# It plays the tutorial's opening (the two-ship launch from the Cobra bays: 600 ticks end in or just after it), the first
# thing a new player sees; SMOKE_SCENARIO overrides (free_flight was the default until the tutorial was merged).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/lib_platform.sh"
BIN="${1:-${ROOT}/build/release/space-combat-sim.x86_64}"
SCENARIO="${SMOKE_SCENARIO:-tutorial}"
[[ -x "${BIN}" ]] || { echo "release_smoke.sh: no binary at ${BIN}; run scripts/build_release.sh" >&2; exit 1; }
mkdir -p "${ROOT}/reports/tmp"
log="$(mktemp "${ROOT}/reports/tmp/release_smoke.XXXXXX.log")"
set +e
timeout 300 "${BIN}" --headless -- --console-strict \
    --console-exec="wait 60; play ${SCENARIO}; wait 600; state ship; quit" > "${log}" 2>&1
code=$?
# timeout stops only the console wrapper on Windows; the game it started keeps running.
if (( code == 124 )) && is_windows; then taskkill //F //IM space-combat-sim.exe > /dev/null 2>&1 || true; fi
set -e
if (( code != 0 )) || grep -q "ERROR:" "${log}" || ! grep -q "loading ${SCENARIO} " "${log}"; then
    echo "release_smoke.sh: FAILED (exit ${code}); log ${log}" >&2
    grep -n "ERROR:" "${log}" | head -10 >&2 || true
    tail -5 "${log}" >&2
    exit 1
fi
echo "release_smoke.sh: ok (${SCENARIO}, exit 0, no ERROR lines)"
rm -f "${log}"
