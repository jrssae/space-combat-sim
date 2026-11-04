"""Equirectangular sky panoramas (M4-T30c): pixel directions, soft blobs composited onto the sphere, sRGB and the PNG.

The convention is Godot's ``PanoramaSkyMaterial``: the image centre looks toward +Z, so -Z sits at the left and right edges,
+u turns toward -X and the top row is +Y (checked on a GPU by rolling the image half a turn, which put the nebula where the M3
sky had it). The PNG goes through ``core.image`` (no Pillow), with a Godot ``.import`` sidecar so
the texture is always imported VRAM compressed with mipmaps.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np

from .color import linear_to_srgb
from .image import write_png

# Blobs facing the viewer at less than this cosine are skipped: their tangent-plane projection breaks down.
_MIN_FACING = 0.05


def direction_grid(width: int, height: int) -> np.ndarray:
    """Unit direction of every pixel centre, shape ``(height, width, 3)``."""
    lon = ((np.arange(width) + 0.5) / width - 0.5) * 2.0 * math.pi
    lat = (0.5 - (np.arange(height) + 0.5) / height) * math.pi
    cos_lat = np.cos(lat)[:, None]
    return np.stack(
        [
            -np.sin(lon)[None, :] * cos_lat,
            np.broadcast_to(np.sin(lat)[:, None], (height, width)),
            np.cos(lon)[None, :] * cos_lat,
        ],
        axis=-1,
    ).astype(np.float32)


def lonlat(directions: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Longitude and latitude (radians) of unit directions, in the grid's convention."""
    lon = np.arctan2(-directions[..., 0], directions[..., 2])
    lat = np.arcsin(np.clip(directions[..., 1], -1.0, 1.0))
    return lon, lat


def _tangent_basis(n: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    helper = np.where(np.abs(n[..., 1:2]) > 0.95, np.array([1.0, 0.0, 0.0]), np.array([0.0, 1.0, 0.0]))
    e1 = np.cross(helper, n)
    e1 /= np.linalg.norm(e1, axis=-1, keepdims=True)
    return e1, np.cross(n, e1)


def _columns(lon0: float, half: float, width: int) -> np.ndarray:
    col0 = math.floor((lon0 - half) / (2.0 * math.pi) * width + width / 2 - 0.5)
    col1 = math.ceil((lon0 + half) / (2.0 * math.pi) * width + width / 2 - 0.5)
    return np.arange(col0, col1 + 1) % width if col1 - col0 + 1 < width else np.arange(width)


def composite_blobs(
    centres: np.ndarray,
    rotations: np.ndarray,
    scales: np.ndarray,
    rgb: np.ndarray,
    alpha: np.ndarray,
    width: int,
    height: int,
) -> tuple[np.ndarray, np.ndarray]:
    """Alpha-composites soft 3D blobs (each a normal distribution) seen from the origin, far to near, onto the panorama.

    ``centres`` ``(N, 3)``, ``rotations`` ``(N, 3, 3)`` (columns are the local axes), ``scales`` ``(N, 3)`` sigmas, ``rgb``
    ``(N, 3)`` linear, ``alpha`` ``(N,)`` peak opacity. Each is projected to its 2D angular covariance on the tangent plane.
    Returns premultiplied linear colour ``(height, width, 3)`` and coverage ``(height, width)``.
    """
    grid = direction_grid(width, height)
    colour = np.zeros((height, width, 3), dtype=np.float32)
    coverage = np.zeros((height, width), dtype=np.float32)

    dist = np.linalg.norm(centres, axis=1)
    n = centres / dist[:, None]
    e1, e2 = _tangent_basis(n)
    cov3 = np.einsum("nij,nj,nkj->nik", rotations, scales**2, rotations)
    basis = np.stack([e1, e2], axis=-1)
    cov2 = np.einsum("nia,nij,njb->nab", basis, cov3, basis) / (dist**2)[:, None, None]
    det = cov2[:, 0, 0] * cov2[:, 1, 1] - cov2[:, 0, 1] ** 2
    inv = np.stack([cov2[:, 1, 1], -cov2[:, 0, 1], cov2[:, 0, 0]], axis=1) / det[:, None]
    trace = cov2[:, 0, 0] + cov2[:, 1, 1]
    reach = 3.0 * np.sqrt(0.5 * (trace + np.sqrt(np.maximum(trace**2 - 4.0 * det, 0.0))))
    lon0, lat0 = lonlat(n)

    for i in np.argsort(-dist, kind="stable"):
        lat_hi, lat_lo = lat0[i] + reach[i], lat0[i] - reach[i]
        row0 = max(0, math.floor((0.5 - lat_hi / math.pi) * height - 0.5))
        row1 = min(height - 1, math.ceil((0.5 - lat_lo / math.pi) * height - 0.5))
        cos_edge = math.cos(min(max(abs(lat_hi), abs(lat_lo)), math.pi / 2))
        if lat_hi >= math.pi / 2 or lat_lo <= -math.pi / 2 or reach[i] >= cos_edge * math.pi:
            cols = np.arange(width)
        else:
            cols = _columns(float(lon0[i]), float(reach[i] / cos_edge), width)
        window = np.ix_(np.arange(row0, row1 + 1), cols)
        d = grid[window]
        facing = d @ n[i].astype(np.float32)
        safe = np.maximum(facing, _MIN_FACING)
        u = (d @ e1[i].astype(np.float32)) / safe
        v = (d @ e2[i].astype(np.float32)) / safe
        m = inv[i, 0] * u * u + 2.0 * inv[i, 1] * u * v + inv[i, 2] * v * v
        a = np.where(facing > _MIN_FACING, alpha[i] * np.exp(-0.5 * m), 0.0).astype(np.float32)
        colour[window] = colour[window] * (1.0 - a)[..., None] + rgb[i].astype(np.float32) * a[..., None]
        coverage[window] = coverage[window] * (1.0 - a) + a
    return colour, coverage


def resize_bilinear(layer: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    """Bilinear resize of a 2D float layer, wrapping round horizontally."""
    h, w = layer.shape
    xs = (np.arange(out_w) + 0.5) * w / out_w - 0.5
    x0 = np.floor(xs).astype(np.int64)
    fx = (xs - x0).astype(np.float32)
    wide = layer[:, x0 % w] * (1.0 - fx) + layer[:, (x0 + 1) % w] * fx
    ys = (np.arange(out_h) + 0.5) * h / out_h - 0.5
    y0 = np.floor(ys).astype(np.int64)
    fy = (ys - y0).astype(np.float32)[:, None]
    return wide[np.clip(y0, 0, h - 1)] * (1.0 - fy) + wide[np.clip(y0 + 1, 0, h - 1)] * fy


def to_srgb8(display: np.ndarray, rng: np.random.Generator | None = None) -> np.ndarray:
    """Display values in 0..1 (clamped) as 8-bit sRGB; with ``rng``, a seeded triangular dither of one level so dark gradients do
    not band."""
    levels = linear_to_srgb(np.clip(display, 0.0, 1.0)) * 255.0
    return quantize8(levels, rng)


def quantize8(levels: np.ndarray, rng: np.random.Generator | None = None) -> np.ndarray:
    """Values in 0..255 rounded to bytes, dithered by one level when ``rng`` is given; zero stays zero, so empty sky has no
    noise floor."""
    if rng is not None:
        noise = rng.random(np.shape(levels)) - rng.random(np.shape(levels))
        levels = np.where(levels > 0.0, levels + noise, 0.0)
    return np.clip(np.round(levels), 0.0, 255.0).astype(np.uint8)


def import_sidecar() -> str:
    """Godot's ``.import`` for a panorama: VRAM compressed (BPTC, so the dark gradients do not band) with mipmaps. The alpha is the
    nebula's opacity, so the importer must not bleed colour into transparent texels (``fix_alpha_border`` off)."""
    return (
        "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n"
        "compress/mode=2\ncompress/high_quality=true\ncompress/lossy_quality=0.7\ncompress/uastc_level=0\n"
        "compress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\ncompress/normal_map=2\ncompress/channel_pack=0\n"
        "mipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=\"\"\n"
        "process/channel_remap/red=0\nprocess/channel_remap/green=1\nprocess/channel_remap/blue=2\nprocess/channel_remap/alpha=3\n"
        "process/fix_alpha_border=false\nprocess/premult_alpha=false\nprocess/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\n"
        "process/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n"
    )


def write_panorama(path: Path, image: np.ndarray) -> list[Path]:
    """Writes the 8-bit sRGB panorama and its sidecar; returns both paths."""
    png = write_png(Path(path), image)
    sidecar = Path(str(png) + ".import")
    sidecar.write_text(import_sidecar())
    return [png, sidecar]


__all__ = [
    "composite_blobs",
    "quantize8",
    "direction_grid",
    "import_sidecar",
    "lonlat",
    "resize_bilinear",
    "to_srgb8",
    "write_panorama",
]
