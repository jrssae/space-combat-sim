"""Break-up chunks (docs/architecture.md section 15.11): the hull's splats partitioned by part group, one PLY and
one fallback OBJ per chunk.

A chunk's splats and mesh are re-centred on the chunk's own splat centroid (GDGS centres every PLY on its mean
position anyway), and its PLY is flipped into the 3DGS frame exactly like the hull's, so a debris node at identity
shows the chunk upright once it is placed at ``ship transform * offset``. ``offset`` is that centroid in the body
frame. Written generically: any asset whose parts carry a group can give chunks.

The caller builds the hull PLY as the chunks' splats concatenated in the same order, so the chunks together hold
exactly the hull's splats.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from . import frames
from .geometry import Mesh
from .obj import write_obj
from .ply import SplatData, write_ply


@dataclass
class ChunkSource:
    """One group's splats (body frame, Godot axes) and fallback mesh (same frame)."""

    name: str
    splats: SplatData
    mesh: Mesh


def chunk_file_names(asset_id: str, name: str) -> tuple[str, str]:
    return f"{asset_id}_chunk_{name}.ply", f"{asset_id}_chunk_{name}.obj"


def write_chunks(
    out_dir: Path, asset_id: str, sources: Sequence[ChunkSource], comments: Sequence[str] = ()
) -> tuple[list[Path], list[dict[str, Any]]]:
    """Writes ``<id>_chunk_<name>.ply`` and ``.obj`` for every source; returns the files and the
    ``hardpoints.chunks[]`` entries ``{name, ply, obj, offset, splats}``."""
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
        files += write_obj(out_dir / obj_name, source.mesh.translated(-centroid), f"{asset_id}_chunk_{source.name}", comments[:1])
        entries.append(
            {
                "name": source.name,
                "ply": ply_name,
                "obj": obj_name,
                "offset": [round(float(v), 5) + 0.0 for v in centroid],
                "splats": len(source.splats),
            }
        )
    return files, entries
