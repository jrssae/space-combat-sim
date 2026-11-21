#!/usr/bin/env bash
# The organic looks' sheet (M10-T06): the organic test hull in each look of tools/procgen/styles/organic.py (vorlon, its
# red-based second colouring, shadow, and the hexagonal minbari, white_star and victory), photographed on this machine's GPU lit and dark, near and far, and laid out as
# one sheet, a column a look. A hull task copies this for its own look sheet.
#
# Usage: scripts/organic_sheet.sh <out_dir> [sheet_name]      (default sheet name: sheen_looks)
# Environment: ORGANIC_ATLAS_PX (the hull's atlas, default the asset's own), SHEET_RES (1920x1080), GODOT_BIN.
# Works in the scratch project reports/scratch/organic_sheet (made here, kept for the next run; remove it with
# scripts/scratch_project.sh --clean organic_sheet): each look is built once; the second colouring is a copy with its sheen
# switched over in the manifest (the maps do not depend on the sheen). What moves (the Vorlons' mottling, the Shadows'
# liquid) does not show in a still: run the game for that. Writes <out_dir>/shots/*.png and <out_dir>/<sheet_name>.png.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
PY="${ROOT}/.venv/bin/python3"
[[ -x "${PY}" ]] || PY="python3"
cd "${ROOT}"

OUT="${1:?output folder}"
SHEET="${2:-sheen_looks}"
ASSET="organic_test_hull"
SCRATCH="${ROOT}/reports/scratch/organic_sheet"
[[ -d "${SCRATCH}" ]] || scripts/scratch_project.sh organic_sheet >/dev/null
OPTIONS_DIR="${SCRATCH}/assets/generated/${ASSET}_options"
atlas=()
[[ -z "${ORGANIC_ATLAS_PX:-}" ]] || atlas=(--option "atlas_px=${ORGANIC_ATLAS_PX}")

for look in vorlon shadow minbari white_star victory; do
    "${PY}" -m tools.procgen build "${ASSET}" --out "${OPTIONS_DIR}/${look}" --option "look=\"${look}\"" "${atlas[@]}"
done
"${PY}" - "${OPTIONS_DIR}" "${ASSET}" <<'PY'
import json, shutil, sys
from pathlib import Path
from tools.procgen.styles import organic

root, asset = Path(sys.argv[1]), sys.argv[2]
target = root / "vorlon_red"
shutil.rmtree(target, ignore_errors=True)
shutil.copytree(root / "vorlon", target)
path = target / asset / "manifest.json"
manifest = json.loads(path.read_text(encoding="utf-8"))
sheen = organic.organic("vorlon", variant=True).surface["sheen"]
for mesh in [manifest["mesh"], *(piece["mesh"] for piece in manifest["pieces"].values())]:
    for surface in mesh["surfaces"]:
        if "sheen" in surface:
            surface["sheen"] = sheen
path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY
"${GODOT}" --headless --path "${SCRATCH}" --import >/dev/null 2>&1 || true

LOOKS=(vorlon vorlon_red shadow minbari white_star victory)
shots=()
for look in "${LOOKS[@]}"; do
    id="${ASSET}:${look}"
    shots+=("${look}_lit|${id}|210|three_quarter|high|lit||" "${look}_dark|${id}|210|three_quarter|high|dark||"
            "${look}_near|${id}|70|side|high|lit||" "${look}_far|${id}|900|three_quarter|low|lit||")
done
mkdir -p "${OUT}/shots"
SHEET_PATH="${SCRATCH}" scripts/model_sheet.sh "${OUT}/shots" "${shots[@]}"

rows=()
for view in lit dark near far; do
    row=""
    for look in "${LOOKS[@]}"; do
        row+="${row:+|}${look}_${view}=${look//_/ }, ${view}"
    done
    rows+=(--row "${row}")
done
"${PY}" tools/refview/model_sheets.py "${OUT}/${SHEET}.png" --title "M10-T06 organic looks (organic test hull, 300 m)" --shots "${OUT}/shots" "${rows[@]}"
