"""The texture maps of a hull (M4-T30a): colour, normal, occlusion/roughness/metal and emissive, baked from the atlas buffers.

Every map is a function of what ``core/raster.py`` knows per texel (world position, normal, part, material, distance to a sharp
edge), so the paint never depends on how a chart was unwrapped. The colour is the part's plating (rows of panels of varied length
with staggered seams, sized per part, M4-T30b), then the generator's markings (bands, stencilled text from a stroke font, decals,
soot) and seeded weathering (worn edges, streaks trailing aft from the seams, smudges and grime). The normal map carries the seams'
grooves, the hatch bevels and the rivet rows as a height field at twice the atlas's resolution, plus, for a coarse render mesh, the
fine mesh's own shape; occlusion is a disk-to-point estimate against surface samples of the whole hull.
"""

from __future__ import annotations

import dataclasses
import math
import weakref
import zlib
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from typing import Any

import numpy as np

from . import hull_decals
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
FLOOD_GREY = 0.35  # the plating's albedo (linear) a flood's pool shows at its full colour


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
    def emblem(part: str, centre: Sequence[float], right: Sequence[float], up: Sequence[float], facing: Sequence[float], height_m: float,
               colour: Vec3, trim: Vec3, depth_m: float = 2.0) -> Marking:
        """The Earth Alliance emblem (``core/hull_decals.py``) ``height_m`` tall, its body ``colour`` and its border and bars ``trim``,
        on the side facing ``facing`` within ``depth_m`` of the face through ``centre``."""
        return Marking("emblem", part, tuple(colour), {"centre": tuple(centre), "right": tuple(unit(np.asarray(right, dtype=float))),
                                                       "up": tuple(unit(np.asarray(up, dtype=float))),
                                                       "facing": tuple(unit(np.asarray(facing, dtype=float))), "height_m": float(height_m),
                                                       "trim": tuple(trim), "depth_m": float(depth_m),
                                                       "reach_m": 0.5 * float(height_m) * hull_decals.DESIGN_W / hull_decals.DESIGN_H + depth_m})

    @staticmethod
    def flood(part: str, lamp: Sequence[float], direction: Sequence[float], outer_deg: float, inner_deg: float, range_m: float, colour: Vec3,
              strength: float) -> Marking:
        """A flood's pool of light (``core/hull_decals.flood_pool``) baked as glow: a lamp at ``lamp`` shining along ``direction``."""
        return Marking("flood", part, tuple(colour), {"centre": tuple(lamp), "direction": tuple(unit(np.asarray(direction, dtype=float))),
                                                      "outer_deg": float(outer_deg), "inner_deg": float(inner_deg), "range_m": float(range_m),
                                                      "strength": float(strength), "reach_m": float(range_m)})

    @staticmethod
    def paint(part: str, colour: Vec3, cover: Callable[[np.ndarray, np.ndarray], np.ndarray], placed: bool = False) -> Marking:
        """A base coat of ``colour`` wherever ``cover(points, normals)`` (0..1 per point, in the part's frame) says, laid before the
        seams and the wear so they show through it (M7-T04: the station's blue panel blocks, too irregular for bands and decals).
        ``placed`` keeps ``cover`` in the frame it was authored in when the part is moved (a capital's edge bands, M10-T67)."""
        return Marking("paint", part, tuple(colour), {"cover": cover, **({"origin": (0.0, 0.0, 0.0)} if placed else {})})

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
    # Many points share a lattice cell: hash each cell's corners once and hand them out (M7-T24: the same values, far fewer hashes).
    cells, inverse = _lattice_cells(c)
    weights = [(1.0 - f[:, k], f[:, k]) for k in range(3)]  # each corner's weights along x, y and z, made once
    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                h = _hash01(cells[:, 0] + dx, cells[:, 1] + dy, cells[:, 2] + dz, np.full(len(cells), seed, dtype=np.int64))
                w = weights[0][dx] * weights[1][dy] * weights[2][dz]
                out += w * (h if inverse is None else h[inverse])
    return out


def _lattice_cells(c: np.ndarray) -> tuple[np.ndarray, np.ndarray | None]:
    """The distinct cells among the integer points ``c`` and each point's index among them; the points themselves (and no index)
    when they are few or their box is too big to number."""
    if len(c) < 4096:
        return c, None
    lo = c.min(axis=0)
    span = c.max(axis=0) - lo + 1
    if float(span[0]) * float(span[1]) * float(span[2]) >= 2.0 ** 62:
        return c, None
    key = ((c[:, 0] - lo[0]) * span[1] + (c[:, 1] - lo[1])) * span[2] + (c[:, 2] - lo[2])
    unique, inverse = np.unique(key, return_inverse=True)
    if len(unique) > 0.7 * len(c):
        return c, None
    z = unique % span[2]
    y = (unique // span[2]) % span[1]
    x = unique // (span[2] * span[1])
    return np.stack([x + lo[0], y + lo[1], z + lo[2]], axis=1), inverse.reshape(-1)


# --- what two bakes of one atlas share ---------------------------------------------------------
# A hull's texture sets (M5-T40) are baked from the same atlas buffers and differ only in their drawn layouts, so the work that does
# not depend on the layouts (noise, paint covers, window rows, the metal finish's steps) is kept for the next bake of those buffers
# and dropped with them (M7-T24: the station bakes ten 4 096 px sets).
_SHARED: dict[int, dict[Any, Any]] = {}


def _shared(buffers: AtlasBuffers) -> dict[Any, Any]:
    key = id(buffers)
    if key not in _SHARED:
        _SHARED[key] = {}
        weakref.finalize(buffers, _SHARED.pop, key, None)
    return _SHARED[key]


def _kept(memo: dict[Any, Any], key: Any, make: Callable[[], Any]) -> Any:
    if key not in memo:
        memo[key] = make()
    return memo[key]


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


def _srgb8(values: np.ndarray, rows: int = 1 << 20) -> np.ndarray:
    """Linear colours as sRGB bytes, a block of rows at a time: the same bytes, without whole-atlas float temporaries."""
    values = np.asarray(values)
    out = np.empty(values.shape, dtype=np.uint8)
    for start in range(0, len(values), rows):
        out[start : start + rows] = _to8(linear_to_srgb(values[start : start + rows]))
    return out


def _texel_metric(filled: np.ndarray, pos: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Per texel: the world step along +u and +v (metres per texel), finite differences inside the filled region. Built in strips
    of rows (rows wrap round), so the temporaries stay small at 4 096 px."""
    n = len(pos)
    du, dv = np.empty_like(pos), np.empty_like(pos)
    step_u, step_v = np.empty(filled.shape), np.empty(filled.shape)

    def blend(here: np.ndarray, f: np.ndarray, p_fwd: np.ndarray, p_bwd: np.ndarray, f_fwd: np.ndarray, f_bwd: np.ndarray) -> np.ndarray:
        forward, backward = p_fwd - here, here - p_bwd
        has_forward, has_backward = f_fwd & f, f_bwd & f
        out = np.where(has_forward[..., None], forward, np.where(has_backward[..., None], backward, 0.0))
        both = has_forward & has_backward
        return np.where(both[..., None], 0.5 * (forward + backward), out)

    for r0 in range(0, n, 256):
        rr = np.arange(r0, min(r0 + 256, n))
        prev, nxt = (rr - 1) % n, (rr + 1) % n
        here, f = pos[rr], filled[rr]
        du[rr] = blend(here, f, np.roll(here, -1, axis=1), np.roll(here, 1, axis=1), np.roll(f, -1, axis=1), np.roll(f, 1, axis=1))
        dv[rr] = blend(here, f, pos[nxt], pos[prev], filled[nxt], filled[prev])
    step_u[:] = np.linalg.norm(du, axis=-1)
    step_v[:] = np.linalg.norm(dv, axis=-1)
    return du, dv, step_u, step_v


def _gradient_rows(height: np.ndarray, filled: np.ndarray, rr: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """d height / d texel along u (columns) and v (rows) for the rows ``rr``, one-sided at the region's border; rows wrap round."""
    n = len(height)
    prev, nxt = (rr - 1) % n, (rr + 1) % n
    h, f = height[rr], filled[rr]

    def blend(h_fwd: np.ndarray, h_bwd: np.ndarray, f_fwd: np.ndarray, f_bwd: np.ndarray) -> np.ndarray:
        forward, backward = h_fwd - h, h - h_bwd
        has_forward, has_backward = f_fwd & f, f_bwd & f
        out = np.where(has_forward, forward, np.where(has_backward, backward, 0.0))
        return np.where(has_forward & has_backward, 0.5 * (forward + backward), out)

    du = blend(np.roll(h, -1, axis=1), np.roll(h, 1, axis=1), np.roll(f, -1, axis=1), np.roll(f, 1, axis=1))
    dv = blend(height[nxt], height[prev], filled[nxt], filled[prev])
    return du, dv


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


def _normal_map(atlas: Atlas, style: Style, platings: Sequence[Plating], scale: int = NORMAL_SCALE,
                seam_height: np.ndarray | None = None) -> np.ndarray:
    """The tangent-space normal map, as 8-bit texels, at ``scale`` times the atlas: the plating's relief (grooves, hatches, rivets) from a
    height field sampled at the finer texels, over the fine mesh's shape for a coarse render mesh. ``seam_height`` is that height
    field already evaluated (at the atlas's own size, without the generic plating)."""
    b = atlas.buffers
    size = b.size
    big = size * scale
    du, dv, step_u, step_v = _texel_metric(b.filled, b.position)
    paneled_table = np.array([m.paneled for m in atlas.materials], dtype=bool)
    chart_normal = _kept(_shared(b), ("chart_normals",), lambda: _chart_normals(b))
    # Where each fine texel falls in the atlas: its nearest atlas texel, and a bilinear position inside one chart.
    src = (np.arange(big) + 0.5) / scale - 0.5
    near = np.clip(np.rint(src).astype(np.int64), 0, size - 1)
    lo = np.clip(np.floor(src).astype(np.int64), 0, size - 1)
    hi = np.clip(lo + 1, 0, size - 1)
    t = np.clip(src - lo, 0.0, 1.0)
    height = np.zeros((big, big)) if seam_height is None else seam_height
    # At the atlas's own size the fine grid is the atlas's: its arrays as they are, not gathered copies.
    grid = (lambda a: a) if scale == 1 else (lambda a: a[np.ix_(near, near)])
    filled_big = grid(b.filled)
    grid_rows = (lambda a, rr: a[rr]) if scale == 1 else (lambda a, rr: a[np.ix_(near[rr], near)])
    strip = 256
    for r0 in range(0, big if seam_height is None else 0, strip):
        rr = np.arange(r0, min(r0 + strip, big))
        rn, rl, rh, rt = near[rr], lo[rr], hi[rr], t[rr]
        f_near = b.filled[np.ix_(rn, near)]
        if not f_near.any():
            continue
        chart = b.chart[np.ix_(rn, near)]
        if scale == 1:
            # At the atlas's own size each fine texel is an atlas texel: the bilinear weights are 1 on it and 0 elsewhere.
            position = b.position[rr]
        else:
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
    fine = _fine_normals(atlas, du, dv)
    del du, dv
    out = np.empty((big, big, 3), dtype=np.uint8)
    # In strips of rows, so the float intermediates (the gradients, the stacked and normalised vectors) stay small at 8 192 px.
    for r0 in range(0, big, strip):
        rr = np.arange(r0, min(r0 + strip, big))
        hu, hv = _gradient_rows(height, filled_big, rr)
        su = np.maximum(grid_rows(step_u, rr) / scale, 1e-6)
        sv = np.maximum(grid_rows(step_v, rr) / scale, 1e-6)
        relief = unit(np.stack([-hu / su, hv / sv, np.ones(hu.shape)], axis=-1))
        if fine is not None:
            shape = grid_rows(fine, rr)
            relief = unit(np.stack([relief[..., 0] + shape[..., 0], relief[..., 1] + shape[..., 1], relief[..., 2] * shape[..., 2]], axis=-1))
        relief[~filled_big[rr]] = (0.0, 0.0, 1.0)
        out[rr] = _to8(relief * 0.5 + 0.5)
    return out


def metal_finish(finish: dict[str, float], pos: np.ndarray, painted: np.ndarray, roughness: np.ndarray, metallic: np.ndarray,
                 dirt: np.ndarray, seed: int, memo: dict[Any, Any] | None = None) -> tuple[np.ndarray, np.ndarray]:
    """Painted metal, not plastic (M7-T16; a style opts in with ``extra["metal_finish"]``): the paint's roughness steps from panel to
    panel (``panel_m`` cells, +-``panel_rough``) and drifts within them (+-``noise_rough``), so a highlight breaks up across the plating;
    dirt (0..1) is rougher (``dirt_rough``) and duller (``dirt_metal``) than the metal under it."""
    def steps() -> tuple[np.ndarray, np.ndarray]:
        cell = np.floor(pos / float(finish.get("panel_m", 1.0))).astype(np.int64)
        cells, inverse = _lattice_cells(cell)  # each panel hashed once
        hashed = _hash01(cells[:, 0], cells[:, 1], cells[:, 2], np.full(len(cells), seed + 911, dtype=np.int64))
        return (2.0 * (hashed if inverse is None else hashed[inverse]) - 1.0,
                2.0 * value_noise(pos, float(finish.get("noise_m", 0.35)), seed + 913) - 1.0)

    key = ("metal_finish", seed, float(finish.get("panel_m", 1.0)), float(finish.get("noise_m", 0.35)))
    step, drift = _kept(memo, key, steps) if memo is not None else steps()
    shift = float(finish.get("panel_rough", 0.0)) * step + float(finish.get("noise_rough", 0.0)) * drift
    roughness = roughness + np.where(painted, shift, 0.0) + float(finish.get("dirt_rough", 0.0)) * dirt
    metallic = metallic * (1.0 - float(finish.get("dirt_metal", 0.0)) * dirt)
    return roughness, metallic


def worn_seams(style: Style, atlas: Atlas) -> tuple[Style, Atlas]:
    """The style and the atlas with the seams as the style wears them (Q69): the grid's grooves, hatches and lines and the drawn
    layouts' grooves at its shares of their full depth and width. A style at full shares (the hulls pinned until T74) bakes as before."""
    depth, width = style.seam_depth, style.seam_width
    if depth == 1.0 and width == 1.0:
        return style, atlas
    worn = dataclasses.replace(style, panel_line_width_m=style.panel_line_width_m * width, groove_depth_m=style.groove_depth_m * depth,
                               hatch_depth_m=style.hatch_depth_m * depth, seam_depth=1.0, seam_width=1.0)
    return worn, dataclasses.replace(atlas, part_seams=tuple(layout.softened(depth, width) for layout in atlas.part_seams))


def bake_maps(atlas: Atlas, style: Style, seed: int, occlusion: bool = True, paintable: Sequence[str] = (),
              normal_scale: int = NORMAL_SCALE) -> dict[str, np.ndarray]:
    """The four maps as 8-bit RGB arrays: ``albedo`` (sRGB), ``normal`` (tangent space, +Y up, ``normal_scale`` times the atlas),
    ``orm`` and ``emissive`` (sRGB). With ``paintable`` material names the albedo is RGBA, its alpha where a livery may paint (M4-T30b):
    those materials, less the chipped edges and the markings."""
    style, atlas = worn_seams(style, atlas)
    b = atlas.buffers
    size = b.size
    filled = b.filled
    memo = _shared(b)
    idx, pos, nrm, mat, part = _kept(memo, ("texels",), lambda: (lambda i: (i, b.position[i], b.normal[i], b.material[i], b.part[i]))(
        np.nonzero(filled)))
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
    names = list(atlas.part_names)

    # Base coats painted by pattern (M7-T04), under the plating, the seams and the wear.
    for marking in atlas.markings:
        if marking.kind != "paint":
            continue
        sel = (np.ones(n, dtype=bool) if not marking.part else part == names.index(marking.part)) & ~glass
        if sel.any():
            cover = _kept(memo, ("paint", id(marking)),
                          lambda m=marking, sel=sel: np.clip(np.asarray(m.params["cover"](pos[sel] - np.asarray(m.params.get("origin", (0.0, 0.0, 0.0))),
                                                                                       nrm[sel]), dtype=float), 0.0, 1.0))
            albedo[sel] = albedo[sel] * (1.0 - cover)[:, None] + np.asarray(marking.colour, dtype=float) * cover[:, None]

    # The paint: each part's plating (panel lines and tint) with the part's own phase.
    on_line = np.zeros(n, dtype=bool)
    lattice_aft = np.full(n, np.inf)
    lattice_cell = np.zeros((n, 3), dtype=np.int64)
    platings = atlas.part_platings or (tuple(plating_for(name, atlas.hull_mesh, style) for name in atlas.part_names) if atlas.grid else ())
    chart_normal = _kept(_shared(b), ("chart_normals",), lambda: _chart_normals(b))
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
    # The layouts' relief, kept for the normal map: at the atlas's own size it is these same texels (M7-T24: evaluated once).
    seam_height = np.zeros((size, size)) if normal_scale == 1 and not atlas.grid else None
    for p_index, layout in enumerate(atlas.part_seams):
        sel = part == p_index
        if not layout or not sel.any():
            continue
        drawn = layout.evaluate(pos[sel], nrm[sel], *seam_size(atlas.texel_m))
        painted = paneled[sel]
        if seam_height is not None:
            seam_height[idx[0][sel], idx[1][sel]] = 0.0 + np.where(painted, drawn.height, 0.0)
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
    noise_fine = _kept(memo, ("noise", 0.11 * k, seed + 1), lambda: value_noise(pos, 0.11 * k, seed + 1))
    noise_coarse = _kept(memo, ("noise", style.grime_scale_m, seed + 2), lambda: value_noise(pos, style.grime_scale_m, seed + 2))
    edge = np.clip(1.0 - b.edge_distance[idx] / style.edge_wear_width_m, 0.0, 1.0)
    plain = np.array([m.smooth for m in table], dtype=bool)[mat]  # smooth finishes (gun barrels) stay clean
    chips = np.clip((edge * (0.35 + noise_fine) - (1.0 - style.edge_wear)) * 3.0, 0.0, 1.0) * ~glass * ~plain
    # A weathering term a style sets to nothing is left out (the same maps: it would add or multiply by zero).
    if style.streaks:
        streak_seed = _hash01(lattice_cell[:, 0], lattice_cell[:, 1], lattice_cell[:, 2] + 17, seeds)
        streak_on = np.clip((streak_seed - 0.45) / 0.55, 0.0, 1.0)
        across = _hash01(lattice_cell[:, 0], lattice_cell[:, 1], np.floor(noise_fine * 7.0).astype(np.int64), seeds + 3)
        fade = np.exp(-np.where(np.isfinite(lattice_aft), lattice_aft, 1e3) / (float(extra.get("streak_length_m", 0.2)) * k))
        streak = style.streaks * streak_on * fade * (across > 0.45) * paneled
        del streak_seed, streak_on, across, fade
    else:
        streak = np.zeros(n)
    del seeds, lattice_cell, lattice_aft  # per-texel arrays only the streaks read
    if float(extra.get("smudge", 0.0)):
        smudge_scale = float(extra.get("smudge_scale_m", 0.45)) * k
        smudge_noise = _kept(memo, ("smudge", smudge_scale, seed + 5),
                             lambda: value_noise(pos * np.array([1.0, 1.0, 0.35]), smudge_scale, seed + 5))  # long fore and aft
        smudge = float(extra.get("smudge", 0.0)) * np.clip((smudge_noise - 0.55) / 0.25, 0.0, 1.0) ** 1.5 * paneled
    else:
        smudge = np.zeros(n)
    if float(extra.get("speckle", 0.0)):
        speckle_noise = _kept(memo, ("noise", 0.035 * k, seed + 6), lambda: value_noise(pos, 0.035 * k, seed + 6))
        speckle = float(extra.get("speckle", 0.0)) * (2.0 * speckle_noise - 1.0) * paneled
    else:
        speckle = np.zeros(n)
    grime = np.where(plain, 1.0, 1.0 + style.grime * (2.0 * noise_coarse - 1.0) + speckle)
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
    marked = np.zeros(n)
    window_glow = np.zeros((n, 3))
    window_strength = np.zeros(n)
    for marking in atlas.markings:
        if marking.kind == "paint":
            continue
        sel = np.ones(n, dtype=bool) if not marking.part else part == names.index(marking.part)
        sel &= ~glass
        if "reach_m" in marking.params:  # a local decal: only the texels in its box, so a big atlas is not copied whole
            for axis in range(3):
                sel &= np.abs(pos[:, axis] - marking.params["centre"][axis]) <= marking.params["reach_m"]
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
            cover, glow = _kept(memo, ("windows", id(marking), seed),
                                lambda q=q, p=p, sel=sel: _window_cover(q, p, nrm[sel], max(atlas.texel_m, soft), seed))
            rows = np.flatnonzero(sel)
            window_glow[rows] = np.maximum(window_glow[rows], glow[:, None] * colour)
            window_strength[rows] = np.where(glow > 0.0, q["strength"], window_strength[rows])
            colour = np.array([0.018, 0.02, 0.024])  # dark glass where a window is unlit, and round the glow where it is
            roughness[sel] = roughness[sel] * (1.0 - cover) + 0.15 * cover
        elif marking.kind == "emblem":
            facing = np.asarray(q["facing"])
            d = p - np.asarray(q["centre"])
            near = np.clip((nrm[sel] @ facing - 0.3) / 0.2, 0.0, 1.0) * (np.abs(d @ facing) < q["depth_m"])
            uv = np.stack([d @ np.asarray(q["right"]), d @ np.asarray(q["up"])], axis=1)
            body, trim = hull_decals.emblem(uv, q["height_m"], soft)
            body, trim = body * near, trim * near
            cover = body + trim
            colour = (body[:, None] * colour + trim[:, None] * np.asarray(q["trim"])) / np.maximum(cover, 1e-6)[:, None]
        elif marking.kind == "flood":
            glow = hull_decals.flood_pool(p, nrm[sel], np.asarray(q["centre"]), np.asarray(q["direction"]), q["outer_deg"], q["inner_deg"],
                                          q["range_m"])
            rows = np.flatnonzero(sel)
            # Lit paint, not a glow over it: the pool takes the colour of what it lands on, so an emblem in it keeps its blue.
            lit = np.clip(albedo[sel] / FLOOD_GREY, 0.0, 1.0)
            window_glow[rows] = np.maximum(window_glow[rows], glow[:, None] * colour * lit)
            window_strength[rows] = np.where(glow > 0.0, np.maximum(q["strength"], window_strength[rows]), window_strength[rows])
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

    def glow_map() -> np.ndarray:  # the same in every texture set
        surface_strength = np.where(glass, surface_emissive_strength(table, True), surface_emissive_strength(table, False, atlas.markings))
        scale = np.where(surface_strength > 0.0, strength / np.maximum(surface_strength, 1e-9), 0.0)
        window_scale = np.where(surface_strength > 0.0, window_strength / np.maximum(surface_strength, 1e-9), 0.0)
        glow = np.clip(np.maximum(emissive * scale[:, None], window_glow * window_scale[:, None]), 0.0, 1.0)
        emissive_map8 = np.zeros((size, size, 3), dtype=np.uint8)  # an empty texel is 0 either way; only the filled ones are converted
        emissive_map8[idx] = _srgb8(glow)
        return emissive_map8

    emissive_map8 = _kept(memo, ("emissive", seed), glow_map)  # made now so its per-texel inputs can go
    del emissive, strength, window_glow, window_strength

    # Painted metal (M7-T16, the styles that ask for it): roughness per panel, dirt rough and dull.
    finish = extra.get("metal_finish")
    if finish:
        dirt = np.clip(streak + smudge + np.clip(1.0 - 2.0 * noise_coarse, 0.0, 1.0) * float(finish.get("grime_dirt", 0.5))
                       + float(finish.get("chip_dirt", 0.0)) * chips + float(finish.get("seam_dirt", 0.0)) * on_line, 0.0, 1.0)
        # M7-T17: chipped edges and seams count as dirt too, and a style may keep the dirt off its bare metal (the paint only).
        dirty = ((paneled & ~glass) if finish.get("dirt_on_paint_only") else ~glass) & ~plain
        roughness, metallic = metal_finish(finish, pos, paneled & ~glass, roughness, metallic, dirt * dirty, seed, memo)

    # The normal map: the plating's relief at twice the atlas's resolution, Godot's +Y up (Q34).
    normal8 = _normal_map(atlas, style, platings, normal_scale, seam_height)

    # Occlusion, roughness and metal; emissive scaled per surface so one map serves both.
    occ = _occlusion(atlas, seed) if occlusion else np.ones((size, size))
    # Each channel goes to bytes on its own, so no float copy of all three is held (the same bytes).
    orm8 = np.empty((size, size, 3), dtype=np.uint8)
    occ_channel = np.where(filled, occ, 1.0)
    del occ
    planar = dict(style.extra).get("planar_detail")
    if planar and not occlusion:
        # Texels whose detail tile is laid flat in their own facet (M7-T24, the station hull shader): the slanted facets of the named
        # parts, marked in the occlusion channel, which a hull baked without occlusion does not use.
        wanted = np.isin(part, [names.index(p) for p in planar["parts"] if p in names])
        slanted = np.abs(nrm).max(axis=1) < float(planar["max_axis"])
        occ_channel[idx[0][wanted & slanted], idx[1][wanted & slanted]] = 0.0
    orm_rough = np.full((size, size), 0.7)
    orm_rough[idx] = np.clip(roughness, 0.02, 1.0)
    orm8[..., 0] = _to8(occ_channel)
    del occ_channel
    orm8[..., 1] = _to8(orm_rough)
    del orm_rough
    orm_metal = np.zeros((size, size))
    orm_metal[idx] = np.clip(metallic, 0.0, 1.0)
    orm8[..., 2] = _to8(orm_metal)
    del orm_metal

    mean = albedo[~glass].mean(axis=0) if (~glass).any() else albedo.mean(axis=0)
    # Converted texel by texel, so only the filled texels and the one colour round them (the same bytes as the whole map's).
    albedo8 = np.empty((size, size, 3), dtype=np.uint8)
    albedo8[idx] = _srgb8(np.clip(albedo, 0.0, 1.0))
    albedo8[~filled] = _to8(linear_to_srgb(np.clip(mean, 0.0, 1.0)[None, :]))[0]
    if paintable:
        may_paint = np.isin(np.array([m.name for m in table])[mat], list(paintable)) & ~glass
        paint = np.zeros((size, size))
        paint[idx] = np.where(may_paint, np.clip(1.0 - chips - marked, 0.0, 1.0), 0.0)
        albedo8 = np.concatenate([albedo8, _to8(paint)[..., None]], axis=-1)
    return {
        "albedo": albedo8,
        "normal": normal8,
        "orm": orm8,
        "emissive": emissive_map8,
        "mean_albedo": mean,
    }


def surface_emissive_strength(materials: Sequence[Material], glass: bool, markings: Sequence[Marking] = ()) -> float:
    """The emission energy of one surface: the strongest glow among its materials and, on the opaque surface, its window rows (the map
    holds each glow's share of it)."""
    strengths = [m.emissive_strength for m in materials if (m.transmittance > 0.0) == glass]
    if not glass:
        strengths += [float(m.params["strength"]) for m in markings if m.kind in ("windows", "flood")]
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
