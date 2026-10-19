#!/usr/bin/env bash
# Installs the pinned Godot editor binary into .tools/godot/ and verifies its SHA-256.
# Idempotent. If GODOT_BIN is set and executable, nothing is downloaded.
set -euo pipefail

GODOT_VERSION="4.7.2-stable"
GODOT_ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${GODOT_ZIP}"
GODOT_SHA256="cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT}/.tools/godot"
LINK="${DEST}/godot"
BIN="${DEST}/Godot_v${GODOT_VERSION}_linux.x86_64"

if [[ -n "${GODOT_BIN:-}" ]]; then
    if [[ -x "${GODOT_BIN}" ]]; then
        echo "Using GODOT_BIN=${GODOT_BIN}"
        exit 0
    fi
    echo "GODOT_BIN is set but not executable: ${GODOT_BIN}" >&2
    exit 1
fi

if [[ -x "${BIN}" ]] && "${BIN}" --headless --version 2>/dev/null | grep -q "^4\.7\.2\.stable"; then
    ln -sfn "$(basename "${BIN}")" "${LINK}"
    echo "Godot ${GODOT_VERSION} already installed at ${LINK}"
    exit 0
fi

mkdir -p "${DEST}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Downloading ${GODOT_URL}"
curl -fsSL --retry 4 --retry-delay 2 -o "${TMP}/${GODOT_ZIP}" "${GODOT_URL}"
echo "${GODOT_SHA256}  ${TMP}/${GODOT_ZIP}" | sha256sum -c -
unzip -q -o "${TMP}/${GODOT_ZIP}" -d "${DEST}"
chmod +x "${BIN}"
ln -sfn "$(basename "${BIN}")" "${LINK}"
"${LINK}" --headless --version
echo "Installed Godot ${GODOT_VERSION} at ${LINK}"
