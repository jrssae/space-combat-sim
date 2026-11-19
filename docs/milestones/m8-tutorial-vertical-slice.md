# Milestone 8: Tutorial vertical slice

> "The first mission." (`docs/roadmap.md`)

**Status:** **in progress** (started 2026-11-18 with T07). Branch `m8` was cut from `main` at `1e7064dc` (M7's merge) on 2026-11-18. The planning
questions below were asked on 2026-11-18; the maintainer answered Q5 to Q8 the same day, and the proposed answers to the others
stand until the maintainer answers. The tutorial's script is
not planned here: its beats, lines and pacing are settled with the maintainer in T01, and T03 to T05 are filled in from it.

The roadmap was renumbered on 2026-11-18 (`docs/roadmap.md`, "After the tutorial"): the capital-ship milestone planned as M12
(its branch is now `m10`) is **M10**. T07 merged it into `m8` and renamed its plan `docs/milestones/m10-factions-and-capital-ships.md`,
so its tasks are called by their new ids here (M10-T19, M10-T20, M10-T49; planned as M12-T19, M12-T20, M12-T49, the ids
its commit subjects keep).

Read `docs/architecture.md` first, especially §14.6 (launch bays and the mission framework), §16 (the instructor as an
`AiPilot`, D37), §18 (M5: missions, `MissionApi`, dialog, the front end, the `CINEMATIC` camera) and M7's §20 (the station,
Cobra-bay launches §20.2, the defense grid §20.3, traffic and the main docking bay's `DockingPlan` §20.4, the hold-X
interaction §20.5, the hangar §20.8, the exterior tour §20.10, known gaps §20.14). Also `docs/roadmap.md` ("Carried from M7"
and L15 in "Carried from M4's full review"), `docs/milestones/m10-factions-and-capital-ships.md` (T19, the raider
strike carrier, and T20, the Battle Wagon, which moves here) and `docs/design-references.md` ("Raider strike carrier", "Raider Battle
Wagon"). Tasks are ordered inside each track; each is one PR-sized unit and names a recommended agent model.

## Goal

Make the first mission. The player starts in the hangar behind the menu, watches their squadron launch from the Cobra bays,
launches, and is taught every control by a subtitled instructor. The instructor tours the station and its defense grid, then
raiders come through the jumpgate and the player defends Babylon 5 with the station's allies, ending in a debrief. A damaged
ship can dock in the main docking bay to be repaired and launched again. The raiders get their capital ships: M10's strike
carrier (T19) comes into M8 and carries the civilian escort's raids, and the Raider Battle Wagon moves here from M10. M7's
carried clean-ups land, and the game ships as a Linux x86_64 release build.

## Planning questions (asked 2026-11-18)

| Q | Question | Proposed answer (planner's default, until the maintainer answers) | Answer |
|---|---|---|---|
| Q1 | The tutorial's script | **Settled in T01** with the maintainer: the beats in the roadmap's order (hangar, squadron launch, own launch, control checks, exterior tour, raid through the jumpgate, defense with allies, debrief), each check's line and pass condition, and the pacing | Maintainer, 2026-11-18: settled in T01 (D79) |
| Q2 | Which controls the instructor checks | The roadmap's list: main pods, retros, strafe (each axis), roll, pitch and yaw, flight assist on and off, the brake, targeting (next, nearest, the radial menu), fire modes (guns linked and alternate, missiles); each check passes on the same `InputMap` actions M1 reads, shown with the pad and keyboard bindings (keyboard parity: every pad action has a keyboard equivalent) | Maintainer, 2026-11-18: the proposed list, plus camera and lights, the X button's tap and hold, wing orders, the buoy course and the jumpgate (D79) |
| Q3 | Can the player fail or skip a check? | A check never fails: the instructor repeats the hint after a pause and demonstrates the move (D37's manoeuvres); the whole training part can be skipped from the pause menu straight to the tour | Maintainer, 2026-11-18: the proposed answer |
| Q4 | The squadron-launch cinematic | As the roadmap says (maintainer, 2026-11-13): the Cobra bay's sawtooth doors open (T02), Starfuries drop out one after another, flip, light their engines and form up, with exterior shots; skippable; it ends with the player's own launch from M7-T08's sequence | Maintainer, 2026-11-18: the proposed answer |
| Q5 | How does the M10 strike carrier come into M8? | Merge `origin/m10` into `m8` in T07, reconciling M10's collision builder with the one M7 built, then mark M10-T19 done once the maintainer flies it in M8's play-test | Maintainer, 2026-11-18: the proposed answer |
| Q6 | The strike carrier in the civilian escort | Each wave's raiders arrive docked on the carrier and launch once it is clear of its point (Q29's data option); the carrier hangs back at stand-off, recalls survivors and jumps out when hurt or when its wave is down; destroying it is an optional objective | Maintainer, 2026-11-18: the proposed answer, for the first two waves; the last wave comes with the Battle Wagon (Q8) |
| Q7 | Docking for repair and relaunch | The player holds X at the main docking bay's mouth (the `dock` interaction that answers "not available" today); `DockingPlan` flies the ship in through the inner doors; a timed repair restores the hull and reloads guns and missiles; the ship then launches from a Cobra bay through M7-T08's launch sequence. A wingman docks on a wing order, or by itself below a hull threshold, and rejoins after its relaunch | Maintainer, 2026-11-18: the proposed answer |
| Q8 | The Battle Wagon in M8 | Moved from M10-T20 with its rules (Q31 there: from images, with weapons settled with the maintainer before work starts, four launch tubes). It appears in free-flight raids and a sandbox scenario; the tutorial's raiders come through the jumpgate vortex as the roadmap says | Maintainer, 2026-11-18: **also in the civilian escort: its last wave comes with the Battle Wagon**, launched from its tubes, instead of the strike carrier |
| Q9 | Release build | Linux x86_64 only, from the pinned 4.7.2 export templates (verified by SHA-256 like the editor), the native library and the generated assets packed; a script builds it, and the bench writes to `user://` in an exported build (L15) | Maintainer, 2026-11-18: the proposed answer; Windows follows in M9 |

## Scope

In:
- **The tutorial mission** (`tutorial`, from New game and offered first on a new profile): the hangar, the squadron launch, the
  control checks, the exterior tour, the raid, the defense and the debrief (Q1 to Q4).
- **Docking for repair and relaunch** in the main docking bay, for the player and the AI wingmen (Q7).
- **The raider capitals:** M10-T19's strike carrier merged into `m8` (Q5), the civilian escort's raids carried by it (Q6), and the
  Raider Battle Wagon moved from M10-T20 (Q8).
- **Carried from M7:** M7-2 the interceptor muzzle, M7-3 the cargo bay's flicker, M7-4 sawtooth Cobra doors, M7-5 the audio rework,
  M7-6 wingmen close formation gaps after losses.
- **Carried from M4:** L15, the bench's `res://reports` in an exported build.
- **The release build** for Linux x86_64 (Q9); the Windows build is M9, right after this milestone.

Out:
- Voiced dialog (M33; subtitles and the comms panel stay).
- Every other capital ship and the M10 framework (sections, beams, the staged break-up): M10 as planned.
- Landing in a Cobra bay (the bays stay launch-only; docking goes through the main docking bay).
- Story missions beyond the tutorial and the escort (M12 onward, one milestone per mission).

## Design (to go into `docs/architecture.md` §21)

### D79 The tutorial mission (T01, settled with the maintainer 2026-11-18)

A `MissionScript` (`data/missions/tutorial.gd`) with `data/scenarios/tutorial.json` and `data/dialog/tutorial.json`, on M5's
`MissionApi` and M7's station seams.

- **Voices.** An original Earth Alliance flight instructor (name and callsign proposed in T05's dialog, the maintainer may rename)
  flies a Starfury beside the player as D37's `AiPilot` with the `instructor` profile; **Babylon Control** is the station's tower
  voice for the launch, the tour's grid, the raid alarms and docking.
- **The story.** The player is a pilot newly transferred to Babylon 5 from another vessel, flying a qualification check to become
  the squadron's leader. The mission list's description, the briefing and the instructor present it as exactly that: training to
  qualify (the controls, the course, the tour, the gate). **The raid surprises everyone**, the instructor and Control included:
  nothing before the alarm hints at it, and the debrief is the first time it is discussed as a whole.
- **Beats, in order.**
  1. Hangar: New game, Tutorial; the briefing over the hangar backdrop.
  2. The squadron-launch cinematic (D81), then the player's own launch; skippable.
  3. Form up on the instructor and fly to a training box about 8 km off the station, away from traffic.
  4. Flight checks: main pods, retros, pitch and yaw, roll, strafe on all four axes, flight assist off (a drift demo) and on, the
     brake.
  5. Camera and lights: the cockpit and chase views, free look, running lights.
  6. **The X button**: tap is auto-track; hold runs the selected target's interaction (the gate's jump, a bay's docking, later
     cargo and more), offered only within its reach, with the prompt naming the live binding; the instructor says X will do more
     as the player meets new places.
  7. Navigation: target a nav buoy from the radial menu, auto-track it, fly a timed buoy course braking on the approach cue (T18).
     **The career remark comes here, in flight, from the course** (the instructor, as the course ends): an exemplary time, the best
     ("keep this up and one day you might be flying a White Star"); par, a plain word of encouragement; below par, a teasing remark;
     a nav buoy destroyed, the worst (something about being lucky to end up piloting a rusty cargo ship). Par and exemplary times are
     data.
  8. Combat: target the nearest enemy and the next one (the pad's B tap, the keyboard's target-next) and pick from the radial
     target menu (B held); target-previous and target-ahead are not taught (maintainer, 2026-11-18: keyboard and mouse only, and
     target-ahead has no default binding); shoot unarmed training drones with the lead reticle, switch fire modes.
  9. Wing orders: form, attack and cover from the comms menu.
  10. The exterior tour: the Cobra bays, the main docking bay, the command section, the defense grid (heavy cannons, interceptors),
      the jumpgate.
  11. **Jumpgate use**: at the gate the player targets it, closes on the approach cue and holds X; the jump and its cinematic run
      (the round trip of M6 until hyperspace exists) and the player comes back out through the blue vortex.
  12. The raid: a first group of raiders through the jumpgate vortex, then **the raider strike carrier** jumps in on its own point
      and launches more (M12-T19, via T07); alarms, more wings launch, the grid engages, the player defends with the wing (orders
      in use). **The rest of the wing launches when the raiders begin firing** on Babylon 5 or on any ship in the area. **The
      player commands only a flight of three** (the player and two Starfuries); the other Starfuries fly in flights of three that
      cover each other and stay together, under their own AI (T19).
      **Traffic is in the way:** cargo and passenger ships wait in a line for the cargo bay and in a separate line for the main
      docking bay, and more fly to and from the jumpgate (M7's traffic and `DockingPlan` lanes); the raiders attack them too.
      **The carrier can be destroyed, but only in a window**: a capital ship's jump drive needs time to recharge after a
      jump before it can open another point (per class, data), and the raider carrier, a pirate ship, has one of the longest.
      Once recharged it jumps out on its own point. It can also run for the jumpgate earlier, which works whatever its drive's
      state, if it decides to run soon enough and the player breaks off the attack. The recharge and the choice to run for the gate
      are built for every carrier in T08.
  13. Docking for repair: when the player is damaged, Control offers the main docking bay (T06); the player docks, is repaired
      and relaunched from a Cobra bay, and rejoins.
  14. The debrief: the raid is discussed here for the first time. **No Starfury lost is a perfect score**, even if the raider
      carrier got away; destroying the carrier is credited but not needed for it. **The qualification:** an exemplary time on the
      buoy course, **no more than one Starfury lost and no civilian ship lost** makes the player squadron leader at once; anything
      less assigns the player to the squadron, to be promoted to leader in a later mission. The rank is saved with the profile
      (`Career`, pure, with its save beside the settings; survives restarts; a `career` console command reads and sets it), and the
      roadmap notes that a later mission promotes a pilot who missed it.
- **Dying in the second half.** If the player dies after the raiders arrive, the debrief offers **restart from the raid's start**
  (a checkpoint taken as the alarm sounds: the course result and the career remark kept, the station, traffic, wing and player
  restored to that moment from the scenario's seed) or **restart the whole mission**. Dying before the raid offers only the full
  restart. These are added to the debrief's existing options (quit to the main menu, quit to the desktop and the rest stay).
  Built on M5's debrief and retry (a retry flies the same seed); tested both ways.
- **Checks never fail** (Q3): a missed check repeats its hint after a pause, then the instructor demonstrates it (D37's manoeuvres).
  The training block (beats 4 to 9) can be skipped from the pause menu straight to the tour.
- Each check shows the action's live pad and keyboard bindings and follows a rebind (D80).

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

The strike carrier as M10-T19 built it (`docs/architecture.md` §19.18): `CarrierJumps` brings it for raider raids, with
fighters docked or beside by data. The escort's first two waves set `docked` (Q6); its last wave comes with the Battle Wagon (Q8). The Battle Wagon follows M10's Q31 rules and its four
tubes launch Delta-Vs; when M10's framework lands (sections, turrets, beams), both hulls move onto it like every other.

- **Jump-drive recharge** (maintainer, 2026-11-18): after a jump a capital ship's drive needs time before it can open another point,
  per class in data; the raider carrier, a pirate ship, has one of the longest. The jumpgate is always usable whatever the drive's
  state.
- **The raider carrier's retreat rules** (maintainer, 2026-11-18; numbers in data, for every raider carrier): raiders go home to
  dock on the carrier when only 3 of the raid are left, or one by one when a raider's hull is below 20 %; the carrier flees when it
  has taken at least 50 % damage or when every surviving raider has docked. Fleeing is a jump on its own point once the drive has
  recharged, otherwise a run for the jumpgate (it may run early if the player breaks off); raiders not docked in time are left
  behind (M10's Q30). These set the thresholds M10-T19 built (its Q27, Q30).
- **The Battle Wagon's weapons** (maintainer, 2026-11-18, M10's Q31): raider plasma turrets and missile racks.

### D84 Approach cues and a speed-scaled gate reach

Today a navigation target that offers an interaction (the jumpgate, the docking and cargo bays) shows only its distance and the
`CLOSE TO 2.0 km` status line, so nothing tells the player when to brake, slow down or turn before they overshoot (maintainer,
2026-11-18).

- **The cue.** A pure `ApproachCue` reads the ship's position and velocity relative to the selected target (against the target's
  own velocity: the gate's and the bays' rest velocity), the target's reach and the ship's braking (the retros' deceleration at its
  mass, as the brake uses it) and answers: the closing speed, the time to reach, the stopping distance, the closest approach on the
  present course, and one state: **ON COURSE**, **BRAKE** (the stopping distance has reached the distance left to the reach, with a
  margin), **OVERSHOOT** (it can no longer stop inside the reach) or **ADJUST COURSE** (the closest approach misses the reach or the
  bay's lane). The HUD draws it on the navigation target's box and the status line (a closing-speed readout and a bar with the brake
  point marked), in both views, from the live bindings' names as the prompt does. HUD-only GDScript: one target a frame.
- **The gate's reach follows the ship's speed.** `GateJumpRequest.range_m` takes the closing speed: the base 2 km, plus the distance
  flown during the 2 s hold, plus what the autopilot needs to slow from that speed to its run-in, capped by data
  (`data/jump/gate_request.json`). A ship closing fast is offered the jump farther out, so the request still lands in time.
- **The autopilot and the cinematic take the ship as it comes.** `GateAutopilot` starts from the ship's velocity at the hold: it
  brakes to the 250 m/s run-in on the way to the line-up point, or, when the ship is already lined up with the mouth, carries its
  speed down to the run-in without the detour; the `CinematicShot` is timed from the predicted arrival at the mouth instead of fixed
  offsets, so the shot frames the run-in at any approach speed. A ship that passes the gate while the hold runs is turned round as
  M7-T28 already does.
- **The bays** keep their 2 km reach; T06's docking autopilot slows the ship from whatever speed it has when docking starts.

### D85 Flights of three, staying together, and two hold-fire orders (T19; maintainer 2026-11-18)

- **The player's flight.** In the tutorial (and any mission whose data says so) the player commands a flight of three: the player
  and two Starfuries. The wing orders go to those two only. The rest of the launched wing flies under its own AI.
- **AI flights of three.** Starfuries not under the player's command fly in flights of three with a lead: they cover each other
  (a member under attack draws its flight-mates onto the attacker) and **stay together** (cohesion: a member that strays past a
  distance rejoins before picking a new target; the flight engages as a group, not as three lone fighters). Native, in the brains'
  job, 1 and 6 threads identical, parity recordings kept or re-recorded with the reason.
- **Formation fires.** In formation (form on me, and the flights' own formations) every ship may fire at a target in its guns'
  reach and cone while keeping its slot; check today's behaviour and fix any rule that keeps followers from firing.
- **Two new orders** on the comms menu (page one grows past four entries, §18.22 allows eight) and on the keyboard (keyboard
  parity: free keys, tap as the other orders), through `WingDirector.give_order` and `AiContext.Order`:
  - **Form up, hold fire:** the flight takes its formation slots on the player and does not fire.
  - **Hold position, hold fire:** the flight holds where it is (station-keeping against the reference) and does not fire, so the
    player goes solo.
  Any other order lifts the hold. The `wing order` console command takes both. Acknowledgement lines in the dialog.

### D86 GPU memory on the debug overlay (T20; maintainer 2026-11-18)
- The debug overlay (`debug_toggle_overlay`) shows the GPU memory in use in GB and as a percentage of the card's total, e.g.
  `VRAM 2.41 / 16.00 GB (15 %)`, refreshed about twice a second (not every frame).
- **Card-wide use and total** come from the driver: on Linux the DRM sysfs files (`/sys/class/drm/card*/device/mem_info_vram_used`
  and `mem_info_vram_total` on AMD; the card that Godot's `RenderingServer.get_video_adapter_name()` names, or the first with the
  files). Godot's own allocation (`RENDER_VIDEO_MEM_USED`, today's `render.vram_mb`) is shown beside it as the game's share.
- Where the driver gives no total (another vendor, no sysfs; Windows in M9 adds its own source), the line shows the game's share
  in GB and `total unknown` instead of a percentage. A pure `VramReading` parses the files and formats the line (unit tests with
  fake files); the read stays off the per-frame path.
- `state render` gains `vram_used_gb`, `vram_total_gb`, `vram_pct`; `info.md`, and `docs/playtest.md`'s overlay notes.

### D87 The game's fonts (T21; maintainer, 2026-11-18)

- Two freeware fonts the maintainer supplied (in `references/`, to be committed under `assets/fonts/` as third-party data and recorded
  in `docs/third-party.md` with their source and the maintainer's word that they are freeware; the files carry no licence text and
  the source page, fonts2u.com, refuses automated fetches): **Babylon5** (`B5______.ttf`, "Fantazia Fonts and Sounds") for every
  title and headline, and **Babylon5Credits** (`Bac_____.ttf`, 1994) for larger blocks of text (mission briefings, debriefs, dialog,
  menus' body text) **and the whole HUD**.
- **All UI text uses one of the two**: the project's default theme font becomes Babylon5Credits, a `Title`/`Headline` theme type
  variation uses Babylon5, and every label, button, `draw_string` and `RichTextLabel` (front end, pause, settings, controls,
  briefing, debrief, comms, subtitles, HUD, overlay, console excepted if it needs a fixed width; say so) reads them from the theme or
  one small `GameFonts` helper. A test walks `src/` and the scenes for any other font in use.
- Both files use a symbol-encoded cmap (glyphs at U+F020-F0FF); the task checks Godot draws ASCII with them (HarfBuzz's symbol
  mapping) and fixes the files' cmap at import time if not, and checks every character the UI prints is covered (digits, `%`, `/`,
  `°`, the key and button names). A look sheet of the front end, a briefing, a debrief and the HUD in both views goes to the
  maintainer before the commit (readability at HUD sizes is (H)).

### D88 Gamepad detection (T22; maintainer, 2026-11-18)

- The maintainer's pad sometimes is not seen by Godot while Steam sees it. Found 2026-11-18 with it plugged in and unseen: USB
  `3537:2106` "HID zk" (a Zikway controller chip), bound only as a raw `hidraw` node (root-only) with **no evdev/joystick device**,
  so nothing that reads input events (Godot's joypad layer) can see it; Steam reads it through its own HID access and, through
  Steam Input, gives games it launches a virtual Xbox pad. Likely the pad comes up in a vendor or console mode some of the time.
- The task diagnoses it on this machine (which mode, what changes when it is seen: the USB id, the driver, Steam running or not),
  and then: logs every joypad at start and on hotplug (name, GUID, known mapping), shows a short toast when a pad connects or
  disconnects and a front-end notice when none is found, adds a `joypads` console command (list, mapping, last events), and writes
  a troubleshooting section in `docs/playtest.md` (the pad's mode switch, launching through Steam as a non-Steam game, a udev rule
  if hidraw access helps SDL). Any game-side fix must keep gameplay reading `InputAdapter`, never `Input`.

### D89 The civilian escort in its own star system (T23; maintainer, 2026-11-18)

- The escort leaves Epsilon Eridani: **no Babylon 5** (so no station, no home dock: the wingmen stay and fight, D82), **no nebula**,
  and a **different nearby planet in colour and look**, in **a different star system** — a new entry in `data/star_systems.json`
  (its own star, the planet on its rail, no gate needed yet; M27's system generator and jumpgate travel come later and will take this
  system over). Its sky, sun colour and planet are data and generated assets; the escort's scenario names the new `system_id` and
  anchors on that system's places. A look sheet of the new sky and planet goes to the maintainer before the commit.
- Everything the escort reads from Epsilon (the anchor, the sun, broadcasts, encounters, the HUD's reference) works from the new
  system; free flight and the station scenarios keep Epsilon.

### D90 Radial menus fit their entries (T24; maintainer, 2026-11-18)

- Every radial menu (the comms menu, the target menu and any page pushed onto them, §18.19, §18.22) lays out **one slice per entry
  present**: 3 entries are 120° each, 5 are 72° each; **no empty slices** are drawn or pickable. The first entry stays at the top and
  the rest follow clockwise in page order.
- Picking follows the layout: the stick's angle picks the nearest slice of the current layout; the D-pad's four directions and the
  keyboard's numbered keys pick by entry order (an entry beyond the fourth is reached by the stick or the keys); entries that are
  unavailable (M8-T06's DOCK with no home dock in range) are left out rather than blanked. Console picks by index follow page order.

## Acceptance criteria

| # | Criterion | Kind | Done |
|---|---|---|---|
| AC1 | Tutorial script: T01's beats and checks written into D79 (the lines go into the dialog file in T05), approved by the maintainer | A | **Met** (T01, 2026-11-18) |
| AC2 | Squadron launch: the cinematic plays from the hangar, the squadron launches and forms up, skipping lands in the same state (test on the end state), the player's launch hands over as M7-T08 does | A | |
| AC3 | Control checks: each check passes on its actions and state in headless tests driven by injected commands, for pad and keyboard bindings; a rebind changes the hint; a missed check repeats and demonstrates, never fails | A | **Met except the flown demo** (T04, 2026-11-18; the instructor flying it is checked in T05's AC4): the demo is asked for on `MissionApi.demo_requested`; the instructor flying it is T05's |
| AC4 | Tutorial mission: starts from the menu and runs to the debrief in a headless test driven by console commands; the tour visits its points; the raid comes through the jumpgate vortex and the station's allies and grid fight it; losing the player ends in the debrief | A | |
| AC5 | Docking: the player docks through the main docking bay, is repaired (hull, guns, missiles) and relaunched from a Cobra bay (headless test on the state before and after); a wingman docks on order and by threshold and rejoins its wing | A | **Met** (T06, 2026-11-18; no missiles exist yet, so hull, gun charge and reaction mass are what is restored) |
| AC6 | Strike carrier: M10-T19 merged into `m8` with its tests green next to M7's; one collision builder serves the station and the carrier | A | |
| AC7 | Civilian escort: the first two waves arrive docked on the strike carrier and launch; the carrier hangs back, recalls and jumps out; the escort's tests (success, both failures, flee and resume) pass with it | A | |
| AC8 | Battle Wagon: meets the output contract with Python tests (budgets, frames, hardpoints, tubes, determinism), its look sheet seen by the maintainer (no STL: M10's Q10), in the game with its weapons and four launch tubes, in a sandbox scenario and free-flight raids; the civilian escort's last wave launches from its tubes and the escort's tests pass with it | A | **Met** (T09, 2026-11-19; two tubes with four lanes, as the sheet has it: the maintainer, 2026-11-18. How it looks and plays is (H), `docs/playtest.md`) |
| AC9 | Carried items: M7-2 to M7-6 and L15 each done with a test where one can be written | A | |
| AC10 | Release build: a script builds the Linux x86_64 export from the pinned templates; the exported game opens, runs the tutorial's opening and quits cleanly in a smoke test | A | |
| AC11 | Cost: on the maintainer's GPU, the squadron launch, the tour and the raid: `renderer = forward_plus`, FPS, draw calls and VRAM recorded; the tick inside the 60 Hz budget during the raid | A | |
| AC12 | Docs and the suite: `docs/architecture.md` §21 as built, a `docs/playtest.md` M8 section, the roadmap row, `info.md`; `scripts/run_tests.sh` green once, at the end | A | |
| AC13 | (H) The maintainer plays it: the tutorial start to finish, the squadron launch, the approach cues and a fast gate jump, docking and relaunch, the escort with the strike carrier, the Battle Wagon, the audio, the release build | H | |
| AC14 | Approach cues and the gate's reach (D84): `ApproachCue`'s states are unit-tested over approach speeds, offsets and brake strengths; the cue shows on the gate and both bays in both views; the gate offers the jump farther out at speed, and headless jumps requested at 200 m/s to several km/s all run the line-up, the run-in and the cinematic and arrive through the mouth (tests on the end state and the shot's timing) | A | |
| AC15 | Flights and orders (D85): the player commands only a flight of two wingmen where the mission says so; AI flights of three cover each other and stay within their cohesion distance through a seeded headless fight; ships in formation fire at targets in reach; the two hold-fire orders hold formation or position without firing and are lifted by any other order (tests for each, pad menu and keyboard), native kept 1 and 6 threads identical | A | **Met** (T19, 2026-11-18) |
| AC16 | GPU memory (D86): the overlay shows VRAM used in GB and as a percentage of the card on the maintainer's GPU, matching `mem_info_vram_used` within a refresh; `state render` reports the three values; with no driver total it shows the game's share and `total unknown` (unit tests on fake sysfs files) | A | **Met** (T20, 2026-11-18) |
| AC17 | Fonts (D87): both fonts in the repo with their `docs/third-party.md` entry; every UI text uses one of them (a test finds no other font); ASCII and the UI's symbols draw on the GPU; the maintainer approved the look sheet | A | **Met** (T21, 2026-11-19) |
| AC18 | Gamepad detection (D88): the cause written down; joypads logged at start and hotplug, the connect, disconnect and none-found notices, `joypads` in `info.md`; the troubleshooting section; the maintainer's pad seen by the game in its working mode (H) | A | |
| AC19 | Escort's own system (D89): the escort runs in the new star system with no station and no nebula, the new planet and sky approved on a sheet, wingmen with no home dock; its tests pass; Epsilon's scenarios unchanged | A | |
| AC20 | Radial fit (D90): menus with 1 to 8 entries lay out equal slices with no empty ones (unit tests on the layout), the stick, the D-pad, the keys and the console pick the right entry for each count, unavailable entries leave the ring | A | |

## Working rules for M8

- **Tracks.** A (the tutorial: T01 to T05), B (docking and approach: T06, T18), C (the raider capitals: T07 to T09), D (carried clean-ups and smaller features: T10 to
  T14, T19, T20), E (release and close-out: T15 to T17). Inside a track the order holds. If work goes one task at a time, the order is the
  table's.
- **The tutorial's script is the maintainer's call.** T01 is held with the maintainer by the controller; no agent writes beats
  or lines before it. A question about the script that comes up later goes back to the maintainer.
- **The Battle Wagon's weapons are the maintainer's call** (M10's Q31): settled 2026-11-18, plasma turrets and missile racks (D83).
- **Fable where the task warrants it** (maintainer, 2026-11-18): Fable for the hardest work (new hulls from references, native AI,
  the tutorial's integration), Opus and Sonnet for the rest as the Agent column says; Fable-suited tasks are started first while
  its tokens last. High effort, never max.
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
| T01 | A | Tutorial script: beats, lines, checks and pacing (discussion with the maintainer) | Q1 to Q4 | controller | The maintainer's design call, held as a discussion, not delegated | done |
| T02 | A | Sawtooth Cobra-bay doors (roadmap M7-4): toothed leaves that slide apart, the launch's door ripple and timing kept | - | Fable | Generator parts and an animated door the cinematic opens on | done |
| T03 | A | The squadron-launch cinematic (D81) | T02, T01 | Opus | Scripted launches, camera shots and a skip that lands in the same state | not started |
| T04 | A | Control checks: `ControlCheck`, the runner and the binding hints (D80) | T01 | Fable | Pass conditions on measured state for every control, pad and keyboard | done |
| T05 | A | The tutorial mission: launch, checks, tour, raid, defense, debrief (D79) | T03, T04 | Fable | The mission script, dialog and pacing on M5's and M7's seams | not started |
| T06 | B | Dock in the main docking bay to be repaired and relaunched, for the player and the AI wingmen (D82, Q7) | - | Fable | The `dock` interaction, the lane for fighters, repair and a Cobra-bay relaunch; wing orders | in progress |
| T07 | C | Bring M10-T19's raider strike carrier into `m8`: merge `origin/m10`, one collision builder, its tests green (Q5) | - | Opus | Two branches built a collision builder; docs, `native/src/lib.rs` and `info.md` conflict | done |
| T08 | C | The civilian escort's raids come with the strike carrier (D83, Q6) | T07 | Fable | Mission data and pacing on `CarrierJumps`; the escort's tests kept green | done |
| T09 | C | Raider Battle Wagon (moved from M10-T20): from images, with weapons (M10 Q31) and four launch tubes; the escort's last wave comes with it (Q8) | T08, the maintainer on its weapons | Fable | No STL; a new hull with weapons and tube launches | in progress |
| T10 | D | Interceptor muzzle at the drawn barrel tip, and the grid balance measured again (roadmap M7-2) | - | Fable | A placement fix in the turret rows with a balance check | done |
| T11 | D | The walls beside the cargo bay stop flickering (roadmap M7-3) | - | Sonnet | Find the coplanar faces or shading cause in the station generator; a test | not started |
| T12 | D | Audio rework of every sound effect and the Starfury engines' steady level (roadmap M7-5) | - | Opus | One loudness reference, the mix, and a smoothed engine gain; a listening checklist | not started |
| T13 | D | Wingmen close the gaps losses leave in a formation (roadmap M7-6) | - | Fable | Native re-slotting with M7-T76's avoidance, 1 and 6 threads identical | done |
| T14 | D | The bench writes to `user://` in an exported build (roadmap L15) | - | Fable | A path fix with a test | done |
| T15 | E | Linux x86_64 release build from the pinned export templates (Q9) | T14 | Sonnet | Templates by SHA-256, the native library and assets packed, an export smoke test | not started |
| T16 | E | Performance and the GPU check: the squadron launch, the tour and the raid | T05, T09 | Opus | Measurement on the maintainer's machine; the budget call | not started |
| T18 | B | Approach cues for navigation targets with an interaction (brake, overshoot, adjust course), and the jumpgate's reach, autopilot and cinematic scaled to the player's speed (D84; maintainer, 2026-11-18; numbered last because it was added after the others had numbers) | - (shared with T06) | Opus | Relative-motion maths on the HUD, and a gate run-in that starts from any speed with its shot timed to match | not started |
| T19 | D | Flights of three: the player commands two wingmen, AI flights of three cover each other and stay together, every ship in formation may fire, and two new orders (form up and hold fire; hold position and hold fire) (D85; maintainer, 2026-11-18; numbered last because it was added after the others had numbers) | T13 | Fable | Native flight cohesion and mutual cover, two orders through the comms menu and keys, parity | done |
| T20 | D | GPU memory in use on the debug overlay, in GB and as a percentage of the card (D86; maintainer 2026-11-18; numbered last because it was added after the others had numbers) | - | Fable | Driver sysfs reads off the frame path, a fallback, the overlay and `state render` | done |
| T21 | D | The game's fonts: Babylon5 for titles and headlines, Babylon5Credits for body text and the HUD, on all UI text (D87; maintainer, 2026-11-18; numbered last) | - | Fable | A theme over every screen and the HUD's own drawing, a symbol-encoded cmap, a look sheet first | done |
| T22 | D | Gamepad detection: why Godot sometimes misses the maintainer's pad, joypad logging and notices, `joypads`, troubleshooting (D88; maintainer, 2026-11-18; numbered last) | - | Fable | Linux input stack diagnosis on the real device, small notices | in progress |
| T23 | C | The civilian escort in its own star system: no Babylon 5, no nebula, a different planet (D89; maintainer, 2026-11-18; numbered last) | T08 | Opus | A second system in the data, its sky and planet, the escort moved onto it; a sheet first | not started |
| T24 | D | Radial menus fit their entries: equal slices for however many entries, no empty spots (D90; maintainer, 2026-11-18; numbered last) | - | Opus | The radial framework's layout and picking for every input | in progress |
| T17 | - | Integration, full suite, docs and acceptance | all | controller | One full run, the GPU check, the (H) list | not started |

### M8-T01 Tutorial script (discussion with the maintainer)

- **Goal:** AC1 (D79). Held by the controller with the maintainer; not dispatched to an agent.
- **Inputs the controller brings:** the roadmap's beats, Q2's list of checks with each one's action and a proposed pass
  condition, the instructor's manoeuvres (D37), the tour points (M7-T12, T57), the station raid's knobs (M7-T10).
- **Files:** D79 in this file, `data/dialog/tutorial.json` (lines as data with voice ids for M33).
- **Done when:** AC1.
- **Done (2026-11-18):** the script settled with the maintainer and written into D79 (the story, the beats, the course's career
  remark, the surprise raid with the carrier's window, the qualification and career rank, the raid checkpoint), Q1 to Q4 answered.
  The dialog lines themselves are written in T05 from D79.

### M8-T02 Sawtooth Cobra-bay doors

- **Goal:** roadmap M7-4: the launch doors become retracting sawtooth doors (toothed leaves that slide apart) instead of today's
  flat-edged doors that swing open; the launch sequence's door ripple and its timing kept.
- **Files:** the station generator's Cobra-bay door parts and their tests, the door animation in the launch sequence, a look sheet
  for the maintainer before the generator commits (the standing rule: the maintainer sees a sheet first).
- **Done when:** the doors slide apart in a launch (headless test on their state through the sequence); the maintainer has seen
  the sheet (H).
- **Done (2026-11-18):** the maintainer chose option B from the look sheet (`references/screenshots/M8-T02 sawtooth doors/`):
  coarse trapezoid teeth as on the main docking bay's inner doors (three a leaf, 4.4 m pitch, 2.2 m deep, the seam along the arm),
  the leaves sliding apart across the arm and fully back under the deck (11.3 m each; an open door shows no leaf, 2.3 m each side
  of a Starfury), and the hangar refitted to match. Built: `station_props.seam_line` and the toothed `door_leaf` with its repainted
  face (slats, lit edge and hazard band along the teeth); each bay's `leaves` hardpoints now `slide`, `travel_m`, `reach_m` (were a
  hinge point and axis); `StationDoorLeaves` slides the prop instances from the manifest's places (so it works headless);
  `LaunchSequence.door_share` and a `leaf_clearance` for sliding leaves; the profile's `door_open_deg` removed (the travel is the
  station's geometry, a departure from the plan's "travel in the profile", to keep one source), the door's 2 s, 3 s and the
  0.25 to 0.5 s ripple unchanged; `b5_interior`'s leaves on the same seam with a lit gap, slide rails and drives in place of the
  hinge pipes and rams; the sheet tool's `t02` views. The leaves have no collision pieces (they never had). Generator versions:
  station 6, interior 2. Tests from a staged copy with both assets rebuilt: Python 125 passed (`test_station_sealed`,
  `test_coplanar_overlaps`, `test_b5_interior`, `test_station_hardpoints`, `test_station_sections`, `test_babylon5_station`,
  `test_station_fidelity` against the STL); GUT unit 44 passed (`test_launch_sequence` 25, `test_station_hardpoints` 5,
  `test_launch_shot_clearance` 2, `test_launch_cut` 7, `test_hangar_camera` 5) and integration 44 passed (`test_launch_bay` 16
  with the new door test: shut, sliding, open for the ejection, sliding, shut, and the ripple; `test_station_sections` 6,
  `test_bay_lights` 1, `test_hangar_backdrop` 6, `test_station_in_game` 10, `test_interior_ships` 3, `test_station_sheltered` 2);
  923 scripts compile; a live `station_launch` and `launch wing all` run without errors. Final renders:
  `references/screenshots/M8-T02 sawtooth doors/final/`. Open (H): the doors in a launch and the hangar's floor doors
  (`docs/playtest.md`, "Play-testing the sawtooth Cobra-bay doors").

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
- **Done (2026-11-18):** `ControlCheck` (pure): four kinds of pass condition on measured state, `velocity` (speed gained along an
  axis of the ship's own frame on ticks its events were held), `rotation` (degrees turned about pitch, yaw or roll, either way),
  `brake` (held `hold_s` and slowed by `min_drop_mps` or to `stop_mps`) and `state` (conditions `equals`, `at_least`, `set`,
  `changed`, `increased` on `ControlCheckSample`'s fields: assist, camera, look angle, lights, tracking, target, fire mode,
  interactions run, the wing's order and order count, target menus opened), after its command events were seen. Events come
  from the tick's `PilotCommand` (`ControlCheckSample.events_of`: `PlayerActions` plus the flight axes from 0.1 and X's and the
  target button's holds), never `Input`. `ControlCheckRunner` (pure): the hint as a check opens, again after `repeat_s` (20 s),
  the demo after a second miss (the hint a third time for a check without one), then it waits without limit; requests come back
  from `take_requests`. `ControlCheckBook` reads `data/checks/controls.json`: 27 checks covering D79's beats 4 to 9, each with a
  `hint_line` id `check_<id>` for T05's dialog file; demos on roll (`roll`), the four strafes (`strafe_box`) and the brake
  (`all_stop`). `MissionApi`: `await m.check(id)` and `await m.run_checks([ids])`; a hint is said as its dialog line when the
  book has it, a demo is announced on `demo_requested(check_id, demo)`, a skipped step passes its checks at once, and a check
  none of whose actions is bound is left out with a journal note so it cannot hold the mission up. `ControlCheckProbe` measures
  the real ship for `MissionRunner` while a check is open; `ControlHint` (HUD layer, under the status line) shows the label, the
  buttons and a progress bar; `ControlHintText` builds the buttons from the live `InputMap` in the prompt line's naming
  (`LT + RT / W`, `HOLD X / SHIFT / MOUSE 4`, `R STICK / MOUSE`), `BindingNames` now naming triggers and sticks too. Console:
  provider and command `checks [status|list|pass|start|stop] [id]` (`info.md`). `WingDirector.orders_given` counts the orders
  the player's wing took. Tests (staged copy): 57 tests in 7 new GUT files (`test_control_check` 21, `_runner` 6, `_book` 5, `_devices` 5: every check passed through
  the real `GodotInputSource` and `InputAdapter` on the pad's bindings and on the keyboard's and mouse's, `test_control_hint_text`
  8 with a rebind, `test_mission_checks` 7, `test_control_checks_live` 5 in the main scene) and one more in `test_wing_orders`
  (10), 0 failing; `test_keyboard_parity` 4, `test_console_command_list` 7, `test_quick_suite` 3, the mission, HUD and input
  neighbours (14 files) green; compile check 923 scripts clean.
  **Left for T05:** the instructor flying a requested demo (the request and its `Manoeuvres` name are there; no behaviour flies
  a move off a route yet), the dialog lines `check_<id>`, and the pause menu's skip of the training block (`mission goto`).
  **For the maintainer:** the default layout binds nothing to `target_ahead` and only the mouse wheel to `target_prev`, so the
  mission leaves `target_ahead` out and a pilot with only a pad cannot pass `target_prev` (its hint reads `MOUSE WHEEL UP`);
  bind them in the default layout or drop them from the script. The hint's look and place on the HUD are (H): `checks start roll` in any mission shows it.

### M8-T05 The tutorial mission

- **Goal:** AC4 (D79), from T01's script.
- **Files:** `data/missions/tutorial.gd`, `data/scenarios/tutorial.json`, the dialog file from T01, the front end's New game entry,
  `tests/integration/test_tutorial.gd` (menu to debrief, the player lost), `info.md`.
- **Notes (from T04):** the instructor flies the demo T04's runner asks for (`MissionApi.demo_requested`); the `check_<id>`
  dialog lines; the pause menu's skip of the training block; drop the `target_prev` and `target_ahead` checks from
  `data/checks/controls.json` (D79 beat 8); T04's thresholds (main pods 40 m/s, retros 20, strafe 10, pitch and yaw 45°, roll 180°,
  free look 25°, a 20 s repeat) are data, tuned in play.
- **Done when:** AC4.

### M8-T06 Dock in the main docking bay to be repaired and relaunched

- **Goal:** AC5 (D82, Q7). Today the bays' `dock` interaction answers "not available" (§20.14).
- **Files:** the `dock` interaction in `InteractionHost`, `DockingPlan`'s lane for a fighter (the player's ship flown in under
  autopilot), the repair (hull, gun charge, missiles) and its timer, the relaunch through `launch_from`, the wing order and the hull
  threshold for wingmen, their slots held while away, a `dock` console command, `info.md`, tests.
- **Done when:** AC5.
- **Done (2026-11-18):** `DockingDirector` (Main's child; command and provider `dock`) fills the docking bay's `dock` interaction.
  **The player:** a hold of X within 2 km locks the controls; `DockAutopilot` (pure) flies the ship round the station by
  `DockKeepOut` (pure: the drum, the spine, the bow ring as boxes from `data/station/docking.json`, turning points with their
  shortest clear way worked out once) to the lane 400 m off the mouth, braking first from whatever speed it had
  (`StoppingDistance`, pure, for T18 to share), then down the lane through the mouth and the inner doors (asked and let go as the
  traffic's ships do). Behind the shut doors it leaves play (hidden, sheltered, no layers), `DockRepair`'s clock runs from the
  damage (6 s plus up to 30 s for the hull, data), hull, gun charge and tank are restored (no missiles exist yet), and it launches
  from Cobra bay Alpha 1 through `LaunchDirector` (`launch_player`; the next free arm when Alpha launches). Three shots
  (`dock_approach`, `dock_entry`, `dock_wait`); A or Start skips a stage each press. `dock cancel` and a respawn end a visit.
  **Wingmen:** the new order (key 6, `UiCommand.wing_dock`; the comms menu's DOCK on a ring of eight whose compass points keep the
  four orders) sends every damaged wingman; one below 40 % hull (25 % since the fix round, below) goes by itself. A docking pilot (`assets/ai/docking.tres`) flies
  it natively: a peel-off out of the formation when it leaves at speed, a route with avoidance to a waiting point off the bow,
  then `DockingPlan`'s lane, one ship at a time with the traffic (`StationTraffic.bay_busy`). Inside it is away (`Wing.set_away`:
  slot kept, not lost, not briefed; `close_gaps` neither moves it nor fills its place), then `LaunchDirector.launch_ships`, its
  own pilot back, and it rejoins. Control's offer below half hull is a signal (`dock_offered`) and a HUD line for T05 to replace
  with its dialog (D79 beat 13). Scenario `station_dock`.
  **Tests** (staged scratch copy, HEAD `a1050290` plus this task; the compile check, 939 scripts, and the docking files run again
  on `7406990c`): the compile check clean; 32 GUT
  files, 372 tests, 0 failures: the new `test_stopping_distance` (5), `test_dock_keep_out` (7, a grid of starts through the 2 km
  sphere arrives without entering a solid), `test_dock_autopilot` (6), `test_dock_repair` (5), `test_dock_visit` (5),
  `test_wing_away` (5) and `test_docking` (7: the reach, the hold to the relaunch with the state before and after, a 450 m/s
  start, skip and cancel, respawn, rebase, wingmen by order and by threshold rejoining their slots), with `test_wing`,
  `test_wing_gaps`, `test_wing_orders`, `test_wing_reform`, `test_wing_replenish`, `test_station_wing_follow`, `test_launch_bay`,
  `test_station_traffic`, `test_station_sheltered`, `test_respawn_in_play`, `test_console_command_list` and the input, comms and
  control-profile files. No native change.
  **Changed in older tests:** `test_nav_targets` (the "not available" hold is the cargo bay's now), `test_comms_menu`,
  `test_comms_menu_input` and `test_launch_bay` (slices of the ring of eight), `test_input_map` (key 6, outside the left block),
  `test_input_adapter`. **(H):** `docs/playtest.md`, "Play-testing docking for repair".
- **Fix round (2026-11-18, the maintainer's answers):** a wingman docks by itself only below **25 %** hull (was 40 %;
  `data/station/docking.json`, free flight included); the HUD roster reads **DOCKING** while a wingman flies in and **DOCKED**
  while it is inside or on the rack, then its usual readout (`Wing.set_docking`, `Wing.dock_status`, on M8-T13's roster by slot;
  the marks end with the membership, so a hull back from the pool carries none); key 6 for DOCK stays.
  **Home docks:** each fighter docks only at its own home (`Combatant.home`: the scenario's `home` on the player, a wing or a
  spawn, `"none"` for nothing; the station whose Cobra bays launched it; the wing's on a replenish; cleared by the pool), found
  among every `NavPoint` that offers `dock` (`NavPoint.DOCKS_GROUP`, so later stations and carriers are docks too; a carrier's
  recall stays M8-T08's). **Range:** the home dock's bay within `dock_range_m` of the fighter, 60 km (the station's space out
  to its jumpgate; before, self-docking measured 60 km to the station's middle and the order had no range). With no home, the
  home gone or out of range a fighter stays and fights, and the order cannot be given: the comms menu leaves DOCK's slice
  **blank** (hidden, not greyed: the radial menu has no disabled look) and key 6 does nothing; the console's `dock wing` says
  `NEGATIVE, NO DOCK IN RANGE`. The bay offers DOCK to the player only when it is the player's home (`free_flight` and
  `station_dock` set `player.home`). **Found on the way:** the keep-out boxes were 1000 m too far aft (the drum's pivot) and
  `station_dock` started 250 m from the mouth, not 1.2 km; both corrected (the drum and the spine as boxes; the ring round the
  mouth lies inside the drum's). **Tests** (staged scratch copy,
  HEAD `afefb54f` plus this round): the compile check clean (940 scripts); 31 GUT files, 412 tests, 0 failures after two
  expected updates (`test_comms_menu_input`: its scene has no home dock in range, so DOCK's slice is blank; the fixture moved
  out of the mission catalog's folder), among them `test_docking` (11: also a fighter with another home or none stays, the
  player is offered only its home's bay, out of range and without a station they fight on with the order unavailable on the
  key and the menu, Cobra-bay launches give a home, the roster's DOCKING and DOCKED), the new `test_scenario_homes` (6),
  `test_wing_away` (7), `test_dock_keep_out` (7), `test_hud_layout`, `test_comms_menu`, `test_scenario_loader`, `test_wing`,
  `test_wing_gaps`, `test_wing_orders`, `test_launch_bay`, `test_station_wing_follow`, `test_nav_targets`, `test_ship_pool`.
- **Follow-up (maintainer, 2026-11-18, queued until after the T3 Code restart):** the AI wings whose home is Babylon 5 (Beta, Delta,
  Zeta and the rest) self-dock for repair too, below the same 25 % hull, with their home in range; their formations keep the
  docked members' slots as the player's wing does.
- **Follow-up (maintainer, 2026-11-18, same queue): repair times.** An AI wingman that docks waits a fixed **30 s** for repair
  before it relaunches from a Cobra bay. **The player does not wait**: the dock cinematic is followed straight by the external
  launch cinematic (no repair stage or shot), repaired on the way through. Replaces the damage-scaled timer (6 s plus up to
  30 s) in `data/station/docking.json`.
- **Follow-up (maintainer, 2026-11-18, same queue): leash evasion.** Under FORM ON ME (and in AI flights), a wingman evading past
  the flight's cohesion distance (2.5 km, `data/wings/flights.json`) breaks toward its leader or flight instead of away, dragging
  the chaser into the wing's guns (M8-T19 saw one dragged 10.4 km off). Native, with parity and 1/6-thread identity kept.

### M8-T07 Bring M10-T19's raider strike carrier into `m8`

- **Goal:** AC6 (Q5). `m10` was cut from `m7` at `b002bbe`; T19 (the strike carrier, its collision builder, `CarrierDock` and the
  native docking kernel, the raid in `CarrierJumps`) is on `origin/m10`, not yet flown by the maintainer.
- **Steps:** merge `origin/m10` into `m8`; reconcile `tools/procgen/core/collision.py` and its tests with M7's builder into one
  (the station and the carrier both built from it, their compares unchanged); resolve `native/src/lib.rs`, the docs and `info.md`;
  rename the plan to `docs/milestones/m10-factions-and-capital-ships.md` and renumber its milestone references by the roadmap's
  mapping (its tasks become M10-T..); mark T20 `not needed (moved to M8-T09)` and T49 `not needed (moved to M11)`; the rest of the
  plan stays M10's, and its later work runs on branch `m10`.
- **Done when:** AC6; the station's and the carrier's Python, Rust and GUT tests pass in a `--staged --build-native` scratch copy.
- **Done (2026-11-18):** `origin/m10` (the branch renamed from `m12`, tip `a5d26349`: M10-T19's strike carrier, `CarrierDock`, the
  native docking kernel and rows, the raid in `CarrierJumps`, `carrier` and `transit docked`) merged into `m8`.
  - **One collision builder:** M7-T03's `core/collision.py` kept (its API, its manifest format with per-piece bounds and hit
    volumes, its coverage on render triangles); T19's second builder folded into it as additions: `box_around`,
    `capsule_between`, `Shape.transformed`/`translated`/`mirrored`/`renamed`/`volume`/`surface_points`, `ring_sectors`,
    `prism_points`, `shapes_of` and `skin_coverage` (coverage against sampled skin, which keeps the rings' holes open). The
    carrier's parts and generator moved onto it (`Budget(max_shapes=64)`, `merge_to_budget`, `section`, its coverage added to
    the section); its 162 shapes and coverage (worst gap 0.54 m, worst excess 1.57 m) are unchanged, and the station's
    collision section is byte-identical to before. `CompoundCollision` now reads the section through M7's `CollisionPieces`
    (a broken section gives no shapes, so the carrier falls back to its box). Both test files merged into
    `tools/procgen/tests/test_collision.py` (43 tests).
  - **Conflicts:** `native/src/lib.rs` keeps both module pairs (surface, dock); `test_sim_core.gd` holds both kernels to the
    rules; `transit_console.gd` grows the raider pool by the count the arrival needs; `look_scene.gd` keeps the station's new
    name and the carrier's sheet; `layouts.py`, `assets/__init__.py` and `manifest.py` keep M7's code with the carrier's added;
    the docs keep both sides (§19.18 before §20, both console tables, the carrier's play-test section, its design reference).
    The plan was renamed `m10-factions-and-capital-ships.md` and renumbered; T20 and T49 are `not needed` there.
  - **One test adapted:** M7-T75's `test_transit_carrier_grows_the_raider_pool_in_free_flight` collapsed the carrier's point after
    2 s and expected the cruiser stand-in in its funnel; the strike carrier holds its arrival point about 1 s and then stands
    off (T19's design), so the test collapses it while held and expects no funnel kill.
  - **Tests** (scratch copy of HEAD plus the staged merge, native rebuilt, `raider_strike_carrier` and `babylon5_station` rebuilt):
    Python 1 245 OK (12 skipped); Rust 242 passed; compile check 903 scripts; GUT 52 files (the carrier, station, collision,
    launch, docking, transit, encounters, mission skip, civilian escort, sim core, jump capability, parity and bench files)
    375 of 378 passed, 0 failed, 4 pending or skipped (3 need the GPU renderer, 1 balance file). `run_tests.sh --quick` in the
    main checkout passed in 244 s (Python 374, Rust 242, GUT 152 files, 2 009 of 2 009, smokes). The full standard suite was not run.

### M8-T08 The civilian escort's raids come with the strike carrier

- **Goal:** AC7 (D83, Q6). All three waves come with the strike carrier here; T09 then moves the last wave onto the Battle Wagon.
  This task also builds the jump-drive recharge per capital class and the raider carrier's retreat rules (D83) for every raider
  carrier, with tests: recall at 3 left and below 20 % hull, flight at 50 % damage and when every survivor has docked, a jump or
  the gate by the drive's state.
- **Files:** `data/missions/civilian_escort.gd` and its scenario (the waves' `via: "carrier"` with the docked option), the
  optional objective, the dialog for the carrier, `tests/integration/test_civilian_escort.gd`.
- **Done when:** AC7.
- **Done (2026-11-18):** the escort's three waves ride in docked on a raider strike carrier each (`RAIDER CARRIER 1` to `3`,
  the wave data in `civilian_escort.gd`'s `WAVES`: size, bearing and the spawn's `carrier` options, so T09 changes data only),
  are launched once it is clear of its point, and the carrier hangs back. Destroying any carrier is the optional objective
  `carrier` (Control's lines `control_carrier` and, at the end, `control_carrier_down`); one that gets away is no kill. Raiders
  back on a cradle count as down, raiders riding in as in play. Architecture §19.16 (the drive) and §19.18 (the retreat rules,
  the mission side).
  - **Jump-drive recharge** (`JumpDrive`, `JumpCapability`, `JumpPointPool`): opening a point empties the opener's drive and the
    pool refuses it another until its class's recharge has passed; a jumpgate needs no drive. Proposed numbers, in
    `data/capitals/capitals.json` (`CapitalData`): cruiser 60 s, destroyer 90 s, carrier 120 s, strike carrier 240 s (the
    longest). A carrier with no cradles holds its course until its drive is ready.
  - **Retreat rules** (`CarrierTactics`, `CarrierJumps`; the raiders' doctrine in the same file, a raid's `carrier` options
    over it): all home at 3 left in the fight (`recall_left`), one alone under 20 % hull (`fighter_return_hull`); the carrier
    flees at 50 % damage (`retreat_hull`), when its raid is over, or when every survivor has docked. Fleeing is a jump through
    its own point once recharged (it waits for fighters on their way first), else a run at 60 m/s (`flee_mps`) for the nearest
    jumpgate, or with no gate away from the enemy until the drive is ready. Not docked 90 s after the call (`wait_s`): left
    behind. `wait_s` was 45 s in M10-T19; measured in the escort, a raider called home from 6.5 km docks after 55 s.
  - **Found on the way:** a docked fighter lost its tier exemption at launch (`CarrierDock` hard-coded it), so a mission's
    launched raiders were parked by the tier and read as destroyed; the dock now keeps what the ship had, and a mission
    registers a ship before it docks.
  - **Console:** `carrier status` shows the drive and why and how it flees; `carrier charge`; provider `carriers` gains `flee`,
    `move`, `drive_left_s`, `gate_departures` (`info.md`).
  - **Tests** (scratch copy of HEAD plus the staged change, `GUT_SLOW=1`): compile check 925 scripts; GUT 32 files, 497 of 497
    passed, 0 failed, 0 pending: the carrier, jump, mission, escort, encounter, transit, bench and stand-in files, with
    `test_civilian_escort` 23 of 23 (4 new; the fought run ends at 435 s, inside 6 to 8 minutes) and `test_strike_carrier`
    16 of 16 (7 new or rewritten). No native or Python change. `bench_quick.sh` was not run (no per-tick work added: the
    carrier decides at 2 Hz).
  - **Play-test fix (2026-11-19, the maintainer's flight):** the civilian stopped after the second wave and never went on to
    NAV BETA, and NAV BETA was not in the target menu's objectives list. (1) It had arrived early, a raid chased it off, and
    with its route flown it idled where the chase ended, kilometres short (it also coasts about 3 km past its route's end
    on first arriving). `MissionStage.hold_route_end` (`m.hold_route_end`, asked for at the hand-over) now sends it back
    to its route's end whenever it has flown the route and is more than 500 m from it, slower the nearer it is so that it
    stops there, and again, faster, when a raid takes it further off on the way. The route behaviour itself (native) is
    untouched. (2) The escort objective named only the civilian. An objective may now give a `subject`; the escort's is
    NAV BETA, so the list shows the buoy from the hand-over (the civilian again if the buoy is shot away). The scripted
    fought run now ends with the civilian back at NAV BETA, at 782 s (with T09's Battle Wagon as the last wave; 744 s before).
    Tests (scratch copy of HEAD plus the staged change, `GUT_SLOW=1`): compile check 948 scripts; GUT 9 files, 170 tests, 164 passed, 0 failed,
    6 pending (the AI runs, behind `GUT_BALANCE`):
    `test_civilian_escort` (2 new: NAV BETA listed; taken 4 km short and 2.5 km past with a wave still up, the civilian
    flies back, stops within 500 m and stays), `test_objective_book` (1 new), the target menu, mission runner, mission skip,
    instructor route, strike carrier and scenario loader files.
  - **Fix round (2026-11-18, the maintainer's answers):** "home at 3 left" stays the doctrine and the escort's waves are
    **6, 8 and 10** raiders (`WAVES`; 24 pooled; each wave rides on one strike carrier, which has 18 cradles, so no second
    carrier and no fighters beside it are needed); the escort flies with **two wingmen**, ALPHA 2 and ALPHA 3, on `cover`
    (the scenario's wing, pool, briefing, the `home` objective "Bring ALPHA 2 and ALPHA 3 home", Alpha 2's line, Control's
    wave lines). The carrier running for the gate at once while its drive recharges, and the numbers in `capitals.json`: kept.
    - **Three ways the longer waves stalled the mission, fixed.** (1) A carrier standing off no longer leaves the fighters
      it called home at 3 left behind after `wait_s`: it waits for them (the fight is often 15 km from it, a 100 s flight),
      and `wait_s` counts only from when it flees. Before, raiders left behind this way could drift off and the wave never
      ended. (2) The escort's progress marks use NAV BETA's place, not the buoy: a stray bolt took the buoy and the next
      wave never came (seen at HEAD too). (3) It has arrived once the civilian has flown its route to the end, not when
      it is within 1.5 km of the buoy while the last wave's step looks: with longer waves it is there early, flees, and
      ends up idle elsewhere.
    - **CI:** `test_jump_holds` failed in shard 4 on a float edge of the test's own making (`fire(now - recharge)` is not
      yet "ready" for about 1 clock value in 600); the test now fires a second earlier. `JumpDrive` is unchanged.
    - **A scripted fought run** (`test_a_fought_run_ends_each_wave_at_three_left_before_the_next_comes`, seed 3: each wave shot
      down to three 10 s a raider after contact, the three fly home): waves at 69, 262 and 531 s, home or dead at 177, 501
      and 732 s, **the end at 744 s** (12.4 minutes; it was 435 s with 3, 4 and 6). The 6 to 8 minutes of Q40 no longer hold.
    - **Winnable with the wing? Flown by AI, no** (`_ai_fought_run`, behind `GUT_BALANCE`; a measurement, not a gate):
      ALPHA 2, ALPHA 3 and a third AI Starfury for the player's guns, the civilian and all three mortal, the pilotless
      player's ship held over the civilian. Six runs, none saved the civilian:
      - seed 1, cover (G'TARN): lost at 645 s; 14 raiders come, 7 destroyed (4 on their way home), 2 gone home, 5 still
        out; ALPHA 2 and 4 lost.
      - seed 2, cover (VELORA): lost at 730 s; 24 come, 7 destroyed (5), 7 gone home, 10 still out; ALPHA 3 and 4 lost.
      - seed 3, cover (TOLVAR): lost at 853 s; 24 come, 12 destroyed (7), 2 gone home, 10 still out; all three lost.
      - seed 1, engage (G'TARN): lost at 335 s; 14 come, 6 destroyed (4), none gone home, 8 still out; ALPHA 2 lost.
      - seed 2, engage (VELORA): lost at 281 s; 14 come, 5 destroyed (5), 1 gone home, 8 still out; no wingman lost.
      - seed 3, engage (TOLVAR): lost at 272 s; 14 come, 6 destroyed (6), none gone home, 8 still out; no wingman lost.

      Wave one (6) is always beaten; the wing is lost, or the civilian shot down behind it, in wave two (8). No carrier was
      destroyed. The runs do not repeat exactly (an earlier cover run on seed 2 won at 898 s with all three wingmen lost).
      For scale, the same check on the old escort (waves of 3, 4 and 6, one wingman plus the AI for the player) won 1 of 6,
      lost 2, and 3 did not end in 20 minutes (two stand-offs, one the buoy stall above). So the AI is a poor stand-in for a
      player, and by this measure the escort is harder than it was. Nothing was tuned. **(H)** the maintainer flies it;
      the levers are data: the waves' sizes, `recall_left`, a third wingman, the civilian's hull.
    - **Tests** (scratch copy of HEAD plus the staged change, `GUT_SLOW=1`): compile check 940 scripts; GUT 19 files,
      335 tests, 329 passed, 0 failed, 6 pending (the AI runs, behind `GUT_BALANCE`): `test_civilian_escort` 24 of 30
      (2 new: the buoy, the retreat-aware fought run in place of the old one), `test_strike_carrier` 16, `test_carrier_logic`
      17, `test_scenario_loader` 40, `test_jump_holds` 5 (and 21 of 21 run in one process after `test_strike_carrier`, the
      late clock the CI failure needed), the mission, encounter, dialog, objective, front-end and console-list files.

### M8-T09 Raider Battle Wagon

- **Goal:** AC8 (Q8; M10-T20 and Q31 moved here). Weapons settled with the maintainer before work starts.
- **Files:** the generator from `raider battle wagon.png` and `raider ships and battle wagon.png` (three views and two
  perspectives; no STL, so its check is (H) on a look sheet beside that sheet), its collision from the shared builder, the four
  launch tubes as hardpoints, the hull in the game on T19's capital body, its weapons on the native turret rows, tube launches for
  Delta-Vs, a sandbox scenario and free-flight raids, the civilian escort's last wave moved onto it (its mission data, dialog and
  `test_civilian_escort.gd`), `docs/assets-capital.md`, tests.
- **Done when:** AC8.
- **Done (2026-11-19):** the raiders' Battle Wagon, `raider_battle_wagon`: 275 m over its antenna spikes, one ring 161 m
  across, in the "salvaged" surface. The maintainer's choices of 2026-11-18 from stage 1's sheets
  (`references/screenshots/M8-T09 battle wagon/`): **two tubes with four lanes** (the sheet has two tubes, above and below,
  not four; `docs/design-references.md` corrected, with the ring at 0.58 of the length, not 1.3), surface C, all eight
  plasma turrets, four missile racks on the ring's bow face, 275 m.
  - **The asset** (`docs/assets-capital.md`): `parts/raider_wagon.py` (every proportion a share of the length read off the
    three-view sheet; no STL), 9 948 triangles, six break-up chunks, 142 collision shapes (covered 1.0 within 2 m, within
    reach 1.0 at 5 m; the tubes and the ring's openings open), hardpoints for the two tubes and their four lanes, twenty
    berths, eight turret mounts, four racks, eight nozzles and the jump point; low and high texture sets; 55 MB of video
    memory a set (RX 6950 XT).
  - **The build's memory.** The first build put the hull on one 4 096 px atlas, took about 10 GB and was killed for memory:
    a bake costs about 600 bytes an atlas texel. `civilian.write_hull_atlases` writes an atlas per chunk, baked one after
    another: **2.6 GB at its peak**, 110 s. `write_hull` is unchanged: the strike carrier and the Skylark rebuilt at HEAD and
    with this change (both at `atlas_px` 1 024, to stay inside the 6 GB cap) are byte for byte the same, 79 files.
  - **In the game** (architecture 19.18): the capital class `battle_wagon` on the strike carrier's body path. Its berths are
    the dock's cradles with their own ways (the native kernel's `Row::lane`, `ScsDockRows.add_lane`): launched ahead through
    the tubes' bow mouths, home through the stern mouths; a cradle's row is bit for bit what it was. Eight `TurretMount`s on
    the native turret rows fire `turret_raider_plasma.tres`; `MissileRacks` asks the native missile rows the bench's
    capitals use for a target and launches M4's guided missile (`RackSchedule`: six cells a rack, 20 s a rack, 2 s apart).
    `capitals.json`: its drive recharges in 240 s as the strike carrier's (D83: the raiders' are the longest), it keeps the
    raiders' doctrine, and `missile_racks.battle_wagon` holds the racks' numbers.
  - **Where it comes:** the escort's last wave (`WAVES`: `RAIDER BATTLE WAGON`, ten raiders on its berths; the scenario's
    `battle_wagons` builds one at load; Control's line and the optional objective's names follow; the fought run ends at
    740 s, as before), a quarter of free flight's raids (`wagon_share`), every raid of the new sandbox scenario
    `battle_wagon_raid` (New game, "Raider Battle Wagon"), and `transit wagon` on the console (`info.md`).
  - **Two things decided here, for the maintainer to confirm (H).** Its turrets are M5's gunners (D61): they fire on a ship
    that hit the wagon or a friend near it, not on every hostile in reach. Its racks fire only at a fighter within 3 km of
    it (data), though a missile reaches 6 km: it stands off at 2.5 km, so they defend it and do not shell the escort's
    fight from afar. Both are first figures, as are its hull (24 000) and the turret's numbers (`docs/playtest.md`).
  - **Tests** (scratch copy of HEAD plus the staged change, native rebuilt, the wagon rebuilt there, `GUT_SLOW=1`): compile
    check 948 scripts; Rust 256 passed (3 new: the lane cases); Python 176 OK in 8 files (`test_raider_battle_wagon` 26
    new); GUT 34 files, 416 tests, 410 passed, 0 failed, 6 pending (the escort's AI runs, behind `GUT_BALANCE`):
    `test_battle_wagon` 7 and `test_rack_schedule` 5 new, `test_carrier_logic` 19 (2 new), `test_civilian_escort` 25 of 31
    (1 new), `test_strike_carrier` 16, and the front end, loader, encounter, mission, jump, turret, missile, stand-in,
    console-list and settings files. `bench_quick.sh` was not run (a wagon in play adds a time check a tick; its turrets
    and docking paths are native rows). The full standard suite was not run.

- **Follow-up (maintainer, 2026-11-19, queued):** the Battle Wagon's turrets engage **any hostile within their reach** (1.6 km),
  not only ships that hit the wagon or a friend; the missile racks stay as built (fire within 3 km, the civilian a valid target).

### M8-T10 Interceptor muzzle at the drawn barrel tip

- **Goal:** roadmap M7-2: a battery's pulse and its muzzle flash start at the drawn barrel tip (placed from the shown angles), and
  the grid balance is measured again.
- **Done when:** a test puts the pulse's start at the barrel tip within a few centimetres at 30 m; the balance fights pass.
- **Done (2026-11-18):** `grid_kernels::lay_on` gives the azimuth and elevation that put the firing barrel's line through a point
  (a barrel 3.9 m beside the trunnion and 1.4 m over it needs a little more or less turn and lift than the trunnion's line), and
  `battery_shot` lays the barrel through the meeting the lead gives, leads again from that muzzle and lays again until the muzzle
  settles (under 1 mm, at most 6 passes). The muzzle is placed from the shown angles, so the pulse starts at the drawn barrel's
  tip, and its line is always the lead from its own start. The flash needed no change: it rides the pitch holder, so it was at
  the drawn tip already and the pulse now starts there too. Architecture §20.3.
  - **Measured** (the new GUT test on I5, bolts from 45 degrees up on four sides and from overhead): on HEAD the pulse started
    2.0 to 2.1 m from the drawn tip at 29 m and 4 to 5 cm at 1 to 1.2 km; now 0.0000 m at both.
  - **Right overhead.** No turn brings a barrel onto a point nearer the mount's axis than the barrel stands beside it (3.9 m): the
    mount keeps its azimuth there, and the pulse leaves the tip a little off the barrel's line (under half a degree at 900 m). A
    first version that only repeated "lead from the muzzle, show along the lead" never settled there and fired on a stale
    lead (the raid moved to a mean of 105.1 s); it was replaced before the commit.
  - **Balance** (`test_station_grid_balance`, GUT_BALANCE=1, seeds 1, 2, 3; before on HEAD 2e7e9c62, after with the fix, same
    assets): identical to the last figure. Raid mean 101.9 s (97.5, 106.2, 102.0; bands 90 to 120 and 75 to 140), pulses 298,
    215, 245 with 172, 127, 144 met; capital destroyed at 123.0, 123.5, 123.9 s (pulses 1 028, 1 268, 1 257); proof 1 149 lost
    with the batteries, 2 028 parked, 1.76 times (bar 1.5). 3/3 pass both times. The pulse still passes through the same
    meeting point with the same spread, only its start moved, so no pulse's hit or miss changed. No recording moved.
  - **Tests.** Rust: `lay_on` (the line through the point for every barrel at 12 m to 1.5 km, the held azimuth, the arc's floor)
    and `battery_shot` (the tip at 30 m and 1.4 km, overhead, below the arc, no lead from the muzzle). GUT:
    `test_a_batterys_pulse_starts_at_the_drawn_barrel_tip_at_30_m_and_at_long_range` (`test_grid_aim_call_sites`; fails on
    HEAD). `test_station_grid`'s barrel test checked that each start lay 2 m from the one before; its bolts fall within metres of
    I5's axis, where a left and a right barrel's tips now come close, so it checks each start against the drawn tip of the barrel
    that fired instead.
  - Counts from the staged scratch copy: Rust 248 pass; 908 scripts compile; GUT_SLOW=1 test_grid_aim_call_sites 3,
    test_station_grid 9, test_station_grid_threads 1, test_parity_fixture 3, test_flight_parity_fight 1, test_weapon_rows_battle
    1, test_brain_parity 7, test_brain_think_parity 5, test_heavy_cannon 10, test_interceptor_battery_model 4,
    test_turret_threads 3, test_turret_defense 2, test_turret_line_of_fire 3, test_turret_kernel 12, test_sim_core 21,
    test_native_constants 2, test_frame_passes 12, test_station_grid_lights 1, all pass; GUT_BALANCE=1
    test_station_grid_balance 3/3.
  - **(H):** up close, pulses leave the barrel tips; a battery firing at shots from nearly overhead turns far between its left
    and right barrels (it showed that before as well).

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
- **Done (2026-11-18):** `Wing.close_gaps`, called by `WingDirector.refresh` every tick after it drops the members that are
  down, so a wing the director runs never flies with a hole (`docs/architecture.md` §20.12, "Closing up after losses"). The
  rule works for any wing size and all three shapes (T19's flights of three included): the members behind an empty slot move up
  their own arm in order; then, while a ship would be better placed in the slot `fill_order` gives a newcomer (an arm two longer
  than the other, the centre ship beside an open arm slot), the worst placed one moves there; mirror slots count as equal, so
  an even wing sends nobody across. The result is the shape that many newcomers would have built, or its mirror.
  - **No native change.** A slot is only the offset in the pilot's `AiContext`; the core flies the new one as any slot, with
    T76's avoidance. Nothing in `native/` moved, so 1 and 6 threads and the `delayed` reference are as they were and no parity
    recording changed (`test_flight_parity_fight`, `test_weapon_rows_battle`, `test_brain_think_parity` green).
  - **Names (my choice, for the maintainer to confirm).** A pilot keeps its callsign and painted number when it moves up. The
    downed pilot's callsign goes with the hole to the back (`Wing.lost_callsign`); the replacement that fills it takes that
    callsign and its number (`WingDirector.callsign_for`). The HUD roster lists its rows by callsign number instead of by
    slot, so no row moves when the wing closes up and the DOWN row reads the downed pilot's callsign.
  - **Tests** (the staged copy, HEAD plus this change): `test_wing` 26 (+9: a finger-four's losses at the front, middle and
    back; an arm of ten moving up; several at once; the centre ship; even arms; the lost callsign; a newcomer after a loss;
    every size 1 to 12 in every shape with seeded random losses; a change of shape), 17 369 asserts. `test_wing_gaps` (new,
    slow, the real main scene on six threads) 6: Alpha's eleven under FORM ON ME shot at from astern by six seeded raiders,
    seeds 1 to 3 (4, 3 and 4 lost; 0 rams inside the wing; every survivor within 2.5 m of its slot 45 s after), and three
    schedules (the first of the left arm; four down at once then two more; a finger-four's last ship crossing to the empty
    arm): 0 rams, no two centres within 50 m, a shape without a hole on every tick. Four older tests asserted that a hole
    stays where it is and now expect the wing closed up (`test_wing_orders`, `test_wing_replenish`, `test_respawn_in_play`,
    `test_tier_fire`). In all: 34 files across the wing, formation, HUD, launch, station, mission, bench and parity tests,
    GUT_SLOW=1, every test passing; 924 scripts compile.
  - **For the maintainer (H), `docs/playtest.md`:** how closing up looks; whether the centre ship should move out to an arm
    that has room (it does, as `fill_order` puts the centre last); the callsigns and the roster's order.
- **Fix round (2026-11-18, the maintainer's answers):** kept: callsigns and painted numbers stay with the pilots, the
  replacement takes the lost pilot's and flies at the back, and the centre ship moves out to an arm. Reversed: the HUD roster
  is in slot order again (the lost slot reads the downed pilot's callsign); and the wing closes up only when a member is
  destroyed (`WingDirector.refresh`), so a released member, a slot whose ship took an AI wing's lead and a change of shape
  leave the slots as before, and `close_gaps` no longer runs every tick. A wingman away docking keeps
  its slot through M8-T06's `Wing.set_away`, which comes with that task. Tests: `test_wing_orders` +1 (only a loss
  closes the wing up), its roster rows by slot; `test_respawn_in_play` back to the slot the old member left. The
  staged copy, GUT_SLOW=1: `test_wing`, `test_tier_fire`, `test_hud_layout`, `test_hud_screens`, `test_wing_orders`,
  `test_wing_replenish`, `test_respawn_in_play`, `test_cockpit_screens`, `test_mission_skip` and `test_wing_gaps` (its fights
  and schedules to the number as before), 193 of 193, 18 919 asserts; 924 scripts compile.

### M8-T14 The bench writes to `user://` in an exported build

- **Goal:** roadmap L15 (`docs/research/m4-full-review.md`).
- **Done when:** the bench reads and writes under `user://` when `res://reports` is not writable; a test covers both.
- **Done (2026-11-18):** `BenchPaths` (`src/perf/bench_paths.gd`, pure but for its write probe): `resolve(path)` leaves a path
  alone unless it lies in `res://reports` and the project takes no files, then gives its place under `user://reports`. An
  export's `res://reports` globalises to the relative `reports` (no folder behind the pack), so "writable" is an absolute folder
  that takes a probe file. `BenchRunner` (its default root), `BenchReport.write` (every report file) and
  `scripts/bench_sweep.gd` (reading the runs, writing the sweep) go through it; no other runtime code in `src/` touches
  `res://reports`. The editor-only capture and sheet scripts (`scripts/*_node.gd`, `bench.sh`, `bench_quick.sh`,
  `aa_compare.sh`, `look_sheet.sh`, `render_compare.sh`, `fullscreen_check.sh`, `capture_m3.sh`, `measure_m3.sh`) keep their
  `reports/` paths. `addons/scs_export` needs no change; T15's preset must keep `reports/*` out of the pack, and a release bench
  links `user://reports` to the snapshot's `reports/` (`scripts/setup_export_templates.sh`, step 4). Checked from the staged
  copy: `test_bench_paths` 10 tests, 30 asserts (both cases by an injected answer, the probe, a report written each way),
  `test_bench_report` 8, `test_bench_layout` 28, `test_bench` 16 (GUT_SLOW), 905 scripts compile; a real `bench furball 10` and
  the sweep wrote to the project's `reports/perf/`; the release template beside a pack of `BenchPaths` wrote to
  `user://reports/perf/` and nothing beside the binary.

### M8-T15 Linux x86_64 release build

- **Goal:** AC10 (Q9).
- **Files:** a `scripts/` build script, `export_presets.cfg`, the templates' version and SHA-256 in `docs/research-notes.md`,
  `docs/third-party.md` if anything is added, an export smoke test.
- **Done when:** AC10.

### M8-T16 Performance and the GPU check

- **Goal:** AC11.
- **Done when:** AC11's numbers recorded in this file and `docs/architecture.md` §21.

### M8-T18 Approach cues and a speed-scaled gate reach

- **Goal:** AC14 (D84).
- **Files:** `src/hud/approach_cue.gd` (pure, test first) and its drawing on the navigation target's box and the status line,
  `GateJumpRequest.range_m(closing_speed)` and `data/jump/gate_request.json`, `GateAutopilot` starting from the ship's velocity,
  the gate's `CinematicShot` timed from the predicted arrival, `InteractionHost.status_text`, the `interact` and `gate` providers
  (the cue's state and the live reach), `info.md`, unit tests for the cue and the reach, integration tests of jumps requested at
  several speeds; `docs/playtest.md` gets the (H) checks (the cue reads in time to brake; a fast jump looks right).
- **Notes:** docking's own approach (T06) uses the same cue; if T06 has landed first, this task adds the cue to the bays.
- **Done when:** AC14.

### M8-T19 Flights of three and the hold-fire orders
- **Goal:** AC15 (D85).
- **Files:** the native brains (cover, cohesion, formation firing), `Wing`/`WingDirector`, `AiContext.Order`, the comms menu's page one,
  `InputMap` actions for the two orders with keyboard keys (and `test_keyboard_parity`), the scenario data's flight split, the
  dialog's acknowledgements, `wing order`, `info.md`, Rust and GUT tests, a seeded fight.
- **Notes:** after T13 (both change `Wing` slots). T05 depends on T19.
- **Done when:** AC15.
- **Done (2026-11-18):** M8-T19 flights of three and the hold-fire orders, as built in `docs/architecture.md` §21.2.
  - **The player's flight.** A scenario's `wings[].flight: true` on the wing the player leads keeps it at two wingmen
    (`WingDirector.command_flight`); orders, DOCK, the roster and the replenish reach those two only. The rest of the squadron,
    a scenario's members or the nine `launch wing` sends, flies as flights from 2 on (`next_flight_place`, `take_place`).
  - **AI flights.** A squadron of flights is several `Wing`s of one name (`Wing.flight`, `first_number`: ALPHA 4 leads 5 and 6),
    so slots, gap closing, lead succession and docking work per flight. A station's own wings launch as four flights of
    three (they were one wing of twelve); later leads hold a slot on the squadron's lead while there is nothing to fight.
    Numbers in `data/wings/flights.json` (`FlightRules`): size 3, cohesion 2 500 m, rejoin 1 000 m.
  - **Native (mirrored in the GDScript reference).** `Context.cover` (a hostile with a flight-mate selected outranks every
    other target; a wingman otherwise takes its lead's target), `cohesion_m`/`rejoined_m` (a strayed wingman attacks nothing
    and flies back to its slot), `ScsBrains.set_flight`. **Formation fires:** before, nothing let a ship in formation shoot
    (FORM ON ME gated every attack and the formation behaviour never held the trigger); now a ship within 150 m of its slot
    turns its guns on the nearest hostile in range and within 40 degrees of its leader's nose and fires on the attack's own
    gate, the thrusters keeping the slot.
  - **Two orders.** `AiContext.Order.FORM_HOLD_FIRE` (`form_hold`, key 7, FORM UP on the comms ring) and `HOLD_POSITION`
    (`hold`, key 8, HOLD POSITION; the formation behaviour brakes, so the ship stops against the reference and stays); any
    other order lifts them; acknowledged `FORMING UP, HOLDING FIRE` and `HOLDING POSITION, HOLDING FIRE`; a held wingman's
    roster row reads HOLD. The comms page lists them by order and names no angle (M8-T24 can resize the ring).
    `wing order form_hold|hold`, `wing.flights`, `info.md`, `docs/playtest.md` ((H) items for the look and feel).
  - **Measured (`test_flight_fight`, two flights against six raiders, 120 s, seeded).** With the rules the farthest a wingman
    got from its lead was 1.1 km and a mate under attack was covered 98 % of the time; the same ships as plain wings: 5.3 km
    and 79 %. One thread equals six and threaded equals `delayed`, bit for bit over 2 400 ticks.
  - **No parity recording moved**: `brain_tolerance`, `flight_parity_fight`, `weapon_rows_battle`, `bolt_rows`, `core_state`,
    `driver_step` and `row_commands` pass unchanged (the new rules need a flight's flags, a hold order, or a ship on its slot
    with a hostile in reach under an order that forbids attacking).
  - **`test_wing_gaps`.** No ram in the wing on any seed (the ram M8-T06 saw on seed 2 did not recur). Since the wing shoots
    back from its slots, seed 3's fight now runs to its time limit with ALPHA 9 chased 10.4 km off by one raider (evading the
    whole time, as FORM ON ME always allowed); the test gives such a stray the time its way back takes before it checks slots.
  - **Tests (staged copy, GUT_SLOW=1).** Rust 253 passed, 0 failed (five new in
    `brain_behaviours::tests`); import clean, 944 scripts compile; GUT 58 files, 662 tests, 661 passing, 0 failing, 1 pending
    (`test_dogfight`'s balance case). New: `test_flights` 4, `test_flight_fight` 3, `test_flight_rules` 3; grown:
    `test_wing_orders` 14, `test_comms_menu_input` 14, `test_comms_menu` 10, `test_wing` 28, `test_brain_think_parity` 6 (the
    native brain and its GDScript twin bit for bit on every new rule), `test_input_map` 13; kept green: `test_wing_gaps` 6,
    `test_docking` 11, `test_wing_away` 7, `test_launch_bay` 16, `test_station_traffic` 7 (both updated for four flights),
    `test_station_wing_follow` 11 and the recorded fights.
  - **Open, for the maintainer.** (H) the look of shots from the slot, the spacing of a squadron's flights and the two ring
    labels (`docs/playtest.md`). A wingman under FORM ON ME can be chased far off while it evades (seed 3 above): whether an
    evading wingman should be pulled back toward its leader is a design question this task did not decide. The tutorial's
    scenario (M8-T05) still has to declare `"flight": true` on the player's wing.

### M8-T20 GPU memory on the debug overlay
- **Goal:** AC16 (D86).
- **Files:** `src/rendering/vram_reading.gd` (pure, test first), `render_status.gd`, the debug overlay, `info.md`, unit tests; a GPU
  run on the maintainer's machine (`--console-exec="...; state render; screenshot references/screenshots/M8-T20 vram/x.png; quit"`).
- **Done when:** AC16.
- **Done (2026-11-18):** `VramReading` (`src/rendering/vram_reading.gd`, pure) reads `mem_info_vram_used` and `mem_info_vram_total`
  under `/sys/class/drm/card<N>/device` (the root is a parameter), picks the card whose PCI vendor the adapter name carries (AMD,
  NVIDIA, Intel words), else the lowest numbered card with both files, and formats the line; a GB is 1024^3 bytes.
  `RenderStatus.vram()` keeps the sample for 0.5 s and reads only when asked (the overlay shown, or `state render`), so no file
  is read per frame and none while the overlay is hidden. The overlay's line follows `GPU`:
  `VRAM  4.08 / 15.98 GB (26 %)   GAME 0.81 GB`, or `VRAM  GAME 0.81 GB   total unknown` without a driver total. `state render`
  has `vram_used_gb`, `vram_total_gb`, `vram_pct` (-1 when unknown); `vram_mb` is unchanged (the game's own, decimal MB).
  - **Tests** (a `--staged` scratch copy, 908 scripts compile): `test_vram_reading` 8, `test_vram_overlay` 4 (two reads a second
    over fake files, `state render`, the fallback, the main scene's overlay), `test_overlay_text` 7, `test_ship_scene` 24,
    `test_main_scene` 14, `test_console_command_list` 7, `test_debug_console` 29, `test_display_driver` 3: 96 passed, 0 failed.
  - **GPU (RX 6950 XT, RADV, Wayland, 1200x675 window, `forward_plus`, 60 fps):** `state render` gave `vram_used_gb` 4.08,
    `vram_total_gb` 15.98, `vram_pct` 25.52, `vram_mb` 873; `mem_info_vram_used` sampled every 0.1 s beside it read
    4 379 271 168 bytes (4.08 GB, 25.52 % of 17 163 091 968) at that moment. Screenshot and both logs in
    `references/screenshots/M8-T20 vram/`.
  - **Limits:** two cards of one vendor (an AMD APU beside an AMD card) cannot be told apart by the adapter name, so the lowest
    numbered one is shown; NVIDIA's and Intel's drivers do not write these files, so they get `total unknown` until a source
    is added for them (Windows gets its own in M9).

### M8-T21 The game's fonts

- **Goal:** AC17 (D87).
- **Files:** `assets/fonts/` (the two files), the default theme and its title variation, a `GameFonts` helper if code draws text,
  every screen and HUD element that sets its own font, `docs/third-party.md`, a guard test, a look sheet under
  `references/screenshots/M8-T21 fonts/` for the maintainer before the commit.
- **Done when:** AC17.
- **Done (2026-11-19):**
  - **Fonts and theme:** `assets/fonts/babylon5.ttf` and `babylon5_credits.ttf` (the maintainer's files, unchanged: both already
    carry a Unicode cmap, so D87's symbol-cmap fix was not needed; both have their own lowercase; Babylon5 draws `°`, `·` and `×`
    blank, and no title uses them). `src/ui/game_theme.tres` is the project theme (`gui/theme/custom`): Babylon5Credits for every
    control, Babylon5 for the `Title`, `Headline` and `Heading` label variations, so labels other tasks add inherit them. The
    `Fonts` autoload (the first) puts the fonts into it at start (`GameFonts.install`): named in the theme's file they broke a
    fresh checkout's first import, which loads the project theme before any font is imported.
    `GameFonts` hands both to code that draws its own text. The debug console keeps its fixed-width system font, the one exception.
  - **The maintainer's answers (2026-11-18):** the HUD's instrument text one size up (`HudPainter.TEXT_SCALE` 1.2) with the layout
    moved so nothing is drawn over anything (the cockpit's left screen: lights on the top row, fuel under the wireframe, REF kept
    to one line when ALT shows; the right screen: `CHARGE` and the fire mode on one line, roster rows and the target's name
    drawn smaller when too long; the chase view: readout, radar, hull and objectives rows spaced for the larger text); fixed
    digit slots for every HUD number and the target preview (`GameFonts.draw_line`: each digit centred in the width of "0");
    the debug overlay and the FPS counter in Babylon5Credits through `ReadoutText`, the overlay's columns placed by
    `ReadoutColumns` (cells two spaces apart, numbers ending at their column's edge) instead of `%8.1f` padding; the mission's
    name in Babylon5 on the briefing and the debrief only (`Headline`), radial headings left in Babylon5Credits.
  - **Also:** the pad diagram's legend shrinks until every line fits (the font is wider than the old one). Not scaled: the
    radial menus, the target preview, the subtitles and the control hint, already 16 px and more.
  - **Tests:** `test_font_guard.gd` (no source, scene, theme or project setting brings in another font; the console's is the one
    allowed), `test_game_fonts.gd` (coverage of ASCII and `°·…—`, the theme, digit slots), `test_readout_columns.gd`,
    `test_readout_text.gd`, `test_hud_text_overlap.gd` (every text the painter draws against every other text and gauge, chase
    window and the three screens, at 1920 by 1080 and 960 by 540). Verified in a staged copy (HEAD plus this commit) imported from an empty `.godot/` as CI does (no script
    error): compile check 957 scripts clean; the 38 UI and HUD GUT files 531 of 531 (5300 asserts, `GUT_SLOW=1`); every
    unit file 2749 of 2749; the main-scene smoke clean.
  - **Look sheets:** `references/screenshots/M8-T21 fonts/` (stage 1: before and after, the size and digit variants) and
    `final/` (the HUD in both views with and without the overlay and a target, at 1080p and the 960 by 540 size; menus,
    briefing, debrief). Readability in play stays (H).

### M8-T22 Gamepad detection

- **Goal:** AC18 (D88).
- **Files:** a pure joypad report class, the connect/disconnect toast and the front end's notice, the `joypads` console command
  and provider, `info.md`, `docs/playtest.md` (troubleshooting), tests with injected joypad events.
- **Done when:** AC18.

### M8-T23 The civilian escort in its own star system

- **Goal:** AC19 (D89).
- **Files:** `data/star_systems.json` (the new system), the sky and planet generators' data for it, `data/scenarios/civilian_escort.json`
  and its mission script, the escort's tests, a sheet under `references/screenshots/M8-T23 escort system/` for the maintainer first.
- **Done when:** AC19.

### M8-T24 Radial menus fit their entries

- **Goal:** AC20 (D90).
- **Files:** the radial framework (§18.19) and its view, `CommsMenu` pages, the target menu, the input adapter's picks, the console's
  `commsmenu pick`, tests. After M8-T19 lands (it adds two comms entries).
- **Done when:** AC20.

### M8-T17 Integration, full suite, docs and acceptance

- **Goal:** AC12 and AC13. Docs as built, the M8 checklist in `docs/playtest.md`, the roadmap row, `info.md`; the full suite once;
  the maintainer's play-test.
