# Capital ships: what the generators build (M12)

One section per capital hull, as built, the way `docs/assets-civilian.md` reads for the civilians. The shapes, sizes and
colours come from `docs/design-references.md`, measured off the maintainer's reference models with `tools/refview`.
Positions are in the authored frame of the design references: x to starboard, y up, z aft from the bow, metres, Godot's
axes. As with every asset, the generator then centres its mesh and hardpoints on the centroid of the visible surface and
records the shift as `manifest.centroid_offset`.

M10-T05 (the old M12-T05) built the shared capital framework (D12.1: sections, texel tiers, weapon mounts), described
under "Capital framework" below; every capital hull from M10-T21 on is built on it. The strike carrier was built ahead of
it (the early delivery, Q25) on the civilians' pipeline, `core/civilian.py`, and stays there until a task moves it.

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

## Capital framework (M10-T05)

What every capital generator is built from. A generator composes **modules**, names the **damage section** each belongs to
and hands a `CapitalSpec` to `core/capital.build`, which writes the whole contract. `capital_test_cruiser` is the worked
example.

```
tools/procgen/parts/capital.py           Module (a part, its collision shapes, its hardpoints, in one frame), Hardpoint, twins, mounts
tools/procgen/parts/capital_hull.py      hull_section (lofted through stations), prow, armour_plates
tools/procgen/parts/capital_weapons.py   turret_mount, beam_emitter, interceptor_dome, missile_launcher, mine_layer
tools/procgen/parts/capital_bays.py      launch_bay, launch_tube
tools/procgen/parts/capital_engines.py   engine_block
tools/procgen/parts/capital_fittings.py  rotating_section, antenna, lamp
tools/procgen/styles/capital.py          CapitalStyle (a faction's paint and skin); the skins PanelMosaic, HexGrid, Seamless
tools/procgen/core/capital.py            Section, PieceSpec, CapitalSpec, problems (the checks), build (the writer)
tools/procgen/core/budgets.py            the class budgets (Q38, "Class budgets" below) and a texture set's memory
tools/procgen/assets/capital_test_cruiser.py   the test hull: one of every part, every section and hardpoint kind
```

- **Modules.** Every library part returns a `Module`: placing, turning (`transformed`, `mounted` for a part built on a
  mount) or mirroring it moves its mesh, its collision and its hardpoints together. A starboard module (`side` RIGHT, its
  name ending `_r`) gets a port twin, as do sections named `..._r`. Any other mesh joins through `capital.module(name,
  mesh, shapes)`: this is where M10-T06's organic bodies come in.
- **Sections** (`manifest.sections[]`): `name`, `kind` (`reactor`, `magazine`, `fuel`, `bridge`, `hangar`, `engine`,
  `habitat`, `structure`), `hull_share` (they add up to 1), `piece`, `chunk` and `collision` (the names of its break-up chunk
  in `hardpoints.chunks[]` and of its entry in `collision.pieces`, where its convex shapes and hit volumes are; `shapes` and
  `hit_volumes` count them), `hardpoints` (the names it holds), `modules`, `aabb_min` and `aabb_max` (body frame), and
  for the explosive kinds (`reactor`, `magazine`, `fuel`) `blast_energy_j`. A section is whole modules, so its chunk is cut
  along its modules' boundaries on its piece's atlas and keeps its own collision.
- **Pieces** (`manifest.pieces`, the station's form): `hull`, whose mesh is also the manifest's `mesh` (`<id>.glb`), and one
  piece per rotating section (`<id>_<piece>.glb`) with `pivot` (body frame, on its axis), `axis` and `spin_rad_s`. A piece
  has an atlas of its own with the high texture set and the low one a mip level down ("Class budgets"). A rotating piece's mesh and its sections' collision are in its
  own frame, on the pivot (as the station's drum: the game drives it as an `AnimatableBody3D`); its chunk draws with its own
  piece's maps, not the hull's.
- **Texel tiers** (D72): the piece's atlas carries the paint, the frame lines and the plating (tens of centimetres a texel
  on a 300 m hull); every opaque surface's `world_detail` names one shared 16 m tile (`<id>_detail_albedo.png`,
  `_normal.png`) that the game lays triplanar in the mesh's own space (`MeshAssets.apply_world_detail`), so a 1 to 3 km
  hull reads from 50 m. A hull too big for one atlas takes a bigger one within its class's budget.
- **Skins** (`styles/capital.py`): `PanelMosaic` by default; `HexGrid` for the Minbari and the Interstellar Alliance (Q45:
  `core/seams.Hexes` on the atlas and a hexagonal tile); `Seamless` for the Shadows and Vorlons (Q46: no seams, no tile).
  `CapitalStyle.surface` adds keys to every opaque surface entry: the sheen layer's numbers go there ("Sheen layer" below). `manifest.skin`
  names the skin.
- **Seam finish** (Q69, T73): every new hull wears the Hyperion's. Its style's grooves are baked 0.22 as deep and 0.6 as wide
  as drawn, its seam lines 0.89 dark (`Style.seam_depth`, `seam_width`, `panel_line_darkness`, the defaults); its skin's
  near-field tile has lines 0.6 as wide and grooves and line darkness half the full tile's (`tile_width`, `tile_soft`), and a
  fifth of its plates are painted in the hull's own colour up to half as dark (`patches`, `darkest`; `patch_tiers` for a few
  fixed shades instead: `core/seams.PatchPlates`). `HexGrid` softens its tile alike, without patches. A style sets its own
  values only on purpose. The hulls built before Q69 pin their finish until T74 (`styles.LEGACY_SEAMS`,
  `styles/capital.LEGACY_SKIN`, `styles/capital.pinned`): the Omega's fleet finish, the Hyperion's option looks B and C, the
  test cruiser, the organic test hull, and every fighter, civilian, station and raider style.
- **Hardpoints** (`hardpoints.json`, body frame, rotating pieces at rest): the ships' contract (`pods` filled from the
  engines, `nav_lights` from the lamps, `turrets` left empty: D61's civilian turrets are not these), plus, each entry with
  its `name`, `section` and `position`:
  - `weapons[]`: `kind` (`turret`, `beam`, `interceptor`, `missile`, `mine`), `forward` (the boresight at rest; the way
    a missile or a mine leaves), `up` (the mount's normal) and the kind's numbers (`traverse_deg`, `elevation_deg`,
    `barrel_m`, `barrels`; `arc_deg`, `aperture_m`; `radius_m`; `cells`, `cell_m`; `mouth_m`);
  - `bays[]`: `kind` (`bay` or `tube`), `position` (where a craft starts), `forward` (its nose and the way out), `up`,
    `exit` (the mouth's centre) and `mouth_m`, `depth_m` or `radius_m`, `length_m`;
  - `engines[]`: `thrust` (the push on the ship), `exhaust`, `share` (of the ship's thrust; they add up to 1), `radius_m`;
  - `rotors[]`: `piece`, `pivot`, `axis`, `spin_rad_s`, `sections`;
  - `lights[]`: `direction`, `role` (`port`, `starboard`, `top`, `beacon`, `flood`), `colour` (linear RGB), `range_m`;
  - `marks[]` (M10-T21, painted lettering): `position` (the letter's centre on the face), `normal`, `up`, `text` (`initial`, the
    first letter of the ship's name, or a fixed string), `height_m`, `colour`, optional `stretch` (wider print); with `mark_atlas`
    (`file`, `chars`, `columns`, `glyph_height_share`, `widths`, `tracking`, `space`: the letters' own widths, so `HullMarks.offsets`
    spaces them as type) when any exist. `parts/capital_fittings.hull_mark` makes one; `core/glyphs.py` draws a bold condensed
    sans A to Z and 0 to 9 in the show's style (M10-T22: strokes in code, no font file, edges antialiased from the exact
    distance) into `<asset>_marks.png` (6 by 6 cells of 256 px, lossless with mipmaps, sampled anisotropically; no geometry or
    hull texture spent);
  - `chunks[]` gain `piece`; `jump_point` as the carrier's.
- **Collision** (above): one entry of `collision.pieces` per section, named for it, with `piece` (the body that carries
  it); 64 shapes a section and 32 points a hull by default; `coverage` over the whole skin. A bay's hall and a rotating
  collar's bore stay open (four walls and a back; ring sectors).
- **The interior layer** (M10-T72, Q68, as Babylon 5's halls: docs/assets-station.md): every `bay`'s hall, a box from its
  hardpoint (`capital_bays.hall_of`: the mouth `exit` plus a sixth of its height, `mouth_m` across, `depth_m` back), takes the
  faces inside it (walls, deck, back, strips, lamps, fillets; not the frame on the mouth's plane) out of the piece's glb into
  `<id>_interior.glb` (`mesh.interior_file`, `interior_triangles`; the chunks keep them). The game draws it under the hull's
  mesh on `LightRig.INTERIOR_LAYER` with the hull's materials, so the sun never lights a hall; a ship in a hall goes on that
  layer too (`InteriorZones.for_bays`: one trigger volume of the halls, a child of the ship, from 8 m inside the mouth); a
  doorless bay's `bay` light is lit (`CapitalBayLamps`) and every bay lamp lights the interior layer alone
  (`LightEmitter.interior_only`), so none shows through the hull. Launch tubes are bores, not halls.
- **Also written:** `far` (M6's D70: the bounding sphere and silhouette areas), `budget` (`class`, `triangles`,
  `texture_mb` and `texture_mb_low` of this build), `dimensions_m`, and `notes` (what is not final).
- **The checks** (`capital.problems`, run by `build`): unknown kinds, shares that do not add up, an explosive section
  without a blast energy, a module in no section, a section with no module, names that repeat, thrust shares that do not
  add up, a piece beside the hull that does not spin.
- **Tests:** `test_capital_parts.py`, `test_capital_style.py`, `test_capital_framework.py`, `test_budgets.py`,
  `test_capital_test_cruiser.py` (Python); `tests/unit/test_capital_framework_asset.gd` (the test hull loads in Godot).

**The test hull**, `capital_test_cruiser`: the stand-ins' cruiser (300 by 60 by 45.6 m with its bay and antenna), 3 646
triangles, a 2 048 px hull atlas (12 cm a texel) and a 1 024 px one for the rotating section: 19.3 MB at high and 6.8 MB at
low, inside the cruiser's row; ten sections (every kind), 13 weapon mounts (every kind), a bay and two tubes, four engines,
a rotating habitat section, four lamps. The explosive sections' blast energies are placeholders until M10-T03
(`manifest.notes` says so). Pictures (gitignored): `references/screenshots/M10-T05 capital framework/test hull/`.

## Organic hulls and the sheen layer (M10-T06)

What the Shadows', the Vorlons' and the semi-organic hulls (Minbari, Interstellar Alliance, Drakh) are built from, on top of the
capital framework above. `organic_test_hull` is the worked example.

```
tools/procgen/core/sdf.py           Field (a body as a signed distance): sphere, ellipsoid, round_cone, box, torus, metaballs, swept;
                                    union, smooth_union, subtract, smooth_subtract, intersect; displaced (noise), ribbed; mesh, solid
tools/procgen/core/isosurface.py    extract: a field's skin as triangles (marching cubes on a sparse grid, its table generated)
tools/procgen/core/decimate.py      decimate: a closed mesh thinned to a triangle budget (quadric edge collapses, in rounds)
tools/procgen/core/sweep.py         Path (a curve with frames that do not twist), spline, tube (a limb's skin written directly)
tools/procgen/core/organic.py       sectioned (one body cut into a module per section), module, convex_pieces (collision)
tools/procgen/core/sheen.py         Sheen (the sheen layer's numbers), sh_from_lobes (a colour over directions)
tools/procgen/parts/organic.py      body parts as fields: lobe, pod, limb_root, body; limbs as modules: limb, taper, ribs,
                                    claw_path, leg_path, tendril_path
tools/procgen/parts/organic_petal.py  PetalPose, petal (a shell that morphs between a closed and an open pose), ring_of
tools/procgen/styles/organic.py     the looks: VORLON, SHADOW, HexColours and hex_style (MINBARI, WHITE_STAR, VICTORY)
tools/procgen/assets/organic_test_hull.py   the test hull: every organic part on one cruiser-class body
assets/shaders/hull_sheen_layer.gdshaderinc the layer; hull_organic.gdshader the hull shader that includes it
src/rendering/hull_sheen_material.gd        HullSheenMaterial: a surface with a `sheen` draws with it
scripts/organic_sheet.sh            the looks photographed on the GPU, a column a look
```

- **A body is a field, not triangles.** A generator melts body parts together (`parts/organic.body`: `smooth_union` with a
  fillet, then seeded relief), so lobes join without a crease. Limbs that stand on their own (spines, claws, legs, tendrils) are
  written directly along a path (`sweep.tube` through `parts/organic.limb`): exact however long and thin, with one UV chart
  along the limb. A limb is rooted by melting a `limb_root` of the same path into the body.
- **Meshing** (`sdf.mesh`): marching cubes at `cell_m`, only in the blocks the skin can pass through (a field's `lipschitz`
  and `slack` bound that), then thinned to the triangles asked. Watertight for every corner pattern (the case table is
  generated by one rule that neighbouring cubes share), the same mesh for the same field and cell, whatever the block size.
  A field far from its box answers with the box's distance (`reach`), which keeps a kilometre hull affordable.
- **Normals.** `Mesh.vertex_normal` carries the field's own normals through every transform, so a body cut into sections
  still shades as one skin: the cut does not show until the section breaks away.
- **Sections** (`organic.sectioned`): the body is meshed once and cut into one module per damage section by region fields
  (a face goes to the region it is deepest in); limbs and petals are modules of their own in their sections. The framework
  then writes chunks, collision and hardpoints as for any capital hull, so D12.5's sections work on organic hulls.
- **Collision** (M7's builder, D73): convex hulls per section. A body is fitted part by part: each field it was melted
  from (`parts=`) gets the hulls of its own share of the skin, with points inside the body so a piece is a solid share and
  not a slab; `convex_pieces` cuts a piece further only where its hull would bridge a hollow deeper than the tolerance.
  Limbs get a hull per run of their sections; a petal's shell is fitted as a shell. Sections overlap a little at their cuts.
- **Petals** (`organic_petal.petal`): a thin leaf-shaped shell hinged at its root, built at any `opening` between a closed
  and an open `PetalPose` on one set of triangles (a hull task can write the two ends as poses). The Vorlon destroyer's
  measured petal (T01) is the test's closed pose: 56 m long, curled to 9.2 m, chord 17.8 m, depth 6.9 m.
- **Skins.** The Shadows and Vorlons are `Seamless` (Q46: no seams, no tile). A seamless hull still gets its low texture
  set a mip level down. The semi-organic hulls take `HexGrid` (Q45, Q47): hexagons on the atlas and in the shared tile.
- **Budgets:** an organic hull is held to its class row like any other ("Class budgets"); the body's triangles are what
  `sectioned` is asked for.

### Sheen layer

A layer the game's shader lays over the four maps, as the liveries are a layer: nothing is baked. A style names a `Sheen`
(`core/sheen.py`); `CapitalStyle.surface = {"sheen": ...}` writes it on every opaque surface of the manifest;
`MeshAssets.paint_material` gives such a surface `HullSheenMaterial` (`hull_organic.gdshader`: the four maps, the hull's
detail tile where it has one, and `hull_sheen_layer.gdshaderinc` over them). Every number of a `Sheen` is a uniform of the
same name (a test holds the three lists together). What moves reads the shader's `TIME`: a visual only.

| Effect | Numbers | What it does |
|---|---|---|
| Iridescence | `iri_sh` (nine spherical-harmonic RGB coefficients, `sh_from_lobes`), `iri_strength`, `iri_base`, `iri_power`, `iri_view`, `iri_metal`, `iri_wave`, `iri_wave_s` | a colour by direction mixed into the paint towards the rim; fixed on the hull or sliding with the view; wandering in slow waves |
| Pattern | `pattern_scale_m`, `pattern_cells` (0 mottling, 1 cells with seams), `pattern_edge`, `pattern_cover`, `pattern_dark`, `pattern_tint`, `pattern_iri`, `pattern_rough`, `pattern_speed_mps` | mottling or cells in the hull's own space; darkens the paint, dulls it, breaks the iridescence up; may drift |
| Living skin | `pattern_spots`, `pattern_pulse`, `pattern_pulse_s` | spots between the blotches; blotches and spots swell and fade, each patch on its own beat |
| Ridges and pools | `pattern_relief`, `liquid`, `liquid_dish`, `liquid_tint`, `liquid_flow_mps` | the seams between cells stand up as dull ridges; each cell is a pool of glossy liquid, higher at its edges, slowly rippling |
| Glow | `glow_colour`, `glow_energy`, `glow_veins`, `glow_rim`, `glow_pulse_s`, `glow_pulse` | a faint light of the hull's own, even or in the pattern's veins, breathing |
| Clear coat | `coat` | the share of `settings.hull_sheen` the skin takes |
| Variant | `variant_share`, `variant_tint`, `variant_sh`, `variant_glow`, `variant_all` | a second colouring worn by a share of the ships |

The looks (`styles/organic.py`; the maintainer's picks, 2026-11-21, from the sheets in
`references/screenshots/M10-T06 organic and sheen/`):

- **Vorlon** (`VORLON`, seamless): yellow-green with bold dark mottling, soft-edged, alive as a cuttlefish's skin (blotches
  that swell and fade, small spots opening and closing between them), a green-gold to violet iridescence that wanders, a
  faint breathing glow, deep blue petals.
- **The red-based Vorlons.** A fifth of Vorlon hulls (`variant_share` 0.2) are copper-brown with the same mottling, their
  petals still blue. The rule: `HullSheenMaterial.variant_for(sheen, ship_name)` draws it from a seeded hash of the ship's
  own name (no shared generator; the same ship is the same colour in every run) and the ship puts it on its drawn pieces
  as the instance uniform `skin_variant` (`RenderPiece.set_skin_variant`; `CapitalShip.skin_variant`). `variant_all` (the
  generator option `variant`) turns every ship, for look sheets.
- **Shadow** (`SHADOW`, seamless): the blackest skin in big slow cells. The seams are raised, dull ridges, darker than the
  skin, with a faint violet in them; each cell is a pool of glossy black liquid drawn up where it meets its ridge.
- **Hexagonal hulls** (`hex_style(HexColours)`): a hint of sheen at the rim and soft mottling, in a colour set a hull. The
  hull task hands its own set; three are made from the show's stills:

| Set | For | Skin | Mottling | Sheen |
|---|---|---|---|---|
| `MINBARI` | the Minbari hulls (T28, T39's Nial, T58's Flyer) | blue | dark blue | cyan to deep blue, no purple |
| `WHITE_STAR` | the White Star (T33) | silver | violet-blue veining | pale violet |
| `VICTORY` | the Victory class (T34) | charcoal | dull, muted red markings | steel blue |

**The test hull**, `organic_test_hull` (not a ship of the show): a cruiser-class body 300 by 180 by 97.6 m: a head, three
lobes round a core, a ribbed tail and two pods as one skin cut into `head` (bridge), `core` (reactor) and `tail` (engine);
a claw and three ribbed legs a side, three tendrils, three half-open petals. 50 250 triangles (the cruiser's 60 000), one
4 096 px atlas (11 cm a texel): 53.3 MB at high and 13.3 MB at low (56.0 / 16.0). Eight sections, 94 convex shapes; every
skin point within 3.1 m of the collision and the collision within 2.9 m of the skin. A beam on the head, one engine on the
tail. About 90 s to build and 7 GB at its peak, so it is built alone (`BUILD_ALONE`). Options: `look` (`vorlon`, `shadow`,
`minbari`, `white_star`, `victory`), `variant`, `cell_m`, `body_triangles`.

- **Tests:** `test_sdf.py` (fields, the mesher, the decimator, a mesh's own normals), `test_organic_parts.py` (paths,
  limbs, petals, a sectioned body and its collision), `test_sheen.py` (the harmonics, the numbers against the shader and
  the material, the looks), `test_organic_test_hull.py` (Python); `tests/unit/test_organic_test_hull_asset.gd` (the hull
  draws with its sheen, both texture sets, the per-ship variant).
- **Open:** the red colouring reaches a `CapitalShip`'s pieces only: break-up chunks (T08 to T11) and pooled fighters (T42)
  must take `skin_variant` when those tasks land. What moves (the Vorlons' skin, the Shadows' liquid) is judged in a
  windowed run `(H)`; the sheets are stills. The hexagons are laid on three projections, so they distort where a body
  curves sharply (limbs, pods).

## Class budgets (M10 Q38)

What a hull of each class may cost, approved by the maintainer on 2026-11-20 (M10-T05). Every M10 hull task names its
hull's class and stays inside its row; `tools/procgen/core/budgets.py` repeats the table (`CLASS_BUDGETS`, `over_budget`)
and `test_budgets.py` reads this one and holds the two together.

| Class | Triangles | Atlases | Normal map | High set, MB | Low set, MB |
|---|---|---|---|---|---|
| fighter | 40 000 | 1 x 2 048 px | 4 096 px | 32.0 | 10.0 |
| small_craft | 30 000 | 1 x 2 048 px | as the atlas | 16.0 | 6.0 |
| cruiser | 60 000 | 1 x 4 096 px | as the atlas | 56.0 | 16.0 |
| capital | 100 000 | 2 x 4 096 px | as the atlas | 109.3 | 29.3 |
| dreadnought | 150 000 | 4 x 4 096 px | as the atlas | 216.0 | 56.0 |

- **Triangles**: the whole hull, every piece, the same in both texture sets. The importer's levels of detail come on top.
- **Texture memory** is one texture set on the card as the game imports it: block compressed with mipmaps, half a byte a
  texel for the colour, ORM and glow maps, one for the normal map (53.3 MB a 4 096 px atlas, 13.3 MB a 2 048 px one), plus
  the shared 1 024 px detail tile (2.7 MB, the same in both sets). Only one set is loaded.
- **High** is the atlas at its full size. **Low** is one mip level down: every map of the set half as wide (2 048 px for
  4 096, 1 024 for 2 048, a fighter's 4 096 px normal map 2 048), about a quarter of the memory; it also keeps the major
  seams alone, as the civilians' low set does. `core/capital.py` writes both (`LOW_SHRINK`); the low set names its own
  glow map, which the game's hull material takes with the others (`MeshAssets.map_file`).
- **A fighter** may carry a normal map twice its atlas, as the Starfury does. The fighters and civilians built before M10
  write their low set at full size; they are not held to the low column until a task says so.
- **Which class**: fighters; small craft (shuttles, pods, the Flyer); cruisers up to about 600 m; capitals to about 2 km;
  dreadnoughts beyond. The hull task chooses, by what the hull needs up close.

**The GPU test behind it** (`scripts/class_budget_probe.sh`, on the maintainer's RX 6950 XT, `forward_plus`, uncapped): 96
stand-in hulls, each at its class's ceiling, in view at once: 2 dreadnoughts, 6 capitals, 12 cruisers, 16 small craft and 60
fighters of 18 types (so 18 hulls' textures), each surface with four maps and the detail tile laid triplanar as the game
lays it. The empty scene takes 0.33 ms of GPU time at 1920x1080.

| Run | Frames a second | GPU time, ms | Draw calls | Triangles drawn |
|---|---|---|---|---|
| 1920x1080, levels of detail on | 1 195 to 1 235 | 0.59 to 0.76 | 31 | 0.40 to 0.54 million |
| 1920x1080, none (every hull at full detail) | 506 | 1.87 | 27 | 4.5 million |
| 3840x2160, levels of detail on | 440 to 678 | 1.30 to 2.09 | 38 | 0.62 to 0.76 million |
| 3840x2160, none | 272 | 3.48 | 27 | 4.5 million |
| 1920x1080, twice the triangles, none | 354 | 2.74 | 27 | 9.0 million |

The ranges are the fleet spread out and the fleet with one dreadnought 50 m off the camera, across the whole view. The
fleet's high sets took 1 091 MB in the renderer (1 069 MB by the table's arithmetic); the test hull's high set 18 MB (19.3).
The card's own counter (`mem_info_vram_used`) rose from 5 761 to 7 608 MB, with other programs holding most of the rest.
**Texture memory is what binds, not triangles**: twice the triangles with no level of detail still draws in under 3 ms, while
a fleet's textures are a gigabyte at high and about 270 MB at low. Pictures (gitignored):
`references/screenshots/M10-T05 capital framework/probe*/`.

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

## `ea_omega` (M10-T21)

`tools/procgen/assets/ea_omega.py` on `parts/ea_omega.py` (the structure, measured off the reference), the capital parts
library, `parts/capital_solids.py` and `styles/ea_capital.py`. The shape is described in `docs/design-references.md`, "EA
Omega-class destroyer". Earth Alliance only; the renegades fly it with their marking (M10-T02, not built here: the style's
`livery` hook stays unused).

### Measurements

| | |
|---|---|
| Reference | `EA Omega Destroyer.stl`, mapping `--right=+y --up=+z --aft=+x`; the drum is turned 45 degrees in the file (`drum_deg -45` builds it so for the compare) |
| Length | **1 714.3 m** (T01) |
| Span, height | 474.6 m, 545.3 m with the drum turned as the reference's (474 x 545); 620 x 478 m at rest, the arms to port and starboard |
| Pieces | `hull` and `drum`, the rotating section (555 to 879 m from the boom's tip), on its own 4 096 px atlas, turning at 0.1 rad/s about the spine's axis (about a third of a g at the arms' bodies) |
| Triangles | 12 016 (budget 100 000) |
| Texture sets | 109.3 MB high, 29.3 MB low (budget 109.3 and 29.3: two 4 096 px atlases); measured 110 MB high and 30 MB low on the RX 6950 XT (model sheet, against the empty scene) |
| Mass (informational) | 1 053 kt from the skin's area at 260 kg/m2; the `ShipSpec` takes it (1.05e9 kg) |

### Sections and hardpoints

Twelve sections: `bow`, `bridge`, `fuel` (the reactant tanks under the command block), `spine_fore`, the drum's `drum_hub`,
`hangar_r` and `hangar_l`, `magazine`, `spine_aft`, `reactor` (the engine housing), `engine_r` and `engine_l`; blast
energies on the fuel, magazine and reactor. Mounts as `data/capitals/loadouts.json` (T03, Q53), each naming its `weapon`:

- 4 `ea_plasma_heavy` turrets on the forward spine's centre line (two above, two below), 24 m (the maintainer, 2026-11-21);
- 12 `ea_pulse_medium` turrets on the spines' corners, in three rings of four;
- 6 `ea_sweep_beam` emitters: one on each shield's pod covering the fore hemisphere, four on the skirt's corners the aft;
- 2 `ea_missile` batteries on the aft spine over the magazine;
- 8 `ea_interceptor` domes along the flanks;
- one launch bay facing the bow (the maintainer, 2026-11-21: one bay, on the command block's fore face just above the two oval
  retro thrusters), in the `bow` section: the reference's octagonal hall, a 74 by 34 m mouth (fillets in its corners make it an
  octagon) at 182 m, the hall 134 m deep, its housing standing out of the head as the reference's tube
  (`parts/ea_omega.fore_bay`); `craft` `starfury_ally`, `capacity` 32. The bridge's window moved up the head's face, above the
  bay. The drum's rims carry no bays: a panelled band runs round their outer faces. Nothing of the hull stands ahead of the
  mouth (`test_the_launch_path_ahead_of_the_bay_is_clear`), so T17's launches leave straight ahead;
- the two oval retro thrusters under the reactant spheres: open nozzles from 168 m to their dark throats at 258 m, as the
  reference's (`parts/ea_omega.retro_nozzle`, which the Nova shares);
- running lights (red to port, green to starboard, white on the roof, red-orange beacons at the keel and the stern), the
  four engines in a square, and a jump anchor 1 500 m ahead with a 450 m mouth.

**The lit bays** (the maintainer, 2026-11-21: the bays keep the hull's colour and glow red, as Babylon 5's docking bay; every
EA hull's bays do). `parts/capital_bays.launch_bay(lit=True)`: the frame round the mouth in the hull's paint, a red band
round the mouth on its face, three rings of red strips down the hall (the first at the mouth, the deeper ones dimmer), red
guide strips on the deck, a red lamp at each corner of the mouth and the hall's walls faintly red; each bay also gets a
light hardpoint of role `bay` (`bay_fore_light`, red, in the hall's mouth) for the game's light rig. The colours are the
station's: `BAY_RED` for the strips (1.6 at the mouth, as the station's mouth frames; 0.9 inside) and its red lamp. The roles
(`bay_light`, `bay_light_deep`, `bay_lamp`, `bay_hall`) come with `styles/ea_capital.bay_light_materials`, which the
Hyperion, Nova, Warlock and Explorer get with the style.

### Fidelity (Q10)

```
.venv/bin/python3 -I tools/refview/compare.py "references/EA Omega Destroyer.stl" ea_omega --length 1714.3 --right=+y --up=+z --aft=+x
```

(built with `drum_deg -45`, as the reference has its drum).

| View | IoU | | Dimension | Mesh / STL |
|---|---|---|---|---|
| top | 0.969 | | length | 1.000 (1 714.3 / 1 714.3 m) |
| side | 0.939 | | width | 1.001 (474.6 / 473.9 m) |
| front | 0.923 | | height | 1.000 (545.3 / 545.1 m) |

(Re-scored with the forward bay, 2026-11-21; the build before it scores the same, so the 0.950 and 0.930 first written here
were an earlier build's.)

**Per-part sections** (`parts/ea_omega_fidelity.py`, `tools/refview/sections.py`; `test_ea_omega.py` holds them): the bow
block, the forward bay, the tankage (its forward plane by outline: the reference's tanks are open shells there), the retro
thrusters, the command section, both spines, the collars, each drum arm and the hub (turned back 45 degrees, each in its own
window), the engine housing and the engines, 35 planes, every one at 0.90 or over (lowest 0.909, the retro nozzle at 200 m);
no exemptions. The bay's hall runs through the bow block and the command section, and the reference's hall is open shells its
winding fills, so the bow block's planes and the command section's at 300 m compare outlines (0.986) and the hall is judged by
relief, as the bow sees its mouth (0.962 at 250 and 300 m); the retro nozzles likewise (0.909, 0.911).

### Surface: look A, show grey with a rust face (the maintainer, 2026-11-21)

From three options (B, station grey and clean; C, dark gunmetal with an ochre face): a mottled blue-grey plate mosaic
(18 x 9 m plates cut twice, frames every 30 m), dark recessed bands, the command section's fore face rust ochre, black
window rows, blue-white engine throats.

### In the game

`assets/ships/ea_omega.tres`, catalogue `ea_omega`, capital class `destroyer` (heard 500 km out, a 90 s jump recharge):
1.05e9 kg, 1.2 m/s2 on its four mains with stand-in retros at half a main (reaction, Q51: no flip), turns at 2 degrees a
second (1.5 in roll), 30 000 hull points, opens its own jump points. `CapitalShip` builds it; the drum is a `CapitalRotor`
(an `AnimatableBody3D`, as the station's drum) whose hits are named `drum_hub`, `hangar_r` or `hangar_l`. Destroyed, it leaves
play through the destruction director, its sections gone from the core; the staged break-up along its section chunks is
T11's. Its guns, beams, missiles and interceptors fire when T12 to T14 put capital weapons on the native rows; the weapon
numbers are `data/capitals/loadouts.json`'s. Names: `data/ships/names.json` gives the Omegas twenty Greek names, the
Agamemnon first, as `EAS <name>` (`ShipNames`; the console's `capital spawn ea_omega` uses them). **Name letter**: as the show's
Zeus and Talos, each Omega wears the first letter of its name in large white block print at the bottom of each shield, on the
leaning lower panel (`parts/ea_omega.shield_mark`, 40 m tall, a fifth of the way up the panel). The hull's `marks` and the glyph
atlas carry it; `CapitalShip` stands one `HullMarkNode` quad (`HullMarks` picks the letter from the display name, skipping the
faction's all-capitals prefix) a little off each face when it is created, so any hull with a name list and marks reuses it.

**Hull decals, floods and bay doors (M10-T22, the Hyperion; off unless a hull asks).** A `CapitalSpec` may carry `markings`
(module name, `core/textures.Marking`) baked into its hull's maps: `Marking.emblem`, the Earth Alliance emblem drawn in code
(`core/hull_decals.py`, close to the maintainer's reference, no image file; Q64), and `Marking.flood`, a flood lamp's pool of
light baked as glow, so a lit pool costs the GPU nothing (the lamp itself is a `flood` light fitting). A hull may instead carry a
picture as a mark (`capital_fittings.hull_image`, `image` naming a `hull_decals.IMAGES` key): the build writes its image at 2 cm a
texel and, with a `glow`, its lamp's light on it (`<asset>_<mark>_glow.png`), and `HullMarkNode` draws it as one sharp quad
(the Hyperion's emblem, which baked into the hull blurred to the plating's texels). A mark with `outline` prints from the
glyph atlas's outlined twin (`<asset>_marks_outlined.png`, black rims 0.06 cap heights wide, written only when a mark asks).
Materials with `smooth` (the Hyperion's barrels and bores) take no grime, chips or dirt. `launch_bay(rim=False)`
keeps a lit bay's red inside the hall; `launch_bay(metal=True)` lines it as Babylon 5's docking bay (the Hyperion's, after the
maintainer's look round): grey `bay_metal` (the station's `bay_tunnel`: #A8AAAE, metallic 0.7, roughness 0.32, faint red 0.04;
`ea_capital.bay_metal_materials`), small red lamps along the roof, no strips, the `bay` light mid-hall; the game lights it red
only while the door is open (`BayDoorNode`'s `LightEmitter`, energy 3.5 times how far it is open, the light's `range_m`, in the
`LightRig`'s omni-slot competition). The Hyperion's seams are subtler than the fleet's (0.22 of the depth, 0.6
of the width; line darkness 0.89), the defaults for every new hull since Q69 ("Seam finish" above). `launch_bay(door=True)` builds a roll housing over the mouth and guide rails, and leaves a
`door` hardpoint (`hardpoints.doors[]`: the shut shutter's centre, `forward`, `up`, `size_m`, `slats`), with rails and a sill that
close the gap round it. `CapitalShip` draws each door as slats on a dark backing plate, so a shut door shows no light
(`BayDoorNode`, rules in `BayDoors`), shut by default; `set_bay_door(bay, open)` winds it up into the housing (T17's hook; the
console's `capital doors open|close[:<bay>]`).

Sheets (gitignored, `references/screenshots/M10-T21 Omega/`): `look_sheet.png` with its shots in `look_sheet/` (from 50 m,
1 km, 10 km and 100 km, the drum in the low texture set, the lit bays from 60 m and into one from 40 m, lit and back-lit), made
with `scripts/model_sheet.sh`; `option_sheet.png` and `section_compare.png` from stage 1. At 100 km the hull is under a pixel.

### Open for the human tester `(H)`

- The lit bays' red: strength and how far off it still reads.
- The 4 096 px atlas over 1.7 km from 50 m (the plates and the detail tile carry it).
- VRAM and frame cost with Omegas in a fight.

## `ea_nova` (M10-T23)

`tools/procgen/assets/ea_nova.py` on `parts/ea_nova.py` (the structure, measured off the reference), in the Omega's parts and
look (the maintainer: the Nova reuses them): its slab armour, girder spine, octagonal collars, nacelles, lit bays, turrets,
beams, interceptors, lamps and `styles/ea_capital.py` look A, worn since T67 in the **soft finish** (`ea_capital(look,
finish="soft")`, Q64): the Hyperion's skin (the default finish since Q69: shallow narrow seams, small patches of darker plates,
little tone wander, faint seam lines) in the Omega's colours, its bays lined in grey metal; the Omega keeps the fleet finish
until T68. The shape is described in `docs/design-references.md`, "EA
Nova-class dreadnought". Earth Alliance and the renegades (their red X marks, as the Omega's).

### Measurements

| | |
|---|---|
| Reference | `EA_Nova_Dreadnought_(with_guns).stl` (T67), mapping `--right=-x --up=+z --aft=+y`, 0.2854 m a unit; its spine's axis is 43.3 m above its box's middle and 0.25 m to starboard of it |
| Length | **1 502.1 m** (T01) |
| Span, height | 383.0 m (the wing guns' masts) x 443.7 m (roof masts to keel mast); the STL 382.6 x 446.1 |
| Pieces | `hull` only, one 4 096 px atlas |
| Triangles | 50 864 as the build counts them: 25 432 in the hull (budget 100 000) and as many in its damage chunks (T67's red fittings and running lights add 2 560 to each); 50 928 before T67 cut the gun barrels to 12 sides |
| Texture sets | 56.0 MB high, 16.0 MB low (budget 109.3 and 29.3); measured 56 MB and 16 MB on the RX 6950 XT (model sheet, against the empty scene) |
| Build | about 3.6 to 4.2 min (3 min 44 s with the forward bays) and 10 GB at its peak on the maintainer's machine (`BUILD_ALONE`) |

### Sections and hardpoints

Ten sections: `bow` (the armour, the keel, the aerials and the launch bay's hall), `bridge` (the bridge tube, the bay's frame,
probes and fins, the open front's decks and the roof; T67 moved them here so neither section's shapes are merged), `fuel` (the capsules and the retro thrusters under the bridge tube), `spine_fore`, `hangar` (the hangar block), `spine_mid`, `spine_aft`,
`reactor` (the engine housing and the engine frame), `engine_r` and `engine_l`; blast energies on the fuel and the reactor.
Mounts as `data/capitals/loadouts.json` (T03, Q53), each naming its `weapon`:

- 18 twin gun pods (T67, `parts/ea_nova_guns.py`, the reference with guns), the Nova's only weapons (Q71: no beams, no
  separate interceptor domes): a faceted housing round two long barrels and a mast through it. **12 fixed pulse cannons**
  (`ea_pulse_cannon_fixed`, `bolt_fixed`, `pulse_*`): a turret hardpoint at the barrels' roots in the housing's nose with no
  traverse (two barrels, traverse 0, elevation 0), aimed by the hull. **2 swivel pulse cannons** (`ea_pulse_cannon_swivel`,
  `bolt_medium`, 2 x 11.25 / 2 s: three quarters of the fixed one's damage; `pulse_hangar_r` and `_l`, M10-T14 review, the
  maintainer 2026-11-24): the hangar block's pods, whose fire ahead the wing pods block (as in the reference), stand on the
  same swivel ring on the block's flank and cover the half sphere over it (traverse 180, elevation 0 to 90, 25/20 deg/s), the
  hardpoint at the ring's centre with an 86 m barrel to the muzzles. **4 interceptors** (`ea_interceptor_pod`,
  `interceptor_mid_top_r`, `_low_r` and their port twins): the middle lug's pods (x ±95, y ±75.5, z 745.7 m), whose fire ahead
  the fore lug's pods block, stand on a swivel ring (an 18 m base and a 15.5 m race between the plate and the housing) and cover
  the half sphere over their plate (traverse 180, elevation 0 to 90), the hardpoint at the ring's centre. One beside the command block (`bridge`) and one on the flank wing's tip (`bow`) each side, one on each
  flank of the hangar block (`hangar`), and four on each ring lug's outriggers, above and below either side (`spine_fore`,
  `spine_mid`, `spine_aft`; the aft lug's face the stern), each on an outrigger plate out to 113.5 m with a brace under it. The
  loadout's count is the reference's; T67 moved the mounts from the waist and the roof's channel (the older STL had no guns);
- the girder's roof and keel channel aft of the hangar holds the reference's blocks and thin decks (`CHANNEL_BLOCKS`,
  `CHANNEL_DECKS`), and the hangar block's roof and keel a channel 44 m wide with four ribs across it (`HANGAR_CHANNEL`);
  the barrels are 12-sided, grown to a round barrel's area (`BARREL_SIDES`, `BARREL_GROW`). Collision keeps the capital
  standard of 64 shapes a section; `COLLISION`'s `max_excess_m` (2.5 m, the coverage check's reach) stops the merge joining two
  shapes whose hull stands out of the parts it covers by more, so a thin mast or fin is never joined to its twin across the
  girder (T67: without it a top and a low pod's masts became one wall through the ship). The pods beside the command block are in
  `bridge` so the `bow` section can merge to 64 within that limit;
- one launch bay facing the bow (the maintainer, 2026-11-21; rebuilt in T67, `parts/ea_nova_bow.py`): the reference's octagonal
  hall, a 62 by 27 m mouth at 190 m in a proud octagonal frame (a flat lip at 182.6 m bevelled back to the mouth and to the
  frame's outer edge at 189.5 m, its back at 196 m, four thin probes forward from the lip's corners to 136.5 m) with a thin
  wedge fin each side above and below the axis, the hall 139 m deep back to the reference's wall at 329 m, in the `bow` section; `craft` `starfury_ally`, `capacity` 24, launched and recovered (`recovers`) on a hidden elevator in the floor 20 m before
  the back wall (`elevator`, a point; `elevator_travel_m` 30 down to the hangar deck; Q71, for T17). The hall is Babylon 5's grey bay
  metal (`launch_bay(metal=True)`: #A8AAAE, metallic 0.7, roughness 0.32, faint red 0.04) lit by small red lamps and the bay's red
  light hardpoint; no glowing rim and no door (Q64). Nothing of the hull stands ahead of the mouth but the frame's probes
  (`test_the_launch_path_ahead_of_the_bay_is_clear`), so T17's launches leave straight ahead;
- the **open-frame bow** (T67, Q61/Q62): the armour is open at the front, and behind it stand the reference's decks: three deck
  plates forward (y 76, 48, 20; the two lower ones sloping back to the armour at their ends, `PLATE_WINGS`) and a sill and a
  plate under the frame, deck blocks between them at the reference's depths (`DECKS`), a bulkhead beside the hall at 331 m, the roof block with the bridge's
  window and two humps, a deck block under the bay, the backing behind the tanks, the retro thrusters' radial struts, and the keel
  (the wall behind the retro thrusters at 257 m, a block under them, the sloping face with a block, two domes and the pipes up
  to the spine). The hall and the decks are the bow's open interior: T72 (Q68) gives them the interior layer
  (`ea_nova_bow.INTERIOR_MODULES`);
- the two oval retro thrusters under the capsules: open nozzles from 165 m with the reference's rounded lips
  (`ea_nova_bow.retro_lip`, back to the outer wall at 173 m), closed by dark throats at 236 m (`parts/ea_omega.retro_nozzle`);
  the flank strake through the vertical plate is the reference's flattened hexagon (`STRAKE_OUTLINE`);
- running lights (red to port, green to starboard, white on the roof, red-orange beacons under the keel and at the stern), the
  four engines in a square, and a jump anchor 1 500 m ahead with a 400 m mouth.

**Name letter**: each Nova wears the first letter of its name in the Omega's place (Q61, Q62): on the lower plate's face, a
at the middle of the lower plate's face (its area's centre), square to its edges, light grey rimmed in black as the stills paint it (`mark_initial_r` and `_l`, 36 m, `HullMarks`). **Renegades**: a red X on each
vertical plate and on the roof (`only_faction` `renegades`). **Names**: `data/ships/names.json`, twenty generals and admirals,
the show's Schwarzkopf first.

**Paint and lamps** (T67, `parts/ea_nova_marks.py`, from the show's stills and the Omega's): the ship's name (`mark_name_r`, `_l`,
10 m, black print on a light grey board ringed by a black line, the stills' name board: `placard`, which the game sizes to the
name, `HullMarkNode.create_placard`) high on each vertical plate just under its top edge, ahead of where the spine's fins come through the plate at 330 m; the Earth Alliance emblem
(`mark_emblem_r`, `_l`, 56 m wide, `core/hull_decals.py`) low on it under the pod; a flood lamp on a bracket under each, shining
up the plate, its pool baked into the plate's maps (the emblem's glow passed to its decal); red beacons beside the top mast's, the
keel mast's and the sensor boom's tips; and a darker grey band 4.5 m wide, 0.5 m in from the edges of the armour plates, the
hangar block's roof and keel, the collars and the housing (`parts/capital_paint.py`, a placed `Marking.paint`, 0.36 of the hull's
albedo; for the Omega in T68). Along the spine: rows of small red-lit fittings on the shelves' edges beside the gun-deck bays (430
to 520, 780 to 850, 940 to 1 000 m) and red running lights every 18 m along the fins' tips, glowing paint with no light of their
own; and a soft red lamp (`light_bow`, 2.4 m, its light reaching 60 m) on the starboard lower deck's face beside the bay, the stills' bow lamp. The soft finish's grey is re-read from the stills (`ea_capital.SOFT_PAINT`: hull `#7D807C`, panels `#6B6E6A`, dark
`#3A3C3A`, from look A's `#8C9199`, `#747A84`, `#3F434B`), its patches in two shades (`SOFT_PATCH_TIERS`: three quarters 12 %
darker, a quarter 40 %, on 35 % of the plates). The seams are the Hyperion's (5e083eb9: 0.22 of the groove's depth, 0.6 of the
line's width, line darkness 0.89, groove 3 mm).

**Bay mouth** (T67): the frame's inner faces lay on the hall's walls and the fillets from 190 to 196 m and flickered; the frame's
back now slants out from the mouth's edge, and the tube starts at the frame's back (`test_the_bay_mouth_has_no_flickering_faces`,
`core/coplanar.py`). **No shared faces anywhere** (T67, second round): wherever two parts lay flush in one plane facing the same
way (the spine's fins on its core, the keel's block on its wedge, the deck plates' wings on the flank wings, a ring's outrigger
under its gun arm: 334 pairs), `parts/capital_flush.py` sets the part with less face in that plane 0.1 m back behind it, a few
rounds where fittings stack (87 parts, by 0.1 to 0.5 m); `test_no_two_parts_share_a_face_anywhere` holds the whole hull to it.

### Fidelity (Q10)

```
.venv/bin/python3 -I tools/refview/compare.py "references/EA_Nova_Dreadnought_(with_guns).stl" ea_nova --length 1502.1 --right=-x --up=+z --aft=+y --model-offset -0.25,-43.3,0
```

(`--model-offset` moves the STL's axis onto the build's: 43.3 m is past the compare's 2 % shift window).

| View | IoU | | Dimension | Mesh / STL |
|---|---|---|---|---|
| top | 0.933 | | length | 1.000 (1 502.1 / 1 502.1 m) |
| side | 0.945 | | width | 0.998 (382.0 / 382.6 m) |
| front | 0.927 | | height | 0.995 (443.7 / 446.1 m) |

Against the reference with guns before T67's pods: top 0.743, side 0.856, front 0.802, width 0.544 (the older STL's 0.952, 0.956,
0.965).

**Per-part sections** (`parts/ea_nova_fidelity.py`, `tools/refview/sections.py`; `test_ea_nova.py` holds them), against the
reference with guns: the command block (by outline: the reference's is a shell of plates round loose parts, open at the front),
the keel wedge, the tankage, the flank wing, the fore spine, the three ring lugs, both collars, the hangar block, the mid and aft
spine, the engine housing and the engines, with the retro thrusters by relief, and (T67) each starboard gun pod across its
barrels and its housing's body by outline (its housing is an open shell round the barrels; the reference's port pods sit a few
metres off the mirror image): 54 planes, every one at 0.90 or over (lowest 0.903, the fore spine at 500 m; the pods 0.917 to
0.956); no exemptions. The bay's hall lies inside the command block's planes. Its mouth alone by relief, in the tube's window,
scores about 0.8: the reference's tube is a thin frame a metre off the centre line, among loose parts the build leaves out; not a
gate, for the maintainer.

**Bow face** (T67, T66's `tools/refview/fidelity.py`; `FACE_SWEEPS`, `FACE_BY_DEPTH`, `FACE_MEAN_IOU`, `FACE_DEPTH` in
`ea_nova_fidelity.py`, `test_the_bow_face_holds_its_floors`). The reference's face is an open shell, so the z cuts (150 to 450 m
every 4 m) and the y cuts (-175 to 95 m every 5 m) are gated by outline, and the x cuts (-70 to 70 m every 5 m) by **face
depth** (`fidelity.sweep(face=True)`, `--face`: each line filled from its first surface aft, so a deck block a few metres deep
counts by where its face stands, not by what a row fill sees through its gaps; by outline they score 0.845, 6 of 29). With the
guns: z mean 0.951, 73 of 76 at 0.90 or over (the frame's back at 194 m, 446 and 450 m); x by face depth mean 0.912, 21 of 29;
y by outline mean 0.952, 51 of 55 (by face depth, reported only on the maintainer's word: mean 0.866, 35 of 55, lower round the
bay's mouth, y -20 to 15 m, and at the roof's edge); the front depth map agrees within 2 m on 59 % of the face, 8.0 m apart on
average (against the older STL before T67's pods: z 67 of 76, x 4 of 29 by outline, 64 % and 7.4 m; the pods beside the command
block now stand in the z cuts' window).

### In the game

`assets/ships/ea_nova.tres`, catalogue `ea_nova`, capital class `dreadnought` (heard 1 000 km out, Q51; a 120 s jump
recharge, `data/capitals/capitals.json`): 6.8e8 kg (680 kt from the skin's area at 260 kg/m2, the Omega's rule), its inertia
a solid box of that mass over its length, span and height (as the Omega's), 1.0 m/s2 on its four mains with stand-in retros
at half a main (reaction, no flip), turns at 3 degrees a second (2.4 in roll) with 3x the Omega's angular acceleration (Q71; torque 7.5e11, 7.0e11,
7.3e10 N m; to be tuned later), 36 000 hull points (T03), opens its own jump
points. `CapitalShip` builds it (no rotating section); destroyed, it leaves play through the destruction director. Its pulse
cannons and interceptor pods fire when T13 and T14 put capital weapons on the native rows. `capital spawn ea_nova` names it from the
list (`EAS Schwarzkopf`, `EAS Nimitz`, ...) and each wears its own name's first letter (`HullMarks`, as the Omega's).

Look sheet (gitignored): `references/screenshots/M10-T23 Nova/look_sheet_v2.png`, its shots in `look_sheet_v2/` (from 50 m in
both texture sets, 1 km, 10 km and 100 km, the forward bays from 70 m lit and back-lit and from 180 m, side by side with the
Omega), made with `scripts/model_sheet.sh`; `section_compare.png` and the first look sheet are stage 1's (the flank bays).

### Open for the human tester `(H)`

- The look beside the Omega; the show's Nova is darker (grey-brown and ochre) than look A.
- One 4 096 px atlas over 1.5 km from 50 m.
- The forward bay's red and its mouth beside the reference's tube, from ahead (`references/screenshots/M10-T23 Nova/bay_fix/`).

## `ea_hyperion` (M10-T22)

`tools/procgen/assets/ea_hyperion.py` on `parts/ea_hyperion.py` (measured off the reference; `ea_hyperion_fidelity.py` holds the
numbers) and its own style `styles/ea_hyperion.py` (the show's light grey with royal-blue bands, plated in the fleet's mosaic),
on the Omega's machinery (`styles/ea_capital.capital_style`: lit red bays, blue-white engines). Earth Alliance and the renegades.
The shape is in `docs/design-references.md`, "EA Hyperion-class heavy cruiser".

### Measurements

| | |
|---|---|
| Reference | `EA Hyperion Class Heavy Cruiser.stl`, mapping `+x +z -y` (T01); the reference is lopsided by modelling slop, so the hull is built symmetric (the maintainer approved) |
| Length | **1 025.39 m** (T01) |
| Span, height | 249.4 m x 266.2 m (the STL 248.7 x 267.4) |
| Pieces | `hull`, one 4 096 px atlas |
| Triangles | 10 176 (capital budget 100 000) |
| Texture sets | 56.0 MB high, 16.0 MB low |

### Sections and hardpoints

Eleven sections: `bow`, `magazine`, `bridge` (the tower, blade, fin and pods), both `hangar` sponsons, `truss`, `reactor`,
`spine_aft`, both `fuel` tanks and `engines`. Mounts as `data/capitals/loadouts.json` (T03): 2 heavy plasma in the bow face,
2 particle cannons (deck and keel), 2 medium and 4 light plasma/pulse domes, 2 torpedo tubes, 4 interceptors, and in each
sponson a lit Starfury bay over a lit shuttle bay (6 Starfuries, 2 shuttles).

**Paint** (the maintainer, 2026-11-21): the royal-blue band is a continuous ring, as in the show's stills. Two rings round the
forward hull (172 to 192 m and 318 to 338 m), each painted across the roof, both flanks and the belly (the hull lengths,
the deck and the keel strake are cut at the band so it closes under the hull), and one round the tower. The old single stripe
along the roof's starboard edge is gone.

**Name and hull number**: the ship's whole name in the bands' blue across the forward roof and on each flank of the tower
(`mark_name_*`, `text: "name"`), and its hull number, the show's "21" (still 02), white outlined in black like the bow's name (Q65), on each flank of the forward
hull between the bow band and the flank dome turret (`mark_number_r` and `_l`, 26 m, `text: "number"`; each leans with the
widening flank so neither digit sinks into it). The number is data:
`data/ships/names.json` `hull_numbers` gives each Hyperion name its own (`Hyperion` 21, `Lexington` 34, ...); `ShipNames.hull_number_of`
reads it (a repeated name, "Hyperion 2", keeps its number) and `HullMarks.text_for` prints it. **Renegades**: red X marks on
both tower flanks and the roof (`only_faction` `renegades`).

**Nose, emblem and floods (M10-T22 refinement)**: the bow's face is hull grey with a blue ring just behind it (`nose_ring_lip`
and `nose_ring`, 50.3 to 58 m, behind a 0.3 m grey lip). Its centre is recessed 3.25 m (the V5c's 3.26 m) inside a 3 m lip
(`nose_recess`; the V5c's lip is 7 to 11.5 m, too wide for the first STL's outer rods), the floor grey (`nose_face`); the antenna
rods (lowered 2.5 m, `ARRAY_LOWER_M`), the torpedo tubes and the bow lamp all root in the floor. A forward dish hangs under the
crown's saucer as both STLs have it (`forward_dish`, the V5c's: a flat face 11.3 m in radius at 346.1 m, no tilt, a feed ahead
and a boom and post back to the saucer). The bow name and hull number are outlined in black; the emblem is a picture mark. The emblem and the tower's name sit on the smooth tower flank aft of the forward hull and
the sponson (`EMBLEM_Z`), the emblem lit by a lamp on a bracket directly below it shining up (`flood_emblem`); a lamp on a post
at the front of the roof lights the bow's name (`flood_name_roof`, on the axis); the crown floods as before. Each flood's pool
is baked onto every hull part it reaches (`Flood.parts`).

### Fidelity (Q10)

Against `references/EA-Hyperion-V5c.stl` (Q58): silhouettes top 0.944, side 0.918, front 0.963; width and height within 1 %,
length 4.3 % over (the old STL's antenna rods reach past the V5c's bow); 31 per-part sections (`parts/ea_hyperion_fidelity.py`,
`test_ea_hyperion.py`) all at 0.926 or over, no exemptions.

### In the game

`assets/ships/ea_hyperion.tres`, catalogue `ea_hyperion` (class `destroyer`), 17 000 hull points (T03), reaction drive, opens its
own jump points. `capital spawn ea_hyperion` names it from the list (`EAS Hyperion`, `EAS Lexington`, ...).

Look sheet (gitignored): `references/screenshots/M10-T22 Hyperion/look_sheet_final.png` (`model_sheet.sh` shots and the in-game
broadside with the painted name and number, `in_game/broadside_name_number.png`).

### Open for the human tester `(H)`

- The look against the stills: light grey, band widths, the white hull number's outline in shadow.
- At the player's flank view the number is easily hidden by a Starfury; it reads best from the capital's own side.

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
| `narn_gquan` | T25 | G'Quan heavy cruiser | **1 400** (Q67) | none canon | 450 (B5W); 1 000 (the STL is modelled exactly 1 000 units long); "over 1 km" (unsourced) | y/x/z | 943 x 206 | yes | own (TBP: jump yes) | capital | **No published length.** B5W sizes it with the Primus (450 against 455 m); at the Primus's 1 586 m that is about 1 500 to 1 600 m. Launches 6 to 12 Frazi (B5W, Traveller) |
| `centauri_vorchan` | T26 | Vorchan warship | **360** | ITF (360 long, 475 beam, 305 draught) | | x/y/z | 465 x 300 | yes | gate (Q22: a small cruiser; TBP says it jumps) | capital | ITF's three dimensions match the STL within 3 %; the beam is wider than the length (two crossed crescents) |
| `centauri_primus` | T27 | Primus battlecruiser | **1 586** | ITF (1 586 x 1 023 x 455); FN | 455 (B5W) | y/x/z | 888 x 284 | yes | own | capital | ITF's beam and draught are 15 % and 60 % bigger than the STL's; the STL is flatter. **Launches none**: no fighter bays (OG; Q49). The mass-driver STL has the same box, so the driver sits inside the envelope |
| `minbari_sharlin` | T28 | Sharlin warcruiser | **1 600** | TBP; WPL (Mongoose, after Brandon Bray: 1 600 long, about 1 900 tall) | | x/y/z | 557 x 1 952 | rolled | own | capital | Taller than long: the STL's height-to-length (1.22) matches the 1 900/1 600 quote. Passes the mouth only on its side; it opens its own points anyway |
| `drazi_sunhawk` | T29 | Sunhawk | **197** | ITF and SotG (197 x 135 x 49) | 350 (FN; WPL, mass 280 kt): wrong (Q49) | x/y/z | 142 x 45 | yes | gate (no Drazi jump engine; SotG lists no hyperdrive) | capital | ITF's proportions match the STL (1 : 0.69 : 0.25 against 1 : 0.72 : 0.23). Can carry one Sky Serpent on a dorsal cradle (TBP, WPL) |
| `drazi_stormfalcon` | T30 | Stormfalcon | **820** | SotG (est.); FN | | x/y/z | 706 x 200 | yes | own (SotG hyperdrive) | capital | SotG complement: 12 Star Snake light fighters, 1 Sky Serpent, 2 shuttles |
| `brakiri_avioki` | T31 | Avioki cruiser | **1 000** (Q67) | SotG; TBP ("over a kilometre") | | x/y/z | 711 x 1 338 | yes | own (SotG, TBP) | capital | The STL's blade wing is taller (826 units) than the hull is long (632). **Launches none**: SotG lists 2 assault shuttles (Q49) |
| `vree_xill` | T32 | Xill | **500** (Q67) | SotG (est.) | 500 (a hidden, unsourced TBP note) | x (diameter)/y/z | 350 x 97 | yes | gate (Q22) | capital | OG: jump engine, 15 antimatter cannons, 1 500 troops |
| `isa_whitestar` | T33 | White Star | **266** (Q67) | TE 1.0, 1.3; TBP; WPL | | x/y/z | 222 x 78 | yes | own (its signature) | capital | Opening its own points is canon and iconic; an exception to Q22's "small ships use gates" |
| `isa_victory` | T34 | Victory destroyer | **2 990** (Q67) | episode dialogue ("a mile and a quarter", per WPL); Q49 | 2 990.31 (TE 1.0, as *Excalibur*; TBP; SotG): too big for a gate | x/y/z | 1 324 x 1 107 | yes | own (a destroyer) | capital | |
| `shadow_battlecrab` | T35 | Shadow battlecrab | **1 500** (the leg span, Q49) | SotG ("Shadow cruiser") | 1 000 (merzo.net chart); 1 to 2 km (h2g2); TBP: "variable" | span x / run y / z | run 641, height 310 | yes | shimmer (Q44) | capital + organic (T06) | The span is the STL's largest extent (148 units); the body's run is 63. Fighters: 6 (B5W) to 36 (SotG, Traveller) |
| `vorlon_destroyer` | T36 | Vorlon destroyer (Q49) | **131** | FN; TBP (the Vorlon transport, the same shape) | 925 (SotG "Vorlon Destroyer") | y/x/z (round) | 20 x 20 (body only) | yes | own | capital + organic | **Show images: the folder `references/show/m10/vorlon_heavy_cruiser/`** (named before Q49). Petals from its two petal STLs (stage 2). No source lists fighters |
| `drakh_carrier` | T37 | Drakh carrier | **7 000** (Q67; own jump points) | TE 1.0 (the Drakh cruiser, "essentially identical" in shape, TBP) | 14 000 (MD); "much larger than a cruiser" (TBP) | y/x/z | 1 021 x 504 | yes | **gate** (canon: no jump engine; it ran for a gate in "Lines of Communication") | capital | MD complement: 10 heavy or 40 light raiders, 40 shuttles |
| `drazi_firehawk` | T59 | Firehawk | **197** (Q49) | the Sunhawk's length: the STL is the Sunhawk's hull | 270 (SotG, est.); 350 (FN): wrong | x/y/z | 142 x 44 | yes | gate (Q22) | capital | SotG's Drazi "Firehawk Advanced Cruiser", a Mongoose design (not seen in the show) carrying a solar cannon. **Launches none** (Q49). Its STL has the Sunhawk's box to 1 % (the same hull, other weapons) |
| `vorlon_heavy_cruiser` | T60 | Vorlon heavy cruiser (Q49) | **1 528** | FN; ITF gave the heavy cruiser 1 330 | "over 1 300" (a B5 game, per WPL and TBP, for a "Star Dreadnought") | y/x/z | 461 x 302 | yes (ellipse 0.08) | own | capital + organic | The file says "Dreadnought"; it is the heavy cruiser (Q49). **Show images: the folder `references/show/m10/vorlon_dreadnought/`**, plus `vorlon_heavy_cruiser/Pasted image.png`. B5W: 6 Vorlon fighters, 2 shuttles |

### Fighters

| Id | Task | Craft | Length (m) | Sources | Alternatives | Axes L/W/H | Box W x H (m) | Flags |
|---|---|---|---|---|---|---|---|---|
| `narn_frazi` | T38 | Frazi | **16.8** (Q67) | TE 1.1; TBP; SotG | | y/x/z | 8.8 x 3.6 | |
| `centauri_sentri` | T38 | Sentri | **22.25** | TE 1.1; TBP | 22.26 (SotG) | x/y/z | 36.0 x 9.5 | Span wider than length; TE's drawing agrees (about 38 m) |
| `minbari_nial` | T39 | Nial | **22.23** | TE 1.1 ("Minbari Fighter"); TBP | | y/x/z | 7.7 x 7.9 | **"Liara"**: no such craft on TBP or the web (the nearest name is the *Liandra*, a 160 m Ranger ship); the file's three-armed fighter is the Nial |
| `drazi_sky_serpent` | T39 | Sky Serpent | **19.12** | TE 1.1 ("Drazi Fighter"); TBP; FN (19 m) | 15.3 (ITF); 30 (SotG, a two-seat variant) | y/x/z | 13.1 x 4.7 | |
| `brakiri_falkosi` | T40 | Falkosi | **15** | SotG (est.) | | y/x/z | 12.1 x 8.7 | The only figure |
| `drakh_fighter` | T40 | Drakh fighter | **215** (Q67; multi-crew, capital framework) | MD ("light raider", est.) | 76.2 (MD "heavy raider") | y/x/z | 9.1 x 8.6 | |
| `shadow_fighter` | T41 | Shadow fighter | **15.3** | ITF (via TBP); SotG | | x/y/z | 10.9 x 6.3 | |
| `shadow_scout` | T41 | Shadow scout | **356** (Q67) | FN | 350 (SotG) | x/y/z | 168 x 120 | A small capital ship: **capital framework with the battlecrab's organic parts** (Q49). Shimmers (Q44) |
| `vorlon_fighter` | T42 | Vorlon light fighter | **21.92** | TE 1.1; TBP | 25.5 (a B5 game, per WPL; SotG) | y/x/z | 15.9 x 15.9 (petals open) | TBP: Vorlon fighters seem to jump on their own (for T04) |
| `ea_thunderbolt` | T50 | Thunderbolt | **16.24** | TE 1.1 | 15.3 (TBP, SotG) | turned 42 degrees about file z, then 168 x 228 x 89 units | 22.0 x 8.6 (if the shorter in-plane extent is the length) | **The STL is not axis-aligned**: `refview --turn z=42` squares it up (M10-T50) |

All fighters: the fighter pipeline (the Starfury's); none opens a jump point (Q22).

### Big civilians and small craft

| Id | Task | Hull | Length (m) | Sources | Alternatives | Axes L/W/H | Box W x H (m) | Gate | Opens | Pipeline | Flags |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `ea_panama` | T51 | Panama transport | **121.6** (Q66: 20 m tall; T71) | none | | y/x/z | 30 x 20 | yes | gate | **civilian** (Q49) | "Panama" is not on TBP; the show images match TBP's "White Star" type commercial transport (no length, no jump engine). Two of the maintainer's stills seem to show it inside a docking bay: at 180 m its section just fits B5's main bay core (45.5 x 30 m); at 20 m tall (T71) it clears the bay's mouth by 6 m |
| `ea_explorer` | T52 | Explorer | **6 103** | SotG; WPL (citation needed); TBP ("over six kilometres") | | y/x/z | 846 x 2 526 (975 without the mast) | no (the mast), hull yes | own (builds gates) | capital | The long antenna mast is 2.5 km tall at this length |
| `ea_asimov` | T53 | Asimov liner | **600** | TBP (unsourced) | | y/x/z (sphere) | 347 x 347 | yes | gate (TBP: no jump engine) | capital | **One generator with T56** (Q49): the liner variant |
| `ea_construction_tender` | T55, T69 | Construction tender | **8** (Q65; T55 built it at 50, est.) | none | | y/x/z | 11.2 x 3.8 (truss span) | yes | gate | **civilian** (Q49) | No class of this name found; the still is a work pod by a construction frame. A tug with claws and a truss |
| `ea_mining_transport` | T56 | Mining transport | **632** closed, 716 open (Q50; the Asimov's sphere and scale) | none | | y/x/z | 330 x 330 | yes | gate | capital | **T53's generator, the mining variant** (Q49): the Asimov's sphere with cargo doors (closed 182, open 206 units long), doors moving (Q43); the show still in its folder (an orange-engined freighter) is a different ship |
| `ea_shuttle` | T57, T69 | EA shuttle | **38** (Q65; T57 built it at 18.64) | TE 1.1; TBP | 18 to 25 by variant (SotG) | y/x/z | 18.8 x 10.7 | | | civilian | |
| `ea_atmo_shuttle` | T57, T69 | EA atmospheric shuttle | **29** (Q65; T57 built it at 25.59) | TE 1.1; TBP ("Kestrel" class) | | y/x/z | 51.6 x 9.6 | | | civilian | Wingspan 1.8 times the length (TE's drawing: about 1.45) |
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

### Axis mappings and measurements (T01 stage 2)

The `refview` and `compare` mapping per hull (`--right --up --aft`), read off the renders in `reports/refs/<id>/`; the
bow is the end the shape and the show agree on (`docs/design-references.md`, "M10 hulls", says why for each). `--length`
is the approved length unless noted.

| Id | File | Mapping | Note |
|---|---|---|---|
| `ea_omega` | `EA Omega Destroyer.stl` | `+y +z +x` | the drum is turned about 40 degrees in the file |
| `ea_hyperion` | `EA Hyperion Class Heavy Cruiser.stl` | `+x +z -y` | |
| `ea_nova` | `EA_Nova_Dreadnought_(with_guns).stl` | `-x +z +y` | the older `EA Nova class destroyer.STL` has no guns |
| `ea_warlock` | `EA-Warlock_destroyer_1992m.stl` | `+x +z -y` | |
| `narn_gquan` | `Narn Gquon battlecruiser 1400m.stl` | `-x +z +y` | |
| `centauri_vorchan` | `Centauri Vorchan Cruiser 360m.stl` | `+y +z +x` | |
| `centauri_primus` | `Centauri_Primus_1586m.stl` | `-x +z +y` | bow at the twin barrels |
| `centauri_primus` (mass driver) | `Centauri_Primus_w_mass_driver.stl` | `+y +z +x` | the driver: ventral, 16 to 46 %, 253 m across its mounts, to y -115 |
| `minbari_sharlin` | `Minbari_Sharlin_cruiser_1600m.stl` | `+y +z +x` | |
| `drazi_sunhawk`, `drazi_firehawk` | `Drazi_Sunhawk_crusier_350m.stl`, `Drazi_Firehawk_350m.stl` | `+y +z +x` | one hull; the Firehawk's aft bulb is windowed |
| `drazi_stormfalcon` | `Drazi_Stormfalcon_cruiser_820m.stl` | `+y +z +x` | |
| `brakiri_avioki` | `Brakiri_Avioki_cruiser_1000m.stl` | `+y +z +x` | |
| `vree_xill` | `Vree_Xill_cruiser_500m.stl` | `+y +z +x` | a saucer: the bow is chosen |
| `isa_whitestar` | `ISA Whitestar 266m.stl` | `+y +z +x` | bow at the single point |
| `isa_victory` | `ISA Destroyer  2990m.stl` | `+y +z +x` | |
| `shadow_battlecrab` | `Shadow_Battlecrab_3_sizes.stl` | `+x +z -y` | `--length 640.6` (the body's run) gives the 1 500 m span |
| `vorlon_destroyer` | `Vorlon_Destroyer (missing pedals) - 131m.stl` | `+x +z -y` | petals below |
| `vorlon_heavy_cruiser` | `Vorlon Dreadnought - 1528m.stl` | `-x +z +y` | bow at the claws |
| `drakh_carrier` | `Drakh carrier 7km.STL` | `+x +z -y` | bow at the prongs |
| `narn_frazi` | `Narn_Fighter 16.8m.stl` | `-x +z +y` | bow at the gun barrels |
| `centauri_sentri` | `Centari_Sentri_Fighter.stl` | `+y +z +x` | |
| `minbari_nial` | `Minbari_Nial_22m.stl` | `+x +z -y` | |
| `drazi_sky_serpent` | `Drazi_Sky_serpant_fighter_19m.stl` | `+x +z -y` | |
| `brakiri_falkosi` | `Brakiri_Falkosi_fighter.STL` | `-x +z +y` | |
| `drakh_fighter` | `Drakh_Fighter_215m.stl` | `-x +z +y` | |
| `shadow_fighter` | `Shadow_advanced_fighter_15.3m.stl` | `+y +z +x` | |
| `shadow_scout` | `Shadow_Scout_fighter_356m.stl` | `+y +z +x` | |
| `vorlon_fighter` | `Vorlon_Light_Fighter (pedals open).stl` | `+x +z -y` | |
| `ea_thunderbolt` | `EA_Thunderbolt_fighter.stl` | turn +42 degrees about file z, then `-x +z +y` | `--turn z=42` (M10-T50) |
| `ea_panama`, `ea_explorer`, `ea_construction_tender`, `ea_shuttle`, `ea_atmo_shuttle` | (their files) | `-x +z +y` | the Explorer's bow is the end with the dome and the launch bay (Q50) |
| `ea_asimov`, `ea_mining_transport` | `EA Asimov liner 600m.stl`, `EA_Mining_Transport_600m.stl`, `..._doors_open.stl` | `-x +z +y` | one scale (3.47 m a unit): the liner 600 m, the mining transport 632 m closed and 716 m open (`--length 632.4` and `716.3`) |
| `centauri_shuttle`, `minbari_flyer` | (their files) | `+y +z +x` | |

**Vorlon destroyer's petals (Q10).** Both petal STLs are single petals at the body's scale (0.18 m a unit), laid out as
print pieces (not in place). Closed: 56 m long, a curled shell of 17.8 m chord and 6.9 m depth (radius about 9.2 m against
the head's 9.8 m), so it wraps the head from the bow to about 43 %, its hinge stub aft. Open: 32 m wide and 46 m long,
standing about 50 degrees out from the axis, tip forward; four make a flower about 90 m across. The petal changes shape
between the states (curled to flat), so the generator morphs it as well as turning it. Four petals per the show; three
would close edge to edge.

**Mining transport doors (Q43).** The two STLs are one mesh moved: the sphere parts across its middle and the halves
slide apart 24.2 units (84 m at the liner's scale), the hold crossed by posts. One rigid moving part, two states.

**Launches settled (Q50).** The White Star launches 4 Nials; the Victory Starfuries, Thunderbolts and Kestrel shuttles.

## Weapons and loadouts (T03)

M10-T03 (weapons and balance concept), settled by the maintainer on 2026-11-21 (Q53). The data is
`data/capitals/loadouts.json`: every weapon's kind and numbers, and every hull's class, hull points, weapon counts,
interceptors, launches, in-battle mines and jump mode (`tools/procgen/tests/test_capital_loadouts.py` keeps it whole).
A hull task builds its manifest's `hardpoints.weapons[]` (`{name, position, up, forward, arc, weapon, section}`) to
these counts and adds its own check of the manifest against them. T12 to T15 turn each weapon into a `WeaponSpec` in
`assets/weapons/<id>.tres`. These are starting numbers: T16 tunes damage and hull points until the balance fights below
pass, and the fights are the contract. Where this section and `docs/design-references.md`'s source counts differ (for
example Omega launches), this section wins.

### The scale (Q53)

- **No armour anywhere.** Every hit takes its full damage. Fighter numbers are unchanged from M5 (Starfury 300 hull,
  10 dmg every 0.25 s; raider 60, 6 every 0.4 s).
- **Anchor: an unescorted Omega (interceptors and guns working, no fighters launched) lasts 10 to 15 minutes against 12
  Starfuries, and the squadron loses about half.**
  - A Starfury's capacitor (100, 14 a shot, +25/s) caps it at 1.79 shots/s, about 17.9 dps sustained.
  - Twelve Starfuries give about 215 dps nominal. That falls to about 36 dps on the hull after 50 % time on target,
    90 % hits, 75 % of the squadron alive on average, and half the bolts taken by the 8 interceptor batteries.
  - So the **Omega has 30 000 hull points** (about 14 minutes).
  - Hundreds of thousands of points cannot fit the anchor. Even if every bolt hit, nothing was intercepted and no
    Starfury died, 12 Starfuries deal at most about 161 000 in 12.5 minutes.
- **Capital weapons** are set so equal capitals take 4 to 8 minutes.
  - An Omega's anti-capital mounts total 187 dps nominal.
  - At about 65 % of mounts bearing, with about 40 % of its bolts taken by the other's interceptors, it lands about
    88 dps on another Omega: about 5.7 minutes.
  - Anti-capital damage is about a sixth of the draft's armoured numbers. Anti-fighter guns stay at fighter scale (the
    light gun is M5's civilian turret, 6 dmg every 2.4 s).
- **The ladder** is hull points times nominal dps against the Omega's 5.6 M:
  - younger-race capitals within about 1.5x (G'Quan and Primus about 0.7x, Nova about 1.35x);
  - Minbari and ISA about 2x (Sharlin 1.9x; the Victory, a dreadnought, 3.2x);
  - ancients 4x or more, placeholders until T04.
- **Tuning dials for T16,** in this order: interceptor reach and rate, the anti-fighter guns' spread and traverse, hull
  points per hull, anti-capital damage per faction.

### Kinds and base numbers

| Kind | Damage | Cycle | Speed m/s | Range m | Spread, traverse | Role |
|---|---|---|---|---|---|---|
| `bolt_light` | 6 | 2.4 s | 1 500 | 3 000 | 0.3 deg, 60/50 deg/s | anti-fighter; ranks fighters first (§20.3) |
| `bolt_medium` | 12 | 2.0 s | 1 800 | 4 000 | 0.2 deg, 25/20 deg/s | dual role, nearer first |
| `bolt_heavy` | 3 x 40 | burst 0.35 s, cycle 10 s | 2 000 | 6 000 | 0.1 deg, 8/6 deg/s | anti-capital; ranks capitals first |
| `bolt_fixed` | 100 | 6 s | 2 500 | 7 000 | gimbal +/-8 deg at 2 deg/s | bow gun the ship points |
| `beam_pulsed` | 100 | 8 s | instant | 8 000 | 4 deg/s | one tick, first hull on the line |
| `beam_sustained` | 40 dps while on | 3 s on, 12 s cycle | instant | 7 000 | 3 deg/s sweep | each tick to the first hull under the line |
| `missile` | 40 + blast | reload 12 s | 350 | 6 000 lock | PN gain 4, 0.6 rad/s, 20 s | M4's guidance; toughness 1 |
| `torpedo` | 150 + blast | reload 20 s | 250 | 10 000 | 0.15 rad/s, 40 s | capitals only; toughness 3 |
| `interceptor` | 0 | 4 pulses/s (4 barrels, 1 s recharge) | 2 000 | 1 500 reach | 0.22 deg, 360 deg/s | the grid battery (§20.3) |

**Traits:** `kinetic` (an interceptor needs 2 pulses to stop it); `push` was dropped with the push beams (Q56). **Toughness**
is how many interceptor pulses stop a shot: 1 for fighter and medium bolts and for missiles; 2 for heavy, fixed and
kinetic bolts; 3 for torpedoes and Narn energy mines. Interceptors never stop beams, blasts or rams.

### Faction weapons (show names)

The numbers are in `loadouts.json` under `weapons`.

| Faction | Ids (kind): show name |
|---|---|
| EA | `ea_sweep_beam` (beam_sustained): the Omega's particle beams (TBP: laser batteries), sweeping. `ea_particle_cannon` (beam_pulsed): phased particle cannon; `_heavy` 150 dmg, bow +/-10 deg (the Warlock's particle beam cannons). `ea_particle_array` (2 x 50): the Explorer's twin particle beam arrays. `ea_plasma_heavy` (bolt_heavy): heavy plasma pulse cannon. `ea_plasma_medium` (bolt_medium, 18): medium plasma or twin plasma cannon. `ea_pulse_cannon_fixed` (bolt_fixed, 2 x 15 / 2 s, no traverse): the Nova's fixed pulse cannon pods (Q71). `ea_pulse_cannon_swivel` (bolt_medium, 2 x 11.25 / 2 s): its two hangar pods on swivel rings (M10-T14). `ea_pulse_medium` (bolt_medium): pulse cannon. `ea_pulse_light` (bolt_light): pulse discharge cannon. `ea_railgun` (bolt_medium 20, 3 s, 4 000 m/s, kinetic). `ea_missile`, `ea_torpedo` (tubes and silos), `ea_interceptor`, `ea_interceptor_pod` (2 barrels: the Nova's swivelling pods, Q71), `ea_mine` (scenario only) |
| Narn | `narn_heavy_laser` (beam_sustained 117 dps, 4 s on, 12 s, fore arc), `narn_twin_particle` (bolt_medium 2 x 8), `narn_light_pulse`, `narn_energy_mine`, `narn_mine` |
| Centauri | `centauri_plasma_accelerator` (bolt_fixed, 2 barrels), `centauri_battle_laser` (Primus heavy X-ray laser; beam_sustained 67 dps, 3 s on, 10 s), `centauri_ion_cannon` (bolt_medium 2 x 8 / 1.8 s; not kinetic), `centauri_light_particle` (bolt_light 2 x 6), `centauri_missile`, `centauri_guided_mine`, `centauri_mine` |
| Minbari | `minbari_neutron_cannon` (beam_pulsed 150, 9 km), `minbari_fusion_cannon` (bolt_medium 8 / 1.4 s, 2 500 m/s, 40 deg/s), `minbari_em_pulse` (beam_pulsed 50, mounts only; T04 may change it) |
| Drazi | `drazi_particle_beam` (beam_pulsed 80, nose +/-15 deg), `drazi_plasma_medium` (13), `drazi_heavy_particle` (2 x 35 / 8 s), `drazi_solar_cannon` (beam_sustained 150 dps, 3 s on, 25 s, bow +/-5 deg), `drazi_missile`, `drazi_interceptor` (half rate), `drazi_mine` |
| Brakiri | Pulse lasers and interceptor lasers only (Q56, no push beams): `brakiri_pulse_laser_heavy` (bolt_heavy 3 x 41 / 10 s, fore 90 deg; takes the graviton beams' 49 dps), `brakiri_pulse_laser` (bolt_medium 4 / 0.6 s; was the graviton pulsar), `brakiri_interceptor`, `brakiri_mine` |
| Vree | `vree_antimatter` (bolt_heavy single 30 / 4 s, 3 km, belly hemisphere) |
| ISA | `isa_neutron_laser` (the White Star's main gun; beam_pulsed 200 / 6 s, bow), `isa_neutron_cannon` (67 / 5 s, 120 deg), `isa_fusion_cannon` (2 x 8 / 1 s), `isa_fusion_beam` (Victory; beam_sustained 250 dps, 5 s on, 45 s, fore +/-15 deg), `isa_array`, `isa_pulse_light`, `isa_interceptor` |
| Drakh | `drakh_pulse` (8 / 1.8 s), `drakh_beam` (beam_pulsed 100), `drakh_light` |
| Ancients (T04 placeholders) | `ancient_slicer` (875 dps, 4 s on, 10 s), `ancient_slicer_small` (220), `ancient_lance` (2 500 / 8 s, 12 km), `ancient_lance_small` (1 250) |

### Hull loadouts

Arcs: **T** a turret (200 deg cone round its up), **F** a fore 90 deg cone, **X** fixed to the bow (gimbal only), **B**
a broadside, **A** aft, **V** the belly hemisphere. The dps column is nominal anti-capital output, every mount bearing,
excluding interceptors.

| Hull | Class | Hull pts | Weapons | Intercep. | Launches | Mines | dps |
|---|---|---|---|---|---|---|---|
| Omega T21 | capital | 30 000 | 4 plasma_heavy T; 6 sweep_beam (2 F, 4 A hemispheres); 12 pulse_medium T; 2 missile | 8 | 32 Starfuries | scenario only | 187 |
| Hyperion T22 | capital | 17 000 | 2 plasma_heavy X; 2 plasma_medium T; 2 particle_cannon F/B; 4 pulse_light T; 2 torpedo F | 4 | 6 Starfuries, 2 shuttles | | 92 |
| Nova T23 | dreadnought | 36 000 | 12 pulse_cannon_fixed (8 F, 4 A; Q71, no beams), 2 pulse_cannon_swivel (the hangar pods, M10-T14) | 4 pods | 24 Starfuries | | 210 |
| Warlock T24 | dreadnought | 45 000 | 2 particle_cannon_heavy X; 12 torpedo silos (salvos of 4); 8 plasma_medium T; 6 railgun T; 6 pulse_light T | 8 | 12 Starfuries (Thunderbolts after M11) | | 254 |
| G'Quan T25 | capital | 30 000 | 2 heavy_laser F; 2 twin_particle T; 6 light_pulse T; 2 energy_mine F | | 12 Frazi | energy | 134 |
| Vorchan T26 | cruiser | 7 000 | 2 plasma_accelerator X; 4 light_particle T; 2 missile; 1 guided_mine | | | guided | 108 |
| Primus T27 | capital | 30 000 | 4 battle_laser F/B; 4 ion_cannon T; 4 light_particle T | | | | 138 |
| Sharlin T28 | capital | 58 000 | 6 neutron_cannon F/B; 12 fusion_cannon T; 1 em_pulse X | | 15 Nial | | 187 |
| Sunhawk T29 | cruiser | 4 000 | 1 particle_beam X; 4 plasma_medium F; 2 missile | | | | 43 |
| Firehawk T59 | cruiser | 4 500 | 1 solar_cannon X; 2 twin heavy_particle F | | | | 36 |
| Stormfalcon T30 | capital | 16 000 | 2 solar_cannon X; 6 heavy_particle T; 4 plasma_medium T | 4 (half rate) | 13 Sky Serpents (1 + 12 for the Star Snakes) | | 114 |
| Avioki T31 | capital | 19 000 | 4 pulse_laser_heavy F; 6 pulse_laser T (Q56) | 4 | | | 89 |
| Xill T32 | cruiser | 6 000 | 15 antimatter V (strafing) | | | | 112 |
| White Star T33 | cruiser | 8 000 | 1 neutron_laser X; 2 neutron_cannon F; 2 fusion_cannon T | | 4 Nial | | 92 |
| Victory T34 | dreadnought | 75 000 | 2 fusion_beam F; 12 array T; 16 pulse_light T | 10 | 12 Starfuries (Thunderbolts after M11), 2 Kestrel | | 240 |
| Battlecrab T35 | capital | 120 000 * | 1 slicer F (belly front) | | 6 Shadow fighters | | 350 * |
| Shadow scout T41 | cruiser | 20 000 * | 1 slicer_small | | | | 88 * |
| Vorlon destroyer T36 | cruiser | 25 000 * | 1 lance_small | | | | 156 * |
| Vorlon heavy cruiser T60 | capital | 120 000 * | 1 lance (claws) | | 6 Vorlon fighters | | 312 * |
| Drakh carrier T37 | dreadnought | 50 000 | 6 beam F/B; 12 pulse T; 8 light T | | 24 Drakh fighters | | 148 |
| Explorer T52 | dreadnought | 60 000 | 4 pulse_medium T; 4 particle_array T | 4 | 24 Starfuries | | 74 |
| Asimov T53, mining transport T56 | capital | 9 000 | unarmed | | | | 0 |
| Strike carrier T19, test cruiser T07 | cruiser | 10 000, 20 000 | unarmed (as built) | | 6 Delta-Vs / none | | 0 |

\* T04 placeholders. Unarmed civilians (Q53): the Panama 185 (T71: by volume at 20 m tall), the construction tender 50 (T69: 8 m long), the Centauri shuttle 250 and the
Minbari Flyer 300 hull points; the EA shuttles as built.

**Fighters** (flight numbers are the hull tasks'):

| Fighter | Hull | Gun (damage / interval) |
|---|---|---|
| Thunderbolt T50 | 360 | Starfury nose gun + pod cannon 16 / 1.0 + missile (M11 flies it) |
| Frazi T38 | 320 | 12 / 0.3 |
| Sentri T38 | 240 | 8 / 0.25 |
| Nial T39 | 380 | 14 / 0.3 |
| Sky Serpent T39 | 300 | 11 / 0.3 |
| Falkosi T40 | 180 | 7 / 0.2 |
| Drakh fighter T40 | 280 | 10 / 0.25 |
| Shadow fighter T41 | 400 | beam 60 dps, 2 s on in 4 (T04) |
| Vorlon fighter T42 | 400 | lance 120 / 3 s (T04) |

### Re-balance (Q54)

The maintainer's 2026-11-21 judgement on the ladder above: `damage_scale` in `loadouts.json` multiplies every anti-capital
weapon of the hull; hull points are unchanged. Power is hull points x anti-capital dps, the Omega = 1; "even" is the
square law (N ships even with M Omegas when N = M / sqrt(power)), the form T16 writes the bars in.

| Hull | damage_scale | dps | Power | Even fight |
|---|---|---|---|---|
| Shadow battlecrab (T04 placeholder) | 1.60 | 560 | 12 | 1 ~ 3.5 Omegas |
| Vorlon heavy cruiser (T04 placeholder) | 1.80 | 560 | 12 | 1 ~ 3.5 Omegas |
| ISA Victory | 1.56 | 375 | 5.0 | 1 ~ 2.2 Omegas |
| EA Warlock | 1.48 | 375 | 3.0 | 1 ~ 1.7 Omegas |
| Minbari Sharlin | 1.55 | 290 | 3.0 | 1 ~ 1.7 Omegas (beats 1, sometimes 2, never 3) |
| Drakh carrier | 1.52 | 225 | 2.0 | 1 ~ 1.4 Omegas |
| Vorlon destroyer (T04 placeholder) | 1.73 | 270 | 1.2 | 1 ~ 1 Omega |
| Shadow scout (T04 placeholder) | 1.93 | 170 | 0.6 | 4 ~ 3 Omegas |
| Narn G'Quan | 0.71 | 95 | 0.5 | 3 ~ 2 Omegas |
| ISA White Star | 2.28 | 210 | 0.3 | 2 ~ 1 Omega |
| EA Explorer | 0.38 | 28 | 0.3 | 2 ~ 1 Omega (mostly hull) |
| EA Hyperion | 0.71 | 65 | 0.2 | 2 to 3 ~ 1 Omega |

Unchanged: Omega 1.0, Nova 1.35, Primus 0.74, Stormfalcon 0.33, Avioki 0.30, Vorchan 0.13, Xill 0.12, Sunhawk and Firehawk
0.03 (6 ~ 1 Omega). Launched fighters are not in the power figure.

### Sections, mounts and blasts

**Section shares** (a template; a hull task may move up to 0.05 between rows):

| Section | Warship | Carrier | Civilian |
|---|---|---|---|
| reactor | 0.14 | 0.14 | 0.12 |
| magazine | 0.10 (0 with no missiles, torpedoes or mines) | 0.08 | 0 |
| fuel | 0.08 (reaction drives only) | 0.08 | 0.12 |
| bridge | 0.05 | 0.05 | 0.06 |
| hangar | 0.06 a bay | 0.20 in total | 0 |
| engine | 0.15 in total | 0.15 | 0.15 |
| structure | the rest | the rest | the rest |

Habitat sections take their share as built.

**Mount hit points** (no armour): light 300, medium 800, heavy or fixed 2 000, beam emitter 2 500, launcher or silo
1 200, interceptor battery 400.

**Blasts** (D12.6). `f(d) = (1 - (d/R)^2)^2`, with `d` measured to the nearest hit volume. The damage `D0 x f(d)` goes to
the nearest section. The push is `dv = I0 x f(d) x A / m`, where `A` is the mean face area of the target's box, capped at
50 m/s. A blast's energy, read by the flashes, is `5e6 J x D0`; T09 fits the flash constant so the Starfury's flash keeps
its size today.

| Source | D0 | R m | I0 N s/m^2 |
|---|---|---|---|
| raider death | 40 | 80 | 1 500 |
| Starfury-class death (heavy fighters x1.3) | 60 | 100 | 2 000 |
| shuttle or small craft | 100 | 150 | 2 500 |
| Saturn-class civilian | 400 | 300 | 3 000 |
| missile / torpedo (on top of the impact) | 20 / 100 | 20 / 60 | 500 / 1 500 |
| proximity mine / Narn energy mine / Centauri guided mine | 300 / 250 / 400 | 120 / 300 / 60 | 2 000 / 4 000 / 1 500 |
| cruiser: magazine / fuel / reactor | 900 / 600 / 1 800 | 400 / 500 / 1 000 | 6 000 |
| capital: magazine / fuel / reactor | 1 800 / 1 200 / 4 500 | 600 / 800 / 2 500 | 1e4 |
| dreadnought: magazine / fuel / reactor | 2 400 / 1 800 / 7 500 | 800 / 1 000 / 3 500 | 1.2e4 |
| ancients | T04 (placeholder 9 000 / 3 000 m) | | |

Three checks on the table:
- A Starfury's death takes 11 % from a wingman 50 m away.
- A capital's reactor kills fighters within about 2 km.
- The same reactor takes 14 % from a capital 500 m away.

The capital rows were scaled to the new hull points (x0.3) to keep the draft's proportions.

### Mines (Q20, Q53)

| Kind | Laid by | Behaviour | Trigger | On radar |
|---|---|---|---|---|
| `mine_prox` | scenario and mission minefields, every faction but the ancients (the Omega's mines too) | static row (§17.16), M7-T64's touch, shot and chain rules | 60 m from the hull's surface, hostile only | hostile within 1 000 m; own and friendly always |
| `mine_energy` | G'Quan, 2 launchers, 1 a 20 s each, at capitals 4 to 12 km away | flies at 900 m/s to the lead point, arms there, goes off on a hostile capital within 200 m or 5 s after arriving | 200 m, capitals only | as a missile while flying |
| `mine_guided` | Vorchan, while a hostile is astern within 3 km: 4 every 30 s, at most 12 in play | dormant for 60 s, homes at 150 m/s on a hostile within 800 m | 30 m | hostile within 1 000 m |

### Jump points (Q22, Q49)

Unchanged from Q49's list:
- **Own point:** Omega, Hyperion, Nova, Warlock, G'Quan, Primus, Sharlin, Stormfalcon, Avioki, White Star, Victory, both
  Vorlons (subject to T04) and the Explorer.
- **Gate or another ship's point:** Vorchan, Sunhawk, Firehawk, Xill, the Drakh carrier and every civilian.
- **Shimmer:** the battlecrab and the Shadow scout.
- **Never:** fighters.

Recharge by `capitals.json` category:
- cruiser 60 s: the White Star, the Vorlon destroyer;
- destroyer 90 s: the Omega, Hyperion, G'Quan, Primus, Sharlin, Stormfalcon, Avioki, the Vorlon heavy cruiser;
- carrier 120 s: the Nova, Warlock, Victory, Explorer.

### Balance fights (D14)

Each fight is seeded and headless through the native core, run at 8x like the station grid test, behind `GUT_BALANCE`
(`tests/balance_suite.txt`). Seeds: 3, or 5 for even fights. Each fight takes under 3 minutes of wall time. Times are
sim time.

| # | Fight | Bar |
|---|---|---|
| B1 | Omega vs Omega | either may win; 240 to 480 s; the winner at 60 % hull or less |
| B2 | Omega vs G'Quan | the Omega wins at least 3 of 5; 200 to 480 s |
| B3 | Primus vs G'Quan | the Primus wins at least 3 of 5; 240 to 540 s |
| B4 | Sharlin vs 1 / 2 / 3 Omegas | wins every seed (240 to 480 s) / wins at least 1 of 5 / never |
| B5 | White Star vs 1 / 2 Vorchans | wins every seed (60 to 240 s) / wins at least 1 of 5 |
| B6 | Victory vs Sharlin | the Victory wins at least 4 of 5; 240 to 480 s |
| B7 | Vorchan vs Sunhawk | the Vorchan wins at least 4 of 5; 45 to 150 s |
| B8 | 12 Starfuries vs a Vorchan | the squadron wins in 70 to 180 s, losing 1 to 4 |
| B9 | 12 Starfuries vs a Sunhawk | the squadron wins in 40 to 120 s, losing 2 or fewer |
| B10 | 12 Starfuries vs an Omega, none launched, the squadron ordered to press (no abort) | the Omega is destroyed in 600 to 900 s; the squadron loses 4 to 8 |
| B11 | 12 Starfuries vs a Sharlin | the squadron aborts after losing 6 within 10 min; the Sharlin keeps 40 % hull or more |
| B12 | strike carrier + 6 Delta-Vs vs a Hyperion with its 6 Starfuries guarding 2 Saturns | the raid fails in at least 2 of 3 (1 Saturn lost or none) and the carrier jumps out |
| B13 | 2 strike carriers vs an Omega | the carriers withdraw within 180 s; the Omega keeps 95 % or more |
| B14 | EA (Omega, Hyperion, 12 Starfuries) vs Centauri (Primus, 2 Vorchans, 8 Sentri) | each side wins at least 1 of 5; 6 to 12 min |
| B15 | battlecrab vs 3 Omegas (until T04) | the battlecrab wins at least 4 of 5; 180 to 480 s |
| B16 | Nova vs Omega | the Nova wins at least 3 of 5; 240 to 540 s |
| F1 | 4 Starfuries vs 4 of each new younger-race fighter | the Starfuries win 30 to 70 % over 10 seeds; against the Nial, the Nial wins 60 to 85 % |
