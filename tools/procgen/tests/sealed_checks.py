"""Whether a space is sealed: what an eye inside it can see in every direction is a surface facing it, never the sky.

The game draws one side of each triangle, so a wall seen from behind is not there: a ray "escapes" when no triangle on its way
faces its origin. A sealed hall lets no ray escape with its doors closed (M7: the sun showed through the Cobra bays' doors).
"""

from __future__ import annotations

import numpy as np


def sphere_directions(count: int) -> np.ndarray:
    """``count`` unit vectors spread evenly over the sphere."""
    k = np.arange(count) + 0.5
    polar = np.arccos(1.0 - 2.0 * k / count)
    turn = np.pi * (1.0 + 5.0 ** 0.5) * k
    return np.stack([np.cos(turn) * np.sin(polar), np.sin(turn) * np.sin(polar), np.cos(polar)], axis=1)


def escapes(triangles: np.ndarray, origin: np.ndarray, directions: np.ndarray) -> np.ndarray:
    """For each of ``directions`` from ``origin``: True when the ray meets no triangle of ``triangles`` (``(n, 3, 3)``) that
    faces the origin."""
    tris = np.asarray(triangles, dtype=float)
    a = tris[:, 0]
    e1, e2 = tris[:, 1] - a, tris[:, 2] - a
    normal = np.cross(e1, e2)
    out = np.ones(len(directions), dtype=bool)
    s = np.asarray(origin, dtype=float) - a  # (n, 3)
    q = np.cross(s, e1)
    for k, d in enumerate(np.asarray(directions, dtype=float)):
        facing = normal @ d < 0.0
        p = np.cross(d, e2)
        det = np.einsum("ij,ij->i", e1, p)
        ok = facing & (np.abs(det) > 1e-12)
        inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        u = np.einsum("ij,ij->i", s, p) * inv
        v = (q @ d) * inv
        t = np.einsum("ij,ij->i", e2, q) * inv
        hit = ok & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1.0 + 1e-9) & (t > 1e-6)
        out[k] = not hit.any()
    return out




def see_through(triangles: np.ndarray, origins: np.ndarray, directions: np.ndarray) -> np.ndarray:
    """For each ray (``origins[k]``, ``directions[k]``, begun outside the body): True when it crosses the body's triangles but none
    that faces it, so an eye there looks through the body at whatever is behind (the sun, through a slit in a hollow hull)."""
    tris = np.asarray(triangles, dtype=float)
    a = tris[:, 0]
    e1, e2 = tris[:, 1] - a, tris[:, 2] - a
    normal = np.cross(e1, e2)
    out = np.zeros(len(directions), dtype=bool)
    for k, (o, d) in enumerate(zip(np.asarray(origins, dtype=float), np.asarray(directions, dtype=float), strict=True)):
        p = np.cross(d, e2)
        det = np.einsum("ij,ij->i", e1, p)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        s = o - a
        u = np.einsum("ij,ij->i", s, p) * inv
        q = np.cross(s, e1)
        v = (q @ d) * inv
        t = np.einsum("ij,ij->i", e2, q) * inv
        hit = ok & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1.0 + 1e-9) & (t > 1e-6)
        out[k] = bool(hit.any()) and not bool((hit & (normal @ d < 0.0)).any())
    return out


__all__ = ["escapes", "see_through", "sphere_directions"]
