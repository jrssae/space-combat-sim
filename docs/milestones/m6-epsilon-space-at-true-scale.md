# Milestone 6: Epsilon Space at True Scale

> "The real neighbourhood." (`docs/roadmap.md`)

**Status:** planned 2026-11-10, ahead of time; **not started.** M5 is the current milestone until the maintainer accepts it.
**2026-11-10 (maintainer):** branch `m6` was cut from `m5` at `5d81686`, with `main`'s M6 and M7 plans merged in, so the early
start (below) runs on it; `m6` takes M5's later work by merging `m5` into it (merges, no rebase, as M5's Q27). The rest of M6 waits
as the early-start section says. T01 is `in progress` (its audit and decisions are written and wait for the maintainer to
read them); every other task is `not started`. The planning questions (Q1 to Q12) are open: the proposed answers below are the
planner's defaults, and each task that depends on one waits for the maintainer's answer. This plan was written against `m5` at
`5d81686`, so it names M5 files (§18, M5-T21, `JumpArrival`) that reach `main` when M5 merges.
**2026-11-12 (maintainer):** `main` (M5 through T48, merged there as work in progress) was merged into `m6` (`c3b8abd`), and M6
goes on from T04 in the planned order, one task at a time, while M5's play-test is pending. T19 stays paused at the maintainer's
word. Q7 and Q9 are answered (the planner's defaults).

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
| Q7 | Where free flight and the sandbox scenarios start | Beside the station's stand-in in its orbit (Q2), with the planet in view; the old origin-at-rest scenarios keep their layout around that point | **As proposed** (maintainer, 2026-11-12) |
| Q8 | The velocity rebase threshold | 200 m/s relative to the frame (architecture §14.1), with the same end-of-tick interpolation rule as the position rebase | **2 000 m/s**, the frame riding its anchor below it (T01's D64, accepted by the maintainer, 2026-11-10) |
| Q9 | The start epoch (the planet's phase, day or night under the station) | Each scenario sets an epoch; free flight seeds one per run, as it seeds its encounters | **As proposed** (maintainer, 2026-11-12) |
| Q10 | References for Epsilon III and the sun's look | The maintainer's references (`docs/design-references.md`; per the standing rule, colours and textures from show images); without them, a rocky planet with thin clouds and a blue limb | **Epsilon III: one show still** (`references/Epsilon III planet.png`, not committed), described in `docs/design-references.md` ("Epsilon III"): a dry rust-and-tan rocky world with strong relief, no oceans, faint wisps at most, a hard terminator and a faint warm limb, not a blue one. The sun's look is still open (maintainer, 2026-11-10) |
| Q11 | References for the jumpgate and its vortex | The maintainer's references; the jumpgate gets a section in `docs/design-references.md` before its generator starts (T13) | **The gate's shape and proportions read off the maintainer's model `references/EA_Jump_Gate.stl`** (nothing copied: geometry generated by code); colours and the vortex's look from show stills found online, described in our own words (no image committed) (maintainer, 2026-11-11) |
| Q12 | M5's `JumpArrival` (a flash where raiders appear) | It stays for open jump points far from the gate; ships that use the gate come through the vortex (T14) | **Revised (maintainer, 2026-11-11): the same vortex everywhere.** Ships that open their own jump points (capital ships, raider arrivals at open points) show the gate's vortex; one stand-alone vortex replaces `JumpArrival`'s flash (T19) |

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
  **As built (T05):** the World's slot only decides the velocity rebase; it is taken in the frame's last slot, just before
  the frame's step, so the movers that step themselves and the bodies change frames in the same step (T05's Done notes).
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
| AC2 | Rebase cost (L4): the statics shift natively and in place, hidden ships are skipped; the worst rebase tick at `bench battle 1000` is within 10 % of the median tick (Report P3: 13.07 against 10.50 ms), measured before and after. **Restated (maintainer, 2026-11-12, after T06):** the cascade's rebuilds are gone and the median rebase tick's extra cost over the median tick is measured before and after (T06: 2.25 to 1.77 ms; the 10 % bar sits inside the tick's own spread, p90 +14 %); the per-node rest is T21 | A | T06 |
| AC3 | Ephemeris and gravity: Kepler positions and velocities match reference values for circular, elliptic and inclined orbits; a moon's orbit is around its planet; the ephemeris seeks to any time with no carried state; gravity on rows is identical with 1 and 6 threads and between `sim_step` threaded and `delayed`; Rust unit tests and GUT tests through the binding | A | |
| AC4 | Everything falls: a ship coasting in orbit beside the station's stand-in stays beside it over one orbit (within T01's budget); a bolt fired near the planet curves as the analytic path says; debris and the tier's rows feel the pull; the brake holds a point under gravity; `GravityStandin` is gone and the bench's `battle` layout runs with its pull from data | A | |
| AC5 | Flying under gravity: the clamp follows Q4; the assist's safe speed and the brake's all stop read against the reference (Q5); with assist on, the player can hold a low orbit; the HUD shows `REF <name>`, range, closing speed, the speed against the reference and the altitude near a body (Q6); hitting the planet or a moon destroys the ship | A | |
| AC6 | System data and scenarios: `data/star_systems.json` holds the bodies of Q1 with their elements, validated on load with the reason given; scenarios spawn relative to a body, a station or an orbit and set an epoch (Q7, Q9); every existing scenario and mission still loads and runs its headless tests | A | |
| AC7 | Scaled space: the star and Epsilon III are drawn at their true angular size and direction from anywhere in the local space and after any rebase (test on the computed placement); the key light and the lens flare follow the true sun direction; the planet's shadow dims the key light; on the maintainer's GPU `renderer = forward_plus`, FPS, draw calls and VRAM recorded with the planet in view | A | |
| AC8 | Jumpgate: the generator meets the output contract with its Python tests; the gate broadcasts to 1 000 km (test); a ship sent through it in a headless run arrives through the vortex; the vortex opens and closes from sim time; GPU numbers recorded with the vortex open | A | |
| AC9 | Far representations: the station's stand-in, the gate and the planet are drawn at every distance from 100 m to their broadcast range with no pop at a hand-off (test on drawn size); the cost at 1 000 km recorded | A | |
| AC10 | Cost: gravity and the moving frame add no more than 5 % to the `bench battle 1000` tick (measured before and after on an idle machine); the paired 13-ship AI budget (`test_ai_think_time`) still passes | A | |
| AC11 | Docs and the suite: `docs/architecture.md` §19 as built (and §14.1, §14.2 brought up to date), a `docs/playtest.md` M6 section, the roadmap row, `info.md`; `scripts/run_tests.sh` green once, at the end | A | |
| AC13 | Mass arrivals (T20): the vortex drops detail layers with distance (its screen size), with no pop between levels; in `bench battle 1000` every ship enters through a jump point, up to 100 points forming at once; the battle's GPU run on the maintainer's machine records fps, GPU frame time, draw calls and VRAM with 100 points forming, against the same battle with ships placed directly | A | |
| AC12 | (H) The maintainer flies it: an orbit beside the station's stand-in, the planet and the sun from orbit and from 1 000 km, the atmosphere's limb and terminator, the jumpgate and its vortex, the assist and brake under gravity, a dogfight across several velocity rebases with nothing seen to jump | H | |

## Working rules for M6

- **Tracks.** A (frame and gravity: T01, T02, T04 to T08), B (system data and scenarios: T03, T09), C (scaled space and far
  representations: T10, T11, T12, T15), D (the jumpgate: T13, T14), E (test tiers: T17, T18). Inside a track the order holds.
  If work goes one task at a time, the order is T01, T17, T18, T02, T03, T04, T05, T06, T07, T08, T09, T10, T11, T12, T13, T14,
  T15, T19, T20, T21, T16. T19's pause was lifted by the maintainer on 2026-11-12 (evening); the maintainer accepted T19 after
  round 6 and the closing flash (2026-11-12, night).
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
- After each task: its row says `done` with its Done notes, in the same commit, and `m6` is pushed once the task's focused runs
  are green; CI's run is checked after each push (maintainer, 2026-11-12, replacing the 2026-11-10 "do not push" rule).

## Task breakdown (ordered)

| Task | Track | Title | Depends on | Agent | Why | Status |
|---|---|---|---|---|---|---|
| T01 | A | Moving-frame audit and design: every World-frame velocity, the rebase order, the error budgets, §19's draft (early start) | - | Fable | Cross-cutting invariants over GDScript, Jolt and the native rows; mistakes surface late | done |
| T02 | A | Ephemeris and gravity kernel: Kepler rails, the body tree, the strongest body's pull and the tidal residual, the integrator (early start, new native files) | T01 | Fable | Precise, deterministic numerics that M9 and M11 reuse | done |
| T03 | B | Star system data: bodies and elements in `data/star_systems.json`, the loader, the `system` provider | T02, Q1 to Q3 | Sonnet | Data and validation on a clear format | done |
| T04 | A | The free-falling frame: the origin as a test particle, `environment_accel` from the ephemeris | T02, T03 | Opus | Touches the tick order and every ship's force step | done |
| T05 | A | The velocity rebase over every body, row, bolt, chunk, particle and interpolated node | T04 | Fable | The riskiest change of the milestone; every moving thing and the parity recordings | done |
| T06 | A | L4: the rebase cascade natively, the cached solid shifted in place, hidden ships skipped | T05 | Opus | A measured native fix on the path T05 rewrote | done (AC2 restated, the per-node rest moved to T21; maintainer, 2026-11-12) |
| T07 | A | Gravity on everything: ships, tier rows, bolts, debris, the brake's and the AI's feed-forward; the gravity stand-in removed | T04 | Opus | Native kernels with parity at zero gravity | done |
| T08 | A | Flying under gravity: the clamp, the assist's and brake's reference, the HUD's reference and altitude, planet impact | T07, Q4 to Q6 | Opus | Flight-model semantics the player feels | done |
| T09 | B | Scenarios at true scale: spawns relative to bodies, stations and orbits, epochs, free flight beside the station's stand-in | T03, T08, Q7, Q9 | Opus | Every scenario and mission must keep working | done |
| T10 | C | Scaled-space layer: placement, draw order and depth, the true sun direction, the planet's shadow | T04 | Fable | Precision and draw order in Forward+ at planetary distances; a design that later layers stand on | done |
| T11 | C | The planet and its atmosphere: the `planet` generator and the scattering shader (generator half early) | T10, Q10 | Opus | Shader maths on T10's layer; the look is (H) | done |
| T12 | C | The sun: disc and glow from the star's colour, the lens flare and key light on the true direction | T10 | Sonnet | A small shader and the existing flare | done |
| T13 | D | Jumpgate references and the `jumpgate` generator (early start) | Q11 | Opus | Geometry read off references | done |
| T14 | D | The jumpgate in the game: the prop, the vortex, 1 000 km broadcast, arrivals through the gate | T13, T09, Q12 | Opus | A new effect and the mission and encounter seams | done |
| T15 | C | Far representations for the station's stand-in, the gate and the planets | T10, T14 | Opus | Hand-offs across three draw paths with no pop | done |
| T16 | - | Integration, full suite, docs and acceptance | all | controller | One full run, the GPU check, the (H) list | in progress (docs drafted beside T20) |
| T17 | E | Test tiers: quick, standard, balance and full, the quick list, its guard test, the Rust tests in the run | T01 | Sonnet | Scripts and one data file from a written plan (`docs/research/test-review/quick-test-suite.md`) | done |
| T18 | E | The review's CONFIRMED test removals (sections A to D), each re-checked, the parity recordings still read | T17 | Opus | Proving two tests cover the same thing needs both read in full; rules on what must stay | done |
| T19 | D | The vortex reworked and stand-alone: fitted to the gate, a shallow funnel, spiralling soft dark patches; open jump points use it too | T14 | Opus | Shader animation and a shared effect seam; the look is (H) | done (accepted by the maintainer, 2026-11-12) |
| T20 | D | Vortex detail by distance and mass arrivals: detail layers dropped with screen size; up to 100 jump points forming at once; every ship of the 1 000-ship battle enters through one; the battle's GPU fps test with them | T19, T07 | Opus | A shader LOD, a pooled effect at a hundred instances and the battle's spawn path, judged on the GPU | in progress |
| T21 | A | The rebase's per-node rest: only the rocks near a ship live in Jolt; a list of the shiftables in play instead of walking the group | T06, T07 | Opus | A measured engine-side follow-up to T06 on the paths T07 also changes | done |

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

- **Done (2026-11-12):**
  - `native/src/frame.rs` (engine-free, 64-bit, kernel axes): `Frame` holds a copy of the star system, the anchor (`Rail` on a
    place's orbit, or `Particle`, a test particle held against its home body's centre, started half a kick back), the local
    origin against the anchor and the tick's sample (bodies against the anchor, zones, the anchor's pull). `sample`, `residual`
    (D66's rule through `gravity::residual`), `step` (kick, then drift) and `anchor_state`. The frame is quiet (exactly zero
    residual, nothing read) when the anchor feels no pull and every zone stays more than 1 000 km (`QUIET_MARGIN_M`) from the
    local origin.
  - Its shell on the core, `native/src/frame_rows.rs` (`ScsSimCore.frame_*`): set the system from `ScsEphemeris`, anchor on a
    rail or in orbit, origin, sample, step, residual, pull, anchor state; the game's axes map to the kernel's as kernel
    (x, y, z) = game (x, -z, y). The flight step adds the residual natively to every ship it flies, gathered or row-flown,
    only while the frame is active, so the parity recordings keep their bits.
  - `WorldFrame`: `anchor_on_rail`, `anchor_in_orbit`, `clear_anchor`; two internal slots, the sample first in the tick
    (`SAMPLE_PRIORITY` -100, before the tier at -12) and the anchor's step last (`FRAME_STEP_PRIORITY`, after `sync_out`);
    `environment_accel` = `field_accel` (the World's own field, the battle's moon stand-in until T07) + `gravity_residual`.
    `Ship.batch_gather` packs only `field_accel`, the core adding the residual; a ship on its own model (the player's) reads the
    whole `environment_accel`. A rebase pushes the new origin to the core. `Main` anchors on `babylon5`'s rail when the
    system has it (`StarSystemHost.DEFAULT_ANCHOR`); that rail is outside Epsilon III's zone, so nothing pulls in play yet.
  - Console: `frame [status|orbit <altitude km> [body]|rail <place>|off]`; `world.anchor`, `anchor_state`, `gravity`,
    `anchor_pull`. In `info.md`.
  - Tests: Rust `frame::tests` (8: one low orbit within 0.05 m at every tick, an `e` 0.3 orbit ending within 0.1 m, the same
    round a planet that circles its star, the station rail quiet, the tidal residual on a rail inside a zone, the origin, the
    half-kick start, refusals) and the axes test; GUT `test_free_fall.gd` (quick, 7 tests, about 4 s): the short arc in the
    real tick, **the whole low orbit through the binding, worst 0.0053 m** (332 692 ticks in 0.7 s, so quick, not standard
    as planned), a ship at rest feels only the residual on the batch's path and on its own model (1 km out: twice the gradient,
    1 km along the track: once, toward the anchor; exactly zero at the anchor), no system and the station's rail pull nothing,
    a rebase keeps the residual at a universe point, the console command. `test_sim_core`'s new
    `test_the_frame_kernel_holds_no_engine_type`. Quick tier green; the parity recordings unchanged.
  - Left for later tasks: tier rows, bolts and debris feel nothing yet (T07); the velocity rebase (T05); the speed readers
    against a rest velocity (T08); the gate is placed by its scenario bearing, not on its rail (T09, T15).

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

- **Done (2026-11-12):**
  - **The rule off the anchor** (`native/src/frame.rs`). The frame holds its origin's velocity against the anchor in 64-bit
    (`origin_velocity`, zero while riding) and, per tick, the pull the origin itself takes: `origin_pull = g(origin) -
    g(anchor)`, fixed at the tick's sample (zero while riding or quiet). A mover feels `g(mover) - g(anchor) - origin_pull`,
    so off the anchor it is `g(mover) - g(origin)` and exactly zero at the local origin. The frame's step kicks the origin's
    velocity with `origin_pull` and drifts the origin, then steps the anchor. Origin plus mover has the acceleration
    `g(mover) - g(anchor)` whichever frame carries it. The tick's `origin_pull` holds through a position rebase and a boost.
    The way back takes `dv = -(origin_velocity + origin_pull dt)` and leaves the frame the one kick it still owes the
    tick's forces, so it is exactly at rest after that tick's step.
  - **A boost is taken at the end of the tick, not in the World's slot** (a change to D64's tick order, made for
    correctness). The rule (`WorldFrame._auto_boost`) runs at priority 0 after the position rebase and only asks; the frame's
    last slot takes it, then steps the frame. Bolts, debris and the tier step themselves inside the tick and the bodies in
    Jolt's step after it: a boost at priority 0 put the bolts into the new frame one step before the bodies, `dv dt` out of
    place (33 m at 2 000 m/s; found by the fight fixture). `boost(dv)` and `boost_to_anchor()` ask; `apply_boost` is the
    immediate form for the last slot and tests. In the same way `origin` and the anchor-tied things take the frame's step
    when the next tick starts (on `SceneTree.physics_frame`), with the bodies, so frames drawn between ticks stay consistent.
  - **Native:** `Rows.boost`, `Bolts.boost`, `TierRows.boost` (velocities, and a capital's `cruise`), `ScsSimCore.boost` and
    `boost_to_anchor` (both bump `rows_version`), `frame_origin`, `frame_origin_velocity`, `frame_riding`, `drift_anchored`
    (the tier's copy of the moon); `Tracker.boost` (the remembered velocities and each open window's `v_before`);
    `set_system` and `clear` keep the origin's place and velocity. A bolt row is drawn along its velocity against the
    anchor, so a boost turns no bolt in flight.
  - **GDScript:** `WorldFrame`: `boost`, `boost_to_anchor`, `apply_boost*`, `riding`, `rest_velocity()` (for T08's readers),
    `boost_sum` and `boost_since`, signals `boosted(dv)` and `drifted(shift)`, export `auto_boost_speed_mps` (0 = off) with
    the return under half of it. A shiftable node is a mover (a rigid body, or it has `frame_boost(dv)`: `Projectile`,
    `DebrisChunk`, `Explosion`, `CapitalStandin` with its cruise), tied to the anchor (group `world_anchored`: `NavBuoy`,
    `Jumpgate`, a stand-alone `JumpVortex`, `StationStandin` and its planet, `AsteroidBelt`, `AsteroidField`, the mines), or
    placed from other nodes every frame (cameras, far dots, voices). Listeners of `boosted`: `DebrisPool` (staged wrecks),
    `FxPool` (emitter velocities), `FarFlashes`, `RamResolver` (the tracker). Listeners of `drifted`: the belts' and the
    field's RID bodies, `GravityStandin`. The drift carries its float32 remainder in 64-bit, so a steady drift does not
    round the same way each tick. `TierDirector` keeps `boost_sum` per parked body and settles the boosts it sat out
    (the fallback with no row, and a capital's `cruise_velocity`). Pooled hidden ships are skipped.
  - Console: `boost <dvx> <dvy> <dvz>`, `ride`; `world.origin_velocity`, `riding`, `auto_boost_speed_mps`, `boosts`,
    `boost_us`. In `info.md`.
  - Tests. Rust (115 pass, 8 new): the frame off its anchor (a mover in a boosted frame and in a riding one agree to
    1e-5 m and 1e-6 m/s over 2 400 ticks in low orbit through two boosts and the way back; nothing felt at the origin;
    a straight line with no pull), rows, bolts, tier rows and cruise, two tracker tests. GUT `test_velocity_rebase.gd`
    (**quick**, 10 tests, 3.5 s): 27 movers through a forced boost (universe positions unchanged, velocities within
    6e-5 m/s, sums too), 30 ticks off the anchor (movers on their paths, buoy, rocks and their bodies with the anchor), no
    ram on a boost mid-contact (fails with 300 damage each without `Tracker.boost`), the automatic boost at 2 000 m/s and
    the return under 1 000, both rebases in one tick, the tier's parked bodies, gravity off the anchor through the binding,
    bolts and bodies changing frames together to 2 mm, the console. `RebaseFight` (fixture) grows `boost_every_s`: a
    150 m/s boost each half second, every third back onto the anchor; it compares universe positions and velocities late
    in the tick and drawn offsets from the drawn player every frame.
    `test_rebase_in_play.test_a_sandbox_fight_across_many_velocity_rebases_shows_no_jump` (**standard**, 23 s): 168
    boosts and 201 position rebases in a 90 s fight, 64 bolt hits, 4 kills, no failure over 41 878 tick checks and 52 574
    drawn checks. Quick tier: 1 754 of 1 756 pass; the two failures are T10's `scaled` command and provider not yet in
    `info.md` (not this task's files). `test_rebase_in_play` (9), `test_tier_handover` (13), `test_ai_guard` (2),
    `test_instructor_route` (4), `test_ram_damage` (14), `test_tier_proxies` (10) pass with `GUT_SLOW=1`. Parity
    recordings unchanged.
  - Performance, `bench battle 1000` (`scripts/bench_quick.sh`): tick median 5.53 ms, p99 7.79 ms after; 5.44 to 5.50 ms
    and 7.50 to 7.62 ms in the three reports of the same day before it (no boost in the bench, so no change). One boost
    with the battle in play: 0.45 to 0.64 ms (a position rebase there: 0.7 to 1.3 ms). **Off the anchor the tick costs about
    1.4 ms more** (7.65 against 6.30 ms in one process): every tick the static rows shift in GDScript, the 1 000 rocks'
    bodies are placed again and the resolvers' grids are rebuilt. That is L4's cascade, now per tick: T06.
  - **The automatic boost is off in `main.tscn`** (`auto_boost_speed_mps` 0). The readers still take a local speed as a
    speed against the anchor (T01's R list), so above 2 000 m/s the brake would stop the ship against the moving frame and
    the HUD would read 0. T08 changes the readers and sets the export to 2 000 in the same commit.
  - **Fix after CI (2026-11-12), `test_weapon_rows_battle.gd`:** CI's shard 1 failed the seeded battle's capital hits
    (384 against the recording's 446, 45 allowed). T05's code does not change that battle: T04's commit and T05's give the
    same hits alone ([885, 406, 159, 146, 28, 0] here). The battle has two samples by where it starts: between two ticks
    (406 here), or inside one (389 here), which is where GUT stands when the file before it ended on
    `await physics_frame`; the main scene is then set up one tick apart. CI's 403 before and 384 after fit the same two
    (not run there to confirm). T04's commit fails the same way after
    `test_free_fall.gd`. T05's new test file moved the shards' file lists, so another file ran before the battle. The
    test now waits for a `process_frame` first, so it always starts between ticks, whatever ran before. **Open:** both
    samples sit 9 to 14 % under the GDScript recording against 10 % allowed (403 in CI is 43 off, 45 allowed), so the test
    is close to its limit on any change that perturbs the battle; whether to look into the capitals' missing hits or
    re-base the tolerance is the maintainer's call. **Closed in T07:** the missing hits are the tier's (on by default
    since M4-T23, off when the battle was recorded); see T07's notes.
  - Left for T08 (readers, all in T01's R list): brake, assist, thrust fade and clamp, the HUD's speed, the brains' own
    speed, spawn velocities ("at rest" means `rest_velocity()`), a missile's held speed and heading (frame speed), rocks
    and props taken as at rest in the hit sweep, the ram rule and avoidance, a buoy marker's `velocity` for lead. Voices
    stay in the local frame (no Doppler, short lives). Left for T06: the per-tick static shift above.

### M6-T06 L4: the rebase cascade

- **Goal:** AC2.
- **Files:** `src/world/static_rows.gd`, `src/perf/sim_core.gd`, the resolvers' cached solids, `src/world/world_frame.gd`, the
  native statics' shift.
- **Tests:** the existing rebase tests keep their tiers; the cost is a bench number, not a test.
- **Done when:** AC2, numbers before and after in the Done notes.

- **Work notes (2026-11-12; AC2's bar not met, the maintainer's choice below):**
  - **A shift is not a new version.** `StaticRows.shift` moves one world's rows in one native call (`ScsStaticRows.shift`
    over `kernels::statics::shift_owned`, engine-free, the same 32-bit sum GDScript's `+=` made) and bumps `moves`, not
    `version` or `solid_version`. The cached `Solid` (now with a `worlds` column) shifts in place with it and counts its own
    `moves`; the hit and ram resolvers take the new places into their kept grids when it changes (a native `keep`, about
    45 us each). `scan_columns` is no longer built again. `SimCore` sends the core only the positions
    (`ScsSimCore.move_statics`: the static block's positions in place, no rebuild, taken by the rows at the next sync as
    `set_statics` was). Measured alone (1 000 rocks, 1 000 mines): shift 100 to 3 us, solid rows 295 to 8 us, scan columns
    128 to 0, the core's copy 104 to a few us.
  - **Hidden pool ships are skipped**: `ShipPool` marks a parked ship (`WorldFrame.PARKED_META`) and `acquire` clears it;
    the rebase walk skips it, as it skips the tier's, and tests both metas before `is_ancestor_of`.
  - **Tried and dropped:** placing the rock bodies natively. 1 000 `body_set_state` calls cost 284 us from Rust against 293 us
    from GDScript: the cost is Godot-Jolt's per body, not the loop.
  - `bench ... boost=<m/s>` (new option): boosts the frame off its anchor once the scene is placed, so the off-anchor tick is
    measured with the same relative motion as a riding run (T05's probe boosted before the spawn, so its ships flew through
    the rocks at the boost's speed and part of its 1.4 ms was more rams and contacts, not the drift).
  - **Numbers**, `bench battle 1000 20 warmup=3 seed=1` (headless, pinned 0-11, idle, before at `ed9935b5`):

    | run | tick median ms | p99 ms | rebase ticks: count, median, worst ms | shift ms |
    |---|---|---|---|---|
    | riding, before | 5.57 | 7.82 | 3, 7.97, 8.50 | 1.34 |
    | riding, after | 5.61 | 7.70 | 3, 7.32, 8.35 | 1.21 |
    | `rebase_m=60`, before | 5.56 | 7.74 | 8, 7.81, 8.28 | 1.33 |
    | `rebase_m=60`, after | 5.57 | 7.67 | 8, 7.34, 7.67 | 1.19 |
    | off the anchor (`boost=50`), before | 6.78 | 8.86 | | |
    | off the anchor (`boost=50`), after | 6.25 | 8.46 | | |

    The off-anchor extra drops from 1.21 to 0.64 ms a tick (hit +0.39 to +0.09, the core's sync +0.39 to 0; what is left: the
    1 000 rock bodies placed each tick, about 0.28 ms in Jolt, the two kept grids, the anchored nodes). The rebase tick's
    extra over the median drops from 2.25 to 1.77 ms (worst 8.28 to 7.67 ms, +38 % against +49 %). `bench_quick.sh
    m6_t06_after_quick battle` (500, 1 000): 4.42 and 5.61 ms median, p99 6.04 and 7.84, every budget held.
  - **Where the rebase tick still goes** (one probed run): the shiftable walk about 0.6 ms (1 128 group members listed, 489
    moved, rigid bodies teleported), the rock field's 1 000 bodies 0.25 ms, far dots 0.06 ms, the end-of-tick interpolation
    reset 0.27 ms, Jolt's next step +0.33 ms, the resolvers' kept grids +0.2 ms. All of it is per-node engine work, not the
    cascade. And the bar itself: the tick's own p90 is 6.37 ms (+14 %), so the worst of 3 to 8 rebase ticks lands over +10 %
    by noise alone, even at no cost.
  - **Maintainer's choice (AC2):** (a) accept AC2 as met by the cascade's removal and restate the bar on the rebase tick's
    median extra (now 1.77 ms; or against the tick's p95); (b) a follow-up task for the per-node part: stream the rocks'
    bodies (only those near a rigid hull live in Jolt, which also removes the off-anchor 0.28 ms), and keep a registry of the
    shiftables in play instead of walking the group with the tier's 580 parked ships in it; (c) both.
  - Tests: Rust 118 pass (new: the shift kernel's bits and owners, columns out of step, `Rows::take_positions`). GUT
    `test_static_shift.gd` (**quick**, 1 test, 2 s): a rebase and a drift over 200 rocks and 3 mines leave the version, the
    solid rows' object and the scan's columns as they were, and the contact scan's statics, the hit sweep's and the ram
    broad phase's rock pairs and the core's static rows equal a fresh build's (fails on the hit pairs and the core's rows
    when either re-take is removed). `test_bench` grows the `boost` option (standard). Quick tier 1 784 of 1 784;
    with `GUT_SLOW=1`: `test_world_frame` 18, `test_rebase_in_play` 9, `test_velocity_rebase` 10, `test_every_world_core` 6,
    `test_ship_pool` 21, `test_weapon_rows_battle` 1, `test_debris_pool` 12, `test_tier_handover` 13,
    `test_flight_parity_fight` 1, `test_parity_fixture` 3, `test_collision_layers` 15, `test_tier` 10, `test_ram_damage` 14,
    `test_rocks_and_mines` 9, `test_asteroid_belt` 4, `test_standins` 20, `test_sim_core` 21, `test_bench` 10 pass.

### M6-T07 Gravity on everything

- **Goal:** AC4 apart from the HUD (D66).
- **Files:** `native/src/flight_step.rs` (input only), `native/src/tier.rs` and `tier_rows.rs` (bodies for point sources),
  `native/src/bolt_kernels.rs` (the pull before the move), the debris path T07 measures, the brake's and the AI's feed-forward,
  `src/perf/standins/gravity_standin.gd` removed with its install path and the bench layout moved to data, tests in Rust and GUT.
- **Tests:** the Rust tests and the zero-gravity parity checks: quick; the parked ship over one orbit and the curved bolt:
  standard.
- **Done when:** AC4; bit-identical results at zero gravity; AC10's cost measured.

- **Work notes (2026-11-12; built and measured):**
  - **One sample, every mover.** Every mover reads the frame's residual from the tick's one sample (`frame.rs`), never a
    second copy of the maths, so nothing pulls outside a body's zone (the station's rail stays quiet) and only the strongest
    body pulls inside one. `Frame::residual_rows` (over `gravity::residual_rows_in_place`) gives a batch of movers the bits
    one `residual` per mover gives; its shell `frame_rows::residuals` converts the axes.
  - **Tier rows** (`tier.rs`, `tier_rows.rs`): `tier::step` takes the pull per row (the shell works it out for every row at
    once before the step) and adds it to the velocity every tick on top of the engines' held acceleration; the beat takes it
    only as the brake's and the cruise law's feed-forward (a fighter's held force is the flight kernel's less its environment
    force). A hulk now falls too, and a capital's engines hold its cruise against the pull while the pull acts on it (M4's
    tier and `CapitalStandin` had the engines' half only, so a capital was pushed off by the moon it never felt). With no
    pull the step is the old one, bit for bit. `tier::Gravity`, `tier_set_gravity`, `tier_gravity_at` and
    `ScsSimCore.drift_anchored` (it moved only the tier's copy of the moon) are gone.
  - **Bolts** (`bolt_kernels.rs`): the step is split into `expire` and `advance`; `advance` adds each owned bolt's pull times
    the 32-bit delta to its velocity before the move; empty where nothing pulls, which keeps the bits (the parity recordings
    stay green). A bolt launched this tick neither moves nor falls.
  - **Debris, wrecks, explosions, projectile nodes**: `HeldPull` (`src/world/held_pull.gd`), the pull read once a second of a
    mover's life and after a velocity rebase, added in the move each tick already makes. Measured over a chunk's 8 s life 3 km
    out on the low orbit: 0.0027 m off a per-tick read, with a 0.25 m bend; one read costs 0.36 us from GDScript (172 us for
    479 reads against 309 us for the chunk's own 479 ticks), so the held pull is the cheaper path and well inside AC4's 0.5 m.
    Staged wrecks (through `DebrisPool.advance_wrecks`), the explosion's fireball and `Projectile` (missiles, beams' bolts and
    a cannon with no core) take it the same way.
  - **Brake and AI feed-forward:** the flight step's residual is the env acceleration for gathered and row-flown ships alike
    (the brake's `env_b`); the AI holds a point with the brake (idle hold, a route's hold), so it gets it there; the tier's
    beat passes it to the flight kernel too. Measured: a braking ship 3 km out holds its point within 5 cm over 10 s on the
    batch's path and on its own model, where a coasting one is carried 0.39 m.
  - **`GravityStandin` is gone**, with `StandinDirector.add_gravity` / `remove_gravity` / `gravity`, the tier director's push,
    and the World's own field (`WorldFrame.environment_field`, `field_accel`): nothing else needed the seam, so
    `environment_accel` is the residual alone and `Ship.batch_gather` packs zero. The station scene's 12 km planet stand-in
    pulls nothing now (smaller than a moon). **The bench's `battle` and `typical` layouts** fly in a 400 km circular orbit of
    Epsilon III, a body of the star system's data (`BenchLayout.gravity_orbit`): the runner anchors the frame on that orbit
    through the battle's centre and puts the anchor back after (`_restore_frame`). Every mover feels the tide (about 0.026
    m/s^2 10 km out). `CapitalStandin.step_engines` adds the pull to the body beside the engines' force.
  - Console: provider fields `core.gravity_rows` (ships, tier rows, bolts the pull reached last tick) and `core.gravity_us`
    (the tier's and the bolts' batches), from `ScsSimCore.gravity_readouts`. In `info.md`.
  - **Tests.** Rust 126 pass (8 new: bolts' `advance` keeps the old bits with no pull, the kick before the move and a 10 s
    drop against `g t (t + dt) / 2`, no fall on the launch tick, expiry first; the tier with no pull and with a pull of zeros
    bit for bit, every row falling and a capital holding its cruise; `Frame::residual_rows` equal to one `residual` per mover
    bit for bit in 1 and 6 parts, and zeros with no anchor and on the station's rail). GUT, **quick**:
    `test_gravity_movers.gd` (new, 5 tests, under a second: a core bolt's kick and move bit for bit, the station rail's bolt
    unchanged, the chunk against a per-tick read, a wreck, an explosion and a projectile node, the brake on both paths),
    `test_tier.gd` (the rows and a capital under the low orbit's pull, nothing on the station's rail, a rebase), the
    `test_sim_core` guards (the tier's tests moved to `native/src/tier/tests.rs`). **Standard**: `test_gravity_orbit.gd` (new,
    3 tests): a parked (tier) ship along the track over **one whole orbit** (332 692 ticks by hand, about a second): worst
    0.081 m at 1 km and 0.052 m at 3 km against a 64-bit run of the same start; the same start flown **in Jolt** by the
    flight batch over the whole orbit with the slow files on (the real tick at 100 times the clock, 32 ticks a frame, about
    72 s; 30 000 ticks in a focused run): worst 0.025 to 0.061 m; a bolt fired 20 km out curves 0.408 m in 4 s and flies the
    analytic path (third order, from the frame's own residual) within 0.009 m. `test_standins.gd` (no field with no system; a
    capital holds its cruise against the pull over 2 s, which fails without the pull on its body), `test_bench.gd` (the
    battle runs in orbit of `epsilon_iii`, pulls, and the rail is back after), `test_bench_layout.gd`. Quick tier: 1 836 of
    1 836 GUT, 126 Rust, 331 Python. With `GUT_SLOW=1`: `test_flight_parity_fight` 1, `test_core_threads`, `test_bolt_rows`,
    `test_tier`, `test_tier_fire`, `test_tier_handover`, `test_tier_outcomes`, `test_tier_proxies`, `test_free_fall`,
    `test_velocity_rebase`, `test_world_frame`, `test_sim_core`, `test_debris_pool`, `test_explosion`, `test_static_shift`,
    `test_flight_model`, `test_parity_fixture`, `test_bench`, `test_standins`, `test_ai_think_time` pass.
    `test_rebase_in_play` failed 4 of 9 on `Targets/Jumpgate/FarProp/Dot` (top level, not shiftable): the jumpgate's work in
    progress in the same checkout, not this task's files.
  - **AC10**, `bench battle 1000` (pinned 0-11, the machine idle, load under 1.2): `bench_quick.sh` (500, 1 000) tick
    median 4.44 and 5.59 ms, p99 5.93 and 7.84 before; 4.52 and 5.63, p99 6.17 and 8.05 after. Two 20 s runs each
    (`warmup=3 seed=1`): median 5.74 and 5.67 ms before, 5.73 and 5.70 after (mean 6.01 and 5.83 against 5.88 and 5.85).
    Within 1 %, against 5 % allowed. In the battle the pull reaches about 270 ships, 680 tier rows (12.6 us) and 1 100 bolts
    (19 us) a tick: about 35 us, 0.6 % of the tick. `test_ai_think_time` passes (AiPilot median 197 us for 13 ships).
  - **The seeded weapon battle (`test_weapon_rows_battle.gd`, slow): compared again with no gravity, no defect, a new
    reference (2026-11-12, at the maintainer's word).** The test failed after the moon went: 802 hits against the GDScript
    recording's 918 (826 allowed), capitals' 359 against 446 (401 allowed). The GDScript battle was run again at the
    recording's commit (`0586e3e`, exported, its own library and assets built) with the moon on and off, and the native
    battle at `c4e4d785` with no gravity and in orbit, every hit logged. 30 s, 100 ships, seed 1; hits, capitals' hits,
    beam shots, launches, missiles shot down, mines set off:

    | battle | tier | hits | capitals' | beams | launches | shot down | mines |
    |---|---|---|---|---|---|---|---|
    | GDScript, M4's moon, clock not reset (the old recording, reproduced) | off | 918 | 446 | 174 | 150 | 26 | 0 |
    | GDScript, M4's moon | off | 955 | 470 | 180 | 151 | 26 | 0 |
    | native at `0586e3e`, M4's moon | off | 955 | 470 | 180 | 151 | 26 | 0 |
    | GDScript, no gravity | off | 920 | 431 | 185 | 151 | 24 | 0 |
    | native, no gravity | off | 920 | 431 | 185 | 151 | 24 | 0 |
    | native, T07's orbit (the new recording) | off | 933 | 420 | 174 | 151 | 25 | 1 |
    | native, M4's moon (T05) | on | 885 | 406 | 159 | 146 | 28 | 0 |
    | native, no gravity | on | 822 | 362 | 171 | 149 | 28 | 0 |
    | native, T07's orbit | on | 802 | 359 | 166 | 147 | 28 | 0 |

    - **The native rows are the GDScript stand-ins, hit for hit.** With no gravity and the tier off, today's native battle
      lands the GDScript battle's 920 hits one for one: the same tick, shooter, target kind, damage and relative speed.
      Seed 2 the same (728 hits, 347 by capitals); seed 3 the same 717 and 334 but for the last digits of one missile's
      relative speed on the final tick. At `0586e3e` the two paths also agree hit for hit, moon on or off.
    - **The missing hits were the tier's, not the weapons'.** The GDScript battle was recorded with the tier off (its
      default until M4-T23 turned it on at 10 km, after the recording). With it on, three capitals and about three
      fighters of this battle fly as tier rows; their fire is rolled (7 capital hits from 84 rolls, 5 fighter hits from
      16 shots) and never reaches the hit resolver the test counts. By category, tier off against on with no gravity:
      capitals 431 to 362 (CRUISER 6 41 to 0, DESTROYER 5 10 to 0, CARRIER 2 92 to 72; 44 of the 69 are 10-point hits
      on targets that are not ships: missiles, mines or rocks), fighters 489 to 460. That is the 9 to 14 %
      T05 left open.
    - **The moon moved the capitals' count less than it seemed.** Tier off, the moon added 35 hits (955 against 920), 39
      of them the capitals'. The old recording's 918 and 446 is the same battle with the sim clock not reset (the reset
      was added in the commit that stored it); with the reset it is 955 and 470.
    - **The reference.** `weapon_rows_battle.json` now holds the native battle in the bench's orbit with the tier off
      (933, 420, 174, 151, 25, 1); the test turns the tier off, checks that no ship flew as a row, and keeps its 10 %. In
      orbit, not with no gravity: the bench's battle has one gravity now (D66) and a no-gravity switch would be a second
      path kept for one test; the orbit's battle also runs the pull on bolts and capitals, and it sits 1.4 % (hits) and
      2.6 % (capitals') from the GDScript battle with no gravity, so the recording is still tied to the GDScript
      reference. The tier off, because the test is about the weapon rows the resolver sees and the tier's fire has its
      own test (`test_tier_outcomes.gd`). The GDScript numbers and this comparison are in `tests/fixtures/parity/README.md`.
      With `GUT_SLOW=1`: recorded [933, 420, 174, 151, 25, 1], now the same. **Confirmed by the maintainer (2026-11-12):**
      the test keeps the tier off and guards the weapon path; the tier's far fire stays with its own tests.

### M6-T08 Flying under gravity

- **Goal:** AC5 (D67).
- **Files:** `src/ship/speed_governor.gd`, `src/ship/ship.gd`, the assist's and the brake's inputs, `src/world/reference_frame.gd`
  (pure), the HUD's reference and altitude (`hud_input.gd`, `hud_frame.gd`, `hud_painter.gd`), the planet-impact rule, settings for
  anything new, tests (a headless low orbit held with assist on; the brake's stop against the reference).
- **Tests:** `ReferenceFrame` and the brake's stop against the reference: quick; the headless low orbit held with assist on:
  standard.
- **Done when:** AC5.

- **Done (2026-11-12):**
  - **The rest velocity** (D64, D67). Every ship reads its speed against a rest: its reference's velocity in the local frame
    and what that reference falls with. `kernels::flight::Rest` goes into `flight::tick` beside `env_accel`: the brake gets
    `v - v_rest` and the feed-forward `env - a_rest`, the thrust fade, the assist's safe speed and the hard ceiling read
    `|v - v_rest|`, and the ceiling cuts to 9 999 m/s on top of the rest (Q4); the pull itself is still applied in full. With a
    zero rest every expression is the old one (kept as a branch), so the parity recordings keep their bits. The flight step
    (`flight_step.rs`) gives each ship the World's rest (`ScsSimCore.frame_rest`: minus the frame's velocity against its anchor
    and minus the origin's own pull; zero while the frame rides), or a ship's own (`set_rest` / `clear_rest`, for a batched
    ship with a reference). The tier's step takes the World's rest for its fighters' beat and its ceiling. `Ship`'s own model
    (the player's) does the same in GDScript (`rest_velocity()`, `rest_accel()`, `set_reference_rest`,
    `SpeedGovernor.clamp_against`); `ship.speed` in the console is the speed against it.
  - **`ReferenceFrame`** (`src/world/reference_frame.gd`, pure): Q6's pick (the mission's reference when it names a candidate,
    else the nearest place whose broadcast holds the ship, holding a tenth beyond its range, else the dominant body, else
    none and the World's anchor), the rest of each (a place's velocity and fall; for a body the circular orbit's velocity at
    the ship, prograde in the plane of the ship's motion about the body, at `sqrt(pull r)` from the zone rule's pull, falling
    with the ship's own pull, so the brake's feed-forward cancels and it settles the ship into that circle), and the
    altitude rule (a body is the reference, or the ship is within `settings.hud_altitude_radii` radii of its surface).
    **`FlightReference`** (`src/world/flight_reference.gd`, priority -5, after the core's sync and before the ship) is its
    shell for the player: candidates are the place the World falls with (when it is a place, with
    `settings.reference_place_range_km`, 1 000 km), the jumpgates (their `Targetable`'s broadcast) and the dominant body from
    the core (`frame_reference_body`: index, centre and velocity in the local frame in 64-bit, the pull at the ship;
    `frame_body_state` for a mission's body). It hands the ship its rest every tick and takes a boost's `dv` off it at the end
    of the tick, so the HUD's speed does not jump between ticks. Console `reference [auto|<id>]` (the mission's seam) and
    provider `reference` (name, kind, rest velocity and acceleration, speed, range, altitude, mission).
  - **HUD:** `REF <name>  <range>  <closing>`; the speed, the velocity marker, the drift sphere and the angles are read against
    the reference (`HudLayout.relative_velocity`); `ALT <km>` on a line under it near a body. `Main.reference_point()` is the
    reference's universe position (the launch point when there is none), so `RebaseFight`'s HUD check still holds. Names come
    from the data (`name` on bodies and places, `StarSystem.display_name`), so the speed's jump on a change of reference
    (station to planet) is explained beside it.
  - **Brains:** the brains' snapshot (`snapshot_into`) takes the World's rest off every local velocity (bodies, tier rows,
    missiles, bolts); rocks, mines and props keep their own motion against the anchor, which is what their rows hold, so in
    the brains a rock is at rest and cruise, stop and run-up speeds are against the place. Zero rest: no change.
  - **The other readers of T05's list:** spawn velocities in data are against the place (`Main`'s player and scenario spawns,
    waves, mission spawns and gate arrivals, encounters with no ship anchor add `rest_velocity()`); `Ship.reset_to` leaves a
    ship at rest against the anchor; a missile steers and holds its speed as seen from the anchor (`steer_missile`); rocks in
    the ram resolver move with the anchor (velocity and start) and `head_on` reads the closing speed against the rock; an
    anchored prop's row velocity gets the rest added in the ram resolver; the hit resolver sweeps a bolt against the rocks on
    its path as seen from them (the narrow phase; the rocks' broad phase still takes the bolt's own segment); the ram tracker
    takes a body it does not hold as moving with the anchor; an anchored marker's target velocity (a buoy's lead) adds the rest.
  - **Planet impact** (D67, Out): `PlanetImpact` (an internal child of the `WorldFrame`, priority 205) asks the core each tick
    for the ships and capitals among its rows (tier rows included, the player's ship too) inside a body's impact radius (its
    radius plus `atmosphere_top_m`, pushed with the system: `StarSystem.impact_radii`, `frame_set_impact_radii`), and kills
    each with `HitInfo.CAUSE_PLANET` (god mode does not hold a ship up). Nothing is read while the frame is quiet. Provider
    fields `world.planet_impacts`, `world.last_impact`, `world.rest_velocity`.
  - **The automatic velocity rebase is on** in `main.tscn` (`auto_boost_speed_mps` 2 000, back under half).
  - Tests. Rust 133 (7 new: the brake stops a ship against its reference and falls with it; no rest keeps the bits, the fade and
    the ceiling ride on the rest; a body seen from a rail, the dominant body and its pull, the impact radius, the origin's pull;
    the tier's ceiling against the rest). GUT, **quick**: `test_reference_frame.gd` (new, 8), `test_flight_reference.gd` (new,
    4, 1.7 s: the brake on both paths, the station then the planet as reference with the circle 2 km along the track reading 0,
    the player and an AI row destroyed 70 km up and one at 150 km not, the automatic boost at 2 500 m/s with the HUD's speed
    unchanged across it and through the way back), `test_low_orbit_flight.gd` (new, 5, about 2 s, so quick rather than the
    planned standard: in the 400 km orbit the speed reads under 0.01 m/s; with assist on and the brake held 20 s the ship stays
    within 0.000 m / 0.0011 m/s of its orbit riding, 0.029 m / 0.0027 m/s in a frame boosted 2 500 m/s and 0.097 m / 0.0059
    m/s at 6 000 m/s, past the assist's 5 000 m/s safe speed; the brake settles a ship 48 m/s off the orbit into the circle at
    400.02 km within 0.1 m/s, which then coasts within 0.0011 m/s of circular for a minute), `test_hud_layout.gd`,
    `test_speed_governor.gd`, `test_star_system.gd` (one new test each), `test_ship_scene.gd` (the new `ship` key).
    With the automatic velocity rebase on, the main-scene tests that fly past 2 000 m/s read the speed against the reference
    (`test_speed_and_autotrack.gd`: the assist's safe speed, coasting above it, the fade toward the ceiling, now with the frame
    boosted under them), and the two position-rebase runs at 4 000 and 5 000 m/s in `test_rebase_in_play.gd` turn it off to
    keep crossing 5 km (one more assert: `main.tscn` sets 2 000). Quick tier: 1 857 of 1 857 GUT, 133 Rust, 331 Python. With
    `GUT_SLOW=1`: `test_weapon_rows_battle` (recorded [933, 420, 174, 151, 25, 1], now the same), `test_ai_think_time`
    (AiPilot median 185 us for 13 ships), `test_parity_fixture`, `test_flight_parity_fight`, `test_rebase_in_play` (9),
    `test_speed_and_autotrack`, `test_tier_handover`, `test_ram_damage`, `test_rocks_and_mines`, `test_hit_resolver`,
    `test_gravity_orbit`, `test_standins`, `test_main_scene`, `test_hud`, `test_free_fall`, `test_velocity_rebase`,
    `test_world_frame`, `test_flight_batch`, `test_flight_step`, `test_tier`, `test_sim_core` pass. The parity recordings
    keep their bits.
  - Bench, `bench_quick.sh m6_t08_after battle` (500, 1 000; pinned 0-11, load 0.6, T15's GPU runs in the same hours): tick
    median 4.59 and 5.71 ms, p99 6.17 and 7.62, every budget held; T07's after: 4.52 and 5.63, p99 6.17 and 8.05. The bench
    rides its anchor, so every rest is zero and the new work is one branch per ship and the planet-impact check over the rows
    (two bodies). Within the run-to-run spread.
  - (H): the assist and the brake under gravity (the brake settling into the circle; holding the brake far from any place is
    an orbit, not a stop against the planet); the `ALT` line under `REF` and the long `REF` line in the chase view's corner;
    the 1 000 km station reference range; planet impact bypassing god mode.
  - Left: GDScript-only brains (`perceive()`, the few pilots not native-capable) still read frame velocities (the native
    snapshot is the seam in play); a turret marker on a moving capital keeps its row velocity; the rocks' broad phase in the
    hit sweep takes the bolt's own segment off the anchor; T09 places the scenarios (the reference picks whatever is there).

### M6-T09 Scenarios at true scale

- **Goal:** the scenario half of AC6.
- **Files:** `ScenarioLoader` (spawns relative to a body, a station point or an orbit; `epoch`), `data/scenarios/*.json`, the
  missions' data where they name positions, `Main`'s start, the encounter director's spawn shell (it spawns relative to the
  player's reference), tests for each spawn form.
- **Notes:** the Civilian escort's belt and beacons keep their layout, moved as a whole to the station's orbit; every mission's
  headless tests run unchanged in outcome.
- **Tests:** each spawn form in the loader: quick; the missions' headless runs keep their tiers.
- **Done when:** AC6; free flight starts beside the station's stand-in with the planet in view.

- **Done (2026-11-12):**
  - **Where a scenario is: `anchor`** (`src/world/scenario_frame.gd`, `ScenarioFrame`, pure; parsed by `ScenarioLoader` into
    `frame`). Three forms: `{"place": "babylon5", "at": [x, y, z]}` (on a place's rail; `at` is where the place stands in the
    scenario's coordinates, so every layout keeps its numbers; `standin`, default true, puts the station's stand-in there);
    `{"body": "epsilon_iii", "altitude_m": h, "phase_deg", "inclination_deg"}` (a circle that high, at that phase at the
    epoch); `{"orbit": {"body", "a_m", "e", ...}}` (any orbit, the star system's own keys). The orbit forms get their start
    state from the ephemeris on a copy of the system with the orbit added as a place (`StarSystem.orbit_state`), so GDScript
    still computes no orbit. No `anchor`: the station's rail with the scenario's origin on it and no stand-in, which is what
    every test's own scenario had before. Refusals name the key and why.
  - **The anchor is the scenario's origin** (D64 kept: a `UniversePos` is relative to the World's anchor). For the place
    form the World rides the place's rail with `WorldFrame.anchor_offset` (the scenario's origin from the place, 64-bit): the
    core is told the origin against the place itself (`_push_origin` adds the offset, `_adopt_origin` takes it off), so the
    gravity, the bodies, the impacts and the rest velocity need no change. The few readers that took the anchor to be the
    place subtract it: `ScaledSpace.body_from_anchor` and `FlightReference.places` (the station's place). So no scenario
    position moved: the layouts, the missions' scripts, triggers, cinematics and wave anchors are untouched, and the
    missions' outcomes are the same by construction. The alternative (moving every position in the loader by the offset)
    would have touched six consumers of `"origin"` and the escort's script for no gain.
  - **When: `epoch`**, seconds of system time at the start (or `"seeded"`). Decision: **the sim clock still starts at 0**;
    the World holds `epoch_s` and `system_time()` = epoch + `SimClock.now()` is what every ephemeris reader asks (the frame's
    sample and orbit anchor, `ScaledSpace`, `StarSystemHost`, the gate's placing). Seeding `SimClock` itself would have
    changed every gameplay timer's rounding (M4-T37 starts each battle at 0 for that) and fed large times to shaders; on the
    World it also keeps D71 (no new state in an autoload) and cannot leak between tests. `ScaledSpace.STAND_IN_EPOCH_S` is
    gone; `epoch_offset_s` stays 0 for `scaled epoch` captures. A seeded epoch (`ScenarioFrame.seeded_epoch`) takes a day of
    the planet's year from the seed and, on a place's rail, the times of one turn of the station whose start is lit (key
    light 0.999 or more), has the planet's centre within 25 degrees of the player's forward and its disc at least half lit,
    and picks one from the seed; on an orbit only the light counts. About 3 to 8 ms.
  - **Every scenario at true scale**: all seven files name `{"place": "babylon5", "at": [5500, -1200, -6000]}` (the
    station 6.6 to 9.6 km from each start, front right of the -Z layouts; `belt_showcase` has it at [2000, 4500, -9000], above
    its belt) and an epoch: free flight `"seeded"` (from the run's seed, as its encounters); the sandbox, the civilian
    showcase, the belt showcase and the civilian escort 540 148 s (the planet 8 degrees off ahead, 67 % lit); the instructor's
    route 3 267 594 s (3 degrees, 98 %); the dogfight 7 482 671 s (its player faces -X: 13 degrees, 95 %). The escort's belt,
    beacons and route keep their layout with the station beside its start. `Main._anchor_world` resolves the frame (a frame
    the system cannot place falls back to the station's rail with a warning), sets the epoch and anchors; `FarPropHost.
    place_station` builds, dresses (`dress_station`) and places the stand-in for good (`far station` takes it away and puts it
    back at the same place); the gate stands on its rail where the ephemeris has it at the start (`JumpgateHost.place` with
    the frame: 50 km ahead on the station's orbit, its front toward the station), the bearing only a fallback with no frame,
    and a rail beyond the gate's 1 000 km broadcast is not placed.
  - **Encounters** take their planned velocities against the player's reference (`EncounterDirector._reference_rest`: the
    reference's rest, else the World's); against the station that is zero, as before.
  - **Found on the way:** with an epoch of 0 the sun lies exactly to the side of a camera looking along -Z (the sun's
    direction has no Y), and `LensFlareAim.sun_uv` asked Godot to project a point on the camera plane (`p.d == 0`, an error
    each frame that failed the mission tests); the probe is now nudged a hair in front (off screen). `system.bodies` printed
    a format error (GDScript has no `%e`); fixed with `String.num_scientific`.
  - Console: `system` gains `epoch_h`, `time_h` and `anchor`; `scaled epoch` is an offset on the World's system time; `far
    station` toggles at the station's place. In `info.md`.
  - Tests. **Quick** (in `tests/quick_suite.txt`): `test_scenario_frame.gd` (new, 9, 0.4 s: no anchor, the place form and
    the station where `at` says, the gate 50 km ahead on the rail at three epochs, the body form's circle, phase and tilt, the
    orbit form at periapsis with the vis-viva speed and its own `epoch_s`, nine refusals, seeded epochs for seven seeds lit
    with the planet ahead and repeatable, epoch 0 in the shadow, every shipped scenario lit with the planet in view and the
    station 6 to 12 km off); `test_scenario_anchor.gd` (new, 4, 0.8 s: the core sees the station at `at` and the planet at the
    epoch's place, through a position rebase, off the anchor at 2 500 m/s and back; the layer and the HUD's reference measure
    from the scenario's origin; a body anchor falls from the scenario's state with the planet pulling);
    `test_true_scale_start.gd` (new, 2, 0.8 s, the real main scene: free flight's seeded epoch with the sim clock at 0, the
    dressed stand-in at [5500, -1200, -6000], the gate 50 km from it facing it, the planet drawn within 30 degrees of the
    view, key light 1, REF BABYLON 5 at the stand-in; another seed another epoch; the sandbox keeps 540 148 s). Standard:
    `test_lens_flare_aim.gd` (one new test), `test_jumpgate_in_play.gd` (the gate's 50 km now measured from the stand-in).
    The missions' and scenarios' headless runs with `GUT_SLOW=1`, outcomes unchanged: `test_civilian_escort` 12/12,
    `test_civilian_flight` 5/5, `test_dogfight` 4/5 (the balance fight pending, as gated; the same-seed fight identical),
    `test_instructor_route` 4/4, `test_m3_sandbox` 1/2 (balance pending), `test_asteroid_belt` 4/4, `test_mission_runner`
    18/18, `test_mission_skip` 7/7, `test_rebase_in_play` 9/9, `test_speed_and_autotrack` 16/16, `test_wave_director` 15/15,
    `test_jumpgate_in_play` 3/3, `test_hud` 13/13, `test_main_scene` 14/14, `test_encounters` 17/17, `test_scaled_space`
    18/18, `test_far_props` 8/8, `test_flight_reference` 4/4, `test_free_fall` 7/7. Quick tier: 1 872 of 1 873 GUT (the one
    failure is `test_velocity_rebase` reading `AsteroidField._bodies`, which T21's work in progress changes), 136 Rust, 331
    Python. The compile check and the console smoke (`wait 30; state ship; state system`) clean.
  - GPU (RX 6950 XT, RADV, Wayland, Forward+, free flight, 1200x675 asked, 1500x844 drawn): `forward_plus`, 64 draw calls,
    `render.vram_mb` 411 MB (sysfs 2 893 MB with the desktop), 41 fps in the short run (the window opened and closed
    unfocused); key light 1.00. Screenshot (H): `references/screenshots/M6-T09 start/free_flight_start.png`: the planet ahead
    over the ship, the station's stand-in front right, REF BABYLON 5 at 8.2 km.
  - (H): the start view (the station's place `at` [5500, -1200, -6000] and its orientation along Z; the planet's phase
    rules: within 25 degrees, half lit or more); the fixed epochs chosen per scenario; free flight's planet is nearly full
    for some seeds (the sun behind the player), half lit at worst.
  - Left: the gate is placed on its rail at the start and then holds still in the frame, while its true place turns round
    the station once an orbit (the chord between them moves about 4.5 m/s, 16 km an hour); M7 or a moving prop row can carry
    it. The station's stand-in has no collision (M4's look-only stand-in; M7 replaces it). `docs/architecture.md` §14.6 and
    §19 are T16's.

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

- **Done (2026-11-12):**
  - **The depth decision: one pass, the layer's depth pinned in its vertex shader** (the "reversed depth with a clamp" option).
    Each body is a small stand-in sphere a few km from the near world's own camera; `assets/shaders/scaled_body.gdshader` gives
    every pixel of it one reversed depth from a slab just in front of the far plane (2e-9 to 1e-8: behind everything nearer than
    about 49.5 km, in front of the star points at 1e-9 and the sky at 0), the nearer body the larger value. So the near world,
    the far dots and every transparent effect draw over the planet with the ordinary depth test, the planet hides the star
    points, the nebula and the star's disc, and there is no second camera, viewport or compositing step. The layer therefore
    has no camera of its own. Measured on the RX 6950 XT (RADV, Wayland, Forward+, combat sandbox, planet in view, `look 150`),
    against a SubViewport with its own world and camera composited behind (built for the measurement, not kept; a second
    camera pass in Godot is that same extra viewport):

    | Window | Variant | Draw calls | Triangles | VRAM (`render.vram_mb`) | GPU frame |
    |---|---|---|---|---|---|
    | 1200x675 | no layer (`scaled hide`) | 64 | 49 090 | 333.5 MB | 0.31 to 0.66 ms |
    | 1200x675 | pinned depth (chosen) | 65 | 65 730 | 333.5 MB | 0.31 to 0.75 ms |
    | 1200x675 | SubViewport | 66 | 65 732 | 369.8 MB (+36 MB) | 0.33 to 0.50 ms + 0.04 to 0.10 ms for the viewport |
    | 3200x1800 | no layer | 64 | 66 502 | 645.7 MB | 1.25 to 1.51 ms |
    | 3200x1800 | pinned depth (chosen) | 65 | 83 142 | 645.7 MB | 1.26 to 1.63 ms |
    | 3200x1800 | SubViewport | 66 | 83 144 | 866.5 MB (+221 MB) | 1.30 to 1.57 ms + 0.09 to 0.28 ms for the viewport |

    FPS sat at the display's 144 to 145 in every run (the compositor caps it even with `--disable-vsync`), so the GPU frame time
    is the measure; the pinned depth is inside the noise of no layer at all. The SubViewport costs a full second set of render
    targets (221 MB at 3200x1800) and its picture would bypass the main view's anti-aliasing, upscaler and motion vectors. The
    plain version of one pass (true depth at the drawn distance) was ruled out without a measurement: a ship 45 km away would
    be hidden behind a stand-in drawn at 20 km. `/sys/class/drm/card1/device/mem_info_vram_used` read 2 829 to 3 150 MB across
    the runs, moved more by the desktop's other clients than by the variants, so the table uses Godot's own figure.
    The slab relies on the 32-bit float depth buffer this GPU has (as the star points' 1e-9 already does).
  - `src/environment/scaled_placement.gd` (pure): `place(camera, body, radius)` from two 64-bit places against the anchor gives
    the direction, the true distance, the angular radius, the stand-in's offset and radius (distance and radius shrunk by one
    factor: 1:1000 while that fits, else onto a 20 km shell, so the angle and the limb's perspective are exact and everything
    stays inside the 50 km far plane) and its layer depth (by the logarithm of the true distance); `camera_from_anchor`
    (`origin` + local, 64-bit), `to_game` (kernel axes to the game's). `src/environment/eclipse_math.gd` (pure): the part of
    the star's disc a body leaves showing, from positions and radii (the two discs' overlap).
  - `src/environment/scaled_space.gd` (`ScaledSpace`, made by `SpaceEnvironment`): one sphere per body of the star system of
    **the World the current camera is in** (`WorldFrame.of(camera)`, so no single-frame assumption, D71), re-placed every
    frame, late, from the ephemeris at `SimClock.now()` and the camera's drawn (interpolated) pose. A rail anchor sees a body
    straight through `relative_state(body, place)`; a free-falling anchor is `anchor_state()` against its home body, so the
    planet never passes through a barycentric number. Placeholder look: the star a flat disc in the star's colour
    (`StarColor` from `StarCatalog`), the planet a rust sphere with a plain day and night side lit from where the star is
    seen from the planet (unshaded, so it takes none of the 8 lights). With no star system on the World nothing is drawn.
  - `SpaceEnvironment`: `follow_sun()` each frame turns the `KeyStar` so its +Z points at the true star (what `PostEffects`
    reads, so the lens flare follows with no change) and multiplies its energy by `ScaledSpace.key_light()`, the smallest lit
    part over the planets. With no star system the authored light stays. `hold_key_star(true)` gives the light to a look sheet
    at full energy: `LookScene` takes and returns it (`src/rendering/look_scene.gd`, three small additions).
  - **A stand-in epoch, to be removed by T09:** at the data's epoch 0 the station is exactly behind Epsilon III from the star,
    in the middle of a 65 minute eclipse, so every run would start with the key light out. Until scenarios seed an epoch (Q9)
    the layer looks at the system 23 300 s (a third of the station's orbit) later than the sim clock
    (`ScaledSpace.STAND_IN_EPOCH_S`, `epoch_offset_s`): the planet is 120 degrees from the sun and three quarters lit.
    It moves only the picture and the light, not the frame's gravity. T09 should set the scenario's epoch on the sim clock (or
    here) and set the constant to 0; the maintainer may prefer another phase.
  - Console: provider `scaled` (`bodies`, `layout`, `has_sun`, `sun_direction`, `key_light`, `epoch_h`), command
    `scaled [status|epoch <hours>|show|hide]`. In `info.md`. No setting: nothing here is the player's to tune.
  - Tests: `tests/unit/test_scaled_placement.gd` (quick, 10: directions, 20.02 degrees from the station, the star's 0.65, the
    angular size kept inside the bounded depth, 1:1000 close in, a rebase changes nothing, a metre and a millimetre kept at
    planetary range, the axes, the depth order, the centre of a body), `tests/unit/test_eclipse_math.gd` (quick, 6),
    `tests/integration/test_scaled_space.gd` (quick, 11, 0.5 s: a World on the station's rail and in a 400 km orbit, 3 000 km
    off the anchor and after a rebase, the planet round the sky over a quarter orbit, no system, the key star's direction and
    energy in and out of the shadow, the look sheet's hold, the console), `tests/integration/test_scaled_space_gpu.gd`
    (standard, Pending headless, 3: the disc's height in pixels against its angular size within 3 px, a marker at 10 m, 5 km,
    30 km and 49 km drawn over the planet, the planet hiding the star's disc; green on the GPU).
  - GPU, planet in view, 1200x675 window: from the station's rail `forward_plus`, 145 fps (the display's cap), 70 draw calls,
    99 020 triangles, 333.5 MB; from `frame orbit 400` 144 fps, 85 draw calls, 107 680 triangles, 333.6 MB.
  - Screenshots (H) in `references/screenshots/M6-T10 scaled space/`: `station_planet.png` and
    `station_planet_after_rebase.png` (the planet's pixels the same but for the ships in front), `station_sun.png` (the disc
    under the flare), `station_eclipse.png` (`scaled epoch 0`: key light 0, the night side hides the stars),
    `orbit400_limb.png`, `orbit400_limb_after_rebase.png`, `orbit400_down.png`, `orbit400_terminator.png`.
  - For T11: replace the planet's material on `ScaledSpace.sphere_of(id)` (or the sphere itself), keep the shader's vertex
    stage (`layer_depth`) and read `sun_direction`; an atmosphere shell is a second sphere with the same placement and depth.
    The 128-segment sphere's limb is about a pixel coarse from 400 km at 1080p; a per-pixel sphere would fix it. `scaled epoch`
    gives the look sheet its day, terminator and night. For T12: the star's sphere is `sphere_of(&"epsilon")`; no flare shows
    in `station_eclipse.png`, but nothing here fades it on purpose (`key_light()` is the factor to use), and the disc's
    brightness (8) is a guess.
    For T15: a far station or gate is one more `ScaledPlacement.place` with its own stand-in; `layer_depth` orders it among
    the bodies. Not checked: the stand-ins' motion vectors under TAA and FSR 2 (a custom `POSITION`); `docs/architecture.md`
    is T16's.

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

- **Shader half done (2026-11-12):**
  - `src/environment/planet_look.gd` (`PlanetLook`, pure): reads the planet's manifest (maps, wisp and haze tints) and the star
    system's `radius_m` and `atmosphere_top_m`; the planet's frame (`orientation`: the maps' north on the ephemeris's z, the
    game's +Y, u = 0 toward the ephemeris's +x, east toward its +y; no tilt or spin, the data has none), the sun in that frame
    (`sun_in_body`), the haze shell's radius and scale height (a fifth of the 100 km top), and how far the coarse mesh is pushed
    out to enclose the true sphere (`mesh_inflate`, 1.0034 for 64x32). A body without built maps is not fatal: it keeps
    T10's plain stand-in, with a warning.
  - `assets/shaders/scaled_planet.gdshader`: the surface on a 64x32 sphere (half T10's triangles), each pixel finding its own
    point on the true sphere (closest approach, no large-number cancellation), so the limb is round from any distance (T10's
    "a pixel coarse from 400 km" is gone) and the mesh's facets never show. Maps sampled with `textureGrad`, the gradients
    taken from whichever of two u's is continuous at that pixel, so neither the 0 nor the 180 degree meridian drops to the
    smallest mip (a dashed line before the fix), anisotropic and mipmapped (the imports carry the mips). The normal map's relief
    is lit only where the sun is up and the terminator is hard (a smoothstep over -0.02 to 0.1 of the sun's height); the night
    side keeps 0.004 of the albedo (about 5/255 on screen, no lights); the wisps are lit by the sun's height only. Full sun is
    `sun_strength` 1.5 against the Filmic tonemap.
  - `assets/shaders/scaled_atmosphere.gdshader`: a shell to the atmosphere's top, added over the surface (`blend_add`, no depth
    write, its depth a hair in front of the planet's in T10's slab). 16 samples of exponential air along each view ray, each
    counted only while its air is sunlit (a band from just past the terminator), tinted by the manifest's `limb_srgb`: the lit
    limb gets a faint warm rim and a thin glow just outside the disc, the night limb none, the face-on disc almost nothing.
    `haze_strength` 0.012 is a look choice (H).
  - `ScaledSpace` (T10's layer): a body with maps gets the surface material, its own axes in the stand-in's basis (its scale
    is still the placement's radius, so T10's size checks hold) and the shell as a child (`shell_of`); `sun_body` on both
    from where the star is seen from the planet. Provider `scaled` gains `mapped`; no new command. Both shaders keep T10's
    vertex stage (`layer_depth`) and are `cull_front`, so they also work with the camera inside the shell.
  - `scripts/planet_sheet.sh` (`planet_sheet_node.gd`): the look sheet on this GPU with the game's sky and light and no ships
    (views from the station's rail, a 400 km orbit, 1 000 and 10 000 km up), each line with the GPU time; `layer=off` for
    the baseline.
  - Tests: `tests/unit/test_planet_look.gd` (quick, 10: the manifest, the air from the data, bad manifests, missing maps,
    north and east against the ephemeris, a tilted pole, the sun in the planet's frame, longitude and latitude against the
    generator's layout, the coarse mesh enclosing the sphere, Epsilon III's built maps); `tests/integration/test_scaled_space.gd`
    (quick, 3 more, 14 in all: the maps, axes and shell wired, the sun in the planet's frame, the maps mipmapped);
    `tests/integration/test_planet_gpu.gd` (standard, Pending headless, 4: the limb a true circle to within 2 px at a 2 degree
    view where the facets measured 5.3 px; the terminator hard, the night side under 0.03 with no relief past it, the day side's
    relief; the warm glow on the lit limb only; no line at either seam, checked to fail with the seam bug put back);
    `test_scaled_space_gpu.gd`'s disc height now hides the haze (the glow is the new file's). Quick tier: 1 801 tests in 127
    scripts, green; both GPU files green on the RX 6950 XT.
  - GPU (RX 6950 XT, RADV, Wayland, Forward+, 1200x675 window, combat sandbox on the station's rail, `look 150`, HUD on),
    against the same build with the manifest moved aside (T10's plain stand-in): `forward_plus`, 145 fps both (the display's
    cap); 71 to 73 draw calls against 70 to 72 (the haze shell); 90 584 triangles against 98 776; `render.vram_mb` 378.6 MB
    against 360.1 MB (+18.4 MB for the three maps; the baseline has grown from T10's 333.5 MB with other tasks' work). GPU
    time with the planet filling the view (`planet_sheet.sh`, layer on against off, mean of 40 frames): 1200x675 +0.08 ms from
    the rail, +0.13 ms at the 400 km limb, +0.24 ms looking down from 1 000 km; 3200x1800 +0.25 ms on both measured views.
  - Look sheet (H) in `references/screenshots/M6-T11 planet/`: `rail_day`, `rail_terminator`, `rail_full`, `rail_crescent`,
    `rail_eclipse` (night side near black, the star behind), `rail_like_still` (lit from the upper right as in the still),
    `rail_lit_limb_zoom` and `rail_dark_limb_zoom` (3 degree views: the round limb and the glow on the lit side only),
    `orbit400_lit_limb`, `orbit400_day_limb`, `orbit400_down`, `orbit400_terminator`, `orbit400_night`, `alt1000_lit_limb`,
    `alt1000_down`, `alt10000`; in game with the HUD: `game_station.png` (beside `game_station_before_t11.png`, T10's
    stand-in) and `game_orbit400_a.png` (`frame orbit 400` starts on the night side, so the night limb with the star behind
    it); `compare_with_still.png` puts the in-game planet beside the generator's preview in the same light. **The still
    `references/Epsilon III planet.png` is not on this machine**, so its panel is a placeholder: once it is back, the
    generator's `look_sheet` (`tools/procgen/assets/planet.py`) sets it beside the preview, and `rail_like_still.png` is
    the in-game planet in the preview's light.
  - Open, for the maintainer (H): the haze's strength (0.012) and the surface's brightness in full sun (1.5); the albedo reads a
    little pink and pale beside the description's rust and tan (the generator half's note too); the map is soft when seen from
    400 km straight down (4 096 texels round, about 1.2 km each), a detail layer would be a later task. No spin or axial tilt:
    the data has none. Not checked: the shells' motion vectors under TAA and FSR 2 (as T10).

### M6-T12 The sun

- **Goal:** the sun half of AC7.
- **Files:** the sun's disc and glow on T10's layer, `src/rendering/lens_flare_aim.gd` and the flare's source on the true
  direction, the star's colour from `data/star_systems.json`.
- **Tests:** pure direction and colour tests: quick; GPU files: standard.
- **Done when:** AC7's sun and light; a look sheet for the maintainer (H).

- **Done (2026-11-12):**
  - `assets/shaders/scaled_star.gdshader`: the star on T10's layer, on a sphere `SunLook.GLOW_SCALE` (10) times its disc. Each
    pixel works out its distance from the disc's centre in disc radii (sine of the angle over the sine of the disc's angular
    radius), so the disc is the true size, with limb darkening (0.7) inside and a corona outside (a power-law falloff faded out by
    9.5 radii), additive, `depth_draw_always`, the same pinned depth (its vertex stage is T10's), so the planet and the near
    world draw over it and the star points are hidden behind it. The disc's brightness is 2.4 against the planet's full sun
    (1.5): the Filmic tonemap and the environment's bloom (threshold 1) fold it to a white core with the orange kept in the
    limb and the corona; a brighter disc (5) was a flat white blob. The corona starts below the limb's own level, so the disc's
    edge stays a line. The old flat-disc path (`glows`, `brightness`, `STAR_BRIGHTNESS`) is gone from `ScaledSpace` and the
    plain shader keeps only the planet stand-in's look.
  - `src/environment/sun_look.gd` (`SunLook`, pure): the disc's colour from the temperature (`StarColor`, 5 084 K for Epsilon
    Eridani: orange-white), the corona's (warmer, less blue), the shader's uniforms, the brightness law (`profile`, the shader's
    twin) and `flare_factor(lit_part)`: a smoothstep from 0.02 of the disc showing to all of it.
  - The flare: `ScaledSpace.flare_strength()` (1 with no star) goes to `PostEffects.set_flare_strength()` from
    `SpaceEnvironment.follow_sun()` each frame, which scales the flare's tint (`FLARE_LEVEL` times the strength); a held key
    light (look sheet) leaves it at 1. So the flare fades with the eclipse and through the limb, measured on the look sheet:
    sun 10.0 degrees from the planet's centre (its limb) gives key light 0.42, flare 0.37; behind the planet 0 and 0. Its
    direction was already the true sun's: `PostEffects` reads the `KeyStar`, which `follow_sun()` turns (T10), so
    `lens_flare_aim.gd` needed no change. The key light's colour is the star's, from `set_star` (Q30, set before T12).
  - One patch to the vendored flare's shader source (`SceneLensFlareEffect.SHADER_PATCHES`, the add-on untouched): a depth
    of 2e-8 or less reads as open sky. The far bodies' pinned depths are 2e-9 to 1e-8, so without it the star's own disc
    would have hidden the flare (the star points never did, they write no depth). A planet over the star is the key light's
    job, not the depth test's.
  - Tests: `tests/unit/test_sun_look.gd` (quick, 7: colour from the data, hotter is bluer, a warmer corona, the flare full and
    gone, smooth, the profile, the uniforms); `test_scaled_space.gd` (quick, 3 more, 17 in all, and the star's drawn size now
    the disc times the glow scale: the star material and colour, the flare against the eclipse over nine steps out of the
    shadow, a held light); `test_post_effects.gd` (the new patch applies); `tests/integration/test_sun_gpu.gd` (standard,
    Pending headless, 3: the disc's height in pixels within 3 px of its angular size, the corona three radii out and the
    orange colour, the flare's streak there in the open and gone in the shadow; green on the RX 6950 XT).
  - GPU (RX 6950 XT, RADV, Wayland, Forward+): the combat sandbox at 1200x675 reads `forward_plus`, 145 fps (the display's
    cap), 71 draw calls, 378.6 MB (`render.vram_mb`), the same as T11's planet numbers. With the star filling the bench
    (`planet_sheet.sh sun_open`) the layer costs 0.025 ms at 1200x675 (0.652 against 0.627 ms) and 0.007 ms at 3200x1800
    (1.875 against 1.868 ms), one draw call. `planet_sheet.sh` gained the views `sun_*`, `flare=` (`SHEET_FLARE`) and `layer=`
    (`SHEET_LAYER`) options.
  - Look sheet (H) in `references/screenshots/M6-T12 sun/`: `sun_open` and `sun_wide` (the star alone, 24 and 70 degree
    views), `sun_off_axis`, `sun_planet` and `sun_orbit400` (the star and the planet in frame, from the rail and from a 400 km
    orbit), `sun_limb_a` to `sun_limb_c` (the star going behind the limb: hidden, half, just out, flare 0, 0.37, 1),
    `sun_eclipse` (the middle of the shadow, no star, no flare).
  - Open, for the maintainer (H): the disc is a white core under the Filmic tonemap with the orange in the corona (brightness
    2.4, corona 0.25 of the disc, limb darkening 0.7 are look choices in `SunLook`); the add-on's glare also draws a large flat
    haloed disc round the star in the picture (about 185 px radius whatever the field of view), which Q31's patches left; it is
    the flare's, not the corona. Not checked: a flare half under a nearer ship's hull in the real game (the depth patch lets
    anything above 2e-8 close it, as before).

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
  - **Layout corrected under T19 (maintainer, 2026-11-11):** the four arms run parallel to each other and to the vortex's axis,
    round it like the corner rails of a square tube (800 m from the axis), not as flat spokes; the mouth sits at their front
    ends and the funnel runs back to their back ends. Generator v2, markers rebuilt (see T19).
    Round 3: at the top, bottom and sides, the side arms 1 080 m out, an elliptical mouth (generator v3, `mouth_aspect`).
    Round 4: the side arms 1 240 m out (aspect 1.55, generator v5).
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

- **Done (2026-11-11, `cfc7882`):**
  - The gate (`src/props/jumpgate.gd`): the generated mesh, 44 Jolt boxes on the rock layer, no hull (bolts pass through), a
    `Targetable` (`PROP`) broadcasting to 1 000 km. No gameplay scene holds the station's stand-in yet, so free flight and the
    sandbox get a `jumpgates[]` entry: 50 km from the scene's origin (the data's distance), toward -Z, facing the origin.
  - The vortex (`jump_vortex.gd` and its shader): a funnel with flash and tip billboards, driven by the pure `VortexTiming`
    (1 s tip glow, 1 s flash, 1.5 s growth, 4 s open, 1 s close); orange/yellow out, blue in.
  - The player's jump: the pure `GateJumpPrompt`, `GateJump` and `GateAutopilot`, and the adapter `JumpgateHost`. Within 10 km
    with the gate targeted the HUD shows `X: REQUEST JUMP` and X sends `request_jump` (auto-track elsewhere); controls lock,
    the autopilot lines up 1 440 m out (around the arms if behind) and runs in at 250 m/s, the cinematic shot, a flash, fade
    and 2 s of black, then out through the blue vortex at 200 m/s with control back after 3 s or 500 m.
  - Data: a mission spawn with `arrival: "gate"` and `m.depart(name)`; an encounter pool's `gate` table sends a share of
    arrivals or departures through the gate while the player is within 25 km (free flight has one). Without either, nothing
    changes; `JumpArrival` stays for open points. Console `gate` (`status`, `open`, `close`, `jump`, `cancel`, `target`,
    `approach`) and provider, in `info.md`.
  - Tests: quick `test_vortex_timing`, `test_gate_jump`, `test_jumpgate_data`, `test_jumpgate_broadcast`; standard
    `test_jumpgate_in_play` (the player out and back, an AI ship in and out, an encounter raid). Quick tier green (1 604 in
    202 s); the touched SLOW files (`test_m3_sandbox`, `test_flight_parity_fight`) green.
  - GPU, **oscar** (R9 200 / Tahiti, not the maintainer's RX 6950 XT), 960x540 Forward+: 94 to 117 fps, 76 draw calls, 76k
    triangles with the vortex open, 58 to 60 fps in the cinematic; VRAM 322 MB in the renderer (sysfs 673 to 970 MB).
    Screenshots in `references/screenshots/M6-T14 jumpgate/`. Open (H): the vortex's look, the shots' framing; the gate
    vanishes beyond 50 km (the camera's far plane) until T15. `docs/architecture.md` waits for T16.

### M6-T15 Far representations

- **Goal:** AC9 (D70).
- **Files:** `src/rendering/lod_switcher.gd` and `far_dots.gd` for the large props, the scaled-space impostors from T10, the
  station's stand-in, the gate and the planets.
- **Tests:** the drawn size across each hand-off: quick if pure, else standard.
- **Done when:** AC9.

- **Done (2026-11-12):**
  - **Three draw paths per big prop** (`FarPropMath`, pure; `FarProp`, the node; both in `src/rendering/`):
    1. **near**: the prop's own mesh where it is, the importer's levels doing the rest (§14.4), out to `pull_m` = the far plane
       (50 km) less 1.02 bounding radii and 500 m: **48.2 km for the gate** (bounding radius 1 265 m round the middle of its
       arms), **45.4 km for the station's stand-in** (4 028 m).
    2. **shrunk**: past that, the same nodes (body, vortex, lamps; the station's frame and turning drum) drawn shrunk toward the
       eye by `pull / distance` under one `Look` node, so they cover exactly the same angle in the same direction with the same
       materials, lights and levels: the hand-off is continuous by construction (no switch, so no hysteresis is needed). Shrunk,
       the meshes take `lod_bias` 100: at a few pixels the importer's coarsest levels drop the gate's rails altogether
       (measured: no light at all 6 px out with the default bias). This is D70's "scaled-space impostor" drawn in the near
       world's own depth rather than on T10's pinned slab: T10's layer is unshaded and near the camera, so a textured hull on
       it would have had to copy the PBR light, the ambient and the sheen and would have caught the player's own thruster
       lights; in the near world it is the same picture. The cost: something truly in front of the prop but between the pull
       distance and the far plane (the last 2 to 5 km before 50 km) is drawn behind it.
    3. **dot**: once the bounding radius is under **`DOT_PX` = 4 px** a far dot takes over (`far_prop_dot.gdshader`: M4's
       far-ship rule, the angular size with a 1 px floor and the square dimming under it), drawn at the shrunk centre, with
       M4's hysteresis (`LodSwitcherMath.far_dot`: back a tenth inside) and a **0.35 s cross-fade** (the mesh's
       `transparency` up as the dot's alpha comes in). The dot covers what the mesh covers **from that direction**: the
       generators now write a silhouette table (`tools/procgen/core/silhouette.py`, manifest `far`: the outline's area along
       227 directions, the axes and rings round them included; generators v4), blended by Shepard's rule (3 % mean error
       against the true outline, 15 % worst near the gate's axis). A gate seen end on covers a sixteenth of its side view
       (15 600 against 196 000 m^2), so a dot sized by its bounding sphere would have been twenty times too bright.
       Hand-off distances: the gate **223 km** at a 1 080-line cockpit view (75 degrees), 139 km at 675 lines, 229 km in
       `far view` (50 degrees, 675 lines); the station **709 km**, 443 km, 729 km. Why 4 px and not M4's 3 km a ship: below
       about 10 px the gate's thin rails hit or miss whole pixels (no MSAA by default) and its light jumps by a factor of two
       or more between sub-pixel shifts; at 4 px the dot carries it steadily.
  - **The dot's light** follows the mesh's: the mean albedo (manifest) times the ambient, the hull's own glow (lamps, windows,
    sheen with no sun: 0.41 of the albedo) and the key star's energy and colour times `hull_phase` (a broad term and a back-lit
    lobe, fitted on the GPU: the textured hulls' sheen keeps them bright past quarter phase and lights the rims against the sun,
    5.8 times full phase at 160 degrees; a Lambert sphere would have had them go dark there). In the planet's shadow the key
    light is 0 and so is its share. Measured against the mesh (`test_far_props_gpu.gd`) the dot's light is within a factor of
    two from every side tried (0.6 to 2.4 at 30 to 60 px); the cross-fade turns that into a gentle change, not a pop (H).
  - **The planet** keeps T10's layer at every distance; once its disc is under 4 px (about **841 000 km** at 1 080 lines) it
    hands over to the same dot on the layer's pinned depth (`ScaledSpace.dot_of`, `is_dotted`), sized to the disc's area,
    painted with its maps' mean albedo (`PlanetLook.mean_albedo`) times the surface shader's full sun (1.5) times a Lambert
    disc's mean light at its phase, with M4's hysteresis; so it stays visible however far out the camera goes.
  - **The gate** builds its `FarProp` in `_ready` (body, vortex and lamps under `Look`; collision, marker and the gate's own
    place untouched). An open vortex is kept drawn as itself when the gate is a dot (its own detail by distance is T20's).
    **The station's stand-in**: `FarPropHost.dress_station(standin)` after `build()`; no gameplay scene holds the stand-in yet,
    so `far station` places it at the station's place (the scene origin the scenarios place the gate from) for captures, and
    **T09 should call `dress_station` where it places the stand-in for good**. It has no `Targetable`, so its range is taken
    as a nav beacon's, 1 000 km (`FarPropHost.STATION_RANGE_M`).
  - Nothing here moves with a rebase on its own: the look and the dot are ordinary children of the prop (not `top_level`), so
    a position rebase or a drift moves them with it until the next frame places them again; `test_rebase_in_play` (GUT_SLOW)
    green, 9 of 9 (an earlier `top_level` dot failed its "left behind" check).
  - Console: provider `far` (`props`, `layout`: each prop's path, distance, shrink, bounding px, covered px^2, fade, range) and
    command `far [status|station|view <gate|station> <km>|off]` (`FarPropHost`, made by `Main`). In `info.md`. No setting.
  - A Color handed to a `vec3` shader uniform is taken as sRGB and darkened (0.0957 drew as 0.0094); the dots' paint goes in
    as a `Vector3`.
  - Tests: `tests/unit/test_far_prop_math.gd` (quick, 11): both manifests' tables, the end-on sliver, the blend continuous
    (under 30 % a quarter degree, 1.5 % a hundredth, the gate's own outline steps 19 % in its first quarter degree off axis),
    the shrunk prop's angle equal to 1e-9 rad and its far side inside the far plane, the dot's hand-off and its tenth back
    with no flapping under 1 % jitter, mesh and dot covering the same area from all 227 directions to 1e-6, flying out from
    100 m past the dot distance and back at 2 % a frame from three sides with the covered area within **0.5 %** of what the
    distance alone explains every frame, every distance from 100 m to 1 000 km drawn, the light laws.
    `tests/integration/test_far_props.gd` (quick, 8): the gate's look holds its visuals and not its collision or marker,
    drawn where it is to 48.2 km, shrunk to the same angle (1e-6 rad) and direction past it with collision and marker unmoved,
    the cross-fade in past the dot distance with the same covered area all through it and back a tenth inside, an open
    vortex kept, the dot's light with the sun, the station's two pieces shrunk with the drum still turning, the console.
    `test_scaled_space.gd` (quick, one more: the planet's dot, its hysteresis, its area, its pinned depth, day and night
    paint). `tests/integration/test_far_props_gpu.gd` (standard, Pending headless): near and shrunk draw the same pixels
    and light either side of the pull distance within 2 % (gate and station); the mesh covers the table's area within 35 %
    (1.11 to 1.32 measured: the lamps' casings and perspective); the dot draws its shader's law to 0.2 %; the dot's light at
    the hand-off within a factor of two of the mesh's. Python: `test_silhouette.py` (quick, 5), the generators' tests check
    the section (standard).
  - GPU (RX 6950 XT, RADV, Wayland, Forward+, combat sandbox, `far view`, 50 degree field, a 1500x844 window: Wayland's 1.25
    scale on `--resolution 1200x675`): **the gate at 1 000 km** `forward_plus`, 145 fps (the display's cap), 23 draw calls,
    40 802 triangles, `render.vram_mb` 379 MB; **the station's stand-in at 1 000 km** (a dot there, the gate one too) 136 to
    145 fps, 26 to 30 draw calls, 37 648 to 61 494 triangles, 410 MB (its pieces' maps), GPU time 0.51 ms. A far prop's dot
    is one draw call; the shrunk mesh is the prop's own (the gate 15 840 triangles at `lod_bias` 100). `test_far_props_gpu.gd`
    on this GPU: near and shrunk within 2 % of each other in pixels and light for both props, the mesh against the table
    (1.11, 1.20, 1.32 and under 1.35 from four sides), the dot's law to 0.2 %; the hand-off light 0.62 with the sun behind
    the eye (8 sub-pixel shifts), the second lighting case not finished: the window was hidden and Wayland stopped drawing it
    mid-run, so that case and a full green run of the file are (H) on a visible window.
  - Screenshots (H) in `references/screenshots/M6-T15 far/` (X11, 1200x675, the window hidden so 1 fps, HUD on): `gate_0.1km`
    to `gate_1000km` (0.1, 1, 10, 48.0 and 48.4 either side of the pull, 50, 100, 200 and 225 shrunk, 233 a dot, 215 still a
    dot, 500, 1 000), `handoff_strip.png` (the centre crops side by side: no change across the pull, a faint few pixels
    either side of the dot hand-off), `station_0.1km`, `station_1km`, `station_10km`. The station's far frames are missing:
    the Wayland run drew no new frames with the window hidden, and an X11 run at 1 fps held the shared Godot lock too long;
    `far station; far view station <km>` takes them on a visible window (its hand-off is 729 km at 1200x675, 911 km at
    1500x844).
  - Open, for the maintainer: (1) **the station's range**: it has no `Targetable`, so 1 000 km (a beacon's) was taken; a
    station may want more, or a `Targetable` of its own (M7). (2) **How visible a far dot should be**: it follows M4's rule
    (dimmer by the square under a pixel), so the gate at 1 000 km is a faint point (about 0.1 px^2 of its dull hull; end on
    almost nothing) and the gate is barely visible past about 200 km. Options: keep it (true to the hull's size); a floor on
    the dot's brightness inside the broadcast range (a beacon's glint, fading out past the range so nothing pops); or the
    lamps as their own far point. (3) The hand-off light is within a factor of two, not tighter: the truss's sheen and lamps
    vary with the view more than one law follows (H on the cross-fade). Not done: the open vortex's own far form (T20);
    `docs/architecture.md` §14.4 (T16); the dots' motion vectors under TAA and FSR 2 (as T10).
  - **Decided (maintainer, 2026-11-12):** (1) the station's stand-in keeps 1 000 km (M7 may revisit with the real station);
    (2) the far dot keeps M4's rule (far objects fade honestly; the HUD and radar find them).

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
- **Done (2026-11-11):** commits `cb4784e` (A, B), `96119a0` (C), `6b26d03` (C8, D). Every entry re-read in full against
  `m6` (both tests with their `before_each` and helpers); asserts only the removed side made were moved first.
  - A8 done: `tests/fixtures/seeded_battle.gd` (`SeededBattle`) builds the seeded battle and the small fights for the six
    battle files in the recordings' build order; no recording was re-taken, every digest still matches.
  - A1 to A4 merged: the 1-vs-6 battles of `test_core_state`, `test_bolt_rows`, `test_row_commands` and `test_driver_step`
    folded into `test_core_threads`' 600-tick one, which now flies with the ram resolver and a player (near and far thinkers)
    and compares the rows, hits and rams, bolt table, core commands and driver events.
  - A5 and A6 merged: `test_driver_step`'s far-rate test went, and its recording (`driver_step.json:battle_far_rate`) is
    checked by `test_row_commands`' battle, which is the same battle (same rows digest and thinks); A6's test stays.
  - A7 done: `core_state.json`'s three identical old-path cases are one, `battle_on_the_old_paths` (the values were equal).
  - B1 removed `test_ram_contact_columns` and `ram_contact_columns.json` (the same rams and poses as `core_state.json`); its
    hull-source assert moved to `test_core_state`'s melee. B2 removed `test_fighter_melee`: `test_core_state`'s melee pins
    the same run at full precision, and now also its 2 959 Jolt contact points (`T14_DIGEST`'s dump went with it).
  - C1 done: `RamTracker.contacts`, `Sample` and `_open` removed; `test_ram_tracker` drives `contacts_columns`;
    `test_ram_tracker_columns` removed, its reset case moved. C2 done: `RadarModel.dots`, `dot_for` and `radius_for_range`
    removed; `test_radar_model`, `test_hud` and `test_broadcast` read `plot`, `test_radar_plot` lost its plot-equals-dots
    test. C3 done: `test_missile_guidance` flies `ScsWeaponRows.steer`; `MissileStandin.steer` stays as
    `test_missile_kernel`'s oracle (its doc comment says so). C4 kept: both wrappers reach the production kernel and `clear`
    is production (through `clear_seen`); moving the tests to perceptions adds nothing. C5 kept (the design oracle, as
    planned). C6 done: the two M4-T05a distance-check tests went; `in_range` stays (console `native bench`), checked by the
    bench test against GDScript. C7 reported, not deleted: `src/frontend/placeholder_screen.gd` (`PlaceholderScreen`) is
    referenced nowhere; the maintainer keeps it (2026-11-11). C8 removed (`test_runner_works`).
  - D1 done (the tank line moved into the tank test). D2 kept: `test_fx_specs` also matches each material to its spec
    (speeds, spread, accelerations), and the other copy is the damping guard's own loop (rule 2). D3 done: the Jolt line
    joined the damping guard (added only); `test_smoke` became `test_project_settings` (quick), the quick tier's damping
    check. D4 done: `test_ship_lights` still drives the curve through `advance` (keep it if E11 is applied). D5 done (the
    facade tests that remain are about the facade). D6 done (maintainer, 2026-11-11: drop one): the GUT copy
    `test_the_acceptance_script_prints_300_then_250` went; the AC's own smoke stays, as it runs the separate process. D7 kept: the scene test is the only
    check that `LodSwitcher` feeds its state back, the pure one pins the exact edges. D8 done (`test_console_command_list`
    boots the sandbox; `test_info_md` left the quick list). D9 done (into `test_settings_schema`). D10 done
    (`test_debug_console` asserts both autoloads are present).
  - Recordings and readers: `core_state` (`test_core_state`), `driver_step` (`test_driver_step` near and far,
    `test_row_commands` far rate), `row_commands` (`test_row_commands`), `bolt_rows` (`test_bolt_rows`); the other 16 files
    are untouched with their readers; `ram_contact_columns.json` deleted with its last reader. The damping guard, the
    `*_holds_no_engine_type` guards and the per-subsystem 1-vs-6 and threaded-vs-delayed tests are untouched.
  - Totals: 9 files deleted, 27 GUT tests fewer (3,324 to 3,297 declared), 1,275 test lines and 148 source lines removed,
    817 lines net. The six battle files alone: 149 s to 96 s run alone.
  - Tiers: `test_project_settings` quick (in `tests/quick_suite.txt` for `test_smoke`); `test_info_md` left the list; moved
    asserts took their new files' tiers. Quick: 264 s, exit 0 (1,581 GUT tests).
  - Standard tier: 6,633 s before (T17), 5,709 s after (95 min; Python 2,482 s of it, GUT 2,895 s, 3,295 tests, 13 pending as before), exit 0. Both runs were made in a detached worktree of `6b26d03`
    (no branch): T14's unfinished work in the main checkout (`main.gd` naming `JumpgateHost`) fails every main-scene test
    there until it lands.

### M6-T19 The vortex reworked and stand-alone

- **Goal:** the vortex as the maintainer described it from T14's screenshots (2026-11-11), and one vortex for every jump point.
- **Shape at a gate:** the mouth lies in the gate's front plane; its rim reaches to a few metres short of the four arms' inner
  tips (about 800 m), and the rim fades to translucent. A **shallow funnel**, visible but not pronounced, recedes behind the
  gate to a depth equal to the arm's length (1 200 m).
- **Look and motion:** layers of colour: the base colour (orange/yellow out, blue in), with **smaller, darker, roughly
  rectangular patches with soft edges that move in a spiral along the funnel**, and perhaps translucent patches of the base
  colour moving with them. Meshes and shaders only (D22); the timing stays `VortexTiming`'s.
- **Stand-alone:** the vortex is its own logic and scene, sized and placed by whoever opens it: the gate (from its markers),
  a capital ship opening its own jump point (M12), and raider arrivals at open points, which replace `JumpArrival`'s flash
  (Q12 revised). An open point's vortex is sized for the ship that comes through.
- **Tests:** the funnel's fit to the gate's markers (rim, depth) and the open-point sizing: quick if pure; the arrivals that
  used `JumpArrival` keep their tests, moved to the vortex (their tier unchanged).
- **The opening, split between the gate and the vortex (maintainer, 2026-11-11):** (1) **gate only, the activation:** the
  lamps at the fin stations flash one after another along each arm, all four arms together, then the inner tips glow; it is
  the gate's own logic and timing, driven by its lamp markers (`GateActivation`, the lead-in of the vortex's timing). (2) **the
  vortex, the initiation flash** at the jump point's centre, for every point, gate or ship-made. (3) **the vortex, flash to
  funnel:** the funnel grows out of that point and unfolds toward the rim of its mouth, not a scaling in place. At a gate:
  activation, centre flash, unfolding, open, closing; a ship-made point starts at the flash.
- **The base depends on the view (maintainer, 2026-11-11, corrected the same day):** only the funnel's base, its narrow deep end,
  changes with the view. From outside the back or from the side it shows a moderately bright white glow, local to the base;
  the rest of the funnel stays visible round it and looks as usual. From in front, looking down the funnel, the base fades to
  black. The shader blends between them from the view direction against the axis.
- **The gate's arms run parallel to the vortex's axis (maintainer, 2026-11-11):** they sit round the funnel like the four
  corner rails of a square tube and contain it, each with a front and a back end; T13's flat spokes were wrong. The mouth sits at
  the front ends, the rim just under the arms' distance from the axis, the funnel runs back to the back ends (depth = arm length).
  The activation's lamps fire from the front end to the back end, then the jump point forms inside the arms. The generator, its
  markers and collision, `VortexFit`, `GateActivation`, `GateAutopilot`'s way round the arms and their tests follow.
- **Round 2 (maintainer, 2026-11-11):** the cone is translucent (stars and the far arms show through its walls); **a departure
  swirls in** (patches spiral down toward the throat) and **an arrival swirls out** (up from the throat to the rim), both turning
  the same way; a broad, gently curving well with a wide soft throat; the blue darker, less saturated and uneven, as the still;
  the patches small, many, drawn out along the spiral, soft-edged and filtered by distance; a darker feathered rim. A ship-made
  point does **not** pause after its flash (the pause in the reference gif is a fault in the gif).
- **Acceptance view (maintainer, 2026-11-11):** the arrival vortex fully open, seen from the pose of
  `references/jumpgate/jumpgate.png`, side by side with it. The bar is an **80 to 90 % match** to the references; small
  differences are fine, pixel matching is not wanted.
- **What the references show** (`references/jumpgate/`, looked at one by one before tuning):
  - `jumpgate.png` (and `jumpgate.gif`, which is a single still WebP, the same picture): the open blue vortex seen obliquely
    from in front, a wide ellipse framed by the four arms with their amber lamps; a dim, deep blue body with paler
    blue-white feathery streaks in a spiral toward a dark throat low and right of centre; the rim soft, fading out.
  - `jumpgate_open.png/jpg`: the activation peak: four hot pink-white glows with rays at the inner tips, a faint white haze
    between them; no funnel yet.
  - `gathering.png/jpg`: the gate in shadow: dark arms picked out by a row of small steady amber lamps, one per fin station;
    a nebula behind, no vortex.
  - `point_1.png/webp` (a ship-made point): a big blue funnel seen obliquely, mid blue, packed with small soft-edged darker and
    paler patches in a spiral, a black eye off centre, the rim breaking into radial wisps.
  - `point_2.png/webp` (a ship-made point opening): the initiation flash alone: a white core with lavender-blue rays on black.
  - The video frames (`yt_*`, the storyboard): lights along the arms, the tips flaring, one big white-pink flash, a pink spark
    that opens into a small blue ring and grows to the full funnel; the departure is the same in orange-gold with darker
    brown streaks.
  - Where they disagree: `jumpgate.png` is dim and deep blue, `point_1` and the video brighter and more cyan. Followed: between
    the two, closer to the video (the gate's hardpoint colours, a little dimmed), since the game is lit for the video's look.
- **Done when:** the fit and sizing tests; every mission and encounter that used `JumpArrival` arrives through a vortex with
  its outcome unchanged; screenshots of the gate's vortex (both colours, front and three-quarter) and of an open point for
  the maintainer (H); GPU numbers with the vortex open. **(H) acceptance view:** `gate view reference` (fitted to where the
  four rails' ends, the vortex's visible edge and the throat sit in the still; round 4's pose: camera at (-469, -433, -1485) m in
  the gate's frame, 1.5 km in front of the mouth, aimed at (-45, 80, 364), about 20 degrees off the axis, 59.8 degree vertical
  field, no roll), the side by side
  `references/screenshots/M6-T19 vortex/acceptance_jumpgate_png.png`, judged at an 80 to 90 % match.

- **Done (2026-11-11; round 2 the same day):**
  - **Stand-alone vortex** (`JumpVortex`, `jump_vortex.tscn`): `JumpVortex.create(colours, standalone)`, then
    `open_at(transform, VortexFit, direction, hold_s, lead_s)` (origin the mouth's centre, -Z the way out), `open`, `close`,
    `stop`, `extend`, `phase_name`, `is_open_for`, `open_in_s`. The centre flash (`jump_glow.gdshader`) at the funnel's base,
    then the funnel unfolds from there forward to the rim of its mouth (a vertex shader on a unit grid); the `jump_in` sound on
    arrivals; a light.
  - **The gate's layout corrected** (`a45a70e`, generator v2): the four arms run parallel to the vortex's axis, 800 m from it,
    from the front plane (the origin) back 1 200 m. The fins span round the tube (the stills show them standing out sideways
    from each rail), their V opening toward the axis.
  - **Fit** (`VortexFit.for_gate`, from the `vortex` marker): the generator measures the rim off the mesh, 8 m short of the
    nearest part of an arm (751 m, the trusses and fins reaching about 40 m in from the arms' 800 m); depth = the arm length
    (1 200 m, to the back ends); the mouth at the front ends (z 0). The well is a broad gaussian bowl with a rounded base.
  - **Open points** (`JumpPointPool`, replacing `JumpArrival` and `JumpArrivalPool`, retired): sized for the ship,
    `VortexFit.for_ship`: mouth radius = 4 bounding radii, never under 60 m, depth 1.6 radii (the gate's proportions); the
    mouth one ship radius behind it, facing its heading; a group arriving within 600 m in the first second shares the point,
    which widens to hold each ship (its offset from the axis plus its own point radius). The ship is placed as before (the
    pool opens after the ship is acquired), so missions and encounters keep their outcomes. No pause after the flash (added and
    taken out again in round 2, on the maintainer's word).
  - **Gate activation** (`GateActivation`, pure): the 1 s lead-in (T14's tip glow, so the gate still opens in 3.5 s): the 40
    lamps ranked into 5 stations by their place along the arm, flashing from the front ends to the back ends over 0.6 s on all
    four arms, then the back ends glow into the flash; one multimesh of glows, the lamps burning steadily (12 %) between
    openings, as the stills show a gate in shadow. `VortexTiming` takes the opener's `lead_s`
    (phases activate, flash, grow, open, closing).
  - **Look:** translucent walls (72 % opaque; the base fully opaque); base by view: a soft black smudge down the funnel from
    in front, a white glow over the base only from the side or behind; the arrival darker (brightness 0.5) than the departure
    (1.2); base colour with its weakest channel cut so the tonemapper keeps it blue, dark at the throat and rim, brightest over
    a band in between, washed unevenly; pale patches (44 round, long and thin) and dark patches (120 round) on spiral grids,
    edges widened by `fwidth` so at a distance they melt into their mean tone; the spiral's travel follows the direction (out
    for an arrival, in for a departure), the rotation the same; rim wisps from 0.42 of the radius.
  - **Console:** `vortex [status|open|close|view] [arrival|departure] [radius_m]` and provider `vortex`; `gate view
    <front|three_quarter|close|tip|run_in|side|behind|reference|off>` (held capture poses, no letterbox); `gate open` holds
    20 s. `CinematicShot` keys take an optional `roll`. In `info.md`. `docs/architecture.md` (§18 D51 still names
    `JumpArrival`) waits for T16, as T14's notes do.
  - **Tests:** quick `test_vortex_fit` (the marker, the built asset inside its arms, ship sizing, widening),
    `test_gate_activation` (front-to-back chase), `test_vortex_timing`, `test_jumpgate_broadcast`, `test_gate_jump` (the way
    round parallel arms), `test_cinematic_shot` (roll); `test_mission_runner` (quick) holds the moved jump-arrival test;
    `test_encounters`, `test_mission_skip`, `test_jumpgate_in_play` (standard) green. Python: `test_jumpgate_helpers` (quick,
    17 tests) and `test_jumpgate` (standard, 107 s) green on generator v2. Quick tier green (1 614 GUT tests, 201 s).
  - **GPU, oscar** (R9 200 / Tahiti, 960x540, Forward+): first pass, window visible: 144 fps (6.9 ms), 25 draw calls, 51.6k
    triangles, 322 MB VRAM in the renderer, sysfs `card1` 947 MB. Round 2 captured with the window hidden (Wayland stops drawing
    it, X11 runs at 1 fps): 7 to 16 draw calls with the vortex open; **the final shader's frame rate is (H)** on the
    maintainer's machine.
  - **Screenshots** in `references/screenshots/M6-T19 vortex/`: `arr_*` (front, three-quarter, close, tip, side, behind,
    run_in, reference) and `dep_*`, `seq1_arm_lights`, `seq2_centre_flash`, `seq3_half_grown`, `arr_motion_a/b` and
    `dep_motion_a/b` (the swirl out and in), `raid_point_flash/open` (an encounter raid's point), `console_point_300m` and
    `console_point_departure`, `gate_closed_lamps`, `acceptance_jumpgate_png.png`; the references' storyboard and the gridded still in `storyboard/`.
  - **Against the references (own estimate, round 2):** `jumpgate.png` about 80 % (pose, the rails converging round the funnel,
    colour within about 10 % of the still's mean, the soft black throat low right, the faded rim, the lamps on the rails; still
    short: the still's streaks are finer and hair-like, its lamps larger and brighter), `point_1` about 85 %, the video's opening
    sequence about 85 %, `jumpgate_open` about 80 %, `point_2` about 80 %, `gathering` (the gate's steady lamps in shadow,
    `gate_closed_lamps.png`) about 80 %. Open (H): the look; the base glow's
    strength from behind; the final frame rate.
- **Round 3 (maintainer, 2026-11-11, after round 2's side-by-side):** the lamps are fine for now; the shape and texture are not.
  - **Arms:** at the top, bottom and both sides of the funnel, the side arms a little further from the axis than the top and
    bottom ones, so the four frame an **elliptical mouth**, wider than tall.
  - **Mouth:** its rim within **1 m** of the arms (it was 8 m short), following the ellipse.
  - **Swirl rotation:** seen from in front of the mouth, **counter-clockwise for an arriving (exiting) vortex, clockwise for a
    departing one**. The patches still travel in for a departure and out for an arrival.
  - **Colour:** lighter, a **dark sky blue** rather than navy, for the arrival vortex.
  - **Texture:** finer, hair-like streaks and a softer swirl, not separate bold bands.
- **Round 3 done (2026-11-11):**
  - **Arms and ellipse** (generator v3): top and bottom arms 800 m from the axis, side arms 1 080 m, all parallel to the axis
    from the front plane back 1 200 m. **Aspect 1.35**, option `mouth_aspect` (1 to 2): the camera and the aspect were fitted
    together to the rails' ends in `jumpgate.png`; the misfit is 31 px rms for a square gate, 23 at 1.2, 20.6 at 1.35, 20.2 at
    1.5, 22 at 1.7, so flat from 1.35 to 1.5, and the low end was taken ("slightly further"). The gate is now 2 242 m wide.
  - **Mouth:** `mouth_semi_axes` measures the ellipse that touches both pairs of arms off the mesh and draws it in 1 m:
    **1 038 m across, 755.5 m up** (the trusses reach about 45 m in from the arms' axes). The `vortex` marker carries
    `semi_axes_m` beside `radius_m` (the half height, the largest circle inside); arrival and departure points follow the half
    height (75.5 m and 1 511 m in front); emitters, lamps and collision follow the arms. `VortexFit` holds the half width
    (`semi_axes`, `aspect`, `contains`); the funnel is scaled by both, elliptical from the mouth to the throat, depth unchanged.
    A ship-made point stays round (no arms shape it). A departing ship counts as through inside the ellipse.
    `GateAutopilot` is unchanged (its 1 600 m diagonal is about 1 km clear of every fin), comments only.
  - **Swirl** (`VortexSwirl`, pure): seen from in front an arrival turns counter-clockwise and travels out, a departure turns
    clockwise and travels in, both along one spiral. Measured off two frames 1 s apart looking down the axis: arrival +13
    degrees and 10 to 20 px outward, departure -13 degrees and 9 to 19 px inward.
  - **Colour:** arrival `colour` (0.06, 0.38, 0.85), `highlight` (0.36, 0.75, 1.0) linear (was (0.045, 0.23, 0.9) and
    (0.38, 0.65, 1.0)); the body reads about sRGB (6, 60, 125) in the acceptance view against the still's (4, 42, 129).
    The departure colours are unchanged.
  - **Texture:** the spiral band grids are gone. Everything lies along one soft spiral (0.17 turns per e-fold of radius):
    broad uneven clouds, soft-edged roughly rectangular darker patches and paler translucent ones, and over them three widths
    of short hair-like streaks (120, 300 and 600 round the funnel), filtered by distance; the rim fades from 0.55 of the radius
    in feathers that follow the streaks; the throat's dark smudge is wider. Translucency unchanged (72 %).
  - **Acceptance pose** refitted (`gate view reference`): camera (-526, -533, -1588) m, aimed at (95, 137, 600), 52.4 degree
    field, about 23 degrees off the axis; fitted to the rails' ends and the dark throat's place (27 px rms; the rails alone
    give 24 px with the throat too near the middle). `gate view tip` moved out to the side arm.
  - **Tests:** quick `test_vortex_swirl` (new, 5 tests), `test_vortex_fit` (semi-axes, `contains`, the built gate's ellipse
    outside every collision box), `test_jumpgate_broadcast`; Python `test_jumpgate_helpers` (quick, 19 tests: the side arms'
    placement, the ellipse within a metre of both pairs, a square gate's round mouth) and `test_jumpgate` (standard, 103 s).
    Quick tier green (1 620 GUT tests, 202 s).
  - **GPU, oscar** (R9 200 / Tahiti, 960x540, Forward+, X11 at 1 fps as in round 2; Wayland stops drawing the window): gate
    vortex open 9 draw calls looking down the axis, 51.2k triangles, 322.6 MB VRAM in the renderer, sysfs `card1` 714 MB; an
    open point 25 draw calls. **Frame rate (H)** on the maintainer's machine.
  - **Screenshots:** `references/screenshots/M6-T19 vortex/acceptance_jumpgate_png.png` (the still left, the game right, lens
    flare off: the star's ghost otherwise falls on the throat from this pose) and `round3/`: `arr_*` and `dep_*` (`front`,
    `three_quarter`, `inside`, `behind`, `side`, `close`, `reference`, `motion_a/b`), `point_arrival_300m`, `point_departure_300m`.
  - **Against the references (own estimate):** `jumpgate.png` about 80 %: the combed streaks, the mottling, the soft dark
    throat low and right and the wide mouth between the four arms are there. Still different: the mouth reaches the arms'
    front ends, so it fills more of the frame than the still's, which lies inside the arms' inner tips; the still's ellipse is
    flatter (about 1.65 to 1 on screen against 1.35) and its streaks a little shorter and crisper; the blue is lighter than the
    still's on purpose; the top arm is dim; the lamps are as round 2. `point_1` about 80 % (it is patchier and paler; ours is
    streakier). The opening sequence, `jumpgate_open`, `point_2` and `gathering` are as round 2. The look stays (H).
- **Remaining work (maintainer, 2026-11-11, after round 3; the row stays `in progress`):** round 3 is about 80 % by the agent's
  estimate, the high 70s by the controller's. Paused here at the maintainer's word; when T19 resumes:
  1. **The mouth's apparent size:** in `jumpgate.png` the mouth sits inside the arms' inner ends; ours reaches their front
     ends and fills more of the frame. Pull its visible edge in to match the still while it stays within 1 m of the arms.
  2. **The ellipse's proportion:** the still's mouth reads about 1.65:1 on screen against ours at 1.35 (`mouth_aspect`);
     flatten toward the still.
  3. **The rim:** ours is fuzzier and spreads wider; tighten it toward the still's cleaner feathered edge.
  4. Still open (H): the frame rate with a visible window on the maintainer's machine, and the maintainer's acceptance of the
     side-by-side (`references/screenshots/M6-T19 vortex/acceptance_jumpgate_png.png`). The lamps are accepted for now; the
     top arm reads dim in the acceptance view.
- **Round 4 done (2026-11-12, items 1 to 4; the row stays `in progress` until the maintainer accepts the side-by-side):**
  - **The still:** `references/jumpgate/` was not on this machine (rounds 1 to 3 ran on oscar). `jumpgate.png` was restored from
    the wiki's `Jumpgate.gif` (the same still, a 385x269 WebP), `jumpgate_open.jpg` beside it; `point_1`, `point_2`, `gathering`
    and the video frames are still only on oscar. Measured off the still by masking its blue (pixels of the 385x269 still): the
    visible vortex is centred at (199, 146), its semi-axes 100.8 x 63.1 px, **1.60 to 1** (round 3 judged 1.65 by eye), tilted
    4 degrees; the throat at (241, 176); the eight rail ends marked by hand (`round4/crop_*`).
  - **1. The mouth's apparent size.** The two asks are both met by splitting the mouth from the visible body. The mouth (what
    ships pass, `VortexFit.contains`, the funnel's mesh) still reaches within 1 m of the arms. The bright body ends further in,
    at **`VortexFit.body_share`** of the radius: **0.665 at a gate**, fitted to the still's visible edge from the acceptance
    pose. That edge falls on the arms' back ends because by then the funnel's walls have receded about 240 m. Past it, a faint
    veil (0.4 % opaque) carries on to the rim at the arms. At a ship-made point the share is **0.9**: no arms frame it, and a
    widened group's ships still come out of the body, not the veil. Shader uniforms `body_edge`, `edge_soft`, `veil`. The look
    (bands, the throat's smudge, the base's glow) is laid out against the body's edge, so a gate and a point look alike. The
    unfolding reaches the body's edge near the end of the growth, and the veil's rim with it.
  - **2. The proportion:** **aspect 1.55** (generator v5): side arms 1 240 m out, the mouth **1 198 x 753.9 m** (1.59), the gate
    2 562 m wide. Fit: camera position, aim and field plus the body's edge, least squares against the eight rail ends, the still's
    visible ellipse (centre, semi-axes, tilt) and its throat, at fixed aspects. Columns: aspect, rail rms (still px; times 2.5 at
    960 wide), the ellipse's on-screen ratio, how far off the throat is:
    1.35: 25.7 px, 1.38, 37 px; 1.45: 25.6, 1.49, 39; 1.50: 25.8, 1.54, 39; **1.55: 26.2, 1.59, 40**; 1.60: 26.6, 1.65, 41;
    1.65: 27.2, 1.70, 41; 1.75: 28.5, 1.81, 43. The on-screen ratio is about the aspect plus 0.04, and the rails barely care
    between 1.35 and 1.6, so the ellipse decides. The rails fit no better than about 25 px at any aspect: the still's gate is
    planar spokes, and its right and bottom arms reach 35 to 50 px further in than parallel rails can. Round 3's pose with 1.35
    and its best body edge scores 29 px on the rails with a 1.39 ellipse. **Acceptance pose refitted:** camera
    (-469, -433, -1485), aimed at (-45, 80, 364), 59.8 degree field, about 20 degrees off the axis.
  - **The throat:** from any pose that holds the rails, the funnel's real base sits 40 px from the still's throat, too near the
    middle. The dark eye is now drawn where the line of sight runs on down the funnel into hyperspace, as if the throat carried on
    as a tube four depths behind the mouth (`eye_depth`, `eye_radius`). From in front it sits on the axis as before; seen
    obliquely it moves toward where the axis recedes, as in the still. The radial smudge is lighter.
  - **Measured in the game** (the same mask, 1200x675 cropped to the still's frame): the visible vortex centred at (192, 144),
    semi-axes 101.2 x 62.8 px, 1.61 to 1, tilted 5 degrees, the throat at (225, 177). The still: (199, 146), 100.8 x 63.1,
    1.60, 4 degrees, (241, 176).
  - **3. The rim:** instead of fading from 0.55 to 0.93 of the radius (feathered by 0.04), the body ends in a short edge 0.075
    wide (0.615 to 0.69 at a gate), feathered by 0.02 along the streaks.
  - **Side effects (H):** from the side and from `gate view tip`, the bright cone starts about 240 m behind the arms' front ends
    (the veil in front is nearly invisible). From the tip, the far wall's edge shows as a separate crescent beside the near wall.
  - **4. GPU, this machine** (RX 6950 XT, RADV, Forward+). Desktop window (Wayland; `--resolution 960x540` draws 1200x675 at the
    1.25 scale; overlay on), reference pose: 145 fps (the display's cap), 6.9 ms, 22 draw calls, 48 452 triangles, 352.6 MB
    in the renderer. The session was locked, so GNOME stopped drawing the window a few seconds into each run. The rest ran
    inside a **headless gamescope** (the same GPU and renderer, X11 inside it, capped at 60 fps, so GPU time is the measure).
    At 1200x675 with the gate's vortex open: front 0.42 ms GPU, three-quarter 0.44, reference 0.48, close 0.53, inside
    (`run_in`) 0.50; 4 draw calls (overlay off), 47 608 triangles, 352.6 MB. At 2560x1440, closed and then open from the
    same poses: close 0.77 to 0.99 ms, inside 0.77 to 1.01, reference 0.79 to 1.01; 526.9 MB. The vortex costs about **0.23 ms
    and one draw call**, even when it fills the screen from inside. An open point (300 m, `vortex view`): 0.38 ms in its flash,
    0.70 ms open, 15 draw calls, 0.60 ms once it has closed. sysfs `card1` VRAM: 2.86 GB desktop baseline, 3.22 GB peak at
    1200x675, 3.55 GB at 1440p. Nothing is costly close up. **For M6-T20 (detail by distance):** the cost is fill, about 0.1 ms
    per covered megapixel on this GPU. The vertex shader inverts `MODEL_MATRIX` per vertex (4 000 vertices a point); at a
    hundred points, hand it in per instance.
  - **Moved with the wider gate (T15's numbers):** the bounding radius 1 265 to 1 408 m, the pull distance 48.2 to 48.1 km, the
    dot hand-off about 223 to about 248 km at 1 080 lines.
  - **Tests:** quick `test_vortex_fit` (the body share: a gate's and a point's, kept when widening, a wingman 300 m out inside
    the body), `test_far_prop_math` (the gate's 1 408 m radius, its hand-off), `test_vortex_swirl`, `test_vortex_timing`,
    `test_gate_activation`, `test_jumpgate_broadcast`, `test_gate_jump`, `test_far_props`, `test_jumpgate_data` green (60
    tests). Python: `test_jumpgate_helpers` (quick, 19) and `test_jumpgate` (standard), 33 together, 41 s. Quick tier green
    (1 858 GUT tests, 124 s).
  - **Screenshots:** `references/screenshots/M6-T19 vortex/acceptance_jumpgate_png.png` (the still left, the game right, lens
    flare and overlay off) and `round4/`: `arr_*` and `dep_*` (`front`, `three_quarter`, `reference`, `close`, `inside`,
    `side`, `behind`; `arr_tip`, `arr_motion_b`), `point_arrival_flash`, `point_arrival_300m`, `point_departure_300m`,
    `fit_round4_overlay` (on the still: the fitted rails against the marked ends, the body's edge, the mouth at the arms),
    `fit_round3_overlay`.
  - **Against `jumpgate.png` (own estimate): about 85 %.** The visible vortex's size, place and proportion match within a few
    pixels, the rim is a short soft edge, and the eye sits low and to the right. Still different: the still's body is darker and
    deeper blue (ours is lighter on purpose, round 3), its streaks shorter and crisper (ours longer and more combed), its rails
    dark navy silhouettes lit by the vortex (ours lit warm by the sun), and its right and bottom rails reach further in
    (planar spokes). Open (H): the look; the truncated cone from the side and the tip; the frame rate in a visible window
    (these numbers were taken while the session was locked).
- **Round 4 not accepted (maintainer, 2026-11-12):** "Vortex funnel opening is too far away from jump gate arms. Bottom of funnel
  black circle is misplaced; must be at base of funnel. May be occluded by the rest of the funnel." Round 5: the visible opening
  comes right up to the arms (round 3's rule, for the visible edge too); the dark circle sits on the funnel's base, placed in 3D,
  and the nearer walls hide it from oblique views. Keep the aspect 1.55 and the cleaner rim.
- **Round 5 done (2026-11-12; the row stays `in progress` until the maintainer accepts the side-by-side):**
  - **The opening at the arms:** round 4's `VortexFit.body_share` and the veil are gone. The body runs to the rim and ends
    there in a short edge (from 0.93 to 0.98 of the radius, feathered by 0.01 along the streaks): half faded about 35 m inside
    the rim at the top and bottom and 55 m at the sides, gone 13 to 21 m inside it, and the rim itself 1 m from the arms. Points and gates
    look alike again. Aspect 1.55 and the short edge are kept.
  - **The dark circle on the base:** round 4's line-of-sight eye is gone (and with it the per-vertex matrix inverse that
    M6-T20 would have had to move). The circle is drawn on the funnel's own base, within 0.24 of the radius (soft from 0.13),
    with the funnel darkening toward it as before. For the walls to hide it, the funnel's triangles now run from the base out to
    the rim (`JumpVortex.funnel_mesh`): the base is drawn first and writes depth, the translucent walls (72 % opaque) blend over
    it. From in front and from `run_in` it shows down the funnel; from the reference and close poses it shows through the mouth
    (the base is in direct view at 20 degrees off the axis); from `gate view tip` the near wall covers it. From the side and
    behind the base glows white, as before.
  - **The pose:** refitted to the rails and the throat at the real base (the visible edge no longer enters the fit): it lands
    on round 4's pose again (rails 26.1 px rms against 26.2, the base 40 px from the still's throat either way), so `gate view
    reference` is unchanged.
  - **Against the still, measured:** the opening at the arms is 171 x 103 px in the 385 px frame (1.66 to 1), centred at (193,
    141). The still's visible vortex is 101 x 63 px: the still's gate is planar spokes whose inner ends frame its vortex, while
    our rails' front ends stand at the outer ends of the still's spokes from this pose. Opening the funnel to the arms makes it
    about 1.7 times the still's across. The dark circle is at (200, 156), the still's throat at (241, 176).
  - **GPU** (RX 6950 XT, headless gamescope as round 4, 1200x675; the session was still locked): reference 0.87 ms (the scene now
    has T09's nebula and lighting in view), close 0.43, inside 0.42; 4 draw calls, 384.7 MB in the renderer.
  - **Tests:** `test_vortex_fit` (round 4's body-share test out; new: the funnel draws its base before its walls), the vortex,
    gate and far-prop tests green; compile check clean. Quick tier: 1 840 of 1 858; the 18 failures are other tasks' work in
    the checkout (a camera `unproject` error in mission, target-menu, preview, pause and console scenes while T09 moves the
    scenarios to true scale; `AsteroidField._bodies` in `test_velocity_rebase` under T21), none in the vortex's files.
  - **Screenshots:** `references/screenshots/M6-T19 vortex/acceptance_jumpgate_png.png` (refreshed) and `round5/`: `arr_*` and
    `dep_*` (`reference`, `front`, `three_quarter`, `close`, `side`, `inside`, `tip`), `point_arrival_300m`,
    `point_departure_300m`.
  - **Own estimate against `jumpgate.png`:** about 75 to 80 %. The colour, the streaks, the soft rim, the ellipse and the throat
    at the base are there. The opening is larger than the still's because it now meets our rails, as asked. Open (H): the
    side-by-side.
- **Round 5 reviewed (maintainer, 2026-11-12):** "Round 5 looks great overall but now the edge is too defined. Let's see if we can
  get closer to the reference edge." Round 6: keep everything else from round 5 and soften only the rim toward
  `jumpgate.png`'s edge, measured: neither round 3's fuzzy spread nor round 5's crisp line.
- **Round 6 done (2026-11-12; the row stays `in progress` until the maintainer accepts the side-by-side):**
  - **The still's edge, looked at** (`round6/still_edge_crops.png`): a soft haze, not an even ramp. The body dims over a wide band
    and its streaks carry on into the fade as thin combed wisps along the spiral, with darker gaps between them. A faint haze
    lies just past it.
  - **Measured:** a radial brightness profile (blue channel, 1 px blur) across the edge along 36 rays, in each picture's
    own elliptical coordinate ρ (1 on the ellipse fitted to its vortex), normalised from the background (0) to the body at ρ
    0.55 to 0.8 (1), averaged over the rays with no arm or nebula behind them (24 in the still, 25 to 26 in the game). The
    game is cropped to the still's frame from `gate view reference`. Where the mean profile crosses each level:

    | | 90 % | 75 % | 50 % | 25 % | 10 % | 90 to 10 width | 75 to 25 width |
    |---|---|---|---|---|---|---|---|
    | `jumpgate.png` | 0.808 | 0.866 | 0.934 | 1.026 | 1.077 | 0.269 | 0.160 |
    | round 5 | 0.831 | 0.954 | 0.987 | 1.014 | 1.035 | 0.205 | 0.060 |
    | **round 6** | 0.792 | 0.852 | 0.936 | 1.007 | 1.052 | **0.260** | **0.155** |

    Mean profile at ρ 0.80, 0.85 ... 1.10: still 0.91 0.80 0.61 0.45 0.34 0.17 0.07; round 5 0.97 0.90 0.89 0.77 0.38 0.04
    0.01; round 6 0.87 0.75 0.62 0.46 0.28 0.10 0.03. Round 5's edge was nearly three times too sharp; round 6's is within
    0.07 of the still's at every sample, the still keeping a slightly longer faint tail (its haze).
  - **The shader:** the body fades from `rim_from` 0.69 of the radius toward `rim_to` 1.08 (past the rim, so about 8 % of the
    body is left at the rim and the faint edge still reaches the arms). The fade's edge moves by up to `rim_feather` 0.3
    times a wisp noise (48 coarse strands round the funnel, drawn out along the spiral, sharpened, with a little of the fine
    hairs). That breaks it up into wisps visible from afar, where the fine hairs alone melt into their mean (tried first: no
    visible change). The rest of round 5 is unchanged: the opening at the arms (171 x 100 px in the still's frame), the dark
    circle on the base at (200, 156) with the walls hiding it from the tip, the 1.55 ellipse, colour and streaks.
  - **Tests:** shader only. Compile check clean (702 scripts); quick tier green (1 881 GUT tests, 131 s).
  - **Screenshots:** `references/screenshots/M6-T19 vortex/acceptance_jumpgate_png.png` (refreshed) and `round6/`: `arr_*` and
    `dep_*` (`reference`, `front`, `three_quarter`, `close`, `side`, `inside`, `tip`), `point_arrival_300m`,
    `point_departure_300m`, `edge_still_vs_game.png` (the edge at three angles: the still, round 5, round 6),
    `still_edge_crops.png`.
  - **Own estimate against `jumpgate.png`:** about 80 %. The edge now fades and breaks up like the still's. Still different: the
    opening is larger (it meets our rails), the blue lighter, the streaks longer. Open (H): the side-by-side.
- **The closing flash (maintainer, 2026-11-12, after the departure and arrival sequence `round6/sequence_departure_arrival.gif`):**
  "The same way there's a flash when the vortex opens, there needs to be a flash when the vortex closes as well. Same for both
  arrival and departures." The flash is white like the opening one, not in the direction's colours (a correction the same day).
  - **Done:** `VortexTiming` has a phase `END_FLASH` (`end_flash`) between `CLOSING` and `CLOSED`, `END_FLASH_S` = 1 s (the
    opening flash's length). The funnel folds back to its centre during the 1 s close as before (the reverse of the
    unfold: it is pulled in from the rim to the base). The flash then mirrors the opening one: it rises through the last
    third of the fold, peaks as the funnel reaches the centre, and dies away over the second after it. It is the opening's
    own flash quad (`jump_glow`, white with pale rays) at the funnel's base, with the vortex's light. It plays for every
    jump point, gate or ship-made, in both directions. An opening now lasts 1 s longer (`done_at_s`). Nothing passes
    during the flash (`is_open` false, `open_in_s` INF from `CLOSING` on). `JumpVortex.open` keeps an opening only while it
    is still before its close, so a new one waits for the flash to finish. A departing ship still counts as through at half
    grown, before the close, and the gate's arrivals still wait for `open_in_s`. Neither `GateJump`, `JumpPointPool`
    (it takes back its oldest point when none is free) nor `JumpgateHost` needed changes beyond the providers' phase
    lists. `info.md`'s `gate` row lists the new phase.
  - **Tests:** `test_vortex_timing` (the phases with `end_flash`; new: the close ends in a flash like the opening, which rises
    through the fold, peaks with the funnel gone, fades, and keeps apart from the opening flash at a zero hold; a vortex in
    its closing flash is not held open again), `test_jumpgate_broadcast` (the gate's close: `end_flash`, no funnel, the flash
    shown, then gone). Green with `GUT_SLOW=1`: those, `test_gate_jump`, `test_vortex_fit`, `test_gate_activation`,
    `test_vortex_swirl`, `test_mission_runner` (55), `test_jumpgate_in_play`, `test_encounters` (20). Compile check clean (702
    scripts); quick tier green (1 883 GUT tests, 131 s).
  - **The sequence again** (Movie Maker inside headless gamescope, `--display-driver x11 --write-movie --fixed-fps 30`,
    1920x1080, `gate view reference`, `gate open departure 1`, then `gate open arrival 1`):
    `round6/sequence_departure_arrival_v2.gif` (720 px, 20 fps) and `..._v2.mp4` (1080p, crf 17), captioned. Each opening
    now ends in the white flash.
  - **The swirl checked frame by frame** from the reference pose (seen from in front): the open funnel's annulus unwrapped
    into angle and log radius, and the best shift found between frames a third of a second apart. Departure: **clockwise**
    (-3.5 degrees per third of a second) and **inward** (-0.03 in log radius). Arrival: **counter-clockwise** (+3.0) and
    **outward** (+0.015 to +0.03). Every pair matches at 0.6 to 0.78 while the funnel is open, as round 3 specified.

### M6-T20 Vortex detail by distance and mass arrivals

- **Goal:** AC13 (maintainer, 2026-11-12). Scenarios will open many jump points at once: the 1 000-ship battle brings its ships in
  through up to 100 points forming together, and that is how every ship enters the battle area. The vortex must stay cheap at a
  hundred instances and at a distance, without losing its look up close.
- **Detail by distance:** the vortex shader (T19's funnel and flash) drops detail layers as its screen size falls: the hair-like
  streaks first (finest width first), then the paler and darker patch layers and the noise octaves, down to a soft disc of the
  base colour with its rim and throat; levels blend over a band (no pop), chosen per instance from its projected radius in
  pixels, so a point 50 km off costs a few cheap fragments. The light per vortex is capped (the nearest few points carry one;
  the rest glow without a light), and the centre flash keeps its timing at every level.
- **Mass arrivals:** `JumpPointPool` holds and reuses up to 100 open points (shared mesh and material variants, no per-point
  allocation while the battle runs); the group rule (ships within 600 m in the first second share a point) stays. In
  `bench battle 1000` (and battle scenarios) every ship enters through a jump point, in waves, with no ship placed directly
  in the battle area; the arrival keeps the seeded outcome rules (the parity recordings use their own fixtures and are not
  changed by this).
- **The fps test:** the battle's GPU run on the maintainer's machine (Forward+, the real renderer) records fps, GPU frame time,
  draw calls and VRAM while 100 points form, beside the same battle with ships placed directly; the tick cost at
  `bench battle 1000` with the arrivals, from `scripts/bench_quick.sh`.
- **Files:** the vortex shaders (`assets/shaders/`), `src/props/jump_vortex.gd`, `src/props/jump_point_pool.gd`, the bench's
  battle layout and spawn path (`src/perf/bench_layout.gd`, `bench_runner.gd`), a pure LOD helper (`RefCounted`) and its tests.
- **Depends on:** T19 (the shader this thins; it is paused at the maintainer's word, so T20 waits for it) and T07 (which moves
  the battle layout's pull to data).
- **Tests:** the LOD helper (levels from projected size, the blend band): quick; the pool at 100 points (no allocation while
  open, reuse): quick if pure; the battle entering through points: standard; GPU files (`*_gpu.gd`): standard (Pending headless).
- **Done when:** AC13; screenshots of one vortex at each level and of 100 points forming in the battle for the maintainer (H).

### M6-T21 The rebase's per-node rest

- **Goal:** what T06 left of a position rebase and of an off-anchor tick (maintainer, 2026-11-12, option (c) after T06). T06
  measured the rest at `bench battle 1000`: the walk over the shiftable group (1 128 listed, 489 moved, about 0.6 ms), the
  1 000 rock bodies (0.25 ms, Godot-Jolt's own cost per body), the end-of-tick interpolation reset (0.27 ms), Jolt's next step
  (+0.33 ms) and the resolvers' rock grids (+0.2 ms); off the anchor the rocks cost about 0.28 ms per tick.
- **Steps:** keep only the rocks near a ship (or a bolt's sweep) as Jolt bodies, the rest as static rows alone, promoted and
  demoted with hysteresis as the tier does; keep a list of the shiftables in play (registered on spawn, dropped on park or
  free) instead of walking the group with the tier's parked ships in it.
- **Tests:** rams and hits against rocks unchanged (the existing ram and hit tests and the parity recordings); a rock promoted
  and demoted keeps its place; the rebase tests keep their tiers.
- **Done when:** the median rebase tick's extra and the off-anchor tick's extra at `bench battle 1000` measured before and
  after, both lower; nothing about a ram or a hit on a rock changes.

- **Done (2026-11-12):**
  - **Live rocks** (`src/world/rock_bodies.gd`, `native/src/rock_stream.rs`, `kernels::rock_stream`). Each rock keeps its RID
    body, but only the rocks a rigid hull could reach soon are live; the rest have layer and mask 0 and are never moved, so a
    rebase or a drift places only the live ones. Every tick, just before `sync_out`, the native `ScsRockStream` looks the
    core's rigid rows up in a dense grid of the rocks in their owner's frame (512 m cells, built once: no rebase or drift
    changes it). Each hull is seen from the owner and moves against the rocks at the World's rest velocity. A rock within
    0.25 s of motion plus 20 m comes to life; it is demoted once no hull has been within that reach plus 10 % (the tier's
    `HYSTERESIS`) for 30 ticks. The hold exists because a ship destroyed against a rock leaves the rows in that tick but stays
    in Jolt, and without it the destroyed fighter of `test_collision_layers` flew through. `AsteroidField` and `AsteroidBelt`
    both use it. A rock that comes back is placed under its owner by the same rule a live one follows (`placed`), to the bit.
    Why bodies stay in Jolt rather than leaving its space: no body is ever made again, so Jolt's body ids, by which it orders
    a tick's contacts, stay as they were. The battle's recording keeps its bits. Bolts never needed the bodies: the hit sweep,
    the rams and the scan read the rows. Cost: about 25 us a tick at `battle 1000`. A first try with the hit sweep's grid of
    levels cost 88 us, about 125 cells probed per hull at this reach. In this battle no rock is near a ship most of the time
    (332 hulls, 1 000 sparse rocks).
  - **The shiftables in play** (`src/world/shiftable_registry.gd`). Kept from the tree's `node_added` and `node_removed`, so no
    spawn site registers by hand. `ShiftableRegistry.set_out` parks a node out of it and brings it back: the pool's and the
    tier's parked ships (`ShipPool`, `Ship` and `CapitalStandin.park_for_tier`, `TierDirector.forget`) and, new, idle debris
    chunks and effect emitters (`DebrisChunk._park_state` and `launch`, `FxPool._release` and `burst`), which a rebase moved
    hidden until now (about 54 a rebase). A node that joins the group after entering the tree, or leaves it while staying in
    the tree, is caught before each walk by comparing the group's size with what is known, and the group is read once more.
    `Projectile` now joins in `_init`. The rebase and the velocity rebase walk the list (about 450 nodes against 1 130).
  - **The bench:** a `boost=` run now holds the automatic velocity rebase off. Since T08 turned it on in `main.tscn`, the
    frame boosted straight back onto its anchor, and T06's off-anchor run measured a riding frame (+0.07 ms).
  - **Numbers**, `bench battle 1000 20 warmup=3 seed=1` (headless, pinned 0-11, load 0.4 to 1.3; T09 and T19 shared the
    machine for the first round). The extras are each round's own: the rebase-tick median over that run's tick median, and
    the off-anchor median over the riding median.

    | run | riding median ms | rebase ticks: median, worst ms | rebase-tick extra ms | off-anchor median ms | off-anchor extra ms |
    |---|---|---|---|---|---|
    | before, `dcaea040`, round 1 | 5.74 | 7.73, 8.36 | +1.91 | 6.35 | +0.61 |
    | before, `dcaea040`, round 2 | 5.73 | 7.83, 10.64 | +2.05 | 6.34 | +0.61 |
    | HEAD baseline (`de2b535e`, T09 and T19 in), round 1 | 5.81 | 7.55, 8.15 | +1.76 | 6.36 | +0.55 |
    | HEAD baseline, round 2 | 5.75 | 7.62, 8.08 | +1.82 | 6.34 | +0.59 |
    | after, round 1 (first stream kernel) | 5.87 | 6.91, 7.59 | +1.05 | 6.15 | +0.28 |
    | after, round 2 | 5.87 | 7.17, 8.31 | +1.34 | 6.12 | +0.25 |
    | after, round 3 | 5.82 | 7.03, 7.60 | +1.18 | 6.12 | +0.30 |

    The rebase tick's extra drops from about 1.9 ms to 1.2 ms, and the off-anchor extra from about 0.59 ms to 0.28 ms. The
    rebase's own readout (`shift`, the rebase and its settle) drops from 1.2 to 0.64 ms. The riding median is about 0.06 ms
    above the HEAD baseline: the stream's 25 us, the rest inside the spread. `bench_quick.sh` battle (500, 1 000): HEAD tick
    median 4.53 and 5.76 ms, p99 6.12 and 7.80, worst rebase tick 5.79 and 7.53; after 4.63 and 5.79, p99 6.20 and 8.57 (a
    6 s run; the 20 s runs do not repeat it), worst rebase tick 5.34 and 6.80. Every budget held.
  - **Left:** the resolvers' kept rock grids are still built again on every rebase and every off-anchor tick (two native
    `keep` calls, about 45 us each). A ship spawned in the same tick right next to a dormant rock meets it one Jolt step
    late (the stream reads the rows of the tick's sync); the row-based ram still lands.
  - Tests. Rust 138 (new: the stream wants and keeps by reach and hysteresis, the hold, hulls in the owner's frame, against
    the rocks' motion and out of Jolt, columns out of step, the grid against a test of every pair). GUT, **quick** (both
    added to `tests/quick_suite.txt`): `test_rock_bodies.gd` (new, 4 tests, about 4 s): only the near rock lives and the
    rest have no layer; a rock demoted after the hold, left by a rebase, then promoted stands where its owner puts it, to
    the bit, as the control that lived along does; a ship flown into a dormant rock is stopped by it and the rock is never
    dormant while the ship is within 15 m of its face; off the anchor the live body follows the drift and the dormant one
    stays put. `test_shiftable_registry.gd` (new, 4 tests): listed on entering and dropped on leaving or freeing; parked by
    the pool or the tier out of the walk and back; a late joiner and a node leaving the group in the tree found by the
    count; a node outside the World never walked. Changed: `test_world_frame` parks through `set_out`; `test_standins`,
    `test_rocks_and_mines`, `test_asteroid_belt` and `test_velocity_rebase` read a dormant rock's place from `placed`;
    `test_collision_layers` checks a live and a dormant rock's layers. Quick tier 1 881 of 1 881 GUT, 138 Rust, 331
    Python. With `GUT_SLOW=1`: `test_weapon_rows_battle` (recorded [933, 420, 174, 151, 25, 1], now the same),
    `test_rebase_in_play` 9, `test_parity_fixture` 3, `test_flight_parity_fight` 1, `test_ship_pool` 21,
    `test_debris_pool` 12, `test_fx_pool` 24, `test_tier` 11, `test_tier_handover` 13, `test_ram_damage` 14,
    `test_hit_resolver` 17, `test_collision_layers` 15, `test_rocks_and_mines` 9, `test_standins` 20,
    `test_asteroid_belt` 4, `test_explosion` 12, `test_weapons` 48, `test_bench` 10, `test_main_scene` 14,
    `test_velocity_rebase` 10, `test_world_frame` 18, `test_sim_core`, `test_every_world_core`, `test_static_shift`
    pass (314 tests).

