"""``nav_buoy``: an inert navigation buoy, the M1 target marker (docs/architecture.md section 9.3).

Composition only, like ``starfury_aurora``: parts from ``parts/`` with the ``earthforce`` style;
the splats (``.ply``), the fallback mesh (``.obj``) and ``hardpoints.json`` are all derived from
the same placed parts, so they agree by construction.

Layout (authored Godot frame, metres, before re-centring; +Y is the long axis the buoy spins
about in game):

* cylinder hull: 2.4 m barrel, 0.8 m across, conical shoulders to 0.32 m end plates; light grey
  with two orange hazard stripes near the ends
* two dark panel wings, 0.9 m x 1.1 m, standing in the X/Y plane on either side (+-X) at mid
  height, so the 10 deg/s spin is easy to see (face-on, then edge-on)
* antenna mast on top (1.0 m) carrying the beacon (a game-side emissive mesh at the ``beacon``
  hardpoint) and a short stub antenna below

About 4.4 m tall overall. Every sampled part is made exactly mirror-symmetric in x and z and the y
centroid is subtracted, so the splat centroid is the origin and lies on the spin axis: GDGS's
import centring is a no-op and the buoy spins about its own axis without wobbling.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core import frames
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh, rotation_x
from ..core.lighting import STUDIO_DEFAULT, StudioRig
from ..core.manifest import build_manifest, lod_entry, write_manifest
from ..core.obj import write_obj
from ..core.ply import SplatData, write_ply
from ..core.sampling import (
    DEFAULT_OVERLAP,
    DEFAULT_THICKNESS,
    SurfaceSamples,
    sample_mesh,
    to_splats,
)
from ..parts import Part, total_mass
from ..parts.hull import CylinderHullSpec, cylinder_hull
from ..parts.structure import MastSpec, PanelSpec, mast, panel
from ..styles import Style
from ..styles.earthforce import EARTHFORCE

ASSET_ID = "nav_buoy"
GENERATOR_VERSION = 1
PLY_NAME = "nav_buoy.ply"
OBJ_NAME = "nav_buoy.obj"
HARDPOINTS_NAME = "hardpoints.json"

DEFAULT_SPACING_M = 0.04  # architecture section 9.3
SPLAT_BUDGET = (5_000, 15_000)  # AC3, at the default spacing
SPIN_AXIS = (0.0, 1.0, 0.0)
JSON_DIGITS = 5


# --- the parametric description --------------------------------------------------------------
# Module-level part specs (frozen dataclasses) so NavBuoySpec can use them as plain defaults.
BUOY_HULL = CylinderHullSpec(
    barrel_height=2.4,
    radius=0.4,
    cap_height=0.3,
    end_radius=0.16,
    bands=((0.07, 0.15, "stripe"), (0.85, 0.93, "stripe")),
    mass_kg=1_800.0,
)
BUOY_WING = PanelSpec(width=0.9, length=1.1, thickness=0.04, material="hull_dark", mass_kg=60.0)
BUOY_MAST = MastSpec(height=1.0, radius=0.035, mass_kg=15.0)
BUOY_STUB = MastSpec(height=0.45, radius=0.03, mass_kg=5.0)


@dataclass(frozen=True)
class NavBuoySpec:
    hull: CylinderHullSpec = BUOY_HULL
    wing: PanelSpec = BUOY_WING
    wing_sink: float = 0.03  # how far a wing's inner edge reaches into the barrel
    mast: MastSpec = BUOY_MAST
    stub: MastSpec = BUOY_STUB
    mast_sink: float = 0.02  # masts start just inside the end plates
    beacon_radius: float = 0.1  # the game's emissive lamp, centred on the mast tip


DEFAULT_SPEC = NavBuoySpec()


def build_parts(spec: NavBuoySpec, style: Style, ctx: BuildContext, spacing: float) -> list[tuple[Part, SurfaceSamples]]:
    """Place and sample every part in the authored frame, exactly symmetric in x and z."""

    def sample(part: Part, stream: str) -> SurfaceSamples:
        return sample_mesh(part.mesh, spacing, ctx.rng("splats", stream))

    placed: list[tuple[Part, SurfaceSamples]] = []
    hull = cylinder_hull(spec.hull, style).renamed("hull")
    placed.append((hull, sample(hull, "hull").symmetrized("xz")))

    # The wing is a flat plate in X/Z; rotating +90 deg about X stands it up in the X/Y plane.
    root_x = hull.anchor("side_right").position[0] - spec.wing_sink
    wing_r = panel(spec.wing, style).transformed(rotation_x(0.5 * math.pi), [root_x + 0.5 * spec.wing.width, 0.0, 0.0])
    wing_r = wing_r.renamed("wing_r")
    wing_samples = sample(wing_r, "wing").symmetrized("z")
    placed.append((wing_r, wing_samples))
    placed.append((wing_r.mirrored("x").renamed("wing_l"), wing_samples.mirrored("x")))

    top = hull.anchor("top").position
    mst = mast(spec.mast, style).translated(top - [0.0, spec.mast_sink, 0.0]).renamed("mast")
    placed.append((mst, sample(mst, "mast").symmetrized("xz")))

    bottom = hull.anchor("bottom").position
    stub = mast(spec.stub, style).transformed(rotation_x(math.pi), bottom + [0.0, spec.mast_sink, 0.0])
    stub = stub.renamed("stub")
    placed.append((stub, sample(stub, "stub").symmetrized("xz")))
    return placed


def centre(placed: list[tuple[Part, SurfaceSamples]]) -> tuple[list[tuple[Part, SurfaceSamples]], np.ndarray]:
    """Subtract the splat centroid from everything. x and z are already exactly zero (symmetry),
    so only y moves; returns the placements and the subtracted offset (``centroid_offset``)."""
    total = sum(len(s) for _, s in placed)
    y_mean = sum(float(s.positions[:, 1].sum()) for _, s in placed) / total
    offset = np.array([0.0, y_mean, 0.0])
    return [(p.translated(-offset), s.translated(-offset)) for p, s in placed], offset


def _phase(name: str, style: Style) -> tuple[float, float, float]:
    """Per-part shift of the panel grid, so neighbouring parts' panel lines do not line up."""
    h = sum((i + 1) * ord(c) for i, c in enumerate(name.split("_")[0]))
    return tuple(((h * k) % 97) / 97.0 * style.panel_size_m for k in (7, 11, 13))


def colour_samples(part: Part, samples: SurfaceSamples, style: Style, rig: StudioRig) -> np.ndarray:
    paneled = samples.material_flag("paneled") > 0.5
    albedo = style.shade_panels(samples.albedo(), samples.positions, samples.normals, paneled, _phase(part.name, style))
    return rig.shade(samples.normals, albedo, samples.material_flag("metallic"))


def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def hardpoints(placed: list[tuple[Part, SurfaceSamples]], spec: NavBuoySpec) -> dict[str, Any]:
    """The hardpoints document (centred Godot frame) from the placed parts."""
    parts = [p for p, _ in placed]
    by_name = {p.name: p for p in parts}
    lo, hi = Mesh.concatenate(p.mesh for p in parts).bounds()
    collision = [{**shape.to_json(digits=JSON_DIGITS), "name": p.name} for p in parts for shape in p.collision]
    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "height_m": round(float(hi[1] - lo[1]), 3),
        "span_m": round(float(hi[0] - lo[0]), 3),
        "depth_m": round(float(hi[2] - lo[2]), 3),
        "mass_kg": round(total_mass(parts), 1),
        "spin_axis": list(SPIN_AXIS),
        "beacon": {"position": _r(by_name["mast"].anchor("tip").position), "radius": spec.beacon_radius},
        "collision": collision,
    }


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the buoy into ``ctx.out_dir``.

    Options: ``spacing`` (m, default 0.04; the CLI's ``--spacing``), ``overlap`` (sigma /
    spacing, default 1.4), ``thickness`` (normal sigma / spacing, default 0.03).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    overlap = float(ctx.option("overlap", DEFAULT_OVERLAP))
    thickness = float(ctx.option("thickness", DEFAULT_THICKNESS))
    if spacing <= 0.0 or overlap <= 0.0 or thickness <= 0.0:
        raise ValueError("spacing, overlap and thickness must be positive")
    spec, style, rig = DEFAULT_SPEC, EARTHFORCE, STUDIO_DEFAULT

    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    placed, offset = centre(build_parts(spec, style, ctx, spacing))
    samples = SurfaceSamples.concatenate([s for _, s in placed])
    rgb = np.concatenate([colour_samples(p, s, style, rig) for p, s in placed])
    authored = to_splats(samples, rgb, spacing, overlap, thickness)

    xyz32 = authored.xyz.astype(np.float32)
    aabb_min, aabb_max = xyz32.min(axis=0), xyz32.max(axis=0)
    written = SplatData(
        xyz=frames.godot_to_3dgs_positions(authored.xyz),
        rgb=authored.rgb,
        alpha=authored.alpha,
        scale=authored.scale,
        rot=frames.godot_to_3dgs_quats(authored.rot),
        normals=frames.flip_xy(authored.normals),
    )
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}", "frame: 3dgs (Rz180 of godot)")
    files: list[Path] = [write_ply(out_dir / PLY_NAME, written, comments)]
    files += write_obj(out_dir / OBJ_NAME, Mesh.concatenate(p.mesh for p, _ in placed), ASSET_ID, comments[:1])

    hp = hardpoints(placed, spec)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    total = len(authored)
    warnings: list[str] = []
    if abs(spacing - DEFAULT_SPACING_M) < 1e-12 and not SPLAT_BUDGET[0] <= total <= SPLAT_BUDGET[1]:
        warnings.append(f"{total} splats is outside the AC3 budget {SPLAT_BUDGET} at the default spacing")
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        lods=[lod_entry(0, PLY_NAME, total, spacing)],
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=offset,
        files={"fallback_mesh": OBJ_NAME, "hardpoints": HARDPOINTS_NAME},
        extra={
            "counts": {p.name: len(s) for p, s in placed},
            "sampling": {"spacing_m": spacing, "overlap": overlap, "thickness": thickness},
            "dimensions_m": {"height": hp["height_m"], "span": hp["span_m"], "depth": hp["depth_m"]},
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), tuple(warnings))
