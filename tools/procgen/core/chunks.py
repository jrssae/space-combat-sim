"""Break-up chunks (docs/architecture.md section 15.11): a hull's parts grouped by chunk, one OBJ per chunk and its place on the ship.

A chunk is centred on its own surface samples' centroid, so a debris node at identity shows the chunk upright once it is placed at
``ship transform * offset``. ``offset`` is that centroid in the body frame. Written generically: any asset whose parts carry a group
can give chunks.

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

from .geometry import Mesh
from .obj import write_obj


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
    """One group's surface sample positions (body frame, Godot axes), which place it, and its mesh (same frame)."""

    name: str
    points: np.ndarray
    mesh: Mesh


def chunk_file_name(asset_id: str, name: str) -> str:
    return f"{asset_id}_chunk_{name}.obj"


def write_chunks(
    out_dir: Path, asset_id: str, sources: Sequence[ChunkSource], comments: Sequence[str] = (), with_meshes: bool = False
) -> tuple[list[Path], list[dict[str, Any]]]:
    """Writes ``<id>_chunk_<name>.obj`` for every source; returns the files and the ``hardpoints.chunks[]`` entries
    ``{name, obj, offset}``, plus ``mesh`` (the chunk's textured mesh, which the caller writes from its cuts) when ``with_meshes``."""
    files: list[Path] = []
    entries: list[dict[str, Any]] = []
    for source in sources:
        if len(source.points) == 0:
            raise ValueError(f"chunk {source.name!r} has no surface samples")
        centroid = np.asarray(source.points, dtype=float).mean(axis=0)
        obj_name = chunk_file_name(asset_id, source.name)
        files += write_obj(out_dir / obj_name, source.mesh.translated(-centroid), f"{asset_id}_chunk_{source.name}", comments[:1])
        entries.append(
            {
                "name": source.name,
                "obj": obj_name,
                "offset": [round(float(v), 5) + 0.0 for v in centroid],
                **({"mesh": chunk_mesh_name(asset_id, source.name)} if with_meshes else {}),
            }
        )
    return files, entries


def chunk_offsets(sources: Sequence[ChunkSource]) -> dict[str, np.ndarray]:
    """Each chunk's offset as ``write_chunks`` records it: its samples' centroid, in the chunks' frame."""
    return {source.name: np.asarray(source.points, dtype=float).mean(axis=0) for source in sources}
