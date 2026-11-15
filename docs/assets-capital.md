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
| `manifest.collision` | the compound collision (below): `budget`, `shape_count`, `pieces[]` (one per break-up chunk, each a list of convex shapes) and `coverage` |
| `hardpoints.cradles[]` | docking hardpoints for a carrier's fighters (below) |
| `hardpoints.jump_point` | where the ship opens its own jump point: `position`, `forward`, `mouth_radius_m` |
| `hardpoints.collision` | empty: the legacy box and capsule list is replaced by `manifest.collision` |

## Compound collision (M7's D73, built in M12-T19)

`tools/procgen/core/collision.py`, general: M7's station and every later hull use it.

- **Shapes.** A part names its collision as convex shapes: a `box` (centre, size, basis), a `capsule` (two end points and
  a radius) or a `hull` (the convex hull of a few points, found exactly for small sets and cut down to the budget's point
  count). A concave part is several shapes: `ring_sectors` cuts a ring into convex sectors so its hole stays open, and
  `prism_points` gives the corner points of a round part's hull.
- **Pieces and the budget.** Shapes are grouped by the asset's pieces (here the break-up chunks, so a chunk keeps its
  collision; D12.1's sections later). `Budget` is what one body may carry: 64 shapes and 32 points a hull by default.
  `build` merges a piece's shapes down to the budget (the pair whose joint hull adds the least empty volume first) and
  refuses a piece over it or two shapes with one name.
- **Coverage**, both ways, against the points of the visible render surface: every surface point lies within
  `tolerance_m` of a shape (`covered`, `worst_gap_m`), and no point of the shapes' joint outer surface is further than
  `reach_m` from the render surface (`within_reach`, `worst_excess_m`). The second is what keeps a ring's hole and a
  cradle's approach open: one hull round a ring fails it. A hull's distance is measured to its face planes: exact inside
  and across a face, a little short past an edge.
- **The manifest.** `collision.pieces[].shapes[]` entries are `{name, type, position, bound_radius}` plus `size` and
  `basis` (box), `radius`, `height`, `axis` and `basis` (capsule, as `hardpoints.collision` wrote them) or `points`
  (hull), all in the body frame. `core/manifest.py` validates the section; `collision.shapes_of` reads it back. The game
  builds one body per piece from it (M12-T19 stage 2, M7-T03).
- **Tests** (`tools/procgen/tests/test_collision.py`): distances, hull corners and the point budget, moves and mirrors,
  a ring covered with its hole open, one hull round a ring failing the reach check, an exact fit, a gap, an oversized
  shape, the merge order, both budgets, the section and its validation, reading it back, determinism.

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

One piece per break-up chunk, 162 shapes in all, inside the default budget (64 shapes a piece, 32 points a hull):

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
excess 1.57 m). A hull shape also carries its tightest bounding `box`: the game's hit sweeps know boxes and capsules
only, so bolts and rams meet the box while Jolt collides with the hull itself. The rings' openings are open (a test probes points between the drum, the mid ring and the outer
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

### Open for the human tester `(H)`

- Whether the 7 cm texel reads well enough from 50 m before T05's shared detail layer.
- The decks' sheen: square-on to the sun a deck shows one bright highlight; the plating stays readable beside it.
- VRAM and frame cost on the target GPU (the sheets were shot on oscar's R9 280X).
