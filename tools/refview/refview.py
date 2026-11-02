"""Orthographic views, silhouettes and cross-sections of a reference STL, scaled to the ship's length (M5-T11).

The maintainer's reference models are fan-made 3D-print files in the untracked ``references/`` folder, each at its own
print scale. This tool reads one, turns it into the ship frame, scales it to the length the design asks for and writes
pictures and numbers into the gitignored ``reports/refs/<name>/``. Ships are described in words from those pictures
(``docs/design-references.md``) and built in code from the words; no geometry, image or number table from here goes
into git or into a generator.

Ship frame: x to starboard, y up, z aft, in metres. The nose is at z = 0; x and y are centred on the bounding box.
(Godot's -Z forward is the same axes; only the origin differs.)

Usage, with the project's venv and isolated mode, so nothing is imported from the folder the model sits in::

    .venv/bin/python3 -I tools/refview/refview.py references/EA_Saturn_4_transport.stl \\
        --name saturn_4_transport --length 100 --right=-x --up=+z --aft=+y

Write the axes with ``=`` (``--right=-x``), or argparse reads ``-x`` as an option. Without ``--right/--up/--aft`` the
file's axes are taken as they are (x right, y up, z aft): the first look, to read the nose and the engines off the
views before choosing the mapping. ``--zrange`` renders a slice of the length larger. The mappings used for the
civilian ships are in ``docs/design-references.md``.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKGROUND = 250
GRID = 222
INK = (20, 20, 20)
CUT = (190, 20, 20)

# name: (view direction from the eye into the scene, image up), in the ship frame.
VIEWS: dict[str, tuple[tuple[float, float, float], tuple[float, float, float]]] = {
    "top": ((0.0, -1.0, 0.0), (1.0, 0.0, 0.0)),  # from above, nose left, starboard up
    "bottom": ((0.0, 1.0, 0.0), (-1.0, 0.0, 0.0)),  # from below, nose left, port up
    "port": ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),  # from the port side, nose left
    "starboard": ((-1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),  # from the starboard side, nose right
    "front": ((0.0, 0.0, 1.0), (0.0, 1.0, 0.0)),  # from ahead, port on the right
    "rear": ((0.0, 0.0, -1.0), (0.0, 1.0, 0.0)),  # from behind, starboard on the right
    "iso_front": ((-1.0, -0.8, 1.0), (0.0, 1.0, 0.0)),  # from above the starboard bow
    "iso_rear": ((1.0, -0.8, -1.0), (0.0, 1.0, 0.0)),  # from above the port quarter
}
AXIS_NAMES = ("x", "y", "z")


# --- STL -------------------------------------------------------------------------------------------------------------
def read_stl(path: Path) -> tuple[np.ndarray, str]:
    """Triangles ``(n, 3, 3)`` of an STL file, binary or ASCII, and which of the two it was."""
    data = Path(path).read_bytes()
    if is_binary_stl(data):
        return parse_binary_stl(data), "binary"
    return parse_ascii_stl(data.decode("ascii", errors="replace")), "ascii"


def is_binary_stl(data: bytes) -> bool:
    """True for a binary STL. Some binary exporters also start their header with ``solid``, so the size is the test."""
    if len(data) >= 84:
        count = struct.unpack_from("<I", data, 80)[0]
        if 84 + 50 * count == len(data):
            return True
    return not data.lstrip()[:5].lower().startswith(b"solid")


def parse_binary_stl(data: bytes) -> np.ndarray:
    count = struct.unpack_from("<I", data, 80)[0]
    count = min(count, (len(data) - 84) // 50)
    record = np.dtype([("normal", "<f4", (3,)), ("v", "<f4", (3, 3)), ("attr", "<u2")])
    return np.frombuffer(data, record, count=count, offset=84)["v"].astype(np.float64)


_VERTEX = re.compile(r"vertex\s+(\S+)\s+(\S+)\s+(\S+)")


def parse_ascii_stl(text: str) -> np.ndarray:
    values = np.array(_VERTEX.findall(text), dtype=np.float64)
    if len(values) % 3:
        raise ValueError(f"ASCII STL has {len(values)} vertices, not a multiple of three")
    return values.reshape(-1, 3, 3)


def write_ascii_stl(path: Path, tris: np.ndarray) -> None:
    """For tests: an ASCII STL of ``tris``."""
    lines = ["solid test"]
    for t in tris:
        lines += [" facet normal 0 0 0", "  outer loop"]
        lines += [f"   vertex {v[0]:.9g} {v[1]:.9g} {v[2]:.9g}" for v in t]
        lines += ["  endloop", " endfacet"]
    lines.append("endsolid test")
    Path(path).write_text("\n".join(lines) + "\n")


def write_binary_stl(path: Path, tris: np.ndarray, header: bytes = b"binary test") -> None:
    """For tests: a binary STL of ``tris`` (the header may start with ``solid`` like some exporters write)."""
    record = np.dtype([("normal", "<f4", (3,)), ("v", "<f4", (3, 3)), ("attr", "<u2")])
    rows = np.zeros(len(tris), record)
    rows["v"] = tris
    Path(path).write_bytes(header.ljust(80, b" ")[:80] + struct.pack("<I", len(tris)) + rows.tobytes())


# --- frame and scale -------------------------------------------------------------------------------------------------
def axis_vector(spec: str) -> np.ndarray:
    """``+x``, ``-y``, ``z`` ... as a unit vector of the file's axes."""
    match = re.fullmatch(r"([+-]?)([xyz])", spec.strip().lower())
    if not match:
        raise ValueError(f"axis {spec!r} is not one of +x -x +y -y +z -z")
    v = np.zeros(3)
    v[AXIS_NAMES.index(match.group(2))] = -1.0 if match.group(1) == "-" else 1.0
    return v


def frame_matrix(right: str, up: str, aft: str) -> np.ndarray:
    """Rows are the file directions of the ship's x (starboard), y (up) and z (aft); a proper rotation."""
    m = np.stack([axis_vector(right), axis_vector(up), axis_vector(aft)])
    det = float(np.linalg.det(m))
    if abs(det) < 0.5:
        raise ValueError("right, up and aft must be three different file axes")
    if det < 0.0:
        raise ValueError("this mapping mirrors the model; flip the sign of one axis")
    return m


def to_ship_frame(tris: np.ndarray, rotation: np.ndarray, length_m: float | None) -> tuple[np.ndarray, float]:
    """Triangles in the ship frame (nose at z = 0, x and y centred on the box) scaled so the z extent is
    ``length_m``; returns them and the metres per file unit (1 when no length is given)."""
    p = tris.reshape(-1, 3) @ rotation.T
    lo, hi = p.min(axis=0), p.max(axis=0)
    scale = 1.0 if length_m is None else float(length_m) / float(hi[2] - lo[2])
    origin = np.array([0.5 * (lo[0] + hi[0]), 0.5 * (lo[1] + hi[1]), lo[2]])
    return ((p - origin) * scale).reshape(-1, 3, 3), scale


def surface_area(tris: np.ndarray) -> float:
    return float(0.5 * np.linalg.norm(np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]), axis=1).sum())


# --- sections --------------------------------------------------------------------------------------------------------
def section_segments(tris: np.ndarray, axis: int, value: float) -> np.ndarray:
    """Where the plane ``coordinate[axis] = value`` cuts the surface: segments ``(m, 2, 3)``."""
    span = float(np.ptp(tris.reshape(-1, 3), axis=0).max()) or 1.0
    s = tris[:, :, axis] - (value + 1e-9 * span)  # a hair off the plane, so no vertex lies on it
    crossing = (s.min(axis=1) < 0.0) & (s.max(axis=1) > 0.0)
    t, d = tris[crossing], s[crossing]
    points, cuts = [], []
    for i, j in ((0, 1), (1, 2), (2, 0)):
        cut = (d[:, i] < 0.0) != (d[:, j] < 0.0)
        w = np.where(cut, d[:, i] / np.where(cut, d[:, i] - d[:, j], 1.0), 0.0)
        points.append(t[:, i] + w[:, None] * (t[:, j] - t[:, i]))
        cuts.append(cut)
    p, c = np.stack(points, axis=1), np.stack(cuts, axis=1)
    first_two = np.argsort(~c, axis=1, kind="stable")[:, :2]  # a crossing triangle has two cut edges
    out = np.take_along_axis(p, first_two[:, :, None], axis=1)
    return out[c.sum(axis=1) == 2]


def extent(points: np.ndarray, axis: int) -> list[float] | None:
    if len(points) == 0:
        return None
    return [round(float(points[..., axis].min()), 3), round(float(points[..., axis].max()), 3)]


# --- connected shells ------------------------------------------------------------------------------------------------
def shells(tris: np.ndarray) -> np.ndarray:
    """A shell label per triangle: triangles sharing a vertex belong together. Print models are often
    several closed shells (a pod, a sphere, a truss), which names the parts."""
    verts = tris.reshape(-1, 3)
    tol = 1e-6 * (float(np.ptp(verts, axis=0).max()) or 1.0)
    _, inverse = np.unique(np.round(verts / tol).astype(np.int64), axis=0, return_inverse=True)
    ids = inverse.reshape(-1, 3)
    parent = np.arange(int(ids.max()) + 1)
    a = np.concatenate([ids[:, 0], ids[:, 1]])
    b = np.concatenate([ids[:, 1], ids[:, 2]])
    while True:
        pa, pb = parent[a], parent[b]
        differ = pa != pb
        if not differ.any():
            break
        np.minimum.at(parent, np.maximum(pa, pb)[differ], np.minimum(pa, pb)[differ])
        while True:
            jumped = parent[parent]
            if np.array_equal(jumped, parent):
                break
            parent = jumped
    return parent[ids[:, 0]]


def shell_table(tris: np.ndarray, labels: np.ndarray, limit: int = 40) -> tuple[list[dict], np.ndarray]:
    """The largest shells by area with their boxes, and a rank per triangle (0 = largest, -1 = not listed)."""
    areas = 0.5 * np.linalg.norm(np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]), axis=1)
    unique, inverse = np.unique(labels, return_inverse=True)
    total = np.bincount(inverse, weights=areas)
    order = np.argsort(-total)
    rank_of = np.full(len(unique), -1)
    rank_of[order[:limit]] = np.arange(min(limit, len(unique)))
    rows = []
    for rank, u in enumerate(order[:limit]):
        pts = tris[inverse == u].reshape(-1, 3)
        lo, hi = pts.min(axis=0), pts.max(axis=0)
        rows.append(
            {
                "rank": rank,
                "triangles": int((inverse == u).sum()),
                "area_m2": round(float(total[u]), 2),
                "min": [round(float(v), 2) for v in lo],
                "max": [round(float(v), 2) for v in hi],
                "size": [round(float(v), 2) for v in hi - lo],
                "centre": [round(float(v), 2) for v in 0.5 * (lo + hi)],
            }
        )
    return rows, rank_of[inverse]


# --- rasterising -----------------------------------------------------------------------------------------------------
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


# --- canvases --------------------------------------------------------------------------------------------------------
def _font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow without FreeType sizing
        return ImageFont.load_default()


def nice_step(span: float, max_ticks: int) -> float:
    for step in (0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 25, 50, 100, 200, 500, 1000):
        if span / step <= max_ticks:
            return float(step)
    return 10.0 ** math.ceil(math.log10(span / max_ticks))


@dataclass
class Canvas:
    """An orthographic view of the ship frame on an image, with the margins for ticks and labels."""

    forward: np.ndarray
    up: np.ndarray
    ppm: float
    u_range: tuple[float, float]
    v_range: tuple[float, float]
    margin: tuple[int, int, int, int] = (70, 44, 24, 56)  # left, top, right, bottom
    right: np.ndarray = field(init=False)

    def __post_init__(self) -> None:
        f = np.asarray(self.forward, dtype=float)
        f = f / np.linalg.norm(f)
        u = np.asarray(self.up, dtype=float)
        u = u - f * float(u @ f)
        self.forward, self.up = f, u / np.linalg.norm(u)
        self.right = np.cross(self.forward, self.up)

    @classmethod
    def fit(cls, forward, up, points: np.ndarray, ppm: float, pad_m: float, margin=(70, 44, 24, 56)) -> Canvas:
        c = cls(np.asarray(forward, float), np.asarray(up, float), ppm, (0.0, 1.0), (0.0, 1.0), margin)
        uv = points.reshape(-1, 3) @ np.stack([c.right, c.up]).T
        c.u_range = (float(uv[:, 0].min()) - pad_m, float(uv[:, 0].max()) + pad_m)
        c.v_range = (float(uv[:, 1].min()) - pad_m, float(uv[:, 1].max()) + pad_m)
        return c

    @property
    def size(self) -> tuple[int, int]:
        left, top, right, bottom = self.margin
        w = int(math.ceil((self.u_range[1] - self.u_range[0]) * self.ppm)) + left + right
        h = int(math.ceil((self.v_range[1] - self.v_range[0]) * self.ppm)) + top + bottom
        return w, h

    def project(self, points: np.ndarray) -> np.ndarray:
        """Pixel x, y and depth of ship-frame points (any leading shape)."""
        p = np.asarray(points, dtype=float)
        u, v, d = p @ self.right, p @ self.up, p @ self.forward
        left, top = self.margin[0], self.margin[1]
        return np.stack([left + (u - self.u_range[0]) * self.ppm, top + (self.v_range[1] - v) * self.ppm, d], axis=-1)

    def axis_label(self, direction: np.ndarray) -> tuple[int, float] | None:
        """(ship axis, sign) when an image axis runs along a ship axis, else None (oblique views)."""
        k = int(np.argmax(np.abs(direction)))
        if abs(abs(float(direction[k])) - 1.0) > 1e-6:
            return None
        return k, float(np.sign(direction[k]))

    def background(self, grid: bool = True) -> Image.Image:
        img = Image.new("RGB", self.size, (BACKGROUND,) * 3)
        if grid:
            self._grid(ImageDraw.Draw(img), lines=True)
        return img

    def _ticks(self, direction: np.ndarray, lo: float, hi: float) -> list[tuple[float, float]]:
        """(coordinate value, image-axis value) of the metre ticks along one image axis."""
        label = self.axis_label(direction)
        if label is None:
            return []
        _, sign = label
        step = nice_step(hi - lo, 24)
        a, b = sorted((sign * lo, sign * hi))
        values = np.arange(math.ceil(a / step) * step, b + 1e-9, step)
        return [(float(c), float(sign * c)) for c in values]

    def _grid(self, draw: ImageDraw.ImageDraw, lines: bool) -> None:
        w, h = self.size
        left, top, right, bottom = self.margin
        font = _font(12)
        for coord, u in self._ticks(self.right, *self.u_range):
            x = left + (u - self.u_range[0]) * self.ppm
            if lines:
                draw.line([(x, top), (x, h - bottom)], fill=(GRID,) * 3)
            else:
                draw.line([(x, h - bottom), (x, h - bottom + 5)], fill=INK)
                draw.text((x, h - bottom + 7), f"{coord:g}", fill=INK, font=font, anchor="mt")
        for coord, v in self._ticks(self.up, *self.v_range):
            y = top + (self.v_range[1] - v) * self.ppm
            if lines:
                draw.line([(left, y), (w - right, y)], fill=(GRID,) * 3)
            else:
                draw.line([(left - 5, y), (left, y)], fill=INK)
                draw.text((left - 7, y), f"{coord:g}", fill=INK, font=font, anchor="rm")

    def decorate(self, img: Image.Image, title: str) -> Image.Image:
        """Ticks, axis names, title and a scale bar in metres."""
        draw = ImageDraw.Draw(img)
        w, h = self.size
        left, top, right, bottom = self.margin
        self._grid(draw, lines=False)
        font = _font(13)
        draw.text((left, 8), title, fill=INK, font=font)
        names = {0: "x (starboard +)", 1: "y (up +)", 2: "z (m from nose, aft +)"}
        for direction, where, anchor in ((self.right, (w - right, h - 18), "rs"), (self.up, (4, top - 8), "ls")):
            label = self.axis_label(direction)
            if label is not None:
                axis, sign = label
                arrow = "" if sign > 0 else "  (decreasing this way)"
                draw.text(where, names[axis] + arrow, fill=INK, font=font, anchor=anchor)
        span = self.u_range[1] - self.u_range[0]
        bar_m = nice_step(span / 5.0, 1)
        x0, y0 = left, h - 18
        segs = 5
        for i in range(segs):
            xa = x0 + i * bar_m * self.ppm / segs
            xb = x0 + (i + 1) * bar_m * self.ppm / segs
            draw.rectangle([xa, y0 - 5, xb, y0], fill=INK if i % 2 == 0 else (255, 255, 255), outline=INK)
        draw.text((x0 + bar_m * self.ppm + 6, y0 - 3), f"{bar_m:g} m", fill=INK, font=font, anchor="lm")
        return img


def shade(canvas: Canvas, tris: np.ndarray, depth: np.ndarray, index: np.ndarray) -> np.ndarray:
    """Grey Lambert shading from the upper left with dark lines on creases and steps, so parts read apart."""
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-30)
    n_view = np.stack([n @ canvas.right, n @ canvas.up, n @ -canvas.forward], axis=1)
    n_view *= np.where(n_view[:, 2:3] < 0.0, -1.0, 1.0)  # face the eye whatever the winding
    light = np.array([-0.45, 0.6, 0.66])
    light /= np.linalg.norm(light)
    covered = index >= 0
    normals = np.zeros(index.shape + (3,))
    normals[covered] = n_view[index[covered]]
    value = np.full(index.shape, float(BACKGROUND))
    lambert = np.clip(normals @ light, 0.0, 1.0)
    value[covered] = 55.0 + 180.0 * (0.22 + 0.78 * lambert[covered])
    crease = np.zeros(index.shape, dtype=bool)
    dz = np.where(covered, depth, np.nan)
    for axis in (0, 1):
        a = [slice(None), slice(None)]
        b = [slice(None), slice(None)]
        a[axis], b[axis] = slice(1, None), slice(None, -1)
        cos = np.sum(normals[tuple(a)] * normals[tuple(b)], axis=-1)
        # A step: neighbours on different triangles further apart in depth than a 76 degree slope.
        other = index[tuple(a)] != index[tuple(b)]
        step = other & (np.abs(dz[tuple(a)] - dz[tuple(b)]) > 4.0 / canvas.ppm)
        edge = covered[tuple(a)] != covered[tuple(b)]
        both = covered[tuple(a)] & covered[tuple(b)]
        mark = edge | (both & ((cos < math.cos(math.radians(32.0))) | step))
        crease[tuple(a)] |= mark
    value[crease] = 40.0
    return value.astype(np.uint8)


# --- outputs ---------------------------------------------------------------------------------------------------------
@dataclass
class Model:
    tris: np.ndarray  # ship frame, metres
    length: float

    @property
    def points(self) -> np.ndarray:
        return self.tris.reshape(-1, 3)


def render(model: Model, name: str, ppm: float, pad: float) -> tuple[Canvas, np.ndarray, np.ndarray]:
    forward, up = VIEWS[name]
    canvas = Canvas.fit(forward, up, model.points, ppm, pad)
    w, h = canvas.size
    depth, index = rasterize(canvas.project(model.tris), w, h)
    return canvas, depth, index


def write_view(model: Model, name: str, ppm: float, pad: float, out: Path, title: str) -> tuple[Canvas, np.ndarray]:
    canvas, depth, index = render(model, name, ppm, pad)
    grey = shade(canvas, model.tris, depth, index)
    img = canvas.background()
    arr = np.asarray(img).copy()
    covered = index >= 0
    arr[covered] = np.repeat(grey[covered][:, None], 3, axis=1)
    edge = (grey == 40) & ~covered
    arr[edge] = 40
    img = canvas.decorate(Image.fromarray(arr), f"{title}: {name}")
    img.save(out / f"view_{name}.png")
    sil = canvas.background()
    arr = np.asarray(sil).copy()
    arr[covered] = 0
    canvas.decorate(Image.fromarray(arr), f"{title}: silhouette {name}").save(out / f"silhouette_{name}.png")
    return canvas, covered


def profile(canvas: Canvas, covered: np.ndarray, length: float, steps: int = 100) -> list[list[float]]:
    """The silhouette's extent across the image at every 1 % of the length: [z, low, high] in metres."""
    left, top = canvas.margin[0], canvas.margin[1]
    rows = np.flatnonzero
    out = []
    for k in range(steps + 1):
        z = length * k / steps
        u = z if canvas.right[2] > 0 else -z
        col = int(round(left + (u - canvas.u_range[0]) * canvas.ppm - 0.5))
        col = min(max(col, 0), covered.shape[1] - 1)
        r = rows(covered[:, col])
        if len(r) == 0:
            out.append([round(z, 2), None, None])
            continue
        hi = canvas.v_range[1] - (r.min() + 0.5 - top) / canvas.ppm
        lo = canvas.v_range[1] - (r.max() + 0.5 - top) / canvas.ppm
        out.append([round(z, 2), round(float(lo), 2), round(float(hi), 2)])
    return out


def draw_segments(img: Image.Image, canvas: Canvas, segments: np.ndarray, width: int = 2) -> None:
    draw = ImageDraw.Draw(img)
    for a, b in canvas.project(segments)[..., :2]:
        draw.line([tuple(a), tuple(b)], fill=CUT, width=width)


def write_cut(model: Model, axis: int, value: float, view: str, ppm: float, pad: float, out: Path, title: str) -> dict:
    """A plane cut along the length (x = c or y = c) over the matching view's faint silhouette."""
    canvas, depth, index = render(model, view, ppm, pad)
    img = canvas.background()
    arr = np.asarray(img).copy()
    arr[index >= 0] = 205
    img = Image.fromarray(arr)
    segs = section_segments(model.tris, axis, value)
    draw_segments(img, canvas, segs)
    label = f"{AXIS_NAMES[axis]} = {value:g} m"
    canvas.decorate(img, f"{title}: cut {label} (red) over the {view} silhouette").save(
        out / f"cut_{AXIS_NAMES[axis]}_{value:g}.png"
    )
    pts = segs.reshape(-1, 3)
    return {"axis": AXIS_NAMES[axis], "value": value, "segments": len(segs), "z": extent(pts, 2), "x": extent(pts, 0), "y": extent(pts, 1)}


def write_sections(model: Model, stations: list[float], out: Path, title: str, columns: int = 4) -> list[dict]:
    """A sheet of cross-sections at the stations (seen from behind, starboard right) on one scale."""
    pts = model.points
    span = max(float(np.ptp(pts[:, 0])), float(np.ptp(pts[:, 1])), 1e-6)
    panel = 300
    ppm = (panel - 20) / span
    forward, up = VIEWS["rear"]
    canvas = Canvas.fit(forward, up, pts, ppm, 0.02 * span, margin=(10, 26, 10, 10))
    w, h = canvas.size
    _, index = rasterize(canvas.project(model.tris), w, h)
    ghost = index >= 0
    rows_n = math.ceil(len(stations) / columns)
    sheet = Image.new("RGB", (columns * w, rows_n * h + 30), (255, 255, 255))
    ImageDraw.Draw(sheet).text((8, 8), f"{title}: cross-sections seen from behind (starboard right), one scale; grey = rear silhouette", fill=INK, font=_font(14))
    font = _font(12)
    records = []
    for i, z in enumerate(stations):
        segs = section_segments(model.tris, 2, z)
        tile = canvas.background(grid=False)
        arr = np.asarray(tile).copy()
        arr[ghost] = 228
        tile = Image.fromarray(arr)
        draw = ImageDraw.Draw(tile)
        c = canvas.project(np.zeros(3))
        draw.line([(c[0] - 6, c[1]), (c[0] + 6, c[1])], fill=(120, 120, 120))
        draw.line([(c[0], c[1] - 6), (c[0], c[1] + 6)], fill=(120, 120, 120))
        draw_segments(tile, canvas, segs)
        p = segs.reshape(-1, 3)
        xr, yr = extent(p, 0), extent(p, 1)
        size = "empty" if xr is None else f"w {xr[1] - xr[0]:.1f}  h {yr[1] - yr[0]:.1f} m"
        draw.text((6, 6), f"z {z:.1f} m ({100 * z / model.length:.0f} %)  {size}", fill=INK, font=font)
        draw.rectangle([0, 0, w - 1, h - 1], outline=(180, 180, 180))
        sheet.paste(tile, ((i % columns) * w, 30 + (i // columns) * h))
        records.append({"z": round(z, 2), "fraction": round(z / model.length, 4), "segments": len(segs), "x": xr, "y": yr})
    sheet.save(out / "sections.png")
    return records


PALETTE = [
    (230, 25, 75), (60, 180, 75), (0, 130, 200), (245, 130, 48), (145, 30, 180), (70, 200, 200), (240, 50, 230),
    (170, 200, 40), (250, 160, 170), (0, 128, 128), (170, 110, 40), (128, 0, 0), (100, 200, 140), (128, 128, 0),
    (255, 200, 120), (0, 0, 128), (200, 160, 240), (90, 90, 90), (255, 225, 25), (40, 40, 160),
]


def write_shells(model: Model, ppm: float, pad: float, out: Path, title: str) -> list[dict]:
    """The largest separate shells, coloured and numbered on the top and iso views."""
    rows, rank = shell_table(model.tris, shells(model.tris))
    for name in ("top", "iso_front", "port"):
        canvas, depth, index = render(model, name, ppm, pad)
        grey = shade(canvas, model.tris, depth, index).astype(float) / 255.0
        img = canvas.background()
        arr = np.asarray(img).astype(float)
        covered = index >= 0
        r = rank[index[covered]]
        colour = np.array([PALETTE[k % len(PALETTE)] if k >= 0 else (200, 200, 200) for k in range(-1, len(PALETTE))])
        base = colour[np.where(r < len(PALETTE), r + 1, 0)]
        arr[covered] = base * grey[covered][:, None]
        img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
        draw = ImageDraw.Draw(img)
        font = _font(13)
        for row in rows[: len(PALETTE)]:
            x, y, _ = canvas.project(np.array(row["centre"]))
            draw.text((x, y), str(row["rank"]), fill=(0, 0, 0), font=font, anchor="mm", stroke_width=2, stroke_fill=(255, 255, 255))
        canvas.decorate(img, f"{title}: separate shells by area rank ({name})").save(out / f"shells_{name}.png")
    return rows


def default_out(name: str) -> Path:
    return REPO_ROOT / "reports" / "refs" / name


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("stl", type=Path)
    ap.add_argument("--name", required=True, help="output folder under reports/refs/")
    ap.add_argument("--length", type=float, default=None, help="metres along the aft axis (default: file units)")
    ap.add_argument("--right", default="+x", help="file axis pointing to starboard, e.g. -y")
    ap.add_argument("--up", default="+y", help="file axis pointing up")
    ap.add_argument("--aft", default="+z", help="file axis pointing from the nose to the engines")
    ap.add_argument("--px", type=int, default=1600, help="pixels along the ship's largest dimension")
    ap.add_argument("--stations", type=int, default=24, help="cross-sections along the length")
    ap.add_argument("--xcuts", default="0", help="comma-separated x (m) of cuts along the length")
    ap.add_argument("--ycuts", default="0", help="comma-separated y (m) of cuts along the length")
    ap.add_argument("--zrange", nargs=2, type=float, default=None, help="render only z0..z1 (m), larger")
    ap.add_argument("--no-shells", action="store_true", help="skip the separate-shell analysis")
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args(argv)

    raw, fmt = read_stl(args.stl)
    rotation = frame_matrix(args.right, args.up, args.aft)
    tris, scale = to_ship_frame(raw, rotation, args.length)
    pts = tris.reshape(-1, 3)
    length = float(np.ptp(pts[:, 2]))
    out = args.out or default_out(args.name)
    title = args.name
    if args.zrange is not None:
        z0, z1 = args.zrange
        keep = (tris[:, :, 2].max(axis=1) >= z0) & (tris[:, :, 2].min(axis=1) <= z1)
        tris = tris[keep]
        out = out / f"zoom_{z0:g}_{z1:g}"
        title = f"{args.name} z {z0:g}..{z1:g} m"
    out.mkdir(parents=True, exist_ok=True)
    model = Model(tris, length)
    view_pts = model.points
    largest = float(np.ptp(view_pts, axis=0).max())
    ppm = args.px / largest
    pad = 0.03 * largest

    canvases = {}
    for name in VIEWS:
        canvases[name] = write_view(model, name, ppm, pad, out, title)
    z_lo, z_hi = float(view_pts[:, 2].min()), float(view_pts[:, 2].max())
    stations = [z_lo + (z_hi - z_lo) * (k + 0.5) / args.stations for k in range(args.stations)]
    sections = write_sections(model, stations, out, title)
    cuts = []
    for value in (float(v) for v in args.xcuts.split(",") if v.strip()):
        cuts.append(write_cut(model, 0, value, "port", ppm, pad, out, title))
    for value in (float(v) for v in args.ycuts.split(",") if v.strip()):
        cuts.append(write_cut(model, 1, value, "top", ppm, pad, out, title))
    shell_rows = [] if args.no_shells else write_shells(model, ppm, pad, out, title)

    lo, hi = view_pts.min(axis=0), view_pts.max(axis=0)
    measurements = {
        "source": args.stl.name,
        "format": fmt,
        "triangles": int(len(raw)),
        "file_extent_units": [round(float(v), 4) for v in np.ptp(raw.reshape(-1, 3), axis=0)],
        "mapping": {"right": args.right, "up": args.up, "aft": args.aft},
        "metres_per_unit": round(scale, 6),
        "frame": "x starboard, y up, z aft from the nose (z = 0); x and y centred on the whole model's box; metres",
        "zrange": args.zrange,
        "dimensions_m": {"length": round(length, 2), "span": round(float(hi[0] - lo[0]), 2), "height": round(float(hi[1] - lo[1]), 2)},
        "bbox_m": {"min": [round(float(v), 2) for v in lo], "max": [round(float(v), 2) for v in hi]},
        "surface_area_m2": round(surface_area(tris), 1),
        "profiles": {
            "top_x_by_z": profile(*canvases["top"], length),
            "side_y_by_z": profile(*canvases["port"], length),
        },
        "sections": sections,
        "cuts": cuts,
        "shells": shell_rows,
    }
    (out / "measurements.json").write_text(json.dumps(measurements, indent=1) + "\n")
    d = measurements["dimensions_m"]
    print(f"{args.stl.name} ({fmt}, {len(raw)} triangles): {d['length']} x {d['span']} x {d['height']} m "
          f"(length x span x height), {scale:.5g} m per unit, area {measurements['surface_area_m2']} m2 -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
