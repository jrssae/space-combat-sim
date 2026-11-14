# Babylon 5 station: measurements for the generator (M7-T01, for T02, T04, T05 and T11)

The station's shape, sizes and colours, read off the maintainer's references (Q1) for `babylon5_station` (D72). The
proportions come from the STL with `tools/refview`; the colours, surfaces and lights come from the images. Nothing from the
references goes into git or into a generator: T04 builds its own geometry from the numbers on this page, and
`docs/design-references.md` ("Babylon 5 station (M7)") has the written description. It is a plan, like
`docs/assets-civilian.md` was: T04 and T05 replace sections with the as-built numbers and add the compare scores.

## Sources

All gitignored, never committed, never traced.

| File | What it is | Used for |
|---|---|---|
| `references/EA Babylon 5 Station.stl` | fan-made 3D-print model, one closed solid, 332 271 triangles | every proportion on this page |
| `references/Babylon 5 station scematic.jpg` | Andy Crook's blueprint: side, top, front, rear and iso line drawings | layout check, vane and arm count, panel lines |
| `references/babylon 5 station side front.jpg` | CG model render on a grey card: top, side, front and rear | colours in soft light, red trim, cargo modules |
| `references/Babylon 5 details.avif` | Lawrence Miller's blueprint sheets (profile and top views with lettered keys, the Blue section detail, a cut-away) | part names, "Cobra Bay Launch Arms, 4", which parts turn |
| `references/T40 seam references/babylon 5 station colors.jpg` | show CG still, credited "PTEN/Warner Bros 1996-8", lit from the upper left | the primary colour source |
| `references/T40 seam references/babylon 5 docking sphere close up.jpg` | fan render (RJB/Mallacore on Andy Crook's model) of the bow from below and ahead | the docking aperture, bow spine, lights |
| `references/T40 seam references/babylon 5 docking sphere to body close up.jpg` | fan render (F. Passaro) of one Cobra arm on the docking sphere | the Cobra hatches, markings, plating |
| `references/T40 seam references/babylon 5 station rear reactor close up.jpg`, `... close up 2.jpg`, `... 3.jpg`, `... 4.jpg` | untextured renders of the reactor, shaft, torus disc and truss spine | the aft end's detail |
| `references/maintenance bot.webp` | a MaintBot model sheet (top, side, front, iso) | T11's bot |

Views and crops made for this task are in `references/screenshots/M7-T01 station references/` (gitignored): the STL's
orthographic set (`stl_view_*.png`, `stl_silhouette_*.png`, `stl_sections.png`), zooms of the bow, the vanes and the aft end
(`stl_zoom_*.png`), the side and top views with every section boundary marked (`sections_annotated_port.png`,
`sections_annotated_top.png`), and crops of the blueprint keys and the Cobra hatches.

## STL conventions and scale

- File units are unknown (print units). The long axis is the file's **x**, 2 370.85 units; y spans 329.17 and z 890.80.
- The **bow is at file +x** (x = +1 060.19), the reactor at file -x (x = -1 310.66). Up is file **+z**: the cargo modules and
  the dorsal spine sit on +z.
- The drum's axis is the file's x axis: y and z are symmetric about 0, so the box centre in the cross plane is the axis.
- Mapping into the ship frame (x starboard, y up, z aft from the bow tip): `--right=-y --up=+z --aft=-x`.
- Scaled to the game's 8 000 m: **3.3743 m per unit**. Every number below is in metres at that scale, in the ship frame,
  z measured aft from the bow tip, x and y about the drum axis. The game's frame (D72) has the bow at -Z; the generator then
  centres on its visible surface's centroid as every asset does.

```
.venv/bin/python3 -I tools/refview/refview.py "references/EA Babylon 5 Station.stl" --name b5_station \
    --length 8000 --right=-y --up=+z --aft=-x
```

## Overall size

| | Metres | Set by |
|---|---|---|
| Length | 8 000 | bow spike tip (z 0) to the reactor's aft face (z 8 000) |
| Width (span) | 1 111 (x ±555) | the vane booms' mounts |
| Height | 3 006 (y ±1 503) | the vane tips |
| Body without vanes and booms | 834 wide, y -417 to +565 | the drum's bands (r 417) and the cargo modules' tops |

The stand-in `b5_station` used a drum 890 m across (1/9 of the length). The STL's widest drum band is 834 m across and the
long middle 660 m: about 1/10 and 1/12 of the length.

## Sections, bow to stern

r is the radius from the drum axis. "Turns" is the reading of the references (next section); the maintainer confirms it.

| # | Section | z start | z end | Size | Turns? |
|---|---|---|---|---|---|
| 1 | Bow spike (fork) | 0 | 560 | a flat fork on top of the bow: tip at y 310 to 330, top rising to y 380 at z 450; two prongs, the slot between them x ±50 from z 0 to 420, outer edges x ±60 at the tip widening to ±180 at z 500. A pylon at z 490 to 560 drops from it to the aperture ring | no (frame) |
| 2 | Docking aperture | 470 | 560 | a ring round the axis: toothed outer rim r 133 to 157, the door disc r 110 with a cross-shaped door (four leaves, arms about 40 m wide) at z 485 | ring: frame (the pylon holds it); doors: see below |
| 3 | Docking sphere ("Blue Section Command Sphere") | 560 | 935 | sphere, r 180 at z 590, widest r 277 at z 790, r 250 at z 935 | yes |
| 4 | Waist | 935 | 1 330 | a core r 185 to 190 between the two bodies, with exposed frame and pipes | yes |
| 5 | Cobra-bay arms, four | 620 | 1 420 | at 0, 90, 180 and 270 degrees (top, starboard, bottom, port). Head z 620 to 1 000 on the sphere: outer face r 284 at z 650, r 324 at z 800, r 274 at z 950, two forward prongs at z 620 to 700. Hatch section z 1 000 to 1 300: outer face r 243, inner r 203, 94 m wide. An ellipsoid knob at the aft root, z 1 340 to 1 420, r 240 to 298 | yes |
| 6 | Forward body | 1 330 | 1 690 | barrel r 272 at z 1 340, widest r 329 at z 1 540, r 303 at z 1 640; a ribbed rim at its front (z 1 330 to 1 400). Four small pods at the arm angles, z 1 450 to 1 650, outer r 350 to 368 | yes |
| 7 | Ring | 1 690 | 1 790 | toothed ring r 344 to 408 | yes |
| 8 | Forward band ("Red section") | 1 790 | 2 340 | cylinder r 417 with rounded front shoulder (r 408 at z 1 790), step down to r 385 at z 2 340 | yes |
| 9 | Green zone | 2 340 | 4 800 | cylinder r 330; a slightly wider band r 346.5 at z 3 340 to 3 800; raised stringers (r 337) along its length, seen from below at x 0, ±220 and ±320 | yes |
| 10 | Aft band | 4 800 | 5 460 | cylinder r 417 (r 352 at z 4 790, full by z 4 840), rounded aft shoulder to r 382 at z 5 440 | yes |
| 11 | Neck | 5 460 | 5 560 | r 295: the gap between the turning drum and the stationary hub | bearing |
| 12 | Hub drum | 5 560 | 5 790 | cylinder r 347, the booms' roots on its flanks (x ±445 to ±488) | no |
| 13 | Cone and delta fins | 5 790 | 6 360 | cone r 335 down to r 90; two flat delta fins, y ±33 thick, tips at x ±522 (z 5 770 to 5 940), roots meeting the cone at z 6 330; four strut tubes inside the cone's flanks | no |
| 14 | Truss spine | 6 360 | 7 120 | open box truss r 104 (longerons, bars, clamps; reactor close-ups 2 to 4) | no |
| 15 | Torus disc ("Generator Torus Housing") | 7 120 | 7 300 | disc r 256 (z 7 160 to 7 280), face r 205 at z 7 140; radial ribs on the face, blocky teeth round the rim | no |
| 16 | Shaft | 7 300 | 7 760 | cylinder r 79 with exposed machinery in recessed bays | no |
| 17 | Reactor | 7 760 | 8 000 | drum r 168 to 172; aft face a torus of bulging pipe sections round a flat central disc, ribbed shell with chevron grilles and railings; aft cap r 98 at z 7 990 | no |

Frame parts that run along the drum:

| Part | z | Size | Turns? |
|---|---|---|---|
| Dorsal spine ("Brown section") | 0 to 6 360 | one continuous structure over the top. Bow: x ±165 at z 700 to 1 300, top y 435 to 465, underside y 342 to 364 over the sphere. A ramp z 1 300 to 1 750 rises to y 548. Over the forward band: a ribbed radiator block z 1 725 to 2 085 (fins every 23 m, top y 553), x ±100. Over the green zone: x ±60 to ±90, underside y 417. A second radiator block z 5 070 to 5 340. Over the hub it sits at y 472, then slopes down the cone's top to the truss at z 6 360 | no |
| Cargo modules | 2 834 to 4 321 | six boxes on the spine, 213 m long at a 254.6 m pitch (z 2 834, 3 089, 3 344, 3 598, 3 853, 4 108 to +213), x ±108, y 437 to 560 | no |
| Observation dome | 1 050 to 1 180 | a dome in a trapezoid hatch on the spine's top, x ±70 | no |
| Vane booms, two | 4 118 to 5 800 | thin rails at x ±535 to ±540 (the starboard one x 482 to 555), 40 to 60 m deep, ±65 at each vane mount. The front tip curves in to x ±482 at z 4 118; a dogleg at z 5 420 to 5 550 brings them in to x ±445 to ±488; they join the hub drum and the delta fins | no |
| Vanes ("Fusion Reactor Ionization Vanes, 6"), twelve blades | centres z 4 362, 4 805, 5 247 | three per boom, each with a blade up and one down (6 per boom, 12 in all, the blueprint's "6" counts pairs). Flat plates about 4 m thick in the y-z plane at x ±535, with a 25 m edge frame. Root at about \|y\| 100, tip at \|y\| 1 503. Chord: 175 m at \|y\| 150, 255 m at 300 (widest), 212 at 600, 167 at 900, 102 at 1 200, 88 at 1 450; a V notch in the tip | no |

Clearances between the turning drum and the frame, which T04, T06 and Q9 need:
- Dorsal spine underside to the drum's bands (r 417): **9 m**. To the green zone (r 330): about 87 m.
- Spine underside to the top Cobra arm's head (z 700 to 900): 18 to 40 m; to its hatch section: about 67 m.
- Vane booms to the drum's bands: about 118 m (x 535 against r 417).
- Q9's spin of 0.148 rad/s gives 62 m/s at r 417 and 49 m/s at r 330 (Q9 wrote 66 m/s for the stand-in's r 446).

## What turns and where the Cobra bays are

The STL is one solid, so it does not say which parts turn. The other references do:

- Lawrence Miller's Blue section sheet labels "rotation compensators, used to control spin", "inertia panels, used to maintain
  structural integrity and synchronize speed", "the 4 scanners are coordinated to match the rotation of the station", and
  "elevators from inner Blue section to habitat area of Green section". The cut-away brackets the drum as Green zone, Red
  section and Blue section, with the Brown section over the top as a separate structure. "Blast deflectors, used when rotation
  section is jettisoned from support spine" names the dorsal spine as the support that does not turn.
- The profile key lists "Cobra Bay Launch Arms, 4" and the top key "Cobra Launch Bay Support Arm, 4".
- Passaro's close-up shows one arm with a row of seven numbered, hazard-striped hatches between two DANGER stencils.

So the references read as: **the frame** is the reactor, shaft, torus disc, truss spine, cone, delta fins, hub drum, vane
booms with their vanes, the dorsal spine with its cargo modules and radiators, the bow spike and the aperture's outer ring.
**The drum** is everything from the docking sphere to the aft band (sections 3 to 10), including the four Cobra arms.

**This contradicts the planner's reading.** `docs/design-references.md` and Q3 put the Cobra bays on "the arms of the
stationary command section", two arms on the sides. In the references there are **four** arms, at 90 degree spacing, on the
docking sphere and waist (z 620 to 1 420), and they belong to the Blue section, which turns with the drum. The hatches face
radially outward, so a fighter leaves outward and spin flings it clear. Q3's own fallback covers this ("if the references say
the bays turn with the drum, released with the drum's surface speed"): at the hatch section's r 243 that is 36 m/s at
0.148 rad/s. **The maintainer decides**; the Q table stays as answered until then.

Smaller corrections to the planner's description:
- The "thin antenna masts extending far above and below" in the front view are the vanes seen edge-on, not masts.
- The vanes sit on two booms beside the aft drum, not on a hub funnel; the hub is a short drum and a cone behind the drum.
- The drum is about 1/10 of the length across at its bands, 1/12 in the middle, not 1/9.
- The docking aperture's door: the bow spike's pylon holds the aperture's outer ring, so the ring is frame. Whether the door
  disc inside turns with the drum (the show's turning docking bay) is open for the maintainer; it matters only for Q8's traffic.

## Compare targets (Q1, the 90 % rule)

T04 must reach, against the STL in the frame above: top, side and front silhouette IoU >= 0.90, and length, width and height
each within 10 % (8 000, 1 111 and 3 006 m).

```
.venv/bin/python3 -I tools/refview/compare.py "references/EA Babylon 5 Station.stl" babylon5_station \
    --length 8000 --right=-y --up=+z --aft=-x
```

- No `--model-offset` is needed if the generator authors x and y about the drum axis: the STL's box is centred on it.
- `compare.py` reads every entry of the manifest's `pieces` (T04): the frame, and the drum moved to its `pivot`, at rest.
- The pixel is 0.25 % of the length, 20 m. The vanes and booms are 19 % of the side silhouette and 18 % of the front one (edge-on
  lines), but under 3 % of the top. The front view therefore needs the vanes at x ±535 to within a pixel, and they set the
  width and height on their own: a vane 10 % short fails the height.
- The thin parts (booms 40 to 60 m deep, vanes 4 m thick, spine rails) mark at least one pixel each, as refview's rasteriser
  does; build them at their real thickness, not thinner.

## Colour scheme

Hex values read off **lit** captures, as M5-T39 recorded them: T04 paints through `capture_albedo` (`core/color.py`), which
turns a capture colour into the albedo that shows it under the game's light. Sampled as the brightest 30 % of a hue class in
each region (`station colors.jpg` unless noted), with shade values for reference.

| Where | Lit | Mid / shade | Source |
|---|---|---|---|
| Drum panels: blue-violet | #9191CB | #6F6EA4 mid; #514F7B shade (Passaro); #2B2B4B in the grey-card render | station colors.jpg |
| Drum, sphere and arm plating: light grey | #AEAEAD (highlights #CECECF) | #6D6C6B | station colors.jpg |
| Recesses, toothed rims, exposed machinery | | #353432 | station colors.jpg |
| Dorsal spine, bow spike, hub (the Brown section) | warm grey-brown #736B63 | #575049; top faces darker, #302C2D | station colors.jpg, side front.jpg |
| Cargo modules | red #974C4C | #823B3B; #5A332D in soft light | station colors.jpg, side front.jpg |
| Vanes | deep blue #20487A | #123C6E; #10244C in soft light; frames grey | station colors.jpg, side front.jpg |
| Reactor, shaft and torus disc | dark bronze grey #37322D | #25201D | side front.jpg (soft light: lift it toward the spine's brown) |
| Trim stripes: Cobra arms' edges, the bow spine's flanks | red #915555 | #6F3B3B; reads #790F0F in soft light | Passaro, side front.jpg |
| Cobra hatches and hazard bands | yellow-orange #CAA75F | #B1834A | Passaro |

Layout of the paint:
- The drum is grey with **large blue-violet panels in stepped, interlocking blocks** (each block 150 to 250 m, edges
  stepping in panel-sized notches), arranged in rings round each band. The bands' blue covers about half the area; the green
  zone has long grey strips with blue blocks between them.
- The docking sphere and forward body carry a finer **blue and grey checkerboard** (squares of about 40 to 70 m).
- The toothed rings between bands are grey with dark gaps between teeth.
- The vanes are deep blue panels in a grey frame, with a pattern of small dark rectangles over the blue (the STL's vanes are
  covered in small recesses).
- Markings: a "5" roundel and arrows on the arms (Passaro). Fan art; T05 may use its own simple markings.

## Surface and panels (for T04 and T05)

- **Drum.** Panels on a regular grid: long rectangular plates along the axis, joined by thin raised ribs; rows of small dark
  rectangles (window or hatch rows) along each band, visible as dotted lines in the STL views. Toothed rims at every band joint.
  Stringers (raised strips, about 7 m) run the green zone's length.
- **Docking sphere and arms.** Dense plating of small rectangular plates in mixed sizes, darker joint lines, raised ribs and
  pipe runs along the arms' edges, recessed bays with machinery on the arms' flanks (Passaro, Mallacore).
- **Dorsal spine and bow spike.** Angular faceted plates; open compartments on the bow spike's top with machinery inside
  (Mallacore); serrated edges along its lower flanks.
- **Aft end.** The reactor's ribbed shell with chevron vents and railings; the shaft's recessed machinery bays; the torus
  disc's radial ribs and rim teeth; the truss's longitudinal bars with clamps at regular stations.

## Near-field places (Q2, panel and window detail from 50 m)

- **The four Cobra arms**, z 620 to 1 420, r 200 to 324: hatches, stripes, markings, the forward prongs, the bay interiors as deep
  as a launch shows (T05).
- **The docking aperture**, z 470 to 560, r up to 157, and the docking sphere's front around it (to about r 200).
- **The command section**: the docking sphere ("Blue Section Command Sphere", z 560 to 935) and the bow spine over it with the
  observation dome (z 0 to 1 300).

Everything else holds from about 200 m.

## Lights (Q10): where the references show them

- A **red lamp or lit dome** on the spine's top at the observation dome, about z 1 100 (side front.jpg).
- **Red lit panels** on the bow spine's flanks near its aft end (Mallacore).
- **Yellow strip lights** along the lower face of an arm (Passaro).
- **Windows**: not readable in the show capture. The STL's dotted rows on the drum's bands and the sphere are where windows read;
  lit as Q10 says, warm white as the civilians' windows were.
- **Beacons**: none visible in the captures. Q10's extremities are the bow spike's tip (z 0), the vane tips (y ±1 503 at three z
  stations per boom), the delta fins' tips (x ±522) and the reactor's aft face.

## Candidate surfaces for the defence grid (observations only)

Where turret-like or weapon-like features appear. T02 decides the grid with the maintainer; this list decides nothing.

- **The Cobra arms' forward prongs** (z 620 to 700, one pair per arm): two barrel-like posts on each, the most gun-like features
  in any reference (Passaro).
- **The ellipsoid knobs** at each arm's aft root (z 1 340 to 1 420, r 240 to 298).
- **The delta fins' upper faces** (z 5 770 to 6 300, tips x ±522): a grille and a row of five slots on each.
- **The hub drum's dorsal block** (z 5 600 to 5 790) with a square hatch and four posts.
- **The bow spine's top**: a spiked tower on it at about mid-length (Mallacore).
- **Blueprint labels** without readable positions: "Forward Defensive Pods" (plural), "Aft Defensive Pod", "Lateral Deflector
  Array", "Forward Deflector Array", "Weapons Coolant Storage Tanks".

The drum turns, so any mount on it turns too; the frame's surfaces (spine, booms, hub, fins, bow) are the fixed ones.

## Maintenance bot (for T11)

A few metres across (the sheet gives no scale; a Starfury is 9.8 m long, so 3 to 5 m reads right). Two curved shell halves side by
side like a split egg, each a long blue-violet pod (#746FBA lit, #6662B5 mid, close to the drum's blue) with a yellow-orange band round it
(#C0A866) and a painted number ("9"). A grey truss body joins them along the middle. Below: two jointed manipulator arms (three segments
each) ending in claw grippers, and a sensor head under the front centre with a green lens. Panel lines on the shells, grey
trusses (#A29E9B lit, #83807D mid), dark joints #33312F. Colours read off the sheet's render (lit).

## As built (M7-T04, phase 1: in the working tree, awaiting the maintainer's look sheet)

`tools/procgen/assets/babylon5_station.py` (shapes in `parts/station.py`, seams, paint and windows in
`parts/station_layouts.py`, paint in `styles/earth_alliance_station.py`). The asset's origin is on the drum axis at z 4 000
(`centroid_offset` [0, 0, 4000]); the drum's frame sits on the axis at z 3 000 (`pivot` [0, 0, -1000], `axis` +Z,
`spin_rad_s` 0.148).

**Compare (Q1's 90 % rule), PASS** (`compare.py` as above, 20 m pixel, no shift needed):

| View | IoU | | Dimension | Asset / STL |
|---|---|---|---|---|
| top | 0.965 | | length | 8 000.0 / 8 000.0 m (1.000) |
| side | 0.954 | | width | 1 112.0 / 1 110.7 m (1.001) |
| front | 0.970 | | height | 3 006.0 / 3 005.8 m (1.000) |

Changed from the plan above while fitting the silhouettes (the measurements were vertex reads; these come from the STL's own
silhouettes):
- The spine over the green zone is low (underside y 365, top 415, x ±75) and the cargo modules stand on it (y 415 to 565);
  between the forward radiators and the first module it rises as a ramp to y 555, and after the last module it holds at 535
  (where D75's L10, L11, I7 and I8 sit). Over the docking sphere a deck at y 459 carries a central ramp (x ±32) rising from
  459 at z 1 300 to 548 at z 1 750 (L9 on the ramp, I6 on the deck). A box hangs under the spine at z 960 to 1 260 (y 316 to
  358). The bow spine's top is y 380 at z 500, with a tower to y 436 at z 495 to 545 (I5 on it, H1 and H2 beside it).
- The waist core is r 135 from z 1 020 to 1 300 (r 188 at its ends); the green zone is r 334 with stringers to r 341; the
  cone falls fast from the hub (r 300 at z 5 830, 225 at 5 900, then 190, 160, 130, 100 to r 90 at 6 360); the reactor is r 166.
- Clearances kept: the drum turning through 360 degrees stays at least 8 m from the frame (the neck between the drum's end at z
  5 500 and the hub at 5 508; the aperture's ring z 488 to 548 at r 133 against the door r 126; the spine 11 m over the bands);
  the test samples both surfaces every 3 m and holds 5 m.

**Pieces and budgets** (after the fix round). Drum 20 768 triangles (sphere, aperture wheel, forward body and waist, the bands, the
green zone, four Cobra arms with their heads, doors, lit door edges and clamps, four pods, toothed rims, stringers); frame 20 020 (bow spike, aperture ring and pylon, spine, ramp,
radiators, cargo, dome and lamps, hub and cone, delta fins, booms and twelve vanes, truss, torus disc, shaft, reactor). Each
piece has a 4 096 px atlas: drum 1.39 m a texel (60 % filled), frame 1.50 m (64 %). The test budget is 40 000 triangles a
piece. Full build 2 to 3.5 minutes, 9.2 to 9.4 GB peak memory (after the fix round: 40 788 triangles, 9.3 GB).

**Texel tiers (D72).** The atlases carry the paint, the seams (about 3 m lines), the windows and the weathering. The near field
comes from one shared detail tile (`core/detail_layer.py`): 16 m square at 1 024 px (1.6 cm a texel), plates of 1 to 4 m with
fine seams, a few inset hatches and a plate-to-plate tone, seamless; each surface's `world_detail` names it and
`MeshAssets.apply_world_detail` lays it with Godot's detail layer (multiply, UV2 triplanar in the mesh's own space, so it turns
with the drum).

**VRAM.** The maps as imported: four maps per piece at 4 096 px (albedo, ORM and emissive BC1 10.7 MB each, normal BC5 21.3 MB,
all with mipmaps) and the tile's two at 1 024 px (1.3 MB each): **109.3 MB**. The card's VRAM
(`/sys/class/drm/card1/device/mem_info_vram_used`) rose **228 to 245 MB** loading both pieces in three clean runs (one run with
something else on the card read 353 MB); the difference over the maps' bytes is the driver's, not measured further.

**Paint.** Base coats painted by pattern (`Marking.paint`, under the seams and the wear): the bands' blue-violet blocks
(checker of 12 x 3 blocks per band whose edges step out and back in 26 m notches, a 7 m grey frame in each); the docking
sphere's and forward body's checkerboard (32 and 36 round, 52 and 56 m along); the green zone's blue blocks between grey strips
(20 round, two blocks per 304 m section); the spine's upward faces darker; the vanes deep blue with a 24 m grey frame and small
dark recesses; red trim along the Cobra arms' edges and seven yellow-orange hatches (22 by 40 m) with hazard bands on each arm.
Colours are the table above through `capture_albedo` (at the civilians' 0.5). Lit windows (Q10): rings on the sphere, forward
body, bands and green zone, and rows on the spine's flanks over the sphere; a red lamp on the dome and four on the bow spine's
flanks.

**Look sheet:** `scripts/station_sheet.sh <dir>` (on this machine with the session locked, `SHEET_DISPLAY=x11`: Wayland stops
drawing a window nobody sees) shoots 50 m off a Cobra bay, 60 m off an arm's head, 50 and 150 m off the aperture, 200 m off a
band, 1 km, 10 km and 100 km. Per view: forward_plus, 14 to 18 draw calls near, 6 at 100 km, 223 to 489 fps steady at
6 144 x 3 456, GPU 1.8 to 4.2 ms. The sheet: `references/screenshots/M7-T04 station/M7-T04_station_look_sheet.png`.

## Metal and reflection (M7-T04 phase 1, the maintainer 2026-11-13: "metallic, not plastic")

**Materials** (`styles/earth_alliance_station.py`, `SCHEME`; metallic and base roughness as baked into the ORM map before the
variation below). Painted metal on the plating; bare metal, more metallic and smoother, on the trim, booms, truss, radiators,
reactor and dome. A painted metal's albedo is raised by `1 / (1 - 0.7 x metallic)` so its diffuse colour stays near the capture's;
a bare metal's albedo is its reflectance (`BARE_METAL`).

| Material | Where | Metallic | Roughness |
|---|---|---|---|
| drum_grey | drum, sphere, arm plating | 0.45 | 0.42 |
| drum_blue | blue-violet blocks (painted over drum_grey) | 0.45 | 0.46 |
| spine / spine_top | spine, bow, hub, fins / their upward faces | 0.50 | 0.48 / 0.56 |
| cargo | cargo modules | 0.40 | 0.50 |
| trim / hatch | Cobra arm stripes / hatches (painted over the arm's grey) | 0.45 | 0.46 / 0.50 |
| vane / vane_dark | vane blades / their small recesses | 0.55 | 0.34 / 0.55 |
| recess | teeth gaps, waist frame, truss core | 0.50 | 0.66 |
| vane_frame (bare, #9C9B99) | booms, vane mounts | 0.75 | 0.32 |
| reactor (bare, #7A6E62) | reactor, shaft, torus disc | 0.75 | 0.38 |
| machinery (bare, #8E8B87) | radiators, truss bars, waist pipes | 0.85 | 0.28 |
| dome (bare, #6E7078) | observation dome | 0.90 | 0.12 |
| window | unlit glass | 0.00 | 0.15 |

**Variation**, so a highlight breaks up instead of one sheen: each drawn plate's roughness is its paint's +-0.14 (`PLATE_SHEEN`,
`parts/station_layouts.py`); the `metal_finish` extra (M7-T16's helper in `core/textures.py`, shared with the raider) steps it
+-0.08 per 40 m panel and drifts it +-0.05 over 30 m; seam lines are 0.25 rougher; dirt (streaks, smudges and low grime) is up to
0.28 rougher and half as metallic; worn edges show metal (`bare_metal` 0.35: metallic 0.85, 0.25 smoother). As baked (median, 10th to 90th
percentile): forward band roughness 0.45 (0.33 to 0.63), metallic 0.44 (0.38 to 0.45); spine 0.52 (0.37 to 0.73), 0.50 (0.44 to
0.53); truss 0.28 (0.18 to 0.44), 0.83 (0.67 to 0.85); booms 0.37 (0.20 to 0.61), 0.75 (0.62 to 0.76). The near field's detail tile tilts each 1 to 4 m
plate up to +-0.06 rad (laid at 35 % on a plate's face), so a sunlit hull breaks into plates even at 50 m; Godot's detail layer
carries colour and normal only, so the roughness itself does not vary below the atlas's metre texel.

**What the station reflects** (the game's environment, unchanged): the key star (`KeyStar`, energy 1.5, Godot's default
specular 0.5) is the specular source; with `settings.hull_sheen` above 0 (0.25 by default) and the nebula shown, the
environment's reflected light is the sky (the nebula panorama, a 128 px radiance map) and every hull's paint, the station's too,
carries a clear coat of that strength at roughness 0.35; ambient light is a flat white at `settings.ambient_level` (0.1), which
lights diffuse only, so a bare metal face turned from the sun shows the dim nebula and goes dark, as metal in space does. There
are no reflection probes and the planet (scaled-space layer) is not reflected. Two global knobs were left alone for the
maintainer: the key star's specular (0.5) and the sky's radiance size (128).

## The Cobra arms and the docking aperture (M7-T04 fix round, the maintainer 2026-11-13)

Sources for the arms (gitignored, inspiration only, never traced): `references/cobra bay references/cobra bay doors lit show
capture.jpg` (show capture), `references/cobra bay references/cobra bay starfury launch render.jpg` (game render) and
`references/cobra bay references/cobra arm untextured model.jpg` (an untextured model of one arm).

What they show:
- **The launch doors** (all three): a row of seven closed doors in a framed strip along the arm's root section. In the show
  capture each door is a framed grating with a warm orange-red lit interior showing through, in a dark, red-trimmed recessed
  band; above the row, a hinged clamp or rail arm per door with a red cap block. In the game render the doors are rust-brown
  panels in a red-bordered frame with stepped, notched ends, and a Starfury drops out of the bay below. The model puts the strip
  near the top of the root section's flank; the show and the render show it on the face a fighter leaves from. T04 keeps it on
  the outward face (T01's read and Q3: the fighter drops out radially).
- **The head** (the model): a fork of two box prongs at the bow end (D75's L1 to L8 stand on them), a flat-topped box with a
  circular hatch held by four clamps (D75's I1 to I4 stand in it), ribbed flanks on the neck that tapers to the root section, and
  on the neck's top a framed panel with a red cross.

As built (`parts/station.py`, `parts/station_layouts.py`):
- Doors: seven per arm, 28 m along and 64 m across, sunk 4 m into a frame of two side rails and a bar between each pair (z 1 020
  to 1 290, centres every 38.6 m); each door two grated leaves (six slats each) painted rust-brown (`door`, #7A4A3A, metallic
  0.55, roughness 0.44), numbered 1 to 7 from the bow in pale stencil 14 m tall; the frame's top red (`trim`). Not built: the
  frame's stepped, notched ends (paint only would blur at the atlas's metre texel; T05 can add them as geometry).
- Bay light: a lit strip along all four edges of every door at the bottom of its well (`bay_light`, warm orange #FFA860,
  strength 3.5): the light leaking round a closed door.
- Clamps: beside each door a post on the rail, an arm reaching 6 m over the door's edge and a red cap block (`clamps`).
- Head: the two prongs are boxes (x 22 to 60 each side, r 255 to 292, z 612 to 705); the head's top is flat at r 320 from z 730
  to 870 with the circular hatch (r 24 to 30, a 1.5 m rim) and its four clamps at z 800; nine ribs on each flank of the neck
  (z 906 to 984); the red cross panel on the neck's top. T05 adds the bays behind the doors and their hardpoints.

**The docking aperture.** The maintainer read the old aperture shot as the reactor's end. Orientation checked and pinned
(`test_the_bow_is_at_minus_z_with_the_aperture_and_the_reactor_at_plus_z`): the bow and the aperture are at the game's -Z, the
reactor at +Z, and the shot looked at the bow. The trouble was the look: the door was a plain grey disc, much like the reactor's
cap. From the docking sphere close-up (`references/T40 seam references/babylon 5 docking sphere close up.jpg`) the door is now a
framed wheel: a front ring (r 88 to 126, panelled, sixteen red lamps) round a dark opening 34 m deep, crossed by four spokes
on a hub, with warm light at the back of the opening between the spokes (`aperture`, turns with the drum). The reactor's aft
face gained its ring of twelve bulging pipe sections, so the two ends no longer look alike.

**For T05 (the docking bay, `references/docking bay references/`).** The wheel is a first pass, one drum shape of its own
(`aperture` in `parts/station.py`: the front ring r 88 to 126, the 34 m well with its back wall at z 512, the hub, the four spokes,
the lit panels and the lamps). T05 replaces that shape whole with the cross housing across the bow disc, the stepped cross mouth in
its vented frame and the tunnel. Nothing else depends on it: the docking sphere's lathe starts at an open ring (z 478, r 126) with
no front cap, so taking the `aperture` shape out leaves a 126 m hole into the hull for the tunnel. The frame's toothed ring (r 133
to 157, z 488 to 548) and its pylon are separate and stay. The bow-end test checks only that the drum's foremost 40 m lie
inside r 126 and that its front is the aperture's hub, so T05 will need to adjust that one line.

**Build memory.** The station's bake peaks at 9.3 GB (9 305 776 kB maximum resident, measured with `/usr/bin/time -v` after the fix
round, 3.0 minutes). `tools/procgen/assets/__init__.py` lists it in `BUILD_ALONE`: `build --jobs N` (and so `scripts/gen_assets.sh`)
builds it after the pool has finished, in a worker of its own, so a 16 GB runner never holds it beside the other bakes
(`test_an_asset_that_builds_alone_waits_for_the_pool`).

**For T18 (exterior lighting).** Each piece has one emissive map (sRGB) with one strength per surface, the strongest glow on it
(the bay light 3.5, the red lamps 3.0, the windows 2.2); fainter glows are fractions of it in 8 bits, so a beacon far brighter
than these would dim the rest's precision: give beacons and ring lights their own emissive material, or a second surface. The
atlas texel is about a metre and a third, so the dashed ring lights on the band edges and sphere rims will want to be thin
emissive geometry (as the bay strips are) rather than paint. The atlases are about 64 % full; a strip light as geometry adds
its own small charts.

## Sections and near-only props (M7-T19)

**Why.** Godot picks one level of detail per mesh instance from its distance to that instance's bounds, and culls whole
instances, so a fighter 50 m off a bay drew both 8 km pieces at full detail and neither was ever culled. Each piece is now drawn
as sections, each its own mesh with its own origin, levels of detail and culling; T05's detail is built on them.

**Cuts** (`babylon5_station.py`, `DRUM_PLANES` and `FRAME_PLANES`, station z aft from the bow tip). On joints the hull already has
(band edges and rings, the sphere's widest ring, the gaps between cargo modules and between vanes); the green zone split at its blue
blocks' joints; no cut crosses a small part (a vane, a cargo module, a fin, a clamp).

| Piece | Sections | Cut planes (z) |
|---|---|---|
| drum (12) | aperture, sphere_fore, sphere_aft, waist, fwd_body, fwd_band, green_1, green_2, green_band, green_3, green_4, aft_band | 560, 750, 945, 1 340, 1 692, 2 348, 2 840, 3 340, 3 800, 4 290, 4 782 |
| frame (16) | bow, bow_ring, spine_sphere, ramp, radiators, cargo_1, cargo_2, cargo_3, vanes_1, vanes_2, vanes_3, hub, cone, truss, torus_shaft, reactor | 420, 700, 1 300, 1 725, 2 340, 3 068, 3 577, 4 087, 4 585, 5 030, 5 460, 5 735, 6 360, 7 110, 7 704 |

**How** (`core/sections.py`, called from `write_textured_mesh(..., sections=...)`). The cut runs after the atlas is packed, on the
piece's own triangles: a triangle across a plane is clipped (positions, normals and UVs interpolated along its edges from the
endpoints in a fixed order, so both sides get the same point), so the sections tile the piece exactly (area within 1e-5, tested),
each texel lands where it did, and the shading matches across a joint. Each section is `babylon5_station_<piece>_sec_<name>.glb`,
its origin on the axis half way along it, listed in the piece's `mesh.sections` (name, file, origin, slab `z0`/`z1`, box,
`triangles`, `skirt_triangles`). The whole-piece glb is still written (the STL compare and the tools read it); the game no longer
loads it. The drum's sections sit under the drum's node, so they turn as one body.

**Levels of detail and skirts.** The importer gives each section its own chain (most sections over 1 500 triangles have 1 to 5
levels), but it does not hold a section's border still: measured on the import, 0 to 70 % of a section's border vertices are gone
from its coarser levels (the waist's 370 border vertices fall to 194 at its third level). Two neighbours at different levels could
open a hairline crack at their joint, so each section carries a **skirt**: a 6 m wall in the cut plane hanging inward from its
border, with the border's normals and UVs, facing out of its section (the fore section's wall faces aft, the aft one's forward), so
whichever neighbour is finer shows hull through a crack. 9 480 skirt triangles in all (drum 7 328, frame 2 152), inside the hull
and rejected by the depth test unless a crack shows them.

**Ranges and shadows.** The hull's sections have no visibility range: together they are the hull, drawn at every distance the piece
is (past the far plane M6's far prop shrinks them; far beyond, the dot). No light in the game casts shadows (the key star and the
light slots have them off), so the sections and props keep `cast_shadow` off; there is no shadow distance to set. Sections out of
view are frustum culled.

**Near-only props** (`core/near_props.py`, `parts/station_props.py`). Small repeated parts drawn instanced (`MultiMeshInstance3D`)
under their section, with a small atlas of their own, shown within `near_m` 1 500 m and faded out (`VISIBILITY_RANGE_FADE_SELF`,
margin 400 m). The range is where the hull atlas's texel (1.39 m) reaches one pixel at 1 080 rows and a 62 degree view
(1.39 m x 1 080 / 1.08 rad = 1.39 km): beyond it the atlas is as sharp as the screen, so the props only add relief. On the
maintainer's 3 456-row display the atlas texel stays above a pixel to about 4.4 km, so there a prop's fade can be seen. The proof:
- **The doors' faces** (`door_row`, one per arm, 4 copies): a face 60.8 by 24.8 m laid 0.2 m over each of the seven doors, inside
  the bay light's strips, on its own atlas at 6.25 cm a texel (1 024 x 4 096, one cell per door): two grated leaves of six slats,
  rivets, worn edges, a hazard band down the seam, the bay's light faint between the slats and in the seam, and the number
  stencilled crisp. The hull keeps its painted door under it, so past the range the door still reads, only softer.
- **The clamps** (`clamp`, 28 copies): moved off the hull for good (1 008 triangles fewer); their red caps stay painted on the
  rails as the far stand-in (`clamp_caps`).
- Manifest: the drum's `props` (`near_m`, `margin_m`, the atlas's `surface`, `kinds`, `groups` with each copy's transform in its
  section's frame). Godot: `PieceSections` (pure) and `RenderPiece`; `MeshAssets.section_mesh`, `piece_materials`, `prop_mesh`.
- VRAM: the prop atlas's four maps about 14 MB as imported; the renderer's own count rose 1 721.7 → 1 739.4 MB.

**Collision by section** (`parts/station_collision.py`, the manifest's `collision`, D73). A first pass, built from the same numbers
as the shapes and cut at the same planes: round bodies as frusta between their profile's points (a 16-sided ring drawn round the
circle), slabs as hulls of runs of rows (runs within 6 to 10 m of straight), boxes for the rest, the aperture's ring as 8 sectors so
its hole stays open (tested). Each shape is named `<section>/<part>.<n>`; each piece lists `sections` (first, count). Drum 114
shapes, frame 128 (the budget, no merging needed). Against the drawn hull, probed every 10 m: the widest gap 12.8 m (the reactor's
ring of pipes) and 7.0 m on the drum; the farthest outer face 58 m off the hull (the vanes' roots and tip notches, filled) and 21 m
(the waist's teeth). Ribs, rail clamps, stringers and the doors' wells are left to the gap. T05 refines the bays and opens the
aperture's tunnel; T06 builds the bodies.

**Cost before and after** (RX 6950 XT, RADV, Forward+, X11, fullscreen 6 144 x 3 456, `scripts/station_sheet.sh` with
`SHEET_VIEWS=t19`, 150 frames settled, the last 60 timed; before: a scratch project with the T04 build, after: this build).

| View | Draw calls | Triangles drawn | GPU ms | Steady fps | Before: draw calls, triangles, GPU ms, fps |
|---|---|---|---|---|---|
| Cobra bay, 50 m | 42 | 89 554 | 3.92 | 230 | 18, 85 072, 3.96, 233 |
| Docking aperture, 50 m | 44 | 78 752 | 4.00 | 232 | 17, 68 432, 3.98, 235 |
| 1 km | 41 | 92 936 | 4.00 | 236 | 15, 84 344, 3.97, 236 |
| 10 km | 44 | 74 344 | 2.18 | 390 to 415 | 18, 68 432, 2.16, 412 |
| 1 000 km | 32 | 85 060 | 1.76 | 469 to 498 | 6, 80 716, 1.75, 500 |

Card VRAM (`mem_info_vram_used`) 4 817 / 4 709 MB after against 4 816 / 4 718 before (bay and far views), within the run-to-run
spread. At 1 000 km on this display the station is still about 15 px, so it is drawn shrunk as a mesh, not a dot: 28 sections at
their coarsest instead of two meshes.

**What it buys now: nothing measurable.** The hull is 40 k triangles; the GPU time is the 6K screen's shading, not geometry (10 km and
1 000 km differ by 0.4 ms with the whole station drawn in both). The section joints and the skirts add 7 to 10 k triangles and 24 to
27 draw calls, and the GPU time is the same within 0.05 ms. The sections are the seam T05's near-field detail needs: detail added to
a section is drawn at full detail only near it and culled with it.

**Occlusion: not built, noted for T13.** The station's whole geometry costs at most about 0.4 ms (above), so occluders inside the
drum and the spine could save a fraction of that; they would pay off for ships and props hidden behind the station in a fight, which
T13 measures with three squadrons and a raid (`rendering/occlusion_culling/use_occlusion_culling` is off in the project).

**Sheets (H)**, `references/screenshots/M7-T19 station sections/`: `before/` and `after/` (the cost views and the doors at 20, 50 and
300 m), `fly/` (a pass under the station about 200 m off the hull from the bow to the reactor), and the contact sheet
`M7-T19_station_sections_sheet.png`.

**For T05.** Put new detail in the section it lies in (its slab in the manifest) or as props under that section
(`station_props.groups`-style: a kind, a section, transforms in the section's frame); a prop's fine paint goes on the prop atlas, not
the hull's. The aperture's door is the `aperture` section (z up to 560): replacing the `aperture` shape changes only that section.
Collision: `station_collision.drum_pieces` closes the aperture's well for now (`aperture` frustum); the tunnel needs it opened.
**For T18.** Lights on the drum go under its sections (they turn with it); a light's emissive props can use the prop atlas's glow.

## Interior (M7-T09, refitted in M7-T20 to T05's doors and T21's arm)

The front end's backdrop (D77, Q7): the inside of Alpha wing's Cobra-bay arm (the top one), `tools/procgen/assets/b5_interior.py`
(shapes in `parts/cobra_bay.py`, paint in `styles/cobra_bay.py`), shown by `src/frontend/hangar_backdrop.gd` with the camera in
`hangar_camera.gd`. Sheet: `references/screenshots/M7-T09 interior/M7-T09_interior_look_sheet.png` (`scripts/interior_sheet.sh <out dir>`).
T09's look was approved 2026-11-13 (a darker grey deck, Alpha's livery, overhead clamps, no cradle); T20 keeps it.

**Read from the station, not hard-coded (T20).** Everything comes from the station's `hardpoints.cobra_arm`
(`station_hardpoints.cobra_arm_layout`): the six doors (20 by 14 m, the leaves from `station_props.LEAF`) and their 23 m pitch, the
upper hall over them (x ±20, r 219 to the doors' plane at 236.5) and the lower hall above it (x ±40, r 206.5 to 219), where a fighter
hangs (r 227.5) and is released (r 244.5), and where the second row is staged (x -28, r 214). Hall frame: +y up toward the drum's
axis, z along the arm with the head (bow) at -z, origin on the floor in the middle of the upper hall; `to_arm` turns it half a turn
about z onto the arm (x flips: the second row, at arm x -28, is at hall x +28). Without a `lower_hall` the hangar is one level.
T04's seven-door names (`COBRA_DOORS`, `DOOR_HALF`, `DOOR_ROW`, `door_centres`) are gone from `parts/station.py`.

**What drove each choice** (references in `references/`, inspiration only, never traced):

| Choice | Reference |
|---|---|
| Dark, grimy, low-key hall; red and white lamps among the gantries; a dark grey floor, the red kept on the lamps and machinery | 1, the show's Cobra-bay capture (most weight); the maintainer |
| Every fighter held from above by its own clamp: the racked six by clamp arms off the upper hall's walls gripping their upper pods from outboard (the rack's middle open, T21); the second row each on a crane trolley under a bridge across the lower hall, which carries it across and down onto its rack | 1 (overhead machinery and clamp arms holding the fighters); 2 (red and white clamp cranes); T05/T21's hardpoints (the second row's path) |
| Hazard striping on the door coamings, the bays' sills, the ledges' edges; a hazard band down each door's seam | 1; 2; T05's door faces |
| Orange canisters with yellow and dark bands on the ledges | 1 |
| A red portal with cut corners round both halls at each launch position; big red bay numbers 1 to 6 on the lower hall's walls | 2 (a suggestion) |
| Yellow railings on the catwalks and along the ledges, ladders, yellow lattice on the columns under the ledges | 2 (a suggestion) |
| "01" to "06" plates on the cranes' bridges | 3, the fan diorama's "01" (a suggestion); its cradle is left out, the show holds them from above |
| Machinery walls with pink-lit panels; the bay's warm orange glow round the closed leaves | `references/docking bay references/`, `cobra bay doors lit show capture.jpg` |
| Pressure doors with toothed leaves at both ends, a lit launch-control booth over each | `docking bay references/6 inner airlock toothed doors.png` |

**The fighters** (`fighters` in the manifest, for T08's launch steps and M8's squadron launch): twelve real `starfury_aurora`
instances in Alpha wing's livery, numbered 1 to 12. Wave 1: one over each door (hall x 0, y 9). Wave 2: the second row in the lower
hall (x 28, y 22.5), launching 10 s later. Each has an `id` (`alpha_<door>_<wave>`), `wing`, `door` (1 at the arm's head), `wave`,
`bay` (`cobra_bay_alpha_<door>`), `number`, where it hangs (nose to -z, back to the axis) and its `release` 8 m below its door;
wave 2 also its `staging_path` (across at its height, then down onto the rack). All points also in the arm's frame (`*_arm`);
the tests check them against T05's `cobra_bay_alpha_*` hardpoints. `launch` gives the wing, doors, waves, gap and the rows' places.

**Pieces and budgets.** `bay` (one launch position, about 3 600 triangles, drawn six times), `ends` (both end walls and the hall's
ends between them and the row, about 1 200), `signs` (288): about 5 000 triangles in the asset, about 23 000 drawn. Faces nobody
inside can see are dropped before packing. Atlases: bay 2 048 px, ends 2 048 px, signs 1 024 px, plus the station's detail tile
(8 m, 1 024 px). The bake takes about 50 s and 2.5 GB.

**Paint: metal, not plastic** (D72; `metal_finish` as the station and the raider), unchanged since T09's approval:

| Role | Capture sRGB | Metallic | Roughness | Where |
|---|---|---|---|---|
| deck | #48484A | 0.70 | 0.48 | floors, ledges, catwalks, the leaves' inner faces |
| wall | #6E6A66 | 0.55 | 0.42 | walls, cabinets, the number panels |
| frame | #9A9998 | 0.50 | 0.40 | columns, beams, the bridges, the booths, clamp links |
| recess | #2E2D2B | 0.50 | 0.66 | wells, the ceiling, vents |
| trim | #915555 | 0.45 | 0.46 | the portals, trolleys, clamp arms and heads, a red pipe run |
| hatch | #CAA75F | 0.45 | 0.50 | coamings, sills, ledge edges, railings, ladders, lattice |
| door | #7A4A3A | 0.55 | 0.44 | the leaves' slats, the end doors |
| canister | #C2662E | 0.45 | 0.48 | the canisters |
| machinery (bare steel #8E8B87) | #5A5856 | 0.90 | 0.30 | pipes, rails, hinges, rams, lamp stalks |
| rubber | #1E1E1E | 0.00 | 0.85 | the clamps' pads |

Glows: bay light (#FFA860, 3.0), red lamp (#FF3A2A, 3.0), work light (#FFE2B8, 6.0), pink panel (#FF8C9A, 1.4), the booths' windows
(warm, 2.0).

**Lights** (8-light budget, `LightPicker`): six white work lamps (#FFE2B8, energy 9, range 30 m), one per bay, each hung from the
ceiling between the racked fighter and the second row (hall x 9.8, y 20.5), 9.5 m along the hall from its door so the second row's
crossing misses it, so it lights both rows; six emitters for the rig's seven omni slots, none ever swaps. The key light is a faint,
slightly red fill from above (colour 1.0, 0.66, 0.6, energy 0.1). Everything else is emissive.

**The camera**: a dolly in the upper hall beside the racks on the far side from the second row (x -12.65, y 7.5), looking toward
the arm's head, from the root end (z 69) to 14 m short of rack 1 (z -43.5) and back in 240 s (under 1.5 m/s), with a 0.6 m bob and a
3 degree sway; the racks and the second row sit right of the menu. The look sheets' fixed views are in the manifest
(`camera.views`): `wide` (from high at the root end), `close` (rack 3), `rack` (the six racks from the catwalks' height), `second`
(the second row, from beside it); `backdrop <view>` shows them.

**Cost on the RX 6950 XT** (1920x1080, Forward+, sheet run): 19 to 21 draw calls with the menu, 6 to 8 without; 85 000 to 263 000
triangles drawn (the twelve Starfuries are most of it); steady 640 to 1 460 fps uncapped; the card's VRAM +234 MB with the front
end and its hangar loaded (Godot's own count 372 MB).

## Near field and hardpoints (M7-T05)

Phase A (the main docking bay, the grid's plinths and the hardpoints) approved by the maintainer on 2026-11-13; phase B added the
cargo bay (zero-gravity), the six-door launch strips with their halls, the command section's detail and the toned-down red.
Generator version 3.

### The main docking bay (in the drum)

`parts/station_detail.py` (`main_docking_bay`, the drum's `aperture` shape: it turns with the drum; the outer toothed ring is frame).
References in `references/docking bay references/`, inspiration only. Station frame, z aft from the bow tip:
- A plate across the sphere's front opening at z 478 (r 126) with 24 sawtooth teeth round its rim (r 112 to 124, 5 m proud; none
  under the housing or the bar).
- The cross housing: arms x 70 to 128, y ±30, front z 460, ribbed; the bar up (x ±16 to y 124, z 466) and down (x ±28 to y -122,
  z 462) carrying the lower hatch.
- The central block (x ±70, y ±56, front z 450, olive grey `bay_frame` #8A8770): slatted grilles above, below and beside the mouth,
  four marked panels at its corners.
- The mouth: a stepped cross (half sizes 58 x 28, 40 x 36, 26 x 44), three frames each stepping in 3 m and back 6 m (red lamps on
  their steps, pink panels at the outer sides); the tunnel from z 468 to the inner airlock at z 640, ringed by six frames (z 490 to
  610, 2 m in, 3 m deep) with machinery between them.
- The inner airlock at z 640: two doors closed on a trapezoid sawtooth (10 m teeth every 22 m, a 2.4 m gap), ribbed, a dark wall
  at z 646 through the seam.
- **Toned down (phase B):** every surface dark machinery (`bay_wall`, no glow); red only on a 0.8 m strip round each frame's inner
  edge, the frames' inner faces, the lamps and the airlock's seam, brightest at the mouth (`bay_red_0` 1.6) and dimmer inward
  (`bay_red_5` 0.65); the pink panels 0.8; the doors' faces 0.08. T18 adds the real red lights and keeps the sun out of the tunnel
  (no light casts shadows, so a sun ahead lights the tunnel's depths; the sheet's inside views light from astern).
- Clear passage: **94 x 34 m** about the axis (the cross's middle 30 m wide is 66 m tall): the small civilians; the Saturns stay out.

### The cargo bay (zero-gravity, on the spine between the forks)

Q8 as refined: Saturn freighters never enter; their pods fly in by themselves (no loader ships). Read off the STL (a stepped
square recess at the forks' root, facing down the slot) and the Mallacore render (a lit machinery compartment there); the look from
the maintainer's show capture (`references/zero g cargo bay references/`; its arms, toothed rings and canisters belong to a loader
ship and are not built). An open box cut into the spine's front where the slot ends, open ahead (down the slot) and above:
- Inside x ±30, floor y 322, from z 420 to 490 (70 m deep: a whole pod, 43 m, with room); the spine starts again at its back.
- A thick rim (`bay_frame`, 8 m wide, 4 m over the spine's top) round the open sides, with greebles along its beams; stepped
  machinery on the floor (dark blocks in tiers to 4 m, a red strip on each block's front edge, pink and red lamps), ribs up the walls
  with red edges, red lamps on the back wall.
- Sized to the Saturn pods (31.1 x 17.2 x 43.0 m, `parts/saturn.py`): 60 m across the inside, a pod square-on clears 14 m a side;
  the room over the machinery is 56 x 42 m to the spine's top and open above. The slot (x ±45 to ±50) takes it all.

### The Cobra bays: six launch doors an arm

The maintainer's untextured arm model: six doors in a framed strip on the root section, each one Starfury. `parts/station.py`
(`LAUNCH_*`, `launch_deck`):
- **Doors:** 20 m across the arm by 14 m along it (a Starfury, 15.4 m across its claws and 9.8 m long, its span across, clears
  2.3 m and 2.1 m), sunk 4 m into the deck at r 239, at a 19 m pitch from z 1 016 to 1 130 (just aft of the ribbed neck), their
  middles at x 18 on the top arm (the strip toward its starboard edge, as the model has it). A darker framed strip round the
  row, a red border round each door, a lit strip along each door's edges, a clamp beside each.
- **The launch hall** under the strip: x -16 to 34, z 1 010 to 1 136, from the doors' plane (r 239) in to its ceiling (r 209),
  dark inside. Over each door a gantry (near-only prop): a beam across the hall, the rack's drop arm and red clamp head 11 to 13 m
  in from the doors, work lamps, and a staging clamp over the **second row**: twelve Starfuries an arm, six on the racks and six
  staged 22 m to port of them under the deck (no open door shows them), each crossing onto its rack once the first wave has dropped.
- **The doors are props:** two leaves a door (`door_leaf_<n>_<r|l>`, one kind each so each carries its half of the number), each
  its own instance so a launch swings it about its hinge on the outer edge; drawn as far as the hull (30 km), since the hull has no
  painted door under them now. Their faces on the prop atlas at 3.1 cm a texel (slats, the bay's light between them, rivets, the
  hazard band, the number). The sheet's `open_door` view swings door 3's leaves open (`scripts/station_sheet_node.gd`).
- **M7-T09's hangar** read T04's seven 64 x 28 m doors until **T20** refitted it to these doors from `hardpoints.cobra_arm`
  and dropped the old names (`COBRA_DOORS`, `DOOR_HALF`, `DOOR_ROW`, `door_centres`).
- **Wings** (the maintainer, 2026-11-13), seen from the bow: Alpha top (0 degrees), Beta starboard (90), Delta bottom (180), Zeta
  port (270); each arm is one wing and launches in two waves of six.

### The command section (Q2: from 50 m)

- **Windows:** crisp panels (`window_panel`, a frame prop on `spine_sphere`, the frame's own small atlas at 3.1 cm a texel) over the
  spine's flanks where the hull paints its windows, seven runs a side between z 700 and 1 300: panes 5.6 x 3 m with frames and
  mullions, 62 % lit warm. Near only; the hull's painted rows beyond.
- **Compartments:** three open machinery compartments on the bow spine's top (z 610, 780, 905): a rim round a dark floor, tanks,
  a coil housing, a red lamp.
- **Serrated forks:** sawtooth teeth (5 m) every 14 m along each fork's outer lower edge.

### The defence grid's plinths

D75's 23 positions exactly. Each gets a 16-sided plinth along its up (light turret r 5 m, heavy cannon 9, interceptor 6.5), its face
0.4 m over the pivot, reaching 6 m below. Where the T04 hull buried a mount it was flattened under it (kept, the maintainer): the
arm's head lowered at the fork (L1 to L8 on the prongs), the bow spine flat at y 375 from z 500 to 530 (H1, H2), a spine row at z
2 650 at y 537 (L10, I7), the spine over the hub at y 472 (L12, I9).

### Hardpoints

`parts/station_hardpoints.py`, the manifest's `hardpoints`; Godot reads them with `StationHardpoints` (`src/world/`). Each entry in
its `body`'s frame: `drum` (the drum node, on its axis at the pivot, turning with it) or `frame` (the asset's frame); no axis flips.

| Section | Count | Fields |
|---|---|---|
| `cobra_bays` | 24: `cobra_bay_alpha_1` to `_6` (top arm, door 1 at the bow), then `beta` (starboard), `delta` (bottom), `zeta` (port) | `wing`, `arm`, `door_number`, `door` (r 239), `door_half_m` [10, 7], `normal` (radially out), `across`, `leaves` (hinge `point` and `axis`), `rail_start` (where the fighter hangs, r 230), `rail_end` (the door), `release` (r 247), `release_direction`, `surface_velocity` (w x r, 36.6 m/s), `forward` (bow), `up` (toward the axis), `staging` (the second row's fighter), `staging_path` (up 3 m, across, down onto the rack) |
| `cobra_arm` | 1 | the doors' layout on an arm standing on top (for T20): `door_floor_r`, `door_depth_m`, `door_half_m`, `pitch_m` 19, `row_z`, `strip_x`, `centres`, `hall`, `hang_r`, `release_r`, `staging_x`, `arms` (each `name`, `wing`, `angle_deg`, `bow_view_deg`, `bays`) |
| `main_docking_bay` | 1 (drum) | `main_docking_bay_approach` (1 500 and 300 m ahead), `_path` (to the mouth and the airlock), `_mouth` (z 450), `_airlock` (z 640), `_clear_half_m` [47, 17]; `spin_axis`, `spin_rad_s` 0.148, `pivot` (a ship flying in matches the drum's roll; the same as `pieces.drum`) |
| `cargo_bay` | 1 (frame) | `cargo_bay_approach` (to the hold), `_hold` (z -700, y 346: on the slot's line, 346 m off the main bay's axis), `_hold_forward`, `_release` (z -640), `_path` (down the slot into the bay), `_entry` (45 m in), `_clear_min`, `_clear_max` |
| `grid_mounts` | 23 (L1 to L12, H1, H2, I1 to I9) | `kind`, `position` (pivot), `up` (D75's, normalised) |
| `launch_clearance` | 1 | `blocked_sectors_deg` [[56.5, 124]], `clear_distance_m` 240 (M7-T22), `margin_deg` 10, `ship_clearance_m` 2, `angle` (how an arm's angle and the drum's turn give a door's angle) |
| `lights` | 57: 14 `beacon` (`blink`), 8 `running`, 7 `ring` (`radius`, `axis`, `dashes`), 24 `bay`, 2 `main_docking_bay`, 2 `cargo_bay` | `position`, `colour` |
| `tour_points` | 8: bow, main_docking_bay, cargo_bay, cobra_arm (drum), grid_tower, drum, vanes, reactor | `position`, `look_at`, `direction` |
| `damage_sections` | 11 | `sections` (T19's render sections, each once), `aabb_min`, `aabb_max` |

### Launch clearance (M7-T08's rule)

A Starfury does not launch while its arm points at the stationary frame. `launch_clearance` gives the arm angles (its outward
normal about the drum's axis, from +x toward +y in the frame's coordinates: the arm's `cobra_arm.arms[].angle_deg` plus the drum's
turn) at which a Starfury's box (15.4 x 9.8 m, its span across the arm) dropping radially out of any of the six doors would pass
within 2 m of the frame's collision shapes within 250 m: **68.5 to 116.5 degrees**, widened by 10 degrees each side to
**58.5 to 126.5** (one sector: the dorsal spine and its hanging box over the drum; nothing else of the frame stands over the strip's
z). The top arm at rest (90 degrees) is blocked; with the drum turning at 0.148 rad/s (8.5 degrees a second) an arm spends 8 s of
its 42 s turn in the sector.
- **The clear distance, 250 m:** the frame's farthest part over the door strip (the spine's top and the observation dome, r 462 to
  465) is 226 m out from the doors' plane, so a drop path clear for 250 m is clear for good; nothing of the frame reaches farther
  out at those z.
- **The margin, 10 degrees:** 1.2 s of the drum's turn, the time from the rack through the release point while the arm keeps turning.

### Collision

Budget raised to **192 shapes a piece** (T03's default 128): the bays' openings take pieces round each one that a merge would close
(`station_collision.KEEP` never merges them). Drum 179, frame 134, no merge.
- Main docking bay: the sphere from the plate to the airlock as four pieces about the clear passage, the block round the mouth the
  same way, the housing and the bar as boxes. Tested: nothing within 0.3 m of the passage from 60 m ahead to the airlock.
- Cobra arms: the hatch round the hall (floor, the solid round it, the deck in pieces between the doors, the taper). Tested: a
  Starfury's box drops from its rack out through its door, and the second row crosses onto the racks, without a contact.
- Cargo bay: the spine's front round the open box (under the floor and machinery, beside it, the rim's posts and sill). Tested: a
  pod square-on flies from the release point down the slot to the entry point without a contact, in collision and on the hull.

### Cost and sheets

Measured on the RX 6950 XT (Forward+, X11, fullscreen 6 144 x 3 456, 150 frames settled; see the Done notes for each view). Sheets
(H), `references/screenshots/M7-T05 near field/`: `M7-T05_main_docking_bay_sheet.png` (beside the six references),
`M7-T05_cargo_bay_sheet.png` (beside the show capture), `M7-T05_detail_strip_50m.png` (the new door strip beside the arm model, a
door swung open onto its hall, the windows, a compartment, both bays at 50 m), `M7-T05_hardpoint_markers_sheet.png` (every hardpoint
as a ball by kind). View sets `t05`, `cargo`, `strip` and `markers` in `scripts/station_sheet_node.gd`.

## The Cobra arm's section and the roofed cargo bay (M7-T21)

The maintainer, after approving T05: the arm read as one rectangular surface, the doors small on it, the cargo bay roofless. Read
again off the STL, section by section (`references/screenshots/M7-T21 arm and cargo bay/stl_arm_sections.png`,
`stl_cargo_bay_sections.png`):
- **The root** (z 1 000 to 1 300, `station.ROOT_HALF`): a flat top at r 240.5 between two **creases** at x ±24.1, chamfers down to
  (±45.8, 216), a short bevel to vertical sides at x ±47.2, a **notch** in each side (in to x ±41.3 between r 202.8 and 206.5), and
  an underside rising from the corners (r 196.2) to a flat middle (r 202.8): a shallow V. Built as four convex pieces (body, band,
  wings).
- **The head and neck** (`ARM_NECK`): one chamfered loft from z 735 to the root, each row with its own chamfer across and down: its
  flat top peaks at r 314 (z 800 to 840, flat ±30) and slopes to x ±80 at r 289; the circular hatch's raised cap (r 10) stands to
  r 323.5, where D75's I1 to I4 stand. The fork's prongs are **posts** (5 m, the STL's are 1 m) under D75's L1 to L8, which keep
  their positions.
- **The doors** on the top face between the creases (the STL's door shafts): six, 20 x 14 m, centred (x 0), at the STL's 23 m pitch
  from z 1 044 to 1 182, sunk 4 m (the doors' plane r 236.5). **The halls**: the upper hall under the doors (x ±20, r 219 to the
  doors' plane) over the lower hall (x ±40, r 206.5 to 219, the notch line). The second row waits in the lower hall 28 m to port
  (r 214), crosses under its rack and rises onto it; the racked fighter hangs at r 227.5, released at r 244.5.
- **Launch clearance** recomputed: blocked 67 to 113.5 degrees, **57 to 123.5** with the margin; clear distance 260 m (the spine's
  top corners over the strip, r 489, are 252 m out).
- **The cargo bay** is the STL's: a **closed compartment inside the spine, roofed**, x ±94 inside, r 323 to 357, z 442 to 490 (the
  STL's ends at 482; 8 m deeper so a 43 m pod lies in it lengthwise), reached only through the STL's **octagonal throat**: x ±34.1,
  r 323.3 to 354.7, corners cut 7.6 m, z 420 to 442, in a 2.9 m frame out to x ±37. A pod (31.1 x 17.2 m) passes square-on with
  18.5 m each side and 7 m over and under. A keel under it (x ±10, down to r 290, to the bow's pylon) and a ridge along its roof
  (x ±10, to r 386), as the STL's; the spine there 2 m thinner (top 363, underside 313 at z 420). `cargo_bay_entry` is the
  compartment's middle (z 466, r 339).
- **Manifest** (field names kept for T06 and T20): `cobra_arm.hall` is the upper hall (`ceiling_r` 219); added `lower_hall`,
  `section` (the root's outline), `creases_x`, `staging_r`; `staging_path` crosses under the rack (`STAGING_LIFT_M` kept at 0 for
  M7-T20's import). Drum collision 191 shapes (budget 192), frame 138.

### The per-part section check (CLAUDE.md "STL fidelity")

`tools/refview/sections.py` cuts the STL and the build at a plane, fills each section by the nonzero winding rule (overlapping
parts as their union, a tunnel left open) and compares them pixel by pixel (0.5 m) in a window round the part: IoU >= 0.90. A plane
marked `outline` compares the sections filled row by row from their outer edges (the build's rooms, the halls and the cargo bay,
are open where the STL is solid). The station's planes are data in `parts/station_fidelity.py`; each Cobra arm is cut in its own
frame (turned onto the top). Tested in `tools/procgen/tests/test_station_fidelity.py`.

| Part | Planes | Before (T05) | After (T21) |
|---|---|---|---|
| Cobra arms (each of four) | head 760, 800 (outline); neck 900, 960; root 1 030; root 1 060, 1 101.5 (outline, through the halls); root 1 240 | 0.65, 0.65, 0.41, 0.77, 0.38, 0.63, 0.69, 0.73 | **0.96, 0.95, 0.92, 0.96, 0.97, 0.93, 0.96, 0.98** |
| Cargo bay | z 430, z 465, top (y 340) (outline) | 0.86, 0.88, 1.00 | **0.96, 0.96, 1.00** |
| Cargo bay | side (x 0) | 0.26 | 0.46, **exempt**: the throat and compartment are open for the pods (the maintainer: "open only where pods enter"); the STL shuts the throat with a door plate |
| Main docking bay | z 455, 470, 520, side | 0.00, 0.01, 0.68, 0.79 | the same, **exempt**: built from the maintainer's show references (T05, approved), not the STL's door |
| Dorsal spine | z 1 500, 2 000, 2 650, 4 500, 5 650 | 0.63, 0.72, 0.60, 0.48, 0.52 | rebuilt in M7-T22 (below) |
| Command section | bow 200, 400; z 600, 1 000, 1 150, 1 250 | 0.66, 0.71, 0.38, 0.53, 0.51, 0.66 | rebuilt in M7-T22 (below) |

**Sheet (H):** `references/screenshots/M7-T21 arm and cargo bay/M7-T21_arm_and_cargo_bay_sheet.png` (the section overlays before
and after with their IoU, the door strip at 50 m beside the model, a door open, the cargo bay; `SHEET_VIEWS=t21`).

## The dorsal spine, command section and bow to the STL (M7-T22)

T04 built the spine to the silhouettes; T21's section check scored it 0.38 to 0.72. Rebuilt in `parts/station_spine.py`: every part
a solid lofted through sections read off the STL (z cuts every 50 m and finer where the shape changes; the STL's long x and y cuts
leak, so only z cuts are used), the numbers as data. A member's sections may be non-convex (ledges, radiator wings); collision takes
the hull of each run of sections. The spine aft of the cargo modules mirrors the spine before them about z 3 577, as the STL does.
- **The bow:** each prong a six-sided section (flat top, a shoulder bending out to the side, vertical outer side, flat underside at
  y 315), lofted z 0 to 430 (outer edge x 55 at the tip to 162.5), a raised lip along its inner top edge (x 42.5 to 52), a flange
  under its outer half and a strip under its inner edge. The STL's port and starboard prongs differ slightly (the shoulder, the
  flange); the build takes their mean.
- **The command section:** at z 597 the spine splits into two side beams (x 81 to 166, a sloped top) and a centre box (x +-59.5 to
  +-73.5, y 338 to 375) with a slot through it (x +-9.5); from z 688 a body widening from a ledged box (x +-95, y 342 to 404) to a
  six-sided block (x +-164, y 313 to 458) at z 997; then the **pointed beam** (flat top x +-88.5 at y 458, out to +-166 at y 403)
  with twelve ribs under it (every 23.2 m), over a **keel** (x +-88 from y 361, down to 329, 352 or 310 along it) on a strut (x +-14,
  to y 310), the 42 m between beam and keel open; the observation dome (an ellipsoid x +-41, 27 high, z 1 069 to 1 165, a disc and
  lamp on top) in a recess in the beam's top (z 1 058 to 1 176), a groove (x +-37, floor 435) along the top from z 1 245; the beam's
  tail closes down onto the deck by z 1 405.
- **The spine:** the deck over the waist (chamfered, x +-97 to +-140, top 458 to 472), the ramp (x +-33, top 487 at z 1 405 to 558 at
  1 738; the STL's is +-37, kept clear of I6's turret) with its stepped tip; over the bands the base section (top 472 x +-84.5,
  chamfer to x +-92.5, underside 426: 9 m over the bands); the radiators z 1 814 to 2 091 and 5 063 to 5 340 (a core x +-92.5 to
  y 542 with a diamond wing each side, twelve fins to y 553 every 23.2 m); a rib (x +-12) and two pipes (r 23.5) on the top before
  the green zone. Over the green zone: a lower slab (top 417) with **sloped side plates** down to y 357 (x +-56 to +-151), a tower
  x +-60 rising to the **turret block** (cap x +-46.5 at y 537 over a body x +-103 to +-115.5, z 2 560 to 2 686; L10 and I7 on the
  cap, and aft L11 and I8), fins x +-92.5 between. The **cargo modules** (the STL's six at the old z) are six-sided, x +-168.5,
  y 357 to 560, with an end frame (to x +-176, y 565) each end, standing on the lower slab. The hub end: rails, the body sloping
  into the hub (x +-106.5 at y 472 to the hub's surface, z 5 562 to 5 788; L12 and I9 between the rails), a narrow tail (x +-33.5)
  down the cone to z 6 188.
- **D75's mounts** all where they were (L9 to L12, H1, H2, I5 to I9 sit on the STL's surfaces as they stand). The drum turns clear
  (tested; the lower slab starts aft of the forward band's rim, z 2 342, and ends before the aft band's, z 4 784).
- **Follows the spine:** the window panels lie on the beam's sloped flanks (two rows of four a side, z 1 012 to 1 268), the painted
  windows there and along the body's sides (z 700 to 880); the compartments stand on the new tops (the first moved to z 635, on the
  centre box); the flank lamps on the beam's outer edges; the bow beacons on the prongs' tips (x +-51, y 322); collision from the
  same sections.
- **Launch clearance** recomputed: **56.5 to 124 degrees** with the margin; clear distance **240 m** (the farthest part of the frame
  over the door strip is now the dome's lamp, r 471, 234 m out; was the old spine's corners, r 489).
- **Tour point:** `cobra_arm` (it rides the drum) moved from (150, 340, 1 010) to (160, 215, 1 010): at r 372 it swept through the
  gap between the beam and the keel (2.5 m off the keel's corner); at r 268 it turns inside everything on the frame there (42 m clear
  through a whole turn, tested).
- **Paint test:** the cargo modules' red share is measured at the full texel (1 024 px, was 512): the six-sided modules and their end
  frames have more worn edges, which fill a coarser map.
- **The check:** the z 1 500 plane's window starts at y 400 (from 340 it caught the drum's pods under the deck); the z 4 500 plane
  moved to **z 4 520** with its window narrowed to x +-145: the STL is open round z 4 330 to 4 500 (its cut there fills whole rows
  below y 368 to the window's edges and between the side plates), clean from z 4 504; z 4 520 is the same section (the turret block
  under L11).

| Plane | Before (T21) | After (T22) |
|---|---|---|
| spine z 1 500 / 2 000 / 2 650 / 4 520 / 5 650 | 0.67, 0.72, 0.60, 0.59, 0.52 | **0.955, 0.986, 0.996, 0.993, 0.976** |
| bow z 200 / 400 | 0.66, 0.71 | **0.905, 0.952** |
| command z 600 / 1 000 / 1 150 / 1 250 | 0.38, 0.53, 0.51, 0.66 | **0.975, 0.993, 0.980, 0.991** |

(Before at the new windows; at T21's own, z 1 500 0.63 and z 4 500 0.48.) No exemptions. The build at z 4 500 itself (window x +-145)
scores 0.81 against the STL's open cut; 0.995 at z 4 504.

**Sheet (H):** `references/screenshots/M7-T22 spine and command section/`: `M7-T22_sections_dorsal_spine.png` and
`M7-T22_sections_command_section.png` (each plane's overlay before and after with its IoU), `M7-T22_z4500_vs_z4520.png` (why the
plane moved), `M7-T22_views_sheet.png` (GPU: the command section, bow and spine at 50 m to 1 km; `SHEET_VIEWS=t22`).

## Maintenance bots as built (M7-T11)

`tools/procgen/assets/maintenance_bot.py` (style `styles/maintenance_bot.py`, generator 1; 2 348 triangles, 4.6 x 3.1 x 3.5 m,
one 1 024 px atlas at 1.2 cm a texel, 5 s to build). Two flattened egg shells with two ochre bands each and a painted 9 on the back,
a grey truss beam with cross braces, three amber lamps and a small dish, a sensor head under the front with a green lens, two
three-segment arms with claws (one reaching fore, one aft) and six little thrusters with faintly glowing throats. A metal finish
(`extra["metal_finish"]`: shells metal 0.5 at roughness 0.42, truss 0.8 at 0.34, roughness stepping plate to plate, dirt rougher and
duller). No collision: the bot is ambient. Colours are the sheet's lit values (shell #6662B5, band #C0A866, truss #83807D, joints
#33312F). Reference, as for the station: inspiration only, nothing traced.

The loops are data, `data/station/bot_points.json` (read by `BotData`): per loop its body (`frame`, or `drum` in the drum's own frame,
so the bot turns with it), the control points of a closed Catmull-Rom curve, the speed (3 to 4 m/s), the number of bots, an up vector
(away from the hull) and two hatches (a control point `at` and an `inside` point sunk 5.5 m below the hull surface). Eight loops, one
bot each: the four Cobra arms (an oval over each arm's shoulder, 254 m from the axis, 20 m off the door lane), the spine over the cargo
modules, the bow prong, the drum's green zone and the reactor's top. They were fitted against the drawn triangles (least distance
over a full turn of the drum: arms 13.2 m, spine 24.8, bow 21.9, band 13.8, reactor 17.7; the file states 8 m, the bot's own radius
is 2.9 m) and `tests/unit/test_bot_loops_clear_of_hull.gd` holds it on every build of the station. Move a loop only with that test.

The cargo ferry (`bots cargo`, M7-T11) reuses the bot on the frame: `CargoFerryPlan` reads the station's `cargo_bay` hardpoints (hold, entry, clear box) and the
Saturn 3's three cargo-pod boxes, and gives each bot an out route and a return route from just inside the bay's back wall (z -3 505, where the bot is hidden)
through the throat and the slot to a point 8 m behind a pod's aft face; the Saturn backs in at the hold point, nose away (-Z in the station's frame), so the pods
(at 11.8 m aft of its origin) are the end nearest the bay.
