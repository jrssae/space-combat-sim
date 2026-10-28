# Handoff: cloud session → local machine (2026-10-20)

Where the project stands, what you need to do on your Linux desktop, and how to keep going with Claude Code
locally. Everything below is on the `m1-first-flight` branch on GitHub. It is **not merged into `main` yet**.

## 1. State of the branch

| Area | State |
|---|---|
| M1 First Flight (T01-T15) | Built. Every automated (A) criterion passes in CI |
| M1 play-test fixes (your feedback) | All merged (list in section 3); **waiting on your re-test** |
| M2 Combat Sandbox plan | `docs/milestones/m2-combat-sandbox.md`: 14 tasks, acceptance criteria, your answers recorded |
| M2 tasks done | **T01** combat maths, **T02** multi-ship readiness, **T03** hit detection and damage, **T04** raider generator, **T05** raider ship and pool, **T06** destruction, **T07** AI, **T08** HUD, **T09** waves, **T12** sound, **T14** fuel tank + weapon capacitor, **T11** control profiles (see section 5) |
| M2 tasks left | T10 (integration, capture set, play-test guide), T13 (only if you reject the raider look), T12, T13 (conditional) |
| M2 play-test round (2026-10-21) | **M2 AC15-AC19 passed.** The feedback round is done in commits `M2.1-*` (controls, speeds, HUD, sound, splats): table in `docs/milestones/m2-combat-sandbox.md`, "Post-M2 play-test round". **Waiting on your re-test** (GPU-only items: flicker and sharpness, engine sound, silhouettes) |
| Tests | 265 Python + about 1 230 GUT, all passing; CI runs on every push |

## 2. Get it running locally

```
git clone https://github.com/jrssae/space-combat-sim.git   # or: git fetch && git checkout m1-first-flight
cd space-combat-sim
git checkout m1-first-flight
pip install numpy pillow          # if not installed
scripts/setup_godot.sh            # Godot 4.7.2 into .tools/godot/ (SHA-256 checked)
scripts/gen_assets.sh             # regenerate the Starfury, buoys and sky (re-run after every pull)
.tools/godot/godot --path . --import
.tools/godot/godot --path .       # play
scripts/run_tests.sh              # optional: the full automated suite (~3 min)
```

`docs/playtest.md` has the controls, the console cheat sheet and the full checklist.

## 3. What changed since your play-test (please re-test)

| Your finding | Fix |
|---|---|
| Checkerboarding (AC12/13) | Two bugs in the vendored splat renderer, patched and documented in `addons/gdgs/PATCHES.md`: (1) a sort-buffer overflow when splats get large on screen (the tile budget was 10 per splat, now 32, with every pass bounds-checked); (2) memory corruption on GPUs with subgroups narrower than 32, which now fall back to Raster. **Not verifiable without your GPU.** Check whether it is gone. |
| Starfury looks like a Thunderbolt | Regenerated from your references: wedge fuselage, swept trussed struts with hazard stripes, ring-faced pods, claws, guns under the nose. About 10 m long, 15 m wide, 230k splats. |
| Blocks in first-person view | The cockpit now matches your reference frame: trapezoid main pane, corner struts, side panes, sill. The centre of the view is clear (tested). |
| Swap D-pad L/R with right stick L/R | Right stick = pitch + **roll**; D-pad L/R = **yaw** (ramped). The old layout is a built-in profile, `m1_classic` (section 5). |
| No R3 on your pad | **Tap D-pad Up** = next target; **hold D-pad Up** (0.35 s, `settings.target_hold_s`) = target nearest the nose. |
| Brake didn't stop rotation | Hold X = **all stop** (linear and rotation). With a target selected it also **turns the nose onto the target** (about 2.6 s for 90°). |
| Chase camera drifts and swings | **Rigidly locked** behind the ship. Optional softness: `set settings.camera_chase_smoothing_s 0.2`. |
| Muzzle flash visible through the hull | A hull depth proxy hides effects behind the ship. |
| Glow not centred on the nozzles | Plumes now come out of each nozzle along its axis. |
| (found while fixing) | Hull splats no longer judder against the camera at speed (`SplatPoseSync`). |

New for you to try:
- the `screenshot` console command (saves a PNG, handy for bug reports)
- fuel and weapon charge in the console (`state ship`, `get weapons.charge`; fuel is unlimited unless
  `set settings.fuel_unlimited off`)
- control profiles (section 5)

**Re-test:** walk the checklist in `docs/playtest.md`. Most important: the checkerboarding (AC12/13), the new Starfury
and cockpit, the swapped controls, hold-to-target, brake-to-target, the locked camera, and hull occlusion
(AC16b). Tell Claude which boxes pass. Once M1 is accepted, Claude can open a PR to merge `m1-first-flight` into
`main`.

## 4. Continuing with Claude Code on your machine

Start Claude Code in the repo (`cd space-combat-sim && claude`). It reads `CLAUDE.md` automatically, which points at
the milestone docs and the rules. Useful prompts:

- *"Read docs/handoff.md and docs/milestones/m2-combat-sandbox.md, then do M2-T02 as one PR-sized change on
  m1-first-flight. Run scripts/run_tests.sh before committing."* Repeat with the next task id.
- *"Record my M1 re-test results in docs/milestones/m1-first-flight.md: <your notes>"*
- *"Here is the Delta-V reference sheet: <attach file>. Record it in docs/design-references.md and do M2-T04."*

Model per task (from the M2 plan): **Opus** for T03 hit detection, T04 raider generator, T07 AI seam and T10
integration; **Sonnet** for T02, T05, T06, T08 HUD, T09 waves and T12 sound. Fable is only worth it for T04/T13
if you top up credits. Switch with `/model opus` or `/model sonnet`.

Dependency order: T02 → T03 → (T04 once the reference arrives) → T05 → T06/T07 → T08 → T09 → T12 → T10.
`docs/milestones/m2-combat-sandbox.md` has the full table.

Locally you have a real GPU, so you can run the game directly to check visuals; `scripts/capture.sh` is only for
GPU-less cloud containers.

**Tips learned in this session:**
- Agent worktrees were created from `main`, not the working branch. Either merge `m1-first-flight` into `main`
  first, or tell each agent to `git merge --ff-only m1-first-flight` before starting.
- Running four agents in parallel hit the plan's session limit twice. Two at a time is steadier.
- `scripts/run_tests.sh` also compiles every script (GUT silently skips test files that fail to parse) and runs
  console smoke tests of the real game, so trust its exit code.

## 5. Control profiles (M2-T11)

Console-driven until the M5 controls menu exists. Open the console with the ` key:

| Command | Does |
|---|---|
| `controls list` | show the profiles |
| `controls use m1_classic` | your original layout: right stick X = yaw, D-pad L/R = roll (this session only) |
| `controls use default` | back to the current layout |
| `controls show` / `controls show fire` | list every binding, or one action's |
| `bind fire pad:button:7` / `unbind fire pad:button:0` | add or remove a binding. Bind the new one first: every action must keep a pad binding |
| `controls save mine` | write `user://controls/mine.cfg` and select it |
| `save` | make the selection survive a restart |
| `controls delete mine` | remove a saved profile (`default` and `m1_classic` are protected) |

`bind` and `unbind` last only until you quit unless you `controls save`. Caveat: `m1_classic` swaps the bindings
only. The stick yaw goes through the D-pad's ramp and the D-pad rolls at full rate, so it isn't proportional as in
the very first M1 build.

## 6. Open questions for you

1. **Delta-V reference (blocks M2-T04).** Please attach the raider fighter sheet as a *file* (pasted images
   don't reach sub-agents). Also: is the wing much wider than the ship is long (span ≈ 2× length)? Is roughly
   9 m long × 17 m wide right? Worn grey or brown-grey?
2. **Defaults being used until you say otherwise:**
   - Starfury bolts blue-white, raider bolts orange-red.
   - Explosion: white flash, short orange fireball and sparks, hull breaking into 4-5 tumbling pieces.
   - "Next target" cycles hostiles first, then buoys.

## 7. Known issues and housekeeping

- The splat-renderer fixes need your GPU to confirm. If checkerboarding remains, send a screenshot and the overlay
  text (`SPLATS COMPUTE/RASTER`, GPU name).
- One headless import crashed once with a Godot "double free" in a cloud container; a rerun was clean and it
  never reproduced.
- The remote branches `m1-t03-ci` and `m1-t03-ci-redcheck` are leftovers from the CI check. Delete them in the
  GitHub UI (the cloud session can't).
- Fable usage credits ran out during this session, so the M1 fixes and the M2 plan were done with Opus and Sonnet.
- Reference images are never committed (copyright). `docs/design-references.md` holds written descriptions.
