# Contributing

Thanks for the interest. This is a small, early, non-commercial fan project (see `DISCLAIMER.md`). Contributions
are welcome under the GPL-3.0 (`LICENSE`).

## Ground rules

- **No franchise assets.** Do not submit models, textures, audio, footage, logos, or text copied from Babylon 5 or
  any other property. Everything here is original work "inspired by" the setting.
- **Licences.** Any third-party code or asset must be GPL-3.0-compatible and recorded in `docs/third-party.md`
  with its licence file kept alongside.
- **Generated assets stay generated.** Commit the generator script in `tools/`, not the `.ply`/`.obj` output.

## Workflow

1. Read `docs/architecture.md` and the current milestone in `docs/milestones/`.
2. `scripts/setup_godot.sh && scripts/gen_assets.sh && scripts/run_tests.sh` must pass before and after your change.
3. One task or one fix per pull request; include tests for pure logic and at least an instantiate test for scenes.
4. Statically typed GDScript; follow the conventions section of the architecture doc.
5. Anything only verifiable with a GPU or a gamepad: say so in the PR and describe what you saw on your machine
   (OS, GPU/driver, pad name).

## Reporting issues

Open a GitHub issue with Godot version, OS, GPU and driver, gamepad name/GUID (the debug overlay shows these),
the splat backend shown in the overlay, and steps to reproduce.
