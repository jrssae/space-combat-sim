#!/usr/bin/env bash
# Builds the release export into build/ and smoke-tests it: Linux x86_64 into build/release/ (M8-T15, Q9), or under Git Bash on
# Windows the zip folder of Q3 (M9-T07): build/windows/ holds space-combat-sim.exe, space-combat-sim.console.exe, the .pck and
# scs_native.dll, and space-combat-sim-<version>-windows-x86_64.zip (the version is application/config/version).
# Steps: pinned export templates (SHA-512, setup_export_templates.sh), native library (release), generated assets, import, export,
# then a headless run of the exported binary that plays the tutorial's opening and quits.
# Usage: build_release.sh [--no-smoke] [--no-gen]   (--no-gen reuses the assets already in assets/generated/, which take most of the time)
# Godot runs in self-contained mode (a ._sc_ file beside the editor): its templates are copied under .tools/godot/editor_data/,
# so nothing under the user's profile is touched. Linux also keeps its game data in .tools/xdg, as before.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/native_lib_name.sh"
LIBNAME="$(native_lib_name)"
GODOT="$(godot_default_bin)"
VERSION="4.7.2.stable"
if is_windows; then
    PRESET="Windows release"
    OUT="${ROOT}/build/windows"
    BIN="${OUT}/space-combat-sim.exe"
    SMOKE_BIN="${OUT}/space-combat-sim.console.exe"
    REQUIRED=(space-combat-sim.exe space-combat-sim.console.exe space-combat-sim.pck "${LIBNAME}")
else
    PRESET="Linux release"
    OUT="${ROOT}/build/release"
    BIN="${OUT}/space-combat-sim.x86_64"
    SMOKE_BIN="${BIN}"
    REQUIRED=(space-combat-sim.x86_64 "${LIBNAME}")
fi
SMOKE=1
GEN=1
for arg in "$@"; do
    case "${arg}" in
        --no-smoke) SMOKE=0 ;;
        --no-gen) GEN=0 ;;
        *) echo "usage: build_release.sh [--no-smoke] [--no-gen]" >&2; exit 2 ;;
    esac
done
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
if (( GEN )); then
    lock write "${ROOT}/scripts/gen_assets.sh"
fi
# The Windows preset reads the icon at export time; a build that skipped the asset step needs it from an earlier one.
if is_windows && [[ ! -f "${ROOT}/assets/generated/app_icon/icon.ico" ]]; then
    echo "build_release.sh: assets/generated/app_icon/icon.ico is missing; run scripts/gen_assets.sh (or: python -m tools.procgen build app_icon)" >&2
    exit 1
fi
lock write "${GODOT}" --headless --path "${ROOT}" --import

rm -rf "${OUT}"
mkdir -p "${OUT}"
start="${SECONDS}"
lock write "${GODOT}" --headless --path "${ROOT}" --export-release "${PRESET}" "${BIN}"
for f in "${REQUIRED[@]}"; do
    [[ -s "${OUT}/${f}" ]] || { echo "build_release.sh: export is missing ${f}" >&2; ls -la "${OUT}"; exit 1; }
done
echo "build_release.sh: exported in $((SECONDS - start)) s: $(du -sh "${OUT}" | cut -f1) in ${OUT#"${ROOT}"/}"

if is_windows; then
    app_version="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "${ROOT}/project.godot")"
    [[ -n "${app_version}" ]] || { echo "build_release.sh: project.godot has no application/config/version" >&2; exit 1; }
    zip="${OUT}/space-combat-sim-${app_version}-windows-x86_64.zip"
    zip_files "${zip}" "${OUT}" "${REQUIRED[@]}"
    echo "build_release.sh: ${zip#"${ROOT}"/}: $(du -h "${zip}" | cut -f1)"
fi

(( SMOKE )) || exit 0
exec "${ROOT}/scripts/release_smoke.sh" "${SMOKE_BIN}"
