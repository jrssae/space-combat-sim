# Capital ships: what the generators build (M12)

One section per capital hull, as built, the way `docs/assets-civilian.md` reads for the civilians. The shapes, sizes and
colours come from `docs/design-references.md`, measured off the maintainer's reference models with `tools/refview`.
Positions are in the authored frame of the design references: x to starboard, y up, z aft from the bow, metres, Godot's
axes. As with every asset, the generator then centres its mesh and hardpoints on the centroid of the visible surface and
records the shift as `manifest.centroid_offset`.

M12-T05 builds the shared capital framework (D12.1: sections, texel tiers, weapon mounts). The strike carrier is built
ahead of it (the early delivery, Q25) on the civilians' pipeline, `core/civilian.py`, and moves onto the framework when it
lands.

## Output contract

The civilians' (`docs/assets-civilian.md`, "Output contract"), per asset id in `assets/generated/<id>/`: `<id>.glb` with
its four maps and the low texture set's three, `<id>.obj`, the break-up chunks, `hardpoints.json` and `manifest.json`. A
capital adds:

| Where | What it is |
|---|---|
| `manifest.collision` | the compound collision (below): `max_shapes`, `max_hull_points`, `pieces[]` (one per break-up chunk, each with its convex shapes and their hit volumes) and `coverage` |
| `hardpoints.cradles[]` | docking hardpoints for a carrier's fighters (below) |
| `hardpoints.jump_point` | where the ship opens its own jump point: `position`, `forward`, `mouth_radius_m` |
| `hardpoints.collision` | empty: the legacy box and capsule list is replaced by `manifest.collision` |
| `hardpoints.tubes[]`, `cradles[].release_to` | a hull with launch tubes (the Battle Wagon): each tube's mouths, clear way and lanes; its berths are `cradles[]` entries that leave ahead to `release_to` and come home from `approach_from` |
| `hardpoints.missile_racks[]` | where a rack's missiles leave from and along which way, and its cells |
| `manifest.mesh.atlases[]` | a hull written with an atlas per chunk (the Battle Wagon, below): each chunk's texel, atlas size and fill; `mesh.surfaces[]` then has a surface per chunk, `hull_<chunk>`, with its own maps |

## Compound collision (M7's D73; M7-T03's builder, the carrier's helpers merged in by M8-T07)

`tools/procgen/core/collision.py`, general: one builder for M7's station, the Saturns' and the cargo pod's pieces and the
carrier (M12-T19 built a second one on its branch; M8-T07 folded it into M7-T03's, keeping M7's API and manifest format).

- **Shapes.** A part names its collision as convex shapes: `box` (centre, size, basis; `box_around` fits one round points), a
  `capsule` (centre, radius, height, basis; `capsule_between` puts one between two end points) or `hull` (the convex hull of
  a few points, cut down to the budget's point count). A concave part is several shapes: `ring_sectors` cuts a ring into
  convex sectors so its hole stays open, and `prism_points` gives the corner points of a round part's hull. A starboard
  part's shapes give their port twins with `mirrored("x")`.
- **Pieces and the budget.** Shapes are grouped by the asset's pieces (here the break-up chunks, so a chunk keeps its
  collision; D12.1's sections later). `Budget(max_shapes, max_hull_points)` is what one body may carry (128 and 32 by
  default; the carrier asks for 64 shapes). `merge_to_budget` joins a piece's shapes pairwise down to the budget (the pair
  whose common box adds the least empty space first); `section` writes the pieces.
- **Coverage.** Two measures. `coverage` takes the render triangles (the station, the Saturns): the widest gap and the
  farthest excess. `skin_coverage` takes a hull's sampled skin (the carrier): every skin point lies within `tolerance_m` of a
  shape (`covered`, `worst_gap_m`), and no point of the shapes' joint outer surface is further than `reach_m` from the skin
  (`within_reach`, `worst_excess_m`). The second is what keeps a ring's hole and a cradle's approach open: one hull round a
  ring fails it.
- **The manifest.** `collision` is `{max_shapes, max_hull_points, pieces[]}`; each piece is `{name, aabb_min, aabb_max,
  bound: {center, radius}, shapes[], hit_volumes[]}`. Shapes are `{name, type}` plus `position`, `size` and `basis` (box),
  `position`, `radius`, `height`, `axis` and `basis` (capsule, as `hardpoints.collision` wrote them) or `points` (hull), all
  in the body frame; `hit_volumes` holds a box or capsule per shape (a hull's tightest box) for the native hit sweep. The
  carrier adds `coverage`. `core/manifest.py` validates the section; `collision.shapes_of` reads it back. The game reads it
  with `CollisionPieces`: the station builds a body per piece (`CollisionBodies`), the carrier puts every shape on its one
  body (`CompoundCollision`, named by piece).
- **Tests** (`tools/procgen/tests/test_collision.py`): hull corners and the point budget, distances, the merge, both coverage
  measures, moves and mirrors, a ring covered with its hole open, one hull round a ring failing the reach check, the
  section and its validation, reading it back, determinism.

## `raider_strike_carrier` (M12-T19)

`tools/procgen/assets/raider_strike_carrier.py` on `parts/raider_carrier.py`, `styles/raider_capital.py` and
`parts/layouts.py` (`raider_carrier`). The shape is described in `docs/design-references.md`, "Raider strike carrier".
No weapons (Q25): its fighters are its weapons.

### Measurements

| | |
|---|---|
| Reference | `Rader_strike_carrier.stl`, mapping `--right=+y --up=+z --aft=+x` |
| Up | +z, confirmed: the sensor housing over the hangar mouth, three cradles stacked at twelve o'clock, the skirt fins under the boxes' stern (how the painted print stands on its base). Shown on the look sheet |
| Length | **112 m** (Q26; the maintainer, 2026-11-15: about 110 m, following the painted print). A docked Delta-V overhangs its pad out to the line of the clamp pins: the pins' tips are 15.24 % of the length apart, the span is 17 m (17 / 0.1524 = 111.5 m) |
| Span, height | 85.5 m, 84.3 m (the reference's box at 112 m: 85.6 and 84.5) |
| Cradles | **18**: 9 on the outer ring, 6 on the mid ring, 3 on the drum's first collar |
| Triangles | 10 440 (budget 20 000); Godot's importer adds the levels of detail |
| Atlas | 4 096 px, 7.1 cm a texel; low and high texture sets |
| Video memory | 54 MB for the hull with its maps (447 to 501 MB in the look scene), measured on oscar's R9 280X, not the target GPU |
| Mass (informational) | 13 550 t from the skin's area at 260 kg/m2; the game's value is the capital class's (below) |

Every proportion in `parts/raider_carrier.py` is a percentage of the length read off the reference, so the length is
the one free number (`CarrierSpec.length_m`). The first build was 144 m (the span fitted to the pad's own wide edge);
the resize changed no proportion.

**Cradles**, as fractions of the length from the bow spikes' tips, and at 112 m. Clock angles are seen from the bow, from
up, both sides unless 0 or 180:

| Ring | Arm's station | Pad centre's station | Pad's outer face from the axis | Clock angles | Count |
|---|---|---|---|---|---|
| drum (first collar) | 0.127 (14.2 m) | 0.171 (19.2 m) | 0.235 (26.3 m) | 0, 120 | 3 |
| mid ring | 0.214 (24.0 m) | 0.258 (28.9 m) | 0.306 (34.3 m) | 0, 60, 120, 180 | 6 |
| outer ring | 0.298 (33.4 m) | 0.343 (38.4 m) | 0.377 (42.2 m) | 0, 40, 80, 120, 160 | 9 |

A pad is 13.2 m wide at its forward edge, 9.9 m at its aft edge, 3.3 m deep and 1.6 m thick; its clamp pins' tips are
17.1 m apart and lie below the pad's outer face, so a wing rests over them. The pins were not moved or shortened.

### Hardpoints

The ships' contract (`docs/assets-civilian.md`, "Hardpoints") with no muzzles, turrets or RCS, plus:

- **`cradles[]`**, eighteen, named `<ring>_<clock>` with `_l` or `_r` off the centre line (`outer_040_r`, `mid_180`,
  `drum_120_l`): `ring`, `clock_deg` (positive to starboard), `position` (on the pad's outer face, 1 m forward of its centre, so a docked fighter's tail stays clear of the next
  ring's arm),
  `forward` (the docked fighter's nose: the carrier's bow, `[0, 0, -1]`), `up` (its back: straight out from the axis),
  `approach_from` (60 m out along `up`), `approach` (the way it comes in: `-up`) and `release` (the way it leaves: `up`).
  A docked fighter rests its belly on `position` with its own box centred over it; the game adds the fighter's belly
  offset from its own bounds (`LookScene.docked_transform` does this for the look sheet). A Delta-V's box (17 x 2 x
  7.2 m) comes down from 60 m onto every cradle without touching a collision shape, and rests within 0.1 m of its pad
  (a test, at 112 m).
- **`pods[]`**: one, `main`, on the axis at the bell's mouth (station 0.970), exhaust aft, radius 2.5 m. No retro engine
  is modelled; how the carrier brakes and turns is stage 2's flight model.
- **`jump_point`**: 250 m ahead of the bow on the axis, facing forward, mouth radius 100 m (the hull's half diagonal is
  60 m).
- **`nav_lights`**: red and green on the boxes' outer flanks, white on the slab's top, a lamp over the spine, and the
  hangar mouth's glow as the `cabin` light. **`cockpit_camera`**: the sensor housing's bow face, looking forward.
- **`chunks[]`**: `drum`, `ring_mid`, `ring_outer`, `core`, `box_l`, `box_r`, each with a joint. A ring's cradles and
  spokes go with their ring; the drum's cradles, spikes and bow fittings with the drum; the spine, centre section and
  engine cluster are the core.

### Collision

One piece per break-up chunk, 162 shapes in all, inside the carrier's budget (64 shapes a piece, 32 points a hull):

| Piece | Shapes | What they are |
|---|---|---|
| `drum` | 31 | the drum (a 16-sided hull), the rim in 10 sectors, the sensor housing, 10 spikes, 3 cradles |
| `ring_mid` | 34 | the ring in 12 sectors, 2 spokes (a capsule and a block each), 6 cradles |
| `ring_outer` | 47 | the ring in 16 sectors, 2 spokes, 9 cradles |
| `core` | 30 | spine, slab, 2 beams, 4 bars, 16 pipe elbows, engine mount, 4 tanks, engine and bell |
| `box_l`, `box_r` | 10 each | the body and the nose (hulls of their outlines), the bow plate, 2 housings, the fitting, 4 skirt fins |

A cradle is three shapes: a capsule for the arm, a box for the beam, a box for the pad with its clamp pins. The hangar
slats are not cut into the boxes' collision (they are 2 m deep recesses).

Coverage at the default 0.5 m surface spacing, at 112 m: **covered 1.0** with tolerance 1.0 m (worst gap 0.54 m: the
bell's petals and the clamp pins' links stand proud of their shapes), **within reach 1.0** with reach 2.5 m (worst
excess 1.57 m; the same after M8-T07 moved it onto M7's builder). Each hull shape has a hit volume, its tightest box: the
game's hit sweeps know boxes and capsules only, so bolts and rams meet the box while Jolt collides with the hull itself. The rings' openings are open (a test probes points between the drum, the mid ring and the outer
ring).

### Fidelity (Q10)

```
.venv/bin/python3 -I tools/refview/compare.py references/Rader_strike_carrier.stl raider_strike_carrier --length 112 --right=+y --up=+z --aft=+x
```

| View | IoU | | Dimension | Mesh / STL |
|---|---|---|---|---|
| top | 0.979 | | length | 1.000 (112.0 / 112.0 m) |
| side | 0.969 | | width | 0.998 (85.5 / 85.6 m) |
| front | 0.981 | | height | 0.998 (84.3 / 84.5 m) |

Verdict: PASS, with no shift. The bar is 0.90 a view and 10 % a dimension.

### Surface: show green (the maintainer, 2026-11-15)

The standing rule: colours and texture from show images of this ship and of the raiders. The maintainer chose option A,
"show green", from three candidates on the first option sheet (B, the Delta-V's worn grey-brown all over, and C, a paler
salvaged grey-green, were dropped and are no longer in the code). `styles/raider_capital.py` holds it:

| Part | Paint |
|---|---|
| flanks, drum, the rings' bands | dark green, #3E5647 |
| decks, the slab, the tanks | dark grey, #4A504B (first #858A84, which washed out under a square-on sun) |
| structure: rings, arms, beams, recesses, the bow face | dark olive, #3B4239 |
| cradle pads | the raiders' ochre, #8C6A32 |
| lit hangar slats | pale green #9CA894, glowing at 0.35 (first #DDE6D4 at 1.6, which bloomed to plain white) |
| engine | dark metal, a yellow-white throat glow |

Plating: big plates (9 x 6 m fields, cut twice), frames every 7.5 m, little plate to plate tone, light wear. The low
texture set draws the boxes' slope breaks and belt and the drum's and the rings' quarter joints; the high set adds the
frame lines, the plating with its tone, sheen and grime, and small proud hatches.

Sheets (gitignored, `references/screenshots/M12-T19 raider strike carrier/`): `look_sheet.png` (three quarters on from
50 m, 500 m and 5 km, then port, top and front, a Delta-V docked on the top outer cradle for scale), made with
`scripts/hull_sheet.sh raider_strike_carrier "<folder>"`. The first sheets (144 m, the three options) are in the
subfolder `stage 1 (144 m, options)`.

### In the game (M12-T19 stage 2)

`docs/architecture.md` §19.18. The hull is the capital class `strike_carrier` with `assets/ships/raider_strike_carrier.tres`:
13 500 t, 2 m/s2 of thrust, a 4 degree a second turn, 10 000 hull points, jump capable. Jolt collides with the 162 shapes
(the hulls as convex polygons); bolts and rams meet the same shapes with each hull as its bounding box. The cradles drive
`CarrierDock`: `position`, `forward` and `up` place a docked Delta-V, and `approach_from` is where a returning one is taken
over by its cradle. The `jump_point` anchor is where it opens the point it leaves through.

### Open for the human tester `(H)`

- Whether the 7 cm texel reads well enough from 50 m before T05's shared detail layer.
- The decks' sheen: square-on to the sun a deck shows one bright highlight; the plating stays readable beside it.
- VRAM and frame cost on the target GPU (the sheets were shot on oscar's R9 280X).

## `raider_battle_wagon` (M8-T09)

`tools/procgen/assets/raider_battle_wagon.py` on `parts/raider_wagon.py`, `styles/raider_capital.py` (`WAGON_SURFACE`) and
`parts/layouts.py` (`raider_wagon`). The shape is described in `docs/design-references.md`, "Raider Battle Wagon". It moved
here from M10-T20 (M8's Q8) with its rules: built from images, with weapons, after the strike carrier.

### Measurements

There is no reference model (M10's Q10): every proportion in `parts/raider_wagon.py` is a percentage of the length read off
the three-view sheet (`raider battle wagon.png`, 1 000 px wide), so the length is the one free number
(`WagonSpec.length_m`), and the shape's check is the maintainer's look at the sheet beside it.

| | |
|---|---|
| Reference | `raider battle wagon.png` (top, side, front, stern, two perspectives), `raider ships and battle wagon.png` (mood only) |
| Up | the tubes above and below: the sheet's own Delta-V is seen in plan in the lower left view (the top view) and edge-on in the view above it |
| Length | **275 m** over the antenna spikes, the hull about 250 m (the maintainer, 2026-11-18). The sheet's Delta-V is 12 px long and 27 px across; at 7.4 m by 16 m that is 0.60 m a pixel, and the ship is 460 px long |
| Span, height | 160.6 m both: the ring, 0.58 of the length across (268 px) |
| Tubes | **2**, above and below the core, each 177 m long, 46 m by 23 m outside and 38.9 m by 16.1 m inside, open at both ends |
| Triangles | 9 948 (budget 20 000); Godot's importer adds the levels of detail |
| Atlases | one per chunk: 2 048 px for the core, the ring and each tube, 1 024 px for the bow and the engine block; 14 to 25 cm a texel; low and high texture sets |
| Video memory | 55 MB for the hull with one texture set and its turret model (869 to 924 MB in the look scene, 1 920 x 1 080), measured on the maintainer's RX 6950 XT |
| Mass (informational) | 101 400 t from the skin's area at 260 kg/m2; the game's value is the capital class's (below) |

Stations along the length, as fractions of it from the spikes' tips (at 275 m):

| Part | From | To | Across |
|---|---|---|---|
| antenna spikes (two long, 15 m from the axis; one short under the eye) | 0 | 0.148 (40.7 m) | |
| eye frame, on its neck | 0.093 | 0.148 | 22.7 m across its rim |
| bow cone, eight flat faces; four booms from the eye's rim to its shoulders | 0.148 | 0.239 (65.7 m) | 33.6 m to 63.3 m across flats |
| core, eight-sided | 0.239 | 0.813 (223.6 m) | 63.3 m across flats |
| frames carrying the tubes, five before the ring and five behind | 0.346 to 0.440 | 0.704 to 0.798 | 69.3 m across flats |
| launch tubes, their axes 45.65 m above and below the ship's | 0.254 (69.9 m) | 0.898 (247.0 m) | |
| deck arms on each side, to the ring's opening (58.6 m from the axis) | 0.239 to 0.465 | 0.680 to 0.840 | 8 m thick |
| ring, its station 0.572 (157.3 m) | 0.461 | 0.683 | 116 m opening, 160.6 m rim |
| engine block: three slabs, eight nozzles in two rows of four (12.1 m across each) | 0.813 | 1.0 | 86 m wide, 62 m high |

### Hardpoints

The ships' contract (`docs/assets-civilian.md`, "Hardpoints") with no muzzles or RCS, plus:

- **`tubes[]`**, `upper` and `lower`: `mouth_fore`, `mouth_aft`, `clear_half_m` (the way through at the axis level: 19.4 m
  either side, and 3.7 m up and down at the walls, where the corners are cut), `forward`, `up`, and two `lanes` each
  (`upper_r`, `upper_l`, `lower_r`, `lower_l`), 9.7 m either side of the tube's middle: a Delta-V (17 m across) to a lane,
  1.2 m from its neighbour's wing tip and 1.3 m from the wall. A lane has `exit` (20 m ahead of the bow mouth),
  `approach_from` (40 m behind the stern mouth) and its five `berths` by name. Four lanes: the "four launch tubes" of the
  plan are two tubes with two lanes each, as the sheet has it (the maintainer, 2026-11-18).
- **`cradles[]`**, twenty berths named `<tube>_<side>_<row>` (`upper_r_1`), row by row from the bow mouths back, so the
  first fighters aboard take the front of every lane: `tube`, `lane`, `row`, `position` (the fighter's belly, 1 m under
  the tube's axis: it floats in the middle of the tube), `forward` (the bow), `up`, and the two keys that make it a lane
  for `CarrierDock`: `release_to` (it is pushed ahead along its lane and let go there) and `approach_from` (it is drawn in
  from there). The first berth is 14 m behind the bow mouth, the rows 12 m apart. A Delta-V's box flies every lane from end
  to end without touching a collision shape (a test).
- **`turrets[]`**, eight, named `<fore|aft>_<dorsal|ventral>_<r|l>`: on the four deck arms above and below, 47.6 m (before
  the ring) and 46.8 m (behind it) from the axis, so one looks into each octant of the sky. `arc_deg` 200, `barrel_m`
  11.25: the shared turret (`parts/turret.py`) at two and a half times its size (a 9 m base), written as the hull's own
  `<id>_turret.glb` in its paint.
- **`missile_racks[]`**, four, `rack_045`, `rack_135`, `rack_225`, `rack_315`: in the diagonal bays of the ring's bow face,
  each a box of six cells. `position` (the middle of its face), `forward` (the way its missiles leave: ahead and 39 degrees
  outward), `up`, `cells`.
- **`pods[]`**: eight, `<top|bottom>_<inner|outer>_<l|r>`, each at its nozzle's mouth (station 0.974), exhaust aft, radius
  5.4 m.
- **`jump_point`**: 450 m ahead of the bow on the axis, mouth radius 130 m (the ring's rim is 80 m from the axis).
- **`nav_lights`**: red and green on the ring's rim at nine and three o'clock, white on its top, a lamp over the upper
  tube's bow mouth, and the eye as the `cabin` light. **`cockpit_camera`**: the eye, looking forward.
- **`chunks[]`**: `bow` (spikes, eye, booms, cone), `core` (the core, the frames, the arms, the lattice), `ring` (with its
  buttresses, fins, windows and racks), `tube_upper`, `tube_lower`, `engines`, each with a joint.

### Collision

One piece per break-up chunk, 142 shapes in all, inside the budget (64 shapes a piece, 32 points a hull):

| Piece | Shapes | What they are |
|---|---|---|
| `bow` | 11 | the eye, its cross bar, the neck, the cone, four booms, three spikes |
| `core` | 43 | the core, the two runs of frames, six arm hulls, and each side's lattice: a spar, two beams, two braces and four blocks a quarter |
| `ring` | 60 | the body in 24 sectors with its true section, each collar in 16, the four racks |
| `tube_upper`, `tube_lower` | 8 each | one slab per wall, so the way through is open |
| `engines` | 12 | the housing, three slabs, eight nozzles |

Coverage at the default 1 m surface spacing: **covered 1.0** with tolerance 2.0 m (worst gap 1.71 m: the ring's fins and
buttresses stand proud of its sectors), **within reach 1.0** with reach 5.0 m (worst excess 2.74 m). Both bounds are
twice the strike carrier's for a hull two and a half times its length. The tubes and the ring's openings are open (a test
probes the way through each tube and the eight bays between the lattice's beams).

### Texture atlases and the build's memory

A bake's memory goes with its atlas's texels: about 600 bytes a texel, so 2.6 GB for a 2 048 px atlas and four times that
for a 4 096 px one. The first build put the whole hull on one 4 096 px atlas (as the strike carrier is), took about 10 GB
and gave 20 cm a texel; with other work running it was killed for memory. `core/civilian.py`'s `write_hull_atlases` writes
a hull with an atlas per chunk, baked one after another: **2.6 GB at its peak**, 100 s. `<id>.glb` holds every chunk's
faces as a surface `hull_<chunk>` drawn with that chunk's maps (`<id>_<chunk>_<map>.png`, each with its low set); the
chunk files draw with the same surfaces. `write_hull` and every other hull's files are unchanged (the strike carrier and
the Skylark rebuilt byte for byte the same before and after).

| Chunk | Atlas | Texel | Fill |
|---|---|---|---|
| `bow` | 1 024 px | 14.1 cm | 0.67 |
| `core` | 2 048 px | 23.8 cm | 0.71 |
| `ring` | 2 048 px | 21.8 cm | 0.63 |
| `tube_upper`, `tube_lower` | 2 048 px | 17.7 cm | 0.57 |
| `engines` | 1 024 px | 24.6 cm | 0.74 |

The ring's charts are cut into quarters round the axis: a chart all the way round it is 500 m long, and fitting it in set
the texel at 25 cm with a third of the atlas used.

### Surface: salvaged (the maintainer, 2026-11-18)

The maintainer chose option C, "salvaged", from three candidates on the option sheet (A, the strike carrier's show green,
and B, the reference render's worn grey-brown, were dropped and are no longer in the code):

| Part | Paint |
|---|---|
| the bow cone, the ring's faces, the tubes' mouths | grey, #5E5F5A |
| decks: the arms, the frames, the tubes' walls, the slabs, the booms | oxide red, #6B4A3A |
| structure: the bays between the frames, the lattice, the ribs, the ring's collars | dark, #34322F |
| the ring's two rim ribs; the turrets' base stripes | the raiders' ochre, #9A7636 |
| the ring's windows | pale blue-white #B4D6DC, glowing at 1.0 |
| nozzles | dark metal, a yellow-white throat glow |

Plating: 8 x 5 m fields cut twice, frames every 6.5 m, a strong plate to plate tone (0.17: plates as if taken from several
ships), medium wear. The low texture set draws the long parts' middle breaks and the ring's eighth joints; the high set
adds the frame lines, the plating with its tone, sheen and grime, and small proud hatches.

Sheets (gitignored, `references/screenshots/M8-T09 battle wagon/`): `look_sheet_final.png` (the hull as built; `look_sheet.png` is stage 1's, in option A: the reference's views beside the
build's, true to scale and in the game from 60 m, 500 m and 5 km), `option_sheet.png` (the three candidates, low and high
sets), `weapons_sheet.png` (the turrets, the racks, the lanes and their berths).

### In the game (stage 2)

`docs/architecture.md` §19.18. The hull is the capital class `battle_wagon` with `assets/ships/raider_battle_wagon.tres`:
100 000 t, 2 m/s2 of thrust, a 3 degree a second turn, 24 000 hull points, jump capable (its drive needs 240 s after a
jump, as the strike carrier's). Jolt collides with the 142 shapes; bolts and rams meet them with each hull as its box.
The berths drive `CarrierDock` (launch ahead through the bow mouths, home through the stern mouths), the turret mounts
fire `assets/weapons/turret_raider_plasma.tres` (450 m/s, 8 damage, 0.8 s, to 1.6 km) at whoever attacked it, and the racks
launch M4's guided missile at a hostile fighter within 3 km: six cells a rack, a rack again after 20 s, the ship's racks
2 s apart (`data/capitals/capitals.json`, `missile_racks.battle_wagon`).

### Open for the human tester `(H)`

- The shape against the sheet (no STL), and whether 275 m reads right beside a Delta-V and beside Babylon 5.
- Whether 14 to 25 cm a texel reads well enough from 50 m; a finer texel is more atlases (video memory), not a bigger one.
- The weapons' numbers and the hull points (first figures), and whether the racks make the escort's last wave too hard.
- Video memory and frame cost with it in a fight.
