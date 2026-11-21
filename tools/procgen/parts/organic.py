"""Organic parts: what the Shadows', the Vorlons' and the semi-organic hulls are grown from (M10-T06, D12.2;
docs/assets-capital.md, "Organic hulls").

Two kinds of part, both in the authored frame (x to starboard, y up, z aft; metres):

* **body parts are fields** (``core/sdf.py``): :func:`lobe`, :func:`pod`, :func:`limb_root`. A generator melts them
  together with :func:`body` and hands the result to ``core/organic.sectioned``, which meshes it once and cuts it into the
  damage sections. Fields join without a crease, which is what makes a hull organic;
* **limbs are modules** (``parts/capital.py``), their skin written directly along a path (``core/sweep.py``):
  :func:`limb` and the paths :func:`claw_path`, :func:`leg_path` and :func:`tendril_path`; :func:`ribs` gives any limb
  or lobe its ribbing. A limb is exact however long and thin it is; root it in the body by melting a :func:`limb_root`
  of the same path into the body's field.

Petals (the Vorlons' opening shells) are in ``parts/organic_petal.py``.
"""

from __future__ import annotations

import math
from collections.abc import Sequence

import numpy as np

from ..core import collision as col
from ..core import sdf
from ..core.geometry import Material
from ..core.sweep import Path, section_ring, spline, tube
from . import capital as cp

Vec3 = Sequence[float]


# --- body parts (fields) -------------------------------------------------------------------------------------------------
def lobe(length_m: float, width_m: float, height_m: float, taper: float = 0.0, centre: Vec3 = (0.0, 0.0, 0.0)) -> sdf.Field:
    """A rounded lobe along z, ``width_m`` by ``height_m`` at its fullest. With ``taper`` its aft end narrows to that share
    less of its size (0: an ellipsoid; 0.6: a teardrop with its bulb forward)."""
    if not 0.0 <= taper < 1.0:
        raise ValueError("a lobe's taper is from 0 up to (not at) 1")
    c = np.asarray(centre, dtype=float)
    if taper == 0.0:
        return sdf.ellipsoid((0.5 * width_m, 0.5 * height_m, 0.5 * length_m), c)
    # A teardrop: a path down the lobe with the section shrinking aft, its ends rounded by the sweep.
    half = 0.5 * length_m
    path = spline(np.array([[0.0, 0.0, -half], [0.0, 0.0, half]]) + c, 17)
    t = path.t
    bulge = np.sqrt(np.clip(1.0 - (2.0 * t - 1.0) ** 2, 0.0, 1.0))
    scale = bulge * (1.0 - taper * t)
    return sdf.swept(path, 0.5 * width_m * scale, 0.5 * height_m * scale)


def pod(radius_m: float, length_m: float, stalk_m: float, stalk_radius_m: float, at: Vec3 = (0.0, 0.0, 0.0), out: Vec3 = (1.0, 0.0, 0.0)) -> sdf.Field:
    """A pod on a stalk: an egg ``length_m`` long along z, ``radius_m`` across, held ``stalk_m`` off the point ``at`` along
    ``out``, the stalk melting into both ends."""
    a = np.asarray(at, dtype=float)
    direction = np.asarray(out, dtype=float) / float(np.linalg.norm(out))
    centre = a + direction * (stalk_m + radius_m)
    egg = sdf.ellipsoid((radius_m, radius_m, 0.5 * length_m), centre)
    stalk = sdf.round_cone(a, centre, 1.4 * stalk_radius_m, stalk_radius_m)
    return sdf.smooth_union(egg, stalk, blend=stalk_radius_m)


def limb_root(path: Path, half_width: np.ndarray, half_height: np.ndarray | None = None, share: float = 0.25, swell: float = 1.15) -> sdf.Field:
    """The first ``share`` of a limb as a field, a little fatter than the limb: melted into the body, it gives the limb a
    shoulder to grow out of, so the limb's own skin starts buried."""
    n = max(int(round(share * (len(path.points) - 1))) + 1, 3)
    stub = Path(path.points[:n], path.tangent[:n], path.side[:n], path.up[:n])
    w = swell * np.asarray(half_width, dtype=float)[:n]
    h = w if half_height is None else swell * np.asarray(half_height, dtype=float)[:n]
    return sdf.swept(stub, w, h)


def body(parts: Sequence[sdf.Field], blend_m: float, relief_m: float = 0.0, relief_scale_m: float = 1.0, seed: int = 0) -> sdf.Field:
    """The parts melted into one body with fillets about ``blend_m`` wide, then seeded bumps ``relief_m`` high and
    ``relief_scale_m`` across pushed into the skin (none at 0). Hand the same ``parts`` to ``core/organic.sectioned``: the
    body's collision is fitted part by part."""
    whole = sdf.smooth_union(*parts, blend=blend_m)
    return whole if relief_m <= 0.0 else sdf.displaced(whole, relief_m, relief_scale_m, seed)


# --- limbs (modules) -----------------------------------------------------------------------------------------------------
def taper(path: Path, root_m: float, tip_m: float = 0.0, power: float = 1.0) -> np.ndarray:
    """A limb's half size at each path point: ``root_m`` at its start down to ``tip_m`` at its end; a ``power`` under one
    keeps it thick for longer before the tip."""
    return tip_m + (root_m - tip_m) * (1.0 - path.t) ** power


def ribs(path: Path, half_size: np.ndarray, pitch_m: float, height: float, sharpness: float = 2.0) -> np.ndarray:
    """``half_size`` with ribs every ``pitch_m`` along the path, each ``height`` of the limb's size proud. The path needs
    several points a rib (``spline``'s ``samples``), or the ribs alias."""
    wave = (0.5 + 0.5 * np.cos(2.0 * math.pi * path.arc / pitch_m)) ** sharpness
    return np.asarray(half_size, dtype=float) * (1.0 + height * wave)


def claw_path(root: Vec3, length_m: float, out: Vec3, curl_to: Vec3, curl_deg: float, samples: int = 40) -> Path:
    """A claw: from ``root`` it sets off along ``out`` and curls evenly towards ``curl_to`` by ``curl_deg`` over its length."""
    o = np.asarray(out, dtype=float) / float(np.linalg.norm(out))
    c = np.asarray(curl_to, dtype=float)
    c = c - (c @ o) * o
    if float(np.linalg.norm(c)) < 1e-9:
        raise ValueError("a claw must curl to one side of where it sets off")
    c /= float(np.linalg.norm(c))
    turn = np.radians(curl_deg) * np.linspace(0.0, 1.0, 9)
    radius = length_m / max(np.radians(curl_deg), 1e-6)
    points = np.asarray(root, dtype=float) + radius * (np.sin(turn)[:, None] * o + (1.0 - np.cos(turn))[:, None] * c)
    return spline(points, samples, up=np.cross(o, c))


def leg_path(root: Vec3, knee: Vec3, tip: Vec3, samples: int = 40, up: Vec3 = (0.0, 1.0, 0.0)) -> Path:
    """A leg: out from ``root`` to its ``knee`` and on to its ``tip``, the bend rounded."""
    r, k, t = (np.asarray(v, dtype=float) for v in (root, knee, tip))
    return spline(np.array([r, 0.5 * (r + k) + 0.08 * (k - t), k, 0.5 * (k + t) + 0.08 * (k - r), t]), samples, up)


def tendril_path(root: Vec3, tip: Vec3, wave_m: float, waves: float, wave_along: Vec3 = (0.0, 1.0, 0.0), samples: int = 48) -> Path:
    """A tendril from ``root`` to ``tip`` that sways ``wave_m`` either side along ``wave_along``, ``waves`` times, the sway
    growing from nothing at the root."""
    r, t = np.asarray(root, dtype=float), np.asarray(tip, dtype=float)
    s = np.linspace(0.0, 1.0, max(int(8 * waves) + 2, 6))
    sway = wave_m * s * np.sin(2.0 * math.pi * waves * s)
    up = np.asarray(wave_along, dtype=float)
    return spline(r + s[:, None] * (t - r) + sway[:, None] * up / float(np.linalg.norm(up)), samples, up=np.cross(t - r, up))


def limb_shapes(name: str, path: Path, half_width: np.ndarray, half_height: np.ndarray, pieces: int) -> list[col.Shape]:
    """A limb's collision: ``pieces`` convex hulls along it, each round its run of the limb's sections (so a curved limb is
    followed, not bridged)."""
    n = len(path.points)
    outline = section_ring(8) / math.cos(math.pi / 8.0)  # an octagon round the section, not inside it
    floor = 0.02 * float(max(half_width.max(), half_height.max()))  # a point's end still has a little volume to hull
    w, h = np.maximum(half_width, floor), np.maximum(half_height, floor)
    rings = (path.points[:, None, :] + w[:, None, None] * outline[None, :, 0:1] * path.side[:, None, :]
             + h[:, None, None] * outline[None, :, 1:2] * path.up[:, None, :])
    bounds = np.linspace(0, n - 1, min(pieces, n - 1) + 1).round().astype(int)
    shapes = []
    # The end pieces reach past the path's ends by the dome the skin is closed with (``sweep.tube``).
    ends = {0: path.points[0] - min(w[0], h[0]) * path.tangent[0], len(bounds) - 2: path.points[-1] + min(w[-1], h[-1]) * path.tangent[-1]}
    for k, (a, b) in enumerate(zip(bounds[:-1], bounds[1:], strict=True)):
        points = rings[a:b + 1].reshape(-1, 3)
        if k in ends:
            points = np.concatenate([points, ends[k][None]])
        shapes.append(col.hull(f"{name}_{k:02d}", points))  # the hull keeps the 32 corners that matter most
    return shapes


def limb(name: str, path: Path, half_width: np.ndarray | float, half_height: np.ndarray | float | None, material: Material, sides: int = 10,
         pieces: int = 4, exponent: float = 2.0, hardpoints: Sequence[cp.Hardpoint] = (), skin: str = cp.SKIN_NONE,
         chart_m: float | None = None) -> cp.Module:
    """A limb as a module: its skin swept along ``path`` (``core/sweep.tube``: an elliptical section ``half_width`` by
    ``half_height`` at each point, a point where they reach nothing), its collision ``pieces`` hulls along it."""
    n = len(path.points)
    w = np.broadcast_to(np.asarray(half_width, dtype=float), (n,)).copy()
    h = w.copy() if half_height is None else np.broadcast_to(np.asarray(half_height, dtype=float), (n,)).copy()
    mesh = tube(path, w, h, material, sides, exponent, chart_m=chart_m)
    return cp.module(name, mesh, limb_shapes(name, path, w, h, pieces), hardpoints, skin=skin)


__all__ = ["body", "claw_path", "leg_path", "limb", "limb_root", "limb_shapes", "lobe", "pod", "ribs", "taper", "tendril_path"]
