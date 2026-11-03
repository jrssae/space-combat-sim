# Scaling to 500 ships: every route, with evidence

Research and analysis only, written 2026-11-03 on branch `m4` at `681fb7b`, after the T06 report paused M4 at 45 ships (Q11).
Nothing here was built, run or benchmarked. Every timing comes from the M4 Cycle log (debug editor build unless it says
release) and the AC6 render check; every outside fact carries its source and date. Figures marked "estimate" are my
reasoning from those numbers, each with a confidence that it holds within about a factor of two.

Short version: the costs that stop us at 45 ships are in our own GDScript, not in Godot's engine core. Every engine on the
list would need the same thing we can do inside Godot today, which is moving the per-ship simulation into native,
data-oriented code. Leaving Godot buys nothing that `gdext` does not already give, costs a rewrite of about 27 000 lines of
game code, 39 000 lines of tests and the splat renderer fork, and in four of the engines the licence makes a GPL-3.0 project
impossible anyway. The honest route to 500 is three phases inside Godot: finish the native cycles to 100, move ship state
into Rust arrays with a node diet to 200 to 300, and add a low-attention simulation tier so that 500 ships live in the world
while about 100 to 150 fight at full fidelity near the player. Whether 500 ships in one furball at 60 FPS on vsync is a
goal at all is the first thing to decide: the setting (three squadrons of 12 at Babylon 5) does not need it, and the render
side would need as much work as the tick.

## 1. The arithmetic of 500

### 1.1 Where a tick goes today

Furball, 100 ships, final measurements (M4-T06m, mean ms per tick, debug editor build, tick mean 16.00 ms, 45 ships thinking
per tick because of the think rate):

| stage | ms at 100 | us per ship | ms at 50 | growth 50 to 100 | scales with |
|---|---|---|---|---|---|
| AI (perception, brains, avoidance) | 6.16 (scan 2.57) | 62 | 3.31 | 1.86x | N (nearest-k caps the per-contact part; the think rate halves the far ships) |
| flight (`Ship._physics_process`, `FlightModel`, bolts, `Main`) | 3.56 | 36 | 1.89 | 1.88x | N |
| hit resolver (bolts against hulls) | 2.52 | 25 | 0.83 | 3.0x | bolts times ships, so about N squared (bolts in flight grow with N) |
| Jolt step and body sync | 1.86 (sync 0.35) | 19 | 1.38 | 1.35x | N, Jolt's own step is threaded (section 3.6) |
| targeting | 1.00 | 10 | 0.52 | 1.92x | N |
| ram resolver (after the broad phase) | 0.71 | 7 | 0.38 | 1.87x | N |
| late, other | 0.15 | 2 | | | |
| **tick** | **16.00** | **160** | **8.43** | | |

The release export runs the GDScript stages 1.2 to 1.3 times faster (cycle 2), so a player's build sits at about 125 us per
ship at 100.

### 1.2 What 500 ships are allowed to cost

The budget is a tick median of 8 ms headless. That is **16 us per ship per tick** for everything at 500 ships: perception,
decision, flight, physics, bolts, targeting, the rebase. The AC6 check adds a harder constraint the headless budget hides: at
45 ships the windowed game runs at 52 FPS with a 7.4 ms tick plus 1.4 ms of renderer CPU time plus the rest of the frame.
If the window is to hold 60 FPS at the headline count, the tick has to leave the main thread about 10 ms, so a realistic
tick target at 500 is nearer **5 ms, or 10 us per ship**, unless rendering leaves the main thread (section 3.8).

For scale: a GDScript call costs 0.08 us, a native call 0.12 to 0.7 us (cycle 4), a GDScript distance check about 0.3 us,
the same check in Rust about 4 ns, a brain's fixed cost per think 25 to 30 us (native research, section 4), and `Ship`'s
force step 36 us per ship. So **no per-ship GDScript at all fits in 10 to 16 us**: one think at the far rate of 20 Hz
already averages 8 to 10 us per ship per tick. This is the single arithmetic fact that decides every option below.

### 1.3 Projection to 500 in the current code

Linear stages times five, the hit resolver with a broad phase (so proportional to bolts, about 1 500 in flight), Jolt from
the handoff's estimate:

| stage | at 500, debug (estimate) | at 500, release | needs to fall to (5 to 8 ms tick) |
|---|---|---|---|
| AI | 31 ms | 25 | 2 to 3 ms |
| flight | 18 | 14 | 1 to 1.5 |
| hit resolver (with a bolt broad phase in GDScript) | 13 | 10 | under 1 |
| Jolt and sync | 9 | 8 | 1 to 2 |
| targeting | 5 | 4 | under 0.5 |
| rams | 4 | 3 | under 0.5 |
| **tick** | **about 80 ms** | **about 64** | **5 to 8** |

The tick must fall by a factor of 8 to 13 (confidence 80 % that the factor is between 6 and 16). Cycles 1 to 4 took the
100-ship tick from 109 to 16 ms, a factor of 7, by removing quadratic work. There is no quadratic work left to remove: what
remains is linear GDScript, and the only ways to divide linear GDScript by ten are native code, fewer ships doing it, or
doing it less often.

Three things scale with N squared or with bolts times ships and must have a broad phase before 500 whatever else is done:
the hit resolver and `incoming_fire` (bolts times ships), the ram resolver's residual (done, cycle 2), and perception (done,
native grid, cycle 4).

### 1.4 The costs the tick does not show

- **Nodes.** A Starfury is 108 nodes (§14.1). 500 ships are about 54 000 nodes. The rebase walks every ship's nodes:
  T14 estimated about 12 ms of shift at 500, against a 16.7 ms rebase-tick budget that also holds the tick itself. The
  body sync writes each Jolt body's transform into its node and propagates it down the children every tick. The 108 nodes
  per ship are a Godot cost that no native code reaches; only a node diet does (section 3.5).
- **Render CPU.** 1.4 ms at 45 ships, 0.8 at 25 (AC6), so about 30 us per ship: 1 201 draw calls at 45 ships, about 27 per
  ship (the depth proxy, eight plumes, lights, nav lights, chunks). At 500 ships that is about 15 ms of renderer CPU time
  and 13 000 draw calls, which alone breaks 60 FPS (estimate, 70 %).
- **Splats.** LOD0 243 728, LOD1 60 956, LOD2 15 210, LOD3 3 718 (`docs/assets-starfury.md`). 500 ships all at LOD3 are
  1.86 M splats, inside the 2 M visible budget; with 50 near ships at LOD1 and 450 at LOD3 it is 4.7 M, so the
  `LodSwitcher` would step most of the fight down to LOD3 and the renderer would clip the rest. The GPU took 4.9 ms at
  1.09 M visible splats (AC6), so about 8 to 9 ms at the full 2 M budget (estimate, 60 %): it fits 16.7 ms only if the CPU
  side also fits.
- **Pool load.** 185 ms at 100 ships headless; about 1 s at 500, a load-time matter for M5, not a tick matter.

So "500 ships" is two problems of the same size: a tick ten times cheaper, and a frame whose per-ship render and node cost
is ten times cheaper. Section 2 treats the tick; section 3.7 treats the frame. An engine change would have to win both.

## 2. Options inside Godot

### 2.1 The remaining cycles (T06 candidates 1 to 4)

Threads inside the native perception and avoidance (N3), a bolt broad phase for the hit resolver and `incoming_fire`, the
flight force step in native code (N4), and a cheaper per-tick gather. The T06 report's own numbers: about 9 ms off the 16
ms tick at 100, so 100 ships near 8 ms headless in the debug build.

- Evidence: the four stages are 6.2, 2.5, 3.6 and 2.4 ms at 100; six performance cores idle; the native call cost is
  measured.
- Gain: headline 45 to about 100 (confidence 70 %). Toward 500: the AI's brains (about 3.4 ms at 100, fixed cost per think
  in GDScript) and the `Ship` adapter stay, so the projection at 500 is still about 35 to 45 ms (estimate). These cycles
  reach 100, not 500.
- Cost: four cycle-sized tasks, the pattern is in place (N0, N1). Risk: parity for N4 (the flight maths); the brains stay the
  largest GDScript cost.

### 2.2 A data-oriented simulation core in native code (ships as arrays)

Move every per-ship, per-tick computation into the Rust crate as struct-of-arrays state: perception (done), avoidance and
the fire lane (N2), the brains (the 3 000 lines of behaviours, profiles and temperaments), the flight model and speed
governor (N4), bolts and the hit sweep (N5), the ram broad phase and sweeps. GDScript keeps the orchestration, the console,
settings, spawning, wings, waves, missions, HUD and visuals; nodes exist for what is rendered or collides; the AI reads a
per-tick snapshot and writes commands into arrays that one call per tick applies.

- Evidence: cycle 4 measured the seam (0.7 us per call, 4 ns per point); the native research estimated 1 to 2 us per ship
  for flight and about 5 us for a brain in native code; `AiPilot`, `FlightModel`, `SweepMath` and the resolvers are already
  pure `RefCounted` classes with 2 259 GUT tests that pin their behaviour, so a port has its oracle.
- Gain (estimate): per ship per tick about 1 us perception, 3 to 5 us brain, 1 to 2 us flight, 1 to 2 us bolts, 0.5 us
  bookkeeping, so 7 to 10 us single-threaded, or 2 to 4 us with the AI across six cores (N3's determinism rules). At 500
  that is 3.5 to 5 ms single-threaded and 1.5 to 2.5 ms threaded, before Jolt and the node sync. Confidence 55 % that the
  tick at 500 lands under 8 ms headless with Jolt kept, 65 % with section 2.4's physics changes.
- Cost: 10 to 15 PR-sized tasks (estimate), the brains the largest and the riskiest: they roll seeded dice
  (`hash([seed, "attack"])`) and mix 32-bit vectors with 64-bit scalars, so bit-identical outcomes are not cheap there. Q9
  already allows later ports to differ within a stated tolerance; the tolerance and the tests that measure it must be
  agreed first (section 5).
- Risk: medium. The architecture's "pure logic in `RefCounted`, nodes are adapters" rule survives, with the pure classes
  becoming facades over native arrays as `ContactScan` already is.

### 2.3 Simulation level of detail (a low-attention tier)

Ships beyond the player's attention (out of sensor range, or beyond a radius such as 10 km) stop being full `RigidBody3D`s
with 108 nodes and a 60 Hz brain. They become rows in the native arrays: a 6DOF state integrated by the native flight model
at 10 to 20 Hz from their last command, a brain that thinks at 2 to 5 Hz against the same contact grid, bolts resolved
statistically (a to-hit roll from the fire gate's geometry and the shooter's accuracy, damage applied, no bolt entities),
and a rendered proxy (a single LOD3 splat node or a MultiMesh dot, section 3.7). When one comes within range it is promoted:
a pool ship takes its state, Jolt gets a body, the full brain resumes with the tier's last decision. This is the design
most space games use for large fleets: X4 runs "high attention" near the player and "low attention" elsewhere, lowering the
precision and rate of the simulation for objects outside the player's attention
([Egosoft developer on Steam, terms](https://steamcommunity.com/app/392160/discussions/0/6664812048260991709);
[PC Games Hardware on the low-attention sim, 2024](https://www.pcgameshardware.de/X4-Foundations-Spiel-61270/Specials/Timelines-DLC-Update-Vulkan-Tech-Test-Release-1449923/galerie/3896065/);
[Egosoft 6.00 notes on low-attention combat, 2022-12](https://www.egosoft.com/news/archive/2022December_en.php)), and the
roadmap's own on-rails warp (M9) already freezes Jolt bodies and propagates ships by the gravity integrator.

- Evidence: the think rate (cycle 3) is the first step of this tier and gained 11 ms at 100; its cost was a 13 to 21 % drop
  in hits for far ships, which the maintainer accepted. Spread's groups 20 km apart show what the world looks like: most
  ships never see the player's fight.
- Gain: the tick scales with the near count, not N. With about 100 to 150 ships at full fidelity (section 2.2's costs) and
  350 to 400 in the tier at about 0.3 us per ship per tick (estimate), 500 ships in the world cost what 150 cost.
  Confidence 80 % that this reaches "500 in the world, 100 to 150 in the fight" within budget once 2.2 is in place; it does
  nothing for "500 in one furball".
- Cost: 4 to 6 tasks (the tier's integrator and brain cadence, promotion and demotion with pooled bodies, statistical
  fire, the render proxy, tests that the tier's outcomes stay within a tolerance of the full simulation over a seeded
  fight).
- Risk: behaviour. The rule "an AI may think less often; its ship never skips physics" (M4 rules, §15.16) holds in letter
  (the tier integrates forces every one of its steps) but the maintainer must accept lower-rate physics for far ships, and
  a promotion must never pop (position, velocity and command carried over exactly). Far fights resolved statistically must
  be tuned so that a squadron out of view wins or loses at the same rate as one in view.

### 2.4 Physics changes

Four independent levers, cheapest first:

1. **Collision layers.** Ships pair-test ships, bolts are not Jolt bodies, so the broad phase is cheap already; the gain
   is at 300 and up (T06 candidate 5, 30 %).
2. **Simpler shapes and no physics interpolation on far ships.** Compound convex shapes from hardpoints are already
   simple; interpolation costs a per-node reset at every rebase.
3. **Own integrator for ships, Jolt for the player and near contacts only.** The project already does its own swept hit
   tests (`SweepMath`, `ConvexSweep`) and its own ram sweeps; Jolt contributes integration, contact reports for
   `RamTracker.keep_touching`, and the body sync. A semi-implicit 6DOF integrator in Rust (inertia tensor from the
   hardpoints, forces at hardpoint positions as now) costs well under 1 us per ship and writes transforms straight into the
   rendered proxies. D4 chose "no custom integrator unless Jolt limits block us" (§5.6); at 500 ships the limit is the
   per-body sync and node propagation, not Jolt's solver, so this is a contract change for the maintainer, not an agent's
   pick. Confidence 60 % that it is needed for 500 in one fight, 20 % that it is needed for 500 in the world.
4. **Jolt's own threading.** Godot 4.7's Jolt module runs Jolt's job system on `WorkerThreadPool` with the pool's thread
   count (`modules/jolt_physics/spaces/jolt_job_system.cpp`, branch 4.7, read 2026-11-03), so the solver is already
   parallel; Jolt itself scales 4.9x at 8 threads on a 3 680-body scene
   ([Jolt multicore scaling document, updated 2023-03-10](https://jrouwe.nl/jolt/JoltPhysicsMulticoreScaling.pdf)). The
   "8.5 ms at 500" estimate in the handoff is therefore mostly sync and node propagation, which are main-thread. Lever 3 or
   the node diet is what moves it, not more Jolt threads.

### 2.5 Multithreaded physics and a server-style simulation thread

`physics/3d/run_on_separate_thread` exists and the Jolt module supports it, marked experimental
([Godot docs, thread-safe APIs, 4.6](https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html);
[forum report on 4.6.2](https://forum.godotengine.org/t/regarding-jolt-physics-im-confused-is-it-ready-or-not-according-to-the-documentation/136790)).
It moves the physics step off the main thread so it overlaps the frame; scripts still run on the main thread in
`_physics_process`, and `RamResolver._read_contacts` reads direct body state, which would need to move to the physics
callback. Gain: overlap only, about the Jolt step's 1.5 ms at 100. Confidence 40 %, low priority.

The stronger form is the server pattern: the whole native simulation (2.2 plus 2.3) steps at a fixed 60 Hz on a worker
thread into a double-buffered snapshot, and the main thread interpolates rendered proxies from the last two snapshots. The
tick then no longer competes with rendering for the 16.7 ms frame, which is what the AC6 finding needs. This is the design
of every multiplayer server and of Doom 3 BFG's game thread (section 4.8). Inside Godot it is possible only once nothing
per ship touches the scene tree during the step (2.2 makes that true for the simulation; the visuals read the snapshot).
Rules: one writer, snapshot by value, ship-index order, the 1-thread against 6-thread parity test from Q9. Confidence
50 % that it is worth its complexity before 300 ships; 70 % that it is needed for 500 in one fight at 60 FPS on vsync.

### 2.6 GPU compute for simulation

Broad phases (bolts against ships, contacts) are embarrassingly parallel and would fit a compute shader, but the result
must come back to the CPU for the brains, which costs a frame of latency through `RenderingDevice` readback, and at 500
ships times 1 500 bolts a CPU grid in Rust is already under 1 ms. The brains themselves are branching, seeded, stateful
code that does not fit a GPU. Not recommended; confidence 10 % that it beats the CPU grid at this size.

### 2.7 The render side

Not in M4's scope, but 500 ships need it as much as the tick (section 1.4):

- **Far-ship proxies.** Beyond a distance, a ship is one splat node at LOD3 or a point in a `MultiMeshInstance3D` of dots
  (the §14.4 "single splat or point sprite" level), with no depth proxy, plumes, lights or chunks: about 1 draw call and
  under 1 us of render CPU per ship instead of 27 calls and 30 us. Confidence 75 % that this takes the render CPU at 500
  under 3 ms.
- **Node diet for AI ships.** The AI ship scene keeps the body, the collision shapes, the LOD splat nodes and the proxy;
  thruster visuals become one MultiMesh per ship or per fleet; nav and running lights, cockpit screens and the hero level
  exist only on the player. 108 nodes to about 12 (estimate), which cuts the rebase, the sync and the render thread's
  per-node work together.
- **GDGS per-instance work.** The fork builds a per-frame table of drawn instances in GDScript (patch 5); at 2 000 splat
  nodes (500 ships times 4 LOD levels) that loop is worth measuring. Paging (resident budget, §14.4) is the fork's next
  patch either way.
- **Splat budget.** 2 M visible splats fit 500 ships only at LOD3 for most of them; the `LodSwitcher` already steps the
  farthest ships down, so the furball at 500 would show about 50 ships with detail and 450 as blurs, which is what §14.4
  calls model blurring. Whether that looks right is (H).

## 3. Changing the engine

### 3.1 What a change must pay for, whatever the engine

| what we have | size | what a new engine does with it |
|---|---|---|
| game code, GDScript | 178 files, 27 300 lines | rewritten in the engine's language |
| tests, GUT and Python | 175 GDScript files, 39 000 lines; 370 Python tests | GUT tests rewritten; the Python tests stay (they test the generators) |
| native crate | 408 lines of Rust | reusable in a Rust engine, rewritten elsewhere |
| GDGS fork | 12 400 lines, 5 patches (sort overflow, subgroups, depth keys, faint splats, visible-splat budget), compute compositing against scene depth, per-splat relighting from `.light` records | rewritten against the new renderer, including everything upstream GDGS gave for free |
| procgen pipeline | 14 200 lines of Python, writes PLY, OBJ, hardpoints, lighting records | stays; the importers are rewritten |
| console, settings, bench harness, control profiles, input shaping, HUD, audio | inside the 27 300 lines | rewritten |
| CI, setup scripts, the SHA-pinned toolchain | | redone |

Estimate for any full change: 60 to 120 PR-sized tasks before the game is back where it is today at 45 ships, against 15 to
25 tasks for sections 2.1 to 2.4 and 2.7 inside Godot (confidence 70 % on the ratio, 50 % on the absolute counts). The M3
and M4 milestone logs say what a task costs here.

### 3.2 Licence fit with GPL-3.0

The project is GPL-3.0 and ships Linux x86_64 builds. A GPL-3.0 game combined with an engine is one work; its
"Corresponding Source" must be distributable under the GPL, and the system-library exception covers the OS, compiler and
interpreter, not a game engine ([Software Freedom Conservancy's copyleft guide on the exception](https://k.sfconservancy.org/Copyleft/guide/changeset/0f3bc95c5160fe0492c1de0032dbf67405e9707c?context=12)).
So:

- **Compatible:** MIT, Apache-2.0, MPL-2.0, GPL-2.0-or-later, GPL-3.0 (with or without id Software's additional terms, which
  are the warranty, liability, trademark and indemnity terms GPL-3.0 section 7 allows).
- **Incompatible:** Unreal's EULA names the GPL as a prohibited licence for code combined with the engine, static or
  dynamic ([Unreal EULA, non-compatible licences](https://conductatlas.com/platform/unreal-engine/unreal-engine-eula/non-compatible-license-prohibition-gpllgpl-ban/);
  [Epic forum answer](https://forums.unrealengine.com/t/server-gnu-libs/394503/2)); Unity's runtime is proprietary under
  the Unity Editor Software Terms (updated 2026-06-30) and cannot be conveyed under the GPL
  ([Unity Editor Software Terms](https://activation.unity3d.com/legal/terms-of-service/software)); Flax is source-available
  under its own EULA with a 4 % royalty above 250 000 USD a quarter, not open source
  ([Flax licensing page](https://flaxengine.com/licensing/)). In all three the maintainer could ship a build only by
  relicensing the game, and nobody else could redistribute it under the GPL.
- **GPL-2.0-only** (Yamagi Quake II per its packagers, [SUSE](https://packagehub.suse.com/packages/yamagi-quake2)) cannot be
  combined with GPL-3.0 code. GPL-2.0-or-later can, under GPL-3.0.

### 3.3 The options table

Confidence is my estimate that the option gets the game to 500 ships (in the world, 100 to 150 in one fight at full
fidelity) at 60 FPS windowed, within about 25 PR-sized tasks for the Godot rows and about 120 for the engine rows, and
without breaking a project constraint (Linux only, GPL-3.0, procedural assets, splats, honest physics). "Gain at 500" is
what the engine itself contributes beyond the rewrite into native code that every row needs.

| # | option | licence, GPL-3.0 fit | Linux (runtime, editor) | threading | physics | Gaussian splats | gain at 500 ships | cost | confidence |
|---|---|---|---|---|---|---|---|---|---|
| G1 | Godot 4.7.2, remaining native cycles (2.1) | MIT, fine | yes, yes | threads inside the crate (Q9) | Jolt, threaded step | GDGS fork, done | 100 ships; not 500 | 4 tasks | 70 % for 100, 10 % for 500 |
| G2 | Godot, native data-oriented core (2.2) plus physics levers (2.4) and the render diet (2.7) | MIT, fine | yes, yes | rayon inside the crate; optionally the sim on a worker thread (2.5) | Jolt for near ships, own integrator for the rest (contract change D4) | done | 200 to 300 in one fight; 500 with G3 | 15 to 25 tasks | 55 % for 300 in one fight, 35 % for 500 in one fight |
| G3 | Godot, G2 plus a low-attention tier (2.3) | MIT, fine | yes, yes | as G2 | as G2, far ships integrated natively at 10 to 20 Hz | far ships as proxies | 500 in the world, 100 to 150 at full fidelity | G2 plus 4 to 6 tasks | 75 % |
| E1 | Bevy 0.20.1 (Rust ECS, wgpu 30 on Vulkan) | MIT or Apache-2.0, fine ([crates.io, 2026-10-28](https://crates.io/crates/bevy)) | yes; no editor, which suits a procgen project | systems run in parallel by default; ECS is data-oriented from day one | avian3d 0.8.0 (MIT or Apache-2.0, 2026-10-20) or bevy_rapier; no Jolt | `bevy_gaussian_splatting` 9.0.0 (MIT or Apache-2.0, 2026-10-25): a renderer exists but none of our five patches, depth compositing or relighting | the native core comes free with the engine; 500 ships' logic is trivial for an ECS | full rewrite (3.1); Bevy breaks its API every release (0.19 on 2026-06-19, 0.20 by 2026-10) | 85 % that it reaches 500 headless; 25 % that it is the right move |
| E2 | Unreal Engine 5.x | EULA prohibits GPL code with the engine: **incompatible** | yes, yes | TaskGraph, Mass Entity for crowds | Chaos | SplatRenderer (Apache-2.0, 2026-03), NanoGS (MIT), YaGS ([radiancefields.com, 2026](https://radiancefields.com/tags/unreal-engine)) | Mass Entity would carry 500 ships | full rewrite in C++ and Blueprints; relicense the game | 5 % |
| E3 | Unity 6 with DOTS | proprietary runtime: **incompatible** with a GPL-3.0 game | yes, yes | Jobs and Burst, Entities 1.x | Unity Physics (DOTS) | `UnityGaussianSplatting` (MIT, Vulkan) ([github](https://github.com/aras-p/UnityGaussianSplatting)) | DOTS would carry 500 ships | full rewrite in C#; relicense the game | 5 % |
| E4 | Flax 1.11 | source-available EULA, 4 % royalty over 250 000 USD a quarter: **incompatible** with GPL-3.0 | runtime yes (Ubuntu 24, Vulkan, X11) ([Flax docs, Linux](https://docs.flaxengine.com/manual/platforms/linux.html)); editor for Linux x64 offered ([download page](https://flaxengine.com/download/)) | work-stealing job system | PhysX | none known | C++ and C# speed, a job system | full rewrite; relicense the game | 10 % |
| E5 | Stride 4.4 (C#/.NET, MIT) | MIT, fine ([github, pushed 2026-11-03](https://github.com/stride3d/stride)) | runtime yes, non-Windows no longer experimental, Vulkan 1.3 required; **Game Studio is WPF, Windows only**, runs under Proton "not as solid", the Avalonia rewrite is in progress ([4.4.0 release notes](https://github.com/stride3d/stride/releases/tag/releases%2F4.4.0); [launcher PR #3276](https://github.com/stride3d/stride/pull/3276)) | `Dispatcher.For`/`ForBatched` parallel loops with `MaxDegreeOfParallelism` ([API](https://doc.stride3d.net/latest/en/api/Stride.Core.Threading.Dispatcher.html)); entity processors are the ECS-like layer | Bepu v2 (Apache-2.0, multithreaded, [github](https://github.com/bepu/bepuphysics2)) through Stride's own job dispatcher | none known; custom render features and compute are possible, so GDGS's compute pipeline could be ported | C# with Burst-like performance is not a given; the GC adds p99 risk; Bepu is strong | full rewrite in C#; the editor host breaks the Linux-only rule unless code-only projects suffice | 20 % |
| E6 | O3DE 26.05 | Apache-2.0 or MIT, fine ([O3DE 26.05, 2026-06](https://digitalproduction.com/2026/06/17/o3de-26-05-gets-native-particles/)) | binaries for Ubuntu 22.04, Linux still rough (window-resize crash under Vulkan in 25.10.1 notes) | job system | PhysX 5 default | none known; Atom has custom passes | a C++ engine with jobs | the largest codebase on the list, long builds; full rewrite in C++ and Lua | 15 % |
| E7 | id Tech 3: ioquake3, Quake3e, vkQuake3 (section 4.7) | GPL-2.0-or-later in every source header ([ioq3 `q_shared.h`](https://raw.githubusercontent.com/ioquake/ioq3/main/code/qcommon/q_shared.h)), so usable under GPL-3.0; ET:Legacy is id Tech 3 under GPL-3.0 outright | yes, no editor (maps need external tools) | single-threaded game and server; Quake3e's Vulkan renderer uses multiple command buffers, no job system | Quake movement code, no rigid bodies | fixed-function era rasteriser; no compute path | nothing: every cost of ours would be rewritten in C anyway | rewrite the game, write a physics engine, write a splat renderer into a 1999 renderer, lift the 1 024-entity and 256-per-snapshot caps | 2 % |
| E8 | id Tech 4: dhewm3, RBDOOM-3-BFG (section 4.8) | GPL-3.0-or-later with id's additional terms, fine | yes, no editor beyond the in-game one | BFG: game on its own thread, `idParallelJobList` worker threads (`jobs_numThreads`) | `idPhysics_RigidBody`: impulse-based 6DOF with CCD, "not very accurate but relatively fast" | RBDOOM renders through NVRHI (Vulkan, DX12), compute is possible, nothing exists | native speed, a job system, a game thread | rewrite the game in C++, replace BSP-shaped world and asset pipeline, build a splat renderer, 4 096-entity cap | 5 % |
| E9 | Cocos Creator 3.8.9 (TypeScript, C++ runtime) | engine MIT ([LICENSE.md](https://raw.githubusercontent.com/cocos/cocos-engine/v3.8.9/LICENSE.md)), editor proprietary; fine for the GPL | **no desktop Linux build target** (native: Windows, macOS, iOS, Android, HarmonyOS; [publish docs 3.8](https://docs.cocos.com/creator/3.8/manual/en/editor/publish/index.html)); editor for Windows and macOS only | JS main thread; native C++ renderer | PhysX, Bullet, cannon.js or ammo.js | none; custom pipeline possible | TypeScript is no faster than GDScript for per-ship logic | fails the platform rule twice; full rewrite | 2 % |
| E10 | Torque3D 4.0.3 (MIT, C++ and TorqueScript) | MIT, fine | Linux CI build; no Vulkan: `gfx/D3D11` and `gfx/gl` only (repo tree, 2026-11-03) | little | Torque physics, optional Bullet or PhysX 3 (`T3D/physics`) | none; a forward renderer without a compute path | native speed | last release 2023-02-07, development branch active 2026-09-26 ([releases](https://github.com/TorqueGameEngines/Torque3D/releases)); full rewrite; the renderer is the oldest on the list | 5 % |
| E11 | Banshee, bs::framework, now B3DFramework (MIT) | MIT, fine | **Windows only**; Linux and macOS ports "in progress" ([README](https://raw.githubusercontent.com/GameFoundry/B3DFramework/master/README.md)); the original Banshee repositories are gone | fiber-based task scheduling, an ECS "for massive object counts" (claims, no numbers) | unnamed | none; Vulkan backend, DX12 and Metal in progress | an ECS with fibers | one developer, abandoned 2019 to 2025 and revived (pushed 2026-11-03), no Linux, no editor; full rewrite | 3 % |
| E12 | Own engine: Rust sim core, wgpu 30 or ash, winit or SDL3, splat renderer ported from GDGS or built on brush (Apache-2.0) or wgpu-3dgs-viewer 0.8.0 | all MIT or Apache-2.0, fine | yes | whatever we write | avian, rapier or own | port GDGS's GLSL compute to wgsl, or write on brush's kernels | total control | E1's cost plus the scene, asset, audio, UI and input layers Bevy gives free | 85 % that it reaches 500; 10 % that it is worth it |
| H1 | Hybrid: Godot for rendering and UI, a separate native simulation it drives | fine | yes | sim in its own process or thread | own | GDGS | the same as G2 | a separate process adds IPC and a frame of latency for nothing; in-process through `gdext` is G2 | see G2 |

### 3.4 Reading the table

Four rows fail on licence (E2, E3, E4) or platform (E9, E11), five more (E7, E8, E10 and in practice E6) offer a C++ host that
is older or heavier than Godot with no splat renderer and the same rewrite, and the one credible alternative, Bevy (E1),
gives exactly what section 2.2 gives inside Godot at four to five times the cost. Stride (E5) is the best of the rest and
still fails the editor-on-Linux test today. Nothing in the engine column changes the arithmetic of section 1: 10 to 16 us per
ship per tick is a native-code budget in any engine, and the per-ship render cost is a node-and-draw-call diet in any engine.

### 3.5 What the engines do not fix

- **The brains are ours.** 3 000 lines of behaviours with seeded rolls and tuned temperaments are the same work to port
  into Rust under Godot, Rust under Bevy, C++ under id Tech 4 or C# under Stride. The tests that pin them are GDScript.
- **The splat renderer is ours.** Upstream GDGS gave the compute pipeline and the depth compositing; the fork added the sort
  overflow fix, narrow-subgroup fallback, depth-key precision, faint-splat footprint, the visible-splat budget and per-splat
  relighting. No other engine has an equivalent that composites against scene depth and relights from our `.light`
  records; `bevy_gaussian_splatting` is the nearest and would need all of it again.
- **The honest physics are ours.** Jolt, Bepu, avian and PhysX all integrate rigid bodies correctly; the Starfury's
  identity is in `FlightModel`, `FlightAssist` and the speed governor, which move with the game.
- **Linux and GPL** are constraints no engine lifts and several break.

## 4. Engine notes in depth

### 4.1 Godot 4.7.2 and what 4.8 changes

Godot 4.7 shipped 2026-06-19 and 4.7.2 on 2026-08-18 ([gamedev.net on 4.7.2](https://gamedev.net/news/5172-godot-engine-472-stable-released/)).
4.8 is at dev snapshots (dev 4 claims object property access 1.6x faster in GDScript,
[linuxcompatible.org](https://www.linuxcompatible.org/story/godot-48-dev-4-lands-native-trail3d-multibounce-ao-and-224-fixes/));
nothing in the snapshots changes the per-ship arithmetic. Jolt is the default physics engine since 4.6 and its step runs on
`WorkerThreadPool` (section 2.4). Node processing stays single-threaded (open proposal
[godot-proposals #4962](https://github.com/godotengine/godot-proposals/issues/4962)); the scene tree is not thread-safe
([docs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)), which is why every threaded
design above keeps the scene tree out of the step.

### 4.2 Bevy

0.19 on 2026-06-19 (261 contributors, 1 185 pull requests, [bevy.org](https://bevy.org/news/)), 0.20.1 on 2026-10-28
(crates.io). MIT or Apache-2.0. wgpu 30.0.1 (2026-08-22) on Vulkan for Linux. ECS systems are scheduled in parallel; 500
entities with a dozen components is a small world for it (published ECS benchmarks run at a million entities,
[flecs-hub ecs_benchmark](https://github.com/flecs-hub/ecs_benchmark)). Physics: avian3d 0.8.0 (2026-10-20, Bevy-native),
bevy_rapier; no Jolt. Splats: `bevy_gaussian_splatting` 9.0.0 (2026-10-25, MIT or Apache-2.0, planar 3D and 4D Gaussians,
headless feature) renders clouds but has no scene-depth compositing contract like GDGS's and no relighting. No editor: fine,
since every asset is generated and the console drives the game. Risk: every minor release breaks the API (0.12 to 0.19 all
did, [strayspark 2026 guide](https://www.strayspark.studio/blog/bevy-rust-game-engine-2026-indie-guide)); for a project
that pins Godot by SHA this means pinning Bevy and upgrading on purpose, as with gdext.

### 4.3 Unreal, Unity, Flax

Unreal: Linux editor and runtime, Mass Entity, Chaos, several open splat plugins (SplatRenderer Apache-2.0 for 5.5 to 5.7,
NanoGS MIT, YaGS). Unity: Linux editor, DOTS Entities 1.x, Burst, the runtime fee cancelled in 2024 and seat pricing up 5 %
from 2026-01-12 ([Unity pricing updates](https://unity.com/pricing-updates)); `UnityGaussianSplatting` MIT on Vulkan. Flax:
Linux editor and runtime, C++ and C#, job system, PhysX. All three are out on licence (section 3.2). Were the project not
GPL, Unreal's Mass Entity and Unity's DOTS are the two mainstream engines built for exactly "thousands of agents", and both
would still need the brain port and a splat compositor of our own.

### 4.4 Stride

MIT, C# on .NET, 4.3 on 2025-11-14 and 4.4.0 on 2026-10-09 (Vulkan 1.3 with dynamic rendering, OpenGL removed, non-Windows
no longer experimental, NativeAOT, physics on Stride's job dispatcher). Bepu v2 is a fast multithreaded solver (its author
reports 9.5 ms against 120 ms for v1 on 8 threads in early benchmarks,
[bepuentertainment.com, 2018](https://www.bepuentertainment.com/blog/2018/4/8/v151-versus-v200-alpha-early-benchmarks.html);
determinism is off by default). `Dispatcher.ForBatched` is the lowest-overhead parallel loop; entity processors are the
ECS-like layer. Custom render features and compute shaders exist, so GDGS's pipeline could be ported in C# and SDSL. The
blocker is the editor: Game Studio is WPF, Windows only, "not as solid" under Proton, and the Avalonia rewrite is funded and
in progress with no date ([Open Collective](https://opencollective.com/stride3d/projects/editor-rewrite-avalonia)). A
code-only workflow (no Game Studio, assets built on the command line, which 4.4 supports on Linux) would satisfy the platform
rule in letter; the maintainer should decide whether it does in spirit. C# also brings the garbage collector into the p99
budget.

### 4.5 O3DE

Apache-2.0 or MIT ([o3d.foundation](https://o3d.foundation/?p=266)). 26.05 in June 2026, binaries for Windows 10 and Ubuntu
22.04, PhysX 5 the default, C++20, a job system, Atom renderer with custom passes. Linux is a first-class but rougher target
(the 25.10.1 notes list a Vulkan window-resize crash on Linux, [release notes](https://docs.o3de.org/docs/release-notes/2510-1-release-notes)).
No Gaussian splat gem. It is the heaviest engine here to build and to learn, aimed at teams, and offers the game nothing that
a Rust core inside Godot does not.

### 4.6 Cocos Creator

Engine MIT (v3.8.9, pushed 2026-10-28), editor proprietary and free, TypeScript scripting over a C++ runtime (renderer, scene
management and native adaptation in C++, "half C++ and half TypeScript", [github](https://github.com/cocos/cocos-engine)).
Vulkan on Windows and Android, Metal on Apple, WebGL on the web. Native publish targets are Windows, macOS, iOS, Android and
HarmonyOS plus web and mini-game platforms; **desktop Linux is not a publish target** and the editor ships for Windows and
macOS ([publish docs 3.8](https://docs.cocos.com/creator/3.8/manual/en/editor/publish/index.html)). Physics is PhysX, Bullet,
cannon.js or ammo.js; threading is the JavaScript model (one main thread plus workers). Per-ship logic in TypeScript would
cost about what GDScript costs. A custom render pipeline is possible, no splat renderer exists. It fails the Linux rule as
target and as editor host, which ends it regardless of the rest. Confidence 2 %.

### 4.7 id Tech 3: ioquake3, Quake3e, vkQuake3

- **Licence.** Every source file says "either version 2 of the License, or (at your option) any later version"
  (`code/qcommon/q_shared.h` in ioquake3 main, Quake3e master and vkQuake3 master, read 2026-11-03), so the code may be
  used under GPL-3.0. GitHub labels all three GPL-2.0 because the COPYING file is the bare GPLv2 text; the grant is in the
  headers. Wolfenstein: Enemy Territory's id Tech 3 was released under GPLv3 in 2010 and ET:Legacy carries it
  ([ET:Legacy README](https://raw.githubusercontent.com/etlegacy/etlegacy/master/README.md)), which settles the question
  in practice. Activity: ioquake3 pushed 2026-10-12, Quake3e 2026-10-14, vkQuake3 2026-06-14 (113 stars, Vulkan back end
  from the Kenny Edition).
- **Limits.** `GENTITYNUM_BITS 10`, so `MAX_GENTITIES` 1 024, `MAX_CLIENTS` 64, `MAX_MODELS` 256 (sent as 8 bits), 256
  entities per client snapshot (`MAX_SNAPSHOT_ENTITIES`, `MAX_ENTITIES_IN_SNAPSHOT`), renderer `MAX_REFENTITIES` 1 023.
  Our furball at 100 ships holds about 300 bolts; at 500 ships about 1 500 bolts plus ships, debris and effects, which is
  past 1 024 before the first explosion. The caps are compile-time and the network protocol encodes them, so lifting them is
  a protocol change too.
- **Threading.** The server and game run single-threaded in `sv_fps` frames (20 Hz by default,
  [icculus quake3 list, 2008](https://icculus.org/pipermail/quake3/2008-April/002397.html)); the game and cgame modules run
  as QVM bytecode or native shared objects; Quake3e's Vulkan renderer lists "multiple command buffers" and a reduced
  dispatch ratio, not a job system ([Quake3e README](https://github.com/ec-/Quake3e)). There is nothing to put 500 brains on.
- **Renderer.** A BSP level renderer with lightmaps, shaders in the Quake sense (texture stages), dynamic lights; the Vulkan
  ports modernise the API calls, not the architecture. There is no compute pass, no scene-depth compositor, no scene graph;
  a Gaussian splat renderer would be written from scratch into it and the space scene has no BSP to render.
- **Physics.** Quake player movement and trace-based entity motion; no rigid bodies, no inertia tensors, no forces at
  hardpoints, no CCD against convex hulls. Newtonian 6DOF flight and the ram resolver would be written from zero.
- **What it would help with.** None of our measured costs. AI, flight, bolts and rams would be new C code (fast, as any
  native code is), and that same speed is available in Rust inside Godot without losing the renderer, the scene tree, the
  input layer, the console or the tests.
- **Porting cost.** Rewrite the game in C, write a rigid-body engine, write a splat renderer, lift the entity caps and the
  32-bit world limits, build an asset path from PLY to something the engine draws. Larger than E1 with a worse result.
- **Confidence 2 %.** Named for completeness; it is a 1999 shooter engine and the Vulkan forks do not change what it is.

### 4.8 id Tech 4: dhewm3, RBDOOM-3-BFG

- **Licence.** Doom 3's source is GPL-3.0 "or (at your option) any later version" in every header, with id Software's
  additional terms: section 15 and 16 replaced (warranty, liability), notices and trademarks (no use of id's names or marks,
  altered versions marked), and an indemnity clause for anyone who offers warranties on a conveyed work
  (`COPYING.txt` in dhewm3, read 2026-11-03). These are the kinds of terms GPL-3.0 section 7 permits, so the combination
  with our GPL-3.0 code is fine; packagers label it "GPL-3 with id Software extra terms". RBDOOM-3-BFG is the same with the
  BFG edition's code and a `LICENSE_EXCEPTIONS.md` for parts not under the GPL. Activity: dhewm3 pushed 2026-06-08
  (1.5.5 era), RBDOOM-3-BFG 1.6.0 on 2025-05-10, pushed 2026-08-07.
- **Threading.** The original engine runs the game at `USERCMD_HZ` 60 on the main thread with a separate renderer back end
  thread. The BFG edition adds `idGameThread` (game and foreground rendering on their own thread,
  `neo/framework/Common_local.h`) and `idParallelJobList`, a job system with sync points, priorities and a `jobs_numThreads`
  worker count used for the renderer front end and back end (`neo/idlib/ParallelJobList.h`, job lists
  `JOBLIST_RENDERER_FRONTEND` and `BACKEND`). Entity thinking (`idGameLocal::RunFrame`) is a serial loop over active
  entities. So the job system is there to use for our own AI batches, which is the same as rayon in the crate.
- **Limits.** `GENTITYNUM_BITS 12`, so `MAX_GENTITIES` 4 096 (`neo/game/GameBase.h`, `neo/d3xp/Game_local.h`), snapshots
  per client sized by it; 500 ships plus 1 500 bolts fit, with room for debris. Clip models and the collision model are
  built for indoor BSP levels with a world of float32 units; a 20 km play area needs the same floating origin we have.
- **Renderer.** dhewm3: the 2004 unified lighting and stencil shadow renderer on OpenGL. RBDOOM: PBR, light grids, SSAO,
  TAA, HDR, through NVRHI on Vulkan and DX12 ([README](https://github.com/RobertBeckebans/RBDOOM-3-BFG)). NVRHI exposes
  compute pipelines, so a Gaussian splat pass with its radix sort and tile blend is possible in principle; none exists, and
  the scene is portal-culled BSP areas, which space does not have. Assets: md5, lwo, ase, glTF2 and OBJ in RBDOOM; PLY splats
  would need a new importer and a new draw path.
- **Physics.** `idPhysics_RigidBody` is an impulse-based 6DOF rigid body ("not very accurate but relatively fast and still
  reliable due to the continuous collision detection", `Physics_RigidBody.h`) with an Euler ODE integrator by default
  (`idODE_Euler`, RK4 available), momentum state, `AddForce` at a point and `ApplyImpulse`, contact friction and bounciness,
  CCD by trace model against the clip world. It is a per-entity integrator with no shared solver, no broad phase beyond the
  clip sectors, and no body-pair contact graph; ship-against-ship contacts would be our ram resolver again. For our needs it
  is roughly what section 2.4's own integrator would be, in C++ and already written, minus Jolt's solver quality.
- **What it would help with.** Native speed everywhere, a job system and a game thread (the shape of section 2.5), an
  integrator close to ours. Nothing it has is better than Rust inside Godot with rayon, and everything else (renderer,
  scene, assets, input, UI, console, tests) is a loss.
- **Porting cost.** Rewrite the game in C++ inside a shooter engine's entity model, replace the asset pipeline, write the
  splat renderer on NVRHI, carry the floating origin over, rebuild the console and the test harness (id Tech 4 has no unit
  test framework). Comparable to E1 and larger than E12 in the parts that fight the engine.
- **Confidence 5 %.** The most capable of the id engines for this game and still a worse host than Godot for every part of
  it except raw C++ speed, which the crate already provides.

### 4.9 Quake 1 and Quake 2 lineages, briefly

QuakeSpasm and vkQuake (GPL-2.0, pushed 2026-10-29 and 2026-11-03), Yamagi Quake II (GPL-2.0-only per its packagers) and
Quake II RTX (GPL-2.0, archived 2025-12-11). Entity caps of 600 to 8 192 depending on the port, Quake movement code, no
rigid bodies, BSP renderers; vkQuake and Quake II RTX are Vulkan renderers of BSP worlds, RTX with path tracing. The
GPL-2.0-only labels would need the headers checked for "or later" before any use under GPL-3.0 (Quake II's 2001 release was
"v2.0 or later" per Wikipedia). Everything in 4.7 applies with lower caps. Not candidates.

### 4.10 Torque3D

MIT. 4.0 on 2022-08-12, 4.0.3 on 2023-02-07, nothing since; the development branch is active (2026-09-26,
[github](https://github.com/TorqueGameEngines/Torque3D)). C++ with TorqueScript. Renderer back ends D3D11 and OpenGL only
(`Engine/source/gfx`), no Vulkan and no compute path, so the splat renderer would be written on OpenGL 3 era code. Physics:
Torque's own plus Bullet and PhysX 3 plugins (`Engine/source/T3D/physics`). Threading is minimal. Linux builds in CI. It is
a 2009 engine in good repair; nothing in it helps the per-ship arithmetic and the renderer is the least suited on the list to
hosting splats. Confidence 5 %.

### 4.11 Banshee, bs::framework, B3DFramework

Banshee Engine and its bs::framework layer went silent around 2019 to 2020 ("suddenly disappeared for mostly unknown
reasons", [GameFromScratch on B3DFramework](https://gamefromscratch.com/b3dframework-3d-game-development-framework/)); the
original repositories are gone (BearishSun/BansheeEngine returns nothing). The author has revived the code as B3DFramework
(MIT, 7 650 commits, pushed 2026-11-03, 1 945 stars): C++17, Vulkan back end with DX12 and Metal in progress, fiber-based
task scheduling, an ECS "for massive object counts", a planned rebuilt Banshee editor; **Windows only today, Linux and macOS
ports in progress** ([README](https://raw.githubusercontent.com/GameFoundry/B3DFramework/master/README.md)). One developer,
one five-year gap, no Linux, no editor, no splats, no physics named. The maintenance risk is the point: a single-developer
engine that stopped once is a dependency the project cannot fix itself the way it can fork GDGS. Confidence 3 %.

### 4.12 Own engine

Rust: a simulation core (sections 2.2 and 2.3 as a crate without the Godot seam), wgpu 30 (MIT or Apache-2.0) or ash on
Vulkan, winit or SDL3, a splat renderer either ported from GDGS's GLSL compute shaders (MIT, ours to port) or built on
brush's kernels (Apache-2.0, Rust, wgpu, pushed 2026-10-03, [github](https://github.com/ArthurBrussee/brush)) or
wgpu-3dgs-viewer 0.8.0 (2026-08-23); 3DGS.cpp is the C++ Vulkan alternative but LGPL-2.1 and last pushed 2025-05-19.
Then audio, input, a UI layer, a scene format, hot reload, the console, the harness. This is Bevy's cost plus everything
Bevy already has, for the one gain of a renderer shaped exactly around splats. It would reach 500 (85 %) and it is the
most expensive route on the list (confidence 10 % that it is worth it). The one case for it: if the project's long-term
ambitions (true-scale solar systems, hyperspace, capital ships, thousands of splat nodes with paging) turn out to fight
Godot's renderer at every step, an own renderer is where that fight ends. Nothing measured so far says that; the GPU has
been under 10 ms at every count tried.

## 5. Recommendation

**Stay in Godot.** Leaving it is not worth it: the measured costs are in GDScript the project owns, every engine needs the
same native rewrite of the brains and the flight model, the splat compositor and its five patches would be redone, four
engines are out on licence or platform, and the one credible alternative (Bevy) costs four to five times the Godot path for
the same per-ship arithmetic. Confidence 85 % in "stay".

**Decide first (the maintainer):**

1. **What 500 means.** 500 ships in one 5 km furball at full fidelity and 60 FPS on vsync, or 500 ships in the world with
   100 to 150 at full fidelity near the player and the rest in a low-attention tier. The setting (three squadrons of 12 plus
   the station at Babylon 5; 4 to 6 ship patrols) needs the second. The first needs section 2.5's simulation thread and the
   render diet in full, and its confidence is half the second's.
2. **The parity rule for ports after N1.** A stated tolerance (for example: over a seeded 30 s fight, hits within 10 %,
   behaviour mix within 5 points, no ship diverging from its GDScript twin by more than 50 m at 10 s) and which seeded runs
   measure it. Without it the brain port cannot be reviewed.
3. **Ships out of Jolt or not** (section 2.4, lever 3): a change to D4 and §5.6.
4. **The budget.** Add the windowed 60 FPS check at the headline (Q13, agreed) and state the tick's share of the frame at
   the headline count (5 ms suggested), since the 8 ms headless budget passed 45 ships that the window did not.

**Phases, each a measurable step:**

| phase | what | expected ship count (headline, furball unless said) | confidence | tasks (estimate) |
|---|---|---|---|---|
| 1 | The remaining native cycles: bolt broad phase (native), threaded perception and avoidance (N3), flight force step native (N4), cheaper gather. Far-ship render proxies and the node diet for AI ships, measured in the window | 100 headless at 8 ms; 60 FPS windowed at 100 with proxies | 70 % | 6 to 8 |
| 2 | Ship state as native arrays: brains ported with the parity tolerance (N2 first, then the behaviours), bolts and resolvers native, one call per tick in and out; optionally ships out of Jolt | 200 to 300 in one fight headless; 150 to 200 windowed | 55 % | 8 to 12 |
| 3 | The low-attention tier (2.3) with promotion and demotion, statistical far fire, far proxies; the simulation step on a worker thread if the window needs it (2.5) | 500 in the world with 100 to 150 near, 60 FPS windowed; 500 in one furball headless at 8 ms | 75 % (world), 35 % (one furball) | 6 to 10 |

Phase 1 is M4 continued (its candidates in T06's order); phases 2 and 3 are a new milestone, since they change the
architecture (§17 gains a native simulation core and a tier) and the roadmap's M5 mission work can start beside phase 1.

**What would change my mind:**

- If phase 1's windowed check at 100 ships stays under 60 FPS with far-ship proxies and the node diet in place, and the
  profiler shows the time in Godot's renderer or scene tree rather than in our code, the render side is the wall and the
  own-renderer case (E12, or Bevy with a splat renderer of our own) reopens. Measure before believing it: nothing so far
  shows Godot's own cost per ship above about 30 us, all of it in nodes and draw calls we control.
- If the brain port cannot meet the parity tolerance in two attempts, the tier (phase 3) carries more of the load: fewer
  full-fidelity ships, more in the tier, with the GDScript brains kept for the near ones. That gives 500 in the world but
  caps a single fight nearer 100.
- If the maintainer wants 500 in one furball at 60 FPS on vsync as a hard goal, the simulation thread (2.5) and ships out
  of Jolt (2.4) stop being options and become phase 2, and the confidence for that goal is 35 %, in any engine.

## Sources

Repository (read 2026-11-03 on `m4` at `681fb7b`): `docs/milestones/m4-performance-and-scale.md` (budget, Q1 to Q13, Cycle
log, T06 report, AC6), `docs/handoff-m4.md`, `.superpowers/sdd/m4-performance-and-scale/native-research.md`,
`docs/architecture.md` (§1, §2, §7, §11, §14, §15.3, §17), `docs/roadmap.md`, `docs/assets-starfury.md`, `addons/gdgs_scs/PATCHES.md`,
`src/`, `tests/`, `native/`, `tools/procgen` (line counts by `wc`).

Engines and licences (all read 2026-11-03):
- Godot 4.7.2 release, 2026-08-18: https://gamedev.net/news/5172-godot-engine-472-stable-released/ ; 4.7 stable 2026-06-19: https://app.cinevva.com/hi/news/2026-06-19-godot-4-7-released ; 4.8 dev 4: https://www.linuxcompatible.org/story/godot-48-dev-4-lands-native-trail3d-multibounce-ao-and-224-fixes/
- Godot Jolt job system on `WorkerThreadPool`: https://raw.githubusercontent.com/godotengine/godot/4.7/modules/jolt_physics/spaces/jolt_job_system.cpp ; thread-safe APIs and `run_on_separate_thread`: https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html ; node processing single-threaded, proposal: https://github.com/godotengine/godot-proposals/issues/4962
- Jolt README (MIT, multicore): https://raw.githubusercontent.com/jrouwe/JoltPhysics/master/README.md ; multicore scaling document (4.9x at 8 threads, 3 680 bodies; updated 2023-03-10): https://jrouwe.nl/jolt/JoltPhysicsMulticoreScaling.pdf
- Bevy 0.19, 2026-06-19: https://bevy.org/news/ ; crates.io: bevy 0.20.1 (2026-10-28), bevy_gaussian_splatting 9.0.0 (2026-10-25), avian3d 0.8.0 (2026-10-20), wgpu 30.0.1 (2026-08-22), all MIT or Apache-2.0; API churn: https://www.strayspark.studio/blog/bevy-rust-game-engine-2026-indie-guide
- Unreal EULA, GPL prohibited: https://conductatlas.com/platform/unreal-engine/unreal-engine-eula/non-compatible-license-prohibition-gpllgpl-ban/ and https://forums.unrealengine.com/t/server-gnu-libs/394503/2 ; Unreal splat plugins: https://radiancefields.com/tags/unreal-engine
- Unity Editor Software Terms (updated 2026-06-30): https://activation.unity3d.com/legal/terms-of-service/software ; pricing 2026: https://unity.com/pricing-updates ; UnityGaussianSplatting (MIT): https://github.com/aras-p/UnityGaussianSplatting
- Flax licensing (EULA, 4 % over 250 000 USD a quarter): https://flaxengine.com/licensing/ ; Linux: https://docs.flaxengine.com/manual/platforms/linux.html ; downloads: https://flaxengine.com/download/
- Stride 4.4.0 release notes: https://github.com/stride3d/stride/releases/tag/releases%2F4.4.0 ; 4.3 (2025-11-14): https://stride3d.net/blog/announcing-stride-4-3-in-dotnet-10/ ; editor rewrite: https://opencollective.com/stride3d/projects/editor-rewrite-avalonia ; launcher PR: https://github.com/stride3d/stride/pull/3276 ; Dispatcher API: https://doc.stride3d.net/latest/en/api/Stride.Core.Threading.Dispatcher.html ; Bepu v2 (Apache-2.0): https://github.com/bepu/bepuphysics2 and https://www.bepuentertainment.com/blog/2018/4/8/v151-versus-v200-alpha-early-benchmarks.html
- O3DE 26.05 (2026-06): https://digitalproduction.com/2026/06/17/o3de-26-05-gets-native-particles/ ; licence: https://o3d.foundation/?p=266 ; 25.10.1 notes: https://docs.o3de.org/docs/release-notes/2510-1-release-notes
- Cocos engine (MIT, v3.8.9): https://github.com/cocos/cocos-engine and https://raw.githubusercontent.com/cocos/cocos-engine/v3.8.9/LICENSE.md ; publish targets: https://docs.cocos.com/creator/3.8/manual/en/editor/publish/index.html
- ioquake3 `q_shared.h` (GPL-2.0-or-later header, `GENTITYNUM_BITS 10`, `MAX_CLIENTS 64`): https://raw.githubusercontent.com/ioquake/ioq3/main/code/qcommon/q_shared.h ; `cg_public.h` (256 per snapshot): https://github.com/ioquake/ioq3/blob/main/code/cgame/cg_public.h ; COPYING: https://raw.githubusercontent.com/ioquake/ioq3/main/COPYING.txt ; Quake3e: https://github.com/ec-/Quake3e ; vkQuake3: https://github.com/suijingfeng/vkQuake3 ; `sv_fps`: https://icculus.org/pipermail/quake3/2008-April/002397.html ; ET:Legacy (GPL-3.0): https://github.com/etlegacy/etlegacy
- dhewm3 COPYING (GPL-3.0 plus id terms): https://raw.githubusercontent.com/dhewm/dhewm3/master/COPYING.txt ; headers "version 3 or later": https://raw.githubusercontent.com/dhewm/dhewm3/master/neo/framework/Common.h ; `GENTITYNUM_BITS 12`: `neo/game/GameBase.h` ; `USERCMD_HZ 60`: `neo/framework/UsercmdGen.h` ; `idPhysics_RigidBody`: `neo/game/physics/Physics_RigidBody.h` ; Doom 3 source release 2011-11-22: https://doomwiki.org/wiki/Doom_3_source_code
- RBDOOM-3-BFG: https://github.com/RobertBeckebans/RBDOOM-3-BFG ; `idParallelJobList`: `neo/idlib/ParallelJobList.h` and `.cpp` (`jobs_numThreads`) ; `idGameThread`: `neo/framework/Common_local.h`
- Quake lineages: vkQuake https://github.com/Novum/vkQuake ; QuakeSpasm https://github.com/sezero/quakespasm ; Yamagi Quake II licence label https://packagehub.suse.com/packages/yamagi-quake2 ; Quake II RTX https://github.com/NVIDIA/Q2RTX
- Torque3D: https://github.com/TorqueGameEngines/Torque3D (releases 4.0.3 2023-02-07; `Engine/source/gfx` D3D11 and gl; `T3D/physics` bullet and physx3) ; https://docs.torque3d.org/general/release-notes
- B3DFramework (Banshee, bs::framework): https://github.com/GameFoundry/B3DFramework and its README ; https://gamefromscratch.com/b3dframework-3d-game-development-framework/
- Pioneer (GPL-3.0 space sim, own engine, pushed 2026-10-23): https://github.com/pioneerspacesim/pioneer
- Splat renderers outside Godot: brush (Apache-2.0): https://github.com/ArthurBrussee/brush ; wgpu-3dgs-viewer: https://docs.rs/wgpu-3dgs-viewer ; 3DGS.cpp (LGPL-2.1): https://github.com/shg8/3DGS.cpp
- ECS scale: https://github.com/flecs-hub/ecs_benchmark
- Low-attention simulation precedent (X4): https://steamcommunity.com/app/392160/discussions/0/6664812048260991709 ; https://www.egosoft.com/news/archive/2022December_en.php
- GPL system-library exception scope: https://k.sfconservancy.org/Copyleft/guide/changeset/0f3bc95c5160fe0492c1de0032dbf67405e9707c?context=12
