"""``sky_default``: the starfield and nebula backdrop (docs/architecture.md section 9.2, M4-T30c).

Both are authored as soft blobs in the Godot frame (each a normal distribution in 3D: a centre, three sigmas, an orientation, a
colour and a peak opacity), the M3 sky's own data and seed, so the look the maintainer approved stays:

* **Stars**: ~12 000 round blobs on a sphere of radius R = 20 km around the origin. Direction
  density is uniform plus a Milky Way band (a great circle through the nebula); magnitudes follow
  ``dN/dm ~ 10^(0.5 m)``; colour is a blackbody tint from a spectral-class temperature table;
  bright stars are bigger (sigma 12 m = 0.6 mrad at R) and brighter than dim ones; opacity ~1.
* **Nebula**: ~4 000 large (300-2 000 m), soft, slightly elongated blobs in one ~40 degree
  region, clustered by a few groups and weighted by 3D fBm noise; two-tone teal/magenta; opacity
  0.021-0.079; filaments follow a smooth orientation field.

The game draws them from two files:

* ``sky_default_stars.f32``: the stars as point records, little-endian float32, seven per star: the unit direction
  (Godot frame), the linear colour tint (largest channel 1) and the brightness, the linear radiance of a disc of
  ``star_field.radius_mrad`` that delivers the light the M3 sky's star did at 1 080 lines (``REFERENCE_FOCAL_PX``), its colour
  decoded from sRGB. ``StarField`` draws them as camera-facing points with a 1 px floor.
* ``sky_default_panorama.png``: the nebula alone, its 4 000 blobs composited analytically into a 4 096 by 2 048 RGBA image
  (``core.panorama``, Godot's ``PanoramaSkyMaterial`` convention: the image centre looks toward +Z, +u turns toward -X; checked
  on a GPU by rolling the image half a turn). RGB is the gas's light, decoded from sRGB; alpha is its opacity over the stars,
  which the star points sample (Q42). A ``.import`` sidecar comes with it.

``manifest.centroid_offset`` and the bounds are the authored blobs' centroid and box about it.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np

from dataclasses import dataclass

from ..core import panorama, rotations
from ..core.color import blackbody_rgb, lerp, srgb_to_linear
from ..core.context import AssetOutputs, BuildContext
from ..core.manifest import build_manifest, write_manifest

ASSET_ID = "sky_default"
GENERATOR_VERSION = 4  # 4: the star file and the panorama only (M4-T31)
PANORAMA_NAME = "sky_default_panorama.png"
STARS_NAME = "sky_default_stars.f32"
STAR_RECORD = ("dir_x", "dir_y", "dir_z", "red", "green", "blue", "brightness")

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
)  # linear radiance of a blob's colour, before alpha blending


@dataclass(frozen=True)
class Blobs:
    """Soft blobs: centres ``(N, 3)``, linear colours ``(N, 3)``, peak opacities ``(N,)``, sigmas ``(N, 3)`` and orientations as
    quaternions ``(N, 4)``."""

    xyz: np.ndarray
    rgb: np.ndarray
    alpha: np.ndarray
    scale: np.ndarray
    rot: np.ndarray

    def __len__(self) -> int:
        return len(self.xyz)


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


def generate_stars(rng: np.random.Generator, count: int, radius: float) -> Blobs:
    """Star catalogue as round blobs in the authoring (Godot) frame."""
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

    return Blobs(
        xyz=dirs * radius,
        rgb=tint * radiance[:, None],
        alpha=np.ones(count),
        scale=np.repeat(sigma[:, None], 3, axis=1),
        rot=rotations.quat_identity(count),
    )


# --- nebula ----------------------------------------------------------------------------------
def generate_nebula(rng: np.random.Generator, count: int, radius: float) -> Blobs:
    """Nebula gas as large soft blobs in the authoring (Godot) frame."""
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

    # Orientation: the long axis follows a smooth field over the sky, so blobs line up into filaments.
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

    return Blobs(
        xyz=d * r[:, None],
        rgb=rgb,
        alpha=alpha,
        scale=scale,
        rot=rotations.matrix_to_quat(rotation),
    )


# --- star points (M4-T30c) ------------------------------------------------------------------
# A star point is a disc this wide; on any screen up to about 2 600 lines at 70 degrees it is under the 1 px floor, so only
# its delivered light shows (StarPointMath).
STAR_RADIUS_MRAD = 0.5
STAR_FLOOR_PX = 1.0
# The height the M3 sky was tuned at: 1 080 lines through the chase camera's 70 degree vertical field of view.
REFERENCE_FOCAL_PX = 540.0 / math.tan(math.radians(35.0))
# The M3 renderer widened every star's footprint by this many square pixels (its anti-aliasing); the approved look includes it.
STAR_SPREAD_PX2 = 0.3
# The light the point sprite's (1 - r^2)^2 profile delivers per unit brightness, over a disc of radius 1.
SPRITE_PROFILE_AREA = math.pi / 3.0


def star_points(stars: Blobs, radius: float) -> np.ndarray:
    """The star file's records, ``(N, 7)`` float32: direction, colour tint and the brightness that matches each M3 star's light.

    The M3 renderer decoded a star's colour from sRGB before it composited, so the light a star showed is the decoded colour, and
    so are the tint and the brightness here.
    """
    directions = _unit(stars.xyz)
    shown = srgb_to_linear(stars.rgb)
    radiance = shown.max(axis=1)
    tint = shown / radiance[:, None]
    sigma = stars.scale[:, 0] / radius
    star_light = radiance * 2.0 * math.pi * (sigma**2 + STAR_SPREAD_PX2 / REFERENCE_FOCAL_PX**2)
    rho = STAR_RADIUS_MRAD * 1e-3
    brightness = star_light / (SPRITE_PROFILE_AREA * rho * rho)
    return np.concatenate([directions, tint, brightness[:, None]], axis=1).astype("<f4")


# --- panorama --------------------------------------------------------------------------------
# The gas is smooth, so it is composited at half size and enlarged.
PANORAMA_NEBULA_SCALE = 2
# How much of a star's light the densest-looking gas holds back (Q42): the opacity follows the gas's brightness up to this, so
# the nebula dims the stars behind it and only the brighter ones shine through. Written as the panorama's alpha.
NEBULA_STAR_OPACITY = 0.8
# The gas brightness (a percentile of the texels with gas) that counts as fully dense.
NEBULA_DENSE_PERCENTILE = 99.9


def render_panorama(
    nebula: Blobs, width: int, height: int, rng: np.random.Generator | None = None
) -> np.ndarray:
    """Equirectangular ``(height, width, 4)`` uint8 render of the nebula as seen from the origin (authoring frame).

    RGB is the gas's light as the M3 sky showed it: the raw colours composited, then decoded from sRGB, then sRGB-encoded for the
    texture. Alpha is the gas's opacity over the stars. ``rng`` dithers both.
    """
    low_w = max(width // PANORAMA_NEBULA_SCALE, 8)
    low_h = max(height // PANORAMA_NEBULA_SCALE, 4)
    colour, coverage = panorama.composite_blobs(
        nebula.xyz, rotations.quat_to_matrix(nebula.rot), nebula.scale, nebula.rgb, nebula.alpha, low_w, low_h
    )
    cover = panorama.resize_bilinear(coverage, height, width)
    premultiplied = np.stack(
        [panorama.resize_bilinear(colour[..., c], height, width) for c in range(3)], axis=-1
    )
    straight = premultiplied / np.maximum(cover, 1e-6)[..., None]
    light = srgb_to_linear(np.clip(straight, 0.0, None)) * cover[..., None]
    image = np.empty((height, width, 4), dtype=np.uint8)
    image[..., :3] = panorama.to_srgb8(light, rng)
    brightness = light.max(axis=2)
    gas = brightness[cover > 0.01]
    dense = float(np.percentile(gas, NEBULA_DENSE_PERCENTILE)) if gas.size else 1.0
    opacity = NEBULA_STAR_OPACITY * np.clip(brightness / max(dense, 1e-9), 0.0, 1.0)
    image[..., 3] = panorama.quantize8(opacity * 255.0, rng)
    return image


# --- build -----------------------------------------------------------------------------------
def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the star file, the panorama (optional) and ``manifest.json`` into ``ctx.out_dir``.

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
            "sky_default needs at least one star, one nebula blob and radius > 0"
        )

    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    stars = generate_stars(ctx.rng("stars"), n_stars, radius)
    nebula = generate_nebula(ctx.rng("nebula"), n_nebula, radius)
    authored = np.concatenate([stars.xyz, nebula.xyz])
    centroid = authored.mean(axis=0)
    centred = (authored - centroid).astype(np.float32)
    aabb_min, aabb_max = centred.min(axis=0), centred.max(axis=0)  # Godot frame, about the centroid

    files: list[Path] = []
    manifest_files: dict[str, str] = {}
    stars_path = out_dir / STARS_NAME
    stars_path.write_bytes(star_points(stars, radius).tobytes())
    files.append(stars_path)
    manifest_files["stars"] = STARS_NAME

    panorama_path = out_dir / PANORAMA_NAME
    sidecar_path = Path(str(panorama_path) + ".import")
    if want_panorama:
        pixels = render_panorama(nebula, pano_w, pano_h, ctx.rng("panorama_dither"))
        files.extend(panorama.write_panorama(panorama_path, pixels))
        manifest_files["panorama"] = PANORAMA_NAME
    else:
        # Never leave a stale panorama the manifest does not list.
        panorama_path.unlink(missing_ok=True)
        sidecar_path.unlink(missing_ok=True)

    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=centroid,
        files=manifest_files,
        extra={
            "sky_radius_m": radius,
            "counts": {"stars": n_stars, "nebula": n_nebula},
            "star_field": {
                "file": STARS_NAME,
                "count": n_stars,
                "format": "float32 little-endian",
                "record": list(STAR_RECORD),
                "radius_mrad": STAR_RADIUS_MRAD,
                "floor_px": STAR_FLOOR_PX,
                "occlusion": "panorama alpha",
                "nebula_opacity": NEBULA_STAR_OPACITY,
            },
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
