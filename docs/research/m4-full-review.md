# M4-T43 full code review

Read-only review of `m4` at `9bb15ea` in the detached worktree `.claude/worktrees/m4-t43`, 2026-11-07, against
`task-t43-brief.md`. Five read-only subagents read one area each: the native crate, `src/perf` + `src/combat` + `src/weapons`,
`src/ai` + `src/ship` + `src/targeting` + `src/input` + `src/world`, the rendering/HUD/game/autoload side with the shaders and
`project.godot`, and `tests/` + `scripts/` + `tools/procgen` + CI. I checked every finding kept below in the code myself (the
quoted lines, the call order, and the "no callers" greps). Findings I could not confirm, or that only restate the earlier refactor
review's fixed items, were dropped. No code, doc or test was changed. I built the native library into a private cargo target and
ran the game four times for the measurements (section "Measurements").

Timings marked **measured** come from my runs or from report P3. Timings marked **estimated** are a reading of the code against P3's
stage table (at `battle` 1 000: flight 3.97 ms, resolvers 2.64, Jolt 1.13, unaccounted 1.12, targeting 0.97, AI main-thread 0.79,
stand-ins 0.71, core sync 0.46).

## Summary

Memory is clean. Twenty scenario reloads and ten minutes of `battle` 500 show no leak: objects, nodes, resources and VRAM stay flat,
orphan nodes plateau at 47 (a bounded cache, identified), static memory grows in steps to a plateau, and the exit lists no leaked
instances. The code base has no determinism or threading break that I could find.

What needs fixing before the merge is small and mostly correctness:

- the release export still cannot load its runtime GLSL, and a lens flare whose shader failed is switched back on and errors every
  frame (likely the "pipeline errors every frame" T25 saw);
- the core's broadcast scan appends rids to the rows' rid column, so a ship that comes back from the pool mid-tick has its ram
  contacts read from the wrong body for that tick;
- two statics keep a dead world's objects (the native brain host holds the old core and its step threads);
- a handful of wasted per-tick work items that are deletions (a full rows copy nobody reads, an unused per-hull engine call, two
  dictionary copies per tick);
- the GDScript fallbacks and always-true switches T37 was meant to remove, plus dead code on both sides;
- the carried-in items (the targeting snapshot, the explosion-LOD tests, `picture_lines`) and CI's timeout.

The large levers are for later: flight's per-ship GDScript gather (37 % of the tick at 1 000), the hit and ram resolvers' GDScript
loops (25 %), the radar's per-contact loop each frame, and a native allocation pass.

Counts: **fix in M4 11**, **later milestone 15**, **no action 9**.

| id | title | size | bucket |
|---|---|---|---|
| F1 | Release export: the runtime GLSL is not in the pack | S | fix in M4 |
| F2 | A failed lens flare is re-enabled and errors every frame | S | fix in M4 |
| F3 | `select` shifts `row_rids` against the rows (wrong body's contacts) | S | fix in M4 |
| F4 | Stand-in director builds a full `ContactScan` every tick and ignores it | S | fix in M4 |
| F5 | Statics outlive their world (`NativeBrains`, `TierDirector._damageables`) | S | fix in M4 |
| F6 | Small per-tick waste: ram `accel`, `BrainBatch` copies, contact grid alloc | S | fix in M4 |
| F7 | Leftovers of the removed paths (T37) and dead code | M | fix in M4 |
| F8 | Player targeting snapshot still walks the nodes (carried in) | S/M | fix in M4 |
| F9 | Explosion-LOD tests share the code's constants; `picture_lines` untested (carried in) | S | fix in M4 |
| F10 | CI: GUT timeout longer than the job; stale comments; missing info.md test | S | fix in M4 |
| F11 | Doc drift: "optional native library", stale comments | S | fix in M4 |
| L1 | Flight batch's per-ship GDScript gather | M/L | later |
| L2 | Hit resolver walks every bolt in GDScript; pairs unfiltered | M | later |
| L3 | Ram resolver's GDScript passes and string keys | M | later |
| L4 | Rebase cascade: statics shifted and re-sent, worst tick 14.7 ms | M | later (M6) |
| L5 | Radar fills its dot buffers per contact in GDScript each frame | M | later |
| L6 | Every AI shot anywhere gets a flash and a sound | S/M | later (M5) |
| L7 | Two `AudioStreamPlayer3D` per pooled ship, walked every frame | M | later (M5) |
| L8 | Native allocation pass (SipHash rebuilds, names per row, snapshot strings) | M | later |
| L9 | `note_hull` / `note_selection` scan every member per event | S | later |
| L10 | Explosion builds meshes and materials per death | S/M | later (M12) |
| L11 | Stand-in counters walk every ship each tick | S | later (M12) |
| L12 | Smaller per-frame and per-tick items (tier prune, quarantine, far proxies, light rig, wing context) | S each | later |
| L13 | Native and GDScript constants mirrored by hand | M | later |
| L14 | Test and script duplication; two always-pending balance tests | M | later |
| L15 | Export: bench reads and writes `res://reports` | S | later (M8) |
| N1-N9 | see "No action" | | no action |

## Fix in M4

### F1. Release export: the runtime GLSL is not in the pack

- **Where:** `src/rendering/runtime_shader.gd:10` (`FileAccess.get_file_as_string(path)`), called from
  `sky_velocity_effect.gd:76`, `motion_blur_effect.gd:132`, `velocity_probe_effect.gd:125`, and `lens_flare_effect.gd:42`
  (`patched_source` reads `res://addons/lens_effects/lens_flares.glsl` the same way). The preset is only described in
  `scripts/setup_export_templates.sh:8-12` (no `export_presets.cfg` is committed).
- **What is wrong:** five `.glsl` files are read as text at runtime, not the three P3 names: `motion_blur.glsl`,
  `motion_blur_copy.glsl`, `sky_velocity.glsl`, `velocity_probe.glsl` and the add-on's `lens_flares.glsl`. Each has a `.import` with
  `importer="glsl"`, so the exporter ships the remap and the imported `.res`, never the source. `include_filter` only adds files that
  have no importer, which is why adding `*.glsl` in T25 changed nothing.
- **Evidence:** `motion_blur.glsl.import` holds `importer="glsl"`, `type="RDShaderFile"`. T25's release log:
  `RuntimeShader: cannot read res://src/rendering/sky_velocity.glsl`.
- **Why not `load()` + `get_spirv()`:** `RuntimeShader` exists because a headless import cannot resolve `#include "godot/..."`
  and stores an empty shader (its header, and research-notes). The export would then depend on which machine imported last.
- **Fix (S):** set the four `src/rendering/*.glsl.import` files to `importer="keep"` (Godot's "Keep File (exported as is)"; the file
  becomes `[remap]` plus `importer="keep"`). The exporter then copies the raw bytes to the same `res://` path and `FileAccess` reads
  them in the editor and the export; the headless import also stops writing broken `RDShaderFile`s. For `lens_flares.glsl.import`:
  it was generated by Godot in M3-T25 (`b3c9805`), not taken from upstream, but it sits under `addons/lens_effects/`, which is
  no-edit. Either the maintainer allows that one generated file to change to `keep` (and `vendor_addons.sh` writes it after a
  re-vendor), or a project-owned `EditorExportPlugin` adds the file with `add_file(path, FileAccess.get_file_as_bytes(path), false)`.
  Add a guard test that reads the `.import` of every path handed to `RuntimeShader` and asserts `importer == "keep"`. Then re-take
  T25's release fullscreen pair (`battle` 500 and 1 000), as the T43 section says. Correct "three files" in `docs/roadmap.md:22`.

### F2. A failed lens flare is re-enabled and errors every frame

- **Where:** `src/rendering/lens_flare_effect.gd:29-35`, `src/rendering/post_effects.gd:91-93`,
  `addons/lens_effects/base_compositor_effect.gd:50-52`, `:142-144`.
- **What is wrong:** the add-on compiles its shader in `_init` through `call_on_render_thread`. On a failed compile
  `SceneLensFlareEffect.create_shader` sets `enabled = false`, but `PostEffects.apply_settings()` (on `_ready` and on every settings
  change) then sets `_flare.enabled = bool(Settings.get_value(&"lens_flare"))`, true by default. From then on the add-on's
  `_render_setup` calls `create_pipeline(invalid)` every frame, which does `push_error("Shader is not valid")` and returns an invalid
  pipeline. Motion blur and the sky effect return early on an invalid pipeline; the flare does not.
- **Evidence:** the code above. With F1 unfixed this is the effect that fails every frame in the export, a likely source of T25's
  "pipeline errors every frame" (not reproduced here: I did not build an export).
- **Fix (S):** a `usable` flag on `SceneLensFlareEffect` set by `create_shader`, and `apply_settings` sets
  `enabled = setting and _flare.usable`. A test with an unreadable source path.

### F3. `select` shifts `row_rids` against the rows

- **Where:** `native/src/sim_core.rs:866-911` (`select`), `:1272` (`push_member` does `self.row_rids.push(m.rid)`), read at
  `native/src/ram_phase.rs:76` (`let rid = core.row_rids[j];`).
- **What is wrong:** `select` (the broadcast scan) builds its own `Rows` but calls `push_member`, which also pushes into the core's
  own `row_names` and `row_rids`. `select` saves and restores `row_names` (`std::mem::take` / `std::mem::replace`) but not
  `row_rids`, so every call appends one rid per broadcaster to the core's rid column. `row_rids` is cleared only in `sync_in`
  (`:434`). When `resync_touched` then appends a late row (a ship back from the pool, `:1340-1345`), that row's rid lands past the
  broadcasters' rids, not at its own index. The ram phase reads `core.row_rids[j]` for that hull row and gets a broadcaster's body
  (contacts from the wrong body, a possible phantom ram) or an invalid rid (no ram).
- **Order:** the AI drivers call `ContactScan.shared_broadcasts` → `core.select` at priority -10 (`ai_pilot_driver.gd:650`), the hit
  resolver resyncs at 200 and the ram resolver reads at 210, so the bug fires in any tick where broadcasters exist and a ship
  activates. It lasts one tick (the next `sync_in` clears the column).
- **Fix (S):** take and restore `row_rids` in `select` as it does `row_names`, or give `push_member` the columns to fill. A Rust
  test: sync, `select` with a broadcaster, activate a body, resync, and assert `row_rids.len() == rows.len()` and the late row's rid.

### F4. Stand-in director builds a full `ContactScan` every tick and ignores it

- **Where:** `src/perf/standins/standin_director.gd:105` (`step(delta, SimClock.now(), ContactScan.shared(get_tree()))`), `:109`.
- **What is wrong:** `step` never reads its `scan` argument (grep: the only use of `scan` in the stand-ins is that line). Once every
  AI driver is hosted (M4-T35) nothing else asks for `ContactScan.shared`, so this call alone rebuilds it each `battle` tick:
  `ScsSimCore.snapshot()` (14 columns of every row, one `StringName` and one name string per row, forwards and ups computed) and
  `_append_static_rows` (the 1 000 rocks and 1 000 mines appended column by column), `contact_scan.gd:166-179`, `:562-576`.
- **Evidence:** the code; it runs outside the stand-ins' own timer, so it shows up in P3's "unaccounted" 1.12 ms. Size **estimated**
  at 0.1 to 0.3 ms at 1 000 (not measured; measuring it needs a code change).
- **Fix (S):** drop the argument and the call. Tests that drive `step` build their own scan with `from_core`. Re-take the `battle`
  numbers T25 reported if the maintainer wants them current.

### F5. Statics outlive their world

- **Where:** `src/perf/native_brains.gd:10-13` (`static var _host`, `_core`), `:46` (`drop()`); `src/ai/tier_director.gd:40`
  (`static var _damageables: Dictionary[int, Damageable]`), `:449-459`.
- **What is wrong:** `NativeBrains` keeps the `ScsBrains` host and the `ScsSimCore` it is attached to (both `RefCounted`) in statics.
  After the world leaves, the old core's rows, its RIDs and the host's step threads stay alive until the next world calls `host()`.
  `drop()` has no caller anywhere (grep over `src`, `tests`, `scripts`: only its definition). The reload loop shows no growth because
  the next world replaces the pair, but a world that ends without a successor (the front end M5 adds, or a test) keeps it.
  `TierDirector._damageables` survives scene reloads and keeps entries for freed hulls (each `is_instance_valid`-checked, so only
  the entries leak, bounded by the hulls ever hit in the tier).
- **Fix (S):** call `NativeBrains.drop()` from `SimCore._exit_tree` when `NativeBrains`' core is this core; make `_damageables` an
  instance variable or clear it in `TierDirector._exit_tree`. Remove `NativeBrains._class_known` and its null return (F7).

### F6. Small per-tick waste removable by deletion

- **Ram `accel`.** `src/combat/ram_resolver.gd:283`: `_hull()` stores `"accel": _accel(i)` (an `instance_from_id` plus an
  `applied_force()` read) for both hulls of every near pair each tick. Nothing reads it: grep for `"accel"` finds this literal, the
  stub at `:460`, and a test fixture. Delete it.
- **`BrainBatch` copies.** `src/perf/brain_batch.gd:275-276`: `_hosted.duplicate()` and `_hosted_brains.duplicate()` on every flush,
  about 1 000 entries each at 1 000 ships. Copy only when host/unhost changed them (a version counter). `_dts` (`:63`, `:267`, `:424`)
  is never appended to: delete.
- **Contact grid allocation.** `native/src/brain_step.rs:653` and `native/src/contact_field.rs:121`, `:135` call
  `contact::sorted_cells(...)`, which allocates a fresh `Vec` each rebuild; `sorted_cells_into` (`kernels.rs:73`, "no allocation once
  it has grown") exists for this. Swap the calls.
- **Fix (S, together).** No behaviour change; the parity fixtures stay as recorded.

### F7. Leftovers of the removed paths (T37) and dead code

CLAUDE.md: "Never add a GDScript fallback or a setting that switches back to an old path." These remain:

- `src/ship/flight_batch.gd:206-209`, `:251-259`: with no step class or a refused step, every ship "flies its own model" in GDScript
  (`fly_own_tick_now`).
- `src/perf/standins/missile_standin.gd:117-123`: a GDScript steering path when the kernel did not answer; tested as such in
  `tests/unit/test_missile_kernel.gd:155` (`test_a_missile_without_a_core_steers_in_gdscript`).
- `src/perf/standins/turret_standin.gd:80-86`: a `Projectile` node per shot when there is no core (every world has one since T42).
- `src/perf/sim_core.gd:199-205` (`enabled()`), `:247-259` (`bolt_rows_enabled()`, `selection_check_enabled()`), `:276-282`
  (`bolt_rows_path()` with its `&"nodes"` answer): always-true switches; `targeting_controller.gd:116` still branches on
  `selection_check_enabled()`.
- `src/ai/ai_pilot_driver.gd:263-284`: a native-capable pilot with no slot yet and stale rows runs the GDScript `perceive()` and
  `AiPilot.think`; the doc at `:38-41` says it "perceives and thinks in GDScript as before".
- `native/src/native_probe.rs:5` and `tests/unit/test_native_probe.gd:22`, `:30`: `NativeProbe.new(false)` still forces a GDScript
  path (used by `native_boundary_bench.gd:17`).
- `src/perf/native_brains.gd:12`, `:21-24` and `NativeWeapons.available()` (doc "GDScript takes over again"): the optional-class
  lookups.
- `tests/fixtures/tier_world.gd:9`, `:40`: `use_native()` / `NATIVE_SETTINGS` sets a bool that defaults to true; a misnamed
  remnant of the `perf_native*` list.

Dead code (each checked with `grep -rnw` over `src tests scripts tools native/src`; one hit means only the definition):

- Native `#[func]`s with no GDScript caller: `ScsBoltSync.reads_open`, `ScsBrains.wake_driver`, `randi_sequence`,
  `ScsSimCore.engine_calls_open`, `bolt_tick`, `set_row_motion`, `set_row_state`, `data_rows`, `selection_check_of`,
  `tier_type_count`, `tier_set_hull`, `tier_body_ids`, `tier_period`, `tier_demotions`, `tier_missiles` (the last four are field
  names inside Rust but have no GDScript caller as functions). The DataRow seam (`sim_core.rs:127`, `:1039-1148`) is used only by
  `test_sim_core.gd` and the wrappers at `sim_core.gd:441-458`; T20 built `weapon_rows` instead.
- GDScript: `NativeBrains.drop` (or wire it, F5), `TierDirector.is_tiered`, `MineStandin.triggers`/`blast`/`broad_phase`,
  `StandinDirector._shot_at`/`_grid`/`FIGHTER_RADIUS_MAX_M`, `SimCore.FLAG_LATE`/`FLAG_HULK`, `HitBroadPhase.native_available`,
  `PulseCannon.muzzle_locals`, `BoltMesh.look_count`, `DamageZones.zone_count_now`, `Upscaler.current_plan`,
  `CameraRig.look_angles`, `TargetBracket.get_bracket_position`, `ConsoleArg.path_optional`,
  `ConsoleRegistry.unregister_command`.
- `tools/procgen`: `core/textured_mesh.py:63 _material_table`, `parts/propulsion.py:575 mark_band`,
  `parts/__init__.py:148 merge_meshes`, `parts/starfury.py:45 strip_loft` (no references).

**Fix (M):** one cleanup task. Remove the fallbacks with the tests that assert them (`test_missile_kernel:155`,
`test_native_probe`'s false case, the no-core world in `test_muzzle_flash_pool.gd:76`, `:127`), the switches and the dead functions;
keep each parity test green against `tests/fixtures/`. Where a test needs a ship outside a world, give it a world.

### F8. Player targeting snapshot still walks the nodes (carried in)

- **Where:** `src/targeting/targeting_controller.gd:308-333` (`_snapshot`, from `refresh()`); tier rows through
  `tier_targets.gd:27-31`, `:50-60` and the native `tier_targets` (`tier_rows.rs:717`).
- **What is wrong:** every tick the player's controller calls `get_nodes_in_group(Targetable.GROUP)` (an Array of every marker,
  parked ones included), and per node `is_ancestor_of` and `is_active()` (two tree walks) and four appends including a String. Then
  the tier gather builds nine columns per tier row in reach, of which the snapshot reads four. T23's review measured +0.19 ms at
  1 000. The radar already reads the same set from the core's rows.
- **Fix (S/M):** call `sim.core.resync_touched_now()` (as `SimCore.check_selections_now` does at that priority), then
  `sim.core.radar_contacts(pos, body_id, sensor_range)` (`sim_core.rs:1837`), which returns the in-reach ids, positions and reach
  for near and tier rows. `marker_active` (`sim_core.rs:1583`) makes the same checks as `Targetable.is_active`, and every marker sits
  at its body's origin. Drop `_snap_names`; `selected_name()` reads the selected marker. The fixture test
  (`test_targeting_on_read.gd:83-129`) calls `refresh()` 600 times inside one physics frame while moving and freeing markers, so it
  must call `SimCore.for_tree(get_tree()).sync_now()` before each refresh; the digest may then come out the same. If it does not,
  re-record `targeting_on_read.json`. Do not move the player onto the core's selection watch (that changes `stale_selects`).

### F9. Explosion-LOD tests share the code's constants; `picture_lines` untested (carried in)

- **Where:** `tests/unit/test_explosion_lod_maths.gd:18-58`; `src/combat/explosion_lod.gd:22` (`FIREBALL_RADII = 1.2`) beside
  `src/combat/explosion.gd` (`FIREBALL_FINAL_SCALE = 1.2`); `explosion_lod.gd:103-106` (`picture_lines`).
- **What is wrong:** the tests build their expectations from `ExplosionLod.PEAK`, `FULL_PX`, `REDUCED_PX` and the class's own
  distance functions, so a changed constant moves the expectation with it. `FIREBALL_RADII` copies `Explosion.FIREBALL_FINAL_SCALE`
  by hand with no tie. `picture_lines` returns `DEFAULT_LINES` under the headless display, so no test reaches its
  `Upscaling.internal_lines(…, scaling_3d_scale)` branch (grep finds no test of it with a scale).
- **Fix (S):** pin a few literal distances (a fighter at 1 080 lines, a cruiser at 2 160); make `FIREBALL_RADII` read
  `Explosion.FIREBALL_FINAL_SCALE`; split a pure `picture_lines_for(window_lines, scale, headless)` and test 2 160 lines at FSR
  quality giving 1 440.

### F10. CI: GUT timeout longer than the job; stale comments; a test the comment promises

- **Where:** `scripts/run_tests.sh:91` (`timeout 3600` on GUT), `.github/workflows/ci.yml:33` (`timeout-minutes: 60`); comments at
  `ci.yml:8-9` ("a test checks the console command list against it"), `ci.yml:29-30` and `run_tests.sh:89` ("about 25 minutes").
- **What is wrong:** GUT's own timeout can never fire before the job is killed, so a hang shows as a cancelled job with no GUT
  summary (noted in M3's final review, still open). No test reads `info.md` (grep over `tests/`); the list matches the code today
  (54 commands, 35 providers), but nothing keeps it so.
- **Fix (S):** GUT timeout about 40 minutes per shard, the comments updated, and one GUT test comparing `DebugConsole.registry`'s
  commands with `info.md`'s table.

### F11. Doc drift

- `native/Cargo.toml:1` "The game's optional native library"; `native_probe.rs:5` "falls back to its own code when the library is
  missing"; `native_brains.gd:4-5` "a pilot the host cannot carry thinks in GDScript"; the stand-ins' headers ("this code is then
  the reference", `turret_standin.gd`, `mine_standin.gd`).
- `src/ship/ship.gd:28` says `contact_monitor` is on; `:679` turns it off. `ai_pilot_driver.gd:94-95` are comment lines with no
  variable under them.
- **Fix (S):** with F7.

## Later milestone

No roadmap milestone owns a performance pass after M4. Where none fits, "later" means a performance task the maintainer schedules
(M5 runs beside M4 and has room).

### L1. Flight batch's per-ship GDScript gather (the biggest lever)

- **Where:** `src/ship/flight_batch.gd:221-237`, `:264-265`; `src/ship/ship.gd:489-507` (`batch_gather`), `:1000-1008`;
  `src/targeting/targeting_controller.gd:179-189` (`selected_offset`).
- **What is wrong:** per ship per tick: two dictionary lookups, `can_process`, `is_inside_tree`, `batch_gather` (a
  `global_basis.transposed()`, `selected_offset()` with an `instance_from_id`, two ancestor walks and two `global_position` reads,
  `_environment_accel()` as a Callable into the moon stand-in, 14 packed writes), then a second loop calling the no-op
  `set_batch_owned(true)`, and five `.slice()` copies. For a row-commanded AI ship the native step overwrites levels, strafe, rot and
  brake from the row (`flight_step.rs:355`, `row_commands.rs:70-75`), so most of that gather is thrown away.
- **Evidence:** P3 **measured** flight at 3.97 ms of 10.68 at 1 000 (gather plus forces into Jolt).
- **Fix (M/L):** a native "row-commanded" step over the core's rows: `face_dir_b` from the target row only when the row brakes, the
  pull from the native gravity sources (the tier already has `tier_set_gravity`), assist/hulk/propellant as per-slot flags set on
  change. GDScript then gathers only ships without a row command. **Estimated** 1.5 to 2.5 ms at 1 000.

### L2. Hit resolver walks every bolt in GDScript; pairs unfiltered

- **Where:** `src/combat/hit_resolver.gd:163-179`, `:187-201` (`_pair_ranges`), `:225-243`; `native/src/sim_core.rs:976`
  (`bolt_columns`); `native/src/hit_sweep.rs:82` (`pairs_core`); per hit `:429` (`hash([...])` allocates an Array for a seed
  `ImpactFlash.create` ignores) and `:365`, `:446` (`last_hit` formatted with two name walks per hit).
- **What is wrong:** every tick `bolt_columns()` builds 15 arrays over every bolt (factions as `Array[StringName]`), `_pair_ranges`
  resizes and fills two bolt-sized arrays, and the loop visits every bolt though few have pairs. `pairs_core` does not drop the
  shooter's own hull, friendly or spent pairs, so each new bolt pairs with its shooter on its first tick and is dropped in GDScript
  after an `instance_from_id` and a `bolt_live` call.
- **Evidence:** P3 **measured** the hit stage at 1.41 ms for 1 069 bolts at 1 000.
- **Fix (M):** the native side returns only bolts with live hostile pairs, in launch order, with their columns; later the narrow phase
  in native too (L). The per-hit `hash` and `last_hit` formatting are S.

### L3. Ram resolver's GDScript passes and string keys

- **Where:** `src/combat/ram_resolver.gd:313-315`, `:351-357` (`_index()`), `:384-397`; `src/combat/ram_tracker.gd:108`, `:123`,
  `:162-174`, `:291`.
- **What is wrong:** a loop over every rigid hull to check `known`; `current_at` rebuilt for all ids and a second 1 000-entry
  dictionary whenever anything touches; `"%d:%d"` / `"%d>%d"` string keys per contact per tick; an 11-key dictionary per near pair
  built before the rigid/tunnelling check sends most pairs away.
- **Evidence:** P3 **measured** the ram stage at 1.20 ms at 1 000.
- **Fix:** S quick wins (contacts return hull indices so `_index()` goes; fill `current_at` only for touched ids; test rigid and
  layers from columns before `_hull()`); M to move `RamTracker` into native, which the per-tick-native rule asks for.

### L4. Rebase cascade (M6)

- **Where:** `src/world/world_frame.gd:167-175`; `src/world/static_rows.gd:92-104`, `:138-153`; `src/perf/sim_core.gd:529-531`.
- **What is wrong:** a rebase walks every `world_shiftable` node (hidden pool ships too); `StaticRows.shift` loops over every static
  row in GDScript and bumps `version`, which rebuilds `solid()` in both resolvers, their grids, `scan_columns()`, and re-sends every
  static to the core. The earlier refactor review's item 11, still open.
- **Evidence:** **measured** in my 10-minute run: 202 rebases, the worst tick holding one 14.69 ms against a 6.04 ms median. P3: the
  worst rebase tick at 1 000 is 13.07 ms against 10.50.
- **Fix (M):** shift the statics natively and the cached `Solid` in place (a pure shift is not a new version); skip hidden ships. M6's
  moving `WorldFrame` and velocity rebase rewrite this path.

### L5. Radar fills its dot buffers per contact in GDScript each frame

- **Where:** `src/hud/hud_painter.gd:462-484` (`_fill_dot_buffers`, a `_put_dot` call with 12 indexed writes per contact, two per
  contact with backings), `:515-520` (a `buffer.slice` copy when the multimesh is larger than the buffer); `radar_model.gd:121-123`
  fills `factions` per contact, read only by `RadarPlot.to_dots()` (tests and readouts).
- **Evidence:** P3 **measured** 5 to 6 ms per frame outside the ticks at 1 000 for the HUD and radar together; this loop's share is
  **estimated** at 0.5 to 1.5 ms.
- **Fix (M):** `ScsRadarPlot.plot` takes the screen transform and radii and returns the three buffers; `factions` built lazily.

### L6. Every AI shot anywhere gets a flash and a sound (M5 sound pass)

- **Where:** `src/perf/sim_core.gd:339-342` → `MuzzleFlashPool.trigger` (`muzzle_flash_pool.gd:180-185` counts lit lights over up to
  256 emitters; `:91-92`, `:166-171` `remove_at(0)` on four arrays when full) and `shot_fired` → `audio_director.gd:241`
  (`voice.play()` per shot, stealing voices, km away or not).
- **Fix (S/M):** a ring buffer and a lit counter; cull flashes and sounds beyond a range from the camera before they are made.

### L7. Two `AudioStreamPlayer3D` per pooled ship, walked every frame (M5 sound pass)

- **Where:** `src/audio/audio_director.gd:236-266` (`watch_ship`), `:281-312` (`_update_engines`).
- **What is wrong:** 2 000 audio nodes at 1 000 ships, and each frame per entry: dictionary reads, two `is_instance_valid`,
  `is_visible_in_tree`, `can_process`, a `global_position` read. The earlier review's item 7, still open.
- **Fix (M):** about 8 hum/hiss voices given to the nearest ships within `ENGINE_RANGE_M`, found from the core's rows.

### L8. Native allocation pass

- `sim_core.rs:1360-1393` `index_rows`: each sync builds a fresh SipHash `ranks` map over every member and a new `hull_rows` Vec, and
  refills `row_of_id`/`row_of_handle` with SipHash; carry `hull_rank` as a row column and use the `IdHasher` from `row_commands.rs`
  (fix round 2 found SipHash was a fifth of a tier row's cost).
- `sim_core.rs:1282`, `:1303` push a cloned `name_key` per row per sync; `brain_behaviours.rs:201-221` matches names by string
  compare over all rows; intern a `u32` name id.
- `sim_core.rs:845`, `:1538` `snapshot`: one `StringName` per row each call; send faction indices (with F4 there is one caller fewer).
- `sim_core.rs:467-489`: every rock and mine re-copied into all columns each sync; cache the static block.
- Small: `sweep_cells.rs:59` drops each cell's Vec per tick; `bolt_kernels.rs:23`, `:51` a new `keep: Vec<bool>` per step;
  `tier_rows.rs:521` a new `HashSet` per call; `weapon_rows.rs:292-300` nine Vecs per step; `resync_touched` collects `touched` into a
  Vec and calls `contains` per member (`sim_core.rs:1311-1316`).
- **Fix (M):** one pass; each item is S. Not measured; P3's core sync is 0.46 ms at 1 000.

### L9. `note_hull` / `note_selection` scan every member per event

- `native/src/sim_core.rs:1742-1770`: each damage event (`sim_core.gd:641`, `:646`) walks every marker and hull; cost is hits times
  members. A body-id → member index map rebuilt in `set_members` (S). `latest_target` (`:217`) is never pruned for freed bodies
  (growth per spawn over a world's life, small).

### L10. Explosion builds meshes and materials per death (M12)

- `src/combat/explosion.gd:135-165`: per death a duplicated `StandardMaterial3D`, a `QuadMesh`, a 28 × 14 `SphereMesh` (generated on
  the CPU) and a `ShaderMaterial`. Share the meshes and materials, make `age` an instance uniform, pool the nodes as `ImpactFlash` is.
  M12's staged capital break-up rewrites this (S/M).

### L11. Stand-in counters walk every ship each tick (M12)

- `src/perf/standins/standin_director.gd:498-526` (`_count`, every tick from `_finish`): `ships.alive()` duplicates the pool's array,
  then `is_tier_parked()` and a `global_position` read per ship, plus four loops over the capitals. It runs at priority -5 and so
  lands in the flight stage it helps measure. Compute near/far at 1 Hz or from the rows (S). M12 replaces the stand-ins.

### L12. Smaller items (S each)

- `src/ai/tier_director.gd:606-618` `_prune` walks every tier row each tick (`keys()` allocates about 580 at 1 000); run it when
  `sim.removals` changed.
- `src/weapons/bolt_slot_quarantine.gd:275-319` duplicates the buffer and loops over every slot every frame under TAA; check slots in
  the core's `bolt_transforms`.
- Far proxies: `far_flashes.gd:75` rewrites and uploads the whole buffer per `add()` (O(n²) when many die in a frame), `:136` uploads
  with zero flashes; `far_hulls.gd:112` sets `instance_count` on every change (reallocates).
- `light_rig.gd:60-68`, `light_picker.gd:39-58`: `get_global_transform_interpolated()` per lit emitter per frame.
- `wing_director.gd:418-428` assigns every `AiContext` field each tick and each setter marks it changed, so every wing member is
  pushed to native every tick; compare before assigning.
- `main.gd:619` builds `selected_readout()` before testing `hud.visible`; `hud_painter.gd:388-410` rebuilds silhouettes per frame.
- `src/perf/sim_core.gd:540`, `:551`: two `get_nodes_in_group(Projectile.GROUP)` per tick for the player's bolts, beams and missiles;
  `beam_standin.gd:168` instantiates a scene per beam (beams as owned rows, M).
- `ai_pilot_driver.gd:201-215`: each of 1 000 drivers rebuilds the AI console vars on enter and exit (spawn cost, not per tick).
- `ship.gd:1050` a new `PackedFloat64Array` per ship per output read.
- `contact_field.rs:374`: a core-attached field passes `reach: &[]` though `rows.reach` exists; latent (the broadcast scan loads
  arrays today), but a trap.
- Duplicated maths: `weapon_kernels.rs:566-620` re-implements `v3`; `sim_core.rs:1672-1705` too; the 64-bit range is written out in
  several places. `_uniform` and the PREDELETE scaffolding are copied in the three compute effects; `FarDots`/`FarFlashes`/
  `FarHulls` repeat their multimesh setup.

### L13. Native and GDScript constants mirrored by hand

- 19 Rust comments name the GDScript constant they copy, for example `brain.rs:32 SENSOR_RANGE_M` from `contact_scan.gd:44`;
  `INTERCEPT_RANGE_M` in `tier_fire.rs:38`, `weapon_kernels.rs:19` and `turret_standin.gd:14`; `kernels.rs` copies
  `RamResolver.MARGIN_M`, `AvoidanceMath.MARGIN_M`, `FireLane.CLEARANCE_M`. No test compares them. A `#[func] constants()` on the core
  and one GUT test (M).

### L14. Test and script duplication; always-pending balance tests

- About 80 copy-pasted test helpers: `_ticks(n)` 29 copies, `_exec(line)` 11, `_console(line)` 10, and others; one `TestSteps`
  fixture (M).
- `tests/unit/test_core_state.gd:348`: the three `OLD_PATH_CASES` recordings are byte-identical; collapse to one (S).
- `tests/integration/test_m3_sandbox.gd:73-76` and `test_dogfight.gd:106-108` end `pending` on every run since 2026-11-01 (AC12
  balance under review) yet cost minutes of simulated fight per CI run. Until the maintainer retunes (M5, or whenever AC12 is
  revisited), run them outside `GUT_SLOW` as a manual balance check.
- CI: shard 1 takes 24 minutes against 16 for shards 2 and 3 because it alone runs the Python tests (325 s) and the console smoke
  runs; give the Python tests their own job and cache `assets/generated` on `hashFiles('tools/procgen/**')`. `run_tests.sh` has 22
  copy-paste smoke blocks; the lock paths are hard-coded in seven scripts (S/M).

### L15. Export: the bench reads and writes `res://reports` (M8)

- `src/perf/bench_runner.gd:28`, `scripts/bench_sweep.gd:46`: in an export `res://` is the pack, which is why T25's sweep summary hung.
  A `user://` or absolute report root for exported builds (S). M8 ships the release build.

## No action

- **N1. Memory across reloads and a long battle.** No leak (measurements below). The static creep in the reload loop is about 4 KB per
  reload, inside allocator noise.
- **N2. The 47 orphan nodes in `battle`.** All are `Damageable` nodes from `RamResolver._rock_hulls` (`ram_resolver.gd:104`,
  `:434-447`): one per rock a ship rammed, kept out of the tree on purpose and freed in `NOTIFICATION_PREDELETE` (`:146-150`).
  Bounded by the rock count. Entries for a replaced asteroid field linger until the resolver goes; M14 replaces the field.
- **N3. Pools kept after a bench.** After the 600 s bench ended the world kept 5 902 nodes and 318 MB static until the scene left
  (151 MB). The pools stay for reuse by design; a scenario reload frees them.
- **N4. Exit leak in `dogfight`.** Quitting `dogfight` after 5 s leaked one `AudioStreamWAV` and its `AudioStreamPlaybackWAV` (a sound
  playing at quit). Engine-side teardown order; no other run leaked anything.
- **N5. `Image format RGBFloat not supported by hardware, converting to RGBAFloat`** once per scene load, from
  `assets/fx/fx_explosion_gas.tres`. A load-time conversion; writing the texture as RGBA in procgen would silence it.
- **N6. `MultiMesh interpolation is being triggered from outside physics process`** about once per scene load and 11 times at a
  battle's start: the asteroid and mine multimeshes are set up in `_ready` (`asteroid_field.gd:46`, `mine_standin.gd:81`). Benign at
  setup.
- **N7. The far-proxy cost's max of 0.506 ms against T23's 0.5 ms bar** (carried in): one window's maximum, 1 % over; the mean is
  0.2 ms.
- **N8. Determinism and threading.** None found: worker scratch is cleared per think, `HashMap` order never feeds a result
  (`free_slots_of` sorts), RNG is a per-brain `Pcg` or the seeded `tier_fire::roll`, no engine call inside the kernels or off the main
  thread, no `Input` read outside `godot_input_source.gd`, no wall clock in gameplay.
- **N9. Console registrations and signals across reloads.** Every registration passes its owner and calls `unregister_owner`;
  signals to autoloads come from nodes and are disconnected when they are freed; the compute effects free their RIDs in PREDELETE.

## Measurements

Editor build, the native library built from `9bb15ea` into a private cargo target, `XDG_DATA_HOME=~/.cache/scs-agents/m4-t43`. A
sampling harness in my scratchpad (a `SceneTree` script that runs the main scene and prints `Performance` monitors every 10 s; not in
the repo) recorded static memory, objects, nodes, orphan nodes, resources, Godot's video memory and
`/sys/class/drm/card1/device/mem_info_vram_used`. Logs: `~/.cache/scs-agents/m4-t43/{reload,battle500,orphans,leak_x}.log`.

**Scenario reload loop** (windowed 960 × 540 on the RX 6950 XT, `--verbose`, under the GPU lock): five rounds of `combat_sandbox`,
`free_flight`, `instructor_route`, `dogfight`, 10 s each, 20 reloads, then quit.

| sample (`combat_sandbox`, round) | static MB | objects | nodes | orphans | resources | Godot VRAM MB |
|---|---|---|---|---|---|---|
| 1 | 154.93 | 4 237 | 511 | 0 | 361 | 283.8 |
| 2 | 155.11 | 4 243 | 511 | 0 | 361 | 283.8 |
| 3 | 155.13 | 4 243 | 511 | 0 | 361 | 283.8 |
| 4 | 155.14 | 4 243 | 511 | 0 | 361 | 283.8 |
| 5 | 155.16 | 4 243 | 511 | 0 | 361 | 283.8 |

The other three scenarios repeat their own values every round (`free_flight` 2 962 to 2 968 objects, 313 nodes; `instructor_route`
3 059 to 3 061, 329; `dogfight` 4 051, 437). System VRAM 2 810 to 2 822 MiB throughout (2 513 MiB before the run). Exit: no leaked
instances.

**`battle` 500 for 10 minutes** (`bench battle 500 600`, windowed 960 × 540, `--verbose`, under the bench and GPU locks):
`425 ships in play`, tick median **6.04 ms**, p99 11.35 ms, 0.00 % behind real time, 202 rebases (worst tick holding one 14.69 ms),
pass.

| t (s) | static MB | objects | nodes | orphans | resources | Godot VRAM MB | system VRAM MiB |
|---|---|---|---|---|---|---|---|
| 11 | 303.4 | 54 699 | 7 569 | 1 | 363 | 284.5 | 2 821 |
| 111 | 318.4 | 55 094 | 7 506 | 22 | 363 | 284.7 | 2 818 |
| 211 | 320.4 | 55 183 | 7 442 | 37 | 363 | 284.7 | 2 818 |
| 311 | 320.0 | 55 329 | 7 482 | 46 | 363 | 284.7 | 2 818 |
| 411 | 322.1 | 55 290 | 7 442 | 47 | 363 | 284.8 | 2 818 |
| 511 | 325.4 | 55 289 | 7 442 | 47 | 363 | 284.8 | 2 818 |
| 601 | 325.4 | 55 291 | 7 442 | 47 | 363 | 284.8 | 2 818 |
| 612 (bench over) | 317.8 | 52 203 | 5 902 | 47 | 363 | 284.7 | 2 822 |
| quit | 151.6 | 3 367 | 0 | 0 | 283 | 284.7 | 2 798 |

Static memory grows in steps (303 to 322 MB in the first 200 s, one step of 3.4 MB at 471 s) and is flat between them; objects and
nodes flat from 300 s; orphans plateau at 47; VRAM flat. Exit: no leaked instances.

**Orphan identification:** a headless `bench battle 500 170` with `Node.print_orphan_nodes()` after 150 s listed 31 stray nodes, all
`Node` with `res://src/combat/damageable.gd` (N2).

**Exit leak checks** (`--verbose --headless`): the default scenario after 600 frames, after 22 frames, and `bench battle 50 3`: no
leaks. `scenario dogfight` after 300 frames: 2 instances (N4).

Report folders written by these runs (gitignored, in the main `reports/perf/`): `t43_mem500`, `t43_orphans`, `t43_leakchk`.

Not done: an export build (F1 and F2 are read from the code and T25's log), and per-finding timings that would need code changes
(F4, L1 to L5 are estimated from P3's stages).
