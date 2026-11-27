"""A capital piece's far mesh (M10-T89): a light stand-in the game draws once the hull is about a hundred pixels long or less.

Godot's import levels of detail cannot thin a hull made of many small boxes (each box keeps its twelve triangles), so a far
Omega still drew 16 to 31 k triangles at 15 km. The far mesh is made from the finished piece alone, so every capital gets one
without its generator knowing:

* **Shape.** The piece's triangles are sampled densely and laid on a grid; the grid's outside is flooded in from its border, so
  everything the flood cannot reach is solid (boxes inside boxes, closed rooms). A distance field signed by that flood, and next
  to the skin by the nearest visible sample's facing, is cut into a watertight skin (``isosurface.extract``) and thinned to the
  class's budget (``decimate``), which keeps the outline (top, side and front views of the far and the full mesh agree, IoU).
* **Paint.** The skin gets an atlas of its own, a few metres a texel, its colour, ORM and glow the mean of what the full hull's
  maps show near each texel on surfaces facing the same way (so a plate's two sides keep their own colours). Only surfaces seen
  from outside count. Its normal map is flat: the skin is drawn faceted.

The piece's manifest entry lists the far mesh in its ``lods`` (the textured mesh's contract): the file, its maps, its triangles
and where the game swaps it in (``from_m`` and ``margin_m``).
"""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from .budgets import CLASS_BUDGETS
from .color import linear_to_srgb, srgb_to_linear
from .decimate import decimate
from .geometry import Material, Mesh
from .glb import GlbPrimitive, read_glb, write_glb
from .image import read_png, write_png
from .isosurface import extract
from .raster import dilate, rasterize
from .silhouette import _fill
from .textured_mesh import MAP_KEYS, import_sidecar
from .uv_atlas import charts_of, pack

FAR_SHARE = 0.03  # of the class's triangle budget: an Omega-size capital (100 k) draws about 3 k far away
FAR_FROM_LENGTHS = 7.9  # the swap, in hull lengths: an Omega (1 714 m) fades over 12.2 to 14.9 km, about 100 px long on 1 080 lines
FAR_MARGIN_SHARE = 0.1  # the cross-fade either side of the swap, a share of its distance
MIN_PIECE_TRIANGLES = 200  # a small rotating piece still keeps its shape
GRID_CELLS = 384  # grid cells along the hull's length
OUTLINE_MIN = 0.95  # the outline IoU a far mesh keeps in the top, side and front views
BUDGET_STEPS = (1.0, 1.25, 1.5, 2.0)  # a hull whose outline needs more than its class's far triangles gets up to twice them
SAMPLES_PER_CELL = 2  # surface samples along a cell's side
MAX_STEPS = 240  # the most samples along one triangle's longest edge
ATLAS_PX = 1024  # the most a far atlas takes; a smaller piece's is smaller, near FAR_TEXEL_M a texel
MIN_ATLAS_PX = 128
FAR_TEXEL_M = 2.5  # under a pixel's 20th at the swap
ATLAS_FILL = 0.55  # the share of the atlas the charts fill, for the first guess at its texel
CHART_ANGLE_DEG = 66.0  # faces this close to parallel share a chart: few big charts, so the gutters cost little
GUTTER_PX = 2
OUTLINE_LINES, OUTLINE_FOV_DEG = 2160, 70.0  # the outline is compared as a 4K view shows the hull at the swap
OUTLINE_SUPERSAMPLE = 4
THIN_DEPTHS = (1.0, 2.0)  # cells across a part to look for its inside before calling it thin
CLOSE_CELLS = 1  # gaps up to twice this many cells wide are filled
FILL_DEPTH = 0.1  # how far inside a node taken in counts, in cells: the skin passes close by it
MIN_BIT_CELLS = 2.5  # loose bits of skin smaller than this many cells are dropped: under a pixel at the swap
VISIBLE_REACH = (1.0, 2.0)  # a sample is seen from outside when the grid is open this many cells out along its facing
FLAT_NORMAL = (128, 128, 255)
MAX_NODES = 40_000_000  # the most grid nodes a piece's far mesh takes (memory)
FAR_STEPS = 24  # grid steps the field is graded over away from the skin
NEAREST_CHUNK = 2_000_000  # samples per pass of the nearest search, to bound its memory
NEIGHBOUR_REACH = 3  # bake buckets searched around a texel whose own has no paint
SRGB_KEYS = ("albedo", "emissive")


@dataclass(frozen=True)
class Samples:
    """Points on a piece's surface: where, which way they face, their UV on the piece's atlas and their surface."""

    position: np.ndarray
    normal: np.ndarray
    uv: np.ndarray
    surface: np.ndarray


def far_triangles(ship_class: str) -> int:
    """The far mesh's triangles for a hull of ``ship_class``, every piece together."""
    return int(round(CLASS_BUDGETS[ship_class].triangles * FAR_SHARE))


def far_from_m(length_m: float) -> float:
    """Where the game swaps a hull ``length_m`` long to its far mesh."""
    return round(FAR_FROM_LENGTHS * float(length_m), 1)


def far_name(stem: str) -> str:
    return f"{stem}_far"


def atlas_size(area_m2: float, largest: int = ATLAS_PX) -> int:
    """The far atlas's side for a skin of ``area_m2``: the power of two near ``FAR_TEXEL_M`` a texel, at most ``largest``."""
    want = math.sqrt(max(area_m2, 1.0) / ATLAS_FILL) / FAR_TEXEL_M
    return int(min(largest, max(MIN_ATLAS_PX, 2 ** math.ceil(math.log2(max(want, 1.0))))))


def outline_px(length_m: float, from_m: float) -> int:
    """The pixels the hull's length spans at the swap on the outline view (the compare's raster)."""
    k = 0.5 * OUTLINE_LINES / math.tan(math.radians(0.5 * OUTLINE_FOV_DEG))
    return max(32, int(round(k * float(length_m) / max(float(from_m), 1e-6))))


# --- the piece -----------------------------------------------------------------------------------------------------------
def read_piece(path: Path, surfaces: Sequence[Mapping[str, Any]]) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """The piece's triangles from its glb: corners ``(F, 3, 3)``, corner UVs ``(F, 3, 2)`` and each face's surface index."""
    names = [str(s.get("name", "")) for s in surfaces]
    corners, uvs, owner = [], [], []
    for k, primitive in enumerate(read_glb(path).primitives):
        faces = np.asarray(primitive.indices, dtype=np.int64).reshape(-1, 3)
        if not len(faces):
            continue
        index = names.index(primitive.material) if primitive.material in names else min(k, len(names) - 1)
        corners.append(np.asarray(primitive.positions, dtype=np.float64)[faces])
        uvs.append(np.asarray(primitive.uv, dtype=np.float64)[faces])
        owner.append(np.full(len(faces), index, dtype=np.int64))
    if not corners:
        raise ValueError(f"{path.name}: no triangles")
    return np.concatenate(corners), np.concatenate(uvs), np.concatenate(owner)


def sample(corners: np.ndarray, uvs: np.ndarray, owner: np.ndarray, spacing: float) -> Samples:
    """Points on every triangle no further apart than ``spacing`` (a lattice in each triangle, so long thin ones are covered)."""
    edges = np.linalg.norm(corners - np.roll(corners, 1, axis=1), axis=2).max(axis=1)
    steps = np.clip(np.ceil(edges / spacing), 1, MAX_STEPS).astype(np.int64)
    normal = np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
    normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-30)
    out: list[tuple[np.ndarray, ...]] = []
    for k in np.unique(steps):
        faces = np.flatnonzero(steps == k)
        i, j = np.meshgrid(np.arange(k + 1), np.arange(k + 1), indexing="ij")
        keep = (i + j) <= k
        bary = np.stack([i[keep], j[keep], k - i[keep] - j[keep]], axis=1).astype(np.float64) / float(k)
        position = np.einsum("pc,fcx->fpx", bary, corners[faces]).reshape(-1, 3)
        uv = np.einsum("pc,fcx->fpx", bary, uvs[faces]).reshape(-1, 2)
        count = len(bary)
        out.append((position.astype(np.float32), np.repeat(normal[faces], count, axis=0).astype(np.float32), uv.astype(np.float32),
                    np.repeat(owner[faces], count).astype(np.int32)))
    return Samples(*(np.concatenate([o[n] for o in out]) for n in range(4)))


# --- the shape -----------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Grid:
    lo: np.ndarray
    cell: float
    dims: tuple[int, int, int]

    def index(self, points: np.ndarray) -> np.ndarray:
        return np.clip(np.rint((points - self.lo) / self.cell).astype(np.int64), 0, np.asarray(self.dims) - 1)

    def flat(self, idx: np.ndarray) -> np.ndarray:
        return (idx[..., 0] * self.dims[1] + idx[..., 1]) * self.dims[2] + idx[..., 2]


def grid_for(lo: np.ndarray, hi: np.ndarray, cell: float) -> Grid:
    """A grid of ``cell`` over the box (coarser if it would pass ``MAX_NODES``), two cells of margin round it."""
    cell = max(cell, float(np.prod(hi - lo + 4.0 * cell) / MAX_NODES) ** (1.0 / 3.0))
    start = lo - 2.0 * cell
    dims = tuple(int(n) for n in np.ceil((hi + 2.0 * cell - start) / cell).astype(np.int64) + 1)
    return Grid(start, cell, dims)


def outside(blocked: np.ndarray) -> np.ndarray:
    """The grid nodes reached from its border without crossing a ``blocked`` one (runs along each axis, until nothing grows)."""
    free = ~blocked
    reached = np.zeros_like(blocked)
    for axis in range(3):
        border = [slice(None)] * 3
        for end in (0, -1):
            border[axis] = end
            reached[tuple(border)] = free[tuple(border)]
    while True:
        before = int(reached.sum())
        for axis in range(3):
            f = np.moveaxis(free, axis, -1)
            r = np.moveaxis(reached, axis, -1)
            n = f.shape[-1]
            rows = f.reshape(-1, n)
            run = np.cumsum(~rows, axis=1) + (np.arange(len(rows)) * (n + 1))[:, None]
            hit = np.bincount(run[rows], weights=r.reshape(-1, n)[rows], minlength=len(rows) * (n + 1)) > 0
            grown = np.zeros_like(rows)
            grown[rows] = hit[run[rows]]
            reached = np.moveaxis(grown.reshape(f.shape), -1, axis).copy()
        if int(reached.sum()) == before:
            return reached


def _grown(solid: np.ndarray, cells: int) -> np.ndarray:
    out = solid.copy()
    for axis in range(3):
        for _ in range(cells):
            step = out.copy()
            lo = [slice(None)] * 3
            hi = [slice(None)] * 3
            lo[axis], hi[axis] = slice(1, None), slice(None, -1)
            step[tuple(lo)] |= out[tuple(hi)]
            step[tuple(hi)] |= out[tuple(lo)]
            out = step
    return out


def closed(solid: np.ndarray, cells: int) -> np.ndarray:
    """``solid`` grown by ``cells`` and shrunk back (a cube's reach): its gaps and tunnels up to twice that wide filled."""
    return ~_grown(~_grown(solid, cells), cells) if cells > 0 else solid


def _nearest(grid: Grid, samples: Samples) -> tuple[np.ndarray, np.ndarray]:
    """Per node, the distance to the nearest sample in the eight cells round it (inf: none) and that sample's index."""
    count = int(np.prod(grid.dims))
    best = np.full(count, np.inf)
    which = np.full(count, -1, dtype=np.int64)
    for start in range(0, len(samples.position), NEAREST_CHUNK):
        position = samples.position[start:start + NEAREST_CHUNK].astype(np.float64)
        base = np.floor((position - grid.lo) / grid.cell).astype(np.int64)
        for corner in np.array([[a, b, c] for a in (0, 1) for b in (0, 1) for c in (0, 1)]):
            idx = np.clip(base + corner, 0, np.asarray(grid.dims) - 1)
            node = grid.flat(idx)
            d = np.linalg.norm(position - (grid.lo + idx * grid.cell), axis=1)
            np.minimum.at(best, node, d)
            won = d <= best[node]
            which[node[won]] = start + np.flatnonzero(won)
    return best, which


def skin(corners: np.ndarray, samples: Samples, cell_m: float) -> tuple[np.ndarray, np.ndarray, Grid, np.ndarray, np.ndarray]:
    """The piece's outer skin as ``(vertices, faces)`` on a grid of ``cell_m``, its grid, the open nodes and which samples are
    seen from outside."""
    flat = corners.reshape(-1, 3)
    grid = grid_for(flat.min(axis=0), flat.max(axis=0), cell_m)
    blocked = np.zeros(grid.dims, dtype=bool)
    blocked.reshape(-1)[grid.flat(grid.index(samples.position))] = True
    open_ = outside(blocked)
    seen = np.zeros(len(samples.position), dtype=bool)
    for reach in VISIBLE_REACH:
        seen |= open_.reshape(-1)[grid.flat(grid.index(samples.position + samples.normal * reach * grid.cell))]
    visible = Samples(samples.position[seen], samples.normal[seen], samples.uv[seen], samples.surface[seen])
    best, which = _nearest(grid, visible)
    near = which >= 0

    def node_at(flat: np.ndarray) -> np.ndarray:
        return grid.lo + np.stack(np.unravel_index(flat, grid.dims), axis=1) * grid.cell

    facing = np.ones(len(best))
    at = np.flatnonzero(near)
    facing[at] = np.sign(np.einsum("ij,ij->i", node_at(at) - visible.position[which[at]], visible.normal[which[at]]))
    facing[facing == 0.0] = 1.0
    sign = np.where(open_.reshape(-1), 1.0, np.where(near, facing, -1.0))
    # A plate or mast thinner than a cell has no node inside it: a node beside it whose twin across it is outside too is taken
    # in (both of them, so a tilted plate stays one sheet: the skin keeps diagonal neighbours apart), so the part keeps about
    # a cell's thickness instead of vanishing.
    beside = np.flatnonzero(near & (sign > 0.0) & blocked.reshape(-1))
    thin = np.ones(len(beside), dtype=bool)
    for depth in THIN_DEPTHS:  # a slanted thick wall's node a cell in may round back outside; two cells in it cannot
        across = grid.flat(grid.index(node_at(beside) - visible.normal[which[beside]] * depth * grid.cell))
        thin &= sign[across] > 0.0
    values = sign * np.minimum(best, grid.cell)
    values[beside[thin]] = -FILL_DEPTH * grid.cell  # just inside: the skin hugs the nodes taken in
    values = values.reshape(grid.dims)
    # Gaps and tunnels a couple of cells wide (truss, frames, slots) are filled: under a pixel at the swap, and every hole
    # through the skin is triangles the thinning cannot take away.
    filled = closed(values < 0.0, CLOSE_CELLS) & (values >= 0.0)
    values[filled] = -FILL_DEPTH * grid.cell
    values = farther(values, grid.cell)

    def field(points: np.ndarray) -> np.ndarray:
        idx = np.rint((points - grid.lo) / grid.cell).astype(np.int64)
        inside = np.all((idx >= 0) & (idx < np.asarray(grid.dims)), axis=1)
        out = np.full(len(points), grid.cell)
        k = idx[inside]
        out[inside] = values[k[:, 0], k[:, 1], k[:, 2]]
        return out

    hi = grid.lo + (np.asarray(grid.dims) - 1) * grid.cell
    vertices, faces = extract(field, grid.lo + grid.cell, hi - grid.cell, grid.cell, block=8)
    vertices, faces = without_bits(vertices, faces, MIN_BIT_CELLS * grid.cell)
    return vertices, faces, grid, open_, seen


def farther(values: np.ndarray, cell: float, steps: int = FAR_STEPS) -> np.ndarray:
    """The field away from the skin as a step count: nodes ``n`` grid steps from a node that changes sign next to it read at
    least ``n`` cells over the square root of three (a lower bound on the true distance), so the extraction skips the blocks
    nowhere near the skin."""
    inside = values < 0.0
    edge = np.zeros_like(inside)
    for axis in range(3):
        lo = [slice(None)] * 3
        hi = [slice(None)] * 3
        lo[axis], hi[axis] = slice(1, None), slice(None, -1)
        change = inside[tuple(lo)] != inside[tuple(hi)]
        edge[tuple(lo)] |= change
        edge[tuple(hi)] |= change
    reach = edge.copy()
    out = values.copy()
    for step in range(2, steps + 1):
        grown = _grown(reach, 1)
        ring = grown & ~reach
        out[ring] = np.where(inside[ring], -1.0, 1.0) * max(cell, step * cell / math.sqrt(3.0))
        reach = grown
    out[~reach] = np.where(inside[~reach], -1.0, 1.0) * max(cell, (steps + 1) * cell / math.sqrt(3.0))
    return out


def components(faces: np.ndarray, count: int) -> np.ndarray:
    """Each vertex's connected piece of skin, as the lowest vertex index in it."""
    label = np.arange(count)
    while True:
        low = label[faces].min(axis=1)
        nxt = label.copy()
        for k in range(3):
            np.minimum.at(nxt, faces[:, k], low)
        nxt = nxt[nxt]
        if np.array_equal(nxt, label):
            return label
        label = nxt


def without_bits(vertices: np.ndarray, faces: np.ndarray, smallest_m: float) -> tuple[np.ndarray, np.ndarray]:
    """The skin without its loose pieces smaller than ``smallest_m`` across, or too few faces to close (the thinning's
    leftovers of a part it flattened)."""
    label = components(faces, len(vertices))
    keys, inverse = np.unique(label, return_inverse=True)
    lo = np.full((len(keys), 3), np.inf)
    hi = np.full((len(keys), 3), -np.inf)
    np.minimum.at(lo, inverse, vertices)
    np.maximum.at(hi, inverse, vertices)
    owner = inverse[faces[:, 0]]
    keep = ((hi - lo).max(axis=1) >= smallest_m) & (np.bincount(owner, minlength=len(keys)) >= 4)
    faces = faces[keep[owner]]
    used, faces = np.unique(faces, return_inverse=True)
    return vertices[used], faces.reshape(-1, 3)


# --- the paint -----------------------------------------------------------------------------------------------------------
def _linear(values: np.ndarray) -> np.ndarray:
    return srgb_to_linear(values / 255.0)


def _encoded(values: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(255.0 * linear_to_srgb(np.clip(values, 0.0, 1.0))), 0, 255).astype(np.uint8)


def _facing_bin(normal: np.ndarray) -> np.ndarray:
    axis = np.argmax(np.abs(normal), axis=1)
    return 2 * axis + (normal[np.arange(len(normal)), axis] < 0.0)


def map_values(samples: Samples, files: Sequence[Mapping[str, str]], out_dir: Path) -> dict[str, np.ndarray]:
    """Each map's value under every sample (linear for the colour maps), read from the surfaces' maps (their lighter set when
    there is one: the far atlas is coarser than either)."""
    cache: dict[str, np.ndarray] = {}
    out: dict[str, np.ndarray] = {}
    for key in ("albedo", "orm", "emissive"):
        values = np.zeros((len(samples.position), 3))
        for k, names in enumerate(files):
            mine = samples.surface == k
            if not mine.any():
                continue
            name = names[key]
            if name not in cache:
                cache[name] = read_png(out_dir / name)
            image = cache[name]
            h, w = image.shape[:2]
            uv = samples.uv[mine]
            px = np.clip((uv[:, 0] * w).astype(np.int64), 0, w - 1)
            py = np.clip((uv[:, 1] * h).astype(np.int64), 0, h - 1)
            texel = image[py, px][..., :3].astype(np.float64) if image.ndim == 3 else np.repeat(image[py, px][:, None], 3, axis=1)
            values[mine] = _linear(texel) if key in SRGB_KEYS else texel / 255.0
        out[key] = values
    return out


def bake(points: np.ndarray, normals: np.ndarray, samples: Samples, values: Mapping[str, np.ndarray], bucket_m: float,
         lo: np.ndarray) -> dict[str, np.ndarray]:
    """Each map at ``points`` (facing ``normals``): the mean of the samples in its bucket facing the same way, else of the
    nearest bucket round it that has some, else of any facing; the whole piece's mean where nothing is near."""
    stacked = np.concatenate([values[k] for k in ("albedo", "orm", "emissive")], axis=1)
    cell = np.floor((samples.position - lo) / bucket_m).astype(np.int64)
    span = int(cell.max()) + 2 * NEIGHBOUR_REACH + 2

    def key(c: np.ndarray, facing: np.ndarray) -> np.ndarray:
        c = c + NEIGHBOUR_REACH + 1
        return ((c[:, 0] * span + c[:, 1]) * span + c[:, 2]) * 7 + facing

    tables = []
    for facing in (_facing_bin(samples.normal), np.full(len(cell), 6)):
        keys, inverse = np.unique(key(cell, facing), return_inverse=True)
        sums = np.zeros((len(keys), stacked.shape[1]))
        np.add.at(sums, inverse, stacked)
        tables.append((keys, sums / np.bincount(inverse, minlength=len(keys))[:, None]))
    result = np.tile(stacked.mean(axis=0), (len(points), 1))
    missing = np.ones(len(points), dtype=bool)
    at = np.floor((points - lo) / bucket_m).astype(np.int64)
    r = NEIGHBOUR_REACH
    offsets = np.array([[a, b, c] for a in range(-r, r + 1) for b in range(-r, r + 1) for c in range(-r, r + 1)])
    offsets = offsets[np.argsort(np.linalg.norm(offsets, axis=1), kind="stable")]
    for (keys, means), facing in zip(tables, (_facing_bin(normals), np.full(len(points), 6)), strict=True):
        for offset in offsets:
            if not missing.any():
                break
            want = np.flatnonzero(missing)
            k = key(at[want] + offset, facing[want])
            slot = np.clip(np.searchsorted(keys, k), 0, len(keys) - 1)
            found = keys[slot] == k
            result[want[found]] = means[slot[found]]
            missing[want[found]] = False
    return {"albedo": result[:, 0:3], "orm": result[:, 3:6], "emissive": result[:, 6:9]}


# --- the outline ---------------------------------------------------------------------------------------------------------
def _coverage(vertices: np.ndarray, faces: np.ndarray, axes: tuple[int, int], lo: np.ndarray, px: float, size: tuple[int, int]) -> np.ndarray:
    """How much of each pixel the mesh covers seen along the third axis, from a raster ``OUTLINE_SUPERSAMPLE`` times finer (as an
    anti-aliased view shows it)."""
    k = OUTLINE_SUPERSAMPLE
    image = np.zeros((k * max(size), k * max(size)), dtype=bool)
    t = (vertices[:, list(axes)] - lo) / (px / k)
    tri = t[np.asarray(faces, dtype=np.int64)]
    twice = (tri[:, 1, 0] - tri[:, 0, 0]) * (tri[:, 2, 1] - tri[:, 0, 1]) - (tri[:, 1, 1] - tri[:, 0, 1]) * (tri[:, 2, 0] - tri[:, 0, 0])
    tri = tri[np.abs(twice) > 1e-12]
    for start in range(0, len(tri), 20000):
        _fill(image, tri[start:start + 20000])
    n = max(size)
    return image.reshape(n, k, n, k).mean(axis=(1, 3))


VIEWS = {"top": (0, 2), "side": (1, 2), "front": (0, 1)}


def outline_iou(full: tuple[np.ndarray, np.ndarray], far: tuple[np.ndarray, np.ndarray], res: int) -> dict[str, float]:
    """How well the far mesh's outline matches the full one's in the top, side and front views: the IoU of their pixel coverage
    on a view whose longest side is ``res`` pixels."""
    v_full, f_full = full
    lo = np.minimum(v_full.min(axis=0), far[0].min(axis=0))
    hi = np.maximum(v_full.max(axis=0), far[0].max(axis=0))
    px = float((hi - lo).max()) * 1.02 / res
    out = {}
    for name, axes in VIEWS.items():
        size = (int(math.ceil((hi[axes[0]] - lo[axes[0]]) / px)) + 2, int(math.ceil((hi[axes[1]] - lo[axes[1]]) / px)) + 2)
        a = _coverage(v_full, f_full, axes, lo[list(axes)], px, size)
        b = _coverage(far[0], far[1], axes, lo[list(axes)], px, size)
        union = float(np.maximum(a, b).sum())
        out[name] = round(float(np.minimum(a, b).sum()) / union, 4) if union else 1.0
    return out


def thinned(vertices: np.ndarray, faces: np.ndarray, triangles: int, full: tuple[np.ndarray, np.ndarray], res: int,
            smallest_m: float) -> tuple[np.ndarray, np.ndarray, dict[str, float]]:
    """The skin thinned to the fewest of ``triangles`` times ``BUDGET_STEPS`` whose outline holds ``OUTLINE_MIN`` in every view
    against ``full`` (else the largest), with its IoU."""
    tried = []
    v, f = vertices, faces
    for step in sorted(BUDGET_STEPS, reverse=True):
        v, f = decimate(v, f, int(round(triangles * step)))
        v, f = without_bits(v, f, smallest_m)
        tried.append((v, f, outline_iou(full, (v, f), res)))
    for v, f, iou in reversed(tried):
        if min(iou.values()) >= OUTLINE_MIN:
            return v, f, iou
    return tried[0]


# --- the whole step ------------------------------------------------------------------------------------------------------
def _surface_files(surface: Mapping[str, Any]) -> dict[str, str]:
    low = surface.get("detail", {}).get("low", {}) if isinstance(surface.get("detail"), Mapping) else {}
    return {key: str(low.get(key, surface[key])) for key in ("albedo", "orm", "emissive")}


def _far_surface(surface: Mapping[str, Any], stem: str) -> dict[str, Any]:
    # The far atlas is one set: no lighter set, and no world-space detail tile (far beyond where it shows).
    out = {k: v for k, v in surface.items() if k not in ("detail", "world_detail")}
    out.update({key: f"{stem}_{key}.png" for key in MAP_KEYS})
    out["blend"] = False
    out["transmittance"] = 0.0
    return out


def build_far(out_dir: Path, entry: Mapping[str, Any], triangles: int, from_m: float, length_m: float,
              atlas_px: int = ATLAS_PX, cells: int = GRID_CELLS) -> tuple[dict[str, Any], list[Path]]:
    """The far mesh of the piece whose textured-mesh section is ``entry`` (files under ``out_dir``) on a hull ``length_m`` long
    (its grid is ``cells`` along that length, whatever the piece's own size): its ``lods`` entry and the files written."""
    out_dir = Path(out_dir)
    surfaces = list(entry["surfaces"])
    corners, uvs, owner = read_piece(out_dir / str(entry["file"]), surfaces)
    if entry.get("interior_file"):  # the bays' halls, kept apart for their light (M10-T72), are part of the shape
        inner = read_piece(out_dir / str(entry["interior_file"]), surfaces)
        corners, uvs, owner = (np.concatenate([a, b]) for a, b in zip((corners, uvs, owner), inner, strict=True))
    cell = float(length_m) / cells
    samples = sample(corners, uvs, owner, cell / SAMPLES_PER_CELL)
    vertices, faces, grid, _open, seen = skin(corners, samples, cell)
    full = (corners.reshape(-1, 3), np.arange(len(corners) * 3).reshape(-1, 3))
    vertices, faces, iou = thinned(vertices, faces, triangles, full, outline_px(length_m, from_m), MIN_BIT_CELLS * grid.cell)

    # Faceted: every face its own corners, so the flat normal map shades it as the plates it stands for.
    corner_pos = vertices[faces]
    normal = np.cross(corner_pos[:, 1] - corner_pos[:, 0], corner_pos[:, 2] - corner_pos[:, 0])
    normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-30)
    welded = Mesh(vertices, faces, np.zeros(len(faces), dtype=np.int64), (Material("far", (0.5, 0.5, 0.5)),))  # charts grow over shared edges
    area = 0.5 * float(np.linalg.norm(np.cross(corner_pos[:, 1] - corner_pos[:, 0], corner_pos[:, 2] - corner_pos[:, 0]), axis=1).sum())
    atlas_px = atlas_size(area, atlas_px)
    charts = charts_of(welded, CHART_ANGLE_DEG)
    packed = pack(charts, math.sqrt(area / (ATLAS_FILL * atlas_px * atlas_px)), atlas_px, GUTTER_PX)
    uv01 = packed.face_uv01(len(faces))
    corner_normals = np.repeat(normal[:, None, :], 3, axis=1)
    buffers = rasterize(atlas_px, uv01, corner_pos, corner_normals, np.zeros(len(faces), dtype=np.int32),
                        np.zeros(len(faces), dtype=np.int32), packed.face_chart(len(faces)), np.zeros((len(faces), 3), dtype=bool))
    dilate(buffers, GUTTER_PX)

    visible = Samples(samples.position[seen], samples.normal[seen], samples.uv[seen], samples.surface[seen])
    values = map_values(visible, [_surface_files(s) for s in surfaces], out_dir)
    texels = np.flatnonzero(buffers.filled.reshape(-1))
    baked = bake(buffers.position.reshape(-1, 3)[texels], buffers.normal.reshape(-1, 3)[texels], visible, values,
                 max(1.5 * packed.texel_m, 0.5 * grid.cell), grid.lo)
    mean_albedo = baked["albedo"].mean(axis=0)

    stem = far_name(Path(str(entry["file"])).stem)
    files: list[Path] = []
    maps: dict[str, np.ndarray] = {}
    for key in ("albedo", "orm", "emissive"):
        image = np.zeros((atlas_px * atlas_px, 3), dtype=np.uint8)
        fill = mean_albedo if key == "albedo" else baked[key].mean(axis=0)
        image[:] = _encoded(fill[None, :]) if key in SRGB_KEYS else np.clip(np.rint(fill * 255.0), 0, 255).astype(np.uint8)
        image[texels] = _encoded(baked[key]) if key in SRGB_KEYS else np.clip(np.rint(baked[key] * 255.0), 0, 255).astype(np.uint8)
        maps[key] = image.reshape(atlas_px, atlas_px, 3)
    maps["normal"] = np.broadcast_to(np.array(FLAT_NORMAL, dtype=np.uint8), (16, 16, 3)).copy()
    for key in MAP_KEYS:
        png = out_dir / f"{stem}_{key}.png"
        files.append(write_png(png, maps[key]))
        sidecar = Path(str(png) + ".import")
        sidecar.write_text(import_sidecar(key), encoding="utf-8", newline="\n")
        files.append(sidecar)

    opaque = next((s for s in surfaces if not s.get("blend", False)), surfaces[0])
    primitive = GlbPrimitive(corner_pos.reshape(-1, 3), np.repeat(normal, 3, axis=0), uv01.reshape(-1, 2),
                             np.arange(len(faces) * 3), str(opaque["name"]))
    files.append(write_glb(out_dir / f"{stem}.glb", [primitive], stem))

    lo, hi = vertices.min(axis=0), vertices.max(axis=0)
    lod = {
        "file": f"{stem}.glb",
        "triangles": int(len(faces)),
        "vertices": int(len(faces) * 3),
        "from_m": round(float(from_m), 1),
        "margin_m": round(float(from_m) * FAR_MARGIN_SHARE, 1),
        "aabb_min": [round(float(x), 5) for x in lo],
        "aabb_max": [round(float(x), 5) for x in hi],
        "texel_m": round(float(packed.texel_m), 6),
        "atlas_px": int(atlas_px),
        "map_px": {key: int(maps[key].shape[0]) for key in MAP_KEYS},
        "mean_albedo": [round(float(c), 6) for c in mean_albedo],
        "surfaces": [_far_surface(opaque, stem)],
        "outline_iou": iou,
    }
    return lod, files


def piece_shares(entries: Mapping[str, Mapping[str, Any]], total: int) -> dict[str, int]:
    """The far triangles of each piece: the total split by the pieces' full triangles, each at least ``MIN_PIECE_TRIANGLES``."""
    full = {name: max(int(e["mesh"]["triangles"]), 1) for name, e in entries.items()}
    whole = float(sum(full.values()))
    return {name: max(MIN_PIECE_TRIANGLES, int(round(total * n / whole))) for name, n in full.items()}


def add_far_meshes(out_dir: Path, manifest: dict[str, Any], ship_class: str, atlas_px: int = ATLAS_PX,
                   cells: int = GRID_CELLS) -> list[Path]:
    """Writes every piece's far mesh into ``out_dir`` and lists it in the piece's ``mesh.lods`` (in ``manifest``, changed in
    place); returns the files written."""
    pieces: dict[str, Any] = manifest["pieces"]
    length = float(manifest["dimensions_m"]["length"])
    from_m = far_from_m(length)
    files: list[Path] = []
    for name, share in piece_shares(pieces, far_triangles(ship_class)).items():
        mesh = pieces[name]["mesh"]
        lod, written = build_far(out_dir, mesh, share, from_m, length, atlas_px, cells)
        mesh["lods"] = [lod]
        files += written
    return files


__all__ = ["FAR_FROM_LENGTHS", "atlas_size", "FAR_MARGIN_SHARE", "FAR_SHARE", "add_far_meshes", "build_far", "far_from_m", "far_name",
           "far_triangles", "outline_iou", "outline_px", "piece_shares", "sample", "skin"]
