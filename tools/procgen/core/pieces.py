"""Big stand-in pieces (M4-T27, Q24; textured in M4-T30d): a set of meshes written as one textured mesh in the piece's own frame,
for the station and the capital hulls.

A piece's parts go on one atlas with their markings (window rows, say), the entry's ``mesh`` section (``core/textured_mesh.py``).
Big pieces bake the normal map at the atlas's size and without occlusion.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..styles import Style
from .geometry import Mesh
from .sections import SectionCut
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
    out_dir: Path, name: str, parts: Sequence[TexturedPart], style: Style, texture: PieceTexture, sections: Sequence[SectionCut] = ()
) -> tuple[list[Path], dict[str, Any]]:
    """Write the textured mesh ``<name>.glb`` and its maps; return the files and the piece's entry: its bounds and its ``mesh``.
    With ``sections`` (M7-T19) the mesh is also written cut into them, listed in ``mesh.sections``."""
    bounds = mesh_of(parts).vertices
    files, section = write_textured_mesh(out_dir, name, list(parts), style, atlas_px=texture.atlas_px, texel_m=texture.texel_m,
                                         seed=texture.seed, occlusion=texture.occlusion, normal_scale=texture.normal_scale,
                                         grid=texture.grid, sections=sections)
    entry: dict[str, Any] = {
        "aabb_min": [round(float(c), 5) for c in np.min(bounds, axis=0)],
        "aabb_max": [round(float(c), 5) for c in np.max(bounds, axis=0)],
        "mesh": section,
    }
    return files, entry


def mesh_of(parts: Sequence[TexturedPart]) -> Mesh:
    return Mesh.concatenate(p.mesh for p in parts)
