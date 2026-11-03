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
core/lighting.py   per-splat lighting records for GDGS relighting (octahedral normal, AO, confidence; one `.light` per PLY)
core/obj.py        OBJ/MTL writer and a small reader for tests
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
core/chunks.py     break-up chunks: splats and mesh partitioned by part group, re-centred per chunk
styles/            design languages: Style (material roles + panel-shading parameters); earthforce.py, raider.py
parts/saturn.py    the Saturn family (M5-T12): lead ship, frames, drum frame, engine section, banded cylinders and
                   tanks, transport pods with recessed ribbed ends and rails, arms, junctions, turret pads; each
                   piece carries a burial volume and a side (centre line or right, mirrored)
parts/turret.py    defensive turret model (base, dome, twin barrels) at any size, and write_turret (its files)
parts/solids.py    burial volumes (box, lathe, prism, capsule, union, difference) that drop hidden samples
styles/ea_civilian.py the Earth Alliance civilian palette; ea_civilian(overrides) repaints roles per hull
parts/centauri.py  the Centauri Brezebel (M5-T15): the elliptic lens hull (bow, arms), engine bay, dorsal fitting,
                   fairings, hooked tip fins and the Centauri turret, each with its burial solid
styles/centauri.py the Centauri palette (violet, gold, lavender trim), painted as written
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
(fallback mesh), `cockpit_interior.obj/.mtl`, `hardpoints.json` and `manifest.json`; since M3-T03 also
`starfury_aurora_lod1.ply` (manifest `lods[1]`: about 57k splats at 0.08 m, 25 % of LOD0, for allies and debris) and
five break-up chunks cut from LOD1 (`starfury_aurora_chunk_<cabin|arm_ur|arm_lr|arm_ul|arm_ll>.ply/.light/.obj/.mtl`). Since
M3-T21 its colours, the raider's and the buoy's are flat paint, and each level and chunk has a `.light` file of per-splat lighting
records in its PLY's order and frame (manifest `lods[].lighting`, hardpoints `chunks[].lighting`). The
full description, the hardpoints schema and the splat-quality reasoning are in `docs/assets-starfury.md`.

Things the Godot side must know:

- All outputs share one frame: the centred Godot body frame (splat centroid = origin, within float32).
  `manifest.centroid_offset` only documents how far the authoring frame was shifted; nothing needs it.
- Splats are written in `manifest.counts` order, so every part is a contiguous slice of the PLY (useful
  for debugging and future per-part effects). The LOD1 PLY is written chunk by chunk instead (`hardpoints.chunks`
  order), so it is the chunks' splats concatenated; manifest `chunk_lod` (1) names the LOD the chunks partition.
- LOD1 is centred on its own centroid like LOD0; its frame is LOD0's within a few millimetres, so it shares the
  hardpoints, the fallback mesh and the depth proxy.
- `hardpoints.json` is the contract for the flight model, cameras, weapons and collision (schema in the docs
  page); `center_of_mass` is on the thrust axis by design.
- The window panes are green-tinted glass (per-splat alpha ~0.03, 70 % transmission through the sheet);
  the frames and the dark lining and bulkhead behind them are opaque. In the OBJ the panes are the
  `ef_canopy_glass` faces. `(H)`: judge the look in both cameras.

## `raider_fighter`

The raiders' Delta-V flying wing (docs/assets-raider.md): a 17 m delta with a raised hump, two engine drums and four
spike guns, `raider` style. Outputs `raider_fighter.ply` (about 26k splats at 0.09 m spacing; AC4 budget 15k-40k),
`raider_fighter.obj/.mtl` (fallback mesh), `hardpoints.json`, `manifest.json` and five break-up chunks
(`raider_fighter_chunk_<wing_l|wing_r|hump|nacelle_l|nacelle_r>.ply/.obj/.mtl`).

Things the Godot side must know:

- Splats are written group by group (`manifest.counts` order: `wing_l`, `wing_r`, `hump`, `nacelle_l`, `nacelle_r`);
  the hull PLY is the chunks' splats concatenated.
- `hardpoints.json` has two pods (`l`, `r`), four muzzles (`root_l`, `root_r`, `nacelle_l`, `nacelle_r`), collision
  primitives that are also the hit volumes, and `chunks[]` `{name, ply, obj, offset, splats}`. A chunk's PLY and OBJ
  are re-centred on its own centroid; `offset` is that centroid in the body frame.
- The centre of mass is trimmed onto the nacelle axis (y = the pods' nozzle y).

## `narn_transport`

The Narn freighter (M5-T14, docs/assets-civilian.md): a 70 m civilian, a flat green crescent with the cockpit in its notch,
flank towers with the main nozzles, fins and a light grey cargo box, `narn` style. Outputs `narn_transport.ply` (about 77k
splats at 0.31 m; budget 60k-90k), `_lod1` to `_lod3` (25 %, 6 %, 1.6 %), a `.light` per level, `narn_transport.obj/.mtl`
(fallback mesh and depth proxy), four chunks cut from LOD1 (`cockpit`, `wing_l`, `wing_r`, `box`), the turret model
`narn_transport_turret.ply/.light/.obj/.mtl` (about 1.9k splats at 0.11 m), `hardpoints.json` and `manifest.json`.

Things the Godot side must know:

- LOD0 is written group by group (`manifest.counts`), LOD1 chunk by chunk; `chunk_lod` is 1, as the Starfury's.
- `hardpoints.json` has two pods on the towers (the thrust line 5 m above the crescent, the centre of mass on it), 14 RCS
  ports, `muzzles` empty, and `turrets[]` `{name, position, up, arc_deg, barrel_m}` (`tower_l`, `tower_r`, on the towers'
  slotted crowns). The manifest's `turret` entry has the keys of `parts/turret.py`'s: `ply`, `lighting`, `obj`, `splats`,
  `spacing_m`, `offset` (the PLY's centroid in the turret frame: pivot at the origin, +Y up, barrels along -Z),
  `barrel_m`, `trunnion` and `muzzles`.

## `centauri_brezebel`

The Centauri Brezebel transport (M5-T15, docs/assets-civilian.md): a 60 m liner, a round lens bow with a pale rim band and
two arms reaching aft to hooked tip fins (gold caps), the engine bay between the arms, a dorsal fitting with five windows,
`centauri` style. Outputs `centauri_brezebel.ply` (about 67k splats at 0.26 m; budget 55k-85k), `_lod1` to `_lod3` (25 %,
6 %, 1.6 %), a `.light` per level, `centauri_brezebel.obj/.mtl` (fallback mesh and depth proxy), three chunks cut from
LOD1 (`bow`, `arm_l`, `arm_r`), the turret model `centauri_brezebel_turret.ply/.light/.obj/.mtl` (about 2.1k splats at
0.11 m), `hardpoints.json` and `manifest.json`.

Things the Godot side must know:

- LOD0 is written group by group (`manifest.counts`), LOD1 chunk by chunk; `chunk_lod` is 1.
- `hardpoints.json` has two pods (mains in the arms' tip faces at z 60, retros on the fairings' lips), the thrust line and
  centre of mass on the hull's centre plane, 16 RCS ports, `muzzles` empty, and one turret (`dorsal`, Q19) on the dorsal
  fitting's ring. The manifest's `turret` entry has the keys of `parts/turret.py`'s.
- The engine and fin-tip glow is pink-white #FFB8E0 (`styles/centauri.py` `GLOW_SRGB`), a `ShipSpec` tint, not paint.

## `saturn_family`

The Earth Alliance Saturn freighters (M5-T12, Q16, docs/assets-civilian.md): one module, five ids. Every variant is the
same lead ship (antenna, command disc, frames and drum frame, engine section) plus cargo, so its length follows from the
parts: `saturn_4_transport` and `saturn_4_tanker` carry one 100 m section (four pods round a banded hull cylinder, or three
banded tanks) and are 158.48 m long, `saturn_8_transport` and `saturn_8_tanker` carry two with a junction (258.48 m), and
`saturn_3_freighter` three pods in a stack with a slim engine between its lower pods (Q20, 96.80 m). Turrets are dorsal
only (Q19). Style `ea_civilian`. Per id: LOD0-3 PLYs and lighting records, the
fallback mesh (also the depth proxy), chunks cut from LOD1, the turret model, `hardpoints.json` and `manifest.json`.
Option: `spacing` (each variant's default lands its LOD0 on its budget), `overlap`, `thickness`.

Things the Godot side must know:

- The chunks partition LOD1 (manifest `chunk_lod` 1); LOD0 is the chunk groups concatenated in `counts` order. Chunk
  names per variant are in docs/assets-civilian.md; `joint` is where each breaks away.
- `hardpoints.json`: two pods (the bell's exit split in two for the mains, retros on the disc's front rim), twelve
  cosmetic RCS, `muzzles: []`, collision boxes and capsules (each cylinder's capsule reaches past its dome tips so its
  caps cover the shallow domes), and `turrets[]` `{name, position, up, arc_deg, barrel_m}`; each turret `position` is
  the top of a pad (or the disc's hub) it stands on. The centre of mass is on the spine axis, the thrust line.
- Manifest `turret`: `{ply, lighting, obj, splats, spacing_m, offset, barrel_m, trunnion, muzzles}`. The turret frame
  has its origin at the base's centre on the mount, +Y the mount's `up`, the barrels along -Z; its PLY is centred on its
  own centroid like a chunk, and `offset` is that centroid in the turret frame.
- Levels are sampled with systematic rounding (`sample_mesh(systematic=True)`) and centre-line pieces right half first,
  so a coarse level keeps LOD0's centroid to a fraction of its spacing.

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

The menu sounds (M5-T02, D57): three mono 16-bit 48 kHz WAVs, peaks at -1.5 dBFS, byte-identical per seed, plain sine tones in
the family of `target_blip`. `ui_move` (a quiet 45 ms tick), `ui_accept` (two notes rising) and `ui_back` (two notes falling).
`AudioDirector` loads them beside `sfx_combat` and plays them with `play_ui`. Same manifest shape as `sfx_combat`, no loops.

## `sfx_world`

Sounds of the world itself (M5-T05, D51): one mono 16-bit 48 kHz WAV, peak -1.5 dBFS, byte-identical per seed. `jump_in`
(1.6 s), a jump point opening (Q12): noise rising through four bands and a sine gliding up three octaves to the opening at
0.8 s, then a bright FM chord over a short thump that dies away. `JumpArrival` plays it at the point. Same manifest shape as
`sfx_combat`, no loops.

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
