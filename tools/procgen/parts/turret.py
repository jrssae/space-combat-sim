"""Defensive turret model (D61): a round base, a dome and twin barrels, in any style, at any size.

The turret frame is the mount's: the origin at the centre of the base where it sits on the hull, +Y the mount's ``up``,
the barrels along -Z at rest. ``write_turret`` turns it into the files a hull ships beside its chunks
(``<id>_turret.ply/.light/.obj/.mtl``): splats re-centred on their own centroid and flipped to the 3DGS frame like a
chunk, with ``offset`` saying where that centroid sits in the turret frame.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

import numpy as np

from ..core import frames, lighting
from ..core.context import BuildContext
from ..core.geometry import Mesh, assign_material_by_predicate, box, ellipsoid_cap, lathe, rotation_x
from ..core.obj import write_obj
from ..core.paint_mesh import PaintPart, write_paint_mesh
from ..core.ply import SplatData, write_ply
from ..core.sampling import SurfaceSamples, sample_mesh, to_splats
from ..styles import Style
from . import Anchor, Part
from .solids import Solid, box_solid, lathe_solid, segment_solid

_Z_TO_Y = rotation_x(-0.5 * math.pi)  # takes local +Z to +Y


@dataclass(frozen=True)
class TurretSpec:
    """Sizes in metres. ``barrel_m`` is the reach from the turret's turning axis to the muzzles."""

    base_diameter: float = 3.6
    base_height: float = 0.9
    dome_diameter: float = 3.0
    dome_height: float = 1.3
    barrel_m: float = 4.5
    barrel_gap: float = 0.8  # between the barrels' axes
    barrel_radius: float = 0.16
    trunnion_height: float = 1.45  # the barrels' axis above the base
    mantlet: tuple[float, float, float] = (1.7, 0.9, 1.1)  # the block on the dome's front holding the barrels
    hazard_stripes: int = 16  # yellow and black blocks round the base's wall
    segments: int = 36
    panel_size_m: float = 0.9  # the turret's own panel grid (a hull's grid is far larger than the turret)
    panel_line_m: float = 0.06
    mass_kg: float = 3_000.0

    def scaled(self, k: float) -> TurretSpec:
        """The same turret at ``k`` times the size (the Skylark carries it at two thirds)."""
        return replace(
            self,
            base_diameter=k * self.base_diameter,
            base_height=k * self.base_height,
            dome_diameter=k * self.dome_diameter,
            dome_height=k * self.dome_height,
            barrel_m=k * self.barrel_m,
            barrel_gap=k * self.barrel_gap,
            barrel_radius=k * self.barrel_radius,
            trunnion_height=k * self.trunnion_height,
            mantlet=tuple(k * v for v in self.mantlet),
            panel_size_m=k * self.panel_size_m,
            panel_line_m=k * self.panel_line_m,
            mass_kg=k**3 * self.mass_kg,
        )

    @property
    def muzzles(self) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
        half = 0.5 * self.barrel_gap
        return ((-half, self.trunnion_height, -self.barrel_m), (half, self.trunnion_height, -self.barrel_m))


def _base(spec: TurretSpec, style: Style) -> Mesh:
    """The base ring standing on the hull: an open-bottomed drum with a chamfered top, hazard blocks round its wall."""
    r, h = 0.5 * spec.base_diameter, spec.base_height
    chamfer = 0.12 * h
    profile = [(0.0, r), (h - chamfer, r), (h, r - chamfer), (h, 0.0)]
    hull = style.material("hull")
    mesh = lathe(profile, spec.segments, [style.material("hazard"), hull, hull], creases={1, 2}).transformed(_Z_TO_Y)
    centroids = mesh.face_centroids()
    angle = np.arctan2(centroids[:, 2], centroids[:, 0]) % (2.0 * math.pi)
    stripe = np.floor(angle / (2.0 * math.pi) * spec.hazard_stripes).astype(int) % 2 == 1
    wall = centroids[:, 1] < h - chamfer - 1e-6
    return assign_material_by_predicate(mesh, style.material("hazard_dark"), wall & stripe)


def _barrel_root(spec: TurretSpec) -> float:
    """Where the barrels end inside the mantlet (z)."""
    return -0.5 * spec.dome_diameter * 0.62


def _barrel(spec: TurretSpec, style: Style, x: float) -> Mesh:
    """One barrel from inside the mantlet to the muzzle, a thicker brake at the end and a dark bore."""
    r = spec.barrel_radius
    root = _barrel_root(spec)
    tip = spec.barrel_m
    brake = 0.12 * spec.barrel_m
    profile = [(0.0, 0.0), (0.0, 0.62 * r), (0.0, 1.3 * r), (brake, 1.3 * r), (brake, r), (tip + root, r), (tip + root, 0.0)]
    barrel, bore = style.material("barrel"), style.material("bore")
    mesh = lathe(profile, 14, [bore, barrel, barrel, barrel, barrel, barrel], creases={1, 2, 3, 4, 5})
    # Built muzzle-first along +Z from z = 0: the muzzle lands at z = -barrel_m, the root inside the mantlet.
    return mesh.translated((x, spec.trunnion_height, -tip))


def _dome_solid(radius: float, height: float, base_y: float) -> Solid:
    def test(p: np.ndarray, margin: float) -> np.ndarray:
        q = (p[:, 0] / radius) ** 2 + ((p[:, 1] - base_y) / height) ** 2 + (p[:, 2] / radius) ** 2
        return (q < (1.0 - margin / height) ** 2) & (p[:, 1] > base_y + margin)

    return Solid(test, ((-radius, base_y, -radius), (radius, base_y + height, radius)))


def turret_pieces(spec: TurretSpec, style: Style) -> list[tuple[str, Mesh, Solid]]:
    """The base, dome, mantlet and barrels, each with the volume that hides what the others push into it."""
    if min(spec.base_diameter, spec.base_height, spec.dome_diameter, spec.dome_height, spec.barrel_m) <= 0.0:
        raise ValueError("turret sizes must be positive")
    base_r, dome_r = 0.5 * spec.base_diameter, 0.5 * spec.dome_diameter
    base_y = spec.base_height - 0.02
    dome = ellipsoid_cap((dome_r, spec.dome_height, dome_r), 0.0, style.material("hull"), rings=8, segments=spec.segments)
    mw, mh, md = spec.mantlet
    mantlet_centre = (0.0, spec.trunnion_height, -(dome_r * 0.62))
    pieces = [
        ("base", _base(spec, style), lathe_solid([(0.0, base_r), (spec.base_height, base_r)]).transformed(_Z_TO_Y)),
        ("dome", dome.translated((0.0, base_y, 0.0)), _dome_solid(dome_r, spec.dome_height, base_y)),
        ("mantlet", box((mw, mh, md), style.material("hull_dark"), center=mantlet_centre), box_solid((mw, mh, md), mantlet_centre)),
    ]
    root = _barrel_root(spec)
    for name, (x, y, z) in zip(("barrel_l", "barrel_r"), spec.muzzles, strict=True):
        pieces.append((name, _barrel(spec, style, x), segment_solid((x, y, z), (x, y, root), spec.barrel_radius)))
    return pieces


def turret(spec: TurretSpec, style: Style) -> Part:
    """The turret in its own frame. Anchors: ``pivot`` (the base centre, along +Y), ``trunnion`` (where the barrels
    elevate) and ``muzzle_l`` / ``muzzle_r`` (pointing along -Z)."""
    mesh = Mesh.concatenate([m for _, m, _ in turret_pieces(spec, style)])
    (ml, mr) = spec.muzzles
    anchors = {
        "pivot": Anchor((0.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
        "trunnion": Anchor((0.0, spec.trunnion_height, 0.0)),
        "muzzle_l": Anchor(ml, (0.0, 0.0, -1.0)),
        "muzzle_r": Anchor(mr, (0.0, 0.0, -1.0)),
    }
    return Part("turret", mesh, anchors, mass_kg=spec.mass_kg)


def write_turret(
    out_dir: Path,
    asset_id: str,
    spec: TurretSpec,
    style: Style,
    ctx: BuildContext,
    spacing: float,
    overlap: float,
    thickness: float,
    comments: tuple[str, ...] = (),
) -> tuple[list[Path], dict[str, Any]]:
    """Writes the turret's PLY, lighting records, fallback OBJ and painted mesh (``<id>_turret_mesh.glb``, the ships-as-meshes
    directive of 2026-11-04); returns the files and the manifest ``turret`` entry."""
    part = turret(spec, style)
    pieces = turret_pieces(spec, style)
    kept = []
    for name, mesh, _solid in pieces:
        s = sample_mesh(mesh, spacing, ctx.rng("turret", "splats", name))
        hidden = np.zeros(len(s), dtype=bool)
        for other, _mesh, solid in pieces:
            if other != name:
                hidden |= solid.contains(s.positions)
        kept.append(s.subset(~hidden))
    samples = SurfaceSamples.concatenate(kept)
    fine = replace(style, panel_size_m=spec.panel_size_m, panel_line_width_m=spec.panel_line_m)
    rgb = fine.shade_panels(samples.albedo(), np.abs(samples.positions), samples.normals, samples.material_flag("paneled") > 0.5)
    splats = to_splats(samples, rgb, spacing, overlap, thickness)
    centroid = splats.xyz.mean(axis=0)
    written = SplatData(
        xyz=frames.godot_to_3dgs_positions(splats.xyz - centroid),
        rgb=splats.rgb,
        alpha=splats.alpha,
        scale=splats.scale,
        rot=frames.godot_to_3dgs_quats(splats.rot),
        normals=frames.flip_xy(splats.normals),
    )
    ply_name, light_name, obj_name = f"{asset_id}_turret.ply", f"{asset_id}_turret.light", f"{asset_id}_turret.obj"
    files = [
        write_ply(out_dir / ply_name, written, tuple(comments) + ("turret",)),
        lighting.write_lighting(out_dir / light_name, written),
    ]
    files += write_obj(out_dir / obj_name, part.mesh.translated(-centroid), f"{asset_id}_turret", comments[:1])
    mesh_path, mesh_entry = write_paint_mesh(out_dir, f"{asset_id}_turret", [PaintPart(part.mesh.translated(-centroid), (0, 0, 0))], fine)
    files.append(mesh_path)

    def r(v: Any) -> list[float]:
        return [round(float(x), 5) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]

    entry = {
        "ply": ply_name,
        "lighting": light_name,
        "obj": obj_name,
        "splats": len(splats),
        "spacing_m": spacing,
        "offset": r(centroid),
        "barrel_m": round(spec.barrel_m, 5),
        "trunnion": r(part.anchor("trunnion").position),
        "muzzles": [r(part.anchor("muzzle_l").position), r(part.anchor("muzzle_r").position)],
        "paint_mesh": mesh_entry,
    }
    return files, entry
