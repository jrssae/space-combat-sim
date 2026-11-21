"""Paths and bodies swept along them (M10-T06, D12.2): spines, legs, claws and tendrils.

A :class:`Path` is a curve's points with a frame at each (the way it runs, its side and its up), carried along the curve
without twisting, so a flat blade stays flat round a bend. :func:`spline` draws one through control points.

Two ways to give a path a body:

* :func:`tube`, here: the skin written directly as rings of an elliptical section, with its own UV chart. Exact however
  long and thin the limb is, and cheap: the way to build a limb that stands on its own;
* ``sdf.swept``: the same body as a field, to melt a limb's root into a body (``core/sdf.py``).

Frames: ``side`` x ``up`` = ``tangent``; a path that runs aft (+z) with up +y has its side to starboard (+x).
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from .geometry import Material, Mesh, unit

Vec3 = Sequence[float]


@dataclass(frozen=True)
class Path:
    """A curve's points, each with its frame; ``t`` is how far along each point is, 0 to 1 by length."""

    points: np.ndarray
    tangent: np.ndarray
    side: np.ndarray
    up: np.ndarray

    @property
    def arc(self) -> np.ndarray:
        """The length along the curve to each point, metres."""
        return np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(self.points, axis=0), axis=1))])

    @property
    def length(self) -> float:
        return float(self.arc[-1])

    @property
    def t(self) -> np.ndarray:
        arc = self.arc
        return arc / arc[-1]

    def along(self, stations: Sequence[tuple[float, float]]) -> np.ndarray:
        """A value at every point from ``(t, value)`` stations, straight between them."""
        ts, values = zip(*stations, strict=True)
        return np.interp(self.t, ts, values)

    def transformed(self, rotation: np.ndarray, translation: Vec3 = (0.0, 0.0, 0.0)) -> Path:
        """The path turned and shifted. A mirror flips the side, so the frame stays right-handed."""
        r = np.asarray(rotation, dtype=float)
        sign = -1.0 if np.linalg.det(r) < 0.0 else 1.0
        return Path(self.points @ r.T + np.asarray(translation, dtype=float), self.tangent @ r.T, sign * (self.side @ r.T), self.up @ r.T)


def frames(points: np.ndarray, up: Vec3 = (0.0, 1.0, 0.0)) -> Path:
    """The path through ``points`` with its frames: the first up is ``up`` squared against the curve, the rest follow the
    curve's bends without twisting about it."""
    p = np.asarray(points, dtype=float).reshape(-1, 3)
    if len(p) < 2:
        raise ValueError("a path needs two points")
    tangent = unit(np.gradient(p, axis=0))
    ups = np.zeros_like(p)
    first = np.asarray(up, dtype=float) - (np.asarray(up, dtype=float) @ tangent[0]) * tangent[0]
    if float(np.linalg.norm(first)) < 1e-9:
        raise ValueError("a path's up must not lie along its start")
    ups[0] = unit(first)
    for k in range(1, len(p)):
        axis = np.cross(tangent[k - 1], tangent[k])
        s, c = float(np.linalg.norm(axis)), float(tangent[k - 1] @ tangent[k])
        carried = ups[k - 1]
        if s > 1e-12:
            a = axis / s
            carried = carried * c + np.cross(a, carried) * s + a * (a @ carried) * (1.0 - c)
        ups[k] = unit(carried - (carried @ tangent[k]) * tangent[k])
    return Path(p, tangent, np.cross(ups, tangent), ups)


def spline(controls: np.ndarray, samples: int = 48, up: Vec3 = (0.0, 1.0, 0.0)) -> Path:
    """A smooth path through the control points (a Catmull-Rom curve), ``samples`` points evenly spaced by length."""
    c = np.asarray(controls, dtype=float).reshape(-1, 3)
    if len(c) < 2 or samples < 2:
        raise ValueError("a spline needs two control points and two samples")
    ext = np.concatenate([[2.0 * c[0] - c[1]], c, [2.0 * c[-1] - c[-2]]])
    fine = []
    for k in range(len(c) - 1):
        p0, p1, p2, p3 = ext[k], ext[k + 1], ext[k + 2], ext[k + 3]
        u = np.linspace(0.0, 1.0, 24, endpoint=False)[:, None]
        fine.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u ** 3))
    dense = np.concatenate([*fine, c[-1:]])
    arc = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(dense, axis=0), axis=1))])
    at = np.linspace(0.0, arc[-1], samples)
    return frames(np.stack([np.interp(at, arc, dense[:, k]) for k in range(3)], axis=1), up)


def section_ring(sides: int, exponent: float = 2.0) -> np.ndarray:
    """A unit section's outline, ``(sides, 2)``: a circle at exponent 2, squarer above it, a diamond at 1."""
    theta = 2.0 * math.pi * np.arange(sides) / sides
    c, s = np.cos(theta), np.sin(theta)
    power = 2.0 / exponent
    return np.stack([np.sign(c) * np.abs(c) ** power, np.sign(s) * np.abs(s) ** power], axis=1)


def tube(path: Path, half_width: Sequence[float] | float, half_height: Sequence[float] | float | None, material: Material,
         sides: int = 12, exponent: float = 2.0, cap: float = 0.6, chart_m: float | None = None) -> Mesh:
    """The swept body's skin, closed at both ends: at each path point a ring ``half_width`` along the side and
    ``half_height`` along the up (the width when ``None``). An end whose section is nothing is a point; any other end is
    closed by a low dome ``cap`` of its smaller half size proud. One UV chart along the body (v its length, u round it),
    cut into charts ``chart_m`` long when given, so a long limb packs."""
    n = len(path.points)
    if sides < 3:
        raise ValueError("a tube needs three sides")
    w = np.broadcast_to(np.asarray(half_width, dtype=float), (n,))
    h = w if half_height is None else np.broadcast_to(np.asarray(half_height, dtype=float), (n,))
    outline = section_ring(sides, exponent)
    rings = (path.points[:, None, :] + w[:, None, None] * outline[None, :, 0:1] * path.side[:, None, :]
             + h[:, None, None] * outline[None, :, 1:2] * path.up[:, None, :])
    tiny = 1e-6 * float(max(w.max(), h.max()))
    first = 1 if min(w[0], h[0]) <= tiny else 0  # a ring of no size is the tip's point instead
    last = n - 2 if min(w[-1], h[-1]) <= tiny else n - 1
    used = np.arange(first, last + 1)
    if len(used) < 2:
        raise ValueError("a tube needs two rings with a size")
    start_tip = path.points[0] if first else path.points[0] - cap * min(w[0], h[0]) * path.tangent[0]
    end_tip = path.points[-1] if last < n - 1 else path.points[-1] + cap * min(w[-1], h[-1]) * path.tangent[-1]
    vertices = np.concatenate([rings[used].reshape(-1, 3), [start_tip], [end_tip]])
    a_tip, b_tip = len(used) * sides, len(used) * sides + 1

    arc = path.arc
    perimeter = np.linalg.norm(rings - np.roll(rings, -1, axis=1), axis=2).sum(axis=1)
    j = np.arange(sides)
    faces, uvs, rows = [], [], []

    def u_of(ring: int, k: np.ndarray | float) -> np.ndarray:
        return (np.asarray(k, dtype=float) / sides - 0.5) * perimeter[ring]

    def corner(ring: int, k: np.ndarray | float) -> np.ndarray:
        u = u_of(ring, k)
        return np.stack([u, np.full_like(u, arc[ring])], axis=1)

    for row, ring in enumerate(used[:-1]):
        a0, a1 = row * sides + j, row * sides + (j + 1) % sides
        b0, b1 = a0 + sides, a1 + sides
        nxt = int(ring) + 1
        faces += [np.stack([a0, a1, b1], axis=1), np.stack([a0, b1, b0], axis=1)]
        uvs += [np.stack([corner(ring, j), corner(ring, j + 1), corner(nxt, j + 1)], axis=1),
                np.stack([corner(ring, j), corner(nxt, j + 1), corner(nxt, j)], axis=1)]
        rows += [np.full(sides, ring), np.full(sides, ring)]
    # The ends: a fan from each tip, in the same chart, the tip's v a little past its ring's.
    ring0, ring1 = int(used[0]), int(used[-1])
    base1 = (len(used) - 1) * sides
    tip_v0 = arc[ring0] - float(np.linalg.norm(start_tip - path.points[ring0]))
    tip_v1 = arc[ring1] + float(np.linalg.norm(end_tip - path.points[ring1]))
    faces += [np.stack([np.full(sides, a_tip), (j + 1) % sides, j], axis=1), np.stack([np.full(sides, b_tip), base1 + j, base1 + (j + 1) % sides], axis=1)]
    uvs += [np.stack([np.stack([u_of(ring0, j + 0.5), np.full(sides, tip_v0)], axis=1), corner(ring0, j + 1), corner(ring0, j)], axis=1),
            np.stack([np.stack([u_of(ring1, j + 0.5), np.full(sides, tip_v1)], axis=1), corner(ring1, j), corner(ring1, j + 1)], axis=1)]
    rows += [np.full(sides, ring0), np.full(sides, max(ring1 - 1, ring0))]

    all_faces, all_uv, face_ring = np.concatenate(faces), np.concatenate(uvs), np.concatenate(rows)
    chart = np.zeros(len(all_faces), dtype=np.int64) if chart_m is None else np.floor(arc[face_ring] / chart_m).astype(np.int64)
    _, chart = np.unique(chart, return_inverse=True)
    return Mesh(vertices, all_faces, np.zeros(len(all_faces), dtype=np.int64), (material,), chart.reshape(-1), all_uv)


__all__ = ["Path", "frames", "section_ring", "spline", "tube"]
