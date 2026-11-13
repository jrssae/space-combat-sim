"""Near-only detail props (M7-T19, D72): small parts repeated over a big piece, drawn instanced and only within a near range, with
textures of their own, so their fine detail (numbers, grates, clamps) does not hang on the piece's metre-a-texel atlas.

A prop kind is a small mesh whose UVs point into one shared prop atlas (four maps, as a textured mesh's). A group is one kind's
copies within one section of the piece, each a transform in that section's frame; the game draws a group as one instanced mesh
(a ``MultiMeshInstance3D``) under the section, shown within ``near_m`` and faded out over ``margin_m``. Past the range the piece's
own atlas carries a painted stand-in, so nothing pops to nothing.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from .geometry import Mesh
from .glb import GlbPrimitive, write_glb
from .image import write_png
from .textured_mesh import MAP_KEYS, import_sidecar

SURFACE = "prop"


@dataclass(frozen=True)
class PropKind:
    """A prop's mesh in its own frame; its ``face_uv`` are already in the prop atlas (0..1). ``near_m``: a draw range of its own,
    for a kind that has no painted stand-in on the piece (the Cobra bays' door leaves are the doors)."""

    name: str
    mesh: Mesh
    near_m: float | None = None


@dataclass(frozen=True)
class PropGroup:
    """Copies of one kind in one section: each transform (3x4: rotation, then translation) places the prop in the section's frame."""

    kind: str
    section: str
    transforms: tuple[np.ndarray, ...]


def prop_mesh_name(asset_id: str, kind: str) -> str:
    return f"{asset_id}_prop_{kind}.glb"


def _primitive(mesh: Mesh) -> GlbPrimitive:
    """Flat shaded corners, welded where position, normal and UV agree."""
    corners = mesh.vertices[mesh.faces].reshape(-1, 3)
    normals = np.repeat(mesh.face_normals(), 3, axis=0)
    uv = np.round(mesh.face_uv.reshape(-1, 2).astype(np.float32), 7).astype(np.float64)
    keys = np.concatenate([np.round(corners, 5), np.round(normals, 5), uv], axis=1)
    _, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    return GlbPrimitive(corners[first], normals[first], uv[first], inverse.reshape(-1), SURFACE)


def _flat(t: np.ndarray) -> list[float]:
    """A 3x4 transform as the manifest writes it: the basis' x, y and z columns, then the origin."""
    t = np.asarray(t, dtype=float).reshape(3, 4)
    return [round(float(v), 5) for v in np.concatenate([t[:, 0], t[:, 1], t[:, 2], t[:, 3]])]


def write_props(out_dir: Path, asset_id: str, kinds: Sequence[PropKind], groups: Sequence[PropGroup],
                maps: Mapping[str, np.ndarray], emissive_strength: float, near_m: float, margin_m: float
                ) -> tuple[list[Path], dict[str, Any]]:
    """Write each kind's glb and the prop atlas's maps; return the files and the piece's ``props`` entry: ``near_m``,
    ``margin_m``, ``surface`` (the atlas's maps, as a textured mesh's surface), ``kinds`` (file and box per kind) and ``groups``
    (kind, section, transforms, and the box of the copies in the section's frame)."""
    names = [k.name for k in kinds]
    if len(set(names)) != len(names):
        raise ValueError("prop kinds must have unique names")
    files: list[Path] = []
    entry_kinds: dict[str, Any] = {}
    for kind in kinds:
        file = prop_mesh_name(asset_id, kind.name)
        files.append(write_glb(out_dir / file, [_primitive(kind.mesh)], f"{asset_id}_prop_{kind.name}"))
        lo, hi = kind.mesh.bounds()
        entry_kinds[kind.name] = {"file": file, "triangles": kind.mesh.face_count, "aabb_min": [round(float(c), 5) for c in lo],
                                  "aabb_max": [round(float(c), 5) for c in hi]}
        if kind.near_m is not None:
            entry_kinds[kind.name]["near_m"] = float(kind.near_m)
    surface: dict[str, Any] = {"name": SURFACE, "blend": False, "transmittance": 0.0,
                               "emissive_strength": round(float(emissive_strength), 6)}
    for key in MAP_KEYS:
        name = f"{asset_id}_props_{key}.png"
        png = write_png(out_dir / name, maps[key])
        sidecar = Path(str(png) + ".import")
        sidecar.write_text(import_sidecar(key), encoding="utf-8", newline="\n")
        files += [png, sidecar]
        surface[key] = name
    entry_groups = []
    by_name = {k.name: k for k in kinds}
    for group in groups:
        if group.kind not in by_name or not group.transforms:
            raise ValueError(f"prop group {group.kind!r} in {group.section!r}: unknown kind or no copies")
        points = by_name[group.kind].mesh.vertices
        placed = np.concatenate([points @ np.asarray(t)[:, :3].T + np.asarray(t)[:, 3] for t in group.transforms])
        entry_groups.append({"kind": group.kind, "section": group.section, "transforms": [_flat(t) for t in group.transforms],
                             "aabb_min": [round(float(c), 5) for c in placed.min(axis=0)],
                             "aabb_max": [round(float(c), 5) for c in placed.max(axis=0)]})
    entry = {"near_m": float(near_m), "margin_m": float(margin_m), "surface": surface, "kinds": entry_kinds, "groups": entry_groups}
    return files, entry


__all__ = ["PropGroup", "PropKind", "SURFACE", "prop_mesh_name", "write_props"]
