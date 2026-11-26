# Civilian ships: what the generators build (M5-T11, for T12 to T15)

Eight civilian hulls from four generators (D59, Q16): `saturn_family` builds `saturn_3_freighter`,
`saturn_4_transport`, `saturn_4_tanker`, `saturn_8_transport` and `saturn_8_tanker`; `skylark_transport`,
`narn_transport` and `centauri_brezebel` build one hull each. The shapes, sizes and colours come from
`docs/design-references.md` ("Civilian ships (M5)"), measured off the maintainer's reference models with
`tools/refview`. This page turns them into parts, budgets, hardpoints, chunks and styles. It is a plan: T12 to T15 build
against it and replace each section with the as-built numbers, the way `docs/assets-raider.md` reads.

Positions here are in the authored frame of the design references: x to starboard, y up, z aft from the nose tip,
metres, Godot's axes. As with every asset, the generator then centres its meshes and hardpoints on the centroid of the
visible surface (every piece sampled, the parts buried in another left out) and records the shift as
`manifest.centroid_offset`. For the Saturns y is measured from the spine axis; for
the others from the hull's box centre or centre plane, as the design references say.

## Ships are meshes (the maintainer, 2026-11-04)

Gaussian splats are dropped from the project (M4 Q29 to Q31; the M5 directive in the milestone file, `3fb15cc`). Every
civilian ship is drawn as a textured mesh. As built in M5-T27: each generator writes the hull, the turret and the Bokmai's
pod through `core/civilian.py`'s `write_hull` and `write_model`, which call M4's `core/textured_mesh.py`
(`write_textured_mesh`): a UV atlas and four maps (colour, normal, occlusion with roughness and metal, emissive), the
`.glb` and the manifest's `mesh` section, the break-up chunks as cuts of the hull's mesh on its atlas. Godot's importer
builds the levels of detail. The parts, the burial solids, `hardpoints.json` and the collision primitives are unchanged;
the splat levels, lighting records and painted meshes are gone, and so is `core/paint_mesh.py`. The fidelity check
(Q18) scores the `.glb`, what the game draws.

**Textures (the maintainer, 2026-11-04).** Every model's textures come from images from the show of that ship, or of
similar ships where it has none (the Bokmai's from the Brakiri cruiser), so a faction's colour scheme and texture pack
stay consistent: base plating, panel layout, markings, wear, windows and engine glow. One texture pack per style
(`ea_civilian`, `narn`, `centauri`, `brakiri`), each ship's colours and markings on top. The colour schemes and their
sources are already in each ship's section of `docs/design-references.md` (Q11); the texture work adds panel, marking and
wear references from the same images. The images stay references (`reports/refs/<ship>/web/`, gitignored).

**Colour round (the maintainer, 2026-11-04).** From approval shots of every ship from five sides: no ship carries the
painted panel grid any more (every civilian style paints its lines at 1.0 and its tint jitter at 0; panel layout comes
with the texture pack, which M5-T27 added: "Styles" below); the Saturns' greys are cooler and their whites and reds closer to the captures (Achilles.jpg,
Red Star 9.jpg, Epsilon.JPG); the Skylark's plating is a greyer khaki, as Transport 1.png shows it; the Narn green is
lifted (#2E4A3B to #3A5A48, its recesses #1E2E25 to #26392F). The Centauri and Brakiri colours stand as approved.
The shots exposed a colour step in M4-T27's paint shader (`paint_mesh.gdshaderinc`, `paint_colour`): it runs
`srgb_to_linear` on an albedo that is already linear, so a painted mesh reads darker and more saturated than its
written colour (the old Narn green came out #0C180C, nearly black). M4's textured path encodes its albedo map with
`linear_to_srgb` and shows the written colours, so the shots were taken with that step removed, as the textured meshes
will look after the rebase. Anyone who draws the painted meshes before then should drop the step too.

## Output contract

The same as `starfury_aurora` and `raider_fighter` (`docs/architecture.md` §9, §15.11 and §17), per asset id in
`assets/generated/<id>/`:

| File | What it is |
|---|---|
| `<id>.glb` + `<id>_albedo/_normal/_orm/_emissive.png` (and their `.import`) | the hull as a textured mesh, what the game draws: one opaque primitive on a 2 048 px atlas; manifest `files.mesh` and the `mesh` section (`core/textured_mesh.py`); Godot builds its levels of detail |
| `<id>.obj` + `.mtl` | the same triangles: the hull depth proxy, `files.obj` |
| `<id>_chunk_<name>.obj` + `<id>_chunk_<name>.glb` | break-up chunks (`core/chunks.py`): the hull's faces of one group, the `.glb` a cut of the hull's textured mesh on its atlas (it draws with the hull's maps), both centred on the chunk's visible surface |
| `<id>_turret.glb` + its four maps, `<id>_turret.obj` | the style's turret model (D61) in the turret frame: the pivot at the origin, +Y the mount's `up`, the barrels along -Z, on its own 1 024 px atlas |
| `brakiri_bokmai_pod.glb` + its four maps, `brakiri_bokmai_pod.obj` | the Bokmai's cargo pod in its own frame, the origin at its mount |
| `hardpoints.json` | below |
| `manifest.json` | AABB, `centroid_offset`, `files`, `mesh`, `chunks`, `surface_spacing_m` (the visible surface's sampling), `dimensions_m`; a `turret` entry `{obj, mesh, barrel_m, trunnion, muzzles}`; the Bokmai's `pod` entry `{obj, mesh, mass_kg, collision, size_m}` |

## Mesh budgets

The meshes are the parts' own triangles; the texture is one 2 048 px atlas per hull with the normal map at the same size,
VRAM-compressed with mipmaps, and the packer grows the texel until every chart fits. The style's wear, seams and noise
are sized for a fighter at a centimetre a texel and scaled to the hull's texel (`core/civilian.py` `at_texel`), so the
plating reads the same on every hull. As built (M5-T27, seed 42):

| Hull | Length | Triangles | Texel | Atlas fill | Turret triangles |
|---|---|---|---|---|---|
| `saturn_4_transport` | 158.5 m | 45 202 | 14.1 cm | 0.59 | 1 012 |
| `saturn_4_tanker` | 158.5 m | 43 698 | 9.6 cm | 0.67 | 1 012 |
| `saturn_8_transport` | 258.5 m | 54 998 | 19.2 cm | 0.60 | 1 012 |
| `saturn_8_tanker` | 258.5 m | 52 506 | 13.1 cm | 0.70 | 1 012 |
| `saturn_3_freighter` | 96.8 m | 41 518 | 11.3 cm | 0.64 | 1 012 |
| `skylark_transport` | 60 m | 26 052 | 5.2 cm | 0.65 | 1 012 (at two thirds) |
| `narn_transport` | 70 m | 5 692 | 7.1 cm | 0.66 | 388 |
| `centauri_brezebel` | 60 m | 16 810 | 5.8 cm | 0.72 | 2 572 |
| `brakiri_bokmai` (hull) | 80 m | 9 284 | 6.0 cm | 0.71 | 1 296 |
| `brakiri_bokmai_pod` | 13.4 m | 3 284 | 5.6 cm | | |

The tests hold each hull under a triangle budget (70 000 for a Saturn, 35 000 for the Skylark, 25 000 for the Brezebel,
20 000 for the Bokmai, 15 000 for the Narn, 5 000 for a turret or the pod) and its texel at the default atlas under a
bound (20 cm for the Saturns, 8 cm for the Narn, 6 cm for the others). Four maps of 2 048 px, VRAM-compressed with
mipmaps, are about 11 MB per hull type; T16 measures the real figure on the GPU.

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
  at least 97 % of the visible surface samples inside the primitives inflated by one sample spacing, and no primitive
  more than 1 m past the surface's box.
- `cockpit_camera` `{"position", "forward": [0, 0, -1], "up": [0, 1, 0]}` on the bridge and `chase_anchor`
  `{"position"}` at (0, 0.3 L, 1.2 L behind the centroid), L the length: the parser requires both, though nobody flies a
  civilian in M5.
- `nav_lights` `{"port", "starboard", "top", "top_lamp", "top_lamp_range_m", "cabin", "cabin_range_m"}`: port and
  starboard at the widest points near mid-length, `top` on the highest point, `top_lamp` above it with a range of about
  0.3 L, `cabin` at the bridge windows with a range of about 0.05 L.
- `turrets[]` (D61), each `{"name", "position", "up", "arc_deg", "barrel_m"}`, positions from the design references.
  `arc_deg` 200 for a dorsal or ventral mount (a hemisphere plus 10 degrees below its base), 220 for the Narn's tower
  tops.
- `chunks[]`, each `{"name", "obj", "mesh", "offset", "joint"}`, per group below.

### Saturn family

The lead ship gives every variant the same retro nozzles, cockpit, RCS and two turrets:

| Hardpoint | Position (authored frame) |
|---|---|
| Retros (`l`, `r`) | the disc's front rim, (±9.51, 0, 8.56), exhaust (0, 0, -1), radius 0.95 |
| Mains (`l`, `r`) | the bell's exit split in two, (±0.95, 0, length), exhaust (0, 0, 1), radius 2.2; on the Saturn 3's slim engine (Q20, 0.583 scale) (±0.55, 0, length), radius 1.28 |
| `cockpit_camera` | inside the disc's front rim, (0, +0.8, 8.0) |
| `cabin` | the same point, `cabin_range_m` 0.05 L |
| RCS | both ends of the two lower drums at (±9.27, -10.55, z), z 41.9 exhausting -z and 50.1 exhausting +z, and the top drum's aft end (0, +5.55, 50.1) (its front is behind the crossed plates; T12 fix round, 11 ports); the disc's flanks (±14.13, 0, 19.06) exhausting ±x; four on the engine collar 3 m behind its front, (±4.78, 0, z) and (0, ±4.78, z), exhausting outward |
| Turrets | `flank_l` (-14.43, 0, 19.1), up (-1, 0, 0), and `flank_r` (14.43, 0, 19.1), up (1, 0, 0), on slim posts (0.8 m radius) sunk into the disc rim (Q32, which replaced Q19's `dorsal_fwd` on the hub) |

Per variant:

| Variant | Length L | Mains at z | More turrets | Port / starboard | Top, top lamp | Chunks |
|---|---|---|---|---|---|---|
| `saturn_4_transport` | 158.5 | 158.48 | `dorsal_aft` (0, +9.3, 124.4) | the first pods' outboard tips (±53.4, -7.29, 74.3) | (0, +8.9, 75.0), lamp (0, +16.6, 99.4), range 48 m | `bow`, `hull`, `engine`, `pods_l`, `pods_r` |
| `saturn_4_tanker` | 158.5 | 158.48 | `dorsal_aft` (0, +9.3, 124.4) | the lower tanks' flanks (±25.6, -13.53, 99.4) | (0, +8.9, 75.0), lamp (0, +16.6, 99.4), range 48 m | `bow`, `spine`, `engine`, `tank_l`, `tank_r` |
| `saturn_8_transport` | 258.5 | 258.48 | `dorsal_mid` (0, +7.2, 149.4) | (±53.4, -7.29, 74.3) | (0, +8.9, 75.0), lamp (0, +21.5, 149.4), range 78 m | `bow`, `hull_1`, `junction`, `hull_2`, `engine`, `pods_1l`, `pods_1r`, `pods_2l`, `pods_2r` |
| `saturn_8_tanker` | 258.5 | 258.48 | `dorsal_mid` (0, +9.0, 149.4) | (±25.6, -13.53, 99.4) | (0, +8.9, 75.0), lamp (0, +21.5, 149.4), range 78 m | `bow`, `spine_1`, `junction`, `spine_2`, `engine`, `tanks_1l`, `tanks_1r`, `tanks_2l`, `tanks_2r` |
| `saturn_3_freighter` | 96.8 | 96.80 | none (Q19, Q20) | the lower pods' outboard ends (±46.8, -5.46, 79.7) | the top pod's ridge (0, +21.03, 74.08), lamp (0, +27.8, 79.7), range 36 m | `bow` (with the cross-beam and blocks), `pod_top`, `pod_l`, `pod_r`, `engine` (with the truss behind the drum frame) |

Collision, per part (the main shapes; `hardpoints.json` has every primitive): the disc a box 28.26 x 7.6 x 27.63 m with the antenna inside it; each
frame (forward and aft) a box 9.56 x 11.3 x 12.0 m round its members and a box round each side box and plate; the drum
frame a box 21.7 x 19.3 x 8.2 m; each hull cylinder or tank a capsule of radius 8.77 m (it covers the 17.53 x 17.27 m polygon) and
height 81.21 m along z (with its domes); each pod a box 35.2 x 17.22 x 44.8 m (turned for the Saturn 3) that also wraps its rail and blocks; each arm
a box 13.0 x 4.5 x 6.0 m; the engine section a capsule of radius 4.8 m and height 22.6 m; the Saturn 8 transport's
junction a box 15.36 x 13.3 x 24.52 m; the Saturn 8 tanker's three junction modules boxes of 18.3 x 16.8 x 19.1 m.

The Saturns' thrust line is the spine axis, so their centre of mass is trimmed onto it although the cargo hangs below.

### Skylark, Narn and Brezebel

| Hull | Pods (`l`, `r`): main / retro | RCS | Cockpit camera | Port / starboard light | Chunks |
|---|---|---|---|---|---|
| Skylark | main: the bells' exits on the nacelles' axis, (±13.03, -0.26, 55.48), radius 1.62; retro: the intakes' faces, (±13.03, -0.26, 35.64), radius 1.3 (T13: the axis measured off the nacelles; ±13.45, -0.45 was their box with the pods) | the tips of the nacelles' two pods each, the four nose vanes' tips, the corner fins' tips, the dorsal fin's crest and the keel aft (12) | in the bridge plate behind its glazing, (0, +3.6, 11.8) | the nacelles' outboard flanks, (±15.84, -0.26, 46.5) | `capsule` (nose, vanes, capsule, bridge, belly fins, spine, collar, side tanks), `body` (body, corner fins, dorsal fin, centre engine), `nacelle_l`, `nacelle_r` (pods, ribs, claws, pylons) |
| Narn | main: a 0.9 m bell on each tower's aft face (z 43.9), its exit at (±15.0, +5.0, 44.72), radius 1.4; retro: the towers' fronts (the vanes' front face on the thrust line), (±15.0, +5.0, 35.7), radius 1.0 | the prong tips (forward and outboard), the fin tips (up and down), the box's aft corners | in the windscreen block behind the canopy, (0, +1.2, 11.3) | the crescent's widest points (±23.0, 0, 27.0) | `cockpit` (cockpit block, dorsal block, the crescent's centre), `wing_l`, `wing_r` (prong, crescent half, fin, tower), `box` |
| Brezebel | main: the arm tips, (±12.0, 0, 60.0), radius 1.2, in the middle of the arm's flat tip face (z 59.4, x 10.67 to 13.2; T15: at x 12.2 the bell would stand out of it); retro: on the fairings' axis where it leaves the bow's rim, (±14.6, 0, 5.7), radius 1.0, firing forward clear of the hull (T15 review: at the fairing's front, z 22.1, it sat 2.6 m inside the arm and the depth proxy hid its plume) | the twelve blocks on the engine bay's walls (their top or bottom faces, exhausting up or down), the four fins' outer faces near their tips (outboard) | behind the window row, (0, +3.5, 2.5) | the bow's widest points (±19.6, 0, 17.0) | `bow` (bow, dorsal fitting, engine bay, main engine), `arm_l`, `arm_r` (arm, fairing, fins) |

The Narn's thrust line is 5 m above its centre plane, the Brezebel's on it (y -0.105 in the box-centred frame). Centre engines (the Skylark's cone, the
Brezebel's drum) glow but are not pods.

## Fidelity (Q18, T23)

Every civilian model must lie within 90 % of its STL, measured as silhouettes and size. `tools/refview/compare.py` is the
measuring stick: each generator task (T12 to T15, T22) runs it on its asset, fixes what falls under the bar and records
its scores in the table at the end of this section. Turrets are left out (the models have none, and they are not in the
hull's mesh); the Bokmai is scored with its three pods mounted.

**One check.** The verdict scores the model's *geometry*, the triangles of its textured mesh `<id>.glb` (the manifest's
`mesh.file`; `<id>.obj` holds the same triangles and is the fallback), against the STL. Until M5-T27 a second check held
the LOD0 splats to their own mesh; with the splats gone it went too.

| Check | What is drawn | Bar | Shift |
|---|---|---|---|
| Geometry (Q18) | the STL's triangles and the asset's mesh, top (x-z), side (y-z) and front (x-y), on one grid | each view's intersection over union (IoU) at least 0.90, and the mesh's length, width and height each within 10 % of the STL's (a ratio from 0.90 to 1.10) | the mesh may move up to 2 % of the length per axis, reported |

`overlay_<view>.png` shows where the two differ. Exit status is 0 when the check passes, 1 when it fails, 2 on bad input
(an output folder that cannot be written included). The terminal gets one line per view, the sizes, the shift and a
`verdict:` line last.

**How the two are put on one grid.**

- The STL goes through `refview`'s frame with the same `--length`, `--right`, `--up` and `--aft`: x to starboard, y up,
  z aft from the nose tip, x and y centred on the model's box. A generator that authors about another origin shows up as
  a shift beyond the window below. The Saturns measure y from the spine axis, not from the box centre, so they pass
  `--model-offset 0,<dy>,0` (metres added to the model, whole ships only; dy is minus the spine axis's height above the
  model's box centre, pinned per model below). When the silhouettes only meet further away than the window, the tool
  prints a `note` with a value from a wider silhouette search (up to 10 % of the length in x and y).
- The asset's `.glb` (and `.obj`) is written in the Godot frame centred on the visible surface's centroid;
  `manifest.centroid_offset` is the authored position of that centre, which the tool adds back. A test pins this on the
  built raider (its mesh starts at z = 0 with the offset).
- The pixel is 0.25 % of the part's length (`--pixel-frac`, never above 0.5 %). The move is the same for all three views,
  whole pixels, to where they overlap best; it is printed and written to `fidelity.json`, and the scores are taken there
  (`iou_unshifted` is the score without it).

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
    --right=+x --up=+z --aft=-y --pods-from-hardpoints
```

`--pods-from-hardpoints` draws the pod's mesh, the manifest's `pod.mesh.file` (`<id>_pod.glb`) beside the asset
(`--pod-mesh FILE` names another, a `.glb` or an `.obj`), at every `cargo_pods[]` mount of `hardpoints.json`. A mount's `position`, `up` and optional `forward` are in the body frame (the centroid offset removed,
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
at the planes; a plane inside a ship moves a tenth of a millimetre inward so a face lying in
it goes with its neighbour: cut in a gap). Each cropped side then starts at z = 0, and the asset part is moved in x and y
so that its box centre meets the model part's (`part_align_m` in the JSON), so a part placed differently by design, like
the Saturn 3's raised stack, is scored on its shape; the usual 2 % fine shift follows. `--model-offset` is for whole
ships. `--model-scale SX,SY,SZ` scales the cropped model about its own box centre in x and y and its start in z. `--part
NAME` writes the result to `compare/<name>/`. Take the model's ranges from the part tables of
`docs/design-references.md` and the asset's from its own:

```
.venv/bin/python3 -I tools/refview/compare.py references/EA_Saturn_4_transport.stl saturn_8_transport --length 158.48 \
    --right=-x --up=+z --aft=+y --part transport_2 --model-zrange 61.65 149.3 --asset-zrange 161.65 249.3
.venv/bin/python3 -I tools/refview/compare.py references/EA_Saturn_Fuel_tanker.stl saturn_8_tanker --length 255.1 \
    --right=-x --up=+z --aft=+y --part tanks_1 --model-zrange 49.3 146.2 --asset-zrange 49.3 149.3
.venv/bin/python3 -I tools/refview/compare.py references/EA_Saturn_Fuel_tanker.stl saturn_4_tanker --length 255.1 \
    --right=-x --up=+z --aft=+y --part tanks --model-zrange 49.3 136.0 --asset-zrange 49.3 136.0
.venv/bin/python3 -I tools/refview/compare.py references/EA_Saturn_3_Freighter.stl saturn_3_freighter --length 91.13 \
    --right=-x --up=+z --aft=+y --part pod_group --model-zrange 41.5 91.13 --asset-zrange 41.5 96.8 \
    --model-scale 1.2436,1.093,1
```

**Output.** `reports/refs/<ship>/compare/` (`.../compare/<part>/` for a part; gitignored): `overlay_top.png`,
`overlay_side.png` and `overlay_front.png` (STL only in orange, mesh only in blue, both in dark grey, with a legend and a
metre scale) and `fidelity.json` (the mesh file and its triangles, the per-view IoU and pixel counts, dimensions, shift,
part alignment and suggested offset, the thresholds, failures and verdict).

**Saturn model offsets (T12).** The spine axis's height above each model's box centre, read off the model's cylinder or
tank (the Saturn 3: its disc's rim): `--model-offset 0,-3.643,0` for `EA_Saturn_4_transport.stl` (length 158.48),
`0,-2.804,0` for `EA_Saturn_8_transport.stl` (266.2), `0,-6.835,0` for `EA_Saturn_Fuel_tanker.stl` (255.1) and `0,-1.293,0`
for `EA_Saturn_3_Freighter.stl` (91.13). The Saturn 3's pod group is scored against the model's scaled to the shared pod
(`--model-scale 1.2436,1.093,1`, an option T12 added: 43.03/34.6 across, 17.27/15.8 tall, Q20).

**Scores.** One row per ship and part, re-measured on the textured meshes (M5-T27, 2026-11-07, `oscar`; the generators'
default build, seed 42). The geometry is the T12 to T22 geometry, so the numbers match the earlier fallback-mesh scores to
within a pixel; the splat column is gone with the splats.

| Ship | Part | Top IoU | Side IoU | Front IoU | Length | Width | Height | Date |
|---|---|---|---|---|---|---|---|---|
| `saturn_4_transport` | whole ship (`--model-offset 0,-3.643,0`; Q32) | 0.958 | 0.966 | 0.930 | 1.000 | 1.000 | 1.026 | 2026-11-07 |
| `saturn_4_transport` | lead ship (Saturn 4 model z 0-49.3, asset 0-49.3; Q32's flank posts, re-scored on every variant) | 0.959 | 0.919 | 0.913 | 1.000 | 1.021 | 0.985 | 2026-11-07 |
| `saturn_4_transport` | transport section (model 49.3-149.3, asset 49.3-149.3) | 0.955 | 0.984 | 0.917 | 1.000 | 1.000 | 1.026 | 2026-11-07 |
| `saturn_4_tanker` | lead ship (Saturn 4 model z 0-49.3, asset 0-49.3; Q32's flank posts, re-scored on every variant) | 0.959 | 0.919 | 0.913 | 1.000 | 1.021 | 0.985 | 2026-11-07 |
| `saturn_4_tanker` | tank group (tanker model 49.3-136.0, asset 49.3-136.0: the tanks on both sides, the model's junction and the asset's engine left out) | 0.987 | 0.976 | 0.938 | 1.000 | 1.000 | 1.026 | 2026-11-07 |
| `saturn_8_transport` | lead ship (Saturn 4 model z 0-49.3, asset 0-49.3; Q32's flank posts, re-scored on every variant) | 0.959 | 0.919 | 0.913 | 1.000 | 1.021 | 0.985 | 2026-11-07 |
| `saturn_8_transport` | transport section 1 (Saturn 4 model 49.3-137.1, asset 49.3-137.1: the aft frame to the cylinder's end on both sides) | 0.955 | 0.990 | 0.923 | 1.000 | 1.000 | 1.005 | 2026-11-07 |
| `saturn_8_transport` | transport section 2 and engine (Saturn 4 model 61.65-149.3, asset 161.65-249.3: the cylinder's front to the engine on both sides) | 0.967 | 0.991 | 0.923 | 1.000 | 1.000 | 1.005 | 2026-11-07 |
| `saturn_8_tanker` | lead ship (Saturn 4 model z 0-49.3, asset 0-49.3; Q32's flank posts, re-scored on every variant) | 0.959 | 0.919 | 0.913 | 1.000 | 1.021 | 0.985 | 2026-11-07 |
| `saturn_8_tanker` | tank section 1 (tanker model 49.3-146.2, asset 49.3-149.3; the model's sections are 96.96 m apart, Q16's 100 m) | 0.947 | 0.935 | 0.917 | 1.032 | 0.993 | 1.012 | 2026-11-07 |
| `saturn_8_tanker` | tank section 2 and engine (tanker model 146.2-255.1, asset 149.3-258.5) | 0.980 | 0.971 | 0.916 | 1.003 | 0.993 | 1.012 | 2026-11-07 |
| `saturn_3_freighter` | lead ship (Saturn 4 model z 0-41.5, asset 0-41.5; Q32) | 0.962 | 0.905 | 0.941 | 1.000 | 1.021 | 0.990 | 2026-11-07 |
| `saturn_3_freighter` | pod group (Saturn 3 model 41.5-91.1 scaled 1.244, 1.093, 1; asset 41.5-96.8): expected exemption (Q23) | 0.768 | 0.644 | 0.927 | 1.114 | 0.989 | 1.022 | 2026-11-07 |
| `narn_transport` | whole ship (no shift) | 0.991 | 0.985 | 0.974 | 1.000 | 1.000 | 0.997 | 2026-11-07 |
| `brakiri_bokmai` | whole ship with its three pods (`--pods-from-hardpoints`, no shift) | 0.966 | 0.977 | 0.954 | 0.999 | 0.999 | 0.999 | 2026-11-07 |
| `centauri_brezebel` | whole ship (best shift x -0.15 m, the model's fins sit 0.2 m to port; unshifted 0.972, 0.983, 0.945) | 0.965 | 0.983 | 0.970 | 1.000 | 1.000 | 0.999 | 2026-11-07 |
| `skylark_transport` | whole ship (no shift) | 0.979 | 0.980 | 0.956 | 1.001 | 1.000 | 0.998 | 2026-11-07 |
| `ea_shuttle` | whole craft at 38 m (no shift; M10-T57, re-run at T69's size) | 0.984 | 0.984 | 0.971 | 1.000 | 0.999 | 0.998 | 2026-11-23 |
| `ea_atmo_shuttle` | whole craft at 29 m (best shift x +0.07 m, the model's vanes sit 0.15 m to starboard; unshifted 0.979, 0.974, 0.917; M10-T57, re-run at T69's size) | 0.973 | 0.974 | 0.932 | 1.000 | 0.999 | 0.988 | 2026-11-23 |
| `ea_panama` | whole hull at 20 m tall, 121.6 m (no shift; M10-T51, re-run at T71's size) | 0.982 | 0.983 | 0.972 | 1.000 | 0.999 | 1.006 | 2026-11-24 |
| `ea_construction_tender` | whole craft at 8 m (no shift; M10-T55, re-run at T69's size) | 0.934 | 0.959 | 0.926 | 1.000 | 1.000 | 1.000 | 2026-11-23 |
| `centauri_shuttle` | whole craft at 36 m (M10-T58 stage 1) | 0.957 | 0.959 | 0.925 | 1.000 | 1.000 | 0.997 | 2026-11-25 |
| `minbari_flyer` | whole craft at 40 m (Q67; M10-T58, with Q97's pod holes) | 0.941 | 0.972 | 0.912 | 1.000 | 0.999 | 1.000 | 2026-11-26 |

**The generator sections below** record each task as it was built on splats (T12 to T22). Their geometry, hardpoints and
fidelity stand; their splat counts, level shares, lighting records and splat-check numbers are history since M5-T27,
which moved every output to the textured meshes above ("Output contract", "Mesh budgets") and re-scored the fidelity.

## `saturn_family` (T12)

**Fix round (2026-11-04).** The lead ship is traced member by member off the Saturn 4 model's sections rather than the
planned truss: the forward frame is an upper tube and an upper beam a side (the beam forking at z 37 into two bars falling
to the drum frame's middle), a centre beam forking into two bars rising to it, and a lower bar falling to the truss drum,
with a cross of thin plates ahead of the top drum and a box and an upright plate beside it; the aft frame is the forward
frame's mirror about the plane the reference reflects its frames in (z' = 92.1 - z), the truss drum's neck too, its
neck ends carried on to land in the first dome's bracket ring at z 61.3. The drum frame's posts are one 3.2 m plate at z 43.9 and
48.25 with one spoke band a side to the lower drums. The disc's section is elliptic (6.0 x sqrt(1 - (r/R)^2), at least
1.0 m), the corner wedges 2.8 m thick, the neck a box ending at z 32.6 with a 1.3 m keel block. The transport pod's
outline is the end band's (7.74 / 17.22 / 4.73 m at the inboard face, ridge and outboard face), the body 0.8 m in. The
tank sections' A-frames stand at the model's two stations (section z 25.7 and 74.2). Scores in "Fidelity" above. The
tables below are the T11 plan; where they differ, the code and this note are the build.

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
| Turret seat | none built: the turret sits on the body's ridge at (0, 2.766, 37.5), as low as the hull under its 2.4 m base (the ridge is 2.87 on the centre line and falls away aft and outboard), so the base meets the hull all round and its front edge is buried about 0.2 m (`BodySpec.turret_seat`, the `body` piece's `turret` anchor) |
| Nacelles | a `lathe` about (±13.03, -0.26): dark ribbed intake ring, sand body, dark bell with its bore; 16 intake ribs and 24 bell ribs as `prism` plates; two pods as lofts of elliptic sections |
| Claws, pylons | each claw two `section_loft` prongs either side of a `section_loft` web, from stations measured along it; flat `prism` pylons from the nacelle |

Budget at the default spacing of 0.26 m (thin parts are sampled finer, the body a little coarser): LOD0 60 924 splats
(capsule 23 018, body 15 014, each nacelle 11 446), LOD1 15 176, LOD2 3 798, LOD3 962; the turret 2 372 at 0.08 m. The
0.26 m spacing (not the planned 0.33 m) follows from the built surface being smaller than the reference's (no inner
faces). The Godot import test lets a coarse level of a hull whose box is 30 m or more across fall short of LOD0's box by 1.25 of
its spacing, and reach past it by at most max(0.3 m, 0.25 of its spacing) (T14).
Hardpoints: the table above. The centre of mass is on the nacelles' axis, the thrust line. Collision: 44 primitives
(a capsule for the capsule's barrel, boxes elsewhere, oriented boxes for the belly fins, pods and claws); every LOD0
splat centre lies inside them grown by one spacing (the neck ahead of the barrel capsule and the engine's vane ring have
their own boxes).

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
| Thinning to the rim | top 0.62 + 0.137 d, bottom -(0.89 + 0.135 d), d the distance in from the rim; beveled over the last 1.2 m to an edge at y -0.15 (1.84 m thick where the bevel starts, 2.33 m 3 m in; the STL's bevel is about 1.9 m wide and reads 2.2 m 3 m in, T14) |
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

## `brakiri_bokmai` and the `brakiri` style (T22)

`tools/procgen/assets/brakiri_bokmai.py`, `tools/procgen/styles/brakiri.py`, parts in `tools/procgen/parts/brakiri.py`,
built through the shared civilian pipeline `tools/procgen/core/civilian.py` (pieces, mirroring, sampling with burial,
paint, chunk sources, the GDGS flip, level and model writers; the four older generators keep their own copies for now).

**As built (2026-11-03).** 79.95 x 31.60 x 30.88 m. The maintainer confirmed the turret seats, the colours and the bolt
colour on the review sheet (Q19, Q22; `reports/refs/brakiri_bokmai/sheet/`).

| Part | As built |
|---|---|
| Bow | a `section_loft` stacked up y through 24 horizontal sections of the blade (front and rear z, half-widths at 2 to 98 % of the way aft), measured off the STL; the rear is concave in side view; from y 9.9 up it runs on into the spine |
| Flank insets | a `hull_dark` stepped panel on each flank's skin in the inset's measured outline (two strips 1.2 m tall, the upper one further forward); the inset's 0.3 m recess is not cut (under a spacing). The turret's seat is the middle of the full-height step, (±2.04, 8.45, 6.58) |
| Windows | a dark strip at y 10.9 from z 3.5 to 10.5 on each flank with six small windows (0.36 x 0.5 m) |
| Spine | a `section_loft` along z through 11 measured sections (bottom, top and half-widths at nine heights) from inside the crown (z 12) to the fork (z 48) |
| Keel web | the fillet from the keel into each arm's root (lofted out along x through seven sections, z 9 to 15.6), as the keel flares into the arms |
| Lower arms | a rounded section (2.0 x 1.3 m; 2.6 x 1.4 at the root) swept along the measured centre line from inside the keel out to x 12.6 by z 22 and straight aft, rising from y -1.45 to +2.3, into the joint |
| Fork struts, posts | swept rounded sections (2.4 x 2.5 m at the fork to 1.9 x 2.0 at the post); posts 1.6 x 2.5 m at x 12.9, y 3.4 to 11.2 |
| Joints, necks, nacelles | one loft per side through 22 stations (centre, width, height, roundness): the joint, the 2.0 x 4.0 m neck with its yellow band (z 63.5 to 65.5), the nacelle (4.6 x 6.6 m) and its tail closing to the cup's rim at z 78.9; the cup's dark inner wall runs back to its floor at z 76 |
| Engine domes | an ellipsoid 1.70 x 2.83 x 3.89 m in each cup, its aft end at z 80 |
| Fins | `section_loft`s of chamfered plates stacked along y every 0.5 m (measured leading and trailing edges and thickness); yellow top (bottom) 1.5 m and the upper fins' insets |
| Spindle | a `lathe` rod 1.93 m across on (0, 1.70), z 12.5 to 58, with its coupling drum |

| Level | Spacing | Hull | Pod (each) |
|---|---|---|---|
| LOD0 | 0.30 m | 41 924 (`bow` 16 506, each arm 3 999, each engine 8 710; budget 32 000 to 49 000) | 11 644 (9 000 to 14 000) |
| LOD1 (the chunks) | 0.60 m | 10 498 (25.0 %) | 2 906 |
| LOD2 | 1.20 m | 2 622 (6.3 %) | 726 |
| LOD3 | 2.40 m | 644 (1.5 %) | 180 |

Hull and three pods at LOD0: 76 856, over the planned 75 000 by 2.5 % (the new totals are below the plan table). Every piece is sampled at the hull's spacing
(the arms, struts and fins too: the splat check shows the loss, 0.972 side coverage); the inset, windows and domes finer.

The pod files (`brakiri_bokmai_pod.ply`, `_lod1` to `_lod3`, a `.light` each, one `brakiri_bokmai_pod.obj`) keep the
pod's own frame, origin at the mount, +y up, -z forward; GDGS centres an imported PLY on its mean, so each of
`pod.lods[]` carries its `offset`, where that level's mean sits in the pod's frame (LOD0 (0, 0.47, 0); LOD3 (0, 0.68,
-0.14)). Each entry also has its file, lighting record, splats and spacing; `pod` has `mass_kg` 120 000, `size_m` and one
collision box, `body` (18.29 x 12.42 x 14.09 m about (0, 0.16, 0), with the side plates, sleeve and top blocks).

The plan this was built from, from the survey of 2026-11-03 ("Brakiri Bokmai transport" in
`docs/design-references.md`). The maintainer confirmed the bow, the pale green pods and the turrets in the bow's flank insets (Q22), then the
turret seats and the rest of the scheme on the review sheet (as built above). Authored frame as in the design references: y from the model's box centre, z from the prow, so the
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
Bokmai as built 76 856, 886 856 in all. With the hero (975 058), the sky (16 000) and five buoys (38 000) that is
1 915 914, 95.8 % of `settings.splat_budget` (2 000 000) (the plan said 75 000 and 95.7 %). All nine at LOD1 make 221 300, at LOD2 55 360, at LOD3 13 870. The
Bokmai keeps about 80 000 splats resident (LOD0 to LOD3, its chunks and the pod's levels), about 19 MB at M3-T24's
240 bytes a splat. The generated surfaces will come out 10 to 30 % smaller than the reference's, as on the other
hulls, so tune the spacing into the ranges.

**Hardpoints.** In the body frame after the centroid shift, like every hardpoint.

| Hardpoint | Position (authored frame) |
|---|---|
| Mains (`l`, `r`) | on the nacelle axis just behind the engine dome, (±13.16, 2.09, 80.06) as built (the plan's cup rim at z 79.3 was inside the dome, where the depth proxy hides the plume), exhaust (0, 0, 1), radius 1.0 |
| Retros (`l`, `r`) | the nacelles' front shoulders beside the necks, on the skin at (±14.5, 2.09, 67.1) as built (the plan's (±14.8, 2.09, 68.5) was 0.7 m inside), exhaust (0, 0, -1), radius 0.6 |
| RCS | the four fin tips (up or down: (±12.92, 15.45, 71.95) and (±12.92, -15.43, 73.33)), the prow (0, 9.2, 0.06) forward, the bow's flanks on the skin at (±1.67, 4.0, 7.0) and the nacelles' outboard flanks at (±15.8, 2.09, 74.0) sideways (as built; 9 ports) |
| `cockpit_camera` | in the bow behind the window insets, (0, +8.5, 6.5) |
| `cabin` | the same point, `cabin_range_m` 4 (0.05 L) |
| Port / starboard lights | just outside the arms' outer faces at mid-length, (±14.12, -0.15, 40.0) (as built) |
| `top`, `top_lamp` | just above the spine's crown, (0, +13.45, 15.0); lamp (0, +18.97, 40.0), 6.2 m over the spine there, range 24 m (as built) |
| Turrets (Q22) | `flank_l` and `flank_r` in the stepped insets high on each flank of the bow, at (±2.04, +8.45, 6.58), the middle of the inset's full-height step (as built, confirmed on the review sheet); up (±1, 0, 0), outboard; `arc_deg` 200, `barrel_m` 3.0. Bolts bright green #7CFF4F (`styles/brakiri.py` `BOLT_SRGB`) |
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
| `hull` | #5A6B59 | the frame: bow, spine, struts, posts, arms, necks, nacelles, fins |
| `frame_plain` (extra) | #5A6B59 | the pods' top plates and saddles |
| `hull_dark` | #3A4538 | recesses, the spindle and drum, the pods' sleeves and rails |
| `hull_panel` | #ABAE9A | the pods' plating |
| `stripe` | #D8B840 | the yellow: the upper fins' insets, every fin's top 1.5 m, a band round each neck (z 63.5 to 65.5), the pods' straps, the turret's band and muzzle rings |
| `hazard`, `hazard_dark` | #D8B840, #3A4538 | the pods' side plates (our choice) |
| `canopy_glass`, `canopy_frame` | #1E2620, #3A4538 | any bridge glazing on the bow (our choice; the flank insets are turret mounts) |
| `window` (extra) | #E8F0DC | small windows, if any |
| `nozzle`, `nozzle_throat` | #2E3530, #121512 | the cups' walls and depths |
| `engine_dome` (extra) | #F2EDC4 | the domes |
| `barrel`, `bore`, `interior`, `rcs` | #2E3530, #101210, #101210, #3A4538 | our choice |

Texture pack (M5-T27; Brakiri ship.jpg): a mottled satin olive. Darker seams (line darkness 0.7), a mild plate-to-plate
tint (6 %), edges worn to primer (no bare metal), light grime, satin paint (roughness 0.65); the pods take the same pack
on 2.0 m plates. The window strips glow pale green-white and the engine domes yellow-white #FFF0B0 (`GLOW_SRGB`, also
T16's `ShipSpec` tint). Turret bolts bright green (the maintainer, Q22). The frame green is lighter than the Narn's #3A5A48, but the raider's warning about dark albedo
still applies: T16's GPU check decides whether it needs a lift.

**The turret model** (as built, the maintainer's sheet): the inset's full-height step is only 1.6 m long, so a turning
ring 1.6 m across from 0.05 m below the seat to 0.35 m above it in `hull_dark`; on it a lens-shaped housing 2.0 m wide,
0.9 m tall and 2.4 m long (centre 0.8 m up) with a yellow band round its rim; twin barrels 0.24 m across at x ±0.3 with
yellow muzzle rings, the muzzles 3.0 m ahead (`barrel_m` 3.0); 1 602 splats at 0.11 m. The plan was: a round base 2.4 m
across and 0.4 m tall in `hull_dark`; on it a flattened lens-shaped
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

## `ea_shuttle` and `ea_atmo_shuttle` (M10-T57)

`tools/procgen/assets/ea_shuttles.py` (both builds), parts in `tools/procgen/parts/ea_shuttle.py` and
`parts/ea_atmo_shuttle.py`, looks in `tools/procgen/styles/ea_shuttle.py`, built through the shared civilian pipeline
(`core/civilian.py`). Both are **small craft** by the class budgets (`docs/assets-capital.md`, "Class budgets", M10 Q38):
one 2 048 px atlas, the low texture set a mip level down. Neither carries a turret.

**Built at Q65's lengths (M10-T69, 2026-11-23).** The maintainer re-sized the small EA craft: the shuttle **38 m** (it
was modelled at 18.64 m), the atmospheric shuttle **29 m** (modelled at 25.59 m), the construction tender **8 m** (modelled
at 50 m). The parts stay authored at the old size; `Craft.scale` grows the assembled pieces, their seams, plating and paint,
the buried volumes, the collision and every hardpoint by one factor (`core/civilian.py`, `scaled_pieces`), so the
proportions, and the 90 % scores, are the STL's at the new length. The tables below give the **authored** numbers; multiply
positions and sizes by 2.039 (shuttle), 1.133 (atmospheric shuttle) or 0.16 (tender) for the built ones.

**As built (2026-11-20, seed 42; sizes, texels and spacings as T69 builds them).**

| | `ea_shuttle` | `ea_atmo_shuttle` |
|---|---|---|
| Size (L x W x H) | 38.00 x 18.76 x 10.72 m (authored 18.64 x 9.20 x 5.26) | 29.00 x 51.56 x 9.59 m (authored 25.59 x 45.50 x 8.46) |
| Triangles (budget 30 000) | 1 456 | 3 074 |
| Texel, atlas fill | 3.8 cm, 0.74 | 3.5 cm, 0.70 |
| Texture memory, high / low set (budget 16.0 / 6.0 MB) | 13.3 / 3.3 MB | 13.3 / 3.3 MB |
| Video memory on the GPU, high set (RX 6950 XT, read off the sheet run) | about 13 MB | about 14 MB |
| Chunks | `bow`, `cabin`, `stern` | `body`, `wing_l`, `wing_r`, `tail`, `engines` |
| Collision primitives | 65 | 71 |
| Sample spacing (authored 0.20 and 0.25 m, grown with the craft) | 0.41 m | 0.28 m |

| Craft | Parts (authored frame: x to starboard, y up, z aft from the nose, x and y on the reference's box centre) |
|---|---|
| `ea_shuttle` | An octagonal hull lofted through four stations of the tapered nose (z 0.55 to 5.45) and level from there to the stern bulkhead (z 17.41), its centre line 0.31 m under the box centre; it is cut at z 5.45 and 12.8 into the three chunks. On it: the docking and sensor blocks on the nose face (off centre to port, as the reference has them; the only parts that are not mirror symmetric), the cockpit hood with its window, a pipe slab along each nose flank, six framed blocks along each flank, three pipes and a manifold each side of the roof with a ridge between, pipes and boxes under the keel, the raised spine and the tall stern plate with the hatch, three cross fins and a crown box on the roof, a box on each of the four chines aft, the bulkhead's wing plates with the two engine panels, and six flaps flaring out behind the bulkhead to z 18.64. |
| `ea_atmo_shuttle` | A lens-shaped lifting body lofted smooth through 15 stations (a half ellipse over the rim, a deeper one under it, the rim a blunt band at y -0.22), flat at the stern (z 17.95); the canopy spine with its windshield; an intake hump on each shoulder, standing proud at its mouth (z 9.2) and sinking into the body aft; a wing each side through seven sections (root chord 3.2 m at x 9.5, a step in the trailing edge at x 13, the tip at x 22.75 and y 3.2: 15 degrees of dihedral); a thin fin on the centre line carrying the swept tailplane (span 14.6 m); three nacelles on y -0.47 at x 0 and ±4.43, each with a forked vane above and below it. |

**Fidelity (Q10).** Both pass the 90 % rule (the table in "Fidelity" above). The reference's vanes sit 0.15 m to
starboard of their engines; here they are centred on them, which costs the front view a little (0.932).

**Looks (Q11).** The `ea_civilian` texture pack at a small craft's scale (seams 3 cm, plates of mixed size 0.2 to
2.4 m, a scatter of small proud hatches), then the paint. The maintainer chose both from A/B/C sheets on 2026-11-20
(`references/screenshots/M10-T57 EA shuttles/`):

- **EA shuttle: option C**, a worn darker grey (#8D8F8A, panels #73756F, mechanical parts #3F4144), heavier grime and
  edge wear, a **green band** (#2E8B4E) round the nose from z 1.35 to 2.25 with the number **03** (#62D0BE) on the roof,
  five dark slots on each upper chine, the stern panels glowing warm red-white (#FFB89A). Not chosen: A, pale grey-white
  with a red-orange band 25; B, the fleet's grey with a blue band 18 (the show's stills carry all three bands).
- **EA atmospheric shuttle: option C**, the fleet's cool grey (#A4A7AA, panels #8A8D90) with **one red band** (#A8322C)
  across the back from z 5.2 to 6.1 between two thin off-white ones, dark nacelles and vanes, the throats glowing orange
  (#FFB060). Not chosen: A, stained pale grey with two orange-red bands; B, grey and olive camouflage with a cream tail.

**Hardpoints.** The civilians' contract ("Hardpoints" above) with `turrets: []`, plus `docking_ports[]`, each
`{"name", "position", "out", "up"}`: where another hull's lock meets this one and the way out of the hull there.

| | `ea_shuttle` | `ea_atmo_shuttle` |
|---|---|---|
| Thrust line and centre of mass | y -0.31 (the hull's centre line) | y -0.47 (the nacelles' axes) |
| `pods[]` main | `l`, `r`: the engine panels on the bulkhead's wing plates, (±2.36, -0.31, 17.96), radius 0.6 | `l`, `r`: the outer nozzles, (±4.43, -0.47, 21.67), radius 0.6; `cl`, `cr`: the centre nozzle as two halves at x ±0.3, radius 0.3 |
| `pods[]` retro | the nose face, (±1.5, -0.31, 0.55) | the nose's rim, (±2.0, -0.22, 0.8) |
| `rcs[]` | bow and stern flank, roof and keel, each side (12) | the nose rim each side, the outer face of each wing's root at (±11.0, -0.14, 16.17) for the side thrust with a port up and a port down beside it (Q97), nose up and down (10); none at the wing tips (Q93, M10-T58) |
| `cockpit_camera`, `nav_lights.cabin` | behind the hood's window, (0, 1.2, 2.9) | behind the windshield, (0, 0.72, 2.6) |
| `nav_lights` port and starboard, top | the third flank block; the roof's crown box | the wing tips; the tailplane's crest |
| `docking_ports[]` | `stern_hatch` at (0, -0.31, 18.30), out aft | none (no hatch stands out on the reference) |
| Collision | the hull's eight sides as slabs 0.8 m deep per chunk with a core box inside the chines; boxes for the fittings | the lens as 36 patches of its skin (three across each side of crown and keel per run of stations), boxes along the wings' and the tail's sweep, a capsule per nacelle, a box per vane |

Every visible surface sample lies inside a primitive grown by one sample spacing, and no primitive reaches more than
0.5 m past the hull's box (`test_ea_shuttles.py`).

**In the game.** `assets/ships/ea_shuttle.tres` (250 t, two pods of 1.5 MN: 12 m/s², 28/28/42 deg/s, 400 hull points)
and `assets/ships/ea_atmo_shuttle.tres` (115 t, four pods of 0.44 MN: 15 m/s², 33/33/47 deg/s, 300 hull points). T69
scaled T57's numbers by size: mass, thrust and fuel by the length squared (the accelerations stay), inertia by its fourth
power, torque by its cube, turn rates by one over its square root, hull points by the length; first numbers, to be tuned when a mission flies them (M24 makes the shuttle a player ship). Both are catalogue civilians of
`earth_alliance` with `random_pool: false`: `ShipCatalog.is_civilian` holds, but random traffic, encounters and
`random_civilian` spawns do not draw them, so the seeded picks of older scenarios stay as they were; a mission places them
by type. Callsigns `SHUTTLE` and `KESTREL` (TBP's class name for the atmospheric shuttle, Q50).

```
.venv/bin/python3 -I tools/refview/compare.py "references/EA Shuttle.stl" ea_shuttle --length 38 --right=-x --up=+z --aft=+y
.venv/bin/python3 -I tools/refview/compare.py references/EA_Atmospheric_Shuttle.stl ea_atmo_shuttle --length 29 --right=-x --up=+z --aft=+y
```

## `ea_panama` and `ea_construction_tender` (M10-T51, M10-T55)

`tools/procgen/assets/ea_work_ships.py` (both builds), parts in `tools/procgen/parts/ea_panama.py` and
`parts/ea_construction_tender.py`, looks in `tools/procgen/styles/ea_work_ships.py`, built through the shuttles'
`build_craft` on the shared civilian pipeline (`core/civilian.py`). Both are unarmed (Q49, Q53).

**Lopsided hulls.** The pipeline gained a third side for a piece, `LONE`: built where it is authored, neither symmetrised
(`CENTRE`) nor mirrored (`RIGHT`). Every piece of the Panama is `LONE`; on the tender the claws, the shoulder blocks and
the landing gear are. The body origin stays on the reference box's centre plane (x = 0).

**Classes (Q38).** The Panama is a **cruiser**: one 4 096 px atlas. It is a civilian, but 122 m long (T71, Q66: 20 m tall) and it flies into
Babylon 5's docking bay, so it is seen from a few metres; a 2 048 px atlas would put a texel at 7 cm. The tender is a
**small craft**: one 2 048 px atlas. Both write the low texture set a mip level down.

**As built (2026-11-21, seed 42).**

| | `ea_panama` | `ea_construction_tender` |
|---|---|---|
| Size (L x W x H) | 121.59 x 30.28 x 20.00 m (T71, Q66; authored 180.00 x 44.83 x 29.61, 41.7 x 26.3 without the aerials; its part and hardpoint numbers below are the authored ones, times 0.6755 as built) | 8.00 x 11.15 x 3.84 m (T69, Q65; authored 50.00 x 69.70 x 24.01, its part numbers below are the authored ones, times 0.16 as built) |
| Triangles (budget) | 3 862 (60 000) | 11 712 (30 000) |
| Texel, atlas fill | 3.5 cm (5.2 cm at 180 m), 0.72 | 1.0 cm (a fighter's), 0.66 |
| Texture memory, high / low set (budget) | 53.3 / 13.3 MB (56.0 / 16.0) | 13.3 / 3.3 MB (16.0 / 6.0) |
| Video memory on the GPU, high / low set (RX 6950 XT, read off the sheet runs) | about 53 / 13 MB | about 14 / 4 MB |
| Chunks | `bow`, `hold_fore`, `hold_aft`, `stern` | `body`, `stern`, `boom_l`, `boom_r`, `claws_l`, `claws_r` |
| Collision primitives | 49 | 92 |
| Sample spacing | 1.01 m (authored 1.5 m) | 0.064 m (authored 0.4 m) |

| Craft | Parts (authored frame: x to starboard, y up, z aft from the bow, x and y on the reference's box centre) |
|---|---|
| `ea_panama` | The **hold** (z 43.3 to 153.9, cut at 98 into two chunks): a wedge in section, mirrored top to bottom about y -0.175: a flat port face at x -20.85, a round tube (radius 3.3) along its upper and its lower edge, the roof falling 0.215 a metre to a blunt starboard edge at x 19.3; open aft, with a wall set 4.4 m into it. On it: a raised band along the port face, a plate over its after end (the cargo lock), a broad slab and a small one on the roof and under the keel aft. The **fore body** (z 21.6 to 43.3): the same wedge smaller, with a tube along its starboard edge whose nose stands forward of it. The **bow spine** on the port side (x -15, z 0 to 21.6) with a tapered nose, a fairing and rods. The **stern**: an octagonal core to z 169, an engine each side of it (x -11.7 and 11.5: a drum, a waist, a bell to z 180, four rails), a flattened tank above and below the core, two drums by the port engine, a disc tank on the port side. Six thin aerials at two stations (no hit volume). |
| `ea_construction_tender` | The **body**: a hexagonal prism (x ±5.7, y -5.9 to 7.1, z 14.8 to 36.5) with a glazed pyramid nose (tip at z 9.6), a box and four tubes along its corners, housings at the bow corners with canted drums, shoulder blocks (z 26.9 to 32; the two sides differ in height, as the reference). Two **grab arms** on the centre line (y 7.1 and -5.6, z 0 to 15). The **stern** block (z 36.5 to 46.3) with a fan panel, two domes and two pointed tanks. A **boom** each side (x 4 to 27.2, z 38.5 to 43.3): four chords falling 0.035 a metre outboard, six leaning uprights fore and aft, cross bars, a zigzag of diagonals over and under, two tanks inside. A **pod** at each tip (x ±29.92, y 4.646, z 32.2 to 50): a drum between two collars, a bell at each end, three small thrusters. Four **claws**, each three sickle blades 16.6 m long at 120° round its own axis on an arm from a ball joint; the starboard pair points 24° outboard, the port pair 30°. The **landing gear**: a mount, four legs and feet, 0.95 m to port of the centre line. |

**Fidelity (Q10).** Both pass the 90 % rule (the table in "Fidelity" above). The tender's claws were placed by a fit of
each claw's three silhouettes against the reference's (hub, axis and roll), since the reference poses the two sides
differently. What the tender's front view loses is the reference's pipe runs and brackets inside the boom.

**Looks (Q11).** The `ea_civilian` texture pack, then the paint. The maintainer chose both from A/B/C sheets on 2026-11-21
(`references/screenshots/M10-T51 T55 Panama and tender/`):

- **Panama: option B**, the still in open space: a warm brown-grey (#8A7F72, tubes #6E655C) that wanders strongly from
  plate to plate (plates 1 to 9 m), a **pale roof and keel** (#B5AB9B) with five cargo hatches each, dark tanks
  (#5C5650), two rows of lit ports along the port face and one each side of the bow spine, the throats warm white
  (#FFC8A0). Not chosen: A, dark grey with a lighter roof and tan tanks; C, near-black with red trim and bands.
- **Construction tender: option A**, the still's work pods: yellow ochre all over (#C29A2C, panels #A5852A), grey
  machinery (#45464A), pale tanks, **yellow claws and grabs striped black**, four black bands round each pod, the after
  bells cold blue-white (#BFD8FF). Not chosen: B, fleet grey with yellow tools; C, worn orange with dark claws.

**Engine glow.** Only the throat's plate and a 1 m collar round it are lit in the Panama's bells; their insides are dark
metal (a Saturn's bell is lit all the way to its lip). From astern at 60 m the two throats show less lit area than one
Saturn 8 bell (the look sheet's last row). On the tender only the pods' after bells are lit; the forward ones brake.

**Hardpoints.** The shuttles' contract (`turrets: []`, `docking_ports[]`).

| | `ea_panama` | `ea_construction_tender` |
|---|---|---|
| Thrust line and centre of mass | y -0.175 (the section's mirror line), x 0 | y 4.646 (the pods' axes), x 0 |
| `pods[]` main | `l`, `r`: the throats, (-11.7 and 11.5, -0.175, 175.0), radius 1.55 | `l`, `r`: the pods' after bells, (±29.92, 4.646, 48.6), radius 1.4 |
| `pods[]` retro | the fore body's face, (±4.0, -0.175, 21.6) | the pods' forward bells, (±29.92, 4.646, 33.5) |
| `rcs[]` | four round the fore body, four round the hold's after end (8) | three thrusters round each pod, two on each bow housing (10) |
| `cockpit_camera`, `nav_lights.cabin` | in the bow spine, (-15.0, 0, 9.5) | behind the nose's glass, (0, 0.7, 13.6) |
| `nav_lights` port and starboard, top | the port band and the starboard edge amidships (not mirror images); the upper tube's crown | the pods' outboard thrusters; the stern's domes |
| `docking_ports[]` | `port_lock` at (-22.4, -0.175, 142.7), out to port: the plate on the port side aft | none |
| Collision | per hull section a tall port box, boxes stepping down to starboard and a slab lying in the roof and one in the keel; boxes for the fittings, a capsule and a box per engine | boxes and slabs for the hexagon's sides, a capsule per arm, leg and pod, three boxes along each blade's sickle (36 in all) |

Every visible surface sample lies inside a primitive grown by one sample spacing, and no primitive reaches more than
0.5 m past the hull's box (`test_ea_work_ships.py`); the Panama's aerials are left out of it.

**In the game.** `assets/ships/ea_panama.tres` (4 930 t, two engines of 2.465 MN: 1.0 m/s², 1.1/1.5/3 deg/s, 185 hull
points; T71 took T51's 16 000 t, 600 points, fuel and RCS force by the volume left, x 0.308 (Q74), and its inertia and RCS torque
by the fifth power of the scale, so every acceleration and turn rate holds) and `assets/ships/ea_construction_tender.tres` (10 t, two pods of 10 kN: 2.0 m/s², braking at half that,
30/30/45 deg/s, 50 hull points; T69 scaled T55's 50 m numbers to 8 m as the shuttles'); first numbers, to be tuned when a mission flies them. Hull points and "unarmed" are
T03's (`data/capitals/loadouts.json`, where the Panama's class is now `cruiser`, as its budget). Both are catalogue
civilians of `earth_alliance` with `random_pool: false` and no docking class: random traffic, encounters and station
traffic do not draw them, so older scenarios' seeded picks stay as they were; a mission places them by type. Callsigns
`PANAMA` and `TENDER`.

```
.venv/bin/python3 -I tools/refview/compare.py "references/EA Panama class.STL" ea_panama --length 121.6 --right=-x --up=+z --aft=+y
.venv/bin/python3 -I tools/refview/compare.py references/EA_construction_tender.stl ea_construction_tender --length 8 --right=-x --up=+z --aft=+y
```

## `centauri_shuttle` and `minbari_flyer` (M10-T58)

`tools/procgen/assets/centauri_shuttle.py` and `assets/minbari_flyer.py`, parts in `tools/procgen/parts/centauri_shuttle.py` and
`parts/minbari_flyer.py`, looks in `tools/procgen/styles/centauri_shuttle.py` and `styles/minbari_flyer.py`, built through the
shuttles' `build_craft` (`assets/ea_shuttles.py`). Both are **small craft** (M10 Q38): one 2 048 px atlas, the low texture set a
mip level down. The shuttle wears its chosen look (Q89); the Flyer wears `p1`, the bluer of the three patterns
the maintainer was shown (Q90), its only look. The shuttle is unarmed on a reaction drive (Q93); the Flyer carries two plasma
guns on a gravitic drive (Q91, Q92).

**As built (2026-11-25, seed 42).**

| | `centauri_shuttle` | `minbari_flyer` |
|---|---|---|
| Size (L x W x H) | 36.00 x 51.96 x 13.47 m | 40.00 x 18.46 x 8.20 m (Q67's length; T01 had 29.19) |
| Triangles (budget 30 000) | 3 774 (1 794 without the wing lamps) | 7 596 |
| Texel | 3.4 cm | 3.5 cm |
| Texture memory, high / low set (budget 16.0 / 6.0 MB) | 13.3 / 3.3 MB | 13.3 / 3.3 MB |
| Video memory on the GPU, high set (RX 6950 XT, sheet run) | about 13 MB | about 14 MB |
| Chunks | `body`, `stern`, `wing_l`, `wing_r` | `body`, `bow`, `tail`, `crossbar`, `spindle_l`, `spindle_r` |
| 90 % compare: top, side, front IoU | 0.957, 0.959, 0.925 | 0.941, 0.973, 0.913 |

| Craft | Parts (authored frame: x to starboard, y up, z aft from the nose, x and y on the reference's box centre) |
|---|---|
| `centauri_shuttle` | A flat delta body lofted with hard edges through 12 stations: flat deck faces from the centre line to a blunt rim, a keel that bulges a little at half width, deeper aft (y -2.8 at the nose, -5.75 at the stern face, z 33.6); the half width grows from 2 m to 9 m at z 20.5 and on to 15 m along the wing roots. On it: a spine from z 6.3 to 34.8 with the canopy on its first runs; a blister either side (x 3.66, 12 m long); five louvres either side at z 29.4 to 33.8 with gold tops. Under the stern a keel pod (y -5.9) on a strut; one nozzle either side of it (x 3.3, y -2.28, radius 2, exit z 35.5). The wings: eight sections from x 11.5 inside the body to the tips at x 26 and y 6.6, the leading edge swept from z 23.6 to 32, the trailing edge at z 35.5 to 36; gold leading edges; nine round lamps (radius 0.28 m) along each trailing edge, for a style with a `running_light` finish. |
| `minbari_flyer` | Smooth lofts of ellipses (Q47). A round fuselage (radius 3.05 at z 8 to 10, 0.85 from z 28 to 35, the tail spike to z 39.6), its nose a ring of 12 petals; a pod either side (x 3.8, z 3.3 to 18.4), a thin web from it to a tall blade at x 8.15 (4.1 m above and below its middle at z 4, a diamond with hollow sides in section) with a lobe at its root and two intake pods on its front; a flat strake along each flank from z 18 to 33 with a rod at x 1.3 to the tail; four waist pods (x 2.25, y 1.0, z 22 to 30); the crossbar (z 30 to 34.7, 16.6 m across) with a spindle at each tip (x 8.3, z 29.3 to 40, 3.6 m above and below), its tail glowing from z 37, and a forward tube. |

**The references differ from T01's descriptions.** The Centauri shuttle's STL has no tail fin: the tall swept shape in its side
view is the upswept wing tip. It carries one large nozzle either side of the keel. The Flyer's blades and spindles are diamonds in
section, wide at their middle and thin at their edges.

**Looks.** Sheets in `references/screenshots/M10-T58 Centauri shuttle and Minbari Flyer/`.

- **Centauri shuttle: D2, chosen by the maintainer (2026-11-25, Q89).** Violet #7540B0 (machinery #3A1F60), between the earlier,
  too dark "Centauri violet" #5A3A86 and the too bright #8A44D0, with a touch of the stills' magenta. Q83's skin as a soft mottle:
  darker clouds at 6, 2.4 and 0.9 m (seeded noise, the edges blended; no plates, no seam lines). Gold (#DEBA60) on the deck: three
  lines across it and one along each side, 44 small panels of mixed size, a crest of our own either side of the spine (a ring open
  at the top round a rising crescent and a spike, on a bar); a 0.5 m brass strip (#B8913E) down the middle of the violet spine;
  gold on the louvres' tops and the wings' leading edges. Nine round lamps glow red with an orange tinge (#FF3418) along each
  wing's trailing edge, readable at 60 m; the nozzles glow pink-white. Option sheet of the last round:
  `centauri_shuttle_option_sheet.png`; D2's views: `shots/centauri_shuttle_d2_top.png`, `_d2_60m.png`.
- **Minbari Flyer: pattern P1, accepted by the maintainer (2026-11-25, Q90).** The hexagonal grid (Q45) on every surface; a
  low-gloss pale grey-blue body (#A4C4F2); a dark blue line running lengthwise, meandering a little, only on the fuselage, the two
  pods and across the crossbar; thick, uneven curved bands branching from it (and, without a line, on the waist pods, webs and
  strakes) towards the lobe's edges, tapering and fading, each a violet purple core (#7A3CB6) inside a blue outline about 2.2 m
  wide at the root that fades into the body (`assets/minbari_flyer_pattern.py`); the blades and spindles darker blue under the
  same bands, their outboard faces bright blue with purple bands; a soft mottled blue glow under the crossbar from 16 overlapping
  pools of light. Sheet: `minbari_flyer_p1_round3_sheet.png`.

**Hardpoints (stage 2).** The shuttles' contract (above), authored frame; neither has a `docking_ports[]` entry: both land in
bays (Q93).

| | `centauri_shuttle` | `minbari_flyer` |
|---|---|---|
| Thrust line and centre of mass | y -2.28 (the nozzles' axes) | y 0 (the spindles' axes) |
| `pods[]` main | `l`, `r`: the two nozzles either side of the keel, (±3.3, -2.28, 35.5), radius 1.6 | `l`, `r`: the spindles' tails, (±8.3, 0, 40); the gravitic drive, drawn with no plume |
| `pods[]` retro | the nose, (±1.2, -2.25, 1.0), radius 0.3 | each bow blade's nose, (±8.15, 0, 0.3), between its two thruster pods, which draw it (Q97) |
| `rcs[]` | the nose each side, up and down; the side thrust on the outer (lower) face of each wing's root, (±16.0, -0.62, 31.0), with a port up and a port down beside it at x ±17.0 (Q97), the root ports 0.2 m in radius; none at the wing tips (10, Q93) | each blade's two thruster pods, (±8.2, ±1.15, 0), firing forward from their holes and tagged `retro` (they draw their side's braking), radius 0.34; the small pod inside each blade, (±7.05, 0, 1.45), a vectored port: `"vector"` 85° up and down, 80° inboard, 20° outboard, radius 0.27 (6, Q97) |
| `muzzles[]` | none (Q93) | `l_gun`, `r_gun` in the holes of the gun pods either side of the fuselage, (±3.8, 0, 3.95), firing forward (Q91, Q97) |
| `cockpit_camera`, `nav_lights.cabin` | behind the canopy, (0, 0.2, 8.6) | in the bow, (0, 1.4, 4.2) |
| `nav_lights` port and starboard, top | the wing tips; the spine's crown aft | the spindles' flanks; the fuselage's crown |
| Chunks | `body`, `stern`, `wing_l`, `wing_r` | `body`, `bow`, `tail`, `crossbar`, `spindle_l`, `spindle_r` |
| Collision | 28 boxes: the body's runs, the spine, blisters, louvres, keel pod and nozzles; each wing a box per pair of sections, leaning with its rise but square to the hull's length (the tip's upright) | 35 boxes: the fuselage's runs; per side the pod, web, the blade in three runs, its root lobe and two intake pods, the strake, rod and two waist pods, the spindle in two runs and its tube; the crossbar |

Every visible surface sample lies inside a box grown by one sample spacing, no box reaches more than 0.5 m past the hull's
own box, and every port, retro and muzzle lies on the surface (`test_centauri_minbari_craft.py`). Stage 2 found and closed the
gaps: the Flyer's pods (boxed at 0.8 of their size), blades (their ends, root lobes and intake pods), waist pods and spindles
(their pointed ends); the shuttle's wing boxes turned with the sweep and stood 0.9 m past the straight trailing edge.

**In the game (stage 2; first numbers from size and mass as T57's, to be tuned when a mission flies them, Q93).**

| | `assets/ships/centauri_shuttle.tres` | `assets/ships/minbari_flyer.tres` |
|---|---|---|
| Mass (the generator's estimate) | 87 t | 73 t |
| Drive | `reaction`: two pods of 0.61 MN (14 m/s²), retros 0.2 MN each (4.6 m/s²) | `gravitic`, fraction 0.5: two pods of 0.65 MN (17.8 m/s²; a Starfury 30), braking 0.325 MN each (8.9 m/s²) |
| Sideways and vertical thrust | 0.435 MN (5 m/s²) | 0.433 MN sideways (5.9 m/s²), 0.65 MN vertical (8.9 m/s²; a Starfury 15) |
| Turn rates (pitch, yaw, roll) | 30, 30, 40 deg/s | 40, 40, 55 deg/s (a Starfury 60, 60, 90) |
| Inertia; RCS torque | (10.6, 11.4, 7.6) x 10⁶ kg m²; (9.3, 10.0, 6.7) MN m | (7.5, 9.0, 1.9) x 10⁶ kg m²; (9.0, 10.8, 2.9) MN m |
| Hull points (`loadouts.json`) | 250 | 300 |
| Guns | none | `assets/weapons/minbari_flyer_plasma.tres`: the Starfury's `pulse_cannon_ef` numbers (10 a bolt, the pair 8 shots a second, 1 000 m/s, the same capacitor) as green-gold Minbari bolts |
| Plumes | pink-white, from the two main nozzles at 3.2 times the Starfury's size (`main_plume_scale`: 1.28 m across the root, 8.3 m long), retros and RCS as every small craft | none from the drive: its nozzle lights follow the thrust and the spindles' tails glow on the hull; plumes from the blades' four forward pods when it brakes or turns, and from the inner pods, swung against the thrust, when it slides sideways or vertically (Q97) |

`ShipSpec.main_plume_scale` (new, default 1) sizes a hull's main plumes against the Starfury's. `ShipSpec.propulsion`
`gravitic` on a fighter or civilian ship now means its main nozzles draw no plume (`ThrusterVisuals.main_plumes`); it flies by
its own thrust numbers like any other. Both craft are catalogue civilians (`centauri`, `minbari`), `finalized` and parked in the ship
line-up, and `traffic_only` (Q97): out of `ShipCatalog.civilian_types`, so the scenarios made before them keep their seeded
hulls, and in the traffic of a scenario whose encounter pools list them (free flight: two of each). They do not dock at
Babylon 5; on the station's run they fly out to the gate. The shuttle flies the `civilian` profile; the Flyer flies
`civilian_armed`: it runs first and turns on one pursuer it cannot shake (after 8 s, the pursuer no more than three times its
size, its own hull above half). The Flyer's bow pods open forward in modelled holes with dark insides (the inner pods' a
rounded rectangle). An `rcs[]` port may carry `radius` (m), the tag `retro` (it draws its pod's braking thrust in place of the
pod's own retro nozzle) and `vector` (`up_deg`, `down_deg`, `left_deg`, `right_deg`: how far its plume swings against the side
thrust asked). The Kestrel's wing-tip RCS moved to its
wing roots in the same change (Q93, table above).

Tests: `test_centauri_minbari_craft.py` and `test_ea_shuttles.py` (129 together) and
`tests/integration/test_centauri_minbari_craft.gd` (6: import with the low set, flight, the Flyer's drive, blade pods and
vectored inner pods, its guns against a Starfury's and the shuttles' plumes and wing-root ports, in play and break-up, the
armed Flyer against a raider). Both in flight: `references/screenshots/M10-T58 Centauri shuttle and Minbari Flyer/stage2/`; how they look is (H).

```
.venv/bin/python3 -I tools/refview/compare.py references/Centauri_Shuttle.stl centauri_shuttle --length 36 --right=+y --up=+z --aft=+x
.venv/bin/python3 -I tools/refview/compare.py references/Minbari_Flyer_diplomat_transport_40m.stl minbari_flyer --length 40 --right=+y --up=+z --aft=+x
```

## Styles

Four styles, each a `Style` with the required roles plus extras and the faction's texture pack (M5-T27): plating, seams,
wear and the lit roles, at a fighter's scale, scaled to each hull's texel. Hex values are sRGB from the design references;
`styles/raider.py`'s `_lin` converts them to the linear albedo the styles store.

**`ea_civilian`** (the Saturns; the Skylark overrides the plating in its variant data).

| Role | sRGB | Where |
|---|---|---|
| `hull` | #A4A7AA | plating: disc, truss, drums, arms, rails, engine section, junction modules |
| `hull_panel` | #8A8D90, patches #72757A | pods |
| `hull_dark` | #4F5256 | recesses, pod end frames and ribs |
| `stripe` | #A8322C | the red bands on cylinders and tanks, the pods' top stripe |
| `band_light` (extra) | #DADCDE | the off-white bands |
| `hazard`, `hazard_dark` | #D6AE2A, #262626 | the pods' hazard band, turret bases |
| `disc_ring`, `disc_fin`, `disc_hub` (extras) | #9A5248, #3B3735, #E2E3E4 | the disc's top face |
| `window` (extra) | #F2E6C8 | the disc rim's windows |
| `canopy_glass`, `canopy_frame` | dark glass, #4F5256 | bridge glazing |
| `nozzle`, `nozzle_throat`, `rcs` | #4A4946, #1C1B1A, #6E6C68 | bells and RCS ports |
| `barrel`, `bore` | #5A5955, #101010 | turret barrels |
| Skylark override | `hull` #A9A68E, `hull_panel` #7A7659, `hull_dark` #4A4839, `stripe` #B8452B, `nozzle` #4A4A46 | its grey khaki plating, red-orange bands and dark nacelle bells and ribs (`skylark_transport.STYLE`) |

Texture pack (M5-T27; Achilles.jpg, Red Star 9.jpg, Epsilon.JPG, Transport 1.png): clean industrial paint. Long plates
with fine dark seams (line darkness 0.72) and a few hatches, a light plate-to-plate tint (5 %), edges worn to dark primer
(no bare metal), faint grime and short streaks, flat paint (roughness 0.72), light rivets. The Skylark's plating is finer
(2.4 m) and more patched (10 % tint), as Transport 1.png shows it. The rim windows glow warm white (#F2E6C8, strength 2)
and the engine throats glow (strength 3): Saturns blue-white #DCE8FF, Skylark warm white #FFE9C2 (also `ShipSpec` tints).

**`narn`**

| Role | sRGB | Where |
|---|---|---|
| `hull` | #3A5A48 | crescent, cockpit, fins, towers |
| `hull_dark` | #26392F | recesses |
| `hull_panel` | #B7BAB5 | the cargo box |
| `stripe` | #A3241C | the red band on each side of the crescent (no emblem) |
| `cargo_panel` (extra) | #4E7552 | the green panel on each side of the box |
| `hazard`, `hazard_dark` | #D2B032, #262626 | the box's corner marks |
| `canopy_glass` | #10201A | the canopy |
| `nozzle`, `nozzle_throat` | #3A3A36, #141413 | tower nozzles |

Texture pack (M5-T27; Tal'Quith.JPG, Tal'Quith's collision.JPG, Na'Tan.JPG): hard-used plating. Big plates with dark
seams (line darkness 0.62) and a strong plate-to-plate tint (9 %), chipped edges with some bare metal (0.25), grime and
long streaks aft, matte paint (roughness 0.8); the cargo box takes the same wear. The engine throats glow orange-white
#FFB070 (strength 3); turret bolts green (D61's `WeaponSpec`, per the wiki).

**`centauri`**

| Role | sRGB | Where |
|---|---|---|
| `hull` | #4C3C8E | everything but the trim |
| `hull_dark` | #2B2257 | the engine bay's walls |
| `stripe` | #D9B23A | the gold caps on the tip fins, turret collars |
| `trim_light` (extra) | #D7D2E6 | the edge band round the bow's rim |
| `window` (extra) | #F3F1FF | the five windows |
| `nozzle`, `nozzle_throat` | #3A3448, #141218 | main engine and arm-tip nozzles |

Texture pack (M5-T27; Centauri Liner.jpg): the liner's polished paint. Fine seams barely darker
than the paint (line darkness 0.82), an even tint (3 %), little wear, no bare metal, glossy paint (roughness 0.42), no
rivets. The five windows glow white (strength 2) and the engine throats pink-white #FFB8E0 (strength 3); the fin-tip
lights and the engine flame are T16's. Turret bolts orange. As built (T15): every value as written (Q19). Roles the design leaves open are our choice:
`hull_panel` the hull violet, `hazard` and `hazard_dark` the gold and the dark violet, `canopy_glass` #1A1530 (unused),
`barrel` and `rcs` #3A3448, `bore` and `interior` #141218. `styles/centauri.py` keeps the glow as `GLOW_SRGB` for
T16's `ShipSpec`.

Two warnings from the raider (`docs/assets-raider.md`): on the RX 6950 XT a dark albedo read as a black silhouette, and
civilians are often seen on their dark side. If the Narn green (#3A5A48) or the Centauri violet (#4C3C8E) reads black
in T16's GPU check, lift the value and keep the hue, and record the change here.

### Turret models (one per style, D61)

| Style | Model | `barrel_m` |
|---|---|---|
| `ea_civilian` | a round base 3.6 m across and 0.9 m tall, a dome 3.0 m across, twin barrels 0.8 m apart; plating grey, barrels dark. The Skylark uses it at two thirds of that size (`TurretSpec.scaled`), in the Skylark's paint. | 4.5 (Skylark 3.0) |
| `narn` | a six-sided base 2.6 m across, a wedge-shaped housing, twin barrels; dark green with the red band | 3.0 |
| `centauri` | a teardrop pod 2.2 m across on a short stalk, twin barrels with gold collars (as built: see `centauri_brezebel` above) | 2.6 |
| `brakiri` | a 1.6 m turning ring, a lens housing 2.0 x 0.9 x 2.4 m with a yellow band, twin barrels with yellow muzzle rings (as built: see `brakiri_bokmai` above) | 3.0 |

## Turret positions

From the design references, authored frame; `up` is (0, 1, 0) for dorsal mounts, (0, -1, 0) for ventral ones and (±1, 0, 0) outboard for the Saturns' flank pair (Q32).

| Hull | Turrets |
|---|---|
| Saturn 4 transport (3) | `flank_l` (-14.43, 0, 19.1), `flank_r` (14.43, 0, 19.1), `dorsal_aft` (0, +9.3, 124.4) |
| Saturn 4 tanker (3) | `flank_l` (-14.43, 0, 19.1), `flank_r` (14.43, 0, 19.1), `dorsal_aft` (0, +9.3, 124.4) |
| Saturn 8 transport (3) | `flank_l` (-14.43, 0, 19.1), `flank_r` (14.43, 0, 19.1), `dorsal_mid` (0, +7.2, 149.4) |
| Saturn 8 tanker (3) | `flank_l` (-14.43, 0, 19.1), `flank_r` (14.43, 0, 19.1), `dorsal_mid` (0, +9.0, 149.4) |
| Saturn 3 (2) | `flank_l` (-14.43, 0, 19.1), `flank_r` (14.43, 0, 19.1) |
| Skylark (1) | `dorsal` (0, +2.766, 37.5), seated on the body's ridge; no ventral (Q19) |
| Narn (2) | `tower_l` (-14.85, +9.0, 41.7), `tower_r` (14.85, +9.0, 41.7), on the slotted crowns |
| Brezebel (1) | `dorsal` (0, +4.3, 7.0), on the dorsal fitting's turret ring |
| Bokmai (2) | `flank_l` (-2.04, +8.45, 6.58), `flank_r` (2.04, +8.45, 6.58), in the bow's flank insets, up (∓1, 0, 0) outboard (Q22) |

## Surface layouts (M5-T40)

What each hull's surface shows in the maintainer's references (`references/T40 seam references/`, never committed; several
are other artists' renders, so they are inspiration only and nothing is reused or traced), and the layout drawn for it
(`tools/procgen/parts/layouts.py`; how it is baked is architecture §18.30). Every feature is drawn per part, in the part's
own frame: seam grooves, sunk hatches, louvres and raised ribs go into the normal and roughness maps and darken the paint a
little; plating gives each plate its own tone and sheen. No triangles are added. Base colours and markings stay T39's.

Each hull is written with two texture sets, picked by `settings.texture_detail`: **low** draws level A below, **high** (the
default) draws A, B and C together. **A** is the major breaks (grooves), **B** the references' seam density with hatches,
ribs and louvres, **C** the plating: plates of mixed size toned plate by plate (a share of the paint's own value, no new
colours), sheen varied, grime in the joints, small proud hatches. Turrets, trusses, arms, struts, antennas and nozzles stay
plain. The phase 1 option sheets are `references/screenshots/T40 seams/T40_options_<hull>.png`.

### Saturn family (shared parts)

- **Read.** Cargo pods: each face is a frame round long slats that run the pod's length (eight or nine to a face), with
  three or four ribbed posts at each end and a break at the middle; the plating is dark grey in plates of clearly
  different value. Hull cylinders and tanks: rings at the edges of every paint band, plate courses round the barrel between
  them, a few long strakes, petals on the domes. Command disc: concentric rings and radial joints outside the fins.
  Collar: close ribs. Seams are sparse for the size (a plate is 5 m or more); the truss, arms, antenna and bell are plain.
- **Layout.** Cylinder and tank: A rings at the four band edges; B three courses a band, six strakes, dome petals and one
  ring a dome, a hatch on each band's back and flank; C every course cut into plates of mixed length with tone, grime and
  a few small hatches. Pod: A the frame lines and the middle break; B slats every 2.46 m inside the frame, the belt on the
  flanks, two ribs at each end; C the slats as planks of mixed length, each its own grey. Disc: A rings at 7.3 m and 11 m;
  B rings at 9.15 m and 12.85 m and radial joints every 30 degrees; C the sectors toned. Collar: one ring, then four ribs
  and eight strakes. Junction modules, the Saturn 3's pod blocks and the drums: plating only (plain in the low set).

### Skylark

- **Read.** The capsule is the busiest part: a ring either side of each orange band, panel courses and about twelve
  strakes between the bands with sunk rectangular ports, petals on both domes, a ribbed neck and spine. Tanks repeat it
  smaller. Nacelles are ringed every metre. The body slab has angular plates that follow its leading edge, a few
  rectangular and rounded hatches and rows of louvres along the flank and beside the ridge. Fins and claws are nearly
  plain. Seams are dense for the size (plates of 1 to 2 m on a 60 m ship).
- **Layout.** Capsule: A the four band rings and the middle joint; B four courses, twelve strakes, dome petals, spine
  ribs, four ports a side; C the courses broken into panels of mixed size in shades of the sand paint. Tanks and nacelles
  the same in small. Body: A two frames and the line inside the leading edge; B a strake, two more frames, five hatches
  and three louvre panels a side (top and belly); C angular plating with tone and small hatches.

### Narn transport

- **Read.** The one capture of the transport is small: a dark green crescent with a blocky pattern of darker
  rectangles and a pale box with a band. The model for its surface is the Frazi fighter (the maintainer, 2026-11-12), the
  consistent Narn construction: framed panels square to the ship's axes, a panel outlined inside a panel, a trim line that
  follows the outline, and over the whole hull small rectangles in slightly varied shades of the paint beneath, with a few
  narrow bars. The angular red and black war paint of the cruisers is a paint scheme, not surface, and is left out.
- **Layout.** Crescent: A the trim line 2.2 m inside the rim (top and belly), two frames and a framed panel on each half
  and on the centre; B a second line at 4.6 m, a strake, three more frames and the panels inside the framed ones; C the
  small rectangles (fields of 3.2 m by 2.4 m split down to 0.55 m, tone 10 % either way, thin joints) and narrow proud bars
  both ways. Box: A frames at the paint panel's ends and middle, the belt and a framed panel on the top and floor; B
  frames every 5 m, the lower belt, two strakes, two inner panels; C the same rectangles at 7 %. Cockpit, towers, fins and
  dorsal block: the rectangles only (plain in the low set).

### Centauri Brezebel

- **Read.** Smooth, glossy hull with no proud detail. Its plating runs fore and aft in long strakes whose plates butt at
  uneven stations, each plate a slightly different violet and gloss; the Centauri fighter's wings are plated across in
  strips, with thin trim lines. The pale rim band and the emblems are paint.
- **Layout.** Bow: A two strake lines a side and one frame; B every 3.25 m strake with uneven butt joints, two rounded
  hatches; C the plates toned and their gloss varied. Arms and fairings the same. Fins: seams across the blade every
  2.5 m and one along it.

### Brakiri Bokmai

- **Read.** A smooth skin in a few big plates with fine seams that follow the limbs, clusters of small raised
  rectangular hatches, and rows of small rounded ports (the lit ones exist as windows). The fins carry seams across the
  chord and one along the span. Tone differences are slight.
- **Layout.** Bow, spine, arms, struts and nacelles: A two or three long seams and frames; B big plates broken unevenly
  with thin seams; C a slight tone and gloss per plate and scattered proud hatches. Fins: chordwise seams every 4 m, then
  every 2 m and the spanwise seam, then hatches. Cargo pod: the belt and girth seams, then plating and hatches.

## Open for the human tester `(H)`

- The Narn's up is read from symmetry, the wiki's draught and one capture; flipping it moves the towers under the
  crescent and the box above.
- The Saturn 3's engine section and its raised, wider pod stack are not in its reference; Q16's shared lead ship needs
  them.
- The texture packs (M5-T27): the plating, seams and wear of each faction, how the scaled wear reads on the Saturns'
  coarser texels (10 to 19 cm a texel; a close fly-by of a Saturn 8 shows it), the glowing windows and engine throats
  (the throats of the retros glow too).
- The Brezebel's violet (#4C3C8E) is painted as written and may read dark on its shadow side; T16's GPU check decides,
  and a lift goes to the maintainer first.
- The Brezebel's retros fire forward from the bow's rim at (±14.6, 0, 5.7), on the fairings' axis, rather than from the
  fairings' fronts the design first named (inside the arm, where the depth proxy hid the plume); judge where the retro
  plumes show.
- The Bokmai's flank turrets stand about 1.25 m out of the bow's insets, facing straight outboard (the insets lean 9
  degrees); the insets are painted dark rather than recessed; the olive frame (#5A6B59) against its pale pods on the GPU.
