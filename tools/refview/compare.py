"""Fidelity check of a built civilian asset against its reference STL (M5-T23, Q18).

Every civilian model must lie within 90 % of its STL, measured as silhouettes and size. This tool is the measuring
stick. It puts the STL (in the same ship frame and at the same length as ``refview.py``) and the asset's **geometry**,
its fallback mesh ``<id>.obj`` (every civilian generator builds it from the same parts as its splats), on one grid,
draws the top, side and front silhouettes of both, and scores each view's intersection over union (IoU) together with
the length, width and height of asset against model. The bar is an IoU of at least 0.90 in every view and every
dimension within 10 %: the *geometry verdict*. A second check, the *splat check*, keeps the LOD0 splats honest against
their own mesh, per view and with a band one LOD0 spacing wide (the manifest's LOD0 spacing, else derived from the
splat scales), on a grid of a third of that spacing whatever the ship's length: at least 95 % of the mesh silhouette must be covered by splats (nothing missing) and at least 95 % of the
splat silhouette must lie within the mesh silhouette grown by one spacing (nothing misplaced). A splat reaches about 0.75
spacings past an edge whatever the setting, so a plain overlap would fail faithful thin parts; the band does not. Nothing
from the STL is kept: overlays and numbers go to the gitignored ``reports/refs/<name>/compare/``.

Usage, with the project's venv and isolated mode::

    .venv/bin/python3 -I tools/refview/compare.py references/EA_Saturn_4_transport.stl saturn_4_transport \\
        --length 158.5 --model-offset 0,-3.643,0 --right=-x --up=+z --aft=+y

The second argument is an asset id (a folder under ``assets/generated/``) or a path to an asset folder. The STL takes the
same ``--length``, ``--right``, ``--up`` and ``--aft`` as ``refview.py``; the mappings of the civilian ships are in
``docs/design-references.md``. Exit status: 0 when both checks pass, 1 when either does not, 2 on bad input.

How the two sides are put on one grid
-------------------------------------
* The model is in the authored frame: x to starboard, y up, z aft from the nose tip (z = 0), metres, x and y centred on
  the model's box (``refview.to_ship_frame``). A generator that authors about another origin (the Saturns measure y
  from the spine axis) shows it as a shift; ``--model-offset X,Y,Z`` moves the model onto that origin. When the
  silhouettes only meet further away than the shift window, the output suggests a value (found by a wider silhouette
  search, not from the boxes).
* The asset's mesh and LOD0 PLY are stored as the generators write them, centred on the splat centroid:
  ``manifest.centroid_offset`` is the authored position of that origin. The OBJ is in the Godot frame as it is, so the
  tool adds the offset; the PLY is also turned by Rz(180) into the GDGS orientation (``core.frames``), which the tool
  undoes on positions and rotations before adding the offset.
* The geometry check's pixel is ``PIXEL_FRACTION`` of the length (never above 0.5 %). The asset may then move by a whole
  number of pixels in x, y and z, up to 2 % of the length each, to the place where the three views overlap best; the
  shift is reported and the geometry scores are those at that place (``iou_unshifted`` in the JSON is the score without
  it). The splat check takes no shift (splats and mesh come from the same parts in the same frame) and has its own grid:
  a pixel of a third of the LOD0 spacing, so its band is exactly three pixels and its numbers do not depend on the ship's
  length, the crop or ``--pixel-frac``.
* Each splat of the splat check is drawn as the orthographic projection of its Gaussian: an ellipse, not a disc, so a
  flat splat seen edge-on is a thin line and a closed hull is not grown by the splat size at its horizon. The ellipse
  reaches ``SPLAT_SIGMAS`` sigmas from the centre (see the constant for why).
* ``--model-zrange`` and ``--asset-zrange`` keep one part of each side so a ship is scored part by part against the
  model each part was built from (the Saturns, Q16). Meshes are cut exactly at the planes and splats are kept by centre; a
  plane inside a ship is nudged by a tenth of a millimetre so a face lying in it belongs to the neighbouring part. Each
  cropped side starts at z = 0, and the asset part is then aligned on its own: moved in x and y so that its box
  centre meets the model part's (a part placed differently by design, like the Saturn 3's raised stack, is scored for
  shape), then the usual best-fit shift. The move is reported (``part_align_m``). ``--part NAME`` puts the result in its
  own folder.
* ``--model-scale SX,SY,SZ`` scales the (cropped) model about its own box centre in x and y and its start in z: a part
  whose size the maintainer set apart from the model (the Saturn 3's shared pods, Q20) is scored for shape and layout
  at that size. ``--model-offset`` is for the whole ship; a cropped part aligns itself.
* Extra parts (the Bokmai's removable pods) are drawn with the hull: ``--pod-obj FILE`` and ``--pod-ply FILE`` are the
  pod's mesh and splats in the pod's own frame (by default ``<id>_pod.obj`` and ``<id>_pod.ply`` beside the asset), put
  at every mount from ``--pod-at X,Y,Z`` (body frame, repeatable) and ``--pods-from-hardpoints`` (the asset's
  ``hardpoints.json`` ``cargo_pods[]``, whose ``position``, ``up`` and optional ``forward`` are in the body frame, as the
  other hardpoints are). The pod's +y is turned onto ``up`` and its forward (-z) onto ``forward``; without ``forward``
  the shortest turn is used.
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
from tools.procgen.core.obj import read_obj  # noqa: E402
from tools.procgen.core.ply import read_ply  # noqa: E402
from tools.refview import refview  # noqa: E402

GENERATED = REPO_ROOT / "assets" / "generated"

IOU_MIN = 0.90  # each view's intersection over union must reach this (Q18)
DIM_TOLERANCE = 0.10  # length, width and height of asset / model within this of 1 (Q18)
SPLAT_COVERAGE_MIN = 0.95  # splat check: this share of the mesh silhouette is covered by splats (nothing missing)
SPLAT_PRECISION_MIN = 0.95  # ... and this share of the splat silhouette lies within one spacing of the mesh's (nothing misplaced)
SHIFT_FRACTION = 0.02  # the best-fit shift of the asset: at most this share of the length, per axis
PIXEL_FRACTION = 0.0025  # default pixel as a share of the length
PIXEL_FRACTION_MAX = 0.005  # the brief's coarsest allowed pixel
SPLAT_PIXELS_PER_SPACING = 3  # the splat check's pixel is the LOD0 spacing over this; the band is this many pixels
SPACING_TOLERANCE = 0.10  # a declared LOD0 spacing this far from the one the splat scales imply fails the splat check
HINT_PIXEL_FRACTION = 0.01  # the wider search behind the --model-offset hint runs on a coarser grid
HINT_WINDOW = 0.10  # ... over this share of the length each way in x and y
CROP_EPS = 1e-4  # m; a crop plane inside a ship moves this far inward, so a face lying in it is not kept face-on
# How far a splat is taken to reach, in sigmas. The generators put about one splat per spacing^2 on the surface, each
# with a sigma of one spacing, and the centres sit on the mesh, so a surface cell is a disc of about 0.56 spacings. The
# value is calibrated on three built assets against their own fallback meshes (the silhouettes the splats were sampled
# from): the mean IoU over the three views peaks at 0.7 to 0.8 sigmas for the raider (0.91), the Narn transport (0.96) and
# the Starfury (0.96); 1.0 grows every edge by about half a spacing and 0.5 leaves holes. Splats near an edge reach about
# 0.75 spacings past it whatever the factor, so a thin part reads lower than a thick one: that is why the verdict is
# scored on the mesh and the splats only against it.
SPLAT_SIGMAS = 0.75

MODEL_ONLY = (232, 128, 24)  # orange
ASSET_ONLY = (36, 112, 224)  # blue
BOTH = (64, 64, 64)  # dark grey
OUTSIDE = (200, 30, 40)  # red: splat pixels beyond the one-spacing band (the splat check's misplaced part)

# This tool's names for the three silhouettes and refview's views they are drawn from.
VIEWS = {"top": "top", "side": "port", "front": "front"}
DIMENSIONS = {"length": 2, "width": 0, "height": 1}  # name -> ship axis
MAX_GRID_PIXELS = 60_000_000
BAD_DATA = (OSError, ValueError, KeyError, IndexError, TypeError)  # what malformed input raises; main() turns it into exit 2


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


def crop_planes(lo: float, hi: float, z_min: float, z_max: float) -> tuple[float, float]:
    """The crop range for a side that spans ``z_min..z_max``: a plane inside the side moves inward by ``CROP_EPS``, so a
    face lying exactly in it (the neighbouring part's cap) is dropped; a plane at or beyond the side's own end stays."""
    return (lo + CROP_EPS if lo > z_min + CROP_EPS else lo), (hi - CROP_EPS if hi < z_max - CROP_EPS else hi)


def crop_triangles(tris: np.ndarray, lo: float, hi: float, z_min: float, z_max: float) -> np.ndarray:
    return clip_slab(tris, 2, *crop_planes(lo, hi, z_min, z_max))


# --- splats and meshes -----------------------------------------------------------------------------------------------
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

    def moved(self, offset: np.ndarray) -> SplatSet:
        return SplatSet(self.centres + offset, self.cov)

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


def mesh_from_obj(path: Path, offset: np.ndarray) -> np.ndarray:
    """Triangles ``(n, 3, 3)`` of a generator's OBJ in the authored frame. The OBJ is written in the Godot frame centred on
    the splat centroid, like the splats after their flip, so only ``offset`` is added back."""
    try:
        obj = read_obj(path)
        tris = obj.vertices[obj.faces]
    except (OSError, ValueError, IndexError, UnicodeDecodeError) as exc:
        raise ValueError(f"{path}: cannot read the fallback mesh ({exc})") from exc
    if len(tris) == 0:
        raise ValueError(f"{path}: the fallback mesh has no triangles")
    return tris + np.asarray(offset, dtype=np.float64)


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


def _centroid_offset(manifest: dict) -> np.ndarray:
    return np.asarray(manifest["centroid_offset"], dtype=np.float64)


def load_asset_splats(folder: Path) -> SplatSet:
    """The LOD0 splats of the asset in ``folder``, in the authored frame."""
    manifest = read_asset_manifest(Path(folder))
    return splats_from_ply(Path(folder) / manifest["lods"][0]["file"], _centroid_offset(manifest))


def load_asset_mesh(folder: Path) -> np.ndarray:
    """The fallback mesh of the asset in ``folder`` (``files.fallback_mesh``, else ``<id>.obj``), in the authored frame."""
    manifest = read_asset_manifest(Path(folder))
    name = manifest.get("files", {}).get("fallback_mesh") or f"{manifest['asset_id']}.obj"
    return mesh_from_obj(Path(folder) / name, _centroid_offset(manifest))


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


def pod_rotation(up: np.ndarray, forward: np.ndarray | None = None) -> np.ndarray:
    """A pod's turn into the body frame: +y onto ``up`` and, when given, the pod's forward (-z) onto ``forward`` (its part
    across ``up``), so a pod that is not fore-aft symmetric faces the right way. Without ``forward``: the shortest turn."""
    u = np.asarray(up, dtype=np.float64)
    if forward is not None and np.linalg.norm(u) > 1e-12:
        u = u / np.linalg.norm(u)
        f = np.asarray(forward, dtype=np.float64)
        f = f - u * float(f @ u)
        if np.linalg.norm(f) > 1e-9:
            z = -f / np.linalg.norm(f)
            return np.stack([np.cross(u, z), u, z], axis=1)
    return rotation_to_up(up)


@dataclass
class Mount:
    """A removable part's place in the body frame: where its origin sits, which way is up and (optionally) forward."""

    position: np.ndarray
    up: np.ndarray
    forward: np.ndarray | None = None


def place_parts(
    part_mesh: np.ndarray, part_splats: SplatSet, mounts: list[Mount], centroid_offset: np.ndarray
) -> tuple[np.ndarray, SplatSet]:
    """One copy of the part (mesh and splats) at every mount, in the authored frame."""
    meshes, splats = [], []
    for m in mounts:
        r = pod_rotation(m.up, m.forward)
        t = np.asarray(m.position, dtype=np.float64) + centroid_offset
        meshes.append(part_mesh @ r.T + t)
        splats.append(part_splats.transformed(r, t))
    return np.concatenate(meshes), SplatSet.concatenate(splats)


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
    """One view's two silhouettes: ``model_mask`` is the reference side (the STL, or the mesh in the splat check) and
    ``asset_mask`` the side scored against it (after the best-fit shift)."""

    grid: ViewGrid
    iou: float
    iou_unshifted: float
    model_mask: np.ndarray
    asset_mask: np.ndarray

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
    """The geometry check: the STL against the asset's mesh."""

    views: dict[str, ViewScore]
    shift_m: np.ndarray
    shift_limit_m: float
    pixel_m: float
    model_dims: dict[str, float]
    asset_dims: dict[str, float]
    ratios: dict[str, float] = field(default_factory=dict)
    at_limit: tuple[bool, bool, bool] = (False, False, False)  # the best-fit shift reached its limit on x, y, z


@dataclass
class SplatView(ViewScore):
    """One view of the splat check: ``model_mask`` is the mesh's silhouette and ``asset_mask`` the splats'. ``coverage`` is
    the share of the mesh's pixels the splats cover; ``precision`` the share of the splats' pixels within the band (the
    mesh silhouette dilated by one spacing); ``outside`` marks the splat pixels beyond the band."""

    coverage: float = 0.0
    precision: float = 0.0
    band_px: float = 1.0
    outside: np.ndarray = field(default_factory=lambda: np.zeros((0, 0), dtype=bool))

    @property
    def outside_px(self) -> int:
        return int(self.outside.sum())


@dataclass
class SplatCheck:
    """The splat check: the LOD0 splats against their own mesh (no shift), with a band one LOD0 spacing wide."""

    views: dict[str, SplatView]
    pixel_m: float
    spacing_m: float
    spacing_source: str


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


def _check_pixel(pixel_fraction: float) -> None:
    if pixel_fraction > PIXEL_FRACTION_MAX + 1e-12 or pixel_fraction <= 0.0:
        raise ValueError(f"the pixel must be at most {PIXEL_FRACTION_MAX:.1%} of the length (got {pixel_fraction:g})")


def _bounds(tris: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    verts = tris.reshape(-1, 3)
    return verts.min(axis=0), verts.max(axis=0)


def _masks(model_tris: np.ndarray, asset_tris: np.ndarray, px: float, pad_px: int) -> tuple[dict, dict]:
    """The three views' grids over both shapes and their two silhouettes each."""
    (m_lo, m_hi), (a_lo, a_hi) = _bounds(model_tris), _bounds(asset_tris)
    lo, hi = np.minimum(m_lo, a_lo), np.maximum(m_hi, a_hi)
    grids = {name: view_grid(name, lo, hi, px, pad_px) for name in VIEWS}
    return grids, {name: (triangle_mask(model_tris, g), triangle_mask(asset_tris, g)) for name, g in grids.items()}


def _best_move(grids: dict, masks: dict, reach: int, free: tuple[bool, bool, bool] = (True, True, True)):
    """The whole-pixel move of the asset, one for all three views, with the best mean overlap (the smallest move among
    equals); ``free`` names the ship axes that may move. Returns the move, the per-view tables and the mean IoU there."""
    tables = {name: shift_table(m[0], m[1], reach) for name, m in masks.items()}
    steps = np.arange(-reach, reach + 1)
    moves = np.stack(np.meshgrid(*[steps if f else np.zeros(1, dtype=np.int64) for f in free], indexing="ij"), axis=-1).reshape(-1, 3)
    score = np.zeros(len(moves))
    for name, grid in grids.items():
        basis = np.rint(grid.basis).astype(np.int64)
        score += tables[name][-(moves @ basis[1]) + reach, moves @ basis[0] + reach]
    best = int(np.lexsort(((moves**2).sum(axis=1), -np.round(score, 9)))[0])
    return moves[best], tables, float(score[best]) / len(grids)


def compare_shapes(
    model_tris: np.ndarray,
    asset_tris: np.ndarray,
    length_ref: float,
    pixel_fraction: float = PIXEL_FRACTION,
    shift_fraction: float = SHIFT_FRACTION,
) -> Comparison:
    """The geometry check: the asset's triangles against the model's, both in the authored frame, on grids whose pixel is
    ``pixel_fraction`` of ``length_ref``; the asset may move up to ``shift_fraction`` of it on each axis."""
    _check_pixel(pixel_fraction)
    if len(model_tris) == 0 or len(asset_tris) == 0:
        raise ValueError("nothing to compare: the model or the asset is empty")
    px = pixel_fraction * length_ref
    reach = int(round(shift_fraction * length_ref / px))
    grids, masks = _masks(model_tris, asset_tris, px, reach + 1)
    move, tables, _ = _best_move(grids, masks, reach)

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
    (m_lo, m_hi), (a_lo, a_hi) = _bounds(model_tris), _bounds(asset_tris)
    model_dims = {n: float(m_hi[a] - m_lo[a]) for n, a in DIMENSIONS.items()}
    asset_dims = {n: float(a_hi[a] - a_lo[a]) for n, a in DIMENSIONS.items()}
    ratios = {n: asset_dims[n] / max(model_dims[n], 1e-9) for n in DIMENSIONS}
    at_limit = tuple(bool(abs(int(v)) >= reach) for v in move)
    return Comparison(views, move * px, shift_fraction * length_ref, px, model_dims, asset_dims, ratios, at_limit)


def dilate(mask: np.ndarray, radius_px: float) -> np.ndarray:
    """The mask grown by a disc of ``radius_px`` pixels (rows of runs, each run by a running sum)."""
    r = int(math.floor(radius_px))
    if r < 1:
        return mask.copy()
    h, w = mask.shape
    runs: dict[int, np.ndarray] = {}

    def widened(k: int) -> np.ndarray:
        if k not in runs:
            padded = np.pad(mask.astype(np.int32), ((0, 0), (k, k)))
            total = np.concatenate([np.zeros((h, 1), dtype=np.int32), np.cumsum(padded, axis=1)], axis=1)
            runs[k] = (total[:, 2 * k + 1 : 2 * k + 1 + w] - total[:, :w]) > 0
        return runs[k]

    out = np.zeros_like(mask)
    for dy in range(-r, r + 1):
        half = int(math.floor(math.sqrt(max(radius_px * radius_px - dy * dy, 0.0))))
        row = widened(half)
        if dy >= 0:
            out[dy:] |= row[: h - dy]
        else:
            out[:dy] |= row[-dy:]
    return out


def _positive(v: object) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0.0


def _overlap(manifest: dict) -> float:
    sampling = manifest.get("sampling")
    overlap = sampling.get("overlap") if isinstance(sampling, dict) else None
    return float(overlap) if _positive(overlap) else 1.0


def derived_spacing(manifest: dict, splats: SplatSet) -> float:
    """The LOD0 spacing the splat scales imply: the largest sigma is ``overlap * spacing`` (overlap from ``sampling`` or 1,
    the generators' default)."""
    sigma = np.sqrt(np.max(np.einsum("nii->ni", splats.cov), axis=1))
    return float(np.median(sigma)) / _overlap(manifest)


def splat_spacing(manifest: dict, splats: SplatSet) -> tuple[float, str]:
    """The asset's LOD0 sampling spacing and where it came from: the manifest's ``lods[0].spacing_m``, else its
    ``sampling.spacing_m``, else derived from the splat scales."""
    lods = manifest.get("lods")
    lod0 = lods[0] if isinstance(lods, list) and lods and isinstance(lods[0], dict) else {}
    if _positive(lod0.get("spacing_m")):
        return float(lod0["spacing_m"]), "manifest lods[0].spacing_m"
    sampling = manifest.get("sampling")
    spacing = sampling.get("spacing_m") if isinstance(sampling, dict) else None
    if _positive(spacing):
        return float(spacing), "manifest sampling.spacing_m"
    return derived_spacing(manifest, splats), f"derived from the splat scales (overlap {_overlap(manifest):g})"


def spacing_mismatch(manifest: dict, splats: SplatSet, spacing: float, source: str) -> str | None:
    """A failure when a declared spacing disagrees with the splats themselves, so a generator cannot widen the band by
    declaring a coarser spacing than it sampled at. ``None`` when it agrees or was derived."""
    if source.startswith("derived"):
        return None
    implied = derived_spacing(manifest, splats)
    if abs(spacing / max(implied, 1e-12) - 1.0) > SPACING_TOLERANCE + 1e-9:
        return f"splats spacing {spacing:g} m ({source}) is off the {implied:.3f} m the splat scales imply by more than {SPACING_TOLERANCE:.0%}"
    return None


def check_splats(
    mesh_tris: np.ndarray,
    splats: SplatSet,
    spacing: float,
    spacing_source: str = "given",
    sigmas: float = SPLAT_SIGMAS,
) -> SplatCheck:
    """The splat check: the splats' silhouettes against their own mesh's, in place (no shift), on a grid of a third of
    ``spacing`` so the numbers depend on the sampling alone. Per view, coverage is the share of the mesh silhouette the
    splats cover and precision the share of the splat silhouette inside the mesh silhouette grown by one ``spacing``. A
    faithful thin part passes (splats reach about 0.75 spacings past an edge); a missing part fails coverage and a part
    moved by several spacings fails precision."""
    if len(mesh_tris) == 0 or len(splats) == 0:
        raise ValueError("nothing to compare: the mesh or the splats are empty")
    if not spacing > 0.0:
        raise ValueError(f"the LOD0 spacing must be positive (got {spacing:g})")
    px = spacing / SPLAT_PIXELS_PER_SPACING
    band_px = float(SPLAT_PIXELS_PER_SPACING)
    (m_lo, m_hi), (s_lo, s_hi) = _bounds(mesh_tris), splats.bounds(sigmas)
    lo, hi = np.minimum(m_lo, s_lo), np.maximum(m_hi, s_hi)
    a, b = sorted(float(v) for v in (hi - lo))[1:]
    if (a / px + 2 * band_px + 2) * (b / px + 2 * band_px + 2) > MAX_GRID_PIXELS:
        raise ValueError(f"a spacing of {spacing:g} m is too fine for a {b:.1f} m part (a view over {MAX_GRID_PIXELS} pixels)")
    views = {}
    for name in VIEWS:
        grid = view_grid(name, lo, hi, px, int(band_px) + 1)
        mesh_mask, splat_mask_ = triangle_mask(mesh_tris, grid), splat_mask(splats, grid, sigmas)
        both = int((mesh_mask & splat_mask_).sum())
        union = int((mesh_mask | splat_mask_).sum())
        outside = splat_mask_ & ~dilate(mesh_mask, band_px)
        views[name] = SplatView(
            grid,
            both / max(union, 1),
            both / max(union, 1),
            mesh_mask,
            splat_mask_,
            coverage=both / max(int(mesh_mask.sum()), 1),
            precision=1.0 - int(outside.sum()) / max(int(splat_mask_.sum()), 1),
            band_px=band_px,
            outside=outside,
        )
    return SplatCheck(views, px, spacing, spacing_source)


def suggest_offset(model_tris: np.ndarray, asset_tris: np.ndarray, length_ref: float) -> tuple[np.ndarray, float, float]:
    """Where the asset would sit best against the model if its origin were elsewhere: a wider silhouette search in x and y
    (``HINT_WINDOW`` of the length each way, on a coarser grid). Returns the move of the asset in metres, the mean IoU
    there and the mean IoU unmoved. The model's offset is minus the move."""
    px = HINT_PIXEL_FRACTION * length_ref
    reach = int(round(HINT_WINDOW / HINT_PIXEL_FRACTION))
    grids, masks = _masks(model_tris, asset_tris, px, reach + 1)
    move, tables, best = _best_move(grids, masks, reach, free=(True, True, False))
    unmoved = float(np.mean([t[reach, reach] for t in tables.values()]))
    return move * px, best, unmoved


def judge(ious: dict[str, float], ratios: dict[str, float]) -> list[str]:
    """What fails the geometry bar (Q18): a view under ``IOU_MIN`` or a dimension off by more than ``DIM_TOLERANCE``.
    Empty = pass."""
    failures = [f"{name} IoU {v:.3f} is under {IOU_MIN:.2f}" for name, v in ious.items() if v < IOU_MIN - 1e-9]
    failures += [
        f"{name} ratio {r:.3f} is off by more than {DIM_TOLERANCE:.0%}" for name, r in ratios.items() if abs(r - 1.0) > DIM_TOLERANCE + 1e-9
    ]
    return failures


def judge_splats(coverage: dict[str, float], precision: dict[str, float]) -> list[str]:
    """What fails the splat check: a view whose splats cover under ``SPLAT_COVERAGE_MIN`` of the mesh silhouette (something
    is missing) or whose splat silhouette lies under ``SPLAT_PRECISION_MIN`` within the band (something is misplaced)."""
    failures = [f"splats {n} coverage {v:.3f} is under {SPLAT_COVERAGE_MIN:.2f}" for n, v in coverage.items() if v < SPLAT_COVERAGE_MIN - 1e-9]
    failures += [f"splats {n} precision {v:.3f} is under {SPLAT_PRECISION_MIN:.2f}" for n, v in precision.items() if v < SPLAT_PRECISION_MIN - 1e-9]
    return failures


# --- placing the two sides -------------------------------------------------------------------------------------------
def scale_about_part(tris: np.ndarray, factors: np.ndarray) -> np.ndarray:
    """Triangles scaled per axis about the part's own box centre in x and y and its start in z."""
    lo, hi = _bounds(tris)
    pivot = np.array([0.5 * (lo[0] + hi[0]), 0.5 * (lo[1] + hi[1]), lo[2]])
    return (tris - pivot) * factors + pivot


def part_alignment(model_tris: np.ndarray, asset_tris: np.ndarray) -> np.ndarray:
    """The move of the asset part that puts its box centre on the model part's in x and y (z starts at the crop start on
    both sides already)."""
    (m_lo, m_hi), (a_lo, a_hi) = _bounds(model_tris), _bounds(asset_tris)
    return np.array([0.5 * ((m_lo + m_hi) - (a_lo + a_hi))[0], 0.5 * ((m_lo + m_hi) - (a_lo + a_hi))[1], 0.0])


# --- outputs ---------------------------------------------------------------------------------------------------------
def write_overlay(path: Path, views: dict[str, ViewScore], view: str, title: str, names: tuple[str, str] = ("model", "asset")) -> None:
    """The view's silhouettes in three colours (reference only, scored only, both) on the metre grid, with legend and scale."""
    score = views[view]
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
    outside = getattr(score, "outside", None)
    banded = outside is not None and outside.shape == score.asset_mask.shape
    if banded:
        paint[outside] = OUTSIDE
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
    entries = [(MODEL_ONLY, f"{names[0]} only ({score.model_px - score.both_px} px)")]
    if banded:
        entries += [
            (ASSET_ONLY, f"{names[1]} in the band ({score.asset_px - score.both_px - score.outside_px} px)"),
            (OUTSIDE, f"{names[1]} beyond it ({score.outside_px} px)"),
        ]
    else:
        entries.append((ASSET_ONLY, f"{names[1]} only ({score.asset_px - score.both_px} px)"))
    entries.append((BOTH, f"both ({score.both_px} px)"))
    for colour, label in entries:
        draw.rectangle([x, 26, x + 13, 39], fill=colour, outline=refview.INK)
        draw.text((x + 19, 33), label, fill=refview.INK, font=font, anchor="lm")
        x += 40 + int(draw.textlength(label, font=font))
    img.save(path)


def view_report(score: ViewScore) -> dict:
    extra = {}
    if isinstance(score, SplatView):
        extra = {
            "coverage": round(score.coverage, 4),
            "precision": round(score.precision, 4),
            "band_px": round(score.band_px, 3),
            "outside_px": score.outside_px,
        }
    return extra | {
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


def pod_mounts(args: argparse.Namespace, folder: Path) -> list[Mount]:
    mounts = [Mount(parse_vec3(text), np.array([0.0, 1.0, 0.0])) for text in args.pod_at]
    if args.pods_from_hardpoints:
        path = folder / "hardpoints.json"
        try:
            pods = json.loads(path.read_text())["cargo_pods"]
            for p in pods:
                forward = p.get("forward")
                mounts.append(
                    Mount(
                        np.asarray(p["position"], dtype=float),
                        np.asarray(p.get("up", [0.0, 1.0, 0.0]), dtype=float),
                        None if forward is None else np.asarray(forward, dtype=float),
                    )
                )
        except BAD_DATA as exc:
            raise ValueError(f"{path}: no readable cargo_pods[] ({type(exc).__name__}: {exc})") from exc
    return mounts


def pod_files(args: argparse.Namespace, folder: Path) -> tuple[Path, Path]:
    """The pod's splat file and mesh: named on the command line (the mesh beside the splats when only they are named) or
    ``<id>_pod.ply`` and ``<id>_pod.obj`` beside the asset."""
    ply = args.pod_ply or (args.pod_obj.with_suffix(".ply") if args.pod_obj else folder / f"{folder.name}_pod.ply")
    obj = args.pod_obj or (args.pod_ply.with_suffix(".obj") if args.pod_ply else folder / f"{folder.name}_pod.obj")
    for path in (ply, obj):
        if not Path(path).is_file():
            raise ValueError(f"{path}: no such pod file (pod mounts need --pod-ply FILE and --pod-obj FILE, or <id>_pod.ply and <id>_pod.obj beside the asset)")
    return Path(ply), Path(obj)


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
    ap.add_argument("--model-scale", default=None, metavar="SX,SY,SZ",
                    help="scale the (cropped) model per axis, about its own box centre in x and y and its start in z (Q20)")
    ap.add_argument("--pod-ply", type=Path, default=None, help="splat file of a removable part, drawn at every mount")
    ap.add_argument("--pod-obj", type=Path, default=None, help="mesh of the removable part (default: beside --pod-ply or <id>_pod.obj)")
    ap.add_argument("--pod-at", action="append", default=[], metavar="X,Y,Z", help="a mount in the body frame (repeatable)")
    ap.add_argument("--pods-from-hardpoints", action="store_true", help="mounts from the asset's hardpoints.json cargo_pods[]")
    ap.add_argument("--pixel-frac", type=float, default=PIXEL_FRACTION, help=f"geometry check's pixel as a share of the length (at most {PIXEL_FRACTION_MAX}); the splat check's is a third of the spacing")
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
        mesh, splats = load_asset_mesh(folder), load_asset_splats(folder)
        spacing, spacing_source = splat_spacing(manifest, splats)
        spacing_failure = spacing_mismatch(manifest, splats, spacing, spacing_source)

        mounts = pod_mounts(args, folder)
        if mounts:
            pod_ply, pod_obj = pod_files(args, folder)
            offset = _centroid_offset(manifest)
            pods_mesh, pods_splats = place_parts(mesh_from_obj(pod_obj, np.zeros(3)), splats_from_ply(pod_ply, np.zeros(3)), mounts, offset)
            mesh, splats = np.concatenate([mesh, pods_mesh]), SplatSet.concatenate([splats, pods_splats])
        elif args.pod_ply or args.pod_obj:
            raise ValueError("--pod-ply and --pod-obj need mounts: --pod-at X,Y,Z or --pods-from-hardpoints")

        cropped = model_range is not None or asset_range is not None
        if model_range is not None:
            z_min, z_max = float(tris[..., 2].min()), float(tris[..., 2].max())
            tris = crop_triangles(tris, *model_range, z_min, z_max)
            if len(tris) == 0:
                raise ValueError(f"the model has no triangles within z {model_range[0]:g}..{model_range[1]:g} m")
            tris = tris - np.array([0.0, 0.0, model_range[0]])
        model_scale = parse_vec3(args.model_scale) if args.model_scale else np.ones(3)
        if np.any(model_scale <= 0.0):
            raise ValueError("--model-scale needs three positive factors")
        tris = scale_about_part(tris, model_scale)
        if asset_range is not None:
            z_min, z_max = float(mesh[..., 2].min()), float(mesh[..., 2].max())
            lo, hi = crop_planes(*asset_range, z_min, z_max)
            mesh, splats = clip_slab(mesh, 2, lo, hi), splats.cropped(2, lo, hi)
            if len(mesh) == 0 or len(splats) == 0:
                raise ValueError(f"the asset has no triangles and splats within z {asset_range[0]:g}..{asset_range[1]:g} m")
            start = np.array([0.0, 0.0, asset_range[0]])
            mesh, splats = mesh - start, splats.moved(-start)
        align = np.zeros(3)
        if cropped:
            align = part_alignment(tris, mesh)
            mesh, splats = mesh + align, splats.moved(align)
        length_ref = float(np.ptp(tris[..., 2]))
        if length_ref <= 0.0:
            raise ValueError("the model has no extent along z")
        comp = compare_shapes(tris, mesh, length_ref, pixel_fraction=args.pixel_frac)
        check = check_splats(mesh, splats, spacing, spacing_source)
        failures = judge({n: s.iou for n, s in comp.views.items()}, comp.ratios)
        splat_failures = judge_splats({n: s.coverage for n, s in check.views.items()}, {n: s.precision for n, s in check.views.items()})
        splat_failures += [spacing_failure] if spacing_failure else []
        suggestion = None
        if not cropped and (failures or any(comp.at_limit[:2])):
            gap, best, unmoved = suggest_offset(tris, mesh, length_ref)
            if float(np.abs(gap[:2]).max()) > comp.shift_limit_m and best - unmoved > 0.02:
                suggestion = model_offset - gap
    except BAD_DATA as exc:
        print(f"compare: {type(exc).__name__ + ': ' if not isinstance(exc, (OSError, ValueError)) else ''}{exc}", file=sys.stderr)
        return 2

    try:
        name = args.name or folder.name
        out = args.out / args.part if (args.out and args.part) else (args.out or default_out(name, args.part))
        out.mkdir(parents=True, exist_ok=True)
        label = f"{name} / {args.part}" if args.part else name
        shift = ", ".join(f"{v:+.2f}" for v in comp.shift_m)
        for view in VIEWS:
            write_overlay(out / f"overlay_{view}.png", comp.views, view, f"{label}: {view}, STL against mesh, IoU {comp.views[view].iou:.3f}, mesh moved ({shift}) m", ("STL", "mesh"))
            write_overlay(out / f"splats_{view}.png", check.views, view, f"{label}: {view}, mesh against LOD0 splats, coverage {check.views[view].coverage:.3f}, precision {check.views[view].precision:.3f}", ("mesh", "splats"))

        verdict_failures = failures + splat_failures
        report = {
            "name": name,
            "part": args.part,
            "model": {
                "stl": args.stl.name,
                "format": fmt,
                "triangles": int(len(tris)),
                "zrange": model_range,
                "offset_m": [round(float(v), 4) for v in model_offset],
                "scale": [round(float(v), 4) for v in model_scale],
                "dims_m": {n: round(v, 3) for n, v in comp.model_dims.items()},
            },
            "asset": {
                "id": manifest["asset_id"],
                "dir": str(folder),
                "lod0": manifest["lods"][0]["file"],
                "mesh_triangles": int(len(mesh)),
                "splats": int(len(splats)),
                "extra_parts": len(mounts),
                "zrange": asset_range,
                "centroid_offset": manifest["centroid_offset"],
                "dims_m": {n: round(v, 3) for n, v in comp.asset_dims.items()},
            },
            "mapping": {"right": args.right, "up": args.up, "aft": args.aft},
            "basis": "mesh",
            "length_m": round(length_ref, 3),
            "pixel_m": round(comp.pixel_m, 5),
            "shift_m": [round(float(v), 4) for v in comp.shift_m],
            "shift_limit_m": round(comp.shift_limit_m, 4),
            "shift_at_limit": list(comp.at_limit),
            "part_align_m": [round(float(v), 4) for v in align],
            "suggested_model_offset_m": None if suggestion is None else [round(float(v), 3) for v in suggestion],
            "views": {n: view_report(s) for n, s in comp.views.items()},
            "dimensions": {
                n: {"model_m": round(comp.model_dims[n], 3), "asset_m": round(comp.asset_dims[n], 3), "ratio": round(comp.ratios[n], 4)}
                for n in DIMENSIONS
            },
            "geometry": {"verdict": "fail" if failures else "pass", "failures": failures},
            "splat_check": {
                "splat_sigmas": SPLAT_SIGMAS,
                "spacing_m": round(check.spacing_m, 4),
                "spacing_source": check.spacing_source,
                "pixel_m": round(check.pixel_m, 5),
                "band_px": round(next(iter(check.views.values())).band_px, 3),
                "coverage_min": SPLAT_COVERAGE_MIN,
                "precision_min": SPLAT_PRECISION_MIN,
                "views": {n: view_report(s) for n, s in check.views.items()},
                "verdict": "fail" if splat_failures else "pass",
                "failures": splat_failures,
            },
            "thresholds": {
                "iou_min": IOU_MIN,
                "dimension_tolerance": DIM_TOLERANCE,
                "shift_fraction": SHIFT_FRACTION,
                "splat_coverage_min": SPLAT_COVERAGE_MIN,
                "splat_precision_min": SPLAT_PRECISION_MIN,
            },
            "failures": verdict_failures,
            "verdict": "fail" if verdict_failures else "pass",
        }
        (out / "fidelity.json").write_text(json.dumps(report, indent=1) + "\n")
    except OSError as exc:
        print(f"compare: cannot write the results: {exc}", file=sys.stderr)
        return 2

    print(f"{label}: {args.stl.name} against {manifest['asset_id']} (mesh {len(mesh)} triangles, LOD0 {len(splats)} splats), length {length_ref:.1f} m, pixel {comp.pixel_m:.3f} m -> {out}")
    print(f"geometry: the STL against the asset's mesh, bar {IOU_MIN:.2f} per view and {DIM_TOLERANCE:.0%} on each dimension")
    for view, score in comp.views.items():
        mark = "ok  " if score.iou >= IOU_MIN - 1e-9 else "LOW "
        print(f"{view:<6} IoU {score.iou:.3f} {mark} (unshifted {score.iou_unshifted:.3f})  STL {score.model_px} px  mesh {score.asset_px} px  both {score.both_px} px")
    print("size   " + "  ".join(f"{n} {comp.ratios[n]:.3f} ({comp.asset_dims[n]:.1f}/{comp.model_dims[n]:.1f} m)" for n in DIMENSIONS) + "  (mesh / STL)")
    if cropped:
        print(f"align  part moved ({', '.join(f'{v:+.2f}' for v in align)}) m to meet the model part's box centre")
    print(f"shift  mesh moved ({shift}) m of at most {comp.shift_limit_m:.2f} m per axis")
    if suggestion is not None:
        gap = ",".join(f"{v:.2f}" for v in suggestion)
        print(f"note   the silhouettes meet best further away than the shift window; if only the origin differs, try --model-offset {gap}")
    print("geometry verdict: " + ("PASS" if not failures else "FAIL (" + "; ".join(failures) + ")"))
    band = next(iter(check.views.values())).band_px
    print(
        f"splats: LOD0 against the mesh, no shift, pixel {check.pixel_m:.3f} m; band one spacing = {check.spacing_m:.3f} m ({check.spacing_source}) = {band:.0f} px; "
        f"bar {SPLAT_COVERAGE_MIN:.2f} coverage and {SPLAT_PRECISION_MIN:.2f} precision per view"
    )
    for view, score in check.views.items():
        cov_mark = "ok  " if score.coverage >= SPLAT_COVERAGE_MIN - 1e-9 else "LOW "
        prec_mark = "ok  " if score.precision >= SPLAT_PRECISION_MIN - 1e-9 else "LOW "
        print(
            f"splats {view:<5} coverage {score.coverage:.3f} {cov_mark} precision {score.precision:.3f} {prec_mark} "
            f"mesh {score.model_px} px  splats {score.asset_px} px  beyond the band {score.outside_px} px"
        )
    print("splats verdict: " + ("PASS" if not splat_failures else "FAIL (" + "; ".join(splat_failures) + ")"))
    print("verdict: " + ("PASS" if not verdict_failures else "FAIL (" + "; ".join(verdict_failures) + ")"))
    return 1 if verdict_failures else 0


if __name__ == "__main__":
    sys.exit(main())
