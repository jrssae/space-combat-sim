#!/usr/bin/env bash
# Builds the Linux x86_64 release export (M8-T15, Q9) into build/release/ and smoke-tests it.
# Steps: pinned export templates (SHA-512, setup_export_templates.sh), native library (release), generated assets, import, export,
# then a headless run of the exported binary that plays free_flight a few ticks and quits. Usage: build_release.sh [--no-smoke]
# Godot runs in self-contained mode (a ._sc_ file beside the editor): its templates are copied under .tools/godot/editor_data/,
# so nothing under the user's profile is touched. Linux also keeps its game data in .tools/xdg, as before.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/native_lib_name.sh"
LIBNAME="$(native_lib_name)"
GODOT="$(godot_default_bin)"
VERSION="4.7.2.stable"
OUT="${ROOT}/build/release"
BIN="${OUT}/space-combat-sim.x86_64"
export SCS_LOCK_LABEL="${SCS_LOCK_LABEL:-M8-T15}"
export TMPDIR="${TMPDIR:-${ROOT}/reports/tmp}"
mkdir -p "${TMPDIR}"
[[ -x "${ROOT}/.venv/bin/python3" ]] && export PATH="${ROOT}/.venv/bin:${PATH}"
lock() { local mode="$1"; shift; "${ROOT}/scripts/godot_lock.sh" "${mode}" -- "$@"; }

[[ -x "${GODOT}" ]] || "${ROOT}/scripts/setup_godot.sh"
"${ROOT}/scripts/setup_export_templates.sh"

# The export looks the templates up as <editor dir>/editor_data/export_templates/<version>/ (self-contained mode).
touch "$(dirname "${GODOT}")/._sc_"
tdir="$(dirname "${GODOT}")/editor_data/export_templates/${VERSION}"
mkdir -p "${tdir}"
for t in "${ROOT}/.tools/godot/templates/"*; do
    [[ "$(basename "${t}")" == version.txt ]] || cp -f "${t}" "${tdir}/"
done
echo "${VERSION}" > "${tdir}/version.txt"
is_windows || export XDG_DATA_HOME="${ROOT}/.tools/xdg"

lock write "${ROOT}/scripts/build_native.sh"
lock write "${ROOT}/scripts/gen_assets.sh"
lock write "${GODOT}" --headless --path "${ROOT}" --import

rm -rf "${OUT}"
mkdir -p "${OUT}"
start="${SECONDS}"
lock write "${GODOT}" --headless --path "${ROOT}" --export-release "Linux release" "${BIN}"
[[ -x "${BIN}" && -f "${OUT}/${LIBNAME}" ]] || { echo "build_release.sh: export is missing the binary or ${LIBNAME}" >&2; ls -la "${OUT}"; exit 1; }
echo "build_release.sh: exported in $((SECONDS - start)) s: $(du -sh "${OUT}" | cut -f1) in ${OUT#"${ROOT}"/}"

[[ "${1:-}" == "--no-smoke" ]] && exit 0
exec "${ROOT}/scripts/release_smoke.sh" "${BIN}"
