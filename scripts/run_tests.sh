#!/usr/bin/env bash
# One entry point for the project's automated checks, in four tiers (M6-T17). Everything works without a GPU. Exits non-zero on
# any failure. Logs and the GUT JUnit XML land in reports/ (gitignored; CI uploads it).
#   run_tests.sh --quick     a few minutes, every area touched, for iteration between changes. NOT a merge gate: it leaves
#                            out the slow and balance files, the whole-asset Python builds, the Jolt behaviour fights and
#                            ten of the twelve console smokes (the list is tests/quick_suite.txt).
#   run_tests.sh --standard  (the default, and the merge gate) the Python tests, the native build and its Rust tests, the import,
#                            the compile check, every GUT file with the slow ones and without the balance tests, and the smokes.
#   run_tests.sh --balance   only the balance tests (tests/balance_suite.txt), the long fights judging how the game plays.
#   run_tests.sh --full      standard plus the balance tests.
# GUT_SHARD=k/n (CI, standard) runs only every n-th GUT script from the k-th, in path order, so n jobs share the GUT run; the
# Rust tests and the console smoke runs then run in shard 1 only (and the Python tests too, unless PYTHON_TESTS=0: CI runs them
# in a job of their own). Unset (the default) runs everything.
# GUT_SLOW=1 (the default here, and CI) runs the slow GUT files too (M4-T36, Q58: the long seeded parity fights,
# `tests/fixtures/slow_tests.gd`); GUT_SLOW=0 leaves them out. GUT_BALANCE=1 runs the balance tests (`tests/fixtures/balance_tests.gd`);
# only --balance and --full set it. A focused GUT run without this script leaves both out.
set -euo pipefail

usage() {
    echo "usage: scripts/run_tests.sh [--quick | --standard | --balance | --full]   (default: --standard)" >&2
    exit 2
}

mode="standard"
(( $# <= 1 )) || usage
case "${1:---standard}" in
    --quick) mode="quick" ;;
    --standard) mode="standard" ;;
    --balance) mode="balance" ;;
    --full) mode="full" ;;
    *) usage ;;
esac

source "$(dirname "${BASH_SOURCE[0]}")/lib_tests.sh"
cd "${ROOT}"
mkdir -p "${REPORTS}"
require_godot

# run_gut <log> <junit xml> <timeout s> <godot args...>: one GUT process; returns its exit code.
run_gut() {
    local log="$1" xml="$2" limit="$3"
    shift 3
    local status=0
    run_logged "${log}" "${GODOT_READ[@]}" timeout "${limit}" "${GODOT}" --headless --path . -s addons/gut/gut_cmdln.gd "$@" -gexit \
        -gjunit_xml_file="${xml}" || status=$?
    return "${status}"
}

# test_paths <list file>: the res:// paths of a tests/*_suite.txt, comments and blank lines skipped, one per line.
test_paths() {
    grep -vE '^\s*(#|$)' "$1" | tr -d '\r'
}

if [[ "${mode}" == "quick" ]]; then
    started=${SECONDS}
    rm -f "${REPORTS}"/quick_*.log "${REPORTS}/gut_quick.xml"
    if [[ ! -d assets/generated ]] || [[ -n "$(find tools/procgen -type f -newer assets/generated -print -quit 2> /dev/null)" ]]; then
        echo "run_tests.sh: assets/generated is missing or older than tools/procgen; run scripts/gen_assets.sh and scripts/run_tests.sh before merging."
    fi
    build_native_or_fail
    # A fresh checkout (or a new class_name) fails the compile check until the import has run (M5-T38's finding).
    godot_import "${REPORTS}/quick_import.log"
    compile_check "${REPORTS}/quick_check_scripts.log"
    rust_tests "${REPORTS}/quick_cargo.log"

    echo "== Python tests"
    mapfile -t py_modules < <(test_paths tests/quick_python.txt)
    run_logged "${REPORTS}/quick_python.log" "$(python_bin)" -m unittest "${py_modules[@]}" \
        || fail "The Python tests failed (see reports/quick_python.log)."

    echo "== GUT"
    mapfile -t quick_files < <(test_paths tests/quick_suite.txt)
    for f in "${quick_files[@]}"; do
        [[ -f "${f#res://}" ]] || fail "tests/quick_suite.txt lists ${f}, which does not exist."
    done
    gut_status=0
    GUT_SLOW=0 GUT_BALANCE=0 run_gut "${REPORTS}/quick_gut.log" reports/gut_quick.xml 600 \
        "-gtest=$(IFS=,; echo "${quick_files[*]}")" || gut_status=$?
    (( gut_status == 0 )) || fail "GUT failed with exit code ${gut_status} (see reports/quick_gut.log)."

    smoke_status=0
    echo "== Console smoke run: strict script that succeeds"
    smoke_console_host "${REPORTS}/quick_console_smoke.log" || smoke_status=1
    echo "== Console smoke run: the real main scene"
    smoke_main_scene "${REPORTS}/quick_console_main.log" || smoke_status=1
    (( smoke_status == 0 )) || fail "The console smoke runs failed (see reports/quick_console_*.log)."
    echo "run_tests.sh --quick: passed in $(( SECONDS - started )) s."
    exit 0
fi

if [[ "${mode}" == "balance" ]]; then
    started=${SECONDS}
    rm -f "${REPORTS}"/balance_*.log "${REPORTS}/gut_balance.xml"
    build_native_or_fail
    mapfile -t balance_files < <(test_paths tests/balance_suite.txt)
    for f in "${balance_files[@]}"; do
        [[ -f "${f#res://}" ]] || fail "tests/balance_suite.txt lists ${f}, which does not exist."
    done
    echo "== GUT (balance files)"
    gut_status=0
    GUT_SLOW=1 GUT_BALANCE=1 run_gut "${REPORTS}/balance_gut.log" reports/gut_balance.xml 7200 \
        "-gtest=$(IFS=,; echo "${balance_files[*]}")" || gut_status=$?
    echo "run_tests.sh --balance: finished in $(( SECONDS - started )) s (GUT exit code ${gut_status})."
    exit "${gut_status}"
fi

# Standard and full: the merge gate, with the balance tests on for full only.
export GUT_SLOW="${GUT_SLOW:-1}"
if [[ "${mode}" == "full" ]]; then
    export GUT_BALANCE=1
else
    export GUT_BALANCE="${GUT_BALANCE:-0}"
fi
started=${SECONDS}
# reports/ must only describe this run (the quick tier's logs are its own).
find "${REPORTS}" -maxdepth 1 -name '*.log' ! -name 'quick_*' ! -name 'balance_*' -delete
rm -f "${REPORTS}/gut.xml"


gut_select=(-gdir=res://tests -ginclude_subdirs)
run_extras=1
if [[ -n "${GUT_SHARD:-}" ]]; then
    [[ "${GUT_SHARD}" =~ ^([0-9]+)/([0-9]+)$ ]] || fail "GUT_SHARD must be k/n, got '${GUT_SHARD}'."
    shard="${BASH_REMATCH[1]}"
    shards="${BASH_REMATCH[2]}"
    (( shard >= 1 && shard <= shards )) || fail "GUT_SHARD ${GUT_SHARD}: k must be 1..n."
    # The scripts GUT finds with -gdir=res://tests -ginclude_subdirs, in a stable order.
    mapfile -t all_scripts < <(find tests -name 'test_*.gd' | LC_ALL=C sort)
    picked=()
    for i in "${!all_scripts[@]}"; do
        if (( i % shards == shard - 1 )); then
            picked+=("res://${all_scripts[$i]}")
        fi
    done
    (( ${#picked[@]} > 0 )) || fail "GUT_SHARD ${GUT_SHARD} picks no script."
    gut_select=("-gtest=$(IFS=,; echo "${picked[*]}")")
    (( shard == 1 )) || run_extras=0
    echo "run_tests.sh: GUT shard ${shard} of ${shards}: ${#picked[@]} of ${#all_scripts[@]} scripts."
fi

if (( run_extras )); then
    # CI runs the Python tests in a job of their own and sets PYTHON_TESTS=0 on the GUT shards.
    if [[ "${PYTHON_TESTS:-1}" != "0" && -d tools/procgen/tests ]]; then
        echo "== Python tests"
        "$(python_bin)" -m unittest discover -s tools/procgen/tests -t . -v
    fi
    rust_tests "${REPORTS}/cargo.log"
fi

# Built before the import so Godot finds it (architecture §17.5).
build_native_or_fail

# --import imports resources but does not compile scripts, hence the separate compile check below.
godot_import "${REPORTS}/import.log"

compile_check "${REPORTS}/check_scripts.log"

echo "== GUT"
# The whole run takes about 40 minutes on the maintainer's machine, a CI shard 15 to 25. A shard's timeout (40 minutes)
# fires before CI's 60-minute job limit, so a hang ends with GUT's log and this script's message, not a cancelled job.
gut_timeout=3600
if [[ -n "${GUT_SHARD:-}" ]]; then
    gut_timeout=2400
elif [[ "${mode}" == "full" ]]; then
    # The balance fights add about half an hour: with them the run passed the hour and was cut short (M5-T20).
    gut_timeout=7200
fi
gut_status=0
run_logged "${REPORTS}/gut.log" "${GODOT_READ[@]}" timeout "${gut_timeout}" "${GODOT}" --headless --path . -s addons/gut/gut_cmdln.gd \
    "${gut_select[@]}" -gexit -gjunit_xml_file=reports/gut.xml \
    || gut_status=$?
if (( gut_status != 0 )); then
    echo "run_tests.sh: GUT failed with exit code ${gut_status} (see reports/gut.log)." >&2
fi
if (( ! run_extras )); then
    echo "run_tests.sh: the console smoke runs are in GUT shard 1."
    exit "${gut_status}"
fi

# Debug console smoke runs (architecture §6.4, AC21): a live headless build driven by --console-exec must print the
# expected [console] lines and exit with the requested code. console_host.tscn is an empty scene, so only the
# console's own providers (settings, debug, time) exist. `set` must not touch user://settings.cfg (only `save` does).
smoke_status=0

echo "== Console smoke run: strict script that succeeds"
smoke_console_host "${REPORTS}/console_smoke.log" || smoke_status=1

echo "== Console smoke run: strict script with an out-of-range value must exit 1"
log="${REPORTS}/console_strict.log"
console_run "${log}" 1 --console-strict --console-exec="set settings.stick_deadzone 0.9; quit 0" || smoke_status=1
expect_line "${log}" "[console] error: settings.stick_deadzone must be in 0.0..0.3, got 0.9" || smoke_status=1
reject_text "${log}" "[console] > quit 0" || smoke_status=1

echo "== Console smoke run: control profiles"
# M2-T11 / AC13: bind is session-only, `controls save` writes user://controls/<name>.cfg, `controls use default`
# drops the unsaved bind, and only `save` may touch settings.cfg. The scratch profile is deleted at the end.
log="${REPORTS}/console_controls.log"
settings_before="$(settings_fingerprint)"
console_run "${log}" 0 --console-strict \
    --console-exec="controls save smoke_test; bind fire key:K; controls show fire; controls use default; controls show fire; controls use m1_classic; controls show yaw_left; controls show roll_left; controls use default; controls show main_left; controls show roll_left; controls delete smoke_test; quit 0" \
    || smoke_status=1
expect_line "${log}" "[console] fire: pad:button:0 key:Space mouse:1 key:K (deadzone 0.50)" || smoke_status=1
expect_line "${log}" "[console] fire: pad:button:0 key:Space mouse:1 (deadzone 0.50)" || smoke_status=1
# Layout B (M3-T01): m1_classic swaps only the pad (stick yaws, D-pad rolls); the keys are the default's.
expect_line "${log}" "[console] yaw_left: pad:axis:2- (deadzone 0.15)" || smoke_status=1
expect_line "${log}" "[console] roll_left: pad:button:13 key:CapsLock (deadzone 0.50)" || smoke_status=1
expect_line "${log}" "[console] main_left: pad:axis:4+ key:Q key:W (deadzone 0.05)" || smoke_status=1
expect_line "${log}" "[console] roll_left: key:CapsLock (deadzone 0.15)" || smoke_status=1
expect_line "${log}" "[console] deleted control profile 'smoke_test'" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
if [[ "$(settings_fingerprint)" != "${settings_before}" ]]; then
    echo "run_tests.sh: control profile commands changed ${SETTINGS_CFG}; only 'save' may write it." >&2
    smoke_status=1
fi

echo "== Console smoke run: binding the console key must exit 1"
log="${REPORTS}/console_controls_strict.log"
console_run "${log}" 1 --console-strict --console-exec="bind fire key:QuoteLeft; quit 0" || smoke_status=1
expect_text "${log}" "[console] error: bind fire: key:QuoteLeft is the console key" || smoke_status=1
reject_text "${log}" "[console] > quit 0" || smoke_status=1

echo "== Console smoke run: the real main scene"
smoke_main_scene "${REPORTS}/console_main.log" || smoke_status=1

echo "== Console smoke run: a rebase 900 km out comes straight back on the real main scene"
# M3-T14 / AC21 (maintainer Q13): `rebase -900000 0 0` puts everything 900 km from the local origin; the automatic rebase
# (5 km in main.tscn) brings the player back in the same tick, so the origin lands on the player, still at the launch point.
log="${REPORTS}/console_rebase.log"
main_run "${log}" 180 0 "rebase" -- --console-strict \
    --console-exec="wait 30; rebase -900000 0 0; wait 1; state world; get ship.position; quit" \
    || smoke_status=1
expect_line "${log}" "[console] world.origin = [-900000.00, 0.00, 0.00] m" || smoke_status=1
expect_line "${log}" "[console] world.origin = [0.00, 0.00, 0.00] m" || smoke_status=1
expect_line "${log}" "[console] world.auto_rebase_distance_m = 5000.00 m" || smoke_status=1
expect_line "${log}" "[console] world.rebases = 2" || smoke_status=1
expect_text "${log}" "[console] world.rebase_us = " || smoke_status=1
expect_line "${log}" "[console] ship.position = (0.00, 0.00, 0.00) m" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: god mode and damage on the real main scene"
# M2-T03 / AC8: with god on the player's hull does not change; with god off it does.
log="${REPORTS}/console_damage.log"
main_run "${log}" 180 0 "damage" -- --console-strict \
    --console-exec="wait 30; god on; damage 50 player; get hull.hp; god off; damage 50 player; get hull.hp; quit" \
    || smoke_status=1
expect_line "${log}" "[console] hull.hp = 300.00" || smoke_status=1
expect_line "${log}" "[console] hull.hp = 250.00" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1

echo "== Console smoke run: a raider is shot down and the player dies and respawns on the real main scene"
# M2-T06 / AC7: kill a selected raider (explosion, debris set, pool), then the player (respawn after 3 s of sim time).
log="${REPORTS}/console_destruction.log"
main_run "${log}" 180 0 "destruction" -- --console-strict \
    --console-exec='wait 30; spawn raider 60 0 0; wait 5; set targeting.selected "RAIDER 1"; kill target; wait 5; get raiders.alive; get debris.free_sets; kill player; wait 3; get hull.destroyed; wait 200; get hull.destroyed; quit' \
    || smoke_status=1
expect_line "${log}" "[console] raiders.alive = 0" || smoke_status=1
expect_line "${log}" "[console] debris.free_sets = 3" || smoke_status=1  # two raider sets and two Starfury sets, one flying
expect_line "${log}" "[console] hull.destroyed = true" || smoke_status=1
expect_line "${log}" "[console] hull.destroyed = false" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: a raider is shot down (the combat smoke of M2-T10)"
log="${REPORTS}/console_combat.log"
main_run "${log}" 180 0 "combat" -- --console-strict \
    --console-exec='wait 30; god on; spawn raider idle 400; wait 5; set targeting.selected "RAIDER 1"; kill target; wait 120; get raiders.alive; get waves.kills; quit' \
    || smoke_status=1
expect_line "${log}" "[console] raiders.alive = 0" || smoke_status=1
expect_line "${log}" "[console] waves.kills = 1" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: an attacking raider on the real main scene"
# M2-T07 / AC9: an attack raider 2 km out flies its gun run (the brain's state is readable) and lands hits on the player.
# `wave stop` first, and `despawn all` parks the sandbox's wingmen (M3-T10): their guns would take the raider (and its brain)
# out of the test.
log="${REPORTS}/console_attack.log"
main_run "${log}" 240 0 "attack" -- --console-strict \
    --console-exec='wait 30; wave stop; god on; despawn all; spawn raider attack 2000; set targeting.selected "RAIDER 1"; wait 1200; get raiders.selected_brain; get combat.hits; quit' \
    || smoke_status=1
expect_text "${log}" "behaviour: attack" || smoke_status=1
expect_text "${log}" "[console] combat.hits = " || smoke_status=1
reject_text "${log}" "[console] combat.hits = 0" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: waves, and the scenario command reloads the scene with the startup script still running"
# M2-T09 / AC11: wave start + kill all advance the waves; `scenario free_flight` reloads into free flight (no raiders, no waves)
# and the statements after it still run in the new scene.
log="${REPORTS}/console_waves.log"
main_run "${log}" 240 0 "waves" -- --console-strict \
    --console-exec='wait 30; wave start 1; wait 480; get waves.state; kill all; wait 30; get waves.kills; scenario free_flight; wait 30; get raiders.pool_size; get waves.state; quit' \
    || smoke_status=1
expect_line "${log}" "[console] waves.state = active" || smoke_status=1
expect_line "${log}" "[console] waves.kills = 4" || smoke_status=1
expect_line "${log}" "[console] raiders.pool_size = 0" || smoke_status=1
expect_line "${log}" "[console] waves.state = idle" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: an allied Starfury is spawned, shot down into Starfury chunks and replaced on the real main scene"
# M3-T08 / AC7: `spawn ally` takes an ALPHA ship from the ally pool, a destroyed ally is no kill and takes one of the Starfury's two
# chunk sets (the player's death takes the other), and `kill allies` leaves none. `despawn all` first parks the sandbox's
# wingmen (M3-T10), so the console's ally is ALPHA 2. It waits before it quits (the explosions' sounds).
log="${REPORTS}/console_allies.log"
main_run "${log}" 180 0 "allies" -- --console-strict \
    --console-exec='wait 30; wave stop; despawn all; spawn ally idle 60 0 0; wait 5; get allies.alive; get allies.pool_size; set targeting.selected "ALPHA 2"; kill target; wait 5; get allies.alive; get allies.free; get waves.kills; get debris.free_sets; spawn ally ai 800; wait 60; ai ALPHA 2; kill allies; get allies.alive; kill player; get debris.free_sets; wait 300; quit' \
    || smoke_status=1
expect_line "${log}" "[console] ALPHA 2 (idle) at 60 m" || smoke_status=1
expect_line "${log}" "[console] allies.alive = 1" || smoke_status=1
expect_line "${log}" "[console] allies.pool_size = 4" || smoke_status=1
expect_line "${log}" "[console] ALPHA 2 destroyed" || smoke_status=1
expect_line "${log}" "[console] allies.alive = 0" || smoke_status=1
expect_line "${log}" "[console] allies.free = 4" || smoke_status=1
expect_line "${log}" "[console] waves.kills = 0" || smoke_status=1
expect_line "${log}" "[console] debris.free_sets = 3" || smoke_status=1
expect_line "${log}" "[console] ALPHA 2 (ai) at 800 m" || smoke_status=1
expect_text "${log}" "[console] ALPHA 2: " || smoke_status=1
expect_line "${log}" "[console] destroyed 1 allied ship(s)" || smoke_status=1
expect_line "${log}" "[console] debris.free_sets = 2" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: spawn ally with a raider behaviour must exit 1"
log="${REPORTS}/console_allies_strict.log"
main_run "${log}" 180 1 "bad ally behaviour" -- --console-strict \
    --console-exec='wait 30; spawn ally attack 500; quit 0' \
    || smoke_status=1
expect_text "${log}" "[console] error: an ally takes idle or ai, not attack" || smoke_status=1
reject_text "${log}" "[console] > quit 0" || smoke_status=1

echo "== Console smoke run: faction relations and friendly fire on the real main scene"
# M3-T02 / AC2, AC3: `relation` prints and sets a pair for the session (it never writes data/factions.json), `reset`
# reloads the file, an unknown faction is an error under --console-strict, and settings.friendly_fire is the switch.
log="${REPORTS}/console_factions.log"
factions_file_before="$(sha256sum data/factions.json | cut -d' ' -f1)"
main_run "${log}" 180 0 "factions" -- --console-strict \
    --console-exec="wait 30; relation earth_alliance raiders; relation earth_alliance raiders neutral; get factions.relations; relation reset; get factions.relations; get factions.friendly_fire; set settings.friendly_fire on; get factions.friendly_fire; quit" \
    || smoke_status=1
expect_line "${log}" "[console] earth_alliance vs raiders: hostile" || smoke_status=1
expect_line "${log}" "[console] earth_alliance vs raiders: hostile -> neutral (this session)" || smoke_status=1
expect_line "${log}" "[console] factions.relations = [earth_alliance raiders neutral, narn raiders hostile, centauri raiders hostile, brakiri raiders hostile]" || smoke_status=1
expect_line "${log}" "[console] factions.relations = [earth_alliance raiders hostile, narn raiders hostile, centauri raiders hostile, brakiri raiders hostile]" || smoke_status=1
expect_line "${log}" "[console] factions.friendly_fire = false" || smoke_status=1
expect_line "${log}" "[console] factions.friendly_fire = true" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1
if [[ "$(sha256sum data/factions.json | cut -d' ' -f1)" != "${factions_file_before}" ]]; then
    echo "run_tests.sh: the relation command changed data/factions.json; session changes must stay in memory." >&2
    smoke_status=1
fi

echo "== Console smoke run: an unknown faction must exit 1"
log="${REPORTS}/console_factions_strict.log"
main_run "${log}" 180 1 "unknown faction" -- --console-strict \
    --console-exec="wait 30; relation pirates raiders; quit 0" \
    || smoke_status=1
expect_text "${log}" "[console] error: unknown faction 'pirates'" || smoke_status=1
reject_text "${log}" "[console] > quit 0" || smoke_status=1

echo "== Console smoke run: an AiPilot raider and the ai provider and command on the real main scene"
# M3-T06 / AC13: `spawn raider ai` flies the raider profile; `ai.ships`, `ai.by_behaviour`, `ai.think_us` and `ai <name>`
# (the pilot's behaviour, state and every behaviour's score) answer under --console-strict. M3-T17: `ai <name> objective
# <target|none>` sets and clears the pilot's objective; the buoys broadcast, so NAV ALPHA is a candidate.
log="${REPORTS}/console_ai.log"
main_run "${log}" 180 0 "ai" -- --console-strict \
    --console-exec='wait 30; wave stop; god on; despawn all; spawn raider ai 1500; wait 120; get ai.ships; get ai.by_behaviour; get ai.think_us; ai RAIDER 1; ai RAIDER 1 objective nav alpha; wait 10; ai RAIDER 1; ai RAIDER 1 objective none; quit' \
    || smoke_status=1
expect_line "${log}" "[console] RAIDER 1 (ai) at 1500 m" || smoke_status=1
expect_text "${log}" "[console] ai.ships = [RAIDER 1 attack (" || smoke_status=1
expect_line "${log}" "[console] ai.by_behaviour = {attack: 1}" || smoke_status=1
expect_text "${log}" "[console] ai.think_us = " || smoke_status=1
expect_text "${log}" "[console] RAIDER 1: attack (" || smoke_status=1
expect_text "${log}" "[console]   scores: ram 0.00, retreat 0.00, evade " || smoke_status=1
expect_line "${log}" "[console] RAIDER 1: objective NAV ALPHA" || smoke_status=1
expect_text "${log}" "objective NAV ALPHA" || smoke_status=1
expect_line "${log}" "[console] RAIDER 1: no objective" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: ai with an unknown ship must exit 1"
log="${REPORTS}/console_ai_strict.log"
main_run "${log}" 180 1 "unknown ai ship" -- --console-strict \
    --console-exec='wait 30; ai NOBODY; quit 0' \
    || smoke_status=1
expect_text "${log}" "[console] error: no AI ship named 'NOBODY'" || smoke_status=1
reject_text "${log}" "[console] > quit 0" || smoke_status=1

echo "== Console smoke run: the wing provider and command on the real main scene"
# M3-T07 / AC11, AC13: the player leads wing ALPHA, whose three wingmen the sandbox places at load (M3-T10); `wing order form`
# is acknowledged with one line by the first of them and `wing formation wedge` changes the shape, under --console-strict.
log="${REPORTS}/console_wing.log"
main_run "${log}" 180 0 "wing" -- --console-strict \
    --console-exec='wait 30; wing order form; wing formation wedge; get wing.order; get wing.formation; get wing.last_ack; wing; quit' \
    || smoke_status=1
expect_line "${log}" "[console] ALPHA 2: COPY, FORMING UP" || smoke_status=1
expect_line "${log}" "[console] ALPHA formation: finger_four -> wedge" || smoke_status=1
expect_line "${log}" "[console] wing.order = form" || smoke_status=1
expect_line "${log}" "[console] wing.formation = wedge" || smoke_status=1
expect_line "${log}" "[console] wing.last_ack = ALPHA 2: COPY, FORMING UP" || smoke_status=1
expect_line "${log}" "[console] ALPHA: order form, formation wedge, members ALPHA 2, ALPHA 3, ALPHA 4" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: a bad wing order must exit 1"
log="${REPORTS}/console_wing_strict.log"
main_run "${log}" 180 1 "bad wing order" -- --console-strict \
    --console-exec='wait 30; wing order dance; quit 0' \
    || smoke_status=1
expect_text "${log}" "[console] error: wing order expects one of attack|form|engage|cover, got 'dance'" || smoke_status=1
reject_text "${log}" "[console] > quit 0" || smoke_status=1

echo "== Console smoke run: wing replenish launches the wingmen on the real main scene"
# M3-T08 / AC11: `wing replenish` gives the empty wing its three wingmen (ALPHA 2-4, 1 500 m astern) on the wing's order; after
# `kill allies` it launches them again, and with a full wing it says so. The sandbox's own wingmen (M3-T10) are parked first
# (`despawn all`). Waits before it quits (the explosions' sounds).
log="${REPORTS}/console_wing_replenish.log"
main_run "${log}" 180 0 "wing replenish" -- --console-strict \
    --console-exec='wait 30; wave stop; despawn all; wait 2; wing replenish; get allies.alive; wing order engage; kill allies; wing replenish; get allies.alive; wing replenish; wait 300; quit' \
    || smoke_status=1
launched_lines="$(grep -cxF -- "[console] ALPHA: launched ALPHA 2, ALPHA 3, ALPHA 4 (1500 m astern)" "${log}" || true)"
if (( launched_lines != 2 )); then
    echo "run_tests.sh: expected the wing to be launched twice, saw ${launched_lines} launch lines (see ${log})." >&2
    smoke_status=1
fi
expect_line "${log}" "[console] allies.alive = 3" || smoke_status=1
expect_line "${log}" "[console] ALPHA 2: COPY, ENGAGING AT WILL" || smoke_status=1
expect_line "${log}" "[console] ALPHA: no empty slot" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: the dogfight scenario loads its three wings on the real main scene"
# M3-T10 / AC12: `scenario dogfight` places wing ALPHA (four allies led by ALPHA 2, engage at will) and raider groups RED and BLUE.
log="${REPORTS}/console_dogfight.log"
main_run "${log}" 180 0 "dogfight" -- --console-strict \
    --console-exec='wait 30; scenario dogfight; wait 120; get allies.alive; get raiders.alive; wing; quit' \
    || smoke_status=1
expect_line "${log}" "[console] allies.alive = 4" || smoke_status=1
expect_line "${log}" "[console] raiders.alive = 6" || smoke_status=1
expect_line "${log}" "[console] ALPHA: order engage, formation finger_four, members ALPHA 3, ALPHA 4, ALPHA 5" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: the instructor leads the route on the real main scene"
# M3-T09 / AC10, AC13: `scenario instructor_route` brings in the instructor; `state` lists `route` beside the other providers,
# and the instructor leads the first leg (`route.*`, `ai INSTRUCTOR`) under --console-strict.
log="${REPORTS}/console_route.log"
main_run "${log}" 240 0 "instructor route" -- --console-strict \
    --console-exec='wait 30; scenario instructor_route; wait 300; state; state route; ai INSTRUCTOR; quit' \
    || smoke_status=1
expect_providers "${log}" "ai, allies, audio, camera, combat, controls, debris, debug, factions, flight, fx, game, hud, hull, input, lights, livery, perf, post, raiders, ram, render, route, screens, settings, ship, sky, targeting, time, waves, weapons, wing, world" \
    || smoke_status=1
expect_line "${log}" "[console] route.index = 1" || smoke_status=1
expect_line "${log}" "[console] route.count = 6" || smoke_status=1
expect_line "${log}" "[console] route.state = lead" || smoke_status=1
expect_line "${log}" "[console] route.demo = none" || smoke_status=1
expect_text "${log}" "[console] INSTRUCTOR: follow_path (lead)" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: the visual pass's commands and settings on the real main scene"
# M3-T12 / AC13: the commands added since T19 answer under --console-strict; the renderer's own numbers need a GPU, so only the
# switches are checked here.
log="${REPORTS}/console_visual.log"
main_run "${log}" 180 0 "visual pass" -- --console-strict \
    --console-exec='wait 30; wave stop; flare off; flare on; blur on; blur off; set settings.particle_density 0.5; get fx.density; running_lights off; get ship.running_lights; running_lights on; look 170 10; look off; state lights; state render; state post; state screens; quit' \
    || smoke_status=1
expect_line "${log}" "[console] fx.density = 0.50" || smoke_status=1
expect_line "${log}" "[console] ship.running_lights = false" || smoke_status=1
expect_line "${log}" "[console] the view held at yaw 170, pitch 10" || smoke_status=1
expect_line "${log}" "[console] the view is free again" || smoke_status=1
expect_text "${log}" "[console] lights.active = " || smoke_status=1
expect_text "${log}" "[console] render.far_dots = " || smoke_status=1
expect_text "${log}" "[console] screens.shown = " || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: a bad look must exit 1"
log="${REPORTS}/console_visual_strict.log"
main_run "${log}" 180 1 "bad look" -- --console-strict \
    --console-exec='wait 30; look north; quit 0' \
    || smoke_status=1
expect_text "${log}" "[console] error: look takes yaw and pitch in degrees, or off, not 'north'" || smoke_status=1
reject_text "${log}" "[console] > quit 0" || smoke_status=1

echo "== Console smoke run: the benchmark harness writes its report on the real main scene"
# M4-T01 / AC1: `bench furball 25 5` flies 25 ships from the pools for 5 s after a second of warm-up and writes
# reports/perf/smoke/; only that the report is there is checked, never its numbers (they are scripts/bench.sh's job). `quit`
# waits for the run, and the probe is off again afterwards.
log="${REPORTS}/console_bench.log"
bench_dir="${REPORTS}/perf/smoke"
rm -rf "${bench_dir}"
touch "${REPORTS}/.gdignore"
main_run "${log}" 300 0 "bench" -- --console-strict \
    --console-exec='wait 30; bench furball 25 5 warmup=1 label=smoke; get perf.enabled; get perf.tick_us; quit' \
    || smoke_status=1
expect_text "${log}" "[console] bench furball 25: 25 ships in play" || smoke_status=1
expect_text "${log}" "[bench] furball 25 seed 1: tick median " || smoke_status=1
expect_line "${log}" "[console] perf.enabled = false" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "SCRIPT ERROR" || smoke_status=1
for report_file in summary.json summary.md; do
    if [[ ! -s "${bench_dir}/${report_file}" ]]; then
        echo "run_tests.sh: the bench smoke run did not write ${bench_dir}/${report_file}." >&2
        smoke_status=1
    fi
done
for key in '"stages"' '"tick"' '"verdict"' '"machine"' '"lag"'; do
    grep -qF -- "${key}" "${bench_dir}/summary.json" 2> /dev/null \
        || { echo "run_tests.sh: ${bench_dir}/summary.json lacks ${key}." >&2; smoke_status=1; }
done
echo "== Console smoke run: --scenario=free_flight still goes straight to Main without a window (M5-T01)"
# AC1 (D50): boot.tscn is the main scene now; a scripted run skips the front end, and the startup script runs once Main is
# ready, so even its first statement (no wait) finds Main's providers.
log="${REPORTS}/console_boot.log"
main_run "${log}" 180 0 "boot" -- --scenario=free_flight --console-strict \
    --console-exec="get game.state; get game.request; get settings.scenario; get raiders.pool_size; get ship.assist_on; quit" \
    || smoke_status=1
expect_line "${log}" "[console] game.state = in_space" || smoke_status=1
expect_line "${log}" "[console] game.request = free_flight (free_flight), encounters off, seed 0" || smoke_status=1
expect_line "${log}" "[console] settings.scenario = free_flight" || smoke_status=1
expect_line "${log}" "[console] raiders.pool_size = 0" || smoke_status=1
expect_line "${log}" "[console] ship.assist_on = true" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: menu, play and the game provider under --console-strict (M5-T01)"
# AC1, AC2 (D50): `menu` shows the front end, `play` goes through the loading screen into Main with the request's scenario
# and seed, and a scenario that does not exist is refused.
log="${REPORTS}/console_game.log"
main_run "${log}" 240 0 "game flow" -- --scenario=free_flight --console-strict \
    --console-exec="menu; wait 5; get game.state; play instructor_route 7; get game.state; wait 600; get game.state; get game.request; get game.last_result; get allies.pool_size; quit" \
    || smoke_status=1
expect_line "${log}" "[console] front end" || smoke_status=1
expect_line "${log}" "[console] game.state = front_end" || smoke_status=1
expect_line "${log}" "[console] loading instructor_route (sandbox), encounters off, seed 7" || smoke_status=1
expect_line "${log}" "[console] game.state = loading" || smoke_status=1
expect_line "${log}" "[console] game.state = in_space" || smoke_status=1
expect_line "${log}" "[console] game.request = instructor_route (sandbox), encounters off, seed 7" || smoke_status=1
expect_line "${log}" "[console] game.last_result = none" || smoke_status=1
expect_line "${log}" "[console] allies.pool_size = 1" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1

echo "== Console smoke run: play of a scenario that does not exist must exit 1 (M5-T01)"
log="${REPORTS}/console_game_strict.log"
main_run "${log}" 180 1 "bad play" -- --scenario=free_flight --console-strict \
    --console-exec="play nowhere; quit 0" \
    || smoke_status=1
expect_text "${log}" "[console] error: <scenario_id> expects one of " || smoke_status=1
reject_text "${log}" "[console] > quit 0" || smoke_status=1

echo "== Console smoke run: from the front end, Main loads cleanly through the loading screen (M5-T01)"
# AC2 (D50): the front end named on the command line, so Main is first loaded by the loading screen's worker thread, as on
# a windowed launch. Nothing may leak at exit (scripts compile on the main thread first; see architecture §18.3).
log="${REPORTS}/console_loading.log"
main_run "${log}" 180 0 "loading" res://src/frontend/front_end.tscn -- --console-strict \
    --console-exec="get game.state; play free_flight; wait 300; get game.state; get raiders.pool_size; quit" \
    || smoke_status=1
expect_line "${log}" "[console] game.state = front_end" || smoke_status=1
expect_line "${log}" "[console] game.state = in_space" || smoke_status=1
expect_line "${log}" "[console] raiders.pool_size = 0" || smoke_status=1
reject_text "${log}" "[console] error:" || smoke_status=1
reject_text "${log}" "ERROR:" || smoke_status=1
reject_text "${log}" "leaked" || smoke_status=1

if (( smoke_status != 0 )); then
    echo "run_tests.sh: console smoke runs failed (see reports/console_*.log)."  >&2
fi
if (( gut_status != 0 )); then
    exit "${gut_status}"
fi
if (( smoke_status == 0 )); then
    echo "run_tests.sh --${mode}: passed in $(( SECONDS - started )) s."
fi
exit "${smoke_status}"
