"""Solid volumes for burial tests: where one part sits inside another, the hidden surface samples are dropped, so the body
origin and the chunks' offsets come from the visible surface only (buried roots and recessed ends do not count).

A :class:`Solid` is a local inside-test plus a rigid placement, so it moves and mirrors with the part it belongs to.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence

import numpy as np

from ..core.geometry import mirror_matrix

LocalTest = Callable[[np.ndarray, float], np.ndarray]


class Solid:
    """Points inside the volume by more than ``margin`` are buried. ``rotation`` columns are the local axes in the
    world (a mirror makes it improper, which the test does not mind); ``bounds`` is the local box for a quick reject."""

    def __init__(
        self,
        test: LocalTest,
        bounds: tuple[Sequence[float], Sequence[float]],
        rotation: np.ndarray | None = None,
        origin: Sequence[float] = (0.0, 0.0, 0.0),
    ) -> None:
        self.test = test
        self.local_bounds = (np.asarray(bounds[0], dtype=float), np.asarray(bounds[1], dtype=float))
        self.rotation = np.eye(3) if rotation is None else np.asarray(rotation, dtype=float)
        self.origin = np.asarray(origin, dtype=float)

    def contains(self, points: np.ndarray, margin: float = 0.01) -> np.ndarray:
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        out = np.zeros(len(p), dtype=bool)
        lo, hi = self.bounds()
        near = np.all((p >= lo) & (p <= hi), axis=1)
        if near.any():
            local = (p[near] - self.origin) @ self.rotation
            out[near] = self.test(local, margin)
        return out

    def transformed(self, rotation: np.ndarray, translation: Sequence[float] = (0.0, 0.0, 0.0)) -> Solid:
        r = np.asarray(rotation, dtype=float)
        return Solid(self.test, self.local_bounds, r @ self.rotation, r @ self.origin + np.asarray(translation, dtype=float))

    def translated(self, offset: Sequence[float]) -> Solid:
        return self.transformed(np.eye(3), offset)

    def mirrored(self, axis: str) -> Solid:
        return self.transformed(mirror_matrix(axis))

    def bounds(self) -> tuple[np.ndarray, np.ndarray]:
        """The world box around the volume."""
        lo, hi = self.local_bounds
        corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
        world = corners @ self.rotation.T + self.origin
        return world.min(axis=0), world.max(axis=0)


def union(*solids: Solid) -> Solid:
    """Inside any of them (world frame)."""

    def test(p: np.ndarray, margin: float) -> np.ndarray:
        out = np.zeros(len(p), dtype=bool)
        for s in solids:
            out |= s.contains(p, margin)
        return out

    boxes = [s.bounds() for s in solids]
    return Solid(test, (np.min([b[0] for b in boxes], axis=0), np.max([b[1] for b in boxes], axis=0)))


def difference(base: Solid, *holes: Solid) -> Solid:
    """Inside ``base`` and outside every hole (a recess cut into a block)."""

    def test(p: np.ndarray, margin: float) -> np.ndarray:
        out = base.contains(p, margin)
        for h in holes:
            out &= ~h.contains(p, -margin)
        return out

    return Solid(test, base.bounds())


def box_solid(size: Sequence[float], center: Sequence[float] = (0.0, 0.0, 0.0)) -> Solid:
    half = 0.5 * np.asarray(size, dtype=float)
    c = np.asarray(center, dtype=float)

    def test(p: np.ndarray, margin: float) -> np.ndarray:
        return np.all(np.abs(p - c) < half - margin, axis=1)

    return Solid(test, (c - half, c + half))


def lathe_solid(profile: Sequence[tuple[float, float]]) -> Solid:
    """A solid of revolution about local Z: ``profile`` is the outer radius ``(z, r)`` at increasing z."""
    zs = np.array([z for z, _ in profile], dtype=float)
    rs = np.array([r for _, r in profile], dtype=float)
    r_max = float(rs.max())

    def test(p: np.ndarray, margin: float) -> np.ndarray:
        radius = np.interp(p[:, 2], zs, rs)
        inside_z = (p[:, 2] > zs[0] + margin) & (p[:, 2] < zs[-1] - margin)
        return inside_z & (np.hypot(p[:, 0], p[:, 1]) < radius - margin)

    return Solid(test, ((-r_max, -r_max, zs[0]), (r_max, r_max, zs[-1])))


def prism_solid(polygon: np.ndarray, z0: float, z1: float) -> Solid:
    """A convex polygon in local X/Y swept from ``z0`` to ``z1``."""
    poly = np.asarray(polygon, dtype=float).reshape(-1, 2)
    if 0.5 * float(np.dot(poly[:, 0], np.roll(poly[:, 1], -1)) - np.dot(poly[:, 1], np.roll(poly[:, 0], -1))) < 0.0:
        poly = poly[::-1]
    edges = np.roll(poly, -1, axis=0) - poly
    inward = np.stack([-edges[:, 1], edges[:, 0]], axis=1)
    inward /= np.linalg.norm(inward, axis=1, keepdims=True)
    offsets = np.einsum("ij,ij->i", inward, poly)

    def test(p: np.ndarray, margin: float) -> np.ndarray:
        depth = p[:, :2] @ inward.T - offsets
        return np.all(depth > margin, axis=1) & (p[:, 2] > z0 + margin) & (p[:, 2] < z1 - margin)

    lo, hi = poly.min(axis=0), poly.max(axis=0)
    return Solid(test, ((lo[0], lo[1], z0), (hi[0], hi[1], z1)))


def capsule_solid(radius: float, z0: float, z1: float) -> Solid:
    """A round bar from ``z0`` to ``z1`` along local Z with half-sphere ends (pipes, rods)."""

    def test(p: np.ndarray, margin: float) -> np.ndarray:
        along = np.clip(p[:, 2], z0, z1)
        d = np.sqrt(p[:, 0] ** 2 + p[:, 1] ** 2 + (p[:, 2] - along) ** 2)
        return d < radius - margin

    return Solid(test, ((-radius, -radius, z0 - radius), (radius, radius, z1 + radius)))


def segment_solid(a: Sequence[float], b: Sequence[float], radius: float) -> Solid:
    """A round bar between two points (world frame of the caller)."""
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    d = b - a
    length = float(np.linalg.norm(d))

    def test(p: np.ndarray, margin: float) -> np.ndarray:
        t = np.clip((p - a) @ d / (length * length), 0.0, 1.0)
        return np.linalg.norm(p - (a + t[:, None] * d), axis=1) < radius - margin

    lo, hi = np.minimum(a, b) - radius, np.maximum(a, b) + radius
    return Solid(test, (lo, hi))
