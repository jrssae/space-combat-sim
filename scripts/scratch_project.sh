#!/usr/bin/env bash
# An isolated Godot project for one agent, so it can import, rebuild or swap assets (for a before/after comparison) without
# touching the shared tree or waiting for the Godot write lock. Code, tests and data are symlinks to the repo (edit them as usual);
# .godot/ (the import cache) and assets/generated/ are private copies, made with reflinks so they cost almost nothing on btrfs.
#
# --staged is for checking a commit before making it: the sources are real files from the git index (HEAD plus staged changes),
# so other agents' uncommitted work in the shared checkout cannot make a test pass here that fails in CI.
#
# Usage: scripts/scratch_project.sh <name|dir> [--assets-from <dir>]     create (a bare name lands in reports/scratch/<name>)
#        scripts/scratch_project.sh <name|dir> --staged [--build-native] [--assets-from <dir>]
#                                                                        create from the index; --build-native rebuilds the
#                                                                        native library from the staged sources (own cargo target)
#        scripts/scratch_project.sh --clean <name|dir>                   remove one
# Then: .tools/godot/godot --headless --path reports/scratch/<name> ...  (no shared Godot lock; its cache is its own).
# Windowed runs there still take the GPU lock: scripts/godot_lock.sh read --gpu -- <godot ...>. After changing a symlinked
# source, run --import in the scratch project once so its cache sees it. Screenshots still go to the main references/screenshots/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARK=".scratch_project"

usage() {
    echo "usage: scripts/scratch_project.sh <name|dir> [--staged [--build-native]] [--assets-from <dir>] | --clean <name|dir>" >&2
    exit 2
}

# A bare name is a scratch project under reports/scratch (gitignored); anything with a slash is taken as the path.
resolve() {
    if [[ "$1" == */* ]]; then realpath -m "$1"; else echo "${ROOT}/reports/scratch/$1"; fi
}

clean=0
staged=0
build_native=0
dir=""
assets_from="${ROOT}/assets/generated"
while (( $# > 0 )); do
    case "$1" in
        --clean) clean=1 ;;
        --staged) staged=1 ;;
        --build-native) build_native=1 ;;
        --assets-from) shift; assets_from="$(realpath "${1:?--assets-from needs a directory}")" ;;
        -*) usage ;;
        *) [[ -z "${dir}" ]] || usage; dir="$(resolve "$1")" ;;
    esac
    shift
done
[[ -n "${dir}" ]] || usage
(( build_native == 0 || staged == 1 )) || { echo "scratch_project.sh: --build-native needs --staged." >&2; exit 2; }

if (( clean == 1 )); then
    [[ -f "${dir}/${MARK}" ]] || { echo "scratch_project.sh: ${dir} is not a scratch project (no ${MARK}); not removing it." >&2; exit 1; }
    rm -rf --one-file-system "${dir}"
    echo "scratch_project.sh: removed ${dir}"
    exit 0
fi

[[ ! -e "${dir}" ]] || { echo "scratch_project.sh: ${dir} exists; use --clean first." >&2; exit 1; }
[[ -d "${assets_from}" ]] || { echo "scratch_project.sh: no assets at ${assets_from}." >&2; exit 1; }

# The staged copy: real files from the index, so nothing untracked or unstaged from the shared checkout is present. The index is
# shared by every agent, so another agent's staged files are in it too; unstage or commit them first if they would pollute a run.
if (( staged == 1 )); then
    lib="${ROOT}/bin/libscs_native.so"
    (( build_native == 1 )) || [[ -f "${lib}" ]] || { echo "scratch_project.sh: no ${lib}; build it (scripts/build_native.sh) or pass --build-native." >&2; exit 1; }
    mkdir -p "${dir}"
    git -C "${ROOT}" checkout-index -a --prefix="${dir}/"
    mkdir -p "${dir}/reports" "${dir}/assets" "${dir}/bin"
    touch "${dir}/${MARK}" "${dir}/reports/.gdignore"
    # .tools holds the Godot binary (gitignored); share it. Cargo gets its own target below, never the shared one.
    [[ ! -d "${ROOT}/.tools" ]] || ln -s "${ROOT}/.tools" "${dir}/.tools"
    "${ROOT}/scripts/godot_lock.sh" read -- bash -c '
        set -e
        if [[ -d "$1/.godot" ]]; then cp -a --reflink=auto "$1/.godot" "$3/.godot"; fi
        rm -rf "$3/assets/generated"
        cp -a --reflink=auto "$2" "$3/assets/generated"
        if [[ "$4" == 0 ]]; then cp -a --reflink=auto "$1/bin/libscs_native.so" "$3/bin/libscs_native.so"; fi
    ' _ "${ROOT}" "${assets_from}" "${dir}" "${build_native}"

    native_staged="$(git -C "${ROOT}" diff --cached --name-only HEAD -- native bin/scs_native.gdextension | head -5)"
    if (( build_native == 1 )); then
        echo "scratch_project.sh: building the native library from the staged sources (own cargo target)..."
        if [[ -d "${ROOT}/.tools/native-target" ]]; then cp -a --reflink=auto "${ROOT}/.tools/native-target" "${dir}/.native-target"; fi
        # build_native.sh resolves its root from its own location, which is the staged copy here.
        CARGO_TARGET_DIR="${dir}/.native-target" "${dir}/scripts/build_native.sh"
    elif [[ -n "${native_staged}" ]]; then
        echo "scratch_project.sh: WARNING staged changes touch native/ (e.g. ${native_staged%%$'\n'*}); the library copied from the main checkout was"
        echo "  built from its working tree, not the staged sources. Rerun with --build-native (or run scripts/build_native.sh in the copy)."
    else
        echo "scratch_project.sh: note the native library is a copy of the main checkout's bin/libscs_native.so, built from its working tree;"
        echo "  if other agents have uncommitted native/ changes, add --build-native for a library that matches HEAD."
    fi

    cat <<EOF
scratch_project.sh: ${dir} (staged: HEAD plus the index)
  1. rebuild any asset whose generator the staged changes touch (its own assets/generated; the shared one is untouched):
       cd "${dir}" && python3 -m tools.procgen build <asset_id>... --out "${dir}/assets/generated"      ('all' for every asset)
  2. import:   .tools/godot/godot --headless --path "${dir}" --import
  3. compile:  .tools/godot/godot --headless --path "${dir}" -s scripts/check_scripts.gd
  4. GUT:      .tools/godot/godot --headless --path "${dir}" -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=<file> -gexit
               (GUT_SLOW=1 for the slow files)
  5. Python:   cd "${dir}" && python3 -m unittest tools.procgen.tests.<module> -v
  No shared Godot lock is needed (the cache is the copy's own). Remove it: scripts/scratch_project.sh --clean "${dir}"
EOF
    exit 0
fi
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
