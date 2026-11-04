"""The textured mesh (M4-T30a): a hull's parts as one ``.glb`` with a UV atlas and four texture maps, the contract M5 builds against
(docs/milestones/m4-performance-and-scale.md, "The contract M5 builds against").

``write_textured_mesh(out_dir, asset_id, parts, style, atlas_px)`` writes ``<asset_id>.glb`` (primitive 0 the opaque hull, primitive 1 the
glass), ``<asset_id>_albedo/_normal/_orm/_emissive.png`` with a Godot ``.import`` sidecar each (VRAM compressed, mipmaps, the normal
map flagged), and returns the manifest's ``mesh`` section. The parts are T27's painted-mesh parts with markings: the same triangles
and bounds as the painted mesh and the fallback OBJ.
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
from .image import write_png
from .livery import digit_atlas, digit_import_sidecar, livery_section
from .paint_mesh import PHASE_STEPS, phase_of
from .raster import dilate, rasterize, sharp_edges
from .textures import Atlas, Marking, bake_maps, surface_emissive_strength
from .uv_atlas import Packed, charts_of, pack

DEFAULT_ATLAS_PX = 2048
DEFAULT_TEXEL_M = 0.01
GUTTER_PX = 2
MAP_KEYS = ("albedo", "normal", "orm", "emissive")
DIGITS_KEY = "digits"
OPAQUE_SURFACE = "hull"
GLASS_SURFACE = "glass"


@dataclass(frozen=True)
class TexturedPart:
    """A hull part's mesh, its panel phase (in 97ths, as ``PaintPart``) and the markings painted on it."""

    mesh: Mesh
    phase: tuple[int, int, int]
    markings: tuple[Marking, ...] = ()
    name: str = ""
    zone: int = 0  # the livery zone its vertices carry (``core/livery.py``; 0: never painted)


def _material_table(parts: Sequence[TexturedPart]) -> tuple[tuple[Material, ...], list[np.ndarray]]:
    """One material table for every part (shared by name) and each part's remap into it."""
    table: list[Material] = []
    by_name: dict[str, int] = {}
    remaps = []
    for part in parts:
        remap = np.zeros(max(len(part.mesh.materials), 1), dtype=np.int64)
        for i, m in enumerate(part.mesh.materials):
            if m.name not in by_name:
                by_name[m.name] = len(table)
                table.append(m)
            elif table[by_name[m.name]] != m:
                raise ValueError(f"material {m.name!r} defined twice with different values")
            remap[i] = by_name[m.name]
        remaps.append(remap)
    return tuple(table), remaps


@dataclass
class PackedParts:
    """Every part's faces in one atlas: the merged mesh, per-face ids and the 0..1 UVs."""

    mesh: Mesh  # every part concatenated (the material table shared)
    face_part: np.ndarray
    face_uv01: np.ndarray
    face_chart: np.ndarray
    packed: Packed
    vertex_zone: np.ndarray  # per merged-mesh vertex


def pack_parts(parts: Sequence[TexturedPart], atlas_px: int, texel_m: float, gutter_px: int = GUTTER_PX) -> PackedParts:
    used = [p for p in parts if p.mesh.face_count > 0]
    if not used:
        raise ValueError("a textured mesh needs at least one face")
    merged = Mesh.concatenate([p.mesh for p in used])
    face_part = np.concatenate([np.full(p.mesh.face_count, k, dtype=np.int64) for k, p in enumerate(parts) if p.mesh.face_count > 0])
    charts = charts_of(merged)
    packed = pack(charts, texel_m, atlas_px, gutter_px)
    vertex_zone = np.concatenate([np.full(len(p.mesh.vertices), p.zone, dtype=np.int64) for p in used])
    return PackedParts(merged, face_part, packed.face_uv01(merged.face_count), packed.face_chart(merged.face_count), packed, vertex_zone)


def atlas_of(parts: Sequence[TexturedPart], atlas_px: int = DEFAULT_ATLAS_PX, texel_m: float = DEFAULT_TEXEL_M,
             style_phase_m: float | None = None) -> Atlas:
    """Pack ``parts`` and rasterise the atlas buffers: what ``bake_maps`` paints from."""
    packed = pack_parts(parts, atlas_px, texel_m)
    mesh = packed.mesh
    corners = mesh.vertices[mesh.faces]
    normals = mesh.vertex_normals()[mesh.faces]
    buffers = rasterize(atlas_px, packed.face_uv01, corners, normals, packed.face_part, mesh.face_material, packed.face_chart,
                        sharp_edges(mesh))
    dilate(buffers, GUTTER_PX)
    panel = style_phase_m if style_phase_m is not None else 0.6
    phases = tuple(tuple(int(s) / float(PHASE_STEPS) * panel for s in p.phase) for p in parts)
    markings = tuple(m for p in parts for m in p.markings)
    return Atlas(buffers, mesh.materials, tuple(p.name for p in parts), phases, markings, packed.packed.texel_m, mesh)


def _primitives(parts: Sequence[TexturedPart], packed: PackedParts, zones: bool = False) -> tuple[GlbPrimitive, GlbPrimitive]:
    """The opaque and glass primitives: a glb vertex per (mesh vertex, UV), normals the parts' smooth vertex normals; with ``zones``
    each vertex's livery zone in COLOR_0's red (zone / 255)."""
    mesh = packed.mesh
    normals = mesh.vertex_normals()
    transmittance = np.array([m.transmittance for m in mesh.materials], dtype=float)[mesh.face_material]
    glass_face = transmittance > 0.0
    out = []
    for glass in (False, True):
        faces = np.flatnonzero(glass_face == glass)
        if len(faces) == 0:
            out.append(GlbPrimitive(np.zeros((0, 3)), np.zeros((0, 3)), np.zeros((0, 2)), [], GLASS_SURFACE if glass else OPAQUE_SURFACE,
                                    (0.0, 0.0, 0.0, 0.3) if glass else (1.0, 1.0, 1.0, 1.0), glass))
            continue
        corner_vertex = mesh.faces[faces].reshape(-1)
        corner_uv = np.round(packed.face_uv01[faces].reshape(-1, 2).astype(np.float32), 7)
        keys = np.concatenate([corner_vertex[:, None].astype(np.float64), corner_uv.astype(np.float64)], axis=1)
        unique, inverse = np.unique(keys, axis=0, return_inverse=True)
        source = unique[:, 0].astype(np.int64)
        base = (0.0, 0.0, 0.0, 0.3) if glass else (1.0, 1.0, 1.0, 1.0)
        colors = None
        if zones:
            colors = np.zeros((len(source), 4))
            colors[:, 0] = packed.vertex_zone[source] / 255.0
            colors[:, 3] = 1.0
        out.append(GlbPrimitive(mesh.vertices[source], normals[source], unique[:, 1:3], inverse.reshape(-1), GLASS_SURFACE if glass else OPAQUE_SURFACE,
                                base, glass, colors=colors))
    return out[0], out[1]


def import_sidecar(kind: str) -> str:
    """Godot's ``.import`` for one map: VRAM compressed with mipmaps; the normal map flagged, the linear maps packed as data."""
    normal_map = {"albedo": 2, "emissive": 2, "normal": 1, "orm": 2}[kind]
    channel_pack = {"albedo": 0, "emissive": 0, "normal": 1, "orm": 1}[kind]
    return (
        "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n"
        "compress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/uastc_level=0\ncompress/rdo_quality_loss=0.0\n"
        f"compress/hdr_compression=1\ncompress/normal_map={normal_map}\ncompress/channel_pack={channel_pack}\n"
        "mipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=\"\"\n"
        "process/channel_remap/red=0\nprocess/channel_remap/green=1\nprocess/channel_remap/blue=2\nprocess/channel_remap/alpha=3\n"
        "process/fix_alpha_border=true\nprocess/premult_alpha=false\nprocess/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\n"
        "process/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n"
    )


def manifest_section(asset_id: str, parts: Sequence[TexturedPart], packed: PackedParts, primitives: Sequence[GlbPrimitive],
                     maps: dict[str, np.ndarray], atlas: Atlas) -> dict[str, Any]:
    mesh = packed.mesh
    lo, hi = mesh.bounds()
    files = {key: f"{asset_id}_{key}.png" for key in MAP_KEYS}
    surfaces = []
    for primitive, glass in zip(primitives, (False, True), strict=True):
        if len(primitive.indices) == 0:
            continue
        transmittance = max((m.transmittance for m in mesh.materials if (m.transmittance > 0.0) == glass), default=0.0)
        surfaces.append({
            "name": primitive.material,
            "blend": bool(glass),
            **files,
            "transmittance": round(float(transmittance), 6),
            "emissive_strength": round(float(surface_emissive_strength(mesh.materials, glass)), 6),
        })
    return {
        "file": f"{asset_id}.glb",
        "triangles": int(mesh.face_count),
        "vertices": int(sum(len(p.positions) for p in primitives)),
        "aabb_min": [round(float(x), 5) for x in lo],
        "aabb_max": [round(float(x), 5) for x in hi],
        "texel_m": round(float(atlas.texel_m), 6),
        "atlas_px": int(atlas.buffers.size),
        "atlas_fill": round(float(packed.packed.fill), 4),
        "mean_albedo": [round(float(c), 6) for c in maps["mean_albedo"]],
        "surfaces": surfaces,
        "lods": [],
    }


def write_textured_mesh(out_dir: Path, asset_id: str, parts: Sequence[TexturedPart], style: Style, atlas_px: int = DEFAULT_ATLAS_PX,
                        texel_m: float = DEFAULT_TEXEL_M, seed: int = 0, occlusion: bool = True,
                        paintable: Sequence[str] = ()) -> tuple[list[Path], dict[str, Any]]:
    """Write the textured mesh of ``parts`` into ``out_dir`` and return its files and the manifest's ``mesh`` section. With
    ``paintable`` material names the hull takes wing liveries (M4-T30b): the vertices carry their parts' zones, the albedo's alpha
    says where paint may go, and the digit atlas and the ``livery`` section are written too."""
    out_dir = Path(out_dir)
    packed = pack_parts(parts, atlas_px, texel_m)
    mesh = packed.mesh
    buffers = rasterize(atlas_px, packed.face_uv01, mesh.vertices[mesh.faces], mesh.vertex_normals()[mesh.faces], packed.face_part,
                        mesh.face_material, packed.face_chart, sharp_edges(mesh))
    dilate(buffers, GUTTER_PX)
    phases = tuple(phase_of(p.phase, style) for p in parts)
    atlas = Atlas(buffers, mesh.materials, tuple(p.name for p in parts), phases, tuple(m for p in parts for m in p.markings),
                  packed.packed.texel_m, mesh)
    maps = bake_maps(atlas, style, seed, occlusion, paintable)
    opaque, glass = _primitives(parts, packed, zones=bool(paintable))
    paths = [write_glb(out_dir / f"{asset_id}.glb", [opaque, glass], asset_id)]
    for key in MAP_KEYS:
        png = out_dir / f"{asset_id}_{key}.png"
        paths.append(write_png(png, maps[key]))
        sidecar = Path(str(png) + ".import")
        sidecar.write_text(import_sidecar(key), encoding="utf-8", newline="\n")
        paths.append(sidecar)
    section = manifest_section(asset_id, parts, packed, [opaque, glass], maps, atlas)
    if paintable:
        digits = out_dir / f"{asset_id}_{DIGITS_KEY}.png"
        paths.append(write_png(digits, digit_atlas()))
        sidecar = Path(str(digits) + ".import")
        sidecar.write_text(digit_import_sidecar(), encoding="utf-8", newline="\n")
        paths.append(sidecar)
        hull = style.materials.get("hull")
        section["livery"] = livery_section(digits.name, hull.albedo if hull is not None else (0.35, 0.35, 0.35))
    return paths, section


__all__ = ["DEFAULT_ATLAS_PX", "DEFAULT_TEXEL_M", "PackedParts", "TexturedPart", "atlas_of", "import_sidecar", "pack_parts",
           "write_textured_mesh"]
