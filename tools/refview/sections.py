"""Section compare (M7-T21): a part's cross-section through the reference STL against the same section through the build.

The silhouette compare (``compare.py``) judges a whole asset from three sides, so a part can be the wrong shape inside its outline and
still pass (the Cobra arm as a flat slab, a roofless cargo bay). Here each part is cut at fixed planes and the filled sections are
compared pixel by pixel inside a window round the part: the intersection over union of the two, ``IoU >= 0.90`` to pass.

A section is filled by the nonzero winding rule from the cut's segments, each oriented by its triangle's outward normal, so a model
built of overlapping closed parts fills as their union and a hole (a tunnel, a bay) stays empty.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

PASS_IOU = 0.90
PLANE_NUDGE_M = 1e-3
# The plane's in-plane axes (u, v) for a cut across each axis: z cuts are seen as x across, y up; x cuts as z along, y up; y cuts
# (from above) as x across, z along.
PLANE_AXES = {0: (2, 1), 1: (0, 2), 2: (0, 1)}


@dataclass(frozen=True)
class SectionPlane:
    """One cut: ``axis`` (0 x, 1 y, 2 z) at ``value``; ``window`` (u0, u1, v0, v1) round the part in the plane's (u, v); a
    ``turn_deg`` about the z axis applied to both meshes first (a Cobra arm seen in its own frame: turned onto the top); with
    ``outline`` the sections are compared filled row by row from their outermost edges (the part's shape, where the build hollows a
    room the reference leaves solid, or the reverse)."""

    name: str
    axis: int
    value: float
    window: tuple[float, float, float, float]
    turn_deg: float = 0.0
    outline: bool = False


@dataclass(frozen=True)
class SectionScore:
    plane: SectionPlane
    iou: float
    reference: np.ndarray  # the reference's filled section in the window (rows from v1 down to v0)
    model: np.ndarray

    @property
    def passed(self) -> bool:
        return self.iou >= PASS_IOU


def turned(tris: np.ndarray, turn_deg: float) -> np.ndarray:
    """Triangles turned by ``turn_deg`` about the z axis."""
    if turn_deg == 0.0:
        return tris
    a = np.radians(turn_deg)
    rot = np.array([[np.cos(a), -np.sin(a), 0.0], [np.sin(a), np.cos(a), 0.0], [0.0, 0.0, 1.0]])
    return tris @ rot.T


def cut_segments(tris: np.ndarray, axis: int, value: float) -> np.ndarray:
    """The section's segments in the plane's (u, v), ``(n, 2, 2)``, each running with the solid on one consistent side (from its
    triangle's outward normal)."""
    t = np.asarray(tris, dtype=float).reshape(-1, 3, 3)
    d = t[:, :, axis] - value
    crossing = (d.min(axis=1) < 0.0) & (d.max(axis=1) > 0.0)
    t, d = t[crossing], d[crossing]
    if len(t) == 0:
        return np.zeros((0, 2, 2))
    points = []
    for i, j in ((0, 1), (1, 2), (2, 0)):
        di, dj = d[:, i], d[:, j]
        hit = di * dj < 0.0
        frac = np.where(hit, di / np.where(hit, di - dj, 1.0), 0.0)
        p = t[:, i] + frac[:, None] * (t[:, j] - t[:, i])
        points.append((hit, p))
    ends = np.zeros((len(t), 2, 3))
    count = np.zeros(len(t), dtype=int)
    for hit, p in points:
        for k in np.flatnonzero(hit):
            if count[k] < 2:
                ends[k, count[k]] = p[k]
            count[k] += 1
    ends, t = ends[count == 2], t[count == 2]
    normal = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    e = np.zeros(3)
    e[axis] = 1.0
    tangent = np.cross(e, normal)  # the boundary's direction with the solid to its left, seen from +axis
    flip = np.einsum("ij,ij->i", ends[:, 1] - ends[:, 0], tangent) < 0.0
    ends[flip] = ends[flip][:, ::-1]
    u, v = PLANE_AXES[axis]
    return ends[:, :, [u, v]]


def section_mask(tris: np.ndarray, plane: SectionPlane, pixel_m: float) -> np.ndarray:
    """The filled section in the plane's window, rows from the window's top (v1) down, by the nonzero winding rule."""
    u0, u1, v0, v1 = plane.window
    # A hair off the plane, so a plane laid on a row of the mesh's corners still cuts every face through it.
    segs = cut_segments(turned(tris, plane.turn_deg), plane.axis, plane.value + PLANE_NUDGE_M)
    cols = int(round((u1 - u0) / pixel_m))
    rows = int(round((v1 - v0) / pixel_m))
    us = u0 + (np.arange(cols) + 0.5) * pixel_m
    mask = np.zeros((rows, cols), dtype=bool)
    if len(segs) == 0:
        return mask
    a, b = segs[:, 0], segs[:, 1]
    lo, hi = np.minimum(a[:, 1], b[:, 1]), np.maximum(a[:, 1], b[:, 1])
    sign = np.where(b[:, 1] > a[:, 1], 1, -1)
    for r in range(rows):
        vc = v1 - (r + 0.5) * pixel_m
        on = (lo <= vc) & (hi > vc)
        if not on.any():
            continue
        fa, fb = a[on], b[on]
        uc = fa[:, 0] + (vc - fa[:, 1]) / (fb[:, 1] - fa[:, 1]) * (fb[:, 0] - fa[:, 0])
        order = np.argsort(uc)
        uc, s = uc[order], sign[on][order]
        # The winding at each column: the signed crossings to its right.
        right = np.concatenate([np.cumsum(s[::-1])[::-1], [0]])
        winding = right[np.searchsorted(uc, us, side="right")]
        mask[r] = winding != 0
    return mask


def fill_holes(mask: np.ndarray) -> np.ndarray:
    """A section's outline: each row filled from its first solid pixel to its last (rooms open to the outside through a door or a
    shaft fill too; the same for both meshes)."""
    out = np.zeros_like(mask)
    rows = np.flatnonzero(mask.any(axis=1))
    for r in rows:
        cols = np.flatnonzero(mask[r])
        out[r, cols[0]: cols[-1] + 1] = True
    return out


def section_score(reference: np.ndarray, model: np.ndarray, plane: SectionPlane, pixel_m: float = 0.5) -> SectionScore:
    """Both meshes' filled sections at ``plane`` and their intersection over union (1.0 when both are empty)."""
    ref, mod = section_mask(reference, plane, pixel_m), section_mask(model, plane, pixel_m)
    if plane.outline:
        ref, mod = fill_holes(ref), fill_holes(mod)
    union = int((ref | mod).sum())
    iou = 1.0 if union == 0 else float((ref & mod).sum()) / union
    return SectionScore(plane, iou, ref, mod)


def overlay(score: SectionScore, scale: int = 4) -> np.ndarray:
    """An RGB picture of the two sections: grey where both are solid, red where only the reference is, blue where only the
    model is."""
    ref, mod = score.reference, score.model
    img = np.full(ref.shape + (3,), 255, dtype=np.uint8)
    img[ref & mod] = (150, 150, 150)
    img[ref & ~mod] = (220, 40, 40)
    img[~ref & mod] = (40, 90, 230)
    return np.kron(img, np.ones((scale, scale, 1), dtype=np.uint8))


def score_all(reference: np.ndarray, model: np.ndarray, planes: Sequence[SectionPlane], pixel_m: float = 0.5) -> list[SectionScore]:
    return [section_score(reference, model, p, pixel_m) for p in planes]


__all__ = ["PASS_IOU", "SectionPlane", "SectionScore", "cut_segments", "fill_holes", "overlay", "score_all", "section_mask", "section_score", "turned"]
