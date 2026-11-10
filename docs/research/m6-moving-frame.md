# M6-T01: the moving frame, audited

Written 2026-11-10 against `m6` at `18cb4c7`. Reading only: no code changed. The decisions are in the milestone file
(`docs/milestones/m6-epsilon-space-at-true-scale.md`, D64 to D71); this note holds the evidence.

Words used below:
- **Boost by `dv`**: a velocity rebase. The frame gains `dv`; every local velocity loses it. Positions do not change.
- **Rest velocity** (`v_rest`): the velocity, in the local frame, of whatever a speed is measured against (the anchor or the
  HUD's reference). Zero today, because the frame never moves.
- **Anchor**: the free-falling point a scene is built around (the station's point in its orbit).

## 1. Findings that change the plan

1. **Everything without a velocity assumes the frame is at rest.** The static rows (rocks, mines), buoys, the station's
   stand-in and every stored `UniversePos` (waypoints, guard posts, trigger points, wave anchors, the respawn and reference
   points) have no velocity. After a boost onto the player they would all have to move every tick. A Starfury reaches 200 m/s
   in about 7 s of full thrust (4 pods of 3.6e5 N on 48 t: 30 m/s^2), so at the planned threshold that is every dogfight.
2. **A barycentric `UniversePos` cannot hold a place.** Epsilon III moves at about 35 km/s around the star. A waypoint stored
   as a barycentric position is 580 m behind after one tick. Places must be held relative to the anchor.
3. **The AI's speeds are frame speeds.** Cruise, "stop", run-up and closing speeds in every brain (GDScript and native) read
   the ship's own velocity as absolute. One seam fixes them all: feed the brains velocities with `v_rest` taken off.
4. **`RamTracker` would read a boost as a ram.** Its open windows keep each hull's velocity from the last tick; a 200 m/s
   boost looks like a 200 m/s velocity change against an 18 m/s lethal limit.
5. **The flight batch runs before the rebase slot** (priority -1 against 0), so gravity must be sampled once per tick and
   the same sample used by every mover and by the frame itself.
6. **The start of an orbit needs half a kick.** Without it the frame is 256 m off the analytic orbit mid-orbit; with it,
   5 mm (section 5).
7. **The 9 999 m/s limit is below escape speed** in low orbit (10 851 m/s), and the thrust fade against a body would leave
   64 % of the thrust in a 400 km orbit and none above the limit.
8. **A boost needs no interpolation reset**: no position jumps, so nothing blends across one.
9. No sound uses Doppler (`doppler` appears nowhere in `src/` or `project.godot`). Jolt's speed cap is 10 000 m/s in
   `project.godot`, not the 500 m/s default that architecture §14.1 names.

## 2. Audit: who holds or reads a local velocity or position

Action on a boost: **B** subtract `dv` from the stored value; **R** read against `v_rest` instead of as absolute;
**H** harmless, with the reason.

### GDScript: state that outlives a tick

| File | Symbol | Holds | Boost |
|---|---|---|---|
| `src/ship/ship.gd` | `linear_velocity` (Jolt body) | the hull's velocity | B (bodies in the tree and not parked) |
| `src/perf/standins/capital_standin.gd` | `linear_velocity`, `cruise_velocity` | velocity, and the cruise it holds | B both; the cruise is a rest-frame target (R) |
| `src/ai/tier_director.gd` | parked bodies, `_park_origins`, `flying_velocity` | a parked body keeps its old velocity; its row is the truth | H while the row exists; line 414's fallback reads the stale body velocity: count boosts since parking, as `_reframe` does for positions |
| `src/game/ship_pool.gd` | pooled ships (`acquire`, release at zero) | hidden ships at zero | H: skipped, placed with a fresh velocity on `acquire` |
| `src/weapons/projectile.gd` | `velocity`, `last_step` | a node bolt's velocity; last tick's displacement | B `velocity`; `last_step` H (rebuilt at the step, after the rebase slot) |
| `src/perf/standins/missile_standin.gd` | the steered velocity it returns | a missile's velocity | B (it is the projectile's `velocity`); its body lookup at line 132 H |
| `src/combat/debris_chunk.gd` | `velocity` | a chunk's velocity | B |
| `src/combat/staged_wreck.gd`, `debris_pool.gd` | `StagedWreck.velocity`, `shift_wrecks` | a held wreck's velocity | B (beside `shift`) |
| `src/combat/explosion.gd` | `velocity` | the fireball's drift | B |
| `src/combat/fx_pool.gd` | `_velocity[]` | each emitter's drift | B; the particles are in the emitter's frame (`local_coords`), so H |
| `src/rendering/far_flashes.gd` | `_velocities` | each far flash's drift | B |
| `src/props/nav_buoy.gd`, `src/targeting/targetable.gd` | `velocity` (a marker with no body) | a prop's own motion | R: anchor-tied, it moves at `v_rest` plus this |
| `src/combat/ram_tracker.gd` | `_prev_velocities`, `Window.v_before`, `Sample.velocity` | last tick's velocities, per open contact | **B**, or every open window reports a ram of `dv`; a missing other is taken as at rest (lines 274, 287): R |
| `src/combat/ram_resolver.gd` | `_velocities` (per tick), `_prop_velocity`, statics at `Vector3.ZERO` (line 471) | hull velocities; props and rocks at rest | per tick H; props and rocks R |
| `src/ai/manoeuvres.gd`, `behaviour_formation.gd` | `_v0`, `speed0_mps`, the leader's last velocity | brain memory of velocities | H once brains are fed rest-relative velocities (finding 3) |
| `src/game/main.gd` | `_start_velocity`, `reference_point()`, `_spawn_position` | the start state and the HUD's reference | spawn velocities R (add `v_rest`); the points are places (section 4) |
| `src/audio/audio_director.gd`, `engine_voices.gd` | voices (shiftable or on the ship) | positions only | H: no Doppler |
| `src/camera/camera_rig.gd`, `chase_camera_math.gd`, `cinematic_shot.gd` | camera poses | poses built from the actors each call | H: a boost moves no position |
| `src/mission/jump_arrival.gd`, `jump_arrival_pool.gd` | a flash at a point | position only | R: it stays with its place |
| `src/world/world_frame.gd` | `origin`, `origin_velocity`, the settler | the frame | the rebase itself; no settle for a boost |

### GDScript: velocities read each tick

| File | Symbol | Reads | Boost |
|---|---|---|---|
| `src/ship/ship.gd` | brake and assist (`_model.compute`), `thrust_gain`, `assist_cap_correction`, the clamp, `reset_to`, console `velocity` and `speed`, `body_velocity` | own velocity as absolute | **R** (section 3) |
| `src/ship/flight_batch.gd`, `flight_model.gd`, `flight_assist.gd`, `speed_governor.gd` | `Out.VELOCITY`, `speed_limit_mps`, `assist_speed_max_mps` | the same, for the native step | R |
| `src/weapons/pulse_cannon.gd` | `body.linear_velocity + dir * muzzle` | muzzle velocity | H: both in the frame of now |
| `src/targeting/targeting_controller.gd`, `targeting_system.gd`, `target_info.gd`, `target_readout.gd`, `tier_targets.gd` | own and target velocity | closing speed, lead | H: differences |
| `src/combat/intercept_math.gd`, `ram_math.gd`, `sweep_math.gd`, `convex_sweep.gd` | relative velocities | lead, contact `dv`, sweeps | H |
| `src/combat/hit_resolver.gd`, `hit_broad_phase.gd` | `_velocities` from the core | hull travel this tick | H per tick; rocks taken as at rest: R |
| `src/combat/destruction_director.gd` | the dying hull's velocity | handed to debris, wreck, explosion | H: same tick |
| `src/hud/hud_input.gd`, `hud_layout.gd`, `hud_frame.gd`, `hud_painter.gd`, `hud.gd`, `hud_surface.gd` | `own_velocity`, `reference_velocity` (zero today) | speed, velocity marker, drift ball, angles | **R**; closing speed and lead H |
| `src/game/main.gd:289, 474` | `speed_mps`, `own_velocity` | state and HUD input | R |
| `src/ai/ai_pilot_driver.gd:610`, `perception.gd`, `contact.gd`, `contact_scan.gd`, `ai_context.gd`, `pilot_rows.gd` | own and contact velocities | the brains' input | **R at this one seam** |
| `src/ai/*_brain.gd`, `behaviour_*.gd`, `attack_slash.gd`, `pilot_steering.gd`, `avoidance_math.gd`, `manoeuvre.gd`, `raider_tactics.gd`, `ai_pilot.gd`, `ai_behaviour.gd`, `route.gd` | `p.velocity`, `cruise_mps`, `STOP_MPS`, closing caps | speeds as absolute; rocks at rest | H after the seam |
| `src/game/wing_director.gd`, `wave_director.gd` | leader velocity, the spawn heading | per tick | H |
| `src/encounters/encounter_director.gd`, `encounter_plan.gd`, `encounter_event.gd` | `anchor_velocity`, planned `velocities` | spawn velocities | the anchor's H; planned ones R at the spawn |
| `src/game/scenario_loader.gd`, `src/mission/mission_stage.gd`, `mission_api.gd`, `mission_world.gd` | velocities in data, `place` | spawn and teleport velocities | data R at the spawn; `place` H |
| `src/perf/bench_runner.gd`, `bench_layout.gd`, `station_scene.gd`, `standins/standin_director.gd`, `turret_standin.gd`, `src/rendering/look_scene.gd` | spawn velocities, a ship set to zero, spawn points | bench and look-sheet set-up | H: the bench rides its anchor with no boost |
| `src/perf/standins/gravity_standin.gd` | the moon's local place | removed in T07 | - |
| `src/rendering/sky_velocity_effect.gd`, `motion_blur_effect.gd`, `motion_blur_gate.gd`, `velocity_probe_effect.gd`, `anti_aliasing.gd`, `post_effects.gd` | screen motion vectors | drawn positions | H: a boost moves no position |
| `src/weapons/bolt_mesh.gd`, `src/rendering/far_dots.gd` | `note_rebase`, `_on_rebased` | positions | H for a boost |
| `src/console/console_vars.gd`, `src/game/overlay_text.gd`, `src/ai/ai_console.gd` | speed readouts | display | R where it says "speed" |
| `tests/fixtures/rebase_fight.gd` | `cruise_mps` against `linear_velocity.length()` | holds a frame speed | R; it grows the forced velocity rebase (T05) |
| `tests/fixtures/target_drone.gd`, `tree_rows.gd`, `turret_scene.gd`, `weapon_rows_scene.gd` | set or copy velocities | fixtures at rest | H: no boost in them |

### Native (`native/src/`)

| File | Symbol | Holds or reads | Boost |
|---|---|---|---|
| `rows.rs`, `sim_core.rs` | `Rows.velocities`, `shift`, `rows_version` | each row's velocity, read at -11 | **B** in a new `boost(dv)` beside `shift`; it bumps `rows_version`, so thinks across it are declined as for a rebase |
| `rows.rs`, `bolt_rows.rs`, `bolt_sync.rs` | `Bolts.velocities`, `last_steps` | the bolts the core owns | B the velocities; `last_steps` H |
| `tier.rs`, `tier_rows.rs` | `TierRows.velocities`, `cruise`, `speed_limit`, `Gravity.positions` | tier rows; a capital's cruise; the clamp | B velocities and cruise; the clamp R (Q4); `accel` held between beats H |
| `flight_step.rs`, `kernels.rs` (`flight::tick`, `compute`) | `v_w` into the brake, `thrust_gain`, `assist_cap_correction`, the clamp | own velocity as absolute | **R**: the step takes `v_rest` and passes `v_w - v_rest` to those four |
| `brain.rs`, `brain_step.rs`, `brain_behaviours.rs`, `brain_maths.rs`, `pilot_kernels.rs`, `civilian.rs` | `p.velocity`, `speed0_mps`, `v0`, cruise, the snapshot's rows | speeds as absolute, one tick behind | R at the snapshot (velocities less `v_rest`); memory then H |
| `kernels.rs` (`avoid`, `incoming`, `closest_approach`, `hull_spheres`, `rigid_spheres`) | relative velocities; a rock's as zero | avoidance, incoming fire, sweep reach | differences H; rocks R |
| `contact_field.rs` | `bolt_velocities`, its own columns | rebuilt per scan | H (the version bump) |
| `sweep_cells.rs`, `hit_sweep.rs` | travel per tick | bolts against hulls and rocks | H; rocks R |
| `weapon_rows.rs`, `weapon_kernels.rs`, `cannons.rs`, `bolt_kernels.rs`, `turret_rows.rs`, `turret_kernels.rs`, `tier_fire.rs` | muzzle velocity, lead | velocities of one tick | H |
| `ram_phase.rs` | `contacts(core, shift)` | Jolt's velocities and contact points | H per tick (the tracker's memory is the B, above) |
| `row_commands.rs`, `radar_kernel.rs`, `radar_plot.rs`, `voice_kernels.rs`, `voice_rows.rs`, `native_probe.rs`, `threads.rs`, `v3.rs` | commands, positions | levels and rates; places of one tick | H |

## 3. Velocities treated as absolute (D64)

Each reads a local velocity as if the frame stood still. Each must read `v - v_rest`:

- The brake's all stop, the thrust fade, the assist's safe-speed cap and the hard clamp: `ship.gd:262-284`,
  `kernels.rs` `flight::tick` (lines 749 to 775) and `compute` (the brake), `tier.rs:295`.
- `Ship.reset_to` and every "at rest" spawn (`linear_velocity = Vector3.ZERO`); spawn velocities from scenario, mission and
  encounter data.
- The HUD's speed, velocity marker, drift ball and angles (`hud_layout.gd:129-154`); `Main`'s `speed_mps`; the console's
  `ship.speed`.
- Every brain's own speed: `manoeuvres.gd` (stop, settle), `behaviour_follow_path.gd` (run-up, brake), `patrol_brain.gd`,
  `behaviour_guard.gd`, `attack_brain.gd` and `attack_slash.gd` (the cap against `target_velocity.length()`), and the same code
  in `brain_behaviours.rs`, `brain_maths.rs` and `civilian.rs`.
- A capital's `cruise_velocity` (`capital_standin.gd:151`, `tier.rs` `cruise`).
- Rocks, mines and props taken as at rest: `ram_resolver.gd:471`, `_prop_velocity`, `ram_tracker.gd:274, 287`, the static rows
  in the hit sweep and in `avoid`.
- `tests/fixtures/rebase_fight.gd`'s cruise hold.

## 4. Places assumed at rest, and single-frame globals (D71)

Stored `UniversePos` that outlive a tick (they stay valid only if `UniversePos` is relative to the anchor, D64):
`patrol_brain.gd` and `route.gd` (waypoints), `ai_context.gd` (`guard_post`, `leader_link_position`), `manoeuvres.gd` (`_start`),
`trigger_area.gd`, `trigger_arrived.gd`, `trigger_proximity.gd`, `mission_world.gd` (`_positions`, `_route_end`),
`wave_director.gd` (`_anchor_origin`, `_anchor_player`), `main.gd` (`_spawn_position`, `reference_point`),
`tier_director.gd` (`_park_origins`), the routes and posts pushed to the native brains with the frame origin as three doubles
(`brain.rs`). Static rows (`static_rows.gd`, `asteroid_belt.gd`, the mine and rock stand-ins) are World-local positions
with no velocity.

Globals that assume one frame. M6 adds none and fixes none; M11 must:

| Where | What |
|---|---|
| `src/perf/sim_core.gd` | `_current`: the latest core attached; `_civilians` |
| `src/world/static_rows.gd` | every column is static; rows carry their world's id, but `solid()`, `scan_columns()` and `version` are one cache |
| `src/ai/contact_scan.gd` | `_shared`, `_shared_broadcasts`: one scan per physics frame |
| `src/ai/ai_pilot_driver.gd` | `_live`, `_frame_scan`, `_frame_batch`, `player`, `_player_at` (a World-local point) |
| `src/perf/brain_batch.gd`, `native_brains.gd` | `_current`; `_host`, `_core` |
| `src/ai/tier_director.gd`, `src/combat/destruction_director.gd`, `src/combat/ram_resolver.gd` | `_current` |
| `src/targeting/targetable.gd`, `targeting_controller.gd`, `src/weapons/pulse_cannon.gd`, `src/combat/turret_mount.gd`, `src/rendering/lod_switcher.gd` | `_broadcasters`, `_live`: every instance in the process |
| `src/perf/standins/missile_standin.gd` | `native_rows` |
| `src/world/world_frame.gd` | the console provider `world` and the command `rebase`, registered under one name |
| `src/rendering/frame_passes.gd`, `light_rig.gd` | `_instance`; the first node of a group |
| `src/ai/perception.gd`, `ai_pilot_driver.gd` | `_default_origin`, `_no_origin`: zero origins for a ship with no world (harmless) |
| `SimClock` | one clock for every space (intended) |

## 5. Numbers

Test orbit: circular, 400 km above an Earth-sized planet (`GM` 3.986e14 m^3/s^2, `r` 6 771 km).

| Quantity | Value |
|---|---|
| Speed, period | 7 673 m/s, 5 545 s (332 691 ticks) |
| Escape speed there | 10 851 m/s (above the 9 999 m/s limit and Jolt's 10 000 m/s cap) |
| Epsilon III around the star (0.6 AU, 0.82 solar masses, assumed) | 34.8 km/s; 580 m per tick |
| A moon-distance orbit (384 400 km) | 1 018 m/s, 27.5 days (1.4e8 ticks) |
| Tidal gradient `2 GM / r^3`, low orbit | 2.57e-6 /s^2 |
| Tidal residual at 100 m, 1 km, 10 km, 50 km | 2.6e-4, 2.6e-3, 0.026, 0.128 m/s^2 |
| The same at the moon-distance orbit | 1.4e-9, 1.4e-8, 1.4e-7, 7e-7 m/s^2 |
| The star's gradient at 0.6 AU | 3e-13 /s^2: nothing over 50 km |

float32 in the local space (one unit in the last place, times 60 Hz):

| Position | Step | Slowest speed that moves it | | Speed | Step | Smallest acceleration that shows |
|---|---|---|---|---|---|---|
| 100 m | 7.6e-6 m | 4.6e-4 m/s | | 50 m/s | 3.8e-6 | 2.3e-4 m/s^2 |
| 1 km | 6.1e-5 m | 3.7e-3 m/s | | 200 m/s | 1.5e-5 | 9.2e-4 m/s^2 |
| 5 km | 4.9e-4 m | 0.029 m/s | | 2 000 m/s | 1.2e-4 | 7.3e-3 m/s^2 |
| 10 km | 9.8e-4 m | 0.059 m/s | | 5 000 m/s | 4.9e-4 | 0.029 m/s^2 |
| 50 km | 3.9e-3 m | 0.23 m/s | | 10 000 m/s | 9.8e-4 | 0.059 m/s^2 |

The game flies at up to 9 999 m/s in the frame today, so 0.059 m/s^2 is the accepted floor; at 2 000 m/s it is eight times
finer, and below a Starfury's thrust by a factor of 4 000.

The integrator, measured (a Python model of the tick: kick, then drift, 64-bit, 1/60 s):

| Case | Error against the analytic orbit |
|---|---|
| Circular, one orbit, velocity taken as given | 256 m at worst mid-orbit (0.011 m at the end) |
| Circular, one orbit, velocity started half a kick back | 0.0053 m at worst |
| `e` 0.3, one orbit (568 060 ticks), half-kick start | 0.0097 m at the end |
| `e` 0.7, one orbit (2 024 695 ticks), half-kick start | 0.12 m at the end |
| Circular, held 9e10 m from the coordinate zero | 0.021 m: 64-bit rounding (a step of 1.5e-5 m there), so states are held relative to the anchor |

A ship in float32 beside a 64-bit anchor, the same orbit, the ship ahead along the track, one orbit (the residual computed
in 64-bit and applied in float32, as the flight step will):

| Separation | Speed in the frame (the frame does not rotate) | Worst error against 64-bit |
|---|---|---|
| 100 m | 0.11 m/s | 0.004 m |
| 1 km | 1.1 m/s | 0.04 m |
| 3 km | 3.4 m/s | 0.08 m |
| 10 km | 11 m/s | 1.6 m |

"Stays beside it" is only true along the track. A ship 1 km above the station with no relative speed is on another orbit and
ends one orbit 37.7 km behind (`12 pi x0`): physics, not error. AC4's test must place the ship along the track, or compare
against a 64-bit run of the same start.
