"""Painted and lit hull decals (M10-T22): the Earth Alliance emblem and the floods' pools of light. The pools are baked into a hull's
maps; the emblem is drawn by the game as a sharp decal from its own image (:func:`write_images`), lit as the pools light the hull.

The emblem is drawn here from scratch (Q64), close to the maintainer's reference (``references/ships/earth_alliance_emblem_reference.png``,
gitignored): a blue body of faceted pieces, each edged with a thick yellow border, and two yellow bars across its right half. Its pieces
are convex polygons in a 600 by 191 design box (x right, y down, as the reference is drawn); a piece drawn later lays its border over
the one before, which gives the yellow seams between them.

A flood's pool is the light a hull-mounted lamp throws on the plating round it: brightest on the cone's axis, fading to its rim and
with distance, and only on faces turned toward the lamp. It is baked as a soft glow so the pool costs the GPU nothing.
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Any

import numpy as np

from .image import write_png

DESIGN_W, DESIGN_H = 600.0, 191.0
EMBLEM = "ea_emblem"  # the emblem's key among the decal images (:data:`IMAGES`)
EMBLEM_BLUE, EMBLEM_YELLOW = (8, 57, 148), (255, 206, 0)  # the reference's colours (sRGB)
IMAGE_PX = 2048  # a decal image's width; at the Hyperion's 42 m emblem, two centimetres a texel
BORDER = 13.0  # the yellow border's width, in design units
BAR_R = 6.5  # half the bars' thickness

_CAP = ((188.5, 39.0), (242.0, 6.0), (260.0, 2.5), (343.0, 2.0), (356.0, 6.0), (414.0, 41.0))
_LEFT_FOOT = ((109.0, 89.0), (225.0, 155.5), (172.0, 189.5), (51.0, 189.0), (-8.0, 153.0))
_RIGHT_FOOT = ((488.5, 88.5), (606.0, 154.0), (546.0, 189.5), (424.0, 189.0), (377.0, 157.0))
_BODY = ((85.5, 30.0), (511.5, 30.0), (561.5, 62.0), (360.0, 188.0), (248.0, 188.0), (37.0, 62.0))
# Drawing order: the cap and the feet first, the body over them. The corners were fitted to the reference by pixel agreement.
PIECES = ((_CAP,), (_LEFT_FOOT,), (_RIGHT_FOOT,), (_BODY,))
BARS = (((294.5, 94.5), (560.0, 94.5)), ((292.5, 139.0), (470.0, 139.0)))


def _inside_distance(x: np.ndarray, y: np.ndarray, poly: tuple[tuple[float, float], ...]) -> np.ndarray:
    """How far inside a convex polygon each point is (negative outside): the nearest edge's distance."""
    pts = np.asarray(poly)
    centre = pts.mean(axis=0)
    out = np.full(x.shape, np.inf)
    for a, b in zip(pts, np.roll(pts, -1, axis=0), strict=True):
        edge = b - a
        normal = np.array([edge[1], -edge[0]]) / np.hypot(*edge)
        if (centre - a) @ normal < 0.0:
            normal = -normal
        out = np.minimum(out, (x - a[0]) * normal[0] + (y - a[1]) * normal[1])
    return out


def _bar_distance(x: np.ndarray, y: np.ndarray, a: tuple[float, float], b: tuple[float, float]) -> np.ndarray:
    """Distance from a horizontal segment, so a bar has round ends."""
    cx = np.clip(x, a[0], b[0])
    return np.hypot(x - cx, y - a[1])


def emblem(uv: np.ndarray, height_m: float, soft_m: float) -> tuple[np.ndarray, np.ndarray]:
    """The emblem's blue body and yellow trim coverage (0..1 each, never overlapping) at ``uv`` (metres from its centre, u to the
    reader's right, v up), the emblem ``height_m`` tall; edges are ``soft_m`` wide."""
    unit_m = height_m / DESIGN_H
    x = uv[:, 0] / unit_m + 0.5 * DESIGN_W
    y = 0.5 * DESIGN_H - uv[:, 1] / unit_m
    soft = max(soft_m / unit_m, 1e-3)
    body = np.zeros(len(uv))
    trim = np.zeros(len(uv))
    for piece in PIECES:
        inside = np.max([_inside_distance(x, y, poly) for poly in piece], axis=0)
        outline = np.clip(inside / soft + 0.5, 0.0, 1.0)
        fill = np.clip((inside - BORDER) / soft + 0.5, 0.0, 1.0)
        body = body * (1.0 - outline) + fill
        trim = trim * (1.0 - outline) + (outline - fill)
    bar = np.zeros(len(uv))  # the last piece's fill is the main body's
    for a, b in BARS:
        bar = np.maximum(bar, np.clip((BAR_R - _bar_distance(x, y, a, b)) / soft + 0.5, 0.0, 1.0))
    bar = np.minimum(bar, fill)  # the bars lie on the main body's blue and run into its border
    return body - bar, trim + bar


def emblem_image(width_px: int = IMAGE_PX) -> np.ndarray:
    """The emblem as an 8-bit sRGB RGBA image, ``width_px`` wide: its colours, and its coverage in alpha with edges smoothed over a
    texel. Clear texels carry the border's yellow, so the mip chain does not darken the edge."""
    height_px = round(width_px * DESIGN_H / DESIGN_W)
    unit = DESIGN_W / width_px
    j, i = np.meshgrid(np.arange(width_px) + 0.5, np.arange(height_px) + 0.5)
    uv = np.stack([(j.ravel() - 0.5 * width_px) * unit, (0.5 * height_px - i.ravel()) * unit], axis=1)
    body, trim = emblem(uv, DESIGN_H, unit)
    cover = body + trim
    blue, yellow = np.asarray(EMBLEM_BLUE, dtype=float), np.asarray(EMBLEM_YELLOW, dtype=float)
    rgb = np.where(cover[:, None] > 1e-6, (body[:, None] * blue + trim[:, None] * yellow) / np.maximum(cover, 1e-6)[:, None], yellow)
    out = np.concatenate([rgb, 255.0 * cover[:, None]], axis=1).reshape(height_px, width_px, 4)
    return np.round(np.clip(out, 0.0, 255.0)).astype(np.uint8)


IMAGES: dict[str, Callable[[], np.ndarray]] = {EMBLEM: emblem_image}


def _to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _to_srgb(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * np.power(np.maximum(c, 0.0), 1.0 / 2.4) - 0.055)


def glow_image(image: np.ndarray, width_m: float, height_m: float, glow: dict[str, Any], grey: float) -> np.ndarray:
    """The light a flood throws on a decal, as an 8-bit sRGB RGB image the decal's size: the pool (:func:`flood_pool`) on its face,
    taking the decal's own colour as the hull's baked pools take the paint's (bright where the paint is as light as ``grey``)."""
    h, w = image.shape[:2]
    j, i = np.meshgrid((np.arange(w) + 0.5) / w - 0.5, 0.5 - (np.arange(h) + 0.5) / h)
    p = np.stack([j.ravel() * width_m, i.ravel() * height_m, np.zeros(j.size)], axis=1)
    n = np.tile([0.0, 0.0, 1.0], (len(p), 1))
    direction = np.asarray(glow["direction"], dtype=float)
    pool = flood_pool(p, n, np.asarray(glow["lamp"], dtype=float), direction / np.linalg.norm(direction), glow["outer_deg"], glow["inner_deg"],
                      glow["range_m"])
    lit = np.clip(_to_linear(image[..., :3].reshape(-1, 3) / 255.0) / grey, 0.0, 1.0)
    light = pool[:, None] * np.asarray(glow["colour"], dtype=float) * lit
    return np.round(255.0 * np.clip(_to_srgb(light), 0.0, 1.0)).reshape(h, w, 3).astype(np.uint8)


def write_images(out_dir: Path, asset_id: str, marks: list[dict[str, Any]], sidecar: str, grey: float) -> list[Path]:
    """Writes each picture mark's image (once per picture) and, for a lit one, its light, with Godot's ``sidecar`` import beside
    each; points the marks at their files (``image``; ``glow`` becomes its file and its energy). Returns the files."""
    files: list[Path] = []
    drawn: dict[str, tuple[np.ndarray, str]] = {}

    def save(name: str, pixels: np.ndarray) -> str:
        png = write_png(out_dir / name, pixels)
        side = Path(str(png) + ".import")
        side.write_text(sidecar, encoding="utf-8", newline="\n")
        files.extend([png, side])
        return png.name

    for mark in marks:
        key = mark["image"]
        if key not in IMAGES:
            raise ValueError(f"mark {mark['name']!r}: no decal image {key!r}; there are {sorted(IMAGES)}")
        if key not in drawn:
            pixels = IMAGES[key]()
            drawn[key] = (pixels, save(f"{asset_id}_{key}.png", pixels))
        pixels, mark["image"] = drawn[key]
        if "glow" in mark:
            light = glow_image(pixels, mark["width_m"], mark["height_m"], mark["glow"], grey)
            mark["glow"] = {"file": save(f"{asset_id}_{mark['name']}_glow.png", light), "energy": float(mark["glow"]["strength"])}
    return files


def flood_pool(p: np.ndarray, n: np.ndarray, at: np.ndarray, direction: np.ndarray, outer_deg: float, inner_deg: float,
               range_m: float) -> np.ndarray:
    """A flood's light (0..1) on hull points ``p`` with normals ``n``: full inside the inner cone, gone at the outer one and at
    ``range_m``, and only on faces that look back at the lamp."""
    d = p - at
    dist = np.linalg.norm(d, axis=1)
    to_p = d / np.maximum(dist, 1e-6)[:, None]
    cos_a = to_p @ direction
    c_out, c_in = np.cos(np.radians(outer_deg)), np.cos(np.radians(inner_deg))
    cone = np.clip((cos_a - c_out) / max(c_in - c_out, 1e-6), 0.0, 1.0)
    reach = np.clip(1.0 - dist / range_m, 0.0, 1.0)
    facing = np.clip(-(n * to_p).sum(axis=1), 0.0, 1.0)
    return cone * cone * (3.0 - 2.0 * cone) * reach * reach * np.sqrt(facing)


__all__ = ["BARS", "BORDER", "DESIGN_H", "DESIGN_W", "EMBLEM", "EMBLEM_BLUE", "EMBLEM_YELLOW", "IMAGES", "IMAGE_PX", "PIECES", "emblem",
           "emblem_image", "flood_pool", "glow_image", "write_images"]
