# Milestone 1: First Flight

> "A working 3D space combat ship (based on the Starfury design) in a starry background with a little bit of a
> nebula visible."

Read `docs/architecture.md` first; task notes below reference its sections (§). Tasks are ordered; each is one
PR-sized unit for an implementation agent. Do them in order unless a task says otherwise.

## Scope

In:
- Godot 4.7.2 project, Forward+, Jolt, vendored GDGS v3.3.0 and GUT v9.7.1, CI green on every PR. Linux only.
- `tools/procgen` framework with three generated assets: `starfury_aurora` (splats + fallback meshes +
  hardpoints), `nav_buoy`, `sky_default` (stars + nebula splats + panorama fallback).
- Player Starfury with Newtonian 6DOF flight on a generic XInput gamepad, using the user's layout (§6.1): analog
  left/right main pods on LT/RT, left/right retros on LB/RB, strafe/heave on the left stick, pitch/yaw on the right
  stick, roll on the D-pad. Pod forces act at the pods (differential thrust yaws the ship physically). Flight
  assist toggle (default on: rate command, uneven triggers turn the ship at a bounded rate), hold-to-brake, reset.
- First-person cockpit camera and third-person chase camera, toggle on Y.
- Two forward pulse cannons with two fire modes (alternating, linked), cycled with D-pad Down; projectiles inherit
  ship velocity; muzzle flash; thruster glow per pod and RCS nozzle.
- Targeting of five inert nav buoys: next target (D-pad Up), target ahead (R3), readout and bracket in the debug
  overlay.
- Long-term seams only (§14.9): `UniversePos` + `World` frame, environment-acceleration hook (zero), `SimClock`,
  command split, faction field, scenario JSON, procgen layout, reaction-mass flow (unlimited).
- Debug overlay and an always-on debug console on the ` key (§6.4): help, state inspection through whitelisted
  providers, typed settings (session or saved), FPS counter, god-mode flag (wired to damage in M2), scriptable from
  the command line for headless runs.
- Headless test suite (Python + GUT) and GitHub Actions CI.

Out (explicitly):
- Anything shootable: enemies, AI, damage, hit detection, shields, missiles or other secondary weapons, lead
  reticle, HUD beyond the debug overlay and target bracket.
- Audio, music, menus, front end, a settings menu (settings live in a config file and are edited through the
  console), save games, localisation.
- Console extras: operating the console from the gamepad, a remote/network console, any scripting beyond the
  command syntax, `timescale` above 1.
- Splat *training* (Brush/gsplat), GDGS relighting, collision generation from splats, LOD chains.
- True-scale world, gravity, automatic rebasing, moving frame, time warp, scaled space, planets, Babylon 5
  station, jumpgates, hyperspace, missions (all on the roadmap; M1 only adds the seams).
- Windows, macOS, consoles (not planned), multiplayer, VR, release packaging.
- Mouse flight; keyboard beyond the fallback bindings in the InputMap table.
- Asset polish passes (decals, markings, cockpit instruments).

## Acceptance criteria

`(A)` = an agent verifies headlessly in the container/CI. `(H)` = needs a human on the platform: **Linux,
discrete Vulkan GPU, generic XInput gamepad**, GDGS Compute backend. M1 is done when every (A) passes in CI and
every (H) is ticked by the user on `main`. Expected values in (A) tests are computed from `ShipSpec` and
hardpoints, never hard-coded.

| # | Criterion | Who |
|---|---|---|
| AC1 | `scripts/setup_godot.sh` installs Godot 4.7.2 into `.tools/godot/` with SHA-256 check; `scripts/run_tests.sh` exits 0 in a fresh container clone | A |
| AC2 | CI runs Python tests, asset generation, `--import` with zero `SCRIPT ERROR`/`Parse Error`, and GUT; fails on any test failure | A |
| AC3 | `python3 -m tools.procgen build all` writes `assets/generated/{starfury_aurora,nav_buoy,sky_default}/` with splat counts 100k-250k / 5k-15k / 10k-25k, fallback OBJs, `hardpoints.json` (ship, buoy) and `manifest.json` with a `lods` array; two runs with the same seed are byte-identical | A |
| AC4 | After `--import`, all three PLYs load as `GaussianResource` with `point_count` equal to the manifest and AABB matching the manifest (Godot frame) within 1 cm | A |
| AC5a | Straight line: RT = LT = 0.5 for 2 s from rest gives speed `0.5 · 4 · pod_main_thrust / mass · 2` ±1 %, `\|w\|` < 1e-3 rad/s, and speed unchanged ±0.1 % for 3 s after release | A |
| AC5b | Pod yaw, assist off: RT = 1 for 0.5 s from rest gives `w_y > 0` (nose left) with magnitude `Σ x_i · T / I_y · 0.5` ±2 %, pitch/roll rates < 1e-3 rad/s, rate persists ±0.5 % for 2 s; LT alone mirrors it; RB alone decelerates and gives `w_y < 0` | A |
| AC5c | Retros: from 50 m/s forward, RB + LB for 1 s reduce speed by `4 · pod_retro_thrust / mass` ±1 %, `\|w\|` < 1e-3 rad/s | A |
| AC5d | Assist on, pod steering: RT = 1 alone, sticks centred: within 1.5 s the yaw rate settles nose-left (`w_y > 0`) at `pod_yaw_gain · rate_max.y` ±5 % and stays there, pitch/roll rates < 1 °/s, `FlightOutput.trim` > 0 at steady state, and no nozzle level ever exceeds its trigger; after release the rotation stops (< 1 °/s) within 1.5 s; LT alone mirrors it; RT = 1 with LT = 0.95 (inside the 10 % deadzone) flies straight: `\|w_y\|` < 1 °/s and heading change < 2° over 2 s | A |
| AC5e | Assist on: a 60 °/s yaw spin stops (< 1 °/s) within 1.5 s. Assist off: the same spin does not decay (±0.5 % over 2 s) | A |
| AC5f | Brake: from body velocity (10, -5, -80) m/s with X held, in both assist modes, `\|v\|` < 0.5 m/s within 7 s and `\|w\|` < 1 °/s throughout | A |
| AC5g | Model matches engine: for five scripted demands, the one-tick angular velocity change measured in Jolt equals `FlightOutput.torque_b / inertia · dt` within 1 %; damping guard passes | A |
| AC6 | Input unit tests: radial deadzones, expo, invert-Y, roll ramp, edge detection, per-side trigger/bumper mapping into `FlightCommand`, combat/ui edges into their commands; every §6.1 action exists in `project.godot` with the listed bindings | A |
| AC7 | Weapons: projectile spawns at a muzzle hardpoint with velocity = ship velocity + 400 m/s forward and frees itself after 4 s; `ALTERNATING` fires 4 Hz alternating muzzles; `LINKED` fires 2 Hz both muzzles; `weapon_next` cycles and wraps and never raises the rate of fire | A |
| AC8 | Targeting: `target_next` cycles by range and wraps; `target_ahead` picks the smallest boresight angle in the forward hemisphere and leaves the selection unchanged if none; readout range ±1e-3 m and closing speed (+10 m/s when approaching a static buoy at 10 m/s); selection clears beyond sensor range; the five scenario buoys appear as candidates with faction `neutral` | A |
| AC9 | World frame: `UniversePos` round-trips at 1.5e11 m with < 1 mm error; `World.rebase(Vector3(5000, 0, 0))` mid-flight keeps every body's velocity, all relative positions within 1 mm, and the ship's universe position within 1 mm | A |
| AC10 | `main.tscn` runs 180 frames under `--headless` with no errors; camera toggle flips `current` and `CockpitInterior.visible`; `target_next` at start selects NAV ALPHA (the nearest) | A |
| AC11 | `TriggerCalibration` tests prove normalisation for rest = 0 and rest = -1; every pad binding uses only standard `JOY_AXIS_*` 0-5 / `JOY_BUTTON_*` 0-14 | A |
| AC12 | Ship renders as splats (not the fallback mesh) in both camera modes; hull orientation and position match the fallback mesh when toggled with F4 | H |
| AC13 | Star field and nebula visible as splats; no parallax when flying; no popping between sky and hull; cockpit frame correctly occludes hull splats | H |
| AC14 | On the tester's generic pad, per the §5.2 table: equal triggers fly straight; with assist off RT alone yaws left and LT alone yaws right; bumpers retro per side; with assist on one trigger turns the ship smoothly at ≈ 30 °/s (overlay shows POD YAW and POD TRIM), the turn stops on release, and both triggers squeezed fully fly straight; right stick pitches/yaws, D-pad rolls (taps give fine roll), left stick strafes/heaves; triggers reach full thrust and rest at zero; no stick drift; releasing the triggers does not slow the ship; brake stops drift in both modes; B and Y toggles work | H |
| AC15 | 60 fps at 1080p on the tester's Linux/Vulkan GPU (overlay FPS), no hitching when firing | H |
| AC16 | Thruster glow is per pod and per side: it shows differential thrust, retros and trim; RCS glow responds to strafe and rotation; projectiles and muzzle flash visible from both cameras; the two fire modes are visibly different | H |
| AC17 | D-pad Up cycles the buoys, R3 picks the buoy nearest the nose; bracket and readout (name, range, closing speed) are correct; buoys render as splats and visibly spin; the drifting buoy shows a non-zero closing speed | H |
| AC18 | Overlay shows splat backend `Compute` (`Raster` only with a recorded reason); fallback meshes/panorama appear automatically if neither backend initialised | H |
| AC19 | Console unit tests: tokenizer (quotes, `;`, `#`), typed args and their error messages, unknown command/key suggestions, `help`, history (100, persisted), Tab completion (commands, paths, setting keys, enum values), provider whitelist (`get ship.queue_free` is an unknown key), owner pruning when a registering node is freed, `god` toggles `debug.invulnerable` and it is never written by `save` | A |
| AC20 | Console input rules: no `InputMap` action binds `KEY_QUOTELEFT`; while the console is open key/mouse-bound actions read 0 and pad-bound actions still work; opening/closing with a key held fires no edge; `settings.console_pause_on_open` pauses the tree | A |
| AC21 | Headless automation: the `--console-exec` smoke runs in `run_tests.sh` print the expected `[console]` lines, `set settings.stick_deadzone 0.2` applies without touching `user://settings.cfg` until `save`, an invalid value exits 1 under `--console-strict`, and after T15 `state` lists every M1 provider (`settings`, `debug`, `time`, `input`, `ship`, `world`, `camera`, `weapons`, `targeting`, `render`) | A |
| AC22 | On the tester's keyboard: ` opens and closes the console (and never types a character), typing does not move the ship, the pad keeps flying with the console open, Esc closes it, Up/Down history and Tab completion work, `fps` shows the counter, `watch ship.speed` updates live, `set` + `save` survives a restart while `set` alone does not, engine errors appear in red | H |

## Task breakdown (ordered)

### M1-T01 Bootstrap: Godot install, vendored addons, project skeleton

- Goal: a `project.godot` that imports cleanly headless with GDGS and GUT enabled.
- Files: `scripts/setup_godot.sh`, `scripts/vendor_addons.sh`, `addons/gdgs/**`, `addons/gut/**`,
  `project.godot`, `.editorconfig`, `src/autoload/settings.gd`, `src/autoload/settings_schema.gd`,
  `src/autoload/sim_clock.gd`, `tests/unit/{test_smoke,test_settings_schema,test_sim_clock}.gd`,
  `scripts/run_tests.sh` (initial),
  `docs/third-party.md` (update if versions differ).
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
    off, `editor_plugins/enabled` = gdgs + gut, autoloads `Settings` and `SimClock` (`DebugConsole` follows in T07),
    `debug/gdscript/warnings/untyped_declaration=2` (error). Main scene is set in T15; until then CI runs
    scripts, not the project.
  - `settings.gd` is schema-driven from the start (architecture §6.4, M1 schema table): `SettingsSchema` holds
    type, default and range/choices per key and parses/validates values (bool accepts `true/false/on/off/1/0`).
    API: `get_value(key)`, `set_value(key, value) -> Error` (applies now, marks unsaved, emits `changed`),
    `reset(key)`, `is_unsaved(key)`, `save()`, `revert()`. Only `save()` writes `user://settings.cfg`. A `[pads]`
    section maps pad GUID -> `trigger_rest` (filled by the input layer in T06; data, not a schema key). Applies any
    lines from `user://gamecontrollerdb.txt` via `Input.add_joy_mapping(line, true)` in `_ready`. Tests: every
    schema key round-trips through save/revert; out-of-range and wrong-type values are rejected with a message;
    `set_value` alone never writes the file.
  - `sim_clock.gd`: `sim_time_s: float` (64-bit) advanced in `_physics_process` by `delta * warp`; `warp` is a
    constant 1.0 in M1 (setter asserts 1.0); `now() -> float`. All later gameplay timers use it or `delta`.
  - `test_smoke.gd`: one GUT test asserting `true` so the runner path is exercised.
- Done when: `godot --headless --path . --import` prints no `SCRIPT ERROR`/`Parse Error`; GUT runs the tests and
  exits 0; `git status` shows only intended files (no `.godot/`).
- Verify: `scripts/setup_godot.sh && scripts/run_tests.sh`.

### M1-T02 procgen framework and `sky_default`

- Goal: the `tools/procgen` package layout (§9) with its CLI, and the first asset.
- Files: `tools/__init__.py`, `tools/procgen/{__init__,__main__}.py`,
  `tools/procgen/core/{__init__,ply,frames,color,manifest,context}.py`, `tools/procgen/assets/__init__.py`
  (registry: `ASSETS: dict[str, Callable[[BuildContext], AssetOutputs]]`), `tools/procgen/assets/sky_default.py`,
  `tools/procgen/tests/{__init__,test_ply,test_frames,test_cli,test_sky_default}.py`, `scripts/gen_assets.sh`,
  `tools/procgen/README.md` (how to run, how to add an asset).
- Notes: follow §9 for the CLI, output contract and manifest, §9.1 item 3 for the PLY layout and §9.2 for
  content. `numpy.random.default_rng(seed)`; binary little endian, header `format binary_little_endian 1.0`.
  `build all` iterates the registry in sorted order. The panorama needs Pillow; skip it with a warning if Pillow is
  missing (the PLY must still build). Write a small PLY reader in `core/ply.py` for tests.
- Done when: tests pass; `python3 -m tools.procgen list` prints `sky_default`; the PLY parses back with the
  expected fields; same seed => identical SHA-256; 10k-25k splats; nebula opacities in [0.02, 0.08]; manifest has
  `lods[0]`.
- Verify: `python3 -m unittest discover -s tools/procgen/tests -t . -v && scripts/gen_assets.sh && ls -la assets/generated/sky_default`.

### M1-T03 CI workflow

- Goal: every PR runs Python tests, asset generation, Godot import and GUT on `ubuntu-latest`.
- Files: `.github/workflows/ci.yml`, `scripts/run_tests.sh` (final shape).
- Notes: steps: checkout; `actions/setup-python@v5` (3.12) + `pip install numpy pillow`; `scripts/setup_godot.sh`
  (cache `.tools/` keyed on the version string with `actions/cache@v4`); `scripts/gen_assets.sh`;
  `scripts/run_tests.sh`; upload `reports/` as artifact `always()`. `run_tests.sh` must `set -euo pipefail`,
  create `reports/`, tee the import log and `! grep -E "SCRIPT ERROR|Parse Error|Failed to load script"
  import.log`, then run GUT with `-gexit -gjunit_xml_file=reports/gut.xml` and propagate its exit code. Add
  `timeout-minutes: 20`.
- Done when: workflow is green on a PR and red when a deliberately failing test is pushed (do that on a scratch
  branch, then revert).
- Verify: GitHub Actions run link in the PR; locally `scripts/run_tests.sh`.

### M1-T04 `starfury_aurora` generator

- Goal: ship splats, fallback meshes and hardpoints from a parametric spec built on reusable parts.
- Files: `tools/procgen/core/{geometry,sampling,lighting,obj}.py`,
  `tools/procgen/parts/{__init__,hull,propulsion,structure,weapons}.py`, `tools/procgen/styles/{__init__,earthforce}.py`,
  `tools/procgen/assets/starfury_aurora.py` (+ registry entry), `tools/procgen/tests/{test_geometry,test_sampling,test_parts,test_starfury_aurora}.py`,
  `docs/assets-starfury.md` (one page: part list, dimensions, hardpoint names, the JSON schema below).
- Notes (§9.1): Dimensions as a guide: fuselage 7.5 m long × 1.6 m wide, cockpit canopy forward-top, four struts
  from the rear fuselage at ±45° in the X/Y plane to pods at radius 4.5 m, pods 3.2 m long × 1.1 m diameter with
  a rear main nozzle (1.0 m) and a forward retro nozzle (0.5 m), two gun barrels under the nose at x = ±0.6 m.
  Overall ~10 m long, ~10 m span. Palette from `styles/earthforce.py`: light grey hull, dark grey panels, dark
  blue-black canopy, muted orange/red pod stripe. Parts take parameters and a style and return tessellated
  geometry plus named anchors; the asset module only composes parts. Hardpoints JSON (Godot frame, metres,
  relative to the re-centred body origin):
  ```json
  {"frame": "godot", "length_m": 10.1, "center_of_mass": [0, 0, 0.8],
   "cockpit_camera": {"position": [0, 0.55, -2.6], "forward": [0, 0, -1]},
   "chase_anchor": {"position": [0, 2.5, 9.0]},
   "muzzles": [{"position": [-0.6, -0.45, -4.9]}, {"position": [0.6, -0.45, -4.9]}],
   "pods": [
     {"name": "ur", "side": "right", "center": [3.18, 3.18, 3.2],
      "main":  {"position": [3.18, 3.18, 4.8], "exhaust": [0, 0, 1]},
      "retro": {"position": [3.18, 3.18, 1.6], "exhaust": [0, 0, -1]}},
     {"name": "lr", "side": "right", "...": "..."},
     {"name": "ul", "side": "left",  "...": "..."},
     {"name": "ll", "side": "left",  "...": "..."}],
   "rcs": [{"name": "ur_px", "position": [3.75, 3.18, 3.2], "exhaust": [1, 0, 0], "tags": ["sway_left", "roll_left", "yaw_right"]}],
   "collision": [{"type": "box", "position": [0, 0, -1.0], "size": [1.6, 1.4, 7.5]},
                 {"type": "capsule", "position": [3.18, 3.18, 3.2], "radius": 0.55, "height": 3.2, "axis": "z"}]}
  ```
  `exhaust` is the exhaust direction (thrust acts opposite). RCS nozzles are cosmetic (glow only, decision D14): tags use
  pilot terms (`sway_left|sway_right|heave_up|heave_down|pitch_up|pitch_down|yaw_left|yaw_right|roll_left|roll_right`)
  derived from the thrust direction and the sign of `r × F`. Re-centre all outputs on the splat centroid; write
  the PLY in 3DGS orientation (flip). Target 100k-250k splats at spacing 0.06 m; expose `--spacing` through
  `BuildContext.options`.
- Done when: tests pass (centroid of written positions ≈ 0 within 1e-3 m after the flip; hardpoints schema incl.
  four pods, two per side, symmetric about x = 0 and y = 0 within 1e-6; OBJ vertex count > 0 and face indices
  valid; determinism; manifest `lods[0]`); `gen_assets.sh` writes all ship files.
- Verify: Python tests; optionally view `starfury_aurora.obj`/`.ply` in any viewer on a workstation (not required).

### M1-T05 Godot asset import tests

- Goal: prove the generated PLYs import into GDGS resources headless.
- Files: `tests/integration/test_splat_import.gd`, `tests/fixtures/manifest_reader.gd` (RefCounted JSON helper),
  `scripts/run_tests.sh` (ensure `--import` precedes GUT).
- Notes: `load("res://assets/generated/starfury_aurora/starfury_aurora.ply")` returns the `GaussianResource` (GDGS
  registers an import plugin; after `--import` the `.import` sidecar exists). Compare `point_count` and `aabb`
  (apply Rz(180°) to the manifest AABB: negate x and y and re-sort min/max) within 0.01 m. Same for
  `sky_default`. Iterate over whatever asset directories exist, so `nav_buoy` (T14) is covered automatically. Fail
  with a clear message if assets are missing ("run scripts/gen_assets.sh").
- Done when: AC4 passes for the assets that exist, locally and in CI.
- Verify: `scripts/run_tests.sh`.

### M1-T06 Input layer

- Goal: `PilotCommand` from InputMap actions through a testable adapter; all actions declared.
- Files: `project.godot` (`[input]` section per the §6.1 table, pad and keyboard events),
  `src/input/{flight_command,combat_command,ui_command,pilot_command,input_source,godot_input_source,trigger_calibration,input_adapter}.gd`,
  `tests/fixtures/fake_input_source.gd`, `tests/unit/{test_input_adapter,test_trigger_calibration,test_input_map}.gd`.
- Notes: `InputSource` API: `get_vector(nx, px, ny, py, deadzone) -> Vector2`, `get_trigger(action) -> float`,
  `is_pressed(action) -> bool`, `pad_info() -> Array[Dictionary]` (name, guid, raw axes 0-5; overlay only),
  `keyboard_mouse_enabled: bool` (default true; the console clears it in T07). `GodotInputSource` evaluates every
  action from its `InputMap` events by polling devices (`Input.get_joy_axis`, `is_joy_button_pressed`,
  `is_physical_key_pressed`, `is_mouse_button_pressed`) and never calls `Input.is_action_pressed`, so key and mouse
  bindings can be masked per device class (§6.1). `InputAdapter.resync_edges()` re-seeds previous-tick state.
  `GodotInputSource.get_trigger` reads the action's `InputEventJoypadMotion` events from `InputMap`, the raw axis
  per connected pad, normalises with `TriggerCalibration` (rest per GUID; calibration samples 0.5 s of idle input
  at start-up and on `joy_connection_changed`), counts bound keys as 1.0, returns the max. Edge detection lives in
  `InputAdapter` (previous-tick booleans) so it is testable. Expo `signf(x) * pow(absf(x), 1.5)` on pitch/yaw
  only; invert-Y from `Settings`; roll ramp per §6.1 (`rot.z` toward ±1 at `1 / roll_ramp_s` per second, snap
  to 0 on release, restart from 0 on reversal). Mapping: `main_right`/`main_left` -> `FlightCommand.main_*`,
  `retro_*` -> 0.0/1.0, combat actions -> `CombatCommand`, camera/reset/pause/debug -> `UiCommand`. Nothing may
  reference rumble or other Xbox-only features. `test_input_map.gd` asserts every action exists, each has at
  least one pad event (except `debug_toggle_fallback_mesh`, keyboard only), axis indices are in 0..5 and button
  indices in 0..14, the specific bindings from §6.1 (e.g. `retro_right` is button 10, `target_ahead` is 8), and
  that no action has a key event with physical keycode `KEY_QUOTELEFT` (the console key). Adapter tests: with
  `keyboard_mouse_enabled = false`, key-bound values read 0 while pad-bound values still pass through; toggling the
  mask with a key held fires no edge.
- Done when: AC6 and AC11 pass.
- Verify: GUT unit suite.

### M1-T07 Debug console

- Goal: the always-on ` console (architecture §6.4) with its core commands, ready for later tasks to register
  their own commands and state.
- Files: `src/autoload/debug_console.gd` (+ autoload entry after `SimClock` in `project.godot`),
  `src/console/{console_registry,console_tokenizer,console_command,console_arg,console_state_provider,console_vars,console_history,console_completer,console_format,console_result}.gd`,
  `src/console/console_ui.tscn|.gd`, `src/console/fps_counter.tscn|.gd`, `src/console/console_logger.gd`,
  `src/debug/debug_flags.gd`, `tests/fixtures/console_host.tscn` (empty Node3D for headless runs),
  `tests/unit/{test_console_tokenizer,test_console_registry,test_console_completer,test_console_history,test_debug_flags}.gd`,
  `tests/integration/test_debug_console.gd`, `scripts/run_tests.sh` (add the console smoke run).
- Notes: follow §6.4 exactly: availability, ` handling in `_input` (physical `KEY_QUOTELEFT`, consumed, Esc
  closes), registry API (`register_command`, `register_provider`, `unregister_owner`, `execute(line) ->
  Array[ConsoleResult]`, `complete(partial)`, `help(name)`), typed arguments with clear errors and "did you mean"
  suggestions, providers via `provider.key` paths only. Core commands: `help`, `clear`, `state`, `get`, `set`,
  `toggle`, `default`, `save`, `revert`, `watch`, `unwatch`, `fps`, `god`, `timescale` (clamped 0.05..1), `exec`,
  `wait`, `quit`. Providers registered here: `settings` (from `SettingsSchema`), `debug` (`DebugFlags`), `time`
  (`SimClock`, plus `Engine.time_scale`), `input` (via the main scene's `GodotInputSource` once it exists; a
  `DebugConsole.set_input_source(source, adapter)` setter; the adapter is what `resync_edges()` and the last-command
  keys need). While open: `captures_keyboard()` is true, the input source's
  `keyboard_mouse_enabled` is false and `InputAdapter.resync_edges()` runs on open and close; joypad events are
  swallowed by the UI only; `console_pause_on_open` pauses the tree. Output mirrored to stdout/stderr with the
  `[console]` prefix. Startup execution of `user://autoexec.cfg`, `--console-file`, `--console-exec`,
  `--console-strict` from `OS.get_cmdline_user_args()`, one physics frame after the current scene is ready.
  `ConsoleLogger` registers with `OS.add_logger()` and only appends to a `Mutex`-guarded queue (its methods are
  called off the main thread); the UI drains it each frame. `run_tests.sh` adds:
  `godot --headless --path . res://tests/fixtures/console_host.tscn -- --console-strict --console-exec="help; set settings.stick_deadzone 0.2; get settings.stick_deadzone; god on; get debug.invulnerable; quit 0"`
  and asserts exit code 0 and the expected `[console]` lines, plus a second run with `set settings.stick_deadzone
  0.9` that must exit 1 under `--console-strict`.
- Done when: AC19, AC20 and AC21 pass.
- Verify: GUT, `scripts/run_tests.sh`.

### M1-T08 Flight model and assist (pure)

- Goal: `FlightModel.new(spec, layout).compute(cmd, v_b, w_b, env_accel_b, assist_on, dt) -> FlightOutput`,
  exactly §5.2. `dt` drives the pod-yaw smoothing; the model owns one `FlightAssist` whose only state is the
  smoothed pod-yaw command (`reset()` on assist toggle and ship reset).
- Files: `src/ship/{ship_spec,thruster_layout,flight_model,flight_assist,flight_output}.gd`,
  `assets/ships/starfury_aurora.tres` (ShipSpec with §5.1 defaults, `asset_id = "starfury_aurora"`),
  `tests/fixtures/hardpoints_nominal.json` (static copy of the nominal pod geometry so unit tests do not depend on
  generated assets), `tests/unit/{test_thruster_layout,test_flight_model,test_flight_assist}.gd`.
- Notes: `ThrusterLayout.from_dict(hardpoints: Dictionary, center_of_mass: Vector3)` builds the 8 pod nozzles
  (group, position, exhaust, `r = p - com`) and the cosmetic RCS list. `FlightOutput`: `nozzle_forces:
  Array[Dictionary]` (`position`, `force`, group, level), `rcs_force_b`, `rcs_torque_b`, `force_b`, `torque_b`,
  `trim` (0..1), `pod_yaw_cmd` (-1..1, pilot terms), `main_levels`/`retro_levels` per pod after trim,
  `rcs_force_level`/`rcs_torque_level` (Vector3, -1..1), `mass_flow_kg_s`. Implement `AXIS_SIGN = Vector3(1, -1,
  -1)` once, in `FlightModel`. `ShipSpec` gains `pod_yaw_gain = 0.5`, `pod_yaw_deadzone = 0.10`,
  `pod_yaw_smoothing_s = 0.15` (§5.1). Unit tests, one per row of the §5.2 table (signs of `torque_b` and
  `force_b`, assist off and on), plus: `|tau_pods.x|, |tau_pods.z| < 1e-6` for random demands; pod-yaw command
  sign (LT or RB => yaw right, RT or LB => yaw left), deadzone (difference 0.05 => 0), rescaling (difference 1.0
  => 1.0), cap (`rot.y + pod_yaw_gain · d_s` clamped to ±1), smoothing frame-rate independent (two 1/120 s steps
  equal one 1/60 s step within 1e-6), zero while braking, cleared by `reset()`; trim `lam` equals the closed form
  for RT alone at steady rate (`w_b` = target); assist with `w = w_target` and equal triggers gives zero RCS
  torque; assist never raises any level above the pilot's; assist off ignores the pod-yaw command; brake levels are
  symmetric across sides; brake with forward velocity uses retros only and never exceeds `retro_total`; brake
  with `env_accel_b = (0, 0, -1)` and zero velocity produces `+mass` N on z (feed-forward); `mass_flow =
  Σ|F| / exhaust_velocity`.
- Done when: unit tests pass; no scene-tree access in these files.
- Verify: GUT unit suite.

### M1-T09 World frame and universe coordinates

- Goal: the large-world seam (§10, §14.1): every world object lives under a `World` node that can rebase.
- Files: `src/world/universe_pos.gd`, `src/world/world_frame.gd`, `tests/unit/test_universe_pos.gd`,
  `tests/integration/test_world_frame.gd`.
- Notes: `UniversePos` (RefCounted): `x, y, z: float` (64-bit), `system_id: StringName = &"local"`,
  `static from_array(a: Array) -> UniversePos`, `plus_local(v: Vector3) -> UniversePos`,
  `offset_to(other) -> Vector3` (documented as valid only for nearby positions), `distance_to(other) -> float`.
  `WorldFrame` (Node3D, the `World` node): `origin: UniversePos`, `origin_velocity: PackedFloat64Array` (zero in
  M1), `universe_to_local(u) -> Vector3` (`to_local` clashes with Node3D's native method), `to_universe(local: Vector3) -> UniversePos`, `spawn(node: Node3D, at:
  UniversePos, basis := Basis.IDENTITY)` (adds the child, joins group `world_shiftable`, places it),
  `rebase(offset: Vector3)` (moves every `world_shiftable` node by `-offset` via `global_position`, calls
  `reset_physics_interpolation()`, adds `offset` to `origin`, emits `rebased(offset)`),
  `environment_accel(local_pos: Vector3) -> Vector3` (returns `Vector3.ZERO`; the gravity/hyperspace hook),
  `auto_rebase_distance_m := 0.0` (0 = disabled; the check exists but is off in M1). Integration test: a
  RigidBody3D moving at 30 m/s plus a static node, call `rebase(Vector3(5000, 0, 0))`, await two physics frames,
  assert velocities unchanged and relative positions and universe positions within 1 mm.
- Console: `World` registers provider `world` and command `rebase <dx> <dy> <dz>` (§6.4).
- Done when: AC9 passes.
- Verify: GUT.

### M1-T10 Ship scene

- Goal: a flyable `RigidBody3D` ship with splat hull, fallback mesh, collision, hardpoints, pod forces at the pods.
- Files: `src/ship/ship.tscn`, `src/ship/ship.gd`, `src/ship/hardpoints.gd`, `src/rendering/splat_status.gd`,
  `tests/integration/{test_ship_physics,test_ship_scene}.gd`.
- Notes: body settings per §5.4; `mass`, `inertia` from `ShipSpec`, `center_of_mass_mode = CUSTOM` with the
  hardpoints CoM; `CollisionShape3D`s built in `_ready` from the JSON. `HullSplats` is a `GaussianSplatNode`
  (instantiate via `preload("res://addons/gdgs/runtime/nodes/gaussian_splat_node.gd").new()` or place it in the
  `.tscn`; keep its transform identity, see §9.1). `ship.gd` API: `setup(spec: ShipSpec, world: WorldFrame)`,
  `set_flight_command(cmd)`, `set_combat_command(cmd)` (stored for T13/T14), `assist_on: bool` (signal
  `assist_toggled(bool)`), `get_flight_output() -> FlightOutput`, `reset_to(xform)`, `forward() -> Vector3`
  (= `-basis.z`), `body_velocity()`. Toggling assist and `reset_to` call `FlightModel.reset_assist()`. Each
  `_physics_process(delta)`: compute the `FlightOutput` (passing `delta`), then
  `apply_force(B * F_i, B * p_i)` per pod nozzle, `apply_central_force(B * rcs_force_b)`,
  `apply_torque(B * rcs_torque_b)`, and `apply_central_force(mass * world.environment_accel(position))`.
  `SplatStatus.active_backend() -> StringName` reads GDGS's selector
  (`addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd`); if none, `HullMeshFallback.visible = true`.
  Integration tests drive the body with `await get_tree().physics_frame` in GUT async tests.
- Console: `Ship` registers provider `ship` and command `assist [on|off]`; `SplatStatus` registers provider
  `render` and command `fallback [on|off]` (§6.4).
- Done when: AC5a-AC5g pass headless; the scene instantiates with the GDGS node present and the fallback hidden.
- Verify: GUT integration suite. Check once by hand that the damping guard fails if `default_linear_damp` is put
  back to 0.1.

### M1-T11 Space environment

- Goal: black sky with star/nebula splats following the camera, compositor wired for GDGS, key light.
- Files: `src/environment/space_environment.tscn`, `src/environment/space_environment.gd`,
  `src/environment/sky_follower.gd`, `assets/environment/environment_default.tres` (Environment resource),
  `assets/environment/environment_fallback.tres` (PanoramaSkyMaterial using `sky_default_panorama.png`),
  `tests/integration/test_environment.gd`.
- Notes: `WorldEnvironment.compositor = Compositor` with one `CompositorEffect` whose script is
  `res://addons/gdgs/runtime/compositor/gaussian_compositor_effect.gd` (defaults for `depth_bias`,
  `depth_test_min_alpha`; expose them as exports on the scene root for tuning). Environment: background colour
  black, ambient 0.02 grey, glow on (intensity 0.4, HDR threshold 1.0), tonemap filmic, no fog, no SSAO/SSR.
  `KeyStar`: `DirectionalLight3D`, energy 1.5, slightly warm, rotated to light the ship's front-left-top.
  `SkyFollower`: in `_process`, `sky.global_position = get_viewport().get_camera_3d().global_position +
  centroid_offset` (from `sky_default/manifest.json`: GDGS re-centres every PLY on its mean, and the one-sided nebula
  puts the sky's mean ~4.6 km off the sphere centre) (also in
  `_physics_process` to avoid a frame of lag after teleports or rebases). The environment sits outside `World`.
  `space_environment.gd` exposes `use_fallback_sky(bool)` which swaps the Environment resource and hides
  `SkySplats`.
- Done when: scene instantiates headless; follower test moves a camera and asserts the sky origin tracks it;
  `use_fallback_sky(true)` swaps resources without errors (panorama may be absent: guard with
  `ResourceLoader.exists`).
- Verify: GUT integration suite.

### M1-T12 Camera rig

- Goal: cockpit and chase cameras with toggle and smoothing.
- Files: `src/camera/camera_rig.gd`, `src/camera/chase_camera_math.gd`, `src/camera/camera_rig.tscn`,
  `tests/unit/test_chase_camera_math.gd`, `tests/integration/test_camera_rig.gd`.
- Notes: §8. `enum Mode { COCKPIT, CHASE }` (more later); `CameraRig.setup(ship: Ship)`; adds a
  `RemoteTransform3D` under the ship's `CockpitAnchor` pointing at `CockpitCamera`. `ChaseCameraMath.step(current:
  Transform3D, ship: Transform3D, dt: float, cfg) -> Transform3D` with half-life smoothing; unit test that two
  1/120 s steps equal one 1/60 s step within 1e-4. `ChaseCamera` joins `world_shiftable`. Toggle sets `current`
  and `ship.set_cockpit_interior_visible(mode == COCKPIT)`. Near 0.05, far 50 000, FOV 75 (cockpit) / 70 (chase).
- Console: `CameraRig` registers provider `camera` (`mode` writable) and command `camera [cockpit|chase]`.
- Done when: camera part of AC10 passes; math tests pass.
- Verify: GUT.

### M1-T13 Thruster visuals and weapons

- Goal: visible per-pod thruster glow and pulse cannons with two fire modes.
- Files: `src/ship/thruster_visuals.gd`, `assets/materials/{thruster_glow,projectile,muzzle_flash}.tres`,
  `src/weapons/{pulse_cannon_gate,pulse_cannon,projectile}.gd`, `src/weapons/projectile.tscn`,
  `tests/unit/test_pulse_cannon_gate.gd`, `tests/integration/test_weapons.gd`.
- Notes: glow = `MeshInstance3D` (`QuadMesh` billboard or `CylinderMesh`) per pod main nozzle, pod retro nozzle
  and RCS nozzle, `StandardMaterial3D` unshaded, additive, pale blue-white emission; scale and alpha ∝ level with
  80 ms smoothing. Pod glows use `FlightOutput.main_levels`/`retro_levels` (post-trim, so trim and differential
  thrust are visible); RCS glows take the max of `rcs_levels` over their tags. `PulseCannonGate`: `enum Mode {
  ALTERNATING, LINKED }`, `cycle_mode()`, `update(now_s: float, trigger_held: bool) -> Array[int]` (muzzle
  indices to fire this tick; first shot immediately on press when the cooldown allows). ALTERNATING: 0.25 s
  interval, alternates 0/1. LINKED: 0.5 s interval, `[0, 1]`. The cooldown carries across mode switches. Time
  from `SimClock.now()`. `PulseCannon` reads `CombatCommand.fire` / `weapon_next` from the ship and spawns
  projectiles under `World/Projectiles` (passed in `setup`). Projectile: `Node3D` moving kinematically in
  `_physics_process` (`position += velocity * dt`), `velocity = ship.linear_velocity + ship.forward() * 400`,
  lifetime 4 s, emissive capsule ~0.1×1.5 m, joins `world_shiftable`. Muzzle flash: a quad scaled up for 50 ms.
  No hit detection.
- Console: `PulseCannon` registers provider `weapons` (`mode` writable: `alternating`, `linked`).
- Done when: AC7 passes; glow nodes exist for every pod nozzle and RCS hardpoint.
- Verify: GUT.

### M1-T14 Nav buoys and targeting

- Goal: five inert, spinning splat buoys spawned from the scenario file, and a working targeting system.
- Files: `tools/procgen/assets/nav_buoy.py` (+ registry entry, `tools/procgen/tests/test_nav_buoy.py`),
  `src/props/nav_buoy.tscn`, `src/props/nav_buoy.gd`,
  `src/targeting/{target_info,target_readout,targeting_system,targetable,targeting_controller}.gd`,
  `src/game/scenario_loader.gd`, `data/scenarios/free_flight.json`,
  `tests/unit/{test_targeting_system,test_scenario_loader}.gd`, `tests/integration/test_targeting_controller.gd`.
- Notes: §6.3 and §9.3. `nav_buoy.py` reuses `parts/` (cylinder hull, panel wings, mast) and `styles/earthforce.py`.
  `NavBuoy`: `BuoySplats` (GaussianSplatNode sharing one loaded resource), `BuoyMeshFallback`, `Beacon`
  (emissive mesh at the `beacon` hardpoint, blinks 1 Hz from `SimClock`), spin 10 °/s, optional `velocity`
  (kinematic drift in `_physics_process`), a `Targetable` child (`display_name`, `faction = &"neutral"`,
  `get_target_velocity()`), group `world_shiftable`, no collision. Scenario file:
  ```json
  {"scenario_id": "free_flight", "system_id": "local",
   "player": {"position": [0, 0, 0], "forward": [0, 0, -1]},
   "props": [
     {"type": "nav_buoy", "name": "NAV ALPHA",   "position": [0, 0, -500]},
     {"type": "nav_buoy", "name": "NAV BRAVO",   "position": [300, 50, -1200]},
     {"type": "nav_buoy", "name": "NAV CHARLIE", "position": [-800, -200, -2000]},
     {"type": "nav_buoy", "name": "NAV DELTA",   "position": [1500, 400, 800], "velocity": [0, 0, -3]},
     {"type": "nav_buoy", "name": "NAV ECHO",    "position": [-200, 900, -4800]}]}
  ```
  Positions are universe coordinates (64-bit when parsed); `ScenarioLoader.load(path) -> Dictionary` returns typed
  spawn entries with `UniversePos`, and spawning goes through `World.spawn()`. `TargetingController` (under the
  ship) builds `TargetInfo`s from group `targetable` each physics tick, applies `target_next` / `target_ahead`
  edges, exposes `selected_readout() -> TargetReadout`, emits `target_changed`.
- Console: `TargetingController` registers provider `targeting` (`selected` writable by display name or `none`).
- Done when: AC8 passes; `nav_buoy` passes AC3 and AC4 (T05's test picks it up).
- Verify: Python tests, GUT.

### M1-T15 Main scene, overlay, glue, human acceptance

- Goal: run the game; everything wired; human checklist executed.
- Files: `src/game/main.tscn`, `src/game/main.gd`, `src/game/debug_overlay.tscn`, `src/game/debug_overlay.gd`,
  `project.godot` (main scene), `tests/integration/test_main_scene.gd`, `docs/milestones/m1-first-flight.md`
  (tick the (H) boxes after the user's test).
- Notes: tree per §3. `main.gd` `_ready`: load `free_flight.json`, spawn the player and buoys through `World`.
  `_physics_process`: `pc = adapter.sample(source, dt)`; `ship.set_flight_command(pc.flight)`;
  `ship.set_combat_command(pc.combat)`; handle `pc.ui` edges (camera, reset, `pause` via `get_tree().paused`
  with ship, buoys and projectiles pausable, overlay toggle = `toggle settings.show_overlay`, F4 fallback mesh
  toggle). Console: `main.gd` registers commands `respawn` and `pause [on|off]` and hands its `GodotInputSource`
  and `InputAdapter` to `DebugConsole.set_input_source(source, adapter)` (held weakly: `main.gd` keeps them);
  `run_tests.sh` adds a smoke run of the real main scene:
  `godot --headless --path . -- --console-strict --console-exec="wait 30; state; state ship; get render.splat_backend; quit"`
  asserting all ten providers are listed. Overlay (`Label`s,
  monospace): speed m/s, body velocity xyz, angular rate °/s per axis, `ASSIST ON/OFF`, `POD YAW ±nn °/s`
  (`pod_yaw_cmd × rate_max.y`, assist on only), `POD TRIM nn %`,
  `CAM COCKPIT/CHASE`, weapon mode, target line (`TGT NAV BRAVO  1243 m  +12.4 m/s`), universe position (64-bit),
  `TIMESCALE x` when not 1, `SPLATS <backend>`, FPS, GPU name (`RenderingServer.get_video_adapter_name()`), pad name + GUID and raw axes 0-5.
  Target bracket: a `Control` drawing a 24 px square at `camera.unproject_position(target)` unless
  `camera.is_position_behind(target)` (then show `TGT BEHIND`). Test: instantiate `main.tscn`, await 180 physics
  frames, assert no errors; through `FakeInputSource` flip the camera and press `target_next` (selects NAV ALPHA).
- Done when: all (A) criteria pass in CI; the user runs the game with the pad and ticks AC12-AC18 and AC22 (or files issues
  with screenshots). If AC12/AC13 fail because of splats, go to T16 before polishing anything else.
- Verify: CI + human session.

### M1-T16 (conditional) Splat fallback activation and triage

- Trigger: an (H) splat criterion fails on the user's machine.
- Goal: keep M1 shippable on meshes while the splat issue is isolated.
- Files: `src/rendering/splat_status.gd` (force-fallback flag via `--fallback-render` CLI arg and Settings),
  `docs/milestones/m1-first-flight.md` (record findings), issue(s) upstream to GDGS if it is a plugin bug.
- Notes: triage order: (1) overlay backend string; (2) force `gdgs/rendering/backend = Raster` and retest; (3)
  check orientation/centring against the fallback mesh (F4) and fix in the generator, not in the scene; (4)
  bisect by loading GDGS's own `samples/demo.tscn` in a scratch project to separate plugin vs asset problems.
- Done when: either splats pass AC12/AC13, or the fallback is default-on with a documented reason and a follow-up
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
AC12 [ ]  AC13 [ ]  AC14 [ ]  AC15 [ ] (FPS: ____)  AC16 [ ]  AC17 [ ]  AC18 [ ]  AC22 [ ]
Notes:
```
