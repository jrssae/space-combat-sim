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
| M2 Combat sandbox | something to shoot | generated `raider_fighter` drones on scripted paths, projectile hit detection (per-tick shape cast), hull damage and destruction (break-up into generated debris), minimal HUD (velocity vector, lead reticle, target box, hull bar), procedural SFX; player hull damage is skipped while `debug.invulnerable` is set (console `god`) | `TargetingSystem` + `Targetable.faction`, `PulseCannonGate`, kinematic projectiles, `DebugFlags`, `tools/procgen` parts/styles (new `raider` style) |
| M3 AI pilots and wingmen | others who fly | `AiPilot` brains writing `FlightCommand` + `CombatCommand`; utility behaviours (attack, evade, formation, follow path, guard); faction relations; allies fight alongside you; an instructor who flies a waypoint route | command split, shared `FlightModel` and assist rules, `TargetInfo.faction`, `SimClock` |
| M4 Mission framework and front end | scripted play | `Game` state machine, scenario + mission scripts (coroutine API), triggers, objectives, subtitles + comms panel (dialog lines as data: speaker, text, voice id), `CINEMATIC` camera mode, debrief, console commands to load a scenario and skip mission steps; front-end menu: free flight (random encounters on/off) or mission select | `ScenarioLoader` + `data/scenarios/`, `World.spawn` from universe coordinates, `UiCommand`, camera mode enum |
| M5 Epsilon space at true scale | the real neighbourhood | moving free-falling `WorldFrame` (auto position and velocity rebase on), restricted n-body gravity with Kepler-rail bodies (Epsilon star, Epsilon III, moons), scaled-space renderer (planet + atmosphere shader, sun), per-asset LOD chains + `LodSwitcher` ("model blurring") + resident splat budget (LOD work upstreamed to GDGS), `jumpgate` asset with vortex effect | `UniversePos`, `World.rebase`, `environment_accel`, brake `env_accel_b` feed-forward, manifest `lods`, procgen framework |
| M6 Babylon 5 station | the station | `babylon5_station` generator (~8 km: hub, rotating drum as `AnimatableBody3D`, launch bays, defense-grid emplacements as hardpoints), compound collision, launch-bay sequence with a cinematic launch camera, generated station interior for the front end | procgen parts/styles and hardpoints contract, camera modes, `World` frame (station fits the local space) |
| M7 Tutorial vertical slice | the first mission | front end over the B5 interior -> launch from a bay -> subtitled instructor (voice comes with M14) checks each control (pods, retros, strafe, roll, assist, brake, targeting, fire modes) -> exterior tour pointing out the defense grid -> raiders arrive through the jumpgate vortex -> defend the station with allies -> debrief; Linux x86_64 release build with export templates | all of the above; tutorial checks read the same `InputMap` actions as M1 |

## After the tutorial

| Milestone | Goal | Contents | Builds on |
|---|---|---|---|
| M8 Time warp and the solar system | go anywhere | `SimClock` warp, KSP-style: physics warp 2-4× (thrust allowed), on-rails warp 10× up to ≈ 100 000× while coasting (no thrust, no hostiles near), altitude-banded limits near bodies, automatic predictive drop-back when anything happens (contact, comms, trigger, alarm, arrival); trajectory preview, nav computer, `warp` console command; fly to the sun or other planets (1 AU in ≈ 50 s at the cap); honest gravity assists and Oberth burns | `SimClock` rule (no wall clock), `UniversePos`, M5 gravity |
| M9 Jumpgate travel | other star systems | system generator (star, planets, moons, belts, gates, per-system sky), gate network, transitions | `UniversePos.system_id`, sky as a generated asset, scenario data |
| M10 Hyperspace | the other space | separate space with gravitational incline, currents, beacons and lock; full-control flight; later combat in hyperspace | `environment_accel`, one `WorldFrame` per space |
| M11 Factions and capital ships | the setting's fleets | raider control ship, Earthforce renegades, Narn, Centauri, Minbari, Drazi and other non-aligned worlds, Shadow scouts and large Shadow ships, Vorlon ships of several sizes; turrets, subsystems; organic part library with SH sheen | `faction`, procgen `styles/` and `parts/`, `AiPilot` |
| M12 Starfury Thunderbolt | second player ship | new `ShipSpec` + generator family member with its own pod/wing layout | `ShipSpec` per class with `asset_id`, `ThrusterLayout` from hardpoints |
| M13 Mission types | variety | rescue with towing (tether force), escort, asteroid fields, comets, random encounters in free flight | tether design (§14.7), procgen asteroid/comet assets, mission framework |
| M14 Voiced dialog | the instructor speaks | offline TTS generator (`tools/procgen` asset kind `voice`): renders every dialog line from mission data on the user's machine with one voice per speaker plus a radio filter; output cached and gitignored. Candidate engine: Piper (`OHF-Voice/piper1-gpl`, GPL-3.0); only voice models whose licence permits it. Being produced by code, voices satisfy the procedural-only rule. Can be pulled forward any time after M7 | dialog lines as data (speaker, text, voice id) from M4; subtitles stay as the fallback |

Finite reaction mass can be switched on in any milestone after M8: `FlightOutput.mass_flow_kg_s` already exists.

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
