#!/usr/bin/env bash
# Renders the game with software Vulkan (llvmpipe) in a virtual X display and saves screenshots through the
# debug console, so agents without a GPU can look at what the renderer draws. GDGS falls back to its Raster
# backend on llvmpipe (8-wide subgroups), so this checks geometry, layout and compositing, not Compute artifacts.
# Needs: sudo apt-get install mesa-vulkan-drivers xvfb   (see docs/research-notes.md)
# Usage: scripts/capture.sh "<console commands>" [WxH]
#   e.g. scripts/capture.sh "wait 60; screenshot /tmp/chase.png; camera cockpit; wait 10; screenshot /tmp/cockpit.png"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
COMMANDS="${1:?console commands required}"
SIZE="${2:-1280x720}"
cd "${ROOT}"
exec timeout 600 xvfb-run -a -s "-screen 0 1920x1080x24" "${GODOT}" --path . --rendering-driver vulkan \
    --resolution "${SIZE}" -- --console-strict --console-exec="${COMMANDS}; quit"
