"""Sections of a big piece (M7-T19, D72): the piece's textured mesh cut across its long axis (z) into slabs, each written as a glb of
its own with its own origin, so the renderer picks a level of detail per section and culls the sections out of view.

The cut runs after the atlas is packed and the normals are made, on the piece's own triangles: a triangle across a cut plane is
clipped exactly (positions, normals and UVs interpolated along its edges), so the sections tile the piece with no gap and no
overlap, a texel lands where it did on the whole piece, and the shading is the same on both sides of a joint.

The importer simplifies each section on its own and does not hold a section's border still, so two neighbours drawn at different
levels can open a hairline crack along their joint. Each section therefore carries a skirt: a short wall in the cut plane hanging
inward from its border, painted and shaded as the border is, so a crack shows hull, not space.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from .glb import GlbPrimitive, write_glb

EPS_M = 1e-6
SKIRT_M = 6.0  # how far a skirt reaches into the hull: more than a level's chord error near the joint, less than a thin part


@dataclass(frozen=True)
class SectionCut:
    """One section: the slab of the piece between ``z0`` and ``z1`` (the piece's frame; the first and last open-ended)."""

    name: str
    z0: float
    z1: float


def section_mesh_name(asset_id: str, name: str) -> str:
    return f"{asset_id}_sec_{name}.glb"


def cuts_from_planes(names: Sequence[str], planes: Sequence[float]) -> tuple[SectionCut, ...]:
    """Sections between consecutive cut planes (ascending); the first and the last reach to the piece's ends."""
    if len(names) != len(planes) + 1:
        raise ValueError("one more section than cut planes")
    if any(b <= a for a, b in zip(planes[:-1], planes[1:], strict=True)):
        raise ValueError("cut planes must ascend")
    if len(set(names)) != len(names):
        raise ValueError("section names must be unique")
    edges = [-np.inf, *[float(p) for p in planes], np.inf]
    return tuple(SectionCut(n, a, b) for n, a, b in zip(names, edges[:-1], edges[1:], strict=True))


def _clip(poly: list[np.ndarray], z: float, keep_above: bool) -> list[np.ndarray]:
    """One side of a convex polygon (rows: position, normal, uv) of the plane at ``z``. The point on an edge is computed from its
    endpoints in a fixed order, so two triangles sharing the edge get the same point."""
    out: list[np.ndarray] = []
    n = len(poly)
    for k in range(n):
        a, b = poly[k], poly[(k + 1) % n]
        ina = a[2] >= z - EPS_M if keep_above else a[2] <= z + EPS_M
        inb = b[2] >= z - EPS_M if keep_above else b[2] <= z + EPS_M
        if ina:
            out.append(a)
        if ina != inb:
            p, q = (a, b) if tuple(a) <= tuple(b) else (b, a)
            t = (z - p[2]) / (q[2] - p[2])
            point = p + t * (q - p)
            point[2] = z
            out.append(point)
    return out


@dataclass
class SectionCorners:
    """A section's triangles as corners: positions, normals and UVs (``(n, 3, k)``), and which are glass."""

    positions: np.ndarray
    normals: np.ndarray
    uvs: np.ndarray
    glass: np.ndarray


def cut_corners(positions: np.ndarray, normals: np.ndarray, uvs: np.ndarray, glass: np.ndarray,
                cuts: Sequence[SectionCut]) -> list[SectionCorners]:
    """The triangles (corner arrays ``(n, 3, 3)``, ``(n, 3, 3)``, ``(n, 3, 2)`` and a glass flag per face) in each section of
    ``cuts``. A triangle within one slab goes whole to it (one in a cut plane to the section above); one across planes is
    clipped into each slab it crosses."""
    planes = np.array([c.z0 for c in cuts[1:]], dtype=float)
    zmin, zmax = positions[:, :, 2].min(axis=1), positions[:, :, 2].max(axis=1)
    lo = np.searchsorted(planes, zmin + EPS_M, side="right")
    hi = np.searchsorted(planes, zmax - EPS_M, side="right")
    whole = hi <= lo
    home = np.where(whole, np.searchsorted(planes, positions[:, :, 2].mean(axis=1), side="right"), -1)
    acc: list[list[tuple[np.ndarray, np.ndarray, np.ndarray, bool]]] = [[] for _ in cuts]
    for f in np.flatnonzero(~whole):
        tri = [np.concatenate([positions[f, k], normals[f, k], uvs[f, k]]) for k in range(3)]
        for s in range(int(lo[f]), int(hi[f]) + 1):
            poly = tri
            if np.isfinite(cuts[s].z0):
                poly = _clip(poly, cuts[s].z0, True)
            if len(poly) >= 3 and np.isfinite(cuts[s].z1):
                poly = _clip(poly, cuts[s].z1, False)
            for j in range(1, len(poly) - 1):
                c = np.array([poly[0], poly[j], poly[j + 1]])
                if np.linalg.norm(np.cross(c[1, :3] - c[0, :3], c[2, :3] - c[0, :3])) < 1e-9:
                    continue
                n = c[:, 3:6] / np.maximum(np.linalg.norm(c[:, 3:6], axis=1, keepdims=True), 1e-12)
                acc[s].append((c[:, :3], n, c[:, 6:8], bool(glass[f])))
    out = []
    for s in range(len(cuts)):
        mine = np.flatnonzero(home == s)
        extra = acc[s]
        p = np.concatenate([positions[mine], np.array([e[0] for e in extra]).reshape(-1, 3, 3)])
        n = np.concatenate([normals[mine], np.array([e[1] for e in extra]).reshape(-1, 3, 3)])
        u = np.concatenate([uvs[mine], np.array([e[2] for e in extra]).reshape(-1, 3, 2)])
        g = np.concatenate([glass[mine], np.array([e[3] for e in extra], dtype=bool)])
        out.append(SectionCorners(p, n, u, g))
    return out


def skirts(corners: SectionCorners, planes: Sequence[tuple[float, float]], depth: float = SKIRT_M) -> SectionCorners:
    """Walls in each cut plane hanging ``depth`` into the hull from the section's border edges there (edges of one triangle each,
    on a surface crossing the plane), each corner with its border vertex's normal and UV. ``planes`` are (z, side): a wall faces
    out of its section (side +1 at the section's aft cut, -1 at its fore cut), so across a crack one of the two neighbours' walls
    faces the eye."""
    out_p, out_n, out_u = [], [], []
    for c, side in planes:
        on = np.abs(corners.positions[:, :, 2] - c) < 1e-4
        for f in np.flatnonzero(on.sum(axis=1) == 2):
            i, j = [k for k in range(3) if on[f, k]]
            pa, pb = corners.positions[f, i], corners.positions[f, j]
            na, nb = corners.normals[f, i], corners.normals[f, j]
            ua, ub = corners.uvs[f, i], corners.uvs[f, j]
            da, db = -np.array([na[0], na[1], 0.0]), -np.array([nb[0], nb[1], 0.0])
            if np.linalg.norm(da) < 0.3 or np.linalg.norm(db) < 0.3 or np.linalg.norm(pb - pa) < 1e-6:
                continue  # a face lying in the plane, or a border running into it: no wall to hang
            qa, qb = pa + depth * da / np.linalg.norm(da), pb + depth * db / np.linalg.norm(db)
            for tri, nrm, uv in (((pa, pb, qb), (na, nb, nb), (ua, ub, ub)), ((pa, qb, qa), (na, nb, na), (ua, ub, ua))):
                facing = np.cross(tri[1] - tri[0], tri[2] - tri[0])[2] * side
                order = (0, 1, 2) if facing > 0.0 else (0, 2, 1)
                out_p.append([tri[k] for k in order])
                out_n.append([nrm[k] for k in order])
                out_u.append([uv[k] for k in order])
    if not out_p:
        return SectionCorners(np.zeros((0, 3, 3)), np.zeros((0, 3, 3)), np.zeros((0, 3, 2)), np.zeros(0, dtype=bool))
    return SectionCorners(np.array(out_p), np.array(out_n), np.array(out_u), np.zeros(len(out_p), dtype=bool))


def _joined(a: SectionCorners, b: SectionCorners) -> SectionCorners:
    return SectionCorners(np.concatenate([a.positions, b.positions]), np.concatenate([a.normals, b.normals]),
                          np.concatenate([a.uvs, b.uvs]), np.concatenate([a.glass, b.glass]))


def _primitive(corners: SectionCorners, glass: bool, origin: np.ndarray, name: str, base: tuple[float, float, float, float]) -> GlbPrimitive:
    faces = np.flatnonzero(corners.glass == glass)
    if len(faces) == 0:
        return GlbPrimitive(np.zeros((0, 3)), np.zeros((0, 3)), np.zeros((0, 2)), [], name, base, glass)
    p = corners.positions[faces].reshape(-1, 3)
    n = corners.normals[faces].reshape(-1, 3)
    u = np.round(corners.uvs[faces].reshape(-1, 2).astype(np.float32), 7).astype(np.float64)
    keys = np.concatenate([np.round(p, 5), np.round(n, 5), u], axis=1)
    unique, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    return GlbPrimitive(p[first] - origin, n[first], u[first], inverse.reshape(-1), name, base, glass)


def write_sections(out_dir: Path, asset_id: str, positions: np.ndarray, normals: np.ndarray, uvs: np.ndarray, glass: np.ndarray,
                   cuts: Sequence[SectionCut], names: tuple[str, str], bases: tuple[tuple[float, ...], tuple[float, ...]]
                   ) -> tuple[list[Path], list[dict[str, Any]]]:
    """Write each section's glb (its opaque and glass primitives, named as the whole piece's ``names``, so it draws with the
    piece's materials) and return the files and the manifest's ``sections`` entries: ``name``, ``file``, ``origin`` (in the piece's
    frame: on the axis, half way along the section's triangles), ``z0`` and ``z1`` (its slab, ``null`` at an open end),
    ``aabb_min`` and ``aabb_max`` (about its origin), ``triangles`` (the hull's) and ``skirt_triangles``. A section with no
    triangles is left out."""
    files: list[Path] = []
    entries: list[dict[str, Any]] = []
    for cut, corners in zip(cuts, cut_corners(positions, normals, uvs, glass, cuts), strict=True):
        if len(corners.glass) == 0:
            continue
        pts = corners.positions.reshape(-1, 3)
        lo, hi = pts.min(axis=0), pts.max(axis=0)
        origin = np.array([0.0, 0.0, round(0.5 * float(lo[2] + hi[2]), 3)])
        skirt = skirts(corners, [(z, side) for z, side in ((cut.z0, -1.0), (cut.z1, 1.0)) if np.isfinite(z)])
        drawn = _joined(corners, skirt)
        prims = [_primitive(drawn, g, origin, names[int(g)], bases[int(g)]) for g in (False, True)]
        file = section_mesh_name(asset_id, cut.name)
        files.append(write_glb(out_dir / file, prims, f"{asset_id}_sec_{cut.name}"))
        entries.append({
            "name": cut.name,
            "file": file,
            "origin": [float(c) for c in origin],
            "z0": float(cut.z0) if np.isfinite(cut.z0) else None,
            "z1": float(cut.z1) if np.isfinite(cut.z1) else None,
            "aabb_min": [round(float(c), 5) for c in lo - origin],
            "aabb_max": [round(float(c), 5) for c in hi - origin],
            "triangles": int(len(corners.glass)),
            "skirt_triangles": int(len(skirt.glass)),
        })
    return files, entries


__all__ = ["SKIRT_M", "SectionCut", "SectionCorners", "cut_corners", "cuts_from_planes", "section_mesh_name", "skirts", "write_sections"]
