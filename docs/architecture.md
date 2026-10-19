# Architecture

Design for `space-combat-sim`: a Newtonian 3D space-fighter sim in Godot 4, rendered primarily with 3D Gaussian
splats. This document is the contract between planning and implementation. Milestone scope and tasks live in
`docs/milestones/`; verified facts (versions, URLs, container quirks) live in `docs/research-notes.md`. §1-§13
describe what M1 builds; §14 is the long-term design that M1 must not block.

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

| # | Decision | Rationale (short) |
|---|---|---|
| D1 | Godot 4.7.2 (latest stable at planning time) | User decision: Godot 4. 4.7.x has Jolt default, SDL3 gamepads, GDGS has an explicit 4.7 fix. |
| D2 | GDGS v3.3.0 for splats, **Compute** backend, Raster as automatic fallback | Only maintained addon with multiple movable nodes, depth compositing against scene depth, and headless-importable resources. Pure GDScript, MIT, no native builds. `gdgs/rendering/backend = Auto` already falls back to Raster when compute is unavailable. |
| D3 | **No splat training.** Splats are produced by sampling procedurally authored surfaces (mesh-to-splat) and by writing Gaussians directly for stars/nebula | Deterministic, CPU-only, seconds to run, reproducible in CI and in the GPU-less container. Training (Brush) stays an optional polish step on a GPU machine. |
| D4 | RigidBody3D + Jolt. Pod nozzle forces are applied **at their hardpoint positions** (`apply_force`); RCS as central force + torque; no custom integrator | Correct rigid-body dynamics (inertia, angular momentum); differential pod thrust yaws the ship through real r × F computed by the engine; free collision later. Verified headless. Custom integrator only if Jolt limits ever block us (§5.6). |
| D5 | Flight logic in pure `RefCounted` classes, nodes are thin adapters | Unit-testable without a scene tree, display or controller. |
| D6 | Flight assist in M1. **ON (default)**: rate-command fly-by-wire that uses pod torque when it helps, cancels it with RCS, and trims the offending pods when RCS is not enough. **OFF**: raw pods + raw RCS torque. **Brake** (hold) works in both | Flyable by default, pods fantasy intact; one closed-form rule (§5.5). |
| D7 | User-chosen pad layout (§6.1): triggers = left/right main pods, bumpers = left/right retros, sticks = strafe / aim, D-pad = roll + target/weapon cycling. `InputMap` actions only, SDL3 standard layout, keyboard as extra events | Every DOF and combat function reachable without modifiers; per-side pod control is the Starfury identity; rebindable, testable, works on a generic pad. |
| D8 | Hybrid rendering: splats for hulls, buoys and sky; meshes for cockpit interior, projectiles, flashes, thruster glow, beacons; primitives for collision | Splats are static radiance; anything animated per frame, emissive-dynamic, or needing depth writes is a mesh. Each exception is justified in §7. |
| D9 | Generated assets are **not committed**; generators are. No Git LFS | Everything binary is reproducible from `tools/procgen` in seconds; LFS adds quotas and fork friction. |
| D10 | GUT over gdUnit4 | Simpler headless CLI (`-gexit`, exit code 1 on failure), no xvfb caveats, GDScript-first, tracks Godot 4.7. |
| D11 | 1 unit = 1 metre, SI everywhere, Godot axes (+X right, +Y up, **-Z forward**) | Avoids conversion bugs; Godot's `Basis.z` is backward, so forward is `-basis.z`. |
| D12 | Vendor addons into `addons/` | Offline-reproducible builds; standard Godot practice; licences travel with the code. |
| D13 | Linux x86_64 + Vulkan is the only target; GDGS Compute is the acceptance backend | The maintainer builds this for his own Linux gaming desktop. No per-OS code is written, so Godot keeps other doors open, but nothing else is tested or promised. |
| D14 | Pod thrust = 8 discrete nozzle forces (4 main, 4 retro) at hardpoint positions; RCS = ideal per-axis force/torque actuator with limits | The asymmetry that matters is in the big pod nozzles; modelling every RCS jet adds allocation maths with no gameplay gain. |
| D15 | M1 has targeting and weapon modes but nothing shootable: `TargetingSystem` over inert splat **nav buoys**; `weapon_next` cycles pulse-cannon fire modes | Smallest behaviour that makes every bound button do something verifiable; spinning buoys exercise several independently moving splat nodes before enemies need them. |
| D16 | Stay on the official single-precision engine. Large worlds use a floating-origin, free-falling `WorldFrame` plus 64-bit universe coordinates in script | No official double builds exist; GDGS packs matrices as float32 anyway; Jolt's 500 m/s cap needs a moving frame regardless (§14.1). |
| D17 | Procedural assets only, via a reusable generator framework (`tools/procgen`): no hand modelling, no AI 3D generators | User decision. Reproducible, reviewable, licence-clean, LOD-able by construction (§14.8). |
| D18 | Gravity (and any later field: hyperspace currents) is an explicit environmental force; project gravity stays 0 | Keeps Jolt a local rigid-body solver; M1 already has the hook (`WorldFrame.environment_accel`), returning zero. |

## 3. Project layout

```
project.godot                 Forward+, Jolt, zero default damping, physics interpolation on, InputMap actions
addons/gdgs/                  vendored GDGS v3.3.0 (MIT)
addons/gut/                   vendored GUT v9.7.1 (MIT)
data/scenarios/free_flight.json  M1 scenario: player start + nav buoys in universe coordinates
src/
  autoload/settings.gd        Settings: invert_y, deadzones, roll ramp, assist/camera defaults, pad calibration
  autoload/sim_clock.gd       SimClock: 64-bit sim time, warp (fixed 1.0 in M1); the only gameplay clock
  world/universe_pos.gd       RefCounted: 64-bit position (x, y, z floats) in metres, + system_id
  world/world_frame.gd        Node3D "World": origin UniversePos + origin velocity, to_local/to_universe,
                              rebase(offset), environment_accel(local_pos) (returns ZERO in M1)
  game/main.tscn|.gd          main scene: loads scenario, wires environment, ship, camera rig, overlay
  game/scenario_loader.gd     RefCounted: free_flight.json -> spawn list (UniversePos per entry)
  game/debug_overlay.tscn|.gd CanvasLayer: flight state, assist/camera, POD TRIM, weapon mode, target readout
                              + target bracket, splat backend, FPS, GPU, pad name/GUID/raw axes, universe position
  ship/ship.tscn|.gd          RigidBody3D "PlayerShip" adapter: consumes FlightCommand + CombatCommand
  ship/ship_spec.gd           Resource: mass, inertia, pod/RCS limits, rates, gains, asset_id, exhaust velocity
  ship/thruster_layout.gd     RefCounted: pod main/retro nozzles + RCS nozzles relative to CoM, from hardpoints
  ship/flight_model.gd        RefCounted, pure: FlightCommand + state -> FlightOutput (§5.2)
  ship/flight_assist.gd       RefCounted, pure: rate controller, pod trim, brake allocation
  ship/flight_output.gd       RefCounted: per-nozzle forces, RCS force/torque, totals, trim, levels, mass flow
  ship/hardpoints.gd          RefCounted: loads assets/generated/starfury_aurora/hardpoints.json
  ship/thruster_visuals.gd    drives emissive glow meshes from FlightOutput levels
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
  camera/chase_camera_math.gd RefCounted, pure: chase pose smoothing (unit-tested)
  input/flight_command.gd     RefCounted: per-side pod demand, strafe, rotation, brake, assist toggle
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

Autoloads: `Settings`, `SimClock`. No global event bus; nodes communicate downward by calls and upward by signals.

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
│   │   ├── HullMeshFallback (MeshInstance3D)  starfury_aurora.obj; visible only if splats unavailable or F4
│   │   ├── CockpitInterior (MeshInstance3D)   cockpit_interior.obj; visible only in first person
│   │   ├── Thrusters (Node3D)             glow mesh per pod main/retro nozzle and per RCS nozzle
│   │   ├── Guns (Node3D)                  Marker3D per muzzle + pulse_cannon.gd
│   │   ├── Targeting (Node)               targeting_controller.gd
│   │   └── CockpitAnchor (Marker3D)       from hardpoints "cockpit_camera"
│   ├── CameraRig (Node3D)                 camera_rig.gd
│   │   ├── CockpitCamera (Camera3D)       follows CockpitAnchor via RemoteTransform3D on the anchor
│   │   └── ChaseCamera (Camera3D)         top_level; smoothed in _process; in group "world_shiftable"
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
| `brake_gain_k` | 2.0 s⁻¹ | translational brake P gain |
| `exhaust_velocity` | 30 000 m/s | only for the reaction-mass seam: `mass_flow = Σ thrust / v_e`, unlimited in M1 |

Pod geometry comes from hardpoints: pod centres at (±3.18, ±3.18) m (4.5 m radius at 45°), so the yaw lever arm
is ≈ 3.18 m. Derived numbers (tests always compute these from spec + hardpoints, never hard-code them):

- One side's mains at full, assist off: yaw torque `2 × 3.18 m × 0.36 MN ≈ 2.29 MN·m`, i.e. 3.8 rad/s²
  (≈ 220 °/s², ≈ 109 °/s after 0.5 s). Deliberately violent: pod steering is the Starfury trick. Tune pod
  thrust or inertia after first flight, not the model.
- RCS yaw authority (0.94 MN·m) cancels at most `0.94 / 3.18 ≈ 0.30 MN` of side imbalance, so with assist on
  one trigger alone gives ≈ 6.2 m/s² straight ahead (POD TRIM ≈ 59 %).

### 5.2 From command to forces

Pods: `ur`, `lr` = right side (x > 0); `ul`, `ll` = left side. Each pod has a main nozzle (exhaust +Z, so
thrust is -Z, forward) and a retro nozzle (exhaust -Z). RT drives both right mains, LT both left mains, RB both
right retros, LB both left retros. Nozzle positions `p_i` come from hardpoints relative to the body origin;
`r_i = p_i - center_of_mass`. Nozzle groups: `R_MAIN, L_MAIN, R_RETRO, L_RETRO`.

```
# inputs: c (FlightCommand), v_b, w_b (body frame), env_accel_b (body frame, ZERO in M1), assist_on
#         layout (ThrusterLayout), spec (ShipSpec)

# 1. pilot demand per nozzle group (levels 0..1) and RCS translation
level[R_MAIN]  = c.main_right      level[L_MAIN]  = c.main_left
level[R_RETRO] = c.retro_right     level[L_RETRO] = c.retro_left
rcs_force      = Vector3(c.strafe.x * rcs_force_max.x, c.strafe.y * rcs_force_max.y, 0)

# 2. brake (hold X) overrides all translational demand, assist on or off
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
    w_target = c.rot * AXIS_SIGN * deg_to_rad(rate_max)
    tau_des  = inertia * assist_gain_k * (w_target - w_b)          # diagonal inertia, per axis
    residual = tau_des - tau_pods
    overflow = residual - clamp(residual, -rcs_torque_max, rcs_torque_max)
    if overflow.y != 0:            # pods yaw harder than RCS can counter: trim the groups causing it
        cause = groups g with sign(tau_g.y) == -sign(overflow.y)
        lam   = max(0, 1 - |overflow.y| / Σ_{g in cause} |tau_g.y|)
        level[g] *= lam for g in cause;  recompute F_pods, tau_pods;  residual = tau_des - tau_pods
    tau_rcs = clamp(residual, -rcs_torque_max, rcs_torque_max)
else:
    tau_rcs = c.rot * AXIS_SIGN * rcs_torque_max                    # raw: stick / D-pad command torque

# 5. outputs (body frame)
nozzle_forces = [(p_i, F_i)]              # Ship: apply_force(B·F_i, B·p_i) for each
rcs_force, tau_rcs                        # Ship: apply_central_force(B·rcs_force), apply_torque(B·tau_rcs)
force_b  = F_pods + rcs_force             # predicted totals, for tests and the overlay
torque_b = tau_pods + tau_rcs
trim     = 1 - lam                        # 0 when nothing was trimmed
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
one unit test per axis.

What the player must experience:

| Input | Assist OFF (raw) | Assist ON (default) |
|---|---|---|
| RT + LT equal | straight acceleration, zero net torque | same |
| RT alone | accelerate and yaw nose **left** (right pods push); the spin keeps building | straight ahead at trimmed thrust (≈ 6 m/s²), heading held, overlay shows POD TRIM |
| LT alone | accelerate and yaw nose **right** | mirror of RT alone |
| RB + LB | straight deceleration (retros) | same |
| RB alone | decelerate and yaw nose **right** | decelerate at trimmed thrust, heading held |
| Right stick right + LT | (raw torque + pod yaw) | faster turn-in: left-pod torque helps until the target rate is reached, then gets trimmed |
| Right stick back / right | nose up / nose right (torque) | nose up / nose right (rate); stops when centred |
| D-pad right | roll right | roll right (ramped) |
| Left stick right / up | translate right / up; nose does not turn | same |
| Release everything | velocity unchanged; spin unchanged | velocity unchanged; rotation stops |
| X held | velocity → 0 with symmetric pods + RCS; rotation still raw | velocity → 0; rotation per stick |

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

- **Assist ON** (toggle B, persisted in `Settings`, default on): the flight computer owns attitude. Stick and
  D-pad command an angular *rate*; centred means "stop rotating". It knows the pods' torque exactly (from
  hardpoints) and treats it as feed-forward: it lets pod torque help when it points the way the pilot is
  turning, cancels it with RCS when it does not, and trims (only ever reduces) the offending side when RCS
  authority is not enough. The pilot's trigger and bumper levels are a ceiling, never exceeded. Translation is
  untouched except by that trim and by the brake.
- **Assist OFF**: raw Newtonian. Pods fire exactly as demanded and their r × F torque acts in full, so uneven
  triggers tank-steer the ship. Stick and D-pad command raw RCS torque. Nothing damps rotation. This is the
  flip-and-burn mode.
- **Brake** (hold X), both modes: the flight computer takes over translation. Pods fire symmetrically (no torque)
  plus RCS sway/heave, nulling velocity relative to the `World` frame (later: relative to a chosen reference such
  as the station). Triggers, bumpers and the left stick are ignored while held; rotation follows the assist mode.
- **Why this rule.** (1) The default mode is flyable by anyone; uneven triggers cannot spin you out. (2) The pods
  are physically real in both modes (forces at the pods, glow per pod, trim visible), and assist off gives the
  full tank-steering fantasy. (3) It is one closed-form rule with no hidden yaw gain: deterministic and
  unit-testable. (4) AI pilots get identical semantics. Rejected alternative: in assist on, treat the trigger
  difference as an extra yaw-rate request. Two yaw inputs with different gains is confusing, and at the target
  rate the pods still exceed RCS, so it would need the same trim anyway.
- Rate controller: pure P with clamp. A 60 °/s stop takes ≈ 0.9 s (simulated). Add D only if human testing shows
  oscillation.

### 5.6 Limits and later work

- Jolt clamps body speed: `physics/jolt_physics_3d/limits/max_linear_velocity` (default 500 m/s, adjustable) and
  `max_angular_velocity` (default 2700 °/s). M1 speeds stay under 200 m/s. Orbital speeds (km/s) are handled by
  the moving `WorldFrame` (§14.1), not by raising the limit.
- If Jolt ever becomes the obstacle, the fallback is a custom integrator driving a `Node3D`; the pure-class split
  (D5) keeps that contained.

## 6. Input

### 6.1 Gamepad mapping (user-chosen layout)

```
RT  right main pods (analog)      LT  left main pods (analog)
RB  right retros (hold)           LB  left retros (hold)
R-stick  pitch / yaw (aim)        L-stick  strafe L/R + up/down
D-pad L/R  roll                   D-pad Up  next target      D-pad Down  next weapon
A  fire       B  flight assist    X  brake (hold)            Y  camera 1st/3rd
R3  target ahead                  L3  debug overlay
Back  reset                       Start  pause
```

All via `InputMap` actions in `project.godot`; `device = -1` (any pad). Names are the Xbox-style names Godot/SDL3
use for the standard layout; any pad SDL3 recognises, generic XInput clones included, presents it.

| Action | Pad (Godot enum, index) | Keyboard | Type | Deadzone | Curve |
|---|---|---|---|---|---|
| `main_right` | RT `JOY_AXIS_TRIGGER_RIGHT` (axis 5, +) | E, W | analog 0..1 via `get_trigger` | 0.05 | linear |
| `main_left` | LT `JOY_AXIS_TRIGGER_LEFT` (axis 4, +) | Q, W | analog 0..1 via `get_trigger` | 0.05 | linear |
| `retro_right` | RB `JOY_BUTTON_RIGHT_SHOULDER` (10) | D, S | hold | - | - |
| `retro_left` | LB `JOY_BUTTON_LEFT_SHOULDER` (9) | A, S | hold | - | - |
| `pitch_down` / `pitch_up` | Right stick Y `JOY_AXIS_RIGHT_Y` (axis 3, -/+): stick back = nose up; `Settings.invert_y` flips | I / K | analog pair | radial 0.15 | expo 1.5 |
| `yaw_left` / `yaw_right` | Right stick X `JOY_AXIS_RIGHT_X` (axis 2, -/+) | J / L | analog pair | radial 0.15 | expo 1.5 |
| `strafe_left` / `strafe_right` | Left stick X `JOY_AXIS_LEFT_X` (axis 0, -/+) | Left / Right arrows | analog pair | radial 0.15 | linear |
| `strafe_down` / `strafe_up` | Left stick Y `JOY_AXIS_LEFT_Y` (axis 1, +/-) | Down / Up arrows | analog pair | radial 0.15 | linear |
| `roll_left` / `roll_right` | D-pad `JOY_BUTTON_DPAD_LEFT` / `DPAD_RIGHT` (13 / 14) | U / O | hold, ramped | - | 0→1 in 0.25 s |
| `target_next` | D-pad `JOY_BUTTON_DPAD_UP` (11) | T | edge | - | - |
| `weapon_next` | D-pad `JOY_BUTTON_DPAD_DOWN` (12) | F | edge | - | - |
| `target_ahead` | R3 `JOY_BUTTON_RIGHT_STICK` (8) | G | edge | - | - |
| `fire` | A `JOY_BUTTON_A` (0) | Space, left mouse | hold | - | - |
| `toggle_flight_assist` | B `JOY_BUTTON_B` (1) | Z | edge | - | - |
| `brake` | X `JOY_BUTTON_X` (2) | X | hold | - | - |
| `toggle_camera` | Y `JOY_BUTTON_Y` (3) | V | edge | - | - |
| `reset_ship` | Back `JOY_BUTTON_BACK` (4) | Backspace | edge | - | - |
| `pause` | Start `JOY_BUTTON_START` (6) | Esc | edge | - | - |
| `debug_toggle_overlay` | L3 `JOY_BUTTON_LEFT_STICK` (7) | F3 | edge | - | - |
| `debug_toggle_fallback_mesh` | none (debug, keyboard only) | F4 | edge | - | - |

Notes:
- Only axes 0-5 and buttons 0-14 are used. Guide (5) and SDL extras (paddles, misc, touchpad, ≥ 15) are not.
  No rumble, no impulse triggers, no light bar, no motion sensors.
- W and S are "both sides" keys: the same key is an event on two actions.
- R3 is clicked with the aiming thumb; `target_ahead` samples the boresight at the press, so the small stick jolt
  of a click does not matter. L3 only toggles the overlay, so an accidental click while strafing is harmless.
- Roll ramp: while a roll action is held, `rot.z` moves toward ±1 at `1 / Settings.roll_ramp_s` per second
  (default 0.25 s to full); release snaps to 0; reversing direction restarts from 0. Taps give fine corrections
  from a digital D-pad.
- Sticks: `Input.get_vector(neg_x, pos_x, neg_y, pos_y, Settings.stick_deadzone)` (radial deadzone with
  rescaling), then `sign(x)·|x|^1.5` on pitch/yaw in `InputAdapter`.

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
var brake: bool         # held
var toggle_assist: bool # edge, true for one tick

class_name CombatCommand extends RefCounted   # weapons + targeting; written by the player or an AI
var fire: bool          # held
var weapon_next: bool   # edge
var target_next: bool   # edge
var target_ahead: bool  # edge

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
  applies `CombatCommand` edges, emits `target_changed(id)`.
- **NavBuoy**: inert marker with a splat body (one shared `GaussianResource`, GDGS instancing), a blinking beacon
  mesh, a 10 °/s spin about its long axis, optional constant drift. No collision; cannot be shot. Five are spawned
  from `data/scenarios/free_flight.json` at 0.5-5 km; faction `neutral`.
- **Pulse cannon modes** (`PulseCannonGate`, pure): `ALTERNATING` (4 Hz, muzzles alternate) and `LINKED`
  (2 Hz, both muzzles together). `weapon_next` cycles and wraps; the cooldown carries over, so switching cannot
  raise the rate of fire.

## 7. Rendering pipeline

### 7.1 What is a splat, what is a mesh

| Element | Representation | Why |
|---|---|---|
| Ship hull (fuselage, struts, pods, canopy exterior) | **Splats** (`HullSplats`, ~150k Gaussians) | The point of the project; GDGS re-uploads a node's transform on change, so a moving, rotating body works. |
| Nav buoy bodies | **Splats** (~8k each, one shared resource, 5 instances, spinning) | Exercises several independently moving splat nodes before enemies need them. |
| Stars | **Splats** (in `SkySplats`, ~12k tiny Gaussians) | A Gaussian is the ideal star PSF; brightness/colour per splat; crisp at any resolution unlike a panorama texture. |
| Nebula | **Splats** (in `SkySplats`, ~4k large soft Gaussians) | Volumetric look for free; per-tile depth sort handles overlapping translucency. |
| Cockpit interior (frame, canopy struts, dash slab) | Mesh (`cockpit_interior.obj`) | Needs hard edges at the near plane and **depth writes** so hull splats behind the frame are rejected by the compositor's depth test; visible only in first person. |
| Thruster glow, buoy beacons | Meshes, unshaded emissive, additive, animated per tick | Per-frame intensity animation; splats are static radiance (no per-splat opacity animation in GDGS). |
| Projectiles, muzzle flash | Meshes, unshaded emissive | Tiny, fast-moving, short-lived; spawning/destroying splat nodes per shot would churn GPU buffers. |
| Target bracket | 2D `Control` in the debug overlay | Screen-space UI. |
| Collision | `CollisionShape3D` primitives from hardpoints JSON | Splats have no surface; GDGS's collision generator is editor-only and overkill for a handful of boxes. |
| Hull / buoy fallback | Meshes (`.obj`, hidden) | Debug comparison and the fallback path (§7.4). |

### 7.2 Compositing order (GDGS Compute backend)

1. Godot renders opaque meshes (cockpit interior, fallback meshes if visible) -> colour + depth.
2. GDGS `CompositorEffect` runs at `EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT`: projects all `GaussianSplatNode`s
   (hull, buoys, sky) in one pass, radix-sorts `(tile | depth)` keys, blends front-to-back, depth-tests against
   the resolved scene depth (`depth_bias`, `depth_test_min_alpha`, `alpha_cutoff` are tunables on the effect).
3. Godot renders transparent meshes (thruster glow, beacons, projectiles, flashes) on top. Correct for additive
   effects even when the emitter sits inside hull splats.
4. Post: glow/bloom, tonemap. Keep glow modest so star splats do not bloom into blobs.

The sky node sits far away (radius 20 km) and follows the camera origin each frame (`SkyFollower`,
`top_level = true`), so it never parallaxes and never collides with the depth of nearby meshes. Camera `near =
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
- **Chase**: `top_level` camera. Target pose each frame from `ChaseCameraMath`: position = `ship.origin +
  ship.basis * Vector3(0, 2.5, 9.0)` (behind and above), looking at `ship.origin + ship.forward * 40`.
  Smoothing: exponential approach with half-life 0.08 s for position and slerp with half-life 0.12 s for
  rotation, computed with `exp2(-dt / half_life)` so it is frame-rate independent. The camera follows
  *orientation*, not velocity, so sideways drift and pod tank-steering are visible; a velocity-vector marker is
  a later HUD item.
- Modes are an enum (`COCKPIT`, `CHASE`; `CINEMATIC` and `FREE_LOOK` later). Toggle via `toggle_camera`;
  `Settings.camera_default`. `CockpitInterior.visible == (mode == COCKPIT)`.
- Camera near/far as in §7.2. Physics interpolation on, so the chase camera's `_process` reads interpolated
  transforms. The chase camera is in group `world_shiftable` because `top_level` nodes do not follow a parent.

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
(`WorldFrame`): spawns take a `UniversePos` (64-bit) and are converted with `to_local()`; `rebase(offset)` exists
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
| GDScript unit | GUT `tests/unit` | container, CI | `FlightModel` (pod forces at positions, r × F signs per §5.2 table, zero pitch/roll from pods, trim maths, brake symmetry, clamps, mass flow), `FlightAssist` (converges, never exceeds limits), `InputAdapter` (radial deadzone, expo, roll ramp, edges, invert-Y, command split), `TriggerCalibration` (rest 0 and -1), `ChaseCameraMath` (frame-rate independence), `PulseCannonGate` (modes, rates, cycling), `TargetingSystem` (next, ahead, readout), `UniversePos` (64-bit precision at 1e11 m) |
| Headless integration | GUT `tests/integration`, `--headless` | container, CI | ship scene instantiates; damping guard; pod-differential yaw measured in Jolt matches the model; assist holds heading under one trigger; brake; projectile velocity/lifetime; all PLYs import with manifest counts; `World.rebase` keeps velocities and relative positions; scenario spawns buoys; targeting with live buoys; `SkyFollower`; camera toggle; `main.tscn` runs 180 frames without script errors |
| Human acceptance | checklist in the milestone doc | Linux/Vulkan GPU + generic XInput pad | splat appearance, compositing, feel, performance, controller behaviour, trigger/deadzone calibration, targeting |

Rules: every pure class gets unit tests in the same PR; every scene gets at least an instantiate-and-run test;
anything that depends on a GPU is marked `(H)` in acceptance criteria and is never faked in CI.

Commands (also in `scripts/run_tests.sh`):

```
python3 -m unittest discover -s tools/procgen/tests -t . -v
.tools/godot/godot --headless --path . --import
.tools/godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=reports/gut.xml
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
- Tunables live in `Resource`s (`ShipSpec`) or `Settings`, not as literals in node scripts.
- Comments explain *why*; the sign conventions in §5.2 are documented at the top of `flight_model.gd`.
- Python: `ruff`-clean (default rules), type hints, `argparse` CLI, `--seed`, pure functions; no Blender
  dependency; every asset module implements the `build(ctx) -> AssetOutputs` contract.
- Commits: imperative subject, task id prefix when applicable (`M1-T07: flight model and assist`).

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

- `SimClock` owns sim time (64-bit seconds since epoch) and `warp`. Levels: 1, 2, 4 (**physics warp**: Jolt keeps
  stepping at 60 Hz sim time with more steps per frame; controls live), then 10, 100, 1000 (**on rails**: Jolt
  bodies frozen; each ship's state propagated by the gravity integrator, a symplectic leapfrog with adaptive
  substeps bounded by the local gravity gradient; no thrust, no collisions).
- Warp limits: on-rails warp is refused or dropped to 1× when a hostile is within 50 km (or any AI is in a combat
  state), when any thrust input is non-zero, inside a close-approach shell of a body (substep limiter), during
  scripted mission sequences, and on proximity or collision-course alarms. The cap is configurable (user's
  default ~1000×).
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
- **Dialog**: subtitles + comms panel in M-series; voice is an open question (procedural-only rule).
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
  bodies), `comet` (nucleus + coma/tail volumetric splats), interiors (front-end B5 interior), per-system skies.
- Every asset emits the same contract: LOD chain, fallback mesh, collision primitives, hardpoints, manifest. Large
  assets (the station) may take minutes, so CI caches outputs keyed by a hash of the generator sources and seed.
  Outputs stay out of git (D9).

### 14.9 Seams already in M1 (and what is deliberately not)

Built in M1 because each is cheap and avoids a later rewrite:

| Seam | M1 task | Avoids later |
|---|---|---|
| `UniversePos` + `World`/`WorldFrame` parent for all world objects, `rebase()` tested, auto-rebase off | T08 | Re-parenting every scene and auditing raw `Vector3` positions when large worlds arrive |
| `World.environment_accel()` applied by the Ship each tick (returns zero); `env_accel_b` feed-forward in the brake | T07, T09 | Retrofitting gravity and hyperspace fields into the flight path |
| `SimClock` autoload; rule: no wall-clock time in gameplay | T01 | Hunting timers when time warp lands |
| Flight/Combat/Ui command split | T06 | Untangling player-only input from what AI pilots write |
| `TargetInfo.faction` | T13 | Changing the targeting data model for IFF, allies and enemies |
| `ShipSpec` per ship class with `asset_id`; `mass_flow` in `FlightOutput` (unlimited reaction mass) | T07, T09 | Ship-class hard-coding (Thunderbolt) and a flight-model change for finite fuel |
| Scenario JSON for free flight, spawns in universe coordinates | T13, T14 | A second spawn path when the mission framework arrives |
| `tools/procgen` framework layout, per-asset output dirs, manifest `lods` array | T02, T04 | Moving files and rewriting import paths for every later asset |
| Camera mode enum | T11 | Reworking the rig for cinematic and free-look modes |

Deliberately **not** seams in M1, because they cannot be made cheap: the moving (velocity-rebased) frame and tidal
gravity (§14.1-14.2), on-rails warp (§14.3), the LOD/scaled-space render layers (§14.4) and the hyperspace space
(§14.5). Each is its own roadmap milestone.
