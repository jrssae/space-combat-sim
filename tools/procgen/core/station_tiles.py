"""The station's detail tiles (M7-T24): the near-field plating laid by the station hull shader over each piece's atlas, at two scales,
so an 8 km hull reads sharp from a few metres and is never one plain colour from a kilometre.

* The **fine** tile is the Earth Alliance mosaic of ``core/detail_layer.py`` (plates 0.8 to 3.2 m, 16 m a tile). The high set adds
  the raised and sunk "maze" relief of the show's station close-ups inside the plates (raised inner panels, split panels, vent slots);
  the low set is the mosaic alone.
* The **panel** tile is a mosaic of 6 to 32 m panels (128 m a tile) carrying only tone, sheen and a lean per panel, with grime toward
  its edges: no lines of its own, so it never fights the atlas's drawn seams.

Each map holds four variants of its tile in a 2 x 2 grid. The shader picks a variant and one of eight orientations (four turns, each
mirrored) per tile cell, so no repeat shows; every variant's border is a seam, so a turned tile always meets its neighbour on one.

The colour map is data, not a colour: red the albedo factor (linear, multiplied into the paint), green the roughness shift (0.5 none),
blue the cavity (multiplied into the ambient occlusion). The normal map is tangent space with +Y up, as the atlases' are.
"""

from __future__ import annotations

import numpy as np

from ..styles import _hash01
from .detail_layer import _plates, _smooth

FINE_TILE_M = 16.0
FINE_PX = 1024  # a variant's side: 1.56 cm a texel, one pixel at about 50 m on a 3 456-row screen
PANEL_TILE_M = 128.0
PANEL_PX = 512  # 25 cm a texel
VARIANTS = 4

# The fine mosaic, as the shared detail tile cuts it.
FINE_MAX_M, FINE_MIN_M = 3.2, 0.8
LINE_M = 0.09
GROOVE_M = 0.025
LINE_DARK = 0.55
TILT = 0.06
# The maze relief (high set only): a share of plates each kind.
HATCH_SHARE = 0.12
RAISED_SHARE = 0.22
SPLIT_SHARE = 0.18
VENT_SHARE = 0.08
RAISE_M = 0.03
INSET_M = (0.12, 0.32)
VENT_W_M, VENT_PITCH_M = 0.09, 0.24
# The panel tile.
PANEL_MAX_M, PANEL_MIN_M = 32.0, 6.0
PANEL_TONE = 0.10
PANEL_SHEEN = 0.16
PANEL_GRIME_M = 2.5
PANEL_GRIME = 0.10
PANEL_TILT = 0.015


def _grid(px: int, tile_m: float) -> tuple[np.ndarray, np.ndarray, float]:
    texel = tile_m / px
    centres = (np.arange(px) + 0.5) * texel
    u, v = np.meshgrid(centres, centres)
    return u, v, texel


def _normal(height: np.ndarray, texel: float) -> np.ndarray:
    """Tangent-space normals from a wrapping height field (image rows run down, the map's +Y up)."""
    dhdu = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) / (2.0 * texel)
    dhdv = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / (2.0 * texel)
    n = np.stack([-dhdu, dhdv, np.ones_like(height)], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def _to8(a: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(a * 255.0), 0, 255).astype(np.uint8)


def _box_distance(u: np.ndarray, v: np.ndarray, u0: np.ndarray, u1: np.ndarray, v0: np.ndarray, v1: np.ndarray) -> np.ndarray:
    """How far inside a box each point is (negative outside)."""
    return np.minimum(np.minimum(u - u0, u1 - u), np.minimum(v - v0, v1 - v))


def _fine_plates(px: int, seed: int) -> tuple[np.ndarray, ...]:
    """A fine tile's grid and mosaic: the texel centres, the texel, and each texel's plate (key and bounds)."""
    u, v, texel = _grid(px, FINE_TILE_M)
    return (u, v, texel, *_plates(u, v, FINE_TILE_M, seed, FINE_MAX_M, FINE_MIN_M))


def fine_variant(px: int, seed: int, maze: bool, plates: tuple[np.ndarray, ...] | None = None) -> tuple[np.ndarray, np.ndarray]:
    """One fine tile: the colour map (factor, roughness shift, cavity) and the normal, both float in 0..1. ``plates`` is the tile's
    mosaic already cut (``_fine_plates``), shared by both sets."""
    u, v, texel, key, u0, u1, v0, v1 = plates if plates is not None else _fine_plates(px, seed)
    s = np.full(u.shape, seed, dtype=np.int64)
    edge = _box_distance(u, v, u0, u1, v0, v1)
    line = _smooth(1.0 - edge / (0.5 * LINE_M))
    height = -GROOVE_M * line
    cavity = 1.0 - 0.35 * line
    tone = 1.0 - 0.08 * _hash01(key, s + 401) - 0.06 * np.exp(-edge / 0.35)
    rough = 0.10 * (2.0 * _hash01(key, s + 409) - 1.0) + 0.12 * line
    pick = _hash01(key, s + 503)
    small = np.minimum(u1 - u0, v1 - v0)
    if maze:
        inset = INSET_M[0] + (INSET_M[1] - INSET_M[0]) * _hash01(key, s + 601)
        inner = edge - inset
        groove = _smooth(1.0 - np.abs(inner) / (0.35 * LINE_M))
        lo = 0.0
        for share, kind in ((HATCH_SHARE, 0), (RAISED_SHARE, 1), (SPLIT_SHARE, 2), (VENT_SHARE, 3)):
            on = (pick >= lo) & (pick < lo + share) & (small > 3.0 * inset + 0.3)
            lo += share
            if kind == 0:  # an inset hatch: a groove round it and its face sunk
                height -= on * (0.6 * GROOVE_M * groove + 0.3 * GROOVE_M * _smooth(inner / LINE_M))
                line = np.maximum(line, on * 0.8 * groove)
            elif kind == 1:  # a raised inner panel with a bevelled edge
                height += on * RAISE_M * _smooth(inner / (0.6 * LINE_M))
                cavity -= on * 0.25 * groove
            elif kind == 2:  # the inner panel split along its length, the parts alternately raised and sunk
                along_u = (u1 - u0) >= (v1 - v0)
                t = np.where(along_u, (u - u0) / np.maximum(u1 - u0, 1e-6), (v - v0) / np.maximum(v1 - v0, 1e-6))
                parts = 2 + (_hash01(key, s + 607) < 0.5)
                part = np.minimum(np.floor(t * parts), parts - 1)
                cut = np.abs(t * parts - np.round(t * parts)) * np.where(along_u, u1 - u0, v1 - v0) / parts
                sign = np.where(_hash01(key, part.astype(np.int64), s + 613) < 0.5, 1.0, -0.6)
                face = _smooth(inner / (0.6 * LINE_M)) * _smooth(cut / (0.5 * LINE_M))
                height += on * RAISE_M * sign * face
                splits = _smooth(1.0 - cut / (0.3 * LINE_M)) * (inner > 0.0)
                line = np.maximum(line, on * 0.6 * np.maximum(groove, splits))
                cavity -= on * 0.25 * np.maximum(groove, splits)
            else:  # a row of vent slots across the plate's short side
                along_u = (u1 - u0) >= (v1 - v0)
                a = np.where(along_u, u - u0, v - v0)
                slot = np.abs(np.mod(a, VENT_PITCH_M) - 0.5 * VENT_PITCH_M) < 0.5 * VENT_W_M
                inside = slot & (inner > 0.0)
                height -= on * inside * 1.4 * GROOVE_M
                cavity -= on * inside * 0.45
                tone -= on * inside * 0.25
                rough += on * inside * 0.15
                line = np.maximum(line, on * 0.6 * groove)
    else:
        hatch = (pick < HATCH_SHARE) & (small > 0.75)
        inner = edge - 0.25
        groove = _smooth(1.0 - np.abs(inner) / (0.4 * LINE_M)) * hatch
        height -= 0.6 * GROOVE_M * groove + 0.3 * GROOVE_M * _smooth(inner / LINE_M) * hatch
        line = np.maximum(line, 0.8 * groove)
    tu, tv = TILT * (2.0 * _hash01(key, s + 701) - 1.0), TILT * (2.0 * _hash01(key, s + 709) - 1.0)
    height += (tu * (u - 0.5 * (u0 + u1)) + tv * (v - 0.5 * (v0 + v1))) * (1.0 - line)
    factor = tone * (1.0 - line) + LINE_DARK * line
    colour = np.stack([np.clip(factor, 0.0, 1.0), np.clip(0.5 + 0.5 * rough, 0.0, 1.0), np.clip(cavity, 0.0, 1.0)], axis=-1)
    return colour, _normal(height, texel) * 0.5 + 0.5


def panel_variant(px: int, seed: int) -> tuple[np.ndarray, np.ndarray]:
    """One panel tile: tone, sheen and grime per 6 to 32 m panel, and a slight lean per panel; no lines."""
    u, v, texel = _grid(px, PANEL_TILE_M)
    key, u0, u1, v0, v1 = _plates(u, v, PANEL_TILE_M, seed, PANEL_MAX_M, PANEL_MIN_M, levels=10)
    s = np.full(u.shape, seed, dtype=np.int64)
    edge = _box_distance(u, v, u0, u1, v0, v1)
    grime = np.exp(-edge / PANEL_GRIME_M)
    tone = 1.0 - PANEL_TONE * _hash01(key, s + 401) - PANEL_GRIME * grime
    rough = PANEL_SHEEN * (2.0 * _hash01(key, s + 409) - 1.0) + 0.08 * grime
    tu, tv = PANEL_TILT * (2.0 * _hash01(key, s + 701) - 1.0), PANEL_TILT * (2.0 * _hash01(key, s + 709) - 1.0)
    flat = _smooth(edge / 0.5)
    height = (tu * (u - 0.5 * (u0 + u1)) + tv * (v - 0.5 * (v0 + v1))) * flat
    colour = np.stack([np.clip(tone, 0.0, 1.0), np.clip(0.5 + 0.5 * rough, 0.0, 1.0), np.ones_like(tone)], axis=-1)
    return colour, _normal(height, texel) * 0.5 + 0.5


def _grid_of(variants: list[tuple[np.ndarray, np.ndarray]]) -> dict[str, np.ndarray]:
    """Four variants in a 2 x 2 grid, as 8-bit maps (the normal's blue dropped: the shader rebuilds it)."""
    rows = [np.concatenate([variants[0][k], variants[1][k]], axis=1) for k in (0, 1)], \
        [np.concatenate([variants[2][k], variants[3][k]], axis=1) for k in (0, 1)]
    colour = np.concatenate([rows[0][0], rows[1][0]], axis=0)
    normal = np.concatenate([rows[0][1], rows[1][1]], axis=0)
    normal[..., 2] = 0.0
    return {"colour": _to8(colour), "normal": _to8(normal)}


def fine_tile_sets(px: int = FINE_PX, seed: int = 0) -> tuple[dict[str, np.ndarray], dict[str, np.ndarray]]:
    """Both sets' fine tiles (with the relief, without), each variant's mosaic cut once for the two (the same maps as
    ``fine_tiles`` gives each)."""
    high, low = [], []
    for k in range(VARIANTS):
        variant_seed = seed * 31 + k * 977 + 5
        plates = _fine_plates(px, variant_seed)
        high.append(fine_variant(px, variant_seed, True, plates))
        low.append(fine_variant(px, variant_seed, False, plates))
    return _grid_of(high), _grid_of(low)


def fine_tiles(px: int = FINE_PX, seed: int = 0, maze: bool = True) -> dict[str, np.ndarray]:
    """The fine tile's four variants: ``colour`` (RGB) and ``normal``, each ``2 px`` square."""
    return _grid_of([fine_variant(px, seed * 31 + k * 977 + 5, maze) for k in range(VARIANTS)])


def panel_tiles(px: int = PANEL_PX, seed: int = 0) -> dict[str, np.ndarray]:
    """The panel tile's four variants, as ``fine_tiles``."""
    return _grid_of([panel_variant(px, seed * 37 + k * 1013 + 11) for k in range(VARIANTS)])


__all__ = ["FINE_PX", "FINE_TILE_M", "PANEL_PX", "PANEL_TILE_M", "VARIANTS", "fine_tile_sets", "fine_tiles", "fine_variant", "panel_tiles",
           "panel_variant"]
