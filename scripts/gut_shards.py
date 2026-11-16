#!/usr/bin/env python3
"""Split the GUT test files into CI shards.

Goal: keep every "test (GUT shard K)" job well under its 40-minute GUT timeout (scripts/run_tests.sh) while guaranteeing that
each tests/**/test_*.gd file runs in exactly one shard, so a new test file is never silently skipped. A plain "every Nth file"
split let one new file move a slow test into another shard and push it past the timeout (M7-T43); weighting by measured time
keeps the shards level whatever gets added.

Usage:
    python3 scripts/gut_shards.py files K [N]   # res:// paths of shard K, comma-separated, for GUT's -gtest (N defaults to SHARDS)
    python3 scripts/gut_shards.py matrix        # JSON list of shard numbers, for the workflow's matrix
    python3 scripts/gut_shards.py plan [N]      # every shard with its estimated time
    python3 scripts/gut_shards.py check [N]     # exit 1 unless the shards cover every test file exactly once

SHARDS is the only place the shard count lives; the workflow reads it through `matrix`. The balance files
(tests/balance_suite.txt) are ordinary test files here: they gate only their balance tests, and the rest of them runs in
whichever shard they land in, exactly as in the unsharded run.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS_DIR = ROOT / "tests"

# Seconds per file on a CI runner: each file's start to the next file's start in the GUT logs of the four shards of CI run
# 43790188947 (green, after M7-T43 sped up test_cargo_carry_clearance: 600 s to 187 s). Only the files that take 5 s or more
# need an entry; the balance is a heuristic, coverage never depends on it. A file with no entry counts as DEFAULT_WEIGHT, so a
# new heavy file lands somewhere sensible even before someone adds it here. test_grid_aim_call_sites (M7-T14) is not in that
# run: its weight is its local time.
WEIGHTS: dict[str, float] = {
    "integration/test_civilian_escort.gd": 384,
    "integration/test_freighter_cargo.gd": 365,
    "integration/test_tier_outcomes.gd": 348,
    "integration/test_jumpgate_in_play.gd": 286,
    "unit/test_cargo_carry_clearance.gd": 187,
    "integration/test_brain_tolerance.gd": 181,
    "integration/test_rebase_in_play.gd": 153,
    "unit/test_tier_fire.gd": 129,
    "integration/test_station_wing_follow.gd": 113,
    "integration/test_turret_defence.gd": 109,
    "integration/test_ai_attack.gd": 90,
    "integration/test_station_tour.gd": 79,
    "integration/test_gravity_orbit.gd": 73,
    "integration/test_station_traffic.gd": 71,
    "integration/test_ai_ram.gd": 69,
    "integration/test_station_jolt_cost.gd": 69,
    "integration/test_speed_and_autotrack.gd": 64,
    "integration/test_station_grid.gd": 54,
    "integration/test_ai_evade.gd": 53,
    "integration/test_bench.gd": 52,
    "integration/test_launch_bay.gd": 50,
    "integration/test_flight_parity_fight.gd": 49,
    "integration/test_ship_physics.gd": 49,
    "integration/test_station_in_game.gd": 46,
    "integration/test_tier_handover.gd": 45,
    "integration/test_ai_objective.gd": 41,
    "integration/test_contact_registry.gd": 38,
    "integration/test_grid_aim_call_sites.gd": 37,
    "integration/test_instructor_route.gd": 36,
    "integration/test_ai_skill.gd": 35,
    "integration/test_civilian_flight.gd": 35,
    "integration/test_turret_threads.gd": 35,
    "integration/test_heavy_cannon.gd": 32,
    "integration/test_vortex_transits.gd": 32,
    "integration/test_ai_avoidance.gd": 31,
    "integration/test_ai_slash.gd": 30,
    "integration/test_station_grid_threads.gd": 30,
    "integration/test_wave_director.gd": 30,
    "integration/test_weapon_rows_battle.gd": 30,
    "integration/test_ai_formation.gd": 28,
    "integration/test_m3_run.gd": 26,
    "unit/test_core_threads.gd": 26,
    "unit/test_core_snapshot.gd": 25,
    "integration/test_rocks_and_mines.gd": 24,
    "integration/test_ai_think_time.gd": 20,
    "integration/test_ship_lights.gd": 20,
    "integration/test_manoeuvres_jolt.gd": 19,
    "integration/test_turret_line_of_fire.gd": 18,
    "integration/test_collision_layers.gd": 17,
    "integration/test_encounters.gd": 45,
    "integration/test_station_run.gd": 60,
    "integration/test_nav_targets.gd": 17,
    "integration/test_raider_flight.gd": 17,
    "integration/test_ai_patrol.gd": 16,
    "integration/test_fx_pool.gd": 16,
    "integration/test_ai_guard.gd": 15,
    "integration/test_ram_damage.gd": 15,
    "unit/test_turret_kernel.gd": 15,
    "integration/test_civilian_attacked.gd": 14,
    "integration/test_running_lights_in_play.gd": 14,
    "integration/test_m2_run.gd": 13,
    "integration/test_ai_driver.gd": 12,
    "integration/test_controls_screen.gd": 12,
    "integration/test_station_threads.gd": 12,
    "integration/test_target_menu.gd": 11,
    "unit/test_core_state.gd": 11,
    "integration/test_brain_in_play.gd": 10,
    "integration/test_comms_menu_input.gd": 10,
    "integration/test_debrief.gd": 10,
    "integration/test_station_pools.gd": 10,
    "integration/test_thrust_smoothness.gd": 10,
    "integration/test_comms_panel.gd": 9,
    "integration/test_main_scene.gd": 9,
    "integration/test_mission_runner.gd": 9,
    "integration/test_pause_menu.gd": 9,
    "integration/test_reaction_mass.gd": 9,
    "integration/test_cinematic_camera.gd": 8,
    "integration/test_pilot_kernels_in_play.gd": 8,
    "integration/test_flight_batch.gd": 7,
    "integration/test_jump_holds.gd": 7,
    "integration/test_station_ai.gd": 7,
    "unit/test_launch_shot_clearance.gd": 7,
    "integration/test_bots_on_station.gd": 6,
    "integration/test_cockpit_screens.gd": 6,
    "integration/test_destruction.gd": 6,
    "integration/test_respawn_in_play.gd": 6,
    "integration/test_rock_bodies.gd": 6,
    "unit/test_bolt_rows.gd": 6,
    "unit/test_row_commands.gd": 6,
    "unit/test_sweep_math.gd": 6,
    "integration/test_ai_retreat.gd": 5,
    "integration/test_ai_think_rate.gd": 5,
    "integration/test_civilian_ships.gd": 5,
    "integration/test_ram_scale.gd": 5,
    "integration/test_target_preview.gd": 5,
    "integration/test_wing_orders.gd": 5,
    "unit/test_bot_crew.gd": 5,
    "unit/test_driver_step.gd": 5,
}
DEFAULT_WEIGHT = 1.0

# Shard 1 also builds and runs the Rust tests before GUT and the console smoke runs after it (scripts/run_tests.sh), about
# five minutes in the logs; it starts that far "loaded" so the whole job, not only GUT, ends level.
EXTRA_SECONDS: dict[int, float] = {1: 300}

# Four shards: three left the slowest one near 25 minutes with the 40-minute GUT timeout as the only margin; four put every
# shard near 19 minutes of GUT.
SHARDS = 4


def res_path(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def discover() -> list[str]:
    """Every test file as GUT finds it with -gdir=res://tests -ginclude_subdirs, as res:// paths, sorted."""
    return sorted(res_path(p) for p in TESTS_DIR.rglob("test_*.gd"))


def weight(path: str) -> float:
    return WEIGHTS.get(path.removeprefix("res://tests/"), DEFAULT_WEIGHT)


def assign(files: list[str], shards: int) -> list[list[str]]:
    """Heaviest file first onto the lightest shard; ties break by path, so the split is deterministic."""
    ordered = sorted(files, key=lambda f: (-weight(f), f))
    buckets: list[list[str]] = [[] for _ in range(shards)]
    loads = [EXTRA_SECONDS.get(i + 1, 0.0) for i in range(shards)]
    for path in ordered:
        lightest = min(range(shards), key=lambda i: (loads[i], i))
        buckets[lightest].append(path)
        loads[lightest] += weight(path)
    return [sorted(b) for b in buckets]


def load(bucket: list[str], shard: int) -> float:
    return EXTRA_SECONDS.get(shard, 0.0) + sum(weight(f) for f in bucket)


def problems(files: list[str], buckets: list[list[str]]) -> list[str]:
    """Empty when the buckets hold every file exactly once."""
    seen: dict[str, int] = {}
    for bucket in buckets:
        for path in bucket:
            seen[path] = seen.get(path, 0) + 1
    out = [f"{f} runs in no shard" for f in files if f not in seen]
    out += [f"{f} runs in {n} shards" for f, n in sorted(seen.items()) if n != 1]
    out += [f"{f} is not a test file" for f in sorted(seen) if f not in files]
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    files_cmd = sub.add_parser("files")
    files_cmd.add_argument("shard", type=int, help="1..N")
    files_cmd.add_argument("shards", type=int, nargs="?", default=SHARDS, help="shard count N (default SHARDS)")
    sub.add_parser("matrix")
    for name in ("plan", "check"):
        sub.add_parser(name).add_argument("shards", type=int, nargs="?", default=SHARDS)
    args = parser.parse_args(argv)

    if args.cmd == "matrix":
        print(json.dumps(list(range(1, SHARDS + 1))))
        return 0

    if args.shards < 1:
        print(f"shard count {args.shards} must be at least 1", file=sys.stderr)
        return 2
    files = discover()
    if not files:
        print(f"no test files under {TESTS_DIR}", file=sys.stderr)
        return 1
    buckets = assign(files, args.shards)

    if args.cmd == "files":
        if not 1 <= args.shard <= args.shards:
            print(f"shard {args.shard} out of range 1..{args.shards}", file=sys.stderr)
            return 2
        print(",".join(buckets[args.shard - 1]))
        return 0

    if args.cmd == "plan":
        for i, bucket in enumerate(buckets, 1):
            print(f"shard {i}/{args.shards}: ~{load(bucket, i):.0f}s, {len(bucket)} files")
            for path in sorted(bucket, key=lambda f: (-weight(f), f)):
                if path.removeprefix("res://tests/") in WEIGHTS:
                    print(f"    {path.removeprefix('res://tests/')}  ({weight(path):.0f}s)")
        return 0

    # Checked against the folder itself (a fresh walk, not the list the shards were made from).
    found = problems(discover(), buckets)
    for line in found:
        print(f"gut_shards: {line}", file=sys.stderr)
    if not found:
        print(f"gut_shards: {len(discover())} test files, each in exactly one of {args.shards} shards")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
