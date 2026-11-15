"""Big stand-in pieces (M4-T27, Q24; textured in M4-T30d): a set of meshes written as one textured mesh in the piece's own frame,
for the station and the capital hulls.

A piece's parts go on one atlas with their markings (window rows, say), the entry's ``mesh`` section (``core/textured_mesh.py``).
Big pieces bake the normal map at the atlas's size and without occlusion.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..styles import Style
from .geometry import Mesh
from .glb import GlbPrimitive, write_glb
from .sections import EPS_M, SectionCut
from .textured_mesh import TexturedPart, write_textured_mesh


@dataclass(frozen=True)
class PieceTexture:
    """How a piece's textured mesh is baked: the atlas's size, the texel to start packing at, the seed, the normal map's scale,
    occlusion and the generic plating."""

    atlas_px: int
    texel_m: float
    seed: int = 0
    normal_scale: int = 1
    occlusion: bool = False
    grid: bool = True  # the generic staggered plating; off for a piece whose parts carry drawn layouts (M7-T04)


def write_piece(
    out_dir: Path, name: str, parts: Sequence[TexturedPart], style: Style, texture: PieceTexture, sections: Sequence[SectionCut] = (),
    interior: Callable[[np.ndarray, np.ndarray], np.ndarray] | None = None
) -> tuple[list[Path], dict[str, Any]]:
    """Write the textured mesh ``<name>.glb`` and its maps; return the files and the piece's entry: its bounds and its ``mesh``.
    With ``sections`` (M7-T19) the mesh is also written cut into them, listed in ``mesh.sections``; ``interior`` flags the faces
    inside its halls and bays (``write_textured_mesh``)."""
    bounds = mesh_of(parts).vertices
    files, section = write_textured_mesh(out_dir, name, list(parts), style, atlas_px=texture.atlas_px, texel_m=texture.texel_m,
                                         seed=texture.seed, occlusion=texture.occlusion, normal_scale=texture.normal_scale,
                                         grid=texture.grid, sections=sections, interior=interior)
    entry: dict[str, Any] = {
        "aabb_min": [round(float(c), 5) for c in np.min(bounds, axis=0)],
        "aabb_max": [round(float(c), 5) for c in np.max(bounds, axis=0)],
        "mesh": section,
    }
    return files, entry


def mesh_of(parts: Sequence[TexturedPart]) -> Mesh:
    return Mesh.concatenate(p.mesh for p in parts)


@dataclass(frozen=True)
class Tier:
    """One texel tier of a big piece (M7-T24): the run of its sections that share an atlas, the atlas's size, and how many times
    smaller its low texture set is written."""

    name: str
    sections: tuple[str, ...]
    atlas_px: int
    low_shrink: int = 1
    texel_m: float | None = None  # the texel the packer starts at (it grows it until the charts fit); else the piece's
    high_quality_albedo: bool = False  # its colour map imported with the better compression (seen up close: no colour noise)


def _slab_of(cuts: Sequence[SectionCut], names: Sequence[str]) -> tuple[float, float]:
    """The z span of a run of consecutive sections."""
    picked = [c for c in cuts if c.name in names]
    order = [c.name for c in cuts]
    first = order.index(picked[0].name)
    if [c.name for c in picked] != order[first:first + len(picked)]:
        raise ValueError(f"a tier's sections must be consecutive: {list(names)}")
    return picked[0].z0, picked[-1].z1


def clip_mesh(mesh: Mesh, z0: float, z1: float) -> Mesh:
    """The part of ``mesh`` between the planes ``z0`` and ``z1``: faces across a plane clipped exactly (their metre UVs with them),
    each new point made from its edge's endpoints in a fixed order, so the faces either side of a cut share it."""
    zc = mesh.vertices[mesh.faces][:, :, 2]
    # A face lying in a cut plane goes to the slab above it, as the sections take it (``cut_corners``).
    on_top = (np.abs(zc - z1) <= EPS_M).all(axis=1) if np.isfinite(z1) else np.zeros(len(zc), dtype=bool)
    inside = (zc >= z0 - EPS_M).all(axis=1) & (zc <= z1 + EPS_M).all(axis=1) & ~on_top
    outside = ~inside & ((zc <= z0 + EPS_M).all(axis=1) | (zc >= z1 - EPS_M).all(axis=1))
    vertices = list(mesh.vertices)
    made: dict[tuple[int, int, float], int] = {}
    faces, mats, charts, uvs = [], [], [], []

    def point(a: tuple[int, np.ndarray], b: tuple[int, np.ndarray], z: float) -> tuple[int, np.ndarray]:
        (ia, ua), (ib, ub) = (a, b) if a[0] < b[0] else (b, a)
        pa, pb = vertices[ia], vertices[ib]
        t = (z - pa[2]) / (pb[2] - pa[2])
        key = (ia, ib, z)
        if key not in made:
            q = pa + t * (pb - pa)
            q[2] = z
            made[key] = len(vertices)
            vertices.append(q)
        return made[key], ua + t * (ub - ua)

    def clip(poly: list[tuple[int, np.ndarray]], z: float, keep_above: bool) -> list[tuple[int, np.ndarray]]:
        out = []
        for k in range(len(poly)):
            a, b = poly[k], poly[(k + 1) % len(poly)]
            za, zb = vertices[a[0]][2], vertices[b[0]][2]
            ina = za >= z - EPS_M if keep_above else za <= z + EPS_M
            inb = zb >= z - EPS_M if keep_above else zb <= z + EPS_M
            if ina:
                out.append(a)
            if ina != inb:
                out.append(point(a, b, z))
        return out

    for f in np.flatnonzero(~inside & ~outside):
        poly = [(int(mesh.faces[f, k]), mesh.face_uv[f, k]) for k in range(3)]
        if np.isfinite(z0):
            poly = clip(poly, z0, True)
        if len(poly) >= 3 and np.isfinite(z1):
            poly = clip(poly, z1, False)
        for j in range(1, len(poly) - 1):
            tri = (poly[0], poly[j], poly[j + 1])
            if len({t[0] for t in tri}) < 3:
                continue
            faces.append([t[0] for t in tri])
            uvs.append([t[1] for t in tri])
            mats.append(mesh.face_material[f])
            charts.append(mesh.face_chart[f])
    keep = np.flatnonzero(inside)
    all_faces = np.concatenate([mesh.faces[keep], np.array(faces, dtype=np.int64).reshape(-1, 3)])
    all_uv = np.concatenate([mesh.face_uv[keep], np.array(uvs, dtype=np.float64).reshape(-1, 3, 2)])
    all_mat = np.concatenate([mesh.face_material[keep], np.array(mats, dtype=np.int64)])
    all_chart = np.concatenate([mesh.face_chart[keep], np.array(charts, dtype=np.int64)])
    used = np.unique(all_faces)
    remap = np.full(len(vertices), -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    return Mesh(np.asarray(vertices)[used], remap[all_faces], all_mat, mesh.materials, all_chart, all_uv)


def write_tiered_piece(
    out_dir: Path, name: str, parts: Sequence[TexturedPart], style: Style, tiers: Sequence[Tier], sections: Sequence[SectionCut],
    texel_m: float, seed: int, detail_levels: dict[str, int], interior: Callable[[np.ndarray, np.ndarray], np.ndarray] | None = None
) -> tuple[list[Path], dict[str, Any]]:
    """A big piece written in texel tiers (M7-T24): each tier is a run of its sections with an atlas of its own, so the places seen up
    close get a finer texel than the long runs seen from afar. Each tier is written as ``write_piece`` writes a piece
    (``<name>_<tier>``, its surfaces named ``hull_<tier>`` and ``glass_<tier>``, its ``detail_levels`` sets, the low one
    ``low_shrink`` times smaller), its parts clipped at its end planes. The entry is the piece's: its bounds and a ``mesh`` whose
    ``surfaces`` and ``sections`` are every tier's, ``tiers`` each tier's atlas, and ``file`` the whole piece untextured (for the
    tools)."""
    out_dir = Path(out_dir)
    covered = [s for t in tiers for s in t.sections]
    if covered != [c.name for c in sections]:
        raise ValueError("the tiers must list every section once, in order")
    files: list[Path] = []
    surfaces: list[dict[str, Any]] = []
    entries: list[dict[str, Any]] = []
    tier_info: list[dict[str, Any]] = []
    for tier in tiers:
        z0, z1 = _slab_of(sections, tier.sections)
        clipped = []
        for part in parts:
            mesh = clip_mesh(part.mesh, z0, z1)
            if mesh.face_count > 0:
                clipped.append(TexturedPart(mesh, part.phase, part.markings, part.name, part.zone, part.seams))
        cuts = [c for c in sections if c.name in tier.sections]
        written, section = write_textured_mesh(
            out_dir, f"{name}_{tier.name}", clipped, style, atlas_px=tier.atlas_px, texel_m=tier.texel_m or texel_m, seed=seed,
            occlusion=False,
            normal_scale=1, grid=False, detail_levels=detail_levels, sections=cuts, interior=interior, surface_suffix=f"_{tier.name}",
            detail_shrink={k: tier.low_shrink for k in detail_levels}, high_quality_keys=("albedo",) if tier.high_quality_albedo else ())
        files += written
        surfaces += section["surfaces"]
        entries += section.get("sections", [])
        tier_info.append({"name": tier.name, "sections": list(tier.sections), "area_m2": round(sum(p.mesh.area() for p in clipped), 1), "z0": None if not np.isfinite(z0) else float(z0),
                          "z1": None if not np.isfinite(z1) else float(z1), "file": section["file"],
                          **{k: section[k] for k in ("triangles", "vertices", "texel_m", "atlas_px", "atlas_fill", "map_px", "mean_albedo")}})
    whole = mesh_of(parts)
    normals = whole.vertex_normals()
    files.append(write_glb(out_dir / f"{name}.glb", [GlbPrimitive(whole.vertices, normals, np.zeros((whole.vertex_count, 2)),
                                                                   whole.faces.reshape(-1), "hull")], name))
    lo, hi = whole.bounds()
    areas = np.array([t["area_m2"] for t in tier_info], dtype=float)
    mesh_entry: dict[str, Any] = {
        "file": f"{name}.glb",
        "triangles": int(whole.face_count),
        "vertices": int(sum(t["vertices"] for t in tier_info)),
        "atlas_px": max(int(t["atlas_px"]) for t in tier_info),
        "aabb_min": [round(float(x), 5) for x in lo],
        "aabb_max": [round(float(x), 5) for x in hi],
        "texel_m": min(t["texel_m"] for t in tier_info),
        "mean_albedo": [round(float(c), 6) for c in np.average([t["mean_albedo"] for t in tier_info], axis=0, weights=areas)],
        "surfaces": surfaces,
        "sections": entries,
        "tiers": tier_info,
        "lods": [],
    }
    entry: dict[str, Any] = {
        "aabb_min": [round(float(c), 5) for c in lo],
        "aabb_max": [round(float(c), 5) for c in hi],
        "mesh": mesh_entry,
    }
    return files, entry
