"""The Minbari Flyer's paint pattern (M10-T58, Q90): on every hull lobe a dark line running lengthwise, with thick curved
bands branching from it towards the lobe's edges, uneven in width, tapering and fading out; no straight edge or corner
anywhere. Each band is a purple core inside a wider blue outline that fades into the body's paint.

Each painted part is laid out as a lobe: a ``Tube`` (round, the line along its crown and its keel, a stroke's length measured
round the girth) or a ``Sheet`` (flat or thin, the line along its middle, the strokes running across it); ``scale`` sizes the
bands for a small lobe, ``outline`` widens the blue round its bands and ``edge`` sharpens
where that blue ends (a higher power holds it at full strength further out), and ``line=False`` leaves the line itself unpainted: the
bands still branch from where it would run, rising out of the body's paint. The covers are
functions of the authored frame (``Marking.paint(..., placed=True)``), evaluated per texel, so every edge is a smooth falloff
at any distance.
"""

from __future__ import annotations

import functools
import math
from dataclasses import dataclass

import numpy as np

STROKE_PITCH_M = 1.6  # bands along a line
STROKE_WIDTH_M = 0.2  # a band's purple core, half width at its root
OUTLINE_WIDTHS = 2.8  # the blue outline's half width, in core widths, before a lobe's own ``outline``
ROOT_FADE_WIDTHS = 2.5  # on a lobe without a line, a band rises over this many core widths
OUTLINE_REACH = 1.15  # the outline runs this much further out than the core
LINE_WIDTH_M = 0.1  # the line's half width
CROWN_ANGLES = (0.5 * math.pi, 1.5 * math.pi)  # a tube's lines: along its crown and its keel
LAYERS = ("blue", "purple", "dark")  # painted in this order


@dataclass(frozen=True)
class Tube:
    """A round lobe about an axis along z through ``(cx, cy)``; ``split_y`` puts a pair of lobes either side of y = 0."""

    cx: float
    cy: float = 0.0
    split_y: bool = False
    scale: float = 1.0
    outline: float = 1.0
    edge: float = 3.0
    line: bool = True


@dataclass(frozen=True)
class Sheet:
    """A flat lobe: the line runs along axis ``along`` at ``centre`` on axis ``across`` (``mirror`` takes ``across`` as a
    distance from the centre plane); strokes reach ``reach_m`` either side. ``flat`` keeps the paint to its two broad faces,
    off its thin edge, where a band would be cut into bars."""

    along: int
    across: int
    centre: float
    reach_m: float
    mirror: bool = False
    scale: float = 1.0
    flat: bool = False
    outline: float = 1.0
    edge: float = 3.0
    line: bool = True


@dataclass(frozen=True)
class Strokes:
    """The pattern at each point, every share 0..1: the line, the bands' purple core, their wider blue outline, and how close
    a band point is to its root (1 at the line, 0 at the tip)."""

    line: np.ndarray
    core: np.ndarray
    outline: np.ndarray
    root: np.ndarray
    distance: np.ndarray  # signed, from the line (m)


def _hash(k: np.ndarray, salt: float) -> np.ndarray:
    v = np.sin(k * 12.9898 + salt * 78.233) * 43758.5453
    return v - np.floor(v)


def _layout(p: np.ndarray, lobe: Tube | Sheet, seed: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Each point's place along the lobe's line, its signed distance from the line (m), and how far strokes reach there."""
    if isinstance(lobe, Tube):
        cy = np.where(p[:, 1] >= 0.0, lobe.cy, -lobe.cy) if lobe.split_y else np.full(len(p), lobe.cy)
        dx, dy = p[:, 0] - lobe.cx, p[:, 1] - cy
        r = np.hypot(dx, dy)
        theta = np.arctan2(dy, dx)
        s = p[:, 2]
        best = np.full(len(p), np.inf)
        for k, phi in enumerate(CROWN_ANGLES):
            wander = 0.07 * np.sin(0.45 * s + seed + 1.7 * k) + 0.04 * np.sin(1.3 * s - seed)  # the line meanders: never straight
            delta = np.mod(theta - phi - wander + math.pi, 2.0 * math.pi) - math.pi
            best = np.where(np.abs(delta) < np.abs(best), delta, best)
        return s, r * best, 0.85 * r * 0.5 * math.pi
    s = p[:, lobe.along]
    across = np.abs(p[:, lobe.across]) if lobe.mirror else p[:, lobe.across]
    d = across - lobe.centre - 0.06 * np.sin(0.6 * s + seed) - 0.03 * np.sin(1.7 * s - 2.0 * seed)
    return s, d, np.full(len(p), lobe.reach_m)


def strokes(points: np.ndarray, lobe: Tube | Sheet, seed: float) -> Strokes:
    """The pattern on ``points``. No two bands alike: each has its own place, length, sweep, width and swell."""
    p = np.asarray(points, dtype=float)
    s, d, reach = _layout(p, lobe, seed)
    line = np.exp(-((d / (LINE_WIDTH_M * (1.0 + 0.35 * np.sin(0.7 * s + seed)))) ** 2))
    side = np.where(d >= 0.0, 1.0, -1.0)
    t = np.abs(d)
    pitch, width = STROKE_PITCH_M * lobe.scale, STROKE_WIDTH_M * lobe.scale
    core, outline, root = np.zeros(len(p)), np.zeros(len(p)), np.zeros(len(p))
    base = np.floor(s / pitch)
    for offset in (-2.0, -1.0, 0.0, 1.0, 2.0):
        k = base + offset
        key = 2.0 * k + side + 1000.0 * seed
        start = (k + 0.5 + 0.55 * (_hash(key, 1.0) - 0.5)) * pitch
        length = reach * (0.4 + 0.6 * _hash(key, 2.0))
        u = t / np.maximum(length, 1e-6)
        along = np.clip(u, 0.0, OUTLINE_REACH)
        sweep = (0.8 * _hash(key, 3.0) - 0.25) * np.minimum(length, 1.5 * pitch)  # most sweep aft as they leave the line, a few forward
        centre = start + sweep * along * along + 0.12 * pitch * along * np.sin(4.0 * along + 6.283 * _hash(key, 5.0))
        swell = (0.65 + 0.7 * _hash(key, 6.0)) * (1.0 + 0.3 * np.sin(5.0 * along + 6.283 * _hash(key, 7.0)))
        w = width * swell * (0.3 + 0.7 * np.clip(1.0 - u, 0.0, 1.0) ** 0.7)
        x = np.abs(s - centre) / w
        keep = _hash(key, 4.0) > 0.1
        if not lobe.line:  # no line to spring from: the band's root fades in, or the two sides' bands would end in a cut
            keep = keep * (1.0 - np.exp(-((t / (ROOT_FADE_WIDTHS * width)) ** 2)))
        v = np.exp(-(x**3)) * np.clip(1.0 - u, 0.0, 1.0) ** 0.5 * keep
        halo = np.exp(-((x / (OUTLINE_WIDTHS * lobe.outline)) ** lobe.edge)) * np.clip(1.0 - u / OUTLINE_REACH, 0.0, 1.0) ** 0.5 * keep
        root = np.where(v > core, np.clip(1.0 - u, 0.0, 1.0), root)
        core = np.maximum(core, v)
        outline = np.maximum(outline, halo)
    return Strokes(line, core, outline, root, d)


def cover(points: np.ndarray, normals: np.ndarray, lobe: Tube | Sheet, seed: float, layer: str) -> np.ndarray:
    """One colour's share per point: ``"blue"`` the bands' outlines and a wide soft halo round the line, ``"purple"`` the
    bands' cores and a narrower halo, ``"dark"`` the line and the bands' roots fading into the purple."""
    k = strokes(points, lobe, seed)
    broad = 1.0
    if isinstance(lobe, Sheet) and lobe.flat:
        broad = np.clip((0.75 - np.abs(np.asarray(normals, dtype=float)[:, lobe.across])) / 0.4, 0.0, 1.0)
    near = np.abs(k.distance) / (LINE_WIDTH_M * max(lobe.scale, 0.6))
    if not lobe.line:
        return broad * np.clip({"blue": k.outline, "purple": k.core, "dark": 0.5 * k.core * k.root**2}[layer], 0.0, 1.0)
    if layer == "blue":
        return broad * np.clip(np.maximum(k.outline, 0.9 * np.exp(-((near / 5.5) ** 2))), 0.0, 1.0)
    if layer == "purple":
        return broad * np.clip(np.maximum(k.core, 0.85 * np.exp(-((near / 2.4) ** 2))), 0.0, 1.0)
    return broad * np.clip(np.maximum(k.line, 0.5 * k.core * k.root**2), 0.0, 1.0)


def outboard(points: np.ndarray, normals: np.ndarray) -> np.ndarray:
    """How squarely each point faces away from the centre plane: the fins' outer faces."""
    out = np.asarray(normals, dtype=float)[:, 0] * np.where(np.asarray(points, dtype=float)[:, 0] >= 0.0, 1.0, -1.0)
    k = np.clip(out / 0.2, 0.0, 1.0)
    return k * k * (3.0 - 2.0 * k)


def cover_fn(lobe: Tube | Sheet, seed: float, layer: str):
    """A ``Marking.paint`` cover for one lobe and colour."""
    return functools.partial(cover, lobe=lobe, seed=seed, layer=layer)
