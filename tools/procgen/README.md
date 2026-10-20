# tools/procgen

Procedural asset generators for space-combat-sim. Every generated asset comes from code in this package
(design: `docs/architecture.md` section 9 and 14.8). Output goes to `assets/generated/` and is never committed.

Requirements: Python 3.11+ and NumPy. Pillow is optional: without it the `sky_default` fallback panorama PNG is
skipped with a warning and everything else still builds.

## Running

```
scripts/gen_assets.sh                           # python3 -m tools.procgen build all
python3 -m tools.procgen list                   # registered asset ids, one per line, sorted
python3 -m tools.procgen build sky_default      # one or more ids
python3 -m tools.procgen build all --seed 7 --out /tmp/assets
python3 -m tools.procgen build starfury_aurora --spacing 0.05 --option overlap=1.2
python3 -m unittest discover -s tools/procgen/tests -t . -v
```

- `--seed N` (default 42, must be >= 0): the same seed always produces byte-identical files.
- `--out DIR` (default `<repo>/assets/generated`): output root; each asset writes into `DIR/<asset_id>/`.
- `--spacing M`: splat spacing in metres for surface-sampled assets (`starfury_aurora` default 0.035).
- `--option KEY=VALUE` (repeatable, JSON values): any other `BuildContext.options` entry, e.g. `overlap=1.2`.
  Assets ignore options they do not know.
- `build all` builds every registered asset in sorted order. If `all` appears among other ids it wins.
- Exit codes: 0 ok, 1 an asset failed to build (the others still build), 2 usage error (unknown id, bad seed).
- Warnings (for example the skipped panorama) are printed to stderr as `warning: ...`.

## Layout

```
core/context.py    BuildContext (out_dir, seed, options, rng) and AssetOutputs (what build() returns)
core/ply.py        3DGS PLY writer + reader (SplatData, write_ply, read_ply)
core/frames.py     Godot <-> 3DGS (Rz 180) conversion, quaternion helpers
core/color.py      blackbody star colours, sRGB transfer
core/manifest.py   manifest.json builder/validator/writer
core/geometry.py   Mesh + Material, primitives (box, tapered box, lathe, loft, superellipse, ellipsoid cap)
core/sampling.py   mesh -> surface samples (area-weighted, stratified, R2 low-discrepancy) -> flat splats
core/lighting.py   baked studio rig (hemisphere ambient + directional lights) for unlit splats
core/obj.py        OBJ/MTL writer and a small reader for tests
parts/             reusable parametric parts: hull (fuselage, canopy, cockpit interior/tub,
                   upright cylinder hull with painted bands, faceted wedge fuselage with a framed
                   cockpit window and its first-person frame mesh), propulsion (nozzle, RCS cone,
                   engine pod, ring-faced pod, claw vane cluster with RCS blocks, pilot_tags),
                   structure (strut, trussed strut with ladder webs and painted bands, block,
                   panel, mast), weapons (gun barrel, twin gun mount).
                   Spec dataclass + Style in, Part out (mesh, named anchors, collision primitives,
                   mass)
styles/            design languages: Style (material roles + panel-shading parameters); earthforce.py
assets/__init__.py registry: ASSETS: dict[str, Callable[[BuildContext], AssetOutputs]]
assets/<id>.py     one module per asset, exposing build(ctx)
tests/             unittest: core, parts, CLI, and every asset
```

## Conventions every generator follows

- **Deterministic.** Take randomness only from `ctx.rng()` (that is `numpy.random.default_rng(ctx.seed)`) or a
  named, independent sub-stream `ctx.rng("stars")`. No wall clock, no environment, no timestamps in outputs.
- **Godot frame in code, 3DGS frame in the PLY.** Author in metres with +X right, +Y up, -Z forward. Re-centre the
  splats on their centroid (GDGS subtracts the mean at import, so this makes that a no-op), then write them
  through `frames.godot_to_3dgs_positions` / `godot_to_3dgs_quats` (Rz 180 degrees) so the `GaussianSplatNode`
  can stay at identity. Meshes and hardpoints are re-centred on the same centroid but stay in the Godot frame.
- **PLY encoding.** `write_ply` stores `scale = ln(metres)`, `opacity = logit(alpha)` (alpha is clamped to
  [1e-4, 0.9999] so the logit is finite) and `f_dc = (rgb - 0.5) / 0.28209479`. Colours are linear radiance and may
  exceed 1.0.
- **Manifest.** Always write `manifest.json` last with `core.manifest.build_manifest` + `write_manifest`:
  `lods[0]` is the full-detail PLY, `aabb_min/max` bound the written splat centres in the Godot frame (the same box
  GDGS reports, up to the flip), `centroid_offset` is the Godot-frame vector subtracted by the re-centring. Extra
  keys (counts and so on) go through `extra=`. `build()` returns an `AssetOutputs` listing every file it wrote
  and any warnings; the CLI checks that the manifest exists and is valid.

## Adding an asset

1. Create `tools/procgen/assets/my_asset.py` with `build(ctx: BuildContext) -> AssetOutputs`. Write into
   `ctx.out_dir` (the CLI has created it), put tunables in module constants or `ctx.option("name", default)`, and
   finish with `write_manifest`.
2. Register it in `tools/procgen/assets/__init__.py`: `ASSETS["my_asset"] = my_asset.build`.
3. Add `tests/test_my_asset.py`: splat count range, PLY fields parse back, centroid near zero, manifest `lods[0]`,
   and same seed gives the same SHA-256 (see `test_sky_default.py` for a template).
4. Run the tests and `scripts/gen_assets.sh`. Third-party dependencies need an entry in `docs/third-party.md`.

## `nav_buoy`

The inert navigation buoy the M1 targeting cycles through (architecture section 9.3): an upright cylinder hull
(2.4 m barrel, 0.8 m across, two orange hazard stripes), two dark panel wings standing in the X/Y plane, an antenna
mast on top and a stub below, about 4.4 m tall, `earthforce` style. Outputs `nav_buoy.ply` (about 7.6k splats at
0.04 m spacing; AC3 budget 5k-15k), `nav_buoy.obj/.mtl` (fallback mesh), `hardpoints.json` and `manifest.json`.
Options: `spacing`, `overlap`, `thickness`, as for the ship.

Things the Godot side must know:

- One frame for everything: the splat centroid is the origin and lies on the long axis (every part is sampled
  exactly mirror-symmetric in x and z), so the buoy spins about its node's +Y without wobbling. `hardpoints.json`
  has `spin_axis` `[0, 1, 0]`.
- `hardpoints.json` `beacon` is `{"position", "radius"}`: the mast tip, where the game puts its emissive beacon mesh
  (the splats never contain the lamp; it blinks). `collision` holds one capsule for later; M1 buoys have none.
- Splats are written in manifest `counts` order: `hull`, `wing_r`, `wing_l`, `mast`, `stub`.

## `starfury_aurora`

The player's SA-23E-style Starfury, composed from `parts/` with the `earthforce` style. Outputs
`starfury_aurora.ply` (about 230k flat, oriented splats at 0.04 m spacing, 0.022 m for the cockpit window's
frames and sill), `starfury_aurora.obj/.mtl`
(fallback mesh), `cockpit_interior.obj/.mtl`, `hardpoints.json` and `manifest.json`. The full description,
the hardpoints schema and the splat-quality reasoning are in `docs/assets-starfury.md`.

Things the Godot side must know:

- All outputs share one frame: the centred Godot body frame (splat centroid = origin, within float32).
  `manifest.centroid_offset` only documents how far the authoring frame was shifted; nothing needs it.
- Splats are written in `manifest.counts` order, so every part is a contiguous slice of the PLY (useful
  for debugging and future per-part effects).
- `hardpoints.json` is the contract for the flight model, cameras, weapons and collision (schema in the docs
  page); `center_of_mass` is on the thrust axis by design.
- The window panes are green-tinted glass (per-splat alpha ~0.03, 70 % transmission through the sheet);
  the frames and the dark lining and bulkhead behind them are opaque. In the OBJ the panes are the
  `ef_canopy_glass` faces. `(H)`: judge the look in both cameras.

## `sky_default`

12 000 star splats on a 20 km sphere (Milky Way band, magnitude distribution, blackbody colours) plus 4 000
nebula splats (300-2 000 m, opacity 0.021-0.079, teal/magenta, one region about 40 degrees across, in view of a
forward camera). Outputs `sky_default.ply`, `manifest.json` and, with Pillow, `sky_default_panorama.png`.

Things the Godot side must know:

- **The sky is one-sided, so its centroid is far from the origin** (about 4.6 km at seed 42). GDGS always
  subtracts the mean position, which therefore shifts the whole sphere. Put the sky node at
  `camera_position + manifest.centroid_offset` (Godot frame) to have the star sphere centred exactly on the camera;
  with the offset omitted the sky is a fish-eye distorted by roughly 13 degrees.
- `manifest.aabb_min/max` are the bounds of the written (re-centred) splat centres, so the import test compares
  them to the PLY bounds with x and y negated.
- `manifest.counts` gives the star count; stars are the first `counts.stars` splats, the nebula follows.
- Panorama: equirectangular 4096x2048, image centre is -Z and +X is to the right (assumed to match
  Godot's `PanoramaSkyMaterial`; not verified in the container, so (H): check the nebula lands on the same side
  as the splat sky). Colours are
  sRGB-encoded; the PLY colours are linear.
