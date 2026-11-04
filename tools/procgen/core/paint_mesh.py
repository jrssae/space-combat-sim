"""The painted mesh: a hull's own surface as a triangle mesh the game can draw instead of its splats (M4-T27, Q24).

The splats are sampled from the parts' meshes and painted by ``Style.shade_panels``; this writes the same meshes (the hull parts the
fallback OBJ holds) as one ``.glb`` whose shader paints the same panel lines and tint on the GPU, so splats and mesh share shape,
bounds and paint. Each vertex carries what the paint needs as integers in its UV:

* ``u = phase_x + 97 * phase_y`` and ``v = phase_z + 97 * material``, where ``phase_*`` are the part's panel phase in 97ths of
  the panel size (the assets' ``_phase`` already quantises to those) and ``material`` indexes the manifest's material table.

Vertices are split per material so a vertex never carries two; normals stay the part's smooth vertex normals, as in the OBJ.
Opaque faces form one primitive and see-through faces (canopy glass) a second, so a ship is one opaque draw per pass.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..styles import Style
from .geometry import Material, Mesh
from .glb import GlbPrimitive, write_glb

PHASE_STEPS = 97
SUFFIX = "_mesh.glb"


def file_name(asset_id: str) -> str:
    return f"{asset_id}{SUFFIX}"


def phase_steps(name: str, base_only: bool) -> tuple[int, int, int]:
    """A part's panel phase in 97ths of the panel size: the integers the assets' ``_phase`` scales."""
    key = name.split("_")[0] if base_only else name
    h = sum((i + 1) * ord(c) for i, c in enumerate(key))
    return tuple((h * k) % PHASE_STEPS for k in (7, 11, 13))


def phase_of(steps: Sequence[int], style: Style) -> tuple[float, float, float]:
    """The panel phase in metres, exactly as ``_phase`` computes it."""
    return tuple(int(s) / float(PHASE_STEPS) * style.panel_size_m for s in steps)


@dataclass(frozen=True)
class PaintPart:
    """A hull part's mesh and its panel phase (in 97ths)."""

    mesh: Mesh
    phase: tuple[int, int, int]


@dataclass
class PaintMesh:
    """The merged mesh: compact opaque and glass vertex sets, and the material table the UVs index."""

    opaque: GlbPrimitive
    glass: GlbPrimitive
    materials: tuple[Material, ...]

    @property
    def triangles(self) -> int:
        return (len(self.opaque.indices) + len(self.glass.indices)) // 3


def _compact(positions: np.ndarray, normals: np.ndarray, uv: np.ndarray, faces: np.ndarray, material: str, blend: bool) -> GlbPrimitive:
    used, inverse = np.unique(faces.reshape(-1), return_inverse=True)
    base = (0.6, 0.6, 0.6, 1.0) if not blend else (0.0, 0.0, 0.0, 0.3)
    return GlbPrimitive(positions[used], normals[used], uv[used], inverse.reshape(-1), material, base, blend)


def build_paint_mesh(parts: Sequence[PaintPart]) -> PaintMesh:
    """Merge ``parts`` into the opaque and glass primitives (materials shared by name, as ``Mesh.concatenate``)."""
    table: list[Material] = []
    by_name: dict[str, int] = {}
    positions, normals, uvs, faces, glass_flags = [], [], [], [], []
    offset = 0
    for part in parts:
        mesh = part.mesh
        if mesh.face_count == 0:
            continue
        remap = np.zeros(len(mesh.materials), dtype=np.int64)
        for i, m in enumerate(mesh.materials):
            if m.name not in by_name:
                by_name[m.name] = len(table)
                table.append(m)
            elif table[by_name[m.name]] != m:
                raise ValueError(f"material {m.name!r} defined twice with different values")
            remap[i] = by_name[m.name]
        face_mat = remap[mesh.face_material]
        vertex_normals = mesh.vertex_normals()
        # One vertex per (vertex, material): a vertex shared by faces of two materials is split.
        keys = mesh.faces * len(table) + face_mat[:, None]
        unique, inverse = np.unique(keys.reshape(-1), return_inverse=True)
        source = unique // len(table)
        mat = unique % len(table)
        px, py, pz = (int(v) for v in part.phase)
        u = np.full(len(unique), float(px + PHASE_STEPS * py))
        v = pz + PHASE_STEPS * mat.astype(float)
        positions.append(mesh.vertices[source])
        normals.append(vertex_normals[source])
        uvs.append(np.stack([u, v], axis=1))
        faces.append(inverse.reshape(-1, 3) + offset)
        transmittance = np.array([table[k].transmittance for k in face_mat])
        glass_flags.append(transmittance > 0.0)
        offset += len(unique)
    if not positions:
        raise ValueError("a paint mesh needs at least one face")
    all_pos = np.concatenate(positions)
    all_nrm = np.concatenate(normals)
    all_uv = np.concatenate(uvs)
    all_faces = np.concatenate(faces)
    glass = np.concatenate(glass_flags)
    return PaintMesh(
        _compact(all_pos, all_nrm, all_uv, all_faces[~glass], "paint", False),
        _compact(all_pos, all_nrm, all_uv, all_faces[glass], "glass", True),
        tuple(table),
    )


def manifest_entry(paint: PaintMesh, style: Style, file: str) -> dict[str, Any]:
    """The manifest's ``paint_mesh`` section: everything the game's paint shader needs besides the mesh."""
    lo = np.minimum(paint.opaque.positions.min(axis=0), paint.glass.positions.min(axis=0)) if len(paint.glass.positions) else paint.opaque.positions.min(axis=0)
    hi = np.maximum(paint.opaque.positions.max(axis=0), paint.glass.positions.max(axis=0)) if len(paint.glass.positions) else paint.opaque.positions.max(axis=0)
    return {
        "file": file,
        "triangles": paint.triangles,
        "glass_triangles": len(paint.glass.indices) // 3,
        "vertices": len(paint.opaque.positions) + len(paint.glass.positions),
        "aabb_min": [round(float(x), 5) for x in lo],
        "aabb_max": [round(float(x), 5) for x in hi],
        "phase_steps": PHASE_STEPS,
        "panel": {
            "size_m": style.panel_size_m,
            "line_width_m": style.panel_line_width_m,
            "line_darkness": style.panel_line_darkness,
            "tint_jitter": style.panel_tint_jitter,
        },
        "materials": [
            {
                "name": m.name,
                "albedo": [round(float(c), 6) for c in m.albedo],
                "paneled": bool(m.paneled),
                "transmittance": float(m.transmittance),
            }
            for m in paint.materials
        ],
    }


def write_paint_mesh(out_dir: Path, asset_id: str, parts: Sequence[PaintPart], style: Style) -> tuple[Path, dict[str, Any]]:
    """Write ``<asset_id>_mesh.glb`` and return it with its manifest section."""
    paint = build_paint_mesh(parts)
    name = file_name(asset_id)
    path = write_glb(Path(out_dir) / name, [paint.opaque, paint.glass], asset_id)
    return path, manifest_entry(paint, style, name)
