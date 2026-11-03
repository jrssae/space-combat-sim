# Milestone 5: Mission Framework and Front End

> "Scripted play." (`docs/roadmap.md`)

**Status:** planned 2026-11-02 on branch `m5`, cut from `main` at `b2f8ce1` (M3 merged) while M4 goes on separately on `m4`.
The maintainer asked for M5 to run beside M4 because most of it does not touch the performance work, and expects `m5` to
be rebased onto `main` once M4 merges (see "Living beside M4"). The planning questions were answered the same day (below),
including the civilian ships' lengths and a seventh civilian hull, the Centauri Brezebel (Q8, Q11). A ninth hull, the
Brakiri Bokmai transport with removable cargo pods, was added during the build (Q17).

Read `docs/architecture.md` first, especially §6 (input and the console), §8 (camera), §14.6 (the mission framework as
first sketched), §15.10 (scenarios and waves), §15.12 (control profiles) and §16 (the M3 AI: D36 wings, D37 the instructor,
D39 broadcasts and pilot objectives). Tasks are ordered inside each track; each is one PR-sized unit and names a
recommended agent model.

## Goal

Turn the sandbox into a game you start from a menu. The player boots into a front end, picks free flight (with or without
encounters) or a mission, and plays it. A mission is a scenario plus a script that talks to the player through subtitles,
sets objectives, cuts to a cinematic camera, sends raiders at things and ends in a debrief. Settings and controls get real
menus. Free flight gets traffic: raiders, allied patrols and nine new civilian ships built from the maintainer's
references and online images. The sound pass replaces the engine loops with per-thruster bursts and gives both guns and the bolt impacts new
voices. M8's tutorial is written on top of all this, so the framework matters more than the one demo mission.

## Maintainer answers (2026-11-02)

| Q | Question | Answer |
|---|---|---|
| Q1 | Which demo missions prove the framework? | **Buoy defence**, with a **scripted cinematic intro**: raiders are sent at a nav buoy from beyond sensor range; the player and their wing defend it. Objectives, comms lines, win and fail, debrief |
| Q2 | What sits behind the front-end menu (the B5 interior needs M7's station)? | **Sky only** |
| Q3 | What does "random encounters on" mean in free flight? | **Mixed traffic**: raiders, allied patrols and neutral traffic |
| Q4 | A pad comms menu for wing orders? | **D-pad Right opens a comms menu**; keys 1-4 stay |
| Q5 | What is the neutral traffic? | **New civilian ships** built from the maintainer's STL references: the **Saturn 3 freighter**, **Saturn 4 transport**, **Saturn 8 transport** and **Saturn fuel tanker**, the **Narn transport** and the **EA Skylark transport** |
| Q6 | Push `m5` after each task? | **Yes**, as on M3 and M4. After the later rebase the agent asks before force-pushing (`--force-with-lease`) |
| Q7 | Keep a quiet low rumble under the new engine bursts? | **No: bright bursts only**, as measured in the reference (nothing below about 300 Hz) |
| Q8 | How long is each civilian ship? | **Saturn 8 transport and Saturn fuel tanker about 200 m, Saturn 4 transport about 100 m, Narn transport about 70 m, Skylark about 60 m.** The **Saturn 3** uses the same transport pods as the 4 and 8, three of them in a group behind the same control section, so its length follows from those parts |
| Q9 | Do raiders attack civilian ships? | **Yes.** Raiders prey on them, civilians evade and run (the M3 civilian profile), allies defend them. Civilians take hull damage and break up like every other ship |
| Q10 | How are tests run during M5? (the maintainer's instruction when starting M5) | Only the tests for the areas a task changes, plus the new tests it adds. The full suite runs once, at the end of the milestone (T20). Agents may run in parallel ("as many agents as needed") |
| Q11 | More civilian ships? Colours? (maintainer, with Q8) | **Add the Centauri Brezebel transport, about 60 m.** For **every** civilian model, take the colour scheme from online images of that ship |
| Q12 | The player's radar reaches 25 km, the AI's sensors 5 km: how do arriving ships appear without popping onto the radar? | **Raiders jump in, traffic cruises.** Raiders arrive through a jump point 6-12 km out with a placeholder flash (M6's vortex replaces it). Patrols and civilians spawn past 25 km on routes that bring them by |
| Q13 | (maintainer, with Q12) Are civilians unarmed? | **No: civilian ships carry defensive weapons.** They still run, and fire defensively. Details in Q14 |
| Q14 | What weapons, when do they fire, how strong? | **Small turrets**: 2-4 light turrets per hull by size, each with its own firing arc, lead-aimed, about 1.5 km range, built as a turret system M12's capital ships can reuse. **Only at attackers**: a turret fires at a ship that has shot at its own ship, or at another civilian or ally close by; a raider flying past is left alone. **Deterrent only**: they hurt raiders and may finish a damaged one, but a raid of two or more raiders still wins unless the player or a patrol helps |
| Q15 | (maintainer, after reading the menu list) Settings layout | **Options on the left; the bottom left is reserved for a controller image with what each button does; the right side has a place for mission objectives.** It applies to the in-flight pause menu and the settings and controls screens, opened from pause or from the front end |
| Q16 | (after T11 measured the references) Built from the Saturn 4's parts, the Saturn 8 is only about 168 m and the tanker about 161 m: how do they reach 200 m? | **The Saturns are modular.** The Saturn 4's **100 m is the length of its cargo section**, not of the whole ship. The Saturn 8's **200 m is two Saturn 4 cargo sections** (or two tank sections for the tanker). A **Saturn 4 with tanks** also exists, half a Saturn 8 tanker. **The Saturn 3 uses the same lead ship** (control section) as the 4 and the 8. Ids (planner's call): `saturn_4_tanker` (new) and `saturn_8_tanker` (was `saturn_fuel_tanker`) |
| Q17 | (maintainer, during the build) Another civilian ship | **Add the Brakiri Bokmai transport, about 80 m, in the Brakiri green and yellow** (the maintainer first said brown and corrected it the same evening). **The cargo pods in its centre are removable.** Reference: `references/Brakiri_Bokmai_transport_80m.STL`. Planner's calls: the generator builds the hull and one pod model apart, a Bokmai flies with three, two, one or no pods, a destroyed Bokmai sheds its pods as debris, letting go of a pod in flight or towing one waits for M14's tether, and its faction is a new `brakiri` |
| Q18 | (maintainer, during the build) How close to the references? | **Every civilian model within 90 % of its STL**, measured as **silhouettes and size**: the top, side and front silhouettes each overlap the STL's by at least 90 % (intersection over union) at the same length, and length, width and height each lie within 10 %. **Civilian ships only**: the Starfury stays as built, and the raider has no STL. Planner's calls: the score is taken on the LOD0 splats by `tools/refview`'s compare mode (T23); where Q16 departs from a model on purpose (the Saturn 8s' 200 m of cargo, the Saturn 3's engine section, the Saturn 4 tanker, which has no model of its own), each part is scored against the part of the model it came from |
| Q19 | (after the review sheet of turret spots and colours) Turrets and colours | **Turrets on top only:** keep every dorsal spot proposed, drop every ventral one. That leaves the Saturn 4 transport, Saturn 4 tanker, Saturn 8 transport and Saturn 8 tanker with two each (`dorsal_fwd` on the disc hub and `dorsal_aft` or `dorsal_mid`), the Saturn 3 with one (`dorsal_fwd`), the Skylark and the Brezebel with one (`dorsal`), the Narn transport with its two tower turrets. **Colours confirmed** as written for the Saturn family, the Skylark, the Narn transport and the Brezebel. **The Narn transport's towers point up** (T11's reading). The maintainer places turrets and confirms colours for any further ship (the Bokmai) before its generator commits them |
| Q20 | (same day) Where is the Saturn 3's engine? | **Between the two lower pods, on the centre line, directly under the top pod**, and **just long enough that its exhaust clears the pods**. It is a **slimmer engine** than the shared section so it fits the gap between the lower pods; the pods keep their places. The Saturn 3's aft turret is dropped. For the 90 % check (Q18) the Saturn 3's pod group is scored against the model's pod group **scaled up to the shared pod size** (Q8), so shape and layout are checked rather than the size the maintainer chose |
| Q21 | (maintainer, 2026-11-03) The mission's buoys | **Buoy defence is set on a string of nav buoys in a huge circle, as if round a planet: 16 buoys on a ring of 20 000 km radius, about 7 850 km apart.** **Every buoy broadcasts to 10 000 km** (was 1 000 km, M3 Q21), and the spacing is set so that a ship always has **at least two buoys in broadcast range**, on the radar and targetable: anywhere on the ring, and within about 6 000 km of it. There is no planet in the middle yet (M6 brings Epsilon III) |

## Scope

In:
- **Game flow**: a `Game` autoload with the states front end, loading, in space and debrief; a boot scene that routes a
  normal launch to the front end and every headless, scripted or benchmark run straight to `Main`, as today.
- **Front end over the sky**: missions, free flight (encounters on or off), a sandbox list (the existing scenarios),
  settings, controls, quit. A pause menu on Start in flight. A loading screen while a scenario's pools fill.
- **Settings menu** built from `SettingsSchema` (user-facing entries only) and a **controls menu** that remaps on top of
  M2's control profiles.
- **Mission framework**: mission scripts as GDScript coroutines over a small API, named steps that the console can skip,
  triggers, objectives with success and failure, dialog lines as data, subtitles and a comms panel, a `CINEMATIC` camera
  mode with locked controls, and a debrief.
- **Comms menu on D-pad Right** with the four wing orders.
- **One mission**: Buoy defence with a cinematic intro.
- **Civilian ships**: nine hulls in five generators (the Saturn family with five variants, the Skylark, the Narn
  transport, the Centauri Brezebel, the Brakiri Bokmai with removable cargo pods), measured from the references and
  rebuilt in `tools/procgen`, coloured after online images of each ship; factions `civilian`, `narn`, `centauri` and
  `brakiri`.
- **Free-flight encounters**: raider raids, allied patrols and civilian traffic, seeded, spawned from pools beyond sensor
  range, capped in ship count.
- **Sound pass**: new Starfury and raider gun sounds, new bolt impacts, per-thruster engine bursts placed on the ship.
- Console commands and providers for all of it (§6.4), schema entries for every new setting.

Out (explicitly):
- The Babylon 5 station, its interior behind the menu and launch bays (M7). The tutorial and its control checks (M8).
- Voiced dialog (M15). Lines carry a voice id now; nothing reads it yet.
- Music. Saved mission progress or unlocks (every mission is open; nothing persists but settings and control profiles).
- Mission types beyond what Buoy defence needs: escort, rescue and towing, asteroid fields (M14). Capital ships (M12).
- Performance work on the AI, contact scan, targeting, rams or the rebase (M4 owns those files; see below).
- A key or button to remember the last camera view (not wanted now, `docs/handoff-m4.md`).

## Living beside M4

`m5` and `m4` move at the same time and will meet in a rebase. To keep that rebase small:

- **Do not edit the files M4 is reworking** unless a task cannot be done otherwise, and then keep the change small and
  list it in the task's Done notes: `src/ai/contact_scan.gd`, `src/ai/perception.gd`, `src/ai/ai_pilot_driver.gd`,
  `src/targeting/targeting_controller.gd`, `src/targeting/targeting_system.gd`, `src/combat/ram_resolver.gd` and anything
  under `src/perf/`. Raiders target civilians through faction data (`data/factions.json`), not through scan or brain code.
- **`src/game/main.gd` is shared.** M4 added `ensure_pool` and the bench wiring. M5 should move new work out of `Main` into
  its own nodes (`MissionRunner`, `EncounterDirector`, `CommsMenu`, the pause menu) and touch `Main` only to create and wire
  them, in small hunks.
- **`docs/architecture.md`**: M4 writes §17. M5's design goes in a new **§18** at the end of the file. In `m5` it follows
  §16 until the rebase; then it moves after §17. Decision numbers for M5 start at **D50**, leaving D46-D49 to M4.
- `scripts/run_tests.sh`: M5 adds its smoke runs as separate lines at the end, so a conflict is a two-line merge.
- `info.md` (the console command list, `CLAUDE.md`): M4 may create it too; on the rebase the two lists merge into one.
- The M4 benchmark numbers come from an otherwise idle machine (`docs/handoff-m4.md` §3). Before a heavy Godot run
  (a GUT directory, a GPU capture), check `pgrep -af 'bench'`; if an M4 benchmark is running, wait for it to finish.

## Design (to go into `docs/architecture.md` §18)

### D50 Boot and the `Game` flow

- `Game` (autoload, `src/autoload/game.gd`) holds a pure `GameFlow` (`src/game/game_flow.gd`, `RefCounted`) with the states
  `FRONT_END`, `LOADING`, `IN_SPACE`, `DEBRIEF` and the transitions between them; `GameFlow` is unit-tested without a tree.
  `Game` changes scenes and carries the request across them: `{kind: free_flight | mission | sandbox, scenario_id,
  encounters, seed}`. It never reads `Input`.
- The project's main scene becomes `src/frontend/boot.tscn`. Boot decides once, at start: a normal windowed launch goes to
  the front end. These go straight to `Main` with `Settings.scenario` exactly as today: `--headless`, any `--console-exec`
  or `--console-file`, a new `--scenario=<id>` argument, or the setting `skip_front_end` (bool, false). So the M4 benchmark,
  every `scripts/*.sh` smoke run and every test keep working unchanged. Tests that instantiate `main.tscn` are unaffected.
- **Loading** shows a loading screen, then loads `main.tscn` with `ResourceLoader.load_threaded_request` and instantiates
  it. `Main._ready` still fills the pools in one go (D22: no splat node enters the tree during play); the hitch now happens
  behind the loading screen. Any ship a mission or an encounter will ever spawn comes from a pool declared in its scenario.
  Acquiring past a pool's size is an error that fails the tests, never a silent instantiation.
- `scenario <id>` (console) keeps reloading `Main`. New: `menu` (back to the front end), `play <scenario_id> [seed]`
  (through loading, like the menu does) and the `game` provider (`state`, `request`, `last_result`).

### D51 Missions are scenarios with a script of named steps

- A mission is a scenario JSON (`data/scenarios/<id>.json`) with a `mission` block: `{title, briefing, script, dialog,
  objectives[]}`. `script` is a GDScript path (`res://data/missions/<id>.gd`) whose class extends `MissionScript`.
  `dialog` is a dialog file (D53). Free flight and the sandbox scenarios have no `mission` block and run as today.
- `MissionScript` declares its steps in order (`steps() -> Array[StringName]`), each a method `step_<name>(m: MissionApi)`
  that runs as a coroutine. `MissionRunner` (node under `Main`) awaits each step in turn.
- `MissionApi` is the whole surface a script sees. First version: `await m.say(line_id)`, `await m.wait(seconds)` (sim
  time from physics ticks, never the wall clock), `await m.until(trigger)`, `m.spawn(spawn_dict)` (from a pool, through the
  scenario loader's spawn rules; a spawn with `arrival: "jump"` comes out of a jump point, below), `m.send(ship_name, objective_name)` (D39's pilot objective), `m.objective_add/complete/
  fail(id)`, `m.waypoint(name | null)`, `await m.cinematic(shot_id)`, `m.lock_controls(bool)`, `await
  m.player_did(action)` (an input-performed trigger for M8), `m.end(success)`.
- **Skipping fast-forwards and forces.** `mission skip` sets a skip flag on the current step: every `await` in the API
  returns at once, and every call that changes the world (`spawn`, `send`, objectives) still runs. An awaited trigger is
  not just resolved but **made true**, so the world ends where the step would have left it: `destroyed` releases the named
  ships (no explosion, kill credit to nobody), `proximity`, `area` and `arrived` place the actor at the goal (`reset_to`,
  velocity kept), `timer`, `dialog_finished` and `input_performed` simply resolve, and an objective whose success trigger
  is forced completes. Lines are logged, not shown; cinematics end. Each trigger kind has its `force()` next to its test.
  `mission goto <step>` skips each step until the named one; M8's tutorial checks lean on it. (Planner's call,
  2026-11-02, after the builder check: resolving without forcing would leave a skipped wave alive.)
- **Jump arrivals (Q12).** `JumpArrival` (node, pooled, no splats) shows a jump point opening at a universe position: a
  short bright flash, a light and a generated `jump_in` sound; the spawned ships appear inside it and fly out on their
  spawn velocity. A placeholder until M6's jumpgate vortex; missions and encounters use the same call.
- The runner also ends the mission: success when every primary objective is done (or the script calls `m.end(true)`),
  failure when a primary objective fails, the script calls `m.end(false)` or the player's ship is destroyed. In a mission
  the player does not respawn (free flight and the sandbox keep today's respawn).

### D52 Triggers and objectives

- Triggers are pure `RefCounted` predicates over a `MissionWorld` snapshot (positions as `UniversePos`, alive sets, sim
  time, finished dialog lines, this tick's player action edges from `InputAdapter`'s output). Kinds: `proximity` (actor
  within r of actor or point), `area` (inside a sphere), `timer`, `destroyed` (one or all named), `dialog_finished`,
  `input_performed` (an action name), `arrived` (an AI actor reached its route's end or a point). `TriggerSpec.from_dict`
  builds them from JSON, so objectives in the scenario can name them.
- `ObjectiveBook` (pure): objectives `{id, text, primary, state: hidden | active | done | failed, success, fail}` where
  `success` and `fail` are optional trigger specs evaluated by the runner each tick. The HUD lists active objectives; the
  debrief lists all of them.
- The runner evaluates triggers once per physics tick after the world moved (late priority, after the resolvers). Cost:
  with 20 live triggers it adds under 0.2 ms to a tick (counted work in a test, not milliseconds).

### D53 Dialog, subtitles and the comms panel

- Lines are data: `data/dialog/<file>.json` holds `{lines: [{id, speaker, text, voice, hold_s?}]}`;
  `data/dialog/speakers.json` holds `{id, name, callsign, faction}`. `voice` is the M15 voice id, unused now. A line's
  hold time is `hold_s` or derived from its length (about 2.5 words a second, at least 2 s).
- `DialogQueue` (pure) orders lines (one at a time, a queue, a `say` that interrupts). A test checks that every line id a
  mission script uses exists in its dialog file and every speaker exists.
- The **comms panel** shows the speaker's callsign in their faction's colour and the line as a subtitle, at the bottom of
  the window in both camera views (the cockpit's right screen keeps the wing roster and acknowledgements). Generated
  `radio_open` and `radio_close` squelch sounds frame each line (`sfx_ui`, D57).

### D54 The comms menu on D-pad Right

- New action `comms_menu`: pad D-pad Right, plus a keyboard key under the left hand (the task picks a free one; keys 1-4
  stay the wing orders). Profiles saved before M5 get it filled from `default` when they load (M3-T07's mechanism).
- While the menu is open, the four D-pad directions pick its four entries and B closes it; it closes itself after 4 s.
  `InputAdapter` routes those presses to `UiCommand.comms_pick` (0-3) and `comms_close`, so assist, next weapon, lights
  and the target button do not fire while it is open. Gameplay still never reads `Input`.
- First page: the wing orders, through the same `WingDirector.give_order` the keys use. `CommsMenu` (pure model) takes
  pages, so a later mission can push a page of replies; M5 builds no reply page.

### D55 The `CINEMATIC` camera and locked controls

- `CameraRig.Mode` gains `CINEMATIC`. A shot is data in the mission's scenario (`cinematics: {<shot_id>: {...}}`): keys of
  `{t, position, look_at, fov}` where `position` and `look_at` are an actor name plus an offset in that actor's frame or
  the scenario origin plus a universe offset. `CinematicShot` (pure) interpolates the keys (Catmull-Rom on positions,
  smoothed look-at) and is unit-tested; the camera node is in `world_shiftable`, so a rebase mid-shot does not jump.
- During a cinematic the HUD hides, letterbox bars slide in, the player's `FlightCommand` and `CombatCommand` are zeroed
  (the ship keeps flying under physics; assist stays as set), and A or Start skips the shot. `lock_controls(true)` alone
  does the zeroing without the camera.

### D56 Debrief

- `DebriefModel` (pure) from the runner's result: success or failure and why, every objective and its state, mission
  time, the player's kills and assists (§15.10's `KillCredit`), wing losses, shots fired and hit. The debrief screen offers
  retry (same scenario and seed through loading) and the front end.

### D57 Menus, the front end and the pause menu

- Pad first. Every screen is Godot `Control`s with one project `Theme` (`src/frontend/theme.tres`, the HUD's green on dark),
  focus moved by the D-pad or left stick, A to accept, B to go back; arrow keys, Enter and Esc and the mouse also work.
  Menus use Godot's `ui_*` actions; `ControlProfiles` must leave those actions alone when it applies a profile (a test
  checks this).
- Front end (`src/frontend/front_end.tscn`): the `sky_default` sky with a slow camera drift and the menu. Entries:
  **Missions** (each scenario with a `mission` block: title, briefing, start), **Free flight** (encounters on or off, from
  `Settings.encounters`), **Sandbox** (combat_sandbox, dogfight, instructor_route), **Settings**, **Controls**, **Quit**.
- **Pause menu** on Start in flight (the `pause` action, as today): Resume, Restart, Settings, Controls, Quit to menu. The
  world pauses; the menu's process mode is always.
- **The three-panel frame (Q15).** The pause menu and the settings and controls screens share one layout, `MenuFrame`:
  - **Left, top:** the options (the pause entries, or the settings list by category, or the controls list), scrolling
    when long.
  - **Left, bottom (reserved):** a controller diagram with a legend of what each button does. The pad is drawn in code
    (an original generic XInput outline: sticks, D-pad, face buttons, bumpers, triggers, Back and Start), no image file.
    Labels come from the active control profile (`ControlProfile.describe_action` per pad descriptor), so a remap shows
    at once. In flight it shows the flight layout; the controls screen highlights the button of the action in focus.
  - **Right:** mission objectives from the running mission's `ObjectiveBook` (state marks, primary and optional). In
    free flight it shows "Free flight" and whether encounters are on; opened from the front end it shows the briefing of
    the mission selected there, or nothing.
  The panel contents come from small providers (`objectives_source`, `bindings_source`), so T02 builds the frame before
  T05's objectives exist and T05 only plugs its book in.
- `SettingsSchema` entries gain `category` (`flight`, `controls`, `camera`, `hud`, `graphics`, `audio`, `game`) and
  `menu: false` for the debug switches that stay console-only. The settings screen is built from the schema: a toggle,
  slider or option list per entry, with apply, revert and defaults (`Settings.save`, `revert`, `reset`). A test fails when
  an entry has no category.
- Audio settings: `master_volume`, `sfx_volume` (exists), `ui_volume`, `comms_volume`, each its own bus. Generated UI
  sounds (`sfx_ui`: move, accept, back, radio open and close).
- Controls screen: pick a profile (built-in or saved), list actions with their bindings (`ControlProfile.describe_action`),
  rebind by pressing a button or key (`ControlProfile.descriptor_of`), unbind, save as. `ControlProfiles.bind`/`unbind`
  do the validation (a pad binding on every action, never the console key); refusals are shown, not swallowed.

### D58 Free-flight encounters

- `EncounterPlan` (pure, seeded by the session seed) decides when and what: an event every 60-180 s of sim time
  (`encounter_interval_s` range), drawn by weight from **raider raid** (2-6 raiders sent at the player or at a civilian
  inside 20 km), **allied patrol** (2, 4 or 6 Starfuries on a route through the area; they engage raiders they meet),
  **civilian traffic** (1-3 civilian ships on a straight route that passes 2-10 km from the player).
- **Arrivals (Q12).** Raiders **jump in** 6-12 km out (beyond the AI's 5 km sensors): a jump point opens with a short
  placeholder flash (D51's `arrival: "jump"`), then the group flies out of it. Patrols and civilians **cruise in**: they
  spawn 26-30 km out, past the player's 25 km radar, on routes that bring them by, so they come in at the radar's edge.
  `EncounterDirector` (node) spawns everything from pools prepared at load and releases a ship once it is 40 km from the
  player or its route has ended.
- `encounter_max_ships` (default 24, ships alive at once besides the player and their wing) caps it: an event that would
  pass the cap waits. M4's numbers, not M5, decide when the cap can rise.
- Factions (`data/factions.json`): `civilian` (Earth-registered merchants: the Saturns and the Skylark), `narn` (the Narn
  transport), `centauri` (the Brezebel) and `brakiri` (the Bokmai, Q17). Raiders are hostile to all four. Earth Alliance
  and `civilian` are allied; `narn`, `centauri` and `brakiri` are neutral to everyone else (civilian turrets fire only at
  attackers, D61, so a feud between them would change nothing in M5). Civilians fly the M3 `civilian` AI profile (never attack, evade, run from hostiles within 3 km).
- **Encounters run only when asked for.** The front end's Free flight screen puts `encounters` into `Game`'s request and
  remembers the choice in `Settings.encounters` (bool, true: the menu's default). A run that goes straight to `Main`
  (headless, `--console-exec`, `--scenario=`, the `scenario` command, every test) has encounters off unless the console
  says `encounters on`, so free flight there stays as empty as today and the existing smoke line (`raiders.pool_size = 0`)
  holds. The encounter pools live in `data/encounters/free_flight.json` and are added to the scenario's pools at load only
  when encounters are on; with them off nothing extra is built. `encounters on` mid-run without those pools refuses with
  a message.

### D59 Civilian ships

- Five generators, nine hulls, the same output contract as §9 and §15.11: hull PLYs for LOD0-3 with lighting records,
  fallback mesh and depth proxy, `hardpoints.json` with pods and nozzles (main and RCS), collision primitives that cover
  the splats, `cockpit_camera` and `chase_anchor` (the parser needs them), running lights, and `chunks[]` from
  `core/chunks.py`. **Defensive turrets (Q13, Q14, D61):** `hardpoints.json` gains `turrets[]` (dorsal mounts only, one or
  two per hull, where the maintainer placed them, Q19), and each style has one generated turret model; civilians still run
  from raiders (the `civilian` profile) while their turrets fire in their own defence.
  - `saturn_family` with variants `saturn_3_freighter`, `saturn_4_transport`, `saturn_4_tanker`, `saturn_8_transport` and
    `saturn_8_tanker` (Q16). The family is modular: one **lead ship** (the control section with the command sphere, its
    truss and the engine section, the same size on every variant) plus cargo. A **Saturn 4 cargo section** (four
    transport pods on their arms, or the tank group) is **100 m long**. The Saturn 4 transport and the Saturn 4 tanker
    carry one such section; the Saturn 8 transport and the Saturn 8 tanker carry two of the same sections, **200 m** of
    cargo; the Saturn 3 freighter carries three of the same transport pods in a group behind the same lead ship. Each
    ship's overall length is the lead ship plus its cargo, so it follows from the parts. The Saturn 3's engine (Q20) is a
    slimmer one that sits between its two lower pods, under the top pod, with its exhaust just clear of the pods' aft
    faces, so the Saturn 3 ends a little behind its pods.
  - `skylark_transport` (about 60 m): a central body with two engine nacelles on short pylons and a rear module.
  - `narn_transport` (about 70 m): a crescent bow, a boxy cargo hull and engines on the flanks, in a new `narn` style.
  - `centauri_brezebel` (about 60 m): the Centauri Brezebel transport (`references/Centauri_Brezebel_Transport.stl`, an
    ASCII STL added 2026-11-02): a rounded bow and two long swept arms reaching aft, in a new `centauri` style.
  - `brakiri_bokmai` (about 80 m, Q17): the Brakiri Bokmai transport (`references/Brakiri_Bokmai_transport_80m.STL`,
    binary, added 2026-11-02), in a new `brakiri` style, green and yellow. A first look: three rounded cargo pods in a
    row amidships, held in an open frame of curved arms under a dorsal spine; at one end a crossbar carries two tall
    vertical fins or nacelles at its tips. T22 reads which end is the nose. **The pods are removable.** The generator
    writes the hull without its pods and one pod model (`<id>_pod.*`, LOD0-3 at the hull's spacings so it switches with
    the hull), and `hardpoints.json` gains `cargo_pods[]` (`{name, position, up}` in the body frame) for the three
    mounts; the pod's collision primitives and splat counts go in a `pod` entry of the manifest, as the turret's do. In
    the game (T16) a Bokmai spawns with 0-3 pods from its spawn data (`cargo_pods`, default 3; encounter traffic draws
    the count from the seed). Each pod is a splat pooled with its ship (D22) and adds its mass and collision shape; a
    destroyed Bokmai sheds its pods as debris along with its chunks. Letting go of a pod in flight, or towing one, waits
    for M14's tether (§14.7). Turrets sit on the frame, not on the pods, so an empty Bokmai still defends itself; the
    maintainer places them (Q19).
- **The references are never copied.** As with the Starfury (`docs/design-references.md`, 2026-10-30), the agent renders
  orthographic views and cross-sections of the untracked STL files, measures them, writes a description of each ship into
  `docs/design-references.md`, and builds the hull in code from those measurements. No STL geometry, vertex data, image or
  texture goes into the generators or into git. Renders and downloaded images go to `reports/refs/<ship>/` (gitignored).
- **Fidelity (Q18).** Each model is within 90 % of its STL: `tools/refview` compare (T23) draws the top, side and front
  silhouettes of the STL (at the ship's length, in the authored frame) and of the model's **geometry** on one grid, and
  each view's intersection over union must be at least 0.90, with length, width and height within 10 %. The geometry is
  the asset's fallback mesh (`<id>.obj`), which every civilian generator builds from the same parts as its splats and
  which must therefore hold every visible part. (Planner's call after the T23 review, 2026-11-03: scoring the splats
  themselves under-read a perfect copy of the Saturn 4 by 5 to 8 % and favoured parts built too thin.) A second check
  keeps the splats honest: the LOD0 splats against their own mesh score at least 0.85 per view, which catches a missing
  or misplaced part without the splat penalty deciding the verdict. Turrets are left out (the models have none); the
  Bokmai is scored with its three pods mounted. Where Q16 departs from a model on purpose, each part is scored against
  the model it was built from, cropped on both sides and aligned on its own: the Saturns' lead ship and transport
  section against the Saturn 4 model, the tank section against the tanker model, the Saturn 3's pod group against the
  Saturn 3 model scaled up to the shared pod size (Q20). Overlays and scores go to `reports/refs/<ship>/compare/`; each
  generator task writes its scores into `docs/assets-civilian.md`.
- **Colours from online images (Q11).** For each of the nine ships the agent finds images online (screen captures, fan
  wiki pages), reads the colour scheme off them (base plating, panel and trim colours, markings, window and engine glow),
  and writes it into the ship's description as colour values and where they go. The generators paint from that written
  scheme through the styles `ea_civilian`, `narn`, `centauri` and `brakiri`; per-hull trim lives in the variant data. The images
  themselves are references only, like the STLs.
- Splat budgets scale with size and LOD; ships this large are mostly seen at range, so LOD2 and LOD3 carry most of the
  time on screen. The task sets each budget so that all nine in view (the Bokmai with its three pods) stay within `splat_budget` and
  records VRAM.
- Flight: each hull flies through the one `FlightModel` (§15.16), heavy and slow (`ShipSpec` mass, thrust and inertia per
  hull; turning is torque only). Civilians break up into their chunks when destroyed, with the usual explosion.

### D61 Defensive turrets (Q14)

- A turret is a gunner, not a pilot: the ship's `AiPilot` keeps flying (a civilian runs) while its turrets pick their own
  targets. `TurretAim` (pure): traverse and elevation limits from the mount's arc, slew rates, lead from `InterceptMath`,
  a fire gate (inside the arc, inside range, the lead error under the bolt's spread at that range). `ThreatMemory`
  (pure): a ship becomes an attacker of a victim when one of its bolts hits that victim (`HitResolver`'s results, shooter
  and victim) and stays one for 30 s; a turret may fire only at an attacker of its own ship, or of a civilian or ally
  within 2 km of it. Both are unit-tested.
- `hardpoints.json` `turrets[]`: `{name, position, up, arc_deg, barrel_m}` in the body frame. `TurretMount` (node, child
  of the ship, built by `ShipAssembly`) holds the turret's model, turns it in `_process` from the physics-tick aim, and
  fires through the existing kinematic projectile pool and `HitResolver` (no new hit path). A generated `turret_fire`
  sound, built like D60's guns but lighter.
- Strength (Q14, deterrent): a light bolt, low fire rate, about 1.5 km range. A seeded headless fight pins the balance:
  two raiders destroy a lone Saturn 4 transport within 180 s in at least two of three seeds, and the transport's turrets
  finish a raider left at 15 % hull that keeps attacking it.
- The seam is general: any ship with `turrets[]` gets them (M12's capital ships). Targeting and the fire gate cost work
  linear in turrets times attackers, never a sweep over all ships (`ThreatMemory` keeps the short attacker list).
- Visuals: the turret model is a small splat (pooled with its ship, D22). If turning many small splat nodes each frame
  costs measurable GPU or sort time, the task falls back to the fallback-mesh model for turrets and says so.

### D60 The sound pass

- Guns (`tools/procgen/assets/sfx_combat.py`), from `docs/design-references.md` "Combat sounds": the Starfury's
  `pulse_fire` is a click attack, a metallic inharmonic cluster from two-frequency FM (our own base and ratio near the
  reference's), a flat hold of about 100 ms and a hard cut; no sweep, no thump. The raider's `raider_fire` is built the same
  way but is clearly another weapon: lower, buzzier, a different cut. Both keep M3-T15's register: every frequency times
  `GUN_PITCH` (0.25), lengths unchanged (Q17 of M3). The sound follows the cannon's own fire rate; no burst rhythm is added.
- Impacts: a new `hit_hull`, bright, metallic and short, same register. `explosion` keeps its low body.
- Engines (Q7): `main_burst` (noise 400 Hz-16 kHz, peak 4-8 kHz, about -5 dB per octave above 1 kHz, slow 3 dB wander) and
  `rcs_burst` (noise 2-16 kHz, brightest 6-16 kHz, brightness rising in the attack and falling in the release) are
  seamless loops; `AudioDirector` shapes attack and release per voice from the reference's numbers. **Nothing below about
  300 Hz.** `engine_loop` and `thruster_loop` go.
- Voices: each main pod and each RCS cluster (the RCS jets grouped by position, a handful per ship) gets a voice at its
  place on the ship, driven by `ThrusterGlowLevels.targets`. The player's ship always has its voices; other ships get pod
  voices only, and only the nearest few within audible range. A voice cap (`engine_voice_cap`, default 24) bounds the
  work; the per-frame update is linear in voices, not in ships times nozzles (a work-count test).

## Acceptance criteria

| # | Criterion | Kind | Done |
|---|---|---|---|
| AC1 | Boot: a windowed launch shows the front end; `--headless`, `--console-exec`, `--console-file`, `--scenario=<id>` and `skip_front_end` go straight to `Main` as before; `GameFlow` transitions unit-tested; `game` provider, `menu` and `play` commands work under `--console-strict` | A | |
| AC2 | Front end and pause: the pause menu and the settings and controls screens use the three-panel frame of Q15 (options left, pad diagram with live bindings bottom left, objectives right; a test checks the legend follows a rebind); every screen is reachable and usable with the pad alone (a test drives focus with injected `ui_*` events); free flight starts with encounters on or off; Missions lists Buoy defence with its briefing; Sandbox starts each existing scenario; Quit quits; Start in flight opens the pause menu and Quit to menu returns to the front end; a loading screen shows while `Main` loads; no splat node enters the tree during play | A | |
| AC3 | Settings menu: every schema entry has a category; entries with `menu: false` are hidden; changing, applying, reverting and resetting a value works and persists through `Settings.save`; four audio buses with their volumes | A | |
| AC4 | Controls menu: pick a profile; rebind an action by pressing a button; unbind; save as; the profile rules are enforced with the reason shown; applying a profile leaves the `ui_*` actions intact | A | |
| AC5 | Mission runtime: `MissionScript`, `MissionApi`, `MissionRunner`; every trigger kind unit-tested; `ObjectiveBook` success and failure; the result rules of D51 (all primaries done, a primary failed, the player destroyed, `m.end`); sim time only; console `mission` provider, `mission skip`, `mission goto <step>`, `mission objectives`, `play <id>`; a skip leaves the world as the step would (a test compares a skipped and an unskipped run's spawns and objectives) | A | |
| AC6 | Dialog: lines and speakers as data with a voice id; every line id used by a script exists (test); subtitles and the comms panel show in cockpit and chase views; `radio_open`/`radio_close` frame each line | A | |
| AC7 | Comms menu: D-pad Right opens it; the four directions give the four wing orders through `WingDirector`; B or 4 s closes it; while open, the D-pad's flight actions and the target button do not fire; a profile saved before M5 loads with `comms_menu` filled in | A | |
| AC8 | `CINEMATIC`: shots from data relative to actors or the origin, unit-tested interpolation; a rebase during a shot moves nothing on screen (test); HUD hidden, letterbox, the player's commands zeroed while the ship keeps its physics; A or Start skips | A | |
| AC9 | Debrief: result and reason, objectives, time, kills and assists, wing losses, shots and hits; retry restarts the same scenario and seed; menu returns to the front end | A | |
| AC10 | Buoy defence: starts from the menu with its cinematic intro, runs to success and to failure (buoy destroyed; player destroyed) in headless tests driven by console commands, and ends in the debrief; it is set on a ring of 16 buoys, 20 000 km in radius, that broadcast to 10 000 km, with at least two buoys in broadcast range anywhere on or near the ring (Q21, test) | A | |
| AC11 | Civilian references: each of the nine ships described (the Saturn 4 tanker from the Saturn parts, Q16; the Bokmai, Q17) in `docs/design-references.md` with the lengths from Q8, Q11, Q16 and Q17, from orthographic views and cross-sections of its STL; every ship's colour scheme written from online images (Q11) with the sources listed; nothing from the STL files or the images is in git | A | |
| AC12 | Civilian generators: nine hulls from five generators meet the output contract (LOD0-3 PLYs and lighting records, fallback mesh, hardpoints with pods, RCS, collision, cockpit camera, chase anchor, running lights, chunks; the Bokmai's pod model and `cargo_pods[]`); Python tests for budgets, frames, symmetry where the design has it, chunk partition, collision coverage and determinism; every PLY imports in Godot with the manifest's count | A | |
| AC13 | Civilian ships in the game: each flies through `FlightModel` with zero damping (the damping guard covers it), turns by torque only, flees raiders on the `civilian` profile, takes hull damage, breaks into its chunks, shows running lights and switches LOD; a Bokmai flies with 0-3 cargo pods and sheds them when destroyed; raiders attack them through faction data; on the maintainer's GPU all nine in view at once run with `splat_backend = compute`, FPS and VRAM recorded by the agent | A | |
| AC14 | Encounters: `EncounterPlan` is deterministic per seed (test); raids, patrols and traffic spawn 6-12 km out from pools and are released past 30 km; raiders sent at a civilian attack it and allies engage them; `encounter_max_ships` holds; encounters off leaves free flight empty; `encounters` provider and an `encounter <kind>` command to force one | A | |
| AC15 | Sounds: generator tests pin the new guns' shape (length, flat hold, constant pitch, energy band after the 0.25 register, inharmonic partials), the impact's length and band, and the engine bursts' band (no energy to speak of below 300 Hz); voices sit at the nozzles; the voice cap holds and the per-frame update is linear in voices (work count); the old loops are gone | A | |
| AC16 | Cost: M5 adds nothing measurable to AC13 of M3 (the paired 13-ship AI budget still passes, `test_ai_think_time`); the mission runner with 20 triggers and the encounter director stay inside their work counts | A | |
| AC17 | Docs and the suite: `docs/architecture.md` §18 as built, a `docs/playtest.md` M5 section (how to start, menus, mission, comms menu, encounters, new settings and commands), the roadmap row; `scripts/run_tests.sh` green **once, at the end** (Q10), read from the suite's own totals | A | |
| AC19 | Defensive turrets (D61): `TurretAim` and `ThreatMemory` unit-tested; civilians fire only at attackers of themselves or of a civilian or ally within 2 km; they keep running while firing; turret bolts go through the projectile pool and `HitResolver`; the seeded balance fight holds (two raiders beat a lone Saturn 4 in at least two of three seeds; its turrets finish a 15 % raider that keeps attacking); `turret_fire` sound | A | |
| AC20 | Fidelity (Q18): every civilian model's top, side and front silhouettes overlap its STL's by at least 90 % (intersection over union) and its length, width and height are within 10 %, Q16's deliberate departures scored part by part against the model each part was built from; measured on the model's geometry (its fallback mesh) by `tools/refview` compare, with the LOD0 splats scoring at least 0.85 against their own mesh, and unit tests that pin the tool's calibration; each model's scores recorded in `docs/assets-civilian.md` | A | |
| AC18 | (H) The maintainer plays it: menus feel right on the pad, the mission's pacing and lines, the cinematic, the civilian ships' look, the new guns, impacts and engines by ear | H | |

## Working rules for M5

- **Tracks.** The maintainer allowed parallel agents for M5 (Q10), so four tracks can run at the same time: A (flow and front end), B (missions), C (civilian ships and
  encounters), D (sound). Inside a track the order holds. Track C's reference and generator tasks (T11-T15) are Python and run beside
  anything; the Godot tasks of every track share one machine, so they follow the locks below. If work has to go one task at
  a time, the order is T01, T02, T05, T06, T08, T09, T07, T10, T03, T04, T11, T23, T12-T15, T22, T21, T16, T17, T18, T19, T20.
- **One working copy.** All M5 work happens in the `m5` worktree (`.claude/worktrees/m5`) on branch `m5`; no task
  branches, no worktrees per agent (the maintainer's rule from M4). Parallel agents keep to their task's files.
- **Locks.** Every Godot run in the `m5` worktree goes through `flock /tmp/m5-godot.lock <command>` (one Godot process at a
  time on the shared `.godot/` import cache). Every `git add` + `git commit` goes through `flock /tmp/m5-git.lock`, and an
  agent stages only the paths it changed (never `git add -A`). GPU checks take `flock /tmp/gpu.lock` as well. M4's
  benchmark runs take `/tmp/m5-godot.lock` too (2026-11-02, from the M4 session), so a Godot run may wait up to about 10
  minutes; never kill or bypass the lock. Other CPU-heavy work (asset builds, STL renders, long Python runs) takes the same
  lock so M4's numbers stay clean.
- **Tests (Q10).** Each task runs the Python tests and GUT scripts for what it touched and the new tests it adds, never the
  whole suite. GUT by file: `.tools/godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/<dir>/<file>.gd -gexit`.
  Read GUT's own totals (Passing, Failing, Pending). The full suite runs in T20.
- **Test first** for the pure classes (`GameFlow`, triggers, `ObjectiveBook`, `DialogQueue`, `CommsMenu`, `CinematicShot`,
  `DebriefModel`, `EncounterPlan`): the failing test is written before the code.
- After each task: the task's row in the table says `done` with its Done notes, in the same commit; then `git push origin
  m5` (Q6).
- **Console commands in `info.md`** (`CLAUDE.md`, maintainer, 2026-11-03): every console command is listed in `info.md` at
  the repository root with its arguments and a one-line purpose. A task that adds, renames or removes a command updates
  `info.md` in the same commit; T24 writes the list and a test that fails when a registered command is missing from it.
- Assets: `assets/generated/` in the worktree is a copy of the main checkout's; a task that changes a generator rebuilds
  only its asset (`python3 -m tools.procgen build <id>`). New Python tests run with the project's `.venv` Python.

## Task breakdown (ordered)

Status: `done` (merged into `m5`, its Done notes written), `in progress`, `not started`, `not needed` (a conditional task
whose trigger never arose). Update the column with each task's commit.

| Task | Track | Title | Depends on | Agent | Why | Status |
|---|---|---|---|---|---|---|
| T01 | A | `Game` flow, boot routing and loading | - | Opus | Changes how every run starts; must not break a single script or test | done |
| T02 | A | Menu kit, front end and pause menu | T01 | Sonnet | Godot UI work on a clear spec | done |
| T03 | A | Settings menu and audio buses | T02 | Sonnet | Schema-driven screen | not started |
| T04 | A | Controls menu | T02 | Sonnet | Wraps the existing profile API | not started |
| T05 | B | Mission core: runner, script API, triggers, objectives, console | T01 | Opus | The framework M8 stands on; coroutine skipping is subtle | done |
| T24 | A | Console command list in `info.md` and its guard test (`CLAUDE.md` rule of 2026-11-03; numbered last because it was added during the build) | T01, T02, T05 | Sonnet | A doc and one test | not started |
| T06 | B | Dialog, subtitles and the comms panel | T05 | Sonnet | Data and HUD | not started |
| T07 | B | Comms menu on D-pad Right | T06 | Sonnet | Input routing with clear rules | not started |
| T08 | B | `CINEMATIC` camera and locked controls | T05 | Opus | Rebase-safe camera paths | not started |
| T09 | B | Debrief | T05, T02 | Sonnet | Model and screen | not started |
| T10 | B | Mission: Buoy defence with a cinematic intro | T06, T07, T08, T09 | Opus | Pacing, writing and the first real use of the API | not started |
| T11 | C | Civilian references: measurements and descriptions | - | Opus | Reading shapes off renders; sizes from Q8 | done |
| T23 | C | Fidelity check: silhouettes and size against the STL, `refview` compare (Q18; numbered last because it was added during the build) | T11 | Sonnet | A small measuring tool that every civilian generator must pass | not started |
| T12 | C | `saturn_family` generator (five variants, Q16) | T11, T23 | Opus | Large shared part library | in progress |
| T13 | C | `skylark_transport` generator | T11, T23 | Opus | Geometry | not started |
| T14 | C | `narn_transport` generator and the `narn` style | T11, T23 | Opus | Geometry and a new style | in progress |
| T15 | C | `centauri_brezebel` generator and the `centauri` style | T11, T23 | Opus | Geometry and a new style | not started |
| T22 | C | Brakiri Bokmai: references, generator with removable pods, the `brakiri` style (placed here in the order; numbered last because it was added during the build, Q17) | T11, T23 | Opus | A new reference read end to end, modular cargo, a new style | not started |
| T21 | C | Defensive turrets (placed here in the order; numbered last because it was added after the others had numbers) | T12, T13, T14, T15, T22, T19 | Opus | A new gunner seam with a balance test | not started |
| T16 | C | Civilian ships in the game | T12, T13, T14, T15, T22, T21 | Opus | Specs for heavy hulls, factions, pools, AI, GPU check | not started |
| T17 | C | Free-flight encounters | T16, T02 | Opus | Seeded director under a CPU cap | not started |
| T18 | D | New guns and impacts | - | Opus | Synthesis to measured shapes | done |
| T19 | D | Per-thruster engine bursts | T18 | Opus | Voice placement and a voice budget | done |
| T20 | - | Integration, full suite, docs and acceptance | all | controller | One full run, the GPU check, the (H) list | not started |

### M5-T01 `Game` flow, boot routing and loading

- **Goal:** AC1 and the loading half of AC2 (D50).
- **Files:** `src/game/game_flow.gd` (pure), `src/autoload/game.gd` (autoload, registered in `project.godot` after
  `ControlProfiles`), `src/frontend/boot.tscn|.gd`, `src/frontend/loading_screen.tscn|.gd`, `src/frontend/front_end.tscn`
  (a placeholder screen with Free flight and Quit; T02 builds the real one), `project.godot` (`run/main_scene`, the
  autoload), `src/autoload/settings_schema.gd` (`skip_front_end`), `tests/unit/test_game_flow.gd`,
  `tests/integration/test_boot_routing.gd`, `scripts/run_tests.sh` (a windowless check that `--scenario=free_flight` still
  reaches `Main`).
- **Notes:** the routing reads `OS.get_cmdline_args()` and `OS.get_cmdline_user_args()` once; keep the rules in a pure
  function so a test covers every case. `DebugConsole`'s startup queue must still run one physics frame after `Main` is
  ready (§6.4). Start §18 in `docs/architecture.md` with D50 as built.
- **Done when:** AC1; a normal launch shows the placeholder front end and Free flight reaches `Main` through the loading
  screen; every `scripts/*.sh` smoke line and `test_main_scene` pass unchanged.
- **Done (as built, 2026-11-02):** `run/main_scene` is `src/frontend/boot.tscn`.
  - **Routing.** `Boot` hands the command line to the new `Game` autoload (after ControlProfiles). The pure `GameFlow.boot_route` sends `--headless`, `--console-exec`/`--console-file` with a script, `--scenario=<id>` (which sets `settings.scenario` for the session) and `settings.skip_front_end` (new, false) straight to Main, which reads `Settings.scenario` as before. Other launches go to a placeholder front end (Free flight, Quit). `Game` swaps the scene itself in a deferred call, so `DebugConsole`'s startup queue still runs after `Main._ready`: a script's first statement finds Main's providers with no `wait`.
  - **Flow.** `GameFlow` holds `FRONT_END`/`LOADING`/`IN_SPACE`/`DEBRIEF` (a run starts at the front end; refused moves change nothing and say why), the request `{kind, scenario_id, encounters, seed}` and the last result.
  - **Loading.** The loading screen compiles `main.tscn`'s scripts on the main thread, then loads the scene with `load_threaded_request` (compiled on the worker, their preloads leaked 8-10 objects at exit in Godot 4.7.2). `Game` builds Main with the request's `scenario_path` and `scenario_seed`.
  - **Console.** `menu`, `play <scenario_id> [seed]` (any `data/scenarios/*.json`, encounters off) and provider `game` (`state`, `request`, `last_result`).
  - **Tests.** `tests/unit/test_game_flow.gd` (21) and `tests/integration/test_boot_routing.gd` (11). `run_tests.sh` gains four M5 smoke runs at the end, and `game` in its two `providers:` lines.
  - **GPU.** On the maintainer's GPU a windowed launch shows the front end, and Free flight reaches Main through the loading screen (`splat_backend = compute`, 60 fps).
  - **Docs.** Architecture §18 starts with D50.
  - **Left for later.** `scenario` reloads do not update `game.request` (T17). Pool-overrun-as-error is left to T05/T17. No M4 file or `main.gd` was touched.
  - Review: approved, no Critical or Important findings. Carried: the abandoned threaded load and null checks to T02, the
    pool-overrun error (D50) to T05.

### M5-T02 Menu kit, front end and pause menu

- **Goal:** AC2 (D57).
- **Files:** `src/frontend/theme.tres`, `src/frontend/menu_screen.gd` (a base for focusable screens: back on B or Esc,
  first focus, UI sounds), `src/frontend/menu_frame.tscn|.gd` (Q15's three panels), `src/frontend/pad_diagram.gd` (the
  pad drawn in code, its legend from a bindings source; a pure `PadLegend` model with a unit test), `src/frontend/front_end.tscn|.gd` (the sky backdrop with a slow drift and the main menu),
  `mission_select`, `free_flight_select`, `sandbox_select` screens, `src/hud/pause_menu.tscn|.gd`, `src/game/main.gd` (create
  the pause menu; `pause` opens it), `tools/procgen/assets/sfx_ui.py` (move, accept, back; T06 adds the radio sounds) and its
  test, `tests/integration/test_front_end.gd`, `tests/integration/test_pause_menu.gd`.
- **Notes:** the menus are UI, not gameplay, so they may use Godot's `ui_*` input; confirm the pad's D-pad, A and B are in
  the default `ui_*` maps and add them in `project.godot` if not. Missions are listed from scenarios with a `mission` block,
  read through `ScenarioLoader` (no hard-coded list). The Settings and Controls entries open placeholders until T03 and T04.
- **Done when:** AC2 apart from Settings and Controls content.
- **Done (as built, 2026-11-02):** `MenuFrame` is the one three-panel layout of Q15 (`src/frontend/menu_frame.tscn`): options top left,
  a code-drawn XInput pad with a legend read from the live control profile bottom left (`PadLegend`, `PadDiagram`; it redraws on
  `ControlProfiles.applied` and on a `bindings_source` refresh, so a rebind shows at once), objectives or briefing on the right
  (`ObjectivesModel`; `objectives_source`, `request_source`). It holds a stack of `MenuScreen` pages; `Game` hosts are the front end
  (sky with a slow sway, its own `AudioDirector`; Missions from `MissionCatalog`, Free flight with encounters on by default in
  `Game`'s request only, Sandbox with the three scenarios, Settings and Controls as placeholders from `MenuScreens`, Quit) and the
  pause menu (`src/hud/pause_menu.tscn`: Resume, Restart via the new `Game.restart()`, Settings, Controls, Quit to menu; the world
  pauses, `Main` hands it the `pause` edge and its `objectives()`). Godot 4.7's defaults lack pad A and B on `ui_accept` and
  `ui_cancel`, so `project.godot` adds them; profiles never touch `ui_*`. Esc is `pause` and `ui_cancel` at once, so pause pages
  ignore the key and the edge does one step. `sfx_ui` (`ui_move`, `ui_accept`, `ui_back`) plays through `AudioDirector.play_ui`,
  whose UI voices always process. T01's review items are closed (collect on leaving mid-load, null checks, two 18.3 notes). Tests:
  `test_pad_legend`, `test_pad_diagram`, `test_objectives_model`, `test_mission_catalog`, `test_menu_frame`, `test_front_end` (pad-only
  navigation with injected `ui_*` events), `test_pause_menu`, `test_loading_screen`, `test_sfx_ui`. Not built: focus wrap at the ends
  of a list; `Settings.encounters` (T17); real Settings and Controls pages (T03, T04).
  - **Review.** Approved after one fix round (sonnet): while the pause menu is open the pad belongs to it
    (`InputAdapter.sample_menu` reads only the pause edge, re-seeds every other button and drains the mouse and wheel), so
    Back, Y, D-pad left and X no longer act on the game behind it and nothing fires on Resume; the loading screen carries
    the Theme and collects a failed load; Back plays its sound only when a page pops; a broken mission file warns; a page
    with no focus takes it back on the next D-pad or A press. Open for later: the console's `pause off` with the menu open
    lets the ship coast uncommanded (debug only); keyboard debug keys are dead while the menu is open (the console still
    works).

### M5-T03 Settings menu and audio buses

- **Goal:** AC3 (D57).
- **Files:** `src/autoload/settings_schema.gd` (`category` on every entry, `menu: false` on debug ones), `src/frontend/
  settings_screen.tscn|.gd`, `default_bus_layout.tres` (`Master`, `SFX`, `UI`, `Comms`), `src/audio/audio_director.gd` (UI
  and comms players on their buses; volumes from settings), `tests/unit/test_settings_schema.gd` (every entry has a known
  category), `tests/integration/test_settings_screen.gd`.
- **Done when:** AC3; the pause menu and the front end both open it.

### M5-T04 Controls menu

- **Goal:** AC4 (D57).
- **Files:** `src/frontend/controls_screen.tscn|.gd`, `src/autoload/control_profiles.gd` (only if a call the screen needs is
  missing; keep `ui_*` actions out of `apply`), `tests/integration/test_controls_screen.gd`.
- **Notes:** while waiting for a press to bind, the screen must not let that press also act on the menu. A refusal from
  `bind` shows its errors.
- **Done when:** AC4.

### M5-T05 Mission core

- **Goal:** AC5 (D51, D52).
- **Files:** `src/mission/` (new): `jump_arrival.gd` (Q12; its `jump_in` sound in a new `tools/procgen/assets/sfx_world.py`,
  so it does not collide with T02's `sfx_ui` or T18's `sfx_combat`), `mission_script.gd`, `mission_api.gd`, `mission_runner.gd` (node, priority after the
  resolvers), `mission_world.gd`, `trigger.gd` and one file per trigger kind, `trigger_spec.gd`, `objective_book.gd`,
  `mission_console.gd`; `src/game/scenario_loader.gd` (the `mission` block, `objectives`, `cinematics` passed through);
  `src/game/main.gd` (create the runner when the scenario has a mission; no respawn in a mission); `src/hud/` (an
  objectives list in both views); a test mission `tests/fixtures/missions/test_mission.json|.gd`;
  `tests/unit/test_triggers.gd`, `test_objective_book.gd`, `tests/integration/test_mission_runner.gd`,
  `test_mission_skip.gd`.
- **Notes:** `say` and `cinematic` are stubs that resolve at once until T06 and T08. The input-performed trigger reads the
  tick's `PilotCommand` edges that `Main` already samples, never `Input`. Measure the per-tick cost as a work count.
- **Done when:** AC5 with the stubbed `say` and `cinematic`.
- **Done (as built, 2026-11-02):** `src/mission/`: pure `MissionWorld` (actors by name as `UniversePos`, sim time, lines, the
  tick's `PlayerActions` from `InputAdapter.last`; every lookup counted), seven `Trigger` kinds each with `test` and `force`,
  `TriggerSpec` (JSON and script builders), `ObjectiveBook` (hidden/active/done/failed, fail first, `snapshot()`),
  `MissionScript`, `MissionSequencer` and `MissionApi`; `MissionRunner` (under Main, priority 400, pausable), `MissionStage`
  (name map kept by `ShipPool.acquired`, pools, `AiContext.objective_name`), `MissionConsole`, `JumpArrival` +
  `JumpArrivalPool` (4 mesh points under `World/Effects`, light, `jump_in` from the new `sfx_world`).
  - **Skip.** Waits resume on the sequencer's `wake` (once per tick after the world moved); `mission skip` emits it at once with
    the step marked skipped, so awaited triggers are made true (destroyed: released, no explosion or credit; proximity, area,
    arrived: placed, velocity kept; the rest latch), objectives are evaluated, and the step finishes inside the command;
    `mission goto <step>` skips up to the named step. A skipped and a played run of the test mission leave the same journal,
    objectives and ships in play.
  - **Result.** Every primary done or `m.end(true)`: success; a failed primary, `m.end(false)` or the player destroyed: failure;
    `Game.end_mission` keeps it (`DEBRIEF`), Main stays in space with the result on the status line. No respawn in a mission.
    A spawn past its pool is a `push_error` (`ShipPool` unchanged).
  - **Wiring.** `ScenarioLoader` passes `mission` and `cinematics` through and exposes `parse_spawn`; Main creates the runner,
    ignores Back in a mission and offers `objectives()` for the pause menu; the HUD lists active objectives top right in both
    views. `say` and `cinematic` resolve at once (T06, T08 seams); `lock_controls` keeps a flag for T08.
  - **Console.** Provider `mission`; `mission [status|skip|goto <step>|objectives|journal]` while a mission runs.
  - **Tests.** `test_triggers` (29), `test_objective_book` (17), `test_mission_sequencer` (17), `test_mission_runner` (15), `test_mission_skip` (5); 5 loader and 3 HUD-layout tests added; `tools/procgen/tests/test_sfx_world.py` (8). The test mission is `tests/fixtures/missions/test_mission.json|.gd`.
  - **Cost.** counted, not timed: 20 live triggers cost 49 units of work in a tick (a check and at most two lookups each, plus one refresh per watched name), the same with 4 or 502 actors; the live runner with 37 triggers, 95.
  - **Docs.** Architecture §18: D51, D52, layout, console, §18.5 as built.
  - **Review.** Approved after two fix rounds (opus): a `destroyed` trigger counts a name only once the game has had that
    ship (placed at load, handed out by a pool, or spawned by the script), so objectives declared before their ships
    spawn hold, and a ship lost before any trigger watched it still counts; a polling loop under `mission skip` trips a
    guard; a forced release leaves the wing first; `respawn` is refused in a mission; `play <mission>` gives the request
    kind `mission`; `Game.end_mission` goes through `GameFlow.keep_result`. Final counts: triggers 32, objective book 18,
    sequencer 19, runner 18, skip 7, game_flow 23, boot routing 11. Names are the identity: a replenished wingman reuses
    its slot's callsign, so arm wingman triggers while the wingman is in play (§18.5).

### M5-T24 Console command list in `info.md`

- **Goal:** the `CLAUDE.md` rule (maintainer, 2026-11-03): keep a list of all console commands in an `info.md` document.
- **Files:** `info.md` (new, repository root), `tests/integration/test_console_command_list.gd` (new).
- **What:** `info.md` lists every console command registered anywhere in the game, M1 to M5: name, arguments, a one-line
  purpose, the subsystem that registers it, and whether it exists only in some runs (a mission, the front end, a
  benchmark). A second table lists the state providers (`state <name>`). Group by subsystem; keep it plain.
- **Test:** boot `main.tscn` (and the contexts that register extra commands: a mission fixture, the front end) and
  read `ConsoleRegistry.command_names()`; every registered command must appear in `info.md`, and every command in
  `info.md` must exist in at least one context. A task that adds a command without listing it fails this test.
- **Done when:** `info.md` is complete for the commands on `m5` at the time, and the test passes.

### M5-T06 Dialog, subtitles and the comms panel

- **Goal:** AC6 (D53).
- **Files:** `src/mission/dialog_queue.gd`, `src/mission/dialog_book.gd` (loads and validates the files),
  `data/dialog/speakers.json`, `src/hud/comms_panel.gd` (both views), `tools/procgen/assets/sfx_ui.py` (`radio_open`,
  `radio_close`), `src/mission/mission_api.gd` (`say` for real), `tests/unit/test_dialog_queue.gd`,
  `tests/unit/test_dialog_book.gd`, `tests/integration/test_comms_panel.gd`.
- **Done when:** AC6.

### M5-T07 Comms menu on D-pad Right

- **Goal:** AC7 (D54).
- **Files:** `project.godot` (`comms_menu`), `data/controls/m1_classic.cfg` (the built-in must stay complete),
  `src/input/input_adapter.gd`, `src/input/ui_command.gd`, `src/hud/comms_menu.gd` (model and view), `src/game/main.gd`
  (wire it to `WingDirector`), `tests/unit/test_comms_menu.gd`, `tests/integration/test_comms_menu_input.gd`.
- **Notes:** add the key binding to the keyboard layout and `docs/architecture.md` §6.1's diagram. A test loads a profile
  file written before the action existed.
- **Done when:** AC7.

### M5-T08 `CINEMATIC` camera and locked controls

- **Goal:** AC8 (D55).
- **Files:** `src/camera/cinematic_shot.gd` (pure), `src/camera/camera_rig.gd` (the mode, the camera, `mode_name` no longer
  binary), `src/hud/letterbox.gd`, `src/game/main.gd` (the command zeroing), `src/mission/mission_api.gd` (`cinematic`,
  `lock_controls`), `src/autoload/settings_schema.gd` (`camera_default` keeps chase and cockpit only),
  `tests/unit/test_cinematic_shot.gd`, `tests/integration/test_cinematic_camera.gd` (with a forced rebase mid-shot).
- **Done when:** AC8.

### M5-T09 Debrief

- **Goal:** AC9 (D56).
- **Files:** `src/mission/debrief_model.gd` (pure), `src/frontend/debrief_screen.tscn|.gd`, `src/autoload/game.gd` (the
  `DEBRIEF` state and retry), a shots-and-hits counter for the player (from `projectile_fired` and `HitResolver`'s
  results, without touching M4's files), `tests/unit/test_debrief_model.gd`, `tests/integration/test_debrief.gd`.
- **Done when:** AC9 with the test mission.

### M5-T10 Mission: Buoy defence with a cinematic intro

- **Goal:** AC10 and the mission half of AC18.
- **Files:** `data/scenarios/buoy_defence.json`, `data/missions/buoy_defence.gd`, `data/dialog/buoy_defence.json`,
  `tests/integration/test_buoy_defence.gd`, `docs/playtest.md` (how to play it).
- **Sketch** (the agent writes the lines; all text original): open in `CINEMATIC` on the relay buoy `NAV ALPHA` with the
  sun behind it, then Alpha wing in finger-four passing the camera with the player as lead. Babylon 5 Control briefs
  over comms: raiders have been seen heading for the relay. Controls hand over. Wave one (three raiders) is sent at the
  buoy from beyond sensor range (`m.send`); a second group (four) comes from another bearing after a comms warning.
  Objectives: protect `NAV ALPHA` (primary, fails if it is destroyed), destroy the raiders (primary), bring Alpha wing
  home (optional). Success and failure lines, then the debrief. Pools sized for every ship the script spawns.
- **The buoy ring (Q21):** the scenario places 16 nav buoys evenly on a ring of 20 000 km radius (about 7 850 km apart)
  in one plane, as if round a planet; `NAV ALPHA` is one of them, and the mission plays out beside it. The ring's
  positions come from a small pure helper (centre, radius, count, plane -> `UniversePos` per buoy, names), not from
  hand-typed coordinates. `NavBuoy.BROADCAST_RANGE_M` becomes 10 000 km (1.0e7 m) for every buoy in the game, so a
  ship anywhere on the ring or within about 6 000 km of it always has at least two buoys in broadcast range: on the
  radar's rim and targetable (M3-T17), and heard by the AI. A unit test samples points on and around the ring and
  checks the two-buoy rule; `test_broadcast.gd`'s 1 000 km assert moves to 10 000 km, and §18 records the change
  against M3's Q21. Far buoys are thousands of km away: they stay in the tree (D22) but must cost no splat sorting or
  drawing while out of sight (hide the splat node beyond a few tens of km, show it again inside; visibility only, no
  nodes added or removed). Their contacts in `ContactScan`'s broadcast list are one entry each, so 16 buoys add
  nothing measurable to M4's scan.
- **Done when:** AC10; the cinematic and dialog read well in a windowed run (captured frames for the maintainer); the
  ring and the two-buoy rule hold (test), and the radar shows the two nearest ring buoys on its rim from `NAV ALPHA`.

### M5-T11 Civilian references: measurements and descriptions

- **Goal:** AC11 (D59).
- **Files:** `tools/refview/` (new; a Python script with the project's `.venv`: orthographic views, silhouettes and
  cross-sections of an STL into `reports/refs/<name>/`; it reads the untracked `references/` and writes nothing to git),
  `docs/design-references.md` (one section per ship), `docs/assets-civilian.md` (new: the parts each generator needs,
  budgets, hardpoints, chunk groups, styles).
- **References:** `references/EA_Saturn_3_Freighter.stl`, `EA_Saturn_4_transport.stl`, `EA_Saturn_8_transport.stl`,
  `EA_Saturn_Fuel_tanker.stl`, `Narn_Transport.stl`, `EA_Skylark_transport.stl`, `Centauri_Brezebel_Transport.stl` (ASCII;
  the others are binary). `EA_cargo_pod.stl` may help with the Saturn transport pods.
- **Notes:** the STLs are at 3D-print scale and each file has its own scale, so every measurement is relative and scaled to
  the ship's length (Q8, Q11, Q16): the Saturns are modular, one lead ship (control section) the same size on every
  variant plus cargo; a Saturn 4 cargo section (pods or tanks) is 100 m, a Saturn 8 carries two of them (200 m of cargo),
  the Saturn 4 tanker is half a Saturn 8 tanker, and the Saturn 3 carries three of the same pods behind the same lead
  ship; Narn transport about 70 m; Skylark about 60 m; Brezebel about 60 m. The longest axis of a file is not always its
  length; read the nose and the engines from the views.
- **Colours (Q11):** for each ship, find online images (search the ship's name; fan wiki pages and screen captures), save
  them under `reports/refs/<ship>/web/` (each download in its own new directory, never opened by an interpreter), list the
  source URLs in the description, and write the scheme as colours and where they go. Pick values that read like the
  images; no image pixels go into the generators.
- **Turrets (Q14):** note where each reference shows turret-like mounts or where 2-4 turrets would cover the hull's
  quarters, for D61's `turrets[]`.
- **Done when:** AC11; each description names its parts, their proportions, its length, its colour scheme and its
  turret positions.
- **Done (as built, 2026-11-02):** `tools/refview/refview.py` (venv, run with `-I`) renders any reference STL in the
  ship frame at a given length into the gitignored `reports/refs/<ship>/`: eight shaded views and silhouettes with a
  metre grid and scale bar, 24 to 32 cross-sections, centre-plane cuts, a table of the model's separate shells with
  boxes in metres, and `measurements.json`; `--zrange` renders a slice larger. It reads binary and ASCII STL (binary
  told by size, and a `solid` header with trailing bytes still reads as binary), fails with the file's name when no
  triangles come out, and exits 2 with a message on a bad file or mapping. 12 unit tests in
  `tools/procgen/tests/test_refview.py`, one a whole `main()` run on a synthetic STL, skipped without Pillow
  (`docs/third-party.md` lists refview under Pillow). `docs/design-references.md` gains "Civilian ships (M5)" for eight
  hulls. The Saturn family is the wiki's "Achilles" type freighter, modular per Q16: one lead ship (dish antenna, 28.3 m
  command disc, 6.3 m truss with a three-drum frame, 22.6 m engine section with a 6.3 m bell) the same on every variant,
  plus 100 m cargo sections (four 31.1 x 17.3 x 43.0 m pods on arms round a 17.5 x 75.5 m cylinder, or three such
  cylinders as tanks), at 0.09746 m per unit of the Saturn 4 model. Lengths follow from the parts: Saturn 4 transport and
  Saturn 4 tanker 158.5 m, Saturn 8 transport and Saturn 8 tanker 258.5 m (the Saturn 8 tanker was
  `saturn_fuel_tanker`), Saturn 3 119.5 m with three pods turned crosswise and the shared engine section behind them,
  which its model lacks. Every Saturn variant has its z stations, pods, arms and turrets tabulated. Skylark 60 m (the
  wiki's "Delta Gamma 9" type), Narn transport 70 m (flat crescent 46 m across; the file's longest axis is its length,
  not its span as the brief expected), Centauri Brezebel 60 m (the purple Centauri liner). Every ship has its colour
  scheme in sRGB from wiki screen captures with the URLs listed, and 2 to 4 turret positions.
  `docs/assets-civilian.md` plans T12 to T15: output contract, LOD0 budgets of 810 000 for all eight (1.84 M with the
  hero, the sky and five buoys, 92 % of `splat_budget`), hardpoints with their exact JSON fields per hull and per Saturn
  variant, chunk groups, parts mapped to `core/geometry.py` and `parts/`, styles `ea_civilian`, `narn` and `centauri`,
  turret models. No STL data or image is in git.
  - Review: approved after two fix rounds (Q16's modular Saturns arrived after the first review; one Saturn 3 pod
    figure corrected). Open for the maintainer (H): the Saturn 3's added engine section and raised pod stack, soft Saturn
    close-ups at about 0.52 m LOD0 spacing, which way is up on the Narn transport.

### M5-T23 Fidelity check: `refview` compare

- **Goal:** AC20's tool (Q18). In the order it comes after T11 and before T12; the generator tasks need it to finish.
- **Files:** `tools/refview/` (a compare mode beside the render), `tools/procgen/tests/test_refview_compare.py`,
  `docs/assets-civilian.md` (a "Fidelity" section: how to run it, the thresholds, a score table the generator tasks fill
  in), `docs/design-references.md` only for the line that names the commands.
- **What it does:** reads an STL with the same axis mapping and length as refview's render, so the model sits in the
  authored frame (x to starboard, y up, z aft from the nose), and a built asset from `assets/generated/<id>/` (the LOD0
  PLY, with `manifest.centroid_offset` undone; each splat drawn as a disc of its own scale). It draws the top, side and
  front silhouettes of both on one grid (a pixel at most 0.5 % of the length), allows a small best-fit shift (at most
  2 % of the length, reported), and scores each view's intersection over union and the length, width and height
  ratios. Crops by z range, set separately for the model and the asset, score one part at a time. It writes overlays
  (model only, asset only, both in three colours) and `fidelity.json` to `reports/refs/<ship>/compare/`, prints a
  one-line verdict per view, and exits non-zero when a view is under 0.90 or a dimension is off by more than 10 %.
  Optional extra parts (the Bokmai's pods at their `cargo_pods[]` mounts) are drawn with the hull.
- **Tests:** synthetic STLs and splat sets: identical shapes score 1.0; a known shift, scale or missing part gives the
  known overlap; crops; the exit code at the thresholds; skipped without Pillow, like `test_refview.py`.
- **Done when:** the tests pass and the tool has been run on every civilian asset already built, with the scores in
  the report (a generator under the bar is that generator's fix, not this task's).

### M5-T12 `saturn_family` generator

- **Goal:** AC12 for the five Saturn hulls (Q16).
- **Files:** `tools/procgen/assets/saturn_family.py`, shared parts in `tools/procgen/parts/` (command sphere, truss spine,
  engine section, cargo module, tank), `tools/procgen/styles/ea_civilian.py`, `tools/procgen/tests/test_saturn_family.py`.
- **Turrets (D61):** each variant's `hardpoints.json` carries `turrets[]` (2-4 by size) and the `ea_civilian` style a
  small turret model (base, dome, twin barrel) written like a chunk (PLY, lighting record, fallback mesh). T13-T15 and T22 do
  the same for their hulls and styles.
- **Notes:** one generator, a variant per asset id, so `python3 -m tools.procgen build saturn_4_transport` builds one hull.
  The variant data holds the length (Q8) and the module layout.
- **Done when:** AC12 and AC20 for the five variants; `tests/integration/test_splat_import.gd` covers them.

### M5-T13 `skylark_transport` generator

- **Goal:** AC12 for the Skylark.
- **Files:** `tools/procgen/assets/skylark_transport.py`, parts it needs, `tools/procgen/tests/test_skylark_transport.py`.
- **Done when:** AC12 and AC20 for the Skylark.

### M5-T14 `narn_transport` generator and the `narn` style

- **Goal:** AC12 for the Narn transport.
- **Files:** `tools/procgen/assets/narn_transport.py`, `tools/procgen/styles/narn.py`, parts it needs,
  `tools/procgen/tests/test_narn_transport.py`.
- **Done when:** AC12 and AC20 for the Narn transport.

### M5-T15 `centauri_brezebel` generator and the `centauri` style

- **Goal:** AC12 for the Brezebel.
- **Files:** `tools/procgen/assets/centauri_brezebel.py`, `tools/procgen/styles/centauri.py`, parts it needs,
  `tools/procgen/tests/test_centauri_brezebel.py`.
- **Done when:** AC12 and AC20 for the Brezebel.

### M5-T22 Brakiri Bokmai: references, generator and the `brakiri` style

- **Goal:** AC11 and AC12 for the Bokmai (Q17, D59). In the order it comes after T15 and before T21.
- **Files:** `docs/design-references.md` (a Bokmai section under "Civilian ships (M5)"), `docs/assets-civilian.md` (its
  parts, budget, hardpoints with `cargo_pods[]`, chunks, turrets and the `brakiri` style, then the as-built numbers),
  `tools/procgen/assets/brakiri_bokmai.py`, `tools/procgen/styles/brakiri.py`, parts it needs,
  `tools/procgen/tests/test_brakiri_bokmai.py`, its lines in `tests/integration/test_splat_import.gd`.
- **Reference:** `references/Brakiri_Bokmai_transport_80m.STL` (binary, 16 998 triangles, about 522 x 1320 x 510
  units; the 1320-unit y axis is its length, about 0.0606 m per unit at 80 m). Measure it with `tools/refview` as T11
  measured the others: views, sections, the shells table (the pods should come out as their own shells), z stations and
  proportions. Read the nose and the engines from the views.
- **Colours (Q11, Q17):** Brakiri green and yellow. Find online images of the Bokmai (other Brakiri ships help if the
  Bokmai has few), save them under `reports/refs/brakiri_bokmai/web/` as T11 did, list the URLs, and write which parts
  are green and which yellow, with the panel, window and engine glow colours.
- **Pods (Q17):** one pod model for the three mounts if the pods match (a variant per mount if they do not). The hull's
  LOD0 budget counts the hull plus three pods, about 75 000 for an 80 m ship, so all nine hulls at LOD0 with the hero,
  the sky and five buoys stay under `splat_budget`; write the new total into `docs/assets-civilian.md`. The hull's
  chunks leave the pods out (each pod is its own debris piece).
- **Turrets (D61, Q19):** dorsal mounts on the frame and a `brakiri` turret model. Propose the spots on the model's views
  and send them, with the colour scheme, to the controller, who confirms both with the maintainer before the generator
  commits them.
- **Done when:** AC11, AC12 and AC20 for the Bokmai; Python tests also cover the pod model (budget, determinism), that the
  hull alone has no splats inside the pod volumes (an empty mount looks empty) and that the pods sit at their
  `cargo_pods[]` mounts; every PLY, the pod's included, imports in Godot with the manifest's count.

### M5-T21 Defensive turrets

- **Goal:** AC19 (D61, Q14). In the order it comes after T22 and before T16.
- **Files:** `src/combat/turret_aim.gd` (pure), `src/combat/threat_memory.gd` (pure), `src/combat/turret_mount.gd` (node),
  `src/game/ship_assembly.gd` (build mounts from `turrets[]`), the `Hardpoints` parser (`turrets[]`, optional),
  `tools/procgen/assets/sfx_combat.py` (`turret_fire`; after T19, which also edits that file), a turret `WeaponSpec`,
  `tests/unit/test_turret_aim.gd`, `test_threat_memory.gd`, `tests/integration/test_turret_defence.gd` (the balance fight).
- **Notes:** the generators of T12-T15 and T22 emit `turrets[]` and the turret model; if one of them landed without them, add
  them here. `HitResolver` is read through its existing results signal; do not change M4's files. Civilians are the only
  ships with turrets in M5.
- **Done when:** AC19.

### M5-T16 Civilian ships in the game

- **Goal:** AC13 (D58 factions, D59).
- **Files:** `data/factions.json` (`civilian`, `narn`, `centauri`, `brakiri`, the relations), `src/game/ship_catalog.gd`
  (nine types),
  `assets/specs/` or wherever `ShipSpec` resources live (one per hull: mass, thrust, inertia, limits), the pools and
  `LodSwitcher` entries, running lights, `DestructionDirector` chunk sets, `data/scenarios/civilian_showcase.json` (all nine
  parked in view, a Bokmai with three pods and one with none, for the GPU check and the maintainer), `tests/integration/test_civilian_ships.gd`.
- **Notes:** check that `PilotSteering` and avoidance cope with a 200 m hull that turns slowly (radius from the collision
  shapes); if a fix is needed in the AI, keep it outside M4's files or list it. GPU check per `CLAUDE.md`: windowed run of
  `civilian_showcase`, `state render`, VRAM from `/sys/class/drm/card1/device/mem_info_vram_used`.
- **Bokmai pods (Q17, D59):** `ShipAssembly` builds a pod at each `cargo_pods[]` mount up to the spawn's `cargo_pods`
  count (0-3, default 3), pooled with the ship (D22); a pod adds its mass and collision shape and switches LOD with the
  hull; when the ship breaks up its pods drift off as debris. A test spawns Bokmais with 3 and 0 pods and checks mass,
  collision and the pods' debris.
- **Done when:** AC13.

### M5-T17 Free-flight encounters

- **Goal:** AC14 (D58).
- **Files:** `src/encounters/encounter_plan.gd` (pure), `src/encounters/encounter_director.gd`, `src/encounters/
  encounter_console.gd`, `data/scenarios/free_flight.json` (pools for encounters), `src/autoload/settings_schema.gd`
  (`encounters`, `encounter_interval_s`, `encounter_max_ships`), `src/game/main.gd` (create the director in free flight when
  encounters are on), `tests/unit/test_encounter_plan.gd`, `tests/integration/test_encounters.gd`.
- **Notes:** the pools add load time to free flight; record it. Run M3's `test_ai_think_time` before and after.
- **Done when:** AC14 and AC16's encounter clause.

### M5-T18 New guns and impacts

- **Goal:** the gun and impact half of AC15 (D60).
- **Files:** `tools/procgen/assets/sfx_combat.py` (bump `GENERATOR_VERSION`), `tools/procgen/core/audio.py` (FM and
  hold-and-cut helpers if needed), `tools/procgen/tests/test_sfx_combat.py`, `src/audio/audio_director.gd` (only if a level
  or pitch needs to change).
- **Done when:** the tests pin the shapes; the agent writes the measured numbers of the new sounds next to the reference's
  in its Done notes for the maintainer's ear test.
- **Done (as built, 2026-11-02):** `sfx_combat` v4 replaces the three sounds; `explosion` is untouched.
  - `pulse_fire` (105 ms): a band-passed noise click, then a two-frequency FM cluster held flat for 100 ms and cut in
    5 ms. The carrier is 2a + b, modulated by a (index 0.8) and b (0.9), with our own a = 2.10 kHz and b = 0.66 kHz near
    the reference's 2.06 / 0.67 kHz. The six reference partial positions are all in it.
  - `raider_fire` (150 ms): the same build, lower (a = 1.16, b = 0.43 kHz) and buzzier (indices 1.4 / 1.6,
    tanh-clipped), held 120 ms, with an exponential cut (tau 6 ms).
  - `hit_hull` (140 ms): FM at 1 : 1.414 whose index dies (tau 20 ms) faster than its level (tau 28 ms), plus a click.
  - All three are designed at reference-like frequencies, then ×`GUN_PITCH` 0.25 with lengths unchanged.
  - `core/audio` gains `fm`, `hold_and_cut` and `hold_and_release`.
  - **Measured, reference / new after ×0.25:**
    - Starfury: main tone 1.198 / 1.215 kHz; hold 95-105 / 99 ms (flat within 0.23 dB); attack under 10 ms / 2 ms
      with a click (+32 dB above 3.5 kHz over the hold); pitch within 2.5 / 0.02 Hz; energy 4-6.5 kHz band ->
      1000-1625 Hz 73.6 % (625-1000 Hz 11.7 %, 1625-2500 Hz 11.8 %, below 250 Hz 0.3 %); inharmonicity 0.026 / 0.075.
    - Raider: median 689 Hz against 1214 Hz; 18 partials within 10 dB against 5; cut 20 ms to -30 dB against 4 ms;
      below 150 Hz 0.7 %; inharmonicity 0.272.
    - Hit: 30 dB down in 96 ms; 250 Hz-4 kHz 93.2 %; median 1516 Hz.
  - `AudioDirector.SHOT_DB` plays the shots at -12 / -13 dB (was -3). The flat tones carry +9.3 / +9.9 dB more
    K-weighted energy per shot than the old decays. The hit stays at -4 dB.
  - Tests: `test_sfx_combat.py` (23, including `GunAndImpactShapeTests`), `test_audio.py` (25), `test_audio_director.gd`
    (17/17, with the shot gain) and `test_splat_import.gd` (15/15).
  - The ear test (character, level, the ±4 % shot pitch jitter) is (H).
  - Review: approved, no Critical or Important findings (minor test tightening deferred).

### M5-T19 Per-thruster engine bursts

- **Goal:** the engine half of AC15 (D60).
- **Files:** `tools/procgen/assets/sfx_combat.py` (`main_burst`, `rcs_burst`; drop `engine_loop`, `thruster_loop`),
  `src/audio/engine_voices.gd` (new: voice placement, envelopes, the cap), `src/audio/audio_director.gd`,
  `src/autoload/settings_schema.gd` (`engine_voice_cap`), `tests/unit/test_engine_voices.gd`,
  `tests/integration/test_engine_audio.gd`.
- **Notes:** envelopes run on sim time in `_process` (visuals and audio in `_process`, physics in `_physics_process`). The
  RCS grouping comes from `ThrusterLayout`'s positions, so the civilian hulls get it for free.
- **Done when:** the engine half of AC15 and AC16's cost clause for audio.
- **Done (as built, 2026-11-02):**
  - **The old loops are gone.** `engine_loop` and `thruster_loop` are removed (Q7). `sfx_combat` (generator 5) now has two seamless loops shaped on the reference:
    - `main_burst` (4 s): noise from 400 Hz to 16 kHz with its loudest octave at 4-8 kHz (36.6 % of the energy), a -5.6 dB/oct tilt above 1 kHz and a slow 3.1 dB wander at 0.5-1.75 Hz.
    - `rcs_burst` (2 s): noise from 2 to 16 kHz, 79 % of it at 6-16 kHz.
    - Neither has energy to speak of below 300 Hz (6.8e-6 and 4e-11). A new `audio.shaped_periodic_noise` helper builds both.
  - **`EngineVoices`** (`src/audio/engine_voices.gd`) is the pure decision side:
    - **Voices:** one per pod for every ship, heard at the pod's main or retro nozzle, whichever fires harder. The player's ship also gets one per RCS cluster. Jets are grouped by their side of the centre of mass along each axis, with a 20 % centre-line band: the Starfury gets 4 clusters and the raider 4, and any hull gets at most 27.
    - **Cap:** `engine_voice_cap` (default 24, min 8) bounds the grants: the player's 8 first, then whole ships, nearest first, within 1.5 km. Ships are re-ranked at 4 Hz, on a cap change, or when a voiced ship leaves play.
    - **Envelopes** run on the frame's delta with the reference's numbers: pod attack 20 ms, pod release 30 dB in 40 ms, jet attack 59 ms, jet release tau 0.15-0.65 s by burn length. A jet's brightness follows its level (an octave of `pitch_scale`).
  - **`AudioDirector`** puts `EnginePod<i>`/`EngineRcs<j>` players on each ship at those places. Each frame it touches only granted voices: work counts show `step_work` equals the granted voices (24) for 300 ships of 16 pods and 64 jets, and a re-rank is one unit per ship. Gains are `POD_DB` -9 and `RCS_DB` -10, so four pods sit at about the loudness of a held shot.
  - **Console:** `audio.engine_voices`, `engine_sounding` and `engine_frame_work` are new.
  - **README:** the procgen README now lists the eight current sounds.
  - **Tests:** `tests/unit/test_engine_voices.gd` (21), `tests/integration/test_engine_audio.gd` (9), and the burst shape tests in `test_sfx_combat.py`.
  - **Not done:** the reference's optional comb sweep and 150 ms soft stop.
  - **(H):** levels and feel.
  - Review: approved, no Critical or Important findings. Carried to T16/T17: engine voices for ships without a
    `PulseCannon` and a removal path for despawned traffic.

### M5-T20 Integration, full suite, docs and acceptance

- **Goal:** AC16, AC17 and the (H) checklist for AC18.
- **Steps:** finish §18 in `docs/architecture.md` as built; write the M5 section of `docs/playtest.md` with the (H)
  checklist; update the roadmap row; run `scripts/run_tests.sh` once and read GUT's and Python's own totals; run the GPU
  check on the maintainer's machine; then ask the maintainer to confirm the milestone. Before `m5` is merged it is rebased
  onto `main` (with M4 in it); the agent asks before force-pushing.
- **Done when:** the maintainer confirms M5.
