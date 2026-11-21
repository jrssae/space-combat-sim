"""Plain solids for capital hulls (M10-T21): what a hull task needs beside the library's lofted hull sections when a part
is a slab, a girder or a round body measured off a reference.

Every solid is a :class:`~.capital.Module` (mesh, collision, burial volume) in the authored frame (x to starboard, y up,
z aft), closed on all sides, so parts may overlap freely: the section compare fills them as their union and the sampler
drops what one buries of another.

* :func:`convex`: the convex hull of a point set, flat faced (a leaning armour slab, a tapering housing);
* :func:`prism`: a convex outline in (x, y) pulled along z (a girder's member, a drum arm's body);
* :func:`slab`: a flat plate of a given thickness under a convex outline anywhere in space (a stand-off plate);
* :func:`round_body`: a solid of revolution along any line (a tank, a collar, a nacelle);
* :func:`rod`: a thin mast or aerial;
* :func:`compound`: several modules as one (a part of two convex pieces).
"""

from __future__ import annotations

from collections.abc import Sequence

import numpy as np

from ..core import collision as col
from ..core.geometry import Material, Mesh, basis_from_z, lathe
from ..styles import Style
from .capital import SKIN_HULL, SKIN_NONE, Module, module
from .capital_hull import HullRoles, _role_of
from .raider_carrier import flat
from .solids import Solid, lathe_solid, union

Vec3 = tuple[float, float, float]
ROUND = 16  # sides of a round body
BORE_STEP_M = 7.5  # a nozzle bore's collision steps: short enough that its open face lies within reach of the wall
BORE_SECTORS = 6
CORNER_SLACK_M = 1.0  # how far a round body's collision corners may stand off its surface


def _convex_solid(points: np.ndarray, faces: col.Faces) -> Solid:
    """Inside every face of the hull."""
    normals, offsets = faces.normals, faces.offsets

    def test(p: np.ndarray, margin: float) -> np.ndarray:
        return np.all(p @ normals.T - offsets < -margin, axis=1)

    return Solid(test, (points.min(axis=0), points.max(axis=0)))


def convex(name: str, points: Sequence[Sequence[float]], style: Style, roles: HullRoles = HullRoles(), skin: str = SKIN_HULL,
           fine: float = 1.0) -> Module:
    """The convex hull of ``points`` as a closed flat-faced part; faces looking up take the deck's paint, down the keel's."""
    pts = np.asarray(points, dtype=float).reshape(-1, 3)
    faces = col.hull_faces(pts)
    inside = pts.mean(axis=0)
    meshes = [flat(pts[ring], style.material(_role_of(n, roles)), inside) for n, ring in zip(faces.normals, faces.polygons, strict=True)]
    return module(name, Mesh.concatenate(meshes), [col.hull(name, pts)], solid=_convex_solid(pts, faces), skin=skin, fine=fine)


def prism(name: str, outline_xy: Sequence[Sequence[float]], z0: float, z1: float, style: Style, roles: HullRoles = HullRoles(),
          skin: str = SKIN_HULL) -> Module:
    """A convex outline in (x, y) pulled from ``z0`` to ``z1``."""
    if z1 <= z0:
        raise ValueError(f"prism {name!r} needs z1 past z0")
    return convex(name, [(x, y, z) for z in (z0, z1) for x, y in outline_xy], style, roles, skin)


def box(name: str, lo: Sequence[float], hi: Sequence[float], style: Style, roles: HullRoles = HullRoles(), skin: str = SKIN_HULL) -> Module:
    """An axis-aligned block between two corners."""
    return convex(name, [(x, y, z) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])], style, roles, skin)


def slab(name: str, outline: Sequence[Sequence[float]], thickness: float, inward: Sequence[float], style: Style,
         roles: HullRoles = HullRoles(), skin: str = SKIN_HULL) -> Module:
    """A plate under a convex outline (points in space, its outer face): the outline and its copy ``thickness`` along
    ``inward``."""
    outer = np.asarray(outline, dtype=float).reshape(-1, 3)
    step = np.asarray(inward, dtype=float)
    step = step / np.linalg.norm(step) * thickness
    return convex(name, np.concatenate([outer, outer + step]), style, roles, skin)


def round_body(name: str, start: Sequence[float], end: Sequence[float], profile: Sequence[tuple[float, float]], style: Style,
               materials: Material | Sequence[Material] | None = None, sides: int = ROUND, creases: Sequence[int] = (),
               skin: str = SKIN_HULL, hollow_from: int | None = None) -> Module:
    """A solid of revolution laid from ``start`` towards ``end``: ``profile`` is (distance from ``start``, radius), its ends
    closed where the radius is zero. ``hollow_from`` is the index where the profile turns back inside (a nozzle's bore):
    collision and burial use the outside only."""
    a, b = np.asarray(start, dtype=float), np.asarray(end, dtype=float)
    mats = style.material("hull") if materials is None else materials
    turn = basis_from_z(b - a)
    mesh = lathe(profile, sides, mats, creases=creases).transformed(turn, a)
    outside = [p for p in profile[:hollow_from] if p[1] > 0.0]
    solid = lathe_solid(outside).transformed(turn, a)
    bore = list(profile[hollow_from:]) if hollow_from is not None else []
    return module(name, mesh, _round_shapes(name, a, b - a, list(profile[:hollow_from]), sides, bore), solid=solid, skin=skin)


def _round_shapes(name: str, start: np.ndarray, axis: np.ndarray, profile: Sequence[tuple[float, float]], sides: int,
                  bore: Sequence[tuple[float, float]] = (), max_points: int = col.MAX_HULL_POINTS) -> list[col.Shape]:
    """Collision that follows a round body's profile: one convex step per profile segment (a waist or a flange is not
    filled over), each cut into wedges about the axis when its two rings hold more corners than a hull may keep. A
    ``bore`` (a nozzle's inside) stays open: the length it runs is a ring of sectors round its narrowest radius."""
    # As few polygon sides as keep the corners within slack of the round surface (the polygon's flats touch it).
    widest = max(r for _, r in profile)
    sides = next((n for n in range(6, sides) if widest * (1.0 / np.cos(np.pi / n) - 1.0) <= CORNER_SLACK_M), sides)
    per_wedge = (max_points - 2) // 2 - 1  # polygon steps a wedge spans: two rings of corners plus the axis at each end
    wedges = 1 if 2 * sides <= max_points else -(-sides // per_wedge)
    bounds = np.linspace(0, sides, wedges + 1).round().astype(int)
    shapes: list[col.Shape] = []
    deep = min((d for d, _ in bore), default=np.inf)
    segments = []
    for (d0, r0), (d1, r1) in zip(profile, profile[1:], strict=False):
        if d1 > deep > d0:  # split where the bore begins
            rd = r0 + (r1 - r0) * (deep - d0) / (d1 - d0)
            segments += [((d0, r0), (deep, rd)), ((deep, rd), (d1, r1))]
        else:
            segments.append(((d0, r0), (d1, r1)))
    for (d0, r0), (d1, r1) in segments:
        if d1 - d0 <= 1e-6 or max(r0, r1) <= 0.0:
            continue  # a radial step: the segments either side already reach it
        if d0 >= deep - 1e-6:
            # In steps, each ring round the bore's radius at its inner end, so the wall stays covered and the open face is shallow.
            wall = sorted((d, r) for d, r in bore if r > 0.0)
            cuts = np.linspace(d0, d1, int(np.ceil((d1 - d0) / BORE_STEP_M)) + 1)
            for a_, b_ in zip(cuts, cuts[1:], strict=False):
                r_in = float(np.interp(a_, [d for d, _ in wall], [r for _, r in wall]))
                r_out = max(r0 + (r1 - r0) * (t - d0) / (d1 - d0) for t in (a_, b_))
                shapes += col.ring_sectors("", start, axis, r_in, r_out, a_, b_, BORE_SECTORS)
            continue
        rings = col.prism_points(start, axis, [(d0, r0), (d1, r1)], sides).reshape(2, sides, 3)
        if wedges == 1:
            groups = [rings.reshape(-1, 3)]
        else:
            unit = axis / np.linalg.norm(axis)
            on_axis = np.array([start + d0 * unit, start + d1 * unit])
            groups = [np.concatenate([rings[:, [k % sides for k in range(lo, hi + 1)]].reshape(-1, 3), on_axis])
                      for lo, hi in zip(bounds, bounds[1:], strict=False)]
        shapes += [col.hull("", g, max_points) for g in groups]
    if not shapes:
        raise ValueError(f"round body {name!r} has no length")
    return [q.renamed(f"{name}_{k}" if len(shapes) > 1 else name) for k, q in enumerate(shapes)]


def rod(name: str, start: Sequence[float], end: Sequence[float], radius: float, style: Style, role: str = "rcs") -> Module:
    """A thin mast between two points, its far end closed."""
    a, b = np.asarray(start, dtype=float), np.asarray(end, dtype=float)
    length = float(np.linalg.norm(b - a))
    mesh = lathe([(0.0, radius), (length, 0.7 * radius), (length, 0.0)], 6, style.material(role), creases={1}).transformed(basis_from_z(b - a), a)
    return module(name, mesh, [col.capsule_between(name, a, b, radius)], skin=SKIN_NONE, fine=0.5)


def compound(name: str, parts: Sequence[Module]) -> Module:
    """Several modules as one named part: their meshes, shapes, hardpoints and volumes together."""
    if not parts:
        raise ValueError(f"compound {name!r} needs a part")
    solids = [p.solid for p in parts if p.solid is not None]
    shapes = [s for p in parts for s in p.shapes]
    shapes = [s.renamed(f"{name}_{k}") for k, s in enumerate(shapes)] if len(shapes) > 1 else [s.renamed(name) for s in shapes]
    return module(name, Mesh.concatenate([p.part.mesh for p in parts]), shapes,
                  [h for p in parts for h in p.hardpoints], solid=union(*solids) if solids else None, skin=parts[0].skin,
                  fine=min(p.fine for p in parts))


__all__ = ["ROUND", "box", "compound", "convex", "prism", "rod", "round_body", "slab"]
