"""Big stand-in pieces drawn both ways (M4-T27, Q24): a set of meshes sampled into a chain of splat levels, and the same meshes as one
painted mesh, for the render comparison's station and capital hulls.

Each level's PLY is centred on its own splat centroid (GDGS subtracts the mean at import), and that centroid is recorded, so the game
places each level's node there and every level lines up with the painted mesh, which stays in the piece's own frame.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any

import numpy as np

from ..styles import Style
from . import frames, lighting
from .geometry import Mesh
from .manifest import lod_entry
from .paint_mesh import PaintPart, phase_of, write_paint_mesh
from .ply import SplatData, write_ply
from .sampling import DEFAULT_OVERLAP, DEFAULT_THICKNESS, sample_mesh, to_splats


def piece_splats(parts: Sequence[PaintPart], style: Style, spacing: float, rng: Callable[[str], np.random.Generator]) -> SplatData:
    """Every part sampled at ``spacing`` and painted with its panel phase, in the piece's frame (Godot axes)."""
    out = []
    for index, part in enumerate(parts):
        samples = sample_mesh(part.mesh, spacing, rng(f"part{index}"))
        if len(samples) == 0:
            continue
        rgb = style.shade_panels(
            samples.albedo(), samples.positions, samples.normals, samples.material_flag("paneled") > 0.5, phase_of(part.phase, style)
        )
        out.append(to_splats(samples, rgb, spacing, DEFAULT_OVERLAP, DEFAULT_THICKNESS))
    return SplatData.concatenate(out)


def _written(splats: SplatData, centroid: np.ndarray) -> SplatData:
    """Centred on ``centroid`` and turned Rz(180): what the PLY stores."""
    return SplatData(
        xyz=frames.godot_to_3dgs_positions(splats.xyz - centroid),
        rgb=splats.rgb,
        alpha=splats.alpha,
        scale=splats.scale,
        rot=frames.godot_to_3dgs_quats(splats.rot),
        normals=frames.flip_xy(splats.normals),
    )


def write_piece(
    out_dir: Path,
    name: str,
    parts: Sequence[PaintPart],
    style: Style,
    spacings: Sequence[float],
    rng: Callable[..., np.random.Generator],
    comments: tuple[str, ...],
) -> tuple[list[Path], dict[str, Any]]:
    """Write ``<name>_lod<k>.ply`` and ``.light`` per spacing, and ``<name>_mesh.glb``; return the files and the piece's entry."""
    files: list[Path] = []
    lods: list[dict[str, Any]] = []
    bounds: list[np.ndarray] = []
    for level, spacing in enumerate(spacings):
        splats = piece_splats(parts, style, spacing, lambda stream, lv=level: rng(name, stream, f"lod{lv}"))
        centroid = splats.xyz.mean(axis=0)
        written = _written(splats, centroid)
        ply_name = f"{name}_lod{level}.ply"
        light_name = f"{name}_lod{level}{lighting.SUFFIX}"
        files.append(write_ply(Path(out_dir) / ply_name, written, comments + (f"lod {level}",)))
        files.append(lighting.write_lighting(Path(out_dir) / light_name, written))
        entry = lod_entry(level, ply_name, len(splats), spacing, light_name)
        entry["centroid"] = [round(float(c), 5) for c in centroid]
        lods.append(entry)
        if level == 0:
            bounds = [splats.xyz.min(axis=0), splats.xyz.max(axis=0)]
    mesh_path, mesh_entry = write_paint_mesh(out_dir, name, parts, style)
    files.append(mesh_path)
    return files, {
        "lods": lods,
        "aabb_min": [round(float(c), 5) for c in bounds[0]],
        "aabb_max": [round(float(c), 5) for c in bounds[1]],
        "paint_mesh": mesh_entry,
    }


def mesh_of(parts: Sequence[PaintPart]) -> Mesh:
    return Mesh.concatenate(p.mesh for p in parts)
