"""A shared near-field detail layer for big hulls (M7-T04, D72): small plating tiled in the hull's own space, so an 8 km station
reads from 50 m without an atlas the size of its surface.

The per-piece atlas carries the broad paint and the large panels at about a metre a texel. This layer adds what that texel cannot:
plates of one to four metres with fine seams, a few inset hatches and a plate-to-plate tone. It is one seamless square tile, laid
by the renderer three ways along the piece's axes (triplanar in object space), so it travels with a turning drum.

The game blends it as Godot's detail layer in multiply mode: ``albedo *= mix(1, rgb, a)`` and the normal map moves toward the
tile's by ``a``. So the alpha is high on the seams (where the tile's normal matters) and low on a plate's face, where the atlas's
own panel relief must keep showing.
"""

from __future__ import annotations

import numpy as np

from ..styles import _hash01
from .color import linear_to_srgb

DEFAULT_PX = 1024
DEFAULT_TILE_M = 16.0
CELL_M = 4.0  # the plating's fields before they are split; the tile holds a whole number of them, so it wraps
SPLITS = 2
MIN_PLATE_M = 1.0
LINE_M = 0.09
GROOVE_M = 0.025
FACE_ALPHA = 0.35  # how much of the tile reaches a plate's face (its tone, and its flat normal over the atlas's)
LINE_DARK = 0.5
HATCH_SHARE = 0.14
HATCH_INSET_M = 0.25
TILT = 0.06  # each plate leans this much (rad, +-) off the surface, so a highlight breaks up plate by plate (metal, not plastic)


def _smooth(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _plates(u: np.ndarray, v: np.ndarray, fields: int, seed: int) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Each point's plate: its key and its bounds. The fields' indices wrap every ``fields`` cells, so the plating is periodic."""
    iu, iv = np.floor(u / CELL_M).astype(np.int64), np.floor(v / CELL_M).astype(np.int64)
    u0, v0 = iu * CELL_M, iv * CELL_M
    u1, v1 = u0 + CELL_M, v0 + CELL_M
    s = np.full(u.shape, seed, dtype=np.int64)
    key = (_hash01(np.mod(iu, fields), np.mod(iv, fields), s) * 0xFFFFFF).astype(np.int64)
    for k in range(SPLITS):
        w, h = u1 - u0, v1 - v0
        at = 0.3 + 0.4 * _hash01(key, s + 307 + k)
        along_u = np.where(w > 1.4 * h, True, np.where(h > 1.4 * w, False, _hash01(key, s + 211 + k) < 0.5))
        size = np.where(along_u, w, h)
        split = (_hash01(key, s + 101 + k) >= 0.2) & (size * np.minimum(at, 1.0 - at) >= MIN_PLATE_M)
        cu, cv = u0 + at * w, v0 + at * h
        first = np.where(along_u, u < cu, v < cv)
        su, sv = split & along_u, split & ~along_u
        u1 = np.where(su & first, cu, u1)
        u0 = np.where(su & ~first, cu, u0)
        v1 = np.where(sv & first, cv, v1)
        v0 = np.where(sv & ~first, cv, v0)
        key = np.where(split, (_hash01(key, first.astype(np.int64) + 7, s + k) * 0xFFFFFF).astype(np.int64), key)
    return key, u0, u1, v0, v1


def detail_tile(px: int = DEFAULT_PX, tile_m: float = DEFAULT_TILE_M, seed: int = 0) -> dict[str, np.ndarray]:
    """The tile's two maps as 8-bit arrays: ``albedo`` (RGBA, the multiply factor in sRGB and the blend in alpha) and ``normal``
    (tangent space, +Y up). ``tile_m`` must hold a whole number of plating fields."""
    fields = round(tile_m / CELL_M)
    if fields < 1 or abs(fields * CELL_M - tile_m) > 1e-9:
        raise ValueError(f"the tile ({tile_m} m) must hold a whole number of {CELL_M} m fields")
    texel = tile_m / px
    centres = (np.arange(px) + 0.5) * texel
    u, v = np.meshgrid(centres, centres)
    key, u0, u1, v0, v1 = _plates(u, v, fields, seed)
    edge = np.minimum(np.minimum(u - u0, u1 - u), np.minimum(v - v0, v1 - v))
    s = np.full(u.shape, seed, dtype=np.int64)
    line = _smooth(1.0 - edge / (0.5 * LINE_M))
    height = -GROOVE_M * line
    # Inset hatches on a few plates: a groove round them and the face sunk a little.
    hatch = (_hash01(key, s + 503) < HATCH_SHARE) & (np.minimum(u1 - u0, v1 - v0) > 3.0 * HATCH_INSET_M)
    inner = edge - HATCH_INSET_M
    hatch_line = _smooth(1.0 - np.abs(inner) / (0.4 * LINE_M)) * hatch
    height -= 0.6 * GROOVE_M * hatch_line + 0.3 * GROOVE_M * _smooth(inner / LINE_M) * hatch
    line = np.maximum(line, 0.8 * hatch_line)
    # Each plate leans a little: a tilted plane over it, flat again at its seams so the tile still wraps.
    tu, tv = TILT * (2.0 * _hash01(key, s + 701) - 1.0), TILT * (2.0 * _hash01(key, s + 709) - 1.0)
    height += (tu * (u - 0.5 * (u0 + u1)) + tv * (v - 0.5 * (v0 + v1))) * (1.0 - line)
    # Each plate's own tone, darker toward its seams (grime in the joints); darkening only, since the blend multiplies.
    tone = 1.0 - 0.07 * _hash01(key, s + 401) - 0.05 * np.exp(-edge / 0.35)
    alpha = np.maximum(FACE_ALPHA, line)
    face = 1.0 - (1.0 - tone) / FACE_ALPHA
    factor = np.where(line > 0.0, face * (1.0 - line) + LINE_DARK * line, face)
    rgb = np.clip(linear_to_srgb(np.clip(factor, 0.0, 1.0)), 0.0, 1.0)
    albedo = np.concatenate([np.repeat(rgb[..., None], 3, axis=-1), alpha[..., None]], axis=-1)
    # Slopes with wrap-around differences, so the normal map is as seamless as the plating.
    dhdu = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) / (2.0 * texel)
    dhdv = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / (2.0 * texel)
    n = np.stack([-dhdu, dhdv, np.ones_like(height)], axis=-1)  # image rows run down, the map's +Y up
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    to8 = lambda a: np.clip(np.rint(a * 255.0), 0, 255).astype(np.uint8)  # noqa: E731
    return {"albedo": to8(albedo), "normal": to8(n * 0.5 + 0.5)}


__all__ = ["DEFAULT_PX", "DEFAULT_TILE_M", "detail_tile"]
