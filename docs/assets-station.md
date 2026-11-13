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
- `compare.py` reads one mesh (the manifest's `mesh.file`). The station has two pieces, so T04 has to make the compare read
  both (the frame, and the drum moved to its `pivot`), for example by loading every entry of the manifest's `pieces`.
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
