"""The texture maps of a hull (M4-T30a): colour, normal, occlusion/roughness/metal and emissive, baked from the atlas buffers.

Every map is a function of what ``core/raster.py`` knows per texel (world position, normal, part, material, distance to a sharp
edge), so the paint never depends on how a chart was unwrapped. The colour is ``Style.shade_panels`` per texel (the paint the
splats and the painted mesh had), then the generator's markings (bands, stencilled text from a stroke font, decals, soot) and
seeded wear (chipped edges, streaks trailing aft from the panel lines, grime). The normal map carries the panel grooves and
hatch bevels as a height field; occlusion is a disk-to-point estimate against surface samples of the whole hull.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Any

import numpy as np

from .color import linear_to_srgb, srgb_to_linear
from .geometry import Material, Mesh, unit
from .raster import AtlasBuffers
from .sampling import sample_mesh
from ..styles import Style, _hash01

Vec3 = tuple[float, float, float]
OCCLUSION_STEP = 4  # texels between occlusion queries; the result is spread over the texels between
OCCLUSION_RADIUS_M = 0.7
OCCLUSION_SAMPLE_M = 0.12
GLASS_ALBEDO_LIFT = 1.0


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


def srgb_to_linear8(rgb8: np.ndarray) -> np.ndarray:
    return srgb_to_linear(np.asarray(rgb8, dtype=float) / 255.0)


def decode_normal(rgb8: np.ndarray) -> np.ndarray:
    """A normal map's texels back to unit vectors (tangent space, Godot's +Y up)."""
    n = np.asarray(rgb8, dtype=float) / 255.0 * 2.0 - 1.0
    return unit(n)


def _to8(values: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(np.asarray(values) * 255.0), 0, 255).astype(np.uint8)


def _texel_metric(buffers: AtlasBuffers) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Per texel: the world step along +u and +v (metres per texel), finite differences inside the filled region."""
    filled = buffers.filled
    pos = buffers.position

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


def bake_maps(atlas: Atlas, style: Style, seed: int, occlusion: bool = True, paintable: Sequence[str] = ()) -> dict[str, np.ndarray]:
    """The four maps as 8-bit RGB arrays: ``albedo`` (sRGB), ``normal`` (tangent space, +Y up), ``orm`` and ``emissive`` (sRGB).
    With ``paintable`` material names the albedo is RGBA, its alpha where a livery may paint (M4-T30b): those materials, less the
    chipped edges and the markings."""
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

    # The paint: panel lines and tint per part, with the part's own phase, exactly as the splats were painted.
    height = np.zeros(n)
    on_line = np.zeros(n, dtype=bool)
    hatch = np.zeros(n, dtype=bool)
    lattice_fv = np.zeros(n)
    lattice_cell = np.zeros((n, 3), dtype=np.int64)
    aft_axis = np.zeros(n, dtype=bool)
    for p_index, phase in enumerate(atlas.part_phases):
        sel = part == p_index
        if not sel.any():
            continue
        lattice = style.panel_lattice(pos[sel], nrm[sel], phase)
        painted = paneled[sel]
        factor = np.where(lattice["on_line"], style.panel_line_darkness, lattice["tint"])
        factor = np.where(lattice["hatch"], factor * 0.93, factor)
        albedo[sel] *= np.where(painted, factor, 1.0)[:, None]
        on_line[sel] = lattice["on_line"] & painted
        hatch[sel] = lattice["hatch"] & painted
        groove = 1.0 - np.clip((lattice["edge_m"] - 0.5 * style.panel_line_width_m) / (0.5 * style.panel_line_width_m) + 1.0, 0.0, 1.0)
        h = -style.groove_depth_m * groove * groove * (3.0 - 2.0 * groove)
        bevel = np.clip(lattice["hatch_edge_m"] / 0.03, 0.0, 1.0)
        h -= np.where(lattice["hatch"], style.hatch_depth_m * bevel, 0.0)
        height[sel] = np.where(painted, h, 0.0)
        lattice_fv[sel] = lattice["fv"]
        lattice_cell[sel] = np.stack([lattice["cu"], lattice["cv"], lattice["drop"]], axis=1)
        aft_axis[sel] = lattice["drop"] != 2  # the lattice's v is world z: streaks can run aft along it

    # Wear, seeded: chipped sharp edges show bare metal, streaks trail aft from the panel lines, grime varies the paint.
    noise_fine = value_noise(pos, 0.11, seed + 1)
    noise_coarse = value_noise(pos, style.grime_scale_m, seed + 2)
    edge = np.clip(1.0 - b.edge_distance[idx] / style.edge_wear_width_m, 0.0, 1.0)
    chips = np.clip((edge * (0.35 + noise_fine) - (1.0 - style.edge_wear)) * 3.0, 0.0, 1.0) * ~glass
    streak_seed = _hash01(lattice_cell[:, 0], lattice_cell[:, 1], lattice_cell[:, 2] + 17, np.full(n, seed, dtype=np.int64))
    streak_on = np.clip((streak_seed - 0.55) / 0.45, 0.0, 1.0)
    across = _hash01(lattice_cell[:, 0], lattice_cell[:, 1], np.floor(noise_fine * 6.0).astype(np.int64), np.full(n, seed + 3, dtype=np.int64))
    streak = style.streaks * streak_on * np.exp(-lattice_fv * style.panel_size_m / 0.2) * (across > 0.5) * aft_axis * paneled
    grime = 1.0 + style.grime * (2.0 * noise_coarse - 1.0)
    albedo *= (grime * (1.0 - streak))[:, None]
    bare = np.array([0.42, 0.42, 0.44])
    albedo = albedo * (1.0 - chips)[:, None] + bare * chips[:, None]
    roughness = roughness + 0.25 * on_line - 0.25 * chips
    metallic = metallic * (1.0 - chips) + 0.85 * chips

    # The markings, in world space, on their parts; what they cover is kept from the livery's paint.
    names = list(atlas.part_names)
    marked = np.zeros(n)
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
            cover = np.clip((0.5 * q["width_m"] - np.abs(along - q["at_m"])) / 0.01 + 0.5, 0.0, 1.0)
        elif marking.kind in ("text", "rect"):
            facing = np.asarray(q["facing"])
            face = np.clip((nrm[sel] @ facing - 0.3) / 0.2, 0.0, 1.0)
            d = p - np.asarray(q["centre"])
            uv = np.stack([d @ np.asarray(q["right"]), d @ np.asarray(q["up"])], axis=1)
            if marking.kind == "text":
                cover = text_coverage(uv, q["text"], q["height_m"], q["stroke_m"]) * face
            else:
                half = 0.5 * np.asarray(q["size_m"])
                inside = np.clip((half - np.abs(uv)) / 0.01 + 0.5, 0.0, 1.0)
                cover = inside[:, 0] * inside[:, 1] * face
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

    # The normal map: the height field's slope per metre, in the texel's tangent frame (u right, v down; Godot's +Y up).
    height_map = np.zeros((size, size))
    height_map[idx] = height
    hu, hv = _gradient(height_map, filled)
    _, _, step_u, step_v = _texel_metric(b)
    slope_u = hu / np.maximum(step_u, 1e-6)
    slope_v = hv / np.maximum(step_v, 1e-6)
    normal_ts = np.stack([-slope_u, slope_v, np.ones((size, size))], axis=-1)
    normal_ts = unit(normal_ts)
    normal_ts[~filled] = (0.0, 0.0, 1.0)

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
    surface_strength = np.where(glass, surface_emissive_strength(table, True), surface_emissive_strength(table, False))
    scale = np.where(surface_strength > 0.0, strength / np.maximum(surface_strength, 1e-9), 0.0)
    glow = np.clip(emissive * scale[:, None], 0.0, 1.0)
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


def surface_emissive_strength(materials: Sequence[Material], glass: bool) -> float:
    """The emission energy of one surface: the strongest glow among its materials (the map holds each glow's share of it)."""
    strengths = [m.emissive_strength for m in materials if (m.transmittance > 0.0) == glass]
    return max(strengths) if strengths else 0.0


__all__ = ["Atlas", "Marking", "bake_maps", "decode_normal", "glyph_strokes", "srgb_to_linear8", "surface_emissive_strength",
           "text_coverage", "value_noise"]
