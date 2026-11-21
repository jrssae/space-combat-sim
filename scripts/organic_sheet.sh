#!/usr/bin/env bash
# The organic looks' sheen sheets (M10-T06): the organic test hull in each look of tools/procgen/styles/organic.py (vorlon,
# shadow, hex) with each sheen option (a, b, c), photographed on this machine's GPU from several views, lit and dark, near
# and far, and laid out as one sheet a look. A hull task copies this for its own option sheet.
#
# Usage: scripts/organic_sheet.sh <out_dir> [look ...]      (default: every look)
# Environment: ORGANIC_ATLAS_PX (the hull's atlas, default the asset's own), SHEET_RES (1920x1080), GODOT_BIN.
# Works in the scratch project reports/scratch/organic_sheet (made here, kept for the next run; remove it with
# scripts/scratch_project.sh --clean organic_sheet): each look is built once, and its other options are copies with their own
# sheen in the manifest (the maps do not depend on the sheen). Writes <out_dir>/shots/*.png and <out_dir>/sheen_<look>.png.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
PY="${ROOT}/.venv/bin/python3"
[[ -x "${PY}" ]] || PY="python3"
cd "${ROOT}"

OUT="${1:?output folder}"
shift
LOOKS=("$@")
(( ${#LOOKS[@]} > 0 )) || LOOKS=(vorlon shadow hex)
ASSET="organic_test_hull"
SCRATCH="${ROOT}/reports/scratch/organic_sheet"
[[ -d "${SCRATCH}" ]] || scripts/scratch_project.sh organic_sheet >/dev/null
OPTIONS_DIR="${SCRATCH}/assets/generated/${ASSET}_options"
atlas=()
[[ -z "${ORGANIC_ATLAS_PX:-}" ]] || atlas=(--option "atlas_px=${ORGANIC_ATLAS_PX}")

for look in "${LOOKS[@]}"; do
    "${PY}" -m tools.procgen build "${ASSET}" --out "${OPTIONS_DIR}/${look}_a" --option "look=\"${look}\"" "${atlas[@]}"
    "${PY}" - "${OPTIONS_DIR}" "${look}" "${ASSET}" <<'PY'
import json, shutil, sys
from pathlib import Path
from tools.procgen.styles import organic

root, look, asset = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
for option in organic.OPTIONS[1:]:
    target = root / f"{look}_{option}"
    shutil.rmtree(target, ignore_errors=True)
    shutil.copytree(root / f"{look}_a", target)
    path = target / asset / "manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    sheen = organic.organic(look, option).surface["sheen"]
    meshes = [manifest["mesh"], *(piece["mesh"] for piece in manifest["pieces"].values())]
    for mesh in meshes:
        for surface in mesh["surfaces"]:
            if "sheen" in surface:
                surface["sheen"] = sheen
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY
done
"${GODOT}" --headless --path "${SCRATCH}" --import >/dev/null 2>&1 || true

shots=()
for look in "${LOOKS[@]}"; do
    for option in a b c; do
        id="${ASSET}:${look}_${option}"
        shots+=("${look}_${option}_lit|${id}|210|three_quarter|high|lit||" "${look}_${option}_dark|${id}|210|three_quarter|high|dark||"
                "${look}_${option}_top|${id}|260|top|high|lit||" "${look}_${option}_near|${id}|70|side|high|lit||"
                "${look}_${option}_far|${id}|900|three_quarter|low|lit||")
    done
done
mkdir -p "${OUT}/shots"
SHEET_PATH="${SCRATCH}" scripts/model_sheet.sh "${OUT}/shots" "${shots[@]}"

for look in "${LOOKS[@]}"; do
    rows=()
    for view in lit dark top near far; do
        rows+=(--row "${look}_a_${view}=A, ${view}|${look}_b_${view}=B, ${view}|${look}_c_${view}=C, ${view}")
    done
    "${PY}" tools/refview/model_sheets.py "${OUT}/sheen_${look}.png" --title "M10-T06 sheen options: ${look} (organic test hull, 300 m)" \
        --shots "${OUT}/shots" "${rows[@]}"
done
