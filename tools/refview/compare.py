"""Fidelity check of a built civilian asset against its reference STL (M5-T23, Q18).

Every civilian model must lie within 90 % of its STL, measured as silhouettes and size. This tool is the measuring
stick: it puts the STL (in the same ship frame and at the same length as ``refview.py``) and the asset's LOD0 splats on
one grid, draws the top, side and front silhouettes of both, and scores each view's intersection over union (IoU)
together with the length, width and height of asset against model. The bar is an IoU of at least 0.90 in every view and
every dimension within 10 %. Nothing from the STL is kept: the overlays and numbers go to the gitignored
``reports/refs/<name>/compare/``.

Usage, with the project's venv and isolated mode::

    .venv/bin/python3 -I tools/refview/compare.py references/EA_Saturn_4_transport.stl saturn_4_transport \\
        --length 100 --right=-x --up=+z --aft=+y

The second argument is an asset id (a folder under ``assets/generated/``) or a path to an asset folder. The STL takes the
same ``--length``, ``--right``, ``--up`` and ``--aft`` as ``refview.py``; the mappings of the civilian ships are in
``docs/design-references.md``. Exit status: 0 when every view and dimension passes, 1 when one does not, 2 on bad input.

How the two sides are put on one grid
-------------------------------------
* The model is in the authored frame: x to starboard, y up, z aft from the nose tip (z = 0), metres, x and y centred on
  the model's box (``refview.to_ship_frame``). A generator that authors about another origin (the Saturns measure y
  from the spine axis) shows it as a shift; ``--model-offset X,Y,Z`` moves the model onto that origin, and the output
  suggests a value when the two boxes' centres are further apart than the shift window.
* The asset's LOD0 PLY is stored as the generators write it: the authored positions minus ``manifest.centroid_offset``,
  then turned by Rz(180) into the GDGS orientation (``core.frames``). The tool reverses both: it flips x and y of the
  positions and rotations back and adds the centroid offset.
* Each splat is drawn as the orthographic projection of its Gaussian: an ellipse, not a disc, so a flat splat seen
  edge-on is a thin line and a closed hull is not grown by the splat size at its horizon. The ellipse reaches
  ``SPLAT_SIGMAS`` sigmas from the centre (see the constant for why).
* The pixel is ``PIXEL_FRACTION`` of the length (never above 0.5 %). The asset may then move by a whole number of pixels
  in x, y and z, up to 2 % of the length each, to the place where the three views overlap best; the shift is reported
  and the scores are those at that place (``iou_unshifted`` in the JSON is the score without it).
* ``--model-zrange`` and ``--asset-zrange`` keep one part of each side so a ship is scored part by part (the Saturns,
  Q16). The model is cut exactly at the planes; the asset keeps the splats whose centres lie inside. Each cropped side
  is moved so that the start of its range is z = 0, so two parts meet at their starts; a side without a range keeps its
  own z = 0. ``--part NAME`` puts the result in its own folder.
* Extra parts (the Bokmai's removable pods) are drawn with the hull: ``--pod-ply FILE`` is a splat file in the pod's own
  frame, put at every mount from ``--pod-at X,Y,Z`` (body frame, repeatable) and ``--pods-from-hardpoints`` (the
  asset's ``hardpoints.json`` ``cargo_pods[]``, whose ``position`` and ``up`` are in the body frame, as the other
  hardpoints are). The pod's +y is turned onto ``up``.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:  # run as a script in isolated mode, the repo root is not on the path
    sys.path.insert(0, str(REPO_ROOT))

from tools.procgen.core import frames  # noqa: E402
from tools.procgen.core.manifest import read_manifest  # noqa: E402
from tools.procgen.core.ply import read_ply  # noqa: E402
from tools.refview import refview  # noqa: E402

GENERATED = REPO_ROOT / "assets" / "generated"

IOU_MIN = 0.90  # each view's intersection over union must reach this (Q18)
DIM_TOLERANCE = 0.10  # length, width and height of asset / model within this of 1 (Q18)
SHIFT_FRACTION = 0.02  # the best-fit shift of the asset: at most this share of the length, per axis
PIXEL_FRACTION = 0.0025  # default pixel as a share of the length
PIXEL_FRACTION_MAX = 0.005  # the brief's coarsest allowed pixel
# How far a splat is taken to reach, in sigmas. The generators put about one splat per spacing^2 on the surface, each
# with a sigma of one spacing, and the centres sit on the mesh, so a surface cell is a disc of about 0.56 spacings. The
# value is calibrated on three built assets against their own fallback meshes (the silhouettes the splats were sampled
# from): the mean IoU over the three views peaks at 0.7 to 0.8 sigmas for the raider (0.91), the Narn transport (0.96) and
# the Starfury (0.96); 1.0 grows every edge by about half a spacing and 0.5 leaves holes. So even a perfect generator
# scores 0.91 to 0.97 here, mostly where parts are thinner than a few spacings.
SPLAT_SIGMAS = 0.75

MODEL_ONLY = (232, 128, 24)  # orange
ASSET_ONLY = (36, 112, 224)  # blue
BOTH = (64, 64, 64)  # dark grey

# This tool's names for the three silhouettes and refview's views they are drawn from.
VIEWS = {"top": "top", "side": "port", "front": "front"}
DIMENSIONS = {"length": 2, "width": 0, "height": 1}  # name -> ship axis
MAX_GRID_PIXELS = 60_000_000


# --- clipping --------------------------------------------------------------------------------------------------------
def _clip_half(tris: np.ndarray, axis: int, value: float, keep_above: bool) -> np.ndarray:
    """The part of every triangle on one side of the plane ``coordinate[axis] = value``, as triangles."""
    sign = 1.0 if keep_above else -1.0
    d = sign * (tris[:, :, axis] - value)  # >= 0 is kept
    inside = d >= 0.0
    count = inside.sum(axis=1)
    out = [tris[count == 3]]

    def cut(tri: np.ndarray, dist: np.ndarray, i: int, j: int) -> np.ndarray:
        """Where the edge from vertex i (outside) to vertex j (inside) meets the plane."""
        di, dj = dist[np.arange(len(tri)), i], dist[np.arange(len(tri)), j]
        t = di / (di - dj)
        a, b = tri[np.arange(len(tri)), i], tri[np.arange(len(tri)), j]
        return a + t[:, None] * (b - a)

    one = count == 1  # one corner inside: a small triangle at that corner
    if one.any():
        tri, dist = tris[one], d[one]
        k = np.argmax(inside[one], axis=1)
        k1, k2 = (k + 1) % 3, (k + 2) % 3
        rows = np.arange(len(tri))
        out.append(np.stack([tri[rows, k], cut(tri, dist, k1, k), cut(tri, dist, k2, k)], axis=1))
    two = count == 2  # one corner outside: a quad at the other two, as two triangles
    if two.any():
        tri, dist = tris[two], d[two]
        o = np.argmax(~inside[two], axis=1)
        a, b = (o + 1) % 3, (o + 2) % 3
        rows = np.arange(len(tri))
        pa, pb = cut(tri, dist, o, a), cut(tri, dist, o, b)
        out.append(np.stack([tri[rows, a], tri[rows, b], pb], axis=1))
        out.append(np.stack([tri[rows, a], pb, pa], axis=1))
    return np.concatenate(out) if any(len(o) for o in out) else np.zeros((0, 3, 3))


def clip_slab(tris: np.ndarray, axis: int, lo: float, hi: float) -> np.ndarray:
    """Triangles ``(n, 3, 3)`` cut exactly to ``lo <= coordinate[axis] <= hi``, so a part of a model keeps its true
    outline at the cut instead of the whole of every triangle that crosses it."""
    return _clip_half(_clip_half(tris, axis, lo, True), axis, hi, False)


# --- splats ----------------------------------------------------------------------------------------------------------
@dataclass
class SplatSet:
    """Splat centres and 3D covariances in the authored frame (metres)."""

    centres: np.ndarray  # (n, 3)
    cov: np.ndarray  # (n, 3, 3)

    def __len__(self) -> int:
        return int(len(self.centres))

    def bounds(self, sigmas: float = SPLAT_SIGMAS) -> tuple[np.ndarray, np.ndarray]:
        """The box of all splat ellipsoids at ``sigmas`` sigmas (exact for an ellipsoid: centre +- reach per axis)."""
        reach = sigmas * np.sqrt(np.maximum(np.einsum("nii->ni", self.cov), 0.0))
        return (self.centres - reach).min(axis=0), (self.centres + reach).max(axis=0)

    def transformed(self, rotation: np.ndarray, offset: np.ndarray) -> SplatSet:
        return SplatSet(self.centres @ rotation.T + offset, np.einsum("ij,njk,lk->nil", rotation, self.cov, rotation))

    def cropped(self, axis: int, lo: float, hi: float) -> SplatSet:
        keep = (self.centres[:, axis] >= lo) & (self.centres[:, axis] <= hi)
        return SplatSet(self.centres[keep], self.cov[keep])

    @staticmethod
    def concatenate(parts: list[SplatSet]) -> SplatSet:
        return SplatSet(np.concatenate([p.centres for p in parts]), np.concatenate([p.cov for p in parts]))


def splat_set(centres: np.ndarray, scales: np.ndarray, quats: np.ndarray | None = None) -> SplatSet:
    """A splat set from authored-frame centres, per-axis sigmas and ``(w, x, y, z)`` rotations (identity if none)."""
    centres = np.asarray(centres, dtype=np.float64).reshape(-1, 3)
    var = np.asarray(scales, dtype=np.float64).reshape(-1, 3) ** 2
    if quats is None:
        cov = np.einsum("ni,ij->nij", var, np.eye(3))
    else:
        r = frames.quat_to_matrix(np.asarray(quats, dtype=np.float64).reshape(-1, 4))
        cov = np.einsum("nij,nj,nkj->nik", r, var, r)
    return SplatSet(centres, cov)


def splats_from_ply(path: Path, offset: np.ndarray) -> SplatSet:
    """Splats of a generator's PLY in the authored frame: the GDGS flip (Rz(180)) undone on positions and rotations, then
    ``offset`` (``manifest.centroid_offset``, the authored position of the file's origin) added back."""
    try:
        data = read_ply(path).to_splats()
    except (OSError, ValueError) as exc:
        raise ValueError(f"{path}: cannot read the splat file ({exc})") from exc
    centres = frames.gdgs_to_godot_positions(data.xyz) + np.asarray(offset, dtype=np.float64)
    return splat_set(centres, data.scale, frames.gdgs_to_godot_quats(data.rot))


def resolve_asset(asset: str | Path, root: Path = GENERATED) -> Path:
    """The asset folder for an id (under ``root``) or a path."""
    direct = Path(asset)
    if direct.is_dir():
        return direct
    under_root = Path(root) / str(asset)
    if under_root.is_dir():
        return under_root
    raise ValueError(f"asset {asset!r}: nothing at {direct} or {under_root}")


def read_asset_manifest(folder: Path) -> dict:
    try:
        return read_manifest(folder)
    except (OSError, ValueError) as exc:
        raise ValueError(f"{folder}: cannot read manifest.json ({exc})") from exc


def load_asset_splats(folder: Path) -> SplatSet:
    """The LOD0 splats of the asset in ``folder``, in the authored frame."""
    manifest = read_asset_manifest(Path(folder))
    return splats_from_ply(Path(folder) / manifest["lods"][0]["file"], np.asarray(manifest["centroid_offset"], dtype=np.float64))


def rotation_to_up(up: np.ndarray) -> np.ndarray:
    """The shortest turn of +y onto ``up``; for the opposite direction, half a turn about x."""
    u = np.asarray(up, dtype=np.float64)
    n = np.linalg.norm(u)
    if n < 1e-12:
        raise ValueError("a pod mount has a zero up vector")
    u = u / n
    c = float(u[1])
    if c > 1.0 - 1e-9:
        return np.eye(3)
    if c < -1.0 + 1e-9:
        return np.diag([1.0, -1.0, -1.0])
    v = np.cross([0.0, 1.0, 0.0], u)
    k = np.array([[0.0, -v[2], v[1]], [v[2], 0.0, -v[0]], [-v[1], v[0], 0.0]])
    return np.eye(3) + k + k @ k * ((1.0 - c) / float(v @ v))


def place_parts(part_ply: Path, mounts: list[tuple[np.ndarray, np.ndarray]], centroid_offset: np.ndarray) -> list[SplatSet]:
    """One copy of the part at every mount ``(position, up)`` of the body frame, in the authored frame."""
    part = splats_from_ply(part_ply, np.zeros(3))
    return [part.transformed(rotation_to_up(up), np.asarray(pos, dtype=np.float64) + centroid_offset) for pos, up in mounts]


# --- grids and silhouettes -------------------------------------------------------------------------------------------
@dataclass
class ViewGrid:
    """A pixel grid over one orthographic view: ``basis`` rows are the image right and up directions in the ship frame;
    column = (u - u0) / px and row = (v1 - v) / px for ``u, v`` = the point on those two directions."""

    name: str
    basis: np.ndarray
    u0: float
    v1: float
    px: float
    shape: tuple[int, int]  # rows, columns

    def to_pixels(self, points: np.ndarray) -> np.ndarray:
        uv = np.asarray(points, dtype=np.float64) @ self.basis.T
        return np.stack([(uv[..., 0] - self.u0) / self.px, (self.v1 - uv[..., 1]) / self.px], axis=-1)


def view_basis(view: str) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """(right, up, forward) of one of this tool's views in the ship frame, as refview draws them."""
    forward, up = refview.VIEWS[VIEWS.get(view, view)]
    canvas = refview.Canvas(np.asarray(forward, float), np.asarray(up, float), 1.0, (0.0, 1.0), (0.0, 1.0))
    return canvas.right, canvas.up, canvas.forward


def view_grid(view: str, lo: np.ndarray, hi: np.ndarray, px: float, pad_px: int) -> ViewGrid:
    """A grid over the box ``lo..hi`` seen in ``view``, ``pad_px`` pixels of empty margin on every side."""
    right, up, _ = view_basis(view)
    basis = np.stack([right, up])
    corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
    uv = corners @ basis.T
    pad = pad_px * px
    u0 = math.floor(uv[:, 0].min() / px) * px - pad
    u1 = math.ceil(uv[:, 0].max() / px) * px + pad
    v0 = math.floor(uv[:, 1].min() / px) * px - pad
    v1 = math.ceil(uv[:, 1].max() / px) * px + pad
    w, h = round((u1 - u0) / px), round((v1 - v0) / px)
    if w * h > MAX_GRID_PIXELS:
        raise ValueError(
            f"the {view} grid would be {w} x {h} pixels: the asset and the model differ by orders of magnitude; check --length and the units"
        )
    return ViewGrid(view, basis, u0, v1, px, (h, w))


def triangle_mask(tris: np.ndarray, grid: ViewGrid) -> np.ndarray:
    """Pixels covered by the triangles in this view (refview's rasteriser: centres inside, and tiny triangles still mark one)."""
    h, w = grid.shape
    if len(tris) == 0:
        return np.zeros((h, w), dtype=bool)
    xy = grid.to_pixels(tris)
    screen = np.concatenate([xy, np.zeros(xy.shape[:-1] + (1,))], axis=-1)
    _, index = refview.rasterize(screen, w, h)
    return index >= 0


def splat_mask(splats: SplatSet, grid: ViewGrid, sigmas: float = SPLAT_SIGMAS) -> np.ndarray:
    """Pixels covered by the splats in this view: a pixel is covered when its centre lies within ``sigmas`` sigmas of a
    splat's projected Gaussian, so a flat splat seen edge-on is a thin line. A splat is never thinner than a pixel and
    always marks the pixel under its centre."""
    h, w = grid.shape
    mask = np.zeros((h, w), dtype=bool)
    if len(splats) == 0:
        return mask
    cx, cy = grid.to_pixels(splats.centres).T
    cov = np.einsum("ai,nij,bj->nab", grid.basis, splats.cov, grid.basis) / grid.px**2
    cov[:, 0, 1] *= -1.0  # the image's y runs against v
    cov[:, 1, 0] *= -1.0
    floor = (0.75 / sigmas) ** 2  # a reach of 3/4 pixel at least, so an edge-on plate is a line that crosses pixel centres
    a, b, c = cov[:, 0, 0] + floor, cov[:, 0, 1], cov[:, 1, 1] + floor
    det = a * c - b * b
    ia, ib, ic = c / det, -b / det, a / det  # the inverse of the covariance
    reach = np.maximum(np.ceil(sigmas * np.sqrt(a)), np.ceil(sigmas * np.sqrt(c))).astype(np.int64) + 1
    limit = sigmas * sigmas

    base_c, base_r = np.floor(cx).astype(np.int64), np.floor(cy).astype(np.int64)
    centred = (base_c >= 0) & (base_c < w) & (base_r >= 0) & (base_r < h)
    mask[base_r[centred], base_c[centred]] = True

    for r in np.unique(reach):
        ids = np.flatnonzero(reach == r)
        side = 2 * int(r) + 1
        step = max(1, 1_000_000 // (side * side))
        offs = np.arange(-int(r), int(r) + 1)
        for start in range(0, len(ids), step):
            s = ids[start : start + step]
            cols = base_c[s][:, None, None] + offs[None, None, :]
            rows = base_r[s][:, None, None] + offs[None, :, None]
            dx = cols + 0.5 - cx[s][:, None, None]
            dy = rows + 0.5 - cy[s][:, None, None]
            q = ia[s][:, None, None] * dx * dx + 2.0 * ib[s][:, None, None] * dx * dy + ic[s][:, None, None] * dy * dy
            hit = (q <= limit) & (cols >= 0) & (cols < w) & (rows >= 0) & (rows < h)
            rows_b, cols_b = np.broadcast_to(rows, hit.shape), np.broadcast_to(cols, hit.shape)
            mask[rows_b[hit], cols_b[hit]] = True
    return mask


# --- scoring ---------------------------------------------------------------------------------------------------------
@dataclass
class ViewScore:
    grid: ViewGrid
    iou: float
    iou_unshifted: float
    model_mask: np.ndarray
    asset_mask: np.ndarray  # after the best-fit shift

    @property
    def model_px(self) -> int:
        return int(self.model_mask.sum())

    @property
    def asset_px(self) -> int:
        return int(self.asset_mask.sum())

    @property
    def both_px(self) -> int:
        return int((self.model_mask & self.asset_mask).sum())


@dataclass
class Comparison:
    views: dict[str, ViewScore]
    shift_m: np.ndarray
    shift_limit_m: float
    pixel_m: float
    model_dims: dict[str, float]
    asset_dims: dict[str, float]
    ratios: dict[str, float] = field(default_factory=dict)
    centre_gap_m: np.ndarray = field(default_factory=lambda: np.zeros(3))  # asset box centre minus model box centre
    at_limit: tuple[bool, bool, bool] = (False, False, False)  # the best-fit shift reached its limit on x, y, z


def shift_table(model: np.ndarray, asset: np.ndarray, reach: int) -> np.ndarray:
    """IoU of the two masks for every whole-pixel move of ``asset`` of up to ``reach`` pixels each way, indexed
    ``[row move + reach, column move + reach]``. Both masks keep ``reach`` empty pixels at their edges."""
    h, w = model.shape
    core = model[reach : h - reach, reach : w - reach]
    total = int(model.sum()) + int(asset.sum())
    table = np.zeros((2 * reach + 1, 2 * reach + 1))
    for dr in range(-reach, reach + 1):
        for dc in range(-reach, reach + 1):
            moved = asset[reach - dr : h - reach - dr, reach - dc : w - reach - dc]
            inter = int(np.count_nonzero(core & moved))
            table[dr + reach, dc + reach] = inter / max(total - inter, 1)
    return table


def compare_shapes(
    model_tris: np.ndarray,
    splats: SplatSet,
    length_ref: float,
    pixel_fraction: float = PIXEL_FRACTION,
    shift_fraction: float = SHIFT_FRACTION,
    sigmas: float = SPLAT_SIGMAS,
) -> Comparison:
    """Score the splats against the model triangles, both in the authored frame, on grids whose pixel is
    ``pixel_fraction`` of ``length_ref``."""
    if pixel_fraction > PIXEL_FRACTION_MAX + 1e-12 or pixel_fraction <= 0.0:
        raise ValueError(f"the pixel must be at most {PIXEL_FRACTION_MAX:.1%} of the length (got {pixel_fraction:g})")
    if len(model_tris) == 0 or len(splats) == 0:
        raise ValueError("nothing to compare: the model or the asset is empty")
    px = pixel_fraction * length_ref
    reach = int(round(shift_fraction * length_ref / px))

    verts = model_tris.reshape(-1, 3)
    m_lo, m_hi = verts.min(axis=0), verts.max(axis=0)
    a_lo, a_hi = splats.bounds(sigmas)
    lo, hi = np.minimum(m_lo, a_lo), np.maximum(m_hi, a_hi)

    grids, masks, tables = {}, {}, {}
    for name in VIEWS:
        grid = view_grid(name, lo, hi, px, reach + 1)
        grids[name] = grid
        masks[name] = (triangle_mask(model_tris, grid), splat_mask(splats, grid, sigmas))
        tables[name] = shift_table(masks[name][0], masks[name][1], reach)

    # One move of the asset for all three views: the best mean overlap, the smallest move among equals.
    steps = np.arange(-reach, reach + 1)
    moves = np.stack(np.meshgrid(steps, steps, steps, indexing="ij"), axis=-1).reshape(-1, 3)
    score = np.zeros(len(moves))
    for name, grid in grids.items():
        basis = np.rint(grid.basis).astype(np.int64)
        score += tables[name][-(moves @ basis[1]) + reach, moves @ basis[0] + reach]
    best = int(np.lexsort(((moves**2).sum(axis=1), -np.round(score, 9)))[0])
    move = moves[best]

    views = {}
    for name, grid in grids.items():
        basis = np.rint(grid.basis).astype(np.int64)
        d_col, d_row = int(move @ basis[0]), int(-(move @ basis[1]))
        model_mask, asset_mask = masks[name]
        views[name] = ViewScore(
            grid,
            float(tables[name][d_row + reach, d_col + reach]),
            float(tables[name][reach, reach]),
            model_mask,
            np.roll(asset_mask, (d_row, d_col), axis=(0, 1)),
        )
    model_dims = {n: float(m_hi[a] - m_lo[a]) for n, a in DIMENSIONS.items()}
    asset_dims = {n: float(a_hi[a] - a_lo[a]) for n, a in DIMENSIONS.items()}
    ratios = {n: asset_dims[n] / max(model_dims[n], 1e-9) for n in DIMENSIONS}
    centre_gap = 0.5 * ((a_lo + a_hi) - (m_lo + m_hi))
    at_limit = tuple(bool(abs(int(v)) >= reach) for v in move)
    return Comparison(views, move * px, shift_fraction * length_ref, px, model_dims, asset_dims, ratios, centre_gap, at_limit)


def judge(ious: dict[str, float], ratios: dict[str, float]) -> list[str]:
    """What fails the bar (Q18): a view under ``IOU_MIN`` or a dimension off by more than ``DIM_TOLERANCE``. Empty = pass."""
    failures = [f"{name} IoU {v:.3f} is under {IOU_MIN:.2f}" for name, v in ious.items() if v < IOU_MIN - 1e-9]
    failures += [
        f"{name} ratio {r:.3f} is off by more than {DIM_TOLERANCE:.0%}" for name, r in ratios.items() if abs(r - 1.0) > DIM_TOLERANCE + 1e-9
    ]
    return failures


# --- outputs ---------------------------------------------------------------------------------------------------------
def write_overlay(path: Path, comp: Comparison, view: str, title: str) -> None:
    """The view's silhouettes in three colours (model only, asset only, both) on the metre grid, with legend and scale."""
    score = comp.views[view]
    grid = score.grid
    h, w = grid.shape
    zoom = max(1, round(1400 / max(h, w)))
    _, up, forward = view_basis(view)
    canvas = refview.Canvas(forward, up, zoom / grid.px, (grid.u0, grid.u0 + w * grid.px), (grid.v1 - h * grid.px, grid.v1))
    arr = np.asarray(canvas.background()).copy()
    paint = np.zeros((h, w, 3), dtype=np.uint8)
    paint[score.model_mask & ~score.asset_mask] = MODEL_ONLY
    paint[score.asset_mask & ~score.model_mask] = ASSET_ONLY
    paint[score.model_mask & score.asset_mask] = BOTH
    covered = np.repeat(np.repeat(score.model_mask | score.asset_mask, zoom, axis=0), zoom, axis=1)
    layer = np.repeat(np.repeat(paint, zoom, axis=0), zoom, axis=1)
    left, top = canvas.margin[0], canvas.margin[1]
    rows, cols = min(covered.shape[0], arr.shape[0] - top), min(covered.shape[1], arr.shape[1] - left)
    region = arr[top : top + rows, left : left + cols]
    region[covered[:rows, :cols]] = layer[:rows, :cols][covered[:rows, :cols]]
    img = canvas.decorate(Image.fromarray(arr), title)
    draw = ImageDraw.Draw(img)
    font = refview._font(13)
    x = max(left, 140)  # right of the axis name that decorate() puts in the top left
    for colour, label in (
        (MODEL_ONLY, f"model only ({score.model_px - score.both_px} px)"),
        (ASSET_ONLY, f"asset only ({score.asset_px - score.both_px} px)"),
        (BOTH, f"both ({score.both_px} px)"),
    ):
        draw.rectangle([x, 26, x + 13, 39], fill=colour, outline=refview.INK)
        draw.text((x + 19, 33), label, fill=refview.INK, font=font, anchor="lm")
        x += 40 + int(draw.textlength(label, font=font))
    img.save(path)


def view_report(score: ViewScore) -> dict:
    return {
        "iou": round(score.iou, 4),
        "iou_unshifted": round(score.iou_unshifted, 4),
        "model_px": score.model_px,
        "asset_px": score.asset_px,
        "both_px": score.both_px,
        "model_only_px": score.model_px - score.both_px,
        "asset_only_px": score.asset_px - score.both_px,
        "grid_px": [score.grid.shape[1], score.grid.shape[0]],
    }


def parse_vec3(text: str) -> np.ndarray:
    try:
        values = [float(v) for v in text.split(",")]
    except ValueError as exc:
        raise ValueError(f"{text!r} is not three numbers x,y,z") from exc
    if len(values) != 3:
        raise ValueError(f"{text!r} is not three numbers x,y,z")
    return np.array(values)


def check_range(label: str, values: list[float] | None) -> list[float] | None:
    if values is not None and not values[0] < values[1]:
        raise ValueError(f"--{label}-zrange {values[0]:g} {values[1]:g}: the start must lie below the end")
    return values


def default_out(name: str, part: str | None) -> Path:
    out = refview.default_out(name) / "compare"
    return out / part if part else out


def pod_mounts(args: argparse.Namespace, folder: Path) -> list[tuple[np.ndarray, np.ndarray]]:
    mounts = [(parse_vec3(text), np.array([0.0, 1.0, 0.0])) for text in args.pod_at]
    if args.pods_from_hardpoints:
        path = folder / "hardpoints.json"
        try:
            pods = json.loads(path.read_text())["cargo_pods"]
            mounts += [(np.asarray(p["position"], dtype=float), np.asarray(p.get("up", [0.0, 1.0, 0.0]), dtype=float)) for p in pods]
        except (OSError, ValueError, KeyError, TypeError) as exc:
            raise ValueError(f"{path}: no readable cargo_pods[] ({exc})") from exc
    return mounts


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("stl", type=Path)
    ap.add_argument("asset", help="an asset id under assets/generated/ or a path to an asset folder")
    ap.add_argument("--name", default=None, help="output folder under reports/refs/ (default: the asset folder's name)")
    ap.add_argument("--part", default=None, help="label of the part being scored; its result goes in a folder of that name")
    ap.add_argument("--length", type=float, default=None, help="metres along the aft axis (default: file units)")
    ap.add_argument("--right", default="+x", help="file axis pointing to starboard, e.g. -y")
    ap.add_argument("--up", default="+y", help="file axis pointing up")
    ap.add_argument("--aft", default="+z", help="file axis pointing from the nose to the engines")
    ap.add_argument("--model-offset", default=None, metavar="X,Y,Z", help="metres added to the model's coordinates, for a generator whose origin is not the model's box centre")
    ap.add_argument("--model-zrange", nargs=2, type=float, default=None, metavar=("Z0", "Z1"), help="keep this z range (m) of the model")
    ap.add_argument("--asset-zrange", nargs=2, type=float, default=None, metavar=("Z0", "Z1"), help="keep this z range (m) of the asset")
    ap.add_argument("--pod-ply", type=Path, default=None, help="splat file of a removable part, drawn at every mount")
    ap.add_argument("--pod-at", action="append", default=[], metavar="X,Y,Z", help="a mount in the body frame (repeatable)")
    ap.add_argument("--pods-from-hardpoints", action="store_true", help="mounts from the asset's hardpoints.json cargo_pods[]")
    ap.add_argument("--pixel-frac", type=float, default=PIXEL_FRACTION, help=f"pixel as a share of the length (at most {PIXEL_FRACTION_MAX})")
    ap.add_argument("--out", type=Path, default=None, help="output folder (default: reports/refs/<name>/compare)")
    args = ap.parse_args(argv)

    try:
        model_range, asset_range = check_range("model", args.model_zrange), check_range("asset", args.asset_zrange)
        raw, fmt = refview.read_stl(args.stl)
        rotation = refview.frame_matrix(args.right, args.up, args.aft)
        tris, _ = refview.to_ship_frame(raw, rotation, args.length)
        model_offset = parse_vec3(args.model_offset) if args.model_offset else np.zeros(3)
        tris = tris + model_offset
        folder = resolve_asset(args.asset)
        manifest = read_asset_manifest(folder)
        splats = load_asset_splats(folder)

        mounts = pod_mounts(args, folder)
        pod_file = args.pod_ply
        if mounts and pod_file is None:
            default_pod = folder / f"{folder.name}_pod.ply"
            if not default_pod.is_file():
                raise ValueError("pod mounts need --pod-ply FILE (no <id>_pod.ply beside the asset)")
            pod_file = default_pod
        if pod_file is not None and not mounts:
            raise ValueError(f"--pod-ply {pod_file} needs mounts: --pod-at X,Y,Z or --pods-from-hardpoints")
        if mounts:
            if not Path(pod_file).is_file():
                raise ValueError(f"{pod_file}: no such pod file")
            splats = SplatSet.concatenate([splats, *place_parts(Path(pod_file), mounts, np.asarray(manifest["centroid_offset"], dtype=float))])

        if model_range is not None:
            tris = clip_slab(tris, 2, *model_range)
            if len(tris) == 0:
                raise ValueError(f"the model has no triangles within z {model_range[0]:g}..{model_range[1]:g} m")
            tris = tris - np.array([0.0, 0.0, model_range[0]])
        if asset_range is not None:
            splats = splats.cropped(2, *asset_range)
            if len(splats) == 0:
                raise ValueError(f"the asset has no splats within z {asset_range[0]:g}..{asset_range[1]:g} m")
            splats = SplatSet(splats.centres - np.array([0.0, 0.0, asset_range[0]]), splats.cov)
        length_ref = float(np.ptp(tris[..., 2]))
        if length_ref <= 0.0:
            raise ValueError("the model has no extent along z")
        comp = compare_shapes(tris, splats, length_ref, pixel_fraction=args.pixel_frac)
    except (OSError, ValueError) as exc:
        print(f"compare: {exc}", file=sys.stderr)
        return 2

    name = args.name or folder.name
    out = args.out / args.part if (args.out and args.part) else (args.out or default_out(name, args.part))
    out.mkdir(parents=True, exist_ok=True)
    label = f"{name} / {args.part}" if args.part else name
    shift = ", ".join(f"{v:+.2f}" for v in comp.shift_m)
    for view in VIEWS:
        write_overlay(out / f"overlay_{view}.png", comp, view, f"{label}: {view}, IoU {comp.views[view].iou:.3f}, asset moved ({shift}) m")

    ious = {n: s.iou for n, s in comp.views.items()}
    failures = judge(ious, comp.ratios)
    report = {
        "name": name,
        "part": args.part,
        "model": {
            "stl": args.stl.name,
            "format": fmt,
            "triangles": int(len(tris)),
            "zrange": model_range,
            "offset_m": [round(float(v), 4) for v in model_offset],
            "dims_m": {n: round(v, 3) for n, v in comp.model_dims.items()},
        },
        "asset": {
            "id": manifest["asset_id"],
            "dir": str(folder),
            "lod0": manifest["lods"][0]["file"],
            "splats": int(len(splats)),
            "extra_parts": len(mounts),
            "zrange": asset_range,
            "centroid_offset": manifest["centroid_offset"],
            "dims_m": {n: round(v, 3) for n, v in comp.asset_dims.items()},
        },
        "mapping": {"right": args.right, "up": args.up, "aft": args.aft},
        "length_m": round(length_ref, 3),
        "splat_sigmas": SPLAT_SIGMAS,
        "pixel_m": round(comp.pixel_m, 5),
        "shift_m": [round(float(v), 4) for v in comp.shift_m],
        "shift_limit_m": round(comp.shift_limit_m, 4),
        "shift_at_limit": list(comp.at_limit),
        "centre_gap_m": [round(float(v), 4) for v in comp.centre_gap_m],
        "views": {n: view_report(s) for n, s in comp.views.items()},
        "dimensions": {
            n: {"model_m": round(comp.model_dims[n], 3), "asset_m": round(comp.asset_dims[n], 3), "ratio": round(comp.ratios[n], 4)}
            for n in DIMENSIONS
        },
        "thresholds": {"iou_min": IOU_MIN, "dimension_tolerance": DIM_TOLERANCE, "shift_fraction": SHIFT_FRACTION},
        "failures": failures,
        "verdict": "fail" if failures else "pass",
    }
    (out / "fidelity.json").write_text(json.dumps(report, indent=1) + "\n")

    print(f"{label}: {args.stl.name} against {manifest['asset_id']} LOD0 ({len(splats)} splats), length {length_ref:.1f} m, pixel {comp.pixel_m:.3f} m -> {out}")
    for view, score in comp.views.items():
        mark = "ok  " if score.iou >= IOU_MIN - 1e-9 else "LOW "
        print(f"{view:<6} IoU {score.iou:.3f} {mark} (unshifted {score.iou_unshifted:.3f})  model {score.model_px} px  asset {score.asset_px} px  both {score.both_px} px")
    print("size   " + "  ".join(f"{n} {comp.ratios[n]:.3f} ({comp.asset_dims[n]:.1f}/{comp.model_dims[n]:.1f} m)" for n in DIMENSIONS) + "  (asset / model)")
    print(f"shift  asset moved ({shift}) m of at most {comp.shift_limit_m:.2f} m per axis")
    if any(comp.at_limit[:2]) or float(np.abs(comp.centre_gap_m[:2]).max()) > comp.shift_limit_m:
        # A generator authoring about another origin (the Saturns measure y from the spine axis) looks like this.
        gap = ",".join(f"{v:.2f}" for v in (comp.centre_gap_m[0], comp.centre_gap_m[1], 0.0))
        print(f"note   the boxes' centres differ by {gap} m (x,y,z) beyond the shift limit; if only the origin differs, try --model-offset {gap}")
    print("verdict: " + ("PASS" if not failures else "FAIL (" + "; ".join(failures) + ")"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
