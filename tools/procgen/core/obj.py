"""Wavefront OBJ/MTL writer (fallback meshes) and a small reader for tests.

Godot's OBJ importer reads vertices as-is (Y up, right handed, -Z forward), so meshes are
written in the Godot frame exactly like the hardpoints. Output is deterministic: fixed
precision, LF newlines, no timestamps. ``Kd`` is written sRGB-encoded because
``StandardMaterial3D.albedo_color`` is an sRGB ``source_color``; splat colours stay linear.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from .color import linear_to_srgb
from .geometry import Material, Mesh

PRECISION = 5


def _num(value: float) -> str:
    text = f"{value:.{PRECISION}f}"
    return "0." + "0" * PRECISION if text == "-" + "0." + "0" * PRECISION else text


def _vec(values: Sequence[float]) -> str:
    return " ".join(_num(float(v)) for v in values)


def mtl_text(materials: Sequence[Material]) -> str:
    lines = ["# space-combat-sim procgen material library"]
    for m in materials:
        kd = linear_to_srgb(np.asarray(m.albedo, dtype=float))
        lines += [
            "",
            f"newmtl {m.name}",
            "Ka 0.000000 0.000000 0.000000",
            f"Kd {_vec(kd)}",
            f"Ks {_vec([0.04 + 0.3 * m.metallic] * 3)}",
            f"Ns {20.0 + 60.0 * m.metallic:.1f}",
            f"d {1.0 - m.transmittance:.4f}",
            "illum 2",
        ]
    return "\n".join(lines) + "\n"


def obj_text(mesh: Mesh, object_name: str, mtl_file: str | None, comments: Sequence[str] = ()) -> str:
    """OBJ with smooth vertex normals (``f v//n``), faces grouped by material."""
    lines = ["# space-combat-sim procgen"] + [f"# {c}" for c in comments]
    if mtl_file:
        lines.append(f"mtllib {mtl_file}")
    lines.append(f"o {object_name}")
    normals = mesh.vertex_normals()
    lines += [f"v {_vec(v)}" for v in mesh.vertices]
    lines += [f"vn {_vec(n)}" for n in normals]
    faces1 = mesh.faces + 1
    for mat_index, material in enumerate(mesh.materials):
        selected = faces1[mesh.face_material == mat_index]
        if len(selected) == 0:
            continue
        lines.append(f"g {material.name}")
        lines.append(f"usemtl {material.name}")
        lines += [f"f {a}//{a} {b}//{b} {c}//{c}" for a, b, c in selected]
    return "\n".join(lines) + "\n"


def write_obj(path: Path, mesh: Mesh, object_name: str, comments: Sequence[str] = (), with_mtl: bool = True) -> list[Path]:
    """Write ``<path>`` (OBJ) and, with ``with_mtl``, ``<path with .mtl>``; returns the files written."""
    path = Path(path)
    mtl_path = path.with_suffix(".mtl")
    files = []
    if with_mtl:
        mtl_path.write_text(mtl_text(mesh.materials), encoding="ascii", newline="\n")
        files.append(mtl_path)
    path.write_text(obj_text(mesh, object_name, mtl_path.name if with_mtl else None, comments), encoding="ascii", newline="\n")
    return [path, *files]


@dataclass
class ObjFile:
    vertices: np.ndarray
    normals: np.ndarray
    faces: np.ndarray  # (M, 3) zero-based vertex indices
    face_materials: list[str] = field(default_factory=list)
    mtllib: str | None = None

    @property
    def materials(self) -> list[str]:
        return sorted(set(self.face_materials))


def read_obj(path: Path) -> ObjFile:
    """Parse the subset this package writes (``v``, ``vn``, ``f`` triangles, ``usemtl``, ``mtllib``)."""
    verts, normals, faces, mats = [], [], [], []
    current = ""
    mtllib = None
    for raw in Path(path).read_text(encoding="ascii").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        tag, rest = parts[0], parts[1:]
        if tag == "v":
            verts.append([float(x) for x in rest[:3]])
        elif tag == "vn":
            normals.append([float(x) for x in rest[:3]])
        elif tag == "usemtl":
            current = rest[0] if rest else ""
        elif tag == "mtllib":
            mtllib = rest[0] if rest else None
        elif tag == "f":
            idx = [int(p.split("/")[0]) - 1 for p in rest]
            if len(idx) != 3:
                raise ValueError(f"non-triangle face in {path}: {line!r}")
            faces.append(idx)
            mats.append(current)
    return ObjFile(
        np.array(verts, dtype=float).reshape(-1, 3),
        np.array(normals, dtype=float).reshape(-1, 3),
        np.array(faces, dtype=np.int64).reshape(-1, 3),
        mats,
        mtllib,
    )
