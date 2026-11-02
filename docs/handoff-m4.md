# Handoff: M4 performance and scale (2026-11-02)

Where M4 stands, what has been measured, what the maintainer has decided, and the options for going faster. Written for
whoever picks M4 up next, an agent or the maintainer. The milestone itself is `docs/milestones/m4-performance-and-scale.md`;
its Cycle log holds the full numbers. This file is the short version plus the decisions that live outside it.

## 1. Where things stand

| Item | State |
|---|---|
| `main` | M3 merged (`b2f8ce1`). |
| `m4` | Holds T01, the quick check and T02's three commits (`0438c56`, `2e83ca3`, `63cc752`). Every task is committed directly on `m4`. |
| T01 benchmark harness, budget and baseline | Done and merged. Reviewed twice, full suite green (GUT 2178 of 2180 passing, 2 pending AC12 balance tests; Python 363 OK). |
| T02 cycle 1 | Built and measured, **not reviewed or merged**. Its commits were made on a worktree branch, then moved onto `m4` (`0438c56`, `2e83ca3`, `63cc752`); the branch and worktree are gone. Report: `.superpowers/sdd/m4-performance-and-scale/task-2-report.md`. The full suite was **not run**: the maintainer stopped it partway through GUT. The new tests (9/9) and 25 targeting scripts (307/307) pass. |
| T03 to T05 cycles 2 to 4, T06 report | Not started. The hold is lifted (section 2, the order to run the recommendations). |

## 2. Decisions and standing orders

- **2026-11-02, the M3 to M4 order:** "once all changes are complete and all tests pass, commit and push to github. then
  merge m3 to main. then create m4 branch and begin executing the m4 milestone. use fable agents if needed to crack the
  performance ceiling." Done up to running M4. Fable (`claude-fable-5-1`) is allowed for hard performance work.
- **2026-11-02, stop after T02:** do not review or merge T02 or start T03 until the maintainer has read the options and
  chosen.
- **2026-11-02, native code:** the maintainer is "not worried about the cost to maintain for this purpose". The milestone's
  rule still says a GDExtension is "a question for the report, not a cycle's pick". This answer settles the maintenance
  cost. The language and the scope of a native port are still to agree (section 7, option 6).
- **Ship counts in the setting** (in the milestone's goal): a full Starfury squadron is 12, patrols are 6 or 4, scouts fly
  alone or in twos and threes, Babylon 5 has three full squadrons plus the station's defences.
- **2026-11-02, run the recommendations:** "begin executing the top 3 recommendations. follow the test cycle approach using
  the shorter performance test." So: finish T02, then cycles 2 to 4 (option 1; options 3 and 4; option 2), with option 11
  measured once in cycle 2. Cycles measure with `scripts/bench_quick.sh`, not the full sweep.
- **2026-11-02, think rate (option 3):** AI ships within about 2 km of the player think every tick; farther ones think at
  20 Hz on staggered ticks and hold their last command between. A behaviour change, listed in the T06 report.
- **2026-11-02, branches:** all work is committed directly on `m4`, never on a task or worktree branch (CLAUDE.md). The
  milestone's `m4-tNN` branches are not used. `spread` uses groups of 12 (6 against 6), `transit` uses wings of four.
- **Working rules that carry over:** one task at a time, finished and merged before the next. Push `m4` after each merged
  task with a green suite. Keep the milestone's Status column current. Read the suite's own totals (Passing, Failing,
  Pending), never a wrapper's exit code: a red push on 2026-11-01 came from trusting the wrapper.
- Not wanted now: a task to remember the last camera view between launches (nothing persists yet).

## 3. The harness (T01)

| Piece | What it does |
|---|---|
| `bench <layout> <n> [seconds]` (console) | Runs `furball`, `spread` or `transit` with N ships on the live main scene and writes `reports/perf/<label>/` (`summary.json`, `summary.md`). Options: `warmup=`, `seed=`, `label=`, `probe=paired`, `rebase_m=`, `sleep=keep`. |
| `perf` provider, `perf [on\|off]` | The last tick split by stage: `tick`, `ai` (with `scan` and `think` inside), `flight`, `targeting`, `resolvers` (with `hit` and `ram`), `late`, `physics` (with `sync`), `other`. |
| `scripts/bench.sh <label>` | The full sweep, N in 25, 50, 100, 150, 200, 300, 400, 500, three seeds, 5 s warm-up and 30 s measured. Stops a layout after two failing counts. About 50 minutes today. Gives max N. |
| `scripts/bench_quick.sh [label]` | The quick check, under 10 minutes (about 4 today). Ramps furball and spread from 10 ships with one 6 s run per count and stops a layout below 30 FPS. Lists the counts that passed the budget, those over budget but still at 30 FPS or more, and the count where it failed. Indicative only. |

The budget (milestone, "The budget"): tick median at most 8 ms and p99 at most 12 ms, no tick holding a rebase over
16.7 ms, the simulation under 1 % behind the wall clock. Max N for a layout needs two passing runs of three; the headline is
the lower of furball and spread.

Things to know before trusting a number:

- Every number is headless on the i5-13600KF (runs pinned to performance cores 0 to 11) with the Godot 4.7.2 **editor
  build (debug)**, the binary the suite uses. A release export template may run GDScript faster; nobody has measured it.
- The bench turns off the engine's sleep between headless frames so the body sync can be timed. With the game's own idle
  the p99 at 20 ships rose from 8.1 to 12.0 ms (the CPU wakes slowly). Read the bench's p99 at low load as a best case.
- When the simulation falls behind, ticks run back to back and `sync` is timed only in the first tick of each catch-up frame
  (12.5 %), so it is a lower bound there.
- The machine swings by up to 2x over seconds. Take numbers with nothing else heavy running (no suite, no GPU work).

## 4. Baseline (before any change)

No layout passed at 25 ships, so max N was 0 everywhere. All three passed at 20 (below the sweep).

| layout | 20 ships | 25 ships | 50 ships | 100 ships |
|---|---|---|---|---|
| furball tick median | 6.96 ms, pass | 9.63 ms | 29.0 ms | 109.1 ms |
| spread | 6.78 ms, pass | 9.41 ms | 27.6 ms | 102.8 ms |
| transit | 6.02 ms, pass | 8.13 ms | 24.2 ms | 91.6 ms |

At 100 ships in the furball the tick was 109 ms, of which targeting was 74 ms, the AI 17.6 ms (5.8 ms of it the contact
scan), the resolvers 12.1 ms (9.5 ms of it rams), flight 3.9 ms and Jolt with the body sync 1.9 ms. Targeting grew with N
squared and cost the same in every layout.

## 5. Cycle 1 (T02)

The agent profiled, ranked three candidates and built the first:

1. **Targeting keeps a candidate list only for the player** (built). Every ship's `TargetingController` turned every
   targetable into a `TargetInfo` each tick, 600 per tick at 25 ships. `to_target_info` alone was 53 of about 67 ms at 100
   ships. Now only the player's controller keeps the per-tick list, for the HUD and radar; AI ships check their one selection
   each tick and walk the targetables only when they pick a new target.
2. **Ram resolver broad phase** (not built). The swept-pair pass costs about 7.8 ms at 100 ships in every layout, N squared at
   about 1.5 us per pair, mostly `tracker.keep_touching` called for pairs nowhere near each other.
3. **Contact scan spatial index** (not built). Perception costs about 6 ms at 100 ships whether a ship sees 12 contacts or
   105, so the scan walks every body regardless of range.

Commits: `15b59b6` (the failing test: 600 `TargetInfo`s per tick against a linear bound of 75, plus six behaviour pins) and
`7cc168e` (the change: 24 per tick). A seeded side-by-side test of the old and new controller over 400 steps gives the same
answers, and seeded bench runs (furball 25, spread 50) give bit-identical outcomes before and after. No behaviour change.

Sweep after cycle 1 (`m4_c1_after`, three seeds):

| layout | 25 ships | 50 ships | 100 ships | max N |
|---|---|---|---|---|
| furball | 5.44 ms, pass 3/3 | 13.0 ms | 34.6 ms (was 109.1) | 25 (was 0) |
| spread | 5.28 ms, pass 3/3 | 11.9 ms | 28.8 ms (was 102.8) | 25 (was 0) |
| transit | 4.10 ms, pass 3/3 | 8.4 ms | 18.8 ms (was 91.6) | 25 (was 0) |

**Headline max N: 0 to 25.** The largest passing count below the next sweep count rose from 20 to 30 in the furball, 35
in spread and 45 in transit. With the engine's own frame sleep kept, the furball still passes at 25 and 30 on every run
(p99 9.2 and 9.5 ms), so 30 is not an artefact of the bench's busy loop. The gain matched the prediction within 0.3 ms at 25
ships, 0.6 ms at 50 and 1.5 ms at 100. Both furball and spread fall under 30 FPS at 100 ships in the quick check, where
before they gave out at 75.

One edge differs inside a tick, listed for the maintainer: a target that left play or reach since the last refresh can no
longer be selected by id before the next refresh (before, the last tick's list allowed it until the refresh at priority 100
cleared it).

What T02 still owes, all on the controller's side and on hold: the full suite (AC13's paired budget and the rest of M1 to M3
are unconfirmed until it runs), the task review (`reviewer-instructions.md`, Sonnet), fix rounds, merge into `m4`, push.

## 6. Where the time goes now

Measured after cycle 1 (`m4_c1_after`), mean ms per tick at 100 ships in the furball (tick mean 35.4 ms):

| stage | ms | share | how it grows | why |
|---|---|---|---|---|
| AI | 17.05 | 48 % | faster than N | perception walks every body (scan 5.65 ms); behaviours score every contact; avoidance about 2.2 ms |
| resolvers | 12.15 | 34 % | N squared | rams 9.46 ms (the swept-pair pass over every pair, about 1.5 us each); bolt hits 2.58 ms |
| flight | 3.41 | 10 % | N | the flight model, bolts, `Main` |
| Jolt and body sync | 1.70 | 5 % | N | native already |
| targeting | 0.96 | 3 % | N | the player's list and the AI ships' selection checks (was 74 ms) |

At 50 ships the tick is 13.2 ms: AI 6.19, resolvers 3.57 (rams 2.70), flight 1.71, physics 1.15, targeting 0.47.

At 500 ships even the linear parts break the budget in GDScript: flight alone would be about 17 ms and Jolt with the sync about 8.5 ms.
Algorithm fixes can bring 100 ships close; 500 needs native code, and likely threads as well.

## 7. Options, with confidence

Confidence is my estimate that the option raises the headline max N by the amount shown. The gains are estimates from the
stage numbers above, not measurements.

| # | Option | Evidence | Expected gain | Behaviour change | Confidence |
|---|---|---|---|---|---|
| 1 | Ram resolver broad phase: test only pairs whose hulls are near (bounding spheres, or the pairs Jolt already reports). | Swept pass 7.8 ms at 100, N squared, same in every layout. | About 7 ms at 100 ships, 2 ms at 50. Max N about 30 to 35. | None if the margin is conservative. | High, 85 % |
| 2 | Spatial grid for the contact scan (cells about the 5 km sensor range; a ship queries its own and neighbouring cells). | Perception about 6 ms at 100 whatever the contact count. | 4 to 5 ms at 100 in spread and transit; little in furball, where every ship is in range. | None (keep contact order). | High for spread, 80 %; low for furball, 30 %. The headline follows furball. |
| 3 | AI think rate: ships think at 20 to 30 Hz on staggered ticks and hold their last command between; physics still every tick. Optionally full rate near the player. | AI is the largest stage after cycle 1 (17.05 ms at 100). | AI cost halved or better, about 8 ms at 100. | Yes: up to 50 ms slower reactions. Maintainer sign-off; AC13 must hold. | High, 80 % |
| 4 | Nearest-k contacts: score, avoid and check fire lanes against the nearest 8 to 16 contacts, not all of them. | Furball AI grows faster than N (2.5, 6.2, 17.6 ms at 25, 50, 100). | About 5 ms at 100 in the furball; essential above 200. | Small: ships ignore far contacts when choosing. | Medium-high, 70 % |
| 5 | Bolt broad phase for the hit resolver and `incoming_fire`. | 2.6 ms at 100 with about 220 bolts. | About 2 ms at 100; more at 300 and up, where bolts times ships explodes. | None. | Medium-high for large N, 70 %; small now. |
| 6 | **Native hot paths** in a GDExtension: the contact scan and perception, behaviour scoring, avoidance, the broad phases, then the flight model's per-tick maths. Rust (godot-rust gdext) or C++ (godot-cpp); check which supports Godot 4.7.2 before choosing. | GDScript costs about 1.5 us per ram pair and about 39 us per ship per tick in flight. Tight loops port to native at 10 to 50 times the speed. The logic already sits in tested `RefCounted` classes, so the GUT tests check the port. | Large: the only option that reaches 500 ships. Combined with 1 to 4, 100 ships inside the budget looks reachable. | None intended; the existing tests pin behaviour. | High that it gives big gains, 85 %. Medium on effort: a toolchain in `setup_godot.sh` and CI, a build step, `docs/third-party.md`. |
| 7 | Threads: AI thinking spread over `WorkerThreadPool` (perception reads a snapshot, commands applied on the main thread). | Six performance cores sit idle; AI is the largest stage. | AI cost divided by 4 or 5. | Determinism needs care. | Medium, 50 % in GDScript (scene tree access is not thread safe); higher inside native code. |
| 8 | Cheaper rebase: fewer nodes per ship, or reset only the interpolated roots. | Rebase ticks run 2.3 to 4.3 ms over the median at 100 ships; T14 estimated about 12 ms of shift at 500. | Needed only at 300 ships and up, where the 16.7 ms rebase budget binds. | None. | Medium, 60 % (later) |
| 9 | Fewer allocations: reuse `Contact`s, pool `UniversePos` conversions. | One `Contact` per pair per tick. | 5 to 15 %. | None. | Low-medium, 40 % |
| 10 | Jolt: collision layers so ships do not pair-test every ship; simpler shapes. | Jolt and sync 1.7 ms at 100, linear. | Matters at 500 (about 8.5 ms). | None. | Low now, 30 %; revisit at 300. |
| 11 | Measure the release export template instead of the debug editor build. | Players run what ships; GDScript in a release build skips debug checks. | Unknown; a free gain if it shows. Measurement, not code. | None. | Medium, 50 %, that release is measurably faster |

My recommendation:

1. Finish cycle 1 (review, merge).
2. Cycles 2 to 4 in GDScript, in this order: option 1 (ram broad phase), then options 3 and 4 together if the maintainer
   accepts the think-rate trade, then option 2. Expected after that: furball and spread inside the budget at about 50 to
   60 ships.
3. Measure option 11 once; it changes what every later number means.
4. Start option 6 as its own task set after T06's report, now that maintenance cost is not a concern: the scan and the AI
   inner loops first, the flight model second. That is the path to 100 and toward 500. Option 7 belongs inside the
   native code, not in GDScript.

## 8. Open items

- **T02:** full suite, review and push are under way on `m4`. To pass 50 ships the furball needs
  about 5 ms off its 13 ms median, more than option 1 or 2 gives alone.
- **M3 carry-overs** (also at the end of the M4 doc): AC12 balance (dogfight unfinished on all five seeds; sandbox idle clears
  only wave 1); AC13's resolver worst tick (recorded, not asserted); the join warning from the wave loop; the CI GUT timeout
  longer than the job limit; stale wing state when the same Combatant is reacquired; repeated frames about once a second
  with vsync on.
- **Maintainer's (H) checks** in `docs/playtest.md`: AC14 to AC19, AC22, AC27, AC35, AC39, AC41.
- **AC6:** the GPU check at the headline max N (FPS, frame time, VRAM) comes with T06's report.

## 9. Picking it up

- Read `CLAUDE.md`, then the M4 milestone, then this file.
- The SDD ledger is `.superpowers/sdd/m4-performance-and-scale/progress.md`. Briefs, reports, reviewer and re-reviewer
  instructions and review diffs sit beside it (`task-N-brief.md`, `task-N-report.md`, `rules.md`).
- Agents work in the main checkout on `m4`, one at a time, with their own `XDG_DATA_HOME`. Real-renderer runs take `flock /tmp/scs-gpu.lock`; the full suite needs no lock and takes about 25
  minutes.
- If AC13's paired test or AC21's rebase cost fails in a loaded suite, rerun that file alone once; a second failure is real.
- `scripts/bench_quick.sh` for iterating and, from cycle 2, for the Cycle log's numbers; `scripts/bench.sh` for a full sweep.
