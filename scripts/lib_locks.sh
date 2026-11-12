#!/usr/bin/env bash
# The lock files that keep one machine's Godot, bench and real-renderer runs from overlapping (sourced, never run). A script
# that opens a window or times a run takes the lock with `flock "${GPU_LOCK}" ...`; the paths live here and nowhere else.
GODOT_LOCK="${SCS_GODOT_LOCK:-/tmp/m5-godot.lock}"
BENCH_LOCK="${SCS_BENCH_LOCK:-/tmp/scs-bench.lock}"
GPU_LOCK="${SCS_GPU_LOCK:-/tmp/scs-gpu.lock}"
