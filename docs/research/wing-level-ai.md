# Wing-level AI: what deciding per wing would save at 300 and 500 ships (M4-T32, Q46)

Research and a proposal for checkpoint 3, written 2026-11-05 on `m4` at `08228cc` (phase 2 merged: T15 to T20, T31). No game
code changed; the timing hook used for the split was a throwaway patch (described in section 3) and is not committed.

## 1. Summary

The maintainer asked how much the AI would save at 300 to 500 ships if the wing picked targets, tactics and engagements a few
times a second and each member only steered, avoided and aimed every tick, as RTS squads, Total War's units and X4's
low-attention fleets do, and what that would do to the feel of a dogfight.

Measured on the `battle` layout with the native brains and threads of T17 and T18, the answer is that the decisions a wing could
make once are already almost free. A native think costs about 13 us on one thread. Of that, 0.1 us is the context split
(friends, hostiles, leader), 0.4 us is the scoring and selection of the nine behaviours (the attack score's loop over the
hostiles is the target choice), 0.3 us is the behaviour in control (steering, aim, the trigger) and 0.3 us is the avoidance
filter. The other 12 us are the perception queries every member must run for itself: the nearest contacts (4.4 us), the
nearest rocks and mines (5.7 us), the incoming fire (1.5 us) and the broadcasts (0.3 us). Around the native think sits about 23 us
of GDScript per thinking ship in the driver, the facade and the command path, which no wing-level decision reaches.

So the three wing-level options save between 0.05 and 0.3 ms a tick at 300 ships and 0.07 to 0.5 ms at 500, out of a think
stage of 3.6 and 5.9 ms and a tick of 18.3 and 31.6 ms (one thread). The two levers the same measurement points at are
worth ten times more: moving the native pilots' inputs and commands into the core's rows (about 2.0 ms at 300, 3.4 ms at 500)
and sharing or caching the perception queries per cluster of ships (about 0.7 ms at 300, 1.2 ms at 500 on one thread).

Recommendation: do not build wing-level decisions in M4 as a performance task. Build the rows-based command path (a T18
follow-up) and a cluster-level perception (which T22's tier brains can reuse) instead, and keep wing tactics for a later
milestone as a feel feature, designed as option B below, with the wing deciding targets and tactics and the members keeping
the hit reaction, the manoeuvres and the avoidance. Confidence 85 % in the measured split, 80 % in the recommendation.

## 2. What the game's AI does today

- **One brain per fighter.** `AiPilot` (architecture §16 D34) scores nine behaviours every think, weighted by the pilot's
  `AiProfile`, with stickiness, a minimum dwell and an emergency margin; the winner flies the ship. Attack picks its own target
  inside its score (nearest, closing, attacking a friend, damaged, the kept target's bonus); evade reads the threats (a hostile
  on the tail, incoming fire, a recent hit) and the hit reaction hands control to evade after the pilot's reaction time (D40).
- **Wings exist but do not think.** `Wing` and `WingDirector` (D36) hold a leader, slots and an order (engage at will, attack my
  target, form on me, cover me). Every tick the director writes the wing's view into each member's `AiContext` (order, leader,
  the leader's target, slot offset, wingmates, the leader link), and the member's own scoring gates itself through
  `AiContext.may_attack`. The wing has no decision of its own; the order is the player's or the scenario's, and an AI-led wing
  only hands the lead down when the leader dies. `BehaviourRally` brings a wing ship back to an engaged wingmate.
- **The think rate** (T04, §17.4): a fighter within 2 km of the player thinks every tick, the rest at 20 Hz on staggered ticks
  and hold their command between. Holding the command, not the decision, was measured and accepted in cycle 3.
- **Native brains and threads** (T17, T18, §17.13): the whole think of a fighter runs in `ScsBrains` over the core's rows, every
  think of a tick in one `think_batch` call across the pool from 48 thinks up. The GDScript driver still builds a lite perception,
  prepares the slot, joins the batch, unpacks the output and applies the command through `Combatant.apply_commands`.
- **The bench has no wings.** The `battle` and `typical` layouts spawn every fighter as a lone pilot engaging at will (the `wing`
  field is empty; only `transit` flies wings of four). A wing-level design would need wings in the layout before its saving
  could be measured on the headline numbers.

## 3. The measured cost split

### 3.1 Method

A throwaway timing hook (`std::time::Instant` around five sections of `Brain::think` in `native/src/brain_behaviours.rs`, the
list picking split into its four queries, sums per worker and a print every 300 batches from `ScsBrains.think_batch`), built
with the worktree's own cargo target directory and run with `bench <layout> <n> 15 warmup=5 seed=1`, editor build, headless,
pinned to cores 0 to 11, under `flock /tmp/m5-godot.lock flock /tmp/scs-bench.lock`, load 1.1 to 1.4. Nine clock reads a think
cost about 0.2 us, under 2 % of the native think. Raw logs and summaries are under `reports/perf/M4-T32_split*` (not
committed); the patch is kept beside them as `t32-timing-hook.patch`. Means over the three five-second windows of each run.

### 3.2 Where a native think's time goes

| run (one thread) | thinks a tick | native think, us | nearest k | statics | incoming fire | broadcasts | context | scoring and selection | behaviour (steer, aim, fire) | avoidance |
|---|---|---|---|---|---|---|---|---|---|---|
| battle 300 | 88 to 90 | 12.9 to 13.3 | 4.4 to 4.5 | 5.7 to 5.8 | 1.5 to 1.6 | 0.26 | 0.10 | 0.41 to 0.43 | 0.34 to 0.35 | 0.27 to 0.28 |
| battle 500 | 145 to 146 | 12.4 to 13.0 | 4.2 to 4.4 | 5.1 to 5.4 | 1.5 to 1.7 | 0.34 to 0.36 | 0.10 | 0.40 to 0.43 | 0.31 to 0.32 | 0.27 |
| typical 58 | 20 to 23 | 15.2 to 15.6 | 5.0 to 5.1 | 8.0 to 8.3 | 0.7 to 1.1 | 0.13 to 0.14 | 0.10 | 0.25 to 0.38 | 0.44 to 0.48 | 0.28 to 0.32 |
| furball 100 (no rocks) | 47 to 54 | 4.4 to 6.0 | 1.7 | 0.7 | 0.9 to 2.5 | 0.09 | 0.09 | 0.27 to 0.33 | 0.40 to 0.44 | 0.21 |

Per batch (one native call a tick): `battle` 300 1.37 to 1.44 ms, of which the grid and the tick's field 0.18 to 0.21 ms serial;
`battle` 500 2.15 to 2.28 ms (grid 0.27 to 0.29); `typical` 0.39 to 0.45 ms (grid 0.08 to 0.09). With six threads the batch
falls to 0.54 to 0.59 ms at 300 and 0.87 to 0.93 ms at 500, while each think's own wall time rises to 15 to 16 us (the workers
share the memory bus; the grid stays serial).

Reading the table:

- **The decisions are a thirtieth of the native think.** Context plus scoring and selection, which is where a target is chosen
  and a behaviour picked, cost 0.5 us a think. Steering, aim, the trigger and avoidance cost another 0.6 us. Everything else is
  perception: 11 to 12 us of grid queries a member runs for itself.
- **The rocks dominate the perception.** The statics query costs 5 to 8 us wherever the asteroid slab is in range (`battle`
  and `typical` carry 1 000 rocks; the query pads its search by the largest rock and ranks every rock whose surface is within
  5 km), and 0.7 us where there are none (`furball`). The nearest-k query costs 4 to 5 us in the battle (every fight is a ball of
  24 inside the 5 km range, so the partial selection runs) and 1.7 us in the furball of 100.
- **The cost per think does not grow with N.** From 300 to 500 the native think stays at 13 us; the think stage grows with the
  number of thinking ships (88 to 146 a tick), as the think rate intends.

### 3.3 The GDScript around the native think

The think stage is the drivers' steps plus the batch call. Taking the batch out leaves the GDScript:

| run (one thread) | think stage, ms | batch, ms | held ships' early returns, ms (T18's estimate) | GDScript left, ms | per thinking ship, us |
|---|---|---|---|---|---|
| battle 300 | 3.64 | 1.40 | about 0.2 | about 2.0 | about 23 |
| battle 500 | 5.95 | 2.2 | about 0.35 | about 3.4 | about 23 |
| typical 58 | 0.98 | 0.42 | about 0.05 | about 0.5 | about 24 |

The same 23 us at every size: the lite perception's property reads, the slot's context check, joining the batch, the command
objects, the selection and `apply_commands`. T18 put it at about 27 to 30 us from GDScript section timers, which carry their own
overhead; the batch it put at 0.55 ms at 300 from the console's `core.batch_us`, a last-tick readout taken after the bench, where this
hook's batches inside the window run 1.25 ms at the least, 1.34 to 1.39 at the median and 1.45 to 1.48 at the 90th percentile
(none declined), and the same run's console readout after the bench still says 0.57 ms (`reports/perf/M4-T32_split/verify2.log`). The think stage
totals agree with T18's (3.6 ms at 300 on one thread); only the attribution moves: the native call carries about 40 % of the
think, the GDScript about 55 %, the held ships the rest.

### 3.4 What a wing could compute once, and what each member must still do

| part of a think | us a think (battle 300, one thread) | wing could do it once? |
|---|---|---|
| context split (friends, hostiles, leader) | 0.10 | yes, per wing (the hostiles of a fight are the same for its members) |
| scoring and selection (target choice, behaviour choice) | 0.42 | yes, with a per-member override for the hit reaction, retreat and ram |
| threat reading inside evade's score (the tail check over the hostiles) | inside the 0.42 | partly: who is shooting is shared, whether it is on my tail is mine |
| incoming fire query (bolts that will pass near me) | 1.5 | no: bolts aimed at me are mine |
| nearest-k contacts | 4.4 | partly: a wing can share the fight's candidate list, each member still needs its own nearest few for avoidance and the fire lane |
| nearest statics (rocks and mines) | 5.7 | no, but it is cacheable per ship (rocks do not move) |
| broadcasts | 0.26 | yes |
| behaviour in control (steering, aim, trigger) | 0.34 | no |
| avoidance and the re-seek | 0.27 | no |
| GDScript driver, facade, command path | about 23 | no: it is paid per thinking ship whatever decided the command |

Strictly wing-shareable: about 0.8 us of 36 us all in (2 %). With a shared candidate list for the nearest-k query: about 3 us
(8 %). Nothing a wing decides removes the GDScript per member; only a member that does not think at all (a held tick, or a
tier row) saves that, and the think rate already does that for far ships.

## 4. How other games split the decisions

The games the maintainer named, and the squad-AI designs the industry documented best, all keep the same shape: a group layer
chooses objectives, targets or tactics on a slow cadence, and every unit keeps its own perception, steering, aim and
self-preservation every frame. None of them documents a saving from the split; where cost is discussed, it sits in the per-unit
work (projectiles, pathing, perception), as here.

| game | group layer | unit layer | cadence | source |
|---|---|---|---|---|
| Killzone 2 multiplayer bots (Guerrilla) | one commander per faction picks objectives and divides bots into squads; squad leaders plan regroup, attack and defend with an HTN planner | each bot keeps its own HTN planner, perception and self-preservation; orders carry a priority, and an individual dodging a grenade overrides a squad order | individuals replan five times a second, squads twice a second | Verweij, VU Amsterdam thesis, hosted by Guerrilla (verified from the PDF text) |
| F.E.A.R. (Monolith) | a global coordinator re-clusters AI into squads by proximity; four simple squad behaviours (get to cover, advance cover, orderly advance, search) find participants, send orders and monitor each tick | every agent plans for itself with GOAP and decides whether to follow an order or flee; no complex squad behaviours existed, the complex look emerges from the two layers | the squad monitors every clock tick; agents plan when goals change | Orkin, GDC 2006 paper (verified from the PDF text) |
| Halo 3 (Bungie) | an objective tree of prioritised, self-describing tasks; squads trickle down to the highest open task; distribution is O(n) in the tasks | each actor's behaviour tree fights inside the task | tasks re-evaluated on activation and completion | Isla, GDC 2008 slides (verified from the PDF text) |
| Total War (Creative Assembly) | a battle AI reasons by unit type and group goals; Warhammer's siege AI has a grand tactical analyser handing objectives to detachments and tactics to units | the unit is the agent (Shogun used per-unit neural nets for formation movement and evasion); every soldier's projectile is physically simulated, and that cost is managed en masse | not published | Thompson's series on Game Developer (parts 1, 2, 5); Pitkethly on Warhammer II (interview) |
| Homeworld 2 (Relic) | squadrons are the command unit (five strike craft built and ordered as one); strike groups are formations of squadrons; tactics settings (aggressive, defensive, evasive) | ships fly the squadron's formation and retaliate by the tactics setting | per order | Well of Souls tech briefing quoting Relic's designers |
| Supreme Commander and Forged Alliance (GPG, FAF) | the AI forms platoons from built units and orders the platoon (attack vector, patrol, retreat); builders and platoon templates in Lua | the engine's unit AI aims, fires and paths on its own | platoon threads on Lua waits of seconds | FAF wiki and forums (community documentation of the shipped Lua) |
| Planetary Annihilation (Uber, Sorian) | a neural network per platoon decides attack, retreat and target from threat values | units fight with the engine's targeting | not published | Sorian's forum posts, summarised by search results only (the forum refused the fetch; not verified in full) |
| Ashes of the Singularity (Stardock, Oxide) | meta-units: grouped units aware of each other, short-ranged ones screen long-ranged ones, repair units help the most damaged | every unit keeps its own weapons and ballistics | not published | Stardock's announcement article (verified) |
| StarCraft II (Blizzard) | the melee AI sends attack waves (a composition, a staging point, a target); the tactical AI data decides per unit when to use abilities | per-unit targeting and movement in the engine | the editor caps the AI's actions per minute (200 by default) | SC2Mapster editor tutorial (community documentation) |
| Age of Empires II (Ensemble) | attack groups sized by strategic numbers are sent at a target | units retaliate and pick targets themselves | per rule tick | AoE2 AI scripting community (not a primary source) |
| X4: Foundations (Egosoft) | not a hierarchy but an attention level of detail: high attention near the player (fully simulated), low attention elsewhere with precision and update rate reduced, combat resolved with fewer checks (a developer confirms the terms are the old OOS and IS) | full per-ship AI in high attention | by attention, not by group | Steam discussion with an Egosoft developer; Egosoft 6.00 notes name "low attention combat simulation" |
| EVE Online (CCP) | the Sleepers' "Level One" AI picks the most threatening targets as a group and switches targets; AI templates derive from it | each NPC flies and fires itself | per server tick | CCP dev blogs 2009 and 2012 (verified) |
| FreeSpace 2 (Volition, FS2 Open) | mission and player goals are issued to wings and copied to each ship (`ai_add_wing_goal_*`, `ai_attack_wing` picks one member of the enemy wing per attacker) | each ship's `AIM_CHASE` and its sub-modes; the target is re-evaluated on a per-skill timer of 0.5 to 5 s (`get_enemy_timestamp`), formation slots are flown every frame | per-ship timers; wing goals at mission events | FS2 Open source (`aigoals.h`, `aicode.cpp`, verified) |
| Craig Reynolds, steering behaviours | action selection | steering, locomotion | not stated | GDC 1999 paper (verified) |

What the survey says for this game:

- **The per-member loop is never removed.** Every design keeps perception, steering, aim and the dodge on the unit, every
  frame. Killzone's and F.E.A.R.'s point is that the individual's self-preservation must override the squad, which is this
  game's hit reaction (D40) and avoidance (D33).
- **The group layer is slow by design.** Two decisions a second (Killzone squads), a target hold of half a second to five
  seconds by skill (FreeSpace 2), one attack wave at a time (StarCraft II). That cadence is where the feel of "a wing fighting
  together" comes from, not a saving.
- **Cost, where it is named, is in the units.** Total War simulates every soldier's shot and manages the requests "en masse";
  Ashes keeps every unit's weapons; X4 saves by lowering the whole simulation's rate and precision away from the player, which is
  this project's think rate (T04) and tier (T21, T22), not a wing.
- **Focus fire is the feel change.** EVE's Sleepers switching to the most threatening target as a group is what players
  remember of that AI; against a lone player, a raider wing of twelve concentrating fire is a different game from twelve pilots
  each choosing the nearest.

## 5. Design options

Each option keeps the member's `AiPilot` as the thing that flies the ship every think, keeps the hit reaction, retreat, ram and
avoidance per member, and adds a wing decision on a slow beat. The saving is per thinking ship at `battle` 300 (89 thinks a
tick) and 500 (146), one thread; with six threads the native part divides by about 1.8 and the GDScript part does not.

### Option A: the wing assigns targets

- **What the wing decides,** at about 4 Hz (every 15 ticks, staggered per wing): a target per member from the fight's hostiles,
  spreading members over targets (two per target as a default), keeping an assignment while it lives and is in range, with a
  switch bonus like today's `ATTACK_KEEP_BONUS`. The member's attack score takes the assigned target as its only candidate
  (as `ATTACK_MY_TARGET` does today) and falls back to its own loop when the wing has none.
- **What changes:** `Wing` gains a seeded target table and a beat; `WingDirector` runs the assignment in its tick (or a native
  `ScsWings` pass once a tick over the rows, since the hostiles are in the rows already); `AiContext` gains `assigned_target_id`;
  `AiPilot`'s attack score and its native twin take it; the tier (T21, T22) assigns the same way for tier rows and resolves fire
  against the assigned target, which it needs anyway.
- **Saving:** the attack loop over the hostiles, about 0.3 us a think: **0.03 ms at 300, 0.04 ms at 500** (under 1 % of the
  think stage). A wing pass costs about 10 to 30 us per wing per decision, so at 64 wings of 4 at 4 Hz about 0.1 ms a tick is
  added; the net is zero or slightly negative.
- **Feel:** better: wingmates stop piling on one raider and leaving the rest free, and ATTACK MY TARGET can spread the wing over
  the target's escorts later. Risk: a wing of twelve raiders focusing the player feels like a gank; the spread rule and the
  profile's aggression should cap how many take the same target.
- **Tests:** the Q16 tolerance test compares native and GDScript twins; an assignment table must run on both paths (GDScript
  reference, native twin) or the test is rebuilt; seeded outcomes change (a behaviour change for the report, as T04's was).

### Option B: the wing decides targets and tactics

- **What the wing decides,** at 2 to 4 Hz: the target per member (as A), the wing's stance (engage, press, disengage and
  regroup, cover the leader, form up) from the fight's balance (hostiles against members, hull left, incoming missiles), and a
  pass type per member (standard run, slashing pass, drag toward a wingmate). The member's scoring keeps ram, retreat, evade
  and the hit reaction above the wing's stance, as Killzone's priority orders and F.E.A.R.'s goals do; the stance sets the
  weights of attack, formation and rally for the beat.
- **What changes:** as A, plus a wing brain (pure, `RefCounted`, seeded, with a native twin in `brain_behaviours.rs` or a wings
  pass of its own), stance words in `AiContext` beside the order, the attack behaviour's run roll taking the wing's pass type
  (D42's roll becomes the fallback), and the console's `wing` provider showing the stance. The tier's brains (T22) run the wing
  brain per tier wing at 2 to 5 Hz instead of a brain per fighter, so a tier wing of 12 costs one decision, not 12.
- **Saving:** context plus scoring and selection, about 0.5 us a think, **0.05 ms at 300, 0.07 ms at 500**; if the wing's
  candidate list also replaces the member's nearest-k hostiles (the member keeps a nearest-4 for avoidance and the fire lane),
  about 2 to 3 us more: **0.2 to 0.3 ms at 300, 0.3 to 0.5 ms at 500** (5 to 8 % of the think stage, 1 to 1.5 % of the tick).
  In the tier (T22) the saving is real in proportion but tiny in absolute terms (the tier budget is 0.3 us a fighter).
- **Feel:** this is the option that changes how fights look: wings that regroup when outnumbered, bracket a target, and break
  off together. Risk to the dogfight: a stance that flips every beat (needs hysteresis, as `stickiness` and `min_dwell_s` give a
  member today); members pulled off a kill by a regroup; AC12's balance (rookies beating the sandbox wing) would be retuned
  from scratch.
- **Tests:** as A, plus the wing brain's own seeded tests and a wing-against-wing outcome test (two wings of four, seeds 1 to
  3, hits and the winner pinned within a tolerance), and `test_ai_think_rate`'s pins move (the stance changes who attacks).

### Option C: full squad behaviours

- **What the wing decides:** everything but the ship's reflexes: manoeuvres as wing plays (pincer, drag and bag, high and
  low pass) with members as slots that fly to assigned points and fire windows, as F.E.A.R.'s squad behaviours fill slots.
  Members keep avoidance, the hit reaction and the fire gate.
- **What changes:** a wing behaviour set beside the member behaviours, slots and timing in `Formation`, the member's attack
  behaviour replaced by a "fly my slot, fire in my window" behaviour while a play runs, the tier unable to run plays (it has no
  per-tick steering) and falling back to B's stance.
- **Saving:** none; the members still think every tick (steering to a moving slot is the same work as steering to a lead
  point), and the wing's plays add a decision per wing per beat. **About 0 ms at 300 and 500, possibly +0.1 ms.**
- **Feel:** the largest change and the largest risk: plays that look great against a drone and fall apart against a human who
  does not fly where the play assumed; the slashing pass (D42) already gives a convincing pass. This is a design milestone of
  its own, with the maintainer judging feel (H), not a performance task.
- **Tests:** the seeded fights change entirely; Q16's tolerance as written (native against GDScript twins) stays satisfiable
  only if both paths carry the plays.

### The two levers the measurement points at instead

- **L1: the native pilots' inputs and commands as rows** (the next step T18 named). The hits, the selection and the clock are
  read into the rows at the sync; the batch writes each pilot's flight and combat command into its row; the flight step applies
  it; the driver does nothing for a native ship but count. **About 2.0 ms at 300 and 3.4 ms at 500** (55 % of the think stage,
  11 % of the tick), the same on one thread and six. Feel: none (the same commands a tick later in the same tick). Tests: the
  parity files already pin the commands; the fallback (a declined think) needs a rows-side hold.
- **L2: perception per cluster, statics cached.** One nearest-k and one statics query per cluster of nearby thinking ships
  (a wing, or a grid cell's worth of ships: the fight), each member then ranking the cluster's candidates (a few hundred
  nanoseconds) and running only its own incoming-fire query; the statics list refreshed only when the ship has moved more than
  a cell or every tenth think, since rocks do not move. **About 8 us a think: 0.7 ms at 300 and 1.2 ms at 500 on one thread,
  0.4 and 0.65 with six.** Feel: none if the candidate set is a superset of today's (the cluster's range is the sensor range
  plus the cluster's radius). Tests: `test_nearest_contacts` and the brain parity need the candidate set to contain today's
  nearest k; bit-for-bit parity holds when the member ranks the superset the same way. This is the one piece of a "wing-level"
  design that pays, and T22's tier brains need exactly this (one perception per far fight).
- **L3: the grid built once a tick** for the scan, the stand-ins and the brains (0.18 ms at 300, 0.27 at 500, serial today in
  the batch; the scan builds its own).

| lever or option | saving at 300, ms (one thread, six) | at 500 | share of the think stage at 300 |
|---|---|---|---|
| A: targets per wing | 0.03, 0.02 | 0.04, 0.03 | under 1 % |
| B: targets and tactics per wing | 0.05 to 0.3, 0.03 to 0.2 | 0.07 to 0.5, 0.04 to 0.3 | 1 to 8 % |
| C: full squad behaviours | 0 or worse | 0 or worse | 0 |
| L1: commands as rows | 2.0, 2.0 | 3.4, 3.4 | 55 % |
| L2: cluster perception, statics cached | 0.7, 0.4 | 1.2, 0.65 | 20 % |
| L3: one grid a tick | 0.2, 0.2 | 0.3, 0.3 | 5 % |

## 6. Risks

- **To the dogfights' feel.** The member-level pieces that make a fight feel like pilots are all in the per-tick path and must
  stay there: the hit reaction and the locked jink (D40), avoidance (D33), the slashing pass and the lead tracking (D42), the
  ram (D41). Any wing layer sits above them, as every surveyed game does. The feel risks are at the wing layer: focus fire that
  feels unfair, stance flapping, members pulled off kills, plays that break against a human. The maintainer's test of feel (H) is
  the dogfight scenario with wings RED and BLUE and the player's ALPHA.
- **To the seeded tests and Q16.** The brains' parity rests on a GDScript reference and a native twin thinking the same bits;
  a wing layer either exists on both paths (twice the work, as T17 paid) or is native only with its own seeded pins and the
  Q16 test rebuilt around it. Any wing decision changes seeded outcomes, so it is a listed behaviour change with new baselines,
  not a port; AC13's paired budget must still hold (a wing pass adds a little GDScript per wing per beat).
- **To the measurement itself.** `battle` and `typical` spawn no wings; giving the layouts wings of four (the setting's patrol)
  or twelve (its squadron) changes the fights' shape and the baseline before any saving shows. The bench numbers for options
  A to C above are projections from the per-think split, not before-and-after runs.
- **To T21 and T22.** A wing-level split helps the tier most as a way to run fewer brains, but its real need is L2's cluster
  perception; building B before T21 would delay phase 3 for a saving the tier's own cadence already gives.

## 7. Recommendation

1. **Do not build wing-level AI in M4.** The decisions a wing could make once are 2 % of a thinking ship's cost; options A and
   B save 0.05 to 0.5 ms where the think stage is 3.6 to 5.9 ms and the tick 18 to 32 ms. Confidence 80 % (the 20 % is the
   chance that giving the bench wings changes the fights enough to move the near count or the hostile lists in ways this split
   does not show).
2. **Take L1 and L2 as M4 tasks** in T21's wave or as a T18 follow-up: commands as rows (about 2 ms at 300, 3.4 at 500) and
   cluster perception with cached statics (0.7 and 1.2 ms on one thread). Together they bring the think at 300 to about 1 ms
   on one thread, under T17's 2 ms target, and T22's tier brains inherit the cluster perception. Confidence 75 % in the
   projections (they rest on this split and on T18's held-ship estimate).
3. **Keep option B as the design for wing tactics in a later milestone** (M5's missions or the roadmap's AI milestone), judged
   on feel at an (H) checkpoint with the dogfight scenario, built as a seeded wing brain with hysteresis above the members'
   reflexes, with the hit reaction, avoidance, ram and retreat never overridden. Option A is its first step and can ride on
   `WingDirector` alone.
4. **Correct the T18 attribution in the milestone's record:** the native think is about 13 us in the battle (perception 12,
   decisions 0.5, flying 0.6), not 6, and the GDScript per thinking ship about 23 us, not 30; the two together are what T18
   measured as the think stage.

## 8. Sources

Repository, read 2026-11-05 on `m4` at `08228cc`: `docs/milestones/m4-performance-and-scale.md` (Q8, Q16, Q46, T17, T18, T21,
T22, T32 and their Cycle log entries), `docs/architecture.md` (§16, §17.4, §17.13), `src/ai/` (`ai_pilot.gd`, `ai_pilot_driver.gd`,
`ai_context.gd`, `wing.gd`, `behaviour_*.gd`), `src/game/wing_director.gd`, `src/perf/brain_batch.gd`, `src/perf/bench_layout.gd`,
`native/src/brain.rs`, `brain_behaviours.rs`, `kernels.rs`; measurements under `reports/perf/M4-T32_split*`.

Primary and close-to-primary sources (fetched 2026-11-05 unless marked):

- Guerrilla Games, "A Hierarchically-Layered Multiplayer Bot System for a First-Person Shooter" (Verweij, VU Amsterdam, the basis
  of Killzone 2's bots): https://www.guerrilla-games.com/read/a-hierarchically-layered-multiplayer-bot-system-for-a-first-person-shooter
  and the PDF https://www.guerrilla-games.com/media/News/Files/VUA07_Verweij_Hierarchically-Layered-MP-Bot_System.pdf (replan
  rates in section 3.2.4; the three layers in chapter 4).
- Jeff Orkin, "Three States and a Plan: The AI of F.E.A.R.", GDC 2006: https://pages.cs.wisc.edu/~dyer/cs540/handouts/gdc2006_orkin_jeff_fear.pdf
  (the "Squad Behaviors" sections).
- Damian Isla, "Building a Better Battle: The Halo 3 AI Objectives System", GDC 2008, slides: https://web.cs.wpi.edu/~rich/courses/imgd4000-d09/lectures/halo3.pdf
- Tommy Thompson, "The AI of Total War", Game Developer: part 1 https://www.gamedeveloper.com/programming/the-road-to-war-the-ai-of-total-war-part-1- ,
  part 2 https://www.gamedeveloper.com/design/evolution-of-war-the-ai-of-total-war-part-2- , part 5
  https://www.gamedeveloper.com/design/war-hammer-the-ai-of-total-war-part-5- ; Scott Pitkethly on Warhammer II's entities and
  projectiles: https://www.gamedeveloper.com/design/designing-i-total-war-warhammer-ii-i-to-handle-tons-of-units-and-massive-battles ;
  Andre Arsenault, "Have Fun Storming the Castle! Siege Battle AI in Total War: Warhammer", GDC 2016 (abstract only):
  https://gdcvault.com/play/1023363/contactUs
- Homeworld 2, "Tech Briefing: Command & Control" (Relic designers quoted): https://well-of-souls.com/homeworld/hw2/tech_control.htm
- Supreme Commander: Forged Alliance AI (platoons, builders), FAForever wiki and forums: https://wiki.faforever.com/Development/AI/AI-Modding ,
  https://wiki.faforever.com/Development/Missions/Mission-Scripting , https://forum.faforever.com/post/18139 (the wiki and forum
  pages refused the fetch; their content is taken from search summaries and is not verified in full).
- Planetary Annihilation, Sorian's forum posts on the platoon neural network: https://forums.planetaryannihilation.com/goto/post?id=1019120 ,
  https://forums.planetaryannihilation.com/posts/1069219 (refused the fetch; search summaries only, not verified).
- Ashes of the Singularity, Stardock, "Don't fight a battle, win the war" (meta-units): https://www.stardock.com/games/article/462158/ashes-of-the-singularity-dont-fight-a-battle-win-the-war
- StarCraft II editor AI (attack waves, tactical AI data): https://sc2mapster.wiki.gg/wiki/Tutorials/Artificial_Intelligence ;
  James Anhalt's GDC 2011 navigation session exists but was not reachable (community notes only).
- Age of Empires II attack groups (community AI scripting reference, not primary): https://airef.github.io/ and
  https://forums.ageofempires.com/t/three-ways-to-get-the-ai-to-attack/205476
- X4: Foundations attention levels: Steam discussion with an Egosoft developer https://steamcommunity.com/app/392160/discussions/0/6664812048260991709 ;
  Egosoft 6.00 announcement naming "low attention combat simulation" https://www.egosoft.com/news/archive/2022December_en.php
- EVE Online, CCP dev blogs: "When Evolution Leaps Forward" (2009) https://www.eveonline.com/news/view/when-evolution-leaps-forward ;
  "Brains! NOM NOM!" (2012) https://www.eveonline.com/article/brains-nom-nom
- FreeSpace 2 Open source: `aigoals.h` https://sources.debian.org/src/freespace2/24.0.2%2Brepack-1/code/ai/aigoals.h ;
  `aicode.cpp` https://raw.githubusercontent.com/scp-fs2open/fs2open.github.com/master/code/ai/aicode.cpp (`find_enemy`,
  `get_enemy_timestamp`, `ai_attack_wing`, `ai_form_on_wing`).
- Craig Reynolds, "Steering Behaviors for Autonomous Characters", GDC 1999: https://www.red3d.com/cwr/steer/gdc99/
- Champandard, Dunstan, Jack, "Believable Tactics for Squad AI", GDC 2012 (abstract: centralized against distributed squad
  designs): https://gdcvault.com/play/1015665/Believable-Tactics-for-Squad
- AI level of detail as a technique: Brockington, "Level-of-detail AI for a large role-playing game", AI Game Programming
  Wisdom (2002), and Brom, Poch, Šerý, "AI Level of Detail for Really Large Worlds", Game Programming Gems 8 (2010): both cited
  from secondary listings, not read.
- A hobbyist dogfight AI write-up on manoeuvre sets and "space jousting" (not primary): https://ibgoge.itch.io/wing-mercenaries/devlog/718838/recapturing-the-golden-era-of-dogfighting-behind-the-scenes-of-squadron-mercenaries-space-combat-ai

Not found: a Blizzard talk on StarCraft II's melee AI internals, a Creative Assembly statement on battle AI update rates, an
Egosoft document on the low-attention combat formula, a Volition design document on wingman AI, and any published figure for the
CPU cost saved by a group layer in any of these games.
