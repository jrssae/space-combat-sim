# Milestone 1: First Flight

> "A working 3D space combat ship (based on the Starfury design) in a starry background with a little bit of a
> nebula visible."

Read `docs/architecture.md` first; task notes below reference its sections (§). Tasks are ordered; each is one
PR-sized unit for an implementation agent. Do them in order unless a task says otherwise.

## Scope

In:
- Godot 4.7.2 project, Forward+, Jolt, vendored GDGS v3.3.0 and GUT v9.7.1, CI green on every PR.
- Procedurally generated Starfury-style ship as Gaussian splats (+ mesh fallback), generated star field and
  nebula as splats (+ panorama fallback), all from committed Python generators.
- Player ship with Newtonian 6DOF flight on a generic XInput gamepad (SDL3 standard layout): main/retro thrust, 2-axis strafe, pitch/yaw/roll,
  rotation assist toggle (default on), hold-to-brake, reset.
- First-person cockpit camera and third-person chase camera, toggle on Y.
- Two forward pulse cannons firing visible projectiles that inherit ship velocity; muzzle flash; thruster glow.
- Debug overlay (speed, velocity, angular rate, assist/camera state, splat backend, FPS).
- Headless test suite (Python + GUT) and GitHub Actions CI.

Out (explicitly):
- Enemies, AI, targets, damage, hit detection beyond projectile lifetime, shields, HUD beyond the debug overlay.
- Audio, music, menus, settings UI (settings are a config file), save games, localisation.
- Splat *training* (Brush/gsplat), GDGS relighting, collision generation from splats.
- Floating origin, capital ships, jump gates, stations, multiplayer, VR, mobile, web export, release packaging.
- Mouse flight; keyboard beyond the fallback bindings in the InputMap table.
- Asset polish passes (decals, markings, cockpit instruments).

## Acceptance criteria

`(A)` = an agent verifies headlessly in the container/CI. `(H)` = needs a human on the acceptance platform:
**Linux, discrete Vulkan GPU, generic XInput gamepad**, GDGS Compute backend. Windows is secondary: it must not be
broken knowingly, but it is not an M1 gate. M1 is done when every (A) passes in CI and every (H) is ticked by the
user on `main`.

| # | Criterion | Who |
|---|---|---|
| AC1 | `scripts/setup_godot.sh` installs Godot 4.7.2 into `.tools/godot/` with SHA-256 check; `scripts/run_tests.sh` exits 0 in a fresh container clone | A |
| AC2 | CI workflow runs Python tests, asset generation, `--import` with zero `SCRIPT ERROR`/`Parse Error`, and GUT; fails on any test failure | A |
| AC3 | `scripts/gen_assets.sh` produces `starfury.ply` (100k-250k splats), `starfury.obj`, `cockpit_interior.obj`, `starfury_hardpoints.json`, `sky_splats.ply` (10k-25k splats), each with `manifest.json`; two runs with the same seed are byte-identical | A |
| AC4 | After `--import`, both PLYs load as `GaussianResource` with `point_count` equal to the manifest and AABB matching the manifest (Godot frame) within 1 cm | A |
| AC5 | Ship integration test: 50 % RT for 2 s from rest gives speed `0.5·thrust_main/mass·2` ±1 %; speed unchanged (±0.1 %) 3 s after release; a 60°/s spin with assist on stops (< 1°/s) within 1.5 s; with assist off it does not decay (±0.5 %) | A |
| AC6 | Input unit tests: deadzones, expo curve, invert-Y, edge-triggered toggles, every InputMap action in §6.1 exists in `project.godot` | A |
| AC7 | Projectile test: spawns at a muzzle hardpoint, velocity = ship velocity + 400 m/s forward, frees itself after 4 s; fire rate gate 4 Hz alternating muzzles | A |
| AC8 | `main.tscn` runs 180 frames under `--headless --quit-after 180` with no errors; camera toggle flips `current` and `CockpitInterior.visible` | A |
| AC9 | Ship renders as splats (not the fallback mesh) in both camera modes; hull orientation and position match the collision proxy/fallback mesh when toggled (D-pad Down) | H |
| AC10 | Star field and nebula visible as splats; no parallax when flying; no popping between sky and hull; cockpit frame correctly occludes hull splats | H |
| AC11 | On the tester's generic XInput pad: controls behave per the §5.2 table; both triggers reach full thrust and rest at zero (trigger calibration works); sticks have no drift at rest; releasing RT does not slow the ship; assist-off spin persists; brake stops drift; assist toggle and camera toggle work on B and Y | H |
| AC12 | 60 fps at 1080p on the tester's Linux/Vulkan GPU (overlay FPS), no hitching when firing | H |
| AC13 | Thruster glow responds to thrust/strafe/rotation inputs; projectiles and muzzle flash visible from both cameras | H |
| AC14 | Overlay shows splat backend `Compute` on the Linux/Vulkan machine (`Raster` only with a recorded reason); fallback mesh/panorama appear automatically if neither backend initialised | H |
| AC15 | Unit tests prove trigger normalisation for rest = 0 and rest = -1, and that every pad binding uses only standard `JOY_AXIS_*`/`JOY_BUTTON_*` values 0-5 / 0-14 | A |
| AC16 | (optional, non-gating) Project opens and runs on Windows/Vulkan with the same bindings | H |

## Task breakdown (ordered)

### M1-T01 Bootstrap: Godot install, vendored addons, project skeleton

- Goal: a `project.godot` that imports cleanly headless with GDGS and GUT enabled.
- Files: `scripts/setup_godot.sh`, `scripts/vendor_addons.sh`, `addons/gdgs/**`, `addons/gut/**`,
  `project.godot`, `.editorconfig`, `src/autoload/settings.gd`, `tests/unit/test_smoke.gd`, `scripts/run_tests.sh`
  (initial), `docs/third-party.md` (update if versions differ).
- Notes:
  - `setup_godot.sh`: `curl -L` the zip from
    `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`,
    verify `sha256 = cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4`, unzip to `.tools/godot/`,
    symlink `.tools/godot/godot`. Idempotent; honour `GODOT_BIN` if set. GitHub release downloads work through
    the container proxy; `archive/refs/tags/*.zip` does not (see `docs/research-notes.md`).
  - `vendor_addons.sh`: `git clone --depth 1 --branch v9.7.1 https://github.com/bitwes/Gut` and
    `--branch v3.3.0 https://github.com/ReconWorldLab/godot-gaussian-splatting` into a temp dir; copy only
    `addons/gut` and `addons/gdgs` (keep `LICENSE*`); print the commit hashes; commit the result. Do not copy
    GDGS `samples/`, `tests/`, or `project.godot`.
  - `project.godot`: `config/features=PackedStringArray("4.7", "Forward Plus")`, rendering method
    `forward_plus`, `physics/3d/physics_engine="Jolt Physics"`, `default_gravity=0`, `default_linear_damp=0`,
    `default_angular_damp=0`, `physics/common/physics_interpolation=true`, window 1920×1080 with `stretch`
    off, `editor_plugins/enabled` = gdgs + gut, autoload `Settings`, `debug/gdscript/warnings/untyped_declaration=2`
    (error). Main scene is set in T12; until then CI runs scripts, not the project.
  - `settings.gd`: loads/saves `user://settings.cfg` with `invert_y=false`, `stick_deadzone=0.15`,
    `trigger_deadzone=0.05`, `assist_default=true`, `camera_default="chase"`, and a `[pads]` section mapping
    pad GUID -> `trigger_rest` (filled by the adapter in T06). Applies any lines from
    `user://gamecontrollerdb.txt` via `Input.add_joy_mapping(line, true)` in `_ready`.
  - `test_smoke.gd`: one GUT test asserting `true` so the runner path is exercised.
- Done when: `godot --headless --path . --import` prints no `SCRIPT ERROR`/`Parse Error`; GUT runs the smoke test
  and exits 0; `git status` shows only intended files (no `.godot/`).
- Verify: `scripts/setup_godot.sh && scripts/run_tests.sh`.

### M1-T02 Python toolchain: PLY writer and sky generator

- Goal: `assets/generated/environment/sky_splats.ply` + manifest from `tools/environment/build_sky.py`.
- Files: `tools/common/ply_writer.py`, `tools/common/frames.py` (Godot <-> 3DGS orientation), `tools/common/
  colors.py` (blackbody table), `tools/environment/build_sky.py`, `tools/tests/test_ply_writer.py`,
  `tools/tests/test_build_sky.py`, `scripts/gen_assets.sh` (initial), `tools/README.md` (10 lines: how to run).
- Notes: follow §9.1 item 3 for the PLY layout and §9.2 for content. Use `numpy.random.default_rng(seed)`.
  Write with `struct`/`numpy.tofile`, binary little endian, header `format binary_little_endian 1.0`. Manifest:
  `{"tool":"build_sky","version":1,"seed":42,"point_count":N,"aabb_min":[...],"aabb_max":[...],
  "frame":"godot","radius_m":20000}` where AABB is in the Godot frame (before the Rz(180°) write-out flip).
  Include `--panorama <png>` (Pillow, optional import) that rasterises the same catalogue to 4096×2048.
- Done when: tests pass; generated file parses back (write a tiny reader in tests) with the expected fields;
  same seed => identical SHA-256; stars within 10k-25k; nebula opacities in [0.02, 0.08].
- Verify: `python3 -m unittest discover -s tools/tests -v && scripts/gen_assets.sh && ls -la assets/generated/environment`.

### M1-T03 CI workflow

- Goal: every PR runs Python tests, asset generation, Godot import and GUT on `ubuntu-latest`.
- Files: `.github/workflows/ci.yml`, `scripts/run_tests.sh` (final shape), `reports/.gitkeep` not needed
  (directory created by the script).
- Notes: steps: checkout; `actions/setup-python@v5` (3.12) + `pip install numpy pillow`; `scripts/setup_godot.sh`
  (cache `.tools/` keyed on the version string with `actions/cache@v4`); `scripts/gen_assets.sh`;
  `scripts/run_tests.sh`; upload `reports/` as artifact `always()`. `run_tests.sh` must `set -euo pipefail`,
  tee the import log and `! grep -E "SCRIPT ERROR|Parse Error|Failed to load script" import.log`, then run GUT
  with `-gexit -gjunit_xml_file=reports/gut.xml` and propagate its exit code. Add `timeout-minutes: 20`.
- Done when: workflow is green on a PR and red when a deliberately failing test is pushed (do that on a scratch
  branch, then revert).
- Verify: GitHub Actions run link in the PR; locally `scripts/run_tests.sh`.

### M1-T04 Starfury generator

- Goal: ship splats, fallback meshes and hardpoints from a parametric spec.
- Files: `tools/common/geometry.py`, `tools/starfury/spec.py`, `tools/starfury/build_starfury.py`,
  `tools/starfury/lighting.py` (baked studio rig), `tools/tests/test_geometry.py`, `tools/tests/test_build_starfury.py`,
  `scripts/gen_assets.sh` (add ship), `docs/assets-starfury.md` (one page: the spec's part list, dimensions,
  hardpoint names and the JSON schema).
- Notes (§9.1): Dimensions as a guide: fuselage 7.5 m long × 1.6 m wide, cockpit canopy forward-top, four struts
  from the rear fuselage at ±45° in the X/Y plane to pods at radius 4.5 m, pods 3.2 m long × 1.1 m diameter with
  a rear main nozzle (1.0 m) and a forward retro nozzle (0.5 m), two gun barrels under the nose at x = ±0.6 m.
  Overall ~10 m long, ~10 m span. Palette: light grey hull, dark grey panels, dark blue-black canopy, muted
  orange/red stripe on pods (original, non-canon markings). Hardpoints JSON:
  ```json
  {"frame":"godot","length_m":10.1,"center_of_mass":[0,0,0.4],
   "cockpit_camera":{"position":[0,0.55,-2.1],"forward":[0,0,-1]},
   "chase_anchor":{"position":[0,2.5,9.0]},
   "muzzles":[{"position":[-0.6,-0.45,-4.2]},{"position":[0.6,-0.45,-4.2]}],
   "thrusters":[{"name":"pod_ur_main","position":[...],"direction":[0,0,1],"tags":["main"]}, ...],
   "collision":[{"type":"box","position":[...],"size":[...]},{"type":"capsule","position":[...],"radius":0.55,"height":3.2,"axis":"z"}, ...]}
  ```
  `direction` is the exhaust direction (thrust acts opposite). Tags drive visuals: `main`, `retro`, `rcs_px`,
  `rcs_nx`, `rcs_py`, `rcs_ny`, plus rotation tags (`pitch_up`, `pitch_down`, `yaw_left`, `yaw_right`,
  `roll_left`, `roll_right`) assigned from each nozzle's position × direction cross product sign.
  Re-centre all outputs on the splat centroid; write PLY in 3DGS orientation (flip). Target 100k-250k splats
  at spacing 0.06 m; expose `--spacing`.
- Done when: tests pass (centroid of written positions ≈ 0 within 1e-3 m after the flip; hardpoints schema;
  OBJ vertex count > 0 and face indices valid; determinism); `gen_assets.sh` writes all ship files.
- Verify: Python tests; optionally view `starfury.obj`/`starfury.ply` in any viewer on a workstation (not required).

### M1-T05 Godot asset import tests

- Goal: prove the generated PLYs import into GDGS resources headless.
- Files: `tests/integration/test_splat_import.gd`, `tests/fixtures/manifest_reader.gd` (RefCounted JSON helper),
  `tests/.gutconfig.json` (optional), `scripts/run_tests.sh` (ensure `--import` precedes GUT).
- Notes: `load("res://assets/generated/ship/starfury.ply")` returns the `GaussianResource` (GDGS registers an
  `EditorImportPlugin`; after `--import` the `.import` sidecar exists). Compare `point_count` and `aabb`
  (apply Rz(180°) to the manifest AABB: negate x and y and re-sort min/max) within 0.01 m. Do the same for the
  sky. Fail with a clear message if the asset is missing ("run scripts/gen_assets.sh").
- Done when: AC4 passes locally and in CI.
- Verify: `scripts/run_tests.sh`.

### M1-T06 Input layer

- Goal: `FlightCommand` from InputMap actions through a testable adapter; all actions declared.
- Files: `project.godot` (`[input]` section per §6.1 table, both pad and keyboard events), `src/input/flight_command.gd`,
  `src/input/input_source.gd`, `src/input/godot_input_source.gd`, `src/input/input_adapter.gd`,
  `tests/unit/test_input_adapter.gd`, `tests/fixtures/fake_input_source.gd`, `tests/unit/test_input_map.gd`.
- Notes: `InputSource` API: `get_axis(neg: StringName, pos: StringName) -> float`,
  `get_vector(nx, px, ny, py, deadzone) -> Vector2`, `get_strength(action) -> float`, `is_pressed(action) -> bool`,
  `get_raw_axis(device: int, axis: JoyAxis) -> float`, `connected_pads() -> Array[int]`.
  Edge detection lives in `InputAdapter` (previous-frame booleans), not in the source, so it is testable. Expo:
  `signf(x) * pow(absf(x), 1.5)` on pitch/yaw only. Invert-Y from `Settings`.
  Generic-pad handling per §6.1: trigger rest calibration (`trigger_rest` per pad GUID, sampled for 0.5 s while
  idle, default 0), normalisation `clamp((raw - rest) / (1 - rest), 0, 1)`, `Settings.stick_deadzone` radial,
  `user://gamecontrollerdb.txt` lines applied with `Input.add_joy_mapping(line, true)` at start-up. Nothing may
  reference rumble or other Xbox-specific features. `test_input_map.gd` asserts `InputMap.has_action()` for every
  action name, that each has at least one `InputEventJoypadMotion`/`InputEventJoypadButton`, and that axis
  indices are in 0..5 and button indices in 0..14 (standard SDL layout only).
- Done when: AC6 and AC15 pass.
- Verify: GUT unit suite.

### M1-T07 Flight model and assist (pure)

- Goal: `FlightModel.compute(cmd, v_body, w_body, spec, assist_on) -> FlightOutput {force_b, torque_b,
  thruster_levels}`.
- Files: `src/ship/ship_spec.gd` (+ `assets/ship_spec_default.tres`), `src/ship/flight_model.gd`,
  `src/ship/flight_assist.gd`, `src/ship/flight_output.gd`, `tests/unit/test_flight_model.gd`,
  `tests/unit/test_flight_assist.gd`.
- Notes: implement §5.2 exactly, including `axis_sign = Vector3(1, -1, -1)` and the asymmetric brake clamp on z.
  `thruster_levels` is a `Dictionary[StringName, float]` keyed by hardpoint tags: `main = max(0, -F_b.z /
  thrust_main)`, `retro = max(0, F_b.z / thrust_retro)`, `rcs_px = max(0, F_b.x / thrust_lateral)` etc., rotation
  tags from `tau_b / torque_max` sign and magnitude. Tests: each stick axis produces the sign in the §5.2 table;
  clamps hold at full deflection; assist with `w = w_target` gives zero torque; brake with `v_b = (0,0,-100)`
  yields `+thrust_retro` on z and never more; with `v_b = (0,0,+100)` yields `-thrust_main`.
- Done when: unit tests pass; no scene-tree imports in these files.
- Verify: GUT unit suite.

### M1-T08 Ship scene

- Goal: a flyable `RigidBody3D` ship with splat hull, fallback mesh, collision, hardpoints.
- Files: `src/ship/ship.tscn`, `src/ship/ship.gd`, `src/ship/hardpoints.gd`, `src/rendering/splat_status.gd`,
  `tests/integration/test_ship_physics.gd`, `tests/integration/test_ship_scene.gd`.
- Notes: body settings per §5.4; `mass`, `inertia`, `center_of_mass` from `ShipSpec` + hardpoints;
  `CollisionShape3D`s built in `_ready` from the JSON. `HullSplats` is a `GaussianSplatNode` (instantiate via
  `preload("res://addons/gdgs/runtime/nodes/gaussian_splat_node.gd").new()` or place it in the `.tscn`; keep its
  transform identity, see §9.1). `ship.gd` API: `set_command(cmd: FlightCommand)`, `assist_on: bool` (signal
  `assist_toggled(bool)`), `get_thruster_levels()`, `reset_to(xform)`, `forward() -> Vector3` (= `-basis.z`),
  `body_velocity()`. Apply forces in `_physics_process` from the last command. `SplatStatus.active_backend()
  -> StringName` reads GDGS's selector (`addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd`); if it
  returns none, set `HullMeshFallback.visible = true`. Integration tests drive the body through 120-300 physics
  ticks using the SceneTree physics frames (`await get_tree().physics_frame` in GUT's async tests) and assert AC5.
- Done when: AC5 passes headless; the scene instantiates with GDGS node present and fallback hidden.
- Verify: GUT integration suite (the damping guard test must fail if `default_linear_damp` is restored to 0.1;
  check once by hand).

### M1-T09 Space environment

- Goal: black sky with star/nebula splats following the camera, compositor wired for GDGS, key light.
- Files: `src/environment/space_environment.tscn`, `src/environment/space_environment.gd`,
  `src/environment/sky_follower.gd`, `assets/environment/environment_default.tres` (Environment resource),
  `assets/environment/environment_fallback.tres` (PanoramaSkyMaterial using `sky_panorama.png`),
  `tests/integration/test_environment.gd`.
- Notes: `WorldEnvironment.compositor = Compositor` with one `CompositorEffect` whose script is
  `res://addons/gdgs/runtime/compositor/gaussian_compositor_effect.gd` (defaults for `depth_bias`,
  `depth_test_min_alpha`; expose them as exports on the scene root for tuning). Environment: background colour
  black, ambient 0.02 grey, glow on (intensity 0.4, HDR threshold 1.0), tonemap filmic, no fog, no SSAO/SSR.
  `KeyStar`: `DirectionalLight3D`, energy 1.5, slightly warm, rotated to light the ship's front-left-top.
  `SkyFollower`: in `_process`, `sky.global_position = get_viewport().get_camera_3d().global_position` (also
  once in `_physics_process` to avoid a frame of lag after teleports). `space_environment.gd` exposes
  `use_fallback_sky(bool)` which swaps the Environment resource and hides `SkySplats`.
- Done when: scene instantiates headless; follower test moves a camera and asserts the sky origin tracks it;
  `use_fallback_sky(true)` swaps resources without errors (panorama file may be absent: guard with
  `ResourceLoader.exists`).
- Verify: GUT integration suite.

### M1-T10 Camera rig

- Goal: cockpit and chase cameras with toggle and smoothing.
- Files: `src/camera/camera_rig.gd`, `src/camera/chase_camera_math.gd`, `src/camera/camera_rig.tscn`,
  `tests/unit/test_chase_camera_math.gd`, `tests/integration/test_camera_rig.gd`.
- Notes: §8. `CameraRig.setup(ship: Ship)`; adds a `RemoteTransform3D` under the ship's `CockpitAnchor` pointing
  at `CockpitCamera`. `ChaseCameraMath.step(current: Transform3D, ship: Transform3D, dt: float, cfg) ->
  Transform3D` using half-life smoothing; unit test that two 1/120 s steps equal one 1/60 s step within 1e-4.
  Toggle sets `current` and `ship.set_cockpit_interior_visible(mode == COCKPIT)`. Near 0.05, far 50 000, FOV 75
  (cockpit) / 70 (chase).
- Done when: AC8 camera part passes; math tests pass.
- Verify: GUT.

### M1-T11 Thruster visuals and weapons

- Goal: visible thruster glow and firing pulse cannons.
- Files: `src/ship/thruster_visuals.gd`, `assets/materials/thruster_glow.tres`, `assets/materials/projectile.tres`,
  `assets/materials/muzzle_flash.tres`, `src/weapons/pulse_cannon.gd`, `src/weapons/projectile.tscn`,
  `src/weapons/projectile.gd`, `tests/integration/test_weapons.gd`, `tests/unit/test_pulse_cannon_gate.gd`.
- Notes: glow = `MeshInstance3D` with a `QuadMesh`/`CylinderMesh` per thruster hardpoint, `StandardMaterial3D`
  unshaded, additive blend, emission colour pale blue-white, `billboard = BILLBOARD_ENABLED` for quads; scale
  and alpha ∝ level with 80 ms smoothing. Cannon: `fire_rate_hz = 4`, alternates muzzles, `projectile_speed =
  400`, `lifetime_s = 4`; projectile is a `Node3D` moving kinematically in `_physics_process` (`position +=
  velocity * dt`), `velocity = ship.linear_velocity + ship.forward() * speed`, emissive capsule mesh ~0.1×1.5 m,
  added under `Main/Projectiles` (pass the container in `setup`). Muzzle flash: a quad scaled up for 50 ms. No
  hit detection. Fire-rate gate is a pure class (`PulseCannonGate`) so it is unit-tested with fake time.
- Done when: AC7 passes; glow nodes exist for every thruster hardpoint.
- Verify: GUT.

### M1-T12 Main scene, overlay, glue, human acceptance

- Goal: run the game; everything wired; human checklist executed.
- Files: `src/game/main.tscn`, `src/game/main.gd`, `src/game/debug_overlay.tscn`, `src/game/debug_overlay.gd`,
  `project.godot` (main scene), `tests/integration/test_main_scene.gd`, `docs/milestones/m1-first-flight.md`
  (tick the (H) boxes after the user's test, record GPU/driver and FPS).
- Notes: `main.gd` `_physics_process`: `cmd = adapter.sample(source, dt)`; handle `toggle_assist`,
  `toggle_camera`, `reset`, `pause` (`get_tree().paused`, ship and projectiles in the pausable group); pass
  `cmd` to the ship; `cannon.set_trigger(cmd.fire)`. Overlay (`Label`s, monospace): speed m/s, body velocity xyz,
  angular rate deg/s per axis, `ASSIST ON/OFF`, `CAM COCKPIT/CHASE`, `SPLATS <backend>`, FPS, renderer/GPU name
  (`RenderingServer.get_video_adapter_name()`), joypad name + GUID (`Input.get_joy_name/get_joy_guid`) and raw
  axes 0-5 (so a tester with a generic pad can diagnose trigger range and drift and author an SDL mapping line).
  Test: `--headless --quit-after 180` style run via GUT (instantiate `main.tscn`, await 120 physics frames,
  assert no errors and that pressing the toggle through `FakeInputSource` flips the camera).
- Done when: all (A) criteria pass in CI; the user runs the game with a controller and ticks AC9-AC14 (or files
  issues with screenshots). If AC9/AC10 fail because of splats, go to T13 before polishing anything else.
- Verify: CI + human session.

### M1-T13 (conditional) Splat fallback activation and triage

- Trigger: an (H) splat criterion fails on the user's machine.
- Goal: keep M1 shippable on meshes while the splat issue is isolated.
- Files: `src/rendering/splat_status.gd` (force-fallback flag via `--fallback-render` CLI arg and Settings),
  `docs/milestones/m1-first-flight.md` (record findings), issue(s) upstream to GDGS if it is a plugin bug.
- Notes: triage order: (1) overlay backend string; (2) force `gdgs/rendering/backend = Raster` and retest; (3)
  check orientation/centring against the fallback mesh (D-pad Down) and fix in the generator, not in the scene;
  (4) bisect by loading GDGS's own `samples/demo.tscn` in a scratch project to separate plugin vs asset problems.
- Done when: either splats pass AC9/AC10, or the fallback is default-on with a documented reason and a follow-up
  milestone "M1.5 splats" exists in `docs/roadmap.md`.

## Definition of done (M1)

- All tasks merged to `main`, CI green, `docs/third-party.md` current, no generated binaries committed.
- (H) criteria ticked below with the tester's GPU, driver, Godot build and FPS noted.

Human acceptance record (fill in):

```
Tester:                      Date:
OS / kernel / Mesa or driver:            GPU:
Gamepad name + GUID (from overlay):      Trigger rest value detected:
Splat backend shown:
AC9 [ ]  AC10 [ ]  AC11 [ ]  AC12 [ ] (FPS: ____)  AC13 [ ]  AC14 [ ]  AC16 (Windows, optional) [ ]
Notes:
```
