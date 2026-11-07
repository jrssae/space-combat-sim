"""The civilian ships' shared build pipeline (M5-T22, D59; textured meshes from M5-T27).

Every civilian generator places pieces (a part, the volume it buries, and whether it sits on the centre line or on the
right and is mirrored), samples their visible surface for the body origin and the chunks' offsets, and writes the hull,
its break-up chunks and small standalone models (turrets, cargo pods) as M4's textured meshes (``core/textured_mesh.py``).

Frames: the authored Godot frame (x to starboard, y up, z aft from the nose), then the body frame centred on the visible
surface's centroid (``offset``, the manifest's ``centroid_offset``). The ``.glb``, the OBJs and ``hardpoints.json`` are all
in the body frame.

The texture pack: each faction's style carries its plating and wear at a fighter's scale (a centimetre texel);
:func:`at_texel` scales the wear, the seams and the noise to the texel the hull's atlas ends up with, so a 260 m freighter
and a 4 m turret read the same paint.
"""

from __future__ import annotations

import dataclasses
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..parts import Part
from ..parts.solids import Solid
from ..styles import Style
from .chunks import ChunkCut, ChunkSource, chunk_offsets, write_chunks
from .context import BuildContext
from .geometry import Mesh
from .obj import write_obj
from .sampling import SurfaceSamples, sample_mesh
from .textured_mesh import DEFAULT_TEXEL_M, TexturedPart, pack_parts, phase_steps, write_textured_mesh
from .textures import Marking

CENTRE, RIGHT = "c", "r"
JSON_DIGITS = 5
HULL_ATLAS_PX = 2048  # every civilian hull: 4 to 16 cm a texel from the Bokmai to the Saturn 8s
MODEL_ATLAS_PX = 1024  # a turret or a cargo pod
LINE_TEXELS = 2.0  # a panel seam is never thinner than this many texels, so it survives the mipmaps


@dataclass(frozen=True)
class Piece:
    """One component: ``solid`` is the volume it buries (``None``: it hides nothing), ``side`` is :data:`CENTRE`
    (symmetrised) or :data:`RIGHT` (mirrored to a left twin), ``fine`` scales its sampling spacing (thin parts are
    sampled finer so their outline counts)."""

    part: Part
    solid: Solid | None = None
    side: str = CENTRE
    fine: float = 1.0

    @property
    def name(self) -> str:
        return self.part.name

    @property
    def group(self) -> str:
        return self.part.group

    def mirrored(self) -> Piece:
        """The left twin of a right piece, named and grouped ``_l`` for ``_r``."""
        solid = None if self.solid is None else self.solid.mirrored("x")
        return Piece(self.part.mirrored("x").renamed(left_name(self.name), group=left_name(self.group)), solid, self.side, self.fine)


def left_name(name: str) -> str:
    """``arm_r`` -> ``arm_l``; a name without the suffix is a centre name and stays."""
    return name[:-2] + "_l" if name.endswith("_r") else name


def with_twins(pieces: Sequence[Piece]) -> list[Piece]:
    """The pieces plus each right piece's left twin, twin after original."""
    out: list[Piece] = []
    for p in pieces:
        out.append(p)
        if p.side == RIGHT:
            out.append(p.mirrored())
    return out


@dataclass
class Sampled:
    piece: Piece
    samples: SurfaceSamples
    spacing: float
    paint_name: str  # the right twin's name: both twins get the same panel phase


def right_half_first(mesh: Mesh) -> Mesh:
    """The same faces with the right half's first, so systematic rounding gives a centre piece's halves equal shares."""
    right = mesh.face_centroids()[:, 0] > 0.0
    order = np.concatenate([np.flatnonzero(right), np.flatnonzero(~right)])
    return Mesh(mesh.vertices, mesh.faces[order], mesh.face_material[order], mesh.materials)


def sample_pieces(
    pieces: Sequence[Piece],
    ctx: BuildContext,
    spacing: float,
    suffix: tuple[str, ...] = (),
    buried_margin: float = 0.03,
) -> list[Sampled]:
    """Every piece's visible surface: samples buried in another piece dropped, centre pieces symmetrised and right pieces
    mirrored, in placement order."""
    solids = [(p.name, p.solid, p.solid.bounds()) for p in with_twins(pieces) if p.solid is not None]
    out: list[Sampled] = []
    for p in pieces:
        step = spacing * p.fine
        mesh = p.part.mesh if p.side == RIGHT else right_half_first(p.part.mesh)
        s = sample_mesh(mesh, step, ctx.rng("surface", p.name, *suffix), systematic=True)
        if len(s):
            lo, hi = s.positions.min(axis=0), s.positions.max(axis=0)
            hidden = np.zeros(len(s), dtype=bool)
            for name, solid, (slo, shi) in solids:
                if name == p.name or np.any(shi < lo) or np.any(slo > hi):
                    continue
                hidden |= solid.contains(s.positions, buried_margin)
            s = s.subset(~hidden)
        if p.side == CENTRE:
            out.append(Sampled(p, s.symmetrized("x"), step, p.name))
        else:
            out.append(Sampled(p, s, step, p.name))
            out.append(Sampled(p.mirrored(), s.mirrored("x"), step, p.name))
    return out


def centroid(sampled: Sequence[Sampled]) -> np.ndarray:
    """The visible surface's centroid (x is zero by symmetry): the authored position of the body origin."""
    total = sum(len(s.samples) for s in sampled)
    mean = sum(s.samples.positions.sum(axis=0) for s in sampled) / total
    return np.array([0.0, float(mean[1]), float(mean[2])])


# --- the textured hull -------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class HullPart:
    """A hull part ready for the textured mesh, in the body frame: its mesh, its chunk, its visible surface points (they
    place the chunk), the name its panel phase comes from (twins share it) and what is painted on it."""

    name: str
    group: str
    mesh: Mesh
    points: np.ndarray
    paint_name: str = ""
    markings: tuple[Marking, ...] = ()


@dataclass
class HullFiles:
    """What :func:`write_hull` wrote: the files, the manifest's ``mesh`` section, the ``hardpoints.chunks[]`` entries, the
    hull's box and its mesh (body frame)."""

    files: list[Path]
    mesh_section: dict[str, Any]
    chunks: list[dict[str, Any]]
    aabb_min: np.ndarray
    aabb_max: np.ndarray
    mesh: Mesh


def hull_parts(sampled: Sequence[Sampled], offset: np.ndarray, markings: dict[str, tuple[Marking, ...]] | None = None) -> list[HullPart]:
    """The sampled pieces as hull parts in the body frame; ``markings`` by piece name (authored frame, moved here too)."""
    marks = markings or {}
    return [
        HullPart(s.piece.name, s.piece.group, s.piece.part.mesh.translated(-offset), s.samples.positions - offset, s.paint_name,
                 tuple(moved_marking(m, -offset) for m in marks.get(s.piece.name, ())))
        for s in sampled
    ]  # fmt: skip


def moved_marking(marking: Marking, by: Sequence[float]) -> Marking:
    """A marking moved with its part: every point it is placed by shifts, its directions stay."""
    params = dict(marking.params)
    for key in ("centre", "exit"):
        if key in params:
            params[key] = tuple(float(a) + float(b) for a, b in zip(params[key], by, strict=True))
    return dataclasses.replace(marking, params=params)


def at_texel(style: Style, texel_m: float) -> Style:
    """The style's texture pack scaled to a hull texelled at ``texel_m``: its wear, noise, grooves and rivets are sized for a
    fighter at a centimetre a texel, so a bigger texel scales them up; a seam stays at least ``LINE_TEXELS`` texels wide."""
    k = max(1.0, float(texel_m) / DEFAULT_TEXEL_M)
    base = float(style.extra.get("wear_scale", 1.0))
    return dataclasses.replace(
        style,
        panel_line_width_m=max(style.panel_line_width_m, LINE_TEXELS * texel_m),
        groove_depth_m=style.groove_depth_m * k,
        hatch_depth_m=style.hatch_depth_m * k,
        edge_wear_width_m=style.edge_wear_width_m * k,
        grime_scale_m=style.grime_scale_m * k,
        extra={**style.extra, "wear_scale": base * k},
    )


def _textured(parts: Sequence[HullPart]) -> list[TexturedPart]:
    return [TexturedPart(p.mesh, phase_steps(p.paint_name or p.name, False), p.markings, p.name) for p in parts if p.mesh.face_count > 0]


def texel_of(parts: Sequence[TexturedPart], atlas_px: int) -> float:
    """The texel the atlas packs the parts at: from the area a texel would have with the atlas two thirds full, grown by the
    packer until every chart fits."""
    area = sum(p.mesh.area() for p in parts)
    start = max(float(np.sqrt(area / (0.66 * atlas_px * atlas_px))), 1e-4)
    return float(pack_parts(parts, atlas_px, start).packed.texel_m)


def write_hull(
    out_dir: Path,
    asset_id: str,
    parts: Sequence[HullPart],
    chunk_order: Sequence[str],
    style: Style,
    ctx: BuildContext,
    comments: Sequence[str] = (),
) -> HullFiles:
    """The hull as ``<id>.glb`` with its maps, the fallback ``<id>.obj`` and one chunk per group in ``chunk_order``
    (``<id>_chunk_<name>.obj`` and its cut of the textured mesh, placed by its visible surface's centroid). Options:
    ``atlas_px`` (default 2 048) and ``occlusion`` (default off: the hulls are far bigger than the occlusion radius)."""
    out_dir = Path(out_dir)
    unknown = {p.group for p in parts} - set(chunk_order)
    if unknown:
        raise ValueError(f"{asset_id}: parts in unlisted chunks {sorted(unknown)}")
    hull_mesh = Mesh.concatenate(p.mesh for p in parts)
    files: list[Path] = write_obj(out_dir / f"{asset_id}.obj", hull_mesh, asset_id, tuple(comments)[:1])
    sources = []
    for group in chunk_order:
        members = [p for p in parts if p.group == group]
        points = [p.points for p in members if len(p.points)]
        if not points:
            raise ValueError(f"{asset_id}: chunk {group!r} has no visible surface")
        sources.append(ChunkSource(group, np.concatenate(points), Mesh.concatenate(p.mesh for p in members)))
    chunk_files, chunk_entries = write_chunks(out_dir, asset_id, sources, tuple(comments), with_meshes=True)
    files += chunk_files

    textured = _textured(parts)
    atlas_px = int(ctx.option("atlas_px", HULL_ATLAS_PX))
    texel = texel_of(textured, atlas_px)
    offsets = chunk_offsets(sources)
    names = {t.name for t in textured}
    cuts = [ChunkCut(g, tuple(p.name for p in parts if p.group == g and p.name in names), tuple(float(v) for v in offsets[g]))
            for g in chunk_order]  # fmt: skip
    paths, section = write_textured_mesh(
        out_dir, asset_id, textured, at_texel(style, texel), atlas_px=atlas_px, texel_m=texel, seed=ctx.seed,
        occlusion=bool(ctx.option("occlusion", False)), normal_scale=1, chunks=cuts,
    )  # fmt: skip
    files += paths
    lo, hi = hull_mesh.bounds()
    return HullFiles(files, section, chunk_entries, lo, hi, hull_mesh)


def write_model(
    out_dir: Path,
    stem: str,
    meshes: Sequence[tuple[str, Mesh]],
    style: Style,
    ctx: BuildContext,
    comments: Sequence[str] = (),
    markings: tuple[Marking, ...] = (),
) -> tuple[list[Path], dict[str, Any]]:
    """A standalone model (a turret, a cargo pod) in its own frame: ``<stem>.obj`` and ``<stem>.glb`` with its own maps;
    returns the files and the model's ``mesh`` section. ``meshes`` pairs each part's name with its mesh."""
    out_dir = Path(out_dir)
    whole = Mesh.concatenate(m for _, m in meshes)
    files: list[Path] = write_obj(out_dir / f"{stem}.obj", whole, stem, tuple(comments)[:1])
    textured = [TexturedPart(m, phase_steps(name, False), markings if k == 0 else (), name) for k, (name, m) in enumerate(meshes)]
    atlas_px = int(ctx.option("model_atlas_px", MODEL_ATLAS_PX))
    texel = texel_of(textured, atlas_px)
    paths, section = write_textured_mesh(out_dir, stem, textured, at_texel(style, texel), atlas_px=atlas_px, texel_m=texel,
                                         seed=ctx.seed, occlusion=bool(ctx.option("occlusion", False)), normal_scale=1)
    return files + paths, section


def r(v: Any, digits: int = JSON_DIGITS) -> list[float]:
    """A vector for the JSON files: rounded, no negative zeros."""
    return [round(float(x), digits) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def collision_json(parts: Sequence[Part], offset: np.ndarray) -> list[dict[str, Any]]:
    """Every part's collision primitives in the body frame, named ``<part>_<shape>``."""
    out = []
    for part in parts:
        for shape in part.collision:
            out.append({**shape.to_json(offset=offset, digits=JSON_DIGITS), "name": f"{part.name}_{shape.name}" if shape.name else part.name})
    return out


def inertia_estimate(parts: Sequence[Part], com: np.ndarray) -> np.ndarray:
    """Diagonal inertia of the parts as point masses at their area centroids (informational; ``ShipSpec`` rules)."""
    inertia = np.zeros(3)
    for part in parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array([d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2])
    return inertia


def turret_entry(stem: str, part: Part, barrel_m: float, section: dict[str, Any]) -> dict[str, Any]:
    """The manifest's ``turret`` entry: its mesh (in the turret's frame, the pivot at the origin), the fallback OBJ, the
    barrel's reach, the trunnion and the muzzles."""
    return {
        "obj": f"{stem}.obj",
        "mesh": section,
        "barrel_m": round(barrel_m, JSON_DIGITS),
        "trunnion": r(part.anchor("trunnion").position),
        "muzzles": [r(part.anchor("muzzle_l").position), r(part.anchor("muzzle_r").position)],
    }


__all__ = [
    "CENTRE",
    "JSON_DIGITS",
    "RIGHT",
    "HullFiles",
    "HullPart",
    "Piece",
    "Sampled",
    "at_texel",
    "centroid",
    "collision_json",
    "hull_parts",
    "inertia_estimate",
    "left_name",
    "moved_marking",
    "r",
    "right_half_first",
    "sample_pieces",
    "texel_of",
    "turret_entry",
    "with_twins",
    "write_hull",
    "write_model",
]
