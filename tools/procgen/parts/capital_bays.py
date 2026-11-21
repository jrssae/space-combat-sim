"""Launch bays and launch tubes (M10-T05, D12.1): where a capital's fighters and shuttles leave.

Both are built on their own frame with the way out along -z and +y up, the mouth's centre at the origin and the hall or the
tube behind it (+z); place them with ``Module.transformed``. The hardpoint (``hardpoints.bays[]``) is the launch: its
``position`` is where a craft starts (in the hall, at the tube's breech), ``forward`` its nose and the way it leaves, ``up``
its back; ``params`` carry ``exit`` (the mouth's centre, moved with the module), ``mouth_m`` and ``depth_m`` (a bay) or
``radius_m`` and ``length_m`` (a tube).

A bay is a housing of its own, open at the mouth: it stands proud of the hull, hangs under it or fills a hull section's
open end (``hull_section(caps=...)``). The hull's own faces are never cut.

A **lit** bay (``launch_bay(lit=True)``; every Earth Alliance hull's, as Babylon 5's docking bay) keeps the hull's paint on its
frame and glows red: a band round the mouth, rings of light strips down a faintly red hall, guide strips on the deck, a lamp at each
corner of the mouth and a ``bay`` light hardpoint in the hall's mouth for the game's light rig. Its style carries
:data:`BAY_LIGHT_ROLES` (``styles/ea_capital.bay_light_materials``).
"""

from __future__ import annotations

import math

import numpy as np

from ..core import collision as col
from ..core.geometry import Mesh, box, lathe
from ..styles import Style
from .capital import BAY, LIGHT, SKIN_FITTING, TUBE, Hardpoint, Module, module
from .raider_carrier import flat
from .solids import box_solid, difference

EXIT = "exit"  # the mouth's centre: one of ``capital.POINT_PARAMS``, so it moves with the module
BAY_LIGHT_ROLES = ("bay_light", "bay_light_deep", "bay_lamp", "bay_hall")  # the mouth's glow, the hall's strips, the lamps, its walls
BAY_LIGHT_ROLE = "bay"  # the light hardpoint's role
BAND_M, STRIP_M = 0.6, 0.5  # the glowing band round the mouth and a strip's width
RINGS = (0.06, 0.45, 0.85)  # where the hall's rings of strips stand, as fractions of its depth: the first is the mouth's own


def _shell(w: float, h: float, z0: float, z1: float, material, inward: bool, back: bool) -> list[Mesh]:
    """The four walls of a box from ``z0`` to ``z1`` (and its back at ``z1``), seen from outside or from inside."""
    x, y = 0.5 * w, 0.5 * h
    ring = [(x, -y), (x, y), (-x, y), (-x, -y)]
    centre = np.array([0.0, 0.0, 0.5 * (z0 + z1)])
    away = centre if not inward else None
    out = []
    for a, b in zip(ring, ring[1:] + ring[:1], strict=True):
        quad = [(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)]
        mid = np.mean(quad, axis=0)
        out.append(flat(quad, material, away if away is not None else 2.0 * mid - centre))
    if back:
        quad = [(px, py, z1) for px, py in ring]
        out.append(flat(quad, material, centre if not inward else np.array([0.0, 0.0, 2.0 * z1 - centre[2]])))
    return out


def launch_bay(name: str, mouth_m: tuple[float, float], depth_m: float, style: Style, wall_m: float = 1.5, lit: bool = False) -> Module:
    """A launch bay: a housing ``wall_m`` thick round a hall ``mouth_m`` wide and high and ``depth_m`` deep, open at -z,
    the hall dark with a lit deck (or, ``lit``, in the hull's paint and red light). A craft starts at the hall's middle, a
    third of its height above the deck."""
    w, h = mouth_m
    if w <= 0.0 or h <= 0.0 or depth_m <= 0.0 or wall_m <= 0.0:
        raise ValueError(f"launch bay {name!r} needs a mouth, a depth and a wall")
    ow, oh = w + 2.0 * wall_m, h + 2.0 * wall_m
    outer = _shell(ow, oh, 0.0, depth_m + wall_m, style.material("hull"), inward=False, back=True)
    hall = _shell(w, h, 0.0, depth_m, style.material("bay_hall" if lit else "interior"), inward=True, back=True)
    # The deck, a hair over the hall's floor (lit warm, or dark under a lit bay's red), and the frame round the mouth.
    deck = flat([(-0.4 * w, -0.5 * h + 0.05, 0.05 * depth_m), (0.4 * w, -0.5 * h + 0.05, 0.05 * depth_m),
                 (0.4 * w, -0.5 * h + 0.05, 0.95 * depth_m), (-0.4 * w, -0.5 * h + 0.05, 0.95 * depth_m)],
                style.material("interior" if lit else "hazard"), (0.0, -h, 0.5 * depth_m))
    x, y, X, Y = 0.5 * w, 0.5 * h, 0.5 * ow, 0.5 * oh
    frame_mat = style.material("hull" if lit else "hazard_dark")
    frame = [flat([(a[0], a[1], 0.0), (b[0], b[1], 0.0), (c[0], c[1], 0.0), (d[0], d[1], 0.0)], frame_mat, (0.0, 0.0, 1.0))
             for a, b, c, d in (((-X, -Y), (X, -Y), (x, -y), (-x, -y)), ((X, -Y), (X, Y), (x, y), (x, -y)),
                                ((X, Y), (-X, Y), (-x, y), (x, y)), ((-X, Y), (-X, -Y), (-x, -y), (-x, y)))]
    mid_z = 0.5 * (depth_m + wall_m)
    # Four walls and a back, so the hall stays open to a craft's collision.
    shapes = [col.box(f"{name}_top", (0.0, 0.5 * (h + wall_m), mid_z), (ow, wall_m, depth_m + wall_m)),
              col.box(f"{name}_bottom", (0.0, -0.5 * (h + wall_m), mid_z), (ow, wall_m, depth_m + wall_m)),
              col.box(f"{name}_right", (0.5 * (w + wall_m), 0.0, mid_z), (wall_m, h, depth_m + wall_m)),
              col.box(f"{name}_left", (-0.5 * (w + wall_m), 0.0, mid_z), (wall_m, h, depth_m + wall_m)),
              col.box(f"{name}_back", (0.0, 0.0, depth_m + 0.5 * wall_m), (w, h, wall_m))]
    start = (0.0, -h / 6.0, 0.5 * depth_m)
    points = [Hardpoint(name, BAY, start, (0.0, 0.0, -1.0), (0.0, 1.0, 0.0),
                        {EXIT: (0.0, -h / 6.0, 0.0), "mouth_m": [round(w, 3), round(h, 3)], "depth_m": round(depth_m, 3)})]
    glow: list[Mesh] = []
    if lit:
        glow = _bay_glow(w, h, depth_m, wall_m, style)
        red = style.material("bay_light").emissive
        points.append(Hardpoint(f"{name}_light", LIGHT, (0.0, 0.0, 0.2 * depth_m), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0),
                                {"role": BAY_LIGHT_ROLE, "colour": [round(float(c), 4) for c in red], "range_m": round(2.0 * (w + h), 2)}))
    solid = difference(box_solid((ow, oh, depth_m + wall_m), (0.0, 0.0, mid_z)), box_solid((w, h, depth_m + 1.0), (0.0, 0.0, 0.5 * depth_m - 0.5)))
    return module(name, Mesh.concatenate([*outer, *hall, deck, *frame, *glow]), shapes, points, solid=solid, skin=SKIN_FITTING)


def _bay_glow(w: float, h: float, depth_m: float, wall_m: float, style: Style) -> list[Mesh]:
    """A lit bay's red light, so the mouth reads as an EA hangar from far off and the hall glows red up close."""
    x, y = 0.5 * w, 0.5 * h
    lift = 0.04  # a hair off the surface it lies on
    out: list[Mesh] = []
    # The band round the mouth, on the frame's face just outside the opening.
    a, b = (x, y), (x + BAND_M, y + BAND_M)
    band = style.material("bay_light")
    for p, q, r, s in (((-b[0], -b[1]), (b[0], -b[1]), (a[0], -a[1]), (-a[0], -a[1])), ((b[0], -b[1]), (b[0], b[1]), (a[0], a[1]), (a[0], -a[1])),
                       ((b[0], b[1]), (-b[0], b[1]), (-a[0], a[1]), (a[0], a[1])), ((-b[0], b[1]), (-b[0], -b[1]), (-a[0], -a[1]), (-a[0], a[1]))):
        out.append(flat([(*p, -lift), (*q, -lift), (*r, -lift), (*s, -lift)], band, (0.0, 0.0, 1.0)))
    # Rings of strips round the hall's walls and roof, the first at the mouth, the deeper ones dimmer.
    for k, f in enumerate(RINGS):
        mat = style.material("bay_light" if k == 0 else "bay_light_deep")
        z0 = f * depth_m
        z1 = z0 + STRIP_M
        xi, yi = x - lift, y - lift
        for sx in (-1.0, 1.0):  # each side wall, facing into the hall
            out.append(flat([(sx * xi, -yi, z0), (sx * xi, yi, z0), (sx * xi, yi, z1), (sx * xi, -yi, z1)], mat, (2.0 * sx * x, 0.0, z0)))
        out.append(flat([(-xi, yi, z0), (xi, yi, z0), (xi, yi, z1), (-xi, yi, z1)], mat, (0.0, 2.0 * y, z0)))  # the roof
    # Two guide strips down the deck, and a lamp at each corner of the mouth.
    deep = style.material("bay_light_deep")
    for sx in (-1.0, 1.0):
        u0, u1 = sx * 0.3 * w, sx * 0.3 * w + sx * STRIP_M
        out.append(flat([(u0, -y + 0.08, 0.05 * depth_m), (u1, -y + 0.08, 0.05 * depth_m), (u1, -y + 0.08, 0.95 * depth_m),
                         (u0, -y + 0.08, 0.95 * depth_m)], deep, (0.0, -h, 0.5 * depth_m)))
    lamp = min(1.2, 0.8 * wall_m)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            out.append(box((lamp, lamp, 0.5 * lamp), style.material("bay_lamp"), (sx * (x + 0.5 * wall_m), sy * (y + 0.5 * wall_m), -0.25 * lamp)))
    return out


def launch_tube(name: str, radius_m: float, length_m: float, style: Style, sides: int = 12) -> Module:
    """A launch tube: a round barrel open at -z, its bore dark; a craft starts at the breech and leaves through the mouth."""
    if radius_m <= 0.0 or length_m <= 2.0 * radius_m:
        raise ValueError(f"launch tube {name!r} needs a radius and a length over its width")
    r, wall = radius_m, 0.18 * radius_m
    bore, hull = style.material("bore"), style.material("hull_dark")
    # From the breech's outside forward to the mouth's lip, then back down the bore.
    profile = [(0.0, 0.0), (0.0, r + wall), (length_m, r + wall), (length_m, r), (0.08 * length_m, r), (0.08 * length_m, 0.0)]
    mesh = lathe(profile, sides, [hull, hull, style.material("hazard_dark"), bore, bore], creases={1, 2, 3, 4})
    mesh = mesh.transformed(np.diag([1.0, -1.0, -1.0]), (0.0, 0.0, length_m))  # the mouth at the origin, facing -z
    grow = 1.0 / math.cos(math.pi / sides)
    sectors = col.ring_sectors(name, (0.0, 0.0, 0.0), (0.0, 0.0, 1.0), r, (r + wall) * grow, 0.0, length_m, 8)
    shapes = [*sectors, col.box(f"{name}_breech", (0.0, 0.0, 0.96 * length_m), (2.0 * r, 2.0 * r, 0.08 * length_m))]
    point = Hardpoint(name, TUBE, (0.0, 0.0, 0.85 * length_m), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0),
                      {EXIT: (0.0, 0.0, 0.0), "radius_m": round(r, 3), "length_m": round(length_m, 3)})
    return module(name, mesh, shapes, [point], skin=SKIN_FITTING)


__all__ = ["BAY_LIGHT_ROLE", "BAY_LIGHT_ROLES", "EXIT", "launch_bay", "launch_tube"]
