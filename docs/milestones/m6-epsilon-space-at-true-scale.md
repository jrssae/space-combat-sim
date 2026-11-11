# Milestone 6: Epsilon Space at True Scale

> "The real neighbourhood." (`docs/roadmap.md`)

**Status:** planned 2026-11-10, ahead of time; **not started.** M5 is the current milestone until the maintainer accepts it.
**2026-11-10 (maintainer):** branch `m6` was cut from `m5` at `5d81686`, with `main`'s M6 and M7 plans merged in, so the early
start (below) runs on it; `m6` takes M5's later work by merging `m5` into it (merges, no rebase, as M5's Q27). The rest of M6 waits
as the early-start section says. T01 is `in progress` (its audit and decisions are written and wait for the maintainer to
read them); every other task is `not started`. The planning questions (Q1 to Q12) are open: the proposed answers below are the
planner's defaults, and each task that depends on one waits for the maintainer's answer. This plan was written against `m5` at
`5d81686`, so it names M5 files (§18, M5-T21, `JumpArrival`) that reach `main` when M5 merges.

Read `docs/architecture.md` first, especially §10 (scale and units), §14.1 (coordinates and frames), §14.2 (gravity), §14.3 (time
acceleration, which M9 builds and M6 must not block), §14.4 (far-field rendering), §14.5 (hyperspace, M11), §17.13 (the native
core and its threading rules) and §17.14 (the low-attention tier). The roadmap's "Required: gravity" section is part of this
milestone's scope. Tasks are ordered inside each track; each is one PR-sized unit and names a recommended agent model.

## Goal

Put the game in the real Epsilon Eridani system at true scale. The local space becomes a moving, free-falling frame: it follows
the player's orbit, so local physics feels only the tidal residual of gravity and float32 speeds stay small (the velocity rebase).
The star and Epsilon III move on Kepler rails, and every ship, bolt and piece of debris falls toward the strongest
nearby body, so a bolt fired near the planet curves. Flight assist, the brake and the HUD read speed against the dominant body or
station instead of the frame. The planet and the sun are drawn in a scaled-space layer with an atmosphere, lit from the true sun
direction, and stay visible from orbit. The first jumpgate is built, with its vortex, and broadcasts to 1 000 km. M4's gravity
stand-in and the rebase cascade (L4) go. M7 puts Babylon 5 into this space, and M9 (time warp) and M11 (hyperspace) build on the
frame without rewriting it.

## Planning questions (open, 2026-11-10)

| Q | Question | Proposed answer (planner's default, until the maintainer answers) | Answer |
|---|---|---|---|
| Q1 | Which bodies make up the Epsilon system in M6, and their sizes and orbits? | The star (Epsilon Eridani, K2V, 0.82 solar masses, already in `data/star_systems.json`), **Epsilon III** and **its moons**, nothing else; other planets wait for M9's travel. Epsilon III's radius, mass, orbit and moon count from the maintainer's references, or an Earth-sized planet with one large moon if there are none | **The star and Epsilon III, no moons.** From the show's notes, 0.75 g at the surface; at Earth's density that is a diameter of about **9 560 km** (radius 4 780 km, `GM` 1.68e14 m^3/s^2, 2.5e24 kg, 0.42 Earth masses). Its orbit around the star stays the planner's (0.6 AU) until references say otherwise (maintainer, 2026-11-10) |
| Q2 | Where is Babylon 5? | At a Lagrange point (L4 or L5) of Epsilon III and its large moon, as the show's background puts it, if the maintainer confirms; else a circular orbit around Epsilon III with the planet filling a large part of the view. M6 places the station's stand-in there; M7 replaces it | **A circular orbit around Epsilon III**, on a rail (D65), its radius tuned so the planet looks from the station as it does in the show; start at about **27 500 km** from the centre (the planet about 20 degrees across, 2 470 m/s, a 19.4 h orbit). Epsilon III has no moon, so there is no planet–moon L5, and the star–planet L5 (0.6 AU away) would make the planet a dot. The goal is fun, not precision (maintainer, 2026-11-10) |
| Q3 | Where is the jumpgate? | Near the station: about 50 km from it, in the same orbit, so a ship from the gate reaches the station in a few minutes and both broadcast to each other | **As proposed**: about 50 km from the station on the same orbit, tunable in data (maintainer, 2026-11-10) |
| Q4 | The hard 9 999 m/s speed clamp in `Ship` | **Drop the clamp**; keep only the thrust fade (`SpeedGovernor.thrust_gain`), measured against the dominant body (Q5). A body falling toward the star may then go as fast as physics says | **Keep a cap, measured against the reference.** Against a planet or moon, speed is read against the circular orbit at the ship's altitude, so a ship in a steady orbit reads about 0 and the 9 999 m/s cap and fade apply on top of the orbit; against a place (station, gate) as today (maintainer, 2026-11-10; D67) |
| Q5 | What is flight assist's "speed" under gravity? | **Relative to the HUD's reference** (Q6): the assist's safe speed, the brake's all stop and the thrust fade all read the ship's velocity minus the reference's. A ship that brakes to a stop in orbit beside the station stays beside it; a ship that brakes far from anything stops against the dominant body | **Against the reference**, as T01's draft; against a planet or moon the brake **settles the ship into a circular orbit** at its altitude instead of stopping it against the body's centre (maintainer, 2026-11-10; D67) |
| Q6 | The HUD's reference point (the launch point today) | Set by the mission (a station, bay, gate or body), else the nearest of the station, the gate and the dominant body, its name shown beside `REF`; near a body the HUD also shows altitude | **T01's draft** (below), accepted (maintainer, 2026-11-10) |
| Q7 | Where free flight and the sandbox scenarios start | Beside the station's stand-in in its orbit (Q2), with the planet in view; the old origin-at-rest scenarios keep their layout around that point | open |
| Q8 | The velocity rebase threshold | 200 m/s relative to the frame (architecture §14.1), with the same end-of-tick interpolation rule as the position rebase | **2 000 m/s**, the frame riding its anchor below it (T01's D64, accepted by the maintainer, 2026-11-10) |
| Q9 | The start epoch (the planet's phase, day or night under the station) | Each scenario sets an epoch; free flight seeds one per run, as it seeds its encounters | open |
| Q10 | References for Epsilon III and the sun's look | The maintainer's references (`docs/design-references.md`; per the standing rule, colours and textures from show images); without them, a rocky planet with thin clouds and a blue limb | **Epsilon III: one show still** (`references/Epsilon III planet.png`, not committed), described in `docs/design-references.md` ("Epsilon III"): a dry rust-and-tan rocky world with strong relief, no oceans, faint wisps at most, a hard terminator and a faint warm limb, not a blue one. The sun's look is still open (maintainer, 2026-11-10) |
| Q11 | References for the jumpgate and its vortex | The maintainer's references; the jumpgate gets a section in `docs/design-references.md` before its generator starts (T13) | **The gate's shape and proportions read off the maintainer's model `references/EA_Jump_Gate.stl`** (nothing copied: geometry generated by code); colours and the vortex's look from show stills found online, described in our own words (no image committed) (maintainer, 2026-11-11) |
| Q12 | M5's `JumpArrival` (a flash where raiders appear) | It stays for open jump points far from the gate; ships that use the gate come through the vortex (T14) | open |

### T01's drafts for Q4 to Q6 and Q8 (2026-11-10; the maintainer's answers are in the table above: Q6 and Q8 as drafted, Q4
and Q5 changed to read speed against the local orbit near a body)

- **Q4 (draft): drop the hard clamp** in `Ship`, the native flight step and the tier. It clamps a frame speed, which a
  velocity rebase changes, and 9 999 m/s is below escape speed in low orbit (10 851 m/s). Keep the thrust fade, read against the
  reference (Q5), **but only while the reference is a place or an object**. Against a body there is no fade and no assist cap:
  in a 400 km orbit (7 673 m/s) the fade would leave 64 % of the thrust and none above 9 999 m/s, and the assist's 5 000 m/s cap
  would cancel every prograde burn, so AC5's low orbit could not be held. Jolt's 10 000 m/s cap stays as a backstop that the
  velocity rebase keeps out of reach.
- **Q5 (draft): yes, against the reference.** Each ship has a rest velocity (the reference's velocity in the local frame); the
  safe speed, the all stop and the fade read `v - v_rest`. The brake holds station on the reference: it also gets the
  reference's own acceleration as feed-forward, beside `env_accel`. The AI uses the World's rest velocity (the anchor's), fed
  once where the brains get their velocities, so "stop", cruise and run-up speeds mean speed against the place and no brain
  changes. Holding the brake far from any place stops the ship against the body, which is a de-orbit burn; the HUD's `REF`
  name says what it will stop against.
- **Q6 (draft):** the mission's reference if it sets one; else the nearest place (station, gate) whose broadcast range holds the
  ship, with a tenth of hysteresis as the far dots have; else the dominant body (the largest pull at the ship). The altitude
  shows while a body is the reference or the ship is within one radius of its surface. The speed readout jumps when the
  reference changes (0.5 km/s against the station, 7.7 km/s against the planet); the name beside `REF` is what explains it.
- **Q8 (T01 recommends a different answer): 2 000 m/s, and the frame rides the anchor below it** (D64). At 200 m/s a Starfury
  triggers a rebase after 7 s of thrust, and from then on every rock, buoy, station and stored place moves each tick. float32
  does not need it: at 2 000 m/s the smallest acceleration a velocity can show is 7.3e-3 m/s^2, eight times finer than the
  game's 9 999 m/s today. Numbers in `docs/research/m6-moving-frame.md`, section 5.

## Scope

In:
- **The moving frame**: `WorldFrame` propagates its origin as a free-falling test particle in 64-bit; the **velocity rebase** on
  (Q8), over every body, row, bolt, debris chunk, particle system and interpolated node; the rebase cascade's cost fixed (L4).
- **Kepler rails and gravity**: one ephemeris in the native core (bodies on Kepler orbits, moons around planets, seekable in time)
  and gravity from the strongest nearby body (D66), applied as the tidal residual to ships, the low-attention tier's rows, bolts and debris; the brake
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

Four tasks have no dependency on M5's open work and can start before M5 is accepted. They run on branch `m6` (2026-11-10). T03
(star system data) can join them once Q1 to Q3 are answered; T04 to T08 wait for M5's performance block (M5-T33 to T36 and T38),
which changes the same native rows and rebase path:
- **T01** (moving-frame audit and design): reading and writing only; its result is this file's Design section, revised.
- **T02** (ephemeris and gravity kernel): engine-free Rust in **new files only** under `native/src/`. It must not touch the row
  files M5-T35 (native allocation pass) and M5-T36 (one native constants table) are changing; it is wired in by T04, after M5.
- **T11's generator half** (the planet textures in `tools/procgen`) and **T13** (the jumpgate generator): Python only, once Q10 and
  Q11 have references.

## Design (to go into `docs/architecture.md` §19)

### D64 The moving, free-falling frame (revised by T01; evidence in `docs/research/m6-moving-frame.md`)

- **The anchor.** Each `WorldFrame` has one anchor: the free-falling point its scene is built around (the station's point; a
  point on an orbit for a scenario with no station). It is a 64-bit test particle in the native core. **A `UniversePos` is
  relative to its World's anchor**, in axes that do not rotate. So every stored place (waypoints, posts, trigger points, wave
  anchors) and every static row stays valid with no change: a barycentric place would fall 580 m behind per tick. Barycentric
  positions live only in the ephemeris.
- **The frame rides its anchor**: `origin_velocity` (64-bit, against the anchor) is zero and `origin` moves only by position
  rebases, as today. Local physics feels `g(x) - g(anchor)`, an exact 64-bit difference. Any frame acceleration gives the same
  universe motion, so this is as honest as falling at the origin, and rocks, buoys and the station stay still in Jolt.
- **Velocity rebase** (Q8, 2 000 m/s proposed): when the focus passes the threshold against the frame, boost onto the focus:
  `dv` comes off every body's `linear_velocity`, every row velocity in the core (ships, tier rows and their cruise, bolts),
  every projectile, chunk, wreck, explosion, emitter and far flash, and off `RamTracker`'s remembered velocities;
  `origin_velocity += dv`. The frame then falls freely at its origin, `origin` moves each tick, and anchor-tied things (static
  rows natively by one vector, the few anchor-tied nodes) move with the anchor. When the focus is back under half the threshold
  against the anchor, boost onto the anchor and ride again.
- **A boost is exact and needs no interpolation reset**: no position jumps. Universe position and velocity of everything are
  unchanged (T05's test).
- **The integrator**: kick, then drift, once per physics tick in 64-bit: `v += g dt; x += v dt`. It is leapfrog with the
  velocity held half a step behind, symplectic (no energy drift, phase error about `(n dt)^2 / 24`), and it is the step Jolt
  and the tier already take, so a body's universe motion does not depend on which frame carries it. An orbit is started half
  a kick back (`v0 - g dt / 2`), or it is 256 m off mid-orbit. One fixed step, fixed operation order, no adaptive substeps:
  the same bits on every run. M9's warp composes the same `kick` and `drift` with its own step.
- **One gravity sample per tick.** A first slot (before the tier director at -12) takes the tick's time once, places the
  bodies against the anchor and fixes the frame's acceleration. Every mover of the tick uses that sample, and the frame's own
  step uses it too, last in the tick (after `sync_out`), so the frame moves with Jolt. Needed because the flight batch (-1)
  applies forces before the rebase slot, and `SimClock` advances at priority 0.
- **The tick**: sample; core sync (-11); drivers, brains, flight batch (-10 to -1); `World` at 0: position rebase, then
  velocity rebase (both may fall in one tick; the core's `shift` then its new `boost`, both bump `rows_version`); bolts (1);
  targeting, hits, rams, missions (100 to 400); the settler (position rebases only); `sync_out`; the frame's step.
- **Speeds are read against a rest velocity**, never the frame: `v_rest` is the reference's velocity in the local frame (D67),
  zero while the frame rides the anchor and the anchor is the reference, so today's results are bit-identical there. T01's
  note lists every reader (section 3); T05 boosts the holders, T08 changes the readers.
- **Error budgets** (a 400 km circular orbit of an Earth-sized planet, 5 545 s, 60 Hz). AC1: an empty frame within **0.05 m**
  of the analytic orbit at every tick (measured 0.005 m) and within 0.1 m at the end of an `e` 0.3 orbit; energy (the velocity brought to the tick by half a kick) within 1e-8 with no trend; that one is a budget, not yet measured. AC4: a ship coasting along the track from the station's stand-in stays within **0.5 m** of a 64-bit run of
  the same start at up to 3 km, and 5 m at 10 km (measured 0.08 m and 1.6 m). Both tests use this low orbit from a fixture
  system whatever Q2 says (the station's own orbit is 19.4 h, 4.2e6 ticks). AC4's ship is placed along the track: a ship 1 km
  above the station is on another orbit and ends 37.7 km behind.
- The rebase cascade (L4): the statics shift natively and the cached `Solid` shifts in place (a pure shift is not a new
  version), and hidden pool ships are skipped. The same in-place shift carries the statics while the frame is off its anchor.

### D65 One ephemeris, in the native core

- Bodies move on Kepler orbits, one element set per body around its parent (moons around their planet, planets around the star),
  evaluated directly at any sim time (seekable, no state carried from tick to tick), so M9's warp can jump and M9's predictive
  drop-back can look ahead.
- The kernel is engine-free Rust under `test_the_kernels_hold_no_engine_type` (new files, D64's integrator beside it as `kick`
  and `drift`). GDScript reads body positions and velocities through one binding (`ScsEphemeris`, or methods on `ScsSimCore`;
  T02 decides), never through a second implementation: M4's L13 finding (constants mirrored by hand) is not repeated.
- The kernel answers in 64-bit **relative to a point it is given** (the anchor), so no caller subtracts two barycentric
  numbers of 1e11 m (a step of 1.5e-5 m there).
- **The station is on a rail** (Q2): a circular orbit around Epsilon III, evaluated like a body, so nothing drifts against it.
  The ephemeris places a point on another orbit at a phase offset (the gate shares the station's orbit, Q3).
- What is not on a rail: ships and debris. They are test particles. A frame's anchor is a test particle only when it is not a
  place on a rail (a scenario's point in a low orbit). Budgets in D64.

### D66 Gravity from the strongest nearby body, on everything

- **Only the strongest nearby body pulls** (maintainer, 2026-11-10): each body has a zone where its pull is at least
  `a_min` = **0.5 m/s^2**, radius `sqrt(GM / a_min)` (about 18 300 km for Epsilon III; about 3 100 km for a Moon-like moon
  elsewhere). Outside every zone nothing pulls; inside a moon's zone the moon takes over from its planet. The pull fades smoothly to
  zero over a band at the zone's edge, so crossing it is no jolt. The star never pulls near a planet: the frame falls with it.
- The residual a frame feels is `g(x) - g(anchor)`, both under the same rule. Babylon 5's orbit (about 27 500 km, a pull of 0.22
  m/s^2) is outside Epsilon III's zone, so the space around it has no pull at all and a ship holds station there with no
  effort; gravity is felt closer in to the planet. If tuning the look brings the orbit inside 18 300 km, the station's space
  feels only the tidal residual (under 1e-4 m/s^2 within 1 km).

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
  reference (Q5, Q6). **Against a planet or moon, the rest velocity is the circular orbit's velocity at the ship's position**
  (prograde, in the orbit's plane), so a steady orbit reads about 0, the 9 999 m/s cap applies on top of it, climbing or escaping
  is just thrust, and the brake settles the ship into that circular orbit. Against a place it is the place's velocity. A pure `ReferenceFrame` (`RefCounted`) gives the
  reference's position, velocity and acceleration in the local frame each tick, from a node, a station, a gate or a body.
- The native flight step takes the rest velocity beside `env_accel` and hands `v - v_rest` to the brake, the fade and the cap;
  the brains get their velocities with the World's rest velocity taken off, at the one place they are fed.
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
- The vortex: meshes and shaders only (D22), opened and closed by the gate when a ship jumps in or out; **orange/yellow for a
  departure into hyperspace, blue for an arrival from it** (maintainer, 2026-11-11; reference video
  https://www.youtube.com/watch?v=2k8SRxOYC_U); it replaces `JumpArrival`
  for gate traffic (Q12). Missions and encounters ask for an arrival through the gate in data.

### D70 Far representations

- The station's stand-in, the gate and the planets stay visible from the near field out to their broadcast range: the importer's
  levels, then a far dot or a scaled-space impostor; generated far levels only where one earns its place (§14.4). Hand-offs keep
  M4's hysteresis and show no pop (a test checks the drawn size across each hand-off).

### D71 Seams for M9 and M11

- The ephemeris is seekable (D65) and the integrator takes any step, so M9's on-rails warp reuses both.
- One `WorldFrame` per space, each with its own anchor, so M11's hyperspace adds a second one. M6's new state (the anchor, the
  gravity sample, the rest velocity) lives on the `WorldFrame` and its core, never in an autoload or a static.
- T01 found statics that do assume one frame (`SimCore._current`, `StaticRows`, `ContactScan._shared`, the directors'
  `_current`, the `_live` lists, the console's `world` provider; the note's section 4). M6 adds none and fixes none; M11 does.
- M9 changes the anchor when the player travels: a hand-over that converts or drops the places held against the old one.

## Acceptance criteria

| # | Criterion | Kind | Done |
|---|---|---|---|
| AC1 | Moving frame: the frame's origin free-falls in 64-bit (test: a frame with nothing in it follows the analytic orbit of a test particle to within the error budget T01 sets over one orbit); the velocity rebase fires at the threshold and leaves every universe position and universe velocity unchanged (test over ships, tier rows, bolts, debris, particles); `RebaseFight` runs with both rebases forced often; the parity recordings in `tests/fixtures/` stay green with gravity and the velocity rebase off | A | |
| AC2 | Rebase cost (L4): the statics shift natively and in place, hidden ships are skipped; the worst rebase tick at `bench battle 1000` is within 10 % of the median tick (Report P3: 13.07 against 10.50 ms), measured before and after | A | |
| AC3 | Ephemeris and gravity: Kepler positions and velocities match reference values for circular, elliptic and inclined orbits; a moon's orbit is around its planet; the ephemeris seeks to any time with no carried state; gravity on rows is identical with 1 and 6 threads and between `sim_step` threaded and `delayed`; Rust unit tests and GUT tests through the binding | A | |
| AC4 | Everything falls: a ship coasting in orbit beside the station's stand-in stays beside it over one orbit (within T01's budget); a bolt fired near the planet curves as the analytic path says; debris and the tier's rows feel the pull; the brake holds a point under gravity; `GravityStandin` is gone and the bench's `battle` layout runs with its pull from data | A | |
| AC5 | Flying under gravity: the clamp follows Q4; the assist's safe speed and the brake's all stop read against the reference (Q5); with assist on, the player can hold a low orbit; the HUD shows `REF <name>`, range, closing speed, the speed against the reference and the altitude near a body (Q6); hitting the planet or a moon destroys the ship | A | |
| AC6 | System data and scenarios: `data/star_systems.json` holds the bodies of Q1 with their elements, validated on load with the reason given; scenarios spawn relative to a body, a station or an orbit and set an epoch (Q7, Q9); every existing scenario and mission still loads and runs its headless tests | A | |
| AC7 | Scaled space: the star and Epsilon III are drawn at their true angular size and direction from anywhere in the local space and after any rebase (test on the computed placement); the key light and the lens flare follow the true sun direction; the planet's shadow dims the key light; on the maintainer's GPU `renderer = forward_plus`, FPS, draw calls and VRAM recorded with the planet in view | A | |
| AC8 | Jumpgate: the generator meets the output contract with its Python tests; the gate broadcasts to 1 000 km (test); a ship sent through it in a headless run arrives through the vortex; the vortex opens and closes from sim time; GPU numbers recorded with the vortex open | A | |
| AC9 | Far representations: the station's stand-in, the gate and the planet are drawn at every distance from 100 m to their broadcast range with no pop at a hand-off (test on drawn size); the cost at 1 000 km recorded | A | |
| AC10 | Cost: gravity and the moving frame add no more than 5 % to the `bench battle 1000` tick (measured before and after on an idle machine); the paired 13-ship AI budget (`test_ai_think_time`) still passes | A | |
| AC11 | Docs and the suite: `docs/architecture.md` §19 as built (and §14.1, §14.2 brought up to date), a `docs/playtest.md` M6 section, the roadmap row, `info.md`; `scripts/run_tests.sh` green once, at the end | A | |
| AC12 | (H) The maintainer flies it: an orbit beside the station's stand-in, the planet and the sun from orbit and from 1 000 km, the atmosphere's limb and terminator, the jumpgate and its vortex, the assist and brake under gravity, a dogfight across several velocity rebases with nothing seen to jump | H | |

## Working rules for M6

- **Tracks.** A (frame and gravity: T01, T02, T04 to T08), B (system data and scenarios: T03, T09), C (scaled space and far
  representations: T10, T11, T12, T15), D (the jumpgate: T13, T14), E (test tiers: T17, T18). Inside a track the order holds.
  If work goes one task at a time, the order is T01, T17, T18, T02, T03, T04, T05, T06, T07, T08, T09, T10, T11, T12, T13, T14,
  T15, T16.
- **One working copy** on branch `m6` in the main checkout, no task branches, as in M5; early-start work runs where the maintainer
  says (Early start, above).
- **Locks** as in M5: Godot runs through `flock /tmp/m6-godot.lock`, commits through `flock /tmp/m6-git.lock` and stage only the
  task's paths, GPU checks through `flock /tmp/gpu.lock`.
- **Native changes** keep the parity recordings green (`CLAUDE.md`); new native behaviour gets its own Rust and GUT tests; results
  identical with 1 and 6 threads and between `sim_step` threaded and `delayed`. No GDScript fallback.
- **Performance** (T05, T06, T07): measure `bench battle 1000` before and after with `scripts/bench_quick.sh` on an idle machine;
  numbers in the task's Done notes.
- **Tests.** Four tiers from T17 on (2026-11-10, maintainer): **quick** (a few minutes, every area touched, run between changes),
  **standard** (the merge gate: everything except the balance runs), **balance** (the long fights whose verdict is a balance
  judgement, behind `GUT_BALANCE=1`) and **full** (standard plus balance). Each task runs the quick tier plus the Python and GUT
  files it touched and its new tests; the full tier runs once, in T16. Every task that adds or changes a test names its tier in
  the task's **Tests** line and its Done notes: quick for pure, fast files (under about 5 s alone, no SLOW gate), standard for
  scene-booting fights, whole-asset builds and anything SLOW-gated, balance only for a fight judged on balance. A quick file is
  added to `tests/quick_suite.txt` in the same commit. Test first for the pure classes (`ReferenceFrame`, the system loader, the
  scaled-space placement, the vortex's timing).
- **Screenshots** to `references/screenshots/<request>/` in the main checkout. Visual judgement is (H).
- After each task: its row says `done` with its Done notes, in the same commit. Do not push: the maintainer handles the
  remotes (`CLAUDE.md`; 2026-11-10, replacing M5's push-after-each-task rule).

## Task breakdown (ordered)

| Task | Track | Title | Depends on | Agent | Why | Status |
|---|---|---|---|---|---|---|
| T01 | A | Moving-frame audit and design: every World-frame velocity, the rebase order, the error budgets, §19's draft (early start) | - | Fable | Cross-cutting invariants over GDScript, Jolt and the native rows; mistakes surface late | done |
| T02 | A | Ephemeris and gravity kernel: Kepler rails, the body tree, the strongest body's pull and the tidal residual, the integrator (early start, new native files) | T01 | Fable | Precise, deterministic numerics that M9 and M11 reuse | done |
| T03 | B | Star system data: bodies and elements in `data/star_systems.json`, the loader, the `system` provider | T02, Q1 to Q3 | Sonnet | Data and validation on a clear format | done |
| T04 | A | The free-falling frame: the origin as a test particle, `environment_accel` from the ephemeris | T02, T03 | Opus | Touches the tick order and every ship's force step | not started |
| T05 | A | The velocity rebase over every body, row, bolt, chunk, particle and interpolated node | T04 | Fable | The riskiest change of the milestone; every moving thing and the parity recordings | not started |
| T06 | A | L4: the rebase cascade natively, the cached solid shifted in place, hidden ships skipped | T05 | Opus | A measured native fix on the path T05 rewrote | not started |
| T07 | A | Gravity on everything: ships, tier rows, bolts, debris, the brake's and the AI's feed-forward; the gravity stand-in removed | T04 | Opus | Native kernels with parity at zero gravity | not started |
| T08 | A | Flying under gravity: the clamp, the assist's and brake's reference, the HUD's reference and altitude, planet impact | T07, Q4 to Q6 | Opus | Flight-model semantics the player feels | not started |
| T09 | B | Scenarios at true scale: spawns relative to bodies, stations and orbits, epochs, free flight beside the station's stand-in | T03, T08, Q7, Q9 | Opus | Every scenario and mission must keep working | not started |
| T10 | C | Scaled-space layer: placement, draw order and depth, the true sun direction, the planet's shadow | T04 | Fable | Precision and draw order in Forward+ at planetary distances; a design that later layers stand on | not started |
| T11 | C | The planet and its atmosphere: the `planet` generator and the scattering shader (generator half early) | T10, Q10 | Opus | Shader maths on T10's layer; the look is (H) | in progress |
| T12 | C | The sun: disc and glow from the star's colour, the lens flare and key light on the true direction | T10 | Sonnet | A small shader and the existing flare | not started |
| T13 | D | Jumpgate references and the `jumpgate` generator (early start) | Q11 | Opus | Geometry read off references | done |
| T14 | D | The jumpgate in the game: the prop, the vortex, 1 000 km broadcast, arrivals through the gate | T13, T09, Q12 | Opus | A new effect and the mission and encounter seams | in progress |
| T15 | C | Far representations for the station's stand-in, the gate and the planets | T10, T14 | Opus | Hand-offs across three draw paths with no pop | not started |
| T16 | - | Integration, full suite, docs and acceptance | all | controller | One full run, the GPU check, the (H) list | not started |
| T17 | E | Test tiers: quick, standard, balance and full, the quick list, its guard test, the Rust tests in the run | T01 | Sonnet | Scripts and one data file from a written plan (`docs/research/test-review/quick-test-suite.md`) | done |
| T18 | E | The review's CONFIRMED test removals (sections A to D), each re-checked, the parity recordings still read | T17 | Opus | Proving two tests cover the same thing needs both read in full; rules on what must stay | in progress |

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
- **Done (2026-11-10; the maintainer read it the same day and accepted the anchor and Q8, answered Q4 to Q6 and Q2, and
  ruled out Doppler; the answers changed D65 to D67 as above):**
  - The audit is `docs/research/m6-moving-frame.md`: every file that reads `linear_velocity`, a row velocity or `origin`, with
    what a boost does to it; the absolute-velocity readers; the places assumed at rest; the single-frame globals; the numbers.
  - D64, D65, D67 and D71 are revised. Decided: the kick-then-drift integrator at the physics tick with a half-kick start; one
    gravity sample per tick, the frame's step last in the tick; the velocity rebase in `World`'s slot after the position
    rebase, with no interpolation reset; budgets of 0.05 m (AC1) and 0.5 m at 3 km (AC4) over one low orbit.
  - **Changed from the plan, for the maintainer to accept or refuse:** a `UniversePos` is relative to the World's anchor, and
    the frame rides the anchor instead of following the player; Q8 at 2 000 m/s instead of 200. If refused (the frame follows
    the player at 200 m/s), T05 also has to move every static row and anchor-tied node each tick and turn every stored
    `UniversePos` into an anchored place.
  - Drafts for Q4 to Q6 are under the planning questions.
  - For later tasks: T02 gives `kick` and `drift` and answers relative to a point; T04 adds the sample slot and the frame's
    step; T05 adds the core's `boost` and boosts `RamTracker`'s windows, the tier's `cruise` and the fallback at
    `tier_director.gd:414`; T08 threads the rest velocity through the flight step and the brains' feed.

### M6-T02 Ephemeris and gravity kernel

- **Goal:** AC3 (D65, D66's maths). Early start in new native files only.
- **Files:** `native/src/ephemeris.rs` (elements, Kepler's equation, the body tree), `native/src/gravity.rs` (n-body sum, tidal
  residual, the integrator), their Rust tests, the binding (`native/src/ephemeris_rows.rs` or methods on `ScsSimCore`, wired in T04),
  `tests/unit/test_ephemeris.gd` once wired.
- **Notes:** elliptic orbits only (e < 1), solved by Newton's method with a fixed iteration rule so every run gives the same bits;
  64-bit throughout; the residual computed as an exact difference. The pull over rows is a pure function over a frozen list of
  body positions, so it runs in the worker job or on the main thread with the same result. Test values from closed-form orbits.
  The pull follows D66 (the strongest body in whose zone a point lies, `a_min` a parameter, the fade at the edge); a point can
  be placed on another orbit at a phase offset (the gate on the station's orbit, Q3).
- **Tests:** the Rust tests and `test_ephemeris.gd`: quick.
- **Done when:** AC3 in Rust; the kernel holds no engine type (the guard test).

- **Done (2026-11-10, `72b3150`):**
  - `native/src/ephemeris.rs`: Kepler elements (e up to 0.99) solved by Newton with a fixed 24 steps, a body tree evaluated
    directly at any time (`state`, `relative_state` against a body, no carried state), `add_on_orbit` for a point sharing an
    orbit at a phase offset (the gate on the station's orbit), and `sample` for the frozen lists the gravity kernel reads.
  - `native/src/gravity.rs`: D66's rule (`pull_at`, `dominant`, `residual` and `residual_rows`: the strongest body whose zone
    holds the point, zones from `zone_radius` with `A_MIN_DEFAULT` 0.5 m/s^2, eased to nothing over the outer fifth); the full
    n-body sum and `tidal` kept beside it; `kick`, `drift`, `step` and `half_kick_back` for the integrator.
  - 27 new Rust tests (63 in all, `cargo test --release --lib`) and `test_the_ephemeris_kernel_holds_no_engine_type` in
    `test_sim_core.gd`: both quick tier. Not bound to GDScript yet: T04 adds the binding and `test_ephemeris.gd`.

### M6-T03 Star system data

- **Goal:** the data half of AC6.
- **Files:** `data/star_systems.json` (bodies with parent, mass or `gm`, radius, atmosphere top, elements, epoch of elements, and
  places such as the station's point and the gate's), `src/world/star_system.gd` (`RefCounted`: load, validate, hand to the core),
  `tests/unit/test_star_system.gd`, provider `system` (bodies and their positions now), `info.md`.
- **Tests:** `test_star_system.gd`: quick.
- **Done when:** the file holds Q1 to Q3's answers, validated with reasons; the core gets the bodies from it.

- **Done (2026-11-10, `95bf34f`):**
  - `data/star_systems.json` holds Q1 to Q3 beside `StarCatalog`'s fields: `a_min`, `bodies` (Epsilon III, no moon: `gm`
    1.68e14, radius 4 780 km, atmosphere top 100 km, a 0.6 AU circular orbit) and `places` (Babylon 5 on a 27 500 km circular
    orbit; the gate on the same orbit, 50 km ahead as a phase offset). Metres, seconds, degrees; `gm` is authoritative.
  - `StarSystem` (`RefCounted`) validates with a reason for every refusal and builds `ScsEphemeris`
    (`native/src/ephemeris_binding.rs`: 64-bit `state` and `relative_state`, `zone_radius`, `dominant`; kernel axes, mapped
    to the game's by T04). `ScsEphemeris` is in `NativeLib.REQUIRED`. Provider `system` from `StarSystemHost`, in `info.md`.
  - Tests: `test_star_system.gd` (quick) and 3 Rust binding tests (quick). By design (D66), the station and gate sit outside
    Epsilon III's zone (18 300 km at `a_min` 0.5), so nothing pulls there; T07 and T08 test gravity on a low fixture orbit.

### M6-T04 The free-falling frame

- **Goal:** the frame half of AC1.
- **Files:** `src/world/world_frame.gd` (origin and `origin_velocity` propagated each tick; `environment_accel` from the core),
  `src/ship/ship.gd` and the flight batch (the residual into `env_accel`), the core's binding, `tests/integration/test_free_fall.gd`.
- **Notes:** `environment_field` stays the seam; the callable now calls the core. The frame is propagated in the slot T01 chose.
- **Tests:** `test_free_fall.gd`: quick for a short arc and the ship at rest; the one-orbit check is standard.
- **Done when:** an empty frame follows the analytic orbit within the budget; a ship at rest in the frame stays at rest to within
  the residual; the parity recordings are green with gravity off.

### M6-T05 The velocity rebase

- **Goal:** the rebase half of AC1 (D64).
- **Files:** every file in T01's audit table that needs a change; `tests/fixtures/rebase_fight.gd` (both rebases forced),
  `tests/integration/test_velocity_rebase.gd`; the native rows' `shift` grows a velocity part.
- **Notes:** universe position and universe velocity of every object unchanged across a rebase (the test sums them before and
  after). The interpolation rule is the position rebase's: reset at the end of the tick. Particles stay in their node's frame.
  Measure the rebase's cost at `bench battle 1000`.
- **Tests:** `test_velocity_rebase.gd` (the sums before and after): quick; `RebaseFight` with both rebases forced and the
  recorded dogfight: standard.
- **Done when:** AC1; a dogfight across many velocity rebases shows no jump in a recorded run (the test compares drawn positions).

### M6-T06 L4: the rebase cascade

- **Goal:** AC2.
- **Files:** `src/world/static_rows.gd`, `src/perf/sim_core.gd`, the resolvers' cached solids, `src/world/world_frame.gd`, the
  native statics' shift.
- **Tests:** the existing rebase tests keep their tiers; the cost is a bench number, not a test.
- **Done when:** AC2, numbers before and after in the Done notes.

### M6-T07 Gravity on everything

- **Goal:** AC4 apart from the HUD (D66).
- **Files:** `native/src/flight_step.rs` (input only), `native/src/tier.rs` and `tier_rows.rs` (bodies for point sources),
  `native/src/bolt_kernels.rs` (the pull before the move), the debris path T07 measures, the brake's and the AI's feed-forward,
  `src/perf/standins/gravity_standin.gd` removed with its install path and the bench layout moved to data, tests in Rust and GUT.
- **Tests:** the Rust tests and the zero-gravity parity checks: quick; the parked ship over one orbit and the curved bolt:
  standard.
- **Done when:** AC4; bit-identical results at zero gravity; AC10's cost measured.

### M6-T08 Flying under gravity

- **Goal:** AC5 (D67).
- **Files:** `src/ship/speed_governor.gd`, `src/ship/ship.gd`, the assist's and the brake's inputs, `src/world/reference_frame.gd`
  (pure), the HUD's reference and altitude (`hud_input.gd`, `hud_frame.gd`, `hud_painter.gd`), the planet-impact rule, settings for
  anything new, tests (a headless low orbit held with assist on; the brake's stop against the reference).
- **Tests:** `ReferenceFrame` and the brake's stop against the reference: quick; the headless low orbit held with assist on:
  standard.
- **Done when:** AC5.

### M6-T09 Scenarios at true scale

- **Goal:** the scenario half of AC6.
- **Files:** `ScenarioLoader` (spawns relative to a body, a station point or an orbit; `epoch`), `data/scenarios/*.json`, the
  missions' data where they name positions, `Main`'s start, the encounter director's spawn shell (it spawns relative to the
  player's reference), tests for each spawn form.
- **Notes:** the Civilian escort's belt and beacons keep their layout, moved as a whole to the station's orbit; every mission's
  headless tests run unchanged in outcome.
- **Tests:** each spawn form in the loader: quick; the missions' headless runs keep their tiers.
- **Done when:** AC6; free flight starts beside the station's stand-in with the planet in view.

### M6-T10 Scaled-space layer

- **Goal:** the placement half of AC7 (D68).
- **Files:** `src/environment/scaled_space.gd` (the layer and its camera), `src/environment/scaled_placement.gd` (pure: direction,
  distance, angular size), `src/environment/space_environment.gd` (the key light's direction from the sun), its tests.
- **Notes:** the design question is how the layer's depth and the near world's coexist in Forward+ (a separate viewport, a second
  camera pass, or reversed depth with a clamp) and what each costs; decide by measuring on the maintainer's GPU. The planet's shadow
  on the near world is a key-light factor from the ephemeris (sun, planet and camera), not a shadow map.
- **Tests:** `scaled_placement` tests: quick; GPU files (`*_gpu.gd`): standard (Pending headless).
- **Done when:** the placement tests; a placeholder sphere for the planet and the sun draws at the right size from anywhere and
  after any rebase; GPU numbers recorded.

### M6-T11 The planet and its atmosphere

- **Goal:** the planet half of AC7.
- **Files:** `tools/procgen/assets/planet.py` (albedo, height or normal, clouds, night side if the references show one; early
  start), its Python tests, the planet's material and the atmosphere shader on T10's layer.
- **Tests:** the generator's Python tests: standard (a whole-asset build), with any pure helper test under 5 s in the quick
  Python list.
- **Done when:** AC7's planet; a look sheet (day, terminator, night, limb from orbit and from 1 000 km) in
  `references/screenshots/M6-T11 planet/` for the maintainer (H).

- **Generator half done (2026-11-11, `ba6da40`; the row stays `in progress` until the shader half on T10's layer):**
  - `tools/procgen/assets/planet.py`: `PlanetSpec` parameter sets, `epsilon_iii` registered (`python3 -m tools.procgen build
    epsilon_iii`, about 40 s). Equirectangular maps from noise sampled on the sphere (seamless, exact pole caps): albedo,
    height and normal at 4096x2048, the wisp mask at 2048x1024, 25.7 MB. Warm palette from the reference, no ocean or city
    lights; the manifest records the layout, height range, relief gain and haze tint.
  - Tests: `test_planet.py` (standard, 52 s, 11 tests: contract, seam, poles, palette, relief, determinism) and
    `test_planet_helpers.py` (quick, about 1 s).
  - Look sheet `references/screenshots/M6-T11 planet/epsilon_iii_preview.png` (H): close in colour and relief, a little
    pinker with larger cream patches than the still.
  - Left for the shader half: the terminator from the true sun direction, no relief lit on the night side, the faint warm
    limb on the lit side only, sunlit wisps, mipmapped sampling. `docs/architecture.md` §9 still needs a `planet` entry.

### M6-T12 The sun

- **Goal:** the sun half of AC7.
- **Files:** the sun's disc and glow on T10's layer, `src/rendering/lens_flare_aim.gd` and the flare's source on the true
  direction, the star's colour from `data/star_systems.json`.
- **Tests:** pure direction and colour tests: quick; GPU files: standard.
- **Done when:** AC7's sun and light; a look sheet for the maintainer (H).

### M6-T13 Jumpgate references and generator

- **Goal:** the generator half of AC8. Early start once Q11 has references.
- **Files:** `docs/design-references.md` (a jumpgate section: shape, proportions, colours from the references, sources listed),
  `tools/procgen/assets/jumpgate.py`, its tests and registry entry.
- **Tests:** as T11: the whole-asset build standard, pure helpers quick.
- **Done when:** the output contract and Python tests; a look sheet for the maintainer (H).

- **Done (2026-11-11, `bb539f4`):**
  - `docs/design-references.md` "Jumpgate (M6)": four separate arms 90 degrees apart (proportions read off the maintainer's
    STL, which holds the arms as print pieces: spine in four longerons, five fin stations, V-tilted hexagonal fins, cross
    caps), colours and lamps from the wiki's stills, the vortex's look and timing from the reference video's frames, sources
    listed. No on-screen size exists; chosen: 1 200 m arms, a 1 440 m vortex, 4 km tip to tip (`arm_length_m`).
  - `tools/procgen/assets/jumpgate.py` (about 44 s): 15 840 triangles (LODs by the importer), 2 048 px maps, 44 collision
    boxes; `hardpoints.json` and the manifest carry the vortex (centre at the origin, normal -Z, radius 720 m, blue arrival
    and orange/yellow departure colours), arrival and departure points, four tip emitters and 40 amber lamps.
  - Tests: `test_jumpgate.py` (standard, 106 s) and `test_jumpgate_helpers.py` (quick, about 1 s).
  - Look sheet `references/screenshots/M6-T13 jumpgate/look/look_sheet.png` (H). Open for the maintainer: which way the fins'
    V opens, amber or white lamps, whether 1.2 m per texel is soft at 100 m.

### M6-T14 The jumpgate in the game

- **Goal:** AC8 (D69).
- **Files:** `src/props/jumpgate.gd`, the vortex (`src/props/jump_vortex.gd`, its shader and mesh), the broadcast, arrivals through
  the gate for missions and encounters (data), `JumpArrival` kept for open points (Q12), the `gate` provider and commands, tests.
- **Tests:** the vortex's timing and the broadcast range: quick; a ship arriving through the gate headless: standard.
- **The player's jump (maintainer, 2026-11-11):** lock on to the gate as to a nav beacon. Within about 10 km, with the gate
  targeted, the HUD shows a prompt `X: request jump`; X does this **only** then (it stays auto-track everywhere else). Pressing
  it starts a sequence: the controls lock, an autopilot lines the ship up with the gate's departure point and accelerates, the
  orange/yellow vortex opens on the show's timing, a cinematic camera (`CinematicShot`) follows the ship in, and a flash and a
  fade end it. In M6 the ship then **comes back through the same gate's blue arrival vortex** and the controls return
  (hyperspace itself is M11, which replaces the round trip). AI ships and encounter raiders arrive (blue) and leave
  (orange/yellow) through the gate when the data asks for it.
- **Order (maintainer, 2026-11-11):** T14 runs before T09: the gate is placed in today's scenes beside the station's stand-in,
  50 km away as `data/star_systems.json` says, at rest; T09 later moves it with the rest of the scene to true scale.
- **Done when:** AC8.

### M6-T15 Far representations

- **Goal:** AC9 (D70).
- **Files:** `src/rendering/lod_switcher.gd` and `far_dots.gd` for the large props, the scaled-space impostors from T10, the
  station's stand-in, the gate and the planets.
- **Tests:** the drawn size across each hand-off: quick if pure, else standard.
- **Done when:** AC9.

### M6-T16 Integration, full suite, docs and acceptance

- **Goal:** AC10, AC11 and the (H) checklist for AC12.
- **Steps:** §19 in `docs/architecture.md` as built (and §14.1, §14.2 updated); the M6 section of `docs/playtest.md` with the (H)
  checklist; the roadmap row; the full tier once (T17's runner), read from the suite's own totals; the GPU check on the maintainer's
  machine; then ask the maintainer to confirm the milestone, and once confirmed merge `m6` into `main`.
- **Done when:** the maintainer confirms M6.

### M6-T17 Test tiers: quick, standard, balance and full

- **Goal:** a few-minute check for iteration, a merge gate that skips the balance fights, and a full run that includes them
  (2026-11-10, maintainer: four tiers instead of the review's two).
- **Steps:** follow `docs/research/test-review/quick-test-suite.md` for the quick tier (its GUT and Python lists, the compile
  check, `cargo test`, the two console smokes, the guard test), with these changes:
  - One entry point: `scripts/run_tests.sh --quick | --standard | --balance | --full`, default `--standard`, so
    `scripts/run_tests.sh` alone stays the gate CLAUDE.md names. Shared helpers in a sourced `scripts/lib_tests.sh`.
  - Standard is what `run_tests.sh` checks today, plus `cargo test --release --lib` (the review's H1: no run calls it), minus
    the balance tests.
  - Balance: a `BalanceTests` gate like `SlowTests` (`GUT_BALANCE=1`), on the tests that judge balance: `test_dogfight`'s
    six-minute fight and `test_m3_sandbox`'s three waves (both end Pending today, review F4), and `test_turret_balance` and any
    other file whose verdict is a balance judgement. The other tests in those files stay standard. `--balance` runs only these.
  - Full: standard plus balance.
- **Files:** `scripts/run_tests.sh`, `scripts/lib_tests.sh`, `tests/quick_suite.txt`, the balance gate beside `SlowTests` and
  its users, `tests/unit/test_quick_suite.gd` (also checks no listed file is a balance file), `CLAUDE.md`'s Commands block,
  `docs/architecture.md`'s tests section, `docs/research/test-review/quick-test-suite.md` (as built).
- **Tests:** `test_quick_suite.gd` and the balance gate's own test: quick.
- **Done when:** `--quick` exits 0 and prints its time (about 3.5 min); a broken listed test and a broken parse each stop it;
  `--balance` runs only the balance tests; `--standard` runs everything it ran before except those, plus the Rust tests, and
  exits 0 (its time in the Done notes); CI keeps running the standard tier.
- **Done (2026-11-10):**
  - `scripts/run_tests.sh --quick | --standard | --balance | --full` (default standard, unknown flag exits 2), helpers in
    `scripts/lib_tests.sh`. Standard is what it ran before plus `cargo test --release --lib` (66 Rust tests; shard 1 in CI), with
    `GUT_BALANCE=0`; CI still calls it with no flag, so it runs the standard tier. Full is standard with `GUT_BALANCE=1`; balance
    runs only the files of `tests/balance_suite.txt` with `GUT_SLOW=1 GUT_BALANCE=1`.
  - `BalanceTests` (`tests/fixtures/balance_tests.gd`, `GUT_BALANCE=1`) with `tests/unit/test_balance_tests.gd`. Gated:
    `test_dogfight`'s six-minute test and `test_m3_sandbox`'s three-waves test (each skips up front; the rest of their files
    stays standard) and the whole of `test_turret_balance` (moved from `GUT_SLOW` to `GUT_BALANCE`). No other test judges
    balance (`test_tier_outcomes` and `test_rebase_in_play` compare tiers and rebases, not balance).
  - `tests/quick_suite.txt` (103 files: the plan's list, minus none, plus `test_balance_tests`, `test_quick_suite` and T03's
    `test_star_system`), `tests/quick_python.txt` (20 modules), `tests/unit/test_quick_suite.gd`. Every file in the plan still
    existed on `m6`; none used SlowTests or BalanceTests.
  - Times (maintainer's machine): quick 208 to 300 s (1,588 GUT tests; the Rust tests ran 66 passed); balance 1,152 s (9 tests,
    turret balance passes, the dogfight and sandbox end Pending as before); standard 6,633 s (110 min), exit 0, 3,322 tests,
    13 pending (including the two skipped balance tests). Full was not run separately (standard and balance both pass).
  - A broken assert in `test_fuel_tank` fails `--quick` naming it; a parse error in it stops the compile check. Both reverted.
  - Quick does no `--import`: after a task adds a `class_name` the compile check fails until one `godot --headless --import`.

### M6-T18 The review's CONFIRMED test removals

- **Goal:** cut duplicated run time without losing coverage (`docs/research/test-review/removal-candidates.md`).
- **Steps:** sections A to D only, each re-checked as the file's "How to verify an entry" says (the branch has moved since
  `5c65d81`); A8's shared seeded-battle fixture first so A1 to A7 are safe. C5 (`StarPointMath`) stays as a design oracle unless
  the maintainer says otherwise; C7 (dead `PlaceholderScreen`) is reported, not deleted. Sections E, F and G wait for the
  maintainer. Then update `tests/quick_suite.txt` as the quick suite's "Interplay" section says.
- **Rules:** the file's five (every parity recording still read, the damping guard, the engine-free guards, one 1-vs-6 and one
  threaded-vs-delayed test per threaded subsystem).
- **Tests:** a removal keeps the kept test's tier; a moved assert takes the tier of the file it lands in.
- **Done when:** each entry is removed, merged or kept with the reason in the Done notes; the standard tier exits 0 and its time
  before and after is recorded.
