# Architecture

Design for `space-combat-sim`: a Newtonian 3D space-fighter sim in Godot 4, rendered primarily with 3D Gaussian
splats. This document is the contract between planning and implementation. Milestone scope and tasks live in
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
| Splat rendering | GDGS `addons/gdgs`, Compute backend | **v3.3.0** | MIT |
| World coordinates | Floating-origin `WorldFrame` + 64-bit script-side `UniversePos` (§14.1) | - | - |
| Language | GDScript, statically typed | - | - |
| Tests (engine) | GUT `addons/gut` | **v9.7.1** | MIT |
| Asset generators | `tools/procgen`, Python + NumPy (+ Pillow for the fallback sky only) | 3.11+ / 2.x | PSF / BSD |
| CI | GitHub Actions, `ubuntu-latest`, Godot downloaded from GitHub releases | - | - |

Version bumps are deliberate PRs that update this table, `scripts/setup_godot.sh`, `.github/workflows/ci.yml`
and `docs/third-party.md` together.

## 2. Key decisions

M2 decisions (D20-D29) are in §15.1.

| # | Decision | Rationale (short) |
|---|---|---|
| D1 | Godot 4.7.2 (latest stable at planning time) | User decision: Godot 4. 4.7.x has Jolt default, SDL3 gamepads, GDGS has an explicit 4.7 fix. |
| D2 | GDGS v3.3.0 for splats, **Compute** backend, Raster as automatic fallback | Only maintained addon with multiple movable nodes, depth compositing against scene depth, and headless-importable resources. Pure GDScript, MIT, no native builds. `gdgs/rendering/backend = Auto` already falls back to Raster when compute is unavailable. |
| D3 | **No splat training.** Splats are produced by sampling procedurally authored surfaces (mesh-to-splat) and by writing Gaussians directly for stars/nebula | Deterministic, CPU-only, seconds to run, reproducible in CI and in the GPU-less container. Training (Brush) stays an optional polish step on a GPU machine. |
| D4 | RigidBody3D + Jolt. Pod nozzle forces are applied **at their hardpoint positions** (`apply_force`); RCS as central force + torque; no custom integrator | Correct rigid-body dynamics (inertia, angular momentum); differential pod thrust yaws the ship through real r × F computed by the engine; free collision later. Verified headless. Custom integrator only if Jolt limits ever block us (§5.6). |
| D5 | Flight logic in pure `RefCounted` classes, nodes are thin adapters | Unit-testable without a scene tree, display or controller. |
| D6 | Flight assist in M1. **ON (default)**: rate-command fly-by-wire; the trigger/bumper difference is a smoothed **yaw command** added to the D-pad's, so pod steering works in both modes; pod torque helps the turn and is trimmed when RCS cannot hold the commanded rate; no pod ever exceeds its trigger. **OFF**: raw pods + raw RCS torque (tank-steer). **Brake** (hold) is an all stop (velocity and rotation) in both, and turns the nose onto the selected target | User decision: pod steering is the Starfury identity in both modes; assist makes it bounded and stop-on-release; one closed-form rule (§5.5). |
| D7 | User-chosen pad layout (§6.1): triggers = left/right main pods, bumpers = left/right retros, left stick = strafe, right stick = pitch / roll, D-pad = yaw + target/weapon cycling (Up: tap next, hold ahead). `InputMap` actions only, SDL3 standard layout, keyboard as extra events | Every DOF and combat function reachable without modifiers or stick clicks (generic pads may lack them); per-side pod control is the Starfury identity; rebindable, testable, works on a generic pad. |
| D8 | Hybrid rendering: splats for hulls, buoys and sky; meshes for cockpit interior, projectiles, flashes, thruster plumes, beacons, the hull depth proxy; primitives for collision | Splats are static radiance; anything animated per frame, emissive-dynamic, or needing depth writes is a mesh. Each exception is justified in §7. |
| D9 | Generated assets are **not committed**; generators are. No Git LFS | Everything binary is reproducible from `tools/procgen` in seconds; LFS adds quotas and fork friction. |
| D10 | GUT over gdUnit4 | Simpler headless CLI (`-gexit`, exit code 1 on failure), no xvfb caveats, GDScript-first, tracks Godot 4.7. |
| D11 | 1 unit = 1 metre, SI everywhere, Godot axes (+X right, +Y up, **-Z forward**) | Avoids conversion bugs; Godot's `Basis.z` is backward, so forward is `-basis.z`. |
| D12 | Vendor addons into `addons/` | Offline-reproducible builds; standard Godot practice; licences travel with the code. |
| D13 | Linux x86_64 + Vulkan is the only target; GDGS Compute is the acceptance backend | The maintainer builds this for their own Linux gaming desktop. No per-OS code is written, so Godot keeps other doors open, but nothing else is tested or promised. |
| D14 | Pod thrust = 8 discrete nozzle forces (4 main, 4 retro) at hardpoint positions; RCS = ideal per-axis force/torque actuator with limits | The asymmetry that matters is in the big pod nozzles; modelling every RCS jet adds allocation maths with no gameplay gain. |
| D15 | M1 has targeting and weapon modes but nothing shootable: `TargetingSystem` over inert splat **nav buoys**; `weapon_next` cycles pulse-cannon fire modes | Smallest behaviour that makes every bound button do something verifiable; spinning buoys exercise several independently moving splat nodes before enemies need them. |
| D16 | Stay on the official single-precision engine. Large worlds use a floating-origin, free-falling `WorldFrame` plus 64-bit universe coordinates in script | No official double builds exist; GDGS packs matrices as float32 anyway; Jolt's 500 m/s cap needs a moving frame regardless (§14.1). |
| D17 | Procedural assets only, via a reusable generator framework (`tools/procgen`): no hand modelling, no AI 3D generators | User decision. Reproducible, reviewable, licence-clean, LOD-able by construction (§14.8). |
| D18 | Gravity (and any later field: hyperspace currents) is an explicit environmental force; project gravity stays 0 | Keeps Jolt a local rigid-body solver; M1 already has the hook (`WorldFrame.environment_accel`), returning zero. |
| D19 | Always-on debug console on the physical ` key (§6.4): a pure command/state registry that subsystems extend by registering, whitelisted state providers (no reflection), keyboard masked while open, gamepad and sim time keep running, output mirrored to stdout, scriptable from the command line | Personal single-user project, so usefulness wins over gating; the registry keeps it testable and lets every later milestone add commands without touching the console; stdout and `--console-exec` let headless agents drive a live build. |

## 3. Project layout

```
project.godot                 Forward+, Jolt, zero default damping, physics interpolation on, InputMap actions
addons/gdgs/                  vendored GDGS v3.3.0 (MIT)
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
                              + target bracket, splat backend, FPS, GPU, pad name/GUID/raw axes, universe position
  ship/ship.tscn|.gd          RigidBody3D "PlayerShip" adapter: consumes FlightCommand + CombatCommand
  ship/ship_spec.gd           Resource: mass, inertia, pod/RCS limits, rates, gains, asset_id, exhaust velocity
  ship/thruster_layout.gd     RefCounted: pod main/retro nozzles + RCS nozzles relative to CoM, from hardpoints
  ship/flight_model.gd        RefCounted, pure: FlightCommand + state -> FlightOutput (§5.2)
  ship/flight_assist.gd       RefCounted, pure (stateful, deterministic): pod-yaw command smoothing, rate
                              controller, pod trim, brake allocation
  ship/flight_output.gd       RefCounted: per-nozzle forces, RCS force/torque, totals, trim, levels, mass flow
  ship/hardpoints.gd          RefCounted: loads assets/generated/starfury_aurora/hardpoints.json
  ship/thruster_visuals.gd    exhaust plumes (cone + core disc along each nozzle's exhaust axis) from FlightOutput levels
  ship/hull_depth_proxy.gd    MeshInstance3D: the fallback mesh inset along its normals, opaque black, depth only (§7.2)
  rendering/splat_pose_sync.gd Node: draws a splat node at its parent's physics-interpolated pose (§7.2)
  weapons/pulse_cannon_gate.gd RefCounted, pure: fire modes, rate gate, muzzle selection (fake-time testable)
  weapons/pulse_cannon.gd     node adapter: trigger state, spawns projectiles at muzzle hardpoints
  weapons/projectile.tscn|.gd kinematic projectile (inherits ship velocity), lifetime, emissive mesh
  targeting/target_info.gd    RefCounted: id, display_name, faction, position, velocity
  targeting/target_readout.gd RefCounted: range, closing speed, angle off boresight
  targeting/targeting_system.gd RefCounted, pure: next / ahead selection, readout
  targeting/targetable.gd     Node3D component: joins group "targetable", display_name, faction, velocity
  targeting/targeting_controller.gd  Node under the ship: gathers targetables, applies CombatCommand edges
  props/nav_buoy.tscn|.gd     inert target marker: splat body, beacon mesh, slow spin, optional drift
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
  environment/space_environment.tscn|.gd  WorldEnvironment (+Compositor with gdgs effect), key light, SkySplats
  environment/sky_follower.gd pins the sky splat node to the active camera position each frame
  rendering/splat_status.gd   reports active GDGS backend; enables fallback meshes if neither backend initialised
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
│   ├── WorldEnvironment                   Environment (black sky, no fog, tonemap filmic, glow on) + Compositor[gdgs effect]
│   ├── KeyStar (DirectionalLight3D)       lights meshes only; splats are pre-lit
│   └── SkySplats (GaussianSplatNode)      top_level = true; sky_follower.gd keeps origin == active camera origin
├── World (Node3D, world_frame.gd)         every world object lives under here (group "world_shiftable")
│   ├── PlayerShip (ship.tscn, RigidBody3D)    ship.gd
│   │   ├── CollisionShape3D x N           from hardpoints "collision" primitives (boxes/capsules)
│   │   ├── HullSplats (GaussianSplatNode) identity transform; gaussian = starfury_aurora.ply import
│   │   ├── HullSplatSync (Node)           splat_pose_sync.gd: HullSplats drawn at the interpolated pose
│   │   ├── HullMeshFallback (MeshInstance3D)  starfury_aurora.obj; visible only if splats unavailable or F4
│   │   ├── HullDepthProxy (MeshInstance3D)    same mesh, inset 4 cm, opaque black; visible exactly when the splats are
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
  `World.rebase()` at any tick (no cached world positions across ticks).
- Weapons and visuals read ship state through typed getters, never by reaching into sibling nodes.
- Rendering (splat vs mesh) is invisible to gameplay code: `Ship` exposes hardpoints; which node draws the hull is
  decided by `SplatStatus`.
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
| `pod_retro_thrust` | 0.18 MN per pod | 4 pods = 0.72 MN = 15 m/s² with both bumpers |
| `rcs_force_max` | (0.48 MN, 0.48 MN, 0) | sway / heave, 10 m/s²; no axial RCS: fore/aft is the pods' job |
| `rcs_torque_max` | (9.4e5, 9.4e5, 1.57e6) N·m | = inertia × (1.57, 1.57, 3.14) rad/s² |
| `rate_max` | (60, 60, 90) deg/s | assist target at full deflection |
| `assist_gain_k` | 6.0 s⁻¹ | rate controller P gain |
| `pod_yaw_gain` | 0.5 | assist on: full one-sided trigger = 0.5 × `rate_max.y` = 30 °/s yaw |
| `pod_yaw_deadzone` | 0.10 | assist on: trigger differences below 10 % fly straight |
| `pod_yaw_smoothing_s` | 0.15 s | assist on: first-order smoothing of the pod-yaw command |
| `brake_gain_k` | 2.0 s⁻¹ | translational brake P gain |
| `exhaust_velocity` | 30 000 m/s | only for the reaction-mass seam: `mass_flow = Σ thrust / v_e`, unlimited in M1 |

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
mass_flow = (Σ |F_i| + |rcs_force|) / exhaust_velocity     # reaction-mass seam, not consumed in M1
```

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
| D-pad right + LT | (raw torque + pod yaw) | D-pad and pod yaw add, capped at `rate_max`; left-pod torque speeds the turn-in |
| Right stick back / right | nose up / roll right (torque) | nose up / roll right (rate); stops when centred |
| D-pad right | yaw right (torque, ramped) | yaw right (rate, ramped) |
| Left stick right / up | translate right / up; nose does not turn | same |
| Release everything (or even out the triggers) | velocity unchanged; spin unchanged | velocity unchanged; rotation stops |
| X held | all stop: velocity → 0 with symmetric pods + RCS, rotation → 0; sticks, D-pad, triggers ignored | same |
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
  angular *rates*. Pitch and roll come from the right stick, and yaw from the D-pad (ramped) **plus the pod-yaw
  command**: the left/right difference of the triggers (and of the bumpers), with a 10 % deadzone, smoothed over
  0.15 s, scaled by `pod_yaw_gain` (one full trigger = 30 °/s) and capped together with the D-pad at `rate_max`.
  Stick and D-pad centred and sides even means "stop rotating". The flight computer knows the pods' torque
  exactly (from hardpoints) and treats it as feed-forward: it lets pod torque drive the turn-in, cancels the
  excess with RCS once the commanded rate is reached, and trims (only ever reduces) the side causing it when RCS
  authority is not enough. The pilot's trigger and bumper levels are a ceiling, never exceeded. Translation is
  untouched except by that trim and by the brake.
- **Assist OFF**: raw Newtonian. Pods fire exactly as demanded and their r × F torque acts in full, so uneven
  triggers tank-steer the ship. Stick and D-pad command raw RCS torque. Nothing damps rotation. This is the
  flip-and-burn mode.
- **Brake** (hold X), both modes: **all stop**. The flight computer takes over translation and rotation.
  Translation: pods fire symmetrically (no torque) plus RCS sway/heave, nulling velocity relative to the `World`
  frame (later: relative to a chosen reference such as the station). Rotation: the rate target is zero and the P
  rate controller (gain `assist_gain_k`, RCS only, pods symmetric so nothing to trim) nulls any spin, with assist
  off too. Triggers, bumpers, both sticks and the D-pad are ignored while held. Measured in Jolt (both modes): a
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
  removes jerk from noisy analog triggers. (3) Gain 0.5 keeps one trigger below the D-pad yaw's authority while
  trigger plus D-pad still reach full rate. (4) The "never above the trigger" rule still holds: the commanded yaw
  points the same way as the pods' own torque, so the flight computer only ever needs to cancel or trim, never to
  add thrust; the pilot's throttle stays a ceiling. (5) One closed-form rule plus one first-order filter:
  deterministic, unit-testable, and identical for AI pilots, which write the same `FlightCommand`. All three
  tunables live in `ShipSpec`.
- Rate controller: pure P with clamp. A 60 °/s stop takes ≈ 0.9 s (simulated). Add D only if human testing shows
  oscillation.

### 5.6 Limits and later work

- Jolt clamps body speed: `physics/jolt_physics_3d/limits/max_linear_velocity` (default 500 m/s, adjustable) and
  `max_angular_velocity` (default 2700 °/s). M1 speeds stay under 200 m/s. Orbital speeds (km/s) are handled by
  the moving `WorldFrame` (§14.1), not by raising the limit.
- If Jolt ever becomes the obstacle, the fallback is a custom integrator driving a `Node3D`; the pure-class split
  (D5) keeps that contained.

## 6. Input and the debug console

### 6.1 Gamepad mapping (user-chosen layout)

```
RT  right main pods (analog)      LT  left main pods (analog)
RB  right retros (hold)           LB  left retros (hold)
R-stick  pitch / roll (aim)       L-stick  strafe L/R + up/down
D-pad L/R  yaw (ramped)           D-pad Down  next weapon
D-pad Up  tap: next target        hold (0.35 s): target nearest the nose
A  fire       B  flight assist    X  brake (hold): all stop; faces the target if one is selected
Y  camera 1st/3rd
R3  target ahead (if the pad has it)    L3  debug overlay (if the pad has it; F3 too)
Back  reset                       Start  pause
```

Revised after the M1 play test on the maintainer's generic pad: yaw and roll swapped places (right stick X was
yaw, the D-pad was roll), and because that pad has no stick clicks, `target_ahead` moved onto a D-pad Up hold
(R3 still works where it exists). Saved, selectable control profiles are on the roadmap.

All via `InputMap` actions in `project.godot`; `device = -1` (any pad). Names are the Xbox-style names Godot/SDL3
use for the standard layout; any pad SDL3 recognises, generic XInput clones included, presents it.

| Action | Pad (Godot enum, index) | Keyboard | Type | Deadzone | Curve |
|---|---|---|---|---|---|
| `main_right` | RT `JOY_AXIS_TRIGGER_RIGHT` (axis 5, +) | E, W | analog 0..1 via `get_trigger` | 0.05 | linear |
| `main_left` | LT `JOY_AXIS_TRIGGER_LEFT` (axis 4, +) | Q, W | analog 0..1 via `get_trigger` | 0.05 | linear |
| `retro_right` | RB `JOY_BUTTON_RIGHT_SHOULDER` (10) | D, S | hold | - | - |
| `retro_left` | LB `JOY_BUTTON_LEFT_SHOULDER` (9) | A, S | hold | - | - |
| `pitch_down` / `pitch_up` | Right stick Y `JOY_AXIS_RIGHT_Y` (axis 3, -/+): stick back = nose up; `Settings.invert_y` flips | I / K | analog pair | radial 0.15 | expo 1.5 |
| `roll_left` / `roll_right` | Right stick X `JOY_AXIS_RIGHT_X` (axis 2, -/+): stick right = roll right | U / O | analog pair | radial 0.15 (one deadzone with pitch) | expo 1.5 |
| `strafe_left` / `strafe_right` | Left stick X `JOY_AXIS_LEFT_X` (axis 0, -/+) | Left / Right arrows | analog pair | radial 0.15 | linear |
| `strafe_down` / `strafe_up` | Left stick Y `JOY_AXIS_LEFT_Y` (axis 1, +/-) | Down / Up arrows | analog pair | radial 0.15 | linear |
| `yaw_left` / `yaw_right` | D-pad `JOY_BUTTON_DPAD_LEFT` / `DPAD_RIGHT` (13 / 14) | J / L | hold, ramped | - | 0→1 in 0.25 s |
| `target_next` | D-pad `JOY_BUTTON_DPAD_UP` (11) | T | tap or hold: a tap gives `target_next` on release; a hold of 0.35 s gives `target_ahead` once | - | - |
| `weapon_next` | D-pad `JOY_BUTTON_DPAD_DOWN` (12) | F | edge | - | - |
| `target_ahead` | R3 `JOY_BUTTON_RIGHT_STICK` (8) | G | edge | - | - |
| `fire` | A `JOY_BUTTON_A` (0) | Space, left mouse | hold | - | - |
| `toggle_flight_assist` | B `JOY_BUTTON_B` (1) | Z | edge | - | - |
| `brake` | X `JOY_BUTTON_X` (2) | X | hold | - | - |
| `toggle_camera` | Y `JOY_BUTTON_Y` (3) | V | edge | - | - |
| `reset_ship` | Back `JOY_BUTTON_BACK` (4) | Backspace | edge | - | - |
| `pause` | Start `JOY_BUTTON_START` (6) | Esc | edge | - | - |
| `debug_toggle_overlay` | L3 `JOY_BUTTON_LEFT_STICK` (7) | F3 | edge (toggles `settings.show_overlay`) | - | - |
| `debug_toggle_fallback_mesh` | none (debug, keyboard only) | F4 | edge | - | - |
| *(console toggle, not an action)* | none | ` (physical `KEY_QUOTELEFT`, 96) | handled in `DebugConsole._input` | - | - |

Notes:
- Only axes 0-5 and buttons 0-14 are used. Guide (5) and SDL extras (paddles, misc, touchpad, ≥ 15) are not.
  No rumble, no impulse triggers, no light bar, no motion sensors.
- W and S are "both sides" keys: the same key is an event on two actions.
- The ` key belongs to the console alone: it is not an `InputMap` action and must never be bound to one (a test
  enforces it). While the console is open, Esc closes it instead of pausing (keyboard gameplay bindings are
  masked, §6.4).
- `GodotInputSource` evaluates every action itself from its `InputMap` events by polling devices
  (`Input.get_joy_axis`, `is_joy_button_pressed`, `is_physical_key_pressed`, `is_mouse_button_pressed`), never via
  `Input.is_action_pressed`. That is what lets it mask keyboard and mouse per device class while the console is
  open: `Input` action state would still report keys typed into the prompt.
- Tap or hold on D-pad Up (in `InputAdapter`, so it works for T too): a press released before
  `Settings.target_hold_s` (default 0.35 s, counted in physics ticks) gives `target_next` on the release tick; a
  press still held when it crosses the threshold gives `target_ahead` once, on that tick, and its release gives
  nothing, so a hold never also cycles. A tap therefore acts on release, which costs nothing when cycling targets.
  A console open/close (`resync_edges`) or `reset()` drops a press in progress. Many generic pads have no stick
  clicks (the maintainer's has neither R3 nor L3), so nothing needed to fly sits on them: R3 keeps `target_ahead`
  where it exists, and L3's overlay toggle is also F3.
- `target_ahead` samples the boresight when it fires, so the small stick jolt of an R3 click does not matter.
- Yaw ramp: while a yaw action is held, `rot.y` moves toward ±1 at `1 / Settings.yaw_ramp_s` per second
  (default 0.25 s to full); release snaps to 0; reversing direction restarts from 0. Taps give fine corrections
  from a digital D-pad. Analog yaw stays available through pod steering (the triggers, §5.5). The setting was
  `roll_ramp_s` before the swap; `Settings` reads that key from an old file (`SettingsSchema.RENAMED`) and the next
  `save` writes the new name.
- Sticks: `Input.get_vector(neg_x, pos_x, neg_y, pos_y, Settings.stick_deadzone)` (radial deadzone with
  rescaling), then `sign(x)·|x|^1.5` on pitch and roll in `InputAdapter`. The right stick is one vector (x roll,
  y pitch), so pitch and roll share the radial deadzone. The keyboard's U/O give full roll at once (no ramp, like
  any stick key); J/L ramp like the D-pad.

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
var target_next: bool   # edge (D-pad Up tap, on release)
var target_ahead: bool  # edge (R3 press, or D-pad Up held for target_hold_s)

class_name UiCommand extends RefCounted       # player-only
var toggle_camera: bool # edges, all of them
var reset: bool
var pause: bool
var toggle_overlay: bool
var toggle_fallback_mesh: bool

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
  `velocity`), sensor range 25 km.
  - `select_next(ship_pos)`: candidates in range sorted by range; picks the one after the current, wrapping to
    the nearest; with no selection, the nearest.
  - `select_ahead(ship_pos, forward)`: smallest angle between `forward` and the direction to the target, forward
    hemisphere only (< 90°), ties to the nearer; if none, the selection is unchanged.
  - `readout(ship_pos, ship_vel) -> TargetReadout`: `range_m`, `closing_mps = -(v_t - v_s)·(p_t - p_s) / range`
    (positive = closing), `angle_off_deg`. The selection clears when the target leaves the list or sensor range.
- **TargetingController** (node under the ship) gathers group `targetable` each physics tick, feeds the system,
  applies `CombatCommand` edges, emits `target_changed(id)`. `selected_offset()` is the live World-frame line of
  sight to the selection (zero without one); the Ship turns it into `FlightCommand.face_dir_b` every tick.
- **NavBuoy**: inert marker with a splat body (one shared `GaussianResource`, GDGS instancing), a blinking beacon
  mesh, a 10 °/s spin about its long axis, optional constant drift. No collision; cannot be shot. Five are spawned
  from `data/scenarios/free_flight.json` at 0.5-5 km; faction `neutral`.
- **Pulse cannon modes** (`PulseCannonGate`, pure): `ALTERNATING` (4 Hz, muzzles alternate) and `LINKED`
  (2 Hz, both muzzles together). `weapon_next` cycles and wraps; the cooldown carries over, so switching cannot
  raise the rate of fire.

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
| `ship` | Ship (T10) | `position`, `universe_position`, `velocity`, `speed`, `body_velocity`, `angular_rate_dps`, `assist_on` (w), `trim`, `pod_yaw`, `main_levels`, `retro_levels`, `mass_flow` |
| `world` | WorldFrame (T09) | `origin`, `origin_velocity`, `auto_rebase_distance_m` |
| `camera` | CameraRig (T12) | `mode` (w), `fov` |
| `weapons` | PulseCannon (T13) | `mode` (w), `cooldown_s` |
| `targeting` | TargetingController (T14) | `selected` (w: display name or `none`), `range_m`, `closing_mps`, `candidates` |
| `render` | SplatStatus (T10) | `splat_backend` (`compute`, `raster`, `headless` or `none`), `fallback` (w), `fps`, `gpu` |

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
| `timescale <0.05..1>` | console | debug slow motion via `Engine.time_scale`, which scales physics delta and therefore `SimClock`. Capped at 1 in M1; real warp is `SimClock`'s job (M8 adds a `warp` command) |
| `exec <file>` | console | run commands from a `res://` or `user://` file |
| `wait <frames>` | console | delay the rest of the queue by N physics frames (scripts, headless runs) |
| `quit [code]` | console | quit with an exit code |
| `assist [on\|off]` | Ship | flight assist |
| `camera [cockpit\|chase]` | CameraRig | set, or toggle with no argument |
| `fallback [on\|off]` | SplatStatus | fallback meshes and panorama sky |
| `respawn` | Main | ship reset (same as Back) |
| `pause [on\|off]` | Main | tree pause (same as Start) |
| `rebase <dx> <dy> <dz>` | WorldFrame | manual `World.rebase()`: the only way to exercise the seam at runtime in M1 |

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
| `yaw_ramp_s` (was `roll_ramp_s`) | float | 0.25 | 0.05-1.0 |
| `target_hold_s` | float | 0.35 | 0.15-1.0 |
| `assist_default` | bool | true | |
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

### 7.1 What is a splat, what is a mesh

| Element | Representation | Why |
|---|---|---|
| Ship hull (fuselage, struts, pods, canopy exterior) | **Splats** (`HullSplats`, ~150k Gaussians) | The point of the project; GDGS re-uploads a node's transform on change, so a moving, rotating body works. |
| Nav buoy bodies | **Splats** (~8k each, one shared resource, 5 instances, spinning) | Exercises several independently moving splat nodes before enemies need them. |
| Stars | **Splats** (in `SkySplats`, ~12k tiny Gaussians) | A Gaussian is the ideal star PSF; brightness/colour per splat; crisp at any resolution unlike a panorama texture. |
| Nebula | **Splats** (in `SkySplats`, ~4k large soft Gaussians) | Volumetric look for free; per-tile depth sort handles overlapping translucency. |
| Cockpit interior (frame, canopy struts, dash slab) | Mesh (`cockpit_interior.obj`) | Needs hard edges at the near plane and **depth writes** so hull splats behind the frame are rejected by the compositor's depth test; visible only in first person. |
| Thruster plumes, buoy beacons | Meshes, unshaded emissive, additive, animated per frame. A plume is a cone from the nozzle position along its `exhaust` axis (length, radius, alpha follow the level) plus a small core disc at the exit; no billboards | Per-frame intensity animation; splats are static radiance (no per-splat opacity animation in GDGS). Tied to the nozzle axis, so the plume reads as coming out of the nozzle from every camera. |
| Hull depth proxy (ship, buoys) | Mesh (`HullDepthProxy`): the fallback mesh, opaque black, vertices inset ~4 cm along their normals | Splats write no depth (§7.2). The proxy writes it just inside the splat surface, so effects behind a hull are hidden and the splats are never covered. Shown exactly when the splats are shown. |
| Projectiles, muzzle flash | Meshes, unshaded emissive | Tiny, fast-moving, short-lived; spawning/destroying splat nodes per shot would churn GPU buffers. |
| Target bracket | 2D `Control` in the debug overlay | Screen-space UI. |
| Collision | `CollisionShape3D` primitives from hardpoints JSON | Splats have no surface; GDGS's collision generator is editor-only and overkill for a handful of boxes. |
| Hull / buoy fallback | Meshes (`.obj`, hidden) | Debug comparison and the fallback path (§7.4). |

### 7.2 Compositing order (GDGS Compute backend)

1. Godot renders opaque meshes (cockpit interior, fallback meshes if visible) -> colour + depth.
2. GDGS `CompositorEffect` runs at `EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT`: projects all `GaussianSplatNode`s
   (hull, buoys, sky) in one pass, radix-sorts `(tile | depth)` keys, blends front-to-back, depth-tests against
   the resolved scene depth (`depth_bias`, `depth_test_min_alpha`, `alpha_cutoff` are tunables on the effect).
3. Godot renders transparent meshes (thruster plumes, beacons, projectiles, flashes) on top. Correct for additive
   effects even when the emitter sits inside hull splats. **But splats write no depth**, so a transparent mesh
   *behind* the hull would draw over it ("firing glow visible through the ship"). The **hull depth proxy** fixes
   that: `HullDepthProxy` draws the fallback mesh in step 1 (opaque, unshaded, black, `cull_back`;
   `assets/shaders/hull_depth_proxy.gdshader`) with every vertex moved `inset_m` (exported uniform, default 0.04 m)
   against its normal. It writes depth just inside the splat surface: effects behind the hull fail the depth test,
   and the splats (centred on the true surface, so nearer than the proxy) still pass step 2's depth test and
   cover it. Ship and `NavBuoy` have one; it is visible exactly when the splats are (hidden while the fallback mesh
   shows, `SplatStatus`) and reuses whatever fallback mesh is loaded, so a regenerated hull needs no change.
   Back-face culling makes it invisible from inside the hull (cockpit camera).
4. Post: glow/bloom, tonemap. Keep glow modest so star splats do not bloom into blobs.

**Splat pose.** GDGS's Compute backend reads a splat node's plain `global_transform`, i.e. the pose of the last
physics tick, while meshes, the proxy, the plumes and the chase camera use the physics-interpolated pose. At speed
that is metres of relative judder (150 m/s: 2.5 m per tick). `SplatPoseSync` (a child of the body, for the hull and the
buoys) therefore sets the splat node to `body.get_global_transform_interpolated() * local` every frame and turns that
node's own physics interpolation off; the Raster backend's quads are children of the splat node and follow.

The sky node sits far away (radius 20 km) and follows the camera origin each frame (`SkyFollower`,
`top_level = true`), so it never parallaxes and never collides with the depth of nearby meshes. Because GDGS
re-centres every PLY on its mean and the sky's mean is not its sphere centre (the nebula is one-sided), the node
sits at `camera + centroid_offset` from the sky manifest, which puts the sphere centre on the camera. Camera `near =
0.05 m` (cockpit), `far = 50 000 m`; Forward+ uses reverse-Z, so this range is fine.

Raster backend differences (automatic fallback on GPUs without compute): splats become sorted
`MultiMeshInstance3D` quads in the normal transparent pass with hardware depth test; sort can lag 1-2 frames
(mild popping on fast rolls). Acceptable; nothing in gameplay depends on the backend.

### 7.3 Lighting

Splats are unlit: the generators bake a "studio" light rig **in asset-local space** (hemisphere ambient + two
directional lights) into the DC colour, so shading rotates with the object. Meshes are lit by `KeyStar`
(`DirectionalLight3D`) plus a dark ambient. To avoid a visible mismatch, M1 mesh materials are either unshaded
emissive (glow, beacons, projectiles) or dim neutral (cockpit interior). GDGS relighting (bakes a lighting proxy
in the editor, lights splats from scene `Light3D`s) is the later option for consistent lighting from a real sun.

### 7.4 Risks and fallback plan

| Risk | Likelihood | Mitigation / fallback |
|---|---|---|
| GDGS compute backend fails on the tester's GPU/driver | low-med | `gdgs/rendering/backend = Auto` falls back to Raster. `SplatStatus` shows the active backend in the overlay. |
| Neither backend initialises, or splats look wrong (orientation, centring) | low | `SplatStatus` shows the fallback meshes and swaps `Environment.sky` to the generated panorama (`PanoramaSkyMaterial`). The game is fully playable on meshes. |
| Hull splat quality from surface sampling looks "dotty" at close range (cockpit view of the nose) | medium | Tune splat spacing/overlap (k≈1.4) and add a denser sampling pass near the cockpit; if still poor, train with Brush on a GPU machine from renders of the fallback mesh. |
| Sorting/perf with sky + hull + buoys in one pass | low | M1 total ≈ 210k splats (150k hull + 16k sky + 5 × 8k buoys) against a 400k budget; GDGS showcases 6M. |
| GDGS breaking change on a Godot bump | low | Versions pinned; CI runs `--import` + resource assertions headless. |
| Splat path blocks M1 entirely | low | Acceptance criteria are written so that mesh fallback + panorama still satisfies "flyable ship in a starry background with nebula"; M1 is then marked "splats pending" and the splat work moves to M1.5. |

## 8. Camera

- **Cockpit**: `Camera3D` glued to `CockpitAnchor` (hardpoint) via `RemoteTransform3D`; FOV 75°. The hull splats
  of the nose and struts are visible, as in the real Starfury. Cockpit interior mesh visible.
- **Chase**: `top_level` camera, **rigidly attached to the ship**. Every rendered frame `CameraRig._process` sets
  its transform to the ship's *physics-interpolated* global transform (`get_global_transform_interpolated()`) times
  one fixed ship-space pose from `ChaseCameraMath.local_pose`: position `Vector3(0, 2.5, 9.0)` (behind and above),
  looking at the point 40 m ahead of the ship's origin along its nose, up = ship up. There is no easing and no
  velocity input: reverse thrust, yaw and roll cannot move the camera relative to the ship (tested to 1e-4 in every
  frame), and the camera follows *orientation*, so sideways drift and pod tank-steering are visible in the world,
  not as camera motion. A velocity-vector marker is a later HUD item. The camera node has physics interpolation
  off (it is already placed from the interpolated pose) and joins `world_shiftable`.
  Optional lag: setting `camera_chase_smoothing_s` (0..0.5 s, default **0** = exactly rigid) lags only the
  *orientation* of the camera frame behind the ship's with that time constant (first-order, frame-rate
  independent, slerp); the position stays `ship origin + frame * offset`, so the distance to the ship never changes.
- Modes are an enum (`COCKPIT`, `CHASE`; `CINEMATIC` and `FREE_LOOK` later). Toggle via `toggle_camera`;
  `Settings.camera_default`. `CockpitInterior.visible == (mode == COCKPIT)`.
- Camera near/far as in §7.2. Physics interpolation on, so the chase camera's `_process` reads interpolated
  transforms (the hull splats are drawn at the same pose, §7.2 *Splat pose*). The chase camera is in group
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
  core/            ply.py (3DGS PLY writer + reader), frames.py (Godot <-> 3DGS), geometry.py (tessellation),
                   sampling.py (surface -> splats), lighting.py (baked studio rig), color.py (blackbody, palettes),
                   obj.py (OBJ/MTL writer), manifest.py, context.py (BuildContext: seed, out_dir, options)
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
{"asset_id": "starfury_aurora", "generator_version": 1, "seed": 42, "frame": "godot", "units": "m",
 "lods": [{"level": 0, "file": "starfury_aurora.ply", "splats": 152340, "spacing_m": 0.06}],
 "aabb_min": [-5.1, -3.9, -5.3], "aabb_max": [5.1, 3.9, 4.8], "centroid_offset": [0.0, 0.1, 0.6],
 "files": {"fallback_mesh": "starfury_aurora.obj", "cockpit_mesh": "cockpit_interior.obj",
           "hardpoints": "hardpoints.json"}}
```

M1 emits LOD 0 only; the `lods` array is the seam for the LOD chain (§14.4). AABBs are in the Godot frame.

### 9.1 `starfury_aurora`

1. Parametric description in the Godot frame, metres, built from `parts/` with the `earthforce` style: central
   fuselage (tapered box + cockpit canopy), four struts in an X, four engine pods (cylinders with rear main
   nozzle, forward retro nozzle and small RCS nozzles), two underslung gun barrels.
2. Outputs:
   - `starfury_aurora.obj` + `.mtl` (fallback mesh; also a future multi-view render source).
   - `starfury_aurora.ply`: area-weighted stratified surface sampling at spacing `s` (default 0.06 m -> ~150k
     points); per point: normal, tangent frame -> quaternion; scales `(k·s, k·s, 0.03·s)` with `k = 1.4`;
     colour = albedo × baked local lighting; opacity 0.98 (stored as logit); SH degree 0 only (`f_dc_*`).
   - `cockpit_interior.obj`: frame ring, canopy struts, dash slab; interior-facing normals.
   - `hardpoints.json`: `center_of_mass`, `cockpit_camera`, `chase_anchor`, `muzzles[]`, `pods[]` (side, main and
     retro nozzle position + exhaust direction), `rcs[]` (cosmetic nozzle positions with effect tags for glow),
     `collision[]` (boxes/capsules). Schema in the M1 task T04.
   - Re-centre **everything** (splats, meshes, hardpoints) on the splat centroid, so GDGS's unconditional import
     centring is a no-op and the hardpoints frame equals the rendered frame.
   - Write PLY in GDGS/3DGS orientation (apply Rz(180°): negate x, y; rotate quaternions) so the
     `GaussianSplatNode` can stay at identity (GDGS applies its own Rz(180°) correction to identity nodes).
3. PLY layout (`core/ply.py`): standard 3DGS binary little-endian, properties
   `x y z nx ny nz f_dc_0 f_dc_1 f_dc_2 opacity scale_0 scale_1 scale_2 rot_0 rot_1 rot_2 rot_3` with
   `rot_* = (w, x, y, z)`, `scale_* = ln(scale)`, `opacity = logit(alpha)`, `f_dc = (rgb - 0.5) / 0.28209479`.

### 9.2 `sky_default`

- Stars: N≈12 000 on a sphere of radius R=20 000 m; magnitude distribution ~ `10^(0.5·m)` with a Milky-Way band
  density boost; colour from a blackbody temperature table; size so that bright stars ≈ 2-3 px at 1080p/75° FOV
  (angular radius ≈ 0.6 mrad -> 12 m at R), dim stars smaller; isotropic Gaussians; opacity 1.0.
- Nebula: N≈4 000 large (300-2 000 m) soft Gaussians clustered by a few fBm-weighted blobs in one sky region
  (~40° across), two-tone palette (e.g. teal/magenta), opacity 0.02-0.08, slight anisotropy for filaments.
- `sky_default.ply` + `sky_default_panorama.png` (4096×2048 equirectangular render of the same catalogue, fallback
  only, needs Pillow) + manifest. Same PLY writer and orientation convention.

### 9.3 `nav_buoy`

- ~4 m tall body: cylinder hull, two small panel wings, antenna mast; `earthforce` palette with a hazard stripe;
  spacing 0.04 m -> 5k-15k splats. Outputs `nav_buoy.ply`, `nav_buoy.obj`, `hardpoints.json` (`beacon`
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
and is tested, but automatic rebasing is off (threshold 0 = disabled) because the M1 play area does not need it.
The full large-world design is §14.1.

## 11. Performance targets (M1)

- 1920×1080, 60 fps sustained on the tester's Linux desktop (discrete Vulkan GPU); floor: GTX 1060 / RX 580 class,
  with ≤ 400k splats on screen.
- Physics 60 Hz fixed; `_physics_process` for the ship < 0.2 ms.
- Input-to-thrust latency: one physics tick after the input event.
- Startup to flyable < 5 s after import (first import of the PLYs may take longer; that is a one-time cost).

## 12. Testing strategy

| Level | Tool | Runs where | Covers |
|---|---|---|---|
| Python unit | `unittest` | container, CI | PLY header/field layout, counts, determinism (hash of output), frame conversion, hardpoints schema (pods, nozzles, CoM), centroid ≈ 0, manifest `lods`, CLI registry |
| GDScript unit | GUT `tests/unit` | container, CI | `FlightModel` (pod forces at positions, r × F signs per §5.2 table, zero pitch/roll from pods, trim maths, brake symmetry, clamps, mass flow), `FlightAssist` (pod-yaw sign, deadzone, frame-rate-independent smoothing, cap at `rate_max`, converges, never exceeds limits or triggers), `InputAdapter` (radial deadzone, expo, roll ramp, edges, invert-Y, command split), `TriggerCalibration` (rest 0 and -1), `ChaseCameraMath` (frame-rate independence), `PulseCannonGate` (modes, rates, cycling), `TargetingSystem` (next, ahead, readout), `UniversePos` (64-bit precision at 1e11 m), console (tokenizer, typed args and errors, help, history, completion, provider whitelist, owner pruning), `SettingsSchema` (types, ranges, session vs save) |
| Headless integration | GUT `tests/integration`, `--headless` | container, CI | ship scene instantiates; damping guard; pod-differential yaw measured in Jolt matches the model; assist turns at the pod-yaw rate under one trigger, stops on release, and flies straight inside the deadzone; brake; projectile velocity/lifetime; all PLYs import with manifest counts; `World.rebase` keeps velocities and relative positions; scenario spawns buoys; targeting with live buoys; `SkyFollower`; camera toggle; console masks keyboard but not pad, and every subsystem's provider answers `state`; `main.tscn` runs 180 frames without script errors; a `--console-exec` run prints the expected `[console]` lines and exits with the requested code |
| Human acceptance | checklist in the milestone doc | Linux/Vulkan GPU + generic XInput pad | splat appearance, compositing, feel, performance, controller behaviour, trigger/deadzone calibration, targeting |

Rules: every pure class gets unit tests in the same PR; every scene gets at least an instantiate-and-run test;
anything that depends on a GPU is marked `(H)` in acceptance criteria and is never faked in CI.

Commands (also in `scripts/run_tests.sh`):

```
python3 -m unittest discover -s tools/procgen/tests -t . -v
.tools/godot/godot --headless --path . --import
.tools/godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=reports/gut.xml
.tools/godot/godot --headless --path . -- --console-strict --console-exec="wait 30; state ship; get render.splat_backend; quit"
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
- **GDGS would not benefit**: its compute registry packs each node's model matrix and the camera view matrix into
  `PackedFloat32Array` separately, so world-space splat positions lose precision at large coordinates in any
  build unless GDGS is patched to camera-relative matrices.
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
  by `-offset` (`global_position`, then `reset_physics_interpolation()`); `origin += offset`.
- **Velocity rebase** when the focus speed relative to the frame exceeds 200 m/s: subtract `v` from every body's
  `linear_velocity` and projectile velocity; `origin_velocity += v`. Keeps Jolt well under its cap and keeps
  float32 velocities small.
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

GDGS facts (v3.3.0 source): no LOD support (open upstream proposal, issue #32); changing a node's `gaussian`
re-merges and re-uploads **every** node's splat buffer; hidden nodes still cost one read per splat in the
projection pass (early-out on the visibility flag); visibility is a flag in the per-node transform upload (cheap).

Decisions:
- Every asset ships a generated **LOD chain** (manifest `lods`): LOD0 full; LOD1 ~25 % of splats with ~2× scales;
  LOD2 ~6 %; LOD3 a "blur" of a few hundred large soft splats (this is the user's model blurring); beyond that a
  single splat or point sprite sized by angular size with a 1-px floor, so ships stay visible as dots.
- A `LodSwitcher` per object picks a level from projected size in pixels with hysteresis. Levels are pre-loaded
  sibling `GaussianSplatNode`s toggled by **visibility**, never by swapping resources.
- A resident splat budget (start at ~3-4 M) is managed per region: objects beyond the near field are not resident
  at all, only their far representation. LOD and paging go upstream to GDGS as PRs rather than a fork.
- **Scaled space** for the sun, Epsilon III, moons and anything beyond ~50 km: a separate render layer drawn
  before the near world, placed at `camera_dir × (distance / scale)` with matching angular size, lit from the true
  sun direction. Planets and the sun are procedural-shader meshes (sphere + atmosphere scattering + generated
  textures): a justified non-splat choice, because they are huge smooth bodies needing day/night lighting and
  limb effects. Splats are used for their near-field features (cloud layers, rings, belts) where they look better.
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
volumetric splats and a shader backdrop. Combat in hyperspace reuses everything.

### 14.6 Scenes and the mission framework

- `Game` autoload state machine: `FrontEnd -> Loading -> InSpace(scenario) -> Debrief`. The front end is UI over a
  generated Babylon 5 interior splat scene (slow camera); mission select or free flight (encounters on/off).
- **Scenario** = data (`data/scenarios/*.json`: spawns in `UniversePos`, actors, factions, start state such as
  "in launch bay 3") + an optional **mission script** in GDScript with a small coroutine API: `await say(speaker,
  text)`, `await until(condition)`, `spawn(...)`, `objective_add/complete(...)`, `waypoint(...)`,
  `cinematic(path)`, `lock_controls(bool)`, `await player_did("roll_right")` (tutorial checks per DOF).
- **Triggers**: proximity/area, timer, target destroyed/disabled, dialog finished, input performed, actor
  arrived. **Objectives** with success/fail states feed the debrief.
- **Launch bays**: station hardpoints with a launch rail; the launch is a scripted state with a `CINEMATIC`
  camera mode (Path3D + look-at), then hand-off to the player with the bay's velocity.
- **Dialog**: subtitles + comms panel first (M4, used by the M7 tutorial). Voiced dialog comes later from an
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
- **core**: add a LOD builder (merge neighbouring splats with moment matching -> LOD1..LOD3 + far sprite), SDF
  sampling, impostor and scaled-space texture bakers, collision builder (convex pieces from parts).
- **parts**: hard-surface library (hull sections, panels, greebles, nozzles, trusses, docking bays, turrets,
  rotating drums, solar panels) and organic library (SDF/metaball and spline-swept bodies, noise surface detail)
  for Shadow and Vorlon designs.
- **styles**: one design language per faction as a parameter set: palette, panel density, curvature, symmetry,
  greeble set, surface finish. View-dependent sheen (SH degree 1-3, which GDGS evaluates) for Vorlon and Shadow
  iridescence.
- **assets**: parametric families, not one-offs: `starfury_aurora`, `starfury_thunderbolt`, `raider_fighter`,
  `raider_control_ship`, faction fighters and capitals, `babylon5_station` (~8 km, hub + rotating drum + bays +
  defense grid), `jumpgate`, planets (shader parameters + generated textures), `asteroid_field` (noise-displaced
  bodies), `comet` (nucleus + coma/tail volumetric splats), interiors (front-end B5 interior), per-system skies,
  and later voice lines rendered from dialog data by an offline TTS tool.
- Every asset emits the same contract: LOD chain, fallback mesh, collision primitives, hardpoints, manifest. Large
  assets (the station) may take minutes, so CI caches outputs keyed by a hash of the generator sources and seed.
  Outputs stay out of git (D9).

### 14.9 Seams already in M1 (and what is deliberately not)

Built in M1 because each is cheap and avoids a later rewrite:

| Seam | M1 task | Avoids later |
|---|---|---|
| `UniversePos` + `World`/`WorldFrame` parent for all world objects, `rebase()` tested, auto-rebase off | T09 | Re-parenting every scene and auditing raw `Vector3` positions when large worlds arrive |
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
| D22 | No `GaussianSplatNode` enters or leaves the tree during play. Splat-bearing entities (raiders, debris chunks) are pooled at scenario load and switched by visibility | GDGS v3.3.0 re-merges every node's splat data on each register and unregister (`gaussian_scene_registry.gd`: a GDScript loop over every splat in the scene, then new GPU buffers), so a spawn would hitch. A visibility change only re-packs instance transforms |
| D23 | Damage model: hull points only. No shields (Starfuries and Delta-Vs have none), no subsystems, no collision damage. Bolt damage comes from `WeaponSpec`, hull from `ShipSpec`. `debug.invulnerable` zeroes damage on `Damageable`s with `respects_god_mode` (the player) | Smallest model that gives kills and deaths. Subsystems are M11, ram damage M3 |
| D24 | Destruction = a code-generated explosion (shader, particles, light: meshes, never splats) + break-up into the asset's generated `chunks` (pooled chunk splats, chunk meshes once the pool is used up). Debris drifts and spins kinematically, no collisions | Reuses the hull's own look, causes no registry churn, stays procedural |
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
src/combat/explosion.tscn|.gd     generated explosion (fireball shader, flash light, sparks); drifts, self-frees
src/combat/explosion_fireball.gdshader
src/combat/debris_chunk.tscn|.gd  one chunk: GaussianSplatNode + chunk mesh fallback
src/combat/debris_pool.gd         Node: pooled chunk splat sets, mesh-only chunks and generic shards; drift, spin, shrink-out
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
src/input/control_profile.gd      RefCounted, pure: bindings <-> InputMap <-> config text, validation
src/input/control_profile_store.gd RefCounted: built-in and user profiles; list, load, save, apply
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
4. Ships (0): flight model and forces; their `PulseCannon`s spawn bolts (`last_step = 0`).
5. Projectiles (0): move, record `last_step = velocity * delta`, expire.
6. `TargetingController`s (100): refresh candidates (inactive targetables skipped).
7. `HitResolver` (200): sweep, damage, impact flashes. `destroyed` -> `DestructionDirector`, which hides and
   disables the ship in the same tick, so nothing targets or hits it afterwards.
8. `WaveDirector` (300): count the dead, spawn from the pool.
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
- `DebrisPool` holds 2 chunk splat sets per chunked asset type (one break-up's worth each); a third simultaneous
  break-up gets mesh chunks. Hidden splat nodes still cost an early-out per splat in projection and sort-buffer
  memory, so pools stay small.
- GDGS applies its Rz(180°) correction when a splat node enters the tree with an identity basis. Keep splat nodes
  as identity children of a moving parent and never reset their own transform; reparenting would also unregister
  and re-register them.
- Splat budget (registered, M2): Starfury ≈ 140k, sky 16k, buoys 38k, 6 raiders ≈ 150k, 2 debris sets ≈ 50k:
  about 400k (§7.4, §11).

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
`settings.show_hud` toggles it; while it shows, the debug overlay hides its own bracket.

### 15.10 Scenarios and waves

`ScenarioLoader` gains optional `pools` (`{"raider_fighter": 6}`), `waves[]` and `loop`. A spawn is `{type, name,
anchor: "player" | "origin", offset, velocity, behaviour}`; positions and waypoints are offsets from the anchor's
universe position at wave start (summed as `UniversePos`, never through float32). `ShipCatalog` maps `type` to a
`ShipSpec`. `WavePlan` (pure, fake-clock tested): `COUNTDOWN(delay) -> ACTIVE -> CLEARED -> next`, then loop from
`loop.from_wave`, one more attacker per loop up to the pool size. `settings.scenario` (`combat_sandbox` by
default, or `free_flight`) picks the file; `Main.scenario_path` overrides it for tests.

### 15.11 `raider_fighter` and chunks

The same output contract as §9, at about 25k splats (15k-40k budget; raiders are mostly seen at range). In
`hardpoints.json`: two pods (one per side, each with a main and a small retro nozzle, centre of mass trimmed onto
the thrust line so pod thrust makes no pitch torque), four `muzzles`, `collision` primitives that also serve as hit
volumes (they must cover the splats), `cockpit_camera` and `chase_anchor` (the `Hardpoints` parser requires them),
the hull depth proxy as `starfury_aurora` emits it since the M1 fix, and `chunks[]`:
`{name, ply, obj, offset, splats}`. `core/chunks.py` partitions the hull splats by part group (wing_l, wing_r, hump,
nacelle_l, nacelle_r); each chunk PLY is re-centred on its own centroid (GDGS centres every PLY) and flipped like the
hull; `offset` is that centroid in the body frame. The chunks together hold exactly the hull's splats. Style
`raider`: worn grey-brown plating, high panel tint jitter, dark canopy, yellow-white engine glow (a `ShipSpec`
tint, not splats).

### 15.12 Control profiles

`ControlProfile` (pure): `{action: [event descriptors], deadzone}` <-> `InputMap` <-> ConfigFile text. A
descriptor is `pad:button:<0-14>`, `pad:axis:<0-5><+|->`, `key:<physical key name>` or `mouse:<button>`. Validation
uses the M1 input rules: every `InputAdapter.ACTIONS` entry present, a pad event on every action except
keyboard-only debug ones, standard indices only, never `KEY_QUOTELEFT`. `default` is a snapshot of the
`project.godot` map taken before any profile is applied. `settings.control_profile` (new schema type `string`)
selects the profile at start-up and on change; an invalid profile warns and falls back to `default`. Bindings
changed with `bind`/`unbind` are session-only until `controls save <name>`. A rebinding menu comes with the M4
front end.

### 15.13 Console and settings (additions to §6.4)

| Provider | Owner (task) | Keys (w = writable) |
|---|---|---|
| `combat` | HitResolver (T03) | `projectiles`, `hits`, `last_hit`, `pairs_tested`, `resolve_us` (profiling only; the one wall-clock read) |
| `hull` | player Damageable (T03) | `hp`, `max_hp`, `fraction`, `invulnerable` (mirror of `debug.invulnerable`), `destroyed` |
| `raiders` | ShipPool (T05, T07) | `pool_size`, `free`, `alive`, `list` (name, behaviour/state, hull %, range), `selected_brain` |
| `waves` | WaveDirector (T09) | `scenario`, `index`, `name`, `state`, `next_in_s`, `alive`, `kills`, `losses` |
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
| `controls [list\|use\|save\|show] [name\|action]`, `bind <action> <descriptor>`, `unbind ...` | ControlProfiles | profiles |
| `sfx <name>` | AudioDirector | play a sound at the player |

New settings: `show_hud` (bool, true), `scenario` (enum `combat_sandbox`|`free_flight`, `combat_sandbox`),
`control_profile` (string `[a-z0-9_]{1,32}`, `default`), `sfx_volume` (float 0.0-1.0, 0.8).

### 15.14 Testing additions

Unit: `SweepMath` (analytic cases plus a brute-force sampling cross-check), `InterceptMath` (checked by
simulating the bolt and the target), `HullHealth`, `Factions`, `HudLayout`, `PilotSteering`, `WavePlan`,
`ControlProfile`, N-muzzle `PulseCannonGate`, hostile-first `TargetingSystem`. Integration (headless): hits at
closing speeds up to 1 400 m/s, near misses, no self-hit, rebase mid-flight, god mode, destruction in the same
tick, pooling (the number of `GaussianSplatNode`s in the tree never changes during a run), brains in Jolt (patrol
reaches its waypoints, attack hits a drone), a three-wave run, the console smoke runs. Python: `raider_fighter`
(budget, contract, chunk partition, collision coverage) and `sfx_combat`. (H) with pre-checks through
`scripts/capture.sh` (llvmpipe, Raster backend): asset silhouette, HUD layout, effect compositing.

### 15.15 Seams M2 leaves for later

| Seam | Task | Avoids later |
|---|---|---|
| `PilotBrain` / `Perception` / `PilotSteering` / `AiPilotDriver`; brains write only commands | T07 | M3 rewriting how AI ships are driven |
| `InterceptMath` shared by HUD and AI | T01 | Two lead solutions that disagree |
| `Factions` as the one relation query | T01 | Hunting faction string compares when M3/M11 add factions |
| `Combatant` + `ShipAssembly` build player and AI ships the same way | T02 | Special-casing allies, wingmen, the Thunderbolt |
| Hardpoints `chunks[]` via `core/chunks.py` | T04 | Per-asset debris code for every later ship |
| Pools filled at scenario load | T05 | Spawn hitches when missions spawn ships (M4) |
| `ControlProfile` | T11 | HOTAS / keyboard+mouse / menu remapping starting from scratch |
