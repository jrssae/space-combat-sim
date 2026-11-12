"""The texture maps of a hull (M4-T30a): colour, normal, occlusion/roughness/metal and emissive, baked from the atlas buffers.

Every map is a function of what ``core/raster.py`` knows per texel (world position, normal, part, material, distance to a sharp
edge), so the paint never depends on how a chart was unwrapped. The colour is the part's plating (rows of panels of varied length
with staggered seams, sized per part, M4-T30b), then the generator's markings (bands, stencilled text from a stroke font, decals,
soot) and seeded weathering (worn edges, streaks trailing aft from the seams, smudges and grime). The normal map carries the seams'
grooves, the hatch bevels and the rivet rows as a height field at twice the atlas's resolution, plus, for a coarse render mesh, the
fine mesh's own shape; occlusion is a disk-to-point estimate against surface samples of the whole hull.
"""

from __future__ import annotations

import math
import zlib
from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Any

import numpy as np

from .color import linear_to_srgb, srgb_to_linear
from .geometry import Material, Mesh, unit
from .raster import AtlasBuffers
from .sampling import sample_mesh
from .seams import SeamLayout
from ..styles import Style, _hash01

Vec3 = tuple[float, float, float]
OCCLUSION_STEP = 4  # texels between occlusion queries; the result is spread over the texels between
OCCLUSION_RADIUS_M = 0.7
OCCLUSION_SAMPLE_M = 0.12
GLASS_ALBEDO_LIFT = 1.0
NORMAL_SCALE = 2  # the normal map's resolution over the atlas's (Q34: the fine detail)
RIVET_PITCH_M = 0.075
RIVET_RADIUS_M = 0.0075
RIVET_HEIGHT_M = 0.0018
RIVET_OFFSET_M = 0.022  # from the edge of a seam's line
TRANSFER_RADIUS_M = 0.12  # how far the fine mesh's vertices reach a coarse texel
SEAM_TEXELS = 2.2  # a drawn seam's width in atlas texels: the thinnest line the mipmaps keep (M5-T40)
SEAM_DEPTH = 0.3  # its depth as a share of its width


def seam_size(texel_m: float) -> tuple[float, float]:
    """A drawn seam's width and depth in metres on a hull texelled at ``texel_m``."""
    line = SEAM_TEXELS * float(texel_m)
    return line, SEAM_DEPTH * line


# --- the stroke font --------------------------------------------------------------------------
# Glyphs on a 4 wide by 6 tall grid, each a tuple of polylines; the digits and the letters the markings use.
_GLYPHS: dict[str, tuple[tuple[tuple[float, float], ...], ...]] = {
    "0": (((0, 0), (4, 0), (4, 6), (0, 6), (0, 0)), ((0, 0), (4, 6))),
    "1": (((1, 5), (2.5, 6), (2.5, 0)), ((1, 0), (4, 0))),
    "2": (((0, 5), (1, 6), (3, 6), (4, 5), (4, 3.5), (0, 0.6), (0, 0), (4, 0)),),
    "3": (((0, 6), (4, 6), (1.8, 3.4), (3, 3.4), (4, 2.5), (4, 1), (3, 0), (1, 0), (0, 1)),),
    "4": (((3, 0), (3, 6), (0, 2), (4, 2)),),
    "5": (((4, 6), (0, 6), (0, 3.4), (3, 3.4), (4, 2.4), (4, 1), (3, 0), (0, 0)),),
    "6": (((4, 6), (1, 6), (0, 5), (0, 1), (1, 0), (3, 0), (4, 1), (4, 2.6), (3, 3.4), (0, 3.4)),),
    "7": (((0, 6), (4, 6), (1.5, 0)),),
    "8": (((1, 3.2), (0, 4.2), (0, 5), (1, 6), (3, 6), (4, 5), (4, 4.2), (3, 3.2), (1, 3.2), (0, 2.2), (0, 1), (1, 0), (3, 0), (4, 1), (4, 2.2), (3, 3.2)),),
    "9": (((0, 0), (3, 0), (4, 1), (4, 5), (3, 6), (1, 6), (0, 5), (0, 3.4), (1, 2.6), (4, 2.6)),),
    "A": (((0, 0), (2, 6), (4, 0)), ((0.8, 2.4), (3.2, 2.4))),
    "B": (((0, 0), (0, 6), (3, 6), (4, 5), (4, 4), (3, 3.2), (0, 3.2)), ((3, 3.2), (4, 2.2), (4, 1), (3, 0), (0, 0))),
    "C": (((4, 5), (3, 6), (1, 6), (0, 5), (0, 1), (1, 0), (3, 0), (4, 1)),),
    "D": (((0, 0), (0, 6), (2.6, 6), (4, 4.6), (4, 1.4), (2.6, 0), (0, 0)),),
    "E": (((4, 6), (0, 6), (0, 0), (4, 0)), ((0, 3.2), (3, 3.2))),
    "F": (((4, 6), (0, 6), (0, 0)), ((0, 3.2), (3, 3.2))),
    "G": (((4, 5), (3, 6), (1, 6), (0, 5), (0, 1), (1, 0), (3, 0), (4, 1), (4, 2.6), (2, 2.6)),),
    "H": (((0, 0), (0, 6)), ((4, 0), (4, 6)), ((0, 3.2), (4, 3.2))),
    "I": (((1, 6), (3, 6)), ((2, 6), (2, 0)), ((1, 0), (3, 0))),
    "J": (((1, 6), (4, 6)), ((3, 6), (3, 1), (2, 0), (1, 0), (0, 1)),),
    "K": (((0, 0), (0, 6)), ((4, 6), (0, 2.6)), ((1.4, 3.6), (4, 0))),
    "L": (((0, 6), (0, 0), (4, 0)),),
    "M": (((0, 0), (0, 6), (2, 2.8), (4, 6), (4, 0)),),
    "N": (((0, 0), (0, 6), (4, 0), (4, 6)),),
    "O": (((1, 0), (0, 1), (0, 5), (1, 6), (3, 6), (4, 5), (4, 1), (3, 0), (1, 0)),),
    "P": (((0, 0), (0, 6), (3, 6), (4, 5), (4, 3.8), (3, 2.8), (0, 2.8)),),
    "Q": (((1, 0), (0, 1), (0, 5), (1, 6), (3, 6), (4, 5), (4, 1), (3, 0), (1, 0)), ((2.4, 1.6), (4, 0))),
    "R": (((0, 0), (0, 6), (3, 6), (4, 5), (4, 3.8), (3, 2.8), (0, 2.8)), ((2, 2.8), (4, 0))),
    "S": (((4, 5), (3, 6), (1, 6), (0, 5), (0, 4), (1, 3.1), (3, 3.1), (4, 2.2), (4, 1), (3, 0), (1, 0), (0, 1)),),
    "T": (((0, 6), (4, 6)), ((2, 6), (2, 0))),
    "U": (((0, 6), (0, 1), (1, 0), (3, 0), (4, 1), (4, 6)),),
    "V": (((0, 6), (2, 0), (4, 6)),),
    "W": (((0, 6), (0.8, 0), (2, 3.6), (3.2, 0), (4, 6)),),
    "X": (((0, 0), (4, 6)), ((0, 6), (4, 0))),
    "Y": (((0, 6), (2, 3), (4, 6)), ((2, 3), (2, 0))),
    "Z": (((0, 6), (4, 6), (0, 0), (4, 0)),),
    "-": (((0.5, 3), (3.5, 3)),),
}
GLYPH_W, GLYPH_H, GLYPH_ADVANCE = 4.0, 6.0, 5.4


def glyph_strokes(ch: str) -> tuple[tuple[tuple[float, float], ...], ...]:
    """The polylines of one glyph on the 4 by 6 grid (empty for a space or an unknown character)."""
    return _GLYPHS.get(ch.upper(), ())


# --- markings ---------------------------------------------------------------------------------
@dataclass(frozen=True)
class Marking:
    """One thing painted onto a part in world space: a band round an axis, stencilled text or a flat decal on a facing
    side, or soot trailing from a nozzle. ``part`` names the part whose texels it may touch (``""``: any)."""

    kind: str
    part: str
    colour: Vec3 = (0.0, 0.0, 0.0)
    params: dict[str, Any] = field(default_factory=dict)

    @staticmethod
    def band(part: str, centre: Sequence[float], axis: Sequence[float], at_m: float, width_m: float, colour: Vec3) -> Marking:
        """A ring of ``colour`` round ``axis`` through ``centre``, ``width_m`` wide, centred ``at_m`` along the axis."""
        return Marking("band", part, colour, {"centre": tuple(centre), "axis": tuple(unit(np.asarray(axis, dtype=float))),
                                                "at_m": float(at_m), "width_m": float(width_m)})

    @staticmethod
    def text(part: str, text: str, centre: Sequence[float], right: Sequence[float], up: Sequence[float], facing: Sequence[float],
             height_m: float, colour: Vec3, stroke_m: float | None = None) -> Marking:
        """``text`` stencilled ``height_m`` tall, centred on ``centre``, read along ``right``, on the side facing ``facing``."""
        return Marking("text", part, colour, {"text": text, "centre": tuple(centre), "right": tuple(unit(np.asarray(right, dtype=float))),
                                                "up": tuple(unit(np.asarray(up, dtype=float))), "facing": tuple(unit(np.asarray(facing, dtype=float))),
                                                "height_m": float(height_m), "stroke_m": float(stroke_m) if stroke_m else 0.14 * float(height_m)})

    @staticmethod
    def rect(part: str, centre: Sequence[float], right: Sequence[float], up: Sequence[float], facing: Sequence[float],
             size_m: Sequence[float], colour: Vec3) -> Marking:
        """A flat ``size_m`` (along ``right``, along ``up``) decal of ``colour`` on the side facing ``facing``."""
        return Marking("rect", part, colour, {"centre": tuple(centre), "right": tuple(unit(np.asarray(right, dtype=float))),
                                                "up": tuple(unit(np.asarray(up, dtype=float))), "facing": tuple(unit(np.asarray(facing, dtype=float))),
                                                "size_m": (float(size_m[0]), float(size_m[1]))})

    @staticmethod
    def windows(part: str, centre: Sequence[float], right: Sequence[float], up: Sequence[float], facing: Sequence[float],
                size_m: Sequence[float], pitch_m: Sequence[float], window_m: Sequence[float], colour: Vec3, strength: float,
                lit: float = 0.75) -> Marking:
        """Rows of lit windows (M4-T30d) in a ``size_m`` region round ``centre`` on the side facing ``facing``: one window of
        ``window_m`` every ``pitch_m`` along ``right`` and ``up``, about ``lit`` of them glowing ``colour`` at ``strength``."""
        return Marking("windows", part, tuple(colour), {"mode": "plane", "centre": tuple(centre),
                                                        "right": tuple(unit(np.asarray(right, dtype=float))),
                                                        "up": tuple(unit(np.asarray(up, dtype=float))),
                                                        "facing": tuple(unit(np.asarray(facing, dtype=float))),
                                                        "size_m": (float(size_m[0]), float(size_m[1])),
                                                        "pitch_m": (float(pitch_m[0]), float(pitch_m[1])),
                                                        "window_m": (float(window_m[0]), float(window_m[1])),
                                                        "strength": float(strength), "lit": float(lit)})

    @staticmethod
    def window_rings(part: str, centre: Sequence[float], axis: Sequence[float], at_m: float, height_m: float, pitch_m: Sequence[float],
                     window_m: Sequence[float], colour: Vec3, strength: float, lit: float = 0.75) -> Marking:
        """Rows of lit windows (M4-T30d) all the way round ``axis`` through ``centre``, in a band ``height_m`` wide centred ``at_m``
        along it: one window of ``window_m`` every ``pitch_m`` (round the axis, along it), about ``lit`` of them glowing."""
        return Marking("windows", part, tuple(colour), {"mode": "ring", "centre": tuple(centre),
                                                        "axis": tuple(unit(np.asarray(axis, dtype=float))), "at_m": float(at_m),
                                                        "height_m": float(height_m),
                                                        "pitch_m": (float(pitch_m[0]), float(pitch_m[1])),
                                                        "window_m": (float(window_m[0]), float(window_m[1])),
                                                        "strength": float(strength), "lit": float(lit)})

    @staticmethod
    def soot(part: str, exit_point: Sequence[float], direction: Sequence[float], radius_m: float, length_m: float, strength: float = 1.0) -> Marking:
        """Soot behind a nozzle exit: a cone of darkening from ``exit_point`` along ``direction``."""
        return Marking("soot", part, (0.0, 0.0, 0.0), {"exit": tuple(exit_point), "direction": tuple(unit(np.asarray(direction, dtype=float))),
                                                         "radius_m": float(radius_m), "length_m": float(length_m), "strength": float(strength)})


def _stroke_distance(points: np.ndarray, strokes: Sequence[Sequence[tuple[float, float]]]) -> np.ndarray:
    """Distance from 2D ``points`` to the nearest stroke segment."""
    best = np.full(len(points), np.inf)
    for stroke in strokes:
        for (x0, y0), (x1, y1) in zip(stroke[:-1], stroke[1:], strict=True):
            a = np.array([x0, y0])
            ab = np.array([x1 - x0, y1 - y0])
            length2 = float(ab @ ab)
            if length2 < 1e-12:
                d = np.linalg.norm(points - a, axis=1)
            else:
                t = np.clip(((points - a) @ ab) / length2, 0.0, 1.0)
                d = np.linalg.norm(points - (a + t[:, None] * ab), axis=1)
            best = np.minimum(best, d)
    return best


def text_coverage(uv_m: np.ndarray, text: str, height_m: float, stroke_m: float) -> np.ndarray:
    """How much of each 2D point (metres, the text centred on the origin) the stencilled ``text`` covers, 0..1."""
    scale = height_m / GLYPH_H
    width = (len(text) * GLYPH_ADVANCE - (GLYPH_ADVANCE - GLYPH_W)) * scale
    best = np.full(len(uv_m), np.inf)
    for k, ch in enumerate(text):
        strokes = glyph_strokes(ch)
        if not strokes:
            continue
        origin = np.array([-0.5 * width + k * GLYPH_ADVANCE * scale, -0.5 * height_m])
        local = (uv_m - origin) / scale
        best = np.minimum(best, _stroke_distance(local, strokes) * scale)
    half = 0.5 * stroke_m
    return np.clip((half + 0.004 - best) / 0.008, 0.0, 1.0)


# --- the plating (M4-T30b, Q34 and Q37) ---------------------------------------------------------
@dataclass(frozen=True)
class Plating:
    """How a part is plated: rows of panels ``width_m`` wide running along world axis ``row_axis``, each panel about
    ``length_m`` long (varied by ``jitter``), each row's seams moved on by ``stagger`` of a panel; ``seed`` varies the rest."""

    length_m: float
    width_m: float
    stagger: float
    jitter: float
    row_axis: int
    seed: int


def plating_for(part_name: str, mesh: Mesh, style: Style) -> Plating:
    """A part's plating: sized and staggered from its name (mirror images share it), its rows along its longest side."""
    base = part_name.split("_")[0] or "part"
    h = zlib.crc32(base.encode("utf-8"))
    r = [((h >> shift) & 0xFF) / 255.0 for shift in (0, 8, 16, 24)]
    size = style.panel_size_m
    extent = np.ptp(mesh.vertices, axis=0) if mesh.vertex_count else np.ones(3)
    return Plating(round(size * (2.2 + 1.6 * r[0]), 4), round(size * (0.8 + 0.6 * r[1]), 4), round(0.2 + 0.25 * r[2], 4), 0.6,
                   int(np.argmax(extent)), int(h & 0xFFFF))


def _partition(x: np.ndarray, jitter: float, *keys: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Cut a line into pieces about one unit long, each cut moved by up to ``jitter`` / 2 (hashed on ``keys``): per point, its
    piece and the piece's left and right cut."""
    k0 = np.floor(x).astype(np.int64)

    def cut(k: np.ndarray) -> np.ndarray:
        return k + jitter * (_hash01(k, *keys) - 0.5)

    c_prev, c0, c1, c2 = cut(k0 - 1), cut(k0), cut(k0 + 1), cut(k0 + 2)
    before, after = x < c0, x >= c1
    left = np.where(before, c_prev, np.where(after, c1, c0))
    right = np.where(before, c0, np.where(after, c2, c1))
    piece = np.where(before, k0 - 1, np.where(after, k0 + 1, k0))
    return piece, left, right


def plating_lattice(style: Style, positions: np.ndarray, normals: np.ndarray, plating: Plating,
                    phase: Sequence[float] = (0.0, 0.0, 0.0), slope_normals: np.ndarray | None = None) -> dict[str, np.ndarray]:
    """Where each point falls in its part's plating: its panel (``cu`` along the row, ``cv`` the row, ``drop`` the projection),
    its place in the panel (``fu``, ``fv`` in 0..1, ``edge_m`` the distance to the nearest seam's centre line), the seam's line
    and the panel's tint, the hatch some panels carry, the distance to the nearest rivet (``rivet_m``), the panel's length, its
    row and left seam (``seam_u``), and how far aft of the panel's front edge it is (``aft_m``, where a row or a panel runs along z).
    Projected along the axis nearest the normal like the old grid, but measured on the surface, so a slope keeps its panel size:
    ``slope_normals`` (the chart's mean normal, say) sets that scale, so it stays constant across a curved chart."""
    p = np.asarray(positions, dtype=float) + np.asarray(phase, dtype=float)
    n = np.abs(np.asarray(normals, dtype=float))
    count = len(p)
    index = np.arange(count)
    drop = np.argmax(n, axis=1)
    axes = np.array([[1, 2], [0, 2], [0, 1]])[drop]
    along_second = axes[:, 1] == plating.row_axis
    ua = np.where(along_second, axes[:, 1], axes[:, 0])
    va = np.where(along_second, axes[:, 0], axes[:, 1])
    ns = n if slope_normals is None else np.abs(np.asarray(slope_normals, dtype=float))
    nd = np.maximum(ns[index, drop], 1e-6)
    su = np.clip(np.sqrt(1.0 + (ns[index, ua] / nd) ** 2), 1.0, 1.6)
    sv = np.clip(np.sqrt(1.0 + (ns[index, va] / nd) ** 2), 1.0, 1.6)
    um = p[index, ua] * su
    vm = p[index, va] * sv
    seed = np.full(count, plating.seed, dtype=np.int64)
    rv = vm / plating.width_m
    row, bottom, top = _partition(rv, 0.5, drop + 29, seed)  # rows of varied height
    fv = (rv - bottom) / (top - bottom)
    offset = plating.stagger * row + 0.37 * _hash01(row, drop, seed)
    uu = um / plating.length_m + offset
    cell, left, right = _partition(uu, plating.jitter, row, drop + 11, seed)
    fu = (uu - left) / (right - left)
    panel_length = (right - left) * plating.length_m
    du = np.minimum(uu - left, right - uu) * plating.length_m
    dv = np.minimum(rv - bottom, top - rv) * plating.width_m
    edge_m = np.minimum(du, dv)
    line = style.panel_line_width_m
    on_line = edge_m < 0.5 * line
    tint = 1.0 + style.panel_tint_jitter * (2.0 * _hash01(cell, row, drop, seed) - 1.0)
    has_hatch = _hash01(cell + 977, row - 331, drop + 7, seed) < style.hatch_fraction
    hx = (np.abs(fu - 0.5) - 0.3) * panel_length
    hy = (np.abs(fv - 0.5) - 0.22) * (top - bottom) * plating.width_m
    outside = np.hypot(np.maximum(hx, 0.0), np.maximum(hy, 0.0)) + np.minimum(np.maximum(hx, hy), 0.0)
    hatch = has_hatch & (outside < 0.0)
    # Rivets in a row beside every seam: along the row seams at a pitch along u, along the panel ends at a pitch along v.
    k = wear_scale(style)
    pitch = RIVET_PITCH_M * k
    off = 0.5 * line + RIVET_OFFSET_M * k
    along_u = (np.mod(um / pitch, 1.0) - 0.5) * pitch
    along_v = (np.mod(vm / pitch, 1.0) - 0.5) * pitch
    rivet_m = np.minimum(np.hypot(dv - off, along_u), np.hypot(du - off, along_v))
    rivet_m = np.where(edge_m > 0.5 * line + RIVET_RADIUS_M * k, rivet_m, np.inf)  # none in a seam's groove, where two seams cross
    is_z_u, is_z_v = ua == 2, va == 2
    aft_m = np.where(is_z_u, (uu - left) * plating.length_m, np.where(is_z_v, (rv - bottom) * plating.width_m, np.inf))
    return {
        "drop": drop, "cu": cell, "cv": row, "row": row, "fu": fu, "fv": fv, "edge_m": edge_m, "on_line": on_line, "tint": tint,
        "hatch": hatch, "hatch_edge_m": np.where(has_hatch, np.abs(outside), np.inf), "rivet_m": rivet_m,
        "panel_length_m": panel_length, "seam_u": (left - offset) * plating.length_m, "aft_m": aft_m, "has_aft": is_z_u | is_z_v,
    }


def wear_scale(style: Style) -> float:
    """How much bigger than a fighter's the style's fine detail is (M4-T30d): rivets, noise and edge softness are sized for a fighter
    texelled at a centimetre, so a capital or a station scales them up (``Style.extra["wear_scale"]``, 1 for fighters)."""
    return float(style.extra.get("wear_scale", 1.0))


def _surface_height(style: Style, lattice: dict[str, np.ndarray]) -> np.ndarray:
    """The plating's relief: the seams' grooves, the hatches' bevels and the rivets' domes (metres, 0 the plate)."""
    k = wear_scale(style)
    line = style.panel_line_width_m
    groove = 1.0 - np.clip((lattice["edge_m"] - 0.5 * line) / (0.5 * line) + 1.0, 0.0, 1.0)
    h = -style.groove_depth_m * groove * groove * (3.0 - 2.0 * groove)
    bevel = np.clip(lattice["hatch_edge_m"] / (0.03 * k), 0.0, 1.0)
    h -= np.where(lattice["hatch"], style.hatch_depth_m * bevel, 0.0)
    dome = np.clip(1.0 - (lattice["rivet_m"] / (RIVET_RADIUS_M * k)) ** 2, 0.0, 1.0)
    return h + RIVET_HEIGHT_M * k * float(style.extra.get("rivets", 1.0)) * np.sqrt(dome)


# --- noise ------------------------------------------------------------------------------------
def value_noise(points: np.ndarray, scale_m: float, seed: int) -> np.ndarray:
    """Smooth seeded noise in [0, 1) over world ``points``: trilinear between hashed lattice corners ``scale_m`` apart."""
    p = np.asarray(points, dtype=float) / scale_m + 0.37 * (seed % 1000)
    c = np.floor(p).astype(np.int64)
    f = p - c
    f = f * f * (3.0 - 2.0 * f)
    out = np.zeros(len(p))
    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                h = _hash01(c[:, 0] + dx, c[:, 1] + dy, c[:, 2] + dz, np.full(len(p), seed, dtype=np.int64))
                w = (f[:, 0] if dx else 1.0 - f[:, 0]) * (f[:, 1] if dy else 1.0 - f[:, 1]) * (f[:, 2] if dz else 1.0 - f[:, 2])
                out += w * h
    return out


# --- the atlas and the maps -------------------------------------------------------------------
@dataclass
class Atlas:
    """What the maps are baked from: the packed buffers, the material table and each part's name, phase and markings."""

    buffers: AtlasBuffers
    materials: tuple[Material, ...]
    part_names: tuple[str, ...]
    part_phases: tuple[tuple[float, float, float], ...]
    markings: tuple[Marking, ...]
    texel_m: float
    hull_mesh: Mesh
    part_platings: tuple[Plating, ...] = ()
    fine_mesh: Mesh | None = None  # the full-detail mesh whose shape a coarse render mesh's normal map carries (render_triangles)
    part_seams: tuple[SeamLayout, ...] = ()  # each part's drawn surface layout (M5-T40); empty: none
    grid: bool = True  # the generic staggered plating; a hull with drawn layouts turns it off


def srgb_to_linear8(rgb8: np.ndarray) -> np.ndarray:
    return srgb_to_linear(np.asarray(rgb8, dtype=float) / 255.0)


def decode_normal(rgb8: np.ndarray) -> np.ndarray:
    """A normal map's texels back to unit vectors (tangent space, Godot's +Y up)."""
    n = np.asarray(rgb8, dtype=float) / 255.0 * 2.0 - 1.0
    return unit(n)


def _to8(values: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(np.asarray(values) * 255.0), 0, 255).astype(np.uint8)


def _texel_metric(filled: np.ndarray, pos: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Per texel: the world step along +u and +v (metres per texel), finite differences inside the filled region."""

    def step(axis: int) -> np.ndarray:
        forward = np.roll(pos, -1, axis=axis) - pos
        backward = pos - np.roll(pos, 1, axis=axis)
        has_forward = np.roll(filled, -1, axis=axis) & filled
        has_backward = np.roll(filled, 1, axis=axis) & filled
        out = np.where(has_forward[..., None], forward, np.where(has_backward[..., None], backward, 0.0))
        both = has_forward & has_backward
        out = np.where(both[..., None], 0.5 * (forward + backward), out)
        return out

    du = step(1)  # along u: columns
    dv = step(0)  # along v: rows
    return du, dv, np.linalg.norm(du, axis=-1), np.linalg.norm(dv, axis=-1)


def _gradient(height: np.ndarray, filled: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """d height / d texel along u (columns) and v (rows), one-sided at the region's border."""

    def along(axis: int) -> np.ndarray:
        forward = np.roll(height, -1, axis=axis) - height
        backward = height - np.roll(height, 1, axis=axis)
        has_forward = np.roll(filled, -1, axis=axis) & filled
        has_backward = np.roll(filled, 1, axis=axis) & filled
        out = np.where(has_forward, forward, np.where(has_backward, backward, 0.0))
        return np.where(has_forward & has_backward, 0.5 * (forward + backward), out)

    return along(1), along(0)


def _occlusion(atlas: Atlas, seed: int) -> np.ndarray:
    """Disk-to-point occlusion from surface samples of the whole hull, at every ``OCCLUSION_STEP`` texels, spread between."""
    buffers = atlas.buffers
    size = buffers.size
    rng = np.random.default_rng([seed, 0x0CC1])
    samples = sample_mesh(atlas.hull_mesh, OCCLUSION_SAMPLE_M, rng)
    if len(samples) == 0:
        return np.ones((size, size))
    s_pos, s_nrm = samples.positions, samples.normals
    area = OCCLUSION_SAMPLE_M * OCCLUSION_SAMPLE_M
    cell = OCCLUSION_RADIUS_M
    s_cell = np.floor(s_pos / cell).astype(np.int64)
    span = s_cell.max(axis=0) - s_cell.min(axis=0) + 3
    base = s_cell.min(axis=0) - 1

    def key_of(cells: np.ndarray) -> np.ndarray:
        c = cells - base
        return (c[:, 0] * span[1] + c[:, 1]) * span[2] + c[:, 2]

    s_key = key_of(s_cell)
    order = np.argsort(s_key, kind="stable")
    s_key, s_pos, s_nrm = s_key[order], s_pos[order], s_nrm[order]
    coarse = np.ones((size // OCCLUSION_STEP, size // OCCLUSION_STEP))
    rows, cols = np.nonzero(buffers.filled[::OCCLUSION_STEP, ::OCCLUSION_STEP])
    q_pos = buffers.position[rows * OCCLUSION_STEP, cols * OCCLUSION_STEP]
    q_nrm = buffers.normal[rows * OCCLUSION_STEP, cols * OCCLUSION_STEP]
    total = np.zeros(len(q_pos))
    offsets = np.array([[dx, dy, dz] for dx in (-1, 0, 1) for dy in (-1, 0, 1) for dz in (-1, 0, 1)])
    chunk = 20000
    for start in range(0, len(q_pos), chunk):
        qp, qn = q_pos[start : start + chunk], q_nrm[start : start + chunk]
        q_cell = np.floor(qp / cell).astype(np.int64)
        acc = np.zeros(len(qp))
        for offset in offsets:
            keys = key_of(q_cell + offset)
            lo = np.searchsorted(s_key, keys, side="left")
            hi = np.searchsorted(s_key, keys, side="right")
            counts = hi - lo
            if not counts.any():
                continue
            q_index = np.repeat(np.arange(len(qp)), counts)
            s_index = np.concatenate([np.arange(a, b) for a, b in zip(lo, hi, strict=True) if b > a])
            d = s_pos[s_index] - qp[q_index]
            dist2 = np.einsum("ij,ij->i", d, d)
            near = (dist2 > 1e-4) & (dist2 < cell * cell)
            d, dist2, q_index, s_index = d[near], dist2[near], q_index[near], s_index[near]
            dist = np.sqrt(dist2)
            d_hat = d / dist[:, None]
            cos_r = np.clip(np.einsum("ij,ij->i", qn[q_index], d_hat), 0.0, 1.0)
            cos_e = np.clip(-np.einsum("ij,ij->i", s_nrm[s_index], d_hat), 0.0, 1.0)
            form = area * cos_r * cos_e / (math.pi * dist2 + area)
            np.add.at(acc, q_index, form)
        total[start : start + chunk] = acc
    coarse[rows, cols] = np.clip(1.0 - 1.6 * total, 0.0, 1.0)
    full = np.repeat(np.repeat(coarse, OCCLUSION_STEP, axis=0), OCCLUSION_STEP, axis=1)
    # Soften the blocks: a box blur that only averages over filled texels.
    weight = buffers.filled.astype(float)
    blurred = np.zeros_like(full)
    norm = np.zeros_like(full)
    for dy in range(-OCCLUSION_STEP // 2, OCCLUSION_STEP // 2 + 1):
        for dx in range(-OCCLUSION_STEP // 2, OCCLUSION_STEP // 2 + 1):
            blurred += np.roll(full * weight, (dy, dx), axis=(0, 1))
            norm += np.roll(weight, (dy, dx), axis=(0, 1))
    return np.where(norm > 0.0, blurred / np.maximum(norm, 1e-9), 1.0)


def _fine_normals(atlas: Atlas, du: np.ndarray, dv: np.ndarray) -> np.ndarray | None:
    """For a coarse render mesh: the fine mesh's smooth normal near each texel, in the texel's tangent frame (u right, -v up),
    so the normal map carries the shape the coarse mesh lost; None when the atlas has no fine mesh."""
    fine = atlas.fine_mesh
    if fine is None or fine.vertex_count == 0:
        return None
    b = atlas.buffers
    size = b.size
    out = np.zeros((size, size, 3))
    out[..., 2] = 1.0
    rows, cols = np.nonzero(b.filled)
    q_pos, q_nrm = b.position[rows, cols], unit(b.normal[rows, cols])
    v_pos, v_nrm = fine.vertices, unit(fine.vertex_normals())
    cell = TRANSFER_RADIUS_M
    v_cell = np.floor(v_pos / cell).astype(np.int64)
    base = np.minimum(v_cell.min(axis=0), np.floor(q_pos.min(axis=0) / cell).astype(np.int64)) - 1
    span = np.maximum(v_cell.max(axis=0), np.floor(q_pos.max(axis=0) / cell).astype(np.int64)) - base + 2

    def key_of(cells: np.ndarray) -> np.ndarray:
        c = cells - base
        return (c[:, 0] * span[1] + c[:, 1]) * span[2] + c[:, 2]

    v_key = key_of(v_cell)
    order = np.argsort(v_key, kind="stable")
    v_key, v_pos, v_nrm = v_key[order], v_pos[order], v_nrm[order]
    offsets = np.array([[dx, dy, dz] for dx in (-1, 0, 1) for dy in (-1, 0, 1) for dz in (-1, 0, 1)])
    total = np.zeros((len(q_pos), 3))
    weight = np.zeros(len(q_pos))
    chunk = 40000
    for start in range(0, len(q_pos), chunk):
        qp, qn = q_pos[start : start + chunk], q_nrm[start : start + chunk]
        q_cell = np.floor(qp / cell).astype(np.int64)
        acc, acc_w = np.zeros((len(qp), 3)), np.zeros(len(qp))
        for offset in offsets:
            keys = key_of(q_cell + offset)
            lo = np.searchsorted(v_key, keys, side="left")
            hi = np.searchsorted(v_key, keys, side="right")
            counts = hi - lo
            if not counts.any():
                continue
            q_index = np.repeat(np.arange(len(qp)), counts)
            v_index = np.concatenate([np.arange(a, c) for a, c in zip(lo, hi, strict=True) if c > a])
            d2 = np.einsum("ij,ij->i", v_pos[v_index] - qp[q_index], v_pos[v_index] - qp[q_index])
            agree = np.einsum("ij,ij->i", v_nrm[v_index], qn[q_index])
            keep = (d2 < cell * cell) & (agree > 0.3)  # the same side of a thin plate
            w = 1.0 / (d2[keep] + 1e-4)
            np.add.at(acc, q_index[keep], v_nrm[v_index[keep]] * w[:, None])
            np.add.at(acc_w, q_index[keep], w)
        total[start : start + chunk] = acc
        weight[start : start + chunk] = acc_w
    found = weight > 0.0
    f = np.where(found[:, None], unit(total), q_nrm)
    tangent = du[rows, cols]
    bitangent = -dv[rows, cols]
    tangent = unit(tangent - np.einsum("ij,ij->i", tangent, q_nrm)[:, None] * q_nrm)
    bitangent = unit(bitangent - np.einsum("ij,ij->i", bitangent, q_nrm)[:, None] * q_nrm)
    ts = np.stack([np.einsum("ij,ij->i", f, tangent), np.einsum("ij,ij->i", f, bitangent), np.einsum("ij,ij->i", f, q_nrm)], axis=1)
    ts[:, 2] = np.maximum(ts[:, 2], 0.05)
    out[rows, cols] = unit(ts)
    return out


def _chart_normals(buffers: AtlasBuffers) -> np.ndarray:
    """Each chart's mean normal, by chart id (the last row for texels of no chart): the plating's slope scale per chart."""
    charts = int(buffers.chart.max()) + 2 if buffers.filled.any() else 1
    ids = np.where(buffers.filled, buffers.chart, -1)
    total = np.zeros((charts, 3))
    np.add.at(total, ids[buffers.filled], buffers.normal[buffers.filled])
    out = unit(total)
    out[-1] = (0.0, 0.0, 1.0)
    return out


def _normal_map(atlas: Atlas, style: Style, platings: Sequence[Plating], scale: int = NORMAL_SCALE) -> np.ndarray:
    """The tangent-space normal map at ``scale`` times the atlas: the plating's relief (grooves, hatches, rivets) from a
    height field sampled at the finer texels, over the fine mesh's shape for a coarse render mesh."""
    b = atlas.buffers
    size = b.size
    big = size * scale
    du, dv, step_u, step_v = _texel_metric(b.filled, b.position)
    paneled_table = np.array([m.paneled for m in atlas.materials], dtype=bool)
    chart_normal = _chart_normals(b)
    # Where each fine texel falls in the atlas: its nearest atlas texel, and a bilinear position inside one chart.
    src = (np.arange(big) + 0.5) / scale - 0.5
    near = np.clip(np.rint(src).astype(np.int64), 0, size - 1)
    lo = np.clip(np.floor(src).astype(np.int64), 0, size - 1)
    hi = np.clip(lo + 1, 0, size - 1)
    t = np.clip(src - lo, 0.0, 1.0)
    height = np.zeros((big, big))
    filled_big = b.filled[np.ix_(near, near)]
    strip = 256
    for r0 in range(0, big, strip):
        rr = np.arange(r0, min(r0 + strip, big))
        rn, rl, rh, rt = near[rr], lo[rr], hi[rr], t[rr]
        f_near = b.filled[np.ix_(rn, near)]
        if not f_near.any():
            continue
        chart = b.chart[np.ix_(rn, near)]
        same = np.ones_like(f_near)
        corners = []
        for rows_, cols_ in ((rl, lo), (rl, hi), (rh, lo), (rh, hi)):
            same &= b.filled[np.ix_(rows_, cols_)] & (b.chart[np.ix_(rows_, cols_)] == chart)
            corners.append(b.position[np.ix_(rows_, cols_)])
        wr, wc = rt[:, None, None], t[None, :, None]
        bilinear = (corners[0] * (1 - wr) * (1 - wc) + corners[1] * (1 - wr) * wc + corners[2] * wr * (1 - wc) + corners[3] * wr * wc)
        position = np.where(same[..., None], bilinear, b.position[np.ix_(rn, near)])
        normal = b.normal[np.ix_(rn, near)]
        part = b.part[np.ix_(rn, near)]
        material = b.material[np.ix_(rn, near)]
        strip_h = np.zeros(f_near.shape)
        for p_index, phase in enumerate(atlas.part_phases if atlas.grid else ()):
            sel = f_near & (part == p_index)
            if not sel.any():
                continue
            lattice = plating_lattice(style, position[sel], normal[sel], platings[p_index], phase, chart_normal[chart[sel]])
            strip_h[sel] = np.where(paneled_table[material[sel]], _surface_height(style, lattice), 0.0)
        for p_index, layout in enumerate(atlas.part_seams):
            sel = f_near & (part == p_index)
            if not layout or not sel.any():
                continue
            drawn = layout.evaluate(position[sel], normal[sel], *seam_size(atlas.texel_m))
            strip_h[sel] += np.where(paneled_table[material[sel]], drawn.height, 0.0)
        height[rr] = strip_h
    hu, hv = _gradient(height, filled_big)
    su = np.maximum(step_u[np.ix_(near, near)] / scale, 1e-6)
    sv = np.maximum(step_v[np.ix_(near, near)] / scale, 1e-6)
    relief = unit(np.stack([-hu / su, hv / sv, np.ones((big, big))], axis=-1))
    fine = _fine_normals(atlas, du, dv)
    if fine is not None:
        shape = fine[np.ix_(near, near)]
        relief = unit(np.stack([relief[..., 0] + shape[..., 0], relief[..., 1] + shape[..., 1], relief[..., 2] * shape[..., 2]], axis=-1))
    relief[~filled_big] = (0.0, 0.0, 1.0)
    return relief


def bake_maps(atlas: Atlas, style: Style, seed: int, occlusion: bool = True, paintable: Sequence[str] = (),
              normal_scale: int = NORMAL_SCALE) -> dict[str, np.ndarray]:
    """The four maps as 8-bit RGB arrays: ``albedo`` (sRGB), ``normal`` (tangent space, +Y up, ``normal_scale`` times the atlas),
    ``orm`` and ``emissive`` (sRGB). With ``paintable`` material names the albedo is RGBA, its alpha where a livery may paint (M4-T30b):
    those materials, less the chipped edges and the markings."""
    b = atlas.buffers
    size = b.size
    filled = b.filled
    idx = np.nonzero(filled)
    pos, nrm = b.position[idx], b.normal[idx]
    mat = b.material[idx]
    part = b.part[idx]
    n = len(mat)
    table = atlas.materials
    albedo = np.array([m.albedo for m in table], dtype=float)[mat]
    paneled = np.array([m.paneled for m in table], dtype=bool)[mat]
    metallic = np.array([m.metallic for m in table], dtype=float)[mat]
    roughness = np.array([m.roughness_value for m in table], dtype=float)[mat]
    transmittance = np.array([m.transmittance for m in table], dtype=float)[mat]
    emissive = np.array([m.emissive for m in table], dtype=float)[mat]
    strength = np.array([m.emissive_strength for m in table], dtype=float)[mat]
    glass = transmittance > 0.0

    # The paint: each part's plating (panel lines and tint) with the part's own phase.
    on_line = np.zeros(n, dtype=bool)
    lattice_aft = np.full(n, np.inf)
    lattice_cell = np.zeros((n, 3), dtype=np.int64)
    platings = atlas.part_platings or (tuple(plating_for(name, atlas.hull_mesh, style) for name in atlas.part_names) if atlas.grid else ())
    chart_normal = _chart_normals(b)
    for p_index, phase in enumerate(atlas.part_phases if atlas.grid else ()):
        sel = part == p_index
        if not sel.any():
            continue
        lattice = plating_lattice(style, pos[sel], nrm[sel], platings[p_index], phase, chart_normal[b.chart[idx][sel]])
        painted = paneled[sel]
        factor = np.where(lattice["on_line"], style.panel_line_darkness, lattice["tint"])
        factor = np.where(lattice["hatch"], factor * 0.93, factor)
        albedo[sel] *= np.where(painted, factor, 1.0)[:, None]
        on_line[sel] = lattice["on_line"] & painted
        lattice_aft[sel] = np.where(painted, lattice["aft_m"], np.inf)
        lattice_cell[sel] = np.stack([lattice["cu"], lattice["cv"], lattice["drop"]], axis=1)

    # The drawn layouts (M5-T40): seam lines, and each plate's tone and sheen.
    plate_rough = np.zeros(n)
    for p_index, layout in enumerate(atlas.part_seams):
        sel = part == p_index
        if not layout or not sel.any():
            continue
        drawn = layout.evaluate(pos[sel], nrm[sel], *seam_size(atlas.texel_m))
        painted = paneled[sel]
        factor = drawn.tint * (1.0 - (1.0 - style.panel_line_darkness) * drawn.line)
        albedo[sel] *= np.where(painted, factor, 1.0)[:, None]
        on_line[sel] |= painted & (drawn.line > 0.5)
        plate_rough[sel] = np.where(painted, drawn.rough, 0.0)

    # Weathering, seeded: worn sharp edges, streaks trailing aft from the seams, smudges and grime over the paint (Q37: no bare metal
    # unless the style asks for it).
    extra = dict(style.extra)
    bare_metal = float(extra.get("bare_metal", 1.0))
    seeds = np.full(n, seed, dtype=np.int64)
    k = wear_scale(style)
    soft = 0.01 * k  # a marking's edge, a texel or so wide
    noise_fine = value_noise(pos, 0.11 * k, seed + 1)
    noise_coarse = value_noise(pos, style.grime_scale_m, seed + 2)
    edge = np.clip(1.0 - b.edge_distance[idx] / style.edge_wear_width_m, 0.0, 1.0)
    chips = np.clip((edge * (0.35 + noise_fine) - (1.0 - style.edge_wear)) * 3.0, 0.0, 1.0) * ~glass
    streak_seed = _hash01(lattice_cell[:, 0], lattice_cell[:, 1], lattice_cell[:, 2] + 17, seeds)
    streak_on = np.clip((streak_seed - 0.45) / 0.55, 0.0, 1.0)
    across = _hash01(lattice_cell[:, 0], lattice_cell[:, 1], np.floor(noise_fine * 7.0).astype(np.int64), seeds + 3)
    fade = np.exp(-np.where(np.isfinite(lattice_aft), lattice_aft, 1e3) / (float(extra.get("streak_length_m", 0.2)) * k))
    streak = style.streaks * streak_on * fade * (across > 0.45) * paneled
    smudge_noise = value_noise(pos * np.array([1.0, 1.0, 0.35]), float(extra.get("smudge_scale_m", 0.45)) * k, seed + 5)  # long fore and aft
    smudge = float(extra.get("smudge", 0.0)) * np.clip((smudge_noise - 0.55) / 0.25, 0.0, 1.0) ** 1.5 * paneled
    speckle = float(extra.get("speckle", 0.0)) * (2.0 * value_noise(pos, 0.035 * k, seed + 6) - 1.0) * paneled
    grime = 1.0 + style.grime * (2.0 * noise_coarse - 1.0) + speckle
    albedo *= (grime * (1.0 - streak) * (1.0 - smudge))[:, None]
    if bare_metal > 0.0:
        bare = np.array([0.42, 0.42, 0.44])
        worn = chips * bare_metal
        albedo = albedo * (1.0 - worn)[:, None] + bare * worn[:, None]
        roughness = roughness - 0.25 * worn
        metallic = metallic * (1.0 - worn) + 0.85 * worn
    else:
        albedo *= (1.0 - 0.3 * chips)[:, None]  # worn edges show dark primer, not metal
    paint_roughness = extra.get("paint_roughness")
    if paint_roughness is not None:
        matte = paneled & (metallic < 0.3) & ~glass
        roughness = np.where(matte, float(paint_roughness), roughness)
    roughness = roughness + 0.25 * on_line + 0.1 * smudge + plate_rough

    # The markings, in world space, on their parts; what they cover is kept from the livery's paint.
    names = list(atlas.part_names)
    marked = np.zeros(n)
    window_glow = np.zeros((n, 3))
    window_strength = np.zeros(n)
    for marking in atlas.markings:
        sel = np.ones(n, dtype=bool) if not marking.part else part == names.index(marking.part)
        sel &= ~glass
        if not sel.any():
            continue
        p = pos[sel]
        colour = np.asarray(marking.colour, dtype=float)
        cover = np.zeros(int(sel.sum()))
        q = marking.params
        if marking.kind == "band":
            axis = np.asarray(q["axis"])
            along = (p - np.asarray(q["centre"])) @ axis
            cover = np.clip((0.5 * q["width_m"] - np.abs(along - q["at_m"])) / soft + 0.5, 0.0, 1.0)
        elif marking.kind in ("text", "rect"):
            facing = np.asarray(q["facing"])
            face = np.clip((nrm[sel] @ facing - 0.3) / 0.2, 0.0, 1.0)
            d = p - np.asarray(q["centre"])
            uv = np.stack([d @ np.asarray(q["right"]), d @ np.asarray(q["up"])], axis=1)
            if marking.kind == "text":
                cover = text_coverage(uv, q["text"], q["height_m"], q["stroke_m"]) * face
            else:
                half = 0.5 * np.asarray(q["size_m"])
                inside = np.clip((half - np.abs(uv)) / soft + 0.5, 0.0, 1.0)
                cover = inside[:, 0] * inside[:, 1] * face
        elif marking.kind == "windows":
            cover, glow = _window_cover(q, p, nrm[sel], max(atlas.texel_m, soft), seed)
            rows = np.flatnonzero(sel)
            window_glow[rows] = np.maximum(window_glow[rows], glow[:, None] * colour)
            window_strength[rows] = np.where(glow > 0.0, q["strength"], window_strength[rows])
            colour = np.array([0.018, 0.02, 0.024])  # dark glass where a window is unlit, and round the glow where it is
            roughness[sel] = roughness[sel] * (1.0 - cover) + 0.15 * cover
        elif marking.kind == "soot":
            direction = np.asarray(q["direction"])
            d = p - np.asarray(q["exit"])
            along = d @ direction
            radial = np.linalg.norm(d - along[:, None] * direction, axis=1)
            spread = q["radius_m"] * (1.0 + 1.5 * along / q["length_m"])
            cone = np.exp(-((radial / np.maximum(spread, 1e-6)) ** 2)) * np.exp(-np.maximum(along, 0.0) / q["length_m"])
            cover = np.where(along > -0.15, cone, 0.0) * q["strength"] * style.soot * (0.7 + 0.3 * noise_fine[sel])
            colour = np.array([0.012, 0.011, 0.01])
            roughness[sel] += 0.3 * cover
        albedo[sel] = albedo[sel] * (1.0 - cover)[:, None] + colour * cover[:, None]
        if marking.kind != "soot":
            metallic[sel] *= 1.0 - 0.6 * cover
            marked[np.flatnonzero(sel)] = np.maximum(marked[np.flatnonzero(sel)], cover)

    # The normal map: the plating's relief at twice the atlas's resolution, Godot's +Y up (Q34).
    normal_ts = _normal_map(atlas, style, platings, normal_scale)

    # Occlusion, roughness and metal; emissive scaled per surface so one map serves both.
    occ = _occlusion(atlas, seed) if occlusion else np.ones((size, size))
    orm = np.zeros((size, size, 3))
    orm[..., 0] = np.where(filled, occ, 1.0)
    orm_rough = np.full((size, size), 0.7)
    orm_rough[idx] = np.clip(roughness, 0.02, 1.0)
    orm[..., 1] = orm_rough
    orm_metal = np.zeros((size, size))
    orm_metal[idx] = np.clip(metallic, 0.0, 1.0)
    orm[..., 2] = orm_metal
    surface_strength = np.where(glass, surface_emissive_strength(table, True), surface_emissive_strength(table, False, atlas.markings))
    scale = np.where(surface_strength > 0.0, strength / np.maximum(surface_strength, 1e-9), 0.0)
    window_scale = np.where(surface_strength > 0.0, window_strength / np.maximum(surface_strength, 1e-9), 0.0)
    glow = np.clip(np.maximum(emissive * scale[:, None], window_glow * window_scale[:, None]), 0.0, 1.0)
    emissive_map = np.zeros((size, size, 3))
    emissive_map[idx] = glow

    albedo_map = np.zeros((size, size, 3))
    albedo_map[idx] = np.clip(albedo, 0.0, 1.0)
    mean = albedo[~glass].mean(axis=0) if (~glass).any() else albedo.mean(axis=0)
    albedo_map[~filled] = np.clip(mean, 0.0, 1.0)
    albedo8 = _to8(linear_to_srgb(albedo_map))
    if paintable:
        may_paint = np.isin(np.array([m.name for m in table])[mat], list(paintable)) & ~glass
        paint = np.zeros((size, size))
        paint[idx] = np.where(may_paint, np.clip(1.0 - chips - marked, 0.0, 1.0), 0.0)
        albedo8 = np.concatenate([albedo8, _to8(paint)[..., None]], axis=-1)
    return {
        "albedo": albedo8,
        "normal": _to8(normal_ts * 0.5 + 0.5),
        "orm": _to8(orm),
        "emissive": _to8(linear_to_srgb(emissive_map)),
        "mean_albedo": mean,
    }


def surface_emissive_strength(materials: Sequence[Material], glass: bool, markings: Sequence[Marking] = ()) -> float:
    """The emission energy of one surface: the strongest glow among its materials and, on the opaque surface, its window rows (the map
    holds each glow's share of it)."""
    strengths = [m.emissive_strength for m in materials if (m.transmittance > 0.0) == glass]
    if not glass:
        strengths += [float(m.params["strength"]) for m in markings if m.kind == "windows"]
    return max(strengths) if strengths else 0.0


def _window_cover(q: dict[str, Any], p: np.ndarray, normals: np.ndarray, soft: float, seed: int) -> tuple[np.ndarray, np.ndarray]:
    """Where a window-rows marking paints glass (``cover``, 0..1) and where that glass glows (``glow``, 0..1), per point."""
    d = p - np.asarray(q["centre"], dtype=float)
    if q["mode"] == "ring":
        axis = np.asarray(q["axis"], dtype=float)
        along = d @ axis
        radial = d - along[:, None] * axis
        radius = np.linalg.norm(radial, axis=1)
        e1 = unit(np.cross(axis, (1.0, 0.0, 0.0) if abs(axis[0]) < 0.9 else (0.0, 1.0, 0.0)))
        e2 = np.cross(axis, e1)
        a = np.arctan2(radial @ e2, radial @ e1) * radius
        b = along - q["at_m"]
        face = np.clip((np.einsum("ij,ij->i", normals, radial / np.maximum(radius, 1e-9)[:, None]) - 0.4) / 0.2, 0.0, 1.0)
        region = np.clip((0.5 * q["height_m"] - np.abs(b)) / soft + 0.5, 0.0, 1.0)
    else:
        a = d @ np.asarray(q["right"], dtype=float)
        b = d @ np.asarray(q["up"], dtype=float)
        face = np.clip((normals @ np.asarray(q["facing"], dtype=float) - 0.5) / 0.2, 0.0, 1.0)
        half = 0.5 * np.asarray(q["size_m"], dtype=float)
        region = np.clip((half[0] - np.abs(a)) / soft + 0.5, 0.0, 1.0) * np.clip((half[1] - np.abs(b)) / soft + 0.5, 0.0, 1.0)
    pitch = np.asarray(q["pitch_m"], dtype=float)
    window = np.asarray(q["window_m"], dtype=float)
    i, j = np.floor(a / pitch[0]), np.floor(b / pitch[1])
    fa, fb = a - (i + 0.5) * pitch[0], b - (j + 0.5) * pitch[1]
    inside = np.clip((0.5 * window[0] - np.abs(fa)) / soft + 0.5, 0.0, 1.0) * np.clip((0.5 * window[1] - np.abs(fb)) / soft + 0.5, 0.0, 1.0)
    cover = inside * face * region
    seeds = np.full(len(p), seed, dtype=np.int64)
    lit = _hash01(i.astype(np.int64), j.astype(np.int64), seeds + 71) < q["lit"]
    return cover, cover * lit


__all__ = ["Atlas", "Marking", "NORMAL_SCALE", "wear_scale", "Plating", "bake_maps", "decode_normal", "glyph_strokes", "plating_for", "plating_lattice",
           "srgb_to_linear8", "surface_emissive_strength", "text_coverage", "value_noise"]
