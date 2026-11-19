#!/usr/bin/env bash
# Export smoke test (M8-T15, AC10): runs the exported binary headless, plays a scenario through the loading screen, waits some
# ticks and quits. Fails on a non-zero exit or any "ERROR:" line. Usage: release_smoke.sh [binary]
# The tutorial's opening replaces free_flight here once the tutorial is merged (SMOKE_SCENARIO overrides).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:-${ROOT}/build/release/space-combat-sim.x86_64}"
SCENARIO="${SMOKE_SCENARIO:-free_flight}"
[[ -x "${BIN}" ]] || { echo "release_smoke.sh: no binary at ${BIN}; run scripts/build_release.sh" >&2; exit 1; }
mkdir -p "${ROOT}/reports/tmp"
log="$(mktemp "${ROOT}/reports/tmp/release_smoke.XXXXXX.log")"
set +e
timeout 300 "${BIN}" --headless -- --console-strict \
    --console-exec="wait 60; play ${SCENARIO}; wait 600; state ship; quit" > "${log}" 2>&1
code=$?
set -e
if (( code != 0 )) || grep -q "ERROR:" "${log}"; then
    echo "release_smoke.sh: FAILED (exit ${code}); log ${log}" >&2
    grep -n "ERROR:" "${log}" | head -10 >&2 || true
    tail -5 "${log}" >&2
    exit 1
fi
echo "release_smoke.sh: ok (${SCENARIO}, exit 0, no ERROR lines)"
rm -f "${log}"
