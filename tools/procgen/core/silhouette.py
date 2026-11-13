"""How large a big prop looks from far away (M6-T15): the area of its silhouette seen along a set of directions.

A far prop (the jumpgate, the station's stand-in) is drawn as a dot once it is a few pixels across, and the dot must cover what the
mesh covered, or it pops: a gate seen end on is four rails' ends, seen from the side four rails and their fins, twenty times more.
The game reads the table from the manifest's ``far`` section and blends it by direction (``FarPropMath`` in ``src/rendering``).
"""

from __future__ import annotations

import math
from typing import Any

import numpy as np

DEFAULT_SPIRAL = 128
DEFAULT_RES = 512
## Extra directions in rings round each of the prop's axes, degrees off it: a gate seen end on is a narrow dip (its rails show
## their length a degree off), which an even table alone would blur (M6-T15: 3 % mean error against the true outline with
## these, 6 % and up to 78 % near the axes without).
AXIS_RINGS_DEG = (1.5, 3.0, 6.0, 10.0)
AXIS_RING_POINTS = 8
# Triangles per batch while rasterising, so the candidate pixels stay a few million.
_BATCH = 4096


def view_directions(spiral: int = DEFAULT_SPIRAL) -> np.ndarray:
    """Unit directions, one per row (a silhouette is the same from both sides, so one of each pair): the three axes, rings round
    each axis (``AXIS_RINGS_DEG``), then a Fibonacci spiral of ``spiral`` over one hemisphere for the rest."""
    if spiral < 1:
        raise ValueError("spiral must be at least 1")
    rows: list[np.ndarray] = list(np.eye(3))
    for axis in np.eye(3):
        hint = np.array([0.0, 1.0, 0.0]) if abs(axis[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
        a = np.cross(axis, hint)
        a /= np.linalg.norm(a)
        b = np.cross(axis, a)
        for ring, degrees in enumerate(AXIS_RINGS_DEG):
            off = math.radians(degrees)
            for k in range(AXIS_RING_POINTS):
                turn = 2.0 * math.pi * (k + 0.5 * (ring % 2)) / AXIS_RING_POINTS  # staggered ring to ring
                rows.append(axis * math.cos(off) + math.sin(off) * (a * math.cos(turn) + b * math.sin(turn)))
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(spiral):
        y = 1.0 - (i + 0.5) / spiral  # (0, 1]: the upper hemisphere
        r = math.sqrt(max(0.0, 1.0 - y * y))
        rows.append(np.array([r * math.cos(golden * i), y, r * math.sin(golden * i)]))
    return np.vstack(rows)


def silhouette_area(vertices: np.ndarray, faces: np.ndarray, direction: np.ndarray, res: int = DEFAULT_RES) -> float:
    """The area, m^2, of the mesh's outline seen along ``direction`` (orthographic), from a ``res`` square raster."""
    d = np.asarray(direction, dtype=np.float64)
    d = d / np.linalg.norm(d)
    hint = np.array([0.0, 1.0, 0.0]) if abs(d[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    a = np.cross(d, hint)
    a /= np.linalg.norm(a)
    b = np.cross(d, a)
    v = np.asarray(vertices, dtype=np.float64)
    p = np.stack([v @ a, v @ b], axis=1)
    lo = p.min(axis=0)
    span = float((p.max(axis=0) - lo).max()) * 1.01 + 1e-9
    px = span / res
    t = (p - lo) / px
    image = np.zeros((res, res), dtype=bool)
    tri = t[np.asarray(faces, dtype=np.int64)]  # (F, 3, 2)
    twice = (tri[:, 1, 0] - tri[:, 0, 0]) * (tri[:, 2, 1] - tri[:, 0, 1]) - (tri[:, 1, 1] - tri[:, 0, 1]) * (tri[:, 2, 0] - tri[:, 0, 0])
    tri = tri[np.abs(twice) > 1e-12]
    for start in range(0, len(tri), _BATCH):
        _fill(image, tri[start:start + _BATCH])
    return float(image.sum()) * px * px


def _fill(image: np.ndarray, tri: np.ndarray) -> None:
    res = image.shape[0]
    x0 = np.clip(np.floor(tri[:, :, 0].min(axis=1) - 0.5).astype(np.int64), 0, res - 1)
    x1 = np.clip(np.ceil(tri[:, :, 0].max(axis=1) - 0.5).astype(np.int64), 0, res - 1)
    y0 = np.clip(np.floor(tri[:, :, 1].min(axis=1) - 0.5).astype(np.int64), 0, res - 1)
    y1 = np.clip(np.ceil(tri[:, :, 1].max(axis=1) - 0.5).astype(np.int64), 0, res - 1)
    w = x1 - x0 + 1
    n = w * (y1 - y0 + 1)
    total = int(n.sum())
    if total == 0:
        return
    owner = np.repeat(np.arange(len(tri)), n)
    k = np.arange(total) - np.repeat(np.cumsum(n) - n, n)
    x = x0[owner] + k % w[owner]
    y = y0[owner] + k // w[owner]
    cx = x + 0.5
    cy = y + 0.5
    c = tri[owner]
    inside_pos = np.ones(total, dtype=bool)
    inside_neg = np.ones(total, dtype=bool)
    for i, j in ((0, 1), (1, 2), (2, 0)):
        e = (c[:, j, 0] - c[:, i, 0]) * (cy - c[:, i, 1]) - (c[:, j, 1] - c[:, i, 1]) * (cx - c[:, i, 0])
        inside_pos &= e >= 0.0
        inside_neg &= e <= 0.0
    hit = inside_pos | inside_neg
    image[y[hit], x[hit]] = True


def far_section(vertices: np.ndarray, faces: np.ndarray, spiral: int = DEFAULT_SPIRAL, res: int = DEFAULT_RES) -> dict[str, Any]:
    """The manifest's ``far`` section: the bounding sphere (centre of the box, farthest vertex) and the silhouette's area along
    each of ``view_directions(spiral)``, in the mesh's own frame."""
    v = np.asarray(vertices, dtype=np.float64)
    centre = 0.5 * (v.min(axis=0) + v.max(axis=0))
    radius = float(np.linalg.norm(v - centre, axis=1).max())
    directions = view_directions(spiral)
    areas = [silhouette_area(v, faces, d, res) for d in directions]
    return {
        "centre": [round(float(c), 4) for c in centre],
        "radius_m": round(radius, 3),
        "directions": [[round(float(c), 6) for c in d] for d in directions],
        "areas_m2": [round(a, 1) for a in areas],
        "raster_px": int(res),
    }
