# Architecture

Design for `space-combat-sim`: a Newtonian 3D space-fighter sim in Godot 4, rendered primarily with 3D Gaussian
splats. This document is the contract between planning and implementation. Milestone scope and tasks live in
`docs/milestones/`; verified facts (versions, URLs, container quirks) live in `docs/research-notes.md`.

## 1. Tech stack (pinned)

| Layer | Choice | Version | Licence |
|---|---|---|---|
| Target platform | **Linux x86_64 + Vulkan (primary)**; Windows x86_64 + Vulkan (secondary, must keep working) | - | - |
| Engine | Godot (standard build, no .NET) | **4.7.2-stable** | MIT |
| Renderer | Forward+ (Vulkan) | - | - |
| Controller | Generic XInput-class gamepad through Godot/SDL3's standard `JOY_*` layout; no Xbox-only features | - | - |
| Physics | Jolt (built in, set explicitly) | bundled | MIT |
| Splat rendering | GDGS `addons/gdgs`, Compute backend | **v3.3.0** | MIT |
| Language | GDScript, statically typed | - | - |
| Tests (engine) | GUT `addons/gut` | **v9.7.1** | MIT |
| Asset generators | Python + NumPy (+ Pillow for the fallback sky only) | 3.11+ / 2.x | PSF / BSD |
| CI | GitHub Actions, `ubuntu-latest`, Godot downloaded from GitHub releases | - | - |

Version bumps are deliberate PRs that update this table, `scripts/setup_godot.sh`, `.github/workflows/ci.yml`
and `docs/third-party.md` together.

## 2. Key decisions

| # | Decision | Rationale (short) |
|---|---|---|
| D1 | Godot 4.7.2 (latest stable at planning time) | User decision: Godot 4. 4.7.x has Jolt default, SDL3 gamepads, GDGS has an explicit 4.7 fix. |
| D2 | GDGS v3.3.0 for splats, **Compute** backend, Raster as automatic fallback | Only maintained addon with multiple movable nodes, depth compositing against scene depth, and headless-importable resources. Pure GDScript, MIT, no native builds. `gdgs/rendering/backend = Auto` already falls back to Raster when compute is unavailable. |
| D3 | **No splat training.** Splats are produced by sampling procedurally authored surfaces (mesh-to-splat) and by writing Gaussians directly for stars/nebula | Deterministic, CPU-only, seconds to run, reproducible in CI and in the GPU-less container. Training (Brush) stays an optional M2+ polish step on a GPU machine. |
| D4 | RigidBody3D + Jolt, forces/torques applied each physics tick; **no custom integrator** | Correct rigid-body dynamics (inertia tensor, angular momentum), free collision later, impulses for hits, sleeping/interp handled by the engine. Verified headless. Custom integrator reserved only if Jolt's velocity clamp becomes a problem (see §5.6). |
| D5 | Flight logic in pure `RefCounted` classes, nodes are thin adapters | Unit-testable without a scene tree, display or controller. |
| D6 | Flight assist ships in M1: **rotation assist** (default on) + **brake hold**; raw Newtonian when off | Starfuries are fly-by-wire in canon; untrained players cannot fly 6DOF without rotational damping; it is ~40 lines on top of the same force path, and toggling it is a core fantasy of the ship. Translational auto-hold stays out of M1. |
| D7 | Gamepad via Godot `InputMap` actions only, bound to SDL3's standard `JOY_AXIS_*`/`JOY_BUTTON_*` layout; keyboard bindings are extra events on the same actions | The tester uses a generic XInput pad, not a genuine Xbox controller: rebindable actions, a fake input source for tests, no rumble/impulse-trigger assumptions, and SDL mapping overrides for misbehaving pads. |
| D13 | Linux/Vulkan with the GDGS **Compute** backend is the M1 acceptance platform; Windows is kept building but is not an M1 gate | That is the tester's machine; Compute is the backend with exact per-tile sorting and depth compositing. |
| D8 | Hybrid rendering: splats for hull and sky, meshes for cockpit interior, projectiles, flashes, thruster glow, collision | Splats are static radiance; anything animated per frame, emissive-dynamic, or needing depth writes is a mesh. Each exception is justified in §7. |
| D9 | Generated assets are **not committed**; generators are. No Git LFS in M1 | Everything binary is reproducible from `tools/` in seconds; LFS adds bandwidth quotas and fork friction. Revisit when hand-authored binaries (audio, textures) appear. |
| D10 | GUT over gdUnit4 | Simpler headless CLI (`-gexit`, exit code 1 on failure), no xvfb caveats, GDScript-first, tracks Godot 4.7. |
| D11 | 1 unit = 1 metre, SI everywhere, Godot axes (+X right, +Y up, **-Z forward**) | Avoids conversion bugs; Godot's `Basis.z` is backward, so forward is `-basis.z`. |
| D12 | Vendor addons into `addons/` | Offline-reproducible builds; standard Godot practice; licences travel with the code. |

## 3. Project layout

```
project.godot                 Forward+, Jolt, zero default damping, physics interpolation on, InputMap actions
addons/gdgs/                  vendored GDGS v3.3.0 (MIT)
addons/gut/                   vendored GUT v9.7.1 (MIT)
src/
  autoload/settings.gd        Settings: invert_y, deadzones, assist default, camera default (user://settings.cfg)
  game/main.tscn|.gd          main scene: wires environment, ship, camera rig, overlay
  game/debug_overlay.tscn|.gd CanvasLayer with speed, velocity, angular rate, assist/camera state, FPS, backend
  ship/ship.tscn|.gd          RigidBody3D "PlayerShip" adapter: reads FlightCommand, applies forces
  ship/ship_spec.gd           Resource: mass, inertia, thrust limits, rate limits, assist gains
  ship/flight_model.gd        RefCounted, pure: FlightCommand + state -> body-frame force/torque + thruster levels
  ship/flight_assist.gd       RefCounted, pure: rate controller and brake
  ship/hardpoints.gd          RefCounted: loads assets/generated/ship/starfury_hardpoints.json
  ship/thruster_visuals.gd    drives emissive glow meshes from thruster levels
  weapons/pulse_cannon_gate.gd RefCounted, pure: fire-rate gate and muzzle alternation (unit-tested with fake time)
  weapons/pulse_cannon.gd     node adapter: trigger state, spawns projectiles at muzzle hardpoints
  weapons/projectile.tscn|.gd kinematic projectile (inherits ship velocity), lifetime, emissive mesh
  camera/camera_rig.gd        owns CockpitCamera + ChaseCamera, toggle, smoothing
  camera/chase_camera_math.gd RefCounted, pure: chase pose from ship pose/velocity (unit-tested)
  input/flight_command.gd     RefCounted struct: the only thing the ship reads from input
  input/input_source.gd       abstract: get_axis(action_neg, action_pos), is_pressed(action), was_just_pressed
  input/godot_input_source.gd InputSource over the Input singleton
  input/input_adapter.gd      InputSource -> FlightCommand (radial deadzone, expo curve, toggles, edge detection)
  environment/space_environment.tscn|.gd  WorldEnvironment (+Compositor with gdgs effect), key light, SkySplats
  environment/sky_follower.gd pins the sky splat node to the active camera position each frame
  rendering/splat_status.gd   reports active GDGS backend; enables fallback meshes if neither backend initialised
assets/
  generated/                  gitignored. ship/{starfury.ply,starfury.obj,starfury.mtl,cockpit_interior.obj,
                              starfury_hardpoints.json,manifest.json}  environment/{sky_splats.ply,manifest.json,
                              sky_panorama.png (fallback, optional)}
  materials/*.tres            emissive glow, projectile, cockpit materials (hand-made, tiny)
tools/
  common/ply_writer.py        standard 3DGS binary PLY writer (+ frame conversion)
  common/geometry.py          primitives (box, cylinder, cone, tube), surface sampling, tangent frames
  starfury/spec.py            parametric Starfury description + hardpoints + collision primitives
  starfury/build_starfury.py  spec -> ply/obj/mtl/json/manifest
  environment/build_sky.py    stars + nebula -> ply (+ --panorama png fallback)
  tests/                      python unittest for all of the above
tests/                        GUT suites: unit/ (pure classes), integration/ (headless scene tests), fixtures/
scripts/
  setup_godot.sh              download + sha256-verify Godot 4.7.2 into .tools/godot/
  vendor_addons.sh            git clone pinned tags, copy addons/<name>, keep licences (run once; result committed)
  gen_assets.sh               run all generators into assets/generated/
  run_tests.sh                python tests, godot --import, GUT headless, junit to reports/
.github/workflows/ci.yml
docs/                         this file, milestones/, roadmap.md, research-notes.md, third-party.md
```

Autoloads: only `Settings`. No global event bus in M1; nodes communicate downward by calls and upward by signals.

### Main scene tree (`src/game/main.tscn`)

```
Main (Node3D)                              main.gd
├── SpaceEnvironment (space_environment.tscn)
│   ├── WorldEnvironment                   Environment (black sky, no fog, tonemap ACES/filmic, glow on) + Compositor[gdgs effect]
│   ├── KeyStar (DirectionalLight3D)       lights meshes only; splats are pre-lit
│   └── SkySplats (GaussianSplatNode)      top_level = true; sky_follower.gd keeps origin == active camera origin
├── PlayerShip (ship.tscn, RigidBody3D)    ship.gd
│   ├── CollisionShape3D x N               from hardpoints "collision" primitives (boxes/capsules)
│   ├── HullSplats (GaussianSplatNode)     identity transform; gaussian = starfury.ply import
│   ├── HullMeshFallback (MeshInstance3D)  starfury.obj; visible only if splats unavailable or debug toggle
│   ├── CockpitInterior (MeshInstance3D)   cockpit_interior.obj; visible only in first person
│   ├── Thrusters (Node3D)                 one glow MeshInstance3D per nozzle, placed from hardpoints
│   ├── Guns (Node3D)                      Marker3D per muzzle + pulse_cannon.gd
│   └── CockpitAnchor (Marker3D)           from hardpoints "cockpit_camera"
├── CameraRig (Node3D)                     camera_rig.gd
│   ├── CockpitCamera (Camera3D)           follows CockpitAnchor via RemoteTransform3D on the anchor
│   └── ChaseCamera (Camera3D)             top_level; smoothed in _process
├── Projectiles (Node3D)                   container for live projectiles
└── DebugOverlay (CanvasLayer)
```

## 4. Module boundaries

```
InputSource ──> InputAdapter ──FlightCommand──> Ship ──(force, torque)──> RigidBody3D/Jolt
                                              │  └──> FlightModel(+FlightAssist)  [pure]
                                              ├──thruster_levels──> ThrusterVisuals
                                              └──fire──> PulseCannon ──> Projectile(s)
Ship.global_transform / linear_velocity ──> CameraRig ──> active Camera3D ──> SkyFollower
Settings (autoload) ──> InputAdapter, CameraRig, Ship (assist default)
```

Rules:
- `FlightModel`, `FlightAssist`, `InputAdapter`, `ChaseCameraMath` are `RefCounted`, import nothing from the scene
  tree, and are covered by unit tests. Nodes only marshal data in and out.
- The ship never reads `Input` directly; it consumes a `FlightCommand` handed to it by `main.gd` each physics tick.
- Weapons and visuals read ship state through typed getters, never by reaching into sibling nodes.
- Rendering (splat vs mesh) is invisible to gameplay code: `Ship` exposes hardpoints; which node draws the hull is
  decided by `SplatStatus`.

## 5. Newtonian flight model

### 5.1 State and units

Owned by Jolt via `RigidBody3D`: position (m), orientation (`Basis`), linear velocity `v` (m/s), angular velocity
`w` (rad/s, world frame). Mass properties from `ShipSpec`:

| Parameter | Default | Note |
|---|---|---|
| `mass` | 48 000 kg | fan-lore Aurora-class mass; tune for feel |
| `inertia` (body, diagonal) | (6.0e5, 6.0e5, 4.0e5) kg·m² | x = pitch, y = yaw, z = roll; set explicitly so torque limits are predictable |
| `center_of_mass` | from hardpoints | `center_of_mass_mode = CUSTOM` |
| `thrust_main` | 1.44 MN (30 m/s², ~3 g) | aft nozzles, +thrust along -Z |
| `thrust_retro` | 0.72 MN | forward-facing nozzles |
| `thrust_lateral`, `thrust_vertical` | 0.48 MN each (10 m/s²) | RCS |
| `torque_max` (pitch, yaw, roll) | (9.4e5, 9.4e5, 1.26e6) N·m | = inertia × (1.57, 1.57, 3.14) rad/s² |
| `rate_max` (pitch, yaw, roll) | (60, 60, 120) deg/s | assist target at full stick |
| `assist_gain_k` | 6.0 s⁻¹ | rate controller P gain |
| `brake_gain_k` | 2.0 s⁻¹ | translational brake P gain |

### 5.2 Body-frame command to force and torque

Let `c` be the `FlightCommand` (all in [-1, 1] or [0, 1]), `B` the ship basis, `v_b = B⁻¹·v`, `w_b = B⁻¹·w`.

```
# translation (body frame; -Z is forward)
F_b.x =  c.strafe.x * thrust_lateral
F_b.y =  c.strafe.y * thrust_vertical
F_b.z = -c.thrust_fwd * thrust_main + c.thrust_rev * thrust_retro

if c.brake:                      # hold-to-brake: cancel velocity with available thrust, per axis
    a_des = -brake_gain_k * v_b
    F_b.x = clamp(mass * a_des.x, -thrust_lateral,  thrust_lateral)
    F_b.y = clamp(mass * a_des.y, -thrust_vertical, thrust_vertical)
    F_b.z = clamp(mass * a_des.z, -thrust_main,     thrust_retro)   # note asymmetric limits

# rotation
if assist_on:
    w_target = c.rot * deg_to_rad(rate_max)                 # per axis
    tau_b    = clamp_per_axis(inertia * assist_gain_k * (w_target - w_b), -torque_max, torque_max)
else:
    tau_b    = c.rot * torque_max                            # raw Newtonian: stick commands torque

F_w   = B · F_b
tau_w = B · tau_b
body.apply_central_force(F_w)      # forces are per-tick in Godot: re-apply every physics step
body.apply_torque(tau_w)
```

Sign conventions. `FlightCommand.rot` is expressed in **pilot terms**: `rot.x = +1` pitch up, `rot.y = +1` yaw
right, `rot.z = +1` roll right (clockwise as seen by the pilot looking forward). With Godot's right-handed axes and
-Z forward, a positive rotation about +X pitches the nose up, a positive rotation about +Y yaws the nose *left*, and
a positive rotation about +Z rolls *left*. `FlightModel` is the single place that converts pilot terms to body
axes: `axis_sign = Vector3(+1, -1, -1)`, so `w_target = rot * axis_sign * rate_max` and (assist off)
`tau_b = rot * axis_sign * torque_max`. Pin this with a unit test per axis; the table below is what the player must
experience:

| Stick input | Expected ship response |
|---|---|
| Right stick back | nose up (pitch) |
| Right stick right | nose right (yaw) |
| RB | roll right (clockwise as seen by pilot) |
| Left stick right | translate right; velocity vector moves right, nose does not turn |
| RT | accelerate forward; releasing RT does **not** slow the ship |

### 5.3 Integration

Jolt integrates at `physics/common/physics_ticks_per_second = 60` (semi-implicit Euler, constant force across the
tick). Rendering runs unlocked with `physics/common/physics_interpolation = true` so cameras see smooth motion.
Forces are applied in `Ship._physics_process` (not `_integrate_forces`; we do not override the integrator).

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

- `assist_on` (toggle, persisted in `Settings`, default **true**): stick deflection commands an angular *rate*;
  stick centred means "stop rotating". With the P controller above and the torque clamp, a 60 deg/s stop takes
  ~0.7 s. Pure P is enough because the plant is a double integrator with direct torque authority; add D only if
  oscillation shows up in human testing.
- `assist_off`: stick commands torque; releasing the stick keeps the ship spinning. This is the "Starfury party
  trick" mode and must feel exactly like the canon flip-and-burn.
- `brake` (hold): translational velocity is driven to zero using RCS and retro/main thrust limits. No
  "auto-hold velocity" in M1.
- Assist never touches the player's translational inputs when `brake` is false: momentum is always conserved.

### 5.6 Limits and later work

- Jolt clamps body speed (`physics/jolt_physics_3d/limits/max_linear_velocity`, default 500 m/s, and
  `max_angular_velocity`). M1 speeds stay under 200 m/s; M2+ either raises the limit or adopts a camera-relative
  velocity frame together with floating origin. If Jolt ever becomes the obstacle, the fallback is a custom
  integrator in `FlightModel` driving a `CharacterBody3D`/`Node3D`; the pure-class split (D5) makes that a
  contained change.
- No atmospheric or gravity effects, ever, in this sim.

## 6. Input

### 6.1 Gamepad mapping (all via `InputMap` actions in `project.godot`; `device = -1` = any pad)

Layout names below are the Xbox-style names Godot/SDL3 use for the standard layout; any pad SDL3 recognises
(generic XInput clones included) presents this layout. Nothing here uses Xbox-only features (no impulse triggers,
no rumble in M1, no Guide-button logic).

| Action | Pad (Godot enum) | Keyboard fallback | Type | Deadzone | Curve |
|---|---|---|---|---|---|
| `thrust_forward` | RT (`JOY_AXIS_TRIGGER_RIGHT`, +) | W | analog 0..1 | 0.05 | linear |
| `thrust_reverse` | LT (`JOY_AXIS_TRIGGER_LEFT`, +) | S | analog 0..1 | 0.05 | linear |
| `strafe_left` / `strafe_right` | Left stick X (`JOY_AXIS_LEFT_X` -/+) | A / D | analog pair | radial 0.15 | linear |
| `strafe_down` / `strafe_up` | Left stick Y (`JOY_AXIS_LEFT_Y` +/-) | C / Space | analog pair | radial 0.15 | linear |
| `pitch_down` / `pitch_up` | Right stick Y (`JOY_AXIS_RIGHT_Y` -/+; `Settings.invert_y` flips) | Up / Down arrows | analog pair | radial 0.15 | expo 1.5 |
| `yaw_left` / `yaw_right` | Right stick X (`JOY_AXIS_RIGHT_X` -/+) | Left / Right arrows | analog pair | radial 0.15 | expo 1.5 |
| `roll_left` / `roll_right` | LB / RB (`JOY_BUTTON_LEFT_SHOULDER` / `RIGHT_SHOULDER`) | Q / E | digital | - | - |
| `fire_primary` | A (`JOY_BUTTON_A`) | Left mouse / Ctrl | hold | - | - |
| `toggle_flight_assist` | B (`JOY_BUTTON_B`) | Z | edge | - | - |
| `brake` | X (`JOY_BUTTON_X`) | X | hold | - | - |
| `toggle_camera` | Y (`JOY_BUTTON_Y`) | V | edge | - | - |
| `reset_ship` | View/Back (`JOY_BUTTON_BACK`) | R | edge | - | - |
| `pause` | Menu/Start (`JOY_BUTTON_START`) | Esc | edge | - | - |
| `debug_toggle_overlay` | D-pad Up (`JOY_BUTTON_DPAD_UP`) | F3 | edge | - | - |
| `debug_toggle_fallback_mesh` | D-pad Down (`JOY_BUTTON_DPAD_DOWN`) | F4 | edge | - | - |

Sticks are read with `Input.get_vector(neg_x, pos_x, neg_y, pos_y, Settings.stick_deadzone)` (radial deadzone
with rescaling), then the expo curve `sign(x)·|x|^1.5` is applied to rotation axes in `InputAdapter`. Per-action
deadzone in the InputMap is set to 0.05 for triggers and 0.15 for stick actions so `get_action_strength` is also
sane.

Generic-pad quirks handled in `InputAdapter`/`Settings` (not in gameplay code):

- **Trigger range.** SDL3 normally reports triggers as 0..1 on `JOY_AXIS_TRIGGER_LEFT/RIGHT`; some generic pads or
  driver paths report -1..1 (rest = -1) or put triggers on a button. `InputSource` therefore also exposes
  `get_raw_axis(device, axis)`. On start-up (and on `Input.joy_connection_changed`) the adapter samples the trigger
  rest value for ~0.5 s while no action is active and stores `trigger_rest` (0 or -1, per pad GUID, in
  `Settings`); triggers are read as `clamp((raw - rest) / (1 - rest), 0, 1)` with `Settings.trigger_deadzone`
  applied afterwards. Unit tests cover both rest values.
- **Stick drift.** `Settings.stick_deadzone` default 0.15, user-adjustable up to 0.30; radial, with rescaling so
  full deflection still reaches 1.0.
- **Wrong layout.** If a pad's buttons or axes land on the wrong `JOY_*` enum, the fix is an SDL mapping string,
  not code: `Settings` reads optional lines from `user://gamecontrollerdb.txt` and applies each with
  `Input.add_joy_mapping(line, true)` before the first frame. The debug overlay shows the pad name, GUID and raw
  axis values so a user can build that line.
- **No haptics, no light bar, no motion.** Not referenced anywhere.
- **Hot-plug.** Godot handles it; the adapter only re-runs trigger calibration and the overlay updates the name.
Example serialised action (so the format is unambiguous):

```
[input]
thrust_forward={
"deadzone": 0.05,
"events": [Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":5,"axis_value":1.0,"script":null), Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)]
}
```

### 6.2 FlightCommand

```
class_name FlightCommand extends RefCounted
var thrust_fwd: float   # 0..1
var thrust_rev: float   # 0..1
var strafe: Vector2     # x right, y up, -1..1 (radial)
var rot: Vector3        # x pitch, y yaw, z roll, -1..1 (post-curve)
var brake: bool
var fire: bool
var toggle_assist: bool # edge, true for one tick
var toggle_camera: bool # edge
var reset: bool         # edge
```

`InputAdapter.sample(source: InputSource, dt: float) -> FlightCommand` is the only place that knows action names.
Tests use `FakeInputSource` with scripted values (including raw trigger axes at rest -1 and 0); the real
`GodotInputSource` is a thin wrapper over `Input`.

## 7. Rendering pipeline

### 7.1 What is a splat, what is a mesh

| Element | Representation | Why |
|---|---|---|
| Ship hull (fuselage, struts, pods, canopy exterior) | **Splats** (`HullSplats`, ~150k Gaussians) | The point of the project; GDGS re-uploads the node transform on change, so a moving/rotating body is supported. |
| Stars | **Splats** (in `SkySplats`, ~12k tiny Gaussians) | A Gaussian is the ideal star PSF; brightness/colour per splat; crisp at any resolution unlike a panorama texture. |
| Nebula | **Splats** (in `SkySplats`, ~4k large soft Gaussians) | Volumetric look for free; per-tile depth sort handles overlapping translucency. |
| Cockpit interior (frame, canopy struts, dash slab) | Mesh (`cockpit_interior.obj`) | Needs hard edges at the near plane and **depth writes** so hull splats behind the frame are rejected by the compositor's depth test; visible only in first person. |
| Thruster glow | Mesh quads/cones, unshaded emissive, additive, scaled per tick by thruster level | Per-frame intensity animation; splats are static radiance (no per-splat opacity animation in GDGS). |
| Projectiles, muzzle flash | Meshes, unshaded emissive | Tiny, fast-moving, short-lived; spawning/destroying splat nodes per shot would churn GPU buffers. |
| Collision | `CollisionShape3D` primitives from hardpoints JSON | Splats have no surface; GDGS's collision generator is editor-only and overkill for a handful of boxes. |
| Hull fallback | Mesh (`starfury.obj`, hidden) | Debug comparison and the fallback path (§7.4). |

### 7.2 Compositing order (GDGS Compute backend)

1. Godot renders opaque meshes (cockpit interior, fallback meshes if visible) -> colour + depth.
2. GDGS `CompositorEffect` runs at `EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT`: projects all `GaussianSplatNode`s
   (hull + sky) in one pass, radix-sorts `(tile | depth)` keys, blends front-to-back, depth-tests against the
   resolved scene depth (`depth_bias`, `depth_test_min_alpha`, `alpha_cutoff` are tunables on the effect).
3. Godot renders transparent meshes (thruster glow, projectiles, flashes) on top. Correct for additive effects
   even when the emitter sits inside hull splats.
4. Post: glow/bloom, tonemap. Keep glow modest so star splats do not bloom into blobs.

The sky node sits far away (radius 20 km) and follows the camera origin each frame (`SkyFollower`,
`top_level = true`), so it never parallaxes and never collides with the depth of nearby meshes. Camera `near =
0.05 m` (cockpit), `far = 50 000 m`; Forward+ uses reverse-Z, so this range is fine.

Raster backend differences (automatic fallback on GPUs without compute or on Mobile/Compatibility): splats become
sorted `MultiMeshInstance3D` quads in the normal transparent pass with hardware depth test; sort can lag 1-2
frames (mild popping on fast rolls). Acceptable; nothing in gameplay depends on the backend.

### 7.3 Lighting

Splats are unlit: the generators bake a "studio" light rig **in ship-local space** (hemisphere ambient + two
directional lights) into the DC colour, so shading rotates with the ship. Meshes are lit by `KeyStar`
(`DirectionalLight3D`) plus a dark ambient. To avoid a visible mismatch, M1 mesh materials are either unshaded
emissive (glow, projectiles) or dim neutral (cockpit interior). GDGS relighting (bakes a lighting proxy in the
editor, lights splats from scene `Light3D`s) is the M2 option for consistent lighting.

### 7.4 Risks and fallback plan

| Risk | Likelihood | Mitigation / fallback |
|---|---|---|
| GDGS compute backend fails on the tester's GPU/driver | low-med | `gdgs/rendering/backend = Auto` falls back to Raster. `SplatStatus` logs the active backend in the overlay. |
| Neither backend initialises, or splats look wrong (orientation, centring) | low | `SplatStatus` shows `HullMeshFallback` and swaps `Environment.sky` to `sky_panorama.png` (`PanoramaSkyMaterial`), generated by `build_sky.py --panorama`. The game is fully playable on meshes. |
| Hull splat quality from surface sampling looks "dotty" at close range (cockpit view of the nose) | medium | Tune splat spacing/overlap (k≈1.4) and add a second denser sampling pass near the cockpit; if still poor, train with Brush on a GPU machine from renders of `starfury.obj` (M2). |
| Sorting/perf regressions with sky + hull in one pass | low | Budget ≤ 400k splats; measured 6M at interactive rates in GDGS showcase. |
| GDGS breaking change on a Godot bump | low | Versions pinned; CI runs `--import` + resource assertions headless. |
| Splat path blocks M1 entirely | low | Acceptance criteria are written so that mesh fallback + panorama still satisfies "flyable ship in a starry background with nebula"; M1 is then marked "splats pending" and the splat work moves to M1.5. |

## 8. Camera

- **Cockpit**: `Camera3D` glued to `CockpitAnchor` (hardpoint) via `RemoteTransform3D`; FOV 75°. The hull splats
  of the nose and struts are visible, as in the real Starfury. Cockpit interior mesh visible.
- **Chase**: `top_level` camera. Target pose each frame from `ChaseCameraMath.compute(ship_xform, ship_velocity,
  dt)`: position = `ship.origin + ship.basis * Vector3(0, 2.5, 9.0)` (behind and above the nose), orientation looks
  at `ship.origin + ship.forward * 40`. Smoothing: exponential approach with half-life 0.08 s for position and
  slerp with half-life 0.12 s for rotation, computed with `exp2(-dt / half_life)` so it is frame-rate independent.
  The camera follows *orientation*, not velocity, so drifting sideways is visible, which is the point of a
  Newtonian sim; a velocity-vector marker is an M2 HUD item.
- Toggle via `toggle_camera`; `Settings.camera_default`. `CockpitInterior.visible == (mode == COCKPIT)`.
- Camera near/far as in §7.2. Physics interpolation on so the chase camera's `_process` reads interpolated
  transforms (`global_transform` of a RigidBody3D is interpolated when the project setting is on).

## 9. Asset pipeline

All generators are deterministic (`--seed`, default 42) CPU Python and run in seconds. They write into
`assets/generated/` (gitignored) and a `manifest.json` per asset (counts, AABB, centroid, seed, generator version)
that Godot-side tests compare against.

### 9.1 Ship (`tools/starfury/`)

1. `spec.py`: parametric description, Godot frame, metres. Parts: central fuselage (tapered box + cockpit
   canopy), four struts in an X, four engine pods (cylinders with rear main nozzle and forward retro nozzle, plus
   small lateral RCS nozzles), two underslung gun barrels. Each part: primitive, transform, albedo colour, name.
   Hardpoints: `cockpit_camera`, `chase_anchor`, `center_of_mass`, `muzzles[]`, `thrusters[]` (position,
   body-frame direction, tags: `main`, `retro`, `rcs_x+`, `pitch_up`, ...), `collision[]` (boxes/capsules).
2. `build_starfury.py`:
   - Tessellate primitives -> `starfury.obj` + `.mtl` (fallback mesh; also future multi-view render source).
   - Area-weighted stratified surface sampling at spacing `s` (default 0.06 m -> ~150k points); per point: normal,
     tangent frame -> quaternion; scales `(k·s, k·s, 0.03·s)` with `k = 1.4`; colour = albedo × baked local
     lighting; opacity 0.98 (stored as logit); SH degree 0 only (`f_dc_*`), `f_rest_*` omitted.
   - `cockpit_interior.obj`: frame ring, canopy struts, dash slab; interior-facing normals.
   - Re-centre **everything** (splats, meshes, hardpoints) on the splat centroid, so GDGS's unconditional import
     centring is a no-op and the hardpoints frame equals the rendered frame.
   - Write PLY in GDGS/3DGS orientation (apply Rz(180°): negate x, y; rotate quaternions) so the
     `GaussianSplatNode` can stay at identity (GDGS applies its own Rz(180°) correction to identity nodes).
   - `manifest.json`: point count, AABB (Godot frame), centroid before re-centring, seed, spacing, tool version.
3. Standard 3DGS binary little-endian PLY writer (`tools/common/ply_writer.py`): properties
   `x y z nx ny nz f_dc_0 f_dc_1 f_dc_2 opacity scale_0 scale_1 scale_2 rot_0 rot_1 rot_2 rot_3` with
   `rot_* = (w, x, y, z)`, `scale_* = ln(scale)`, `opacity = logit(alpha)`, `f_dc = (rgb - 0.5) / 0.28209479`.

### 9.2 Sky (`tools/environment/build_sky.py`)

- Stars: N≈12 000 on a sphere of radius R=20 000 m; magnitude distribution ~ `10^(0.5·m)` with a Milky-Way band
  density boost; colour from a blackbody temperature table; size so that bright stars ≈ 2-3 px at 1080p/75° FOV
  (angular radius ≈ 0.6 mrad -> 12 m at R), dim stars smaller; isotropic Gaussians; opacity 1.0.
- Nebula: N≈4 000 large (300-2 000 m) soft Gaussians clustered by a few fBm-weighted blobs in one sky region
  (~40° across), two-tone palette (e.g. teal/magenta), opacity 0.02-0.08, slight anisotropy for filaments.
- `--panorama sky_panorama.png`: 4096×2048 equirectangular render of the same catalogue (fallback only).
- Output `sky_splats.ply` (same writer and orientation convention) + `manifest.json`.

### 9.3 Running

`scripts/gen_assets.sh` runs both generators; `scripts/run_tests.sh` runs `python3 -m unittest discover tools/tests`
first. CI regenerates assets on every run (they are not committed). A human opening the project in the editor
runs `scripts/gen_assets.sh` once (Python 3.11+ and NumPy are the only requirements).

## 10. Scale, units, floating origin

1 unit = 1 m, SI. Ship ≈ 10 m long, play area ≈ ±20 km (float32 position error ≈ 2 mm there; fine). Sky radius
20 km around the camera, independent of ship position. Floating origin is **not** in M1 but the design leaves the
hooks: all world content is under `Main` (ship, projectiles, future NPCs), the sky is camera-relative already, and
velocities are never derived from positions. M3 adds a `WorldShifter` that rebases every child of `Main` when the
camera is > 10 km from origin (teleporting Jolt bodies via `global_position` keeps their velocities). A
double-precision engine build is a last resort (needs custom Godot and GDGS shader review).

## 11. Performance targets (M1)

- 1920×1080, 60 fps sustained on a GTX 1060 / RX 580-class Vulkan GPU with ≤ 400k splats on screen.
- Physics 60 Hz fixed; `_physics_process` for the ship < 0.2 ms.
- Input-to-thrust latency: one physics tick after the input event.
- Startup to flyable < 5 s after import (first import of the PLYs may take longer; that is a one-time cost).

## 12. Testing strategy

| Level | Tool | Runs where | Covers |
|---|---|---|---|
| Python unit | `unittest` | container, CI | PLY header/field layout, counts, determinism (hash of output), frame conversion, hardpoints schema, centroid ≈ 0 |
| GDScript unit | GUT `tests/unit` | container, CI | `FlightModel` (forces, torques, clamps, sign table in §5.2), `FlightAssist` (converges, never exceeds limits, brake asymmetry), `InputAdapter` (radial deadzone, expo, edges, invert-Y, trigger rest -1 vs 0 normalisation, SDL mapping lines parsed), `ChaseCameraMath` (frame-rate independence) |
| Headless integration | GUT `tests/integration`, `--headless` | container, CI | ship scene instantiates; RigidBody3D reaches `F/m·t` velocity and keeps it (damping guard); assist stops a 60°/s spin within 1.5 s; projectile inherits ship velocity and despawns; `GaussianResource.point_count > 0` and AABB matches manifest for both PLYs; `SkyFollower` tracks camera; camera toggle flips `current` and cockpit visibility; `main.tscn` runs 120 frames with `--quit-after` and no script errors |
| Human acceptance | checklist in the milestone doc | Linux/Vulkan GPU + generic XInput pad | splat appearance, compositing, feel, performance, controller behaviour, trigger/deadzone calibration |

Rules: every pure class gets unit tests in the same PR; every scene gets at least an instantiate-and-run test;
anything that depends on a GPU is marked `(H)` in acceptance criteria and is never faked in CI.

Commands (also in `scripts/run_tests.sh`):

```
python3 -m unittest discover -s tools/tests -v
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
  `projectile_fired`); connect in `_ready`, never in `_process`.
- Pure logic classes extend `RefCounted` and take plain data in/out. Nodes do not compute physics or parse input.
- No `get_node("../..")` upward reaches; parents pass dependencies down via exported `NodePath`s or setters.
- Physics in `_physics_process`, visuals in `_process`. Never apply forces from `_process`.
- Tunables live in `Resource`s (`ShipSpec`) or `Settings`, not as literals in node scripts.
- Comments explain *why*; the sign conventions in §5.2 are documented at the top of `flight_model.gd`.
- Python: `ruff`-clean (default rules), type hints, `argparse` CLIs, `--seed`, pure functions; no Blender
  dependency.
- Commits: imperative subject, task id prefix when applicable (`M1-T06: flight model and assist`).
