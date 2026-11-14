"""The station's dorsal spine, command section and bow as the reference STL has them (M7-T22): each part a solid lofted through
sections read off the STL at fixed planes (``reports/M7-T22_stl_measurements.md``, ``docs/assets-station.md``), station frame (z aft
from the bow tip, x starboard, y up), metres.

A member is a run of sections along z with the same number of corners. A ``side`` member is one piece to starboard, copied to port;
any other is the right half of one piece symmetric about x = 0, listed from the top's middle down the starboard side to the
underside's middle. Sections need not be convex (a ledge, a radiator's wing); the ends are closed by ear clipping.

What follows the spine reads it here: the collision pieces (one hull per pair of sections), the tops the compartments stand on, the
faces the windows lie on, the prongs' edges the fork teeth hang from.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Material, Mesh

Profile = tuple[tuple[float, float], ...]
Row = tuple[float, Profile]
MIRROR_Z = 3577.0  # the spine aft of the cargo modules mirrors the spine before them about this plane (the STL's)


@dataclass(frozen=True)
class Member:
    """One lofted solid: its name (the collision pieces take it), the shape it belongs to, its sections along z, whether it is one
    piece to starboard copied to port, and whether it has collision of its own."""

    name: str
    part: str
    rows: tuple[Row, ...]
    side: bool = False
    collide: bool = True  # False: drawn only; a bigger member's hull or a proxy covers it within the collision's gap tolerance


def _rows(*rows: tuple[float, Sequence[tuple[float, float]]]) -> tuple[Row, ...]:
    return tuple((float(z), tuple((float(x), float(y)) for x, y in p)) for z, p in rows)


def _box(w: float, y0: float, y1: float) -> Profile:
    """A box's right half."""
    return ((0.0, y1), (w, y1), (w, y0), (0.0, y0))


def _rect(x0: float, x1: float, y0: float, y1: float) -> Profile:
    return ((x0, y0), (x1, y0), (x1, y1), (x0, y1))


def mirrored(rows: Sequence[Row], about: float = MIRROR_Z) -> tuple[Row, ...]:
    """The same sections mirrored front to back about ``about``."""
    return tuple((2.0 * about - z, p) for z, p in reversed(rows))


# --- the bow: two prongs, each a six-sided section (flat top, a sloped outer shoulder bending out to the side) -------------------
# (z, underside, outer x, side's top, the shoulder's knee (x, y), the top's end x, top); the inner side stands at x 46.5. A flange
# hangs under each prong's outer half: (z, x from, its underside).
PRONG_INNER_X = 46.5
PRONG = ((0.0, 315.0, 55.0, 319.0, (53.0, 320.0), 51.0, 321.0), (25.0, 315.0, 60.5, 322.0, (59.0, 323.0), 58.0, 324.0),
         (50.0, 315.0, 65.0, 325.8, (59.5, 326.5), 55.5, 329.0), (100.0, 315.0, 87.5, 320.8, (74.0, 327.0), 72.5, 331.0),
         (200.0, 315.0, 111.0, 321.8, (104.0, 325.8), 89.5, 340.0), (300.0, 314.5, 134.5, 322.2, (129.5, 324.2), 106.0, 349.5),
         (400.0, 315.0, 158.0, 323.2, (154.5, 324.2), 123.5, 360.0), (430.0, 314.0, 162.5, 323.2, (161.0, 323.8), 126.0, 362.5))
# A second bend in the shoulder where the STL has one (the rest lie on the straight line): z, (x, y).
PRONG_BEND = {200.0: (96.0, 335.0)}
PRONG_FLANGE = ((100.0, 69.0, 313.0), (200.0, 83.0, 312.5), (300.0, 97.0, 312.5), (400.0, 111.0, 312.0), (430.0, 114.0, 312.0))
PRONG_LIP = ((25.0, 319.0, 324.2), (100.0, 326.8, 332.2), (200.0, 337.2, 342.8), (300.0, 347.2, 352.5), (400.0, 358.0, 363.2),
             (430.0, 359.5, 365.0))  # the raised lip along each prong's inner top edge (x 42.5 to 52): z, underside, top
PRONG_KEEL = (46.5, 52.0, 312.5)  # the strip under each prong's inner edge: x from, x to, underside (z 100 to 430)


def prong_rows() -> tuple[Row, ...]:
    xi = PRONG_INNER_X
    rows = []
    for z, yb, xo, ys, k, xs, yt in PRONG:
        bend = PRONG_BEND.get(z, (0.5 * (k[0] + xs), 0.5 * (k[1] + yt)))
        rows.append((z, ((xi, yb), (xo, yb), (xo, ys), k, bend, (xs, yt), (xi, yt))))
    return _rows(*rows)


def flange_rows() -> tuple[Row, ...]:
    outer = {r[0]: (r[2], r[1]) for r in PRONG}
    return _rows(*((z, ((x0, yf), (outer[z][0] - 3.0, yf), (outer[z][0], outer[z][1] + 0.5), (x0, outer[z][1] + 0.5)))
                   for z, x0, yf in PRONG_FLANGE))


def lip_rows() -> tuple[Row, ...]:
    return _rows(*((z, _rect(42.5, 52.0, y0, y1)) for z, y0, y1 in PRONG_LIP))


# --- the command section over the docking sphere ----------------------------------------------------------------------------
# z 595 to 690: the spine splits into two side beams and a centre box with a slot through it.
CMD_BEAM = _rows((597.0, ((81.0, 321.5), (166.0, 321.5), (166.0, 349.0), (128.5, 389.0), (80.5, 389.0))),
                 (600.0, ((81.0, 321.5), (166.0, 321.5), (166.0, 349.0), (128.5, 389.0), (80.5, 389.0))),
                 (620.0, ((75.0, 325.0), (152.0, 325.0), (152.0, 358.0), (121.5, 392.0), (73.0, 392.0))),
                 (680.0, ((51.0, 338.0), (109.5, 338.0), (109.5, 379.0), (99.5, 402.0), (50.5, 402.0))),
                 (692.0, ((51.0, 338.0), (109.5, 338.0), (109.5, 379.0), (99.5, 402.0), (50.5, 402.0))))
CMD_SLOT = 9.5  # the centre box's slot: half width
CMD_BOX = ((597.0, 59.5, 338.0, 344.5, 362.8, 371.0), (600.0, 59.5, 338.0, 344.5, 362.8, 371.0), (620.0, 73.5, 342.0, 348.5, 366.8, 375.0), (655.0, 73.5, 342.0, 348.5, 366.8, 375.0))
# z 688 to 997: the body over the sphere, a box with ledges widening aft into a six-sided block (the STL's).
CMD_BODY = _rows(
    (688.0, ((0.0, 404.0), (92.0, 404.0), (93.5, 386.0), (95.5, 368.0), (95.5, 350.0), (95.5, 342.0), (0.0, 342.0))),
    (750.0, ((0.0, 414.0), (85.0, 414.0), (88.5, 391.0), (97.0, 386.0), (97.0, 366.0), (87.5, 355.0), (0.0, 352.0))),
    (800.0, ((0.0, 422.0), (88.0, 422.0), (88.0, 401.0), (99.5, 400.0), (99.5, 373.0), (87.0, 368.0), (0.0, 362.0))),
    (850.0, ((0.0, 431.0), (89.0, 431.0), (122.5, 407.0), (130.0, 396.0), (126.0, 369.0), (110.5, 361.0), (0.0, 354.0))),
    (900.0, ((0.0, 440.0), (89.5, 440.0), (124.0, 415.0), (139.5, 401.0), (139.5, 363.0), (103.0, 344.0), (0.0, 339.0))),
    (950.0, ((0.0, 448.0), (90.0, 448.0), (154.0, 385.0), (162.0, 380.0), (153.0, 357.0), (95.5, 327.0), (0.0, 324.0))),
    (980.0, ((0.0, 454.0), (89.0, 454.0), (125.0, 404.0), (161.5, 354.0), (126.0, 335.0), (91.5, 317.0), (0.0, 315.0))),
    (997.0, ((0.0, 458.0), (88.5, 458.0), (164.5, 403.0), (164.5, 353.0), (130.0, 334.0), (96.5, 317.0), (0.0, 312.5))),
)
# z 997 to 1290: the pointed beam (flat top x +-88.5 at y 458, out to +-166 at y 403) over a keel and a strut, the gap between them
# open; the observation dome in a recess in its top (z 1058 to 1176), a groove along its top aft of z 1245.
BEAM_TOP, BEAM_TOP_X, BEAM_EDGE = 458.0, 88.5, (166.0, 403.0)
RECESS = ((1058.0, 69.0, 59.0), (1100.0, 61.0, 49.0), (1140.0, 53.0, 41.0), (1176.0, 47.5, 35.5))  # z, half width at top and floor
RECESS_FLOOR = 426.0
GROOVE = (37.0, 435.0)  # half width, floor
KEEL = ((997.0, 1131.0, 329.0), (1131.0, 1237.0, 352.0), (1237.0, 1290.0, 310.0))  # z from, z to, underside: x +-88 from y 361
KEEL_HALF, KEEL_TOP = 88.0, 361.0
STRUT = (14.0, 310.0, 352.0, 997.0, 1237.0)  # half width, underside, top, z from, z to
BEAM_RIB = ((0.0, 403.5), (166.5, 403.0), (153.0, 398.0), (0.0, 398.0))  # the ribs under the beam (the STL's): their section
BEAM_RIBS = (1012.0, 23.18, 12, 9.5)  # the first's front, the pitch, how many, how thick
# z 1284 to 1405: the beam's tail closing down onto the deck (the STL's): z, the top's half width at the groove's floor, the side's
# top and bottom corners, the underside's corner and the underside.
BEAM_TAIL = ((1284.0, 120.5, (166.0, 403.0), (166.0, 360.0), (120.0, 314.0), 314.0),
             (1290.0, 120.5, (166.0, 402.0), (166.0, 360.0), (120.0, 314.0), 314.0),
             (1310.0, 118.5, (159.0, 407.0), (159.0, 368.0), (115.0, 332.0), 332.0),
             (1330.0, 117.0, (144.5, 416.0), (144.5, 380.0), (110.0, 349.0), 349.0),
             (1360.0, 114.5, (128.0, 425.0), (128.0, 393.0), (105.0, 376.0), 376.0),
             (1405.0, 97.0, (97.0, 432.0), (97.0, 420.0), (97.0, 412.0), 411.5))
DOME = (1117.0, RECESS_FLOOR, (41.0, 27.0, 48.0))  # z, its base's height, semi-axes across, up, along
DOME_DISC = (32.0, 452.0, 464.0)  # the disc on the dome's top: radius, underside, top

# --- the dorsal spine aft of the command section ---------------------------------------------------------------------------
# The deck over the waist (z 1395 to 1797), a five-sided section: top, its chamfered corner, the side, the underside.
DECK = ((1395.0, 458.0, 88.0, 97.0, 444.0, 411.5), (1420.0, 458.0, 96.5, 106.0, 444.0, 412.0), (1450.0, 458.0, 110.0, 120.5, 445.0, 412.0),
        (1500.0, 458.8, 128.0, 140.5, 444.8, 412.8), (1550.0, 461.0, 120.5, 132.0, 447.0, 415.0), (1600.0, 463.2, 112.5, 123.5, 450.0, 417.5),
        (1700.0, 468.2, 97.0, 106.5, 454.2, 422.0), (1750.0, 471.0, 89.0, 98.0, 456.8, 424.5), (1797.0, 472.2, 84.5, 92.5, 458.8, 426.0))
BASE = (472.2, 84.5, 92.5, 458.8, 426.0)  # the spine over the bands: top, its half width, the side's half width, chamfer foot, underside
# The ramp up the spine's middle (kept to +-33 so I6's interceptor turns clear of it), its top rising from z 1405 to 1738, a stepped
# tip behind it.
RAMP_HALF = 33.0
RAMP = ((1405.0, 487.0), (1738.0, 557.8))
RAMP_TIP = ((1738.0, 1772.0, 33.0, 518.0), (1738.0, 1765.0, 23.0, 542.0), (1740.0, 1752.0, 9.0, 569.0))  # z from, z to, half width, top
RAIL = (55.5, 83.5, 472.0, 500.0)  # the short rails on the spine's top: x from, x to, underside, top
RAILS_Z = ((1782.0, 1800.0), (5354.0, 5372.0), (5405.0, 5425.0), (5450.0, 5470.0), (5495.0, 5515.0), (5545.0, 5560.0))
# The radiators: a core +-92.5 to y 542 with a diamond wing each side; fins every FIN_PITCH_M.
RADIATOR_Z = ((1814.0, 2091.0), (5063.0, 5340.0))
RADIATOR = ((0.0, 542.2), (92.5, 542.2), (122.5, 472.0), (125.0, 465.0), (98.0, 447.0), (92.5, 446.0), (92.5, 470.0), (0.0, 470.0))
FIN = ((0.0, 553.0), (97.5, 553.0), (132.0, 472.0), (135.5, 463.0), (128.0, 458.0), (101.0, 439.5), (92.5, 439.0), (92.5, 470.0),
       (0.0, 470.0))
FIN_PITCH_M = 23.2
FINS = 12
FIN_THICK_M = 9.5
FIN_FIRST = (1819.0, 5073.0)
# The rib along the spine's top and the two pipes on it (z 2095 to 2470, mirrored aft).
RIB = (12.0, 470.0, ((2095.0, 485.0), (2400.0, 505.0), (2470.0, 509.0)))  # half width, underside, (z, top)
PIPE = (51.5, 505.5, 23.5, 2128.0, 2312.0)  # x, y, radius, z from, z to
PIPE_SIDES = 12
# The green zone's sections (z 2342 to 2834, mirrored aft): a lower slab with sloped side plates (skirts) under a tower, the turret
# block (cap and body, L10 on the cap) and the fins between. The lower slab: z, top, top's half width, the slab's outer bottom corner,
# the skirt's outer and inner bottom corners (at y 357), the skirt's top inside and the slab's underside.
SKIRT_Y = 357.0
LOWER = ((2342.0, 450.0, 105.5, (115.5, 421.5), 115.5, 115.0, 114.5, 421.5),
         (2360.0, 445.0, 110.0, (121.0, 408.5), 121.0, 120.5, 120.0, 408.5),
         (2400.0, 435.0, 119.5, (132.0, 390.0), 132.0, 131.5, 131.0, 390.0),
         (2450.0, 422.0, 131.5, (145.0, 367.0), 145.0, 144.5, 144.0, 367.0),
         (2500.0, 417.0, 137.0, (150.0, 361.0), 151.0, 104.0, 94.0, 361.0),
         (2550.0, 417.0, 137.0, (148.0, 370.0), 151.0, 125.5, 93.0, 370.0),
         (2600.0, 417.0, 137.0, (145.5, 379.0), 151.0, 147.0, 93.0, 378.5),
         (2650.0, 417.0, 125.5, (134.5, 380.0), 139.5, 138.0, 86.0, 379.5),
         (2700.0, 417.0, 112.5, (121.0, 380.0), 126.5, 126.0, 77.0, 379.5),
         (2750.0, 417.0, 99.0, (108.0, 380.0), 113.5, 113.0, 68.5, 379.5),
         (2800.0, 417.0, 86.0, (95.0, 380.0), 100.0, 98.5, 59.5, 379.5),
         (2834.0, 417.0, 81.0, (90.0, 380.0), 95.5, 94.5, 56.5, 379.5))
# The lower slab's end aft, clear of the aft band's rim (its teeth reach r 414 from z 4792): z, top, top's half width, bottom.
LOWER_AFT_END = ((4740.0, 431.0, 124.0, (136.0, 384.0)), (4770.0, 445.0, 110.0, (121.0, 405.0)), (4784.0, 450.0, 105.5, (115.5, 419.5)))
TOWER = (60.0, ((2342.0, 482.0, 448.0), (2400.0, 494.0, 433.0), (2450.0, 504.0, 415.0), (2566.0, 527.0, 415.0)))  # half width, (z, top, bottom)
FWD_BLOCK = (92.5, 430.0, 479.0, 2350.0, 2422.0)  # half width, underside, top, z from, z to
GZ_FINS = ((2432.0, 2444.0, 494.0), (2468.0, 2480.0, 496.0), (2506.0, 2516.0, 503.0), (2542.0, 2552.0, 511.0))  # z from, z to, top (x +-92.5)
CAP = (46.5, 536.8, (2566.0, 2686.0))  # half width, top, z from, z to (D75's L10 and I7 on it)
BODY = ((0.0, 528.0), (103.0, 528.0), (115.5, 417.0), (0.0, 417.0))  # the turret block under the cap, z 2560 to 2686
BODY_Z = (2560.0, 2686.0)
AFT_TOWER = (60.0, 415.0, ((2686.0, 550.8), (2786.0, 550.8), (2796.0, 418.0)))  # half width, underside, (z, top)
# The cargo modules (the STL's): a six-sided body between two end frames, standing on the lower slab.
CARGO_LENGTH = 213.0
CARGO_FRAME_M = 8.0
CARGO_BODY = ((0.0, 560.0), (90.0, 560.0), (104.0, 549.0), (163.0, 437.0), (168.5, 421.0), (165.5, 417.0), (126.5, 380.0), (95.0, 357.0),
              (92.0, 370.0), (88.0, 417.0), (77.0, 437.0), (0.0, 437.0))
CARGO_END = ((0.0, 565.0), (94.5, 565.0), (110.0, 551.0), (117.5, 538.0), (161.5, 455.0), (171.5, 436.0), (176.0, 424.0), (174.0, 417.0),
             (136.0, 380.0), (110.0, 356.0), (88.5, 356.0), (88.5, 361.0), (77.0, 431.5), (0.0, 431.5))
# The hub end: the spine's last stretch drops onto the hub (z 5400 to 5562), a body slopes into it (5562 to 5788), rails on top, a
# narrow tail down the cone.
HUB_LOWER = (83.5, ((5410.0, 419.5), (5480.0, 403.5), (5530.0, 391.5), (5562.0, 389.0)))  # half width, (z, underside); top 430
HUB_BODY = ((5562.0, 92.5, (110.0, 389.0), (124.0, 347.0)), (5600.0, 106.5, (128.0, 392.0), (151.0, 312.0)),
            (5650.0, 106.5, (120.0, 410.0), (136.0, 330.0)), (5700.0, 107.0, (117.0, 400.0), (127.5, 322.0)),
            (5788.0, 107.0, (117.0, 400.0), (127.5, 322.0)))  # z, top's half width (y 472), a side point, the foot
HUB_BODY_TOP = 472.0
HUB_RAILS = (60.0, 97.0, 472.0, 486.0, 5610.0, 5745.0)  # x from, x to, underside, top, z from, z to (L12 and I9 between them)
TAIL = (33.5, 30.0, ((5786.0, 439.0, 322.0), (5800.0, 438.0, 318.0), (5900.0, 384.0, 219.0), (6000.0, 330.0, 185.0),
                     (6100.0, 278.0, 155.0), (6188.0, 232.0, 128.0)))  # half width, the top's half width, (z, top, underside)


def _lerp(points: Sequence[tuple[float, float]], z: float) -> float:
    zs, vs = zip(*points, strict=True)
    return float(np.interp(z, zs, vs))


def lower_profile(top: float, wt: float, corner: tuple[float, float], xo: float, xs: float, xi: float, bottom: float) -> Profile:
    wb, yb = corner
    return ((0.0, top), (wt, top), (wb, yb), (xo, SKIRT_Y if xi < wb - 1.0 else yb - 0.5), (xs, SKIRT_Y if xi < wb - 1.0 else yb - 0.5),
            (xi, bottom), (0.0, bottom))


def lower_rows() -> tuple[tuple[Row, ...], tuple[Row, ...]]:
    """The lower slab before the cargo modules and after them (its end aft kept clear of the aft band's rim)."""
    front = tuple((z, lower_profile(t, wt, c, xo, xs, xi, b)) for z, t, wt, c, xo, xs, xi, b in LOWER)
    mid = (front[-1], (2.0 * MIRROR_Z - front[-1][0], front[-1][1]))
    aft = [r for r in mirrored(front) if r[0] <= 2.0 * MIRROR_Z - 2450.0 + 1e-6]
    for z, t, wt, (wb, yb) in LOWER_AFT_END:
        aft.append((z, lower_profile(t, wt, (wb, yb), wb, wb - 0.5, wb - 1.0, yb)))
    return tuple(front[:-1]) + mid, tuple(aft)


def _green_zone_front() -> list[Member]:
    """The green zone's members before the cargo modules (the aft ones mirror them)."""
    hw, rows = TOWER
    out = [Member("tower", "spine", _rows(*((z, _box(hw, b, t)) for z, t, b in rows))),
           Member("fwd_block", "spine", _rows((FWD_BLOCK[3], _box(FWD_BLOCK[0], FWD_BLOCK[1], FWD_BLOCK[2])),
                                              (FWD_BLOCK[4], _box(FWD_BLOCK[0], FWD_BLOCK[1], FWD_BLOCK[2])))),
           Member("cap", "spine", _rows((CAP[2][0], _box(CAP[0], 520.0, CAP[1])), (CAP[2][1], _box(CAP[0], 520.0, CAP[1])))),
           Member("body", "spine", _rows((BODY_Z[0], BODY), (BODY_Z[1], BODY))),
           Member("aft_tower", "spine", _rows(*((z, _box(AFT_TOWER[0], AFT_TOWER[1], t)) for z, t in AFT_TOWER[2])))]
    out += [Member("gz_fin", "radiators", _rows((z0, _box(92.5, 417.0, top)), (z1, _box(92.5, 417.0, top))), collide=False)
            for z0, z1, top in GZ_FINS]
    out.append(Member("gz_fin", "proxy", _rows((GZ_FINS[0][0], _box(92.5, 417.0, GZ_FINS[0][2])),
                                               (GZ_FINS[-1][1], _box(92.5, 417.0, GZ_FINS[-1][2])))))
    hw, under, tops = RIB
    out.append(Member("rib", "spine", _rows(*((z, _box(hw, under, t)) for z, t in tops))))
    x, y, r, z0, z1 = PIPE
    a = np.linspace(0.0, 2.0 * np.pi, PIPE_SIDES, endpoint=False)
    ring = tuple((float(x + r * np.cos(t)), float(y + r * np.sin(t))) for t in a)
    out.append(Member("pipe", "spine", _rows((z0, ring), (z1, ring)), side=True))
    for zs in ((z0, z0 + 8.0), (z1 - 8.0, z1)):  # the pipes' saddles
        saddle = _rect(x - 22.0, x + 22.0, BASE[0] - 1.0, y - 0.6 * r)
        out.append(Member("pipe_saddle", "spine", _rows((zs[0], saddle), (zs[1], saddle)), side=True, collide=False))
    return out


def members() -> list[Member]:
    """Every lofted solid of the bow, the command section and the dorsal spine."""
    x0, x1, yk = PRONG_KEEL
    out = [Member("prong", "bow", prong_rows(), side=True), Member("prong_trim", "bow", flange_rows(), side=True, collide=False),
           Member("prong_trim", "bow", lip_rows(), side=True, collide=False),
           Member("prong_trim", "bow", _rows((100.0, _rect(x0, x1, yk, 315.5)), (430.0, _rect(x0, x1, yk, 315.5))), side=True,
                  collide=False),
           Member("cmd_beam", "spine", CMD_BEAM, side=True)]
    box = [(z, w, b0, b1, t0, t1) for z, w, b0, b1, t0, t1 in CMD_BOX]
    out += [Member("cmd_box", "spine", _rows(*((z, _box(w, t0, t1)) for z, w, _, _, t0, t1 in box)), collide=False),
            Member("cmd_box", "spine", _rows(*((z, _box(w, b0, b1)) for z, w, b0, b1, _, _ in box)), collide=False),
            Member("cmd_box", "spine", _rows(*((z, _rect(CMD_SLOT, w, b1, t0)) for z, w, _, b1, t0, _ in box)), side=True, collide=False),
            Member("cmd_box", "proxy", _rows(*((z, _box(w, b0, t1)) for z, w, b0, _, _, t1 in box))),
            Member("cmd_body", "spine", CMD_BODY)]
    # The beam: whole before and after the recess, its lower part and the recess's walls along it.
    full = ((0.0, BEAM_TOP), (BEAM_TOP_X, BEAM_TOP), BEAM_EDGE, (0.0, BEAM_EDGE[1]))
    out += [Member("beam", "spine", _rows((997.0, full), (RECESS[0][0], full))),
            Member("beam", "spine", _rows((RECESS[-1][0], full), (1245.0, full)))]
    floor_x = beam_x(RECESS_FLOOR)
    lower = ((0.0, RECESS_FLOOR), (floor_x, RECESS_FLOOR), BEAM_EDGE, (0.0, BEAM_EDGE[1]))
    out.append(Member("beam", "spine", _rows((RECESS[0][0], lower), (RECESS[-1][0], lower))))
    out.append(Member("beam_recess", "spine", _rows(*((z, ((wf, RECESS_FLOOR), (floor_x, RECESS_FLOOR), (BEAM_TOP_X, BEAM_TOP), (wt, BEAM_TOP)))
                                                     for z, wt, wf in RECESS)), side=True))
    gw, gy = GROOVE
    groove_x = beam_x(gy)
    out.append(Member("beam", "spine", _rows((1245.0, ((0.0, gy), (groove_x, gy), BEAM_EDGE, (0.0, BEAM_EDGE[1]))),
                                             (1284.0, ((0.0, gy), (groove_x, gy), BEAM_EDGE, (0.0, BEAM_EDGE[1]))))))
    out.append(Member("beam_tail", "spine", _rows(*((z, ((0.0, gy), (w, gy), a, b, c, (0.0, u))) for z, w, a, b, c, u in BEAM_TAIL))))
    out.append(Member("beam_groove", "spine", _rows((1245.0, ((gw, gy), (groove_x, gy), (BEAM_TOP_X, BEAM_TOP), (gw, BEAM_TOP))),
                                                    *((z, ((gw, gy), (w, gy), (min(BEAM_TOP_X, w - 0.5), BEAM_TOP), (gw, BEAM_TOP)))
                                                      for z, w, *_ in BEAM_TAIL)), side=True))
    out += [Member("keel", "spine", _rows((z0, _box(KEEL_HALF, u, KEEL_TOP)), (z1, _box(KEEL_HALF, u, KEEL_TOP)))) for z0, z1, u in KEEL]
    out.append(Member("keel", "spine", _rows((1258.0, ((0.0, 352.0), (134.5, 352.0), (143.5, 347.0), (143.5, 334.0), (134.5, 329.0), (0.0, 329.0))),
                                             (1288.0, ((0.0, 352.0), (134.5, 352.0), (143.5, 347.0), (143.5, 334.0), (134.5, 329.0), (0.0, 329.0))))))
    z0, pitch, count, thick = BEAM_RIBS
    out += [Member("beam_rib", "spine", _rows((z0 + k * pitch, BEAM_RIB), (z0 + k * pitch + thick, BEAM_RIB)), collide=False)
            for k in range(count)]
    sw, su, st_, sz0, sz1 = STRUT
    out.append(Member("strut", "spine", _rows((sz0, _box(sw, su, st_)), (sz1, _box(sw, su, st_)))))
    # The deck, the ramp and the spine over the bands to the hub.
    deck = [(z, ((0.0, t), (xc, t), (xw, yc), (xw, u), (0.0, u))) for z, t, xc, xw, yc, u in DECK]
    out.append(Member("deck", "spine", _rows(*deck)))
    top, xc, xw, yc, u = BASE
    base = ((0.0, top), (xc, top), (xw, yc), (xw, u), (0.0, u))
    out.append(Member("base", "spine", _rows((DECK[-1][0], base), (2422.0, base))))
    out.append(Member("base", "spine", _rows((2.0 * MIRROR_Z - 2422.0, base), (HUB_BODY[0][0], base))))
    out.append(Member("ramp", "spine", _rows(*((z, _box(RAMP_HALF, 455.0, t)) for z, t in RAMP))))
    out += [Member("ramp", "spine", _rows((z0, _box(w, 455.0, t)), (z1, _box(w, 455.0, t)))) for z0, z1, w, t in RAMP_TIP]
    x0, x1, y0, y1 = RAIL
    out += [Member("rail", "spine", _rows((z0, _rect(x0, x1, y0, y1)), (z1, _rect(x0, x1, y0, y1))), side=True, collide=False)
            for z0, z1 in RAILS_Z]
    for z0, z1 in (RAILS_Z[0], (RAILS_Z[1][0], RAILS_Z[-1][1])):  # their collision: the forward rail, the aft rails as one run
        out.append(Member("rail", "proxy", _rows((z0, _rect(x0, x1, y0, y1)), (z1, _rect(x0, x1, y0, y1))), side=True))
    for (z0, z1), first in zip(RADIATOR_Z, FIN_FIRST, strict=True):
        out.append(Member("radiator", "radiators", _rows((z0, RADIATOR), (z1, RADIATOR))))
        out += [Member("radiator_fin", "radiators", _rows((first + k * FIN_PITCH_M, FIN), (first + k * FIN_PITCH_M + FIN_THICK_M, FIN)),
                       collide=False) for k in range(FINS)]
    # The green zones and the cargo modules between them.
    front, aft = lower_rows()
    out += [Member("lower", "spine", front), Member("lower", "spine", aft)]
    for m in _green_zone_front():
        out += [m, Member(m.name, m.part, mirrored(m.rows), m.side, m.collide)]
    for z in CARGO_Z:
        body = _rows((z + CARGO_FRAME_M, CARGO_BODY), (z + CARGO_LENGTH - CARGO_FRAME_M, CARGO_BODY))
        out.append(Member("module", "cargo", body))
        out += [Member("module_frame", "cargo", _rows((a, CARGO_END), (a + CARGO_FRAME_M, CARGO_END)), collide=False)
                for a in (z, z + CARGO_LENGTH - CARGO_FRAME_M)]
    # The hub end.
    hw, rows = HUB_LOWER
    out.append(Member("hub_lower", "spine", _rows(*((z, _box(hw, b, 430.0)) for z, b in rows))))
    out.append(Member("hub_body", "spine", _rows(*((z, ((0.0, HUB_BODY_TOP), (w, HUB_BODY_TOP), m, f, (0.0, f[1]))) for z, w, m, f in HUB_BODY))))
    x0, x1, y0, y1, z0, z1 = HUB_RAILS
    out.append(Member("rail", "spine", _rows((z0, _rect(x0, x1, y0, y1)), (z1, _rect(x0, x1, y0, y1))), side=True))
    hw, tw, rows = TAIL
    out.append(Member("tail", "spine", _rows(*((z, ((0.0, t), (tw, t), (hw, t - 4.0), (hw, u), (0.0, u))) for z, t, u in rows))))
    return out


CARGO_Z = (2834.0, 3089.0, 3344.0, 3598.0, 3853.0, 4108.0)  # each module's front (the STL's)


def beam_x(y: float) -> float:
    """The beam's half width at height ``y`` (between its top and its outer edge)."""
    (xt, yt), (xe, ye) = (BEAM_TOP_X, BEAM_TOP), BEAM_EDGE
    return float(xt + (yt - y) * (xe - xt) / (yt - ye))


# --- the sections as polygons ----------------------------------------------------------------------------------------------
def polygon(profile: Profile, side: bool) -> np.ndarray:
    """A section's whole polygon (x, y), counter-clockwise: a side piece as it is, a right half joined to its mirror."""
    p = np.asarray(profile, dtype=float)
    if not side:
        p = np.concatenate([p, p[-2:0:-1] * [-1.0, 1.0]])
    area = 0.5 * float(np.sum(p[:, 0] * np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1) * p[:, 1]))
    return p if area > 0.0 else p[::-1]


def section_at(rows: Sequence[Row], z: float) -> Profile:
    """A member's section at ``z``, each corner between its rows."""
    zs = [r[0] for r in rows]
    k = int(np.clip(np.searchsorted(zs, z) - 1, 0, len(rows) - 2))
    (za, pa), (zb, pb) = rows[k], rows[k + 1]
    t = 0.0 if zb - za < 1e-9 else float(np.clip((z - za) / (zb - za), 0.0, 1.0))
    return tuple((xa + t * (xb - xa), ya + t * (yb - ya)) for (xa, ya), (xb, yb) in zip(pa, pb, strict=True))


def rings(member: Member, z_values: Sequence[float] | None = None) -> list[tuple[float, np.ndarray]]:
    """The member's rings (z, polygon), starboard's for a side piece."""
    zs = [r[0] for r in member.rows] if z_values is None else list(z_values)
    return [(z, polygon(section_at(member.rows, z), member.side)) for z in zs]


# --- meshes -----------------------------------------------------------------------------------------------------------------
def _quad_uv(q: np.ndarray) -> np.ndarray:
    """A quad's corners in its own plane (metres), the longest edge along u."""
    edges = np.roll(q, -1, axis=0) - q
    k = int(np.argmax(np.linalg.norm(edges, axis=1)))
    e1 = edges[k] / np.linalg.norm(edges[k])
    normal = np.cross(q[2] - q[0], q[3] - q[1])
    normal = normal / (np.linalg.norm(normal) or 1.0)
    e2 = np.cross(normal, e1)
    d = q - q[0]
    return np.stack([d @ e1, d @ e2], axis=1)


def ear_clip(poly: np.ndarray) -> list[tuple[int, int, int]]:
    """A simple counter-clockwise polygon's triangles (indices), by ear clipping; collinear and repeated corners are skipped."""
    idx = [i for i in range(len(poly)) if np.linalg.norm(poly[i] - poly[i - 1]) > 1e-9]
    out = []

    def cross(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
        return float((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))

    guard = 0
    while len(idx) > 3 and guard < 10_000:
        guard += 1
        n = len(idx)
        clipped = False
        for k in range(n):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % n]
            a, b, c = poly[i0], poly[i1], poly[i2]
            turn = cross(a, b, c)
            if abs(turn) < 1e-9:  # a straight corner: drop it
                idx.pop(k)
                clipped = True
                break
            if turn < 0.0:
                continue
            others = [poly[j] for j in idx if j not in (i0, i1, i2)]
            if any(cross(a, b, p) > 1e-9 and cross(b, c, p) > 1e-9 and cross(c, a, p) > 1e-9 for p in others):
                continue
            out.append((i0, i1, i2))
            idx.pop(k)
            clipped = True
            break
        if not clipped:
            break
    if len(idx) == 3 and abs(cross(poly[idx[0]], poly[idx[1]], poly[idx[2]])) > 1e-9:
        out.append((idx[0], idx[1], idx[2]))
    return out


def loft_mesh(ring_list: Sequence[tuple[float, np.ndarray]], material: Material) -> Mesh:
    """A closed solid through counter-clockwise rings along +z: a flat chart per side face, each end one chart."""
    verts, faces, uvs, charts = [], [], [], []
    chart = 0
    for (za, a), (zb, b) in zip(ring_list[:-1], ring_list[1:], strict=True):
        n = len(a)
        for i in range(n):
            j = (i + 1) % n
            q = np.array([[*a[i], za], [*a[j], za], [*b[j], zb], [*b[i], zb]])
            if np.linalg.norm(np.cross(q[2] - q[0], q[3] - q[1])) < 1e-9:
                continue
            base = len(verts) * 4
            verts.append(q)
            uv = _quad_uv(q)
            for tri in ((0, 1, 2), (0, 2, 3)):
                if np.linalg.norm(np.cross(q[tri[1]] - q[tri[0]], q[tri[2]] - q[tri[0]])) < 1e-9:
                    continue
                faces.append([base + t for t in tri])
                uvs.append(uv[list(tri)])
                charts.append(chart)
            chart += 1
    flat = [np.asarray(v) for v in verts]
    cap_verts = []
    for (z, ring), forward in ((ring_list[0], False), (ring_list[-1], True)):
        start = 4 * len(flat) + sum(len(c) for c in cap_verts)
        pts = np.column_stack([ring, np.full(len(ring), z)])
        cap_verts.append(pts)
        for i0, i1, i2 in ear_clip(ring):
            tri = (i0, i1, i2) if forward else (i0, i2, i1)
            faces.append([start + t for t in tri])
            uvs.append(ring[list(tri)])
            charts.append(chart)
        chart += 1
    all_verts = np.concatenate(flat + cap_verts) if flat else np.concatenate(cap_verts)
    n = len(faces)
    return Mesh(all_verts, np.array(faces), np.zeros(n, dtype=np.int64), (material,), np.array(charts), np.array(uvs))


def member_mesh(member: Member, material: Material) -> Mesh:
    """A member's solid, both sides for a side piece."""
    starboard = loft_mesh(rings(member), material)
    return Mesh.concatenate([starboard, starboard.mirrored("x")]) if member.side else starboard


def dome_mesh(material: Material, lamp: Material) -> Mesh:
    """The observation dome in the beam's recess: half an ellipsoid, the disc on its top and a lamp on that."""
    from ..core.geometry import lathe, rotation_x  # noqa: PLC0415

    z, base, (a, b, c) = DOME
    profile = [(0.0, 1.0)] + [(float(np.sin(t)), float(np.cos(t))) for t in np.linspace(0.15, 0.5 * np.pi, 8)]
    half = lathe(profile, 32, material).transformed(rotation_x(-0.5 * np.pi))  # its axis up
    half = half.transformed(np.diag([a, b, c]), (0.0, base, z))
    r, y0, y1 = DOME_DISC
    disc = lathe([(y0, 0.0), (y0, r), (y1, r), (y1, 0.0)], 24, material, creases=(1, 2)).transformed(rotation_x(-0.5 * np.pi), (0.0, 0.0, z))
    light = box_mesh((-4.0, y1, z - 4.0), (4.0, y1 + 5.0, z + 4.0), lamp)
    return Mesh.concatenate([half, disc, light])


def box_mesh(lo: Sequence[float], hi: Sequence[float], material: Material) -> Mesh:
    from ..core.geometry import box  # noqa: PLC0415

    lo_, hi_ = np.asarray(lo, dtype=float), np.asarray(hi, dtype=float)
    return box(hi_ - lo_, material, 0.5 * (lo_ + hi_))


def shapes(mats: dict[str, Material]) -> dict[str, Mesh]:
    """Each part's solids as one mesh: ``bow`` (the prongs), ``spine``, ``radiators``, ``cargo``."""
    material = {"bow": mats["spine"], "spine": mats["spine"], "radiators": mats["machinery"], "cargo": mats["cargo"]}
    out: dict[str, list[Mesh]] = {k: [] for k in material}
    for m in members():
        if m.part != "proxy":  # collision only
            out[m.part].append(member_mesh(m, material[m.part]))
    return {k: Mesh.concatenate(v) for k, v in out.items()}


# --- collision -------------------------------------------------------------------------------------------------------------
def collision_pieces(planes: Sequence[float], tol: float = 8.0, max_rows: int = 8) -> list[tuple[str, np.ndarray]]:
    """Each member's convex pieces: the hull of a run of its sections, cut at the section planes; a run whose sections stay within
    ``tol`` of the straight loft between its ends is one piece."""
    out = []
    for m in members():
        if not m.collide:
            continue
        z0, z1 = m.rows[0][0], m.rows[-1][0]
        zs = sorted({r[0] for r in m.rows} | {p for p in planes if z0 + 1e-6 < p < z1 - 1e-6})
        cut = set(p for p in planes if z0 + 1e-6 < p < z1 - 1e-6)
        secs = [np.asarray(section_at(m.rows, z)) for z in zs]
        a = 0
        while a < len(zs) - 1:
            b = a + 1
            while (b + 1 < len(zs) and b + 1 - a < max_rows and zs[b] not in cut
                   and _straight(zs[a: b + 2], secs[a: b + 2], tol)):
                b += 1
            polys = [polygon(tuple(map(tuple, secs[k])), m.side) for k in range(a, b + 1)]
            pts = np.concatenate([np.column_stack([p, np.full(len(p), zs[k])]) for p, k in zip(polys, range(a, b + 1), strict=True)])
            out.append((m.name, pts))
            if m.side:
                out.append((m.name, pts * [-1.0, 1.0, 1.0]))
            a = b
    return out


def _straight(zs: Sequence[float], secs: Sequence[np.ndarray], tol: float) -> bool:
    t = (np.asarray(zs) - zs[0]) / (zs[-1] - zs[0])
    line = secs[0][None] + t[:, None, None] * (secs[-1] - secs[0])[None]
    return bool(np.abs(np.asarray(secs) - line).max() <= tol)


def dome_collision() -> np.ndarray:
    z, base, (a, _, c) = DOME
    r, _, top = DOME_DISC
    return np.array([[x, y, zz] for x in (-a, a) for y in (base, top + 5.0) for zz in (z - c, z + c)])


# --- what follows the spine -----------------------------------------------------------------------------------------------
def top_at(z: float, x: float = 0.0, parts: Sequence[str] = ("spine",)) -> float:
    """The highest point of the spine's members over (x, z), or -inf where none stands."""
    best = -np.inf
    for m in members():
        if m.part not in parts or not (m.rows[0][0] <= z <= m.rows[-1][0]):
            continue
        for sx in ((1.0, -1.0) if m.side else (1.0,)):
            p = polygon(section_at(m.rows, z), m.side) * [sx, 1.0]
            for (xa, ya), (xb, yb) in zip(p, np.roll(p, -1, axis=0), strict=True):
                if min(xa, xb) - 1e-9 <= x <= max(xa, xb) + 1e-9 and abs(xb - xa) > 1e-9:
                    best = max(best, ya + (x - xa) * (yb - ya) / (xb - xa))
    return float(best)


def prong_edge(z: float) -> tuple[float, float]:
    """A prong's outer lower edge at ``z``: its x and the underside's y."""
    zs = [r[0] for r in PRONG]
    return float(np.interp(z, zs, [r[2] for r in PRONG])), float(np.interp(z, zs, [r[1] for r in PRONG]))


__all__ = ["CARGO_Z", "DOME", "Member", "beam_x", "collision_pieces", "dome_mesh", "loft_mesh", "member_mesh", "members", "polygon",
           "prong_edge", "rings", "section_at", "shapes", "top_at"]
