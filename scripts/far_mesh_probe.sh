#!/usr/bin/env bash
# Capital hulls near and far, with and without their far meshes, on this machine's GPU (M10-T89; scripts/far_mesh_probe_node.gd).
#
# Usage: scripts/far_mesh_probe.sh <out_dir> [project_dir]
# Environment: PROBE_RES (1920x1080), PROBE_PHASES (the node's `phases`), GODOT_BIN.
# Prints one line a phase and saves <out_dir>/<phase>.png. Run it under the locks: scripts/godot_lock.sh read --gpu -- scripts/far_mesh_probe.sh ...
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
OUT="${1:?output folder}"
PROJECT="${2:-${ROOT}}"
RES="${PROBE_RES:-1920x1080}"
mkdir -p "${OUT}"
km_phases() {
    local asset="$1" out=""
    for km in 1 3 15 50; do
        for mode in full auto; do out+="${asset}@${km}@${mode},"; done
    done
    printf '%s' "${out}"
}
PHASES="${PROBE_PHASES:-empty,$(km_phases ea_omega)$(km_phases ea_nova)$(km_phases ea_hyperion)$(km_phases raider_strike_carrier)fleet16@15@full,fleet16@15@auto,fleet16@25@full,fleet16@25@auto}"
timeout 900 "${GODOT}" --path "${PROJECT}" --resolution "${RES}" --display-driver x11 --disable-vsync --audio-driver Dummy -s res://scripts/far_mesh_probe.gd -- \
    "out=${OUT}" "phases=${PHASES}" 2>&1 | grep -E '^\[far\]|SCRIPT ERROR|ERROR:' || true
