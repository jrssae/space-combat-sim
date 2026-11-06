"""``nav_buoy``: an inert navigation buoy, the M1 target marker (docs/architecture.md section 9.3).

Composition only, like ``starfury_aurora``: parts from ``parts/`` with the ``earthforce`` style;
the textured mesh, the OBJ and ``hardpoints.json`` are all derived from the same placed parts, so
they agree by construction.

Layout (authored Godot frame, metres, before re-centring; +Y is the long axis the buoy spins
about in game):

* cylinder hull: 2.4 m barrel, 0.8 m across, conical shoulders to 0.32 m end plates; light grey
  with two orange hazard stripes near the ends
* two dark panel wings, 0.9 m x 1.1 m, standing in the X/Y plane on either side (+-X) at mid
  height, so the 10 deg/s spin is easy to see (face-on, then edge-on)
* antenna mast on top (1.0 m) carrying the beacon (a game-side emissive mesh at the ``beacon``
  hardpoint) and a short stub antenna below

The textured mesh (M4-T30d, ``core/textured_mesh.py``) is the same parts plus the beacon's lens, a short collar under the beacon
whose glass glows amber like the beacon itself; the orange hazard bands are the hull's own ``stripe`` material.

About 4.4 m tall overall. Every sampled part is made exactly mirror-symmetric in x and z and the y
centroid of the surface samples is subtracted, so the origin lies on the spin axis and the buoy
spins about its own axis without wobbling.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Material, Mesh, lathe, rotation_x
from ..core.manifest import build_manifest, write_manifest
from ..core.obj import write_obj
from ..core.textured_mesh import TexturedPart, phase_steps, write_textured_mesh
from ..core.sampling import SurfaceSamples, sample_mesh
from ..parts import Part, total_mass
from ..parts.hull import CylinderHullSpec, cylinder_hull
from ..parts.structure import MastSpec, PanelSpec, mast, panel
from ..styles import Style
from ..styles.earthforce import EARTHFORCE

ASSET_ID = "nav_buoy"
GENERATOR_VERSION = 4  # 4: the textured mesh only (M4-T31); 3: the textured mesh (M4-T30d)
OBJ_NAME = "nav_buoy.obj"
HARDPOINTS_NAME = "hardpoints.json"
MESH_NAME = "nav_buoy.glb"
# The textured mesh (M4-T30d): about 12 m² of hull in a 1 024 px atlas, the normal map at the atlas's size.
ATLAS_PX = 1024
TEXEL_M = 0.006
# The beacon's lens: a glass collar on the mast just under the beacon, glowing the beacon's amber.
LENS = Material("ef_lens", (0.05, 0.035, 0.015), roughness=0.1, emissive=(1.0, 0.62, 0.22), emissive_strength=3.0)
LENS_RADIUS_M = 0.06
LENS_SPAN_M = (0.17, 0.09)  # from below the mast tip: where the collar starts and ends

DEFAULT_SPACING_M = 0.04  # the surface samples' spacing, which centres the buoy
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
        return sample_mesh(part.mesh, spacing, ctx.rng("surface", stream))

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
    """Subtract the samples' centroid from everything. x and z are already exactly zero (symmetry),
    so only y moves; returns the placements and the subtracted offset (``centroid_offset``)."""
    total = sum(len(s) for _, s in placed)
    y_mean = sum(float(s.positions[:, 1].sum()) for _, s in placed) / total
    offset = np.array([0.0, y_mean, 0.0])
    return [(p.translated(-offset), s.translated(-offset)) for p, s in placed], offset


def lens_mesh(tip: np.ndarray) -> Mesh:
    """The beacon's lens collar, round the mast just under its tip (the beacon sits on the tip)."""
    lo, hi = tip[1] - LENS_SPAN_M[0], tip[1] - LENS_SPAN_M[1]
    collar = lathe([(0.0, 0.0), (0.0, LENS_RADIUS_M), (hi - lo, LENS_RADIUS_M), (hi - lo, 0.0)], 24, LENS, creases=(1, 2))
    return collar.transformed(rotation_x(-0.5 * math.pi), (float(tip[0]), float(lo), float(tip[2])))


def textured_parts(placed: list[tuple[Part, SurfaceSamples]]) -> list[TexturedPart]:
    """The hull parts and the lens as the textured mesh takes them."""
    parts = [TexturedPart(p.mesh, phase_steps(p.name, False), (), p.name) for p, _ in placed]
    tip = next(p for p, _ in placed if p.name == "mast").anchor("tip").position
    return parts + [TexturedPart(lens_mesh(np.asarray(tip, dtype=float)), (0, 0, 0), (), "lens")]


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

    Option: ``spacing`` (m, default 0.04), the surface samples' spacing.
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")
    spec, style = DEFAULT_SPEC, EARTHFORCE

    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    placed, offset = centre(build_parts(spec, style, ctx, spacing))
    body = Mesh.concatenate(p.mesh for p, _ in placed)
    aabb_min, aabb_max = body.bounds()
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)
    files: list[Path] = write_obj(out_dir / OBJ_NAME, body, ASSET_ID, comments)

    textured_paths, mesh_entry = write_textured_mesh(out_dir, ASSET_ID, textured_parts(placed), style, atlas_px=ATLAS_PX, texel_m=TEXEL_M,
                                                     seed=ctx.seed, occlusion=True, normal_scale=1)
    files += textured_paths

    hp = hardpoints(placed, spec)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=offset,
        files={"obj": OBJ_NAME, "mesh": mesh_entry["file"], "hardpoints": HARDPOINTS_NAME},
        extra={
            "dimensions_m": {"height": hp["height_m"], "span": hp["span_m"], "depth": hp["depth_m"]},
            "mesh": mesh_entry,
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
