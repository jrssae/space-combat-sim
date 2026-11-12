# Milestone 5: Mission Framework and Front End

> "Scripted play." (`docs/roadmap.md`)

**Status:** **built, awaiting the maintainer's confirmation (2026-11-12).** Every task is done except T20, whose automated part is
finished: AC1 to AC17 and AC19 to AC28 are met (the acceptance table's Done column), the full suite is green, the GPU check and
the benchmark are in T20's notes. What is left is AC18, the maintainer's play-test (`docs/playtest.md`, "M5 acceptance
checklist"), and the confirmation; then `m5` merges into `main`. History: planned 2026-11-02 on branch `m5`, cut from `main` at `b2f8ce1` (M3 merged) while M4 goes on separately on `m4`.
The maintainer asked for M5 to run beside M4 because most of it does not touch the performance work, and expects `m5` to
be rebased onto `main` once M4 merges (see "Living beside M4"). The planning questions were answered the same day (below),
including the civilian ships' lengths and a seventh civilian hull, the Centauri Brezebel (Q8, Q11). A ninth hull, the
Brakiri Bokmai transport with removable cargo pods, was added during the build (Q17). **2026-11-07:** `main` (M4 through T22
and T41, the native core) was merged into `m5` (Q27, T26); from here M5's per-tick, per-entity work goes in the native core
under `CLAUDE.md`'s language split and threading rules ("M5 on the native core", below). **2026-11-08:** M4 was accepted
and the rest of `main` (M4-T23 to T44, with the GDScript fallbacks removed) was merged into `m5` (Q34). The maintainer
then replaced the demo mission with **Civilian escort** (Q36 to Q42) and moved M4's later findings assigned to M5 into this
milestone as the **performance block** (Q35, T31 to T39).

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
voices. M8's tutorial is written on top of all this, so the framework matters more than the one demo mission. The demo
mission is a civilian escort through a thin asteroid belt (Q36). M4's review left eleven findings to M5: they are its
performance block.

## Maintainer answers (2026-11-02)

| Q | Question | Answer |
|---|---|---|
| Q1 | Which demo missions prove the framework? | (Superseded by Q36.) **Buoy defence**, with a **scripted cinematic intro**: raiders are sent at a nav buoy from beyond sensor range; the player and their wing defend it. Objectives, comms lines, win and fail, debrief |
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
| Q21 | (maintainer, 2026-11-03) The mission's buoys | (Superseded by Q41.) **Buoy defence is set on a string of nav buoys in a huge circle, as if round a planet: 16 buoys on a ring of 20 000 km radius, about 7 850 km apart.** **Every buoy broadcasts to 10 000 km** (was 1 000 km, M3 Q21), and the spacing is set so that a ship always has **at least two buoys in broadcast range**, on the radar and targetable: anywhere on the ring, and within about 6 000 km of it. There is no planet in the middle yet (M6 brings Epsilon III) |
| Q22 | (after T22's survey) The Bokmai's frame, colours and turrets | **The tall fins are at the stern**, so the blade is the bow (T22's reading; the STL stands on its tail, its length along file y). **The pods are pale green** (#ABAE9A, as proposed). **Two turrets, in the stepped Z-shaped insets on either side of the bow** (4.9 x 2.4 m, high on each flank; the survey had read them as windows), each facing outboard: an exception to Q19's top-only rule, for the Bokmai. **Brakiri turrets fire a bright green pulse.** (The maintainer first said one on top and one underneath the bow, then corrected it the same day) |
| Q23 | (same day) The Saturn 3's pod group misses 0.90 because T11 spread its pods wider than the model to let the truss and engine pass. Keep it? | **Keep the wider spread.** The Saturn 3's pod group is an **expected exemption** from Q18's bar: its scores are recorded with that note and do not fail T12. Every other Saturn part must still pass |
| Q24 | (maintainer, 2026-11-04) How civilians flee | **Every civilian has a faction** (the Saturns and the Skylark are Earth Alliance, the Narn transport Narn, the Brezebel Centauri, the Bokmai Brakiri); "civilian" is its role, not its faction. **Attacked, a civilian runs away from the enemy towards the nearest vessel of its own faction, of any kind** (an Earth Alliance freighter makes for any Earth Alliance ship, military or civilian). **Civilians under attack run together and cover each other** (they close up while fleeing, and their turrets fire for one another, D61). In T16 (the `civilian` profile and the faction data) and T21; T16 and T21 wait for M4's merge, so this lands after the rebase |
| Q25 | (maintainer, same day) More on fleeing | **Panic spreads:** a fleeing civilian sets other civilians of the same faction running when they are within about its radar range of it, even if nothing has attacked them. **Shelter behind the military:** when a fleeing civilian has a military ship of its own faction to run to, it aims for the far side of that ship from the threat, so the warship sits between it and the attacker. Read with Q24; T16, after the M4 rebase |
| Q26 | (maintainer, 2026-11-05, from the M4 session) Targeting with hundreds of ships | **Add a task to turn the target selector into a menu and brainstorm other targeting UX for large battles** (M4 brings battles of 300 to 500 ships, and cycling one ship at a time no longer scales). T25, after the M4 rebase; a concept stop for the maintainer before it is built |
| Q27 | (2026-11-07) M4's native core is on `main` since Q69's mid-milestone merge: how does it come into `m5`? | **Merge `main` into `m5`**, one merge commit and a normal push; no rebase and no force-push (supersedes the rebase of "Living beside M4" and Q6's force-push clause). M4's close-out comes in by a later merge the same way |
| Q28 | (same day) M4-T37 (the fallbacks removed) is still running on `m4` and touches the weapon files T21 extends. Wait for it? | **Start T21's native work now** on `main`'s core; take T37 in a later merge and resolve any overlap in `weapon_kernels.rs` and `weapon_rows.rs` then |
| Q29 | (same day) The second machine (`oscar`, two R9 280X) | **GPU runs are allowed there, labelled as oscar's** (never taken as the RX 6950 XT's numbers); **no many-ship scenarios** (no `bench`, no `battle` or `typical` layouts, no `GUT_SLOW` long fights) |
| Q30 | (maintainer, 2026-11-07, during T16) How do the Saturn specs relate? | **The Saturn 4 and Saturn 8 variants share one engine, so their acceleration follows their mass.** `saturn_4_transport`, `saturn_4_tanker`, `saturn_8_transport` and `saturn_8_tanker` all carry the Saturn 4 transport's engine and thrusters (`pod_main_thrust` 2.1e7, `pod_retro_thrust` 7e6, `rcs_force_max` (7e6, 7e6, 0), `rcs_torque_max` (6.9e8, 1.15e9, 5e8)); nothing is scaled per hull. Mass and inertia come from each hull's `hardpoints.json` (14 082 000 kg for the Saturn 4 transport, not 1.4e7): forward 0.304 g, 0.204 g, 0.168 g and 0.106 g; pitch/yaw/roll about 2.0/2.0/2.0, 2.6/4.1/5.2, 0.36/0.49/1.0 and 0.29/0.48/2.5 °/s². `rate_max` is set so the assist reaches it in a sensible time at that acceleration (T16's rule: 3 s from rest); `fuel_capacity_kg` per hull. **The Saturn 3 keeps its own smaller, slimmer engine (Q20)**, 1.523e7 N a pod, about the Saturn 4 transport's 0.30 g; its torque and RCS stay its own. A test pins it |
| Q31 | (maintainer, 2026-11-07, during T16) The turrets' balance on the civilian Saturns | **A Saturn occasionally wins against two raiders, but never against three.** Read (the controller, confirmed by the maintainer): every Saturn variant (`saturn_3_freighter`, `saturn_4_transport`, `saturn_4_tanker`, `saturn_8_transport`, `saturn_8_tanker`) alone with its own turrets and its Q30 spec; against two raiders, 10 seeds a variant, it wins at least 1 and at most 3; against three, 10 seeds, none. A fight runs until the Saturn is destroyed or no raider is left fighting (destroyed or beyond 5 km), capped at 600 s of sim time; the Saturn wins if it is alive at the end (alive at the cap is a win). The check that the turrets finish a raider left at 15 % hull that keeps attacking stays. **The turrets become a bit more dangerous** (the maintainer's follow-up): tune the shared turret `WeaponSpec` first (`assets/weapons/turret_light.tres`: damage, fire interval, spread; range about 1.5 km, Q14), then each hull's `hull_max` for what the turret alone cannot balance across the five; never the raiders' specs or AI. Supersedes D61's "two raiders destroy a lone Saturn 4 within 180 s in two of three seeds" |
| Q32 | (maintainer, 2026-11-07, T16 fix round 1) The finish check fails because the Saturn 4 transport dies before a raider under its dorsal arc comes back into it | **Every Saturn's command section gets two turrets, one on each side, instead of the single dorsal one** (supersedes Q19 for the command section): a smaller blind spot, the belly seen from astern left vulnerable on purpose. Read: on all five Saturns `dorsal_fwd` on the disc hub becomes `flank_l` and `flank_r` on the command section's flanks, `up` ±x outboard, the 200° arc unless the barrels need less, on turret pads; the cargo sections' `dorsal_aft` / `dorsal_mid` stay. The Saturn 3 carries 2 turrets, each Saturn 4 and 8 carries 3. Q31's sweep is re-run and re-tuned in its order, and the 15 % finish check comes back on (with a raider inside the arcs and a test pinning the rear-belly blind spot if the raider attacks from there) |
| Q33 | (maintainer, 2026-11-07, T16 fix round 2) Q32's rear-belly blind spot is not in the model: a turret fires through its own ship | **A ship's own hull blocks its turrets' fire.** Make the blind spot real with a native line-of-fire check, not by narrowing arcs: a turret fires only when the line from it to the lead point misses its own ship's hit volumes, and the pick skips an attacker the hull hides; for every turreted ship (M12's capitals too). Q31's sweep is re-run and re-tuned in its order |
| Q34 | (maintainer, 2026-11-08) "Pull m5, then rebase from main." A rebase rewrites 132 commits and needs a force-push; Q27 chose merges | **Merge `main` into `m5`** (Q27 stands): one merge commit, normal push |
| Q35 | (same day) "Add the updated requirements": there is no `requirements.md`; is it the roadmap's "Carried from M4's full review" table? | **Yes.** L1, L2, L3, L5, L8, L9, L12, L13 (performance), L6, L7 (sound pass) and L14 (tests and CI) become M5 tasks T31 to T39 (`docs/research/m4-full-review.md` has the details) |
| Q36 | (maintainer, same day) The demo mission | **Replace Buoy defence with a civilian escort.** The civilian travels from a starting nav beacon to one on the far side of a **less dense asteroid belt**. The player escorts it and fights off raider waves that trigger at **three points** on the way. **One wingman** for the player. **Three raiders in the first wave.** **The civilian ship is random** (any of the nine hulls) |
| Q37 | (same day) The waves' sizes | **3, 4 and 6 raiders** |
| Q38 | (same day) What the belt's rocks are | **New procedural rocks**: a small `tools/procgen` asteroid generator (lumpy textured rocks, a few shapes and sizes), placed sparsely. It pulls part of M14 forward; M4's grey-sphere bench stand-in stays for the bench |
| Q39 | (same day) What the civilian does under attack | **Flee, then resume**: it flees by the Q24 and Q25 rules and returns to its route to the far beacon once the raiders are gone |
| Q40 | (same day) How far apart the beacons are | **About 30 km**, about 6 to 8 minutes of play; the belt sits in the middle |
| Q41 | (same day) The 16-buoy ring of Q21 | **Drop it**: `BuoyRing`, its tests and the scenario's `buoy_rings` go, and buoys broadcast to 1 000 km again (M3 Q21). Supersedes Q21 |
| Q42 | (same day) A cinematic intro for the escort? | **Yes, adapted**: the civilian at the start beacon, then the player and the wingman flying past; Control briefs, then hands over |
| Q43 | (maintainer, same day) Where screenshots go | **`references/screenshots/<a folder named for the request>/`** (gitignored), for every screenshot an agent takes; written into `CLAUDE.md` |
| Q44 | (maintainer, 2026-11-08) T25's targeting concept | **Tap and a tactical-pause wheel**: a tap of the target button selects the nearest enemy; a tap while it is selected selects the 2nd nearest, and the next tap goes back to the nearest (only those two). Holding the button pauses the game and opens a command wheel that stays open after release: Enemies, Allies, Civilian, Unknown, Navigation, Mission objectives; each opens a second ring of the nearest five (objectives: up to five) plus "none". (Input superseded by the maintainer's layout of 2026-11-09 in T25's section: the menu sits at one side of the screen, the right stick points, A selects, B goes back; keyboard arrows or mouse direction, Enter, Backspace.) Picking a ship makes it the target, closes the wheel and resumes. Beacons and objectives become the HUD waypoint (highlighted on the radar) and never the ship's facing target; the latest of the player's pick and a mission's `m.waypoint` wins. "Hold = nearest the nose" leaves this button (an unbound action). **Unknown** = contacts beyond an identification range (5 km, the AI sensors) with no transponder (allies, civilians and buoys broadcast and are always identified); the radar and HUD show them as unknown. A mockup sheet first, then the build. **Mockup approved (2026-11-11)** with one change: in every radial menu with a "none" entry, "none" sits in the down slice (the target rings, Navigation, Objectives, and T46's comms pages when they have one). T43's info lines approved as proposed: name, class and faction, hull bar, range, closing speed (civilians add their cargo pods, objectives their text instead of a hull); no weapons, absolute speed or heading |

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
- **One mission**: Civilian escort with a cinematic intro (Q36; it replaced Buoy defence, T10, which is removed with the
  buoy ring, Q41), through a sparse belt of generated asteroids (Q38).
- **Performance block** (Q35): M4's later findings L1, L2, L3, L5, L8, L9, L12 and L13 (T31 to T36), and L14's test and CI
  clean-up (T38). The sound pass takes L6 and L7 (T37).
- **Civilian ships**: nine hulls in five generators (the Saturn family with five variants, the Skylark, the Narn
  transport, the Centauri Brezebel, the Brakiri Bokmai with removable cargo pods), measured from the references and
  rebuilt in `tools/procgen`, coloured after online images of each ship; each in its people's faction (`earth_alliance`,
  `narn`, `centauri`, `brakiri`) with the `civilian` role (Q24).
- **Free-flight encounters**: raider raids, allied patrols and civilian traffic, seeded, spawned from pools beyond sensor
  range, capped in ship count.
- **Sound pass**: new Starfury and raider gun sounds, new bolt impacts, per-thruster engine bursts placed on the ship.
- Console commands and providers for all of it (§6.4), schema entries for every new setting.

Out (explicitly):
- The Babylon 5 station, its interior behind the menu and launch bays (M7). The tutorial and its control checks (M8).
- Voiced dialog (M15). Lines carry a voice id now; nothing reads it yet.
- Music. Saved mission progress or unlocks (every mission is open; nothing persists but settings and control profiles).
- Mission types beyond the escort: rescue and towing, comets, M14's full asteroid fields (M5 builds only the rocks and a
  sparse belt the escort needs, Q38). Capital ships (M12).
- Performance work beyond the L-items above. The rebase cascade (L4) is M6's, the explosion and stand-in counters (L10,
  L11) M12's, the bench's `res://reports` (L15) M8's.
- A key or button to remember the last camera view (not wanted now, `docs/handoff-m4.md`).

## Living beside M4

*(Historical since 2026-11-08: M4 is accepted and all of it is in `m5`, Q34. The file rules below no longer apply.)*

`m5` and `m4` move at the same time. Since 2026-11-07 `m5` holds `main` (M4 through T22, Q27); M4's later work (T37, T42,
T23, T25) comes in by later merges of `main`, never a rebase. To keep those merges small:

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

## M5 on the native core (2026-11-07)

`CLAUDE.md` (from M4): per-tick work that scales with entity count goes in the native core (Rust with gdext under
`native/`); everything else stays statically typed GDScript. AI decisions run in the core's worker job one tick behind on a
frozen snapshot, applied at the join on the main thread against the pilot's stamp; work that writes to the engine in the
same tick (flight forces, bolts, the hit sweep, rams, weapons) stays on the main thread; no engine call off the main thread,
no GDScript threads; randomness is a seeded per-entity hash; results identical with 1 and 6 threads and between `sim_step`
threaded and `delayed`. M5's tasks, read against that rule:

| Task | Per tick, per entity? | Where it goes |
|---|---|---|
| T01-T04, T06-T09 (flow, menus, settings, controls, dialog, comms menu, cinematic camera, debrief) | No: UI and per-event | GDScript, as planned |
| T05, T10 (mission core and Buoy defence) | No: the runner's work grows with live triggers, not ships (49 units for 20 triggers with 4 or 502 actors, T05) | GDScript, as built |
| T11-T15, T22, T23 (references, generators, fidelity) | No: tools | Python; T27 moves the generators to textured meshes |
| T18, T19 (sounds, engine voices) | The per-frame step is bounded by `engine_voice_cap`; the 4 Hz re-rank walks every ship | GDScript; the re-rank's ship query moves to the core (T28) |
| T21 (turrets) | Yes: a weapon, every tick, per turret | The native core: rows and kernels beside M4-T20's, below |
| T16 (civilians in play) | The AI, avoidance and tier are; data, pools and assembly are not | AI already native (the `civilian` profile through the native brains); the big-hull kind, avoidance sizing and tier handling in the core; the rest GDScript |
| T17 (encounters) | No: per event, at most `encounter_max_ships` (24) ships | GDScript; its random draws are hashes of the session seed and the event index, not a stepped generator |

**Turrets under the threading rules (T21).** A turret is split like a pilot. Its **target pick** is a decision: it runs in
the AI job, one tick behind, on the frozen rows and the frozen attacker memory, and is applied at the join against the
turret's stamp. Its **aim, fire gate and shot** write a bolt row the same tick, so they run in the weapon rows' step on the
main thread. The **attacker memory** is updated on the main thread from the hit sweep's results in the sweep's order. A
shot's spread is a hash of the turret's id and the tick. M5's civilians carry one or two turrets each, under the parallel
threshold; a turret pass with its own measured threshold waits for M12's capitals.

### Maintainer directive (2026-11-04): Gaussian splats dropped

The maintainer dropped Gaussian splats from the project entirely (M4, answers Q29 to Q31 in `m4-performance-and-scale.md`).
Every ship, station and capital becomes a textured polygon mesh generated by code in `tools/procgen` (procedural UVs and
texture maps: colour, normal, roughness and metal, emissive). M4 builds that pipeline (tasks T30 and T31) and removes
`addons/gdgs_scs` and the splat code; the GDGS fork is archived and will be deleted.

For M5: **build new ship assets, including the civilian ships from the STL references, as textured meshes; do no new splat
work.** The STL fidelity rule stays (silhouette IoU at least 0.90 in three views, length, width and height within 10 %). Use
M4's mesh exporter (`tools/procgen/core/glb.py`, from M4-T27 and T30) rather than a second one. M5's existing splat code is
removed or converted when M5 rebases onto `main` after M4.

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
- **Revised by T45 (maintainer, 2026-11-09):** the start screen shows only its options list (New game, Load game,
  Free flight, Settings, Quit); New game lists the missions and the sandbox scenes; Controls moves inside Settings, which
  groups its entries as Gameplay, Controls, Camera & HUD, Video and Audio, on the start screen and in the pause menu
  alike. The paragraphs below are as first built.
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
- Factions (`data/factions.json`, revised by Q24): a civilian ship belongs to its own people's faction and `civilian` is
  its role: the Saturns and the Skylark are `earth_alliance`, the Narn transport `narn`, the Brezebel `centauri` and the
  Bokmai `brakiri` (Q17). Raiders are hostile to all four; `narn`, `centauri` and `brakiri` are neutral to everyone else
  (civilian turrets fire only at attackers, D61, so a feud between them would change nothing in M5). Civilians fly the M3
  `civilian` AI profile (never attack, evade, run from hostiles within 3 km), and run towards the nearest ship of their
  own faction, in a group with other attacked civilians (Q24, T16).
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
  keeps the splats honest against their own mesh, per view, with a band one LOD0 spacing wide for the splats' soft
  edge: at least 95 % of the mesh's silhouette is covered by splats (nothing missing), and at least 95 % of the splats'
  silhouette lies within the band of the mesh's (nothing misplaced). Plain IoU at 0.85 was tried first and failed
  faithful thin parts (a Saturn lead ship's truss, a 0.6 m wing), so it is not the measure. Turrets are left out (the models have none); the
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

- A turret is a gunner, not a pilot: the ship's brain keeps flying (a civilian runs) while its turrets pick their own
  targets. **Native (2026-11-07, Q28):** the turret is a row in the core's weapon rows, extending M4-T20's turret kernels
  (`native/src/weapon_kernels.rs`, `weapon_rows.rs`) from stand-ins to mounts. The aim kernel: traverse and elevation
  limits from the mount's arc, slew rates, lead by the same intercept maths as the brains; the fire gate: inside the arc,
  inside range, the lead error under the bolt's spread at that range. The attacker memory: a ship becomes an attacker of
  a victim when one of its bolts hits that victim (the hit sweep's shooter and victim) and stays one for 30 s; a turret
  may fire only at an attacker of its own ship, or of a civilian or ally within 2 km of it. The split between the AI job
  and the main thread is in "M5 on the native core". Rust unit tests for each kernel, GUT tests through the core.
- `hardpoints.json` `turrets[]`: `{name, position, up, arc_deg, barrel_m}` in the body frame. `TurretMount` (node, child
  of the ship, built by `ShipAssembly`) holds the turret's model and only turns it in `_process` from the row's aim; the
  shot is a bolt row in the core and goes through the native hit sweep (no new hit path, no projectile node). A generated `turret_fire`
  sound, built like D60's guns but lighter.
- Strength (Q14, deterrent): a light bolt, low fire rate, about 1.5 km range. A seeded headless fight pins the balance:
  two raiders destroy a lone Saturn 4 transport within 180 s in at least two of three seeds, and the transport's turrets
  finish a raider left at 15 % hull that keeps attacking it.
- The seam is general: any ship with `turrets[]` gets them (M12's capital ships). Targeting and the fire gate cost work
  linear in turrets times attackers, never a sweep over all ships (`ThreatMemory` keeps the short attacker list).
- Visuals: the turret model is a small textured mesh (T27), pooled with its ship (D22); its turn is part of the frame's
  per-ship pass (M4-T36's `FramePasses`), not a `_process` per turret.

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

### D62 Civilian escort (Q36 to Q42)

- **The mission** `civilian_escort` (`data/scenarios/civilian_escort.json`, `data/missions/civilian_escort.gd`,
  `data/dialog/civilian_escort.json`) replaces `buoy_defence`. Two nav buoys about 30 km apart (Q40): **NAV ALPHA**, the
  start, at the scenario origin, and **NAV BETA** beyond the belt. They are the existing `nav_buoy` asset and broadcast to
  1 000 km (Q41). The belt (D63) lies across the route in the middle: the straight line between the buoys crosses it.
- **The civilian is random (Q36).** A spawn's `type` may be `random_civilian`. The scenario loader resolves it from the
  run's seed before pools are built, so only the drawn hull is pooled, and retry (same seed) gets the same ship. Any of
  the nine hulls can come up; a Bokmai draws 1 to 3 pods from the same seed. Its name and callsign come from a small
  per-hull list in the mission data (all names original), and the dialog fills them in through a placeholder in the line
  text (`{civilian}`), so one dialog file serves all nine.
- **The civilian's route.** It is sent to NAV BETA (`m.send`, D39's pilot objective) at its hull's cruise speed, about
  100 to 150 m/s; the heavy Saturns build up to that speed slowly, which is part of the escort. Its native brain flies the
  route and avoids rocks by its size (T16's big-hull avoidance). **Flee, then resume (Q39):** when raiders attack it, it
  flees by Q24 and Q25 (towards the nearest ship of its own faction, behind it from the threat when that ship is
  military: an Earth Alliance civilian shelters behind the player or the wingman; a Narn, Centauri or Brakiri one simply
  runs). Once no hostile is within its flee radius for a few seconds, it turns back onto the route to NAV BETA. The
  resume is part of the pilot objective: the objective outlives the flee, and the brain goes back to it. It belongs in the
  native brains (per tick, per ship), not in the mission script.
- **The escort.** The player leads **Alpha wing** with one wingman, **ALPHA 2** (Q36), on the `cover` order. The
  civilian keeps its turrets (D61), which fire only at its attackers.
- **The waves (Q36, Q37).** Three trigger points on the civilian's progress along the route: about 25 % (before the belt),
  50 % (inside it) and 75 % (past it), each a `proximity` trigger on the civilian against a point on the route. The waves
  hold **3, 4 and 6 raiders**. Each jumps in (D51's `arrival: "jump"`) 6 to 12 km from the civilian, beyond the AI's 5 km
  sensors, from a different bearing, and is sent at the civilian. A wave whose point comes up while the last one is still
  fighting jumps in anyway; the raiders' pool holds all 13.
- **Objectives.** *Escort the {civilian} to NAV BETA* (primary): done when the civilian is within 1.5 km of NAV BETA and
  the third wave has jumped in and no raider is left fighting; failed when the civilian is destroyed. *Bring ALPHA 2
  home* (optional): failed when the wingman is lost. Failure also comes from the player's death (D51). The mission ends on
  a closing line, then the debrief.
- **The intro (Q42).** Two shots: the civilian beside NAV ALPHA with the belt's rocks beyond, then Alpha 1 and 2 flying
  past a camera held still in space. Control (or the civilian's master) hails over the fly-past and briefs with the
  controls held, then hands over. A or Start skips a shot.
- **Skipping.** `mission goto wave_two` and the rest work as D51 says: a skipped wave's raiders are released, and an
  `arrived` or `proximity` trigger on the civilian places it at the point, so a skip leaves the world as the step would.
- **The ring goes (Q41).** `BuoyRing`, `test_buoy_ring.gd`, the scenario field `buoy_rings`, the Buoy defence files and
  their tests are removed. `NavBuoy.BROADCAST_RANGE_M` returns to 1 000 km (M3 Q21), with `test_broadcast.gd` to match.
  §18 records both changes.

### D63 Generated asteroids and a sparse belt (Q38)

- **Generator.** `tools/procgen` gains an `asteroids` asset: a handful of rock shapes (about six), each a seeded icosphere
  pushed out by layered noise into a lumpy rock with a few craters, written as M4's textured `.glb` (UV atlas, colour,
  normal, roughness and metal maps from `core/glb.py`) with two or three mesh levels. Greys and browns with a little
  variation per shape. The manifest records each shape's bounding radius and the radius of the sphere that stands for it
  in collision. Python tests: determinism, watertight and outward-facing triangles, triangle budgets per level, radii in
  the manifest that match the mesh.
- **Placement.** A scenario's `asteroid_belts[]`: `{centre, size: [x, y, z], count, radius_m: [min, max], seed,
  min_gap_m}`. A pure `BeltLayout` (`RefCounted`) turns it into rocks (position, shape, scale, rotation): seeded and
  deterministic, every rock inside the box, no two closer than `min_gap_m` plus their radii, sizes drawn so small rocks
  outnumber large ones. Unit tests cover all of that.
- **Less dense (Q36).** The escort's belt is about 8 km deep along the route, 24 km across and 3 km high, with a few
  hundred rocks of 10 to 150 m: an average gap of several hundred metres, so a 200 m Saturn 8 threads it while avoiding
  rocks, and a fighter can use the rocks for cover. The task tunes the count to that rule and records it.
- **In the game.** `AsteroidBelt` (node, `src/world/`) draws every rock of one shape with one `MultiMeshInstance3D` per
  shape and level (visibility ranges switch the levels). Each rock's collision is a static sphere made through
  `PhysicsServer3D` by RID and registered in `StaticRows`, as M4's `AsteroidField` does, so the contact scan, the hit
  sweep, rams and avoidance all see the rocks with no node per rock and no per-tick walk. It is spawned from `UniversePos`
  and follows rebases. The rocks do not move in M5. M4's `AsteroidField` stays the bench's stand-in; M14 builds full
  fields on this generator.
- **Cost.** On the maintainer's GPU the belt in view adds a handful of draw calls (one per shape and level). The agent
  records FPS, draw calls and VRAM with the belt in view (CLAUDE.md's GPU rule), and the tick cost of the static rows at
  the belt's count.

## Acceptance criteria

| # | Criterion | Kind | Done |
|---|---|---|---|
| AC1 | Boot: a windowed launch shows the front end; `--headless`, `--console-exec`, `--console-file`, `--scenario=<id>` and `skip_front_end` go straight to `Main` as before; `GameFlow` transitions unit-tested; `game` provider, `menu` and `play` commands work under `--console-strict` | A | **Met.** `test_game_flow` (27: the states, moves and the boot rule), `test_boot_routing` (14); the suite's smoke runs `--scenario=free_flight` straight to Main, `menu`, `play` and `game.*` under `--console-strict`, `play nowhere` exits 1, and the front end loading Main with nothing leaked. Windowed launch on the GPU shows the start screen (`T20 acceptance/start_screen.png`) |
| AC2 | Front end and pause: the pause menu and the settings and controls screens use the three-panel frame of Q15 (options left, pad diagram with live bindings bottom left, objectives right; a test checks the legend follows a rebind); every screen is reachable and usable with the pad alone (a test drives focus with injected `ui_*` events); free flight starts with encounters on or off; Missions lists the demo mission (Civilian escort since Q36) with its briefing; Sandbox starts each existing scenario; Quit quits; Start in flight opens the pause menu and Quit to menu returns to the front end; a loading screen shows while `Main` loads; no splat node enters the tree during play | A | **Met, as changed by T45 (AC27).** `test_menu_frame` (11), `test_front_end` (25), `test_pause_menu` (29), `test_loading_screen` (2), `test_pad_legend`, `test_pad_diagram`, `test_mission_catalog`: the three-panel frame, the legend following a rebind, pad-only focus with injected `ui_*` events, free flight with encounters on or off, the escort with its briefing, each sandbox scene, Quit, Start to the pause menu and Quit to menu. Missions and Sandbox are now under New game (T45). No splat node exists any more (M4-T31) |
| AC3 | Settings menu: every schema entry has a category; entries with `menu: false` are hidden; changing, applying, reverting and resetting a value works and persists through `Settings.save`; four audio buses with their volumes | A | **Met.** `test_settings_schema` (26: every entry has a known category), `test_settings_menu_model`, `test_settings_screen` (12: change, apply, revert, defaults, persisted through `Settings.save`), `test_audio_buses` (unit and integration: four buses and their volumes). T03's open minor items stand (the console's `audio.volume` sets only `sfx_volume`; Revert reverts every key) |
| AC4 | Controls menu: pick a profile; rebind an action by pressing a button; unbind; save as; the profile rules are enforced with the reason shown; applying a profile leaves the `ui_*` actions intact | A | **Met.** `test_controls_model`, `test_binding_capture` (25), `test_controls_screen` (35: pick a profile, bind by a press, unbind, save as, each refusal shown with its reason, `ui_*` intact after every change) |
| AC5 | Mission runtime: `MissionScript`, `MissionApi`, `MissionRunner`; every trigger kind unit-tested; `ObjectiveBook` success and failure; the result rules of D51 (all primaries done, a primary failed, the player destroyed, `m.end`); sim time only; console `mission` provider, `mission skip`, `mission goto <step>`, `mission objectives`, `play <id>`; a skip leaves the world as the step would (a test compares a skipped and an unskipped run's spawns and objectives) | A | **Met.** `test_triggers` (32, all seven kinds with `test` and `force`), `test_objective_book` (19), `test_mission_sequencer` (19), `test_mission_runner` (18: the four result rules, the console's `mission` provider and actions, 20 live triggers inside a counted bound), `test_mission_skip` (7: a skipped run leaves the same spawns and objectives as a played one); `play <id>` in the smoke runs |
| AC6 | Dialog: lines and speakers as data with a voice id; every line id used by a script exists (test); subtitles and the comms panel show in cockpit and chase views; `radio_open`/`radio_close` frame each line | A | **Met.** `test_dialog_book`, `test_dialog_queue`, `test_dialog_ids` (5: every line id and speaker a script uses exists), `test_mission_say`, `test_comms_layout`, `test_comms_panel` (14: both views, the squelches round each line). Seen on the GPU in the escort (`T20 acceptance/escort_intro_wing_shot.png`, `escort_wave_two_belt.png`) |
| AC7 | Comms menu: D-pad Right opens it; the four wing orders go through `WingDirector`; while open, the D-pad's flight actions and the target button do not fire; a profile saved before M5 loads with `comms_menu` filled in. **Updated by T46 (2026-11-11):** the orders are picked with the right stick and A on the radial ring (not the four D-pad directions), B or D-pad Right closes it, and there is no 4 s timeout (the game is paused while it is open); AC28 is the full behaviour | A | **Met as updated by T46** (AC28 has the behaviour). `test_comms_menu` (9), `test_comms_menu_input` (13: the four orders through `WingDirector`, nothing else fires while open), `test_control_profile_store` (a profile saved before M5 loads with `comms_menu` filled in) |
| AC8 | `CINEMATIC`: shots from data relative to actors or the origin, unit-tested interpolation; a rebase during a shot moves nothing on screen (test); HUD hidden, letterbox, the player's commands zeroed while the ship keeps its physics; A or Start skips | A | **Met.** `test_cinematic_shot` (15: the interpolation), `test_cinematic_camera` (12: a rebase during a shot moves nothing on screen, HUD hidden, letterbox, A or Start skips), `test_control_lock` (10), `test_mission_cinematic` |
| AC9 | Debrief: result and reason, objectives, time, kills and assists, wing losses, shots and hits; retry restarts the same scenario and seed; menu returns to the front end | A | **Met.** `test_debrief_model` (21), `test_mission_tally`, `test_debrief` (26: result and reason, objectives, time, kills and assists, wing losses, shots and hits; retry plays the same scenario and seed through loading; the front end) |
| AC10 | Civilian escort (D62): starts from the menu with its cinematic intro and runs to success and to failure (civilian destroyed; player destroyed) in headless tests driven by console commands, ending in the debrief; the civilian is drawn from all nine hulls by the seed (test over seeds) and only its hull is pooled; it flies from NAV ALPHA through the belt to NAV BETA about 30 km away, flees when attacked and resumes its route (test); three waves of 3, 4 and 6 raiders jump in at the 25, 50 and 75 % points; one wingman; the buoy ring is gone and buoys broadcast to 1 000 km (Q41). Buoy defence's AC10 is superseded | A | **Met.** `test_civilian_escort` (12: from the menu on a fresh seed, console-driven to success and the debrief, failure by losing the civilian and by losing the player, flee and resume, a skipped wave leaves no raider, a Saturn 8 through the belt, buoys at 1 000 km and no ring), `test_scenario_loader` (the seed draws every one of the nine hulls and only that hull is pooled; a retry flies the same ship). The buoy ring and Buoy defence are removed. On the GPU: the intro and waves one and two at 145 fps, 82 to 85 draw calls |
| AC11 | Civilian references: each of the nine ships described (the Saturn 4 tanker from the Saturn parts, Q16; the Bokmai, Q17) in `docs/design-references.md` with the lengths from Q8, Q11, Q16 and Q17, from orthographic views and cross-sections of its STL; every ship's colour scheme written from online images (Q11) with the sources listed; nothing from the STL files or the images is in git | A | **Met** (T11, T22). `docs/design-references.md` describes the nine ships with their lengths and colour schemes and lists the sources; `references/` is gitignored and no STL or image is in git |
| AC12 | Civilian generators: nine hulls from five generators meet the output contract (LOD0-3 PLYs and lighting records, fallback mesh, hardpoints with pods, RCS, collision, cockpit camera, chase anchor, running lights, chunks; the Bokmai's pod model and `cargo_pods[]`); Python tests for budgets, frames, symmetry where the design has it, chunk partition, collision coverage and determinism; every PLY imports in Godot with the manifest's count | A | **Met in the form T27 gave it** (Q29: splats dropped, so the output is a textured mesh with Godot's own mesh levels, not LOD0-3 PLYs). `test_saturn_family`, `test_skylark_transport`, `test_narn_transport`, `test_centauri_brezebel`, `test_brakiri_bokmai` (budgets, frames, symmetry, chunk partition, collision coverage, determinism, the Bokmai's pod model and `cargo_pods[]`), `test_seams`, `test_textured_hulls`; `test_civilian_meshes` (7: every hull imports in Godot as the manifest says). Python: 860 tests, OK |
| AC13 | Civilian ships in the game: each flies through `FlightModel` with zero damping (the damping guard covers it), turns by torque only, flees raiders on the `civilian` profile, towards the nearest ship of its own faction (behind it from the threat when it is military) and in a group with other fleeing civilians, and sets same-faction civilians within its sensor range fleeing too (Q24, Q25), takes hull damage, breaks into its chunks, shows running lights and switches LOD; a Bokmai flies with 0-3 cargo pods and sheds them when destroyed; raiders attack them through faction data; on the maintainer's GPU all nine in view at once run with `renderer = forward_plus`, FPS, draw calls and VRAM recorded by the agent | A | **Met.** `test_civilian_ships` (6: every hull Newtonian with zero damping and torque-only turning, hull damage, chunks, lights, LOD, the Bokmai's pods mounted and shed), `test_civilian_flight` (5: flees to its own faction, groups, the alarm; 1 and 6 threads, threaded and delayed), `test_ship_catalog`, `test_factions`. **GPU (T20, RX 6950 XT, RADV, Wayland, 1200x675 window):** all nine in view in `civilian_showcase`: `forward_plus`, 145 fps (the Wayland cap), 129 draw calls from the cockpit (96 in chase), `render.vram_mb` 481 MB (the card as a whole 3 262 MB with the desktop, 2 832 MB before the run) |
| AC14 | Encounters: `EncounterPlan` is deterministic per seed (test); raids jump in 6-12 km out and patrols and traffic cruise in from 26-30 km (D58), all from pools, and are released past 40 km (D58; this line said 30 until T17); raiders sent at a civilian attack it and allies engage them; `encounter_max_ships` holds; encounters off leaves free flight empty; `encounters` provider and `encounters force <kind>` to force one | A | **Met.** `test_encounter_plan` (15: deterministic per seed, the ranges), `test_encounters` (17: pools, raids at a civilian and allies engaging, the cap waiting and trimming, releases past 40 km, off leaves free flight empty, the provider and `encounters force`) |
| AC15 | Sounds: generator tests pin the new guns' shape (length, flat hold, constant pitch, energy band after the 0.25 register, inharmonic partials), the impact's length and band, and the engine bursts' band (no energy to speak of below 300 Hz); voices sit at the nozzles; the voice cap holds and the per-frame update is linear in voices (work count); the old loops are gone | A | **Met.** `test_sfx_combat` (the guns' length, flat hold, constant pitch, band and inharmonic partials; the impact; the bursts' band), `test_audio`, `test_engine_voices` (23), `test_engine_audio` (14: voices at the nozzles, the cap, work linear in voices), `test_voice_query` (5); the old loops are gone from the generator |
| AC16 | Cost: M5 adds nothing measurable to AC13 of M3 (the paired 13-ship AI budget still passes, `test_ai_think_time`); the mission runner with 20 triggers and the encounter director stay inside their work counts | A | **Met.** `test_ai_think_time` passes in the full run (13 ships: AiPilot median 195 us against the M2 brain's 2 177 us); `test_twenty_live_triggers_stay_inside_a_counted_bound`; the encounter director's `check_work` tests in `test_encounters`. `bench battle 1000` (T20, headless, idle): tick median 5.44 ms, p99 7.51 ms, real time kept, against 9.22 ms at M4's close |
| AC17 | Docs and the suite: `docs/architecture.md` §18 as built, a `docs/playtest.md` M5 section (how to start, menus, mission, comms menu, encounters, new settings and commands), the roadmap row; `scripts/run_tests.sh` green **once, at the end** (Q10), read from the suite's own totals | A | **Met.** Architecture §18 as built (a map of its 33 subsections, the file list, the superseded parts marked); `docs/playtest.md` "Play-testing M5" with one (H) checklist; the roadmap row. `scripts/run_tests.sh --full` passed on 2026-11-12 in 4 459 s, exit 0: GUT 303 scripts, 3 433 tests, 3 421 passing, 0 failing, 12 pending (10 need the real renderer, 2 are M3's AC12 balance tests still under the maintainer's review), 134 659 asserts; Python 860 tests OK (2 skipped); Rust 66 passed; every console smoke run passed |
| AC19 | Defensive turrets (D61): the native turret kernels (aim, fire gate, target pick) and the attacker memory unit-tested in Rust and through GUT, identical with 1 and 6 threads and between `sim_step` threaded and `delayed`; civilians fire only at attackers of themselves or of a civilian or ally within 2 km, and never through their own hull (Q33: a blind spot astern of a Saturn is pinned); they keep running while firing; turret bolts go through the projectile pool and `HitResolver`; the seeded balance holds (Q31: every Saturn variant alone beats two raiders in 1 to 3 of 10 seeds and three raiders in none, a fight running until the Saturn dies or no raider fights on, at most 600 s; its turrets finish a 15 % raider that keeps attacking); `turret_fire` sound | A | **Met.** Rust `turret_kernels/tests.rs` (in the 66 `cargo test --lib`), `test_turret_kernel` (12), `test_turret_threads` (3: threaded against delayed, 1 against 6 threads, byte for byte), `test_turret_line_of_fire` (3: the own hull blocks, the Saturn's blind spot astern), `test_turret_defence` (2), `test_turret_balance` (2, balance tier: every Saturn variant beats two raiders in 1 to 3 of 10 seeds and three in none), `turret_fire` in `test_sfx_combat` |
| AC20 | Fidelity (Q18): every civilian model's top, side and front silhouettes overlap its STL's by at least 90 % (intersection over union) and its length, width and height are within 10 %, Q16's deliberate departures scored part by part against the model each part was built from; measured on the model's geometry (its fallback mesh) by `tools/refview` compare, with the LOD0 splats covering at least 95 % of their own mesh's silhouette and lying at least 95 % within a one-spacing band of it, and unit tests that pin the tool's calibration; each model's scores recorded in `docs/assets-civilian.md` | A | **Met on the textured mesh** (T27 re-scored it; the splat coverage clause went with the splats, Q29). `test_refview_compare`, `test_refview` (the tool's calibration); every hull's silhouette and size scores are in `docs/assets-civilian.md`, with the Saturn 3 pod stack's deliberate departure (Q23) |
| AC21 | Asteroids (D63): the generator's Python tests (determinism, closed meshes, budgets, radii); `BeltLayout` unit-tested (seeded, inside the box, gaps held, size spread); the belt's rocks are static rows that the scan, hits, rams and avoidance see; a Saturn 8 crosses the escort's belt in a headless run without hitting a rock; FPS, draw calls and VRAM with the belt in view recorded on the maintainer's GPU | A | **Met.** `test_asteroids` (determinism, closed meshes, budgets, radii), `test_belt_layout` (7), `test_asteroid_belt` (4: static rows seen by the scan, hits, rams and avoidance; a rebase), `test_a_saturn_8_crosses_the_belt_without_hitting_a_rock`. **GPU (T20):** `belt_showcase` (400 rocks, 16 draw groups): 145 fps and 62 draw calls in chase, 131 fps and 94 from the cockpit, `render.vram_mb` 355 to 360 MB; the escort's belt with a wave in view 145 fps, 85 draw calls, 403 MB |
| AC22 | Performance block (Q35): each of L1, L2, L3, L5, L8, L9, L12 and L13 fixed as its task says; results unchanged (the recorded parity fixtures, and the same answers with 1 and 6 threads and with `sim_step` threaded and delayed); each task measures `bench battle 1000` before and after with `scripts/bench_quick.sh` on an idle machine, and the per-stage numbers go into its Done notes against Report P3's (flight 3.97 ms, hits 1.41 ms, rams 1.20 ms at 1 000) | A | **Met.** L1 T31, L2 T32, L3 T33, L5 T34, L8 and L9 T35, L12 and L13 T36, each with its before and after in its Done notes; the parity fixtures and the thread tests (`test_core_threads`, `test_core_snapshot`, `test_flight_parity_fight`, `test_weapon_rows_battle`) pass in the full run. **T20's run** (`bench_quick.sh t20 battle`, 1 000, seed 1, idle): tick median 5.44 ms, p99 7.51 ms; flight 2.30 ms (P3 3.97), hits 0.78 ms (P3 1.41), rams 0.23 ms (P3 1.20) |
| AC23 | Sound and test clean-up (Q35): L6 (muzzle flashes and shot sounds culled by range, a ring buffer for the flash pool) and L7 (no audio node per pooled ship walked every frame) with work-count tests; L14's shared test steps fixture, the collapsed recordings, the always-pending balance tests out of the default run, and CI's Python job split off with cached assets, CI green | A | **Met.** `test_shot_cull` (5), `test_muzzle_flash_pool` (4), `test_impact_flash`, `test_engine_audio`'s work counts (L6, L7); `TestSteps`, one recording in `test_core_state`, the balance tier (`tests/balance_suite.txt`), CI's Python job and asset cache (L14). CI green on run 43179401269 (T38) and on T20's pushes |
| AC24 | Pause backdrop (T42): with the pause menu open, an outside camera flies a slow closed figure 8 around the player's ship behind the menu (`PauseOrbitPath` unit-tested: closed, smooth, never inside the hull's clearance, always looking at the ship); it blends in from the camera in use and back to it on Resume; the world stays paused; `settings.pause_backdrop` off gives the old still view; no player ship (dead, or mid-load) leaves the still view | A | **Met.** `test_pause_orbit_path` (6: closed, smooth, outside the hull's clearance, looking at the ship), `test_pause_menu` (the blend in and back, the world paused, the setting off, no player ship), `test_camera_rig`. GPU: `T20 acceptance/pause_backdrop.png`, 145 fps, 117 draw calls |
| AC25 | Target preview (T43): highlighting an entity in the target menu's second level shows its green wireframe on the side of the screen opposite the radial menu, vertically centred, slowly turning, with only the edges on the side facing the viewer (feature edges plus the silhouette, no flat-panel diagonals), its hull bar and distance, and the info lines T43 settles; `FeatureEdges` and `TargetPreviewModel` unit-tested; the preview's viewport renders nothing while the menu's second level is closed; opening it on the largest hull costs what T43 records | A | **Met.** `test_feature_edges` (9), `test_wire_framing`, `test_target_preview_model` (11), `test_target_preview` (10: the side, the content per kind, nothing rendered while closed); the cost is in T43's notes. GPU: `T20 acceptance/target_menu_preview_blur.png`, 134 fps with the ring, preview and blur up, 98 draw calls |
| AC26 | Focus pull (T44): opening a radial menu (the target menu, or the comms menu since T46) takes everything except that menu and the target information (the 3D view, the flight HUD, its brackets and radar) slightly out of focus over 0.2 s, so only the menu and the target information are sharp; closing it (a pick with A, or B out of the first level) brings the play view back into focus over 0.2 s; reopening mid-pull reverses from where it is; `FocusPull` unit-tested; with the menu closed the blur is off and costs nothing; `settings.target_menu_blur` 0 turns it off | A | **Met.** `test_focus_pull` (5: 0.2 s each way, a reversal from where it is), `test_target_menu` (the pull on real time while paused, hidden and not processing at rest, the setting at 0) |
| AC27 | Start screen (T45): only the options list shows (no pad diagram, no right panel): New game, Load game (shown disabled; D-pad focus and the mouse skip it), Free flight, Settings, Quit; New game lists the catalogue's missions and then the sandbox scenes, the highlighted entry's briefing or description under the list; Free flight works as before (encounters on or off); Settings opens the groups Gameplay, Controls, Camera & HUD, Video and Audio, Controls holding the profile and rebinding screen and the stick and mouse settings; every schema entry shown in the menu falls in one group (test); the pause menu reads Resume, Restart, Settings, Quit to menu, keeps its pad diagram and objectives, and its Settings opens the same groups; pad-only navigation tested | A | **Met.** `test_front_end` (the five entries, Load game disabled and skipped, New game's missions then scenes with the text under the list), `test_settings_groups` (5: every menu entry in one group), `test_pause_menu` (Resume, Restart, Settings, Quit to menu; the same groups), pad-only. GPU: `T20 acceptance/start_screen.png` |
| AC28 | Radial comms menu (T46): D-pad Right opens the comms menu on T25's radial framework, as big as the target menu and vertically centred at the same side, with T44's focus pull, and pauses the game while open as the target menu does; the right stick points at an entry, A confirms, B goes back a page and closes it from the first; nothing it was pressed for fires, steers or targets when the game resumes; a profile saved before M5 still loads with `comms_menu` filled in | A | **Met.** `test_comms_menu` (9), `test_comms_menu_input` (13: opens and pauses, the stick and A send each order, B, D-pad Right, nothing held fires on close, Start to the pause menu), `test_input_adapter`, `test_control_profile_store`. GPU: `T20 acceptance/comms_ring.png`, 145 fps, 82 draw calls |
| AC18 | (H) The maintainer plays it: menus feel right on the pad, the mission's pacing and lines, the cinematic, the civilian ships' look, the new guns, impacts and engines by ear; the pause backdrop's path and speed, the radial target and comms menus, the start screen and the settings groups, the target preview's readability at 1080 and 4K, the focus pull's feel, and the pause and resume of the radial menus mid-fight | H | **Open: the maintainer's.** The checklist is `docs/playtest.md`, "M5 acceptance checklist" |

## Working rules for M5

- **Tracks.** The maintainer allowed parallel agents for M5 (Q10), so four tracks can run at the same time: A (flow and front end), B (missions), C (civilian ships and
  encounters), D (sound). Inside a track the order holds. Track C's reference and generator tasks (T11-T15) are Python and run beside
  anything; the Godot tasks of every track share one machine, so they follow the locks below. If work has to go one task at
  a time, the order is T01, T02, T05, T06, T08, T09, T07, T10, T03, T04, T11, T23, T12-T15, T22, T26, T27, T21, T16, T28, T17,
  T18, T19, then (after Q34 to Q43) T29, T30, T31-T38 in number order, T25, T42, T45, T43, T44, T46, T20. T42 and
  T45 do not wait for T25 and can run beside it; T43, T44 and T46 build on T25's radial menu.
- **One working copy.** Since 2026-11-08 all M5 work happens in the main checkout on branch `m5` (the `.claude/worktrees/m5`
  worktree, used while M4 held the main checkout, was removed once M4 merged); no task branches, no worktrees per agent (the
  maintainer's rule from M4). Parallel agents keep to their task's files.
- **Locks.** Every Godot run in the `m5` worktree goes through `flock /tmp/m5-godot.lock <command>` (one Godot process at a
  time on the shared `.godot/` import cache). Every `git add` + `git commit` goes through `flock /tmp/m5-git.lock`, and an
  agent stages only the paths it changed (never `git add -A`). GPU checks take `flock /tmp/gpu.lock` as well. M4's
  benchmark runs take `/tmp/m5-godot.lock` too (2026-11-02, from the M4 session), so a Godot run may wait up to about 10
  minutes; never kill or bypass the lock. Other CPU-heavy work (asset builds, STL renders, long Python runs) takes the same
  lock so M4's numbers stay clean.
- **Screenshots (Q43):** every screenshot or captured frame goes to `references/screenshots/<a folder named for the
  request>/` in the main checkout, never `/tmp` or `reports/`.
- **Performance tasks (T31 to T36):** measure before and after on an idle machine (`scripts/bench_quick.sh`, `bench battle
  1000`), keep results identical (parity fixtures, 1 and 6 threads, threaded and delayed), and run the whole suite or let CI
  run it before marking the task done (M4's lesson: focused runs missed full-suite failures).
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
| T03 | A | Settings menu and audio buses | T02 | Sonnet | Schema-driven screen | done |
| T04 | A | Controls menu | T02 | Sonnet | Wraps the existing profile API | done |
| T05 | B | Mission core: runner, script API, triggers, objectives, console | T01 | Opus | The framework M8 stands on; coroutine skipping is subtle | done |
| T24 | A | Console command list in `info.md` and its guard test (`CLAUDE.md` rule of 2026-11-03; numbered last because it was added during the build) | T01, T02, T05 | Sonnet | A doc and one test | done |
| T06 | B | Dialog, subtitles and the comms panel | T05 | Sonnet | Data and HUD | done |
| T07 | B | Comms menu on D-pad Right | T06 | Sonnet | Input routing with clear rules | done |
| T08 | B | `CINEMATIC` camera and locked controls | T05 | Opus | Rebase-safe camera paths | done |
| T09 | B | Debrief | T05, T02 | Sonnet | Model and screen | done |
| T10 | B | Mission: Buoy defence with a cinematic intro | T06, T07, T08, T09 | Opus | Pacing, writing and the first real use of the API | done |
| T11 | C | Civilian references: measurements and descriptions | - | Opus | Reading shapes off renders; sizes from Q8 | done |
| T23 | C | Fidelity check: silhouettes and size against the STL, `refview` compare (Q18; numbered last because it was added during the build) | T11 | Sonnet | A small measuring tool that every civilian generator must pass | done |
| T12 | C | `saturn_family` generator (five variants, Q16) | T11, T23 | Opus | Large shared part library | done |
| T13 | C | `skylark_transport` generator | T11, T23 | Opus | Geometry | done |
| T14 | C | `narn_transport` generator and the `narn` style | T11, T23 | Opus | Geometry and a new style | done |
| T15 | C | `centauri_brezebel` generator and the `centauri` style | T11, T23 | Opus | Geometry and a new style | done |
| T22 | C | Brakiri Bokmai: references, generator with removable pods, the `brakiri` style (placed here in the order; numbered last because it was added during the build, Q17) | T11, T23 | Opus | A new reference read end to end, modular cargo, a new style | done |
| T26 | - | Merge `main` (M4 through T22, the native core) into `m5` (Q27): the conflicts, M5's splat code off, engine voices on M4's frame passes, the focused suites green | - | Opus | Every later C task builds on the core; a two-milestone merge | done |
| T27 | C | The civilian generators on the textured-mesh pipeline: `core/civilian.py` and the five generators write M4's textured `.glb` (UV atlas, colour, normal, roughness and metal, emissive) from show-reference schemes instead of splats; fidelity (AC20) re-scored on the mesh | T26 | Opus | Five generators and their tests move from splat levels to mesh levels; the paint is a look call | done |
| T21 | C | Defensive turrets in the native core (Q28): mounts, aim, the fire gate and the attacker memory as weapon rows (placed here in the order; numbered last because it was added after the others had numbers) | T27, T19 | Opus | A native gunner seam under the threading rules, with a balance test | done |
| T16 | C | Civilian ships in the game: data and assembly in GDScript, the big-hull kind, avoidance and tier in the native core | T27, T21 | Opus | Specs for heavy hulls, factions, pools, native AI fixes, GPU check | done |
| T28 | D | Engine voices on the core's rows: the 4 Hz re-rank asks the core for the ships near the listener instead of walking every ship | T26, T16 | Sonnet | A small native query; the re-rank stops growing with ship count | done |
| T17 | C | Free-flight encounters | T16, T02 | Opus | Seeded director under a CPU cap | done |
| T18 | D | New guns and impacts | - | Opus | Synthesis to measured shapes | done |
| T19 | D | Per-thruster engine bursts | T18 | Opus | Voice placement and a voice budget | done |
| T25 | A | Targeting at scale: a target menu and other targeting UX for large battles (Q26; placed before T20; numbered last because it was added after the others had numbers) | T02, T07, the M4 rebase | Opus | UX judgement with a concept stop (H); reads M4's on-read candidate list | done |
| T29 | C | Generated asteroids and a sparse belt (D63, Q38): the `asteroids` generator, `BeltLayout`, `AsteroidBelt` as static rows | T27 | Opus | A new procgen asset and a placement seam M14 builds on | done |
| T30 | B | Mission: Civilian escort with a cinematic intro (D62, Q36 to Q42), replacing Buoy defence and the ring | T29, T16, T17 | Opus | The random civilian, flee-and-resume in the native brains, three waves, writing and pacing | done |
| T31 | - | L1: the flight batch's per-ship gather in native for row-commanded ships | T30 | Opus | The biggest measured lever (about 37 % of the tick at 1 000) | done |
| T32 | - | L2: the hit resolver gets only bolts with live hostile pairs from native; per-hit hash and readout costs | T31 | Opus | 1.41 ms at 1 000; native pair filtering | done |
| T33 | - | L3: the ram resolver's quick wins, then `RamTracker` in native | T32 | Fable (maintainer, 2026-11-11) | 1.20 ms at 1 000; string keys and full passes per tick | done |
| T34 | - | L5: the radar's dot buffers filled natively | T31 | Sonnet | Per-contact GDScript every frame | done |
| T35 | - | L8 and L9: the native allocation pass and the per-event member scans | T33 | Fable (maintainer, 2026-11-11) | Hash maps and Vec churn per sync; hits times members | done |
| T36 | - | L12 and L13: the smaller items and one native constants table with its GUT check | T35 | Sonnet | Many small fixes and a drift guard | done |
| T37 | D | L6 and L7: muzzle flashes and shot sounds culled by range; no audio node per pooled ship walked per frame | T28 | Sonnet | Sound-pass cost at scale | done |
| T38 | - | L14: the shared test steps fixture, collapsed recordings, balance tests out of the default run, CI's Python job and asset cache | T36 | Sonnet | Duplication and CI time; CI must stay green | done |
| T39 | C | Civilian colours as the show shows them, and a sheen on every hull (maintainer, 2026-11-08; added after T38, done before T30) | T27 | controller | Colour read off captures vs lit albedo; the look is (H) | done |
| T40 | C | Civilian panel seams drawn from the show's references instead of the generic brick grid (maintainer, 2026-11-08) | T39, the maintainer's reference captures | controller | Per-ship seam layouts read off images; the look is (H) | done |
| T41 | - | Rock rams by the speed into the rock: a glancing scrape costs its closing speed, not the ship's whole speed (maintainer, 2026-11-08; done before T31) | T29 | controller | A small change to the ram rule for rocks | done |
| T42 | A | Pause backdrop: a slow figure-8 camera around the Starfury behind the pause menu (maintainer, 2026-11-08) | T02, T08 | Sonnet | A camera path that runs while the tree is paused; the look is (H) | done |
| T43 | A | Target preview: a turning green wireframe of the highlighted entity on the side of the screen opposite the radial target menu, with hull bar and distance (maintainer, 2026-11-08) | T25 | Fable (maintainer, 2026-11-11) | Hidden-line wireframe in a small viewport, edges from the mesh, an info panel kept lean | done |
| T44 | A | Focus pull: while the target menu is open only it and the target information are in focus; the play view and HUD blur over 0.2 s and come back over 0.2 s when it closes (maintainer, 2026-11-08, corrected 2026-11-09) | T25 | Sonnet | A short tweened screen blur between the HUD and the menu layers, free when closed | done |
| T45 | A | Start screen and settings groups: an options-only start screen (New game, Load game, Free flight, Settings, Quit), the sandbox scenes under New game, Controls inside Settings, five settings groups (maintainer, 2026-11-09) | T02, T03, T04 | Sonnet | Menu re-plumbing on the built kit; mostly tests | done |
| T46 | A | Radial comms menu: the comms menu moves onto T25's radial framework, with the focus pull, the right stick to point, A to confirm, B to go back (maintainer, 2026-11-09) | T25, T44, T07 | Sonnet | One framework for both menus; the comms routing changes from the D-pad to the stick; it pauses the game | done |
| T47 | - | Radar plot input checks and scratch reuse: the code review's two open radar items (maintainer, 2026-11-12; numbered last because it was added after the others had numbers) | T34 | controller | Two small native fixes found by the code review | done |
| T48 | - | The full code review's three P3 findings (maintainer, 2026-11-12; numbered last because it was added after the others had numbers) | T47 | controller | Small fixes found by the review | done |
| T20 | - | Integration, full suite, docs and acceptance | all | Fable (maintainer, 2026-11-11) | One full run, the GPU check, the (H) list | in progress — awaiting the maintainer's confirmation |

**Progress (2026-11-12).** Every task in the table is `done` except T20, which is `in progress` until the maintainer confirms
the milestone (its notes are at the end of this file). The paragraphs below are the build's history, kept as written.

**Progress (2026-11-03).** Done: T01, T02, T05, T11, T15, T18, T19, T24. In progress:

- Track A and B on this machine. T03, T04, T06 and T09 were cut off mid-build by a usage limit; their unreviewed work is
  committed as found (8e0d13f) and each finishes on top of it. T07, T08, T10, T17, T20 not started.
- Track C on a second machine, Python only: T23 (re-review of its fix rounds), T13 and T14 (small follow-ups), T22
  (maintainer answers in Q22, then the generator) and T12 (fix round to reach 0.90, the Saturn 3 pods exempt by Q23,
  a full review). `docs/handoff-m5-civilians.md` has the state, the open questions and the rules for two
  machines on `m5`. T21 and T16 wait for them.

**Progress (2026-11-07).** `main` merged into `m5` (T26, Q27). The civilian generators are out of the asset registry and
their Python tests skip until T27 moves them onto the textured-mesh pipeline (`main` removed the splat writers they call).
T21, T16 and T28 are re-planned on the native core ("M5 on the native core", below).

**Hand-off (2026-11-08, from the `oscar` session).** Every task is `done` except T25 and T20. The native split in "M5 on
the native core" is built: T21 (turrets in Rust, with the own-hull line-of-fire rule, Q33), T16 (civilian fleeing in the
native brains, the role column, big-hull handling; Q30 shared Saturn engine, Q31 balance, Q32 flank turrets), T28 (engine
voices from the core's rows), T27 (civilians as textured meshes) and T17 (encounters). Open for the maintainer:
- **Q33's blind spot is narrow**: the hull hides only a cone straight behind each Saturn and a little below (the flank
  turrets see past the cargo hull). Keep it, or widen it (narrower flank arcs, or the turrets set closer in)?
- **T25 (targeting at scale)** waits for its concept stop (Q26).
- **T20** needs the main machine: the full suite with `GUT_SLOW=1` (including `test_flight_parity_fight`,
  `test_weapon_rows_battle`, `test_core_threads`, `test_core_snapshot` and `test_turret_balance`, which `oscar` cannot or
  did not run), `run_tests.sh` with its bench smoke run, the GPU checks on the RX 6950 XT (`civilian_showcase`) and the
  encounters part of `docs/playtest.md`.
- **Not yet seen rendered**: the Saturns' flank turrets (windowed runs on `oscar` hung while the display slept). Earlier
  Saturn 4 shots, before the flank turrets, are in the gitignored `references/screenshots/`.
- **(H)**: the nine hulls and their paint, the turrets' look and `turret_fire`, fleeing civilians, the Saturn 8s' slow
  turns, the low Saturn hulls against the harder turrets, the encounters' pacing and the 15 km civilian transponder.
- M4-T37 and the rest of M4 come in by a later merge of `main` (Q27); expect overlap in the native weapon files (Q28).

**Progress (2026-11-08, main machine).** `main` (M4 accepted) merged into `m5` (Q34): nine conflicts, plus the M5 code
that still named T37's removed switches, `SimCore.bolt_rows_enabled` and `NativeBrains.drop`. Assets regenerated. M5's
unit GUT files pass (711), its integration files 336 of 338 in one run (the two failures, the loading screen's timing and
a second `Main` in the pause test, pass alone; the second is fixed). Open: a forced raid in free flight
(`encounters force raid`) leaks two objects and one resource at exit; CI's smoke runs do not cover it, and T30 (jump
arrivals) clears it. The maintainer replaced the demo mission (Q36 to Q42) and added the performance block (Q35): T29 to
T38 below.

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
- **Done (as built, 2026-11-04):** every `SettingsSchema` entry has a `category`; debug and tuning switches carry
  `menu: false` and stay hidden (a test fails on an entry without a known category). The settings page
  (`src/frontend/settings_screen.gd`) is built from the schema through the pure `SettingsMenuModel`: a toggle, slider or
  option list per entry, unsaved rows marked `*`, the right panel shows the entry's description, and Apply, Revert,
  Defaults and Back map to `Settings.save`, `revert` and `reset`. `MenuScreens.settings()` opens it from the pause menu and
  the front end (a test each). `default_bus_layout.tres` holds Master with SFX, UI and Comms; `AudioBuses` and
  `AudioDirector` route menu sounds to UI and radio to Comms and apply `master_volume`, `sfx_volume`, `ui_volume` and
  `comms_volume` live. From the T02 review: the console `pause` is refused while the pause menu is open.
  - **Review.** One fix round (sonnet): tests that both hosts open a `SettingsScreen`. Open (minor):
    `test_changes_drive_the_audio_bus_volume` drives no bus; console `audio.volume` still sets only `sfx_volume`; Revert
    reverts every key, not only the listed ones.

### M5-T04 Controls menu

- **Goal:** AC4 (D57).
- **Files:** `src/frontend/controls_screen.tscn|.gd`, `src/autoload/control_profiles.gd` (only if a call the screen needs is
  missing; keep `ui_*` actions out of `apply`), `tests/integration/test_controls_screen.gd`.
- **Notes:** while waiting for a press to bind, the screen must not let that press also act on the menu. A refusal from
  `bind` shows its errors.
- **Done when:** AC4.
- **Done (as built, 2026-11-04):** `ControlsScreen` in the `MenuFrame`: a profile picker (built-in and saved), the action
  list with its bindings, and add, replace or unbind by pressing a pad button, stick direction, key or mouse button
  (the pure `BindingCapture`; the press is swallowed while waiting, holding B or Esc or 6 s cancels). Save as cleans the
  name and refuses built-in or invalid names with the reason; every refusal from `ControlProfiles` is shown. The pure
  `ControlsModel` feeds the page; the diagram lights the focused action's buttons and the legend follows a rebind and
  back (a test, restored from the T02 review). Only `InputAdapter.ACTIONS` are listed, so the `ui_*` actions survive
  every change the page makes (a test); `control_profiles.gd` is unchanged. B steps back inside the page
  (`MenuScreen.back_step`), with a 0.35 s grace after a bind so the pause action from the same press does not close it.
  Both hosts open it (a test each).
  - **Review.** Approved (sonnet), no fixes needed. Open (minor): the controls tests report orphans because `after_each`
    rebuilds the list before teardown (not a leak); a stick that jumps from rest to full in one event is ignored until it
    returns to rest; one focus assertion checks only "Profile: default"; the success colour is a literal; a mouse click
    cannot cancel a wait.

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
- **Done (as built, 2026-11-03):** `info.md` at the repository root lists the 51 console commands and 32 state providers on `m5`, in
  8 tables by subsystem (console, game flow and controls, flight, rendering and effects, combat, ships and waves, audio,
  missions) with arguments, a one-line purpose and where each exists (`always`, `front end, flight`, `in flight`, `AI ships`,
  `mission`, `route`, `benchmark`), and a legend of the intro for `--console-exec`, `--console-file` and `--console-strict`.
  `tests/integration/test_console_command_list.gd` boots free flight, the mission fixture, the instructor route and the front
  end, reads `ConsoleRegistry.command_names()` and `provider_names()`, and fails when a registered command or provider is
  missing from `info.md`, when a listed one is registered by no booted scene (rows marked `benchmark` are exempt, none
  yet), or when a name is listed twice; 7 tests, all passing. `docs/architecture.md` §6.4 points to the list. A task that
  adds, renames or removes a command now updates `info.md` in the same commit.
  - **Review.** Approved (sonnet), no fixes needed: an independent grep of every `register_command` and
    `register_provider` site matched the 51 commands and 32 providers, and twelve rows checked against their usage
    strings were right. Open: the `benchmark` skip and the Where column are not checked further (after the M4 rebase,
    `bench`, `native` and `perf` arrive marked `benchmark`).

### M5-T06 Dialog, subtitles and the comms panel

- **Goal:** AC6 (D53).
- **Files:** `src/mission/dialog_queue.gd`, `src/mission/dialog_book.gd` (loads and validates the files),
  `data/dialog/speakers.json`, `src/hud/comms_panel.gd` (both views), `tools/procgen/assets/sfx_ui.py` (`radio_open`,
  `radio_close`), `src/mission/mission_api.gd` (`say` for real), `tests/unit/test_dialog_queue.gd`,
  `tests/unit/test_dialog_book.gd`, `tests/integration/test_comms_panel.gd`.
- **Done when:** AC6.
- **Done (as built, 2026-11-04):** lines are data, `{id, speaker, text, voice, hold_s?}`, with speakers in
  `data/dialog/speakers.json` (`{id, name, callsign, faction}`); `DialogBook` loads and validates them and refuses a bad file
  whole, naming the file and entry, which stops the mission starting. A line holds `hold_s` or 2.5 words a second, at least
  2 s. The pure `DialogQueue` plays one line at a time with a 0.4 s gap on sim-time deltas; `m.say(id, interrupt=false)`
  resolves when the line has shown out, an interrupt cuts the line showing (no closing squelch), and skipped or cut lines are
  logged and count as finished for `dialog_finished`. `CommsPanel` is a CanvasLayer at 41 (above the HUD, below the pause
  menu), so subtitles show in cockpit and chase views and with the HUD off; callsigns in the faction colour; `radio_open`
  and `radio_close` (`sfx_ui`, generator version 2) at -6 dB on the Comms bus. `test_dialog_ids` checks every line id and
  speaker a script uses. `dialog` state provider (no new commands). D53 in architecture §18.
  - **Review.** Approved (sonnet), no fixes needed. Open (minor): `CommsLayout.compute` ignores its cockpit argument; the
    panel's `drawn_*` test fields are not marked test-only; `add_speakers`/`add_lines` repeat one validation loop; D53
    could say plainly that a cut line still completes `dialog_finished`.

### M5-T07 Comms menu on D-pad Right

- **Goal:** AC7 (D54).
- **Files:** `project.godot` (`comms_menu`), `data/controls/m1_classic.cfg` (the built-in must stay complete),
  `src/input/input_adapter.gd`, `src/input/ui_command.gd`, `src/hud/comms_menu.gd` (model and view), `src/game/main.gd`
  (wire it to `WingDirector`), `tests/unit/test_comms_menu.gd`, `tests/integration/test_comms_menu_input.gd`.
- **Notes:** add the key binding to the keyboard layout and `docs/architecture.md` §6.1's diagram. A test loads a profile
  file written before the action existed.
- **Done when:** AC7.
- **Done (as built, 2026-11-04):** the `comms_menu` action is D-pad Right and, on the keyboard, Ctrl (every other
  left-hand key was taken; with the menu open Ctrl picks the right-hand entry). The pure `CommsMenu` model and the
  `CommsMenuView` (layer 42, a plate at the left middle, clear of the subtitles and the cockpit roster): up, right, down
  and left pick attack my target, form on me, engage at will and cover me through `WingDirector.give_order` (the call keys
  1 to 4 make; `wing_director.gd` unchanged); a pick closes the menu; B or 4 s of physics time closes it; the pause edge
  or the player's death closes it, and the pause menu freezes its timer. While it is open the adapter swallows assist,
  next weapon, lights and the target button, and a B held through the close does not tap a target. A profile saved before
  M5 gets `comms_menu` filled from the default; one that rolls on D-pad Right keeps its roll and gets Ctrl alone (tests).
  The menu takes pages (`push_page`/`pop_page`); M5 builds no reply page. Provider `comms_menu`; §6.1 and D54 updated.
  - **Review.** Approved (sonnet), no fixes needed. Open (minor): the input test's comment says a hostile is selectable
    but the test asserts slot 0 is refused, so the attack pick's happy path is not run end to end; keys 1 to 4 and the
    mouse wheel still act while the menu is open (D54 promises only the target button is quiet); one weapon assertion is
    skipped when the cannon has no `mode`.

### M5-T08 `CINEMATIC` camera and locked controls

- **Goal:** AC8 (D55).
- **Files:** `src/camera/cinematic_shot.gd` (pure), `src/camera/camera_rig.gd` (the mode, the camera, `mode_name` no longer
  binary), `src/hud/letterbox.gd`, `src/game/main.gd` (the command zeroing), `src/mission/mission_api.gd` (`cinematic`,
  `lock_controls`), `src/autoload/settings_schema.gd` (`camera_default` keeps chase and cockpit only),
  `tests/unit/test_cinematic_shot.gd`, `tests/integration/test_cinematic_camera.gd` (with a forced rebase mid-shot).
- **Done when:** AC8.
- **Done (as built, 2026-11-04):** the pure `CinematicShot` reads a scenario's
  `cinematics: {<id>: {keys: [{t, position, look_at, fov?}]}}`; a point is `{actor, offset?}` (in the actor's frame) or
  `{origin}` (a 64-bit universe offset). Positions follow a Catmull-Rom curve through the key times; the look-at point and
  fov ease. The shot keeps no state between frames and `CameraRig`'s `CinematicCamera` is `top_level` in `world_shiftable`,
  so a rebase mid-shot moves nothing on screen (a test forces one). `CameraRig.Mode.CINEMATIC` comes only with
  `play_shot`; the shot's clock runs on physics ticks and the rig returns to the mode it left; `camera_default` stays
  chase or cockpit. While a shot plays the HUD hides and a `Letterbox` (layer 39) slides in under the subtitles. The pure
  `ControlLock` (`src/input/control_lock.gd`, added to keep `Main` thin) zeroes the player's `FlightCommand` and
  `CombatCommand` while the ship keeps its physics; wing keys and the comms menu wait and an open menu closes. Start or a
  new A press skips a shot; the A that skipped neither fires nor skips the next shot until released. `m.cinematic` resolves
  at the shot's end, on a skip, on `mission skip` or at the mission's end; `m.lock_controls(true)` alone zeroes the
  commands without a camera change. A bad shot stops the mission from starting. The `camera` provider gains `shot` and
  `shot_time_s`. D55 and §18.8 in the architecture.
  - **Review.** One fix round (opus review, sonnet re-review): one held A skipped every chained shot. Open (minor): the
    console `throttle` still pushes during a lock; `camera cockpit` during a shot echoes `cinematic`; a shot naming an
    actor not yet in play parks the camera; no runner-level test of a bad shot; the auto-track latch is not reset by a
    lock. Found on the way: T06's dialog broke two T05 tests (fixed in aee57f2).

### M5-T09 Debrief

- **Goal:** AC9 (D56).
- **Files:** `src/mission/debrief_model.gd` (pure), `src/frontend/debrief_screen.tscn|.gd`, `src/autoload/game.gd` (the
  `DEBRIEF` state and retry), a shots-and-hits counter for the player (from `projectile_fired` and `HitResolver`'s
  results, without touching M4's files), `tests/unit/test_debrief_model.gd`, `tests/integration/test_debrief.gd`.
- **Done when:** AC9 with the test mission.
- **Done (as built, 2026-11-04):** the pure `DebriefModel` holds the result and reason (a failed objective's id becomes
  its text), every objective with its state, sim time, kills and assists, wing losses, shots fired and hit and accuracy;
  `panel()` fills the right panel, `summary()` the console. The pure `MissionTally` counts the player's bolts fired and
  hit and the wing's losses (never the player), fed by the `DebriefRecorder` node from `projectile_fired`,
  `HitResolver.hit_resolved`, `ship_destroyed` and `KillCredit`, with no M4 file touched. On mission end the runner builds
  the report, `Game.end_mission` moves the flow to `DEBRIEF` (missions only), and 3 s of sim time later
  `Game.show_debrief` swaps `Main` for the debrief screen (pausing holds the beat). Retry replays the same scenario,
  encounters and seed through loading (no leaked nodes over repeated retries, a test); Front end returns to the menu; a
  0.7 s input guard stops a fire-button tap from picking Retry. Console `retry`, provider `debrief`. D56 in §18.
  - **Review.** One fix round (sonnet): the player's own death no longer counts as a wing loss (test). Open (minor):
    accuracy is computed in both `DebriefModel` and `MissionTally`; the recorder keys the player by `main.ship` for shots
    and `main.combatant` for losses.

### M5-T10 Mission: Buoy defence with a cinematic intro

*(Superseded 2026-11-08: T30 replaces Buoy defence with Civilian escort and removes the ring, Q36 and Q41. Kept for the
framework pieces it added: `player.velocity`, `mission.closing_lines` and the cinematic fly-past.)*

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
- **Done (as built, 2026-11-04):** `data/scenarios/buoy_defence.json`, `data/missions/buoy_defence.gd` and
  `data/dialog/buoy_defence.json`: five steps (intro, brief, wave_one, wave_two, wrap), 13 original lines, objectives
  protect `NAV ALPHA` and destroy the raiders (primary) and bring Alpha wing home (optional), pools of 7 raiders and 3
  allies. The intro is two shots, `relay` (NAV ALPHA against the star) and `wing` (Alpha wing coasting past a camera
  that holds still in space); Control briefs with the controls held, then hands over. Wave one (three raiders) and wave
  two (four, from another bearing after a warning) jump in about 9.5 km out and are sent at the buoy. The ring comes from
  the pure `BuoyRing` through the scenario's `buoy_rings[]`: 16 buoys on a 20 000 km ring, NAV ALPHA among them.
  `NavBuoy.BROADCAST_RANGE_M` is 10 000 km for every buoy (M3 Q21 had 1 000 km; §18.9). With those numbers the
  two-buoy rule holds on the ring and within about 4 900 km of it outward beside a buoy (6 000 km out of the plane and
  inward), tested at the real edges; the radar from NAV ALPHA shows NAV BRAVO and NAV PAPA on its rim (test). New in the
  framework: a scenario's `player.velocity` (first spawn only) and `mission.closing_lines` (a last line for a loss that
  ends the mission before a step can speak; the debrief waits for it). Missions start from the menu or `play`;
  `--scenario=buoy_defence` is refused. By ruling, no far-buoy splat hiding (splats leave with M4); the far buoys' draw
  and scan cost is checked after the rebase (T20). `docs/playtest.md` says how to play it. Frames of the intro are in
  `reports/m5-t10/` for the maintainer (H).
  - **Review.** Approved (opus), no fixes needed. Open (minor): a closing line ignores the skip flag; the optional `home`
    failure is untested; the raider names live in both the script and the objective; `TriggerDestroyed`'s header is long
    and mission-specific; closing lines are keyed by free-text reasons; the debug overlay (on by default) draws over
    cinematics.

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
  authored frame (x to starboard, y up, z aft from the nose), and a built asset from `assets/generated/<id>/`. The
  verdict (Q18, as changed on 2026-11-03) scores the asset's fallback mesh `<id>.obj` against the STL: top, side and front
  silhouettes on one grid (a pixel at most 0.5 % of the length), a small best-fit shift (at most 2 % of the length,
  reported), each view's intersection over union and the length, width and height ratios. A second check holds the LOD0
  splats (with `manifest.centroid_offset` and the GDGS flip undone) to their own mesh: per view, coverage and banded
  precision within one LOD0 spacing, each at least 0.95. Crops by z range, set separately for the model and the asset,
  score one part at a time. It writes overlays and `fidelity.json` to `reports/refs/<ship>/compare/`, prints a verdict
  per view, and exits 1 when either check fails (2 on bad input). Optional extra parts (the Bokmai's pods at their
  `cargo_pods[]` mounts) are drawn with the hull.
- **Tests:** synthetic STLs and splat sets: identical shapes score 1.0; a known shift, scale or missing part gives the
  known overlap; crops; the exit code at the thresholds; skipped without Pillow, like `test_refview.py`.
- **Done when:** the tests pass and the tool has been run on every civilian asset already built, with the scores in
  the report (a generator under the bar is that generator's fix, not this task's).
- **Done (as built, 2026-11-03):** `tools/refview/compare.py` (venv, run with `-I`), 69 tests in
  `tools/procgen/tests/test_refview_compare.py` (skipped without Pillow; two read the built raider when it exists).
  - **Geometry verdict (Q18):** the STL in refview's frame against the asset's fallback mesh, on a grid of 0.25 % of the
    (part's) length; a best-fit shift of up to 2 % per axis, reported with the unshifted scores; IoU at least 0.90 per
    view and each dimension within 10 %. `--model-offset` for whole ships whose origin is not the model's box centre
    (with a hint from a wider silhouette search), `--model-zrange` and `--asset-zrange` to score one part (cut exactly at
    the planes, each side starting at z = 0, the asset part aligned on the model part's box centre), `--model-scale`
    for Q20's scaled pod group, `--part` for its own folder.
  - **Splat check:** the LOD0 splats (each the outline of its Gaussian at 0.75 sigma) against their own mesh, no shift,
    on a grid of a third of the LOD0 spacing so the band is exactly three pixels and the numbers depend on the sampling
    alone (not on the length, the crop or `--pixel-frac`). Coverage of the mesh silhouette and precision within the
    mesh silhouette grown by one spacing, each at least 0.95. The spacing is `lods[0].spacing_m`, and a declared spacing
    more than 10 % off the one the splat scales imply fails the check.
  - **Pods:** `--pods-from-hardpoints` or `--pod-at` draw `<id>_pod.obj` and `<id>_pod.ply` at each mount (the pod's +y
    on `up`, its -z on an optional `forward`).
  - **Outputs:** `overlay_<view>.png` (STL against mesh), `splats_<view>.png` (mesh against splats, splats beyond the
    band in red), `fidelity.json`. Exit 0 when both pass, 1 when either fails, 2 on bad input or an output folder that
    cannot be written.
  - **Scores on 2026-11-03 (whole ships):** Narn transport 0.991 / 0.985 / 0.974, Skylark 0.979 / 0.976 / 0.956,
    Brezebel 0.966 / 0.984 / 0.970, Saturn 4 transport 0.949 / 0.933 / 0.901; splat coverage 0.974 to 1.000 and
    precision 1.000 on all four. The Saturn parts and the per-generator rows are T12 to T14's
    (`docs/assets-civilian.md`, Fidelity).
  - **Review.** Four fix rounds. 1 (86888f9): the verdict moved from the splats to the mesh (12b2165), because splats
    under-read a perfect copy of the Saturn 4 by 5 to 8 %. 2 (d2a2adc): coverage and banded precision replaced 0.85 IoU
    (7ab9e05). 3 (7bcd755), after the scoped re-review of 1 and 2: the splat check got its own spacing grid (on the
    length-based grid a lead ship's side coverage read 0.939 to 0.979 depending on `--pixel-frac`, and the band rounded
    up to 1.65 spacings), `lods[0].spacing_m` first with the mismatch check, an unwritable output exits 2, the score
    table gained a splat column, tests for no shift, a precision-only failure and the built raider at the 0.95 bar.
    4 (8d276ac): Saturn rows of three other tables that round 3 had broken were restored, a length test that could not
    fail was made real, the grid guard checks area. Approved after round 4.

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
- **Done (as built, 2026-11-04):** `saturn_family` (`tools/procgen/assets/saturn_family.py`, parts in
  `tools/procgen/parts/saturn.py`, style `tools/procgen/styles/ea_civilian.py`), five ids from one lead ship plus cargo
  (Q16): `saturn_3_freighter` 96.8 m, `saturn_4_transport` and `saturn_4_tanker` 158.48 m, `saturn_8_transport` and
  `saturn_8_tanker` 258.48 m.
  - **Shape (fix round, off the Saturn 4 and tanker models' sections):** the lead ship traced member by member: an elliptic
    disc with its fins, neck box, keel block and 2.8 m corner wedges; the antenna on a strut, a bar and a plate; the
    forward frame (upper tubes, upper beams forking at z 37, a centre beam forking, a lower bar into the truss drum's
    neck), the crossed plates, side boxes and plates; the aft frame as its mirror about z 92.1, landing in the first
    dome's brackets; the drum frame's posts as one 3.2 m plate and a spoke band a side. Transport pods with the end band's
    outline (7.74 / 17.22 / 4.73 m) and the body 0.8 m in; the tank sections' A-frames at the model's two stations. The
    Saturn 3 keeps T11's wider pod stack, its slim engine and the truss through the stack (Q20, Q23).
  - **Outputs:** LOD0 74 894 / 136 626 / 74 852 / 218 216 / 127 220 splats (Saturn 3, 4 transport, 4 tanker, 8
    transport, 8 tanker), LOD1-3 at 25 / 6 / 1.5 %, chunks from LOD1, the fallback mesh and the painted mesh
    `<id>_mesh.glb` (41 518 to 54 998 triangles; ships are meshes from 2026-11-04), the EA turret (2 363 splats) with its
    own mesh.
  - **Hardpoints:** two pods (mains at the bell, retros on the disc's rim), the centre of mass on the spine axis, 11 RCS
    ports (the top drum's front port dropped: it sat in the crossed plates), collision over at least 97 % of the splats,
    turrets per Q19 (`dorsal_fwd` and `dorsal_aft` or `dorsal_mid`; the Saturn 3 `dorsal_fwd` only), chunks with joints on
    their chunks.
  - **Fidelity (Q18), mesh against the STL, part by part with crops that match on both sides:** every lead ship 0.960 /
    0.919 / 0.916 (the Saturn 3's, z 0-41.5, 0.964 / 0.905 / 0.946); transport sections lowest view 0.917 to 0.923; tank
    sections 0.916 to 0.938; the whole Saturn 4 transport 0.958 / 0.966 / 0.931; lengths, widths and heights within 3.2 %.
    The Saturn 3's pod group reads 0.768 / 0.644 / 0.927, the expected exemption (Q23). Splats cover at least 0.957 of
    their mesh, precision 1.000. All rows in `docs/assets-civilian.md`.
  - **Tests:** 165 Python tests (each variant's contract, mirror symmetry of every splat level and of the drawn mesh, the
    fallback and chunk meshes hold every piece, the painted mesh is the fallback mesh, the frames' lower bars meet the
    truss drum and the aft frame lands in the brackets, collision, turrets, determinism); `test_splat_import.gd` 17/17.
  - **Review.** Built in eab08b1 and c80eace. Fix round (ae98f72, 45ecd75): the lead ship traced member by member, the
    pod bands, the tank A-frames, crops and Fidelity rows. Full review: the aft frame's mirror plane and floating lower
    bar, an RCS port inside a plate, two crops not matching, a mesh off mirror (the Saturn 3's top pod rail), docs (90bcd8b);
    a re-check found the aft frame's dome end short of the brackets and the pod joints between pods (cb0a565). Approved.
    Open (H): the Saturn 3's wider pod stack and added engine (Q20, Q23), soft close-ups at 0.48 to 0.55 m splat spacing
    until the meshes are textured (M4-T30a).

### M5-T13 `skylark_transport` generator

- **Goal:** AC12 for the Skylark.
- **Files:** `tools/procgen/assets/skylark_transport.py`, parts it needs, `tools/procgen/tests/test_skylark_transport.py`.
- **Done when:** AC12 and AC20 for the Skylark.
- **Done (as built, 2026-11-03):** `skylark_transport` (`tools/procgen/assets/skylark_transport.py`, parts in
  `tools/procgen/parts/skylark.py`, the `ea_civilian` style with the Skylark's sand paint).
  - **Shape:** the EA "Delta Gamma 9" type, 60.0 x 40.2 x 10.2 m. A capsule with nose vanes, a glazed bridge plate, two
    red-orange bands and belly fins; spine vane rings and a collar; banded side tanks with dumbbells; the faceted body
    with corner fins, the dorsal fin and the centre engine; nacelles on their measured axis (x ±13.03, y -0.26) with two
    pods, ribbed intakes and bells, and forked claws on short pylons.
  - **Outputs:** LOD0 60 924 splats at 0.26 m (budget 48 000 to 72 000; capsule 23 018, body 15 014, each nacelle
    11 446), LOD1-3 15 176 / 3 798 / 962 with lighting records, fallback mesh, four chunks from LOD1 (`capsule`,
    `body`, `nacelle_l`, `nacelle_r`).
  - **Hardpoints:** two pods on the nacelles' axis (mains at the bells, retros at the intakes), the centre of mass on
    that thrust line, 12 RCS ports, 44 collision primitives that hold every LOD0 splat centre.
  - **Turret (Q19):** one, `dorsal` at (0, 2.766, 37.5), on the body's ridge as low as the hull under its 2.4 m base
    (no pedestal); the EA turret at two thirds, 2 372 splats at 0.08 m, `barrel_m` 3.0.
  - **Fidelity (Q18), mesh against the STL:** 0.979 / 0.980 / 0.956; length, width, height 1.001 / 1.000 / 0.998; the
    splats cover at least 0.983 of their mesh (side), precision 1.000.
  - **Tests:** 34 Python tests (every level mirror-symmetric, the fallback and chunk meshes hold every piece, every splat
    inside a collision primitive, the turret's base meets the hull round its rim, the LOD box rule of T14);
    `test_splat_import.gd` 16/16.
  - **Review.** Built and approved in 47d5627. Follow-up (1c20bf3, the hand-off's list): the turret off its pedestal,
    full collision cover (a box for the nose neck and one for the engine's vane ring), the fallback-mesh test, 99.9 %
    coverage, symmetry to LOD3, the mesh Fidelity row, the budget row's 0.26 m. Two fix rounds: the base floated up
    to 0.10 m over the ridge's fall aft and outboard, so the seat is the lowest hull height under the rim (df298a9), sized
    from the turret model itself (a6074c6). Approved. Open (H): the sand paint and the soft close-ups at 0.26 m.

### M5-T14 `narn_transport` generator and the `narn` style

- **Goal:** AC12 for the Narn transport.
- **Files:** `tools/procgen/assets/narn_transport.py`, `tools/procgen/styles/narn.py`, parts it needs,
  `tools/procgen/tests/test_narn_transport.py`.
- **Done when:** AC12 and AC20 for the Narn transport.
- **Done (as built, 2026-11-03):** `narn_transport` (`tools/procgen/assets/narn_transport.py`, parts in
  `tools/procgen/parts/narn.py`, style `tools/procgen/styles/narn.py`).
  - **Shape:** 70.0 x 46.0 x 18.0 m. The crescent (thinning from 7.8 m on the centre line to a beveled rim, thinner
    prongs, a step behind the notch), the cockpit with a framed canopy and windscreen block, the dorsal block and bar,
    fins, the flank towers with vanes, slotted crowns and the main nozzles, the cargo box with its wedge front, aft cut,
    green panels, hazard corners and vent grilles.
  - **Outputs:** LOD0 77 224 splats at 0.31 m (`cockpit` 15 718, `wing_l` and `wing_r` 13 526 each, `box` 34 454),
    LOD1-3 19 292 / 4 872 / 1 222 with lighting records, fallback mesh, four chunks from LOD1.
  - **Hardpoints:** two pods (mains in the towers' aft faces, retros at their fronts) on the thrust line 5 m above the
    centre plane, 14 RCS ports, 19 collision primitives (99.9 % of the LOD0 centres), cockpit camera, chase anchor,
    running lights.
  - **Turrets (Q19):** `tower_l` and `tower_r` on the slotted crowns, `arc_deg` 220, `barrel_m` 3.0; the Narn turret
    model (six-sided base, wedge housing, red band, twin barrels) 1 894 splats on its own 0.65 m panel grid.
  - **Colours** as confirmed (Q19): hull #2E4A3B, panel lines #1E2E25, cargo panels #4E7552, the red band; the green is
    not lifted, T16's GPU check decides that with the maintainer. (Superseded 2026-11-04: lifted to #3A5A48, no
    painted grid; `docs/assets-civilian.md`, "Colour round".)
  - **Fidelity (Q18), mesh against the STL:** 0.991 / 0.985 / 0.974; length, width, height 1.000 / 1.000 / 0.997; the
    splats cover at least 0.976 of their mesh (side), precision 1.000.
  - **LOD box rule (follow-up):** `test_splat_import.gd` checks a coarse level's box against LOD0's per side: past it by
    at most max(0.3 m, 0.25 of its spacing), short of it by 0.3 m, or for a hull whose box is 30 m or more across by
    1.25 of its spacing (worst today: the Saturn 4 transport's LOD3 1.02 spacings short). The Narn and Skylark tests
    use the same rule.
  - **Tests:** 35 Python tests; `test_splat_import.gd` 16/16.
  - **Review.** Built in 48fd358 and approved after a fix round (d4c66a9: the confirmed colours unlifted, the LOD box
    tolerance for big hulls only, systematic coarse levels, 99.9 % collision coverage). Follow-up (c742c52, the
    hand-off's list): the asymmetric box rule keyed on a 30 m box, the crescent's thickness re-measured on the STL, the
    mesh Fidelity row. One fix round (3e0d3ae): the STL's bevel is about 1.9 m wide (1.9 m thick where it starts, 2.2 m
    3 m in), the rule's wording. Approved. Open (H): the dark green on the GPU, which way is up.

### M5-T15 `centauri_brezebel` generator and the `centauri` style

- **Goal:** AC12 for the Brezebel.
- **Files:** `tools/procgen/assets/centauri_brezebel.py`, `tools/procgen/styles/centauri.py`, parts it needs,
  `tools/procgen/tests/test_centauri_brezebel.py`.
- **Done when:** AC12 and AC20 for the Brezebel.
- **Done (as built, 2026-11-02):** `centauri_brezebel` (`tools/procgen/assets/centauri_brezebel.py`, parts in
  `tools/procgen/parts/centauri.py`, style `tools/procgen/styles/centauri.py`).
  - **Shape:** one elliptic lens hull measured off the STL. Every section is an ellipse; the quarter-ellipse bow is
    39.1 m wide at z 17 with a pale rim band, and the arms taper to flat tip faces holding the main nozzles at z 60.
    Around it: the engine bay with twelve RCS blocks and the main engine, a dorsal fitting with five windows and the
    turret ring, arm fairings, and hooked tip fins (1.45 to 0.47 m thick, leaning 12.7 degrees, gold caps, lights on
    the upper hooks).
  - **Outputs:** 67 230 LOD0 splats at 0.26 m (budget 55 000 to 85 000), LOD1-3 16 774 / 4 198 / 1 060 with lighting
    records, fallback mesh and depth proxy, and three chunks from LOD1 (`bow`, `arm_l`, `arm_r`).
  - **Hardpoints:** two pods (mains in the arm tips; retros firing forward from the bow's rim on the fairings' axis,
    z 5.7) with the thrust line and centre of mass on the hull's centre plane (y -0.105), 16 RCS ports and 30
    collision boxes that cover every LOD0 splat.
  - **Turret (Q19):** one, `dorsal` at (0, 4.3, 7.0). The Centauri turret model has 2 080 splats and `barrel_m` 2.6.
  - **Colours** are painted as written (Q19). The panel lines are #2B2257 on #4C3C8E, and #FFB8E0 glow is kept for
    T16.
  - **Fidelity (Q18), mesh against the STL:** top 0.966, side 0.984, front 0.970; length 1.000, width 1.000, height
    0.999. The STL's fins are 0.43 m asymmetric, so the tool shifts the ship 0.15 m to port. The LOD0 splats against
    their mesh read 0.978, 0.960 and 0.951 (bar 0.85).
  - **Tests:** 40 Python tests and the Godot import test (16/16) pass.
  - **Docs:** both Brezebel sections carry the corrected turret row and the STL-proven numbers (fin thickness and lean,
    arm tip, fairings, nozzle x).
  - **Review.** Approved after one fix round (sonnet): the two splat-compensation nudges were reverted (fins at their
    measured thickness, the back wall meets the hull); the retros fire forward from where the fairing's line leaves the
    bow's skin, (±14.6, centre plane, 5.7), so their plume shows and they add no pitch torque (test); the rail has its own
    collision box (30 boxes, every splat covered); a test checks that the fallback mesh holds every piece. Mesh against
    the STL 0.966 / 0.984 / 0.970, length, width and height 1.000 / 1.000 / 0.999. Open (H): the dark violet and its
    panel lines on the GPU, the retro plume leaving bare skin in the rim band.

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
- **Done (as built, 2026-11-03):** `brakiri_bokmai` (`tools/procgen/assets/brakiri_bokmai.py`, parts in
  `tools/procgen/parts/brakiri.py`, style `tools/procgen/styles/brakiri.py`), through the new shared civilian pipeline
  `tools/procgen/core/civilian.py` (pieces, mirroring, sampling with burial, paint, chunk sources, the GDGS flip, level
  and model writers). The four older generators keep their copies: moving them was not cheap enough to do here.
  - **Maintainer (2026-11-03), on the review sheet** (`reports/refs/brakiri_bokmai/sheet/`): the two turrets as drawn,
    `flank_l` and `flank_r` at (±2.04, 8.45, 6.58) in the middle of each inset's full-height step, up (±1, 0, 0), a
    1.6 m turning ring (the step is only 1.6 m long, so the planned 2.4 m base did not fit), a lens housing 2.0 x 0.9 x
    2.4 m, muzzles 3.0 m ahead; the colour scheme as written (frame #5A6B59, lines #3A4538, pods #ABAE9A with #868A78
    lines, yellow #D8B840, cups #2E3530, domes #F2EDC4, glow #FFF0B0, small #E8F0DC windows); the bolts #7CFF4F.
  - **Shape:** 79.95 x 31.60 x 30.88 m. The bow blade lofted up through 24 measured horizontal sections (concave rear),
    the flank insets as dark panels, a window row, the spine through 11 sections to the fork, the keel web into the
    arms, swept arms and fork struts, posts, one loft per engine (joint, neck with its yellow band, nacelle, cup),
    engine domes, chamfered fins with yellow tops and insets, the spindle. Every number is a rounded station measured
    off the STL's sections.
  - **Outputs:** the hull without pods, LOD0 41 924 at 0.30 m (budget 32 000 to 49 000), LOD1-3 10 498 / 2 622 / 644,
    five chunks from LOD1 (`bow`, `arm_l`, `arm_r`, `engine_l`, `engine_r`; the pods are left out). The pod model in its
    own frame (origin at the mount), LOD0-3 at the hull's spacings, 11 644 splats at LOD0, a manifest `pod` entry with
    per-level files, counts and offsets (GDGS centres each import on its mean), mass 120 000 kg, size and a collision
    box. Hull and three pods 76 856 (the plan said 75 000); all nine hulls at LOD0 with the hero, the sky and five buoys
    1 915 914, 95.8 % of `splat_budget`. The Brakiri turret 1 602 splats.
  - **Hardpoints:** two pods on the nacelle axis (mains just behind the domes, retros on the nacelles' shoulders, both
    clear of the hull), the centre of mass on that thrust line, 9 RCS ports, 39 collision primitives that hold every
    LOD0 splat, `cargo_pods[]` (`pod_fwd`, `pod_mid`, `pod_aft` with `up` and `forward`), two flank turrets.
  - **Fidelity (Q18), mesh with three pods against the STL:** 0.966 / 0.977 / 0.954; length, width, height 0.999 each;
    the splats cover at least 0.972 of their mesh (side), precision 1.000. The arms, struts and fins are sampled at the
    hull's spacing (no thickening).
  - **Tests:** 42 Python tests (budgets, every hull and pod level mirror-symmetric, no hull splats in the pod volumes
    outside the 1.48 m bore, pods at their mounts and clear of the frame, nozzles clear of the hull, turrets, collision,
    the fallback mesh holds every piece, determinism, the shared helper); `test_splat_import.gd` learns the pod
    (listed PLYs, counts, each level's box at its offset about the mount), 17/17.
  - **Review.** Two fix rounds. 1 (a9b0bde): the nozzles were inside the nacelle and the dome, the pod had one offset
    for four levels, the Godot pod check ignored the offset, the budget totals, the pod's collision box and panel grid,
    the bow chunk's joint in a pod's space, the inset described at a coarser rounding. 2 (2515fe2): the inset built from
    its two strips, the lamp and joint pinned by tests, docs as built. Approved. Open (H): the turrets standing out of
    the insets (painted, not recessed), the olive frame against the pale pods on the GPU (T16).

### M5-T26 Merge `main` into `m5` (Q27)

- **Goal:** `m5` on M4's native core (`main` at `095c73d`, M4 through T22 and T41), so the C-track tasks build on it.
- **Files:** the 14 conflicted files (architecture §17 before §18, the roadmap, `info.md`, `project.godot`'s autoloads,
  `run_tests.sh`'s provider lists, `settings_schema.gd` and its test, `audio_director.gd`, `main.gd`, the procgen README
  and registry, `glb.py`, third-party), M5's splat references (`test_mission_runner`, `test_settings_menu_model`), the
  menu metadata (`category`, `label`, `step`, `menu`) for every setting M4 added, the civilian generators out of the
  asset registry with their Python tests skipped for T27.
- **Notes:** a merge, not a rebase (Q27). M5's engine voices (T19) take the ships' `shot_fired` signal and must still be
  granted for the flight batch's ships, which no longer tick themselves (M4-T35, T36). On `oscar` (Q29) only the focused
  suites run: no `GUT_SLOW`, no bench.
- **Done when:** the Python suite and the GUT files M5 touched, `test_console_command_list`, `test_settings_schema`,
  `test_engine_audio`, `test_mission_runner` and the M4 parity files the merge touched pass on the native library; the
  merge is pushed.
- **Done (as built, 2026-11-07, on `oscar`):**
  - **Merge.** `main` at `095c73d` into `m5`; 14 conflicts. §17 sits before §18 in the architecture; the roadmap keeps M4's
    rows and M5's own; `info.md` keeps M5's layout (its guard test parses it) with M4's commands and providers added and the
    splat ones (`fallback`, `relight`, `lod`) gone, plus `dialog` (T06's provider, never listed); `project.godot` has both
    `Game` and `FramePassesNode`; `run_tests.sh` keeps M5's smoke runs and M4's bench smoke run, `game` in M4's provider
    lists. `glb.py` is M4's (a superset of M5's copy). Pillow stays for `tools/refview` only.
  - **Settings.** The splat settings went with M4; every setting M4 added has menu metadata: anti-aliasing, upscaler,
    render resolution, FSR sharpness and ambient light in the Graphics menu, the `perf_*`, AI, tier and step settings
    console-only. The menu's task-id stripper also takes `(M4-T30a, live)` forms.
  - **Code.** `JumpArrival` uses `LightRig` (M4's name for `SplatLightRig`). Engine voices take `shot_fired` (both bolt
    paths) with M5's per-shot gain. Two tests lost their splat references: the mission runner's arrival test counts
    `Ship` nodes and attaches the shared far-dot multimesh first (M4-T11 makes it on first use); the menu-model test groups
    thousands on `engine_voice_cap`.
  - **Civilians off until T27.** `main` removed `core/ply.py`, `core/lighting.py` and `core/frames.py`, which the civilian
    pipeline calls, so the five generators are out of the asset registry and their five Python test files raise
    `SkipTest` naming T27. `test_splat_import.gd` went with `main`.
  - **Assets.** `assets/generated/` rebuilt with `main`'s generators (the textured Starfury, raider, buoy, station, capitals
    and the star-point sky).
  - **Tests (oscar, Q29: no bench, no `GUT_SLOW`).** `check_scripts`: 572 scripts compile. GUT, every file M5 added or
    changed (including T03, T04 and T06 to T10 from the main machine, merged in the same commit) plus `test_main_scene`,
    `test_sim_core` and `test_flight_model`: 54 files, 920 passing, 0 failing. The Python suite passes with the six
    civilian and refview test files skipped for T27. `run_tests.sh` was not run here (its bench smoke run is a many-ship
    scenario, Q29); the full run is T20's.
  - **History.** One merge commit whose parents are the main machine's `m5` (`06a1f63`) and `main` (`095c73d`); the
    numbers this plan first used (T25, Q24 to Q26) were taken by the main machine's own plan, so the merge is T26, the
    civilian move T27, the engine-voice query T28 and the answers Q27 to Q29.

### M5-T27 The civilian generators on the textured-mesh pipeline

- **Goal:** AC12 and AC20 on meshes: the nine hulls (and the Bokmai pod and every turret model) written as M4's textured
  `.glb` with LODs built at import, chunks as meshes, `hardpoints.json` and the collision primitives unchanged.
- **Files:** `tools/procgen/core/civilian.py` (the splat writer, levels and `frames`/`lighting` calls replaced by
  `core/textured_mesh.py`'s `write_textured_mesh`), the five generators, `parts/turret.py`, the styles (paint, markings and
  wear from the show references, one texture pack per faction: EA civilian, Narn, Centauri, Brakiri), the five Python test
  files (their splat counts and LOD box rules become the mesh contract's checks), the asset registry, the README,
  `docs/assets-civilian.md`, a GUT import check for the nine hulls.
- **Notes:** the geometry (parts, pieces, burial solids) stays; only the output changes. `core/paint_mesh.py` (M5's copy of
  M4-T27) goes once nothing uses it. Fidelity is re-scored on the textured mesh. The look is (H).
- **Done when:** AC12 and AC20 on the mesh path; the five generators back in the registry; no splat code left in `tools/`.
- **Done (as built, 2026-11-07, on `oscar`; started by a sub-agent, finished by the controller after the agent hit a rate
  limit):**
  - **Output.** `core/civilian.py`'s `write_hull` and `write_model` write each hull, the Bokmai pod and every turret as M4's
    textured `.glb` with its four maps; chunks are cuts of the hull's mesh; the `.obj` files stay because the game's
    contract (hardpoints' chunk `obj`) reads them. No splat code is left in `tools/` (`test_mesh_only` passes; `paint_mesh.py`
    went with T26). The five generators are back in the asset registry.
  - **Paint.** One texture pack per faction style (`ea_civilian`, `narn`, `centauri`, `brakiri`): plating, seams, wear,
    glowing windows and throats, scaled to each hull's texel; the schemes and the show images they were read from are in
    `docs/design-references.md`. The look is (H).
  - **Fidelity (AC20).** `tools/refview` compare now scores the `.glb` and its splat coverage check is gone; its tests are
    rebuilt from meshes. Every ship and part is re-scored in `docs/assets-civilian.md`: each view's IoU is 0.905 or more
    (lowest: the Saturn 3 lead ship's side view, 0.905) and every size within 10 %, except the Saturn 3 pod group, which Q23
    exempts.
  - **Tests.** Python: `test_saturn_family` 146 (2 skipped by design, the Saturn 3 has no aft frame), `test_brakiri_bokmai`
    42, `test_centauri_brezebel` 36, `test_skylark_transport` 32, `test_narn_transport` 31, `test_refview_compare` 45,
    `test_textured_hulls` 19, `test_cli` 19, `test_mesh_only` 2, all OK. GUT: `test_civilian_meshes` 4/4 (the nine hulls,
    the pod and the turrets import as textured meshes).

### M5-T21 Defensive turrets in the native core

- **Goal:** AC19 (D61, Q14, Q28). In the order it comes after T27 and before T16.
- **Files:**
  - Native: `native/src/weapon_kernels.rs` (the mount's aim with arc limits, slew and lead; the fire gate; the attacker
    filter), `native/src/weapon_rows.rs` (mount rows bound to a ship's row, the attacker memory as columns, the shot as a
    bolt row), the AI job's turret pick in the core's worker step with its stamp (`native/src/sim_core.rs` and the step's
    join), Rust unit tests beside each kernel.
  - GDScript: `src/combat/turret_mount.gd` (node: the model and its turn from the row, through the frame pass), the facade
    that binds mounts to rows (beside `src/perf/native_weapons.gd`), `src/game/ship_assembly.gd` (mounts from `turrets[]`),
    the `Hardpoints` parser (`turrets[]`, optional), a turret `WeaponSpec`, `tools/procgen/assets/sfx_combat.py`
    (`turret_fire`).
  - Tests: `tests/unit/test_turret_kernel.gd` (aim, gate, pick and memory through the core on seeded scenes),
    `tests/integration/test_turret_threads.gd` (1 against 6 threads and `threaded` against `delayed`, byte for byte),
    `tests/integration/test_turret_defence.gd` (the balance fight: two raiders and a Saturn 4, headless, three seeds).
- **Threads:** as "M5 on the native core" says: the pick in the AI job one tick behind, applied at the join against the
  turret's stamp; aim, gate and shot on the main thread in the weapon rows' step; the memory written on the main thread in
  the sweep's order; spread from a hash of turret id and tick. No GDScript per tick per turret.
- **Notes:** extends M4-T20's kernels; T37 (Q28) may reshape the same files on `m4`, and its overlap is resolved at the next
  merge of `main`. No GDScript fallback (`CLAUDE.md`). Civilians are the only ships with turrets in M5; the seam is general
  (M12's capitals).
- **Done when:** AC19.
- **Done (as built, 2026-11-07, on `oscar`; started by a sub-agent that hit a usage limit, finished by a second one):**
  - **Native.** `native/src/turret_kernels.rs` is engine-free. It holds the mounts, the attacker memory (30 s from the last
    hit, forgotten when a hull dies), the pick (`PickJob`), the aim (arc, slew, lead by `brain_maths::solve`), the gate and
    the spread (a splitmix hash of the mount's id and the tick). `native/src/turret_rows.rs` is the `ScsSimCore` shell
    around them. The kernels sit in their own files beside M4-T20's stand-ins, not in `weapon_kernels.rs` and
    `weapon_rows.rs`, so T37's reshaping of those (Q28) meets no turret code at the next merge.
  - **Threads.** The pick rides in the brains' job one tick behind (`brain_step::pick_turrets`, on the frozen rows and memory)
    and lands at both joins against each mount's stamp (`take_turret_picks`; `turret_picks_stale` counts the dropped ones).
    `BrainBatch` launches a job on a tick with turrets even when no AI ship thinks. Aim, gate and shot run on the main thread
    in `SimCore.step_now`, after the cannons and before the bolt step; each shot is an owned bolt row, landed by the native
    hit sweep. `HitResolver` writes the memory in the sweep's order (`SimCore.note_hit`).
  - **GDScript.** `TurretRows` binds the mounts and hands the shots back. `TurretMount` is the node; its model is the
    manifest's `turret` mesh, split once per asset into base and barrels, and `FramePasses` turns it once a frame.
    `ShipAssembly` builds the mounts from the optional `turrets[]` that `Hardpoints` parses. Also new: a `civilian`
    assembly option, `ShipSpec.turret_weapon`, the light turret `assets/weapons/turret_light.tres`, and `turret_fire`
    (sfx_combat v6).
  - **Saturn 4 for the fight.** A minimal `assets/ships/saturn_4_transport.tres` and the catalog type
    `saturn_4_transport` (Earth Alliance): 14,000 t, 1000 hull, slow rates, no cannon. The sheet can park it. T16 owns the
    full civilian catalog and may replace every number.
  - **Balance (`test_turret_defence`).** Seeds 1, 2, 3; the transport flies the `civilian` profile; dead ships are parked as
    the pool parks them. The first numbers (2.5 damage every 1.2 s) killed both raiders in every seed, and a 1500 hull never
    fell, so the light turret became 4.5 damage every 3.0 s (900 m/s, 2 s life, 1.5 km range and 0.8 degree spread kept)
    and the Saturn's hull 1000.

    | Seed | Raid: transport down at | Raiders left | Turret hits | Run before death | Turrets finish the 15 % raider at |
    |---|---|---|---|---|---|
    | 1 | 51.9 s | 100 %, 100 % | 0 of 14 | 474 m | 70.3 s (2 hits of 4 shots) |
    | 2 | 91.4 s | 10 %, 100 % | 12 of 45 | 775 m | 43.2 s (2 of 4) |
    | 3 | 87.5 s | 100 %, 33 % | 9 of 42 | 816 m | 33.9 s (2 of 4) |

  - **Tests.**
    - Rust: 13 of 13 (`turret_kernels/tests.rs`, the crate's only Rust tests).
    - New GUT: `test_turret_kernel` 14 of 14 (7 new), `test_turret_threads` 2 of 2 (byte for byte, threaded against
      delayed and 1 thread against 6, 300 ticks), `test_turret_defence` 2 of 2 (about 100 s).
    - Regression, all passing: `test_sim_core` 17, `test_brain_parity` 7, `test_brain_think_parity` 5, `test_weapons` 48,
      `test_weapon_charge` 10, `test_hit_resolver` 16, `test_console_command_list` 7, `test_engine_audio` 9,
      `test_audio_director` 13, `test_main_scene` 13, `test_mission_runner` 18, `test_frame_passes` 12, `test_core_threads`
      7, `test_hardpoints` 20, `test_ship_pool` 21, `test_far_dots` 10, `test_ship_catalog` 5, `test_livery_hull` 9,
      `test_textured_hull` 4.
    - Python: `test_sfx_combat` 31. `scripts/check_scripts.gd` is clean.
    - Not run on `oscar` (slow files, `GUT_SLOW=1`): `test_flight_parity_fight`.
  - **GPU.** One small GPU screenshot on `oscar` (Tahiti, labelled as oscar's): `sheet saturn_4_transport` shows the aft
    turret on the dorsal drum, textured, its barrels forward at rest.
  - **(H):**
    - The turret model's look on every hull, and its turn and lift in flight.
    - The `turret_fire` sound's level (-14 dB) and feel.
    - At high elevation the barrels' roots may show through the dome, because the mantlet stays on the base.
    - The visual muzzle is 1.45 m above the core's: the shot leaves along the axis from the base's pivot, the model's barrels
      from the trunnion.

### M5-T16 Civilian ships in the game

- **Goal:** AC13 (D58 factions, D59).
- **Files:**
  - GDScript: `data/factions.json` (`narn`, `centauri`, `brakiri`, the relations; civilians are a role, not a faction,
    Q24), `src/game/ship_catalog.gd` (nine types), a `ShipSpec` per hull (mass, thrust, inertia, limits), the pools,
    running lights, `DestructionDirector` chunk sets, the Bokmai's pods in `ShipAssembly`,
    `data/scenarios/civilian_showcase.json` (all nine parked in view, a Bokmai with three pods and one with none),
    `tests/integration/test_civilian_ships.gd`.
  - Native, the brains (`native/src/brain_behaviours.rs`, run in the AI job one tick behind): the fleeing of Q24 and Q25 as
    behaviour, not GDScript: run from the threat towards the nearest ship of the civilian's own faction, of any kind, and
    for a military one aim for its far side from the threat; close up with other fleeing civilians of the same faction;
    panic spreads to same-faction civilians within about radar range of a fleeing one. Each reads the frozen rows (faction,
    kind, role, position), so it costs work linear in the ship's nearest contacts, never a sweep over all ships.
  - Native, the core: the body kind (or role column) for a big non-combat hull in the registry, so the brains' targeting,
    the raiders' picks and the turrets see a 200 m freighter for what it is, not as a fighter or a capital; the avoidance
    radius from the hull's collision bounds for slow 200 m hulls; the low-attention tier's promotion and demotion of those
    hulls (M4-T21 handles fighters and capitals).
  - Tests: Rust tests for each new behaviour and column, GUT tests through the core on seeded scenes (flee target, shelter
    side, panic radius, grouping), 1 against 6 threads and `threaded` against `delayed` byte for byte, and the brains'
    recorded-reference parity tests (`tests/fixtures/`) green for every ship that is not a civilian.
- **Notes:** the civilians fly through the native brains already; no new GDScript AI. The GPU check (`civilian_showcase`,
  `state render`, VRAM from `/sys/class/drm/card1/device/mem_info_vram_used`) runs on the maintainer's machine; on `oscar`
  a small showcase may run with its numbers labelled (Q29).
- **Bokmai pods (Q17, D59):** `ShipAssembly` builds a pod at each `cargo_pods[]` mount up to the spawn's `cargo_pods`
  count (0-3, default 3), pooled with the ship (D22); a pod adds its mass and collision shape and switches LOD with the
  hull; when the ship breaks up its pods drift off as debris. A test spawns Bokmais with 3 and 0 pods and checks mass,
  collision and the pods' debris.
- **Flight to friends (Q24):** each civilian hull carries its faction (Earth Alliance, Narn, Centauri, Brakiri) with
  `civilian` as its role, so relations come from the faction and the profile from the role. Attacked, the `civilian`
  profile flees the attacker towards the nearest ship of its own faction, of any kind, found through the contact scan's
  results (not a new scan; M4 owns the scan); with none in range it flees straight away from the threat as before.
  Civilians fleeing near each other close up and run as a group, so their turrets (D61) cover one another. **Panic
  spreads (Q25):** a fleeing civilian sets same-faction civilians within its sensor range running too, though nothing
  attacked them. **Shelter (Q25):** when the friend it runs to is a military ship, the civilian aims for a point beyond
  that ship on the line from the threat (a standoff of a few hull lengths), so the warship sits between it and the
  attacker. Tests: an Earth Alliance freighter attacked with a Starfury and a Narn transport in range heads for the far
  side of the Starfury from the attacker; a second freighter within sensor range of it starts fleeing, one beyond does
  not; two attacked freighters end closer together than they started.
- **Done when:** AC13.
- **Done (as built, 2026-11-07, on `oscar`):**
  - **Data.** `data/factions.json` gains `narn`, `centauri` and `brakiri`, each hostile to raiders and neutral to the rest
    (Q24). `ShipCatalog` lists the nine hulls with their people's factions and `CIVILIAN_TYPES` (the role); `ShipPool`
    builds them with `ShipAssembly`'s `civilian` option; `Main` prepares any other pool type a scenario lists and its debris
    sets; a spawn may give `cargo_pods` (0-3) and `forward`. `civilian_showcase` (front end Sandbox, `scenario`, `play`)
    parks all nine in view, a Bokmai with three pods and one with none.
  - **Specs.** One `ShipSpec` a hull: mass and inertia from its hardpoints; no cannon, its turrets (T21); torque-only
    turning; zero damping (`test_civilian_ships` checks the body's damping and that a coasting hull keeps its speed); no
    damage layout, so a civilian bursts into its chunks. Q30: the four Saturn 4 and 8 variants share the Saturn 4
    transport's engine and thrusters (0.304, 0.204, 0.168, 0.106 g), the Saturn 3 keeps its own (0.31 g); `rate_max` is
    three seconds of each hull's angular acceleration (S4 transport 6/6/6 deg/s, S4 tanker 7.8/12.2/15.6, S8 transport
    1.1/1.5/3.0, S8 tanker 0.9/1.4/7.6); the smaller hulls (Skylark, Narn, Brezebel, Bokmai) 5 m/s^2 and a rate of about
    950 / length deg/s. Engine glows from the written schemes. The Brakiri turrets fire green
    (`turret_light_brakiri.tres`, the light turret's numbers).
  - **The Bokmai's pods.** `CargoPods` (`src/ship/cargo_pods.gd`) builds every mount's pod mesh and Jolt shapes once with
    the ship; `set_count` mounts the first n with their mass, inertia, shapes and hit volumes (`Damageable.set_volumes`);
    the far dot hides them; a destroyed Bokmai sheds the mounted pods as one-shot debris chunks (`DebrisPool.burst`'s
    `pooled` off). The assist still reads the spec's mass, so a laden Bokmai answers a little slower than it expects.
  - **Native.** The rows' role column (`ROLE_CIVILIAN`), fed from `SimCore.set_civilian` at registration (touching the
    body), kept in the tier. `native/src/civilian.rs` (engine-free, under `test_sim_core`'s guard): a civilian with a
    hostile in range runs to the nearest ship of its own people among its contacts, to a warship's far side from the
    threat (standoff three radii of the larger hull, at least 150 m) or to a freighter, and closes up with its people's
    other fleeing civilians; panic: the job marks the fleeing and alarmed civilians from every brain's last think before
    its pass, and a civilian with an alarmed kin within 5 km runs (20 s hold, one hop). With nobody to run to the retreat
    is M3's, bit for bit. Against a civilian target the attack's ranges and the raiders' pick use its skin distance;
    avoidance gives it a rock's horizon; turrets defend it within 2 km of skin; the tier moves it by its surface. Design in
    architecture §18.11.
  - **Turrets (Q32, fix round 1).** Every Saturn's command disc carries `flank_l` and `flank_r` at (∓14.43, 0, 19.1),
    up ∓x outboard, the 200 degree arc, on 0.8 m posts sunk 1.2 m into the rim (the turret's 3.6 m base overhangs them);
    `dorsal_fwd` on the hub is gone, the cargo sections' `dorsal_aft` (Saturn 4s, (0, +9.3, 124.4)) and `dorsal_mid` (Saturn
    8 transport (0, +7.2, 149.4), tanker (0, +9.0, 149.4)) stay: the Saturn 3 carries 2 turrets, the others 3. A first try
    with 1.6 m drum pads took the lead ship's front IoU to 0.893; with the posts it is 0.959 / 0.919 / 0.913 (width 1.021),
    re-scored on every variant (`docs/assets-civilian.md`). `test_saturn_family` checks the mounts and that no barrel enters
    the hull at any azimuth from the arc's lowest elevation up (151 tests OK). The two posts add 10 t, so the specs take the
    new hardpoint masses (Saturn 4 transport 14 092 000 kg).
  - **Line of fire (Q33, fix round 2).** A ship's own hull blocks its turrets' fire, natively. `TurretRows` hands the core
    the ship's own hit volumes (the `Damageable`'s boxes and capsules, body frame, 16 numbers each: 15 to 45 on the
    civilians) when its first mount binds and again on `Damageable.volumes_changed` (the Bokmai's pods); nothing per tick.
    `turret_kernels.rs` tests a line against them: a bounding-sphere reject, then a slab test for a box or the
    segment-to-axis distance for a capsule, in 64 bits; a volume the line starts in does not count. The line starts 1.5 m
    above the mount's base (the trunnion, clear of the hull on every civilian; the barrel's tip may dip into the hull) and
    runs to the lead point at the gate (main thread, `step_turrets`: a blocked shot is withheld and counted,
    `turret_readouts()[4]`), and to the attacker in the pick (the AI job, on its copy of the volumes, re-copied when their
    version changes; tested only for a candidate that would win, so a blocked one is skipped and the next taken). Stamps
    unchanged. Cost: about 0.56 us a line test on the Saturn 8 transport's 45 volumes; one or two a mount a tick in the pick
    (worker thread), one a shot at the gate. Every turreted ship has it (M12's capitals). The real blind spot of a Saturn 4
    transport is narrower than "the belly from astern": its flanks sit wide on the disc rim and see past the narrow cargo
    hull, so the hull hides only what lies near its axis astern and a little below (pinned at 320 m astern, 60 m below:
    both flanks have it in their arcs, no turret picks or fires).
  - **Balance (Q31, re-tuned in fix rounds 1 and 2).** With Q32's flanks every Saturn won far too often at Q31's first
    numbers (the Saturn 3 10 of 10 against two raiders and 6 against three); in Q31's order the shared light turret came
    down to 6 damage every 2.4 s with 0.5 degree spread (T21 had 4.5, 3.0 s, 0.8; Q31's first tune 8; 900 m/s, 2 s life,
    1.5 km range kept; the Brakiri copy follows), then each hull from the winners' damage taken. Under Q33 the turret held
    four of five in the band, so only hulls moved: the Saturn 8 transport (0 of 10 at 620) and the two thinnest wins.
    Final hulls: Saturn 3 640, Saturn 4 transport 450, Saturn 4 tanker 440, Saturn 8 transport 1150, Saturn 8 tanker 330
    (Skylark 440, Narn 340, Brezebel 300, Bokmai 330 untuned, no balance rule for them). `test_turret_balance` (behind
    `GUT_SLOW`; run alone on `oscar`, about 30 minutes):

    | Saturn | Turrets | `hull_max` | Two raiders (of 10) | Three raiders (of 10) |
    |---|---|---|---|---|
    | 3 freighter | 2 | 640 | 1 (seed 8, 11 % hull left) | 0 |
    | 4 transport | 3 | 450 | 1 (seed 7, 12 %) | 0 |
    | 4 tanker | 3 | 440 | 2 (seeds 3, 5: 62 %, 10 %) | 0 |
    | 8 transport | 3 | 1150 | 2 (seeds 1, 8: 13 %, 9 %) | 0 |
    | 8 tanker | 3 | 330 | 1 (seed 7, 36 %) | 0 |

    Three variants sit at one win, the band's floor: a change to the raiders or the brains can move a count by one. The
    15 % finish check (`test_turret_defence`) holds without a change: the turrets finish the raider in all three seeds at
    37 to 41 s with two hits, the transport at 37 to 49 %. `test_turret_defence` also checks the three mounts, the shots
    and the run; D61's "two of three seeds within 180 s" is superseded.
  - **Tests.** Rust 29 of 29 (`civilian/tests.rs` 11 new, `turret_kernels/tests.rs` 18 with fix round 2's five: box and
    capsule segments, the turned frame, the pick skipping a hidden attacker, the volume table). Fix round 2's GUT:
    `test_turret_line_of_fire` 3 (the blind spot pinned, the same raider fired at with the hull's volumes taken out, a
    raider beside the ship fired at), `test_turret_threads` 3 (a Saturn with its own turrets against four AI raiders,
    threaded against delayed and one thread against six, byte for byte), `test_turret_kernel` 14 (its below-the-arc raider
    moved into clear line), `test_turret_defence` 2, `test_sim_core` 17, `test_brain_parity` 7, `test_brain_think_parity`
    5, `test_weapons` 48, `test_civilian_ships` 5, `test_ship_catalog` 6; `check_scripts` clean. Not run on `oscar`:
    `test_weapon_rows_battle` (the `battle` layout). GUT: `test_civilian_flight` 5
    (shelter, panic in and out, grouping, threaded against delayed and one thread against six byte for byte),
    `test_civilian_ships` 5, `test_ship_catalog` 6 (Q30 pinned), `test_faction_table` 33 and `test_factions` 21 (the
    shipped file's new peoples), `test_turret_balance` 2 (slow), `test_turret_defence` 2. Python: `test_saturn_family` 151
    (2 skipped by design). Regression, all passing: `test_sim_core` 17 (the guard holds `civilian.rs`), `test_brain_parity` 7, `test_brain_think_parity` 5, `test_pilot_kernels` 7, `test_turret_kernel` 14, `test_turret_threads` 2, `test_destruction` 11, `test_debris_pool` 12, `test_main_scene` 13, `test_console_command_list` 7, `test_tier` 10, `test_tier_handover` 13, `test_ai_retreat` 1, `test_civilian_meshes` 4, `test_damage` 17, `test_frame_passes` 12, `test_brain_in_play` 2, `test_last_hit_breakup` 14, `test_hit_resolver` 16, `test_hardpoints` 20, `test_scenario_loader` 36; `check_scripts` clean.
    `test_ai_think_time`: before AiPilot median 335 us (paired difference -2522 us), after 337 us (-2487 us): no change beyond noise.
  - **GPU (oscar, R9 280X, labelled as oscar's, Q29).** `civilian_showcase` at 960x540: `renderer = forward_plus`, 57 fps,
    96 draw calls, 158 406 triangles, `render.vram_mb` 441 MB; the card's VRAM (`mem_info_vram_used`) 695 MB idle, 1 273 MB at
    its peak in the run. At 1.8 km the hulls are small beside the overlay; the screenshot is in `reports/` (not in git).
  - **Left:**
    - The GPU check on the maintainer's machine (`civilian_showcase`, `state render`, VRAM). Not run on `oscar`:
    the slow parity fights (`GUT_SLOW`), `test_core_threads` and `test_core_snapshot` (the `battle` layout), any bench.
  - **(H):** the nine hulls' look in play and their engine glows; the Bokmai's pale pods against the olive frame; how the
    fleeing reads (shelter, groups, panic); the Saturn 8s' slow turns (about 1 deg/s pitch); the balance's feel with the
    harder-hitting turrets and the low Saturn hulls (330 to 620); the flank turrets on their posts at the disc rim
    (GPU screenshots skipped in fix round 1: the maintainer's display was asleep).

### M5-T28 Engine voices on the core's rows

- **Goal:** AC16's audio clause at any ship count: `EngineVoices`' 4 Hz re-rank stops walking every ship.
- **Files:** a native query for the rows within a radius of a point, nearest first (beside the registry's nearest-k),
  `src/audio/audio_director.gd` and `src/audio/engine_voices.gd` (rank from the query's rows), `tests/unit/test_engine_voices.gd`,
  `tests/integration/test_engine_audio.gd` (a work count: the re-rank's units grow with the ships in range, not in play).
- **Notes:** reads the rows the main thread already has, never the worker's in-flight snapshot; audio stays in `_process`.
- **Done when:** the work-count test and the existing engine-voice tests pass.
- **Done (as built, 2026-11-07, on `oscar`):**
  - **The query.** `ScsSimCore.ships_near(centre, radius_m)` returns `[body_ids, squared_distances]`: the node rows that are
    rigid ships, not tier rows, within the radius, nearest first (ties in row order). The maths is `voice_kernels.rs`
    (engine-free, under `test_the_kernels_hold_no_engine_type`, with 7 Rust tests); `voice_rows.rs` is the shell. It reads
    `self.rows`, the rows the main thread holds after the tick's sync, never the AI job's snapshot (M4-T24). The facade is
    `SimCore.ships_near`; without a core it answers empty (no GDScript walk to fall back to), so only the player's own voices
    sound then.
  - **The re-rank.** `EngineVoices.allocate` is gone: `begin_allocation(player_in_play)`, an `offer(ship)` per listed ship
    and `finish_allocation()`. `AudioDirector.reallocate_engines` maps the body ids to its ships and stops offering when the
    cap is spent. The grant order is unchanged (the player's voices, then whole ships nearest first). The rows are the tick's,
    so each candidate's node is checked (`_in_play`) before it is offered: a ship parked or freed since is never granted from
    a stale row. The per-frame envelope step stays GDScript in `_process`, bounded by `engine_voice_cap`.
  - **Work counts.** The re-rank's `allocate_work` was one unit per registered ship (14 in the default scenario's pools) and is
    now the player plus the ships walked: 5 in the default scenario (the player, its own row and the allies in earshot), 7 with
    nine raiders at 300 m (the cap spends first). Three hundred bodies 20 km away leave it unchanged
    (`test_ships_beyond_hearing_cost_the_re_rank_nothing`; the unit tests show 3 in earshot among 303 cost 1 + 3). The new
    console readout `audio.engine_rank_work` shows it; `info.md` is updated.
  - **T26's note.** A ship the flight batch flies (no tick of its own, M4-T35/T36) is voiced: `get_flight_output()` fills from
    the batch's row, and `test_a_ship_the_flight_batch_flies_is_voiced_when_it_thrusts` pins it.
  - **T19's carried items.** `watch_ship` no longer returns for a hull with no cannon, so a civilian gets its pod voices (and
    its turrets' sound hook); a ship watched before it is ready gets its voices at its `ready`. `AudioDirector.unwatch_ship`
    (and `EngineVoices.remove_ship`) takes a ship's voices away for good: playing ones stop, their nodes are freed and the id
    is never granted again (its slots stay taken, a few words per voice). **For M5-T17:** traffic returned to the pool needs
    nothing (a parked ship leaves the rows and falls silent), traffic freed for good calls `audio.unwatch_ship`.
  - **Tests.** `test_engine_voices.gd` (23: the re-rank follows the ships in earshot, the walk stops at the cap, a removed
    ship), `test_engine_audio.gd` (15: the cannon-less civilian, the not-yet-ready ship, the pool-parked ship revoked, unwatch,
    the batch ship, the far rows), `test_voice_query.gd` (5, new: the query on the core, tier rows never listed, a rebase) and
    the Rust tests. A test that spawns or moves a ship now waits a tick before it re-ranks, since the rows are the tick's.
    `test_audio_director`, `test_sim_core`, `test_console_command_list` pass; `cargo test` 36.
  - **Not run.** `check_scripts` reports `encounter_console.gd`, `encounter_director.gd` and `main.gd` (M5-T17's files, in
    progress in the same working copy), none of them T28's. No benchmark, no `GUT_SLOW` suite and no windowed run (`oscar`).

### M5-T17 Free-flight encounters

- **Goal:** AC14 (D58).
- **Files:** `src/encounters/encounter_plan.gd` (pure), `src/encounters/encounter_director.gd`, `src/encounters/
  encounter_console.gd`, `data/scenarios/free_flight.json` (pools for encounters), `src/autoload/settings_schema.gd`
  (`encounters`, `encounter_interval_s`, `encounter_max_ships`), `src/game/main.gd` (create the director in free flight when
  encounters are on), `tests/unit/test_encounter_plan.gd`, `tests/integration/test_encounters.gd`.
- **Notes:** the pools add load time to free flight; record it. Run M3's `test_ai_think_time` before and after.
  `EncounterPlan`'s draws are hashes of the session seed and the event index (`CLAUDE.md`: no shared or stepped RNG), so
  an event's draw does not depend on how many came before it was asked for.
- **Done when:** AC14 and AC16's encounter clause.
- **Done (as built, 2026-11-08, on `oscar`):**
  - **Plan.** `EncounterPlan` and `EncounterEvent` (pure, tests first). Event `i` comes at `interval * (i + 1)` give or take a
    quarter interval (gaps 60-180 s at the default 120 s of sim time). Every draw is `hash([seed, i, salt])`, so an event is the
    same whatever was asked before it. Kinds by weight (raid 0.4, patrol 0.25, traffic 0.35, in the pools file). Raids: 2-6
    raiders around one jump point 6-12 km from their target, half of them sent at an encounter civilian within 20 km of the
    player when there is one. Patrols: 2/4/6 Starfuries at 220 m/s. Traffic: 1-3 hulls of any of the nine at 120 m/s,
    passing 2-10 km out, a Bokmai's pods 0-3 from the seed. Both start 26-30 km out on straight routes that end as far out.
    `EncounterPlan.admit` is the cap rule.
  - **Director.** `EncounterDirector` (node under Main, pausable) exists in any scenario with `data/encounters/<id>.json` (free
    flight), off. `Main.encounters`, set by `Game.finish_loading` from the request, turns it on at load. Every other run
    stays off until `encounters on`, which builds the pools then (D58 said refuse; the brief asked for `encounters on` to
    work in a straight-to-Main run, so it builds them, a hitch on a debug path). It spawns through `ShipPool.acquire`,
    `BrainFactory` (raider with the target as objective, `ally_starfury` engaging, `civilian`), `BehaviourFollowPath` on a
    `Route` (no pacing, no loop; a patrol's yields to attacks) and its own 4-point `JumpArrivalPool`. Releases: once a second,
    over its own ships only, a ship 40 km from the player or at its route's end goes back to its pool, then
    `AudioDirector.reallocate_engines()` once. A destroyed ship leaves the count at once. The ships are pooled, never freed,
    so T28's `unwatch_ship` is not needed (a parked ship drops out of the core's rows by itself).
  - **Found and fixed.** Ships built after load (`ensure_pool`) were not watched by the `DestructionDirector`, so they would
    not break up or return to the pool when destroyed. The director now watches every pooled ship after it builds the
    pools. The bench's `ensure_pool` ships have the same gap; I left it alone.
  - **Additions beyond the spec.**
    - Encounter civilians broadcast 15 km (a transponder) so a raid 6-12 km out finds them past its 5 km sensors.
    - A due event that does not fit waits (later ones queue behind it); one bigger than the whole cap is trimmed to it once
      nothing else is in play, so it cannot wait for ever.
    - A traffic hull whose pool is spent gives way to the next civilian hull with a free ship.
    - The front end gives each free flight a fresh seed (`FrontEnd.session_seed`) so sessions differ; Restart keeps it.
  - **Settings.** `encounters` (bool, true): the Free flight page starts from it and keeps the toggle there for the session (the
    next settings save, from the menu or the console, writes it to disk). `encounter_interval_s` (120, 20-600, read when encounters first turn on).
    `encounter_max_ships` (24, 4-48, live).
  - **Console.** `encounters [status|on|off|next|force|clear] [raid|patrol|traffic]` (AC14's `encounter <kind>` is `encounters
    force <kind>`, drawn from indices from 1 000 000 up so the schedule is untouched) and provider `encounters`; both in `info.md`
    under the new "free flight" place.
  - **Pools** (`data/encounters/free_flight.json`): 12 raiders, 12 Starfuries, two of each civilian hull (42 ships).
  - **Load time** (oscar, headless, `test_encounters`): free flight with encounters off 120-156 ms; on 740-920 ms, of which
    the pools take 650-820 ms. A live `--console-exec` `encounters on` built them in 992 ms.
  - **Cost (AC16).**
    - A tick compares one time.
    - The release check's work equals the director's own ships: 4 units for 4 own ships with 6 in play.
    - `test_ai_think_time`: before, AiPilot median 342 us (paired difference -2610 us); after, 345 us (-2559 us). No change
      beyond noise.
  - **Tests.**
    - New: `test_encounter_plan` 15 (seeds, order independence, intervals, weights, the three kinds' numbers, routes, the cap,
      trim) and `test_encounters` 17. The integration file covers: off leaves free flight empty with `raiders.pool_size = 0`;
      the pools; raid ranges and jump points; cruise-in ranges and routes; Bokmai pods; hull substitution; releases at 40 km
      and at the route's end with no engine voice left; a near ship stays; a destroyed ship leaves at once; the cap waits and
      trims; sim time and the pause; raiders sent at a Saturn attack it and the patrol engages them; the check's work count;
      the console; the load time.
    - Regression, all passing: `test_settings_schema` 25, `test_settings_menu_model` 15, `test_console_command_list` 7,
      `test_main_scene` 13, `test_boot_routing` 14, `test_front_end` 22. `test_front_end` was red from T16 (Sandbox now lists
      `civilian_showcase`); I updated it here. `check_scripts` is clean (590).
  - **Left:** the `docs/playtest.md` M5 section on encounters (T20, AC17). AC14 says "released past 30 km"; this follows D58's 40 km.
  - **(H):**
    - The pacing (an event every 1-3 minutes) and the mix.
    - How raids read when they jump in at 6-12 km.
    - Patrols and traffic coming over the radar's edge.
    - Whether the 15 km civilian transponder shows anything odd on the radar rim.
    - No GPU run on `oscar` for this task.

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

### M5-T25 Targeting at scale: a target menu and other targeting UX (Q26)

- **Track:** A. **Agent:** Opus. **Depends on:** T02 (the menu kit), T07 (the D-pad menu routing), and the M4 rebase (battles of
  300 to 500 ships, M4-T34's candidate list built when it is read, M4's far-ship dots and tier). Placed before T20.
- **Why:** today the pilot cycles targets one at a time (`target_next`, `target_prev`, `target_cycle`, `target_ahead`) through a list
  of every targetable in reach. With hundreds of ships, cycling to the one that matters takes too many presses, and the HUD and radar
  bracket too much.
- **First: a concept stop (H).** Before any code, the task writes the options below (and any better ones it finds in other games'
  targeting UX: flight sims, space sims, RTS selection), builds a mockup sheet of the menu and HUD at 300 ships, and stops with
  `NEEDS_CONTEXT: targeting concepts ready` for the maintainer to pick. Then it builds the chosen set, tests first.
- **The maintainer's layout (2026-11-09):** the target menu is circular (radial), vertically centred at one side of the
  screen (left by default), and the target information (T43's wireframe, hull bar, distance and info lines) sits
  vertically centred on the opposite side. **The right stick points at an entry** (the ring highlights the slice it
  points to; a centred stick keeps the last highlight), **A selects** (a category at the first level, the target at the
  second) and **B goes back** (to the first level, then closes the menu); X and Y take no part in the menu. **Opening a
  radial menu pauses the game** (maintainer, 2026-11-09), as the pause menu does: the world and sim time stop, the menu,
  its preview and the focus pull run with process mode always, and the pad belongs to the menu (`InputAdapter` reads only
  the menu's stick, A and B, and re-seeds every other edge on close so nothing fires, steers or targets on the frame the
  game resumes). Picking a target (or B out of the first level) closes the menu and resumes. Start while a radial menu is
  open closes it and opens the pause menu. While it is open the rest of the view is out of focus (T44). The radial ring, the pause while open, its input (right stick, A, B,
  nested pages) and T44's focus pull are one reusable framework (`RadialMenu`, its pure layout, stick-to-slice and page-stack model in a
  `RefCounted` with GUT tests), because the comms menu moves onto it in T46 and later comms options grow on it. The concept stop mocks this
  layout first; the options below fill it in.
- **Options to brainstorm and mock up:**
  1. **A target menu** on a held button (or the comms menu pattern of D54): categories (hostile fighters, capital ships, ships
     attacking me, my wing's targets, objectives, navigation and stations), each sorted by threat or distance and paged with the
     D-pad; picking an entry selects it. Radial, per the maintainer's layout above.
  2. **Smart target buttons:** "who is shooting me" (the nearest attacker, from the hit log), "my leader's target" and "my wing's
     targets", "the objective", "the ship in my reticle" (exists as `target_ahead`), "the previous target" toggle.
  3. **Scoped cycling:** cycle within the current category only (hostiles only, fighters only), ordered by threat instead of
     distance, with ships beyond weapon or sensor range skipped.
  4. **HUD and radar decluttering:** bracket only the top few threats and the selection, show off-screen arrows only for the
     selection and current attackers, fade markers by distance, and merge distant groups into one cluster marker with a count
     (the far-ship dots of M4-T11 and T23 can carry the group).
  5. **Target pins:** mark up to a few ships to return to; wing orders from the menu ("attack my target", "cover me from this one").
  6. **Later, with M12's capitals:** sub-targets on a capital ship (turrets, engines, launch bays) as a second menu level.
- **Rules:** gameplay never reads `Input` (new `UiCommand` or `CombatCommand` fields through `InputAdapter`, as D54 does); the menu
  reads the candidate list on demand, never builds per tick (M4-T34); categories come from data already on the rows (faction, kind,
  attacker); new actions get profile defaults through M3-T07's mechanism; console commands and a state provider per the rules, rows
  in `info.md`.
- **Tests first:** the category filters and threat ordering as pure logic (`RefCounted`) with GUT tests on seeded candidate sets of
  500; the smart buttons pick the right ship in scripted cases; the menu routes the D-pad without firing other actions; the cost of
  opening the menu at 500 ships measured (no per-tick cost when closed).
- **Done when:** the maintainer's chosen set works in the dogfight scenario and a 300-ship battle, the tests pass, and the (H) items
  (readability at 4K and 1080 lines, the feel of the pause and resume mid-fight) are in the playtest list.
- **Done (as built, 2026-11-11, on the maintainer's machine):**
  - **Built (Q44's set, the mockup of 2026-11-11):**
    - **The tap.** A tap of a target button (pad B, keyboard B, Mouse 2) gives `CombatCommand.target_nearest`:
      `TargetCategories.tap_pick` takes the nearest enemy, or the 2nd nearest when the nearest is selected, and back. The
      old hold (`target_ahead` on the keyboard, `target_prev` on the pad) left the buttons; both stay actions, unbound.
      The mouse wheel still cycles every target.
    - **The hold.** Held `settings.target_hold_s` (0.35 s), a target button gives `UiCommand.target_menu_open`.
      `TargetMenuDirector` reads the player's candidate list once, pauses the tree (the pause the game had before is put
      back on close) and shows the menu; it stays open after the release.
    - **The framework.** `RadialMenu` (pages, highlight, stick to slice, `arrange` with "none" in the down slice),
      `RadialLayout` (the ring vertically centred at the left, slice polygons, label points) and `RadialMenuView` (a
      `CanvasLayer` at layer 45 that is hidden and does not process while closed). T46 puts the comms pages on the same
      three; T44's blur goes between the HUD's layer (40) and 45; T43's panel takes the right side (`right_side` mirrors
      the ring if that is ever swapped).
    - **The rings.** First: Enemies, Allies, Civilian, Unknown, Navigation, Objectives, clockwise from the top, with counts.
      Second: six slices, the nearest five of the category clockwise from the top and NONE straight down. Objectives: the
      active objectives whose triggers name an actor in play or a fixed place (`ObjectiveBook.subject`, `Trigger.place`),
      the first five.
    - **Picking.** A ship becomes the target; a beacon or an objective becomes the HUD waypoint (`HudWaypoint`: the diamond
      on screen as before, and a diamond round its radar contact), never the target; NONE clears the target or the
      waypoint. Every pick closes the menu and resumes. The later of the pilot's pick and a script's waypoint wins
      (`MissionApi.waypoint_serial`, the instructor's route by its `NAV n`).
    - **Input.** While it is open `InputAdapter.sample_radial` reads only the menu's stick, select, back and Start
      (`radial_up/down/left/right/select/back`: the right stick or the arrow keys, A or Enter or Mouse 1, B or Backspace or
      Mouse 2; the mouse's direction of travel points too). `begin_radial` seeds select and back from what is held (the B
      that opened it is not a back); `end_radial` re-seeds every edge, and the A that selected does not fire and the stick
      that pointed does not steer until each is let go. Start closes it and opens the pause menu.
    - **Unknown.** A contact beyond 5 km (`TargetCategories.IDENT_RANGE_M`, the AI's sensor range) with no broadcast range is
      unidentified: grey on the radar (the native radar kernel flags it, `ScsRadarPlot` colours it), listed under Unknown
      with no name, and as the target it reads `UNKNOWN` in grey with no hull bar or damage outline.
    - **Console.** Provider `target_menu`, command `targetmenu open|pick <entry>|back|close`; both in `info.md`.
  - **Assumptions made where the settled design was silent (say if any should change):**
    1. Both target buttons share the tap and the hold, so pad B's "hold = previous target" is gone with "nearest the nose".
    2. With no identified enemy a tap takes the nearest unknown contact (and the 2nd nearest), so the button is never dead
       while something is out there. With neither (free flight) it does nothing: buoys are reached through Navigation.
    3. Identification keeps no memory: a contact that opens past 5 km is unknown again. The exception is the selected
       target, which keeps its name and colour once identified for as long as it stays selected.
    4. "Broadcasts" means a broadcast range above 0, at any distance (a civilian's 15 km transponder identifies it at 20 km).
    5. Categories: a hostile ship is an enemy even when it is a civilian hull; a civilian of any people, and any ship of a
       people neutral to the pilot, is under Civilian; a friendly ship that is not a civilian is an ally. A ship in the
       low-attention tier is sorted by faction alone (its row carries no role).
    6. The menu's own actions are fixed, like the menu kit's `ui_*` ones: declared in `project.godot`, not part of a control
       profile, so nothing was added to saved profiles. Mouse 1 and Mouse 2 also select and go back. A plain left or right
       arrow takes the upper slice of that side; add Down for the lower one.
    7. Every category ring keeps six slices, so NONE and "the nearest" are always in the same direction; empty slices are
       blank and the highlight skips them.
    8. An objective's slice shows its text cut to 16 characters with its subject and range; the whole text shows under the
       ring while it is highlighted.
    9. The pilot's NONE on Navigation or Objectives hides a script's waypoint too, until the script sets one anew.
    10. A hold does nothing while the controls are not the pilot's (a cinematic, `lock_controls`, the player down, the pause
        menu). Opening the target menu closes the comms menu.
    11. A light dim (25 % black) sits behind the ring until T44's blur.
    12. The HUD keeps the selected target's box and readout behind a pause (it used to drop them behind the pause menu,
        because a paused marker did not count as in play).
  - **Changed from the plan:** no smart buttons, pins, scoped cycling or declutter (Q44 chose the tap and the wheel only). The
    radar's unknown flag went into the native kernel (per contact, per frame); everything else is per-event GDScript.
    `TargetCategories.summarise` keeps the nearest five per category in one pass instead of sorting every category.
  - **Measured (RX 6950 XT, Forward+, window 1200x675, overlay off):** opening the menu, median of 10: 0.28 ms in the dogfight
    (10 candidates), 2.56 ms in `bench battle 300` (304 candidates; 2.4 to 5.5 ms), most of it the candidate list itself;
    `TargetMenu.open` alone on 500 seeded candidates 0.43 ms. Closed, it costs nothing per tick (no node of it processes,
    no candidate is built: test). Dogfight: 145 fps and 41 draw calls closed, 145 and 71 on the first ring, 145 and 69 on
    the second. Battle 300: 144 and 126 closed, 145 and 156 on the first ring, 134 and 154 on the second (the 144 Hz cap
    throughout; the ring adds about 30 draw calls of text and lines).
  - **Tests:** `test_radial_menu` 12, `test_target_categories` 6 (seeded sets of 500), `test_target_menu` 12 (with `HudWaypoint`
    and the 500-candidate opening), integration `test_target_menu` 16 on the main scene (tap, hold and pause, stick, A and B,
    Start, nothing fired or steered on resume, waypoints, the mission's later word, unknown contacts, no cost closed, the
    console, the ring's place on screen), `test_input_adapter` 50 (five new, the tap and hold ones rewritten),
    `test_input_map` 13, `test_radar_model` 15, `test_hud_layout` 52, `test_objective_book` 19,
    `test_targeting_controller` 20, `test_control_lock` 10, and two Rust tests of the radar kernel. The quick tier passes
    (1 629 GUT tests), and so does every GUT file with the slow ones left out (303 scripts, 3 318 tests); main-scene smoke
    runs show no errors or leaks.
  - **(H):** the screenshots in `references/screenshots/T25 target menu/` (both rings in the dogfight and the battle, and
    the HUD after a pick); readability of the ring's labels at 1080 lines and at 4K; the feel of the pause and the resume
    mid-fight, and whether 0.35 s is the right hold; whether a tap falling back to unknown contacts is wanted; whether a
    far contact should stay identified once it has been seen close (assumption 3); the grey of unknown contacts against
    the radar; the keyboard and mouse pointing.

### M5-T29 Generated asteroids and a sparse belt

- **Goal:** AC21 and D63 (Q38). **Track:** C. **Agent:** Opus. **Depends on:** T27 (the textured-mesh pipeline).
- **Files:** `tools/procgen/assets/asteroids.py` (and its registry entry), `tools/procgen/tests/test_asteroids.py`,
  `src/world/belt_layout.gd`, `src/world/asteroid_belt.gd`, the scenario loader's `asteroid_belts[]`,
  `tests/unit/test_belt_layout.gd`, `tests/integration/test_asteroid_belt.gd`, §18, `docs/third-party.md` if anything new
  comes in (nothing should).
- **Tests first** for `BeltLayout`: seeded and deterministic, every rock inside the box, gaps held, small rocks outnumber
  large ones, the count as asked or as many as fit (said, not silent).
- **In the game:** one multimesh per shape and level; static spheres by RID in `StaticRows` (copy the pattern of M4's
  `AsteroidField`, do not change the bench's stand-in); spawned from `UniversePos`, rebase-safe (a test rebases with the
  belt loaded and checks rows and draw positions); the belt is freed with its world (M4-T44's statics rule).
- **Measure:** the static rows' tick cost at the belt's count (`perf on`), and on the maintainer's GPU FPS, draw calls and
  VRAM with the belt in view. A look sheet of the rock shapes and the belt from 2 km and 10 km goes to
  `references/screenshots/T29 asteroid belt/` for the maintainer (H).
- **Done when:** AC21, with the belt in a test scenario; the escort uses it in T30.
- **Done (as built, 2026-11-08, on the maintainer's machine):**
  - **Built:** the `asteroids` generator (16 shapes from 12 kinds, 5 120-triangle render mesh with an 81 920-triangle normal
    map, `shapes.json` with each shape's bounding radius and one to three collision spheres), `BeltLayout`, `AsteroidBelt`,
    the loader's `asteroid_belts[]` (result key `belts`), `Main._spawn_belts` (it warns when a count does not fit), provider
    `belts`, and `data/scenarios/belt_showcase.json`: D63's escort belt, 24 x 3 x 8 km, 400 rocks of 10 to 150 m, 200 m gap,
    starting 3 km ahead of the player. 400 rocks give a mean nearest-neighbour distance of about 620 m (0.55 (V/N)^(1/3)), so a
    Saturn 8 can thread it; all 400 fit. `belt_showcase` is in `settings.scenario` and the `scenario` command, not the menu.
  - **Changed from the drafts:** the peanut's lobes sit further apart (the waist test failed: the neck was as wide as a lobe),
    generator version 3; the crater-floor test checks the render level (a pitted rock's small craters spanned too few faces of
    the coarse test mesh); the CLI's build line now counts the rock shapes' triangles. The drafts grouped rocks into 2 km
    cells (362 multimeshes for this belt); measured against one multimesh per shape, the cells cost more draw calls (274 vs 156
    with the overlay on, from 2 km) and no fewer triangles, also from inside the belt, so the belt draws one multimesh per shape.
  - **Measured (RX 6950 XT, Forward+, 960x540, overlay off):** 16 multimeshes; 145 fps from 2 km and from 10 km (the 144 Hz
    vsync cap), 44 draw calls and about 44 000 triangles in both views; Godot's VRAM 338 MB with the belt vs 282 MB in free
    flight (the 16 shapes' maps). Static rows: 859 spheres; `perf` tick 1 999 us vs 1 946 us in free flight, inside the noise.
  - **Tests:** `test_asteroids` 15 (Python), `test_belt_layout` 7, `test_asteroid_belt` 4, `test_scenario_loader` 39 (three new:
    parsing, errors, the showcase file fits), `test_info_md` 2, `test_console_command_list` 7; main-scene smoke runs (default
    and `belt_showcase` with a rebase) show no errors or leaks.
  - **(H):** the belt sheet (`references/screenshots/T29 asteroid belt/`, from 2 km and 10 km) and the shapes sheet again
    (`references/screenshots/T29 asteroid shapes/`; the approved one is kept beside it), since the peanut changed. Fly it with
    `--scenario=belt_showcase`.

### M5-T30 Mission: Civilian escort with a cinematic intro

- **Goal:** AC10 (rewritten) and the mission half of AC18, per D62 (Q36 to Q42). **Track:** B. **Agent:** Opus.
  **Depends on:** T29 (the belt), T16 (civilians in play), T17 (jump arrivals as used by encounters).
- **Files:** `data/scenarios/civilian_escort.json`, `data/missions/civilian_escort.gd`, `data/dialog/civilian_escort.json`,
  `tests/integration/test_civilian_escort.gd`; the loader's `random_civilian` spawn type; the native brains' resume of the
  pilot objective after a flee; `docs/playtest.md` (how to play it); removed: `data/*/buoy_defence.*`,
  `tests/integration/test_buoy_defence.gd`, `BuoyRing` and `test_buoy_ring.gd`, the `buoy_rings` field;
  `NavBuoy.BROADCAST_RANGE_M` back to 1 000 km with `test_broadcast.gd`; the menu's Missions list, `test_front_end`,
  `test_mission_catalog` and any other test that names Buoy defence.
- **Steps:**
  1. `random_civilian`: drawn from `ShipCatalog.CIVILIAN_TYPES` by the run's seed before pools are built; only that hull
     pooled; a test over many seeds sees all nine and the same ship on a retry.
  2. Flee and resume in the native brains (per tick, per ship, so native under `CLAUDE.md`): a civilian with a pilot
     objective flees by Q24/Q25 and goes back to the objective once no hostile is within its flee radius for a few
     seconds. Rust unit test plus a GUT test (a raider attacks a civilian bound for a point; it flees, the raider is
     destroyed, it reaches the point). The same answers with 1 and 6 threads and threaded and delayed.
  3. The scenario: NAV ALPHA and NAV BETA about 30 km apart, the belt across the middle, Alpha 1 and ALPHA 2, the
     civilian at NAV ALPHA, pools of 13 raiders, 1 ally and the drawn civilian, the two intro shots.
  4. The script: steps `intro`, `brief`, `depart`, `wave_one`, `wave_two`, `wave_three`, `arrive`; the three proximity
     points at 25, 50 and 75 % of the route; waves of 3, 4 and 6 sent at the civilian; closing lines for the civilian's
     loss and the player's; every line original.
  5. Headless tests driven by console commands: success (with `mission goto` and `kill all` between waves), failure by the
     civilian destroyed and by the player destroyed, the debrief in each case, the skip contract (a skipped wave leaves
     no raider and the civilian at the point). A whole-mission run without skips (the civilian crosses the belt with no
     rock hit) goes under `GUT_SLOW`.
  6. The leak after jump arrivals (Progress, 2026-11-08): find it and fix it; the escort's smoke run must be clean of
     `leaked` and `ERROR:`.
  7. A windowed run on the maintainer's GPU: frames of the intro and of each wave to
     `references/screenshots/T30 civilian escort/` for the maintainer (H).
- **Done when:** AC10; the mission plays from the menu in 6 to 8 minutes for a fair player (Q40; the agent times a run
  where the escort fights each wave and records it); the playtest section is rewritten.

- **Done (as built, 2026-11-08):**
  - **Built:** `data/scenarios/civilian_escort.json` (NAV ALPHA at the origin, NAV BETA 30 km out, D63's belt across the middle on
    seed 38, the civilian's route `ESCORT` at 120 m/s through the 25/50/75 % points, ALPHA 2 on `cover`, pools 13 raiders, 1 ally,
    1 `random_civilian`, two intro shots, names for all nine hulls), `data/missions/civilian_escort.gd` (steps intro, brief,
    depart, wave_one, wave_two, wave_three, arrive; waves of 3, 4 and 6 jump in 6-12 km off the civilian on three bearings and are
    sent at it), `data/dialog/civilian_escort.json` (16 original lines with `{civilian}`). `ScenarioLoader.resolve_random_civilian`
    (Main, before the pools), `DialogBook.fill`, `MissionApi.filled` and `MissionApi.transient` (a skipped wave's raiders
    released). The menu starts each mission on a fresh seed. Removed: Buoy defence's files and test, `BuoyRing`, its test and
    `buoy_rings`; `NavBuoy.BROADCAST_RANGE_M` back to 1 000 km.
  - **Changed from the plan:** step 2 needed no native change. A passive civilian never takes a pilot objective (the attack
    behaviour carries it), so the civilian flies a scenario route instead, and the native arbiter already ranks retreat (0.85
    under threat) over follow-path (0.5) and returns to the route's current waypoint when retreat drops; the GUT test pins
    flee-then-resume. The wave points are route waypoints, so the civilian must pass within 150 m of each and the 1 km triggers
    cannot be missed after a detour. The belt seed was picked so the 50 % point (where a skip places the civilian) has no rock
    within 500 m and the straight route clears every rock by 200 m (unit test).
  - **Found and fixed:** (1) mission actors were parked in the low-attention tier once beyond its radius from the player, and a
    parked body read as destroyed to the triggers (the escort failed with the civilian alive); `Ship.tier_exempt`, set by
    `MissionStage.register`, keeps them out. (2) Civilians now broadcast to 15 km from the pool (`ShipPool.CIVILIAN_BROADCAST_RANGE_M`),
    so raiders sent from a jump point find them. (3) The leak at exit after jump arrivals and comms lines: a sound stopped in the
    frame of the quit kept its playback; the console's `quit` now pauses, silences and waits 0.5 s. The escort's smoke runs and
    `encounters force raid` in free flight end clean.
  - **Tests:** `test_civilian_escort` 12 with `GUT_SLOW=1` (menu, intro, success, both failures, flee and resume, the skip
    contract, pools, buoy range, a Saturn 8 crossing the belt with its hull untouched); `test_scenario_loader` 38 (random civilian
    over 200 seeds sees all nine, retry, placeholders, names checked, the belt's clearances); `test_dialog_ids`, `test_objective_book`,
    `test_game_flow`, `test_objectives_model`, `test_mission_catalog`, and the focused files for the tier, pools, mission runner,
    console, front end, encounters and pause menu.
  - **(H):** pacing (6 to 8 minutes for a fair player, Q40: not timed by a person; the route alone is about 4.5 minutes at
    120 m/s plus the intro and brief, so a run with fights should land in it), the lines, the intro frames
    (`references/screenshots/T30 civilian escort/`), and whether a fragile hull (the Skylark) survives three waves with a fair escort.

### M5-T31 L1: the flight batch's gather in native

- **Goal:** AC22 for L1 (`docs/research/m4-full-review.md` L1). **Agent:** Opus.
- **What:** a native step for row-commanded ships over the core's rows: `face_dir_b` from the target row only when the row
  brakes, the pull from the native gravity sources (the tier's `tier_set_gravity`), assist, hulk and propellant as
  per-slot flags set when they change. GDScript gathers only ships without a row command (the player, scripted ships).
  The no-op `set_batch_owned` loop and the five `.slice()` copies go.
- **Done when:** the flight stage at `battle 1000` drops (Report P3: 3.97 ms; estimate 1.5 to 2.5 ms saved), the flight
  parity fixtures hold, and the numbers are in the Done notes.
- **Done (as built, 2026-11-08):**
  - **Built:** row flight in `ScsFlightStep` (`native/src/flight_step.rs`): each slot keeps its body id, a row-mode flag and
    the assist and propellant flags (`set_row_flight`, set on change). `step_core` flies every row-mode slot that was not
    gathered, has a live row command and an active row, from the core alone: pose from the row (the physics server for a body
    touched since the sync), `face_dir_b` from the selection column and the target's row only while braking, gravity from the
    core's sources (`tier_gravity`). `row_strays` lists row ships whose row lost its command; `out_slots` and `slot_rows` map
    outputs to slots. `FlightBatch` gathers only the ships without a row command (`_plain`), a row ship with fresh combat
    commands (once, `mark_gather`) and the strays; ships read their outputs through `batch_slot` and `row_of`. The no-op
    `set_batch_owned` loop is gone (owned on the first gather or when row flight starts) and `rows` became `stepped_count` /
    `stepped_ships`. The command arrays are still sliced, now to the gathered ships only (none in a battle).
  - **Measured** (`scripts/bench_quick.sh`, `battle` 1000, seed 1, idle machine): flight stage median 3.89 ms before, 2.45 ms
    after (-1.44 ms); tick median 8.87 to 7.50 ms, p99 11.53 to 9.86 ms, so `battle 1000` now passes the 8 ms budget. In the
    battle 850 ships fly, 0 gathered; the gather readout fell from about 1.5 ms to under 0.25 ms.
  - **Tests:** `test_flight_parity_fight` (the recorded fixture) holds; new `test_ships_flying_from_their_rows_are_not_gathered`
    (`test_row_commands`); `test_flight_batch` (updated for `stepped_count`), `test_ai_driver`, the brain and tier files,
    `test_weapon_rows_battle`, `test_ai_think_time`, `test_engine_audio`, the ram files: 138 passing with `GUT_SLOW=1`. Rust
    `cargo test` passes; `cargo clippy` flags two lints in `turret_kernels.rs` (not touched here; CI does not run clippy). Fix round: a teleport before the step (`reset_to`, the tier's unpark) no longer marks the batch row stale (`test_sim_core` caught it in CI).

### M5-T32 L2: the hit resolver's bolt walk

- **Goal:** AC22 for L2. **Agent:** Opus.
- **What:** `pairs_core` drops the shooter's own hull, friendly and spent pairs; the native side returns only bolts with
  live hostile pairs, in launch order, with their columns; GDScript no longer builds bolt-sized arrays per tick. Per hit,
  the unused `hash([...])` and the `last_hit` string build go (the readout builds on read). The narrow phase in native is
  optional, measured first.
- **Done when:** the hit stage at `battle 1000` drops from 1.41 ms, hits are identical to the recorded fixtures, numbers
  in the Done notes.
- **Done (as built, 2026-11-08):**
  - **Built:** `ScsSimCore.hit_bolts(hull_keys, rock_keys, rock_count)`: from the broad phase's keys it drops the pairs of
    spent bolts and a bolt's pair with its own shooter's hull, and returns only the bolts left with a pair, in launch order,
    with their columns, their pair ranges, and the columns of just the hulls those pairs name (the paired hull's slot per
    pair). `HitResolver` walks those candidates; it no longer reads `bolt_columns` or `sweep_columns` (every bolt's and every
    hull's arrays) per tick, nor resizes and fills bolt-sized range arrays. Per hit, the unused `hash([...])` seed and the
    `last_hit` string go (`last_hit` is described when read). `pairs_core` is unchanged, so the broad-phase parity fixtures
    hold; the faction test stays in GDScript per surviving pair (the core has no hostility table). The narrow phase stays in
    GDScript: two pairs reach it per tick in the battle.
  - **Measured** (`bench_quick.sh`, `battle` 1000, seed 1): hit stage median 1.30 ms (after T31) to 1.01 ms (P3: 1.41);
    tick median 7.50 to 7.22 ms, p99 9.86 to 9.59 ms. In the battle about 400 bolts are in play, 30 broad-phase pairs, 2
    pairs tested; the resolver's gather fell from about 0.25 ms to the candidates' columns.
  - **Tests:** new `test_a_bolt_whose_only_pair_is_its_shooter_is_not_walked` (`test_hit_resolver`); `test_hit_resolver`,
    `test_hit_scale`, `test_last_hit_breakup`, the turret files, `test_weapon_rows_battle` (recorded), `test_weapons`,
    `test_bolt_rows`, `test_bolt_sync`, `test_hit_broad_phase`, `test_rocks_and_mines`, `test_flight_parity_fight`,
    `test_row_commands`, `test_sim_core`, `test_ai_driver`: 180 passing with `GUT_SLOW=1`.

### M5-T33 L3: the ram resolver

- **Goal:** AC22 for L3. **Agent:** Opus.
- **What:** first the quick wins (contacts return hull indices so `_index()` goes, `current_at` filled only for touched ids,
  rigid and layers tested from columns before `_hull()`), measured; then `RamTracker` in native (integer keys, no strings),
  which the per-tick-native rule asks for.
- **Done when:** the ram stage at `battle 1000` drops from 1.20 ms, ram results identical, numbers in the Done notes.
- **Done (as built, 2026-11-11):**
  - **Built:** `ScsRamTracker` (`native/src/ram_tracker.rs`, an engine-free kernel under the guard test, and its shell
    `native/src/ram_contacts.rs`) replaces the GDScript `RamTracker`, which moved to `tests/fixtures/ram_tracker.gd` as
    the reference. Pairs are keyed by their two body ids as integers; the last tick's index by id is built only on a
    tick with a contact or an open window. One call a tick (`contacts`) reads Jolt's contacts over the core's rigid rows,
    feeds the tracker and notes the pairs Jolt holds; it asks GDScript back only for the acceleration of a hull the
    flight step did not fly (`set_accels`) and the ram limits of a hull with a measured window (`land`). `swept_pairs`
    runs the broad phase (`kernels::ram`) and returns the pairs with the columns of just the hulls they name; it leaves
    out prop pairs and, for pairs Jolt does not hold, those the swept test's own first two rejects are sure to refuse
    (`ram::clearly_apart`: the bounding spheres; `ram::cannot_reach`: the first hull's sphere against the second's
    `ram_bounds`, read from the `Damageable`; both with room for the resolver's 32-bit sums). `RamResolver` no longer
    copies every hull's columns, keeps no per-hull array or index, tests each pair from the columns and builds a hull's
    Dictionary only for a pair it sweeps; the hull columns are read whole only on a tick where a contact ram lands or a
    ship is near a rock. `ScsRamPhase.contacts` is gone (`pairs` stays for the parity tests); `ScsSimCore.hull_count` is
    new. The rocks' grid (`sweep_cells.rs`, shared with the hit resolver): a look walks only the cells between the
    lowest and highest held cell of a level; a kept grid marks its held cells (`mark_cells`, a bit a cell) and lists a
    sparse level's hulls by x range; hulls far from a look are counted as work, not listed; only the pairs that pass the
    sphere test are sorted. Pairs, their order and `visited` are unchanged (the recorded fixtures hold).
  - **Not moved:** the shape-by-shape swept test (`_sweep_pair`, `ConvexSweep`) stays in GDScript: about one pair a
    tick reaches it in the battle after the native rejects. The contact read's cost is now two engine calls a rigid hull
    (`body_get_direct_state`, `get_contact_count`), which a cache could not replace without changing which hulls count
    as in play.
  - **Measured** (`bench_quick.sh`, `battle` 1000, seed 1, `reports/perf/t33_before` at a107cffe and `t33_after` at
    027956b5): ram stage median 0.577 ms before, 0.230 ms after (P3: 1.20); hit stage 1.013 to 0.926 ms (the rocks'
    grid); tick median 7.22 to 6.79 ms, p99 9.49 to 9.32 ms (8.85 to 9.38 over four runs). Per part, microseconds a
    tick (about 330 rigid hulls, 55 of them capitals, 1 000 rocks): gather 35-68 to 6; contacts 168-178 to 98; swept
    89-197 to 41-59 (9-27 broad-phase pairs, 1 left for GDScript); rocks 136-153 to 66-70.
  - **Tests:** Rust `cargo test --release --lib` 54 passing (16 new: the tracker's rules 8, the grid 4, the two pair
    rejects against the resolver's own tests 4). GUT: `test_ram_tracker` (22: the 20 ported to the native class, the
    native tracker beside the GDScript reference for 1 500 random ticks, a refused feed), `test_ram_scale` (8: new
    `test_a_ship_inside_a_large_hulls_bounding_sphere_but_out_of_reach_of_its_box_is_not_swept`), the guard test
    (`ram_tracker.rs` added). Focused run with `GUT_SLOW=1`, 374 passing: the ram files, `test_rocks_and_mines`,
    `test_tier_outcomes`, `test_core_state`, `test_core_threads`, `test_core_snapshot`, `test_row_commands`,
    `test_driver_step`, `test_bolt_rows`, `test_sim_core`, `test_weapon_rows_battle`, `test_flight_parity_fight`,
    `test_hit_resolver`, `test_hit_scale`, `test_hit_broad_phase`, `test_sweep_cells`, `test_rebase_in_play`, the pool,
    stand-in and run files.

### M5-T34 L5: the radar's dot buffers

- **Goal:** AC22 for L5. **Agent:** Sonnet.
- **What:** `ScsRadarPlot.plot` takes the screen transform and radii and returns the three buffers ready for the
  multimeshes; `factions` built only when read; no `slice` copy when the multimesh is larger.
- **Done when:** the HUD's frame cost outside the ticks at 1 000 ships drops, the radar tests pass unchanged, numbers in the
  Done notes.
- **Done (as built, 2026-11-11):**
  - **State found:** `RadarModel.plot` already ran natively (M4-T23); what stayed in GDScript was the painter's per-contact
    `_fill_dot_buffers` (12 indexed writes a contact, two with backings), the `buffer.slice` copy when a multimesh was larger,
    the per-contact `factions` loop in `RadarModel.plot`, and six `push` loops in the native shell.
  - **Readouts first:** `hud.radar_plot_us` (the plot call) and `hud.radar_paint_us` (`_draw_radar`), each smoothed over about
    twenty frames. The bench runs headless but the HUD still lays out and draws, so the readouts work there (`bench battle
    1000 10 warmup=2 seed=1`, then `wait 60; state hud`).
  - **Built:** `radar_kernel::dot_counts`, `grown_capacity` and `fill_dots` (engine-free, `Vector2` and `Color` added to the
    kernel's allowed imports) behind `ScsRadarPlot.dot_buffers`. `RadarModel.dot_buffers` returns a `RadarDotBuffers`
    (plain, rim and backing buffers with their counts). The painter passes its multimeshes' instance counts, so a buffer
    comes sized for its multimesh (doubling only when it must) and goes to the server whole: no `resize`, no `slice`. The
    selected and waypoint dots are placed by one transform each; the stalks stay a single transform of the plot's units.
    `RadarPlot.factions` is built when read (`bind_factions` keeps the order and indices); the native `plot` shell fills its
    buffers by slice instead of per-element `push`.
  - **Measured** (`battle` 1000, seed 1, three headless runs each, HUD readouts after `wait 60`; before = this task's
    readouts on the T35 code): the radar's plot call 323 to 374 us before, 77 to 117 us after; its paint 358 to 436 us
    before, 91 to 138 us after; together about 0.7 to 0.8 ms before, 0.17 to 0.25 ms after a frame. Tick median 5.86 to 5.93 ms
    before and 5.90 to 5.96 ms after (the radar is not in the tick); `bench_quick.sh t34_after battle` at 1 000: median 5.89 ms,
    p99 8.15 ms (T35's recorded run, 5.82 and 7.87 ms, is within the run-to-run spread). No separate `t34_before` bench run:
    the tick is untouched, and the readouts above are the before and after of the code that changed.
  - **Look:** `references/screenshots/T34 radar/` before and after in `battle 300` (the same frame, seeded) and the dogfight;
    the radars read the same. Final judgement of the look stays `(H)`.
  - **Tests:** 3 Rust tests in `radar_kernel/tests.rs` (63 pass in `cargo test --release --lib`); GUT `test_radar_plot` gains 3
    (native buffers against the old per-contact loop, with and without backings and a rim selection; buffer sizing; lazy
    factions), `test_sim_core`'s radar guard allows the new builtins and names `fill_dots`. The radar, HUD, target-menu,
    cockpit-screen and broadcast files pass unchanged.

### M5-T35 L8 and L9: native allocations and per-event scans

- **Goal:** AC22 for L8 and L9. **Agent:** Opus.
- **What:** the items listed in L8 (`index_rows` with a rank column and the `IdHasher`, interned name ids instead of cloned
  strings, faction indices in `snapshot`, a cached static block, the per-step Vecs and sets reused) and L9 (a body id to
  member index map rebuilt in `set_members`; `latest_target` pruned for freed bodies).
- **Done when:** the core's sync and the snapshot cost less at 1 000 (measured), Rust and GUT parity hold, numbers in the
  Done notes.
- **Done (as built, 2026-11-11):**
  - **Readouts first:** `core.core_sync_us` (the native `sync_in` call alone), `core.snapshot_us`, `core.select_us`, and
    `ScsSimCore.sync_parts_us()` (the tier's step, the bodies, the statics, the tier rows, the lookups). A bench sums them
    over its window and writes the means to `summary.json` under `core`. Readouts only.
  - **L8, built per item:**
    - *`index_rows`:* the hull rank is a column beside the rows (`row_ranks`), so no map of ranks is built; `row_of_id`,
      `row_of_handle`, `touched`, `seen`, `parked_since_sync`, `marker_at`, `slot_of`, `latest_target`, `accels` and the
      tier's `by_body` hash with `IdHasher` (`IdMap`, `IdSet`); the hull list is built in a kept Vec. The rows' id lookup
      sorts only the bodies and tier rows and merges the rocks' and mines' pairs, sorted once (`index_ids_around`).
    - *Names:* a row carries a `u32` name id; the lowered names live in a shared `NameTable` and the brains match a
      wanted name by its id (`rows_named`, `first_named`, the keeper). Display names are ids too, so a sync clones no
      engine string. Names no body carries are dropped once the tables pass twice the bodies plus 256.
    - *`snapshot`:* the faction and name columns are kept and made again only when a row's faction or name changed; the
      scan gets copies of its own. **Not built as listed:** faction indices are not sent. `ContactScan`, its GDScript
      readers and several test files read `_factions` as names, and the kept column already removes the per-call cost.
    - *Statics:* one ready block built in `set_statics`, appended whole each sync.
    - *Small items, all five:* the sweep grid's cell lists are pooled (`sweep_cells.rs`); the bolt step's `keep` flags,
      the tier ram's pair set and the weapon step's nine lists (plus `interceptors_of`) are kept between ticks;
      `resync_touched` asks the set, not a copied Vec.
  - **L9:** `members_by_body` (sorted, rebuilt in `set_members`) gives `note_hull` and `note_selection` a body's members
    by binary search. `set_members` drops `latest_target` entries of bodies that are neither a member nor a tier row.
  - **Beyond the list, found by the readouts:** the tier rows are appended column by column (122 to 10 us); `Rows` and
    `Bolts` copy into the job snapshot's held columns (`clone_from`; the derived clone allocated every column each tick);
    a hull with no active marker is asked for its activity only when its body is touched or first seen, as the markers
    are since M4-T35b (about 700 parked hulls cost four engine calls each a tick; the bodies' part 284 to 124 us).
  - **Measured** (`bench_quick.sh`, `battle` 1000, seed 1, three runs each; `reports/perf/t35_before` at 797819a8,
    `t35_after` at d09c4d7e), mean microseconds a tick:

    | | before | after |
    |---|---|---|
    | native `sync_in` | 722 | 255 (P3's core sync: 460) |
    | its parts: tier step / bodies / statics / tier rows / lookups | 53 / 400 / 35 / 122 / 96 | 52 / 124 / 23 / 10 / 30 |
    | `snapshot` (0.07 calls a tick here) | 47 a call | 21 a call |
    | think stage median (the job's snapshot copy) | 512 | 335 |
    | hit stage median | 917 | 775 to 790 |
    | targeting stage median | 157 | 88 |
    | tick median | 6 730 to 6 750 | 5 820 to 5 900 |
    | tick p99 | 8 760 to 9 160 | 7 870 to 8 060 |

    The ram and flight stages are unchanged (0.23 ms, 2.42 ms). What is left of the sync: three engine calls a body in
    play (pose and velocities) and the tier's step.
  - **Tests:** Rust `cargo test --release --lib` 60 passing (6 new in `native/src/rows/tests.rs`: the name ids, the
    merged id lookup against the plain one, the block append, the copy into held columns, the tier's column append
    against its row push). GUT `test_body_registry` 15 (4 new: the kept snapshot columns, names dropped, an event
    reaching only its body and a freed body's selection dropped, a parked hull not asked again until touched). Focused
    run with `GUT_SLOW=1`, 48 files, 431 passing: `test_core_state`, `test_core_threads`, `test_core_snapshot`,
    `test_row_commands`, `test_driver_step`, `test_bolt_rows`, `test_weapon_rows_battle`, `test_sim_core` (the guard's
    import lists take `IdMap` and `IdSet`), `test_brain_parity`, `test_brain_think_parity`, `test_tier_outcomes`, the
    tier, ram, hit, pool, stand-in, destruction and run files. `run_tests.sh --quick` 1 672 passing; the main-scene smoke
    clean.
  - **Open:** none. A caller that sets a hull's `destroyed` flag or a body's `process_mode` without the hull's signals
    or a visibility change must call `ContactScan.touch(body)` (architecture 18.24); the game's own paths all signal.

### M5-T36 L12 and L13: the smaller items and the constants table

- **Goal:** AC22 for L12 and L13. **Agent:** Sonnet.
- **What:** each L12 item as listed in the review (the tier's prune on removals, the bolt quarantine from the core's
  transforms, the far proxies' uploads, the light picks, the wing director's compare-before-assign, the HUD readout and
  silhouettes, the two group walks, the drivers' console vars, the output array, the latent `reach`, the duplicated maths).
  L13: a `#[func] constants()` on the core and one GUT test that compares every mirrored constant with its GDScript twin.
- **Done when:** each item is done or marked not worth it with a measured reason; the constants test passes.
- **Done (as built, 2026-11-12):** architecture §18.29.
  - **L12, item by item:**

    | Item | Outcome |
    |---|---|
    | Tier `_prune` every tick | Done: `TierDirector._prune` walks only when `SimCore.removals` changed |
    | Bolt quarantine under TAA | Done, native: `ScsSimCore.bolt_quarantine` (kernel `bolt_kernels::quarantine`, bit-identical in 64-bit over the 32-bit rows); measured 0.39 ms per 1 000 slots per frame in GDScript, no `duplicate`/GDScript loop left |
    | `FarFlashes` upload per `add()` / with zero flashes | Done: `add` only queues, the next `advance` uploads once; an empty, already-empty multimesh is not uploaded |
    | `FarHulls` `instance_count` per change | Not worth it: it changes only when the capital count changes (rare), and the exact-size buffer needs the exact count |
    | Light rig / picker `get_global_transform_interpolated` | Not worth it: only lit emitters pay it; `state lights` in `battle 1000` reads 30 candidates, `cost_us` 33 |
    | Wing director compare-before-assign | Done: the `AiContext` wing setters return on an equal value, so only a real change (a moving leader's link, an order) marks the pilot for the native push |
    | `main.gd` readout before `hud.visible`; silhouettes per frame | Done: `_update_bracket` tests `hud.visible` first; `Silhouette.wireframe`/`polygons` are cached per layout and aspect |
    | Two `get_nodes_in_group(Projectile.GROUP)` per tick | Not worth it: only one call per sync remains (the other is the delayed path), the group holds the player's bolts, beams and missiles only (NPC bolts are core rows); beams as owned rows is a larger task |
    | Drivers' console vars on enter/exit | Done: the first driver in the tree owns the `ai` entries; the other 999 register nothing |
    | `PackedFloat64Array` per ship per output read | Done: `group_levels` is filled in place |
    | Latent `reach: &[]` in `contact_field.rs` | Done: the core-attached view carries `rows.reach` |
    | Duplicated maths | Done: `weapon_kernels.rs` and `sim_core.rs` use `v3` (about 70 lines gone); the three compute effects share `ComputeUniform.make`. Not done: the PREDELETE scaffolding (each frees different RIDs) and the multimesh setups of `FarDots`/`FarFlashes`/`FarHulls` (formats differ); the "64-bit range" had no identifiable duplicate |

  - **L13:** `native/src/constants.rs` is one table of 32 numbers and `FlightModel.AXIS_SIGN`, served by `ScsSimCore.constants()`
    (the mirrored consts are `pub` now); `tests/unit/test_native_constants.gd` finds each GDScript twin through the global class
    list and fails on any difference or missing twin. `MUZZLE_OFFSET_M` has no GDScript twin and stays out.
  - **`battle 1000` (`bench_quick.sh`, seed 1, other agents working beside it, so a few percent is noise):** before tick median 5.88 ms, p99
    8.13 ms; after 5.50 ms, p99 7.62 ms. Stages: targeting 0.09 / 0.09, ai 0.41 / 0.40, resolvers 1.00 / 1.00, stand-ins 0.69 / 0.68
    ms; nothing moved beyond noise (the work done is per-frame and TAA-only, or a spawn cost). Results identical.
  - **Tests:** cargo `--lib` 66 (3 new: the quarantine kernel); GUT quick suite 1681 tests, all pass after the two guard
    allow-lists in `test_sim_core.gd` were widened (`use crate::v3::`, the test module's `use super::*;`); new
    `test_native_constants` 2; the quarantine and TAA mesh tests (17) are unchanged and pass on the native kernel; 20 focused
    parity/tier/wing/battle files with `GUT_SLOW=1`: 203 pass; main-scene smoke clean.

### M5-T37 L6 and L7: flashes and sounds at scale

- **Goal:** AC23 for L6 and L7 (the sound pass's share). **Agent:** Sonnet.
- **What:** L6: a ring buffer and a lit counter for the muzzle flash pool, and flashes and shot sounds culled beyond a range
  from the camera before they are made. L7: check what T19 and T28 left (the engine voices come from the core's query
  now); any per-pooled-ship audio node still walked every frame goes, so the per-frame audio work is linear in voices, not
  ships.
- **Done when:** work-count tests pin both; `battle 1000` frame time with sound on is recorded before and after.
- **Done (2026-11-12):**
  - **Built:** `ShotCull` (`src/weapons/shot_cull.gd`): flashes beyond 2 500 m of the camera and gun or turret sounds beyond
    3 000 m are not made (`MuzzleFlashPool.trigger` returns false and counts `culled`; `AudioDirector.play_shot` counts
    `shots_culled` and takes no voice). The flash pool is a ring (head, span, dead slots skipped by the head) with a `_lit`
    counter and ages from a pool clock, so a full pool shifts no arrays and the pass visits the ring's span. Readouts
    `frame.flashes_culled`, `audio.shots_culled`. L7: T19 and T28 had already left the per-frame audio work linear in
    voices (the existing `test_a_frames_engine_work_follows_the_voices_not_the_ships` pins it); nothing per pooled ship is walked.
  - **Measured** (`bench_quick.sh`, `battle` 1000, seed 1, one run each, headless so the flash pass and audio mixing do
    not run; "before" is the ring with the ranges set to infinity): tick median 5.64 ms to 5.48 ms, p99 8.17 ms to 7.50 ms.
    The effect is inside the run-to-run noise here; the gain is the work not done (a voice steal and a light per far shot)
    on a machine with a window. `reports/perf/t37_before`, `t37_after`.
  - **Tests:** new `test_shot_cull.gd` (5: far flash culled and counted, full ring caps at 256 and holds the light cap, the pass
    follows live flashes not capacity, `clear_for` leaves the ring consistent, the range maths); `test_audio_director.gd`
    +1 (a shot beyond earshot takes no voice); `test_muzzle_flash_pool` 4 and `test_engine_audio` 14 unchanged and passing.
  - **(H):** by ear and eye near the player: shots, flashes and engine hum sound and look as before; distant dogfights
    no longer thin out the near sounds.

### M5-T38 L14: test duplication and CI

- **Goal:** AC23 for L14. **Agent:** Sonnet.
- **What:** one `TestSteps` fixture for the copied `_ticks`, `_exec`, `_console` helpers (move the copies over in one pass);
  `test_core_state.gd`'s three identical `OLD_PATH_CASES` recordings collapsed to one; the always-pending balance tests
  (`test_m3_sandbox`, `test_dogfight`) out of the default run as a manual balance check; CI's Python tests in their own job
  and `assets/generated` cached on `hashFiles('tools/procgen/**')`; `run_tests.sh`'s smoke blocks through one helper and
  the lock paths in one place.
- **Done when:** the suite's totals are unchanged except the moved balance tests; CI is green on the push, with shard times
  in the Done notes.

- **Done (as built, 2026-11-12):**

  | L14 item | Outcome |
  | --- | --- |
  | `TestSteps` fixture for `_ticks`, `_exec`, `_console` | Done now: `tests/fixtures/test_steps.gd`; 54 test files (and one inner class) extend it and lost 41 + 11 + 10 copies in one pass. Two files whose `_ticks` meant something else were renamed (`test_m3_run`: `_wait_seconds`; `test_reaction_mass`: `_ticks_in`, the seconds-to-ticks one); the three files whose `_ticks(seconds)` returns a tick count, and the two that step the flight model directly, keep their own (a different signature). |
  | `OLD_PATH_CASES` collapsed to one recording | Already done by M6-T18 (cherry-picked in 2c76787): `OLD_PATHS_CASE`, one recording. |
  | Balance tests out of the default run | Already done by M6-T17: `tests/fixtures/balance_tests.gd`, `tests/balance_suite.txt`, `--balance`/`--full`; confirmed that `test_dogfight` and `test_m3_sandbox` do not run in the standard tier. |
  | CI: Python tests in their own job, `assets/generated` cached | Done now: job `python` (`unittest discover`), `PYTHON_TESTS=0` on the three GUT shards; `assets/generated` restored on `assets-<os>-py3.12-hashFiles('tools/procgen/**')` in the Python job and the shards, `gen_assets.sh` only on a miss. The key covers T40's low/high civilian texture sets because they are generated from `tools/procgen`. |
  | `run_tests.sh` smoke blocks through one helper | Done now: `main_run` in `scripts/lib_tests.sh` replaced 23 copies of the run, `cat`, exit-code check (the file lost about 190 lines). The expect/reject lines stay per block: they are the checks. Verified by running every smoke block (exit 0). |
  | Lock paths in one place | Done now: `scripts/lib_locks.sh` (`GODOT_LOCK`, `BENCH_LOCK`, `GPU_LOCK`, each overridable) sourced by the seven scripts that hard-coded them. |

  - **Totals:** no test added or removed. `--quick` GUT before and after: 111 scripts, 1 686 tests, all passing; the 56 touched
    scripts run focused with `GUT_SLOW=1`: 740 tests, 8 091 asserts, all passing. Python untouched.
  - **CI (run 43179401269, green, cold asset cache):** python tests 22.9 min (it generates the assets on the miss), GUT shard 1
    14.9 min, shard 2 27.4 min, shard 3 25.3 min. Shard 1 fell from about 24 min (it no longer runs the Python tests); shards 2
    and 3 are now the longest because the heavy files fall on them in path order (a rebalance by cost is a later option). The
    runs after this one restore `assets/generated` from the cache, which removes the asset generation from every job.

### M5-T39 Civilian colours and hull sheen

- **Why (maintainer, 2026-11-08):** the civilian ships look much whiter than in the show, and every hull (the Starfury and the
  raider too) reads as flat paint although they are metal: add a small reflection or sheen.
- **Cause:** the civilian schemes were read off lit screen captures and used as albedo, so the game's key star and ambient
  light them a second time; reflections were off (`REFLECTION_SOURCE_DISABLED`) and the paint matte, so nothing shone.
- **What:** `capture_albedo` (`tools/procgen/core/color.py`) turns a capture colour into the albedo that shows it on a lit
  face, from a measured grey ramp; the four civilian styles paint with it (emission unchanged). `settings.hull_sheen` (0.25)
  puts a clear coat on every hull's paint (`MeshAssets`, the livery shader) and turns on the nebula's reflection; 0 is the old
  flat look. Rocks take no sheen.
- **Done when:** the civilian generators rebuilt and their tests green, before and after sheets in
  `references/screenshots/Civilian colours and hull sheen/`, and the maintainer's OK on the look (H) before the commit.
- **Done (as built, 2026-11-08, on the maintainer's machine):**
  - **Measured:** a grey of albedo #A4A7AA showed #EEE9DF head-on and #D8D4CA at 50 degrees (key star 1.5, ambient 0.3,
    filmic). A grey ramp at 45 degrees gave the table in `core/color.py`; `reports/colour_probe/` has the probe (gitignored).
  - **The maintainer's picks (three rounds of sheets):** the calibrated paint still read too light, so `PAINT_DARKEN` 0.5
    (option C) with `settings.ambient_level` 0.3 -> 0.1 (darker shadow sides, as in the show); the Brakiri pods painted
    #C8CCB4 directly, lighter than the written #ABAE9A, so they stay pale in shade; sheen 0.25 approved. The generic staggered
    plating is off on every civilian style (`extra["panel_grid"]` 0: no seams, tint patchwork, hatches or rivets; wear and
    grime stay) until T40 draws seams from the show.
  - **Code:** `capture_albedo` (with `darken`) in the four civilian styles and the Saturn pod tops; `settings.hull_sheen`
    through `MeshAssets` (clear coat on `StandardMaterial3D`, `sheen` on `hull_livery.gdshader`) and the sky's reflection in
    `SpaceEnvironment` (radiance 128); rocks pass `sheen` false.
  - **Tests:** Python 356 (the civilians, `test_color`'s calibration, `test_textures`' grid switch; absolute brightness cuts
    in the paint tests lowered to the darkened colours), GUT `test_environment` 19, `test_mesh_assets` 6 (the sheen),
    `test_settings_schema` 25, `test_settings_menu_model` 15, `test_textured_hull` 4, `check_scripts` 610.
  - **(H):** approved by the maintainer (2026-11-08). A saved `ambient_level` overrides the new default.

### M5-T40 Civilian panel seams from the show

- **Why (maintainer, 2026-11-08):** the generic brick grid looked terrible; seams suit some ships, but they must follow the
  show's references.
- **Needs:** the maintainer's captures per ship (Saturn family: Achilles.jpg, Red Star 9.jpg, Epsilon.JPG; Skylark; Narn
  transport; Brakiri Bokmai; Brezebel), which are not on this machine.
- **References given (maintainer, 2026-11-12):** 42 images in `references/T40 seam references/` (gitignored, never
  committed). For the civilians: `saturn 8 texture close up`, `EA skylark texture close up`, the `ea transport` close-ups (the
  Earth Alliance civilian look), the Narn ones (`narn station`, `narn cruiser`, `narn heavy cruiser`, `narn base`, `narn frazi
  fighter`) for the Narn transport, `centauri fighter close up` for the Brezebel; none shows Brakiri styling. The rest
  (Babylon 5 station, Omega, Hyperion, Warlock, Starfury, Minbari, Vorlon, Shadow, Vree, raider carrier and battle wagon) are
  for later ships and the station (M7, M12, M13).
- **Phase 1 answers (maintainer, 2026-11-12):** option sheets A (major seams only), B (reference density, hatches, ribs) and C
  (B plus mixed-size plates with per-plate tone and sheen, joint grime, raised hatches) were shown for all nine hulls.
  (1) A graphics setting picks the texture detail: **low = A, high = C**, for every civilian. (2) C's per-plate tone (5 to 9 %
  of value, up to 17 % on the Narn crescent) is acceptable, not a colour change. (3) The Saturn 8s' wider lines are good; no
  4096 atlases. (4) Turrets, trusses, arms, struts, antennas and nozzles stay plain for now. (5) Narn war-paint stays out as a
  paint scheme, but the **Narn transport takes the Frazi fighter as its model**: the consistent Narn construction, with the
  fighter's pattern of smaller rectangles in slightly varied colour across the hull. (6) The references are inspiration only,
  never reused or traced. (7) No re-shoot needed. Phase 2 commits the layouts with tests (per part: feature counts and
  positions, mirror symmetry, minimum plate size, determinism) and removes `panel_grid` and the civilian path of `plating_for`.
- **Note (maintainer, 2026-11-12):** the texture detail setting is meant for every ship, but only the civilian hulls have low and
  high texture sets so far. The Starfury, the raider and the allies keep their one set (the setting changes nothing on them) until
  their surfaces get the same A/C treatment; the setting's description says so, and `docs/roadmap.md` carries it as a follow-up.
- **What:** per ship, the seams and hatches read off the captures (where plates break, which way they run, ribs on the
  pods), drawn as per-part seam layouts instead of `plating_for`'s staggered grid; a look sheet per ship for the
  maintainer before the generator commits.
- **Done when:** each civilian's seams match its references (H), tests pin the layouts, and `panel_grid` is gone or unused.
- **Done (as built, 2026-11-12, on the maintainer's machine):** per-part surface layouts and two texture sets a hull
  (architecture §18.30; the reads and the layouts are in `docs/assets-civilian.md`, "Surface layouts").
  - **Procgen.** `core/seams.py` (features as distances on the surface: cuts, spokes, hoops, paths, hatches with louvres,
    mixed-size plating; a layout follows its part through moves, turns and mirrors) and `parts/layouts.py` (the five
    generators' layouts). The baker draws them into the albedo, normal and ORM maps. Every civilian hull and the Bokmai pod
    are written with the full set and a `_low` set (major seams only); meshes, chunks, hardpoints and the emissive map are
    unchanged, so fidelity was not re-scored. `panel_grid` is gone from the styles; `Atlas.grid` turns the generic plating
    off for hulls with layouts, and they compute no `plating_for`.
  - **The setting.** `settings.texture_detail`, "Ship texture detail" (`low` or `high`, default `high`, Video group of the
    settings menu), for every ship. It is live: `MeshAssets` swaps the maps on the hulls already in the scene. The loading is
    general (paint, livery and glass materials): a hull with one set ignores it, and only the civilians have both for now.
  - **Narn.** Reworked after the Frazi fighter: framed panels, a panel inside a panel, and small rectangles in slightly
    varied shades (10 % on the green, 7 % on the box) in place of phase 1's larger 17 % mosaic. GPU check on the RX 6950 XT
    (Forward+, 103 fps, 54 draw calls in the sheet scene): `references/screenshots/T40 seams/narn_final.png`, low and high.
  - **Kept from the sheets, changed since.** Barrel and disc plating now mirrors across the centre plane (it did not on the
    sheets), the Skylark's dome petals moved 7.5 degrees to be symmetric, and the Saturn 3's cross beam is plain. The
    Bokmai's arms and fork struts keep their layout: they are hull limbs, not structure (confirmed by the maintainer, 2026-11-12).
  - **Tests.** Python `test_seams` 34 (features, plating never under its least size, determinism, mirror symmetry, a layout
    following its part, every part's feature counts per level pinned, key positions against the parts' own dimensions, the
    baked maps, the low set's files and manifest entry), `test_textures` (the grid switch) and the five ship suites. GUT
    `test_civilian_meshes` 7 (the setting picks each hull's set and swaps a loaded hull's maps; a one-set hull ignores it;
    a shader material takes the set too).
  - **(H):** the look of each hull at `high` and `low`.

### M5-T41 Rock rams by the speed into the rock

- **Why (maintainer, 2026-11-08):** ram damage should follow the impact's speed. Rocks did, but by the ship's whole speed, so a
  Starfury grazing a rock at 100 m/s died as if it had flown straight in.
- **Done (as built, 2026-11-08):** `RamResolver.head_on` cuts a ship's velocity to the part along the rock's outward normal at
  the contact point (`RamMath.closing_speed`) before the swept ram rule charges it; head-on hits are unchanged, a scrape costs its
  closing speed and the motion along the surface costs nothing. Ship-to-ship rams are unchanged. Tests: `test_ram_math` (closing
  speed: head-on, scrape, along, away), `test_rocks_and_mines` (a drone at 40 m/s along and 3 m/s into a rock is unhurt; checked to
  fail without the change; the head-on 40 m/s ram stays lethal), and the ram files (`test_ram_damage`, `test_ram_scale`,
  `test_ai_ram`, `test_ram_contact_columns`, `test_asteroid_belt`): 50 passing.

### M5-T42 Pause backdrop: a cinematic camera behind the pause menu

- **Why (maintainer, 2026-11-08):** the pause menu sits over a frozen frame. A slow camera move around the player's ship
  behind the menu makes the pause feel like part of the game instead of a stop.
- **Track:** A. **Agent:** Sonnet. **Depends on:** T02 (the pause menu), T08 (the rig's `CINEMATIC` mode and its shot
  hand-back).
- **The path.** The suggested move is a figure 8 around the ship, and it is the default: a lemniscate (Gerono's, so the
  two lobes sit either side of the ship) laid in a plane tilted about 20 degrees off the ship's top, at about 1.3 times the
  chase distance, so the camera passes the nose and the tail in turn and dips under and over the hull; one loop in about
  60 s, eased so the crossings are not faster than the turns; the camera always looks at the ship's chase anchor with a
  small lead. The frame's panels fill nearly the whole screen (the screenshot of 2026-11-08 in
  `references/screenshots/front_end_and_pause_menu_as_is/`: options and pad left, objectives right, a 25 px gutter), so
  the ship is framed in the right half, behind the objectives panel's empty space, and that panel's ground becomes
  mostly see-through (text kept on a dark band) while the backdrop runs. Other moves the task
  may offer at the look check, each a different `PauseOrbitPath`: a plain slow orbit with a gentle rise and fall (the
  safest), a Lissajous path (a figure 8 that drifts so no two loops repeat), or a slow cycle of three or four held "beauty"
  angles (front three-quarter, top-down on the wings, behind the engines) with long dissolves. The maintainer picks (H).
- **How:** a pure `PauseOrbitPath` (`RefCounted`) gives the camera's ship-local pose at a phase in [0, 1); the rig plays
  it through its cinematic camera with process mode always, since the tree is paused (the frames' `delta` still comes
  in; nothing reads the wall clock). On open it blends from the camera in use (cockpit or chase) to the path over about
  1 s, starting at the phase nearest the current camera so the first move is short; on Resume it blends back and the rig
  returns to the mode it left (T08's hand-back). Settings, Controls and their sub-pages keep it running; Restart and Quit
  to menu cut it. The pause menu's 0.6 dim becomes lighter (about 0.3) with the options and pad panels kept dark, so the ship
  reads on the right and the text stays legible. The flight HUD (readouts, radar, wing list) shows through the menu today;
  it hides while the backdrop runs and comes back on Resume. Paused during a mission cinematic: the shot holds and no orbit runs.
  The world is paused, so no rebase can happen mid-path; the path is ship-local anyway.
- **Settings and console:** `settings.pause_backdrop` (bool, `camera`, default on; off is today's still frame) and
  `settings.pause_backdrop_speed` (loop time); `pause_menu` provider keys `backdrop` (on, off or still) and `backdrop_phase`;
  `info.md` updated.
- **Tests first:** `test_pause_orbit_path` (the loop closes, position and direction are smooth across the seam, the camera
  never comes inside the hull's bounding radius plus a margin for the Starfury and a Saturn 8, it always faces the
  target, the phase nearest a given pose); `test_pause_menu` gains: the backdrop runs while `get_tree().paused`, Resume
  restores the mode and the pose, no player ship gives the still view, the setting off gives the still view.
- **Done when:** AC24, the tests pass, and screenshots of three phases in `references/screenshots/Pause backdrop/` for
  the maintainer's look check (H).
- **Done (2026-11-12):**
  - **Built.** `PauseOrbitPath` (pure, `src/camera/pause_orbit_path.gd`) and a backdrop mode in `CameraRig` (`start_backdrop`,
    `stop_backdrop`, `chosen_mode`) that plays it on the cinematic camera while the tree is paused (the rig goes to process mode
    always for as long as it runs). `Main` starts it on the pause menu's `opened` and stops it on `resumed`; the flight HUD
    hides meanwhile. Console: `pausemenu [on|off]` (opens or closes the menu), `camera.backdrop`, `camera.backdrop_phase`;
    settings `pause_backdrop` (on) and `pause_backdrop_loop_s` (30 s, 10 to 120).
  - **Choices.** The move is a circle around the ship that rises and dips twice per loop (a vertical figure 8: seen from the side
    an 8, and its crossing is off to the side, so it never comes near the hull), at the larger of 1.3 times the chase distance and
    2 times the hull's bounding radius, about 20 degrees of tilt, aimed a little ahead of the ship and pushed aside so the ship
    sits in the right half. It blends in over 1 s from the current camera, starting at the nearest phase. Resume cuts back to
    the mode left with the chase camera snapped to the ship (the pose is exactly the one the player left; there is no blend
    back). A shot playing, no ship or the setting off give the still frame. Not for the radial menus. The `settings.pause_backdrop_speed`
    name became `pause_backdrop_loop_s`, and the provider keys live on `camera`, not `pause_menu` (T45 owns that file).
  - **Not done.** The lighter dim and see-through objectives ground (the frame's ground is T45's file): the panels still cover
    most of the ship in a 960x540 frame. Left as a follow-up for the look check.
  - **Tests.** `test_pause_orbit_path` (6: closed, seam smooth, clearance for a Starfury and a Saturn 8, nose and tail, faces the ship,
    nearest phase); `test_pause_menu` +5 (runs while paused and Resume restores the view and HUD, sub pages keep it, setting off,
    no ship, cockpit comes back); `test_camera_rig` provider keys. Screenshots in `references/screenshots/T42 pause backdrop/`.
  - **(H).** Whether the move looks right and the panels hide too much of the ship; the loop time; the pick between this and the
    alternatives (plain orbit, Lissajous, beauty angles).

### M5-T43 Target preview: a wireframe of the highlighted entity

- **Why (maintainer, 2026-11-08):** in the target menu's second level (the entries of a category, T25) a name and a range
  do not say which ship it is. A small turning wireframe of the highlighted entity, with its health and distance, shows
  at a glance what the pick is.
- **Track:** A. **Agent:** Opus. **Depends on:** T25 (the menu and its second level; if T25's concept stop picks a layout
  without a second level, this task follows the list the pilot scrolls through to pick a ship).
- **The look.** A panel vertically centred on the side of the screen opposite T25's radial menu (the menu on the left,
  the panel on the right by default), clear of the reticle, the wireframe about 256 px square at 1080 lines and scaled with the UI at 4K. The entity in the HUD's green, drawn as lines on a dark
  ground, turning slowly (about 15 degrees per second) about its own up axis with a fixed view from about 20 degrees
  above, framed by its bounding box so a Starfury and a Saturn 8 both fill the panel. Only the lines on the side facing
  the viewer show (hidden-line removal); the far side's lines are hidden, not dimmed.
- **How:**
  - **Edges, not triangles.** A raw triangle wireframe draws every diagonal of every flat panel and turns a hull into
    noise. `FeatureEdges` (pure, `RefCounted`) takes the entity's lowest-detail mesh that still reads (LOD2, or LOD1 for
    small hulls) and keeps only the creases (edges whose faces meet at more than about 25 degrees, with welded vertex
    positions) and the open borders, as a `PRIMITIVE_LINES` mesh; built once per hull id on first highlight and cached.
    If building it on the largest hull costs more than a frame's slack (measure; about 5 ms), the edges move into procgen's
    output contract as a written file instead.
  - **Hidden lines.** The panel is a `SubViewport` with its own `World3D` (nothing from the game world leaks in): the
    solid mesh is drawn first in the ground colour, writing depth, pulled back a little along its normals, then the
    lines on top with the depth test, so the far side's lines fail it.
  - **The silhouette.** Rounded hulls (the Saturns' tanks, the Narn's drum) have soft outlines with no crease to draw, so
    an edge-detect pass on the solid mesh's depth in the same viewport draws the outline. Two draws and one pass; nothing
    else enters that world.
  - **Cost.** The viewport updates only while the second level is open (`UPDATE_DISABLED` otherwise); the entity's data
    is read once per highlight (the world is paused while the menu is open), never for the whole list.
- **Below the wireframe, at most four lines:**
  - **Kept (worth the space):** the ship class or kind (`Starfury`, `Raider`, `Saturn 4 tanker`, `Nav buoy`); the hull bar
    (the HUD's target bar, green to red, with a shield bar only if the entity has shields); the distance (the HUD's m or
    km format); the closing speed, signed (`+120 m/s` closing, `-40 m/s` opening), which is what the pilot needs to judge
    an intercept and what `targeting` already computes; and the faction as one word in the HUD's IFF colour, because the
    menu's categories mix civilians, allies and hostiles.
  - **One flag:** `ATTACKING YOU` when the entity is in the player's attacker memory (or attacking the escort in the
    mission), since that is the question a pick is usually answering.
  - **Left out as clutter for now:** the weapon list (every fighter carries the same few guns; it matters with M12's
    capitals, where T25's sub-target level shows turrets on the wireframe itself), the full relative velocity vector, the
    entity's own target when it is not the player, its orders, and cargo (the Bokmai's pods show on the wireframe already).
  - The concept sheet of T25 can carry this panel; if the maintainer wants a field back, it is one line in
    `TargetPreviewModel`.
- **Entities without a hull** (nav points, jump points): their marker icon instead of a wireframe, no bar. A rock: its
  wireframe, no bar. An entity destroyed while highlighted: the panel says `DESTROYED` until the highlight moves, and
  T25's rule for the list applies.
- **Console:** provider `target_preview` (entity, hull id, edge count, visible, cache size); `info.md` updated.
- **Tests first:** `test_feature_edges` (a cube gives 12 edges; a quad split into two triangles gives its 4 borders and
  no diagonal; the crease angle; welded seams give no false border; deterministic order); `test_target_preview_model`
  (the lines for a fighter, a civilian, a buoy, a rock; distance and closing-speed formats; the attacker flag; hull and
  shield fractions); an integration test that highlighting an entry sets the preview's entity and that the viewport is
  disabled while the menu is closed; the edge build timed on the Saturn 8.
- **GPU (oscar or the main machine, labelled):** the panel's frame cost and draw calls with the menu open in a 300-ship
  battle, `state render` before and after.
- **Done when:** AC25, the tests pass, and screenshots of a Starfury, a raider and a Saturn 8 in the panel in
  `references/screenshots/Target preview/` for the maintainer's look check (H).
- **Done (as built, 2026-11-11, on the maintainer's machine):**
  - **Built:**
    - **The panel** (`TargetPreview`, a `CanvasLayer` on the ring's layer 45, so above T44's blur): vertically centred at
      the side opposite the ring, 552 x 624 px at 1080 lines, scaled with the ring. It shows while the second ring is
      open and follows the highlight; on the first ring and with the menu closed it is hidden.
    - **The wireframe** (`WirePreview`, a `SubViewport` with its own `World3D`, 504 x 300 px at 1080 lines, MSAA 4x): the
      hull turns at 15 degrees a second about its up axis under an orthographic camera 20 degrees above, sized from the
      bounding box so the hull stays inside the view through the whole turn (`WireFraming`). Per part two draws (the solid
      mesh for depth, then its feature edges with the depth test) and one outline pass on the depth buffer.
    - **The edges** (`FeatureEdges`, `FeatureEdgeJob`): creases over 25 degrees, open borders and edges of three or more
      faces, vertices welded at 1 mm; found once per mesh and kept for the session.
    - **The lines** (`TargetPreviewModel`, Q44's approved set): name in the IFF colour; class and faction; hull bar with
      percent; range; closing speed, signed. A hull with pod mounts adds `CARGO PODS 2 of 3`. A beacon shows `Nav buoy`
      and no hull bar. An objective shows its text and range, and its actor's wireframe when it names a ship in play (a
      diamond for a bare place). `ATTACKING YOU` in red over the drawing. No weapons, absolute speed or heading. Each
      kind's rows are one list in `TargetPreviewModel.FIELDS`.
    - **Console:** provider `target_preview`; `targetmenu highlight <entry>` points at an entry without picking it. Both
      in `info.md`.
  - **Changed from the plan:**
    1. The edges come from the full mesh, not LOD1 or LOD2: the generator writes no LOD meshes any more (the importer
       builds index levels inside the mesh), and the full mesh gives clean creases.
    2. The edge search costs more than a frame on every ship (table below), so it runs 2 ms a frame (`FeatureEdgeJob`)
       instead of moving into procgen's output contract: no new asset file, no regeneration. The outline shows at once
       and the creases follow within 4 to 28 frames, the first time a hull is highlighted in a session.
    3. The lines are pulled toward the camera (0.6 % of the hull's radius, in view space) instead of the solid being
       shrunk along its normals: split normals at hard edges would open cracks in a shrunk solid.
    4. The outline pass measures the bend of the depth across a pixel, not its plain difference, so a steep flat face
       draws nothing and the line is one pixel wide.
    5. The panel is the mockup's 552 x 624 px with a 504 x 300 px drawing, not "about 256 px square": a wide drawing
       suits long hulls.
    6. `DESTROYED` is not built: the game is paused while the menu shows, so nothing can be destroyed while highlighted.
    7. Rocks are not in the candidate list, so there is no rock wireframe.
  - **Assumptions (say if any should change):**
    1. An unknown contact shows `NO ID` in grey in the drawing's place, with `UNKNOWN`, `No transponder`, range and closing
       speed: no generic silhouette, since any hull shape would suggest a class.
    2. `NONE` keeps the panel up with `NONE` and what picking it does (`Clears the target` or `Clears the waypoint`), and
       no drawing, so the panel does not blink as the stick crosses the down slice.
    3. `ATTACKING YOU` means the ship's pilot has the player selected and is in an attack (`attack`, `ram`, or `aggro` in
       its attack state). The player has no attacker memory of its own, and a ship in the low-attention tier is never
       flagged. "Attacking the escort" is not flagged.
    4. Class names are a table in `TargetPreviewModel.CLASS_NAMES` (`Aurora Starfury`, `Delta-V raider`, `Saturn 8 tanker`,
       `Bokmai hauler`, `Brezebel transport`, `Nav buoy`, ...); an unlisted hull reads as its asset id.
    5. A civilian of the pilot's own faction has its name in the friendly blue (the IFF colour), though it is listed
       under Civilian in the ring's orange.
    6. The wireframe shows the hull and a Bokmai's mounted pods; turrets are left off.
    7. The turn starts at yaw 125 degrees (from ahead and well to one side) each time the highlight moves.
    8. The panel's ground is the mockup's 72 % dark green; until T44's blur the HUD's drift ring shows faintly through its
       lower right corner.
  - **Measured (RX 6950 XT, Forward+, RADV, Wayland):**

    | Hull | Triangles | Edges | In one go | In the game, sliced | Longest frame's share |
    |---|---|---|---|---|---|
    | Nav buoy (smallest) | 776 | 296 | 0.8 ms | 1.4 ms, 2 frames | 1.3 ms |
    | Raider | 5 700 | 1 999 | 5.5 ms | 8.5 to 10.1 ms, 4 frames | 3.0 to 4.5 ms |
    | Bokmai with 3 pods | 9 284 + pod | 5 726 | 8.9 ms (hull) | 15.1 to 15.5 ms, 9 frames | 2.7 to 3.3 ms |
    | Starfury | 34 428 | 11 320 | 32.7 ms | 36.4 to 36.8 ms, 17 frames | 4.2 ms |
    | Saturn 8 tanker | 52 890 | 6 332 | 49.3 ms | 58.7 to 64.6 ms, 26 to 28 frames | 5.0 to 8.3 ms |
    | Saturn 8 transport (largest) | 55 382 | 11 648 | 51.8 ms | 55.8 to 56.1 ms, 26 frames | 3.7 ms |

    The longest share is the frame that reads the mesh back from the GPU (`Mesh.surface_get_arrays`, one call, 3 to 9 ms
    on the GPU, 1 ms headless); every other slice is 2 to 3 ms. A hull already seen costs nothing.
    Per frame with the panel showing: 0.06 ms of CPU in the dogfight and 0.15 ms in `bench battle 300`
    (`target_preview.frame_ms`), 9 draw calls. Closed or on the first ring: nothing (hidden, not processing, the
    viewport `UPDATE_DISABLED`: test).

    | Scene (window) | Closed | First ring | Second ring with the panel |
    |---|---|---|---|
    | Dogfight (1200x675 and 1920x1080) | 145 fps, 41 draw calls | 145, 71 | 145, 80 |
    | `bench battle 300` (1200x675) | 145, 88 | 145, 118 | 144, 127 |
    | Civilian showcase, Saturn 8 tanker (1920x1080) | 145, 53 | | 145, 90 |

    The frame rate is the 144 Hz cap throughout, so the GPU cost shows only as draw calls.
  - **Tests:** `test_feature_edges` 9 (the cube's 12 edges, the flat panel's diagonal dropped and borders kept, the crease
    angle, welded seams, the order, slivers, a three-face edge, a mesh and its line mesh, a sliced job giving the same
    lines), `test_wire_framing` 5 (the turn, both hulls inside the view at every angle and aspect, the camera, the
    panel's place at five window shapes, the rows inside it), `test_target_preview_model` 11 (a fighter, the formats, the
    attacker flag and rule, an ally, a civilian with and without pods, a buoy, an unknown contact, an objective, none,
    every catalogue hull named), integration `test_target_preview` 10 on the main scene (the highlight sets the entity,
    read once per highlight, the stick moves it, the viewport off while closed and on the first ring, the turn behind
    the pause, unknown, a buoy, an objective, the flag, the console, the largest hull's edges in slices), and one more in
    `test_civilian_ships` (a Bokmai's pods in the drawing). The quick tier passes (109 scripts, 1 664 GUT tests, 292
    Python tests), `test_civilian_ships` 6, `test_target_menu` 16 and 12; main-scene smoke runs show no errors or leaks.
  - **(H):** the screenshots in `references/screenshots/T43 target preview/` (an enemy raider, an ally Starfury, a Saturn
    8 tanker and transport, a Bokmai laden and empty, an unknown contact, a nav buoy, `NONE`; 1920x1080): whether the
    wireframes read as the ships, and whether the dense spots (the Starfury's pods, the Saturn's container ends) want
    fewer lines (a higher `FeatureEdges.CREASE_DEG`, or short edges dropped); the turn's speed and the 20 degree view;
    how small a long hull gets when it turns end-on; the outline's one-pixel line beside the anti-aliased creases;
    readability at 4K; the class names (assumption 4); the `NO ID` placeholder (assumption 1); the panel over the HUD's
    lower right until T44.

### M5-T44 Focus pull when the target menu opens

- **Why (maintainer, 2026-11-08, corrected 2026-11-09):** while the target menu is open, the play view goes out of
  focus and the target menu and the target information (T43's wireframe and its lines) are the only things in focus,
  so the eye goes to the pick. It belongs to the radial framework, so the comms menu (T46) gets the same pull.
- **Track:** A. **Agent:** Sonnet. **Depends on:** T25 (the radial menu, its open and close), T43 (the target
  information panel, which must sit above the blur).
- **What:** on open, everything except the menu and the target information eases from sharp to slightly out of focus
  over 0.2 s: the 3D view and the flight HUD alike (readouts, brackets, radar, wing list). On close (A picks the target,
  or B backs out of the first level) it eases back to sharp over 0.2 s. A reopen during a pull reverses from where it
  is, never jumps. "Slightly" means a small radius and perhaps a light dim, so the frozen fight behind stays readable as
  shapes. The game is paused while the menu is open (T25), so the pull runs with process mode always on the frame
  `delta`.
- **How:** a pure `FocusPull` (`RefCounted`) gives the blur amount from the time since the last open or close
  (smoothstep, reversible mid-way). The blur is one full-screen `ColorRect` with a screen-reading blur shader (mipmapped
  screen texture, or two separable passes if the mips look blocky) on a `CanvasLayer` between the HUD's layers and the
  target menu's, so it blurs everything drawn under it (the 3D view and the HUD) and nothing drawn over it (the menu and
  the target information). Depth of field is not used: it would blur only the 3D view and leave the HUD sharp. The pull
  runs on frame `delta`; with the menu closed and the pull at rest the rect is hidden, so it costs nothing. The console
  and the pause menu draw above it.
- **Settings and console:** `settings.target_menu_blur` (0 to 1, `hud`, default 0.35; 0 is off); a `focus` key on the
  target menu's provider (the blur amount now); `info.md` if a command is added.
- **Tests first:** `test_focus_pull` (0 to full in 0.2 s, back in 0.2 s, a reversal from the middle, rest states); an
  integration test that opening and closing the menu shows and hides the blur, that the blur layer sits above every HUD
  layer and below the menu and the target information, and that the setting at 0 never shows it.
- **GPU:** frame cost with the pull at full on oscar (labelled) and, when it is on hand, the main machine.
- **Done when:** AC26, the tests pass, and a short frame sequence of the pull in `references/screenshots/Focus pull/` for
  the maintainer's look check (H).

- **Done (as built, 2026-11-11, on the maintainer's machine):**
  - **Built:** `FocusPull` (pure, `src/hud/focus_pull.gd`: progress at 1/0.2 s toward open or closed, smoothstep amount, reversal
    from where it is), `FocusPullView` (`CanvasLayer` 44, one `ColorRect` with `focus_pull.gdshader`: a mip of the screen read
    with nine taps, plus a dim) and `RadialMenuView` owning it, so the comms menu (T46) gets the pull by using the view. The pull
    is a sibling of the view, not its child, so it keeps easing back after the view hides. It runs on real frame time
    (`delta / Engine.time_scale`) with process mode always; at rest the layer is hidden and does not process.
    `settings.target_menu_blur` (hud, 0..1, default 0.35; 0 never shows it) sets the radius (up to 3 mip levels) and the dim
    (up to 35 %); the console's `target_menu.focus` gives the amount.
  - **Choice:** T25's fixed 25 % dim is removed: the pull dims by itself (about 12 % at the default). At setting 0 the view
    is neither blurred nor dimmed (the ring's plate carries the menu).
  - **Layers:** blur 44 sits under the radial menu and `TargetPreview` (both 45) and over the HUD (40) and comms menu (42);
    the debug overlay (50), console and pause menu stay sharp, as the screenshot shows.
  - **Measured (RX 6950 XT, Forward+, 960x540 window):** dogfight 59 draw calls closed, 89 with the first ring open (ring,
    preview, blur), 59 again after; `bench battle 300` 102, 132 open, 103 closed; the frame rate stays at the 144 Hz cap with
    the menu open (the sampled `fps` reads a window average: 126 to 145). GPU frame time 0.4 to 0.8 ms open. Hidden: nothing.
  - **Tests:** `test_focus_pull` (5: rest, open in 0.2 s, close in 0.2 s, reversal mid-way, negative step) and two in
    `test_target_menu` (eases in and out on real time while paused, layer order, hidden and not processing at rest; setting 0
    never shows); the quick suite passes (110 scripts, 1671 tests, 47663 asserts); main-scene smoke clean.
  - **Screenshots:** `references/screenshots/T44 focus pull/` (`open1`, `open2`, `battle_open`, `closed`).
  - **(H):** the strength and dim look right at 0.35 (`set settings.target_menu_blur 0.6` to try more); the 0.2 s ease feels
    right; the ring and the preview panel read as the only sharp things.

### M5-T45 Start screen and settings groups

- **Why (maintainer, 2026-11-09):** the start screen carries the pad diagram and an empty right panel it does not need,
  Sandbox and Missions split what is one list to the player, and Controls belongs inside Settings.
- **Track:** A. **Agent:** Sonnet. **Depends on:** T02 (the menu kit), T03 (the settings screen), T04 (the controls
  screen). Independent of T25.
- **Start screen:** the sky backdrop as today and only the options list (`MenuFrame` with the pad and right panels hidden,
  or a slimmer layout from the same kit): **New game**, **Load game** (shown greyed out; focus by D-pad, stick or mouse
  skips it, A does nothing on it, until saves exist), **Free flight**, **Settings**, **Quit**. A selects and B goes back
  everywhere, as today.
- **New game** (for now, until a campaign exists): one list with the missions from `MissionCatalog` first (Civilian
  escort) and then the sandbox scenes (Combat sandbox, Dogfight, Instructor route, Civilian ships); the highlighted
  entry's briefing (a mission) or a one-line description (a sandbox scene, written in its scenario file) shows under the
  list. The Sandbox page and its entry go away; the scenes stay as they are and keep their console ids.
- **Free flight:** as today (open space with the nav buoys, encounters on or off from `Settings.encounters`).
- **Settings:** a list of five groups, each opening its page. The schema's seven categories map onto them:
  - **Gameplay:** `game` and `flight` (encounters, friendly fire, ram damage, flight assist at start, unlimited fuel).
  - **Controls:** the controls screen of T04 (profiles, rebinding, unbind, save as) and the `controls` settings (invert
    pitch, deadzones, target hold time, mouse speeds). This page keeps the pad diagram, since it highlights the button of
    the action in focus.
  - **Camera & HUD:** `camera` and `hud`.
  - **Video:** `graphics`.
  - **Audio:** `audio`.
  The mapping lives in one table beside `SettingsSchema.CATEGORIES`; a test fails when a menu entry falls in no group.
  Apply, revert and defaults work per page as today.
- **Pause menu:** Resume, Restart, Settings (with Controls inside, the same five groups), Quit to menu; it keeps its pad
  diagram and objectives panels.
- **Not in this task:** a Load game screen and saves; new video settings (there is no window mode, V-sync or frame cap
  setting today; the console's `window` command resizes) unless the maintainer asks for them.
- **Tests first:** `test_settings_groups` (every menu entry in exactly one group, the order of groups); `test_front_end`
  (the entries in order, Load game disabled and skipped by focus in both directions, New game lists the mission then the
  four scenes and starts each, the text under the list follows the highlight, Settings, Controls and back with injected
  `ui_*` events, no pad diagram or right panel on the start screen); `test_pause_menu` (four entries, Controls reached
  through Settings); the existing settings and controls screen tests moved onto the groups.
- **Done when:** AC27, the tests pass, `docs/playtest.md`'s menu section and `info.md` (if a command changes) updated,
  and screenshots of the start screen, New game and the Settings groups in `references/screenshots/Start screen/` for
  the maintainer's look check (H).
- **Done (as built, 2026-11-12):** the start screen, New game and the five settings groups (architecture §18.28).
  - **Built:** `FrontEnd`'s list is New game, Load game, Free flight, Settings, Quit, with no pad diagram and no right panel
    (`MenuScreen.show_pad` and `show_right`, applied by `MenuFrame`; without the right panel the page's `info()` shows under
    its list, `MenuFrame.detail_text`). `NewGameSelect` (replaces `MissionSelect` and `SandboxSelect`, both deleted) lists the
    catalogue's missions and then Combat sandbox, Dogfight, Instructor route and Civilian ships; the scenes' one-line
    descriptions are a new `description` key in their scenario files (the loader ignores it). `SettingsSchema.GROUPS`
    (Gameplay: game then flight, Controls, Camera & HUD, Video, Audio) with `group_of_category` and `categories_of_group`;
    `SettingsGroupsScreen` is the Settings list both hosts push (`MenuScreens.settings()`); `MenuScreens.settings_screen(group)`
    builds one group's `SettingsScreen` (`SettingsMenuModel` takes the categories; Apply, Revert and Defaults work per page).
    The pause menu lost its Controls entry (four entries); its Settings opens the same groups.
  - **Assumptions:** Load game is disabled with the tooltip "No saved games yet." (no save system exists). The Controls group
    is the controls page itself (it keeps the pad diagram); the `controls` settings (invert pitch, deadzones, hold time, mouse
    speeds) open from a row "Sensitivity and deadzones..." at the end of its list, through the new `MenuScreen.push_requested`
    (the frame pushes it and copies `cancel_ignores_keys`, so the pause menu's Esc stays one edge). Free flight also uses the
    slim layout (its text under the list). Settings group pages hide the pad diagram and keep the help panel. AC1 to AC4 hold
    with the new routes; AC27 is the criterion for this design.
  - **Tests (focused, passing):** `test_settings_groups` 5 (new), `test_front_end` rewritten for the new list (start screen,
    Load game skipped both ways, no pad or right panel, New game's list, starts and text under the list, five groups, Controls
    inside Settings with its diagram, the controls settings), `test_pause_menu`, `test_controls_screen`, `test_settings_screen`
    (a group page test added), `test_civilian_escort`, `test_settings_menu_model`, `test_boot_routing`, `test_game_flow`.
    `run_tests.sh --quick` passed.
  - **GPU look check:** `references/screenshots/T45 start screen/` (start, New game, Settings, each group), RX 6950 XT.
  - **(H):** how the slim start screen and the text under New game read; the Controls row for the stick settings; whether
    Load game's greyed look is clear.

### M5-T46 Radial comms menu

- **Why (maintainer, 2026-11-09):** the comms menu should work like the target menu (circular, as big, the same blur
  behind it, the right stick to point, A to confirm, B to go back), so that when the comms options grow there is one
  common framework for both.
- **Track:** A. **Agent:** Sonnet. **Depends on:** T25 (the `RadialMenu` framework), T44 (the focus pull), T07 (the
  comms menu and its routing).
- **What:** D-pad Right still opens it. `CommsMenuView` lays `CommsMenu`'s pages on T25's radial framework, the same
  size as the target menu and vertically centred at the same side, with T44's focus pull behind it. The right stick
  points at an entry, A confirms it, B goes back a page and closes the menu from the first page. The first page is the
  four wing orders; a later page of replies, or sub-pages of orders, nest on the same page stack. D54's routing changes
  from the D-pad picking to the stick: `UiCommand` carries the stick's pick and A and B as menu edges instead of
  `comms_pick` 0-3. Opening it pauses the game, as the target menu does (the framework's rule): the order given takes
  effect when the game resumes, and the pad belongs to the menu while it is open. The 4 s timeout goes (the game is
  paused, so there is nothing to time out); B or D-pad Right closes it and resumes. Keys 1-4 still give the wing orders directly.
- **Tests:** `CommsMenu`'s page tests move onto the shared page stack; the routing tests rewritten for the stick, A and
  B (the tree paused while open and resumed on close; the edges re-seeded on close so nothing fires, steers or targets on
  the frame it closes);
  a profile saved before M5 loads with `comms_menu`; a view test that the entries sit on the ring and the highlight
  follows the stick.
- **Done when:** AC28, the tests pass, `docs/playtest.md`'s comms section updated, a screenshot in
  `references/screenshots/Radial comms menu/` for the look check (H).
- **Done (as built, 2026-11-11):** the comms menu is a radial menu on T25's framework (architecture §18.22).
  - **Built:** `CommsMenu` (pure) is now a thin page stack over a `RadialMenu`: the first ring is the wing orders (ATTACK,
    FORM ON ME, ENGAGE, COVER ME) on the up, right, down and left slices, in the order of keys 1-4; an entry carrying a
    `page` opens that ring over it (a mission's replies, sub-orders), `select` returns the confirmed entry and closes,
    `back` pops a page. `CommsMenuDirector` (a node under `Main`, `src/hud/comms_menu_director.gd`) mirrors the target
    menu's director: it pauses the game on open, owns a `RadialMenuView` (same ring, size, left side, layer 45 and T44
    focus pull) and sends the order through `WingDirector.give_order` once the game runs again. Input: `Main` calls
    `adapter.sample_radial` while it is open, so the right stick (arrows, mouse) points, A sends, B goes back or out,
    Start hands over to the pause menu, and D-pad Right (Ctrl) again closes it (`UiCommand.comms_open` is read as a
    close edge by `sample_radial`; `begin_radial` seeds it so the opening press is not a close). Console: provider
    `comms_menu` (`open`, `page`, `highlight`, `entries`, `picks`, `last_pick`, `closed_by`, `focus`) and the command
    `commsmenu open|pick|highlight|back|close`, in `info.md`.
  - **Changed:** removed `CommsMenuView` (the plate), the 4 s timer (`CLOSE_S`, `remaining_s`), `UiCommand.comms_pick` and
    `comms_close`, `InputAdapter.comms_open` and `COMMS_PICKS`, and every rule in `InputAdapter.sample` that swallowed
    assist, next weapon, lights and the target button while the menu was open (the pad is read by `sample_radial` then,
    so none of it can fire). The two menus exclude each other: neither opens over the other (the target menu used to
    close the comms menu; it now refuses). A cinematic or a script's `lock_controls` closes an open comms menu as before.
    Profiles are untouched: `comms_menu` is still the same action, so a profile saved before M5 loads with it filled in
    from the default (the existing `test_control_profile_store` test).
  - **Assumptions:** the heading reads WING ORDERS (the page title); the hint line is `A  SEND      B  CLOSE` (`B  BACK`
    on a sub-page); labels are short with a second line (`ATTACK` / `my target`, `ENGAGE` / `at will`); a page needs no
    "none" entry, so the down-slice rule is not exercised yet (`RadialMenu.arrange` already supports it); a page holds up to
    eight entries and pads to four slices. Keys 1-4 are unchanged.
  - **Tests (focused, all passing):** `test_comms_menu` 9 (unit: pages, compass slices, sub-page push and back, pick closes
    the stack, blanks skipped); `test_comms_menu_input` 13 (integration on the real main scene: opens and pauses, the stick
    and A send each of the four orders, B, pad B taps no target, D-pad Right closes and the opening press does not, no
    timeout, flight buttons inert, nothing held fires on close, Start to the pause menu, the console, `pause` refused, ring
    size and side and highlight follow the stick); `test_input_adapter` 48 (the comms and radial section rewritten);
    `test_control_lock`, `test_cinematic_camera`, `test_target_menu` adjusted. `run_tests.sh --quick`: GUT 1669 of 1669, exit 0;
    main-scene smoke clean (no `ERROR:`, no leaks).
  - **GPU look check (RX 6950 XT, RADV, Forward+):** `references/screenshots/T46 radial comms/comms_ring.png` (the ring at the
    left with FORM ON ME lit, blurred view behind, hint under it); about 52 fps in the windowed run with the debug overlay on.
  - **(H):** how the ring feels with a real stick; that the pause-while-open feels right for giving orders in a dogfight;
    label wording.

### M5-T47 Radar plot input checks and scratch reuse

- **Why (maintainer, 2026-11-12):** the last two open items of `code-review-comments.md`.
- **Done (as built, 2026-11-12):** `radar_kernel::plot` refuses columns of different lengths (it returns false with an empty
  plot instead of plotting up to the shortest column), and `ScsRadarPlot.plot` also checks `colour_ix` against `ids` and
  every colour index against the palette: a mismatch logs an error and returns an empty plot, never a truncated one or a
  white stand-in. `Plot` keeps its output vectors and its point, range and key scratch between calls and clears them, so a
  steady plot no longer allocates per call. Tests: Rust `columns_of_different_lengths_plot_nothing` and
  `a_second_plot_reuses_its_buffers_and_matches_the_first` (8 radar kernel tests pass); GUT
  `test_mismatched_columns_are_refused_not_truncated` in `test_radar_plot`, with `test_radar_model`, `test_sim_core`,
  `test_hud` and `test_target_menu`: 71 passing.

### M5-T48 The full code review's findings

- **Why (maintainer, 2026-11-12):** a Fable agent reviewed the whole codebase at `104264ea` (no P1 or P2 issues; three P3 items
  in `code-review-comments.md`); the maintainer asked for them fixed before the merge.
- **Done (as built, 2026-11-12):** `Damageable.apply_hit` emits `destroyed` only for the kill of its own hit, so a dead hull hit
  while invulnerable no longer announces its death again (`test_damage`: `test_a_dead_hull_hit_while_invulnerable_does_not_die_again`);
  the brains' hosted settle reads each item's place in the hosted list from `Work.hosted_at` instead of searching the list per
  think (the seeded-battle parity files pass unchanged); a new `SimCore` drops civilian ids of ships freed since instead of
  handing them to its core (`test_sim_core`: `test_a_new_core_forgets_civilians_freed_with_an_earlier_scene`). Rust 68 pass;
  GUT: `test_damage`, `test_sim_core`, `test_row_commands`, `test_core_threads`, `test_core_state`, `test_driver_step`,
  `test_turret_defence`, `test_civilian_ships`, `test_ai_driver`: 89 passing with `GUT_SLOW=1`; the quick tier passes.

### M5-T20 Integration, full suite, docs and acceptance

- **Goal:** AC16, AC17 and the (H) checklist for AC18.
- **Steps:** finish §18 in `docs/architecture.md` as built; write the M5 section of `docs/playtest.md` with the (H)
  checklist; update the roadmap row; run `scripts/run_tests.sh` once and read GUT's and Python's own totals; run the GPU
  check on the maintainer's machine; then ask the maintainer to confirm the milestone. `m5` already holds all of M4 (Q34);
  once confirmed it merges into `main` (no rebase).
- **Done when:** the maintainer confirms M5.
- **Status:** in progress — awaiting the maintainer's confirmation. Not merged into `main`.
- **Notes (2026-11-12, the automated part):**
  - **Docs.** Architecture §18: a map of which subsection describes each part of M5 and what a later task replaced; the
    file list brought up to date (the buoy ring and T02's two select pages gone; the settings and controls menus, dialog,
    the radial framework, focus pull, comms menu, pause path and engine voices added); the providers and settings M5 added;
    new as-built subsections §18.31 (settings and controls menus, audio buses), §18.32 (the sound pass) and §18.33 (tests and
    CI); stale lines corrected (the menus' root lists, the comms menu's layer, Buoy defence in §18.5). Numbers 18.1 to 18.33
    are unique and in order, and every `§18.n` reference in the docs resolves. `docs/playtest.md`: "Play-testing M5" now
    covers the start screen and menus, the escort, the target and comms menus, encounters, the civilians, sounds, the new
    settings and commands, and one "M5 acceptance checklist" with every task's (H) item. The roadmap's M5 row and the
    carried findings L1 to L14 are marked.
  - **Loose ends** (fixes in 87be2300 and d9c4d65a; the docs in 99778cb1).
    - T36's two `ScsWeaponRows.set_turrets` ERROR lines come from
      `test_turret_kernel.test_turrets_of_a_capital_that_is_not_bound_are_refused`, an error-path test that already expects
      both with `assert_engine_error`. GUT 9.7.1 counts them as expected but cannot stop the engine printing them; nothing to fix.
    - T46's "4 resources still in use at exit" was ours: `test_target_menu` built a `Hud` only to read its layer and never
      freed it (11 objects, a canvas RID, 4 resources). It reads the live HUD now; the file exits clean.
    - T38's `--quick` on a fresh checkout: the quick tier now runs the same import step as the standard tier before the
      compile check (`godot_import` in `scripts/lib_tests.sh`; about 3 s on a current cache).
    - **Found by the full run:** `run_tests.sh --full` runs every GUT file in one process under the standard tier's 3 600 s
      limit, and with the balance fights that is not enough: the first run was cut at 3 600 s in `test_core_threads` (after
      173 of 303 scripts) with nothing failing before the cut. `--full` now allows 7 200 s.
  - **The full suite** (`scripts/run_tests.sh --full`, the run after that fix): exit 0 in 4 459 s, read from each
    runner's own totals:

    | Runner | Total | Passed | Failed | Other |
    |---|---|---|---|---|
    | GUT (slow and balance files on) | 303 scripts, 3 433 tests, 134 659 asserts | 3 421 | 0 | 12 pending |
    | Python (`unittest discover`) | 860 | 858 | 0 | 2 skipped (the Saturn 3 has no aft frame) |
    | Rust (`cargo test --release --lib`) | 66 | 66 | 0 | - |
    | Console smoke runs | 29 | 29 | 0 | - |

    The 12 pending: 10 need the real renderer (`test_motion_vectors_gpu`, `test_upscaling_gpu`), and `test_dogfight` and
    `test_m3_sandbox` each have their M3 AC12 balance test pending by design (the maintainer's review of the balance). GUT
    alone took 3 766 s, which is why the old 3 600 s limit cut the first run; that run's 173 scripts had no failure
    either. No flake seen in either run.
    **Open, not fixed:** the whole-suite GUT process ends with "61 ObjectDB instances leaked at exit" and "8 resources
    still in use". No test fails on it and the game's own smoke runs, which reject any leak line, pass. It is not the four
    menu files that report orphans mid-run (`test_controls_screen`, `test_menu_frame`, `test_pause_menu`,
    `test_settings_screen`): each exits clean alone. Finding the file means bisecting 303 scripts; left for a later task.
    **CI:** green on d9c4d65a (run 43195940012, 20 min 55 s with the asset cache warm).
  - **GPU check** (RX 6950 XT, RADV NAVI21, Wayland, Forward+, a 1200x675 window; fps is capped near 145 by Wayland's
    vsync; VRAM is `render.vram_mb`, the game's own; the card as a whole read 2 832 MB before the runs and peaked at 3 263 MB
    during them, desktop included). Screenshots in `references/screenshots/T20 acceptance/`, all looked at, nothing broken:

    | Scene | Shot | fps | Draw calls | VRAM MB |
    |---|---|---|---|---|
    | Start screen | `start_screen.png` | - | - | - |
    | Civilian showcase, all nine in view (cockpit) | `civilian_showcase_all_nine.png` | 145 | 129 | 481 |
    | Saturn 8 transport at 420 m, texture detail high and low | `saturn_8_transport_high.png`, `_low.png` | 134 | 106 | 481 |
    | Bokmai at 90 m, high and low | `bokmai_high.png`, `bokmai_low.png` | 145 | - | - |
    | Escort: the intro's wing shot with the hail, the brief | `escort_intro_wing_shot.png`, `escort_brief.png` | 145 | - | - |
    | Escort: wave one (3 raiders in), wave two in the belt | `escort_wave_one.png`, `escort_wave_two_belt.png` | 145 | 82, 85 | 403 |
    | Target menu: categories; a ring with the preview and blur | `target_menu_categories.png`, `target_menu_preview_blur.png` | 134 | 98 | 335 |
    | Comms ring (FORM ON ME lit) | `comms_ring.png` | 145 | 82 | 335 |
    | Pause menu and its backdrop | `pause_backdrop.png` | 145 | 117 | 337 |
    | Belt showcase, chase and cockpit | `belt_showcase.png`, `belt_showcase_cockpit.png` | 145, 131 | 62, 94 | 355, 360 |
    | `bench battle 300` in view | `bench_battle_300.png` | 144 | 102 | 319 |
    | `bench battle 1000` in view | `bench_battle_1000.png` | 144 | 98 | 320 |

    The windowed benches kept real time: tick median 3.52 ms (p99 9.65) at 300 and 5.48 ms (p99 10.79) at 1 000.
    For the maintainer's eye, not faults: in the pause backdrop the ship passes behind the left panel for part of the loop
    (T42's (H) item); `civilian_showcase` parks its hulls 1.8 km ahead, so they are small until you fly up to them.
  - **Benchmark** (`QUICK_NS="1000" scripts/bench_quick.sh t20 battle`, headless, seed 1, load 0.9, at 99778cb1): 59.9 ticks a
    second, tick median **5.44 ms**, p99 **7.51 ms**, worst rebase tick 7.56 ms, budget passed. Stages (median): flight
    2.30 ms (Report P3: 3.97), hits 0.78 ms (1.41), rams 0.23 ms (1.20), Jolt 1.18 ms, AI on the main thread 0.35 ms,
    targeting 0.09 ms, the core's sync 0.25 ms. M4 closed at 9.22 ms for the same run.
  - **Acceptance.** AC1 to AC17 and AC19 to AC28 are met, with the evidence in the table's Done column. AC12 and AC20 are
    met in the form T27 gave them (textured meshes instead of splat levels, Q29). AC18 is the maintainer's play-test.
  - **Left for the maintainer:** the (H) checklist in `docs/playtest.md`; the open questions earlier tasks recorded (Q33's
    narrow blind spot, T25's tap on unknown contacts, T42's choice of path); then the confirmation and the merge into `main`.
