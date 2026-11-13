# tools/procgen

Procedural asset generators for space-combat-sim. Every generated asset comes from code in this package
(design: `docs/architecture.md` section 9 and 14.8). Output goes to `assets/generated/` and is never committed.

Requirements: Python 3.11+ and NumPy. The PNGs are written by `core/image.py` (zlib alone).

## Running

```
scripts/gen_assets.sh                           # python3 -m tools.procgen build all, a few assets at a time
python3 -m tools.procgen list                   # registered asset ids, one per line, sorted
python3 -m tools.procgen build sky_default      # one or more ids
python3 -m tools.procgen build all --seed 7 --out /tmp/assets --jobs 4
python3 -m tools.procgen build starfury_aurora --option render_triangles=20000
python3 -m unittest discover -s tools/procgen/tests -t . -v
```

- `--seed N` (default 42, must be >= 0): the same seed always produces byte-identical files.
- `--out DIR` (default `<repo>/assets/generated`): output root; each asset writes into `DIR/<asset_id>/`.
- `--jobs N` (default 1): build up to N assets at once in worker processes (M4-T30d); the output is the same either way.
- `--option KEY=VALUE` (repeatable, JSON values): any `BuildContext.options` entry, e.g. `render_triangles=20000`, `atlas_px=4096`,
  `spacing=0.05` (the surface samples' spacing). Assets ignore options they do not know.
- `build all` builds every registered asset in sorted order. If `all` appears among other ids it wins.
- Exit codes: 0 ok, 1 an asset failed to build (the others still build), 2 usage error (unknown id, bad seed).
- Warnings are printed to stderr as `warning: ...`.

## Layout

```
core/context.py    BuildContext (out_dir, seed, options, rng) and AssetOutputs (what build() returns)
core/color.py      blackbody star colours, sRGB transfer
core/manifest.py   manifest.json builder/validator/writer, the mesh section's validation
core/geometry.py   Mesh + Material, primitives (box, tapered box, lathe, loft, superellipse, ellipsoid cap), with UVs
core/sampling.py   mesh -> surface samples (area-weighted, stratified, R2 low-discrepancy): centring, chunks, bakes
core/obj.py        OBJ/MTL writer and a small reader for tests
core/glb.py        binary glTF writer (and a reader for tests): positions, normals, one UV set, a material a primitive
core/uv_atlas.py   charts (the primitives' own UVs or the unwrapper's regions) and the shelf packer (M4-T30a)
core/raster.py     atlas buffers: world position, normal, part, material, chart and sharp-edge distance per texel
core/textures.py   the texture maps: paint, markings (bands, a stroke font, decals, soot, windows), wear, grooves, occlusion, emissive
core/image.py      8-bit PNG writer and reader with zlib alone
core/textured_mesh.py  write_textured_mesh: the textured glb, its four maps with .import sidecars, the manifest's mesh section
core/livery.py     the Starfury's wing liveries: zones, patterns, number fields, the digit atlas (M4-T30b)
core/chunks.py     break-up chunks: the parts grouped per chunk, placed at their samples' centroid, one OBJ each
core/pieces.py     big stand-in pieces (the station, the capital hulls): a textured mesh and its bounds each
core/panorama.py   equirectangular sky panoramas: soft blobs composited onto the sphere (M4-T30c)
core/rotations.py  quaternions and rotation matrices for the sky's nebula
parts/             reusable parametric parts: hull (fuselage, canopy, cockpit interior/tub,
                   upright cylinder hull with painted bands, faceted wedge fuselage with a framed
                   cockpit window and its first-person frame mesh), propulsion (nozzle, RCS cone,
                   engine pod, ring-faced pod, claw vane cluster with RCS blocks, pilot_tags),
                   structure (strut, trussed strut with ladder webs and painted bands, block,
                   panel, mast), weapons (gun barrel, twin gun mount), wing (delta wing,
                   vent grille); hull also has the raider's hump and canopy panel, propulsion
                   its nacelle drum.
                   Spec dataclass + Style in, Part out (mesh, named anchors, collision primitives,
                   mass)
styles/            design languages: Style (material roles, panel, wear and marking parameters); earthforce.py, raider.py
core/civilian.py   the civilian ships' shared pipeline (M5-T22, textured from M5-T27): Piece, mirroring with twins, the
                   visible surface (sampling with burial) for the body origin and the chunks, write_hull (the textured
                   hull, its OBJ and chunk cuts), write_model (a turret or a cargo pod), at_texel (a style's texture pack
                   scaled to the hull's texel)
parts/saturn.py    the Saturn family (M5-T12): lead ship, frames, drum frame, engine section, banded cylinders and
                   tanks, transport pods with recessed ribbed ends and rails, arms, junctions, turret pads; each
                   piece carries a burial volume and a side (centre line or right, mirrored)
parts/turret.py    defensive turret model (base, dome, twin barrels) at any size, and write_turret (its textured mesh)
parts/solids.py    burial volumes (box, lathe, prism, capsule, union, difference) that drop hidden surface samples
styles/ea_civilian.py the Earth Alliance civilian palette and texture pack; ea_civilian(overrides, engine_glow) repaints
                   roles per hull
parts/centauri.py  the Centauri Brezebel (M5-T15): the elliptic lens hull (bow, arms), engine bay, dorsal fitting,
                   fairings, hooked tip fins and the Centauri turret, each with its burial solid
parts/skylark.py   the Skylark transport (M5-T13): capsule with nose vanes, bridge and belly fins, spine vane rings,
                   collar, side tanks, the faceted body with corner fins, dorsal fin, centre engine and the turret's
                   seat on its ridge, nacelles with pods, ribbed rings, forked claws and their pylons; burial solids and sides
styles/centauri.py the Centauri palette (violet, gold, lavender trim) and texture pack (polished paint)
parts/brakiri.py   the Brakiri Bokmai (M5-T22): bow blade lofted up through measured sections, flank insets, windows,
                   spine, keel web, swept arms and fork struts, posts, engine lofts with cups and domes, fins, spindle;
                   the cargo pod model and the Brakiri turret
styles/brakiri.py  the Brakiri palette (olive frame, pale pods with their own grid, yellow) and texture pack, BOLT_SRGB,
                   GLOW_SRGB
assets/__init__.py registry: ASSETS: dict[str, Callable[[BuildContext], AssetOutputs]]
assets/<id>.py     one module per asset, exposing build(ctx)
tests/             unittest: core, parts, CLI, and every asset
```

## Conventions every generator follows

- **Deterministic.** Take randomness only from `ctx.rng()` (that is `numpy.random.default_rng(ctx.seed)`) or a
  named, independent sub-stream `ctx.rng("stars")`. No wall clock, no environment, no timestamps in outputs.
- **Godot frame.** Author in metres with +X right, +Y up, -Z forward. A hull is re-centred on the centroid of its surface
  samples; meshes, maps and hardpoints share that frame.
- **The textured mesh.** Hulls are written with `core.textured_mesh.write_textured_mesh`: one `.glb` (primitive 0 the opaque
  hull, primitive 1 the glass), the albedo, normal, ORM and emissive maps, a Godot `.import` sidecar beside each map, and the
  manifest's `mesh` section (the contract M5 builds against: `docs/milestones/m4-performance-and-scale.md`).
- **Manifest.** Always write `manifest.json` last with `core.manifest.build_manifest` + `write_manifest`: `aabb_min/max` bound
  the hull mesh in the Godot frame, `centroid_offset` is the Godot-frame vector subtracted by the re-centring, and the textured
  mesh goes under `mesh` through `extra=`. `build()` returns an `AssetOutputs` listing every file it wrote and any warnings; the
  CLI checks that the manifest exists and is valid.

## Adding an asset

1. Create `tools/procgen/assets/my_asset.py` with `build(ctx: BuildContext) -> AssetOutputs`. Write into
   `ctx.out_dir` (the CLI has created it), put tunables in module constants or `ctx.option("name", default)`, and
   finish with `write_manifest`.
2. Register it in `tools/procgen/assets/__init__.py`: `ASSETS["my_asset"] = my_asset.build`.
3. Add `tests/test_my_asset.py`: the files it writes, the manifest's `mesh` section, the frame and bounds, and same seed gives
   the same SHA-256 (see `test_nav_buoy.py` for a template).
4. Run the tests and `scripts/gen_assets.sh`. Third-party dependencies need an entry in `docs/third-party.md`.

## `nav_buoy`

The inert navigation buoy the M1 targeting cycles through (architecture section 9.3): an upright cylinder hull
(2.4 m barrel, 0.8 m across, two orange hazard stripes), two dark panel wings standing in the X/Y plane, an antenna
mast on top and a stub below, an amber lens under the beacon, about 4.4 m tall, `earthforce` style. Outputs the textured
`nav_buoy.glb` and its maps, `nav_buoy.obj/.mtl`, `hardpoints.json` and `manifest.json`. Option: `spacing`.

Things the Godot side must know:

- One frame for everything: the samples' centroid is the origin and lies on the long axis (every part is sampled
  exactly mirror-symmetric in x and z), so the buoy spins about its node's +Y without wobbling. `hardpoints.json`
  has `spin_axis` `[0, 1, 0]`.
- `hardpoints.json` `beacon` is `{"position", "radius"}`: the mast tip, where the game puts its emissive beacon mesh
  (the textured mesh holds only the lens; the beacon breathes). `collision` holds one capsule for later; M1 buoys have none.

## `starfury_aurora`

The player's SA-23E-style Starfury, composed from `parts/` with the `earthforce` style. Outputs the textured
`starfury_aurora.glb` with its maps and digit atlas, `starfury_aurora.obj/.mtl` (the hull the cockpit view draws from inside),
`cockpit_interior.obj/.mtl`, `hardpoints.json`, `manifest.json` and five break-up chunks
(`starfury_aurora_chunk_<cabin|arm_ur|arm_lr|arm_ul|arm_ll>.glb/.obj/.mtl`), each placed at its parts' samples' centroid and cut
from the hull's textured mesh on the hull's UVs. The full description and the hardpoints schema are in `docs/assets-starfury.md`.

Things the Godot side must know:

- All outputs share one frame: the centred Godot body frame (the samples' centroid = origin, within float32).
  `manifest.centroid_offset` only documents how far the authoring frame was shifted; nothing needs it.
- `hardpoints.json` is the contract for the flight model, cameras, weapons and collision (schema in the docs
  page); `center_of_mass` is on the thrust axis by design.
- The window panes are the glass surface (`ef_canopy_glass` in the OBJ); their dark red cabin glow is the glass shader's.
  `(H)`: judge the look in both cameras.
- `render_triangles` rebuilds the round parts coarser with the fine hull baked into the normal map (M4-T30b); the default draws
  the full hull.

## `raider_fighter`

The raiders' Delta-V flying wing (docs/assets-raider.md): a 17 m delta with a raised hump, two engine drums and four
spike guns, `raider` style. Outputs the textured `raider_fighter.glb` and its maps, `raider_fighter.obj/.mtl`, `hardpoints.json`,
`manifest.json` and five break-up chunks (`raider_fighter_chunk_<wing_l|wing_r|hump|nacelle_l|nacelle_r>.glb/.obj/.mtl`).

Things the Godot side must know:

- `hardpoints.json` has two pods (`l`, `r`), four muzzles (`root_l`, `root_r`, `nacelle_l`, `nacelle_r`), collision
  primitives that are also the hit volumes, and `chunks[]` `{name, obj, offset, mesh}`. A chunk's meshes are re-centred on its
  own samples' centroid; `offset` is that centroid in the body frame.
- The centre of mass is trimmed onto the nacelle axis (y = the pods' nozzle y).

## The civilian ships

Five generators, nine hulls (M5, D59; textured meshes from M5-T27, docs/assets-civilian.md): `saturn_family` (five ids),
`skylark_transport`, `narn_transport`, `centauri_brezebel` and `brakiri_bokmai`, all through `core/civilian.py`. Each
writes, per id:

- `<id>.glb` with `<id>_albedo/_normal/_orm/_emissive.png` and their `.import` sidecars: the hull as M4's textured mesh
  (`core/textured_mesh.py`), on a 2 048 px atlas (`atlas_px`) at the texel the packer reaches (about 5 cm for the
  Skylark to 19 cm for the Saturn 8 transport), the normal map at the atlas's size, no baked occlusion (`occlusion`). Godot's
  importer builds the levels of detail. The manifest's `mesh` section and `files.mesh` name it.
- `<id>.obj/.mtl`: the same triangles (`files.obj`), the depth proxy and what `hardpoints.chunks[].obj` and the fidelity
  check fall back on.
- `<id>_chunk_<name>.obj` and `<id>_chunk_<name>.glb` per break-up chunk: the hull's faces of that group, a cut of the
  textured mesh on its atlas (no maps of their own), placed by `offset`; `joint` is where each breaks away.
- `<id>_turret.glb/.obj` with its own maps (on a 1 024 px atlas, `model_atlas_px`): the style's turret in the turret frame
  (the pivot at the origin, +Y the mount's `up`, the barrels along -Z). Manifest `turret`: `{obj, mesh, barrel_m,
  trunnion, muzzles}`.
- `hardpoints.json` and `manifest.json` (`centroid_offset`, `dimensions_m`, `chunks`, `surface_spacing_m`, `turret`).

The body origin is the centroid of the visible surface: every piece sampled at `spacing` (the right pieces once and
mirrored, the centre pieces symmetrised, the samples buried in another piece dropped), so it sits on the centre plane and
the hardpoints keep their frame. The paint is the faction's texture pack in its style (`ea_civilian`, `narn`, `centauri`,
`brakiri`): seams, plate tints, hatches and rivets in the colour and normal maps, wear, streaks and grime, at a fighter's
scale and scaled to the hull's texel by `at_texel`; windows and engine throats (the Bokmai's domes) glow in the emissive
map. Options: `spacing`, `atlas_px`, `model_atlas_px`, `occlusion`.

- `narn_transport`: 70 m, a flat green crescent with the cockpit in its notch, flank towers with the main nozzles, fins
  and a light grey cargo box. Four chunks (`cockpit`, `wing_l`, `wing_r`, `box`); two pods on the towers (the thrust
  line 5 m above the crescent, the centre of mass on it), 14 RCS ports, `turrets[]` `tower_l` and `tower_r` on the
  towers' slotted crowns. The throats glow orange-white.
- `centauri_brezebel`: 60 m, a round lens bow with a pale rim band and two arms reaching aft to hooked tip fins (gold
  caps), the engine bay between the arms, a dorsal fitting with five windows. Three chunks (`bow`, `arm_l`, `arm_r`);
  mains in the arms' tip faces, retros on the bow's rim; 16 RCS ports; one turret (`dorsal`, Q19). The windows glow
  white, the throats pink-white #FFB8E0 (`GLOW_SRGB`, also a `ShipSpec` tint).
- `brakiri_bokmai`: 80 m, a tall bow blade, a dorsal spine to a fork, lower arms, nacelles with cups and engine domes
  between tall fins, a spindle the cargo pods ride on. The hull is written without its pods; five chunks (`bow`, `arm_l`,
  `arm_r`, `engine_l`, `engine_r`) leave them out. `brakiri_bokmai_pod.glb/.obj` is the pod in its own frame (origin at
  the mount); manifest `pod`: `{obj, mesh, mass_kg, collision, size_m}`. `hardpoints.json` has `cargo_pods[]`
  (`pod_fwd`, `pod_mid`, `pod_aft`, each `{name, position, up, forward}` in the body frame) and two turrets, `flank_l`
  and `flank_r`, in the bow's flank insets facing outboard (Q22); the bolts are bright green #7CFF4F (`BOLT_SRGB`). The
  domes glow yellow-white #FFF0B0 (`GLOW_SRGB`) and the window strips pale green-white.
- `saturn_family`: one lead ship (antenna, command disc, frames and drum frame, engine section) plus cargo, so the length
  follows from the parts: `saturn_4_transport` and `saturn_4_tanker` (one 100 m section, 158.48 m), `saturn_8_transport`
  and `saturn_8_tanker` (two with a junction, 258.48 m), `saturn_3_freighter` (three pods in a stack and a slim engine,
  Q20, 96.80 m). Chunk names per variant are in docs/assets-civilian.md. Two pods (the bell's exit split in two for the
  mains, retros on the disc's front rim), cosmetic RCS, collision boxes and capsules, dorsal `turrets[]` (Q19) each on
  the pad or hub it stands on. The rim windows glow warm white, the throat blue-white.
- `skylark_transport`: 60 m, a capsule forward, the spine and collar, banded side tanks, a faceted body with a dorsal
  fin, the centre engine and two nacelles with forked claws. `ea_civilian` with the Skylark's sand paint and a more
  patched plating (`STYLE`); four chunks (`capsule`, `body`, `nacelle_l`, `nacelle_r`); two pods on the nacelles' axis,
  12 RCS ports, one turret (`dorsal`, Q19) on the body's ridge. The throats glow warm white #FFE9C2
  (`ENGINE_GLOW_SRGB`).

Fidelity (Q18, AC20) is scored on the textured mesh by `tools/refview/compare.py` against the STLs in `references/`; the
commands and scores are in docs/assets-civilian.md.

## `capital_hulls` and `b5_station`

The bench's capital stand-ins (one textured box per class, window rows on the flanks) and the Babylon 5 station stand-in (a
turning drum and a stationary frame), each piece a textured mesh with its bounds (`core/pieces.py`; manifest `classes` and
`pieces`). The station's drum is centred on its axis, so turning its node about local Z turns it in place.

## `sfx_combat`

The combat sounds (M2-T12, reshaped by M5-T18 and T19 on the reference in docs/design-references.md "Combat sounds"): eight
mono 16-bit 48 kHz WAVs synthesised with NumPy, peaks at -1.5 dBFS, byte-identical per seed:

- `pulse_fire`, `raider_fire`: the Starfury's and the raiders' guns, a click and a held, inharmonic FM cluster, cut hard.
- `hit_hull`: a bolt striking a hull, short and metallic. `explosion`: a boom, swept noise and crackle.
- `main_burst`, `rcs_burst`: seamless loops for the per-thruster engine voices, a main pod's roar (400 Hz-16 kHz, loudest
  at 4-8 kHz) and an attitude jet's hiss (2-16 kHz). Nothing below 300 Hz.
- `warning_beep`, `target_blip`: the hull warning and the target-selected blip.

Its manifest has `kind` `audio`, a `sounds` object (file, samples, sample rate, duration, peak, and `loop_begin` / `loop_end`
for the two loops, seamless by construction) and no `lods`. Option: `peak_dbfs` (default -1.5, at most -1).

## `sfx_ui`

The menu sounds (M5-T02, D57) and the comms squelches (M5-T06, D53): five mono 16-bit 48 kHz WAVs, peaks at -1.5 dBFS,
byte-identical per seed. `ui_move` (a quiet 45 ms tick), `ui_accept` (two notes rising) and `ui_back` (two notes falling) are
plain sine tones in the family of `target_blip`. `radio_open` (0.22 s: band-limited static fading into a rising key-up chirp)
and `radio_close` (0.16 s: a falling chirp and a short tail of static) frame each comms line; they stay in the voice band
(nothing below 400 Hz). `AudioDirector` loads them beside `sfx_combat` and plays them with `play_ui`. Same manifest shape as
`sfx_combat`, no loops.

## `sfx_world`

Sounds of the world itself (M5-T05, D51): one mono 16-bit 48 kHz WAV, peak -1.5 dBFS, byte-identical per seed. `jump_in`
(1.6 s), a jump point opening (Q12): noise rising through four bands and a sine gliding up three octaves to the opening at
0.8 s, then a bright FM chord over a short thump that dies away. A jump vortex plays it with an arrival's centre flash (M6-T19; M5's `JumpArrival` did before). Same manifest shape as
`sfx_combat`, no loops.

## `sky_default`

12 000 stars on a 20 km sphere (Milky Way band, magnitude distribution, blackbody colours) and 4 000 soft nebula blobs (300-2 000
m, opacity 0.021-0.079, teal/magenta, one region about 40 degrees across, in view of a forward camera). Outputs
`sky_default_stars.f32` (direction, tint and brightness per star, for the game's point field), `sky_default_panorama.png` (the
nebula, 4096x2048 equirectangular RGBA, its alpha the gas's opacity over the stars) with its sidecar, and `manifest.json`
(`star_field` names the record layout). The panorama follows Godot's `PanoramaSkyMaterial` convention: the image centre looks
toward +Z and +u turns toward -X.
