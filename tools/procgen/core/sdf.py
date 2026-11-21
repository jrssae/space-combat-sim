"""Signed distance fields for organic hulls (M10-T06, D12.2; docs/assets-capital.md, "Organic hulls").

A :class:`Field` answers, for any point, how far it is from a body's skin: negative inside. Bodies are made by joining
fields, not triangles, so two lobes melt into each other instead of meeting at a crease:

* primitives: :func:`sphere`, :func:`ellipsoid`, :func:`round_cone`, :func:`box`, :func:`torus`;
* :func:`metaballs`: blobs that swell towards each other;
* :func:`swept`: a body swept along a path (``core/sweep.py``), its section an ellipse that changes along the way;
* joins: :func:`union`, :func:`smooth_union`, :func:`subtract`, :func:`smooth_subtract`, :func:`intersect`;
* :func:`displaced`: seeded noise pushed into the skin, and :func:`ribbed`: ribs across an axis.

:func:`mesh` turns a field into a watertight :class:`Mesh` (``core/isosurface.py``), thinned to a triangle budget
(``core/decimate.py``), with the field's own normals. :func:`solid` gives the field as the volume that buries other parts.

Two promises every field keeps, which the mesher relies on:

* ``lo`` and ``hi`` box the whole body, and a point outside the body never answers below zero;
* the answer never changes faster than ``lipschitz`` per metre, relief aside (``slack`` is how many metres bumps and
  ribs may add or take), so a far point cannot hide a skin.

Beyond ``reach`` of its box a field answers with the distance to the box instead of working out its own: cheaper, right in
sign, and never more than the true distance. Joins keep every part's reach wider than their blend.
"""

from __future__ import annotations

import dataclasses
import math
from collections.abc import Callable, Sequence
from dataclasses import dataclass

import numpy as np

from ..parts.solids import Solid
from .geometry import Material, Mesh, unit
from .sweep import Path
from .textures import value_noise

Vec3 = Sequence[float]
CHUNK = 1 << 17  # points a field works on at once


def _vec(v: Vec3) -> np.ndarray:
    return np.asarray(v, dtype=float).reshape(3)


@dataclass(frozen=True)
class Field:
    """A body as a distance: ``fn`` takes ``(n, 3)`` points and gives ``(n,)`` distances, negative inside."""

    fn: Callable[[np.ndarray], np.ndarray]
    lo: np.ndarray
    hi: np.ndarray
    lipschitz: float = 1.0
    reach: float = math.inf
    slack: float = 0.0

    def __post_init__(self) -> None:
        object.__setattr__(self, "lo", _vec(self.lo))
        object.__setattr__(self, "hi", _vec(self.hi))
        if np.any(self.hi <= self.lo):
            raise ValueError("a field's box needs a size on every axis")

    def __call__(self, points: np.ndarray) -> np.ndarray:
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        out = np.empty(len(p))
        for start in range(0, len(p), CHUNK):
            part = p[start:start + CHUNK]
            if math.isinf(self.reach):
                out[start:start + CHUNK] = self.fn(part)
                continue
            outside = np.linalg.norm(np.maximum(np.maximum(self.lo - part, part - self.hi), 0.0), axis=1)
            near = outside <= self.reach
            values = outside.copy()
            if near.any():
                values[near] = self.fn(part[near])
            out[start:start + CHUNK] = values
        return out

    def with_reach(self, reach: float) -> Field:
        """The same body, working its own distance out at least ``reach`` from its box."""
        return self if self.reach >= reach else dataclasses.replace(self, reach=float(reach))

    def moved(self, rotation: np.ndarray | None = None, translation: Vec3 = (0.0, 0.0, 0.0)) -> Field:
        """The body turned (``rotation``'s columns are its axes afterwards; a mirror is fine) and then shifted."""
        r = np.eye(3) if rotation is None else np.asarray(rotation, dtype=float)
        t = _vec(translation)
        corners = np.array([[x, y, z] for x in (self.lo[0], self.hi[0]) for y in (self.lo[1], self.hi[1]) for z in (self.lo[2], self.hi[2])])
        world = corners @ r.T + t
        inner = self
        return Field(lambda p: inner((p - t) @ r), world.min(axis=0), world.max(axis=0), self.lipschitz, slack=self.slack)

    def translated(self, offset: Vec3) -> Field:
        return self.moved(None, offset)

    def mirrored(self, axis: int = 0) -> Field:
        flip = np.eye(3)
        flip[axis, axis] = -1.0
        return self.moved(flip)

    def grown(self, by: float) -> Field:
        """The skin pushed out by ``by`` metres everywhere (in, when negative)."""
        inner = self
        return Field(lambda p: inner(p) - by, self.lo - max(by, 0.0), self.hi + max(by, 0.0), self.lipschitz, slack=self.slack + abs(by))

    def normals(self, points: np.ndarray, step: float) -> np.ndarray:
        """The skin's outward direction at ``points``: the way the distance grows, measured ``step`` either side."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        grad = np.zeros_like(p)
        for axis in range(3):
            shift = np.zeros(3)
            shift[axis] = step
            grad[:, axis] = self(p + shift) - self(p - shift)
        return unit(grad)

    @property
    def size(self) -> np.ndarray:
        return self.hi - self.lo


# --- primitives ----------------------------------------------------------------------------------------------------------
def sphere(radius: float, centre: Vec3 = (0.0, 0.0, 0.0)) -> Field:
    c = _vec(centre)
    return Field(lambda p: np.linalg.norm(p - c, axis=1) - radius, c - radius, c + radius)


def ellipsoid(radii: Vec3, centre: Vec3 = (0.0, 0.0, 0.0)) -> Field:
    """An ellipsoid with half axes ``radii``. Its distance is a close estimate, exact on the skin."""
    c, r = _vec(centre), _vec(radii)

    def fn(p: np.ndarray) -> np.ndarray:
        return _ellipse_distance((p - c) / r, (p - c) / (r * r), float(r.min()))

    return Field(fn, c - r, c + r)


def _ellipse_distance(scaled: np.ndarray, scaled_twice: np.ndarray, least: float) -> np.ndarray:
    """A point's distance to an ellipsoid from the point over the radii (``scaled``) and over their squares: the estimate
    that keeps its slope near one on the flat sides too, so a blend is as wide there as on the ends."""
    k0 = np.linalg.norm(scaled, axis=-1)
    k1 = np.linalg.norm(scaled_twice, axis=-1)
    return np.where(k1 > 1e-12, k0 * (k0 - 1.0) / np.maximum(k1, 1e-12), -least)


def round_cone(a: Vec3, b: Vec3, radius_a: float, radius_b: float) -> Field:
    """A rounded limb from ``a`` to ``b``, its radius running from ``radius_a`` to ``radius_b``."""
    pa, pb = _vec(a), _vec(b)
    axis = pb - pa
    length2 = float(axis @ axis)
    if length2 <= 0.0:
        raise ValueError("a round cone needs two different ends")

    def fn(p: np.ndarray) -> np.ndarray:
        h = np.clip((p - pa) @ axis / length2, 0.0, 1.0)
        return np.linalg.norm(p - pa - h[:, None] * axis, axis=1) - (radius_a + (radius_b - radius_a) * h)

    r = max(radius_a, radius_b)
    slope = abs(radius_b - radius_a) / math.sqrt(length2)
    return Field(fn, np.minimum(pa, pb) - r, np.maximum(pa, pb) + r, math.sqrt(1.0 + slope * slope))


def box(size: Vec3, centre: Vec3 = (0.0, 0.0, 0.0), rounding: float = 0.0) -> Field:
    """A box of full extents ``size`` with its edges rounded by ``rounding``."""
    c, half = _vec(centre), 0.5 * _vec(size)
    core = half - rounding
    if np.any(core <= 0.0):
        raise ValueError("a box's rounding must be under half its smallest side")

    def fn(p: np.ndarray) -> np.ndarray:
        q = np.abs(p - c) - core
        return np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0) - rounding

    return Field(fn, c - half, c + half)


def torus(ring_radius: float, tube_radius: float, centre: Vec3 = (0.0, 0.0, 0.0), axis: int = 2) -> Field:
    """A ring round ``axis`` through ``centre``."""
    c = _vec(centre)
    others = [k for k in range(3) if k != axis]

    def fn(p: np.ndarray) -> np.ndarray:
        q = p - c
        return np.hypot(np.hypot(q[:, others[0]], q[:, others[1]]) - ring_radius, q[:, axis]) - tube_radius

    reach = np.full(3, ring_radius + tube_radius)
    reach[axis] = tube_radius
    return Field(fn, c - reach, c + reach)


def metaballs(centres: np.ndarray, radii: Sequence[float], blend: float) -> Field:
    """Blobs of the given radii that swell towards their neighbours: the nearer two are, the wider the neck between them
    (about ``blend`` metres of swell where two just touch)."""
    c = np.asarray(centres, dtype=float).reshape(-1, 3)
    r = np.asarray(radii, dtype=float).reshape(-1)
    if len(c) != len(r) or len(c) == 0 or blend <= 0.0:
        raise ValueError("metaballs need a radius for every centre and a blend above zero")

    def fn(p: np.ndarray) -> np.ndarray:
        d = np.linalg.norm(p[:, None, :] - c[None], axis=2) - r[None]
        least = d.min(axis=1)
        return least - blend * np.log(np.exp(-(d - least[:, None]) / blend).sum(axis=1))

    swell = blend * math.log(len(c))
    return Field(fn, (c - r[:, None]).min(axis=0) - swell, (c + r[:, None]).max(axis=0) + swell, reach=float(r.max()) + 4.0 * blend)


def swept(path: Path, half_width: Sequence[float] | float, half_height: Sequence[float] | float | None = None) -> Field:
    """A body swept along ``path``: at each of the path's points an ellipse ``half_width`` along the path's side and
    ``half_height`` along its up (one number, or one per point; the height is the width when left out). The ends are rounded
    to the section there, so a section that shrinks to nothing ends in a point."""
    n = len(path.points)
    w = np.broadcast_to(np.asarray(half_width, dtype=float), (n,)).copy()
    h = w.copy() if half_height is None else np.broadcast_to(np.asarray(half_height, dtype=float), (n,)).copy()
    floor = 1e-4 * float(max(w.max(), h.max()))
    w, h = np.maximum(w, floor), np.maximum(h, floor)
    a, e = path.points[:-1], path.points[1:] - path.points[:-1]
    length2 = np.einsum("ij,ij->i", e, e)

    def fn(p: np.ndarray) -> np.ndarray:
        best = np.full(len(p), np.inf)
        for k in range(n - 1):  # a segment at a time: the working arrays stay the size of the points
            rel = p - a[k]
            t = np.clip(rel @ e[k] / length2[k], 0.0, 1.0)
            off = rel - t[:, None] * e[k]
            x = off @ path.side[k] + t * (off @ (path.side[k + 1] - path.side[k]))
            y = off @ path.up[k] + t * (off @ (path.up[k + 1] - path.up[k]))
            z = np.sqrt(np.maximum(np.einsum("ij,ij->i", off, off) - x * x - y * y, 0.0))  # past an end only
            ws, hs = w[k] + t * (w[k + 1] - w[k]), h[k] + t * (h[k + 1] - h[k])
            least = np.minimum(ws, hs)
            d = _ellipse_distance(np.stack([x / ws, y / hs, z / least], axis=-1),
                                  np.stack([x / (ws * ws), y / (hs * hs), z / (least * least)], axis=-1), least)
            np.minimum(best, d, out=best)
        return best

    r = float(max(w.max(), h.max()))
    slope = float(np.max(np.abs(np.diff(np.maximum(w, h))) / np.sqrt(length2)))
    return Field(fn, path.points.min(axis=0) - r, path.points.max(axis=0) + r, math.sqrt(1.0 + slope * slope), reach=r)


# --- joins ---------------------------------------------------------------------------------------------------------------
def _joint_box(fields: Sequence[Field], pad: float = 0.0) -> tuple[np.ndarray, np.ndarray]:
    return np.min([f.lo for f in fields], axis=0) - pad, np.max([f.hi for f in fields], axis=0) + pad


def union(*fields: Field) -> Field:
    """Everything any of the bodies holds; they meet at a crease."""
    if not fields:
        raise ValueError("a union needs a field")
    lo, hi = _joint_box(fields)
    return Field(lambda p: np.min([f(p) for f in fields], axis=0), lo, hi, max(f.lipschitz for f in fields), slack=max(f.slack for f in fields))


def _smooth_min(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - 0.25 * k * h * h


def smooth_union(*fields: Field, blend: float) -> Field:
    """The bodies melted together: where two come within ``blend`` metres a fillet about that wide joins them."""
    if not fields or blend <= 0.0:
        raise ValueError("a smooth union needs a field and a blend above zero")
    parts = [f.with_reach(2.0 * blend) for f in fields]

    def fn(p: np.ndarray) -> np.ndarray:
        out = parts[0](p)
        for f in parts[1:]:
            out = _smooth_min(out, f(p), blend)
        return out

    # Each join can swell the skin by a quarter of the blend.
    lo, hi = _joint_box(parts, 0.25 * blend * max(len(parts) - 1, 1))
    return Field(fn, lo, hi, max(f.lipschitz for f in parts), slack=max(f.slack for f in parts))


def subtract(body: Field, *holes: Field) -> Field:
    """``body`` with the ``holes`` cut out of it, the cut's edge sharp."""
    return Field(lambda p: np.max([body(p), *(-h(p) for h in holes)], axis=0), body.lo, body.hi, max(f.lipschitz for f in (body, *holes)),
                 slack=max(f.slack for f in (body, *holes)))


def smooth_subtract(body: Field, hole: Field, blend: float) -> Field:
    """``body`` with ``hole`` scooped out of it, the scoop's edge rounded over about ``blend`` metres."""
    cut = hole.with_reach(2.0 * blend)
    return Field(lambda p: -_smooth_min(-body(p), cut(p), blend), body.lo, body.hi, max(body.lipschitz, hole.lipschitz),
                 slack=max(body.slack, hole.slack))


def intersect(*fields: Field) -> Field:
    """Only what every body holds."""
    lo, hi = np.max([f.lo for f in fields], axis=0), np.min([f.hi for f in fields], axis=0)
    return Field(lambda p: np.max([f(p) for f in fields], axis=0), lo, hi, max(f.lipschitz for f in fields), slack=max(f.slack for f in fields))


# --- surface relief ------------------------------------------------------------------------------------------------------
def displaced(body: Field, amplitude: float, scale_m: float, seed: int, octaves: int = 2) -> Field:
    """Seeded noise pushed into the skin: bumps up to ``amplitude`` metres either way, the broadest ``scale_m`` across, each
    further octave half the size and half the height."""
    if amplitude < 0.0 or scale_m <= 0.0 or octaves < 1:
        raise ValueError("a displacement needs an amplitude, a scale and an octave")
    weights = np.array([0.5 ** k for k in range(octaves)])
    weights /= weights.sum()

    def fn(p: np.ndarray) -> np.ndarray:
        bump = sum(w * (2.0 * value_noise(p, scale_m * 0.5 ** k, seed + 31 * k) - 1.0) for k, w in enumerate(weights))
        return body(p) - amplitude * bump

    return Field(fn, body.lo - amplitude, body.hi + amplitude, body.lipschitz, slack=body.slack + amplitude)


def ribbed(body: Field, amplitude: float, pitch_m: float, axis: Vec3 = (0.0, 0.0, 1.0), sharpness: float = 1.0) -> Field:
    """Ribs across ``axis``, one every ``pitch_m``, standing ``amplitude`` proud of the skin; a ``sharpness`` above one
    narrows them into ridges with wide valleys between."""
    direction = unit(_vec(axis))

    def fn(p: np.ndarray) -> np.ndarray:
        wave = 0.5 + 0.5 * np.cos(2.0 * math.pi * (p @ direction) / pitch_m)
        return body(p) - amplitude * wave ** sharpness

    return Field(fn, body.lo - amplitude, body.hi + amplitude, body.lipschitz, slack=body.slack + amplitude)


# --- out of the field ----------------------------------------------------------------------------------------------------
def mesh(body: Field, cell_m: float, material: Material, triangles: int | None = None) -> Mesh:
    """The body's skin as a watertight mesh, cut on a grid of ``cell_m`` cells and thinned to ``triangles`` (left as cut
    when ``None``), with the field's own normals so it shades as the smooth body it is."""
    from .decimate import decimate
    from .isosurface import extract

    vertices, faces = extract(body, body.lo, body.hi, cell_m, body.lipschitz, body.slack)
    if triangles is not None and len(faces) > triangles:
        vertices, faces = decimate(vertices, faces, triangles)
    return Mesh(vertices, faces, np.zeros(len(faces), dtype=np.int64), (material,), vertex_normal=body.normals(vertices, 0.25 * cell_m))


def solid(body: Field) -> Solid:
    """The body as the volume that buries other parts' skin (``parts/solids.py``)."""
    return Solid(lambda p, margin: body(p) < -margin, (body.lo, body.hi))


__all__ = ["Field", "box", "displaced", "ellipsoid", "intersect", "mesh", "metaballs", "ribbed", "round_cone", "smooth_subtract", "smooth_union",
           "solid", "sphere", "subtract", "swept", "torus", "union"]
