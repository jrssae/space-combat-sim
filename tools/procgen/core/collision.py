"""Compound collision from parts (M7's D73, built in M12-T19): a hull's parts each name a convex shape, the shapes are
grouped by the asset's pieces (a body, a section, a break-up chunk) inside a budget, and a coverage check measures them
against the render mesh. The manifest's ``collision`` section carries the result; the game builds one body per piece from it.

A shape is a ``box``, a ``capsule`` (both as ``parts.Collision`` writes them) or a ``hull`` (the convex hull of a few points).
A concave part (a ring, a rim) is cut into several convex shapes (:func:`ring_sectors`), so its opening stays open.

Coverage, both ways (:func:`coverage`): every point of the render surface lies within ``tolerance_m`` of a shape, and no
point of the shapes' joint outer surface is further than ``reach_m`` from the render surface. A hull's distance is measured to its face planes, which
is exact inside and across a face and a little short past an edge or a corner.

Numpy only, and deterministic: the same parts give the same section, byte for byte.
"""

from __future__ import annotations

import itertools
import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

import numpy as np

from .geometry import mirror_matrix

BOX, CAPSULE, HULL = "box", "capsule", "hull"
KINDS = (BOX, CAPSULE, HULL)
JSON_DIGITS = 5
PLANE_TOL = 1e-7  # of the hull's size: how far a point may stand past a face plane and still count as on it
FLAT_TOL = 1e-6  # of the hull's size: thinner than this is a flat point set, not a hull
EXACT_POINTS = 72  # up to this many candidate points the hull's faces are found by trying every triple
FIXED_DIRECTIONS = tuple(d for d in itertools.product((-1.0, 0.0, 1.0), repeat=3) if any(d))


@dataclass(frozen=True)
class Budget:
    """What one body may carry (Jolt's compound shapes): how many convex shapes, and how many points one hull."""

    max_pieces: int = 64
    max_hull_points: int = 32

    def __post_init__(self) -> None:
        if self.max_pieces < 1 or self.max_hull_points < 4:
            raise ValueError("a budget needs at least one piece and four points a hull")


# --- convex hulls of small point sets ----------------------------------------------------------------------------------
def support_directions(count: int) -> np.ndarray:
    """Unit directions spread over the sphere: the 26 axis and diagonal ones (so a box keeps its corners), then a spiral."""
    fixed = np.array(FIXED_DIRECTIONS)
    fixed /= np.linalg.norm(fixed, axis=1, keepdims=True)
    if count < len(fixed):
        fixed = fixed[:0]  # too few to take them all: an even spiral alone
    extra = max(int(count) - len(fixed), 0)
    k = np.arange(extra) + 0.5
    polar = np.arccos(1.0 - 2.0 * k / max(extra, 1))
    turn = math.pi * (1.0 + math.sqrt(5.0)) * k
    spiral = np.stack([np.cos(turn) * np.sin(polar), np.sin(turn) * np.sin(polar), np.cos(polar)], axis=1)
    return np.concatenate([fixed, spiral])


def _unique_rows(points: np.ndarray) -> np.ndarray:
    p = np.asarray(points, dtype=float).reshape(-1, 3)
    _, first = np.unique(np.round(p, 6), axis=0, return_index=True)
    return p[np.sort(first)]


def _extremes(points: np.ndarray, count: int) -> np.ndarray:
    """The points furthest along ``count`` directions: corners of the hull, in the points' own order."""
    picked = np.unique(np.argmax(points @ support_directions(count).T, axis=0))
    return points[picked]


def _size(points: np.ndarray) -> float:
    return float(np.ptp(points, axis=0).max()) or 1.0


def hull_faces(points: np.ndarray) -> tuple[np.ndarray, np.ndarray, list[np.ndarray]]:
    """The faces of the convex hull of a small point set: outward unit normals ``(k, 3)``, offsets ``(k,)`` (a point is inside
    where ``n . p <= d`` for every face) and each face's corners as indices into ``points``, in order round the face."""
    p = np.asarray(points, dtype=float).reshape(-1, 3)
    size = _size(p)
    centre = p.mean(axis=0)
    if len(p) < 4 or np.linalg.svd(p - centre, compute_uv=False)[-1] < FLAT_TOL * size:
        raise ValueError("a hull needs four points that are not in one plane; use a box for a flat part")
    triples = np.array(list(itertools.combinations(range(len(p)), 3)))
    a, b, c = p[triples[:, 0]], p[triples[:, 1]], p[triples[:, 2]]
    normal = np.cross(b - a, c - a)
    length = np.linalg.norm(normal, axis=1)
    solid = length > 1e-9 * size * size
    normal, a = normal[solid] / length[solid, None], a[solid]
    offset = np.einsum("ij,ij->i", normal, a)
    inward = normal @ centre > offset
    normal[inward], offset[inward] = -normal[inward], -offset[inward]
    supporting = (p @ normal.T - offset).max(axis=0) <= PLANE_TOL * size
    normals: list[np.ndarray] = []
    offsets: list[float] = []
    for n, d in zip(normal[supporting], offset[supporting], strict=True):
        if not any(float(n @ m) > 1.0 - 1e-9 and abs(d - e) < 1e-6 * size for m, e in zip(normals, offsets, strict=True)):
            normals.append(n)
            offsets.append(float(d))
    n_arr, d_arr = np.array(normals), np.array(offsets)
    faces = []
    for n, d in zip(n_arr, d_arr, strict=True):
        on = np.flatnonzero(np.abs(p @ n - d) <= 10.0 * PLANE_TOL * size)
        mid = p[on].mean(axis=0)
        u = np.cross(n, [1.0, 0.0, 0.0] if abs(n[0]) < 0.9 else [0.0, 1.0, 0.0])
        u /= np.linalg.norm(u)
        v = np.cross(n, u)
        faces.append(on[np.argsort(np.arctan2((p[on] - mid) @ v, (p[on] - mid) @ u))])
    return n_arr, d_arr, faces


def hull_corners(points: np.ndarray) -> np.ndarray:
    """The points that are corners of their own convex hull (points inside it or inside a face are dropped)."""
    p = _unique_rows(points)
    normals, offsets, _ = hull_faces(p)
    on_faces = (np.abs(p @ normals.T - offsets) <= 10.0 * PLANE_TOL * _size(p)).sum(axis=1)
    return p[on_faces >= 3]


def reduce_points(points: np.ndarray, max_points: int) -> np.ndarray:
    """At most ``max_points`` corners for the hull of ``points``. A hull that needs more loses its least prominent corners
    (the furthest points along fewer directions are kept), so it shrinks a little: the coverage check says by how much."""
    p = _unique_rows(points)
    if len(p) > EXACT_POINTS:
        p = _extremes(p, 16 * EXACT_POINTS)
    if len(p) <= EXACT_POINTS:
        p = hull_corners(p)
    if len(p) <= max_points:
        return p
    for factor in (8.0, 6.0, 4.0, 3.0, 2.0, 1.5, 1.0):
        kept = _extremes(p, int(max_points * factor))
        if len(kept) <= max_points:
            return kept
    return _extremes(p, max_points)


# --- shapes ------------------------------------------------------------------------------------------------------------
@dataclass(frozen=True, eq=False)
class Shape:
    """One convex collision shape in the frame of the part it was made for. ``basis`` columns are the local axes (a rotation);
    a box has ``size`` (full extents), a capsule ``radius`` and ``height`` (its whole length along local z), a hull ``points``."""

    kind: str
    name: str
    center: np.ndarray
    basis: np.ndarray
    size: np.ndarray | None = None
    radius: float = 0.0
    height: float = 0.0
    points: np.ndarray | None = None

    def __post_init__(self) -> None:
        if self.kind not in KINDS:
            raise ValueError(f"unknown collision shape {self.kind!r}")
        object.__setattr__(self, "center", np.asarray(self.center, dtype=float).reshape(3))
        object.__setattr__(self, "basis", np.asarray(self.basis, dtype=float).reshape(3, 3))
        if self.kind == BOX:
            size = np.asarray(self.size, dtype=float).reshape(3)
            if np.any(size <= 0.0):
                raise ValueError(f"box {self.name!r} needs a positive size")
            object.__setattr__(self, "size", size)
        elif self.kind == CAPSULE:
            if self.radius <= 0.0 or self.height < 2.0 * self.radius:
                raise ValueError(f"capsule {self.name!r} needs a radius and a height of at least twice it")
        else:
            pts = np.asarray(self.points, dtype=float).reshape(-1, 3)
            object.__setattr__(self, "points", pts)
            object.__setattr__(self, "_faces", hull_faces(pts))

    # -- makers --
    @staticmethod
    def box(name: str, center: Sequence[float], size: Sequence[float], basis: np.ndarray | None = None) -> Shape:
        return Shape(BOX, name, np.asarray(center, dtype=float), np.eye(3) if basis is None else basis, size=np.asarray(size, dtype=float))

    @staticmethod
    def box_around(name: str, points: np.ndarray, basis: np.ndarray | None = None) -> Shape:
        """The tightest box round ``points`` with its sides along ``basis`` (the frame's axes by default)."""
        b = np.eye(3) if basis is None else np.asarray(basis, dtype=float)
        local = np.asarray(points, dtype=float).reshape(-1, 3) @ b
        lo, hi = local.min(axis=0), local.max(axis=0)
        return Shape.box(name, b @ (0.5 * (lo + hi)), np.maximum(hi - lo, 1e-6), b)

    @staticmethod
    def capsule(name: str, a: Sequence[float], b: Sequence[float], radius: float) -> Shape:
        """A round bar between two points: its half-sphere ends are centred on them."""
        a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
        axis = b - a
        length = float(np.linalg.norm(axis))
        if length == 0.0:
            raise ValueError(f"capsule {name!r} needs two different end points")
        z = axis / length
        x = np.cross([0.0, 1.0, 0.0] if abs(z[1]) < 0.9 else [1.0, 0.0, 0.0], z)
        x /= np.linalg.norm(x)
        return Shape(CAPSULE, name, 0.5 * (a + b), np.stack([x, np.cross(z, x), z], axis=1), radius=float(radius),
                     height=length + 2.0 * float(radius))

    @staticmethod
    def hull(name: str, points: np.ndarray, max_points: int = Budget.max_hull_points) -> Shape:
        """The convex hull of ``points``, cut down to ``max_points`` corners."""
        pts = reduce_points(points, max_points)
        return Shape(HULL, name, pts.mean(axis=0), np.eye(3), points=pts)

    # -- moves --
    def transformed(self, rotation: np.ndarray, translation: Sequence[float] = (0.0, 0.0, 0.0)) -> Shape:
        r, t = np.asarray(rotation, dtype=float), np.asarray(translation, dtype=float)
        if self.kind == HULL:
            pts = self.points @ r.T + t
            return Shape(HULL, self.name, pts.mean(axis=0), np.eye(3), points=pts)
        basis = r @ self.basis
        if np.linalg.det(basis) < 0.0:
            basis = basis @ np.diag([-1.0, 1.0, 1.0])  # a mirrored box or capsule is the same shape with one local axis turned
        return Shape(self.kind, self.name, r @ self.center + t, basis, self.size, self.radius, self.height)

    def translated(self, offset: Sequence[float]) -> Shape:
        return self.transformed(np.eye(3), offset)

    def mirrored(self, axis: str = "x") -> Shape:
        return self.transformed(mirror_matrix(axis))

    def renamed(self, name: str) -> Shape:
        return Shape(self.kind, name, self.center, self.basis, self.size, self.radius, self.height, self.points)

    # -- measures --
    def distance(self, points: np.ndarray) -> np.ndarray:
        """Signed distance of each point to the shape: negative inside. Exact for a box and a capsule; a hull's is to its
        nearest face plane (short of the true distance past an edge)."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        if self.kind == HULL:
            normals, offsets, _ = self._faces
            return (p @ normals.T - offsets).max(axis=1)
        local = (p - self.center) @ self.basis
        if self.kind == BOX:
            q = np.abs(local) - 0.5 * self.size
            return np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0)
        half = 0.5 * self.height - self.radius
        along = np.clip(local[:, 2], -half, half)
        return np.sqrt(local[:, 0] ** 2 + local[:, 1] ** 2 + (local[:, 2] - along) ** 2) - self.radius

    def corners(self) -> np.ndarray:
        """Points whose hull is the shape (a capsule's is a faceted bar just inside it)."""
        if self.kind == HULL:
            return self.points
        if self.kind == BOX:
            signs = np.array(list(itertools.product((-0.5, 0.5), repeat=3)))
            return self.center + (signs * self.size) @ self.basis.T
        half = 0.5 * self.height - self.radius
        turn = np.arange(8) * (math.pi / 4.0)
        rows = [(half, 1.0), (half + 0.7071 * self.radius, 0.7071), (-half, 1.0), (-half - 0.7071 * self.radius, 0.7071)]
        local = [[self.radius * k * math.cos(t), self.radius * k * math.sin(t), z] for z, k in rows for t in turn]
        local += [[0.0, 0.0, half + self.radius], [0.0, 0.0, -half - self.radius]]
        return self.center + np.array(local) @ self.basis.T

    def bounds(self) -> tuple[np.ndarray, np.ndarray]:
        if self.kind == CAPSULE:
            half = (0.5 * self.height - self.radius) * self.basis[:, 2]
            ends = np.array([self.center + half, self.center - half])
            return ends.min(axis=0) - self.radius, ends.max(axis=0) + self.radius
        c = self.corners()
        return c.min(axis=0), c.max(axis=0)

    def bound_radius(self) -> float:
        """The radius of a sphere round ``center`` that holds the shape (the broad phase of the native hit sweep)."""
        if self.kind == CAPSULE:
            return 0.5 * self.height
        return float(np.linalg.norm(self.corners() - self.center, axis=1).max())

    def volume(self) -> float:
        if self.kind == BOX:
            return float(np.prod(self.size))
        if self.kind == CAPSULE:
            return math.pi * self.radius**2 * (self.height - 2.0 * self.radius) + 4.0 / 3.0 * math.pi * self.radius**3
        _, _, faces = self._faces
        inside = self.points.mean(axis=0)
        total = 0.0
        for face in faces:
            v = self.points[face] - inside
            for k in range(1, len(face) - 1):
                total += abs(float(np.dot(v[0], np.cross(v[k], v[k + 1])))) / 6.0
        return total

    def surface_points(self, spacing: float) -> np.ndarray:
        """Points on the shape's surface about ``spacing`` apart (its corners and edges among them)."""
        if self.kind == CAPSULE:
            return self._capsule_surface(spacing)
        if self.kind == BOX:
            c = self.corners()
            quads = [(0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)]
            return np.concatenate([_polygon_points(c[list(q)], spacing) for q in quads])
        _, _, faces = self._faces
        return np.concatenate([_polygon_points(self.points[face], spacing) for face in faces])

    def _capsule_surface(self, spacing: float) -> np.ndarray:
        half = 0.5 * self.height - self.radius
        around = max(8, math.ceil(2.0 * math.pi * self.radius / spacing))
        turn = np.arange(around) * (2.0 * math.pi / around)
        rows = [(z, 1.0) for z in np.linspace(-half, half, max(2, math.ceil(2.0 * half / spacing) + 1))]
        for lat in np.linspace(0.0, 0.5 * math.pi, max(2, math.ceil(0.5 * math.pi * self.radius / spacing) + 1))[1:]:
            rows += [(half + self.radius * math.sin(lat), math.cos(lat)), (-half - self.radius * math.sin(lat), math.cos(lat))]
        local = np.array([[self.radius * k * math.cos(t), self.radius * k * math.sin(t), z] for z, k in rows for t in turn])
        return self.center + local @ self.basis.T

    def bounding_box(self) -> Shape:
        """The tightest box round a hull among a few framings: the frame's own axes, and each axis with the other two turned to
        face the hull's centre (a ring's sector lies along its chord). What a hit sweep that knows only boxes uses for the hull."""
        if self.kind != HULL:
            return self
        best: Shape | None = None
        candidates = [np.eye(3)]
        centre = self.points.mean(axis=0)
        for axis in range(3):
            a, b = (axis + 1) % 3, (axis + 2) % 3
            if math.hypot(centre[a], centre[b]) > 1e-6:
                turn = math.atan2(centre[b], centre[a])
                basis = np.zeros((3, 3))
                basis[axis, axis] = 1.0
                basis[a, a], basis[b, a] = math.cos(turn), math.sin(turn)
                basis[a, b], basis[b, b] = -math.sin(turn), math.cos(turn)
                candidates.append(basis)
        for basis in candidates:
            box = Shape.box_around(self.name, self.points, basis)
            if best is None or box.volume() < best.volume() - 1e-9:
                best = box
        return best

    def to_json(self, offset: Sequence[float] = (0.0, 0.0, 0.0), digits: int = JSON_DIGITS) -> dict[str, Any]:
        """The shape for the manifest, moved by ``-offset`` into the body frame. Boxes and capsules as ``hardpoints.collision``
        writes them; a hull lists its corners and its bounding ``box`` (for hit sweeps, which know boxes and capsules only).
        ``bound_radius`` is the sphere round ``position`` that holds it."""
        off = np.asarray(offset, dtype=float)
        out: dict[str, Any] = {"name": self.name, "type": self.kind, "position": _r(self.center - off, digits)}
        if self.kind == HULL:
            out["points"] = [_r(p - off, digits) for p in self.points]
            box = self.bounding_box()
            out["box"] = {"position": _r(box.center - off, digits), "size": _r(box.size, digits),
                          "basis": {k: _r(box.basis[:, i], digits) for i, k in enumerate("xyz")}}
        else:
            if self.kind == BOX:
                out["size"] = _r(self.size, digits)
            else:
                out.update(radius=round(self.radius, digits), height=round(self.height, digits), axis="z")
            out["basis"] = {k: _r(self.basis[:, i], digits) for i, k in enumerate("xyz")}
        out["bound_radius"] = round(self.bound_radius(), digits)
        return out

    @staticmethod
    def from_json(entry: Mapping[str, Any]) -> Shape:
        """The shape a manifest entry describes, in the entry's frame (what the game builds; tests measure against it)."""
        kind, name, centre = entry["type"], str(entry.get("name", "")), np.asarray(entry["position"], dtype=float)
        if kind == HULL:
            pts = np.asarray(entry["points"], dtype=float)
            return Shape(HULL, name, pts.mean(axis=0), np.eye(3), points=pts)
        basis = np.stack([np.asarray(entry["basis"][k], dtype=float) for k in "xyz"], axis=1)
        if kind == BOX:
            return Shape(BOX, name, centre, basis, size=np.asarray(entry["size"], dtype=float))
        return Shape(CAPSULE, name, centre, basis, radius=float(entry["radius"]), height=float(entry["height"]))


def _r(v: Any, digits: int = JSON_DIGITS) -> list[float]:
    return [round(float(x), digits) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def _polygon_points(corners: np.ndarray, spacing: float) -> np.ndarray:
    """Points over a flat convex polygon: its corners, points along its edges and a grid inside, about ``spacing`` apart."""
    c = np.asarray(corners, dtype=float)
    out = [c]
    for a, b in zip(c, np.roll(c, -1, axis=0), strict=True):
        n = max(1, math.ceil(float(np.linalg.norm(b - a)) / spacing))
        out.append(a + (np.arange(1, n) / n)[:, None] * (b - a))
    normal = np.zeros(3)
    for a, b in zip(c, np.roll(c, -1, axis=0), strict=True):
        normal += np.cross(a - c[0], b - c[0])
    if np.linalg.norm(normal) == 0.0:
        return np.concatenate(out)
    normal /= np.linalg.norm(normal)
    u = (c[1] - c[0]) / np.linalg.norm(c[1] - c[0])
    v = np.cross(normal, u)
    flat = np.stack([(c - c[0]) @ u, (c - c[0]) @ v], axis=1)
    lo, hi = flat.min(axis=0), flat.max(axis=0)
    gu, gv = np.meshgrid(np.arange(lo[0] + 0.5 * spacing, hi[0], spacing), np.arange(lo[1] + 0.5 * spacing, hi[1], spacing), indexing="ij")
    grid = np.stack([gu.ravel(), gv.ravel()], axis=1)
    edge = np.roll(flat, -1, axis=0) - flat
    side = edge[:, 0][None, :] * (grid[:, 1][:, None] - flat[:, 1][None, :]) - edge[:, 1][None, :] * (grid[:, 0][:, None] - flat[:, 0][None, :])
    inside = np.all(side >= 0.0, axis=1) | np.all(side <= 0.0, axis=1)
    out.append(c[0] + grid[inside, 0:1] * u + grid[inside, 1:2] * v)
    return np.concatenate(out)


def ring_sectors(name: str, centre: Sequence[float], axis: Sequence[float], r_inner: float, r_outer: float, z0: float, z1: float,
                 count: int, phase: float = 0.0) -> list[Shape]:
    """A ring (or any hollow round part) as ``count`` convex sectors, so its hole stays open. ``axis`` is the ring's axis
    through ``centre``; the ring spans ``z0`` to ``z1`` along it. Each sector's flat outer faces touch the outer radius, and
    its inner face is the chord of the inner one, so the whole ring is inside the sectors."""
    if count < 3 or not 0.0 <= r_inner < r_outer or z1 <= z0:
        raise ValueError("a ring needs three sectors or more, an outer radius past the inner one and a length")
    z = np.asarray(axis, dtype=float) / np.linalg.norm(axis)
    x = np.cross([0.0, 1.0, 0.0] if abs(z[1]) < 0.9 else [1.0, 0.0, 0.0], z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    step = 2.0 * math.pi / count
    reach = r_outer / math.cos(0.25 * step)  # three outer corners a sector: the flats between them touch the outer radius
    shapes = []
    for k in range(count):
        a0 = phase + k * step
        rim = [(r_inner, a0), (r_inner, a0 + step), (reach, a0), (reach, a0 + 0.5 * step), (reach, a0 + step)]
        pts = [np.asarray(centre, dtype=float) + r * (math.cos(a) * x + math.sin(a) * y) + h * z for h in (z0, z1) for r, a in rim]
        shapes.append(Shape.hull(f"{name}_{k:02d}", np.array(pts)))
    return shapes


def prism_points(centre: Sequence[float], axis: Sequence[float], rings: Sequence[tuple[float, float]], sides: int = 12,
                 phase: float = 0.0) -> np.ndarray:
    """Corner points for a round part's hull: at each ``(z, radius)`` along ``axis`` a ``sides``-gon whose flats touch the radius."""
    z = np.asarray(axis, dtype=float) / np.linalg.norm(axis)
    x = np.cross([0.0, 1.0, 0.0] if abs(z[1]) < 0.9 else [1.0, 0.0, 0.0], z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    turn = phase + np.arange(sides) * (2.0 * math.pi / sides)
    grow = 1.0 / math.cos(math.pi / sides)
    return np.array([np.asarray(centre, dtype=float) + h * z + r * grow * (math.cos(t) * x + math.sin(t) * y) for h, r in rings for t in turn])


# --- budget ------------------------------------------------------------------------------------------------------------
def merged(a: Shape, b: Shape, max_points: int) -> Shape:
    """One hull round both shapes."""
    return Shape.hull(a.name, np.concatenate([a.corners(), b.corners()]), max_points)


def fit_budget(shapes: Sequence[Shape], budget: Budget, neighbours: int = 6) -> list[Shape]:
    """The shapes cut down to the budget's piece count: the pair whose joint hull adds the least empty volume is merged, again
    and again. Each merge may bridge a gap, so check the coverage after it. Shapes inside the budget come back as they are."""
    out = list(shapes)

    def cost(i: int, j: int) -> float:
        return merged(out[i], out[j], budget.max_hull_points).volume() - out[i].volume() - out[j].volume()

    while len(out) > budget.max_pieces:
        centres = np.array([s.center for s in out])
        best: tuple[float, int, int] | None = None
        for i in range(len(out)):
            near = np.argsort(np.linalg.norm(centres - centres[i], axis=1), kind="stable")[1 : neighbours + 1]
            for j in (int(j) for j in near if j > i):
                c = cost(i, j)
                if best is None or c < best[0]:
                    best = (c, i, j)
        if best is None:
            raise ValueError("cannot merge down to the budget")
        _, i, j = best
        out[i] = merged(out[i], out[j], budget.max_hull_points)
        del out[j]
    return out


def check_budget(pieces: Mapping[str, Sequence[Shape]], budget: Budget) -> None:
    """Raise unless every piece is inside the budget: its shape count and each hull's point count."""
    for name, shapes in pieces.items():
        if not shapes:
            raise ValueError(f"collision piece {name!r} has no shape")
        if len(shapes) > budget.max_pieces:
            raise ValueError(f"collision piece {name!r} has {len(shapes)} shapes, over the budget of {budget.max_pieces}")
        for s in shapes:
            if s.kind == HULL and len(s.points) > budget.max_hull_points:
                raise ValueError(f"hull {s.name!r} has {len(s.points)} points, over the budget of {budget.max_hull_points}")


# --- coverage ----------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Coverage:
    """How the shapes sit on the render surface. ``covered``: the share of surface points within ``tolerance_m`` of a shape,
    ``worst_gap_m`` the furthest one's distance. ``within_reach``: the share of the shapes' own surface within ``reach_m`` of
    the render surface, ``worst_excess_m`` the furthest."""

    tolerance_m: float
    covered: float
    worst_gap_m: float
    reach_m: float
    within_reach: float
    worst_excess_m: float

    @property
    def ok(self) -> bool:
        return self.covered >= 1.0 and self.within_reach >= 1.0

    def to_json(self) -> dict[str, float]:
        return {"tolerance_m": round(self.tolerance_m, 4), "covered": round(self.covered, 6), "worst_gap_m": round(self.worst_gap_m, 4),
                "reach_m": round(self.reach_m, 4), "within_reach": round(self.within_reach, 6),
                "worst_excess_m": round(self.worst_excess_m, 4)}  # fmt: skip


def gaps(shapes: Sequence[Shape], points: np.ndarray) -> np.ndarray:
    """Each point's signed distance to the nearest shape."""
    p = np.asarray(points, dtype=float).reshape(-1, 3)
    best = np.full(len(p), np.inf)
    for s in shapes:
        lo, hi = s.bounds()
        # Only points near the shape can improve on what they have: skip the rest.
        margin = np.where(np.isfinite(best), np.maximum(best, 0.0), np.inf)
        near = np.all((p >= lo - margin[:, None]) & (p <= hi + margin[:, None]), axis=1)
        if near.any():
            best[near] = np.minimum(best[near], s.distance(p[near]))
    return best


def _grid_pass(q: np.ndarray, p: np.ndarray, cell: float) -> np.ndarray:
    """Each query's distance to the nearest point in its own grid cell or the 26 round it (infinite when they are empty)."""
    origin = np.minimum(q.min(axis=0), p.min(axis=0)) - cell
    dims = np.floor((np.maximum(q.max(axis=0), p.max(axis=0)) - origin) / cell).astype(np.int64) + 3

    def key(ijk: np.ndarray) -> np.ndarray:
        return (ijk[:, 0] * dims[1] + ijk[:, 1]) * dims[2] + ijk[:, 2]

    p_cell = np.floor((p - origin) / cell).astype(np.int64)
    order = np.argsort(key(p_cell), kind="stable")
    sorted_keys, sorted_points = key(p_cell)[order], p[order]
    q_cell = np.floor((q - origin) / cell).astype(np.int64)
    best = np.full(len(q), np.inf)
    for shift in itertools.product((-1, 0, 1), repeat=3):
        keys = key(q_cell + np.array(shift))
        start, stop = np.searchsorted(sorted_keys, keys, "left"), np.searchsorted(sorted_keys, keys, "right")
        for depth in range(int((stop - start).max(initial=0))):
            has = np.flatnonzero(start + depth < stop)
            d = np.linalg.norm(q[has] - sorted_points[start[has] + depth], axis=1)
            best[has] = np.minimum(best[has], d)
    return best


def _thinned(points: np.ndarray, voxel: float) -> np.ndarray:
    """One point per voxel: enough to measure a distance to within about two voxels."""
    _, first = np.unique(np.floor(points / voxel).astype(np.int64), axis=0, return_index=True)
    return points[np.sort(first)]


def nearest_distance(queries: np.ndarray, points: np.ndarray, cell: float) -> np.ndarray:
    """Each query's distance to the nearest of ``points``. A grid of ``cell`` finds a neighbour within a cell's size exactly;
    queries with none that near go to a grid twice as coarse over thinned points, and so on, so a far query's distance is never
    short and at most half as much again."""
    q = np.asarray(queries, dtype=float).reshape(-1, 3)
    p = np.asarray(points, dtype=float).reshape(-1, 3)
    best = np.full(len(q), np.inf)
    todo = np.arange(len(q))
    reach = float(np.linalg.norm(np.maximum(q.max(axis=0), p.max(axis=0)) - np.minimum(q.min(axis=0), p.min(axis=0))))
    size, thinned = float(cell), p
    while len(todo):
        best[todo] = _grid_pass(q[todo], thinned, size)
        todo = todo[best[todo] > size]  # a nearer point can hide outside the 27 cells only beyond one cell's size
        if size > reach:
            break
        size *= 2.0
        thinned = _thinned(p, size / 8.0)
    return best


def outer_surface(shapes: Sequence[Shape], spacing_m: float, touch_m: float = 1e-3) -> np.ndarray:
    """Points on the shapes' joint outer surface: a shape's own surface points that no other shape holds or touches (the faces
    two sectors of a ring share are inside the ring, not on it)."""
    out = []
    for k, shape in enumerate(shapes):
        own = shape.surface_points(spacing_m)
        others = [s for j, s in enumerate(shapes) if j != k]
        out.append(own[gaps(others, own) > touch_m] if others else own)
    return np.concatenate(out)


def coverage(shapes: Sequence[Shape], surface: np.ndarray, tolerance_m: float, reach_m: float, spacing_m: float) -> Coverage:
    """Measure ``shapes`` against the render surface's points (sampled about ``spacing_m`` apart, which the reach allows for)."""
    gap = gaps(shapes, surface)
    own = outer_surface(shapes, spacing_m)
    excess = np.maximum(nearest_distance(own, surface, max(reach_m, 2.0 * spacing_m)) - spacing_m, 0.0)
    return Coverage(float(tolerance_m), float(np.mean(gap <= tolerance_m)), float(gap.max()), float(reach_m),
                    float(np.mean(excess <= reach_m)), float(excess.max()))


# --- the manifest's section --------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Compound:
    """An asset's collision: per asset piece, in order, its convex shapes (inside ``budget``)."""

    pieces: Mapping[str, tuple[Shape, ...]]
    budget: Budget

    @property
    def shapes(self) -> list[Shape]:
        return [s for shapes in self.pieces.values() for s in shapes]

    def to_json(self, offset: Sequence[float] = (0.0, 0.0, 0.0), cover: Coverage | None = None) -> dict[str, Any]:
        """The manifest's ``collision`` section in the body frame (authored positions minus ``offset``)."""
        out: dict[str, Any] = {
            "budget": {"max_pieces": self.budget.max_pieces, "max_hull_points": self.budget.max_hull_points},
            "shape_count": len(self.shapes),
            "pieces": [{"name": name, "shapes": [s.to_json(offset) for s in shapes]} for name, shapes in self.pieces.items()],
        }
        if cover is not None:
            out["coverage"] = cover.to_json()
        return out


def shapes_of(section: Mapping[str, Any]) -> list[Shape]:
    """Every shape of a manifest's ``collision`` section, piece by piece."""
    return [Shape.from_json(entry) for piece in section["pieces"] for entry in piece["shapes"]]


def build(parts: Mapping[str, Sequence[Shape]], budget: Budget | None = None) -> Compound:
    """The asset's compound: every piece's shapes merged down to the budget and checked against it. Shape names must be
    unique in a piece, so a hit can name what it struck."""
    budget = budget or Budget()
    pieces: dict[str, tuple[Shape, ...]] = {}
    for name, shapes in parts.items():
        fitted = tuple(fit_budget(list(shapes), budget))
        names = [s.name for s in fitted]
        if len(set(names)) != len(names):
            raise ValueError(f"collision piece {name!r} has two shapes with one name")
        pieces[name] = fitted
    check_budget(pieces, budget)
    return Compound(pieces, budget)


def validate_section(section: Any) -> None:
    """Raise ``ValueError`` unless ``section`` is a well-formed ``collision`` section inside its own budget."""
    if not isinstance(section, dict) or not isinstance(section.get("pieces"), list) or not section["pieces"]:
        raise ValueError("manifest 'collision' needs a non-empty 'pieces' list")
    budget = section.get("budget", {})
    max_pieces, max_points = budget.get("max_pieces"), budget.get("max_hull_points")
    if not isinstance(max_pieces, int) or not isinstance(max_points, int):
        raise ValueError("manifest 'collision.budget' needs max_pieces and max_hull_points")
    for piece in section["pieces"]:
        shapes = piece.get("shapes") if isinstance(piece, dict) else None
        if not isinstance(piece.get("name"), str) or not isinstance(shapes, list) or not shapes:
            raise ValueError("a collision piece needs a name and shapes")
        if len(shapes) > max_pieces:
            raise ValueError(f"collision piece {piece['name']!r} is over its budget of {max_pieces} shapes")
        for shape in shapes:
            kind = shape.get("type")
            if kind not in KINDS or len(shape.get("position", ())) != 3:
                raise ValueError(f"collision piece {piece['name']!r} has a malformed shape")
            if kind == HULL and not 4 <= len(shape.get("points", ())) <= max_points:
                raise ValueError(f"hull {shape.get('name')!r} needs 4 to {max_points} points")
            if kind == BOX and len(shape.get("size", ())) != 3:
                raise ValueError(f"box {shape.get('name')!r} needs a size")
            if kind == CAPSULE and not (shape.get("radius", 0.0) > 0.0 and shape.get("height", 0.0) > 0.0):
                raise ValueError(f"capsule {shape.get('name')!r} needs a radius and a height")


__all__ = [
    "BOX",
    "CAPSULE",
    "HULL",
    "Budget",
    "Compound",
    "Coverage",
    "Shape",
    "build",
    "check_budget",
    "coverage",
    "fit_budget",
    "gaps",
    "hull_corners",
    "hull_faces",
    "merged",
    "nearest_distance",
    "outer_surface",
    "prism_points",
    "reduce_points",
    "ring_sectors",
    "shapes_of",
    "support_directions",
    "validate_section",
]
