# Roadmap (sketch)

Milestones after M1 are sketched only so M1 decisions do not block them. Each gets its own
`docs/milestones/` file when it starts. Order and scope will change.

| Milestone | Theme | Likely contents | M1 hooks that make it possible |
|---|---|---|---|
| **M1 First Flight** | flyable splat ship | see `m1-first-flight.md` | - |
| M1.5 Splat polish (only if needed) | splat quality | denser/near-field sampling, Brush training from multi-view renders of `starfury.obj` on a GPU box, GDGS relighting bake, `.compressed.ply`/`.sog` to allow committing assets | mesh + hardpoints already generated; `SplatStatus` fallback; generators are parametric |
| M2 Targets and combat model | something to shoot | static/moving target drones (splats from the same pipeline), projectile hit detection (`Area3D`/shape-cast per tick), hull HP, debris, impulse on hit, recoil, basic sound | pure `FlightModel`; projectiles are kinematic nodes with velocity; `Projectiles` container |
| M3 HUD and flight aids | readability under Newtonian drift | velocity-vector (prograde/retrograde) markers, target lead reticle, radar/sphere, speed/throttle, auto-hold-velocity assist, "flip to retrograde" assist, free-look (right stick click) | `FlightAssist` is a separate class; `CameraRig` owns cameras; overlay is a `CanvasLayer` |
| M3 (parallel) Floating origin | big play spaces | `WorldShifter` rebases children of `Main` beyond 10 km; Jolt velocity-clamp handling; double-check GDGS precision at range | world content under `Main`; camera-relative sky; velocities never derived from positions |
| M4 Enemy AI | dogfights | state-machine pilots using the same `FlightCommand` interface (AI writes commands, ship does not care who wrote them), pursuit/evade with Newtonian intercept maths, wingman basics | `Ship.set_command()` is the only input to a ship; AI reuses `FlightModel` for feasibility checks |
| M5 B5 environments | the setting | jump gate (splats + animated vortex shader mesh), a station or capital ship hull (large splat set, LOD/paging per GDGS issue #32), asteroid field, lighting from a local star, mission start/finish | multiple `GaussianSplatNode`s already composited in one pass; environment scene is self-contained |
| M6 Game loop | playable slice | mission briefings, objectives, respawn, settings UI (rebinding via `InputMap`), save/load, release builds for Linux/Windows with export templates | `Settings` autoload; InputMap-only bindings; CI already downloads Godot and can download export templates |
| Later | nice-to-have | keyboard+mouse flight, HOTAS, VR cockpit (Raster backend supports multiview), multiplayer (deterministic 60 Hz physics is a start, not a guarantee), mod support | - |

Architecture rules to keep across milestones:

- Gameplay never reads `Input`; everything consumes `FlightCommand`.
- Pure logic stays in `RefCounted` classes with unit tests; nodes stay adapters.
- Generated binaries stay out of git until an asset is hand-authored or training-derived; then adopt Git LFS for
  that directory only.
- Any new dependency is recorded in `docs/third-party.md` with a GPL-3.0-compatible licence.
- Nothing from the Babylon 5 franchise is ever imported; all content stays original and "inspired by".
