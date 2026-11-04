"""Break-up chunks (docs/architecture.md section 15.11): the hull's splats partitioned by part group, one PLY, its
lighting records and one fallback OBJ per chunk.

A chunk's splats and mesh are re-centred on the chunk's own splat centroid (GDGS centres every PLY on its mean
position anyway), and its PLY is flipped into the 3DGS frame exactly like the hull's, so a debris node at identity
shows the chunk upright once it is placed at ``ship transform * offset``. ``offset`` is that centroid in the body
frame. Written generically: any asset whose parts carry a group can give chunks.

The caller builds the hull PLY as the chunks' splats concatenated in the same order, so the chunks together hold
exactly the hull's splats.

A chunk's textured mesh (M4-T30d) is cut from the parent's textured mesh (``ChunkCut``, written by
``textured_mesh.write_textured_mesh``): the parent's faces of the chunk's parts, re-centred on the same offset, on the parent's
UVs, so it is drawn with the parent's maps and materials and names no map of its own. ``hardpoints.chunks[]`` gain its ``mesh``.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from . import frames, lighting
from .geometry import Mesh
from .obj import write_obj
from .ply import SplatData, write_ply


@dataclass(frozen=True)
class ChunkCut:
    """A chunk's textured mesh: the parent's faces of ``parts`` (part names), moved so ``offset`` (in the textured mesh's frame) is
    the chunk's origin."""

    name: str
    parts: tuple[str, ...]
    offset: tuple[float, float, float]


def chunk_mesh_name(asset_id: str, name: str) -> str:
    return f"{asset_id}_chunk_{name}.glb"


@dataclass
class ChunkSource:
    """One group's splats (body frame, Godot axes) and fallback mesh (same frame)."""

    name: str
    splats: SplatData
    mesh: Mesh


def chunk_file_names(asset_id: str, name: str) -> tuple[str, str]:
    return f"{asset_id}_chunk_{name}.ply", f"{asset_id}_chunk_{name}.obj"


def write_chunks(
    out_dir: Path, asset_id: str, sources: Sequence[ChunkSource], comments: Sequence[str] = (), with_meshes: bool = False
) -> tuple[list[Path], list[dict[str, Any]]]:
    """Writes ``<id>_chunk_<name>.ply``, ``.light`` and ``.obj`` for every source; returns the files and the
    ``hardpoints.chunks[]`` entries ``{name, ply, lighting, obj, offset, splats}``, plus ``mesh`` (the chunk's textured mesh, which
    the caller writes from its cuts) when ``with_meshes``."""
    files: list[Path] = []
    entries: list[dict[str, Any]] = []
    for source in sources:
        if len(source.splats) == 0:
            raise ValueError(f"chunk {source.name!r} has no splats")
        centroid = source.splats.xyz.mean(axis=0)
        centred = SplatData(
            xyz=frames.godot_to_3dgs_positions(source.splats.xyz - centroid),
            rgb=source.splats.rgb,
            alpha=source.splats.alpha,
            scale=source.splats.scale,
            rot=frames.godot_to_3dgs_quats(source.splats.rot),
            normals=None if source.splats.normals is None else frames.flip_xy(source.splats.normals),
        )
        ply_name, obj_name = chunk_file_names(asset_id, source.name)
        files.append(write_ply(out_dir / ply_name, centred, tuple(comments) + (f"chunk {source.name}",)))
        light_name = lighting.chunk_file_name(asset_id, source.name)
        files.append(lighting.write_lighting(out_dir / light_name, centred))
        files += write_obj(out_dir / obj_name, source.mesh.translated(-centroid), f"{asset_id}_chunk_{source.name}", comments[:1])
        entries.append(
            {
                "name": source.name,
                "ply": ply_name,
                "lighting": light_name,
                "obj": obj_name,
                "offset": [round(float(v), 5) + 0.0 for v in centroid],
                "splats": len(source.splats),
                **({"mesh": chunk_mesh_name(asset_id, source.name)} if with_meshes else {}),
            }
        )
    return files, entries


def chunk_offsets(sources: Sequence[ChunkSource]) -> dict[str, np.ndarray]:
    """Each chunk's offset as ``write_chunks`` records it: its splats' centroid, in the chunks' frame."""
    return {source.name: source.splats.xyz.mean(axis=0) for source in sources}
