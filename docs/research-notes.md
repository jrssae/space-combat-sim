# Research notes (verified 2026-10-19)

Facts the architecture relies on, with how each was checked. Re-verify anything older than a few months before
bumping versions. "Container" means the Claude cloud Linux container used for implementation sessions.

## Engine

| Item | Verified value | How |
|---|---|---|
| Latest stable Godot | **4.7.2-stable** (4.7 stable 2026-06-19; 4.7.2 is a maintenance release) | GitHub release asset exists and runs; `4.7.3-stable` and `4.8-stable` assets return 404 |
| Linux editor binary | `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip` (77,860,424 bytes) | Downloaded in the container in 3.4 s |
| SHA-256 of that zip | `cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4` | `sha256sum` after download |
| `--version` output | `4.7.2.stable.official.ed1daf0bf` | Ran `--headless --version` in the container (no GPU, no X) |
| Default renderer | `forward_plus` | `ProjectSettings.get_setting("rendering/renderer/rendering_method")` headless |
| 3D physics default | Jolt is the default for **new** projects since 4.6; a hand-written `project.godot` reports `physics/3d/physics_engine = "DEFAULT"`, so **set `"Jolt Physics"` explicitly** | 4.6 release coverage; headless probe |
| Headless physics | RigidBody3D forces/torques integrate normally under `--headless` with both Jolt and GodotPhysics3D | Scratch SceneTree script: 50 kN on 10 t for 60 ticks gave 4.76 m/s |
| Damping gotcha | With `linear_damp = 0` on the body, velocity still decayed 4.76 -> 4.32 m/s over 1 s: project defaults `physics/3d/default_linear_damp = 0.1` / `default_angular_damp = 0.1` are *combined* with the body value | Same probe; `exp(-0.1)` matches |
| Gamepad backend | Godot 4.5+ uses **SDL3** for controllers on Windows/macOS/Linux; Xbox pads map to the standard `JOY_AXIS_*` / `JOY_BUTTON_*` enums | Godot docs "Controllers, gamepads, and joysticks" (4.5/4.7) |
| Enum values | LX=0 LY=1 RX=2 RY=3 LT=4 RT=5; A=0 B=1 X=2 Y=3 BACK=4 GUIDE=5 START=6 LS=7 RS=8 LB=9 RB=10 DPAD U/D/L/R=11/12/13/14 | Printed from the 4.7.2 binary |
| Useful CLI flags | `--headless` (= `--display-driver headless --audio-driver Dummy`), `--path`, `-s/--script`, `--import` (editor-only: imports all resources and quits), `--quit-after <n>`, `--check-only`, `--log-file`, `--fixed-fps` | `--help` of the 4.7.2 binary |

## Gaussian splat rendering in Godot

| Candidate | Status (2026-10) | License | Notes |
|---|---|---|---|
| **GDGS** `ReconWorldLab/godot-gaussian-splatting` | v3.3.0 (2026-07-30), active, 1 open issue | MIT | Pure GDScript + GLSL/gdshader (55 .gd, 8 .glsl, 2 .gdshader, no GDExtension), 692 KB. Godot 4.3+, 4.7 fix landed in 3.1.0. Two backends: **Compute** (Forward+, per-tile radix sort, composites via `CompositorEffect` at `EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT` against resolved depth) and **Raster** (any renderer, `MultiMeshInstance3D` quads, threaded CPU sort that can lag 1-2 frames). Multiple `GaussianSplatNode`s, instancing, per-node transforms re-uploaded on `NOTIFICATION_TRANSFORM_CHANGED`. Imports `.ply`, `.compressed.ply`, `.splat`, `.sog` (v2), `.glb` (KHR_gaussian_splatting), `.usdz`. Headless CI in its own repo runs `--import` + script tests. |
| `haztro/godot-gaussian-splatting` | standalone viewer for 4.6 | MIT | Not an addon; single `.ply`; no compositing story |
| `4321ba/GodotGaussianSplattingNodes` | thesis WIP built on GDGS layout | - | Not production |
| `klausi3D/godotGS` | engine fork, alpha | - | Requires a custom engine build |

GDGS behaviours that shape our pipeline (read from the v3.3.0 source):

- `GaussianSplatNode._enter_tree()` applies a one-time **180 deg rotation about Z** when the node's basis is identity (`get_model_orientation_correction()`), to turn COLMAP-style Y-down data into Y-up. Our generators therefore write PLY data pre-rotated by Rz(180 deg) (negate x and y) so the node can stay at identity.
- `GaussianResourceBuilder.build()` **unconditionally subtracts the mean position** from all splats (`_get_import_options()` returns `[]`). Our generators re-centre every output (splats, fallback mesh, hardpoints) on the splat centroid so this is a no-op.
- `standard_ply_decoder.gd` reads properties with defaults, so `f_rest_*` may be omitted (SH degree 0 files import). `opacity` is passed through sigmoid and `scale_*` through `exp`, i.e. the standard 3DGS PLY encoding (store logit opacity and log scale).
- `GaussianResource` exposes `point_count`, `aabb`, `xyz` -> usable for headless assertions.
- Node `@export`s: `gaussian: GaussianResource`, relighting group (`lighting`, `relight_enabled`, `relight_cast_shadows`, ...). Relighting needs a lighting proxy baked in the editor; not used in M1.
- Project setting `gdgs/rendering/backend` = `Auto` | `Compute` | `Raster`, read at startup, falls back to the other backend on init failure.

## Splat asset production

| Tool | Version | License | Headless/CPU? | Verdict for M1 |
|---|---|---|---|---|
| Direct mesh-to-splat sampling (own Python) | n/a | GPL-3.0 (ours) | Yes, numpy only, seconds | **Primary**: deterministic, no GPU, no training |
| Brush `ArthurBrussee/brush` | v0.3.0 (2026-09) | Apache-2.0 | GPU via wgpu (Vulkan/Metal/DX12); CLI with `--export-path`, `--export-every`; no documented CPU path | Optional M2+ polish path on a GPU machine |
| OpenSplat `pierotofy/OpenSplat` | active | AGPL-3.0 | CPU possible but "~100x slower" | Usable as an external tool (AGPL only covers the tool); too slow for CI |
| gsplat / nerfstudio | active | Apache-2.0 | CUDA | GPU machine only |
| `nianticlabs/spz` format | - | MIT | - | Not needed; GDGS has no `.spz` import |

## Testing frameworks

| Framework | Version | License | Headless CLI |
|---|---|---|---|
| **GUT** `bitwes/Gut` | **v9.7.1** (branch `godot_4_7`, targets Godot 4.7.x) | MIT | `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=reports/gut.xml`; exits 1 on failure. Options verified in `addons/gut/cli/gut_cli.gd` |
| gdUnit4 `godot-gdunit-labs/gdUnit4` | v6.2.2 (2026-10-07) | MIT | `gdUnit4-action@v1`; has had headless input-handling caveats (historically needed xvfb) |

## Container findings (implementation sessions)

- `github.com/<org>/<repo>/releases/download/...` **works** through the proxy (Godot 4.7.2 zip and export templates both 200).
- `git clone --depth 1 --branch <tag> https://github.com/...` **works** (GUT v9.7.1 and GDGS v3.3.0 cloned in ~1.4 s each).
- `github.com/<org>/<repo>/archive/refs/tags/*.zip` (codeload) returns **403**. Do not use archive zips.
- `api.github.com` REST and `gh` GraphQL are blocked unless the repo is attached with `add_repo`. Not needed for setup.
- `docs.godotengine.org`, `godotengine.org`, `*.readthedocs.io`, `*.github.io` are **not reachable** from the container (403/ENOTFOUND). Read docs via `raw.githubusercontent.com` (e.g. `godotengine/godot-docs`) or rely on these notes.
- Tools present: `python3` 3.13 with `numpy` 2.5 and `Pillow` 12.3, `curl`, `wget`, `unzip`, `git`, `git-lfs`, `xvfb-run`/`Xvfb`, `libvulkan.so.1`, `libGL.so.1`, X11 client libs. No GPU, so **no splat rendering can be verified in the container**. 4 CPUs, 15 GB RAM.
- Godot export templates (`Godot_v4.7.2-stable_export_templates.tpz`) are downloadable but not required for M1 (we run from the editor binary).

## Long-term design research (verified 2026-10-19, Godot 4.7.2 source and GDGS v3.3.0 source)

| Question | Finding | How |
|---|---|---|
| Official double-precision builds? | **None.** `…/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.double.zip` and variants return 404. A double build needs `scons precision=double` (SConstruct adds `REAL_T_IS_DOUBLE`, binaries get a `.double` suffix) for the editor *and* export templates | HEAD requests; `SConstruct` lines 192, 596, 1043 at tag `4.7.2-stable` |
| Jolt in a double build | Supported: `modules/jolt_physics/SCsub` appends `JPH_DOUBLE_PRECISION` when `precision == "double"` | sparse clone of `godotengine/godot` at `4.7.2-stable` |
| Jolt limits | `physics/jolt_physics_3d/limits/max_linear_velocity` default 500 m/s (range hint allows greater); `max_angular_velocity` default 2700 °/s; `max_bodies` 10240 | `modules/jolt_physics/jolt_project_settings.cpp` |
| GDGS at large coordinates | Not safe in any build: the compute registry packs model matrices (`PackedFloat32Array`) and the camera view matrix as float32 separately, so world-space precision is lost far from the origin. Floating origin is required regardless | `runtime/render/compute/gaussian_scene_registry.gd`, `gaussian_renderer.gd` |
| GDGS LOD / streaming | No LOD (upstream proposal: issue #32). Changing a node's `gaussian` calls `_sync_scene_resources()`, which re-merges and re-uploads all nodes' point data. Hidden nodes early-out in `gsplat_projection.glsl` (`if (is_visible < 0.5) return;`) but are still dispatched; the visibility flag lives in the per-node transform upload | GDGS v3.3.0 source |
| GDScript precision | GDScript `float` is 64-bit in every build; `Vector3` is float32 in official builds. Universe coordinates in script therefore cost nothing if stored as `float`s, not `Vector3` | Godot GDScript reference (known behaviour) |

## Offline TTS candidates (verified 2026-10-19, not dependencies yet)

| Candidate | Licence | Notes |
|---|---|---|
| Piper, `rhasspy/piper` | MIT | Archived: README says "Development has moved: https://github.com/OHF-Voice/piper1-gpl" |
| Piper, `OHF-Voice/piper1-gpl` (current) | **GPL-3.0** (`COPYING`) | "A fast and local neural text-to-speech engine that embeds espeak-ng for phonemization". GPL-3.0 matches this project. Voice models are separate downloads, each with its own `MODEL_CARD` licence ("Some voices may have restrictive licenses"); pick voices per card. `huggingface.co` (voice hosting) is **not reachable** from the container (CONNECT 403), so voice licences must be checked from a workstation |
| Kokoro, `hexgrad/kokoro` | Apache-2.0 (code; README: "Apache-licensed weights") | 82M-parameter model; uses espeak-ng for fallback phonemes |
| espeak-ng | GPL-3.0 | Rule-based formant synthesis; robotic, but fully code-generated with no model weights (a fit for radio chatter) |

## Debug console facts (verified 2026-10-19, Godot 4.7.2 source)

| Item | Finding | Source |
|---|---|---|
| Console key | `Key.KEY_QUOTELEFT = 0x0060` (96), the ` key; match on `physical_keycode` so it stays the same key on non-US layouts | `core/os/keyboard.h` |
| Engine messages into the console | `Logger` class ("Custom logger to receive messages from the internal error/warning stream") registered with `OS.add_logger()` / `OS.remove_logger()`. `_log_error` and `_log_message` "will be called from threads other than the main thread, possibly at the same time", so guard with a `Mutex` | `doc/classes/Logger.xml`, `doc/classes/OS.xml` |
| Command-line arguments | Pass custom arguments after `--` and read them with `OS.get_cmdline_user_args()`; the engine ignores them by design | `doc/classes/OS.xml` |
| Device polling | `Input.get_joy_axis`, `Input.is_joy_button_pressed`, `Input.is_physical_key_pressed`, `Input.is_mouse_button_pressed` exist, so actions can be evaluated per device class (needed to mask the keyboard while the console is open, because `Input` action state ignores GUI focus) | `doc/classes/Input.xml` |
| Slow motion | `Engine.time_scale` scales the `delta` of `_process` and `_physics_process`; above 1.0 each physics tick stretches (less precise), so the console caps it at 1.0 | `doc/classes/Engine.xml` |

## Software rendering in the container (verified 2026-10-20)

- `apt-get install mesa-vulkan-drivers xvfb` works through the proxy and provides llvmpipe (Vulkan 1.4, CPU).
  `glslang-tools` gives `glslangValidator` for offline GLSL checks (strip Godot's `#[compute]` first line).
- `scripts/capture.sh "<console commands>"` runs the real game under `xvfb-run` with `--rendering-driver vulkan`;
  the console's `screenshot <path>` command saves frames. About 1 FPS at 1280x720.
- llvmpipe runs compute with 8-wide subgroups. GDGS's radix sort needs 32+, so the Compute backend declines
  (local patch) and GDGS renders through its Raster backend: good for geometry, layout, cockpit framing and
  compositing; Compute-only artifacts still need the human tester's GPU.
