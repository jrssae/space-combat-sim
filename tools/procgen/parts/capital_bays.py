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
:data:`BAY_LIGHT_ROLES` (``styles/ea_capital.bay_light_materials``). ``rim=False`` keeps the red inside the hall (the Hyperion's).
``metal=True`` lines the hall as Babylon 5's docking bay instead (the Hyperion's, M10-T22): grey metal (``bay_metal``,
``styles/ea_capital.bay_metal_materials``) lit red by the bay's light, small lamps along the roof and no glowing strips.

A bay with a **door** (``door=True``, M10-T22) has a roll-up shutter: a housing over the mouth and guide rails down its sides are
built here; the shutter itself is a ``door`` hardpoint (``hardpoints.doors[]``) the game draws as slats, shut until a craft
launches or docks, when it winds up into the housing.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from ..core import collision as col
from ..core.geometry import Mesh, box, lathe
from ..styles import Style
from .capital import BAY, DOOR, LIGHT, SKIN_FITTING, TUBE, Hardpoint, Module, module
from .raider_carrier import flat
from .solids import box_solid, difference

EXIT = "exit"  # the mouth's centre: one of ``capital.POINT_PARAMS``, so it moves with the module
BAY_LIGHT_ROLES = ("bay_light", "bay_light_deep", "bay_lamp", "bay_hall")  # the mouth's glow, the hall's strips, the lamps, its walls
BAY_LIGHT_ROLE = "bay"  # the light hardpoint's role
BAND_M, STRIP_M = 0.6, 0.5  # the glowing band round the mouth and a strip's width
LAMP_DEPTHS = (0.2, 0.5, 0.8)  # a metal-lined hall's lamps, as fractions of its depth
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


def launch_bay(name: str, mouth_m: tuple[float, float], depth_m: float, style: Style, wall_m: float = 1.5, lit: bool = False,
               rim: bool = True, door: bool = False, metal: bool = False) -> Module:
    """A launch bay: a housing ``wall_m`` thick round a hall ``mouth_m`` wide and high and ``depth_m`` deep, open at -z,
    the hall dark with a lit deck (or, ``lit``, in the hull's paint and red light; ``rim=False`` leaves the mouth's outer band and corner
    lamps off, the red staying inside; ``door`` adds a roll-up door: its housing over the mouth and a door hardpoint the game draws as
    a shutter; ``metal``, with ``lit``, lines the hall in grey metal lit red by its light alone, as Babylon 5's docking bay, with
    small lamps and no glowing strips). A craft starts at the hall's middle, a third of its height above the deck."""
    w, h = mouth_m
    if w <= 0.0 or h <= 0.0 or depth_m <= 0.0 or wall_m <= 0.0:
        raise ValueError(f"launch bay {name!r} needs a mouth, a depth and a wall")
    ow, oh = w + 2.0 * wall_m, h + 2.0 * wall_m
    outer = _shell(ow, oh, 0.0, depth_m + wall_m, style.material("hull"), inward=False, back=True)
    metal = metal and lit
    hall_role = "bay_metal" if metal else "bay_hall" if lit else "interior"
    hall = _shell(w, h, 0.0, depth_m, style.material(hall_role), inward=True, back=True)
    # The deck, a hair over the hall's floor (lit warm, or dark under a lit bay's red), and the frame round the mouth.
    deck = flat([(-0.4 * w, -0.5 * h + 0.05, 0.05 * depth_m), (0.4 * w, -0.5 * h + 0.05, 0.05 * depth_m),
                 (0.4 * w, -0.5 * h + 0.05, 0.95 * depth_m), (-0.4 * w, -0.5 * h + 0.05, 0.95 * depth_m)],
                style.material("hull_dark" if metal else "interior" if lit else "hazard"), (0.0, -h, 0.5 * depth_m))
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
        glow = _bay_lamps(w, h, depth_m, style) if metal else _bay_glow(w, h, depth_m, wall_m, style, rim)
        red = style.material("bay_light").emissive
        points.append(Hardpoint(f"{name}_light", LIGHT, (0.0, 0.0, (0.5 if metal else 0.2) * depth_m), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0),
                                {"role": BAY_LIGHT_ROLE, "colour": [round(float(c), 4) for c in red], "range_m": round(2.0 * (w + h), 2)}))
    shutter: list[Mesh] = []
    if door:
        points.append(door_point(name, w, h))
        shutter = _door_housing(w, h, wall_m, style)
    solid = difference(box_solid((ow, oh, depth_m + wall_m), (0.0, 0.0, mid_z)), box_solid((w, h, depth_m + 1.0), (0.0, 0.0, 0.5 * depth_m - 0.5)))
    return module(name, Mesh.concatenate([*outer, *hall, deck, *frame, *glow, *shutter]), shapes, points, solid=solid, skin=SKIN_FITTING)


DOOR_GAP_M = 0.3  # the shutter's plane, this far out from the frame's face
DOOR_THICK_M = 0.2
RAIL_M = 0.4  # the guide rails' width each side of the mouth
SLAT_M = 0.9  # about one slat a metre of mouth


def door_point(name: str, w: float, h: float) -> Hardpoint:
    """A bay's roll-up door: a shutter of slats over the mouth, its top inside the roll housing; the game draws the slats and
    winds them up into the housing to open it. ``position`` is the shut shutter's centre, ``up`` the way it rolls."""
    return Hardpoint(f"{name}_door", DOOR, (0.0, -0.05, -DOOR_GAP_M), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0),
                     {"size_m": [round(w + RAIL_M, 3), round(h + 0.1, 3), DOOR_THICK_M], "slats": max(4, round(h / SLAT_M))})


def _door_housing(w: float, h: float, wall_m: float, style: Style) -> list[Mesh]:
    """The roll housing over the mouth, which the shutter winds up into, the guide rails it runs down and the sill it shuts on:
    together they close the gap between the shutter and the frame, so no light from the hall shows round a shut door."""
    x, y = 0.5 * w, 0.5 * h
    depth = DOOR_GAP_M + 0.6
    tall = 0.6 + 0.16 * h
    housing = box((w + 2.0 * wall_m + 0.4, tall, depth), style.material("hull_panel"), (0.0, y - DOOR_GAP_M + 0.5 * tall, -0.5 * depth))
    rails = [box((RAIL_M, h, DOOR_GAP_M + 0.25), style.material("hull_dark"), (sx * (x + 0.5 * RAIL_M), 0.0, -0.5 * (DOOR_GAP_M + 0.25)))
             for sx in (-1.0, 1.0)]
    sill = box((w + 2.0 * RAIL_M, 0.4, DOOR_GAP_M + 0.25), style.material("hull_dark"), (0.0, -y - 0.3, -0.5 * (DOOR_GAP_M + 0.25)))
    return [housing, *rails, sill]


def _bay_glow(w: float, h: float, depth_m: float, wall_m: float, style: Style, rim: bool = True) -> list[Mesh]:
    """A lit bay's red light, so the mouth reads as an EA hangar from far off and the hall glows red up close."""
    x, y = 0.5 * w, 0.5 * h
    lift = 0.04  # a hair off the surface it lies on
    out: list[Mesh] = []
    # The band round the mouth, on the frame's face just outside the opening.
    a, b = (x, y), (x + BAND_M, y + BAND_M)
    band = style.material("bay_light")
    quads = (((-b[0], -b[1]), (b[0], -b[1]), (a[0], -a[1]), (-a[0], -a[1])), ((b[0], -b[1]), (b[0], b[1]), (a[0], a[1]), (a[0], -a[1])),
             ((b[0], b[1]), (-b[0], b[1]), (-a[0], a[1]), (a[0], a[1])), ((-b[0], b[1]), (-b[0], -b[1]), (-a[0], -a[1]), (-a[0], a[1])))
    for p, q, r, s in quads if rim else ():
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
    for sx in (-1.0, 1.0) if rim else ():
        for sy in (-1.0, 1.0):
            out.append(box((lamp, lamp, 0.5 * lamp), style.material("bay_lamp"), (sx * (x + 0.5 * wall_m), sy * (y + 0.5 * wall_m), -0.25 * lamp)))
    return out


def _bay_lamps(w: float, h: float, depth_m: float, style: Style) -> list[Mesh]:
    """A metal-lined hall's small red lamps along the roof's edges: the only thing in it that glows."""
    lamp, y = min(0.5, 0.03 * w), 0.5 * h - 0.04
    out: list[Mesh] = []
    for f in LAMP_DEPTHS:
        z = f * depth_m
        for sx in (-1.0, 1.0):
            u0, u1 = sx * (0.5 * w - 0.3), sx * (0.5 * w - 0.3 - lamp)
            out.append(flat([(u0, y, z), (u1, y, z), (u1, y, z + lamp), (u0, y, z + lamp)], style.material("bay_lamp"), (0.0, 2.0 * h, z)))
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


# --- inside or outside (M10-T72, Q68) ------------------------------------------------------------------------------------
# No light casts shadows, so the sun would light a bay's hall as it does the hull round it. The faces inside a hall are told apart
# here, from the bays' hardpoints alone, and drawn out of the sun's light (the game's interior layer), as the station's halls are.
INSIDE_EPS_M = 0.05


@dataclass(frozen=True)
class Hall:
    """A bay's hall as a box: its centre, its axes (across, up, out of the mouth, as rows) and its half sizes along them."""

    name: str
    centre: np.ndarray
    axes: np.ndarray
    half: np.ndarray


def hall_of(point: Hardpoint) -> Hall:
    """The hall behind a bay's hardpoint (``launch_bay``'s): the mouth's centre is ``exit`` raised by a sixth of its height."""
    w, h = (float(v) for v in point.params["mouth_m"])
    depth = float(point.params["depth_m"])
    out, up = np.asarray(point.forward, dtype=float), np.asarray(point.up, dtype=float)
    centre = np.asarray(point.params[EXIT], dtype=float) + up * (h / 6.0) - out * (0.5 * depth)
    return Hall(point.name, centre, np.array([np.cross(up, out), up, out]), np.array([0.5 * w, 0.5 * h, 0.5 * depth]))


def halls_of(modules: Sequence[Module]) -> list[tuple[str, Hall]]:
    """Every bay's hall, with the section its module stands in."""
    return [(m.section, hall_of(p)) for m in modules for p in m.hardpoints if p.kind == BAY and "mouth_m" in p.params]


def inside_halls(halls: Sequence[Hall], points: np.ndarray) -> np.ndarray:
    """Which points (face centroids) lie inside any of the halls: on or within its walls, deck, roof and back, short of the mouth's
    plane (the frame round the mouth faces the sky)."""
    pts = np.asarray(points, dtype=float).reshape(-1, 3)
    inside = np.zeros(len(pts), dtype=bool)
    e = INSIDE_EPS_M
    for hall in halls:
        local = (pts - hall.centre) @ hall.axes.T
        inside |= np.all(np.abs(local) < hall.half + e, axis=1) & (local[:, 2] < hall.half[2] - e)
    return inside


__all__ = ["BAY_LIGHT_ROLE", "BAY_LIGHT_ROLES", "EXIT", "INSIDE_EPS_M", "Hall", "hall_of", "halls_of", "inside_halls", "launch_bay", "launch_tube"]
