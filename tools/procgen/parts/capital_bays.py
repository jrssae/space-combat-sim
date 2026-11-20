"""Launch bays and launch tubes (M10-T05, D12.1): where a capital's fighters and shuttles leave.

Both are built on their own frame with the way out along -z and +y up, the mouth's centre at the origin and the hall or the
tube behind it (+z); place them with ``Module.transformed``. The hardpoint (``hardpoints.bays[]``) is the launch: its
``position`` is where a craft starts (in the hall, at the tube's breech), ``forward`` its nose and the way it leaves, ``up``
its back; ``params`` carry ``exit`` (the mouth's centre, moved with the module), ``mouth_m`` and ``depth_m`` (a bay) or
``radius_m`` and ``length_m`` (a tube).

A bay is a housing of its own, open at the mouth: it stands proud of the hull, hangs under it or fills a hull section's
open end (``hull_section(caps=...)``). The hull's own faces are never cut.
"""

from __future__ import annotations

import math

import numpy as np

from ..core import collision as col
from ..core.geometry import Mesh, lathe
from ..styles import Style
from .capital import BAY, SKIN_FITTING, TUBE, Hardpoint, Module, module
from .raider_carrier import flat
from .solids import box_solid, difference

EXIT = "exit"  # the mouth's centre: one of ``capital.POINT_PARAMS``, so it moves with the module


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


def launch_bay(name: str, mouth_m: tuple[float, float], depth_m: float, style: Style, wall_m: float = 1.5) -> Module:
    """A launch bay: a housing ``wall_m`` thick round a hall ``mouth_m`` wide and high and ``depth_m`` deep, open at -z,
    the hall dark with a lit deck. A craft starts at the hall's middle, a third of its height above the deck."""
    w, h = mouth_m
    if w <= 0.0 or h <= 0.0 or depth_m <= 0.0 or wall_m <= 0.0:
        raise ValueError(f"launch bay {name!r} needs a mouth, a depth and a wall")
    ow, oh = w + 2.0 * wall_m, h + 2.0 * wall_m
    outer = _shell(ow, oh, 0.0, depth_m + wall_m, style.material("hull"), inward=False, back=True)
    hall = _shell(w, h, 0.0, depth_m, style.material("interior"), inward=True, back=True)
    # The lit deck, a hair over the hall's floor, and the frame round the mouth.
    deck = flat([(-0.4 * w, -0.5 * h + 0.05, 0.05 * depth_m), (0.4 * w, -0.5 * h + 0.05, 0.05 * depth_m),
                 (0.4 * w, -0.5 * h + 0.05, 0.95 * depth_m), (-0.4 * w, -0.5 * h + 0.05, 0.95 * depth_m)], style.material("hazard"),
                (0.0, -h, 0.5 * depth_m))
    x, y, X, Y = 0.5 * w, 0.5 * h, 0.5 * ow, 0.5 * oh
    frame_mat = style.material("hazard_dark")
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
    point = Hardpoint(name, BAY, start, (0.0, 0.0, -1.0), (0.0, 1.0, 0.0),
                      {EXIT: (0.0, -h / 6.0, 0.0), "mouth_m": [round(w, 3), round(h, 3)], "depth_m": round(depth_m, 3)})
    solid = difference(box_solid((ow, oh, depth_m + wall_m), (0.0, 0.0, mid_z)), box_solid((w, h, depth_m + 1.0), (0.0, 0.0, 0.5 * depth_m - 0.5)))
    return module(name, Mesh.concatenate([*outer, *hall, deck, *frame]), shapes, [point], solid=solid, skin=SKIN_FITTING)


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


__all__ = ["EXIT", "launch_bay", "launch_tube"]
