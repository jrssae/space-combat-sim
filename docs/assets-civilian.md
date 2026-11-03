# Civilian ships: what the generators build (M5-T11, for T12 to T15)

Eight civilian hulls from four generators (D59, Q16): `saturn_family` builds `saturn_3_freighter`,
`saturn_4_transport`, `saturn_4_tanker`, `saturn_8_transport` and `saturn_8_tanker`; `skylark_transport`,
`narn_transport` and `centauri_brezebel` build one hull each. The shapes, sizes and colours come from
`docs/design-references.md` ("Civilian ships (M5)"), measured off the maintainer's reference models with
`tools/refview`. This page turns them into parts, budgets, hardpoints, chunks and styles. It is a plan: T12 to T15 build
against it and replace each section with the as-built numbers, the way `docs/assets-raider.md` reads.

Positions here are in the authored frame of the design references: x to starboard, y up, z aft from the nose tip,
metres, Godot's axes. As with every asset, the generator then centres splats, meshes and hardpoints on the splat
centroid and records the shift as `manifest.centroid_offset`. For the Saturns y is measured from the spine axis; for
the others from the hull's box centre or centre plane, as the design references say.

## Output contract

The same as `starfury_aurora` and `raider_fighter` (`docs/architecture.md` §9 and §15.11), per asset id in
`assets/generated/<id>/`:

| File | What it is |
|---|---|
| `<id>.ply`, `<id>_lod1.ply`, `<id>_lod2.ply`, `<id>_lod3.ply` | LOD0 at the default spacing, LOD1 to LOD3 resampled at 2, 4 and 8 times it from their own RNG streams (as the raider's `FAR_LODS`), GDGS orientation, splats of the chunk groups concatenated in `manifest.counts` order |
| `<id>_lod<0-3>.light` | lighting records, one per level (`core/lighting.py`) |
| `<id>.obj` + `.mtl` | fallback mesh; also the hull depth proxy |
| `<id>_chunk_<name>.ply/.light/.obj/.mtl` | break-up chunks cut from LOD1 (`core/chunks.py`; manifest `chunk_lod` 1, as the Starfury) |
| `<id>_turret.ply/.light/.obj/.mtl` | the style's turret model, written like a chunk (D61, T12 brief) |
| `hardpoints.json` | below |
| `manifest.json` | `lods[0..3]`, AABB, `centroid_offset`, `files`, `counts`, `chunks`, `chunk_lod`, `sampling`, `dimensions_m`; a `turret` entry naming the turret files and their splat count |

## Splat budgets

Big ships are mostly seen far away. With `LodSwitcherMath`'s thresholds (LOD0 from 200 px of projected diameter, LOD1
from 60 px, LOD2 from 16 px, at 1080p and 75 degrees vertical), a 258.5 m Saturn 8 is LOD0 inside 910 m, LOD1 to 3.0 km
and LOD2 to 11.4 km; a 158.5 m Saturn 4 switches at 560 m, 1.9 km and 7.0 km; the 96.8 m Saturn 3 at 340 m, 1.1 km
and 4.3 km; a 60 m hull at 210 m, 700 m and 2.6 km. Raiders jump in 6 to 12 km out; patrols and civilians spawn 26 to
30 km out, past the player's 25 km radar (Q12). Patrols fly a route through the area; civilian traffic flies a straight
route that passes 2 to 10 km from the player (T17). LOD2 and LOD3 carry most of the screen time.

The budget rule: all eight at LOD0 at once, plus the player's hero level, the sky and five nav buoys, stays inside
`settings.splat_budget` (2 000 000). Eight LOD0s make 810 000; with the hero (975 058), the sky (16 000) and five buoys
(38 000) that is 1 839 058, 92 % of the budget. In practice eight ships in one view are at LOD1 or coarser (202 500 for
all eight).

| Hull | Length | Surface | LOD0 target (range) | Start spacing | LOD1 | LOD2 | LOD3 |
|---|---|---|---|---|---|---|---|
| `saturn_4_transport` | 158.5 m | 34 500 m² | 130 000 (105 000 to 155 000) | 0.52 m | 32 500 | 8 100 | 2 000 |
| `saturn_4_tanker` | 158.5 m | about 18 400 m² | 70 000 (55 000 to 85 000) | 0.51 m | 17 500 | 4 400 | 1 100 |
| `saturn_8_transport` | 258.5 m | about 65 000 m² | 210 000 (170 000 to 250 000) | 0.56 m | 52 500 | 13 100 | 3 300 |
| `saturn_8_tanker` | 258.5 m | about 36 900 m² | 120 000 (95 000 to 145 000) | 0.55 m | 30 000 | 7 500 | 1 900 |
| `saturn_3_freighter` | 96.8 m | about 19 700 m² | 75 000 (60 000 to 90 000) | 0.51 m | 18 750 | 4 700 | 1 200 |
| `skylark_transport` | 60 m | 6 400 m² | 60 000 (48 000 to 72 000) | 0.33 m | 15 000 | 3 800 | 900 |
| `narn_transport` | 70 m | 9 200 m² | 75 000 (60 000 to 90 000) | 0.35 m | 18 750 | 4 700 | 1 200 |
| `centauri_brezebel` | 60 m | 8 000 m² | 70 000 (55 000 to 85 000) | 0.34 m | 17 500 | 4 400 | 1 100 |
| All eight | | | 810 000 | | 202 500 | 50 700 | 12 700 |

- Surface is the reference model's area at its length (refview's `surface_area_m2`). For the Saturns it is the Saturn
  4 model's area at the family scale (34 500 m²), split into the lead ship (about 4 800 m²), a transport section (about
  29 700 m²) and the tanks, then summed per variant. It counts inner faces the generators drop (buried roots, the
  recessed pod ends), so the generated surface will be 10 to 30 % smaller; tune the spacing to land in the range and
  warn outside it at the default spacing, as the raider does. LOD shares as the raider: LOD1 20 to 30 % of LOD0.
- Start spacing is `sqrt(surface / target)`. Splat sigma is one spacing (overlap 1.0). At 0.52 m a splat seen from
  100 m is about 3.7 px across on a 1080p screen, from 50 m about 7 px, so a close fly-by of a Saturn looks soft. That
  is the price of eight big hulls in the budget; judging it is `(H)`.
- Panel detail has to suit the spacing: a panel grid of 3.6 m with lines 0.4 m wide on the Saturns, 2.4 m and 0.25 m
  on the three smaller ships, survives LOD0 sampling; the Starfury's 4 cm lines would not.
- Turret models are small and sampled finer (about 0.1 m, about 2 000 splats each); with 2 to 4 per hull they add under
  1 % to the totals.
- VRAM, an estimate for T16 to measure: each hull type keeps LOD0 to LOD3 (1.33 times LOD0) and its chunks (0.25 times)
  resident, 1.28 M splats for all eight types. M3-T24 measured about 240 bytes of unique splat buffer per resident
  splat (+234 MB for the hero's 975 058), so about 310 MB with all eight types loaded, before instancing.

## Hardpoints

`hardpoints.json` has the keys the `Hardpoints` and `ThrusterLayout` parsers read (the raider's file is the model),
plus `turrets[]`. Vectors are `[x, y, z]` in the centred body frame, rounded to 5 decimals.

- `center_of_mass`: x = 0; y on the main thrust line, so main thrust makes no pitch torque (as the raider); z from the
  part masses. `mass_kg` and `inertia_estimate_kg_m2` are informational; `ShipSpec` (T16) is the authority.
- `pods[]`, each `{"name": "l", "side": "left", "center": [...], "main": {"position": [...], "exhaust": [0, 0, 1],
  "radius": r}, "retro": {"position": [...], "exhaust": [0, 0, -1], "radius": r}}`. `side` is `"left"` or `"right"`,
  and `ThrusterLayout` needs at least one of each. Hulls with one centre engine split it into a left and a right half.
- `muzzles`: an empty array. The parser requires the key; turrets carry their own barrels.
- `rcs[]`, each `{"name", "pod", "position", "exhaust", "tags"}`, cosmetic ports for plume glow. `tags` holds pilot terms
  from `parts.propulsion.pilot_tags` (`sway_left`, `heave_up`, `yaw_right`, ...); `pod` names the pod it belongs to.
- `collision[]`, each `{"name", "type": "box", "position", "size", "basis"}` or `{"name", "type": "capsule",
  "position", "radius", "height", "axis": "z", "basis"}`, also the hit volumes. Coverage test as the raider's, scaled:
  at least 97 % of LOD0 splat centres inside the primitives inflated by one spacing, and no primitive more than 1 m past
  the splat box.
- `cockpit_camera` `{"position", "forward": [0, 0, -1], "up": [0, 1, 0]}` on the bridge and `chase_anchor`
  `{"position"}` at (0, 0.3 L, 1.2 L behind the centroid), L the length: the parser requires both, though nobody flies a
  civilian in M5.
- `nav_lights` `{"port", "starboard", "top", "top_lamp", "top_lamp_range_m", "cabin", "cabin_range_m"}`: port and
  starboard at the widest points near mid-length, `top` on the highest point, `top_lamp` above it with a range of about
  0.3 L, `cabin` at the bridge windows with a range of about 0.05 L.
- `turrets[]` (D61), each `{"name", "position", "up", "arc_deg", "barrel_m"}`, positions from the design references.
  `arc_deg` 200 for a dorsal or ventral mount (a hemisphere plus 10 degrees below its base), 220 for the Narn's tower
  tops.
- `chunks[]`, each `{"name", "ply", "lighting", "obj", "offset", "joint", "splats"}`, per group below.

### Saturn family

The lead ship gives every variant the same retro nozzles, cockpit, RCS and two turrets:

| Hardpoint | Position (authored frame) |
|---|---|
| Retros (`l`, `r`) | the disc's front rim, (±9.51, 0, 8.56), exhaust (0, 0, -1), radius 0.95 |
| Mains (`l`, `r`) | the bell's exit split in two, (±0.95, 0, length), exhaust (0, 0, 1), radius 2.2; on the Saturn 3's slim engine (Q20, 0.583 scale) (±0.55, 0, length), radius 1.28 |
| `cockpit_camera` | inside the disc's front rim, (0, +0.8, 8.0) |
| `cabin` | the same point, `cabin_range_m` 0.05 L |
| RCS | both ends of the drum frame's three outer drums: the top one at (0, +5.55, z) and the lower ones at (±9.27, -10.55, z), z 41.9 exhausting -z and 50.1 exhausting +z; the disc's flanks (±14.13, 0, 19.06) exhausting ±x; four on the engine collar 3 m behind its front, (±4.78, 0, z) and (0, ±4.78, z), exhausting outward |
| Turrets | `dorsal_fwd` (0, +3.8, 19.1), up (0, 1, 0); dorsal mounts only (Q19) |

Per variant:

| Variant | Length L | Mains at z | More turrets | Port / starboard | Top, top lamp | Chunks |
|---|---|---|---|---|---|---|
| `saturn_4_transport` | 158.5 | 158.48 | `dorsal_aft` (0, +9.3, 124.4) | the first pods' outboard tips (±53.4, -7.29, 74.3) | (0, +8.6, 75.0), lamp (0, +16.6, 99.4), range 48 m | `bow`, `hull`, `engine`, `pods_l`, `pods_r` |
| `saturn_4_tanker` | 158.5 | 158.48 | `dorsal_aft` (0, +9.3, 124.4) | the lower tanks' flanks (±25.6, -13.53, 99.4) | (0, +8.6, 75.0), lamp (0, +16.6, 99.4), range 48 m | `bow`, `spine`, `engine`, `tank_l`, `tank_r` |
| `saturn_8_transport` | 258.5 | 258.48 | `dorsal_mid` (0, +7.2, 149.4) | (±53.4, -7.29, 74.3) | (0, +8.6, 75.0), lamp (0, +21.5, 149.4), range 78 m | `bow`, `hull_1`, `junction`, `hull_2`, `engine`, `pods_1l`, `pods_1r`, `pods_2l`, `pods_2r` |
| `saturn_8_tanker` | 258.5 | 258.48 | `dorsal_mid` (0, +9.0, 149.4) | (±25.6, -13.53, 99.4) | (0, +8.6, 75.0), lamp (0, +21.5, 149.4), range 78 m | `bow`, `spine_1`, `junction`, `spine_2`, `engine`, `tanks_1l`, `tanks_1r`, `tanks_2l`, `tanks_2r` |
| `saturn_3_freighter` | 96.8 | 96.80 | none (Q19, Q20) | the lower pods' outboard ends (±46.8, -5.46, 79.7) | the top pod's ridge (0, +21.8, 73.9), lamp (0, +27.8, 79.7), range 36 m | `bow` (with the cross-beam and blocks), `pod_top`, `pod_l`, `pod_r`, `engine` (with the truss behind the drum frame) |

Collision, per part: the disc a box 28.3 x 6.0 x 28.3 m with the antenna inside it; the forward truss a box 6.3 x 6.3
m along its length; the drum frame a box 21.7 x 19.3 x 8.2 m; each hull cylinder or tank a capsule of radius 8.77 m (it covers the 17.53 x 17.27 m polygon) and
height 75.5 m along z; each pod a box 31.1 x 17.3 x 43.0 m (turned for the Saturn 3) that also wraps its rail; each arm
a box 13.0 x 4.5 x 6.0 m; the engine section a capsule of radius 4.8 m and height 22.6 m; the Saturn 8 transport's
junction a box 13.3 x 13.3 x 24.5 m; the Saturn 8 tanker's three junction modules boxes of 18.3 x 16.8 x 19.1 m.

The Saturns' thrust line is the spine axis, so their centre of mass is trimmed onto it although the cargo hangs below.

### Skylark, Narn and Brezebel

| Hull | Pods (`l`, `r`): main / retro | RCS | Cockpit camera | Port / starboard light | Chunks |
|---|---|---|---|---|---|
| Skylark | main: the bells' exits on the nacelles' axis, (±13.03, -0.26, 55.48), radius 1.62; retro: the intakes' faces, (±13.03, -0.26, 35.64), radius 1.3 (T13: the axis measured off the nacelles; ±13.45, -0.45 was their box with the pods) | the tips of the nacelles' two pods each, the four nose vanes' tips, the corner fins' tips, the dorsal fin's crest and the keel aft (12) | in the bridge plate behind its glazing, (0, +3.6, 11.8) | the nacelles' outboard flanks, (±15.84, -0.26, 46.5) | `capsule` (nose, vanes, capsule, bridge, belly fins, spine, collar, side tanks), `body` (body, corner fins, dorsal fin, centre engine, pedestal), `nacelle_l`, `nacelle_r` (pods, ribs, claws, pylons) |
| Narn | main: a 0.9 m bell on each tower's aft face (z 43.9), its exit at (±15.0, +5.0, 44.72), radius 1.4; retro: the towers' fronts (the vanes' front face on the thrust line), (±15.0, +5.0, 35.7), radius 1.0 | the prong tips (forward and outboard), the fin tips (up and down), the box's aft corners | in the windscreen block behind the canopy, (0, +1.2, 11.3) | the crescent's widest points (±23.0, 0, 27.0) | `cockpit` (cockpit block, dorsal block, the crescent's centre), `wing_l`, `wing_r` (prong, crescent half, fin, tower), `box` |
| Brezebel | main: the arm tips, (±12.0, 0, 60.0), radius 1.2, in the middle of the arm's flat tip face (z 59.4, x 10.67 to 13.2; T15: at x 12.2 the bell would stand out of it); retro: on the fairings' axis where it leaves the bow's rim, (±14.6, 0, 5.7), radius 1.0, firing forward clear of the hull (T15 review: at the fairing's front, z 22.1, it sat 2.6 m inside the arm and the depth proxy hid its plume) | the twelve blocks on the engine bay's walls (their top or bottom faces, exhausting up or down), the four fins' outer faces near their tips (outboard) | behind the window row, (0, +3.5, 2.5) | the bow's widest points (±19.6, 0, 17.0) | `bow` (bow, dorsal fitting, engine bay, main engine), `arm_l`, `arm_r` (arm, fairing, fins) |

The Narn's thrust line is 5 m above its centre plane, the Brezebel's on it (y -0.105 in the box-centred frame). Centre engines (the Skylark's cone, the
Brezebel's drum) glow but are not pods.

## Fidelity (Q18, T23)

Every civilian model must lie within 90 % of its STL, measured as silhouettes and size. `tools/refview/compare.py` is the
measuring stick: each generator task (T12 to T15, T22) runs it on its asset, fixes what falls under the bar and records
its scores in the table at the end of this section. Turrets are left out (the models have none, and they are not in the
fallback mesh or the LOD0 file); the Bokmai is scored with its three pods mounted.

**Two checks, one run.** The verdict scores the model's *geometry*, the fallback mesh `<id>.obj` that every civilian
generator builds from the same parts as its splats (so it must hold every visible part), against the STL. A second check
keeps the LOD0 splats honest against their own mesh. Scoring the splats against the STL directly under-read a perfect
copy of the Saturn 4 by 5 to 8 % and favoured parts built too thin: a splat near an edge reaches about 0.75 spacings
past it whatever the settings, so the loss follows the shape.

| Check | What is drawn | Bar | Shift |
|---|---|---|---|
| Geometry (Q18) | the STL's triangles and the asset's mesh, top (x-z), side (y-z) and front (x-y), on one grid | each view's intersection over union (IoU) at least 0.90, and the mesh's length, width and height each within 10 % of the STL's (a ratio from 0.90 to 1.10) | the mesh may move up to 2 % of the length per axis, reported |
| Splats | the asset's mesh and its LOD0 splats, same views, with a band one LOD0 spacing wide | per view, **coverage** at least 0.95 (the share of the mesh silhouette's pixels that splat pixels cover: nothing missing) and **banded precision** at least 0.95 (the share of the splat silhouette's pixels within the mesh silhouette grown by one spacing: nothing misplaced) | none: same parts, same frame |

The band is the asset's LOD0 spacing: `manifest.sampling.spacing_m`, or, if the manifest has none, derived from the splat
scales (the median of the largest sigma, divided by `sampling.overlap` or 1). The console line and `fidelity.json` say
which was used, and the band in pixels (the spacing over the pixel, rounded up, never under one pixel). Plain IoU at 0.85
was tried first and failed faithful thin parts, so the band stands in for it: it passes a fringe of up to a spacing and
fails parts that are absent or moved by several spacings. The tool's own tests pin it. Splats sampled from a 46 x 18 x
70 m box read coverage 0.998 or better and precision 1.000 against it at 0.31 and 0.5 m spacing; from a hull with a
0.6 m wing (two spacings thick at 0.31 m, where plain IoU read 0.77 in front) coverage 0.977 or better and precision
1.000; with the wing missing from the splats top coverage is 0.33; with the wing's splats eight spacings aft top
precision is 0.90 (three spacings aft passes, 0.97); a box's splats grown by a spacing keep precision at 0.97 or more and
by three spacings fall to 0.88. Coverage is the tight number on thin parts seen edge-on (the Saturn lead ship's side view
reads 0.95 to 0.96, the built raider's 0.95), where a slab thicker than the splats' reach is covered only by its end faces.
`splats_<view>.png` shows which failed: orange is mesh the splats do not cover, red is splat beyond the band, blue is
splat inside the band. Exit status is 0 when both checks pass, 1 when either fails, 2 on bad input. The terminal gets one
block per check and a `verdict:` line last.

**How the two are put on one grid.**

- The STL goes through `refview`'s frame with the same `--length`, `--right`, `--up` and `--aft`: x to starboard, y up,
  z aft from the nose tip, x and y centred on the model's box. A generator that authors about another origin shows up as
  a shift beyond the window below. The Saturns measure y from the spine axis, not from the box centre, so they pass
  `--model-offset 0,<dy>,0` (metres added to the model, whole ships only; dy is minus the spine axis's height above the
  model's box centre, pinned per model below). When the silhouettes only meet further away than the window, the tool
  prints a `note` with a value from a wider silhouette search (up to 10 % of the length in x and y).
- The asset's `<id>.obj` is written in the Godot frame centred on the splat centroid, and `<id>.ply` is the same turned
  by Rz(180) into the GDGS orientation; `manifest.centroid_offset` is the authored position of that centre. The tool
  adds the offset to the mesh and undoes the flip and adds the offset to the splats. A test pins this on the built raider
  (its mesh starts at z = 0 with the offset, its splats follow its mesh).
- A splat is drawn as the outline of its Gaussian at 0.75 sigma, so a flat splat seen edge-on is a thin line; the factor
  is calibrated against the built raider, Starfury and Narn transport (mean IoU over the views peaks at 0.7 to 0.8).
- The pixel is 0.25 % of the part's length (`--pixel-frac`, never above 0.5 %). The move is the same for all three views,
  whole pixels, to where they overlap best; it is printed and written to `fidelity.json`, and the geometry scores are
  taken there (`iou_unshifted` is the score without it).

**Running it** (the STLs are in the main checkout's `references/`; the mappings and lengths are from
`docs/design-references.md`):

```
.venv/bin/python3 -I tools/refview/compare.py references/EA_Skylark_transport.stl skylark_transport --length 60 --right=-x --up=+z --aft=+y
.venv/bin/python3 -I tools/refview/compare.py references/Narn_Transport.stl narn_transport --length 70 --right=+y --up=+z --aft=+x
.venv/bin/python3 -I tools/refview/compare.py references/Centauri_Brezebel_Transport.stl centauri_brezebel --length 60 --right=+y --up=+z --aft=+x
.venv/bin/python3 -I tools/refview/compare.py references/EA_Saturn_4_transport.stl saturn_4_transport --length 158.48 \
    --right=-x --up=+z --aft=+y --model-offset 0,-3.643,0
```

The Saturn models are scaled to the family scale of Q16, so their `--length` is the model's length there: 158.48 m for the
Saturn 4 transport, 266.2 m for `EA_Saturn_8_transport.stl`, 255.1 m for `EA_Saturn_Fuel_tanker.stl` and 91.13 m for
`EA_Saturn_3_Freighter.stl` (no engine section). The Bokmai takes its three pods from its `hardpoints.json`; T22 fills in
its file mapping from the reference:

```
.venv/bin/python3 -I tools/refview/compare.py references/Brakiri_Bokmai_transport_80m.STL brakiri_bokmai --length 80 \
    --right=<axis> --up=<axis> --aft=<axis> --pods-from-hardpoints
```

`--pods-from-hardpoints` draws the pod's mesh and splats, `<id>_pod.obj` and `<id>_pod.ply` beside the asset (`--pod-obj
FILE` and `--pod-ply FILE` name others; naming only one takes the other from beside it), at every `cargo_pods[]` mount of
`hardpoints.json`. A mount's `position`, `up` and optional `forward` are in the body frame (the centroid offset removed,
like the other hardpoints) and the pod files' origin is the mount point; the pod's +y is turned onto `up` and its forward
(-z) onto `forward` (a pod that is not fore-aft symmetric needs it; without it the shortest turn is used). `--pod-at
X,Y,Z` (repeatable) gives a mount by hand.

**Part by part (Q16, Q20).** The Saturns are modular, so only the whole Saturn 4 transport is scored as a whole. Every
other part is scored against the part of the model it was built from, cropped on both sides and aligned on its own:

| Asset part | Model it is scored against |
|---|---|
| the lead ship of every Saturn | the Saturn 4 model's lead ship |
| a transport section (Saturn 4, 8 transport) | the Saturn 4 model's transport section |
| a tank section (Saturn 4 and 8 tanker) | the tanker model's tank section |
| the Saturn 3's pod group | the Saturn 3 model's pods, scaled up to the shared pod size (`--model-scale`, Q20) |

`--model-zrange Z0 Z1` keeps one z range of the model and `--asset-zrange Z0 Z1` one of the asset (meshes are cut exactly
at the planes, splats are kept by centre; a plane inside a ship moves a tenth of a millimetre inward so a face lying in
it goes with its neighbour: cut in a gap). Each cropped side then starts at z = 0, and the asset part is moved in x and y
so that its box centre meets the model part's (`part_align_m` in the JSON), so a part placed differently by design, like
the Saturn 3's raised stack, is scored on its shape; the usual 2 % fine shift follows. `--model-offset` is for whole
ships. `--model-scale SX,SY,SZ` scales the cropped model about its own box centre in x and y and its start in z. `--part
NAME` writes the result to `compare/<name>/`. Take the model's ranges from the part tables of
`docs/design-references.md` and the asset's from its own:

```
.venv/bin/python3 -I tools/refview/compare.py references/EA_Saturn_4_transport.stl saturn_8_transport --length 158.48 \
    --right=-x --up=+z --aft=+y --part transport_2 --model-zrange 49.3 149.3 --asset-zrange 149.3 249.3
.venv/bin/python3 -I tools/refview/compare.py references/EA_Saturn_Fuel_tanker.stl saturn_8_tanker --length 255.1 \
    --right=-x --up=+z --aft=+y --part tanks_1 --model-zrange 49.3 146.2 --asset-zrange 49.3 149.3
.venv/bin/python3 -I tools/refview/compare.py references/EA_Saturn_3_Freighter.stl saturn_3_freighter --length 91.13 \
    --right=-x --up=+z --aft=+y --part pod_group --model-zrange 41.5 91.13 --asset-zrange 41.5 96.8 \
    --model-scale 1.2436,1.093,1
```

**Output.** `reports/refs/<ship>/compare/` (`.../compare/<part>/` for a part; gitignored): `overlay_top.png`,
`overlay_side.png` and `overlay_front.png` (STL only in orange, mesh only in blue, both in dark grey, with a legend and a
metre scale), `splats_top.png`, `splats_side.png` and `splats_front.png` (mesh only in orange, splats inside the band in
blue, splats beyond it in red, both in dark grey) and `fidelity.json` (the geometry check's per-view IoU and pixel counts,
dimensions, shift, part alignment and suggested offset; `splat_check` with the spacing and where it came from, the band in
pixels and each view's coverage and precision; the thresholds, failures and verdicts).

**Saturn model offsets (T12).** The spine axis's height above each model's box centre, read off the model's cylinder or
tank (the Saturn 3: its disc's rim): `--model-offset 0,-3.643,0` for `EA_Saturn_4_transport.stl` (length 158.48),
`0,-2.804,0` for `EA_Saturn_8_transport.stl` (266.2), `0,-6.835,0` for `EA_Saturn_Fuel_tanker.stl` (255.1) and `0,-1.293,0`
for `EA_Saturn_3_Freighter.stl` (91.13). The Saturn 3's pod group is scored against the model's scaled to the shared pod
(`--model-scale 1.2436,1.093,1`, an option T12 added: 43.03/34.6 across, 17.27/15.8 tall, Q20).

**Scores.** One row per ship and part, filled by the generator task that builds it (the date is the run's). The
rows written before the planner's change of 2026-11-03 (the mesh as the verdict) read the LOD0 splats against the STL, the tool's first version; each generator
task re-scores its rows on the mesh (the geometry check's numbers) and says which check each row is.

| Ship | Part | Top IoU | Side IoU | Front IoU | Length | Width | Height | Date |
|---|---|---|---|---|---|---|---|---|
| `saturn_4_transport` | whole ship | 0.926 | 0.904 | 0.908 | 1.002 | 1.007 | 1.050 | 2026-11-03 |
| `saturn_4_tanker` | lead ship (vs Saturn 4 model, z 0-49.3) | 0.895 | 0.764 | 0.795 | 1.007 | 1.024 | 1.028 | 2026-11-03 |
| `saturn_4_tanker` | tank section (vs tanker model's first) | 0.880 | 0.856 | 0.905 | 1.039 | 0.980 | 1.030 | 2026-11-03 |
| `saturn_8_transport` | lead ship (z 0-49.3) | 0.873 | 0.715 | 0.808 | 1.008 | 1.019 | 1.030 | 2026-11-03 |
| `saturn_8_transport` | cargo 1 (model 49.3-152.8, asset 49.3-149.3) | 0.901 | 0.882 | 0.842 | 0.973 | 1.004 | 1.002 | 2026-11-03 |
| `saturn_8_transport` | cargo 2 and engine (model 152.8-266.2, asset 149.3-258.5) | 0.905 | 0.906 | 0.837 | 0.969 | 1.004 | 1.003 | 2026-11-03 |
| `saturn_8_tanker` | lead ship (z 0-49.3) | 0.894 | 0.762 | 0.792 | 1.008 | 1.023 | 1.036 | 2026-11-03 |
| `saturn_8_tanker` | cargo 1 (model 49.3-146.2, asset 49.3-149.3) | 0.926 | 0.887 | 0.889 | 1.040 | 1.001 | 1.020 | 2026-11-03 |
| `saturn_8_tanker` | cargo 2 and engine (model 146.2-255.1, asset 149.3-258.5) | 0.970 | 0.929 | 0.888 | 1.010 | 1.001 | 1.021 | 2026-11-03 |
| `saturn_3_freighter` | lead ship (z 0-41.5) | 0.660 | 0.499 | 0.665 | 1.007 | 1.023 | 0.812 | 2026-11-03 |
| `saturn_3_freighter` | pod group (model 41.5-91.1 scaled 1.244, 1.093, 1; asset 41.5-96.8) | 0.772 | 0.383 | 0.655 | 1.130 | 0.996 | 1.038 | 2026-11-03 |
| `centauri_brezebel` | whole ship, mesh against the STL (best shift x -0.15 m, the model's fins sit 0.2 m to port; unshifted 0.972, 0.984, 0.945); the LOD0 splats against the mesh read 0.978, 0.960, 0.951 | 0.966 | 0.984 | 0.970 | 1.000 | 1.000 | 0.999 | 2026-11-03 |
| `skylark_transport` | whole ship (no shift; against its own fallback mesh the splats read 0.964, 0.958, 0.926) | 0.958 | 0.949 | 0.911 | 1.004 | 1.006 | 1.022 | 2026-11-03 |

## `saturn_family` (T12)

One module, `tools/procgen/assets/saturn_family.py`, registering the five ids; each id is a variant record. The shared
parts go into a new `tools/procgen/parts/saturn.py`. Every part has one size on every variant (Q16); the variants differ
only in how many cargo sections they carry and of which kind.

| Part | How to build it | Size |
|---|---|---|
| `antenna` | a `lathe` dish and cone spike on a `box` boom | dish 7.2 m, spike 3.8 m |
| `command_disc` | `loft` along z through flattened elliptic sections: width from the plan outline (a circle of radius 14.13 m cut square 10.6 m behind its centre, then the 12.7 m neck to the truss), height from the lens profile (6.0 m at the centre, 1.6 m at the rim). The 12 radial fins on each face and the hub are `box`es and a `lathe`; the corner blocks are `box`es. | 28.3 m across |
| `truss_spine` | three longerons (thin `lathe` tubes or `sweep_rect` bars) in a 6.3 m triangle with V braces in bays of about 7 m; the length sets the bay count; a ring of radial brackets where it meets a dome | 28.5 m to the first cylinder; 63.7 m on the Saturn 3 |
| `drum_frame` | a triangular frame of `box`es round the truss holding three `lathe` drums, plus the drum on the truss | drums 3.2 and 4.0 m x 8.2 m |
| `hull_cylinder` | a horizontal `lathe` with 5.9 m domes and a straight barrel, paint bands as per-segment materials. `parts/hull.py`'s `cylinder_hull` paints bands the same way but stands on Y with conical shoulders, so this is a new part. Also every tank. | 17.53 m x 75.5 m |
| `engine_section` | a `lathe` collar, four `lathe` propellant tanks round a central one, U-shaped `sweep_rect` feed pipes, and `propulsion.nozzle` for the bell | 9.6 m collar, bell exit 6.3 m, 22.6 m long |
| `cargo_arm` | a `box` arm and a `sweep_rect` brace | 13.0 x 6.0 x 4.5 m |
| `pod_rail` | a `lathe` rod with `box` end blocks | 2.74 m x 41.4 m |
| `transport_pod` | `prism` of the kite outline (inboard end face 6.02 m, ridge 17.27 m at 31 % of the width, outboard end face 3.80 m) extruded along the pod's length and turned so the extrusion runs along z (along x for the Saturn 3). The end faces are recessed: an inset ring (`inset_convex_polygon`) with ladder ribs as `box`es inside. The 3.65 m end bands are a second, slightly larger prism. Trim (stripe, hazard band, rust-red top) is material bands on the prism's faces. | 31.06 x 17.27 x 43.03 m |
| `transport_section` | a hull cylinder, four arms, four rails and four pods at the section-local stations of the design references | 100 m |
| `tank_section` | three hull cylinders (the spine tank and two lower tanks at x ±16.51, 13.53 m below) with `sweep_rect` braces between them | 100 m |
| `junction` | the Saturn 8 transport's hexagonal `prism` module with struts to both domes; the Saturn 8 tanker's three hexagonal `prism` modules with recessed panels, `lathe` necks and joining plates | 13.3 x 10.6 m; 18.3 x 16.8 x 19.1 m each |
| Saturn 3 cross-beam and pod blocks | `box`, `tapered_box`, and `wing.vent_grille` for the grilles | beam 56.4 m wide; blocks 6.3 x 4.4 x 13.4 m |

| Variant | Cargo | Junction | Engine section | Length |
|---|---|---|---|---|
| `saturn_4_transport` | one transport section at z 49.3 to 149.3 | none | z 135.9 to 158.5 | 158.5 m |
| `saturn_4_tanker` | one tank section at z 49.3 to 149.3 | none | z 135.9 to 158.5 | 158.5 m |
| `saturn_8_transport` | transport sections at z 49.3 to 149.3 and 149.3 to 249.3 | z 137.2 to 161.7, one module | z 235.9 to 258.5 | 258.5 m |
| `saturn_8_tanker` | tank sections at z 49.3 to 149.3 and 149.3 to 249.3 | z 137.2 to 161.7, three modules | z 235.9 to 258.5 | 258.5 m |
| `saturn_3_freighter` | cross-beam, blocks and three pods crosswise (z 48.5 to 95.3), the truss through the stack | none | slim (0.583 scale, Q20), z 83.6 to 96.8, between the lower pods and under the top pod | 96.8 m |

The length rule (Q16) is lead ship plus cargo: 49.3 m of lead ship ahead of the first section, 100 m per section, and
the engine section's last 9.2 m behind the last section. The section's own stations, the Saturn 3's stack and every
variant's z table are in the design references. Per-variant trim is variant data: the transports' pods get the red
top stripe and the hazard band, the Saturn 3 pods rust-red tops, every tank the red and off-white bands.

## `skylark_transport` (T13)

As built (2026-11-03): `tools/procgen/assets/skylark_transport.py` places the pieces of `tools/procgen/parts/skylark.py`
in the authored frame of the design references (x and y from the model's box centre, the nose vanes' tips at z = 0), so
the fidelity check needs no model offset. 60.04 m long, 40.2 m across the claw tips, 10.25 m tall.

| Part | As built |
|---|---|
| Capsule, nose | one `lathe` from the dark nose face through the neck, a front dome, the barrel with its two bands (z 6.6 to 7.8 and 15.6 to 16.8), an aft dome and the spine to z 29.6; both domes are spheres of the capsule's 3.73 m radius |
| Nose vanes | four `sweep_rect` plates square to their radius, narrowing from 2.09 m to 1.13 m, 0.22 m thick, each with a strut back into the neck |
| Bridge | a `section_loft` of hexagons: straight walls up from inside the capsule to y 3.39, sides leaning in to a ridge that peaks at y 4.29 (z 14.7); its faces ahead of z 12.6 are dark glass |
| Belly fins | `prism` trapezoids 0.32 m thick, 24.1 degrees below the horizontal, root chord z 6.0 to 12.75, tip chord 7.8 to 9.95 |
| Spine vanes, collar | twelve `prism` wedges per ring round the spine; a `lathe` collar 6.34 m across |
| Side tanks | `lathe` tanks with their band (z 23.8 to 25.0) and neck, `lathe` dumbbells, a flat bracket at each tank's nose, a flat plate to the spine, a pointed flat bar beside each neck |
| Body | a `section_loft` through 18 stations of an 18-point flattened diamond (ridge, flanks, side faces, a knee on the bottom, the keel), from the measured plan and sections; olive patches on the ridge's flanks and the side faces; `prism` corner fins; two dark blocks on its aft face |
| Dorsal fin | a `section_loft` of lens sections stacked up y, from the root inside the body to the crest at y 5.13 |
| Centre engine | a `lathe` drum, a `lathe` exhaust cone (dark metal) with a dark bore, twelve dark vanes round its neck |
| Pedestal | a `lathe` drum 2.1 m across from inside the body up to the turret mount at y 3.6 |
| Nacelles | a `lathe` about (±13.03, -0.26): dark ribbed intake ring, sand body, dark bell with its bore; 16 intake ribs and 24 bell ribs as `prism` plates; two pods as lofts of elliptic sections |
| Claws, pylons | each claw two `section_loft` prongs either side of a `section_loft` web, from stations measured along it; flat `prism` pylons from the nacelle |

Budget at the default spacing of 0.26 m (thin parts are sampled finer, the body a little coarser): LOD0 61 014 splats
(capsule 23 020, body 15 104, each nacelle 11 446), LOD1 15 200, LOD2 3 804, LOD3 964; the turret 2 372 at 0.08 m. The
0.26 m spacing (not the planned 0.33 m) follows from the built surface being smaller than the reference's (no inner
faces); it stays at 0.25 m or more so the Godot import test's looser box rule for big hulls applies to its coarse levels.
Hardpoints: the table above. The centre of mass is on the nacelles' axis, the thrust line. Collision: 43 primitives
(a capsule for the capsule's barrel, boxes elsewhere, oriented boxes for the belly fins, pods and claws).

## `narn_transport` and the `narn` style (T14)

`tools/procgen/assets/narn_transport.py`, `tools/procgen/styles/narn.py`.

As built (M5-T14); the parts are in `tools/procgen/parts/narn.py`. Numbers the design references leave open were measured
off the STL's shells and sections. Authored frame: y from the crescent's centre plane, z from the prong tips.

| Part | As built |
|---|---|
| Crescent | a centre body (z 15 to 51.3, out to x ±13.2) and two halves (each prong from its tip, then the plate outboard of x 13.2 to z 46.65): faceted `section_loft`s whose seams are left open, the notch's walls and back built. Section in the table below. A red band on each half's top, z 18.5 to 22.5, from 15 % to 85 % of the way from the cap's corner to the bevel |
| Cockpit | a hexagonal `section_loft` (stations below) with a flat top at y -0.16; a `canopy_glass` panel z 6.6 to 12.9 out to 84 % of the top's half-width, in a 0.4 m `canopy_frame`; a windscreen block (y -0.5 to 2.0; x ±4.48, z 10.06 to 15.8 at its foot; x ±2.45, z 11.1 to 15.8 at its top) whose front face is glass |
| Dorsal block and bar | a frustum (x ±3.4, z 20.32 to 26.46 at y 2.25; x ±2.01, z 21.49 to 25.30 at y 4.78); a trapezoid bar z 25.44 to 35.28, half-width 1.25 at y 2.52 and 0.84 at y 4.21 (the model's bar, not a `lathe` rod); two plates 0.44 m thick at y 4.36 beside its end, outline (x, z) (0.9, 30.86), (2.95, 33.4), (2.95, 35.29), (0.9, 35.29) |
| Fins | `prism` 0.5 m thick at x ±17.1, outline (z, y) (28.4, 0), (28.7, 8.1), (38.0, 8.1), (44.1, 0), (38.0, -8.6), (28.7, -8.6) |
| Flank towers | a frustum from y 0 (x 12.98 to 16.96, z 34.82 to 43.82) to y 7.93 (x 13.36 to 16.58, z 39.03 to 43.90); a slotted crown x 14.15 to 15.54, z 40.36 to 43.07, y 7.8 to 9.0, its slot x 14.61 to 15.08 down to y 8.55; three vanes (`sweep_rect`, 0.67 m square) at x 14.09, 15.04 and 15.99 along (z, y) (34.0, 0.3), (35.75, 4.4), (36.1, 5.05), (36.6, 5.5), (37.3, 5.75), (38.2, 5.87), (39.2, 5.87); a `propulsion.nozzle` (throat 0.95, exit 1.4, 0.9 m long) on the aft face at x 15.0, y 5.0 |
| Cargo box | a chamfered `section_loft` along z: x ±12.75, y -9.0 to 5.0, the chamfers from x ±11.6 to (±12.75, 4.35) and (±12.75, -8.5); the wedge front's edge at z 31.2, y 0.52, its top rising 1.158 and its bottom falling 2.70 per metre; the top's rear chamfer from z 69.2 down to y 4.35 at z 70; the aft cut from (z 66.4, y -9.0) to (70.0, 0.55). Paint as facets: `cargo_panel` z 41 to 61, y -6.5 to 2.5 on each side; 1.2 m hazard checkers z 35.2 to 40.0 and 61.4 to 66.2, y -8.3 to -7.1. Two `wing.vent_grille`s (five slats, 4.58 m across, 5.55 m long) at x ±8.88, z 65.09 |

| Crescent section | Measured |
|---|---|
| Outline (z, half-width) | (0, 10.0), (3.6, 15.3), (15.3, 22.0), (27.0, 23.0), (38.8, 19.1), (45.0, 15.5), (51.3, 6.7); the notch's inner edge (0, 10.0), (6.3, 10.0), (9.4, 13.2), (15.0, 13.2) |
| Thinning to the rim | top 0.62 + 0.137 d, bottom -(0.89 + 0.135 d), d the distance in from the rim; beveled over the last 1.2 m to an edge at y -0.15 |
| Centre body caps, z: top / bottom | 15: 2.5 / -2.85; 27: 3.76 / -4.04; 45: 2.2 / -2.4; 51.3: 1.0 / -1.2 |
| Prong caps, z: top / bottom | 0: -0.15 / -0.15; 0.3: 0.02 / -0.28; 1.5: 0.43 / -0.70; 2.5: 0.77 / -1.05; 4.5: 0.88 / -1.16; 6: 1.04 / -1.32; 8: 1.13 / -1.41; 12: 1.20 / -1.48; 15: 1.33 / -1.61 (the plate steps up behind them) |

| Cockpit station z | Widest half-width (at y -1.43) | Top: half-width, y | Keel: half-width, y |
|---|---|---|---|
| 2.8 | 4.5 | 1.5, -1.43 | 1.5, -1.43 (a sharp front edge) |
| 5.85 | 6.75 | 3.76, -0.16 | 2.1, -2.05 |
| 6.9 | 7.5 | 4.4, -0.16 | 2.3, -2.27 |
| 8.75 | 8.1 | 5.65, -0.16 | 2.6, -2.6 |
| 9.8 | 8.3 | 5.85, -0.16 | 2.87, -2.85 |
| 11.7 and 15.8 | 8.52 | 6.29, -0.16 | 2.87, -2.85 |

The turret model: a six-sided base 2.6 m across its corners and 0.5 m tall, a wedge housing (z -1.0 to 1.1, half-width
0.7 to 0.95, top 0.95 to 1.7 m) with a red band at z 0.15 to 0.45, twin barrels at x ±0.42, y 0.7 with the muzzles 3.0 m
ahead of the turning axis; 1 894 splats at 0.11 m on its own 0.65 m panel grid.

## `centauri_brezebel` and the `centauri` style (T15)

`tools/procgen/assets/centauri_brezebel.py`, `tools/procgen/styles/centauri.py`.

As built (M5-T15); the parts are in `tools/procgen/parts/centauri.py`. Numbers the design references leave open were
measured off the STL's shells and sections. Authored frame: y from the box centre, the hull's centre plane at
`CENTRE_Y` -0.105 (heights below are above that plane), z from the nose.

| Part | As built |
|---|---|
| Bow | a smooth `section_loft` of ellipses from z 0.02 (a small cap) to z 19: half-width W and half-height H from a quarter ellipse (W = 19.56 s, H = 4.375 s, s = sqrt(1 - ((17 - z) / 17)^2)), straight on behind z 17 (W 19.56 - 0.1402 (z - 17), H 4.375 - 0.0389 (z - 17)); 64 points a ring, 33 stations dense at the nose. The `trim_light` band is the rim's 9 degrees either side of the centre plane, bow only. The rear face between the inner walls is a flat `hull_dark` panel |
| Arms | one smooth `section_loft` per arm from z 19 to 59.4 through the same ellipses outboard of the flat inner wall at x 10.67 (33 points); the wall is `hull_dark` up to z 25.4 (the bay). From z 58.3 the section shrinks towards the wall's middle by (1 - t^2.5)^(1/2.5), t = (z - 58.3) / 1.7, to a flat tip face at z 59.4 holding a `propulsion.nozzle` (throat 0.85, exit 1.2, 0.6 m long) at x 12.0 whose exit is the reference's tip at z 60. A `hull_dark` rail box x 10.39 to 10.75, y -0.64 to 0, z 18.6 to 58.8 |
| Engine bay | `hull_dark` boxes: the block x ±7.40, ±2.89 about the centre plane, z 18.8 to 25.43; low side boxes x 7.40 to 10.75, ±0.90, z 19.0 to 25.28; engine mounts x 2.2 to 5.6, ±1.53, z 25.3 to 28.7. Twelve `rcs` blocks x 7.43 to 9.34, 0.635 to 1.955 above and below, 1.29 m long at z 20.11, 22.0 and 23.85. The main engine: a `lathe` drum (radius 1.2 from z 25.3, 1.58 from 26.4 to 29.5, a 1.62 ring at 29.8 to 30.1, 1.25 to 30.47) and a `propulsion.nozzle` (throat 0.85, exit 1.2, 0.9 m) to z 31.37 |
| Dorsal fitting | a `section_loft` along y through horizontal rectangles (y, half-width, z front, z back): (0.9, 4.90, 1.30, 10.88), (3.95, 3.86, 2.30, 11.58), (4.2, 2.80, 2.42, 11.45), the front raked back 18 degrees; five `window` boxes 0.6 by 1.2 m, 0.95 m apart, centred 2.95 m up on the raked front and standing 0.08 m proud of it; a `hull_dark` turret ring 2.4 m across from y 4.12 to 4.3 at z 7.0, the turret's mount |
| Arm fairings | a smooth `section_loft` per arm, upper and lower halves alike, through stations (z, x in, x out, peak): (22.1, 11.13, 18.48, 3.865), (24, 11.04, 18.32, 3.765), (27, 10.86, 18.0, 3.565), (30, 10.83, 17.58, 3.305), (33, 10.85, 17.1, 3.015), (36, 11.01, 16.43, 2.645), (38, 11.25, 15.89, 2.335), (40, 11.56, 15.25, 1.995), (41.5, 12.06, 14.49, 1.585), (42.6, 12.7, 13.6, 1.0); the top at u of the way out is peak times 0.80, 0.885, 0.964, 1.0, 0.997, 0.972, 0.927, 0.868, 0.792, 0.686, 0.548, 0.40, 0 at u 0, 0.03, 0.1, 0.2 ... 0.9, 0.97, 1. Only the part outside the arm shows: the lip at z 22.1 and up to 1 m of bulge |
| Tip fins | a `section_loft` along y through thin chamfered sections (h, leading edge z, trailing edge z): (1.0, 44.40, 57.15), (2.1, 44.38, 56.22), (2.6, 44.92, 55.78), (3.1, 45.52, 55.32), (4.1, 46.68, 54.72), (5.1, 47.58, 54.08), (6.1, 48.12, 53.48), (7.1, 48.28, 52.88), (8.1, 48.12, 52.22), (9.1, 47.72, 51.62), (9.6, 47.42, 51.32), (10.1, 46.88, 50.98), (10.6, 46.02, 50.68), (10.9, 44.42, 50.48), (11.1, 43.18, 50.38), (11.3, 42.18, 50.28), (11.5, 41.62, 50.12), (11.9, 41.42, 49.88), (12.3, 41.48, 49.62), (12.4, 41.58, 49.48), (12.53, 42.0, 49.2). Inner face x 10.785 - 0.178 (h - 3.105), outer 12.145 - 0.272 (h - 3.105) (the mean of the model's port and starboard fins). The top 0.65 m is the gold cap; a gold light 0.28 m across stands on each upper hook's tip (h 12.58, z 41.95). The lower fins mirror the upper ones in the centre plane |

| Level | Spacing | Splats (seed 42) |
|---|---|---|
| LOD0 | 0.26 m | 67 230 (`bow` 34 128, `arm_l` and `arm_r` 16 551 each; budget 55 000 to 85 000) |
| LOD1 (the chunks) | 0.52 m | 16 774 (24.9 %) |
| LOD2 | 1.04 m | 4 198 (6.2 %) |
| LOD3 | 2.08 m | 1 060 (1.6 %) |

The turret model: a `hull_dark` flange 1.5 m across and 0.15 m tall, a stalk 0.64 m across up to 0.8 m, a teardrop pod
2.2 m across lying fore and aft on its axis 1.75 m up (a round front from z -1.2, widest at z -0.1, tapering to a point at
z 1.9), twin barrels at x ±0.45 on the pod's axis with the muzzles 2.6 m ahead of the turning axis, and two gold collars
on each barrel (where it leaves the pod, and near the muzzle); 2 080 splats at 0.11 m.

## `brakiri_bokmai` and the `brakiri` style (T22, plan)

`tools/procgen/assets/brakiri_bokmai.py`, `tools/procgen/styles/brakiri.py`, parts in a new
`tools/procgen/parts/brakiri.py`. This is T22's plan from the survey of 2026-11-03 ("Brakiri Bokmai transport" in
`docs/design-references.md`). The maintainer confirmed the bow, the pale green pods and the turrets in the bow's flank insets (Q22); the
turret seats and the rest of the scheme go on a review sheet before the generator commits them. Authored frame as in the design references: y from the model's box centre, z from the prow, so the
fidelity check needs no model offset. The generator writes the hull without its pods and one pod model,
`brakiri_bokmai_pod.*`, LOD0 to LOD3 at the hull's spacings so it switches with the hull (D59).

| Part | How to build it | Size |
|---|---|---|
| `bow` | `section_loft` (`parts/starfury.py`) along z through the blade's measured sections: wide top, waist, flared keel. The prow's rounded edge and the crown's rise come from the side profile. The two stepped flank insets are the turret mounts (Q22): recess them and seat a turret in each. | z 0 to 14, 13.5 m tall, at most 5.7 m across |
| `spine` | `section_loft` of rounded rectangles (`superellipse_ring`) from the crown to the fork | 5.24 x 3.5 m at z 15 to 30, 8.2 m wide at the fork (z 47.6) |
| `fork_strut`, `post` | `section_loft` along the strut's centre line from the fork to the post's top, then down the post | struts 2.6 x 2.0 m, posts 1.6 x 2.5 m |
| `lower_arm` | `section_loft` along the measured centre line: out from the keel, then straight aft, rising from y -1.45 to +1.9 | about 2.0 x 1.3 m, z 10 to 60 |
| `neck`, `nacelle` | `loft` of upright ovals (`superellipse_ring`) along the nacelle axis (±13.16, 2.09): the neck's 2.0 x 4.0 m oval swelling to the nacelle's 4.6 x 6 m body. The open cup at the aft end is an inner wall in `nozzle`. | z 62 to 79.5 |
| `engine_dome` | `ellipsoid_cap` (or a short `lathe`) in the cup | 1.70 x 2.83 x 3.89 m, aft end at z 80.0 |
| `fin` | `section_loft` along y through thin sections (leading edge z, trailing edge z, thickness) from the fin rows of the design references. The upper fins' insets are `stripe` faces; every fin's top 1.5 m is `stripe`. | upper to y 15.45, lower to -15.43 |
| `spindle` | `lathe` rod and coupling drum, `hull_dark` | rod 1.93 m x 45.5 m; drum 2.43 x 1.87 m |
| `cargo_pod` (the pod model) | `loft` of `superellipse_ring` sections (17.81 x 11.74 m, corners about 3.5 m, the crowned top) with domed ends from the end stations. The sleeve is a `lathe` tube, the straps `sweep_rect` hoops, the top and side plates `box`es, the saddles `ellipsoid_cap`s, the corner rails `lathe` rods. | 17.81 x 11.74 x 13.39 m |

The pod model's origin is its mount point, the pod's centre on the spindle axis, with +y up and -z forward. In the
model the corner rails run unbroken from the front pod's middle to the aft pod's, with couplers over the gaps, and touch
only the pods. The pod model carries its own rails, from its saddles to its end faces, and leaves the couplers out, so
an empty mount shows no floating rail. The rods are 0.38 m across and lie inside the pods' outlines from above and from
the side, so the silhouettes barely see the difference.

The spindle runs through every pod's sleeve. D59's test that the hull alone has no splats inside the pod volumes
therefore leaves out the bore, a cylinder of radius 1.48 m (the sleeve's) round the spindle's axis; with no pods the
bare spindle is what an empty mount looks like.

**Budget.** The surfaces come from the reference's shells table: the frame 3 112 m², the spindle and drum 298, the domes
52, the fin insets 102 and the bow insets 15; a pod's body 896 m², its straps 68, plates 26, and rails, saddles and
couplers about 60 (the sleeve's 145 m² lies mostly inside the pod). Scaling the 60 m hulls' switch distances, the
Bokmai is LOD0 inside about 280 m, LOD1 to 930 m and LOD2 to 3.5 km.

| Asset | Surface | LOD0 target (range) | Start spacing | LOD1 | LOD2 | LOD3 |
|---|---|---|---|---|---|---|
| `brakiri_bokmai` (hull) | about 3 600 m² | 40 500 (32 000 to 49 000) | 0.30 m | 10 100 | 2 500 | 630 |
| `brakiri_bokmai_pod` (each) | about 1 000 m² | 11 500 (9 000 to 14 000) | 0.30 m | 2 900 | 720 | 180 |
| Hull and three pods | about 6 600 m² | 75 000 | | 18 800 | 4 660 | 1 170 |

All nine hulls at LOD0, the Bokmai with its three pods: the eight planned in "Splat budgets" make 810 000 and the
Bokmai 75 000, 885 000 in all. With the hero (975 058), the sky (16 000) and five buoys (38 000) that is 1 914 058,
95.7 % of `settings.splat_budget` (2 000 000). All nine at LOD1 make 221 300, at LOD2 55 360, at LOD3 13 870. The
Bokmai keeps about 80 000 splats resident (LOD0 to LOD3, its chunks and the pod's levels), about 19 MB at M3-T24's
240 bytes a splat. The generated surfaces will come out 10 to 30 % smaller than the reference's, as on the other
hulls, so tune the spacing into the ranges.

**Hardpoints.** In the body frame after the centroid shift, like every hardpoint.

| Hardpoint | Position (authored frame) |
|---|---|
| Mains (`l`, `r`) | the cups' rims on the nacelle axis, (±13.16, 2.09, 79.3), exhaust (0, 0, 1), radius 1.0; the dome glows inside the cup |
| Retros (`l`, `r`) | the nacelles' front shoulders beside the necks, (±14.8, 2.09, 68.5), exhaust (0, 0, -1), radius 0.6 |
| RCS | the four fin tips (up or down), the prow (0, 8.8, 0) forward, the bow's flanks at (±2.8, 4.0, 7.0) and the nacelles' outboard flanks at (±15.8, 2.09, 74.0) sideways |
| `cockpit_camera` | in the bow behind the window insets, (0, +8.5, 6.5) |
| `cabin` | the same point, `cabin_range_m` 4 (0.05 L) |
| Port / starboard lights | the arms' outer faces at mid-length, (±14.0, -0.1, 40.0) |
| `top`, `top_lamp` | the spine's crown (0, +13.3, 15.0); lamp (0, +19.5, 40.0), range 24 m |
| Turrets (Q22) | `flank_l` and `flank_r` in the stepped insets high on each flank of the bow, at about (±2.3, +8.45, 6.5), the insets' middle; up (±1, 0, 0), outboard; `arc_deg` 200, `barrel_m` 3.0. Bolts bright green. Exact seats go on the review sheet |
| `cargo_pods[]` | `pod_fwd` (0, 1.70, 24.63), `pod_mid` (0, 1.70, 39.07), `pod_aft` (0, 1.70, 53.57); `up` (0, 1, 0), `forward` (0, 0, -1) |

The thrust line is the nacelle axis (y 2.09), so the centre of mass is trimmed onto it, as on the Saturns. The pods'
axis lies 0.4 m below it, so a loaded and an empty Bokmai trim alike; each pod's mass goes in the manifest's `pod`
entry for T16's `ShipSpec`.

Collision, hull without pods: the bow a box 5.7 x 13.6 x 14 m; the spine a box 5.3 x 3.6 x 33 m and one over the fork;
each strut an oriented box; each post a box 1.6 x 7 x 2.5 m; each lower arm an oriented box for its root and one along
its straight run (it rises 3.3 m); each neck and nacelle a capsule of radius 2.3 m along z; each fin an oriented box;
the spindle a capsule of radius 0.97 m. The pod: one box 17.81 x 11.74 x 13.39 m about its origin, in the manifest's
`pod` entry; its saddles and rails lie inside it, and the side plates stand 0.25 m out, inside the coverage test's
one-spacing margin.

**Chunks** (`core/chunks.py`, cut from LOD1, the pods left out): `bow` (bow, spine to the fork, spindle and drum),
`arm_l`, `arm_r` (the lower arms), `engine_l`, `engine_r` (fork strut, post, neck, nacelle, fins, dome). Each mounted
pod comes off whole as its own debris piece (D59), so a destroyed Bokmai sheds five chunks and up to three pods.

**The `brakiri` style.**

| Role | sRGB | Where |
|---|---|---|
| `hull` | #5A6B59 | the frame: bow, spine, struts, posts, arms, necks, nacelles, fins; the pods' top plates and saddles |
| `hull_dark` | #3A4538 | panel lines, recesses, the spindle and drum, the pods' sleeves and rails |
| `hull_panel` | #ABAE9A | the pods' plating |
| `pod_line` (extra) | #868A78 | the pods' panel lines |
| `stripe` | #D8B840 | the yellow: the upper fins' insets, every fin's top 1.5 m, a band round each neck (z 63.5 to 65.5), the pods' straps, the turret's band and muzzle rings |
| `hazard`, `hazard_dark` | #D8B840, #3A4538 | the pods' side plates (our choice) |
| `canopy_glass`, `canopy_frame` | #1E2620, #3A4538 | any bridge glazing on the bow (our choice; the flank insets are turret mounts) |
| `window` (extra) | #E8F0DC | small windows, if any |
| `nozzle`, `nozzle_throat` | #2E3530, #121512 | the cups' walls and depths |
| `engine_dome` (extra) | #F2EDC4 | the domes |
| `barrel`, `bore`, `interior`, `rcs` | #2E3530, #101210, #101210, #3A4538 | our choice |

Panel grid 2.4 m with 0.25 m lines on the frame, 2.0 m on the pods; tint jitter 0.06. Engine glow yellow-white
#FFF0B0 (`GLOW_SRGB` for T16's `ShipSpec`). Turret bolts bright green (the maintainer, Q22). The frame green is lighter than the Narn's #2E4A3B, but the raider's warning about dark albedo
still applies: T16's GPU check decides whether it needs a lift.

**The turret model** (proposed): a round base 2.4 m across and 0.4 m tall in `hull_dark`; on it a flattened lens-shaped
housing 2.2 m wide, 1.0 m tall and 2.6 m long in `hull`, with a yellow band round its rim; twin barrels 0.24 m across and
0.7 m apart with yellow muzzle rings, the muzzles 3.0 m ahead of the turning axis (`barrel_m` 3.0). About 2 000 splats
at 0.11 m, like the others. The lens shape follows the frame's rounded, organic lines.

**Fidelity.** The mapping for the compare run, with the three pods drawn from `hardpoints.json`:

```
.venv/bin/python3 -I tools/refview/compare.py references/Brakiri_Bokmai_transport_80m.STL brakiri_bokmai --length 80 \
    --right=+x --up=+z --aft=-y --pods-from-hardpoints
```

The arms (2.0 m), struts (2.6 m) and fins (1 to 1.7 m) are only a few spacings across. The verdict scores the mesh, so
build them at their measured size and let the splat check show the reading loss.

## Styles

Three styles, each a `Style` with the required roles plus extras. Hex values are sRGB from the design references;
`styles/raider.py`'s `_lin` converts them to the linear albedo the styles store.

**`ea_civilian`** (the Saturns; the Skylark overrides the plating in its variant data).

| Role | sRGB | Where |
|---|---|---|
| `hull` | #A7A49E | plating: disc, truss, drums, arms, rails, engine section, junction modules |
| `hull_panel` | #8C8B86, patches #75736E | pods |
| `hull_dark` | #55534F | panel lines, recesses, pod end frames and ribs |
| `stripe` | #A33A2E | the red bands on cylinders and tanks, the pods' top stripe |
| `band_light` (extra) | #D9D5CC | the off-white bands |
| `hazard`, `hazard_dark` | #D6AE2A, #262626 | the pods' hazard band, turret bases |
| `disc_ring`, `disc_fin`, `disc_hub` (extras) | #9C4A3C, #3B3735, #E2DED6 | the disc's top face |
| `window` (extra) | #F2E6C8 | the disc rim's windows |
| `canopy_glass`, `canopy_frame` | dark glass, #55534F | bridge glazing |
| `nozzle`, `nozzle_throat`, `rcs` | #4A4946, #1C1B1A, #6E6C68 | bells and RCS ports |
| `barrel`, `bore` | #5A5955, #101010 | turret barrels |
| Skylark override | `hull` #B3A982, `hull_panel` #7E7552, `hull_dark` #4A4536, `stripe` #B8452B, `nozzle` #4A4A46 | its sand plating, red-orange bands and dark nacelle bells and ribs (`skylark_transport.STYLE`) |

Panel grid 3.6 m with 0.4 m lines on the Saturns, 2.4 m with 0.25 m lines on the Skylark; tint jitter 0.06. Engine glow
(a `ShipSpec` tint): Saturns blue-white #DCE8FF, Skylark warm white #FFE9C2.

**`narn`**

| Role | sRGB | Where |
|---|---|---|
| `hull` | #2E4A3B | crescent, cockpit, fins, towers |
| `hull_dark` | #1E2E25 | panel lines, recesses |
| `hull_panel` | #B7BAB5 | the cargo box |
| `stripe` | #A3241C | the red band on each side of the crescent (no emblem) |
| `cargo_panel` (extra) | #4E7552 | the green panel on each side of the box |
| `hazard`, `hazard_dark` | #D2B032, #262626 | the box's corner marks |
| `canopy_glass` | #10201A | the canopy |
| `nozzle`, `nozzle_throat` | #3A3A36, #141413 | tower nozzles |

Panel grid 2.4 m, 0.25 m lines, tint jitter 0.08. Engine glow orange-white #FFB070; turret bolts green (D61's
`WeaponSpec`, per the wiki).

**`centauri`**

| Role | sRGB | Where |
|---|---|---|
| `hull` | #4C3C8E | everything but the trim |
| `hull_dark` | #2B2257 | panel lines, the engine bay's walls |
| `stripe` | #D9B23A | the gold caps on the tip fins, turret collars |
| `trim_light` (extra) | #D7D2E6 | the edge band round the bow's rim |
| `window` (extra) | #F3F1FF | the five windows |
| `nozzle`, `nozzle_throat` | #3A3448, #141218 | main engine and arm-tip nozzles |

Panel grid 2.4 m, 0.25 m lines, tint jitter 0.04 (the liner reads smooth). Engine and fin-tip glow pink-white #FFB8E0;
turret bolts orange. As built (T15): every value as written (Q19); the panel lines are `hull_dark` on the violet, so
the style's line darkness is #2B2257's share of #4C3C8E's albedo (0.35). Roles the design leaves open are our choice:
`hull_panel` the hull violet, `hazard` and `hazard_dark` the gold and the dark violet, `canopy_glass` #1A1530 (unused),
`barrel` and `rcs` #3A3448, `bore` and `interior` #141218. `styles/centauri.py` keeps the glow as `GLOW_SRGB` for
T16's `ShipSpec`.

Two warnings from the raider (`docs/assets-raider.md`): on the RX 6950 XT a dark albedo read as a black silhouette, and
civilians are often seen on their dark side. If the Narn green (#2E4A3B) or the Centauri violet (#4C3C8E) reads black
in T16's GPU check, lift the value and keep the hue, and record the change here.

### Turret models (one per style, D61)

| Style | Model | `barrel_m` |
|---|---|---|
| `ea_civilian` | a round base 3.6 m across and 0.9 m tall, a dome 3.0 m across, twin barrels 0.8 m apart; plating grey, barrels dark. The Skylark uses it at two thirds of that size (`TurretSpec.scaled`), in the Skylark's paint. | 4.5 (Skylark 3.0) |
| `narn` | a six-sided base 2.6 m across, a wedge-shaped housing, twin barrels; dark green with the red band | 3.0 |
| `centauri` | a teardrop pod 2.2 m across on a short stalk, twin barrels with gold collars (as built: see `centauri_brezebel` above) | 2.6 |

## Turret positions

From the design references, authored frame; `up` is (0, 1, 0) for dorsal mounts and (0, -1, 0) for ventral ones.

| Hull | Turrets |
|---|---|
| Saturn 4 transport (2) | `dorsal_fwd` (0, +3.8, 19.1), `dorsal_aft` (0, +9.3, 124.4) |
| Saturn 4 tanker (2) | `dorsal_fwd` (0, +3.8, 19.1), `dorsal_aft` (0, +9.3, 124.4) |
| Saturn 8 transport (2) | `dorsal_fwd` (0, +3.8, 19.1), `dorsal_mid` (0, +7.2, 149.4) |
| Saturn 8 tanker (2) | `dorsal_fwd` (0, +3.8, 19.1), `dorsal_mid` (0, +9.0, 149.4) |
| Saturn 3 (1) | `dorsal_fwd` (0, +3.8, 19.1) |
| Skylark (1) | `dorsal` (0, +3.6, 37.5) on a pedestal 2.1 m across (the body's top is at y 2.87 there); no ventral (Q19) |
| Narn (2) | `tower_l` (-14.85, +9.0, 41.7), `tower_r` (14.85, +9.0, 41.7), on the slotted crowns |
| Brezebel (1) | `dorsal` (0, +4.3, 7.0), on the dorsal fitting's turret ring |

## Open for the human tester `(H)`

- The Narn's up is read from symmetry, the wiki's draught and one capture; flipping it moves the towers under the
  crescent and the box above.
- The Saturn 3's engine section and its raised, wider pod stack are not in its reference; Q16's shared lead ship needs
  them.
- Close fly-bys look soft: about 0.52 m spacing on the Saturns, 0.33 to 0.35 m on the others.
- The Brezebel's violet (#4C3C8E) with its #2B2257 panel lines (35 % of the hull's albedo, about a fifth of the
  surface) is painted as written and may read dark on its shadow side; T16's GPU check decides, and a lift goes to the
  maintainer first.
- The Brezebel's retros fire forward from the bow's rim at (±14.6, 0, 5.7), on the fairings' axis, rather than from the
  fairings' fronts the design first named (inside the arm, where the depth proxy hid the plume); judge where the retro
  plumes show.
