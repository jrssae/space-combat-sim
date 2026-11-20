#!/usr/bin/env bash
# Regenerates docs/catalogue/ships.md from data/ships/catalogue.json, the ShipSpecs and the generated manifests (M10-T61).
# Run it after changing the catalogue, a ship's .tres or a hull's generator (build the assets first: scripts/gen_assets.sh);
# tests/unit/test_ship_catalog_doc.gd fails while the page is stale. Takes the Godot read lock itself.
#
# Usage: scripts/gen_ship_catalog.sh            Environment: GODOT_BIN.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
source "${ROOT}/scripts/lib_locks.sh"
SCS_LOCK_LABEL="${SCS_LOCK_LABEL:-gen_ship_catalog}" "${GODOT_LOCK_SH}" read -- \
    "${GODOT}" --headless --path "${ROOT}" -s scripts/gen_ship_catalog.gd
