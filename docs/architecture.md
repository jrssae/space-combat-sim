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
  run_tests.sh                python tests, godot --import, GUT headless, junit to reports/
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
- If Jolt ever becomes the obstacle, the fallback is a custom integrator driving a `Node3D`; the pure-class split
  (D5) keeps that contained.

## 6. Input and the debug console

### 6.1 Gamepad mapping (user-chosen layout)

```
RT  right main pods (analog)      LT  left main pods (analog)
RB  right retros (hold)           LB  left retros (hold)
R-stick  up/down pitch, left/right yaw, diagonals roll       L-stick  strafe L/R + up/down
D-pad Up  flight assist           D-pad Down  next weapon           D-pad Left  running lights        D-pad Right  free
A  fire       B  tap: next target, hold (0.35 s): previous target
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
are key 5 alone (m1_classic, which rolls on the D-pad, is the same).

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
| `render` | RenderStatus (M4-T31) | `renderer` (`forward_plus`, or `headless`), `fps`, `frame_ms`, `draw_calls`, `triangles`, `vram_mb`, `far_dots`, `gpu`, `gpu_ms` |
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
emitters out (`ThrusterVisuals` and `MuzzleFlash` watch the node's disable and exit), and `_process` puts them back when it plays
again. Numbers: `src/rendering/emitter_curves.gd`.

Console: `state lights` (`picked`, `candidates`, `active`, `cost_us`).

### 7.4 Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| A hull's texture maps blur or shimmer up close (cockpit view of the nose) | low | The Starfury's normal map is at twice its atlas (4 096 px), the maps have mipmaps and anisotropic filtering; the look gates are the maintainer's (H). |
| GPU time at the 500 battle | low | Every copy of a hull instances; far ships are dots in one multimesh; the importer's levels of detail; `RenderScale` caps a very large window's 3D (§17.15 adds resolution scaling if needed). |
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
- Modes are an enum (`COCKPIT`, `CHASE`; `CINEMATIC` and `FREE_LOOK` later). Toggle via `toggle_camera`;
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

### 9.4 Running

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

## 12. Testing strategy

| Level | Tool | Runs where | Covers |
|---|---|---|---|
| Python unit | `unittest` | container, CI | UV atlas, maps, PNG and glb writers, determinism (hash of output), hardpoints schema (pods, nozzles, CoM), centroid ≈ 0, the manifest's `mesh` section, CLI registry |
| GDScript unit | GUT `tests/unit` | container, CI | `FlightModel` (pod forces at positions, r × F signs per §5.2 table, zero pitch/roll from pods, trim maths, brake symmetry, clamps, mass flow), `FlightAssist` (pod-yaw sign, deadzone, frame-rate-independent smoothing, cap at `rate_max`, converges, never exceeds limits or triggers), `InputAdapter` (radial deadzone, expo, roll ramp, edges, invert-Y, command split), `TriggerCalibration` (rest 0 and -1), `ChaseCameraMath` (frame-rate independence), `PulseCannonGate` (modes, rates, cycling), `TargetingSystem` (next, ahead, readout), `UniversePos` (64-bit precision at 1e11 m), console (tokenizer, typed args and errors, help, history, completion, provider whitelist, owner pruning), `SettingsSchema` (types, ranges, session vs save) |
| Headless integration | GUT `tests/integration`, `--headless` | container, CI | ship scene instantiates; damping guard; pod-differential yaw measured in Jolt matches the model; assist turns at the pod-yaw rate under one trigger, stops on release, and flies straight inside the deadzone; brake; projectile velocity/lifetime; the textured meshes import with their materials and maps; `World.rebase` keeps velocities and relative positions; scenario spawns buoys; targeting with live buoys; `SkyFollower`; camera toggle; console masks keyboard but not pad, and every subsystem's provider answers `state`; `main.tscn` runs 180 frames without script errors; a `--console-exec` run prints the expected `[console]` lines and exits with the requested code |
| Human acceptance | checklist in the milestone doc | Linux/Vulkan GPU + generic XInput pad | hull appearance, compositing, feel, performance, controller behaviour, trigger/deadzone calibration, targeting |

Rules: every pure class gets unit tests in the same PR; every scene gets at least an instantiate-and-run test;
anything that depends on a GPU is marked `(H)` in acceptance criteria and is never faked in CI.

CI (M3-T12) runs GUT in two jobs: `GUT_SHARD=k/n` makes `scripts/run_tests.sh` run every n-th GUT script from the k-th, in path
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
- `WorldFrame` (the `World` node): the local Jolt/render space. It holds the frame origin's universe position and
  velocity (64-bit) and propagates them as a **free-falling test particle**, so local physics only feels tidal
  gravity (a ship near the orbiting station is effectively weightless, which is physically right).
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
- **Velocity rebase** (roadmap M6, still off) when the focus speed relative to the frame exceeds 200 m/s: subtract `v`
  from every body's `linear_velocity` and projectile velocity; `origin_velocity += v`. Keeps Jolt well under its cap and
  keeps float32 velocities small.
- Local space radius ~10 km. Anything farther (planets, sun, distant ships and stations) is not in Jolt: it is
  propagated in universe coordinates and rendered in scaled space (§14.4). B5's ~8 km length fits: at ±8 km
  float32 resolution is ~1 mm.

### 14.2 Gravity

**Decision:** celestial bodies (sun, planets, moons) move on analytic Kepler orbits ("on rails", deterministic,
seekable in time). Ships, projectiles, asteroids and comets are massless test particles under **restricted n-body**
gravity, the sum of `μ_i / r²` over all bodies of the system (a dozen bodies per system is cheap). No patched
conics for actual motion: sphere-of-influence switching makes flybys discontinuous, and the user asked for
physically honest assists. Patched conics may still be used for UI orbit previews.

Coexistence with Jolt: project gravity stays 0 forever. Each tick the Ship (and any body) gets
`World.environment_accel(local_pos) = g(x_body) - g(x_frame)` applied as a central force. The tidal residual is
tiny near the frame origin, which is why the free-falling frame is chosen. The brake and future velocity-hold
assists receive `env_accel` as feed-forward (§5.2 already takes `env_accel_b`). Expectation to communicate to
players: a solar flyby alone does not add heliocentric energy (that is physics); gains come from an Oberth burn at
perihelion or from flybys of moving planets, and the sim does both correctly because it is honest.

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
- **Scaled space** for the sun, Epsilon III, moons and anything beyond ~50 km: a separate render layer drawn
  before the near world, placed at `camera_dir × (distance / scale)` with matching angular size, lit from the true
  sun direction. Planets and the sun are procedural-shader meshes (sphere + atmosphere scattering + generated
  textures), because they are huge smooth bodies needing day/night lighting and limb effects; their near-field
  features (cloud layers, rings, belts) get their own meshes or particles.
- The starfield stays camera-relative (one per star system, generated).

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
| `tools/procgen` framework layout, per-asset output dirs, manifest `lods` array | T02, T04 | Moving files and rewriting import paths for every later asset |
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
src/combat/impact_flash.gd        short additive flash + sparks, child of the hit ship at the hit point
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

One physics tick, in order (`process_physics_priority`, then tree order):

1. `AiPilotDriver`s (-10): build a `Perception`, call the brain, `Combatant.apply_commands(flight, combat)`.
   Commands are levels and rates, never positions, so a later rebase in the same tick cannot stale them.
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
- **Now** `RamBroadPhase` (pure) boxes each hull's bounding sphere along its path through the tick, grown by a metre, and sorts
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

- **Optional during M4** (maintainer Q9). No GDScript names a native class: `NativeLib.instantiate(&"ScsName")` returns null when
  the library is not loaded or the setting `perf_native` (default on) is off, and the facade then runs its GDScript code. So a
  missing or stale library never breaks parsing, the suite or the game, and a bench can pair native against GDScript in one
  process by flipping the setting. Each facade keeps the GDScript code as the reference its parity tests compare against.
  A native class gets its own name (`Scs...`), since a GDScript `class_name` cannot share it.
- **Building.** `scripts/build_native.sh` builds only when the library is missing or older than a file under `native/`; with no
  `cargo` it prints one line and exits 0. `run_tests.sh` runs it before the import, and CI builds once per job with cargo's
  files cached on `Cargo.lock` and the toolchain file. Without the library Godot logs three errors about it at every start;
  `run_tests.sh` ignores those three, and only when the library is absent. The library is built for baseline x86-64, never
  `target-cpu=native`, so the maths is the same on every machine.
- **Crossing the boundary** (Cycle log, cycle 4, debug editor build): a native call with one int costs 0.12 us, 0.22 us through
  a facade, against 0.08 us for a GDScript call; one with a packed array in and one out about 0.35 us plus a few ns per element.
  Packed arrays share their data (copy on write). So the seam is one call per ship per query with packed arrays in and indices
  out, never a call per contact, and native code never reads a GDScript object. Results are collected in Rust and handed over once.
- **Threads** are allowed inside native code later (N3, maintainer Q9), with a test that one thread and six give the same
  output; T05a adds none.
- **Following the setting.** `NativeLib.enabled()` caches `perf_native` and clears the cache on `Settings.changed`, so a
  facade asks it on every call and a flip takes effect at once, also on objects made before it (T05b). `NativeLib.version`
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
  returns false; `ContactScan` then marks the scan rejected and answers it from GDScript. The grid's cell count is a checked
  product, so a range too large to enumerate (a huge finite one saturates the cell indices) tests every body instead.
- **Parity is bit for bit** (maintainer, 2026-11-02). The field repeats GDScript's arithmetic: 32-bit vectors, 64-bit scalars,
  the engine's order (`x*x + y*y + z*z`), a float rounded to 32 bits before it scales a vector, the same comparisons
  (`<=` for contacts, "not greater" for nearest-k, equal ranges to the earlier body) and no fused multiply-add (Rust never
  contracts). `test_contact_field` compares both paths on seeded worlds of 1 to 300 bodies and on bolts that graze the
  15 m line, where only the same precision gives the same count.
- **Contacts are made when first handed out.** Each faction's list starts empty and a `Contact` is built the first time a
  query returns that body, on both paths (a broadcaster nobody hears, or a body no ship of the faction sees, costs nothing).
  The objects are still one per body per faction per scan, shared and read-only.

### 17.6 The battle and typical layouts and the stand-ins (T07)

```
src/perf/battle_mix.gd              BattleMix, pure: the typical and grand profiles, counts per entity type from N
src/perf/bench_layout.gd            + battle and typical: fights on an 8 km lattice, capitals, rocks, the moon, the sides
src/perf/standins/standin_director.gd   Node3D (World/Standins): holds and steps the stand-ins, counts the battle
src/perf/standins/capital_standin.gd    RigidBody3D: a box hull with Targetable (kind capital) and Damageable, cruising
src/perf/standins/turret_standin.gd     Node3D under a capital: a gun or an interceptor, stepped by the director
src/perf/standins/asteroid_field.gd     Node3D: one MultiMeshInstance3D, static sphere bodies by RID, a marker per rock
src/perf/standins/gravity_standin.gd    Node: a point source installed as WorldFrame.environment_field
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
  20 to 200 m, log-uniform) is centred on the player's fight and clears every hull by 100 m; the moon is a point source 400 km
  below pulling 0.03 m/s^2. Sides 3 and 4 (`bench_c`, `bench_d`) fly raider and Starfury hulls with their own faction, so the
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
- **The moon** is `WorldFrame.environment_field` (new), a `Callable` that `environment_accel` calls when set. Ships already add
  `mass * environment_accel(position)` every tick, and capitals do in their engines. Bolts fly straight (they never took the
  environment), so the moon bends ships' paths and every intercept's drift, not bolts.
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
- **Native and GDScript run the same grid.** With the library loaded and `perf_native` on, `ScsHitSweep`
  (`native/src/hit_sweep.rs`) answers; the GDScript code is the reference and the fallback. Both use the same levels, cells and
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
native/src/body_registry.rs     ScsBodyRegistry: the scan's bodies, known once, read natively in one refresh a tick
src/ai/body_kind.gd             BodyKind: ship, capital, turret, missile, mine, static, prop; rocks and mines are obstacles
```

- **What it ends.** After cycle 4 the scan's queries were native but the scan itself was still gathered in GDScript every
  tick (`ContactScan.from_tree`: walking the groups and reading about fifteen properties a body), with the broadcast scan
  built the same way and a freed-body check on every `shared` call. With the library and `perf_native` on, `shared` now
  comes from `ContactScan.from_registry`: no per-body GDScript a tick. `from_tree` stays the reference and is counted
  (`ContactScan.gathers`, 0 a tick on the native path).
- **Membership.** The registry is told the `targetable` and `damageable` groups (`set_members`, the group arrays passed
  whole) when they change: `ContactScan` listens to the tree's `node_added` and `node_removed` for markers and hulls. A
  pool ship stays in the tree when parked, so play rarely changes the members; spawning and parking do not.
- **The refresh.** Each tick's first scan calls `refresh` once. For every member it asks the engine what
  `Targetable.is_active()` and `Damageable.is_active()` ask (in the tree, visible, processing; a hull's `destroyed` flag only
  for a body with no active marker), then reads the active body's global transform and its `linear_velocity` (a prop's
  marker `velocity`) through the node's own getters, so every value is the one GDScript reads. The plan said
  `PhysicsServer3D` by RID; that differs from the node by a quaternion round trip after any teleport (a spawn, a rebase),
  which breaks bit parity, so the node's getters are used (they are engine calls, not script). The axes are normalised as
  `Vector3.normalized` does it, in 32 bits. Faction, name, kind and radius are read only when a body turns active, when it
  is hidden or shown (each body's `visibility_changed` touches it, which covers the pool's release and acquire in one
  tick), or after `ContactScan.touch(body)` or `invalidate()`. Rows come in group order (markers, then hulls with no
  active marker, deduplicated by body), then the node-less static rows.
- **Hull and selection** are read when a contact is first handed out (`Contact`s are made lazily since cycle 4), on both
  paths alike (fix round 1: the tree gather no longer reads them at the build), so the paths agree whatever changes between
  a scan's build and its queries (a hit, the console, the player). A driver that changes its ship's selection first calls
  `ContactScan.note_selection`, so this frame's scans still hand out the selection they were built with (M3's behaviour).
- **The broadcast scan** is `ScsBodyRegistry.select`: a row, read now, for each active marker of
  `Targetable.broadcasters()` in that list's order (a body's second marker gets its own row, as in `from_broadcasters`),
  with each broadcaster's range read in GDScript. A body's hull is its first `Damageable` in group order, which is child
  order, so it is the one `Damageable.of(body)` finds.
- **Kinds** (`BodyKind`). A marker's `kind` property (M4-T07 adds it to `Targetable`) is read as a name or a value; a
  body without one is a ship. `static` and `mine` rows are never contacts: `contacts_for` and `nearest_for` skip them on
  both paths, so a rock field or a mine belt never fills a fighter's twelve. `statics_for(own, at, faction, k)` gives the
  `k` nearest by surface distance (centre distance less radius, equal ones to the earlier row) within the sensor range,
  in scan order; the field searches the cells the range plus the largest static radius reaches. `Perception.statics`
  holds them (setting `ai_nearest_static_k`, 4; 0 = none) and `AiPilotDriver` adds them to avoidance's contacts:
  `AvoidanceMath` treats a contact as an obstacle with its radius and velocity; for a rock or mine its horizon is at least
  the time a sideways RCS burn takes to clear the obstacle's reach (plus `URGENT_SETTLE_S`), so a 150 m rock is seen early
  enough to go round, while ship-sized contacts keep M3's horizon. The fire lane does not read statics.
- **Rows with no node.** `ContactScan.register_static(id, position, radius, kind, faction, world)` adds a rock (by RID) or
  a mine row to both paths, after the bodies, in registration order; `unregister_static`, `clear_statics`. A row belongs to
  the `WorldFrame` it was registered with (its position is in that frame): that world's `rebase` calls
  `shift_statics(shift, self)` and moves only its own rows, once, by the nodes' shift; a row with no world never moves. Ids
  must be unique and not instance ids.
- **NaN radii.** A static whose surface distance is NaN (a NaN radius or position) is never an obstacle, on both paths.
- **Bad input never panics.** `set_statics` and the field's `set_kinds` check their array lengths, log one error and keep
  nothing; the scan then answers from GDScript, as for a rejected `load`.
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
  reference and the player's feel is untouched. Any ship can be taken out (`batched = false`), and when the library lacks the
  class or `perf_native` or `perf_native_flight` is off, the batch steps nothing and every ship flies its own model that same
  tick; the flip works live, and a bench pairs the two paths in one process by flipping `perf_native_flight` alone.
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
  array sizes and that every slot is known, and on a mismatch logs one error, applies nothing and returns false, so the batch
  leaves every ship to its own model that tick. A body not in a space (a parked pool ship) gives a row of zeros and no force.

### 17.10 Far-ship dots and the node diet for AI ships (T11)

History (M4-T31): the node diet below was measured on the M3 renderer. T31 removed its level nodes, their pose sync and the depth
proxy; a lean ship now draws its hull on one `Hull` node (11 nodes of its own besides its guns, was 16), and the far dot's colour is
the manifest's `mesh.mean_albedo` (M4-T30d). The far dot itself is unchanged.

```
src/ship/ship.gd                 `lean` (AI ships): no cockpit, anchor or fallback node; collision shapes as shape owners;
                                 `set_far_dot` hides the ship's visuals and hands it to the world's FarDots
src/ship/thruster_visuals.gd     `instanced`: every plume of a ship is an instance of one multimesh (cone and core in one surface)
src/ship/running_lights.gd       `instanced`: the three markers are instances of one multimesh (the colour in the custom data)
src/ship/hull_depth_proxy.gd     the proxy draws the fallback mesh merged into one surface; on a lean ship it also draws the
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
- **Settings.** `collision_layers` (default on; off puts every body on the one default layer: ships follow it live, capitals and
  rocks as they are built) and `far_ship_interpolation_off` (default on) are the switches for measuring either half alone.
- **Measured** (battle 300 and 500, Cycle log, M4-T14): the physics stage and the tick median are unchanged within noise; the
  rebase shift falls by 1.5 to 2 ms, a third, which is the far ships' interpolation alone.
- **Tests**: `test_collision_layers` (the table, the setting, two fighters meeting report a Jolt contact and exchange momentum,
  allied fighters collide, 30 m/s costs each at least half its hull once as a contact ram, 600 m/s takes the swept ram, a 4 m/s
  bump hurts nobody, the player bounces off a fighter, a capital and a rock pair with a fighter, a bolt and a mine have no body,
  the settle walks only the interpolated nodes, a far ship is left out of it and returns) and `test_fighter_melee` (a seeded melee
  of eight fighters, 2 966 contacts and 11 rams, whose digest equals the base's byte for byte).

### 17.13 The native core (T15)

```
native/src/sim_core.rs           ScsSimCore: one store of rows for every simulated entity, filled from the engine at the tick's
                                 sync points and read by every native kernel
native/src/rows.rs               Rows, Bolts and the row flags: the plain row tables, the only thing the kernels import from the crate
native/src/kernels.rs            the kernels: every query and step over the rows (contact, sweep, ram, flight), no way to the engine
native/src/ram_phase.rs          ScsRamPhase: the ram resolver's broad phase on the core's rows (RamBroadPhase stays the reference)
native/src/body_registry.rs      ScsBodyRegistry: the core without its facade, kept for the scan's registry path
src/perf/sim_core.gd             SimCore: the facade; a node under World at priority -11 (sync_in) with an internal child at
                                 2 000 000 (sync_out); the `core` console provider
src/ai/contact_scan.gd, src/combat/hit_broad_phase.gd, src/combat/hit_resolver.gd, src/combat/ram_resolver.gd,
src/ship/flight_batch.gd         the four classes read the core (their own loads stay behind `perf_native_core` off)
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
- **Parity is bit for bit** with each class's own load: the scan's rows equal `from_tree`'s (the registry's rule), the
  field reads the same values from the rows, the sweep and the ram phase build the same spheres and boxes from the rows
  in GDScript's precision and order (the hull rows in the `damageable` group's order, so ties fall the same way), the
  flight step reads the basis Jolt wrote back to the node after its last step, which is what the direct state holds too
  (`test_sim_core`, `test_fighter_melee`'s digest, the seeded outcome runs in the Cycle log). What differs: a ship
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
- **Settings and console.** `perf_native_core` (default on; off = each class loads its own copy, so a bench pairs the two
  in one process). Provider `core` (`path`, `rows`, `bodies`, `statics`, `bolts`, `syncs`, `sync_us`, `bolts_us`,
  `sync_calls`, `fallback_calls`, `attribute_reads`, `touched`); `combat.source` and `combat.gather_us`, `ram.source` and
  `ram.gather_us`, `flight.source` and `flight.fallback_reads` say what each class read.
- **Tests**: `test_sim_core` (the lifecycle, the rebase, the round trip, the four classes' parity, the engine seam) and the
  files of the four classes on both paths.

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
  that tick's remaining questions to the GDScript. In the game's tick order nothing changes the rows between -11 and the
  drivers' end. `ContactScan.pilot_kernels_on` (off only in tests) pairs the kernels alone against the GDScript with
  the core on.
- **The facades.** `AvoidanceMath.filter_seen(p, radius, v_des, exempt_id, seed)` (the driver), `FireLane.clear_seen(p,
  aim, range, target)` (the attack brain and the slash) and `AiContext.refresh` ask the kernels when the perception is on
  the rows, and otherwise list the contacts and run `filter`, `clear` or the loop as before. Off the core (`perf_native`
  or `perf_native_core` off, no library) nothing changes.
- **Bit for bit.** The kernels repeat the GDScript's arithmetic: 32-bit vectors, 64-bit scalars, a scalar rounded to 32
  bits before it scales a vector, division where the engine divides, the engine's `Basis(axis, angle)` for the tie's turn
  (`cosf` and `sinf`, as the engine calls them), and the tie angle in the engine's `deg_to_rad` form (`x * (PI / 180)`,
  checked bit for bit through `ScsPilotKernels.tie_angle`). The tie-break is passed in as `hash(seed)` from GDScript, so the kernel
  holds no hash of its own. `test_pilot_kernels` compares both on seeded contacts (ties on top of the ship and on a dead
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
  kernels read the core's rows and bolts. The GDScript stand-ins stay the reference behind `perf_native_weapons`
  (default on), and either path carries on from the other's state: switching hands the turrets' axes, targets, aim errors,
  gate times and counters, the strike targets and the launch turn over.
- **Who does what.** One `ScsWeaponRows.step` a tick decides, in the GDScript's order, which guns fire (with each bolt's
  start and velocity), which projectiles the interceptors shoot down, which beams fire at what, and which capitals launch
  at whom. The director then does it: it spawns the bolts, beams and missiles with the stand-ins' own code, spends the
  projectiles, and steps the capitals' engines and the carriers' launches as before. `MineStandin.step_native` asks
  `mine_step` for the mines set off and `blast` for each one's hulls, and still lays, retires and hurts. A missile's
  steering hook asks `steer_missile` for its velocity from its target's row. Every engine write stays in GDScript.
- **When the rows step.** Only when the core synced this physics frame and no body was touched since (a body hidden,
  shown or destroyed after the sync has a stale row): otherwise the director runs the GDScript for that tick. A missile
  whose target was touched, or with no core to read, steers in GDScript. In the game's tick order the director runs at -5,
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
  weighted scores by tie order, and twelve numbers of the behaviour in control's state. The GDScript brains stay the
  reference and fly whenever a perception is not on the rows (`perf_native_brains` off, no core, a pilot with a scripted or
  subclassed behaviour, a ship with no row this tick).
- **Bit for bit, with the seeds.** The maths repeats the GDScript op for op (32-bit vectors, 64-bit scalars, a scalar rounded
  to 32 bits before it scales a vector, the engine's `atan2`, `sin`, `cos`, `tan`, `acos`, `exp` through the same libm).
  The seeded rolls are Godot's own: `hash([seed, "label"])` is the Array hash (murmur3 over `hash_one_uint64` of the int and
  djb2 of the String, `hash_fmix32` at the end), and `RandomNumberGenerator` is PCG32 with the engine's increment, `randf`
  from `ldexp` of a draw whose top and bottom bits are set (the bottom bit breaks the u32-to-f32 rounding ties upward). The
  avoidance tie-break reaches the kernel as `hash(seed)`, as `AvoidanceMath.tie_direction` takes it. `test_brain_parity`
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
- **Console and settings.** `perf_native_brains` (default on; off = the GDScript brains, so a bench pairs the two in one
  process). Provider `ai` gains `thinks_native` (AI ships whose think ran natively in the last tick) and `thinks_fallback` (native pilots the host declined, each holding its last command); `ai <name>` reads a
  native pilot's `describe()` from its slot (the behaviour in control, its state and fields, the scores).


**Threads inside the core (T18, N3).**

```
native/src/threads.rs            Threads: the core's rayon pool (none for one thread), a threshold per pass, the per-item pass,
                                 the performance-core count; engine-free (std and rayon only), under test_sim_core's guard
native/src/sim_core.rs           the pool on the core (set_threads, threads, parallel_passes, the thresholds), rows_digest
native/src/brain.rs              ScsBrains.think_batch: every native think of a tick in one call, across the pool
native/src/flight_step.rs        ScsFlightStep: read on the main thread, the kernel on the pool, the forces applied in row order
src/perf/brain_batch.gd          BrainBatch: an internal child of SimCore at -9 that carries the drivers' native thinks
```

- **What runs in parallel.** Two passes. The brains: the drivers (-10) hand each native pilot's inputs to `BrainBatch`
  (its slot, its relation row, selection, latest attacker, dt, hull and hits), and at -9 one `think_batch` call thinks
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
  once. `test_sim_core`'s guard covers `threads.rs`.
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
- **What changed, each behind a setting that keeps the old path as the reference.** The bolt reader (`perf_native_bolt_sync`)
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
- **What a reader sees.** Everything the simulation decides is the same bit for bit (the tests below). One thing moved in
  time: the player's candidate list a window's HUD reads is now built at that read, after the tick, so its positions and
  hulls are a physics step fresher than the list the last refresh used to leave. In a window the HUD still builds it once a
  frame: the gain is the ticks a frame carries beyond the first, and all of it headless.
- **Tests.** `test_bolt_sync` (a seeded crowd of bolts, missiles and beams, spent, freed and new each round: the same bolt
  rows at both sync points; the engine calls counted alike), `test_ram_tracker_columns` (400 random ticks of two trackers
  side by side: the same rams field for field), `test_ram_contact_columns` (T14's melee both ways: the same rams and
  digest), `test_ram_sweep_cull` (6 000 seeded sweeps: the same hits at the same points, a fifth of the volumes placed),
  `test_targeting_on_read` (400 steps of moves, parks, frees and selection commands: the same selection, signals and lists
  read; no list built while nothing reads), `test_targetable_hull`, `test_sweep_cells` (twelve seeded mixes against the
  sorted grid and the GDScript reference; the guard holds the new kernel).

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
  rocks within half its move plus its bounding radius plus `RamBroadPhase.MARGIN_M`; each candidate goes through the same swept
  test as a prop (any touch rams), with a hull per rock made on first contact and kept (a sphere of the rock's radius,
  invulnerable, `SOLID_MASS_KG`), so the outcome is the old marker's: the ship takes the whole closing speed, the rock nothing.
  Jolt's own bounce off the RID body is unchanged (its contacts never named a rock: the RID body has no object id).
- **Why nothing changes for fighters.** Furball, spread and transit have no rocks and no mines, so the rows are empty, the kept
  grids answer nothing and every contact list is what it was; the seeded outcomes match the base with `perf_native` on and off.
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
src/perf/station_scene.gd              StationScene (under Main): the station, 10 capitals, 80 fighters, the planet; `station near|far|off`
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
