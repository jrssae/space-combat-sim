# Civilian ships: what the generators build (M5-T11, for T12 to T15)

Seven civilian hulls from four generators (D59): `saturn_family` builds `saturn_3_freighter`, `saturn_4_transport`,
`saturn_8_transport` and `saturn_fuel_tanker`; `skylark_transport`, `narn_transport` and `centauri_brezebel` build one
hull each. The shapes, sizes and colours come from `docs/design-references.md` ("Civilian ships (M5)"), measured off the
maintainer's reference models with `tools/refview`. This page turns them into parts, budgets, hardpoints, chunks and
styles. It is a plan: T12 to T15 build against it and replace each section with the as-built numbers, the way
`docs/assets-raider.md` reads.

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
from 60 px, LOD2 from 16 px, at 1080p and 75 degrees vertical), a 200 m hull is LOD0 inside 700 m, LOD1 to 2.3 km and
LOD2 to 8.8 km; a 100 m hull switches at 350 m, 1.2 km and 4.4 km; a 60 m hull at 210 m, 700 m and 2.6 km. Traffic
spawns 6 to 12 km out and passes 2 to 10 km from the player (Q12), so LOD2 and LOD3 carry most of the screen time.

The budget rule: all seven at LOD0 at once, plus the player's hero level, the sky and five nav buoys, stays inside
`settings.splat_budget` (2 000 000). Seven LOD0s make 800 000; with the hero (975 058), the sky (16 000) and five buoys
(38 000) that is 1 829 058, 91 % of the budget. In practice seven ships in one view are at LOD1 or coarser (200 000
for all seven).

| Hull | Length | Surface | LOD0 target (range) | Start spacing | LOD1 | LOD2 | LOD3 |
|---|---|---|---|---|---|---|---|
| `saturn_4_transport` | 100 m | 13 700 m² | 130 000 (105 000 to 155 000) | 0.32 m | 32 500 | 8 100 | 2 000 |
| `saturn_8_transport` | 200 m | about 23 000 m² | 190 000 (150 000 to 230 000) | 0.35 m | 47 500 | 11 900 | 3 000 |
| `saturn_fuel_tanker` | 200 m | about 17 000 m² | 150 000 (120 000 to 180 000) | 0.34 m | 37 500 | 9 400 | 2 300 |
| `saturn_3_freighter` | 58 m | about 9 800 m² | 90 000 (70 000 to 110 000) | 0.33 m | 22 500 | 5 600 | 1 400 |
| `skylark_transport` | 60 m | 6 400 m² | 70 000 (55 000 to 85 000) | 0.30 m | 17 500 | 4 400 | 1 100 |
| `narn_transport` | 70 m | 9 200 m² | 85 000 (70 000 to 100 000) | 0.33 m | 21 200 | 5 300 | 1 300 |
| `centauri_brezebel` | 60 m | 8 000 m² | 85 000 (70 000 to 100 000) | 0.31 m | 21 200 | 5 300 | 1 300 |
| All seven | | | 800 000 | | 200 000 | 50 000 | 12 400 |

- Surface is the reference model's area at its length (refview's `surface_area_m2`), or for the Saturn 8 and the tanker
  the Saturn 4's parts in the generator layout. It counts inner faces the generators drop (buried roots, the recessed
  pod ends), so the generated surface will be 10 to 30 % smaller; tune the spacing to land in the range and warn
  outside it at the default spacing, as the raider does. LOD shares as the raider: LOD1 20 to 30 % of LOD0.
- Start spacing is `sqrt(surface / target)`. Splat sigma is one spacing (overlap 1.0). At 0.33 m a splat seen from
  50 m is about 4.6 px across on a 1080p screen, so a close fly-by looks soft. That is the price of seven big hulls in
  the budget; judging it is `(H)`.
- Panel detail has to suit the spacing: a panel grid of 2.4 m with lines 0.25 m wide survives LOD0 sampling, the
  Starfury's 4 cm lines would not.
- Turret models are small and sampled finer (about 0.08 m, about 2 000 splats each); with 2 to 4 per hull they add
  under 1 % to the totals.
- VRAM, an estimate for T16 to measure: each hull type keeps LOD0 to LOD3 (1.33 times LOD0) and its chunks (0.25 times)
  resident, 1.27 M splats for all seven types. M3-T24 measured about 240 bytes of unique splat buffer per resident
  splat (+234 MB for the hero's 975 058), so about 300 MB with all seven types loaded, before instancing.

## Hardpoints

`hardpoints.json` carries the keys the `Hardpoints` and `ThrusterLayout` parsers need, plus `turrets[]`:

- `center_of_mass`: x = 0; y trimmed onto the main thrust line, so main thrust makes no pitch torque (as the raider);
  z from the part masses. `mass_kg` and `inertia_estimate_kg_m2` are informational; `ShipSpec` (T16) is the authority.
- `pods[]`: `ThrusterLayout` needs at least one pod on each side, each with a `main` (exhaust +z) and a `retro`
  (exhaust -z) nozzle. Hulls with one centre engine split it into a left and a right half.
- `muzzles`: an empty array. The parser requires the key; turrets carry their own barrels.
- `rcs[]`: cosmetic ports with `pilot_tags`, for plume glow.
- `collision[]`: boxes and capsules per part, also the hit volumes. Coverage test as the raider's, scaled: at least
  97 % of LOD0 splat centres inside the primitives inflated by one spacing, and no primitive more than 1 m past the
  splat box.
- `cockpit_camera` (on the bridge, looking -Z) and `chase_anchor` (0, 0.3 L, 1.2 L behind the centroid, L the length):
  the parser requires both, though nobody flies a civilian in M5.
- `nav_lights`: `port` and `starboard` at the widest points near mid-length, `top` on the highest point, `top_lamp`
  about 0.05 L above it with `top_lamp_range_m` about 0.3 L, `cabin` at the bridge windows with `cabin_range_m` about
  0.05 L.
- `turrets[]` (D61): `{name, position, up, arc_deg, barrel_m}`, positions from the design references. `arc_deg` 200
  for a dorsal or ventral mount (a hemisphere plus 10 degrees below its base), 220 for the Narn's tower tops.
- `chunks[]`: `{name, ply, lighting, obj, offset, joint, splats}` per group below.

| Hull | Pods (`l`, `r`): main / retro | RCS | Cockpit camera | Port / starboard light | Chunks |
|---|---|---|---|---|---|
| Saturn 4, 8, tanker | main: the bell's exit split in two, (±0.6, 0, end of the engine section), radius 1.4; retro: the disc's front rim, (±6.0, 0, 5.4), radius 0.6 | both ends of the drum frame's three drums (exhaust ±z), the disc rim's flanks (±x), the engine collar (±x, ±y) | inside the disc's front rim, (0, +0.5, 4.5) | the outboard tips of the first pod pair, on the Saturn 4 (±33.8, -4.6, 47.0) and 12 m further aft on the Saturn 8; the tanker's first lower tanks' flanks (±15.9, -8.5, 80.5) | Saturn 4: `bow`, `hull`, `engine`, `pods_l`, `pods_r`. Saturn 8: `bow`, `hull_1`, `junction`, `hull_2`, `engine`, `pods_1l`, `pods_1r`, `pods_2l`, `pods_2r`. Tanker: `bow`, `spine_1`, `junction`, `spine_2`, `engine`, `tanks_1l`, `tanks_1r`, `tanks_2l`, `tanks_2r` |
| Saturn 3 | main: two half-size bells on the lower pods' aft points, (±15.5, -6.3, 57.7); retro: the disc rim, (±6.0, 0, 2.3) | the drum frame, the disc rim | (0, +0.5, 1.4) | the lower pods' outboard ends (±29.6, -6.3, 47.9) | `bow`, `pod_top`, `pod_l`, `pod_r` |
| Skylark | main: the nacelle bells, (±13.45, -0.45, 55.5), radius 3.0; retro: the nacelle intake rings, (±13.45, -0.45, 35.6), radius 1.5 | the nacelles' three cones each, the capsule's two cones, the nose vanes | under the capsule's dorsal plate, (0, +3.0, 11.0) | the nacelles' outboard cones (±16.8, -0.45, 42.5) | `capsule` (nose, capsule, spine, side tanks, collar), `body` (body, dorsal fin, centre engine), `nacelle_l`, `nacelle_r` (with claws) |
| Narn | main: the flank towers' aft faces, (±15.0, +5.0, 43.9), radius 1.4; retro: the towers' fronts, (±15.0, +5.0, 35.25), radius 1.0 | the prong tips (forward and outboard), the fin tips (up and down), the box's aft corners | under the canopy, (0, +1.5, 7.0) | the crescent's widest points (±23.0, 0, 27.0) | `cockpit` (cockpit block, dorsal block, the crescent's centre), `wing_l`, `wing_r` (prong, crescent half, fin, tower), `box` |
| Brezebel | main: the arm tips, (±11.5, 0, 60.0), radius 1.5; retro: the fairings' fronts, (±14.6, 0, 21.75), radius 1.0 | the twelve blocks on the engine bay's walls, the fin tips | behind the window row, (0, +3.5, 2.5) | the bow's widest points (±19.6, 0, 17.0) | `bow` (bow, dorsal fitting, engine bay, main engine), `arm_l`, `arm_r` (arm, fairing, fins) |

The Saturns' thrust line is the spine axis, so their centre of mass is trimmed onto it although the pods hang below.
The Saturn 3 model shows no engine at all; the two small bells on its lower pods are our choice and keep its length
at 57.7 m. The Narn's thrust line is 5 m above its centre plane, the Brezebel's on it. Centre engines (the Skylark's
cone, the Brezebel's drum) glow but are not pods.

## `saturn_family` (T12)

One module, `tools/procgen/assets/saturn_family.py`, registering the four ids; each id is a variant record. The shared
parts go into a new `tools/procgen/parts/saturn.py`. The Saturn 4 fixes every shared part's size; the variants differ
only in the variant data below.

| Part | How to build it | Size (Saturn 4) |
|---|---|---|
| `antenna` | a `lathe` dish and cone spike on a `box` boom; the Saturn 3's variant is a `lathe` ball on a curved `sweep_rect` boom | dish 4.5 m, spike 2.4 m; ball 2.3 m |
| `command_disc` | `loft` along z through flattened elliptic sections: width from the plan outline (a circle of radius 8.9 m cut square 6.7 m behind its centre, then the 8 m neck to the truss), height from the lens profile (3.8 m at the centre, 1.0 m at the rim). The 12 radial fins on each face and the hub are `box`es and a `lathe`; the corner blocks are `box`es. | 17.8 m across |
| `truss_spine` | three longerons (thin `lathe` tubes or `sweep_rect` bars) in a 4 m triangle with V braces in bays of about 4.5 m; the length sets the bay count; a ring of radial brackets where it meets a dome. Also the Saturn 8's junction truss. | 18 m |
| `drum_frame` | a triangular frame of `box`es round the truss holding three `lathe` drums, plus the drum on the truss | drums 2.0 to 2.5 m x 5.2 m |
| `hull_cylinder` | a horizontal `lathe` with 3.7 m domes and a straight barrel, paint bands as per-segment materials. `parts/hull.py`'s `cylinder_hull` paints bands the same way but stands on Y with conical shoulders, so this is a new part. Also the tanker's tank. | 11.06 m x 47.6 m |
| `engine_section` | a `lathe` collar, four `lathe` propellant tanks round a central one, U-shaped `sweep_rect` feed pipes, and `propulsion.nozzle` for the bell | 6 m collar, bell exit 4.0 m, 14.3 m long |
| `cargo_arm` | a `box` arm and a `sweep_rect` brace | 8.2 x 3.8 x 2.8 m |
| `pod_rail` | a `lathe` rod with `box` end blocks | 1.73 m x 26.1 m |
| `transport_pod` | `prism` of the kite outline (inboard end face 3.8 m, ridge 10.9 m at 31 % of the width, outboard end face 2.4 m) extruded along the pod's length and turned so the extrusion runs along z (along x for the Saturn 3). The end faces are recessed: an inset ring (`inset_convex_polygon`) with ladder ribs as `box`es inside. The 2.3 m end bands are a second, slightly larger prism. Trim (stripe, hazard band, rust-red top) is material bands on the prism's faces. | 19.6 x 10.9 x 27.15 m |
| `junction_module` | a hexagonal `prism` with recessed panels | Saturn 8: 8.4 m across, 6.7 m long; tanker: three of 11.5 x 10.6 x 12.1 m |
| Saturn 3 cross-beam and pod blocks | `box`, `tapered_box`, and `wing.vent_grille` for the grilles | beam 27.8 m wide; blocks 4.0 x 2.8 x 8.5 m |

| Variant | Antenna | Forward truss | Cargo | Junction | Engine | Length |
|---|---|---|---|---|---|---|
| `saturn_4_transport` | dish | 18 m | one cylinder, two pod pairs lengthwise | none | bell | 100.0 m |
| `saturn_8_transport` | dish | 30 m | two cylinders, two pod pairs on each | 40.45 m with the hexagonal module | bell | 200.0 m |
| `saturn_fuel_tanker` | dish | 30 m | two rows of three 59.3 m tanks (a spine tank and two lower ones) | 17.05 m with three modules | bell | 200.0 m |
| `saturn_3_freighter` | ball, under the disc | to the drum frame, then the cross-beam and pod blocks (z 17.8 to 38.1) | three pods crosswise, one on top and two below | none | two half-size bells on the lower pods | 57.7 m |

The design references explain the 200 m layouts: built from the Saturn 4's parts the reference Saturn 8 is 168 m and
the tanker 161 m, so the stated length goes into longer trusses (Saturn 8) and longer tanks (tanker). The Saturn 3's
disc starts at z 0, since its ball antenna hangs under the disc rather than ahead of it, so its parts sit 3.1 m further
forward than the Saturn 4's. Per-hull trim is variant data too: the Saturn 4 and 8 pods get the red top stripe and the
hazard band, the Saturn 3 pods rust-red tops, the tanker's tanks the red and off-white bands.

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
| Engine bay | an inset box in the bow's rear face, filled with `box` and `lathe` machinery and the twelve RCS blocks; the main engine as a `lathe` drum with `propulsion.nozzle` |
| Dorsal fitting | `tapered_box` with five window insets |
| Arm fairings | two `ellipsoid_cap`s or a `lathe` ellipsoid per arm |
| Tip fins | `section_loft` of the hooked outline, thinning from 3.4 m at the root, leaning inward 10 degrees, gold caps as a material band |

## Styles

Three styles, each a `Style` with the required roles plus extras. Hex values are sRGB from the design references;
`styles/raider.py`'s `_lin` converts them to the linear albedo the styles store. Panel grids are coarse to suit the
spacing (2.4 m cells, 0.25 m lines).

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

Panel tint jitter 0.06. Engine glow (a `ShipSpec` tint): Saturns blue-white #DCE8FF, Skylark warm white #FFE9C2.

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

Panel tint jitter 0.08. Engine glow orange-white #FFB070; turret bolts green (D61's `WeaponSpec`, per the wiki).

**`centauri`**

| Role | sRGB | Where |
|---|---|---|
| `hull` | #4C3C8E | everything but the trim |
| `hull_dark` | #2B2257 | panel lines, the engine bay's walls |
| `stripe` | #D9B23A | the gold caps on the tip fins, turret collars |
| `trim_light` (extra) | #D7D2E6 | the edge band round the bow's rim |
| `window` (extra) | #F3F1FF | the five windows |
| `nozzle`, `nozzle_throat` | #3A3448, #141218 | main engine and arm-tip nozzles |

Panel tint jitter 0.04 (the liner reads smooth). Engine and fin-tip glow pink-white #FFB8E0; turret bolts orange.

Two warnings from the raider (`docs/assets-raider.md`): on the RX 6950 XT a dark albedo read as a black silhouette, and
civilians are often seen on their dark side. If the Narn green (#2E4A3B) or the Centauri violet (#4C3C8E) reads black
in T16's GPU check, lift the value and keep the hue, and record the change here.

### Turret models (one per style, D61)

| Style | Model | `barrel_m` |
|---|---|---|
| `ea_civilian` | a round base 2.4 m across and 0.6 m tall, a dome 2.0 m across, twin barrels 0.5 m apart; plating grey, barrels dark | 3.0 |
| `narn` | a six-sided base 2.6 m across, a wedge-shaped housing, twin barrels; dark green with the red band | 3.0 |
| `centauri` | a teardrop pod 2.2 m across on a short stalk, twin barrels with gold collars | 2.6 |

## Turret positions

From the design references, authored frame; `up` is +y for dorsal mounts and -y for ventral ones.

| Hull | Turrets |
|---|---|
| Saturn 4 (3) | `dorsal_fwd` (0, +2.4, 12.0), `ventral_fwd` (0, -4.6, 29.0), `dorsal_aft` (0, +5.9, 82.0) |
| Saturn 8 (4) | `dorsal_fwd` (0, +2.4, 12.0), `ventral_fwd` (0, -4.6, 29.0), `dorsal_mid` (0, +4.6, 118.7), `ventral_mid` (0, -4.6, 118.7) |
| Tanker (4) | `dorsal_fwd` (0, +2.4, 12.0), `ventral_fwd` (0, -4.6, 29.0), `dorsal_mid` (0, +5.3, 118.7), `ventral_mid` (0, -13.5, 118.7) |
| Saturn 3 (2) | `dorsal` (0, +2.4, 8.9), `ventral` (0, -8.6, 28.7) |
| Skylark (2) | `dorsal` (0, +3.6, 37.5), `ventral` (0, -4.2, 15.0) |
| Narn (2) | `tower_l` (-15.0, +9.0, 39.5), `tower_r` (15.0, +9.0, 39.5); fallback for the belly: one moves to (0, -9.0, 55.0) |
| Brezebel (2) | `dorsal` (0, +4.3, 7.0), `ventral` (0, -4.5, 9.0) |

## Open for the human tester `(H)`

- The Saturn 8's pods sit in two groups 40 m apart where the reference spaces them evenly (the cost of keeping the
  Saturn 4's parts at 200 m).
- The Narn's up is read from symmetry, the wiki's draught and one capture; flipping it moves the towers under the
  crescent and the box above.
- The Saturn 3's two small engines are not in its reference.
- Close fly-bys at about 0.33 m spacing look soft.
