"""Atlas-space buffers (M4-T30a): what every texel of a hull's texture atlas knows about the surface it covers.

Each triangle is rasterised in texture space with a little conservative padding, so even a sliver marks the texels it touches and a
triangle smaller than a texel still marks one. The buffers hold the world position, the smooth normal, the part, material and chart
ids and the distance to the nearest sharp mesh edge; every texture map is then a function of these buffers. A dilation afterwards
copies the buffers into the gutters so filtering and mipmaps read paint, not black.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from .geometry import Mesh

PAD_PX = 0.6  # conservative padding, texels: a texel whose centre is this close to a triangle belongs to it
SHARP_ANGLE_DEG = 35.0


@dataclass
class AtlasBuffers:
    size: int
    mask: np.ndarray  # covered by a triangle
    filled: np.ndarray  # covered or dilated into
    position: np.ndarray
    normal: np.ndarray
    part: np.ndarray
    material: np.ndarray
    chart: np.ndarray
    edge_distance: np.ndarray
    overlaps: int = 0

    @staticmethod
    def empty(size: int) -> AtlasBuffers:
        return AtlasBuffers(
            size,
            np.zeros((size, size), dtype=bool),
            np.zeros((size, size), dtype=bool),
            np.zeros((size, size, 3), dtype=np.float64),
            np.zeros((size, size, 3), dtype=np.float64),
            np.full((size, size), -1, dtype=np.int32),
            np.full((size, size), -1, dtype=np.int32),
            np.full((size, size), -1, dtype=np.int32),
            np.full((size, size), np.inf, dtype=np.float64),
        )


def sharp_edges(mesh: Mesh, angle_deg: float = SHARP_ANGLE_DEG) -> np.ndarray:
    """``(faces, 3)``: whether the edge from corner k to k + 1 is a crease over ``angle_deg`` or an open rim (by vertex position)."""
    if mesh.face_count == 0:
        return np.zeros((0, 3), dtype=bool)
    rounded = np.round(mesh.vertices, 5)
    _, by_position = np.unique(rounded, axis=0, return_inverse=True)
    by_position = by_position.reshape(-1)
    f = by_position[mesh.faces]
    edges = np.stack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]], axis=1).reshape(-1, 2)
    edges.sort(axis=1)
    keys = edges[:, 0] * (int(by_position.max()) + 2) + edges[:, 1]
    unique, inverse, counts = np.unique(keys, return_inverse=True, return_counts=True)
    inverse = inverse.reshape(-1)
    normals = mesh.face_normals()
    face_of_slot = np.repeat(np.arange(mesh.face_count), 3)
    # The sum of the normals of the faces on an edge: two parallel faces give length 2, a crease less.
    summed = np.zeros((len(unique), 3))
    np.add.at(summed, inverse, normals[face_of_slot])
    cos_half = math.cos(math.radians(angle_deg) / 2.0)
    two_faces = counts == 2
    sharp_edge = ~two_faces | (np.linalg.norm(summed, axis=1) < 2.0 * cos_half)
    return sharp_edge[inverse].reshape(-1, 3)


def _segment_distance(p: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    ab = b - a
    length2 = float(ab @ ab)
    if length2 < 1e-18:
        return np.linalg.norm(p - a, axis=1)
    t = np.clip(((p - a) @ ab) / length2, 0.0, 1.0)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


def rasterize(
    size: int,
    uv01: np.ndarray,
    corners: np.ndarray,
    corner_normals: np.ndarray,
    face_part: np.ndarray,
    face_material: np.ndarray,
    face_chart: np.ndarray,
    sharp: np.ndarray,
) -> AtlasBuffers:
    """Rasterise every triangle into the buffers (``uv01`` ``(F, 3, 2)``, u right, v down, both 0..1)."""
    buffers = AtlasBuffers.empty(size)
    uv = np.asarray(uv01, dtype=float) * float(size)
    corners = np.asarray(corners, dtype=float)
    corner_normals = np.asarray(corner_normals, dtype=float)
    sharp = np.asarray(sharp, dtype=bool)
    overlaps = 0
    for t in range(len(uv)):
        p0, p1, p2 = uv[t]
        area = (p1[0] - p0[0]) * (p2[1] - p0[1]) - (p2[0] - p0[0]) * (p1[1] - p0[1])
        lo = np.floor(uv[t].min(axis=0) - PAD_PX).astype(int)
        hi = np.ceil(uv[t].max(axis=0) + PAD_PX).astype(int)
        lo = np.clip(lo, 0, size - 1)
        hi = np.clip(hi, 0, size - 1)
        xs = np.arange(lo[0], hi[0] + 1)
        ys = np.arange(lo[1], hi[1] + 1)
        gx, gy = np.meshgrid(xs + 0.5, ys + 0.5)
        if abs(area) < 1e-9:
            inside = np.zeros(gx.shape, dtype=bool)
            w = np.full(gx.shape + (3,), 1.0 / 3.0)
        else:
            sign = 1.0 if area > 0 else -1.0
            e = np.empty(gx.shape + (3,))
            lengths = np.empty(3)
            for k, (a, b) in enumerate(((p1, p2), (p2, p0), (p0, p1))):
                e[..., k] = ((b[0] - a[0]) * (gy - a[1]) - (b[1] - a[1]) * (gx - a[0])) * sign
                lengths[k] = max(math.hypot(b[0] - a[0], b[1] - a[1]), 1e-9)
            inside = np.all(e / lengths >= -PAD_PX, axis=-1)
            w = np.clip(e / abs(area), 0.0, 1.0)
            w /= np.maximum(w.sum(axis=-1, keepdims=True), 1e-12)
        if not inside.any():
            # Too small for any texel centre: the texel under its centroid is its own.
            c = np.clip(np.floor(uv[t].mean(axis=0)).astype(int), 0, size - 1)
            inside = np.zeros(gx.shape, dtype=bool)
            iy, ix = c[1] - lo[1], c[0] - lo[0]
            if 0 <= iy < inside.shape[0] and 0 <= ix < inside.shape[1]:
                inside[iy, ix] = True
                w[iy, ix] = 1.0 / 3.0
            else:
                continue
        rows, cols = np.nonzero(inside)
        py, px = ys[rows], xs[cols]
        bary = w[rows, cols]
        position = bary @ corners[t]
        normal = bary @ corner_normals[t]
        norm = np.linalg.norm(normal, axis=1, keepdims=True)
        normal = normal / np.where(norm == 0.0, 1.0, norm)
        previous = buffers.chart[py, px]
        overlaps += int(np.count_nonzero((previous >= 0) & (previous != face_chart[t])))
        buffers.mask[py, px] = True
        buffers.position[py, px] = position
        buffers.normal[py, px] = normal
        buffers.part[py, px] = face_part[t]
        buffers.material[py, px] = face_material[t]
        buffers.chart[py, px] = face_chart[t]
        distance = buffers.edge_distance[py, px]
        for k in range(3):
            if sharp[t, k]:
                distance = np.minimum(distance, _segment_distance(position, corners[t, k], corners[t, (k + 1) % 3]))
        buffers.edge_distance[py, px] = distance
    buffers.filled = buffers.mask.copy()
    buffers.overlaps = overlaps
    return buffers


def dilate(buffers: AtlasBuffers, passes: int) -> None:
    """Copy every buffer into the empty texels next to filled ones, ``passes`` texels deep (the gutters)."""
    shifts = ((0, 1), (0, -1), (1, 0), (-1, 0))
    arrays = (buffers.position, buffers.normal, buffers.part, buffers.material, buffers.chart, buffers.edge_distance)
    for _ in range(passes):
        filled = buffers.filled.copy()
        for dy, dx in shifts:
            source = np.roll(filled, (dy, dx), axis=(0, 1))
            if dy == 1:
                source[0, :] = False
            elif dy == -1:
                source[-1, :] = False
            if dx == 1:
                source[:, 0] = False
            elif dx == -1:
                source[:, -1] = False
            take = source & ~buffers.filled
            if not take.any():
                continue
            for array in arrays:
                array[take] = np.roll(array, (dy, dx), axis=(0, 1))[take]
            buffers.filled |= take


__all__ = ["AtlasBuffers", "dilate", "rasterize", "sharp_edges"]
