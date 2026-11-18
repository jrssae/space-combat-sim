#!/usr/bin/env bash
# Takes the M3 capture set P5-P13 (docs/milestones/m3-ai-pilots-and-wingmen.md, "Capture pre-checks") on the GPU, writing PNGs and each
# run's console output to reports/m3/. One window per capture: it closes by itself, and a hard timeout ends it if it does not.
# Keep the machine's mouse alone while it runs: the game window takes it for a few seconds at a time. `wait` counts physics ticks, 60 a real
# second at any frame rate, so at `timescale 0.1` a `wait 60` is a tenth of a second of the fight.
# Usage: scripts/capture_m3.sh [p5 p6 ...]     all of them with no arguments; set CAPTURE_SIZE=WxH for another window size.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIZE="${CAPTURE_SIZE:-1920x1080}"
GODOT="${GODOT_BIN:-${ROOT}/.tools/godot/godot}"
OUT="reports/m3"
source "${ROOT}/scripts/lib_locks.sh"
mkdir -p "${ROOT}/${OUT}"
touch "${ROOT}/reports/.gdignore"  # or the next --import takes every screenshot for a game texture
cd "${ROOT}"

# run <name> <seconds> "<console commands>": one window, under the GPU lock, killed after <seconds>.
run() {
    local name="$1" seconds="$2" commands="$3" status=0
    "${GODOT_LOCK_SH}" read --gpu -- timeout "${seconds}" "${GODOT}" --path . --resolution "${SIZE}" -- --console-strict \
        --console-exec="${commands}; quit" > "${OUT}/${name}.log" 2>&1 || status=$?
    grep -E '^\[console\]|^SCRIPT ERROR|^ERROR' "${OUT}/${name}.log" | grep -vE '^\[console\] > ' || true
    if (( status != 0 )); then
        echo "capture_m3.sh: ${name} exited ${status} (see ${OUT}/${name}.log)" >&2
        return "${status}"
    fi
}

p5() {
    echo "== P5 allies and break-up (AC7, AC18)"
    run p5 90 "wave stop; god on; despawn all; camera cockpit; spawn ally idle 60 0 0; wait 20; screenshot ${OUT}/p5_ally_front.png; despawn all; spawn ally idle 60 35 20; wait 20; screenshot ${OUT}/p5_ally_three_quarter.png; set targeting.selected \"ALPHA 2\"; timescale 0.25; kill target; wait 40; screenshot ${OUT}/p5_breakup.png; wait 80; screenshot ${OUT}/p5_breakup_late.png; timescale 1; wait 60; screenshot ${OUT}/p5_debris.png"
}

p6() {
    echo "== P6 instructor (AC10, AC17)"
    # The instructor waits for a parked player 1 600 m out, so the player coasts straight at the roll's waypoint to see it from behind.
    run p6 90 "scenario instructor_route; wait 30; god on; set ship.velocity 6 4.5 -59.7; wait 270; screenshot ${OUT}/p6_follow.png; state route; wait 600; screenshot ${OUT}/p6_demo.png; state route; camera cockpit; wait 90; screenshot ${OUT}/p6_demo_cockpit.png; state route; ai INSTRUCTOR"
}

p7() {
    echo "== P7 wing (AC11, AC15)"
    # The finger-four's slots lie behind the chase camera, so `look` turns the view back over the player's ship to show them.
    run p7 90 "god on; wave stop; wait 600; look 165 15; wait 30; screenshot ${OUT}/p7_formation_chase.png; look off; wing order engage; wave start 3; wait 900; screenshot ${OUT}/p7_engage.png; state wing"
}

p8() {
    echo "== P8 dogfight (AC12, AC15)"
    # The two sides meet about 3 km ahead of the player's start and off to its right, so the player coasts in to see the merge and what follows.
    run p8 90 "scenario dogfight; wait 10; god on; set ship.velocity -100 0 -45; set targeting.selected \"RAIDER 1\"; wait 900; screenshot ${OUT}/p8_merge.png; wait 300; screenshot ${OUT}/p8_dogfight.png; wait 300; screenshot ${OUT}/p8_late.png; state ai"
}

p9() {
    echo "== P9 visual pass (AC30-AC33, AC35)"
    run p9_relit 60 "wave stop; god on; despawn all; camera cockpit; spawn ally idle 40 30 10; wait 20; screenshot ${OUT}/p9_relit.png; camera chase; wait 5; screenshot ${OUT}/p9_hero_chase.png"
    run p9_fight 90 "god on; wing order engage; wave start 3; wait 600; screenshot ${OUT}/p9_fight.png; state lights; state render; camera cockpit; wait 30; screenshot ${OUT}/p9_cockpit.png"
}

p10() {
    echo "== P10 ranges and far dots (AC28, AC35)"
    # `spawn` places every ship straight ahead (its yaw and pitch turn the ship, not the bearing), so each range gets its own frame.
    run p10 60 "wave stop; god on; despawn all; camera cockpit; spawn raider idle 150 35 20; wait 30; screenshot ${OUT}/p10_lod_150.png; get render.far_dots; despawn all; spawn raider idle 600 35 20; wait 30; screenshot ${OUT}/p10_lod_600.png; get render.far_dots; despawn all; spawn raider idle 2000 35 20; wait 30; screenshot ${OUT}/p10_lod_2000.png; get render.far_dots; despawn all; spawn raider idle 6000 35 20; wait 30; screenshot ${OUT}/p10_lod_6000.png; get render.far_dots"
}

p11() {
    echo "== P11 running lights (AC36, AC37, AC39)"
    run p11 60 "wave stop; god on; despawn all; camera cockpit; spawn ally idle 40 0 10; wait 20; screenshot ${OUT}/p11_near_ally.png; despawn all; spawn ally idle 26 0 -80; wait 20; screenshot ${OUT}/p11_top_lit.png; despawn all; spawn ally idle 26 0 -80 lights=off; wait 20; screenshot ${OUT}/p11_top_dark.png; despawn all; spawn raider idle 80 10 0; wait 20; screenshot ${OUT}/p11_near_raider.png; despawn all; spawn raider idle 80 10 0 lights=off; wait 20; screenshot ${OUT}/p11_near_raider_dark.png; despawn all; spawn raider idle 800 0 0; wait 20; screenshot ${OUT}/p11_far.png; despawn all; wait 5; screenshot ${OUT}/p11_cockpit.png; camera chase; wait 5; screenshot ${OUT}/p11_own_lights.png"
}

p12() {
    echo "== P12 last-hit break-up (AC38, AC39)"
    # A console `kill` has no hit point, so its blast is at the centre; the second run lets a raider's bolt kill a damaged player, for a blast at a joint.
    run p12 60 "wave stop; god on; despawn all; camera cockpit; spawn ally idle 60 0 0; timescale 0.1; wait 5; kill allies; wait 15; screenshot ${OUT}/p12_a.png; wait 210; screenshot ${OUT}/p12_b.png; timescale 1"
    run p12_joint 60 "wave stop; god off; despawn all; damage 296 player; spawn raider ai 120 0 0; wait 23; screenshot ${OUT}/p12_joint.png; state hull"
}

p13() {
    echo "== P13 cockpit (AC40, AC41)"
    # The sandbox's wingmen stay for the octagon's friendly contacts; the raider ahead is the target, the far one a second hostile on the radar.
    run p13 60 "god on; wave stop; camera cockpit; spawn raider idle 60 -10 -120; spawn raider idle 3000; set targeting.selected \"RAIDER 1\"; wait 60; screenshot ${OUT}/p13_cockpit.png; wait 600; state render; state screens"
}

ALL=(p5 p6 p7 p8 p9 p10 p11 p12 p13)
for capture in "${@:-${ALL[@]}}"; do
    "${capture}"
done
echo "== done: $(ls "${OUT}"/p*.png | wc -l) images in ${OUT}/"
