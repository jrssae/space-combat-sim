#!/usr/bin/env bash
# Renders every Cobra-bay launch shot for review (M8-T30): four key frames, a contact sheet per shot and shots.md
# (scripts/launch_shot_review_node.gd). Usage: scripts/launch_shot_review.sh <out dir> [id,id,...]
# Environment: REVIEW_RES (960x540), GODOT_PATH (the project, default this checkout), GODOT_BIN. Takes the Godot (read) and GPU locks.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
cd "${ROOT}"
OUT="$(realpath -m "${1:?usage: scripts/launch_shot_review.sh <out dir> [ids]}")"
mkdir -p "${OUT}"
"${ROOT}/scripts/godot_lock.sh" read --gpu -- timeout 3600 "${GODOT}" --path "${GODOT_PATH:-.}" --resolution "${REVIEW_RES:-960x540}" \
    --disable-vsync --audio-driver Dummy -s res://scripts/launch_shot_review.gd -- out="${OUT}" only="${2:-}" 2>&1 | tee "${OUT}/review.log" \
    | grep -E '^\[launch_shot_review\]|SCRIPT ERROR|WARNING: launch_shot_review' || true
