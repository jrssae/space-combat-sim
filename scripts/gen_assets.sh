#!/usr/bin/env bash
# Generate every procedural asset into assets/generated/ (gitignored): python3 -m tools.procgen build all, several at a time
# (M4-T30d: the textured hulls take about 110 s one after another). Jobs: PROCGEN_JOBS, else the machine's cores capped at four
# (memory: each textured hull's bake holds up to about 3.5 GB; the station, near 9 GB, is built alone after the others,
# `BUILD_ALONE` in tools/procgen/assets). Each asset's output is the same either way.
# Needs Python 3.11+ and NumPy (the PNGs are written by tools/procgen/core/image.py, no Pillow).
# Extra arguments pass through, e.g. scripts/gen_assets.sh --seed 7 --out /tmp/assets.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
    echo "gen_assets.sh: Python 3.11 or newer is required (found $(python3 --version 2>&1))" >&2
    exit 1
fi
if ! python3 -c 'import numpy' 2>/dev/null; then
    echo "gen_assets.sh: NumPy is missing (pip install numpy)" >&2
    exit 1
fi

# jobs: the cores, capped at four, unless PROCGEN_JOBS says
JOBS="${PROCGEN_JOBS:-$(nproc 2>/dev/null || echo 1)}"
if (( JOBS > 4 )) && [[ -z "${PROCGEN_JOBS:-}" ]]; then JOBS=4; fi
# end jobs

exec python3 -m tools.procgen build all --jobs "${JOBS}" "$@"
