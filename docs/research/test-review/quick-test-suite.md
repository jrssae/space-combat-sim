# Quick test suite (for an implementing agent)

A fast suite that touches every major area of the game, for agents and the maintainer to run between changes.
`scripts/run_tests.sh` stays the full gate before a merge. This list was **trial-run on 2026-11-09** (branch `m5`,
`5c65d81`, maintainer's machine, generated assets present): everything passed.

| Piece | Measured | Full suite equivalent |
| --- | ---: | ---: |
| Compile check (`scripts/check_scripts.gd`) | 20 s | same |
| Rust kernel tests (`cargo test --release --lib`, warm) | 0.2 s (72 s cold) | not run at all today |
| Python, 20 files (292 tests) | 14 s | 48.6 min (713 tests) |
| GUT, 99 files (1,571 of 3,299 tests), one process, `GUT_SLOW=0` | 162 s | about 40-65 min |
| Console smokes: the console host + the real main scene | 5 s + 7 s | 12 runs, several minutes |
| **Total** | **about 3.5 min** | **about 90 min** |

Timings for every file are in `docs/research/test-review/timings.md`. Removal candidates are in
`docs/research/test-review/removal-candidates.md`; if those removals land first, update the list below (see "Interplay").

## What to build

1. **`tests/quick_suite.txt`**: one GUT script path per line (`res://tests/...gd`), `#` comments allowed, grouped by
   area as below. A data file, so adding a test to the quick suite is a one-line change.
2. **`scripts/run_quick_tests.sh`**, modelled on `scripts/run_tests.sh` (reuse its `fail`, `run_logged`,
   `console_run`, `expect_line` helpers by copying them, or move them into a sourced `scripts/lib_tests.sh`; do not
   change what `run_tests.sh` checks). In order, stopping at the first failure:
   1. `scripts/build_native.sh` (the library is required; it is a no-op when up to date).
   2. Compile check: `godot --headless --path . -s res://scripts/check_scripts.gd`, grep for the same
      `SCRIPT ERROR|Parse Error|Failed to load script` pattern. Keep this: GUT skips a file that does not parse, so
      without it a broken test file passes silently.
   3. `cargo test --release --lib` in `native/` with `CARGO_TARGET_DIR` as `build_native.sh` sets it
      (`.tools/native-target`); skip with a message if `cargo` is missing.
   4. Python: `python3 -m unittest <modules>` with the module list below. Use `.venv/bin/python` when it exists
      (the system `python3` on the maintainer's machine has no NumPy; every Python test failed to import with it).
   5. GUT: `GUT_SLOW=0 godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=<comma-joined list> -gexit
      -gjunit_xml_file=reports/gut_quick.xml`, the list read from `tests/quick_suite.txt` (skip blank and `#` lines;
      fail if a listed file does not exist). Timeout 600 s.
   6. Two console smokes, copied from `run_tests.sh`: "strict script that succeeds" on
      `res://tests/fixtures/console_host.tscn`, and "the real main scene" (`wait 30; state; state ship; get
      render.renderer; quit`, with its `expect_providers` and `ship.assist_on` checks).
   - No Godot `--import` step: it is needed only after assets change. Print a hint to run `scripts/gen_assets.sh` and
     `run_tests.sh` when `assets/generated/` is missing or older than `tools/procgen/`.
   - Logs go to `reports/quick_*.log`; clear only those at start, not `run_tests.sh`'s logs.
3. **A guard test** (pure, so it can sit in the quick list itself): `tests/unit/test_quick_suite.gd`, checking that
   every path in `tests/quick_suite.txt` exists, names a `test_*.gd`, appears once, and is not a SLOW file
   (`SlowTests` users) or a GPU-only file (`*_gpu.gd`).
4. **Docs**: add `scripts/run_quick_tests.sh` to the Commands block of `CLAUDE.md` and to the tests section of
   `docs/architecture.md`, saying it is for iteration and that `run_tests.sh` stays the gate. Do not edit `README.md`
   (maintainer-owned).
5. **Task bookkeeping** (CLAUDE.md): this needs a task row in the current milestone file on branch `m5`, status
   `in progress` in the first commit, and commit subjects starting with that task id. Ask the maintainer for the id.

## The GUT list, by area

Each area has its pure logic plus, where one exists, one in-scene test proving the wiring.

**Flight model (Newtonian, assist, governor, fuel)**: `unit/test_flight_model`, `unit/test_flight_assist`,
`unit/test_flight_model_propellant`, `unit/test_speed_governor`, `unit/test_fuel_tank`, `unit/test_thruster_layout`,
`unit/test_hardpoints`, `integration/test_flight_batch` (batched ships in Jolt, with its damping guard),
`unit/test_smoke` (the project's zero gravity and zero damping).

**Native core, parity and guards**: `unit/test_sim_core` (holds the required engine-free guard
`test_the_kernels_hold_no_engine_type`), `unit/test_native_required`, `unit/test_flight_step` (native flight step vs
`FlightModel`, bit for bit), `unit/test_contact_field`, `unit/test_hit_broad_phase`, `unit/test_pilot_kernels`,
`unit/test_brain_parity`, `unit/test_sweep_cells`, `unit/test_missile_kernel`, `unit/test_mine_kernel`,
`unit/test_tier`, `unit/test_parity_fixture`.

**Threads (1 vs 6 identical) and the seeded battle**: `unit/test_core_state` (21 s, the slowest file in the list:
the seeded 120-ship battle against its recordings, 1 vs 6 threads, the melee's rams).

**Input and controls**: `unit/test_input_adapter`, `unit/test_input_map`, `unit/test_control_profile`,
`unit/test_godot_input_source`, `unit/test_trigger_calibration`, `unit/test_binding_capture`,
`unit/test_controls_model`.

**Console, settings, info.md**: `unit/test_console_registry`, `unit/test_console_tokenizer`,
`unit/test_console_completer`, `unit/test_settings_schema`, `unit/test_settings`, `unit/test_settings_menu_model`,
`integration/test_debug_console`, `integration/test_console_command_list`, `integration/test_info_md`.

**Weapons, hits, damage, rams**: `unit/test_pulse_cannon_gate`, `unit/test_pulse_cannon_capacitor`,
`unit/test_weapon_capacitor`, `unit/test_hull_health`, `unit/test_hit_shape`, `unit/test_intercept_math`,
`unit/test_ram_math`, `unit/test_ram_tracker`, `unit/test_damage_zones`, `integration/test_hit_resolver`,
`integration/test_damage`, `integration/test_friendly_fire`, `integration/test_ram_scale`.

**Ships, pools, destruction**: `unit/test_ship_catalog`, `integration/test_ship_scene`, `integration/test_ship_pool`,
`integration/test_multi_ship`, `integration/test_starfury_breakup`, `integration/test_debris_pool`.

**Targeting and HUD**: `unit/test_targeting_system`, `unit/test_hud_layout`, `unit/test_radar_model`,
`integration/test_targeting_controller`, `integration/test_hud`.

**AI and wings**: `unit/test_ai_pilot_selection`, `unit/test_attack_brain_states`, `unit/test_avoidance_math`,
`unit/test_fire_lane`, `unit/test_pilot_steering`, `unit/test_formation`, `unit/test_wing`, `unit/test_ai_profile`,
`unit/test_brain_factory`, `integration/test_ai_driver` (13 s), `integration/test_ai_think_rate`,
`integration/test_wing_orders`.

**Factions**: `unit/test_faction_table`.

**World, rebase, universe positions**: `unit/test_universe_pos`, `unit/test_sim_clock`, `integration/test_world_frame`,
`integration/test_every_world_core`.

**Missions, dialog, scenarios**: `unit/test_scenario_loader`, `unit/test_mission_sequencer`, `unit/test_triggers`,
`unit/test_objective_book`, `unit/test_dialog_queue`, `unit/test_dialog_ids`, `integration/test_mission_runner` (11 s).

**Waves and encounters**: `unit/test_wave_plan`, `unit/test_encounter_plan`.

**Game flow and menus**: `unit/test_game_flow`, `integration/test_boot_routing`, `integration/test_front_end`,
`integration/test_pause_menu`.

**The main scene end to end**: `integration/test_main_scene` (boot, pad input flies the ship, fire, pause, respawn,
rebase).

**Audio**: `unit/test_audio_buses`, `unit/test_engine_voices`, `integration/test_audio_director`.

**Rendering settings (headless wiring)**: `unit/test_upscaling`, `unit/test_anti_aliasing_mode`,
`integration/test_post_effects`.

**Test infrastructure**: `unit/test_slow_tests`.

The same list, ready to paste into `tests/quick_suite.txt`:

```
# Flight
res://tests/unit/test_smoke.gd
res://tests/unit/test_flight_model.gd
res://tests/unit/test_flight_assist.gd
res://tests/unit/test_flight_model_propellant.gd
res://tests/unit/test_speed_governor.gd
res://tests/unit/test_fuel_tank.gd
res://tests/unit/test_thruster_layout.gd
res://tests/unit/test_hardpoints.gd
res://tests/integration/test_flight_batch.gd
# Native core, parity, guards, threads
res://tests/unit/test_sim_core.gd
res://tests/unit/test_native_required.gd
res://tests/unit/test_flight_step.gd
res://tests/unit/test_contact_field.gd
res://tests/unit/test_hit_broad_phase.gd
res://tests/unit/test_pilot_kernels.gd
res://tests/unit/test_brain_parity.gd
res://tests/unit/test_sweep_cells.gd
res://tests/unit/test_missile_kernel.gd
res://tests/unit/test_mine_kernel.gd
res://tests/unit/test_core_state.gd
res://tests/unit/test_tier.gd
res://tests/unit/test_parity_fixture.gd
# Input and controls
res://tests/unit/test_input_adapter.gd
res://tests/unit/test_input_map.gd
res://tests/unit/test_control_profile.gd
res://tests/unit/test_godot_input_source.gd
res://tests/unit/test_trigger_calibration.gd
res://tests/unit/test_binding_capture.gd
res://tests/unit/test_controls_model.gd
# Console, settings, info.md
res://tests/unit/test_console_registry.gd
res://tests/unit/test_console_tokenizer.gd
res://tests/unit/test_console_completer.gd
res://tests/unit/test_settings_schema.gd
res://tests/unit/test_settings.gd
res://tests/unit/test_settings_menu_model.gd
res://tests/integration/test_debug_console.gd
res://tests/integration/test_console_command_list.gd
res://tests/integration/test_info_md.gd
# Weapons, hits, damage, rams
res://tests/unit/test_pulse_cannon_gate.gd
res://tests/unit/test_pulse_cannon_capacitor.gd
res://tests/unit/test_weapon_capacitor.gd
res://tests/unit/test_hull_health.gd
res://tests/unit/test_hit_shape.gd
res://tests/unit/test_intercept_math.gd
res://tests/unit/test_ram_math.gd
res://tests/unit/test_ram_tracker.gd
res://tests/unit/test_damage_zones.gd
res://tests/integration/test_hit_resolver.gd
res://tests/integration/test_damage.gd
res://tests/integration/test_friendly_fire.gd
res://tests/integration/test_ram_scale.gd
# Ships, pools, destruction
res://tests/unit/test_ship_catalog.gd
res://tests/integration/test_ship_scene.gd
res://tests/integration/test_ship_pool.gd
res://tests/integration/test_multi_ship.gd
res://tests/integration/test_starfury_breakup.gd
res://tests/integration/test_debris_pool.gd
# Targeting and HUD
res://tests/unit/test_targeting_system.gd
res://tests/unit/test_hud_layout.gd
res://tests/unit/test_radar_model.gd
res://tests/integration/test_targeting_controller.gd
res://tests/integration/test_hud.gd
# AI and wings
res://tests/unit/test_ai_pilot_selection.gd
res://tests/unit/test_attack_brain_states.gd
res://tests/unit/test_avoidance_math.gd
res://tests/unit/test_fire_lane.gd
res://tests/unit/test_pilot_steering.gd
res://tests/unit/test_formation.gd
res://tests/unit/test_wing.gd
res://tests/unit/test_ai_profile.gd
res://tests/unit/test_brain_factory.gd
res://tests/integration/test_ai_driver.gd
res://tests/integration/test_ai_think_rate.gd
res://tests/integration/test_wing_orders.gd
# Factions
res://tests/unit/test_faction_table.gd
# World and rebase
res://tests/unit/test_universe_pos.gd
res://tests/unit/test_sim_clock.gd
res://tests/integration/test_world_frame.gd
res://tests/integration/test_every_world_core.gd
# Missions, dialog, scenarios
res://tests/unit/test_scenario_loader.gd
res://tests/unit/test_mission_sequencer.gd
res://tests/unit/test_triggers.gd
res://tests/unit/test_objective_book.gd
res://tests/unit/test_dialog_queue.gd
res://tests/unit/test_dialog_ids.gd
res://tests/integration/test_mission_runner.gd
# Waves and encounters
res://tests/unit/test_wave_plan.gd
res://tests/unit/test_encounter_plan.gd
# Game flow, menus, main scene
res://tests/unit/test_game_flow.gd
res://tests/integration/test_boot_routing.gd
res://tests/integration/test_front_end.gd
res://tests/integration/test_pause_menu.gd
res://tests/integration/test_main_scene.gd
# Audio
res://tests/unit/test_audio_buses.gd
res://tests/unit/test_engine_voices.gd
res://tests/integration/test_audio_director.gd
# Rendering settings
res://tests/unit/test_upscaling.gd
res://tests/unit/test_anti_aliasing_mode.gd
res://tests/integration/test_post_effects.gd
# Test infrastructure
res://tests/unit/test_slow_tests.gd
```

## The Python list

Every file here ran alone in under 5 s; together 14 s for 292 tests. They cover the generator's core (geometry,
sampling, UV atlas, image and audio writers, the manifest, the CLI and registry), the parts library, the cockpit, the
livery and the sounds:

```
tools.procgen.tests.test_rotations tools.procgen.tests.test_wing tools.procgen.tests.test_color
tools.procgen.tests.test_image tools.procgen.tests.test_audio tools.procgen.tests.test_manifest
tools.procgen.tests.test_panorama tools.procgen.tests.test_chunks tools.procgen.tests.test_uv_atlas
tools.procgen.tests.test_geometry tools.procgen.tests.test_sfx_ui tools.procgen.tests.test_parts
tools.procgen.tests.test_refview tools.procgen.tests.test_sfx_world tools.procgen.tests.test_starfury_parts
tools.procgen.tests.test_cockpit tools.procgen.tests.test_cli tools.procgen.tests.test_sfx_combat
tools.procgen.tests.test_sampling tools.procgen.tests.test_livery
```

## Deliberately left out, and why

The quick suite does not replace `run_tests.sh`. These areas have no quick coverage; say so in the script's header
comment so nobody mistakes a green quick run for a merge gate:

- **Whole-asset Python builds**: every per-hull file, `test_textured_hulls`, `test_textured_mesh`, `test_textures`
  (26 s), `test_nav_buoy` (27 s), `test_sky_default` (60 s), `test_asteroids` and `test_render_pieces` (over 120 s
  each), `test_parallel_build`, `test_refview_compare` (20 s), `test_mesh_only` (9 s). Run them after touching
  `tools/procgen`.
- **SLOW files and long Jolt fights**: `test_turret_balance` (664 s), `test_civilian_escort` (385 s),
  `test_tier_outcomes`, `test_dogfight`, `test_brain_tolerance`, `test_m3_sandbox`, `test_rebase_in_play`, `test_ai_ram`,
  `test_tier_fire` (132 s), `test_ship_physics` (48 s; it holds the damping guard, which stays in the full run, and
  `test_flight_batch` plus `test_smoke` guard damping in the quick one), `test_sweep_math` (36 s, brute-force cross
  checks), `test_core_snapshot`, `test_core_threads`, and the other battle replays (see removal list A).
- **AI behaviour runs in Jolt** (`test_ai_attack`, `test_ai_evade`, `test_ai_formation`, ...: about 5 minutes together),
  the civilian and turret fights, the tier handover.
- **GPU files** (`*_gpu.gd`): Pending headless anyway.
- The remaining ten console smokes of `run_tests.sh` (controls, rebase, damage, destruction, combat, attack, ...).

If the 3.5 minutes is still too long for a tight loop, a "tier 0" without `test_core_state`, `test_ai_driver`,
`test_mission_runner`, `test_main_scene` and `test_flight_batch` saves about 60 s of GUT time but loses the seeded
battle, the AI driver and the in-scene mission. Offer that as an option (`--tier0`), not as the default.

## Interplay with the removal list

- C8/D3 propose deleting `test_smoke.gd` after moving its project-settings asserts into `test_ship_physics.gd`. If that
  happens, the quick suite loses its only damping check outside `test_flight_batch`. Either keep a small pure
  `test_project_settings.gd` in the quick list, or add `test_ship_physics.gd` (48 s) to it.
- D8 proposes deleting `test_info_md.gd` after a merge into `test_console_command_list.gd`: then drop it from the list.
- A1-A7 leave `test_core_state.gd` as the kept battle test, so the list does not change.
- C1/C2 port `test_ram_tracker` and `test_radar_model` to other entry points; they stay in the list.

## Check before handing back

- `scripts/run_quick_tests.sh` exits 0 on a clean `m5` checkout with generated assets, and prints its total time.
- Break one listed test on purpose (a wrong `assert_eq`), see the script fail with that file named, then revert.
- Break the parse of one listed test file, see the compile check stop the run.
- `scripts/run_tests.sh` still exits 0 and runs everything it ran before.
