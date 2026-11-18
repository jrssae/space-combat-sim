"""The depth rasteriser shared by the reference views and the section tool, kept free of PIL so the section checks run
without it (CI's Python has no PIL)."""

from __future__ import annotations

import numpy as np


def rasterize(screen: np.ndarray, width: int, height: int) -> tuple[np.ndarray, np.ndarray]:
    """Depth buffer and triangle index per pixel (-1 where empty) for triangles in pixel coordinates
    ``(n, 3, 3)`` = (x, y, depth). A pixel is covered when its centre is inside; triangles too small to
    cover a centre still mark the pixel under their centroid, so thin parts stay visible."""
    depth = np.full(width * height, np.inf)
    index = np.full(width * height, -1, dtype=np.int64)

    def commit(pix: np.ndarray, z: np.ndarray, tri: np.ndarray) -> None:
        if len(pix) == 0:
            return
        order = np.lexsort((z, pix))
        pix, z, tri = pix[order], z[order], tri[order]
        first = np.ones(len(pix), dtype=bool)
        first[1:] = pix[1:] != pix[:-1]
        pix, z, tri = pix[first], z[first], tri[first]
        nearer = z < depth[pix]
        depth[pix[nearer]] = z[nearer]
        index[pix[nearer]] = tri[nearer]

    n = len(screen)
    x, y, d = screen[:, :, 0], screen[:, :, 1], screen[:, :, 2]
    area = (x[:, 1] - x[:, 0]) * (y[:, 2] - y[:, 0]) - (x[:, 2] - x[:, 0]) * (y[:, 1] - y[:, 0])
    flat = np.abs(area) <= 1e-12
    safe = np.where(flat, 1.0, area)
    # Depth as a plane over the screen: d = d0 + a (x - x0) + b (y - y0).
    da, db = d[:, 1] - d[:, 0], d[:, 2] - d[:, 0]
    a = (da * (y[:, 2] - y[:, 0]) - db * (y[:, 1] - y[:, 0])) / safe
    b = (db * (x[:, 1] - x[:, 0]) - da * (x[:, 2] - x[:, 0])) / safe
    row0 = np.maximum(np.ceil(y.min(axis=1) - 0.5), 0).astype(np.int64)
    row1 = np.minimum(np.floor(y.max(axis=1) - 0.5), height - 1).astype(np.int64)
    rows = np.where(flat, 0, np.maximum(row1 - row0 + 1, 0))
    covered = np.zeros(n)

    # Scanlines: one (triangle, row) pair per pixel row a triangle crosses, then the pixels of each span.
    ends = np.cumsum(rows + np.where(flat, 0.0, 0.5 * np.abs(area)))  # rows plus pixels, to size the batches
    batch = 3_000_000
    start_tri = 0
    while start_tri < n:
        stop_tri = int(np.searchsorted(ends, (ends[start_tri - 1] if start_tri else 0) + batch, side="right"))
        stop_tri = max(stop_tri, start_tri + 1)
        sel = np.arange(start_tri, min(stop_tri, n))
        start_tri = int(sel[-1]) + 1
        counts = rows[sel]
        if counts.sum() == 0:
            continue
        tri = np.repeat(sel, counts)
        first = np.repeat(np.cumsum(counts) - counts, counts)
        row = row0[tri] + (np.arange(len(tri)) - first)
        yc = row + 0.5
        lo = np.full(len(tri), np.inf)
        hi = np.full(len(tri), -np.inf)
        for i, j in ((0, 1), (1, 2), (2, 0)):
            ya, yb, xa, xb = y[tri, i], y[tri, j], x[tri, i], x[tri, j]
            hit = (yc >= np.minimum(ya, yb)) & (yc < np.maximum(ya, yb))
            xe = xa + (yc - ya) * (xb - xa) / np.where(hit, yb - ya, 1.0)
            lo = np.where(hit, np.minimum(lo, xe), lo)
            hi = np.where(hit, np.maximum(hi, xe), hi)
        c0 = np.maximum(np.ceil(lo - 0.5), 0)
        c1 = np.minimum(np.floor(hi - 0.5), width - 1)
        length = np.where(np.isfinite(c0) & np.isfinite(c1), np.maximum(c1 - c0 + 1, 0), 0).astype(np.int64)
        covered += np.bincount(tri, weights=length, minlength=n)
        keep = length > 0
        tri, row, c0, length = tri[keep], row[keep], c0[keep].astype(np.int64), length[keep]
        ptri = np.repeat(tri, length)
        pstart = np.repeat(np.cumsum(length) - length, length)
        col = np.repeat(c0, length) + (np.arange(len(ptri)) - pstart)
        prow = np.repeat(row, length)
        z = d[ptri, 0] + a[ptri] * (col + 0.5 - x[ptri, 0]) + b[ptri] * (prow + 0.5 - y[ptri, 0])
        commit(prow * width + col, z, ptri)

    # Triangles that cover no pixel centre: the pixel under the centroid.
    small = np.flatnonzero(covered == 0)
    cx = np.floor(x[small].mean(axis=1)).astype(np.int64)
    cy = np.floor(y[small].mean(axis=1)).astype(np.int64)
    inside = (cx >= 0) & (cx < width) & (cy >= 0) & (cy < height)
    commit((cy * width + cx)[inside], d[small].mean(axis=1)[inside], small[inside])
    return depth.reshape(height, width), index.reshape(height, width)
