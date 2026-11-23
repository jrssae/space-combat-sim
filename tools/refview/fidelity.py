"""Fidelity checks (M10-T66): where a build (or a second STL) departs from a reference STL, found by sweeping rather than by a few
hand-picked planes.

Three measures, all on the generator's frame (x to starboard, y up from the spine's axis, z aft from the bow tip):

* ``sweep``: cuts both meshes on planes across z (or x, or y) every ``--step`` metres, scores each slice's section IoU, and writes a
  CSV plus a strip image (reference | build | overlay per slice, labelled with its position and IoU).
* ``depth``: orthographic depth of both meshes seen from ahead (or above, or the side) over a box, side by side with a signed
  difference (red: the reference stands nearer, the build lacks it; blue: the build stands nearer, extra), and a summary number.
* ``stl-vs-stl``: the same two measures between two STLs after their bows are aligned (the tip and the spine's axis), and a search
  for the scale that makes the forward hulls match.

A mesh is named by a preset (``omega``, ``nova``, ``hyperion`` the STLs; ``omega-build``, ``nova-build`` the built assets), by a path to an
STL, or by a ``.npy`` of triangles already in the generator's frame.
Needs Pillow for the images (the scores and CSVs do not). Development only; outputs go under the gitignored ``references/screenshots/``.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np

try:
    from . import compare, refview
    from .raster import rasterize
    from .sections import SectionPlane, SectionScore, fill_holes, section_mask, section_score
except ImportError:  # run as a script
    import compare  # type: ignore[no-redef]
    import refview  # type: ignore[no-redef]
    from raster import rasterize  # type: ignore[no-redef]
    from sections import SectionPlane, SectionScore, fill_holes, section_mask, section_score  # type: ignore[no-redef]

ROOT = Path(__file__).resolve().parents[2]
REFERENCES = ROOT / "references"
# Per hull: the STL, the file's axes, the length the generator scales it to, the spine's axis in the ship frame (the box is centred, the
# axis is not), the built asset and the span of z the STL's rotating section is turned over (the Omega's drum sits turned 45 degrees).
PRESETS: dict[str, dict] = {
    "omega": {"stl": "EA Omega Destroyer.stl", "mapping": ("+y", "+z", "+x"), "length": 1714.3, "axis": (0.0, 35.58, 0.0),
              "asset": "ea_omega", "turn": (560.0, 880.0, 45.0)},
    "nova": {"stl": "EA_Nova_Dreadnought_(with_guns).stl", "mapping": ("-x", "+z", "+y"), "length": 1502.1, "axis": (0.25, 43.3, 0.0),
             "asset": "ea_nova", "turn": None},
    "nova1": {"stl": "EA Nova class destroyer.STL", "mapping": ("-x", "+z", "+y"), "length": 1502.1, "axis": (0.0, 43.3, 0.0),
              "asset": "ea_nova", "turn": None},
    "hyperion": {"stl": "EA-Hyperion-V5c.stl", "mapping": ("-x", "+z", "+y"), "length": 1025.39, "axis": (0.0, 0.0, 0.0),
                 "asset": "ea_hyperion", "turn": None},
    "hyperion1": {"stl": "EA Hyperion Class Heavy Cruiser.stl", "mapping": ("+x", "+z", "-y"), "length": 1025.39, "axis": (-3.4, 0.0, 0.0),
                  "asset": "ea_hyperion", "turn": None},
}
DEFAULT_TOLERANCE_M = 2.0


# --- meshes ----------------------------------------------------------------------------------------------------------
def turn_span(tris: np.ndarray, z0: float, z1: float, deg: float) -> np.ndarray:
    """The triangles whose middle lies in z0..z1 turned about the spine (z) axis; the rest as they were."""
    out = np.array(tris, dtype=float)
    mid = out[:, :, 2].mean(axis=1)
    sel = (mid >= z0) & (mid <= z1)
    a = math.radians(deg)
    rot = np.array([[math.cos(a), -math.sin(a), 0.0], [math.sin(a), math.cos(a), 0.0], [0.0, 0.0, 1.0]])
    out[sel] = out[sel] @ rot.T
    return out


def load_stl(path: Path, mapping: tuple[str, str, str], length: float | None, axis: tuple[float, float, float]) -> np.ndarray:
    raw, _ = refview.read_stl(path)
    ship, _ = refview.to_ship_frame(raw, refview.frame_matrix(*mapping), length)
    return np.asarray(ship).reshape(-1, 3, 3) - np.asarray(axis)


def load_mesh(spec: str, rest_drum: bool = True) -> np.ndarray:
    """A mesh by preset name (``omega``, ``nova-build``) or STL path. The Omega STL's drum is squared up to the build's rest pose
    unless ``rest_drum`` is off."""
    name, _, kind = spec.partition("-")
    if name in PRESETS:
        p = PRESETS[name]
        if kind == "build":
            return compare.load_asset_mesh(compare.resolve_asset(p["asset"]))
        tris = load_stl(REFERENCES / p["stl"], p["mapping"], p["length"], p["axis"])
        return turn_span(tris, *p["turn"]) if p["turn"] and rest_drum else tris
    path = Path(spec)
    if path.suffix == ".npy" and path.is_file():  # triangles already in the generator's frame, (n, 3, 3)
        return np.load(path)
    if not path.is_file():
        raise ValueError(f"{spec!r} is neither a preset ({', '.join(PRESETS)} with an optional -build) nor an STL file")
    # A bare STL: the file's axes as they are (x across, y up, z aft), its box centred and its nose at z = 0.
    return load_stl(path, ("+x", "+y", "+z"), None, (0.0, 0.0, 0.0))


def bounds(tris: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    p = np.asarray(tris).reshape(-1, 3)
    return p.min(axis=0), p.max(axis=0)


# --- slice sweep -----------------------------------------------------------------------------------------------------
def sweep_window(axis: int, ref: np.ndarray, model: np.ndarray, span: tuple[float, float], pad: float = 4.0) -> tuple[float, float, float, float]:
    """The plane window (u0, u1, v0, v1) that holds both meshes over the swept span of the cut's axis."""
    lo = np.minimum(*(bounds(m)[0] for m in (ref, model)))
    hi = np.maximum(*(bounds(m)[1] for m in (ref, model)))
    if axis == 2:  # x across, y up; a window over the span's slab only, so a narrow bow is not drowned in the drum's width
        sel = [m[(m[:, :, 2].max(axis=1) >= span[0]) & (m[:, :, 2].min(axis=1) <= span[1])] for m in (ref, model)]
        lo = np.minimum(*(bounds(s)[0] for s in sel if len(s)))
        hi = np.maximum(*(bounds(s)[1] for s in sel if len(s)))
    u, v = {0: (2, 1), 1: (0, 2), 2: (0, 1)}[axis]
    return (float(lo[u] - pad), float(hi[u] + pad), float(lo[v] - pad), float(hi[v] + pad))


def plane_values(span: tuple[float, float], step: float) -> list[float]:
    n = int(math.floor((span[1] - span[0]) / step + 1e-9))
    return [span[0] + i * step for i in range(n + 1)]


def face_fill(mask: np.ndarray, axis: int) -> np.ndarray:
    """An x or y cut's section filled from the first surface the bow meets back to the window's aft edge: the face's depth along
    each line, whatever lies behind it. An open shell (deck blocks a few metres deep) then counts by where its face stands."""
    if axis == 0:  # rows are y, columns z from the bow
        seen = np.cumsum(mask, axis=1) > 0
    elif axis == 1:  # rows are z from aft (top) to the bow (bottom), columns x
        seen = np.cumsum(mask[::-1], axis=0)[::-1] > 0
    else:
        raise ValueError("a face fill is for x and y cuts")
    return seen


def sweep(ref: np.ndarray, model: np.ndarray, axis: int, span: tuple[float, float], step: float, pixel_m: float,
          window: tuple[float, float, float, float] | None = None, relief: bool = False,
          outline: bool = False, face: bool = False) -> list[SectionScore]:
    """The section score of every plane across ``axis`` from span[0] to span[1]; ``face`` scores x and y cuts by
    :func:`face_fill`."""
    window = window or sweep_window(axis, ref, model, span)
    name = "xyz"[axis]
    planes = [SectionPlane(f"{name}{v:.1f}", axis, v, window, relief=relief and axis == 2, outline=outline and not face) for v in plane_values(span, step)]
    if not face:
        return [section_score(ref, model, p, pixel_m) for p in planes]
    out = []
    for p in planes:
        a, b = (face_fill(section_mask(m, p, pixel_m), axis) for m in (ref, model))
        union = int((a | b).sum())
        out.append(SectionScore(p, 1.0 if union == 0 else float((a & b).sum()) / union, a, b))
    return out


def sweep_rows(scores: list[SectionScore], pixel_m: float) -> list[dict]:
    rows = []
    for s in scores:
        r, m = s.reference, s.model
        area = pixel_m * pixel_m
        rows.append({"position_m": round(s.plane.value, 3), "iou": round(s.iou, 4), "reference_m2": round(float(r.sum()) * area, 1),
                     "model_m2": round(float(m.sum()) * area, 1), "missing_m2": round(float((r & ~m).sum()) * area, 1),
                     "extra_m2": round(float((~r & m).sum()) * area, 1)})
    return rows


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]) if rows else ["position_m"])
        w.writeheader()
        w.writerows(rows)


def _font(size: int):  # noqa: ANN202 - a PIL font
    from PIL import ImageFont  # noqa: PLC0415

    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def overlay_rgb(ref: np.ndarray, model: np.ndarray) -> np.ndarray:
    img = np.full(ref.shape + (3,), 255, dtype=np.uint8)
    img[ref & model] = (150, 150, 150)
    img[ref & ~model] = (220, 40, 40)
    img[~ref & model] = (40, 90, 230)
    return img


def _mask_rgb(mask: np.ndarray) -> np.ndarray:
    return np.where(mask[:, :, None], np.uint8(60), np.uint8(255)).repeat(3, axis=2)


def write_strip(path: Path, scores: list[SectionScore], labels: tuple[str, str], unit: str = "z", tile_px: int = 200, rows_per_column: int = 30) -> None:
    """One image: a cell per slice (reference | build | overlay) labelled with its position and IoU, the cells in as many columns as
    keep a column to ``rows_per_column`` rows. Red is what only the reference has, blue what only the build has."""
    from PIL import Image, ImageDraw  # noqa: PLC0415

    if not scores:
        raise ValueError("no slices to draw")
    h, w = scores[0].reference.shape
    k = min(1.0, tile_px / max(h, w))
    tw, th = max(1, int(w * k)), max(1, int(h * k))
    label_h = 16
    cell_w, cell_h = 3 * tw + 16, th + label_h + 4
    columns = max(1, math.ceil(len(scores) / rows_per_column))
    per = math.ceil(len(scores) / columns)
    img = Image.new("RGB", (columns * cell_w, per * cell_h + 20), (20, 20, 23))
    draw = ImageDraw.Draw(img)
    draw.text((6, 2), f"left to right: {labels[0]} | {labels[1]} | overlay (red only {labels[0]}, blue only {labels[1]})", fill=(232, 232, 226), font=_font(13))
    for i, s in enumerate(scores):
        cx, cy = (i // per) * cell_w, 20 + (i % per) * cell_h
        draw.text((cx + 4, cy + 1), f"{unit}={s.plane.value:.1f} m  IoU {s.iou:.3f}", fill=(255, 120, 120) if s.iou < 0.9 else (190, 230, 190), font=_font(13))
        for j, tile in enumerate((_mask_rgb(s.reference), _mask_rgb(s.model), overlay_rgb(s.reference, s.model))):
            im = Image.fromarray(tile).resize((tw, th), Image.NEAREST)
            img.paste(im, (cx + j * tw, cy + label_h))
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


# --- depth maps ------------------------------------------------------------------------------------------------------
VIEWS = {"front": "ahead, looking aft (x across, y up)", "top": "from above, bow up (x across, z up the page)",
         "side": "from starboard, bow left (z along, y up)"}


def clip_box(tris: np.ndarray, box: tuple[float, ...]) -> np.ndarray:
    """The triangles cut to the box (x0, x1, y0, y1, z0, z1), so a face map shows only what lies in it."""
    out = np.asarray(tris, dtype=float)
    for axis in range(3):
        out = compare.clip_slab(out, axis, box[2 * axis], box[2 * axis + 1])
        if len(out) == 0:
            break
    return out


def _view_coords(tris: np.ndarray, view: str) -> np.ndarray:
    """Triangles as (u, v, d): the picture's across and up and the distance from the viewer (nearer is smaller)."""
    x, y, z = tris[:, :, 0], tris[:, :, 1], tris[:, :, 2]
    if view == "front":
        return np.stack([x, y, z], axis=2)
    if view == "top":
        return np.stack([x, -z, -y], axis=2)
    if view == "side":
        return np.stack([z, y, -x], axis=2)
    raise ValueError(f"view {view!r} is not one of {', '.join(VIEWS)}")


def view_window(view: str, box: tuple[float, ...]) -> tuple[float, float, float, float]:
    x0, x1, y0, y1, z0, z1 = box
    return {"front": (x0, x1, y0, y1), "top": (x0, x1, -z1, -z0), "side": (z0, z1, y0, y1)}[view]


def depth_map(tris: np.ndarray, view: str, box: tuple[float, ...], pixel_m: float) -> np.ndarray:
    """Distance from the viewer to the first surface per pixel over the box's face (inf where nothing is seen), rows from the top."""
    u0, u1, v0, v1 = view_window(view, box)
    cols, rows = max(1, int(round((u1 - u0) / pixel_m))), max(1, int(round((v1 - v0) / pixel_m)))
    t = clip_box(tris, box)
    if len(t) == 0:
        return np.full((rows, cols), np.inf)
    c = _view_coords(t, view)
    screen = np.empty_like(c)
    screen[:, :, 0] = (c[:, :, 0] - u0) / pixel_m
    screen[:, :, 1] = (v1 - c[:, :, 1]) / pixel_m
    screen[:, :, 2] = c[:, :, 2]
    return rasterize(screen, cols, rows)[0]


@dataclass(frozen=True)
class DepthDiff:
    reference: np.ndarray
    model: np.ndarray
    missing: np.ndarray  # the reference stands nearer by more than the tolerance (or the build has nothing there)
    extra: np.ndarray  # the build stands nearer (or the reference has nothing there)
    summary: dict


def depth_diff(ref_depth: np.ndarray, model_depth: np.ndarray, tol_m: float, pixel_m: float) -> DepthDiff:
    rf, mf = np.isfinite(ref_depth), np.isfinite(model_depth)
    both = rf & mf
    d = np.where(both, np.where(both, model_depth, 0.0) - np.where(both, ref_depth, 0.0), 0.0)
    missing = (rf & ~mf) | (both & (d > tol_m))
    extra = (mf & ~rf) | (both & (d < -tol_m))
    union = int((rf | mf).sum())
    area = pixel_m * pixel_m
    summary = {
        "pixels": union,
        "coverage_iou": round(float(both.sum()) / union, 4) if union else 1.0,
        "within_tolerance": round(1.0 - float((missing | extra).sum()) / union, 4) if union else 1.0,
        "mean_abs_depth_diff_m": round(float(np.abs(d[both]).mean()), 3) if both.any() else 0.0,
        "missing_m2": round(float(missing.sum()) * area, 1), "extra_m2": round(float(extra.sum()) * area, 1),
        "tolerance_m": tol_m,
    }
    return DepthDiff(ref_depth, model_depth, missing, extra, summary)


def write_depth_sheet(path: Path, diff: DepthDiff, labels: tuple[str, str], title: str, scale: int = 3, span_m: float | None = None) -> None:
    """Reference depth | build depth (nearer is lighter) | the signed difference, with the summary under the title."""
    from PIL import Image, ImageDraw  # noqa: PLC0415

    finite = np.concatenate([diff.reference[np.isfinite(diff.reference)], diff.model[np.isfinite(diff.model)]])
    lo = float(finite.min()) if len(finite) else 0.0
    hi = lo + (span_m if span_m else max(1.0, float(finite.max()) - lo if len(finite) else 1.0))

    def gray(depth: np.ndarray) -> np.ndarray:
        g = 255 - np.clip((depth - lo) / (hi - lo), 0.0, 1.0) * 220
        g = np.where(np.isfinite(depth), g, 12).astype(np.uint8)
        return np.stack([g, g, g], axis=2)

    both = np.isfinite(diff.reference) & np.isfinite(diff.model)
    delta = np.where(both, np.where(both, diff.model, 0.0) - np.where(both, diff.reference, 0.0), 0.0)
    ok = np.full(delta.shape + (3,), 235, dtype=np.uint8)
    ok[~(np.isfinite(diff.reference) | np.isfinite(diff.model))] = 12
    ok[both & ~(diff.missing | diff.extra)] = (170, 170, 170)
    # Strength by how far off, so a 2 m slip and a 30 m hole read differently.
    mag = np.clip(np.abs(delta) / 20.0, 0.0, 1.0)
    red, blue = diff.missing, diff.extra
    ok[red] = np.stack([np.full(red.sum(), 255), (200 - 160 * mag[red]), (200 - 160 * mag[red])], axis=1).astype(np.uint8)
    ok[blue] = np.stack([(200 - 160 * mag[blue]), (200 - 140 * mag[blue]), np.full(blue.sum(), 255)], axis=1).astype(np.uint8)
    # One-sided pixels (the other mesh has nothing there) show in the strongest tint.
    ok[diff.missing & ~np.isfinite(diff.model)] = (255, 0, 0)
    ok[diff.extra & ~np.isfinite(diff.reference)] = (0, 60, 255)
    h, w = diff.reference.shape
    s = min(scale, max(1, 700 // max(h, w)) if max(h, w) < 700 else 1)
    k = max(1, s)
    tiles = [np.kron(t, np.ones((k, k, 1), dtype=np.uint8)) for t in (gray(diff.reference), gray(diff.model), ok)]
    th, tw = tiles[0].shape[:2]
    head = 44
    img = Image.new("RGB", (3 * tw + 20, th + head + 20), (20, 20, 23))
    d = ImageDraw.Draw(img)
    sm = diff.summary
    d.text((6, 3), title, fill=(232, 232, 226), font=_font(15))
    d.text((6, 23), f"within {sm['tolerance_m']} m: {sm['within_tolerance']:.3f}  mean |dz| {sm['mean_abs_depth_diff_m']} m  missing {sm['missing_m2']} m2  "
           f"extra {sm['extra_m2']} m2  (red: {labels[0]} nearer/build lacks it, blue: build nearer)", fill=(232, 232, 226), font=_font(13))
    for i, (t, lab) in enumerate(zip(tiles, (labels[0], labels[1], "difference"), strict=True)):
        img.paste(Image.fromarray(t), (i * (tw + 10), head + 16))
        d.text((i * (tw + 10) + 2, head + 1), lab, fill=(190, 230, 190), font=_font(13))
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


# --- STL against STL -------------------------------------------------------------------------------------------------
def bow_tip(tris: np.ndarray, depth_m: float = 8.0) -> np.ndarray:
    """The bow's tip: the middle of the vertices within ``depth_m`` of the foremost point (its x and y, its z)."""
    p = np.asarray(tris).reshape(-1, 3)
    near = p[p[:, 2] <= p[:, 2].min() + depth_m]
    return np.array([0.5 * (near[:, 0].min() + near[:, 0].max()), 0.5 * (near[:, 1].min() + near[:, 1].max()), p[:, 2].min()])


def align_bow(base: np.ndarray, other: np.ndarray, scale: float = 1.0, dz: float = 0.0) -> np.ndarray:
    """``other`` scaled about the spine's axis at its bow tip, then laid so the tips meet in z (plus ``dz``). The spine's axis is
    the frame's own (x = y = 0 on both), so the widths and heights are compared about the same line."""
    tip = bow_tip(other)
    pivot = np.array([0.0, 0.0, tip[2]])
    return (np.asarray(other) - pivot) * scale + np.array([0.0, 0.0, bow_tip(base)[2] + dz])


def width_ratio(base: np.ndarray, other: np.ndarray, z0: float, z1: float, dz: float = 0.0, step: float = 10.0) -> float:
    """The forward hulls' section width, base over other, median over the stations z0..z1 (``other`` laid ``dz`` aft of the tip
    match): the scale that makes the widths agree."""
    window = sweep_window(2, base, other, (z0, z1))
    ratios = []
    for z in np.arange(z0, z1 + 1e-9, step):
        w = []
        for m, zz in ((base, z), (other, z + dz)):
            cols = np.flatnonzero(section_mask(m, SectionPlane("w", 2, zz, window), 1.0).any(axis=0))
            w.append(float(cols.max() - cols.min() + 1) if len(cols) else 0.0)
        if w[0] > 0 and w[1] > 0:
            ratios.append(w[0] / w[1])
    return float(np.median(ratios)) if ratios else float("nan")


def best_scale(base: np.ndarray, other: np.ndarray, z0: float, z1: float, pixel_m: float, scales: np.ndarray,
               shifts: np.ndarray, outline: bool = False) -> tuple[float, float, float, list[tuple[float, float, float]]]:
    """The scale and the z shift of ``other`` that give the highest mean section IoU against ``base`` over z0..z1 (a station every
    10 m); returns (scale, shift, IoU, every try)."""
    zs = list(np.arange(z0, z1 + 1e-9, 10.0))
    window = sweep_window(2, base, other, (z0, z1))
    fill = fill_holes if outline else (lambda m: m)
    cache = [fill(section_mask(base, SectionPlane("r", 2, z, window), pixel_m)) for z in zs]
    tried = []
    for sc in scales:
        for dz in shifts:
            moved = align_bow(base, other, float(sc), float(dz))
            ious = []
            for z, ref in zip(zs, cache, strict=True):
                mod = fill(section_mask(moved, SectionPlane("m", 2, z, window), pixel_m))
                u = int((ref | mod).sum())
                ious.append(1.0 if u == 0 else float((ref & mod).sum()) / u)
            tried.append((float(sc), float(dz), float(np.mean(ious))))
    best = max(tried, key=lambda t: t[2])
    return best[0], best[1], best[2], tried


# --- command line ----------------------------------------------------------------------------------------------------
def parse_pair(text: str) -> tuple[float, float]:
    a, b = (float(v) for v in text.split(","))
    return a, b


def parse_box(text: str | None, ref: np.ndarray, model: np.ndarray) -> tuple[float, ...]:
    """``x0,x1,y0,y1,z0,z1``; missing, the two meshes' joint bounds."""
    if text:
        v = tuple(float(s) for s in text.split(","))
        if len(v) != 6:
            raise ValueError("--box is x0,x1,y0,y1,z0,z1")
        return v
    lo = np.minimum(*(bounds(m)[0] for m in (ref, model)))
    hi = np.maximum(*(bounds(m)[1] for m in (ref, model)))
    return (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2])


def prepare(args: argparse.Namespace) -> tuple[np.ndarray, np.ndarray, tuple[str, str]]:
    ref, model = load_mesh(args.reference), load_mesh(args.model)
    if args.scale_search or args.scale != 1.0 or args.dz or args.align_bow:
        scale, dz = args.scale, args.dz
        if args.scale_search:
            z0, z1 = args.align_zrange
            scale, dz, best, _ = best_scale(ref, model, z0, z1, 2.0, np.arange(0.96, 1.321, 0.02), np.arange(-60.0, 20.1, 6.0), args.outline)
            print(f"best of {args.model} to {args.reference} over z {z0:g}-{z1:g}: scale {scale:.3f}, z shift {dz:+.0f} m, mean IoU {best:.3f}; "
                  f"width ratio (omega/nova) over z 250-400 m {width_ratio(ref, model, 250.0, 400.0, dz):.3f}")
        model = align_bow(ref, model, scale, dz)
    return ref, model, (args.reference, args.model)


def cmd_sweep(args: argparse.Namespace) -> int:
    ref, model, labels = prepare(args)
    out = Path(args.out)
    axis = "xyz".index(args.axis)
    span = parse_pair(args.span) if args.span else (float(bounds(ref)[0][axis]) + 0.5, float(bounds(ref)[1][axis]) - 0.5)
    window = tuple(float(v) for v in args.window.split(",")) if args.window else None
    scores = sweep(ref, model, axis, span, args.step, args.pixel, window, relief=args.relief, outline=args.outline, face=args.face)
    tag = args.tag or f"{args.reference}_vs_{args.model}_{args.axis}_{span[0]:g}-{span[1]:g}_step{args.step:g}"
    rows = sweep_rows(scores, args.pixel)
    write_csv(out / f"{tag}.csv", rows)
    write_strip(out / f"{tag}_strip.png", scores, labels, unit=args.axis, tile_px=args.tile, rows_per_column=args.rows_per_column)
    ious = np.array([s.iou for s in scores])
    print(f"{tag}: {len(scores)} slices, mean IoU {ious.mean():.3f}, min {ious.min():.3f} at {scores[int(ious.argmin())].plane.value:.1f} m, "
          f"{int((ious < 0.9).sum())} below 0.90")
    return 0


def cmd_depth(args: argparse.Namespace) -> int:
    ref, model, labels = prepare(args)
    box = parse_box(args.box, ref, model)
    out = Path(args.out)
    for view in args.view.split(","):
        diff = depth_diff(depth_map(ref, view, box, args.pixel), depth_map(model, view, box, args.pixel), args.tolerance, args.pixel)
        tag = args.tag or f"{args.reference}_vs_{args.model}_depth"
        name = f"{tag}_{view}"
        write_depth_sheet(out / f"{name}.png", diff, labels, f"{name}: {VIEWS[view]}  box {', '.join(f'{v:.0f}' for v in box)}", span_m=args.depth_span)
        (out / f"{name}.json").write_text(json.dumps(diff.summary, indent=1))
        print(name, json.dumps(diff.summary))
    return 0


def cmd_shots(args: argparse.Namespace) -> int:
    """One sheet: the reference pictures in a grid, then the fixed-view renders of the build (``scripts/model_sheet.sh`` output,
    not camera-matched) in a grid below, so the two can be read against each other."""
    from PIL import Image, ImageDraw  # noqa: PLC0415

    pictures = [(p.name, p) for p in sorted(Path(args.pictures).glob("*.png"))]
    renders = [(n, Path(args.shots) / f"{n}.png") for n in args.names.split(",")]
    tile, cols = args.tile, args.columns
    th = tile * 9 // 16 + 18

    def block(items: list[tuple[str, Path]], y0: int, img: Image.Image, d: ImageDraw.ImageDraw) -> int:
        for i, (label, path) in enumerate(items):
            x, y = (i % cols) * tile, y0 + (i // cols) * th
            d.text((x + 4, y + 1), label, fill=(190, 230, 190), font=_font(12))
            if path.is_file():
                im = Image.open(path).convert("RGB")
                im.thumbnail((tile, th - 18), Image.LANCZOS)
                img.paste(im, (x, y + 16))
        return y0 + math.ceil(len(items) / cols) * th

    rows = math.ceil(len(pictures) / cols) + math.ceil(len(renders) / cols)
    img = Image.new("RGB", (cols * tile, 24 + rows * th), (20, 20, 23))
    d = ImageDraw.Draw(img)
    d.text((6, 4), args.title, fill=(232, 232, 226), font=_font(15))
    y = block(pictures, 24, img, d)
    block(renders, y, img, d)
    Path(args.sheet).parent.mkdir(parents=True, exist_ok=True)
    img.save(args.sheet)
    print(f"wrote {args.sheet}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    def pair(p: argparse.ArgumentParser) -> None:
        p.add_argument("reference", help="preset or STL: the side the build is judged against")
        p.add_argument("model", help="preset or STL: the build (or a second STL)")
        p.add_argument("--out", default=str(REFERENCES / "screenshots" / "fidelity"))
        p.add_argument("--tag", default=None)
        p.add_argument("--pixel", type=float, default=1.0, help="metres per pixel")
        p.add_argument("--align-bow", action="store_true", help="lay the model's bow tip on the reference's (STL against STL)")
        p.add_argument("--scale", type=float, default=1.0, help="scale the model about its bow tip (with --align-bow)")
        p.add_argument("--scale-search", action="store_true", help="find the model's scale that matches the forward hulls, then use it")
        p.add_argument("--outline", action="store_true", help="fill each section row between its outer edges (an open-shell STL against a solid one)")
        p.add_argument("--dz", type=float, default=0.0, help="shift the model aft by this many metres (with --align-bow)")
        p.add_argument("--align-zrange", type=parse_pair, default=(150.0, 450.0), help="z0,z1 the forward hull is matched over")

    s = sub.add_parser("sweep", help="section IoU every --step metres, as a CSV and a strip image")
    pair(s)
    s.add_argument("--axis", choices=("x", "y", "z"), default="z")
    s.add_argument("--span", default=None, help="from,to metres along the axis (default the whole reference)")
    s.add_argument("--step", type=float, default=5.0)
    s.add_argument("--window", default=None, help="u0,u1,v0,v1 of the cut's plane (default holds both meshes)")
    s.add_argument("--relief", action="store_true", help="z cuts: what the bow sees in front of the plane")
    s.add_argument("--face", action="store_true", help="x and y cuts: each line filled from its first surface aft (an open shell's face)")
    s.add_argument("--tile", type=int, default=200, help="largest tile side in pixels")
    s.add_argument("--rows-per-column", type=int, default=30)
    s.set_defaults(fn=cmd_sweep)
    d = sub.add_parser("depth", help="orthographic depth of both meshes over a box, and their signed difference")
    pair(d)
    d.add_argument("--view", default="front", help="front, top, side (comma-separated)")
    d.add_argument("--box", default=None, help="x0,x1,y0,y1,z0,z1 in metres (default everything)")
    d.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE_M)
    d.add_argument("--depth-span", type=float, default=None, help="metres of depth the grey ramp covers")
    d.set_defaults(fn=cmd_depth)
    h = sub.add_parser("shots", help="reference pictures beside renders of the build")
    h.add_argument("pictures", help="folder of reference pictures")
    h.add_argument("shots", help="folder of renders (scripts/model_sheet.sh output)")
    h.add_argument("sheet")
    h.add_argument("--names", required=True, help="comma-separated render names, each <name>.png in the shots folder")
    h.add_argument("--title", default="")
    h.add_argument("--tile", type=int, default=640)
    h.add_argument("--columns", type=int, default=3)
    h.set_defaults(fn=cmd_shots)
    args = ap.parse_args(argv)
    try:
        return args.fn(args)
    except ValueError as exc:
        print(f"fidelity: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
