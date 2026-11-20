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

## M10 lengths (T01)

Stage 1 of M10-T01 (Q4, Q22, Q48): every M10 hull's quoted length with its sources, the reference STL's proportions, the
fit through a jumpgate's mouth and the pipeline. **Approved by the maintainer on 2026-11-20 with the changes of Q49**
(below, "The maintainer's answers"); the rows show the approved values.
Per-hull descriptions, renders and the full axis mappings (with signs) follow in stage 2, in `docs/design-references.md`.

**Sources** (as reached on 2026-11-20; the fan wiki is read through its API, the charts as images):

- **TE**: Tim Earls, *Size Comparison Charts* 1.0 to 1.3 (19 and 26 January 1999). Earls was the visual-effects art
  director in seasons 4 and 5; the charts are the nearest thing to production figures. `isnnews.net/warlock/resources/sizecharts/Chart1.jpg` to `Chart4.jpg`.
- **TBP**: The Babylon Project wiki (`babylon5.fandom.com`) infobox or text; most of its lengths cite TE.
- **ITF**: Sierra's cancelled game *Into the Fire* (1999), its docking-bay data as quoted on TBP.
- **OG**: *The Official Guide to Babylon 5* (Sierra CD-ROM), as quoted on TBP.
- **SotG**: Mongoose, *Babylon 5: Ships of the Galaxy* (RPG), as transcribed on `d6holocron.com`; several figures are marked
  "estimated" there. **MD**: Mongoose, *Babylon 5: The Drakh*, same site.
- **B5W**: Agents of Gaming, *Babylon 5 Wars* (miniatures game), as quoted on TBP. Its scale runs about a quarter of TE's
  (Hyperion 245 m against 1 025 m).
- **WPL**: the draft "List of starships in Babylon 5" (`en.wikipedia.org/wiki/User:Jclemens/...`); it quotes TE, Mongoose and
  episode dialogue.
- **FN**: the length written into the STL's file name. **est.**: my estimate, no published figure.

**Columns.** *Axes*: the STL axes that carry length, width and height (up assumed to be file z, the print orientation; the
bow's sign is read in stage 2). *Box*: width x height in metres at the chosen length, from the STL's bounding box. *Gate*:
whether that box passes the mouth, an ellipse 2 400 by 1 510 m (Q22): **yes** (the box's corners inside the ellipse),
**rolled** (only turned 90 degrees about its length), **no**. *Opens*: the first list of hulls that open their own jump
points (Q22; T03 finalises it): **own**, **gate** (uses a gate or another ship's point), **shimmer** (Q44).

### Capital ships

| Id | Task | Hull | Length (m) | Sources | Alternatives | Axes L/W/H | Box W x H (m) | Gate | Opens | Pipeline | Flags |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `ea_omega` | T21 | Omega destroyer | **1 714.3** | TE 1.0, 1.2; TBP | ~1 700 (forums); 989 (an RPG sheet, outlier) | x/y/z | 474 x 545 | yes | own | capital | |
| `ea_hyperion` | T22 | Hyperion heavy cruiser | **1 025.39** | TE 1.2; TBP (beam 286.5); WPL | 245 (B5W) | y/x/z | 249 x 267 | yes | own (TBP: jump engine) | capital | **Launches 6 Starfuries and 2 shuttles** (TBP, WPL; Q49) |
| `ea_nova` | T23 | Nova dreadnought | **1 502.1** | TE 1.2 (labelled "EA Gunboat"); TBP; SotG | | y/x/z | 210 x 446 | yes | own | capital | TE names it a gunboat; TBP and SotG give the figure to the Nova |
| `ea_warlock` | T24 | Warlock destroyer | **1 992.4** | TE 1.0, 1.2 | | y/x/z | 575 x 349 | yes | own | capital | |
| `narn_gquan` | T25 | G'Quan heavy cruiser | **1 500** (est.) | none canon | 450 (B5W); 1 000 (the STL is modelled exactly 1 000 units long); "over 1 km" (unsourced) | y/x/z | 943 x 206 | yes | own (TBP: jump yes) | capital | **No published length.** B5W sizes it with the Primus (450 against 455 m); at the Primus's 1 586 m that is about 1 500 to 1 600 m. Launches 6 to 12 Frazi (B5W, Traveller) |
| `centauri_vorchan` | T26 | Vorchan warship | **360** | ITF (360 long, 475 beam, 305 draught) | | x/y/z | 465 x 300 | yes | gate (Q22: a small cruiser; TBP says it jumps) | capital | ITF's three dimensions match the STL within 3 %; the beam is wider than the length (two crossed crescents) |
| `centauri_primus` | T27 | Primus battlecruiser | **1 586** | ITF (1 586 x 1 023 x 455); FN | 455 (B5W) | y/x/z | 888 x 284 | yes | own | capital | ITF's beam and draught are 15 % and 60 % bigger than the STL's; the STL is flatter. **Launches none**: no fighter bays (OG; Q49). The mass-driver STL has the same box, so the driver sits inside the envelope |
| `minbari_sharlin` | T28 | Sharlin warcruiser | **1 600** | TBP; WPL (Mongoose, after Brandon Bray: 1 600 long, about 1 900 tall) | | x/y/z | 557 x 1 952 | rolled | own | capital | Taller than long: the STL's height-to-length (1.22) matches the 1 900/1 600 quote. Passes the mouth only on its side; it opens its own points anyway |
| `drazi_sunhawk` | T29 | Sunhawk | **197** | ITF and SotG (197 x 135 x 49) | 350 (FN; WPL, mass 280 kt): wrong (Q49) | x/y/z | 142 x 45 | yes | gate (no Drazi jump engine; SotG lists no hyperdrive) | capital | ITF's proportions match the STL (1 : 0.69 : 0.25 against 1 : 0.72 : 0.23). Can carry one Sky Serpent on a dorsal cradle (TBP, WPL) |
| `drazi_stormfalcon` | T30 | Stormfalcon | **820** | SotG (est.); FN | | x/y/z | 706 x 200 | yes | own (SotG hyperdrive) | capital | SotG complement: 12 Star Snake light fighters, 1 Sky Serpent, 2 shuttles |
| `brakiri_avioki` | T31 | Avioki cruiser | **1 024** | SotG; TBP ("over a kilometre") | | x/y/z | 711 x 1 338 | yes | own (SotG, TBP) | capital | The STL's blade wing is taller (826 units) than the hull is long (632). **Launches none**: SotG lists 2 assault shuttles (Q49) |
| `vree_xill` | T32 | Xill | **350** (diameter) | SotG (est.) | 500 (a hidden, unsourced TBP note) | x (diameter)/y/z | 350 x 97 | yes | gate (Q22) | capital | OG: jump engine, 15 antimatter cannons, 1 500 troops |
| `isa_whitestar` | T33 | White Star | **475.6** | TE 1.0, 1.3; TBP; WPL | | x/y/z | 222 x 78 | yes | own (its signature) | capital | Opening its own points is canon and iconic; an exception to Q22's "small ships use gates" |
| `isa_victory` | T34 | Victory destroyer | **2 012** | episode dialogue ("a mile and a quarter", per WPL); Q49 | 2 990.31 (TE 1.0, as *Excalibur*; TBP; SotG): too big for a gate | x/y/z | 1 324 x 1 107 | yes | own (a destroyer) | capital | |
| `shadow_battlecrab` | T35 | Shadow battlecrab | **1 500** (the leg span, Q49) | SotG ("Shadow cruiser") | 1 000 (merzo.net chart); 1 to 2 km (h2g2); TBP: "variable" | span x / run y / z | run 641, height 310 | yes | shimmer (Q44) | capital + organic (T06) | The span is the STL's largest extent (148 units); the body's run is 63. Fighters: 6 (B5W) to 36 (SotG, Traveller) |
| `vorlon_destroyer` | T36 | Vorlon destroyer (Q49) | **131** | FN; TBP (the Vorlon transport, the same shape) | 925 (SotG "Vorlon Destroyer") | y/x/z (round) | 20 x 20 (body only) | yes | own | capital + organic | **Show images: the folder `references/show/m10/vorlon_heavy_cruiser/`** (named before Q49). Petals from its two petal STLs (stage 2). No source lists fighters |
| `drakh_carrier` | T37 | Drakh carrier | **3 316** (Q49) | TE 1.0 (the Drakh cruiser, "essentially identical" in shape, TBP) | 14 000 (MD); "much larger than a cruiser" (TBP) | y/x/z | 1 021 x 504 | yes | **gate** (canon: no jump engine; it ran for a gate in "Lines of Communication") | capital | MD complement: 10 heavy or 40 light raiders, 40 shuttles |
| `drazi_firehawk` | T59 | Firehawk | **197** (Q49) | the Sunhawk's length: the STL is the Sunhawk's hull | 270 (SotG, est.); 350 (FN): wrong | x/y/z | 142 x 44 | yes | gate (Q22) | capital | SotG's Drazi "Firehawk Advanced Cruiser", a Mongoose design (not seen in the show) carrying a solar cannon. **Launches none** (Q49). Its STL has the Sunhawk's box to 1 % (the same hull, other weapons) |
| `vorlon_heavy_cruiser` | T60 | Vorlon heavy cruiser (Q49) | **1 528** | FN; ITF gave the heavy cruiser 1 330 | "over 1 300" (a B5 game, per WPL and TBP, for a "Star Dreadnought") | y/x/z | 461 x 302 | yes (ellipse 0.08) | own | capital + organic | The file says "Dreadnought"; it is the heavy cruiser (Q49). **Show images: the folder `references/show/m10/vorlon_dreadnought/`**, plus `vorlon_heavy_cruiser/Pasted image.png`. B5W: 6 Vorlon fighters, 2 shuttles |

### Fighters

| Id | Task | Craft | Length (m) | Sources | Alternatives | Axes L/W/H | Box W x H (m) | Flags |
|---|---|---|---|---|---|---|---|---|
| `narn_frazi` | T38 | Frazi | **17.53** | TE 1.1; TBP; SotG | | y/x/z | 8.8 x 3.6 | |
| `centauri_sentri` | T38 | Sentri | **22.25** | TE 1.1; TBP | 22.26 (SotG) | x/y/z | 36.0 x 9.5 | Span wider than length; TE's drawing agrees (about 38 m) |
| `minbari_nial` | T39 | Nial | **22.23** | TE 1.1 ("Minbari Fighter"); TBP | | y/x/z | 7.7 x 7.9 | **"Liara"**: no such craft on TBP or the web (the nearest name is the *Liandra*, a 160 m Ranger ship); the file's three-armed fighter is the Nial |
| `drazi_sky_serpent` | T39 | Sky Serpent | **19.12** | TE 1.1 ("Drazi Fighter"); TBP; FN (19 m) | 15.3 (ITF); 30 (SotG, a two-seat variant) | y/x/z | 13.1 x 4.7 | |
| `brakiri_falkosi` | T40 | Falkosi | **15** | SotG (est.) | | y/x/z | 12.1 x 8.7 | The only figure |
| `drakh_fighter` | T40 | Drakh fighter | **17.8** | MD ("light raider", est.) | 76.2 (MD "heavy raider") | y/x/z | 9.1 x 8.6 | |
| `shadow_fighter` | T41 | Shadow fighter | **15.3** | ITF (via TBP); SotG | | x/y/z | 10.9 x 6.3 | |
| `shadow_scout` | T41 | Shadow scout | **201** | FN | 350 (SotG) | x/y/z | 168 x 120 | A small capital ship: **capital framework with the battlecrab's organic parts** (Q49). Shimmers (Q44) |
| `vorlon_fighter` | T42 | Vorlon light fighter | **21.92** | TE 1.1; TBP | 25.5 (a B5 game, per WPL; SotG) | y/x/z | 15.9 x 15.9 (petals open) | TBP: Vorlon fighters seem to jump on their own (for T04) |
| `ea_thunderbolt` | T50 | Thunderbolt | **16.24** | TE 1.1 | 15.3 (TBP, SotG) | turned 42 degrees about file z, then 168 x 228 x 89 units | 22.0 x 8.6 (if the shorter in-plane extent is the length) | **The STL is not axis-aligned**: refview needs a turn first (stage 2) |

All fighters: the fighter pipeline (the Starfury's); none opens a jump point (Q22).

### Big civilians and small craft

| Id | Task | Hull | Length (m) | Sources | Alternatives | Axes L/W/H | Box W x H (m) | Gate | Opens | Pipeline | Flags |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `ea_panama` | T51 | Panama transport | **180** (est.) | none | | y/x/z | 45 x 29 | yes | gate | **civilian** (Q49) | "Panama" is not on TBP; the show images match TBP's "White Star" type commercial transport (no length, no jump engine). Two of the maintainer's stills seem to show it inside a docking bay: at 180 m its section just fits B5's main bay core (45.5 x 30 m) |
| `ea_explorer` | T52 | Explorer | **6 103** | SotG; WPL (citation needed); TBP ("over six kilometres") | | y/x/z | 846 x 2 526 (975 without the mast) | no (the mast), hull yes | own (builds gates) | capital | The long antenna mast is 2.5 km tall at this length |
| `ea_asimov` | T53 | Asimov liner | **600** | TBP (unsourced) | | y/x/z (sphere) | 347 x 347 | yes | gate (TBP: no jump engine) | capital | **One generator with T56** (Q49): the liner variant |
| `ea_construction_tender` | T55 | Construction tender | **50** (est.) | none | | y/x/z | 70 x 24 (truss span) | yes | gate | **civilian** (Q49) | No class of this name found; the still is a work pod by a construction frame. A tug with claws and a truss |
| `ea_mining_transport` | T56 | Mining transport | **600** (the Asimov's hull) | none | | y/x/z | 330 x 330 | yes | gate | capital | **T53's generator, the mining variant** (Q49): the Asimov's sphere with cargo doors (closed 182, open 206 units long), doors moving (Q43); the show still in its folder (an orange-engined freighter) is a different ship |
| `ea_shuttle` | T57 | EA shuttle | **18.64** | TE 1.1; TBP | 18 to 25 by variant (SotG) | y/x/z | 9.2 x 5.3 | | | civilian | |
| `ea_atmo_shuttle` | T57 | EA atmospheric shuttle | **25.59** | TE 1.1; TBP ("Kestrel" class) | | y/x/z | 45.6 x 8.6 | | | civilian | Wingspan 1.8 times the length (TE's drawing: about 1.45) |
| `centauri_shuttle` | T58 | Centauri shuttle | **36** | SotG | | x/y/z | 52 x 13.5 | | | civilian | |
| `minbari_flyer` | T58 | Minbari Flyer | **29.19** | TE 1.1; TBP | | x/y/z | 13.5 x 6.0 | | gate (TBP: jump yes; Q22: small craft never) | civilian | |

The Falkosi and the Sentri have no carrier in M10 (Q49): the sources give the Avioki and the Primus no fighters.

Cross-check on a hull already built: SotG gives the raider strike carrier "118 m (estimated)", 5 % over the 112 m chosen
in T19 (Q26).

### The maintainer's answers (Q49, 2026-11-20)

All lengths approved, with these changes (already in the rows above): the Sunhawk and the Firehawk 197 m (the files'
350 m are wrong); the Drakh carrier 3 316 m, using gates; the Victory 2 012 m, still opening its own points; the Vorlon
remap (T36 the 131 m destroyer with its petals, T60 the 1 528 m heavy cruiser, no separate dreadnought); the
battlecrab's 1 500 m is its leg span. Launches follow the sources: the Hyperion 6 Starfuries and 2 shuttles, the Avioki,
the Firehawk and the Primus none. Pipelines as proposed (the Panama and the construction tender civilian, the Shadow scout
on the capital framework, T53 and T56 one generator). The jump-point list below is T03's starting point.

**Jump points, first list** (for T03): own for the Omega, Hyperion, Nova, Warlock, G'Quan, Primus, Sharlin, Stormfalcon,
Avioki, White Star (canon, though small), Victory, the Vorlons and the Explorer; gates for the Vorchan, Sunhawk,
Firehawk, Xill, Drakh carrier (canon) and every civilian; the Shadows shimmer (Q44). Only the Explorer (its mast) cannot
pass a gate; the Sharlin passes only rolled.

**Vorlon show folders** (gitignored, named before Q49, not renamed): `references/show/m10/vorlon_heavy_cruiser/` shows
the T36 destroyer's hull (the transport shape: 03, 04 with its petals open, Pasted image (2) and (3)), except
`Pasted image.png`, a close view of the T60 hull's body; `references/show/m10/vorlon_dreadnought/` shows the T60 heavy
cruiser (the long forward claws).
