"""Finds faces that would z-fight: two triangles facing the same way in the same plane, one over the other.

The renderer's depth test cannot order them, so the winner changes from frame to frame as the camera or the mesh moves; where one
of the two glows (a lamp set flush in a wall panel) the light flickers (the launch halls' work lamps, M7). A generator keeps such
faces apart by standing one part proud of the other, or by not drawing the face that is covered.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

GAP_M = 0.02  # planes closer than this fight at a station's viewing distances
MIN_AREA_M2 = 1e-3  # shared area under this is an edge or a corner touching, not an overlap


@dataclass(frozen=True)
class Overlap:
    """Two triangles (indices into the input) sharing ``area`` square metres of one plane, about ``at``."""

    first: int
    second: int
    area: float
    at: tuple[float, float, float]
    normal: tuple[float, float, float]


def _clip(subject: list[np.ndarray], a: np.ndarray, b: np.ndarray) -> list[np.ndarray]:
    """``subject`` (a convex polygon, counter-clockwise) kept on the left of the edge a to b."""
    out: list[np.ndarray] = []
    edge = b - a
    for k, p in enumerate(subject):
        q = subject[(k + 1) % len(subject)]
        sp = edge[0] * (p[1] - a[1]) - edge[1] * (p[0] - a[0])
        sq = edge[0] * (q[1] - a[1]) - edge[1] * (q[0] - a[0])
        if sp >= 0.0:
            out.append(p)
        if (sp > 0.0 and sq < 0.0) or (sp < 0.0 and sq > 0.0):
            out.append(p + (q - p) * (sp / (sp - sq)))
    return out


def _area(polygon: Sequence[np.ndarray]) -> float:
    p = np.asarray(polygon)
    if len(p) < 3:
        return 0.0
    x, y = p[:, 0], p[:, 1]
    return 0.5 * float(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))


def _shared_area(t0: np.ndarray, t1: np.ndarray) -> float:
    """The area two 2D triangles have in common."""
    a = list(t0 if _area(t0) > 0.0 else t0[::-1])
    b = t1 if _area(t1) > 0.0 else t1[::-1]
    for k in range(3):
        a = _clip(a, b[k], b[(k + 1) % 3])
        if len(a) < 3:
            return 0.0
    return abs(_area(a))


def coplanar_overlaps(triangles: np.ndarray, gap_m: float = GAP_M, min_area_m2: float = MIN_AREA_M2) -> list[Overlap]:
    """Every pair of ``triangles`` (``(n, 3, 3)``) that face the same way within ``gap_m`` of one plane and share area. Faces back
    to back are left alone: only one of them is ever drawn toward the camera."""
    tris = np.asarray(triangles, dtype=float).reshape(-1, 3, 3)
    cross = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    length = np.linalg.norm(cross, axis=1)
    keep = np.nonzero(length > 1e-9)[0]
    normals = cross[keep] / length[keep, None]
    offsets = np.einsum("ij,ij->i", normals, tris[keep, 0])
    groups: dict[tuple[int, int, int], list[int]] = {}
    for row, key in enumerate(map(tuple, np.round(normals * 500.0).astype(int))):
        groups.setdefault(key, []).append(row)
    found: list[Overlap] = []
    for rows in groups.values():
        if len(rows) < 2:
            continue
        r = np.asarray(rows)
        n = normals[r].mean(axis=0)
        n /= np.linalg.norm(n)
        u = np.cross(n, [1.0, 0.0, 0.0] if abs(n[0]) < 0.9 else [0.0, 1.0, 0.0])
        u /= np.linalg.norm(u)
        v = np.cross(n, u)
        flat = np.stack([tris[keep[r]] @ u, tris[keep[r]] @ v], axis=-1)  # (k, 3, 2)
        lo, hi = flat.min(axis=1), flat.max(axis=1)
        order = np.argsort(offsets[r])
        d = offsets[r][order]
        for a in range(len(order) - 1):
            end = int(np.searchsorted(d, d[a] + gap_m, side="right"))
            if end <= a + 1:
                continue
            i = order[a]
            others = order[a + 1:end]
            near = np.all((lo[others] < hi[i] - 1e-6) & (hi[others] > lo[i] + 1e-6), axis=1)
            for j in others[near]:
                area = _shared_area(flat[i], flat[j])
                if area > min_area_m2:
                    first, second = sorted((int(keep[r[i]]), int(keep[r[j]])))
                    at = 0.5 * (tris[first].mean(axis=0) + tris[second].mean(axis=0))
                    found.append(Overlap(first, second, area, tuple(np.round(at, 3)), tuple(np.round(n, 3))))
    return sorted(found, key=lambda o: (o.first, o.second))


def mesh_triangles(mesh: object) -> np.ndarray:
    """A ``Mesh``'s triangles, ``(n, 3, 3)``."""
    return np.asarray(mesh.vertices)[np.asarray(mesh.faces)]


def describe(overlaps: Sequence[Overlap], limit: int = 8) -> str:
    """The first few overlaps, for a failing test's message."""
    lines = [f"{o.area:.3f} m2 at {o.at} facing {o.normal} (triangles {o.first}, {o.second})" for o in overlaps[:limit]]
    more = f"; {len(overlaps) - limit} more" if len(overlaps) > limit else ""
    return f"{len(overlaps)} overlapping coplanar face pairs: " + "; ".join(lines) + more
