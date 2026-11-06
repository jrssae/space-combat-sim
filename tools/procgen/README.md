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

## `capital_hulls` and `b5_station`

The bench's capital stand-ins (one textured box per class, window rows on the flanks) and the Babylon 5 station stand-in (a
turning drum and a stationary frame), each piece a textured mesh with its bounds (`core/pieces.py`; manifest `classes` and
`pieces`). The station's drum is centred on its axis, so turning its node about local Z turns it in place.

## `sfx_combat`

The combat sounds (docs/milestones M2-T12): seven mono 16-bit 48 kHz WAVs (`pulse_fire`, `raider_fire`, `hit_hull`, `explosion`,
`engine_loop`, `warning_beep`, `target_blip`) synthesised with NumPy, peaks at -1.5 dBFS, byte-identical per seed. Its manifest has
`kind` `audio` and a `sounds` object (file, samples, sample rate, duration, peak, and `loop_begin` / `loop_end` for the engine loop,
which is seamless by construction). Option: `peak_dbfs` (default -1.5, at most -1).

## `sky_default`

12 000 stars on a 20 km sphere (Milky Way band, magnitude distribution, blackbody colours) and 4 000 soft nebula blobs (300-2 000
m, opacity 0.021-0.079, teal/magenta, one region about 40 degrees across, in view of a forward camera). Outputs
`sky_default_stars.f32` (direction, tint and brightness per star, for the game's point field), `sky_default_panorama.png` (the
nebula, 4096x2048 equirectangular RGBA, its alpha the gas's opacity over the stars) with its sidecar, and `manifest.json`
(`star_field` names the record layout). The panorama follows Godot's `PanoramaSkyMaterial` convention: the image centre looks
toward +Z and +u turns toward -X.
