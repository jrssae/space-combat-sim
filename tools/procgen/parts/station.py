"""The Babylon 5 station's shapes (M7-T04), from the measurements in docs/assets-station.md: every number is metres in the station
frame read off the reference model, x to starboard, y up, z aft from the bow tip (0 to 8 000), x and y about the drum's axis.

Two sets: :func:`drum_shapes` (what turns: the docking sphere and its door, the waist, the four Cobra arms, the forward body, the
rings and bands, the green zone) and :func:`frame_shapes` (what stands still: the bow spike, the aperture's ring, the dorsal spine
with its radiators, cargo modules and dome, the hub and cone, the delta fins, the vane booms and vanes, the truss, the torus disc,
the shaft and the reactor). Each shape is a named mesh; the generator gives it its surface layout, paint and windows
(``station_layouts.py``) and moves it into its piece's frame.
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
# The docking aperture's door (turns with the drum): a front ring round a dark opening crossed by four spokes on a hub, lit inside.
APERTURE_R = 88.0  # the opening's radius
APERTURE_BACK_Z = 512.0  # the lit wall at the back of the opening
APERTURE_SPOKE = (18.0, 482.0)  # each spoke's width and the z of its front face
APERTURE_HUB = (22.0, 474.0)  # the hub's radius and the z of its front face
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
ARM_HEAD = [(640.0, 55.0, 225.0, 282.0), (700.0, 80.0, 235.0, 305.0), (730.0, 80.0, 235.0, 320.0), (870.0, 78.0, 232.0, 320.0),
            (900.0, 75.0, 225.0, 300.0), (980.0, 50.0, 212.0, 258.0), (1000.0, 47.0, 203.0, 243.0)]
ARM_TOP_HATCH = (800.0, 24.0, 30.0)  # the circular hatch on the head's top: z of its middle, inner and outer radius
ARM_RIBS = (906.0, 984.0, 9)  # the neck's ribs on both flanks: z from, z to, how many
ARM_HATCH = (1000.0, 1300.0, 47.0, 203.0, 243.0)  # z from, z to, half width, inner and outer radius (the frame's top)
# The launch doors on each arm's hatch section: seven in a row, sunk into a frame of rails and bars (T05 adds the bays behind).
COBRA_DOORS = 7
DOOR_HALF = (32.0, 14.0)  # half across, half along
DOOR_DEPTH = 4.0  # the frame stands this far above the doors
DOOR_ROW = (1020.0, 1290.0)  # where the row of doors runs along the arm
ARM_PRONGS_X = (-41.0, 41.0)  # the fork's two prongs' middles (D75's light turrets stand on them)
ARM_PRONG = (612.0, 705.0, 19.0, 255.0, 292.0)  # z from, z to, half width, underside and top
ARM_KNOB = (1380.0, 269.0, (45.0, 29.0, 40.0))  # z, radius, semi-axes across, radial, along
STRINGER_ANGLES_DEG = tuple(270.0 + 36.0 * k for k in range(10))  # from the bottom, every 36 degrees
STRINGER = (14.0, 331.0, 341.0)  # width, inner and outer radius
# --- the frame -------------------------------------------------------------------------------------------------------
RING_FRAME = (488.0, 548.0, 133.0, 157.0)  # the aperture's ring: z from, z to, inner and outer radius
SPINE: list[tuple[float, float, float, float]] = [  # z, half width, underside, top
    (420.0, 172.0, 311.0, 368.0), (500.0, 185.0, 315.0, 380.0), (580.0, 150.0, 330.0, 400.0), (640.0, 80.0, 340.0, 405.0),
    (700.0, 150.0, 348.0, 445.0), (800.0, 165.0, 362.0, 452.0), (950.0, 165.0, 362.0, 455.0), (1050.0, 160.0, 395.0, 462.0),
    (1300.0, 150.0, 395.0, 458.0), (1400.0, 110.0, 415.0, 459.0), (1500.0, 100.0, 418.0, 459.0), (1600.0, 100.0, 425.0, 462.0),
    (1700.0, 100.0, 428.0, 475.0), (1790.0, 100.0, 428.0, 520.0), (2085.0, 100.0, 428.0, 480.0), (2300.0, 90.0, 428.0, 500.0),
    (2350.0, 85.0, 428.0, 505.0), (2362.0, 80.0, 380.0, 505.0), (2420.0, 75.0, 368.0, 505.0), (2750.0, 75.0, 365.0, 555.0), (2832.0, 75.0, 365.0, 552.0),
    (2834.0, 75.0, 365.0, 415.0), (4321.0, 75.0, 365.0, 415.0), (4323.0, 75.0, 365.0, 535.0), (4600.0, 75.0, 365.0, 535.0),
    (4700.0, 78.0, 366.0, 505.0), (4760.0, 80.0, 367.0, 505.0), (4772.0, 84.0, 370.0, 508.0), (4782.0, 85.0, 428.0, 510.0),
    (4840.0, 90.0, 428.0, 520.0), (5440.0, 90.0, 426.0, 505.0),
    (5520.0, 90.0, 400.0, 470.0), (5560.0, 100.0, 395.0, 480.0), (5790.0, 100.0, 395.0, 485.0), (5800.0, 90.0, 300.0, 435.0),
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
    """Where each launch door's middle sits along the arm (z, station frame)."""
    z0, z1 = DOOR_ROW
    pitch = (z1 - z0) / COBRA_DOORS
    return [z0 + pitch * (k + 0.5) for k in range(COBRA_DOORS)]


def door_frame(m: Material) -> Mesh:
    """The frame round an arm's launch doors: two rails along the sides and a bar between each door and the next."""
    z0, z1, w, _, top = ARM_HATCH
    floor, dx, dz = top - DOOR_DEPTH, DOOR_HALF[0], DOOR_HALF[1]
    parts = [block((sx * dx if sx > 0 else -w, floor, z0), (w if sx > 0 else -dx, top, z1), m) for sx in (-1.0, 1.0)]
    edges = [z0] + [e for c in door_centres() for e in (c - dz, c + dz)] + [z1]
    for a, b in zip(edges[0::2], edges[1::2], strict=True):
        if b - a > 0.5:
            parts.append(block((-dx, floor, a), (dx, top, b), m))
    return Mesh.concatenate(parts)


def door_glow(m: Material) -> Mesh:
    """The bays' light leaking round each closed door: a lit strip along each of its four edges, at the bottom of its well."""
    floor, dx, dz = ARM_HATCH[4] - DOOR_DEPTH, DOOR_HALF[0], DOOR_HALF[1]
    strips = []
    for c in door_centres():
        for sz in (-1.0, 1.0):
            z = c + sz * (dz - 0.9)
            strips.append(block((-dx + 0.5, floor, z - 0.6), (dx - 0.5, floor + 0.5, z + 0.6), m))
        for sx in (-1.0, 1.0):
            x = sx * (dx - 0.9)
            strips.append(block((x - 0.6, floor, c - dz + 1.5), (x + 0.6, floor + 0.5, c + dz - 1.5), m))
    return Mesh.concatenate(strips)


def door_clamps(post: Material, cap: Material) -> Mesh:
    """Beside each door a hinged clamp: a post on the rail, an arm reaching over the door's edge and a red cap block."""
    top, dx = ARM_HATCH[4], DOOR_HALF[0]
    parts = []
    for c in door_centres():
        parts.append(block((dx + 4.0, top, c - 2.0), (dx + 9.0, top + 8.0, c + 2.0), post))
        parts.append(block((dx - 6.0, top + 6.0, c - 1.5), (dx + 9.0, top + 8.0, c + 1.5), post))
        parts.append(block((dx + 3.0, top + 8.0, c - 3.0), (dx + 10.0, top + 12.0, c + 3.0), cap))
    return Mesh.concatenate(parts)


def arm_mesh(m: Material) -> Mesh:
    """One Cobra arm standing on top of the drum (+y): the forked head with its circular clamped hatch, the ribbed neck, the hatch
    section with its frame of launch doors, the knob."""
    head = slab([(z, -w, w, r0, r1) for z, w, r0, r1 in ARM_HEAD], m)
    z0, z1, w, r0, r1 = ARM_HATCH
    floor = r1 - DOOR_DEPTH
    hatch = slab([(z0, -w, w, r0, floor), (z1, -w, w, r0, floor), (z1 + 40.0, -0.8 * w, 0.8 * w, r0 + 10.0, r1 - 5.0)], m)
    hatch = Mesh.concatenate([hatch, door_frame(m)])
    pz0, pz1, half, under, top = ARM_PRONG
    prongs = [block((x - half, under, pz0), (x + half, top, pz1), m) for x in ARM_PRONGS_X]
    hz, ri, ro = ARM_TOP_HATCH
    head_top = ARM_HEAD[3][3]
    rim = lathe([(head_top, ro), (head_top + 1.5, ro), (head_top + 1.5, ri), (head_top, ri)], 32, m, creases=(1, 2))
    rim = rim.transformed(rotation_x(-0.5 * math.pi), (0.0, 0.0, hz))
    clamps = [block((-2.0, head_top, -5.0), (2.0, head_top + 3.0, 5.0), m).transformed(rotation_y(math.radians(a)), (0.0, 0.0, 0.0))
              .translated((math.cos(math.radians(a)) * (ro + 4.0), 0.0, hz - math.sin(math.radians(a)) * (ro + 4.0)))
              for a in (45.0, 135.0, 225.0, 315.0)]
    rz0, rz1, count = ARM_RIBS
    ribs = []
    for z in np.linspace(rz0, rz1, count):
        hw = float(np.interp(z, [r[0] for r in ARM_HEAD], [r[1] for r in ARM_HEAD]))
        r_top = float(np.interp(z, [r[0] for r in ARM_HEAD], [r[3] for r in ARM_HEAD]))
        for sx in (-1.0, 1.0):
            ribs.append(block((sx * hw - 1.0 if sx > 0 else -hw - 4.0, 228.0, z - 2.0), (hw + 4.0 if sx > 0 else -hw + 1.0, r_top - 6.0, z + 2.0), m))
    kz, kr, semi = ARM_KNOB
    knob = ellipsoid((0.0, kr, kz), semi, m)
    return Mesh.concatenate([head, hatch, *prongs, rim, *clamps, *ribs, knob])


def aperture_mesh(mats: dict[str, Material]) -> Mesh:
    """The docking aperture's door: a front ring round the dark opening, four spokes on a hub across it, the lit back wall, and
    lamps round the ring."""
    grey, recess = mats["drum_grey"], mats["recess"]
    back, r = APERTURE_BACK_Z, APERTURE_R
    well = lathe([(back, 0.0), (back, r), (DOOR_Z, r), (DOOR_Z, DOOR_R)], 96, [recess, recess, grey], creases=(1, 2))
    hub_r, hub_z = APERTURE_HUB
    hub = lathe([(hub_z, 0.0), (hub_z, hub_r), (back, hub_r)], 32, grey, creases=(1,))
    width, spoke_z = APERTURE_SPOKE
    spoke = block((-0.5 * width, hub_r - 2.0, spoke_z), (0.5 * width, r + 1.0, back), grey)
    spokes = around(spoke, (0.0, 90.0, 180.0, 270.0))
    glow = around(block((-14.0, 38.0, back - 1.5), (14.0, 62.0, back), mats["bay_light"]), (45.0, 135.0, 225.0, 315.0))
    lamps = teeth(16, DOOR_Z - 1.5, DOOR_Z, 104.0, 112.0, 0.25, mats["lamp"], 11.25)
    return Mesh.concatenate([well, hub, spokes, glow, lamps])


def drum_shapes(mats: dict[str, Material]) -> list[Shape]:
    """What turns, in the station frame (the generator moves it onto the drum's own axis frame)."""
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
        Shape("aperture", aperture_mesh(mats)),
        Shape("arms", around(arm_mesh(grey), ARM_ANGLES_DEG)),
        Shape("bay_lights", around(door_glow(mats["bay_light"]), ARM_ANGLES_DEG)),
        Shape("clamps", around(door_clamps(mats["machinery"], mats["trim"]), ARM_ANGLES_DEG)),
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
        Shape("spine", Mesh.concatenate([spine_slab(SPINE, spine), spine_slab(RAMP, spine), block((-hw, hy0, hz0), (hw, hy1, hz1), spine),
                                         *struts])),
        Shape("radiators", Mesh.concatenate(radiators)),
        Shape("cargo", Mesh.concatenate(cargo)),
        Shape("dome", Mesh.concatenate([dome, lamp, *flank_lamps])),
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
