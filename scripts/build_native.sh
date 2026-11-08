#!/usr/bin/env bash
# Builds the native library (native/, Rust with godot-rust gdext) into bin/libscs_native.so. The game needs it and
# refuses to start without it (M4-T37).
# Builds only when the library is missing or older than any file under native/; cargo then rebuilds what changed.
# With no cargo it says so and exits 1. The Rust version comes from native/rust-toolchain.toml; rustup installs it on
# first use.
# Cargo's build files go to .tools/native-target (CARGO_TARGET_DIR overrides it).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE="${ROOT}/native"
LIB="${ROOT}/bin/libscs_native.so"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${ROOT}/.tools/native-target}"

# Godot's import scan must never walk cargo's build files.
mkdir -p "${ROOT}/.tools"
touch "${ROOT}/.tools/.gdignore"

if [[ -f "${LIB}" ]] && [[ -z "$(find "${CRATE}" -type f -newer "${LIB}" -print -quit)" ]]; then
    echo "build_native.sh: ${LIB#"${ROOT}"/} is up to date."
    exit 0
fi

# rustup's default install puts cargo here, and a non-login shell may not have it on PATH.
if ! command -v cargo > /dev/null && [[ -x "${HOME}/.cargo/bin/cargo" ]]; then
    export PATH="${HOME}/.cargo/bin:${PATH}"
fi
if ! command -v cargo > /dev/null; then
    echo "build_native.sh: cargo not found, so ${LIB#"${ROOT}"/} cannot be built, and the game needs it to start. Install rustup (https://rustup.rs) and run this script again." >&2
    exit 1
fi

# rustup reads rust-toolchain.toml from the working directory, so build from inside the crate.
cd "${CRATE}"
start="${SECONDS}"
# Some rustup versions do not fetch the pinned toolchain on first use, so make sure it is there.
if command -v rustup > /dev/null && ! rustup show active-toolchain > /dev/null 2>&1; then
    rustup toolchain install
fi
cargo build --release --locked
built="${CARGO_TARGET_DIR}/release/libscs_native.so"
[[ -f "${built}" ]] || { echo "build_native.sh: cargo did not produce ${built}" >&2; exit 1; }
# Copy then rename, so a running Godot that has the old library mapped keeps its own copy.
mkdir -p "$(dirname "${LIB}")"
cp "${built}" "${LIB}.tmp"
mv -f "${LIB}.tmp" "${LIB}"
echo "build_native.sh: built ${LIB#"${ROOT}"/} in $((SECONDS - start)) s."
