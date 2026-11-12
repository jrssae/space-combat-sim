# Test timings (one run, 2026-11-09, maintainer's machine, branch m5 at 5c65d81)

How measured, and its limits:
- GUT: one full run, `GUT_SLOW=1`, all files in one process. A watcher polled `reports`-style log output every 2 s and
  noted when each file started, so each time below is from one file's start to the next one's (±2 s). Files that
  started and finished inside one poll are listed as "under 2 s".
- The Python run (48.6 min) shared the machine for the first 49 minutes, so GUT times are somewhat high.
- The run hit its 66-minute timeout in `test_tier_fire.gd`. That file and the 13 after it were timed one by one;
  those times include about 5.5 s of GUT start-up each (`test_smoke` alone: 6.1 s).
- The first seven files (`test_ai_attack` to `test_ai_objective`) ran before the watcher started: about 5 minutes
  together, not split per file.
- No test failed. Pending (not run headless or balance under review): `test_dogfight`, `test_m3_sandbox`, the GPU files.

## GUT files over 2 s (seconds, slowest first)

| s | file |
| ---: | --- |
| 664 | integration/test_turret_balance.gd |
| 385 | integration/test_civilian_escort.gd |
| 350 | integration/test_tier_outcomes.gd |
| 325 | integration/test_dogfight.gd |
| 183 | integration/test_brain_tolerance.gd |
| 150 | integration/test_m3_sandbox.gd |
| 130 | integration/test_rebase_in_play.gd |
| 113 | integration/test_ai_ram.gd |
| 73 | integration/test_turret_defence.gd |
| 64 | integration/test_speed_and_autotrack.gd |
| 56 | integration/test_flight_parity_fight.gd |
| 48 | integration/test_ship_physics.gd |
| 46 | integration/test_tier_handover.gd |
| 38 | integration/test_contact_registry.gd |
| 37 | integration/test_instructor_route.gd |
| 36 | unit/test_sweep_math.gd |
| 36 | unit/test_core_snapshot.gd |
| 36 | integration/test_turret_threads.gd |
| 36 | integration/test_ai_skill.gd |
| 34 | integration/test_civilian_flight.gd |
| 32 | integration/test_weapon_rows_battle.gd |
| 30 | unit/test_core_threads.gd |
| 30 | integration/test_wave_director.gd |
| 30 | integration/test_ai_slash.gd |
| 26 | integration/test_ram_damage.gd |
| 26 | integration/test_m3_run.gd |
| 24 | integration/test_rocks_and_mines.gd |
| 23 | unit/test_core_state.gd |
| 21 | integration/test_ship_lights.gd |
| 20 | unit/test_driver_step.gd |
| 20 | integration/test_ai_think_time.gd |
| 18 | unit/test_row_commands.gd |
| 18 | integration/test_turret_line_of_fire.gd |
| 18 | integration/test_manoeuvres_jolt.gd |
| 16 | unit/test_bolt_rows.gd |
| 16 | integration/test_raider_flight.gd |
| 16 | integration/test_collision_layers.gd |
| 16 | integration/test_bench.gd |
| 15 | integration/test_comms_menu_input.gd |
| 14 | integration/test_running_lights_in_play.gd |
| 14 | integration/test_m2_run.gd |
| 14 | integration/test_fx_pool.gd.TestSandbox |
| 14 | integration/test_controls_screen.gd |
| 12 | integration/test_mission_runner.gd |
| 10 | unit/test_convex_sweep.gd |
| 10 | integration/test_thrust_smoothness.gd |
| 10 | integration/test_reaction_mass.gd |
| 10 | integration/test_encounters.gd |
| 10 | integration/test_debrief.gd |
| 10 | integration/test_comms_panel.gd |
| 10 | integration/test_brain_in_play.gd |
| 8 | unit/test_brain_think_parity.gd |
| 8 | integration/test_pilot_kernels_in_play.gd |
| 8 | integration/test_main_scene.gd |
| 8 | integration/test_engine_audio.gd |
| 8 | integration/test_destruction.gd |
| 8 | integration/test_cinematic_camera.gd |
| 7 | integration/test_pause_menu.gd |
| 6 | unit/test_native_required.gd |
| 6 | unit/test_contact_field.gd |
| 6 | integration/test_respawn_in_play.gd |
| 6 | integration/test_flight_batch.gd |
| 6 | integration/test_explosion_lod.gd |
| 6 | integration/test_cockpit_screens.gd |
| 6 | integration/test_civilian_ships.gd |
| 6 | integration/test_ai_think_rate.gd |
| 4 | unit/test_ram_sweep_cull.gd |
| 4 | unit/test_mine_kernel.gd |
| 4 | unit/test_flight_step.gd |
| 4 | integration/test_wing_replenish.gd |
| 4 | integration/test_wing_orders.gd |
| 4 | integration/test_tier_proxies.gd |
| 4 | integration/test_ram_scale.gd |
| 4 | integration/test_ram_contact_columns.gd |
| 4 | integration/test_mission_skip.gd |
| 4 | integration/test_last_hit_breakup.gd |
| 4 | integration/test_hud.gd |
| 4 | integration/test_fighter_melee.gd |
| 4 | integration/test_buoy_destruction.gd |
| 4 | integration/test_boot_routing.gd |
| 4 | integration/test_audio_director.gd |
| 4 | integration/test_ai_retreat.gd |
| 6 (alone) | unit/test_smoke.gd |
| 138 (alone) | unit/test_tier_fire.gd |
| 6 (alone) | unit/test_trigger_calibration.gd |
| 9 (alone) | unit/test_triggers.gd |
| 24 (alone) | unit/test_turret_kernel.gd |
| 7 (alone) | unit/test_universe_pos.gd |
| 6 (alone) | unit/test_upscaling.gd |
| 6 (alone) | unit/test_voice_query.gd |
| 6 (alone) | unit/test_wall_clock_budget.gd |
| 6 (alone) | unit/test_wave_plan.gd |
| 6 (alone) | unit/test_weapon_capacitor.gd |
| 7 (alone) | unit/test_weapon_spec.gd |
| 5 (alone) | unit/test_wing.gd |
| 6 (alone) | unit/test_world_statics.gd |

## GUT files under 2 s

- integration/test_anti_aliasing.gd
- integration/test_audio_buses.gd
- integration/test_civilian_meshes.gd
- integration/test_console_command_list.gd
- integration/test_damage.gd
- integration/test_debris_pool.gd
- integration/test_debug_console.gd
- integration/test_environment.gd
- integration/test_every_world_core.gd
- integration/test_explosion.gd
- integration/test_frame_passes.gd
- integration/test_livery_hull.gd
- integration/test_loading_screen.gd
- integration/test_measure_exec.gd
- integration/test_menu_frame.gd
- integration/test_mesh_only_scene.gd
- integration/test_motion_vectors_gpu.gd
- integration/test_muzzle_flash_pool.gd
- integration/test_settings_screen.gd
- integration/test_ship_nodes.gd
- integration/test_standins.gd
- integration/test_targeting_on_read.gd
- integration/test_targeting_scale.gd
- integration/test_textured_hull.gd
- integration/test_thruster_visuals.gd
- integration/test_upscaler.gd
- integration/test_upscaling_gpu.gd
- integration/test_weapon_charge.gd
- integration/test_weapons.gd
- unit/test_ai_keep_contacts.gd
- unit/test_ai_pilot_selection.gd
- unit/test_ai_profile.gd
- unit/test_ai_temperament.gd
- unit/test_ai_think_rate_math.gd
- unit/test_anti_aliasing_mode.gd
- unit/test_attack_brain_states.gd
- unit/test_attack_slash.gd
- unit/test_audio_buses.gd
- unit/test_avoidance_math.gd
- unit/test_battle_mix.gd
- unit/test_bench_report.gd
- unit/test_binding_capture.gd
- unit/test_body_registry.gd
- unit/test_bolt_mesh_taa.gd
- unit/test_bolt_slot_quarantine.gd
- unit/test_bolt_sync.gd
- unit/test_brain_facade.gd
- unit/test_brain_parity.gd
- unit/test_breakup_plan.gd
- unit/test_camera_look.gd
- unit/test_chase_camera_math.gd
- unit/test_cinematic_shot.gd
- unit/test_comms_layout.gd
- unit/test_comms_menu.gd
- unit/test_console_completer.gd
- unit/test_console_execute_all.gd
- unit/test_console_history.gd
- unit/test_console_registry.gd
- unit/test_console_tokenizer.gd
- unit/test_control_lock.gd
- unit/test_control_profile.gd
- unit/test_control_profile_store.gd
- unit/test_controls_model.gd
- unit/test_damage_zones.gd
- unit/test_debrief_model.gd
- unit/test_debug_flags.gd
- unit/test_dialog_book.gd
- unit/test_dialog_ids.gd
- unit/test_dialog_queue.gd
- unit/test_display_driver.gd
- unit/test_encounter_plan.gd
- unit/test_engine_voices.gd
- unit/test_explosion_lod_maths.gd
- unit/test_faction_console.gd
- unit/test_faction_table.gd
- unit/test_far_dots.gd
- unit/test_fire_lane.gd
- unit/test_flight_assist.gd
- unit/test_flight_model.gd
- unit/test_flight_model_propellant.gd
- unit/test_formation.gd
- unit/test_fuel_tank.gd
- unit/test_fx_specs.gd
- unit/test_game_flow.gd
- unit/test_godot_input_source.gd
- unit/test_hardpoints.gd
- unit/test_hud_layout.gd
- unit/test_hud_screens.gd
- unit/test_hull_health.gd
- unit/test_impact_flash.gd
- unit/test_input_adapter.gd
- unit/test_input_map.gd
- unit/test_intercept_math.gd
- unit/test_kill_credit.gd
- unit/test_lens_flare_aim.gd
- unit/test_light_emitters.gd
- unit/test_livery.gd
- unit/test_lod_switcher_math.gd
- unit/test_manifest_reader.gd
- unit/test_manoeuvres.gd
- unit/test_mesh_assets.gd
- unit/test_mesh_materials.gd
- unit/test_mine_trigger.gd
- unit/test_missile_guidance.gd
- unit/test_missile_kernel.gd
- unit/test_mission_catalog.gd
- unit/test_mission_cinematic.gd
- unit/test_mission_say.gd
- unit/test_mission_sequencer.gd
- unit/test_mission_tally.gd
- unit/test_motion_blur_gate.gd
- unit/test_native_probe.gd
- unit/test_nearest_contacts.gd
- unit/test_objective_book.gd
- unit/test_objectives_model.gd
- unit/test_overlay_text.gd
- unit/test_pad_diagram.gd
- unit/test_pad_legend.gd
- unit/test_parity_fixture.gd
- unit/test_perf_probe.gd
- unit/test_perf_stats.gd
- unit/test_pilot_steering.gd
- unit/test_pulse_cannon_capacitor.gd
- unit/test_pulse_cannon_gate.gd
- unit/test_radar_model.gd
- unit/test_radar_plot.gd
- unit/test_raider_layout.gd
- unit/test_ram_broad_phase.gd
- unit/test_ram_math.gd
- unit/test_ram_tracker.gd
- unit/test_route.gd
- unit/test_running_light_dimming.gd
- unit/test_running_lights.gd
- unit/test_runtime_glsl_export.gd
- unit/test_settings.gd
- unit/test_settings_menu_model.gd
- unit/test_settings_schema.gd
- unit/test_ship_catalog.gd
- unit/test_silhouette.gd
- unit/test_sim_clock.gd
- unit/test_sky_manifest.gd
- unit/test_smoke.gd
- unit/test_speed_governor.gd
- unit/test_star_color.gd
- unit/test_star_point_math.gd
- unit/test_static_rows.gd
- unit/test_sweep_cells.gd
- unit/test_targetable_hull.gd
- unit/test_targeting_system.gd
- unit/test_thruster_glow_levels.gd
- unit/test_thruster_layout.gd
- unit/test_tier.gd
- unit/test_slow_tests.gd
- unit/test_sim_core.gd
- unit/test_scenario_loader.gd
- unit/test_ram_tracker_columns.gd
- unit/test_pilot_kernels.gd
- unit/test_light_picker.gd
- unit/test_hit_shape.gd
- unit/test_hit_broad_phase.gd
- unit/test_factions.gd
- unit/test_contact_scan.gd
- unit/test_brain_factory.gd
- unit/test_bench_layout.gd
- unit/test_belt_layout.gd
- unit/test_behaviour_ram.gd
- integration/test_world_frame.gd
- integration/test_textured_hulls.gd
- integration/test_targeting_controller.gd
- integration/test_starfury_breakup.gd
- integration/test_ship_scene.gd
- integration/test_ship_pool.gd
- integration/test_ram_damage.gd.TestInTheMainScene
- integration/test_post_effects.gd
- integration/test_multi_ship.gd
- integration/test_kill_credit_in_play.gd
- integration/test_info_md.gd
- integration/test_hit_scale.gd
- integration/test_hit_resolver.gd
- integration/test_fx_pool.gd
- integration/test_front_end.gd
- integration/test_friendly_fire.gd
- integration/test_control_profiles.gd
- integration/test_camera_rig.gd
- integration/test_broadcast.gd
- integration/test_asteroid_belt.gd
- integration/test_ally_pool.gd.TestAlliesInTheSandbox
- integration/test_ally_pool.gd
- integration/test_ai_patrol.gd

## Python files run alone (seconds; 124 = killed at 120 s)

| s | exit | module |
| ---: | ---: | --- |
| 0.3 | 0 | test_rotations |
| 0.3 | 0 | test_wing |
| 0.3 | 0 | test_color |
| 0.4 | 0 | test_image |
| 0.4 | 0 | test_audio |
| 0.4 | 0 | test_manifest |
| 0.4 | 0 | test_panorama |
| 0.4 | 0 | test_chunks |
| 0.6 | 0 | test_uv_atlas |
| 0.6 | 0 | test_geometry |
| 0.6 | 0 | test_sfx_ui |
| 0.7 | 0 | test_parts |
| 0.9 | 0 | test_refview |
| 1.0 | 0 | test_sfx_world |
| 1.0 | 0 | test_starfury_parts |
| 1.6 | 0 | test_cockpit |
| 1.8 | 0 | test_cli |
| 3.4 | 0 | test_sfx_combat |
| 4.0 | 0 | test_sampling |
| 4.2 | 0 | test_livery |
| 9.1 | 0 | test_mesh_only |
| 19.7 | 0 | test_refview_compare |
| 26.3 | 0 | test_textures |
| 27.4 | 0 | test_nav_buoy |
| 60.1 | 0 | test_sky_default |
| 120.0 | 124 | test_render_pieces |
| 120.0 | 124 | test_asteroids |

Not run alone (each builds full assets in setUpClass, minutes each): the per-hull files, `test_textured_hulls`, `test_textured_mesh`, `test_parallel_build`, `test_raider_fighter`, `test_starfury_aurora`.

## Other pieces

- `cargo test --release --lib` in `native/`: 36 passed; 72 s compile from cold, 0.00 s to run.
- Compile check (`scripts/check_scripts.gd`): 20 s, 608 scripts.
- Main-scene console smoke (`wait 30; state ship; quit`): 7 s.

## Independent review notes (2026-11-09)

- The 66-minute GUT run ended by timeout while `test_tier_fire.gd` was running; it is not a completed full-suite measurement.
  The approximate full-suite duration in `quick-test-suite.md` is an estimate from the partial GUT timing, the separate 48.6-minute
  Python run, and the remaining runner steps.
- The first seven GUT files have only a combined estimate, and one-by-one runs include about 5.5 seconds of GUT startup each.
  Use those numbers to prioritize candidates, not to promise exact savings from each test removal.
- The Python test list was measured in an environment where NumPy was available for the selected modules; the notes say the
  maintainer's system Python lacked NumPy. A quick runner must validate or select its Python environment explicitly.
- The timings belong to `5c65d81`; the pulled head `5d81686` adds review documents and milestone planning, with no test/source
  changes between those commits. Re-take the measurements after test-suite changes land.
