#!/usr/bin/env bash
# Where the lock wrapper is (sourced, never run). A script that opens a window or times a run starts its Godot command with
# `"${GODOT_LOCK_SH}" read --gpu -- ...`; the lock files, their order and the modes are in scripts/godot_lock.sh and nowhere else.
GODOT_LOCK_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/godot_lock.sh"
