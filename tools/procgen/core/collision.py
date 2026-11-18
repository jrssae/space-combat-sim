"""Compound collision from parts (M7-T03, D73): the convex shapes a physics body is built from, per piece of an asset.

Each part names its shape: a box, a capsule, or the convex hull of its own points. A piece's shapes are merged down to a
budget, written into the manifest's ``collision.pieces`` (the game builds one body per piece from it), and checked against
the render mesh: every render triangle near a shape, no shape far outside the render mesh. The same shapes give the hit
volumes the native core sweeps (boxes and capsules only), so bolts, rams and turrets see what the physics body is.

The budget is chosen for Jolt, not forced by it: Jolt refuses a hull above 256 points, and its cost per contact grows with
the points and with the shapes a body's compound tree holds.
"""

from __future__ import annotations

import itertools
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

import numpy as np

MAX_SHAPES_PER_PIECE = 128
MAX_HULL_POINTS = 32
JSON_DIGITS = 5
BOX, CAPSULE, HULL = "box", "capsule", "hull"
KINDS = (BOX, CAPSULE, HULL)
FLAT = 1e-7  # of a point set's size: thinner than this is no volume


@dataclass(frozen=True)
class Budget:
    """The most shapes one piece's body may hold and the most points one of its hulls may have."""

    max_shapes: int = MAX_SHAPES_PER_PIECE
    max_hull_points: int = MAX_HULL_POINTS

    def __post_init__(self) -> None:
        if self.max_shapes < 1 or self.max_hull_points < 4:
            raise ValueError("a budget needs at least 1 shape and 4 points a hull")


def _vec(v: Sequence[float]) -> np.ndarray:
    return np.asarray(v, dtype=float).reshape(3)


def _r(v: Any, digits: int = JSON_DIGITS) -> list[float]:
    return [round(float(x), digits) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


@dataclass(frozen=True)
class Faces:
    """A convex hull's faces: outward planes ``normals @ p <= offsets``, each face's corners in order, and the edges."""

    normals: np.ndarray
    offsets: np.ndarray
    polygons: tuple[np.ndarray, ...]
    edges: np.ndarray


def hull_faces(points: np.ndarray) -> Faces:
    """The faces of a small point set's convex hull (every triple is tried, so keep it to a budgeted hull's points)."""
    pts = np.asarray(points, dtype=float)
    size = float(np.linalg.norm(pts.max(axis=0) - pts.min(axis=0))) or 1.0
    tol = 1e-6 * size
    triples = np.array(list(itertools.combinations(range(len(pts)), 3)), dtype=int).reshape(-1, 3)
    a, b, c = pts[triples[:, 0]], pts[triples[:, 1]], pts[triples[:, 2]]
    normals = np.cross(b - a, c - a)
    lengths = np.linalg.norm(normals, axis=1)
    keep = lengths > FLAT * size * size
    normals, a = normals[keep] / lengths[keep, None], a[keep]
    offsets = np.einsum("ij,ij->i", normals, a)
    side = pts @ normals.T - offsets  # points x planes
    below, above = np.all(side <= tol, axis=0), np.all(side >= -tol, axis=0)
    flat = below & above
    if flat.any() or not (below | above).any():
        raise ValueError("a convex hull needs points that span a volume")
    normals = np.concatenate([normals[below], -normals[above]])
    offsets = np.concatenate([offsets[below], -offsets[above]])
    # One plane per face: the triples of a face with more than three corners all name the same plane.
    keys = np.round(np.column_stack([normals, offsets / size]), 6) + 0.0
    _, first = np.unique(keys, axis=0, return_index=True)
    first = np.sort(first)
    normals, offsets = normals[first], offsets[first]
    polygons, edges = [], set()
    for n, d in zip(normals, offsets):
        on = np.flatnonzero(np.abs(pts @ n - d) <= tol)
        mid = pts[on].mean(axis=0)
        u = np.cross(n, [1.0, 0.0, 0.0] if abs(n[0]) < 0.9 else [0.0, 1.0, 0.0])
        u /= np.linalg.norm(u)
        w = np.cross(n, u)
        rel = pts[on] - mid
        ring = on[np.argsort(np.arctan2(rel @ w, rel @ u), kind="stable")]
        polygons.append(ring)
        for i, j in zip(ring, np.roll(ring, -1)):
            edges.add((min(int(i), int(j)), max(int(i), int(j))))
    return Faces(normals, offsets, tuple(polygons), np.array(sorted(edges), dtype=int).reshape(-1, 2))


def convex_points(points: np.ndarray, max_points: int = MAX_HULL_POINTS) -> tuple[np.ndarray, float]:
    """At most ``max_points`` corners of the points' convex hull, and how far the farthest point left out lies outside them.

    Starts from the extremes along the axes and adds the point farthest outside the hull so far, so the corners kept are
    the ones that matter most to the shape.
    """
    pts = np.unique(np.asarray(points, dtype=float).reshape(-1, 3), axis=0)
    if len(pts) < 4:
        raise ValueError("a convex hull needs at least 4 points")
    size = float(np.linalg.norm(pts.max(axis=0) - pts.min(axis=0)))
    chosen: list[int] = []
    for axis in range(3):
        for index in (int(np.argmin(pts[:, axis])), int(np.argmax(pts[:, axis]))):
            if all(np.linalg.norm(pts[index] - pts[other]) > FLAT * size for other in chosen):
                chosen.append(index)
    while True:
        try:
            faces = hull_faces(pts[chosen])
        except ValueError:
            # The corners so far are flat: the point farthest from their plane gives them a volume.
            base = pts[chosen] - pts[chosen].mean(axis=0)
            normal = np.linalg.svd(base)[2][-1]
            away = np.abs((pts - pts[chosen].mean(axis=0)) @ normal)
            index = int(np.argmax(away))
            if away[index] <= FLAT * size or index in chosen:
                raise ValueError("a convex hull needs points that span a volume") from None
            chosen.append(index)
            continue
        outside = (pts @ faces.normals.T - faces.offsets).max(axis=1)
        index = int(np.argmax(outside))
        residual = max(float(outside[index]), 0.0)
        if residual <= 1e-9 * size or len(chosen) >= max_points:
            return pts[chosen], residual
        chosen.append(index)


@dataclass(frozen=True)
class Shape:
    """One convex collision shape in its piece's frame. A box has ``size`` (full extents on its basis' axes), a capsule
    ``radius`` and ``height`` (total, along its basis' z), a hull its corner ``points``."""

    name: str
    kind: str
    center: np.ndarray
    basis: np.ndarray
    size: np.ndarray | None = None
    radius: float = 0.0
    height: float = 0.0
    points: np.ndarray | None = None
    faces: Faces | None = None

    @property
    def half_segment(self) -> float:
        return max(0.5 * self.height - self.radius, 0.0)

    def corners(self) -> np.ndarray:
        """Points whose convex hull is the shape (a capsule's: rings on its surface, a little inside it)."""
        if self.kind == HULL:
            return self.points
        if self.kind == BOX:
            signs = np.array(list(itertools.product((-0.5, 0.5), repeat=3)))
            return self.center + (signs * self.size) @ self.basis.T
        local = []
        angles = np.arange(8) * (np.pi / 4.0)
        for sign in (-1.0, 1.0):
            local.append([0.0, 0.0, sign * (self.half_segment + self.radius)])
            for lift in (0.0, np.pi / 4.0):
                ring_r, z = self.radius * np.cos(lift), sign * (self.half_segment + self.radius * np.sin(lift))
                local += [[ring_r * np.cos(t), ring_r * np.sin(t), z] for t in angles]
        return self.center + np.array(local) @ self.basis.T

    def probes(self) -> np.ndarray:
        """Points on the shape's surface, where it reaches farthest: the corners plus each face's and edge's middle."""
        if self.kind == BOX:
            grid = np.array([g for g in itertools.product((-0.5, 0.0, 0.5), repeat=3) if any(g)])
            return self.center + (grid * self.size) @ self.basis.T
        if self.kind == CAPSULE:
            return self.corners()
        mids = [self.points[ring].mean(axis=0) for ring in self.faces.polygons]
        return np.concatenate([self.points, np.array(mids)])

    def bounds(self) -> tuple[np.ndarray, np.ndarray]:
        if self.kind == CAPSULE:
            ends = self.center + np.outer((-self.half_segment, self.half_segment), self.basis[:, 2])
            return ends.min(axis=0) - self.radius, ends.max(axis=0) + self.radius
        corners = self.corners()
        return corners.min(axis=0), corners.max(axis=0)

    def distance(self, points: np.ndarray) -> np.ndarray:
        """How far each point is outside the shape (0 inside or on it)."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        if self.kind == BOX:
            q = np.abs((p - self.center) @ self.basis) - 0.5 * self.size
            return np.linalg.norm(np.maximum(q, 0.0), axis=1)
        if self.kind == CAPSULE:
            local = (p - self.center) @ self.basis
            local[:, 2] -= np.clip(local[:, 2], -self.half_segment, self.half_segment)
            return np.maximum(np.linalg.norm(local, axis=1) - self.radius, 0.0)
        out = np.zeros(len(p))
        outside = (p @ self.faces.normals.T - self.faces.offsets).max(axis=1) > 0.0
        if outside.any():
            out[outside] = self._hull_distance(p[outside])
        return out

    def _hull_distance(self, p: np.ndarray) -> np.ndarray:
        """Outside points' distance to the hull: to the face straight below them, or else to the nearest edge."""
        a, b = self.points[self.faces.edges[:, 0]], self.points[self.faces.edges[:, 1]]
        ab = b - a
        along = np.einsum("pej,ej->pe", p[:, None, :] - a[None], ab)
        t = np.clip(along / np.maximum(np.einsum("ej,ej->e", ab, ab), 1e-300), 0.0, 1.0)
        best = np.linalg.norm(p[:, None, :] - (a[None] + t[:, :, None] * ab[None]), axis=2).min(axis=1)
        for n, d, ring in zip(self.faces.normals, self.faces.offsets, self.faces.polygons):
            corners = self.points[ring]
            sides = np.cross(np.roll(corners, -1, axis=0) - corners, n)  # in the face's plane, pointing out of it
            over = np.all(np.einsum("pej,ej->pe", p[:, None, :] - corners[None], sides) <= 0.0, axis=1)
            best[over] = np.minimum(best[over], np.abs(p[over] @ n - d))
        return best

    def to_json(self, digits: int = JSON_DIGITS) -> dict[str, Any]:
        """The shape as a manifest entry; a box and a capsule read as a ``hardpoints.json`` collision entry does."""
        if self.kind == HULL:
            return {"name": self.name, "type": HULL, "points": [_r(p, digits) for p in self.points]}
        out: dict[str, Any] = {"name": self.name, "type": self.kind, "position": _r(self.center, digits)}
        if self.kind == BOX:
            out["size"] = _r(self.size, digits)
        else:
            out["radius"], out["height"], out["axis"] = round(self.radius, digits), round(self.height, digits), "z"
        out["basis"] = {axis: _r(self.basis[:, k], digits) for k, axis in enumerate("xyz")}
        return out

    def hit_volume(self) -> Shape:
        """The box or capsule the native hit sweep uses for this shape: itself, or the tightest box found around a hull."""
        if self.kind != HULL:
            return self
        best: Shape | None = None
        for basis in (np.eye(3), _principal_axes(self.points)):
            local = self.points @ basis
            lo, hi = local.min(axis=0), local.max(axis=0)
            fitted = box(self.name, basis @ (0.5 * (lo + hi)), hi - lo, basis)
            if best is None or float(np.prod(fitted.size)) < float(np.prod(best.size)) * (1.0 - 1e-9):
                best = fitted
        return best


def _principal_axes(points: np.ndarray) -> np.ndarray:
    """The points' principal axes as a rotation, each axis signed the same way on every run."""
    axes = np.linalg.svd(points - points.mean(axis=0))[2].T.copy()
    for k in range(3):
        if axes[np.argmax(np.abs(axes[:, k])), k] < 0.0:
            axes[:, k] = -axes[:, k]
    if np.linalg.det(axes) < 0.0:
        axes[:, 2] = -axes[:, 2]
    return axes


def _rotation(basis: Sequence[Sequence[float]] | None) -> np.ndarray:
    out = np.eye(3) if basis is None else np.asarray(basis, dtype=float).reshape(3, 3)
    if not np.allclose(out.T @ out, np.eye(3), atol=1e-6) or np.linalg.det(out) < 0.0:
        raise ValueError("a collision shape's basis must be a rotation")
    return out


def box(name: str, center: Sequence[float], size: Sequence[float], basis: Sequence[Sequence[float]] | None = None) -> Shape:
    """A box of full extents ``size`` along the columns of ``basis``."""
    size_v = _vec(size)
    if np.any(size_v <= 0.0):
        raise ValueError(f"box {name!r} needs a positive size")
    return Shape(name, BOX, _vec(center), _rotation(basis), size=size_v)


def capsule(name: str, center: Sequence[float], radius: float, height: float,
            basis: Sequence[Sequence[float]] | None = None) -> Shape:
    """A capsule along the basis' z: ``height`` is its total length, caps included (at least a sphere's)."""
    if radius <= 0.0:
        raise ValueError(f"capsule {name!r} needs a positive radius")
    return Shape(name, CAPSULE, _vec(center), _rotation(basis), radius=float(radius), height=max(float(height), 2.0 * radius))


def hull(name: str, points: np.ndarray, max_points: int = MAX_HULL_POINTS) -> Shape:
    """The convex hull of ``points``, kept to ``max_points`` corners."""
    corners, _ = convex_points(points, max_points)
    return Shape(name, HULL, corners.mean(axis=0), np.eye(3), points=corners, faces=hull_faces(corners))


def from_primitive(primitive: Any, name: str, offset: Sequence[float] = (0.0, 0.0, 0.0)) -> Shape:
    """A part's box or capsule primitive (``parts.Collision``) as a shape, moved by ``-offset`` into the piece's frame."""
    center = _vec(primitive.center) - _vec(offset)
    if primitive.kind == BOX:
        return box(name, center, primitive.size, primitive.basis)
    return capsule(name, center, primitive.radius, primitive.height, primitive.basis)


def shape_for_part(part: Any, offset: Sequence[float] = (0.0, 0.0, 0.0), fit_m: float = 0.5) -> Shape:
    """The shape a part (``parts.Part``) gets when it does not pick one: its own capsule if that holds every point of its
    mesh within ``fit_m`` (a round tank is a capsule, not a faceted hull), else the convex hull of its points."""
    points = np.asarray(part.mesh.vertices, dtype=float) - _vec(offset)
    for primitive in part.collision:
        if primitive.kind == CAPSULE:
            fitted = from_primitive(primitive, part.name, offset)
            if float(fitted.distance(points).max()) <= fit_m:
                return fitted
    return hull(part.name, points)


def merge_to_budget(shapes: Sequence[Shape], budget: Budget = Budget()) -> list[Shape]:
    """The shapes, joined pairwise into hulls until they fit the budget. The pair joined is the one whose common bounding
    box adds the least empty space, so neighbours go first and the body grows as little as it can."""
    out = list(shapes)
    while len(out) > budget.max_shapes:
        lo = np.array([s.bounds()[0] for s in out])
        hi = np.array([s.bounds()[1] for s in out])
        own = np.prod(hi - lo, axis=1)
        joint = np.prod(np.maximum(hi[:, None], hi[None]) - np.minimum(lo[:, None], lo[None]), axis=2)
        added = joint - own[:, None] - own[None]
        added[np.tril_indices(len(out))] = np.inf
        i, j = (int(k) for k in np.unravel_index(int(np.argmin(added)), added.shape))
        joined = hull(out[i].name, np.concatenate([out[i].corners(), out[j].corners()]), budget.max_hull_points)
        out[i] = joined
        del out[j]
    return out


def check_budget(name: str, shapes: Sequence[Shape], budget: Budget = Budget()) -> None:
    """Raise unless the piece's shapes fit the budget."""
    if len(shapes) > budget.max_shapes:
        raise ValueError(f"piece {name!r} has {len(shapes)} collision shapes, the budget is {budget.max_shapes}")
    for shape in shapes:
        if shape.kind == HULL and len(shape.points) > budget.max_hull_points:
            raise ValueError(f"hull {shape.name!r} of piece {name!r} has {len(shape.points)} points, the budget is {budget.max_hull_points}")


def piece_entry(name: str, shapes: Sequence[Shape], budget: Budget = Budget()) -> dict[str, Any]:
    """One piece of the manifest's ``collision.pieces``: its shapes inside the budget, the hit volumes fitted to them, and
    the box and sphere that bound them."""
    if not shapes:
        raise ValueError(f"piece {name!r} has no collision shapes")
    merged = merge_to_budget(shapes, budget)
    check_budget(name, merged, budget)
    lo = np.min([s.bounds()[0] for s in merged], axis=0)
    hi = np.max([s.bounds()[1] for s in merged], axis=0)
    mid = 0.5 * (lo + hi)
    reach = max(float(np.linalg.norm(s.probes() - mid, axis=1).max()) for s in merged)
    return {
        "name": name,
        "aabb_min": _r(lo),
        "aabb_max": _r(hi),
        "bound": {"center": _r(mid), "radius": round(reach, JSON_DIGITS)},
        "shapes": [s.to_json() for s in merged],
        "hit_volumes": [s.hit_volume().to_json() for s in merged],
    }


def section(pieces: Mapping[str, Sequence[Shape]], budget: Budget = Budget()) -> dict[str, Any]:
    """The manifest's ``collision`` section: the budget and one entry per piece of the asset, in the order given."""
    return {
        "max_shapes": budget.max_shapes,
        "max_hull_points": budget.max_hull_points,
        "pieces": [piece_entry(name, shapes, budget) for name, shapes in pieces.items()],
    }


def shapes_from_entry(entry: Mapping[str, Any], key: str = "shapes") -> list[Shape]:
    """A piece entry's shapes (or its ``hit_volumes``) read back from the manifest."""
    out = []
    for item in entry[key]:
        if item["type"] == HULL:
            out.append(hull(item["name"], np.array(item["points"]), max(len(item["points"]), 4)))
            continue
        basis = np.column_stack([item["basis"][axis] for axis in "xyz"])
        # Rounded to the manifest's digits, the axes are a hair off a rotation: square them up again.
        u, _, vt = np.linalg.svd(basis)
        basis = u @ vt
        if item["type"] == BOX:
            out.append(box(item["name"], item["position"], item["size"], basis))
        else:
            out.append(capsule(item["name"], item["position"], item["radius"], item["height"], basis))
    return out


# --- coverage ---------------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Coverage:
    """How well shapes fit a render mesh: ``max_gap_m`` is the render point farthest outside every shape, ``max_excess_m``
    the shape point farthest from the render surface; each with where it is."""

    step_m: float
    max_gap_m: float
    gap_at: tuple[float, float, float]
    max_excess_m: float
    excess_shape: str

    def check(self, gap_tolerance_m: float, excess_tolerance_m: float) -> None:
        """Raise unless the render mesh is covered within the gap tolerance and no shape strays past the excess one."""
        if self.max_gap_m > gap_tolerance_m:
            raise ValueError(f"render surface at {self.gap_at} is {self.max_gap_m:.3f} m from any collision shape (tolerance {gap_tolerance_m} m)")
        if self.max_excess_m > excess_tolerance_m:
            raise ValueError(f"collision shape {self.excess_shape!r} reaches {self.max_excess_m:.3f} m off the render surface (tolerance {excess_tolerance_m} m)")


def surface_probes(triangles: np.ndarray, step: float) -> np.ndarray:
    """Points on every triangle (``(n, 3, 3)``), no farther apart than about ``step``: its corners and a lattice across it."""
    tris = np.asarray(triangles, dtype=float).reshape(-1, 3, 3)
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    longest = np.max([np.linalg.norm(b - a, axis=1), np.linalg.norm(c - b, axis=1), np.linalg.norm(a - c, axis=1)], axis=0)
    cuts = np.maximum(np.ceil(longest / step).astype(int), 1)
    out = [np.unique(tris.reshape(-1, 3), axis=0)]
    for n in np.unique(cuts):
        if n == 1:
            continue
        which = cuts == n
        lattice = np.array([(i, j) for i in range(n + 1) for j in range(n + 1 - i) if (i, j) not in ((0, 0), (n, 0), (0, n))]) / n
        u, v = lattice[:, 0][None, :, None], lattice[:, 1][None, :, None]
        out.append((a[which][:, None] * (1.0 - u - v) + b[which][:, None] * u + c[which][:, None] * v).reshape(-1, 3))
    return np.concatenate(out)


def _gaps(points: np.ndarray, shapes: Sequence[Shape], reach: float) -> np.ndarray:
    """Each point's distance to the nearest shape. Shapes are asked only about points near their box; a point near none
    is then measured against them all."""
    gap = np.full(len(points), np.inf)
    for shape in shapes:
        lo, hi = shape.bounds()
        near = np.flatnonzero(np.all((points >= lo - reach) & (points <= hi + reach), axis=1))
        if len(near):
            gap[near] = np.minimum(gap[near], shape.distance(points[near]))
    far = np.flatnonzero(gap > reach)
    for shape in shapes if len(far) else ():
        gap[far] = np.minimum(gap[far], shape.distance(points[far]))
    return gap


def _nearest(points: np.ndarray, cloud: np.ndarray, reach: float) -> np.ndarray:
    """Each point's distance to the nearest point of ``cloud``. The cloud is binned into cells of ``reach`` so a point near
    it looks only at its neighbour cells; a point farther than ``reach`` is measured against the whole cloud."""
    cells = np.floor(cloud / reach).astype(np.int64)
    low = cells.min(axis=0) - 1
    span = cells.max(axis=0) - low + 2

    def key(c: np.ndarray) -> np.ndarray:
        c = c - low
        return (c[..., 0] * span[1] + c[..., 1]) * span[2] + c[..., 2]

    order = np.argsort(key(cells), kind="stable")
    sorted_keys = key(cells)[order]
    around = np.array(list(itertools.product((-1, 0, 1), repeat=3)))
    out = np.full(len(points), np.inf)
    own = np.clip(np.floor(points / reach).astype(np.int64), low, low + span - 1)
    for cell in np.unique(own, axis=0):
        mine = np.flatnonzero(np.all(own == cell, axis=1))
        keys = key(cell + around)
        spans = zip(np.searchsorted(sorted_keys, keys, "left"), np.searchsorted(sorted_keys, keys, "right"))
        found = np.concatenate([order[i:j] for i, j in spans])
        if len(found):
            out[mine] = np.linalg.norm(points[mine][:, None] - cloud[found][None], axis=2).min(axis=1)
    for index in np.flatnonzero(out > reach):
        out[index] = np.linalg.norm(cloud - points[index], axis=1).min()
    return out


def coverage(triangles: np.ndarray, shapes: Sequence[Shape], step: float) -> Coverage:
    """Measure the shapes against the render triangles (``(n, 3, 3)``, the shapes' frame), probed every ``step``: the widest
    gap and the farthest excess. The excess is measured to the probes, so it can read up to ``step`` long."""
    probes = surface_probes(triangles, step)
    gap = _gaps(probes, shapes, 2.0 * step)
    worst = int(np.argmax(gap))
    own = [shape.probes() for shape in shapes]
    off = _nearest(np.concatenate(own), probes, 2.0 * step)
    farthest = int(np.argmax(off))
    owner = int(np.searchsorted(np.cumsum([len(o) for o in own]), farthest, "right"))
    gap_at = tuple(round(float(x), 3) for x in probes[worst])
    return Coverage(step, float(gap[worst]), gap_at, float(off[farthest]), shapes[owner].name)
