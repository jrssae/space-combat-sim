# Handoff: M5 civilian ship models on a second machine (2026-11-03)

Five M5 tasks need only Python: the civilian ship generators and the fidelity tool they are scored with. Nothing in them
runs the game. This file is everything a Claude Code session on another computer needs to finish them on the `m5`
branch while this machine carries on with the Godot tasks.

Read first: `CLAUDE.md`, then `docs/milestones/m5-mission-framework-and-front-end.md` (Q8, Q11, Q14 and Q16 to Q23, D59,
D61, AC11, AC12, AC20 and the sections of T11, T12 to T15, T22 and T23), then `docs/assets-civilian.md` and the
"Civilian ships (M5)" part of `docs/design-references.md`.

## The tasks

Do them in this order. Each one ends as every M5 task does: implement, a fresh-agent review of the diff, fix rounds,
then a commit `M5-TNN: docs: status and as-built` that sets the Status cell to `done` and writes the task's
**Done (as built, date)** notes, then a push.

| Task | State on 2026-11-03 | What is left |
|---|---|---|
| T23 (`refview compare`: the 90 % check) | Built (2150669, d3f66e5, a0af8df), two fix rounds (86888f9, d2a2adc) | A scoped re-review of the two fix rounds, then the status commit |
| T13 (`skylark_transport` generator) | Built and approved (47d5627) | A small follow-up, then the status commit |
| T14 (`narn_transport` generator, `narn` style) | Built and approved (48fd358, d4c66a9) | A small follow-up, then the status commit |
| T22 (Brakiri Bokmai: references, generator with removable pods, `brakiri` style) | Survey and plan written (2c9109f), no generator | Maintainer answers in (Q22); confirm the turret seats on a sheet, then the generator |
| T12 (`saturn_family` generator, five hulls) | Built (eab08b1, c80eace) | A fix round to reach 0.90 (Saturn 3 pod group exempt, Q23), then a full review |

T15 (Brezebel) and T11 (the references) are done. Use them as the model of a finished civilian generator:
`tools/procgen/assets/centauri_brezebel.py` and its T15 Done notes.

### T23: re-review the fix rounds

The first review found that scoring splats against the STL read 5 to 8 % low even for a perfect copy, because the splat
discs blur thin parts. Fix round 1 (86888f9) made the verdict score the fallback mesh (`<id>.obj`) against the STL and
added a second check of the LOD0 splats against their own mesh. Fix round 2 (d2a2adc) replaced that second check's
0.85 IoU with coverage of at least 95 % of the mesh silhouette and banded precision of at least 95 % within one LOD0
spacing (plan commit 7ab9e05). A reviewer should check both commits against those two rulings (12b2165 and 7ab9e05 in
the milestone file). Known close calls are the Saturn 4 lead ship's side coverage (0.952 to 0.957) and the raider's
(0.952); precision reads 1.000 everywhere.

### T13: Skylark follow-up

- Seat the dorsal turret on the hull at about y 2.87 and drop its pedestal.
- Add a test that the fallback mesh holds every piece (face count per chunk), like T15's.
- Re-score with the mesh verdict and add the Fidelity row to `docs/assets-civilian.md`. The T23 run gave 0.979 / 0.976 /
  0.956.
- `docs/assets-civilian.md` line 51 (the budget row) still says start spacing 0.33 m; the build uses 0.26 m.
- Raise the coverage test from 97 % to 99.9 % and extend the symmetry test to LOD2 and LOD3.

### T14: Narn follow-up

- Add the Fidelity row. The mesh scores 0.991 / 0.985 / 0.974.
- `docs/design-references.md` line 443, the crescent row: the T14 re-review measured 2.33 m where the row says "about
  1.3 m thick 3 m in from the rim". Confirm it on the STL's sections and fix the figure.
- Make the LOD box tolerance asymmetric (overshoot at most max(0.3 m, 0.25 spacing), undershoot 1.25) and key the
  big-hull rule on a box extent of 30 m or more instead of spacing 0.25 m.
- The Narn green was lifted to #3A5A48 when the maintainer judged it too dark (2026-11-04, `docs/assets-civilian.md`,
  "Colour round").

### T22: Brakiri Bokmai

The survey is done: the frame mapping, pod mounts, stations, budget, hardpoints, chunks, the `brakiri` style and the
compare command are in both docs (2c9109f). The maintainer answered T22's questions on 2026-11-03 (Q22):

- The tall fins are at the stern, so the blade is the bow and `--right=+x --up=+z --aft=-y` stands. The STL stands on
  its tail (its length runs along file y).
- The pods are pale green, #ABAE9A, as proposed. Put the rest of the scheme (frame #5A6B59, yellow #D8B840) on the
  same sheet for a final OK.
- Two turrets, in the stepped Z-shaped insets high on each flank of the bow (4.9 x 2.4 m, x ±2.3, y 7.2 to 9.7, z 4.1
  to 8.9), one a side, facing outboard (`flank_l`, `flank_r`, up (±1, 0, 0)). The survey had read the insets as windows;
  they are the turret mounts. This is an exception to Q19's top-only rule for the Bokmai. The maintainer first said
  one on top and one under the bow, then corrected it.
- Brakiri turrets fire a bright green pulse (T21 and T16 use it for the bolt colour).

Before the generator commits, show the maintainer a sheet with the two turret spots on the STL's port and front views
and how each turret sits in its inset, and get their OK (Q19).

Then build it. Notes from the survey and the controller's rulings:

- The civilian pipeline (mirror and twins, sampling, `_to_3dgs`, hardpoints, the turret writer, `Piece`, `CENTRE`,
  `RIGHT`) is copied in four generators. T22 moves it into one shared helper module and uses it. Move the four older
  generators onto it only if that is cheap.
- The spindle runs through every pod's sleeve, so the test that the hull has no splats inside the pod volumes leaves out
  a bore of radius 1.48 m round the spindle's axis.
- The pod model's origin is its mount point. Each pod is its own debris piece; the hull's chunks leave the pods out.
- The verdict runs with `--pods-from-hardpoints` (the command is in `docs/assets-civilian.md`).
- The arms, struts and fins are only a few spacings across. Build them at their measured size and let the splat check
  show the loss; never thicken geometry to pass a metric (T15's review reverted exactly that).

### T12: Saturn family fix round

The T23 mesh verdict, part by part (each part scored against the model it was built from: the lead ship and the
transport section against the Saturn 4 STL, the tank section against the tanker STL, the Saturn 3 pod group against the
Saturn 3 STL scaled to the shared pod size, `--model-scale`):

| Part | Top / side / front | Fix |
|---|---|---|
| Lead ship (every variant) | 0.906 / 0.788 / 0.809 | Trace the truss, drum-frame posts and neck member by member off the Saturn 4 model's side and front views |
| Transport sections | front about 0.89 | Pod rims and arms, scored against the Saturn 4 STL (the Saturn 8 model's pods are shorter; Q16 uses the Saturn 4's) |
| Tank sections | under 0.90 in side or front | Closer A-frames, junction recesses |
| Saturn 3 pod group | side 0.639 | Exempt (Q23): record the scores with the note |

Also: crop ranges that match each part on both sides, a test that the fallback mesh holds every piece, and the Fidelity
rows in `docs/assets-civilian.md`.

**The Saturn 3's pod group is exempt (Q23).** T11 spread its lower pods 7.0 m apart (the model has 4.2 m) and raised the
stack 4.7 m so the truss and the slim engine pass. The maintainer keeps that layout. Record the pod group's scores in its
Fidelity row with the note "expected exemption (Q23)"; they do not fail T12. Every other Saturn part, the Saturn 3's
lead ship included, must still pass.

After the fix round, T12 needs a full review (not a scoped one): it is the largest generator and has had no full review
since it was built.

## Setup on the other machine

```
git clone https://github.com/jrssae/space-combat-sim.git && cd space-combat-sim
git checkout m5
python3 -m venv .venv && .venv/bin/pip install numpy pillow
```

Copy the maintainer's `references/` folder from this machine to the repo root by hand. It is gitignored and never
committed. These tasks read `EA_Saturn_3_Freighter.stl`, `EA_Saturn_4_transport.stl`, `EA_Saturn_8_transport.stl`,
`EA_Saturn_Fuel_tanker.stl`, `EA_cargo_pod.stl`, `EA_Skylark_transport.stl`, `Narn_Transport.stl`,
`Brakiri_Bokmai_transport_80m.STL` and `Brakiri_Falkosi_fighter.STL`.

```
.venv/bin/python3 -m tools.procgen build saturn_4_transport          # one asset into assets/generated/
.venv/bin/python3 -m unittest discover -s tools/procgen/tests -t .    # the Python suite
.venv/bin/python3 -I tools/refview/refview.py --help                  # views, sections, shells into reports/refs/
.venv/bin/python3 -I tools/refview/compare.py --help                  # the 90 % verdict
```

Each generator's compare command, with its axis mapping and length, is in its section of `docs/assets-civilian.md`.

Godot is optional there. With `scripts/setup_godot.sh` (no GPU needed), `tests/integration/test_splat_import.gd` checks
that every PLY imports with the manifest's count:

```
.tools/godot/godot --headless --path . --import
.tools/godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_splat_import.gd -gexit
```

Without Godot, write the T22 lines in that test anyway and say so in the Done notes. The controller runs the test here
when the tasks come back.

## Working on `m5` from two machines

This machine keeps going with the Godot tasks (T03, T04, T06, T09, then T07, T08, T10). To keep the two from colliding:

- The other machine owns `tools/procgen/assets/{saturn_family,skylark_transport,narn_transport,brakiri_bokmai}.py`,
  `tools/procgen/parts/`, `tools/procgen/styles/`, `tools/procgen/core/` (only for the shared civilian helper),
  `tools/procgen/tests/` for those generators, `tools/refview/`, `docs/assets-civilian.md`, `docs/design-references.md`
  and the civilian lines of `tests/integration/test_splat_import.gd`. This machine leaves them alone until they come
  back.
- In the milestone file, edit only your tasks' sections and Status cells.
- `git pull --rebase` before every push, and push after every task.
- Commit subjects start with the task id (`M5-T22: ...`) and end with the `Co-Authored-By` trailer.
- Never commit `assets/generated/`, `reports/`, `references/`, `.tools/` or `.godot/`. Never copy STL data or web
  images into the generators; measure and describe.
- Comments explain a method's goal, briefly.

## Rules that apply to every civilian ship

- **90 % fidelity (Q18).** The fallback mesh against the STL: top, side and front IoU each at least 0.90; length, width
  and height each within 10 %. The LOD0 splats against their own mesh: coverage and banded precision each at least 95 %.
  Record the scores in the asset's Fidelity row.
- **The maintainer confirms turrets and colours (Q19)** from a visual sheet before a generator commits them. Turrets are
  dorsal only. Colours come from online images, never from the STL.
- **No metric gaming.** Build parts at their measured size. A thin part that reads soft in splats is a finding, not a
  reason to thicken it.

## Handing back

When all five tasks are `done` and pushed, tell the controller on this machine. It runs `test_splat_import.gd` if the
other machine could not, then starts T21 (defensive turrets) and T16 (civilian ships in the game, with the GPU check),
which wait on these generators.
