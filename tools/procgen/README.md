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
python3 -m unittest discover -s tools/procgen/tests -t . -v
```

- `--seed N` (default 42, must be >= 0): the same seed always produces byte-identical files.
- `--out DIR` (default `<repo>/assets/generated`): output root; each asset writes into `DIR/<asset_id>/`.
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
assets/__init__.py registry: ASSETS: dict[str, Callable[[BuildContext], AssetOutputs]]
assets/<id>.py     one module per asset, exposing build(ctx)
tests/             unittest: core, CLI, and every asset
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
