"""Finds faces of different parts that lie in one plane, face the same way and overlap: the renderer cannot tell which is in
front, so they flicker (z-fighting; M10-T67, the Nova's bay mouth). Used by the tests to keep a region of a hull free of them."""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Iterable, Sequence

import numpy as np

from .geometry import Mesh

PLANE_TOL_M = 0.01  # faces closer than this to one plane count as sharing it
NORMAL_DECIMALS = 3


def _clip(poly: list[np.ndarray], a: np.ndarray, b: np.ndarray) -> list[np.ndarray]:
    """``poly`` cut to the left of the line through ``a`` and ``b``."""
    def side(p: np.ndarray) -> float:
        return float((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]))
    out: list[np.ndarray] = []
    for i, p in enumerate(poly):
        q = poly[(i + 1) % len(poly)]
        sp, sq = side(p), side(q)
        if sp >= 0.0:
            out.append(p)
        if (sp >= 0.0) != (sq >= 0.0):
            out.append(p + sp / (sp - sq) * (q - p))
    return out


def _area(poly: list[np.ndarray]) -> float:
    if len(poly) < 3:
        return 0.0
    p = np.asarray(poly)
    return 0.5 * abs(float(np.sum(p[:, 0] * np.roll(p[:, 1], -1) - p[:, 1] * np.roll(p[:, 0], -1))))


def _ccw(t: list[np.ndarray]) -> list[np.ndarray]:
    turn = (t[1] - t[0])[0] * (t[2] - t[0])[1] - (t[1] - t[0])[1] * (t[2] - t[0])[0]
    return t if turn > 0.0 else t[::-1]


def coplanar_overlaps(parts: Iterable[tuple[str, Mesh]], lo: Sequence[float], hi: Sequence[float], min_area_m2: float = 0.05) -> dict[tuple[str, str], float]:
    """The pairs of parts with same-facing faces sharing a plane and overlapping by more than ``min_area_m2`` (the area they
    overlap by), among the faces whose bounds reach into the box ``lo`` to ``hi``."""
    lo_a, hi_a = np.asarray(lo, dtype=float), np.asarray(hi, dtype=float)
    tris: list[tuple[str, np.ndarray]] = []
    for name, mesh in parts:
        v = mesh.vertices[mesh.faces]
        inside = np.all((v.max(axis=1) >= lo_a) & (v.min(axis=1) <= hi_a), axis=1)
        tris += [(name, t) for t in v[inside]]
    groups: dict[tuple, list[int]] = defaultdict(list)
    for i, (_, t) in enumerate(tris):
        n = np.cross(t[1] - t[0], t[2] - t[0])
        length = float(np.linalg.norm(n))
        if length < 1e-9:
            continue
        n /= length
        groups[(*np.round(n, NORMAL_DECIMALS), round(float(n @ t[0]) / PLANE_TOL_M))].append(i)
    out: dict[tuple[str, str], float] = {}
    for key, members in groups.items():
        if len(members) < 2:
            continue
        n = np.asarray(key[:3], dtype=float)
        u = np.cross(n, (0.0, 0.0, 1.0) if abs(n[2]) < 0.9 else (1.0, 0.0, 0.0))
        u /= np.linalg.norm(u)
        w = np.cross(n, u)
        flat = {i: _ccw([np.array([p @ u, p @ w]) for p in tris[i][1]]) for i in members}
        for k, i in enumerate(members):
            for j in members[k + 1:]:
                if tris[i][0] == tris[j][0]:
                    continue
                poly = list(flat[i])
                for e in range(3):
                    poly = _clip(poly, flat[j][e], flat[j][(e + 1) % 3])
                    if not poly:
                        break
                area = _area(poly)
                if area > min_area_m2:
                    pair = tuple(sorted((tris[i][0], tris[j][0])))
                    out[pair] = out.get(pair, 0.0) + area  # type: ignore[index]
    return out


__all__ = ["coplanar_overlaps"]
