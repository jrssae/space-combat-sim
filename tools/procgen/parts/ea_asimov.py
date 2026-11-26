"""The Asimov-class liner's structure (M10-T53, Q84): the parts measured off the reference model, on the capital library.

Authored frame: x to starboard, y up from the sphere's axis, z aft from the saucer's nose; 600 m long (docs/assets-capital.md,
"M10 lengths (T01)"). Numbers are the reference's own (``references/EA Asimov liner 600m.stl`` at that length, mapping ``-x +z
+y``, its sections cut with ``tools/refview/sections.py``); docs/design-references.md describes the ship.

Bow to stern:

* **command spine** (0 to 183 m): the saucer bridge at the nose (a lens 90 m across), the keel under it, a broad skirt and a
  column behind it running back into the sphere's face, and a hexagonal pod each side;
* **forward face** (166 to 202 m outside, its structure to 236 m): the sphere cut flat at 183 m, a collar with a ring of teeth round a deep terraced bowl (the
  show's cavity, Q95, not the reference's shallow disc) the spine runs into, and in the bowl's floor the hexagonal mouth below the
  spine (open, 45 x 27 m, a frame 2 m deep);
* **shuttle bay** (216 to 286 m, Q84, Q96): the hall behind the mouth, straight back inside the fixed core the band turns
  round: 70 m wide and deep, 23.2 m high, a berth for a crew shuttle to starboard and one for a Kestrel with folded wings to
  port, each on its own lane through the mouth (``shuttle_bay``);
* **habitat band** (236 to 428 m): the sphere's middle, which turns (its own piece), in two halves split at the equator so the
  mining transport (T56) can part them; the skin from the ring to its forward groove (202 to 236 m) turns with it, so a
  ship's bars run unbroken from the ring. A habitat ring: its collision is a ring round the fixed core as far back as the
  bay reaches (to 298 m), solid aft of it;
* **aft cap** (428 to 505 m): the rest of the sphere with the dark band of window rows at its forward edge;
* **engine frame** (465 to 600 m): a cross of radiator bars and six nacelles in two rows of three; the outer four are the
  engines, the middle pair the reactors.

Every function returns modules already named for their damage section and side; ``assets/ea_asimov.py`` adds the lights and the
section table.
"""

from __future__ import annotations

import dataclasses
import math
from collections.abc import Sequence

import numpy as np

from ..core import collision as col
from ..core.geometry import Material, Mesh, lathe, rotation_z
from ..styles import Style
from . import capital as cp
from . import capital_bays as bays
from . import capital_solids as cs
from .capital_hull import HullRoles
from .raider_carrier import flat
from .solids import Solid, lathe_solid

LENGTH_M = 600.0
SPHERE_Z, SPHERE_R = 331.5, 173.7  # the sphere's centre on the axis and its radius
FACE_Z = 183.0  # where the sphere is cut flat for its forward face
COLLAR = (174.0, 60.0, 75.0)  # the ring round the bowl: its face, inner and outer radius (its outside slopes back to the face's edge)
# The bowl inside the collar (Q95: the show's deep cavity): its terraces, each (z it begins at, radius there, radius at its foot),
# a ledge between one and the next, the last standing on the floor.
BOWL = ((174.0, 60.0, 58.5), (183.0, 53.0, 50.5), (198.0, 45.5, 42.0))
BOWL_FLOOR_Z = 214.0
RIB_DEPTH = 2.0  # how far the ribs on the bowl's walls stand out
FORE_SEAM_Z, AFT_SEAM_Z = 236.0, 428.0  # the habitat band turns between these
SEAM_INSET, SEAM_WIDTH = 2.5, 2.5  # the groove each side of the band
BAND_PIVOT = (0.0, 0.0, SPHERE_Z)
# The hexagonal mouth below the spine (the reference's, about 45 x 30 m): its outline in the bowl's floor and how deep it runs.
HEX = ((22.5, -21.5), (11.5, -8.0), (-11.5, -8.0), (-22.5, -21.5), (-11.5, -35.0), (11.5, -35.0))
HEX_BACK_Z = 216.0  # the mouth is a frame this deep; the shuttle bay's hall begins behind it
# The shuttle bay (Q84, Q96): a hall straight back behind the mouth, inside the fixed core the habitat band turns round. Its
# two berths lie either side of the mouth's axis, each on a straight lane through the mouth's middle (a fan: a craft is as
# wide as half the mouth, so two cannot pass it side by side); the deck stands above the mouth's lower edge, where a folded
# Kestrel passes the mouth with the same room above and below.
BAY_NAME = "bay_shuttle"
BAY_SIZE, BAY_DEPTH = (70.0, 23.2), 70.0  # the hall across and up, and how far back it runs
BAY_DECK_Y = -31.2
BAY_CRAFT = ("ea_shuttle", "ea_atmo_shuttle")  # berth by berth: the crew shuttle to starboard, the Kestrel to port
BAY_FAN_DEG = (-20.0, 20.0)  # each berth's way out, turned this far to starboard of straight ahead
BAY_RUN_M = (49.1, 54.0)  # from the mouth's plane back along its lane to each craft's middle: its stern 3 m off the back wall
BAY_DOOR_M = (45.4, 27.1)  # the shutter across the mouth, inside its frame
CORE_R, CORE_SIDES, CORE_END_Z = 52.0, 16, 298.0  # the fixed core the band's collision turns round, and where it ends
POD_ANGLES_DEG = (-70.5, -52.5, -34.5, -16.5, 19.5, 36.0, 53.5)  # the collar's teeth from starboard (the port ones are their twins)
POD_R, POD_Z = (62.0, 74.0), (166.0, COLLAR[0] + 0.5)
# The docking collars (Q84): on the tips of these four teeth below the spine (the port two are the twins), where a crew shuttle
# backed onto one lies clear of the spine, the saucer and its neighbour.
COLLAR_TEETH_DEG = (-34.5, -70.5)
COLLAR_NAMES = ("collar_upper_r", "collar_lower_r")
COLLAR_R, COLLAR_REACH = 2.6, 2.6  # the lock's radius and how far it stands ahead of its tooth
WINDOW_BAND_Z = (429.5, 441.5)  # the dark band of window rows on the aft cap
ENGINE_XY = (39.0, 37.5)  # the outer nacelles' axes; the middle pair stands on x = 0
ENGINE_Z = (466.0, 600.0)
NACELLE_R = 19.5
DRUM_R, DRUM_SQUASH = 21.5, 18.0 / 21.5  # the engines' drums: their height's half and how much narrower they are
BELL_Z, BELL_XY, BELL_WIDEN = 550.0, (38.6, 38.3), (1.03, 1.05, 1.17, 1.17)  # where the engines' bells begin, their axes (a little out of the drums'), how much wider than tall along them
REACTOR_R = 22.0
REACTOR_END_Z = 577.0  # the middle nacelles end here in a square exhaust box
BAR_Z = (465.0, 511.0)
SIDES = 96  # the sphere's segments round the axis: a meridian band is a whole number of them

PANEL = HullRoles(side="hull_panel", deck="hull_panel", keel="hull_panel", cap="hull_panel")
DARK = HullRoles(side="hull_dark", deck="hull_dark", keel="hull_dark", cap="hull_dark")
WHITE = HullRoles(side="hull", deck="hull", keel="hull", cap="hull")


@dataclasses.dataclass(frozen=True)
class Pattern:
    """How the sphere is painted (Q95, the show's layout): a band-coloured ring round the forward face from ``ring_z`` to
    ``ring_end_z`` (about as wide as a bar), a white rim inside it, and bars running aft from the ring to the aft groove,
    ``bar_half_m`` to each side of their meridians, white between them. A ship has one of ``bar_counts`` (the game draws the
    bars, by the ship's name)."""

    ring_z: float = 187.0
    ring_end_z: float = 202.0
    bar_counts: tuple[int, ...] = (6, 8)
    bar_half_m: float = 12.5


def sphere_r(z: float) -> float:
    """The sphere's radius across the axis at ``z``."""
    return math.sqrt(max(SPHERE_R**2 - (z - SPHERE_Z) ** 2, 0.0))


def _arc(z0: float, z1: float, step_deg: float = 3.0) -> list[tuple[float, float]]:
    """The sphere's outline from ``z0`` to ``z1`` as (z, r), a point every ``step_deg`` of its polar angle."""
    a0, a1 = (math.acos((z - SPHERE_Z) / SPHERE_R) for z in (z0, z1))
    n = max(2, int(math.ceil(abs(a1 - a0) / math.radians(step_deg))))
    zs = [SPHERE_Z + SPHERE_R * math.cos(a) for a in np.linspace(a0, a1, n + 1)]
    zs[0], zs[-1] = z0, z1
    return [(z, sphere_r(z)) for z in zs]


def _hull_shapes(name: str, z0: float, z1: float) -> list:
    """Collision for a zone of the sphere: convex steps of at most 15 degrees of arc, on a sphere grown so each step's chord
    touches the surface (the whole zone inside them, none of it much more than a metre and a half out)."""
    a0, a1 = (math.acos(np.clip((z - SPHERE_Z) / SPHERE_R, -1.0, 1.0)) for z in (z0, z1))
    n = max(1, int(math.ceil(abs(a1 - a0) / math.radians(15.0))))
    grown = SPHERE_R / math.cos(0.5 * abs(a1 - a0) / n)
    angles = np.linspace(a0, a1, n + 1)
    zs = [SPHERE_Z + grown * math.cos(a) for a in angles]
    zs[0], zs[-1] = z0, z1
    profile = [(z - z0, max(grown * math.sin(a), 1.0)) for z, a in zip(zs, angles, strict=True)]
    return cs._round_shapes(name, np.array([0.0, 0.0, z0]), np.array([0.0, 0.0, 1.0]), profile, 32)


def _revolved(name: str, profile: Sequence[tuple[float, float]], mats: Material | Sequence[Material], shapes: list,
              outline: Sequence[tuple[float, float]], creases: Sequence[int] = ()) -> cp.Module:
    """A zone of the sphere: ``profile`` (z, r) lathed round the axis, ``outline`` the (z, r) it buries (increasing z)."""
    mesh = lathe(profile, SIDES, mats, creases=creases)
    return cp.module(name, mesh, shapes, solid=lathe_solid(list(outline)))


def _ring_shapes(name: str, z0: float, z1: float) -> list:
    """Collision for a zone of the sphere as a ring round the fixed core: ``_hull_shapes``' steps, each in sectors whose inner
    faces are the core's sides (the band is a habitat ring; the shuttle bay lies in the core, which does not turn)."""
    a0, a1 = (math.acos(np.clip((z - SPHERE_Z) / SPHERE_R, -1.0, 1.0)) for z in (z0, z1))
    n = max(1, int(math.ceil(abs(a1 - a0) / math.radians(15.0))))
    grown = SPHERE_R / math.cos(0.5 * abs(a1 - a0) / n)
    angles = np.linspace(a0, a1, n + 1)
    zs = [SPHERE_Z + grown * math.cos(a) for a in angles]
    zs[0], zs[-1] = z0, z1
    radii = [grown * math.sin(a) for a in angles]
    step = 2.0 * math.pi / CORE_SIDES
    reach = 1.0 / math.cos(0.25 * step)  # three outer corners a sector, as col.ring_sectors
    out = []
    for i in range(n):
        for k in range(CORE_SIDES):
            b = k * step
            pts = [(r * math.cos(a), r * math.sin(a), z) for z, outer in ((zs[i], radii[i]), (zs[i + 1], radii[i + 1]))
                   for r, a in ((CORE_R, b), (CORE_R, b + step), (outer * reach, b), (outer * reach, b + 0.5 * step), (outer * reach, b + step))]
            out.append(col.hull(f"{name}_{i}_{k:02d}", np.array(pts)))
    return out


def _round_the_core(solid: Solid) -> Solid:
    """``solid`` without the fixed core: what the band buries, which is nothing of the bay's hall."""
    def test(p: np.ndarray, margin: float) -> np.ndarray:
        return solid.test(p, margin) & ((np.hypot(p[:, 0], p[:, 1]) > CORE_R) | (p[:, 2] > CORE_END_Z))

    return Solid(test, solid.local_bounds)


def _put(section: str, m: cp.Module, side: str = cp.CENTRE) -> cp.Module:
    return m.in_section(section).on_side(side)


# --- the command spine ---------------------------------------------------------------------------------------------------
# The spine behind the saucer, bow to the face: at each z the starboard half (x, y) of the skirt below and of the column above it
# (two lofts, since the outline narrows where the column rises from the skirt).
SKIRT_STATIONS = (
    (86.0, ((16.0, 19.0), (24.0, 19.0), (40.0, 21.0), (40.0, 29.0), (18.0, 41.0))),
    (105.0, ((16.0, 18.0), (40.0, 21.0), (42.0, 27.0), (34.0, 33.0), (26.0, 36.0), (20.0, 39.0), (17.0, 44.0))),
    (130.0, ((16.0, 18.0), (28.0, 19.0), (36.0, 20.2), (43.0, 21.0), (45.0, 27.0), (46.0, 30.0), (38.0, 36.0), (30.0, 39.5), (28.0, 42.0), (21.0, 45.0))),
    (150.0, ((16.0, 17.5), (32.0, 21.0), (46.0, 24.0), (48.0, 30.0), (42.0, 36.0), (36.0, 42.0), (31.0, 45.0), (20.0, 48.0))),
    (170.0, ((20.0, 17.5), (30.0, 17.5), (36.0, 21.0), (48.0, 23.5), (50.0, 31.0), (48.0, 36.0), (42.0, 44.0), (36.0, 49.5), (30.0, 50.8), (22.0, 51.5))),
    (FACE_Z + 2.0, ((20.0, 17.5), (30.0, 17.5), (36.0, 21.0), (50.0, 23.5), (51.0, 31.0), (49.0, 36.0), (43.0, 44.0), (37.0, 49.5), (31.0, 50.8), (22.0, 51.5))),
)
COLUMN_STATIONS = (
    (86.0, ((18.0, 40.0), (18.0, 53.0), (12.0, 56.0))),
    (105.0, ((17.0, 40.0), (16.0, 48.0), (14.0, 56.0), (10.0, 62.0))),
    (130.0, ((22.0, 45.0), (22.0, 62.0), (14.0, 65.0))),
    (150.0, ((19.0, 46.0), (19.0, 58.0), (19.0, 65.0))),
    (170.0, ((21.0, 50.0), (21.0, 64.0), (17.0, 66.0))),
    (FACE_Z + 2.0, ((22.0, 50.0), (22.0, 64.0), (17.0, 66.0))),
)
CREST_STATIONS = ((150.0, ((14.0, 60.0), (14.0, 69.0))), (170.0, ((17.0, 60.0), (17.0, 66.0), (14.0, 68.0), (14.0, 80.0), (12.0, 81.5))), (FACE_Z + 2.0, ((17.0, 60.0), (17.0, 66.0), (14.0, 68.0), (14.0, 81.0), (12.0, 83.0))))
LEDGE = ((24.0, 60.5, 65.5), (150.0, FACE_Z + 2.0))  # the shelf each side of the column's top: half width, y from, to; z from, to
SAUCER_AT, SAUCER_R = (0.0, 31.0, 47.0), 46.5


def _into_bowl(stations: tuple, narrow: float, towards_y: float, squash: float) -> tuple:
    """The stations with one more on the bowl's floor: the last one drawn in toward the axis, so the spine runs down into the
    cavity as the show's does (Q95)."""
    half = tuple((x * narrow, towards_y + (y - towards_y) * squash) for x, y in stations[-1][1])
    return (*stations, (BOWL_FLOOR_Z + 1.0, half))


def command(s: Style, bridge: str = "bridge", spine: str = "spine") -> list[cp.Module]:
    """The saucer bridge (a lens round an upright axis) with its ridge, the keel under it, the spine lofted through its measured
    stations (the skirt broadening aft, the column above it rising to the face) and a hexagonal pod each side."""
    profile = [(0.0, 0.0), (0.0, 20.0), (2.0, 23.0), (4.0, 30.0), (6.0, 35.0), (8.0, 39.0), (10.0, 43.0), (14.0, SAUCER_R),
               (18.0, 43.0), (20.0, 39.0), (22.0, 34.0), (24.0, 29.0), (26.0, 21.0), (28.0, 15.0), (31.0, 11.0), (32.0, 0.0)]
    x, y, z = SAUCER_AT
    panel, dark = s.material("hull_panel"), s.material("hull_dark")
    mats = [dark, dark, panel, panel, panel, panel, panel, panel, panel, panel, panel, panel, panel, panel, dark]
    saucer = cs.round_body("saucer", SAUCER_AT, (x, y + 32.0, z), profile, s, mats, sides=40, creases={1, 7})
    dome = cs.round_body("saucer_dome", (x, y + 29.0, z), (x, y + 34.5, z), [(0.0, 13.0), (3.0, 11.0), (5.5, 6.0), (5.5, 0.0)], s,
                         [s.material("window"), s.material("window"), panel], sides=24, skin=cp.SKIN_FITTING)
    ridge = cs.prism("saucer_ridge", [(-13.0, 50.0), (13.0, 50.0), (13.0, 58.0), (8.0, 62.0), (-8.0, 62.0), (-13.0, 58.0)], 40.0, 74.0, s, PANEL)
    nose = cs.prism("saucer_neck", [(-20.0, 30.0), (20.0, 30.0), (20.0, 36.0), (-20.0, 36.0)], 44.0, 92.0, s, PANEL)
    keel = cs.prism("keel", [(-24.0, 18.5), (24.0, 18.5), (26.0, 20.0), (26.0, 30.5), (-26.0, 30.5), (-26.0, 20.0)], 27.0, 92.0, s, DARK)
    body = []
    for part, stations in (("skirt", _into_bowl(SKIRT_STATIONS, 0.6, 30.0, 0.55)), ("column", _into_bowl(COLUMN_STATIONS, 0.65, 40.0, 0.8)),
                           ("crest", CREST_STATIONS)):
        for k, ((za, a), (zb, b)) in enumerate(zip(stations, stations[1:], strict=False)):
            ring = [(sx * x, y, z) for z, half in ((za, a), (zb, b)) for sx in (-1.0, 1.0) for x, y in half]
            body.append(cs.convex(f"{part}_{k + 1}", ring, s, PANEL))
    (w, y0, y1), (z0, z1) = LEDGE
    body.append(cs.box("column_ledge", (-w, y0, z0), (w, y1, z1), s, DARK))
    pod = cs.prism("spine_pod_r", [(26.0, 44.0), (46.0, 44.0), (49.0, 48.0), (49.0, 59.0), (46.0, 63.0), (22.0, 63.0), (22.0, 55.0)], 95.0, 122.0, s, DARK)
    mast = cs.rod("mast", (0.0, 62.0, 90.0), (0.0, 80.0, 90.0), 0.9, s)
    return ([_put(bridge, m) for m in (saucer, dome, ridge, nose)] + [_put(spine, m) for m in (keel, *body, mast)]
            + [_put(spine, pod, cp.RIGHT)])


# --- the forward face ----------------------------------------------------------------------------------------------------
def _bowl_r(z: np.ndarray) -> np.ndarray:
    """The bowl's radius at each ``z``; nothing ahead of the collar or behind the floor."""
    out = np.zeros_like(z, dtype=float)
    ends = [t[0] for t in BOWL[1:]] + [BOWL_FLOOR_Z]
    for (z0, top, foot), z1 in zip(BOWL, ends, strict=True):
        out = np.where((z >= z0) & (z < z1), top + (foot - top) * (z - z0) / (z1 - z0), out)
    return out


def _bowl_floor(material: Material, tunnel: Material, sill: Material) -> Mesh:
    """The bowl's floor, with the hexagonal mouth through it, the mouth's frame and the sill under the bay's deck."""
    hex_pts = np.array(HEX)
    centre = hex_pts.mean(axis=0)
    floor_z, floor_r = BOWL_FLOOR_Z, BOWL[-1][2]
    corners = [math.atan2(*(p - centre)[::-1]) for p in hex_pts]
    angles = sorted(set(corners) | set(np.linspace(-math.pi, math.pi, 73)[:-1].tolist()))
    quads = []
    for a, b in zip(angles, angles[1:] + angles[:1], strict=True):
        pts = []
        for t in (a, b):
            d = np.array([math.cos(t), math.sin(t)])
            inner = _ray_to_polygon(centre, d, hex_pts)
            # Where the ray from the mouth's centre leaves the floor's circle.
            bq = float(centre @ d)
            outer = centre + d * (-bq + math.sqrt(bq * bq - float(centre @ centre) + floor_r**2))
            pts.append((inner, outer))
        (ia, oa), (ib, ob) = pts
        quads.append(flat([(*ia, floor_z), (*oa, floor_z), (*ob, floor_z), (*ib, floor_z)], material, (0.0, 0.0, floor_z + 10.0)))
    axis = (float(centre[0]), float(centre[1]), 0.5 * (floor_z + HEX_BACK_Z))
    walls = [flat([(*a, floor_z), (*b, floor_z), (*b, HEX_BACK_Z), (*a, HEX_BACK_Z)], tunnel, (axis[0] + 3.0 * (a[0] + b[0] - 2 * axis[0]), axis[1] + 3.0 * (a[1] + b[1] - 2 * axis[1]), axis[2]))
             for a, b in zip(HEX, HEX[1:] + HEX[:1], strict=True)]
    below = _clip_xy(list(HEX), lambda p: BAY_DECK_Y - p[1])
    plate = flat([(*p, HEX_BACK_Z) for p in below], sill, (axis[0], axis[1], HEX_BACK_Z + 10.0))
    return Mesh.concatenate([*quads, *walls, plate])


def _ray_to_polygon(origin: np.ndarray, d: np.ndarray, poly: np.ndarray) -> np.ndarray:
    """Where a ray from inside a convex polygon leaves it."""
    best = math.inf
    for a, b in zip(poly, np.roll(poly, -1, axis=0), strict=True):
        e, w = b - a, a - origin
        den = d[0] * e[1] - d[1] * e[0]
        if abs(den) < 1e-12:
            continue
        t = (w[0] * e[1] - w[1] * e[0]) / den
        u = (w[0] * d[1] - w[1] * d[0]) / den
        if t > 1e-9 and -1e-9 <= u <= 1.0 + 1e-9:
            best = min(best, t)
    return origin + best * d


def _clip_xy(poly: list[tuple[float, float]], keep) -> list[tuple[float, float]]:  # noqa: ANN001 - keep(p) linear in p
    """The part of a convex outline where ``keep(p)`` is not negative."""
    out: list[tuple[float, float]] = []
    for a, b in zip(poly, poly[1:] + poly[:1], strict=True):
        fa, fb = keep(a), keep(b)
        if fa >= 0.0:
            out.append(a)
        if (fa >= 0.0) != (fb >= 0.0):
            t = fa / (fa - fb)
            out.append((a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])))
    return out


COLLAR_SLOPE = ((178.0, 81.0), (181.5, 87.0))  # the collar's outside between its face and the sphere's edge, as (z, r)


def _cap_solid(z0: float, z1: float) -> Solid:
    """What the forward cap buries under its skin from ``z0`` to ``z1`` (and, from the face, its collar): the sphere there, less
    the bowl (where the spine runs in) and the open mouth."""
    cz, _, c1 = COLLAR
    outline = ((cz, c1), *COLLAR_SLOPE, (FACE_Z, sphere_r(FACE_Z)))
    hex_pts = np.array(HEX)
    edges = [(a, b - a) for a, b in zip(hex_pts, np.roll(hex_pts, -1, axis=0), strict=True)]

    def test(p: np.ndarray, margin: float) -> np.ndarray:
        r = np.hypot(p[:, 0], p[:, 1])
        z = p[:, 2]
        ball = (z > z0) & (z < z1 - (margin if z1 == FORE_SEAM_Z else 0.0)) & (np.linalg.norm(p - np.array([0.0, 0.0, SPHERE_Z]), axis=1) < SPHERE_R - margin)
        if z0 != FACE_Z:
            ball &= r > c1  # the skin behind the ring buries what stands under it, never the bowl's floor
        ring = (z0 == FACE_Z) & (z > cz + margin) & (z <= FACE_Z) & (r < np.interp(z, [q[0] for q in outline], [q[1] for q in outline]) - margin)
        bowl = (z < BOWL_FLOOR_Z + margin) & (r < _bowl_r(z) + margin)
        in_mouth = z < HEX_BACK_Z + margin
        for a, e in edges:
            in_mouth &= (e[0] * (p[:, 1] - a[1]) - e[1] * (p[:, 0] - a[0])) > -margin  # left of each edge, the outline running anticlockwise
        return (ball | ring) & ~bowl & ~in_mouth

    big = SPHERE_R
    return Solid(test, ((-big, -big, cz if z0 == FACE_Z else z0), (big, big, z1)))


def _bowl_shapes(count: int = 16) -> list:
    """Collision for the collar and the bowl's walls down to its floor, in ``count`` sectors round the axis, a shape a terrace:
    the walls stand a metre in, so the ribs on them are inside."""
    cz, _, c1 = COLLAR
    reach = 1.0 / math.cos(0.25 * 2.0 * math.pi / count)  # three outer corners a sector, as col.ring_sectors
    ends = [t[0] for t in BOWL[1:]] + [BOWL_FLOOR_Z]
    out = []
    for k in range(count):
        a0 = 2.0 * math.pi * k / count
        a1 = a0 + 2.0 * math.pi / count
        for tier, ((z0, top, foot), z1) in enumerate(zip(BOWL, ends, strict=True)):
            inner = ((top - 0.5 * RIB_DEPTH, z0), (foot - 0.5 * RIB_DEPTH, z1))
            outer = ((c1, cz), *((r, z) for z, r in COLLAR_SLOPE), (sphere_r(FACE_Z), FACE_Z)) if tier == 0 else \
                ((sphere_r(z0) + 0.6, z0), (sphere_r(z1) + 0.6, z1))
            pts = [(r * math.cos(a), r * math.sin(a), z) for r, z in inner for a in (a0, a1)]
            pts += [(r * reach * math.cos(a), r * reach * math.sin(a), z) for r, z in outer for a in (a0, 0.5 * (a0 + a1), a1)]
            out.append(col.hull(f"cap_bowl_{tier}_{k:02d}", np.array(pts)))
    return out


def _mouth_shapes() -> list:
    """Collision for the mouth's frame, from the bowl's floor to the bay's hall, round the hexagonal mouth and not across it
    (shuttles fly in there): the parts above and below it and, each side, above and below its pointed end."""
    def edge(a: tuple[float, float], b: tuple[float, float]):  # noqa: ANN202 - the side of the hex edge a-b away from its middle
        centre = np.array(HEX).mean(axis=0)
        n = np.array([b[1] - a[1], a[0] - b[0]])
        n = n if float(n @ (np.array(a) - centre)) > 0.0 else -n
        return lambda p: float(n @ (np.array(p) - np.array(a)))

    top, low = HEX[1][1], HEX[4][1]
    mid = HEX[0][1]
    regions = {
        "top": [lambda p: p[1] - top],
        "low": [lambda p: low - p[1]],
        "side_up_r": [lambda p: top - p[1], lambda p: p[1] - mid, edge(HEX[0], HEX[1]), lambda p: p[0]],
        "side_low_r": [lambda p: mid - p[1], lambda p: p[1] - low, edge(HEX[5], HEX[0]), lambda p: p[0]],
    }
    regions["side_up_l"] = [regions["side_up_r"][0], regions["side_up_r"][1], edge(HEX[2], HEX[3]), lambda p: -p[0]]
    regions["side_low_l"] = [regions["side_low_r"][0], regions["side_low_r"][1], edge(HEX[3], HEX[4]), lambda p: -p[0]]
    sides = 24
    out = []
    for name, keeps in regions.items():
        rings = []
        for z in (BOWL_FLOOR_Z, HEX_BACK_Z):
            r = (sphere_r(z) + 0.6) / math.cos(math.pi / sides)
            poly = [(r * math.cos(a), r * math.sin(a)) for a in np.linspace(0.0, 2.0 * math.pi, sides, endpoint=False)]
            for keep in keeps:
                poly = _clip_xy(poly, keep)
            rings += [(x, y, z) for x, y in poly]
        out.append(col.hull(f"cap_mouth_{name}", np.array(rings)))
    return out


def _on_wall(deg: float) -> bool:
    """Whether the bowl's wall at this angle (from starboard) shows: on the starboard half, clear of the spine above."""
    return -90.0 < deg < 14.0


def bowl_fittings(s: Style, section: str = "face") -> list[cp.Module]:
    """What stands on the bowl's walls (the show's cavity is full of structure): ribs down every terrace, fewer the deeper, and
    a few lit ports low on the inner walls. The starboard half; the spine hides the wall above it."""
    ends = [t[0] for t in BOWL[1:]] + [BOWL_FLOOR_Z]
    ribs: list[Mesh] = []
    lights: list[Mesh] = []
    glow = s.material("window")
    for tier, ((z0, top, foot), z1) in enumerate(zip(BOWL, ends, strict=True)):
        step = (11.25, 15.0, 22.5)[tier]
        for k in range(int(360.0 / step)):
            deg = -180.0 + (k + 0.5) * step
            if not _on_wall(deg):
                continue
            a = math.radians(deg)
            u, v = np.array([math.cos(a), math.sin(a), 0.0]), np.array([-math.sin(a), math.cos(a), 0.0])
            pts = [(r + dr) * u + w * v + np.array([0.0, 0.0, z]) for r, z in ((top, z0 + 0.4), (foot, z1))
                   for dr in (0.4, -RIB_DEPTH) for w in (-0.8, 0.8)]
            ribs.append(cs.convex("rib", pts, s, PANEL, skin=cp.SKIN_FITTING).part.mesh)
            if tier > 0 and deg < -20.0:
                # A lit port between this rib and the next, facing the axis.
                b = math.radians(deg + 0.5 * step)
                z = 0.5 * (z0 + z1)
                r = 0.5 * (top + foot) - 0.15
                p = np.array([r * math.cos(b), r * math.sin(b), z])
                t = np.array([-math.sin(b), math.cos(b), 0.0])
                lights.append(flat([p + su * 1.2 * t + np.array([0.0, 0.0, sv * 0.7]) for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))], glow, (0.0, 0.0, z)))
    # Their collision is the walls' own; each module's token shape lies buried in the collar.
    buried = (0.5 * (COLLAR[1] + COLLAR[2]) * math.cos(math.radians(-45.0)), 0.5 * (COLLAR[1] + COLLAR[2]) * math.sin(math.radians(-45.0)), FACE_Z)
    return [_put(section, cp.module("bowl_ribs_r", Mesh.concatenate(ribs), [col.box("bowl_ribs_r", buried, (2.0, 2.0, 2.0))], skin=cp.SKIN_FITTING), cp.RIGHT),
            _put(section, cp.module("bowl_ports_r", Mesh.concatenate(lights), [col.box("bowl_ports_r", buried, (2.0, 2.0, 2.0))], skin=cp.SKIN_NONE,
                                    fine=0.5), cp.RIGHT)]


def forward_face(s: Style, pattern: Pattern, section: str = "face") -> list[cp.Module]:
    """The sphere's forward cap: the collar with its ring of teeth, the terraced bowl inside it down to the floor with the open
    hexagonal mouth, and outside a white rim and the ring in the band colour, where its skin ends (the rest turns, ``band``)."""
    panel, dark, white, green = s.material("hull_panel"), s.material("hull_dark"), s.material("hull"), s.material("stripe")
    rim, ring = _arc(FACE_Z, pattern.ring_z), _arc(pattern.ring_z, pattern.ring_end_z)
    cz, _, c1 = COLLAR
    ends = [t[0] for t in BOWL[1:]] + [BOWL_FLOOR_Z]
    # From the floor's edge up the terraces (wall, ledge, wall, ...) to the collar's face, then out and back to the groove.
    profile: list[tuple[float, float]] = []
    mats: list[Material] = []
    for (z0, top, foot), z1 in reversed(list(zip(BOWL, ends, strict=True))):
        profile += [(z1, foot), (z0, top)]
        mats += [dark, panel]  # the wall, then the ledge above it
    mats[-1] = panel  # above the top wall, the collar's face
    profile += [(cz, c1), *COLLAR_SLOPE, *rim, *ring[1:]]
    mats += [panel] * (len(COLLAR_SLOPE) + 1) + [white] * (len(rim) - 1) + [green] * (len(ring) - 1)
    creases = set(range(1, 2 * len(BOWL) + len(COLLAR_SLOPE) + 2))
    mesh = Mesh.concatenate([lathe(profile, SIDES, mats, creases=creases), _bowl_floor(dark, s.material("interior"), s.material("bore"))])
    shapes = [*_bowl_shapes(), *_mouth_shapes()]  # behind the frame the cap's collision is the bay's (``shuttle_bay``)
    cap = cp.module("forward_cap", mesh, shapes, solid=_cap_solid(FACE_Z, pattern.ring_end_z))
    out = [_put(section, cap), *bowl_fittings(s, section)]
    for k, deg in enumerate(POD_ANGLES_DEG):
        a = math.radians(deg)
        u, v = np.array([math.cos(a), math.sin(a), 0.0]), np.array([-math.sin(a), math.cos(a), 0.0])
        base = [r * u + w * v + np.array([0.0, 0.0, POD_Z[1]]) for r in POD_R for w in (-4.0, 4.0)]
        tip = [r * u + w * v + np.array([0.0, 0.0, POD_Z[0]]) for r in (65.0, 70.0) for w in (-3.0, 3.0)]
        out.append(_put(section, cs.convex(f"collar_tooth_{k}_r", base + tip, s, DARK, skin=cp.SKIN_FITTING), cp.RIGHT))
    keel = [(w, -r, z) for z, rs, ws in ((POD_Z[1], POD_R, (-5.0, 5.0)), (POD_Z[0], (64.0, 70.0), (-4.0, 4.0))) for r in rs for w in ws]
    out.append(_put(section, cs.convex("collar_tooth_keel", keel, s, DARK, skin=cp.SKIN_FITTING)))
    return out


def _round_a_hall(name: str, z: tuple[float, float], outline, sides: int) -> list:  # noqa: ANN001 - outline(z) a radius
    """Collision for a round block from ``z[0]`` to ``z[1]`` with the bay's hall left open through it: the parts above and
    below the hall and one each side. ``outline(z)`` is the radius of the block's ``sides`` corners there."""
    half, (y0, y1) = 0.5 * BAY_SIZE[0], (BAY_DECK_Y, BAY_DECK_Y + BAY_SIZE[1])
    regions = {
        "top": [lambda p: p[1] - y1],
        "low": [lambda p: y0 - p[1]],
        "side_r": [lambda p: y1 - p[1], lambda p: p[1] - y0, lambda p: p[0] - half],
        "side_l": [lambda p: y1 - p[1], lambda p: p[1] - y0, lambda p: -half - p[0]],
    }
    out = []
    for part, keeps in regions.items():
        rings = []
        for at in z:
            poly = [(outline(at) * math.cos(a), outline(at) * math.sin(a)) for a in np.linspace(0.0, 2.0 * math.pi, sides, endpoint=False)]
            for keep in keeps:
                poly = _clip_xy(poly, keep)
            rings += [(x, y, at) for x, y in poly]
        out.append(col.hull(f"{name}_{part}", np.array(rings)))
    return out


def _bay_shapes() -> list:
    """Collision round the bay's hall: the cap behind the mouth's frame out to the sphere, then the fixed core the band turns
    round (its corners where the band's sectors meet, so the two lie face to face as built), and the core's solid end."""
    cap = _round_a_hall("cap_bay", (HEX_BACK_Z, FORE_SEAM_Z), lambda z: (sphere_r(z) + 0.6) / math.cos(math.pi / 24), 24)
    back = HEX_BACK_Z + BAY_DEPTH
    core = _round_a_hall("core_bay", (FORE_SEAM_Z, back), lambda _z: CORE_R, CORE_SIDES)
    ring = [(CORE_R * math.cos(a), CORE_R * math.sin(a)) for a in np.linspace(0.0, 2.0 * math.pi, CORE_SIDES, endpoint=False)]
    end = col.hull("core_end", np.array([(x, y, z) for z in (back, CORE_END_Z) for x, y in ring]))
    return [*cap, *core, end]


def _bay_front(material: Material) -> Mesh:
    """The hall's front wall, seen from inside: round the mouth, which is cut off at the deck."""
    half, (y0, y1) = 0.5 * BAY_SIZE[0], (BAY_DECK_Y, BAY_DECK_Y + BAY_SIZE[1])
    z = HEX_BACK_Z + 0.1  # a hand inside the hall, so it is lit as the hall is
    mouth = np.array(_clip_xy(list(HEX), lambda p: p[1] - y0))
    wall = np.array([(half, y0), (half, y1), (-half, y1), (-half, y0)])
    centre = mouth.mean(axis=0)
    corners = [math.atan2(*(p - centre)[::-1]) for p in (*mouth, *wall)]
    angles = sorted(set(corners) | set(np.linspace(-math.pi, math.pi, 25)[:-1].tolist()))
    quads = []
    for a, b in zip(angles, angles[1:] + angles[:1], strict=True):
        rays = [np.array([math.cos(t), math.sin(t)]) for t in (a, b)]
        (ia, oa), (ib, ob) = ((_ray_to_polygon(centre, d, mouth), _ray_to_polygon(centre, d, wall)) for d in rays)
        if float(np.linalg.norm(oa - ia)) + float(np.linalg.norm(ob - ib)) > 1e-6:  # along the deck the mouth's edge is the wall's
            quads.append(flat([(*ia, z), (*oa, z), (*ob, z), (*ib, z)], material, (0.0, 0.0, z - 10.0)))
    return Mesh.concatenate(quads)


def shuttle_bay(s: Style, section: str = "face") -> cp.Module:
    """The shuttle bay behind the mouth (Q84, Q96): a metal-lined hall lit red by its own lamp, its front wall round the
    mouth, a roll-up door across the mouth inside its frame, and the ``bay`` hardpoint with its two berths: ``berth_craft``
    names each berth's craft, ``berth_fan_deg`` its lane (the way out, turned to starboard of the bay's) and ``berth_run_m``
    how far back along it the craft's middle rests. ``mouth_m`` is the hall's own section; ``aperture_m`` the mouth's."""
    centre_y = BAY_DECK_Y + 0.5 * BAY_SIZE[1]
    hall = bays.launch_bay(BAY_NAME, BAY_SIZE, BAY_DEPTH, s, wall_m=1.0, lit=True, rim=False, metal=True, housing=False)
    hall = hall.transformed(np.eye(3), (0.0, centre_y, HEX_BACK_Z))
    mouth_y = float(np.array(HEX)[:, 1].mean())
    door = cp.Hardpoint(f"{BAY_NAME}_door", cp.DOOR, (0.0, mouth_y, 0.5 * (BOWL_FLOOR_Z + HEX_BACK_Z)), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0),
                        {"size_m": [*BAY_DOOR_M, bays.DOOR_THICK_M], "slats": round(BAY_DOOR_M[1] / bays.SLAT_M)})
    mesh = Mesh.concatenate([hall.part.mesh, _bay_front(s.material("bay_metal"))])
    hall = dataclasses.replace(hall, part=dataclasses.replace(hall.part, mesh=mesh), shapes=tuple(_bay_shapes()), hardpoints=(*hall.hardpoints, door))
    width = float(np.ptp(np.array(HEX)[:, 0]))
    height = float(np.ptp(np.array(HEX)[:, 1]))
    return _put(section, hall.with_params(cp.BAY, craft=BAY_CRAFT[0], capacity=len(BAY_CRAFT), berths=len(BAY_CRAFT), berth_craft=list(BAY_CRAFT),
                                          berth_fan_deg=list(BAY_FAN_DEG), berth_run_m=list(BAY_RUN_M), aperture_m=[width, height], visitors=True))


def docking_collars(s: Style, section: str = "face") -> list[cp.Module]:
    """The starboard docking collars (Q84; their port twins follow): a short lock with a lit rim on a tooth's tip, facing
    forward, and its ``dock`` hardpoint on the lock's face, where a crew shuttle's stern hatch meets it."""
    dark, glow = s.material("hull_dark"), s.material("window")
    out = []
    for name, deg in zip(COLLAR_NAMES, COLLAR_TEETH_DEG, strict=True):
        a = math.radians(deg)
        x, y = 67.5 * math.cos(a), 67.5 * math.sin(a)  # the middle of the tooth's tip
        z0, z1 = POD_Z[0], POD_Z[0] - COLLAR_REACH
        profile = [(0.0, COLLAR_R + 0.4), (0.7, COLLAR_R + 0.4), (0.7, COLLAR_R), (COLLAR_REACH, COLLAR_R), (COLLAR_REACH, 0.0)]
        lock = cs.round_body(name, (x, y, z0), (x, y, z1), profile, s, [dark, glow, dark, dark], sides=16, creases={1, 2, 3}, skin=cp.SKIN_FITTING)
        point = cp.Hardpoint(name, cp.DOCK, (x, y, z1), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), {"radius_m": COLLAR_R})
        out.append(_put(section, dataclasses.replace(lock, hardpoints=(point,)), cp.RIGHT))
    return out


# --- the habitat band and the aft cap ------------------------------------------------------------------------------------
def band(s: Style, pattern: Pattern, section: str = "habitat") -> list[cp.Module]:
    """The turning band in two halves split at the equator (the mining transport parts its sphere there, T56), white (the game
    draws the ship's bars on it), grooved at both edges, two rows of windows on each half; and ahead of it the skin from the
    ring's aft edge, turning with it so the bars meet the ring whole."""
    white, dark = s.material("hull"), s.material("hull_dark")
    # Skin only: the forward cap's structure and collision lie under it; its token shape lies buried in the band's.
    lead = cp.module("band_lead", lathe(_arc(pattern.ring_end_z, FORE_SEAM_Z), SIDES, white), [col.box("band_lead", (0.0, 0.0, FORE_SEAM_Z + 10.0), (2.0, 2.0, 2.0))],
                     solid=_cap_solid(pattern.ring_end_z, FORE_SEAM_Z))
    out = [_put(section, lead)]
    for name, z0, z1 in (("band_fore", FORE_SEAM_Z, SPHERE_Z), ("band_aft", SPHERE_Z, AFT_SEAM_Z)):
        # Open at both ends (nothing inside the sphere takes atlas space); at a seam the band owns its groove's two walls.
        lo, hi = z0 + (SEAM_WIDTH if z0 == FORE_SEAM_Z else 0.0), z1 - (SEAM_WIDTH if z1 == AFT_SEAM_Z else 0.0)
        arc = _arc(lo, hi)
        fore = [(z0, sphere_r(z0)), (z0, sphere_r(z0) - SEAM_INSET)] if z0 == FORE_SEAM_Z else []
        aft = [(z1, sphere_r(z1) - SEAM_INSET), (z1, sphere_r(z1))] if z1 == AFT_SEAM_Z else []
        profile = [*fore, *arc, *aft]
        mats = [dark] * len(fore) + [white] * (len(arc) - 1) + [dark] * len(aft)
        outline = [(z0, sphere_r(z0)), *[p for p in profile if lo < p[0] < hi], (z1, sphere_r(z1))]
        shapes = _hull_shapes(name, z0, z1) if z0 >= CORE_END_Z else [*_ring_shapes(name, z0, CORE_END_Z), *_hull_shapes(f"{name}_aft", CORE_END_Z, z1)]
        half = _revolved(name, profile, mats, shapes, outline, creases={1, len(profile) - 2})
        out.append(_put(section, dataclasses.replace(half, solid=_round_the_core(half.solid)) if z0 < CORE_END_Z else half))
        out.append(_put(section, window_rows(f"{name}_windows", s, 0.5 * (z0 + z1), rows=2)))
    return out


def _window(at_deg: float, z: float, half: tuple[float, float], mat: Material) -> Mesh:
    """One lit window, a plate standing just proud of the sphere: ``half`` its half width round the axis and along it."""
    a = math.radians(at_deg)
    r = sphere_r(z)
    p = np.array([r * math.cos(a), r * math.sin(a), z])
    n = (p - np.array([0.0, 0.0, SPHERE_Z])) / SPHERE_R
    t = np.array([-math.sin(a), math.cos(a), 0.0])
    b = np.cross(n, t)
    corners = [p + 0.15 * n + su * half[0] * t + sv * half[1] * b for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    return flat(corners, mat, (0.0, 0.0, SPHERE_Z))


def window_rows(name: str, s: Style, z: float, rows: int = 1) -> cp.Module:
    """Rows of lit windows round the sphere at ``z`` in groups of four (the show's), a group every 15 degrees: the bars, six or
    eight to a ship, run between the groups."""
    glow = s.material("window")
    meshes: list[Mesh] = []
    for g in range(24):
        centre = g * 15.0 + 7.5
        for row in range(rows):
            zz = z + (row - 0.5 * (rows - 1)) * 6.0
            step = math.degrees(4.6 / sphere_r(zz))
            meshes += [_window(centre + (k - 1.5) * step, zz, (1.6, 1.1), glow) for k in range(4)]
    mesh = Mesh.concatenate(meshes)
    lo, hi = mesh.bounds()
    centre = 0.5 * (lo + hi)
    return cp.module(name, mesh, [col.box(name, (float(centre[0]), float(centre[1]), z), (2.0, 2.0, 2.0))], skin=cp.SKIN_NONE, fine=0.5)


def aft_cap(s: Style, section: str = "sphere_aft") -> list[cp.Module]:
    """The sphere's aft cap from the band's groove: the dark window band at its forward edge, white aft of it."""
    white, dark = s.material("hull"), s.material("hull_dark")
    arc = _arc(AFT_SEAM_Z, SPHERE_Z + SPHERE_R - 0.5)
    arc = sorted({*arc, *((z, sphere_r(z)) for z in WINDOW_BAND_Z)})
    profile = [*arc, (arc[-1][0], 0.0)]
    mats = [dark if WINDOW_BAND_Z[0] <= 0.5 * (a[0] + b[0]) <= WINDOW_BAND_Z[1] or b[0] <= WINDOW_BAND_Z[0] else white
                     for a, b in zip(arc, arc[1:], strict=False)] + [white]
    cap = _revolved("aft_cap", profile, mats, _hull_shapes("aft_cap", AFT_SEAM_Z, arc[-1][0]), arc)
    return [_put(section, cap), _put(section, window_rows("aft_windows", s, 0.5 * sum(WINDOW_BAND_Z)))]


def brackets(s: Style, name: str, section: str, z: tuple[float, float], phase_deg: float = 0.0) -> cp.Module:
    """The twelve clamps standing on the sphere beside a groove (the reference's), as one part."""
    parts = []
    for k in range(12):
        a = math.radians(phase_deg + 30.0 * k)
        turn = rotation_z(a)
        r0, r1 = min(sphere_r(z[0]), sphere_r(z[1])) - 1.5, max(sphere_r(z[0]), sphere_r(z[1])) + 2.0
        pts = [turn @ np.array([r, w, zz]) for r in (r0, r1) for w in (-3.0, 3.0) for zz in z]
        parts.append(cs.convex(f"{name}_{k}", pts, s, DARK, skin=cp.SKIN_FITTING))
    return _put(section, cs.compound(name, parts))


# --- the engine frame ----------------------------------------------------------------------------------------------------
def engine_frame(s: Style, section: str = "reactor") -> list[cp.Module]:
    """The cross of radiator bars behind the sphere and the middle pair of nacelles, the reactors, each ending in a square
    exhaust box."""
    bar_h = cs.box("frame_bar_side", (-100.0, -17.5, BAR_Z[0]), (100.0, 17.5, BAR_Z[1]), s, DARK)
    bar_v = cs.box("frame_bar_dorsal", (-17.0, -100.0, BAR_Z[0]), (17.0, 100.0, BAR_Z[1]), s, DARK)
    out = [_put(section, bar_h), _put(section, bar_v)]
    panel, dark = s.material("hull_panel"), s.material("hull_dark")
    for tag, sy in (("top", 1.0), ("low", -1.0)):
        y = sy * ENGINE_XY[1]
        end = REACTOR_END_Z - ENGINE_Z[0]
        body = cs.round_body(f"reactor_{tag}", (0.0, y, ENGINE_Z[0]), (0.0, y, REACTOR_END_Z), [(0.0, 0.0), (0.0, REACTOR_R - 1.0), (6.0, REACTOR_R),
                             (end - 3.0, REACTOR_R), (end, REACTOR_R - 3.0), (end, 0.0)], s, [dark, panel, panel, dark, dark], sides=24, creases={1, 2, 3, 4})
        box = cs.box(f"reactor_{tag}_exhaust", (-12.0, y - 11.0, REACTOR_END_Z - 4.0), (12.0, y + 11.0, ENGINE_Z[1] - 2.0), s, DARK)
        out += [_put(section, body), _put(section, box)]
    return out


def _widened(m: cp.Module, centre_x: float, zs: Sequence[float], widths: Sequence[float]) -> cp.Module:
    """A round part made oval: stretched across x about ``centre_x`` by a factor that runs through ``widths`` at ``zs``. Its
    burial volume stays the round one, which lies inside."""
    def stretch(p: np.ndarray) -> np.ndarray:
        out = np.array(p, dtype=float)
        out[:, 0] = centre_x + (out[:, 0] - centre_x) * np.interp(out[:, 2], zs, widths)
        return out

    mesh = dataclasses.replace(m.part.mesh, vertices=stretch(m.part.mesh.vertices))
    shapes = tuple(col.hull(q.name, stretch(q.points)) if q.kind == col.HULL else q for q in m.shapes)
    return dataclasses.replace(m, part=dataclasses.replace(m.part, mesh=mesh), shapes=shapes)


def engine(s: Style, name: str, section: str, up: float) -> cp.Module:
    """One starboard engine (``up`` +1 the upper, -1 the lower): an oval drum taller than wide and an oval bell wider than tall
    (the reference's), open to its glowing bore, the engine's hardpoint at the mouth."""
    x, y = ENGINE_XY[0], up * ENGINE_XY[1]
    z0, z1 = ENGINE_Z
    hull, dark, metal, glow = s.material("hull_panel"), s.material("hull_dark"), s.material("nozzle"), s.material("nozzle_throat")
    drum_len = BELL_Z - z0
    drum_profile = [(0.0, 0.0), (0.0, DRUM_R - 1.0), (6.0, DRUM_R), (drum_len, DRUM_R), (drum_len, 0.0)]
    squash = np.diag([DRUM_SQUASH, 1.0, 1.0])
    drum = cs.round_body(f"{name}_drum", (0.0, y, z0), (0.0, y, BELL_Z), drum_profile, s, [dark, hull, hull, dark], sides=24, creases={1, 2, 3})
    inside = cs.round_body("inside", (0.0, y, z0), (0.0, y, BELL_Z), [(d, r * DRUM_SQUASH) for d, r in drum_profile], s).solid
    drum = dataclasses.replace(drum.transformed(squash, (x, 0.0, 0.0)), solid=inside.translated((x, 0.0, 0.0)))
    length = z1 - BELL_Z
    bell_profile = [(0.0, 0.0), (0.0, 17.0), (23.0, 17.0), (25.0, 15.3), (length, 15.0), (length, 10.5), (length - 25.0, 10.2), (length - 25.0, 0.0)]
    bx, by = BELL_XY[0], up * BELL_XY[1]
    bell = cs.round_body(f"{name}_bell", (bx, by, BELL_Z), (bx, by, z1), bell_profile, s, [dark, hull, dark, metal, metal, metal, glow], sides=24,
                         creases=set(range(1, 7)), skin=cp.SKIN_FITTING, hollow_from=5)
    bell = _widened(bell, bx, (BELL_Z, BELL_Z + 23.0, BELL_Z + 25.0, z1), BELL_WIDEN)
    point = cp.Hardpoint(name, cp.ENGINE, (bx, by, z1), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), {"share": 0.25, "radius_m": 12.0})
    return _put(section, dataclasses.replace(cs.compound(name, [drum, bell]), hardpoints=(point,)), cp.RIGHT)


__all__ = ["AFT_SEAM_Z", "BAND_PIVOT", "BAY_CRAFT", "BAY_DECK_Y", "BAY_DEPTH", "BAY_DOOR_M", "BAY_FAN_DEG", "BAY_NAME", "BAY_RUN_M", "BAY_SIZE", "BOWL", "BOWL_FLOOR_Z", "COLLAR_NAMES", "CORE_END_Z", "CORE_R", "CORE_SIDES", "COLLAR_R", "COLLAR_TEETH_DEG", "ENGINE_XY", "ENGINE_Z", "FACE_Z", "FORE_SEAM_Z", "HEX", "HEX_BACK_Z", "LENGTH_M", "POD_ANGLES_DEG",
           "Pattern", "SAUCER_AT", "SEAM_WIDTH", "SPHERE_R", "SPHERE_Z", "WINDOW_BAND_Z", "aft_cap", "band", "bowl_fittings", "brackets", "command", "docking_collars", "engine",
           "engine_frame", "forward_face", "shuttle_bay", "sphere_r", "window_rows"]
