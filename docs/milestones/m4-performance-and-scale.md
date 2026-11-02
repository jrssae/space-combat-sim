# Milestone 4: Performance and Scale

> "Many ships at once." (`docs/roadmap.md`)

**Status:** planned 2026-10-28 at the maintainer's request, inserted after M3; the later milestones moved up one (the mission
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
  `docs/third-party.md` is a question for the report, not a cycle's pick.
- Console and settings as everywhere (§6.4): the `perf` provider and `bench` command register with `DebugConsole`; new settings
  are `SettingsSchema` entries.
- GPU checks run on the maintainer's machine (`CLAUDE.md`); only judgements of how it looks or feels are (H).

## Acceptance criteria

| # | Criterion | Kind | Done |
|---|---|---|---|
| AC1 | Harness: `bench <layout> <n> [seconds]` on the console and `scripts/bench.sh` (the sweep) run the three layouts at any N headless on the real main scene and write `reports/perf/<label>/` (`summary.json`, `summary.md`); the `perf` provider shows the last tick's stages (`tick_us`, `ai_us`, `scan_us`, `physics_us`, `resolvers_us`, `targeting_us`, `rebase_us`, `ships`); the statistics (median, p99, the budget verdict, the max-N search) are unit-tested; `scripts/run_tests.sh` has a short smoke run (`furball`, 25 ships, 5 s) that checks the report is written, not its numbers | A | M4-T01, 2026-11-02 |
| AC2 | Baseline: before any change, the sweep's max N per layout and the stage breakdown at 50 and 100 ships are recorded below | A | M4-T01, 2026-11-02 (Cycle log, Baseline) |
| AC3 | Four cycles, each recorded below: the numbers before, three candidates ranked by confidence with the evidence for each, the first built **test first** (the failing test committed before the change), the numbers after, the gain against the prediction | A | |
| AC4 | No regressions: `scripts/run_tests.sh` green after each cycle; AC13's paired budget holds; every behaviour change listed | A | |
| AC5 | Goal: the headline max N is at least 100, and toward 500. Not reached after cycle 4: the report says so and asks for guidance (T06) | A | |
| AC6 | Render check at the headline max N on the maintainer's GPU: FPS, frame time, VRAM, GPU and driver recorded (by the agent, 2026-11-01) | A | |

## Task breakdown (ordered)

Status: `done` (merged, its milestone accepted), `in progress`, `not started`, `not needed` (a conditional task whose trigger never arose). Update the column with each task's commit.

| Task | Title | Depends on | Agent | Why | Status |
|---|---|---|---|---|---|
| T01 | Benchmark harness, budget and baseline | M3 | Opus | Measurement design on a noisy machine; touches the tick order | done |
| T02 | Cycle 1 | T01 | Opus | Profiling and a ranked judgement call | done |
| T03 | Cycle 2 | T02 | Opus | Same | not started |
| T04 | Cycle 3 | T03 | Opus | Same | not started |
| T05 | Cycle 4 | T04 | Opus | Same | not started |
| T06 | Report to the maintainer | T05 | controller | A summary and a question, no code | not started |

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

Each cycle is one task, committed directly on `m4` (no task branches, maintainer 2026-11-02), with a green suite and a push before the next starts:

1. **Measure.** Run the sweep on the branch's base. Profile the worst layout at the largest passing N and at the first failing
   one: which stage grows, and how fast with N.
2. **Rank.** Write three candidate improvements in the cycle log, ranked by confidence that they improve the headline max N,
   each with its evidence (the measured stage and its growth), the expected gain and the behaviour risk. The previous cycle's
   unbuilt candidates are ranked again with the new numbers, not carried over unexamined.
3. **Test first.** Commit a failing test that pins the improvement: a work count (for example contacts touched per tick in
   `spread`, or nodes walked per rebase) or a cost compared in one process, plus behaviour tests for anything it may change.
4. **Build** candidate 1 until the test passes and the full suite is green.
5. **Measure again.** The sweep after; record the gain against the prediction. A candidate that gains nothing is reverted, says
   why, and the cycle still counts.

While iterating, `scripts/bench_quick.sh` (under 10 minutes: furball and spread ramped from 10 ships until they fall under
30 FPS, one short run per count) shows whether a change moves the ceiling; the numbers recorded in the log come from the sweep.

- **Done when:** the cycle's entry in the log is complete and the merge is green and pushed.
- **Done (T02, cycle 1, 2026-11-02):** only the player's targeting keeps a candidate list (`TargetingController.keeps_candidates`,
  `docs/architecture.md` §17.2); headline max N 0 to 25, the ceiling below the sweep 20 to 30 ships. Entry in the Cycle log.

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

**Test** (`15b59b6`, before the change): `tests/integration/test_targeting_scale.gd`. `TargetInfo.built_count` counts every
`TargetInfo` built; in a fight of 24 AI ships (`AiPilot`, ally and raider profiles, seeded) plus the player, the test failed
with 600 per tick against a linear bound of 75, and an AI ship's `candidates()` returned the last tick's list instead of the
targets as they are. Six behaviour tests passed before and after: a selection that leaves the sensors, turns inactive or is
freed clears in the refresh and says so, a broadcast stretches the reach, an id out of reach is refused and the selection
kept, the nearest hostile wins over a nearer neutral, two hostiles at the same range go to the lower id.

**Change** (`7cc168e`): `TargetingController.keeps_candidates`, set by `ShipAssembly` from `is_player`. The player's controller
rebuilds its list every tick as before. Every other one checks only its selection each tick and builds a list when asked:
`candidates()`, the target edges and names gather on demand, `select_id` checks the one target, and `select_nearest_hostile`
walks the targetables without building a `TargetInfo`. Design in `docs/architecture.md` §17.2. With it the test counts 24
`TargetInfo`s per tick (the player's list), and a controller of each kind run side by side over 400 seeded steps of moving,
hiding and selecting gives the same answers, selections and signals (a mutation that drops the broadcast reach makes that test
fail 97 times).

**After**: `scripts/bench.sh m4_c1_after` on `7cc168e` (the same settings as the baseline, nothing else heavy running), plus
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
before the next refresh (the last tick's list allowed it until the refresh at priority 100 cleared it). The full suite was not run
for this cycle: the maintainer stopped the run on purpose, partway through GUT, and asked for it not to be restarted, so AC13's
paired budget and the rest of M1-M3 are not confirmed here. What did run on the change: the new test file (9/9) and 25
targeting-related test scripts (307/307 passing, 2706 asserts), and the 24 GUT scripts the stopped run reached passed.

**What is left for cycle 2** (re-rank with these numbers): at 50 ships the AI is 47 % of the furball tick (the scans 2.1 ms,
the brains and avoidance 4.0 ms) and the resolvers 27 % (rams 2.7 ms); at 100 the AI is 17.1 ms, the rams 9.5 ms and the bolt sweep 2.6 ms.
To pass 50 the furball needs 5 ms off its 13 ms median, more than candidate 2 or 3 gives alone.

## Definition of done (M4)

- The maintainer has the T06 report and has answered it: more cycles, or M4 closed with the number reached.
- `scripts/run_tests.sh` green, AC1-AC6 recorded (AC6 on the maintainer's GPU). Then `m4` merges into
  `main`.

Carried over from M3's final review (2026-11-02), to do when convenient: the wing join warning fires every wave from the sandbox's second loop, because looped waves add raiders past BLUE's three slots (they fly solo, as before); on CI the GUT step's own timeout (3600 s) is longer than the 45-minute job limit, so a hung shard shows as a cancelled job; a pool ship released and taken again as the same `Combatant` before the wing's next refresh keeps stale wing state; with vsync on, about one repeated frame a second in a fight, half of them with no ships in the scene (M3-T12, cause not found).
