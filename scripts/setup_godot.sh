#!/usr/bin/env bash
# Installs the pinned Godot editor binary into .tools/godot/ and verifies its SHA-256.
# Idempotent. If GODOT_BIN is set and executable, nothing is downloaded.
set -euo pipefail

GODOT_VERSION="4.7.2-stable"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/lib_platform.sh"
DEST="${ROOT}/.tools/godot"
if is_windows; then
    # Copies, not symlinks. godot.exe is the editor itself (it prints to a pipe, exits with the script's code, and a killed run
    # leaves no child). godot_console.exe is the console wrapper, which only works as <name>_console.exe beside <name>.exe.
    GODOT_ZIP="Godot_v${GODOT_VERSION}_win64.exe.zip"
    GODOT_SHA256="731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953"
    GODOT_EXE="Godot_v${GODOT_VERSION}_win64.exe"
    GODOT_CONSOLE_EXE="Godot_v${GODOT_VERSION}_win64_console.exe"
    LINK="${DEST}/godot.exe"
    BIN="${LINK}"
else
    GODOT_ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
    GODOT_SHA256="cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4"
    LINK="${DEST}/godot"
    BIN="${DEST}/Godot_v${GODOT_VERSION}_linux.x86_64"
fi
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${GODOT_ZIP}"

if [[ -n "${GODOT_BIN:-}" ]]; then
    if [[ -x "${GODOT_BIN}" ]]; then
        echo "Using GODOT_BIN=${GODOT_BIN}"
        exit 0
    fi
    echo "GODOT_BIN is set but not executable: ${GODOT_BIN}" >&2
    exit 1
fi

if [[ -x "${BIN}" ]] && "${BIN}" --headless --version 2>/dev/null | grep -q "^4\.7\.2\.stable"; then
    [[ "${BIN}" == "${LINK}" ]] || ln -sfn "$(basename "${BIN}")" "${LINK}"
    echo "Godot ${GODOT_VERSION} already installed at ${LINK}"
    exit 0
fi

mkdir -p "${DEST}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Downloading ${GODOT_URL}"
curl -fsSL --retry 4 --retry-delay 2 -o "${TMP}/${GODOT_ZIP}" "${GODOT_URL}"
echo "${GODOT_SHA256}  ${TMP}/${GODOT_ZIP}" | sha256sum -c -
if is_windows; then
    unzip_member "${TMP}/${GODOT_ZIP}" "${TMP}" "${GODOT_EXE}"
    unzip_member "${TMP}/${GODOT_ZIP}" "${TMP}" "${GODOT_CONSOLE_EXE}"
    cp -f "${TMP}/${GODOT_EXE}" "${LINK}"
    cp -f "${TMP}/${GODOT_CONSOLE_EXE}" "${DEST}/godot_console.exe"
else
    unzip -q -o "${TMP}/${GODOT_ZIP}" -d "${DEST}"
    chmod +x "${BIN}"
    ln -sfn "$(basename "${BIN}")" "${LINK}"
fi
"${LINK}" --headless --version
echo "Installed Godot ${GODOT_VERSION} at ${LINK}"
