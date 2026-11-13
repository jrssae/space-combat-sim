"""The Babylon 5 station's shapes (M7-T04), from the measurements in docs/assets-station.md: every number is metres in the station
frame read off the reference model, x to starboard, y up, z aft from the bow tip (0 to 8 000), x and y about the drum's axis.

Two sets: :func:`drum_shapes` (what turns: the docking sphere and its main docking bay (``station_detail.py``), the waist, the four Cobra arms, the forward body, the
rings and bands, the green zone) and :func:`frame_shapes` (what stands still: the bow spike, the aperture's ring, the dorsal spine
with its radiators, cargo modules and dome, the hub and cone, the delta fins, the vane booms and vanes, the truss, the torus disc,
the shaft and the reactor). Each shape is a named mesh; the generator gives it its surface layout, paint and windows
(``station_layouts.py``) and moves it into its piece's frame. The launch doors' clamps and close-up faces are near-only props
(``station_props.py``, M7-T19).
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Material, Mesh, box, lathe, planar_uv, polygon_area_2d, prism, rotation_x, rotation_y, rotation_z, unit

Section = tuple[float, float, float, float, float]  # z, x0, x1, y0, y1 of an axis-aligned slab's cross-section

# --- the drum --------------------------------------------------------------------------------------------------------
DOOR_Z = 478.0
DOOR_R = 126.0
# The main docking bay's door plate closes the sphere's front opening (``station_detail.py``, M7-T05; it turns with the drum).
SPHERE_PROFILE = [(DOOR_Z, DOOR_R), (558.0, DOOR_R), (562.0, 150.0), (575.0, 178.0), (600.0, 205.0), (640.0, 236.0),
                  (700.0, 262.0), (760.0, 275.0), (800.0, 277.0), (860.0, 271.0), (900.0, 262.0), (935.0, 248.0), (945.0, 196.0)]
WAIST_R = 188.0
WAIST_CORE_R = 135.0
BODY_PROFILE = [(945.0, WAIST_R), (1000.0, WAIST_R), (1020.0, WAIST_CORE_R), (1300.0, WAIST_CORE_R), (1310.0, WAIST_R), (1325.0, WAIST_R), (1332.0, 210.0), (1340.0, 272.0), (1400.0, 303.0), (1460.0, 322.0),
                (1540.0, 329.0), (1620.0, 318.0), (1680.0, 305.0), (1692.0, 330.0)]
RING_Z = (1692.0, 1790.0)
RING_R = 362.0
BAND_R = 417.0
FWD_BAND_PROFILE = [(1692.0, 330.0), (1700.0, RING_R), (1786.0, RING_R), (1790.0, 400.0), (1800.0, BAND_R), (2290.0, BAND_R),
                    (2340.0, 385.0), (2348.0, 330.0)]
GREEN_R = 334.0
GREEN_BAND = (3340.0, 3800.0, 346.5)
GREEN_PROFILE = [(2348.0, GREEN_R), (3330.0, GREEN_R), (3340.0, GREEN_BAND[2]), (3800.0, GREEN_BAND[2]), (3810.0, GREEN_R),
                 (4782.0, GREEN_R)]
AFT_BAND_PROFILE = [(4782.0, GREEN_R), (4790.0, 352.0), (4840.0, BAND_R), (5400.0, BAND_R), (5440.0, 382.0), (5458.0, 330.0),
                    (5464.0, 292.0), (5500.0, 292.0), (5500.0, 0.0)]
DRUM_Z = (DOOR_Z, 5500.0)
ARM_ANGLES_DEG = (90.0, 0.0, 270.0, 180.0)  # top, starboard, bottom, port: the angle from +x toward +y
# The Cobra arm's head as it stands on top of the drum: z, half width, inner and outer radius.
# The head is a box with a flat top (the circular clamped hatch on it), then a ribbed neck tapering to the hatch section
# (references/cobra bay references/cobra arm untextured model.jpg).
# The head and neck (M7-T21, off the STL's sections): one chamfered loft from behind the fork's posts to the root, its flat top
# peaking where the circular hatch sits; each row (z, half width, underside, top, chamfer across, chamfer down). The underside lies
# inside the docking sphere. D75's light turrets keep the posts' tops, its interceptors stand on the hatch's cap at r 324.
ARM_NECK = ((735.0, 60.0, 232.0, 298.0, 30.0, 16.0), (760.0, 72.0, 235.0, 311.0, 35.0, 27.0), (800.0, 80.0, 235.0, 314.0, 50.0, 25.0),
            (840.0, 80.0, 235.0, 314.0, 49.0, 25.5), (880.0, 75.0, 240.0, 304.0, 50.0, 26.0), (900.0, 62.0, 246.0, 290.0, 34.0, 36.0),
            (960.0, 58.8, 220.0, 268.0, 32.4, 27.7), (1000.0, 47.2, 202.8, 240.5, 23.1, 24.5))
HATCH_CAP = (10.0, 323.5)  # the hatch's raised cap: its radius and top (the STL's)
# The arm's outline along its length, for what follows its edges (trim, ribs).
ARM_HEAD = [row[:4] for row in ARM_NECK]
ARM_TOP_HATCH = (800.0, 24.0, 30.0)  # the circular hatch on the head's top: z of its middle, inner and outer radius
ARM_RIBS = (906.0, 984.0, 9)  # the neck's ribs on both flanks: z from, z to, how many
ARM_HATCH = (1000.0, 1300.0, 47.2, 202.8, 240.5)  # z from, z to, half width, underside and top of the root section (the STL's)
# M7-T09's hangar (b5_interior) is laid out on T04's seven 64 x 28 m doors; T20 refits it to the launch doors below and drops
# these four names.
COBRA_DOORS = 7
DOOR_HALF = (32.0, 14.0)  # half across, half along
DOOR_ROW = (1020.0, 1290.0)  # where T04's row of doors ran along the arm
DOOR_DEPTH = 4.0  # the deck stands this far above the doors
# The root's section (M7-T21, read off the STL): a flat top between two creases, chamfers down to a short bevel and vertical sides,
# a notch in each side near the bottom, an underside rising to a flat middle (a shallow V). Half of it, from the top's middle round
# to the underside's middle (x, r).
ROOT_HALF = ((0.0, 240.5), (24.1, 240.5), (45.8, 216.0), (47.2, 214.5), (47.2, 206.5), (41.3, 206.5), (41.3, 202.8), (47.2, 202.8),
             (47.2, 196.2), (24.1, 202.8), (0.0, 202.8))
ARM_CHAMFER = 23.1 / 47.2  # the taper aft of the root keeps the creases' share
# The launch doors (M7-T05, M7-T21: the maintainer's untextured arm model and the STL's door shafts): six to an arm, each taking one
# Starfury (15.4 m across its claws, 9.8 m long, its span across the arm) with about 2.3 m to spare each side, on the root section's
# flat top between its creases, at the STL's 23 m pitch from just aft of the ribbed neck; a launch hall under them.
LAUNCH_DOORS = 6
LAUNCH_DOOR_HALF = (10.0, 7.0)  # half across, half along
LAUNCH_ROW = (1044.0, 1182.0)  # where the row runs along the arm: a 23 m pitch
LAUNCH_STRIP_X = 0.0  # the doors' middle across the arm: the top face's middle
# The launch hall: an upper hall under the doors between the chamfers (x +-20, r 219 to the doors' plane) over a wider lower hall
# (x +-42, r 207 to 219) where the second row waits.
LAUNCH_HALL = (-20.0, 20.0, 1038.0, 1188.0)  # the upper hall: x from, x to, z from, z to
HALL_UPPER_R = 219.0  # where the upper hall gives onto the lower one
HALL_LOWER_HALF = 40.0
HALL_CEILING_R = 206.5  # the lower hall's ceiling, toward the axis: the root's notch line
# The second row (the maintainer, 2026-11-13: twelve Starfuries an arm, launching in two waves of six): staged in the lower hall to
# port of each rack, under the chamfer where no open door shows it; it crosses under the rack and rises onto it once the first
# wave has dropped.
STAGING_OFFSET_X = -28.0
STAGING_R = 214.0
ARM_PRONGS_X = (-41.5, 41.5)  # the fork's two posts' middles (D75's light turrets stand on them)
ARM_PRONG = (620.0, 705.0, 2.5, 255.0, 288.5)  # z from, z to, half width, underside and top: posts, as the STL's (M7-T21)
ARM_KNOB = (1380.0, 269.0, (45.0, 29.0, 40.0))  # z, radius, semi-axes across, radial, along
STRINGER_ANGLES_DEG = tuple(270.0 + 36.0 * k for k in range(10))  # from the bottom, every 36 degrees
STRINGER = (14.0, 331.0, 341.0)  # width, inner and outer radius
# --- the frame -------------------------------------------------------------------------------------------------------
RING_FRAME = (488.0, 548.0, 133.0, 157.0)  # the aperture's ring: z from, z to, inner and outer radius
SPINE: list[tuple[float, float, float, float]] = [  # z, half width, underside, top
    # The tops under D75's mounts are flat where a mount stands (H1 and H2 at z 515, L10 and I7 at 2 650, L12 and I9 at 5 650).
    (420.0, 172.0, 313.0, 363.0), (500.0, 185.0, 316.0, 375.0), (530.0, 172.0, 320.0, 375.0), (580.0, 150.0, 330.0, 400.0), (640.0, 80.0, 340.0, 405.0),
    (700.0, 150.0, 348.0, 445.0), (800.0, 165.0, 362.0, 452.0), (950.0, 165.0, 362.0, 455.0), (1050.0, 160.0, 395.0, 462.0),
    (1300.0, 150.0, 395.0, 458.0), (1400.0, 110.0, 415.0, 459.0), (1500.0, 100.0, 418.0, 459.0), (1600.0, 100.0, 425.0, 462.0),
    (1700.0, 100.0, 428.0, 475.0), (1790.0, 100.0, 428.0, 520.0), (2085.0, 100.0, 428.0, 480.0), (2300.0, 90.0, 428.0, 500.0),
    (2350.0, 85.0, 428.0, 505.0), (2362.0, 80.0, 380.0, 505.0), (2420.0, 75.0, 368.0, 505.0), (2650.0, 75.0, 366.0, 537.0), (2750.0, 75.0, 365.0, 555.0), (2832.0, 75.0, 365.0, 552.0),
    (2834.0, 75.0, 365.0, 415.0), (4321.0, 75.0, 365.0, 415.0), (4323.0, 75.0, 365.0, 535.0), (4600.0, 75.0, 365.0, 535.0),
    (4700.0, 78.0, 366.0, 505.0), (4760.0, 80.0, 367.0, 505.0), (4772.0, 84.0, 370.0, 508.0), (4782.0, 85.0, 428.0, 510.0),
    (4840.0, 90.0, 428.0, 520.0), (5440.0, 90.0, 426.0, 505.0),
    (5520.0, 90.0, 400.0, 470.0), (5560.0, 100.0, 395.0, 472.0), (5790.0, 100.0, 395.0, 472.0), (5800.0, 90.0, 300.0, 435.0),
    (5900.0, 80.0, 200.0, 385.0), (6000.0, 70.0, 170.0, 325.0), (6100.0, 60.0, 140.0, 275.0), (6200.0, 50.0, 110.0, 130.0),
    (6360.0, 40.0, 80.0, 100.0),
]
RAMP = [(1300.0, 32.0, 440.0, 459.0), (1500.0, 32.0, 440.0, 507.0), (1750.0, 32.0, 440.0, 548.0), (1790.0, 32.0, 440.0, 520.0)]  # the
# ramp up the spine's middle from the deck over the docking sphere to the radiators: z, half width, underside, top
BOW_TOWER_TOP = 436.0  # the tower on the bow spine (D75's interceptor I5 stands on it, the heavy cannons beside it)
HANGING_BOX = (960.0, 1260.0, 60.0, 316.0, 358.0)  # z from, z to, half width, underside, top
CARGO_Z = (2834.0, 3089.0, 3344.0, 3598.0, 3853.0, 4108.0)
CARGO = (213.0, 108.0, 415.0, 565.0)  # length, half width, underside, top
RADIATORS = ((1725.0, 2085.0, 100.0, 548.0), (5070.0, 5340.0, 90.0, 528.0))  # z from, z to, half width, fin tops
FIN_PITCH_M = 23.0
DOME = (1115.0, 420.0, 45.0)  # z, its base's height, radius
HUB_PROFILE = [(5508.0, 0.0), (5508.0, 292.0), (5560.0, 292.0), (5562.0, 347.0), (5788.0, 347.0), (5792.0, 335.0), (5830.0, 300.0),
               (5900.0, 225.0), (6000.0, 190.0), (6100.0, 160.0), (6200.0, 130.0), (6300.0, 100.0), (6360.0, 90.0), (6362.0, 0.0)]
FIN = ([(60.0, 5740.0), (522.0, 5765.0), (522.0, 5945.0), (105.0, 6340.0), (60.0, 6340.0)], 66.0)  # outline (x, z), thickness
BOOM: list[Section] = [(4110.0, 478.0, 492.0, -12.0, 12.0), (4200.0, 500.0, 520.0, -20.0, 20.0), (4300.0, 515.0, 555.0, -25.0, 25.0),
                       (5400.0, 515.0, 555.0, -25.0, 25.0), (5460.0, 465.0, 515.0, -25.0, 25.0), (5520.0, 445.0, 488.0, -25.0, 25.0),
                       (5800.0, 445.0, 488.0, -25.0, 25.0)]
VANE_Z = (4365.0, 4805.0, 5247.0)
VANE_X = 535.0
VANE_THICK_M = 4.0
VANE_TIP_Y = 1503.0
VANE_NOTCH = (20.0, 40.0)  # half width, depth of the V in the tip
# The blade's half chord along its length (|y| from the axis).
VANE_CHORD = [(60.0, 35.0), (150.0, 87.0), (300.0, 125.0), (600.0, 120.0), (900.0, 100.0), (1200.0, 70.0), (1300.0, 60.0),
              (1450.0, 50.0), (VANE_TIP_Y, 50.0)]
VANE_MOUNT = (488.0, 556.0, 95.0, 60.0)  # x from, x to, half height, half length of each blade pair's clamp on the boom
VANE_TIP_BAR = (522.0, 546.0, 1440.0, 1472.0)  # x from, x to, |y| from, |y| to: the bar across each blade's tip
VANE_RIM_STEP_M = 10.0  # the blades' rims in short steps, so a blade seen edge on still reads as a line  # half width (x), half height, half length of each blade pair's clamp on the boom
TRUSS = (6360.0, 7120.0, 70.0, 90.0)  # z from, z to, the core's half size, the longerons' outer half size
TORUS_PROFILE = [(7110.0, 0.0), (7110.0, 90.0), (7122.0, 204.0), (7140.0, 218.0), (7160.0, 256.0), (7280.0, 256.0), (7300.0, 146.0),
                 (7304.0, 79.0)]
SHAFT_PROFILE = [(7304.0, 79.0), (7700.0, 79.0), (7704.0, 101.0)]
REACTOR_PROFILE = [(7704.0, 101.0), (7760.0, 162.0), (7790.0, 166.0), (7950.0, 166.0), (7975.0, 162.0), (7990.0, 120.0),
                   (7998.0, 98.0), (8000.0, 0.0)]
SEGMENTS = 128  # round the drum's bands: a facet's chord is 20 m at r 417, 13 cm off the true circle


@dataclass(frozen=True)
class Shape:
    """A named mesh in the station frame."""

    name: str
    mesh: Mesh


# --- primitives ------------------------------------------------------------------------------------------------------
def quads(corners: Sequence[np.ndarray], insides: Sequence[np.ndarray], material: Material) -> Mesh:
    """Flat four-cornered faces, each turned to face away from its ``inside`` point, each its own chart with planar UVs: hard
    edges everywhere, the way plate built structures read."""
    verts, faces, uvs = [], [], []
    for k, (quad, inside) in enumerate(zip(corners, insides, strict=True)):
        q = np.asarray(quad, dtype=float).reshape(4, 3)
        normal = np.cross(q[1] - q[0], q[2] - q[0]) + np.cross(q[2] - q[0], q[3] - q[0])
        if float(normal @ (q.mean(axis=0) - np.asarray(inside, dtype=float))) < 0.0:
            q = q[::-1]
        base = 4 * k
        verts.append(q)
        faces += [[base, base + 1, base + 2], [base, base + 2, base + 3]]
        flat = planar_uv(q) if np.linalg.norm(q[1] - q[0]) > 1e-9 else planar_uv(q[[1, 2, 3, 0]])[[3, 0, 1, 2]]
        uvs += [flat[[0, 1, 2]], flat[[0, 2, 3]]]
    n = len(faces)
    charts = np.repeat(np.arange(len(corners)), 2)
    return Mesh(np.concatenate(verts), np.array(faces), np.zeros(n, dtype=np.int64), (material,), charts, np.array(uvs))


def slab(sections: Sequence[Section], material: Material) -> Mesh:
    """A solid of axis-aligned rectangular sections along z (``z, x0, x1, y0, y1`` each), flat sided and closed at both ends."""
    secs = [tuple(float(v) for v in s) for s in sections]
    corners, insides = [], []

    def ring(s: tuple[float, ...]) -> np.ndarray:
        z, x0, x1, y0, y1 = s
        return np.array([[x0, y0, z], [x1, y0, z], [x1, y1, z], [x0, y1, z]])

    for a, b in zip(secs[:-1], secs[1:], strict=True):
        ra, rb = ring(a), ring(b)
        inside = 0.5 * (ra.mean(axis=0) + rb.mean(axis=0))
        for i in range(4):
            j = (i + 1) % 4
            corners.append(np.array([ra[i], ra[j], rb[j], rb[i]]))
            insides.append(inside)
    first, last = ring(secs[0]), ring(secs[-1])
    corners += [first, last]
    insides += [first.mean(axis=0) + [0.0, 0.0, 1.0], last.mean(axis=0) - [0.0, 0.0, 1.0]]
    return quads(corners, insides, material)


def block(lo: Sequence[float], hi: Sequence[float], material: Material) -> Mesh:
    lo, hi = np.asarray(lo, dtype=float), np.asarray(hi, dtype=float)
    return box(hi - lo, material, 0.5 * (lo + hi))


def spine_row_at(z: float) -> tuple[float, float, float, float]:
    """The spine's row (z, half width, underside, top) at ``z``, between its listed rows."""
    zs = [r[0] for r in SPINE]
    return (z, *(float(np.interp(z, zs, [r[k] for r in SPINE])) for k in (1, 2, 3)))


def spine_rows_from(z: float) -> list[tuple[float, float, float, float]]:
    """The spine's rows from ``z`` aft (the cargo bay is cut into its front, M7-T05)."""
    return [spine_row_at(z)] + [r for r in SPINE if r[0] > z + 1e-6]


def spine_slab(rows: Sequence[tuple[float, float, float, float]], material: Material) -> Mesh:
    """A slab symmetric about x = 0 from ``(z, half width, underside, top)`` rows."""
    return slab([(z, -w, w, y0, y1) for z, w, y0, y1 in rows], material)


def around(mesh: Mesh, angles_deg: Sequence[float]) -> Mesh:
    """Copies of a mesh built on top of the axis (at +y) turned to each angle (from +x toward +y) about the axis."""
    return Mesh.concatenate(mesh.transformed(rotation_z(math.radians(a - 90.0))) for a in angles_deg)


def teeth(count: int, z0: float, z1: float, r0: float, r1: float, fill: float, material: Material, phase_deg: float = 0.0) -> Mesh:
    """Blocks standing round the axis between radii ``r0`` and ``r1``, ``fill`` of the girth covered: a toothed rim."""
    width = fill * 2.0 * math.pi * 0.5 * (r0 + r1) / count
    one = block((-0.5 * width, r0, z0), (0.5 * width, r1, z1), material)
    return around(one, [phase_deg + 90.0 + 360.0 * k / count for k in range(count)])


def ellipsoid(centre: Sequence[float], semi: Sequence[float], material: Material, segments: int = 24, rings: int = 12) -> Mesh:
    """An ellipsoid with semi-axes ``semi`` (x, y, z) about ``centre``."""
    angles = np.linspace(0.0, math.pi, rings + 1)
    profile = [(-math.cos(a), math.sin(a)) for a in angles]
    profile[0], profile[-1] = (-1.0, 0.0), (1.0, 0.0)
    unit_sphere = lathe(profile, segments, material)
    scale = np.diag(np.asarray(semi, dtype=float))
    return unit_sphere.transformed(scale, centre)


def rim(outline: Sequence[tuple[float, float]], thickness: float, material: Material) -> Mesh:
    """The edge wall of a flat plate in its own (u, v) plane, thickness along local z: one strip, one chart, unrolled along the
    outline (counter-clockwise or not, it faces outward)."""
    loop = np.asarray(outline, dtype=float)
    if polygon_area_2d(loop) < 0.0:
        loop = loop[::-1]
    n = len(loop)
    half = 0.5 * thickness
    lo = np.column_stack([loop, np.full(n, -half)])
    hi = np.column_stack([loop, np.full(n, half)])
    arc = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.roll(loop, -1, axis=0) - loop, axis=1))])
    verts, faces, uvs = [], [], []
    for k in range(n):
        j = (k + 1) % n
        base = 4 * k
        verts += [lo[k], lo[j], hi[j], hi[k]]
        faces += [[base, base + 1, base + 2], [base, base + 2, base + 3]]
        a, b = arc[k], arc[k + 1]
        uvs += [[[a, 0.0], [b, 0.0], [b, thickness]], [[a, 0.0], [b, thickness], [a, thickness]]]
    return Mesh(np.array(verts), np.array(faces), np.zeros(2 * n, dtype=np.int64), (material,), np.zeros(2 * n, dtype=np.int64),
                np.array(uvs))


def flat_plate(outline: Sequence[tuple[float, float]], pieces: Sequence[Sequence[tuple[float, float]]], thickness: float,
               basis: np.ndarray, origin: Sequence[float], material: Material) -> Mesh:
    """A flat plate: ``pieces`` (convex) tile its face, ``outline`` closes its rim; built in the plane's (u, v) and placed with
    ``basis`` (columns: u, v and the thickness axis in the station frame) at ``origin``."""
    faces = prism([(np.asarray(p, dtype=float), material) for p in pieces], [], thickness)
    return Mesh.concatenate([faces, rim(outline, thickness, material)]).transformed(np.asarray(basis, dtype=float), origin)


# --- the drum --------------------------------------------------------------------------------------------------------
def door_centres() -> list[float]:
    """M7-T09's hangar's door positions along the arm (T04's seven doors; T20 refits the hangar to launch_door_centres)."""
    z0, z1 = DOOR_ROW
    pitch = (z1 - z0) / COBRA_DOORS
    return [z0 + pitch * (k + 0.5) for k in range(COBRA_DOORS)]


def launch_door_centres() -> list[float]:
    """Where each launch door's middle sits along the arm (z, station frame), 1 nearest the bow."""
    z0, z1 = LAUNCH_ROW
    pitch = (z1 - z0) / LAUNCH_DOORS
    return [z0 + pitch * (k + 0.5) for k in range(LAUNCH_DOORS)]


def arm_section(w: float, bottom: float, top: float, chamfer: float | None = None, drop: float | None = None) -> list[tuple[float, float]]:
    """The head's, neck's and taper's chamfered section (x, r), counter-clockwise from the underside's port corner: the flat top
    between its creases, the chamfers (``chamfer`` across, ``drop`` down; 45 degrees when only one is given), the sides, the
    underside."""
    c = ARM_CHAMFER * w if chamfer is None else chamfer
    d = c if drop is None else drop
    return [(-w, bottom), (w, bottom), (w, top - d), (w - c, top), (-(w - c), top), (-w, top - d)]


def root_outline() -> list[tuple[float, float]]:
    """The root's whole section (x, r), counter-clockwise from the top's middle (``ROOT_HALF`` and its mirror)."""
    right = list(ROOT_HALF)
    left = [(-x, r) for x, r in reversed(ROOT_HALF[1:-1])]
    return right + left


def root_pieces() -> list[list[tuple[float, float]]]:
    """The root's section as convex pieces: the body over the notches, the band between them, the underside's two wings."""
    (_, top), (cx, _), (bx, by), (sx, sy), _, (nx, ny0), (_, ny1), _, (_, wy), (ux, uy), _ = ROOT_HALF
    body = [(sx, ny0), (sx, sy), (bx, by), (cx, top), (-cx, top), (-bx, by), (-sx, sy), (-sx, ny0)]
    band = [(-nx, ny1), (nx, ny1), (nx, ny0), (-nx, ny0)]
    wing = [(ux, uy), (sx, wy), (sx, ny1)]
    return [body, band, wing, [(-x, r) for x, r in reversed(wing)]]


def root_chamfer_x(r: float) -> float:
    """Where the root's chamfer stands at radius ``r`` (between its crease and its bevel)."""
    (_, top), (cx, _), (bx, by) = ROOT_HALF[0], ROOT_HALF[1], ROOT_HALF[2]
    return float(np.interp(r, [by, top], [bx, cx]))


def hex_slab(rows: Sequence[tuple[float, ...]], material: Material) -> Mesh:
    """A solid of chamfered sections along z (``z, half width, underside, top`` and optionally the chamfers), closed at both ends."""
    corners, insides = [], []
    rings = [np.array([[x, r, row[0]] for x, r in arm_section(*row[1:])]) for row in rows]
    for ra, rb in zip(rings[:-1], rings[1:], strict=True):
        inside = 0.5 * (ra.mean(axis=0) + rb.mean(axis=0))
        for i in range(6):
            k = (i + 1) % 6
            corners.append(np.array([ra[i], ra[k], rb[k], rb[i]]))
            insides.append(inside)
    for ring, dz in ((rings[0], 1.0), (rings[-1], -1.0)):  # each end as two quads: the box under the creases and the trapezoid over
        inside = ring.mean(axis=0) + [0.0, 0.0, dz]
        corners += [ring[[0, 1, 2, 5]], ring[[5, 2, 3, 4]]]
        insides += [inside, inside]
    return quads(corners, insides, material)


def prism_xr(points: Sequence[tuple[float, float]], z0: float, z1: float, material: Material) -> Mesh:
    """A convex section (x, r) extruded from ``z0`` to ``z1``."""
    ring0 = np.array([[x, r, z0] for x, r in points])
    ring1 = ring0 + [0.0, 0.0, z1 - z0]
    n = len(points)
    inside = 0.5 * (ring0.mean(axis=0) + ring1.mean(axis=0))
    corners = [np.array([ring0[i], ring0[(i + 1) % n], ring1[(i + 1) % n], ring1[i]]) for i in range(n)]
    insides = [inside] * n
    parts = [quads(corners, insides, material)]
    for ring, dz in ((ring0, 1.0), (ring1, -1.0)):  # each end fanned from its first corner
        for i in range(1, n - 1):
            tri = ring[[0, i, i + 1]]
            parts.append(_triangle(tri, ring.mean(axis=0) + [0.0, 0.0, dz], material))
    return Mesh.concatenate(parts)


def _triangle(tri: np.ndarray, inside: np.ndarray, material: Material) -> Mesh:
    """One flat triangle facing away from ``inside``, its own chart."""
    t = np.asarray(tri, dtype=float)
    if float(np.cross(t[1] - t[0], t[2] - t[0]) @ (t.mean(axis=0) - inside)) < 0.0:
        t = t[[0, 2, 1]]
    uv = planar_uv(t)
    return Mesh(t, np.array([[0, 1, 2]]), np.zeros(1, dtype=np.int64), (material,), np.zeros(1, dtype=np.int64), np.array([uv]))


def launch_deck(m: Material) -> list[Mesh]:
    """The root section round the launch doors and the halls under them (M7-T21: its section off the STL): the whole section fore
    and aft of the halls; under them its band and wings; the lower hall's walls up to the upper hall, the shoulders between the upper
    hall and the chamfers, and the deck over it with a hole for each door, sunk ``DOOR_DEPTH`` below the top; so the halls show
    through an open door."""
    z0, z1, _, _, top = ARM_HATCH
    floor, ceiling, upper = top - DOOR_DEPTH, HALL_CEILING_R, HALL_UPPER_R
    _, hx1, hz0, hz1 = LAUNCH_HALL
    lw = HALL_LOWER_HALF
    cx, (dx, dz) = LAUNCH_STRIP_X, LAUNCH_DOOR_HALF
    _, band, wing_r, wing_l = root_pieces()
    parts = [prism_xr(piece, a, b, m) for a, b in ((z0, hz0), (hz1, z1)) for piece in root_pieces()]
    parts += [prism_xr(piece, hz0, hz1, m) for piece in (band, wing_r, wing_l)]
    (_, crease_top), (crease_x, _), (bevel_x, bevel_r), (side_x, side_r) = ROOT_HALF[0], ROOT_HALF[1], ROOT_HALF[2], ROOT_HALF[3]
    for sx in (-1.0, 1.0):
        wall = [(lw, ceiling), (side_x, ceiling), (side_x, side_r), (bevel_x, bevel_r), (root_chamfer_x(upper), upper), (lw, upper)]
        shoulder = [(hx1, upper), (root_chamfer_x(upper), upper), (root_chamfer_x(floor), floor), (hx1, floor)]
        deck = [(cx + dx, floor), (root_chamfer_x(floor), floor), (crease_x, crease_top), (cx + dx, crease_top)]
        for piece in (wall, shoulder, deck):
            parts.append(prism_xr([(sx * x, r) for x, r in piece], hz0, hz1, m))
    edges = [hz0] + [e for c_ in launch_door_centres() for e in (c_ - dz, c_ + dz)] + [hz1]
    for a, b in zip(edges[0::2], edges[1::2], strict=True):
        if b - a > 0.5:
            parts.append(block((cx - dx, floor, a), (cx + dx, top, b), m))
    return parts


def door_glow(m: Material) -> Mesh:
    """The bays' light leaking round each closed door: a lit strip along each of its four edges, at the bottom of its well."""
    floor, cx, (dx, dz) = ARM_HATCH[4] - DOOR_DEPTH, LAUNCH_STRIP_X, LAUNCH_DOOR_HALF
    strips = []
    for c in launch_door_centres():
        for sz in (-1.0, 1.0):
            z = c + sz * (dz - 0.5)
            strips.append(block((cx - dx + 0.3, floor, z - 0.3), (cx + dx - 0.3, floor + 0.4, z + 0.3), m))
        for sx in (-1.0, 1.0):
            x = cx + sx * (dx - 0.5)
            strips.append(block((x - 0.3, floor, c - dz + 0.8), (x + 0.3, floor + 0.4, c + dz - 0.8), m))
    return Mesh.concatenate(strips)


def arm_mesh(m: Material) -> Mesh:
    """One Cobra arm standing on top of the drum (+y): the forked head with its circular clamped hatch, the ribbed neck and the
    root section with their creased, chamfered section (M7-T21), the launch doors and halls in the root, the knob."""
    neck = hex_slab(ARM_NECK, m)
    z0, z1, w, r0, r1 = ARM_HATCH
    hatch = Mesh.concatenate([*launch_deck(m), hex_slab([(z1, w, r0, r1), (z1 + 40.0, 0.8 * w, r0 + 10.0, r1 - 5.0)], m)])
    pz0, pz1, half, under, top = ARM_PRONG
    prongs = [block((x - half, under, pz0), (x + half, top, pz1), m) for x in ARM_PRONGS_X]
    hz, ri, ro = ARM_TOP_HATCH
    head_top = max(r[3] for r in ARM_NECK)  # the peak the hatch sits on
    cap = lathe([(head_top - 1.0, 0.0), (head_top - 1.0, HATCH_CAP[0]), (HATCH_CAP[1], HATCH_CAP[0]), (HATCH_CAP[1], 0.0)], 24, m,
                creases=(1, 2)).transformed(rotation_x(-0.5 * math.pi), (0.0, 0.0, ARM_TOP_HATCH[0]))
    rim = lathe([(head_top, ro), (head_top + 1.5, ro), (head_top + 1.5, ri), (head_top, ri)], 32, m, creases=(1, 2))
    rim = rim.transformed(rotation_x(-0.5 * math.pi), (0.0, 0.0, hz))
    clamps = [block((-2.0, head_top, -5.0), (2.0, head_top + 3.0, 5.0), m).transformed(rotation_y(math.radians(a)), (0.0, 0.0, 0.0))
              .translated((math.cos(math.radians(a)) * (ro + 4.0), 0.0, hz - math.sin(math.radians(a)) * (ro + 4.0)))
              for a in (45.0, 135.0, 225.0, 315.0)]
    rz0, rz1, count = ARM_RIBS
    ribs = []
    for z in np.linspace(rz0, rz1, count):
        zs = [r[0] for r in ARM_NECK]
        hw = float(np.interp(z, zs, [r[1] for r in ARM_NECK]))
        r_bottom = float(np.interp(z, zs, [r[2] for r in ARM_NECK]))
        r_top = float(np.interp(z, zs, [r[3] - r[5] for r in ARM_NECK]))  # up to where the chamfer starts
        for sx in (-1.0, 1.0):
            ribs.append(block((sx * hw - 1.0 if sx > 0 else -hw - 4.0, r_bottom + 2.0, z - 2.0), (hw + 4.0 if sx > 0 else -hw + 1.0, r_top - 2.0, z + 2.0), m))
    kz, kr, semi = ARM_KNOB
    knob = ellipsoid((0.0, kr, kz), semi, m)
    return Mesh.concatenate([neck, hatch, *prongs, cap, rim, *clamps, *ribs, knob])


def mount_plinths(m: Material, body: str) -> Mesh:
    """The plinths under the defence grid's mounts on one piece (D75, M7-T05)."""
    from . import station_detail as sd  # noqa: PLC0415 - it builds on this module's shapes
    from . import station_hardpoints as sh  # noqa: PLC0415

    return Mesh.concatenate(sd.plinth(p, u, sd.PLINTH_R[k], m) for _, k, b, p, u in sh.GRID_MOUNTS if b == body)


def drum_shapes(mats: dict[str, Material]) -> list[Shape]:
    """What turns, in the station frame (the generator moves it onto the drum's own axis frame)."""
    from . import station_detail as sd  # noqa: PLC0415 - it builds on this module's shapes

    grey, recess, machinery = mats["drum_grey"], mats["recess"], mats["machinery"]

    def revolve(profile: Sequence[tuple[float, float]], segments: int = SEGMENTS) -> Mesh:
        creases = [i for i in range(1, len(profile) - 1) if abs(profile[i][0] - profile[i - 1][0]) < 1e-6
                   or abs(profile[i + 1][0] - profile[i][0]) < 1e-6]
        return lathe(profile, segments, grey, creases=creases)

    shapes = [
        Shape("sphere", revolve(SPHERE_PROFILE, 96)),
        Shape("fwd_body", revolve(BODY_PROFILE, 96)),
        Shape("fwd_band", revolve(FWD_BAND_PROFILE)),
        Shape("green", revolve(GREEN_PROFILE)),
        Shape("aft_band", revolve(AFT_BAND_PROFILE)),
        Shape("aperture", sd.main_docking_bay(mats)),
        Shape("drum_plinths", mount_plinths(mats["machinery"], "drum")),
        Shape("arms", around(arm_mesh(grey), ARM_ANGLES_DEG)),
        Shape("bay_lights", around(door_glow(mats["bay_light"]), ARM_ANGLES_DEG)),
        Shape("pods", around(slab([(1450.0, -30.0, 30.0, 300.0, 350.0), (1550.0, -35.0, 35.0, 300.0, 368.0),
                                   (1650.0, -30.0, 30.0, 290.0, 350.0)], grey), ARM_ANGLES_DEG)),
        Shape("rims", Mesh.concatenate([
            teeth(48, RING_Z[0] + 6.0, RING_Z[1] - 4.0, RING_R - 4.0, 404.0, 0.55, grey),
            teeth(64, 2292.0, 2338.0, 372.0, 414.0, 0.5, grey, 2.8),
            teeth(64, 4792.0, 4838.0, 345.0, 414.0, 0.5, grey, 2.8),
        ])),
        Shape("stringers", Mesh.concatenate(
            block((-0.5 * STRINGER[0], STRINGER[1], z0), (0.5 * STRINGER[0], STRINGER[2], z1), grey)
            .transformed(rotation_z(math.radians(a - 90.0)))
            for a in STRINGER_ANGLES_DEG for z0, z1 in ((2360.0, GREEN_BAND[0] - 12.0), (GREEN_BAND[1] + 12.0, 4770.0)))),
        Shape("waist", Mesh.concatenate([
            teeth(8, 1010.0, 1310.0, WAIST_CORE_R - 2.0, 165.0, 0.2, machinery, 22.5),
            teeth(36, 1325.0, 1338.0, 200.0, 262.0, 0.45, recess),
        ])),
    ]
    return shapes


# --- the frame -------------------------------------------------------------------------------------------------------
def bow_mesh(m: Material) -> Mesh:
    """The forked bow spike: two prongs from the tip to z 420, where they meet the spine's front."""
    prong = slab([(0.0, 45.0, 62.0, 312.0, 328.0), (200.0, 47.0, 115.0, 311.0, 336.0), (430.0, 50.0, 172.0, 311.0, 368.0)], m)
    return Mesh.concatenate([prong, prong.mirrored("x")])


def vane_outline() -> tuple[list[tuple[float, float]], list[list[tuple[float, float]]]]:
    """One blade in its own plane: u along the station's z about the blade's centre line, v out from the axis (|y|). Returns the
    rim and the convex pieces that tile it, the V notch cut in the tip."""
    right = [(c, y) for y, c in VANE_CHORD]
    hw, depth = VANE_NOTCH
    tip_y = VANE_TIP_Y
    rim = [(-c, y) for c, y in right] + [(-hw, tip_y), (0.0, tip_y - depth), (hw, tip_y)] + [(c, y) for c, y in reversed(right)]
    rim = _densified(rim, VANE_RIM_STEP_M)
    pieces = []
    for (c0, y0), (c1, y1) in zip(right[:-2], right[1:-1], strict=True):
        pieces.append([(-c0, y0), (c0, y0), (c1, y1), (-c1, y1)])
    c_last, y_last = right[-2]
    c_tip = right[-1][0]
    pieces.append([(-c_last, y_last), (0.0, y_last), (0.0, tip_y - depth), (-hw, tip_y), (-c_tip, tip_y)])
    pieces.append([(0.0, y_last), (c_last, y_last), (c_tip, tip_y), (hw, tip_y), (0.0, tip_y - depth)])
    return rim, pieces


def _densified(loop: list[tuple[float, float]], step: float) -> list[tuple[float, float]]:
    """A closed outline with points added so no edge is longer than ``step``."""
    out = []
    for a, b in zip(loop, loop[1:] + loop[:1], strict=True):
        count = max(1, math.ceil(math.dist(a, b) / step))
        out += [(a[0] + (b[0] - a[0]) * k / count, a[1] + (b[1] - a[1]) * k / count) for k in range(count)]
    return out


def vanes_mesh(m: Material) -> Mesh:
    rim, pieces = vane_outline()
    blades = []
    for side in (-1.0, 1.0):
        for zc in VANE_Z:
            for up in (1.0, -1.0):
                # u -> z, v -> y (up or down), thickness -> x.
                basis = np.array([[0.0, 0.0, 1.0], [0.0, up, 0.0], [1.0, 0.0, 0.0]]).T
                blades.append(flat_plate(rim, pieces, VANE_THICK_M, basis, (side * VANE_X, 0.0, zc), m))
                x0, x1, y0, y1 = VANE_TIP_BAR
                c = VANE_CHORD[-1][1]
                lo, hi = sorted((up * y0, up * y1))
                blades.append(block((min(side * x0, side * x1), lo, zc - c), (max(side * x0, side * x1), hi, zc + c), m))
    return Mesh.concatenate(blades)


def booms_mesh(m: Material) -> Mesh:
    starboard = slab(BOOM, m)
    x0, x1, hy, hz = VANE_MOUNT
    mounts = [block((x0, -hy, zc - hz), (x1, hy, zc + hz), m) for zc in VANE_Z]
    one = Mesh.concatenate([starboard, *mounts])
    return Mesh.concatenate([one, one.mirrored("x")])


def fins_mesh(m: Material) -> Mesh:
    outline, thick = FIN
    # The plate's (u, v) are the station's (x, z); its thickness runs along y.
    basis = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]]).T
    starboard = flat_plate(outline, [outline], thick, basis, (0.0, 0.0, 0.0), m)
    return Mesh.concatenate([starboard, starboard.mirrored("x")])


def truss_mesh(core_m: Material, bar_m: Material) -> Mesh:
    z0, z1, core, outer = TRUSS
    parts = [block((-core, -core, z0), (core, core, z1), core_m)]
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            lo = (min(sx * core, sx * outer), min(sy * core, sy * outer), z0)
            hi = (max(sx * core, sx * outer), max(sy * core, sy * outer), z1)
            parts.append(block(lo, hi, bar_m))
    pitch = 38.0
    for z in np.arange(z0 + 0.5 * pitch, z1, pitch):
        for k in range(4):
            bar = block((-core, core, z - 4.0), (core, outer - 4.0, z + 4.0), bar_m)
            parts.append(bar.transformed(rotation_z(0.5 * math.pi * k)))
    for z in np.linspace(z0 + 40.0, z1 - 40.0, 6):  # the clamps
        parts.append(block((-outer - 14.0, -outer - 14.0, z - 9.0), (outer + 14.0, outer + 14.0, z + 9.0), bar_m))
    return Mesh.concatenate(parts)


def frame_shapes(mats: dict[str, Material]) -> list[Shape]:
    """What stands still, in the station frame."""
    from . import station_detail as sd  # noqa: PLC0415 - it builds on this module's shapes

    spine, grey, recess, machinery = mats["spine"], mats["drum_grey"], mats["recess"], mats["machinery"]
    rz0, rz1, ri, ro = RING_FRAME
    ring = lathe([(rz0, ri), (rz0, ro - 6.0), (rz0 + 8.0, ro), (rz1 - 8.0, ro), (rz1, ro - 6.0), (rz1, ri), (rz0, ri)], 96, grey,
                 creases=(1, 2, 3, 4, 5))
    ring_teeth = teeth(36, rz0 + 12.0, rz1 - 12.0, ro - 2.0, ro + 6.0, 0.5, recess)
    pylon = block((-25.0, ro - 4.0, 494.0), (25.0, 330.0, 542.0), spine)
    tower = block((-20.0, 370.0, 495.0), (20.0, BOW_TOWER_TOP, 545.0), spine)
    radiators = []
    for z0, z1, w, top in RADIATORS:
        radiators.append(block((-w, 470.0, z0), (w, top - 28.0, z1), machinery))
        for z in np.arange(z0 + 0.5 * FIN_PITCH_M, z1, FIN_PITCH_M):
            radiators.append(block((-w, top - 30.0, z - 3.0), (w, top, z + 3.0), machinery))
    cargo = [block((-CARGO[1], CARGO[2], z), (CARGO[1], CARGO[3], z + CARGO[0]), mats["cargo"]) for z in CARGO_Z]
    dz, dy, dr = DOME
    dome = lathe([(0.0, dr)] + [(dr * math.sin(a), dr * math.cos(a)) for a in np.linspace(0.15, 0.5 * math.pi, 8)], 32, mats["dome"])
    dome = dome.transformed(rotation_x(-0.5 * math.pi), (0.0, dy, dz))
    lamp = block((-5.0, dy + dr - 2.0, dz - 5.0), (5.0, dy + dr + 6.0, dz + 5.0), mats["lamp"])
    flank_lamps = [block((sx * 150.5 - 1.0, 410.0, z - 12.0), (sx * 150.5 + 1.0, 422.0, z + 12.0), mats["lamp"])
                   for sx in (-1.0, 1.0) for z in (1180.0, 1230.0)]
    hz0, hz1, hw, hy0, hy1 = HANGING_BOX
    struts = [block((-12.0, hy1, z - 12.0), (12.0, 400.0, z + 12.0), mats["machinery"]) for z in (hz0 + 40.0, hz1 - 40.0)]
    return [
        Shape("bow", Mesh.concatenate([bow_mesh(spine), ring, ring_teeth, pylon, tower])),
        Shape("spine", Mesh.concatenate([spine_slab(spine_rows_from(sd.ZG_BACK_Z), spine), sd.cargo_bay_walls(spine), spine_slab(RAMP, spine),
                                         block((-hw, hy0, hz0), (hw, hy1, hz1), spine),
                                         *struts])),
        Shape("radiators", Mesh.concatenate(radiators)),
        Shape("cargo", Mesh.concatenate(cargo)),
        Shape("dome", Mesh.concatenate([dome, lamp, *flank_lamps])),
        Shape("frame_plinths", mount_plinths(machinery, "frame")),
        Shape("cargo_bay", sd.cargo_bay(mats)),
        Shape("command_detail", sd.command_detail(mats)),
        Shape("hub", lathe(HUB_PROFILE, 96, spine, creases=(1, 2, 3, 4, 5, 6))),
        Shape("fins", fins_mesh(spine)),
        Shape("booms", booms_mesh(mats["vane_frame"])),
        Shape("vanes", vanes_mesh(mats["vane"])),
        Shape("truss", truss_mesh(recess, machinery)),
        Shape("aft", Mesh.concatenate([
            lathe(TORUS_PROFILE, 96, mats["reactor"], creases=(1, 2, 3, 4, 5, 6)),
            teeth(48, 7170.0, 7270.0, 252.0, 264.0, 0.45, mats["reactor"]),
            lathe(SHAFT_PROFILE, 48, mats["reactor"], creases=(1,)),
            lathe(REACTOR_PROFILE, 64, mats["reactor"], creases=(1, 2, 3, 4, 5, 6)),
            # The aft face's ring of bulging pipe sections round its flat middle.
            around(ellipsoid((0.0, 132.0, 7984.0), (24.0, 18.0, 14.0), mats["reactor"], 12, 8), [15.0 + 30.0 * k for k in range(12)]),
        ])),
    ]


def signed_volume(mesh: Mesh) -> float:
    """The enclosed volume, positive when the faces turn outward: a closed shape built inside out comes out negative."""
    v = mesh.vertices[mesh.faces]
    return float(np.einsum("ij,ij->i", v[:, 0], np.cross(v[:, 1], v[:, 2])).sum() / 6.0)


__all__ = ["Shape", "drum_shapes", "frame_shapes", "quads", "slab", "unit"]
