# Milestone 8: Tutorial vertical slice

> "The first mission." (`docs/roadmap.md`)

**Status:** **planned, not started.** Branch `m8` was cut from `main` at `1e7064dc` (M7's merge) on 2026-11-18. The planning
questions below were asked on 2026-11-18; the maintainer answered Q5 to Q8 the same day, and the proposed answers to the others
stand until the maintainer answers. The tutorial's script is
not planned here: its beats, lines and pacing are settled with the maintainer in T01, and T03 to T05 are filled in from it.

Read `docs/architecture.md` first, especially §14.6 (launch bays and the mission framework), §16 (the instructor as an
`AiPilot`, D37), §18 (M5: missions, `MissionApi`, dialog, the front end, the `CINEMATIC` camera) and M7's §20 (the station,
Cobra-bay launches §20.2, the defense grid §20.3, traffic and the main docking bay's `DockingPlan` §20.4, the hold-X
interaction §20.5, the hangar §20.8, the exterior tour §20.10, known gaps §20.14). Also `docs/roadmap.md` ("Carried from M7"
and L15 in "Carried from M4's full review"), `docs/milestones/m12-factions-and-capital-ships.md` on branch `m12` (T19, the raider
strike carrier, and T20, the Battle Wagon, which moves here) and `docs/design-references.md` ("Raider carrier", "Raider Battle
Wagon"). Tasks are ordered inside each track; each is one PR-sized unit and names a recommended agent model.

## Goal

Make the first mission. The player starts in the hangar behind the menu, watches their squadron launch from the Cobra bays,
launches, and is taught every control by a subtitled instructor. The instructor tours the station and its defense grid, then
raiders come through the jumpgate and the player defends Babylon 5 with the station's allies, ending in a debrief. A damaged
ship can dock in the main docking bay to be repaired and launched again. The raiders get their capital ships: M12's strike
carrier (T19) comes into M8 and carries the civilian escort's raids, and the Raider Battle Wagon moves here from M12. M7's
carried clean-ups land, and the game ships as a Linux x86_64 release build.

## Planning questions (asked 2026-11-18)

| Q | Question | Proposed answer (planner's default, until the maintainer answers) | Answer |
|---|---|---|---|
| Q1 | The tutorial's script | **Settled in T01** with the maintainer: the beats in the roadmap's order (hangar, squadron launch, own launch, control checks, exterior tour, raid through the jumpgate, defense with allies, debrief), each check's line and pass condition, and the pacing | open (T01) |
| Q2 | Which controls the instructor checks | The roadmap's list: main pods, retros, strafe (each axis), roll, pitch and yaw, flight assist on and off, the brake, targeting (next, nearest, the radial menu), fire modes (guns linked and alternate, missiles); each check passes on the same `InputMap` actions M1 reads, shown with the pad and keyboard bindings (keyboard parity: every pad action has a keyboard equivalent) | |
| Q3 | Can the player fail or skip a check? | A check never fails: the instructor repeats the hint after a pause and demonstrates the move (D37's manoeuvres); the whole training part can be skipped from the pause menu straight to the tour | |
| Q4 | The squadron-launch cinematic | As the roadmap says (maintainer, 2026-11-13): the Cobra bay's sawtooth doors open (T02), Starfuries drop out one after another, flip, light their engines and form up, with exterior shots; skippable; it ends with the player's own launch from M7-T08's sequence | |
| Q5 | How does the M12 strike carrier come into M8? | Merge `origin/m12` into `m8` in T07, reconciling M12's collision builder with the one M7 built, then mark M12-T19 done once the maintainer flies it in M8's play-test | Maintainer, 2026-11-18: the proposed answer |
| Q6 | The strike carrier in the civilian escort | Each wave's raiders arrive docked on the carrier and launch once it is clear of its point (Q29's data option); the carrier hangs back at stand-off, recalls survivors and jumps out when hurt or when its wave is down; destroying it is an optional objective | Maintainer, 2026-11-18: the proposed answer, for the first two waves; the last wave comes with the Battle Wagon (Q8) |
| Q7 | Docking for repair and relaunch | The player holds X at the main docking bay's mouth (the `dock` interaction that answers "not available" today); `DockingPlan` flies the ship in through the inner doors; a timed repair restores the hull and reloads guns and missiles; the ship then launches from a Cobra bay through M7-T08's launch sequence. A wingman docks on a wing order, or by itself below a hull threshold, and rejoins after its relaunch | Maintainer, 2026-11-18: the proposed answer |
| Q8 | The Battle Wagon in M8 | Moved from M12-T20 with its rules (Q31 there: from images, with weapons settled with the maintainer before work starts, four launch tubes). It appears in free-flight raids and a sandbox scenario; the tutorial's raiders come through the jumpgate vortex as the roadmap says | Maintainer, 2026-11-18: **also in the civilian escort: its last wave comes with the Battle Wagon**, launched from its tubes, instead of the strike carrier |
| Q9 | Release build | Linux x86_64 only, from the pinned 4.7.2 export templates (verified by SHA-256 like the editor), the native library and the generated assets packed; a script builds it, and the bench writes to `user://` in an exported build (L15) | |

## Scope

In:
- **The tutorial mission** (`tutorial`, from New game and offered first on a new profile): the hangar, the squadron launch, the
  control checks, the exterior tour, the raid, the defense and the debrief (Q1 to Q4).
- **Docking for repair and relaunch** in the main docking bay, for the player and the AI wingmen (Q7).
- **The raider capitals:** M12-T19's strike carrier merged into `m8` (Q5), the civilian escort's raids carried by it (Q6), and the
  Raider Battle Wagon moved from M12-T20 (Q8).
- **Carried from M7:** M7-2 the interceptor muzzle, M7-3 the cargo bay's flicker, M7-4 sawtooth Cobra doors, M7-5 the audio rework,
  M7-6 wingmen close formation gaps after losses.
- **Carried from M4:** L15, the bench's `res://reports` in an exported build.
- **The release build** for Linux x86_64 (Q9).

Out:
- Voiced dialog (M15; subtitles and the comms panel stay).
- Every other capital ship and the M12 framework (sections, beams, the staged break-up): M12 as planned.
- Landing in a Cobra bay (the bays stay launch-only; docking goes through the main docking bay).
- Story missions beyond the tutorial and the escort (M14).

## Design (to go into `docs/architecture.md` §21)

### D79 The tutorial mission

A `MissionScript` (`data/missions/tutorial.gd`) with its scenario and dialog files, built on M5's `MissionApi` and M7's station
seams: the hangar backdrop, `launch_from`, the exterior tour's points (M7-T12, T57), the defense grid and raids at the station
(M7-T10). The instructor is D37's `AiPilot` with the `instructor` profile. T01 writes the beats; this section is filled in from it.

### D80 Control checks

A pure `ControlCheck` (one per check: the actions it watches, a pass condition on measured ship state, a hint line, a demo
manoeuvre) and a `ControlCheckRunner` that the mission awaits. Checks read the same `InputMap` actions as M1 through the ship's
commands, never `Input`; the hint shows the current pad and keyboard bindings and follows a rebind.

### D81 The squadron-launch cinematic

A `CINEMATIC` sequence over M7-T08's launch: the sawtooth doors open, each Starfury of the squadron launches in turn from the
rail, flips and lights its engines, and the wing forms up on M7-T74's slots; exterior shots from fixed and tracking cameras.
Skipping lands in the state the full sequence ends in (the same rule as M7-T08's skip).

### D82 Docking, repair and relaunch

The `dock` interaction at the main docking bay starts `DockingPlan`'s lane for the player's ship (the lane the civilians already
fly, §20.4). Inside the inner doors the ship leaves play (M7's "ships inside the station unavailable" rule), a repair timer runs
from the damage taken, and the ship comes back through a Cobra-bay launch. Wingmen use the same path on a wing order or a hull
threshold, and the wing keeps their slots open (M7-6's re-slotting decides who moves up while they are away).

### D83 The raider capitals in M8

The strike carrier as M12-T19 built it (`docs/architecture.md` §19.18 on `m12`): `CarrierJumps` brings it for raider raids, with
fighters docked or beside by data. The escort's first two waves set `docked` (Q6); its last wave comes with the Battle Wagon (Q8). The Battle Wagon follows M12's Q31 rules and its four
tubes launch Delta-Vs; when M12's framework lands (sections, turrets, beams), both hulls move onto it like every other.

## Acceptance criteria

| # | Criterion | Kind | Done |
|---|---|---|---|
| AC1 | Tutorial script: T01's beats, lines and checks written into D79 and the dialog file, approved by the maintainer | A | |
| AC2 | Squadron launch: the cinematic plays from the hangar, the squadron launches and forms up, skipping lands in the same state (test on the end state), the player's launch hands over as M7-T08 does | A | |
| AC3 | Control checks: each check passes on its actions and state in headless tests driven by injected commands, for pad and keyboard bindings; a rebind changes the hint; a missed check repeats and demonstrates, never fails | A | |
| AC4 | Tutorial mission: starts from the menu and runs to the debrief in a headless test driven by console commands; the tour visits its points; the raid comes through the jumpgate vortex and the station's allies and grid fight it; losing the player ends in the debrief | A | |
| AC5 | Docking: the player docks through the main docking bay, is repaired (hull, guns, missiles) and relaunched from a Cobra bay (headless test on the state before and after); a wingman docks on order and by threshold and rejoins its wing | A | |
| AC6 | Strike carrier: M12-T19 merged into `m8` with its tests green next to M7's; one collision builder serves the station and the carrier | A | |
| AC7 | Civilian escort: the first two waves arrive docked on the strike carrier and launch; the carrier hangs back, recalls and jumps out; the escort's tests (success, both failures, flee and resume) pass with it | A | |
| AC8 | Battle Wagon: meets the output contract with Python tests (budgets, frames, hardpoints, tubes, determinism), its look sheet seen by the maintainer (no STL: Q10 on `m12`), in the game with its weapons and four launch tubes, in a sandbox scenario and free-flight raids; the civilian escort's last wave launches from its tubes and the escort's tests pass with it | A | |
| AC9 | Carried items: M7-2 to M7-6 and L15 each done with a test where one can be written | A | |
| AC10 | Release build: a script builds the Linux x86_64 export from the pinned templates; the exported game opens, runs the tutorial's opening and quits cleanly in a smoke test | A | |
| AC11 | Cost: on the maintainer's GPU, the squadron launch, the tour and the raid: `renderer = forward_plus`, FPS, draw calls and VRAM recorded; the tick inside the 60 Hz budget during the raid | A | |
| AC12 | Docs and the suite: `docs/architecture.md` §21 as built, a `docs/playtest.md` M8 section, the roadmap row, `info.md`; `scripts/run_tests.sh` green once, at the end | A | |
| AC13 | (H) The maintainer plays it: the tutorial start to finish, the squadron launch, docking and relaunch, the escort with the strike carrier, the Battle Wagon, the audio, the release build | H | |

## Working rules for M8

- **Tracks.** A (the tutorial: T01 to T05), B (docking: T06), C (the raider capitals: T07 to T09), D (carried clean-ups: T10 to
  T14), E (release and close-out: T15 to T17). Inside a track the order holds. If work goes one task at a time, the order is the
  table's.
- **The tutorial's script is the maintainer's call.** T01 is held with the maintainer by the controller; no agent writes beats
  or lines before it. A question about the script that comes up later goes back to the maintainer.
- **The Battle Wagon's weapons are the maintainer's call** (M12's Q31): settled with the controller before T09 starts.
- **One working copy** on branch `m8` in the main checkout, no task branches.
- **Locks**: every Godot or asset-building command goes through `scripts/godot_lock.sh` with `SCS_LOCK_LABEL=<task id>` set (`write`
  for `--import`, the native build and asset builds; `read` for tests and console runs; `--gpu` for windows). Commits stay under
  `flock /tmp/m8-git.lock` with only the task's hunks staged.
- **Verify against the committed code**: touched tests run in `scripts/scratch_project.sh <name> --staged` before every commit.
- **Native changes** keep the parity recordings green; new native behaviour gets its own Rust and GUT tests. No GDScript fallback.
- **Tests.** Each task runs the Python and GUT files it touched and its new tests; the full suite runs once, in T17.
- **Screenshots** to `references/screenshots/<request>/` in the main checkout. Visual judgement is (H).
- After each task: its row says `done` with its Done notes, in the same commit; push `m8`.

## Task breakdown (ordered)

| Task | Track | Title | Depends on | Agent | Why | Status |
|---|---|---|---|---|---|---|
| T01 | A | Tutorial script: beats, lines, checks and pacing (discussion with the maintainer) | Q1 to Q4 | controller | The maintainer's design call, held as a discussion, not delegated | not started |
| T02 | A | Sawtooth Cobra-bay doors (roadmap M7-4): toothed leaves that slide apart, the launch's door ripple and timing kept | - | Opus | Generator parts and an animated door the cinematic opens on | not started |
| T03 | A | The squadron-launch cinematic (D81) | T02, T01 | Opus | Scripted launches, camera shots and a skip that lands in the same state | not started |
| T04 | A | Control checks: `ControlCheck`, the runner and the binding hints (D80) | T01 | Opus | Pass conditions on measured state for every control, pad and keyboard | not started |
| T05 | A | The tutorial mission: launch, checks, tour, raid, defense, debrief (D79) | T03, T04 | Opus | The mission script, dialog and pacing on M5's and M7's seams | not started |
| T06 | B | Dock in the main docking bay to be repaired and relaunched, for the player and the AI wingmen (D82, Q7) | - | Opus | The `dock` interaction, the lane for fighters, repair and a Cobra-bay relaunch; wing orders | not started |
| T07 | C | Bring M12-T19's raider strike carrier into `m8`: merge `origin/m12`, one collision builder, its tests green (Q5) | - | Opus | Two branches built a collision builder; docs, `native/src/lib.rs` and `info.md` conflict | not started |
| T08 | C | The civilian escort's raids come with the strike carrier (D83, Q6) | T07 | Opus | Mission data and pacing on `CarrierJumps`; the escort's tests kept green | not started |
| T09 | C | Raider Battle Wagon (moved from M12-T20): from images, with weapons (M12 Q31) and four launch tubes; the escort's last wave comes with it (Q8) | T08, the maintainer on its weapons | Fable | No STL; a new hull with weapons and tube launches | not started |
| T10 | D | Interceptor muzzle at the drawn barrel tip, and the grid balance measured again (roadmap M7-2) | - | Sonnet | A placement fix in the turret rows with a balance check | not started |
| T11 | D | The walls beside the cargo bay stop flickering (roadmap M7-3) | - | Sonnet | Find the coplanar faces or shading cause in the station generator; a test | not started |
| T12 | D | Audio rework of every sound effect and the Starfury engines' steady level (roadmap M7-5) | - | Opus | One loudness reference, the mix, and a smoothed engine gain; a listening checklist | not started |
| T13 | D | Wingmen close the gaps losses leave in a formation (roadmap M7-6) | - | Opus | Native re-slotting with M7-T76's avoidance, 1 and 6 threads identical | not started |
| T14 | D | The bench writes to `user://` in an exported build (roadmap L15) | - | Sonnet | A path fix with a test | not started |
| T15 | E | Linux x86_64 release build from the pinned export templates (Q9) | T14 | Sonnet | Templates by SHA-256, the native library and assets packed, an export smoke test | not started |
| T16 | E | Performance and the GPU check: the squadron launch, the tour and the raid | T05, T09 | Opus | Measurement on the maintainer's machine; the budget call | not started |
| T17 | - | Integration, full suite, docs and acceptance | all | controller | One full run, the GPU check, the (H) list | not started |

### M8-T01 Tutorial script (discussion with the maintainer)

- **Goal:** AC1 (D79). Held by the controller with the maintainer; not dispatched to an agent.
- **Inputs the controller brings:** the roadmap's beats, Q2's list of checks with each one's action and a proposed pass
  condition, the instructor's manoeuvres (D37), the tour points (M7-T12, T57), the station raid's knobs (M7-T10).
- **Files:** D79 in this file, `data/dialog/tutorial.json` (lines as data with voice ids for M15).
- **Done when:** AC1.

### M8-T02 Sawtooth Cobra-bay doors

- **Goal:** roadmap M7-4: the launch doors become retracting sawtooth doors (toothed leaves that slide apart) instead of today's
  flat-edged doors that swing open; the launch sequence's door ripple and its timing kept.
- **Files:** the station generator's Cobra-bay door parts and their tests, the door animation in the launch sequence, a look sheet
  for the maintainer before the generator commits (the standing rule: the maintainer sees a sheet first).
- **Done when:** the doors slide apart in a launch (headless test on their state through the sequence); the maintainer has seen
  the sheet (H).

### M8-T03 The squadron-launch cinematic

- **Goal:** AC2 (D81), as T01 placed it.
- **Files:** the cinematic's sequence on M7-T08's `LaunchSequence` and launch camera, the shots, the skip, tests (end state of
  the full run equals the skipped one, every ship formed up).
- **Done when:** AC2.

### M8-T04 Control checks

- **Goal:** AC3 (D80).
- **Files:** `src/mission/control_check.gd` and `control_check_runner.gd` (pure, test first), the `MissionApi` entry the mission
  awaits, the hint widget reading the live bindings, unit tests per check and for a rebind.
- **Done when:** AC3.

### M8-T05 The tutorial mission

- **Goal:** AC4 (D79), from T01's script.
- **Files:** `data/missions/tutorial.gd`, `data/scenarios/tutorial.json`, the dialog file from T01, the front end's New game entry,
  `tests/integration/test_tutorial.gd` (menu to debrief, the player lost), `info.md`.
- **Done when:** AC4.

### M8-T06 Dock in the main docking bay to be repaired and relaunched

- **Goal:** AC5 (D82, Q7). Today the bays' `dock` interaction answers "not available" (§20.14).
- **Files:** the `dock` interaction in `InteractionHost`, `DockingPlan`'s lane for a fighter (the player's ship flown in under
  autopilot), the repair (hull, gun charge, missiles) and its timer, the relaunch through `launch_from`, the wing order and the hull
  threshold for wingmen, their slots held while away, a `dock` console command, `info.md`, tests.
- **Done when:** AC5.

### M8-T07 Bring M12-T19's raider strike carrier into `m8`

- **Goal:** AC6 (Q5). `m12` was cut from `m7` at `b002bbe`; T19 (the strike carrier, its collision builder, `CarrierDock` and the
  native docking kernel, the raid in `CarrierJumps`) is on `origin/m12`, not yet flown by the maintainer.
- **Steps:** merge `origin/m12` into `m8`; reconcile `tools/procgen/core/collision.py` and its tests with M7's builder into one
  (the station and the carrier both built from it, their compares unchanged); resolve `native/src/lib.rs`, the docs and `info.md`;
  in the M12 file, mark T20 `not needed (moved to M8-T09)`; the M12 plan stays M12's.
- **Done when:** AC6; the station's and the carrier's Python, Rust and GUT tests pass in a `--staged --build-native` scratch copy.

### M8-T08 The civilian escort's raids come with the strike carrier

- **Goal:** AC7 (D83, Q6). All three waves come with the strike carrier here; T09 then moves the last wave onto the Battle Wagon.
- **Files:** `data/missions/civilian_escort.gd` and its scenario (the waves' `via: "carrier"` with the docked option), the
  optional objective, the dialog for the carrier, `tests/integration/test_civilian_escort.gd`.
- **Done when:** AC7.

### M8-T09 Raider Battle Wagon

- **Goal:** AC8 (Q8; M12-T20 and Q31 moved here). Weapons settled with the maintainer before work starts.
- **Files:** the generator from `raider battle wagon.png` and `raider ships and battle wagon.png` (three views and two
  perspectives; no STL, so its check is (H) on a look sheet beside that sheet), its collision from the shared builder, the four
  launch tubes as hardpoints, the hull in the game on T19's capital body, its weapons on the native turret rows, tube launches for
  Delta-Vs, a sandbox scenario and free-flight raids, the civilian escort's last wave moved onto it (its mission data, dialog and
  `test_civilian_escort.gd`), `docs/assets-capital.md`, tests.
- **Done when:** AC8.

### M8-T10 Interceptor muzzle at the drawn barrel tip

- **Goal:** roadmap M7-2: a battery's pulse and its muzzle flash start at the drawn barrel tip (placed from the shown angles), and
  the grid balance is measured again.
- **Done when:** a test puts the pulse's start at the barrel tip within a few centimetres at 30 m; the balance fights pass.

### M8-T11 The walls beside the cargo bay stop flickering

- **Goal:** roadmap M7-3: find the coplanar or overlapping faces, or the shading cause, and fix it in the station generator.
- **Done when:** a Python test finds no coplanar overlap there; the maintainer sees no flicker (H).

### M8-T12 Audio rework

- **Goal:** roadmap M7-5: every effect's level, mix and attenuation against one loudness reference; the Starfury engines' gain
  smoothed and the thrusters summed to a steady level per throttle, with no clipping.
- **Files:** the sound generators and buses, the engine audio, tests on the engine gain's steadiness, a listening checklist in
  `docs/playtest.md`.
- **Done when:** the tests pass; the maintainer's listening checklist (H).

### M8-T13 Wingmen close the gaps losses leave

- **Goal:** roadmap M7-6: wingmen behind a lost Starfury move up into the empty slots in `Wing.fill_order`'s order, flown with
  M7-T76's avoidance, with no ally rams; native kept 1 and 6 threads identical, parity kept.
- **Done when:** a seeded headless fight shows the formation without holes after losses, with no ally rams; parity green.

### M8-T14 The bench writes to `user://` in an exported build

- **Goal:** roadmap L15 (`docs/research/m4-full-review.md`).
- **Done when:** the bench reads and writes under `user://` when `res://reports` is not writable; a test covers both.

### M8-T15 Linux x86_64 release build

- **Goal:** AC10 (Q9).
- **Files:** a `scripts/` build script, `export_presets.cfg`, the templates' version and SHA-256 in `docs/research-notes.md`,
  `docs/third-party.md` if anything is added, an export smoke test.
- **Done when:** AC10.

### M8-T16 Performance and the GPU check

- **Goal:** AC11.
- **Done when:** AC11's numbers recorded in this file and `docs/architecture.md` §21.

### M8-T17 Integration, full suite, docs and acceptance

- **Goal:** AC12 and AC13. Docs as built, the M8 checklist in `docs/playtest.md`, the roadmap row, `info.md`; the full suite once;
  the maintainer's play-test.
