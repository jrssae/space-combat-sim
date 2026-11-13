#!/usr/bin/env bash
# An isolated Godot project for one agent, so it can import, rebuild or swap assets (for a before/after comparison) without
# touching the shared tree or waiting for the Godot write lock. Code, tests and data are symlinks to the repo (edit them as usual);
# .godot/ (the import cache) and assets/generated/ are private copies, made with reflinks so they cost almost nothing on btrfs.
#
# Usage: scripts/scratch_project.sh <name|dir> [--assets-from <dir>]     create (a bare name lands in reports/scratch/<name>)
#        scripts/scratch_project.sh --clean <name|dir>                   remove one
# Then: .tools/godot/godot --headless --path reports/scratch/<name> ...  (no shared Godot lock; its cache is its own).
# Windowed runs there still take the GPU lock: scripts/godot_lock.sh read --gpu -- <godot ...>. After changing a symlinked
# source, run --import in the scratch project once so its cache sees it. Screenshots still go to the main references/screenshots/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARK=".scratch_project"

usage() {
    echo "usage: scripts/scratch_project.sh <name|dir> [--assets-from <dir>] | --clean <name|dir>" >&2
    exit 2
}

# A bare name is a scratch project under reports/scratch (gitignored); anything with a slash is taken as the path.
resolve() {
    if [[ "$1" == */* ]]; then realpath -m "$1"; else echo "${ROOT}/reports/scratch/$1"; fi
}

clean=0
dir=""
assets_from="${ROOT}/assets/generated"
while (( $# > 0 )); do
    case "$1" in
        --clean) clean=1 ;;
        --assets-from) shift; assets_from="$(realpath "${1:?--assets-from needs a directory}")" ;;
        -*) usage ;;
        *) [[ -z "${dir}" ]] || usage; dir="$(resolve "$1")" ;;
    esac
    shift
done
[[ -n "${dir}" ]] || usage

if (( clean == 1 )); then
    [[ -f "${dir}/${MARK}" ]] || { echo "scratch_project.sh: ${dir} is not a scratch project (no ${MARK}); not removing it." >&2; exit 1; }
    rm -rf --one-file-system "${dir}"
    echo "scratch_project.sh: removed ${dir}"
    exit 0
fi

[[ ! -e "${dir}" ]] || { echo "scratch_project.sh: ${dir} exists; use --clean first." >&2; exit 1; }
[[ -d "${assets_from}" ]] || { echo "scratch_project.sh: no assets at ${assets_from}." >&2; exit 1; }
mkdir -p "${dir}/assets" "${dir}/reports"
touch "${dir}/${MARK}" "${dir}/reports/.gdignore"

# Everything at the top level is shared except the cache, the generated assets and reports; dot entries stay behind.
shopt -s dotglob nullglob
for entry in "${ROOT}"/*; do
    name="$(basename "${entry}")"
    case "${name}" in
        .*|assets|reports) continue ;;
    esac
    ln -s "${entry}" "${dir}/${name}"
done
for entry in "${ROOT}"/assets/*; do
    name="$(basename "${entry}")"
    [[ "${name}" == "generated" ]] || ln -s "${entry}" "${dir}/assets/${name}"
done
shopt -u dotglob nullglob

# The copies read .godot/ and assets/generated/, so they wait out a running import or asset build (a shared Godot lock).
"${ROOT}/scripts/godot_lock.sh" read -- bash -c '
    set -e
    if [[ -d "$1/.godot" ]]; then cp -a --reflink=auto "$1/.godot" "$3/.godot"; fi
    cp -a --reflink=auto "$2" "$3/assets/generated"
' _ "${ROOT}" "${assets_from}" "${dir}"

echo "scratch_project.sh: ${dir}"
echo "  run Godot with --path \"${dir}\"; remove it with scripts/scratch_project.sh --clean \"${dir}\""
