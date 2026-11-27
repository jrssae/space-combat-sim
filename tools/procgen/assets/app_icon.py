"""``app_icon``: the game's application icon (M9-T07, Q3), drawn by code: ``icon.ico`` for the Windows exe and ``icon.png``.

An original abstract mark with no franchise imagery: a tilted orbit ring around a small swept-wing craft that leaves a cyan
engine glow, on a deep-space rounded square. The ring's far half is drawn behind the craft and its near half in front, so the
craft sits inside the orbit.

The ``.ico`` holds seven sizes (16 to 256 px): the small ones as 32-bit bitmaps, which every Windows version reads, the large
ones as PNG. Each size is drawn at its own resolution (four samples a pixel), not shrunk from the biggest, so the small sizes
keep their edges; the tiny sizes drop the stars and thicken the ring so the mark still reads at 16 px.

Not a mesh or a sound: the manifest has an empty box, and lists the two files. ``scripts/build_release.sh`` exports the Windows
preset with ``icon.ico``, so ``scripts/gen_assets.sh`` must have built this asset first.
"""

from __future__ import annotations

import math
import struct
from pathlib import Path

import numpy as np

from ..core.context import AssetOutputs, BuildContext
from ..core.image import png_bytes
from ..core.manifest import build_manifest, write_manifest

ASSET_ID = "app_icon"
GENERATOR_VERSION = 1
ICO_NAME = "icon.ico"
PNG_NAME = "icon.png"
SIZES = (16, 24, 32, 48, 64, 128, 256)
PNG_MIN_SIZE = 128  # an .ico entry from this size up is PNG data; smaller ones are bitmaps
PNG_SIZE = 256
SAMPLES = 4  # per axis, per output pixel
STARS_MIN_SIZE = 48  # smaller icons would turn the stars into noise

# Colours are sRGB in 0..1; the icon is composited in sRGB, as an icon is meant to be seen.
SPACE_TOP = np.array([0.06, 0.09, 0.19])
SPACE_BOTTOM = np.array([0.015, 0.025, 0.07])
RING_COLOR = np.array([0.98, 0.66, 0.22])
CRAFT_LIGHT = np.array([0.93, 0.95, 0.98])
CRAFT_DARK = np.array([0.55, 0.62, 0.74])
GLOW_COLOR = np.array([0.30, 0.85, 1.0])
CORNER_RADIUS = 0.22
RING_TILT = math.radians(-28.0)
RING_RADII = (0.40, 0.17)  # semi-axes, as a fraction of the icon's side
RING_WIDTH = 0.05
CRAFT_ANGLE = math.radians(35.0)  # the nose turns this far from straight up, clockwise


def _grid(size: int) -> tuple[np.ndarray, np.ndarray]:
    """Sample centres in 0..1 (x right, y down) at SAMPLES per pixel."""
    n = size * SAMPLES
    axis = (np.arange(n) + 0.5) / n
    return np.meshgrid(axis, axis)


def _rotate(x: np.ndarray, y: np.ndarray, angle: float) -> tuple[np.ndarray, np.ndarray]:
    c, s = math.cos(angle), math.sin(angle)
    return x * c - y * s, x * s + y * c


def _inside_triangle(x: np.ndarray, y: np.ndarray, a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> np.ndarray:
    def side(p: tuple[float, float], q: tuple[float, float]) -> np.ndarray:
        return (q[0] - p[0]) * (y - p[1]) - (q[1] - p[1]) * (x - p[0])

    s1, s2, s3 = side(a, b), side(b, c), side(c, a)
    return ((s1 >= 0) & (s2 >= 0) & (s3 >= 0)) | ((s1 <= 0) & (s2 <= 0) & (s3 <= 0))


def _over(canvas: np.ndarray, color: np.ndarray, alpha: np.ndarray) -> None:
    """Composites ``color`` with per-sample ``alpha`` onto a premultiplied RGBA canvas."""
    canvas *= (1.0 - alpha)[..., None]
    canvas[..., :3] += color * alpha[..., None]
    canvas[..., 3] += alpha


def render_icon(size: int) -> np.ndarray:
    """The icon at ``size`` by ``size`` pixels: uint8 RGBA, straight (not premultiplied) alpha."""
    x, y = _grid(size)
    small = size < STARS_MIN_SIZE
    canvas = np.zeros(x.shape + (4,))

    # The sky: a vertical gradient with a faint teal haze behind the craft.
    sky = SPACE_TOP[None, None, :] * (1.0 - y)[..., None] + SPACE_BOTTOM[None, None, :] * y[..., None]
    haze = np.exp(-(((x - 0.5) ** 2 + (y - 0.5) ** 2) / 0.09))
    sky = sky + haze[..., None] * np.array([0.02, 0.10, 0.16])
    _over(canvas, sky, np.ones_like(x))

    if not small:
        rng = np.random.default_rng(7)  # fixed: the icon never depends on the build's seed
        for _ in range(26):
            sx, sy = rng.uniform(0.08, 0.92, 2)
            radius = rng.uniform(0.004, 0.011)
            glint = np.clip(1.0 - np.hypot(x - sx, y - sy) / radius, 0.0, 1.0)
            _over(canvas, np.array([0.85, 0.9, 1.0]), glint * rng.uniform(0.35, 0.9))

    # The ring in its own frame: u along the major axis, v across; v < 0 is the far half.
    ring_u, ring_v = _rotate(x - 0.5, y - 0.5, -RING_TILT)
    a, b = RING_RADII
    rho = np.hypot(ring_u / a, ring_v / b)
    width = RING_WIDTH * (1.6 if small else 1.0)
    ring = np.abs(rho - 1.0) * (a + b) / 2.0 < width / 2.0
    far_half = ring & (ring_v < 0)
    near_half = ring & (ring_v >= 0)
    _over(canvas, RING_COLOR * 0.62, far_half.astype(float))

    # The craft: a delta with a notched tail, two facets, nose up before it is turned.
    cx, cy = 0.5, 0.49
    craft_u, craft_v = _rotate(x - cx, y - cy, -CRAFT_ANGLE)
    nose, left, right, notch = (0.0, -0.26), (-0.19, 0.19), (0.19, 0.19), (0.0, 0.085)
    glow_d = np.hypot(craft_u / 0.07, (craft_v - 0.17) / 0.17)
    glow = np.clip(1.0 - glow_d, 0.0, 1.0) ** 1.6
    _over(canvas, GLOW_COLOR, glow * 0.9)
    _over(canvas, CRAFT_LIGHT, _inside_triangle(craft_u, craft_v, nose, left, notch).astype(float))
    _over(canvas, CRAFT_DARK, _inside_triangle(craft_u, craft_v, nose, notch, right).astype(float))
    cockpit = _inside_triangle(craft_u, craft_v, (0.0, -0.17), (-0.035, -0.04), (0.035, -0.04))
    _over(canvas, GLOW_COLOR * 0.75, cockpit.astype(float))
    _over(canvas, RING_COLOR, near_half.astype(float))

    # The rounded-square outline, as a signed distance to the box.
    qx, qy = np.abs(x - 0.5) - (0.5 - CORNER_RADIUS), np.abs(y - 0.5) - (0.5 - CORNER_RADIUS)
    outside = np.hypot(np.maximum(qx, 0.0), np.maximum(qy, 0.0)) + np.minimum(np.maximum(qx, qy), 0.0) - CORNER_RADIUS
    canvas *= (outside <= 0.0).astype(float)[..., None]
    rim = (outside <= 0.0) & (outside > -0.012)
    canvas[rim, :3] = canvas[rim, :3] * 0.6 + np.array([0.28, 0.45, 0.62]) * 0.4

    # Down to the output size, then straight alpha.
    small_canvas = canvas.reshape(size, SAMPLES, size, SAMPLES, 4).mean(axis=(1, 3))
    alpha = small_canvas[..., 3]
    out = np.zeros((size, size, 4))
    covered = alpha > 1e-6
    out[covered, :3] = small_canvas[covered, :3] / alpha[covered, None]
    out[..., 3] = alpha
    return np.clip(np.rint(out * 255.0), 0, 255).astype(np.uint8)


def _bitmap_entry(pixels: np.ndarray) -> bytes:
    """An .ico image as a 32-bit DIB: the header (height doubled for the mask), BGRA rows bottom up, an all-clear AND mask."""
    size = pixels.shape[0]
    header = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    bgra = pixels[::-1, :, [2, 1, 0, 3]]
    mask_row = ((size + 31) // 32) * 4
    return header + np.ascontiguousarray(bgra).tobytes() + bytes(mask_row * size)


def ico_bytes(images: dict[int, np.ndarray]) -> bytes:
    """The .ico file for square RGBA images keyed by their size (at most 256)."""
    entries = []
    for size in sorted(images):
        data = png_bytes(images[size]) if size >= PNG_MIN_SIZE else _bitmap_entry(images[size])
        entries.append((size, data))
    head = struct.pack("<HHH", 0, 1, len(entries))
    offset = len(head) + 16 * len(entries)
    directory, blobs = b"", b""
    for size, data in entries:
        dim = 0 if size >= 256 else size  # the directory byte is 0 for 256
        directory += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset + len(blobs))
        blobs += data
    return head + directory + blobs


def build(ctx: BuildContext) -> AssetOutputs:
    """Write ``icon.ico``, ``icon.png`` and ``manifest.json`` into ``ctx.out_dir``. The seed does not change the icon."""
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    images = {size: render_icon(size) for size in SIZES}
    ico_path, png_path = out_dir / ICO_NAME, out_dir / PNG_NAME
    ico_path.write_bytes(ico_bytes(images))
    png_path.write_bytes(png_bytes(images[PNG_SIZE]))
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=(0.0, 0.0, 0.0),
        aabb_max=(0.0, 0.0, 0.0),
        centroid_offset=(0.0, 0.0, 0.0),
        files={"ico": ICO_NAME, "png": PNG_NAME},
        extra={"icon": {"sizes": list(SIZES), "png_size": PNG_SIZE}},
    )
    return AssetOutputs(ASSET_ID, out_dir, manifest, (ico_path, png_path, write_manifest(out_dir, manifest)), ())
