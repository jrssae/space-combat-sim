# Milestone 3: AI Pilots and Wingmen

> "Others who fly." (`docs/roadmap.md`)

**Status:** planned 2026-10-21 on branch `m3`. The maintainer answered the planning questions the same day (below). M2's
(A) work is done; its AC20 (saved control profile) and AC21 (sound) still wait for a re-test and do not block M3.
Extended 2026-10-28 at the maintainer's request with splat LOD and a visual pass (Q22, Q23; T19-T25).

Read `docs/architecture.md` first, §1-§15 and especially **§16** (the M3 design: decisions D30-D38, layout, tick
order). Task notes reference its sections (§). Tasks are ordered; each is one PR-sized unit for an implementation agent
and names a recommended agent model with a one-line reason.

## Before you start

M3 builds on M2 as built, including the M2.1 play-test rounds. Read the code, not only `m2-combat-sandbox.md`, for:

- **AI seam** (`src/ai/`): `PilotBrain.think(Perception, dt) -> PilotCommand`, `AiPilotDriver` (priority -10),
  `PilotSteering.face/seek`, `ShipCapability`, the four M2 brains, `BrainFactory`, `RaiderTactics`. Gun convergence
  (`WeaponSpec.convergence_range_m`) and the miss-distance fire gate came out of M2-T07; keep them.
- **Ships**: `ShipAssembly` builds player and AI ships the same way; `ShipPool` (`World/Ships`) is raiders-only today
  (faction stamped at build, names `RAIDER <n>`). `Ship` speed limits come from `SpeedGovernor` (9 999 m/s hard
  limit, 5 000 m/s assist safe speed); Starfury bolts are 1 000 m/s relative to the ship.
- **Destruction**: `DestructionDirector` releases pool ships in the same tick; `DebrisPool` holds two chunk sets per
  chunked asset; the Starfury had no `chunks[]` before M3-T03 (the player died into generic shards).
- **Input**: auto-track (`FlightCommand.autotrack`), R3 brake, L3 free look, the mouse flies pitch and yaw, Alt frees
  the mouse. The keyboard layout changes in T01.
- **Newtonian invariant** (§15.16): every ship goes through the one `FlightModel`; turning is torque only. AI never
  writes velocities.

## Scope

In:
- **Keyboard layout B** (maintainer choice): every flight key under the left hand; the right hand stays on the mouse.
- **Factions as data** (`data/factions.json`), `Factions` API unchanged; **friendly fire** as a setting (default off).
- **Ram damage**: collisions hurt by speed; bumps are harmless, hard hits wreck, tunnelling speeds are fatal for both.
- **Collision avoidance** for every AI ship (ships and buoys).
- **`AiPilot extends PilotBrain`**: utility selection over attack, evade, formation, follow path, guard and retreat,
  with per-pilot profiles (weights, skill) and a fire-lane check.
- **Wingmen**: three allied Starfuries (a finger-four with the player as lead) that form on the player and engage on
  their own; four orders on keys 1-4 and the console. Downed wingmen are replaced at the next wave.
- **Starfury break-up chunks** and a lighter **LOD1** Starfury for allies (and all Starfury debris).
- **Raiders on the new AI**: groups of two or three, evasion, collision avoidance; the M2 idle and patrol brains stay
  for target practice.
- **Instructor**: a Starfury that leads a paced waypoint route around the buoys and performs demo manoeuvres (roll,
  flip-and-burn, strafe box, pod turn, all stop) for the player to copy.
- Scenarios: wingmen in `combat_sandbox` with bigger raider waves; new `instructor_route` and `dogfight`.
- HUD: wing roster, order acknowledgements, a route waypoint marker. Console commands and providers for all of it.
- **Splat LOD by screen size** (Q22): LOD2 and LOD3 for every ship asset, a `LodSwitcher` that shows one LOD per ship by
  visibility, and a resident splat budget in GDGS so hidden LODs cost no sort memory (T19, T20).
- **Visual pass** (Q23): GDGS relighting with procgen-written per-splat normals and flat hull colours, a picker for GDGS's
  8 lights; nozzle, muzzle-flash and explosion lights; `GPUParticles3D` sparks and debris; a denser LOD for the player's
  ship; lens flare and motion blur after the maintainer signs off the dependencies (T21-T25).

Out (explicitly):
- Dialog, subtitles, the comms panel, mission scripts, objectives (M5). Order acknowledgements are one HUD text line.
- A pad comms menu (M5, with the comms panel). Orders are keyboard and console only in M3.
- Tutorial checks that the player copied a demo (M8). The instructor only shows the moves.
- Capital ships, turrets, subsystems, towing (M12 / M14). The station and jumpgate (M6 / M7).
- New factions beyond `earth_alliance`, `raiders` and `neutral` (the data format allows them; M12 adds them).
- Physical collision for buoys (they stay `Node3D` props; rams against them are detected, not bounced).
- LOD chains for the station, jumpgate and planets (M6, M7). M3 builds the `LodSwitcher` and the splat budget for ships
  (T19, T20); later assets join them.

## Maintainer answers (2026-10-21)

Record later answers here (rules) or in `docs/design-references.md` (designs), so agents never rely on chat history.

| # | Question | Answer |
|---|---|---|
| Q1 | How does the player order wingmen (the pad has no free buttons)? | **Autonomous + keys**: wingmen form on the player and engage hostiles by themselves; orders on keys 1-4 and console commands. A pad comms menu waits for M5 |
| Q2 | Friendly fire? | **A setting, default off** (`settings.friendly_fire`). The AI's fire-lane check is built either way |
| Q3 | Ram damage? | **Speed-scaled**: bumps under about 5 m/s harmless, about 30 m/s wrecks a Starfury, tunnelling speeds always fatal for both. `god` protects the player. Applies to buoys too |
| Q4 | Allies at once? | **Three wingmen** (finger-four with the player). Allies use a lighter splat Starfury (LOD1) |
| Q5 | Instructor? | **Paced route + demo moves**: leads a waypoint route, slows or waits for the player, the HUD marks it and its next waypoint, and it performs manoeuvres at waypoints (roll, flip-and-burn, strafe, pod turn, all stop). No dialog |
| Q6 | Raider AI? | **Yes**: raiders use the utility AI too (evade, groups of 2-3, collision avoidance). M2 idle / patrol brains stay for target practice |
| Q7 | Sandbox? | **Wingmen in `combat_sandbox`**, raider waves grow to match; plus `instructor_route` and `dogfight` scenarios |
| Q8 | Wingman deaths? | **Replaced at the next wave**: a downed wingman explodes (Starfury chunks) and a replacement launches when the next wave starts |
| Q9 | Keyboard (right hand on the mouse; M2.1 put flight keys on the right side, which was wrong) | **Layout B, pods by position**, no keyboard pitch/yaw (the mouse flies). Table in M3-T01 |
| Q10 | AC13's AI budget (2026-10-24: after T06's trims the 13-ship path measures 1.7-2.1 ms on the development desktop with M2 brains alone) | **Relative + record**: `AiPilot` may add at most 0.5 ms per tick over the M2 AI path in the same fight (paired test); the absolute number is recorded, and T12 records it again on `dogfight` |
| Q11 | (2026-10-24, raised by the maintainer) How should AI ships react to being shot? | **Evade when hit**: every AI ship, ally or raider, that takes a bolt hit starts evasive manoeuvres at once, even mid-attack, then returns to its fight (M3-T10, AC9 hit reaction). The instructor (evade weight 0, invulnerable) is exempt |
| Q12 | (2026-10-24, raised by the maintainer) Can AI ships differ in skill and temperament (civilian vs raider vs military)? | **Per-ship skill rank and aggressiveness**, named ranks: skill `rookie` / `regular` / `veteran` / `ace`, aggressiveness `passive` / `cautious` / `balanced` / `aggressive` / `reckless` (0-1 inside; a number is accepted too), set per spawn with profile defaults. At `reckless`, a badly damaged ship whose allies are mostly or all dead has a chance to ram an enemy; **any AI ship** may, allies included, when set to reckless. **Civilians: a profile only** in M3 (never attacks, evades and flees), usable on any hull; civilian ships and traffic come later (M3-T13) |
| Q13 | (2026-10-25, reported by the maintainer) The ship model jumps while thrusting more than about 900 km from the reference point, almost constantly in splat mode and slightly in mesh mode | **Bug, fixed by turning on the planned position rebase** (§14.1, 5 km) in play from M3-T14. Cause: `Main` leaves `World.auto_rebase_distance_m` at 0 (M1 assumed a 20 km play area), so the local origin stays at the launch point while Jolt allows 10 km/s; at 900 km a float32 position steps in 6.25 cm, and GDGS packs the model and view matrices as float32 separately, so every splat quantises on its own. The velocity rebase stays in M6 |
| Q14 | (2026-10-25) AC9's 90° turn: at 10°/s the leader's nose leads its flight path by about 60°, and slots fixed to the nose swing round with it; T07 measured #2 / #3 within 57 m and #4 at 107-115 m | **Looser bound for #4**: slots stay fixed to the leader's nose; #2 and #3 within 80 m, the far slot #4 within 120 m, at 10°/s. Harder turns are left to the AC15 feel test |
| Q15 | (2026-10-26, play-test request; amended 2026-10-30) Pad: assist, target cycling and the right stick | **Swap them**: B is target cycling (tap next, hold the previous target, as the mouse wheel), D-pad Up toggles flight assist. **The right stick flies all three axes** (2026-10-30): up / down pitch, left / right yaw, a diagonal rolls. D-pad Left / Right, which yawed, are left free. **Free look holds**: while L3 is held, the view stays where the right stick left it and returns to the nose only when L3 is released (M3-T15) |
| Q16 | (2026-10-26, play-test request) What does pressing 1-4 show? | **The order in words**: the acknowledgement line names the command issued, e.g. `ALPHA 1: FORM ON ME` (M3-T11) |
| Q17 | (2026-10-26, play-test request) Gun and impact sounds | **Two octaves lower** (every frequency ÷ 4, lengths unchanged): the Starfury and raider gun sounds and the bolt hitting a hull (M3-T15). M5's new gun sounds keep that register |
| Q18 | (2026-10-26, play-test request) Kill count | **Three numbers**: player kills (the player landed the killing hit), player assists (the player fired at least one shot while that ship was the player's selected target, and someone else killed it), and total enemy kills by anyone (M3-T16) |
| Q19 | (2026-10-26, play-test request) Attack style | **Slashing pass and chase** for some skill / aggression levels: fire through the pass, then burn to slow down and turn to chase, flying for the most time with the guns on the target (M3-T18) |
| Q20 | (2026-10-26, play-test request) Starfury thrust | **Reverse equals forward**; side thrust at least 50 % of today's forward thrust, or today's side thrust if larger. Four pods give 1.44 MN forward, so: retros 0.36 MN per pod (1.44 MN, 30 m/s²), sway and heave 0.72 MN each (15 m/s², up from 0.48 MN) (M3-T15) |
| Q21 | (2026-10-26, play-test request) Contacts beyond the radar's 25 km | **Broadcast signals**: nav buoys and allies broadcast, so they show beyond the 25 km sensor range: allies to 100 km, buoys to 1 000 km (M3-T17). Later the station and jumpgates broadcast to 1 000 km (M6, M7), and in hyperspace the destination jumpgate's range is unlimited (M11). **The AI receives every broadcast at the same ranges** (maintainer, 2026-10-26): e.g. a raider sent to attack a nav buoy or the station sees it from as far as the player's radar does |
| Q22 | (2026-10-28, maintainer request) Fewer splats on distant ships, more up close? | **Yes, in M3** (pulled forward from M6): LOD2 and LOD3 for the ship assets, a `LodSwitcher` that picks one LOD per ship by its size on screen and switches by visibility (never by swapping the resource, which rebuilds every GDGS buffer), and a resident splat budget patched into GDGS so hidden LODs cost no sort memory (T19, T20) |
| Q23 | (2026-10-28, maintainer request) Close the visual gap to Unreal without leaving Godot | **A visual pass, in this order**: GDGS relighting with procgen-written per-splat normals, flat hull colours and a picker for GDGS's 8 lights (T21); thrust-driven nozzle lights, muzzle-flash and explosion lights through the picker (T22); `GPUParticles3D` sparks and debris (T23); a denser LOD for the player's ship only (T24); lens flare and motion blur last, each a new dependency or new effect the maintainer signs off first (T25) |
| Q24 | (2026-10-30, maintainer request) Match the Starfury to the reference 3D model, and draw the HUD's own-ship damage display as a low-poly wireframe | **Done first, before the other open tasks** (M3-T26): `starfury_aurora` generator v3 reshapes the pods, claws, struts and the fuselage behind the cockpit after the model's proportions (written down in `docs/design-references.md`; the model itself stays untracked); the Starfury damage silhouette becomes a low-poly wireframe seen from behind and above, each part coloured by its damage zone |

Calls made by the planner (say if you want them changed): callsigns `ALPHA 1` (player) to `ALPHA 4`, the instructor
`INSTRUCTOR`; the default order is **cover me** (hold formation, engage hostiles that come within 2 km of the player);
the instructor is invulnerable and never fires; while the player is dead the wingmen engage at will and resume their
order on respawn; ally LOD1 is about 25 % of the Starfury's splats.

## Acceptance criteria

`(A)` = an agent verifies headlessly. `(H)` = the maintainer's Linux desktop with a Vulkan GPU (GDGS Compute), the pad,
keyboard and mouse. Expected values in (A) tests come from specs, profiles and hardpoints, never hard-coded.
**Pre-check** names a capture set (below) attached to the PR before the maintainer looks.

| # | Criterion | Who | Pre-check |
|---|---|---|---|
| AC0 | Every M1 and M2 (A) test still passes, except tests that assert the old keyboard keys, which T01 updates, and the player break-up in `test_destruction.gd`, which T03 moves from shards to the Starfury chunks, and tests that count the sandbox's pooled ships or engine hums, which change because Q7 puts wingmen in the sandbox (T08 pools them, T10 launches them), and the explosion's sparks flag in `test_explosion.gd`, which T14 replaces with a direct check that the sparks stay where the ship blew and move with a rebase (the M2 AC16 look gets an (H) glance in AC22). With `factions.json` at its defaults, every M2 faction, hit and target-order result is unchanged | A | |
| AC1 | Keyboard layout B: `project.godot` and `m1_classic` hold exactly the T01 table; no flight action has a key right of the G/B column (Backspace, N, Print, F3/F4 and Esc are the only keys outside the left block); every action keeps a pad binding (wing orders are keyboard-only and allow-listed); `B` is tap = next target, hold = nearest the nose; `W` and `S` drive both pods; a profile round trip is exact | A | |
| AC2 | Factions: `data/factions.json` validates (broken variants give path-qualified errors and leave the table unchanged); same faction is FRIENDLY, an unlisted pair is the file's default, listed pairs are symmetric; `relation` on the console changes a pair for the session and HUD colours follow | A | |
| AC3 | Friendly fire: with `settings.friendly_fire` off, nothing changes from M2 (AC3 of M2 still holds); on, a bolt hits any active hull except its shooter's (allies, the player, buoys); god mode still protects the player; an AI never fires while a friendly sits in its fire lane (both settings) | A | |
| AC4 | Ram damage: two Starfuries meeting at 4 m/s closing take no damage; at 30 m/s each loses at least 50 % hull; at 600 m/s closing (one tick is 10 m) both are destroyed and neither tunnels through unhurt (50/50 seeded offsets inside the hull overlap); a ship ramming a buoy at 40 m/s destroys the buoy; the player with `god on` takes nothing and still bounces; `HitInfo.cause` is `ram`; kills by ram count | A | |
| AC5 | Avoidance (`AvoidanceMath`, pure): head-on, crossing and overtaking cases produce a dodge that raises the miss distance above the sum of radii plus margin; diverging or distant contacts produce none; ties break by seed, never NaN. In Jolt: two AI ships set on a head-on course at 150 m/s closing pass without contact in 20/20 seeded runs; an AI ship aimed at a buoy at 100 m/s misses it | A | |
| AC6 | Starfury asset: `python3 -m tools.procgen build starfury_aurora` also writes LOD1 (`lods[1]`, 20-30 % of LOD0's splats, same AABB within 0.3 m) and `chunks[]` `cabin`, `arm_ur`, `arm_lr`, `arm_ul`, `arm_ll` that partition the LOD1 splats exactly; LOD0 output is byte-identical to before; deterministic; after `--import` the LOD1 and chunk PLYs load with manifest counts | A | |
| AC7 | Allied ships: a `starfury_ally` from the pool flies the Starfury `ShipSpec` numbers (M1 AC5 formulas) with LOD1 splats; the splat-node count never changes across acquire / release / destroy / replenish cycles (D22); a destroyed ally explodes into Starfury chunks and returns to the pool; the player's death also uses Starfury chunks | A | P5 |
| AC8 | `AiPilot` selection (unit, scripted `AiContext`s): the highest weighted score wins; the current behaviour keeps a stickiness bonus and a minimum dwell unless a challenger beats it by the emergency margin; orders gate behaviours (FORM ON ME never attacks; ATTACK MY TARGET attacks only the leader's target); `describe()` names the behaviour and its state; same seed = same choices | A | |
| AC9 | Behaviours in Jolt: **formation** members hold within 25 m of their slots in straight flight and within 80 m through a 90° leader turn at 100 m/s and 10°/s, flown like a player on the mains (the far slot, #4, within 120 m; Q14), never closer than 15 m to anyone; **evade** cuts an M2 attack raider's hits on the evader by at least half against the same seeded run without evade; **guard** engages a hostile that enters the guard radius and returns within 300 m of its post once it is gone; **retreat** below 25 % hull opens the range; **hit reaction** (Q11): an AI ship (ally or raider, any order) hit by a bolt starts evading within 0.25 s (skill `regular` or better; a `rookie` within 0.6 s, T13), even mid-attack inside its minimum dwell, and flies at least one full jink before it may attack again; repeated hits keep it evading | A | |
| AC10 | Instructor: on `instructor_route` the instructor visits every waypoint in order; with the player parked it stops within 1 600 m and resumes when the player closes to 800 m; each demo completes its measurable goal (roll 360 ± 10°, flip-and-burn ends with velocity reversed or below 2 m/s, strafe box returns within 30 m of its start with every leg over 40 m, pod turn yaws the right way by over 30°, all stop ends below 0.5 m/s and 1 °/s); the HUD's waypoint marker projects to the route point | A | P6 |
| AC11 | Wing orders: keys 1-4 (through `UiCommand`, never `Input`) and `wing order <attack\|form\|engage\|cover>` change every member's order and post one acknowledgement line naming the order (Q16); ATTACK MY TARGET with no hostile selected is refused with a message; the roster lists callsigns, hull and current behaviour; downed wingmen are replaced when the next wave starts, entering 1 500 m behind the player | A | P7 |
| AC12 | Scenarios: `combat_sandbox`, `instructor_route` and `dogfight` validate (and broken `wings` / `route` entries give path-qualified errors); a headless sandbox run with wingmen clears three waves; a headless `dogfight` (four allies, six raiders, player `god on` and idle) ends with one side destroyed within 6 sim minutes in 5/5 seeds and is reproducible per seed within 1e-3 m after 60 s | A | P8 |
| AC13 | Console and perf: `state` lists the M2 providers plus `factions`, `ram`, `wing`, `ai` (and `route` on `instructor_route`); every new command works under `--console-strict` and rejects bad arguments; new settings are schema entries; AI think time for 13 ships: `AiPilot` adds at most 0.5 ms per tick over the M2 AI path in the same headless fight (paired, Q10), with the absolute number recorded; the hit and ram resolvers stay under 2 ms per tick in the dogfight run | A | |
| AC14 | Keyboard layout B feels right with the right hand on the mouse; Caps Lock rolls (press and release both register) | H | |
| AC15 | Wingmen fly a believable finger-four on the player, break to engage, rejoin, follow orders 1-4, and are useful in a fight; raiders fly in groups, evade when chased, and still make attack runs | H | P7, P8 |
| AC16 | Rams: bumps feel harmless, hard hits hurt, head-ons kill; nothing tunnels visibly | H | |
| AC17 | Instructor: the route is easy to follow, the waypoint marker reads, every demo is clearly visible from behind | H | P6 |
| AC18 | Allied Starfuries (LOD1) look right at combat ranges; a Starfury break-up shows its cabin and four arms tumbling apart | H | P5 |
| AC19 | 60 fps at 1080p on the tester's GPU with four Starfuries, nine raiders, bolts, explosions and debris on screen | H | |
| AC20 | Skill and aggressiveness (Q12): every AI spawn (scenario, wave, console) takes `skill` and `aggression` by name or 0-1, defaulting from its profile, and `ai <name> skill|aggression <value>` changes them live. Unit tests show skill scaling aim error, reaction delay and fire discipline, and aggression scaling the attack / evade / retreat weights, the retreat threshold and the engage range, each monotonically. A `civilian` profile never fires and evades and flees hostiles. In Jolt, on the same seeded runs: an `ace` raider lands more hits on a drone than a `rookie`; a `cautious` ship retreats at a higher hull than an `aggressive` one. **Last-ditch ram**: only at `reckless`, below 25 % hull with at most a quarter of its allies left, a seeded chance commits a ship to `ram`: avoidance stops dodging that target and it flies a collision course; in Jolt a committed rammer hits its target in at least 8 of 10 seeded runs, and no ship below `reckless` ever rams. `ai <name>` shows skill, aggression and the behaviour | A | |
| AC21 | Position rebase in play (Q13): `main.tscn` runs with `World.auto_rebase_distance_m` 5 000 m (a bare `WorldFrame` keeps 0); after `rebase -900000 0 0` the player ship is back within 5 km of the local origin on the next physics tick, with every ship's, prop's and bolt's `UniversePos` and velocity unchanged (1 mm, 1 mm/s); under constant thrust after that, the ship's tick-to-tick change of step, taken in universe coordinates, stays under 2 mm (about 5 cm without the rebase). In a headless sandbox fight with wingmen and the threshold forced down so the world rebases at least every 2 s, the waves still clear, bolts still hit, no hit lands along a jump, no ship's universe position jumps more than its own motion plus 1 m across a rebase tick, the chase camera's offset from the ship stays continuous, and the HUD's reference range follows the universe distance. One rebase of the full sandbox costs under 0.5 ms (record the number) | A | |
| AC22 | Far from the launch point (after `rebase -900000 0 0`, or a long flight), the ship shows no jumping while thrusting in any direction, in splat and mesh mode; flying at full speed through rebases shows no hitch | H | |
| AC23 | Play-test tweaks (Q15, Q17, Q20): pad B (`JOY_BUTTON_B`) is `target_cycle`, where a tap selects the next target on release and a hold (`target_hold_s`) selects the previous one once, as the mouse wheel does; D-pad Up (`JOY_BUTTON_DPAD_UP`) is `toggle_flight_assist`; the right stick pitches within 22.5° of straight up or down, yaws within 22.5° of straight left or right, and rolls on the diagonals between (toward the side the stick leans), one axis at a time; D-pad Left / Right have no binding; in free look (`CameraLook`) the right stick turns the view at a rate, a centred stick leaves the view where it is while L3 is held, and only releasing L3 eases it back to the nose; all in `project.godot` and every saved profile that had the old default pad layout, and a profile round trip is exact; `pulse_fire`, `raider_fire` and `hit_hull` have their spectral centroid within 5 % of a quarter of the old one and the same length, deterministic per seed; both Starfury specs have `pod_retro_thrust == pod_main_thrust` and sway and heave forces of 0.72 MN, and the M1 AC5 physics tests (numbers from the spec) pass with them | A | |
| AC24 | Kill credit (Q18): a raider killed by the player's bolt (or rammed by the player) adds a player kill; one the player fired at while it was selected but an ally killed adds an assist, never both; total kills counts every enemy ship destroyed by anyone; the HUD status line shows all three, the `waves` provider has `player_kills` and `player_assists`; drones and buoys count as now | A | |
| AC25 | Broadcasts (Q21): a buoy at 900 km and an ally at 90 km show on the radar and can be selected (range in the target box), an ally at 110 km and a non-broadcasting raider at 30 km do not; beyond the radar's 25 km scale a broadcast contact sits on the rim in its true direction; `broadcast_range_m = INF` works at 1e9 m; ranges come from universe distances and survive a rebase. The AI gets the same broadcasts at the same ranges (any faction): a raider's perception lists the 900 km buoy and the 90 km ally, not the 110 km ally; a raider given that buoy as its objective (`ai <name> objective <target>`) flies toward it from 200 km and closes inside 2 km; avoidance and the fire lane still use only the near (5 km) contacts; AC13's paired budget still holds | A | |
| AC26 | Slashing pass (Q19): pilots at the levels T18 lists fly a pass, firing within 1 s of closest approach, then burn and turn to chase; on the same seeded runs against a straight-flying drone their time with the target inside the fire gate over 60 s is at least 25 % more than the standard attack's; other levels attack as before; AC13's paired budget still holds | A | |
| AC27 | The tweaks feel right: B selects targets (hold for the previous one) and D-pad Up toggles assist; the right stick pitches, yaws and rolls (diagonals roll); free look stays where it was left until L3 is released; gun and impact sounds sit two octaves lower; reverse and side thrust feel strong; the kill / assist numbers read at a glance; buoys and wingmen far out show on the radar rim; some AI ships make slashing passes and turn to chase | H | |
| AC28 | Splat LOD (Q22): `python3 -m tools.procgen build all` writes LOD2 and LOD3 for `starfury_aurora` and `raider_fighter` (`lods[2]` about 6 % and `lods[3]` about 1.5 % of LOD0's splats, each within the share range T19 records; same AABB within 0.3 m; deterministic; existing LOD files unchanged unless T21 has changed them). `LodSwitcherMath` (pure) picks a level from the ship's projected diameter in pixels with hysteresis: a slow range sweep through every threshold switches each boundary exactly once each way, and a ship held on a threshold never flaps. In play a ship's level changes only by visibility: across a 0.2-20 km sweep with 13 ships the splat-node count never changes and GDGS records no resource rebuild. `lod` provider and `lod <ship\|all> <n\|auto>` command; AC13's paired budget still holds | A | P10 |
| AC29 | Resident splat budget (Q22): GDGS patch 5 is recorded in `addons/gdgs/PATCHES.md`; the pure sizing helper sizes the projection, sort and culled buffers from `settings.splat_budget` (visible splats), not from every resident splat; with 100 LOD-chained ships resident the sizes it returns stay within the budget's bytes; the `LodSwitcher` steps the farthest visible ships down a level until the visible sum fits, and logs once when it cannot. The Raster backend and headless runs are unaffected | A | |
| AC30 | Relighting (Q23): procgen writes a 4-byte lighting record per splat (octahedral normal, AO, confidence; GDGS `GaussianLightingResource` format 1) for every ship and buoy LOD, chunk and the hero level; on a test shape each normal is within 5° of the analytic surface normal; hull colours carry no baked shading (two splats of the same paint with opposite normals have the same colour); ships, chunks and buoys load with `relight_enabled`, the sky does not. `LightPicker` (pure) keeps the key star and the 7 highest-scoring emitters, stable under small changes (no swap within the hysteresis margin). The scene holds no `Light3D` except the picker's 8 slots. `relight [on\|off]`, the `lights` provider (picked emitters, candidates, cost per frame) | A | P9 |
| AC31 | Ship lights (Q23): every main pod has a nozzle emitter whose energy follows its `FlightOutput` level (0 at idle, full at full thrust, the plume's colour); every shot adds a muzzle-flash emitter for 60 ms; an explosion's emitter keeps today's curve (0 to 8 to 0 over 0.25 s, range 4 x radius); all go through `LightPicker`, never straight to a `Light3D`. In a headless sandbox fight with wingmen at most 8 lights are ever active, the player's own nozzles stay picked while they fire, and AC13's paired budget still holds | A | P9 |
| AC32 | Particles (Q23): bolt hull hits, rams, explosions and debris chunks emit `GPUParticles3D` effects from fixed pools (the particle node count never changes across a 120 s sandbox fight); every process material has zero gravity and zero damping, and every effect inherits its source's velocity; a burst live across a forced rebase is shifted with the world (its emitter's World-local offset follows the `rebased` offset); `settings.particle_density` (0-1) scales the amounts | A | P9 |
| AC33 | Hero LOD (Q23): `starfury_aurora` writes a `hero` level at half LOD0's spacing (about 4x LOD0's splats, within the budget T24 records), deterministic, LOD0-LOD3 unchanged by it; only the player's ship uses it (`ShipSpec.splat_hero`), in the chase and cockpit cameras, dropping to LOD0 and below by screen size like any ship; the player's hero ship plus AC19's fight stays inside `settings.splat_budget` | A | P9 |
| AC34 | Lens flare and motion blur (Q23), after the maintainer signs off the T25 choice: `settings.lens_flare` (default on) and `settings.motion_blur` (default off) toggle the compositor effects live and from the console; any vendored add-on is pinned, listed in `docs/third-party.md` with its licence, and untouched under `addons/`; headless runs and the smoke runs are unchanged | A | |
| AC35 | The visual pass reads right on the tester's GPU: no visible LOD pop at combat ranges; plumes light the pods, muzzle flashes light the nose, explosions light nearby hulls, the key star gives each hull a lit and a dark side as it rolls; sparks on hits and debris; the player's hull is visibly sharper close up; the flare follows the star and hides behind hulls; motion blur (when on) smears the stars on fast turns, not the HUD. AC19's 60 fps still holds with all of it; frame time and VRAM recorded for AC19's fight and for 100 ships (`spawn` loop), before and after T19-T20 | H | P9, P10 |

## Capture pre-checks

`scripts/capture.sh "<commands>"` (llvmpipe, GDGS Raster) or `CAPTURE_REAL_GPU=1` on a desktop. T12 bundles them as
`scripts/capture_m3.sh` writing to `reports/m3/` (gitignored). Wrap the command string in single quotes.

- **P5 allies and break-up** (AC7, AC18; T08): `god on; spawn ally idle 60 0 0; wait 20; screenshot reports/m3/p5_ally_front.png; despawn all;
  spawn ally idle 60 35 20; wait 20; screenshot reports/m3/p5_ally_three_quarter.png; set targeting.selected "ALPHA 2"; timescale 0.1;
  kill target; wait 30; screenshot reports/m3/p5_breakup.png; timescale 1; wait 60; screenshot reports/m3/p5_debris.png`
- **P6 instructor** (AC10, AC17; T09): `scenario instructor_route; wait 300; screenshot reports/m3/p6_follow.png; camera cockpit; wait 600;
  screenshot reports/m3/p6_demo.png; state route`
- **P7 wing** (AC11, AC15; T07, T11): `god on; wave stop; wait 600; screenshot reports/m3/p7_formation_chase.png; wing order engage;
  wave start 3; wait 900; screenshot reports/m3/p7_engage.png; state wing`
- **P8 dogfight** (AC12, AC15; T10): `scenario dogfight; god on; wait 1800; screenshot reports/m3/p8_dogfight.png; state ai`
- **P9 visual pass** (AC30-AC33, AC35; T21-T24): `god on; spawn ally idle 40 30 10; wait 20; screenshot reports/m3/p9_relit.png;
  wave start 1; wait 600; screenshot reports/m3/p9_fight.png; state lights; camera cockpit; wait 30; screenshot reports/m3/p9_cockpit.png`.
  GDGS relights on the Raster backend too, so llvmpipe shows the lighting; particles and Compute-only artefacts stay (H).
- **P10 LOD** (AC28, AC35; T19, T20): `god on; spawn raider idle 150 0 0; spawn raider idle 600 10 0; spawn raider idle 2000 20 0;
  spawn raider idle 6000 30 0; wait 30; screenshot reports/m3/p10_lod.png; state lod`

## Task breakdown (ordered)

| Task | Title | Depends on | Agent |
|---|---|---|---|
| M3-T01 | Keyboard layout B | - | Sonnet |
| M3-T02 | Factions as data, friendly fire | - | Sonnet |
| M3-T03 | Starfury chunks and LOD1 | - (Python only) | Opus |
| M3-T04 | Ram damage | T02 | Opus |
| M3-T05 | Contacts, avoidance and fire lane | T02 | Opus |
| M3-T06 | `AiPilot` core: utility selection, attack, evade, retreat | T05 | Opus |
| M3-T07 | Wings, formation and orders | T01, T06 | Opus |
| M3-T08 | Allied ships: pool, LOD1, destruction, replenish | T03, T06 | Sonnet |
| M3-T09 | Instructor: follow path, pacing, demo manoeuvres, route scenario | T06, T08 | Opus |
| M3-T10 | Guard, raider AI upgrade, sandbox and dogfight scenarios | T07, T08 | Opus |
| M3-T11 | HUD: wing roster, acknowledgements, waypoint marker | T07, T09 | Sonnet |
| M3-T13 | Skill ranks, aggressiveness, civilian profile, last-ditch ram (runs before T12) | T06, T10 | Opus |
| M3-T14 | Position rebase in play (far-from-origin jitter, Q13) | - | Opus |
| M3-T15 | Play-test tweaks: pad layout, gun sounds, Starfury thrust (Q15, Q17, Q20) | - | Sonnet |
| M3-T16 | Kill credit: player kills, assists, total (Q18) | T08 | Sonnet |
| M3-T17 | Broadcast contacts for the radar and the AI (Q21) | T08, T10 | Opus |
| M3-T18 | Slashing pass and chase (Q19) | T13 | Opus |
| M3-T19 | Splat LOD chain and `LodSwitcher` (Q22) | T08 | Opus |
| M3-T20 | Resident splat budget: GDGS patch 5 (Q22) | T19 | Opus |
| M3-T21 | Splat relighting: procgen normals, flat colours, `LightPicker` (Q23) | T19 | Opus |
| M3-T22 | Ship lights: nozzles, muzzle flashes, explosions (Q23) | T21 | Sonnet |
| M3-T23 | `GPUParticles3D` sparks and debris (Q23) | T14 | Sonnet |
| M3-T24 | Hero LOD for the player's ship (Q23) | T20, T21 | Sonnet |
| M3-T25 | Lens flare and motion blur, after sign-off (Q23) | T21 | Sonnet |
| M3-T26 | Starfury after the reference model, wireframe damage display (Q24) | - | Opus |
| M3-T12 | Integration, smoke runs, capture set, play-test guide | T01-T11, T13-T26 | Opus |

Parallel lanes: T01, T02 and T03 touch disjoint files and can run together; T04 and T05 can run together after T02.
Two agents at a time is steadier than four (`docs/handoff.md`).

### M3-T01 Keyboard layout B

- Goal: every flight key under the left hand (the right hand flies the mouse), per the maintainer's answer Q9.
- Agent: **Sonnet**. A data change with explicit bindings plus the tests and docs that name keys.
- Files: `project.godot` (`[input]`), `data/controls/m1_classic.cfg` (keyboard descriptors only; its pad swap stays),
  `src/input/input_adapter.gd` (comments, mouse side buttons), `docs/playtest.md` (keyboard block), `docs/architecture.md`
  §6.1 (keyboard table), tests that assert keys (`test_input_adapter`, `test_godot_input_source`, `test_control_profile*`,
  `test_control_profiles`).
- Bindings (physical keys, US positions; pad bindings unchanged):

  | Key | Action | Key | Action |
  |---|---|---|---|
  | Q | `main_left` | W | `main_left` + `main_right` (both mains) |
  | E | `main_right` | A | `retro_left` |
  | S | `retro_left` + `retro_right` (both retros) | D | `retro_right` |
  | R | `strafe_up` | F | `strafe_down` |
  | Z | `strafe_left` | C | `strafe_right` |
  | Caps Lock | `roll_left` | G | `roll_right` |
  | X | `brake` (hold) | Shift | `autotrack` (toggle) |
  | Space | `fire` (and Mouse 1) | V | `weapon_next` (fire mode) |
  | B | `target_next` (tap next, hold nearest the nose, as D-pad Up) | T | `toggle_flight_assist` |
  | Tab | `toggle_camera` | Esc | `pause` |
  | Backspace | `reset_ship` | N, Print | `screenshot` |
  | F3 / F4 | debug overlay / fallback meshes | Mouse 4 / Mouse 5 | `autotrack` / `weapon_next` (optional extras) |

  No keys for `pitch_*`, `yaw_*`, `target_prev`, `target_ahead` (mouse motion, the wheel, Mouse 2 and B cover them; their
  pad bindings stay). Ctrl and keys 1-4 stay free (T07 binds 1-4). Never bind ` (console) or Alt (frees the mouse).
- Notes: check that Godot reports both press and release for Caps Lock on X11 and Wayland in a headless `InputEventKey`
  test; if the platform toggles instead, say so in the PR (fallback: Ctrl for `roll_left`). Users' saved profiles in
  `user://controls/` keep their old keys; `controls use default` gets the new ones.
- Done when: AC1 passes; AC0 except the updated key tests.
- Verify: `scripts/run_tests.sh`; `--console-exec="controls show main_left; controls show roll_left; quit"`.

### M3-T02 Factions as data, friendly fire

- Goal: the relation rule comes from a data file (§16 D30), and friendly fire is a setting (D31, maintainer Q2).
- Agent: **Sonnet**. A pure loader with validation plus one filter change in the resolver.
- Files: `data/factions.json`, `src/combat/{factions,faction_table}.gd`, `src/combat/{damageable,hit_resolver}.gd`,
  `src/autoload/settings_schema.gd` (`friendly_fire`), `tests/unit/{test_factions,test_faction_table}.gd`,
  `tests/integration/test_friendly_fire.gd`.
- Notes:
  - `data/factions.json`: `{"factions": [{"id", "name"}], "relations": [{"a", "b", "relation": "friendly|neutral|hostile"}],
    "default": "neutral"}` with `earth_alliance`, `raiders`, `neutral` and the one hostile pair. Same id is always
    FRIENDLY; an unlisted pair is `default`; an unknown id is NEUTRAL to everything but itself (M2 rule 2).
  - `FactionTable` (pure): `from_dict(d) -> {ok, error, table}` with path-qualified errors
    (`relations[0].relation must be one of ...`), `relation(a, b)`, `ids()`, `display_name(id)`. `Factions` keeps its static
    API and constants; it holds the active table, loaded lazily from `res://data/factions.json`, and offers
    `Factions.use_table(t)` / `Factions.reset()` for tests and the console. A broken file warns and falls back to the
    built-in M2 rule.
  - Friendly fire: `Damageable.can_be_hit_by(bolt_faction, friendly_fire := false)`; on, everything active except the
    shooter's own hull can be hit (the resolver already skips the shooter). God mode is unchanged. `settings.friendly_fire`
    (bool, false); `HitResolver` reads it each tick.
  - Console: provider `factions` (`ids`, `relations`, `friendly_fire`); command `relation <a> <b> [friendly|neutral|hostile]`
    (prints or sets for this session; `relation reset`).
- Done when: AC2, AC3 (the AI fire-lane half arrives in T05) and AC0 pass.
- Verify: GUT; `--console-exec="relation earth_alliance raiders; relation earth_alliance raiders neutral; get factions.relations; quit"`.

### M3-T03 Starfury chunks and LOD1

- Goal: the Starfury breaks into its parts, and allies get a lighter splat model (§16 D35).
- Agent: **Opus**. Generator work where the output contract must stay byte-identical for LOD0.
- Files: `tools/procgen/assets/starfury_aurora.py`, `tools/procgen/core/{chunks,manifest}.py` (if LOD entries need it),
  `tools/procgen/tests/test_starfury_aurora.py` (+ chunk tests), `docs/assets-starfury.md` (LOD1 and chunks section),
  `tests/integration/test_splat_import.gd` (LOD1 and chunk PLYs).
- Notes:
  - LOD1: resample every part at a coarser spacing (start at 2× the default; pick the factor that lands at 20-30 % of
    LOD0's splats) with the same RNG streams suffixed `lod1`, scales growing with the spacing as `core/sampling.py` already
    does. Write `starfury_aurora_lod1.ply` and a manifest `lods[1]` entry (`level`, `file`, `splats`, `spacing_m`). LOD0 files
    must not change (test the SHA-256 against a pre-change build in the test, or compare counts and a few bytes).
  - Chunks from LOD1 samples with `core/chunks.py` (generic since M2-T04): `cabin` (fuselage, cockpit, gun mount) and
    `arm_ur`, `arm_lr`, `arm_ul`, `arm_ll` (strut, pod and claw on each corner; the names match `DamageZones`' Starfury
    zones if those differ, use theirs). Chunk splats partition the **LOD1** hull exactly; `hardpoints.chunks[]` as for the
    raider. The cockpit interior and depth proxy are unchanged.
- Done when: AC6 passes; `scripts/gen_assets.sh` writes the new files.
- Verify: `python3 -m unittest discover -s tools/procgen/tests -t . -v && scripts/gen_assets.sh`; GUT import test.

### M3-T04 Ram damage

- Goal: collisions hurt by impact severity (§16 D32, maintainer Q3).
- Agent: **Opus**. Contact timing against the tick order and tunnelling are subtle.
- Files: `src/combat/{ram_resolver,ram_math,hit_info,damageable}.gd`, `src/ship/{ship,ship_spec}.gd` (contact reporting,
  `ram_safe_dv_mps`, `ram_lethal_dv_mps`), `src/props/nav_buoy.gd` (mass for ram maths), `src/game/main.{gd,tscn}` (`Combat/RamResolver`),
  `assets/ships/*.tres`, `tests/unit/test_ram_math.gd`, `tests/integration/test_ram_damage.gd`.
- Notes:
  - `HitInfo.cause`: `bolt` (default), `ram`, `console`. `Damageable.core_radius` (largest sphere inside its shapes,
    about 1 m for a fighter) next to `bounding_radius`.
  - Severity is the ship's own velocity change: damage = `hull_max × clamp((Δv - safe) / (lethal - safe), 0, 1)²`.
    Starting values (tune in (H)): safe 5 m/s for every ship; lethal 18 m/s for the Starfury, 15 m/s for the raider.
    Δv is per ship, not the closing speed: a head-on between equal masses at 30 m/s closing with Jolt's default zero
    restitution gives each ship about 15 m/s, which these values turn into about 60 % of a Starfury's hull (AC4).
  - **Ship-ship at ordinary speeds**: Jolt resolves the bounce. Enable `contact_monitor` with a few reported contacts on
    ships; `RamResolver` keeps every active ship's velocity from its previous run and, for a pair whose contact began
    since then, takes Δv = |v_now - v_prev| minus what the ship's own thrust could have added in that time.
  - **Tunnelling speeds and buoys** (closing speed × dt over half the smaller `core_radius`, or no physics body): a
    target-relative swept test, each of one body's hit volumes against each of the other's over the tick (as built: exact for
    boxes and capsules, see the as-built note). Every swept hit, at tunnelling speed or against a buoy, uses the momentum split
    `Δv_self = v_rel × m_other / (m_self + m_other)` through the normal damage curve (buoy mass from its spec, about 2 t), so
    a tunnelling hit is fatal once each ship's split Δv reaches its lethal value (600 m/s closing: 300 m/s each, both
    destroyed). Controller ruling (2026-10-22, M3-T04 review), replacing "a hit at tunnelling speed destroys both".
  - AC4's "seeded offsets inside the hull overlap" means offsets at which the two hulls' collision shapes, as built from the
    hardpoints, interpenetrate by at least 0.3 m somewhere along the pass. Every such offset at 600 m/s must ram both (both
    destroyed); a pass with 0.3 m or more clearance must not ram; shallower overlaps (thin claw tips) may be left to Jolt.
    Controller ruling (2026-10-23, M3-T04 re-review).
  - One ram per pair per contact (no damage every tick of a resting contact). God mode protects the player; the bounce
    still happens. `HitInfo.shooter_id` is the other ship, so a raider that rams the player is not credited as a kill by
    the player, but `waves.kills` still counts every raider death (M2 rule).
  - Priority: after the `HitResolver` (200), before the `WaveDirector` (300), e.g. 210. Same-tick destruction rules as §15.7.
  - Console: provider `ram` (`events`, `last`, `resolve_us`); settings `ram_damage` (bool, true) for testing.
- Done when: AC4 passes.

### M3-T05 Contacts, avoidance and fire lane

- Goal: AI ships see everything around them, never fly into it, and never shoot through friends (§16 D33, D34).
- Agent: **Opus**. Closed-loop dodging through Newtonian steering is easy to make oscillate.
- Files: `src/ai/{perception,ai_pilot_driver,contact,contact_scan,avoidance_math,fire_lane}.gd`,
  `tests/unit/{test_avoidance_math,test_fire_lane,test_contact_scan}.gd`, `tests/integration/test_ai_avoidance.gd`.
- Notes:
  - `Contact` (plain data): `id`, `name`, `faction`, `relation` (to the perceiving ship), `position`, `velocity`, `forward`,
    `bounding_radius`, `is_ship`, `hull_fraction`, `target_id` (whom it has selected, -1 if unknown). `ContactScan` builds
    the list once per tick for every driver (a shared cache keyed by the physics frame) from active `Targetable`s and
    `Damageable`s within `sensor_range_m` (5 km). `Perception.contacts`, `Perception.incoming_fire` (hostile bolts whose
    closest approach is under 15 m within 2 s), `Perception.last_hit_s`.
  - `AvoidanceMath.filter(own_pos, own_vel, own_radius, contacts, v_des, capability, seed) -> {v_des, urgent}`:
    closest-approach time and distance against each contact (static props use zero velocity); a contact closer than the
    sum of radii plus `margin_m` (15) within the horizon (the time to stop, at least 4 s) adds a sideways velocity away
    from the closest-approach offset scaled by urgency; `urgent` lets the seek use RCS strafe before turning. Matched
    velocities (formation flight) only push apart when already inside the margin.
  - `AiPilotDriver` runs every brain's output through avoidance (M2 brains too, so raiders on attack runs stop ramming).
  - `FireLane.clear(own_pos, aim_dir, range_m, contacts) -> bool`: false when a friendly (or, with friendly fire on, any
    non-target ship) lies within `radius + 5 m` of the bolt path short of the target. `AttackBrain` checks it before it
    holds the trigger.
- Done when: AC5 and the fire-lane half of AC3 pass; M2's AC9 still passes.

### M3-T06 `AiPilot` core: utility selection, attack, evade, retreat

- Goal: one brain that picks what to do from scored behaviours (§16 D34).
- Agent: **Opus**. This is the interface every later AI task builds on.
- Files: `src/ai/{ai_pilot,ai_context,ai_behaviour,ai_profile,behaviour_attack,behaviour_evade,behaviour_retreat,
  behaviour_idle}.gd`, `assets/ai/{ally_starfury,raider,instructor}.tres` (`AiProfile`), `assets/ai/starfury_tactics.tres`,
  `src/ai/brain_factory.gd` (behaviour type `ai`), `tests/unit/{test_ai_pilot_selection,test_ai_profile}.gd`,
  `tests/integration/{test_ai_evade,test_ai_retreat}.gd`.
- Notes:
  - `AiPilot extends PilotBrain`; `AiBehaviour` (RefCounted): `id`, `score(ctx) -> float` (0..1), `think(ctx, dt) ->
    PilotCommand`, `enter()`, `describe()`. Selection each tick: score × the profile's weight for that behaviour; the
    current behaviour gets `stickiness` (0.15) and keeps control for at least `min_dwell_s` (1.0) unless a challenger wins
    by `emergency_margin` (0.4). Ties break by a fixed behaviour order.
  - `AiContext` = the `Perception` plus what the wing adds later (leader, slot, order, guard post, route). Orders gate
    scores (T07 fills them; default ENGAGE AT WILL for a ship without a wing).
  - Attack wraps the M2 `AttackBrain` state machine with the profile's tactics resource (the Starfury gets its own: its
    bolts fly 1 000 m/s, so fire range and cone differ) and target choice: the leader's target under ATTACK MY TARGET,
    else the best-scored hostile (near, closing, attacking a friend, damaged). Aim skill: `AiProfile.aim_error_deg` is a
    seeded slowly wandering offset on the lead, not per-tick noise.
  - Evade: scores from a hostile within 1.2 km in the rear hemisphere with its nose within 15° of us, `incoming_fire`, or a
    hit in the last 2 s. Seeded jinks: a break turn across the threat's line of fire with RCS strafe, then a reversal,
    2-4 s per jink; ends when the threat no longer points at us.
  - Retreat: hull under the profile's `retreat_below` (0.25; 0 for the instructor and raiders that fight to the death,
    per profile): extend away from the nearest hostiles at cruise + 50 m/s.
  - Idle: hold position (brake) or coast; the fallback at score 0.05.
  - `BrainFactory`: `{"type": "ai", "profile": "ally_starfury|raider|instructor", "orders": "...", ...}`.
  - Console: provider `ai` (`ships`, `by_behaviour`, `think_us`); `ai <name>` prints that ship's `describe()` with every
    behaviour's last score.
- Done when: AC8, the evade and retreat parts of AC9, and the AI half of AC13's timing pass.

### M3-T07 Wings, formation and orders

- Goal: wingmen fly with the player and take orders (maintainer Q1, Q4).
- Agent: **Opus**. Formation keeping on Newtonian ships, and the order flow from keys to brains.
- Files: `src/ai/{wing,formation,behaviour_formation}.gd`, `src/game/wing_director.gd`, `src/input/{ui_command,input_adapter}.gd`
  (order edges), `src/input/control_profile.gd` (allow-list the keyboard-only order actions), `project.godot` (actions
  `wing_attack`, `wing_form`, `wing_engage`, `wing_cover` on keys 1-4), `src/ai/pilot_steering.gd` (`align_roll`),
  `src/game/main.gd`, `tests/unit/{test_formation,test_wing}.gd`, `tests/integration/{test_ai_formation,test_wing_orders}.gd`.
- Notes:
  - `Formation` (pure): slot offsets in the leader's body frame for `finger_four` (default) and `wedge`, `line_abreast`,
    scaled by `spacing_m` (40). Finger-four with the leader at the origin: #2 left and behind, #3 right and behind, #4 right
    of #3 and further back.
  - `Wing` (RefCounted): `name` (`ALPHA`), leader (a `Combatant`, the player), members with slot indices, `formation`,
    `order` (`ATTACK_MY_TARGET`, `FORM_ON_ME`, `ENGAGE_AT_WILL`, `COVER_ME`; default COVER_ME), `engage_radius_m` (2 000).
  - Formation behaviour: slot point `p_L + B_L · offset + v_L · 0.5 s`; `v_des = v_L + clamp(k · error)` (k about 0.4 s⁻¹,
    closure capped at 60 m/s near and cruise + 100 m/s beyond 1.5 km); inside 150 m face the leader's forward and roll
    toward the leader's up (`PilotSteering.align_roll`, a P loop on roll only, gain like `face`). Avoidance keeps the 15 m
    minimum.
  - Orders gate scores: FORM_ON_ME formation only (evade still allowed); COVER_ME formation, attack only hostiles within
    `engage_radius_m` of the leader or attacking the leader; ENGAGE_AT_WILL attack anything; ATTACK_MY_TARGET attack the
    leader's selected hostile, refused with a message when there is none. While the leader is dead the wing engages at
    will and resumes its order on respawn.
  - `WingDirector` (`Combat`, priority 290): owns the wings, applies orders from `UiCommand` (keys 1-4) and the console,
    keeps an acknowledgement line for the HUD (`ALPHA 2: COPY, FORMING UP`, 3 s). Console: `wing order <attack|form|engage|cover>`,
    `wing formation <finger_four|wedge|line_abreast>`, provider `wing` (`name`, `order`, `formation`, `members`, `last_ack`).
- Done when: AC11 (minus replenish, T08) and the formation part of AC9 pass.

### M3-T08 Allied ships: pool, LOD1, destruction, replenish

- Goal: allied Starfuries come from a pool like raiders, use LOD1, die into chunks and are replaced (maintainer Q4, Q8).
- Agent: **Sonnet**. Generalising existing pool, catalog and destruction code along spelled-out lines.
- Files: `assets/ships/starfury_ally.tres`, `src/ship/{ship_spec,ship}.gd` (`splat_lod`), `src/game/{ship_catalog,ship_pool,
  ship_assembly,scenario_loader,wave_director,wing_director}.gd`, `src/combat/{destruction_director,debris_pool}.gd`,
  `tests/integration/{test_ally_pool,test_starfury_breakup,test_destruction}.gd`.
- Notes:
  - `test_destruction.gd` pins T03's interim player break-up (5 mesh-only chunks, no Starfury sets prepared); update it
    once the pool prepares the Starfury chunk sets.
  - `ShipSpec.splat_lod` (0 = LOD0): `Ship` loads `manifest.lods[splat_lod]`. `starfury_ally` = the Starfury's numbers,
    `splat_lod` 1, no cockpit interior.
  - `ShipCatalog` gains a default faction per type (`starfury_ally` earth_alliance, `raider_fighter` raiders); `ShipPool`
    builds each type with its catalog faction and names ships per acquire (`acquire(name, ...)`, prefixes from the
    caller). Scenario `pools` stays `{"type": count}`.
  - `DestructionDirector` treats any pool ship the same way (signal `ship_destroyed(combatant, info)`; keep
    `raider_destroyed` for the M2 callers or migrate them). `DebrisPool` prepares two `starfury_aurora` chunk sets (LOD1
    chunks) in every scenario, used for allies and the player.
  - Replenish: on `WaveDirector.wave_started`, `WingDirector.replenish()` acquires an ally for each empty slot 1 500 m
    behind the player at the player's velocity, flying the wing's current order.
  - Console: `spawn ally [idle|ai] [distance_m] [yaw_deg] [pitch_deg]` (named `ALPHA <n>`), provider `allies` or extend
    `wing.members`.
- Done when: AC7 and the replenish part of AC11 pass; P5 attached.

### M3-T09 Instructor: follow path, pacing, demo manoeuvres, route scenario

- Goal: an instructor who leads a route and shows the moves the M8 tutorial will check (maintainer Q5).
- Agent: **Opus**. Paced leading and closed-loop manoeuvres through the real flight model.
- Files: `src/ai/{behaviour_follow_path,route,manoeuvre,manoeuvres}.gd`, `data/scenarios/instructor_route.json`,
  `src/game/{scenario_loader,main}.gd` (routes, `invulnerable` spawns), `src/hud/{hud_input,hud_layout}.gd` (waypoint marker
  data; T11 draws the final look), `tests/unit/{test_route,test_manoeuvres}.gd`, `tests/integration/{test_instructor_route,
  test_manoeuvres_jolt}.gd`.
- Notes:
  - `Route`: waypoints as `UniversePos` with optional `demo` (`roll`, `flip_and_burn`, `strafe_box`, `pod_turn`, `all_stop`)
    and `hold_s`; `cruise_mps` (60); `pace` (the player); `loop` (bool).
  - Pacing: lag = distance from the pace ship. Full cruise under 600 m, linear to zero at 1 500 m; beyond 1 600 m brake,
    face the player and wait until it closes to 800 m. Arrival within 150 m.
  - `Manoeuvre` (pure state machines on measured state, not timers alone): **roll** a full 360° at the roll rate limit
    (integrate body roll rate); **flip_and_burn** face retrograde, then mains until the velocity is reversed or under
    2 m/s; **strafe_box** RCS right, up, left, down legs of 1.5 s each, assist holding the attitude; **pod_turn** the left
    main alone until the heading has turned over 30° (nose right, physics); **all_stop** the brake until under 0.5 m/s and
    1 °/s. Each reports `done` and a measurable result for the tests (AC10).
  - The instructor: `instructor` profile (attack weight 0, retreat 0, never fires), invulnerable (`Damageable` flag from the
    scenario, `god`-style), named `INSTRUCTOR`, faction earth_alliance. Scenario `instructor_route.json`: the five buoys,
    no waves, a route through them with one of each demo, the instructor 200 m ahead of the player at start.
  - HUD data: `HudInput.waypoint_position/label` (the instructor's next waypoint, `NAV 2`); status line
    `FOLLOW INSTRUCTOR — NAV 2/6 — NEXT: ROLL`. Console provider `route` (`index`, `count`, `lag_m`, `state`, `demo`).
- Done when: AC10 passes; P6 attached.

### M3-T10 Guard, raider AI upgrade, sandbox and dogfight scenarios

- Goal: raiders fight as groups on the new AI, wingmen join the sandbox, and a dogfight scenario exercises everything
  (maintainer Q6, Q7).
- Agent: **Opus**. Tuning and balancing many AI ships at once.
- Files: `src/ai/behaviour_guard.gd`, `assets/ai/raider.tres` (profile, wedge groups), `src/game/{scenario_loader,wave_director,
  wing_director}.gd` (`wings` for raiders too), `data/scenarios/{combat_sandbox,dogfight}.json`, `tests/integration/{test_ai_guard,
  test_dogfight,test_m3_sandbox}.gd`; for the hit reaction (Q11) `src/ai/{behaviour_evade,ai_pilot}.gd`, `assets/ai/*.tres`,
  `tests/unit/test_ai_pilot_selection.gd`, `tests/integration/test_ai_evade.gd`.
- Notes:
  - Hit reaction (maintainer Q11): today a hit scores evade only `HIT_SCORE` 0.5 x the profile weight (0.4-0.45), below a
    running attack (0.3-0.8 plus stickiness), so a hit ship rarely evades. Make a fresh bolt hit an interrupt: evade takes
    over on that tick or the next, regardless of stickiness and the minimum dwell, flies at least one full jink, and is
    renewed by further hits; then normal selection resumes. A retreating ship that is hit jinks too, then keeps retreating.
    Profiles with evade weight 0 (the instructor) never react. Keep `score` cheap (AC13 paired budget). Raiders and allies
    both; record in the as-built notes how often hit ships now evade in `dogfight` and what it does to the kill rate.
  - Guard behaviour: hold a post (a ship's slot or a `UniversePos`) within `guard_radius_m` (1 500), attack hostiles inside
    it or attacking the guarded ship, return to the post after.
  - Scenario schema: `wings[]` `{name, faction, leader: "player" | <spawn name>, formation, order, members: [{type, name,
    offset, behaviour}]}`; wave spawns may name a `wing` so raiders form groups (`RED`, `BLUE`); a raider wing's leader is
    its first member, and a dead leader hands over to the next.
  - `combat_sandbox`: wing `ALPHA` with three `starfury_ally` members on the player (COVER ME); raider pool 9; waves
    TARGET PRACTICE 4 idle, PATROL 5 (groups of 3 + 2 on the AI with patrol routes), STRIKE 6 (two groups of 3); loop +1 up
    to 9. Kills, losses and the status line as in M2.
  - `dogfight.json`: four allies (wing ALPHA, ENGAGE AT WILL, leader ALPHA 2) and six raiders (RED, BLUE) 4 km apart; the
    player starts 3 km off to the side. For headless tuning and AC12.
- Done when: AC12 and the guard and hit-reaction parts of AC9 pass; P8 attached.

### M3-T11 HUD: wing roster, acknowledgements, waypoint marker

- Goal: the player can see the wing and the route at a glance.
- Agent: **Sonnet**. Layout from a pure model, as in M2-T08.
- Files: `src/hud/{hud_layout,hud_frame,hud_input,hud}.gd`, `src/game/main.gd` (`_build_hud_input`), `tests/unit/test_hud_layout.gd`,
  `tests/integration/test_hud.gd`.
- Notes: green line theme. **Roster** top-left: one row per wing member (callsign, a hull bar in the faction colour,
  the behaviour or order in short form: `FORM`, `ATK RAIDER 3`, `EVADE`, `DOWN`). **Acknowledgement** line under the status
  line for 3 s, naming the order issued in words (Q16, 2026-10-26: the maintainer pressed 1-4 and saw nothing), e.g.
  `ALPHA 1: FORM ON ME`, `ALPHA 1: ATTACK MY TARGET (RAIDER 3)`, and the refusal text when ATTACK MY TARGET has no target. **Waypoint marker**: a diamond with `NAV n` and range at the projected route point, an edge arrow when
  off-screen. Allies already show blue in the radar and target box (`Factions.hud_color`). Chase-view layout and opacity
  as in M2.1.
- Done when: the HUD parts of AC10 and AC11 pass; P6 and P7 show them.
- Done (2026-10-31): `WingDirector.hud_roster` gives one row per slot (`callsign`, `hull`, `behaviour`, `target`, `down`);
  `Wing.mark_lost` keeps a shot-down wingman's slot on the roster as `DOWN` (in red, empty bar) until a replacement
  takes it, and slots never flown are left out. `HudLayout._wing` stacks the rows top left (a 64 px hull bar in the
  wing's colour, then `ALPHA 3  ATK RAIDER 3`; `roster_tag` maps behaviour ids to `FORM`, `ATK <target>`, `EVADE`,
  `RETREAT`, `NAV`, `IDLE`) and puts `WingDirector.ack_text()` centred under the status line and AUTO-TRACK's line, in
  both views. `Main._build_hud_input` fills both. The waypoint marker landed with T09 and keeps its look. Tests:
  `test_hud_layout.gd` (tags, rows, ack line), `test_wing.gd` (lost slots), `test_wing_orders.gd` (the rows and the
  line reach the HUD input; a downed slot reads DOWN). P6 and P7 are captures (H), taken in T12.

### M3-T13 Skill ranks, aggressiveness, civilian profile, last-ditch ram

Added 2026-10-24 for maintainer Q12; numbered last to keep the earlier ids, run before T12.

- Goal: AI ships differ by skill and temperament per ship, so civilian, raider and military AI feel different, and a
  reckless ship that is losing may try to ram.
- Agent: **Opus**. Cross-cutting tuning of every behaviour plus one new behaviour with a physics test.
- Files: `src/ai/{ai_temperament,behaviour_ram}.gd` (new), `src/ai/{ai_profile,ai_pilot,ai_context,ai_console,
  ai_pilot_driver,behaviour_attack,behaviour_evade,behaviour_retreat,brain_factory}.gd`, `assets/ai/civilian.tres` (new)
  and the other profiles (defaults), `src/game/{scenario_loader,ship_pool}.gd` (spawn fields, `spawn ... skill= aggression=`),
  `tests/unit/{test_ai_temperament,test_behaviour_ram}.gd`, `tests/integration/{test_ai_skill,test_ai_ram}.gd`.
- Notes:
  - `AiTemperament` (pure): parses ranks or numbers (skill `rookie` 0.2, `regular` 0.45, `veteran` 0.7, `ace` 0.95;
    aggression `passive` 0.0, `cautious` 0.25, `balanced` 0.5, `aggressive` 0.75, `reckless` 1.0), and maps them onto
    the profile's numbers. A profile's own tuned values are what `regular` + `balanced` give, so today's tests keep their
    numbers at the defaults.
  - Skill: aim error (ace about 0.4x the profile's, rookie about 2.5x), reaction delay to a new threat or hit (ace 0.1 s,
    regular 0.25 s, rookie 0.6 s), fire discipline (the miss-distance gate tighter with skill: fewer wasted bolts), and evade
    quality (shorter, less regular jinks with skill).
  - Aggression: attack weight up and evade / retreat weights down with aggression; retreat threshold (cautious about 2x the
    profile's, aggressive half, reckless never retreats); engage range and break-off distance (closer with aggression);
    `passive` never starts an attack (it may fire back at a ship that hit it in the last 10 s unless the profile never
    fires).
  - Defaults: `ally_starfury` (the military profile) `veteran` / `balanced`; `raider` `regular` / `aggressive`;
    `instructor` `ace` / `passive` (never rams, never fires); new `civilian` `rookie` / `passive` (attack weight 0, fires
    false, retreat whenever a hostile is within 3 km, evade on). Scenario and wave spawns and `spawn` may override per ship;
    `dogfight` gets one `reckless` raider group so the ram shows up.
  - Last-ditch ram (`BehaviourRam`): eligible only at aggression 1.0, own hull under 25 %, and friendly ships within sensor
    range at most a quarter of the most it has seen this engagement (none counts). While eligible, a seeded roll every 5 s
    (35 % each) commits it. A committed rammer picks its attack target or the nearest hostile ship (never a prop), flies a
    lead-collision course at full mains, and tells `AiPilotDriver` to leave that one contact out of avoidance (every other
    contact is still avoided). It stays committed until the target dies, then normal selection resumes. T04's
    `RamResolver` does the damage. Keep `score` cheap (AC13 paired budget).
  - Console: `ai <name>` gains `skill`, `aggression`; `ai <name> skill <rank|0-1>` and `ai <name> aggression <level|0-1>`
    set them; the `ai` provider's `by_behaviour` counts `ram`.
- Done when: AC20 passes and the hit-reaction latency by skill in AC9 holds.

### M3-T14 Position rebase in play

Added 2026-10-25 for the maintainer's bug report (Q13); independent of the AI tasks, so it can run at once. Run before
T12.

- Goal: the ship never shows float32 jitter however far it flies, because the world keeps its origin near the player,
  as §14.1 designs.
- Agent: **Opus**. Small change, wide audit: every system has to survive a rebase at any tick in a live fight.
- Files: `src/game/main.gd` (or `main.tscn`: `World.auto_rebase_distance_m` 5 000), `src/world/world_frame.gd` (docs,
  a `rebases` count and the last rebase's cost on the `world` provider), any system the audit finds caching a
  World-local position between ticks, `tests/integration/{test_world_frame,test_rebase_in_play}.gd` (the second new),
  `scripts/run_tests.sh` (a smoke line: `rebase -900000 0 0; wait 1; state world`), `docs/architecture.md` (§14.1,
  §15.3 tick order, §6.4 `world` and `rebase` rows, the seams table's "auto-rebase off"), `docs/roadmap.md` (M6:
  position rebase is already on), `docs/playtest.md` (AC22 check).
- Notes:
  - Reproduce first: in today's build `rebase -900000 0 0` puts everything 900 km from the local origin without moving
    anything in universe terms, which is the maintainer's case. Measured in script (float32 `Vector3`, 60 Hz, constant
    thrust): the tick-to-tick change of step is 0.46 mm at 5 km, 7.3 mm at 100 km, 5.4 cm at 900 km.
  - Keep `WorldFrame`'s default at 0 (bare-World tests mean it); `Main` turns it on. The velocity rebase stays M6.
  - The rebase runs in `World._physics_process` (priority 0, before its children). Write down where that falls in
    §15.3: after the AI drivers (-10) and `Main`, before ships and bolts, so commands built before it stay valid
    (levels and rates) and everything after it sees the new frame.
  - Audit everything that keeps a position between ticks: `ShipPool` and `DebrisPool` parking, impact and muzzle
    effects, `AudioDirector` voices, the HUD reference point (`UniversePos`, recomputed each frame), `WaveDirector`
    spawn points, props, `ContactScan`, `AiPilot` behaviours, T07 formation slots, T09 routes and T10 guard points (they
    must store `UniversePos` or rebuild from live nodes each tick), `CameraRig` (chase camera shiftable, cockpit pivot
    reset), `SplatPoseSync`, explosions, debris, bolts, `RamTracker`, `HitResolver`, `TargetingController`,
    `SkyFollower`. List what you checked in the report.
  - Physics interpolation: the rebase resets every shifted node's interpolation, so the frame after a rebase shows the
    current tick without interpolation. Check that everything snaps together (no node left interpolating across 5 km)
    and leave the felt hitch to AC22 (H).
  - Tests that the AI tasks in flight (T07, T09, T10, T13) can reuse: a helper that runs a fight with the threshold
    forced low, so their own rebase checks are one line.
- Done when: AC21 passes; AC22 is in the play-test checklist.

### M3-T15 Play-test tweaks: pad layout, gun sounds, Starfury thrust

Added 2026-10-26 for the maintainer's play-test requests Q15, Q17 and Q20; the pad part amended 2026-10-30 (the right
stick pitches, yaws and rolls, a long B press selects the previous target, free look holds its view while L3 is held). Independent of the AI tasks; run before T12.

- Goal: small changes the maintainer asked for after flying the M3 build.
- Agent: **Sonnet**. Three mechanical changes, each with a test.
- Files: `project.godot` (`[input]`), `data/controls/m1_classic.cfg` (header comment), `src/input/input_adapter.gd` (right
  stick sectors, the D-pad ramp's removal, the second tap-or-hold button, comments that name D-pad Up),
  `src/autoload/settings_schema.gd` (`yaw_ramp_s`, the `target_hold_s` doc), the control-profile loader (saved-profile
  migration),
  `src/camera/camera_look.gd` and `tests/unit/test_camera_look.gd` (free look),
  `tools/procgen/assets/sfx_combat.py` and `tools/procgen/tests/test_sfx_combat.py`,
  `assets/ships/{starfury_aurora,starfury_ally}.tres`, `src/ship/ship_spec.gd` (defaults and docs),
  `tests/unit/test_input_adapter.gd`, `test_godot_input_source` and the input-map and profile tests, `docs/architecture.md`
  (§6.1 pad table and D7, D6 and the §5.5 manoeuvre table and assist text where they name the D-pad's yaw, the §5 spec
  table, the §6.1 / §8 free-look text), `docs/playtest.md` (pad layout, the L3 line, the AC17 targeting line).
- Notes:
  - **Pad layout (Q15, amended 2026-10-30)**:
    - **Right stick, three axes by direction**: the stick is bound to `pitch_*` (Y, axis 3) and `yaw_*` (X, axis 2; it
      was roll), read as one vector with today's radial deadzone and expo, then split into eight 45° sectors:
      - within 22.5° of straight up or down: **pitch** only;
      - within 22.5° of straight left or right: **yaw** only;
      - the four diagonals between: **roll** only, toward the side the stick leans (up-right and down-right roll right,
        up-left and down-left roll left; planner call).

      Only one axis is driven at a time, at the stick's full deflection after deadzone and expo. The sector half-width
      (22.5°) is one named constant in `InputAdapter`. Make the split a pure function with unit tests at 0°, 22°, 23°,
      45°, 67°, 68°, 90°, 135°, 180°, 225° and 315°, and inside the deadzone. `invert_y` still flips pitch, and free look
      (L3) still gives the stick to the camera. The pod-yaw command (D6) adds to the stick's yaw instead of the D-pad's,
      capped together at `rate_max` as before. Roll is the stick's roll plus the roll keys (Caps Lock / G, unchanged),
      clamped to ±1.
    - **D-pad Left / Right** (`JOY_BUTTON_DPAD_LEFT` / `_RIGHT`, 13 / 14): **no binding**, left free (maintainer). The
      digital yaw ramp loses its only user: remove `_step_yaw`. Remove `yaw_ramp_s` from the schema if `Settings.revert`
      ignores unknown saved keys; otherwise keep it, documented as unused. Say which in the report.
    - **B** (`JOY_BUTTON_B`, 1): a new action, `target_cycle`, with the tap-or-hold rule. A tap gives `target_next` on
      release. A hold of `target_hold_s` (0.35 s) gives `target_prev` once as the threshold is crossed, and the release
      then gives nothing, so a long press steps back one target, as the mouse wheel does. Holding longer does not
      repeat. It is a separate action because keyboard B and Mouse 2 keep `target_next`'s rule (hold = nearest the
      nose); `InputAdapter` runs the two tap-or-hold buttons on separate timers, and `reset` and focus changes drop
      both. The pad then has no `target_ahead` (keyboard B, a Mouse 2 hold or the console still give it).
    - **Free look holds its view (2026-10-30)**: today, with L3 held, the right stick gives an absolute direction
      (`CameraLook.step`: centre = look ahead), so letting the stick go swings the view back to the nose while L3 is
      still down. Wanted: while L3 is held the view stays where the stick left it; only releasing L3 eases it back to
      the nose (`RETURN_RATE_PER_S`, unchanged). Planner call: the stick becomes a **rate**, not a position: the view
      turns at `stick × STICK_LOOK_RATE_DEG_S` (180°/s at full deflection, a named constant), clamped to the mode's
      limits, and a centred stick holds the view. An absolute stick that holds would jump the view back toward centre
      on the next small push. The mouse already holds where it stops; keep that. Free look reads the raw stick vector
      (both axes together), not the flight sectors above. Rewrite the `test_camera_look` cases that assume the absolute
      stick (the full-stick and half-stick cases, "a stick back at centre returns the view while still held"); add a
      centred stick holding the view over many ticks, the clamp at the limits, and the ease back on release.
    - **D-pad Up** (`JOY_BUTTON_DPAD_UP`, 11): `toggle_flight_assist` (edge). D-pad Down stays `weapon_next`.
    - Keyboard and mouse bindings do not change, and AC1's table still holds.
    - **Saved profiles**: a profile whose pad events match the old default layout gets the new pad events, and its
      keyboard and mouse events are kept. A profile with its own pad bindings is left alone and logged once.
      `m1_classic` keeps its pad layout (stick X yaw, D-pad roll, D-pad Up targets, B assist): with the adapter change
      its stick yaws in proportion instead of through the ramp and rolls on the diagonals, and its D-pad still rolls at
      full rate. Update its header comment and say in the report what changed for it.
  - **Gun and impact sounds (Q17)**: two octaves lower = every frequency in `pulse_fire`, `raider_fire` and `hit_hull` ÷ 4
    (sweeps, partials, noise bands), lengths and envelopes unchanged; do not resample (that would stretch them 4x). Bump
    the generator's version so caches rebuild. Leave the engine, thruster, explosion and UI sounds. (H) by ear in AC27.
  - **Thrust (Q20)**: forward stays 0.36 MN per pod (1.44 MN, 30 m/s²); `pod_retro_thrust` 0.18 to 0.36 MN per pod
    (reverse = forward); `rcs_force_max` (0.48, 0.48, 0) to (0.72, 0.72, 0) MN (50 % of forward, which beats today's side
    thrust), sway and heave both. Starfury specs only (player, ally, instructor); the raider's spec is unchanged. The
    brake's all stop and the AI (`ShipCapability` reads the spec) get stronger with it: expect tests that hard-coded a
    stopping distance or time to move, and fix them to read the spec, never new constants. Watch T07's formation
    (AC9) and T09's demos (flip-and-burn), which ran on the old numbers.
- Done when: AC23 passes and AC27's first three checks are in the play-test checklist.

### M3-T16 Kill credit: player kills, assists, total

Added 2026-10-26 for Q18; run before T12.

- Goal: the HUD tells the player what they did, not only what the wing did.
- Agent: **Sonnet**. Bookkeeping on hits the code already attributes (`HitInfo.shooter_id`).
- Files: `src/game/wave_director.gd` (counts, status line, `waves` provider), `src/combat/kill_credit.gd` (new, pure:
  who gets what for one death), the player's fire path (to note "fired while this ship was selected"),
  `tests/unit/test_kill_credit.gd`, `tests/integration/test_kill_credit_in_play.gd`, `docs/architecture.md` §6.4 (`waves`).
- Notes:
  - **Player kill**: the killing `HitInfo.shooter_id` is the player ship. For a ram, check what `RamResolver` puts in
    `shooter_id`; the player's own ram counts as a player kill.
  - **Assist**: the ship died, the kill is not the player's, and the player fired at least one shot while that ship was
    their selected target (fired, not hit: the request's words; record it per ship id until the ship dies or is released
    to the pool, so a reused pool ship starts clean).
  - **Total**: today's `kills` (enemy ships destroyed by anyone, rams included). Status line, planner call:
    `KILLS 7   YOURS 3   ASSISTS 2`. Counts last the session, across respawns, like `kills` today.
- Done when: AC24 passes; the status line shows in P7.

### M3-T17 Broadcast contacts for the radar and the AI

Added 2026-10-26 for Q21 (the AI half the same day); after T10 (raiders on `AiPilot`); run before T12.

- Goal: the player and the AI can find the buoys and the wing from far away, as with a beacon's broadcast, so that later
  missions can send a raider at a buoy or the station from beyond sensor range.
- Agent: **Opus**. A per-contact range on the targeting side, a radar rim marker, and a far-contact list in the AI's
  perception that must not cost AC13's paired budget.
- Files: `src/targeting/{targetable,targeting_system,target_info}.gd` (`broadcast_range_m`, 0 = none), `src/hud/radar_model.gd`
  (rim marker), `src/props/nav_buoy.gd`, `src/game/ship_pool.gd` (allies), `src/ai/{perception,ai_pilot,ai_context,ai_console,
  behaviour_attack}.gd` (broadcast contacts, the objective), `tests/unit/{test_radar_model,test_targeting_system}.gd`,
  `tests/integration/{test_broadcast,test_ai_objective}.gd`, `docs/architecture.md` (targeting, radar, §16 perception).
- Notes:
  - A contact is listed when it is within the 25 km sensor range or within its own `broadcast_range_m`: allies 100 km,
    nav buoys 1 000 km. `INF` must work (hyperspace destination gates, M11). Measure range from universe positions (or
    World-local, which T14's rebase keeps exact enough), never cached across ticks.
  - Radar, planner call: inside 25 km nothing changes; beyond, a broadcast contact sits on the rim in its true direction as
    a hollow dot. Selecting it puts its range in the target box as today.
  - **AI (maintainer, 2026-10-26)**: every AI ship receives the same broadcasts at the same ranges, whatever its faction.
    `ContactScan` (5 km) stays the near scan for avoidance, the fire lane and threat picking; broadcasts arrive as a
    separate, short `Perception` list (one registry of broadcasters, kept in step with the pool, not a second physics or
    distance sweep over every body). Behaviours do not chase far contacts on their own: a pilot **objective** (one target
    by name, `ai <name> objective <target|none>` and a spawn field) makes attack fly toward it from any broadcast range and
    attack it once near. That is the seam M5's mission scripts use ("raiders attack the buoy / the station").
  - Later broadcasters (the station, jumpgates, 1 000 km) are recorded in `docs/roadmap.md` (M6, M7, M11); they register
    with the same list, so the AI sees them too.
- Done when: AC25 passes (radar and AI halves); the radar rim shows in a capture with a buoy moved past 25 km.

### M3-T18 Slashing pass and chase

Added 2026-10-26 for Q19; after T13 (it is keyed to skill and aggression); run before T12.

- Goal: better pilots fight like Starfuries: a firing pass through the target, then a burn to kill the overshoot and a
  turn to chase, keeping the guns on the target as long as possible.
- Agent: **Opus**. A new attack mode with a physics test and the AC13 budget to keep.
- Files: `src/ai/behaviour_attack.gd` (or a new `src/ai/attack_slash.gd` it delegates to), `src/ai/ai_temperament.gd`
  (which levels use it), `tests/unit/test_attack_slash.gd`, `tests/integration/test_ai_slash.gd`.
- Notes:
  - The pass: close at speed on a lead course, firing through closest approach (the fire gate decides, as now), keeping
    avoidance on so it passes clear of the target.
  - After the pass: flip or pod-turn onto the target and burn to cancel the overshoot, then chase at a small closing
    speed, holding the target inside the fire gate. Retros now equal the mains (T15), so this works on both.
  - Planner call (say if you want it changed): skill `veteran` or `ace` with aggression `balanced` or higher use the
    slashing pass; everyone else attacks as today. A profile may turn it off (instructor, civilian).
  - Measure "time on target" (ticks with the target inside the fire gate) and use it for AC26 against the standard
    attack on the same seeds.
- Done when: AC26 passes; the paired AC13 test still passes; the dogfight scenario shows it.

### M3-T19 Splat LOD chain and `LodSwitcher`

Added 2026-10-28 for Q22 (pulled forward from M6); after T08 (the ally pool and LOD1); run before T12.

- Goal: a ship far away draws a few thousand splats instead of tens of thousands. A Starfury 2 km away is about 10 px
  wide at 1080p (70° FOV) but draws all of LOD1's ~37k splats today. Every visible splat adds at least one sort key, and a
  small ship's splats all land in one or two 16 px tiles, which one workgroup then blends one after another.
- Agent: **Opus**. A generator extension plus a switching rule that must not trigger GDGS's full buffer rebuild.
- Files: `tools/procgen/assets/{starfury_aurora,raider_fighter}.py` and their tests, `src/rendering/lod_switcher.gd` (node),
  `src/rendering/lod_switcher_math.gd` (new, pure), `src/ship/ship.gd` / `src/game/ship_assembly.gd` (one splat node per
  LOD), `src/autoload/settings_schema.gd`, `tests/unit/test_lod_switcher_math.gd`, `tests/integration/test_lod_in_play.gd`,
  `docs/architecture.md` (§7 rendering, §16 D22 node count), `docs/assets-starfury.md`.
- Notes:
  - **Procgen**: LOD2 = every spacing × 4, LOD3 = × 8, the way LOD1 uses × 2 (`LOD1_SPACING_FACTOR`), with RNG streams
    suffixed `lod2` / `lod3` and scales growing with the spacing. Starfury and raider; the buoys keep LOD0 (5 small props).
    Record each share range in the generator, as `LOD1_SHARE` does.
  - **Switch by visibility, never by resource.** Setting a node's `gaussian` marks the resource dirty and GDGS rebuilds
    every GPU buffer and re-uploads every splat in the scene; visibility rides in the instance transform
    (`model_matrix[0][3]`) and costs one transform upload. So each ship carries one `GaussianSplatNode` per LOD it can
    use (resources are shared, so splat data is stored once), exactly one visible. The node count is fixed when the
    pool is built (D22 holds). Count GDGS rebuilds (a counter on the render manager's rebuild path, read by the test) to
    prove none happen.
  - **Rule (planner call)**: projected diameter in pixels from the ship's bounding radius, camera FOV and viewport height.
    LOD0 ≥ 200 px, LOD1 ≥ 60 px, LOD2 ≥ 16 px, else LOD3; step up only 25 % past a threshold (hysteresis). Chains:
    player and raiders LOD0-LOD3, allies LOD1-LOD3 (as today at the near end). Evaluate in `_process`, change visibility
    only when the level changes. Debris chunks keep LOD1 (short-lived).
  - GDGS cannot cross-fade (no per-splat opacity), so a switch pops; at these sizes the pop is under a pixel or two.
    AC35 judges it.
  - `settings.splat_lod_bias` (-1 to +1 levels, default 0) for the tester. `lod` provider: per-ship level, visible splat
    total.
- Done when: AC28 passes; P10 shows the four raiders at four levels.

### M3-T20 Resident splat budget: GDGS patch 5

Added 2026-10-28 for Q22; after T19.

- Goal: hidden LODs and off-screen ships cost no sort memory, so 100-500 ships fit in VRAM.
- Agent: **Opus**. A patch to vendored GPU code that the container cannot run (llvmpipe falls back to Raster).
- Files: `addons/gdgs/runtime/render/compute/{gaussian_renderer,gaussian_gpu_state_cache,gaussian_scene_registry}.gd`
  and `shaders/gsplat_projection.glsl` (each changed line marked `[space-combat-sim patch]`), `addons/gdgs/PATCHES.md`
  (patch 5), a pure sizing helper the tests can call, `src/rendering/lod_switcher.gd` (budget step-down),
  `src/autoload/settings_schema.gd`, `tests/unit/test_splat_budget.gd`.
- Notes:
  - Today GDGS sizes its buffers by every resident instanced splat, hidden ones included: 32 sort slots × 8 B, 64 B of
    projected data and 8 B of instance id, about 330 B each. LOD1 allies at 100 ships are about 1.2 GB; at 500, about
    6 GB. Carrying the LOD chain makes it about 1.35x LOD0 per ship.
  - Patch: (1) a small per-frame table of visible instances (start, count, resource base), with a prefix sum; the
    projection pass runs over visible splats only and finds its instance by binary search, which replaces the per-splat
    instance-id buffer; (2) the culled and sort buffers sized from `settings.splat_budget` (visible splats, planner call
    2 000 000), not from the resident total; patch 1's clamps stay as the overflow guard.
  - The `LodSwitcher` keeps the visible total under the budget: when over, it steps the farthest visible ships down one
    level until it fits, and logs once if even LOD3 everywhere does not fit.
  - The Raster backend is not touched. Upstream candidate, like patches 1 and 2.
  - Compute-only: AC35 records frame time and VRAM before and after on the tester's GPU.
- Done when: AC29 passes; patch 5 is in `PATCHES.md` with how to revert it; AC35's VRAM numbers are asked for.

### M3-T21 Splat relighting: procgen normals, flat colours, `LightPicker`

Added 2026-10-28 for Q23; after T19 (it writes records for every LOD). The biggest visual gain, with no new dependency.

- Goal: ship hulls are lit by the scene: the key star gives each hull a lit and a dark side, and later (T22) plumes,
  flashes and explosions light nearby hulls.
- Agent: **Opus**. It changes every ship asset's colours and the lighting contract (§7: "splats are pre-lit").
- Files: `tools/procgen/core/` (normal records, writer), `tools/procgen/assets/{starfury_aurora,raider_fighter,nav_buoy}.py`
  and tests, `src/rendering/splat_lighting_loader.gd` (new: wraps the bytes in a `GaussianLightingResource`, no per-splat
  loop), `src/rendering/light_picker.gd` (new, pure), `src/rendering/splat_light_rig.gd` (new node: the 8 slots),
  `src/environment/space_environment.tscn|.gd` (the key star becomes slot 0), `src/ship/ship.gd` (the cabin light becomes
  an emitter), `src/autoload/settings_schema.gd`, `tests/unit/{test_light_picker,test_splat_lighting_loader}.gd`,
  `tests/integration/test_relight.gd`, `tools/procgen/tests/` (normals, flat colours), `docs/architecture.md` (D8, §7.1,
  §7.2), `docs/research-notes.md` (relighting now used).
- Notes:
  - **GDGS already relights** (v3.3.0, vendored): per splat, in the projection stage, from up to `MAX_LIGHTS = 8`
    directional, omni and spot lights, with Godot's own falloff; the Raster backend matches it. It needs a
    `GaussianLightingResource` per splat file: 4 bytes per splat (octahedral normal ×2, AO, confidence). GDGS bakes that
    in the editor from a voxel proxy; procgen already knows every splat's exact surface normal, so it writes the bytes
    itself (`<asset>_lod<n>.light`, manifest field per LOD and chunk) and skips the bake. AO: a cheap per-part cavity term
    or 1.0 (agent's call, say which). Confidence 255 on the surface.
  - **Flat colours**: remove any baked light or shade term from hull colours (keep paint, panel lines, weathering).
    Emissive parts (windows, lenses) must not darken: read `relight_factor()` in the shader and pick how (low confidence,
    or a separate unlit node); say which. Bump generator versions. LOD0 bytes change here, so AC6's "LOD0 byte-identical"
    applies to T03's run, not after T21.
  - **Shadows**: splats do not receive shadows; `relight_cast_shadows` off in M3 (nothing mesh-like to receive them).
  - **Why a picker**: GDGS's rig walks the whole scene for `Light3D` nodes every 30 frames, ranks by energy × range at
    that moment, and drops all past 8. A 60 ms muzzle flash would be missed and a far explosion could push out the
    player's nozzles. So the scene holds exactly 8 `Light3D` nodes (the key star, 7 omni slots), created once and never
    freed; `LightPicker` chooses which emitters fill the 7 slots each frame and the rig copies the slot's position,
    colour, energy and range (it re-reads cached lights every frame, so a moved slot shows at once). Unused slots sit at
    energy 0 (the rig skips them). Meshes are lit by the same 8, so meshes and splats agree.
  - **Score (planner call)**: priority class (player's own > explosion > muzzle flash > nozzle > cabin) × energy × range
    ÷ distance to the camera², with a 20 % bonus for the incumbent so slots do not flicker. The cabin light counts only in
    the cockpit camera.
  - The rig's walk stops after 20 000 nodes (`MAX_VISITED_NODES`): put the rig node before `World` in the tree so its
    slots are found when M4 has 500 ships.
  - The sky stays unlit (`relight_enabled` off: stars are emitters). Debris chunks and buoys are lit.
  - `settings.splat_relight` (default on) and `relight [on|off]`; the knobs (`relight_ambient`, `relight_unlit_level`,
    `relight_light_gain`) as settings so the tester can tune them live.
- Done when: AC30 passes; P9 shows a lit and a dark side on the ally.

### M3-T22 Ship lights: nozzles, muzzle flashes, explosions

Added 2026-10-28 for Q23; after T21.

- Goal: plumes light the pods and struts, a shot lights the nose, an explosion lights nearby hulls.
- Agent: **Sonnet**. Emitters feeding T21's picker; no rendering work.
- Files: `src/rendering/light_emitter.gd` (new, RefCounted record), `src/ship/thruster_visuals.gd` (nozzle emitters),
  the gun's fire path (muzzle flash), `src/combat/explosion.gd` (its `OmniLight3D` becomes an emitter),
  `tests/unit/test_light_emitters.gd`, `tests/integration/test_ship_lights.gd`.
- Notes:
  - One emitter per main pod nozzle, 1.5 m out along the exhaust axis (so it falls on the pod and strut, not inside the
    splat shell), energy from the pod's `FlightOutput` level, the plume material's colour, range about 15 m (tune by
    eye). RCS jets and bolts get no lights (too many; planner call).
  - Muzzle flash: 60 ms at the muzzle hardpoint, per shot. Explosion: today's curve and range, through the picker.
  - All ships, raiders included; the picker decides which reach the 7 slots.
  - Visuals in `_process`; the physics tick only publishes levels. Record the picker's per-frame cost in `lights`.
- Done when: AC31 passes; P9's fight frame shows lit pods.

### M3-T23 `GPUParticles3D` sparks and debris

Added 2026-10-28 for Q23; after T14 (particles must follow the rebase).

- Goal: hits, rams and explosions throw sparks and glowing fragments; debris chunks spark and vent for a few seconds.
  Splats cannot do this (static radiance, no per-splat animation), so it stays in Godot's particles (D8).
- Agent: **Sonnet**. Built-in nodes in a fixed pool.
- Files: `src/combat/fx_pool.gd` (new: fixed `GPUParticles3D` pools per effect), `src/combat/fx_specs.gd` (new, pure:
  amounts, lifetimes, speeds per effect), `src/combat/{hit_resolver,ram_resolver,explosion,debris_pool}.gd` (emit
  calls), `assets/fx/*.tres` (process materials, hand-made and tiny), `src/autoload/settings_schema.gd`,
  `tests/unit/test_fx_specs.gd`, `tests/integration/test_fx_pool.gd`.
- Notes:
  - Effects: hull hit (spark streaks reflected about the hit normal), ram (sparks along the contact), explosion (glowing
    fragments, a short expanding gas shell), debris (sparks and venting for 2-4 s).
  - **Newtonian**: process materials have zero gravity and zero damping; every burst inherits its source's velocity. The
    damping guard test is extended to them.
  - Pools: one-shot emitters restarted from a fixed pool, never instanced per hit (as `DebrisPool`).
  - **Rebase**: emitters live under `World`; a burst in global coordinates would jump on a rebase. Use local coordinates
    under an anchor the `rebased` handler shifts (or shift the emitters' transforms; say which).
  - Unshaded, emissive, additive; the hull depth proxies hide them behind hulls as they hide plumes.
  - Headless has no particle simulation: (A) tests the pools, specs and wiring; the look is AC35.
- Done when: AC32 passes; P9's fight frame shows sparks.

### M3-T24 Hero LOD for the player's ship

Added 2026-10-28 for Q23; after T20 (the budget) and T21 (lighting records for the new level).

- Goal: the player's own Starfury is sharper close up (panel lines, edges, canopy frames) without making every ship
  heavier.
- Agent: **Sonnet**. A generator variant and one spec flag on T19's chain.
- Files: `tools/procgen/assets/starfury_aurora.py` and tests, `src/ship/ship_spec.gd`, `assets/ships/starfury_aurora.tres`,
  `src/rendering/lod_switcher.gd`, `tests/integration/test_hero_lod.gd`, `docs/assets-starfury.md`.
- Notes:
  - `hero` level at every spacing × 0.5 (about 0.02 m, about 4x LOD0, so about 600k splats; record the budget), the cockpit
    faces' factor applied too. A separate manifest entry (`hero`), so LOD0-LOD3 are unchanged.
  - `ShipSpec.splat_hero` true for the player's Starfury only: its chain is hero, LOD0-LOD3, by screen size (hero
    ≥ 400 px). The instructor and allies never use it.
  - The visible splats count against T20's budget; check AC19's fight plus the hero stays inside it. Record the import
    time of the hero PLY.
- Done when: AC33 passes; P9's cockpit frame is sharper than before (AC35 judges it).

### M3-T25 Lens flare and motion blur, after sign-off

Added 2026-10-28 for Q23; last of the visual pass; after T21. **Gate**: the first step is a short report to the maintainer;
no code until the maintainer picks.

- Goal: a lens flare from the star, and motion blur on fast turns as an option.
- Agent: **Sonnet**. Compositor effects; the choice is the maintainer's.
- Files: `addons/<flare>/` (if vendored, untouched), or `src/rendering/{lens_flare,motion_blur}_effect.gd` and shaders,
  `src/environment/space_environment.tscn` (Compositor), `src/autoload/settings_schema.gd`, `docs/third-party.md`,
  `tests/integration/test_post_effects.gd`.
- Notes:
  - Options found 2026-10-28 (check again before the report): **lens flare**: ARez2's "Compositor Lens Effects / Lens flare"
    (MIT, Godot 4.4+, a `CompositorEffect` with lens flares and god rays; https://github.com/ARez2/compositor-effect-lens-effects),
    or in-house. **Motion blur**: no maintained Godot 4.7 compositor add-on found (Bauxitedev's port was last updated in
    2022 and is a camera scene, not a compositor effect), so the planner's call is an in-house `CompositorEffect` over the
    motion vectors Forward+ already writes.
  - Splats write no depth or motion vectors; the hull depth proxies do. Check the flare's occlusion test and the blur both
    read them, so the flare hides behind hulls and hulls blur as solid shapes.
  - Order after GDGS's effect (`PRE_TRANSPARENT`); the HUD and console are canvas layers and are never blurred.
  - `settings.lens_flare` (default on), `settings.motion_blur` (default off) and `motion_blur_strength`.
- Done when: the maintainer has picked; AC34 passes; AC35's flare and blur lines are in the play-test checklist.

### M3-T26 Starfury after the reference model, wireframe damage display

Added 2026-10-30 for the maintainer's request Q24, done before the other open tasks.

- Goal: the in-game Starfury reads like the maintainer's reference model, and the HUD's Starfury damage display is a
  low-poly wireframe of it.
- Agent: **Opus** (done by the controller). A parametric reshape checked against orthographic renders of the reference,
  plus a pure HUD data change.
- Files: `tools/procgen/assets/starfury_aurora.py` (generator v3: pod, claw, strut, rear fuselage stations, pod
  centre), `tools/procgen/parts/propulsion.py` (`RingPodSpec` knuckle and `collision_radius`),
  `tools/procgen/tests/test_starfury_aurora.py` (LOD0 contract re-pinned, claw box and pod capsule checks),
  `src/hud/silhouette.gd` (`wireframe`), `src/hud/hud.gd`, `tests/unit/test_silhouette.gd`,
  `docs/design-references.md`, `docs/assets-starfury.md`.
- Notes:
  - Reference read-off (the model scaled to our claw span): pods 5.6 m long at (±5.5, ±2.5) with a knuckle, sensor
    dome and dorsal stub where the strut joins; struts 3.8 to 2.25 m in chord, about 21° from horizontal; claws are
    long flat blades almost level with the pod's outboard side, splaying 13-22°; the fuselage behind the cockpit is a
    2.2 m shield with a pointed keel. The cockpit segment (window, eye, tested view), gun mount and masses are
    unchanged, so the cockpit-view tests hold as they were.
  - LOD0 is 246 602 splats (AC3 budget 100k-250k), LOD1 24.9 % of it (AC6). Pod lever arms change (y 2.2 to 2.5, the
    nozzles' z); thrust and RCS torques read the hardpoints, so nothing else needs new constants.
  - Wireframe: a fixed low-poly model in the ship frame (fuselage rings, guns, and per arm hexagonal pod rings, the
    strut's edges and the claw blades), projected from behind and above (yaw -0.25 rad, pitch 0.5 rad) so the
    ship's right stays right and its top up, fitted undistorted into the silhouette rect. Each zone's lines take
    its damage colour, and a damaged zone draws heavier. The raider keeps its outline polygons.
- Second pass (2026-10-31, generator v4): the maintainer found v3 still far from the reference ("only minor
  simplifications allowed"), so the hull was rebuilt from the model's measured cross-sections:
  - New builders in `tools/procgen/parts/starfury.py` (`section_loft`, `fury_pod`, `fury_claw`, `fury_strut`,
    `fury_guns`, `fury_fittings`; tests in `tools/procgen/tests/test_starfury_parts.py`). The authored frame is the
    reference's. A hexagonal glazed beak; a body between two decks with chin guns and keel box, flank port blocks,
    teardrops and wedge fairings; arms of a deck and a brace merging into a slotted beam (the lower arms' brace is
    rooted lower, so upper and lower struts are two variants); lathed pods with dome and sensor bulb; bent pincer
    claws. Orthographic silhouette IoU against the reference: 0.95 top, 0.94 side, 0.87 front. 9.83 x 15.39 x 7.47 m.
  - The whole ship is centred on its splat centroid (the body-only y shift would have lifted the fuselage 0.68 m);
    the pods' centre line sits at y = +0.096 and the CoM is trimmed onto it. Hull spacing 0.047 m (243 728 splats,
    AC3), cockpit faces still 0.022 m. The eye moves into the beak (0, 0.7, -3.85 authored); the tested clear view
    holds. The guns now hang 1.4 m under the centre, so `AttackBrain` solves its lead from the mean muzzle position
    (`Perception.muzzle_offset`), as the HUD's lead marker already did.
  - The HUD wireframe follows the new hull (canopy rings, deck outline, pod rings with dome and bulb, pincers).
- Done when: the procgen and GUT suites pass, and the maintainer accepts the look in game (H).

### M3-T12 Integration, smoke runs, capture set, play-test guide

- Goal: M3 complete in one build, every (A) criterion green, the maintainer handed a checklist and screenshots.
- Agent: **Opus**. Cross-task glue.
- Files: `scripts/run_tests.sh` (providers line, new smoke runs: wing order, dogfight, instructor route), `scripts/capture_m3.sh`,
  `tests/integration/test_m3_run.gd`, `docs/playtest.md` (M3 section: keyboard, orders, instructor, new console commands,
  AC14-AC19, AC22, AC27 and AC35 checklist), this file (status, as-built notes), `docs/architecture.md` §16 (as built), `docs/roadmap.md`.
- Done when: every (A) criterion passes; the capture set is attached; the maintainer runs the (H) checklist.

## As-built notes

(Implementation agents record deviations from §16 and this file here, per task.)

**M3-T01 (keyboard layout B).**
- Bindings are exactly the T01 table, in `project.godot` and in `data/controls/m1_classic.cfg` (only its keyboard and mouse
  descriptors changed; its pad swap is as before). Event order per action is pad, keys, mouse: the specific key first, then
  the both-pods key (`main_left` = `[LT, Q, W]`, `main_right` = `[RT, E, W]`, `retro_left` = `[LB, A, S]`, `retro_right` =
  `[RB, D, S]`).
- Mouse 2 stays on `target_next` (tap = next, hold = nearest the nose), because the T01 note counts it among the ways to reach
  `target_prev` / `target_ahead`. Mouse 4 (`mouse:8`) is `autotrack`, Mouse 5 (`mouse:9`) is `weapon_next`; the descriptor grammar
  already accepted 8 and 9, and `GodotInputSource` polls any button, so no code changed. `InputAdapter` has only comments edited.
- `pitch_*` and `yaw_*` keep only their pad bindings. `target_prev` and `target_ahead` had no pad binding and now have no event
  at all (empty `events` in `project.godot`, `[]` in the profile text). They stay in `ControlProfile.KEYBOARD_ONLY`, so
  validation passes and a player can still `bind target_prev key:<name>`; a profile round trip keeps the empty lists. The wheel
  is `target_prev`, a B or Mouse 2 hold is `target_ahead`. `ControlProfile.describe_action` prints `(unbound)` for an action with
  an empty list (it used to print nothing after the colon), so `controls show target_prev` stays readable.
- B inherits the D-pad Up tap-or-hold with no adapter change (`TARGET_NEXT` is the tap-or-hold action;
  `test_godot_input_source` drives real B events through `GodotInputSource` and `InputAdapter`: tap gives `target_next` on the
  release, a hold gives one `target_ahead` and no `target_next`).
- Caps Lock: the headless test sends `InputEventKey` press and release for `KEY_CAPSLOCK` and checks `roll_left` follows them.
  That proves the input source reads it as a held key; it cannot prove how X11 or Wayland deliver the real key (some desktops or
  keyboard settings toggle it), so the real-keyboard check is the maintainer's (H) AC14. Fallback if it toggles: Ctrl for
  `roll_left` (a data change in the same two files).
- AC1 as tests: `test_input_map` pins the exact keys and mouse buttons per action (`KEYS_B`, `MOUSE_B`), and
  `test_no_flight_key_is_right_of_the_g_b_column` lists the allowed keyboard keys (the Q-T, A-G, Z-B block plus Shift, Caps Lock,
  Tab, Space) and the six keys outside it (Esc, Backspace, N, Print, F3, F4, each for one housekeeping action). The old
  "every action has a keyboard fallback" test became "every action has an event, except `target_prev` / `target_ahead`".
  Keys 1-4 are not in the allowed block yet; T07 adds them with the wing-order actions (and extends `KEYS_B`).
- Saved profiles in `user://controls/` keep their old keys; `controls use default` gets layout B. Tests that named old keys
  (`test_control_profile`, `test_control_profiles`, `test_debug_console`, `test_input_adapter` comments) were updated; the
  "also bound to" note test now uses B (K is free). The control-profile console smoke run in `scripts/run_tests.sh` expected
  `yaw_left ... key:J`; it now expects the layout B lines for `yaw_left` and `roll_left` (m1_classic) and `main_left` and
  `roll_left` (default).

**M3-T02 (factions as data, friendly fire).**
- `data/factions.json` holds `earth_alliance`, `raiders`, `neutral`, the one hostile pair and `"default": "neutral"`; with
  it, every M2 relation is unchanged (`test_faction_table::test_the_shipped_file_is_the_built_in_m2_rule` compares the file,
  `FactionTable.builtin()` and the M2 rule coded out in the test, over known and unknown ids).
- `FactionTable.from_dict(d) -> {ok, error, table}` (`table` is null on failure; `parse(text, source)` and `load_file(path)`
  prefix `source: ` to the error). Validation beyond the brief: ids match `^[a-z0-9_]{1,32}$`; `factions` is a non-empty
  array; `relations` and `default` are required (no silent defaults in a data file); a relation's `a`/`b` must be listed
  ids, must differ (the same id is always FRIENDLY), and a pair may appear once in either order (symmetric). First problem
  in file order wins. `Factions.load_table(path)` installs a valid file and leaves the active table untouched otherwise.
- `default` applies only to two different listed factions that `relations` does not list. An id the file does not list is
  NEUTRAL to everything but itself, whatever `default` says (M2 rule 2). So `earth_alliance` vs `neutral` is the file's
  default, which is `neutral` in the shipped file (M2: NEUTRAL).
- `Factions` keeps `relation`, `is_hostile`, `is_known`, `hud_color` and its constants. New: `table()`, `use_table(t)`,
  `load_table(path)`, `reset()`, `TABLE_PATH`. The active table is a GDScript `static var`, i.e. process-wide:
  `reset()` drops it (and with it every session `relation` change) and the next query reloads the file. Tests that swap or
  edit the table call `Factions.reset()` in `after_each`. A file that does not validate when first needed warns once and
  `FactionTable.builtin()` stays active.
- `FactionTable` and `Factions` reference each other (`Factions.Relation` is the one relation enum); GDScript compiles the
  cycle without trouble. `relation()` allocates nothing (nested dictionary lookups), so the resolver's per-bolt-per-ship
  query stays cheap.
- Console: `src/combat/faction_console.gd` (`FactionConsole`, not in the brief's file list) builds the `factions` provider and
  the `relation` command and holds the handler, so it is testable without a node. `HitResolver` registers both in `_ready`
  (owner = itself, dropped in `_exit_tree`). `relation <a> <b>` prints, `relation <a> <b> friendly|neutral|hostile` sets for
  the session, `relation reset` reloads the file; only listed factions, never the same one twice, never writes the JSON.
  Provider keys `ids` and `relations` (`"earth_alliance raiders hostile"` per listed pair, so it pastes back into
  `relation`) and `friendly_fire`, a read-only mirror: change it with `set`/`toggle settings.friendly_fire`.
- Friendly fire: `Damageable.can_be_hit_by(bolt_faction, friendly_fire := false)` returns true for any bolt when on, which
  also lifts the buoy rule "a bolt of its own faction passes through". The shooter's own hull is excluded by the resolver by
  instance id, as before, so a bolt with `shooter_id` 0 (console or test bolts) can hit anything when on. `HitResolver`
  reads `settings.friendly_fire` at the start of each `resolve` into its public `friendly_fire`. God mode is untouched.
  `settings.friendly_fire` (bool, default false) is a `SettingsSchema` entry.
- For T05: the fire-lane check is not built here. With the setting on, a friend in the lane is a hull the bolt can hit
  (`Factions.relation(...) != HOSTILE` for anything that is not the shooter); the check runs in both settings (D31).
- `scripts/run_tests.sh`: the main-scene providers line gains `factions` (T12 keeps it), plus two small smoke runs: `relation`
  print / set / reset with `data/factions.json` unchanged, and an unknown faction exiting 1 under `--console-strict`.

**M3-T03 (Starfury chunks and LOD1).**

- LOD1 spacing factor 2.0 for every spacing (hull 0.08 m, cockpit faces 0.044 m): 57 538 splats, 25.0 % of LOD0's
  230 230. RNG streams are `ctx.rng("splats", <part>, "lod1")` (an extra stream component). Option `lod1_factor`
  (default 2.0) added for tuning; LOD0 is byte-identical whatever its value (tested).
- LOD1 is balanced and centred on its own samples, so its centroid is the origin (GDGS centring is a no-op); its frame
  differs from LOD0's by 3.2 mm in z (and 1.1 mm in y for the cabin) at seed 42. Its AABB is LOD0's within 1.3 cm.
- Coverage (probe points, composite opacity): LOD1 mean 0.985 against LOD0's 0.995, 0.38 % of points under 0.5
  against 0.10 %; the hull sheet has no holes, small claw and ring details thin out. Recorded in
  `docs/assets-starfury.md`, tested in `test_starfury_aurora.py`.
- Chunk names are the brief's (`cabin`, `arm_ur`, `arm_lr`, `arm_ul`, `arm_ll`): `DamageZones` has index constants
  (`CABIN`, `UPPER_RIGHT`, ...) and no string names, so there was nothing to follow. The cockpit interior is in no
  chunk.
- The manifest gains `chunks` (names, as the raider's) and `chunk_lod` (1) beyond `lods[1]`; `test_splat_import.gd`
  reads `chunk_lod` (default 0) to know which LOD the chunks partition. `hardpoints.json` gains `chunks[]` as its last
  key. `generator_version` stays 2: it is in the LOD0 PLY header, which must not change.
- LOD0 is checked by recorded per-part counts, the exact PLY header and three splat records, not by a pinned SHA-256
  (a NumPy build could change bits without changing the design); the pre/post SHA-256 comparison is in the task report.
- Behaviour change ahead of T08: `DestructionDirector` bursts any `chunks[]` it finds, so the player now dies into the
  five Starfury chunks as mesh-only debris (no Starfury splat sets until T08) instead of 12 generic shards.
  `test_destruction.gd` was updated to expect that.

**M3-T04 (ram damage).**
- `RamResolver` is `Combat/RamResolver` in `main.tscn`, priority 210. It needs no wiring: it reads every active `Damageable` from
  the group each tick. `main.gd` is unchanged. Signal `ram_resolved(info)` mirrors `hit_resolved`; nothing plays a sound or a
  flash for a ram yet. Every `Ship` must run its `_physics_process` before 210, because the resolver reads
  `Ship.applied_force()` as this tick's (the main-scene test checks the player's and the pool's priorities).
- The node only reads the scene and sweeps. `RamTracker` (`src/combat/ram_tracker.gd`, pure, typed inner classes `Sample`,
  `Touch`, `ContactRam`) keeps everything between ticks: the previous tick's velocities and contacts, the contact windows and
  the one-ram-per-collision rules. `tests/unit/test_ram_tracker.gd` covers it without Jolt.
- Contacts come from the direct body state (`PhysicsServer3D.body_get_direct_state`: collider ids, points, normals). `Ship` sets
  `contact_monitor` and `max_contacts_reported = 8` in `_apply_newtonian_body`.
- One tick of contact is not enough. A Starfury nose into a raider gave a speculative contact one tick before the bounce, and
  Jolt spread the bounce over two steps. So a new contact opens a window of `CONTACT_WINDOW_TICKS` (3) ticks, counting the tick
  it is first reported, and the ram lands once with the largest Δv seen. A lethal Δv lands at once; otherwise the damage
  arrives up to 2 ticks (33 ms) after the first contact report. Windows are per pair (hull, other), so a second body hitting
  during a window gets its own ram and shooter. Two bodies hitting the same hull within 3 ticks each see its total Δv.
- Thrust is subtracted exactly, not as a bound. `Ship.applied_force()` is the World-frame sum of the forces the ship applied on
  its last tick (nozzles, RCS, the assist's speed cap, the environment). `RamMath.contact_dv(v_now, v_before, own_dv)` takes
  what those forces added over the window.
- Swept hits use the momentum split for both sides, through the normal curve (controller ruling of 2026-10-22, also written
  into the T04 notes above). There is no "destroys both" rule any more, and with it no cliff at the tunnelling threshold. At
  600 m/s closing each Starfury's split Δv is 300 m/s, so both die. Two raiders at 29 m/s get 14.5 m/s each (under their
  lethal 15) and survive with 6 of 60 points.
- The swept test is shape by shape (`src/combat/convex_sweep.gd`, `ConvexSweep`: GJK on the Minkowski difference of a hit volume
  swept along the tick's relative move and another volume, support functions for boxes and capsules, exact at any speed).
  Two ships ram when a point of either comes at least `RamMath.RAM_DEPTH_M` (0.3 m) deep inside a volume of the other, tested
  both ways by shrinking one side's volume by 0.3 m. A prop rams at any touch (no Jolt body would notice it otherwise).
  Filters in order: the bodies' bounding spheres, a volume's swept box against the other body's box and each of its volumes'
  boxes, the whole volumes, then the shrunk ones; the first pair of volumes that rams decides. `Damageable` caches its volumes
  (`ram_volumes`, `ram_cores`, `ram_bounds`) when it builds its shapes. The touch point is where the two volumes' bounding
  spheres met (best effort, for the damage zones).
- Why not the review's chain of inscribed spheres: a sphere swept against a box grown by its radius on each axis is square
  at the box's edges, so a 1.235 m fuselage sphere would ram a box edge it passes 0.5 m clear of; and one chain down the middle
  of a flat strut misses deep overlaps at its wide edges. The exact sweep has neither problem and passed seeded cross-checks
  against a separating-axis test (box pairs) and exact point distances (capsules) at 241 instants of each move.
- `core_radius` (largest sphere inside any one shape: Starfury 1.235 m, raider 0.78 m, buoy 0.4 m) only sets the tunnelling
  threshold. Round 1's origin-centred core is gone.
- Band probe (AC4 setup, 600 m/s, 15 seeded offsets per band of the origin's distance from the other hull, a tracker reset
  between trials): round 1 had both destroyed at 15/15, 9/15 and 6/15 for 0-0.84 m, 0.84-1.235 m and beyond; now 15/15 in
  every band. The AC4 test draws its 50 offsets from a ±15 × ±8 m square with a geometry oracle (grid points inside one
  hull's volumes tested with `HitShape.contains` against the other's shrunk by 0.3 m, every 0.25 m of the pass, both ways);
  it accepted 50 and rejected 22. Each trial resets the tracker, since the last trial's swept ram a few ticks earlier would
  otherwise still be inside its grace ticks.
- Cost (`ram.resolve_us`, headless, another Godot run in parallel): two pairs of Starfuries passing at 600 m/s closing peak at
  0.17-1.2 ms on their worst tick; over the band probe the median tick is 0.1 ms, p95 0.5 ms, the worst 1.5 ms. Round 1's
  origin sweep: p95 0.44 ms, worst 0.93 ms.
- Tunnelling uses the relative speed `|v_a - v_b|`, not the radial closing speed, because a glancing pass tunnels too. With
  `TUNNEL_FRACTION` 0.5 the threshold is 37 m/s for two Starfuries and 23.4 m/s for any pair with a raider. Below it Jolt's
  contacts decide.
- At tunnelling speed the sweep runs even while Jolt reports a contact for the pair, because that is when Jolt cannot be
  trusted (at 10 m a tick two hulls can already overlap deeply when Jolt first sees them, and its push-out need not stop them). `RamTracker` keeps it to one
  ram per pair per collision: a swept ram cancels the pair's open contact windows, and for `SWEPT_GRACE_TICKS`
  (`CONTACT_WINDOW_TICKS` + 1) ticks after it the pair opens no contact window and takes no other swept ram. The sweep
  predicts the hit for the coming step, and Jolt reports the same collision as a contact a tick or two later. A pair Jolt holds
  in contact below tunnelling speed stays "met" (`keep_touching`), so it is not rammed again when it separates. A contact ram
  does not block a later swept ram: if Jolt's bounce fails and the cores cross, that is a second, real hit.
- Props never ram props. Ships fly through buoys: the buoy has no body and nothing writes the ship's velocity (§15.16), so only
  the damage happens.
- The ram values live on `Damageable` (`core_radius`, `ram_volumes`, `ram_cores`, `ram_bounds`, `ram_safe_dv_mps`,
  `ram_lethal_dv_mps`, `ram_mass_kg`, `ram_mass()`), so the resolver treats ships and buoys alike. `ShipAssembly._wire` copies the limits from the
  `ShipSpec` (a file the brief did not list). `NavBuoy` has `MASS_KG` 2000 and `RAM_LETHAL_DV_MPS` 15.
- Measured in Jolt: a 30 m/s head-on between Starfuries changes each velocity by 14.9 m/s, and each loses 58 % of its hull. A
  4 m/s head-on changes each by 2 m/s and does nothing. A 40 m/s ram destroys a buoy and leaves the Starfury untouched. After a
  swept ram between two raiders at 29 m/s, Jolt's own bounce changed each by 14.6 m/s, close to the split's 14.5.
- `ram.last` is labelled before any damage lands, so a raider sent back to the pool by the first side still has its name.
- `HitInfo.cause` (`CAUSE_BOLT` default, `CAUSE_RAM`, `CAUSE_CONSOLE`) is an 8th optional constructor argument. The console's
  `damage` and `Damageable.kill()` are `console`. `HitResolver.name_of(id)` is now a public static; `RamResolver` uses it for
  `ram.last`.
- `settings.ram_damage` off resets the tracker, so turning it back on never rams a contact that began while it was off. Ships
  still bounce.
- For T05/T06: the main-scene test disables the raider's `AiPilotDriver` so avoidance cannot dodge the ram. Ram kills reach
  `waves.kills` through `DestructionDirector.raider_destroyed`, unchanged.
- `scripts/run_tests.sh`: the main-scene providers line gains `ram`. `docs/architecture.md` D32 now says the swept test uses the
  momentum split for both sides and what it guarantees at tunnelling speed (an overlap of 0.3 m or more always rams; below it,
  and for a shallower clip between two ships, Jolt's contacts decide).

**M3-T05 (contacts, avoidance, fire lane).**
- `Contact` has the brief's fields. `id` is the `Targetable`'s instance id (the same as `TargetInfo.id` and a
  `TargetingController` selection, so `target_id` and `p.target.id` compare directly); a hull without a `Targetable` (test
  drones) uses its body's id. `target_id` is -1 when nothing is selected or the body has no targeting computer.
  `relation` is to the perceiving ship. The scan makes one stamped copy per faction and shares it between every ship of that
  faction: brains read contacts, never write them.
- `ContactScan.shared(tree)` is a static cache keyed by `Engine.get_physics_frames()` (the first driver of a tick builds it).
  It is also rebuilt within a frame when a body it saw has been freed (GUT tears worlds down mid-frame); `invalidate()`
  drops it; `from_tree(tree)` is an uncached scan. A body counts while its `Targetable` or its `Damageable` is active (parked
  pool ships never do). A body added mid-frame appears from the next frame, and a test that calls `driver.step()` several times
  in one physics frame sees the first call's contacts (targets are still read fresh, as in M2).
- `Perception` gains `contacts`, `incoming_fire` (an **int**, the count of hostile bolts passing within 15 m in 2 s; not
  a list, so T06's evade finds the shooter among the contacts), `last_hit_s` (from `Damageable.hit_taken`, so T04's ram hits
  count too; -INF until the first hit, reset when a brain is set) and, beyond the brief, `friendly_fire` (the setting this
  tick: `FireLane` needs it and brains must not read `Settings`).
- **Desired-velocity protocol** (how the driver filters "every brain's output"): `PilotBrain.desired_velocity` and
  `has_desired_velocity`, set by the new helper `seek_velocity(flight, p, v_des)` (seek + record), which `PatrolBrain` and
  `AttackBrain` now use. The driver clears the flag before each `think`; a brain that delegates clears its inner brain's flag
  and copies both fields back (`AggroBrain`). **T06's `AiPilot` must forward its behaviour's desired velocity the same way.**
  A brain that coasts leaves the flag false and the current velocity is its wish; a held brake (all stop) is never filtered.
- `AiPilotDriver`: after `think`, `AvoidanceMath.filter` on the wish; when it changes it, the thrust (mains, retros, strafe) is
  sought again toward the filtered velocity, harder when `urgent` (`PilotSteering.seek` gained an optional `horizon_s`;
  the driver uses 0.25 s instead of 1 s). The turn command and the combat command stay the brain's. With nothing
  threatening, the brain's command reaches the ship untouched. The tie-break seed is `hash(display_name)` (deterministic per
  ship, no spawner change). Public `avoiding` / `avoiding_urgent` (this tick) for tests and T06's `ai` provider; no console
  provider here.
- `AvoidanceMath` predicts with the **wish**, not the current velocity: the dodge then shrinks as the ship's position moves
  off the line, not as its velocity swings, which keeps the loop from chattering against the seek. Horizon = time to stop the
  larger of the wished and current relative speed on the retros, at least 4 s; a threat is a closest approach under the
  radii + 15 m with `0 < t* < horizon`. The dodge is perpendicular to the relative velocity, sized exactly (a quadratic) so
  the filtered straight line clears radii + 15 + 1 m, capped at the relative speed; several threats add. Relative speeds under
  3 m/s (formation) are not predicted: inside the margin they push apart at `(reach - d) / 2 s` plus any closing speed.
  Ties (offset under 0.1 m): "right of the relative velocity, world up", turned by a seeded angle within ±40°; the base is odd
  in the relative velocity, so two ships meeting dead-on dodge apart for any pair of seeds (unit-tested over 625 pairs).
  `urgent` = closest approach sooner than a 90° turn + 1 s, or inside the margin and closing faster than 3 m/s.
- `FireLane.clear(own_pos, aim_dir, range_m, contacts, target_id := 0, friendly_fire := false)`: two arguments beyond the
  brief (the target must be excluded, and the rule depends on the setting). Closed by a friendly, or with friendly fire on by
  any **non-hostile** ship (the brief's "any non-target ship", read with T02's note: a hostile in the way is fair game),
  within its radius + 5 m of the line, `0 < along < range`. Props never close it: buoys are hit by any bolt whatever the
  setting. `AttackBrain` asks with the nose direction (where the bolts go) and the range to the target.
- Jolt numbers (60 Hz, `test_ai_avoidance`, all runs in one world 6 km apart): head-on 20/20 closest 32.7-35.8 m against
  radii 17.7-20.2 m; buoy at 100 m/s 25.4-27.2 m against 10.3-11.6 m; every encounter engages once with at most one strafe
  reversal. The same at the 0.1 s step (`time_scale` 6). With the filter disabled all 20 head-on runs collide (3-8 m) and every
  buoy run goes through the buoy.
- M2 AC9 after the change (`test_ai_attack`, the attack raider now avoids the drone it attacks): first fire 12.9 s (M2: 13.5),
  first hit 15.5 s (same), closest approach 394 m (391), 65 hits; same-seed runs still match to 0.0 m. Patrol, idle and
  driver tests unchanged.
- Cost (headless, 13 AI ships within 2 km, M2 attack brains, 39 bolts in flight; a temporary probe, not committed): the
  drivers take about 1.0 ms per tick, of which about 0.64 ms is the M2 path (perception, retarget, brain) and about 0.32 ms
  this task (scan about 90 us per tick, `contacts_for` about 110 us and `incoming_fire` about 65 us and the filter about 55 us for
  all 13). Hostility of bolts is resolved once per faction per scan. AC13's 1.5 ms leaves T06 roughly 0.5 ms; the
  incoming-fire count grows with the bolts in flight.
- For T07: two Starfuries have a reach of about 2 x 10.1 + 15 = 35 m, so slots closer than that are pushed apart all the
  time; AC9's "never closer than 15 m" fits slot spacings of 40 m or more.

**M3-T06 (AiPilot core).**
- **The interface later tasks build on.**
  - `AiBehaviour` (RefCounted): `id` (also its `AiProfile.weights` key and its `AiPilot.TIE_ORDER` place), `score(ctx) -> float`
    (0..1, every tick before any `think`, for every behaviour the profile weighs above 0; it may cache what `think` needs,
    e.g. the chosen target), `enter()` (control was handed over), `think(ctx, dt) -> PilotCommand` (the behaviour in control
    only), `target_id()` (the `Contact.id` the ship's targeting computer should select, `PilotBrain.TARGET_NONE` by default),
    `describe()` (at least `state`), `reset()`, and
    `seek_velocity(flight, p, v_des)`, which records `desired_velocity` / `has_desired_velocity` as `PilotBrain` does (T05's
    protocol; `AiPilot` forwards them to the driver). A score of 0 means "cannot run now".
  - `AiContext` (one per pilot, kept across ticks): `perception` and `profile`; wing fields set from outside the brain and kept
    until changed: `order` (`Order.ENGAGE_AT_WILL` default, `ATTACK_MY_TARGET`, `FORM_ON_ME`, `COVER_ME`; words `engage`,
    `attack`, `form`, `cover` in `ORDER_WORDS`), `leader_id` (the leader's `Targetable` id), `leader_target_id`,
    `engage_radius_m` (2 000); derived each tick by `refresh(p)`: `leader` (its `Contact`, null when not in sight), `hostiles`
    (hostile ships) with `hostile_offsets` / `hostile_ranges` by the same index (from this ship, World frame), `friendly_ids`
    (a `PackedInt64Array`: this ship and every friendly contact). `may_attack(contact)` is the one order gate:
    FORM_ON_ME nothing, ATTACK_MY_TARGET only `leader_target_id`, COVER_ME hostiles within `engage_radius_m` of the leader or
    whose `target_id` is the leader (a covering ship that cannot see its leader engages at will), ENGAGE_AT_WILL any hostile
    ship. T07 sets `pilot.context.order` / `leader_id` / `leader_target_id` and adds its slot fields here; T09 the route, T10
    the guard post.
  - `AiPilot(profile, seed, behaviours := [])`: empty means the standard four (retreat, evade, attack, idle) built from the
    profile with seeds derived from `seed`. `add_behaviour(b)` slots a behaviour in by `TIE_ORDER` (`retreat, evade, attack,
    guard, formation, follow_path, idle`; unknown ids after these) and reads its weight then. `behaviour(id)`, `score_of(id)`,
    `raw_score_of(id)`, `current`, `dwell_s`, `switches`, `context`.
  - `PilotBrain` gained `wanted_target_id`: `TARGET_NEAREST_HOSTILE` (0, the default, every M2 brain) keeps the M2 rule (the
    driver selects the nearest hostile every 0.5 s); `TARGET_NONE` (-1) means no selection (the driver clears it and stays
    out); any other value is a `Contact.id` the driver selects after `think`. `AiPilot` starts at `TARGET_NONE` and sets its
    attack's target while attacking, `TARGET_NONE` otherwise, so an evading or retreating ship shows no target
    (`Contact.target_id` -1). `reads_target()`: `AiPilot` says no, and the driver skips `Perception.target`. `Perception`
    gained `self_id` (the ship's own `Targetable` id, for "attacking me"). `TargetingController.select_id(id)` is new; it
    selects from the last refresh's candidates and gathers again only when the id is not among them.
- **Selection as built.** Weighted score = clamped score x the profile's weight (a weight the profile does not name is 1).
  The best weighted score wins, ties to the earlier `TIE_ORDER` entry. A challenger takes over when it beats the current
  behaviour's weighted score by more than `stickiness`, or, within `min_dwell_s` of the last switch, by more than
  `emergency_margin` (both margins are measured from the current's weighted score; strict `>`). Beyond the brief: a current
  behaviour whose weighted score is 0 hands over at once (its target died; dwell protects a behaviour that has something to
  do, not one that has nothing; a controller ruling keeps this). A behaviour weighted 0 is not scored. When nothing scores
  above 0 the pilot falls back to idle and never hands control to a behaviour that scored 0 (fix round 1);
  `AiProfile.validate()` requires an idle weight above 0. Weights are read when a behaviour is added, scores live in packed
  arrays (AC13).
- **Behaviours.** Scores are placed so a tail threat and a retreat outrank an attack, and an attack under fire keeps going
  (tuning in (H)/T10):
  - attack 0.3 + 0.5 x the best target's value (0.3..0.8). Value = 0.4 x nearness (1 - range / 5 km) + 0.2 x closing speed /
    200 m/s + 0.3 when its `target_id` is this ship or a friend + 0.1 x missing hull, + 0.1 for the current target (no
    flicker). A new target restarts the `AttackBrain` run (`restart()`: APPROACH, timers cleared, seeded break sides go on).
    `AttackBrain.think` now calls `engage(p, target_id, position, velocity, dt)` (the attack passes its contact's values) and
    applies `aim_offset_rad` to the lead (zero for M2 brains, skipped entirely). Aim wander: per axis
    `aim_error x (0.6 sin(2 pi f1 t + phi1) + 0.4 sin(2 pi f2 t + phi2))`, f1 0.05-0.15 Hz, f2 0.15-0.35 Hz, seeded, in the
    behaviour's own time (so two runs at different sim times match).
  - evade: a hostile ship within 1.2 km behind (our nose points away from it) with its nose within 15 degrees of us scores
    0.75 at 1.2 km to 1.0 point blank; `incoming_fire` 0.6; a hit in the last 2 s 0.5. The threat is the tail hostile, else the
    nearest hostile whose nose is within 15 degrees of us, else the one whose nose points closest at us. Jinks seek the velocity the ship had when the evasion began plus 100 m/s across
    the line of fire (more than a 2-4 s jink reaches, so the thrust never stops), the nose turned toward the velocity change;
    the first side is a seeded angle round the line of fire, each reversal is the opposite side turned by up to +-45 degrees.
  - retreat: hull under `retreat_below` with a hostile ship in sight scores 0.85 at the threshold to 1.0 at zero hull; it flies
    `cruise_mps + 50` (World frame, not relative to the hostiles: a faster chaser still closes, and two ships never escalate
    each other's speed) away from the hostiles, each pulling with 1 / distance, nose along. Never fires.
  - idle 0.05: brake (`idle_hold`) or coast. The brake faces the ship's selected target (M1 §5.5); an idle `AiPilot` has none
    (`TARGET_NONE`), so it holds its attitude.
- **Profiles** (`assets/ai/`; selection numbers 0.15 / 1.0 s / 0.4 in all three): `ally_starfury` weights attack 1, evade 0.9,
  retreat 1, idle 1; `retreat_below` 0.25; cruise 100 m/s; aim error 0.1 degrees; `starfury_tactics`; holds when idle.
  `raider` evade 0.8, the rest 1; `retreat_below` 0 (fights to the death; T10 may give some groups 0.25); cruise 80; aim 0.2;
  the M2 `raider_tactics`; coasts when idle. `instructor` attack, evade and retreat weights 0, `retreat_below` 0, `fires`
  false (the pilot clears the trigger whatever the behaviour), cruise 60, holds. `AiProfile.validate()` checks ranges;
  `AiProfile.load_named(name)` and `PATHS` list the three.
- **`starfury_tactics.tres`**: closing 150 / 80 m/s, near range 2 000 m, fire range 1 800 m (bolt reach 4 000 m), cone 2.5
  degrees capped by a 4 m miss, break under 500 m (at 300 m an attacking Starfury, with its 15 m/s^2 retros, passed 42 m
  from its target; at 500 m 176 m), break 150 m/s for 2.5 s, extend at least 3 s and beyond 1 600 m. Aim 0.25 degrees landed
  1 hit in 30 s on an idle raider at 500-800 m, 0.1 degrees 5, 0 degrees 7: raiders are small.
- **BrainFactory** `{"type": "ai", "profile": ..., "orders": ...}`: `profile` is required (no silent default in a data file;
  `test_every_behaviour_name_builds` now passes one), `orders` defaults to `engage`; errors name `behaviour.profile` /
  `behaviour.orders`. `spawn raider ai [distance] [yaw] [pitch]` builds one on the raider profile (`ShipPool`).
- **Console.** Provider `ai` (`ships`: `NAME behaviour (state)` per AI ship in play; `by_behaviour`: counts; `think_us`) and
  `ai <name>` (case-insensitive; prints `NAME: behaviour (state)`, the behaviour's other fields, then `scores: retreat 0.00,
  evade 0.00, attack 0.52 *, idle 0.05` with `*` on the one in control; M2 brains print their `describe()`). The code is
  `src/ai/ai_console.gd` (`AiConsole`, RefCounted, like T02's `FactionConsole`; not in the brief's file list); every
  `AiPilotDriver` entering the tree registers it with itself as owner (`AiConsole.register`), handed to another live driver
  when the owner leaves, gone with the last; it reads `AiPilotDriver.flying()`. `think_us` sums the wall-clock time of every driver's `step` in the last complete physics tick
  (profiling only). `scripts/run_tests.sh`: the main-scene providers line gains `ai`; two smoke runs (`spawn raider ai` + the
  provider and command, and `ai NOBODY` exiting 1 under `--console-strict`).
- **Time steps in the Jolt tests.** `Engine.time_scale` scales the physics step: at `SPEED_UP` 6 every 60 Hz tick is 0.1 s of
  sim time. The M2 tests (`test_ai_attack`, `test_ai_patrol`) count `RUN_S x 60` ticks, so their "30 s" are 180 s of sim time
  at 0.1 s steps. `test_ai_evade` and `test_ai_retreat` count `RUN_S x 60 / SPEED_UP` ticks (their `RUN_S` is sim time), and
  fly both halves of their comparison at once in one world, 10 km apart at mirrored positions; both use the
  `tests/fixtures/physics_ticker.gd` fixture. `test_ai_evade` runs at `SPEED_UP` 2 (1/30 s steps, fix round 1; 40 s of wall
  time), `test_ai_retreat` at 6.
- **Evade (AC9)**: an M2 attack raider (seed 4242) from 2 km behind a Starfury that cannot fight back (attack weight 0):
  80 s at 1/30 s steps, 25 hits while it holds position against 1 while it evades. Before fix round 1 (holding ships still
  faced their selected target): 37 against 2 over 120 s at 0.1 s steps, and 23 against 1 at 60 Hz over 90 s (a one-off run).
  Evasions are short now (the threat stops pointing at us within a jink), so the Jolt run sees no reversal; the reversal is
  unit-tested.
- **Retreat (AC9)**: an `ally_starfury` pilot at 20 % hull with an idle raider 800 m ahead retreats for the whole 30 s and the
  range reaches 4 612 m at 149 m/s straight away; the same pilot at full hull attacks (closest 176 m, 5 hits).
- **M2 unchanged**: `test_ai_attack` after the `AttackBrain` refactor: first fire 12.9 s, first hit 15.5 s, closest 394 m,
  65 hits, same-seed runs 0.0 m apart (as T05 recorded).
- **AC13, AI half: met as rebaselined (Q10).** The whole driver path, M2 brains included, is over the original 1.5 ms
  on the development desktop
  (`test_ai_think_time`; 13 AI ships, four Starfuries on `ally_starfury` and nine raiders on `raider`, one fight, 60 Hz).
  Measured in fix round 1 with no other Godot running (one desktop program used about half a core throughout), paired: the
  same ships fly 12 alternating 60-tick blocks on `AiPilot` and on M2 `AttackBrain`s in one process, after a 4 s warm-up.
  - Quiet medians over three runs of the final test: AiPilot 1 847 / 2 367 / 2 213 us, M2 brains 1 708 / 2 078 / 2 001 us;
    paired difference (as measured then: the median over the six block pairs of AiPilot's block median minus the next M2
    block's) +250 / +177 /
    +117 us (the difference of the two medians: +139 / +289 / +212 us; +362 us inside a full `run_tests.sh`). The frame's
    speed swings about 2x over seconds whatever flies the ships: in the fast stretches both brains measure about 0.9-1.1 ms
    (AiPilot 1 117 / 1 131 us, M2 984 / 885 us in one run), in the slow ones about 2.0-2.5 ms. Hence short, many blocks and
    the per-pair statistic. Before the trims, the committed build's two quiet runs: AiPilot 2 493 / 2 564 us, M2 2 204 /
    2 270 us; the alternating harness on it: AiPilot 2 081 us, M2 2 008 us.
  - Cost per tick for the 13, by component (instrumented runs after the trims, two runs, AiPilot / M2 brains): perception
    0.87-0.98 / 1.03-1.34 ms (of which: the scan 0.27-0.29 / 0.27-0.34, `contacts_for` 0.17-0.20 / 0.15-0.19, `incoming_fire`
    with 41 bolts in flight 0.22-0.25 / 0.19-0.25, `Perception.new` 0.06-0.07, the other perception fields 0.15-0.17, the
    target info 0.02 / 0.25-0.34); brain 1.04-1.18 / 0.40-0.53 ms (AiPilot: context refresh 0.18-0.19, scoring and selection
    0.32-0.37, the attack's think about the M2 brain's cost); avoidance filter 0.17-0.19 / 0.15-0.20 ms; retarget 0.01-0.02 /
    0.14-0.21 ms; applying the commands 0.06-0.07 ms.
  - The test asserts the paired difference only: within 0.5 ms (T05's share for `AiPilot`), printing both medians and every
    block's. No absolute assertion, since the quiet median does not meet 1.5 ms;
    the replay test of round 0 was dropped. The maintainer rebaselined AC13 to this paired share (Q10, 2026-10-24).
  - After review the controller made the statistic bracketed: AiPilot flies one block more (13 blocks), every M2 block
    sits between two AiPilot blocks, and the statistic is the median over the six M2 blocks of the mean of the two AiPilot
    block medians either side minus the M2 block median, so a steady drift of the frame cost cannot hide AiPilot's cost.
  - Trimmed: `Perception.target` skipped for `AiPilot` (`reads_target()`); no target re-pick for a brain that chooses
    (`TARGET_NONE`, retarget 76 -> 14 us); `TargetingController.select_id` without a gather when the id is a candidate; a
    behaviour weighted 0 not scored; selection on packed arrays; the attack's engage-at-will fast path; shared per-hostile
    offsets and ranges in `AiContext`; `friendly_ids` packed; no `TargetInfo` per tick in the attack. In T05/M2 code, with
    identical results: `ContactScan` keeps each body's data in packed arrays and builds each faction's `Contact`s from them
    once (no base contacts and no `with_relation` copies; `Contact.with_relation` removed, it had no other caller), copies a
    faction list minus the ship itself when every body is within sensor range of every other, finds each body's
    `Damageable` from the group once instead of `Damageable.of` per body, and rejects in `incoming_fire` the bolts too far
    to close within the horizon before the closest-approach maths; `Perception` shares default `ShipCapability` /
    `UniversePos` objects instead of allocating two per perception; the driver uses `world.origin` (a rebase assigns a new
    one) instead of `world.to_universe(Vector3.ZERO)`.
  - Left, for a rebaseline or a later trim: the scan and `incoming_fire` grow with the bodies and bolts in play; the attack's
    `AttackBrain` returns dictionaries from `InterceptMath.solve` and `PilotSteering.seek` every tick; the M2 path's own cost
    (about 1.7-2.2 ms here with M2 brains) is already over the budget on this desktop.

**M3-T07 (wings, formation and orders).**
- **The API later tasks build on.**
  - `Formation` (pure): `Shape` (`FINGER_FOUR` default, `WEDGE`, `LINE_ABREAST`), `NAMES`, `shape_from_name`, `spacing_m`
    (40), `offset(slot)` in the leader's body frame (x right, y up, +z behind), `slot_point(position, forward, up, offset)`.
    Slot 0 is the leader. In units of the spacing: finger-four #2 (-1, 0, 1), #3 (1, 0, 1), #4 (2, 0, 2), further slots
    carry the echelon on to the right; wedge is a V (#4 left of #2); line abreast is the finger-four with z = 0, so every
    pilot keeps its side when the shape changes. Closest two slots: 56.6 m (finger-four, wedge), 40 m (line abreast).
  - `Wing` (pure; members are `Combatant` handles it never reads): `name`, `leader`, `formation`, `order` (COVER ME),
    `engage_radius_m` (2 000), `size` (3); `add_member(c, slot := -1) -> slot or -1`, `remove_member`, `slot_of`,
    `member_at`, `members()` (slot order), `empty_slots()`, `is_full()`, `callsign(slot)` (`ALPHA 2` for slot 1, for T08's
    replacements), `slot_offset`, `effective_order(leader_alive)`, `speaker()`, `ack_for(order, target_name)`,
    `refusal_no_hostile()`.
  - `WingDirector` (`Combat/WingDirector`, priority 290): `setup(world)`, `create_wing(name, leader)`, `player_wing()`,
    `add_member(wing, combatant, slot := -1)` (the ship must be in play and fly an `AiPilot`; the pilot gets a
    `BehaviourFormation` if it has none, and is briefed at once), `remove_member`, `give_order(order, wing := player's)
    -> {ok, line}`, `set_formation`, `ack_text()` (the HUD line for 3 s of sim time), `last_ack`, signal
    `acknowledged(line)`, `roster()` (rows `callsign`, `slot`, `hull`, `behaviour`, `state`: the data for T11's roster),
    `leader_alive`, `leader_hostile_target`, `refresh(wing)` (every tick). A member that is down (`Damageable.is_active`
    false: destroyed or parked) or no longer flies an `AiPilot` leaves its slot on the next refresh, so a downed wingman
    is an empty slot: T08's replenish fills `empty_slots()`, T11 can show an empty slot as DOWN under `callsign(slot)`.
  - `AiContext` gains `has_slot`, `slot_offset`, `leader_link_position` (a `UniversePos`, null with no live leader) and
    `leader_link_velocity`, all set by the director every tick, and `has_attackable()`, `may_retreat()` and `clear_wing()`
    (back to a ship without a wing; `remove_member` uses it).
  - The desired-velocity protocol (T05) gains `desired_all_axes` on `PilotBrain` and `AiBehaviour`, set by
    `seek_velocity(flight, p, v_des, all_axes := false)` and forwarded by `AiPilot`, `AggroBrain` and `BehaviourAttack` like
    the other two fields; `PilotSteering.seek` has the matching `all_axes` flag (the mains or retros take the part of the
    error along the nose whatever the angle, for a ship whose nose is held elsewhere). The driver's avoidance re-seek uses
    it, so a formation member that dodges keeps braking and accelerating along its nose.
  - `Main` creates wing ALPHA for the player in every scenario (empty until T08 or T10 add members; T10 configures it from
    the scenario's `wings`) and passes the key edges on (`_give_wing_orders`).
- **Beyond the brief's files.** `src/ai/contact.gd` and `contact_scan.gd`: `Contact.up` (the body's +Y), so the slot point
  and the roll use the leader's attitude as of this tick (one more packed array in the scan). `src/ai/behaviour_retreat.gd`:
  no retreat under FORM ON ME ("formation only, evade still allowed"; `AiContext.may_retreat`). `data/controls/m1_classic.cfg`:
  the four wing actions (a built-in profile must bind every action). `tests/unit/test_input_adapter.gd` and
  `test_input_map.gd` (keys 1-4 in `KEYS_B` and the left block, the four actions keyboard-only). Fix round 1:
  `src/ai/{pilot_brain,ai_behaviour,ai_pilot,aggro_brain,behaviour_attack,ai_pilot_driver}.gd` (`desired_all_axes`),
  `src/input/{control_profile,control_profile_store}.gd` and `src/autoload/control_profiles.gd` (saved profiles gain new
  actions), `docs/architecture.md` §15.12, `tests/integration/{test_ai_driver,test_ai_think_time,test_control_profiles}.gd`,
  `tests/unit/test_control_profile_store.gd`.
- **Formation behaviour as built.** The brief's `p_L + B_L * offset + v_L * 0.5 s` read literally parks the member 0.5 s
  ahead of its slot (50 m at 100 m/s), so the error looks ahead for both ships: `e = (S - p) + 0.5 s * (v_L - v)`, a damping
  term with no offset (with the seek's 1 s horizon a second-order loop, damping ratio about 0.95). `v_des = v_L +
  clamp(0.4 * e)`, closure 60 m/s within 1.5 km of the slot, cruise + 100 m/s beyond. Within 150 m: the leader's nose, roll
  to its top (`PilotSteering.align_roll`), and `seek` with `all_axes` (mains or retros on the part of the error along the
  nose and the RCS on the rest, at once). `seek`'s cones fire the mains only within 12 degrees of the nose (the retros within
  30 of the tail) and expect the nose to turn toward the error, which a formation member's never does: with them, a
  4 degrees/s turn gave 33 / 78.5 / 64 m and a 10.6 m clearance. Beyond 150 m the nose turns toward the velocity change when
  it is over 30 m/s and not a slow-down along the way (else it faces the desired velocity and the retros brake; no flip for
  an overshoot), with the cones.
- **Fix round 1: lean and feed-forward.** (1) When the sideways part of the acceleration the wish asks for (`(v_des - v) /
  1 s`) is more than the RCS gives (10 m/s^2), the nose leans off the leader's toward it by the least angle that lets the
  mains or retros carry the rest, at most 40 degrees (`PilotSteering.lean_toward`); in steady flight it is the leader's.
  (2) The slot's own motion is fed forward: the leader's acceleration (its contact velocity against the last tick's) gives
  its flight path's turn rate `w = v x a / |v|^2`; the slot moves at `v_L + w x arm` and accelerates at `a_L + w x (w x arm)`,
  so `v_des = v_slot + clamp(0.4 e) + a_slot * 1 s` (the error `e` uses `v_slot` too). Without (2) a member lags about
  2.5 s x the slot's acceleration. Feeding forward the nose's spin instead (a `Contact.angular_velocity`, tried and dropped)
  made members chase the leader's nose swinging onto its lead, overspeed to 155 m/s, and drift out for the rest of the
  turn (#4 112 m at 10 degrees/s).
- **Scores.** 0.25 while the orders allow no attack on anything in sight (`has_attackable`), 0.1 while they do. Idle
  is 0.05 and the stickiness 0.15, so formation must score over 0.2 to take over from idle; an attack scores at least
  0.3 and must beat the current behaviour by 0.15, so formation stands by at 0.1 whenever there is something it may attack
  (any hostile at will; near or after the leader under COVER ME; the leader's target, in sight, under ATTACK MY TARGET).
  0 without a slot, or without a leader in sight or on the link.
- **Leader beyond sensor range** (beyond the brief): the director's link (the leader's universe position and velocity) lets
  a member that chased a raider out past 5 km fly back at the far closure; the slot offset counts again once the leader's
  contact is back. Without it the member would idle where the fight ended. While the leader is dead the link is cleared,
  the members fly ENGAGE AT WILL, and the wing's order comes back on the respawn.
- **Orders.** `UiCommand.wing_attack` / `wing_form` / `wing_engage` / `wing_cover` (four edges, so the input layer does not
  know `AiContext.Order`); keys 1-4 in `project.godot`, keyboard-only. Every order (repeated ones too) posts exactly one
  line from the member in the lowest slot: `ALPHA 2: COPY, ATTACKING RAIDER 1` / `FORMING UP` / `ENGAGING AT WILL` /
  `COVERING YOU`; ATTACK MY TARGET with nothing hostile selected (nothing, a buoy, a friend, or the leader dead):
  `ALPHA 2: UNABLE, NO HOSTILE SELECTED`, the order unchanged. A wing with no members stores the order and says
  `ALPHA: NO WINGMEN`. Console: `wing` (summary), `wing order [attack|form|engage|cover]` (words in key order; a refusal
  is a console failure, so `--console-strict` exits 1), `wing formation [finger_four|wedge|line_abreast]` (no
  acknowledgement); provider `wing` (`name`, `order`, `formation`, `members` as `ALPHA 2 100% formation (in slot)`,
  `last_ack`). `scripts/run_tests.sh`: the providers line gains `wing`, plus two smoke runs (order and formation; a bad word
  exits 1).
- **Saved control profiles** (fix round 1, controller ruling): a user profile that never mentions an action (saved before it
  existed, like the wing orders) takes the default profile's bindings and deadzone for it at load, with a notice
  (`ControlProfiles: control profile 'x' was saved before wing_attack, ... existed: they use the default bindings (controls
  save x keeps them)`, also shown by `controls use`); malformed entries, or an action in one section only, stay invalid.
  Built-in profiles are not filled. Architecture §15.12 says so.
- **Jolt numbers** (`test_ai_formation`, as of fix round 1: three `ally_starfury` members join from 200 m behind and 60 m
  out, 15 s straight, then a 90 degree turn at 100 m/s and 10 s straight; 1/30 s steps). The leader is flown like a player
  turns: its flight path swings at a steady rate and its nose goes ahead of it toward the acceleration needed (the
  centripetal part plus closing any gap), by as much as the RCS needs the mains to carry (`lean_toward` from the flight
  path, up to 80 degrees), mains burning. Every member is within 25 m after 5.9-6.2 s; straight flight max 2.4-2.5 m (the
  seek's 1 m/s coast band over k = 0.4); avoidance never acts in the straight legs (asserted). Max slot error (body frame)
  from the turn's start to 10 s after it, #2 / #3 / #4, the leader's largest nose lead over its flight path, and the least
  clearance between bounding spheres:

  | Turn | Max error (m) | Nose lead | Clearance (m) |
  |---|---|---|---|
  | 5 degrees/s left and right (18 s) | 2.4-2.8 / 2.4-2.8 / 3.2-4.0 | 2 degrees | 30.0 |
  | 6 degrees/s left and right (15 s), in the test | 16-18 / 16-18 / 34-35.5 | 23 degrees | 30.0 |
  | 8 degrees/s left and right (11.2 s) | 37 / 37-41 / 73-74 | 52 degrees | 23.3 |
  | 10 degrees/s left and right (9 s), in the test | 54-57 / 54-57 / 107-115 | 61 degrees | 19.6 |
  | 15 degrees/s left and right (6 s) | 78-109 / 78-109 / 156-249 | 93 degrees (the leader reaches 118 m/s) | 13.4 |

  **10 degrees/s, asserted per Q14** (fix round 1b): #2 and #3 within 80 m, the far slot #4 within 120 m, clearance at
  least 15 m, both directions; the 6 degrees/s turns keep 80 m for every slot. Why #4 needs more: a Starfury turning at
  10 degrees/s at 100 m/s needs 17.5 m/s^2 sideways, so its nose runs about 55-61 degrees ahead of its flight path, and the
  slots, being in its body frame, swing round it by that much when the lead builds up and when it collapses at the end of
  the turn (about 1.2 s). A member that holds its place relative to the flight path is then 2 r sin(lead / 2) from its
  body-frame slot: 57 m for #2 and #3 (r 56.6 m), 113-115 m for #4 (r 113 m). The measured peaks match those chords; in
  the steady part of the turn every member is within 10-24 m of the rotated slot. Easing the leader out of the turn over
  3 s did not help (#4 101-124 m: the lead still collapses in under a second once the RCS can carry the turn). Snap turns
  (the nose swung at 60 degrees/s) cannot be tracked with body-frame slots (note for AC15).
- **AC13 with a wing** (fix round 1): `test_ai_think_time`'s four Starfuries fly as wing ALPHA (ALPHA 1 leads, ALPHA 2-4 on
  COVER ME through a real `WingDirector`, rejoining at every switch back from the M2 blocks), so the formation's score and
  the order gate are in the paired cost: +101 us run alone (budget 500 us), with M3-T09 running Godot in parallel.
- **Slow leaders** (fix round 1c): the path's turn rate v x a / |v|^2 fed forward is capped at 20 degrees/s and fades in
  up to 30 m/s of the leader's speed, so a leader thrusting from near rest does not fling the far slot (428 m/s of wish
  before, for a 5 m/s leader pulling 20 m/s^2; `test_formation`). The AC9 runs are unchanged.

**M3-T08 (allied ships: pool, LOD1, destruction, replenish).**
- **Spec and LOD.** `assets/ships/starfury_ally.tres` is `starfury_aurora.tres` with `splat_lod = 1` and `has_cockpit_interior = false`
  (same `asset_id`, so the hardpoints, hull mesh and chunks are the Starfury's; `test_ship_catalog` compares every stored `ShipSpec`
  field). `ShipSpec.splat_lod` (0 = the full PLY): `Ship._load_visuals` asks `SplatLod.resolve(asset_id, level)`
  (`src/ship/splat_lod.gd`, pure, returns `{path, level, warning}`; level 0 is `<asset_id>.ply` without reading the manifest, a higher
  level is looked up in `manifest.json` `lods` by `level`). A level the manifest does not list warns once and draws LOD0; a manifest that
  is missing or unreadable warns once ("... manifest.json is missing") and draws no splats, with no second "ply missing" message. The ally draws
  `starfury_aurora_lod1.ply` (57 538 splats against the player's 230 230).
- **`ShipCatalog`** gains `starfury_ally` and `FACTIONS` / `faction_for(type)` (`starfury_aurora` and `starfury_ally`
  `earth_alliance`, `raider_fighter` `raiders`; `neutral` for an unlisted type).
- **`ShipPool`.** `prepare(type, count)` builds with the catalog faction; `acquire(name, at, basis, velocity, brain, type)` is unchanged
  (the caller names the ship); `next_name(prefix = "RAIDER", first = 1)` (allies: `next_name("ALPHA", 2)`, the player is ALPHA 1).
  `alive()`, `pool_size()` and `free_count()` take an optional `type` (no type = every pooled ship); `type_of(combatant)` is new.
  `ALLY_TYPE` is `starfury_ally`. Providers `raiders` and `allies` (`pool_size`, `free`, `alive`, `list`, `selected_brain`, each about its
  own type; there is no `wing.members` yet). `spawn <raider|ally> [behaviour] [distance_m] [yaw_deg] [pitch_deg]`: an ally takes only `idle`
  or `ai` (profile `ally_starfury`; a raider's `ai` uses `raider`), is named `ALPHA <n>` from 2 and placed like a raider (ahead of the
  player, nose toward it). `despawn all` and `despawn target` return any pooled ship (P5 needs the ally to go).
- **Scenario and `Main`.** `combat_sandbox` pools `{"raider_fighter": 6, "starfury_ally": 4}` (three wingmen and a spare for `spawn ally`;
  **T10 owns the final pool numbers**: it launches the wingmen and sizes both pools); `ScenarioLoader` needed no change beyond its doc (any catalog type may be pooled). `Main.ally_pool_size`
  (-1 = the scenario) next to `raider_pool_size`, and `Main` prepares the pools by type. `DebrisPool.prepare(type)` is now idempotent per
  asset (the player's `starfury_aurora` and the allies' `starfury_ally` share one asset): `Main` always prepares the two `starfury_aurora`
  chunk sets, in every scenario, and the raider's only when raiders are pooled. `DebrisPool.set_count` / `free_set_count` take an optional
  asset id.
- **Destruction.** `DestructionDirector.ship_destroyed(combatant, info)` fires for every pooled ship; `raider_destroyed` still fires after
  it when the ship is a raider by pool type (`ShipPool.DEFAULT_TYPE`, not the faction relation, so a console `relation` change cannot turn
  kills into losses), so kills count raiders only and an ally's death is no kill. `AudioDirector` moved to `ship_destroyed` (an ally explodes with a sound). An ally is released in the same tick and breaks up
  into the Starfury chunk set, like the player (`burst` is keyed by `spec.asset_id`, which is `starfury_aurora` for both). `kill all` still
  means every raider (pool type `DEFAULT_TYPE`); `kill allies` takes pool type `ALLY_TYPE` (an error when none is in play); `kill target`
  takes any pooled ship.
- **Waves.** `WaveDirector` counts and clears `ShipPool.DEFAULT_TYPE` ships only (`waves.alive`, the wave-cleared test, `_clear_field`, the
  status line, `on_player_respawned`), so allies in the pool are neither raiders nor removed by `wave start|stop|next|restart`.
- **Tests.** New: `test_splat_lod`, `test_ship_catalog`, `test_ally_pool` (the pool, LOD1 hull and no cockpit, the Starfury formula for a
  straight burn with assist on - 30.0000 m/s after 2 s against 30.0000 expected, naming, per-type counts, 12 acquire / release cycles with
  an unchanged splat-node count, the console, and an inner class on the sandbox for the waves) and `test_starfury_breakup` (the player's and
  an ally's break-up are five pooled splat chunks that hold exactly the LOD1 hull's splats, ally back in the pool, two sets shared and a
  third break-up mesh-only, the splat-node count over launch / destroy / respawn rounds). Changed to follow the new facts:
  `test_destruction` (the player's break-up is now splat chunks, raider set counts per asset), `test_audio_director` (11 engine hums:
  the player and 10 pooled ships), `test_wave_director` (`pool_size(type)`), `test_scenario_loader` (the sandbox's pools).
  `scripts/run_tests.sh`: the providers line gains `allies`, `debris.free_sets` after a raider kill is 3 (two raider and two Starfury sets),
  and two smoke runs (`spawn ally` / kill / `kill allies` / the player's death, and `spawn ally attack` exiting 1). A smoke run that
  quits while an explosion sound still plays makes Godot report the WAV as "still in use" (an `ERROR:` line): the new run waits 300 ticks
  before it quits.
- **Splat budget (sandbox).** Registered splats are 841 362 (M2: 496 134), +345 228: player 230 230, four allies 230 152, six raiders
  158 928, raider debris 52 976, Starfury debris 115 076 (two LOD1 sets), sky 16 000, five buoys 38 000. Of the increase, the four parked
  LOD1 allies are about 230k (two thirds) and the two Starfury chunk sets about 115k (one third). A hidden splat node still costs an
  early-out per splat in projection and sort-buffer memory, so parked ships and parked debris both count. Levers if AC19 shows a problem:
  fewer allies in the pool (each is 57 538; T10 decides the pool size, three wingmen are the minimum for the wing), one Starfury chunk
  set instead of two (57 538, a second simultaneous Starfury break-up then gets mesh chunks), or a coarser ally LOD. Recorded for the
  (H) frame-rate check.
- **Shared constants.** `ShipSpec.ASSET_ROOT` is the one definition of `res://assets/generated` (`Ship`, `SplatLod`, `DebrisPool` and
  `ShipSpec.hardpoints_path()` use it) and `ShipCatalog.PLAYER_TYPE` the one for the player's type (`Main` builds its ship from the catalog
  and prepares its debris with it). Fix round 1 also made the M2 tests that mean raiders ask for `alive(ShipPool.DEFAULT_TYPE)`.
- **Replenish (phase 2, after T07).** `WingDirector.replenish(wing := null) -> Array[Combatant]` (the player's wing by default; the
  ships launched, lowest slot first) gives each empty slot an ally from `ShipPool.ALLY_TYPE`. `Main` passes the pool in
  (`wings.setup(world, ships)`, `WingDirector.pool`) and connects `WaveDirector.wave_started` to `WingDirector.on_wave_started`, which
  calls it. Per replacement: `pool.acquire(wing.callsign(slot), at, basis, velocity, brain, ALLY_TYPE)` (so ALPHA 2 for slot 1, no longer
  `next_name`: the deferred T07 minor 3), then `add_member(wing, ally, slot)`; the brain is `ai` / `ally_starfury` born with the wing's
  current order (`add_member`'s refresh confirms it, and gives it the formation behaviour, its slot and the leader link). Positions go
  through `UniversePos` (`world.to_universe(leader)` then `plus_local`), taken and used inside the one call, so nothing is cached across
  ticks for M3-T14's rebase.
  - **Behind = along the player's nose axis** (the body frame's +Z, the way `Formation` counts "behind"), `REPLENISH_DISTANCE_M` = 1 500 m
    exactly. The velocity can be zero (a player at rest has no behind) or point anywhere (braking, drifting), so it is no reference.
    The replacements do not stack on one point: each enters in its slot's lane (the formation's x and y offset: -40, +40, +80 m for
    #2-#4 in a finger-four, so at least 40 m apart), which adds at most 2.1 m to the 1 500 m range. They take the player's heading and
    velocity.
  - **Slots, tick order.** `replenish` calls `refresh(wing)` itself rather than relying on the per-tick one, so a wingman shot down
    in the very tick the wave starts is an empty slot whoever calls it. In the normal order the hit resolvers (200) and the director's
    own refresh (290) have already dropped it before the `WaveDirector` (300) emits `wave_started`; the explicit refresh covers the
    other callers (the console's `wing replenish`, which refreshes before it looks at the slots, tests, a signal fired outside the
    physics order). The test kills a wingman and starts the wave with no tick in between.
  - **Decisions.** Pool short: it launches what the pool has, lowest slots first, with one `push_warning` per call
    ("replenish launched 1 of 3 wingmen ..."; `ShipPool.acquire` is never asked for a ship that is not there, so its own warning does not
    repeat per slot); a scenario that pools no allies (free flight, tests with `ally_pool_size` 0) is silent. No wing, no pool, the leader
    down (`leader_alive` false: the player is dead) or the tree paused: it launches nothing; the next wave start tries again. A callsign
    already on a ship in play (a console `spawn ally` takes ALPHA 2 on the next free number) is not given twice: that slot's ship is named
    with the next free number after the wing's own (`next_name(wing.name, wing.size + 2)`: ALPHA 5), so the other slots keep their
    callsigns and every name in play is unique; the stray ship stays out of the wing. A wing with no members at the wave start is filled
    like one with downed members: until T10 launches the sandbox's wingmen at load, the first wave start brings all three (the
    sandbox test in `test_ally_pool` now expects that). The wing's other members are never touched; a full wing launches nothing.
  - **Console.** `wing replenish` (the `what` choices gain `replenish`): `ALPHA: launched ALPHA 2, ALPHA 3, ALPHA 4 (1500 m astern)`,
    `ALPHA: no empty slot` (success), or a failure naming why nothing launched (leader down, paused, `no free allied ship: 3 of 3 in the
    pool are in use`). `scripts/run_tests.sh` has a smoke run: replenish, `wing order engage` (acknowledged by ALPHA 2), `kill allies`,
    replenish again, then "no empty slot".
  - **Tests** (`test_wing_replenish`, 12): one and two downed wingmen replaced in their slots by callsign, 1 500 m behind along the
    nose (the player turned 40 degrees and drifting along another line), in the slot's lane, at the player's velocity and heading, on
    FORM ON ME / ENGAGE AT WILL with the formation behaviour, a slot, the leader id; an empty wing filled with no two ships closer than
    39 m; a full wing untouched; a pool of two fills two slots with one warning and serves the next call when a ship comes back; no
    ally pool: silent; dead leader and no wing: nothing; a taken callsign; AC7: the splat-node count unchanged over five kill / replenish
    cycles; a real `wave start 1` in the sandbox replenishes through `Main`'s wiring, 1 500 m astern as the wave begins; the console.
    `test_ally_pool`'s sandbox test now expects the three wingmen next to the console ally.
- **P5 is (H).** The capture needs a display and a GPU. Its console commands were run headless without the `screenshot` lines (spawn,
  `despawn all`, spawn with yaw and pitch, `set targeting.selected "ALPHA 2"`, `timescale 0.1`, `kill target`: five Starfury chunks flying,
  none mesh-only).

**M3-T14 (position rebase in play, Q13).**
- **On.** `main.tscn` sets `World.auto_rebase_distance_m` to 5 000 m (`world.focus` is the player); a bare `WorldFrame` keeps 0.
  The rebase runs in `World._physics_process` at priority 0, after the AI drivers (-10), the console and `Main`, before every
  node below `World` and the late systems (architecture §14.1, §15.3 step 3b). `WorldFrame` counts `rebases` and times the last
  one (`last_rebase_us`); the `world` provider shows both (`rebases`, `rebase_us`). The velocity rebase stays M6.
- **Reproduced first.** In the build before T14, after `rebase -900000 0 0` and under full main thrust with the nose off every
  axis, the change of step in universe coordinates (`(u[k] - u[k-1]) - (u[k-1] - u[k-2])`, 64-bit) spread up to 57.1 mm round its
  mean (rms 17.5 mm; a dt^2 is 8.3 mm). With the rebase on: 0.005 mm (rms 0.002). A nose along -Z showed nothing: only the
  coordinate that is 900 km long quantises, so the test thrusts diagonally.
- **The audit** (everything that keeps a position between ticks). Fixed:
  - `RamResolver` / `RamTracker`: an open contact window kept its World-local point for up to three ticks, and Jolt's contacts
    are in the frame of its last step, so a rebase in between put the ram's point (and its damage zone) kilometres off (3.2 km
    in the test). `RamResolver.world` (set by `Main`) follows `rebased`: the points read this tick lose the rebases since the
    step, and `RamTracker.shift` moves the open windows.
  - `WaveDirector`: the `origin` anchor was `world.to_universe(Vector3.ZERO)`, the World's local origin, which now follows the
    player. It is the scenario's origin, universe (0, 0, 0), where the props are (no shipped scenario uses it).
  - `Explosion`: sparks and embers were `GPUParticles3D` in global space, which a rebase cannot move (they would be left 5 km
    away). Their nodes are now `top_level`, placed where the ship blew up, in `world_shiftable`, with `local_coords`: the M2 look
    (they stay behind while the ball drifts) is kept, and a rebase moves them. `test_explosion`'s M2 assertion
    `assert_false(local_coords)` became the same intent through the new mechanism (`top_level`, shiftable).
  - `AudioDirector.play`: a voice moved to a new sound inside a tick blended from its last sound (and from where a rebase left it)
    until the next tick; it resets its interpolation now.
  - Safe as they were: `ShipPool` and `DebrisPool` parking (shifted with the rest; placed again from a `UniversePos` when taken
    out), impact flashes and muzzle flashes (children of the ship), engine hums (children of the ship), the HUD reference point
    (`UniversePos`, converted every frame; `Main.reference_point()` is new, for tests), `WaveDirector`'s player anchor, props,
    `ContactScan` and `Perception` (built at -10 every tick, before the rebase), `AiPilot` behaviours (contacts re-picked every
    tick in `score`), `AiContext.leader_link_position` and the formation slot (`UniversePos` / rebuilt from the leader's contact),
    replenish (positions taken and used in one call), `PatrolBrain` waypoints (`UniversePos`), `CameraRig` (chase camera
    shiftable; cockpit pivot reset by `Main` on `rebased`), `SplatPoseSync` (only a fixed offset), debris chunks and bolts
    (shiftable, store velocities and a step), `HitResolver` (nothing kept between ticks), `TargetingController` (candidates
    rebuilt at 100; `apply` and `select_nearest_hostile` gather first), `SkyFollower` (camera-relative, outside World, after
    the rebase). T09 routes and T10 guard points must keep `UniversePos` (or rebuild from live nodes) and can prove it with
    `RebaseFight`.
- **AC21 numbers.** After `rebase -900000 0 0` the automatic rebase in the same tick puts the player on the origin and moves the
  13 ships, buoys and bolts by at most 0.021 mm in universe terms, velocities by 0 (the console's own shift to 900 km rounds
  them by up to 21 mm: float32 at 900 km, the bug itself). Sandbox fight with the wing on ENGAGE AT WILL, the threshold at 40 m
  and the player cruising at 60 m/s (`SPEED_UP` 4): waves 1 and 2 cleared in about 70 s of sim time, 96 rebases (longest gap
  0.78 s), 42 bolt hits (4 in rebase ticks), 6 kills; universe jumps within each body's motion, chase camera 0.0000 m, HUD range
  0.0000 m, every node drawn at its tick pose in the frames after the rebases. The 1 mm clause is measured from the state right
  after the console's own 900 km shift (its float32 rounding of about 21 mm there is unavoidable; accepted at review). Cost of one
  rebase of the full sandbox: see fix round 1 below (the first build measured a median of 0.22-0.45 ms with spikes to 1.1 ms).
- **Interpolation (fix round 1).** The first build reset every shifted node at the rebase. The bodies were then drawn held at their
  tick-start pose for one tick while bolts, debris and the explosion ball, moved later in the tick, blended on, so at 5 000 m/s a
  bolt beside the ship jumped 83 m off its motion in the view once a second. Now the world stalls together: `rebase` leaves the
  interpolation alone and `World`'s internal `RebaseSettler` (physics priority 1 000 000, last in the tick) resets every visible,
  interpolated shiftable node at the end of a tick with a rebase, so that tick is drawn held, everything together (at most one
  repeated frame; AC22 stays (H)); outside a tick `rebase` resets at once. The alternative, no reset at all, draws everything
  sweeping by the offset over the tick, smooth in the view, but measured the HUD's markers through the chase camera 3.4 km off
  what is drawn (the sky in the cockpit and anything spawned in that tick would be off too), so it was not taken. Measured per
  rendered frame (`test_through_a_rebase_at_full_speed_...`): bolt off its motion relative to the ship 83.3 m before, 0.001 m now;
  HUD versus drawn NAV ALPHA 0.000 m; chase camera and cockpit pivot locked to the drawn ship (0.0007 m, 0.0005 m). Mutation
  checks of the first build: without any reset the fight fixture fails 3 052 times; with the chase camera out of `world_shiftable`
  it fails at every rebase (43-44 m).
- **Cost (fix round 1).** Hidden (parked) nodes and silent voices are no longer reset (they are re-placed and reset when they come
  back); parked ships and debris stay in `world_shiftable` and are still shifted (`test_ship_pool`, `test_debris_pool`). One
  rebase of the full sandbox (shift, `rebased` handlers and end-of-tick reset), over a fight's 96 rebases, idle: median
  0.28-0.30 ms from run to run, min about 0.12 ms, max 0.5-0.6 ms (the first build on the same machine: median 0.39-0.45 ms, max
  0.9-1.2 ms). The ships dominate (a Starfury is 108 nodes, walked by the shift and by the reset): about 17 us to reset and 7-10
  us to shift each. The median stays asserted under 0.5 ms. The 900 km test prints its rebase cost without its own snapshot
  handler.
- **Accepted at review, no change.** `test_explosion`'s M2 assertion change (`local_coords`; the new test checks the behaviour
  directly): M2 AC16's explosion look needs an (H) glance, listed under AC0 at merge. The 1 mm clause after the console's own shift
  (above).
- **`RebaseFight`** (`tests/fixtures/rebase_fight.gd`), for T09, T10, T13: `await RebaseFight.run(test, main, sim_s, until :=
  Callable(), threshold_m := 40.0, cruise_mps := 60.0, rebase_every_s := 0.0) -> RebaseFight`. It forces the threshold down, gives
  the player `cruise_mps` along its nose when slower (0: the caller moves the player), with `rebase_every_s` > 0 forces a 1 km
  rebase at the start of a tick whenever that much sim time passed without one (a player who sits still), runs until `sim_s` of
  sim time or `until`, restores the threshold and asserts: a rebase at least every 2 s; no ship, prop or bolt jumps more than its
  motion plus 1 m in a tick; every bolt hit on its bolt's path and its target's hull, every ram on its hull; after every rebase
  tick the structure (each object under World shiftable or below a shiftable node, every `top_level` node below World shiftable
  itself, no particles in global space: the sparks bug, caught by a mutation run); the chase camera moved with the ship at each rebase
  (1 mm) and kept its offset from the drawn ship every frame (1 cm); the HUD's reference range equals the universe distance;
  every visible interpolated node of World drawn at its tick pose (1 cm) in the frame after a rebase. It returns the counts
  (`rebases`, `forced_rebases`, `rebase_ticks`, `hits`, `hits_in_rebase_ticks`, `rams`, `kills`, `rebase_us`) and `summary()` for
  the caller's own asserts.
- **Tests.** New `tests/integration/test_rebase_in_play.gd` (8: the 5 km setting, 900 km out and back, the thrust jitter with and
  without the rebase, a change-of-step window across an automatic 5 km rebase under thrust (0.46 mm, the 5 km float32 step), the
  low-threshold sandbox fight, 4 000 m/s through 5 km rebases with an explosion and debris in flight, the view at 5 000 m/s through
  a rebase, a still player rebasing on the fixture's timer), `test_world_frame` (an in-tick rebase draws the world at its tick
  pose until the next tick),
  `test_world_frame` (count and cost, provider keys), `test_ram_tracker` (shift), `test_ram_damage` (a contact ram with the world
  rebasing every tick; `Main` wires the resolver), `test_wave_director` (origin anchor after a rebase), `test_explosion` (sparks
  stay and move with a rebase), `test_audio_director` (a reused voice is heard at its new place at once).
  `scripts/run_tests.sh`: `rebase -900000 0 0; wait 1; state world; get ship.position` on the real main scene.

**M3-T09 (instructor: follow path, pacing, demo manoeuvres, route scenario).** Merged into `m3` as unreviewed work in progress
(maintainer, 2026-10-27); the review, its fixes and a `RebaseFight` check of the route (T14) are still to do.
- **Built.** `Route` (`src/ai/route.gd`, pure: `Waypoint`s as `UniversePos` with `demo` and `hold_s`, `cruise_mps` 60, `pace`
  `player|none` and the spawner-set `pace_id`, `loop`, the pacing constants and `pace_speed` / `should_wait` / `lag_to`).
  `Manoeuvre` (base: `step(p, dt)` until `done`, `result()`, `needs_speed()`, `TIMEOUT_S` 45 as a safety net, the desired-velocity
  protocol) and `Manoeuvres` (the five as inner classes, `create(name)`, `NAMES`, `display_name`). `BehaviourFollowPath`
  (`follow_path`, score 0.5; states `lead`, `wait`, `run_up`, `demo`, `hold`, `done`) reads `AiContext.route` (new field);
  `BehaviourFollowPath.attach(pilot, route)` sets it and adds the behaviour once. `assets/ai/instructor.tres` weighs `follow_path` 1.
  `ShipCapability.alpha_max_rad` (RCS torque / inertia per axis, for the roll's stop). `Damageable.invulnerable` (no damage from
  bolts or rams, `hit_taken` still fires; the console's `kill` gets through, as through god mode; `ShipPool.acquire` clears it).
- **Scenario schema.** `routes[]` (`{name, cruise_mps, pace, loop, waypoints: [{position, demo, hold_s}]}`, absolute universe
  positions) and top-level `spawns[]`: ships placed at load, a wave spawn's fields plus `invulnerable` (bool) and `route` (a
  route's name; needs an `ai` behaviour). Path-qualified errors for both (`routes[0].waypoints[2].demo must be one of ...`,
  `spawns[0].route 'X' is not a route of this scenario (TRAINING)`); load spawns and each wave share the pools (`waves[0]: 4 spawns of
  raider_fighter and 1 ship at load but pools.raider_fighter holds 4`). `Main` places the spawns from the pool after the props (name,
  anchor + offset, the player's start attitude, the brain, the flag, the route with `pace_id` = the player's `Targetable` id) and
  **places them again on every respawn** (the lesson starts over; the instructor would otherwise wait for a player that respawned out of
  sensor range). `instructor_route.json`: the five buoys, no waves, pool `{"starfury_ally": 1}` (the instructor is a pooled LOD1
  Starfury), route TRAINING of six waypoints (NAV 1 none, NAV 2 roll, NAV 3 strafe_box, NAV 4 pod_turn, NAV 5 flip_and_burn hold 2 s,
  NAV 6 all_stop hold 3 s), each at least 140 m from a buoy; the box's NAV 3 lies on the line toward NAV 4, so the 1.2 km the box
  travels at cruise is not wasted. `settings.scenario` and `Main.SCENARIO_CHOICES` gain `instructor_route`.
- **Pacing as built.** The lag is the distance to the pace contact (INF when it is not in sight: destroyed, parked or beyond 5 km;
  0 with `pace: none`). `lead` flies `cruise * clamp((1500 - lag) / 900, 0, 1)` toward the waypoint; beyond 1 600 m `wait` brakes with the
  player selected, so the brake turns the nose onto it (§5.5 brake-to-face), until the lag is under 800 m. Beyond the brief: **a demo
  also waits for the player within 800 m** (same `wait` state), so the move is shown to someone close enough to see it; a demo that
  takes speed away (flip and burn, all stop) is shown from at least 90 % of cruise, with a **run-up** toward the next waypoint first;
  pacing never interrupts a move that has started; a move that loses control to another behaviour starts again on return. In Jolt
  (`test_instructor_route`, 0.1 s steps): with the player parked the instructor stopped at NAV 2, 1 097 m out, facing the player
  within 0.1 degrees, still waited with the player at 1 000 m and started the roll when the player was put 700 m away; left 2 km behind
  on the next leg it braked, stopped 2 012 m out facing the player within 0.6 degrees, waited at 1 000 m and led on from 700 m.
- **Demo goals in Jolt** (`test_manoeuvres_jolt`, one `starfury_ally` each, assist forced on, from 60 m/s, 60 Hz; measured from the
  body, not from the moves' reports):
  - roll: 4.73 s; the up axis turned 360.7 degrees at the end and 361.4 settled; peak 90.0 degrees/s (the roll rate limit); then
    `min(K_FACE * left, sqrt(2 * 0.5 * alpha * left))` to stop on the circle.
  - flip and burn: flip 3.43 s, burn 2.0 s on both mains at full; ends at 1.92 m/s along the starting direction (under 2 m/s; the burn
    is a seek to rest, so it does not reverse).
  - strafe box: 19.7 s; legs 50.44 / 50.45 / 50.45 / 50.45 m; back within 0.45 m of the start moving at the starting velocity; nose held
    to 0.00 degrees. **Deviation**: the brief's "legs of 1.5 s each" cannot give AC10's 40 m legs with the Starfury's 10 m/s^2 RCS (a 1.5
    s push covers 11 m), so each leg is a seek to the next corner of a 50 m square that moves with the starting velocity, opening
    with a full-strafe push of about 1.4 s (1.37 s in the unit model) up to 15 m/s and braking onto the corner; a leg ends within 2 m,
    under 1 m/s relative.
  - pod turn: 1.32 s on the left main alone; 30.3 degrees right at the end, 38.9 settled. With the assist on, the pod difference is
    a 30 degrees/s yaw-rate command and the assist trims the left main (at most 0.43 of full) because its torque is more than the
    RCS can cancel.
  - all stop: 4.85 s; 0.498 m/s and 0.000 degrees/s.
  - On the route at 0.1 s steps with the player kept 300 m behind (`test_instructor_route`): every waypoint in order, the route done in
    197 s of sim time; roll 360.42, box legs 50.24 m and closure 0.24 m, pod turn 30.84, flip and burn from 59.0 to 1.25 m/s, all
    stop 0.448 m/s and 0 degrees/s; none timed out.
- **HUD.** `HudInput.has_waypoint` / `waypoint_position` (World, converted from the `UniversePos` every frame) / `waypoint_label`
  (`NAV 3`); `HudFrame.waypoint_*` (on screen at the projected point, else an edge arrow; `HudLayout._edge_arrow` now returns its point
  and angle, shared with the target's arrow) and a plain green diamond with label and range in `Hud` (T11 draws the final look).
  Status line: `FOLLOW INSTRUCTOR — NAV 3/6 — NEXT: STRAFE BOX` while leading, `CLOSE UP ON INSTRUCTOR — ...` while waiting,
  `WATCH INSTRUCTOR — NAV 3/6 — STRAFE BOX` during a run-up or demo, `FOLLOW INSTRUCTOR — ROUTE COMPLETE` at the end; it replaces the
  waves' line while a ship leads a route (`Main.route_active()`: the instructor in play and still flown by that pilot). The main-scene
  test checks the marker against `Camera3D.unproject_position` within 0.5 px.
- **Console.** Provider `route` (`index` 1-based like the HUD, `count`, `lag_m` (-1 out of sight), `state` (`none` when the
  instructor is not flying the route), `demo`), registered by `Main` only on a scenario with a route ship, so the sandbox's providers
  line is unchanged. `ai INSTRUCTOR` shows `follow_path (lead)` with `nav`, `lag_m`, `demo` (and the move's `step` during a demo). New
  smoke run in `scripts/run_tests.sh`: `scenario instructor_route` lists `route` in `state` and leads the first leg.
- **Not touched.** AC13's fight: `follow_path` exists only on a pilot given a route, so the ally and raider profiles score nothing new.
  `docs/playtest.md` still lists `scenario [combat_sandbox|free_flight]` (T12 writes the M3 section). P6 is (H): its console
  commands run headless without the `screenshot` lines (`scenario instructor_route`, waits, `camera cockpit`, `state route`).

## Definition of done (M3)

- T01-T25 merged into `m3`, `scripts/run_tests.sh` green, `docs/third-party.md` current, no generated binaries committed.
- Every (A) criterion passes.
- AC14-AC19 and AC35 ticked by the maintainer, with GPU, driver, FPS and VRAM recorded below. Then `m3` merges into `main`.

Human acceptance record (fill in):

```
Tester:                                  Date:
OS / kernel / Mesa or driver:            GPU:
Splat backend shown:                     FPS with 4 Starfuries + 9 raiders + effects:
AC14 [ ]  AC15 [ ]  AC16 [ ]  AC17 [ ]  AC18 [ ]  AC19 [ ]  AC35 [ ]
VRAM / frame time, AC19 fight and 100 ships, before and after T19-T20:
Notes:
```
