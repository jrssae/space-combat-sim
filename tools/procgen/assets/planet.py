"""``planet``: a planet's surface maps, one asset per parameter set (M6-T11, D68). The first is ``epsilon_iii``.

Epsilon III follows the maintainer's show still (``docs/design-references.md``, "Epsilon III"): a dry rust, tan and ochre world,
dark brown lowlands, beige-cream highlands with pale patches toward the north, strong relief at every scale (ridges, wrinkled
ground, canyon grooves), no oceans, no city lights and at most thin pale wisps. Nothing is traced from the still: every map is
noise on the unit sphere, so it is seamless at the 0/360 degree seam and has no pinch at the poles.

Four equirectangular maps, each with a Godot ``.import`` sidecar:

* ``<id>_albedo.png``: sRGB colour.
* ``<id>_height.png``: elevation, grey, 0..255 over ``planet.maps.height.range_m``.
* ``<id>_normal.png``: tangent-space normals from the height (red east, green north, Godot's +Y up), relief exaggerated by
  ``planet.normal_exaggeration`` so the lit side reads bumpy from orbit.
* ``<id>_clouds.png``: the haze and wisp cover, grey, 0..1 opacity; the shader tints it.

The mapping is Godot's ``SphereMesh``: u = 0 looks toward +Z and grows toward +X (east), v = 0 is the north pole (+Y).

Size: from the station (Q2, 27 500 km out) the planet is about 20 degrees across a 70 degree, 1 080 line view, a disc about
270 px wide showing 162 px per radian of surface at its centre. A map 4 096 texels round holds 652 texels per radian: four per
pixel at the station (mipmaps keep the grain steady) and still one per pixel down to about 5 600 km altitude, where the planet
fills the view. The wisps are soft, so their map is half that size.

``look_sheet`` renders a lit-sphere preview beside the reference for the maintainer to judge; the game's look comes from the
atmosphere shader on the scaled-space layer (M6-T10, T11's shader half).
"""

from __future__ import annotations

import functools
import math
import os
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, replace
from pathlib import Path

import numpy as np

from ..core import panorama
from ..core.color import linear_to_srgb, srgb_to_linear
from ..core.context import AssetOutputs, BuildContext
from ..core.image import png_bytes, read_png, write_png
from ..core.manifest import build_manifest, write_manifest
from ..core.textured_mesh import import_sidecar

GENERATOR_VERSION = 1
MAP_KEYS = ("albedo", "height", "normal", "clouds")
PNG_FILTER_SUB = 1  # every planet map is stored with PNG's "sub" row filter: about half the bytes of unfiltered rows


@dataclass(frozen=True)
class PlanetSpec:
    """One planet's look as numbers; a new planet is a new spec. Colours are sRGB 0..255; frequencies are noise cells across one
    planet radius."""

    asset_id: str
    radius_m: float
    map_size: tuple[int, int] = (4096, 2048)
    cloud_size: tuple[int, int] = (2048, 1024)
    # Elevation colour ramp: (elevation 0..1, sRGB), lowest first.
    ramp: tuple[tuple[float, tuple[int, int, int]], ...] = ()
    rust: tuple[int, int, int] = (0, 0, 0)  # the redder mottle
    ochre: tuple[int, int, int] = (0, 0, 0)  # the yellower mottle
    pale: tuple[int, int, int] = (0, 0, 0)  # the pale northern patches
    cloud_srgb: tuple[int, int, int] = (0, 0, 0)  # a hint for the shader: the wisps' tint
    limb_srgb: tuple[int, int, int] = (0, 0, 0)  # a hint for the shader: the thin warm haze on the lit limb
    # Terrain.
    continent_freq: float = 1.6
    highland_level: float = 0.0  # continent noise above this is highland
    ridge_freq: float = 6.0
    wrinkle_freq: float = 64.0
    canyon_freq: float = 2.5
    canyon_width: float = 0.14
    warp: float = 0.35
    fine_warp: float = 0.06
    bump_freq: float = 20.0
    height_range_m: float = 16_000.0
    normal_exaggeration: float = 14.0
    # Pale patches: how far north they start and stop (degrees) and how much of that band they cover.
    pale_lat_deg: tuple[float, float] = (25.0, 70.0)
    pale_cover: float = 0.34
    # Wisps: their peak opacity.
    cloud_peak: float = 0.35
    ocean: bool = False
    night_lights: bool = False


EPSILON_III = PlanetSpec(
    asset_id="epsilon_iii",
    radius_m=4_780_000.0,  # Q1: 0.75 g at Earth's density
    # Read off the show still's lit side (5th to 99th percentile of its disc), lifted to albedo.
    ramp=(
        (0.00, (68, 44, 38)),
        (0.30, (110, 72, 60)),
        (0.48, (158, 104, 82)),
        (0.64, (182, 130, 100)),
        (0.80, (204, 158, 120)),
        (1.00, (226, 194, 152)),
    ),
    rust=(160, 96, 78),
    ochre=(180, 132, 92),
    pale=(232, 196, 158),
    cloud_srgb=(240, 226, 206),
    limb_srgb=(236, 150, 84),
)

PLANETS: dict[str, PlanetSpec] = {spec.asset_id: spec for spec in (EPSILON_III,)}


# --- the grid ---------------------------------------------------------------------------------
def latitudes(height: int) -> np.ndarray:
    """Latitude (radians) of each row centre, north first."""
    return (0.5 - (np.arange(height) + 0.5) / height) * math.pi


def longitudes(width: int) -> np.ndarray:
    """Longitude (radians) of each column centre: 0 at +Z, growing toward +X."""
    return (np.arange(width) + 0.5) / width * 2.0 * math.pi


def sphere_directions(width: int, height: int) -> np.ndarray:
    """The unit direction of every texel centre, ``(height, width, 3)`` float32, in the planet's frame."""
    lat, lon = latitudes(height)[:, None], longitudes(width)[None, :]
    cos_lat = np.cos(lat)
    return np.stack(
        [np.sin(lon) * cos_lat, np.broadcast_to(np.sin(lat), (height, width)), np.cos(lon) * cos_lat], axis=-1
    ).astype(np.float32)


def direction_to_uv(d: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Map coordinates (0..1) of unit directions in the planet's frame."""
    u = np.mod(np.arctan2(d[..., 0], d[..., 2]) / (2.0 * math.pi), 1.0)
    v = 0.5 - np.arcsin(np.clip(d[..., 1], -1.0, 1.0)) / math.pi
    return u, v


def tangent_frame(d: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """East and north unit vectors at unit directions ``d``: the normal map's red and green axes."""
    lon = np.arctan2(d[..., 0], d[..., 2])
    lat = np.arcsin(np.clip(d[..., 1], -1.0, 1.0))
    east = np.stack([np.cos(lon), np.zeros_like(lon), -np.sin(lon)], axis=-1)
    north = np.stack([-np.sin(lat) * np.sin(lon), np.cos(lat), -np.sin(lat) * np.cos(lon)], axis=-1)
    return east, north


# --- noise ------------------------------------------------------------------------------------
_GRADIENTS = np.array(
    [(1, 1, 0), (-1, 1, 0), (1, -1, 0), (-1, -1, 0), (1, 0, 1), (-1, 0, 1), (1, 0, -1), (-1, 0, -1),
     (0, 1, 1), (0, -1, 1), (0, 1, -1), (0, -1, -1), (1, 1, 0), (-1, 1, 0), (0, -1, 1), (0, -1, -1)],
    dtype=np.float32,
)  # fmt: skip


_PRIMES = (np.uint32(0x8DA6B343), np.uint32(0xD8163841), np.uint32(0xCB1AB31F))


def _mix(h: np.ndarray) -> np.ndarray:
    """Scrambles a 32-bit corner key, so neighbouring corners get unrelated gradients and high octaves never repeat."""
    h ^= h >> np.uint32(15)
    h *= np.uint32(0x2C1B3C6D)
    h ^= h >> np.uint32(12)
    h *= np.uint32(0x297A2D39)
    h ^= h >> np.uint32(15)
    return h


def gradient_noise(points: np.ndarray, seed: int) -> np.ndarray:
    """Seeded 3D gradient noise in about [-1, 1] at ``points`` ``(..., 3)``, one lattice cell per unit."""
    p = np.asarray(points, dtype=np.float32)
    shape = p.shape[:-1]
    p = p.reshape(-1, 3)
    cell = np.floor(p)
    f = p - cell
    c = cell.astype(np.int32).view(np.uint32)
    u = f * f * f * (f * (f * np.float32(6.0) - np.float32(15.0)) + np.float32(10.0))
    keys = [[c[:, a] * _PRIMES[a], (c[:, a] + np.uint32(1)) * _PRIMES[a]] for a in range(3)]
    keys[0][0] ^= np.uint32(seed & 0xFFFFFFFF)
    keys[0][1] ^= np.uint32(seed & 0xFFFFFFFF)
    offsets = [[f[:, a], f[:, a] - np.float32(1.0)] for a in range(3)]
    corners = []
    for dz in (0, 1):
        for dy in (0, 1):
            yz = keys[1][dy] ^ keys[2][dz]
            for dx in (0, 1):
                g = _GRADIENTS[_mix(keys[0][dx] ^ yz) & np.uint32(15)]
                corners.append(g[:, 0] * offsets[0][dx] + g[:, 1] * offsets[1][dy] + g[:, 2] * offsets[2][dz])
    ux, uy, uz = u[:, 0], u[:, 1], u[:, 2]
    x00 = corners[0] + ux * (corners[1] - corners[0])
    x10 = corners[2] + ux * (corners[3] - corners[2])
    x01 = corners[4] + ux * (corners[5] - corners[4])
    x11 = corners[6] + ux * (corners[7] - corners[6])
    y0 = x00 + uy * (x10 - x00)
    y1 = x01 + uy * (x11 - x01)
    return (y0 + uz * (y1 - y0)).reshape(shape)


# Texels per lattice cell a layer is computed at before it is enlarged to the map: enough that bilinear enlarging is exact to a
# few per cent of the noise's swing and leaves no creases in the normals. Colour-only layers may go coarser.
TEXELS_PER_CELL = 8.0
COLOUR_TEXELS_PER_CELL = 4.0
MIN_LAYER_WIDTH = 256
# Row chunks are pure functions of their rows, so they run on threads (NumPy releases the GIL) with the same bytes as one thread.
THREADS = max(1, min(8, os.cpu_count() or 1))


class SphereSampler:
    """Noise layers on one equirectangular map. Each layer is computed at the coarsest size its frequency allows and enlarged,
    so the low octaves cost almost nothing; ``warp`` (a smooth displacement on the sphere) bends every layer it is given."""

    def __init__(self, width: int, height: int, seed: int, chunk_rows: int = 256) -> None:
        self.width, self.height, self.seed = width, height, seed
        self._chunk_rows = chunk_rows
        self._dirs: dict[int, np.ndarray] = {}
        self._warp: np.ndarray | None = None
        self._stretch = np.ones(3, dtype=np.float32)
        self._warp_cache: dict[int, np.ndarray] = {}

    def layer_width(self, freq: float, texels: float = TEXELS_PER_CELL) -> int:
        need = texels * 2.0 * math.pi * freq
        width = MIN_LAYER_WIDTH
        while width < need and width < self.width:
            width *= 2
        return min(width, self.width)

    def directions(self, width: int) -> np.ndarray:
        if width not in self._dirs:
            self._dirs[width] = sphere_directions(width, width // 2)
        return self._dirs[width]

    def set_warp(self, warp: np.ndarray | None, stretch: tuple[float, float, float] = (1.0, 1.0, 1.0)) -> None:
        """A full-size ``(height, width, 3)`` displacement added to every later layer's sample points (``None`` to stop), and a
        per-axis scale of those points (above 1 makes the noise finer along that axis)."""
        self._warp = warp
        self._stretch = np.asarray(stretch, dtype=np.float32)
        self._warp_cache = {}

    def _points(self, width: int) -> np.ndarray:
        d = self.directions(width)
        if self._warp is None:
            return d * self._stretch
        if width not in self._warp_cache:
            if width == self.width:
                self._warp_cache[width] = self._warp
            else:
                self._warp_cache[width] = np.stack(
                    [panorama.resize_bilinear(self._warp[..., k], width // 2, width) for k in range(3)], axis=-1
                ).astype(np.float32)
        return (d + self._warp_cache[width]) * self._stretch

    def noise(self, freq: float, salt: int, texels: float = TEXELS_PER_CELL) -> np.ndarray:
        """One octave: gradient noise of ``freq`` cells per radius, full size ``(height, width)`` float32."""
        width = self.layer_width(freq, texels)
        seed = (self.seed * 0x9E3779B1 + salt * 0x85EBCA77) & 0xFFFFFFFF
        out = self._evaluate(self._points(width), freq, seed)
        if width == self.width:
            return out
        full = panorama.resize_bilinear(out, self.height, self.width).astype(np.float32)
        # Enlarging in latitude and longitude pinwheels the poles (every fine row above the coarse grid's first row copies it), so
        # the caps two coarse rows deep are computed exactly and blended in.
        cap = min(self.height // 2, math.ceil(2 * self.height / (width // 2)))
        fine = self._points(self.width)
        blend = smoothstep(0.0, 1.0, (cap - 0.5 - np.arange(cap, dtype=np.float32)) / (cap * 0.5))[:, None]
        for rows in (slice(0, cap), slice(self.height - cap, self.height)):
            exact = self._evaluate(fine[rows], freq, seed)
            weight = blend if rows.start == 0 else blend[::-1]
            full[rows] = exact * weight + full[rows] * (1.0 - weight)
        return full

    def _evaluate(self, points: np.ndarray, freq: float, seed: int) -> np.ndarray:
        out = np.empty(points.shape[:2], dtype=np.float32)

        def rows(r: int) -> None:
            out[r : r + self._chunk_rows] = gradient_noise(points[r : r + self._chunk_rows] * np.float32(freq), seed)

        starts = range(0, points.shape[0], self._chunk_rows)
        if THREADS > 1 and len(starts) > 1:
            with ThreadPoolExecutor(THREADS) as pool:
                list(pool.map(rows, starts))
        else:
            for r in starts:
                rows(r)
        return out

    def fbm(self, freq: float, octaves: int, salt: int, gain: float = 0.5, lacunarity: float = 2.0,
            texels: float = TEXELS_PER_CELL) -> np.ndarray:
        """Fractal sum of octaves, normalised to about [-1, 1]."""
        total = np.zeros((self.height, self.width), dtype=np.float32)
        amp, norm = 1.0, 0.0
        for k in range(octaves):
            total += np.float32(amp) * self.noise(freq * lacunarity**k, salt * 101 + k, texels)
            norm += amp
            amp *= gain
        return total / np.float32(norm * 0.6)

    def ridged(self, freq: float, octaves: int, salt: int, gain: float = 0.5, lacunarity: float = 2.0) -> np.ndarray:
        """Ridged multifractal in about [0, 1]: sharp crests where the noise crosses zero, each octave stronger on the last's
        crests, so ridges branch into wrinkles."""
        total = np.zeros((self.height, self.width), dtype=np.float32)
        weight = np.ones((self.height, self.width), dtype=np.float32)
        amp, norm = 1.0, 0.0
        for k in range(octaves):
            crest = 1.0 - np.abs(self.noise(freq * lacunarity**k, salt * 101 + k))
            crest = crest * crest
            total += np.float32(amp) * crest * weight
            weight = np.clip(crest * 1.6, 0.0, 1.0)
            norm += amp
            amp *= gain
        return total / np.float32(norm)

    def billow(self, freq: float, octaves: int, salt: int, gain: float = 0.5, lacunarity: float = 2.0) -> np.ndarray:
        """Billowed noise in about [0, 1]: rounded lumps with creases between them, the still's cauliflower ground."""
        total = np.zeros((self.height, self.width), dtype=np.float32)
        amp, norm = 1.0, 0.0
        for k in range(octaves):
            total += np.float32(amp) * np.abs(self.noise(freq * lacunarity**k, salt * 101 + k))
            norm += amp
            amp *= gain
        return total / np.float32(norm * 0.5)


def smoothstep(lo: float, hi: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# --- terrain ----------------------------------------------------------------------------------
@dataclass
class Terrain:
    """The fields the maps are made from, full size, float32: elevation 0..1 and what shaped it."""

    height: np.ndarray  # 0..1
    highland: np.ndarray  # 0 lowland .. 1 highland
    groove: np.ndarray  # 0 .. 1 at a canyon floor
    crest: np.ndarray  # ridge crests, 0..1
    grain: np.ndarray  # the lumpy hills, about -1..1


def make_terrain(spec: PlanetSpec, sampler: SphereSampler) -> Terrain:
    """Continents, ridges, lumpy hills, wrinkles and canyons, all on the sphere."""
    # A slow bend of the sample points, so coasts and canyons curve instead of following the noise lattice. The fine layers get
    # only a little of it: a strong bend drags small features into swirls.
    sampler.set_warp(None)
    bend = np.stack([sampler.fbm(1.2, 3, salt=10 + k) for k in range(3)], axis=-1)
    sampler.set_warp(bend * np.float32(spec.warp))
    continent = sampler.fbm(spec.continent_freq, 5, salt=1, gain=0.55)
    highland = smoothstep(spec.highland_level - 0.25, spec.highland_level + 0.35, continent)
    # Canyons: long sinuous grooves where a smooth field crosses zero, on the highland's slopes and plateaus, in some regions.
    field = sampler.fbm(spec.canyon_freq, 3, salt=5, gain=0.4)

    sampler.set_warp(bend * np.float32(spec.fine_warp))
    width = np.float32(spec.canyon_width) * (0.5 + 0.5 * smoothstep(-0.6, 0.6, sampler.fbm(spec.canyon_freq * 4.0, 2, salt=6)))
    floor = np.clip(np.abs(field) / width, 0.0, 1.0)
    groove = (1.0 - floor * floor) ** 2
    groove *= smoothstep(-0.2, 0.4, highland) * smoothstep(-0.2, 0.3, sampler.fbm(spec.canyon_freq * 0.6, 2, salt=7))

    ridges = sampler.ridged(spec.ridge_freq, 3, salt=2, gain=0.5)
    hills = sampler.billow(spec.bump_freq, 4, salt=3, gain=0.55)
    wrinkle = sampler.ridged(spec.wrinkle_freq, 3, salt=4, gain=0.55)
    sampler.set_warp(None)

    relief = 0.45 + 0.55 * highland
    h = (
        0.50 * continent
        + 0.16 * relief * (ridges - 0.3)
        + 0.16 * relief * (hills - 0.4)
        + 0.03 * relief * (wrinkle - 0.3)
        - 0.12 * groove
    )
    lo, hi = np.percentile(h, [0.2, 99.8])
    height = np.clip((h - lo) / (hi - lo), 0.0, 1.0).astype(np.float32)
    return Terrain(height=height, highland=highland.astype(np.float32), groove=groove.astype(np.float32),
                   crest=np.clip(ridges, 0.0, 1.0).astype(np.float32), grain=(2.0 * hills - 0.8).astype(np.float32))


# --- the maps ---------------------------------------------------------------------------------
def ramp_colour(ramp: tuple[tuple[float, tuple[int, int, int]], ...], t: np.ndarray) -> np.ndarray:
    """Linear colour of the elevation ramp at ``t`` (0..1), ``(..., 3)``; the stops blend in linear light."""
    stops = np.array([s for s, _ in ramp], dtype=np.float32)
    colours = srgb_to_linear(np.array([c for _, c in ramp], dtype=np.float32) / 255.0).astype(np.float32)
    return np.stack([np.interp(t, stops, colours[:, k]).astype(np.float32) for k in range(3)], axis=-1)


def _linear(srgb: tuple[int, int, int]) -> np.ndarray:
    return srgb_to_linear(np.array(srgb, dtype=np.float32) / 255.0).astype(np.float32)


def albedo_map(spec: PlanetSpec, terrain: Terrain, sampler: SphereSampler) -> np.ndarray:
    """``(height, width, 3)`` uint8 sRGB: the elevation ramp, mottled rust and ochre, dark canyon floors, pale crests and the
    pale northern patches."""
    h = terrain.height
    colour = ramp_colour(spec.ramp, h)

    # Broad rust and ochre drifts and a finer mottle, as the still's lit side shows.
    drift = sampler.fbm(3.0, 4, salt=20, texels=COLOUR_TEXELS_PER_CELL)
    mottle = sampler.fbm(24.0, 3, salt=21, texels=COLOUR_TEXELS_PER_CELL)
    tone = smoothstep(-0.8, 0.8, 0.7 * drift + 0.5 * mottle)[..., None]
    rust, ochre = _linear(spec.rust), _linear(spec.ochre)
    hue = rust / rust.mean() * (1.0 - tone) + ochre / ochre.mean() * tone
    colour = colour + 0.35 * (colour.mean(axis=-1, keepdims=True) * hue - colour)

    # Relief in the colour: darker canyon floors, lighter exposed crests, darker hollows between the lumps.
    colour *= (1.0 - 0.12 * terrain.groove)[..., None]
    colour *= (0.92 + 0.16 * terrain.crest * (0.4 + 0.6 * terrain.highland))[..., None]
    colour *= (1.0 + 0.08 * terrain.grain)[..., None]

    # Pale patches on the high ground, most of them toward the north: high ground or haze, not ice.
    lat = np.degrees(latitudes(sampler.height))[:, None]
    band = 0.3 + 0.7 * smoothstep(spec.pale_lat_deg[0], spec.pale_lat_deg[1], lat)
    blotch = smoothstep(1.0 - 2.5 * spec.pale_cover, 1.0 - 0.5 * spec.pale_cover,
                        0.5 + 0.5 * sampler.fbm(4.0, 5, salt=22, texels=COLOUR_TEXELS_PER_CELL))
    pale = (band * blotch * smoothstep(0.35, 0.85, terrain.height) * (1.0 - 0.5 * terrain.groove))[..., None]
    colour = colour + 0.75 * pale * (_linear(spec.pale) - colour)

    return np.clip(np.rint(linear_to_srgb(np.clip(colour, 0.0, 1.0)) * 255.0), 0, 255).astype(np.uint8)


def normals_from_height(height_m: np.ndarray, radius_m: float, exaggeration: float) -> np.ndarray:
    """Tangent-space unit normals ``(height, width, 3)`` (east, north, up) of an equirectangular height field in metres.

    Steps are true distances on the sphere; across a pole the neighbour row is the same row half a turn round, so the poles need
    no special case.
    """
    hgt = np.asarray(height_m, dtype=np.float64)
    rows, cols = hgt.shape
    lat = latitudes(rows)
    step_e = radius_m * np.cos(lat) * 2.0 * math.pi / cols
    step_n = radius_m * math.pi / rows
    d_east = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) / (2.0 * step_e[:, None])
    half = cols // 2
    padded = np.concatenate([np.roll(hgt[:1], half, axis=1), hgt, np.roll(hgt[-1:], half, axis=1)], axis=0)
    d_north = (padded[:-2] - padded[2:]) / (2.0 * step_n)
    n = np.stack([-exaggeration * d_east, -exaggeration * d_north, np.ones_like(hgt)], axis=-1)
    return (n / np.linalg.norm(n, axis=-1, keepdims=True)).astype(np.float32)


def encode_normals(n: np.ndarray) -> np.ndarray:
    return np.clip(np.rint((n * 0.5 + 0.5) * 255.0), 0, 255).astype(np.uint8)


def decode_normals(rgb8: np.ndarray) -> np.ndarray:
    n = np.asarray(rgb8, dtype=np.float32) / 255.0 * 2.0 - 1.0
    return n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)


def height_metres(height01: np.ndarray, spec: PlanetSpec) -> np.ndarray:
    """Elevation in metres about the mean radius, from the 0..1 field."""
    return (np.asarray(height01, dtype=np.float32) - 0.5) * np.float32(spec.height_range_m)


def cloud_map(spec: PlanetSpec, terrain: Terrain, seed: int) -> np.ndarray:
    """``(height, width)`` uint8 opacity of the thin pale wisps: filaments drawn out east to west in patches over the brighter
    ground, fading out toward the poles."""
    width, height = spec.cloud_size
    sampler = SphereSampler(width, height, seed)
    bend = np.stack([sampler.fbm(1.5, 3, salt=40 + k) for k in range(3)], axis=-1) * np.float32(0.3)
    # Finer across latitude than along it: long east-west streaks.
    sampler.set_warp(bend, stretch=(1.0, 2.5, 1.0))
    filament = (1.0 - np.abs(sampler.fbm(4.0, 4, salt=44, gain=0.5))) ** 7
    sampler.set_warp(bend)
    patch = smoothstep(0.0, 0.7, sampler.fbm(2.0, 3, salt=45))
    sampler.set_warp(None)
    bright = smoothstep(0.4, 0.8, panorama.resize_bilinear(terrain.height, height, width))
    lat = np.abs(np.degrees(latitudes(height)))[:, None]
    wisp = filament * patch * bright * (1.0 - smoothstep(55.0, 75.0, lat))
    peak = max(float(np.percentile(wisp, 99.9)), 1e-6)
    cover = np.clip(wisp / peak, 0.0, 1.0) * spec.cloud_peak
    return np.clip(np.rint(cover * 255.0), 0, 255).astype(np.uint8)


# --- the build --------------------------------------------------------------------------------
@dataclass
class PlanetMaps:
    albedo: np.ndarray  # (h, w, 3) uint8 sRGB
    height: np.ndarray  # (h, w) uint8
    normal: np.ndarray  # (h, w, 3) uint8
    clouds: np.ndarray  # (h/2, w/2) uint8
    terrain: Terrain


def make_maps(spec: PlanetSpec, seed: int) -> PlanetMaps:
    width, height = spec.map_size
    sampler = SphereSampler(width, height, seed)
    terrain = make_terrain(spec, sampler)
    albedo = albedo_map(spec, terrain, sampler)
    normals = normals_from_height(height_metres(terrain.height, spec), spec.radius_m, spec.normal_exaggeration)
    height8 = np.clip(np.rint(terrain.height * 255.0), 0, 255).astype(np.uint8)
    clouds = cloud_map(spec, terrain, seed + 1)
    return PlanetMaps(albedo, height8, encode_normals(normals), clouds, terrain)


def _write_map(path: Path, pixels: np.ndarray, kind: str) -> list[Path]:
    path.write_bytes(png_bytes(pixels, row_filter=PNG_FILTER_SUB))
    sidecar = Path(str(path) + ".import")
    sidecar.write_text(import_sidecar(kind), encoding="utf-8", newline="\n")
    return [path, sidecar]


def build_planet(asset_id: str, ctx: BuildContext) -> AssetOutputs:
    """Generate the planet's four maps and ``manifest.json`` into ``ctx.out_dir``.

    Options: ``map_size`` and ``cloud_size`` ((width, height); tests build small).
    """
    spec = PLANETS[asset_id]
    map_size = tuple(int(v) for v in ctx.option("map_size", spec.map_size))
    cloud_size = tuple(int(v) for v in ctx.option("cloud_size", spec.cloud_size))
    for w, h in (map_size, cloud_size):
        if w != 2 * h or w < 64:
            raise ValueError(f"{asset_id}: equirectangular maps are twice as wide as tall and at least 64 wide, got {w}x{h}")
    spec = replace(spec, map_size=map_size, cloud_size=cloud_size)

    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    maps = make_maps(spec, ctx.seed)
    names = {key: f"{asset_id}_{key}.png" for key in MAP_KEYS}
    jobs = ((names["albedo"], maps.albedo, "albedo"), (names["height"], maps.height, "orm"),
            (names["normal"], maps.normal, "normal"), (names["clouds"], maps.clouds, "orm"))
    with ThreadPoolExecutor(min(THREADS, len(jobs))) as pool:  # zlib releases the GIL
        written = list(pool.map(lambda job: _write_map(out_dir / job[0], job[1], job[2]), jobs))
    files: list[Path] = [path for pair in written for path in pair]

    r = spec.radius_m
    mean_albedo = srgb_to_linear(maps.albedo.reshape(-1, 3).astype(np.float64) / 255.0).mean(axis=0)
    size = [map_size[0], map_size[1]]
    manifest = build_manifest(
        asset_id=asset_id,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=(-r, -r, -r),
        aabb_max=(r, r, r),
        centroid_offset=(0.0, 0.0, 0.0),
        files=names,
        extra={
            "planet": {
                "radius_m": r,
                "projection": "equirectangular",
                "uv": "SphereMesh: u = 0 at +Z growing toward +X (east), v = 0 at +Y (north pole)",
                "maps": {
                    "albedo": {"file": names["albedo"], "size": size, "format": "rgb8 srgb"},
                    "height": {"file": names["height"], "size": size, "format": "r8 linear",
                               "range_m": [-0.5 * spec.height_range_m, 0.5 * spec.height_range_m]},
                    "normal": {"file": names["normal"], "size": size, "format": "rgb8 tangent",
                               "tangent": "red east, green north, blue up"},
                    "clouds": {"file": names["clouds"], "size": [cloud_size[0], cloud_size[1]], "format": "r8 opacity",
                               "tint_srgb": list(spec.cloud_srgb)},
                },
                "normal_exaggeration": spec.normal_exaggeration,
                "cloud_peak": spec.cloud_peak,
                "mean_albedo": [round(float(v), 4) for v in mean_albedo],
                "atmosphere": {"limb_srgb": list(spec.limb_srgb), "ocean": spec.ocean, "night_lights": spec.night_lights},
            },
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(asset_id, out_dir, manifest, tuple(files), ())


BUILDERS: dict[str, Callable[[BuildContext], AssetOutputs]] = {
    asset_id: functools.partial(build_planet, asset_id) for asset_id in PLANETS
}


# --- the look sheet (a preview for the maintainer, not the game's shader) ----------------------
def _sample(image: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Bilinear lookup of an equirectangular ``(h, w, c)`` float image, wrapping in u."""
    h, w = image.shape[:2]
    x = u * w - 0.5
    y = np.clip(v * h - 0.5, 0.0, h - 1.0)
    x0, y0 = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
    fx, fy = (x - x0)[..., None], (y - y0)[..., None]
    x0w, x1w = x0 % w, (x0 + 1) % w
    y1 = np.minimum(y0 + 1, h - 1)
    top = image[y0, x0w] * (1 - fx) + image[y0, x1w] * fx
    bottom = image[y1, x0w] * (1 - fx) + image[y1, x1w] * fx
    return top * (1 - fy) + bottom * fy


def _halve(image: np.ndarray) -> np.ndarray:
    h, w = image.shape[:2]
    return image.reshape(h // 2, 2, w // 2, 2, -1).mean(axis=(1, 3))


def _rotation(yaw_deg: float, pitch_deg: float) -> np.ndarray:
    """Planet frame to view frame: turn the planet by ``yaw`` about its axis, then tip its north pole toward the viewer."""
    a, b = math.radians(yaw_deg), math.radians(pitch_deg)
    yaw = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
    pitch = np.array([[1, 0, 0], [0, math.cos(b), -math.sin(b)], [0, math.sin(b), math.cos(b)]])
    return pitch @ yaw


def render_disc(spec: PlanetSpec, albedo8: np.ndarray, normal8: np.ndarray, clouds8: np.ndarray, frame: tuple[int, int],
                centre: tuple[float, float], radius_px: float, yaw_deg: float = 0.0, pitch_deg: float = 20.0,
                light: tuple[float, float, float] = (0.78, 0.52, 0.34), exposure: float = 1.5) -> np.ndarray:
    """An orthographic lit-sphere render, ``(h, w, 3)`` uint8 sRGB on black: Lambert light from ``light`` (view frame, x right,
    y up, z toward the viewer) with a hard terminator, the normal map's relief, the wisps and a faint warm haze on the lit limb."""
    w, h = frame
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    px = (xs + 0.5 - centre[0]) / radius_px
    py = (centre[1] - ys - 0.5) / radius_px
    rr = px * px + py * py
    inside = rr < 1.0
    nz = np.sqrt(np.clip(1.0 - rr, 0.0, 1.0))
    n_view = np.stack([px, py, nz], axis=-1)
    l = np.array(light) / np.linalg.norm(light)
    rot = _rotation(yaw_deg, pitch_deg)
    d = n_view[inside] @ rot  # view to planet frame (rot is orthonormal)
    u, v = direction_to_uv(d)
    albedo = srgb_to_linear(_sample(_halve(albedo8.astype(np.float64) / 255.0), u, v))
    tangent = decode_normals(_sample(_halve(normal8.astype(np.float64)), u, v))
    cloud = _sample(clouds8.astype(np.float64)[..., None] / 255.0, u, v)
    east, north = tangent_frame(d)
    n_planet = tangent[:, :1] * east + tangent[:, 1:2] * north + tangent[:, 2:3] * d
    n_bumped = n_planet @ rot.T
    geo = n_view[inside] @ l
    lit = np.clip(n_bumped @ l, 0.0, None) * smoothstep(-0.02, 0.12, geo)
    sun = 1.0 * exposure
    colour = albedo * (sun * lit)[:, None] + 0.004 * albedo
    cloud_lit = cloud * (np.clip(geo, 0.0, None) * sun)[:, None]
    colour = colour * (1.0 - cloud) + _linear(spec.cloud_srgb) * cloud_lit
    rim = (1.0 - n_view[inside][:, 2]) ** 3 * smoothstep(-0.15, 0.5, geo)
    colour += 0.25 * rim[:, None] * _linear(spec.limb_srgb)
    image = np.zeros((h, w, 3))
    image[inside] = colour
    # A thin glow just outside the lit limb.
    outside = (~inside) & (rr < 1.08**2)
    edge = n_view[outside] / np.sqrt(rr[outside])[:, None]
    edge[:, 2] = 0.0
    glow = np.exp(-(np.sqrt(rr[outside]) - 1.0) / 0.012) * smoothstep(-0.1, 0.5, edge @ l)
    image[outside] = 0.18 * glow[:, None] * _linear(spec.limb_srgb)
    return np.clip(np.rint(linear_to_srgb(np.clip(image, 0.0, 1.0)) * 255.0), 0, 255).astype(np.uint8)


def _fit(image: np.ndarray, height: int) -> np.ndarray:
    """Box-filtered shrink (or nearest enlarge) to ``height`` rows, keeping the aspect."""
    h, w = image.shape[:2]
    width = max(1, round(w * height / h))
    ys = ((np.arange(height) + 0.5) * h / height).astype(np.int64)
    xs = ((np.arange(width) + 0.5) * w / width).astype(np.int64)
    if h >= 2 * height:
        k = h // height
        image = image[: (h // k) * k, : (w // k) * k].reshape(h // k, k, w // k, k, -1).mean(axis=(1, 3))
        return _fit(np.rint(image).astype(np.uint8), height)
    return image[ys][:, xs]


def look_sheet(asset_dir: Path, out_path: Path, reference: Path | None = None, asset_id: str = "epsilon_iii") -> Path:
    """The maintainer's sheet: the reference beside the preview in its framing (top), a whole-disc view and the flat albedo
    (bottom). Reads the built maps from ``asset_dir``."""
    spec = PLANETS[asset_id]
    albedo = read_png(asset_dir / f"{spec.asset_id}_albedo.png")
    normal = read_png(asset_dir / f"{spec.asset_id}_normal.png")
    clouds = read_png(asset_dir / f"{spec.asset_id}_clouds.png")
    frame = (1000, 561)
    framed = render_disc(spec, albedo, normal, clouds, frame, centre=(515.0, 335.0), radius_px=340.0, yaw_deg=40.0)
    whole = render_disc(spec, albedo, normal, clouds, (561, 561), centre=(280.5, 280.5), radius_px=250.0, yaw_deg=160.0,
                        pitch_deg=55.0)
    if reference is not None and Path(reference).is_file():
        ref = read_png(reference)[..., :3]
        ref = _fit(ref, frame[1])[:, : frame[0]]
    else:
        ref = np.zeros((frame[1], frame[0], 3), dtype=np.uint8)
    top = np.concatenate([_pad(ref, frame[0]), framed], axis=1)
    flat = _fit(albedo, frame[1])
    bottom = np.concatenate([whole, flat], axis=1)
    bottom = _pad(bottom, top.shape[1])
    sheet = np.concatenate([top, bottom], axis=0)
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    return write_png(out_path, sheet)


def _pad(image: np.ndarray, width: int) -> np.ndarray:
    h, w = image.shape[:2]
    if w >= width:
        return image[:, :width]
    return np.concatenate([image, np.zeros((h, width - w, 3), dtype=np.uint8)], axis=1)
