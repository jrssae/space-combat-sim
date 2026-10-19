#!/usr/bin/env bash
# Generate every procedural asset into assets/generated/ (gitignored): python3 -m tools.procgen build all.
# Needs Python 3.11+ and NumPy; Pillow is optional (only for the fallback sky panorama PNG).
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

exec python3 -m tools.procgen build all "$@"
