# Test removal candidates (for a verifying agent)

> **Applied (M6-T18, 2026-11-11, sections A to D only).** Removed or merged: A1 to A8 (one `SeededBattle` fixture; the
> 1-vs-6 battles folded into `test_core_threads`; `driver_step.json`'s far-rate case read by `test_row_commands`;
> `core_state.json`'s three identical cases now one), B1 and B2 (`test_ram_contact_columns`, `ram_contact_columns.json` and
> `test_fighter_melee` gone; `test_core_state`'s melee also pins the contact count), C1 (`RamTracker.contacts` and `Sample`),
> C2 (`RadarModel.dots`, `dot_for`, `radius_for_range`), C3 (`test_missile_guidance` on the native rows), C6 (the probe's
> distance-check tests), C8, D1, D3 (`test_smoke` is now `test_project_settings`), D4, D5, D8, D9, D10. Kept: C4, C5, D2,
> D6, D7; C7 reported. Reasons and the recording-to-test map are in `docs/milestones/m6-epsilon-space-at-true-scale.md`,
> M6-T18's Done notes. For E: E11 must keep one test that drives the explosion light through `advance` (D4 relied on
> `test_ship_lights`). Sections E to H are untouched and wait for the maintainer.

Review of every test on branch `m5` at `5c65d81` (2026-11-09): 288 GUT files (3,299 tests), 37 Python files (713 tests),
3 Rust test modules (36 tests). **Nothing here has been removed or changed.** Your job is to check each entry and remove
or merge only what holds up.

## How to read this

- **CONFIRMED**: the reviewer read the code or compared the recordings, and the duplication or dead path is real. Still
  re-check it before deleting: the branch may have moved on.
- **PLAUSIBLE**: inferred from test names, file headers and greps. Read both sides before acting. Some will turn out to
  test different wiring and should stay.
- "Remove A, keep B" always names what keeps the behaviour covered. Never remove both sides.
- Timings, where given, come from `docs/research/test-review/timings.md` (one full timed run on the maintainer's machine).

## Rules that limit what can go (CLAUDE.md)

1. **Parity recordings stay covered.** "A native change keeps its parity test against the recordings in `tests/fixtures/`
   green." Every recording in `tests/fixtures/parity/*.json` must still be read by at least one test after a removal.
   You can remove a *second* test replaying the same recording. You cannot remove the last one.
2. **The damping guard stays**: `test_ship_physics.gd` `test_damping_guard_project_and_body_settings` and
   `test_damping_guard_measured_in_jolt`.
3. **The engine-free guard stays**: `test_sim_core.gd` `test_the_kernels_hold_no_engine_type` (and the sibling
   `*_holds_no_engine_type` tests, which guard other kernel files).
4. **1 and 6 threads identical, `threaded` equal to `delayed`** (architecture §17): at least one test of each must stay
   for the AI step, and one per subsystem that has its own threading (turrets, civilians, tier).
5. Removing a test is a test-only change, but it is still a task: it needs a task id, a row in the current milestone's
   task table (`docs/milestones/`, on branch `m5`) and a commit subject starting with that id. Ask the maintainer which
   task it belongs to.

## How to verify an entry

1. Read both tests in full, including `before_each` and the helpers they call.
2. List the assertions the candidate makes that the kept test does not. If there are any, either move them into the kept
   test first or keep the candidate.
3. For "tests code production never calls": re-run the grep given in the entry, on `src/` only, and check `.tscn`/`.tres`
   files too.
4. After removing, run the kept file alone and then `scripts/run_tests.sh`. Both must exit 0.
5. If you remove a source function that only tests called, update its doc comments, `docs/architecture.md` mentions and
   `info.md` if a console command is involved.

---

## A. The same seeded battle replayed by six unit files (CONFIRMED, biggest win)

Six files each carry their own copy (about 100 lines) of `_battle(...)`: `BenchLayout.BATTLE`, 120 ships, seed 1,
240 ticks (600 in `test_core_threads`). Each was written to compare a new native path against the old path it replaced.
M4-T37 removed every old path and its switch, so they all run the same code now. The recordings prove it. These digests
are byte-identical across files:

| Digest (first chars) | Recorded in |
| --- | --- |
| hits `b94b8b3793` | `bolt_rows.json:battle_with_bolt_nodes`, `core_state.json` (all three `battle_without_*` cases), `driver_step.json:battle_far_rate` |
| commands `a3c263839b` | `core_state.json` (all three cases), `driver_step.json:battle_far_rate` |
| rows `982f6ac7aa` | `core_state.json`, all three cases |
| rows `4c06a6c7ea` | `driver_step.json:battle_far_rate`, `row_commands.json:battle_with_commands_from_the_drivers` |

(Check: `python3` over `tests/fixtures/parity/*.json`, group string values of 16+ characters by value.)

Candidates:

| # | Remove | Keep | Note |
| --- | --- | --- | --- |
| A1 | `test_core_state.gd` `test_one_thread_and_six_give_the_same_battle_with_everything_on` | `test_core_threads.gd` `test_a_seeded_battle_gives_the_same_rows_byte_for_byte_with_one_thread_and_six` (600 ticks, same layout and seed) | Two battles each. Check the 600-tick run also digests hits; if not, add hits to it first. |
| A2 | `test_bolt_rows.gd` `test_one_thread_and_six_give_the_same_bolts` | A1's kept test | Only if the kept test's digest includes the bolt rows; else add a bolt digest to it. |
| A3 | `test_row_commands.gd` `test_one_thread_and_six_give_the_same_commands_from_rows` | A1's kept test | Same: make sure commands are in the kept digest. |
| A4 | `test_driver_step.gd` `test_one_thread_and_six_give_the_same_hosted_battle` | A1's kept test | The hosted step is always on now. |
| A5 | `test_driver_step.gd` `test_the_hosted_step_flies_the_same_battle_at_the_far_rate` | `test_core_state.gd` `test_the_battle_flies_as_each_old_path_did` | Same hits and commands digests. The `rows` digest (`4c06…`) differs from core_state's because the digest covers different columns. Keep `driver_step.json:battle_far_rate` read by `test_row_commands.gd` (same rows digest), or fold its `pilots` digest into the kept test. Rule 1 applies. |
| A6 | `test_row_commands.gd` `test_commands_from_rows_fly_the_same_battle_as_today` **or** A5, not both | the other one | They pin the same `rows` digest. |
| A7 | In `test_core_state.gd` `test_the_battle_flies_as_each_old_path_did`, the loop over three identical recordings | one case | One battle, the same assert three times. Merge the three fixture entries into one (re-record is not needed: the values are identical). |
| A8 | The six private `_battle` helpers | one shared fixture, e.g. `tests/fixtures/seeded_battle.gd` | Not a removal, but it makes A1-A7 safe and removes about 500 duplicated lines. |

Measured file times (timed run): `test_core_snapshot` 36 s, `test_core_threads` 30 s, `test_core_state` 23 s,
`test_driver_step` 20 s, `test_row_commands` 18 s, `test_bolt_rows` 16 s. Together that is about 2.4 minutes, and A1-A6
remove roughly half of it.

Keep in every case: `test_core_snapshot.gd` (`threaded` equal to `delayed`, deadline and panic handling), the
domain-specific 1-vs-6 tests (`test_civilian_flight`, `test_turret_threads`, `test_tier_fire`, `test_tier_handover`),
`test_driver_step.gd` `test_the_hosted_step_flies_the_same_battle_with_near_and_far_ships` (its own recording).

## B. The same 4 s melee pinned three times (CONFIRMED)

`test_fighter_melee.gd` `test_digest`, `test_ram_contact_columns.gd` `test_the_melee_rams_the_same_with_the_contacts_in_columns`
and `test_core_state.gd` `test_the_melee_rams_the_same_with_the_contacts_read_natively` all fly T14's eight-fighter melee
in a fresh physics space and compare a digest. `core_state.json:melee_rams/poses` and
`ram_contact_columns.json:melee_rams_from_samples/poses` are the same value (`43c4b758ff…`).

- B1: remove `test_ram_contact_columns.gd` (whole file, one test). Keep `test_core_state.gd`'s melee test, which reads an
  identical recording. Rule 1: `ram_contact_columns.json` is then unread; delete it in the same change.
- B2: check whether `test_fighter_melee.gd` (hard-coded SHA `505025d7…`, plus contact and ram counts) pins anything the
  core_state recording does not. If the two digests cover the same lines, keep one of them.

## C. Tests of code production never calls (CONFIRMED by grep of `src/`)

These test a GDScript reference or wrapper that the game itself does not use. Either retarget the tests at the
production path and delete the reference, or accept the reference as a test oracle and say so in its doc comment.

| # | Code | Production calls | Tests | Suggestion |
| --- | --- | --- | --- | --- |
| C1 | `RamTracker.contacts(samples, delta)` (`src/combat/ram_tracker.gd:114`) | none; `RamResolver` calls only `contacts_columns` (`ram_resolver.gd:336`) | `test_ram_tracker.gd` (19 tests drive `contacts`), `test_ram_tracker_columns.gd` (proves columns equal samples) | Port `test_ram_tracker.gd` to `contacts_columns` (build columns from the samples, as `test_ram_tracker_columns` already does), then delete `contacts()`, `Sample`, and `test_ram_tracker_columns.gd`. |
| C2 | `RadarModel.dots(...)` (`src/hud/radar_model.gd:81`) | none; `HudLayout` calls `RadarModel.plot` | `test_radar_model.gd` (most of its 13 tests), `test_radar_plot.gd` (plot equals dots) | Port `test_radar_model` to `plot()`; then `dots()` and the equivalence test can go. |
| C3 | `MissileStandin.steer(...)` (`src/perf/standins/missile_standin.gd:84`) | none; missiles steer through `ScsWeaponRows` | `test_missile_guidance.gd` (all 7 tests run the GDScript maths), `test_missile_kernel.gd` (native vs `steer`) | `test_missile_guidance` tests a reference, not the game. Keep `test_missile_kernel`. Either delete `test_missile_guidance` or point its scenarios at the native rows. The stand-in is bench-only anyway (its own doc comment). |
| C4 | `AvoidanceMath.filter(...)` and `FireLane.clear(...)` | none for `filter`; `clear` only through `clear_seen`'s off-rows branch | `test_avoidance_math.gd` (18), `test_fire_lane.gd` (9) | Low priority: both wrappers go through the same native kernel, so the tests still test production maths. Optional: switch the tests to `filter_seen` / `clear_seen` and delete `filter`. |
| C5 | `StarPointMath` (`src/environment/star_point_math.gd`) | none (only its own file mentions it; the shader does the work) | `test_star_point_math.gd` (10) | A CPU mirror of `star_point.gdshader`, kept in step by `test_the_shader_uses_the_same_constants`. Maintainer's call: it is a design oracle. If kept, nothing to do. |
| C6 | `NativeProbe.in_range` and the boundary bench | the bench tool `src/perf/native_boundary_bench.gd`; `PerfProbe` uses only `NATIVE_CLASS` and `path()` | `test_native_probe.gd` (5) | Keep `test_the_probe_takes_the_native_path`. The distance-check tests exercise an M4-T05a experiment. `test_native_required.gd` already covers "the library is loaded". |
| C7 | `PlaceholderScreen` (`src/frontend/placeholder_screen.gd`) | nothing references the class or its file | none | Not a test issue: dead source to report to the maintainer. |
| C8 | `test_smoke.gd` `test_runner_works` | n/a | `assert_true(true)` | Remove: any other test proves the runner works. Keep `test_newtonian_project_settings` (see D3). |

## D. The same assertion in two or more places (CONFIRMED)

| # | Remove | Keep | Evidence |
| --- | --- | --- | --- |
| D1 | `test_reaction_mass.gd` `test_fuel_unlimited_defaults_to_true` (schema half) | `test_settings_schema.gd` `test_fuel_unlimited_is_a_bool_that_defaults_to_true` | Both assert the schema default. Keep the integration file's `ship.get_fuel_tank().unlimited` line by moving it into `test_the_tank_is_built_from_the_ship_spec_and_starts_full`. |
| D2 | `test_fx_specs.gd` `test_every_process_material_is_newtonian` **or** the FxSpecs loop in `test_ship_physics.gd` `test_damping_guard_project_and_body_settings` (lines 511-517) | `test_fx_pool.gd` `test_every_process_material_has_zero_gravity_and_zero_damping` (checks the built emitters, which is stronger) | Three loops over `FxSpecs.COUNT` asserting gravity 0 and damping 0. Rule 2: do not touch the damping guard test's own body asserts; only its particle loop is the duplicate. |
| D3 | merge `test_smoke.gd` `test_newtonian_project_settings` into the damping guard | `test_ship_physics.gd` `test_damping_guard_project_and_body_settings` | Same three project settings. The smoke test also checks `physics_engine == "Jolt Physics"`: move that line, then drop the smoke test (with C8, the file goes). |
| D4 | `test_explosion.gd` `test_the_light_peaks_at_8_and_is_out_by_a_quarter_second` | `test_light_emitters.gd` `test_the_explosion_light_is_a_triangle_up_to_8_and_out_by_a_quarter_second` | Same curve; the integration one goes through `advance`, so check it is the only test of `advance` driving `emitter.energy` before removing. |
| D5 | `test_factions.gd` `test_relation_is_symmetric`, `test_same_faction_is_friendly`, `test_unknown_faction_is_neutral_against_everyone_else`, `test_the_built_in_rule_matches_the_shipped_file_for_every_query` | `test_faction_table.gd` `test_listed_pairs_are_symmetric`, `test_same_faction_is_friendly_even_when_unlisted`, `test_an_unknown_id_is_neutral_to_everything_but_itself_whatever_the_default`, `test_the_shipped_file_is_the_built_in_m2_rule` | `Factions` is a facade over the active `FactionTable`. Keep the facade tests that are about the facade (lazy load, `use_table`, reset, HUD colours). |
| D6 | `test_damage.gd` `test_the_acceptance_script_prints_300_then_250` | the "god mode and damage" console smoke in `scripts/run_tests.sh` | Identical commands and expected lines. Keep one. The smoke is the AC's own script; the GUT copy runs on every focused run, so keep whichever the maintainer prefers. |
| D7 | `test_lod_switcher_math.gd` (one test) **or** `test_far_dots.gd` `test_the_dot_holds_until_the_ship_is_a_tenth_inside` | the other | Same 90 % hysteresis. The pure one is far cheaper; keep it for the quick suite and drop the scene one if the rest of `test_far_dots` covers the dot wiring. |
| D8 | `test_info_md.gd` (2 tests), after a merge | `test_console_command_list.gd` | Not a straight duplicate: `test_console_command_list` boots free flight, a mission, the route and the front end, but **not** `combat_sandbox`, which `test_info_md` boots for the AI and flight-batch entries. Add `_in_flight("sandbox", ScenarioLoader.SANDBOX_PATH)` to `_collect()`, then delete `test_info_md.gd`. |
| D9 | Schema checks inside scene-booting integration files: `test_audio_director.gd` `test_sfx_volume_is_a_schema_entry`, `test_hud.gd` `test_the_hud_settings_are_schema_entries`, `test_engine_audio.gd` `test_engine_voice_cap_is_a_schema_entry`, `test_friendly_fire.gd` `test_friendly_fire_is_a_setting_that_defaults_off`, `test_fx_pool.gd` `test_the_schema_has_particle_density_as_a_unit_range`, `test_ram_damage.gd` `test_the_ram_damage_setting_is_a_bool_that_defaults_on`, `test_post_effects.gd` `test_strength_is_a_unit_range_setting` | `test_settings_schema.gd` | Each pays its file's `before_each` (often a full scene) to read a schema entry. Move any assert `test_settings_schema` lacks into it, then remove. |
| D10 | `test_sim_clock.gd` `test_autoload_is_registered` | `test_debug_console.gd` `test_autoload_is_registered_after_sim_clock_and_always_processes` | Check the latter asserts SimClock's presence, not only its order. |

## E. Overlaps found from names and headers (PLAUSIBLE: read both sides)

Weapons and combat:

- E1 `test_weapons.gd`: `test_alternating_fires_four_hertz_from_alternating_muzzles`, `test_linked_fires_two_hertz_from_both_muzzles_together`,
  `test_switching_mode_while_firing_never_raises_the_rate_of_fire`, `test_the_cooldown_carries_over_a_mode_switch`,
  `test_a_four_muzzle_cannon_cycles_all_four_muzzles`, `test_a_linked_four_muzzle_cannon_fires_all_four_every_four_intervals`
  repeat `test_pulse_cannon_gate.gd`'s rate rules through the cannon. Keep one integration test that proves the cannon
  uses the gate (alternating 4 Hz from its own muzzles); the rest are the gate's.
- E2 `test_weapon_charge.gd` `test_a_two_second_burst_is_the_m1_rate`, `test_sustained_fire_is_limited` vs
  `test_pulse_cannon_capacitor.gd` `test_alternating_burst_of_two_seconds_is_the_m1_rate`, `test_sustained_fire_settles_at_the_recharge_rate`.
- E3 Hit resolver: `test_hit_resolver.gd` `test_a_bolt_never_hits_its_shooter` vs `test_friendly_fire.gd`
  `test_on_a_bolt_never_hits_its_shooter`; `test_a_bolt_never_hits_its_own_faction_or_a_neutral` vs the `off_*` tests of
  `test_friendly_fire.gd`; `test_hit_scale.gd` `test_friendly_fire_off_and_on` vs all of `test_friendly_fire.gd`;
  `test_hit_scale.gd` `test_a_grazing_bolt_hits_inside_the_reach_and_misses_outside` vs `test_hit_resolver.gd`
  `test_a_bolt_passing_0_3_m_outside_the_inflated_volume_never_hits` + `test_a_bolt_just_inside_the_reach_hits`;
  `test_hit_scale.gd` `test_a_bolt_that_crosses_a_thin_wing_in_one_tick_hits` vs `test_a_fast_bolt_cannot_tunnel_through_a_thin_target`;
  the two `combat` provider tests in those files.
- E4 Rams: `test_collision_layers.gd` `test_a_fighter_head_on_at_thirty_mps_rams_as_on_the_base`,
  `test_two_fighters_at_six_hundred_mps_still_take_the_swept_ram`, `test_a_four_mps_bump_between_fighters_hurts_nobody`
  vs `test_ram_damage.gd` `test_a_thirty_mps_head_on_costs_each_ship_at_least_half_its_hull_once`,
  `test_a_six_hundred_mps_head_on_destroys_both_for_fifty_seeded_offsets`, `test_a_four_mps_bump_does_no_damage`. The
  collision-layer ones may exist to prove lean AI fighters (not the player) get the same result: if so keep one of them,
  not three. Also `test_ram_math.gd` `test_a_buoy_rammed_at_forty_mps_is_destroyed_and_the_ship_is_not_hurt` vs
  `test_ram_damage.gd` `test_ramming_a_buoy_at_forty_mps_destroys_it_and_spares_the_ship` (pure vs Jolt; keep both
  only if the Jolt one adds wiring).
- E5 Break-ups: "a third simultaneous break-up gets one-shot chunks" is tested four times: `test_debris_pool.gd`
  `test_with_both_sets_busy_a_third_break_up_uses_one_shot_chunks`, `test_destruction.gd`
  `test_with_both_sets_busy_a_third_break_up_uses_mesh_chunks`, `test_starfury_breakup.gd`
  `test_allies_and_the_player_share_two_sets_and_a_third_break_up_is_one_shot`, `test_last_hit_breakup.gd`
  `test_every_set_busy_gives_mesh_chunks_that_stage_the_same_way`. Keep the pool's and the Starfury one (shared sets).
- E6 "Pooled nodes never enter or leave the tree": `test_ship_pool.gd`, `test_debris_pool.gd`, `test_starfury_breakup.gd`,
  `test_m2_run.gd`, `test_wing_replenish.gd` (`the_pooled_node_count_never_changes...`). `test_m2_run` checks it across a
  whole game; the per-pool ones may be enough without the others, or the reverse.

Ships, flight and visuals:

- E7 `test_raider_flight.gd` repeats `test_ship_physics.gd`'s rules for the raider: keep the raider-specific ones
  (two nacelles, yaw sign from the short lever arm) and drop `test_the_ship_is_built_with_the_newtonian_body_settings`
  if `test_civilian_ships` / `test_flight_batch` already guard AI hulls' damping.
- E8 Empty tank: `test_flight_model_propellant.gd` (8, pure), `test_reaction_mass.gd`
  `test_with_an_empty_tank_the_ship_cannot_thrust`, `test_raider_flight.gd` `test_an_empty_tank_cuts_the_nacelles`,
  `test_flight_batch.gd` `test_a_batched_ship_out_of_reaction_mass_coasts`. Player path vs batch path differ, so keep the
  pure file + the batch test + one player test.
- E9 Textured hull drawn: `test_ship_scene.gd` `test_the_hull_draws_its_textured_mesh`, `test_textured_hull.gd`
  `test_the_player_and_a_lean_ally_draw_the_textured_mesh`, `test_ship_nodes.gd`
  `test_a_lean_ship_drops_the_cockpit_and_draws_its_hull_on_one_node`, `test_ally_pool.gd`
  `test_an_ally_draws_the_starfurys_textured_hull_without_a_cockpit_interior`, `test_mesh_assets.gd`
  `test_every_hull_is_textured_and_a_missing_asset_is_nothing`.
- E10 Canopy cleared in the cockpit: `test_speed_and_autotrack.gd` `test_the_canopy_glass_is_cleared_in_the_cockpit_and_back_outside`
  and `test_the_hulls_window_frames_are_cleared_in_the_cockpit_too` vs `test_ship_scene.gd`
  `test_the_cockpit_view_draws_the_hull_it_was_built_around_with_the_canopy_cleared`. They sit in the wrong file
  (speed and auto-track) either way.
- E11 Muzzle and explosion lights: `test_ship_lights.gd` `test_a_shot_adds_a_flash_light_for_sixty_milliseconds` vs
  `test_light_emitters.gd` `test_a_muzzle_flash_lasts_sixty_milliseconds`; `test_ship_lights.gd`
  `test_an_explosions_light_goes_through_the_picker_on_its_curve` vs D4.
- E12 `test_main_scene.gd` `test_target_next_selects_the_nearest_buoy`, `test_holding_dpad_up_targets_the_buoy_nearest_the_nose`
  vs `test_targeting_controller.gd` `test_target_next_cycles_by_range_and_wraps`, `test_target_ahead_picks_the_buoy_nearest_the_nose`;
  `test_main_scene.gd` `test_rebase_keeps_flying` vs `test_rebase_in_play.gd`. `test_main_scene`'s value is the input
  path end to end: keep the tests that go through pad input, drop the ones that only call the controller.
- E13 `test_multi_ship.gd` `test_target_next_selects_hostiles_first_nearest_first_then_neutrals` vs `test_targeting_system.gd`
  `test_next_cycles_hostiles_first_nearest_first_then_the_rest`; `test_multi_ship.gd` `test_an_inactive_targetable_is_never_a_candidate`
  and `test_a_selection_that_turns_inactive_clears_and_says_so` vs `test_targeting_scale.gd`
  `test_a_selection_that_turns_inactive_or_is_freed_clears_and_says_so`.
- E14 `test_raider_layout.gd` (static copy of the raider's hardpoints) vs `test_raider_flight.gd` (generated hardpoints)
  and Python `test_raider_fighter.py` (hardpoint contract). The fixture copy goes stale silently when the generator
  changes.

Game flow, menus and missions:

- E15 `test_mission_sequencer.gd` `test_a_skipped_run_leaves_the_same_spawns_and_objectives_as_a_played_one` (bare world)
  vs `test_mission_skip.gd` (same name, real scene) vs `test_civilian_escort.gd` `test_a_skipped_run_spawns_every_ship_from_the_pools`.
- E16 The 20-live-triggers bound is tested three times: `test_triggers.gd`
  `test_twenty_live_triggers_cost_a_bounded_count_whatever_the_world_holds`, `test_mission_sequencer.gd`
  `test_twenty_live_triggers_cost_a_counted_bound_per_tick`, `test_mission_runner.gd`
  `test_twenty_live_triggers_stay_inside_a_counted_bound`. Keep the pure one and the in-scene one.
- E17 Menu pages: `test_front_end.gd` and `test_pause_menu.gd` both have `test_settings_and_controls_open_in_the_frame_and_go_back`
  (or `..._start_steps_back`) and `test_the_settings_entry_opens_a_settings_page`. "The legend follows a rebind" is in
  `test_menu_frame.gd`, `test_pause_menu.gd` and `test_controls_screen.gd`. The frame is shared; test it once in
  `test_menu_frame` and keep only host-specific behaviour (Start steps back, the world is paused) in the hosts.
- E18 `test_boot_routing.gd` `test_a_windowed_launch_shows_the_front_end`, `test_every_scripted_run_goes_straight_to_main_with_the_scenario_setting`
  vs `test_game_flow.gd`'s six boot-rule tests (pure). Keep the pure rules and one routing test per destination.
- E19 `test_controls_screen.gd` (35 tests, 157 awaits: the slowest UI file) repeats `test_binding_capture.gd`'s rules
  through the page: `holding_b_cancels_the_wait_and_changes_nothing`, `a_modifier_alone_is_refused_with_a_hint...`,
  `a_stick_pushed_is_bound_with_its_direction`, `a_key_is_bound_by_its_physical_key`, `a_mouse_button_is_bound`,
  `a_wait_nobody_answers_gives_up`. Keep the page tests that are about the page (focus, navigation, the press not
  leaking to the menu).
- E20 Control-profile migrations live in three files: `test_control_profile.gd` (`a_profile_saved_with_the_old_default_pad_layout...`,
  `..._after_t15_is_never_migrated`), `test_control_profile_store.gd` (three "saved before ..." tests),
  `test_running_lights.gd` (`a_profile_saved_before_the_toggle_gets_it`, `a_saved_layout_that_uses_dpad_left_keeps_it...`).
  Not duplicates, but the running-lights ones belong in the store's file; check for overlap when moving.
- E21 `test_input_map.gd` `test_console_key_is_never_bound` vs `test_control_profile.gd` `test_the_console_key_is_rejected_and_nothing_is_applied`
  and the `bind fire key:QuoteLeft` console smoke in `run_tests.sh`. `test_godot_input_source.gd`
  `test_b_is_tap_for_next_target_and_hold_for_the_one_nearest_the_nose` vs `test_input_adapter.gd`'s tap/hold tests.
- E22 `test_measure_exec.gd` (one test of a measure tool's set-up) vs `test_console_execute_all.gd`
  `test_execute_all_runs_the_statements_after_a_hold`. The tool test adds only that the tool calls `execute_all`.

Scenarios and end-to-end runs (all slow):

- E23 Three waves cleared: `test_m2_run.gd` (three waves + `kill all`), `test_wave_director.gd`
  `test_three_waves_advance_with_the_expected_kills` and `test_kill_all_clears_a_wave_and_the_next_one_comes`,
  `test_rebase_in_play.gd` `test_a_sandbox_fight_with_wingmen_rebasing_every_second_clears_its_waves`,
  `test_m3_sandbox.gd` `test_the_wingmen_clear_three_waves_with_the_player_idle` (SLOW), and the combat smoke in
  `run_tests.sh`. Each is a long real-time run.
- E24 The dogfight scenario is flown in `test_dogfight.gd` (SLOW, five seeds), `test_m3_run.gd`
  `test_the_dogfight_records_the_ai_time_and_holds_the_resolver_budget`, `test_ai_ram.gd` (two dogfight tests) and
  `test_respawn_in_play.gd` `test_dogfight_raiders_shot_down_stay_down_and_every_wing_flies_on`.
- E25 `test_rebase_in_play.gd` `test_rebase_900_km_out_comes_back_on_the_next_tick_with_every_universe_position_kept`
  vs the rebase console smoke in `run_tests.sh` (same command, same expected lines).
- E26 `test_destruction.gd` `test_the_players_death_hides_the_ship_ignores_input_and_respawns_after_three_seconds` and
  `test_kill_all_and_kill_target_work_through_the_console...` vs the destruction smoke in `run_tests.sh`.

## F. Tests that measure the wall clock or pin removed paths (maintainer's decision)

F1. **Wall-clock budgets.** `WallClockBudget` only records on CI (`CI=true`), so on CI these tests can never fail:
`test_ai_think_time.gd` (one long paired fight), `test_hit_resolver.gd` `test_64_bolts_against_8_targets_resolve_well_under_two_milliseconds`,
`test_m2_run.gd` (resolver p99), `test_m3_run.gd` (resolver budget), `test_rebase_in_play.gd` (median rebase),
`test_world_frame.gd` (rebase of 20 nodes). Also `test_encounters.gd` `test_the_free_flight_load_time_with_encounters_on_is_recorded`
and `test_bench.gd`. These are benchmarks living in the test suite. Option: move them under `scripts/bench_quick.sh` and
keep the work-count tests (which are deterministic) in the suite.

F2. **`test_ai_think_time.gd`** compares `AiPilot` against M2's `AttackBrain` by wall clock. Since M4-T17 the pilots
think in the native batch, so check what `ai.think_us` still measures. If it no longer measures the brains' cost,
the test pins nothing.

F3. **Tolerance runs against removed GDScript paths** (all SLOW-gated, long): `test_flight_parity_fight.gd`,
`test_brain_tolerance.gd`, `test_weapon_rows_battle.gd`, and `test_tier_outcomes.gd`. Each has two halves: a tolerance
check against a recording of the removed GDScript path (hits within 10-20 %, mix within 5 points), and an exact check
against a native recording. Rule 1 says the recordings stay tested. Ask the maintainer whether the tolerance halves
(which can only fail if the native path drifts a lot, and then the exact half fails first) are still wanted. Do not
remove these without that answer.

F4. **Long runs that end Pending (CONFIRMED in the timed run).** With `GUT_SLOW=1`:
- `test_dogfight.gd` took 325 s. Its main test, `test_one_side_is_destroyed_within_six_minutes_for_every_seed`, ended
  `[Pending]: AC12 balance under review by the maintainer: 5 of 5 seeds did not finish in 360 s`.
- `test_m3_sandbox.gd` took 150 s. `test_the_wingmen_clear_three_waves_with_the_player_idle` ended
  `[Pending]: AC12 balance under review by the maintainer: waves [1] cleared in 900 s, 0 wingmen left`.

About 8 minutes of every full run fly fights whose verdict is thrown away. Until the balance answer comes, skip these
two tests up front (`pending("…")` before the run, or move them behind a separate `GUT_BALANCE=1` switch), so the
other tests in those files still run. Ask the maintainer first: the pending verdicts may be what they read to tune
the balance. `test_turret_balance.gd` (664 s, the slowest file in the suite) is the same kind of balance run; check
whether it ends Pending too (it passed in this run).

## G. Python generator tests (PLAUSIBLE)

- G1. Five civilian-ship files repeat one contract per hull, nearly test for test: `test_brakiri_bokmai.py` (42),
  `test_centauri_brezebel.py` (36), `test_narn_transport.py` (31), `test_skylark_transport.py` (32),
  `test_saturn_family.py` (39). Their docstrings list the same checks: files, the mesh contract, frames, symmetry, chunk
  cuts, collision coverage, the hardpoint contract. A parameterised contract (one class, one row per hull) would remove
  most of the duplicated code; keep the hull-specific tests (turret placement, pods, Q-answers) per file.
- G1b. Measured (`--durations 0`, one run, 48.6 min wall in all): `test_saturn_family` spends 487 s inside its tests,
  370 s of it in `SaturnDeterminismTests.test_same_seed_gives_byte_identical_output`. Every hull's "a different seed
  changes the wear but not the design" test builds that hull again: 128 s for the Starfury, 74 s Saturn, 47 s raider,
  25 s Skylark, 16 s Brezebel. Most of the 48 minutes is outside the tests, in `setUpClass` asset builds (the Starfury's
  textured mesh alone: 148 s).
- G2. Determinism tests that build an asset twice and compare bytes exist in nearly every asset file
  (`test_nav_buoy`, `test_raider_fighter`, `test_starfury_aurora`, `test_sky_default`, the five above).
  `test_parallel_build.py` already builds assets in workers and compares bytes; check whether one cross-asset
  determinism test plus `test_parallel_build` covers them.
- G3. `test_textured_hulls.py` (every other hull textured) vs the per-asset files' "the mesh contract" tests, and
  `test_textured_mesh.py`. Check for repeated `.glb` contract checks on the same asset.
- G4. `test_mesh_only.py` (2 tests: no point-cloud writers left) guards a removal done in M4-T31. Cheap; keep unless the
  maintainer considers that migration finished.

## H. Not removals, but found on the way

- H1. **The Rust tests never run.** `native/src/{turret_kernels,civilian,voice_kernels}/tests.rs` hold 36 tests.
  Neither `scripts/run_tests.sh` nor `.github/workflows/ci.yml` runs `cargo test`. They pass today
  (`cargo test --release --lib`: 36 passed, 72 s to compile from cold, 0.00 s to run). Wire them into `run_tests.sh`
  or drop them; their GUT counterparts are `test_turret_kernel`, `test_turret_line_of_fire`, `test_civilian_flight` and
  `test_voice_query`, which also check the same behaviour from GDScript.
- H2. `tests/fixtures/` holds tests of the test fixtures themselves: `test_manifest_reader.gd`, `test_parity_fixture.gd`,
  `test_wall_clock_budget.gd`, `test_slow_tests.gd`. They are cheap and guard real failure modes (recording on CI, slow
  files left out silently); keep.
- H3. Stale names: `test_sim_clock.gd` `test_warp_is_fixed_at_one_in_m1`, `test_world_frame.gd`
  `test_environment_accel_is_zero_in_m1`. Check they still describe the current design (time warp, the gravity source).
