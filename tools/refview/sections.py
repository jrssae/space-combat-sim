"""Section compare (M7-T21): a part's cross-section through the reference STL against the same section through the build.

The silhouette compare (``compare.py``) judges a whole asset from three sides, so a part can be the wrong shape inside its outline and
still pass (the Cobra arm as a flat slab, a roofless cargo bay). Here each part is cut at fixed planes and the filled sections are
compared pixel by pixel inside a window round the part: the intersection over union of the two, ``IoU >= 0.90`` to pass.

A section is filled by the nonzero winding rule from the cut's segments, each oriented by its triangle's outward normal, so a model
built of overlapping closed parts fills as their union and a hole (a tunnel, a bay) stays empty. A reference STL that is not watertight
leaks stripes of "inside" along the rows that run through its missing faces, so a row that does not close defers to the column (M10-T62).

A ``relief`` plane (z cuts only) reads the face as seen from the bow instead: a pixel is solid where the first surface met looking
aft lies at or before the plane. It serves a reference whose shells overlap with mixed winding (the STL's bow, M7-T25), where the
nonzero fill calls an open mouth solid; it sees only what faces the bow, which is what a bay's mouth is judged by.
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
    room the reference leaves solid, or the reverse); with ``relief`` (z cuts only) the section is what the bow sees in front of
    the plane."""

    name: str
    axis: int
    value: float
    window: tuple[float, float, float, float]
    turn_deg: float = 0.0
    outline: bool = False
    relief: bool = False


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


def relief_mask(tris: np.ndarray, plane: SectionPlane, pixel_m: float) -> np.ndarray:
    """What the bow sees in front of a z plane, in its window: solid where the nearest surface looking aft is at or before it."""
    from .raster import rasterize  # noqa: PLC0415 - the renderer's rasteriser, only for relief planes

    if plane.axis != 2:
        raise ValueError(f"{plane.name}: a relief plane cuts across z")
    u0, u1, v0, v1 = plane.window
    cols = int(round((u1 - u0) / pixel_m))
    rows = int(round((v1 - v0) / pixel_m))
    t = turned(np.asarray(tris, dtype=float).reshape(-1, 3, 3), plane.turn_deg)
    t = t[t[:, :, 2].min(axis=1) <= plane.value]
    # Faces seen edge-on (walls along the view) cover nothing; the rasteriser would still mark a pixel under each.
    e1, e2 = t[:, 1, :2] - t[:, 0, :2], t[:, 2, :2] - t[:, 0, :2]
    t = t[np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]) > 1e-9]
    if len(t) == 0:
        return np.zeros((rows, cols), dtype=bool)
    screen = np.empty_like(t)
    screen[:, :, 0] = (t[:, :, 0] - u0) / pixel_m
    screen[:, :, 1] = (v1 - t[:, :, 1]) / pixel_m
    screen[:, :, 2] = t[:, :, 2]
    depth, _ = rasterize(screen, cols, rows)
    return depth <= plane.value


def _scan(segs: np.ndarray, u0: float, v1: float, cols: int, rows: int, pixel_m: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Per pixel: is the winding of the crossings to its right nonzero, and the same for its left; per row: does the row run through
    a closed outline (its crossings cancel). On a closed row the two agree and are the winding; a row through a gap in an open shell
    does not close, and the two can differ."""
    us = u0 + (np.arange(cols) + 0.5) * pixel_m
    right = np.zeros((rows, cols), dtype=bool)
    left = np.zeros((rows, cols), dtype=bool)
    closed = np.ones(rows, dtype=bool)
    if len(segs) == 0:
        return right, left, closed
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
        # The signed crossings to each column's right; the ones to its left are the rest.
        to_right = np.concatenate([np.cumsum(s[::-1])[::-1], [0]])[np.searchsorted(uc, us, side="right")]
        right[r] = to_right != 0
        left[r] = (s.sum() - to_right) != 0
        closed[r] = s.sum() == 0
    return right, left, closed


def section_mask(tris: np.ndarray, plane: SectionPlane, pixel_m: float) -> np.ndarray:
    """The filled section in the plane's window, rows from the window's top (v1) down (or the relief a ``relief`` plane asks for).

    A pixel is solid by the nonzero winding of the cut counted along its row, or along its column where the row does not close (a
    gap in an open shell: the count there is a stripe of 'inside' through the missing face). Where neither closes, two of the four
    directions (right, left, up, down) must call it solid. On a watertight mesh every line closes, so this is the plain nonzero
    rule and a model built of overlapping closed parts fills as their union with a hole left empty."""
    if plane.relief:
        return relief_mask(tris, plane, pixel_m)
    u0, u1, v0, v1 = plane.window
    # A hair off the plane, so a plane laid on a row of the mesh's corners still cuts every face through it.
    segs = cut_segments(turned(tris, plane.turn_deg), plane.axis, plane.value + PLANE_NUDGE_M)
    cols = int(round((u1 - u0) / pixel_m))
    rows = int(round((v1 - v0) / pixel_m))
    if len(segs) == 0:
        return np.zeros((rows, cols), dtype=bool)
    right, left, row_closed = _scan(segs, u0, v1, cols, rows, pixel_m)
    # Above and below: the same scan with u and v swapped, whose rows run along u from u1 down and columns along v from v0 up.
    swapped_up, swapped_down, column_closed = _scan(segs[:, :, ::-1], v0, u1, rows, cols, pixel_m)
    up, down = swapped_up[::-1, ::-1].T, swapped_down[::-1, ::-1].T
    by_row, by_column = row_closed[:, None], column_closed[::-1][None, :]
    votes = right.astype(np.int8) + left + up + down
    return np.where(by_row, right, np.where(by_column, up, votes >= 3))


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


__all__ = ["PASS_IOU", "SectionPlane", "SectionScore", "cut_segments", "fill_holes", "overlay", "relief_mask", "score_all", "section_mask", "section_score",
           "turned"]
