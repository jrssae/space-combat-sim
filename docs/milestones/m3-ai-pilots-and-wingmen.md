# Milestone 3: AI Pilots and Wingmen

> "Others who fly." (`docs/roadmap.md`)

**Status:** planned 2026-10-21 on branch `m3`. The maintainer answered the planning questions the same day (below). M2's
(A) work is done; its AC20 (saved control profile) and AC21 (sound) still wait for a re-test and do not block M3.

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
  chunked asset; the Starfury has no `chunks[]` yet (the player dies into generic shards).
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

Out (explicitly):
- Dialog, subtitles, the comms panel, mission scripts, objectives (M4). Order acknowledgements are one HUD text line.
- A pad comms menu (M4, with the comms panel). Orders are keyboard and console only in M3.
- Tutorial checks that the player copied a demo (M7). The instructor only shows the moves.
- Capital ships, turrets, subsystems, towing (M11 / M13). The station and jumpgate (M5 / M6).
- New factions beyond `earth_alliance`, `raiders` and `neutral` (the data format allows them; M11 adds them).
- Physical collision for buoys (they stay `Node3D` props; rams against them are detected, not bounced).
- Splat LOD switching by distance (M5's `LodSwitcher`); M3 only picks a fixed LOD per ship class.

## Maintainer answers (2026-10-21)

Record later answers here (rules) or in `docs/design-references.md` (designs), so agents never rely on chat history.

| # | Question | Answer |
|---|---|---|
| Q1 | How does the player order wingmen (the pad has no free buttons)? | **Autonomous + keys**: wingmen form on the player and engage hostiles by themselves; orders on keys 1-4 and console commands. A pad comms menu waits for M4 |
| Q2 | Friendly fire? | **A setting, default off** (`settings.friendly_fire`). The AI's fire-lane check is built either way |
| Q3 | Ram damage? | **Speed-scaled**: bumps under about 5 m/s harmless, about 30 m/s wrecks a Starfury, tunnelling speeds always fatal for both. `god` protects the player. Applies to buoys too |
| Q4 | Allies at once? | **Three wingmen** (finger-four with the player). Allies use a lighter splat Starfury (LOD1) |
| Q5 | Instructor? | **Paced route + demo moves**: leads a waypoint route, slows or waits for the player, the HUD marks it and its next waypoint, and it performs manoeuvres at waypoints (roll, flip-and-burn, strafe, pod turn, all stop). No dialog |
| Q6 | Raider AI? | **Yes**: raiders use the utility AI too (evade, groups of 2-3, collision avoidance). M2 idle / patrol brains stay for target practice |
| Q7 | Sandbox? | **Wingmen in `combat_sandbox`**, raider waves grow to match; plus `instructor_route` and `dogfight` scenarios |
| Q8 | Wingman deaths? | **Replaced at the next wave**: a downed wingman explodes (Starfury chunks) and a replacement launches when the next wave starts |
| Q9 | Keyboard (right hand on the mouse; M2.1 put flight keys on the right side, which was wrong) | **Layout B, pods by position**, no keyboard pitch/yaw (the mouse flies). Table in M3-T01 |

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
| AC0 | Every M1 and M2 (A) test still passes, except tests that assert the old keyboard keys, which T01 updates. With `factions.json` at its defaults, every M2 faction, hit and target-order result is unchanged | A | |
| AC1 | Keyboard layout B: `project.godot` and `m1_classic` hold exactly the T01 table; no flight action has a key right of the G/B column (Backspace, N, Print, F3/F4 and Esc are the only keys outside the left block); every action keeps a pad binding (wing orders are keyboard-only and allow-listed); `B` is tap = next target, hold = nearest the nose; `W` and `S` drive both pods; a profile round trip is exact | A | |
| AC2 | Factions: `data/factions.json` validates (broken variants give path-qualified errors and leave the table unchanged); same faction is FRIENDLY, an unlisted pair is the file's default, listed pairs are symmetric; `relation` on the console changes a pair for the session and HUD colours follow | A | |
| AC3 | Friendly fire: with `settings.friendly_fire` off, nothing changes from M2 (AC3 of M2 still holds); on, a bolt hits any active hull except its shooter's (allies, the player, buoys); god mode still protects the player; an AI never fires while a friendly sits in its fire lane (both settings) | A | |
| AC4 | Ram damage: two Starfuries meeting at 4 m/s closing take no damage; at 30 m/s each loses at least 50 % hull; at 600 m/s closing (one tick is 10 m) both are destroyed and neither tunnels through unhurt (50/50 seeded offsets inside the hull overlap); a ship ramming a buoy at 40 m/s destroys the buoy; the player with `god on` takes nothing and still bounces; `HitInfo.cause` is `ram`; kills by ram count | A | |
| AC5 | Avoidance (`AvoidanceMath`, pure): head-on, crossing and overtaking cases produce a dodge that raises the miss distance above the sum of radii plus margin; diverging or distant contacts produce none; ties break by seed, never NaN. In Jolt: two AI ships set on a head-on course at 150 m/s closing pass without contact in 20/20 seeded runs; an AI ship aimed at a buoy at 100 m/s misses it | A | |
| AC6 | Starfury asset: `python3 -m tools.procgen build starfury_aurora` also writes LOD1 (`lods[1]`, 20-30 % of LOD0's splats, same AABB within 0.3 m) and `chunks[]` `cabin`, `arm_ur`, `arm_lr`, `arm_ul`, `arm_ll` that partition the LOD1 splats exactly; LOD0 output is byte-identical to before; deterministic; after `--import` the LOD1 and chunk PLYs load with manifest counts | A | |
| AC7 | Allied ships: a `starfury_ally` from the pool flies the Starfury `ShipSpec` numbers (M1 AC5 formulas) with LOD1 splats; the splat-node count never changes across acquire / release / destroy / replenish cycles (D22); a destroyed ally explodes into Starfury chunks and returns to the pool; the player's death also uses Starfury chunks | A | P5 |
| AC8 | `AiPilot` selection (unit, scripted `AiContext`s): the highest weighted score wins; the current behaviour keeps a stickiness bonus and a minimum dwell unless a challenger beats it by the emergency margin; orders gate behaviours (FORM ON ME never attacks; ATTACK MY TARGET attacks only the leader's target); `describe()` names the behaviour and its state; same seed = same choices | A | |
| AC9 | Behaviours in Jolt: **formation** members hold within 25 m of their slots in straight flight and within 80 m through a 90° leader turn at 100 m/s, never closer than 15 m to anyone; **evade** cuts an M2 attack raider's hits on the evader by at least half against the same seeded run without evade; **guard** engages a hostile that enters the guard radius and returns within 300 m of its post once it is gone; **retreat** below 25 % hull opens the range | A | |
| AC10 | Instructor: on `instructor_route` the instructor visits every waypoint in order; with the player parked it stops within 1 600 m and resumes when the player closes to 800 m; each demo completes its measurable goal (roll 360 ± 10°, flip-and-burn ends with velocity reversed or below 2 m/s, strafe box returns within 30 m of its start with every leg over 40 m, pod turn yaws the right way by over 30°, all stop ends below 0.5 m/s and 1 °/s); the HUD's waypoint marker projects to the route point | A | P6 |
| AC11 | Wing orders: keys 1-4 (through `UiCommand`, never `Input`) and `wing order <attack\|form\|engage\|cover>` change every member's order and post one acknowledgement line; ATTACK MY TARGET with no hostile selected is refused with a message; the roster lists callsigns, hull and current behaviour; downed wingmen are replaced when the next wave starts, entering 1 500 m behind the player | A | P7 |
| AC12 | Scenarios: `combat_sandbox`, `instructor_route` and `dogfight` validate (and broken `wings` / `route` entries give path-qualified errors); a headless sandbox run with wingmen clears three waves; a headless `dogfight` (four allies, six raiders, player `god on` and idle) ends with one side destroyed within 6 sim minutes in 5/5 seeds and is reproducible per seed within 1e-3 m after 60 s | A | P8 |
| AC13 | Console and perf: `state` lists the M2 providers plus `factions`, `ram`, `wing`, `ai` (and `route` on `instructor_route`); every new command works under `--console-strict` and rejects bad arguments; new settings are schema entries; AI think time for 13 ships stays under 1.5 ms per tick headless (record the number); the hit and ram resolvers stay under 2 ms per tick in the dogfight run | A | |
| AC14 | Keyboard layout B feels right with the right hand on the mouse; Caps Lock rolls (press and release both register) | H | |
| AC15 | Wingmen fly a believable finger-four on the player, break to engage, rejoin, follow orders 1-4, and are useful in a fight; raiders fly in groups, evade when chased, and still make attack runs | H | P7, P8 |
| AC16 | Rams: bumps feel harmless, hard hits hurt, head-ons kill; nothing tunnels visibly | H | |
| AC17 | Instructor: the route is easy to follow, the waypoint marker reads, every demo is clearly visible from behind | H | P6 |
| AC18 | Allied Starfuries (LOD1) look right at combat ranges; a Starfury break-up shows its cabin and four arms tumbling apart | H | P5 |
| AC19 | 60 fps at 1080p on the tester's GPU with four Starfuries, nine raiders, bolts, explosions and debris on screen | H | |

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
| M3-T12 | Integration, smoke runs, capture set, play-test guide | T01-T11 | Opus |

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
    Starting values (tune in (H)): safe 5 m/s for every ship; lethal 30 m/s for the Starfury, 25 m/s for the raider.
  - **Ship-ship at ordinary speeds**: Jolt resolves the bounce. Enable `contact_monitor` with a few reported contacts on
    ships; `RamResolver` keeps every active ship's velocity from its previous run and, for a pair whose contact began
    since then, takes Δv = |v_now - v_prev| minus what the ship's own thrust could have added in that time.
  - **Tunnelling speeds and buoys** (closing speed × dt over half the smaller `core_radius`, or no physics body): a
    target-relative swept test like `HitResolver`'s, the other body's origin against this body's shapes inflated by the
    other's `core_radius`. A hit at tunnelling speed destroys both (damage = `hull_max`, cause `ram`); a buoy ram uses
    the momentum split `Δv_self = v_rel × m_other / (m_self + m_other)` (buoy mass from its spec, about 2 t).
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
  `tests/integration/{test_ally_pool,test_starfury_breakup}.gd`.
- Notes:
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

- Goal: an instructor who leads a route and shows the moves the M7 tutorial will check (maintainer Q5).
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
  test_dogfight,test_m3_sandbox}.gd`.
- Notes:
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
- Done when: AC12 and the guard part of AC9 pass; P8 attached.

### M3-T11 HUD: wing roster, acknowledgements, waypoint marker

- Goal: the player can see the wing and the route at a glance.
- Agent: **Sonnet**. Layout from a pure model, as in M2-T08.
- Files: `src/hud/{hud_layout,hud_frame,hud_input,hud}.gd`, `src/game/main.gd` (`_build_hud_input`), `tests/unit/test_hud_layout.gd`,
  `tests/integration/test_hud.gd`.
- Notes: green line theme. **Roster** top-left: one row per wing member (callsign, a hull bar in the faction colour,
  the behaviour or order in short form: `FORM`, `ATK RAIDER 3`, `EVADE`, `DOWN`). **Acknowledgement** line under the status
  line for 3 s. **Waypoint marker**: a diamond with `NAV n` and range at the projected route point, an edge arrow when
  off-screen. Allies already show blue in the radar and target box (`Factions.hud_color`). Chase-view layout and opacity
  as in M2.1.
- Done when: the HUD parts of AC10 and AC11 pass; P6 and P7 show them.

### M3-T12 Integration, smoke runs, capture set, play-test guide

- Goal: M3 complete in one build, every (A) criterion green, the maintainer handed a checklist and screenshots.
- Agent: **Opus**. Cross-task glue.
- Files: `scripts/run_tests.sh` (providers line, new smoke runs: wing order, dogfight, instructor route), `scripts/capture_m3.sh`,
  `tests/integration/test_m3_run.gd`, `docs/playtest.md` (M3 section: keyboard, orders, instructor, new console commands,
  AC14-AC19 checklist), this file (status, as-built notes), `docs/architecture.md` §16 (as built), `docs/roadmap.md`.
- Done when: every (A) criterion passes; the capture set is attached; the maintainer runs the (H) checklist.

## As-built notes

(Implementation agents record deviations from §16 and this file here, per task.)

## Definition of done (M3)

- T01-T12 merged into `m3`, `scripts/run_tests.sh` green, `docs/third-party.md` current, no generated binaries committed.
- Every (A) criterion passes.
- AC14-AC19 ticked by the maintainer, with GPU, driver and FPS recorded below. Then `m3` merges into `main`.

Human acceptance record (fill in):

```
Tester:                                  Date:
OS / kernel / Mesa or driver:            GPU:
Splat backend shown:                     FPS with 4 Starfuries + 9 raiders + effects:
AC14 [ ]  AC15 [ ]  AC16 [ ]  AC17 [ ]  AC18 [ ]  AC19 [ ]
Notes:
```
