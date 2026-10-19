# CLAUDE.md

Guide for implementation agents working in this repository.

## What this is

`space-combat-sim`: a GPL-3.0, non-commercial fan project. A Newtonian 6DOF space-fighter sim in **Godot 4.7.2**
where the player flies a Starfury-inspired ship rendered with **3D Gaussian splats** (GDGS addon) in a starry,
nebula-lit void. Primary platform: Linux + Vulkan, generic XInput gamepad. Read `DISCLAIMER.md` once: it is an open fan
project, so Babylon 5 names (Starfury, Earth Alliance, ...) are fine in code, UI and docs, but never commit
official or ripped franchise assets (models, textures, audio, footage, logos). All content is original.

## Where things are

- `docs/architecture.md`: the design contract (stack, decisions, layout, flight model, input, rendering, assets,
  tests, conventions). Read it before writing code.
- `docs/milestones/m1-first-flight.md`: current milestone, acceptance criteria and the **ordered task list**.
- `docs/roadmap.md`: what comes after, so you do not paint us into a corner.
- `docs/research-notes.md`: verified versions, URLs, container quirks (what is reachable, what is not).
- `docs/third-party.md`: every dependency and its licence; update it in the same PR as the dependency.

## Start here

1. `scripts/setup_godot.sh` (installs Godot 4.7.2 into `.tools/godot/`, verified by SHA-256).
2. `scripts/gen_assets.sh` (regenerates `assets/generated/`; needs `python3` + `numpy`).
3. `scripts/run_tests.sh` (Python tests, `godot --headless --import`, GUT headless; must exit 0).
4. Open `docs/milestones/m1-first-flight.md`, find the first task whose "Done when" is not met, and do that one
   task as one PR-sized change. If none of the scripts exist yet, you are on **M1-T01**.

Until T01 lands, download/clone details are in `docs/research-notes.md` ("Container findings"): GitHub release
assets and `git clone` work through the proxy; `archive/refs/tags/*.zip`, `api.github.com` and the Godot docs
site do not.

## Rules of the road

- Do not commit `assets/generated/`, `.tools/`, `.godot/`, or `reports/` (already in `.gitignore`).
- Do not edit `README.md`, `LICENSE`, `DISCLAIMER.md` (owned by the maintainer) or files under `addons/`
  (vendored upstream code; see `docs/third-party.md`).
- Statically typed GDScript, one class per file, pure logic in `RefCounted` classes with GUT unit tests in the
  same PR; nodes are thin adapters. Physics in `_physics_process`, visuals in `_process`.
- Gameplay never reads `Input`; it consumes `FlightCommand` from `InputAdapter`.
- Keep Newtonian motion honest: zero gravity, zero damping (project *and* body, `DAMP_MODE_REPLACE`), forces
  re-applied every physics tick. The damping guard test must stay.
- Anything that needs a GPU cannot be verified in the container; mark it `(H)` and leave it for the human
  tester instead of faking it.
- Commit subjects start with the task id, e.g. `M1-T07: flight model and assist`. Do not push or open PRs unless
  asked; the maintainer handles git remotes.

## Commands

```
scripts/setup_godot.sh
scripts/gen_assets.sh
scripts/run_tests.sh
# pieces, if you need them individually:
python3 -m unittest discover -s tools/tests -v
.tools/godot/godot --headless --path . --import
.tools/godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
.tools/godot/godot --path . --quit-after 180 --headless        # smoke-run the main scene (after M1-T12)
```
