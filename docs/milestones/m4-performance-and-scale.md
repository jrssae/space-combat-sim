# Milestone 4: Performance and Scale

> "Many ships at once." (`docs/roadmap.md`)

**Status:** resumed 2026-11-03 (Q14 to Q18): the research's phases 1 to 3 toward 500 ships in one battle. Planned as T07 to T26 on 2026-11-03 and revised the same day for Q20 to Q23 (the plan section below the T06 report; Q19 and Q21 add capital ships, turrets, missiles, mines, asteroids and a typical mission's load; Q20 sets the fullscreen render bar). Paused earlier the same day after the T06 report (45 ships; Q11 to Q13). Earlier: planned 2026-10-28 at the maintainer's request, inserted after M3; the later milestones moved up one (the mission
framework is now M5, Epsilon space M6, and so on to voiced dialog, M15). M4 starts when M3 is accepted and merged into `main`,
on branch `m4`, unless the maintainer pulls it forward.

Read `docs/architecture.md` first (§11 performance targets, §14.1 the large world, §15.3 the tick order, §16 the M3 AI) and
the M3 as-built notes on AC13, T05, T06 and T14 (`m3-ai-pilots-and-wingmen.md`): they hold every per-component cost measured so
far. Tasks are ordered; each is one PR-sized unit and names a recommended agent model.

## Goal

Find how many ships can fly at once while the game still performs well, then raise that number: **at least 100 ships (the
minimum), up to 500 (the target)**. The work is test-driven and aimed at the **ship AI and location tracking**: the contact scan
and perception, the AI's behaviours and avoidance, targeting and the radar, `UniversePos` conversions and the position rebase.
Rendering, splat budgets and LOD are not in scope (they are M3-T19's `LodSwitcher` and M3-T20's resident splat budget); their
cost is only recorded.

Ship counts in the setting (maintainer, 2026-11-02): The standard “full” squadron of starfuries is 12. 6 and 4 are very common patrol sizes. Solo, 2, or 3 ships are common for scout missions. Babylon 5 has 3 full squadrons in addition to the station itself with it’s defense system.

## Maintainer answers (2026-10-28)

| Q | Question | Answer |
|---|---|---|
| Q1 | How many ships | **At least 100** (minimum), **up to 500** (target) |
| Q2 | Where to look | The **ship AI** and **location tracking** |
| Q3 | Method | **Test first.** Measure, then write **three candidate improvements ranked by confidence of improvement**, implement the **first**, and run the cycle again |
| Q4 | When to stop | **After four cycles, report a summary to the maintainer.** If the game is still under 100 ships, **ask for guidance** before going on |
| Q5 | What "good game performance" means | Not given; the planner's default is the budget below. The maintainer may change the numbers before T01 or at any report |

## Maintainer answers (2026-11-02)

After cycle 1 the maintainer read the options in `docs/handoff-m4.md` section 7 and the native-code proposal, and decided:

| Q | Question | Answer |
|---|---|---|
| Q6 | Plan for cycles 2 to 4 | Cycle 2: the ram resolver's broad phase. Cycle 3: the AI think rate with nearest-k contacts. Cycle 4: native code (below). The release export template is measured once, in cycle 2 |
| Q7 | How cycles measure | With `scripts/bench_quick.sh` ("the shorter performance test"), plus single `bench` runs for the stage breakdown; not the full sweep |
| Q8 | Think rate | AI ships within about 2 km of the player think every tick; farther ones think at 20 Hz on staggered ticks and hold their last command between (their physics still runs every tick). A behaviour change, listed in the report |
| Q9 | Native code | Allowed (this answers the rule below). **Rust with godot-rust `gdext`** (pinned, `api-4-7`). Cycle 4 is native: first the toolchain, CI and seam (N0), then the contact scan's queries in native code behind `ContactScan` (N1); the GDScript grid is dropped. Seeded outcomes stay bit-identical where that is cheap (N1 must be); later ports may differ within a stated tolerance, with every test green, listed in the report. Worker threads are allowed inside the native code only, with tests that one thread and six give the same output |
| Q10 | How cycles test | Focused GUT runs on the code a task touches plus AC13's paired-budget file, and the quick check; then the push, and CI's full suite is the gate. `scripts/run_tests.sh` runs locally **once per milestone**, before it closes |
| Q11 | The T06 report (2026-11-03) | **Stop M4 here for now** at 45 ships (25 by the sweep, 50 in the release export). A research agent reviews every route to 500 ships, engine changes included, before more work is planned |
| Q12 | Which build sets the budget | The editor build, as so far; the release export is measured once per report |
| Q13 | The windowed frame | Add a windowed check: each future cycle also checks the windowed build holds 60 FPS at its ceiling (a short GPU run) |
| Q14 | After the research (`docs/research/scaling-to-500-ships.md`, 2026-11-03) | **Stay in Godot** and run its phases 1 to 3 inside M4 (its goal already reads at least 100, up to 500), in the most efficient order, parallel where tracks do not collide |
| Q15 | What 500 means | **500 ships in one battle, stretch goal 1000**, but not a small battle area: one battle spread over a large area with many engagements. Ships near the player at full fidelity; the far parts of the battle may run in a cheaper tier that still fights. A `battle` benchmark layout measures it |
| Q16 | Parity for ports past N1 (the brains) | A stated tolerance: over a seeded 30 s fight, hits within 10 %, behaviour mix within 5 points, no ship more than 50 m from its GDScript twin at 10 s; every test green; listed in the report |
| Q17 | Ships out of Jolt | Decide by measurement: Jolt stays through phase 1; phase 2 measures and proposes it only if Jolt binds, with the maintainer's sign-off (it changes D4) |
| Q18 | Parallel work | Detached git worktrees (no branch), the controller cherry-picks onto `m4`; a branch off `m4` only if that is truly helpful |
| Q19 | What a large battle holds (2026-11-03) | **Capital ships too**: cruisers, destroyers and carriers beside the fighters, each with several gun turrets, lasers, interceptors and missiles; carriers launch fighters; and non-AI objects (asteroids, planets, moons) that the scan, the broad phases, avoidance, line of fire and gravity must account for. None exist yet (roadmap M6, M12, M14): M4 builds no game feature for them, it makes the performance work entity-type-agnostic and measures against stand-ins with a stated, adjustable mix (the plan below, T07) |
| Q20 | The render bar (2026-11-03, the plan's question 1) | "for a huge battle, dropping to as low as 30 fps at 1080p in fullscreen on this machine is acceptable, but 60 fps is still the target. upscaling resolution is also an acceptable technique. windowed performance is less of a concern". So the render check is **fullscreen 1920x1080 on the maintainer's machine** (it replaces Q13's windowed form); at the headline battle the floor is 30 FPS and the target 60; resolution upscaling (Godot's 3D scaling, FSR) is allowed and is a task (T26); no tick-share rule |
| Q21 | The battle mix (question 2) | "the 1000 ship goal would be closer to 100-200 capitals, but that's a worst case scenario. the goal would be a game mission which is a playable version of the babylon 5 tv episode into the fire from season 4, episode 6. a grand battle between multiple sides facing off against each other. however, the vast majority of scenarios would be less than 10 capital ships and ~50 fighters, with all relevant weapons. in addition to missiles, there would be some cases with proximity mines". So three loads: a **`typical`** layout (under 10 capitals, about 50 fighters, every weapon) that holds 60 FPS comfortably; the **headline 500** as the grand multi-side battle with the capital share scaled from the stretch (15 %, about 75 capitals at 500); the **stretch 1 000** worst case with 100 to 200 capitals; and **proximity mines** as a stand-in entity kind |
| Q22 | Questions 3 to 6 | Accepted as recommended: stand-ins with box hulls and no assets, bench-only; the tier integrates far ships at 20 Hz with no Jolt body and promotion carries state over exactly; Q16's tolerance is for fighters, entities without a GDScript twin are pinned by their own tests plus a seeded outcome comparison (hits within 10 %); the gravity stand-in is a harness-only point source through `environment_accel` |
| Q23 | The 1 000 stretch (question 7) | Measured once at T25 (headless and fullscreen), reported, not a gate for closing M4 |
| Q24 | Splats against meshes (2026-11-03) | Add a direct render comparison (T27): the 500 battle with splat and with mesh ships, and a Babylon 5 station scene (an 8 km stand-in with a rotating central cylinder and a stationary top bar, 10 capitals, about 80 fighters, a nearby planet), splat and mesh variants. The maintainer weighs dropping splats if meshes carry the battles at the show's look |
| Q25 | The fullscreen check on 4K screens | A native 4K fullscreen window with the 3D rendered at 1 080 lines and upscaled, as T07 built it |
| Q26 | Running lights at distance (T28) | Point-sized past about 70 m and dimmed by the inverse square, no halo; at today's brightness they fade out past about 500 m, and that is accepted: far ships are found by radar and the HUD |
| Q27 | Do AI ships know where mines are (2026-11-03) | **Depends on faction**: a side knows its own mines and steers clear of them; enemy mines are hidden from it (no avoidance) until they go off. Asteroids are obstacles for everyone |

## The budget ("good game performance", Q5)

The physics runs at a fixed 60 Hz, so a frame has 16.7 ms. The budget is measured **headless on the development desktop**, on
the real main scene (`Main`) with the player flying, so the main thread's whole simulation is in it and the GPU's work is not:

- **Simulation tick:** median **≤ 8.0 ms** and p99 **≤ 12.0 ms** over the measured window. The tick is all of a physics frame's
  work: the AI drivers (-10), the console and `Main`, the rebase (0), ships and the flight model, the Jolt step, bolts, the hit and
  ram resolvers, targeting (100) and the late systems. About half the frame stays free for rendering and the rest of the main
  thread.
- **Rebase ticks:** none over **16.7 ms** (a rebase walks every ship's nodes; at 500 ships T14's per-ship cost adds up to
  about 12 ms).
- **Real time kept:** over the run the simulation falls behind the wall clock by under **1 %** (Godot runs at most
  `max_physics_steps_per_frame` ticks per frame, so a tick slower than 16.7 ms spirals).
- **Max N** for a layout is the largest ship count in the sweep where all three hold on **two runs of three**. The headline
  number is the lower of `furball` and `spread` (below); `transit` is recorded.
- **Once per report, on the GPU:** the windowed build at the headline max N, FPS, frame time, VRAM and GPU recorded by the
  agent on the maintainer's machine (`CLAUDE.md`, GPU work). Not a gate.

The development desktop swings by up to 2x over seconds whatever runs on it (`test_ai_think_time`'s notes), so every number is a
median of runs on the same seeds, and the pass-or-fail tests in the suite count work (contacts touched, nodes walked, pairs
tested) or compare costs in one process; they never assert absolute milliseconds.

## Benchmark layouts

Every layout is seeded and spawns from the pools (allies as `starfury_ally` LOD1, raiders as `raider_fighter`), half and half,
with the player at cruise along its nose (60 m/s, `RebaseFight`'s default), so rebases happen as they do in play:

- **`furball`**: all N ships inside 5 km of each other in one fight. Every ship sees every other one: the worst case for the
  scan and the behaviours (O(N^2) if nothing changes).
- **`spread`**: groups of 12 (6 against 6, the setting's full squadron; groups of 10 before the maintainer added the ship counts
  on 2026-11-02) 20 km apart, each its own fight. Most ships are out of each other's sensor range: the case where a spatial
  index or a think-rate rule should win.
- **`transit`**: wings of four (the setting's common patrol) cruising on routes, no fight. Tracking, perception and the rebase
  without combat.

- **`battle`** (T07, Q15, Q19 and Q21): the headline layout from phase 1 on, the grand multi-side battle in the mix
  `BattleMix.GRAND` states (the plan section, "What the battle is"). N counts fighters and capitals: `round(0.15 N)` capitals
  (carriers `floor(0.2 c)`, destroyers `round(c / 3)`, the rest cruisers, a quarter a side), the rest fighters. Fights of 24 on
  an 8 km lattice in a 60 by 60 by 20 km area (growing with the square root of N past 500), the player's fight first, 2.5 km
  ahead; in each fight the four sides (`earth_alliance`, `raiders`, `bench_c`, `bench_d`, every pair hostile through a session
  faction table) come in from their own directions, and each side's capitals sit 5 km behind its fights, cruising in at 30 m/s
  with their gun turrets (carrier 12, destroyer 10, cruiser 8) and 4 interceptors each. An asteroid slab of 1 000 rocks (20 by
  5 by 20 km) over the player's fight, a moon 400 km below pulling 0.03 m/s^2, and every carrier launching a fighter every 5 s.
  T12 adds the mix's missiles in flight (launched by the capitals at hostile fighters), two beam lasers per capital and the
  mine belts (1.5 km out from each fight, each side's toward its own direction).
- **`typical`** (T07, Q21): the usual mission's load, `BattleMix.TYPICAL`: at N 58, 50 fighters and 8 capitals (2 carriers, 3
  destroyers, 3 cruisers) on two sides in two fights of 25, 20 by 20 by 10 km, with the same rocks and moon. It must hold the
  budget and 60 FPS fullscreen with headroom.
- Every run of either prints its mix and writes it, and the per-entity counts (`entities`: fighters near and far of the
  player, capitals, turrets, interceptors, beams, missiles, mines, bolts, asteroids, launches, sides), beside the stages; the
  stand-ins' own cost is the `standins` stage inside `flight`. `rocks=<count>` overrides the asteroids (0 for none).
  `scripts/fullscreen_check.sh <layout> <n>` is the Q20 render check.

The sweep is N in {25, 50, 100, 150, 200, 300, 400, 500}: 5 s of warm-up, 30 s measured, three runs each. A layout's sweep stops
after two failing ship counts in a row. Pools are pre-warmed to N at load; the load time is recorded, not budgeted (load hitches
are M5's mission work).

## Rules

- **Behaviour stays.** An improvement that does not mean to change behaviour keeps every M1-M3 test green and, where the run is
  seeded, the same outcome. One that trades behaviour for speed (for example far ships thinking at a lower rate) states the
  cost, keeps every test green, keeps AC13's paired 13-ship budget, and is listed for the maintainer in the report.
- **Newtonian motion stays honest** (§15.16): every ship goes through the one `FlightModel` with forces every tick; the
  damping guard stays. An AI may think less often; its ship never skips physics.
- **No new dependency** without the maintainer: a native GDExtension, a threading change or anything that needs
  `docs/third-party.md` is a question for the report, not a cycle's pick. (Answered for native code on 2026-11-02, Q9.)
- Console and settings as everywhere (§6.4): the `perf` provider and `bench` command register with `DebugConsole`; new settings
  are `SettingsSchema` entries.
- GPU checks run on the maintainer's machine (`CLAUDE.md`); only judgements of how it looks or feels are (H).

## Acceptance criteria

| # | Criterion | Kind | Done |
|---|---|---|---|
| AC1 | Harness: `bench <layout> <n> [seconds]` on the console and `scripts/bench.sh` (the sweep) run the three layouts at any N headless on the real main scene and write `reports/perf/<label>/` (`summary.json`, `summary.md`); the `perf` provider shows the last tick's stages (`tick_us`, `ai_us`, `scan_us`, `physics_us`, `resolvers_us`, `targeting_us`, `rebase_us`, `ships`); the statistics (median, p99, the budget verdict, the max-N search) are unit-tested; `scripts/run_tests.sh` has a short smoke run (`furball`, 25 ships, 5 s) that checks the report is written, not its numbers | A | M4-T01, 2026-11-02 |
| AC2 | Baseline: before any change, the sweep's max N per layout and the stage breakdown at 50 and 100 ships are recorded below | A | M4-T01, 2026-11-02 (Cycle log, Baseline) |
| AC3 | Four cycles, each recorded below: the numbers before, three candidates ranked by confidence with the evidence for each, the first built **test first** (the failing test committed before the change), the numbers after, the gain against the prediction | A | M4-T02 to M4-T05, 2026-11-03 (Cycle log) |
| AC4 | No regressions: after each cycle the focused runs (the touched code and AC13's paired budget) are green locally and CI's full suite is green on the push (Q10); `scripts/run_tests.sh` green locally once, before M4 closes; every behaviour change listed | A | M4-T06m, 2026-11-03: full suite 2 257 of 2 259 passing, 0 failing, 2 pending (AC12); CI green on every cycle's push; behaviour changes in the T06 report |
| AC5 | Goal: the headline max N is at least 100, and toward 500. Not reached after cycle 4: the report says so and asks for guidance (T06) | A | **Not met**: headline 25 by the sweep, 45 with the below-sweep runs (release build: 50 in the quick check). T06 asks for guidance, 2026-11-03 |
| AC6 | Render check at the headline max N on the maintainer's GPU: FPS, frame time, VRAM, GPU and driver recorded (by the agent, 2026-11-01) | A | M4-T06m, 2026-11-03 (Cycle log, Final measurements) |

## Task breakdown (ordered)

Status: `done` (merged, its milestone accepted), `in progress`, `not started`, `not needed` (a conditional task whose trigger never arose). Update the column with each task's commit.

| Task | Title | Depends on | Agent | Why | Track | Status |
|---|---|---|---|---|---|---|
| T01 | Benchmark harness, budget and baseline | M3 | Opus | Measurement design on a noisy machine; touches the tick order | - | done |
| T02 | Cycle 1 | T01 | Opus | Profiling and a ranked judgement call | - | done |
| T03 | Cycle 2 | T02 | Opus | Same | - | done |
| T04 | Cycle 3 | T03 | Opus | Same | - | done |
| T05 | Cycle 4: native contact scan (Rust `gdext`, N0 then N1, Q9) | T04 | Opus or Fable | A new toolchain and bit-identical parity | - | done |
| T06 | Report to the maintainer | T05 | controller | A summary and a question, no code | - | done (waiting for the maintainer's answer) |
| T07 | The `battle` and `typical` layouts, the mix (`BattleMix`), capital, turret, asteroid and gravity stand-ins, per-entity counters, the fullscreen check script | T06 | Opus | The ruler every later task measures against; what the stand-ins cost needs judgement | A | done |
| T08 | Bolt broad phase in native code (`ScsHitSweep`), projectile kinds | T06 | Opus | Hits grow with bolts times ships; the windowed spikes | G, N | done |
| T09 | Native body registry: the scan built from RIDs, entity kinds, nearest-k per kind | T06 | Opus | The per-tick gather cycle 4 left; rocks must not fill a fighter's contacts | G, N | done |
| T10 | N4: the flight force step in native code for AI ships (`ScsFlightStep`) | T06 | Fable | The riskiest parity maths (`FlightModel`, the assist's state) | G, N | done (2026-11-03, in a worktree on `f134e00`; Cycle log, M4-T10) |
| T11 | Far-ship render proxies and the node diet for AI ships | T10 | Opus | 108 nodes and 27 draw calls a ship; GPU numbers by the agent, the look (H) | R | done (2026-11-03, in a worktree on `441a3b4`; Cycle log, M4-T11) |
| T12 | Missile, beam, interceptor and mine stand-ins | T07, T08 | Opus | The weapon kinds Q19 and Q21 name, measured | A, G | done (2026-11-03, in a worktree on `441a3b4`; Cycle log, M4-T12) |
| T13 | Phase 1 measurements and report P1 (checkpoint 1) | T11, T12, T14 | Sonnet | Measurement, no code | M | not started |
| T14 | Jolt collision layers; interpolation off for far ships | T11 | Sonnet | Mechanical; matters from 300 ships | G | not started |
| T15 | The native simulation core: entity rows, one call in and out (`ScsSimCore`) | T13 | Fable | Architecture: every native class moves onto it; serial | N | not started |
| T16 | N2: avoidance, the fire lane and the context lists on the core | T15 | Opus | Per-contact loops, bit for bit | N, G | not started |
| T17 | The brains in native code under Q16's tolerance (T17a maths, T17b behaviours) | T16 | Fable | 3 000 lines of seeded behaviour with a tolerance to meet | N, G | not started |
| T18 | N3: threads inside the core (rayon), 1-thread and 6-thread identical | T17 | Opus | Determinism rules, a new crate | N | not started |
| T19 | Jolt measured at 300 and 500, the ships-out-of-Jolt proposal (Q17, checkpoint 2) | T15 | Sonnet | Measurement and a proposal, no game code | M | not started |
| T20 | Turrets, missiles, beams and mines as native rows | T16, T12 | Opus | The non-fighter rows' budget (710 turrets at 500); M12 inherits the path | N, A | not started |
| T21 | The low-attention tier: state, 20 Hz integration, promotion and demotion of fighters and capitals | T20, checkpoint 3 | Fable | The pool and ship adapter handover must never pop; serial | T | not started |
| T22 | Tier brains at 2 to 5 Hz, statistical fire, far capitals' aggregated fire | T21 | Opus | Far fights must stay fair | T, N | not started |
| T23 | Far proxies for tier rows (dots, radar, targeting) | T21, T11 | Opus | GPU numbers by the agent, the look (H) | R | not started |
| T24 | The simulation step on a worker thread (only if the fullscreen check misses the floor at 500; checkpoint 4) | T23, T26 | Fable | A tick-order change, double-buffered snapshots | N | not started |
| T25 | Phase 3 measurements, the 1 000 stretch, the full suite, report P3 | T23 (T24, T26) | Sonnet | Measurement, no code | M | not started |
| T26 | Resolution scaling for the big battle (only if the GPU binds at the fullscreen check; Q20) | T11 | Sonnet | One setting and an automatic step on `RenderScale`; the look (H) | R | not started |
| T27 | Render comparison: Gaussian splats against meshes, in the 500 battle and a Babylon 5 station scene (Q24) | T07, T11, T12 | Opus | Measures whether splats or meshes carry the big battles; GPU numbers by the agent, the look (H) | R, M | not started |
| T28 | Running lights stay point-sized and dim by the inverse square (maintainer, 2026-11-03) | none | Sonnet | Lights in vacuum do not scatter into globes | R | done |
| T29 | Rocks and mines as static rows: T07's asteroids registered as statics, T12's mines as faction-owned mine rows; avoidance sees rocks and its own side's mines only (Q27) | T09, T12 | Opus | Takes the rocks' 24 to 49 ms per tick out of the GDScript paths | G, N | not started |

### M4-T01 Benchmark harness, budget and baseline

- **Goal:** AC1 and AC2.
- **Files:** `src/perf/` (new: a pure `PerfStats` for median, p99 and the verdict; a `PerfProbe` node that times the stages
  through the timers that exist, `AiPilotDriver.think_us`, the resolvers' and `WorldFrame.last_rebase_us`, plus
  `Performance.TIME_PHYSICS_PROCESS`, and adds what is missing), `src/game/main.gd` (the `bench` command and layouts; spawns from
  the pools), `scripts/bench.sh`, `scripts/run_tests.sh` (the smoke run), `tests/unit/test_perf_stats.gd`,
  `tests/integration/test_bench.gd`.
- **Notes:** a stage timer must cost far less than the stage (check with the probe off and on at 100 ships). The probe's own
  sampler runs last in the tick, like `test_ai_think_time`'s. Record the machine (CPU, Godot build) in every summary.
- **Done when:** AC1; the baseline sweep is recorded under "Cycle log" with the stage breakdown at 50 and 100 ships.
- **Done (as built, 2026-11-02):** `src/perf/` holds `PerfStats` and `BenchLayout` (pure, `test_perf_stats`, `test_bench_layout`),
  `PerfProbe` (provider `perf`, command `perf [on|off]`), `BenchRunner` (command `bench`) and `BenchReport`; `scripts/bench.sh`
  runs the sweep and `scripts/bench_sweep.gd` summarises it; `test_bench` and a `run_tests.sh` smoke run cover the harness on
  the real main scene. Design in `docs/architecture.md` §17.1. Where it differs from the plan above:
  - The `bench` command lives in `BenchRunner`, a child `Main` creates (with the probe), not in `main.gd`, which only gained
    `ensure_pool` (grow a pool, with sound, at the run's load) and the wiring.
  - `Performance.TIME_PHYSICS_PROCESS` is the worst physics step of each second, not a per-tick number, so it cannot give a
    median. The probe times the tick itself: `SceneTree.physics_frame`, marker nodes between the systems' priorities, its
    sampler last in the tick, and the next frame's start (the end of Jolt's step). The engine's number is kept as a check on that
    window (see the baseline).
  - The body sync (Jolt's bodies written back to their nodes, before the scripts) can only be timed when the engine does not
    sleep between frames, so a headless run sets `OS.low_processor_usage_mode_sleep_usec` to 0 for its duration (`sleep=keep`
    leaves it; the baseline measures the difference). When ticks run back to back the sync is a lower bound, and every summary
    gives the share of ticks in which it was timed.
  - Windows are counted in ticks (300 of warm-up, 1 800 measured), so every run has the same number of samples; real time kept
    is their sim time against the wall time they took. A run under a tenth of real time is cut short and fails.
  - The rebase threshold is lowered to 180 m for the run: at the player's 60 m/s that is a rebase every 3 s (ten per window,
    enough to see their cost) while rebase ticks stay under 1 % of the ticks and so do not decide the p99 on their own. The
    rebase budget is checked on the whole tick that held a rebase; the shift's own cost is recorded beside it.
  - Bench ships are invulnerable and god mode is on, so N holds for the whole window (no deaths, explosions or respawns);
    `transit` makes the two sides neutral for the run, which is its "no fight".
  - The machine is a hybrid i5-13600KF (performance cores 0-11 at 5.1 GHz, efficiency cores at 3.9 GHz), so `bench.sh` pins
    every run to cores 0-11 (`BENCH_CPUS`); the allowed cores and the Godot binary (the official 4.7.2 editor build, debug) are
    in every summary. N counts the layout's ships; the player flies too.
  - A run that dies without a report leaves a failing placeholder summary, so the sweep counts it as a failed run against the
    runs it asked for (one surviving pass cannot pass a count).
  - Review round 1 (2026-11-02) fixed the rebase budget (it had checked the shift alone), missing runs, and split the resolvers
    into hit and ram; the baseline below was taken again on the fixed harness (`935ae1a`).

### M4-T02 to M4-T05 Cycles 1-4

Each cycle is one task, committed directly on `m4` (no task branches, maintainer 2026-11-02), with its focused runs green, a push and CI green before the next starts (Q10):

1. **Measure.** Run the sweep on the branch's base (from cycle 2, the quick check and single `bench` runs, Q7). Profile the worst layout at the largest passing N and at the first failing
   one: which stage grows, and how fast with N.
2. **Rank.** Write three candidate improvements in the cycle log, ranked by confidence that they improve the headline max N,
   each with its evidence (the measured stage and its growth), the expected gain and the behaviour risk. The previous cycle's
   unbuilt candidates are ranked again with the new numbers, not carried over unexamined.
3. **Test first.** Commit a failing test that pins the improvement: a work count (for example contacts touched per tick in
   `spread`, or nodes walked per rebase) or a cost compared in one process, plus behaviour tests for anything it may change.
4. **Build** candidate 1 until the test passes and the focused runs are green (the full suite runs once per milestone, Q10).
5. **Measure again.** The sweep after (from cycle 2, the quick check, Q7); record the gain against the prediction. A candidate that gains nothing is reverted, says
   why, and the cycle still counts.

While iterating, `scripts/bench_quick.sh` (under 10 minutes: furball and spread ramped from 10 ships until they fall under
30 FPS, one short run per count) shows whether a change moves the ceiling; the numbers recorded in the log come from the sweep.

- **Done when:** the cycle's entry in the log is complete and the merge is green and pushed.
- **Done (T02, cycle 1, 2026-11-02):** only the player's targeting keeps a candidate list (`TargetingController.keeps_candidates`,
  `docs/architecture.md` §17.2); headline max N 0 to 25, the ceiling below the sweep 20 to 30 ships. Entry in the Cycle log.
- **Done (T03, cycle 2, 2026-11-02):** the ram resolver looks only at pairs `RamBroadPhase` finds near each other and pairs Jolt
  holds in contact (`docs/architecture.md` §17.3); rams at 100 ships 10.2 to 0.7 ms, the quick check's ceiling stays 30 in
  furball and spread (35 ships now 0.1 to 0.2 ms over). Measured with the quick check and single runs, not the sweep. Entry in
  the Cycle log.
- **Done (T04, cycle 3, 2026-11-02):** AI ships beyond 2 km of the player (all of them with no player alive) think at 20 Hz on
  staggered ticks and hold their last command between, and every AI ship weighs its nearest 12 contacts plus the nearest hostile
  ship and what it keeps (`docs/architecture.md` §17.4); the AI at 100 ships 18.2 to 7.0 ms in the furball, 11.6 to 6.1 ms in
  spread, the quick check's ceiling 30 to 40 in both. A behaviour change, listed in the Cycle log with the outcome comparison.
  Measured with the quick check and single runs, not the sweep.
- **Done (T05, cycle 4, 2026-11-03):** N0 (T05a) put the Rust toolchain, the CI build and the `NativeLib` seam in place; N1
  (T05b) moved the contact scan's queries into the native `ScsContactField` behind `ContactScan`'s unchanged interface, bit for
  bit (`docs/architecture.md` §17.5). The scan at 100 ships 3.91 to 2.40 ms in the furball and 3.12 to 2.66 ms in spread; the
  quick check's ceiling stays 40 in both, and in this run 30 FPS held to 150 ships (the before's run failed at 150, at a
  lower load: 0.48 against 0.95 to 1.64). Seeded outcomes are identical with `perf_native` on and off. Entry in the Cycle log.

Starting hypotheses from the M3 measurements, for T02 to test, not to follow:

- `ContactScan.contacts_for` copies a faction list per ship (about 110 us per tick at 13 ships); with everyone in range that is
  O(N) per ship and O(N^2) per tick, and the behaviours then score every contact.
- No spatial index: the 5 km query walks every body. A grid or sorted sweep should win `spread` and `transit`, not `furball`.
- Think rate: every AI ship thinks every tick. Ships far from the player or with nothing near could think at 15-30 Hz on staggered
  ticks and hold their last command (their physics still runs every tick).
- Nearest-k: a ship scores, avoids and checks its fire lane against its nearest k contacts, not all of them.
- `incoming_fire` and the hit resolver test bolts against ships without a broad phase.
- Rebase: about 17 us per ship to reset and 7-10 us to shift (a Starfury is 108 nodes); fewer nodes per ship or resetting only
  the interpolated roots.
- Allocation: a `Contact` per pair per tick and a `UniversePos` per conversion.
- Jolt: body count and ship-against-ship contact pairs (collision layers).

### M4-T06 Report to the maintainer

After cycle 4, the controller writes the summary: the headline max N and each layout's before and after, the stage costs at
100 and at the max, what each cycle built and gained, the behaviour changes, and the remaining candidates ranked. **If the
headline max N is under 100, the report asks the maintainer for guidance and M4 stops there.** At 100 or more it asks whether to
run more cycles toward 500 or to close M4.

#### Report (2026-11-03)

**Where M4 ended.** The headline max N went from **0 to 25** by the milestone's sweep, and to **45** counting the runs below the
sweep's 50-ship step (the furball passes 45 on two runs of three; spread passes 50 and transit 50). The release export holds **50**
in both headline layouts in the quick check. AC5's minimum is 100, so it is **not met**, and M4 stops here for guidance.

| | baseline | cycle 1 | cycle 2 | cycle 3 | cycle 4 (final) |
|---|---|---|---|---|---|
| sweep max N (furball, spread, transit) | 0, 0, 0 | 25, 25, 25 | | | 25, 50, 50 |
| real ceiling below the sweep (furball) | 20 | 30 | 30 | 40 | 45 |
| quick check (furball, spread) | | 30, 30 | 30, 30 | 40, 40 | 40, 40 (release export: 50, 50) |
| furball tick median at 50 ships | 28.99 ms | 13.03 | 12.19 | 8.23 | 8.39 |
| furball tick median at 100 ships | 109.07 ms | 34.57 | 30.48 | 17.06 | 15.22 |

The tick medians come from each cycle's own runs (sweeps for the baseline and cycle 1, the quick check for cycle 2, 10 s stage runs
for cycle 3, the final 30 s stage runs for cycle 4), so they compare roughly, not to the tenth of a millisecond.

**What each cycle built** (all four test first, all green on CI):

| cycle | change | stage it hit, furball 100 ships | behaviour |
|---|---|---|---|
| 1 (T02) | only the player's targeting keeps a per-tick candidate list | targeting 74.0 to 1.0 ms | one in-tick edge (selecting by id a target that left reach since the last refresh) |
| 2 (T03) | broad phase for the ram resolver | rams 10.2 to 0.7 ms | none (seeded runs identical) |
| 3 (T04) | AI think rate (near the player every tick, far at 20 Hz staggered, Q8) and nearest-12 contacts | AI 17.6 to 6.95 ms | **far ships react up to 50 ms later; hits fall about 13 % at 100 ships (15 to 21 % with every ship far); far contacts beyond the nearest 12 are ignored when choosing (the nearest hostile, target, wing and recent attacker are always kept)** |
| 4 (T05) | Rust toolchain and native seam (N0), the contact scan's queries in native code (N1) | scan 3.9 to 2.4 ms | none (bit-identical with `perf_native` on and off) |

Also measured or fixed along the way: the release export runs GDScript 1.2 to 1.3 times faster than the editor build; a CI-only
test flake (the dogfight test's time scale) fixed; the native field hardened against huge ranges and malformed input; the asset
generator rejects non-finite values (the maintainer's code review).

**Where the time goes now** (furball, 100 ships, tick mean 16.0 ms against 109.5 at the baseline): AI 6.2 ms (scan 2.6), flight
3.6, the hit resolver 2.5, physics (Jolt and sync) 1.9, targeting 1.0, rams 0.7. Every stage now grows about linearly; reaching
100 ships needs the tick halved.

**A finding the headless budget hides.** On the GPU (AC6, RX 6950 XT) the headline's 25 ships run at 120 FPS unconstrained and 60
on vsync, but at 45 ships, which pass the 8 ms headless budget, the windowed game falls to 52 FPS: the tick plus the renderer's
own CPU work and the rest of the frame no longer fit 16.7 ms. The hit resolver also spikes to 7.5 to 8.5 ms every few seconds in
the window (not investigated). The budget's "half the frame for rendering" holds to about 25 to 40 ships.

**Remaining candidates, ranked by confidence that they raise the headline:**

| # | candidate | evidence (furball 100) | expected | confidence |
|---|---|---|---|---|
| 1 | AI perception and brain work across worker threads inside the native code (N3; allowed by Q9), with 1-thread and 6-thread outputs identical | AI 6.2 ms, the largest stage; six performance cores idle | AI 6.2 to about 1.5 to 2 ms | medium-high, 70 % |
| 2 | Bolt broad phase for the hit resolver (and `incoming_fire`), which may also explain the windowed spikes | hits 2.5 ms, bolts times ships | 2.5 to about 0.5 ms; spikes likely gone | high, 75 % |
| 3 | The flight model's per-tick maths in native code (N4) | flight 3.6 ms, linear | 3.6 to about 1 ms | medium, 60 % |
| 4 | A cheaper per-tick gather for the scan (cache the broadcast scan, skip the freed-body check) | scan remainder about 2.4 ms is GDScript gather | about 1 ms | medium, 60 % |
| 5 | Jolt collision layers (ships do not pair-test ships) | physics 1.9 ms | under 1 ms; matters at 300 and up | low now, 30 % |
| 6 | Broadcast and incoming-fire broad phase in the native field (code review P2) | 0.12 and 0.14 ms | about 0.1 ms; matters toward 500 | low now |

Candidates 1 to 4 together (about 9 ms off 16) would put 100 ships near the 8 ms tick, headless and in the debug build. 500 needs
those and physics work, and a budget conversation (Jolt alone is about 8.5 ms at 500).

**The question for the maintainer:**

1. Continue M4 toward 100 with more cycles (candidates 1 to 4 in that order), or close M4 at 45 (debug) and 50 (release)?
2. Which build sets the budget from here: the editor build (as so far) or the release export players run?
3. Should the budget also cover the windowed frame (the 45-ship finding), for example a render check at each cycle's ceiling?

### M4 phases 1 to 3, T07 to T26: the plan (2026-11-03, revised the same day for Q20 to Q23)

Planned on `439f4f0` from `docs/research/scaling-to-500-ships.md` (sections 1, 2 and 5), the maintainer's answers Q12 to Q23 and
the final measurements above. Nothing below was built or measured. Every gain is an estimate with a confidence; the tick costs it
starts from are the furball at 100 ships on the debug editor build (tick 16.0 ms: AI 6.2, of which the scan is 2.6 and the brains
about 3.4; flight 3.6; hits 2.5; Jolt and the sync 1.9; targeting 1.0; rams 0.7).

#### What the battle is (Q15, Q19 and Q21)

Q19 and Q21 change what "500 ships" costs. The load is not 500 fighters: it is fighters, capital ships whose turrets each aim and
fire, beam lasers, interceptor defences, guided missiles, proximity mines, carriers launching fighters, an asteroid field and a
nearby moon's gravity, and in the grand battle several sides at once. None of those exist in the game yet (capital ships, turrets,
missiles and mines are roadmap M12, asteroid fields M14, planets and gravity M6), so M4 does not build them. It makes the
performance work ready for them (a native core whose rows carry an entity kind and a size, broad phases that take a 1 km hull
beside a 10 m fighter, a projectile system whose rows can be a bolt, a beam or a guided missile, triggers for mines) and measures
against **stand-ins** that put the real load on the tick without the real features. The stand-ins live under `src/perf/standins/`,
are built by code with no assets (box hulls, sphere rocks and mines, no splats), are bench-only (spawned by the layouts below,
never by a scenario) and are replaced by the roadmap's real work:

| stand-in (M4) | what it costs the tick | replaced by |
|---|---|---|
| `CapitalStandin`: a `RigidBody3D` with a `Damageable` and `Targetable`, a box hull 300 m (cruiser), 600 m (destroyer) or 1 200 m (carrier) long, cruising at 30 m/s on a fixed heading, hull points only | a large body in Jolt, the scan and every broad phase | M12's capital ships (generated hulls, subsystems, damage model) |
| `TurretStandin`: a child of a capital that picks the nearest hostile fighter within 4 km from the contact scan, turns a gun axis at a limited rate and fires `PulseCannon` bolts through the fire gate; `interceptor` variant: targets missiles and bolts within 1.5 km and removes the nearest one at its rate (no bolt of its own) | an aiming and firing agent per turret; interceptors query bolts and missiles | M12's turrets, AI gunners and defence grid |
| `BeamStandin`: a hitscan shot along a segment of 3 km, resolved by the hit sweep in the tick it fires, at 0.5 Hz per emitter | a long thin sweep per shot, no entity in flight | M12's lasers |
| `MissileStandin`: a projectile row with a target, a turn rate and a lifetime, steered by proportional navigation in native code from phase 2 (GDScript before), launched by capitals at fighters | a guided agent in flight, swept like a bolt with a larger radius | M12's missiles |
| `MineStandin` (Q21): a static row of kind `mine` with a trigger radius (50 m) and a blast radius (100 m), laid in belts between the sides; every third tick it asks the grid for a hostile inside the trigger and detonates on one (damage to every hull in the blast, the row removed); hundreds per battle | a static row queried on a cadence, a burst of damage, a removal | M12's weapons work (mines are not on the roadmap yet; the maintainer places them) |
| `AsteroidField`: one `MultiMeshInstance3D` and static sphere shapes created through `PhysicsServer3D` by RID (no node per rock), kind `static` in the scan, `hit_by_anyone` | static rows in the grid (built once, never moved except by a rebase), avoidance, line-of-fire and occlusion checks, Jolt's static set | M14's asteroid fields (generated rocks, LOD, mining) |
| `GravityStandin`: the harness installs a point source in `WorldFrame.environment_accel` (a moon at 400 km, up to 0.03 m/s² over the area; no body, no visual) | one acceleration per body per tick, the drift it adds to every intercept | M6's Kepler bodies, the scaled-space renderer and true gravity |
| carrier launches: every 5 s a carrier releases one fighter of its side to the pool and takes it again at its bay (N holds) | a pool release and acquire in play (the launch hitch) | M12's launch tubes and M5's spawning |
| sides: the grand battle has four factions (`earth_alliance`, `raiders` and two bench factions), every pair hostile, installed by the runner as a session faction table and put back after the run (`data/factions.json` lists three ids today; `FactionTable` treats an unlisted id as neutral) | hostility rows per faction in the field, more hostile pairs per contact | M12's factions and relations data |

**Three loads** (Q21), each a layout with its own `BattleMix` profile (pure, in `src/perf/battle_mix.gd`, read by the layouts and
printed in every summary). The profile fixes the capital share, the per-class turret, beam and interceptor counts, the missiles
and mines held in flight or laid per fighter, the sides, and the field; N is the ship count (fighters plus capitals):

| | `typical` (most missions) | `battle` (the headline: the grand multi-side battle) | `battle` at the 1 000 stretch |
|---|---|---|---|
| ships N (default) | 58: 50 fighters and 8 capitals | 500: 425 fighters and 75 capitals | 1 000: 850 fighters and 150 capitals |
| capital share | 1 in 7 (8 at N 58; under 10 as Q21 says) | 15 % (`round(0.15 N)`; 15 at N 100, 45 at 300), scaled from the stretch's 100 to 200 at 1 000 | 15 %: 150 (the worst case's lower edge; the profile takes 20 % as a parameter for the upper) |
| capital classes | 2 carriers, 3 destroyers, 3 cruisers | 15 carriers, 25 destroyers, 35 cruisers (1:2:3 by tenths, carriers rounded down) | 30, 50, 70 |
| turrets (carrier 12, destroyer 10, cruiser 8) | 78 | about 710 (142 at N 100, 430 at 300) | about 1 420 |
| beam emitters (2 per capital) | 16 | 150 | 300 |
| interceptors (4 per capital) | 32 | 300 | 600 |
| missiles in flight | 20 (0.4 per fighter) | about 170 (0.4 per fighter; 35 at N 100) | about 340 |
| mines laid | 100 | 500 (1 per fighter, at least 100) | 1 000 |
| bolts in flight (emergent: 3 per fighter as measured, about 2 per turret) | about 300 | about 2 700 | about 5 400 |
| asteroids | 1 000 rocks of 20 to 200 m in a slab 20 by 20 by 5 km over a third of the fights | the same | the same |
| gravity | one point source | one | one |
| sides | 2 | 4, every pair hostile | 4 |
| area | 20 by 20 by 10 km, two fights of 24 and the capitals 5 km behind each side | 60 by 60 by 20 km, fights of 24 on an 8 km lattice, a side's capitals 5 km behind its fights, the player's fight at the centre | 85 by 85 by 20 km |
| what it must hold | 60 FPS fullscreen with headroom and the 8 ms tick with headroom: tick median 4 ms or under, frame mean 12 ms or under (recommended reading of "comfortably") | the 8 ms headless budget; fullscreen 60 FPS the target, 30 FPS the floor (Q20) | measured at T25, not a gate (Q23) |

`battle` is the headline layout from T07 on and `typical` is the second gate; `furball` stays the worst case for one fight, and
`spread` and `transit` are recorded. Max N for `battle` counts ships; the summary prints every entity count beside it.

**Budget per entity type**, the target at `battle` 500 inside the 8 ms headless budget, with the native core (phase 2), the tier
(phase 3, which holds far capitals and their turrets as well as far fighters) and the AI threaded. The near set is what lies within
`tier_radius_m` (10 km) of the player: on the 8 km lattice that is the player's fight and its neighbours, about 150 fighters and
about 20 capitals with their 190 turrets and 80 interceptors. Estimates; each row has its own counter in the `perf` provider from
T07 so the plan is checked per row, not per ship:

| entity | count | target us each per tick | ms | where the cost goes |
|---|---|---|---|---|
| fighter near the player, full fidelity | 150 | 8 | 1.2 | brain 3 to 5 (native, 60 Hz), flight 1.5, scan 1, bolts and hits 1, sync 1 |
| fighter in the tier | 275 | 0.3 | 0.08 | native integration at 20 Hz, a brain at 2 to 5 Hz, statistical fire |
| capital near | 20 | 5 | 0.1 | a big body in Jolt and the grid, no brain |
| capital in the tier, its turrets as one aggregated fire roll per group | 55 | 2 | 0.11 | a row integrated at 20 Hz, one roll per turret group per second |
| turret near | 190 | 2 | 0.38 | a nearest-hostile query against the grid, an aim step, a fire gate |
| interceptor near | 80 | 3 | 0.24 | a query over bolts and missiles in 1.5 km |
| beam shot near | 40 emitters at 0.5 Hz | 1 per shot | 0.02 | one long segment through the hit sweep |
| missile near | 80 | 3 | 0.24 | guidance, a grid insert, a sweep; far launches resolve statistically |
| bolt near | about 1 100 | 0.3 | 0.33 | move, a grid insert, the sweep's candidate pairs |
| mine | 500 | 0.2 | 0.1 | one grid query every third tick |
| asteroid | 1 000 | 0.02 | 0.02 | static rows, queried not updated; avoidance against the nearest statics is counted in the fighters |
| Jolt step and body sync (about 160 fighters, 20 capitals, 1 000 statics) | | | 1.3 | Jolt's own threaded step, the per-node sync of the near ships |
| rebase, console, waves, HUD-side bookkeeping | | | 0.5 | |
| **tick** | | | **about 4.6** | |

Confidence 55 % that `battle` at 500 lands under 8 ms headless with all three phases built, 35 % under 5 ms. The rows that
decide it are the near fighters (the brain port, T17), Jolt with the sync (Q17's measurement, T19) and the near turrets (T20).
At the 1 000 stretch the near set is the same and the tier carries 700 fighters and 130 capitals (about 0.5 ms more): under 8 ms
headless 35 %.

**The render bar** (Q20): the check is fullscreen at 1920x1080 on the maintainer's machine, not windowed. At the battle's
headline the target is 60 FPS and the floor 30 FPS; `typical` must hold 60 FPS with headroom. Resolution upscaling (Godot's 3D
scaling with FSR, which `RenderScale` already drives for the tile budget) is an allowed technique and is T26 when the GPU binds.
No rule ties the tick to a share of the frame; the headless 8 ms budget stays the gate for max N, and at the 30 FPS floor a frame
holds two ticks, so a 10 ms tick still fits. Confidence at `battle` 500 fullscreen: 60 % for the 30 FPS floor, 40 % for 60 FPS
(with T24 and T26 if they are needed); at 1 000: 30 % and 15 %.

**Revised phase targets** (the research's, with Q19 and Q21's load):

| phase | target headless (editor build) | fullscreen check (Q20) | confidence (research's) |
|---|---|---|---|
| 1 (T07 to T14) | `typical` under 8 ms; the furball at 100 under 8 ms; `battle` 100 (15 capitals, 142 turrets in GDScript) under 8 ms | `typical` at 60 FPS; `battle` 100 at 60 FPS with far proxies and the node diet | typical 65 %, furball 65 %, battle 100 50 % (70 %) |
| 2 (T15 to T20) | `typical` under 4 ms; `battle` 300 (45 capitals, 430 turrets, 100 missiles, 300 mines) under 8 ms | `typical` at 60 FPS with headroom; `battle` 300 at the 30 FPS floor | typical 85 %, battle 300 45 % (55 %) |
| 3 (T21 to T26) | `battle` 500 in the world, 100 to 150 fighters and about 20 capitals near, the full mix, under 8 ms | `battle` 500 at the 30 FPS floor, 60 FPS the target | 55 % under 8 ms; 60 % floor, 40 % target (75 %); 1 000: 35 %, 30 %, 15 % |

Why lower than the research's: the grand battle's 75 capitals carry 710 turrets, each an aiming and firing agent, and 300
interceptors querying bolts and missiles; missiles are guided agents that cannot be held like a far fighter's command; mines query
the grid; the asteroid field adds occlusion and avoidance to every near think; and four sides give every contact more hostile
pairs. What would make 500 fit if a phase misses: the simulation step on a worker thread (T24), ships out of Jolt (T19, the
maintainer's call), resolution scaling for the frame (T26), a smaller near radius (fewer full-fidelity rows), far capitals' fire
aggregated per capital rather than per turret group. What would make 1 000 fit: all of those, and the tier carrying 85 % of the
rows at 0.3 us each.

**Re-ranking the T06 candidates against cycle 4's finding.** The T06 report put threads inside the native perception first
(70 %). Cycle 4 then found the native queries are about 0.2 ms of the 2.4 ms scan at 100 ships: the rest is the per-tick gather
in GDScript and the brains. Threads over 0.2 ms gain nothing, so threads move to phase 2 (T18), after the brains are native and
there is work to divide. Phase 1 takes the bolt broad phase (T08), the native flight step (T10) and a native body registry that
ends the per-tick gather (T09) instead.

#### The tracks and the shared files

| track | what | files it owns |
|---|---|---|
| A, harness | the `battle` and `typical` layouts, the mix, the stand-ins, per-entity counters, the fullscreen check script | `src/perf/battle_mix.gd`, `src/perf/bench_layout.gd`, `src/perf/bench_runner.gd`, `src/perf/perf_probe.gd`, `src/perf/standins/`, `scripts/bench_quick.sh`, `scripts/bench.sh`, `scripts/bench_sweep.gd`, `scripts/fullscreen_check.sh`, `tests/unit/test_battle_mix.gd`, `tests/integration/test_standins.gd` |
| N, native | the Rust crate: one file per native class, the sim core | `native/src/<class>.rs` (one per task), `src/perf/native_*.gd` facades named per task |
| G, gameplay seams | the GDScript side of each port: resolvers, projectiles, the ship adapter, the scan | named per task |
| R, render | far proxies, the node diet, the LOD switcher, resolution scaling | `src/ship/ship.gd` (T11 only), `src/ship/thruster_visuals.gd`, `src/ship/running_lights.gd`, `src/ship/nav_lights.gd`, `src/rendering/lod_switcher.gd`, `src/rendering/render_scale.gd` (T26), `src/game/ship_pool.gd` |
| T, tier | the low-attention tier | `native/src/tier.rs`, `src/ai/tier_director.gd`, `src/game/ship_pool.gd` (T21 only) |
| M, measurement | sweeps, headlines, the fullscreen check, reports | the Cycle log entries, `reports/` (not committed) |

Rules for files two tasks might touch, so that tasks in one wave never edit the same file:

- `native/src/lib.rs`: a task adds only its own `mod <file>;` line; the controller resolves the one-line conflict at the
  cherry-pick. Nothing else in the file.
- `native/Cargo.toml` and `Cargo.lock`: only T18 (rayon) edits them, with its `docs/third-party.md` rows in the same commit.
- `src/autoload/settings_schema.gd`: a task appends its own entries under a comment with its task id, nothing else.
- `info.md`: a task adds rows for its own commands under its own heading, nothing else.
- `docs/architecture.md`: a task appends only the §17 subsection this plan assigns it (below); nobody reflows another's.
- `docs/milestones/m4-performance-and-scale.md`: a task edits its own section, its own Cycle log entry (headed with its task id)
  and its own status row.
- `src/ship/ship.gd`: T10 in wave 1, T11 in wave 2, T14 in wave 3, T21 in wave 7; never two in one wave.
- `src/combat/hit_resolver.gd` and `src/weapons/projectile.gd`: T08 in wave 1, T12 in wave 2.
- `src/ai/contact_scan.gd`, `native/src/contact_field.rs`: T09 in wave 1, T15 in wave 4.
- `src/targeting/targetable.gd`: T07 adds `kind`; nobody else.
- `src/game/main.gd`: T07 only (the stand-in spawning hook); later tasks reach `Main` through what T07 adds.
- `src/rendering/render_scale.gd`: T26 only.
- A worktree task that needs a file another wave-mate owns writes what it needs in its report and the controller adds it.

Every task: test first (the failing test committed before the change), no milliseconds in assertions, commit subjects start with
the task id, focused GUT runs plus the quick check before the last commit (Q10), the report in
`.superpowers/sdd/m4-performance-and-scale/task-<id>-report.md`, benchmarks under both locks (`rules.md`). A worktree is
prepared by the controller: `.tools`, `assets/generated` and `reports` linked from the main checkout, `bin/libscs_native.so`
built for the worktree (cargo serialises on the shared target directory), one import.

#### Measuring a wave

Each task measures its own before and after in its worktree with `scripts/bench_quick.sh` (furball and spread) and, once T07 is
merged, single `bench typical 58 10 seed=1` and `bench battle <n> 10 seed=1` runs at 100 and 300 ships (and 500 from wave 4)
for the stage and per-entity breakdown, so its gain is attributable. After a wave is cherry-picked onto `m4` the controller
takes one combined measurement: the quick check, `typical`, `battle` at 100, 300 and 500, and the fullscreen check at `typical`
and at the battle's ceiling (`scripts/fullscreen_check.sh`, T07: `scripts/measure_fight.gd` with the layout, fullscreen at
1920x1080 under `/tmp/scs-gpu.lock`, 20 s; FPS, frame time, GPU time, VRAM, draw calls, the 3D scale). The headline (max N by
the sweep) is taken at the three phase ends (T13, T20, T25) with `scripts/bench.sh`, the release export once per phase end. A
wave's combined gain that is less than the sum of its parts is written down as such; the parts are what the Cycle log credits.

#### Execution schedule

| wave | tasks in parallel | merge order onto `m4` | measurement point | agents at once |
|---|---|---|---|---|
| 1 | T07 (A), T08 (G+N), T09 (G+N), T10 (G+N) | T07, T08, T09, T10 | each task's own; then the wave's combined quick check, typical, battle 100 and 300, fullscreen at typical and the ceiling | 4 |
| 2 | T11 (R), T12 (A+G) | T11, T12 | the same; T11's own GPU numbers | 2 |
| 3 | T13 (M), T14 (G), T27 (R+M) | T14, T13, T27 (T13 and T27 share the GPU lock; T27 measures after T14) | **phase 1 end: the sweep, typical and battle headlines, fullscreen, release once; report P1** | 2 |
| 4 | T15 (N, serial: it touches every native class) | T15 | its own before and after at typical, 100 and 300 | 1 |
| 5 | T16 (N+G), T17 (N+G), T19 (M) | T16, T17, T19 | combined; T19's Jolt numbers at 300 and 500 feed **checkpoint Q17** | 3 |
| 6 | T18 (N), T20 (N+A) | T18, T20 | **phase 2 end: sweep, headlines, fullscreen, release once; report P2** | 2 |
| 7 | T21 (T, serial: pool and ship adapter) | T21 | its own at 500 | 1 |
| 8 | T22 (T+N), T23 (R), T26 (R, only if the GPU binds at the fullscreen check after T11) | T22, T23, T26 | combined at 500; fullscreen at 500 | 2 or 3 |
| 9 | T24 (N, only if the fullscreen check at 500 misses the floor after T23), T25 (M) | T24, T25 | **phase 3 end: sweep, battle 500 and 1 000, fullscreen, release, the full local suite; report P3** | 1 or 2 |

Wall clock: waves 1, 5 and 8 are the parallel ones; the serial waves (4 and 7) are the two architecture changes that touch every
native class and the pool. The order inside a wave's merge puts the harness first so the others' Cycle log entries can cite
`battle` numbers taken after the merge.

#### Checkpoints for the maintainer

1. **After wave 3 (report P1).** Phase 1's numbers, the fullscreen check at `typical` and at the battle's headline, the cost per
   entity type against the budget table. The controller stops until the maintainer answers.
2. **After T19 (wave 5), Q17.** Jolt's and the sync's measured share at 300 and 500 in the battle, with the proposal: keep Jolt for
   every ship, or take AI ships out of Jolt (a change to D4 and §5.6). The controller stops; T20 and later do not assume either.
3. **After wave 6 (report P2).** Phase 2's numbers; the tier's physics rule (Q22) is already accepted, so the checkpoint is the
   numbers and whether `typical` holds its headroom.
4. **Before T24.** Only if the fullscreen check at 500 misses the 30 FPS floor after T23 and T26: the simulation thread changes
   §15.3's tick order and is a design-contract change; the controller asks before dispatching it.
5. **After T25 (report P3).** M4's definition of done; the maintainer confirms the milestone before `m4` merges into `main`.

#### The maintainer's answers to the plan's questions (Q20 to Q23)

Recorded in the answers table. Q20 sets the render bar (fullscreen 1920x1080, 60 FPS the target, 30 FPS the floor at the headline
battle, upscaling allowed, no tick-share rule). Q21 sets the three loads (typical, the grand multi-side 500, the 1 000 worst case
with 100 to 200 capitals) and adds proximity mines. Q22 accepts the stand-in fidelity, the tier's physics rule, parity for
entities without a GDScript twin and the gravity stand-in as recommended. Q23 makes the 1 000 stretch a measurement, not a gate.
No question is open.

#### Task sections

##### M4-T07 The `battle` and `typical` layouts, the mix, the first stand-ins and per-entity counters

- **Track:** A. **Agent:** Opus (the stand-ins need judgement about what the real features will cost; the layouts themselves are
  mechanical). **Depends on:** T06.
- **Goal:** the headline layout of Q15, Q19 and Q21 and the typical mission's layout exist and print their load per entity type,
  so every later task measures against them.
- **Files:** `src/perf/battle_mix.gd` (new, pure: the `typical` and `grand` profiles of the table above, every number a
  parameter), `src/perf/bench_layout.gd` (`battle`: fights of 24 on an 8 km lattice over 60 by 60 by 20 km, four sides, the
  player's fight at the centre, a side's capitals 5 km behind its fights, the asteroid slab over a third of the fights, the
  carriers' launch cycle; `typical`: two fights of 24, two sides, 20 by 20 by 10 km), `src/perf/standins/capital_standin.gd`,
  `turret_standin.gd` (gun and interceptor variants, firing through the existing `PulseCannon` and the projectile pool),
  `asteroid_field.gd` (a `MultiMeshInstance3D` and `PhysicsServer3D` static bodies by RID, shifted on `rebased`),
  `gravity_standin.gd`, `src/perf/bench_runner.gd` (spawns and parks the stand-ins, installs and restores the session faction
  table for four sides, prints the mix, the carrier launch cycle), `src/perf/perf_probe.gd` and `bench_report.gd` (counters per
  entity type: `fighters_near`, `fighters_far`, `capitals`, `turrets`, `interceptors`, `beams`, `missiles`, `mines`, `bolts`,
  `asteroids`, `launches`, `sides`, and the stage `standins_us`), `src/targeting/targetable.gd` (`kind`: ship, capital, turret,
  missile, mine, static, prop; default ship), `src/game/main.gd` (one hook: the runner's stand-in parent under `World`),
  `scripts/bench.sh`, `scripts/bench_quick.sh`, `scripts/bench_sweep.gd` (the layouts and the per-entity columns),
  `scripts/fullscreen_check.sh` (new: fullscreen 1920x1080 on the maintainer's machine under the GPU lock, 20 s after warm-up,
  FPS, frame time, GPU time, VRAM, draw calls and the 3D scale, with the floor and target verdict), `info.md` (the `bench` row),
  `tests/unit/test_battle_mix.gd`, `tests/unit/test_bench_layout.gd` (its battle and typical cases),
  `tests/integration/test_standins.gd`, `tests/integration/test_bench.gd` (battle and typical smoke). Missiles, beams and mines
  are T12.
- **Tests first:** `BattleMix.counts(profile, n)` gives the table above at 58, 100, 500 and 1 000 and scales as stated;
  `BenchLayout.plan("battle", n, seed)` is seeded, puts no two ships within 50 m, keeps every fight 8 km from the next, puts
  `round(0.15 n)` capitals in, a quarter a side, four sides every pair hostile; `plan("typical", 58, seed)` gives 50 fighters and
  8 capitals on two sides; a turret stand-in fires only inside its gate and only at hostiles within 4 km; an interceptor removes
  only missiles and bolts within 1.5 km; the asteroid field appears in the contact scan as `static` rows and is hit by a bolt; a
  rebase shifts every rock and the capitals; the gravity stand-in bends a bolt measurably over 30 s; the session faction table is
  installed for the run and restored after; `bench battle 50 3` and `bench typical 58 3` write summaries with every entity count.
- **Measures:** `bench typical 58 10`, `bench battle 100 10` and `battle 300 10` (seed 1), the stage and per-entity breakdown,
  the quick check on furball and spread unchanged (the layouts add nothing to them, and a run of each shows it). These are the
  phase 1 before.
- **Done when:** the tests pass, `scripts/bench.sh x battle typical` runs the sweeps, `fullscreen_check.sh typical 58` and
  `fullscreen_check.sh battle 100` record FPS, frame time, GPU, VRAM and draw calls on the maintainer's GPU with the floor and
  target verdicts, and the milestone's "Benchmark layouts" section describes both layouts and the mix.
- **Expected gain:** none; it is the ruler. Expected cost at battle 100: the 1 000 statics and 142 turrets in GDScript add about
  2 to 3 ms to what 100 fighters cost in spread (60 %); recorded, not budgeted, until T09 keeps statics out of the brains' contact
  lists and T20 moves the turrets native. `typical` at phase 1 is expected near the furball's 50 to 60 ship cost plus about 1.5 ms
  of stand-ins.
- **Architecture:** §17.6.
- **Done (2026-11-03):** `BattleMix`, the `battle` and `typical` layouts, the stand-ins under `src/perf/standins/` (capitals,
  gun and interceptor turrets, the asteroid field, the moon, the carrier launch cycle), `Targetable.kind`,
  `WorldFrame.environment_field`, the per-entity counters and `standins` stage, the sweep's battle headline and entity table,
  `scripts/fullscreen_check.sh`, and the bench option `rocks=<count>`. Numbers in the Cycle log, "M4-T07".
- **As built, where it differs from the plan:**
  - Rocks are hulls the current GDScript paths can see: each rock has one bare marker node with a `Damageable` (physics by RID
    and drawing by one multimesh, as planned). So the 1 000 rocks go through the contact scan's gather, the hit resolver's
    per-bolt loop and the ram resolver's gather every tick. That costs far more than the plan's 2 to 3 ms: about 24 ms at
    typical 58 and 49 ms at battle 100 (mostly the hit resolver: bolts times 1 058 hulls). T08's broad phase and T09's registry
    are what removes it; `rocks=0` measures everything else meanwhile. The ram resolver's gather of static hulls (about 3.8 ms
    for 1 000 rocks) is no wave-1 task's: listed for the controller.
  - Turrets aim at contacts no larger than 50 m (fighters), because the scan does not carry kinds yet (T09).
  - Bolts fly straight (they never took `environment_accel`), so the moon bends ships' paths and intercepts, not bolts; the
    test checks a coasting path over 30 s (13.5 m).
  - Mines are counted per ship in the mix (`max(100, N)`), which is what the table's 500 at N 500 and 1 000 at 1 000 give.
  - The maintainer's screens are 3840x2160 (the window reports 6144x3456 at the desktop's scale), so a fullscreen window is not
    1080p: the check holds the 3D scale at 1 080 lines (`scale3d=1080p`), the HUD at the screen's size.

##### M4-T08 Bolt broad phase in native code, projectile kinds

- **Track:** G and N. **Agent:** Opus. **Depends on:** T06.
- **Goal:** the hit resolver and the scan's incoming-fire query test only the bolt and hull pairs that can meet this tick, whatever
  the hull's size, so hits stop growing with bolts times ships; the windowed hit spikes (AC6) go with it or are explained.
- **Files:** `native/src/hit_sweep.rs` (new: `ScsHitSweep`, a grid over the bolts' swept segments and the hulls' bounding spheres
  with a per-cell maximum radius so a 1 km hull is found from any cell it reaches; returns candidate pairs in the resolver's
  order), `src/combat/hit_broad_phase.gd` (new facade, GDScript fallback by sort and sweep like `RamBroadPhase`),
  `src/combat/hit_resolver.gd` (gathers once into packed arrays, sweeps only the candidates, exact tests unchanged),
  `src/weapons/projectile.gd` (`kind`: bolt, beam, missile; `hit_radius_m` per kind), `src/ai/contact_scan.gd` is not touched
  (`incoming_fire` already runs in the field; T15 unifies). `tests/unit/test_hit_broad_phase.gd`,
  `tests/integration/test_hit_scale.gd`.
- **Tests first:** a work count: in a fleet of 24 ships 250 m apart with 300 bolts flying between two of them, pairs tested per
  tick against a bound of 3 per bolt (the resolver today tests every pair); every candidate the broad phase drops fails the
  resolver's sphere test on 40 seeded crowds, near the origin and 45 km out, with hull radii from 5 m to 1 km; the candidates'
  order is the resolver's; the native and GDScript paths give the same pairs; hit pins from `test_hit_resolver` (a grazing bolt at
  the edge, a bolt that tunnels a hull in one tick, friendly fire off and on).
- **Measures:** quick check and `bench furball 100 10` before and after; the hit stage and `combat.resolve_us` p99; after T07
  merges, `battle 100` in the wave's combined run.
- **Done when:** the work count passes on both paths, parity is bit for bit (pairs are integers), the hit stage at furball 100
  falls and the p99 spike is measured before and after in the window.
- **Expected gain:** hits 2.5 to about 0.6 ms at furball 100 (75 %); at 500 the difference between 13 ms and about 1 ms (70 %).
- **Architecture:** §17.7.
- **Done (2026-11-03):** as planned, with one change: the GDScript fallback is the same grid of levels as the native code, not sort
  and sweep, so the two paths can be compared pair for pair and count for count. Projectile kinds include `mine` (Q19's latest
  answer). The windowed hit spike was the impact flash building its quad and materials per hit, now shared per colour (the
  windowed hit p99 at furball 25 went from 7.6 to 0.4 ms). Numbers in the Cycle log, "M4-T08".

##### M4-T09 Native body registry: the scan built in native code, kinds and nearest-k per kind

- **Track:** G and N. **Agent:** Opus. **Depends on:** T06.
- **Goal:** the per-tick gather that cycle 4 left in GDScript (building the scan from the tree, the broadcast scan, the freed-body
  checks, about 1.2 ms at 100 ships) goes, and the scan knows an entity's kind and size so a field of rocks or a belt of mines does
  not fill a fighter's twelve contacts.
- **Files:** `native/src/body_registry.rs` (new: `ScsBodyRegistry`; bodies register once with their RID, id, faction, kind,
  radius and reach, unregister on release; each tick one `refresh` reads every registered body's transform and velocity through
  `PhysicsServer3D` by RID, static rows and mines only after a rebase), `native/src/contact_field.rs` (loads from the registry
  instead of packed arrays; `nearest` takes k ships plus `k_static` nearest statics, mines among them; a per-cell maximum
  radius), `src/ai/contact_scan.gd` (registers and unregisters bodies, asks the field; the GDScript path keeps today's gather as
  the reference), `src/ai/perception.gd` (`statics`: the nearest statics, read by avoidance), `src/ai/ai_pilot_driver.gd` (passes
  them), `src/ai/avoidance_math.gd` (statics are obstacles with their radius), settings `ai_nearest_static_k` (4).
  `tests/unit/test_contact_field.gd` (extended), `tests/unit/test_body_registry.gd`, `tests/integration/test_contact_registry.gd`.
- **Tests first:** a work count: the scan builds no per-tick arrays in GDScript (a counter of `from_tree` gathers, 0 on the native
  path); a released pool ship is gone from the next tick's scan; a body that moved is seen at its new place the same tick; 1 to
  300 bodies with 1 000 statics give the same contacts on both paths (statics never among the k ships, the nearest `k_static`
  beside them); four factions every pair hostile give the same hostile lists on both paths; a fighter in the rock slab avoids the
  rock in its path (a seeded flight through the field with no ram); the freed-body behaviour of cycle 4's tests holds.
- **Measures:** quick check and `furball 100`, `spread 100` before and after (the scan stage); `typical` and `battle 100` after T07.
- **Done when:** parity bit for bit on the contacts, the scan stage falls, the rock slab costs the brains nothing measurable.
- **Expected gain:** scan 2.6 to about 1.2 ms at furball 100 (60 %); the registry is the seed of T15's core.
- **Architecture:** §17.8.
- **Done (2026-11-03, as built; Cycle log, "M4-T09").** `ScsBodyRegistry` builds the shared scan in one native refresh a
  tick, with the same rows as `from_tree` bit for bit, and on both paths a contact's hull and selection are read when it is
  first handed out, so the paths agree whatever changes between build and query (`ContactScan.gathers` stays 0 on the
  native path); `BodyKind` keeps rocks and mines
  out of every contact list, `statics_for` and `Perception.statics` (`ai_nearest_static_k`, 4) hand the nearest to avoidance,
  and node-less rows register through `ContactScan.register_static`. Deviations: the refresh reads the nodes' own getters,
  not `PhysicsServer3D` by RID (the server's basis differs from the node's after a teleport, which would break parity);
  there is no per-cell maximum radius, a statics query pads by the largest static radius instead; the bolts are still
  gathered in GDScript each tick (0.16 ms of the 0.23 ms build at furball 100, T15's); avoidance's horizon for a static
  is at least the time to sidestep its reach (fighters keep M3's). Gain: the scan at furball 100 from 2.43 (cycle 4,
  native) to 2.13 ms, not the 1.2 ms planned: the gather was 0.37 ms of it, the rest is the queries, the contacts and
  the keepers. `typical` and `battle 100` wait for T07 (T07 adds `Targetable.kind`; see the Cycle log entry).

##### M4-T10 N4: the flight force step in native code

- **Track:** G and N. **Agent:** Fable (the riskiest maths for parity: `FlightModel` mixes 32-bit vectors and 64-bit scalars,
  and the assist's smoothing carries state). **Depends on:** T06.
- **Goal:** every AI ship's flight step (the model, the governor, the assist, the force application) runs in one native call per
  tick for all AI ships, with the player's ship on the GDScript path, so flight stops costing 36 us a ship.
- **Files:** `native/src/flight_step.rs` (new: `ScsFlightStep`, ships' specs and layouts loaded once, per-tick commands in as
  packed arrays, forces applied through `PhysicsServer3D.body_apply_force` by RID, glow levels and the applied force out),
  `src/ship/flight_batch.gd` (new node under `World` at priority -1: collects every batched ship's command, calls the step,
  hands glow levels to `ThrusterVisuals`), `src/ship/ship.gd` (a ship can be `batched`: its `_physics_process` skips the model
  and reads `applied_force` from the batch; the player is never batched), `src/ship/flight_model.gd` and `flight_assist.gd`
  untouched (the reference), `tests/unit/test_flight_step.gd`, `tests/integration/test_flight_batch.gd`.
- **Tests first:** a differential test over 10 000 seeded commands and states compares the native step's forces, torques and
  assist state with `FlightModel.compute` plus `SpeedGovernor`: bit for bit where the maths allows, else within 1e-6 relative
  and listed; the damping guard stays green with batched ships; `test_flight_model`, `test_flight_assist`, `test_speed_governor`,
  `test_raider_flight`, `test_ship_physics` green; a seeded 30 s fight with batching on and off meets Q16 (hits within 10 %,
  behaviour mix within 5 points, no ship more than 50 m from its twin at 10 s); a batched ship that runs out of fuel coasts.
- **Measures:** quick check and `furball 100` before and after (the flight stage); paired in one process by flipping
  `perf_native` as cycle 4 did.
- **Done when:** parity as stated and listed, the flight stage falls, the player's ship unchanged.
- **Expected gain:** flight 3.6 to about 1.2 ms at furball 100 (60 %); at 500 the difference between 18 ms and about 3 ms.
- **Architecture:** §17.9.
- **Done (2026-11-03, worktree on `f134e00`):** `ScsFlightStep` and `FlightBatch` as planned; the ship adapter's
  `batched` flag (on for every ship but the player's), `flight_path()`, the lazy row read for `applied_force()` and
  `get_flight_output()`, the `perf_native_flight` setting (pairs the flight step alone in one process) and the `flight`
  console provider (`path`, `ships`, `stepped`, `gather_us`, `step_us`, `positions`). Parity is bit for bit: the
  differential test finds no mismatch in 20 000 samples, the Jolt twins match, and the seeded fights with the batch on and
  off give the same outcome line for line (the Cycle log entry, M4-T10). The numbers are in the Cycle log.
- **Fix round 1 (review, 2026-11-03):** one `_prepare_command` for both paths (the assist edge, the brake's facing, the
  auto-track's lead), the twin test with a selected target, `brake` and `autotrack`, and the Q16 seeded fight as a committed
  test (`test_flight_parity_fight`, each fight in its own process: a second fight in one process is never the same fight; it
  finds 0.000 m between twins at 10 s, 135 hits against 135 and the same mix). The frame the batch applied the forces in is
  recorded apart from the output row, a refused step never prepares a command twice, a ship that can no longer fly leaves the
  batch, and the spec snapshot (mass included) is documented in §17.9.

##### M4-T11 Far-ship render proxies and the node diet for AI ships

- **Track:** R. **Agent:** Opus; the GPU numbers are taken by the agent on the maintainer's machine, the look stays (H).
  **Depends on:** T10 (it edits `ship.gd` after T10's change lands).
- **Goal:** an AI ship costs the renderer and the scene tree a tenth of what it does now: beyond a distance a ship is one LOD3
  splat node or a point in a `MultiMeshInstance3D` of dots, with no depth proxy, plumes, lights or chunks, and a near AI ship
  carries about 12 nodes instead of 108.
- **Files:** `src/ship/ship.gd` (AI ships build the lean set: body, collision shapes, LOD splat nodes, the proxy; thruster
  visuals as one `MultiMeshInstance3D` per ship; no running lights, nav lights, cockpit or screens), `src/ship/thruster_visuals.gd`
  (a multimesh mode), `src/ship/running_lights.gd`, `nav_lights.gd` (player only), `src/rendering/lod_switcher.gd` (the far level:
  hide every splat node and show the dot), `src/rendering/far_dots.gd` (new: one multimesh for every far ship, updated in
  `_process`), `src/game/ship_pool.gd` (builds AI ships lean), settings `far_ship_dot_m` (the distance). `tests/unit/test_far_dots.gd`,
  `tests/integration/test_ship_nodes.gd`.
- **Tests first:** a node count: a pooled AI ship has at most 16 nodes, the player's as today; a ship beyond `far_ship_dot_m`
  shows no splat node and one dot, and back inside shows its LOD level; the dot's position tracks the ship each frame; the rebase
  shifts the dots; GDGS's render state count stays 1; `test_lod_switcher` green.
- **Measures:** the fullscreen check at `typical`, `battle 100` and furball 45 before and after (FPS, frame time, GPU time, draw
  calls, render CPU time from `state render`); the rebase shift cost (`WorldFrame.last_rebase_us`) at 100 and 300 headless.
- **Done when:** draw calls per AI ship fall from about 27 to under 3, the rebase shift at 300 ships is under 2 ms, the fullscreen
  check at `typical` holds 60 FPS and at the wave 1 battle ceiling holds the floor, or the report says why not and whether the
  GPU or the main thread binds (the trigger for T26).
- **Expected gain:** render CPU at 500 from about 15 ms to under 3 ms (75 %); the sync and the rebase cut with the nodes (70 %).
- **Architecture:** §17.10.
- **Done (2026-11-03, worktree on `441a3b4`):** pool ships are built lean (`ShipAssembly` option `lean`): collision shapes as
  shape owners of the body, no cockpit interior, anchor or separate fallback node (the depth proxy draws the fallback mesh when
  it is wanted), the plumes as one multimesh with cone and core in one surface, the markers as one multimesh with the colour per
  instance; the depth proxy draws the hull merged into one surface (the player's too); past `far_ship_dot_m` (3 000 m) an AI
  ship is a point in the world's one `FarDots` multimesh. A Starfury ally is 19 nodes (112), a raider 24 (74), the player's
  123 as before. Numbers in the Cycle log, "M4-T11".
- **As built, where it differs from the plan:**
  - The node bound is 16 besides the guns: each muzzle keeps its marker and flash (two per muzzle, the weapons' nodes), and the
    gameplay components (`Targeting`, `AiPilotDriver`, `Damageable`, `Targetable`, `LodSwitcher`) stay; the plan's "about 12"
    counted neither. The running lights stay on AI ships (T28, Q26), drawn as one multimesh.
  - Draw calls: the lean set's own meshes cost about 1.3 a near ship (20 idle raiders in view add 45 calls with everything on,
    19 of them gone when the proxy, markers and plumes are hidden); the rest of a near ship's calls come with its visible GDGS
    splat node (about 2 a ship, gone when the node is hidden, as a far dot does). A mixed fleet of 100 idle ships in view: 5.0
    calls a ship (14.8 before). So under 3 a ship holds for the diet's own meshes and for a battle as a whole (battle 100: 367
    calls for 85 AI ships, 1 423 before), not for a near ship's splat node; listed for T27.
  - The rebase shift at battle 300 fell from 6.44 to 3.44 ms (median), not under 2 ms: the ships' part is about 1.3 ms
    (5 us a ship, shift and interpolation reset); the rest is 1 568 bolts (0.9 ms, a node each until T15's rows) and the
    capitals.

##### M4-T12 Missile, beam, interceptor and mine stand-ins

- **Track:** A and G. **Agent:** Opus. **Depends on:** T07, T08.
- **Goal:** the battle carries guided missiles, beam shots, interceptor defences and proximity mines, so the hit sweep and the scan
  are measured with every weapon kind Q19 and Q21 name.
- **Files:** `src/perf/standins/missile_standin.gd` (a `Projectile` of kind missile: a target, proportional navigation with a turn
  rate limit, a lifetime, launched by capitals to hold the mix's count in flight), `beam_standin.gd` (an emitter firing a 3 km
  segment resolved in its tick through `HitBroadPhase`), `mine_standin.gd` (the belts, the trigger cadence, the blast through
  `Damageable`), the interceptor variant of `turret_standin.gd` gains bolt and missile queries through the field,
  `src/weapons/projectile.gd` (the missile's steering hook; T08 added `kind`), `src/combat/hit_resolver.gd` (beam segments
  through the same sweep), `tests/unit/test_missile_guidance.gd`, `tests/unit/test_mine_trigger.gd`,
  `tests/integration/test_standins.gd` (extended).
- **Tests first:** a missile launched at a crossing fighter closes and hits within its lifetime at the stand-in's turn rate and
  misses at a tenth of it; a beam hits the first hull along its segment and none behind it; an interceptor removes a missile
  inside 1.5 km and never a bolt outside; a mine detonates on a hostile inside its trigger, never on a friendly, damages every
  hull in its blast and is gone after; the missile count in flight and the mines laid hold the mix; the per-entity counters
  report them.
- **Measures:** `typical`, `battle 100` and `300` before and after (the hit stage, `missiles`, `beams`, `mines` counters).
- **Done when:** the tests pass and both layouts' mix tables are complete.
- **Expected cost:** about 0.1 ms per 20 missiles and 0.1 ms per 100 mines in GDScript at 100 ships (60 %); T20 moves guidance
  and the mine trigger native.
- **Architecture:** §17.11.
- **Done (2026-11-03, worktree on `441a3b4`):** `MissileStandin` (proportional navigation at 350 m/s, turn limited to 0.6 rad/s,
  20 s, launched by the capitals to hold the mix's count in flight), `BeamStandin` (two per capital, a 3 km one-tick beam every
  2 s), interceptors that take missiles first from hit broad phase candidates, `MineStandin` (the belts as rows, a trigger every
  third tick, the blast through `Damageable`), `BenchLayout.mines`, the counters and the summary's weapons line. Both layouts'
  mix tables are complete. Numbers in the Cycle log, "M4-T12".
- **As built, where it differs from the plan:**
  - Interceptors query "through the field" by the hit broad phase's grid (`HitBroadPhase`, native `ScsHitSweep`): one query a
    tick for every interceptor due. The contact scan's native field is T09's file in this wave.
  - A beam is a projectile laid by `Projectile.fire_beam` that does not move in its own tick; the hit resolver retires every
    beam after the resolve that swept it.
  - Missiles and beams fire at a capital's strike target, its nearest hostile fighter within 6 km, looked up again after 30
    ticks; the guns keep T07's 4 km scan query.
  - Mines are laid again in their place 10 s after going off, so the belts hold the mix over a run. They are not in today's
    contact scan (no `Targetable`); T09's registry takes them as rows of kind `MINE` (§17.11).
  - The belts lie 1.5 km out from each fight toward each side's own direction; in the 10 s windows measured no mine went off
    (the fighters stay inside 1.2 km), so the blast's cost was not on the tick. The trigger queries were.

##### M4-T13 Phase 1 measurements and report P1

- **Track:** M. **Agent:** Sonnet. **Depends on:** T11, T12, T14.
- **Goal:** phase 1's headlines and the maintainer's first checkpoint.
- **Files:** the Cycle log entry "Phase 1 (T07 to T14)" and the "Report P1" subsection in this file; `reports/` (not committed).
- **Tests:** none new; AC13's paired budget and the focused files of every phase 1 task run once.
- **Measures:** `scripts/bench.sh m4_p1 battle typical furball spread transit` (the full sweep), below-sweep counts for the
  battle's real ceiling, the stage and per-entity breakdown at typical, battle 100, 300 and 500, the fullscreen check at `typical`
  and at the battle's headline and at 100, the release export's quick check once.
- **Done when:** the entry holds every number in the form of the final measurements above, the gains per task against their
  predictions, the cost per entity type against the budget table, and the behaviour changes.
- **Expected:** `typical` under 8 ms and 60 FPS (65 %); furball 100 under 8 ms (65 %); battle headline 100 (50 %).

##### M4-T14 Jolt collision layers and far-ship physics interpolation off

- **Track:** G. **Agent:** Sonnet. **Depends on:** T11.
- **Goal:** Jolt's broad phase stops pairing fighters with fighters (the ram resolver does the exact work), capitals, rocks and
  mines pair only with what can hit them, and far AI ships skip the per-node interpolation reset at a rebase.
- **Files:** `src/ship/ship.gd` (layers and masks by kind), `src/perf/standins/*` (the capitals', rocks' and mines' layers),
  `src/world/world_frame.gd` (the settle skips nodes flagged uninterpolated), `tests/integration/test_collision_layers.gd`.
- **Tests first:** two fighters crossing report no Jolt contact and still take the swept ram; a fighter into a rock stops; a bolt
  never has a body; the rebase settle walks only the interpolated nodes (a count).
- **Measures:** `battle 300` and `500` before and after (the physics stage, `sync`, the rebase tick).
- **Done when:** the counts pass and the physics stage at 300 is lower or the entry says it was not.
- **Expected gain:** physics 1.9 ms at 100 unchanged; at 300 and up about 1 ms (30 %).
- **Architecture:** §17.12.

##### M4-T15 The native simulation core: entity rows, one call in and one call out

- **Track:** N. **Agent:** Fable (architecture). **Depends on:** T13 (phase 1 accepted).
- **Goal:** one struct-of-arrays store in the crate holds every simulated entity (fighter, capital, turret, missile, beam, bolt,
  mine, static) as a row with kind, radius, faction, flags, position, velocity, attitude, command and the per-kind state, filled
  once per tick from Jolt and the registry and read by every native class, so the contact field, the hit sweep, the flight step
  and the ram broad phase stop loading their own copies.
- **Files:** `native/src/sim_core.rs` (new: `ScsSimCore`, the rows, `sync_in`, `sync_out`, a row's lifecycle), `body_registry.rs`
  (becomes the core's registration), `contact_field.rs`, `hit_sweep.rs`, `flight_step.rs` (read the core), `native/src/ram_phase.rs`
  (new: the ram broad phase on the core's rows, the GDScript `RamBroadPhase` stays the reference), `src/perf/sim_core.gd` (the
  facade; a `SimCore` node under `World` at priority -11 does `sync_in`, and one at 2 000 000 does `sync_out`), `src/ai/contact_scan.gd`,
  `src/combat/hit_broad_phase.gd`, `src/combat/ram_resolver.gd`, `src/ship/flight_batch.gd` (ask the core), `tests/unit/test_sim_core.gd`.
- **Tests first:** rows survive a pool release and acquire with a new id; a rebase shifts every row once; the four classes give
  the same answers from the core as from their own loads on seeded worlds (bit for bit); a row of each kind round-trips its state;
  `sync_in` and `sync_out` are the only places the core touches the engine (a counter of engine calls per tick that does not grow
  with ships).
- **Measures:** quick check, `furball 100`, `typical`, `battle 300` before and after: the sum of the four facades' load times,
  now one.
- **Done when:** parity holds, the per-tick engine calls are one per body for the sync and nothing per query, and §17's tick
  order names the core's two nodes.
- **Expected gain:** about 0.5 ms at 100 (55 %); the real gain is that T16 to T22 have somewhere to live.
- **Architecture:** §17.13 (a new subsection head, "The native core", that T16 to T24 add to).

##### M4-T16 N2: avoidance, the fire lane and the context lists in native code

- **Track:** N and G. **Agent:** Opus. **Depends on:** T15.
- **Goal:** the per-contact loops that run on every think (avoidance over the contacts and statics, the fire lane, the hostile
  and friendly splits in `AiContext.refresh`) run on the core's rows in one call per thinking ship.
- **Files:** `native/src/pilot_kernels.rs` (new: `avoid`, `fire_lane`, `context_lists`), `src/ai/avoidance_math.gd`,
  `src/ai/fire_lane.gd`, `src/ai/ai_context.gd` (facades over the kernels; the GDScript stays the reference), `src/ai/ai_pilot_driver.gd`
  (the seed for the tie-break passed in), `tests/unit/test_pilot_kernels.gd`.
- **Tests first:** differential tests over seeded contacts compare the filtered velocity, the lane verdict and the lists bit for
  bit (the tie-break's `hash()` reproduced or passed in); `test_avoidance_math`, `test_fire_lane`, `test_ai_pilot_selection`,
  `test_ai_avoidance`, `test_ai_ram` green.
- **Measures:** `furball 100`, `typical`, `battle 300` (the think stage) before and after.
- **Done when:** bit for bit, the think stage falls.
- **Expected gain:** about 1 ms at furball 100, 3 ms at 300 (55 %).
- **Architecture:** §17.13.

##### M4-T17 The brains in native code, under Q16's tolerance

- **Track:** N and G. **Agent:** Fable (3 000 lines of seeded, stateful behaviour with a tolerance to meet, the single riskiest
  port). **Depends on:** T16. Two commit sets, each test first: T17a `PilotSteering`, `InterceptMath`, `Manoeuvres` and the
  temperament maths (pure, bit-identical plausible); T17b `AiPilot`'s scoring and the behaviours (attack, slash, evade, idle,
  formation, follow path, guard, retreat, ram, rally), profiles and temperaments.
- **Goal:** a thinking fighter costs about 5 us in native code instead of 25 to 30 in GDScript, with the GDScript brains kept as
  the reference and the player-facing seams unchanged (`PilotBrain`'s interface, wings, orders, objectives, the console).
- **Files:** `native/src/brain.rs`, `brain_behaviours.rs`, `brain_maths.rs` (new), `src/ai/ai_pilot.gd` (a facade: with the core,
  `think` runs native and reads the result; without, today's code), `src/ai/brain_factory.gd` (builds the native row's profile),
  `src/ai/ai_console.gd` (scores read from the row), `tests/unit/test_brain_parity.gd`, `tests/integration/test_brain_tolerance.gd`.
  Seeded rolls: Godot's `hash([seed, "attack"])` reproduced in Rust (the engine's hash is public) or, failing that, rolled from a
  per-ship seed table built once and listed as a tolerated difference.
- **Tests first:** T17a bit for bit on seeded inputs; T17b the Q16 test: a seeded 30 s fight (furball 50 and spread 50, seeds 1
  to 3) with native brains against GDScript twins gives hits within 10 %, behaviour mix within 5 points, no ship more than 50 m
  from its twin at 10 s; every AI test file green on both paths (`test_ai_*`, `test_dogfight`, `test_m3_run`, AC13's paired budget).
- **Measures:** `furball 100`, `typical`, `battle 300` and `500` (the think stage) before and after, paired by `perf_native`.
- **Done when:** the tolerance test passes on every seed and the differences are listed in the Cycle log; the think stage at 300
  is under 2 ms single-threaded.
- **Expected gain:** think about 3.4 to about 0.8 ms at furball 100 (50 %); at 500 the difference between 25 ms and about 4 ms.
  If the tolerance cannot be met in two attempts the controller stops: the tier (phase 3) then carries more and the near count
  falls (the research's fallback).
- **Architecture:** §17.13.

##### M4-T18 N3: threads inside the core

- **Track:** N. **Agent:** Opus. **Depends on:** T17.
- **Goal:** the per-ship kernels (perception queries, the brains, avoidance, flight, missile guidance) run across the performance
  cores inside the crate under the determinism rules (read the snapshot, write only your own row, no engine call off the main
  thread, merge in row order), with 1-thread and N-thread outputs identical.
- **Files:** `native/Cargo.toml`, `Cargo.lock` (rayon, pinned), `docs/third-party.md` (its rows), `native/src/sim_core.rs` (the
  parallel pass, a thread count setting), the kernel files' signatures, settings `perf_threads` (0 = the performance cores,
  pinned for the bench), `tests/unit/test_core_threads.gd`.
- **Tests first:** the same seeded battle stepped 600 ticks with 1 thread and with 6 gives identical rows byte for byte; a kernel
  that reads another row's output (a mutation) is caught by the test; the thread count follows the setting at once.
- **Measures:** `battle 300` and `500` with 1 and 6 threads in one process; p99 at `typical` (the pool wake-up cost), with the
  threshold below which the pass runs single-threaded chosen by the numbers.
- **Done when:** identical outputs, the AI stage at 500 divided by about 3, no p99 loss at `typical`.
- **Expected gain:** the native per-ship work divided by 3 to 4 above about 100 ships (60 %).
- **Architecture:** §17.13.

##### M4-T19 Jolt measured at 300 and 500: the ships-out-of-Jolt proposal (Q17)

- **Track:** M. **Agent:** Sonnet. **Depends on:** T15.
- **Goal:** the maintainer decides D4 on numbers: what Jolt's step, the body sync and the node propagation cost at 300 and 500
  ships in the battle with the mix (45 and 75 capitals among them), against what a native 6DOF integrator for AI ships would cost
  (under 1 us a ship, the research's estimate), and what Jolt would still be needed for (the player, near contacts, capitals,
  statics).
- **Files:** the Cycle log entry and a proposal subsection in this file; a throwaway timing build (not committed).
- **Measures:** `battle 300` and `500` with the probe's `physics` and `sync` stages and the rebase tick; the same with the AI
  ships' bodies frozen for a tick to isolate the sync; Jolt's thread count varied.
- **Done when:** the entry gives the costs, a recommendation (keep Jolt for every ship, or AI ships integrated natively with
  Jolt for the player, capitals and statics, and what the ram resolver then does) and the controller stops for the answer.
- **Expected:** the sync and node propagation, not Jolt's solver, bind at 500 (60 %, the research); if the maintainer says
  yes, the integrator is a phase 3 task the controller adds (T21 takes it for tier rows either way).

##### M4-T20 Turrets, missiles, beams and mines as native rows

- **Track:** N and A. **Agent:** Opus. **Depends on:** T16, T12.
- **Goal:** the stand-ins' per-tick work (a turret's target pick, aim and gate; an interceptor's query; a missile's guidance; a
  beam's segment; a mine's trigger) runs as kernels over the core's rows, so M12's real turrets, missiles and mines inherit a
  budget-tested path and the battle's non-fighter rows cost what the budget table says (710 turrets at 500 make this the second
  largest row after the fighters).
- **Files:** `native/src/turret_kernel.rs`, `missile_kernel.rs`, `mine_kernel.rs` (new), `src/perf/standins/turret_standin.gd`,
  `missile_standin.gd`, `beam_standin.gd`, `mine_standin.gd` (facades over the rows; the GDScript stand-ins stay the reference),
  `tests/unit/test_turret_kernel.gd`, `test_missile_kernel.gd`, `test_mine_kernel.gd`.
- **Tests first:** the kernels against the GDScript stand-ins on seeded scenes: the same target picks, aim steps, fire ticks,
  guidance commands and detonations bit for bit; a seeded 30 s battle at 100 with native rows against GDScript stand-ins: hits
  within 10 % (Q22).
- **Measures:** `typical`, `battle 300` and `500` before and after (`standins_us`, the `turrets`, `interceptors`, `missiles`,
  `mines` counters).
- **Done when:** the per-entity cost at 500 meets the budget table's turret, interceptor, missile, beam and mine rows or the
  entry says by how much it misses.
- **Expected gain:** the stand-ins' GDScript cost (about 8 ms at battle 500 with 710 turrets, about 1.5 ms at `typical`) to
  under 2 ms and 0.3 ms (60 %).
- **Architecture:** §17.13.

##### M4-T21 The low-attention tier: state, integration, promotion and demotion

- **Track:** T. **Agent:** Fable. **Depends on:** T20 and checkpoint 3 (Q17's decision shapes what a tier ship has when
  promoted).
- **Goal:** a fighter or a capital beyond the attention radius leaves Jolt and the scene tree and lives as a core row integrated
  by the native flight model at 20 Hz from its held command (a capital on its heading); coming within the radius promotes it onto
  a pooled body with its position, velocity, attitude and command carried over exactly, and the reverse demotes it. A far
  capital's turrets, interceptors and missile launchers leave with it (T22 gives them their aggregated fire).
- **Files:** `native/src/tier.rs` (new: the tier's integrator and cadence), `src/ai/tier_director.gd` (new node under `World`:
  the radius, promotion and demotion with hysteresis, the row and body handover for fighters and capitals), `src/game/ship_pool.gd`
  (acquire and release from a row's state), `src/ship/ship.gd` (a demoted ship parks its body), `src/perf/standins/capital_standin.gd`
  (park and restore from a row), settings `tier_radius_m` (10 000), `tier_hz` (20). `tests/unit/test_tier.gd`,
  `tests/integration/test_tier_handover.gd`.
- **Tests first:** a ship demoted and promoted 100 times over a seeded 60 s flight never pops (position within 1 cm, velocity
  within 1 cm/s, the command identical at each handover); a capital the same with its turrets back on it; a tier ship keeps the
  Newtonian invariant (its velocity changes only by its nozzle forces and gravity, the damping guard's reading); the count of
  bodies in Jolt equals the near count; the player flying into a far fight sees it promoted before it is within 5 km;
  `test_ai_think_rate` green (the tier replaces the far rate for tier ships and leaves it for near ones).
- **Measures:** `battle 500` before and after (the physics, sync, flight and AI stages; `fighters_near`, `fighters_far`, the
  capitals' split).
- **Done when:** the handover tests pass and the tick at battle 500 scales with the near count (a run with the radius halved
  shows it).
- **Expected gain:** at 500 the tick falls to what about 150 near fighters and 20 near capitals cost plus 0.3 us a tier fighter
  and 2 us a tier capital (70 %).
- **Architecture:** §17.14 (a new subsection head, "The low-attention tier", that T22 to T24 add to).

##### M4-T22 Tier brains, statistical fire and far capitals' aggregated fire

- **Track:** T and N. **Agent:** Opus. **Depends on:** T21.
- **Goal:** tier rows still fight: a fighter's brain at 2 to 5 Hz on the same contact grid, fire resolved as a to-hit roll from
  the fire gate's geometry and the shooter's skill, damage applied, no bolt row; a far capital's turret groups fire as one roll per
  group per second against the fighters in its range, its interceptors as one removal roll against missiles, its launchers as
  missiles resolved at launch; a squadron or a capital out of view wins or loses at the rate one in view does.
- **Files:** `native/src/tier.rs` (the cadence and the roll), `native/src/tier_fire.rs` (new: fighters' and capitals' rolls),
  `src/ai/tier_director.gd` (the damage path through `Damageable`), settings `tier_brain_hz` (4), `tests/unit/test_tier_fire.gd`,
  `tests/integration/test_tier_outcomes.gd`.
- **Tests first:** the to-hit rate against a seeded full-fidelity duel (the same geometry, 1 000 shots) within 10 %; a 12 against
  12 fight run 30 s in the tier and at full fidelity, seeds 1 to 3: hits within 15 %, the winning side the same, mean hull loss
  within 15 %; a cruiser with 8 turrets against 12 fighters, 30 s, in the tier and at full fidelity: fighter hull loss within 15 %;
  a tier ship hit by a near ship's bolt (it has no body: the hit sweep tests tier rows as spheres) takes damage.
- **Measures:** `battle 500` (the tier's cost per row, `fighters_far`, the far capitals).
- **Done when:** the outcome tests pass and the tier's cost is at or under 0.3 us a fighter and 2 us a capital.
- **Expected:** the tier's fairness (65 %); its cost (75 %).
- **Architecture:** §17.14.

##### M4-T23 Far proxies for tier rows

- **Track:** R. **Agent:** Opus (GPU numbers by the agent, the look (H)). **Depends on:** T21, T11.
- **Goal:** a tier row with no node is still drawn: a point in T11's far dots sized by angular size with a 1 px floor (a capital's
  larger), radar and targeting see it (the player's radar reads rows, not nodes, for tier rows), so 500 ships are on screen for
  the cost of one multimesh.
- **Files:** `src/rendering/far_dots.gd` (rows as a second source), `src/hud/radar_model.gd` (the radar's contact source gains
  the tier's rows), `src/targeting/targeting_controller.gd` (the player's candidates include tier rows by id),
  `tests/integration/test_tier_proxies.gd`.
- **Tests first:** every tier row has a dot and a radar blip; a promoted ship's dot disappears the frame its body shows; the
  player can select a tier ship and the selection survives its promotion.
- **Measures:** the fullscreen check at battle 500 (FPS, frame time, GPU time, draw calls, render CPU, visible splats).
- **Done when:** the window at 500 shows every ship and the renderer's CPU time at 500 is under 3 ms or the entry says why not.
- **Expected:** 70 %.
- **Architecture:** §17.14.

##### M4-T24 The simulation step on a worker thread (conditional)

- **Track:** N. **Agent:** Fable. **Depends on:** T23, T26 if built, and checkpoint 4. **Status `not needed`** if the fullscreen
  check at `battle` 500 holds the 30 FPS floor after T23 and T26.
- **Goal:** the whole native step (every kernel over the core) runs at a fixed 60 Hz on a worker thread into a double-buffered
  snapshot; the main thread's physics tick does only `sync_in`, the handover of commands and `sync_out`, and the visuals
  interpolate between the last two snapshots, so the tick no longer competes with rendering for the frame.
- **Files:** `native/src/sim_core.rs` (the thread, the two buffers), `src/perf/sim_core.gd`, `src/rendering/splat_pose_sync.gd`
  (interpolation from snapshots for tier rows' dots), `tests/unit/test_core_snapshot.gd`.
- **Tests first:** the threaded step gives the same rows as the inline step tick for tick on a seeded battle; no engine call from
  the worker (a guard that panics in debug); a missed deadline is counted, never skipped.
- **Measures:** the fullscreen check at battle 500 before and after; the headless tick.
- **Done when:** identical rows, the floor held and the target approached in the window at 500, or the entry says what still
  binds.
- **Expected:** 50 % that it is needed; 70 % that it holds the floor at 500 when it is, 45 % the target.
- **Architecture:** §17.13 and §15.3 (the tick order; a design-contract change, checkpoint 4).

##### M4-T25 Phase 3 measurements, the 1 000 stretch, the full suite and report P3

- **Track:** M. **Agent:** Sonnet. **Depends on:** T23 (and T24, T26 if built).
- **Goal:** M4's definition of done.
- **Files:** the Cycle log entry "Phase 3 (T21 to T26)" and "Report P3"; AC5 and AC6's Done cells; `docs/architecture.md` §11
  (the entity budget and the render bar), `docs/roadmap.md` (one line each at M6, M12 and M14 naming the stand-in each replaces,
  and the mines' placement as the maintainer decides); `reports/`.
- **Measures:** `scripts/bench.sh m4_p3` on every layout, `battle` to 1 000 (the sweep's N list extended; the 1 000 run with the
  profile's 15 % and 20 % capital share), the fullscreen check at `typical`, at the battle's headline, at 500 and at 1 000, the
  release export once, `scripts/run_tests.sh` once (Q10).
- **Done when:** every number is in the entry in the form of the final measurements above, every behaviour change and every
  tolerated difference is listed, the suite is green locally and on CI, and the maintainer is asked to confirm M4.
- **Expected:** `typical` under 4 ms and 60 FPS with headroom (85 %); battle 500 in the world, 100 to 150 fighters and about 20
  capitals near, under 8 ms headless (55 %), the 30 FPS floor (60 %), 60 FPS (40 %); 1 000 under 8 ms headless (35 %), the floor
  (30 %), 60 FPS (15 %).

##### M4-T26 Resolution scaling for the big battle (conditional)

- **Track:** R. **Agent:** Sonnet. **Depends on:** T11; built in wave 8 only if T11's or T13's fullscreen check shows the GPU
  binding (GPU time over about 12 ms a frame at the battle's headline or at 500); else `not needed`.
- **Goal:** the 3D scene renders at a lower internal resolution and is upscaled (Godot's `scaling_3d_mode` FSR 2 or bilinear and
  `scaling_3d_scale`, the technique Q20 allows) when the frame would miss the target, by a setting and, optionally, a floor-driven
  automatic step; the HUD and the text stay at the window's resolution as `RenderScale` already keeps them.
- **Files:** `src/rendering/render_scale.gd` (a second input: the wanted scale from the setting and the automatic step, combined
  with the tile budget's), `src/rendering/post_effects.gd` or wherever the viewport's scale is applied today (named in the report
  if it is not `render_scale.gd`'s caller), settings `render_scale_3d` (1.0; 0.5 to 1.0), `render_scale_auto` (off),
  `tests/unit/test_render_scale.gd` (extended).
- **Tests first:** the combined scale is the smaller of the tile budget's and the setting's; the automatic step lowers the scale
  by 0.1 after a second under the floor and raises it after five seconds over the target, never past 1.0 or under 0.5; the
  setting applies at once.
- **Measures:** the fullscreen check at the battle's headline and at 500 at scales 1.0, 0.75 and 0.5 (FPS, GPU time, visible
  splats); a screenshot at each for the maintainer's (H) judgement of the look.
- **Done when:** the scale moves the GPU time as expected and the entry says which scale the headline needs for the target and the
  floor; the maintainer judges the look.
- **Expected:** GPU time roughly proportional to the pixels drawn for the splat passes (65 %).
- **Architecture:** §17.15.

##### M4-T27 Render comparison: Gaussian splats against meshes (Q24)

- **Goal:** answer with numbers whether the big battles are cheaper drawn with Gaussian splats or with polygon meshes, at the
  same shapes and detail, on the maintainer's GPU (fullscreen 1920x1080, Q20). The simulation tick does not depend on how ships
  are drawn; this measures the render side only (GPU time, CPU render time, draw calls, VRAM, FPS).
- **Mesh variants:** `tools/procgen` already builds each ship as a surface and samples splats from it (`core/sampling.py`).
  Export that same surface as a mesh (a procgen output beside the splat files, generated by code like every asset), with simple
  materials that light like the splats; capitals, asteroids and the planet are meshes already (T07's stand-ins). A setting or
  bench option switches a scene's ships between the splat and the mesh path, so both runs share everything else. Mesh ships use
  the engine's LOD and, where many ships share a hull, instanced drawing (`MultiMesh` or the renderer's automatic instancing):
  say which.
- **Scene 1, the 500 battle:** the `battle` layout at 500 (T07's mix), drawn with splat fighters and then mesh fighters, 20 s
  each after warm-up, the camera in the battle.
- **Scene 2, a Babylon 5 station scene (maintainer, Q24):** a stand-in of the station, about 8 km long: a central cylinder that
  rotates and a stationary top bar (the stand-in's shape only: no franchise assets, generated by code, `docs/design-references.md`
  for proportions), 10 capital ships, about 80 fighters and a nearby planet (T07's planet stand-in, gravity as Q6's harness-only
  source). Splat and mesh variants of the station and the ships. The camera near the station and at a distance.
- **Measure, per scene and variant:** FPS (vsync off and on), frame time mean, p99 and max, GPU time, CPU render time, draw
  calls, splats or triangles drawn, VRAM, under `/tmp/scs-gpu.lock` (and both bench locks), in the fullscreen check's form
  (`scripts/fullscreen_check.sh` once T13 has it, or the same measurement). Screenshots of each variant to `/tmp/m4_t27_*.png`
  for the maintainer; how they look stays (H).
- **Test first:** the mesh export (a mesh per hull, matching the splat surface's bounds and triangle budget) and the variant switch
  (the same scene builds with either path) as unit and integration tests before the change.
- **Done when:** the Cycle log entry "T27 render comparison" holds both scenes' tables, a short reading (which path is cheaper,
  where each binds, what a hybrid of near splats and far meshes would cost), and a recommendation for the maintainer; the
  screenshots are listed for (H).

#### Architecture subsections this plan assigns

§17.6 the battle and typical layouts and the stand-ins (T07); §17.7 the hit broad phase and projectile kinds (T08); §17.8 the body
registry and kinds (T09); §17.9 the native flight step (T10); §17.10 far proxies and the node diet (T11); §17.11 missile, beam,
interceptor and mine stand-ins (T12); §17.12 collision layers (T14); §17.13 the native core (T15, with T16, T17, T18, T20 and T24
adding paragraphs under their own task ids); §17.14 the low-attention tier (T21, with T22 and T23 adding paragraphs); §17.15
resolution scaling (T26). T13, T19 and T25 write only in this file.


## Cycle log

(T01 records the baseline here; each cycle adds its entry: before, candidates, test, change, after.)

### Baseline (M4-T01, 2026-11-02, taken again after review round 1)

Measured on commit `935ae1a` (the harness after review round 1, no game change since M3), headless on the development desktop
with nothing else heavy running: an i5-13600KF (six performance cores at 5.1 GHz, eight efficiency cores), 31 GB, Bazzite 44,
the official Godot 4.7.2-stable editor build (`ed1daf0bf`, debug), as `run_tests.sh` uses it. `scripts/bench.sh
m4_baseline_r1`: the `combat_sandbox` scene, 5 s of warm-up and 30 s measured, seeds 1, 2 and 3, each run its own process pinned
to cores 0-11. N counts the layout's ships; the player flies too. The full reports are in `reports/perf/m4_baseline_r1*/`,
`m4_sleep_*/` (not committed). The first baseline, before the review, gave the same ticks within 1.2 %.

**Max N: furball 0, spread 0, transit 0; headline 0.** No layout passes at 25 ships, the sweep's smallest count, so each one
stopped after 25 and 50. Three runs at 100 were added past the stop for the breakdown, and counts of 12, 16 and 20 were run
below the sweep to find the real ceiling (`m4_baseline_r1_below`, not part of max N): all three layouts pass at 20 on every
run. Three run medians never spread more than 3.3 % (furball at 20). How far the bench's busy main thread flatters these
numbers is measured below (frame sleep): at 20 ships it is the p99, so the limit is about 20 ships, not comfortably above it.

| layout | N | runs passed | tick median ms (three runs) | p99 ms | behind real time | worst rebase tick ms | worst shift ms |
|---|---|---|---|---|---|---|---|
| furball | 20 | 3/3 (below the sweep) | 6.96 (6.96, 7.01, 6.78) | 8.16 | 0.00 % | 8.10 | 0.37 |
| furball | 25 | 0/3 | 9.63 (9.63, 9.74, 9.63) | 11.52 | 0.00 % | 12.76 | 0.41 |
| furball | 50 | 0/3 | 28.99 (28.96, 29.09, 28.99) | 32.85 | 44.2 % | 33.24 | 1.17 |
| furball | 100 | 0/3 (past the stop) | 109.07 (109.07, 109.26, 109.02) | 116.02 | 84.9 % | 116.84 | 3.78 |
| spread | 20 | 3/3 (below the sweep) | 6.78 (6.83, 6.77, 6.78) | 8.00 | 0.00 % | 11.23 | 0.51 |
| spread | 25 | 0/3 | 9.41 (9.47, 9.41, 9.36) | 11.17 | 0.00 % | 12.71 | 0.70 |
| spread | 50 | 0/3 | 27.63 (27.25, 27.63, 27.82) | 31.21 | 41.5 % | 30.99 | 1.19 |
| spread | 100 | 0/3 (past the stop) | 102.83 (102.83, 102.41, 103.67) | 112.54 | 84.1 % | 113.79 | 2.62 |
| transit | 20 | 3/3 (below the sweep) | 6.02 (6.00, 6.02, 6.04) | 6.74 | 0.00 % | 6.71 | 0.32 |
| transit | 25 | 0/3 | 8.13 (8.14, 8.13, 8.11) | 9.49 | 0.00 % | 9.44 | 0.40 |
| transit | 50 | 0/3 | 24.17 (24.06, 24.17, 24.43) | 26.66 | 33.1 % | 27.42 | 1.02 |
| transit | 100 | 0/3 (past the stop) | 91.55 (92.49, 91.12, 91.55) | 97.18 | 82.0 % | 100.24 | 2.25 |

Every failure at 25 is the tick median alone (p99, real time and the rebase ticks hold); from 50 the simulation falls behind
the wall clock and every tick, rebase or not, is over a frame. The rebase budget is on the whole tick that held a rebase: the
shift itself costs under 1.2 ms up to 50 ships and 2.3-3.8 ms at 100, and the median rebase tick is about 0.3-0.5 ms over the
median tick at 12-25 ships, 1-1.6 ms at 50 and 2.3-4.3 ms at 100 (the shift, Jolt moving every body, the interpolation reset). Pool growth (the load) took 30, 80 and 185 ms at 25, 50 and 100 ships
headless, where the splat renderer is off.

**Stage breakdown**, mean ms per tick (the median over the three runs of each run's mean; means add up to the mean tick, the
median tick is above). `scan` and `think` are inside `ai`, `hit` and `ram` inside `resolvers`, `sync` inside `physics`; `other`
is the tick's unaccounted remainder. At 50 and 100 ships the simulation runs behind and its ticks run back to back, so the sync
of one tick lands in the engine window of the one before: `sync` was timed only in the first tick of each catch-up frame
(12.5 % of ticks at 50 and 100 ships, re-measured after a probe fix) and is a lower bound there (it was timed in every tick
at 25 and below).

| layout | N | tick | ai | (scan) | (think) | flight | targeting | resolvers | (hit) | (ram) | late | physics | (sync) | other (unaccounted) | bolts |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| furball | 50 | 29.28 | 6.18 | 2.05 | 6.09 | 1.81 | 16.75 | 3.56 | 0.85 | 2.68 | 0.05 | 0.86 | 0.11 | 0.05 | 115 |
| furball | 100 | 109.49 | 17.64 | 5.82 | 17.45 | 3.86 | 73.98 | 12.13 | 2.63 | 9.46 | 0.07 | 1.85 | 0.28 | 0.11 | 214 |
| spread | 50 | 27.90 | 4.71 | 1.82 | 4.62 | 1.77 | 16.98 | 3.52 | 0.82 | 2.71 | 0.05 | 0.86 | 0.10 | 0.05 | 107 |
| spread | 100 | 103.59 | 11.01 | 4.83 | 10.82 | 3.80 | 74.39 | 12.41 | 2.84 | 9.53 | 0.07 | 1.81 | 0.23 | 0.11 | 230 |
| transit | 50 | 24.33 | 3.59 | 1.44 | 3.50 | 1.52 | 16.52 | 1.67 | 0.10 | 1.55 | 0.27 | 0.72 | 0.05 | 0.03 | 0 |
| transit | 100 | 91.69 | 8.43 | 3.68 | 8.25 | 3.29 | 72.66 | 5.13 | 0.19 | 4.91 | 0.59 | 1.54 | 0.13 | 0.03 | 0 |

What the baseline says, for cycle 1 to test rather than follow:

- **Targeting is two thirds of the tick and the same in every layout**: 4.5 ms at 25 ships, 16.5-17.0 ms at 50, 72.7-74.4 ms
  at 100 (3.7 and 4.4 times per doubling, so quadratic), whether the ships share one fight or sit 20 km apart. M3-T20's figure
  (`TargetingController` about 63 of 87 ms at 100 ships) is confirmed in a real fight: 74 of 109 ms. Every ship's controller
  turns every targetable into a `TargetInfo` each tick before the range cut.
- **The AI** is the second cost and grows faster than linearly: 2.5, 6.2 and 17.6 ms at 25, 50 and 100 in the furball,
  11.0 ms at 100 in spread and 8.4 ms in transit. The scan inside it (5.8 ms at 100 in the furball, 4.8 ms in spread) costs
  nearly as much in spread as in the furball, so it too walks every body whatever the range.
- **The resolvers** are third, and most of them is the ram resolver: at 100 ships 9.5 ms of 12.1 is rams and 2.6 ms is the bolt
  sweep (about 220 bolts); in transit, with no bolt at all, rams are 4.9 of 5.1 ms (0.57, 1.55, 4.91 ms at 25, 50, 100: quadratic).
- Flight (the flight model, bolts, `Main`) grows linearly (1.8 ms at 50, 3.9 ms at 100); Jolt and the body sync are under 2 ms
  at 100; the wings and waves (late) are small.

**Frame sleep** (review round 1). A bench run turns the engine's 6.9 ms sleep between headless frames off so the body sync can
be timed, which keeps the main thread busy and its core awake; the shipped game idles between frames. The same furball runs
with the engine's own sleep kept (`sleep=keep`, seeds 1-3, run alternately with `sleep=0`):

| furball | tick median ms (three runs) | median less the sync | p99 ms | mean ms | verdicts |
|---|---|---|---|---|---|
| 20, sleep off (the bench) | 6.95 (6.95, 7.01, 6.81) | about 6.80 | 8.12 | 7.03 | 3/3 pass |
| 20, sleep kept | 7.13 (7.13, 7.16, 7.05), no sync in it | 7.13 | 11.95 | 7.89 | 2/3 pass (p99 12.02 ms) |
| 25, sleep off (the bench) | 9.64 (9.59, 9.66, 9.64) | about 9.43 | 11.30 | 9.77 | 0/3 |
| 25, sleep kept | 9.48 (9.42, 9.51, 9.48), no sync in it | 9.48 | 12.30 | 9.71 | 0/3 |

The median moves by 0 to 5 % (about the run spread at 25, above it at 20), but the tail does not: with the sleep kept, the p99
rises from 8.1 to 12.0 ms at 20 ships and from 11.3 to 12.3 ms at 25. The scripts themselves are slower right after a sleep
(at 20 ships targeting's p99 is 5.2 against 3.2 ms and the AI's 4.5 against 2.5 ms; the engine's own worst tick per second says
the same, 12 against 8 ms), so this is the CPU waking up, not the probe. It leans the baseline optimistic: with the game's own
idle, 20 ships sit on the p99 budget's edge (two runs of three pass), so today's limit is about 20 ships, not 20 to 25. The
bench keeps the sleep off so cycles compare like with like; read its p99 at low load as a best case.

**Spread far from the origin** (review round 1). Spread's lattice puts the farthest fight 47 km from the origin at 500 ships
(about 37 km at 300), not 100 km. The nearest fight and the three farthest of the 500-ship lattice, flown alone for 31 s (48
ships, cheap ticks): 117 hits, 72 m/s mean speed and an attack/evade mix of 79/21 % near the player, against 87-122 hits,
63-68 m/s and 71-76 % attack 46-47 km out, no position or velocity ever non-finite. Fights that far out behave like the near
one, so large-N spread numbers are not skewed by float precision.

Checks on the harness: the engine's own worst physics step of each second (`Performance.TIME_PHYSICS_PROCESS`) agrees with the
probe's worst tick per 60 ticks within noise in every run (the engine's is 0.3-5.4 % lower, as a worst over one wall second
against a worst over 60 ticks should be; 111.0 against 114.9 ms at furball 100). The stage timers cost little against what they time: `bench furball 100 30 probe=paired` (30 blocks with them on, 29
off, half a second each) gave a paired difference of +255 us on a 109 ms tick (0.2 %); the first baseline's run gave +48 us.
Both are noise next to stages of milliseconds.

### Cycle 1 (M4-T02, 2026-11-02): only the player's targeting keeps a list

**Before.** No game code changed between the baseline and this cycle's base (`14acadd`, only the harness), so the baseline's
sweep is the before: max N 0 in every layout, headline 0, the real ceiling 20 ships. For the profile I re-ran, on the base,
`scripts/bench.sh m4_c1_profile_low` at 20 and 25 ships (seed 1, every layout, 5 s + 30 s) for the stage breakdown the baseline
only has at 50 and 100, and then short instrumented runs (temporary timers inside the targeting gather, the AI driver's step and
the ram resolver, 3 s + 12 s, seed 1, never committed) at 25, 50 and 100. The re-runs agree with the baseline (furball 25:
9.60 against 9.63 ms).

| layout | N | tick | ai | (scan) | flight | targeting | resolvers | (ram) | physics |
|---|---|---|---|---|---|---|---|---|---|
| furball | 20 | 7.13 | 1.93 | 0.68 | 0.79 | 3.00 | 0.86 | 0.62 | 0.50 |
| furball | 25 | 9.72 | 2.52 | 0.86 | 0.95 | 4.47 | 1.14 | 0.86 | 0.58 |
| spread | 20 | 6.89 | 1.77 | 0.64 | 0.77 | 2.96 | 0.83 | 0.61 | 0.49 |
| spread | 25 | 9.62 | 2.33 | 0.85 | 0.95 | 4.46 | 1.21 | 0.86 | 0.60 |
| transit | 20 | 6.10 | 1.42 | 0.56 | 0.68 | 2.99 | 0.49 | 0.43 | 0.38 |
| transit | 25 | 8.31 | 1.75 | 0.68 | 0.83 | 4.45 | 0.64 | 0.57 | 0.46 |

(mean ms per tick, one run each). What grows, with the baseline's 50 and 100:

- **Targeting** is 3.00, 4.47, 16.75 and 73.98 ms at 20, 25, 50 and 100 ships in the furball and within 1 % of that in the
  other layouts: 1.49 times for 1.25 times the ships, then 3.7 and 4.4 times per doubling, so quadratic, and 42 % of the tick
  at 20 ships, 46 % at 25, 68 % at 100. Inside it (furball 25 and 100): 24.7 and 95 gathers per tick, each over 30.8 and 105.7
  targetables; building the `TargetInfo`s took 3.62 and 53.10 ms (5.4 us each: three `Damageable.of` walks over the ship's
  children, the zone severities and the object), copying the list in `TargetingSystem.update` 0.48 and 9.73 ms, the active
  filter 0.27 and 3.79 ms, the group fetch 0.02 and 0.15 ms. Only the player's list is read every frame (the HUD and the
  radar); an AI ship reads its selection's id, and `AiPilot` picks its target from its contacts and selects it by id when it
  changes.
- **The AI** is 1.93, 2.52, 6.18 and 17.64 ms in the furball. At 100 ships the driver's `perceive` costs 6.39 ms in the
  furball with 105 contacts per ship, 6.07 ms in spread with 12 and 4.10 ms in transit with 3.5: the scan costs the same however
  few a ship sees. The brains' `think` is 7.59, 3.96 and 2.89 ms, avoidance 2.18, 0.56 and 0.32 ms, the selection and the
  commands under 0.7 ms (at 50: perceive 2.38, 2.38 and 1.70 ms, think 2.69, 1.90 and 1.31 ms).
- **The ram resolver** is 0.62, 0.86, 2.68 and 9.46 ms: its swept pass over every pair of hulls is 2.17 ms at 50 and 7.76 ms
  at 100 in the furball, 7.74 ms in spread and 4.12 ms in transit, the hull gather and Jolt's contacts 0.3 to 0.6 ms.

**Candidates**, ranked by confidence that they raise the headline max N:

1. **Only the player's targeting keeps a candidate list** (built). Evidence: the targeting stage above, the largest at every
   count and the same in every layout, nearly all of it `TargetInfo`s nobody reads. Predicted: targeting falls to about 0.2,
   0.5 and 1.0 ms at 25, 50 and 100 ships (the player's list alone), so the tick falls by about 4.3 ms at 25 (9.6 to 5.3), 16.3
   ms at 50 (29.0 to 12.7) and 73 ms at 100 (109 to 36) in every layout. Max N 0 to 25 in every layout, headline 25 (50 still
   about 13 ms); the ceiling below the sweep 20 to about 35. Behaviour risk: low, the same selections by construction, checked
   side by side.
2. **A broad phase for the ram resolver's swept pass.** Evidence: 2.2 ms at 50 and 7.8 ms at 100 in the fights, quadratic,
   while a tick's sweep reaches only the closing speed times one tick plus the two radii (tens of metres) and nearly every pair
   is hundreds of metres apart. Predicted: about 2.0 ms less at 50 and 7 ms at 100 in the furball and spread, 3.8 ms at 100 in
   transit; after candidate 1 the ceiling about 35 to 40, max N still 25. Behaviour risk: none if the filter is conservative
   (any pair that could meet this tick, or that Jolt holds in contact, still gets the exact test and `keep_touching`).
3. **The contact scan by space instead of by list.** Evidence: `perceive` costs the same in spread (12 contacts) as in the
   furball (105): `contacts_for` walks every body for every ship outside the furball's fast path, `ContactScan.shared()` checks
   that every body is still alive on every driver's call (O(N) per ship, twice with the broadcasts) and `_body_ids.find` is
   O(N). Predicted: 4 to 5 ms less at 100 in spread and transit, 1.5 ms at 50, but only 1 to 2 ms at 100 in the furball, where
   every ship is in range, so it moves spread and not the furball that sets the headline; third for that. Behaviour risk: none
   if the contacts keep their order (brains and avoidance may break ties by it).

Looked at and not ranked: a lower think rate for far or idle ships (the AI drivers are 46 % of the furball tick at 50 once
targeting is gone, but it trades behaviour, so later cycles weigh it with the numbers after candidates 2 and 3); keeping the
`Damageable` in the `Targetable` (a constant factor on the `TargetInfo`s still built: the player's list and each AI ship's
perceived target, about 0.5 ms each at 100); nearest-k contacts (a behaviour trade, furball only).

**Test** (`0438c56`, before the change): `tests/integration/test_targeting_scale.gd`. `TargetInfo.built_count` counts every
`TargetInfo` built; in a fight of 24 AI ships (`AiPilot`, ally and raider profiles, seeded) plus the player, the test failed
with 600 per tick against a linear bound of 75, and an AI ship's `candidates()` returned the last tick's list instead of the
targets as they are. Six behaviour tests passed before and after: a selection that leaves the sensors, turns inactive or is
freed clears in the refresh and says so, a broadcast stretches the reach, an id out of reach is refused and the selection
kept, the nearest hostile wins over a nearer neutral, two hostiles at the same range go to the lower id.

**Change** (`2e83ca3`): `TargetingController.keeps_candidates`, set by `ShipAssembly` from `is_player`. The player's controller
rebuilds its list every tick as before. Every other one checks only its selection each tick and builds a list when asked:
`candidates()`, the target edges and names gather on demand, `select_id` checks the one target, and `select_nearest_hostile`
walks the targetables without building a `TargetInfo`. Design in `docs/architecture.md` §17.2. With it the test counts 24
`TargetInfo`s per tick (the player's list), and a controller of each kind run side by side over 400 seeded steps of moving,
hiding and selecting gives the same answers, selections and signals (a mutation that drops the broadcast reach makes that test
fail 97 times).

**After**: `scripts/bench.sh m4_c1_after` on `2e83ca3` (the same settings as the baseline, nothing else heavy running), plus
the counts below the sweep (`m4_c1_after_below` at 30, 35 and 40, `m4_c1_after_transit45`). **Max N: furball 25, spread 25,
transit 25; headline 25** (was 0). Every layout passes 25 on every run and fails 50 on every run, so each stopped after 50
and 100. The ceiling below the next sweep count: furball 30, spread 35, transit 45 (was 20 in all three).

| layout | N | runs passed | tick median ms (three runs) | p99 ms | behind real time | worst rebase tick ms | worst shift ms |
|---|---|---|---|---|---|---|---|
| furball | 25 | 3/3 | 5.44 (5.36, 5.49, 5.44) | 6.76 | 0.00 % | 7.07 | 0.45 |
| furball | 30 | 3/3 (below the sweep) | 7.01 (7.01, 7.01, 7.19) | 8.38 | 0.01 % | 8.75 | 0.78 |
| furball | 35 | 0/3 (below the sweep) | 8.52 (8.52, 8.57, 8.51) | 10.27 | 0.00 % | 10.95 | 0.93 |
| furball | 50 | 0/3 | 13.03 (13.03, 13.11, 12.99) | 16.19 | 0.00 % | 16.55 | 1.02 |
| furball | 100 | 0/3 | 34.57 (34.68, 34.41, 34.57) | 42.42 | 54.3 % | 42.82 | 2.31 |
| spread | 25 | 3/3 | 5.28 (5.28, 5.25, 5.40) | 6.62 | 0.03 % | 6.91 | 0.71 |
| spread | 35 | 3/3 (below the sweep) | 7.84 (7.94, 7.84, 7.77) | 9.99 | 0.00 % | 10.29 | 0.94 |
| spread | 40 | 0/3 (below the sweep) | 9.25 (9.25, 9.20, 9.45) | 12.03 | 0.00 % | 12.91 | 1.03 |
| spread | 50 | 0/3 | 11.92 (11.92, 11.90, 12.04) | 15.13 | 0.00 % | 15.83 | 1.36 |
| spread | 100 | 0/3 | 28.84 (28.84, 28.91, 28.78) | 38.09 | 46.0 % | 40.06 | 2.67 |
| transit | 25 | 3/3 | 4.10 (4.10, 4.12, 4.10) | 4.78 | 0.00 % | 4.91 | 0.43 |
| transit | 45 | 3/3 (below the sweep) | 7.53 (7.53, 7.53, 7.50) | 9.12 | 0.01 % | 11.34 | 2.17 |
| transit | 50 | 0/3 | 8.44 (8.38, 8.46, 8.44) | 10.05 | 0.01 % | 10.34 | 1.07 |
| transit | 100 | 0/3 | 18.84 (18.84, 18.82, 18.84) | 22.31 | 17.6 % | 23.57 | 2.18 |

Every failure from 35 to 50 is the tick median, with the p99 on some runs at 40 and on every fight run at 50 (transit 50
fails on the median alone); the rebase ticks and real time fail only at 100. At 50 the simulation now keeps real time in every
layout, and at 100 it falls 18 to 54 % behind (82 to 85 % before). The spread at 30 and the
transit at 30 to 40 passed too (6.47, 5.02, 5.77, 6.59 ms). With the engine's own frame sleep kept (`sleep=keep`, the furball,
seeds 1 to 3), 25 and 30 ships still pass on every run: medians 5.75 and 6.92 ms, p99 9.23 and 9.47 ms (12.0 ms was the
baseline's p99 at 20 ships with the sleep kept), so the furball's 30 is not an artefact of the bench's busy loop.

**Stage breakdown**, in the baseline's form (mean ms per tick, the median over three runs). At 50 ships the simulation now
keeps real time, so the sync is timed in every tick; the baseline's 50-ship sync was a lower bound, which is why `physics`
reads higher there.

| layout | N | tick | ai | (scan) | (think) | flight | targeting | resolvers | (hit) | (ram) | late | physics | (sync) | other (unaccounted) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| furball | 50 | 13.18 | 6.19 | 2.07 | 6.10 | 1.71 | 0.47 | 3.57 | 0.86 | 2.70 | 0.05 | 1.15 | 0.43 | 0.05 |
| furball | 100 | 35.37 | 17.05 | 5.65 | 16.86 | 3.41 | 0.96 | 12.15 | 2.58 | 9.46 | 0.06 | 1.70 | 0.31 | 0.10 |
| spread | 50 | 12.19 | 4.85 | 1.88 | 4.76 | 1.81 | 0.50 | 3.55 | 0.83 | 2.71 | 0.05 | 1.36 | 0.56 | 0.05 |
| spread | 100 | 29.75 | 10.81 | 4.87 | 10.61 | 3.58 | 1.01 | 12.37 | 2.83 | 9.49 | 0.07 | 1.81 | 0.24 | 0.11 |
| transit | 50 | 8.57 | 3.72 | 1.50 | 3.63 | 1.54 | 0.44 | 1.69 | 0.10 | 1.57 | 0.27 | 0.88 | 0.42 | 0.02 |
| transit | 100 | 19.19 | 8.16 | 3.65 | 7.98 | 2.96 | 0.88 | 5.14 | 0.19 | 4.92 | 0.54 | 1.48 | 0.13 | 0.03 |

**Gain against the prediction:**

| | predicted | measured (furball, spread, transit) |
|---|---|---|
| targeting at 50 / 100 | about 0.5 / 1.0 ms | 0.47, 0.50, 0.44 / 0.96, 1.01, 0.88 ms (from 16.5-17.0 / 72.7-74.4) |
| tick median at 25 | 9.6 to 5.3 ms (-4.3) | 9.63 to 5.44 (-4.19), 9.41 to 5.28 (-4.13), 8.13 to 4.10 (-4.03) |
| tick median at 50 | 29.0 to 12.7 ms (-16.3) | 28.99 to 13.03 (-15.96), 27.63 to 11.92 (-15.71), 24.17 to 8.44 (-15.73) |
| tick median at 100 | 109 to 36 ms (-73) | 109.07 to 34.57 (-74.5), 102.83 to 28.84 (-74.0), 91.55 to 18.84 (-72.7) |
| max N | 0 to 25, headline 25 | 25, 25, 25; headline 25 |
| ceiling below the sweep | 20 to about 35 | 30, 35, 45 |

The gain is what was predicted at every count: within 0.3 ms at 25, 0.6 ms at 50 and 1.5 ms at 100. The furball's ceiling is 30, not
35: what is left grows faster than linearly (the AI and the rams).

**Behaviour changes: none intended, none seen.** Seeded runs give identical outcomes before and after: `bench furball 25 10
seed=1` (bolts in flight 67.658 on average, ship pairs 0.587, behaviours attack 16, evade 6, idle 3, and every ship's range
from the player the same to the metre) and `bench spread 50 6 seed=2` (bolts 251.839, pairs 2.294, behaviours and ranges the
same); two runs of the base were identical to each other too, so the comparison means something. One edge differs inside a
tick and is listed for the maintainer: a target that left play or reach since the last refresh can no longer be selected by id
before the next refresh (the last tick's list allowed it until the refresh at priority 100 cleared it). The first full suite run
was stopped partway through GUT at the maintainer's request; the controller ran it again on `m4` after the merge (`ae6d02a`):
GUT 2187 of 2189 passing, 0 failing, 2 pending (the AC12 balance tests, as before), Python 363 OK, AC13's paired budget held.
The new test file alone: 9/9; 25 targeting-related scripts: 307/307 passing, 2706 asserts.

**What is left for cycle 2** (re-rank with these numbers): at 50 ships the AI is 47 % of the furball tick (the scans 2.1 ms,
the brains and avoidance 4.0 ms) and the resolvers 27 % (rams 2.7 ms); at 100 the AI is 17.1 ms, the rams 9.5 ms and the bolt sweep 2.6 ms.
To pass 50 the furball needs 5 ms off its 13 ms median, more than candidate 2 or 3 gives alone.

### Cycle 2 (M4-T03, 2026-11-02): a broad phase for the ram resolver

**How this cycle measured** (maintainer, 2026-11-02): with `scripts/bench_quick.sh` (furball and spread ramped through 10, 15,
20, 25, 30, 40, 50, 75, 100, 150 ships; **one run of seed 1, 2 s of warm-up and 6 s measured per count**, so indicative, not
the sweep's verdict) for the ceiling, and single `bench <layout> <n> 10 seed=1` runs (5 s of warm-up, 10 s measured) at 50
and 100 ships in all three layouts for the stage breakdown. No full sweep, so no max N moves in this entry: the sweep's
numbers stay cycle 1's (headline 25). Every run was pinned to cores 0-11 and held both bench locks (`/tmp/m5-godot.lock`,
`/tmp/scs-bench.lock`), so no other Godot run overlapped it; the before and after runs were taken within 15 minutes of each
other (12:00 to 12:20). The base is `0db8953` plus the failing test (`314dab4`) and the release-build script (`968cd29`), no
game change since cycle 1.

**Before** (`m4_c2_before2_quick`, `m4_c2_before_stages`). Quick check: furball and spread both hold the budget up to 30 ships
and fail at 40 (tick median 11.06 and 10.96 ms); an earlier quick check of the same code, at 10:37 before the second lock
existed, gave the same ceilings and 40-ship medians within 0.13 ms. Single runs at 35 ships: 9.26 ms (furball) and 9.30 ms
(spread). Stage breakdown, mean ms per tick (one run each; the median tick in the second column):

| layout | N | tick median | tick mean | ai | (scan) | (think) | flight | targeting | resolvers | (hit) | (ram) | late | physics | (sync) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| furball | 50 | 14.30 | 14.41 | 6.56 | 2.28 | 6.46 | 1.99 | 0.55 | 3.89 | 1.09 | 2.78 | 0.06 | 1.30 | 0.31 |
| furball | 100 | 37.82 | 38.34 | 18.13 | 6.19 | 17.92 | 3.78 | 1.09 | 13.29 | 3.00 | 10.24 | 0.07 | 1.85 | 0.25 |
| spread | 50 | 12.70 | 12.90 | 5.07 | 2.06 | 4.97 | 1.87 | 0.51 | 3.91 | 1.12 | 2.76 | 0.06 | 1.42 | 0.50 |
| spread | 100 | 30.73 | 32.10 | 11.57 | 5.45 | 11.37 | 3.77 | 1.05 | 13.67 | 4.05 | 9.57 | 0.07 | 1.84 | 0.23 |
| transit | 50 | 8.57 | 8.68 | 3.71 | 1.49 | 3.62 | 1.56 | 0.45 | 1.75 | 0.10 | 1.63 | 0.28 | 0.93 | 0.44 |
| transit | 100 | 19.30 | 19.65 | 8.34 | 3.72 | 8.15 | 3.07 | 0.92 | 5.18 | 0.19 | 4.95 | 0.57 | 1.54 | 0.14 |

These 10 s runs read about 1 ms higher at 50 ships than cycle 1's 30 s sweep (furball 14.30 against 13.03 ms); the cycle
compares them only with each other. The profile agrees with cycle 1's: the AI is the largest stage (46 % of the furball tick
at 50, 47 % at 100), and the rams are the second at 100 ships in every layout (10.2, 9.6 and 5.0 ms) and grow with N squared
(2.8 to 10.2 ms for twice the ships), while the bolt hits are 1.1 ms at 50 and 3.0 to 4.1 ms at 100.

**Candidates**, ranked by confidence that they raise the headline, against the plan the maintainer set for the cycles left
(Q6: cycle 3 the think rate with nearest-k contacts, cycle 4 the contact scan in native code):

1. **A broad phase for the ram resolver's swept pass** (built). Evidence: the rams above, N squared and the same per pair in
   every layout; in the test below a spread-out fleet of 24 ships has all 276 of its pairs looked at every tick, though every
   pair is at least 250 m apart. Predicted: the rams fall to the hull gather and Jolt's contacts, about 0.4 ms at 50 and
   0.8 ms at 100, so the tick falls by about 2.4 ms at 50 and 9 ms at 100 in the fights and 1.3 and 4.2 ms in transit. The
   quick check's ceiling stays 30 in both layouts: 40 ships needs 11.0 ms down to 8, and the rams at 40 are only about
   1.8 ms; 35 ships comes close. Behaviour risk: none if the filter is conservative (below). Confidence: high, 90 %, for the
   stage; low, 20 %, that the quick check's ceiling moves a step.
2. **The AI think rate with nearest-k contacts** (cycle 3, Q8). Evidence: after candidate 1 the AI is about 55 % of the
   furball tick at 50 ships and 64 % at 100; the brains and avoidance (think less scan) are 4.1 ms at 50 and 11.4 ms at 100 in
   the furball, growing faster than N with every contact scored. A ship more than 2 km from the player thinking every third
   tick takes most of that off in spread (the player's own fight is one group of twelve) and much of it in the furball, where
   most of a 5 km ball is beyond 2 km; nearest-k caps the furball's per-contact growth. Predicted: the AI about halved in the
   furball and cut by about two thirds in spread, enough to bring 40 and likely 50 ships under 8 ms. Behaviour risk: the one
   the maintainer accepted (up to 50 ms slower reactions far from the player; far contacts ignored when choosing); AC13 must
   hold. Confidence: high, 80 %, that it moves the ceiling at least one step.
3. **The contact scan in native code** (cycle 4, Q9, N0 then N1). Evidence: the scan inside the AI costs 2.3 ms at 50 and
   6.0 ms at 100 in the furball, and nearly as much in spread (5.4 ms) though a spread ship sees 12 contacts, not 100.
   Predicted: 10 to 50 times faster, so about 2 ms off at 50 and 5 ms at 100 in every layout, less if cycle 3's think rate has
   already cut how often far ships perceive. Behaviour risk: none (N1 must be bit-identical). Confidence: high that the scan
   gets much cheaper, 85 %; medium, 60 %, that it moves the ceiling on its own after cycle 3, and it carries a toolchain.

Cycle 1's unbuilt candidates, ranked again: its candidate 3 (the contact scan by space in GDScript) is replaced by the native
scan (Q9 drops the GDScript grid). Looked at and not ranked: a broad phase for the bolt hits (the hit resolver is now 80 and
84 % of the resolvers at 100 ships in the fights, 3.0 and 4.1 ms, and 1.1 ms at 50; the next resolver cost, but under a step of the
ceiling now, and a natural part of later native work); flight (3.8 ms at 100, linear).

**Test** (`314dab4`, before the change): `tests/integration/test_ram_scale.gd`. In a spread-out fleet of 24 ships 250 m
apart, half still and half crossing at 300 m/s, it counts the pairs the resolver looks at per tick (pairs swept shape by shape,
counted by a subclass of the resolver, plus `RamTracker.keep_touching` calls, counted by a subclass of the tracker). It failed
with 276 per tick (144 swept, 132 kept touching: every pair) against a linear bound of 48 (two per ship). Five behaviour pins
passed before the change and after: a 600 m/s head-on among bystanders destroys both with one tunnelling ram each; at
3 000 m/s closing (50 m per tick), where the two origins are beyond both bounding spheres at each end of the tick of the hit,
both are still destroyed; a glancing pass 15.40 m abreast at 600 m/s lands and 15.60 m does not (the edge, sampled on the base,
lies between 15.45 and 15.50 m); a 20 m/s scrape with the wings overlapping is a contact ram on each hull, never a tunnelling
one, and its pair is kept touching while Jolt holds it; two raiders that take a swept ram, are pulled 300 m apart and sent back
take a second ram each, once per meeting. A sixth pin came with the change (below).

**Change** (`a894c9b`): `RamBroadPhase` (pure, `src/combat/ram_broad_phase.gd`) boxes each hull's bounding sphere along its
path through the tick, grown by a metre, and sorts and sweeps the boxes along x. Only the overlapping pairs, plus every pair
Jolt reported touching in its last step, reach the resolver's per-pair code, in the full pass's order (a ram earlier in the
pass can destroy a hull that a later pair holds). Why it changes nothing: a pair whose boxes do not overlap cannot pass the
resolver's first exact test (the two bounding spheres meeting over the tick), so its shape sweep would have found nothing; and
`RamTracker.keep_touching` acts only on a pair Jolt holds in contact, and those are always looked at. So the tracker gets every
call that matters, and a skipped pair stops touching exactly when it did before. Design in `docs/architecture.md` §17.3. With
it the work-count test passes (no pair of the spread-out fleet is near another). `tests/unit/test_ram_broad_phase.gd` checks
every candidate against the resolver's sphere test on 40 seeded crowds of 60 hulls at up to 1 500 m/s near the origin and again
45 km out, the order, the far pairs left out and the contact pairs always in. Two mutations were tried and caught: boxes
without the bounding radius (the unit tests and the glancing pin fail), and the contact pairs dropped (caught by the sixth pin,
`test_a_pair_jolt_holds_in_contact_is_kept_touching_whatever_its_bounding_spheres`, which shrinks the spheres so only Jolt's
report can bring the pair in; real hulls in contact are always inside their spheres, so this path is a safety net).

**After** (`m4_c2_after_quick`, `m4_c2_after2_quick`, `m4_c2_after_stages`, `m4_c2_after35`, `m4_c2_before35`):

| quick check | furball ceiling | furball 40 ms | spread ceiling | spread 40 ms |
|---|---|---|---|---|
| before (two runs) | 30, 30 | 10.93, 11.06 | 30, 30 | 11.04, 10.96 |
| after (two runs) | 30, 30 | 9.46, 9.62 | 30, 30 | 9.21, 9.51 |
| single run at 35, before to after | | 9.26 to 8.10 | | 9.30 to 8.19 |

The quick check's ceiling does not move (30 in both layouts, four quick checks agree), so the step is not noise either way.
Every count's median falls (furball 25: 5.92 to 5.21 ms, 50: 14.62 to 12.19 ms, 100: 39.69 to 30.48 ms), 35 ships now misses
the 8 ms median by 0.10 and 0.19 ms (p99 9.9 and 10.5 ms hold), and both layouts now hold 30 FPS at 100 ships (31.7 and 35.6)
and fall under it at 150 (at 100 before).

| layout | N | tick median | tick mean | ai | (scan) | (think) | flight | targeting | resolvers | (hit) | (ram) | late | physics | (sync) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| furball | 50 | 11.27 | 11.64 | 6.46 | 2.25 | 6.36 | 1.86 | 0.50 | 1.46 | 1.08 | 0.37 | 0.05 | 1.25 | 0.49 |
| furball | 100 | 27.18 | 27.66 | 17.57 | 5.99 | 17.38 | 3.55 | 1.00 | 3.70 | 2.95 | 0.71 | 0.06 | 1.66 | 0.23 |
| spread | 50 | 9.88 | 10.16 | 4.95 | 2.02 | 4.86 | 1.80 | 0.48 | 1.51 | 1.12 | 0.36 | 0.05 | 1.31 | 0.55 |
| spread | 100 | 21.38 | 22.89 | 11.37 | 5.38 | 11.18 | 3.66 | 1.02 | 4.90 | 4.10 | 0.75 | 0.06 | 1.75 | 0.23 |
| transit | 50 | 7.10 | 7.28 | 3.68 | 1.48 | 3.59 | 1.54 | 0.44 | 0.48 | 0.10 | 0.36 | 0.27 | 0.86 | 0.40 |
| transit | 100 | 14.76 | 15.13 | 8.19 | 3.67 | 8.01 | 2.98 | 0.89 | 0.92 | 0.19 | 0.70 | 0.53 | 1.58 | 0.20 |

Transit at 50 ships passes the budget in its run (median 7.10 ms, p99 9.30 ms; cycle 1's sweep failed it at 8.44 ms), and
transit at 100 now keeps real time (it fell 20 % behind before).

**Gain against the prediction:**

| | predicted | measured (furball, spread, transit) |
|---|---|---|
| rams at 50 | about 0.4 ms | 2.78 to 0.37, 2.76 to 0.36, 1.63 to 0.36 ms |
| rams at 100 | about 0.8 ms | 10.24 to 0.71, 9.57 to 0.75, 4.95 to 0.70 ms |
| tick mean at 50 | -2.4, -2.4, -1.3 ms | -2.77, -2.74, -1.40 ms |
| tick mean at 100 | -9, -9, -4.2 ms | -10.68, -9.21, -4.52 ms |
| quick-check ceiling | stays 30, 30 | 30, 30 |

The rams fell as predicted; the ticks fell slightly more than the rams did (by 0.1 to 1.2 ms), within what single runs
spread. The stage is gone, but it was not enough to move the quick check a step: 35 ships is 0.1 to 0.2 ms over.

**Behaviour changes: none intended, none seen.** Seeded runs give identical outcomes on the base (twice) and after:
`bench furball 25 10 seed=1` (bolts 60.647 on average, pairs 0.497), `bench furball 100 6 seed=1` (bolts 268.447, pairs 1.922,
behaviours attack 70 and evade 30, one ram: the player into NAV ALPHA) and `bench spread 50 6 seed=2` (bolts 177.144, pairs
1.444); every AI ship's behaviour and state line from `state ai`, `state ram` and `state combat` is the same line for line.
Tests (the maintainer's rule for this task, 2026-11-02: focused runs instead of the full suite, which CI runs): 38 GUT files
that touch the ram resolver, the tracker, ram maths, collisions, the hit resolver and AC13's paired budget
(`test_ai_think_time`), each run alone on `a894c9b`: 495 passing, 0 failing, 0 pending. No Python changed. The seeded runs held
one ram between them, so they show little about rams; the case that nothing ram-related moved rests on the unit test against the
resolver's own sphere test and the six pins. The after runs' reports name `968cd29` because the change was not yet committed;
the code they measured is `a894c9b`.

**The release build, measured once** (handoff option 11, M4-T03r). Every number in this log is the Godot 4.7.2 editor build
(debug). The same quick check and stage runs with an exported release build (the official `linux_release.x86_64` template, from
a `git archive` snapshot of `ae6d02a`, before the ram change; `scripts/setup_export_templates.sh` installs the templates and its
header holds every step to repeat the run), in the order debug, release, release, debug, all under both locks:

| furball | editor build (debug) | release export | ratio |
|---|---|---|---|
| quick-check ceiling, furball and spread | 30 | 30 | |
| first count under 30 FPS (furball, spread) | 100, 100 | 150, 150 (100 holds 30.6 to 30.7 FPS; the next count tried is 150) | |
| tick median at 50 ships (quick check, two runs) | 14.33, 14.44 ms | 11.79, 11.85 ms | 1.22x |
| tick median at 100 ships (quick check, two runs) | 39.13, 39.41 ms | 31.60, 31.69 ms | 1.24x |
| stage means at 50 and 100 ships | | | ai 1.22 to 1.26x, flight 1.29 to 1.31x, targeting 1.38 to 1.40x, resolvers 1.24 to 1.26x, physics (Jolt, native) 1.06 to 1.12x |

Every GDScript stage runs 1.2 to 1.3 times faster in the release export; Jolt barely moves. The same workload ran in both (identical
bolts, pairs and rebases), and repeating a binary moved its median by at most 0.6 ms, so the gap is real; the p99 moves 1 to 2 ms
between repeats of one binary. Interpolating the 30 and 40 ship medians, the 8 ms crossing is at about 32 ships for the editor
build and 37 for the release export, so a player's build holds about 17 to 19 % more ships than the numbers in this log. The
comparison is the editor build against the release template; the debug template was not run, so how much comes from dropping debug
checks and how much from leaving the editor is not separated. Later cycles keep measuring the editor build, like for like; the T06
report gives both.

**What is left for cycle 3**: at 50 ships the AI is 56 % of the furball tick (6.46 of 11.64 ms) and 49 % in spread; at 100 it
is 17.6 ms of 27.7. Rams are 3 % of the tick. To pass 40 the furball needs 1.5 ms off its 9.5 ms median, 50 needs 4.2 ms off
12.2.

### Cycle 3 (M4-T04, 2026-11-02): the AI think rate with nearest-k contacts

**How this cycle measured** (Q7, as in cycle 2): `scripts/bench_quick.sh` (furball and spread, one run of seed 1 per count, 2 s
of warm-up and 6 s measured) for the ceiling, and single `bench <layout> <n> 10 seed=1` runs at 50 and 100 ships in all three
layouts for the stages. Every run held both bench locks and was pinned to cores 0-11. The quick check's numbers drift a little
between sessions, so the before was taken again on this cycle's base (`e296d35`, no game change since cycle 2; the runs had one
console readout added, `ai.mean_speed_mps`, which changes nothing in the simulation) rather than taken from cycle 2's after.
Each stage run also printed `state ai`, `state combat` and `state ram` at its end, for the outcome comparison. No full sweep, so no
max N moves in this entry (the sweep's headline stays cycle 1's 25).

**Before** (`m4_c3_before_quick`, `m4_c3_before_stages`, load 2.95). Quick check: furball and spread hold the budget to 30 ships
and fail at 40 (tick median 9.60 and 10.39 ms; cycle 2's after gave 9.46 to 9.62 and 9.21 to 9.51). Stages, mean ms per tick
(one run each; the median tick in the third column):

| layout | N | tick median | tick mean | ai | (scan) | (think) | flight | targeting | resolvers | (hit) | (ram) | late | physics | (sync) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| furball | 50 | 12.25 | 12.36 | 6.65 | 2.31 | 6.55 | 2.01 | 0.56 | 1.53 | 1.11 | 0.39 | 0.06 | 1.49 | 0.57 |
| furball | 100 | 28.55 | 29.23 | 18.18 | 6.18 | 17.97 | 3.91 | 1.16 | 3.84 | 3.00 | 0.79 | 0.07 | 1.96 | 0.27 |
| spread | 50 | 10.28 | 10.54 | 5.08 | 2.06 | 4.98 | 1.89 | 0.52 | 1.51 | 1.11 | 0.38 | 0.05 | 1.44 | 0.60 |
| spread | 100 | 22.24 | 23.48 | 11.55 | 5.42 | 11.35 | 3.79 | 1.08 | 4.96 | 4.12 | 0.79 | 0.07 | 1.90 | 0.25 |
| transit | 50 | 7.27 | 7.41 | 3.72 | 1.50 | 3.63 | 1.57 | 0.44 | 0.48 | 0.10 | 0.36 | 0.27 | 0.91 | 0.44 |
| transit | 100 | 15.00 | 15.32 | 8.27 | 3.71 | 8.09 | 3.03 | 0.92 | 0.93 | 0.19 | 0.71 | 0.54 | 1.59 | 0.17 |

The AI is 54 % of the furball tick at 50 ships and 62 % at 100; inside it the scans are 2.31 and 6.18 ms and the rest (the brains
scoring every contact, avoidance against every contact, the selection) 4.24 and 11.79 ms, 2.8 times for twice the ships. In spread
a ship sees about 12 contacts, yet the AI still grows faster than N (5.08 to 11.55 ms): every ship perceives and thinks every tick.

**Candidates**, ranked by confidence that they raise the headline, against the plan for the cycles left (Q6: cycle 4 is the
contact scan in native Rust behind `ContactScan`, Q9):

1. **The think rate with nearest-k contacts** (built; decided by the maintainer, Q6 and Q8). Evidence: the AI above, the largest
   stage at every count, and its per-contact part growing with N squared in the furball. Predicted (written down before any after
   run was read): in the furball, a ball 5 km across with the player in it, about half the ships are within 2 km, so the think rate
   alone takes the AI to about two thirds; in spread only the player's group of 12 is near, so about half at 50 and 40 % at 100;
   nearest-k (12) helps only the furball (a spread group sees 11). Together: furball 50 AI 6.65 to about 3.3 ms (tick about 9),
   furball 100 18.2 to about 7 ms (tick about 17), spread 50 5.08 to about 2.5 ms (tick about 7.7), spread 100 11.55 to about 4.8 ms
   (tick about 15.5); each half alone about -6 ms at furball 100; the quick check's ceiling 30 to 40 in both layouts. Behaviour risk:
   the one the maintainer accepted (far ships react up to 50 ms later; far contacts ignored when choosing). Confidence: 80 %.
2. **The contact scan in native code** (cycle 4, Q9). Evidence: after candidate 1 the scans are still 1.67 and 3.91 ms of the
   furball's 3.16 and 7.00 ms of AI at 50 and 100 ships (more than half of what is left), and `ContactScan.shared` still checks that
   every body is alive on every driver's call (O(N) per think) before `contacts_for` or `nearest_for` walks every body in GDScript.
   Predicted: 10 to 50 times faster scans, so about 1.4 ms off at 50 and 3.5 ms at 100 in the furball, about the same in spread.
   Behaviour risk: none (N1 must be bit-identical). Confidence: 85 % that the scan gets much cheaper, 60 % that it moves the quick
   check a step.
3. **A broad phase for the bolt hits** (the hit resolver and `incoming_fire`). Evidence: after candidate 1 the hit resolver is the
   largest stage outside the AI that grows faster than N: 1.09 and 3.71 ms at 50 and 100 in the furball, 1.02 and 3.81 ms in
   spread, against about 150 and 320 bolts in flight. Predicted: about 0.8 ms off at 50, 3 ms at 100. Behaviour risk: none if
   conservative (like cycle 2's). Confidence: 70 % for the stage, 35 % that it moves the ceiling alone.

Cycle 2's unbuilt candidates, ranked again: its candidate 2 is this cycle's; its candidate 3, the native scan, stays cycle 4 and
ranks second. Looked at and not ranked: re-running the cheap steering between thinks (below: held commands aim as well in a duel;
it would cost part of the gain); flight (3.7 ms at 100, linear).

**Test** (`d4e7265`, before the change): `tests/integration/test_ai_think_rate.gd`, with the work counts it reads
(`AiPilotDriver.thinks_near`, `thinks_far`, `contacts_max`), the player registry and the four settings entries, nothing reading the
settings yet. Real ships, real physics frames. It failed 7 of 10: with six ships within 1 km of the player and 24 between 3 and
4.3 km, the far ships thought 24 per tick against a bound of 9 (a third plus one); 25 ships in one 800 m crowd handed 25 contacts
per ship to their brains against k plus 2 (14); a far ship thought every tick (30 of 30, against 10) and was given one tick, not
three; the stagger carried 24 a tick, not 7 to 9; a ship leaving 2 km kept thinking every tick; the brain's target 4.4 km out and the
latest attacker were among 19 contacts, not 10; with no player alive a ship thought every tick. The three that passed before and
after: a near ship thinks every tick, a hit wakes a far ship on the next tick, and both settings off give every ship every tick and
every contact. One test was corrected with the change: a far ship's count started one tick early (a physics frame's signal comes
before its drivers run, so the first await had not yet seen the ship's first think).

**Change** (`5d4d267`): `AiThinkRate` (pure: the period, the staggered beat, when a ship thinks) and the driver (design in
`docs/architecture.md` §17.4).
- A ship within `ai_think_near_m` (2 000 m) of the live player thinks every tick; a farther one every third tick at
  `ai_think_far_hz` 20, on a beat set by its driver's place in the tree, so consecutive pool ships share the ticks evenly. Each think
  is given the time since the last. A new pilot or a hit wakes it for the next tick; a lost target or the 2 km line waits at most one
  far period (50 ms). With no player in play, or the player dead, every AI ship thinks at the far rate.
- **What is held**: the ship's last `FlightCommand` and `CombatCommand`, after avoidance. The driver just does not replace them, and
  `Ship` flies a command until the next (edges act once, `fire` holds), so the flight model and Jolt step every tick. Evidence that
  this does not misbehave, so re-running the steering was not needed: four veterans hunting straight-flying drones for 60 s (the
  AC26 duel of `test_ai_slash`, two slashing and two standard, no player, so every ship far) kept their drones in the fire gate
  139.1 s in total at 60 Hz and 137.8 s at 20 Hz (-1 %), fired 286 and 288 shots inside the gate and 2 and 0 outside, and their
  turn rate changed 3 % more per tick (0.00659 against 0.00678 rad/s per tick). A throwaway test, not committed.
- **Avoidance** (D33) runs with the think, against that think's contacts; at 20 Hz its 4 s horizon still sees every threat several
  thinks ahead. Two allies grazing each other (a tunnelling ram of 29 m/s, no damage under god mode) appeared in the after run at
  100 ships; the base shows the same kind (ALPHA 12 into ALPHA 24, four of them in its seed 2 run at 50 ships), so the rate of these
  is within what seeds give (below).
- **Nearest-k**: `ContactScan.nearest_for` gives the nearest `ai_nearest_k` (12) of the contacts in 5 km, by a partial selection
  over the scan's packed positions (no full sort), back in scan order, so a ship that sees 12 or fewer gets `contacts_for`'s very
  list. When the cut leaves something out, the nearest hostile ship joins them, and so do the contacts the brain keeps (its target,
  wingmates, leader and the leader's target, the route's pace ship, its objective and guarded ship by name), the selection and
  whoever hit it in the last 10 s; those lists are built only then. Why the nearest hostile: the first build kept only the nearest
  12 and some furball ships idled with hostiles 1 to 3 km away behind a crowd of friends (3 of 100 at the end of the 100-ship run, 11
  of 50 with k 8); with the rule no ship idles at 100 and the hits come back from 254 to 320 (366 on the base), for 0.2 ms at 50 and
  0.6 ms at 100. k 12 is the evidence's choice among 8, 12 and 16 (below).
- Console: provider `ai` gains `thinks_near`, `thinks_far`, `held`, `contacts_max` and `mean_speed_mps`. Settings `ai_think_rate`,
  `ai_think_near_m`, `ai_think_far_hz`, `ai_nearest_k` (0 = every contact).

**Both settings off is the base, bit for bit**: `bench furball 50`, `spread 50` and `furball 100` (seed 1, 10 s) with
`ai_think_rate` off and `ai_nearest_k` 0 give, against the base, the same `state ai` line for every ship, the same behaviour counts
and mean speed to the centimetre per second, the same hit count and last hit, the same rams and the same mean bolts and pairs
(`m4_c3_off`, and `m4_c3_v2_off` again on the final code).

**After** (`m4_c3_v2_after_quick`, `m4_c3_v2_after_stages`; the first build's runs are `m4_c3_after_*`):

| quick check | furball ceiling | furball 40 / 50 ms | spread ceiling | spread 40 / 50 ms |
|---|---|---|---|---|
| before (`m4_c3_before_quick`, load 2.95) | 30 | 9.60 / 12.79 | 30 | 10.39 / 12.20 |
| after, first build (`m4_c3_after_quick`, load 2.68) | 40 | 6.88 / 8.05 | 40 | 7.32 / 9.47 |
| after, final (`m4_c3_v2_after_quick`, load 1.72) | 40 | 6.77 / 8.70 | 40 | 7.07 / 9.07 |

Both layouts now hold the budget at 40 ships (p99 8.19 and 8.50 ms) and miss it at 50 by 0.7 and 1.1 ms (the first build, without
the nearest hostile kept, missed the furball's 50 by 0.05 ms). Both hold 30 FPS to 100 ships and fall under it at 150 (the first
build's furball held it to 150). The quick check's 35 is not a count it runs.

| layout | N | tick median | tick mean | ai | (scan) | (think) | flight | targeting | resolvers | (hit) | (ram) | late | physics | (sync) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| furball | 50 | 8.42 | 8.45 | 3.16 | 1.67 | 3.09 | 1.90 | 0.51 | 1.49 | 1.09 | 0.38 | 0.05 | 1.29 | 0.55 |
| furball | 100 | 17.55 | 18.23 | 7.00 | 3.91 | 6.86 | 3.74 | 1.04 | 4.52 | 3.71 | 0.76 | 0.06 | 1.76 | 0.25 |
| spread | 50 | 8.06 | 8.13 | 2.92 | 1.44 | 2.85 | 1.87 | 0.51 | 1.42 | 1.02 | 0.38 | 0.05 | 1.31 | 0.57 |
| spread | 100 | 17.42 | 17.40 | 6.06 | 3.20 | 5.93 | 3.71 | 1.03 | 4.62 | 3.81 | 0.77 | 0.06 | 1.79 | 0.25 |
| transit | 50 | 5.60 | 5.67 | 2.01 | 1.02 | 1.96 | 1.59 | 0.45 | 0.48 | 0.10 | 0.37 | 0.28 | 0.84 | 0.40 |
| transit | 100 | 11.35 | 11.61 | 4.16 | 2.20 | 4.05 | 2.99 | 0.90 | 0.93 | 0.19 | 0.71 | 0.55 | 2.05 | 0.63 |

The resolvers rise at 100 ships in the furball (3.84 to 4.52 ms) because the fight there has more bolts in flight (246 to 317);
the AI falls by 11.2 ms. Transit's ships are all far from the player (none in 2 km), so they all think at 20 Hz.

**Each half alone**, AI ms (the think-rate-only runs, `m4_c3_rate_only`, have `ai_nearest_k` 0, a path the final change did not
touch; the nearest-k-only runs, `m4_c3_v2_k_only`, have `ai_think_rate` off, on the final code):

| layout | N | base | think rate only | nearest-k only | both | predicted, both |
|---|---|---|---|---|---|---|
| furball | 50 | 6.65 | 3.73 (-2.92) | 5.61 (-1.04) | 3.16 (-3.49) | about 3.3 |
| furball | 100 | 18.18 | 10.61 (-7.57) | 12.53 (-5.65) | 7.00 (-11.18) | about 7 |
| spread | 50 | 5.08 | 2.83 (-2.25) | 5.48 (+0.40) | 2.92 (-2.16) | about 2.5 |
| spread | 100 | 11.55 | 5.88 (-5.67) | 12.07 (+0.52) | 6.06 (-5.49) | about 4.8 |
| transit | 50 | 3.72 | 1.99 (-1.73) | 3.93 (+0.21) | 2.01 (-1.71) | |

**Fix round 1, nearest-k where it cuts nothing** (`m4_c3_f1_k_only` against `m4_c3_v2_k_only`, nearest-k on and the think rate
off, seed 1, 10 s). `nearest_for` now gathers like `contacts_for` until more than k contacts are in range and only then selects; its
output is unchanged (every `state ai`, hit, ram and mean in `m4_c3_f1_k_only` and `m4_c3_f1_after` matches the v2 runs line for
line, and both settings off still match the base). The scan stage, where `nearest_for` is timed:

| layout | N | base (`contacts_for`) | nearest-k only, v2 | nearest-k only, fix round 1 |
|---|---|---|---|---|
| transit | 50 | 1.50 | 1.57 | 1.54 |
| transit | 100 | 3.71 | 3.81 | 3.79 |
| spread | 50 | 2.06 | 2.33 | 2.29 |
| spread | 100 | 5.42 | 5.80 | 5.70 |

Where nothing is cut (transit, at most 8 in range) nearest-k now costs what `contacts_for` did, within a run's noise. Spread still
pays about 0.2 to 0.3 ms: its ships see up to 17 contacts in range at times (with the cut, `contacts_max` reads 13: the 12 nearest plus one kept), so the cut, the nearest hostile and the keeps
do run there, for little gain. The rest of the AI stage's difference with the think rate off (0.1 to 0.2 ms at 50 ships) is the
driver's own bookkeeping (the player distance and the counts), which the both-settings-off runs show too (spread 50: 5.18 to 5.26
against the base's 5.08 ms). With the think rate on, nearest-k costs spread about 0.1 ms.

**Gain against the prediction:** the furball is where predicted (AI 3.16 against about 3.3 ms at 50, 7.00 against about 7 at 100;
tick medians 8.42 against about 9 and 17.55 against about 17), and each half at furball 100 too (think rate -7.6 against -6, nearest-k
-5.7 against -6). Spread gained less than predicted (AI 2.92 against 2.5 at 50, 6.06 against 4.8 at 100): the per-tick scan
build and the bookkeeping on held ticks are a larger share than I allowed for, and nearest-k costs spread 0.4 to 0.5 ms alone (its
selection loop is dearer than `contacts_for`'s plain one and spread ships sometimes see 13 to 17, so the cut and the keeps run);
with the think rate on that cost falls to 0.1 ms (2.92 against 2.83). The quick check moved as predicted: 30 to 40 in both layouts; 50 is 0.7 to 1.1 ms away.

**Behaviour changes** (the trade the maintainer accepted, Q8, and what came with it):
- Far ships (beyond 2 km of the player, or all of them with no player alive) decide every 50 ms instead of every 16.7 ms: a new
  threat, a lost target or the 2 km line is answered up to 50 ms later; a hit is answered on the next tick as before (then the
  pilot's own reaction time applies).
- Their commands are held between decisions: thrust, turn and the trigger, after avoidance, for two ticks. In a duel this aims as
  well as before (above).
- Avoidance for far ships runs at 20 Hz.
- Ships that see more than 12 contacts choose, avoid and check fire lanes against the nearest 12, the nearest hostile ship, their
  own target, wingmates, leader, objective, guarded ship and latest attacker; farther ones within 5 km are ignored when choosing.
- In the dogfight scenario's seed, `test_ai_ram`'s fight went differently: of its three reckless raiders (RAIDER 4, 5 and 6, BLUE
  wing), RAIDER 6 was shot to 17 % hull by 148 s on the base and then rammed; with the think rate none of the three rammed in
  360 s (RAIDER 6, traced, was never hit), so the test asserted nothing (risky). The ram itself is unchanged: the committed-rammer
  test, its rammers 3 km and more from the player (so at the far rate), hits 10 of 10. Fix round 1 split the dogfight test in two:
  the full dogfight asserts that no pilot below reckless rams, and a second run of the scenario leaves RAIDER 4 alone at 20 % hull
  against ALPHA with the player 30 km off, where it chooses the ram from the fight at the far rate (at 20.3 s).
- The far rate is counted in physics ticks, so `Engine.time_scale` stretches it in sim time: at the integration tests' 4 to 6
  times speed-up (and the console's time scale) a far ship decides every 0.2 to 0.3 s of sim time, not every 50 ms, and near
  ships every 0.07 to 0.1 s. Results from sped-up runs show more of the far rate's cost than real time does (the lost dogfight ram
  above is partly this).

**Outcome comparison**, seeded runs (seed 1, 10 s measured after 5 s of warm-up and 30 s of scenario; hits and rams are session
totals at the end, behaviours and mean AI speed at the end; bench ships are invulnerable, so no kills):

| run | | hits | rams | behaviours at the end | mean speed m/s | bolts in flight (mean) | ship pairs (mean) |
|---|---|---|---|---|---|---|---|
| furball 50 | before | 157 | 1 | attack 41, evade 9 | 72.3 | 149.5 | 1.22 |
| | after | 140 | 1 | attack 34, evade 15, idle 1 | 76.6 | 152.7 | 1.12 |
| furball 100 | before | 366 | 1 | attack 73, evade 27 | 73.4 | 245.6 | 1.99 |
| | after | 320 | 3 | attack 76, evade 24 | 68.9 | 317.0 | 2.50 |
| spread 50 | before | 241 | 1 | attack 33, evade 17 | 64.6 | 153.4 | 1.31 |
| | after | 246 | 1 | attack 24, evade 26 | 61.4 | 136.7 | 1.28 |
| spread 100 | before | 429 | 1 | attack 61, evade 39 | 79.6 | 341.8 | 3.02 |
| | after | 375 | 1 | attack 60, evade 40 | 72.0 | 320.7 | 2.63 |
| transit 50 and 100 | before and after | 0 | 1 | the same (formation and follow path) | 80.0 | 0 | 0 |

The one ram in most runs is the player flying into NAV ALPHA. The fights still look like fights: the same mix of attack and evade,
speeds within 10 %, hits 11 % lower to 2 % higher at 50 ships and about 13 % lower at 100. How much of the hit loss is the far rate: with every
ship far (`ai_think_near_m` 0, nearest-k off), over three seeds, the hits fall 15 % at 50 ships (157, 149, 138 to 150, 102, 125) and
21 % at 100 (366, 309, 349 to 240, 253, 310), with the same attack and evade mix and speeds; rams 1 to 5 per run on the base and 1
to 2 with every ship far. Since the duel aims as well at 20 Hz, I read the loss as decisions taken up to 50 ms late in a crowd (whom
to attack, when to evade), not as wobble. It is the cost of the rule as set; a far radius larger than 2 km would buy hits back.

**Choosing k** (`m4_c3_v2_k8`, `m4_c3_v2_k16`, furball, both halves on): 

| k | furball 50: AI ms, tick median | furball 100: AI ms, tick median | hits 50 / 100 | idle at the end 50 / 100 | contacts max |
|---|---|---|---|---|---|
| 8 | 3.12, 8.51 | 6.87, 17.98 | 133 / 437 | 1 / 1 | 11 / 12 |
| 12 | 3.16, 8.42 | 7.00, 17.55 | 140 / 320 | 1 / 0 | 15 |
| 16 | 3.30, 8.59 | 7.19, 17.83 | 156 / 283 | 1 / 1 | 19 |

With the nearest hostile kept, k moves the AI by only 0.2 to 0.3 ms between 8 and 16, inside one run's noise for the tick, and the
outcomes move by more between seeds than between k (furball 100's hits run 283 to 437). So k is chosen by the setting: 12 is a full
squadron's fight, so a 6-against-6 (spread's groups) is never cut, which 8 would; 16 costs the most. Before the nearest-hostile
rule, k 8 left 11 of 50 ships idle and slowed the fight to 60 m/s (`m4_c3_k8`).

**Tests** (focused, Q10; no full suite, CI runs it after the push): 57 GUT files run alone, every file that covers the AI driver,
brains, behaviours, avoidance, the fire lane, perception, the contact scan, wings, formations, routes, the pools, the settings and
console, the new tests, AC13's paired budget (`test_ai_think_time`), `test_ai_ram` and `test_dogfight`: 692 passing, 0 failing, 2
pending (the AC12 balance tests of `test_dogfight` and `test_m3_sandbox`, as before), none risky. AC13's paired budget held; the
dogfight's seeded determinism test gave 0.000000 m twice. No Python changed.

### Cycle 4 (M4-T05, 2026-11-03): the contact scan in native code

**N0, the toolchain and the seam (T05a).** No gameplay change. `native/` is a Rust crate (`scs_native`, gdext pinned `=0.5.5`
with `api-4-7`, Rust 1.99.1 pinned by `native/rust-toolchain.toml`) with one trivial class, `ScsNativeProbe`.
`scripts/build_native.sh` builds it into `bin/libscs_native.so` when the library is missing or older than the crate, and
`run_tests.sh` and CI call it before the import. GDScript reaches native classes only through `NativeLib` and falls back to its
own code when the library is missing or `perf_native` is off (`docs/architecture.md` §17.5). Build times on the maintainer's
machine (20 threads): cold 56 s (60 s with the crate downloads), 0.4 s after an edit to the crate, 0.02 s when nothing changed.
CI's first run with the native build (run 41600109943 on `40c83c4`, green: shard 1 1 087 passing and 1 pending, shard 2 1 156
passing and 1 pending, the AC12 tests) missed both caches (Godot and native): the native build step took 82 s on shard 1
(cargo 1 m 14 s) and 111 s on shard 2 (cargo 1 m 42 s), `run_tests.sh` then found the library up to date, and the shards took
20 m 22 s and 14 m 41 s against the 45-minute limit. A warm run's time (cache hit) comes from the next push and is still
pending. The boundary (`native bench` on the main scene, debug editor build, three runs, load about
1): a call through the facade with one int costs 0.21 to 0.24 us against 0.08 us for the GDScript method (a direct native call
0.12 us). `in_range` (a packed array of positions in, the indices within 5 km out, about half the points in range) costs 1.0 to
1.1 us at 100 points, 1.5 to 1.6 at 200 and 1.8 to 1.9 at 300 natively, against 2.7, 5.0 and 7.0 us in GDScript (27 to 24 ns a
point): about 0.66 us fixed per native call plus 4 ns a point. At 300 calls a tick of 300 points that is 0.55 ms native against
2.1 ms in GDScript. So a call costs about what 25 points cost in GDScript: T05b's per-ship calls pay off at the furball's sizes,
and anything per contact must stay inside one call.

**How N1 measured** (Q7, as in cycles 2 and 3): `scripts/bench_quick.sh` for the ceiling and single `bench <layout> <n> 10
seed=1` runs at 50 and 100 ships in all three layouts for the stages, all under both bench locks and pinned to cores 0-11, on
the debug editor build. The before was taken again on this task's base (`40c83c4`, the native library built but nothing calling
it). New this cycle: a paired run in one process (`bench` twice per round, `set settings.perf_native true` then `false`, two
rounds), so the native gain is measured without the machine's drift. No full sweep, so the sweep's headline stays cycle 1's 25.

**Before** (`m4_c4_before_quick`, load 0.48; `m4_c4_before_stages`). Quick check: both layouts hold the budget to 40 ships
and miss it at 50 (tick median 8.51 ms in the furball, 8.71 in spread); both fall under 30 FPS at 150. Stages, mean ms per tick:

| layout | N | tick median | tick mean | ai | (scan) | (think) | flight | targeting | resolvers | (hit) | (ram) | late | physics | (sync) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| furball | 50 | 8.23 | 8.29 | 3.13 | 1.65 | 3.07 | 1.85 | 0.50 | 1.48 | 1.09 | 0.37 | 0.05 | 1.22 | 0.52 |
| furball | 100 | 17.06 | 17.75 | 6.95 | 3.91 | 6.81 | 3.57 | 0.99 | 4.44 | 3.68 | 0.72 | 0.06 | 1.64 | 0.24 |
| spread | 50 | 8.15 | 8.20 | 2.90 | 1.42 | 2.84 | 1.88 | 0.51 | 1.43 | 1.02 | 0.38 | 0.05 | 1.38 | 0.59 |
| spread | 100 | 16.71 | 16.93 | 5.89 | 3.12 | 5.77 | 3.59 | 0.99 | 4.54 | 3.77 | 0.73 | 0.06 | 1.74 | 0.26 |
| transit | 50 | 5.44 | 5.51 | 1.96 | 0.99 | 1.90 | 1.54 | 0.43 | 0.48 | 0.10 | 0.37 | 0.27 | 0.81 | 0.38 |
| transit | 100 | 11.00 | 11.33 | 4.09 | 2.15 | 3.98 | 2.98 | 0.88 | 0.92 | 0.19 | 0.70 | 0.53 | 1.91 | 0.62 |

Inside the scan stage (a throwaway timing build, furball 100, GDScript path, per tick, about 47 thinking ships a tick): building
the scan from the tree 0.61 ms, the freed-body checks 0.16 ms, `nearest_for` 1.26 to 1.53 ms (0.56 ms of it making each
faction's `Contact`s), `incoming_fire` 0.41 to 0.97 ms, the broadcast scan's build 0.31 ms and `broadcasts_for` 0.33 to 0.36 ms
(nearly all of it making `Contact`s for broadcasters nobody hears).

**Candidates**, ranked by confidence that they raise the headline:

1. **N1, the contact scan's queries in native code** (built; decided by the maintainer, Q9). Evidence: the scan is 1.65 and
   3.91 ms of the furball's 3.13 and 6.95 ms of AI at 50 and 100 ships, and the queries are 2.0 to 2.9 ms of the 3.9 at 100.
   Predicted (cycle 3's candidate 2, written before this cycle): about 1.4 ms off at 50 and 3.5 ms at 100 in the furball, about
   the same in spread; the native proposal said about 5 ms at 100. Behaviour risk: none (bit-identical). Confidence: 85 % that
   the scan gets much cheaper, 60 % that it moves the quick check a step.
2. **A broad phase for the bolt hits** (cycle 3's candidate 3, ranked again; native as the proposal's N5 or in GDScript). The
   hit resolver is now the largest stage outside the AI that grows faster than N: 1.09 and 3.68 ms at 50 and 100 in the furball,
   3.77 in spread. Predicted about 0.8 ms off at 50 and 3 ms at 100. Behaviour risk: none if conservative. Confidence 70 % for
   the stage, 40 % that it moves the ceiling alone.
3. **The flight force step in native code** (the proposal's N4). Flight is 1.85 and 3.57 ms at 50 and 100, linear, about 36 us
   a ship. Predicted about 2.5 ms off at 100. Behaviour risk: the riskiest maths for parity (`FlightModel`). Confidence 55 %.

Re-ranked and not chosen: the per-contact loops in the brains and the driver (N2) gain less after nearest-k (the AI outside the
scan is 1.4 and 2.9 ms at 50 and 100 in the furball); the GDScript contact grid was dropped by the maintainer (Q6, Q9).

**Tests** (`27107bb`, before the native class): `tests/unit/test_contact_field.gd`, with the facade's surface it reads
(`ContactScan.NATIVE_CLASS`, `use_native`, `path`, `native_visits`) answering for GDScript only, and `NativeLib.version` taking the
class (a review finding on T05a). Seeded worlds of 1 to 300 bodies in four shapes (a furball, spread groups, a coarse lattice
for equal ranges, far from the origin, with bodies exactly on the 5 km line and one just past it), up to 400 bolts and a
broadcast scan per world; 1 499 queries through the facade on both paths, comparing `contacts_for`, `nearest_for` with and
without a keeper, `incoming_fire` and `broadcasts_for` (the same contact objects in the same order, the same counts); a work count
(spread's shape, 120 bodies in groups of 12 20 km apart: a query may test 12 to 24 bodies); `perf_native` flipped live on a scan
in use; freed bodies on both paths. With T05a's library loaded it failed 4 of 5 (the scan never took the native path; worst visits
0 against 12 to 24). Without the library the file is 6 pending, saying why. Added with the change: bolts that graze the 15 m
line (400 ships, 1 600 bolts within 5 micrometres of it), where only GDScript's precision gives the same counts. Each test was
checked against a broken native build: `<` for `<=` on the range, equal ranges to the later body, and the closest approach in
64 bits each failed it (the last on 117 of 400 ships).

**Change** (`48f0d71`): `ScsContactField` and the facade (`docs/architecture.md` §17.5).
- Once per tick, on a scan's first native query, `ContactScan` hands the field its arrays in one call; the field sorts the bodies
  into a grid of 5 km cells. A contact or nearest query tests only the bodies in the cells its range reaches, then follows the
  GDScript loop's rules in scan order. `incoming_fire`, `broadcasts_for` and the freed-body check moved too. The keeper (the
  brain's kept ids and names) still runs in GDScript, after the native selection, exactly as before.
- How cycle 3 changed the plan: the callers ask `nearest_for` (k 12) and only fall back to `contacts_for`, and only thinking
  ships ask (about 45 a tick at furball 100, not 100), so the native query returns the nearest 12 and the nearest hostile ship
  plus a marker when the cut left something out, and the keeper stays in GDScript; the per-call cost (about 0.7 us) is paid
  about 140 times a tick rather than 300.
- Factions cross as `StringName`s; the facade sends each querying faction's hostility row once per scan, so native code never
  calls `Factions`.
- `Contact`s are now made when first handed out, on both paths: a broadcaster nobody hears and a body no ship of the faction
  sees cost nothing. This is most of what the GDScript path gained below.
- `NativeLib.enabled()` caches `perf_native` and follows `Settings.changed`, so the scan (and `NativeProbe`) follow a flip at
  once (a review finding on T05a).
- Per query (a hand-built scan of 100 bodies in one 5 km ball, 300 bolts): `nearest_for` 5.9 us native against 14.4 us in
  GDScript (the native call itself 1.7 us, building the 12-contact list 2.8 us), `incoming_fire` 1.3 against 10.1 us.

**After** (`m4_c4_after_quick`, load 0.95 to 1.64; `m4_c4_after_stages`):

| quick check | furball ceiling | furball 40 / 50 ms | spread ceiling | spread 40 / 50 ms | 30 FPS holds to |
|---|---|---|---|---|---|
| before (`m4_c4_before_quick`) | 40 | 6.50 / 8.51 | 40 | 6.81 / 8.71 | 100 in both |
| after (`m4_c4_after_quick`) | 40 | 6.13 / 8.06 | 40 | 6.67 / 8.56 | 150 in both |

| layout | N | tick median | tick mean | ai | (scan) | (think) | flight | targeting | resolvers | (hit) | (ram) | late | physics | (sync) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| furball | 50 | 7.61 | 7.70 | 2.67 | 1.21 | 2.60 | 1.82 | 0.49 | 1.46 | 1.08 | 0.37 | 0.05 | 1.15 | 0.48 |
| furball | 100 | 16.02 | 16.23 | 5.43 | 2.40 | 5.29 | 3.51 | 0.99 | 4.42 | 3.68 | 0.70 | 0.06 | 1.72 | 0.27 |
| spread | 50 | 7.71 | 7.80 | 2.79 | 1.33 | 2.73 | 1.81 | 0.49 | 1.39 | 1.00 | 0.37 | 0.05 | 1.22 | 0.52 |
| spread | 100 | 16.37 | 16.50 | 5.49 | 2.66 | 5.36 | 3.58 | 0.99 | 4.51 | 3.75 | 0.73 | 0.06 | 1.75 | 0.27 |
| transit | 50 | 5.35 | 5.44 | 1.92 | 0.94 | 1.87 | 1.52 | 0.43 | 0.48 | 0.10 | 0.36 | 0.27 | 0.80 | 0.37 |
| transit | 100 | 10.79 | 11.03 | 3.91 | 1.96 | 3.80 | 2.93 | 0.87 | 0.91 | 0.18 | 0.70 | 0.52 | 1.86 | 0.66 |

The furball at 50 now has a single run's median under 8 ms (7.61), but the quick check's shorter run still misses 50 by 0.06 ms,
so the ceiling stays 40; 50 ships is within reach of the next cycle in both layouts.

**Paired, native against GDScript in one process** (`m4_c4_paired_*`, seed 1, 10 s, two rounds each; the GDScript path here
already has the lazy contacts, so this is the native part alone):

| layout | N | scan, GDScript | scan, native | AI, GDScript | AI, native | tick median, GDScript | tick median, native |
|---|---|---|---|---|---|---|---|
| furball | 50 | 1.63, 1.65 | 1.21, 1.24 | 3.14, 3.19 | 2.68, 2.75 | 8.19, 8.33 | 7.66, 7.80 |
| furball | 100 | 3.76, 3.81 | 2.43, 2.45 | 6.81, 6.90 | 5.48, 5.54 | 17.08, 17.39 | 16.02, 16.31 |
| spread | 100 | 3.47, 3.44 | 2.69, 2.65 | 6.34, 6.29 | 5.53, 5.49 | 17.05, 16.99 | 16.51, 16.49 |

Native saves 0.42 ms of scan at furball 50, 1.35 ms at furball 100 and 0.79 ms at spread 100; the lazy contacts save
little more on both paths: about 0.00 to 0.02 ms at furball 50 (the before's 1.65 against the paired GDScript runs' 1.63 and
1.65) and about 0.10 to 0.15 ms at furball 100 (3.91 against 3.76 and 3.81).

**Gain against the prediction:** the scan got cheaper, but by a third to a half of what was predicted (furball 0.44 ms off at 50
against about 1.4, 1.51 off at 100 against about 3.5; spread 0.09 and 0.46 against about the same as the furball), and the quick
check did not move a step. Why: the queries were not most of the scan. With the think rate, only about 45 ships query each tick at
furball 100, and what N1 leaves in GDScript is per tick and per result: building the scan from the tree (0.56 ms native run),
building the broadcast scan (0.21 ms), the freed-body checks (about 0.16 ms, no cheaper natively, as the engine does the lookup
either way), making the `Contact`s (0.30 ms) and building each ship's list (about 3 us per query). After N1 the scan at furball
100 is about 2.4 ms, of which the native queries are about 0.2 ms. Spread gains less because its queries were already short (a
ship sees about 12) and its scan has the same per-tick builds.

**Behaviour changes:** none. Seeded outcomes with `perf_native` on and off (`m4_c4_outcome`, each in a fresh process): `bench
furball 25 10 seed=1` and `bench spread 50 6 seed=2` give the same `state ai` line for every ship, the same behaviour counts (16
attack and 9 evade; 31 and 19), the same mean speed (70.06 and 65.11 m/s), hits (50 and 156), last hit, rams, mean bolts in flight
(84.19 and 184.09) and ship pairs (0.61 and 1.36).

**Tests** (focused, Q10; CI's full suite after the push): 33 GUT files run alone, every file that touches the contact scan,
perception, the AI driver, avoidance, targeting scale, the bench and AC13's paired budget (`test_ai_think_time`, `test_m3_run`),
once with the library and once without: with it 271 passing, 0 failing, 2 pending (the AC12 balance tests of `test_dogfight` and
`test_m3_sandbox`, as before); without it 265 passing, 0 failing, 8 pending (the same two and `test_contact_field`'s 6). No
Python changed.

**Fix round 2, robustness of the native field** (review). The grid's cell count is now a checked product: a huge finite range
saturates the cell indices, the count overflowed `i64` and could send a query through billions of cells, so a box too large to
count takes the scan-every-body path (same results). `load` checks that the parallel arrays line up; on a mismatch it logs one
error, keeps an empty scan and returns false, and `ContactScan` then answers that scan from GDScript. New tests pin both, and
three edges that were right but unpinned: a negative range, more than 256 factions, a hostility row shorter than the faction list.

### M4-T10 (2026-11-03): N4, the flight force step in native code

Built in a detached worktree on `f134e00` (wave 1, Q18), so these numbers see only this change; T07's `battle` layout was not in
the base, so the quick check and single `bench` runs at furball 50 and 100 and spread 100 measure it. Debug editor build, headless,
all runs under both bench locks and pinned to cores 0-11, load 1.5 to 2.1 throughout.

**Change.** `ScsFlightStep` (`native/src/flight_step.rs`) and `FlightBatch` (`src/ship/flight_batch.gd`, a child of `World` at
priority -1): every ship but the player's is `batched`, so its `FlightModel.compute`, the `SpeedGovernor` and the force
application of `Ship._physics_process` run in one native call per tick for all of them, by body RID through the physics server;
the ship node then only takes its command edges, and reads the applied force and the glow levels from the batch's row on
demand. `perf_native` and the new `perf_native_flight` flip it live; the assist's smoothed pod-yaw command follows a ship
across the two paths (architecture §17.9).

**Tests** (`5d03616`, before the change; both files failed, 0 of 4 and 0 of 7): `tests/unit/test_flight_step.gd`, a
differential test of 10 000 seeded commands and states per ship type (Starfury and raider) through the native step and the
GDScript model plus the ship's force maths, 23 fields each, exact; `tests/integration/test_flight_batch.gd`, ships in Jolt: the
player's ship stays on GDScript, a batched ship and its GDScript twin at one position (collisions off) fly the same, the damping
guard with a batched ship, an empty tank coasts, a live `perf_native` flip switches the path and keeps the assist state, a
parked ship leaves the step, the `flight` provider. With the change (`a19089a`) 11 of 11.

**Parity: bit for bit** (the stronger of the plan's two options, so Q16's tolerance is not needed). The native maths repeats
GDScript's 32-bit vectors and 64-bit scalars op for op (a scalar rounded to 32 bits before it scales a vector, Godot's operator
order and its `clampf`, `minf`, `maxf`, `signf`, the host's `exp` and `atan2`): zero mismatches in 20 000 differential samples
(brake, auto-track, the face controller's edges, an empty tank, assist on and off, speeds up to past the hard ceiling, random
bases, environment acceleration, `dt` of 1/60, 1/20 and 0); the Jolt twins give the same velocity, spin, position and applied
force after 3 s of changing commands. Seeded fights with `perf_native` on and off in separate processes
(`reports/perf/m4_t10_outcome`): `bench furball 25 30 seed=1` (a 35 s fight), `bench furball 25 5 seed=1` (positions at 10 s) and `bench spread 50 6 seed=2` give the same `state ai` line for every ship, the same behaviour counts (furball 25 at 35 s: 19 attack and 6 evade; spread 50: 31 and 19), the same mean speed (71.26 and 65.11 m/s), hits (154 and 156), last hit and rams, and every ship's position at 10 s (and at 15 s and 35 s) equal to the centimetre the console prints, worst distance 0.000 m over 25 and 50 ships, against Q16's 50 m.

**Before** (`m4_t10_before_quick`, load 1.9; `m4_t10_before_stages`) and **after** (`m4_t10_after_quick`, load 1.9;
`m4_t10_after_stages`):

| quick check | furball ceiling | furball 40 / 50 / 100 ms | spread ceiling | spread 40 / 50 / 100 ms | 30 FPS holds to |
|---|---|---|---|---|---|
| before | 40 | 6.48 / 8.16 / 18.04 | 40 | 6.67 / 8.58 / 18.96 | 150 in both |
| after | **50** | 5.84 / 7.62 / 16.85 | 40 | 6.35 / 8.27 / 18.36 | 150 in both |

Stages, mean ms per tick (single runs, `bench <layout> <n> 10 seed=1`):

| layout | N | | tick median | ai | (scan) | flight | targeting | resolvers | (hit) | (ram) | physics |
|---|---|---|---|---|---|---|---|---|---|---|---|
| furball | 50 | before | 7.89 | 2.70 | 1.22 | 1.87 | 0.50 | 1.49 | 1.09 | 0.37 | 1.21 |
| furball | 50 | after | 7.26 | 2.83 | 1.28 | **0.81** | 0.56 | 1.54 | 1.11 | 0.40 | 1.44 |
| furball | 100 | before | 16.05 | 5.53 | 2.45 | 3.62 | 1.01 | 4.48 | 3.71 | 0.73 | 1.73 |
| furball | 100 | after | 15.25 | 5.82 | 2.57 | **1.41** | 1.13 | 4.71 | 3.81 | 0.84 | 2.13 |
| spread | 100 | before | 16.46 | 5.54 | 2.69 | 3.60 | 1.00 | 4.54 | 3.76 | 0.73 | 1.76 |
| spread | 100 | after | 15.77 | 5.93 | 2.87 | **1.41** | 1.14 | 4.83 | 3.91 | 0.86 | 2.19 |

The batch's own cost inside the flight stage (`state flight` at the end of each run): 50 ships, gather 125 us and step 98 us;
100 ships, gather 233 us and step 179 us, so about 2.3 us a ship in GDScript (the command packed, the fuel flag, the
environment acceleration) and 1.8 us a ship natively (the body state read, the model, five force calls), against about 36 us a
ship before. The rest of the flight stage is the console, `Main`, the bolts and the props.

**Paired, the batch on and off in one process** (`m4_t10_paired`, `perf_native_flight` flipped between four 10 s runs, seed 1;
only the flight step changes, the native scan runs in both):

| layout | N | flight, off | flight, on | tick median, off | tick median, on | off the tick |
|---|---|---|---|---|---|---|
| furball | 50 | 2.05, 2.08 | 0.82, 0.83 | 8.66, 8.77 | 7.29, 7.39 | about 1.4 ms |
| furball | 100 | 4.17, 4.15 | 1.46, 1.47 | 18.05, 18.36 | 15.35, 15.82 | about 2.6 ms |
| spread | 100 | 4.07, 4.07 | 1.42, 1.42 | 17.82, 17.82 | 15.80, 15.76 | about 2.0 ms |

**Gain against the prediction:** the plan said flight 3.6 to about 1.2 ms at furball 100 (60 %); measured 3.6 to 1.4 in the
single runs and 4.2 to 1.5 paired (65 %). The tick at furball 100 fell 0.8 ms in the single runs and 2.6 ms paired: the other
stages read 0.1 to 0.4 ms higher in the after runs (AI, resolvers, physics), which the paired runs show to be the machine, not
the change, except physics, which reads 0.05 to 0.15 ms higher with the batch on in every pair (five server calls per ship from
native code instead of the node's `apply_force`; unexplained, small). The quick check moved the furball a step (50 ships hold
the budget, 7.62 ms) and left spread at 40 (8.27 ms at 50, 0.27 over).

**Behaviour changes:** none. Everything a batched ship's output used to carry is still there except the per-nozzle
`nozzle_forces` list, which stays empty for a batched ship (nothing reads it for an AI ship; the glow and the audio read the
levels). A batched ship's `FlightCommand.face_dir_b` is written only while it brakes (the only time the model reads it).

**Tests** (focused, Q10; CI's full suite after the push): the 82 GUT files that spawn ships, fly them in Jolt, read the flight
output or the applied force, or run the bench, plus AC13's paired budget (`test_ai_think_time`, `test_m3_run`), once with the
library and once without: with it 993 tests, 991 passing, 0 failing, 2 pending (the AC12 balance tests of `test_dogfight` and
`test_m3_sandbox`, as before); without it 993 tests, 967 passing, 0 failing, 26 pending (the same two, `test_contact_field`'s 13,
`test_flight_step`'s 4 and `test_flight_batch`'s 7, each saying the library is not built). `cargo fmt --check` and
`cargo clippy --release -- -D warnings` are clean for `flight_step.rs` (clippy 1.99 flags gdext's generated `base: base` in every
native class; this file allows that one lint at module level, the two older files are not this task's). No Python changed.

### Final measurements (M4-T06m, 2026-11-03)

Taken on commit `9b6091f` (all four cycles and the two robustness fixes), the debug editor build with the native library built
(`bin/libscs_native.so`, `perf.native_loaded = true`), default settings (think rate on, nearest-k 12, `perf_native` on), on the
maintainer's desktop with their browser and sync client running (load 1.6 to 2.5 at the start of each sweep, no other Godot
process; the M5 and bench locks held for every number). Runs are pinned to cores 0-11. Reports are in `reports/perf/m4_final*/`
(not committed).

**The full suite, once for the milestone (Q10).** `scripts/run_tests.sh` under the bench lock, 27 min 35 s, exit 0: the Python
tests 370 run, OK; GUT 172 scripts, 2 259 tests, **2 257 passing, 0 failing, 2 pending** (the two AC12 balance tests, as in every
run since M3), 52 499 asserts. AC13's paired budget and AC21's rebase cost passed the first time, so nothing was rerun.

**The sweep** (`scripts/bench.sh m4_final`, 22 min, all three layouts, seeds 1 to 3, 5 s + 30 s; a layout stops after two failing
counts in a row). Max N: **furball 25, spread 50, transit 50; headline 25** (the lower of furball and spread), against the
baseline's 0 and cycle 1's 25.

| layout | N | runs passed | tick median ms (three runs) | p99 ms | behind real time | worst rebase tick ms |
|---|---|---|---|---|---|---|
| furball | 25 | 3/3 | 4.38 (4.38, 4.36, 4.47) | 5.85 | 0.00 % | 5.58 |
| furball | 50 | 0/3 | 8.49 (8.43, 8.79, 8.49) | 10.73 | 0.00 % | 11.33 |
| furball | 100 | 0/3 | 15.88 (15.71, 15.88, 17.35) | 23.02 | 5.29 % | 23.85 |
| spread | 25 | 3/3 | 4.32 (4.32, 4.36, 4.29) | 5.57 | 0.00 % | 5.74 |
| spread | 50 | 2/3 | 7.98 (7.98, 8.03, 7.75) | 10.37 | 0.01 % | 11.00 |
| spread | 100 | 0/3 | 15.03 (15.03, 15.58, 15.01) | 23.10 | 3.68 % | 22.44 |
| spread | 150 | 0/3 | 23.08 (22.68, 24.91, 23.08) | 36.68 | 36.04 % | 44.17 |
| transit | 25 | 3/3 | 3.06 (3.02, 3.06, 3.09) | 4.04 | 0.00 % | 4.57 |
| transit | 50 | 3/3 | 5.38 (5.38, 5.39, 5.34) | 6.86 | 0.00 % | 7.11 |
| transit | 100 | 0/3 | 11.26 (10.93, 11.54, 11.26) | 15.03 | 0.00 % | 17.88 |
| transit | 150 | 0/3 | 16.22 (16.22, 16.19, 16.22) | 22.12 | 9.27 % | 25.08 |

Every failure from 50 up in the furball is the tick median alone until 100; at 100 the p99 and the rebase tick go over too, and
real time is kept (under 1 % behind) up to 50 in the furball and spread, and up to 100 in transit. Furball 50 misses the median
by 0.4 to 0.8 ms; spread 50 passes on seeds 1 and 3 and misses on seed 2 by 0.03 ms.

**Below the sweep's first failing count** (`m4_final_below`, `m4_final_below75`, the same settings, seeds 1 to 3). They show the
real ceiling is above the sweep's step:

| layout | N | runs passed | tick median ms (three runs) | p99 ms | worst rebase tick ms |
|---|---|---|---|---|---|
| furball | 35 | 3/3 | 5.51 (5.51, 6.15, 5.49) | 7.30 | 7.72 |
| furball | 40 | 3/3 | 6.70 (6.66, 7.20, 6.70) | 9.47 | 10.09 |
| furball | 45 | 2/3 | 7.88 (7.88, 7.69, 8.03) | 11.29 | 11.46 |
| spread | 75 | 0/3 | 11.87 (12.00, 11.66, 11.87) | 16.47 | 18.87 |
| transit | 75 | 0/3 | 8.52 (8.52, 8.53, 8.40) | 11.39 | 11.91 |

So **the furball's ceiling is 45** (two runs of three; seed 3 misses by 0.03 ms, and at 50 all three miss), spread passes 50 and
fails 75 (50 to 74 not run), and transit passes 50 and fails 75. Counted with these runs, the headline is **45** (the furball,
below spread's 50 or more); the sweep's own number stays 25, since the sweep steps from 25 to 50 and the furball fails 50.

**Stage breakdown** (single 30 s runs, seed 1, `m4_final_stages`, `m4_final_stages_head`), mean ms per tick, in the form of the
baseline and cycle tables. The baseline's 50 and 100 are the baseline table above (tick means 29.28 and 109.49 in the furball);
the final tick means are 8.43 and 16.00:

| layout | N | tick median | tick mean | ai | (scan) | (think) | flight | targeting | resolvers | (hit) | (ram) | late | physics | (sync) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| furball | 25 | 4.06 | 4.10 | 1.71 | 0.74 | 1.68 | 0.96 | 0.25 | 0.52 | 0.31 | 0.20 | 0.04 | 0.58 | 0.21 |
| furball | 45 | 7.41 | 7.55 | 3.10 | 1.29 | 3.03 | 1.67 | 0.45 | 1.11 | 0.76 | 0.33 | 0.05 | 1.12 | 0.47 |
| furball | 50 | 8.39 | 8.43 | 3.31 | 1.38 | 3.24 | 1.89 | 0.52 | 1.23 | 0.83 | 0.38 | 0.05 | 1.38 | 0.60 |
| furball | 100 | 15.22 | 16.00 | 6.16 | 2.57 | 6.01 | 3.56 | 1.00 | 3.27 | 2.52 | 0.71 | 0.06 | 1.86 | 0.35 |
| spread | 50 | 7.70 | 7.79 | 3.00 | 1.38 | 2.94 | 1.80 | 0.49 | 1.16 | 0.77 | 0.37 | 0.05 | 1.24 | 0.54 |
| spread | 100 | 14.48 | 15.41 | 5.58 | 2.65 | 5.45 | 3.50 | 0.99 | 3.28 | 2.54 | 0.71 | 0.06 | 1.89 | 0.35 |
| transit | 50 | 5.36 | 5.41 | 1.93 | 0.95 | 1.87 | 1.52 | 0.42 | 0.47 | 0.10 | 0.36 | 0.27 | 0.78 | 0.36 |
| transit | 100 | 10.87 | 11.10 | 3.91 | 1.96 | 3.81 | 2.95 | 0.87 | 0.92 | 0.19 | 0.70 | 0.53 | 1.90 | 0.66 |

The headline's furball at 25 ships and 45 are in the table. At 100 ships the AI (6.2 ms, 38 %), flight (3.6 ms), the hit resolver
(2.5 ms) and physics (1.9 ms) are the largest stages in the furball; targeting is 1.0 ms and the ram resolver 0.7 ms.

**The release build, once on the final code.** A snapshot of `9b6091f` (`git archive`, the generated assets and the native
library copied in, imported), exported with the script header's preset to `scs_release.x86_64` (embedded pack, release template
4.7.2). The export keeps the native library: `bin/scs_native.gdextension` is in the pack, and `libscs_native.so` is written beside
the binary byte for byte equal to the built one; `state perf` in the exported build says `native_loaded = true`,
`native_version = 0.1.0`. `scripts/bench_quick.sh` with the export, under both locks (`m4_final_release_quick`, load 1.49, 247 s,
seed 1, 2 s + 6 s per count):

| N | 10 | 25 | 40 | 50 | 75 | 100 | 150 | 200 |
|---|---|---|---|---|---|---|---|---|
| furball tick median ms | 1.47 | 3.09 | 4.97 | 6.39 | 10.74 | 14.18 | 24.56 | 36.75 |
| furball FPS | 60.0 | 60.1 | 60.1 | 60.0 | 59.9 | 59.8 | 39.0 | 26.2 |
| spread tick median ms | 1.58 | 3.46 | 5.25 | 6.69 | 11.48 | 15.16 | 24.47 | 40.06 |
| spread FPS | 60.0 | 60.0 | 60.0 | 60.0 | 60.1 | 59.3 | 38.3 | 23.5 |

**The release quick check holds the budget to 50 ships in the furball and in spread (6.39 and 6.69 ms at 50 ships, against 8.39 and
7.70 ms for the debug build's sweep runs)**; 75 misses (10.74 and 11.48 ms), and 30 FPS holds to 150 and falls under it at 200. The debug build's quick check
for the same code (cycle 4's table) held 40 and 30 FPS to 150, so the release build gains one step of the quick check's ladder. The
75-ship counts were not run in the full sweep's form, so the release ceiling between 50 and 75 is not known.

**AC6, the render check on the GPU** (maintainer's machine; windowed, 1920x1080, AMD Radeon RX 6950 XT, RADV NAVI21, Vulkan 1.4.354
Forward+, GDGS `splat_backend = compute`, `fallback = false`, splat budget 2 000 000; the furball at the headline's 25 ships, flown
by the bench's layout for a 20 s window after 8 s of warm-up, with `scripts/measure_fight.gd`, `scene=quiet`, under
`/tmp/scs-gpu.lock`; load 0.9 to 1.2). Drive: `scripts/measure_fight.gd -- scene=quiet exec="bench furball N 60
warmup=2 seed=1 ..."`. Screenshot `/tmp/m4_ac6.png` (the player's view of 25 ships and the radar full of blips; how it looks stays (H)).

| scene | vsync | FPS | frame ms mean / p99 / max | frames over 16.7 ms | GPU ms mean / max | splats visible (mean) | VRAM added (MB) | draw calls |
|---|---|---|---|---|---|---|---|---|
| furball 25 | off | 120 (min 114) | 8.34 / 17.36 / 34.92 | 39 (1.6 %) | 4.62 / 5.17 | 1.05 M | 1 630 | 678 |
| furball 25 | on | 60 (min 59) | 16.72 / 26.90 / 38.47 | 594 (49.6 %, vsync paced) | 4.59 / 5.11 | 1.05 M | 1 641 | 677 |
| furball 45 (the real ceiling) | off | 52 (min 47) | 19.10 / 34.44 / 42.15 | 796 (76 %) | 4.87 / 5.68 | 1.09 M | 1 657 | 1 201 |

VRAM at rest on the desktop was 2.8 GB of 17.2 GB before each run (other programs share the GPU), peak 4.44 GB, so the game
added about 1.6 GB (within about 100 MB). GTT added 0.7 GB. Render CPU time 0.8 ms (25 ships) and 1.4 ms (45). Findings: at the headline's
25 ships the game runs at 60 FPS on vsync and 120 FPS unconstrained, with the GPU at 4.6 ms a frame. **At 45 ships, which holds the
8 ms budget headless, the real renderer falls to 52 FPS (frame mean 19.1 ms)**: the main thread carries the 7.4 ms tick plus the
renderer's CPU work (1.4 ms) and the rest of the frame, and the frames over 25 ms mostly hold two ticks. The headless budget leaves
the main thread about half a frame for rendering, as designed; at 45 ships the real frame is over that. Also in every window: the
hit resolver has a spike of 7.5 to 8.5 ms every few seconds (`combat.resolve_us` p99 7.5 ms at 25 ships, mean 0.5 ms), behind several of
the frames over 25 ms at 25 ships; the headless run's p99 for the same layout is 5.9 ms. Not investigated here.

**Concerns carried to T06.** AC5 is not met: the headline is 25 by the sweep and 45 counting the below-sweep runs, against the
minimum of 100. The release build holds 50 in the quick check. The render check shows the headless budget is not enough on its own
above about 25 to 40 ships: at 45 the windowed game is under 60 FPS.

### M4-T07 (2026-11-03): the battle and typical layouts, the phase 1 before

Single seeded runs (`seed=1`, 5 s warm-up, 10 s measured, editor build, headless, both locks, load 1.4 to 2.6), on `31ec5fe`
in the T07 worktree, so only T07's change. Reports under `reports/perf/m4_t07/`. Means in ms per tick; the tick's median and
p99. "No rocks" is `rocks=0`, the same run without the asteroid field.

| run | tick median | p99 | ai | (scan) | flight | (standins) | targeting | (hit) | (ram) | physics | behind real time |
|---|---|---|---|---|---|---|---|---|---|---|---|
| typical 58 | 33.45 | 51.63 | 6.23 | 4.68 | 3.83 | 1.82 | 0.58 | 20.44 | 4.34 | 1.03 | 55.6 % |
| typical 58, no rocks | 9.13 | 11.99 | 2.97 | 1.47 | 2.27 | 0.30 | 0.58 | 1.48 | 0.56 | 1.42 | 0.0 % |
| battle 100 | 67.70 | 83.35 | 10.61 | 7.62 | 7.21 | 3.73 | 1.07 | 41.22 | 5.29 | 1.92 | 75.8 % |
| battle 100, no rocks | 19.07 | 24.52 | 6.06 | 3.19 | 4.55 | 1.09 | 1.07 | 4.58 | 1.03 | 1.81 | 18.3 % |
| battle 300 | 215.60 | 235.66 | 27.08 | 18.72 | 22.55 | 12.09 | 3.31 | 148.68 | 7.51 | 6.05 | 92.4 % (cut short) |
| battle 300, no rocks | 86.96 | 108.99 | 20.10 | 11.82 | 17.15 | 6.19 | 3.65 | 37.96 | 3.55 | 6.08 | 81.9 % |

Per entity (means per tick): typical 58 holds 50 fighters (all within 10 km of the player), 8 capitals, 78 turrets,
32 interceptors, about 190 bolts, 1 000 asteroids, 4 launches in the window, 2 sides; battle 100 holds 76 near and 9 far
fighters, 15 capitals, 142 turrets, 60 interceptors, about 385 bolts, 6 launches, 4 sides; battle 300 160 near and 95 far,
45 capitals, 426 turrets, 180 interceptors, about 1 230 bolts, 16 to 18 launches. Interceptors shot down 62 (typical) to
1 158 (battle 300, no rocks) bolts in 10 s. Missiles, beams and mines are 0 until T12.

- **The rocks dominate** through the GDScript paths that see every hull every tick: at typical 58 they add 19.0 ms of hits
  (each of about 190 bolts tested against 1 058 hulls), 3.8 ms of rams (the gather), 3.2 ms of scan (the gather) and 1.5 ms
  of turret retargeting (bigger contact lists). The plan expected 2 to 3 ms for the statics and turrets together. T08 (hit
  broad phase) and T09 (the registry, statics out of the brains' lists) are what removes most of it.
- **Without rocks** typical 58 is 9.1 ms (the plan: near the furball's 50 to 60 ship cost plus about 1.5 ms of stand-ins; the
  stand-ins themselves are 0.30 ms) and battle 100 19.1 ms (spread 100 is 19 ms; the plan: plus 2 to 3 ms). At battle 300 the
  turrets in GDScript are 6.2 ms and the hits 38 ms with 1 230 bolts.
- **The quick check** on furball and spread (the layouts add nothing to them): budget held up to 40 ships in both, as on the
  base (T08's and T10's before runs on `f134e00`, code-identical to `34c704b`). Tick medians came out 5 to 10 % higher in two
  runs (furball 100: 18.85 and 19.30 ms against 18.04 and 18.68; spread 100: 21.66 and 21.30 against 18.96 and 19.52), but
  evenly in every stage, including the AI and targeting stages that T07 does not touch on those layouts (the stand-in director
  does nothing outside a battle), at a load of 1.8 to 2.2: read as the machine's noise.
- **Fullscreen** (`scripts/fullscreen_check.sh`, the 3D at 1 080 lines in a fullscreen window on the 4K screen, vsync off,
  20 s; reports `reports/perf/m4_t07_fs_*`):

| run | FPS | frame mean ms | GPU ms mean | render CPU ms | draw calls | VRAM added MB | verdict |
|---|---|---|---|---|---|---|---|
| typical 58 | 2.8 | 356.7 | 6.1 | 1.45 | 908 | 1 389 | fails 60 FPS |
| typical 58, no rocks | 32.9 | 30.4 | 5.9 | 1.39 | 856 | 1 612 | fails 60 FPS |
| battle 100 | 1.8 | 559.8 | 5.9 | 1.81 | 1 545 | 1 290 | misses the 30 FPS floor |
| battle 100, no rocks | 5.5 | 182.5 | 6.3 | 1.73 | 1 479 | 1 320 | misses the 30 FPS floor |

  The GPU is not what binds (6 ms a frame at 1080p): the main thread is. With a tick over about 10 ms the windowed frame runs
  two or more ticks plus the frame's own process work (up to 17 to 20 ms a second's worst), so it falls behind. That is the
  phase 1 before for T11 (render proxies and the node diet); T26's trigger (the GPU binding) was not seen.

### M4-T08 (2026-11-03): the bolt broad phase in native code, projectile kinds

**How it measured.** In its own worktree (base `f134e00`), so the numbers see only this change: `scripts/bench_quick.sh` (furball
and spread) and single `bench <layout> <n> 10 seed=1` runs at furball 50 and 100 and spread 100, under both bench locks and pinned
to cores 0-11, debug editor build, before on the base and after on the change. T07's `battle` layout was not in this base, so
battle numbers come with wave 1's combined measurement. The windowed check: `bench furball 25|45 20 warmup=3 seed=1` in a
1920x1080 window on the maintainer's GPU (compute backend), under the GPU lock, the base from a snapshot of `f134e00`.

**Before** (`m4_t08_before_quick`, load 2.42; `m4_t08_before_stages`). The hit resolver put every bolt against every active hull:
300 bolts against 100 hulls at furball 100 is 30 000 sphere tests a tick. Quick check: both layouts hold the budget to 40 and
miss it at 50 (8.59 ms furball, 8.73 spread); 30 FPS holds to 100.

**Candidates** (the plan chose this task; ranked again here against the before):

1. **The bolt broad phase, native with a GDScript twin** (built). The hit stage is 3.70 ms of the furball's 15.9 ms at 100 ships
   and grows with bolts times hulls. Predicted 3.7 to about 0.6 ms at furball 100. Behaviour risk: none if the broad phase
   returns exactly the pairs the sphere test accepts. Confidence 75 %.
2. **The same grid in GDScript only.** Most of the gain without native code; predicted about 1 ms at furball 100. Kept as the
   fallback and the reference (measured below: 1.09 ms).
3. **Bolts as rows (no node per bolt).** The bolt moves and the per-tick gather are still node work; that is T15's core.

**Tests first** (`5dcf58b`): `tests/unit/test_hit_broad_phase.gd` (40 seeded crowds near the origin and 45 km out, hulls of
5 m to 1 km, bolts, missiles and 3 km beams: the broad phase gives exactly the pairs the sphere test accepts, ascending; native
and GDScript give the same pairs and work; 3 000 pairs within float rounding of the line; odd inputs; a 1 km hull among 200
fighters) and `tests/integration/test_hit_scale.gd` (24 drones 250 m apart, 300 bolts between two of them: at most 3 pairs tested
a bolt; a seeded melee of 30 drones and 400 bolts lands the same hits, bit for bit, as a broad phase that tests every pair, on
both paths; the grazing, tunnelling and friendly-fire pins on both paths; a missile's radius, a 3 km beam and a 1 km hull).
Committed with surface stubs: 4 of 6 and 4 of 10 failing (24 pairs a bolt against the bound of 3, no `ScsHitSweep`, one radius
for every kind). Each maths test was checked against a broken native build: the distance in 64 bits and another order of
operations each failed the edge test, a look without the level's largest reach or without the pad failed parity.

**Change** (`5848bda`): `HitBroadPhase` and `ScsHitSweep`, the resolver on packed arrays, `Projectile.kind` (§17.7). Then
(`298222d`) impact flashes share their quad and materials per colour, which removes the windowed hit spike (below).

**After** (`m4_t08_after_quick`, load 1.02; `m4_t08_after_stages`):

| quick check | furball ceiling | furball 40 / 50 ms | spread ceiling | spread 40 / 50 ms | 30 FPS holds to |
|---|---|---|---|---|---|
| before (`m4_t08_before_quick`) | 40 | 6.42 / 8.59 | 40 | 6.80 / 8.73 | 100 in both |
| after (`m4_t08_after_quick`) | 50 | 5.85 / 7.19 | 50 | 6.01 / 7.46 | 200 in both |
| final (`m4_t08_final_quick`, load 2.37, with the shared flashes) | 50 | 5.88 / 7.38 | 50 | 6.12 / 7.54 | 200 in both |

| run | tick median | tick p99 | resolvers | hit mean | hit p99 | hit max | bolts (mean) |
|---|---|---|---|---|---|---|---|
| furball 50 before | 8.08 | 10.64 | 1.49 | 1.09 | 1.84 | 2.58 | 153 |
| furball 50 after | 7.01 | 8.55 | 0.67 | 0.30 | 0.94 | 1.44 | 153 |
| furball 100 before | 15.93 | 22.37 | 4.47 | 3.70 | 6.27 | 6.93 | 317 |
| furball 100 after | 13.19 | 18.02 | 1.34 | 0.59 | 1.13 | 1.38 | 317 |
| furball 100 after, GDScript path | 15.51 | | | 1.09 | 1.83 | 2.29 | 317 |
| spread 100 before | 16.76 | 23.32 | 4.57 | 3.78 | 7.29 | 9.80 | 321 |
| spread 100 after | 13.40 | 17.76 | 1.36 | 0.61 | 1.16 | 1.33 | 321 |

(The GDScript-path run has `perf_native` off, so its contact scan is GDScript too: only its hit stage compares.) Taken again on a
library built in the worktree's own cargo target directory (`cc047f9`, load 0.93; `m4_t08_rerun`), after the shared target
directory once handed another worktree its library: furball 100 tick median 12.99 ms, hit 0.55 ms (p99 0.94); spread 100 13.33
and 0.55 ms (p99 1.01); the seeded outcome runs identical to the base, with `perf_native` on and off. In the tests'
fleet of 24 the resolver now tests 0.51 pairs a bolt at worst against 24 before.

**Gain against the prediction:** the hit stage at furball 100 fell from 3.70 to 0.59 ms (predicted about 0.6), its p99 from
6.27 to 1.13 ms; the tick median 2.7 ms. The quick check moved a step in both layouts (40 to 50) and 30 FPS now holds to 200.
What is left of the hit stage is the gather (two group walks and the packed arrays) and the hits themselves.

**The windowed spike (AC6).** It was not the sweep. In a 1920x1080 window on the maintainer's GPU (compute
backend), `bench furball 25|45 20 warmup=3 seed=1`, the base's hit stage has a median of 0.37 ms and a p99 of 7.63 ms (max
11.25); with the broad phase alone the median falls to 0.16 ms and the p99 stays 7.71 ms. Headless the same run has no spike
(max 1.35 ms). A throwaway timing build (never committed) split each slow resolve: in 20 s at 25 ships, 42 resolves over 2.5 ms,
each with one hit (no kill), where making and adding the `ImpactFlash` took 6.9 to 17.1 ms (median 7.4) and the damage, sparks
and signal tens of microseconds. Each flash built a quad and two materials; in the window that creation stalls on the renderer.
Flashes now share them per bolt colour (`64a00d3` test, `298222d` change), so a hit makes only nodes; the fade is per instance,
so the look is unchanged ((H) may confirm).

| window, furball seed 1, 20 s | tick median | tick p99 | tick max | hit median | hit p99 | hit max | render.fps at the end |
|---|---|---|---|---|---|---|---|
| 25, base | 4.37 | 12.35 | 18.79 | 0.37 | 7.63 | 11.25 | 60 |
| 25, broad phase | 4.68 | 12.70 | 23.71 | 0.16 | 7.71 | 10.72 | 60 |
| 25, broad phase and shared flashes | 4.47 | 8.51 | 14.19 | 0.15 | 0.43 | 0.72 | 60 |
| 45, base | 8.01 | 15.95 | 23.49 | 0.79 | 8.24 | 11.30 | 47 |
| 45, broad phase | 7.69 | 15.76 | 24.96 | 0.25 | 7.77 | 11.95 | 49 |
| 45, broad phase and shared flashes | 7.32 | 12.27 | 36.95 | 0.24 | 0.56 | 1.02 | 54 |

All six windows give the same hits (100 and 172) and bolt means. The tick max of 36.95 ms at 45 with the fix is not the hit
stage (its max is 1.02 ms); not investigated here. `render.fps` is one reading at the end of the run, not a mean.

**Behaviour changes:** none. Seeded outcomes (`m4_t08_before_outcome`, `m4_t08_after_outcome`, each a fresh process):
`bench furball 25 10 seed=1` and `bench spread 50 6 seed=2` give the same `state ai`, `combat` and `ram` lines, bolts and pairs
means on the base and on the change, with `perf_native` on and off (hits 50 and 156, behaviours 16/9 and 31/19, mean speed
70.06 and 65.11 m/s, bolts 84.19 and 184.09), the values cycle 4 recorded.

**Tests** (focused, Q10): 30 GUT files run alone, every file that covers the hit resolver,
projectiles, impact flashes, weapons, damage and destruction, the AI fights, the bench and the probe, and AC13's paired budget
(`test_ai_think_time`, `test_m3_run`), on `298222d`, once with the library and once without: with it 325 passing, 0 failing,
0 pending; without it 320 passing, 0 failing, 5 pending (`test_hit_broad_phase`'s native cases, saying why). No Python
changed. The full suite runs on CI after the push.

### M4-T12 (2026-11-03): missile, beam, interceptor and mine stand-ins

In its own worktree on `441a3b4` (so only this change), single seeded runs (`seed=1`, 5 s warm-up, 10 s measured, editor build,
headless, both locks, pinned to cores 0-11, load 0.9 to 1.5), before on a snapshot of the base and after on the change. Reports
under `reports/perf/M4-T12_before/` and `M4-T12_after/`. Means in ms per tick; the tick's median and p99.

| run | tick median before | after | p99 before | after | standins before | after | hit before | after | bolts before | after |
|---|---|---|---|---|---|---|---|---|---|---|
| typical 58 | 15.37 | 15.66 | 18.29 | 19.04 | 1.72 | 1.86 | 1.51 | 1.63 | 193 | 213 |
| typical 58, no rocks | 6.54 | 6.74 | 7.88 | 8.40 | 0.28 | 0.39 | 0.31 | 0.34 | 191 | 211 |
| battle 100 | 22.65 | 23.23 | 28.07 | 28.65 | 3.29 | 3.45 | 1.96 | 2.05 | 381 | 413 |
| battle 100, no rocks | 13.01 | 12.85 | 15.80 | 16.02 | 0.99 | 1.10 | 0.62 | 0.66 | 390 | 418 |
| battle 300 | 56.24 | 55.72 | 72.85 | 71.90 | 10.86 | 9.76 | 4.00 | 4.20 | 1 245 | 1 286 |
| battle 300, no rocks | 39.41 | 38.38 | 55.38 | 55.19 | 5.55 | 4.43 | 2.18 | 2.26 | 1 237 | 1 275 |

Per entity after (means per tick): typical 58 holds 20 missiles in flight, 16 beam emitters, 100 mines; battle 100 34 missiles
(the mix asks 34), 30 emitters, 100 mines; battle 300 102 missiles, 90 emitters, 300 mines. In the 10 s window battle 300
launched 182 missiles, its interceptors shot down 80, its beams fired 184 to 189 shots; typical's beams fired none (its capitals
stay over 3 km from the fighters) and no mine went off in any run.

What each stand-in part costs (the director's own timers, means per tick at battle 300 without rocks, and per entity):

| part | us per tick | per entity |
|---|---|---|
| missile steering (in the projectiles' tick) | 105 | 1.0 us a missile |
| missile launches and strike targets | 18 | |
| beams (cadence, strike targets, firing) | 41 | 0.5 us an emitter, plus one 3 km sweep a shot in the hit stage |
| mines (a third of the belts' triggers through the grid) | 93 | 0.3 us a mine |
| interceptors (one grid query, the picks) | 750 | 4.2 us an interceptor |
| the gathers (every projectile and every flying hull) | 1 341 | shared by interceptors, missiles and mines |

- **Against the plan's expectation** (0.1 ms per 20 missiles, 0.1 ms per 100 mines at 100 ships): 20 missiles cost about 0.03 ms
  and 100 mines about 0.035 ms, both under it. The hit stage grew 0.03 to 0.2 ms with the missiles and beams in flight.
- **The stand-ins' stage fell at battle 300** (5.55 to 4.43 ms without rocks, 10.86 to 9.76 with them) although it now carries
  missiles, beams and mines: T07's interceptors each looped over every bolt in flight, and one grid query replaces that. At
  typical and battle 100 the stage rose 0.1 to 0.15 ms, the new weapons' cost.
- **The gathers** (1.3 ms at battle 300) are the largest new part: a walk of the projectile group (about 1 280) and the flying
  hulls every tick. T07's interceptors walked the projectiles too; T20's native rows end both walks.
- **Furball and spread are unchanged:** the quick check held the budget up to 50 ships in both, as on the base (failing at 300
  at 24.8 and 24.3 FPS against 24.7 and 24.2; load 1.2 against 1.5), and seeded runs give the same outcome on base and change
  (furball 25: 113 projectiles, 17 hits, the same last hit; spread 24: 115 and 19).
### M4-T09 (2026-11-03): the native body registry, kinds and nearest statics

**How it measured** (as cycle 4): the quick check and single `bench <layout> <n> 10 seed=1` runs, all under both bench locks
and pinned to cores 0-11, on the debug editor build; the before on this task's base (`34c704b`) exported beside the
worktree with its own library build, the after on `2ede5a9`; and a paired run in one process (`perf_native` on, off, on,
off). `typical` and `battle 100` need T07's layouts and are not in this worktree. The machine was shared with three other
agents' runs, so loads were 1.0 to 2.9 and the single runs are noisier than the paired ones.

**Before** (`m4_t09_before_quick`, load 1.63; `m4_t09_before_stages`) and **after** (`m4_t09_after_quick`, load 2.09;
`m4_t09_after_stages`):

| run | before tick median | before scan | after tick median | after scan |
|---|---|---|---|---|
| furball 50 | 8.05 | 1.25 | 8.26 | 1.15 |
| furball 100 | 18.18 | 2.75 | 17.38 | 2.32 |
| spread 100 | 18.33 | 2.94 | 17.47 | 2.76 |
| quick, furball 50 | 8.55 | | 8.11 | |
| quick, spread 50 | 8.66 | | 9.02 | |

The quick check's ceilings did not move (40 ships in both layouts, before and after; 30 FPS holds to 150 ships in the furball and 100 in spread, both times).

**Paired, native against GDScript in one process** (`m4_t09_after_paired_*`, load 1.0 to 1.6; mean ms per tick):

| layout | N | scan, native | scan, GDScript | AI, native | AI, GDScript | tick median, native | tick median, GDScript |
|---|---|---|---|---|---|---|---|
| furball | 50 | 1.08, 1.11 | 1.73, 1.76 | 2.58, 2.65 | 3.26, 3.33 | 7.50, 7.56 | 8.27, 8.34 |
| furball | 100 | 2.13, 2.13 | 4.04, 4.06 | 5.30, 5.30 | 7.19, 7.21 | 16.19, 16.01 | 17.45, 17.96 |
| spread | 100 | 2.57, 2.55 | 3.66, 3.66 | 5.46, 5.46 | 6.57, 6.59 | 16.16, 16.43 | 17.18, 17.11 |

Against cycle 4's paired native scan (1.21 at furball 50, 2.43 at 100, 2.66 at spread 100) the native scan is 0.1 to 0.3 ms
cheaper. Inside the build (a throwaway timing run, a 100-ship fight, 542 bolts in flight): `from_tree` 522 us, the registry
scan 233 us, of which the native refresh 53 us, the snapshot's arrays 16 us and the bolts' GDScript gather 158 us; loading the
field 46 us. The GDScript path got about 0.25 ms slower at furball 100 (3.78 to 4.05): the reference now reads each marker's
`kind` and skips static rows.

**Gain against the prediction:** about 0.3 ms off the scan at furball 100, against the 1.4 ms predicted (2.6 to 1.2). The
prediction counted cycle 4's whole "gather" bucket (building the scan 0.61, the broadcast scan 0.31, the freed-body checks
0.16); measured on this base the body gather was about 0.37 ms and the bolts' gather, which this task leaves to T15, about
0.16 ms. What remains of the 2.1 ms native scan is per query and per result: about 45 `nearest_for`, `incoming_fire`,
`statics_for` and `broadcasts_for` calls a tick, making the `Contact`s and the keepers' lists. Those move with the brains
(T16, T17) and the core's rows (T15).

**Behaviour changes:** none for fighters. Seeded outcomes with `perf_native` on and off (`m4_t09_after_outcome`, each in a
fresh process): `bench furball 25 10 seed=1` and `bench spread 50 6 seed=2` give the same `state ai` line for every ship and
the same work counts, behaviour mix (16 attack and 9 evade; 31 and 19), mean speed (70.06 and 65.11 m/s), mean bolts in
flight (84.19 and 184.09) and ship pairs (0.61 and 1.36), which are also cycle 4's values. New behaviour where nothing
existed before: rocks and mines are avoided (a fighter at 100 m/s straight at a 150 m rock passes 170 m from its centre,
`test_contact_registry`), and avoidance looks further ahead for a big static.

**What T07's `kind` needs** (T07 owns `Targetable` this wave): the registry and `from_tree` read a marker's `kind` property
as a `BodyKind` name (`ship`, `capital`, `turret`, `missile`, `mine`, `static`, `prop`, any case) or as an int in that order;
anything else is a ship. If T07's `kind` is an enum in another order, map it in `BodyKind.from_variant` and in
`body_registry.rs` (`kind_of`). T07's asteroid field registers its rocks with `ContactScan.register_static(id, position,
radius, BodyKind.STATIC, Factions.NEUTRAL, world)` (ids unique, not instance ids); that world's `rebase` already shifts them. A body whose kind or
faction changes while it stays shown calls `ContactScan.touch(body)`.
### M4-T11 (2026-11-03): far-ship dots and the node diet for AI ships

**How it measured.** In its own worktree (base `441a3b4`, T07, T08, T10 and T28 merged), so the numbers see only this change:
single seeded runs (`bench <layout> <n> 10 warmup=5 seed=1`, headless, editor build, both bench locks, pinned to cores 0-11)
before on the base and after on the change (`m4_t11_before`, `m4_t11_after`, load 1.1 to 1.9), and the fullscreen check
(`scripts/fullscreen_check.sh`: a 4K fullscreen window, the 3D at 1 080 lines, vsync off, 20 s after 8 s, under the GPU lock and
both bench locks; `m4_t11_before_fs_*`, `m4_t11_after_fs_*`). Per-ship draw calls from `scripts/measure_fight.gd`'s `quiet` (the
player alone), `hundred_view` (100 idle AI ships, 150 m to 1.5 km, all in view) and `hundred` (100 from 200 m to 6 km all round),
fullscreen the same way, and a throwaway probe that hid one part at a time on 20 idle raiders in view.

**Candidates** (the plan chose this task; ranked against the before):

1. **The lean AI ship and far dots** (built). A pooled Starfury was 112 nodes and a raider 74; an idle AI ship in view cost
   about 15 draw calls (the depth proxy's 13 or 9 material surfaces, three markers, the plumes). Predicted: render CPU and the
   physics sync and rebase cut with the nodes (70 %).
2. **Far dots alone.** Takes the far ships' calls but leaves every near ship's 15 and every ship's nodes in the sync and the
   rebase.
3. **One fleet-wide multimesh for every AI plume.** One call for all plumes, but each frame a GDScript loop over every nozzle
   of every ship in World space (12 000 at 500 ships); per-ship multimeshes need no per-frame transform at all.

**Tests first** (`a699fca`): `tests/integration/test_ship_nodes.gd` (a pooled AI ship at most 16 nodes besides its guns' muzzles
and flashes, no `CollisionShape3D` yet every hit volume a shape of the body and hit by a ray, no cockpit or separate fallback
node, the proxy node draws the fallback, plumes as one multimesh whose instance follows the level, the nozzle lights where the
plume nodes put them, one plume material per colour, markers as one multimesh of three in port red, starboard green and top
white that go dark and park, at most three surfaces drawn near; the player's ship keeps every node), `tests/unit/test_far_dots.gd`
(the paint, past the distance no splat node and one dot, back a tenth inside its level again and no dot, the hysteresis, the dot
tracks the ship, a rebase moves it at once, a parked ship leaves none, two ships one multimesh, the player never a dot, the
setting, no render state) and `LodSwitcherMath.far_dot`. Committed with surface stubs: 9 of 11, 9 of 12 and 1 of 13 failing.

**Change** (`9e135f7`): §17.10. **Nodes:** Starfury ally 112 to 19, raider 74 to 24 (16 each besides the guns), the player's
123 unchanged.

**Headless** (means and medians in ms; "shift" is the rebase's shift and interpolation reset, median and max of 4):

| run | tick median before | after | p99 before | after | physics before | after | shift before | after |
|---|---|---|---|---|---|---|---|---|
| typical 58 | 15.56 | 14.84 | 18.24 | 17.45 | | | 1.91 max | 1.21 max |
| typical 58, no rocks | 6.55 | 5.66 | 8.52 | 6.51 | 1.17 | 0.53 | 1.08 max | 0.53 max |
| battle 100 | 22.60 | 21.89 | 27.03 | 24.62 | | | 2.87 max | 1.79 max |
| battle 100, no rocks | 12.84 | 10.70 | 16.00 | 12.86 | 2.25 | 0.84 | 1.85 / 1.91 | 0.88 / 0.94 |
| battle 300, no rocks | 39.38 | 36.97 | 56.02 | 40.80 | 5.11 | 1.96 | 6.44 / 6.77 | 3.44 / 3.56 |
| furball 100 | 11.65 | 9.68 | 15.16 | 11.96 | 2.53 | 0.95 | 1.92 max | 1.06 max |

The physics stage (Jolt's step and the body sync, which propagates each body's transform down its nodes) falls by 55 to 62 %;
that is most of the tick's gain. The rebase at battle 300 split by a probe (a 1 mm shift, three times, and a reset of every
visible interpolated node): ships 0.18 ms of shift and 1.14 ms of reset (5 us a ship), 1 568 bolts 0.40 and 0.54 ms, 45 capitals
0.02 and 0.12 ms. So the ships' share meets the plan's 2 ms; the bolts are T15's rows.

**Fullscreen** (verdicts as the script gives them):

| run | FPS before | after | frame mean ms before | after | GPU ms | render CPU ms before | after | draw calls before | after |
|---|---|---|---|---|---|---|---|---|---|
| typical 58 | 7.0 | 8.7 | 141.97 | 114.68 | 7.1 / 7.0 | 1.22 | 0.63 | 850 | 274 |
| typical 58, no rocks | 55.5 | **92.0** | 18.01 | **10.87** | 5.9 / 5.7 | 1.24 | 0.57 | 855 | 277 |
| battle 100 | 4.7 | 5.1 | 212.33 | 196.57 | 6.2 / 5.9 | 1.64 | 0.69 | 1 506 | 388 |
| battle 100, no rocks | 12.2 | 27.1 | 81.73 | 36.88 | 6.5 / 6.2 | 1.69 | 0.75 | 1 423 | 367 |
| furball 45 | 67.6 | 86.6 | 14.79 | 11.54 | 6.6 / 6.4 | 1.24 | 0.60 | 1 202 | 297 |
| quiet (the player alone) | 243.8 | 258.7 | 4.10 | 3.87 | 3.7 / 3.6 | 0.32 | 0.30 | 95 | 83 |
| hundred_view (100 idle in view) | 31.2 | 37.3 | 32.09 | 26.79 | 12.0 / 12.3 | 0.86 | 0.70 | 1 575 | 583 |
| hundred (100, 200 m to 6 km) | 47.1 | 67.1 | 21.22 | 14.91 | 5.4 / 5.4 | 0.56 | 0.47 | 489 | 299 |

- **`typical` without rocks now passes Q20's bar** (60 FPS with a frame mean of 12 ms or under: 92 FPS, 10.87 ms). With the
  rocks it is still the T07 rocks cost on the tick (T09's registry). **`battle` 100 misses the 30 FPS floor**, 27.1 without
  rocks and 5.1 with: the main thread binds, not the GPU (6 ms a frame), so T26's trigger is not seen. The tick (10.7 ms
  headless, 17.9 ms at worst a second in the window) and the frame's own process work (12.9 ms at worst a second) are what is
  left; the wave's other tasks (T09's registry, T12, T14) and phase 2 are where they go.
- **Draw calls per AI ship**: 100 idle ships in view cost 5.0 calls a ship (14.8 before). The probe on 20 idle raiders in view:
  45 calls with everything on, 2.25 a ship; hiding the proxies took 10 calls, the markers none (why the count does not
  show them was not found; they draw, the screenshots show them), the plumes 9; hiding the splat nodes took the rest, about 2 a ship. So the diet's own meshes cost about
  1.3 calls a near ship and the far ships one call together; what is left of a near ship is its visible GDGS splat node,
  which T27 measures against meshes. In the battle as a whole, 367 calls for 85 AI ships (4.3, bolts included) against 1 423.
- **Render CPU** halved everywhere (1.2 to 1.7 ms down to 0.6 to 0.75 ms); it was never the 15 ms the research feared at 45 to
  100 ships. VRAM added is unchanged within noise (1.3 to 1.5 GB, the splat budget's buffers).
- **GDGS** kept one render state in every run.

**Quick check** (furball and spread, `m4_t11_after_quick` against the base `m4_t11_before_quick`): both layouts held the budget to 75 ships after, to 50 before
(load 0.9 and 1.1). Tick medians at 50 / 75 / 100: furball 5.75 / 8.97 / 11.77 ms before, 4.88 / 7.61 / 9.80 after; spread 5.97 /
9.53 / 12.03 before, 5.01 / 7.70 / 10.08 after. Both still fall under 30 FPS at 300 (24.8 and 24.1 FPS before, 28.8 and 29.1
after).

**Behaviour changes:** none in the simulation (ships, physics, contacts, gameplay components are the same; the player's ship is
unchanged). Visual changes for (H): AI ships' plumes are drawn as instances (the core disc's falloff baked into vertex colours,
its offset a share of the plume's length), the proxy is one merged surface, and past 3 km an AI ship is a dot of its hull's mean
paint lit as a lit side. Screenshots for the maintainer: `/tmp/m4_t11_before_battle_far.png` and `_near`,
`/tmp/m4_t11_after_battle_far.png` and `_near` (the `battle` 100 layout without rocks, 2 s and 28 s in, windowed 1080p),
`/tmp/m4_t11_before_hundred_near.png`, `_far` and the same `after` (the 100-ship scenes, 4K), `/tmp/m4_t11_after_plumes_near.png`
(a raider and a Starfury burning broadside at 45 and 60 m, three raiders as dots at 3.5 to 6.5 km) and
`/tmp/m4_t11_after_held_markers.png` (the 13-ship fight from the cockpit, the markers per instance).

**Tests** (focused, Q10): 41 GUT files run alone on `50d8b43`, each with 0 failing and 0 pending: `test_ship_nodes` 11, `test_far_dots` 12, `test_lod_switcher_math` 13, `test_hull_depth_proxy` 12, `test_ally_pool` 21, `test_ship_pool` 21, `test_running_lights_in_play` 21, `test_running_lights` 24, `test_running_light_dimming` 7, `test_lod_in_play` 5, `test_hero_lod` 11, `test_splat_budget_in_play` 8, `test_thruster_visuals` 28, `test_ship_lights` 14, `test_multi_ship` 17, `test_ship_scene` 27, `test_rebase_in_play` 8, `test_world_frame` 16, `test_flight_batch` 7, `test_flight_parity_fight` 1, `test_relight` 26, `test_cockpit_screens` 20, `test_camera_rig` 36, `test_destruction` 11, `test_respawn_in_play` 6, `test_main_scene` 11, `test_splat_pose_sync` 6, `test_last_hit_breakup` 14, `test_starfury_breakup` 11, `test_debris_pool` 13, `test_ram_damage` 15, `test_hit_resolver` 16, `test_standins` 8, `test_bench` 8, `test_ship_physics` 17, `test_wing_replenish` 13, `test_ai_think_time` 1, `test_m3_run` 2, `test_control_profiles` 32, `test_control_profile` 34, `test_control_profile_store` 15; 599 passing in all. They are the new and changed files, every file that covers the ship, its lights, plumes, proxy, levels, the pool, the rebase, the flight batch and its parity fight, destruction and the bench, and AC13's files (`test_ai_think_time`, `test_m3_run`, the control profiles). No Python or Rust changed. The full suite runs on CI after the push.

## Definition of done (M4)

- The maintainer has the T06 report and has answered it: more cycles, or M4 closed with the number reached.
- `scripts/run_tests.sh` green, AC1-AC6 recorded (AC6 on the maintainer's GPU). Then `m4` merges into
  `main`.

Carried over from M3's final review (2026-11-02), to do when convenient: the wing join warning fires every wave from the sandbox's second loop, because looped waves add raiders past BLUE's three slots (they fly solo, as before); on CI the GUT step's own timeout (3600 s) is longer than the 45-minute job limit, so a hung shard shows as a cancelled job; a pool ship released and taken again as the same `Combatant` before the wing's next refresh keeps stale wing state; with vsync on, about one repeated frame a second in a fight, half of them with no ships in the scene (M3-T12, cause not found).
