"""``sky_default``: the starfield and nebula backdrop as Gaussian splats (docs/architecture.md section 9.2).

Contents of ``sky_default.ply`` (stars first, then nebula):

* **Stars**: ~12 000 isotropic Gaussians on a sphere of radius R = 20 km around the origin. Direction
  density is uniform plus a Milky Way band (a great circle through the nebula); magnitudes follow
  ``dN/dm ~ 10^(0.5 m)``; colour is a blackbody tint from a spectral-class temperature table;
  bright stars are bigger (sigma 12 m = 0.6 mrad at R) and brighter than dim ones; opacity ~1.
* **Nebula**: ~4 000 large (300-2 000 m), soft, slightly elongated Gaussians in one ~40 degree
  region, clustered by a few blobs and weighted by 3D fBm noise; two-tone teal/magenta; opacity
  0.021-0.079; filaments follow a smooth orientation field.

Frames: authored in the Godot frame, re-centred on the splat centroid (GDGS subtracts the mean at
import, so this makes that a no-op), then written pre-rotated by Rz(180) for GDGS. Because the sky is
one-sided, the centroid is kilometres from the origin: ``manifest.centroid_offset`` is that offset,
and the sky node must sit at ``camera_position + centroid_offset`` to place the star sphere exactly
around the camera.

The optional ``sky_default_panorama.png`` (equirectangular, centre = -Z, the Godot
``PanoramaSkyMaterial`` convention) is a CPU render of the same catalogue for the mesh fallback
path. It needs Pillow and is skipped with a warning without it.
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Any

import numpy as np

from ..core import frames
from ..core.color import blackbody_rgb, lerp, linear_to_srgb
from ..core.context import AssetOutputs, BuildContext
from ..core.manifest import build_manifest, lod_entry, write_manifest
from ..core.ply import SplatData, write_ply

ASSET_ID = "sky_default"
GENERATOR_VERSION = 1
PLY_NAME = "sky_default.ply"
PANORAMA_NAME = "sky_default_panorama.png"

DEFAULT_STARS = 12_000
DEFAULT_NEBULA = 4_000
DEFAULT_RADIUS_M = 20_000.0
DEFAULT_PANORAMA_SIZE = (4096, 2048)  # width, height

# --- stars -----------------------------------------------------------------------------------
STAR_SIGMA_MAX_M = 12.0  # sigma of the brightest star at R = 20 km (0.6 mrad)
STAR_MAG_MIN, STAR_MAG_MAX = -1.0, 6.5
STAR_BRIGHTNESS_GAMMA = (
    0.35  # compresses the 1000:1 flux range into something a display can hold
)
STAR_PEAK_RADIANCE = (
    1.5  # brightest star, linear; slightly HDR so modest glow picks it up
)
BAND_FRACTION = 0.45  # share of stars drawn from the Milky Way band
BAND_SIGMA_DEG = 9.0
# (temperature K, weight): O B A F G K M. Weighted towards what is visible, not what is common.
STAR_CLASSES = (
    (33000.0, 0.02), (14000.0, 0.10), (8800.0, 0.16), (6800.0, 0.18),
    (5700.0, 0.20), (4500.0, 0.20), (3300.0, 0.14),
)  # fmt: skip
STAR_TINT_STRENGTH = 0.7  # 0 = white, 1 = pure blackbody colour

# --- nebula ----------------------------------------------------------------------------------
NEBULA_AZIMUTH_DEG = 35.0  # right of forward (-Z)
NEBULA_ELEVATION_DEG = 12.0
# (east deg, north deg, sigma deg, palette t) with t = 0 teal ... 1 magenta, relative to the centre.
NEBULA_BLOBS = (
    (-9.0, 2.0, 8.5, 0.05),
    (6.0, -3.0, 9.0, 0.90),
    (1.0, 8.0, 6.5, 0.45),
    (12.0, 5.0, 6.0, 0.75),
)
NEBULA_SIGMA_RANGE_M = (
    300.0,
    2000.0,
)  # minor axis >= 300, major axis (minor * elongation) <= 2000
NEBULA_MAX_ELONGATION = 1.8
NEBULA_RADIUS_SPREAD = (
    0.9,
    1.1,
)  # of the sky radius, so stars sit in and behind the gas
NEBULA_ALPHA_RANGE = (
    0.021,
    0.079,
)  # inside the specified 0.02-0.08, clear of float32 round-off
NEBULA_NOISE_FREQ = 7.0
NEBULA_TEAL = np.array([0.08, 0.60, 0.65])
NEBULA_MAGENTA = np.array([0.70, 0.14, 0.48])
NEBULA_BRIGHTNESS = (
    0.04,
    0.50,
)  # linear radiance of a splat's colour, before alpha blending


def _unit(v: np.ndarray) -> np.ndarray:
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def _direction(azimuth_deg: float, elevation_deg: float) -> np.ndarray:
    """Godot-frame unit vector; azimuth is measured from -Z (forward) towards +X (right)."""
    az, el = math.radians(azimuth_deg), math.radians(elevation_deg)
    return np.array(
        [math.sin(az) * math.cos(el), math.sin(el), -math.cos(az) * math.cos(el)]
    )


NEBULA_CENTER = _direction(NEBULA_AZIMUTH_DEG, NEBULA_ELEVATION_DEG)
# The Milky Way band is the great circle through the nebula centre, tilted against the horizon.
GALACTIC_NORMAL = _unit(np.cross(NEBULA_CENTER, np.array([0.6, 0.3, 0.74])))


def tangent_basis(n: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Two unit vectors orthogonal to each unit vector in ``n`` (shape ``(..., 3)``)."""
    n = np.asarray(n, dtype=float)
    helper = np.where(
        np.abs(n[..., 1:2]) > 0.95, np.array([1.0, 0.0, 0.0]), np.array([0.0, 1.0, 0.0])
    )
    e1 = _unit(np.cross(helper, n))
    e2 = np.cross(n, e1)
    return e1, e2


def _smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


class _ValueNoise:
    """Periodic 3D value noise and fBm, seeded from the build rng (vectorised, no dependencies)."""

    def __init__(self, rng: np.random.Generator, size: int = 32) -> None:
        self._size = size
        self._lattice = rng.random((size, size, size))

    def sample(self, p: np.ndarray) -> np.ndarray:
        size, lat = self._size, self._lattice
        cell = np.floor(p).astype(np.int64)
        f = p - cell
        s = f * f * (3.0 - 2.0 * f)
        x0, y0, z0 = (cell % size).T
        x1, y1, z1 = ((cell + 1) % size).T
        sx, sy, sz = s.T

        def mix(a: np.ndarray, b: np.ndarray, t: np.ndarray) -> np.ndarray:
            return a + (b - a) * t

        c00 = mix(lat[x0, y0, z0], lat[x1, y0, z0], sx)
        c10 = mix(lat[x0, y1, z0], lat[x1, y1, z0], sx)
        c01 = mix(lat[x0, y0, z1], lat[x1, y0, z1], sx)
        c11 = mix(lat[x0, y1, z1], lat[x1, y1, z1], sx)
        return mix(mix(c00, c10, sy), mix(c01, c11, sy), sz)

    def fbm(self, p: np.ndarray, octaves: int = 5, gain: float = 0.5) -> np.ndarray:
        """Fractal Brownian motion, roughly centred on 0.5 within [0, 1]."""
        total = np.zeros(len(p))
        amplitude, norm, freq = 1.0, 0.0, 1.0
        for octave in range(octaves):
            total += amplitude * self.sample(p * freq + 17.31 * octave)
            norm += amplitude
            amplitude *= gain
            freq *= 2.03
        return total / norm


# --- stars -----------------------------------------------------------------------------------
def _uniform_directions(rng: np.random.Generator, n: int) -> np.ndarray:
    z = rng.uniform(-1.0, 1.0, n)
    phi = rng.uniform(0.0, 2.0 * math.pi, n)
    r = np.sqrt(1.0 - z * z)
    return np.stack([r * np.cos(phi), z, r * np.sin(phi)], axis=1)


def _band_directions(rng: np.random.Generator, n: int) -> np.ndarray:
    b = np.clip(
        rng.normal(0.0, math.radians(BAND_SIGMA_DEG), n),
        -math.radians(70),
        math.radians(70),
    )
    lon = rng.uniform(0.0, 2.0 * math.pi, n)
    u1, u2 = tangent_basis(GALACTIC_NORMAL)
    around = np.cos(lon)[:, None] * u1 + np.sin(lon)[:, None] * u2
    return np.cos(b)[:, None] * around + np.sin(b)[:, None] * GALACTIC_NORMAL


def generate_stars(rng: np.random.Generator, count: int, radius: float) -> SplatData:
    """Star catalogue as splats in the authoring (Godot) frame."""
    n_band = round(count * BAND_FRACTION)
    dirs = np.concatenate(
        [_band_directions(rng, n_band), _uniform_directions(rng, count - n_band)]
    )
    dirs = _unit(dirs[rng.permutation(count)])

    # Magnitude with pdf ~ 10^(0.5 m) on [min, max], by inverse CDF.
    span = STAR_MAG_MAX - STAR_MAG_MIN
    u = rng.random(count)
    mag = STAR_MAG_MIN + np.log10(1.0 + u * (10.0 ** (0.5 * span) - 1.0)) / 0.5
    brightness = 10.0 ** (
        -0.4 * STAR_BRIGHTNESS_GAMMA * (mag - STAR_MAG_MIN)
    )  # (0.09 .. 1]
    radiance = STAR_PEAK_RADIANCE * brightness**0.8
    sigma = (
        STAR_SIGMA_MAX_M
        * (0.4 + 0.6 * np.sqrt(brightness))
        * (radius / DEFAULT_RADIUS_M)
    )

    temps = np.array([t for t, _ in STAR_CLASSES])
    weights = np.array([w for _, w in STAR_CLASSES])
    temperature = temps[rng.choice(len(temps), size=count, p=weights / weights.sum())]
    temperature = np.clip(
        temperature * np.exp(rng.normal(0.0, 0.07, count)), 2400.0, 40000.0
    )
    tint = lerp(1.0, blackbody_rgb(temperature), STAR_TINT_STRENGTH)

    return SplatData(
        xyz=dirs * radius,
        rgb=tint * radiance[:, None],
        alpha=np.ones(count),
        scale=np.repeat(sigma[:, None], 3, axis=1),
        rot=frames.quat_identity(count),
        normals=-dirs,
    )


# --- nebula ----------------------------------------------------------------------------------
def generate_nebula(rng: np.random.Generator, count: int, radius: float) -> SplatData:
    """Nebula gas as large soft splats in the authoring (Godot) frame."""
    noise = _ValueNoise(rng)
    east, north = tangent_basis(NEBULA_CENTER)

    blobs = np.array(NEBULA_BLOBS)
    blobs[:, :2] += rng.normal(0.0, 1.5, (len(blobs), 2))  # seeded jitter in degrees
    pool = count * 3  # candidates; fBm weighting then keeps `count` of them
    blob_p = blobs[:, 2] ** 2 / np.sum(blobs[:, 2] ** 2)  # bigger blobs hold more gas
    blob_id = rng.choice(len(blobs), size=pool, p=blob_p)
    offset = np.radians(
        blobs[blob_id, :2] + rng.normal(0.0, 1.0, (pool, 2)) * blobs[blob_id, 2:3]
    )
    rho = np.hypot(offset[:, 0], offset[:, 1])
    phi = np.arctan2(offset[:, 1], offset[:, 0])
    cand = np.cos(rho)[:, None] * NEBULA_CENTER + np.sin(rho)[:, None] * (
        np.cos(phi)[:, None] * east + np.sin(phi)[:, None] * north
    )
    cand = _unit(cand)

    density = _smoothstep((noise.fbm(cand * NEBULA_NOISE_FREQ) - 0.38) / 0.30)
    weight = 0.01 + density**3
    keep = rng.choice(pool, size=count, replace=False, p=weight / np.sum(weight))
    d, blob_id, density = cand[keep], blob_id[keep], density[keep]

    r = radius * rng.uniform(*NEBULA_RADIUS_SPREAD, count)

    # Orientation: the long axis follows a smooth field over the sky, so splats line up into filaments.
    t1, t2 = tangent_basis(d)
    theta = 2.0 * math.pi * noise.fbm(d * 3.0 + 11.7, octaves=2) + rng.normal(
        0.0, 0.25, count
    )
    major = np.cos(theta)[:, None] * t1 + np.sin(theta)[:, None] * t2
    minor = np.cross(d, major)
    rotation = np.stack(
        [major, minor, d], axis=-1
    )  # columns = local x, y, z in world space

    elongation = 1.0 + (NEBULA_MAX_ELONGATION - 1.0) * rng.random(count)
    lo, hi = NEBULA_SIGMA_RANGE_M
    scale_unit = radius / DEFAULT_RADIUS_M
    sigma_minor = np.exp(rng.uniform(np.log(lo), np.log(hi / elongation))) * scale_unit
    scale = np.stack([sigma_minor * elongation, sigma_minor, sigma_minor], axis=1)

    # Two-tone colour: the blob sets the base tone, noise drifts it, density sets brightness.
    drift = noise.fbm(d * 5.0 + 3.1, octaves=3) - 0.5
    tone = _smoothstep(0.5 + 0.6 * (blobs[blob_id, 3] - 0.5) + 1.0 * drift)[:, None]
    brightness = (
        NEBULA_BRIGHTNESS[0] + (NEBULA_BRIGHTNESS[1] - NEBULA_BRIGHTNESS[0]) * density
    )
    rgb = lerp(NEBULA_TEAL, NEBULA_MAGENTA, tone) * brightness[:, None]

    a_lo, a_hi = NEBULA_ALPHA_RANGE
    alpha = a_lo + (a_hi - a_lo) * np.clip(
        0.6 * density + 0.4 * rng.random(count), 0.0, 1.0
    )

    return SplatData(
        xyz=d * r[:, None],
        rgb=rgb,
        alpha=alpha,
        scale=scale,
        rot=frames.matrix_to_quat(rotation),
        normals=-d,
    )


# --- panorama --------------------------------------------------------------------------------
def _load_pillow() -> Any | None:
    try:
        from PIL import Image
    except ImportError:
        return None
    return Image


def _direction_grid(width: int, height: int) -> np.ndarray:
    """Unit direction of every pixel centre of an equirectangular image (centre = -Z, +u = +X)."""
    lon = ((np.arange(width) + 0.5) / width - 0.5) * 2.0 * math.pi
    lat = (0.5 - (np.arange(height) + 0.5) / height) * math.pi
    cos_lat = np.cos(lat)[:, None]
    return np.stack(
        [
            np.sin(lon)[None, :] * cos_lat,
            np.broadcast_to(np.sin(lat)[:, None], (height, width)),
            -np.cos(lon)[None, :] * cos_lat,
        ],
        axis=-1,
    ).astype(np.float32)


def _lonlat(directions: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    lon = np.arctan2(directions[..., 0], -directions[..., 2])
    lat = np.arcsin(np.clip(directions[..., 1], -1.0, 1.0))
    return lon, lat


def _render_stars(
    stars: SplatData, width: int, height: int, channel: int
) -> np.ndarray:
    """One channel of the star layer: each star is a small Gaussian sprite on the pixel grid."""
    lon, lat = _lonlat(_unit(stars.xyz))
    px = (lon / (2.0 * math.pi) + 0.5) * width - 0.5
    py = (0.5 - lat / math.pi) * height - 0.5
    sigma_rel = stars.scale[:, 0] / stars.scale[:, 0].max()
    sigma_px = (0.35 + 0.8 * sigma_rel**2) * (width / 4096.0) ** 0.5

    offsets = np.arange(-3, 4)
    cx = np.round(px).astype(np.int64)[:, None, None] + offsets[None, None, :]
    cy = np.round(py).astype(np.int64)[:, None, None] + offsets[None, :, None]
    d2 = (cx - px[:, None, None]) ** 2 + (cy - py[:, None, None]) ** 2
    amp = stars.rgb[:, channel, None, None] * np.exp(
        -0.5 * d2 / sigma_px[:, None, None] ** 2
    )
    amp = np.where((cy >= 0) & (cy < height), amp, 0.0)
    index = np.clip(cy, 0, height - 1) * width + (cx % width)
    layer = np.bincount(index.ravel(), weights=amp.ravel(), minlength=width * height)
    return layer.reshape(height, width).astype(np.float32)


def _render_nebula(
    nebula: SplatData, width: int, height: int
) -> tuple[np.ndarray, np.ndarray]:
    """Alpha-composite the nebula far to near. Returns premultiplied linear RGB and coverage."""
    grid = _direction_grid(width, height)
    colour = np.zeros((height, width, 3), dtype=np.float32)
    coverage = np.zeros((height, width), dtype=np.float32)

    dist = np.linalg.norm(nebula.xyz, axis=1)
    n = nebula.xyz / dist[:, None]
    e1, e2 = tangent_basis(n)
    rot = frames.quat_to_matrix(nebula.rot)
    cov3 = np.einsum("nij,nj,nkj->nik", rot, nebula.scale**2, rot)
    basis = np.stack([e1, e2], axis=-1)  # (N, 3, 2)
    cov2 = np.einsum("nia,nij,njb->nab", basis, cov3, basis) / (dist**2)[:, None, None]
    det = cov2[:, 0, 0] * cov2[:, 1, 1] - cov2[:, 0, 1] ** 2
    inv = (
        np.stack([cov2[:, 1, 1], -cov2[:, 0, 1], cov2[:, 0, 0]], axis=1) / det[:, None]
    )
    trace = cov2[:, 0, 0] + cov2[:, 1, 1]
    sigma_max = np.sqrt(0.5 * (trace + np.sqrt(np.maximum(trace**2 - 4.0 * det, 0.0))))
    reach = 3.0 * sigma_max  # radians
    lon0, lat0 = _lonlat(n)

    for i in np.argsort(-dist, kind="stable"):
        lat_hi, lat_lo = lat0[i] + reach[i], lat0[i] - reach[i]
        row0 = max(0, math.floor((0.5 - lat_hi / math.pi) * height - 0.5))
        row1 = min(height - 1, math.ceil((0.5 - lat_lo / math.pi) * height - 0.5))
        cos_edge = math.cos(min(max(abs(lat_hi), abs(lat_lo)), math.pi / 2))
        if (
            lat_hi >= math.pi / 2
            or lat_lo <= -math.pi / 2
            or reach[i] >= cos_edge * math.pi
        ):
            cols = np.arange(width)
        else:
            half = reach[i] / cos_edge
            col0 = math.floor(
                (lon0[i] - half) / (2.0 * math.pi) * width + width / 2 - 0.5
            )
            col1 = math.ceil(
                (lon0[i] + half) / (2.0 * math.pi) * width + width / 2 - 0.5
            )
            cols = (
                np.arange(col0, col1 + 1) % width
                if col1 - col0 + 1 < width
                else np.arange(width)
            )
        window = np.ix_(np.arange(row0, row1 + 1), cols)
        d = grid[window]
        facing = d @ n[i].astype(np.float32)
        safe = np.maximum(facing, 0.05)
        u = (d @ e1[i].astype(np.float32)) / safe
        v = (d @ e2[i].astype(np.float32)) / safe
        m = inv[i, 0] * u * u + 2.0 * inv[i, 1] * u * v + inv[i, 2] * v * v
        a = np.where(facing > 0.05, nebula.alpha[i] * np.exp(-0.5 * m), 0.0).astype(
            np.float32
        )
        colour[window] = (
            colour[window] * (1.0 - a)[..., None]
            + nebula.rgb[i].astype(np.float32) * a[..., None]
        )
        coverage[window] = coverage[window] * (1.0 - a) + a
    return colour, coverage


def _resize_bilinear(layer: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    """Bilinear resize of a 2D float layer, wrapping horizontally (it is a panorama)."""
    h, w = layer.shape
    xs = (np.arange(out_w) + 0.5) * w / out_w - 0.5
    x0 = np.floor(xs).astype(np.int64)
    fx = (xs - x0).astype(np.float32)
    wide = layer[:, x0 % w] * (1.0 - fx) + layer[:, (x0 + 1) % w] * fx
    ys = (np.arange(out_h) + 0.5) * h / out_h - 0.5
    y0 = np.floor(ys).astype(np.int64)
    fy = (ys - y0).astype(np.float32)[:, None]
    return (
        wide[np.clip(y0, 0, h - 1)] * (1.0 - fy) + wide[np.clip(y0 + 1, 0, h - 1)] * fy
    )


def render_panorama(
    stars: SplatData, nebula: SplatData, width: int, height: int
) -> np.ndarray:
    """Equirectangular ``(height, width, 3)`` uint8 sRGB render of the sky, as seen from the origin.

    ``stars`` and ``nebula`` are in the authoring frame (not re-centred). The nebula is composited
    at quarter resolution (it is smooth) and upsampled; stars are drawn at full resolution.
    """
    low_w, low_h = max(width // 4, 8), max(height // 4, 4)
    neb_colour, neb_cover = _render_nebula(nebula, low_w, low_h)
    cover = _resize_bilinear(neb_cover, height, width)
    image = np.empty((height, width, 3), dtype=np.uint8)
    for channel in range(3):
        starlight = _render_stars(stars, width, height, channel)
        layer = _resize_bilinear(neb_colour[..., channel], height, width)
        # Half the stars sit behind the gas (they are spread through its depth), half in front.
        linear = layer + starlight * (1.0 - 0.5 * cover)
        display = 1.0 - np.exp(-1.5 * linear)
        image[..., channel] = np.round(linear_to_srgb(display) * 255.0).astype(np.uint8)
    return image


# --- build -----------------------------------------------------------------------------------
def build(ctx: BuildContext) -> AssetOutputs:
    """Generate ``sky_default.ply`` (+ optional panorama) and ``manifest.json`` into ``ctx.out_dir``.

    Options: ``stars``, ``nebula`` (counts), ``radius_m``, ``panorama`` (bool),
    ``panorama_size`` ((width, height)).
    """
    n_stars = int(ctx.option("stars", DEFAULT_STARS))
    n_nebula = int(ctx.option("nebula", DEFAULT_NEBULA))
    radius = float(ctx.option("radius_m", DEFAULT_RADIUS_M))
    want_panorama = bool(ctx.option("panorama", True))
    pano_w, pano_h = (
        int(v) for v in ctx.option("panorama_size", DEFAULT_PANORAMA_SIZE)
    )
    if n_stars < 1 or n_nebula < 1 or radius <= 0:
        raise ValueError(
            "sky_default needs at least one star, one nebula splat and radius > 0"
        )

    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    stars = generate_stars(ctx.rng("stars"), n_stars, radius)
    nebula = generate_nebula(ctx.rng("nebula"), n_nebula, radius)
    authored = SplatData.concatenate([stars, nebula])

    # Re-centre on the centroid (what GDGS does on import anyway); keep the offset for the node.
    centroid = authored.xyz.mean(axis=0)
    centred = (authored.xyz - centroid).astype(np.float32)
    aabb_min, aabb_max = (
        centred.min(axis=0),
        centred.max(axis=0),
    )  # Godot frame, as in the manifest

    written = SplatData(
        xyz=frames.godot_to_3dgs_positions(centred.astype(np.float64)),
        rgb=authored.rgb,
        alpha=authored.alpha,
        scale=authored.scale,
        rot=frames.godot_to_3dgs_quats(authored.rot),
        normals=frames.flip_xy(authored.normals),
    )
    files: list[Path] = [
        write_ply(
            out_dir / PLY_NAME,
            written,
            comments=(
                f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",
                "frame: 3dgs (Rz180 of godot)",
            ),
        )
    ]

    warnings: list[str] = []
    manifest_files: dict[str, str] = {}
    panorama_path = out_dir / PANORAMA_NAME
    if want_panorama:
        image_module = _load_pillow()
        if image_module is None:
            warnings.append(
                f"Pillow is not installed: skipped {PANORAMA_NAME} (the PLY is unaffected; "
                "pip install pillow to build the mesh-fallback panorama)"
            )
        else:
            pixels = render_panorama(stars, nebula, pano_w, pano_h)
            image_module.fromarray(pixels).save(
                panorama_path, format="PNG", compress_level=6
            )
            files.append(panorama_path)
            manifest_files["panorama"] = PANORAMA_NAME
    if PANORAMA_NAME not in manifest_files.values():
        panorama_path.unlink(
            missing_ok=True
        )  # never leave a stale panorama the manifest does not list

    total = len(authored)
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        # For a sky "spacing" is the mean gap between splats on the sphere: sqrt(area per splat).
        lods=[
            lod_entry(
                0, PLY_NAME, total, round(radius * math.sqrt(4.0 * math.pi / total), 2)
            )
        ],
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=centroid,
        files=manifest_files,
        extra={
            "sky_radius_m": radius,
            "counts": {"stars": n_stars, "nebula": n_nebula},
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), tuple(warnings))
