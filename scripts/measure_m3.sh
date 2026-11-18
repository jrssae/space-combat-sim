#!/usr/bin/env bash
# Measures AC19's fight and the 100-ship scene on the GPU at 1080p (scripts/measure_fight.gd), one window per line under one hold of the
# GPU lock, and adds the summaries to reports/m3/measure.log. Each window closes by itself, and a hard timeout ends it if it does not.
# Usage: scripts/measure_m3.sh [ac19|costs|hundred|vsync]     all of them with no arguments
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
OUT="reports/m3"
LOG="${OUT}/measure.log"
mkdir -p "${ROOT}/${OUT}"
touch "${ROOT}/reports/.gdignore"  # or the next --import takes every screenshot for a game texture
cd "${ROOT}"
source "${ROOT}/scripts/lib_locks.sh"

# one <timeout seconds> <vsync flag or "-"> <measure_fight arguments...>
one() {
    local seconds="$1" vsync="$2" status=0
    shift 2
    local flags=(--path . --resolution 1920x1080)
    if [[ "${vsync}" != "-" ]]; then
        flags+=("${vsync}")
    fi
    timeout "${seconds}" "${GODOT}" "${flags[@]}" -s res://scripts/measure_fight.gd -- "$@" > "${OUT}/measure_run.log" 2>&1 || status=$?
    grep -E '^\[measure\]|^SCRIPT ERROR' "${OUT}/measure_run.log" | tee -a "${LOG}" || true
    if (( status != 0 )); then
        echo "measure_m3.sh: run exited ${status}: $*" | tee -a "${LOG}" >&2
    fi
}

ac19() {
    local cam
    for cam in chase cockpit; do
        one 80 --disable-vsync scene=held camera="${cam}" window=20 label="held_combat_${cam}" shot="${OUT}/ac19_held_${cam}.png"
        one 80 --disable-vsync scene=held camera="${cam}" near=60 far=110 window=20 label="held_close_${cam}" shot="${OUT}/ac19_close_${cam}.png"
        one 80 --disable-vsync scene=fight camera="${cam}" window=20 label="fight_${cam}" shot="${OUT}/ac19_fight_${cam}.png"
    done
}

# What each visual feature costs in the worst of AC19's scenes, against the same scene with everything on.
costs() {
    local base=(scene=held near=60 far=110 camera=chase window=10)
    one 60 --disable-vsync "${base[@]}" label=cost_everything_on
    one 60 --disable-vsync "${base[@]}" label=cost_flare_off exec="flare off"
    one 60 --disable-vsync "${base[@]}" label=cost_particles_off exec="set settings.particle_density 0"
    one 60 --disable-vsync "${base[@]}" label=cost_lights_off exec="running_lights off"
    one 60 --disable-vsync "${base[@]}" label=cost_blur_on exec="blur on"
    one 60 --disable-vsync "${base[@]}" label=cost_everything_on_again
    one 60 --disable-vsync scene=held near=60 far=110 camera=cockpit window=10 label=cost_cockpit_screens_on
    one 60 --disable-vsync scene=held near=60 far=110 camera=cockpit window=10 label=cost_cockpit_screens_off exec="set settings.show_hud off"
}

hundred() {
    one 120 --disable-vsync scene=hundred camera=chase warmup=8 window=12 label=hundred_t20_spiral shot="${OUT}/hundred_spiral.png"
    one 120 --disable-vsync scene=hundred camera=chase warmup=8 window=12 steps=1 label=hundred_t20_spiral_one_tick
    one 120 --disable-vsync scene=hundred_view camera=chase warmup=8 window=12 steps=1 label=hundred_in_view_one_tick shot="${OUT}/hundred_in_view.png"
}

# With vsync on, as it plays: what the player sees is 60 fps minus the vblanks that were missed.
vsync() {
    one 40 - scene=quiet camera=chase window=20 label=vsync_quiet_chase
    one 40 - scene=quiet camera=cockpit window=20 label=vsync_quiet_cockpit
    one 80 - scene=held near=60 far=110 camera=chase window=20 label=vsync_held_close_chase
    one 80 - scene=held camera=cockpit window=20 label=vsync_held_combat_cockpit
    one 80 - scene=fight camera=chase window=20 label=vsync_fight_chase
    one 80 - scene=fight camera=cockpit window=20 label=vsync_fight_cockpit
}

{
    echo "== measure_m3.sh $(date -Iseconds), load $(cut -d' ' -f1-3 /proc/loadavg)"
    pgrep -a godot | grep -v measure_fight | cut -c1-120 || true
} | tee -a "${LOG}"
export -f one ac19 costs hundred vsync
export GODOT OUT LOG
WHICH=("${@:-all}")
if [[ "${WHICH[0]}" == "all" ]]; then
    WHICH=(ac19 vsync costs hundred)
fi
"${GODOT_LOCK_SH}" read --gpu --bench -- bash -c 'for step in "$@"; do "${step}"; done' _ "${WHICH[@]}"
echo "== done, see ${LOG}"
