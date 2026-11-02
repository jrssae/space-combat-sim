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
| T02 | Cycle 1 | T01 | Opus | Profiling and a ranked judgement call | not started |
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
    sleep between frames, so a headless run sets `OS.low_processor_usage_mode_sleep_usec` to 0 for its duration.
  - Windows are counted in ticks (300 of warm-up, 1 800 measured), so every run has the same number of samples; real time kept
    is their sim time against the wall time they took. A run under a tenth of real time is cut short and fails.
  - The rebase threshold is lowered to 180 m for the run: at the player's 60 m/s that is a rebase every 3 s (ten per window,
    enough to see their cost) while rebase ticks stay under 1 % of the ticks and so do not decide the p99 on their own.
  - Bench ships are invulnerable and god mode is on, so N holds for the whole window (no deaths, explosions or respawns);
    `transit` makes the two sides neutral for the run, which is its "no fight".
  - The machine is a hybrid i5-13600KF (performance cores 0-11 at 5.1 GHz, efficiency cores at 3.9 GHz), so `bench.sh` pins
    every run to cores 0-11 (`BENCH_CPUS`); the allowed cores are in every summary.

### M4-T02 to M4-T05 Cycles 1-4

Each cycle is one task on its own branch (`m4-tNN`), merged into `m4` with a green suite before the next starts:

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

- **Done when:** the cycle's entry in the log is complete and the merge is green and pushed.

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

### Baseline (M4-T01, 2026-11-02)

Measured on commit `0d4a503` (the harness, before any change), headless on the development desktop with nothing else heavy
running: an i5-13600KF (six performance cores at 5.1 GHz, eight efficiency cores), 31 GB, Bazzite 44, Godot 4.7.2-stable
official (`ed1daf0bf`). `scripts/bench.sh m4_baseline`: the `combat_sandbox` scene, 5 s of warm-up and 30 s measured, seeds 1, 2
and 3, each run its own process pinned to cores 0-11. The full reports are in `reports/perf/m4_baseline*/` (not committed).

**Max N: furball 0, spread 0, transit 0; headline 0.** No layout passes at 25 ships, the sweep's smallest count, so each one
stopped after 25 and 50. Three runs at 100 were added past the stop for the breakdown, and counts of 12, 16 and 20 were run
below the sweep to find the real ceiling (`m4_baseline_below`, not part of max N): all three layouts pass at 20 on every run,
so today's limit is between 20 and 25 ships. The runs agree closely: three run medians never spread more than 2.7 % (furball at 20).

| layout | N | runs passed | tick median ms (three runs) | p99 ms | behind real time | worst rebase ms |
|---|---|---|---|---|---|---|
| furball | 20 | 3/3 (below the sweep) | 6.99 (6.99, 6.99, 6.80) | 8.21 | 0.00 % | 0.34 |
| furball | 25 | 0/3 | 9.69 (9.67, 9.83, 9.69) | 11.65 | 0.00 % | 0.48 |
| furball | 50 | 0/3 | 28.99 (28.95, 29.43, 28.99) | 32.83 | 44.3 % | 1.28 |
| furball | 100 | 0/3 (past the stop) | 109.29 (109.49, 109.29, 108.62) | 116.04 | 85.0 % | 2.77 |
| spread | 20 | 3/3 (below the sweep) | 6.80 (6.80, 6.85, 6.79) | 7.94 | 0.02 % | 0.36 |
| spread | 25 | 0/3 | 9.42 (9.57, 9.42, 9.37) | 11.20 | 0.00 % | 0.49 |
| spread | 50 | 0/3 | 27.32 (27.53, 27.19, 27.32) | 31.00 | 41.0 % | 1.23 |
| spread | 100 | 0/3 (past the stop) | 102.52 (103.54, 102.52, 102.20) | 111.37 | 84.0 % | 2.59 |
| transit | 20 | 3/3 (below the sweep) | 5.99 (5.99, 5.99, 5.96) | 6.67 | 0.00 % | 0.41 |
| transit | 25 | 0/3 | 8.12 (8.12, 8.12, 8.14) | 9.39 | 0.00 % | 0.36 |
| transit | 50 | 0/3 | 24.14 (24.27, 24.06, 24.14) | 26.64 | 33.0 % | 1.06 |
| transit | 100 | 0/3 (past the stop) | 91.15 (91.15, 91.03, 91.61) | 96.15 | 81.9 % | 2.10 |

Every failure at 25 is the tick median alone (p99, rebase and real time hold); from 50 the simulation falls behind the wall
clock. Pool growth (the load) took 30, 80 and 185 ms at 25, 50 and 100 ships headless, where the splat renderer is off.

**Stage breakdown**, mean ms per tick (the median over the three runs of each run's mean; means add up to the mean tick, the
median tick is above). `scan` is inside `ai`, `sync` inside `physics`; `other` is the tick's unaccounted remainder:

| layout | N | tick | ai | (scan) | flight | targeting | resolvers | late | physics | (sync) | rebase | other (unaccounted) | bolts |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| furball | 50 | 29.30 | 6.19 | 2.06 | 1.82 | 16.75 | 3.56 | 0.05 | 0.86 | 0.11 | 0.01 | 0.05 | 115 |
| furball | 100 | 109.92 | 17.59 | 5.79 | 3.86 | 74.32 | 12.09 | 0.07 | 1.82 | 0.28 | 0.01 | 0.11 | 214 |
| spread | 50 | 27.64 | 4.72 | 1.82 | 1.77 | 16.63 | 3.55 | 0.05 | 0.85 | 0.11 | 0.01 | 0.05 | 107 |
| spread | 100 | 103.01 | 11.04 | 4.86 | 3.82 | 73.96 | 12.30 | 0.07 | 1.79 | 0.23 | 0.01 | 0.11 | 230 |
| transit | 50 | 24.30 | 3.59 | 1.45 | 1.52 | 16.50 | 1.66 | 0.27 | 0.71 | 0.05 | 0.00 | 0.03 | 0 |
| transit | 100 | 91.22 | 8.43 | 3.70 | 3.27 | 72.22 | 5.14 | 0.59 | 1.54 | 0.13 | 0.01 | 0.03 | 0 |

What the baseline says, for cycle 1 to test rather than follow:

- **Targeting is two thirds of the tick and the same in every layout**: 4.4 ms at 25 ships, 16.6 ms at 50, 72-74 ms at 100
  (3.7 and 4.4 times per doubling, so quadratic), whether the ships share one fight or sit 20 km apart. M3-T20's figure
  (`TargetingController` about 63 of 87 ms at 100 ships) is confirmed in a real fight: 74 of 110 ms. Every ship's controller
  turns every targetable into a `TargetInfo` each tick before the range cut.
- **The AI** is the second cost and grows faster than linearly: 2.6, 6.2 and 17.6 ms at 25, 50 and 100 in the furball,
  11.0 ms at 100 in spread and 8.4 ms in transit. The scan inside it (5.8 ms at 100 in the furball, 4.9 ms in spread) costs
  nearly as much in spread as in the furball, so it too walks every body whatever the range.
- **The resolvers** are third: 12 ms at 100 with about 220 bolts in flight, and still 5.1 ms in transit with no bolt at all
  (0.6, 1.7, 5.1 ms at 25, 50, 100), which points at the ram resolver's pair checks rather than the bolt sweep.
- Flight (the flight model, bolts, `Main`) grows linearly (1.9 ms at 50, 3.9 ms at 100); Jolt and the body sync are under 2 ms
  at 100; the wings and waves (late) and the rebase are small: the worst rebase tick at 100 ships was 2.8 ms, far inside its
  16.7 ms budget.

Checks on the harness: the engine's own worst physics step of each second (`Performance.TIME_PHYSICS_PROCESS`) is 2-3 % under
the probe's worst tick per 60 ticks in every run (111.8 against 115.3 ms at furball 100), so the probe's tick window misses
nothing the engine counts. The stage timers cost nothing measurable: `bench furball 100 30 probe=paired` (30 blocks with them
on, 29 off, half a second each) gives a paired difference of +48 us on a 109 ms tick (0.04 %, inside the noise; the on blocks'
median was even 0.25 ms below the off blocks').

## Definition of done (M4)

- The maintainer has the T06 report and has answered it: more cycles, or M4 closed with the number reached.
- `scripts/run_tests.sh` green, AC1-AC6 recorded (AC6 on the maintainer's GPU). Then `m4` merges into
  `main`.

Carried over from M3's final review (2026-11-02), to do when convenient: the wing join warning fires every wave from the sandbox's second loop, because looped waves add raiders past BLUE's three slots (they fly solo, as before); on CI the GUT step's own timeout (3600 s) is longer than the 45-minute job limit, so a hung shard shows as a cancelled job; a pool ship released and taken again as the same `Combatant` before the wing's next refresh keeps stale wing state; with vsync on, about one repeated frame a second in a fight, half of them with no ships in the scene (M3-T12, cause not found).
