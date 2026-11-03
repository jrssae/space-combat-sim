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

## Maintainer answers (2026-11-02)

After cycle 1 the maintainer read the options in `docs/handoff-m4.md` section 7 and the native-code proposal, and decided:

| Q | Question | Answer |
|---|---|---|
| Q6 | Plan for cycles 2 to 4 | Cycle 2: the ram resolver's broad phase. Cycle 3: the AI think rate with nearest-k contacts. Cycle 4: native code (below). The release export template is measured once, in cycle 2 |
| Q7 | How cycles measure | With `scripts/bench_quick.sh` ("the shorter performance test"), plus single `bench` runs for the stage breakdown; not the full sweep |
| Q8 | Think rate | AI ships within about 2 km of the player think every tick; farther ones think at 20 Hz on staggered ticks and hold their last command between (their physics still runs every tick). A behaviour change, listed in the report |
| Q9 | Native code | Allowed (this answers the rule below). **Rust with godot-rust `gdext`** (pinned, `api-4-7`). Cycle 4 is native: first the toolchain, CI and seam (N0), then the contact scan's queries in native code behind `ContactScan` (N1); the GDScript grid is dropped. Seeded outcomes stay bit-identical where that is cheap (N1 must be); later ports may differ within a stated tolerance, with every test green, listed in the report. Worker threads are allowed inside the native code only, with tests that one thread and six give the same output |
| Q10 | How cycles test | Focused GUT runs on the code a task touches plus AC13's paired-budget file, and the quick check; then the push, and CI's full suite is the gate. `scripts/run_tests.sh` runs locally **once per milestone**, before it closes |

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
  `docs/third-party.md` is a question for the report, not a cycle's pick. (Answered for native code on 2026-11-02, Q9.)
- Console and settings as everywhere (§6.4): the `perf` provider and `bench` command register with `DebugConsole`; new settings
  are `SettingsSchema` entries.
- GPU checks run on the maintainer's machine (`CLAUDE.md`); only judgements of how it looks or feels are (H).

## Acceptance criteria

| # | Criterion | Kind | Done |
|---|---|---|---|
| AC1 | Harness: `bench <layout> <n> [seconds]` on the console and `scripts/bench.sh` (the sweep) run the three layouts at any N headless on the real main scene and write `reports/perf/<label>/` (`summary.json`, `summary.md`); the `perf` provider shows the last tick's stages (`tick_us`, `ai_us`, `scan_us`, `physics_us`, `resolvers_us`, `targeting_us`, `rebase_us`, `ships`); the statistics (median, p99, the budget verdict, the max-N search) are unit-tested; `scripts/run_tests.sh` has a short smoke run (`furball`, 25 ships, 5 s) that checks the report is written, not its numbers | A | M4-T01, 2026-11-02 |
| AC2 | Baseline: before any change, the sweep's max N per layout and the stage breakdown at 50 and 100 ships are recorded below | A | M4-T01, 2026-11-02 (Cycle log, Baseline) |
| AC3 | Four cycles, each recorded below: the numbers before, three candidates ranked by confidence with the evidence for each, the first built **test first** (the failing test committed before the change), the numbers after, the gain against the prediction | A | |
| AC4 | No regressions: after each cycle the focused runs (the touched code and AC13's paired budget) are green locally and CI's full suite is green on the push (Q10); `scripts/run_tests.sh` green locally once, before M4 closes; every behaviour change listed | A | |
| AC5 | Goal: the headline max N is at least 100, and toward 500. Not reached after cycle 4: the report says so and asks for guidance (T06) | A | |
| AC6 | Render check at the headline max N on the maintainer's GPU: FPS, frame time, VRAM, GPU and driver recorded (by the agent, 2026-11-01) | A M4-T06m, 2026-11-03 (Cycle log, Final measurements) |

## Task breakdown (ordered)

Status: `done` (merged, its milestone accepted), `in progress`, `not started`, `not needed` (a conditional task whose trigger never arose). Update the column with each task's commit.

| Task | Title | Depends on | Agent | Why | Status |
|---|---|---|---|---|---|
| T01 | Benchmark harness, budget and baseline | M3 | Opus | Measurement design on a noisy machine; touches the tick order | done |
| T02 | Cycle 1 | T01 | Opus | Profiling and a ranked judgement call | done |
| T03 | Cycle 2 | T02 | Opus | Same | done |
| T04 | Cycle 3 | T03 | Opus | Same | done |
| T05 | Cycle 4: native contact scan (Rust `gdext`, N0 then N1, Q9) | T04 | Opus or Fable | A new toolchain and bit-identical parity | done |
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

## Definition of done (M4)

- The maintainer has the T06 report and has answered it: more cycles, or M4 closed with the number reached.
- `scripts/run_tests.sh` green, AC1-AC6 recorded (AC6 on the maintainer's GPU). Then `m4` merges into
  `main`.

Carried over from M3's final review (2026-11-02), to do when convenient: the wing join warning fires every wave from the sandbox's second loop, because looped waves add raiders past BLUE's three slots (they fly solo, as before); on CI the GUT step's own timeout (3600 s) is longer than the 45-minute job limit, so a hung shard shows as a cancelled job; a pool ship released and taken again as the same `Combatant` before the wing's next refresh keeps stale wing state; with vsync on, about one repeated frame a second in a fight, half of them with no ships in the scene (M3-T12, cause not found).
