# Milestone 6: Epsilon Space at True Scale

> "The real neighbourhood." (`docs/roadmap.md`)

**Status:** planned 2026-11-10, ahead of time; **not started.** M5 is the current milestone until the maintainer accepts it.
M6 starts after that, on branch `m6` cut from `main` once M5 has merged, unless the maintainer pulls a task forward ("Early
start", below). Every task is `not started`. The planning questions (Q1 to Q12) are open: the proposed answers below are the
planner's defaults, and each task that depends on one waits for the maintainer's answer. This plan was written against `m5` at
`5d81686`, so it names M5 files (§18, M5-T21, `JumpArrival`) that reach `main` when M5 merges.

Read `docs/architecture.md` first, especially §10 (scale and units), §14.1 (coordinates and frames), §14.2 (gravity), §14.3 (time
acceleration, which M9 builds and M6 must not block), §14.4 (far-field rendering), §14.5 (hyperspace, M11), §17.13 (the native
core and its threading rules) and §17.14 (the low-attention tier). The roadmap's "Required: gravity" section is part of this
milestone's scope. Tasks are ordered inside each track; each is one PR-sized unit and names a recommended agent model.

## Goal

Put the game in the real Epsilon Eridani system at true scale. The local space becomes a moving, free-falling frame: it follows
the player's orbit, so local physics feels only the tidal residual of gravity and float32 speeds stay small (the velocity rebase).
The star, Epsilon III and its moons move on Kepler rails, and every ship, bolt and piece of debris falls under restricted n-body
gravity, so a bolt fired near the planet curves. Flight assist, the brake and the HUD read speed against the dominant body or
station instead of the frame. The planet and the sun are drawn in a scaled-space layer with an atmosphere, lit from the true sun
direction, and stay visible from orbit. The first jumpgate is built, with its vortex, and broadcasts to 1 000 km. M4's gravity
stand-in and the rebase cascade (L4) go. M7 puts Babylon 5 into this space, and M9 (time warp) and M11 (hyperspace) build on the
frame without rewriting it.

## Planning questions (open, 2026-11-10)

| Q | Question | Proposed answer (planner's default, until the maintainer answers) | Answer |
|---|---|---|---|
| Q1 | Which bodies make up the Epsilon system in M6, and their sizes and orbits? | The star (Epsilon Eridani, K2V, 0.82 solar masses, already in `data/star_systems.json`), **Epsilon III** and **its moons**, nothing else; other planets wait for M9's travel. Epsilon III's radius, mass, orbit and moon count from the maintainer's references, or an Earth-sized planet with one large moon if there are none | open |
| Q2 | Where is Babylon 5? | At a Lagrange point (L4 or L5) of Epsilon III and its large moon, as the show's background puts it, if the maintainer confirms; else a circular orbit around Epsilon III with the planet filling a large part of the view. M6 places the station's stand-in there; M7 replaces it | open |
| Q3 | Where is the jumpgate? | Near the station: about 50 km from it, in the same orbit, so a ship from the gate reaches the station in a few minutes and both broadcast to each other | open |
| Q4 | The hard 9 999 m/s speed clamp in `Ship` | **Drop the clamp**; keep only the thrust fade (`SpeedGovernor.thrust_gain`), measured against the dominant body (Q5). A body falling toward the star may then go as fast as physics says | open |
| Q5 | What is flight assist's "speed" under gravity? | **Relative to the HUD's reference** (Q6): the assist's safe speed, the brake's all stop and the thrust fade all read the ship's velocity minus the reference's. A ship that brakes to a stop in orbit beside the station stays beside it; a ship that brakes far from anything stops against the dominant body | open |
| Q6 | The HUD's reference point (the launch point today) | Set by the mission (a station, bay, gate or body), else the nearest of the station, the gate and the dominant body, its name shown beside `REF`; near a body the HUD also shows altitude | open |
| Q7 | Where free flight and the sandbox scenarios start | Beside the station's stand-in in its orbit (Q2), with the planet in view; the old origin-at-rest scenarios keep their layout around that point | open |
| Q8 | The velocity rebase threshold | 200 m/s relative to the frame (architecture §14.1), with the same end-of-tick interpolation rule as the position rebase | open |
| Q9 | The start epoch (the planet's phase, day or night under the station) | Each scenario sets an epoch; free flight seeds one per run, as it seeds its encounters | open |
| Q10 | References for Epsilon III, its moons and the sun's look | The maintainer's references (`docs/design-references.md`; per the standing rule, colours and textures from show images); without them, a rocky planet with thin clouds and a blue limb | open |
| Q11 | References for the jumpgate and its vortex | The maintainer's references; the jumpgate gets a section in `docs/design-references.md` before its generator starts (T13) | open |
| Q12 | M5's `JumpArrival` (a flash where raiders appear) | It stays for open jump points far from the gate; ships that use the gate come through the vortex (T14) | open |

## Scope

In:
- **The moving frame**: `WorldFrame` propagates its origin as a free-falling test particle in 64-bit; the **velocity rebase** on
  (Q8), over every body, row, bolt, debris chunk, particle system and interpolated node; the rebase cascade's cost fixed (L4).
- **Kepler rails and gravity**: one ephemeris in the native core (bodies on Kepler orbits, moons around planets, seekable in time)
  and restricted n-body gravity, applied as the tidal residual to ships, the low-attention tier's rows, bolts and debris; the brake
  and the AI get it as feed-forward.
- **Star system data**: `data/star_systems.json` grows bodies with their elements (Q1 to Q3); scenarios spawn relative to a body,
  a station or an orbit, and set an epoch (Q7, Q9).
- **Flying under gravity**: the speed clamp (Q4), the assist's and brake's reference (Q5), the HUD's reference and altitude (Q6).
- **Scaled space**: a render layer for anything beyond about 50 km (planets, moons, the sun), a generated planet with an atmosphere
  shader, the sun's disc and glow, the key light and the lens flare from the true sun direction, the planet's shadow on the near
  world.
- **The jumpgate**: references, a `jumpgate` generator, the gate in the game with its vortex, broadcasting to 1 000 km.
- **Far representations** for the station's stand-in, the gate and the planets, so each is seen at every distance with no pop.
- Console commands and providers for all of it (§6.4), `SettingsSchema` entries for every new setting, `info.md` kept current.

Out (explicitly):
- Babylon 5 itself (M7: M6 places M4's `b5_station` stand-in where the station will be). Launch bays (M7).
- Time warp, the trajectory preview and the nav computer (M9). Other planets as places to fly to (M9) and other systems (M10).
- Hyperspace (M11): M6 keeps one frame per space as a seam, nothing more.
- Finite reaction mass. Landing on, or atmospheric flight near, a planet: a ship that hits the planet or drops below its
  atmosphere's top is destroyed (a stated rule, not a simulation).
- Capital ships and blast damage (M12).

## Early start (2026-11-10)

Four tasks have no dependency on M5's open work and can start before M5 is accepted, if the maintainer says where they run (a
branch or a worktree; `CLAUDE.md` forbids an agent making its own branch):
- **T01** (moving-frame audit and design): reading and writing only; its result is this file's Design section, revised.
- **T02** (ephemeris and gravity kernel): engine-free Rust in **new files only** under `native/src/`. It must not touch the row
  files M5-T35 (native allocation pass) and M5-T36 (one native constants table) are changing; it is wired in by T04, after M5.
- **T11's generator half** (the planet textures in `tools/procgen`) and **T13** (the jumpgate generator): Python only, once Q10 and
  Q11 have references.

## Design (to go into `docs/architecture.md` §19)

### D64 The moving, free-falling frame

- `WorldFrame.origin` (`UniversePos`) and `origin_velocity` (64-bit) are propagated each tick as a test particle under the system's
  gravity (leapfrog, the same integrator as T02's, sim time from `SimClock`). Local physics then feels only the tidal residual,
  `g(origin + x) - g(origin)`, computed in 64-bit as an exact difference, never linearised.
- **Velocity rebase** when the focus's speed relative to the frame passes the threshold (Q8): `v` is subtracted from every body's
  `linear_velocity`, every native row's velocity (ships, tier rows, bolts), every projectile, debris chunk and particle emitter, and
  `origin_velocity += v`. Same tick slot as the position rebase (priority 0 in `World._physics_process`), same end-of-tick reset of
  the interpolation, and both rebases may fall in one tick (position first).
- **Velocities that outlive a tick** are relative to a reference, never to the frame: the HUD's reference, the assist and brake
  (D67), the AI's "stop" and station keeping, the mission triggers on speed. T01 lists every place that reads a World-frame
  velocity as absolute; each one is fixed in T05 or named as harmless.
- The rebase cascade (L4, `docs/research/m4-full-review.md`): the statics shift natively and the cached `Solid` shifts in place (a
  pure shift is not a new version), and hidden pool ships are skipped.

### D65 One ephemeris, in the native core

- Bodies move on Kepler orbits, one element set per body around its parent (moons around their planet, planets around the star),
  evaluated directly at any sim time (seekable, no state carried from tick to tick), so M9's warp can jump and M9's predictive
  drop-back can look ahead.
- The kernel is engine-free Rust under `test_the_kernels_hold_no_engine_type` (new files, D64's integrator beside it). GDScript
  reads body positions and velocities through one binding (`ScsEphemeris`, or methods on `ScsSimCore`; T02 decides), never through
  a second implementation: M4's L13 finding (constants mirrored by hand) is not repeated.
- What is not on a rail: anything at a Lagrange point (the station, if Q2 says so), ships and debris. They are test particles. T01
  sets the error budget for a station that is integrated while the bodies are analytic (the drift between a parked ship and the
  station over an orbit).

### D66 Restricted n-body gravity on everything

- Ships: the native flight step already takes `env_accel` per ship (world frame); it gets the tidal residual instead of zero.
- The low-attention tier: `tier_set_gravity`'s point sources (M4's moon stand-in) become the ephemeris's bodies.
- Bolts: the native bolt step adds `g_tidal * delta` before it moves a bolt; at zero gravity the step is bit-identical to today
  (the parity recordings in `tests/fixtures/` stay green).
- Debris chunks: their pull is applied by whatever T07 measures as cheapest within the error budget (per tick, or once per chunk
  for its short life); the rule is no GDScript per-chunk loop per tick if it shows in the tick.
- The brake and the AI's steering get the residual as feed-forward (`env_accel_b`), so a ship told to hold a point holds it.
- Gravity only matters near a star, planet or moon; nothing smaller pulls (`CLAUDE.md`).
- `GravityStandin` (M4-T07) and its install path are removed; the bench's `battle` layout gets its pull from a body in data.

### D67 Flying under gravity

- The speed clamp and the thrust fade follow Q4; the assist's safe speed and the brake's all stop are measured against the HUD's
  reference (Q5, Q6). A pure `ReferenceFrame` (`RefCounted`) gives the reference's position and velocity in the local frame each
  tick, from a node, a station, a gate or a body.
- The HUD shows `REF <name>` with its range and closing speed, the speed against the reference, and the altitude near a body.
- Hitting a planet or a moon, or dropping below its atmosphere's top, destroys the ship (Out, above): a rule from data, checked
  against the ephemeris each tick for the player and the AI rows.

### D68 Scaled space

- Anything beyond about 50 km that is not a ship (the star, planets, moons; far stations and gates when their far level asks for
  it) is drawn in a separate layer before the near world: placed at `camera_dir * (distance / scale)` with its true angular size,
  depth kept apart from the near world's, lit from the true sun direction.
- The planet is a procedural mesh with generated maps (`tools/procgen` asset kind `planet`) and an atmosphere scattering shader
  (limb, terminator, day and night sides); the sun is a disc with a glow coloured from `data/star_systems.json`. The `KeyStar`
  light and the lens flare follow the sun's true direction; the planet's shadow dims the key light on the near world.
- Precision rule: no position beyond the local space reaches the GPU as a world coordinate; the layer is camera-relative.

### D69 The jumpgate

- A `jumpgate` generator (references from Q11), a gate prop with collision and a `Targetable`, broadcasting to 1 000 km as M3-T17's
  buoys do (the AI sees it at that range, so a mission can send ships at it).
- The vortex: meshes and shaders only (D22), opened and closed by the gate when a ship jumps in or out; it replaces `JumpArrival`
  for gate traffic (Q12). Missions and encounters ask for an arrival through the gate in data.

### D70 Far representations

- The station's stand-in, the gate and the planets stay visible from the near field out to their broadcast range: the importer's
  levels, then a far dot or a scaled-space impostor; generated far levels only where one earns its place (§14.4). Hand-offs keep
  M4's hysteresis and show no pop (a test checks the drawn size across each hand-off).

### D71 Seams for M9 and M11

- The ephemeris is seekable (D65) and the integrator takes any step, so M9's on-rails warp reuses both.
- One `WorldFrame` per space: no autoload or static holds "the" frame, so M11's hyperspace adds a second one (T01 lists any that do).

## Acceptance criteria

| # | Criterion | Kind | Done |
|---|---|---|---|
| AC1 | Moving frame: the frame's origin free-falls in 64-bit (test: a frame with nothing in it follows the analytic orbit of a test particle to within the error budget T01 sets over one orbit); the velocity rebase fires at the threshold and leaves every universe position and universe velocity unchanged (test over ships, tier rows, bolts, debris, particles); `RebaseFight` runs with both rebases forced often; the parity recordings in `tests/fixtures/` stay green with gravity and the velocity rebase off | A | |
| AC2 | Rebase cost (L4): the statics shift natively and in place, hidden ships are skipped; the worst rebase tick at `bench battle 1000` is within 10 % of the median tick (Report P3: 13.07 against 10.50 ms), measured before and after | A | |
| AC3 | Ephemeris and gravity: Kepler positions and velocities match reference values for circular, elliptic and inclined orbits; a moon's orbit is around its planet; the ephemeris seeks to any time with no carried state; gravity on rows is identical with 1 and 6 threads and between `sim_step` threaded and `delayed`; Rust unit tests and GUT tests through the binding | A | |
| AC4 | Everything falls: a ship coasting in orbit beside the station's stand-in stays beside it over one orbit (within T01's budget); a bolt fired near the planet curves as the analytic path says; debris and the tier's rows feel the pull; the brake holds a point under gravity; `GravityStandin` is gone and the bench's `battle` layout runs with its pull from data | A | |
| AC5 | Flying under gravity: the clamp follows Q4; the assist's safe speed and the brake's all stop read against the reference (Q5); with assist on, the player can hold a low orbit; the HUD shows `REF <name>`, range, closing speed, the speed against the reference and the altitude near a body (Q6); hitting the planet or a moon destroys the ship | A | |
| AC6 | System data and scenarios: `data/star_systems.json` holds the bodies of Q1 with their elements, validated on load with the reason given; scenarios spawn relative to a body, a station or an orbit and set an epoch (Q7, Q9); every existing scenario and mission still loads and runs its headless tests | A | |
| AC7 | Scaled space: the star, Epsilon III and its moons are drawn at their true angular size and direction from anywhere in the local space and after any rebase (test on the computed placement); the key light and the lens flare follow the true sun direction; the planet's shadow dims the key light; on the maintainer's GPU `renderer = forward_plus`, FPS, draw calls and VRAM recorded with the planet in view | A | |
| AC8 | Jumpgate: the generator meets the output contract with its Python tests; the gate broadcasts to 1 000 km (test); a ship sent through it in a headless run arrives through the vortex; the vortex opens and closes from sim time; GPU numbers recorded with the vortex open | A | |
| AC9 | Far representations: the station's stand-in, the gate and the planet are drawn at every distance from 100 m to their broadcast range with no pop at a hand-off (test on drawn size); the cost at 1 000 km recorded | A | |
| AC10 | Cost: gravity and the moving frame add no more than 5 % to the `bench battle 1000` tick (measured before and after on an idle machine); the paired 13-ship AI budget (`test_ai_think_time`) still passes | A | |
| AC11 | Docs and the suite: `docs/architecture.md` §19 as built (and §14.1, §14.2 brought up to date), a `docs/playtest.md` M6 section, the roadmap row, `info.md`; `scripts/run_tests.sh` green once, at the end | A | |
| AC12 | (H) The maintainer flies it: an orbit beside the station's stand-in, the planet and the sun from orbit and from 1 000 km, the atmosphere's limb and terminator, the jumpgate and its vortex, the assist and brake under gravity, a dogfight across several velocity rebases with nothing seen to jump | H | |

## Working rules for M6

- **Tracks.** A (frame and gravity: T01, T02, T04 to T08), B (system data and scenarios: T03, T09), C (scaled space and far
  representations: T10, T11, T12, T15), D (the jumpgate: T13, T14). Inside a track the order holds. If work goes one task at a
  time, the order is T01, T02, T03, T04, T05, T06, T07, T08, T09, T10, T11, T12, T13, T14, T15, T16.
- **One working copy** on branch `m6` in the main checkout, no task branches, as in M5; early-start work runs where the maintainer
  says (Early start, above).
- **Locks** as in M5: Godot runs through `flock /tmp/m6-godot.lock`, commits through `flock /tmp/m6-git.lock` and stage only the
  task's paths, GPU checks through `flock /tmp/gpu.lock`.
- **Native changes** keep the parity recordings green (`CLAUDE.md`); new native behaviour gets its own Rust and GUT tests; results
  identical with 1 and 6 threads and between `sim_step` threaded and `delayed`. No GDScript fallback.
- **Performance** (T05, T06, T07): measure `bench battle 1000` before and after with `scripts/bench_quick.sh` on an idle machine;
  numbers in the task's Done notes.
- **Tests.** Each task runs the Python and GUT files it touched and its new tests; the full suite runs once, in T16. Test first for
  the pure classes (`ReferenceFrame`, the system loader, the scaled-space placement, the vortex's timing).
- **Screenshots** to `references/screenshots/<request>/` in the main checkout. Visual judgement is (H).
- After each task: its row says `done` with its Done notes, in the same commit; push `m6` (the maintainer's rule from M5).

## Task breakdown (ordered)

| Task | Track | Title | Depends on | Agent | Why | Status |
|---|---|---|---|---|---|---|
| T01 | A | Moving-frame audit and design: every World-frame velocity, the rebase order, the error budgets, §19's draft (early start) | - | Fable | Cross-cutting invariants over GDScript, Jolt and the native rows; mistakes surface late | not started |
| T02 | A | Ephemeris and gravity kernel: Kepler rails, the body tree, n-body and tidal pull, the integrator (early start, new native files) | T01 | Fable | Precise, deterministic numerics that M9 and M11 reuse | not started |
| T03 | B | Star system data: bodies and elements in `data/star_systems.json`, the loader, the `system` provider | T02, Q1 to Q3 | Sonnet | Data and validation on a clear format | not started |
| T04 | A | The free-falling frame: the origin as a test particle, `environment_accel` from the ephemeris | T02, T03 | Opus | Touches the tick order and every ship's force step | not started |
| T05 | A | The velocity rebase over every body, row, bolt, chunk, particle and interpolated node | T04 | Fable | The riskiest change of the milestone; every moving thing and the parity recordings | not started |
| T06 | A | L4: the rebase cascade natively, the cached solid shifted in place, hidden ships skipped | T05 | Opus | A measured native fix on the path T05 rewrote | not started |
| T07 | A | Gravity on everything: ships, tier rows, bolts, debris, the brake's and the AI's feed-forward; the gravity stand-in removed | T04 | Opus | Native kernels with parity at zero gravity | not started |
| T08 | A | Flying under gravity: the clamp, the assist's and brake's reference, the HUD's reference and altitude, planet impact | T07, Q4 to Q6 | Opus | Flight-model semantics the player feels | not started |
| T09 | B | Scenarios at true scale: spawns relative to bodies, stations and orbits, epochs, free flight beside the station's stand-in | T03, T08, Q7, Q9 | Opus | Every scenario and mission must keep working | not started |
| T10 | C | Scaled-space layer: placement, draw order and depth, the true sun direction, the planet's shadow | T04 | Fable | Precision and draw order in Forward+ at planetary distances; a design that later layers stand on | not started |
| T11 | C | The planet and its atmosphere: the `planet` generator and the scattering shader (generator half early) | T10, Q10 | Opus | Shader maths on T10's layer; the look is (H) | not started |
| T12 | C | The sun: disc and glow from the star's colour, the lens flare and key light on the true direction | T10 | Sonnet | A small shader and the existing flare | not started |
| T13 | D | Jumpgate references and the `jumpgate` generator (early start) | Q11 | Opus | Geometry read off references | not started |
| T14 | D | The jumpgate in the game: the prop, the vortex, 1 000 km broadcast, arrivals through the gate | T13, T09, Q12 | Opus | A new effect and the mission and encounter seams | not started |
| T15 | C | Far representations for the station's stand-in, the gate and the planets | T10, T14 | Opus | Hand-offs across three draw paths with no pop | not started |
| T16 | - | Integration, full suite, docs and acceptance | all | controller | One full run, the GPU check, the (H) list | not started |

### M6-T01 Moving-frame audit and design

- **Goal:** the facts and decisions every later A task builds on. Early start: reading and writing only.
- **Steps:** list every place, in GDScript and in `native/src/`, that holds or reads a velocity or position in the local frame:
  Jolt bodies, `Ship`, the native flight step, the tier's rows, bolt rows and `Projectile`, debris chunks, particle emitters (their
  `local_coords`), the interpolation reset, `RamTracker`'s contact windows, the HUD, the AI's perception and brains, mission
  triggers, the camera rig, the sound's Doppler, `CinematicShot`. For each: what a velocity rebase must do to it, or why it is
  harmless. List every place that treats a World-frame velocity as absolute (D64) and every global that assumes one frame (D71).
- **Decide and write down:** the integrator and its step (leapfrog at the physics tick, or a different one), the error budgets for
  AC1 and AC4 (a parked ship against an integrated station over one orbit), where the velocity rebase sits in the tick against the
  position rebase and the native sync, and draft answers for Q4 to Q6 with their consequences for the assist and the AI.
- **Files:** this file's Design section (D64 to D71 revised), a short research note `docs/research/m6-moving-frame.md` with the
  audit table.
- **Done when:** the audit table covers every file that reads `linear_velocity`, a row velocity or `origin`; the maintainer has
  read the decisions and the drafts for Q4 to Q6.

### M6-T02 Ephemeris and gravity kernel

- **Goal:** AC3 (D65, D66's maths). Early start in new native files only.
- **Files:** `native/src/ephemeris.rs` (elements, Kepler's equation, the body tree), `native/src/gravity.rs` (n-body sum, tidal
  residual, the integrator), their Rust tests, the binding (`native/src/ephemeris_rows.rs` or methods on `ScsSimCore`, wired in T04),
  `tests/unit/test_ephemeris.gd` once wired.
- **Notes:** elliptic orbits only (e < 1), solved by Newton's method with a fixed iteration rule so every run gives the same bits;
  64-bit throughout; the residual computed as an exact difference. The pull over rows is a pure function over a frozen list of
  body positions, so it runs in the worker job or on the main thread with the same result. Test values from closed-form orbits.
- **Done when:** AC3 in Rust; the kernel holds no engine type (the guard test).

### M6-T03 Star system data

- **Goal:** the data half of AC6.
- **Files:** `data/star_systems.json` (bodies with parent, mass or `gm`, radius, atmosphere top, elements, epoch of elements, and
  places such as the station's point and the gate's), `src/world/star_system.gd` (`RefCounted`: load, validate, hand to the core),
  `tests/unit/test_star_system.gd`, provider `system` (bodies and their positions now), `info.md`.
- **Done when:** the file holds Q1 to Q3's answers, validated with reasons; the core gets the bodies from it.

### M6-T04 The free-falling frame

- **Goal:** the frame half of AC1.
- **Files:** `src/world/world_frame.gd` (origin and `origin_velocity` propagated each tick; `environment_accel` from the core),
  `src/ship/ship.gd` and the flight batch (the residual into `env_accel`), the core's binding, `tests/integration/test_free_fall.gd`.
- **Notes:** `environment_field` stays the seam; the callable now calls the core. The frame is propagated in the slot T01 chose.
- **Done when:** an empty frame follows the analytic orbit within the budget; a ship at rest in the frame stays at rest to within
  the residual; the parity recordings are green with gravity off.

### M6-T05 The velocity rebase

- **Goal:** the rebase half of AC1 (D64).
- **Files:** every file in T01's audit table that needs a change; `tests/fixtures/rebase_fight.gd` (both rebases forced),
  `tests/integration/test_velocity_rebase.gd`; the native rows' `shift` grows a velocity part.
- **Notes:** universe position and universe velocity of every object unchanged across a rebase (the test sums them before and
  after). The interpolation rule is the position rebase's: reset at the end of the tick. Particles stay in their node's frame.
  Measure the rebase's cost at `bench battle 1000`.
- **Done when:** AC1; a dogfight across many velocity rebases shows no jump in a recorded run (the test compares drawn positions).

### M6-T06 L4: the rebase cascade

- **Goal:** AC2.
- **Files:** `src/world/static_rows.gd`, `src/perf/sim_core.gd`, the resolvers' cached solids, `src/world/world_frame.gd`, the
  native statics' shift.
- **Done when:** AC2, numbers before and after in the Done notes.

### M6-T07 Gravity on everything

- **Goal:** AC4 apart from the HUD (D66).
- **Files:** `native/src/flight_step.rs` (input only), `native/src/tier.rs` and `tier_rows.rs` (bodies for point sources),
  `native/src/bolt_kernels.rs` (the pull before the move), the debris path T07 measures, the brake's and the AI's feed-forward,
  `src/perf/standins/gravity_standin.gd` removed with its install path and the bench layout moved to data, tests in Rust and GUT.
- **Done when:** AC4; bit-identical results at zero gravity; AC10's cost measured.

### M6-T08 Flying under gravity

- **Goal:** AC5 (D67).
- **Files:** `src/ship/speed_governor.gd`, `src/ship/ship.gd`, the assist's and the brake's inputs, `src/world/reference_frame.gd`
  (pure), the HUD's reference and altitude (`hud_input.gd`, `hud_frame.gd`, `hud_painter.gd`), the planet-impact rule, settings for
  anything new, tests (a headless low orbit held with assist on; the brake's stop against the reference).
- **Done when:** AC5.

### M6-T09 Scenarios at true scale

- **Goal:** the scenario half of AC6.
- **Files:** `ScenarioLoader` (spawns relative to a body, a station point or an orbit; `epoch`), `data/scenarios/*.json`, the
  missions' data where they name positions, `Main`'s start, the encounter director's spawn shell (it spawns relative to the
  player's reference), tests for each spawn form.
- **Notes:** the Civilian escort's belt and beacons keep their layout, moved as a whole to the station's orbit; every mission's
  headless tests run unchanged in outcome.
- **Done when:** AC6; free flight starts beside the station's stand-in with the planet in view.

### M6-T10 Scaled-space layer

- **Goal:** the placement half of AC7 (D68).
- **Files:** `src/environment/scaled_space.gd` (the layer and its camera), `src/environment/scaled_placement.gd` (pure: direction,
  distance, angular size), `src/environment/space_environment.gd` (the key light's direction from the sun), its tests.
- **Notes:** the design question is how the layer's depth and the near world's coexist in Forward+ (a separate viewport, a second
  camera pass, or reversed depth with a clamp) and what each costs; decide by measuring on the maintainer's GPU. The planet's shadow
  on the near world is a key-light factor from the ephemeris (sun, planet and camera), not a shadow map.
- **Done when:** the placement tests; a placeholder sphere for the planet and the sun draws at the right size from anywhere and
  after any rebase; GPU numbers recorded.

### M6-T11 The planet and its atmosphere

- **Goal:** the planet half of AC7.
- **Files:** `tools/procgen/assets/planet.py` (albedo, height or normal, clouds, night side if the references show one; early
  start), its Python tests, the planet's material and the atmosphere shader on T10's layer.
- **Done when:** AC7's planet; a look sheet (day, terminator, night, limb from orbit and from 1 000 km) in
  `references/screenshots/M6-T11 planet/` for the maintainer (H).

### M6-T12 The sun

- **Goal:** the sun half of AC7.
- **Files:** the sun's disc and glow on T10's layer, `src/rendering/lens_flare_aim.gd` and the flare's source on the true
  direction, the star's colour from `data/star_systems.json`.
- **Done when:** AC7's sun and light; a look sheet for the maintainer (H).

### M6-T13 Jumpgate references and generator

- **Goal:** the generator half of AC8. Early start once Q11 has references.
- **Files:** `docs/design-references.md` (a jumpgate section: shape, proportions, colours from the references, sources listed),
  `tools/procgen/assets/jumpgate.py`, its tests and registry entry.
- **Done when:** the output contract and Python tests; a look sheet for the maintainer (H).

### M6-T14 The jumpgate in the game

- **Goal:** AC8 (D69).
- **Files:** `src/props/jumpgate.gd`, the vortex (`src/props/jump_vortex.gd`, its shader and mesh), the broadcast, arrivals through
  the gate for missions and encounters (data), `JumpArrival` kept for open points (Q12), the `gate` provider and commands, tests.
- **Done when:** AC8.

### M6-T15 Far representations

- **Goal:** AC9 (D70).
- **Files:** `src/rendering/lod_switcher.gd` and `far_dots.gd` for the large props, the scaled-space impostors from T10, the
  station's stand-in, the gate and the planets.
- **Done when:** AC9.

### M6-T16 Integration, full suite, docs and acceptance

- **Goal:** AC10, AC11 and the (H) checklist for AC12.
- **Steps:** §19 in `docs/architecture.md` as built (and §14.1, §14.2 updated); the M6 section of `docs/playtest.md` with the (H)
  checklist; the roadmap row; `scripts/run_tests.sh` once, read from the suite's own totals; the GPU check on the maintainer's
  machine; then ask the maintainer to confirm the milestone, and once confirmed merge `m6` into `main`.
- **Done when:** the maintainer confirms M6.
