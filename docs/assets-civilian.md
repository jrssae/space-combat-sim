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
and LOD2 to 11.4 km; a 158.5 m Saturn 4 switches at 560 m, 1.9 km and 7.0 km; the 119.5 m Saturn 3 at 420 m, 1.4 km
and 5.3 km; a 60 m hull at 210 m, 700 m and 2.6 km. Raiders jump in 6 to 12 km out; patrols and civilians spawn 26 to
30 km out, past the player's 25 km radar, on routes that pass 2 to 10 km from the player (Q12, T17). LOD2 and LOD3
carry most of the screen time.

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
| `saturn_3_freighter` | 119.5 m | about 19 700 m² | 75 000 (60 000 to 90 000) | 0.51 m | 18 800 | 4 700 | 1 200 |
| `skylark_transport` | 60 m | 6 400 m² | 60 000 (48 000 to 72 000) | 0.33 m | 15 000 | 3 800 | 900 |
| `narn_transport` | 70 m | 9 200 m² | 75 000 (60 000 to 90 000) | 0.35 m | 18 800 | 4 700 | 1 200 |
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
| Mains (`l`, `r`) | the bell's exit split in two, (±0.95, 0, length), exhaust (0, 0, 1), radius 2.2 |
| `cockpit_camera` | inside the disc's front rim, (0, +0.8, 8.0) |
| `cabin` | the same point, `cabin_range_m` 0.05 L |
| RCS | both ends of the drum frame's three outer drums: the top one at (0, +5.55, z) and the lower ones at (±9.27, -10.55, z), z 41.9 exhausting -z and 50.1 exhausting +z; the disc's flanks (±14.13, 0, 19.06) exhausting ±x; four on the engine collar 3 m behind its front, (±4.78, 0, z) and (0, ±4.78, z), exhausting outward |
| Turrets | `dorsal_fwd` (0, +3.8, 19.1), up (0, 1, 0); `ventral_fwd` (0, -7.4, 46.0), up (0, -1, 0) |

Per variant:

| Variant | Length L | Mains at z | More turrets | Port / starboard | Top, top lamp | Chunks |
|---|---|---|---|---|---|---|
| `saturn_4_transport` | 158.5 | 158.48 | `dorsal_aft` (0, +9.3, 124.4) | the first pods' outboard tips (±53.4, -7.29, 74.3) | (0, +8.6, 75.0), lamp (0, +16.6, 99.4), range 48 m | `bow`, `hull`, `engine`, `pods_l`, `pods_r` |
| `saturn_4_tanker` | 158.5 | 158.48 | `dorsal_aft` (0, +9.3, 124.4) | the lower tanks' flanks (±25.6, -13.53, 99.4) | (0, +8.6, 75.0), lamp (0, +16.6, 99.4), range 48 m | `bow`, `spine`, `engine`, `tank_l`, `tank_r` |
| `saturn_8_transport` | 258.5 | 258.48 | `dorsal_mid` (0, +7.2, 149.4), `ventral_aft` (0, -5.3, 240.0) | (±53.4, -7.29, 74.3) | (0, +8.6, 75.0), lamp (0, +21.5, 149.4), range 78 m | `bow`, `hull_1`, `junction`, `hull_2`, `engine`, `pods_1l`, `pods_1r`, `pods_2l`, `pods_2r` |
| `saturn_8_tanker` | 258.5 | 258.48 | `dorsal_mid` (0, +9.0, 149.4), `ventral_aft` (0, -5.3, 240.0) | (±25.6, -13.53, 99.4) | (0, +8.6, 75.0), lamp (0, +21.5, 149.4), range 78 m | `bow`, `spine_1`, `junction`, `spine_2`, `engine`, `tanks_1l`, `tanks_1r`, `tanks_2l`, `tanks_2r` |
| `saturn_3_freighter` | 119.5 | 119.46 | `dorsal_aft` (0, +5.3, 99.0) | the lower pods' outboard ends (±46.8, -5.46, 79.7) | the top pod (0, +21.8, 79.7), lamp (0, +27.8, 79.7), range 36 m | `bow` (with the cross-beam and blocks), `pod_top`, `pod_l`, `pod_r`, `engine` (with the truss behind the drum frame) |

Collision, per part: the disc a box 28.3 x 6.0 x 28.3 m with the antenna inside it; the forward truss a box 6.3 x 6.3
m along its length; the drum frame a box 21.7 x 19.3 x 8.2 m; each hull cylinder or tank a capsule of radius 8.77 m (it covers the 17.53 x 17.27 m polygon) and
height 75.5 m along z; each pod a box 31.1 x 17.3 x 43.0 m (turned for the Saturn 3) that also wraps its rail; each arm
a box 13.0 x 4.5 x 6.0 m; the engine section a capsule of radius 4.8 m and height 22.6 m; the Saturn 8 transport's
junction a box 13.3 x 13.3 x 24.5 m; the Saturn 8 tanker's three junction modules boxes of 18.3 x 16.8 x 19.1 m.

The Saturns' thrust line is the spine axis, so their centre of mass is trimmed onto it although the cargo hangs below.

### Skylark, Narn and Brezebel

| Hull | Pods (`l`, `r`): main / retro | RCS | Cockpit camera | Port / starboard light | Chunks |
|---|---|---|---|---|---|
| Skylark | main: the nacelle bells, (±13.45, -0.45, 55.5), radius 3.0; retro: the nacelle intake rings, (±13.45, -0.45, 35.6), radius 1.5 | the nacelles' three cones each, the capsule's two cones, the nose vanes | under the capsule's dorsal plate, (0, +3.0, 11.0) | the nacelles' outboard cones (±16.8, -0.45, 42.5) | `capsule` (nose, capsule, spine, side tanks, collar), `body` (body, dorsal fin, centre engine), `nacelle_l`, `nacelle_r` (with claws) |
| Narn | main: the flank towers' aft faces, (±15.0, +5.0, 43.9), radius 1.4; retro: the towers' fronts, (±15.0, +5.0, 35.25), radius 1.0 | the prong tips (forward and outboard), the fin tips (up and down), the box's aft corners | under the canopy, (0, +1.5, 7.0) | the crescent's widest points (±23.0, 0, 27.0) | `cockpit` (cockpit block, dorsal block, the crescent's centre), `wing_l`, `wing_r` (prong, crescent half, fin, tower), `box` |
| Brezebel | main: the arm tips, (±12.2, 0, 60.0), radius 1.2, inside the 2.8 m wide tip; retro: the fairings' fronts, (±14.6, 0, 21.75), radius 1.0 | the twelve blocks on the engine bay's walls, the fin tips | behind the window row, (0, +3.5, 2.5) | the bow's widest points (±19.6, 0, 17.0) | `bow` (bow, dorsal fitting, engine bay, main engine), `arm_l`, `arm_r` (arm, fairing, fins) |

The Narn's thrust line is 5 m above its centre plane, the Brezebel's on it. Centre engines (the Skylark's cone, the
Brezebel's drum) glow but are not pods.

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
| `saturn_3_freighter` | cross-beam, blocks and three pods crosswise (z 48.5 to 95.3), the truss through the stack | none | z 96.9 to 119.5 | 119.5 m |

The length rule (Q16) is lead ship plus cargo: 49.3 m of lead ship ahead of the first section, 100 m per section, and
the engine section's last 9.2 m behind the last section. The section's own stations, the Saturn 3's stack and every
variant's z table are in the design references. Per-variant trim is variant data: the transports' pods get the red
top stripe and the hazard band, the Saturn 3 pods rust-red tops, every tank the red and off-white bands.

## `skylark_transport` (T13)

`tools/procgen/assets/skylark_transport.py`; parts that other hulls will not reuse can live in the asset module.

| Part | How to build it |
|---|---|
| Nose cap and vanes | a `lathe` cap and four `sweep_rect` vanes |
| Forward capsule | a `lathe` capsule 7.46 m across with a `box` dorsal plate (the bridge, glazed front) and two `lathe` cones turned down and outboard |
| Spine and collar | `lathe` tubes with rings of short `box` vanes at both ends of the spine |
| Side tanks | `lathe` capsules and dumbbells |
| Central body | `section_loft` through faceted sections, about eight sides, following the plan widths (16 m, 23.8 m, 10 m) and 7.2 m depth; `prism` corner fins; a tapered `section_loft` dorsal fin; `sweep_rect` belly struts |
| Nacelles | `lathe` with ribbed rings at the intake and the bell, like `propulsion.ring_pod`'s ribbing, and three `lathe` cones |
| Claws | bent blades as `section_loft` or `sweep_rect`, like the Starfury's claw plates |
| Centre engine | a `lathe` drum and `propulsion.nozzle` for the cone |

## `narn_transport` and the `narn` style (T14)

`tools/procgen/assets/narn_transport.py`, `tools/procgen/styles/narn.py`.

| Part | How to build it |
|---|---|
| Crescent | the plan outline is not convex (the notch), so build it as pieces that overlap: a centre body from z 15 to 51.3 and two prongs from z 0 to 27, each a `section_loft` of flat diamond sections whose thickness falls from 7.8 m on the centre line to an edge at the rim |
| Cockpit | a `section_loft` hexagonal nose with the canopy recess as inset faces in `canopy_glass` |
| Dorsal block and rod | `tapered_box` and a `lathe` rod |
| Fins | `prism` of the fin's outline, 0.5 m thick |
| Flank towers | `tapered_box` with three rounded vanes (`sweep_rect`) on the front, the slot as an inset in the top, and `propulsion.nozzle` on the aft face |
| Cargo box | a chamfered `section_loft` along z with the aft lower cut, two `wing.vent_grille`s on top, the green panel and hazard corners as material regions |

## `centauri_brezebel` and the `centauri` style (T15)

`tools/procgen/assets/centauri_brezebel.py`, `tools/procgen/styles/centauri.py`.

| Part | How to build it |
|---|---|
| Bow | a `section_loft` of lens sections from the nose to z 19, widths from the half-ellipse plan |
| Arms | one `section_loft` per arm from z 17 to 60, lens sections from the outer and inner edges and the depths (7.6 m, 5.2 m at z 40, 3.5 m at the tip), overlapping the bow at the root; a `lathe` or `box` rail on the inner edge |
| Engine bay | an open box in the bow's rear face, filled with `box` and `lathe` machinery and the twelve RCS blocks; the main engine as a `lathe` drum with `propulsion.nozzle` |
| Dorsal fitting | `tapered_box` with five window insets |
| Arm fairings | two `ellipsoid_cap`s or a `lathe` ellipsoid per arm |
| Tip fins | `section_loft` of the hooked outline, thinning from 3.4 m at the root, leaning inward 10 degrees, gold caps as a material band; the main nozzle sits in the arm's tip between the fins |

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
| Skylark override | `hull` #B3A982, `hull_panel` #7E7552, `hull_dark` #4A4536, `stripe` #B8452B | its sand plating and red-orange bands |

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
turret bolts orange.

Two warnings from the raider (`docs/assets-raider.md`): on the RX 6950 XT a dark albedo read as a black silhouette, and
civilians are often seen on their dark side. If the Narn green (#2E4A3B) or the Centauri violet (#4C3C8E) reads black
in T16's GPU check, lift the value and keep the hue, and record the change here.

### Turret models (one per style, D61)

| Style | Model | `barrel_m` |
|---|---|---|
| `ea_civilian` | a round base 3.6 m across and 0.9 m tall, a dome 3.0 m across, twin barrels 0.8 m apart; plating grey, barrels dark. The Skylark uses it at two thirds of that size. | 4.5 (Skylark 3.0) |
| `narn` | a six-sided base 2.6 m across, a wedge-shaped housing, twin barrels; dark green with the red band | 3.0 |
| `centauri` | a teardrop pod 2.2 m across on a short stalk, twin barrels with gold collars | 2.6 |

## Turret positions

From the design references, authored frame; `up` is (0, 1, 0) for dorsal mounts and (0, -1, 0) for ventral ones.

| Hull | Turrets |
|---|---|
| Saturn 4 transport (3) | `dorsal_fwd` (0, +3.8, 19.1), `ventral_fwd` (0, -7.4, 46.0), `dorsal_aft` (0, +9.3, 124.4) |
| Saturn 4 tanker (3) | `dorsal_fwd` (0, +3.8, 19.1), `ventral_fwd` (0, -7.4, 46.0), `dorsal_aft` (0, +9.3, 124.4) |
| Saturn 8 transport (4) | `dorsal_fwd` (0, +3.8, 19.1), `ventral_fwd` (0, -7.4, 46.0), `dorsal_mid` (0, +7.2, 149.4), `ventral_aft` (0, -5.3, 240.0) |
| Saturn 8 tanker (4) | `dorsal_fwd` (0, +3.8, 19.1), `ventral_fwd` (0, -7.4, 46.0), `dorsal_mid` (0, +9.0, 149.4), `ventral_aft` (0, -5.3, 240.0) |
| Saturn 3 (3) | `dorsal_fwd` (0, +3.8, 19.1), `ventral_fwd` (0, -7.4, 46.0), `dorsal_aft` (0, +5.3, 99.0) |
| Skylark (2) | `dorsal` (0, +3.6, 37.5), `ventral` (0, -4.2, 15.0) |
| Narn (2) | `tower_l` (-15.0, +9.0, 39.5), `tower_r` (15.0, +9.0, 39.5); fallback for the belly: one moves to (0, -9.0, 55.0) |
| Brezebel (2) | `dorsal` (0, +4.3, 7.0), `ventral` (0, -4.5, 9.0) |

## Open for the human tester `(H)`

- The Narn's up is read from symmetry, the wiki's draught and one capture; flipping it moves the towers under the
  crescent and the box above.
- The Saturn 3's engine section and its raised, wider pod stack are not in its reference; Q16's shared lead ship needs
  them.
- Close fly-bys look soft: about 0.52 m spacing on the Saturns, 0.33 to 0.35 m on the others.
