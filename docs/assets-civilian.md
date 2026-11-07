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
| Turrets | `dorsal_fwd` (0, +3.8, 19.1), up (0, 1, 0); dorsal mounts only (Q19) |

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
| `saturn_4_transport` | whole ship (`--model-offset 0,-3.643,0`) | 0.958 | 0.966 | 0.931 | 1.000 | 1.000 | 1.026 | 2026-11-07 |
| `saturn_4_transport` | lead ship (Saturn 4 model z 0-49.3, asset 0-49.3) | 0.960 | 0.919 | 0.916 | 1.000 | 1.000 | 0.985 | 2026-11-07 |
| `saturn_4_transport` | transport section (model 49.3-149.3, asset 49.3-149.3) | 0.955 | 0.984 | 0.917 | 1.000 | 1.000 | 1.026 | 2026-11-07 |
| `saturn_4_tanker` | lead ship (Saturn 4 model z 0-49.3, asset 0-49.3) | 0.960 | 0.919 | 0.916 | 1.000 | 1.000 | 0.985 | 2026-11-07 |
| `saturn_4_tanker` | tank group (tanker model 49.3-136.0, asset 49.3-136.0: the tanks on both sides, the model's junction and the asset's engine left out) | 0.987 | 0.976 | 0.938 | 1.000 | 1.000 | 1.026 | 2026-11-07 |
| `saturn_8_transport` | lead ship (Saturn 4 model z 0-49.3, asset 0-49.3) | 0.960 | 0.919 | 0.916 | 1.000 | 1.000 | 0.985 | 2026-11-07 |
| `saturn_8_transport` | transport section 1 (Saturn 4 model 49.3-137.1, asset 49.3-137.1: the aft frame to the cylinder's end on both sides) | 0.955 | 0.990 | 0.923 | 1.000 | 1.000 | 1.005 | 2026-11-07 |
| `saturn_8_transport` | transport section 2 and engine (Saturn 4 model 61.65-149.3, asset 161.65-249.3: the cylinder's front to the engine on both sides) | 0.967 | 0.991 | 0.923 | 1.000 | 1.000 | 1.005 | 2026-11-07 |
| `saturn_8_tanker` | lead ship (Saturn 4 model z 0-49.3, asset 0-49.3) | 0.960 | 0.919 | 0.916 | 1.000 | 1.000 | 0.985 | 2026-11-07 |
| `saturn_8_tanker` | tank section 1 (tanker model 49.3-146.2, asset 49.3-149.3; the model's sections are 96.96 m apart, Q16's 100 m) | 0.947 | 0.935 | 0.917 | 1.032 | 0.993 | 1.012 | 2026-11-07 |
| `saturn_8_tanker` | tank section 2 and engine (tanker model 146.2-255.1, asset 149.3-258.5) | 0.980 | 0.971 | 0.916 | 1.003 | 0.993 | 1.012 | 2026-11-07 |
| `saturn_3_freighter` | lead ship (Saturn 4 model z 0-41.5, asset 0-41.5) | 0.964 | 0.905 | 0.946 | 1.000 | 1.000 | 0.990 | 2026-11-07 |
| `saturn_3_freighter` | pod group (Saturn 3 model 41.5-91.1 scaled 1.244, 1.093, 1; asset 41.5-96.8): expected exemption (Q23) | 0.768 | 0.644 | 0.927 | 1.114 | 0.989 | 1.022 | 2026-11-07 |
| `narn_transport` | whole ship (no shift) | 0.991 | 0.985 | 0.974 | 1.000 | 1.000 | 0.997 | 2026-11-07 |
| `brakiri_bokmai` | whole ship with its three pods (`--pods-from-hardpoints`, no shift) | 0.966 | 0.977 | 0.954 | 0.999 | 0.999 | 0.999 | 2026-11-07 |
| `centauri_brezebel` | whole ship (best shift x -0.15 m, the model's fins sit 0.2 m to port; unshifted 0.972, 0.983, 0.945) | 0.965 | 0.983 | 0.970 | 1.000 | 1.000 | 0.999 | 2026-11-07 |
| `skylark_transport` | whole ship (no shift) | 0.979 | 0.980 | 0.956 | 1.001 | 1.000 | 0.998 | 2026-11-07 |

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

From the design references, authored frame; `up` is (0, 1, 0) for dorsal mounts and (0, -1, 0) for ventral ones.

| Hull | Turrets |
|---|---|
| Saturn 4 transport (2) | `dorsal_fwd` (0, +3.8, 19.1), `dorsal_aft` (0, +9.3, 124.4) |
| Saturn 4 tanker (2) | `dorsal_fwd` (0, +3.8, 19.1), `dorsal_aft` (0, +9.3, 124.4) |
| Saturn 8 transport (2) | `dorsal_fwd` (0, +3.8, 19.1), `dorsal_mid` (0, +7.2, 149.4) |
| Saturn 8 tanker (2) | `dorsal_fwd` (0, +3.8, 19.1), `dorsal_mid` (0, +9.0, 149.4) |
| Saturn 3 (1) | `dorsal_fwd` (0, +3.8, 19.1) |
| Skylark (1) | `dorsal` (0, +2.766, 37.5), seated on the body's ridge; no ventral (Q19) |
| Narn (2) | `tower_l` (-14.85, +9.0, 41.7), `tower_r` (14.85, +9.0, 41.7), on the slotted crowns |
| Brezebel (1) | `dorsal` (0, +4.3, 7.0), on the dorsal fitting's turret ring |
| Bokmai (2) | `flank_l` (-2.04, +8.45, 6.58), `flank_r` (2.04, +8.45, 6.58), in the bow's flank insets, up (∓1, 0, 0) outboard (Q22) |

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
