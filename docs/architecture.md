# Architecture

Design for `space-combat-sim`: a Newtonian 3D space-fighter sim in Godot 4, every hull a procedurally textured polygon
mesh. This document is the contract between planning and implementation. Milestone scope and tasks live in
`docs/milestones/`; verified facts (versions, URLs, container quirks) live in `docs/research-notes.md`. §1-§13
describe what M1 builds and §15 what M2 adds; §14 is the long-term design that neither may block.

## 1. Tech stack (pinned)

| Layer | Choice | Version | Licence |
|---|---|---|---|
| Target platform | **Linux x86_64 + Vulkan, only.** Windows, macOS and consoles are not planned (deferred indefinitely) | - | - |
| Engine | Godot (official single-precision build, no .NET) | **4.7.2-stable** | MIT |
| Renderer | Forward+ (Vulkan) | - | - |
| Controller | Generic XInput-class gamepad through Godot/SDL3's standard `JOY_*` layout; no Xbox-only features | - | - |
| Physics | Jolt (built in, set explicitly) | bundled | MIT |
| World coordinates | Floating-origin `WorldFrame` + 64-bit script-side `UniversePos` (§14.1) | - | - |
| Language | GDScript, statically typed | - | - |
| Tests (engine) | GUT `addons/gut` | **v9.7.1** | MIT |
| Asset generators | `tools/procgen`, Python + NumPy (PNGs written by its own `core/image.py`) | 3.11+ / 2.x | PSF / BSD |
| CI | GitHub Actions, `ubuntu-latest`, Godot downloaded from GitHub releases | - | - |

Version bumps are deliberate PRs that update this table, `scripts/setup_godot.sh`, `.github/workflows/ci.yml`
and `docs/third-party.md` together.

## 2. Key decisions

M2 decisions (D20-D29) are in §15.1.

| # | Decision | Rationale (short) |
|---|---|---|
| D1 | Godot 4.7.2 (latest stable at planning time) | User decision: Godot 4. 4.7.x has Jolt default and SDL3 gamepads. |
| D2 | Every hull is a **textured polygon mesh** drawn by Godot's Forward+ renderer (M4-T31, Q29; the M1 to M3 hulls were a point-cloud renderer's, see the M4 milestone) | On the GPU the textured meshes cost 2 to 3 times less wherever hulls are on screen and need no sort buffers; a mesh writes its own depth and follows the body's interpolated pose like any `MeshInstance3D`, and the importer builds its levels of detail. |
| D3 | **No trained or scanned assets.** Every mesh and texture map is produced by code from procedurally authored surfaces (the UV atlas, the bakes and the paint, §9) | Deterministic, CPU-only, reproducible in CI and in the GPU-less container. |
| D4 | RigidBody3D + Jolt. Pod nozzle forces are applied **at their hardpoint positions** (`apply_force`); RCS as central force + torque; no custom integrator | Correct rigid-body dynamics (inertia, angular momentum); differential pod thrust yaws the ship through real r × F computed by the engine; free collision later. Verified headless. Custom integrator only if Jolt limits ever block us (§5.6). |
| D5 | Flight logic in pure `RefCounted` classes, nodes are thin adapters | Unit-testable without a scene tree, display or controller. |
| D6 | Flight assist in M1. **ON (default)**: rate-command fly-by-wire; the trigger/bumper difference is a smoothed **yaw command** added to the right stick's (the D-pad's before M3-T15), so pod steering works in both modes; pod torque helps the turn and is trimmed when RCS cannot hold the commanded rate; no pod ever exceeds its trigger. **OFF**: raw pods + raw RCS torque (tank-steer). **Brake** (hold) is an all stop (velocity and rotation) in both, and turns the nose onto the selected target | User decision: pod steering is the Starfury identity in both modes; assist makes it bounded and stop-on-release; one closed-form rule (§5.5). |
| D7 | User-chosen pad layout (§6.1): triggers = left/right main pods, bumpers = left/right retros, left stick = strafe, right stick = pitch / yaw by direction, roll on its diagonals; B = target cycling (tap next, hold previous); D-pad Up = flight assist, Down = weapon; D-pad Left / Right free (M3-T15). `InputMap` actions only, SDL3 standard layout, keyboard as extra events | Every DOF and combat function reachable without modifiers or stick clicks (generic pads may lack them); per-side pod control is the Starfury identity; rebindable, testable, works on a generic pad. |
| D8 | Meshes for everything drawn: textured hulls, buoys and chunks, the cockpit interior, projectiles, flashes, thruster plumes, beacons; the sky as star points and a nebula panorama; primitives for collision | One renderer, one lighting model (the scene's 8 lights and an ambient term, §7.3); animated and emissive-dynamic things are their own transparent meshes (§7). |
| D9 | Generated assets are **not committed**; generators are. No Git LFS | Everything binary is reproducible from `tools/procgen` in seconds; LFS adds quotas and fork friction. |
| D10 | GUT over gdUnit4 | Simpler headless CLI (`-gexit`, exit code 1 on failure), no xvfb caveats, GDScript-first, tracks Godot 4.7. |
| D11 | 1 unit = 1 metre, SI everywhere, Godot axes (+X right, +Y up, **-Z forward**) | Avoids conversion bugs; Godot's `Basis.z` is backward, so forward is `-basis.z`. |
| D12 | Vendor addons into `addons/` (GUT and the lens flare, `docs/third-party.md`) | Offline-reproducible builds; standard Godot practice; licences travel with the code. |
| D13 | Linux x86_64 + Vulkan is the only target; Forward+ on the maintainer's GPU is the acceptance renderer | The maintainer builds this for their own Linux gaming desktop. No per-OS code is written, so Godot keeps other doors open, but nothing else is tested or promised. |
| D14 | Pod thrust = 8 discrete nozzle forces (4 main, 4 retro) at hardpoint positions; RCS = ideal per-axis force/torque actuator with limits | The asymmetry that matters is in the big pod nozzles; modelling every RCS jet adds allocation maths with no gameplay gain. |
| D15 | M1 has targeting and weapon modes but nothing shootable: `TargetingSystem` over inert **nav buoys**; `weapon_next` cycles pulse-cannon fire modes | Smallest behaviour that makes every bound button do something verifiable; spinning buoys exercise several independently moving bodies before enemies need them. |
| D16 | Stay on the official single-precision engine. Large worlds use a floating-origin, free-falling `WorldFrame` plus 64-bit universe coordinates in script | No official double builds exist; the GPU works in float32 anyway; Jolt's 500 m/s cap needs a moving frame regardless (§14.1). |
| D17 | Procedural assets only, via a reusable generator framework (`tools/procgen`): no hand modelling, no AI 3D generators | User decision. Reproducible, reviewable, licence-clean, LOD-able by construction (§14.8). |
| D18 | Gravity (and any later field: hyperspace currents) is an explicit environmental force; project gravity stays 0 | Keeps Jolt a local rigid-body solver; M1 already has the hook (`WorldFrame.environment_accel`), returning zero. |
| D19 | Always-on debug console on the physical ` key (§6.4): a pure command/state registry that subsystems extend by registering, whitelisted state providers (no reflection), keyboard masked while open, gamepad and sim time keep running, output mirrored to stdout, scriptable from the command line | Personal single-user project, so usefulness wins over gating; the registry keeps it testable and lets every later milestone add commands without touching the console; stdout and `--console-exec` let headless agents drive a live build. |

## 3. Project layout

```
project.godot                 Forward+, Jolt, zero default damping, physics interpolation on, InputMap actions
addons/gut/                   vendored GUT v9.7.1 (MIT)
data/scenarios/free_flight.json  M1 scenario: player start + nav buoys in universe coordinates
src/
  autoload/settings.gd        Settings: schema-driven typed values (§6.4), session vs saved, pad calibration
  autoload/settings_schema.gd RefCounted, pure: key -> type, default, range/choices; parse + validate
  autoload/sim_clock.gd       SimClock: 64-bit sim time, warp (fixed 1.0 in M1); the only gameplay clock
  autoload/debug_console.gd   DebugConsole: owns registry, ConsoleUI, FpsCounter, ConsoleLogger, DebugFlags (§6.4)
  console/console_registry.gd RefCounted, pure: commands + state providers, parse/validate/execute, help
  console/console_tokenizer.gd, console_command.gd, console_arg.gd, console_state_provider.gd, console_vars.gd,
  console/console_history.gd, console_completer.gd, console_format.gd, console_result.gd   (all pure)
  console/console_ui.tscn|.gd CanvasLayer 100: log + prompt, keyboard only, history, Tab completion
  console/fps_counter.tscn|.gd CanvasLayer 99: FPS + frame ms + watched values, top-right
  console/console_logger.gd   Logger subclass (OS.add_logger): engine errors/warnings into the log, mutex-queued
  debug/debug_flags.gd        RefCounted: session-only cheats; M1: invulnerable
  world/universe_pos.gd       RefCounted: 64-bit position (x, y, z floats) in metres, + system_id
  world/world_frame.gd        Node3D "World": origin UniversePos + origin velocity, universe_to_local/to_universe,
                              rebase(offset), environment_accel(local_pos) (returns ZERO in M1)
  game/main.tscn|.gd          main scene: loads scenario, wires environment, ship, camera rig, overlay
  game/scenario_loader.gd     RefCounted: free_flight.json -> spawn list (UniversePos per entry)
  game/debug_overlay.tscn|.gd CanvasLayer (visible = settings.show_overlay): flight state, assist/camera, POD YAW +
                              POD TRIM, weapon mode, timescale (when ≠ 1), target readout
                              + target bracket, renderer, FPS, GPU, pad name/GUID/raw axes, universe position
  ship/ship.tscn|.gd          RigidBody3D "PlayerShip" adapter: consumes FlightCommand + CombatCommand
  ship/ship_spec.gd           Resource: mass, inertia, pod/RCS limits, rates, gains, asset_id, exhaust velocity
  ship/thruster_layout.gd     RefCounted: pod main/retro nozzles + RCS nozzles relative to CoM, from hardpoints
  ship/flight_model.gd        RefCounted, pure: FlightCommand + state -> FlightOutput (§5.2)
  ship/flight_assist.gd       RefCounted, pure (stateful, deterministic): pod-yaw command smoothing, rate
                              controller, pod trim, brake allocation
  ship/flight_output.gd       RefCounted: per-nozzle forces, RCS force/torque, totals, trim, levels, mass flow
  ship/hardpoints.gd          RefCounted: loads assets/generated/starfury_aurora/hardpoints.json
  ship/thruster_visuals.gd    exhaust plumes (cone + core disc along each nozzle's exhaust axis) from FlightOutput levels
  rendering/mesh_assets.gd    RefCounted: a hull's textured mesh from its manifest, one material per surface (§7.1, §9)
  rendering/light_rig.gd      Node: the scene's 8 lights, the key star and 7 omni slots filled from emitters (§7.3)
  rendering/light_picker.gd   RefCounted, pure: which emitters fill the 7 slots each frame (§7.3)
  rendering/light_emitter.gd  RefCounted: something that gives off light, as the picker sees it (§7.3)
  weapons/pulse_cannon_gate.gd RefCounted, pure: fire modes, rate gate, muzzle selection (fake-time testable)
  weapons/pulse_cannon.gd     node adapter: trigger state, spawns projectiles at muzzle hardpoints
  weapons/projectile.tscn|.gd kinematic projectile (inherits ship velocity), lifetime, emissive mesh
  targeting/target_info.gd    RefCounted: id, display_name, faction, position, velocity
  targeting/target_readout.gd RefCounted: range, closing speed, angle off boresight
  targeting/targeting_system.gd RefCounted, pure: next / ahead selection, readout
  targeting/targetable.gd     Node3D component: joins group "targetable", display_name, faction, velocity
  targeting/targeting_controller.gd  Node under the ship: gathers targetables, applies CombatCommand edges
  props/nav_buoy.tscn|.gd     inert target marker: textured body, beacon mesh, slow spin, optional drift
  camera/camera_rig.gd        owns CockpitCamera + ChaseCamera; mode enum (COCKPIT, CHASE; later CINEMATIC)
  camera/chase_camera_math.gd RefCounted, pure: rigid chase pose, optional orientation lag (unit-tested)
  camera/chase_camera_config.gd Resource: chase offset, look-ahead and the optional smoothing time constant
  input/flight_command.gd     RefCounted: per-side pod demand, strafe, rotation, brake, assist toggle, face dir
  input/combat_command.gd     RefCounted: fire (held), weapon_next / target_next / target_ahead (edges)
  input/ui_command.gd         RefCounted: camera, reset, pause, debug toggles (edges)
  input/pilot_command.gd      RefCounted: {flight, combat, ui}; what InputAdapter.sample() returns
  input/input_source.gd       abstract: get_vector, get_trigger, is_pressed, pad info
  input/godot_input_source.gd InputSource over Input + InputMap, applies per-pad trigger calibration
  input/trigger_calibration.gd RefCounted, pure: trigger rest detection and normalisation
  input/input_adapter.gd      InputSource -> PilotCommand (deadzone, expo, roll ramp, edge detection)
  environment/space_environment.tscn|.gd  WorldEnvironment (+Compositor: motion blur, lens flare), the light rig, the sky
  environment/star_field.gd   the stars as camera-facing points, one multimesh (§17.19)
  environment/sky_follower.gd pins the star field to the active camera position each frame
  rendering/render_status.gd  the `render` provider: renderer, FPS, frame time, draw calls, triangles, VRAM (§6.4)
assets/
  generated/                  gitignored; one directory per asset id (§9): starfury_aurora/, nav_buoy/, sky_default/
  ships/starfury_aurora.tres  ShipSpec for the player ship (asset_id = "starfury_aurora")
  materials/*.tres            emissive glow, projectile, beacon, cockpit materials (hand-made, tiny)
tools/
  __init__.py
  procgen/                    procedural asset framework (§9, §14.8): core/, parts/, styles/, assets/, tests/
tests/                        GUT suites: unit/ (pure classes), integration/ (headless scene tests), fixtures/
scripts/
  setup_godot.sh              download + sha256-verify Godot 4.7.2 into .tools/godot/
  vendor_addons.sh            git clone pinned tags, copy addons/<name>, keep licences (run once; result committed)
  gen_assets.sh               python3 -m tools.procgen build all
  run_tests.sh                the four test tiers (--quick, --standard, --balance, --full); lib_tests.sh holds its helpers
.github/workflows/ci.yml
docs/                         this file, milestones/, roadmap.md, research-notes.md, third-party.md
```

Autoloads, in this order: `Settings`, `SimClock`, `DebugConsole`. No global event bus; nodes communicate downward
by calls and upward by signals. `DebugConsole` adds its own `ConsoleUI` and `FpsCounter` canvas layers to the root,
so it works in every scene (the future front end included) and is not part of `main.tscn`.

### Main scene tree (`src/game/main.tscn`)

```
Main (Node3D)                              main.gd
├── SpaceEnvironment (space_environment.tscn)   outside World: camera-relative, never rebased
│   ├── WorldEnvironment                   Environment (the nebula panorama, no fog, tonemap filmic, glow on) + Compositor[blur, flare]
│   ├── LightRig (Node3D)                  the scene's only lights (§7.3)
│   │   ├── KeyStar (DirectionalLight3D)   slot 0: the star's light
│   │   └── Slot1..Slot7 (OmniLight3D)     filled from emitters by LightPicker each frame; energy 0 when unused
│   └── StarField (MultiMeshInstance3D)    top_level = true; sky_follower.gd keeps origin == active camera origin
├── World (Node3D, world_frame.gd)         every world object lives under here (group "world_shiftable"); rebases at 5 km (M3-T14)
│   ├── PlayerShip (ship.tscn, RigidBody3D)    ship.gd
│   │   ├── CollisionShape3D x N           from hardpoints "collision" primitives (boxes/capsules)
│   │   ├── Hull (MeshInstance3D)          the textured mesh (starfury_aurora.glb, shared); the OBJ while the cockpit is shown
│   │   ├── CockpitInterior (MeshInstance3D)   cockpit_interior.obj; visible only in first person
│   │   ├── Thrusters (Node3D)             exhaust plume per pod main/retro nozzle and per RCS nozzle
│   │   ├── Guns (Node3D)                  Marker3D per muzzle + pulse_cannon.gd
│   │   ├── Targeting (Node)               targeting_controller.gd
│   │   └── CockpitAnchor (Marker3D)       from hardpoints "cockpit_camera"
│   ├── CameraRig (Node3D)                 camera_rig.gd
│   │   ├── CockpitCamera (Camera3D)       follows CockpitAnchor via RemoteTransform3D on the anchor
│   │   └── ChaseCamera (Camera3D)         top_level; set from the ship's interpolated pose in _process; in group "world_shiftable"
│   ├── Targets (Node3D)                   NavBuoy instances spawned from the scenario
│   └── Projectiles (Node3D)               container for live projectiles
└── DebugOverlay (CanvasLayer)
```

## 4. Module boundaries

```
InputSource ─> InputAdapter ─PilotCommand─┬─flight─> Ship ─> FlightModel(+FlightAssist) [pure]
                                          │           ├─ pod nozzle forces: apply_force at hardpoints ─┐
                                          │           ├─ RCS force + torque: central ──────────────────┼─> RigidBody3D / Jolt
                                          │           ├─ environment accel: World.environment_accel ───┘   (ZERO in M1)
                                          │           └─ FlightOutput levels ─> ThrusterVisuals
                                          ├─combat─> Ship ─> PulseCannon(+PulseCannonGate) ─> Projectile(s)
                                          │               └> TargetingController(+TargetingSystem) <─ group "targetable"
                                          └─ui─────> Main: camera toggle, reset, pause, debug toggles
Ship pose / velocity ─> CameraRig ─> active Camera3D ─> SkyFollower
Settings ─> InputAdapter, GodotInputSource, CameraRig, Ship        SimClock ─> every gameplay timer
Every subsystem ─register commands + state providers─> DebugConsole.registry <─ ConsoleUI / --console-exec
DebugConsole.captures_keyboard() ─> GodotInputSource (masks keyboard/mouse bindings while the console is open)
```

Rules:
- `FlightModel`, `FlightAssist`, `InputAdapter`, `TriggerCalibration`, `ChaseCameraMath`, `PulseCannonGate`,
  `TargetingSystem`, `UniversePos` are `RefCounted`, import nothing from the scene tree, and are unit-tested.
  Nodes only marshal data in and out.
- The ship never reads `Input`. It consumes a `FlightCommand` and a `CombatCommand` handed to it by `main.gd`
  each physics tick. An AI pilot (§14.7) produces the same two commands; `UiCommand` is player-only.
- World objects are spawned through `World` (`WorldFrame`) from universe coordinates and must tolerate
  `World.rebase()` at any tick (no cached world positions across ticks). Since M3-T14 the main scene rebases whenever the
  player is 5 km from the local origin: keep places as `UniversePos` or rebuild them from the live nodes every tick; a
  World-local point that must outlive a tick follows `World.rebased` (§14.1).
- Weapons and visuals read ship state through typed getters, never by reaching into sibling nodes.
- Rendering is invisible to gameplay code: `Ship` exposes hardpoints; its one `Hull` node draws the textured mesh, and
  its `LodSwitcher` decides when it is a far dot instead.
- The console imports no subsystem. Subsystems register their own commands and state providers with
  `DebugConsole.registry` in `_ready` (owner = `self`) and are dropped when they leave the tree (§6.4).

## 5. Newtonian flight model

### 5.1 State, units, parameters

Owned by Jolt via `RigidBody3D`: position (m), orientation (`Basis`), linear velocity `v` (m/s), angular velocity
`w` (rad/s, world frame), all relative to the `World` frame. Parameters from `ShipSpec`:

| Parameter | Default | Note |
|---|---|---|
| `mass` | 48 000 kg | tune for feel |
| `inertia` (body, diagonal) | (6.0e5, 6.0e5, 5.0e5) kg·m² | x pitch, y yaw, z roll; four heavy pods at 4.5 m radius dominate |
| `center_of_mass` | hardpoints `center_of_mass` | `center_of_mass_mode = CUSTOM` |
| `pod_main_thrust` | 0.36 MN per pod | 4 pods = 1.44 MN = 30 m/s² (~3 g) with both triggers |
| `pod_retro_thrust` | 0.36 MN per pod | 4 pods = 1.44 MN = 30 m/s² with both bumpers: reverse = forward (M3-T15, Q20; was 0.18) |
| `rcs_force_max` | (0.72 MN, 0.72 MN, 0) | sway / heave, 15 m/s², half the forward thrust (M3-T15, Q20; was 0.48); no axial RCS: fore/aft is the pods' job |
| `rcs_torque_max` | (9.4e5, 9.4e5, 1.57e6) N·m | = inertia × (1.57, 1.57, 3.14) rad/s² |
| `rate_max` | (60, 60, 90) deg/s | assist target at full deflection |
| `assist_gain_k` | 6.0 s⁻¹ | rate controller P gain |
| `pod_yaw_gain` | 0.5 | assist on: full one-sided trigger = 0.5 × `rate_max.y` = 30 °/s yaw |
| `pod_yaw_deadzone` | 0.10 | assist on: trigger differences below 10 % fly straight |
| `pod_yaw_smoothing_s` | 0.15 s | assist on: first-order smoothing of the pod-yaw command |
| `brake_gain_k` | 2.0 s⁻¹ | translational brake P gain |
| `exhaust_velocity` | 30 000 m/s | the reaction-mass flow: `mass_flow = Σ thrust / v_e` |
| `fuel_capacity_kg` | 28 800 kg | M2-T14 tank (`FuelTank`): 10 minutes of the four mains at full (48 kg/s). Only drawn down when `settings.fuel_unlimited` is off |

Pod geometry comes from hardpoints: pod centres at (±3.18, ±3.18) m (4.5 m radius at 45°), so the yaw lever arm
is ≈ 3.18 m. Derived numbers (tests always compute these from spec + hardpoints, never hard-code them):

- One side's mains at full, assist off: yaw torque `2 × 3.18 m × 0.36 MN ≈ 2.29 MN·m`, i.e. 3.8 rad/s²
  (≈ 220 °/s², ≈ 109 °/s after 0.5 s). Deliberately violent: pod steering is the Starfury trick. Tune pod
  thrust or inertia after first flight, not the model.
- With assist on, one trigger alone commands `pod_yaw_gain × rate_max.y` = 30 °/s (simulated: within 5 % after
  0.73 s; stops < 1 °/s 0.82 s after release). Holding that rate needs ≈ zero net torque, but one side's pods make
  2.29 MN·m and RCS (0.94 MN·m) can cancel only `0.94 / 3.18 ≈ 0.30 MN` of imbalance, so the flight computer trims
  that side to ≈ 41 % (≈ 6.2 m/s² forward) while turning: POD TRIM ≈ 59 %.

### 5.2 From command to forces

Pods: `ur`, `lr` = right side (x > 0); `ul`, `ll` = left side. Each pod has a main nozzle (exhaust +Z, so
thrust is -Z, forward) and a retro nozzle (exhaust -Z). RT drives both right mains, LT both left mains, RB both
right retros, LB both left retros. Nozzle positions `p_i` come from hardpoints relative to the body origin;
`r_i = p_i - center_of_mass`. Nozzle groups: `R_MAIN, L_MAIN, R_RETRO, L_RETRO`.

```
# inputs: c (FlightCommand), v_b, w_b (body frame), env_accel_b (body frame, ZERO in M1), assist_on, dt
#         layout (ThrusterLayout), spec (ShipSpec); state: d_s (smoothed pod-yaw command, in FlightAssist)

# 1. pilot demand per nozzle group (levels 0..1) and RCS translation
level[R_MAIN]  = c.main_right      level[L_MAIN]  = c.main_left
level[R_RETRO] = c.retro_right     level[L_RETRO] = c.retro_left
rcs_force      = Vector3(c.strafe.x * rcs_force_max.x, c.strafe.y * rcs_force_max.y, 0)

# 2. brake (hold X) overrides all translational demand, assist on or off (its rotation half is 4c)
if c.brake:
    a_des = -brake_gain_k * v_b - env_accel_b                     # env term: gravity hook (zero in M1)
    f_z   = clamp(mass * a_des.z, -main_total, retro_total)       # totals = 4 x per-pod thrust; -Z is forward
    level[R_MAIN]  = level[L_MAIN]  = max(0, -f_z) / main_total   # symmetric sides => zero pod torque
    level[R_RETRO] = level[L_RETRO] = max(0,  f_z) / retro_total
    rcs_force = clamp(mass * Vector3(a_des.x, a_des.y, 0), -rcs_force_max, rcs_force_max)

# 3. pod forces and their torque about the CoM: physics, not a yaw term
F_i      = level[group(i)] * thrust(i) * -exhaust_i                # each of the 8 pod nozzles
F_pods   = Σ F_i
tau_g    = Σ_{i in g} r_i × F_i                                    # per group;  tau_pods = Σ_g tau_g
# right mains: tau_y = +Σ x_i·T > 0 => nose LEFT.  left mains => nose RIGHT.  retros: the reverse.

# 4. rotation
if assist_on:
    # 4a. pod steering: the side difference is a yaw command (pilot terms, + = yaw right). LT or RB => right.
    d_raw = 0 if c.brake else (c.main_left - c.main_right) + (c.retro_right - c.retro_left)
    d_dz  = sign(d_raw) * max(0, |d_raw| - pod_yaw_deadzone) / (1 - pod_yaw_deadzone)
    d_s  += (clamp(d_dz, -1, 1) - d_s) * (1 - exp(-dt / pod_yaw_smoothing_s))   # reset on assist toggle / reset
if c.brake:
    # 4c. brake = all stop, assist on or off: sticks and D-pad ignored, d_s decays unused, nothing is trimmed
    w_target = face_rate(c.face_dir_b)                              # ZERO when face_dir_b is zero (no target)
    tau_rcs  = clamp(inertia * assist_gain_k * (w_target - w_b) - tau_pods, -rcs_torque_max, rcs_torque_max)
elif assist_on:
    rot   = Vector3(c.rot.x, clamp(c.rot.y + pod_yaw_gain * d_s, -1, 1), c.rot.z)
    # 4b. rate controller with pod feed-forward and trim
    w_target = rot * AXIS_SIGN * deg_to_rad(rate_max)
    tau_des  = inertia * assist_gain_k * (w_target - w_b)          # diagonal inertia, per axis
    residual = tau_des - tau_pods
    overflow = residual - clamp(residual, -rcs_torque_max, rcs_torque_max)
    if overflow.y != 0:            # more yaw is needed than RCS has: trim the groups fighting it (never raise any)
        cause = groups g with sign(tau_g.y) == -sign(overflow.y)   # empty when the stick alone asks too much
        lam   = 1 if cause is empty else max(0, 1 - |overflow.y| / Σ_{g in cause} |tau_g.y|)
        level[g] *= lam for g in cause;  recompute F_pods, tau_pods;  residual = tau_des - tau_pods
    tau_rcs = clamp(residual, -rcs_torque_max, rcs_torque_max)
else:
    tau_rcs = c.rot * AXIS_SIGN * rcs_torque_max                    # raw: stick / D-pad command torque

# face_rate(d): the brake's attitude controller, a stateless outer loop around the 4b rate loop (FlightAssist)
#   e     = (d.y, -d.x, 0) / sin(θ) * θ   for d = normalize(d), θ = angle(-Z, d)    # FORWARD × d: pitch + yaw only
#                                         # e = (θ, 0, 0) dead astern (pitch up through it); zero dead ahead
#   K     = assist_gain_k / 4             # critical damping of the cascade θ'' + k θ' + k K θ = 0
#   a     = 0.5 * min(rcs_torque_max.x / inertia.x, rcs_torque_max.y / inertia.y)   # planned deceleration
#   w     = e / θ * min(K θ, sqrt(2 a θ)), then scaled as a whole to fit rate_max per axis;  w.z = 0

# 5. outputs (body frame)
nozzle_forces = [(p_i, F_i)]              # Ship: apply_force(B·F_i, B·p_i) for each
rcs_force, tau_rcs                        # Ship: apply_central_force(B·rcs_force), apply_torque(B·tau_rcs)
force_b  = F_pods + rcs_force             # predicted totals, for tests and the overlay
torque_b = tau_pods + tau_rcs
trim     = 1 - lam                        # 0 when nothing was trimmed
pod_yaw_cmd = pod_yaw_gain * d_s          # for the overlay (POD YAW); 0 while braking or with assist off
rate_target_b = w_target                  # 0 with assist off unless braking
facing, face_error_rad                    # braking with a face_dir_b; the angle off the nose
mass_flow = (Σ |F_i| + |rcs_force|) / exhaust_velocity     # the Ship draws it from the FuelTank (M2-T14)
```

Reaction mass (M2-T14). `FuelTank` (pure) starts full at `fuel_capacity_kg`; the Ship calls `draw(mass_flow, dt)`
after each `compute`. `settings.fuel_unlimited` (default true, the M1 decision) makes the tank read full and never
draws it down. When a finite tank is empty the Ship passes `has_propellant = false` to `compute`: every pod nozzle and
the RCS translation force are cut to zero (`FlightOutput.propellant_empty`), whatever the mode or the brake asks.
RCS torque is not reaction-mass limited (it was never in `mass_flow`), so an empty ship can still turn but not thrust.
The ship's `mass` stays constant as the tank empties; `reset_to` (respawn) refuels.

The Ship also applies `apply_central_force(mass * World.environment_accel(position))` every tick (zero in M1).
Gravity is an environmental force, not a flight-model concern; `env_accel_b` enters the model only as
feed-forward for the brake (and later velocity-hold assists).

Why trim only yaw: with one command per side, a side's upper and lower pods fire equally, so their pitch torques
cancel and axial nozzles produce no roll. A unit test asserts `|tau_pods.x|, |tau_pods.z| < 1e-6` for every
demand. If a future layout breaks that symmetry, generalise the trim per axis.

Sign conventions. `c.rot` is in **pilot terms**: `x` pitch up, `y` yaw right, `z` roll right (clockwise as seen
by the pilot). With Godot's right-handed axes and -Z forward, +X rotation pitches the nose up, +Y yaws it left,
+Z rolls left, so `AXIS_SIGN = Vector3(+1, -1, -1)`. `FlightModel` is the only place that applies it; pin it with
one unit test per axis. `c.face_dir_b` is not in pilot terms but already a body-frame direction, so no sign map.

What the player must experience:

| Input | Assist OFF (raw) | Assist ON (default) |
|---|---|---|
| RT + LT equal | straight acceleration, zero net torque | same; differences under 10 % also fly straight (RCS cancels the small imbalance) |
| RT alone | accelerate and yaw nose **left** (right pods push); the spin keeps building | accelerate and turn nose **left** at a steady ≈ 30 °/s; at that rate the right pods are trimmed (POD TRIM); release and the turn stops |
| LT alone | accelerate and yaw nose **right** | mirror of RT alone |
| RB + LB | straight deceleration (retros) | same |
| RB alone | decelerate and yaw nose **right** | decelerate and turn nose **right** at ≈ 30 °/s |
| Right stick right + LT | (raw torque + pod yaw) | stick yaw and pod yaw add, capped at `rate_max`; left-pod torque speeds the turn-in |
| Right stick back / right / up-right diagonal | nose up / yaw right / roll right (torque) | nose up / yaw right / roll right (rate); stops when centred |
| Left stick right / up | translate right / up; nose does not turn | same |
| Release everything (or even out the triggers) | velocity unchanged; spin unchanged | velocity unchanged; rotation stops |
| X held | all stop: velocity → 0 with symmetric pods + RCS, rotation → 0; sticks, triggers ignored | same |
| X held, target selected | velocity → 0 while the nose swings onto the target and holds there (no roll) | same |

### 5.3 Integration

Jolt integrates at `physics/common/physics_ticks_per_second = 60` (semi-implicit Euler, constant force across the
tick). Rendering runs unlocked with `physics/common/physics_interpolation = true`. Forces are applied in
`Ship._physics_process` (not `_integrate_forces`; we do not override the integrator).

Expected test behaviour (verified headless): with F applied for n ticks from rest and zero damping,
`|v| = F / m · n / 60` within 1e-3 relative, and `|v|` stays constant after the force stops.

### 5.4 Mandatory project/body settings for true Newtonian motion

- `project.godot`: `physics/3d/physics_engine = "Jolt Physics"`, `physics/3d/default_gravity = 0.0`,
  `physics/3d/default_linear_damp = 0.0`, `physics/3d/default_angular_damp = 0.0`.
- Body: `gravity_scale = 0`, `linear_damp_mode = DAMP_MODE_REPLACE`, `linear_damp = 0`,
  `angular_damp_mode = DAMP_MODE_REPLACE`, `angular_damp = 0`, `can_sleep = false`, `continuous_cd = false`.
- The default damping is *combined* with the body value; forgetting either side gives a 10 %/s silent decay
  (measured: 4.76 -> 4.32 m/s over one second). An integration test guards this.

### 5.5 Flight assist semantics

- **Assist ON** (toggle B, persisted in `Settings`, default on): the flight computer owns attitude and commands
  angular *rates*. Pitch, yaw and roll come from the right stick (one axis by direction, §6.1) **plus the pod-yaw
  command**: the left/right difference of the triggers (and of the bumpers), with a 10 % deadzone, smoothed over
  0.15 s, scaled by `pod_yaw_gain` (one full trigger = 30 °/s) and capped together with the stick's yaw at `rate_max`.
  Stick centred and sides even means "stop rotating". The flight computer knows the pods' torque
  exactly (from hardpoints) and treats it as feed-forward: it lets pod torque drive the turn-in, cancels the
  excess with RCS once the commanded rate is reached, and trims (only ever reduces) the side causing it when RCS
  authority is not enough. The pilot's trigger and bumper levels are a ceiling, never exceeded. Translation is
  untouched except by that trim and by the brake.
- **Assist OFF**: raw Newtonian. Pods fire exactly as demanded and their r × F torque acts in full, so uneven
  triggers tank-steer the ship. The stick commands raw RCS torque. Nothing damps rotation. This is the
  flip-and-burn mode.
- **Brake** (hold X), both modes: **all stop**. The flight computer takes over translation and rotation.
  Translation: pods fire symmetrically (no torque) plus RCS sway/heave, nulling velocity relative to the `World`
  frame (later: relative to a chosen reference such as the station). Rotation: the rate target is zero and the P
  rate controller (gain `assist_gain_k`, RCS only, pods symmetric so nothing to trim) nulls any spin, with assist
  off too. Triggers, bumpers and both sticks are ignored while held. Measured in Jolt (both modes): a
  60 °/s tumble plus 50 m/s of drift is below 0.5 °/s after 0.87 s and below 0.5 m/s after 4.3 s (RCS sway/heave
  at 10 m/s² is the slow part); AC5f.
- **Brake with a target selected**: rotation tracks `face_rate(face_dir_b)` (§5.2) instead of zero, so the nose
  swings onto the target along the shortest arc and stays there; facing a point has no roll requirement, so the
  roll target is zero and any roll rate is nulled. `FlightCommand.face_dir_b` is the body-frame line of sight,
  which the Ship writes every tick from its `TargetingController` (zero without a selection); an AI pilot gets the
  same behaviour by selecting a target. The controller is a stateless outer loop on the angle off the nose around
  the rate loop: `|w| = min(K θ, sqrt(2 a θ))`. `K = assist_gain_k / 4` makes the small-angle cascade
  `θ'' + k θ' + k K θ = 0` critically damped (double pole at `-k / 2` = -3 s⁻¹: no overshoot, no hunting on the
  target). The `sqrt(2 a θ)` branch, with `a` half the RCS pitch/yaw angular acceleration, guarantees the turn can
  be stopped within RCS authority with margin for the rate loop's lag and cross-axis nulling (for the Starfury it
  never binds: `rate_max` does first). The vector is scaled as a whole to fit `rate_max`, so the nose still swings
  straight at the target. Measured in Jolt (both modes): 90° off the nose to within 2° in 2.6 s, no overshoot,
  0.002° after 5.5 s; in the pure model 150° off takes 3.2 s.
- **Why the brake owns rotation** (maintainer's M1 play test: "expected behavior is to get to an all stop with the
  brake on", and to "center the nose on the target when a target is selected"). X is the panic button: one input
  that leaves the ship motionless whatever it was doing, in either mode, instead of a brake that stops drift but
  leaves a tumble running with assist off. Facing the selected target is the natural next step (stop, then point
  the guns) and costs nothing when no target is selected.
- **Why this rule** (user decision: pod steering must work with assist on too). (1) Pod steering is the Starfury
  identity in both modes; assist off is the raw tank-steer, assist on is the same gesture made controllable: a
  bounded, predictable turn rate instead of ≈ 220 °/s² of runaway, which stops when the sides are evened out.
  (2) The deadzone exists because generic-pad triggers rarely read exactly equal at full squeeze; the smoothing
  removes jerk from noisy analog triggers. (3) Gain 0.5 keeps one trigger below the stick yaw's authority while
  trigger plus stick still reach full rate. (4) The "never above the trigger" rule still holds: the commanded yaw
  points the same way as the pods' own torque, so the flight computer only ever needs to cancel or trim, never to
  add thrust; the pilot's throttle stays a ceiling. (5) One closed-form rule plus one first-order filter:
  deterministic, unit-testable, and identical for AI pilots, which write the same `FlightCommand`. All three
  tunables live in `ShipSpec`.
- Rate controller: pure P with clamp. A 60 °/s stop takes ≈ 0.9 s (simulated). Add D only if human testing shows
  oscillation.

### 5.6 Limits and later work

- Jolt clamps body speed: `physics/jolt_physics_3d/limits/max_linear_velocity` (default 500 m/s) and
  `max_angular_velocity` (default 2700 °/s). M1 speeds stayed under 200 m/s; after the M2 play test the project sets the
  linear limit to 10 000 m/s, just above the ship's own ceiling (next bullet).
- Speed ceilings (post-M2, `SpeedGovernor`, `ShipSpec.speed_limit_mps` = 9 999 and `assist_speed_max_mps` = 5 000): relativity
  does not exist, but inertia grows with speed, so the thrust that reaches the hull is scaled by `sqrt(1 - (v / v_max)²)`
  (effective mass `m / sqrt(1 - (v / v_max)²)`): full at rest, 87 % at 5 000 m/s, 0 at 9 999 m/s. Flight assist is a "maximum
  safe speed": with assist on, thrust that would push the speed past 5 000 m/s is cancelled along the velocity (sideways thrust
  stays, so the ship can still turn its velocity; coasting faster is left alone). `Ship` applies both to the force each
  tick (never to torque) and clamps the speed at the limit as a last resort. Bolts leave at 1 000 m/s relative to the ship.
  **As built (M6-T08, D67, §19.5):** these speeds are read against the ship's reference (`v - v_rest`: a place's velocity, or the
  circular orbit's at the ship near a body), not against the frame, so a ship in a steady low orbit reads about 0 and the ceiling
  and the assist's limit apply on top of the orbit.
- If Jolt ever becomes the obstacle, the fallback is a custom integrator driving a `Node3D`; the pure-class split
  (D5) keeps that contained.

## 6. Input and the debug console

### 6.1 Gamepad mapping (user-chosen layout)

```
RT  right main pods (analog)      LT  left main pods (analog)
RB  right retros (hold)           LB  left retros (hold)
R-stick  up/down pitch, left/right yaw, diagonals roll       L-stick  strafe L/R + up/down
D-pad Up  flight assist           D-pad Down  next weapon           D-pad Left  running lights        D-pad Right  comms menu (radial)
A  fire       B  tap: next target, hold (0.35 s): previous target
Comms menu open (D-pad Right, 4 s): D-pad Up/Right/Down/Left pick entries 1-4 (attack my target, form on me, engage at will,
  cover me); B closes it; assist, next weapon, lights and the target button do nothing meanwhile
X  auto-track (toggle): the nose follows the lead point of the selected target
Y  camera 1st/3rd
R3  brake (hold): all stop; faces the target if one is selected
L3  free look (hold): the right stick turns the camera, not the ship; the view stays where it is left until L3 is released
Back  reset                       Start  pause
```

Revised after the M2 play test: X toggles the auto-track (`FlightCommand.autotrack`: pitch and yaw go to the attitude controller
that swings the nose onto `track_dir_b`, the lead point of the selected target, plus `track_rate_b`, the rate at which that
direction is turning, fed forward so a crossing target is followed without the standing lag of a position-only controller; thrust
and drift are untouched; with no target it takes the nearest hostile, and `Main` switches it off when none is left), R3 is the
brake, L3 is free look (`CameraLook`: cockpit head turn up to 135° / 80°, chase orbit around the ship; the right stick turns the
view at up to 180°/s and a centred stick holds it (M3-T15; it was an absolute direction), the mouse turns it by its travel; only
releasing the button eases the view back to centre). The debug overlay is F3
only. The mouse flies (its speed, smoothed over a few ticks, is the pitch and yaw rate command; `settings.mouse_full_rate_px_s`),
mouse 1 fires, mouse 2 is the tap-or-hold target button, the wheel steps through the targets, the middle button is free look.
The mouse is captured while flying and freed by holding Alt, the console, the pause or a lost window focus
(`GodotInputSource.mouse_free` then reads it as idle).

Keyboard layout B (M3-T01, maintainer answer Q9). The M2.1 keyboard put pitch, yaw, strafe and targets on the right side, under
the hand that holds the mouse. Layout B puts every flight key under the left hand and none right of the G / B column; physical
keys, US positions. Pods are by position: Q / E drive the left / right main pod and W both, A / D the left / right retro and S
both. R / F strafe up / down, Z / C strafe left / right, Caps Lock / G roll left / right, X brake (hold), Shift auto-track
(toggle), Space fire, V fire mode, T flight assist, B the tap-or-hold target button (as mouse 2: tap next, hold nearest the nose), Tab camera. The
housekeeping keys stay where they were (Esc, Backspace, N and Print, F3). There are no keys for pitch, yaw, `target_prev`
or `target_ahead`: the mouse flies, the wheel steps targets both ways, and a hold of B or mouse 2 is target-ahead. Mouse 4 / 5
(the side buttons, `mouse:8` / `mouse:9`) are auto-track and fire mode. Ctrl, Alt (frees the mouse), the number row (keys 1-4
are the wing orders of M3-T07) and ` (console) are not bound to flight. Caps Lock is read as a held key by polling
`Input.is_physical_key_pressed(KEY_CAPSLOCK)` like any other; a desktop that delivers it as a toggle would need Ctrl instead.
Saved user profiles in `user://controls/` keep the keys they were saved with; `controls use default` loads layout B.

Revised after the M1 play test on the maintainer's generic pad: yaw and roll swapped places (right stick X was
yaw, the D-pad was roll), and because that pad has no stick clicks, `target_ahead` moved onto a D-pad Up hold
(R3 still works where it exists). Revised again after the M3 play test (M3-T15, Q15): the right stick flies all three
axes by direction (pitch on up/down, yaw on left/right, roll on the diagonals), B cycles targets (tap next, hold
previous, as the mouse wheel), D-pad Up toggles assist and D-pad Left / Right are left free; the pad has no
`target_ahead` (keyboard B, a Mouse 2 hold or the console give it). A saved profile with the old default pad layout
is moved onto the new one when it loads (its keys and mouse kept; `ControlProfile.PAD_LAYOUT_BEFORE_T15`); one with
its own pad bindings is left alone, with a warning. D-pad Left became the running lights (M3-T27, Q27), with key 5, the free key beside the
wing orders. A saved profile gets the action when it loads, like any new action; one that already uses D-pad Left keeps it, and its lights
are key 5 alone (m1_classic, which rolls on the D-pad, is the same). D-pad Right became the comms menu (M5-T07, D54), with Ctrl, the left
hand's free key; a saved profile gets it like any new action, and one that rolls on D-pad Right keeps that and gets Ctrl alone.

All via `InputMap` actions in `project.godot`; `device = -1` (any pad). Names are the Xbox-style names Godot/SDL3
use for the standard layout; any pad SDL3 recognises, generic XInput clones included, presents it.

| Action | Pad (Godot enum, index) | Keyboard | Type | Deadzone | Curve |
|---|---|---|---|---|---|
| `main_right` | RT `JOY_AXIS_TRIGGER_RIGHT` (axis 5, +) | E, W | analog 0..1 via `get_trigger` | 0.05 | linear |
| `main_left` | LT `JOY_AXIS_TRIGGER_LEFT` (axis 4, +) | Q, W | analog 0..1 via `get_trigger` | 0.05 | linear |
| `retro_right` | RB `JOY_BUTTON_RIGHT_SHOULDER` (10) | D, S | hold | - | - |
| `retro_left` | LB `JOY_BUTTON_LEFT_SHOULDER` (9) | A, S | hold | - | - |
| `pitch_down` / `pitch_up` | Right stick Y `JOY_AXIS_RIGHT_Y` (axis 3, -/+): stick back = nose up; `Settings.invert_y` flips | none (the mouse's Y) | analog pair, split by direction (below) | radial 0.15 | expo 1.5 |
| `yaw_left` / `yaw_right` | Right stick X `JOY_AXIS_RIGHT_X` (axis 2, -/+): stick right = yaw right; the diagonals roll | none (the mouse's X) | analog pair with pitch, split by direction | radial 0.15 (one deadzone with pitch) | expo 1.5 |
| `roll_left` / `roll_right` | none (the right stick's diagonals) | Caps Lock / G | hold, full roll, added to the stick's | - | - |
| `strafe_left` / `strafe_right` | Left stick X `JOY_AXIS_LEFT_X` (axis 0, -/+) | Z / C | analog pair | radial 0.15 | linear |
| `strafe_down` / `strafe_up` | Left stick Y `JOY_AXIS_LEFT_Y` (axis 1, +/-) | F / R | analog pair | radial 0.15 | linear |
| `target_cycle` | B `JOY_BUTTON_B` (1) | none | tap or hold: a tap gives `target_next` on release; a hold of 0.35 s gives `target_prev` once | - | - |
| `target_next` | none (pad B, `target_cycle`) | B, mouse 2 | tap or hold: a tap gives `target_next` on release; a hold of 0.35 s gives `target_ahead` once | - | - |
| `target_prev` | none (the wheel steps both ways) | none | edge | - | - |
| `weapon_next` | D-pad `JOY_BUTTON_DPAD_DOWN` (12) | V, mouse 5 | edge | - | - |
| `target_ahead` | none | none (the B / mouse 2 hold) | edge | - | - |
| `fire` | A `JOY_BUTTON_A` (0) | Space, mouse 1 | hold | - | - |
| `toggle_flight_assist` | D-pad `JOY_BUTTON_DPAD_UP` (11) | T | edge | - | - |
| `toggle_running_lights` | D-pad `JOY_BUTTON_DPAD_LEFT` (13) | 5 | edge (M3-T27) | - | - |
| `comms_menu` | D-pad `JOY_BUTTON_DPAD_RIGHT` (14) | Ctrl | edge (opens the comms menu, M5-T07; while it is open the same press closes it, M5-T46) | - | - |
| `brake` | R3 `JOY_BUTTON_RIGHT_STICK` (8) | X | hold | - | - |
| `autotrack` | X `JOY_BUTTON_X` (2) | Shift, mouse 4 | edge (toggles auto-track; `InputAdapter.autotrack_on`) | - | - |
| `camera_look` | L3 `JOY_BUTTON_LEFT_STICK` (7) | mouse 3 (middle) | hold | - | - |
| `toggle_camera` | Y `JOY_BUTTON_Y` (3) | Tab | edge | - | - |
| `reset_ship` | Back `JOY_BUTTON_BACK` (4) | Backspace | edge | - | - |
| `pause` | Start `JOY_BUTTON_START` (6) | Esc | edge | - | - |
| `debug_toggle_overlay` | none | F3 | edge (toggles `settings.show_overlay`) | - | - |
| `screenshot` | none | N, Print | edge (saves `user://screenshots/shot_<time>.png`) | - | - |
| *(console toggle, not an action)* | none | ` (physical `KEY_QUOTELEFT`, 96) | handled in `DebugConsole._input` | - | - |

Notes:
- Only axes 0-5 and buttons 0-14 are used. Guide (5) and SDL extras (paddles, misc, touchpad, ≥ 15) are not.
  No rumble, no impulse triggers, no light bar, no motion sensors.
- W and S are "both sides" keys: the same key is an event on two actions (W the two main pods, S the two retros). The mouse wheel is not an action (it cannot be held):
  `Main._input` feeds wheel notches and mouse motion to `GodotInputSource`, which hands them to `InputAdapter` once per tick.
- The ` key belongs to the console alone: it is not an `InputMap` action and must never be bound to one (a test
  enforces it). While the console is open, Esc closes it instead of pausing (keyboard gameplay bindings are
  masked, §6.4).
- `GodotInputSource` evaluates every action itself from its `InputMap` events by polling devices
  (`Input.get_joy_axis`, `is_joy_button_pressed`, `is_physical_key_pressed`, `is_mouse_button_pressed`), never via
  `Input.is_action_pressed`. That is what lets it mask keyboard and mouse per device class while the console is
  open: `Input` action state would still report keys typed into the prompt.
- Tap or hold (in `InputAdapter`): two buttons, on separate timers. Pad B (`target_cycle`) and keyboard B / Mouse 2
  (`target_next`): a press released before `Settings.target_hold_s` (default 0.35 s, counted in physics ticks) gives
  `target_next` on the release tick; a press still held when it crosses the threshold gives its hold action once, on
  that tick (`target_prev` for pad B, `target_ahead` for keyboard B and Mouse 2), and its release gives nothing, so a
  hold never also cycles and never repeats. A tap therefore acts on release, which costs nothing when cycling targets.
  A console open/close (`resync_edges`) or `reset()` drops a press in progress on either. Many generic pads have no
  stick clicks (the maintainer's has neither R3 nor L3), so nothing needed to fly sits on them: R3 is the brake (also
  X on the keyboard) and the overlay toggle is F3.
- `target_ahead` samples the boresight when it fires, so the small stick jolt of an R3 click does not matter.
- The right stick by direction (`InputAdapter.split_stick`, M3-T15): within `STICK_SECTOR_HALF_DEG` (22.5°) of straight
  up or down it pitches, within it of straight left or right it yaws, and on the four diagonals between it rolls toward
  the side the stick leans (up-right and down-right roll right). One axis at a time, at the stick's deflection after
  deadzone and expo. The D-pad yaw ramp (`yaw_ramp_s`) went with it; `Settings` reads only schema keys, so an old
  file's line is ignored and dropped on the next `save`.
- Sticks: `Input.get_vector(neg_x, pos_x, neg_y, pos_y, Settings.stick_deadzone)` (radial deadzone with
  rescaling), then `sign(r)·|r|^1.5` on the right stick's length in `InputAdapter`. The right stick is one vector (x yaw,
  y pitch, split as above), so its three axes share the radial deadzone. The keyboard's Caps Lock/G give full roll at
  once (no ramp), added to the stick's roll and clamped; yaw and pitch have no keys (the mouse flies them, §16 D38).

Generic-pad quirks, handled in the input layer (never in gameplay code):

- **Trigger range.** SDL3 normally reports triggers as 0..1; some generic pads or driver paths report -1..1
  (rest = -1), and some have digital triggers. `InputSource.get_trigger(action)` reads every
  `InputEventJoypadMotion` bound to the action from `InputMap` (so rebinding still works), takes the raw
  `Input.get_joy_axis(device, axis)` per connected pad and normalises it with that pad's calibrated rest through
  the pure `TriggerCalibration`: `clamp((raw - rest) / (1 - rest), 0, 1)`, then the trigger deadzone. Bound keys
  count as 1.0; the result is the max. Calibration samples 0.5 s of idle input at start-up and on
  `Input.joy_connection_changed`, snaps rest to 0 or -1, and stores it per pad GUID in `Settings`. Digital
  triggers simply report 0 or 1 (full side thrust).
- **Stick drift.** `Settings.stick_deadzone` default 0.15, adjustable to 0.30; radial with rescaling.
- **Wrong layout / D-pad as hat.** SDL3 maps recognised pads (hats included) to the standard enums. Otherwise the
  fix is an SDL mapping string, not code: `Settings` applies lines from `user://gamecontrollerdb.txt` with
  `Input.add_joy_mapping(line, true)` before the first frame. The overlay shows pad name, GUID and raw axes so a
  user can author that line.
- **Hot-plug.** Godot handles it; the input layer re-runs trigger calibration and the overlay updates.

Example serialised action (so the format is unambiguous):

```
[input]
main_right={
"deadzone": 0.05,
"events": [Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":5,"axis_value":1.0,"script":null), Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":69,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null), Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)]
}
```

### 6.2 Commands

```
class_name FlightCommand extends RefCounted   # consumed by the flight model; written by the player or an AI
var main_left: float    # 0..1  LT -> both left main nozzles
var main_right: float   # 0..1  RT -> both right main nozzles
var retro_left: float   # 0..1  LB (0 or 1 from a button; float keeps AI/HOTAS analog-ready)
var retro_right: float  # 0..1  RB
var strafe: Vector2     # x sway right, y heave up, -1..1 (radial)
var rot: Vector3        # pilot terms: x pitch up, y yaw right, z roll right; -1..1
var brake: bool         # held: all stop, and face face_dir_b if set (§5.5)
var toggle_assist: bool # edge, true for one tick
var face_dir_b: Vector3 # body frame (+X right, +Y up, -Z forward), any length, zero = none: what the brake
                        # turns the nose onto. Not a pilot input: the Ship writes it every tick from its
                        # TargetingController (line of sight to the selected target).

class_name CombatCommand extends RefCounted   # weapons + targeting; written by the player or an AI
var fire: bool          # held
var weapon_next: bool   # edge
var target_next: bool   # edge (a pad B, keyboard B or Mouse 2 tap, on release)
var target_ahead: bool  # edge (keyboard B or Mouse 2 held for target_hold_s)

class_name UiCommand extends RefCounted       # player-only
var toggle_camera: bool # edges, all of them
var reset: bool
var pause: bool
var toggle_overlay: bool

class_name PilotCommand extends RefCounted
var flight: FlightCommand
var combat: CombatCommand
var ui: UiCommand
```

`InputAdapter.sample(source: InputSource, dt: float) -> PilotCommand` is the only place that knows action names.
Tests use `FakeInputSource` with scripted values; the real `GodotInputSource` is a thin wrapper over `Input` and
`InputMap`.

Why `face_dir_b` lives in `FlightCommand` (and is body-frame): the pure `FlightModel` sees only the command and
body-frame state, so the direction must arrive in the body frame, and the Ship is the one that knows its basis and
owns the `TargetingController`. Putting it in the command rather than a `compute` argument keeps one input type
for every pilot: an AI pilot selects a target and brakes exactly like the player, and pure tests or other hosts can
set it directly.

### 6.3 Combat functions behind the buttons (M1)

- **TargetingSystem** (pure). Candidates are `Array[TargetInfo]` (`id`, `display_name`, `faction`, `position`,
  `velocity`, `broadcast_range_m`), sensor range 25 km. Broadcasts (M3-T17, Q21): a candidate is within reach inside the
  sensor range or inside its own `Targetable.broadcast_range_m` (0 = none; nav buoys 1 000 km, allied ships 100 km, `INF`
  for M11's hyperspace gates), so it can be cycled to, selected and read out from there. Ranges are taken from this tick's
  World-local positions in 64-bit; the rebase keeps the World origin near the player, so they equal the universe distances
  to float32 rounding at that range (6 cm at 900 km, 64 m at 1e9 m).
  - `select_next(ship_pos)`: candidates in range sorted by range; picks the one after the current, wrapping to
    the nearest; with no selection, the nearest.
  - `select_ahead(ship_pos, forward)`: smallest angle between `forward` and the direction to the target, forward
    hemisphere only (< 90°), ties to the nearer; if none, the selection is unchanged.
  - `readout(ship_pos, ship_vel) -> TargetReadout`: `range_m`, `closing_mps = -(v_t - v_s)·(p_t - p_s) / range`
    (positive = closing), `angle_off_deg`. The selection clears when the target leaves the list or sensor range.
- **TargetingController** (node under the ship) gathers group `targetable` each physics tick, feeds the system,
  applies `CombatCommand` edges, emits `target_changed(id)`. `selected_offset()` is the live World-frame line of
  sight to the selection (zero without one); the Ship turns it into `FlightCommand.face_dir_b` every tick.
- **NavBuoy**: inert marker with a textured body (one shared mesh, so every buoy instances), a steady beacon mesh with a slow fade over it, a 10 °/s spin about its long axis, optional constant drift. No collision; cannot be shot. Five are spawned
  from `data/scenarios/free_flight.json` at 0.5-5 km; faction `neutral`.
- **Pulse cannon modes** (`PulseCannonGate`, pure): `ALTERNATING` (4 Hz, muzzles alternate) and `LINKED`
  (2 Hz, both muzzles together). `weapon_next` cycles and wraps; the cooldown carries over, so switching cannot
  raise the rate of fire.
- **Capacitor** (`WeaponCapacitor`, pure, M2-T14): each projectile costs `cost_per_shot` (a linked volley is two),
  the store recharges at `recharge_per_s` up to `capacity`. Defaults 100 / 14 / 25 per s: empty to full in 4 s;
  a full store pays for 12 alternating shots (3 s) or 5 linked volleys at the full rates, after which sustained fire is
  held to 1.8 projectiles per second. The gate asks the capacitor before it commits a shot; a refused shot leaves the
  cooldown and the muzzle turn untouched. `PulseCannonGate.capacitor` is null (unlimited, as in M1) unless set;
  `PulseCannon` builds one from its `WeaponSpec` (`capacitor_capacity`, `capacitor_cost_per_shot`,
  `capacitor_recharge_per_s`, M2-T02).

### 6.4 Debug console (` key)

**Availability.** Always on, in every build and every scene (`settings.console_enabled`, default true). It is a
single-user personal project, so usefulness wins over gating. With `console_enabled = false` the ` key does nothing,
but startup scripts (`--console-exec`, autoexec) still run, so headless automation keeps working.

**Opening.** The physical ` key (`KEY_QUOTELEFT`, 96; physical so it stays the same key on non-US layouts) toggles
the console. It is handled in `DebugConsole._input` before GUI and gameplay, marked handled (so the character never
reaches the prompt), and is never an `InputMap` action. Esc also closes it.

```
DebugConsole (autoload Node, PROCESS_MODE_ALWAYS so it works while paused)
├─ registry: ConsoleRegistry   pure: commands, state providers, parse / validate / execute, help, completion
├─ ConsoleUI (CanvasLayer 100) log + prompt; keyboard only; history; Tab completion
├─ FpsCounter (CanvasLayer 99) top-right: FPS + frame time (ms) + watched values; follows settings.show_fps
├─ ConsoleLogger (Logger)      OS.add_logger(): engine errors/warnings into the log. Called off the main
│                              thread, so it only appends to a Mutex-guarded queue that the console drains
└─ flags: DebugFlags           session-only cheats, never saved. M1: invulnerable
```

Pure, unit-tested pieces: `ConsoleTokenizer` (whitespace, "double quotes", `;` separates commands, `#` starts a
comment), `ConsoleCommand` + `ConsoleArg` (typed arguments: bool, int, float, string, enum, path, vec3; optional
with default; summary and usage strings), `ConsoleRegistry`, `ConsoleStateProvider` with the `ConsoleVars` helper,
`ConsoleHistory` (100 entries, persisted to `user://console_history.txt`), `ConsoleCompleter`, `ConsoleFormat`,
`ConsoleResult` (ok flag + output lines).

**Registration.** Subsystems register in `_ready` with themselves as owner; the registry drops an owner's entries
when it calls `unregister_owner(self)` in `_exit_tree`, and prunes freed owners on access. The console never
imports a subsystem: later milestones extend it only by registering.

```
func _ready() -> void:
    DebugConsole.registry.register_command(ConsoleCommand.new(&"assist", "Toggle or set flight assist",
        [ConsoleArg.bool_optional(&"state")]), _cmd_assist, self)
    DebugConsole.registry.register_provider(&"ship", ConsoleVars.new({
        &"speed":     {"get": func() -> float: return linear_velocity.length(), "type": TYPE_FLOAT, "unit": "m/s"},
        &"assist_on": {"get": func() -> bool: return assist_on, "set": set_assist, "type": TYPE_BOOL},
    }), self)
```

**State, not reflection.** State is read through `provider.key` paths from whitelisted providers only.
`get ship.queue_free` is "unknown key", never a call. Writable keys declare a setter, type and range; `set`
validates before calling. Values are formatted consistently (vectors to 2 decimals, units appended).

| Provider | Owner (task) | Keys (w = writable) |
|---|---|---|
| `settings` | Settings (T01/T07) | every schema key (w, typed, ranged) |
| `debug` | DebugConsole (T07) | `invulnerable` (w) |
| `time` | SimClock (T07) | `sim_time_s`, `warp`, `timescale` |
| `input` | GodotInputSource (T07) | `pads` (name, GUID, trigger rest, raw axes), `keyboard_masked`, last command fields |
| `ship` | Ship (T10) | `position`, `universe_position`, `velocity`, `speed`, `body_velocity`, `angular_rate_dps`, `assist_on` (w), `trim`, `pod_yaw`, `main_levels`, `retro_levels`, `mass_flow`, `fuel_kg` (w; M2-T14), `fuel_fraction` (0..1; 1 while `fuel_unlimited`) |
| `world` | WorldFrame (T09) | `origin`, `origin_velocity`, `auto_rebase_distance_m` (5 000 in the main scene), `rebases` (count, automatic and console), `rebase_us` (the last one's wall-clock cost, shift, handlers and end-of-tick reset; M3-T14) |
| `camera` | CameraRig (T12) | `mode` (w), `fov` |
| `weapons` | PulseCannon (T13) | `mode` (w), `cooldown_s`, `charge` (w, 0..1 capacitor; M2-T14) |
| `targeting` | TargetingController (T14) | `selected` (w: display name or `none`), `range_m`, `closing_mps`, `candidates` |
| `render` | RenderStatus (M4-T31) | `renderer` (`forward_plus`, or `headless`), `fps`, `frame_ms`, `draw_calls`, `triangles`, `vram_mb`, `far_dots`, `gpu`, `gpu_ms`, `display`, `window` (M4-T41) |
| `lights` | LightRig (M3-T21) | `picked`, `candidates`, `active`, `cost_us` (§7.3) |

M1 commands:

| Command | Owner | Does |
|---|---|---|
| `help [command]` | console | list commands, or one command's usage |
| `clear` | console | clear the log |
| `state [provider]` | console | list providers, or every `key = value` of one |
| `get <path>` | console | one value, e.g. `get ship.speed` |
| `set <path> <value>` | console | type-checked write; for `settings.*` it applies now and is session-only until `save` |
| `toggle <path>` | console | flip a writable bool |
| `default <path>` | console | reset a setting to its default (session) |
| `save` / `revert` | console -> Settings | persist all settings to `user://settings.cfg` / reload them from disk |
| `watch <path>` / `unwatch <path\|all>` | console | live values under the FPS counter (max 8, session) |
| `fps [on\|off]` | console | shorthand for `toggle settings.show_fps` |
| `god [on\|off]` | console | shorthand for `toggle debug.invulnerable`; session-only, never saved. M1 has no damage; M2 hull damage on the player skips while it is set |
| `timescale <0.05..1>` | console | debug slow motion via `Engine.time_scale`, which scales physics delta and therefore `SimClock`. Capped at 1 in M1; real warp is `SimClock`'s job (M9 adds a `warp` command) |
| `exec <file>` | console | run commands from a `res://` or `user://` file |
| `wait <frames>` | console | delay the rest of the queue by N physics frames (scripts, headless runs) |
| `quit [code]` | console | quit with an exit code |
| `assist [on\|off]` | Ship | flight assist |
| `refuel [kg]` | Ship | refill the reaction-mass tank, or add `kg` (M2-T14) |
| `camera [cockpit\|chase]` | CameraRig | set, or toggle with no argument |
| `respawn` | Main | ship reset (same as Back) |
| `pause [on\|off]` | Main | tree pause (same as Start) |
| `rebase <dx> <dy> <dz>` | WorldFrame | manual `World.rebase()`. Since M3-T14 the main scene's automatic rebase brings the player back to the origin in the same tick, so `rebase -900000 0 0` ends with `world.origin` on the player and `world.rebases` up by two |

Weapon mode and target selection are reached with `set weapons.mode linked` and `set targeting.selected "NAV
BRAVO"` rather than extra commands.

**Settings.** `Settings` is schema-driven (`SettingsSchema`): every key has a type, default and range or choices.
`Settings.get_value(key)`, `Settings.set_value(key, value) -> Error` (validated, applies immediately, marks the key
unsaved, emits `changed(key, value)`), `reset(key)`, `save()`, `revert()`. Nothing is written to disk except by
`save`; `state settings` marks unsaved keys with `*`. M1 schema:

| Key | Type | Default | Range / choices |
|---|---|---|---|
| `invert_y` | bool | false | |
| `stick_deadzone` | float | 0.15 | 0.0-0.30 |
| `trigger_deadzone` | float | 0.05 | 0.0-0.20 |
| `target_hold_s` | float | 0.35 | 0.15-1.0 |
| `target_menu_blur` | float | 0.35 | 0.0-1.0 | M5-T44: focus pull strength while a radial menu is open; 0 is off |
| `assist_default` | bool | true | |
| `fuel_unlimited` | bool | true | M2-T14: reaction mass is never drawn down and the fuel gauge stays full; off = finite tank |
| `camera_default` | enum | `chase` | `chase`, `cockpit` |
| `camera_chase_smoothing_s` | float | 0.0 | 0.0-0.5 (0 = rigid chase camera) |
| `show_overlay` | bool | true | |
| `show_fps` | bool | false | |
| `console_enabled` | bool | true | |
| `console_pause_on_open` | bool | false | |

Pad calibration (`[pads]`, trigger rest per GUID) is data, not a setting: read-only through `state input`.

**Input and time while open.**
- Keyboard and mouse gameplay input are masked: `GodotInputSource` drops key and mouse bindings while
  `DebugConsole.captures_keyboard()` (§6.1), so typing `w` never thrusts. On open and close, `InputAdapter`
  re-seeds its edge state from the current state, so nothing fires on the transition.
- The gamepad keeps flying. It is never used for typing, and the console's main job is watching live state
  (`watch ship.speed`) while you fly. The console UI swallows joypad *events*, so pad buttons cannot navigate or
  activate the prompt; gameplay polls devices and is unaffected.
- Sim time keeps running: the ship simply coasts (Newtonian) while your hands are on the keyboard.
  `settings.console_pause_on_open` pauses the tree while the console is open, and `pause` works either way.

**FPS counter vs overlay.** The debug overlay (L3/F3, `settings.show_overlay`) is the full readout and keeps its FPS
line. The FPS counter is a separate minimal label owned by `DebugConsole`, so it works in every scene and while
the overlay is hidden; watched values are drawn under it.

**Output and automation.**
- Every command line and its output go to the log and to stdout (`[console] > get ship.speed`,
  `[console] ship.speed = 42.10 m/s`); errors go to stderr (`[console] error: unknown key 'ship.sped' (did you
  mean ship.speed?)`). Headless tests and agents grep these lines.
- Startup scripts run one physics frame after the current scene's `_ready`, so its providers exist: first
  `user://autoexec.cfg` (one command per line, if present), then the command-line user arguments
  `--console-file=<path>` and `--console-exec="cmd; cmd"`. With `--console-strict`, the first error quits with exit
  code 1. Example: `godot --headless --path . -- --console-exec="wait 60; state ship; quit"`.

**Command list.** `info.md` (repository root) lists every console command and state provider with its arguments and where it exists; `tests/integration/test_console_command_list.gd` fails when a registered one is missing from it, so a task that adds a command updates `info.md` in the same commit.

**UI.** Top 40 % of the screen, translucent panel, monospace, prompt `>`, Up/Down history, Tab completion (command
names, then provider paths, setting keys and enum values; repeated Tab cycles), PageUp/PageDown scroll, 1000-line
ring buffer; engine errors in red and warnings in yellow from `ConsoleLogger`.

## 7. Rendering pipeline

### 7.1 What is drawn how

| Element | Representation | Why |
|---|---|---|
| Ship hulls (the Starfury, the raider), capital stand-ins, the station stand-in | **Textured meshes** (`Hull`, one shared mesh per asset from `MeshAssets`, §9; M4-T30a to T30d), lit by the scene (§7.3) | One draw per surface per asset, so every copy of a hull instances; the maps carry the paint, the panel lines, the markings, wear and the emissive windows and nozzles; a Starfury's wing livery is per-ship instance uniforms over the shared material (§17.18). |
| Nav buoy bodies, debris chunks | Textured meshes (the buoy's own; a chunk is cut from its hull on the hull's maps, so chunks instance with the hulls) | The same pipeline as the hulls. |
| Stars | Points: `StarField`, one `MultiMeshInstance3D` of camera-facing quads with a 1 px floor (§17.19) | Crisp at any resolution; a star delivers the same light at every render height. |
| Nebula | A generated equirectangular panorama on the environment's sky; its alpha dims the stars behind it (§17.19) | The gas is smooth: one texture, no per-frame work. |
| Cockpit interior (V struts, bar, sills, lamps, the console around its screens, a closed shell; M3-T29) | Mesh (`cockpit_interior.obj`), with 2D-only `SubViewport`s on screen meshes the hardpoints place (`CockpitScreens`, §15.9) | Hard edges at the near plane; visible only in first person. From inside, the `Hull` node draws the hull's OBJ with its canopy glass and window frames cleared, the view the cockpit was built around. |
| Thruster plumes, buoy beacons | Meshes, unshaded emissive, additive, animated per frame. A plume is a cone from the nozzle position along its `exhaust` axis (length, radius, alpha follow the level) plus a small core disc at the exit; no billboards | Per-frame intensity animation. Tied to the nozzle axis, so the plume reads as coming out of the nozzle from every camera. |
| Projectiles, muzzle flash | Meshes, unshaded emissive | Tiny, fast-moving, short-lived. |
| Far AI ships | One point each in the world's `FarDots` multimesh past `settings.far_ship_dot_m` (§17.10) | Every far ship together is one draw call. |
| Target bracket | 2D `Control` in the debug overlay | Screen-space UI. |
| Collision | `CollisionShape3D` primitives from hardpoints JSON | A handful of boxes and capsules, never the render mesh. |

### 7.2 Drawing order

1. Godot's Forward+ renderer draws the opaque meshes (hulls, chunks, buoys, the cockpit interior) with their depth.
2. Transparent meshes (canopy glass, thruster plumes, beacons, projectiles, flashes, running light markers, the star points) are drawn
   on top, depth-tested against the opaque pass, so an effect behind a hull is hidden by the hull's own depth and the glass shows the
   cabin glow through it.
3. Post: motion blur and lens flare (§7.5), then glow/bloom, tonemap. Keep glow modest so the star points do not bloom into blobs.

Every hull node is a `MeshInstance3D` child of its body, so it is drawn at the body's physics-interpolated pose like any other node.

The star field sits around the camera (`SkyFollower`, `top_level = true`), so it never parallaxes and never collides with the depth
of nearby meshes. Camera `near = 0.05 m` (cockpit), `far = 50 000 m`; Forward+ uses reverse-Z, so this range is fine.

### 7.3 Lighting

Hulls, buoys and debris are lit by the scene (M3-T21, Q23; PBR from M4-T30a), so each has a lit and a dark side that changes as it rolls.
The sky is not lit: stars and nebula are emitters.

**The surfaces.** Each hull surface is a PBR material from its four maps (§9): albedo (sRGB), tangent-space normals, occlusion,
roughness and metal packed as ORM, and emission (sRGB, at the surface's `emissive_strength`). A Starfury's hull is
`hull_livery.gdshader`, the same maps with the wing's livery layered in the shader; its glass is `hull_glass.gdshader`.

**Ambient.** `settings.ambient_level` (0.3) is the environment's ambient light, white, on every side, so the dark side of a hull stays
legible against the black sky; it applies live. Sky reflections are off, so the hulls keep the look they were approved with.

**Nothing on a hull lights anything else.** Windows, the buoy's lens, the nozzle throats and the Starfury's cabin glow are emissive
texels: they glow at no cost per ship and light nothing. Anything that must light its surroundings is an emitter (below).

**The 8 lights.** The scene holds exactly 8 lights, created once and never freed: `LightRig` owns the `KeyStar` (slot 0) and 7
`OmniLight3D` slots, a light budget the clustered renderer still wants at 500 ships. Things that give off light are `LightEmitter`
records, entered with `add_emitter`; each frame `LightPicker` (pure) keeps the 7 highest by

```
score = priority class * energy * range / distance to the camera^2    (closer than 1 m counts as 1 m; an incumbent counts 20 % more)
```

with classes player's own 16 > explosion 8 > muzzle flash 4 > nozzle 2 > cabin 1, and the rig copies position, colour, energy,
range and attenuation into the slots; an unused slot sits at energy 0. An emitter keeps its slot while it is picked, so a short
muzzle flash is never missed and a far explosion cannot push out the player's nozzles. The cabin lamp is an emitter in the rig only
while the cockpit interior is shown.

**Running lights (M3-T27, Q27).** Every ship has a port red marker on -X, a starboard green on +X and a top white, steady, at its `nav_lights`
hardpoints: `RunningLights`, one node per ship with three `MeshInstance3D`s, built once with the pool. A marker is one shared quad and one
material per colour (`assets/shaders/running_light_marker.gdshader`): additive, facing the camera, 0.1 m in radius and never under
`settings.running_light_min_px` on screen (1 px, M4-T28), all in the vertex shader, so it stays a point at several km with no work on the CPU. Past
the distance where the real disc is one pixel wide (about 70 m at 1080p) the footprint stays at the floor and the brightness falls by the inverse
square of distance, `(real_px / floor_px)^2`, so the light delivered is what the real disc would deliver and there is no jump at the crossover
(`RunningLightDimming` is the tested copy of that sum; there is no atmosphere to scatter a far light into a globe). It keeps its
centre's depth, so hulls in front of it hide it, and it hides with a parked or destroyed ship. The markers are all there is: the top lamp's glow is
the lens in the hull's emissive map, and it is on whether or not the markers are (M4-T31). `Ship.running_lights` holds the state; nothing per frame
reads it, and radar and AI contact lists never do.

The cabin glow stays on when a ship is dark. Outside it is the canopy glass's own dark red emission (`hull_glass.gdshader`, M4-T30b, Q36):
`settings.cabin_glow_level` 0.3 at the manifest's strength, seen within `settings.cabin_glow_view_m` 150 m and fading over the last 30 m. Inside, the
`cabin` emitter is red too, and dim; it stays in the rig only while the cockpit interior is shown.

The dark rule: `BrainFactory` sets `PilotBrain.flies_dark` from a behaviour's `"running_lights": "on" | "off"`, by default off for a ship on patrol
(`patrol`, `aggro`, `ai` with a `patrol` route) and on for every other. `AiPilotDriver` sets the ship's lights when it is given a brain, so a
pool ship starts as its new pilot wants, and turns them on in the tick of its first shot (Q27). Once a ship fires it has stopped hiding for the rest of that life, so it does not flicker as it breaks
off and comes back. In `combat_sandbox` the PATROL wave's five raiders start dark, by data. The player's toggle is a `UiCommand` edge (`Main`) or
`running_lights [on|off]`; `WingDirector` copies the player's state to its wing each tick, and a respawn puts them back on.

**Ship lights (M3-T22).** Every light is an emitter, so with any effect live the scene still holds exactly the rig's 8 `Light3D`
nodes. Main pod nozzles (`ThrusterVisuals`): one emitter each, 1.5 m out along the exhaust so it falls on the pod and strut, energy
from the smoothed plume level (0 at idle, 2.5 at full thrust), the plume's colour at display brightness, range 15 m; the player's
own are class 16. RCS and retro nozzles and bolts give none. A shot (`MuzzleFlash`): the flash owns one emitter for life, 1 m ahead of
the muzzle, in the competition for 60 ms per shot, so a shot allocates nothing. The explosion (`Explosion`): its old `OmniLight3D`
is now an emitter with the same curve (0 to 8 to 0 over 0.25 s, range 4 x radius), in the competition only while it shines. Emitters
follow their node's drawn pose each frame, so a rebase moves them with it. A ship that is parked, freed or out of the tree takes its
emitters out (`ThrusterVisuals` and `MuzzleFlash` watch the node's disable and exit), and the frame's pass puts them back when it
plays again (§17.21). Numbers: `src/rendering/emitter_curves.gd`.

Console: `state lights` (`picked`, `candidates`, `active`, `cost_us`).

### 7.4 Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| A hull's texture maps blur or shimmer up close (cockpit view of the nose) | low | The Starfury's normal map is at twice its atlas (4 096 px), the maps have mipmaps and anisotropic filtering; the look gates are the maintainer's (H). |
| GPU time at the 500 battle | low | Every copy of a hull instances; far ships are dots in one multimesh; the importer's levels of detail; the 3D at the window's full resolution (M4-T36 removed the splat-era tile cap; §17.15 adds resolution scaling if needed). |
| VRAM | low | The maps are VRAM compressed with mipmaps, one set per asset (about 105 MB for every hull together). |
| A Godot bump changes the importer | low | Versions pinned; CI runs `--import` and the asset tests headless. |

### 7.5 Lens flare and motion blur (M3-T25, Q23, Q26)

Two effects on the `WorldEnvironment`'s Compositor, in this order: `MotionBlurEffect`, then the lens flare (both
`POST_TRANSPARENT`, so the blur smears the stars and hulls but never the flare). The HUD and the console
are canvas layers drawn after the 3D scene and are never touched. `PostEffects` (a node of `SpaceEnvironment`) switches them from
`settings.lens_flare` (default on), `settings.motion_blur` (default off) and `settings.motion_blur_strength` (0-1, default 0.5), live,
and feeds them each frame. Console: `flare [on|off]`, `blur [on|off]`, provider `post`.

- **No haze (Q31).** The flare is a lens effect only: no veil, no broad lobes, no god rays, since space has nothing to scatter light (`SceneLensFlareEffect.SHADER_PATCHES`).
- **Star colour (Q30).** `data/star_systems.json` gives each `system_id` a star temperature; `StarColor` turns it into one colour for the flare and the key star's light (`SpaceEnvironment.set_star`).
- **Lens flare.** ARez's add-on (`addons/lens_effects/`, vendored unedited, `docs/third-party.md`) draws the sun disc, ghosts, an
  anamorphic streak (its god rays are patched out, Q31). It wants the sun's screen position from its own `world_environment.gd`; `PostEffects` sets
  `sun_position` and `sun_dir_sign` instead (`LensFlareAim`), from the key star's direction (`KeyStar`'s +Z, the way to the star).
  **Occlusion** is the add-on's: it treats depth 0 (reverse-Z far plane) as open sky, so a hull hides the flare because the hull
  mesh writes depth (§7.2). The add-on's shader `#include`s Godot's built-in `godot/scene_data_inc.glsl`, which a headless import cannot resolve (it caches an empty
  shader), so `SceneLensFlareEffect` (a thin subclass of ours) compiles it at start-up (`RuntimeShader`).
- **Motion blur.** An in-house compute effect, two passes (blur into a scratch image, copy back; Godot's colour buffer is not
  copy-readable). Hull pixels (depth above 0) blur by the velocity buffer Forward+ writes when an enabled effect has
  `needs_motion_vectors`. The buffer is zero for the sky and the stars (the star points write no depth or velocity), so pixels at depth 0 derive
  their motion from how far the camera turned since last frame (previous and current view and projection, rotation only: they
  are at infinity). That is what smears the stars on a fast turn; a far dot blurs like a star. A sky pixel never
  samples a hull pixel, so the hull's paint is not dragged across the stars. While `settings.motion_blur` is off the effect is disabled,
  so the renderer is not asked for motion vectors and nothing runs. **Rebase:** `World.rebased` calls `MotionBlurGate.note_rebase`;
  the next two frames get strength 0 (the previous-frame transforms the renderer holds are kilometres off), then the blur returns.
- Headless runs and the smoke runs have no `RenderingDevice`, so both effects do nothing there; `tests/integration/test_post_effects.gd`
  checks the wiring and the values the effects are given.

### 7.6 Anti-aliasing and motion vectors (M4-T38, Q59, Q60)

`settings.anti_aliasing` picks one of Godot's own modes for the 3D view: `off`, `fxaa`, `smaa` (the default), `msaa_2x`, `msaa_4x` or
`taa`. `AntiAliasing` (a node of `SpaceEnvironment`) applies it live to the viewport through `AntiAliasingMode` (pure: one mode sets
one of the viewport's `screen_space_aa`, `msaa_3d` and `use_taa`, so modes never stack). Console `aa [mode]`, provider `aa`.
Upscaling (FSR 1.0 and 2.2) is T40's.

**Why SMAA by default.** A look call that the costs allow, not a cost result: every mode but TAA costs well under a millisecond
more than `off` on the maintainer's RX 6950 XT, and the game is CPU-bound in every layout. With the 3D at the 6144x3456 window's own
size (scale 1, the machine's default) at `battle` 300, frozen-scene turns: off 2.83 ms, FXAA 2.99, SMAA 3.20, MSAA 2x 3.48, MSAA 4x
3.77, TAA 5.50 (the M4 Cycle log, M4-T38). SMAA smooths every edge the picture has (hull silhouettes, rocks, the shader-drawn panel
lines) where MSAA smooths only geometry edges; whether it looks better than FXAA on the panel lines and the stars is the
maintainer's call (H, on the return checklist). SMAA, TAA and MSAA each take VRAM for their buffers (at the full 6K: SMAA about
160 MB, TAA about 580 MB, MSAA 4x about 1.1 GB). TAA is offered, not defaulted: it costs the most GPU and 1 to 2 ms of CPU a frame, and
it softens thin moving things. With the 3D scaled down in a larger window (1 080 or 2 160 lines in the 6K window), `off`, MSAA and
TAA cost more than FXAA and SMAA: without a screen-space pass Godot composites the glow during the tonemap at the window's size;
with glow off the gap is gone (a control run, the Cycle log).

**Motion vectors (TAA, and T40's FSR 2.2).** Godot writes velocity only for opaque meshes. Measured with `VelocityProbeEffect`
(a diagnostic compositor effect that reads the velocity buffer back, used by `test_motion_vectors_gpu`):

- The sky, the star points and the far dots write no depth, so their pixels hold zero velocity. Under TAA a camera turn then blends
  each star with the dark sky it left, and the star field kept about a fifth of its light. `SkyVelocityEffect` (first on the
  Compositor, `POST_SKY`, on only under TAA) writes the camera's turn into every depth-0 pixel, the motion of a thing at infinity,
  without the TAA jitter (Godot's convention: the previous place minus the current one, in uv units). Far dots are kilometres out,
  so the turn is most of their motion too.
- Transparent meshes write no velocity: they inherit the pixel behind them. Large soft effects (plumes, the explosion's fireball,
  flashes) survive that, because TAA clamps the history to the current neighbourhood. A thin fast bolt does not: an additive bolt
  kept about 3 % of its light under TAA. So under TAA every bolt material draws opaque (`BoltMesh.set_motion_vectors`, also the
  player's node bolts through `Projectile.bolt_materials`), and a bolt writes its own vector. Over black space the opaque bolt looks
  the same as the additive one; over a hull it covers instead of adding.
- A multimesh instance's previous transform is whatever its slot held in the last drawn frame. A bolt that takes a slot that was
  empty gets a vector from the world origin (NaN when the camera is there); one that takes a slot freed since the last frame gets
  the old bolt's place (a 70 px smear in the test). `BoltSlotQuarantine` draws a bolt new to its slot collapsed at its own place for
  that one frame, so the slot is drawn empty before its new occupant shows and the first real vector starts where the bolt is.
  "New" means the basis changed or the bolt moved backwards along its flight (the same cannon's next shot). It costs one pass over
  the slots a frame, under TAA only. A World rebase, switching the bolt rows off and on, a grown buffer and a look drawn empty
  each start the slots afresh (every bolt drawn collapsed for one frame). A bolt material that is not a `BaseMaterial3D` stays as it
  is and warns once.
- Running lights, plumes, muzzle flashes, hit flashes, sparks, beams, missile bodies and the explosion stay transparent: they
  inherit the hull's or the sky's vector. A far dot gets only the camera's turn, not its own motion (a dot at 2 km crossing at
  300 m/s moves about 4 px a frame at 2 160 lines); TAA's clamp makes such a thing dim rather than ghost. None of these was measured
  moving; they are on the return checklist.
- **A rebase** shifts the camera and every hull together, so the renderer's own previous transforms stay consistent; the sky pass
  uses only the camera's turn; the bolts start afresh (above).
- **The motion blur** (§7.5) reads the velocity buffer for hulls and works out the sky's turn itself with the same sum, now also
  without the TAA jitter, so turning the sky pass on changes nothing it draws and a still camera under TAA does not blur the sky.
  It runs at `POST_TRANSPARENT`, before the TAA resolve, so the two never smear the same motion twice.

`scripts/aa_compare.sh` measures the modes against each other in one process (they take turns on a frozen or a live scene, so the
GPU's clock changes cancel) and saves a screenshot per mode.

### 7.7 Upscaling: FSR 1.0 and FSR 2.2 (M4-T40, Q59, Q60)

`settings.upscaler` picks how the 3D view is rendered and enlarged to the window: `native` (the window's own size, the default),
`bilinear`, `fsr1` (FSR 1.0, spatial, sharpened by `settings.fsr_sharpness`, Godot's scale: 0 the sharpest, 2 the softest) or `fsr2`
(FSR 2.2, temporal, its own anti-aliasing; Godot's built-in one, with no frame generation, so it adds no frames and no lag beyond its
compute). `settings.upscale_preset` picks the internal resolution as a share of the window's height: `native` 1.0, `quality` 1/1.5
(0.67, the default), `balanced` 1/1.7 (0.59), `performance` 0.5, `ultra_performance` 1/3 (0.33) or `custom`
(`settings.upscale_custom_scale`, 0.33 to 1). The ratios are AMD's, so a 2 160-line window renders whole lines (1 440, 1 080, 720).
The preset is ignored while the upscaler is `native`. `Upscaler` (a node of `SpaceEnvironment`, after `AntiAliasing`) applies them
live to the viewport's `scaling_3d_mode`, `scaling_3d_scale` and `fsr_sharpness` through `Upscaling` (pure). Console
`upscale [upscaler] [preset|scale]`, provider `upscale`.

- **The HUD and text** draw at the window's own pixels: the project sets no stretch mode, and the 3D scale changes only the 3D render
  buffers, so a one-pixel HUD line stays one window pixel wide with the 3D at a third (`test_upscaling_gpu`).
- **FSR 2.2 and the anti-aliasing setting.** Godot turns TAA off under FSR 2.2. `Upscaler` goes further and holds the whole
  anti-aliasing mode off while FSR 2.2 is on (FXAA, SMAA and MSAA would only blur or cost on top of its own anti-aliasing), keeps the
  setting as it was, shows the hold (`aa` says "held off while FSR 2.2 anti-aliases", provider `aa.held`), and gives the mode back
  when FSR 2.2 goes. Under FSR 2.2 the motion vectors stay on whatever the mode: the sky pass and the opaque bolts with their slot
  quarantine (§7.6), as under TAA. Bilinear and FSR 1.0 keep the anti-aliasing mode, applied at the internal resolution.
- **Why native by default (a measurement).** On the maintainer's RX 6950 XT the game draws a cheap scene (mostly black space), so
  FSR 2.2's own pass costs more than the pixels it saves: with the 3D at the 6144x3456 window's own size, frozen `battle` 300, native
  with SMAA takes 3.19 ms of GPU, FSR 2.2 Quality 5.86, Ultra Performance 4.46; in a 3840x2160 window native 1.27 and FSR 2.2 Quality
  2.27. Live at `battle` 300 FSR 2.2 lowers the average from 102 to 76 to 85 FPS and adds 210 to 1 770 MB of VRAM. FSR 1.0 and
  bilinear do save GPU (FSR 1.0 Quality 2.19 ms frozen, 3.28 live against 4.71), but the FPS gain is small because the frame is
  CPU-bound: +3 to +5 % in the in-process live round (native 119.0, bilinear Quality 123.1, FSR 1.0 Quality 124.7 FPS), not
  distinguishable from run-to-run noise in the single fullscreen runs. Whether FSR 1.0 Quality looks as good as native in a large
  window is the maintainer's call (H, on the return checklist). The full tables are in the M4 Cycle log, M4-T40.
- **The look.** Stars and far dots are single pixels at the internal resolution, so at Ultra Performance (FSR 1.0 or 2.2) they
  enlarge into soft blobs; at Quality they stay close to native. FSR 2.2 left no trail behind a moving point over black space, but it
  clamps its history so hard that a point without vectors left none either. A sub-pixel point (1.4 window pixels across, 6 pixels a
  frame) at half scale keeps its light under FSR 2.2 but spreads it: the light summed around it is 1.6 to 1.65 against the 1.56 a
  fully lit disc of its size gives, while its brightest pixel is only 0.25 to 0.39 of white (`test_upscaling_gpu`'s recorded
  measure, two runs), so small fast things such as far bolts read softer at low presets. No ghosting showed on the live screenshots; the look is on the return checklist. If FSR 2.2's
  ghosting proves unacceptable, FSR 3.1's upscaler (AMD's FidelityFX SDK, open source, Vulkan) in the native library is the fallback
  (Q60), still without frame generation.

`scripts/aa_compare.sh ... scale3d=setting upscalers=native,fsr1:quality,fsr2:quality` takes the same turns over upscalers, and
`FULLSCREEN_SCALE=setting` lets `scripts/fullscreen_check.sh` measure the upscaler settings, set through `FULLSCREEN_EXEC` (for
example `upscale fsr2 quality`) or a saved settings file. Until T40's fix round the measure tool dropped every `FULLSCREEN_EXEC` and
`RC_EXEC` statement, because `bench` holds the console until its run ends; it now runs them all at set-up
(`ConsoleRegistry.execute_all`), and its log prints the upscaler and anti-aliasing in use. A held scale (`1080p` or a number, the tools' default) is a bilinear stretch, as
before T40.

## 8. Camera

- **Cockpit**: `Camera3D` glued to `CockpitAnchor` (hardpoint) via `RemoteTransform3D`; FOV 75°. The pilot looks out of a built cabin (M3-T29, `docs/design-references.md`, the second
  cockpit reference, and `docs/assets-starfury.md`, "Cockpit view", for the numbers): slim red V struts landing on the sides of the octagonal display, a thin bar across the top, side panes
  past them down to low sills, and the console's three screens below. Nothing crosses the centre. Cockpit interior mesh visible, and the hull mesh with its canopy glass and window frames
  cleared. Instruments are on the screens (§15.9); the window keeps only what must line up with the world.
- **Chase**: `top_level` camera, **rigidly attached to the ship**. Every rendered frame `CameraRig._process` sets
  its transform to the ship's *physics-interpolated* global transform (`get_global_transform_interpolated()`) times
  one fixed ship-space pose from `ChaseCameraMath.local_pose`: position = the hardpoints' `chase_anchor` (behind and
  above; the Starfury's `(0, 4, 17)` frames its 15 m claw span, `Vector3(0, 2.5, 9.0)` is the fallback without
  hardpoints), looking at the point 40 m ahead of the ship's origin along its nose, up = ship up. There is no easing
  and no velocity input: reverse thrust, yaw and roll cannot move the camera relative to the ship (tested to float32
  round-off, 1.1e-5 of the offset's length, in every frame), and the camera follows *orientation*, so sideways drift and pod tank-steering are visible in the world,
  not as camera motion. A velocity-vector marker is a later HUD item. The camera node has physics interpolation
  off (it is already placed from the interpolated pose) and joins `world_shiftable`.
  Optional lag: setting `camera_chase_smoothing_s` (0..0.5 s, default **0** = exactly rigid) lags only the
  *orientation* of the camera frame behind the ship's with that time constant (first-order, frame-rate
  independent, slerp); the position stays `ship origin + frame * offset`, so the distance to the ship never changes.
- Modes are an enum (`COCKPIT`, `CHASE`, `CINEMATIC` since M5-T08 (§18 D55), which only a shot enters; `FREE_LOOK` later). Toggle via `toggle_camera`;
  `Settings.camera_default`. `CockpitInterior.visible == (mode == COCKPIT)`.
- Camera near/far as in §7.2. Physics interpolation on, so the chase camera's `_process` reads interpolated
  transforms (the hull meshes are drawn at the same pose, §7.2). The chase camera is in group
  `world_shiftable` because `top_level` nodes do not follow a parent.

## 9. Asset pipeline (`tools/procgen`)

All assets come from committed generator code (D17). Generators are deterministic (`--seed`, default 42),
CPU-only Python, and M1 assets build in seconds. M1 sets up the framework layout that later assets extend
(§14.8):

```
tools/__init__.py
tools/procgen/
  __init__.py
  __main__.py      CLI: python3 -m tools.procgen list | build <asset_id>... | build all  [--seed N] [--out DIR]
  core/            geometry.py (tessellation with UVs), sampling.py (surface samples), uv_atlas.py, raster.py, textures.py
                   (the maps), image.py (PNG), glb.py, textured_mesh.py (the writer), livery.py, chunks.py, pieces.py,
                   panorama.py, rotations.py, color.py, obj.py (OBJ/MTL writer), manifest.py, context.py (BuildContext)
  parts/           reusable parametric parts. M1: hull.py (box, tapered box, canopy), propulsion.py (pod, nozzle),
                   structure.py (strut, mast, panel), weapons.py (gun barrel)
  styles/          design languages as parameter sets. M1: earthforce.py (palette, panel density, stripe)
  assets/          one module per asset id exposing build(ctx) -> AssetOutputs; __init__.py holds the registry.
                   M1: starfury_aurora.py, nav_buoy.py, sky_default.py
  tests/           unittest for core, parts and every asset
```

Output contract: each asset writes to `assets/generated/<asset_id>/` (gitignored) and always includes
`manifest.json`:

```json
{"asset_id": "starfury_aurora", "generator_version": 9, "seed": 42, "frame": "godot", "units": "m",
 "aabb_min": [-7.3, -4.1, -8.4], "aabb_max": [7.3, 3.3, 8.7], "centroid_offset": [0.0, 0.1, 0.6],
 "files": {"obj": "starfury_aurora.obj", "mesh": "starfury_aurora.glb", "cockpit_mesh": "cockpit_interior.obj",
           "hardpoints": "hardpoints.json"},
 "dimensions_m": {...}, "chunks": ["cabin", "arm_ur", ...],
 "mesh": {"file": "starfury_aurora.glb", "triangles": 34428, "vertices": ..., "aabb_min": [...], "aabb_max": [...],
          "texel_m": ..., "atlas_px": 2048, "atlas_fill": ..., "mean_albedo": [...], "map_px": {...},
          "surfaces": [{"name": "hull", "blend": false, "albedo": "starfury_aurora_albedo.png", "normal": ..., "orm": ...,
                        "emissive": ..., "transmittance": 0.0, "emissive_strength": ...}, {"name": "glass", ...}],
          "lods": [], "livery": {...}}}
```

The `mesh` section is the contract M5 builds against (the M4 milestone, "The contract M5 builds against"; written by
`core.textured_mesh.write_textured_mesh`, validated by `core.manifest.validate_mesh_section`): one `.glb` in the Godot frame with
one UV set into the atlas, primitive 0 the opaque hull and primitive 1 the glass, and the four maps beside it, each with a Godot
`.import` sidecar the generator writes (VRAM compressed, mipmaps, the normal map flagged). `mesh.lods` is empty: the importer
builds the levels of detail. AABBs are in the Godot frame and bound the hull mesh; `centroid_offset` is what was subtracted from the
authored positions to centre the hull on its surface samples. A big stand-in (the station, the capital hulls) lists its pieces
(`pieces`, `classes`), each with its own `mesh`, `aabb_min` and `aabb_max` (`core/pieces.py`). A sound set (`kind: audio`) lists
`sounds` instead. The Starfury's and the raider's `hardpoints.json` `chunks[]` name each break-up chunk's OBJ and textured mesh
(`core/chunks.py`).

### 9.1 `starfury_aurora`

1. Parametric description in the Godot frame, metres, built from `parts/` with the `earthforce` style, following
   the SA-23E silhouette in `docs/design-references.md`: a faceted wedge fuselage (arrowhead from above) with the
   cockpit window in its nose, four trussed, swept struts in a wide X (18° off horizontal), four ring-faced pods
   (rear main nozzle, forward retro nozzle), a claw of splayed vanes behind each pod carrying the RCS nozzles, and a
   ventral twin-gun mount. Details and numbers: `docs/assets-starfury.md`.
2. Outputs:
   - `starfury_aurora.glb`, its four maps and the digit atlas (the textured mesh, §17.18; the livery table in the manifest).
   - `starfury_aurora.obj` + `.mtl` (the hull's OBJ: the cockpit view draws it from inside, and the chunks are cut from the same parts).
   - `cockpit_interior.obj`: the cabin seen from inside (`parts/cockpit.py`, M3-T29), nothing across the forward view; hard edges, faces toward the eye.
   - `hardpoints.json`: `screens` (M3-T29, §15.9: per screen `center`, `size`, `normal`, `up`, `corner`), `nav_lights` (M3-T27, §7.3: `port`, `starboard`, `top`, `top_lamp`, `cabin`, `top_lamp_range_m`, `cabin_range_m`; `raider_fighter` too), `center_of_mass`, `cockpit_camera`, `chase_anchor`, `muzzles[]`, `pods[]` (side, main and
     retro nozzle position + exhaust direction), `rcs[]` (cosmetic nozzle positions with effect tags for glow),
     `collision[]` (boxes/capsules). Schema in the M1 task T04.
   - Re-centre **everything** (meshes, hardpoints) on the centroid of the hull's surface samples (area-weighted stratified
     sampling at 4.7 cm, the faces the pilot sees up close finer), so the hardpoints frame equals the rendered frame. The same
     samples keep the running lights clear of the hull and place the break-up chunks.

### 9.2 `sky_default`

- Stars: N≈12 000 directions on a sphere of radius R=20 000 m; magnitude distribution ~ `10^(0.5·m)` with a Milky-Way band
  density boost; colour from a blackbody temperature table; brighter stars bigger and brighter. Written as
  `sky_default_stars.f32` (direction, tint, brightness per star), drawn as points (§17.19).
- Nebula: N≈4 000 large (300-2 000 m) soft blobs clustered by a few fBm-weighted groups in one sky region
  (~40° across), two-tone palette (e.g. teal/magenta), opacity 0.02-0.08, slight anisotropy for filaments; composited into
  `sky_default_panorama.png` (4096×2048 equirectangular, RGBA: the alpha dims the stars behind the gas) + manifest.

### 9.3 `nav_buoy`

- ~4 m tall body: cylinder hull, two small panel wings, antenna mast; `earthforce` palette with a hazard stripe and an
  amber lens under the beacon. Outputs the textured `nav_buoy.glb` and its maps, `nav_buoy.obj`, `hardpoints.json` (`beacon`
  position), manifest.

### 9.4 `planet` (M6-T11, D68)

- One asset per `PlanetSpec` in `tools/procgen/assets/planet.py`; the first is `epsilon_iii` (the show still described in
  `docs/design-references.md`, "Epsilon III"). Equirectangular maps from noise sampled on the unit sphere, so they are seamless
  at 0/360 degrees with no pinch at the poles: albedo (sRGB), height, tangent-space normal (red east, green north, relief
  exaggerated by `planet.normal_exaggeration`) at 4096x2048, and the wisp cover at 2048x1024, each with a VRAM-compressed,
  mipmapped `.import` sidecar. The manifest's `planet` section gives the layout (`uv`: u = 0 at the planet's +Z growing east
  toward +X, v = 0 at the north pole, +Y), the height range, the wisps' tint and the lit limb's haze tint
  (`atmosphere.limb_srgb`).
- In the game (`ScaledSpace`, D68): `PlanetLook` reads the manifest and the star system's `radius_m` and `atmosphere_top_m`.
  The planet's frame puts the maps' north on the ephemeris's z (the game's +Y) and u = 0 toward the ephemeris's +x; no tilt or
  spin yet (the data has none). `assets/shaders/scaled_planet.gdshader` draws the surface on a coarse 64x32 sphere pushed out
  just enough to enclose the true one, finds each pixel's point on the true sphere (a round limb at any distance), samples
  the maps with seam-safe gradients (anisotropic, mipmapped), lights the relief only where the sun is up, with a hard
  terminator and a near-black night side. `assets/shaders/scaled_atmosphere.gdshader` is a shell to the atmosphere's top,
  added over it: sunlit air along each view ray, so the lit limb gets a faint warm rim and glow and the night limb none.
  Both keep T10's pinned layer depth. A body without built maps keeps T10's plain stand-in, with a warning.
- `scripts/planet_sheet.sh` photographs the planet from the station's rail, a 400 km orbit, 1 000 and 10 000 km up for
  the look sheets.

### 9.5 Running

`scripts/gen_assets.sh` runs `python3 -m tools.procgen build all`. `scripts/run_tests.sh` first runs
`python3 -m unittest discover -s tools/procgen/tests -t .`. CI regenerates assets on every run (they are not
committed). A human opening the project in the editor runs `scripts/gen_assets.sh` once (Python 3.11+ and NumPy
are the only requirements).

## 10. Scale, units, world frame

1 unit = 1 m, SI. Ship ≈ 10 m long; M1 play area ≈ ±20 km (float32 error ≈ 2 mm there; fine). Sky radius 20 km
around the camera, independent of ship position. M1 already routes all world content through `World`
(`WorldFrame`): spawns take a `UniversePos` (64-bit) and are converted with `universe_to_local()` (not `to_local`, which would clash with Node3D's native method); `rebase(offset)` exists
and is tested. Automatic rebasing was off in M1 (threshold 0 = disabled, still the default of a bare `WorldFrame`) because
the M1 play area does not need it; since M3-T14 the main scene rebases at 5 km (maintainer Q13: far from the launch point,
float32 positions made the ship jump visibly).
The full large-world design is §14.1.

## 11. Performance targets (M1)

- 1920×1080, 60 fps sustained on the tester's Linux desktop (discrete Vulkan GPU); floor: GTX 1060 / RX 580 class.
- Physics 60 Hz fixed; `_physics_process` for the ship < 0.2 ms.
- Input-to-thrust latency: one physics tick after the input event.
- Startup to flyable < 5 s after import (the first import of the generated meshes and maps takes longer; a one-time cost).
- Many ships (M4): the tick budget for 100-500 ships (median ≤ 8 ms, p99 ≤ 12 ms headless at 60 Hz) and how it is
  measured are in `docs/milestones/m4-performance-and-scale.md`.
- The entity budget (M4-T25, the editor build headless, the tier on at 10 km): the usual mission (`typical`, 50 fighters and
  8 capitals with every weapon, 1 000 rocks and a moon) ticks in 1.9 ms; the grand battle (`battle`, 15 % capitals) holds the
  budget to 400 ships (6.6 ms) and is at the line at 500 (7.7 to 8.1 ms); 1 000 ships tick in 10.5 ms (11.0 at 20 % capitals)
  and keep real time. The tier carries the far share (580 of 850 fighters and 97 of 150 capitals at 1 000), so the cost grows
  by about 5 us a ship past 500. The milestone's Report P3 has the tables.
- The render bar (Q20, Q52): fullscreen at the panel's size with the 3D at 1 080 lines; at the headline battle the floor is
  30 FPS and the target 60, and the bar the maintainer judges is 60 FPS at the screen with vsync on (H). Measured through
  Wayland (M4-T25): the average holds 60 FPS to 1 000 ships (65 to 71 there), the 1 % low drops under 60 from about 500 and
  stays over 30 everywhere, and the GPU draws a frame in under 1 ms at every count, so the main thread binds. Through Wayland
  Godot paces frames to at most about 145 FPS (6.9 ms); through X11 `typical` runs at 314 FPS.

## 12. Testing strategy

| Level | Tool | Runs where | Covers |
|---|---|---|---|
| Python unit | `unittest` | container, CI | UV atlas, maps, PNG and glb writers, determinism (hash of output), hardpoints schema (pods, nozzles, CoM), centroid ≈ 0, the manifest's `mesh` section, CLI registry |
| GDScript unit | GUT `tests/unit` | container, CI | `FlightModel` (pod forces at positions, r × F signs per §5.2 table, zero pitch/roll from pods, trim maths, brake symmetry, clamps, mass flow), `FlightAssist` (pod-yaw sign, deadzone, frame-rate-independent smoothing, cap at `rate_max`, converges, never exceeds limits or triggers), `InputAdapter` (radial deadzone, expo, roll ramp, edges, invert-Y, command split), `TriggerCalibration` (rest 0 and -1), `ChaseCameraMath` (frame-rate independence), `PulseCannonGate` (modes, rates, cycling), `TargetingSystem` (next, ahead, readout), `UniversePos` (64-bit precision at 1e11 m), console (tokenizer, typed args and errors, help, history, completion, provider whitelist, owner pruning), `SettingsSchema` (types, ranges, session vs save) |
| Headless integration | GUT `tests/integration`, `--headless` | container, CI | ship scene instantiates; damping guard; pod-differential yaw measured in Jolt matches the model; assist turns at the pod-yaw rate under one trigger, stops on release, and flies straight inside the deadzone; brake; projectile velocity/lifetime; the textured meshes import with their materials and maps; `World.rebase` keeps velocities and relative positions; scenario spawns buoys; targeting with live buoys; `SkyFollower`; camera toggle; console masks keyboard but not pad, and every subsystem's provider answers `state`; `main.tscn` runs 180 frames without script errors; a `--console-exec` run prints the expected `[console]` lines and exits with the requested code |
| Human acceptance | checklist in the milestone doc | Linux/Vulkan GPU + generic XInput pad | hull appearance, compositing, feel, performance, controller behaviour, trigger/deadzone calibration, targeting |

Rules: every pure class gets unit tests in the same PR; every scene gets at least an instantiate-and-run test;
anything that depends on a GPU is marked `(H)` in acceptance criteria and is never faked in CI.

CI (M3-T12) runs GUT in three jobs (two until M4, when shard 1 reached the 45-minute job limit; the limit is now 60): `GUT_SHARD=k/n` makes `scripts/run_tests.sh` run every n-th GUT script from the k-th, in path
order, and shard 1 also runs the Python tests and the console smoke runs; locally, unset, it runs everything. Wall-clock budgets (AI
think time, resolver ticks, rebase cost) are asserted on the maintainer's machine and only recorded on CI (`CI=true`), through
`WallClockBudget` (`tests/fixtures/wall_clock_budget.gd`): a shared runner's clock says nothing about the game.

Commands (also in `scripts/run_tests.sh`):

```
python3 -m unittest discover -s tools/procgen/tests -t . -v
.tools/godot/godot --headless --path . --import
.tools/godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=reports/gut.xml
.tools/godot/godot --headless --path . -- --console-strict --console-exec="wait 30; state ship; get render.renderer; quit"
```

The slow files (M4-T36, Q58: `test_dogfight`, `test_m3_sandbox`, `test_brain_tolerance`, `test_flight_parity_fight`,
`test_weapon_rows_battle`) skip themselves unless `GUT_SLOW=1` (`tests/fixtures/slow_tests.gd`). `scripts/run_tests.sh` sets it
unless told otherwise and CI sets it, so the full run includes them; a direct GUT run as above leaves them out (GUT logs "Script
skipped"), so put `GUT_SLOW=1` in front of it for a complete run.

**Four tiers (M6-T17).** `scripts/run_tests.sh` takes `--quick`, `--standard` (the default and the merge gate), `--balance` or
`--full`. *Quick* (about 3.5 minutes) builds the native library, compiles every script, runs the Rust kernel tests, the Python modules
of `tests/quick_python.txt` and the GUT files of `tests/quick_suite.txt` with `GUT_SLOW=0 GUT_BALANCE=0`, and two console smokes; it
is for iteration, not a gate (`tests/unit/test_quick_suite.gd` keeps slow, balance and GPU files out of the list). *Standard* is
everything the script ran before plus `cargo test --release --lib`, with the slow files and without the balance tests. *Balance*
runs only the files of `tests/balance_suite.txt` with `GUT_BALANCE=1` (`tests/fixtures/balance_tests.gd`: `test_dogfight`'s six-minute
fight, `test_m3_sandbox`'s three waves, `test_turret_balance`); *full* is standard with the balance tests on. CI runs the standard tier.

**Shared test steps (M5-T38).** `tests/fixtures/test_steps.gd` (`TestSteps`, extends `GutTest`) holds the helpers scene tests used to
copy: `_ticks(n)` (n physics frames), `_exec(line)` (one console line) and `_console(line)` (the same, asserting a single
statement). A test file that needs them extends `TestSteps`; a file with a different `_ticks` (seconds in, ticks out) keeps its own
under another name. CI runs the Python tests in a job of their own (`PYTHON_TESTS=0` on the GUT shards) and both restore
`assets/generated` from a cache keyed on `hashFiles('tools/procgen/**')`. The smoke blocks of `run_tests.sh` go through
`main_run` (`scripts/lib_tests.sh`), and the lock files and their order are in `scripts/godot_lock.sh`.

## 13. Coding conventions

- GDScript 4, **statically typed everywhere** (`var x: float`, typed arrays, return types). Enable
  `debug/gdscript/warnings/untyped_declaration = error` and treat warnings as errors in CI
  (`--check-only` is per-file; the import step surfaces parse errors).
- One class per file, `class_name` in PascalCase matching the file name in snake_case
  (`flight_model.gd` -> `FlightModel`). Commit `.uid` files.
- Private members prefixed `_`. Constants `UPPER_SNAKE`. Signals are past-tense events (`assist_toggled`,
  `projectile_fired`, `target_changed`); connect in `_ready`, never in `_process`.
- Pure logic classes extend `RefCounted` and take plain data in/out. Nodes do not compute physics or parse input.
- No `get_node("../..")` upward reaches; parents pass dependencies down via exported `NodePath`s or setters.
- Physics in `_physics_process`, visuals in `_process`. Never apply forces from `_process`.
- Time comes from the `delta` argument or `SimClock`, never from `Time.get_ticks_*` or OS clocks (time warp
  later depends on it).
- Positions that may be far away (spawn points, waypoints, celestial bodies) are `UniversePos`, never `Vector3`.
  `Vector3` is for `World`-local positions only.
- Tunables live in `Resource`s (`ShipSpec`) or `Settings`, not as literals in node scripts. A new setting is a
  `SettingsSchema` entry (type, default, range), so the console can list, check and save it automatically.
- Every new subsystem registers its console commands and a state provider in `_ready` (owner = `self`, unregister
  in `_exit_tree`). Command names are `lower_snake`; keys are read-only unless writing them is useful; prefer a
  writable key over a new command. Never expose state by reflection.
- Comments explain *why*; the sign conventions in §5.2 are documented at the top of `flight_model.gd`.
- Python: `ruff`-clean (default rules), type hints, `argparse` CLI, `--seed`, pure functions; no Blender
  dependency; every asset module implements the `build(ctx) -> AssetOutputs` contract.
- Commits: imperative subject, task id prefix when applicable (`M1-T08: flight model and assist`).

## 14. Long-term architecture

Design for the user's vision (true-scale Epsilon system, Babylon 5 station, jumpgates, hyperspace, missions,
factions; see `docs/roadmap.md`). Nothing here is built in M1 except the seams listed in §14.9.

### 14.1 Coordinates and frames at solar-system scale

Verified for Godot 4.7.2 (details in `docs/research-notes.md`):
- No official double-precision binaries exist (`…4.7.2-stable_linux.x86_64.double.zip` -> 404). A double build
  means compiling the editor *and* export templates from source with `scons precision=double` (binaries get a
  `.double` suffix): feasible, but it adds a full engine toolchain and a long cached build to setup and CI.
- The Jolt module supports it (`modules/jolt_physics/SCsub` adds `JPH_DOUBLE_PRECISION` when `precision=double`).
- The GPU would not benefit: vertex positions and matrices reach it as float32 in any build, so large coordinates lose precision
  there unless every renderer path were camera-relative.
- Jolt clamps body speed at 500 m/s by default; orbital speeds near Epsilon III are several km/s. A moving local
  frame is needed whatever the precision.
- GDScript `float` is 64-bit in every build, so double-precision universe positions in script cost nothing.

**Decision:** official single-precision engine; no double build.
- `UniversePos`: 3 × 64-bit floats, metres, in the inertial frame of the current star system (barycentric), plus
  `system_id`. Never stored in `Vector3`.
- `WorldFrame` (the `World` node): the local Jolt/render space. **As built (M6, D64):** it has one **anchor**, a free-falling
  point in 64-bit (a place on a Kepler rail such as the station, or a test particle in orbit), and a `UniversePos` is relative
  to that anchor in axes that do not rotate (barycentric numbers live only in the ephemeris, so stored places never fall
  behind). The frame's origin rides the anchor and moves by position rebases; after a velocity rebase it falls freely itself.
  Either way local physics only feels the tidal residual `g(x) - g(anchor)`, so a ship near the orbiting station is effectively
  weightless, which is physically right. `SimClock` stays at 0 at the start; the World holds the scenario's epoch and
  `system_time()` = epoch + sim time is what the ephemeris is asked (§19.3, §19.6).
- **Position rebase** when the focus object is > 5 km from the local origin: every `world_shiftable` node moves
  by `-offset` (`global_translate`); `origin += offset`; interpolation is reset at the end of that tick (below). **On in play since M3-T14**
  (maintainer Q13: at 900 km a float32 coordinate steps in 6.25 cm, and the ship's hull jumped while thrusting):
  `main.tscn` sets `World.auto_rebase_distance_m` to 5 000 with the player as `focus`; a bare `WorldFrame` keeps 0.
  - Where in the tick: `World._physics_process` (priority 0; §15.3), after the AI drivers (-10), the console and `Main`,
    whose commands are levels and rates and stay valid, and before every node below `World` (ships, bolts, props, effects)
    and the late systems, which all see the new frame. Jolt's contacts of the last step are still in the old frame
    (`RamResolver` takes the rebase off them).
  - Rules: places that outlive a tick are `UniversePos` (wave anchors, waypoints, the wing's leader link, the HUD's
    reference point, the respawn point) or are rebuilt from the live nodes each tick (contacts, perceptions, targets,
    hit sweeps, slots). The two things a rebase cannot reach by itself listen to `World.rebased`: the cockpit pivot's
    interpolation (`Main`; it follows the ship through a `RemoteTransform3D`) and the points of open ram contact windows
    (`RamTracker.shift`). Parked pool ships and debris are shifted
    with the rest (harmless: they are placed again from a `UniversePos` when taken out). Particles stay in their node's
    frame (`local_coords`), never in global space, or a rebase would leave them behind (the explosion's sparks; since M3-T23 the `FxPool`'s emitters, which are `top_level` and `world_shiftable`).
  - Physics interpolation: **the world stalls together for the rebase tick.** A rebase inside a tick leaves interpolation
    alone; `World`'s internal `RebaseSettler` (physics priority 1 000 000, last in the tick, §15.3) then resets every visible,
    interpolated shiftable node, after everything has moved. The frames until the next tick draw every body, bolt, piece of
    debris, effect and both cameras at their tick pose, unblended: nothing blends across the jump, view-relative motion is
    kept (a bolt beside the ship stays beside it), and the HUD, which projects tick positions, matches what is drawn. The
    cost is at most one tick of held motion per rebase (one repeated frame; AC22 (H)). Hidden (parked) nodes and silent
    voices are skipped (`acquire`, `launch`, `play` reset them when they come back); a rebase outside a tick (the console
    between frames) resets at once. Measured at 5 000 m/s through a 5 km rebase (`test_rebase_in_play`, per rendered frame):
    resetting at the rebase itself (the first M3-T14 build) drew the bodies held while bolts and debris blended on, so a
    bolt's offset from the ship jumped 83 m off its motion in the frames of the rebase tick; not resetting at all draws
    everything sweeping by the offset over that tick (view-relative motion exact), but the HUD's markers through the chase
    camera were then 3.4 km off what is drawn (and the sky in the cockpit view, and anything spawned in that tick, would be
    too), so that was rejected. Now: 0.001 m and 0.000 m.
  - Cost: one rebase of the full sandbox (the player and 10 pooled ships, 20 parked debris chunks, 16 sound voices, 5 buoys
    and the chase camera: 53 nodes, plus bolts and effects in flight) costs about 0.28-0.30 ms idle (the median of a fight's
    rebases, from run to run; min about 0.12 ms, wall-clock spikes to about 0.6 ms), the shift, the `rebased` handlers and
    the end-of-tick reset together; the ships dominate it (a Starfury is 108 nodes, which the shift and the reset both walk).
    `world.rebases` and `world.rebase_us` watch it. Tests: `tests/integration/test_rebase_in_play.gd` and the `RebaseFight`
    fixture (`tests/fixtures/rebase_fight.gd`), which runs any live scene with the threshold forced low.
- **Velocity rebase** (on since M6-T05/T08, as built in §19.3): when the focus speed against the frame passes 2 000 m/s
  (`World.auto_boost_speed_mps`; Q8 chose 2 000 over this section's first draft of 200 because the frame rides its anchor below it)
  the frame is boosted onto the focus: `dv` comes off every body's `linear_velocity`, every core row, bolt and projectile,
  and `origin_velocity += dv`. The frame is then off its anchor and falls freely; back under 1 000 m/s it is boosted back onto
  the anchor and rides again. The boost is taken at the end of the tick and moves no position. Keeps Jolt well under its cap and
  float32 velocities small.
- Local space radius ~10 km. Anything farther (planets, sun, distant ships and stations) is not in Jolt: it is
  propagated in universe coordinates and rendered in scaled space (§14.4). B5's ~8 km length fits: at ±8 km
  float32 resolution is ~1 mm.

### 14.2 Gravity

**Decision:** celestial bodies (sun, planets, moons) move on analytic Kepler orbits ("on rails", deterministic,
seekable in time). Ships, projectiles, debris and (later) comets are massless test particles. No patched
conics for actual motion: sphere-of-influence switching makes flybys discontinuous. Patched conics may still be used for UI orbit previews.

**As built (M6, D66, §19.4): not a full n-body sum.** The maintainer chose that **only the strongest body inside its zone pulls**
(2026-11-10). A body's zone is the radius where its pull is at least `a_min` (0.5 m/s^2 in `data/star_systems.json`; 18 300 km
for Epsilon III), and the pull eases to zero over the outer fifth, so crossing a zone's edge is no jolt. Outside every zone nothing
pulls, inside a moon's zone the moon takes over from its planet, and nothing smaller than a moon pulls (`CLAUDE.md`). The star
does not pull near a planet: the frame falls with it. The n-body sum (`gravity::tidal`) stays in the kernel for tests only.

Coexistence with Jolt: project gravity stays 0 forever. Each tick every mover gets the residual `g(x_mover) - g(x_anchor)`
(off the anchor, `g(x_mover) - g(x_origin)`), taken from the tick's one sample of the frame (`frame.rs`), applied as a central
force on a ship, as an added velocity on a tier row or bolt (`bolt_kernels::advance`, `tier::step`) and through `HeldPull` on
debris, wrecks, explosions and projectile nodes. The brake and the AI's idle hold receive the residual as feed-forward
(`env_accel_b`). `WorldFrame.environment_accel` is that residual alone (the World's own field and M4's `GravityStandin` are
gone). Babylon 5's orbit (27 500 km, a pull of 0.22 m/s^2) is outside Epsilon III's zone, so the space around the station has no
pull; gravity is felt closer in. Expectation to communicate to
players: a solar flyby alone does not add heliocentric energy (that is physics); gains come from an Oberth burn at
perihelion or from flybys of moving planets (M9), and the sim does both correctly because it is honest.

### 14.3 Time acceleration

- `SimClock` owns sim time (64-bit seconds since epoch) and `warp`. Two regimes, KSP-style:
  - **Physics warp**, 2× and 4× only: Jolt keeps stepping at 60 Hz sim time with more steps per frame; controls
    stay live and thrust is allowed. It stays low because Jolt and the flight model are tuned for 60 Hz steps.
  - **On-rails warp**, 10×, 100×, 1 000×, 10 000× and 100 000× (cap ≈ 100 000×, configurable), only while
    coasting: no thrust input, no hostiles nearby. Jolt bodies are frozen; every ship is propagated by the gravity
    integrator (symplectic leapfrog, adaptive substeps bounded by the local gravity gradient). One 100 000× frame
    is ≈ 1 670 s of sim time, which is cheap for tens of ships. No collisions. At the cap, 1 AU at 30 km/s takes
    ≈ 50 s of real time.
- Entry rules: on-rails warp is refused while thrusting, with a hostile within 50 km or any AI in a combat state,
  during scripted mission sequences, and above a per-body altitude band's limit (the closer to a body, the lower the
  highest allowed level, as in KSP).
- **Automatic drop-back** when anything interesting happens: thrust or weapon input (straight to 1×), a hostile
  or unknown contact entering sensor range, a comms/dialog event or mission trigger, a proximity or
  collision-course alarm, crossing into a lower altitude band, arriving at a target or waypoint. Events are
  predicted: each frame the propagator looks ahead several warp steps and steps the warp down early enough that
  the event happens at 1×, so nothing (a periapsis, an encounter, a gate) is overshot at 100 000×.
- Leaving warp: the `WorldFrame` re-centres on the player, nearby objects are re-materialised from universe state
  into Jolt bodies.

### 14.4 Far-field rendering and LOD ("model blurring")

Decisions (M4-T31: the hulls are textured meshes, §7):
- Every hull mesh gets its levels of detail from Godot's scene importer (the manifest's `mesh.lods` stays empty; M4-T30d measured
  that a generated far level has nothing to win at the 500 battle). The importer's levels switch by screen size inside the renderer,
  with no node of ours.
- Past `settings.far_ship_dot_m` (3 km) an AI ship is a **far dot** (§17.10): its hull, plumes and markers hidden and one point in
  the world's `FarDots` multimesh drawn instead, sized by its angular size with a 1-px floor, so ships stay visible as dots (the
  user's model blurring). A `LodSwitcher` per ship decides with hysteresis (back a tenth inside).
- Objects beyond the near field need not be resident at all, only their far representation; paging them in and out is later
  (the low-attention tier, §17.14, is the first step).
- **Scaled space** for the sun, Epsilon III, moons and anything beyond ~50 km: **as built (M6-T10, D68, §19.8)** not a separate
  camera or viewport but a layer of stand-in spheres in the near world's own pass, a few km from the camera at the body's true
  angular size, each pixel's depth pinned in the vertex shader to a slab in front of the far plane (a SubViewport cost 221 MB more
  at 3200x1800), lit from the true sun direction. Planets and the sun are procedural-shader meshes (sphere + atmosphere scattering + generated
  textures), because they are huge smooth bodies needing day/night lighting and limb effects; their near-field
  features (cloud layers, rings, belts) get their own meshes or particles.
- The starfield stays camera-relative (one per star system, generated).
- **Big props (M6-T15, D70, §19.9):** the jumpgate and the station's stand-in keep their own meshes out to the far plane (less their
  radius and 500 m), then are drawn shrunk toward the eye (the same angle, a continuous hand-off), and become a far dot once their
  bounding radius is under 4 px (`FarPropMath.DOT_PX`; the dot's size comes from a silhouette table the generators write). The
  planet hands over to the same dot when its disc is under 4 px. M4's rule (the 1 px floor, the square dimming, a tenth of
  hysteresis) is kept.

### 14.5 Hyperspace

A separate `Space` with its own `WorldFrame`, scene and environment, entered through jumpgates (or a capital
ship's jump engine later). It has no celestial gravity; instead the space provides `environment_accel`:
- **Gravitational incline**: a field that pulls ships away from the beacon lane, growing with distance from it;
  flying hyperspace means constantly working against it.
- **Currents**: a spatially varying flow field that accelerates ships toward the local flow velocity.
- **Beacons**: navigation nodes with lock range. Lose lock and you drift: a mission-failure condition and a
  gameplay hazard.

Same ship, same `FlightModel`; only the environment differs, which is exactly the D18 hook. Mapping between normal
and hyperspace positions is a per-system scale table (hyperspace distances are shorter). Rendered with red/orange
volumetric shaders and a shader backdrop. Combat in hyperspace reuses everything.

### 14.6 Scenes and the mission framework

- `Game` autoload state machine: `FrontEnd -> Loading -> InSpace(scenario) -> Debrief`. The front end is UI over a
  generated Babylon 5 interior scene (slow camera); mission select or free flight (encounters on/off).
- **Scenario** = data (`data/scenarios/*.json`: spawns in `UniversePos`, actors, factions, start state such as
  "in launch bay 3") + an optional **mission script** in GDScript with a small coroutine API: `await say(speaker,
  text)`, `await until(condition)`, `spawn(...)`, `objective_add/complete(...)`, `waypoint(...)`,
  `cinematic(path)`, `lock_controls(bool)`, `await player_did("roll_right")` (tutorial checks per DOF).
- **Triggers**: proximity/area, timer, target destroyed/disabled, dialog finished, input performed, actor
  arrived. **Objectives** with success/fail states feed the debrief.
- **Launch bays**: station hardpoints with a launch rail; the launch is a scripted state with a `CINEMATIC`
  camera mode (Path3D + look-at), then hand-off to the player with the bay's velocity.
- **Dialog**: subtitles + comms panel first (M5, used by the M8 tutorial). Voiced dialog comes later from an
  offline TTS generator run on the user's machine (candidate: Piper, see `docs/third-party.md`). Voices are produced
  by code, so they satisfy the procedural-only rule; generated audio stays out of git like every other generated
  asset. Dialog lines are data (speaker, text, voice id), so adding voices changes no mission scripts.
- M1 seam: the free-flight scene is already driven by `data/scenarios/free_flight.json` through `ScenarioLoader`.
- **As built (M6-T09, §19.6):** a scenario names its place in the system with `anchor` (the station's rail with `at` the station's
  position in the scenario's coordinates, a body and altitude, or any orbit) and its `epoch` (system seconds, or `"seeded"`).

### 14.7 AI, allies, towing, capital ships

- `AiPilot` = pure brain (`RefCounted`) + node adapter. Input: a perception snapshot (targeting candidates with
  faction relations, own state, orders). Output: `FlightCommand` + `CombatCommand`, the same interface as the
  player, so AI obeys the same physics and limits. Behaviours are utility-scored: attack, evade, escort, formation,
  follow path (the instructor's tour), guard, flee; Newtonian intercept maths shared with a future lead reticle.
- Factions and a relations table (Earth Alliance, raiders, Earthforce renegades, Narn, Centauri, Minbari, Drazi
  and other non-aligned worlds, Shadows, Vorlons). M1 seam: `TargetInfo.faction`.
- **Towing**: a custom tether force (spring-damper with rest length, max length and breaking strain, applied at
  hardpoints on both bodies), not a Jolt joint: robust under frame rebases and large mass ratios. A "tow" assist
  mode in `FlightAssist` damps oscillation.
- **Capital ships and stations**: `RigidBody3D` with large mass (stations: kinematic in the free-falling frame),
  compound collision generated from parts, turrets as child nodes with AI gunners, subsystem damage. B5: a
  non-rotating hub with docking/launch bays and a rotating drum as a separate `AnimatableBody3D`; defense-grid
  emplacements as hardpoints the tour can point out.

### 14.8 Procedural asset framework

`tools/procgen` (§9) grows, it is not rewritten:
- **core**: the textured mesh writer (M4-T30a: UV atlas, the four maps, the glb) is the one exporter every asset uses; add SDF
  sampling, impostor and scaled-space texture bakers, a generated far level where one earns its place, a collision builder
  (convex pieces from parts).
- **parts**: hard-surface library (hull sections, panels, greebles, nozzles, trusses, docking bays, turrets,
  rotating drums, solar panels) and organic library (SDF/metaball and spline-swept bodies, noise surface detail)
  for Shadow and Vorlon designs.
- **styles**: one design language per faction as a parameter set: palette, panel density, curvature, symmetry,
  greeble set, surface finish. View-dependent sheen (a shader layer over the maps, as the liveries are) for Vorlon and
  Shadow iridescence.
- **assets**: parametric families, not one-offs: `starfury_aurora`, `starfury_thunderbolt`, `raider_fighter`,
  `raider_control_ship`, faction fighters and capitals, `babylon5_station` (~8 km, hub + rotating drum + bays +
  defense grid), `jumpgate`, planets (shader parameters + generated textures), `asteroid_field` (noise-displaced
  bodies), `comet` (nucleus + coma/tail volumetric shading), interiors (front-end B5 interior), per-system skies,
  and later voice lines rendered from dialog data by an offline TTS tool.
- Every asset emits the same contract: the textured mesh and its maps, the OBJ, collision primitives, hardpoints, manifest. Large
  assets (the station) may take minutes, so CI caches outputs keyed by a hash of the generator sources and seed.
  Outputs stay out of git (D9).

### 14.9 Seams already in M1 (and what is deliberately not)

Built in M1 because each is cheap and avoids a later rewrite:

| Seam | M1 task | Avoids later |
|---|---|---|
| `UniversePos` + `World`/`WorldFrame` parent for all world objects, `rebase()` tested, auto-rebase off (on in play since M3-T14, §14.1) | T09 | Re-parenting every scene and auditing raw `Vector3` positions when large worlds arrive |
| `World.environment_accel()` applied by the Ship each tick (returns zero); `env_accel_b` feed-forward in the brake | T08, T10 | Retrofitting gravity and hyperspace fields into the flight path |
| `SimClock` autoload; rule: no wall-clock time in gameplay | T01 | Hunting timers when time warp lands |
| Flight/Combat/Ui command split | T06 | Untangling player-only input from what AI pilots write |
| `TargetInfo.faction` | T14 | Changing the targeting data model for IFF, allies and enemies |
| `ShipSpec` per ship class with `asset_id`; `mass_flow` in `FlightOutput` (unlimited reaction mass) | T08, T10 | Ship-class hard-coding (Thunderbolt) and a flight-model change for finite fuel |
| Scenario JSON for free flight, spawns in universe coordinates | T14, T15 | A second spawn path when the mission framework arrives |
| `tools/procgen` framework layout, per-asset output dirs (the manifest's `lods` array was the seam until T31 removed it; `mesh.lods` stays empty, Q45, and its validator stays for M6's generated far levels) | T02, T04 | Moving files and rewriting import paths for every later asset |
| Camera mode enum | T12 | Reworking the rig for cinematic and free-look modes |
| Debug console registry, whitelisted state providers, `debug.invulnerable` flag | T07 (+ each subsystem's task) | Bolting debug tooling onto every subsystem later; M2 hull damage only has to read the flag |

Deliberately **not** seams in M1, because they cannot be made cheap: the moving (velocity-rebased) frame and tidal
gravity (§14.1-14.2), on-rails warp (§14.3), the LOD/scaled-space render layers (§14.4) and the hyperspace space
(§14.5). Each is its own roadmap milestone.

## 15. Combat sandbox (M2)

What M2 adds to §1-§13 (tasks in `docs/milestones/m2-combat-sandbox.md`). Every M1 rule still holds; this section
only lists what is new. Task ids below are M2 tasks.

### 15.1 Decisions

| # | Decision | Rationale (short) |
|---|---|---|
| D20 | Raiders are ordinary `Ship`s (RigidBody3D, `FlightModel`, assist always on, same limits) driven by a `PilotBrain` that writes `FlightCommand` + `CombatCommand`. No kinematic path followers | It is the M3 seam (§14.7): AI obeys the player's physics, and targeting, hits, HUD and destruction have one code path |
| D21 | Projectile hits: one `HitResolver` sweeps each bolt's last tick against each hostile target **in that target's frame** (relative motion): segment vs. bounding sphere, then vs. the target's hardpoints `collision` primitives inflated by the bolt's hit radius. Pure script maths, not Jolt queries | Exact for straight-line relative motion at any closing speed (1 400 m/s is 23 m per tick against hulls about 1 m thick); independent of when Jolt moves the target; rebase-safe, because a bolt stores its last displacement rather than a position; unit-testable; bounded cost (64 bolts × 8 targets of broadphase is well under 1 ms) |
| D22 | No pooled entity enters or leaves the tree during play. Raiders, allies and debris chunks are built at scenario load and switched by visibility (M4-T31: the reason is node churn, not a renderer) | A spawn mid-fight builds nodes, a body and its shapes and reads hardpoints, so it would hitch; a visibility change costs next to nothing. The M2 renderer re-merged all of its data on every register, which made this rule; it outlived that renderer |
| D23 | Damage model: hull points only. No shields (Starfuries and Delta-Vs have none), no subsystems, no collision damage. Bolt damage comes from `WeaponSpec`, hull from `ShipSpec`. `debug.invulnerable` zeroes damage on `Damageable`s with `respects_god_mode` (the player) | Smallest model that gives kills and deaths. Subsystems are M12, ram damage M3 |
| D24 | Destruction = a code-generated explosion (shader, particles, light: meshes) + break-up into the asset's generated `chunks` (pooled chunks, one-shot chunks once the pool is used up; each draws its textured mesh, cut from the hull on the hull's maps, M4-T30d). Debris drifts and spins kinematically, no collisions | Reuses the hull's own look, causes no node churn, stays procedural |
| D25 | Factions: `earth_alliance`, `raiders`, `neutral`, with a fixed rule in `Factions` (M3 turns it into data). Bolts hit only hostiles and never their shooter. `target_next` cycles hostiles first (nearest first), then the rest | Enough IFF for one enemy faction. Hostile-first cycling needs no new button, and the maintainer's pad has none free |
| D26 | The HUD is its own CanvasLayer drawn from a pure `HudLayout` that projects with the camera's matrices (tested against `Camera3D.unproject_position`) | Layout is unit-testable; the debug overlay stays a debug tool |
| D27 | Only the player's components register console providers (`ship`, `targeting`, `weapons`, `hull`) and `assist`. Other ships appear in aggregate providers (`raiders`) | The registry replaces entries by name, so per-ship registration would overwrite the player's entries and drop them when that ship is freed |
| D28 | Control profiles: named binding sets in `user://controls/<name>.cfg`, applied to `InputMap` at run time; `default` is the `project.godot` map and cannot be overwritten | `GodotInputSource` already reads `InputMap` events on every poll, so switching needs no input-layer change |
| D29 | Sound (T12, may slip to M3): `tools/procgen` synthesises WAVs with NumPy (asset kind `audio`); `AudioDirector` plays them through a pooled set of `AudioStreamPlayer3D`s. Space is audible, as in the show | Procedural-only rule; no new dependency (`wave` is in the standard library) |

### 15.2 Layout additions

```
src/combat/factions.gd            RefCounted, pure: faction ids, relation rule, HUD colours
src/combat/hull_health.gd         RefCounted, pure: hull points; destroyed reported exactly once
src/combat/sweep_math.gd          RefCounted, pure statics: segment vs. sphere / box / capsule -> entry fraction
src/combat/hit_shape.gd           RefCounted: one hit volume (box | capsule, body-frame transform) from Hardpoints.collision
src/combat/hit_info.gd            RefCounted: one resolved hit (target, shooter, faction, damage, point, normal, rel. speed)
src/combat/intercept_math.gd      RefCounted, pure: lead solution for bolts that inherit the shooter's velocity (HUD, AI)
src/combat/damageable.gd          Node component, group "damageable": HullHealth + HitShapes, signals
src/combat/hit_resolver.gd        Node: per-tick swept hits, damage, impact flashes; console `combat`, `damage`, `heal`
src/combat/impact_flash.gd        short additive flash, one pooled node on the hit ship at the hit point (sparks: FxPool; §17.21)
src/combat/explosion.tscn|.gd     generated explosion (fireball shader, light emitter since M3-T22; its sparks come from the FxPool since M3-T23); drifts, self-frees
src/combat/explosion_fireball.gdshader
src/combat/debris_chunk.tscn|.gd  one chunk: its textured mesh (the OBJ for an entry without one)
src/combat/debris_pool.gd         Node: pooled chunk sets, one-shot chunks and generic shards; drift, spin, shrink-out
src/combat/destruction_director.gd  Node: Damageable.destroyed -> explosion, debris, park the raider / respawn the player
src/weapons/weapon_spec.gd        Resource: muzzle speed, shot interval, damage, lifetime, hit radius, bolt look
src/ai/pilot_brain.gd             RefCounted base: think(Perception, dt) -> PilotCommand; M3's AiPilot extends it
src/ai/perception.gd              RefCounted: one tick's snapshot for a brain
src/ai/pilot_steering.gd          RefCounted, pure: face a direction, seek a velocity -> FlightCommand fields
src/ai/{idle,patrol,attack,aggro}_brain.gd, src/ai/brain_factory.gd   M2 behaviours; scenario dict -> brain
src/ai/raider_tactics.gd          Resource: attack thresholds (ranges, cone, speeds, timings); assets/ai/raider_tactics.tres
src/ai/ai_pilot_driver.gd         Node under an AI ship (physics priority -10): Perception -> brain -> Combatant
src/game/combatant.gd             RefCounted handle: ship, cannon, thrusters, targetable, damageable, driver; apply_commands
src/game/ship_assembly.gd         RefCounted statics: builds a player or AI Combatant from a ShipSpec
src/game/ship_catalog.gd          RefCounted: scenario ship type -> ShipSpec path
src/game/ship_pool.gd             Node: pooled Combatants (D22); acquire at a UniversePos, release
src/game/wave_plan.gd             RefCounted, pure: wave state machine
src/game/wave_director.gd         Node: runs the WavePlan, spawns from the pool, counts kills; console `wave`, `spawn`
src/hud/hud.tscn|.gd              CanvasLayer 40 (below the overlay's 50): draws a HudFrame
src/hud/hud_layout.gd, hud_frame.gd   RefCounted, pure: projection and every HUD element's screen state
src/hud/hud_surface.gd            RefCounted: one surface the HUD draws on and where each instrument goes on it; HudFrame extends it (M3-T29)
src/hud/hud_painter.gd            RefCounted: the one set of drawing code, for the 2D layer and each console screen (M3-T29)
src/hud/cockpit_screens.gd        Node3D: the player's console screens and indicator lamps (M3-T29)
src/input/control_profile.gd      RefCounted, pure: bindings <-> InputMap <-> config text, validation
src/input/control_profile_store.gd RefCounted: built-in and user profiles; list, load, save, delete
src/autoload/control_profiles.gd  Node (autoload): applies the selected profile at start-up; console `controls`, `bind`, `unbind`
data/controls/m1_classic.cfg      built-in profile: the original M1 pad layout (stick yaw, D-pad roll, D-pad Up targets, B assist)
src/audio/audio_director.gd       Node: pooled 3D players, engine hum, volume (T12)
assets/ships/raider_delta_v.tres, assets/weapons/{pulse_cannon_ef,raider_plasma}.tres
data/scenarios/combat_sandbox.json
tools/procgen/assets/raider_fighter.py, styles/raider.py, parts/wing.py, core/chunks.py   (T04)
tools/procgen/assets/sfx_combat.py, core/audio.py                                        (T12)
```

Main scene additions (pausable, like `World`):

```
Main
├── World
│   ├── PlayerShip (+ ThrusterVisuals, PulseCannon, Targetable, Damageable)   built by ShipAssembly
│   ├── Ships (ShipPool)          pooled raiders, each with an AiPilotDriver
│   ├── Effects                   explosions (impact flashes ride on the hit ship)
│   └── Debris (DebrisPool)
├── Combat (Node, PROCESS_MODE_PAUSABLE)
│   ├── HitResolver   ├── DestructionDirector   └── WaveDirector
├── AudioDirector (T12)
└── Hud (CanvasLayer 40)
```

### 15.3 Tick order and data flow

Superseded for M4 and later by §17.13's sync points (the brain batch at -9, the stand-ins at -5, the flight batch at -1,
`SimCoreStep`, `SimCoreOut`) and T24's threaded step; this section keeps M1's order as history.

One physics tick, in order (`process_physics_priority`, then tree order):

1. `AiPilotDriver`s (-10): build a `Perception`, call the brain, `Combatant.apply_commands(flight, combat)`.
   Commands are levels and rates, never positions, so a later rebase in the same tick cannot stale them.
1b. `BrainBatch` (-9; M4-T24, `sim_step`): on the native path the AI step is a job over a snapshot of the core's rows
   (`SimCore` synced them at -11). With `threaded` (the default) or `delayed`, the batch first joins the previous tick's
   job and hands over its results (the commands into the rows, which the flight batch flies at -1; the events to the
   drivers that joined then), then launches this tick's job, on the step's worker thread when threaded. Every AI
   command therefore lands one tick after the rows it was decided on; the player's own command (3) is never behind. Until
   M4-T37 an `inline` schedule thought and applied in the same call (§17.13, "The AI step on a worker thread").
2. `DebugConsole` statements (autoload, so first among the priority-0 nodes; a `rebase` here moves everything
   together).
3. `Main` (0): player `PilotCommand` -> `Combatant.apply_commands` (the same call).
3b. `World` (0, `Main`'s child, so after it and before every node below it; M3-T14): the automatic position rebase when
   the player is more than 5 km from the local origin (§14.1). Commands built before it are levels and rates and stay
   valid; everything after it in the tick works in the new frame.
4. Ships (0): flight model and forces; their `PulseCannon`s spawn bolts (`last_step = 0`).
5. Projectiles (0): move, record `last_step = velocity * delta`, expire.
6. `TargetingController`s (100): the player's refreshes its candidate list (inactive targetables skipped); an AI ship's checks its one selection (§17.2).
7. `HitResolver` (200): sweep, damage, impact flashes. `destroyed` -> `DestructionDirector`, which hides and
   disables the ship in the same tick, so nothing targets or hits it afterwards.
8. `WaveDirector` (300): count the dead, spawn from the pool.
8b. `World`'s `RebaseSettler` (1 000 000, last; M3-T14): in a tick with a rebase, resets the interpolation of every visible
   shiftable node, so that tick is drawn held, all together (§14.1).
9. Jolt steps the bodies.

```
PilotBrain <-Perception- AiPilotDriver --+          InputAdapter (player) --+
                                         +--> Combatant.apply_commands <----+
                                               |- Ship (FlightModel) -> Jolt
                                               |- PulseCannon (WeaponSpec) -> Projectile (shooter, faction, damage, last_step)
                                               '- TargetingController (hostile first)
Projectiles + active Damageables -> HitResolver (SweepMath) -> Damageable.apply_hit -> hit_taken / damaged / destroyed
destroyed -> DestructionDirector -> Explosion, DebrisPool, ShipPool.release | player respawn -> WaveDirector
player ship + selected target + active camera -> HudLayout (InterceptMath) -> Hud
```

### 15.4 Hull and damage

- `HullHealth`: `max_hp`, `hp`; `apply(amount) -> float` (applied, clamped at 0); `destroyed` becomes true once,
  and the call that crossed zero reports it; later hits apply nothing. `restore()` refills.
- `Damageable` (child of a ship, like `Targetable`): `faction`, `hull`, `shapes: Array[HitShape]` from the owner's
  `Hardpoints.collision`, `bounding_radius` from the shapes, `respects_god_mode`. `apply_hit(info: HitInfo)` always
  emits `hit_taken(info)` (effects, HUD flash), then applies damage unless god mode applies, emitting
  `damaged(info, applied)` when applied > 0 and `destroyed(info)` once. `is_active()` = visible in tree and
  processing.
- Starting values (tune in (H)): Starfury hull 300, pulse bolt 10; Delta-V hull 60, raider bolt 6. A raider dies
  to 6 hits, the player to 50.

### 15.5 Hit detection

Per projectile P (this tick it moved from `p1 - step` to `p1`; `step = P.last_step`) and per active `Damageable` D
that is hostile to P's faction and not P's shooter. D's body has not been stepped yet, so it is at its
start-of-tick pose `(t0, B)` with velocity `v_t`:

```
a = B^T ((p1 - step) - t0)                 # bolt relative to the target at the start of the tick, body frame
b = B^T (p1 - (t0 + v_t * dt))             # ... and at the end of the tick
if SweepMath.segment_sphere(a, b, Vector3.ZERO, D.bounding_radius + r_hit) < 0: skip
t = min over D.shapes of shape.sweep(a, b, r_hit)          # box: slab test on half extents + r_hit
                                                            # capsule (local +Y axis): exact cylinder + end spheres
hit point (World-local) = t0 + v_t * dt * t + B * (a + t * (b - a))
```

- The target's rotation during the tick is ignored (90 °/s is 1.5° per tick; ≤ 0.2 m at the wing tip).
- The box inflation is conservative at edges and corners (a rounded box would be exact); the bolt's
  `hit_radius_m` (0.25 m, generous next to the 0.05 m visual) dominates anyway.
- The earliest hit over all targets wins; the bolt is spent; an `ImpactFlash` is added to the hit ship at the
  local hit point; `hit_resolved(info)` is emitted for HUD and sound.
- A rebase between ticks changes nothing: positions shift together and `step` is a displacement.

### 15.6 Pools (D22)

- `ShipPool.prepare(type, count)` builds `count` Combatants with `ShipAssembly` at scenario load and spawns them
  through `World.spawn` at a parking position, then parks them: `visible = false`,
  `process_mode = PROCESS_MODE_DISABLED` (`CollisionObject3D.disable_mode` REMOVE takes the body out of the space).
  `acquire(name, at: UniversePos, basis, velocity, brain)` enables the ship first, then sets the pose from
  `World.universe_to_local(at)`, the velocities and a full hull, and calls `reset_physics_interpolation()`.
  `release` parks it again. The M2 raider pool holds 6.
- `DebrisPool` holds 2 chunk sets per chunked asset type (one break-up's worth each); a third simultaneous
  break-up gets one-shot chunks (a Starfury's chunks are held as a staged wreck for about a second first, §15.7). Pools stay
  small: parked nodes still cost memory.

### 15.7 Destruction

`DestructionDirector` listens to every `Damageable.destroyed`. Raider: hide and disable it in the same tick, spawn
an `Explosion` at its position with its velocity (scaled by `bounding_radius`), and `DebrisPool.burst` its chunks
(from hardpoints `chunks[]`) at its pose: velocity = ship velocity + `w × r` + 4-15 m/s outward, spin up to
90 °/s, an RNG seeded from the ship id and the tick (reproducible). The raider goes straight back to the pool;
debris lives 8 s, shrinks to zero over 0.5 s and hides. Assets without `chunks[]` (the Starfury in M2) get the
explosion plus generic generated shards. Player: same effects, controls ignored, respawn at the scenario start
after 3 s of sim time with a full hull, and `WaveDirector.on_player_respawned()` keeps the wave going (surviving
raiders re-target the player; maintainer decision).
`kill` (console) bypasses god mode.

**A Starfury dies where it was hit (M3-T28, Q28).** For a ship with the X-fighter damage layout (the player, the allies,
the instructor) the director takes the killing `HitInfo.point` (`World`-local), puts it in the ship's frame with the
transform it read before the ship left play, and `DamageZones.zone_for` names the part: the cabin or one of the four
arms, which are the five chunks. The main `Explosion` (same size, light and sound as before) starts at that chunk's
`joint` (`hardpoints.json` `chunks[].joint`, `docs/assets-starfury.md`) and `DestructionDirector.last_blast_position`
carries the place to `AudioDirector`. A console `kill` has no point: the blast is at the ship's centre and the order
is drawn from the seed alone. A ram is a hit with its contact point. Raiders, buoys and shards break up as before.

`DebrisPool.stage_wreck` replaces `burst` for these ships. `BreakupPlan` (pure) draws, from the seed (ship id and tick),
the order, the release times, the kicks and the tumbles: the first part leaves at once, the other four at about
0.2 + 0.25 k s (k = 0..3, each jittered by up to 0.05 s), so all five are away by about 1.0 s. `StagedWreck` (pure)
holds the chunks as one rigid body on the ship's velocity and spin, integrated exactly, and says when each leaves. A
chunk is held as a `DebrisChunk` (`hold`, `place_held`): drawn and busy, so its set stays taken, but placed by the pool
each physics tick. At its time it is released (`release`) with the wreck's velocity at its centroid (`v + w x r`) plus
a 4-15 m/s kick away from the wreck's centre (11-15 for the first), and the wreck's spin plus its own tumble. After
that it is the old chunk: constant velocity, no damping, 8 s of life, shrink, park. Its debris vent starts at the
release. Every later release also throws a small blast of `FxSpecs.HIT` sparks (24 particles, 0.45 s) at its joint:
no node, no light, no mesh, and the particles come from the hit pool's twelve emitters, never the explosion's, so
a wreck holds at most three at once and `fx.reused` moves only if all twelve are busy. Every set busy means mesh-only
chunks, staged the same way. The wreck copies everything it needs when it is made, so the pooled `Ship` can be
reacquired, or the player respawn, while it is held.

Rebase: the wreck's pose is `World`-local, so `DebrisPool` listens to `WorldFrame.rebased` and shifts every held wreck
by the same offset the shiftable chunks were just shifted by; nothing moves relative to the wreck.

### 15.8 Pilot brains (the M3 seam)

- `PilotBrain.think(p: Perception, dt) -> PilotCommand` (flight + combat; `ui` unused), `describe() ->
  Dictionary` (behaviour, state; console), `reset()`. Deterministic: randomness only from a seed set by the
  spawner.
- `Perception` (built fresh every tick, so it is rebase-safe): sim time, own pose, velocity, angular velocity, hull
  fraction, `ShipSpec`, weapon muzzle speed and lifetime, `frame_origin: UniversePos` (brains keep waypoints as
  `UniversePos` and convert them every tick), the selected target as `TargetInfo` and whether it is hostile.
- `PilotSteering` (pure): `face(dir)` -> `rot` (a P loop on the body-frame angle error that commands rates through
  the assist, gain well below `assist_gain_k`, signs via `FlightModel.AXIS_SIGN`); `seek(v_des)` -> mains when
  aligned with the velocity error, retros when it points aft, RCS strafe for the lateral rest.
- M2 brains: `IdleBrain` (coast, or hold with the brake), `PatrolBrain` (waypoint loop at a cruise speed, slowing
  for arrival), `AttackBrain` (approach -> aim at the `InterceptMath` lead -> fire inside a cone and range -> break
  off -> extend -> re-attack), `AggroBrain` (patrol until a hostile comes within range or it takes damage, then
  attack). `BrainFactory` builds them from scenario `behaviour` dicts.
- `AiPilotDriver` keeps its ship's `TargetingController` on the nearest hostile (`select_next`, hostile first).
  M3 adds `AiPilot extends PilotBrain` (utility selection, evade, formation, wingmen) behind the same interface.

### 15.9 HUD

`HudLayout.compute(input) -> HudFrame` is pure: it takes the camera transform, `Camera3D.get_camera_projection()`
and viewport size, the player's pose, velocity, mean muzzle position, `WeaponSpec`, hull and god flag, and the
selected target (position, velocity, faction, name, range, closing speed, hull fraction or -1, bounding radius).
Elements: boresight (nose axis at 1 km), velocity marker (prograde, or retrograde when prograde is behind) with
speed, target box (at least 24 px, faction colour) with name, range, closing speed and hull bar, an edge arrow when
the target is off-screen or behind, lead reticle (`InterceptMath`, hidden without a solution or beyond bolt
range), own hull bar with a `GOD` tag, and one status line (wave, raiders left, kills). `Hud` only draws it.
Radar (`RadarModel`): inside 25 km as before; a broadcast contact beyond it (M3-T17) sits on the rim in its true direction
as a hollow dot (`Dot.rim`).
`settings.show_hud` toggles it; while it shows, the debug overlay hides its own bracket. While the overlay shows, the wing roster sits below its text (M3-T29).

Console screens (M3-T29, Q29). In the cockpit camera of a ship with `screens` hardpoints the instruments leave the window. `HudSurface` is one surface the HUD draws on: what it lists (`items`) and
where each goes; `HudFrame` extends it, so the frame is also the 2D layer's layout, and `frame.screens` holds the octagon's, the left's and the right's, all drawn from that one frame by one
`HudPainter`. The window draws only the crosshair, lead marker, target brackets or edge arrow, and waypoint marker (and the prograde marker if `settings.hud_velocity_marker` is on, off by default: it
must line up with the world too). The octagon has the red grid, radar rings named by range, own ship, the same contact dots in the same faction colours as the chase view's radar (with a dark backing, over a dimmed grid), the selected
contact ringed, the grid's marker as a ring on a diagonal stroke, and AUTO-TRACK. The left screen has the damage wireframe, the hull bar with its percentage and GOD, speed, angles, reference, drift
sphere, lights, and fuel while the tank is finite. The right screen has the target's name, range, closing speed, hull bar and outline across its full width, a divider, then at the right edge the
upright charge bar (40/640 of the width, `CHARGE` and the fire mode above it) with the wing roster, acknowledgement and status lines to its left. `CockpitScreens` shows each `SubViewport` (`disable_3d`,
updated once per new frame, disabled while hidden) on an unshaded mesh without mipmaps, on the player's ship only (`console_owner`). Off with `settings.show_hud`. The chase camera, and a cockpit with no
screens, keep the whole 2D HUD. Indicator lamps are surfaces of the interior mesh, lit from `HudFrame.lamps`: assist, guns (the capacitor can pay for a shot), running lights, auto-track.

### 15.10 Scenarios and waves

`ScenarioLoader` gains optional `pools` (`{"raider_fighter": 6}`), `waves[]` and `loop`. A spawn is `{type, name,
anchor: "player" | "origin", offset, velocity, behaviour}`; positions and waypoints are offsets from the anchor's
universe position at wave start (summed as `UniversePos`, never through float32). `origin` is the scenario's origin,
universe (0, 0, 0), where its props are placed, not the World's local origin, which the rebase keeps near the player
(M3-T14). `ShipCatalog` maps `type` to a
`ShipSpec`. `WavePlan` (pure, fake-clock tested): `COUNTDOWN(delay) -> ACTIVE -> CLEARED -> next`, then loop from
`loop.from_wave`, one more attacker per loop up to the pool size. A wave may set `skill` and `aggression` ranges for its AI
raiders and `loop.skill_step` raises the skill range per pass up to an ace (M3-T13); each raider's values are rolled inside
them, seeded by its name and the wave number. `settings.scenario` (`combat_sandbox` by
default, or `free_flight`) picks the file; `Main.scenario_path` overrides it for tests.

Kill credit (M3-T16, Q18): `WaveDirector.kills` counts every raider destroyed, by anyone (rams included). `KillCredit` (pure)
splits out the player's share. A raider whose killing `HitInfo.shooter_id` is the player's ship (a bolt, or a ram: `RamResolver`
puts the other body there) is a player kill. One the player fired at least one shot at while it was the selected target
(the cannon's `projectile_fired`, with `TargetingController.selected_id()` at that moment), and someone else killed, is an
assist, never both. The mark is kept per `Targetable` id until that raider dies or `ShipPool.acquired` hands its ship out
again. The counts last the session, across respawns. Status line: `WAVE 2  PATROL   RAIDERS 2   KILLS 7   YOURS 3   ASSISTS 2`.

### 15.11 `raider_fighter` and chunks

The same output contract as §9 (the textured mesh since M4-T30d). In
`hardpoints.json`: two pods (one per side, each with a main and a small retro nozzle, centre of mass trimmed onto
the thrust line so pod thrust makes no pitch torque), four `muzzles`, `collision` primitives that also serve as hit
volumes (they must cover the hull's surface), `cockpit_camera` and `chase_anchor` (the `Hardpoints` parser requires them),
and `chunks[]`: `{name, obj, offset, mesh}`. `core/chunks.py` groups the hull's parts by part group (wing_l, wing_r, hump,
nacelle_l, nacelle_r); each chunk is re-centred on its own surface samples' centroid; `offset` is that centroid in the body frame.
Style `raider`: worn grey-brown plating, high panel tint jitter, dark canopy, yellow-white engine glow (a `ShipSpec`
tint for the plumes, the nozzle throats in the emissive map).

### 15.12 Control profiles

`ControlProfile` (pure): `{action: [event descriptors], deadzone}` <-> `InputMap` <-> ConfigFile text. A
descriptor is `pad:button:<0-14>`, `pad:axis:<0-5><+|->`, `key:<physical key name>` or `mouse:<button>`. Validation
uses the M1 input rules: every `InputAdapter.ACTIONS` entry present, a pad event on every action except
keyboard-only debug ones, standard indices only, never `KEY_QUOTELEFT`. `default` is a snapshot of the
`project.godot` map taken before any profile is applied. `settings.control_profile` (new schema type `string`)
selects the profile at start-up and on change; an invalid profile warns and falls back to `default`. Bindings
changed with `bind`/`unbind` are session-only until `controls save <name>`. A rebinding menu comes with the M5
front end.

As built (M2-T11): the `ControlProfiles` autoload applies the selection in `_ready`, before the main scene, and
follows `Settings.changed`. `Settings.validators` (key -> Callable) lets it refuse `set settings.control_profile x`
for a name that is not a valid profile; loading from disk does not consult it, so a stale saved name only warns and
falls back. Profiles are ConfigFile text: `[profile]` (`format`, `description`), `[bindings]` (one descriptor list
per action, in event order) and `[deadzones]` (one number per action, the InputMap deadzone); `data/controls/*.cfg`
are the built-ins (`m1_classic`), `user://controls/*.cfg` the user's. `bind` adds a descriptor and `unbind` removes one;
each builds the edited copy, validates it and applies it all at once, so an action can only lose its last pad
binding by binding another first. Applying replaces every game action's events and deadzone in the InputMap, then
`DebugConsole.resync_input_edges()` re-seeds the adapter so a button that now means something else cannot fire an
edge. Per-action shaping beyond the deadzone (ramps, expo, tap-or-hold) stays in `InputAdapter`/`Settings`, so a
profile moves bindings, not feel: under `m1_classic` the stick yaws in proportion and rolls on its diagonals (M3-T15), and
its D-pad rolls at full rate on top.

Saved profiles and new actions (M3-T07): a user profile that does not mention an action at all (neither in `[bindings]`
nor in `[deadzones]`: the action was added to the game after the profile was saved, like the wing orders on keys 1-4)
takes the `default` profile's bindings and deadzone for it when it loads (`ControlProfile.from_config_text`'s
`fill_from`, `ControlProfileStore.load_profile`), and applying it posts a notice naming them (printed, and shown by
`controls use`); `controls save <name>` writes them into the file. An action the file mentions in one section only, or
with bad entries, still makes the profile invalid. The built-in data profiles are not filled: they must be complete.

### 15.13 Console and settings (additions to §6.4)

| Provider | Owner (task) | Keys (w = writable) |
|---|---|---|
| `combat` | HitResolver (T03) | `projectiles`, `hits`, `last_hit`, `pairs_tested`, `resolve_us` (profiling only; the one wall-clock read) |
| `hull` | player Damageable (T03) | `hp`, `max_hp`, `fraction`, `invulnerable` (mirror of `debug.invulnerable`), `destroyed` |
| `raiders` | ShipPool (T05, T07) | `pool_size`, `free`, `alive`, `list` (name, behaviour/state, hull %, range), `selected_brain` |
| `waves` | WaveDirector (T09, M3-T16) | `scenario`, `index`, `name`, `state`, `next_in_s`, `alive`, `kills`, `player_kills`, `player_assists`, `losses` |
| `hud` | Hud (T08) | `visible`, `lead_tof_s`, `lead_on_screen`, `prograde_on_screen`, `target_box` |
| `controls` | ControlProfiles (T11) | `profile`, `profiles`, `unsaved` |
| `audio` | AudioDirector (T12) | `sounds`, `voices_active`, `volume` |

| Command | Owner | Does |
|---|---|---|
| `damage <amount> [player\|target]` / `heal [player\|target\|all]` | HitResolver | a hit with no shooter (god mode applies) / restore hull |
| `spawn raider [idle\|patrol\|attack\|aggro] [distance_m] [yaw_deg] [pitch_deg]` | WaveDirector | take a raider from the pool ahead of the player, named `RAIDER <n>`, nose toward the player turned by yaw/pitch (screenshot turntables) |
| `despawn [target\|all]` | ShipPool | return raiders to the pool without effects (screenshots, tests) |
| `kill [target\|all\|player]` | DestructionDirector | destroy now, bypassing god mode |
| `wave [start\|next\|stop\|restart] [index]` | WaveDirector | drive the wave plan |
| `scenario [free_flight\|combat_sandbox]` | Main | set the session setting and reload the scene |
| `controls [list\|use\|save\|show\|delete] [name\|action]`, `bind <action> <descriptor>`, `unbind <action> <descriptor>` | ControlProfiles | profiles |
| `sfx <name>` | AudioDirector | play a sound at the player |

New settings: `show_hud` (bool, true), `scenario` (enum `combat_sandbox`|`free_flight`, `combat_sandbox`),
`control_profile` (string `[a-z0-9_]{1,32}`, `default`), `sfx_volume` (float 0.0-1.0, 0.8).

### 15.14 Testing additions

Unit: `SweepMath` (analytic cases plus a brute-force sampling cross-check), `InterceptMath` (checked by
simulating the bolt and the target), `HullHealth`, `Factions`, `HudLayout`, `PilotSteering`, `WavePlan`,
`ControlProfile`, N-muzzle `PulseCannonGate`, hostile-first `TargetingSystem`. Integration (headless): hits at
closing speeds up to 1 400 m/s, near misses, no self-hit, rebase mid-flight, god mode, destruction in the same
tick, pooling (no pooled ship or chunk enters or leaves the tree during a run), brains in Jolt (patrol
reaches its waypoints, attack hits a drone), a three-wave run, the console smoke runs. Python: `raider_fighter`
(contract, chunks, collision coverage) and `sfx_combat`. (H) with pre-checks through
`scripts/capture.sh` (llvmpipe in xvfb): asset silhouette, HUD layout, effect compositing.

### 15.14b As built (M2 deviations from §15.1-§15.13)

Details per task are in the as-built notes of `docs/milestones/m2-combat-sandbox.md`. The ones that change the design above:

- `ShipAssembly` wires hardpoint-dependent components on the ship's `ready` signal; console ownership is opt-in
  (`Ship.console_owner`, `register_console` flags).
- Guns can converge: `WeaponSpec.convergence_range_m` (0 = parallel). The raider's plasma converges at 700 m; the AI's fire gate is also
  capped by a miss distance (`RaiderTactics.fire_miss_m`).
- Kills count every raider destroyed (the console's `kill` has no shooter). The wave carries on across the player's death.
- The sandbox is the default scenario; free flight has no pool, waves or activity. `Main.scenario_path`, `waves_auto_start` and
  `raider_pool_size` are test overrides.
- `ShipPool` keeps the `spawn` command; `AudioDirector` is `World/Audio` (a `Node3D`); the debris pool and the explosion are built in
  code (no `.tscn` for the chunk); the `scenario` command reloads the scene and the console queue survives it.
- `HudLayout` is pure and agrees with `Camera3D.unproject_position`; the radar sphere is tilted (`RadarModel.TILT_RAD`).
- Sound: manifest `kind` `audio`; engine hum is a child of each ship.

### 15.15 Seams M2 leaves for later

| Seam | Task | Avoids later |
|---|---|---|
| `PilotBrain` / `Perception` / `PilotSteering` / `AiPilotDriver`; brains write only commands | T07 | M3 rewriting how AI ships are driven |
| `InterceptMath` shared by HUD and AI | T01 | Two lead solutions that disagree |
| `Factions` as the one relation query | T01 | Hunting faction string compares when M3/M12 add factions |
| `Combatant` + `ShipAssembly` build player and AI ships the same way | T02 | Special-casing allies, wingmen, the Thunderbolt |
| Hardpoints `chunks[]` via `core/chunks.py` | T04 | Per-asset debris code for every later ship |
| Pools filled at scenario load | T05 | Spawn hitches when missions spawn ships (M5) |
| `ControlProfile` | T11 | HOTAS / keyboard+mouse / menu remapping starting from scratch |


### 15.16 Post-M2 additions

- **Destructible nav buoys.** `NavBuoy` carries a `Damageable` built from its `hardpoints.json` collision list (`Hardpoints.load_collision_only`, a
  prop has no pods or muzzles) with 60 hull points, neutral to every faction but `hit_by_anyone` (`Damageable.can_be_hit_by`: a bolt of its own
  faction still passes). `DestructionDirector.watch_buoy` blows it up (explosion, generic shards, explosion sound) and `NavBuoy.set_destroyed`
  hides and disables it without freeing it (D22); `Main.respawn` restores every buoy.
- **Newtonian invariant.** Every ship, the player's and the AI's, goes through the one `FlightModel`, which only produces nozzle forces and torques.
  Turning (sticks, assist, auto-track, brake-facing) is torque only, so the velocity changes only when pod or RCS nozzles fire (the brake is nozzles
  firing). The only writes to `linear_velocity` in `src/` are pool spawn / release, `reset_to` (respawn) and the 9 999 m/s ceiling clamp.
  Tests: `test_flight_model::test_turning_alone_never_produces_a_net_force`, `test_speed_and_autotrack` (a 180 degree auto-track turn at 250 m/s
  leaves the velocity unchanged to 0.01 m/s).

## 16. AI pilots and wingmen (M3)

What M3 adds to §1-§15 (tasks in `docs/milestones/m3-ai-pilots-and-wingmen.md`). Every earlier rule still holds; task ids
below are M3 tasks.

### 16.1 Decisions

| # | Decision | Rationale (short) |
|---|---|---|
| D30 | Factions come from `data/factions.json` (ids, names, symmetric relation pairs, a default). `Factions.relation` / `is_hostile` keep their signatures; the table is loaded lazily and can be swapped for tests and the console | M2's fixed rule was the seam (D25); callers do not change, and M12's factions are data |
| D31 | Friendly fire is `settings.friendly_fire` (default off, maintainer Q2). AI ships always check their fire lane for friends before firing | The forgiving default suits wingmen crossing the player's line; the check keeps AI behaviour right with the setting on |
| D32 | Ram damage from the ship's own velocity change: `hull_max × clamp((Δv - safe) / (lethal - safe))²` (Δv per ship; a 30 m/s head-on between equals is about 15 m/s each). Jolt contacts give Δv at ordinary speeds; at tunnelling speeds and for props without bodies, a swept test of each hit volume against each of the other's (exact for boxes and capsules) finds the hit, with the momentum split for both sides (fatal once that Δv reaches lethal) | Physical (the lighter ship suffers more), tunable per `ShipSpec`. At tunnelling speed (and always for props), hit volumes that overlap by 0.3 m or more always ram and a pass 0.3 m clear never does; below it, and for a shallower clip between two ships, Jolt's contacts decide |
| D33 | Collision avoidance is a filter in `AiPilotDriver` on every brain's desired velocity (closest-approach maths against `Perception.contacts`), not a behaviour | Every AI ship, M2 brains included, avoids collisions whatever it is doing |
| D34 | `AiPilot extends PilotBrain`: scored behaviours (attack, evade, formation, follow path, guard, retreat, idle) × `AiProfile` weights, with stickiness, a minimum dwell and an emergency margin. Orders and wings gate scores through `AiContext` | Utility selection (§14.7) without a behaviour tree; profiles give allies, raiders and the instructor different characters from one brain |
| D35 | `chunks[]` for `starfury_aurora` (the cabin and four arms). Allies fly the Starfury's numbers and hull with no cockpit (`starfury_ally`); M3 gave allies and debris a coarser point-cloud level, which M4-T31 retired with that renderer: every Starfury draws the one shared textured mesh | One shared mesh and material per asset instances every copy, so allies cost a draw each, not a coarser asset |
| D36 | Wings: the player leads `ALPHA` (finger-four). Orders (attack my target, form on me, engage at will, cover me) arrive as `UiCommand` edges from keys 1-4 (keyboard-only actions) or the console, and go to brains through `WingDirector`, never through `Input` | Maintainer Q1; the pad has no free button and the M5 comms panel will add a pad route on the same `WingDirector` API |
| D37 | The instructor is an `AiPilot` with the `instructor` profile, a `Route` (paced to the player) and demo `Manoeuvre`s, invulnerable via its scenario spawn | The M8 tour and control checks reuse it unchanged; manoeuvres are closed loops on measured state, so the tutorial can compare the player against the same goals |
| D38 | Keyboard layout B: every flight key is under the left hand (pods by position on Q/W/E and A/S/D), the mouse flies pitch and yaw, no keyboard pitch/yaw | Maintainer Q9: the right hand is on the mouse |
| D39 | Broadcasts (M3-T17, Q21): `Targetable.broadcast_range_m` lets a contact be heard beyond the sensors. Targeting and the radar use it directly; the AI hears the same broadcasts at the same ranges (any faction) as a separate `Perception.broadcasts` list from `ContactScan.shared_broadcasts`, a scan of `Targetable.broadcasters()` alone. `ContactScan` (5 km) stays the near list for avoidance, the fire lane and threats. Behaviours do not chase far contacts on their own: a pilot **objective** (`AiContext.objective_name`, `ai <name> objective <target|none>`, a spawn's `objective`) makes the attack transit to it and attack it once inside 5 km, as a fallback while no hostile in sight may be attacked (M3-T10); the player broadcasts like an ally (100 km) and wave raiders take the player as their objective | Missions (M5) send raiders at a buoy or the station from beyond sensor range; one registry, no second sweep over every body, so AC13's budget holds |
| D40 | Hit reaction, guard, wings in scenarios (M3-T10, Q11): a fresh bolt hit hands control to evade at once for one full jink (`AiPilot.select`, `BehaviourEvade.locked`). A guard post gates the attack through `AiContext.may_attack` (hostiles inside the radius or after the guarded ship) and `BehaviourGuard` keeps station. Scenarios declare `wings[]` and spawns name a `wing`; an AI-led wing hands the lead to its next member; its ships rally on an engaged wingmate (`BehaviourRally`). `AttackBrain` caps the speed it seeks (`RaiderTactics.max_speed_mps`: break and extend at it, approach at the higher of it and the target's speed, plus the closure) | Ships under fire behave like pilots; raider groups and wings come from data; AI-versus-AI fights stay at fighting speed and together while a chaser still outruns any target |
| D42 | Slashing pass (M3-T18, Q19): each attack run is, by a seeded roll, `AttackSlash` (an offset firing pass, a turn and burn, a chase at 500 m) or `AttackBrain`'s standard run; rookies always slash, higher skill less often (`AiTemperament.slash_chance`), the most aggressive pass at 100 m instead of 200 m; evade weighs threats from ships other than the attack's target by skill (`awareness`); `AiProfile.slashing` opts out; the nose tracks the lead with its turn rate fed forward (`PilotSteering.face_tracking`) | Better pilots keep their guns on the target far longer (3.8x the time in the fire gate against a drone), with the same gate, target choice and caps |
| D43 | Retired by M4-T31. M3-T19 gave every ship a chain of point-cloud levels picked by projected size; the textured meshes take the importer's levels of detail instead, and `LodSwitcher` keeps only the far dot (§14.4, §17.10) | The renderer that needed hand-built levels is gone |
| D44 | Retired by M4-T31. M3-T20 sized the old renderer's sort buffers from a visible budget; meshes need no sort buffers (the VRAM they held, about 1.2 GB, is free again) | The renderer that needed the budget is gone |
| D45 | Retired by M4-T31. M3-T24 gave the player's Starfury a finer point-cloud level for close range; its textured mesh (a 4 096 px normal map, M4-T30b) is the close-range look now | The renderer that needed it is gone |
| D41 | Skill and aggressiveness (M3-T13, Q12): `AiTemperament` scales a copy of the pilot's `AiProfile` (weights, retreat threshold, aim error, miss gate, engage and break-off ranges) and sets the reaction time, jink quality, passivity and the reckless ram; `regular` + `balanced` leave a profile as tuned. `BehaviourRam` commits a reckless, badly hurt, mostly alone ship to a collision course with avoidance off for its target only | Civilian, raider and military AI feel different from one brain and one set of behaviours; numbers stay data |

### 16.2 Layout additions

```
data/factions.json                       faction ids, names, relation pairs, default (T02)
src/combat/faction_table.gd              RefCounted, pure: parsed factions.json; relation lookup (T02)
src/combat/ram_math.gd, ram_resolver.gd  pure severity maths; Node: contacts + swept rams -> Damageable (T04)
src/ai/contact.gd, contact_scan.gd       per-tick contact list shared by every driver (T05)
src/ai/avoidance_math.gd, fire_lane.gd   pure: closest-approach dodge; friendly-in-lane check (T05)
src/ai/ai_pilot.gd, ai_context.gd, ai_behaviour.gd, ai_profile.gd        utility brain (T06)
src/ai/behaviour_{attack,evade,retreat,idle,formation,guard,follow_path}.gd  (T06, T07, T09, T10)
src/ai/wing.gd, formation.gd             wing state and slot offsets (T07)
src/ai/behaviour_{guard,rally}.gd        guard post, rally on an engaged wingmate (T10)
src/ai/ai_temperament.gd, behaviour_ram.gd   skill and aggression; last-ditch ram (T13)
src/ai/attack_slash.gd                   the slashing pass and chase (T18)
src/rendering/lod_switcher{,_math}.gd    level of detail by size on screen (T19; since M4-T31 only the far dot)
src/combat/fx_specs.gd, fx_pool.gd       pure effect numbers; fixed GPUParticles3D pools, one per effect (T23)
assets/fx/*.tres                         the effects' process materials and draw meshes (T23)
src/rendering/{light_rig,light_picker,light_emitter}.gd   the 8 lights and who fills them (T21; the rig renamed in M4-T31)
assets/ai/civilian.tres                  never attacks, flees within 3 km (T13)
src/ai/route.gd, manoeuvre.gd, manoeuvres.gd   instructor route and demo moves (T09)
src/game/wing_director.gd                Node (Combat, priority 290): wings, orders, acknowledgements, replenish (T07, T08)
assets/ai/{ally_starfury,raider,instructor}.tres, starfury_tactics.tres
assets/ships/starfury_ally.tres          the Starfury's numbers, no cockpit (T08)
data/scenarios/{instructor_route,dogfight}.json   (dogfight: wings ALPHA, RED, BLUE; T10)
data/star_systems.json, src/environment/star_catalog.gd, star_color.gd   a system's star and its colour, by `system_id` (T25, Q30)
src/ai/ai_console.gd, src/combat/faction_console.gd   the console sides of the AI drivers and the factions (T06, T02)
src/combat/kill_credit.gd                the player's kills and assists (T16)
src/combat/ram_tracker.gd, convex_sweep.gd   ram bookkeeping; exact swept hull test at tunnelling speed (T04)
src/combat/breakup_plan.gd, staged_wreck.gd  pure: which part leaves when; the wreck that holds the rest until then (T28)
src/rendering/post_effects.gd, lens_flare_*.gd, motion_blur_*.gd   the compositor effects (T25)
src/ship/running_lights.gd, nav_lights.gd    the markers, from generated `nav_lights` hardpoints (T27)
src/hud/hud_surface.gd, hud_painter.gd, cockpit_screens.gd   one drawing code for the 2D layer and the console screens (T29)
tools/procgen/parts/cockpit.py           the Starfury's interior and its `screens` hardpoints (T29)
scripts/capture_m3.sh, measure_m3.sh, measure_fight{,_node}.gd, measure_held_brain.gd   the capture set; AC19's fight and 100 ships measured on the GPU (T12)
tests/integration/test_m3_run.gd         the whole sandbox in one build; the dogfight's AI time and resolver budget (T12)
```

### 16.3 Tick order (changes to §15.3)

Superseded for M4 and later by §17.13 (see the note under §15.3).

1. `AiPilotDriver`s (-10): `ContactScan` (first driver of the tick builds it), `Perception`, brain, avoidance filter,
   `Combatant.apply_commands`.
2. Console, `Main` (0), the World's automatic rebase (0, M3-T14), ships, projectiles as before. `Main` passes order edges
   from `UiCommand` to the `WingDirector`.
3. `TargetingController`s (100), `HitResolver` (200), `RamResolver` (210): contacts reported by Jolt since its last run
   and swept rams; destruction in the same tick (§15.7).
4. `WingDirector` (290): orders, acknowledgements, leader changes; `WaveDirector` (300): waves; on `wave_started` it calls
   `WingDirector.replenish()` (allies for the player wing's empty slots, 1 500 m behind the player, T08).
5. Jolt steps the bodies (and reports the contacts the `RamResolver` reads next tick).

### 16.4 Console and settings (additions to §6.4 and §15.13)

| Provider | Owner (task) | Keys |
|---|---|---|
| `factions` | Factions (T02) | `ids`, `relations`, `friendly_fire` |
| `ram` | RamResolver (T04) | `events`, `last`, `resolve_us` |
| `ai` | AI drivers (T06) | `ships`, `by_behaviour`, `think_us` |
| `allies` | ShipPool (T08) | `pool_size`, `free`, `alive`, `list`, `selected_brain` |
| `wing` | WingDirector (T07) | `name`, `order`, `formation`, `members`, `last_ack` |
| `route` | instructor (T09) | `index`, `count`, `lag_m`, `state`, `demo` |

Commands: `relation <a> <b> [friendly|neutral|hostile]` / `relation reset`; `wing order <attack|form|engage|cover>`;
`wing formation <finger_four|wedge|line_abreast>`; `wing replenish`; `spawn ally [idle|ai] [distance_m] [yaw_deg] [pitch_deg]`; `kill allies`; `ai <name>`;
`ai <name> objective <target|none>` (M3-T17: an `AiPilot` flies to the named target from any broadcast range and attacks it);
`ai <name> skill <rookie|regular|veteran|ace|0-1>`, `ai <name> aggression <passive|cautious|balanced|aggressive|reckless|0-1>`,
`spawn raider|ally ai ... skill=<...> aggression=<...>` (M3-T13);
`scenario [free_flight|combat_sandbox|instructor_route|dogfight]`. Settings: `friendly_fire` (bool, false), `ram_damage`
(bool, true). Provider `render` gains `gpu_ms` (M3-T20).
M3-T27: command `running_lights [on|off]`, key
`ship.running_lights`, `spawn ... lights=on|off`, and settings `cabin_glow_level` (0-2, 0.3),
`cabin_glow_view_m` (1-2000, 150), `running_light_min_px` (0.5-12, 1; 3 before M4-T28). `raiders.list` and `allies.list` mark a ship flying dark.
M3-T21: provider `lights` (`picked`, `candidates`, `active`, `cost_us`). M3-T25: commands `flare [on|off]` and
`blur [on|off]`, provider `post`, settings `lens_flare` (bool, true), `motion_blur` (bool, false), `motion_blur_strength` (0.5). M3-T29: provider `screens` (`shown`, `powered`, `paints`, `lamps`),
`hud.window_items`. M4-T31 removed the M3 renderer's commands (`lod`, `fallback`, `relight`), its settings and the `lod` provider;
`render` is `RenderStatus`'s (§6.4). M3-T12: command `look <yaw> [pitch]` / `look off` holds the view off the nose from the console, for captures and for looking back at a formation.

### 16.5 Particles (M3-T23)

Hull hits, rams, explosions and debris throw sparks and glowing fragments from `GPUParticles3D` (D8).
`FxPool` (`World/Fx`) holds a fixed set of one-shot emitters per effect (`FxSpecs`: `hit` 12, `ram` 6, `explosion_sparks` 4,
`explosion_fragments` 4, `explosion_gas` 4, `debris` 16), built once in `_ready` and restarted for each burst, so the particle node
count never changes. `HitResolver`, `RamResolver`, `Explosion` (through `DestructionDirector`) and `DebrisPool` hold a reference
(`fx`, set by `Main`) and call `FxPool.burst(effect, position, direction, velocity, duration)` in the physics tick.

- **Newtonian.** The process materials (`assets/fx/fx_*.tres`) have zero gravity and zero damping (the damping guard test checks
  them). A burst inherits its source's velocity by flying its emitter at that velocity; the particles live in the emitter's frame
  (`local_coords`), so they go where it goes. The explosion's old 0.8-1.6 damping on its sparks is gone with that.
- **Rebase.** Every emitter is `top_level` and in `world_shiftable`, so `WorldFrame.rebase` shifts its transform (the emitters'
  transforms are shifted, there is no anchor node). A burst asked for in the tick is placed at once and only started in
  `_process`, so a rebase between the two shifts it as well.
- **Hot path.** `burst` allocates nothing and does no tree lookup: parallel packed arrays hold the state, the setting is cached from
  `Settings.changed`, and the return value is an int handle (slot plus generation) for `stop`. With every emitter of an effect busy
  the oldest is restarted (a fresh hit matters more than a fading one); effects never grow the pool.
- **Density.** `settings.particle_density` (0-1) sets `amount_ratio`; at 0 `burst` returns 0 before it claims anything and the pool's
  `_process` stays off (it is on only while an emitter is busy).
- **Aim.** A hull hit's sparks leave along the bolt mirrored about the hull's surface (taken as radial from the hull's centre); a ram's
  along the contact normal in a wide cone; explosions in every direction.
- **Vents.** Each debris chunk vents for 2-4 s (`FxSpecs.debris_duration_s`, from the break-up's seed); `DebrisChunk` stops its vent
  when it parks, finishes or leaves the tree, so no emitter is left venting where a chunk was.
- Meshes are additive, unshaded, transparent, so the hull depth proxies hide them behind hulls like the plumes.

Console: provider `fx` (`emitters`, `busy`, `bursts`, `reused`, `density`); command `fxburst [hit|ram|explosion_sparks|
explosion_fragments|explosion_gas|debris]` throws one burst 40 m in front of the camera. Setting: `particle_density` (float 0-1, 1).

### 16.6 As built (M3 deviations from §16.1-§16.5)

Details per task are in the as-built notes of `docs/milestones/m3-ai-pilots-and-wingmen.md`. The ones that change the design above:

- **Renderer.** M3 forked its hull renderer (Q25, Q32) for a visible budget and per-instance lights; M4-T31 removed that renderer
  and the fork with it (§17.20).
- **Who slashes.** The plan had veterans and aces only. As built every pilot does, on a seeded share of attack runs, a rookie on all of them (D42, T18, the maintainer's call). The balance this leaves is AC12's, below.
- **AC12's balance is open.** With the skills and slashing as built, rookies shoot down the sandbox's wing in wave 2 and the dogfight does not always end in 6 sim minutes. The maintainer holds that tuning, so `test_m3_sandbox` and
  `test_dogfight` record their runs and go pending instead of failing.
- **Break-up.** A Starfury does not burst into its five chunks in one tick: the part hit last leaves first and the rest follow over about a second (T28, Q28). Raiders and buoys burst as before.
- **Cockpit HUD.** In the cockpit camera the instruments are on three `SubViewport` screens built into the console (T29, Q29), for the player's ship only; the window keeps the aiming marks. The chase camera keeps the 2D HUD. Both draw through `HudPainter`.
- **Lights the player can't see.** A dark ship (Q27) is dark to the eye only: radar and AI contact lists never use lights.
- **Star.** A system's star is data; the flare and the key light take its colour, and the flare is a lens effect only, with no veil or god rays (Q30, Q31).
- **What runs on what.** The one number that limits scale is on the CPU: 100 ships miss 60 fps because of `TargetingController` (as T20 measured it, before the visual pass), not the renderer (M3-T20; `docs/roadmap.md`, M4).

## 17. Performance and scale (M4)

What M4 adds (tasks in `docs/milestones/m4-performance-and-scale.md`, where the budget and the cycle log live). Every earlier
rule still holds; task ids below are M4 tasks.

### 17.1 Benchmark harness (T01)

```
src/perf/perf_stats.gd      RefCounted, pure: median, p99, the budget verdict, max N over a sweep, the paired on/off cost
src/perf/bench_layout.gd    RefCounted, pure: where furball, spread and transit ships start, seeded
src/perf/perf_probe.gd      Node (Main/PerfProbe): times every tick's stages; provider `perf`, command `perf [on|off]`
src/perf/bench_runner.gd    Node (Main/BenchRunner): command `bench`, runs a layout on the live scene, writes the report
src/perf/bench_report.gd    RefCounted: a run's and a sweep's summary.json and summary.md, and the machine they ran on
scripts/bench.sh, bench_sweep.gd   the sweep: one headless process per run, pinned to the performance cores, then the summary
scripts/bench_quick.sh      the quick check: ramps furball and spread until 30 FPS, one short run per count, under 10 minutes
```

- **The tick** is the whole physics frame: the sync of the bodies back to their nodes, every script and Jolt's step.
  `PerfProbe` reads the wall clock at `SceneTree.physics_frame` (before any script), at marker nodes between the systems'
  priorities (-11 and -9 around the AI drivers, 99 and 101 around targeting, 211 after the resolvers), at its own sampler last
  in the tick (2 000 000, after the `RebaseSettler`), and at the next frame's start (the end of Jolt's step). So the stages
  split the tick without timing any system from inside: `ai`, `flight` (priority 0: the console, `Main`, the rebase's shift,
  the ships' flight model, bolts, props), `targeting`, `resolvers`, `late` (wings, waves, the rebase's reset), `physics` (Jolt and
  the body sync with the engine's flushes around them) and `other`, the remainder before the AI drivers. `scan` (the contact
  scans, timed inside `AiPilotDriver.perceive` only while the probe is on), `think` (the drivers' own timer), `hit` and `ram`
  (the resolvers' own `resolve_us`) and `rebase` (the shift, `WorldFrame.last_rebase_us`) are listed inside them. The engine's
  `Performance.TIME_PHYSICS_PROCESS` is the worst step of each second, not a per-tick number, so it is only a check on the
  probe's window: the two agree within noise.
- **The body sync** happens after the last frame and before the scripts, so it is only timed when nothing sits in between:
  headless the engine sleeps up to 6.9 ms between frames (`OS.low_processor_usage_mode_sleep_usec`), and a bench run sets that
  to 0 for its duration (`PerfProbe.time_sync`; `sleep=keep` leaves it, to measure what the busy loop changes). With a window
  open the frame's drawing sits there instead and `sync_us` stays 0. When ticks run back to back (a simulation behind real
  time) a tick's sync lands in the previous tick's engine window, so `sync` is a lower bound; summaries give the share of ticks
  in which it was timed.
- **The quick check** (`scripts/bench_quick.sh`) ramps furball and spread from 10 ships up, one seed, 2 s of warm-up and 6 s
  measured per count, and stops a layout at the first count under 30 FPS (simulation ticks per wall second, 60 while it keeps
  real time; `QUICK_MIN_FPS`) or when its share of a 9 minute budget runs out. Per count it prints the FPS, tick, p99, worst
  rebase tick and the three costliest stages; when a layout stops it lists the counts that passed the budget, those over budget
  but still above the floor (with why), and the count where it failed. One short run is indicative only: it is for iterating,
  and the sweep gives max N.
- **A run** (`bench <layout> <n> [seconds] [warmup=] [seed=] [label=] [probe=paired] [rebase_m=]`) parks every pool ship,
  grows the pools to the layout's count (`Main.ensure_pool`; that is the run's load time), stops the waves, turns god mode on,
  turns the player to face -Z and gives it 60 m/s, lowers the rebase threshold to 180 m (a rebase every 3 s, under 1 % of the
  ticks), makes the sides neutral for `transit`, and takes `BenchLayout`'s ships from the pools, invulnerable so the count holds.
  N counts those ships; the player flies too. The rebase budget is on the whole tick that held a rebase, not the shift alone.
  Windows are counted in ticks; real time kept is the recorded ticks' sim time against the wall time they took. The command
  holds the console queue until it ends (`DebugConsole.release_wait`); a run under a tenth of real time is cut short. Afterwards
  everything it changed is put back, and its ships stay in play. A run that dies without a report leaves a failing
  placeholder, so the sweep counts it as a failed run (one surviving pass cannot pass a count) and still sees the count.
- **Tests** never assert milliseconds: `test_perf_stats`, `test_bench_layout` and `test_bench_report` are pure; `test_bench`
  checks per tick that the stages split the tick and that each inner stage fits in its own (scan and think in ai, hit and ram in
  resolvers, sync in physics, the rebase in flight and late), and that runs write their reports; `run_tests.sh` runs
  `bench furball 25 5` and checks the report is there.
- **A release build** (M4-T03r): numbers come from the editor build (debug), which the suite uses. To measure what players
  run, `scripts/setup_export_templates.sh` installs the official Linux templates under `.tools/godot/templates/`, and its
  header gives the steps: snapshot a commit with `git archive`, export it with a "Linux release" preset, link the export's
  `reports/` to the snapshot's, and point `GODOT_BIN` at a wrapper that drops `--path` (a template cannot open a project
  folder). The release export runs GDScript stages about 1.2 to 1.3 times faster (Cycle log, cycle 2).

### 17.2 Cycle 1: only the player's targeting keeps a list (T02)

- **Before**, every ship's `TargetingController` turned every targetable into a `TargetInfo` each tick, so targeting cost
  O(N^2) and was two thirds of a 100-ship tick (74 of 109 ms in the furball), the same in every layout.
- **Now** `TargetingController.keeps_candidates` says whether the whole list is rebuilt every tick. `ShipAssembly` sets it from
  `is_player`: the player's list is read by the HUD and the radar every frame and is built as before. Every other ship's
  controller checks only its selection each tick (the target still exists, is in play, is not its own, and is within the
  sensors or its own broadcast range) and builds a list only when asked: `candidates()`, the target edges and `select_by_name`
  gather on demand, `select_id` checks the one target, and `select_nearest_hostile` walks the targetables for the nearest hostile
  without building a `TargetInfo` (the same pick as the head of `TargetingSystem.cycle_order`). A target picked this way is held
  as the system's only candidate, so `TargetingSystem` keeps its rule that a selection is among its candidates.
- **Behaviour** is the same: `test_targeting_scale` runs a controller of each kind side by side over 400 seeded steps and
  compares every answer, selection and `target_changed` signal, and a seeded bench run gives identical outcomes before and after.
  One difference stays inside a tick: a target that left play or reach since the last refresh can no longer be selected by id
  before the next refresh, where the last tick's list used to allow it until the refresh at priority 100 cleared it.
- **Work count**: `TargetInfo.built_count` (every `TargetInfo` built in the process), for tests and profiling.

### 17.3 Cycle 2: the ram resolver's broad phase (T03)

- **Before**, `RamResolver`'s swept pass looked at every pair of active hulls every tick: a velocity difference, the tunnelling
  test and either the shape sweep or `RamTracker.keep_touching`, about 1.5 us a pair, so O(N^2) and 7.8 of the 9.5 ms of rams at
  100 ships in every layout, though nearly every pair was hundreds of metres apart.
- **Now** `RamBroadPhase` (pure; native as `ScsRamPhase` since M4-T15, the GDScript kept in `tests/fixtures/` since M4-T42)
  boxes each hull's bounding sphere along its path through the tick, grown by a metre, and sorts
  and sweeps the boxes along x. Only overlapping pairs, and the pairs Jolt reported touching in its last step, reach the old
  per-pair code, in the old pass's order (a ram earlier in the pass can destroy a hull a later pair holds).
- **Why nothing changes**: a pair whose boxes do not overlap cannot meet the resolver's first exact test (the two bounding spheres
  meeting over the tick), so its shape sweep would have found nothing; and `keep_touching` only acts on a pair Jolt holds in
  contact, which is always looked at. So `RamTracker` sees the same calls that matter, and a skipped pair stops touching exactly
  when it did before. `test_ram_broad_phase` checks every candidate against the sphere test on seeded crowds near the origin and
  45 km out; `test_ram_scale` counts the pairs looked at per tick and pins the rams that must still land.

### 17.4 Cycle 3: the AI think rate and nearest-k contacts (T04)

- **Before**, every AI ship perceived, thought and filtered its wish through avoidance every tick, against every contact
  within 5 km: the AI was 56 % of a 50-ship furball tick and grew faster than N (each ship scored and avoided all N).
- **Think rate** (Q8, settings `ai_think_rate` on, `ai_think_near_m` 2 000, `ai_think_far_hz` 20). A ship within
  `ai_think_near_m` of the live player thinks every tick. A farther one thinks every `AiThinkRate.period_ticks` ticks (3 at
  20 Hz and 60 Hz physics), on a beat shifted by its driver's place in the tree when its pilot was set, so consecutive pool
  ships share the ticks evenly. Between thinks the driver leaves the ship's last `FlightCommand` and `CombatCommand` in place:
  `Ship` keeps flying a command until it is replaced (edges act once, `fire` holds), so the flight model and Jolt still step
  every tick. Each think is given the time since the last one, so the brain's timers keep sim time. A new pilot or a hit
  (`Damageable.hit_taken`) wakes the ship for the next tick; anything else waits at most one far period (50 ms). Avoidance
  (D33) runs with the think, against the contacts of that think. **With no player in play, or the player dead, every AI ship
  thinks at the far rate.** The player is the `Combatant` `ShipAssembly` built with `is_player` (`AiPilotDriver.player`,
  cleared when that ship leaves the tree). The rate is counted in physics ticks, so `Engine.time_scale` stretches it in sim time:
  at 4 to 6 times speed-up (the integration tests, the console's time scale) a far ship decides every 0.2 to 0.3 s of sim time.
- **Nearest-k** (option 4, setting `ai_nearest_k`, 12; 0 = every contact). The perception's `contacts` are the nearest k of
  the contacts within 5 km (`ContactScan.nearest_for`, a partial selection over the scan's packed positions, back in scan
  order, so with k or fewer in range it is `contacts_for`'s list). When the cut leaves anything out, the nearest hostile
  ship joins them (a crowd of friends must not hide the fight: without it some furball ships idled), and so do the contacts
  the brain keeps: its wanted target (`PilotBrain.keep_ids`; an `AiPilot` adds its wingmates, leader, the leader's target, its
  attack target and the route's pace ship, and keeps its objective and guarded ship by name), the ship's selection and whoever
  hit it in the last `KEEP_ATTACKER_S` (10 s). The kept lists are built only then (`AiPilotDriver._keep_lists`, called by the
  scan), so a ship that sees k or fewer pays nothing for them, and until more than k are in range the scan only gathers, like
  `contacts_for`, so where nothing is cut nearest-k costs what the full list did. Behaviours, the avoidance filter and the fire lane all read
  that one list. Broadcasts are not cut.
- **Holding the command, not the decision.** Re-running the steering between thinks was allowed if held commands misbehaved.
  They did not: a veteran against a straight-flying drone for 60 s keeps it in its fire gate within 1 % as long at 20 Hz as at
  60 Hz, with no shot outside the gate and 3 % more change in turn rate per tick (Cycle log, cycle 3). So nothing is re-run on a
  held tick.
- **Console**: provider `ai` gains `thinks_near`, `thinks_far`, `held` and `contacts_max` (the latest tick's work counts) and
  `mean_speed_mps`. Both settings off give the M3 behaviour bit for bit (a seeded bench comparison in the Cycle log).
- **Tests**: `test_ai_think_rate` (work counts per tick against the near ships plus a third of the far ones, contacts per ship
  against k, and the behaviour pins), `test_nearest_contacts` (the selection against a full sort on seeded crowds) and
  `test_ai_think_rate_math`.

### 17.5 The native library (cycle 4, T05)

```
native/                         Rust crate scs_native (cdylib), skipped by Godot's scan (.gdignore); one native class per file
native/Cargo.toml, Cargo.lock   gdext pinned "=0.5.5" with feature api-4-7; every crate locked
native/rust-toolchain.toml      the one Rust version (1.99.1); rustup installs it on first use
bin/scs_native.gdextension      committed; points Godot at bin/libscs_native.so (built, ignored by git)
scripts/build_native.sh         cargo build --release --locked into .tools/native-target, then copies the library to bin/
src/perf/native_lib.gd          NativeLib: the only way GDScript reaches a native class
src/perf/native_probe.gd        NativeProbe: facade over the trivial ScsNativeProbe, the pattern for later ports
src/perf/native_boundary_bench.gd   what a call into the library costs (console `native bench`)
native/src/contact_field.rs     ScsContactField: the contact scan's queries (T05b, N1), behind ContactScan
```

- **Optional until M4-T37** (maintainer Q9). No GDScript named a native class: `NativeLib.instantiate(&"ScsName")` returned null
  when the library was not loaded or the setting `perf_native` was off, and the facade then ran its GDScript code, so a missing
  or stale library never broke parsing, the suite or the game, and a bench could pair native against GDScript in one process.
  M4-T37 ended this (Q57, Q67): the library is required (`Main` refuses to start without it, naming the missing classes and
  `scripts/build_native.sh`), `perf_native` is gone, and the parity tests compare with recordings in `tests/fixtures/parity/`.
  A native class gets its own name (`Scs...`), since a GDScript `class_name` cannot share it.
- **Building.** `scripts/build_native.sh` builds only when the library is missing or older than a file under `native/`; with no
  `cargo` it says the game needs the library and exits 1 (until M4-T37 it exited 0 and the game fell back to GDScript).
  `run_tests.sh` runs it before the import and stops when the build fails or leaves no library, and CI builds once per job
  with cargo's files cached on `Cargo.lock` and the toolchain file. The library is built for baseline x86-64, never
  `target-cpu=native`, so the maths is the same on every machine.
- **Crossing the boundary** (Cycle log, cycle 4, debug editor build): a native call with one int costs 0.12 us, 0.22 us through
  a facade, against 0.08 us for a GDScript call; one with a packed array in and one out about 0.35 us plus a few ns per element.
  Packed arrays share their data (copy on write). So the seam is one call per ship per query with packed arrays in and indices
  out, never a call per contact, and native code never reads a GDScript object. Results are collected in Rust and handed over once.
- **Threads** are allowed inside native code later (N3, maintainer Q9), with a test that one thread and six give the same
  output; T05a adds none.
- **Following the setting.** `NativeLib.enabled()` cached `perf_native` until M4-T37 removed both. `NativeLib.version`
  takes the class to ask.
- **The contact field (T05b, N1).** `ContactScan` keeps its interface, so brains, drivers and tests are unchanged. On a
  scan's first native query it makes an `ScsContactField` and hands it the scan's arrays in one `load` call: body ids,
  positions, factions, ship flags, broadcast reaches, the bolts, and the sensor range as the grid's cell size. The field
  sorts the bodies into a uniform grid of 5 km cells; a contact or nearest query tests only the bodies in the cells its range
  reaches (or every body when the range spans more cells than there are bodies), then works through them in scan order.
  `contacts`, `nearest` (the nearest k and the nearest hostile ship, then a -1 marker when the cut left something out),
  `broadcasts` and `incoming` return body indices or a count; the freed-body check (`bodies_alive`) moved too. The facade
  still calls the brain's keeper and adds what it names (ids and case-insensitive names) in GDScript, sorts, and builds the
  `Array[Contact]` from the faction's shared list. Factions cross as `StringName`s, and the facade sends each querying
  faction's hostility row (from `Factions`, which native code never calls).
- **Bad input never panics.** `load` checks that the parallel arrays line up (bodies, positions, factions, ship flags, reach
  when given, and the four bolt arrays). On a mismatch it logs one error, keeps an empty scan (every query answers nothing) and
  returns false; `ContactScan` then marks the scan rejected, and it answers nothing (it answered from GDScript until M4-T42
  removed the loops). The grid's cell count is a checked
  product, so a range too large to enumerate (a huge finite one saturates the cell indices) tests every body instead.
- **Parity is bit for bit** (maintainer, 2026-11-02). The field repeats GDScript's arithmetic: 32-bit vectors, 64-bit scalars,
  the engine's order (`x*x + y*y + z*z`), a float rounded to 32 bits before it scales a vector, the same comparisons
  (`<=` for contacts, "not greater" for nearest-k, equal ranges to the earlier body) and no fused multiply-add (Rust never
  contracts). `test_contact_field` compares the field with the GDScript loops' recorded answers (M4-T37; the loops went in
  M4-T42) on seeded worlds of 1 to 300 bodies and on bolts that graze the 15 m line, where only the same precision gives
  the same count.
- **Contacts are made when first handed out.** Each faction's list starts empty and a `Contact` is built the first time a
  query returns that body (a broadcaster nobody hears, or a body no ship of the faction sees, costs nothing).
  The objects are still one per body per faction per scan, shared and read-only.

### 17.6 The battle and typical layouts and the stand-ins (T07)

```
src/perf/battle_mix.gd              BattleMix, pure: the typical and grand profiles, counts per entity type from N
src/perf/bench_layout.gd            + battle and typical: fights on an 8 km lattice, capitals, rocks, the orbit, the sides
src/perf/standins/standin_director.gd   Node3D (World/Standins): holds and steps the stand-ins, counts the battle
src/perf/standins/capital_standin.gd    RigidBody3D: a box hull with Targetable (kind capital) and Damageable, cruising
src/perf/standins/turret_standin.gd     Node3D under a capital: a gun or an interceptor, stepped by the director
src/perf/standins/asteroid_field.gd     Node3D: one MultiMeshInstance3D, static sphere bodies by RID, a marker per rock
scripts/fullscreen_check.sh         a layout fullscreen, the 3D at 1080p, under the GPU lock, with the Q20 verdict
```

- **What they are for.** Q19 and Q21 put capital ships, turrets, interceptors, missiles, mines, asteroid fields and a moon's
  gravity in the battles the game must hold, and none of them exist yet (M6, M12, M14). The stand-ins put their load on the
  tick so every M4 task measures against it: bench-only (the runner spawns them; no scenario does), built by code with no
  assets, and replaced by the roadmap's real work. Missiles, beams and mines are T12's.
- **The mix** (`BattleMix`): a profile is a Dictionary of parameters and `counts(profile, n)` gives fighters, capitals by class,
  turrets, interceptors, beams, missiles, mines, asteroids, sides and the area. `typical` is 1 capital in 7 (8 at N 58), two
  sides; `grand` is `round(0.15 N)` capitals, carriers `floor(0.2 c)`, destroyers `round(c / 3)`, four sides. Every run of a
  battle or typical layout prints its mix and writes it in `summary.json` (`mix`, `mix_line`).
- **The layouts.** N counts fighters and capitals. Fights of 24 sit on an 8 km lattice in as many layers as the area's depth
  holds, the player's fight first, 2.5 km ahead. In each fight every side comes in from its own direction (+Z, -Z, +X, -X; the
  player's side, Earth Alliance, from +Z) in a 400 m ball 800 m out, facing in. A side's capitals sit 5 km behind its fights,
  taken in turn, side by side 2.5 km apart, cruising into the fight at 30 m/s. The rock slab (20 by 5 by 20 km, 1 000 rocks of
  20 to 200 m, log-uniform) is centred on the player's fight and clears every hull by 100 m. Its gravity (M6-T07, which
  removed M4's point-source moon, `GravityStandin`) comes from a body of the star system's data: the runner anchors the
  World's frame on a 400 km circular orbit of Epsilon III through the battle's centre (`BenchLayout.gravity_orbit`), so every
  mover feels the tide of a real body (about 0.026 m/s^2 10 km out), and puts the frame's anchor back after. Sides 3 and 4 (`bench_c`, `bench_d`) fly raider and Starfury hulls with their own faction, so the
  runner installs a session `FactionTable` with every pair hostile and puts the game's table and every pool ship's own faction
  back afterwards.
- **Capitals** are Newtonian bodies like ships (no damping; engines re-apply a force every tick that holds the cruise velocity
  and the environment's pull, capped at 2 m/s^2). Their `Targetable` has `kind` capital (new: `Targetable.Kind`, default ship),
  so later scans and broad phases can tell them apart; the scan sees them as ships today. Hull points only, invulnerable in
  the bench like the fighters.
- **Turrets** do not process themselves: the director steps them once per tick at priority -5, after the AI drivers built the
  tick's shared `ContactScan`. A gun asks the scan for the nearest hostile fighter within 4 km every sixth tick (staggered across
  guns; contacts over 50 m are capitals or rocks until the scan carries kinds, T09), turns at 30 deg/s toward the
  `InterceptMath` lead and fires a pulse-cannon bolt through its own `PulseCannonGate` (1 s) only while the aim is within 1.5 deg.
  The bolt is a normal `Projectile` with the capital as shooter, so the hit resolver, the scan's incoming fire and the
  interceptors see it like any other. An interceptor shoots down the nearest hostile bolt within 1.5 km every 0.5 s (staggered
  ticks) by spending it; T12 adds missiles. No turret has a mesh.
- **The asteroid field** draws every rock with one `MultiMeshInstance3D` and collides through one static sphere body per rock
  made by RID (`PhysicsServer3D`), with no mesh or physics node per rock. The scan and the hit and ram resolvers still find hulls
  through `Damageable` nodes, so each rock also has one bare marker `Node3D` with an unbreakable, `hit_by_anyone` sphere hull: the
  scan sees it as a static row (not a ship, no velocity, its radius) and bolts hit it. The field node is shiftable; after a rebase
  `on_rebased` moves the RID bodies. T09's registry and T08's sweep can read rows from the field instead of the markers.
- **Gravity** (M6-T07, D66) is the World frame's residual alone: `WorldFrame.environment_accel` returns it, and the M4 seam
  for a field of the World's own (`environment_field`, the moon stand-in) is gone. Every mover takes it: ships (the flight
  step, natively), capitals (their engines hold it off and the body takes it too), the tier's rows, the core's bolts, and the
  GDScript movers through `HeldPull`.
- **Carrier launches**: every 5 s each carrier (first launches spread over the period) releases one in-play fighter of its side
  to the pool, taken in turn, and acquires one again at its bay with a new brain and 80 m/s along its nose, so N holds and the
  pool's release and acquire run in play.
- **Counters.** `PerfProbe` records the director's own time (`standins`, inside `flight`) and per tick `fighters_near` and
  `fighters_far` (within 10 km of the player, the tier's radius to come), `capitals`, `turrets`, `interceptors`, `beams`,
  `missiles`, `mines` (0 until T12), `asteroids`, `launches` and `sides`; the `perf` provider shows them and a run's summary has
  `entities` (means per tick, launches summed) beside the ship count. A sweep's summary lists them per ship count, and its
  headline is battle's max N when battle was measured.
- **The fullscreen check** (Q20) runs `scripts/measure_fight.gd` with `scene=quiet` and the bench as its console statement,
  fullscreen with vsync off and the chase camera, 20 s after 8 s of warm-up, and writes the verdict: the battle's floor 30 FPS
  and target 60, typical 60 with a frame mean of 12 ms or under. The maintainer's screens are 3840x2160, so a fullscreen window
  is 4K; the check renders the 3D at 1 080 lines (`scale3d=1080p`, the HUD at the screen's size) to measure Q20's 1080p, and
  `FULLSCREEN_SCALE=1` measures the screen's own resolution.
- **Tests**: `test_battle_mix` (the table at 58, 100, 500 and 1 000, scaling, parameters), `test_bench_layout` (seeded plans,
  spacing hull to hull, the 8 km lattice, a quarter of the capitals a side, four sides every pair hostile, the slab clear of
  every ship, the moon), `test_standins` (a gun fires only at hostiles within 4 km and only inside its gate at a limited turn
  rate, an interceptor removes only hostile bolts within 1.5 km, rocks are static rows that bolts hit, a rebase moves rocks and
  capitals, the moon bends a coasting path about 13.5 m in 30 s) and `test_bench` (battle and typical runs write every entity
  count, the factions and stand-ins go afterwards).

### 17.7 The hit broad phase and projectile kinds (T08)

- **Before**, `HitResolver` put every projectile against every active hull each tick (a bounding-sphere test, then the shape
  sweep for the few that passed): projectiles times hulls, so about N squared in a fight (3.7 ms of a 17 ms tick at furball 100,
  300 bolts against 100 hulls).
- **Now** the resolver gathers the tick's hulls and projectiles into packed arrays once and asks `HitBroadPhase` (pure,
  `src/combat/hit_broad_phase.gd`) for the pairs that pass the sphere test, as `bolt * hulls + hull` in ascending order, which is
  the old loop's order. Only those pairs reach the faction, shooter and destroyed checks and the shape sweep, unchanged.
- **Any hull size.** Hulls sit in a grid of five levels (cells of 64 m, 256 m, 1 km, 4 km and 16 km); each goes into the finest
  level whose cell is at least twice its reach, at the cell holding its centre, and each level keeps its largest reach. A
  projectile looks, per level, at the cells its reach plus that largest reach can touch, so a 10 m fighter and a 1 km capital
  are both found from anywhere they reach without filling the fine cells. A look that would cover more cells than the level
  has hulls (a 3 km beam), and a hull that fits no cell (not finite, beyond the top level or the grid), test everything instead.
- **Native and GDScript ran the same grid.** `ScsHitSweep` (`native/src/hit_sweep.rs`) answers; the GDScript code was the
  reference until M4-T37 removed it (its work counts are recorded in `tests/fixtures/parity/hit_broad_phase.json`). Both use the same levels, cells and
  fallbacks and the sphere test in 32-bit vectors with 64-bit scalars in the engine's order, so the pairs and the work count
  (`pairs_visited`) are the same bit for bit. The plan named sort and sweep for the fallback; the same grid was chosen so the
  two paths can be compared pair for pair and count for count.
- **Why nothing changes**: the broad phase returns exactly the pairs the old sphere test accepted, in the old order, so the
  resolver sweeps the same pairs and lands the same hits (`test_hit_scale` compares a seeded melee against a broad phase that
  tests every pair, on both paths). A hit handler that retires a later projectile still stops it, as before.
- **Projectile kinds.** `Projectile.kind` is `bolt`, `beam`, `missile` or `mine`, each with a stand-in hit radius
  (`HIT_RADIUS_BY_KIND`, set by `set_kind`) until roadmap M12 brings the real weapons. The resolver treats every kind alike: a
  sphere of the projectile's radius swept along the segment it flew this tick, so a beam is a projectile that flies its whole
  length in the tick it fires, and a proximity mine a slow one with a fuse-sized radius.
- **The windowed hit spike (AC6)** was not the sweep: `ImpactFlash` built a quad and two materials for every hit, and in a
  window that creation stalled the tick by about 7 ms on many hits. Flashes now share them per bolt colour; the fade is per
  instance (`transparency`), so the look is unchanged.
- **Not moved**: `ContactScan.incoming_fire` still tests every bolt per querying ship inside the native contact field; T15's
  simulation core unifies the two.

### 17.8 The body registry and entity kinds (M4-T09)

```
native/src/body_registry.rs     ScsBodyRegistry: the scan's bodies, read natively in one refresh a tick (removed by M4-T42)
src/ai/body_kind.gd             BodyKind: ship, capital, turret, missile, mine, static, prop; rocks and mines are obstacles
```

- **What it ends.** After cycle 4 the scan's queries were native but the scan itself was still gathered in GDScript every
  tick (`ContactScan.from_tree`: walking the groups and reading about fifteen properties a body), with the broadcast scan
  built the same way and a freed-body check on every `shared` call. On a world with no core, `shared` then came from
  `ContactScan.from_registry`: no per-body GDScript a tick, with `from_tree` as the reference. Since M4-T42 every world
  has a core, so the registry (now the core's own registration, §17.13) is read only through the core; `from_registry`,
  `from_tree`, `from_broadcasters`, `ScsBodyRegistry` and the `gathers` count are gone.
- **Membership** (as built in M4-T09; the core keeps the same rules, §17.13). The registry was told the `targetable` and
  `damageable` groups (`set_members`, the group arrays passed whole) when they changed: `ContactScan` listened to the
  tree's `node_added` and `node_removed` for markers and hulls. A
  pool ship stays in the tree when parked, so play rarely changes the members; spawning and parking do not.
- **The refresh** (the core's first sync since M4-T15). Each tick's first scan called `refresh` once. For every member it asks the engine what
  `Targetable.is_active()` and `Damageable.is_active()` ask (in the tree, visible, processing; a hull's `destroyed` flag only
  for a body with no active marker), then reads the active body's global transform and its `linear_velocity` (a prop's
  marker `velocity`) through the node's own getters, so every value is the one GDScript reads. The plan said
  `PhysicsServer3D` by RID; that differs from the node by a quaternion round trip after any teleport (a spawn, a rebase),
  which breaks bit parity, so the node's getters are used (they are engine calls, not script). The axes are normalised as
  `Vector3.normalized` does it, in 32 bits. Faction, name, kind and radius are read only when a body turns active, when it
  is hidden or shown (each body's `visibility_changed` touches it, which covers the pool's release and acquire in one
  tick), or after `ContactScan.touch(body)` or `invalidate()`. Rows come in group order (markers, then hulls with no
  active marker, deduplicated by body), then the node-less static rows.
- **Hull and selection** are read when a contact is first handed out (`Contact`s are made lazily since cycle 4; the tree
  gather did the same until M4-T42 removed it), so a scan hands out what is true when it is asked, whatever changes between
  its build and its queries (a hit, the console, the player). A driver that changes its ship's selection first calls
  `ContactScan.note_selection`, so this frame's scans still hand out the selection they were built with (M3's behaviour).
- **The broadcast scan** is the core's `select` (the registry's until M4-T42): a row, read now, for each active marker of
  `Targetable.broadcasters()` in that list's order (a body's second marker gets its own row, as `from_broadcasters` gave),
  with each broadcaster's range read in GDScript. A body's hull is its first `Damageable` in group order, which is child
  order, so it is the one `Damageable.of(body)` finds.
- **Kinds** (`BodyKind`). A marker's `kind` property (M4-T07 adds it to `Targetable`) is read as a name or a value; a
  body without one is a ship. `static` and `mine` rows are never contacts: `contacts_for` and `nearest_for` skip them, so a rock field or a mine belt never fills a fighter's twelve. `statics_for(own, at, faction, k)` gives the
  `k` nearest by surface distance (centre distance less radius, equal ones to the earlier row) within the sensor range,
  in scan order; the field searches the cells the range plus the largest static radius reaches. `Perception.statics`
  holds them (setting `ai_nearest_static_k`, 4; 0 = none) and `AiPilotDriver` adds them to avoidance's contacts:
  `AvoidanceMath` treats a contact as an obstacle with its radius and velocity; for a rock or mine its horizon is at least
  the time a sideways RCS burn takes to clear the obstacle's reach (plus `URGENT_SETTLE_S`), so a 150 m rock is seen early
  enough to go round, while ship-sized contacts keep M3's horizon. The fire lane does not read statics.
- **Rows with no node.** `ContactScan.register_static(id, position, radius, kind, faction, world)` adds a rock (by RID) or
  a mine row to the scan, after the bodies, in registration order; `unregister_static`, `clear_statics`. A row belongs to
  the `WorldFrame` it was registered with (its position is in that frame): that world's `rebase` calls
  `shift_statics(shift, self)` and moves only its own rows, once, by the nodes' shift; a row with no world never moves. Ids
  must be unique and not instance ids.
- **NaN radii.** A static whose surface distance is NaN (a NaN radius or position) is never an obstacle.
- **Bad input never panics.** `set_statics` and the field's `set_kinds` check their array lengths, log one error and keep
  nothing; the scan then answers nothing, as for a rejected `load` (it answered from GDScript until M4-T42 removed the
  loops).
- **Still per tick in GDScript:** the bolts' gather for `incoming_fire` (T15 unifies it with the hit sweep's rows).

### 17.9 The native flight step (T10, N4)

```
native/src/flight_step.rs       ScsFlightStep: FlightModel.compute, the SpeedGovernor and the ship's force application for every
                                batched ship in one call, by body RID through PhysicsServer3D
src/ship/flight_batch.gd        FlightBatch: a child of World at physics priority -1; gathers, steps, keeps the outputs; the
                                `flight` console provider
src/ship/ship.gd                a ship is `batched` (every ship but the player's); its _physics_process then only takes the edges
```

- **One call for all AI ships.** After the AI drivers (-10) and before the ships (0), `FlightBatch` packs each batched ship's
  `FlightCommand` (the four group levels, strafe, rot, the track and face directions, the environment acceleration, and the
  flags brake, autotrack, assist and propellant) into packed arrays and calls `ScsFlightStep.step` once. The step reads each
  body's basis and velocities from the physics server (what `RigidBody3D` reads too), runs the model, the governor's gain and
  cap and the hard ceiling, and applies the nozzle forces at their positions, the RCS force and torque, the cap and the
  environment force to the body in the order `Ship._physics_process` applied them. The outputs (the applied force and torque,
  the body-frame forces and torques, the levels, the RCS shares, the flow, the flags) come back as two packed arrays; a ship
  reads its row only when asked (`applied_force()` for the ram resolver, `get_flight_output()` for the glow and the audio),
  and the batch draws the reaction mass when the tank is finite. The per-nozzle `nozzle_forces` of a batched ship's output
  stay empty: nothing reads them for an AI ship.
- **The player's ship never joins** (`console_owner` switches `batched` off in `_ready`), so the GDScript path stays the
  reference and the player's feel is untouched. Any ship can be taken out (`batched = false`). Until M4-T37 a library without
  the class, `perf_native` off or `perf_native_flight` off left every ship on its own model; M4-T37 removed both settings,
  the game refuses to start without the library, and the batch always flies the AI ships.
- **The assist's state follows the ship.** `FlightAssist.pod_yaw_smoothed` is the model's only state; the native slot keeps
  its own copy. When a ship changes path the value is carried over (to native at the next gather, back to the model at the
  next GDScript tick), and `set_assist` and `reset_to` clear both.
- **Parity is bit for bit.** The step repeats GDScript's arithmetic: 32-bit vectors, 64-bit scalars, a scalar rounded to 32
  bits before it scales a vector, Godot's `Vector3` operator order, its `clampf`, `minf`, `maxf` and `signf` comparisons, and
  the same `exp` and `atan2` (both paths call the host's libm). `test_flight_step` runs 10 000 seeded commands and states per
  ship type through both and finds no mismatch in any field; `test_flight_batch` flies a batched ship and its GDScript twin
  through one position (collisions off: Jolt rounds the torque of a force at a point against the body's world position, so
  twins at different positions can never match bit for bit) and finds the same velocity, spin, track and applied force.
- **Entity-type-agnostic.** A slot is a spec (mass, thrusts, gains, limits, inertia, maxima) and a layout (any number of
  nozzles in the four groups, their positions and exhausts, the group torque axes), so a capital ship's or any other
  `ShipSpec` and hardpoints register the same way; nothing in the step is sized for a fighter. `register` snapshots the spec,
  mass included: anything that changes a ship's mass or thrust at runtime (burnt fuel, damage, a capital ship's modules) must
  register the ship again (`FlightBatch.join` on a joined ship does that).
- **Bad input never panics.** `register` checks the arrays line up and returns -1 after one error; `step` checks the per-ship
  array sizes and that every slot is known, and on a mismatch logs one error, applies nothing and returns false, so nothing
  flies that tick (M4-T44 removed the GDScript fallback that flew each ship's own model). A body not in a space (a parked pool ship) gives a row of zeros and no force.

### 17.10 Far-ship dots and the node diet for AI ships (T11)

History (M4-T31): the node diet below was measured on the M3 renderer. T31 removed its level nodes, their pose sync and the depth
proxy; a lean ship now draws its hull on one `Hull` node (11 nodes of its own besides its guns, was 16), and the far dot's colour is
the manifest's `mesh.mean_albedo` (M4-T30d). The far dot itself is unchanged.

```
src/ship/ship.gd                 `lean` (AI ships): no cockpit, anchor or fallback node; collision shapes as shape owners;
                                 `set_far_dot` hides the ship's visuals and hands it to the world's FarDots
src/ship/thruster_visuals.gd     `instanced`: every plume of a ship is an instance of one multimesh (cone and core in one surface)
src/ship/running_lights.gd       `instanced`: the three markers are instances of one multimesh (the colour in the custom data)
src/ship/hull_depth_proxy.gd     (removed with the splats, T31) the proxy draws the fallback mesh merged into one surface; on a lean ship it also draws the
                                 fallback mesh itself
src/rendering/lod_switcher.gd    the far level: past settings.far_ship_dot_m from the camera an AI ship is a dot
src/rendering/far_dots.gd        FarDots: one MultiMeshInstance3D under World, a point per far ship, updated each frame
assets/shaders/far_ship_dot.gdshader   the dot: the hull's angular size with a 1 px floor, dimmed by the inverse square under it
```

- **Why.** A pooled AI Starfury was 112 nodes and a raider 74 (the player's 123): a `CollisionShape3D` per hit volume (14 and
  13), a `Node3D` and two mesh instances per plume (24 and 4 plumes), three marker meshes, the cockpit interior and anchor, a
  fallback mesh node. The rebase shifts and resets every one of them, the body sync propagates every transform, and each
  visible surface is a draw call: the depth proxy alone drew the hull's 13 material surfaces (9 on a raider). Measured on the
  GPU, an idle AI ship in view cost about 15 draw calls.
- **The lean set** (`ShipAssembly` option `lean`, on for every pool ship, never the player's): the body; the collision shapes as
  shape owners of the body (`create_shape_owner`, the same shapes, contacts and ray hits, no node); the splat levels and their
  `SplatPoseSync`; one `HullDepthProxy` node that draws the proxy while the splats are drawn and the fallback mesh with its own
  materials when the fallback is on; `ThrusterVisuals` on the body as one multimesh; `RunningLights` as one multimesh; the guns
  (a marker and a flash per muzzle, the weapons' own) and the gameplay components (`Targeting`, `AiPilotDriver`, `Damageable`,
  `Targetable`, `LodSwitcher`). A Starfury ally is 19 nodes (112 before) and a raider 24 (74): 16 and 16 besides
  their guns' muzzles and flashes, the plan's bound. The player's Starfury stays at 123.
- **One surface per part.** The proxy is the fallback mesh merged into one surface of positions and normals (all its shader
  reads), made once per mesh and shared, for every ship (the player's too: the picture is the same). The instanced plume is the
  unit cone and the core disc in one surface with one material: the core texture's radial falloff is baked into the disc's
  vertex colours, the disc sits at a share of the length, and the level is the instance colour's alpha (the nodes used the mesh
  `transparency`). The markers share the quad and the shader of §7.3, the colour read from the instance's custom data
  (`use_instance_tint`). So a near AI ship draws three surfaces; measured on the GPU, 20 idle raiders in view add 45 draw calls
  (the probe counted 2.25 a ship, but it does not count the markers' multimesh, so the real figure is higher; with splats a near AI ship measured about 5 draw calls), against about 15 a ship before. The plan's target of under 3 was not met: each visible splat node adds about 2 calls (T27 looks at it).
- **Far dots** (§14.4's last level). Each frame the `LodSwitcher` measures the camera's distance; past
  `settings.far_ship_dot_m` (3 000 m) an AI ship is a dot: `Ship.set_far_dot` hides its splat levels, proxy, plumes, markers
  and guns, and `FarDots` (one `MultiMeshInstance3D` under `World`, never culled) draws it as one instance, so every
  far ship together is one draw call. It shows its level again at 90 % of the distance (`LodSwitcherMath.far_dot`), never
  flapping on the line. The dot is the hull's opacity-weighted mean paint from its coarsest level's splats, lit as §7.3's
  lit side (1.2, applied before the sRGB to linear step as GDGS applies it), at the hull's angular size with a 1 px floor
  and dimmed by the inverse square under it, like a running light; alpha-blended and depth-tested, so a nearer hull's proxy
  hides it. Each frame it writes every shown ship's drawn pose in World-local metres. It is shiftable, so a rebase moves the
  dots with everything else (no frame shows one at its old place); on `rebased` it goes back to the World's origin and moves
  the dots instead, so its own offset never grows. A parked ship draws none, a forced level (`lod`) and the player's ship never become dots, and a ship back from the
  pool starts drawn in full. Headless there is a camera too, so dots are taken there as well; it costs the frame, not the tick.
- **What it does not change.** Ships, physics, contacts and the gameplay components are the same; the player's ship keeps
  every node. The plumes' lights stay emitters on the plume positions (the ship's `ThrusterVisuals` is their anchor), and a
  hidden instanced ship's lights go dark. The look of the plumes, markers and dots is the maintainer's (H).
- **Console**: the `lod` provider's `far_dots` counts the ships drawn as dots; setting `far_ship_dot_m`.

### 17.11 Missile, beam, interceptor and mine stand-ins (T12)

```
src/perf/standins/missile_standin.gd   MissileStandin (RefCounted): a missile's steering, proportional navigation, the launch
src/perf/standins/beam_standin.gd      BeamStandin (Node3D under a capital): fires a 3 km hitscan beam as a one-tick projectile
src/perf/standins/mine_standin.gd      MineStandin (Node3D): every mine of the battle as rows, the trigger cadence and the blast
src/weapons/projectile.gd              + `steering` (a guided projectile's hook), `fire_beam` (a beam's one tick)
src/combat/hit_resolver.gd             + a beam is retired after the resolve that swept it
```

- **What they are for.** The rest of Q19's and Q21's weapons, so the hit sweep, the interceptors and the per-entity counters are
  measured with every kind: guided missiles, beam lasers, interceptors that also hunt missiles, and proximity mines. Bench-only
  like T07's stand-ins, built by code with no assets, replaced by M12's weapons.
- **Missiles** are `Projectile`s of kind missile (hit radius 2 m) whose `steering` hook gives the tick's velocity before the
  projectile moves: proportional navigation (gain 4) at a constant 350 m/s, the turn limited to 0.6 rad/s (about 21 g), for 20 s.
  The hook's object rides on the projectile (`guidance`), because a `Callable` does not keep a `RefCounted` alive. The director
  keeps the mix's count in flight (`missile_target`, 0.4 per fighter): at most two launches a tick, from the capitals in turn, each
  at its capital's strike target, the nearest hostile fighter within 6 km (looked up again every 30 ticks), aimed at the lead.
  Without its target a missile flies straight on until its lifetime ends. The hit resolver sweeps it like any projectile.
- **Beams** are two emitters per capital (`BeamStandin`), each firing every 2 s at its capital's strike target when that is within
  3 km. A beam is a `Projectile` of kind beam laid by `fire_beam`: its whole 3 km segment is its one tick of flight (it does not
  move in its own tick), so the resolver sweeps it through the hit broad phase in the tick it fires and the earliest hit along the
  segment, the first hull, takes it. The resolver retires every beam after its resolve, hit or not; beams are fired after the
  scan is built, so they never reach the scan's incoming fire. A 3 km look covers more cells than the grid holds hulls, so the
  broad phase tests a beam against every hull (§17.7); at 0.5 Hz per emitter that is about one beam a tick at battle 300.
- **Interceptors** now take candidates from the hit broad phase: once a tick the director gathers every projectile in flight but
  beams and asks the grid which lie within 1.5 km of each interceptor due (the interceptors as hulls of 1.5 km reach, the
  projectiles as points), then each interceptor shoots down the nearest hostile missile in reach, else the nearest hostile bolt.
- **Mines** are rows in one `MineStandin` node (no node per mine, one `MultiMeshInstance3D` draws them): 50 m trigger, 100 m blast,
  200 hull points. The layout lays the mix's mines (`max(100, N)`) in belts, each fight's share split between its sides, each side's
  on a 90 degree arc 1.5 km out toward its own direction (between its fighters' start and its capitals), 150 m deep and high either
  way, none inside a trigger of a starting hull. Each tick a third of the mines (by index) ask the grid for a hull hostile to
  their layer whose sphere comes inside the trigger; one that finds one goes off, applies a `HitInfo` with cause `mine` to every
  hull whose sphere lies within the blast (friend or foe) and is removed. It is laid again in its place after 10 s, so the belts
  hold the mix over a run. The hulls are the director's per-tick list of what flies (the pool's fighters, the capitals, the
  player). Mines are not in today's contact scan: they have no `Targetable`, and T09's body registry takes them as rows of kind
  `Targetable.Kind.MINE` (`position_of`, `faction_of`, `kind`, `TRIGGER_RADIUS_M`, and the `laid` and `detonated` signals).
- **Counters**: `beams` (emitters), `missiles` (in flight) and `mines` (in play) per tick, beside T07's; a run's summary has
  `weapons` (launches, missiles shot down, beam shots, mines set off over the window) and the director's cost by part
  (`parts_us`: gather, engines and guns, interceptors, beams, missiles, mines, launches) with the missiles' steering, which runs
  in the projectiles' own tick.
- **Tests**: `test_missile_guidance` (a crossing fighter hit within the lifetime at the turn rate and missed at a tenth of it, the
  turn per tick limited, the speed held), `test_mine_trigger` (hostile only, the trigger from a hull's surface, the native and
  GDScript grids agree with the plain definition, the blast's reach) and `test_standins` (a beam hits the first hull and none
  behind it and is gone after its tick, beams at 0.5 Hz within 3 km, an interceptor takes a missile in reach first and never
  anything outside 1.5 km, a missile hits a crossing fighter through the resolver, the count in flight holds, a mine goes off on
  a hostile, never a friend, hurts every hull in its blast and is gone, checks every third tick and is laid again, a rebase moves
  the mines), `test_bench_layout` (the belts hold the mix per side, on their arcs, clear of every ship, seeded) and `test_bench`
  (a battle run counts beams, missiles and mines).

### 17.12 Jolt collision layers and far-ship interpolation (T14)

```
src/ship/collision_layers.gd        CollisionLayers: the layers, the masks by kind, and `collide` (the either-way rule)
src/ship/ship.gd                    layers by kind at `_ready` (the lean AI ship is a fighter, any other ship the player's kind);
                                    a far dot's body is not interpolated
src/perf/standins/capital_standin.gd, asteroid_field.gd   the capitals' and the rocks' layers
src/combat/ram_resolver.gd          a rigid pair whose layers do not meet in Jolt (none today) goes through the swept test at any speed
src/world/world_frame.gd            `last_settle_resets`: the nodes the end-of-tick interpolation reset reached
```

| kind | layer | mask (collides with) |
|---|---|---|
| player (a ship that is not lean, and any body left on the default layer) | 1 | everything |
| AI fighter (a lean ship) | 2 | player, fighter, capital, rock |
| capital | 4 | player, fighter, capital, rock |
| rock (the RID body of T07's field) | 8 | player, fighter, capital |

Two bodies collide when either mask holds the other's layer (Godot's rule; the masks above are symmetric, so it does not
matter). Everything the table does not list is as before: a bolt (a `Node3D` flown by hand, §17.7) and a mine (a row of
`StaticRows`, §17.16) have no Jolt body, so they have no layer.

- **Fighters collide with fighters (Q33).** The first build took AI fighters out of each other's mask and let the ram resolver's
  swept test do their collisions; the maintainer ruled against it: two fighters that pass through each other, with no momentum
  exchanged and only an inelastic ram, break Newtonian motion, and it bought no measured time (the physics stage did not fall).
  So any two AI fighters, allies included, get Jolt's contact response as before layers existed, and the ram resolver is the
  base's for them: Jolt's contacts decide below tunnelling speed, the sweep above it. `_jolt_can_touch` stays as a guard for a
  rigid pair whose layers do not meet, none of which exist today. The player keeps the default layer and collides with everything.
  A ship that is given layers before it enters the tree keeps them. What the layers do now is name the kinds, keep a rock from
  pairing with a rock, and leave room for a later kind (debris, props) to opt out.
- **Capitals and rocks.** Capitals pair with every kind (a fighter into a capital is a Jolt contact as before). T29 made rocks
  rows with no node; they are still RID static bodies in Jolt (their row id is the body's RID id), so a fighter into a rock still
  bounces off it in Jolt and still takes the prop ram of §17.16 from the rock's row. Their layer only keeps rocks out of pairs
  with each other.
- **The settle.** A rebase inside a tick resets the interpolation of every visible, interpolated shiftable node at the end of the
  tick (§10, `WorldFrame._settle`), and `reset_physics_interpolation` walks the node's whole subtree. A far dot's ship
  (`Ship.set_far_dot`, §17.10) is drawn by `FarDots` from its tick pose, so its body is set to `PHYSICS_INTERPOLATION_MODE_OFF` and
  the settle skips it, subtree and all; back near, the mode returns to inherit and the interpolation is reset once. A dot moves
  at the tick rate, by one tick of travel at most (2.5 m at 150 m/s, 10 m at 600 m/s; a few pixels at the 3 km a dot starts at, (H)). `WorldFrame.last_settle_resets`
  counts the nodes the last settle reached.
- **Settings.** `collision_layers` and `far_ship_interpolation_off` were the switches for measuring either half alone; M4-T37
  removed them, so every body takes its kind's layers and a far dot is never interpolated.
- **Measured** (battle 300 and 500, Cycle log, M4-T14): the physics stage and the tick median are unchanged within noise; the
  rebase shift falls by 1.5 to 2 ms, a third, which is the far ships' interpolation alone.
- **Tests**: `test_collision_layers` (the table, two fighters meeting report a Jolt contact and exchange momentum,
  allied fighters collide, 30 m/s costs each at least half its hull once as a contact ram, 600 m/s takes the swept ram, a 4 m/s
  bump hurts nobody, the player bounces off a fighter, a capital and a rock pair with a fighter, a bolt and a mine have no body,
  the settle walks only the interpolated nodes, a far ship is left out of it and returns) and `test_fighter_melee` (a seeded melee
  of eight fighters, 2 966 contacts and 11 rams, whose digest equals the base's byte for byte; since M6-T18 the melee and
  its contact count are pinned in `test_core_state`).

### 17.13 The native core (T15)

```
native/src/sim_core.rs           ScsSimCore: one store of rows for every simulated entity, filled from the engine at the tick's
                                 sync points and read by every native kernel
native/src/rows.rs               Rows, Bolts and the row flags: the plain row tables, the only thing the kernels import from the crate
native/src/kernels.rs            the kernels: every query and step over the rows (contact, sweep, ram, flight), no way to the engine
native/src/ram_phase.rs          ScsRamPhase: the ram resolver's broad phase on the core's rows (RamBroadPhase, in tests/fixtures/, the reference)
native/src/body_registry.rs      ScsBodyRegistry: the core without its facade, for the scan's registry path (removed by M4-T42)
src/perf/sim_core.gd             SimCore: the facade; a node under World at priority -11 (sync_in) with an internal child at
                                 2 000 000 (sync_out); the `core` console provider
src/ai/contact_scan.gd, src/combat/hit_broad_phase.gd, src/combat/hit_resolver.gd, src/combat/ram_resolver.gd,
src/ship/flight_batch.gd         the four classes read the core (their own loads, for a world with no core, went with M4-T42)
```

- **What it is.** Phase 1 left four native classes, each loading its own copy of the world every tick: the registry's
  snapshot copied into the scan (1 000 rock rows included) and then into the contact field, the hit resolver's two gathers
  (hulls and bolts) packed and handed to the sweep, the flight step's direct-state read per ship, and the ram resolver's
  Dictionary per hull. The core is one struct-of-arrays store in the crate: a row per body (kind, radius, faction, flags,
  position, velocity, basis, angular velocity, name, hull, a handle), the static rows after them, the bolts in a table of
  their own (position, velocity, last step, faction, shooter, kind, hit radius), and rows with no node for what T20 adds
  (`add_row`, `row`: kind, id, faction, radius, flags, position, velocity, basis, angular, command, state). The kernels
  (`ScsContactField` queries, `ScsHitSweep.pairs_core` and `kept_pairs_core`, `ScsRamPhase.pairs`, `ScsFlightStep.step_core`)
  read the rows through `bind()` and never call the engine; T16 to T18 and T20 put their kernels beside them.
- **The tick's sync points** (§15.3's order with the core): `SimCore` at -11 does `sync_in` before the first driver (-10)
  builds the scan: every member body read once through the nodes' own getters (the registry's reads, M4-T09, plus the
  angular velocity), the static rows taken again from `StaticRows` when its version changed, the bolts read. The flight
  batch (-1) reads each ship's basis and velocities from its row (nothing moves a body between -11 and -1) and applies the
  forces through the physics server as before: the one write per ship per tick, kept at -1 because Jolt rounds the torque
  of a force at a point against the body's world position, so applying after the World's rebase (0) would change the bits
  on a rebase tick. The hit resolver (200) asks for the bolts again (`ensure_bolts_synced`), since they moved at 0, and the
  bodies touched since the first sync are read again then: a ship back from the pool gets its row (flagged late, at the
  end, so the scan's indices hold), a parked or destroyed one loses its hull flag. The ram resolver (210) reads the same
  rows. `SimCoreOut` at 2 000 000 does `sync_out`: it closes the tick's engine-call count and is the seam where T17's
  commands and T21's tier rows write back. A rebase shifts the node and bolt rows once (`rebased`, the same 32-bit add
  `global_translate` does); the static rows follow `StaticRows`' own shift at the next sync.
- **Lifecycle.** Members are registered once (`set_members`, when the `targetable` or `damageable` group changes) and keep
  a slot; a row's handle is its slot and a generation that grows each time the body turns active, so a ship back from the
  pool is a new row to anything holding the old handle (`row_of` answers -1 for it). Faction, name, kind, radius and the
  destroyed flag are read on activation and on `touch` (the facade touches a body when it is hidden or shown and when its
  hull emits `destroyed`); a hull-only body reads its destroyed flag every tick, as the tree gather does.
- **Parity is bit for bit** with each class's own load (the loads went in M4-T42; their outputs are recorded): the scan's
  rows equal the tree gather's (the registry's rule; `TreeRows` in the tests reads the tree the same way), the
  field reads the same values from the rows, the sweep and the ram phase build the same spheres and boxes from the rows
  in GDScript's precision and order (the hull rows in the `damageable` group's order, so ties fall the same way), the
  flight step reads the basis Jolt wrote back to the node after its last step, which is what the direct state holds too
  (`test_sim_core`, the seeded melee's digest, now in `test_core_state`, the seeded outcome runs in the Cycle log). What differs: a ship
  teleported without a visibility change between -11 and 200 (the console only) is swept at its -11 pose that tick, and the
  flight step reads a launched ship from the physics server on its launch tick (`fallback_reads`), as before.
- **The kernels hold no way to the engine.** Every query and step over the rows lives in `native/src/kernels.rs`
  (`contact`, `sweep`, `ram`, `flight`), and the row tables they read in `native/src/rows.rs` (`Rows`, `Bolts`, the row
  flags: plain columns of value types). The four classes are shells that bind the core and hand the results over; the
  flight step applies what its kernel gives through the physics server, the one engine write outside the sync points.
  `test_sim_core` reads both files line by line and fails on: a forbidden token (`Gd<`, `Variant`, `InstanceId`,
  `singleton`, `PhysicsServer`, a `godot_*` macro, `#[func]`, `GodotClass`, a property read `.get(&` or `.call(`, `Node`,
  `RigidBody`, the `Scs` classes, `pub use`, a block comment, `unsafe`; in rows.rs also `Object`, `Array` and `Packed`), a
  `use` outside the allow-list (`std::`, `godot::builtin::Vector3` or `{Basis, Vector3}` and `crate::rows::{Bolts,
  FLAG_RIGID, Rows}` for the kernels; `std::` and `godot::builtin::{Basis, GString, Vector3}` for the rows), and any
  `crate::`, `super::` or `godot::` path on a line that is not such a `use`. The task's report shows it failing on an
  injected `Gd<Node>`, an inline `crate::sim_core::ScsSimCore` call, a `super::` path and a `godot::meta::` path. What the
  test does not do: run the kernels under a call tracer; the claim rests on the source check and on the shells being the
  only callers. The engine seam test also checks that a tick full of queries and steps costs the sync points the same
  engine calls as a quiet tick (the sync reads nothing again for them) and that the flight step read no ship from the
  physics server. What is counted: the sync points' calls (`core.sync_calls`, one per engine getter, so they grow with the
  bodies and bolts) and the flight step's fallback reads for ships without a row (`core.fallback_calls`,
  `flight.fallback_reads`, 0 outside launch ticks). T18's threads rest on the same property: a kernel takes its rows and
  its own scratch (the flight kernel writes its nozzle forces into the buffer the caller passes) and shares nothing.
- **Settings and console.** `perf_native_core` (off = each class loaded its own copy) went with M4-T37: a world with a
  core always uses it. Provider `core` (`path`, `rows`, `bodies`, `statics`, `bolts`, `syncs`, `sync_us`, `bolts_us`,
  `core_sync_us`, `snapshot_us`, `select_us` (M5-T35), `sync_calls`, `fallback_calls`, `attribute_reads`, `touched`); `combat.source` and `combat.gather_us`, `ram.source` and
  `ram.gather_us`, `flight.source` and `flight.fallback_reads` say what each class read.
- **Tests**: `test_sim_core` (the lifecycle, the rebase, the round trip, the four classes' parity against the recorded
  loads, the engine seam) and the files of the four classes.
- **Every world attaches the core, one hull read (M4-T42).** Until M4-T42 only a world with batched ships had a core
  (`FlightBatch.attach` made it), so free flight (no ship pools), bare test worlds and their resolvers each read the tree
  their own way. Now `WorldFrame` attaches its `SimCore` as it becomes ready, and the stand-ins attach it when they get
  capitals or mines. One world per tree (the game only ever has one): a second world, while the first world's core is
  live, is refused its core with one error, and nothing takes over when the core's world leaves. The paths for a world
  with no core are gone: the body registry with `from_registry` and `from_tree`, the hit
  resolver's walk of hulls and bolts, the ram resolver's walk and its contact read per hull, the flight batch's server
  read, the contact field's GDScript query loops, and the resolvers' `use_core` and the scan's `use_native` switches. A
  tree with no world has no core: its scan sees nothing, its resolvers resolve nothing (`source` none) and its flight
  batch lets every ship fly its own model; the first ask about bodies there warns once a run
  (`SimCore.no_world_warnings`). The flight step still reads a ship with no row (back from the pool on its launch tick)
  from the physics server. What differs from the old walks: a hull that enters the tree after the core's sync at -11 has
  no row in that tick's hit sweep or ram rows (the walks at 200 and 210 saw it at once); battles have run this way since
  T15, it lasts one tick, and pooled ships come back through `touch`. The tests compare
  the core's rows with `TreeRows` (a node-by-node read of the tree kept in `tests/fixtures/`), and the removed paths'
  recorders are stored reads of `tests/fixtures/parity/` (`test_every_world_core`).

**The pilot kernels (T16, N2).**

```
native/src/kernels.rs (pub mod pilot)   avoid, fire_lane, context_lists: AvoidanceMath, FireLane and AiContext.refresh's split
native/src/pilot_kernels.rs              ScsPilotKernels: binds the core's rows (or rows loaded from arrays) and hands answers over
```

- **What moved.** The three loops over a thinking ship's contacts: the avoidance filter over its contacts and statics,
  the fire lane, and the hostile and friendly split of `AiContext.refresh`, each a kernel over the core's rows. The first
  two answer the game through one native call per question; the GDScript stays the reference and answers whenever a
  perception is not on the rows. The split (`context_lists`) is not called from GDScript: handing its five lists back
  costs more than `AiContext.refresh`'s own loop, so it waits for T17's native brains.
- **How a ship reaches its rows.** A core scan's rows are the core's, in the same order, so the indices the scan picked a
  list from name the core rows of its contacts: `ContactScan.picked_rows` holds those of the latest list handed out. The
  driver puts them in the perception beside `contacts` and `statics` (`contact_rows`, `static_rows`), with the scan's
  `pilot_kernels()` and the ship's `relation_row` (its `Factions.Relation` to each faction of the core's table, made once
  per faction per scan, since the kernels never call `Factions`). `Perception.on_rows()` is true when the kernels are there
  and both row lists line up with their lists.
- **The rows are frozen from the sync to the last driver** (the contract the kernels, T17 and T18 rest on). The scan's
  contacts are copies of the rows as of the scan; the kernels read the live rows. `ScsSimCore.rows_version` grows on every
  sync, resync of touched bodies and rebase shift, the scan notes it when taken, and `pilot_kernels()` gives nothing once
  it moved (asked on every call), so a resync or rebase later in the same frame (a test, the console, a bench hook) sends
  that tick's remaining questions to the perception's own lists (the GDScript until M4-T42). In the game's tick order
  nothing changes the rows between -11 and the drivers' end. `ContactScan.pilot_kernels_on`, the test seam that paired
  the kernels alone against the GDScript, went in M4-T42.
- **The facades.** `AvoidanceMath.filter_seen(p, radius, v_des, exempt_id, seed)` (the driver), `FireLane.clear_seen(p,
  aim, range, target)` (the attack brain and the slash) ask the kernels over the core's rows when the perception is on
  them; otherwise (M4-T42) the kernels read the perception's own lists loaded as rows (`PilotRows`: row i the i-th
  contact, with a faction of its own whose relation is the contact's). `AvoidanceMath.filter` and `FireLane.clear` take a
  plain list the same way. The GDScript loops they matched bit for bit went in M4-T42, their answers recorded first
  (`pilot_kernels.json`, the facades case of `pilot_kernels_in_play.json`). `AiContext.refresh` stays its own GDScript
  loop (faster than taking the kernel's arrays apart).
- **Bit for bit.** The kernels repeat the GDScript's arithmetic: 32-bit vectors, 64-bit scalars, a scalar rounded to 32
  bits before it scales a vector, division where the engine divides, the engine's `Basis(axis, angle)` for the tie's turn
  (`cosf` and `sinf`, as the engine calls them), and the tie angle in the engine's `deg_to_rad` form (`x * (PI / 180)`,
  checked bit for bit through `ScsPilotKernels.tie_angle`). The tie-break is passed in as `hash(seed)` from GDScript, so the kernel
  holds no hash of its own. `test_pilot_kernels` compares the kernels with the recorded GDScript answers on seeded contacts (ties on top of the ship and on a dead
  centre course, the margin, matched velocities, rocks and mines, lanes grazed at their edge), and
  `test_pilot_kernels_in_play` on the core's rows and through the driver.
- **Thread-ready (for T18).** Each kernel is a pure function of the frozen rows and one ship's inputs: no statics, no
  caches written during a pass, any tie-break passed in; `context_lists` writes only the output struct its caller owns.
  The module sits in `kernels.rs`, under the same engine-free guard as the other kernels. The shell's
  `ScsPilotKernels.context_lists` shares one scratch per shell (one shell per scan), so T18 calls the kernel with a
  `Lists` per ship, never that method from several threads.
- **What it costs.** Per call on a 13-contact perception: avoidance 1.35 us native against 4.0 in GDScript, a lane check
  0.83 against 3.0, the context split 3.8 against 3.4 (its five result arrays cost more than the short loop, hence not
  called). No measurable change in the think stage (Cycle log, M4-T16): the per-ship plumbing costs about what the
  kernels save, and the brains and the scan queries are what a think pays for.

**The weapon kernels (T20).**

```
native/src/weapon_kernels.rs      the kernels: a gun's pick, aim and gate, an interceptor's pick, a capital's strike target,
                                  a missile's guidance, a mine's trigger and blast; plain data in and out, no engine type
native/src/weapon_rows.rs         ScsWeaponRows: the turrets, strike state and mines as rows with no node, stepped over the
                                  core's rows once a tick (`step`, `mine_step`, `blast`) and per missile (`steer_missile`)
src/perf/native_weapons.gd        NativeWeapons: binds the stand-ins to the rows, keeps the hostility table, hands state back
src/perf/standins/                the director, turret, missile and mine stand-ins: the native path beside the reference
```

- **What moved.** Every per-tick loop of the battle's non-fighter weapons: each gun's pick (every sixth tick, staggered),
  aim step and fire gate, each interceptor's pick among the projectiles in reach, each capital's strike target and the
  beams and missile launches that use it, the mines' trigger checks and a blast's hulls, and a missile's proportional
  navigation. The director's two gathers (every flying hull and every projectile, 2.5 ms at `battle` 500) go too: the
  kernels read the core's rows and bolts. Until M4-T37 the GDScript stand-ins stayed the reference behind
  `perf_native_weapons`, and either path carried on from the other's state. M4-T37 removed the setting and the GDScript
  step; the stand-ins step only on the native rows, and their parity tests compare with recordings in `tests/fixtures/parity/`.
- **Who does what.** One `ScsWeaponRows.step` a tick decides, in the GDScript's order, which guns fire (with each bolt's
  start and velocity), which projectiles the interceptors shoot down, which beams fire at what, and which capitals launch
  at whom. The director then does it: it spawns the bolts, beams and missiles with the stand-ins' own code, spends the
  projectiles, and steps the capitals' engines and the carriers' launches as before. `MineStandin.step_native` asks
  `mine_step` for the mines set off and `blast` for each one's hulls, and still lays, retires and hurts. A missile's
  steering hook asks `steer_missile` for its velocity from its target's row. Every engine write stays in GDScript.
- **When the rows step.** Every tick the core synced: a body touched since the sync (hidden, shown or destroyed, so its row
  is stale) is read again first (`resync_touched_now`); with no core nothing steps. A missile
  whose target was touched reads the touched rows again and asks once more (M4-T44); with no core to read it flies
  straight on. In the game's tick order the director runs at -5,
  after the sync and before anything moves or is touched, so the rows step every tick of a battle.
- **Frozen rows.** The kernels keep no index into the rows between calls and cache nothing across a sync: each call looks
  its capitals and targets up by body id in the rows as they are, and the mines' grid is over their offsets from the belt's
  node, which no sync or rebase changes. A resync or a rebase between the sync and a call therefore leaves the answers
  equal to the GDScript's (the rows move with the nodes, `test_turret_kernel` rebases between the two). `rows_version` is
  not needed for that; a touched body is what makes a row stale, and the director checks for it.
- **Bit for bit.** The kernels repeat the stand-ins' arithmetic: `InterceptMath.solve` in 64 bits, the limited turn as the
  engine's `angle_to` (`atan2f`) and axis-angle `rotated`, the gate as `PulseCannonGate.update` with one muzzle, a turret's
  place as the engine composes a child's transform (`basis.rows[i].dot(offset) + origin`), proportional navigation with
  a scalar rounded to 32 bits before it scales a vector, and the same comparisons (`<` and `<=`) and tie-breaks. Hostility
  comes in as a table by the core's faction indices, built in GDScript from `Factions` when another table is active, the
  core knows a new faction or the active table changed a relation (`FactionTable.revision`, which the console's `relation`
  bumps). A blast's hulls come back in the core's `damageable` order; `MineStandin.step_native` then hurts them in the
  order the GDScript's mines walk them (the pool's ships, the capitals, the player, gathered only on a tick a mine goes
  off), and only those, so hit signals and kills fall in the same order on both paths. What differs: a capital's strike
  target walks the hulls in the core's order, which only matters for two hostile fighters at exactly the same squared
  distance; a target that leaves the tree (not hidden: removed) between the sync and the missile's step keeps its row for
  that tick.
- **Thread-ready (for T18).** Each kernel is a pure function: `retarget`, `aim_gun`, `gate`, `intercept_candidates`,
  `strike_target`, `steer`, `mine_hits` and `blast` read the frozen rows (or a turret's, mine's or missile's own inputs) and
  return a value or fill the output their caller passes. No statics, no interior mutability, no caches written during a
  pass. Two steps are sequential by nature and stay in the shell: the interceptors' resolve (each takes the best candidate
  not yet shot down this tick, `intercept_pick` over a per-tick spent mask) and the launches' turn round the capitals; T18
  runs the per-row parts in parallel and those two walks after. The shell's scratch (fighter rows, candidates, the spent
  mask, the mines' hits) is per shell.
- **Tests**: `test_turret_kernel` (the aim maths on seeded inputs, a seeded miniature battle logged tick by tick on both
  paths: picks, axes, aim errors, gate times, bolts, kills, beams and launches byte for byte, also across a rebase between
  the sync and the step and across native, GDScript, native in one run), `test_missile_kernel` (the guidance on seeded
  inputs, seeded flights at a weaving target side by side, a target hidden after the sync, no core), `test_mine_kernel`
  (hulls within a millimetre of a trigger's edge, a carrier's reach across the grid's slabs, a blast on pooled ships in
  the pool's order, a belt that goes off and is laid again on the same ticks, hits compared in the order they land),
  `test_weapon_rows_battle` (a seeded 30 s `battle` at 100: hits within 10 %; in one process the numbers follow the run's
  place, not the path: the first run gives the same counts on either path, and so does the second), and `test_sim_core`'s engine-free check
  of `weapon_kernels.rs`.
**The brains in native code (T17).**

```
native/src/brain_maths.rs        PilotSteering, InterceptMath, the AiTemperament tables, the five Manoeuvres, Godot's hash([seed, label])
                                 and its RandomNumberGenerator, op for op (engine-free)
native/src/brain_behaviours.rs   AiContext.refresh, AiPilot's scoring and selection, the nine behaviours with AttackBrain and
                                 AttackSlash, the driver's avoidance and re-seek: one think as a pure function of the rows (engine-free)
native/src/v3.rs                 the one home of the 32-bit vector and basis maths the kernels and the brains share (engine-free)
native/src/brain.rs              ScsBrains: the host; one slot per AiPilot over the core's rows, the think's packed output
src/perf/native_brains.gd        NativeBrains: the host's facade, one host per core; the nearest-k settings pushed to it
src/ai/ai_pilot.gd               the facade: with the perception on the rows, try_think_native; else today's code (the reference)
src/ai/ai_pilot_driver.gd        the native path: a perception without contact lists, the finished command back, no own avoidance
```

- **What moved.** The whole think of an `AiPilot`: the lists the driver picked (the nearest k with the keeps, the nearest
  statics, the incoming fire and the broadcasts, through the contact kernels over the brain host's own grid of the rows),
  `AiContext.refresh`, the scoring and the selection with the hit reaction, the behaviour in control (ram, retreat, evade,
  attack with the standard run and the slashing pass, guard, formation, rally, follow path with the five manoeuvres, idle),
  and the driver's avoidance filter with its re-seek. One native call per thinking ship (`ScsBrains.think`, thirteen
  arguments: the relation row, the clock, the hull, the selection, the hits, the friendly-fire setting and the frame origin
  as three doubles) gives back a `PackedFloat64Array` of 54 numbers: the flight command, the trigger, the wanted target in
  two halves, the dodge flags, the wish, the behaviour in control, dwell and switches, the contacts seen, the raw and
  weighted scores by tie order, and twelve numbers of the behaviour in control's state. The GDScript brains fly whenever a
  perception is not on the rows (no core, a pilot with a scripted or subclassed behaviour, a ship with no row this tick;
  `perf_native_brains` off did too until M4-T37 removed it).
- **Bit for bit, with the seeds.** The maths repeats the GDScript op for op (32-bit vectors, 64-bit scalars, a scalar rounded
  to 32 bits before it scales a vector, the engine's `atan2`, `sin`, `cos`, `tan`, `acos`, `exp` through the same libm).
  The seeded rolls are Godot's own: `hash([seed, "label"])` is the Array hash (murmur3 over `hash_one_uint64` of the int and
  djb2 of the String, `hash_fmix32` at the end), and `RandomNumberGenerator` is PCG32 with the engine's increment, `randf`
  from `ldexp` of a draw whose top and bottom bits are set (the bottom bit breaks the u32-to-f32 rounding ties upward). The
  avoidance tie-break reaches the kernel as `hash(seed)`, as the GDScript `AvoidanceMath.tie_direction` took it (until M4-T42). `test_brain_parity`
  checks each piece against the GDScript on seeded inputs; `test_brain_think_parity` drives a native slot and a GDScript
  twin tick by tick on hand-built rows (crowds of four sides, wings under each order, objectives, guard posts, every
  temperament, live retunes, a patrol route with its demos, hits) and asks for the same command, target, dodge, behaviour
  and scores; `test_brain_tolerance` flies the bench's furball and spread at 50 for seeds 1 to 3 on both paths (Q16).
- **The rows the brains need.** Three columns joined the rows: `hull_fraction` (`Damageable.hull.fraction()`, -1 without a
  hull), `target_ids` (the ship's selection, -1 for none) and `reach` (the marker's broadcast range), plus a lowered copy of
  the name for the objective's and the guard's name matching, and an id-to-row index rebuilt with the rows, so a brain finds
  a kept contact, its objective or its guarded ship by id in a binary search (the names are resolved to ids once, and again
  only when that row is gone or renamed). The first two are read at the sync points (two property
  reads of the hull's health and one of the targeting system a body, the handles taken once with the attributes; a read that finds no value is counted in
  `core.column_read_failures` and warned about once), where
  the GDScript scan stamped them live on the first hand-out; in the tick's order both read the same values, since
  selections change at the drivers (behind `note_selection`) and hulls at the resolvers. The broadcast list comes from the
  rows with a reach beyond the near range, in row order, where the GDScript scan listed `Targetable.broadcasters()` in
  theirs: a tolerated difference (it only orders ties in a rally's pick and the objective's first match).
- **The slot's life.** `AiPilot` makes its slot at its first native think from the base profile, the temperament and the
  behaviours it has, then replays the driver's `reset` and every `set_temperament` since, so the seeded generators stand
  where the GDScript objects' do; `add_behaviour`, `set_temperament` and `reset` reach the slot from then on, and the slot is
  freed when the pilot is. The wing's view, the objective, the guard post and the route are pushed when they change. What
  the game reads of a pilot is mirrored back after each think: `current`, the scores, `wanted_target_id`, the wish, an
  evade's jinks, an attack's run and gate, a rammer's commitment, a route's waypoint, phase, lag, visited list and results.
  A rammer committed from outside (a test) is pushed forward.
- **Thread-ready (for T18).** `brain_behaviours::Brain::think` takes the rows, the bolts, the grid, the tick's field (the bolts
  by cell, the broadcasters), the ship's own row, the caller's scratch (the picked lists, the context split, the keep ids)
  and the inputs, mutates only its own `Brain` and that scratch, and allocates nothing per ship per tick after warm-up; the
  contact queries fill the caller's lists (`*_into`). No statics, no caches written during a pass, every roll from the
  brain's own generators. Not yet in place for a batch: `contact::Work` bundles the shared cells with the per-query scratch
  (to split), the host's one `Scratch` (one per worker), and the per-ship `Inputs` that still arrive from GDScript per call.
- **The fallback.** A pilot with a brain in the slot whose think the host declines (the rows moved under the frame's scan,
  or its ship has no row this tick) holds its last command for that tick, as a held far-rate tick does, and is counted in
  `ai.thinks_fallback`; its GDScript objects, which hold only the mirror, never run. A pilot without a slot yet thinks in
  GDScript as before.
- **Console and settings.** `perf_native_brains` (default on; off = the GDScript brains, so a bench paired the two in one
  process; M4-T37 removed it). Provider `ai` gains `thinks_native` (AI ships whose think ran natively in the last tick) and `thinks_fallback` (native pilots the host declined, each holding its last command); `ai <name>` reads a
  native pilot's `describe()` from its slot (the behaviour in control, its state and fields, the scores).


**Threads inside the core (T18, N3).**

```
native/src/threads.rs            Threads: the core's rayon pool (none for one thread), a threshold per pass, the per-item pass,
                                 the performance-core count; engine-free (std and rayon only), under test_sim_core's guard
native/src/sim_core.rs           the pool on the core (set_threads, threads, parallel_passes, the thresholds), rows_digest
native/src/brain.rs              ScsBrains.think_batch: every native think of a tick in one call, across the pool (M4-T37
                                 removed it; launch_batch and launch_rows carry it)
native/src/flight_step.rs        ScsFlightStep: read on the main thread, the kernel on the pool, the forces applied in row order
src/perf/brain_batch.gd          BrainBatch: an internal child of SimCore at -9 that carries the drivers' native thinks
```

- **What runs in parallel.** Two passes. The brains: the drivers (-10) hand each native pilot's inputs to `BrainBatch`
  (its slot, its relation row, selection, latest attacker, dt, hull and hits), and at -9 one batch call (`think_batch`, a
  launched job since M4-T24) thinks
  every ship across the pool (the perception queries, the context split, the scoring, the behaviour and the avoidance all
  run inside a think); each driver then gets its output in the order it came and does what it did before (the selection,
  the hiding lights, `apply_commands`). The flight step: the ships' commands and poses are read on the main thread (a ship
  with no row from the physics server, as before), the kernel runs on the pool, and the forces go to the physics server on
  the main thread in row order. A driver stepped by hand (the tests) thinks alone as before. The probe's AI stage now ends
  at -8, so it holds the batch.
- **How the bits stay the same.** Every item reads only frozen, shared data (the rows, the bolts, the grid, the tick's
  field, the ship's own slot) and writes only itself (its brain, taken out of its slot for the pass, and its output; a
  flying ship's assist state and forces), with one scratch per worker thread that the item clears before it reads it. The
  merge (brains back into their slots, outputs packed, forces applied) is on the main thread in the given order. Nothing a
  worker runs touches the engine: the brains and the flight kernel are the engine-free files of T15 and T17. To make that
  hold, T17's two open gaps closed: `contact::Work` is now the shared `Grid` (cells, cell size, largest static) plus a
  `Query` per worker, and the host keeps one `Scratch`, keep list and query per worker; and the display names left `Rows`
  for `ScsSimCore.row_names`, because Godot's string type cannot be shared between threads (the guard now refuses an
  engine string in `rows.rs`). The rows version, the counters and every cache are written only on the main thread.
- **The thread count.** `perf_threads` (0, the default: as many threads as the machine has performance cores, read from
  `/sys/devices/cpu_core/cpus` and the CPU topology, at most the CPUs the process may use, so 6 on the i5-13600KF; 1: the
  main thread alone, no pool). `SimCore` hands it to the core when it is made and whenever the setting changes, and the
  next pass uses it. The count is not a placement: unpinned, the scheduler may run workers on efficiency cores. The
  benches pin the process to cores 0 to 11 and the pool's threads inherit that.
- **When a pass stays on the main thread.** Below its threshold, where waking the workers costs more than they save:
  the brains run in parallel from 48 thinks a tick, the flight step from 1 024 ships (Cycle log, M4-T18: at `typical`, 19
  to 28 thinks, the threads took 0.1 ms off the think and added about 0.5 ms to the 1 % slowest ticks; at `battle` 100, 34
  thinks, 0.3 ms off and 0.6 to 0.9 ms on the slow ticks; the flight kernel is a few microseconds a ship and gained at no
  measured count). `core.parallel_min` and `core.flight_parallel_min` set them for a bench or a test.
- **Tests.** `test_core_threads`: a seeded battle (the `battle` layout's 102 fighters at 120, four sides, no player, in a
  space of its own with the clock reset) stepped 600 ticks with one thread and with six, every pass forced parallel,
  gives the same `rows_digest` every tick (positions, velocities, bases, spins, flags, hulls and selections of every row,
  every bolt); with an injected fault (`ScsBrains.set_fault`: a think adds what the worker's previous think left in its
  scratch, so it reads another row's output) the two differ within 30 ticks; the thread count follows `perf_threads` at
  once. `test_sim_core`'s guard covers `threads.rs`. Since M6-T18 the battle has a ram resolver and a player ship (near
  and far thinkers), and the comparison also covers the hits and rams, the bolt table, the core's commands and the drivers'
  events: the other battle files' 1-vs-6 checks were folded into it, and their builds share `tests/fixtures/seeded_battle.gd`.
- **Holding instead of guessing** (fix round 1). The batch carries the core's rows version the drivers' scan was taken
  at; if the rows moved before the batch (a resync or a rebase between -10 and -9) every think is declined and each pilot
  holds its last command, counted in `ai.thinks_fallback`, as T17's per-ship check did. A panic inside the pass is caught:
  that tick's thinks are declined the same way, every brain goes back to its slot, and `ScsBrains.pass_failures` counts
  it. The pool is joined (its workers waited for) whenever the thread count changes and when the core goes, so no worker
  outlives the library (`core.live_workers`). A flight slot listed twice in one step flies its entries one after the
  other on the main thread, each reading the assist state the last left.
- **The glue around a native think** (fix round 1). The batch's answer is read in place by each pilot (an offset, no
  array per ship); the mirror of the behaviour in control into its GDScript object is written only when something reads
  the behaviours (`current`, `behaviour`, `describe`) for attack, evade, guard and formation, and at once for ram (the
  avoidance's exemption) and follow-path (the instructor's route, read every frame); the drivers look the host and the
  batch up once a physics frame. The names the brains match (objectives, guarded ships) are indexed once per rows version
  in the tick's field, so a think looks its name's rows up instead of walking every row.
- **Also fixed.** A duplicate name no longer hides the live ship: the objective and the guarded ship are matched among
  the think's contacts (then the broadcasts for the objective) every think, as `AiContext._named` does, and every row
  with the name is kept beyond the nearest k, as `ContactScan._keep_named` does (T17 had kept the first row with the
  name anywhere, so a far or parked row earlier in the rows could hide it; `test_brain_think_parity`).

**The cheap pass on the per-ship stages (T34).**

```
native/src/bolt_sync.rs          ScsBoltSync: the core's two bolt reads a tick, the same rows as the core's own read, cheaper
native/src/sweep_cells.rs        the hit broad phase's grid with its cells in hash maps; engine-free, under T15's guard
native/src/hit_sweep.rs          ScsHitSweep.set_cells: the hashed grid or the sorted one (kernels.rs), the same pairs and work
src/perf/sim_core.gd             the core's sync with no bolts, then the reader (bolt_path); its engine calls counted with the core's
src/combat/ram_tracker.gd        RamTracker.contacts_columns: the contact phase from columns
src/combat/ram_resolver.gd       the contact phase in columns; the swept test's early rejects
src/targeting/targetable.gd      the owner's hull looked up once while in the tree
src/targeting/targeting_controller.gd  the player's candidate list built when read
```

- **Why.** After phase 2 four stages of per-ship GDScript and engine calls held 9.1 ms of the 17.7 ms tick at `battle`
  300 and 15.8 of 30.4 at 500: targeting, the hit resolver, the ram resolver and the core's first sync. Each was profiled
  line by line first (Cycle log, M4-T34); the costs were the player's per-tick candidate list (2.1 ms at 300, about 5.5 us
  a target), the bolts read twice a tick (0.8 to 0.9 ms a read), a `RamTracker.Sample` built for every rigid hull every
  tick though almost none touched anything (1.3 ms), and about ten fighter and capital pairs a tick in the ram sweep, each
  placing all 13 or 14 fighter volumes before most failed their first box test (0.5 ms).
- **What changed, each behind a setting that kept the old path as the reference** (M4-T37 removed the five switches and the
  old paths; their outputs are recorded in `tests/fixtures/parity/`). The bolt reader (`perf_native_bolt_sync`)
  finds a known bolt by the instance id in its array slot instead of making it into an object handle, does not ask the
  group's nodes whether they are in the tree (a group holds only nodes that are) and keeps its bolts in a cheaper map; it
  counts its engine calls as the core counts its own, and `SimCore.engine_calls` adds them. The ram contact phase
  (`perf_ram_contact_columns`) hands the tracker every rigid hull's id, velocity and accel as columns and builds contact
  lists only for the hulls Jolt reports touching; a hull's ram limits are read only when it has an open window. The swept
  test (`perf_ram_sweep_cull`) checks the body's bounding sphere, then each volume's, swept and padded by 5 cm, against the
  other hull's box before it places a volume; the rejects skip only work whose answer is no ram. The player's targeting
  computer (`perf_targeting_on_read`) checks its selection every tick as an AI ship's does and builds its list on the first
  read after a refresh (the HUD and the radar once a frame, a selection command), without touching the selection. The hit
  broad phase's grid (`perf_native_sweep_cells`) finds a projectile's candidates by one hash lookup a cell instead of two
  binary searches a column, so the candidates, the pairs and the work count stay the same. With no setting, a targetable
  keeps its owner's hull until the owner's children change (`child_order_changed`), so every value stays what
  `Damageable.of` gives.
- **What a reader sees.** Everything the simulation decides is the same bit for bit (the tests below). On read, the
  player's refresh still notes each listed target's id, position, broadcast range and name (fix round 1), so the selection
  check, the selection's name and `select_id` answer from what the refresh's list held, as before; a target that left reach
  after the refresh can still be selected by a command until the next refresh clears it, both ways. One thing moved in
  time: the full candidate list a window's HUD reads (`candidates()`) is now built at that read, after the tick, so its
  positions and hulls are a physics step fresher than the list the last refresh used to leave. In a window the HUD still
  builds it once a frame: the gain is the ticks a frame carries beyond the first, and all of it headless. The note costs
  0.52 ms of targeting at `battle` 300 (0.36 without it, 2.43 on the base). The list is changed from the HUD's `_process`,
  so `refresh` and the commands must stay on the main thread (a note for T24).
- **Tests.** `test_bolt_sync` (a seeded crowd of bolts, missiles and beams, spent, freed and new each round: the same bolt
  rows at both sync points; the engine calls counted alike), `test_ram_tracker_columns` (400 random ticks of two trackers
  side by side: the same rams field for field; M6-T18 removed the sample path and ported `test_ram_tracker` to the columns), `test_ram_contact_columns` (T14's melee both ways: the same rams and
  digest; M6-T18 folded it into `test_core_state`, which reads the same recording), `test_ram_sweep_cull` (6 000 seeded sweeps: the same hits at the same points, a fifth of the volumes placed),
  `test_targeting_on_read` (400 steps of moves, parks, frees and selection commands: the same selection, signals and lists
  read; no list built while nothing reads), `test_targetable_hull`, `test_sweep_cells` (twelve seeded mixes against the
  sorted grid and the GDScript reference; the guard holds the new kernel).
**The native pilots' commands as core rows (T33).**

```
native/src/row_commands.rs       RowCommand and the core's commands by body: written by the brains' batch, flown by the flight step
native/src/brain.rs              ScsBrains.think_batch_rows and rows_events: the rows batch, its commands and its events
                                 (M4-T37 removed think_batch_rows; launch_rows carries it)
native/src/flight_step.rs        the step flies a ship's command from its row when it has one
src/perf/brain_answer.gd         BrainAnswer: one tick's answer, kept by the drivers and pilots that joined, read when needed
src/perf/brain_batch.gd          the rows batch (add_rows, the flush that hands out the few events)
src/ai/ai_pilot_driver.gd        the rows path at -10, the events at -9, the think rate's clock settled lazily
src/ai/ai_pilot.gd, pilot_brain.gd  the pending answer, read at the first getter or method that needs it
src/ship/ship.gd                 use_row_command, release_row_command, pull_row_command
```

- **What moved.** T18 left about 27 us of GDScript around every native think: the lite perception, the slot's checks,
  joining the batch, then unpacking the answer, mirroring it, building the command objects, the selection, the lights
  and `apply_commands`. With `perf_native_commands` on (the default until M4-T37 removed it with T18's path, so always
  now) a native think goes into a rows batch: the driver
  hands in the slot, dt, its faction's relation row, the near flag and the latest hits; the host reads the hull and the
  selection from the ship's own row (the sync stamped them, T17), thinks as before, and writes each think's flight
  numbers and trigger into the core's commands by body (`ScsSimCore.row_commands`). The flight batch (-1) flies a ship's
  command from there, whatever it gathered from the ship, so the ship flies the command its pilot chose in the same tick.
- **What the drivers still do.** At -10, for every ship: the think rate's decision (near the player, the stagger, the
  wake), and for a thinking ship the context pushed when it changed and the join (about 8 us, measured with a throwaway
  hook at `battle` 300); a held ship costs about 1.4 us. At -9, only the ships the batch names (`rows_events`): the
  first command from the row (the ship and the cannon are handed their commands once, then `Ship.use_row_command`), a
  changed trigger (the driver's one `CombatCommand`, which the cannon holds), the first shot of a hiding pilot (the
  lights), a target to select (`TargetingController`, as before), and a rammer or route follower in control or a new ram
  commitment (the pilot is read at once, as the facade's eager mirror did). At `battle` 300 that is about 40 of 94
  thinks a tick, most of them trigger changes. Everything else is read when asked: the driver settles the think rate's
  clock at its next step (a declined think puts back the time since the last think and the wake), and the pilot reads
  its place in the tick's `BrainAnswer` at the first getter or method that needs it (`current`, the scores, `describe`,
  `behaviour`, the wanted target, the wish, dwell, switches, the dodge). An answer a newer think replaces unread is
  skipped as the lazy mirror (T18) skips it, except a rammer's and a route's state and the attack's target in the context.
- **Holding from the row.** A declined think (the rows moved, a panic in the pass, no row) writes nothing, so its ship
  flies the command its row already holds, as a far-rate tick does. Anything that commands the ship from GDScript
  (`set_flight_command`: a GDScript brain, the pool parking a ship, a test) releases the row, and so does a new pilot;
  its next native think hands the commands over again. A ship on its own GDScript model (the batch off or its step
  refused) and the batch's step without the core read the row's command into the ship first (`pull_row_command`).
- **Bit for bit.** The row keeps the think's numbers as they are (the strafe and the spin already 32-bit), and the step
  packs them as `FlightBatch.pack_command` packs a `FlightCommand`; the selection follows the same rule (`_follow_target`),
  and the row's selection equals the live one at -9 in the game's order (selections change at the drivers and at the
  targeting controllers, 100, before the next sync). `test_row_commands` flies the seeded battle of `test_core_threads`
  (120 ships, 240 ticks) with the rows path off and on: every ship's command, trigger and selection, and the rows, are
  the same every tick, and every pilot reads the same at the end; one thread and six give the same commands; with the
  flight batch off the ships fly the same bits on their own models; a declined think keeps every row's command; a
  command set from GDScript takes over. T17's parity files, Q16's fights and the seeded melee's digest are unchanged.
- **Thread-ready (for T24).** The commands are written on the main thread after the pass, from each item's output, in
  batch order; the pass itself is T18's. What is left per ship on the main thread is the think rate's decision, the
  context check and the join at -10, and the events at -9: the next lever (the think rate decided in the host from the
  slot's own clock, the hits pushed when they land) takes the per-ship step off the main thread with the rest of T24.
- **Console and settings.** `perf_native_commands` (default on, live; off was T18's path, for pairing; M4-T37 removed
  both). Provider `ai` gains
  `rows_events` (drivers the last rows batch handed something to do) and `row_commands` (ships flying from their rows).

**The core owns the simulated state (T35).**

```
native/src/bolt_kernels.rs       the bolt step, the cannon gate and capacitor, a shot's start and velocity, the multimesh transforms;
                                 engine-free, under test_sim_core's guard
native/src/bolt_rows.rs          ScsSimCore's own bolts: add_bolt, spend, step_bolts, the renderer's buffer
native/src/cannons.rs            ScsCannons: every AI cannon's gate and muzzles as rows, stepped in one call over the core
native/src/sim_core.rs           activity, hull and selection from events; the direct-state read by RID; row RIDs; the
                                 accelerations the flight step wrote; the AI controllers' selection check
native/src/ram_phase.rs          ScsRamPhase.contacts: the ram stage's contact read in one call over the rigid rows
native/src/brain.rs              the hosted drivers: the think rate's stagger, wake and hold decided in the batch's call
src/perf/sim_core.gd             SimCoreStep (priority 1: the cannons, then the bolts), SimCoreTargeting (100), the events into
                                 the columns, the cannon and selection registries, the settings
src/weapons/pulse_cannon.gd      the cannon on the kernel (shot_fired), a lean ship's on muzzle transforms; src/weapons/bolt_mesh.gd
                                 draws the owned bolts; src/weapons/muzzle_flash_pool.gd the lean ships' flashes
src/perf/brain_batch.gd, src/ai/ai_pilot_driver.gd, src/ai/ai_pilot.gd, src/ai/ai_context.gd   the hosted step
src/combat/hit_resolver.gd, src/combat/ram_resolver.gd, src/targeting/targeting_controller.gd, src/ship/flight_batch.gd
```

- **Why.** T15 built the core as a mirror of the engine (every body read through its node's getters each tick, every bolt
  a node read twice a tick), the right seam for parity but the wrong direction for T24, whose worker thread cannot move
  nodes. The refactor review (2026-11-05) priced the bolt nodes at 5 to 8 ms a tick at `battle` 500 and the per-ship
  GDScript left on the batched path (the cannons' ticks, the drivers' steps, the ships' own ticks, the controllers'
  selection checks) at about 4 ms more. After this task everything simulated is a row the core owns or steps, and the
  nodes are the mirror: a body's pose and motion are the only columns read from the engine each tick.
- **Bolts as rows** (`perf_native_bolt_rows` until M4-T37, which also removed the core's own bolt-node read). The `Bolts` table's front rows are the core's own, in launch order (a negative
  id each, never an instance id), with the columns a hit lands with and the renderer draws (damage, colour, look, expiry,
  launch tick, spent); the projectiles that still have a node (beams, missiles, the player's bolts) follow them at each
  sync point, read as before. `bolt_kernels::step` expires the owned bolts whose time is up and moves the rest by
  `velocity * delta` with the delta rounded to 32 bits, as `Projectile._physics_process` did; a bolt launched this tick
  stays where it is (its launch tick sweeps only its muzzle). The hit resolver reads shooter, faction, damage and tint from
  columns on every path, checks liveness and spends an owned row in the core; the spent rows go at the next tick's first
  sync, as a spent node is gone by then. The resolver lands the tick's hits in launch order (`bolt_columns`' order: the
  owned rows and the node rows merged by launch tick, an owned row first on a tie), the order the bolt nodes' group had, so
  a same-tick kill goes to the bolt fired first whichever form it has. `BoltMesh` (an internal child of `SimCore`) draws
  the owned bolts with one `MultiMeshInstance3D` per look, its buffer filled once a frame (one of `FramePasses`' passes,
  §17.21) from `bolt_transforms`: each bolt between its last two ticks as an interpolated node would be, enlarged by
  `Projectile.visual_scale`, under a custom AABB so nothing culls it. A bolt keeps its instance slot for life (a freed slot
  is drawn empty, an all-zero transform, until a new bolt takes it), so instance k follows one bolt from frame to frame, as
  T38's motion vectors need.
- **The cannons as rows.** Every cannon but the player's registers with `ScsCannons` (its ship, its muzzles as origins in the
  ship's frame composed from the markers' transforms, its gate and capacitor, what its bolts carry) and stops its own
  `_physics_process`. `SimCoreStep` at priority 1 (after the drivers' commands, `Main` and the World's rebase at 0, before
  the targeting at 100 and the resolvers) runs the cannon step: the trigger from the ship's row command when it flies one
  (T33), else the one `set_combat_command` pushed; `bolt_kernels::Gate` and `Capacitor` op for op with `PulseCannonGate` and
  `WeaponCapacitor`; a bolt row per firing muzzle from the ship's row (the basis, position and velocity the sync read, which
  nothing moves before priority 1), the muzzle's World position as the engine composes a child's transform
  (`basis.rows[i].dot(local) + origin`) and the velocity as `PulseCannon.step` aims it. The shots come back to their
  cannons (`on_kernel_fired`: the muzzle flash and `shot_fired(muzzle_index, position)`), then `step_bolts` moves the owned
  bolts. A live cannon whose ship has no row this tick is handed back for GDScript to step from the node's pose
  (`step_one`), so a bare body still fires. The GDScript gate stays the reference (`step`, which the tests drive by hand)
  and its state is carried over when a cannon joins or leaves the kernel.
- **The state from events** (`perf_core_event_columns` until M4-T37). A body's activity (`Targetable.is_active`: valid, in the tree,
  visible, processing) is checked again only when the body was touched (hidden, shown, destroyed: the events the facade
  already watched, plus a marker hidden on its own) or first seen; its hull column follows `Damageable.damaged` and the new
  `restored` signal (`note_hull`, `clamp(hp / max_hp)` as the read did), its selection column every change a
  `TargetingController` makes (`SimCore.note_selection_changed`). The attributes hold the latest values; the rows are
  written from them at the sync points, so a row holds what a read at the sync would have given, and the brains at -9 read
  the same columns as before. What the events do not cover: a body that only stops processing (no visibility change) keeps
  its row until something touches it; a hull changed under `Damageable` (a test poking `HullHealth` directly) is not heard.
  The reads a body makes each tick fell from eleven to three (the transform and two velocities).
- **The direct-state read** (`perf_core_body_direct`, off by default; M4-T37 removed the read with the setting). The
  rigid bodies' pose and motion read from
  `PhysicsServer3D.body_get_direct_state` by RID instead of the nodes' getters: four calls a body against three, and the
  bits equal the nodes' after Jolt's first step (the node is set from the same state) but differ between a teleport and the
  next step (the server rebuilds the basis from its quaternion, T09's finding), which moves T14's melee digest. Measured
  no faster (Cycle log); M4-T37 removed it with its switch.
- **The ram stage's contact read** (`perf_native_ram_contacts` until M4-T37). `ScsRamPhase.contacts` walks the rigid hull rows once:
  each body's direct state by the row's RID, the contact count, and for the hulls Jolt reports touching, every contact's
  collider, point (shifted by what the World was rebased by since Jolt's step) and normal; with them the velocity column and
  the acceleration the flight step wrote into the core for every ship it flew this tick (`force / mass` in 32 bits, as
  `Ship.applied_force() / ship.mass`), flagged where it did not (a ship on its own model, which GDScript asks as before). The
  resolver builds the tracker's columns from that (`RamTracker.contacts_columns`, T34), so the rams are bit for bit the
  columns path's. `contact_monitor` is off on every ship (`ship_contact_monitor` until M4-T37): nothing connects
  `body_entered`, and the direct state's contact list, which this read takes, needs only `max_contacts_reported` (T14's melee
  counts the same 2 959 Jolt contacts).
- **The AI controllers' selection check** (`perf_native_selection_check` until M4-T37). An AI ship's
  `TargetingController` (one that does not keep candidates) hands its check to the core (`watch_selection`, with its sensor
  range) and stops ticking; `SimCoreTargeting` at the controllers' priority asks `selection_clears` once: for every watched
  ship whose latest selection (the events') is a marker id, no row for it, its own ship, or a 64-bit range beyond the
  sensor range or the target's own reach, as `_check_selection` tested them, and each named controller clears its selection
  (the same `target_changed`). A controller whose sensor range changes tells the core (`set_sensor_range_m`). The check
  ranges on the rows as the first sync read them, so a target that moves by script after that sync touches its row
  (`SimCore.touch_moved`; `NavBuoy`'s drift does), and the core reads the touched rows again before the check
  (`resync_touched_now`) and again at the resolvers' sync, so this check and the hit sweep see this tick's place as the
  tree reads at 0 and later did. The buoy keeps the default priority: the World's rebase at 0 runs before every prop.
- **The batch owns its ships' ticks** (`perf_batch_owns_ships` until M4-T37, which removed the setting: the batch always
  owns them). A ship the flight batch flew has nothing left to do at 0 (its combat edges are taken in the batch's gather,
  before the World's rebase), so `FlightBatch` switches its `_physics_process` off once and gives it back when it stops
  flying the ship (the ship leaving). M4-T44 removed the GDScript fallback that flew a ship's own model at once
  (`fly_own_tick_now`) when there was no native step or a refused one.
- **The drivers' step in the host** (`perf_native_driver_step` until M4-T37, which removed the setting: the host always
  takes the step, and a hand step takes it back). Once a native pilot's slot is bound to its ship, its driver hands the
  host its think rate's state (its place in the stagger, its steps, the time since the last think, the wake, the latest
  hits) through `BrainBatch.host_driver` and stops ticking. In the batch's job (`think_batch_rows`, `launch_rows` since
  M4-T37) the
  host steps every hosted driver after the queued ships: a step and the tick added, near the player or not from the ship's
  row and the player's position the batch gave it, `AiThinkRate.thinks`' rule (`posmod(steps + ordinal, period) == 0`),
  a ship with no row this tick held as a declined think was; the thinking ones become items with the relation row of their
  faction from a matrix the batch keeps over the core's factions (rebuilt when the factions or the table change). A think
  that lands starts the ship's clock again; a declined one keeps it, as the driver's settle put it back. The pilot reads
  its latest think from the host's slot when something asks (`slot_output`, counted by `slot_think_count`), the hits reach
  the host as they land (`set_driver_hits`, which wakes the ship), a parked ship's driver is marked not live, and a changed
  context (`AiContext`'s wing, objective, guard and route fields, whose setters list the context) is pushed by the batch
  before the call. The driver takes its step back when its pilot changes, it leaves the tree, the setting goes off, or a
  test steps it by hand. `rows_events`' head gained the held count; `ai.hosted` says how many drivers the host steps.
- **The lean ships' muzzle flashes from one pool** (refactor finding 12). A lean ship builds no `Marker3D` per muzzle: the
  hardpoints' muzzle transforms are data (`Ship.get_muzzle_transforms`), its cannon fires from them (`PulseCannon.setup_transforms`,
  a shot leaves at `body.global_transform * muzzle.origin`, the marker's position bit for bit), and its flashes go to the World's
  `MuzzleFlashPool` (`src/weapons/muzzle_flash_pool.gd`): one `MultiMeshInstance3D` of billboard quads drawn once a frame by
  `FramePasses` (§17.21; the pool has no `_process` of its own) (each
  at the muzzle's position on the ship's interpolated transform, grown and faded as `MuzzleFlash` did, the fade in the instance
  colour's alpha), and a small set of `LightEmitter`s reused across shots, each anchored on the ship at the muzzle plus the
  flash's offset down the barrel, in the `LightRig`'s competition for `EmitterCurves.FLASH_S`. A ship that parks or leaves ends
  its flashes at once. The brains' mean muzzle is the marker's position round-tripped from the transform (`ship.to_local(xf *
  origin)`), the same bits as from the marker. The player's ship keeps its markers and flash nodes (the HUD reads them). The
  look goes on the return checklist (Q54).
- **Bit for bit.** Every path keeps its reference behind its setting, and the seeded battle of `test_core_threads` (120
  fighters, 240 ticks) gives the same rows, commands, hits and hull rows every tick on each pair (`test_bolt_rows`,
  `test_core_state`, `test_driver_step`), T14's melee the same rams and digest with the native contact read
  (`test_core_state`), and one thread and six the same bits with everything on. What differs: the bolt table's order
  (owned rows in launch order, cannons in slot order, then the node projectiles; today's was the `projectiles` group's
  spawn order across every kind), which only orders two projectiles hitting the same hull in the same tick; the player's
  cannon keeps its bolt nodes, so its bolts sit after the AI's rows; a live cannon whose ship has no row at the step fires
  from the node's pose; the direct-state read's last bits after a teleport (off by default).
- **Thread-ready (for T24).** The cannon step, the bolt step, the selection check and the hosted drivers' step read the
  frozen rows and write the core's own tables on the main thread; the only engine calls left in the tick are the sync
  points' pose reads, the ram stage's contact read and the flight step's force application, each in one call over the rows.
- **Settings and console.** `perf_native_bolt_rows`, `perf_core_event_columns`, `perf_core_body_direct` (off),
  `perf_native_ram_contacts`, `perf_native_selection_check`, `perf_batch_owns_ships`, `perf_native_driver_step`,
  `ship_contact_monitor` (off), all live until M4-T37 removed them. Provider `core` gains `bolt_path` (removed in M4-T44), `owned_bolts`,
  `cannons`, `cannon_us`, `bolt_step_us`, `shots`, `expired`, `bolt_draws`, `watched_selections`,
  `selection_clears`; `ai` gains `hosted`.

**The AI step on a worker thread, one tick behind (T24, Q53).**

```
native/src/brain_step.rs         the step as a job: Work (the brains, the hosted drivers, the batch's scratch), Snapshot (the rows,
                                 the bolts, the rows by body, the touched set, the commands, the version), Params, Job, Done, run;
                                 engine-free, under test_sim_core's guard
native/src/threads.rs            + Runner (the core's pool behind an Arc, so a job off the main thread runs its pass on the same
                                 threads with the same thresholds) and StepThread (one std thread, a job in, its result out,
                                 joined on drop)
native/src/brain.rs              ScsBrains launches and joins the job (launch_rows, launch_batch, join_step; think is launch plus
                                 join, and so were think_batch and think_batch_rows until M4-T37 removed them), queues what
                                 arrives while the brains are away, keeps the readers' view
native/src/row_commands.rs       snapshot_into and take_commands: the commands copied out at the launch and swapped in at the join,
                                 less the ones released since
src/perf/brain_batch.gd          flush by `sim_step`: join the previous tick's job and hand its results over, then launch this tick's
src/ai/ai_pilot_driver.gd, src/ai/ai_pilot.gd   an answer that has not come yet is kept until it has; the reads one tick behind
src/game/main.gd                 `physics_max_steps_per_frame` applied live (Engine.max_physics_steps_per_frame)
scripts/input_latency.gd         the input latency probe: a pad press on the fake input source to the ship's first answer
```

- **Why, and what moved.** The maintainer asked that the AI never make the game loop or the player's input wait (Q53). The
  brains' batch (the perception queries, the thinks, the avoidance, the hosted drivers' think-rate step, the commands
  written into the rows: `ScsBrains.think_batch_rows`, and the plain `think_batch`, both `launch_rows` and
  `launch_batch` since M4-T37) is the engine-free half of the tick, so
  it became a job (`brain_step::run`) over a snapshot of the core's tables that runs on a worker thread. Everything the job
  touches it owns: the brains and the batch's state (`Work`) move into the job and come back with its result, and the
  rows, bolts, touched set and commands are copied (`clone_from` into kept buffers: the double buffer's back half) at
  the launch. The main thread's tick keeps the sync points, the handover, the flight step (its forces are the tick's
  engine write and must come from this tick's pose: a one-tick-old pose in the assist's feedback loop would lag every AI
  ship's control), the cannon and bolt step (a shot from a one-tick-old muzzle would start metres behind a fast fighter),
  the hit sweep, the ram phase and the weapon kernels (their results feed GDScript damage in the same tick). The brief's
  "every kernel" was read as directional: the one that is the AI left; the kernels whose outputs are engine writes in the
  same tick stayed, and the entry says so.
- **The schedule** (`sim_step`, live). Until M4-T37 an `inline` schedule thought and applied in one call at -9 (the Q54
  fallback and the reference the GDScript-against-native parity tests pinned); M4-T37 removed it, and a saved `inline`
  loads as `threaded`. `delayed`: the batch is launched at
  -9 of tick N and runs there and then, but its results are applied at -9 of tick N+1: the one-tick handover without a
  thread, the threaded step's deterministic reference. `threaded` (the default): the same job runs on the step's thread
  (`scs-sim-step`; its pass still across the core's rayon pool through a `Runner`) from -9 of tick N; at -9 of tick N+1
  the main thread joins it. A join that finds the job still running waits for it and counts a miss (`core.step_misses`);
  nothing is skipped. Every AI command therefore flies one tick (16.7 ms) after the rows it was decided on; the player's
  command (sampled and applied at 0) is never behind.
- **The handover** (`BrainBatch.flush`): join (or take the delayed result) -> the job's commands swapped into
  `row_commands` less the bodies something else commanded since the launch (`release_command` records them) -> the
  events to the drivers that joined the previous tick (the ship's first command from its row, a changed trigger, a target
  to select, a rammer or route follower to read) -> the hits, liveness, wakes and newly hosted drivers that arrived
  meanwhile applied -> the contexts, the frame and the relation matrix pushed -> the snapshot taken and this tick's job
  launched. A scheduled job's result (its output, events, hosted slots and commands) is parked at its join, early or
  not, until `join_step` hands it over, so a single `think` while the job is out loses nothing.
  Each launched driver is stamped with the pilot flying its ship at the launch (and each hosted slot with its driver and
  pilot): a result for a ship parked or re-piloted meanwhile is stale and dropped, counted (`core.step_stale`).
- **Where the job's pass runs** (`perf_step_threads`, 1): on the step's thread alone by default, so the job never queues
  the main thread's passes (flight, the sweeps) behind its chunks on the core's pool; `n` gives it a pool of its own,
  `0` the core's pool (what `test_core_threads` uses to compare one thread with six). The measured choice is in the
  Cycle log, M4-T24 (fix round 1). The counts (`ai.thinks_*`, `held`) roll every flush and are credited at the join, so a tick with no join reads
  zero.
- **While the brains are away.** `set_driver_hits`, `set_driver_live`, `wake_driver` and `host_driver` queue and apply at
  the join (which is when today's hits reach the next think too). The hosted readers (`slot_output`, `slot_think_count`,
  `driver_dt`, `slot_attack_target`, `driver_state`, `hosted_count`) read a view taken at the launch until `join_step`
  hands the job over, whatever an early join brought back, so no reader sees a think before the tick that applies it.
  `describe`, `path_visited` and `path_results` (the HUD roster reads `describe` every frame) answer from a per-slot cache
  refreshed at every launch for the slots asked since the last one; a slot not asked before joins the job early. Anything
  else (`unhost_driver`, `set_wing` outside the flush, `create`, `set_fault`, ...) joins first; every such join is counted
  (`core.step_early_joins`). A driver keeps an answer that has not come (and the one before it) until it is ready, then
  settles its clock from it; a pilot keeps the answer before a still-pending one whole, so a read in between lands it in
  full, and a hosted pilot's reads prefer the host's newer thinks. The plain batch resets a driver's think clock when the
  think queues, as the rows path does, and puts it back when the host declines.
- **No engine call from the worker.** gdext without `experimental-threads` does not check the thread of an engine call,
  so there is no runtime guard; the guard is in two halves. The compiler: `StepThread<J: Send + 'static, ...>` takes only
  `Send` jobs, and a `Gd<T>` is not `Send` without `experimental-threads`, so no engine handle can ride in a job (the
  job is plain data in, plain data out, no `unsafe`). The source rule, for the free engine calls the compiler cannot see
  (singletons, `godot_*!` macros): `brain_step.rs` and `threads.rs` are under `test_sim_core`'s engine-free check (no
  engine type, call, singleton or macro; imports from the allow-list only, the command row's exact items among them), and
  `core.step_off_main` records that the joined job ran off the main thread.
- **Determinism.** The job is a pure function of its snapshot and the brains it carries, so `threaded` equals `delayed`
  tick for tick (rows, commands, hits, thinks; one thread and six) and the order of the results' application is the
  batch's order on the main thread, as before. The delay itself changes outcomes against today: the seeded references
  the Cycle log records are the delayed step's.
- **The catch-up cap.** `physics_max_steps_per_frame` (3; Godot's default is 8) caps the ticks a frame may run to catch
  up, so a tick slower than a frame lowers the simulation rate instead of the frame rate (refactor finding 15); applied
  live by `Main` beside the jitter fix. Measured at `battle` 500: 3 had the best 1 % low and p99 frame against 2 and 8
  (Cycle log, M4-T24).
- **Measured** (Cycle log, M4-T24). Headless, the tick at `battle` 300 7.04 to 6.43 ms (p99 10.6 to 8.3), at 500 11.58 to
  10.69 (p99 16.8 to 12.9), `typical` 2.20 to 1.82; the main thread keeps the snapshot copy and the launch (0.15 to 0.2 ms)
  and the join (under 0.1 ms); the job runs 0.6 to 1.0 ms on its thread and no tick's join waited. Fullscreen, the average
  FPS within run-to-run noise on both schedules (the AI step was 5 to 8 % of a tick that already keeps real time at 500);
  the input latency two physics ticks on both (the pad is sampled at 60 Hz).
- **Settings and console.** `sim_step` (`threaded`), `physics_max_steps_per_frame` (3). Provider `core` gains
  `step_mode`, `step_launched`, `step_us` (the job's own run time), `step_wait_us` (how long the join waited), `join_us`,
  `step_misses`, `step_early_joins`, `step_off_main`, `step_threads`.
- **Tests.** `test_core_snapshot`: threaded equals delayed tick for tick on the seeded battle (rows, commands, hits,
  thinks; the job off the main thread; 1 and 6 threads); a job slower than the tick (`FAULT_SLOW`) misses every deadline, is waited for and skips
  nothing; the schedule flips live; a reader while the brains are away answers from the launch (one early join, then the
  cache). `test_sim_core` guards the job and the thread. The existing native-against-native pairings (T33, T35) hold under
  the default. Until M4-T37 the GDScript-against-native ones pinned `inline` and a test showed inline flying the same first
  commands one tick earlier; M4-T37 removed the inline step, and those tests compare with recordings instead.

### 17.14 The low-attention tier (T21)

```
native/src/tier.rs               the tier's rows (far fighters and capitals with no body and no node) and the integrator: the
                                 pose advanced every tick, the forces recomputed on the row's beat; the pull from point sources;
                                 the candidate walks; engine-free, under test_sim_core's guard
native/src/tier_rows.rs          the core's shell: types, add, attrs, control, hulk, take, state, period, gravity, the walks
native/src/sim_core.rs           the tier stepped inside sync_in and its rows appended after the statics, flagged FLAG_TIER
src/ai/tier_director.gd          TierDirector: a child of World at -12 (before the core's sync); the radius and the hysteresis,
                                 promotion and demotion, the row and body handover; the `tier` console provider
src/game/ship_pool.gd            park_in_tier, return_from_tier; release takes a tiered ship's row with it
src/ship/ship.gd                 park_for_tier, unpark_from_tier, assist_state, set_assist_state, hulk
src/perf/standins/capital_standin.gd   park_for_tier, unpark_from_tier; the director skips a parked capital's engines and weapons
```

- **Why.** At `battle` 500 half the fighters and most capitals are more than 10 km from the player, out of sensor range of
  anything the player sees, and each still cost Jolt's step, the body sync and the propagation of its transform to fifteen
  child nodes (T19: 2.8 us a ship for the sync alone, about a third of the physics stage), a flight step, a cannon step and a
  slot in every broad phase. The tier takes those ships out of Jolt and out of the scene's processing and keeps them as rows
  the core integrates itself (Q15, Q22), so the tick scales with the near count. T22 gives the rows brains and fire, T23 their
  dots and radar blips.
- **What a tier row is.** One row in the core's tier table: the body's id and its hull's, the kind (a fighter of a registered
  type, or a capital), faction, radius, broadcast reach, hull fraction, name, position, velocity, attitude, spin, a capital's
  cruise velocity, the command a fighter flies when the brains hold none for it, the assist's smoothed pod-yaw state, the hulk
  flag, a stagger ordinal and what the last beat left to apply (acceleration, angular acceleration, the speed ceiling). A
  fighter type is the flight kernel's `Body` (T10's maths: the same spec, nozzles and torque axes `ScsFlightStep` flies) plus the
  centre of mass its nozzles turn it about; the director registers each `ShipSpec` once (`FlightBatch.type_arrays`).
- **The integrator.** Inside every `sync_in`, before the bodies are read, the core steps the tier for the current tick, so a
  tier row in the scan leads the body rows by one tick's motion (a demotion shows two ticks' motion in one scan step, a
  promotion the same pose twice; the steps per tick stay exact, and `test_tier_handover` checks the scan stays within that
  tick of its path). Every row advances semi-implicitly as Jolt does: the velocity by the
  held acceleration, then the position by the new velocity, the spin by the held angular acceleration, the attitude by the
  spin (the axis-angle rotation, re-orthonormalised). On its beat (every `tier_hz` ticks, staggered by ordinal) a fighter's
  held command (the row command the brains wrote, `row_commands` by body id, else the command it was demoted with) goes
  through `kernels::flight::tick` with the beat's dt: the engines' force (nozzles, RCS, the assist's cap; the pull is
  added every tick, below) over the mass is the acceleration; the RCS torque plus each nozzle force's moment about the centre of mass, turned into
  the body frame and divided by the spec's inertia, the angular acceleration; the spec's speed limit clamps every tick. A
  capital follows `CapitalStandin.cruise_force`'s law (toward its cruise at 2 m/s^2 at most, holding off the pull) and keeps
  its attitude. A hulk holds no force and no brain: it coasts on its last motion and is never removed for being idle (M12's
  disabled hulks, `docs/roadmap.md`). The pull (M6-T07) is the World frame's residual, worked out for every row at once from
  the tick's one sample (`Frame::residual_rows`, the bits a ship at the same place gets) and applied every tick on top of the
  held engine acceleration (the beat takes it only as the brake's and the cruise law's feed-forward), so a parked ship falls as
  its body would. Fuel is not drawn in the tier.
- **The rows in the scan.** After the statics the core appends the tier rows to `Rows`, flagged `FLAG_TIER` and `FLAG_HULL`
  (a hulk `FLAG_HULK` too), `rigid` (a ship to the brains' contacts; a hulk is not) but never `FLAG_RIGID` (no Jolt body) and
  never `FLAG_HULL_ACTIVE` (nothing sweeps or rams a tier row in T21; T22 adds the sphere sweep and the fire). So the near
  brains see far ships as contacts, `row_of_id`, the handles (negative for a tier row) and `rows_digest` hold them, while the
  kernels that write to a body or fire from one skip them: the hosted drivers' step holds a tier ship (the tier replaces the
  far think rate for it; T22's tier brains think for it), the cannon kernel fires nothing from it, the weapon rows treat a
  tier capital as having no row (its turrets, beams, launches and strike wait for T22's aggregated fire), the selection check
  leaves its parked controller alone. The scan GDScript builds from the core (`snapshot`, the first `node_count` rows) never
  carries them. A rebase shifts the tier table and the pull's sources with the rows.
- **Promotion and demotion.** `TierDirector` runs at -12, before the core's first sync, so a tick's rows never hold a body
  and its tier row at once. Each tick the core names, from the rows as the last sync left them and the player's position
  (`AiPilotDriver.driver_frame`), the fighters and capitals in Jolt beyond `tier_radius_m` plus 10 % (`tier_far_bodies`;
  the player's own body left out) and the tier rows within `tier_radius_m` (`tier_near_rows`): the hysteresis keeps a ship on
  the line from flipping every tick. The director hands over at most 64 of them a tick, promotions first (a battle's start
  would otherwise park hundreds in one tick); the budget counts successful demotions only, so a far body the director cannot
  demote (a ship outside the pool) never uses one up. A demotion reads the body's pose and motion through the same getters the core
  reads (so the row starts bit for bit where the body was), its held command (`held_command`: the row command when it flies
  one, else the ship's own command and trigger; that fallback carries the ten scalars and the trigger only, so a GDScript-piloted
  ship's `autotrack` and its track and face directions are dropped in the tier, which matters little since native pilots fly row
  commands) and its assist state, adds the row with the ship's attributes, and parks the
  body: hidden and not processing, which takes it out of Jolt (`CollisionObject3D`'s disable mode removes the body from the
  space), out of the scan (its marker inactive) and out of every per-ship pass; its hosted driver is marked not live by the
  same notification the pool's parking sends, its cannon idles, its name, pilot, hull, selection and wing slot state stay.
  A promotion takes the row (`tier_take`) and sets the body's transform, velocities and assist state from it exactly, then
  shows it; the row command stays in the map, so the flight step flies it again at -1 and the ship's own command is what
  it left with. A capital goes with its turrets and emitters (children of its body) and comes back with them where they were.
  With no live player nothing moves tier; with `tier_radius_m` 0, or the core off, every row is promoted (the bodies come
  back where the rows had flown to; with the core gone, where they were parked, re-placed in today's frame from the world's
  origin at park time, since the rebase skipped them). A pooled ship released while tiered takes
  its row with it (`ShipPool.release`); a capital freed by the bench's `clear` loses its row at the next tick.
- **A hulk's promotion** brings the body back as a hulk: `Ship.hulk` (its assist off for good; `set_hulk` clears its command),
  its pilot dropped, its trigger released, so it coasts under Jolt as it drifted in the tier; demoted again it goes back into a
  row as a hulk. The pool clears `hulk` when it hands the ship out again. Today nothing disables a ship without destroying it, so this
  is a row state and a test, not gameplay.
- **What a tier ship is not, in T21.** Not hittable (no sweep, no ram, no blast: T22), not drawn (T23: a dot from its row; its
  far dot leaves with its hidden body), not on the player's radar or targetable by the player (both read active markers; T23),
  not fuelled, not heard. It stays a wing member: `WingDirector` counts a tier-parked, undestroyed ship as in play, so a
  wingman keeps its slot and a group leader its lead. Not a GDScript contact either: the contact field attached to the core
  reads only the rows the GDScript scan holds (`Rows.tier_rows` marks the tier rows at the end), so a GDScript pilot never gets
  a tier row's index; native brains still see tier rows. A hosted driver over a tier row (rare: a parked ship's driver is not
  live) counts in its own events slot, `ai.tiered`, not in the far rate's `held`. Its parked node keeps its last pose: readers of a
  tiered ship's node position (the pool's console list) see where it was demoted, not where its row is.
- **Bit for bit.** The handover copies: a demotion's row equals the body's pose, motion, command and assist state, and a
  promotion's body equals the row's (`test_tier_handover`: 100 handovers over a 20 s flight with no handover error at all,
  on both of T24's schedules). Its scan is not a copy check: the core steps the tier for the current tick before it reads the
  bodies, so a tier row leads the body rows by one tick's motion (a demotion shows two ticks' motion in one scan step, a
  promotion the same pose twice), and the test checks every scan step across the handovers stays within a tick's motion of the
  ship's path. The integrator itself is not Jolt (a 20 Hz force update against Jolt's 60 Hz step; the same
  flight maths), so a ship demoted and promoted flies a slightly different path from one that stayed; the near set, which
  is what the player sees and fights, is untouched. One thread and six give the same rows with tier rows among the
  contacts; `threaded` equals `delayed` (the tier runs on the main thread inside the sync; the job only reads its rows).
- **The rebase** (refactor finding 11) walks the shiftable group once: the nodes it moved are kept for the end-of-tick
  interpolation reset, and a body parked for the tier is left where it stands (its row moves with the core and promotion
  places it); a second rebase before the end-of-tick settle keeps the first one's nodes. **Since M6-T21 the walk is a kept
  list**, `ShiftableRegistry`: the group's nodes in play, World by World, kept from the tree's `node_added` and
  `node_removed` (no site registers by hand), with what the pools and the tier park (`ShiftableRegistry.set_out`: the
  tier's and the pool's parked ships, idle debris chunks and effect emitters) out of it until they are back. A node that
  joins the group after entering the tree (test fixtures; `Projectile` now joins in `_init`) is caught by comparing the
  group's size with what is known before each walk, which reads the group again. The velocity rebase walks the same list.
- **Settings and console.** `tier_radius_m` (10 000 since T23; 0 = off, live), `tier_hz` (20, live). Provider `tier`: `radius_m`,
  `period_ticks`, `fighters`, `capitals`, `rows`, `hulks`, `promotions`, `demotions`, `step_us` (the tier's integration inside
  the sync), `director_us`. Provider `perf` and the bench's entity counts gain `tier_fighters` and `tier_capitals`;
  `fighters_far` counts a tiered fighter as far.
- **Tests.** `test_tier` (the integrator on a hand-held tick: coasting keeps the velocity and spin bit for bit, the pull equals
  the stand-in's, a held command pushes and the ceiling holds, the assist's held acceleration, the capital's cap, a hulk drifts
  and stays, the rows join the scan after the statics flagged tier, a rebase shifts rows and pull once, the candidate walks,
  take hands the state back exactly), `test_tier_handover` (above), `test_sim_core` (the tier's guard; `slot_of` bounded over
  spawn and release cycles, an old handle to a reused slot refused), `test_world_frame` (the rebase and the parked body).

**Tier brains and fire (T22).**

```
native/src/tier_fire.rs          the fighter shot's chance, the seeded roll, the soft fire gate, the far capitals' chances and their
                                 nearest hostile fighter; engine-free, under test_sim_core's guard
native/src/brain_step.rs         a hosted driver handed to the tier thinks on the tier's beat in the AI step's job
native/src/cannons.rs            a tier ship's parked cannon fires through its own gate in a pass of its own; each shot a roll
native/src/weapon_rows.rs        a far capital's guns, beams and interceptors once a second, its launches resolved at launch
native/src/sim_core.rs           the hit sweep's rows: the hull rows, then the tier rows (sweep_rows, sweep_columns)
src/ai/tier_director.gd          hands a fighter's driver to the tier, lands the rolled hits, keeps a row's hull, the costs
src/combat/destruction_director.gd   a tier death where its row flew; every death's blast on its killing hit
```

- **Brains.** A tier fighter's hosted driver is handed to the tier (`AiPilotDriver.set_tiered`, `ScsBrains.set_driver_tiered`)
  when it is demoted, so the AI step's job (T24, on the worker thread, one tick behind) keeps thinking for it on the same rows
  and contact grid as the near brains, every `tier_brain_hz` (3 since fix round 2: every 20 ticks, staggered by the driver's ordinal;
  at once when it is handed over). A tier think is lean (fix round 2, Q65): it skips the rocks and mines, the incoming fire
  and the avoidance, which a tier row cannot use (it collides with nothing and dodges no bolt), and its nearest-contacts
  query walks the ships' rows in scan order (`contact::nearest_among`), the same contacts as the grid's gather for fewer rows
  and no sort. A think went from 10.65 to about 2.5 us. 2 Hz was tried and failed the loose fairness checks (the raiders
  lost half their hits). A hit does not wake a tier think (fix round 1): it waits for its beat, so the thinks stay staggered
  however the far hits fall (every landed hit used to wake one, and a ship hit every tick thought every tick). The job counts
  and times the tier thinks (`ScsBrains.tier_thinks`, `tier_think_us`, on the job's own clock: the worker thread when threaded,
  the main thread on the inline step, until M4-T37 removed it). Its command goes to the core's row commands, which the tier's integrator flies; its driver
  gets no event (its node is parked). A ship whose native pilot the host does not step yet waits in Jolt until it does, so no
  tier ship is left without a brain. A hulk never thinks. The think also writes what the roll reads with the command: the
  target the pilot wants, its aim error and its fire gate (the miss distance and the cone).
- **A new command flies at once** (fix round 1). A row whose command a think wrote since its last beat (`RowCommand.seq`)
  gets its beat in the next tier step rather than at its stagger: waiting for the beat added up to two ticks of steering lag
  on top of the step's one-tick handover, enough to swing a 4 Hz pilot's nose off its gate, and made the tier's fights
  differ between the inline step (removed by M4-T37) and the threaded step (the same seed's raiders held their trigger 62 %
  more ticks on inline).
- **A fighter's fire.** Its parked cannon (`ScsCannons`, T35) keeps its gate and capacitor: in a pass after the near cannons
  (a tier shot makes no bolt, so the bolt order holds) the gate fires on the row command's trigger as on the body, and each
  shot is a seeded roll against the pilot's target, with no bolt row. The chance (`tier_fire::hit_chance`) is a circular
  Gaussian miss against the disc the hull presents (0.78 of its bounding radius plus the bolt's hit radius; 0.7 until M7-T16, and
  still 0.7 for a far capital's gun): the miss spread by
  the gate's miss distance, the nose's wander (0.007 rad), the pilot's aim error (its skill) and the target's manoeuvres over
  the bolt's flight (8 m/s^2, the flight time from the range and the closing speed), and offset by how far outside the gate
  the row's nose points (a 4 Hz brain holds its trigger for a quarter second after a near pilot's gate would have closed),
  then scaled by the shooter hull's term (`ShipSpec.tier_hit_scale`: 2.3 for the allied Starfury, 2.8 for the raider since
  M7-T16, 0.92 and 1.25 before; a 4 Hz brain flown at 20 Hz changes each hull's shots differently, and the term evens the sides). How the constants were found,
  never on the seeds the fairness tests use (fix round 1): the model's by maximum likelihood over every full-fidelity shot of
  six 12 against 12 melees (seeds 11 to 16, 2 853 shots) and of ten rounds of head-on duels (seeds from 50 000, 3 284
  shots), each hit matched to its shot; the hull terms from the tier against full fidelity in the even fight (12 Starfuries
  against 40 raiders, the maintainer's Q63, found by a full-fidelity sweep) on seeds 101 to 103, both schedules (the Cycle
  log has the sweep and the steps). **M7-T16 refit.** The raider's hull became its reference model's: a smaller bounding radius
  (8.4 m, was 8.8) with more hull across a shot's path, so full fidelity hit it 17 % more while the model's size term shrank,
  and the tier had drifted below full fidelity since M4 (the even fight on the test seeds: 449 tier hits against 761 with the old
  hull). Refitted the same way, never on the test seeds: the size share by matching the model's expected hits to the landed ones
  on held-out duels (seeds from 50 000, 3 521 shots: 0.80) and the 12 against 12 melees (seeds 11 to 16, the shots matched to the
  hostile nearest the nose: 0.75), 0.78 taken; the hull terms on the even fight's fit seeds, widened to 101 to 106 because three seeds flipped the win share on margins of a
  few hundredths (2.3 and 2.8: the tier's Starfuries win 4 of 6 against full fidelity's 3; Starfury hits 378 in the tier against
  452, raider hits 930 against 1 227, mean hull loss 1.55 against 2.04 and 1.58 against 1.88; at 2.2 the tier's Starfuries win 1
  of 6, at 2.4 five). The raider's term barely moves its hits (2.6 to 3.8 gave 972, 786 and 868): its close shots already roll
  near certain, and a tier raider takes fewer of them than a full-fidelity one. The draw (`tier_fire::roll`, SplitMix64 over the seed (the bench's,
  `TierDirector.seed_value`), the core's own sync count, the row's ordinal and the muzzle) is the same on every thread count
  and every run of a seeded fight; the beat keys on the core's sync count too (T21 keyed it on the engine's frame). The hits wait in the core
  (`tier_take_hits`) until the director's next tick (-12), which lands each through the target's `Damageable.apply_hit`
  (a `HitInfo` of cause bolt with the shooter's faction), so the hull, `hit_taken`, `damaged`, `destroyed`, the score, the
  wing's losses, the pool's release and the respawns all run as for a near hit; a kill parks its ship before the sync.
- **Hits on a tier row.** The hit sweep tests the tier rows after the hull rows (`sweep_rows`; the resolver reads
  `sweep_columns`, the ram resolver keeps `hull_columns`): a near ship's bolt lands on a tier ship's hit shapes at its row's
  pose and hurts its `Damageable` (no flash on a parked node). The ram phase, the strike target, the mines' blasts and the
  near turrets keep to the hull rows (a tier ship is not rammed, struck or turret-targeted by near ships). The director
  watches each tiered body's `damaged` and writes its hull to the row, which the brains read.
- **A far capital's fire** (`ScsWeaponRows.step`): once a second each (staggered), its guns roll as one group against the
  nearest hostile fighter within 4 km (near or tier; `tier_fire::turret_chance`: the gun's 1.5 degree gate and the fighter's
  manoeuvres over the bolt's flight), its beams (each every 2 s, alternate seconds) against the nearest within the strike
  reach when it is inside 3 km (0.95), and its interceptors remove up to two hostile missiles each within 1.5 km (the near
  interceptors' pick, sharing their spent mask; a removal is certain, as a near interceptor's shot is, not a roll). Its
  launches join the mix's top-up in turn: a far capital's missile is resolved at launch (the hit rolled from the range,
  `missile_chance`), counts in flight until it would arrive (350 m/s), and then is shot down when an interceptor hostile to
  it (on a near or a tier capital) came within its reach of the missile's path (from its capital to the target) with a shot
  to spare that second (two a second each),
  else lands if it rolled a hit and the target still flies, is not a hulk, and is on the hull life it was launched at
  (`Damageable.life`, bumped by every restore: a released and re-used pool ship is not the same target). The standin
  director lands the hits through `land_hits`.
- **Rams** (fix round 1). A committed rammer (its row command's `ram`, which the tier thinks note too) meeting its target
  where one of the two is a tier row, tier against tier or near against tier, lands ram damage once on first contact: the
  core finds the pairs whose straight paths come within 0.7 of their bounding radii summed over the tick
  (`tier_ram_contacts`), and the director lands them by the near swept rule (`RamResolver.ram_pending`: each hull's share of
  the velocity change when the two move on together), through the ram resolver when there is one so `ram_resolved` hears
  them. Two near ships ram through the ram resolver as before.
- **Deaths.** A tier ship destroyed goes through `DestructionDirector` as a near one does (released to the pool, its row
  with it, `ship_destroyed` and `raider_destroyed`), its pose read from its row (`TierDirector.row_pose`), with no explosion
  or debris (since T23 a far death is drawn by the explosion level of detail). Every pooled ship's or the player's killing hit carries the
  death's blast (`HitInfo.blast_energy_j`, `blast_radius_m`, `blast_point`; placeholders until M12 sizes a blast by class and
  cargo: 1e5 J a kilogram of hull, four bounding radii), for T23 and M12.
- **Cost.** The tier's main-thread work (the integration, the cannons' tier pass, the landing; the far capitals' rolls and
  launches, with their share of the integration) is timed and its means since the bench window began are `tier.cost_us` and
  the bench summary's tier line, beside the tier thinks (count, most in a tick, their time on the step's clock): at `battle`
  500 0.20 us a fighter row on the main thread plus 0.12 us of thinks (on the worker thread; on the main thread under the inline
  step, which existed at the time), 0.31 us a capital row (fix round 2; it was 0.24 plus 0.72). The main thread's share is the integration with
  its flight beats (about 0.1 us), the cannons' tier pass (0.04) and landing the hits through `Damageable` in GDScript
  (about 14 us a hit, 0.06 us a row). The row commands use an id hasher (`CommandMap`), the core keeps a tier row's hull
  from `note_hull` (no per-ship hull signal in the director), and the landing finds hulls through a cache.
- **Settings and console.** `tier_brain_hz` (3, live; 4 until fix round 2). Provider `tier` gains `brain_period_ticks`, `shots`, `hits`,
  `hits_landed`, `land_us`, `capital_rolls`, `capital_hits`, `capital_fire_us`, `cost_us`.
- **What a tier ship still is not, after T22:** drawn, on the player's radar or targetable by the player (all three since T23); struck
  by a near capital's missiles or targeted by its turrets; selected on its parked targeting (its pilot's target rides in its
  row command; the driver selects it again when promoted).
- **Tests.** `test_tier_fire` (the chance's shape, thinks at `tier_brain_hz`, the brain steering, rolled shots through the
  `Damageable` with no bolt row, one thread and six rolling the same hits, a near bolt on a tier row, a tier kill through the
  destruction director with its blast, a near death's blast, a far capital's group rolls, launches resolved at launch and
  counted in flight, interceptors; fix round 2: a tier think does not avoid; fix round 1: thinks timed and kept on their beat, far missiles shot down, the tier's rams,
  the seed, a far missile on a re-used ship, a kill by a roll through the wing, a pending hit after a promotion, a hit on a
  hulk), `test_tier_outcomes` (slow: the duel, the even 12 against 40 for seeds 1 to 3 with the per-side bound reported
  pending, a cruiser against 12 fighters, far missiles' share shot down, each tier against full fidelity on both schedules), `test_sim_core` (the guard on `tier_fire.rs`),
  `test_tier_handover` (a tier ship thinks at the tier's rate).

**Far proxies, the radar and the explosion level of detail (T23).**

```
native/src/tier.rs               adds each row's proxy (a far dot's paint, or a far hull class), fill_dots, fill_hulls and
                                 clear_of_statics (a promoted row moved clear of a rock or mine), engine-free
native/src/tier_rows.rs          tier_set_proxy, tier_fill_dots, tier_fill_hulls, tier_targets, tier_target, tier_position,
                                 tier_cleared; tier_take clears the row of the statics first
native/src/sim_core.rs           radar_contacts (the radar's contacts from the rows); select answers a parked marker from its
                                 tier row (the broadcasts); tier rows carry their ship's selection
native/src/radar_kernel.rs       the radar sphere's plot (RadarModel.plot's maths), engine-free; radar_plot.rs is its shell
                                 (ScsRadarPlot)
native/src/weapon_kernels.rs     a mine's trigger and blast over the sweep's rows, tier rows among them (mine_can_hurt)
src/rendering/far_dots.gd        FarDots: the tier fighters as a second source in the same buffer
src/rendering/far_hulls.gd       FarHulls: the tier capitals, one MultiMesh per mesh their bodies draw
src/rendering/far_flashes.gd     FarFlashes: far deaths as point flashes in one MultiMesh (far_flash.gdshader)
src/combat/explosion_lod.gd      ExplosionLod: the level from the distance and the hull's size; the flash's maths
src/targeting/tier_targets.gd    TierTargets: tier ships as targets, by marker id, from their rows
```

- **Drawn.** At demotion the director gives a fighter's row its hull's paint (`FarDots.asset_paint`) and a capital's row the
  class of the mesh its body draws (`FarHulls.class_of(CapitalStandin.drawn_mesh())`; the box look shares one mesh per class).
  Each frame `FarDots` writes its near ships' dots and then asks the core to write the tier dots after them into the same
  buffer (one draw call), and `FarHulls` asks the core for each class's transforms. A promotion takes the row and shows the body
  in the same tick, and a demotion parks the body and adds the row in the same tick, so a ship is drawn by one of the two in
  every frame. The far proxies' CPU update at `battle` 1 000 is about 0.2 ms a frame (580 dots and 97 hull instances), under
  the 0.5 ms that would have called for a compute pass, so none was built.
- **Radar and targeting.** A tier ship's marker is parked, so the player's candidates, a selection, its readout and the nearest
  hostile read the row by the marker's id (`TierTargets`): the selection names the same `Targetable` before, during and after
  the tier. A controller whose own ship is in the tier reads its own position from its row. A tier think that names or drops a
  target hands it to the parked controller (`EVENT_SELECT`, never the nearest-hostile retarget), and the tier rows carry that
  selection, so a promoted ship holds its brain's target. The broadcast scan hears a parked ally from its row. The radar reads
  its contacts in one pass over the core's rows (`radar_contacts`, markers and tier rows) and plots them in the native kernel,
  in the GDScript's steps and precision; with the tier's ships back on it a `battle` 1 000 frame plots about a thousand
  contacts, and the GDScript walk and plot had cost 73 to 52 FPS (a frame's work comes back about 2.5 times through the extra
  ticks a slower frame runs).
- **Promotion inside a rock.** A row collides with nothing, so `tier_take` first moves it clear of every static row it
  overlaps (rocks and mines) by the shortest way out plus 5 m (fix round 1; first along its velocity, which could carry a
  fighter across a 300 m rock): a fighter as a sphere of its bounding radius, a capital as its hull box (`tier_set_box` at
  demotion), so a grazing rock moves a carrier by the graze, not by its 614 m bounding radius. Eight passes for rocks that
  touch; a row still overlapping after them stays where the last pass put it. `cleared` counts them. A release or a death in
  the tier removes the row with `tier_remove` (no clearance, not a promotion).
- **The explosion level of detail** (fix round 1: from pixels, not fixed radii). The level follows the fireball's final radius
  (1.2 bounding radii) on the current 3D picture (`ExplosionLod.picture_lines`: the window's lines times the 3D scale, 1 080
  headless): the full `Explosion` while it is 8 px or more, a reduced one (no light, the gas shell only, no debris) down to
  2 px, then a point flash in `FarFlashes` with no node and no particle. The flash starts as big as the fireball and as bright
  as the explosion's glow (2.4 / 1.7 / 1.0), so at the switch it delivers the reduced effect's light; it shrinks to its 1 px
  floor at twice the switch distance and then keeps the pixel and dims with the square of its real size (the inverse square of
  distance) until it delivers under a quarter of its peak, at four times the switch distance. Its length grows with the cube
  root of the blast's energy. At 1 080 lines and 70 degrees: a fighter (9.3 m) full to 1.1 km, reduced to 4.3 km, its flash
  reading to 17 km; a destroyer (307 m) 36, 142 and 570 km; a carrier (614 m) 71, 284 and 1 140 km; at 2 160 lines all twice
  as far. The first build switched at 250 and 800 bounding radii and sized the flash from the energy alone (3 m for a raider,
  48 m for a carrier), so the flash took over already under its own visibility bar. A tier death flashes where the row flew. A
  capital stand-in's death (`DestructionDirector.watch_capital`) is drawn the same way, takes the capital out of play and out
  of the tier, and emits `capital_destroyed`; the stand-ins' counts leave a dead capital and its weapons out. Every death's
  killing hit carries its blast's energy, radius and point (M12).
- **Mines on the rows.** A mine's trigger and blast read the sweep's rows (the near hulls, then the tier rows), so a tier ship
  sets a mine off and is hurt by it, in the core's order; `StandinDirector`'s GDScript walk of the hulls is gone (Q68).
- **The default.** `tier_radius_m` is 10 000 again. The far-ship tests read where a tier ship flies and whether it is in play
  (`TierDirector.flying_position`, `flying_velocity`, the pool's in-play list), not its parked node.
- **Console.** Provider `tier` gains `proxy_dots`, `proxy_hulls`, `proxy_us`, `flashes`, `cleared`; `kill target` destroys any
  selected target with a hull.
- **Tests.** `test_tier_proxies` (every tier row drawn and on the radar, one multimesh per capital mesh, the handover frame, the
  selection through promotion and demotion, candidates and broadcasts, the rock for a fighter and for a capital by its hull, a
  release or death not counted as a promotion, a mine's blast on a tier row, the bench counts without a dead capital),
  `test_explosion_lod_maths` (the levels from pixels, the switch moving with the lines, the flash visible at the switch with the
  reduced effect's light for a fighter, a destroyer and a carrier at 1 080 and 2 160 lines, the floor and the inverse square,
  the reach), `test_explosion_lod` (near, reduced, far, a tier death, a carrier at 14 km full, a cruiser past its switch as a
  flash, `kill` on a capital), `test_mine_kernel` (the
  core's order), `test_sim_core` (the guards on the new kernels).

### 17.16 Rocks and mines as static rows (T29)

```
src/world/static_rows.gd            StaticRows: the rows with no node (rocks by RID, mines), registered once, moved by their world's rebase
src/combat/hit_broad_phase.gd       + keep / kept_pairs: hulls that stay put kept in a grid of their own between calls
native/src/hit_sweep.rs             + ScsHitSweep.keep / kept_pairs, the same grid natively
native/src/contact_field.rs         + set_friendly_row; statics(..., faction, ...) hides other sides' mines (Q27)
```

- **What it ends.** T07 gave each rock a bare marker node with a `Damageable`, so the contact scan's members, the hit resolver's
  gather and the ram resolver's gather walked 1 000 rock hulls every tick (the ram resolver built a Dictionary for each), and the
  rocks were contacts that filled turrets' and fighters' lists. Measured on T29's base: about 8.5 ms a tick at `typical` 58 and
  10 ms at `battle` 100. Now no rock and no mine has a node, and no per-tick path walks them.
- **The store.** `StaticRows` (static, like `ContactScan`'s caches) keeps id, position, radius, faction, `BodyKind` and owning
  world per row, in registration order. `register` and `unregister` (or `unregister_many`, one pass) are the only ways in and
  out; `ContactScan.register_static` and its siblings now call them, so T09's API is unchanged. `version` changes with any row;
  `solid_version` only when a solid row (kind `STATIC`) does, so a mine coming and going never rebuilds the rocks' grids. A row
  belongs to the `WorldFrame` it was registered with: `WorldFrame.rebase` calls `ContactScan.shift_statics(shift, self)` (T09's
  line), which moves only that world's rows, once. Ids are unique and never instance ids: a rock's is its body's RID id, a mine's
  comes from `StaticRows.new_id` (`rid_allocate_id`, so no RID shares it either). `registrations` and `solid_builds` are the work
  counts the tests read.
- **Rocks.** `AsteroidField.build(rocks, space, world)` registers each rock (kind `STATIC`, neutral, its radius) as it makes the
  RID body, and `free_bodies` removes the rows with the bodies. The field keeps only its multimesh node; `on_rebased` still moves
  the RID bodies (a node rebase does not reach them), the rows move with the world.
- **Live rocks (M6-T21).** Only the rocks a rigid hull could reach soon are live Jolt bodies (`RockBodies`, shared by the
  stand-ins' field and `AsteroidBelt`): each tick, late (just before `sync_out`), the native `ScsRockStream` sweeps the core's
  rigid rows, seen in the owner's frame and moving against the rocks at the World's rest velocity, over a grid of the rocks
  that no rebase or drift changes. A rock within `0.25 s` of motion plus 20 m of a hull comes to life; one is demoted once no
  hull has been within that reach plus 10 % for 30 ticks (a hull destroyed against a rock leaves the rows before it leaves
  Jolt). A dormant rock keeps its body with layer and mask 0, never moved, so `on_rebased` and every drift place only the live
  ones; a rock that comes back is placed under its owner exactly as one that lived along. The bodies stay in Jolt rather than
  leaving its space so no body is made again: Jolt orders contacts by body id, so the battle's bits hold. The hit sweep, the
  rams and the scan read the rows, never the bodies, so nothing about a hit or a ram on a rock changes.
- **Mines.** `MineStandin` registers every mine in play (kind `MINE`, its layer's faction, the trigger's 50 m as its radius, the
  director's world) when the belts are laid; a mine that goes off is unregistered at once, and laid again 10 s later it is
  registered again with the same id at its place. Leaving the tree (`remove_mines`, the director's `clear`) unregisters the
  rest. Mines are not solid: bolts and rams pass them, as before; the mine's own trigger is what sets it off.
- **The scan.** Both paths append the static rows whole after the node rows (`append_array` of `StaticRows`' columns and of
  constant columns cached per `version`), so the GDScript reference does not walk them either; the registry gets
  `set_statics` only when `version` changes. Rows of kind `STATIC` and `MINE` stay out of every contact list (T09); turrets'
  retargeting and the fighters' nearest-k no longer see rocks at all.
- **Mines by faction (Q27).** `statics_for(own, at, faction, k)` keeps a rock for everyone and a mine only when its faction is
  friendly to the asking one (its own included, `Factions.relation` FRIENDLY): a side steers round its own and its friends'
  mines and never knows where an enemy's are until they go off (and then they are gone from the rows). The GDScript path builds
  a per-faction flag row once per scan; the native field gets the same flags per faction (`set_friendly_row`, built from the
  same relations, like T05's hostile rows) and filters inside `statics`, so the two give the same statics bit for bit
  (`test_contact_field`, four sides with one friendly pair).
- **Bolts on rocks.** `HitBroadPhase.keep(mids, reach)` holds hulls that do not move; `kept_pairs(bolt_mids, bolt_reach)` gives
  exactly what `pairs` would with those hulls, in the same `bolt * hulls + hull` order, from the same five-level grid built once
  (on each path when first asked after a `keep`). The hit resolver keeps `StaticRows.solid()` there and calls `keep` again only
  when that changes (a rock added, removed or rebased). Per bolt it takes the earliest of its node-hull hit and its rock hit
  (a node hull on a tie). A rock is a sphere of its radius swept by the bolt's hit radius (`SweepMath.segment_sphere`, which is
  what the old marker's capsule of zero length did); any bolt of another faction stops on it (the marker's `hit_by_anyone`),
  is spent, throws sparks and emits `hit_resolved` with the rock's row id as the target; nothing breaks. The impact flash that
  hung on the marker is gone (there is no node to hang it on). `hulls_last_tick` and `static_pairs_visited` are the work counts.
- **Ships into rocks.** The ram resolver keeps its own kept grid of the solid rows. Each tick every rigid hull asks it for the
  rocks within half its move plus its bounding radius plus `RamResolver.MARGIN_M` (`RamBroadPhase.MARGIN_M` until M4-T42); each candidate goes through the same swept
  test as a prop (any touch rams), with a hull per rock made on first contact and kept (a sphere of the rock's radius,
  invulnerable, `SOLID_MASS_KG`), so the outcome is the old marker's: the ship takes the whole closing speed, the rock nothing.
  Jolt's own bounce off the RID body is unchanged (its contacts never named a rock: the RID body has no object id).
- **Why nothing changes for fighters.** Furball, spread and transit have no rocks and no mines, so the rows are empty, the kept
  grids answer nothing and every contact list is what it was; the seeded outcomes matched the base with `perf_native` on and off (before M4-T37).
### 17.17 Splats against meshes: the render comparison (T27)

History (M4-T31): this subsection records the comparison that led to Q29. T31 removed the point-cloud side and the painted mesh
(`core/paint_mesh.py`, `PaintMeshes`, `PaintMeshLights`, the paint shaders, `settings.ship_render` and `ship_mesh_beyond_m`);
`scripts/render_compare.sh` stays as the scene measurer, without its render argument, and `RenderPiece` draws only the textured mesh.

```
tools/procgen/core/glb.py              a binary glTF writer (and a reader for tests): positions, normals, one UV set, a material a primitive
tools/procgen/core/paint_mesh.py       the painted mesh: a hull's parts as one glb, the paint codes in the UVs, the manifest's paint_mesh
tools/procgen/core/pieces.py           a big piece both ways: splat levels centred on their own centroids, and its painted mesh
tools/procgen/assets/b5_station.py     the Babylon 5 station stand-in (shape only): a turning drum and a stationary frame, 8 km
tools/procgen/assets/capital_hulls.py  the capital stand-ins' boxes as splats and painted meshes
assets/shaders/paint_mesh*.gdshader*   the paint shader: Style.shade_panels and GDGS's relight factor on the GPU
src/rendering/paint_meshes.gd          PaintMeshes: loads a painted mesh and puts one shared paint material on each surface
src/rendering/paint_mesh_lights.gd     PaintMeshLights (under Main): the light rig's 8 lights into every paint material, each frame
src/rendering/render_piece.gd          RenderPiece: a piece's splat levels (by projected spacing) or its painted mesh
src/perf/standins/station_standin.gd   StationStandin: the station's two pieces, the drum turning
src/perf/station_scene.gd              StationScene (under Main): the station, 10 capitals, 80 fighters, the planet; `station_scene near|far|off`
scripts/render_compare.sh              one scene one way, fullscreen, the 3D at 1 080 lines, measured like the fullscreen check
scripts/probe_draw_calls.gd            what one hull costs in Godot's draw calls, by kind
```

- **What it is for.** Q24: whether the big battles are cheaper drawn as Gaussian splats or as polygon meshes at the same shapes and
  detail, measured on the maintainer's GPU, so the maintainer can decide whether splats stay. The simulation does not depend on it.
- **The painted mesh.** The splats are sampled from the parts' meshes and painted by `Style.shade_panels`; the generators now also
  write those meshes (the hull parts the fallback OBJ holds, so the same triangles and bounds) as `<asset>_mesh.glb`, with each
  vertex's part phase and material as whole numbers in its UV (`u = px + 97 py`, `v = pz + 97 material`, the phase in 97ths of a
  panel as `_phase` already quantises it). Vertices are split per material; opaque faces are one primitive and see-through faces
  (canopy glass) a second, so a ship is one opaque surface. The manifest's `paint_mesh` holds the material table (linear albedo,
  paneled, transmittance) and the panel grid. Godot's scene importer builds the mesh's levels of detail; the mesh is drawn with
  the engine's LOD and no instancing of our own (see the cycle log for what the renderer does with many copies).
- **Paint and light like the splats.** `paint_mesh.gdshader` is unshaded and does the splats' sums itself: the panel lines and
  per-panel tint of `shade_panels` on the lattice projected along the normal's dominant axis (a different hash for the tint, the
  same ±jitter; lines faded to their mean once a panel is a few pixels across), then GDGS's relight factor over the same 8 lights
  (`PaintMeshLights` packs the rig's lights in GDGS's layout) with `relight_unlit_level`, `relight_ambient` and
  `relight_light_gain`, applied before the sRGB to linear step as GDGS applies it. Own lights (the cabin glow, the top lamp) are
  not on the mesh.
- **The switch.** `settings.ship_render`: `splat` (as before), `mesh` (every ship draws its painted mesh: a lean AI ship through its
  one hull node, which already drew the fallback mesh, so the node diet holds; the player's ship through its fallback node, the
  depth proxy hidden), or `hybrid` (splats near, the mesh past `settings.ship_mesh_beyond_m`, 400 m, back a tenth inside, decided
  by the `LodSwitcher` beside the far dot). Far dots stay on every path. The cockpit view keeps the OBJ it was built around. It
  applies live.
- **The pieces.** A capital stand-in draws its box (the bench's), or with `set_look` the `capital_hulls` box as splats (1/300 of
  the length apart, so about 60 000 a class, two coarser levels) or as its painted mesh (12 triangles). The station stand-in
  (`b5_station`, from `docs/design-references.md`'s proportions: drum 1/9 of the 8 km length across and 42 % of it long, reactor,
  truss spine, funnel with three pairs of vanes, the top bar with its cargo modules clear of the drum, the command sphere with its
  ring, arms and masts, the forked bow) is two pieces, each four splat levels (4, 8, 16, 32 m; 1.38 million splats at LOD0) and a
  painted mesh (10 000 triangles). A `RenderPiece` shows the coarsest level whose spacing projects to 2 px or less at its nearest
  point. The drum turns at 0.148 rad/s (1 g at its radius) each frame.
- **Levels for the lines drawn.** `LodSwitcherMath.render_height` is the window's height times its 3D scale; the `LodSwitcher` and
  `RenderPiece` pick levels from it, so a 4K window drawing the 3D at 1 080 lines (the fullscreen check) picks for 1 080 lines.
- **What was found** (the milestone's Cycle log, "T27 render comparison"): the painted meshes cost 2 to 3 times less GPU time than the
  splats wherever hulls are on screen, with the same draw calls and render CPU time; neither path binds the big battles today. A splat
  node adds no draw call (GDGS draws in its compositor effect); the depth proxy adds one per ship (its material is per node, so the
  renderer cannot instance it) at full triangles. Godot's Forward+ renderer instances identical painted meshes on its own.
- **Tests**: `test_paint_mesh.py` (the glb round trip, the codes, a vertex split per material, glass apart, the fighters' meshes hold
  their OBJ's triangles and their splats' box, deterministic), `test_render_pieces.py` (the station's two pieces, levels and
  centroids, 8 km and a ninth across, the drum on its axis and clear of everything stationary, the capital boxes), `test_paint_meshes`
  (the imported mesh, its materials from the manifest, the codes survive the import, the lights packed as GDGS packs them, a piece's
  level) and `test_render_path` (the switch live on an AI ship and the player's, hybrid with its hysteresis, dots on the mesh path,
  a capital's three looks, the station both ways with its drum turning).
### 17.18 The textured mesh pipeline (T30a)

History (M4-T31): T30a to T30d built this beside the M3 renderer, so the text below compares with it and names its switches
(`ship_render`, the painted and splat looks of the `sheet` command); T31 removed them. The textured mesh is the only path.

```
tools/procgen/core/geometry.py        Mesh carries a UV per face corner (metres) and a chart id; lathe and box write theirs as they tessellate
tools/procgen/core/uv_atlas.py        charts: the primitives' own, the rest unwrapped by normal regions; the shelf packer at one texel size
tools/procgen/core/raster.py          the atlas buffers: world position, normal, part, material, chart and sharp-edge distance per texel
tools/procgen/core/textures.py        the maps from the buffers: paint, markings (bands, a stroke font, decals, soot), wear, grooves, occlusion
tools/procgen/core/image.py           8-bit PNG writer and reader with zlib alone (no Pillow for the maps)
tools/procgen/core/textured_mesh.py   write_textured_mesh: the glb, the four maps with their .import sidecars, the manifest's mesh section
tools/procgen/core/manifest.py        validate_mesh_section: the contract's keys
tools/procgen/styles/__init__.py      Style.panel_lattice (what shade_panels paints, per point) and the wear, groove and hatch parameters
tools/procgen/assets/starfury_aurora.py  markings_for: the pods' bands and squadron numbers, the flanks' letters, the soot
src/rendering/mesh_assets.gd          MeshAssets: a hull's textured mesh with a StandardMaterial3D per surface (or T27's painted mesh)
src/rendering/paint_meshes.gd         PaintMeshes: the old name, a subclass of MeshAssets until T31
src/rendering/look_scene.gd           LookScene: the `sheet` command that parks one ship for the look sheets
src/environment/space_environment.gd  settings.ambient_level: the environment's ambient light, live
scripts/look_sheet.sh, look_sheet.gd  the look sheet: every shot and the composed sheet, on the real renderer
```

- **What it is for.** Q29: the renderer moves from Gaussian splats to procedurally textured meshes, and this is the pipeline every hull
  goes through from here (T30b converts the other assets, T31 removes the splats). It is also the contract M5's civilian ships are built
  against: the milestone's plan subsection "The contract M5 builds against" lists the files; this section says how they are made.
- **Charts and the atlas.** A `Mesh` now carries a UV per face corner in metres and a chart id per face; `lathe` writes the arc around
  the axis (at each ring's own radius) against the arc along the profile, one chart with its seam at the first vertex, and `tapered_box`
  (so `box`) one planar chart per side. Both ride through `transformed`, `mirrored` (the corner order flips with the winding) and
  `concatenate` (chart ids are offset, so a mirrored part gets charts of its own). Every other face (the hand-built lofts of the fuselage,
  struts and claws) is unwrapped by `uv_atlas.auto_charts`: regions grown over shared edges while a face stays within 40 degrees of the
  region's seed, each projected onto its mean plane. The packer sorts the charts by height onto shelves at the asked texel size with a
  two-texel gutter and grows the texel by 4 % a round until everything fits; the Starfury's 2 048 px atlas lands at 1.8 cm a texel
  (578 m² of hull, 1 705 charts, 76 % filled).
- **The buffers.** `raster.rasterize` draws every triangle in texture space with 0.6 texel of conservative padding (a sliver still marks
  the texels it touches; a triangle smaller than a texel marks the one under its centroid) and interpolates the world position and the
  part's smooth vertex normal, keeping the part, material and chart ids and the distance to the nearest sharp edge (creases over 35
  degrees and open rims, found by vertex position). `dilate` copies the buffers two texels into the gutters so filtering and the mipmaps
  read paint. Every map is then a function of these buffers, so the paint never depends on how a chart was unwrapped.
- **The maps.** Colour: `Style.shade_panels`'s own lattice per part (`panel_lattice`, the same cells, lines and tint the splats and the
  painted mesh had, with the part's phase), an inset hatch in some cells, the markings in world space (a band round an axis, text from a
  4 by 6 stroke font stencilled on the side facing a direction, flat decals, soot round a nozzle's mouth) and seeded wear (chips of bare
  metal along the sharp edges, streaks trailing aft from the panel lines, low-frequency grime), written sRGB. Normal: a height field of
  panel grooves and hatch bevels differentiated in texture space and scaled by the metres each texel spans (from the position buffer), in
  the texel's tangent frame with Godot's +Y up; a flat panel centre is (0.5, 0.5, 1). ORM: occlusion from a disk-to-point sum over
  surface samples of the whole hull (12 cm apart, within 0.7 m, every fourth texel and spread between), roughness from the material (rougher
  on the lines, smoother where chipped), metal from the material (bare where chipped). Emissive: the materials' glow colours (the nozzle
  throats, the canopy glass) scaled to the surface's strongest glow, which the manifest carries as `emissive_strength`, black elsewhere,
  written sRGB because Godot's standard material reads the emission texture as colour.
- **The files.** `<asset>.glb` holds the opaque hull as primitive 0 and the glass as primitive 1 (a glb vertex per mesh vertex and UV,
  the parts' smooth normals, no tangents: the importer makes them with `ensure_tangents`), beside `<asset>_albedo.png`, `_normal.png`,
  `_orm.png`, `_emissive.png`, each with a `.import` sidecar the generator writes (VRAM compressed, mipmaps, the normal map flagged, the
  albedo and emissive packed for colour and the data maps for data, 3D detection off), so a fresh import never lands at the lossless
  default. The manifest's `mesh` section (validated by `validate_mesh_section`) names them. The painted mesh (`_mesh.glb`, `paint_mesh`)
  is still written beside them until T31.
- **Godot.** `MeshAssets.for_asset` gives the textured mesh when the manifest has `mesh` (one `StandardMaterial3D` per surface: the
  albedo, the normal map, the ORM map's three channels, the emission map at the surface's strength, glass alpha-blended and two-sided at
  one minus the transmittance), else T27's painted mesh, cached per file so every copy of a hull shares its materials and the renderer
  instances them (20 textured Starfuries are one draw call per surface per pass; the probe's "painted meshes" phase with `asset=`). The
  hulls are lit by the Forward+ renderer: the rig's lights and `settings.ambient_level` (0.3 of white) on the environment, live. `Ship`
  drew whatever `PaintMeshes.for_asset` returned when `ship_render` was `mesh`; since T31 its `Hull` node always draws
  `MeshAssets.for_asset`.
- **The look sheet.** `sheet <asset> <m> [lit|dark|off] [livery] [view]` (until T31 it also took a look: `splat`, `painted` or `textured`) parks one idle pooled ship ahead of the chase camera
  three-quarters on, hides the player's hull and turns the key star to light the ship from over the camera's shoulder or from behind it;
  `scripts/look_sheet.sh` photographs every look at 8, 30, 150 and 600 m, lit and dark, and the cockpit view, fullscreen with the 3D at
  1 080 lines, and composes `/tmp/m4_t30_<asset>_sheet.png` with each tile's GPU time.
- **Tests**: `test_image.py` (round trips, byte-identical, the filters), `test_uv_atlas.py` (the lathe's and the box's charts, mirrored
  charts, the unwrapper, packing without overlap, texel density within 20 %, the texel growing to fit), `test_textures.py` (the sharp
  edges, the buffers, a sub-texel triangle, the maps' size and depth, the flat normal, the emissive mask, the albedo within the jitter,
  the ORM channels, determinism per seed, the font, a band and a stencil), `test_textured_mesh.py` (the contract's files and section,
  identical bytes per seed, the Starfury's mesh against its painted mesh and OBJ, the maps, the sidecars, the build time printed),
  `test_mesh_assets` (the imported surfaces and materials, the import flags, the painted path for the raider), `test_textured_hull` (the
  player's and a lean ship's hull node, the far dot, `ambient_level` live, the `sheet` command).


#### T30b: the Starfury refined and wing liveries (Q34 to Q37)

```
tools/procgen/core/livery.py          the livery table (Alpha, Beta, Delta, Zeta, the FNV-1a fallback, plain), stripe patterns and number
                                      fields as data, the digit distance-field atlas, the manifest's mesh.livery section
tools/procgen/core/textures.py        Plating per part (rows of varied height, panels of varied length, staggered seams, rivet rows),
                                      weathering from Style.extra, the normal map at twice the atlas, the fine-mesh normal transfer
tools/procgen/core/textured_mesh.py   4-texel gutters, zones in COLOR_0, the paint mask in the albedo's alpha, map_px, fine_mesh
tools/procgen/assets/starfury_aurora.py  render_triangles (a coarse rebuild of the round parts), textured_parts
assets/shaders/hull_livery.gdshader   the textured hull plus the wing's stripes and the ship's number from instance uniforms
assets/shaders/hull_glass.gdshader    the canopy glass: dark, see-through, the cabin's red glow at settings.cabin_glow_level
src/rendering/livery.gd               Livery: a ship's livery from the table (the player is Alpha 01), applied to a hull node
src/rendering/mesh_assets.gd          the livery and glass ShaderMaterials, the table as uniform arrays, the glow setting live
src/ship/ship.gd, src/game/ship_pool.gd  Ship.set_livery; ShipPool.acquire paints a Starfury from its callsign (ALPHA 2: Alpha 02)
src/rendering/look_scene.gd           the `livery` command and provider; the `sheet` command's livery argument
```

- **Why a shader layer.** Every Starfury must stay one material so copies instance (Q35); a texture set per wing would also blow the
  40 MB VRAM bar at 4 096 px. The maps stay livery-free. The glb carries each vertex's zone (fuselage, fittings, upper and lower struts,
  pods, claws, gun mount) in `COLOR_0`'s red, the albedo's alpha marks where paint may go (the hull paint materials, less worn edges and
  markings), and `hull_livery.gdshader` paints a pattern: a short list of stripes, each a band where a linear coordinate of the object-space
  position (`|x|` for a mirror-symmetric one) falls in a range, on some zones, on faces turned one way (the face normal from the position's
  derivatives). The two digits come from a 960 by 128 distance-field atlas of the stroke font, drawn inside number fields (a plane on
  some zones; the centre's y on the point's side, so one field serves an upper and a lower part). The paint is darkened as the base map
  is darker than the hull paint, so panel lines, grime and streaks show through it. The pattern table and the fields are material
  uniforms (from the manifest); a ship sets six instance uniforms: two colours, the number's colour, the pattern's index, the number
  fields' bits and the number. 20 Starfuries of four wings draw in the same 3 extra calls as 20 of one wing.
- **The table.** Alpha: yellow-green and dark blue-grey bands across all four struts; Beta: a blue band round each pod's front and a
  blue nose; Delta: a dark green arrowhead over the back and the upper struts, edged in sand; Zeta: thin red pinstripes and a magenta
  chevron; any other wing a stable pick (FNV-1a of the lower-case name, which `Livery.fnv1a` repeats) of six palette pairs (none red,
  magenta or maroon) and a pattern family no named wing uses (a diagonal sash, solid strut tips, two-tone struts; Q41); no wing the
  plain field grey with no number (enemies, unnamed ships). The base hull carries no colour of its own: T30a's hazard stripes are gone
  (Q41), so any colour is the livery's. Every wing numbers the dorsal deck large and the upper
  left wing small (Q37). The number is the callsign's: the slot in its wing from 1, two digits. A Starfury is painted when the pool
  hands it out (from its callsign) and again when it takes a place in a wing (`WingDirector`: the leader 01, slot n as n + 1), so a
  scenario wing's unnamed members fly their wing's livery. Hulls without a livery table (raiders) get no livery values.
- **The seam for a paint scheme.** A livery is data a ship is handed (`Ship.set_livery`); the player's is `Livery.player` (Alpha 01)
  until a setting or a front-end pick hands it another.
- **Plating and weathering (Q34, Q37).** The uniform world grid is gone from the textured mesh: each part gets a `Plating` from its name
  (mirror images share it) with rows along its longest side; rows vary in height, panels in length, and each row's seams are staggered.
  The grid is still projected along the axis nearest the normal, but measured on the surface with the chart's mean slope, so a slope keeps
  its panel size and a curved chart stays smooth. Rivet rows run beside every seam. Weathering comes from `Style.extra`: streaks trailing
  aft from the seams, smudges stretched fore and aft, speckle, worn edges that show dark primer (`bare_metal` 0: no metal), matte paint.
  The Earthforce hull is a medium weathered blue-grey (sRGB about 90, 97, 111, Q41) so it renders a medium grey under the key star.
- **The shader's derivatives.** Only per-instance values (the pattern, the fields, the number) choose the paths in
  `hull_livery.gdshader`; the zone, the facing and the paint mask are multiplied in, and the digits are sampled with explicit
  gradients, so no derivative or mip choice is taken inside a per-pixel branch.
- **The maps.** The normal map is baked at twice the atlas (4 096 px for the Starfury: the grooves, hatches and rivets at 1 cm a texel),
  from positions interpolated inside each chart; the albedo (RGBA, the paint mask), ORM and emissive stay at 2 048. Gutters are four
  texels of the 2 048 maps. The Starfury's textures take 32.0 MB of VRAM (bar 40 MB): albedo 5.6, normal 22.4, ORM 2.8, emissive 2.8,
  digits 0.02.
- **render_triangles.** The option rebuilds the Starfury's round parts with fewer segments (a binary search on a segment scale) and
  bakes the fine hull's smooth normals into the coarse mesh's normal map (inverse-distance weights of the fine vertices within 12 cm,
  same side of a plate), in the texel's tangent frame. The strut plates and fittings have no segments, so the Starfury floors at about
  18 000 triangles; T30d decides whether the coarse build becomes the default.
- **The cabin (Q36, Q37).** The canopy glass is dark and neutral; its emissive is a dark red cabin glow whose energy is the manifest's at
  `settings.cabin_glow_level` 0.3 and scales with it, fading out by `settings.cabin_glow_view_m`. The cockpit interior's surfaces are grey,
  lit by `MeshMaterials.COCKPIT_GLOW`'s subtle red and the red cabin lamp (`cockpit_light_energy` 1.0).
- **Tests**: `test_livery.py`, `test_textures.py` (plating, rivets, a tilted plate, the groove's handedness decoded with +Y up,
  weathering), `test_uv_atlas.py` (the 4-texel gutter), `test_textured_mesh.py` (zones, the paint mask, the digit atlas, the livery
  section's validation, the real Starfury atlas without overlaps and with even texel density, render_triangles), `test_cockpit.py`
  (Q36); GUT `test_livery`, `test_livery_hull` (Alpha 02 from a callsign, the player Alpha 01, plain without a wing, four wings on one
  material, the command and provider, the glass glow live, the grey cockpit lit red), `test_mesh_assets`.
#### T30d: every other hull textured, the mesh path the default

```
tools/procgen/assets/raider_fighter.py  the raider's textured mesh: its own darker paint, soot, the two engine glows, render_triangles
tools/procgen/assets/nav_buoy.py      the buoy's textured mesh and the beacon's lens (an amber glass collar under the beacon)
tools/procgen/assets/capital_hulls.py the capital boxes textured: plating sized to the hull, window rows on both flanks
tools/procgen/assets/b5_station.py    the station's drum and frame textured: bands, cargo modules, the command sphere's window rings
tools/procgen/core/textures.py        window markings (rows on a face, rings round an axis) that glow; wear_scale for big hulls
tools/procgen/core/textured_mesh.py   chunk cuts (a chunk's faces on the parent's atlas), the normal map's scale
tools/procgen/core/chunks.py          ChunkCut and the chunks' mesh entry; core/pieces.py the pieces' textured meshes
tools/procgen/build.py, __main__.py   one checked build, importable, so build --jobs N runs assets in worker processes
src/rendering/mesh_assets.gd          chunk_mesh: a chunk's glb drawn with its parent's materials
src/rendering/render_piece.gd         a piece's textured mesh, and pieces built without splat levels
src/props/nav_buoy.gd, src/combat/debris_chunk.gd   the textured body on the mesh path, the splats on the splat path
src/rendering/far_dots.gd             the dot's paint from the manifest's mean_albedo
src/rendering/look_scene.gd           the sheet parks the props too: the buoy, a ship's chunks, the capitals, the station
```

- **The mesh path is the default.** `settings.ship_render` defaults to `mesh`; `splat` and `hybrid` stay for comparison until T31. Every
  hull the game draws has a textured mesh: the Starfury and its liveries (T30a, T30b), the raider, the nav buoy, both ships' break-up
  chunks, the capital stand-ins' boxes and the station's two pieces.
- **Chunks share their parent's maps.** A chunk's glb is the parent's faces of the chunk's parts, cut after the atlas is packed, so its
  UVs are a subset of the parent's and its surfaces carry the parent's surface names; `MeshAssets.chunk_mesh` gives them the parent's
  materials, so chunks and hulls instance together. Each chunk is moved by its offset (for the Starfury, the LOD1 frame's chunk centroid
  plus the shift between LOD1's centring and LOD0's) so it sits where its OBJ sits. `hardpoints.json` `chunks[]` gain `mesh`. A Starfury's
  chunks wear the dying ship's livery (`DebrisPool.stage_wreck` and `burst` take it); raiders' chunks take none.
- **Big hulls.** The fighters' fine detail (rivet pitch, noise scales, edge softness) is sized for a texel of about a centimetre; a capital
  or the station is texelled at tens of centimetres to two metres, where that detail turns to speckle. `Style.extra["wear_scale"]` scales
  it, `extra["rivets"]` 0 drops the rivets, and the styles scale the grooves, hatches and edge wear themselves. Pieces bake the normal map
  at the atlas's size and without occlusion. Window rows are markings (`Marking.windows`, `Marking.window_rings`): dark glass in the
  albedo, a lit share of them in the emissive map at their own strength, which the surface's `emissive_strength` covers.
- **Paint for PBR.** The raider's splat hull (sRGB #A89F96) was chosen bright so the splats read; lit by the renderer it reads near
  white, so its maps take a darker worn grey-brown of their own (`styles/raider.py` `TEXTURED_ALBEDO`), and the station's and capitals'
  tones were darkened into the Starfury's range. The two engine glows are the main nozzles' throats; the nose intakes, which share the
  throat material on the splats, get a dark one of their own.
- **The stand-ins.** `CapitalStandin.set_look` takes the box or the textured hull, and `StationStandin` draws its pieces textured; both
  build their pieces without splat levels, so no splat node is made for them. The station scene's fighters still follow
  `settings.ship_render`.
- **Far dots.** A dot's colour is the asset's manifest `mesh.mean_albedo` (linear) lit as a hull's lit side, read once per asset; the
  splats' mean paint only for an asset without a textured mesh.
- **Levels of detail (Q45).** The fine Starfury stays the render mesh and `mesh.lods` stays empty: the coarse build (17 892 triangles,
  its floor) cut the triangles drawn at the 500 battle by 15 % and not the GPU time, and showed facets at 8 m; the importer's levels hold
  the battle at about 2 ms (the milestone's Cycle log, M4-T30d).
- **Building.** `build all` with every textured hull takes about 110 s one asset at a time; `scripts/gen_assets.sh` builds several at once
  (`--jobs`: `PROCGEN_JOBS`, else `nproc` capped at four; about 63 s with four on a 20-thread machine). The bytes are the same either
  way (tested). When a worker dies (an out-of-memory kill, say), the assets it left unfinished are built again in workers of their own,
  so only the one that kills its worker is reported failed, and the exit is nonzero.
- **Tests**: `test_textured_hulls.py` (window rows and rings, the normal map's scale, wear_scale, a chunk on its parent's atlas, the raider,
  the buoy, the station and the capitals, the Starfury's chunk meshes), GUT `test_textured_hulls` (the default, the buoy, a raider chunk,
  a capital and the station drawn textured with no splat node shown, the far dot's colour), `test_render_path` (the capital and station
  looks), `test_debris_pool` (a chunk on the mesh path).

### 17.19 The sky without splats (T30c)

History (M4-T31): T31 removed the sky's point-cloud file, `environment_fallback.tres` and the `fallback` command; the star file and
the panorama are written byte for byte as before.

```
tools/procgen/core/panorama.py        equirectangular helpers: pixel directions, Gaussians composited on the sphere, sRGB, the PNG and its .import
tools/procgen/assets/sky_default.py   the star file (sky_default_stars.f32) and the nebula panorama; the PLY stays until T31
src/environment/star_point_math.gd    StarPointMath: a star's footprint and dimming, the running lights' rule with the radius an angle
src/environment/star_field.gd         StarField: one MultiMeshInstance3D, one instance per star, under SpaceEnvironment
src/environment/sky_manifest.gd       SkyManifest: the star file's name, count, layout, disc radius and floor, and the panorama's name
src/environment/sky_follower.gd       SkyFollower: keeps the star field on the camera (no centroid offset any more)
src/environment/space_environment.gd  the panorama on the environment's sky; the `sky` command and provider
assets/shaders/star_point.gdshader    a star as a camera-facing point with a 1 px floor
```

- **What it is for.** Q29: the sky was the last splat node in the scene (12 000 star splats and 4 000 nebula splats). The stars are now
  points, crisp at any resolution, and the nebula is a picture on the environment's sky, so the sky costs one draw call plus the sky pass.
- **The star file.** `sky_default_stars.f32` holds one record of seven little-endian float32 per star: the unit direction in the Godot
  frame, the colour tint (largest channel 1) and the brightness. The manifest's `star_field` names the file, the count, the layout, the
  disc's angular radius (`radius_mrad`, 0.5) and the floor (`floor_px`, 1). The stars are the splat sky's own, drawn from the same seed.
  GDGS decodes a splat's colour from sRGB before it composites (`gaussian_composite.glsl`), so the tint and the brightness come from
  the decoded colour `c = srgb_to_linear(rgb)`: the tint is `c / max(c)` and the brightness is chosen so a point delivers the light its
  splat did at the reference height (1 080 lines at 70 degrees, GDGS's 0.3 px² dilation included):
  `L * pi/3 * rho^2 = max(c) * 2 pi (sigma^2 + 0.3 / f^2)`. Measured on the GPU (a bare scene, linear tone map, 2 621 stars in view)
  the points deliver 0.85 of the splats' light; the rest is GDGS's halo beyond the model.
- **Drawing a star.** Each instance's basis Z is its star's direction and its origin is the node's, so the shader reads only rotations
  (`mat3(MODELVIEW_MATRIX) * Z`): the camera turns inside a fixed sky and no camera offset can shift a star. (`NODE_POSITION_WORLD` and
  `MODEL_MATRIX` include the instance transform in a multimesh, so a position-based direction comes out zero.) The point is placed just
  in front of the far plane (reversed depth 1e-9), unshaded and additive, depth-tested so a hull hides it, writing no depth so the lens
  flare (open where the depth is still 0) and the motion blur still read the pixel as sky. Its footprint is the disc's, never under the
  floor; under the floor it is dimmed by (disc / floor)^2, so its light is the same at every render height (`StarPointMath`, the running
  lights' rule of Q26). It is drawn as a soft round point, a Gaussian 0.7 of its footprint wide cut at three widths (2.1 px for a
  floor-sized star), so its summed light holds within 2 % and its brightest pixel varies under 2x as it crosses pixel centres and
  corners (a 2 by 2 px square's varied 4x, and shimmered). The nebula dims the stars behind it (Q42): the vertex shader samples the
  panorama's alpha in the star's direction (`StarPointMath.panorama_uv`, mip 3) and multiplies the star's light by one minus it. The node carries a `custom_aabb` round the camera so it is never culled, and its material draws first among the
  transparent surfaces.
- **The panorama.** The nebula's Gaussians are composited far to near at half size (2 048 by 1 024, each projected to its angular
  covariance on the tangent plane) and enlarged to 4 096 by 2 048, in Godot's `PanoramaSkyMaterial` convention (the centre looks
  toward +Z, +u turns toward -X; checked on a GPU by rolling the image half a turn). Its RGB is the gas as GDGS showed it: the raw
  colours composited, then decoded from sRGB per texel (`decode(C / a) * a`), with no gain and no tone curve. Its alpha is the gas's
  opacity over the stars: 0.8 (`NEBULA_STAR_OPACITY`) times the gas's brightness over its 99.9th percentile, so the densest-looking gas
  passes a fifth of a star's light and only the brighter stars shine through. Both are dithered by one level (seeded, empty sky left
  black) so the dark gradients do not band. The stars are not painted into it. It is written by `core/image.py` (no Pillow) with a
  `.import` sidecar: VRAM compressed as BPTC with mipmaps, 11.2 MB.
- **Godot.** `SpaceEnvironment` reads the manifest, loads the star file into `StarField` and puts the panorama on the default environment
  (`background_mode` sky, a `PanoramaSkyMaterial`, radiance 32 px). Reflections from the sky are off, so the hulls keep the look they were
  approved with on the black sky; the ambient is still `settings.ambient_level`. Without the generated asset it warns and the sky stays
  black with no stars. `use_fallback_sky` keeps its group and flag for `SplatStatus`, but the sky is the same either way; T31 removes it
  with `environment_fallback.tres`. `sky <stars|nebula> [on|off]` hides a part for measures (a hidden nebula dims no stars; with no panorama, `sky nebula` answers
  "missing"); the `sky` provider says what is loaded.
- **Tests**: `test_panorama.py` (directions, compositing, the seam, resize, the dither, the PNG and sidecar), `test_sky_default.py` (the
  star file's layout and records, the same stars as the splats, each star's decoded colour and light against an independent decode,
  blue and orange stars kept, a lone gas splat shown as GDGS shows it, the panorama's size, its alpha rising with the gas, its light
  centred within 10 degrees of the splat sky's centroid, no star pixels in it, no Pillow), `test_star_point_math` (the floor, the dimming,
  equal light at 1 080 and 2 160 lines, the soft point's light and flicker across pixel offsets, the panorama mapping, parity with
  `RunningLightDimming` and the shader's constants), `test_sky_manifest`, `test_environment` (one instance per star, the material, the
  nebula's occlusion wired and switched, no splat node, the panorama, no generated asset, the follower, the command), `test_post_effects`
  (the flare's open-sky rule against the star shader's depth modes). That a hull hides a star, and that the flare and blur see open sky
  through the stars, is (H): no pixel test runs headless.

### 17.20 Removing Gaussian splats (T31)

History (M4-T31, Q29, Q30): the last splat code went. Every hull, chunk, buoy, capital and the station is the textured mesh of
§7 and §9, and the sky is §17.19's.

```
removed  addons/gdgs_scs/ (the fork, its LICENSE and PATCHES.md; the plugin line and the [gdgs] section of project.godot)
         src/rendering/{splat_budget_math,splat_lighting_loader,splat_pose_sync,paint_mesh_lights,paint_meshes}.gd
         src/ship/{splat_lod,hull_depth_proxy}.gd, assets/shaders/{hull_depth_proxy,paint_mesh,paint_mesh_glass}.gdshader*
         assets/environment/environment_fallback.tres, scripts/sync_gdgs_fork.sh, the F4 action debug_toggle_fallback_mesh
         tools/procgen/core/{ply,lighting,frames,paint_mesh}.py; the splat halves of sampling.py, chunks.py and pieces.py
renamed  splat_status.gd -> render_status.gd (RenderStatus); splat_light_rig.gd -> light_rig.gd (LightRig)
added    tools/procgen/core/rotations.py (the sky's quaternions); MeshAssets.read_manifest
```

- **One hull node.** `ship.tscn` has one `Hull` `MeshInstance3D`: the asset's shared textured mesh, or, while the cockpit interior is
  shown, the hull's OBJ with its canopy glass and window frames cleared (the cockpit view the maintainer approved). `NavBuoy` has one
  `Body`, a `DebrisChunk` one mesh node. A lean AI ship has 11 nodes of its own besides its guns (was 16).
- **`LodSwitcher`** keeps only the far dot; `LodSwitcherMath` keeps `far_dot`. `RenderPiece` draws its piece's textured mesh.
- **Console.** `lod`, `fallback` and `relight` and the `lod` provider are gone. `render` is `RenderStatus`: `renderer`
  (`forward_plus`, or `headless`), `fps`, `frame_ms`, `draw_calls`, `triangles`, `vram_mb`, `far_dots`, `gpu`, `gpu_ms`. The `sheet`
  command lost its look argument.
- **Settings removed:** `splat_lod_bias`, `splat_relight`, `relight_ambient`, `relight_unlit_level`, `relight_light_gain`,
  `splat_hero`, `splat_budget`, `own_lights`, `top_lamp_energy` (the top lamp's glow is the lens's emissive texels now),
  `hull_splat_sync`, `hull_depth_proxy`, `ship_render`, `ship_mesh_beyond_m`. A saved settings file that still names one is read
  as before; the key is ignored.
- **Generators.** The manifest lost `lods`, `hero`, `paint_mesh`, `sampling` and `counts`; `files.fallback_mesh` is `files.obj`;
  `kind` defaults to `asset`; the top-level box bounds the hull mesh. Surface samples stay: they centre each hull, keep the markers
  clear of it, place the chunks (now on the full-detail samples, millimetres from where M3's coarser level put them) and feed the
  occlusion and normal bakes. The sample streams are named `surface` (by sampling noise the hull centroids move 1.5 to 4 mm and
  the chunk centres up to 27 mm, each a pure translation).
  `--spacing` left the CLI (`--option spacing=...` still works). The sky's star file and panorama are byte-identical to T30c's.
- **What stays history:** the milestone files, the Cycle log, the handoff docs, `docs/research-notes.md` under its "Gaussian splats
  (historical)" heading, and the History lines of §17.10, §17.17 to §17.20 here.

### 17.21 The frame's per-ship work in one pass per subsystem (T36)

As built (M4-T36, Q56, refactor findings 2, 3, 7, 9, 12 and 13). The frame's own work (`_process` and the canvas, the engine's
`TIME_PROCESS`) grew with the ship count while the tick's budget never looked at it: at `battle` 500 its worst second was 25.7 ms
(in-callback timers: the HUD 11 ms, the LOD switchers 0.84, the far dots 0.80, the plumes 0.70, the engine sounds 0.64, the muzzle
flashes 0.45, the hit flashes 0.15). Each subsystem is now one pass over its ships a frame:

- **`FramePasses`** (`src/rendering/frame_passes.gd`): one node for the game, the autoload `FramePassesNode`, run before the
  default priority, so tests and scenes without `Main` animate from their first frame and the light rig still picks from this
  frame's levels. It walks four lists: the plumes of ships in play and shown (`ThrusterVisuals.frame_update`; an instanced ship leaves the list while
  hidden, and once every level is within `SETTLE_LEVEL` of its target the levels are set to the targets and the plumes are left
  alone until the flight output changes), the muzzle flashes that are showing (`trigger` adds one, it leaves when idle), the hit
  flashes that are showing, and every `LodSwitcher` with the camera and `far_ship_dot_m` read once (`decide`). A node takes part
  only while `can_process()`, as its own `_process` did. No node of a lean ship processes each frame (`test_frame_passes`).
  Console provider `frame` (`plumes_us`, `flashes_us`, `impacts_us`, `lod_us` and the lists' sizes).
- **Hit flashes** (`ImpactFlash`): one `MeshInstance3D` per hit, the flash quad (the 6 to 10 mesh sparks are gone; the `FxPool` hit
  burst is the spark effect). When over it leaves the ship for a pool kept under `FramePasses` (up to 256), from which
  `ImpactFlash.create` hands it out again, so a hit builds no node once the pool has filled.
- **Far dots** (`FarDots`): a ship's paint and hull radius are read when it turns into a dot and the identity rotations once per
  slot; a frame writes each dot's place, paint and size; `add` and `remove` queue one refresh at the frame's end, so ships turning
  together cost one and a ship that turns is drawn as a dot the same frame.
- **Engine sounds** stay as they were (two players on every watched ship, `_update_engines` walking them all, 0.64 ms a frame at
  500): refactor finding 7 is M5-T19's engine voices (`EngineVoices`, a cap with the player's ship first and the nearest next),
  taken at M5's rebase onto M4; T37 checks the per-ship audio node count after it.
- **The HUD radar**: `Main` gathers the radar's contacts straight from the targetables (`RadarContacts`, the same set as
  `TargetingController.candidates()`, without a `TargetInfo` each or the range sort), `RadarModel.plot` places them on the sphere
  into packed arrays (`RadarPlot`) ordered by a native int64 sort key (bit for bit the old GDScript `RadarModel.dots`, removed in M6-T18, but for two
  ranges equal to a millimetre), and `HudPainter` draws every stalk in one `draw_multiline_colors` and every plain dot in one canvas multimesh (the
  cockpit octagon's dark backings in another); rim and selected dots are drawn one by one. `HudFrame.radar_dots` is built from
  the plot when read. The player's candidate list is built only when something cycles it (M4-T34's refresh on read).
- **The debug overlay** text is rebuilt every `Main.OVERLAY_INTERVAL_S` (0.1 s) while it shows.
- **`RenderScale` is gone**: the splat sorter's tile cap rendered a 6K window's 3D at 0.86; the 3D is now at the window's full
  resolution (a manual scale stays T26's).
- **Motion blur** (checked, unchanged): hulls write depth (`depth_draw_opaque`) and blur by the velocity buffer; the sky, the star
  points and the additive markers write none (`depth_draw_never`) and blur by the camera's turn. Nothing depended on the removed
  hull depth proxy; `motion_blur.glsl`'s header comment no longer names it (fix round 1, so T37's doc-drift item is done).

The worst second's process work at `battle` 500 fell from 25.7 to about 10.5 ms, at 300 from 20.2 to 11.3 ms (the M4 Cycle log, M4-T36).

### 17.22 Anti-aliasing and motion vectors (T38)

T38 adds the anti-aliasing setting and the motion vectors TAA needs (§7.6). For the performance side: SMAA is the default as a
look call the costs allow; with the 3D at the 6K window's own size it costs 0.37 ms of GPU over `off` at `battle` 300 (3.20 against
2.83 ms, frozen-scene turns) and about 160 MB, while TAA costs 2.7 ms and MSAA 4x 0.9 ms and 1.1 GB (the full tables, scaled and
native, are in the M4 Cycle log). Under TAA the bolt slot check walks every bolt slot once a frame in
GDScript (measured 0.8 ms a frame at `battle` 500's 2 300 bolts, against 0.09 ms for the bolt pass without it); T37 or a later
native task can move it into the core's `bolt_transforms`, which knows when a slot changes hands. Under TAA the frame also costs
about 1 ms more CPU elsewhere (Godot's own motion-vector bookkeeping). FSR 2.2 (T40) reuses the same motion vectors.

### 17.23 Upscaling (T40)

T40 adds the upscaler and preset settings (§7.7). For the performance side: on this GPU upscaling buys little because the GPU is
not what binds. The frame is CPU-bound at `battle` 300 and 500 at the 6K window's native size (GPU 4.7 ms against a 9.8 and 24 ms
frame), and only `typical` (a 4 ms frame) is close to GPU-bound. FSR 2.2 costs more than native at every preset (its pass at 6K is
about 4 ms of GPU and its motion vectors add 2 to 3 ms to the frame), so it is offered for its anti-aliasing and for heavier future
scenes, not as a saving. FSR 1.0 and bilinear save 1.4 to 3.8 ms of GPU at 6K. The default stays native; a weaker GPU or a heavier
scene would change that, and the setting is ready for it.
## 18. Mission framework and front end (M5)

What M5 adds to §1-§17 (tasks in `docs/milestones/m5-mission-framework-and-front-end.md`). M4's §17 joined `m5` in two merges
of `main` (2026-11-07, M4 through T22; 2026-11-08, the rest, after M4 was accepted); its language split and threading rules
(§17.13, `CLAUDE.md`) bind M5's per-tick work too. Every earlier rule still holds; task ids below are M5 tasks. Decision
numbers start at D50 (D46-D49 are M4's).

The subsections were written task by task, so here is where each part of M5 is described and what a later task replaced:

| Part | Read | Replaced or changed by |
|---|---|---|
| Boot, `Game`, loading | D50, §18.3 | - |
| Menu kit, front end, pause menu | D57, §18.6 | the root lists and the settings entry points: §18.28 (T45); the view behind the pause menu: §18.27 (T42) |
| Settings and controls menus, audio buses | §18.31 | their grouping: §18.28 |
| Missions, triggers, objectives | D51, D52, §18.5 | - |
| Dialog and the comms panel | D53 | - |
| Comms menu | §18.22 | D54's D-pad picking, plate and timer are gone |
| Cinematics and locked controls | D55, §18.8 | - |
| Debrief | D56, §18.7 | - |
| The demo mission | §18.15 (Civilian escort) | §18.9 (Buoy defence) is removed from the game |
| Civilian ships, turrets, colours, surfaces | §18.10, §18.11, §18.14, §18.30 | the turret's first strength in §18.10: §18.11 |
| Encounters | §18.12 | - |
| Asteroids, belts, rock rams | §18.13, §18.16 | - |
| Target menu, preview, focus pull | §18.19, §18.20, §18.21 | - |
| Sound pass | §18.32, §18.26 | - |
| Performance block (L1 to L13) | §18.17, §18.18, §18.23, §18.24, §18.25, §18.29 | - |
| Tests and CI (L14) | §12 ("Shared test steps"), §18.33 | - |

### 18.1 Decisions

| # | Decision | Rationale (short) |
|---|---|---|
| D50 | Boot and the `Game` flow (T01). The main scene is `src/frontend/boot.tscn`; `Boot` hands the command line to the `Game` autoload once, and the pure `GameFlow.boot_route` decides: a windowed launch shows the front end; `--headless` (the display server or the engine argument), `--console-exec` or `--console-file` with a script, `--scenario=<id>` (after `--`, or before it) and `settings.skip_front_end` go straight to Main, which reads `Settings.scenario` as before (`--scenario=<id>` sets it for the session, like the `scenario` command). `GameFlow` (`RefCounted`) holds the states `FRONT_END`, `LOADING`, `IN_SPACE`, `DEBRIEF`, the request `{kind: free_flight \| mission \| sandbox, scenario_id, encounters, seed}` and the last result; a run starts at `FRONT_END`, and a refused move changes nothing and says why. `Game` only swaps scenes: the loading screen loads `main.tscn` with `ResourceLoader.load_threaded_request` (its scripts compiled first on the main thread, §18.3), `Game` builds Main with the request's `scenario_path` and `scenario_seed`, and `Main._ready` fills the pools behind the loading screen (D22 unchanged). Leaving a scene unpauses the tree and frees the mouse. The console's `scenario <id>` still reloads Main in place | Every tool, benchmark, smoke run and test starts as it did, and the menus get a flow that the debrief, retry and missions plug into without touching Main |
| D51 | Missions are scenarios with a script of named steps (T05). `ScenarioLoader` passes a scenario's `mission` block through (`title`, `briefing`, `script`, `dialog`, `objectives[]`; strings type-checked only, objectives by `ObjectiveBook.declare`) and `cinematics` beside it; `Main` creates a `MissionRunner` (under Main, physics priority 400, pausable) when the block is there. The script extends `MissionScript` (`steps()`, `step_<name>(m)`); `MissionSequencer` awaits each step as a coroutine, and every wait in `MissionApi` resumes on the sequencer's `wake`, emitted once per tick after the world moved, so mission time is sim time. `mission skip` marks the step skipped and emits `wake` at once: waits return, an awaited trigger is first made true (`Trigger.make_true`), the objectives are evaluated right after, and the step runs to its end and the next starts inside the command (an emission calls only the waits it began with); `mission goto <step>` skips every step before the named one. World changes go through `MissionStage`: pools, `AiContext.objective_name` for `send`, the jump points. `cinematic` and `lock_controls` are D55's (T08); `say` is D53's (T06). Success: every primary done, or `m.end(true)`; failure: a primary failed, `m.end(false)`, or the player destroyed. The result goes to `Game.end_mission` (`last_result`, `DEBRIEF`); Main stays in space with `MISSION COMPLETE` or `MISSION FAILED - <REASON>` on the status line until T09's debrief. In a mission the player does not respawn (the runner cancels it, Back is ignored); a spawn past its pool is a `push_error`, never a new ship. Jump arrivals (Q12): **as built, M6-T19 replaced M5's `JumpArrivalPool` and `JumpArrival` flash with `JumpPointPool` (§19.10)**: it holds 4 stand-alone `JumpVortex` points (the gate's vortex, sized for the ship, the `jump_in` sound and a light), a spawn with `arrival: "jump"` opens one (a group within 600 m in the same second shares it) and comes out of it on its own velocity; `arrival: "gate"` comes through the jumpgate | Scripts read like the mission; skipping by forcing leaves the world where the step would have (a skipped wave is gone, not alive and ignored), which M8's tutorial checks need; one script surface keeps missions out of Main |
| D52 | Triggers and objectives (T05). Seven kinds (`proximity`, `area`, `timer`, `destroyed`, `dialog_finished`, `input_performed`, `arrived`), each a `RefCounted` with its `test` and `force` side by side, over a `MissionWorld` snapshot: actors by name (case-free; `player` is the player) with `UniversePos`, alive and route end, sim time, finished lines, and this tick's `PlayerActions` from the `PilotCommand` Main sampled (`InputAdapter.last`; held controls past half way and edges). Forced, `destroyed` releases its ships to the pool (no explosion, no credit), `proximity`, `area` and `arrived` place the actor (`reset_to`, velocity kept; beside a goal actor at half the radius), the rest latch. `TriggerSpec.from_dict` builds them from JSON and has builders for scripts. `ObjectiveBook` (pure): hidden, active, done, failed (final); success and fail triggers evaluated while active, fail first; `snapshot()` is `{id, text, primary, state}`. Cost: every lookup is one unit of `MissionWorld.work`, and the stage refreshes only the names the live triggers read, from a name map `ShipPool.acquired` keeps current, so a tick costs a check and at most two lookups per trigger plus one refresh per name, whatever the number of ships | Pure predicates are unit-tested without a scene; a counted bound is stable on any machine where a millisecond budget is not |
| D53 | Dialog, subtitles and the comms panel (T06). Lines are data: `data/dialog/<file>.json` `{lines: [{id, speaker, text, voice, hold_s?}]}` and `data/dialog/speakers.json` `{id, name, callsign, faction}`; `DialogBook` loads and validates them (a bad file stops the mission from starting), a line's hold is `hold_s` or about 2.5 words a second, at least 2 s. `DialogQueue` (pure, sim-time deltas) plays one line at a time with a 0.4 s gap, and a `say` with `interrupt` cuts the line showing. `MissionApi.say` queues the line and resolves when it has finished showing; skipped, it is logged and recorded finished. `CommsPanel` (a `CanvasLayer`, layer 41, above the HUD and below the pause menu) draws the callsign in the faction's colour over the subtitle at the bottom of the window in both views, and plays the `sfx_ui` `radio_open` / `radio_close` squelches (a cut line makes no close); the cockpit's right screen keeps the wing roster. A test checks every line id a mission script uses exists in its dialog file and every speaker exists | Lines as data keep M15's voices from touching any script; the panel sits on its own layer so a cinematic that hides the HUD keeps its subtitles |
| D54 | The comms menu on D-pad Right (T07; the D-pad picking, the plate view and the timer are superseded by §18.22, T46). New action `comms_menu`: D-pad Right and Ctrl (the left hand's last free key; keys 1-4 stay the wing orders, 5 the lights). `CommsMenu` (pure, `src/hud/comms_menu.gd`) holds pages of up to four `{label, payload}` entries, one per D-pad direction (up, right, down, left), a 4 s close timer on sim time, and `push_page` / `pop_page` so a later mission can push a page of replies (M5 builds none). Page one is the wing orders, payload an `AiContext.Order`, in the order of keys 1-4. `Main` owns the model and a `CommsMenuView` (`CanvasLayer` 42, a plate at the left edge, vertically centred: free of the roster and acknowledgements top-left and top-right, the gauges at the bottom and the subtitles at bottom centre), opens it on `UiCommand.comms_open`, and calls `WingDirector.give_order` for a pick, the call keys 1-4 make. A pick closes the menu. `Main` tells `InputAdapter.comms_open`; while set, the adapter turns the D-pad's four actions into `UiCommand.comms_pick` 0-3 and either B button into `comms_close`, and reports no assist, next-weapon, lights or target-cycle edge (a B press held through the close taps nothing when released). The timer is stepped with the physics tick, so it stops behind the pause menu; the pause edge and the player's death close the menu. A profile saved before M5 gets `comms_menu` from `default` when it loads (D36's fill); `m1_classic` keeps its D-pad rolls and has Ctrl alone (`ControlProfile.KEYBOARD_ONLY`) | The pad gets the wing orders without a new button, and one adapter rule keeps every D-pad action quiet while the menu is up |
| D55 | The `CINEMATIC` camera and locked controls (T08). A shot is data in the scenario's `cinematics: {<shot_id>: {keys: [{t, position, look_at, fov?}]}}`; a point is `{actor, offset?}` (metres in that actor's frame, -z its nose) or `{origin: [x, y, z]}` (a universe offset from the scenario origin, 64-bit); `fov` defaults to 70°. `CinematicShot` (pure) reads and checks a shot and gives the pose at a time from the actors' poses handed in each frame: Catmull-Rom on positions with the key times (Godot's `cubic_interpolate_in_time`, mirrored at the ends), the look-at point and the field of view eased key to key (smoothstep), up the world's +y. It keeps nothing between calls, and `CameraRig`'s `CinematicCamera` is `top_level` in `world_shiftable` with interpolation off, so a rebase mid-shot moves nothing on screen. The rig's `play_shot` switches to `CINEMATIC` (only a shot does; `camera_default` keeps chase and cockpit), clocks the shot on physics ticks and goes back to the mode it left when the shot ends or `stop_shot` cuts it; a mode asked for during a shot is the one it goes back to. Main hides the HUD (`Hud.cinematic`) and slides in the `Letterbox` (layer 39, under the comms panel) while the camera is cinematic. `ControlLock` (pure) zeroes the player's `FlightCommand` and `CombatCommand` during a shot or while `MissionApi.controls_locked` is set (the ship drifts on; assist stays as set), holds the wing orders (keys 1-4, the comms menu's opening and picks; Main closes the menu), and during a shot reads Start or a fresh A press as a skip; the A that skipped does not fire until released. `m.cinematic` plays the shot through `MissionStage` and resolves at its end, on a player skip or a `mission skip` (which cuts it), or when the mission ends; a bad shot stops the mission from starting | Shots as data relative to actors read like direction and survive ships moving; a stateless pose is rebase-proof without bookkeeping; zeroing commands, not physics, keeps the world honest during a shot |
| D56 | The debrief (T09). When a mission ends, `MissionRunner` asks `DebriefRecorder` for the result with the player's counters (`MissionApi.result` plus `kills` and `assists` from `WaveDirector.credit`, the `KillCredit` of §15.10, and `shots_fired`, `shots_hit` and `wing_losses` from the pure `MissionTally`) and gives it to `Game.end_mission`, which moves the flow to `DEBRIEF` only for a run the flow started as a `mission` (anything else keeps the result and shows nothing). After a short beat the runner calls `Game.show_debrief`, which `GameFlow.debrief_problem` guards (state `DEBRIEF`, a mission request, a result: a debrief with no mission never opens) and which replaces Main with `src/frontend/debrief_screen.tscn`: the sky and a `MenuFrame` (D57) whose `DebriefPage` offers **Retry** (`Game.retry`: the same scenario, encounters and seed through the loading screen) and **Front end** (`Game.show_front_end`), with the whole debrief on the right. `DebriefModel` (pure) turns the result into that panel and into the console's `debrief` provider | The result carries everything, so the debrief needs nothing from the Main it replaces; the menu kit and the one flow serve retry and the way out without a new path |
| D57 | The front end, the pause menu and the three-panel frame (T02). `MenuFrame` (`menu_frame.tscn`) is the one layout of Q15: the options top left (a scroll container), the controller diagram with what each button does bottom left, the objectives right. It holds a stack of `MenuScreen` pages (the D-pad and left stick walk Godot's `ui_*` focus, A accepts, B goes back; arrow keys, Enter, Esc and the mouse work too) and reads three providers: `bindings_source` (a `ControlProfile`; unset, the InputMap as it is now, so a rebind shows at once), `objectives_source` (`Array[Dictionary]`, the `ObjectiveBook.snapshot()` shape) and `request_source` (`Game`'s request). `PadLegend` (pure) maps each pad descriptor of the profile to a part of the pad and the menu's word for the action; `PadDiagram` draws the pad in code, no image. The right panel shows the page's own content (a mission's briefing), else the objectives, else the run (`Free flight`, `Encounters: on|off`), else nothing (`ObjectivesModel`, pure). The front end is the sky (the camera sways about the nebula view) behind a frame whose root page is Missions, Free flight, Sandbox, Settings, Controls and Quit; the pause menu (`src/hud/pause_menu.tscn`, a `CanvasLayer` that always processes, created by `Main`) opens on the `pause` edge, pauses the tree and offers Resume, Restart, Settings, Controls and Quit to menu. Missions are the scenarios with a `mission` block (`MissionCatalog`, through `ScenarioLoader`); Settings and Controls were placeholders from `MenuScreens` until T03 and T04 returned their pages from there (§18.31). **Changed by T45 (§18.28):** the front end's root is New game, Load game, Free flight, Settings, Quit with no pad diagram or right panel, the pause menu is Resume, Restart, Settings, Quit to menu, and Controls is a group inside Settings | One layout for the pause menu, settings and controls screens, and providers so the mission core and the controls screen plug in without touching the frame |

### 18.2 Layout additions

```
src/game/game_flow.gd                    RefCounted, pure: states, moves, the request, the boot rule (T01)
src/autoload/game.gd                     autoload `Game` after ControlProfiles: scene changes, `menu`, `play`, provider `game` (T01)
src/frontend/boot.tscn|.gd               the project's main scene: hands the command line to Game (T01)
src/frontend/loading_screen.tscn|.gd     shown while main.tscn loads on a thread (T01)
src/frontend/front_end.tscn|.gd          the sky with a slow drift and the main menu in a MenuFrame (T01 placeholder, T02)
src/frontend/menu_frame.tscn|.gd, menu_screen.gd, theme.tres   the three-panel frame, the base page, the one Theme (T02)
src/frontend/choice_list_screen.gd, free_flight_select.gd, placeholder_screen.gd, menu_screens.gd   the pages (T02)
src/frontend/new_game_select.gd, settings_groups_screen.gd   missions then sandbox scenes; the five settings groups (T45; they
                                 replaced T02's mission_select.gd and sandbox_select.gd)
src/frontend/settings_screen.tscn|.gd, settings_menu_model.gd   a settings page built from the schema; its pure model (T03)
src/frontend/controls_screen.tscn|.gd, controls_model.gd, binding_capture.gd   profiles and rebinding; the pure model and capture (T04)
src/audio/audio_buses.gd, default_bus_layout.tres   Master, SFX, UI, Comms and their volumes (T03)
tests/unit/test_settings_schema.gd, test_settings_menu_model.gd, test_settings_groups.gd, test_controls_model.gd,
  tests/integration/test_settings_screen.gd, test_controls_screen.gd   (T03, T04, T45)
src/frontend/pad_legend.gd, pad_diagram.gd, objectives_model.gd, objectives_panel.gd, mission_catalog.gd   legend, diagram, right panel, mission list (T02)
src/hud/pause_menu.tscn|.gd              the pause menu, created by Main (T02)
tools/procgen/assets/sfx_ui.py           `ui_move`, `ui_accept`, `ui_back` (T02)
tests/unit/test_pad_legend.gd, test_pad_diagram.gd, test_objectives_model.gd, test_mission_catalog.gd, tests/integration/test_front_end.gd, test_pause_menu.gd, test_menu_frame.gd, test_loading_screen.gd   (T02)
tests/unit/test_game_flow.gd, tests/integration/test_boot_routing.gd   (T01)
src/mission/mission_script.gd, mission_sequencer.gd, mission_api.gd   the script's base, step and skip sequencing, the script surface (T05)
src/mission/mission_runner.gd, mission_stage.gd, mission_console.gd   the node under Main, its game side, provider and command `mission` (T05)
src/mission/mission_world.gd, trigger.gd, trigger_*.gd, trigger_spec.gd, player_actions.gd, objective_book.gd   pure (T05)
src/mission/jump_arrival.gd, jump_arrival_pool.gd   the jump point opening (Q12) and its fixed pool (T05)
tools/procgen/assets/sfx_world.py        `jump_in` (T05)
src/mission/debrief_model.gd, mission_tally.gd   the debrief's content and the player's shot, hit and wing-loss counters, pure (T09)
src/mission/debrief_recorder.gd   feeds the tally from the game's signals and adds the counters to a mission's result (T09)
src/frontend/debrief_screen.tscn|.gd, debrief_page.gd   the debrief shown by `Game.show_debrief` (T09)
tests/unit/test_debrief_model.gd, test_mission_tally.gd, tests/integration/test_debrief.gd, tests/fixtures/recording_main.tscn|.gd   (T09)
tests/fixtures/missions/test_mission.json|.gd   the test mission (T05)
src/camera/cinematic_shot.gd   a camera shot from the scenario's `cinematics`, pure (T08)
src/input/control_lock.gd   zeroes the player's commands during a shot or a lock, reads the skip, pure (T08)
src/hud/letterbox.gd   the cinematic's black bars (T08)
tests/unit/test_cinematic_shot.gd, test_control_lock.gd, test_mission_cinematic.gd, tests/integration/test_cinematic_camera.gd, tests/fixtures/missions/test_cinematic.json|.gd   (T08)
tests/unit/test_triggers.gd, test_objective_book.gd, test_mission_sequencer.gd, tests/integration/test_mission_runner.gd, test_mission_skip.gd   (T05)
src/mission/dialog_book.gd, dialog_queue.gd, src/hud/comms_panel.gd, comms_layout.gd, data/dialog/speakers.json   lines as
                                 data, the one-line queue (pure), the subtitle panel (T06)
tests/unit/test_dialog_book.gd, test_dialog_queue.gd, test_dialog_ids.gd, test_comms_layout.gd, tests/integration/test_comms_panel.gd   (T06)
data/scenarios/civilian_escort.json, data/missions/civilian_escort.gd, data/dialog/civilian_escort.json   the Civilian escort
                                 mission (T30; it replaced T10's Buoy defence, whose files and the buoy ring are gone)
tests/integration/test_civilian_escort.gd   (T30)
tools/procgen/assets/asteroids.py, tools/procgen/tests/test_asteroids.py   the rock shapes and their spheres (T29)
src/world/belt_layout.gd   a belt's rocks in its box, pure (T29)
src/world/asteroid_belt.gd   a multimesh per shape, static spheres in StaticRows (T29)
tests/unit/test_belt_layout.gd, tests/integration/test_asteroid_belt.gd, data/scenarios/belt_showcase.json   (T29)
src/hud/feature_edges.gd, feature_edge_job.gd, wire_framing.gd, target_preview_layout.gd, src/targeting/target_preview_model.gd   pure (T43)
src/hud/wire_preview.gd, target_preview.gd, assets/shaders/wire_solid|wire_lines|wire_outline.gdshader   the preview's viewport and panel (T43)
tests/unit/test_feature_edges.gd, test_wire_framing.gd, test_target_preview_model.gd, tests/integration/test_target_preview.gd   (T43)
src/hud/radial_menu.gd, radial_layout.gd, radial_menu_view.gd   the radial framework (T25)
src/targeting/target_menu.gd, target_categories.gd, target_menu_director.gd, src/hud/hud_waypoint.gd   the target menu (T25)
tests/unit/test_radial_menu.gd, test_target_menu.gd, test_target_categories.gd, tests/integration/test_target_menu.gd   (T25)
src/hud/focus_pull.gd, focus_pull_view.gd, assets/shaders/focus_pull.gdshader, tests/unit/test_focus_pull.gd   (T44)
src/hud/comms_menu.gd, comms_menu_director.gd, tests/unit/test_comms_menu.gd, tests/integration/test_comms_menu_input.gd   (T07, T46)
src/camera/pause_orbit_path.gd, tests/unit/test_pause_orbit_path.gd   the pause backdrop's path, pure (T42)
src/audio/engine_voices.gd, tests/unit/test_engine_voices.gd, test_voice_query.gd, tests/integration/test_engine_audio.gd   (T19, T28)
tests/fixtures/test_steps.gd   the scene tests' shared steps (T38, §12)
```

The turrets', civilians', encounters' and native files are listed in their own subsections (§18.10 to §18.12, §18.23 to
§18.26, §18.29, §18.30).

### 18.3 Boot, scene changes and the console's startup scripts

- `Boot._ready` runs while the root is still readying its children, so `Game` changes the scene with a deferred call. On the
  straight route that call adds Main in the first message flush, before the first process frame ends; `DebugConsole` waits a
  process frame and then a physics frame (§6.4), so its startup scripts still run after `Main._ready` and after the calls
  Main deferred from it. A script's first statement finds Main's providers without a `wait` (smoke run in
  `scripts/run_tests.sh`).
- `Game` replaces the current scene itself (remove, `queue_free`, add, `current_scene`), rather than through
  `change_scene_to_*`, which adds the new scene only at the end of the frame, after the console has started waiting. Tests
  point `Game.scene_parent` at a node of their own and `Game.main_scene_path` at a light stand-in.
- Loading: `Game.play(request)` checks the request and that `data/scenarios/<id>.json` exists, moves to `LOADING` and shows
  the loading screen. After two drawn frames the screen compiles `main.tscn`'s own scripts on the main thread (holding
  them), then requests the scene on a worker thread, polls it, and hands the `PackedScene` to `Game.finish_loading`, which
  builds Main and moves to `IN_SPACE`. A failed load goes back to the front end with an error. Why the scripts first: in
  Godot 4.7.2, when Main's scripts compile on the worker thread, the preloads they resolve there leave 8 to 10 engine
  objects behind ("ObjectDB instances leaked at exit"); compiled on the main thread first, nothing leaks. The smoke run
  that starts at the front end rejects the warning.
- The `scenario` command reloads Main without telling `Game`, so `game.request` keeps naming the scenario that was started
  (from the menu, `play` or boot).
- `play` does not change `Settings.scenario`: the `scenario` command with no argument still names the scenario the setting holds, not the one `play` started.
- `scenario x; menu` on one console line races the engine's deferred reload of Main: put a `wait` between them.
- `user://autoexec.cfg` runs at the first scene the console sees: the front end on a normal launch, Main on a scripted run.

### 18.4 Console and settings (additions to §6.4)

| Provider | Owner (task) | Keys |
|---|---|---|
| `game` | Game (T01) | `state` (`front_end`, `loading`, `in_space`, `debrief`), `request` (`<scenario> (<kind>), encounters on\|off, seed <n>`, or `none`), `last_result` (`success`, `failure: <reason>`, or `none`) |
| `mission` | MissionRunner (T05), only while a mission runs | `id`, `title`, `state` (`running`, `success`, `failure`, `error`), `result`, `step` (`<name> (n/N)`), `steps`, `time_s`, `objectives`, `live_triggers`, `tick_work`, `skipping`, `waypoint`, `controls_locked`, `jump_points` |
| `debrief` | Game (T09) | `result` (`success`, `failure`), `reason`, `time` (`m:ss`), `kills`, `assists`, `wing_losses`, `shots_fired`, `shots_hit`, `accuracy` (`45%` or `no shots fired`), `objectives` (`id state, ...`); every key `none` until a mission ends |
| `camera` | CameraRig (M1; T08 adds) | `mode` now also reads `cinematic` while a shot plays (setting it then picks the view after the shot), `shot` (the shot's id or `none`), `shot_time_s` |
| `encounters` | EncounterDirector (T17), free flight only | `on`, `pools_built`, `seed`, `interval_s`, `max_ships`, `alive`, `raiders`, `patrol`, `traffic`, `next_index`, `next_in_s`, `waiting`, `started`, `released`, `last_event`, `check_work`, `build_ms` |
| `pause_menu` | PauseMenu (T02) | `open`, `page` (the title of the page on top: `PAUSED`, `Settings`, a group's name, `Controls`), `depth` (pages open, 1 is the pause list) |
| `dialog` | CommsPanel (T06), only while a mission runs | whether a line shows, its id, callsign and text, lines queued, time left, lines shown |
| `belts` | Main (T29) | `count`, `rocks`, `spheres`, `draw_groups` |
| `target_menu` | TargetMenuDirector (T25) | open, the ring and its entries, the highlight, the target and waypoint as the HUD names them, the last pick, `focus` (T44) |
| `comms_menu` | CommsMenuDirector (T46) | open, the page, the highlight, the ring's entries, orders picked, the last order, why it last closed |
| `audio` | AudioDirector (M2; M5 adds) | `engine_voices`, `engine_sounding`, `engine_frame_work`, `engine_rank_work` (T19, T28), `shots_culled` (T37) |
| `target_preview` | TargetPreview (T43) | `visible`, `entity`, `kind` (`none`, `ship`, `beacon`, `objective`, `unknown`), `hull` (the asset drawn, `+n pods`), `edges`, `building`, `rendering`, `lines`, `flag`, `cache`, `last_build_ms`, `last_build_slice_ms`, `last_build_frames`, `shows`, `frame_ms` |

Commands: `retry` (T09: in the debrief, play the same mission again, same scenario and seed, through the loading screen; refused anywhere else); `menu` (back to the front end); `play <scenario_id> [seed]` (any `data/scenarios/*.json`, through the loading screen
as the menu does; seed 0 by default, encounters off). Setting: `skip_front_end` (bool, false). Command line: `--scenario=<id>`
(goes straight to Main with that scenario for the session). T05: `mission [status|skip|goto <step>|objectives|journal]`, registered only while a mission runs (elsewhere `mission` is an unknown command); a bad action, `goto` without a step or with an unknown or past one, and a step given to anything but `goto` are refused. T43: `targetmenu highlight <entry>` points at an entry of the open ring without picking it. T25 and T46: `targetmenu` and `commsmenu` (`open|pick <entry>|highlight <entry>|back|close`); T42: `pausemenu [on|off]`; T17: `encounters` (§18.12).

`info.md` at the repository root is the full list of commands and providers, held to the game by
`tests/integration/test_console_command_list.gd`; the keys above are the ones a script is likely to read. M5's settings:
`skip_front_end`, `encounters`, `encounter_interval_s`, `encounter_max_ships` (§18.12), `master_volume`, `sfx_volume`,
`ui_volume`, `comms_volume`, `engine_voice_cap` (§18.31, §18.32), `target_hold_s`, `target_menu_blur` (§18.19, §18.21),
`pause_backdrop`, `pause_backdrop_loop_s` (§18.27), `hull_sheen`, `ambient_level` (§18.14) and `texture_detail` (§18.30).

### 18.5 Missions as built (T05)

- **Tick.** `MissionRunner` (400) runs after `WaveDirector` (300) and before the `RebaseSettler`: time, the player's actions, the
  snapshot for the watched names, the objectives (and the result rules), then `wake`, where the waiting step tests its trigger.
  The first step starts in a call deferred from the runner's `_ready`, so it runs before the first tick and before any console
  startup script. Paused, nothing ticks.
- **Lifetime.** A waiting step holds the API and the script, and the API holds the sequencer: `MissionSequencer.release`
  (the runner's `_exit_tree`) disconnects every wait, so the step is dropped and nothing is left at exit. After `end` a step that
  waits again never resumes, and world changes after `end` are ignored.
- **Journal.** `MissionApi.journal` lists every world change in order (`spawn RAIDER 1 raider_fighter`, `send ...`,
  `objective_add ...`, `objective raiders done`, `end success: ...`); `mission journal` prints its tail, and the skip test
  compares a skipped run's whole journal, objectives and ships in play with a played one's.
- **Not yet arrived is not destroyed.** `MissionWorld` remembers every name it has seen in play; `destroyed` counts a name only
  once it was seen and is gone, so an objective or an `until` may be live before its ships spawn (a new spawn is refreshed at
  once, so a ship lost before the next tick still counts). A name the stage knows (placed at load, or handed out by the pool to
  anyone) but finds gone is recorded as seen and gone, however long ago it died and whether or not a trigger watched it; a name
  the game never had stays "not arrived". Forcing a never-seen name releases nothing and latches. A name is the ship's
  identity: a `destroyed` that goes live between a ship's loss and a later spawn reusing its name holds at once.
- **Skips and polling.** Scripts wait with `until`, never poll: a skipped step's waits return at once, so after
  `MissionApi.SKIP_SPIN_LIMIT` (1 000) such returns in one skip the step is reported (`push_error`) and waits a tick at a time.
  `until_objective` on a hidden objective warns. A forced release takes the ship out of its wing slots first (not marked lost);
  a wing it led hands the lead on. A forced placement goes through `Ship.reset_to` (D51), which also refills the tank and
  starts the assist afresh; velocity and spin are put back.
- **HUD and menus.** `Hud.extra_input` (set by the runner) adds the active objectives (top right, right-aligned, on the window
  in both views: `HudSurface.OBJECTIVES`, only while there are any), the mission's waypoint when no route marks one, and the
  result line. `Main.objectives()` returns `ObjectiveBook.snapshot()` (empty outside a mission): the pause menu's
  `objectives_source`.
- **Spawns.** `m.spawn` takes a scenario spawn (`ScenarioLoader.parse_spawn`) plus `arrival` and `invulnerable`; `anchor` is the
  player's position at the call or the scenario origin. `ShipPool` is unchanged: the stage checks `free_count` first and pushes
  the error itself.
- **Game.** `GameFlow.kind_for` reads the scenario file: one with a `mission` block is a `mission` (so `play <id>` and boot ask
  for it). `Game.end_mission` moves the flow to `DEBRIEF`, or, for a Main the flow did not start (tests), keeps the result
  through `GameFlow.keep_result`. The console's `respawn` is refused in a mission, as Back is.
- **Wingmen's names.** A replacement from `WingDirector.replenish` flies under the lost wingman's callsign, so a `destroyed` on
  wing names is only safe as an objective's `fail` with `all` false (Civilian escort's `home`): it fails at the loss, before any
  replacement, and failure is final. A success trigger or an `until` on wing names could be satisfied, or undone, by a
  replacement. Civilian escort pools exactly its one wingman and runs no `WaveDirector` waves (which replenish), so no
  replacement comes.
- **Left for later.** `cinematic` and the control lock are T08's (§18.8); the debrief screen is T09's (§18.7).

### 18.6 Front end and pause menu as built (T02)

- **Input.** Menus are UI and use Godot's `ui_*` actions; gameplay still never reads them. Godot 4.7's defaults put the D-pad and the
  left stick on `ui_up/down/left/right` but only keys on `ui_accept` and `ui_cancel`, so `project.godot` adds pad A and B to those two.
  `ControlProfile` covers `InputAdapter.ACTIONS` only, so applying a profile leaves every `ui_*` action alone (test).
- **Esc and Start.** In flight Esc is both `ui_cancel` and the `pause` action, so one press would go back twice. The pause menu's pages
  ignore the key (`MenuScreen.cancel_ignores_keys`); `Main` hands the pause edge (Start, Esc) to `PauseMenu.on_pause_action`, which
  opens the menu, goes back a page, or at the list resumes. B on the pad is `ui_cancel`: the page asks the frame to go back, and at
  the list that closes the menu. In the front end Esc and B both go back.
- **Sounds.** `AudioDirector` loads `sfx_ui` (`ui_move` on a focus move, `ui_accept` on a press, `ui_back` on going back) and plays it
  with `play_ui`; its UI voices always process, so the sounds play behind the paused World. The front end carries an `AudioDirector`
  of its own. They play on the UI bus at `ui_volume` (T03, §18.31).
- **Objectives.** `Main` sets `pause_menu.objectives_source` to its `objectives()` (`ObjectiveBook.snapshot()`, empty outside a mission), so the right panel lists the running mission's objectives with a mark per state and `(optional)` on the secondary ones.
- **Behind the menu.** While the menu is open `Main._physics_process` calls `InputAdapter.sample_menu` instead of `sample`: only the pause edge is read, every other button is re-seeded from what is held and the mouse and wheel are drained, so Back, Y, D-pad left and X (and T03's D-pad sliders) move the menu and do nothing in the game, and nothing fires when the menu closes. Closing drops the menu's pages (no hidden button keeps the focus), and a page with no focus takes it back on the next D-pad or A press.
- **Resume.** `Main` re-seeds the adapter's edges when the menu closes (`InputAdapter.resync_edges`), so the button that closed it (B is also the target button) does not also tap a target when it is released.
- **Missions.** `MissionCatalog.entries(dir, read)` lists the scenario files whose loader result has a non-empty `mission` block (its
  `title`, else the id made readable, and `briefing`). Civilian escort is the one shipped mission; with none the page says "No missions yet".
- **Free flight.** `encounters` lives in `Game`'s request (the menu starts it from `Settings.encounters`; `play` and boot keep it
  off); T17 (§18.12) added the setting and a fresh session seed for each menu start. Restart is `Game.restart()`: the request that started the run, else the scenario setting.
- **Loading.** Leaving the loading screen mid-load collects the threaded request; a failed load is collected too. `Game` refuses a scene
  it cannot build instead of failing on a null.
- **Sky.** The front end's camera has the rig's far plane (50 km): the sky sphere is 20 km across and a default far plane clips the stars.
- **Pad diagram.** The legend lists each side's rows top to bottom by where the button sits, pushed apart where several are close
  (`PadDiagram.stack_rows`); the face buttons carry their letter and need no leader line. The controls page lights the buttons of the
  action in focus through `MenuFrame.highlight_actions`.

### 18.7 The debrief as built (T09)

- **The beat.** The mission ends, the HUD shows `MISSION COMPLETE` or `MISSION FAILED - <REASON>`, and `Game` is in `DEBRIEF` at once
  (`game.state`, `game.last_result`); the debrief screen follows `MissionRunner.DEBRIEF_DELAY_S` (3 s) later. The beat is sim time counted
  in the runner's `_physics_process`: a pause holds it, and quitting to the menu or restarting from the pause menu drops it with
  Main, so a late debrief never lands on top of another screen. Why not at once: a win would cut the last explosion and a death
  would cut the break-up of the ship before the player has seen either; why not longer: the player has nothing left to do in space.
  A scripted run (`--console-exec`, headless) gets the same beat and the same swap: a console script that carries on with
  Main's providers after the mission ends has to read them within the beat (3 s, 180 physics frames); `debrief.*` and
  `game.last_result` stay readable afterwards.
- **The counters.** `DebriefRecorder` (a node under the runner) counts the player's own bolts only: a shot is the player's cannon's
  `projectile_fired`; a hit is a `HitResolver.hit_resolved` with cause `bolt` whose `shooter_id` is the player's ship (rams, console
  damage and other ships' bolts do not count). A wing loss is a `DestructionDirector.ship_destroyed` of a ship in the player's wing
  slots (or of an AI leader of it), counted at the hit, before the wings drop the ship at their next tick. Kills and assists are the
  session's `KillCredit`, which M3 feeds from raiders (the pool's default type) only: a civilian or an ally destroyed earns none,
  and a ship released by `mission skip` earns none.
- **The page.** Retry is first and focused, Front end second; B does nothing, so the debrief is never skipped by accident. A is fire
  in flight, so presses in the first `DebriefScreen.INPUT_GUARD_S` (0.7 s) are ignored: a tap meant for the fight does not pick Retry. A
  refused retry says why under the options. The right panel (`DebriefPage.info`, so it stays when the focus is lost) lists the mission,
  the verdict (green or red) and why (a failed primary is named by its text, not its id), every objective with its mark and, for an
  optional one, `(optional)`; an objective still open at the end reads `not finished`, one that was never shown `not reached`; then the
  time (`m:ss`, sim time), kills and assists, wing losses, shots fired and hit with the accuracy. The panel sets its lines small
  (`compact: true` in the content, `ObjectivesPanel`), because a debrief is the longest thing the right panel shows.
- **Retry.** `Game.retry` is `GameFlow.retry` (the request, seed and encounters unchanged, state `LOADING`) and the loading screen,
  so Main is built again exactly as the first time; `last_result` stays readable. The console's `retry` does the same.
- **No debrief without a mission.** `Game.end_mission` moves to `DEBRIEF` only when the request is a mission; free flight, the sandbox
  and a Main the flow did not start (a test's) only keep the result; a Main the `scenario` command reloaded is judged by `game.request`, which
  that command leaves as it was. `show_debrief` refuses outside `DEBRIEF` or with an empty result, and a `DebriefScreen` opened with nothing to show
  reports it and goes back to the front end.
- **Objectives that only guard.** An optional objective with only a `fail` trigger (`protect` in the test mission) stays active when the
  mission ends well, so the debrief says `not finished`; a mission that wants it to read done completes it before `m.end`.

### 18.8 Cinematics and locked controls as built (T08)

- **The frame.** The rig's `_physics_process` advances the shot's clock; `_process` places the camera at the time between the last
  two ticks (`Engine.get_physics_interpolation_fraction()`) from the actors' interpolated poses
  (`get_global_transform_interpolated`), so the shot moves with what the renderer draws. `update_cinematic(fraction)` is public for
  tests. If a key's actor is gone (destroyed, released) on the segment playing, the camera holds where it is (it is shiftable, so a
  rebase still moves it with the world); a missing neighbour key only flattens the curve.
- **One lookup.** `MissionStage.actor_pose` and `origin_to_local` place the points: the same name map as the triggers (the player,
  the buoys, pooled ships by the name they fly under) and the scenario's system.
- **Skips.** The skip edge is read in `Main._physics_process` before anything else uses the command, so Start never reaches the
  pause menu during a shot. A held since before the shot is not a skip until it has been let go (a trigger finger from the fight
  does not throw the shot away). `mission skip` cuts the shot inside the command; the step goes on at once.
- **What stays.** The rest of the UI part of the command (overlay, screenshot, lights) passes during a lock; with no shot Start still
  opens the pause menu. The input-performed triggers read `InputAdapter.last`, which the lock zeroes, so a player action held
  during a lock does not count (M8's tutorial unlocks before it asks). The adapter's own latches (auto-track) are not reset.
- **Console.** `camera.shot`, `camera.shot_time_s`; `camera <mode>` during a shot picks the view after it. No new command: a shot is
  played by a mission script, and `mission skip` cuts it.

### 18.9 Buoy defence as built (T10)

*Superseded by §18.15 (T30, Q36, Q41): the mission, `BuoyRing`, the `buoy_rings` field and their tests are removed, and
`NavBuoy.BROADCAST_RANGE_M` is back at 1 000 km. Kept for the framework pieces it added: `player.velocity`, closing lines and the
fly-past shot.*

- **The ring (Q21).** A scenario may declare `buoy_rings: [{centre, radius_m, count, normal, first, prefix}]`; `ScenarioLoader`
  turns each into nav buoy props (after the hand-placed ones, names checked for duplicates) from `BuoyRing` (pure): the ring in the
  plane square to `normal`, the first buoy along `first` from the centre, the rest at equal angles, named `prefix` + ALPHA, BRAVO,
  ... (3 to 26 buoys), sums in 64 bits. Buoy defence has 16 on a ring of 20 000 km radius centred 20 000 km behind the scenario
  origin, so NAV ALPHA sits at the origin and its neighbours are 7 804 km away (7 854 km along the arc). No planet there (M6 put Epsilon III in the system, but this scenario's ring is gone, §18.15).
- **Broadcast range: 10 000 km (changes M3's Q21).** `NavBuoy.BROADCAST_RANGE_M` is 1.0e7 m for every buoy in the game (M3-T17 had
  1.0e6 m, 1 000 km). On the ring every point hears at least two buoys. Off it the rule holds in every direction to about 4 900 km
  (`test_buoy_ring.gd`); straight out of the plane and inward it holds to 6 000 km and more, but straight outward beside a buoy the
  second buoy drops out at 4 913 km, because both neighbours draw away. The maintainer's "within about 6 000 km" is therefore true
  except on the ring's outer side near a buoy (about 10 750 km of range, or more buoys, would close that). From NAV ALPHA the radar
  shows NAV BRAVO and NAV PAPA on its rim; NAV CHARLIE and NAV OSCAR, 15 300 km out, are not heard. In the AI's `ContactScan`
  each buoy is one broadcast entry: 16 here against the sandbox's five, a list it already walks for allies; M5 leaves the scan
  (M4's) alone and measured nothing there.
  Comments in `perception.gd`, `targeting_system.gd` and `targetable.gd` still say 1 000 km: they are M4's files and are
  corrected on the rebase.
- **Far buoys and drawing.** The ring's far buoys stay in the tree (D22) thousands of km out, beyond every camera's far plane. M4
  replaces the buoy's splats with a mesh, so T10 adds no splat hiding; whether 15 far meshes cost anything to cull is checked after
  the rebase (T20).
- **Starting in flight.** A scenario's `player` may carry `velocity` (m/s, zero by default); Main gives it to the ship at the first
  spawn only (a respawn still starts at rest). Buoy defence starts the wing coasting at 40 m/s toward the buoy, the wingmen spawned
  on their finger-four slots at the same velocity, on a line that passes the buoy 110 m or more to one side, so a hands-off
  player does not ram it.
- **The intro.** Two shots, every actor in play from load (the player and NAV ALPHA; `test_buoy_defence.gd` checks): `relay`
  (6 s, origin points round the buoy on the far side from the key star, so it stands against the star and its flare) and `wing`
  (7 s, points in the player's frame moving back at 40 m/s, so the camera holds still in space while the finger-four flies past it
  on its left). Control's hail is said, not awaited, as the second shot starts and plays over it. The controls stay locked
  (`lock_controls`) through the brief and hand over with the objectives.
- **Closing lines.** `mission.closing_lines` maps a result's reason (`player destroyed`, `objective failed: protect`) or `success` /
  `failure` to a line id (`MissionApi.closing_line_for`: the reason first). When the mission ends the queue is cleared as before,
  then the closing line is said; the API keeps ticking the queue after the end, and the runner's debrief beat is the longer of
  `DEBRIEF_DELAY_S` and what is left of the line. Why: a mission lost at a stroke (the buoy, the player) has no step left to speak
  in, and "nothing keeps talking over the debrief" still holds. `test_dialog_ids.gd` checks closing lines like spoken ones.
- **The script.** Steps `intro`, `brief`, `wave_one` (three raiders jump in about 9.5 km off the wing's port side, beyond the AI's
  5 km sensors, each sent at NAV ALPHA with `m.send`), `wave_two` (Control's warning, 4 s, then four from starboard and below) and
  `wrap` (the optional objective completes if no wingman was lost, the success lines, then `protect` completes and, as the last
  primary, ends the mission). Pools: 7 raiders and 3 allied Starfuries, every ship the script and the scenario place.

### 18.10 Defensive turrets as built (T21, D61)

```
native/src/turret_kernels.rs     the mounts, the attacker memory, the pick (PickJob, run in the AI job) and the aim, gate, spread
                                 and shot; engine-free, under test_sim_core's guard; Rust unit tests in turret_kernels/tests.rs
native/src/turret_rows.rs        ScsSimCore's shell: add_turret and the bindings, step_turrets (main thread), note_attackers,
                                 the launch's copy and the join's picks, the readouts and the digest
native/src/brain_step.rs         Snapshot.turrets and pick_turrets: the pick beside the thinks, on the frozen rows and memory
native/src/brain.rs              the picks applied at both joins (take_turret_picks, against each mount's stamp)
src/perf/turret_rows.gd          TurretRows: binds the mounts, keeps the relation table, steps once a tick, hands the shots back
src/combat/turret_mount.gd       TurretMount: the mount's place on the ship and its model (yaw, pitch), turned by FramePasses
src/ship/hardpoints.gd           turrets[] {name, position, up, arc_deg, barrel_m}, optional
assets/weapons/turret_light.tres the light turret (WeaponSpec with its Turret group: range, spread, slew rates)
assets/ships/saturn_4_transport.tres  a minimal Saturn 4 for the balance fight (catalog type saturn_4_transport; T16 owns it)
```

D61 as built: the turret kernels went into their own engine-free files (`turret_kernels.rs`, `turret_rows.rs`) beside
M4-T20's capital stand-ins rather than into `weapon_kernels.rs` and `weapon_rows.rs`, so M4-T37's reshaping of those files
(Q28) meets no turret code at the next merge of `main`. Everything else is D61 as written.

- **The split.** The pick is a decision, so it rides in the brains' job (`brain_step::run`): the launch copies the live mounts,
  the memory and the relations into the snapshot (`snapshot_into`), the job picks for every mount, and the join applies each
  pick only when the mount's stamp is still the one it was picked for (a mount parked, rebound or removed meanwhile gets a
  new stamp: `turret_picks_stale` counts the dropped picks). `BrainBatch` launches a job on a tick with turrets even when no
  AI ship thinks. The aim, gate and shot run in `SimCore.step_now` (priority 1) after the cannons and before the bolt step,
  from the ship's row; the shot is an owned bolt row (`add_owned_bolt`), so the native hit sweep lands it like any other bolt.
  The memory is written on the main thread: `HitResolver` notes each landed bolt's shooter and victim in the sweep's order
  (`SimCore.note_hit`, before the hit applies), a destroyed hull is forgotten at once (a pooled ship comes back as someone
  new), and the step prunes what is older than 30 s. A shot's spread is a splitmix hash of the mount's id and the core's tick.
- **The pick.** Over the remembered pairs only (work linear in mounts times pairs, never a walk of every ship): an attacker of
  the mount's own ship, or of a ship within 2 km that is friendly to it or a civilian not hostile to it (`SimCore.set_civilian`,
  set by `ShipAssembly`'s `civilian` option); the attacker alive, not in the low-attention tier, not friendly, within 1.25
  times the turret's range; the nearest inside the arc, else the nearest outside it (the barrel waits at the arc's edge).
- **The mount.** `arc_deg` is a cone round the base's `up` (200: a hemisphere and 10 degrees below the base), so traverse is
  free all round and the elevation runs from `90 - arc / 2` to straight up. Azimuth 0 is the ship's nose laid flat on the
  base (its top when the base faces the nose). The aim leads by `InterceptMath.solve` (the brains' `brain_maths::solve`: the
  bolt inherits the ship's velocity) and slews at the weapon's traverse and elevation rates. The gate opens when the lead is
  solvable and inside the arc, the target within range, the gun ready, and the barrel's miss at the lead point no wider than
  the bolt's spread there plus the target's radius.
- **Strength (Q14; retuned by Q31 to Q33 in T16, §18.11: 6 damage every 2.4 s, 0.5 degree spread, the Saturns'
  hulls per variant; M7-T16: 0.4 degree spread for the raider's new hull).** As T21 built it: the light turret: 900 m/s, one shot every 3.0 s, 4.5 damage, 2 s life, 1.5 km range, 0.8 degree spread,
  50 and 40 degrees a second. Few, harder shots: two hits finish a raider at 15 %, but a full raider takes fourteen, so two
  raiders still win. Pinned by `test_turret_defence` against a Saturn 4 of 1000 hull flown by the `civilian` profile: the
  raid wins in all three seeds (52, 91 and 88 s), the turrets finish a 15 % raider in all three (70, 43 and 34 s). The first
  numbers (2.5 damage every 1.2 s) killed both raiders in every seed.
- **Visuals and sound.** The mount shows its hull's turret model (the manifest's `turret` entry, T27): `TurretMount.model_for`
  splits the mesh once per asset into the base, on `Yaw`, and the barrels, on `Pitch` at the trunnion. A barrel triangle
  lies near a muzzle's axis and is a barrel's side or a flat ring, so the dome the barrels' roots sink into stays on the
  base. A far dot hides the turrets with the hull. `FramePasses` turns every bound mount's `Yaw` and `Pitch` holders once a
  frame from one read of the core's aims (`turret_aims`). A shot emits `TurretMount.shot_fired`, which `AudioDirector` plays
  as `turret_fire` (the sfx_combat generator's lighter gun, version 6).
- **Line of fire (Q33, M5-T16).** A ship's own hull blocks its turrets' fire. `TurretRows` gives the core the ship's own hit
  volumes (its `Damageable`'s boxes and capsules in the body frame, `set_turret_hull`) when its first mount binds and again
  on `Damageable.volumes_changed`; never per tick. `turret_kernels::line_blocked` takes the line into the ship's frame and
  tests it against each volume (a bounding-sphere reject, a slab test for a box, the segment-to-axis distance for a
  capsule, in 64 bits; a volume the line starts in does not count). The line starts `LINE_LIFT_M` (1.5 m) above the
  mount's base, about the trunnion, so a barrel dipping into the hull still reads as blocked. The gate tests the line to
  the lead point and withholds a blocked shot (`turret_readouts()[4]` counts them); the pick tests the line to each
  attacker that would win, on the job's copy of the volumes (re-copied when their version changes), so a turret never
  holds a target its hull hides. About 0.56 us a line test on 45 volumes; work linear in mounts times attackers times the
  own ship's volumes. Every turreted ship has it.
- **No fallback.** Turrets need the core and its bolt rows; without them a mount stays unbound and holds fire.
- **Tests.** Rust: `turret_kernels/tests.rs` (13). GUT: `test_turret_kernel` (aim, arc, gate, pick, memory and stamps through
  the core; the Saturn 4's model split and turned), `test_turret_threads` (threaded against delayed, one thread against six,
  byte for byte), `test_turret_defence` (the balance fight, three seeds), `test_sim_core`'s guard. The mechanics tests fire a
  copy of the light turret at 1.2 s (`TurretScene.MECHANICS_INTERVAL_S`), so a few seconds carry several shots whatever the
  balance sets.

### 18.11 Civilian ships in the game as built (T16, D58, D59, Q24, Q25, Q30, Q31)

```
data/factions.json               + narn, centauri, brakiri (hostile to raiders, neutral to everyone else; Q24)
assets/ships/<civilian>.tres     a ShipSpec per hull: mass and inertia from its hardpoints, heavy and slow, no cannon
src/game/ship_catalog.gd         the nine types, each its people's faction; CIVILIAN_TYPES, is_civilian (the role)
src/ship/cargo_pods.gd           CargoPods: the Bokmai's 0-3 pods (mass, inertia, Jolt shapes, hit volumes, far dot, debris)
native/src/rows.rs               the role column (ROLE_COMBAT, ROLE_CIVILIAN), fed from SimCore.set_civilian, kept in the tier
native/src/civilian.rs           the civilian flight: kin, shelter, group, alarm; engine-free, tests in civilian/tests.rs
native/src/brain_behaviours.rs   the retreat runs the civilian flight for a civilian row; Field marks the fleeing civilians
data/scenarios/civilian_showcase.json   all nine parked in view, a Bokmai with three pods and one with none
tests/integration/test_civilian_flight.gd, test_civilian_ships.gd, test_turret_balance.gd (GUT_SLOW)
```

- **Role, not faction (Q24).** A civilian hull flies for its people (`earth_alliance` for the Saturns and the Skylark,
  `narn`, `centauri`, `brakiri`); `civilian` is a role. `ShipPool.prepare` builds a catalog civilian with
  `ShipAssembly`'s `civilian` option, which calls `SimCore.set_civilian` (T21's turret set). The core reads the role with a
  body's other attributes (on activation and on touch; `set_civilian` touches the body), into `Rows.roles`; a tier row
  takes it at `tier_add`. Rows built without the column (tests) are combat rows (`Rows.role`). No per-tick gather.
- **The flight (`civilian.rs`, in the AI job).** The retreat keeps M3's rule for every other ship and for a civilian with
  nobody to run to (bit for bit). A civilian that sees a hostile in range runs to the nearest ship of its own faction among
  its contacts, of any kind: to a warship's far side from the nearest threat (a standoff of three radii of the larger hull,
  at least 150 m, slowing over 10 s and matching the warship there), or to a freighter (swinging off the threat's side; once
  together, on away); with its people's other fleeing civilians it closes up (a pull toward their centre beyond a group's
  gap, half the run's speed at most). Panic (Q25): before its pass the job marks, from every brain's last think, which
  civilian rows are fleeing (retreat or evade) and which are alarmed (fleeing a threat they see, or dodging fire); a
  civilian with an alarmed kin within 5 km scores retreat at the threat level and runs with it for 20 s after the last
  alarm it heard. The alarm is one hop (only a civilian that sees a threat raises it), so two panicked ships never keep
  each other running. Every query walks the ship's own contacts; the marks are one pass over the brains a tick, sequential
  inside the job, so one thread and six, `threaded` and `delayed`, give the same bits (`test_civilian_flight`).
- **A big hull for what it is.** Against a civilian target the attack brain and the slashing pass measure their ranges to
  its skin (centre distance less its radius) and widen the miss gate by half the radius; the attack's pick ranks a civilian
  by its skin distance. Avoidance gives a civilian contact the rocks' horizon (time for a sideways burn to clear its reach).
  A turret defends a civilian (by role or by its memory's flag) within 2 km of skin. The tier demotes and promotes a
  civilian by its surface distance. Every other row's maths is unchanged, so the brains' parity tests hold.
- **Specs (Q30).** Turning is torque only (no pod torque about pitch or roll, `test_civilian_ships`); zero damping. The
  Saturn 4 and 8 variants share the Saturn 4 transport's engine and thrusters, their mass and inertia their own, so they
  accelerate 0.304, 0.204, 0.168 and 0.106 g; the Saturn 3 keeps its own engine (0.31 g). `rate_max` is three seconds of
  each hull's angular acceleration (the same rule sized the smaller hulls' torque from a rate of about 950 / length deg/s).
  No hull has a cannon; each has its turrets (T21). `damage_layout` is none, so a civilian bursts into its chunks.
- **The Bokmai's pods (D59).** `CargoPods` builds every mount's pod mesh and Jolt shapes once with the ship (pooled with it)
  and `set_count` mounts the first n: the ship's mass and inertia (point masses about the hull's centre of mass), the shapes
  enabled, the `Damageable`'s hit volumes rebuilt (`set_volumes`, the hull kept), the core touched for the new radius. A
  pool hand-out mounts all three; a spawn's `cargo_pods` (0-3) sets it. The far dot hides them with the hull; the pod mesh
  switches LOD with it. A destroyed Bokmai sheds its mounted pods as one-shot debris chunks beside its hull's chunk set.
  The flight model's assist reads the spec's mass, so a laden Bokmai answers a little slower than the assist expects.
- **Turrets and balance (Q31, Q32, Q33).** Every Saturn's command disc carries two flank turrets (`flank_l`, `flank_r` on
  posts at the rim's widest point, up ±x outboard, 200 degrees) instead of Q19's hub turret; the cargo sections keep their
  dorsal one, so a Saturn 3 has 2 and the others 3. The own hull blocks their fire (§18.10): a Saturn 4 transport's blind
  spot lies near its axis astern and a little below (its wide flanks see past the narrow cargo hull elsewhere). Each
  Saturn alone beats two raiders in 1 to 3 of 10 seeds and three raiders in none (`test_turret_balance`, behind
  `GUT_SLOW`): the light turret 6 damage every 2.4 s with 0.4 degree spread, hulls per variant (Saturn 3 640, Saturn 4
  transport 450, Saturn 4 tanker 440, Saturn 8 transport 715, Saturn 8 tanker 380); the counts are in M5's T16 Done block,
  and M7-T16's (the raider rebuilt to its model) retune in M7's. **M7-T16 retune** (Q31's order: the turret first, then the
  hulls; never the raiders' specs or AI): with the raider's new hull the same fights came out within noise of before (turret
  hits 32 % of shots against 31 %, the same loss times and raider hull left), but three variants fell to 0 wins against two
  raiders and the Saturn 8 transport won one of ten against three. The spread at 0.4 degrees (0.5 before) brings the Saturn 3
  to 2 wins and the Saturn 4 tanker to 3; the Saturn 8 tanker needs 380 (330: 0 wins); the Saturn 8 transport sits in a
  narrow window, 715 (1150 before): its one win against two raiders (seed 8) ends with about 700 points taken, and its
  three-raider seed 3 kills them all after about 725 taken, so 700 and below wins none against two and 725 and above wins one
  against three. The turrets finish a 15 % raider in every seed of `test_turret_defence`.

### 18.12 Free-flight encounters as built (T17, D58, Q3, Q9, Q12)

```
src/encounters/encounter_plan.gd       RefCounted, pure: the schedule and each event's draws, hashed from (seed, index, salt)
src/encounters/encounter_event.gd      RefCounted, pure: one event's kind, ships, offsets, velocities, routes, pods
src/encounters/encounter_director.gd   node under Main (pausable): pools, starts, the cap, releases
src/encounters/encounter_console.gd    command and provider `encounters`
data/encounters/free_flight.json       the pools built when encounters turn on, and the kinds' weights
tests/unit/test_encounter_plan.gd, tests/integration/test_encounters.gd, tests/fixtures/encounters/small.json
```

- **Plan.** Event `i` is due at `interval * (i + 1 + 0.25 * (2u - 1))` of encounter time (sim seconds with encounters on), so gaps
  run from half to one and a half intervals (60-180 s at the default 120). Its kind (weights raid 0.4, patrol 0.25, traffic 0.35
  from the pools file), sizes, directions (within 30 degrees of the horizontal plane), ranges and hulls are each `hash([seed, i,
  salt])`: an event never depends on what was drawn before it. Raids: 2-6 raiders around one jump point 6-12 km from their target,
  flying at it at 120 m/s plus the target's velocity; half of them go for an encounter civilian within 20 km of the player when
  there is one (picked by the event's draw), else for the player. Patrols (2, 4 or 6 Starfuries, 220 m/s, passing 0.5-5 km out)
  and traffic (1-3 hulls of any of the nine, 120 m/s, passing 2-10 km out, a Bokmai with 0-3 pods) start 26-30 km out at
  cruise on straight, parallel routes that end as far out on the other side.
- **Director.** A Main whose scenario has `data/encounters/<scenario_id>.json` (free flight) gets one, off. `Main.encounters` (set
  by `Game.finish_loading` from the request) turns it on at load, behind the loading screen; anything else stays off until
  `encounters on`, which builds the pools then (a hitch, a debug path; D58 had it refuse). Pools are grown with
  `Main.ensure_pool`, their debris sets prepared and every pooled ship watched by the `DestructionDirector` (ships built after
  load were not). Ships come from the existing paths: `ShipPool.acquire`, `BrainFactory` (`raider` with the target as
  objective; `ally_starfury` engaging; `civilian`), a `Route` (`pace` none, no loop; a patrol's yields to attacks) through
  `BehaviourFollowPath`, raiders through the director's own `JumpPointPool` (4 points, built with the director; M6-T19 replaced `JumpArrivalPool`). Encounter
  civilians broadcast 15 km (a transponder) so a raid sent from 6-12 km finds them; the range is cleared when they leave.
- **Cap.** `encounter_max_ships` (24, live) counts the director's ships in play. A due event that would pass it waits (one at a
  time; later events queue behind it); one bigger than the whole cap is trimmed to it once nothing else is in play. Raids and
  patrols wait for their pool; a traffic hull whose pool is spent gives way to the next civilian hull with a free ship.
- **Releases.** Once a second, over its own ships only (`check_work` = their number, whatever else is in play): a ship 40 km
  from the player (its tier row's position when tiered) or at its route's end goes back to its pool, then the engine voices are
  re-ranked once. A destroyed ship leaves the count at once (`ship_destroyed`). Encounter ships are pooled, never freed, so
  `AudioDirector.unwatch_ship` is not needed; a parked ship drops out of the core's rows by itself (T28).
- **Console.** `encounters [status|on|off|next|force|clear] [raid|patrol|traffic]`: `force` draws from indices from 1 000 000 up,
  so the schedule is untouched; `next` takes the next scheduled event now (it waits if it does not fit).
- **Settings.** `encounters` (bool, true: the Free flight page starts from it and keeps the player's toggle there for the
  session), `encounter_interval_s` (120, read when encounters first turn on), `encounter_max_ships` (24). The front end gives each
  free flight it starts a fresh seed (`FrontEnd.session_seed`); Restart keeps it.



### 18.13 Generated asteroids and belts as built (T29, D63, Q38)

- **The rocks.** `tools/procgen/assets/asteroids.py` writes 16 shapes from twelve kinds (`KINDS`): potato, fragment, peanut,
  shard, boulder, slab, cratered, rubble, half, banana, spindle and pitted; every kind once, then four again with other draws.
  A shape is an icosphere whose radius along each direction comes from its kind (an ellipsoid, or fused lobes through a soft
  maximum for the peanut and the rubble pile), roughened by five octaves of value noise, pressed with craters, clipped by
  fracture planes (fragments, shards, boulders, slabs, the half rock), then bent or tapered along its long axis. It is
  authored at about 4 m (`AUTHOR_RADIUS_M`, so the fine mesh's detail lies inside the normal map's 0.12 m transfer reach) and
  written as M4's textured mesh: a 5 120-triangle render mesh whose normal map carries an 81 920-triangle fine mesh, painted
  through a `rock` style with no plating, rivets, streaks or bare metal: a grey, brown or cold-grey family per shape, soft
  grime, darker regolith in crater floors, fresher rock on fracture faces. Godot's importer builds the mesh levels.
  `shapes.json` (and the manifest) lists each shape's kind, mesh section, bounding radius and collision spheres: one for a
  round rock, two or three spaced along a long one (its principal axis), each the mean distance of its stretch of surface.
- **The layout.** `BeltLayout.place(belt, shape_count)` (pure) scatters a belt's rocks through its box: sizes drawn as
  `min * (max / min) ^ (u ^ 3)` so small rocks outnumber large ones, placed largest first by rejection against a hash grid so
  no two are closer than `min_gap_m` plus their radii and every rock lies inside the box; seeded (`RandomNumberGenerator`),
  so a scenario's belt is the same every run. A count that cannot fit places what fits and reports the `shortfall`, which `Main` warns about.
- **In the game.** A scenario's `asteroid_belts[]` (`{centre, size, count, radius_m: [min, max], seed, min_gap_m}`, the
  radius a rock's bounding radius) comes out of `ScenarioLoader` as `belts`; `Main._spawn_belts` spawns an `AsteroidBelt` per
  belt from `UniversePos` and connects the world's `rebased`. The belt draws one `MultiMeshInstance3D` per shape (2 km cells
  were tried and measured: more draw calls, no fewer triangles), and makes each collision sphere a static body by RID registered in `StaticRows` (kind `STATIC`, neutral), as M4's
  `AsteroidField` does, so the scan, the hit sweep, rams and avoidance see the rocks with no node per rock and nothing walked
  per tick; it releases bodies and rows when it leaves the tree. Provider `belts` (count, rocks, spheres, draw_groups).
  M4's `AsteroidField` stays the bench's stand-in.

### 18.14 Civilian colours and hull sheen as built (T39)

- **Colours.** The civilian schemes were read off lit screen captures, so `capture_albedo` (`tools/procgen/core/color.py`)
  turns a scheme colour into paint: a measured grey ramp (key star 1.5 at 45 degrees, ambient 0.3, filmic) inverted so a lit
  face shows the capture's colour, then halved (`PAINT_DARKEN`, the maintainer's pick), hue kept. Emission is not touched. The
  Brakiri pods are painted #C8CCB4 directly. Re-measure with a probe if the key light, the ambient default or the tonemap change.
- **Ambient.** `settings.ambient_level` defaults to 0.1 (was 0.3): darker shadow sides, as in the show.
- **Sheen.** `settings.hull_sheen` (0.25, live): `MeshAssets` gives every hull's paint a clear coat (roughness 0.35;
  `StandardMaterial3D.clearcoat`, the livery shader's `sheen`), and `SpaceEnvironment` turns on the sky's reflection
  (radiance 128) while it is above 0. Glass and rocks take none; 0 is the old flat paint.
- **Plating.** The civilians paint no generic staggered grid (seams, tint patchwork, hatches, rivets); T40 draws their
  surfaces per part (§18.30). The fighters keep the grid.

### 18.15 Civilian escort as built (T30, D62, Q36 to Q42)

- **The random civilian.** A spawn and a pool may name `random_civilian`. `ScenarioLoader.resolve_random_civilian(scenario,
  seed)` (Main calls it right after loading, before any pool is built) draws one of the nine hulls from the seed, moves the pool
  to it, gives a Bokmai 1 to 3 pods, and takes a name from the scenario's `civilian_names` for that hull. The name replaces
  `{civilian}` in spawn names, the mission block and the cinematics, and `DialogBook.fill` puts it into the dialog lines;
  scripts read it with `m.filled("{civilian}")`. The menu starts each mission on a fresh seed (`FrontEnd.session_seed`); retry
  keeps it, so the same ship comes back.
- **Flee and resume needed no new native code.** The civilian flies a scenario route (`routes[]`, cruise 120 m/s, waypoints at
  25, 50 and 75 % and 1 km short of NAV BETA) instead of a pilot objective: a passive profile never takes an objective (the
  attack behaviour carries it). The native arbiter already gives retreat (0.85 while a hostile is within the civilian's 3 km or an
  alarm holds) precedence over follow-path (0.5), and follow-path picks up at its current waypoint once retreat scores 0. So
  flee-then-resume is the brains' own per-tick choice; `test_civilian_escort.gd` pins it. Routes through the progress points also
  make the wave triggers reliable: the civilian must pass within 150 m of each to go on, and the triggers use 1 km.
- **Transponder.** Every civilian hull broadcasts to 15 km (`ShipPool.CIVILIAN_BROADCAST_RANGE_M`, the encounters' value), so
  raiders sent from a jump point beyond sensor range find it. A civilian leading a route is not taken for the instructor.
- **Mission actors stay out of the tier.** `MissionStage.register` sets `Ship.tier_exempt` on every ship it knows (the pool
  clears it on parking), and `TierDirector` never demotes such a ship. Without it the civilian, once more than the tier radius
  ahead of the player, was parked in the low-attention tier, and a parked body (hidden, not processing) read as gone to the
  `destroyed` trigger, failing the escort. At most 15 ships, so the tier's savings are untouched.
- **Waves and skipping.** Each wave jumps in 6 to 12 km off the civilian (from its live position) on its own bearing and is
  sent at it with `m.send`. `m.transient(names)` (new) releases a wave's raiders when its step is skipped, so `mission goto`
  leaves no raider behind and the civilian at the step's point. `arrive` waits for all 13 to be gone, then completes `home` if
  ALPHA 2 lives and `escort` (the last primary) ends the mission.
- **Quitting cleanly.** The console's `quit` pauses the tree, silences every player and waits 0.5 s (`QUIT_SETTLE_S`) before
  quitting: a sound stopped in the same frame as the quit kept its playback alive past exit (the "leaked" lines after jump
  arrivals and comms squelches). The comms panel plays nothing once it or the audio has left the tree.

### 18.16 Rock rams by the speed into the rock (T41)

A rock is a sphere nothing moves, so the swept ram rule charged a ship its whole speed. `RamResolver.head_on` now keeps only the
part of the ship's velocity along the rock's outward normal at the contact point (`RamMath.closing_speed`): head-on hits are as
before, a glancing scrape costs its slow closing speed, and Jolt still deflects the ship. Ship-to-ship rams keep the momentum split
of their full relative speed.

### 18.17 Row flight: the flight batch without a gather for native pilots (T31, L1)

A ship whose native pilot commands it from the core's row (M4-T33) is no longer gathered in GDScript. `ScsFlightStep` keeps
each slot's body id, a row-mode flag and the assist and propellant flags (set on change), and `step_core` flies every row-mode
slot that has a live command and an active row straight from the core: the pose from the row, `face_dir_b` from the selection
column (only while braking), gravity from the core's sources. GDScript gathers the other ships, a row ship once when it takes
fresh combat commands, and any row ship whose command the core lost. Outputs are read by slot (`FlightBatch.row_of`). At
`battle` 1000 the flight stage fell from 3.89 to 2.45 ms.

### 18.18 The hit resolver walks candidate bolts only (T32, L2)

`ScsSimCore.hit_bolts` takes the broad phase's hull and rock keys, drops spent bolts and each bolt's pair with its own shooter,
and hands back only the bolts left with a pair (in launch order), their columns, and the columns of the hulls those pairs name.
`HitResolver` no longer reads every bolt's and every hull's columns per tick. The faction test and the narrow phase stay in
GDScript (a couple of pairs a tick in a battle). `last_hit` is described when read. At `battle` 1000 the hit stage fell from
1.30 to 1.01 ms.

### 18.19 The target menu and the radial framework as built (T25, Q26, Q44)

**The target buttons.** A tap (`CombatCommand.target_nearest`) toggles between the nearest and the 2nd nearest enemy
(`TargetCategories.tap_pick`, unknown contacts standing in when no enemy is identified). A hold of `settings.target_hold_s`
gives `UiCommand.target_menu_open`. `target_ahead` and `target_prev` stay actions without a default binding; the wheel
still cycles every target.

**The radial framework** (shared with T46's comms menu):

| Class | Kind | Holds |
|---|---|---|
| `RadialMenu` | pure | the page stack, the highlight, `slice_at` (slice 0 straight up, clockwise; a boundary takes the slice nearer the top; under `POINT_THRESHOLD` nothing is pointed at) and `arrange`, which puts a "none" entry in the down slice of an even ring |
| `RadialLayout` | pure | the ring vertically centred at one side, slice polygons, spokes, label points, scaled by window height |
| `RadialMenuView` | `CanvasLayer` 45 | draws a `RadialMenu`; hidden and not processing while closed |

A slot is `{label, sub, detail, color, payload}`; an empty one is a blank slice the highlight skips. The owner feeds
`point`, `select` and `back` and decides what a selected entry does.

**The target menu.** `TargetMenu` (pure) builds the pages from one candidate list: the six categories with counts, then
the nearest five of one and NONE. `select` returns `{action: target | waypoint | clear_target | clear_waypoint, id, label,
point}` and closes. `TargetMenuDirector` (a node under `Main`) reads `TargetingController.candidates()` before it pauses
the tree, since a paused marker is not in play, then carries the pick out after it resumes. `Main` calls its `step` only
while it is open, with `InputAdapter.sample_radial`'s command.

**Input while a radial menu is open.** `begin_radial` seeds the menu's select and back from what is held;
`sample_radial` reads the direction pointed (the `radial_*` actions, else the mouse's travel), select, back and Start, and
re-seeds every other edge each tick; `end_radial` re-seeds them once more and holds fire and the aim stick over until each
is let go. The `radial_*` actions are in `project.godot` and outside the control profiles, as the menu kit's `ui_*` are.

**Identification.** `TargetCategories.is_identified`: within 5 km, or a broadcast range above 0. An unidentified contact is
grey on the radar (`radar_kernel::plot` flags it from `ident_range_m`; `known_id` exempts a selection already identified),
sits under Unknown, and reads `UNKNOWN` as the target (`HudInput.target_unknown`). `TargetingController.selection_identified`
latches for the player's selection until it changes. `Targetable.role` (ship, civilian, beacon) feeds the categories.

**Waypoints.** `HudWaypoint` holds the pilot's pick and who spoke last. A script's waypoint carries a key that changes when
it is set anew (`mission:<serial>`, `route:NAV n`); `Hud.final_input` lets the director settle the frame's waypoint after
the mission's part. `HudInput.waypoint_id` marks the waypoint's radar contact.

**Cost.** Opening: 0.28 ms with 10 candidates, 2.56 ms with 304 (the list is most of it). Closed: nothing per tick.

### 18.20 The target preview as built (T43, Q44)

While the target menu's second ring is open, a panel at the side opposite the ring shows the highlighted entry: its hull as
a turning green wireframe, its name in the IFF colour, class and faction, and a few rows. On the first ring and when the
menu is closed the panel is hidden, its viewport is `UPDATE_DISABLED` and none of its nodes process.

| Class | Kind | Holds |
|---|---|---|
| `FeatureEdges` | pure | a mesh's creases (faces meeting at more than 25 degrees), open borders and edges of three faces or more, as line pairs; vertices within 1 mm weld, so UV seams and hard-normal splits are no border; `line_mesh` makes the `PRIMITIVE_LINES` mesh |
| `FeatureEdgeJob` | pure | the same search worked a slice at a time (`step(budget_usec)`): weld, faces, collect |
| `WireFraming` | pure | the turn (15 degrees a second from yaw 125), the 20 degree elevation, and the orthographic view height that holds the bounding box through a whole turn |
| `TargetPreviewModel` | pure | the panel's content per kind of entry; `FIELDS` lists each kind's rows, so a field is one entry to add or drop |
| `TargetPreviewLayout` | pure | the panel's rectangle (the ring's centre mirrored, scaled with the ring), the drawing's and the hull bar's |
| `WirePreview` | `SubViewport`, own `World3D` | the drawing; the edge cache |
| `TargetPreview` | `CanvasLayer` 45 | the panel; provider `target_preview` |

**The drawing.** Per part of the hull (the hull mesh; a Bokmai's mounted pods from `CargoPods.mounted_parts`) two draws:
the solid mesh in the ground colour, both sides, to fill the depth buffer (`wire_solid.gdshader`), and its feature edges
tested against that depth without writing any (`wire_lines.gdshader`), so lines on the far side are hidden, not dimmed.
Each line is pulled toward the camera by 0.6 % of the hull's radius, in view space, so it wins against the faces it lies
on; the camera is orthographic, so the pull does not move it on screen. The solid mesh is not shrunk along its normals as
first planned: split normals at hard edges would open cracks. Then one quad over the view (`wire_outline.gdshader`) draws
the outline from the depth buffer: where depth bends across a pixel (left + right - 2 x centre) by more than 3 % of the
radius, on the nearer side only. A flat face has no bend however steep, so only steps draw; this closes rounded hulls
(the Saturns' tanks) whose outline has no crease. The viewport has MSAA 4x, a transparent ground and `mesh_lod_threshold`
0, so the solid is the same full mesh the edges were found on.

**Edges are found once per mesh and kept for the session** (`WirePreview._edges`, by the mesh's instance id). The search is
GDScript, about 1 microsecond a triangle: 53 ms for the largest hull in one go. That is several frames, so `WirePreview`
gives it 2 ms a frame (`FeatureEdgeJob`); the outline shows at once and the creases appear when the search ends (4 frames
for a raider, 26 for a Saturn 8). The plan's alternative, an edge file in procgen's output contract, was not needed. The one
part that cannot be sliced is reading the mesh back from the GPU (`Mesh.surface_get_arrays`): 3 to 9 ms, once per mesh.

**Content.** `TargetMenuDirector._sync_preview` runs when the highlight lands on a new slice (never per tick: the game is
paused). The slot's `source` (its `TargetInfo` or objective) and what the list does not carry (`_facts`: the hull's asset
id, the pod count, whether its pilot is attacking the player) go to `TargetPreviewModel`:

| Kind | Title | Second line | Rows | Drawing |
|---|---|---|---|---|
| ship | name, IFF colour | class · faction | hull bar and percent, range, closing speed, cargo pods (a hull with pod mounts) | wireframe |
| beacon | name | `Nav buoy` · faction | range, closing speed | wireframe |
| objective | its actor or id | `Mission objective` | its text, range | its actor's wireframe, or a diamond for a bare place |
| unknown | `UNKNOWN`, grey | `No transponder` | range, closing speed | `NO ID`, no wireframe |
| none | `NONE`, grey | what picking it clears | | nothing |

`ATTACKING YOU` shows over the drawing when the ship's pilot has the player selected and its brain describes an attack
(`attack`, `ram`, or `aggro` in its attack state); a ship that only has the player selected does not count. An unknown
contact gets none of its facts. Closing speed is `TargetingSystem.compute_readout`'s, signed, positive closing.

**Cost (RX 6950 XT, Forward+).** Showing: 9 draw calls (3 in the viewport for a one-part hull) and 0.06 to 0.15 ms of CPU a
frame; the frame rate stays at the 144 Hz cap in the dogfight and in `bench battle 300`. Hidden: nothing.

### 18.21 The focus pull as built (T44)

While a radial menu shows, everything under it (the 3D view and the HUD) goes out of focus over 0.2 s and comes back over 0.2 s
when it closes, so the menu and the target preview are the only sharp things.

| Class | Kind | Holds |
|---|---|---|
| `FocusPull` | pure | progress toward open or closed at 1 per 0.2 s, the smoothstep amount, `at_rest`; a reversal continues from where it is |
| `FocusPullView` | `CanvasLayer` 44 | one full-screen `ColorRect` with `focus_pull.gdshader`: a mip of the screen read with nine taps, and a dim |

`RadialMenuView.set_showing` opens and closes the pull; the view creates it as its own sibling, so it eases back after the view
hides, and each radial menu (the target menu, and the comms menu since T46) carries it. It runs on real frame time, since the tree is
paused: `delta / Engine.time_scale` with process mode always. Layer 44 is above the HUD (40) and the comms panel's subtitles (41) and under the
radial menus and `TargetPreview` (45); the console, debug overlay (50) and pause menu (60) stay sharp. At rest the layer is hidden and
does not process; `settings.target_menu_blur` (0 to 1, default 0.35) scales the radius (up to 3 mip levels) and dim (up to
35 %), and 0 never shows it. T25's fixed 25 % dim is gone. Console: `target_menu.focus`.

**Cost (RX 6950 XT, Forward+).** Open: about 30 more draw calls with the ring and preview (59 to 89 in the dogfight, 102 to 132
in `bench battle 300`), 0.4 to 0.8 ms of GPU, the 144 Hz cap held. Closed: nothing.

### 18.22 The comms menu on the radial framework as built (T46, D54)

D-pad Right (Ctrl) opens the comms menu as a second user of §18.19's framework: the same ring, size and side, T44's focus pull,
and the game paused while it is open.

| Class | Kind | Holds |
|---|---|---|
| `CommsMenu` | pure | a page stack over a `RadialMenu`: `set_root_page`, `open`, `push_page`, `select` (opens an entry's `page`, or returns the entry and closes), `back`, `close`; the wing orders as the first page |
| `CommsMenuDirector` | node under `Main` | pauses on open, owns a `RadialMenuView`, sends the order through `WingDirector.give_order` after resuming, the `comms_menu` provider and the `commsmenu` command |

An entry is `{label, sub?, color?, payload?, page?: {title, entries}}`; a page pads to four slices (the wing orders sit up, right,
down, left in the order of keys 1-4) and holds at most eight. `Main` calls `adapter.sample_radial` while the comms menu is open,
so the right stick, arrows or mouse point, A selects, B backs (out of the first page it closes), Start hands over to the pause
menu, and the comms key's edge (`UiCommand.comms_open`, read by `sample_radial`; the opening press is seeded as held) closes it. The
4 s timer, `comms_pick`/`comms_close` and the adapter's open-menu swallowing are gone: the pad is not read for flight while a radial
menu is open. The target menu and the comms menu refuse to open over each other; a cinematic, a mission's `lock_controls`
or the pilot's death closes the comms menu. A later page of replies is `push_page` (or an entry's `page`); a page with a "none"
entry goes through `RadialMenu.arrange` so "none" takes the down slice (Q44).

### 18.23 The ram tracker in native (T33, L3)

`ScsRamTracker` keeps what the ram resolver needs between ticks: contacts, windows and one ram per pair per collision. The
rules are §16 D32's, unchanged; the kernel is `native/src/ram_tracker.rs` (engine-free, under the guard test) and the shell is
`native/src/ram_contacts.rs`. The GDScript `RamTracker` is the reference in `tests/fixtures/`, run beside it by `test_ram_tracker`.

| Call (once a tick, in order) | Does |
|---|---|
| `contacts(core, shift, delta)` | Reads Jolt's contacts over the core's rigid hull rows, opens and measures windows, notes the pairs Jolt holds. Returns the hull count, the bodies with no acceleration from the flight step, and the hulls whose ram limits it needs |
| `set_accels`, `land(limits)` | GDScript's answers, only when asked: a hull on its own flight model; the limits of a hull with a measured window. `land` returns the contact rams as columns |
| `swept_pairs(core, delta)` | The broad phase's pairs plus Jolt's, with the columns of just the hulls they name |
| `swept_meeting`, `keep_touching` | Per pair the resolver looks at, as before |
| `end_tick` | Closes the tick |

`swept_pairs` leaves out a pair Jolt does not hold when the swept test is sure to refuse it: the bounding spheres stay apart
(`kernels::ram::clearly_apart`), or the first hull's sphere cannot reach the second's `ram_bounds` (`cannot_reach`, the box read
from the `Damageable` each tick). Both repeat `_sweep_pair`'s first two rejects in 64 bits with a few centimetres of room, so
they only ever drop a pair whose answer is no ram. A fighter inside a carrier's 614 m bounding sphere but away from its hull no
longer reaches GDScript.

The resolver copies no hull columns per tick. It reads the whole columns only on a tick where a contact ram lands or a ship is
near a rock. The shape-by-shape swept test stays in GDScript (about one pair a tick in the battle).

The rocks' grid (`sweep_cells.rs`, also the hit resolver's): a look walks only between a level's lowest and highest held cell; a
kept grid marks its held cells and lists a sparse level's hulls by x range; only pairs that pass the sphere test are sorted. The
pairs, their order and the work count `visited` are unchanged.

At `battle` 1000 the ram stage fell from 0.58 to 0.23 ms and the hit stage from 1.01 to 0.93 ms. What is left of the ram stage
is mostly the contact read: two engine calls a rigid hull.

### 18.24 The core's sync without per-row allocations (T35, L8 and L9)

The first sync (`ScsSimCore.sync_in`) builds the tick's rows. Until T35 it allocated per row and hashed every id with the
default hasher; now it copies blocks and numbers. Results are unchanged: the same rows in the same order, the recorded
fixtures hold.

| Part | Before | Now |
|---|---|---|
| Names | A lowered `String` cloned per row per sync, a `GString` beside it; names matched by string compare | A row carries `name_ids` (a `u32`); `Rows.names` is a shared `NameTable` (`rows.rs`). A wanted name is looked up once, then numbers are compared. Display names are ids too (`row_name_ids`), resolved only when asked |
| Lookups (`index_rows`) | A fresh map of ranks over every member, three default-hashed maps, a sort of every `(id, row)` pair | The rank is a column beside the rows; the maps use `IdHasher` (`IdMap`, `IdSet` in `row_commands.rs`); the rocks' and mines' pairs are sorted once and merged in (`Rows::index_ids_around`) |
| Rocks and mines | Every column pushed per static per sync | One ready block, built in `set_statics`, appended whole (`Rows::extend_from`) |
| Tier rows | Pushed row by row with a name clone | Appended column by column (`TierRows::append_to`) |
| Activity | A hull with no active marker asked four to seven engine calls every tick | Asked only when its body is touched or first seen, as the markers are since M4-T35b |
| The job's snapshot | `Rows` and `Bolts` cloned whole (new columns each tick) | `clone_from` copies into the columns the snapshot holds |
| `snapshot` | A `StringName` and a `GString` made per row per call | Both columns kept and handed out as copies; made again only when a row's faction or name changed |
| Events (L9) | `note_hull` and `note_selection` walked every member | Members listed by body (`members_by_body`, rebuilt in `set_members`), found by binary search |

Rules that follow from it:

- **Name ids are private to one table.** Compare a row's `name_ids` only with an id from the same rows' table
  (`Rows::name_id`). Id 0 is the empty name and matches nothing. A job's snapshot holds the table its rows were made with.
- **Names are dropped, never renumbered in place.** When the tables hold more than twice the bodies plus 256 names,
  `compact_names` rebuilds them at the start of a first sync, where the rows are made again anyway.
- **The id-hashed maps have no order.** Nothing may iterate `row_of_id`, `touched`, `latest_target` or the tier's `by_body`
  for a result.
- **A hull's activity needs its events.** The core hears a body hidden or shown and a hull destroyed or restored
  (`SimCore._watch`). Code that changes a hull's `destroyed` flag or a body's `process_mode` without one of those must call
  `ContactScan.touch(body)`.
- **The scan's GDScript face is unchanged.** `snapshot` still returns faction names, not indices: `ContactScan` and its
  tests keep their columns, and the kept column removes the per-call cost that indices would have.
- `latest_target` keeps a selection only for a member or a tier row; `set_members` drops the rest.

Readouts: `core.core_sync_us`, `core.snapshot_us`, `core.select_us`; `ScsSimCore.sync_parts_us()` splits the sync into the
tier's step, the bodies, the statics, the tier rows and the lookups. A bench's `summary.json` has their means under `core`.

At `battle` 1000 the native sync fell from 0.72 to 0.26 ms a tick and the tick median from 6.73 to 5.9 ms. What is left of the
sync is the bodies' pose and velocity reads (three engine calls a body in play) and the tier's own step.

### 18.25 The radar's dot buffers filled natively (T34, L5)

The radar's plot has been native since M4-T23; T34 moves the painter's per-contact loop after it.

```
RadarModel.plot            ScsRadarPlot.plot: order, ids, points, ranges, colours, rims, unit points, stalks
RadarModel.dot_buffers     ScsRadarPlot.dot_buffers: plain, rim and backing multimesh buffers (radar_kernel::fill_dots)
HudPainter._draw_radar     hands the three buffers to their multimeshes whole; draws the stalks, selection, waypoint
```

- **Buffers come sized for their multimesh.** The painter passes the multimeshes' instance counts; `grown_capacity` keeps
  the size while the dots fit, else doubles or takes the count, and `0` for no dots. The painter sets `instance_count` only
  when it differs and hands the buffer to `RenderingServer.multimesh_set_buffer` with no `resize` or `slice`.
- **Screen placement is native.** `fill_dots` places each unit point on the surface's radar (`centre`, `radius_px`), so the
  painter keeps no per-contact array. The selection and the waypoint diamond are one transform of one point each; the stalks
  are still one transform of the plot's stalk units.
- **`RadarPlot.factions` is built when read** (tests, `to_dots`): `RadarModel.plot` binds the order, the contacts' faction
  indices and the names, and nothing builds the list per frame.
- **The kernel stays engine-free.** `radar_kernel.rs` takes `Vector2` and `Color` builtins beside `Basis` and `Vector3`; the
  guard test lists them.

Readouts: `hud.radar_plot_us` and `hud.radar_paint_us` (smoothed over about twenty frames). At `battle` 1000 the plot call fell
from about 350 to about 100 us a frame and the paint from about 400 to about 110 us.

### 18.26 Flashes and shot sounds culled by range, the flash ring (T37, L6 and L7)

```
ShotCull                 FLASH_RANGE_M 2500, SOUND_RANGE_M 3000; listener(node) = the camera; within(from, at, range)
MuzzleFlashPool.trigger  skips (and counts in `culled`) a flash whose ship is beyond FLASH_RANGE_M of the camera
AudioDirector.play_shot  skips (`shots_culled`) a gun or turret shot beyond SOUND_RANGE_M; takes no voice
MuzzleFlashPool          a ring of CAPACITY slots: head, span, dead slots until the head passes, `_lit` counter
```

- **Why those ranges.** A 1.2 m flash is under a pixel past 2.5 km and its light reaches 10 m; a shot is more than 40 dB down
  past 3 km (inverse distance, 60 m unit size, a 6 km `max_distance` before). Near the player nothing changes. With no
  camera nothing is culled.
- **The ring.** Flashes start in time order, so the oldest are at the head. Full: the head's flash ends and the slot is
  reused; no `remove_at(0)` on four arrays. A flash ended mid-ring (`clear_for`, a ship that left play) leaves a dead slot
  that the head skips later. A flash's age is the pool's clock less its birth, so the pass does not write an age per flash.
  The light cap reads the `_lit` counter, not a scan of the emitters.
- **L7 was done by T19 and T28.** The engine nodes are walked only for granted voices (`engine_frame_work`), the re-rank asks the
  core for ships near the listener; `test_a_frames_engine_work_follows_the_voices_not_the_ships` and `test_engine_voices` pin it.

Readouts: `frame.flashes_culled`, `audio.shots_culled`; the pool's `advance_work` (the ring's span) and `started`/`culled`.

### 18.27 The pause backdrop as built (T42)

```
PauseOrbitPath.create(chase_distance, hull_radius)   radius = max(1.3 x chase distance, 2 x hull radius)
  position_at(phase)   (r sin a, 0.36 r sin 2a, r cos a), a = 2 pi phase: a circle that rises and dips twice, ship-local
  look_at_at(phase)    a point 0.12 r ahead of the ship, pushed 0.22 r to the camera's left (the ship frames right)
CameraRig.start_backdrop(loop_s, hull_radius)   cinematic camera, process mode always, blend 1 s from the view in use
CameraRig.stop_backdrop()                       back to the mode left, chase snapped; chosen_mode() = the mode that comes back
Main                pause_menu.opened -> start (if settings.pause_backdrop), resumed -> stop; the HUD hides while it runs
```

The path is pure and ship-local; every frame the rig puts the camera on the ship's interpolated pose times it, so it needs no
state that a rebase could move (the world is paused anyway). The phase advances on the frame's `delta`. The radial menus do not
start it. A shot playing, no ship or the setting off leave the still frame.

### 18.28 The start screen and the settings groups as built (T45)

```
FrontEnd root list   New game | Load game (disabled, tooltip) | Free flight | Settings | Quit; show_pad = show_right = false
NewGameSelect        missions of MissionCatalog, then SCENES (combat_sandbox, dogfight, instructor_route, civilian_showcase);
                     scene text = "description" in data/scenarios/<id>.json; chosen -> mission or sandbox request
MenuScreen           show_pad, show_right (the frame hides those panels); push_requested(page) (the frame pushes it)
MenuFrame            _apply_layout(): panels per top page; right panel hidden -> Detail label under the list (detail_text())
SettingsSchema.GROUPS  gameplay (game, flight) | controls | camera_hud (camera, hud) | video (graphics) | audio
MenuScreens          settings() -> SettingsGroupsScreen; settings_screen(group) -> SettingsScreen; controls() -> ControlsScreen
PauseMenu            Resume | Restart | Settings | Quit to menu; Settings pushes the same SettingsGroupsScreen
```

Both hosts push one `SettingsGroupsScreen`; choosing a group emits `push_requested` with its page, so the pause menu and the
front end share the five groups with no code of their own. Controls opens `ControlsScreen`, whose list ends with "Sensitivity
and deadzones..." pushing the `controls` category's `SettingsScreen`. A test fails when a menu entry falls in no group.

### 18.29 The smaller performance items and the constants table (T36, L12 and L13)

```
ScsSimCore.bolt_quarantine(buffer, last, forward) -> [buffer with the new-occupant slots collapsed, count]   (bolt_kernels::quarantine)
ScsSimCore.constants() -> { "Class.CONST[@module][#size]": value }                                             (constants.rs)
tests/unit/test_native_constants.gd   every entry equals its GDScript twin
```

`BoltSlotQuarantine` keeps its last buffers and calls the kernel; the pass over the slots (a rule of the previous frame's
place, basis and move) is native, computed in 64 bits over the 32-bit rows in the GDScript's order so the draw is unchanged.
Constants a native file copies from GDScript are `pub` and listed in `constants.rs`; adding a mirrored constant means adding it
there. Smaller changes: the tier prunes only when the removal count changed, `AiContext`'s wing setters ignore an equal value
(so the wing director's per-tick assignment no longer pushes every member to native), the far flashes upload once per frame, the
HUD silhouettes are cached, one driver registers the `ai` console entries, `group_levels` is filled in place and the
core-attached contact view carries the broadcast reach.

### 18.30 Civilian surfaces drawn per part, and the texture detail setting (T40)

```
tools/procgen/core/seams.py     Feature (Cut, Spoke, Hoop, Path, Hatch, Plates), SeamLayout, Relief
tools/procgen/parts/layouts.py  saturn(), saturn_engine(k), skylark(), narn(), centauri(), brakiri(), brakiri_pod()
Part.seams -> HullPart.seams -> TexturedPart.seams -> Atlas.part_seams -> bake_maps (albedo, normal, ORM)
manifest mesh.surfaces[].detail.low = { albedo, normal, orm }      settings.texture_detail low | high
```

- **Features, not a grid.** A part carries a `SeamLayout`: features in the part's own frame, each a distance on the surface
  (a plane's cut, a seam along or round a barrel, a circle, a polyline, a hatch with optional louvres, plating). The layout
  keeps the frame it was drawn in and is transformed with the part, so placed, turned and mirrored copies need no second
  description. The baker asks it per texel for relief (into the normal map), seam cover (darker paint, rougher), and each
  plate's tone and roughness shift. A seam is 2.2 texels wide (`SEAM_TEXELS`), so it is as thin as each hull's atlas allows.
- **Plating.** `Plates` cuts fields into rectangles by rounds of uneven splits (never under `min_m`), hashed from the seed:
  mixed sizes, no rows, no stagger. A plate's tone is a share of the paint's own value, so base colours stay T39's. Plating
  mirrors across the part's centre plane. `scatter` draws only a share of the plates, standing proud (hatches).
- **Levels.** A feature is major (1), full (2: the references' seam density, hatches, ribs, louvres) or plating (3). A civilian
  hull is baked twice from the same atlas: the full set (`<id>_albedo.png` ...) with every level, and the low set
  (`<id>_albedo_low.png`, `_normal_low`, `_orm_low`) with the major features alone. The emissive map and the mesh are shared.
  A model without layouts (the turrets) has one set.
- **The setting.** `settings.texture_detail` ("Ship texture detail", `high` by default, in the Video group) picks the set
  for every ship. The loading is general: `MeshAssets.map_file` reads a surface's `detail` entry, a hull written with one
  set ignores the setting, and the paint, livery and glass materials all take their maps through it. Only the civilians
  have both sets so far; the Starfury, the raider and later hulls join when their generator passes `detail_levels`.
  Materials with a second set are remembered and take the other set's maps when the setting changes, so it is live and
  every copy still shares one material. Only the set in use is loaded.
- **The generic grid.** `Atlas.grid` (on by default: fighters, props, rocks) replaces the styles' `panel_grid` switch; the
  civilian writers pass it off and compute no `plating_for`.
- **Cost.** No triangles and no change to video memory (one set is bound); three more PNGs a hull on disk and a second bake
  (a Saturn builds in about 60 s instead of 40 s).

### 18.31 The settings and controls menus and the audio buses as built (T03, T04)

```
SettingsSchema        every entry has a category; `menu: false` hides debug and tuning switches (test: no entry without one)
SettingsMenuModel     pure: a toggle, slider or option list per entry, unsaved rows marked `*`
SettingsScreen        Apply, Revert, Defaults, Back -> Settings.save, revert, reset; the entry's description on the right
ControlsModel         pure: the profile list (built-in and saved) and each action's bindings (InputAdapter.ACTIONS only)
BindingCapture        pure: the next pad button, stick direction, key or mouse button is the binding; B, Esc or 6 s cancels
ControlsScreen        profile picker, add | replace | unbind, save as; every refusal from ControlProfiles shown with its reason
default_bus_layout    Master -> SFX, UI, Comms; AudioBuses applies master_volume, sfx_volume, ui_volume, comms_volume live
```

- **One page per group.** T45 (§18.28) opens a `SettingsScreen` per group instead of one long page; the model and the
  screen are unchanged.
- **A press binds and does nothing else.** While the controls page waits, the press is swallowed; after a bind B has a
  0.35 s grace, so the pause action from the same press does not close the page. `MenuScreen.back_step` lets B step back
  inside the page before it leaves it.
- **`ui_*` stay.** Only `InputAdapter.ACTIONS` are listed and applied, so no change the page makes can unbind the menus.
- **Buses.** Menu sounds play on UI, the radio squelches on Comms, everything in the world on SFX.

### 18.32 The sound pass as built (T18, T19, T28, D60)

```
tools/procgen/assets/sfx_combat.py   pulse_fire, raider_fire, turret_fire, hit_hull, explosion, main_burst, rcs_burst
tools/procgen/core/audio.py          fm, hold_and_cut, hold_and_release, shaped_periodic_noise
src/audio/engine_voices.gd           EngineVoices, pure: which pod and jet cluster sounds, the cap, the envelopes
native/src/voice_kernels.rs, voice_rows.rs   ScsSimCore.ships_near(centre, radius): rigid ships near a point, nearest first
```

- **Guns and impacts (T18).** A click, then an FM cluster held flat and cut (`pulse_fire` 105 ms, `raider_fire` 150 ms,
  lower and buzzier); `hit_hull` is FM whose brightness dies faster than its level. All are designed at the written
  reference's frequencies and played at a quarter of them (`GUN_PITCH`, M3's register). The Python tests pin length, the
  flat hold, constant pitch, the energy band and the inharmonic partials.
- **Engines (T19).** The old loops are gone. `main_burst` and `rcs_burst` are seamless noise loops with nothing to speak of
  below 300 Hz. Every ship has a voice per pod at the nozzle that fires harder; the player's ship also has one per RCS
  cluster (jets grouped by their side of the centre of mass). `engine_voice_cap` (24) grants the player's voices first,
  then whole ships nearest first within 1.5 km; the frame touches only granted voices.
- **The re-rank (T28).** Four times a second the director asks the core for the ships near the listener and offers them
  until the cap is spent, so its work follows the ships in earshot, not the ships in play. The rows are the tick's, so a
  candidate's node is checked before it is offered. Without a core only the player's voices sound.
- **Culling (T37)** is §18.26.

### 18.33 Tests and CI as built (T38, L14)

`TestSteps` (`tests/fixtures/test_steps.gd`, §12) holds the steps the scene tests share. `scripts/run_tests.sh` has four tiers:
`--quick` (iteration, not a gate), `--standard` (the gate and CI: the slow files, no balance tests), `--balance` and `--full`.
Each starts with the import, since the compile check and GUT know a new `class_name` only after it (T20). The smoke runs go
through `main_run` in `scripts/lib_tests.sh`; the lock files and their order are in `scripts/godot_lock.sh`. CI runs the Python tests in a job of
their own and the GUT files in three shards, with `assets/generated` cached on a hash of `tools/procgen`.

## 19. Epsilon space at true scale (M6)

What M6 adds to §1-§18 (tasks in `docs/milestones/m6-epsilon-space-at-true-scale.md`; evidence for the frame in
`docs/research/m6-moving-frame.md`). The game now sits in the real Epsilon Eridani system at true scale: the local space is a
moving, free-falling frame, bodies move on Kepler rails, one gravity rule acts on every mover, the planet and the sun are drawn in
a scaled-space layer, and the first jumpgate has its vortex. Decision numbers D64 to D71 are M6's. The kernels are engine-free
Rust under `native/src/` (`test_the_kernels_hold_no_engine_type` and its two M6 siblings); the rest is statically typed
GDScript. Task ids below are M6 tasks.

| Part | Read | Replaced or changed by |
|---|---|---|
| The moving frame, the anchor, the velocity rebase | D64, §19.3 | the 200 m/s threshold of §14.1's first draft: 2 000 m/s (Q8) |
| Ephemeris and gravity | D65, D66, §19.4 | M4's `GravityStandin` and the World's own field: gone |
| Flying under gravity | D67, §19.5 | the 9 999 m/s clamp as an absolute speed (§5.6): now against the reference |
| Scenarios at true scale | §19.6 | - |
| The rebase's cost (L4) | §19.7 | AC2 restated |
| Scaled space, the planet, the sun | D68, §19.8, §9.4 | - |
| Far representations | D70, §19.9 | §14.4 |
| The jumpgate and the vortex | D69, §19.10 | M5's `JumpArrival` and its pool (§18.1 D51, §18.12) |
| Seams for M9 and M11 | D71, §19.11 | - |
| Vortex detail by distance, mass arrivals | §19.14 | M6-T20 |
| Ships fly the vortex funnel | §19.15 | M6-T22 |
| Who may open a jump point | §19.16 | M6-T23 |

### 19.1 Decisions

| # | Decision | Rationale (short) |
|---|---|---|
| D64 | Each `WorldFrame` has one **anchor**, a free-falling point in 64-bit (a place on a rail, or a test particle in orbit), and a `UniversePos` is relative to it. The frame **rides its anchor** (`origin_velocity` 0) and moves only by position rebases until the focus passes **2 000 m/s** against it; the **velocity rebase** then boosts the frame onto the focus and it falls on its own until the focus is back under 1 000 m/s. One gravity sample per tick; the frame's step is last in the tick | Stored places and static rows stay valid with no change; float32 speeds stay small; Jolt stays far under its cap; a boost moves no position |
| D65 | One ephemeris in the native core: Kepler orbits, one element set per body around its parent, evaluated directly at any time (seekable, no state between ticks), answering in 64-bit **relative to a point it is given**. The station and the gate are on rails like bodies | Seekable for M9's warp; no barycentric subtraction of 1e11 m numbers |
| D66 | **Only the strongest body inside its zone pulls.** A zone is the radius where a body's pull is at least `a_min` (0.5 m/s^2; `sqrt(GM / a_min)`, 18 300 km for Epsilon III); the pull eases to zero over the outer fifth. Outside every zone nothing pulls; nothing smaller than a moon pulls. A mover feels `g(x) - g(anchor)` (the tidal residual), both under the same rule | A frame that falls with its anchor feels almost nothing; the station's orbit (27 500 km) is outside the zone, so station keeping costs nothing |
| D67 | Speed is read against the ship's **reference** (a place's velocity, or the circular orbit's at the ship near a body), never against the frame. The brake, assist, thrust fade and the 9 999 m/s ceiling read `v - v_rest`; against a body the brake **settles the ship into the circular orbit** at its altitude. Hitting a body or its atmosphere's top destroys the ship | A ship in a steady orbit reads about 0 and can hold the orbit; escaping is just thrust |
| D68 | The star, the planets and (for the far station and gate) other big things are drawn in a **scaled-space layer** in the near world's own pass: a small stand-in per body a few km from the camera at its true angular size, its depth pinned in the vertex shader to a slab in front of the far plane | No second camera or viewport (a SubViewport cost 221 MB more at 3200x1800); the near world, dots and effects draw over it by the ordinary depth test |
| D69 | The jumpgate is a generated prop with collision and a `Targetable` broadcasting to 1 000 km, with a stand-alone **vortex** (meshes and shaders only): orange/yellow for a departure, blue for an arrival. **The same vortex everywhere**: open jump points of ships use it too, and it replaced `JumpArrival` | One effect, one set of tests (Q12, revised) |
| D70 | Big props (the gate, the station's stand-in) have three draw paths by distance: their own meshes, the same meshes **shrunk toward the eye** past the far plane, then a **far dot** under 4 px. The planet keeps the scaled layer, then the dot | No pop: size and direction are continuous by construction |
| D71 | M6's state (anchor, sample, rest velocity) lives on the `WorldFrame` and its core, never in an autoload or a static; the ephemeris is seekable and the integrator takes any step | M9 reuses both; M11 adds a second frame |

### 19.2 Layout additions

```
native/src/ephemeris.rs        Kepler elements, the body tree, add_on_orbit (T02)
native/src/gravity.rs          the zone rule (pull_at, dominant, residual, residual_rows), kick, drift, step (T02)
native/src/ephemeris_binding.rs ScsEphemeris: state, relative_state, zone_radius, dominant (T03)
native/src/frame.rs            Frame: anchor (Rail or Particle), origin, origin_velocity, the tick's sample (T04, T05)
native/src/frame_rows.rs       ScsSimCore.frame_*: the frame's shell; game axes (x, y, z) -> kernel (x, -z, y)
native/src/static_rows.rs      the statics' in-place shift (T06)
native/src/rock_stream.rs      ScsRockStream: which rocks are live in Jolt (T21)
data/star_systems.json         a_min, bodies (Epsilon III), places (babylon5, the gate on its orbit) (T03)
src/world/star_system.gd       StarSystem: load, validate, build ScsEphemeris, impact radii, orbit_state
src/world/star_system_host.gd  StarSystemHost: the `system` provider, DEFAULT_ANCHOR
src/world/world_frame.gd       WorldFrame: anchor, sample and frame-step slots, boost, riding, system_time()
src/world/scenario_frame.gd    ScenarioFrame (pure): a scenario's anchor and epoch
src/world/reference_frame.gd   ReferenceFrame (pure): the reference pick, rest velocity, altitude rule
src/world/flight_reference.gd  FlightReference: the shell that feeds the player's ship (priority -5)
src/world/planet_impact.gd     PlanetImpact (priority 205)
src/world/held_pull.gd         HeldPull: a mover's pull, read once a second of its life
src/world/rock_bodies.gd       RockBodies: dormant and live rock bodies
src/world/shiftable_registry.gd ShiftableRegistry: the shiftables in play
src/environment/scaled_placement.gd, eclipse_math.gd   pure: placement, the star's lit part
src/environment/scaled_space.gd, planet_look.gd, sun_look.gd   the layer, the planet's and the star's look
assets/shaders/scaled_body.gdshader, scaled_planet.gdshader, scaled_atmosphere.gdshader, scaled_star.gdshader
src/rendering/far_prop_math.gd, far_prop.gd, far_prop_host.gd   far representations (T15)
src/props/jumpgate.gd, jumpgate_host.gd, jump_vortex.gd(+shader), jump_point_pool.gd, vortex_timing.gd, vortex_fit.gd,
  vortex_swirl.gd, gate_activation.gd, gate_jump.gd, gate_jump_prompt.gd, gate_autopilot.gd
tools/procgen/assets/planet.py, jumpgate.py; tools/procgen/core/silhouette.py   generators (§9.4 for the planet)
```

### 19.3 The moving frame (D64, T04, T05)

**The anchor.** `Frame` (`native/src/frame.rs`, 64-bit, kernel axes) holds a copy of the star system, the anchor, the local
origin against the anchor and the tick's sample. The anchor is a `Rail` (a place on its orbit: the station) or a `Particle` (a
test particle in orbit about a body, started half a kick back). `WorldFrame.anchor_on_rail(place)`, `anchor_in_orbit(body,
altitude)` and `clear_anchor()` set it; `anchor_offset` (T09) is the scenario's origin from the place the World rides. A
`UniversePos` is relative to the anchor in axes that do not rotate; barycentric numbers exist only inside the ephemeris. The frame
is **quiet** (a residual of exactly zero, nothing read) when the anchor feels no pull and every zone stays more than 1 000 km
(`QUIET_MARGIN_M`) from the local origin, which is the station's case and keeps the parity recordings' bits.

**One sample, the step last.** The tick's slots, around the order of §15.3:

| Priority | Who | What |
|---|---|---|
| -100 (`SAMPLE_PRIORITY`) | `WorldFrame` | takes the tick's time once: bodies placed against the anchor, the zones, the anchor's pull and the origin's own pull. Every mover reads this one sample |
| -12 to -1 | tier, drivers, brains, the flight batch | the movers; the flight step adds the residual natively |
| -5 | `FlightReference` | hands the player's ship its rest velocity |
| 0 | `World` | position rebase; decides whether a velocity rebase is wanted (`_auto_boost`), does not take it |
| 1, 100 to 400 | bolts, hits, rams, missions | |
| 205 | `PlanetImpact` | ships and capitals inside a body's impact radius die |
| `SimCore.OUT_PRIORITY` + 1 (`FRAME_STEP_PRIORITY`) | `WorldFrame` | takes a wanted boost, then steps the anchor and the origin |
| 1 000 000 | `RebaseSettler` | resets interpolation after a rebase |

**The integrator** is kick, then drift, once per physics tick in 64-bit (`gravity::kick`, `drift`, `step`): leapfrog with the
velocity half a step behind, the step Jolt and the tier already take. One fixed step and operation order, so the same bits on
every run; M9's warp composes the same two with its own step. Budgets (measured): an empty frame follows a 400 km circular orbit
within 0.005 m over a whole orbit (budget 0.05 m) and an `e` 0.3 orbit ends within 0.1 m; a ship coasting along the track from the
station's point stays within 0.08 m of a 64-bit run at 1 km, 0.05 m at 3 km (tier) and 0.025 to 0.06 m in Jolt over a whole orbit
(budget 0.5 m).

**The velocity rebase.** When the focus passes `auto_boost_speed_mps` (2 000 in `main.tscn`; 0 turns it off) against the frame,
`WorldFrame.boost(dv)` is asked for; the frame's last slot takes it. **It is taken at the end of the tick, not in `World`'s slot**
(a change to D64's first draft): bolts, debris and the tier step themselves inside the tick and the bodies in Jolt's step after
it, so a boost at priority 0 put the bolts one step ahead of the bodies (33 m at 2 000 m/s). A boost takes `dv` off every body's
`linear_velocity`, every core row (`Rows.boost`, `Bolts.boost`, `TierRows.boost` with a capital's `cruise`), the ram tracker's
remembered velocities and open windows (`Tracker.boost`), and every projectile, chunk, wreck, explosion, emitter and far flash
(`frame_boost(dv)` or a `boosted` listener: `DebrisPool`, `FxPool`, `FarFlashes`, `RamResolver`); `origin_velocity += dv`, and
`TierDirector` settles the boosts a parked body sat out (`boost_sum`). The frame is then **off its anchor**: it falls freely and a
mover feels `g(mover) - g(origin)` (`origin_pull` fixed at the sample), exactly zero at the local origin; the anchor-tied things
(group `world_anchored`: buoys, the gate, a stand-alone vortex, the station's stand-in, belts and fields, mines) and the static
rows move with the anchor each tick (`drifted(shift)`). When the focus is under half the threshold the boost goes back onto the
anchor and the frame rides again. A boost moves no position, so it needs no interpolation reset. Particles stay in their node's
frame.

**Rest velocity.** Speeds are read against `v_rest`, never against the frame (§19.5). While the frame rides its anchor and the
anchor is the reference, it is zero and every result is bit-identical to before M6.

### 19.4 The ephemeris and gravity (D65, D66, T02, T03, T07)

- **Ephemeris** (`ephemeris.rs`): elliptic orbits (e up to 0.99), Kepler's equation by Newton with a fixed 24 steps, a body tree
  evaluated at any time (`state`, `relative_state` against a body or place), `add_on_orbit` for a point sharing an orbit at a phase
  offset (the gate on the station's orbit, 50 km ahead). GDScript reads it through `ScsEphemeris` only (`StarSystem`); no second
  implementation. `data/star_systems.json` holds `a_min`, the bodies (Epsilon III: `gm` 1.68e14, radius 4 780 km, atmosphere top
  100 km, a 0.6 AU circular orbit; no moon, Q1) and the places (Babylon 5 on a 27 500 km circular orbit, period 19.4 h; the gate).
  Metres, seconds, degrees; `gm` is authoritative; every refusal on load names the key.
- **Gravity** (`gravity.rs`): `pull_at`, `dominant`, `residual` and `residual_rows` implement D66; the n-body sum and `tidal` stay
  beside it for tests. `Frame::residual_rows` gives a batch the bits one `residual` per mover gives, in 1 and 6 parts.
- **Who feels it.** Ships: the native flight step adds the residual to every ship it flies, as `env_accel` and the brake's
  feed-forward (`env_b`); a ship on its own model (the player's) reads `WorldFrame.environment_accel`, which is the residual alone
  (the World's own field and `GravityStandin` are gone). Tier rows: `tier::step` takes the pull per row on top of the engines' held
  acceleration; a hulk falls, a capital's engines hold its cruise against the pull. Bolts: `bolt_kernels::advance` adds the pull times
  the 32-bit delta before the move (a bolt launched this tick neither moves nor falls). Debris, wrecks, explosions and projectile
  nodes: `HeldPull` reads the pull once per second of the mover's life and after a boost (0.0027 m off a per-tick read over an 8 s
  chunk, cheaper than a per-tick read). With no pull every step is the old one bit for bit.
- **The bench.** `battle` and `typical` fly in a 400 km circular orbit of Epsilon III (`BenchLayout.gravity_orbit`); the runner
  anchors the frame there and puts the rail back after. The seeded weapon battle's recording (`weapon_rows_battle.json`) is that
  orbit with the tier off (comparison table in `tests/fixtures/parity/README.md`).

### 19.5 Flying under gravity (D67, T08)

- **Rest.** `kernels::flight::Rest` goes into `flight::tick` beside `env_accel`: the brake gets `v - v_rest` and the feed-forward
  `env - a_rest`; the thrust fade, the assist's safe speed and the 9 999 m/s ceiling read `|v - v_rest|` (the pull itself is
  applied in full). The flight step gives each ship the World's rest (`frame_rest`: minus the frame's velocity and its origin's
  pull) or a ship's own (`set_rest`, `clear_rest`); the tier's step does the same for fighters. `Ship` does it in GDScript for the
  player (`rest_velocity()`, `set_reference_rest`, `SpeedGovernor.clamp_against`); `ship.speed` is the speed against it. A zero
  rest is a branch that keeps the old expressions.
- **The reference** (`ReferenceFrame`, pure, `FlightReference`, its shell): the mission's reference if it names a candidate; else
  the nearest place whose broadcast holds the ship (`settings.reference_place_range_km`, 1 000, held to a tenth beyond); else the
  dominant body; else none (the World's anchor). A body's rest is the **circular orbit's velocity at the ship**, prograde in the
  plane of the ship's motion, `sqrt(pull r)` from the zone rule, falling with the ship's own pull so the brake's feed-forward cancels:
  holding the brake settles the ship into that circle, and holding it far from any place is an orbit, not a stop against the
  planet. Console `reference [auto|<id>]`, provider `reference`.
- **HUD** (`HudLayout.relative_velocity`): `REF <name>  <range>  <closing>`; the speed, the velocity marker, the drift sphere and
  the angles read against the reference; `ALT <km>` on a line under it while a body is the reference or the ship is within
  `settings.hud_altitude_radii` (1.0) radii of its surface. `Main.reference_point()` is the reference's universe position.
- **Brains** get their snapshot (`snapshot_into`) with the World's rest taken off every local velocity (bodies, tier rows, missiles,
  bolts), so cruise, stop and run-up speeds mean speed against the place with no brain changed. Spawn velocities in data, waves,
  missions, gate arrivals and encounters are against the place. GDScript-only brains (`perceive()`) still read frame velocities.
- **Planet impact.** `PlanetImpact` asks the core each tick for rows (tier rows and the player included) inside a body's radius
  plus `atmosphere_top_m` (`frame_set_impact_radii`) and kills each with `HitInfo.CAUSE_PLANET`; god mode does not hold a ship up.
- Held under assist in a 400 km orbit with the brake held 20 s: within 0.000 m / 0.0011 m/s riding, 0.029 m / 0.0027 m/s in a frame
  boosted 2 500 m/s (`test_low_orbit_flight.gd`).

### 19.6 Scenarios at true scale (T09)

- **`anchor`** in a scenario file (`ScenarioFrame`, parsed by `ScenarioLoader`): `{"place": "babylon5", "at": [x, y, z]}` (the
  World rides the place's rail; `at` is where the place stands in the scenario's coordinates, so every layout keeps its numbers;
  `standin` puts the station's stand-in there), `{"body", "altitude_m", "phase_deg", "inclination_deg"}` (a circle that high) or
  `{"orbit": {...}}` (any orbit; the start state comes from the ephemeris on a copy of the system, `StarSystem.orbit_state`).
  With no `anchor` the scenario's origin is on the station's rail with no stand-in. The anchor is the scenario's origin: for the
  place form the World rides the rail with `anchor_offset`, and the few readers that took the anchor for the place subtract it
  (`ScaledSpace.body_from_anchor`, `FlightReference.places`), so no scenario position moved.
- **`epoch`**: seconds of system time at the start, or `"seeded"`. **The sim clock still starts at 0**; the World holds `epoch_s`
  and `system_time()` = epoch + `SimClock.now()` is what every ephemeris reader asks. A seeded epoch (`ScenarioFrame.seeded_epoch`)
  takes a lit start with the planet's centre within 25 degrees of the player's forward and its disc at least half lit.
- All seven scenarios place the station 6.6 to 9.6 km from the start (`[5500, -1200, -6000]`; `belt_showcase` `[2000, 4500,
  -9000]`) with an epoch (free flight seeded; the sandbox, showcases and escort 540 148 s; the instructor's route 3 267 594 s; the
  dogfight 7 482 671 s). `Main._anchor_world` resolves the frame (a frame the system cannot place falls back to the station's rail
  with a warning); `FarPropHost.place_station` builds and dresses the stand-in; the gate stands on its rail 50 km ahead on the
  station's orbit, facing the station (`JumpgateHost.place`). Encounters take planned velocities against the player's reference.
- Console: `system` gains `epoch_h`, `time_h` and `anchor`; `scaled epoch <hours>` offsets the World's system time for captures;
  `frame [status|orbit <km> [body]|rail <place>|off]`.

### 19.7 The rebase's cost (L4, AC2; T06, T21)

- **A shift is not a new version** (T06): `StaticRows.shift` moves a world's rows in one native call (`ScsStaticRows.shift`) and
  bumps `moves`, not `version`; the cached `Solid` shifts in place; the resolvers' kept grids take the new places by a native
  `keep`; `ScsSimCore.move_statics` updates the core's copy. Parked pool ships are skipped (`WorldFrame.PARKED_META`).
- **Live rocks** (T21): each rock keeps its RID body, but only rocks a rigid hull could reach soon are live; the rest have layer
  and mask 0 and are never moved. `ScsRockStream` looks the core's rigid rows up in a dense grid of the rocks in their owner's frame
  every tick (before `sync_out`); a rock within 0.25 s of motion plus 20 m comes to life, and is demoted once no hull has been within
  that reach plus 10 % for 30 ticks. Bodies stay in Jolt (never made again), which keeps Jolt's contact order and the recordings'
  bits. Bolts, rams and the scan read the rows, never the bodies.
- **`ShiftableRegistry`** keeps the shiftables in play from `node_added` and `node_removed`; `set_out` parks a node out of it
  (the pool's and the tier's parked ships, idle debris chunks and effect emitters). A rebase walks about 450 nodes instead of 1 130.
- **Numbers**, `bench battle 1000 20 warmup=3 seed=1` (headless, pinned 0-11): the rebase tick's median extra over the tick median
  2.25 ms (before L4) -> 1.77 (T06) -> about 1.2 (T21); the off-anchor tick's extra 1.21 -> 0.64 -> 0.28 ms. **AC2 is restated
  (maintainer, 2026-11-12)**: the original bar (worst rebase tick within 10 % of the median) sits inside the tick's own spread (p90
  is +14 %), so AC2 asks for the cascade's removal and the median extra measured before and after. Left: the resolvers' kept rock
  grids are rebuilt on every rebase and off-anchor tick (about 45 us each).

### 19.8 Scaled space, the planet and the sun (D68, T10 to T12; the planet's maps are §9.4)

- **Depth.** One pass: `assets/shaders/scaled_body.gdshader` gives every pixel of a body one reversed depth from a slab just in
  front of the far plane (2e-9 to 1e-8, the nearer body the larger): behind everything nearer than about 49.5 km and in front of the
  star points (1e-9) and the sky. Measured on the RX 6950 XT: the pinned depth is inside the noise of no layer at all (1 200x675
  0.31 to 0.75 ms against 0.31 to 0.66); a SubViewport cost +36 MB (+221 MB at 3200x1800) and bypassed anti-aliasing and motion
  vectors. It relies on a 32-bit float depth buffer.
- **Placement** (`ScaledPlacement.place`, pure): from two 64-bit places against the anchor gives the direction, the true distance,
  the angular radius, and the stand-in's offset and radius (distance and radius shrunk by one factor: 1:1000 while that fits, else
  onto a 20 km shell), so the angle and the limb's perspective are exact and everything stays inside the 50 km far plane. No
  position beyond the local space reaches the GPU as a world coordinate. `ScaledSpace` makes one sphere per body of **the World the
  current camera is in** (`WorldFrame.of(camera)`), re-placed every frame from the ephemeris at `system_time()` and the camera's
  drawn pose; a rail anchor sees a body through `relative_state(body, place)`, a free-falling one through `anchor_state()` against
  its home body. A World with no star system draws nothing.
- **Light.** `SpaceEnvironment.follow_sun()` turns the `KeyStar` to the true star each frame (what `PostEffects` reads, so the lens
  flare follows) and multiplies its energy by `ScaledSpace.key_light()`, the smallest lit part over the planets (`EclipseMath`, the
  overlap of the two discs). The planet's shadow is a key-light factor, not a shadow map. `hold_key_star(true)` gives the light to
  a look sheet. The flare fades with `ScaledSpace.flare_strength()` (`SunLook.flare_factor`: from 0.02 of the disc showing to all).
  One patch to the vendored flare's shader source (`SceneLensFlareEffect.SHADER_PATCHES`) reads a depth of 2e-8 or less as open sky,
  so the star's own disc does not hide the flare.
- **The planet** (`scaled_planet.gdshader`, `PlanetLook`): the surface on a 64x32 sphere pushed out to enclose the true one, each
  pixel finding its own point on the true sphere (a round limb at any distance), maps sampled with seam-safe gradients; relief lit
  only where the sun is up, a hard terminator, the night side 0.004 of the albedo with no lights; full sun is 1.5 against the Filmic
  tonemap. `scaled_atmosphere.gdshader` is a shell to the atmosphere's top, added over it (16 samples of sunlit air per view ray):
  a faint warm rim and glow on the lit limb, none on the night limb. No tilt or spin (the data has none). A body without built maps
  keeps the plain stand-in, with a warning. Cost with the planet filling the view: +0.08 ms from the rail and +0.24 ms looking
  down from 1 000 km at 1200x675.
- **The sun** (`scaled_star.gdshader`, `SunLook`): a sphere ten times the disc, each pixel working out its distance from the centre
  in disc radii, so the disc is the true size, with limb darkening (0.7) and a corona out to 9.5 radii; the colour from the star's
  temperature (`StarColor`: 5 084 K, orange-white); disc brightness 2.4. 0.025 ms with the star filling the view. Brightness,
  corona and haze strengths are look choices (H).
- Console: `scaled [status|epoch <hours>|show|hide]` and provider `scaled`; `scripts/planet_sheet.sh` makes the look sheets.

### 19.9 Far representations (D70, T15; changes §14.4)

`FarPropMath` (pure) and `FarProp` (the node) give a big prop three draw paths:

1. **near**: the prop's own mesh, out to `pull_m` = the far plane less 1.02 bounding radii and 500 m (48.1 km for the gate, bounding
   radius 1 408 m; 45.4 km for the station's stand-in, 4 028 m);
2. **shrunk**: the same nodes under one `Look` node, drawn shrunk toward the eye by `pull / distance`, so they cover exactly the same
   angle in the same direction with the same materials and levels (a continuous hand-off, so no hysteresis); the meshes take
   `lod_bias` 100. The cost: something truly in front of the prop but between the pull distance and 50 km is drawn behind it;
3. **dot**: once the bounding radius is under `DOT_PX` = 4 px a far dot (`far_prop_dot.gdshader`: M4's rule, the angular size with
   a 1 px floor and the square dimming under it) takes over with M4's hysteresis (back a tenth inside) and a 0.35 s cross-fade. Its
   area comes from a silhouette table the generators write (`tools/procgen/core/silhouette.py`, manifest `far`: the outline's area
   along 227 directions, blended by Shepard's rule; 3 % mean error), because a gate seen end on covers a sixteenth of its side
   view. Its light follows the mesh's (mean albedo times ambient, the hull's own glow, the key star's energy times `hull_phase`),
   and is 0 in the planet's shadow. The hand-off is at about 248 km for the gate and 709 km for the station at 1 080 lines.

The **planet** keeps the scaled layer at every distance and hands over to the same dot once its disc is under 4 px (about 841 000 km
at 1 080 lines; `ScaledSpace.dot_of`, `is_dotted`). Per the maintainer (2026-11-12): the station's stand-in keeps a **1 000 km**
range (`FarPropHost.STATION_RANGE_M`; it has no `Targetable`) and a far dot keeps M4's honest dimming (the gate at 1 000 km is a faint
point; the HUD and radar find it). `FarPropHost.dress_station` is called where the stand-in is placed for good. Nothing here is
`top_level`: a rebase or a drift moves the look and the dot with the prop. Drawn size across each hand-off is within 0.5 % of what
the distance alone explains (`test_far_prop_math.gd`). Console `far [status|station|view <gate|station> <km>|off]`, provider `far`.
At 1 000 km (GPU): the gate 23 draw calls, 145 fps (the display's cap), 379 MB; the station 26 to 30 draw calls, 410 MB.

### 19.10 The jumpgate and the vortex (D69, Q12, T13, T14, T19)

- **The gate** (`tools/procgen/assets/jumpgate.py`, generator v5; shape and colours in `docs/design-references.md`, "Jumpgate
  (M6)"): four arms **parallel to the vortex's axis**, round it like the corner rails of a square tube, 1 200 m long, the top and
  bottom arms 800 m from the axis and the side arms 1 240 m (an elliptical mouth, `mouth_aspect` 1.55), 2 562 m wide, 44 collision
  boxes on the rock layer, no hull (bolts pass through), 40 lamps, four tip emitters, 2 048 px maps. The manifest and
  `hardpoints.json` carry the `vortex` marker: the mouth's semi-axes (`mouth_semi_axes` draws them within 1 m of the arms: 1 198 m by
  753.9 m), depth 1 200 m, the arrival and departure points and the colours. `Jumpgate` (`src/props/jumpgate.gd`) is a `Targetable`
  (`PROP`) broadcasting to 1 000 km (`BROADCAST_RANGE_M` 1.0e6, so the radar, targeting and the AI see it at that range).
- **The vortex** (`JumpVortex`, `jump_vortex.tscn`, `jump_vortex.gdshader`) is its own logic and scene, sized and placed by whoever
  opens it: `JumpVortex.create(colours, standalone)`, then `open_at(transform, VortexFit, direction, hold_s, lead_s)` (origin at the
  mouth's centre, -Z the way out). `VortexFit` holds the mouth's semi-axes and depth: `for_gate` from the marker, `for_ship` for an
  open point (mouth radius 4 bounding radii, never under 60 m, depth 1.6 radii, one ship radius behind the ship, facing its
  heading; widened to hold a group). The funnel's triangles run from the base out to the rim, the base drawn first with the walls
  (72 % opaque) blending over it, so the walls hide the dark circle on the base from oblique views; from the side or behind the base
  glows white. Meshes and shaders only (D22).
- **Timing** (`VortexTiming`, pure, a function of the age in sim seconds): an optional lead-in belonging to the opener, then the
  phases `activate`, `flash` (1 s), `grow` (1.5 s, the funnel unfolds from the centre point to the rim), `open` (4 s by default,
  `extend` while a ship is on its way, `close_now`), `closing` (1 s, folding back to the point), `end_flash` (1 s, a white flash like
  the opening one, in both directions and at every point) and `closed`. Nothing passes from `closing` on (`is_open` false, `open_in_s`
  INF); a departing ship counts as through at half grown. A gate's lead-in is `GateActivation` (1 s: the 40 lamps flash from the
  front ends to the back ends along all four arms, then the back ends glow into the flash).
- **Swirl** (`VortexSwirl`): seen from in front, an **arrival** turns counter-clockwise and its patches travel out; a **departure**
  turns clockwise and travels in, along one spiral (checked frame by frame). Colours: arrival blue, dark sky blue; departure
  orange/yellow. The rim fades over a soft wisped edge measured against `references/jumpgate/jumpgate.png`.
- **Open points** (`JumpPointPool`, replacing `JumpArrival` and `JumpArrivalPool`, which are gone): `open_for(at, forward,
  ship_radius, ..., opener)` sizes a point for the ship (only a jump-capable opener, §19.16); a group arriving within 600 m (`SHARE_M`) in the first second (`SHARE_S`) shares
  one point; the pool (`DEFAULT_COUNT` 4 until M6-T20) takes back its oldest point when none is free. The ship is placed as before
  (the pool opens after the ship is acquired), so missions and encounters keep their outcomes. Missions use `arrival: "jump"` (an
  open point) or `arrival: "gate"` (through the gate) and `m.depart(name)`; an encounter pool's `gate` table sends a share of arrivals
  or departures through the gate while the player is within 25 km (free flight has one).
- **The player's jump** (`GateJumpPrompt`, `GateJump`, `GateAutopilot`, `JumpgateHost`): within 10 km with the gate targeted the HUD
  shows `X: REQUEST JUMP` (X is auto-track everywhere else); the controls lock, the autopilot lines up 1 440 m out (around the arms
  if behind) and runs in at 250 m/s under a `CinematicShot`, a flash, a fade and 2 s of black, then the ship comes **back out through
  the blue vortex** at 200 m/s and control returns after 3 s or 500 m. In M6 the trip is a round trip; hyperspace (M11) replaces it.
- Console `gate [status|open|close|jump|cancel|target|approach|view]` (`gate open <dir> <hold_s>`; `gate view reference` is the
  acceptance pose of the still), `vortex [status|open|close|view]`; providers `gate`, `vortex`.
- GPU (RX 6950 XT, headless gamescope): the vortex costs about 0.23 ms and one draw call, even filling the screen from inside; the
  cost is fill (about 0.1 ms per covered megapixel). An open point at 300 m: 0.70 ms open, 15 draw calls. Frame rate in a visible
  window is (H).

### 19.11 Seams for M9 and M11 (D71)

- The ephemeris is seekable and the integrator takes any step, so M9's on-rails warp calls the same `kick` and `drift`. M9 changes
  the anchor when the player travels: a hand-over that converts or drops the places held against the old one.
- One `WorldFrame` per space, each with its own anchor, sample and rest velocity; M11's hyperspace adds a second one. Statics that
  still assume one frame (found by T01; M6 adds none and fixes none): `SimCore._current`, `StaticRows`, `ContactScan._shared`, the
  directors' `_current`, the `_live` lists, the console's `world` provider. M11 fixes them.
- The station is a stand-in (M4's look-only `StationStandin`, no collision, no `Targetable`) on a rail; M7 replaces it.

### 19.12 Console and settings

Commands: `frame`, `boost`, `ride`, `reference`, `scaled`, `far`, `gate`, `vortex` (listed in `info.md`). Providers: `system`, `world`
(anchor, `origin_velocity`, `riding`, `boosts`, `planet_impacts`), `reference`, `scaled`, `far`, `gate`, `vortex`, `core`
(`gravity_rows`, `gravity_us`). New settings: `hud_altitude_radii` (1.0) and `reference_place_range_km` (1 000). The automatic
velocity rebase is `World.auto_boost_speed_mps`, an export of `main.tscn`, not a setting.

### 19.13 Tests and measurements

- **Tiers (T17, T18).** `scripts/run_tests.sh` has `--quick`, `--standard`, `--balance`, `--full` (§12). A test names its tier: quick
  for pure or fast files (under about 5 s, no `SlowTests` gate; listed in `tests/quick_suite.txt`), standard for scene-booting fights,
  whole-asset builds and anything slow-gated, GPU files (`*_gpu.gd`) standard and Pending headless (green on the RX 6950 XT). T18
  removed 9 files and 27 GUT tests the review confirmed as duplicates; the parity recordings, the damping guard and the
  engine-free guards were kept.
- **Frame and gravity:** Rust `frame::tests`, `gravity`, `ephemeris` (138 Rust tests at T21); GUT `test_free_fall` (the whole low
  orbit through the binding), `test_velocity_rebase` (27 movers through a boost: universe positions unchanged, velocities within
  6e-5 m/s), `test_gravity_movers`, `test_gravity_orbit` (standard: a whole orbit in the tier and in Jolt, a curved bolt),
  `test_flight_reference`, `test_low_orbit_flight`, `RebaseFight` with `boost_every_s`
  (`test_rebase_in_play`: 168 boosts and 201 position rebases in a 90 s fight, no jump over 41 878 tick checks).
- **Scenarios, scaled space, props:** `test_scenario_frame`, `test_scenario_anchor`, `test_true_scale_start`, `test_scaled_placement`,
  `test_eclipse_math`, `test_scaled_space`, `test_planet_look`, `test_sun_look`, `test_far_prop_math`, `test_far_props`,
  `test_vortex_timing`, `test_vortex_fit`, `test_vortex_swirl`, `test_gate_activation`, `test_gate_jump`, `test_jumpgate_broadcast`,
  `test_jumpgate_in_play` (standard), Python `test_planet`, `test_jumpgate` (standard), their helpers (quick) and `test_silhouette`.
- **Cost (AC10),** `bench battle 1000` (pinned 0-11, idle): tick median 5.74 and 5.67 ms before gravity, 5.73 and 5.70 after (within
  1 %, 5 % allowed); gravity reaches about 270 ships, 680 tier rows and 1 100 bolts a tick for about 35 us. `test_ai_think_time`
  passes (AiPilot median 185 us for 13 ships). The velocity rebase adds nothing while riding (one boost: 0.45 to 0.64 ms).
- **Full tier (T16), `scripts/run_tests.sh --full`, at `b75e0785` (2026-11-13):** passed in 4 886 s. Python 925 tests OK (2
  skipped), 679 s. Rust kernels 138 passed, 0 failed. GUT with `GUT_SLOW` and the balance tests: 344 scripts, 3 705 tests, 3 680
  passing, 25 risky or pending, 170 142 asserts, 4 040 s. The pending ones are the GPU files ("needs the real renderer, no
  RenderingDevice headless") and two balance fights under the maintainer's review (AC12: 5 of 5 seeds did not finish in 360 s, and
  waves [1] cleared in 900 s with no wingman left). Every console smoke passed; CI is green for that commit.
- **GPU check and acceptance.** GPU numbers so far are in the tasks' notes (T10 to T12, T15, T19, T20, T22; §19.14 has T20's: a
  hundred points cost 0.1 to 0.3 ms of GPU time). The agents' runs were headless gamescope with a 60 fps cap, so the frame rate in a
  visible window on the maintainer's desktop is an (H) item, with the rest of the checklist in `docs/playtest.md`.

### 19.14 Vortex detail by distance and mass arrivals (M6-T20)

- **Detail by distance** (`VortexLod`, `src/props/vortex_lod.gd`, pure). Six layers drop out as the mouth's projected radius in
  pixels falls, finest first, each fading over a band whose top is 1.5 times its bottom (no pop): finest hairs 240 to 160 px, fine
  hairs 120 to 80, broad hairs 54 to 36, patches and rim wisps 24 to 16, fine cloud octave 12 to 8, coarse cloud 6 to 4. That gives
  seven levels (0 everything, 6 the soft disc of the base colour with its band, rim fade and dark throat). A fading layer blends
  toward its mean so the tone does not shift, and a layer at weight 0 is not computed. Under 10 px the funnel uses a 24 x 10 mesh
  instead of 96 x 40 (back above 14 px). The centre flashes are not layers and keep their timing at every level.
- **Per instance.** Vortexes of one set of colours share one funnel material per direction and one flash material; growth, the
  base's view, swirl time and layer weights are instance uniforms (`vortex_state`, `vortex_lod_a`, `vortex_lod_b`). A closed vortex
  does not process. A pool lights its 3 nearest open points (`VortexLod.lit`) and starts at most 4 arrival sounds a second.
- **`JumpPointPool`.** Up to 100 points (`MAX_POINTS`), driven by one `_process`; opening fills the point's fit and timing in place
  (`VortexTiming.reset`); a free point comes from a cursor, else the oldest is taken back. Opening and drawing 100 points makes no
  node or object but a few sound playbacks. `open_for(..., share = false)` and `join` let a caller that grouped its ships open one
  point per group.
- **Battle arrivals** (`BattleArrivals`, pure, and `BenchRunner`). In `bench battle` and `bench typical` every ship comes out of a
  jump point. Ships of one side and one fight within 600 m share the group's first point; a capital opens its own, sized by cross-section.
  Waves bring whole fights (the player's first), 100 points a wave, each later wave a point's life plus 1.5 s (10 s) after the last,
  the points spread over 1 s. `battle 1000`: 353 points in 4 waves (100, 100, 100, 53; the last at 31 s), never more than 100 open.
  The warm-up stretches until the last wave is in (32 s). A battle of one wave places every ship at the start as before
  (`test_weapon_rows_battle` unchanged). `arrive=placed` places every ship at the start. The report gains `arrivals`, `engine_ticks`
  and `render`.
- **Measured.** GPU (RX 6950 XT, 1920x1080, `battle 1000`, headless gamescope, 60 fps cap so GPU time is the measure): chase view
  0.98 ms median with 100 points forming against 0.86 placed, 1.11 against 0.82 with 100 open; overview 0.82 against 0.69 and 0.93
  against 0.72; about one draw call per point in view; renderer VRAM 461 to 462 MB in all runs. Tick (headless): arriving median
  5.10 and 6.31 ms at battle 500 and 1 000, p99 6.87 and 8.48 (placed 4.61 and 5.74; 6.17 and 7.72). While the waves come in the
  engine tick p99 is 14.8 ms against 10.2 placed, and one tick's arrivals cost up to 4.8 ms.
- **Console.** `vortex lod <auto|0-6>` forces one level on every vortex, `vortex view [mouth radii]` holds the camera on a point;
  provider `vortex` gains `lod`, `radius_px`, `forced_lod`, `lit`.

### 19.15 Ships fly the vortex funnel (M6-T22)

- **The passage** (`VortexTransits`, one per World; rules in the pure `VortexTransit`, scaling in `TransitScale`, the record in
  `VortexPassage`). It serves any ship through any open point or gate, whoever opened it: `begin_arrival(body, vortex, exit_position,
  exit_velocity)` and `begin_departure(body, vortex, on_through)`. An arriving ship waits on the funnel's base through the opening
  flash, comes out of the black ring in its own white flash, shrunk, and flies out to its place in the mouth, growing to exactly 1.0
  there with the velocity its spawn asked for. A departing ship flies on down the axis, shrinking, and flashes and vanishes when its
  nose touches the base. The vortex is held open for each passage; a gate closes after its last ship is through.
- **Scale law** (`VortexTransit.scale_at`). The ship keeps its share of the funnel's width as it narrows, at most `MARGIN` (0.8) of it
  and never above 1; every ship reaches the ring's share of the mouth (0.24) at the base, and one too big for that shrinks further.
  The size used is the radius across the line of flight. In a ship-made point the funnel keeps T19's depth and the passage takes
  `MIN_TRANSIT_S` (2.5 s) to `MAX_TRANSIT_S` (6 s) instead, the ship's own speed held between them.
- **Normal, scaled, in transit** (`TransitScale`). The body is never scaled; its children and Jolt shapes are, and so are the hit
  volumes (`Damageable.set_hull_scale`), so the ship stays targetable and collides at its scaled size. Mass, inertia and zero damping
  are kept. Ships in one funnel do not collide with each other. Rebuilds are throttled (6 a tick, exactly 1 at the end).
- **Pilots and flashes.** An AI pilot is held for the passage (`AiPilotDriver.in_passage`) and decides afresh afterward. Ring flashes
  are one pooled multimesh of up to 256 (`transit_flash.gdshader`), a rendering-server instance placed in global coordinates every
  tick so the rebase guard holds. An arrival under 2 px on screen comes out in place with the flash (`VortexTransit.worth_flying`),
  which keeps a far battle wave as cheap as T20's.
- **The player's jump** (`JumpgateHost`, `GateJump`) is always an outside shot, whatever view was active: it follows the ship down
  the funnel to the ring's flash, fades to black, and on arrival watches the ship come out and grow, then hands the controls back.
- **Every path:** missions, encounters, the battle's waves, the gate's departures and the player's jump. Console `transit`, provider
  `transit` (`info.md`). Costs: `battle 1000` window tick median 5.94 ms, p99 7.81 against T20's 6.31 and 8.48.

### 19.16 Who may open a jump point (M6-T23)

- **The rule** (`JumpCapability`, pure; the maintainer, 2026-11-13): only a jump-capable ship opens a point. `ShipSpec` has
  `can_open_jump_point` (false for every designed hull: the Starfuries, the raider, the nine civilian ships) and `jump_hold_range_m`
  (0: twice the ship's length); `CapitalStandin.CLASSES` gives every class `can_open_jump_point: true`. Any other ship arrives or
  leaves through a gate or through an open point a capable ship holds, of any side. `JumpPointPool.open_for` / `open_with` take the
  `opener` and refuse one that cannot (`refused`); a point with no opener is a debug tool's (`vortex open`, a fighter's
  `transit arrive point`) or a test's, held by nothing.
- **Holding** (`JumpPointPool._physics_process`, its held points only, a hundred at most): a point holds while its opener is within
  `hold_range_m` of the mouth (the opener's position, or its tier row's). Out of range, destroyed, disabled (a hulk) or gone, it
  collapses at once (`JumpVortex.collapse`, `VortexTiming.collapse_now`: no fold, the closing flash at its peak) and every ship in
  its funnel, arriving or departing, is destroyed (`VortexTransits.kill_in`, `HitInfo.CAUSE_VORTEX_COLLAPSE`, no shooter, no kill
  credit). An opener that touches the black ring of its own point holds it `OWN_DEPARTURE_HOLD_S` (3 s) more, then it collapses on
  whatever is still inside. Gates are exempt: their vortex closes by its timing and waits for its ships (T22).
- **Raids and missions, by data.** A mission spawn says `arrival: "jump"` with `via: "carrier"` or `via: "gate"` (`arrival: "gate"`
  is the same as `via: "gate"`; a `jump` with no `via` is only for a capable ship, else an error), and optionally
  `carrier: {"class", "then"}`. An encounter pools file has `via: {"raid": "carrier" | "gate"}` and `carrier`; its `gate` share still
  sends raids through the gate while the player is within 25 km of it. `CarrierJumps` (one per World, the carriers pooled at load,
  D22: 3 for a mission, 3 for the encounters) brings a capital stand-in (a cruiser by default) out of its own point where the raid
  comes in; fighters of one side arriving within 2 km in that second come out of the same point, each at 0.6 mouth radii round its
  axis. Once they are out the carrier waits 2 s, lets its arrival point close, opens a departure point 3 s of its 20 m/s ahead of
  its bow and leaves through it (or stays, `then: "stay"`), back to the pool at the ring. Its guns are silent; it can be shot. A
  departing AI ship with no gate (`MissionStage.depart`) routes to the nearest departure point a capable ship holds
  (`CarrierJumps.send_departure`).
- **The battle** (`BattleArrivals`, `BenchRunner`): units and waves as T20 (the same 353 units in 4 waves at `battle 1000`); each
  fighter group then rides the nearest capital point of its side in its wave within 6 km (its own fight's capitals) that has room
  (one group per capital) and comes in with that capital, at its point's mouth; any other group comes through the battle's own
  jumpgate (`BENCH GATE`, 14 km below the first fight, beyond the tier's reach from the player, facing up, made for the run and
  freed after), on a spiral across its mouth at its 200 m/s, 4 a tick (`Jumpgate.arrivals_per_tick`; 0, all at once, elsewhere).
  Only capitals open points: `battle 1000` 150 points (46 open at most), 138 groups (713 fighters) through capital points, 65
  groups (137 fighters) through the gate. A later wave's capitals open two to a tick, evenly over its second
  (`CAPITALS_PER_SLOT`), and once the battle runs their riders come out 8 a tick in the ticks between (`RIDERS_PER_TICK`), inside
  their point's opening flash. The warm-up waits `ARRIVAL_SETTLE_S` (14.5 s, the gate's lead-in included) past the last wave.
  Measured (after T23's follow-up): window tick median 4.55 and 5.76 ms at 500 and 1 000, p99 7.20 and 7.80; engine tick while
  the waves come in p99 14.4 to 15.1 ms (T22 14.9).
- **Console.** `vortex collapse` (destroys the newest held point's opener), `transit carrier [-] [-] [none|follow]`; provider `vortex`
  gains `opener`, `hold_range_m`, `opener_distance_m`, `held`, `collapses`, `collapse_kills`, `last_collapse`; provider `carriers`.

### 19.17 Known gaps (carried to later milestones)

- Arrival-tick spike: while the battle's waves come in, the engine tick p99 is 14.4 to 15.1 ms against 10.2 placed. What is left
  is a capital joining play, about 7 ms in its tick whatever the number (the core's member rebuild when a hull enters the tree,
  the stand-ins' native capital set); pooling the later waves' capitals, or adding members to the core one by one, would flatten it.
- A stand-alone jump point beyond the 50 km far plane is not drawn; it has no far stand-in like the gate's.
- The gate is placed on its rail at the start and then holds still in the frame, while its true place turns round the station once
  an orbit (the chord between them moves about 4.5 m/s, 16 km an hour); M7 or a moving prop row carries it.
- The station's stand-in has no collision and no `Targetable`; M7 replaces it (done: M7-T06, §20.1).
- GDScript-only brains (`perceive()`, the few pilots not native-capable) read frame velocities; a turret marker on a moving capital
  keeps its row velocity; the rocks' broad phase in the hit sweep takes the bolt's own segment off the anchor.
- The resolvers' kept rock grids are rebuilt on every rebase and off-anchor tick; a ship spawned in a tick right beside a dormant
  rock meets it one Jolt step late (the row-based ram still lands).
- The planet has no tilt, spin or detail layer (the map is soft from 400 km straight down); the shells' and dots' motion vectors
  under TAA and FSR 2 are not checked.
- Doppler is out: voices stay in the local frame.

## 20. The Babylon 5 station (M7)

What M7 adds (tasks in `docs/milestones/m7-babylon-5-station.md`, decisions D72 to D78 there). M7-T14 writes the section in full;
the parts below are contracts other tasks build on.

### 20.1 The station in the game (D74, T06)

```
src/world/station.gd             Station: the frame and drum bodies, hulls, marker, visuals, the drum's turn; provider and command `station`
src/world/station_spin.gd        StationSpin (pure): the drum's angle from the system's clock
src/world/station_sections.gd    StationSections (pure): the damage sections' health, a hit's section, a loss said once
native/src/surface.rs            big hulls' surfaces: packed volumes and hull planes, nearest points, the segment sweep, a turning skin's speed
native/src/surface_rows.rs       ScsSimCore.set_surface / clear_surface / surface_count / surface_volume_count / surface_distance
```

- **Placement.** `FarPropHost.place_station` builds a `Station` where the scenario's anchor puts the station (M6-T09) and dresses
  its visuals for the far field (`FarPropHost.dress_station`; the bodies never shrink). The node is shiftable and anchored, so
  rebases and an off-anchor frame's drift move it with the anchor (D65). M4's `StationStandin` stays for the bench's
  `station_scene` and the look tools only.
- **Bodies.** The manifest's `collision.pieces` become two `AnimatableBody3D`s (`sync_to_physics` off) on the rock layer: the frame
  never moves in the station's frame; the drum is set each tick at priority -50 (after the frame's sample, before the core's sync)
  to `StationSpin.angle_at(system_time)` plus a phase kept when `station spin` holds and restarts it, so Jolt moves it kinematically
  and its skin has the drum's speed. The drum's body is a node of the World beside the station, shiftable and tied to the anchor
  itself (a group member never sits inside another), placed at its pose before it joins: a rebase or the frame's drift moves it
  once, and a velocity rebase leaves its motion against the anchor (its turn) as it was. The visual drum turns each frame to the
  same clock between ticks. No lights (M7-T18).
- **Big hulls in the core (`ROLE_SURFACE`).** Each piece carries a `Damageable` (the frame's on the `Station` node beside the
  `Targetable`) whose row the core marks with the role `ROLE_SURFACE` once `set_surface` gave its body the hit volumes (16 numbers
  a box or capsule) and the convex hulls they were fitted to (by volume index). `Rows::surface(r)` gives a row's surface. With it:
  - `hit_bolts(hull_keys, rock_keys, rock_count, delta)` sweeps a pair's bolt against the surface in the hull's frame (hull planes
    where given, else the box or capsule, grown by the bolt's hit radius) and keeps the pair only when it hits, with where along
    the tick (a 26th column, `-1` for ordinary hulls); `HitResolver` takes that instead of sweeping the shapes.
  - The ram tracker's swept pairs leave a surface row out (no prop sweep over 4 km); a ship ramming the station is Jolt's contact.
    A contact with a turning surface (spin not 0) rams at once by `|v_ship - (v_rest + w x r)|`, the whole speed between the hull
    and the skin under it (Q9), whatever Jolt's friction made of it; the station takes nothing.
  - Avoidance treats each volume within reach as a threat at its nearest point (so a tunnel's floor and roof push equally); the
    fire lane tests the segment against the volumes; the brains' skin range to a surface is the distance to its nearest volume.
    Every other row's arithmetic is unchanged (parity recordings green); the surfaces travel with the rows into the AI job.
- **Damage (Q5).** A hit's point in its piece's frame picks the damage section whose box holds it (`StationSections.section_at`);
  the section's health falls (20 000 each, to be tuned by T07 and T10), the `DamageZones` layout `STATION` shows each section's
  own share and `Silhouette.set_station_sections` draws them side on; `Station.section_lost` fires once per section. The hulls are
  invulnerable: the station is never destroyed or disabled.
- **Marker.** `BABYLON 5`, `earth_alliance`, kind `PROP`, broadcasting to 1 000 km (the AI hears it, M3-T17).
- **Cost.** Jolt's physics stage with a fighter in the tunnel, along the spine and along the drum: +11 to +31 us a tick on a quiet
  machine (one and six core threads), +43 to +91 us under load (`test_station_jolt_cost`, slow); T05's 192 shapes a piece stand.
