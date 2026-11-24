"""Finds faces of different parts that lie in one plane, face the same way and overlap: the renderer cannot tell which is in
front, so they flicker (z-fighting; M10-T67, the Nova's bay mouth). Used by the tests to keep a region of a hull free of them."""

from __future__ import annotations

import dataclasses
from collections import defaultdict
from collections.abc import Collection, Iterable, Sequence

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


SET_BACK_M = 0.1  # how far a part sitting flush on another's face is set back from it: clear of the depth buffer's reach


def _shared(parts: list[tuple[str, Mesh]], lo: np.ndarray, hi: np.ndarray, min_area_m2: float, among: Collection[str] | None = None):  # noqa: ANN202
    """Each overlap of two parts' same-facing faces in one plane: (the pair, the plane's normal and offset, each part's face
    area in that plane, the area they overlap by), among the faces whose bounds reach into the box ``lo`` to ``hi`` (and in
    planes one of ``among`` has a face in, if given)."""
    tris: list[tuple[str, np.ndarray]] = []
    for name, mesh in parts:
        v = mesh.vertices[mesh.faces]
        inside = np.all((v.max(axis=1) >= lo) & (v.min(axis=1) <= hi), axis=1)
        tris += [(name, t) for t in v[inside]]
    groups: dict[tuple, list[int]] = defaultdict(list)
    for i, (_, t) in enumerate(tris):
        n = np.cross(t[1] - t[0], t[2] - t[0])
        length = float(np.linalg.norm(n))
        if length < 1e-9:
            continue
        n /= length
        groups[(*np.round(n, NORMAL_DECIMALS), round(float(n @ t[0]) / PLANE_TOL_M))].append(i)
    for key, members in groups.items():
        names = {tris[i][0] for i in members}
        if len(names) < 2 or (among is not None and not names & set(among)):
            continue
        n = np.asarray(key[:3], dtype=float)
        u = np.cross(n, (0.0, 0.0, 1.0) if abs(n[2]) < 0.9 else (1.0, 0.0, 0.0))
        u /= np.linalg.norm(u)
        w = np.cross(n, u)
        flat = {i: _ccw([np.array([p @ u, p @ w]) for p in tris[i][1]]) for i in members}
        areas: dict[str, float] = defaultdict(float)
        for i in members:
            areas[tris[i][0]] += _area(flat[i])
        found: dict[tuple[str, str], float] = defaultdict(float)
        for k, i in enumerate(members):
            for j in members[k + 1:]:
                if tris[i][0] == tris[j][0]:
                    continue
                poly = list(flat[i])
                for e in range(3):
                    poly = _clip(poly, flat[j][e], flat[j][(e + 1) % 3])
                    if not poly:
                        break
                found[tuple(sorted((tris[i][0], tris[j][0])))] += _area(poly)  # type: ignore[index]
        for pair, area in found.items():
            if area > min_area_m2:
                yield pair, n, key[3] * PLANE_TOL_M, areas, area


def coplanar_overlaps(parts: Iterable[tuple[str, Mesh]], lo: Sequence[float], hi: Sequence[float], min_area_m2: float = 0.05) -> dict[tuple[str, str], float]:
    """The pairs of parts with same-facing faces sharing a plane and overlapping by more than ``min_area_m2`` (the area they
    overlap by), among the faces whose bounds reach into the box ``lo`` to ``hi``."""
    out: dict[tuple[str, str], float] = defaultdict(float)
    for pair, _, _, _, area in _shared(list(parts), np.asarray(lo, dtype=float), np.asarray(hi, dtype=float), min_area_m2):
        out[pair] += area
    return dict(out)


def flush_planes(parts: Iterable[tuple[str, Mesh]], min_area_m2: float = 0.05, among: Collection[str] | None = None) -> dict[str, list[tuple[np.ndarray, float]]]:
    """For each part that sits flush on another's face, the planes (normal, offset) it should be set back from: of each
    overlapping pair, the part with less face in that plane (the fitting on the plate), so the bigger face stays where it was.
    ``among`` limits the search to the planes those parts have faces in."""
    out: dict[str, list[tuple[np.ndarray, float]]] = defaultdict(list)
    big = np.full(3, 1e9)
    for (a, b), n, d, areas, _ in _shared(list(parts), -big, big, min_area_m2, among):
        name = a if (areas[a], a) < (areas[b], b) else b
        if not any(np.allclose(n, m) and abs(d - e) < PLANE_TOL_M for m, e in out[name]):
            out[name].append((n, d))
    return dict(out)


def set_back(mesh: Mesh, planes: Sequence[tuple[np.ndarray, float]], depth_m: float = SET_BACK_M) -> Mesh:
    """``mesh`` with its vertices on each of ``planes`` moved ``depth_m`` in behind it, so its faces there no longer share
    the plane. A part too thin to lose that much keeps the plane."""
    v = mesh.vertices.copy()
    for n, d in planes:
        along = mesh.vertices @ n
        if float(along.max() - along.min()) < 4.0 * depth_m:
            continue
        on = np.abs(along - d) < PLANE_TOL_M
        v[on] -= depth_m * n
    return dataclasses.replace(mesh, vertices=v)


__all__ = ["SET_BACK_M", "coplanar_overlaps", "flush_planes", "set_back"]
