# Roadmap

The next target after M1 is the **tutorial mission vertical slice**: launch from Babylon 5, an instructor teaches
the controls and gives an exterior tour, then raiders come through the jumpgate and you defend the station with
allies. Milestones M2-M8 build toward it; everything else follows it. Each milestone gets its own
`docs/milestones/` file when it starts, with a Status column in its task table (`CLAUDE.md`, "Milestone documents");
order and scope will change. Long-term design: `docs/architecture.md` §14.

## Path to the tutorial slice

| Milestone | Goal | Contents | Builds on (M1 hooks) |
|---|---|---|---|
| **M1 First Flight** | flyable Starfury (historical: its first hull renderer was replaced in M4) | see `m1-first-flight.md` | - |
| M1.5 Hull polish (historical, not needed) | hull quality | superseded: M3-T21 and T24 took the near-field work, and M4 made every hull a textured mesh | - |
| M2 Combat sandbox | something to shoot | see `m2-combat-sandbox.md`: generated `raider_fighter` (Delta-V) with break-up chunks; raiders are real `Ship`s flown by simple `PilotBrain`s (idle, patrol, attack runs); target-relative swept hit detection per tick; hull damage (`god` protects the player), generated explosions and debris; pools so nothing hitches; minimal HUD (velocity vector, lead reticle, target box with hull, own hull); `combat_sandbox` waves; control profiles (saved binding sets, console-driven); generated SFX if it fits (else M3) | `TargetingSystem` + `Targetable.faction`, `PulseCannonGate`, kinematic projectiles, `DebugFlags`, `tools/procgen` parts/styles (new `raider` style) |
| M3 AI pilots and wingmen | others who fly | see `m3-ai-pilots-and-wingmen.md`: `AiPilot extends PilotBrain`: utility selection over attack, evade, formation, follow path, guard; collision avoidance and ram damage; faction relations as data (M2 has a fixed rule); allies fight alongside you (Starfury break-up chunks); an instructor who flies a waypoint route; **level of detail and a visual pass** (maintainer, 2026-10-28, M3-T19..T25; its hull renderer, levels and budget were replaced in M4): a `LodSwitcher` by screen size; scene-lit hulls with a picker for the 8 lights; nozzle, muzzle-flash and explosion lights; `GPUParticles3D` sparks and debris; lens flare and motion blur after the maintainer signs off | M2's `PilotBrain`/`Perception`/`PilotSteering`/`AiPilotDriver`, `InterceptMath`, `Factions`, `Combatant`/`ShipAssembly`, pools; command split, `SimClock` |
| M4 Performance and scale | many ships at once | see `m4-performance-and-scale.md` (maintainer, 2026-10-28): find the most ships that fly at once with good performance (a headless tick budget at 60 Hz), at least 100 and up to 500; test-driven cycles on the ship AI and location tracking (contact scans, perception, targeting, radar, `UniversePos`, the rebase): measure, rank three candidate improvements by confidence, build the first, measure again; four cycles, then a report to the maintainer (under 100: ask for guidance). **Start from what M3 measured:** at 100 ships `TargetingController` takes about 63 of 87 ms per frame (M3-T20: one per ship, each scanning every contact), and with the visual pass 100 ships still run at 9 fps with one physics tick per frame and at about 1 fps with Godot's default of up to 8, while the GPU takes under 10 ms even with all 100 in view (M3-T12, `scripts/measure_m3.sh hundred`). The limit is the CPU tick, not the renderer. Even AC19's 13 ships spend about as long in the tick as on the GPU | `ContactScan` (shared per tick), `AiPilotDriver.think_us`, `WorldFrame.last_rebase_us`, `test_ai_think_time` (AC13), `RebaseFight`, `ShipPool` / ally pool, the console's `--console-exec` |
| M4 (added 2026-11-04) Textured meshes | textured meshes for every hull | every ship, station and capital as a procedurally textured polygon mesh (UVs and colour, normal, roughness and metal, emissive maps from `tools/procgen`); the M1 to M3 hull renderer and its addon removed (maintainer, M4 Q29); tasks T30 and T31 in `m4-performance-and-scale.md` | M4-T27's painted mesh path and `core/glb.py` exporter, M3's `LodSwitcher`, M4-T11's far dots |
| M5 Mission framework and front end | scripted play | see `m5-mission-framework-and-front-end.md` (planned 2026-11-02, beside M4): `Game` state machine, scenario + mission scripts (coroutine API), triggers, objectives (AI ships take a target through M3-T17's pilot objective, e.g. raiders sent at a buoy or the station from broadcast range), subtitles + comms panel (dialog lines as data: speaker, text, voice id), `CINEMATIC` camera mode, debrief, console commands to load a scenario and skip mission steps; front-end menu: free flight (random encounters on/off) or mission select; settings and controls menus (remapping on top of M2 control profiles); **sound pass** (maintainer, 2026-10-25): per-thruster engine bursts (each main pod and RCS jet sounds when it fires, placed on the ship), new Starfury and raider gun sounds and bolt impacts, all synthesised from the written reference in `docs/design-references.md` ("Combat sounds"); gun and impact sounds keep the two-octave-lower register M3-T15 set (2026-10-26); **civilian traffic** (maintainer, 2026-11-02): nine civilian hulls (the modular Saturn family: Saturn 3, Saturn 4 transport and tanker, Saturn 8 transport and tanker; the Skylark, the Narn transport, the Centauri Brezebel, and the Brakiri Bokmai with removable cargo pods) and free-flight encounters with raiders, allied patrols and civilians; one demo mission, Civilian escort (a random civilian from a nav beacon through a sparse belt of generated asteroids to a beacon 30 km away, three raider waves, one wingman; it replaced Buoy defence, 2026-11-08); the performance block from M4's review (L1, L2, L3, L5, L8, L9, L12, L13, L14) and the sound pass's L6 and L7 | `ScenarioLoader` + `data/scenarios/` (waves since M2), `World.spawn` from universe coordinates, `UiCommand`, camera mode enum, `ControlProfile` |
| M6 Epsilon space at true scale | the real neighbourhood | moving free-falling `WorldFrame` (the velocity rebase on; the position rebase is already on in play since M3-T14), restricted n-body gravity with Kepler-rail bodies (Epsilon star, Epsilon III, moons), scaled-space renderer (planet + atmosphere shader, sun), levels of detail for the station, jumpgate and planets (the importer's mesh levels and the far dots, M4; generated far levels where they earn their place), `jumpgate` asset with vortex effect; the jumpgate broadcasts to 1 000 km (radar, targeting and the AI beyond sensor range, as M3-T17's buoys); it replaces M4's gravity stand-in (`GravityStandin`, the benchmark's point-source moon at 400 km pulling 0.03 m/s^2 with no body or visual) with the Kepler bodies and true gravity. | `UniversePos`, `World.rebase`, `environment_accel`, brake `env_accel_b` feed-forward, the manifest's `mesh` section, procgen framework |
| M7 Babylon 5 station | the station | `babylon5_station` generator (~8 km: hub, rotating drum as `AnimatableBody3D`, launch bays, defense-grid emplacements as hardpoints), compound collision, launch-bay sequence with a cinematic launch camera, generated station interior for the front end; the station broadcasts to 1 000 km (M3-T17; the AI sees it at that range too, so a mission can send raiders at it) | procgen parts/styles and hardpoints contract, camera modes, `World` frame (station fits the local space) |
| M8 Tutorial vertical slice | the first mission | front end over the B5 interior -> launch from a bay -> subtitled instructor (voice comes with M15) checks each control (pods, retros, strafe, roll, assist, brake, targeting, fire modes) -> exterior tour pointing out the defense grid -> raiders arrive through the jumpgate vortex -> defend the station with allies -> debrief; Linux x86_64 release build with export templates | all of the above; tutorial checks read the same `InputMap` actions as M1 The release export opens its window since M4-T44: M4-T25 found the game reading five `.glsl` files as text that the export did not ship (four of ours and the lens flare's); our four are now kept as files and our export plugin (`addons/scs_export`) adds the flare's. |

## After the tutorial

| Milestone | Goal | Contents | Builds on |
|---|---|---|---|
| M9 Time warp and the solar system | go anywhere | `SimClock` warp, KSP-style: physics warp 2-4× (thrust allowed), on-rails warp 10× up to ≈ 100 000× while coasting (no thrust, no hostiles near), altitude-banded limits near bodies, automatic predictive drop-back when anything happens (contact, comms, trigger, alarm, arrival); trajectory preview, nav computer, `warp` console command; fly to the sun or other planets (1 AU in ≈ 50 s at the cap); honest gravity assists and Oberth burns | `SimClock` rule (no wall clock), `UniversePos`, M6 gravity |
| M10 Jumpgate travel | other star systems | system generator (star, planets, moons, belts, gates, per-system sky; a star's colour is one entry in `data/star_systems.json`, Q30, and the Narn system's star is red), gate network, transitions | `UniversePos.system_id`, sky as a generated asset, scenario data |
| M11 Hyperspace | the other space | separate space with gravitational incline, currents, beacons and lock; full-control flight; later combat in hyperspace; the destination jumpgate broadcasts with unlimited range (M3-T17's `broadcast_range_m = INF`, for the player and the AI) | `environment_accel`, one `WorldFrame` per space |
| M12 Factions and capital ships | the setting's fleets | raider carrier and Raider Battle Wagon (launch tubes as Delta-V spawn points; moved out of M2 because they need M6's LOD chains; earlier only if the M8 raiders launch from one), raider control ship, Earthforce renegades, Narn, Centauri, Minbari, Drazi and other non-aligned worlds, Shadow scouts and large Shadow ships, Vorlon ships of several sizes; turrets, subsystems; organic part library with SH sheen; capital-ship destruction as a staged break-up with secondary blasts, visible from tens of km through M4-T23's far explosion flashes; blast damage with distance falloff for every explosion and ship death scaled by size, and ships and stations disabled without exploding (see "Required: blast damage and disabled hulks"); it replaces M4's benchmark stand-ins: the box capitals (`CapitalStandin`), their gun and interceptor turrets, beam lasers, missiles, carrier launches, the four bench sides and the mine stand-ins' flat 200-point blast; mines belong here (the maintainer, 2026-11-08): defensive minefields laid by each faction around its stations, capital ships and chokepoints, placed by scenario and mission data instead of M4's belts between the sides, with M12's blast falloff replacing the flat 200-point stand-in blast (M14's missions may add minefield crossings on top). | `faction`, procgen `styles/` and `parts/`, `AiPilot` |
| M13 Starfury Thunderbolt | second player ship | new `ShipSpec` + generator family member with its own pod/wing layout | `ShipSpec` per class with `asset_id`, `ThrusterLayout` from hardpoints |
| M14 Mission types | variety | rescue with towing (tether force), escort, asteroid fields, comets, random encounters in free flight; it replaces M4's asteroid stand-in (`AsteroidField`, the benchmark's slab of 1 000 static rocks) with generated asteroid fields, built on M5's `asteroids` generator and `BeltLayout` (M5-T29, the escort's sparse belt). | tether design (§14.7), procgen asteroid/comet assets, mission framework |
| M15 Voiced dialog | the instructor speaks | offline TTS generator (`tools/procgen` asset kind `voice`): renders every dialog line from mission data on the user's machine with one voice per speaker plus a radio filter; output cached and gitignored. Candidate engine: Piper (`OHF-Voice/piper1-gpl`, GPL-3.0); only voice models whose licence permits it. Being produced by code, voices satisfy the procedural-only rule. Can be pulled forward any time after M8 | dialog lines as data (speaker, text, voice id) from M5; subtitles stay as the fallback |

## Carried from M4's full review (2026-11-08)

M4-T43 read the whole code base after M4; its eleven "fix in M4" findings were fixed (M4-T44), and the fifteen below are assigned
here (the maintainer, 2026-11-08). Details, evidence and suggested fixes: `docs/research/m4-full-review.md`, sections L1 to L15.

| finding | what | milestone |
|---|---|---|
| L1 | the flight batch's per-ship GDScript gather (about 37 % of the tick at 1 000 ships): read the rows natively | M5 (performance block) |
| L2 | the hit resolver walks every bolt in GDScript and builds unfiltered pairs | M5 (performance block) |
| L3 | the ram resolver's GDScript passes and string keys | M5 (performance block) |
| L5 | the radar fills its dot buffers per contact in GDScript each frame | M5 (performance block) |
| L8 | a native allocation pass (per-tick `Vec` and packed-array churn in the kernels) | M5 (performance block) |
| L9 | `note_hull` / `note_selection` scan every member per event | M5 (performance block) |
| L12 | the smaller items (S each) | M5 (performance block) |
| L13 | native and GDScript constants mirrored by hand | M5 (performance block) |
| L6 | every AI shot anywhere gets a flash and a sound | M5 (sound pass) |
| L7 | two `AudioStreamPlayer3D` per pooled ship, walked every frame | M5 (sound pass) |
| L14 | test and script duplication; always-pending balance tests | M5 (with the balance retune, AC12) |
| L4 | the rebase cascade (statics shifted natively, the cached solid shifted in place, hidden ships skipped) | M6 |
| L15 | the bench reads and writes `res://reports`, which an exported build does not have | M8 |
| L10 | an explosion builds meshes and materials per death | M12 (the staged capital break-up rewrites it) |
| L11 | the stand-in counters walk every ship each tick | M12 (M12 replaces the stand-ins) |

## Required: gravity

Maintainer requirement (M2 play test): gravitational pull must be in the plan. It is, in three places: **M6** adds restricted
n-body gravity with Kepler-rail bodies (the Epsilon star, Epsilon III and its moons) through `World.environment_accel`, which
`Ship` already applies as `mass * env_accel` and the brake already feeds forward; **M9** adds honest gravity assists and Oberth
burns for the time-warp work; **M11** gives hyperspace its own incline field through the same hook. What M6 must cover:

- Ships, bolts and debris all feel it (bolts and debris as test particles, so a bolt fired near a planet curves).
- The hard 9 999 m/s speed clamp in `Ship` is for thrust. A body falling toward a star can legitimately go faster, so M6 drops
  the clamp and keeps only the thrust fade (`SpeedGovernor.thrust_gain`), or raises the limit with the scale of the system.
- Low orbit around an Earth-sized body is about 7.8 km/s, inside the 5 000 / 9 999 m/s ceilings, so a ship can hold an orbit
  with assist on only below 5 000 m/s of thrust-added speed; orbital speed is not "thrust-added", so M6 decides how assist's safe
  speed is measured (relative to the dominant body) before orbits are flown.
- The HUD's reference point (now the launch point) becomes the dominant body, bay or jump gate of the mission.

Finite reaction mass can be switched on in any milestone after M9: `FlightOutput.mass_flow_kg_s` already exists.

## Required: blast damage and disabled hulks (M12)

Maintainer requirement (2026-11-05). Today no explosion hurts anything except M4's mine stand-ins, which deal a flat 200 hull
points to every hull within 100 m with no falloff (`mine_standin.gd`, a benchmark placeholder). M12 replaces that with one blast
model and adds disabling without explosion:

- **Damage falls off with distance.** Every blast (mines, missiles, torpedoes and ship deaths) has an energy and a radius;
  damage to a hull falls with the distance from the blast centre to the hull's nearest surface (a smooth falloff to zero at the
  radius, not a flat value inside it), so a ship at the edge of a blast is scratched and one beside it is wrecked. The same falloff
  feeds the push a blast gives to nearby bodies.
- **Every ship's death is a blast scaled by its size.** A fighter's death is a small blast that can hurt a wingman flying close; a
  capital ship's reactor going up is a large and very dangerous one that can destroy fighters and damage other capitals nearby.
  The blast's energy and radius come from the ship's class and what is aboard (reactor size, magazines), not from a fixed number.
  M4-T23's far explosion flashes already scale their brightness and reach with the blast's energy; this uses the same energy.
- **Large ships and stations can be destroyed without exploding.** Capital ships and stations are built of sections; only
  sections holding a reactor, fuel or weapons and magazines can blow up. Terminal damage to other sections (bridge, hangar decks,
  engines, habitat) incapacitates the ship or station instead: it loses power, control or thrust in stages, stops fighting, and the
  hulk keeps drifting on its last motion (Newtonian, no damping), a navigational hazard and a possible later mission object
  (boarding, salvage, rescue). A disabled hulk can still explode later if a reactor or magazine section is hit.
- **Seams to keep before M12:** M4's damage zones (`DamageZones`) and hardpoints are the start of the section model; the explosion
  level of detail (M4-T23) keeps each death's energy and radius as data; the low-attention tier (M4-T21) must carry a disabled
  hulk as a drifting row, not remove it.

## Required: alternate control profiles

Maintainer requirement from the M1 play test: "a future version must support alternate controls from a saved set".
The player picks a control profile (the default layout of architecture §6.1, alternates such as the pre-swap stick-yaw / D-pad-roll
layout, and their own edits), and the choice and any custom profile are saved and survive restarts. Planned as
M2-T11 (saved, console-driven profiles); the M5 controls menu adds remapping on top, and the M8 tutorial teaches
whichever profile is active. Seams already in M1: every
binding is an `InputMap` action, `InputAdapter` is the only place that knows action names, and per-action shaping
(ramps, tap-or-hold, deadzones) lives in `InputAdapter`/`Settings`, so a profile is a saved set of `InputMap`
events plus those settings, applied before the first frame. The tutorial checks read actions, never devices.

## Later, and not planned

- **Later** (nice to have): keyboard + mouse flight, HOTAS, VR cockpit (Godot's Mobile and Forward+ renderers support multiview),
  mod support, multiplayer.
- **Later, a feel feature** (M4-T32, Q51): wing-level AI, where the wing picks targets and tactics a few times a second and its
  members steer, avoid and aim every tick (T32's option B, `docs/research/wing-level-ai.md`). It saves almost nothing in performance;
  it is built only if the maintainer judges that it makes the dogfights feel better (H), starting from "the wing picks targets" on
  `WingDirector`.
- **Not planned** (deferred indefinitely): Windows, macOS (Apple Silicon), Xbox and other consoles. Release builds
  are Linux x86_64 only.

## Rules that hold across milestones

- Gameplay never reads `Input`; ships consume `FlightCommand` + `CombatCommand`, written by the player or an AI.
- Pure logic stays in `RefCounted` classes with unit tests; nodes stay adapters.
- Every new subsystem registers its debug-console commands and state provider (architecture §6.4).
- Far positions are `UniversePos`; world objects live under `World` and survive rebases.
- Every asset (ships, stations, planets, asteroids, comets, interiors, skies) comes from `tools/procgen` code: no
  hand modelling, no AI 3D generators, no official or ripped franchise assets. Generated binaries stay out of git.
- Any new dependency is recorded in `docs/third-party.md` with a GPL-3.0-compatible license.

**Follow-up from M5-T40 (maintainer, 2026-11-12):** the texture detail setting (low = major seams only, high = show-like plating
with per-plate tone, hatches and ribs) applies to every ship, but only the nine civilian hulls have both texture sets. The Starfury,
the raider and every later hull (capitals, station, other races) need low and high sets built the same way, from show references,
when their surfaces are next worked on. The Starfury and the raider are M7-T15 (planned on `m6`, 2026-11-12).

