#!/usr/bin/env bash
# The livery concept sheet (M4-T30b, the concept stop): the textured Starfury in each wing's livery from above, below and the side,
# then the canopy at 8 m and the cockpit view lit and dark, on this machine's GPU; every shot beside the sheet.
#
# Usage: scripts/livery_concepts.sh [out.png] [wing:number,...]     (/tmp/m4_t30b_livery_concepts.png; alpha:2,beta:3,delta:7,zeta:1,kilo:4)
# Run it under the locks: flock /tmp/m5-godot.lock flock /tmp/scs-bench.lock scripts/livery_concepts.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
OUT="${1:-/tmp/m4_t30b_livery_concepts.png}"
LIVERIES="${2:-alpha:2,beta:3,delta:7,zeta:1,kilo:4}"
flock /tmp/scs-gpu.lock timeout 300 "${GODOT}" --path . --resolution 1920x1080 --disable-vsync \
    -s res://scripts/livery_concepts.gd -- out="${OUT}" liveries="${LIVERIES}"
