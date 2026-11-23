"""Painted and lit hull decals baked into a hull's maps (M10-T22): the Earth Alliance emblem and the floods' pools of light.

The emblem is drawn here from scratch (Q64), close to the maintainer's reference (``references/ships/earth_alliance_emblem_reference.png``,
gitignored): a blue body of faceted pieces, each edged with a thick yellow border, and two yellow bars across its right half. Its pieces
are convex polygons in a 600 by 191 design box (x right, y down, as the reference is drawn); a piece drawn later lays its border over
the one before, which gives the yellow seams between them.

A flood's pool is the light a hull-mounted lamp throws on the plating round it: brightest on the cone's axis, fading to its rim and
with distance, and only on faces turned toward the lamp. It is baked as a soft glow so the pool costs the GPU nothing.
"""

from __future__ import annotations

import numpy as np

DESIGN_W, DESIGN_H = 600.0, 191.0
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


__all__ = ["BARS", "BORDER", "DESIGN_H", "DESIGN_W", "PIECES", "emblem", "flood_pool"]
