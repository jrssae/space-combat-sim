"""The civilian ships' shared build pipeline (M5-T22, D59).

Every civilian generator places pieces (a part, the volume it buries, and whether it sits on the centre line or on the
right and is mirrored), samples them into splats, paints them through a style and writes levels, chunks and small
standalone models (turrets, cargo pods). Until T22 this was copied into each generator; the Bokmai is the first to use
this module.

Frames: the authored Godot frame (x to starboard, y up, z aft from the nose), then the body frame centred on the splat
centroid (``offset``); the PLY stores the body frame turned by Rz(180) (the GDGS orientation).
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..parts import Part
from ..parts.solids import Solid
from ..styles import Style
from . import frames, lighting
from .chunks import ChunkSource
from .context import BuildContext
from .geometry import Mesh
from .obj import write_obj
from .ply import SplatData, write_ply
from .sampling import SurfaceSamples, sample_mesh, to_splats

CENTRE, RIGHT = "c", "r"
JSON_DIGITS = 5


@dataclass(frozen=True)
class Piece:
    """One sampled component: ``solid`` is the volume it buries (``None``: it hides nothing), ``side`` is :data:`CENTRE`
    (symmetrised) or :data:`RIGHT` (mirrored to a left twin), ``fine`` scales its sampling spacing (thin parts are
    sampled finer so their outline survives)."""

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
    paint_name: str  # the right twin's name: both twins get the same panel pattern


def right_half_first(mesh: Mesh) -> Mesh:
    """The same faces with the right half's first, so systematic rounding gives a centre piece's halves equal shares and a
    coarse level keeps LOD0's centroid."""
    right = mesh.face_centroids()[:, 0] > 0.0
    order = np.concatenate([np.flatnonzero(right), np.flatnonzero(~right)])
    return Mesh(mesh.vertices, mesh.faces[order], mesh.face_material[order], mesh.materials)


def sample_pieces(
    pieces: Sequence[Piece],
    ctx: BuildContext,
    spacing: float,
    suffix: tuple[str, ...] = (),
    buried_margin: float = 0.03,
    extra_hidden: Callable[[Piece, SurfaceSamples], np.ndarray] | None = None,
) -> list[Sampled]:
    """Every piece sampled, samples buried in another piece dropped, centre pieces symmetrised and right pieces mirrored,
    in placement order. ``suffix`` keeps another level's random draws apart from LOD0's; ``extra_hidden`` may drop more
    samples of a piece (a mask over its samples)."""
    solids = [(p.name, p.solid, p.solid.bounds()) for p in with_twins(pieces) if p.solid is not None]
    out: list[Sampled] = []
    for p in pieces:
        step = spacing * p.fine
        mesh = p.part.mesh if p.side == RIGHT else right_half_first(p.part.mesh)
        s = sample_mesh(mesh, step, ctx.rng("splats", p.name, *suffix), systematic=True)
        if len(s):
            lo, hi = s.positions.min(axis=0), s.positions.max(axis=0)
            hidden = np.zeros(len(s), dtype=bool)
            for name, solid, (slo, shi) in solids:
                if name == p.name or np.any(shi < lo) or np.any(slo > hi):
                    continue
                hidden |= solid.contains(s.positions, buried_margin)
            if extra_hidden is not None:
                hidden |= extra_hidden(p, s)
            s = s.subset(~hidden)
        if p.side == CENTRE:
            out.append(Sampled(p, s.symmetrized("x"), step, p.name))
        else:
            out.append(Sampled(p, s, step, p.name))
            out.append(Sampled(p.mirrored(), s.mirrored("x"), step, p.name))
    return out


def centroid(sampled: Sequence[Sampled]) -> np.ndarray:
    """The splat centroid (x is zero by symmetry): the authored position of the body origin."""
    total = sum(len(s.samples) for s in sampled)
    mean = sum(s.samples.positions.sum(axis=0) for s in sampled) / total
    return np.array([0.0, float(mean[1]), float(mean[2])])


def panel_phase(name: str, style: Style) -> tuple[float, float, float]:
    """A per-piece shift of the panel grid so neighbouring pieces' lines do not line up."""
    h = sum((i + 1) * ord(c) for i, c in enumerate(name))
    return tuple(((h * k) % 97) / 97.0 * style.panel_size_m for k in (7, 11, 13))


def colour(s: Sampled, style: Style) -> np.ndarray:
    """Paint only (paint, panel lines mirrored across the centre line, tint): the scene's lights shade it in the game."""
    at = s.samples.positions.copy()
    at[:, 0] = np.abs(at[:, 0])
    paneled = s.samples.material_flag("paneled") > 0.5
    return style.shade_panels(s.samples.albedo(), at, s.samples.normals, paneled, panel_phase(s.paint_name, style))


def splats_of(s: Sampled, style: Style, offset: np.ndarray, overlap: float, thickness: float) -> SplatData:
    """One sampled piece as splats in the body frame."""
    return to_splats(s.samples.translated(-offset), colour(s, style), s.spacing, overlap, thickness)


def chunk_sources(
    sampled: Sequence[Sampled], order: Sequence[str], style: Style, offset: np.ndarray, overlap: float, thickness: float
) -> list[ChunkSource]:
    """One source per chunk group in ``order``: its pieces' splats and fallback mesh in the body frame."""
    sources = []
    for group in order:
        members = [s for s in sampled if s.piece.group == group]
        splats = SplatData.concatenate([splats_of(s, style, offset, overlap, thickness) for s in members])
        sources.append(ChunkSource(group, splats, Mesh.concatenate(s.piece.part.mesh.translated(-offset) for s in members)))
    return sources


def to_3dgs(splats: SplatData) -> SplatData:
    """Rz(180 deg) of the Godot frame: what the PLY stores, so the splat node stays at identity."""
    return SplatData(
        xyz=frames.godot_to_3dgs_positions(splats.xyz), rgb=splats.rgb, alpha=splats.alpha, scale=splats.scale,
        rot=frames.godot_to_3dgs_quats(splats.rot), normals=frames.flip_xy(splats.normals),
    )  # fmt: skip


def write_level(out_dir: Path, ply_name: str, light_name: str, splats: SplatData, comments: tuple[str, ...]) -> list[Path]:
    """A level's PLY (GDGS orientation) and its lighting record."""
    written = to_3dgs(splats)
    return [write_ply(out_dir / ply_name, written, comments), lighting.write_lighting(out_dir / light_name, written)]


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


# --- standalone models (turrets, cargo pods) ---------------------------------------------------------------------------
def sample_model(
    part: Part, solids: Sequence[Solid], style: Style, ctx: BuildContext, stream: str, spacing: float, overlap: float,
    thickness: float, buried_margin: float = 0.03,
) -> SplatData:  # fmt: skip
    """A small model in its own frame, sampled whole, its buried samples dropped and made mirror-symmetric in x."""
    s = sample_mesh(right_half_first(part.mesh), spacing, ctx.rng("splats", stream), systematic=True)
    hidden = np.zeros(len(s), dtype=bool)
    for solid in solids:
        hidden |= solid.contains(s.positions, buried_margin)
    sampled = Sampled(Piece(part), s.subset(~hidden).symmetrized("x"), spacing, stream)
    return to_splats(sampled.samples, colour(sampled, style), spacing, overlap, thickness)


def write_model(
    out_dir: Path, stem: str, part: Part, splats: SplatData, comments: tuple[str, ...], centred: bool = True,
    with_obj: bool = True,
) -> tuple[list[Path], np.ndarray]:
    """A model written like a chunk: ``<stem>.ply``, its lighting record and ``<stem>.obj``. Centred, the files sit on
    the splat centroid and the returned offset is that centroid in the model's frame (a turret); otherwise they keep the
    model's own origin (a cargo pod, whose origin is its mount) and the offset is still the centroid, for the importer,
    which subtracts it."""
    mean = splats.xyz.mean(axis=0)
    shift = mean if centred else np.zeros(3)
    moved = SplatData(splats.xyz - shift, splats.rgb, splats.alpha, splats.scale, splats.rot, splats.normals)
    files = write_level(out_dir, f"{stem}.ply", f"{stem}{lighting.SUFFIX}", moved, comments)
    if with_obj:
        files += write_obj(out_dir / f"{stem}.obj", part.mesh.translated(-shift), stem, comments[:1])
    return files, mean


def turret_entry(stem: str, part: Part, splats: SplatData, spacing: float, barrel_m: float, offset: np.ndarray) -> dict[str, Any]:
    """The manifest's ``turret`` entry, with the keys of ``parts/turret.py``'s."""
    return {
        "ply": f"{stem}.ply",
        "lighting": f"{stem}{lighting.SUFFIX}",
        "obj": f"{stem}.obj",
        "splats": len(splats),
        "spacing_m": spacing,
        "offset": r(offset),
        "barrel_m": round(barrel_m, JSON_DIGITS),
        "trunnion": r(part.anchor("trunnion").position),
        "muzzles": [r(part.anchor("muzzle_l").position), r(part.anchor("muzzle_r").position)],
    }


__all__ = [
    "CENTRE",
    "JSON_DIGITS",
    "RIGHT",
    "Piece",
    "Sampled",
    "centroid",
    "chunk_sources",
    "collision_json",
    "colour",
    "inertia_estimate",
    "left_name",
    "panel_phase",
    "r",
    "right_half_first",
    "sample_model",
    "sample_pieces",
    "splats_of",
    "to_3dgs",
    "turret_entry",
    "with_twins",
    "write_level",
    "write_model",
]
