# Roadmap

The next target after M1 is the **tutorial mission vertical slice**: launch from Babylon 5, an instructor teaches
the controls and gives an exterior tour, then raiders come through the jumpgate and you defend the station with
allies. Milestones M2-M7 build toward it; everything else follows it. Each milestone gets its own
`docs/milestones/` file when it starts; order and scope will change. Long-term design: `docs/architecture.md` §14.

## Path to the tutorial slice

| Milestone | Goal | Contents | Builds on (M1 hooks) |
|---|---|---|---|
| **M1 First Flight** | flyable splat Starfury | see `m1-first-flight.md` | - |
| M1.5 Splat polish (only if needed) | splat quality | denser near-field sampling, optional Brush training on a GPU box, GDGS relighting bake | fallback meshes and hardpoints already generated; `SplatStatus` |
| M2 Combat sandbox | something to shoot | see `m2-combat-sandbox.md`: generated `raider_fighter` (Delta-V) with break-up chunks; raiders are real `Ship`s flown by simple `PilotBrain`s (idle, patrol, attack runs); target-relative swept hit detection per tick; hull damage (`god` protects the player), generated explosions and debris; pools so nothing hitches; minimal HUD (velocity vector, lead reticle, target box with hull, own hull); `combat_sandbox` waves; control profiles (saved binding sets, console-driven); generated SFX if it fits (else M3) | `TargetingSystem` + `Targetable.faction`, `PulseCannonGate`, kinematic projectiles, `DebugFlags`, `tools/procgen` parts/styles (new `raider` style) |
| M3 AI pilots and wingmen | others who fly | `AiPilot extends PilotBrain`: utility selection over attack, evade, formation, follow path, guard; collision avoidance and ram damage; faction relations as data (M2 has a fixed rule); allies fight alongside you (Starfury break-up chunks); an instructor who flies a waypoint route | M2's `PilotBrain`/`Perception`/`PilotSteering`/`AiPilotDriver`, `InterceptMath`, `Factions`, `Combatant`/`ShipAssembly`, pools; command split, `SimClock` |
| M4 Mission framework and front end | scripted play | `Game` state machine, scenario + mission scripts (coroutine API), triggers, objectives, subtitles + comms panel (dialog lines as data: speaker, text, voice id), `CINEMATIC` camera mode, debrief, console commands to load a scenario and skip mission steps; front-end menu: free flight (random encounters on/off) or mission select; settings and controls menus (remapping on top of M2 control profiles) | `ScenarioLoader` + `data/scenarios/` (waves since M2), `World.spawn` from universe coordinates, `UiCommand`, camera mode enum, `ControlProfile` |
| M5 Epsilon space at true scale | the real neighbourhood | moving free-falling `WorldFrame` (auto position and velocity rebase on), restricted n-body gravity with Kepler-rail bodies (Epsilon star, Epsilon III, moons), scaled-space renderer (planet + atmosphere shader, sun), per-asset LOD chains + `LodSwitcher` ("model blurring") + resident splat budget (LOD work upstreamed to GDGS), `jumpgate` asset with vortex effect | `UniversePos`, `World.rebase`, `environment_accel`, brake `env_accel_b` feed-forward, manifest `lods`, procgen framework |
| M6 Babylon 5 station | the station | `babylon5_station` generator (~8 km: hub, rotating drum as `AnimatableBody3D`, launch bays, defense-grid emplacements as hardpoints), compound collision, launch-bay sequence with a cinematic launch camera, generated station interior for the front end | procgen parts/styles and hardpoints contract, camera modes, `World` frame (station fits the local space) |
| M7 Tutorial vertical slice | the first mission | front end over the B5 interior -> launch from a bay -> subtitled instructor (voice comes with M14) checks each control (pods, retros, strafe, roll, assist, brake, targeting, fire modes) -> exterior tour pointing out the defense grid -> raiders arrive through the jumpgate vortex -> defend the station with allies -> debrief; Linux x86_64 release build with export templates | all of the above; tutorial checks read the same `InputMap` actions as M1 |

## After the tutorial

| Milestone | Goal | Contents | Builds on |
|---|---|---|---|
| M8 Time warp and the solar system | go anywhere | `SimClock` warp, KSP-style: physics warp 2-4× (thrust allowed), on-rails warp 10× up to ≈ 100 000× while coasting (no thrust, no hostiles near), altitude-banded limits near bodies, automatic predictive drop-back when anything happens (contact, comms, trigger, alarm, arrival); trajectory preview, nav computer, `warp` console command; fly to the sun or other planets (1 AU in ≈ 50 s at the cap); honest gravity assists and Oberth burns | `SimClock` rule (no wall clock), `UniversePos`, M5 gravity |
| M9 Jumpgate travel | other star systems | system generator (star, planets, moons, belts, gates, per-system sky), gate network, transitions | `UniversePos.system_id`, sky as a generated asset, scenario data |
| M10 Hyperspace | the other space | separate space with gravitational incline, currents, beacons and lock; full-control flight; later combat in hyperspace | `environment_accel`, one `WorldFrame` per space |
| M11 Factions and capital ships | the setting's fleets | raider carrier and Raider Battle Wagon (launch tubes as Delta-V spawn points; moved out of M2 because they need M5's LOD chains; earlier only if the M7 raiders launch from one), raider control ship, Earthforce renegades, Narn, Centauri, Minbari, Drazi and other non-aligned worlds, Shadow scouts and large Shadow ships, Vorlon ships of several sizes; turrets, subsystems; organic part library with SH sheen | `faction`, procgen `styles/` and `parts/`, `AiPilot` |
| M12 Starfury Thunderbolt | second player ship | new `ShipSpec` + generator family member with its own pod/wing layout | `ShipSpec` per class with `asset_id`, `ThrusterLayout` from hardpoints |
| M13 Mission types | variety | rescue with towing (tether force), escort, asteroid fields, comets, random encounters in free flight | tether design (§14.7), procgen asteroid/comet assets, mission framework |
| M14 Voiced dialog | the instructor speaks | offline TTS generator (`tools/procgen` asset kind `voice`): renders every dialog line from mission data on the user's machine with one voice per speaker plus a radio filter; output cached and gitignored. Candidate engine: Piper (`OHF-Voice/piper1-gpl`, GPL-3.0); only voice models whose licence permits it. Being produced by code, voices satisfy the procedural-only rule. Can be pulled forward any time after M7 | dialog lines as data (speaker, text, voice id) from M4; subtitles stay as the fallback |

## Required: gravity

Maintainer requirement (M2 play test): gravitational pull must be in the plan. It is, in three places: **M5** adds restricted
n-body gravity with Kepler-rail bodies (the Epsilon star, Epsilon III and its moons) through `World.environment_accel`, which
`Ship` already applies as `mass * env_accel` and the brake already feeds forward; **M8** adds honest gravity assists and Oberth
burns for the time-warp work; **M10** gives hyperspace its own incline field through the same hook. What M5 must cover:

- Ships, bolts and debris all feel it (bolts and debris as test particles, so a bolt fired near a planet curves).
- The hard 9 999 m/s speed clamp in `Ship` is for thrust. A body falling toward a star can legitimately go faster, so M5 drops
  the clamp and keeps only the thrust fade (`SpeedGovernor.thrust_gain`), or raises the limit with the scale of the system.
- Low orbit around an Earth-sized body is about 7.8 km/s, inside the 5 000 / 9 999 m/s ceilings, so a ship can hold an orbit
  with assist on only below 5 000 m/s of thrust-added speed; orbital speed is not "thrust-added", so M5 decides how assist's safe
  speed is measured (relative to the dominant body) before orbits are flown.
- The HUD's reference point (now the launch point) becomes the dominant body, bay or jump gate of the mission.

Finite reaction mass can be switched on in any milestone after M8: `FlightOutput.mass_flow_kg_s` already exists.

## Required: alternate control profiles

Maintainer requirement from the M1 play test: "a future version must support alternate controls from a saved set".
The player picks a control profile (the default layout of architecture §6.1, alternates such as the pre-swap stick-yaw / D-pad-roll
layout, and their own edits), and the choice and any custom profile are saved and survive restarts. Planned as
M2-T11 (saved, console-driven profiles); the M4 controls menu adds remapping on top, and the M7 tutorial teaches
whichever profile is active. Seams already in M1: every
binding is an `InputMap` action, `InputAdapter` is the only place that knows action names, and per-action shaping
(ramps, tap-or-hold, deadzones) lives in `InputAdapter`/`Settings`, so a profile is a saved set of `InputMap`
events plus those settings, applied before the first frame. The tutorial checks read actions, never devices.

## Later, and not planned

- **Later** (nice to have): keyboard + mouse flight, HOTAS, VR cockpit (the GDGS Raster backend supports multiview),
  mod support, multiplayer.
- **Not planned** (deferred indefinitely): Windows, macOS (Apple Silicon), Xbox and other consoles. Release builds
  are Linux x86_64 only.

## Rules that hold across milestones

- Gameplay never reads `Input`; ships consume `FlightCommand` + `CombatCommand`, written by the player or an AI.
- Pure logic stays in `RefCounted` classes with unit tests; nodes stay adapters.
- Every new subsystem registers its debug-console commands and state provider (architecture §6.4).
- Far positions are `UniversePos`; world objects live under `World` and survive rebases.
- Every asset (ships, stations, planets, asteroids, comets, interiors, skies) comes from `tools/procgen` code: no
  hand modelling, no AI 3D generators, no official or ripped franchise assets. Generated binaries stay out of git.
- Any new dependency is recorded in `docs/third-party.md` with a GPL-3.0-compatible licence.
