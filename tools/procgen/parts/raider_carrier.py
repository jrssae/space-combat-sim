"""The raider strike carrier's parts (M12-T19; docs/assets-capital.md and docs/design-references.md, "Raider strike carrier").

Every proportion below is a percentage of the ship's length, read off the maintainer's reference model and written down in
docs/assets-capital.md; :class:`CarrierSpec` turns them into metres. The frame is the authored one: x to starboard, y up,
z aft from the bow (the tips of the bow spikes at z = 0).

Bow to stern: a drum with an open rim and the hangar mouth in its face, two rings round it joined to it by a spoke on each
side, a spine back to the centre section, a box hull on each side of that section with five hangar slats in its outer flank,
and one main engine with four tanks behind the centre section. Eighteen cradle arms stand out from the drum's first collar
and the two rings; each ends in a pad a Delta-V docks on (:func:`cradles`).

Each builder returns its render piece and the convex collision shapes that stand for it (``core/collision.py``); a piece of
the right side is mirrored to the left by the generator, shapes and all.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from ..core import civilian as cv
from ..core import collision as col
from ..core.geometry import Material, Mesh, basis_from_z, box, lathe, tapered_box
from ..styles import Style
from . import Part

# --- proportions, in percent of the length ----------------------------------------------------------------------------
# The drum: the rim's mouth, the recessed face, the body, three collars, the aft cap.
RIM_Z = (6.84, 10.5)
RIM_R = (12.9, 14.4, 14.8)  # the mouth's inner wall, the rim's front edge, the rim's aft edge
DRUM_R = 13.3
DRUM_AFT_Z = 32.8
COLLAR_R = 14.34
COLLARS_Z = ((10.5, 14.48), (19.6, 23.19), (28.03, 31.62))
FRAME_Z = 9.8  # the hangar mouth's frame stands this far forward of the face
FRAME_HALF = (8.5, 6.3)
MOUTH_HALF = (6.2, 4.2)
DISH = ((9.6, 1.8, 6.2), (0.0, 9.7, 7.4))  # the sensor housing over the mouth: size, centre
SPIKES_LONG = (7.02, 13.6, (1.19, 0.36), (0, 60, 120, 180))  # length, radius, root section (radial, across), clocks
SPIKES_SHORT = (2.9, 13.45, (0.7, 0.36), (30, 150))
SPIKE_SHORT_Z = 4.1

# The rings: station (centre), half width, inner and outer radius, the bevel of the section's corners.
RING_MID = (21.4, 2.635, 19.7, 21.3)
RING_OUTER = (29.83, 2.635, 26.8, 28.4)
RING_BEVEL = 0.5
SPOKE_R = 1.48
SPOKE_BLOCK = (2.66, 5.6, 3.7)  # where a spoke meets its ring: along the spoke, up, along the ship

# The cradles: per ring, the arm's station and root radius and the clock positions (degrees from up, positive to starboard).
ARM_LENGTH = 8.1
ARM_R = (1.1, 0.65)  # at the root, along the shaft
CRADLE_RINGS = (
    ("outer", 29.83, 28.2, (0, 40, 80, 120, 160)),
    ("mid", 21.4, 21.1, (0, 60, 120, 180)),
    ("drum", 12.7, 14.0, (0, 120)),
)
PAD_AFT_OF_ARM = 2.95  # the pad's forward edge, aft of the arm's axis
PAD_DEPTH = 2.96  # along the ship
PAD_THICK = 1.405  # radially
PAD_HALF = (5.915, 4.436)  # half width at the forward and the aft edge
PIN_REACH = 7.62  # the clamp pins' tips, from the pad's centre line
PIN = (0.52, 0.37, 3.33)  # a pin: across, radially, along the ship
PIN_AHEAD = 1.63  # how far a pin starts ahead of the pad's forward edge
BRACKET = (2.52, 0.8)  # the beam from the arm's top to the pad: across, radially

# The spine and the centre section between the boxes.
SPINE_R = 2.59
SPINE_Z = (32.8, 44.92)
BEAM_HALF = (11.09, 4.8)
BEAMS_Z = ((44.92, 47.87), (76.71, 79.67))
SLAB_HALF = (6.65, 2.95)
BAR_X = (4.81, 11.09)
BAR_Y = (2.95, 6.28)
ELBOWS_Z = (49.0, 57.85, 66.7, 75.6)
ELBOW = (7.9, 8.9, 1.1)  # the riser's x, the cross pipe's y, the pipe's radius

# The engine: the mount disc, four tanks round the centre line, the main engine and its bell.
MOUNT = (79.6, 81.37, 4.73)
TANK_OFFSET = 3.03
TANK_PROFILE = ((81.52, 0.0), (81.9, 1.1), (82.6, 1.7), (83.4, 1.85), (88.5, 1.85), (89.3, 1.7), (90.0, 1.1), (90.39, 0.0))
ENGINE_PROFILE = ((81.37, 1.05), (91.6, 1.05), (93.9, 2.25), (97.04, 2.25), (97.04, 1.95), (94.2, 1.95), (94.2, 0.0))
PETAL = ((2.6, 0.6, 3.55), 2.2, 98.225)  # size, radius, station: the bell's four petals reach z = 100

# A box hull: its outline seen from the side (z, y), top half; the bottom half mirrors it. The first two points are the nose.
BOX_X = (11.09, 36.97)
BOX_NOSE = ((41.22, 9.24), (44.18, 9.82))
BOX_BODY = ((44.18, 9.82), (48.61, 18.11), (79.67, 24.77), (86.69, 15.15))
FRONT_PLATE = (39.0, 41.22, 9.3)  # z from, z to, half height
SLOT_X = 35.49  # the slats' floor
SLOT_Z = (51.2, 77.08)
SLOT_HALF = 1.48
SLOTS_Y = (-13.31, -6.65, 0.0, 6.65, 13.31)
SLAT_BARS_Z = (57.85, 60.85, 63.75, 66.75, 69.65)
SLAT_BAR = (0.71, 1.5)  # how far a bar stands out of the floor, its width along the ship
KNOB = ((3.7, 2.7, 3.7), (2.3, 2.3), (34.4, 21.4, 57.9))  # base size, top size, centre: one on the top deck, one under the keel
GADGET = ((5.0, 3.4, 4.6), (33.4, -15.6, 44.6))  # the fitting under the bow slope
FIN_X = ((11.09, 14.79), (18.48, 22.18), (25.88, 29.57), (33.27, 36.97))
FIN_PROFILE = ((79.6, -24.8), (86.9, -28.68), (89.28, -16.2), (86.7, -15.15))  # (z, y): the skirt under the stern slope

DOCK_AHEAD_M = 1.0  # a docked fighter's box centre, forward of the pad's centre: its tail stays clear of the next ring's arm

AREAL_DENSITY = 260.0  # kg per square metre of skin: the informational mass


@dataclass(frozen=True)
class CarrierSpec:
    """The one free number: the length (docs/assets-capital.md, "Length")."""

    length_m: float = 112.0

    @property
    def u(self) -> float:
        """Metres per percent of the length."""
        return self.length_m / 100.0


@dataclass(frozen=True)
class Built:
    """A render piece and the collision shapes that stand for it (a right-hand piece's are mirrored with it)."""

    piece: cv.Piece
    shapes: tuple[col.Shape, ...] = ()


@dataclass(frozen=True)
class Cradle:
    """One docking cradle: its ring, its clock angle (degrees from up, positive to starboard), the pad's centre on its outer
    face, and the pad's frame (``across`` along the pad, ``out`` away from the ship's axis; forward is -z)."""

    name: str
    ring: str
    clock_deg: float
    arm_z: float
    root_r: float
    pad_centre: np.ndarray
    across: np.ndarray
    out: np.ndarray

    @property
    def basis(self) -> np.ndarray:
        return np.stack([self.across, self.out, np.array([0.0, 0.0, 1.0])], axis=1)

    @property
    def dock(self) -> np.ndarray:
        """Where a docked fighter's box is centred, on the pad's outer face."""
        return self.pad_centre - np.array([0.0, 0.0, DOCK_AHEAD_M])


# --- helpers -----------------------------------------------------------------------------------------------------------
def clock_frame(clock_deg: float) -> tuple[np.ndarray, np.ndarray]:
    """The tangent and the outward direction at a clock angle."""
    a = math.radians(clock_deg)
    return np.array([math.cos(a), -math.sin(a), 0.0]), np.array([math.sin(a), math.cos(a), 0.0])


def cradle_name(ring: str, clock_deg: float) -> str:
    side = "" if clock_deg in (0, 180) else "_r"
    return f"{ring}_{int(clock_deg):03d}{side}"


def cradles(spec: CarrierSpec, both_sides: bool = True) -> list[Cradle]:
    """Every cradle, ring by ring from the stern forward, each ring from the top round to the bottom; with ``both_sides`` the
    port twin follows each starboard one."""
    u = spec.u
    out = []
    for ring, arm_z, root_r, clocks in CRADLE_RINGS:
        for clock in clocks:
            for sign in (1, -1) if both_sides and clock not in (0, 180) else (1,):
                across, outward = clock_frame(sign * clock)
                top_r = root_r + ARM_LENGTH + PAD_THICK
                centre = top_r * u * outward + np.array([0.0, 0.0, (arm_z + PAD_AFT_OF_ARM + 0.5 * PAD_DEPTH) * u])
                name = cradle_name(ring, clock)
                out.append(Cradle(name if sign > 0 else cv.left_name(name), ring, float(sign * clock), arm_z * u, root_r * u, centre, across, outward))
    return out


def flat(points: Sequence[Sequence[float]], material: Material, away: Sequence[float]) -> Mesh:
    """One flat convex polygon as a fan, facing away from the point ``away``."""
    p = np.asarray(points, dtype=float).reshape(-1, 3)
    normal = np.zeros(3)
    for a, b in zip(p[1:-1], p[2:], strict=True):
        normal += np.cross(a - p[0], b - p[0])
    if float(normal @ (p.mean(axis=0) - np.asarray(away, dtype=float))) < 0.0:
        p = p[::-1]
    faces = [[0, k, k + 1] for k in range(1, len(p) - 1)]
    return Mesh(p, np.array(faces), np.zeros(len(faces), dtype=np.int64), (material,))


def clip(poly: np.ndarray, axis: int, value: float, keep_above: bool) -> np.ndarray:
    """A convex 2D polygon cut by the line ``axis = value``: the part above it or below it."""
    out = []
    sign = 1.0 if keep_above else -1.0
    for a, b in zip(poly, np.roll(poly, -1, axis=0), strict=True):
        da, db = sign * (a[axis] - value), sign * (b[axis] - value)
        if da >= 0.0:
            out.append(a)
        if (da > 0.0 > db) or (da < 0.0 < db):
            out.append(a + (b - a) * (da / (da - db)))
    return np.array(out).reshape(-1, 2)


def extrude_x(profile_zy: Sequence[Sequence[float]], x0: float, x1: float, wall: Material, caps: tuple[Material | None, Material | None],
              wall_by_edge: dict[int, Material] | None = None) -> Mesh:
    """A side-view outline (z, y) pulled from ``x0`` to ``x1``: a wall per edge (``wall_by_edge`` repaints some), a cap at each
    end where a material is given. The outline may bend in, as long as its middle sees every edge."""
    p = np.asarray(profile_zy, dtype=float).reshape(-1, 2)
    inside = np.array([0.5 * (x0 + x1), p[:, 1].mean(), p[:, 0].mean()])
    parts = []
    for k, (a, b) in enumerate(zip(p, np.roll(p, -1, axis=0), strict=True)):
        quad = [(x0, a[1], a[0]), (x0, b[1], b[0]), (x1, b[1], b[0]), (x1, a[1], a[0])]
        parts.append(flat(quad, (wall_by_edge or {}).get(k, wall), inside))
    for x, material in zip((x0, x1), caps, strict=True):
        if material is not None:
            parts.append(flat([(x, y, z) for z, y in p], material, inside))
    return Mesh.concatenate(parts)


def tube(a: Sequence[float], b: Sequence[float], profile: Sequence[tuple[float, float]], segments: int,
         materials: Material | Sequence[Material], creases: Sequence[int] = ()) -> Mesh:
    """A lathe laid from ``a`` towards ``b``: ``profile`` is (distance from ``a``, radius)."""
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    return lathe(profile, segments, materials, creases).transformed(basis_from_z(b - a), a)


def part(name: str, group: str, mesh: Mesh) -> Part:
    return Part(name, mesh, {}, [], round(mesh.area() * AREAL_DENSITY, 1), group)


def mirrored_y(mesh: Mesh) -> Mesh:
    return mesh.mirrored("y")


# --- the drum and the bow ----------------------------------------------------------------------------------------------
def drum(spec: CarrierSpec, style: Style) -> Built:
    """The bow drum: the open rim, the recessed face, the body with its three collars, the aft cap."""
    u = spec.u
    hull, dark = style.material("hull"), style.material("hull_dark")
    profile = [(RIM_Z[1], 0.0), (RIM_Z[1], RIM_R[0]), (RIM_Z[0], RIM_R[0]), (RIM_Z[0], RIM_R[1]), (RIM_Z[1], RIM_R[2]), (RIM_Z[1], COLLAR_R)]
    mats = [dark, dark, dark, dark, dark]  # the recessed face is dark, as the show's still has it
    z = COLLARS_Z[0][1]
    profile.append((z, COLLAR_R))
    mats.append(dark)
    for z0, z1 in COLLARS_Z[1:]:
        profile += [(z, DRUM_R), (z0, DRUM_R), (z0, COLLAR_R), (z1, COLLAR_R)]
        mats += [dark, hull, dark, dark]
        z = z1
    profile += [(z, DRUM_R), (DRUM_AFT_Z, DRUM_R), (DRUM_AFT_Z, 0.0)]
    mats += [dark, hull, dark]
    mesh = lathe([(a * u, b * u) for a, b in profile], 48, mats, creases=range(1, len(profile) - 1))
    body = col.Shape.hull("drum", col.prism_points((0, 0, 0), (0, 0, 1), [(FRAME_Z * u, COLLAR_R * u), (DRUM_AFT_Z * u, COLLAR_R * u)], 16))
    rim = col.ring_sectors("rim", (0, 0, 0), (0, 0, 1), RIM_R[0] * u, RIM_R[2] * u, RIM_Z[0] * u, RIM_Z[1] * u, 10)
    return Built(cv.Piece(part("drum", "drum", mesh)), (body, *rim))


def bow_fittings(spec: CarrierSpec, style: Style) -> Built:
    """In the rim's mouth: the hangar mouth and its eight-sided frame, and the sensor housing over it."""
    u = spec.u
    fx, fy = FRAME_HALF[0] * u, FRAME_HALF[1] * u
    cut = 0.3 * fy
    z0, z1 = FRAME_Z * u, RIM_Z[1] * u
    outline = [(-fx + cut, -fy), (fx - cut, -fy), (fx, -fy + cut), (fx, fy - cut), (fx - cut, fy), (-fx + cut, fy), (-fx, fy - cut), (-fx, -fy + cut)]
    inside = (0.0, 0.0, z1)
    frame = [flat([(x, y, z0) for x, y in outline], style.material("hull_panel"), inside)]
    for a, b in zip(outline, outline[1:] + outline[:1], strict=True):
        frame.append(flat([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], style.material("hull_dark"), inside))
    mx, my = MOUTH_HALF[0] * u, MOUTH_HALF[1] * u
    mouth = flat([(-mx, -my, z0 - 0.02), (mx, -my, z0 - 0.02), (mx, my, z0 - 0.02), (-mx, my, z0 - 0.02)], style.material("interior"), inside)
    size, centre = np.array(DISH[0]) * u, np.array(DISH[1]) * u
    dish = tapered_box(size[1], (size[0], size[2]), (0.6 * size[0], 0.55 * size[2]), style.material("hull_panel"))
    dish = dish.transformed(np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]]), centre)  # its taper runs up
    shape = col.Shape.box("dish", centre, (size[0], size[1], size[2]))
    return Built(cv.Piece(part("bow_fittings", "drum", Mesh.concatenate([*frame, mouth, dish]))), (shape,))


def spikes(spec: CarrierSpec, style: Style) -> list[Built]:
    """The antenna spikes on the rim: blades standing forward, long ones and short ones between them."""
    u = spec.u
    out = []
    for kind, (length, radius, root, clocks), z_tip in (("long", SPIKES_LONG, 0.0), ("short", SPIKES_SHORT, SPIKE_SHORT_Z)):
        for clock in clocks:
            across, outward = clock_frame(clock)
            blade = tapered_box(length * u, (0.12 * u, 0.06 * u), (root[0] * u, root[1] * u), style.material("barrel"))
            # The blade's wide side lies along the radius.
            basis = np.stack([outward, -across, np.array([0.0, 0.0, 1.0])], axis=1)
            centre = radius * u * outward + np.array([0.0, 0.0, (z_tip + 0.5 * length) * u])
            mesh = blade.transformed(basis, centre)
            name = f"spike_{kind}_{cradle_name('', clock)[1:]}"
            shape = col.Shape.box_around(name, mesh.vertices, basis)
            out.append(Built(cv.Piece(part(name, "drum", mesh), side=cv.CENTRE if clock in (0, 180) else cv.RIGHT), (shape,)))
    return out


# --- the rings and their spokes ----------------------------------------------------------------------------------------
def ring(spec: CarrierSpec, style: Style, name: str, dims: tuple[float, float, float, float], sectors: int) -> Built:
    """One ring: an eight-sided section swept round the axis; its collision is ``sectors`` convex pieces."""
    u = spec.u
    z, half, r0, r1 = dims
    z0, z1, b = z - half, z + half, RING_BEVEL
    mid = 0.5 * (r0 + r1)
    profile = [(z0, mid - 0.4), (z0, mid + 0.4), (z0 + b, r1), (z1 - b, r1), (z1, mid + 0.4), (z1, mid - 0.4), (z1 - b, r0), (z0 + b, r0), (z0, mid - 0.4)]
    dark, band = style.material("hull_dark"), style.material("hull")
    mesh = lathe([(a * u, r * u) for a, r in profile], 64, [dark, dark, band, dark, dark, dark, band, dark], creases=range(1, 8))
    shapes = col.ring_sectors(name, (0, 0, 0), (0, 0, 1), r0 * u, r1 * u, z0 * u, z1 * u, sectors)
    return Built(cv.Piece(part(name, name, mesh)), tuple(shapes))


def spoke(spec: CarrierSpec, style: Style, name: str, group: str, dims: tuple[float, float, float, float]) -> Built:
    """The starboard spoke that carries a ring: a tube from the drum to the ring and a block where they meet."""
    u = spec.u
    z, _, r0, _ = dims
    a, b = np.array([DRUM_R * u, 0.0, z * u]), np.array([(r0 + 0.2) * u, 0.0, z * u])
    pipe = tube(a, b, [(0.0, SPOKE_R * u), (float(np.linalg.norm(b - a)), SPOKE_R * u)], 16, style.material("hull_dark"))
    size = np.array(SPOKE_BLOCK) * u
    centre = np.array([(r0 + 0.33) * u - 0.5 * size[0], 0.0, z * u])
    block = box(size, style.material("hull_panel"), centre)
    shapes = (col.Shape.capsule(f"{name}_pipe_r", a + [SPOKE_R * u, 0, 0], b - [SPOKE_R * u, 0, 0], SPOKE_R * u),
              col.Shape.box(f"{name}_block_r", centre, size))
    return Built(cv.Piece(part(f"{name}_r", group, Mesh.concatenate([pipe, block])), side=cv.RIGHT), shapes)


# --- the cradles -------------------------------------------------------------------------------------------------------
def cradle(spec: CarrierSpec, style: Style, c: Cradle, group: str) -> Built:
    """One cradle: the arm standing out from its ring, the beam from its top aft to the pad, the pad a fighter sits on (its
    forward edge the wide one) and the two clamp pins at the pad's ends."""
    u = spec.u
    metal, pad_paint, clamp = style.material("hull_dark"), style.material("stripe"), style.material("rcs")
    basis = c.basis
    arm_len = ARM_LENGTH * u
    root = c.root_r * c.out + np.array([0.0, 0.0, c.arm_z])
    arm = tube(root, root + c.out, [(0.0, ARM_R[0] * u), (0.07 * arm_len, ARM_R[0] * u), (0.23 * arm_len, ARM_R[1] * u), (arm_len, ARM_R[1] * u),
                                    (arm_len, 0.0)], 12, metal, creases=(1, 3))
    # The pad's frame: x across, y out from the ship's axis, z aft; its origin under the pad's centre on the axis.
    r0 = c.root_r + arm_len
    r1 = r0 + PAD_THICK * u
    zf = c.arm_z + PAD_AFT_OF_ARM * u
    zb = zf + PAD_DEPTH * u
    wf, wb = PAD_HALF[0] * u, PAD_HALF[1] * u
    local = []
    inside = (0.0, 0.5 * (r0 + r1), 0.5 * (zf + zb))
    outline = [(-wf, zf), (wf, zf), (wb, zb), (-wb, zb)]
    local.append(flat([(x, r1, z) for x, z in outline], pad_paint, inside))
    local.append(flat([(x, r0, z) for x, z in outline], metal, inside))
    for a, b in zip(outline, outline[1:] + outline[:1], strict=True):
        local.append(flat([(a[0], r0, a[1]), (b[0], r0, b[1]), (b[0], r1, b[1]), (a[0], r1, a[1])], metal, inside))
    bx, by = BRACKET[0] * u, BRACKET[1] * u
    z_from = c.arm_z - ARM_R[1] * u
    local.append(box((bx, by, zf + 0.3 * u - z_from), metal, (0.0, r0 - 0.5 * by, 0.5 * (z_from + zf + 0.3 * u))))
    pw, pt, pl = PIN[0] * u, PIN[1] * u, PIN[2] * u
    pin_z = zf - PIN_AHEAD * u + 0.5 * pl
    reach = PIN_REACH * u
    for side in (1.0, -1.0):
        local.append(box((pw, pt, pl), clamp, (side * (reach - 0.5 * pw), 0.5 * (r0 + r1), pin_z)))
        link = reach - wb
        local.append(box((link, pt, 0.37 * u), clamp, (side * (reach - 0.5 * link), 0.5 * (r0 + r1), pin_z + 0.5 * pl - 0.185 * u)))
    pad = Mesh.concatenate(local).transformed(basis)
    mesh = Mesh.concatenate([arm, pad])
    pad_points = np.array([[s * reach, r, z] for s in (-1.0, 1.0) for r in (r0, r1) for z in (zf - PIN_AHEAD * u, zb)]) @ basis.T
    bracket_points = np.array([[s * 0.5 * bx, r, z] for s in (-1.0, 1.0) for r in (r0 - by, r0) for z in (z_from, zf)]) @ basis.T
    grip = 0.85 * u
    shapes = (
        col.Shape.capsule(f"arm_{c.name}", root + grip * c.out, root + (arm_len - 0.3 * u) * c.out, grip),
        col.Shape.box_around(f"pad_{c.name}", pad_points, basis),
        col.Shape.box_around(f"bracket_{c.name}", bracket_points, basis),
    )
    side = cv.CENTRE if c.clock_deg in (0.0, 180.0) else cv.RIGHT
    return Built(cv.Piece(part(f"cradle_{c.name}", group, mesh), side=side), shapes)


# --- the spine, the centre section and the engine ----------------------------------------------------------------------
def spine(spec: CarrierSpec, style: Style) -> Built:
    u = spec.u
    a, b = np.array([0.0, 0.0, SPINE_Z[0] * u]), np.array([0.0, 0.0, SPINE_Z[1] * u])
    mesh = lathe([(SPINE_Z[0] * u, SPINE_R * u), (SPINE_Z[1] * u - 1.48 * u, SPINE_R * u), (SPINE_Z[1] * u - 1.48 * u, 3.7 * u),
                  (SPINE_Z[1] * u, 3.7 * u)], 20, style.material("hull_dark"), creases=(1, 2))
    shape = col.Shape.hull("spine", col.prism_points((0, 0, 0), (0, 0, 1), [(a[2], 3.2 * u), (b[2], 3.2 * u)], 8))
    return Built(cv.Piece(part("spine", "core", mesh)), (shape,))


def centre_section(spec: CarrierSpec, style: Style) -> list[Built]:
    """Between the boxes: a slab on the centre line, a cross beam at each end, a long bar above and below it on each side."""
    u = spec.u
    deck, dark = style.material("hull_panel"), style.material("hull_dark")
    z0, z1 = BEAMS_Z[0][1] * u, BEAMS_Z[1][0] * u
    slab_size = (2 * SLAB_HALF[0] * u, 2 * SLAB_HALF[1] * u, z1 - z0)
    slab_centre = (0.0, 0.0, 0.5 * (z0 + z1))
    out = [Built(cv.Piece(part("slab", "core", box(slab_size, deck, slab_centre))), (col.Shape.box("slab", slab_centre, slab_size),))]
    beams, shapes = [], []
    for k, (a, b) in enumerate(BEAMS_Z):
        size, centre = (2 * BEAM_HALF[0] * u, 2 * BEAM_HALF[1] * u, (b - a) * u), (0.0, 0.0, 0.5 * (a + b) * u)
        beams.append(box(size, dark, centre))
        shapes.append(col.Shape.box(("beam_fore", "beam_aft")[k], centre, size))
    out.append(Built(cv.Piece(part("beams", "core", Mesh.concatenate(beams))), tuple(shapes)))
    for label, sign in (("top", 1.0), ("bottom", -1.0)):
        size = ((BAR_X[1] - BAR_X[0]) * u, (BAR_Y[1] - BAR_Y[0]) * u, z1 - z0)
        centre = (0.5 * (BAR_X[0] + BAR_X[1]) * u, sign * 0.5 * (BAR_Y[0] + BAR_Y[1]) * u, 0.5 * (z0 + z1))
        out.append(Built(cv.Piece(part(f"bar_{label}_r", "core", box(size, dark, centre)), side=cv.RIGHT), (col.Shape.box(f"bar_{label}_r", centre, size),)))
    return out


def elbows(spec: CarrierSpec, style: Style) -> list[Built]:
    """The pipes from the bars into the boxes: four above and four below on each side, each a riser and a cross pipe."""
    u = spec.u
    x, y, r = ELBOW[0] * u, ELBOW[1] * u, ELBOW[2] * u
    out = []
    for label, sign in (("top", 1.0), ("bottom", -1.0)):
        meshes, shapes = [], []
        for k, z in enumerate(ELBOWS_Z):
            foot, knee, end = np.array([x, sign * BAR_Y[1] * u, z * u]), np.array([x, sign * y, z * u]), np.array([BOX_X[0] * u, sign * y, z * u])
            rise = float(np.linalg.norm(knee - foot))
            meshes.append(tube(foot, knee, [(0.0, r), (rise, r), (rise + 0.6 * r, 0.75 * r), (rise + r, 0.0)], 12, style.material("rcs")))
            meshes.append(tube(knee, end, [(0.0, r), (float(np.linalg.norm(end - knee)), r)], 12, style.material("rcs")))
            lo = np.array([x - r, min(foot[1], sign * (y + r)), z * u - r])
            hi = np.array([BOX_X[0] * u, max(foot[1], sign * (y + r)), z * u + r])
            shapes.append(col.Shape.box(f"elbow_{label}_{k}_r", 0.5 * (lo + hi), hi - lo))
        out.append(Built(cv.Piece(part(f"elbows_{label}_r", "core", Mesh.concatenate(meshes)), side=cv.RIGHT), tuple(shapes)))
    return out


def engine(spec: CarrierSpec, style: Style) -> list[Built]:
    """The engine cluster: the mount disc on the aft beam, four tanks round the centre line, the main engine with its bell and
    petals, its throat glowing."""
    u = spec.u
    metal, dark, throat = style.material("nozzle"), style.material("hull_dark"), style.material("nozzle_throat")
    z0, z1, r = MOUNT[0] * u, MOUNT[1] * u, MOUNT[2] * u
    mount = lathe([(z0, 0.0), (z0, r), (z1, r), (z1, 0.0)], 24, dark, creases=(1, 2))
    mount_shape = col.Shape.hull("engine_mount", col.prism_points((0, 0, 0), (0, 0, 1), [(z0, r), (z1, r)], 12))
    tanks, tank_shapes = [], []
    ends = (TANK_PROFILE[0][0] * u, TANK_PROFILE[-1][0] * u)
    tank_r = max(p[1] for p in TANK_PROFILE) * u
    for k, clock in enumerate((0, 90, 180, 270)):
        _, outward = clock_frame(clock)
        offset = TANK_OFFSET * u * outward
        tanks.append(lathe([(a * u, b * u) for a, b in TANK_PROFILE], 16, style.material("hull_panel")).translated(offset))
        tank_shapes.append(col.Shape.capsule(f"tank_{k}", offset + [0, 0, ends[0] + tank_r], offset + [0, 0, ends[1] - tank_r], tank_r))
    bell = lathe([(a * u, b * u) for a, b in ENGINE_PROFILE], 24, [metal, metal, metal, metal, dark, throat], creases=(1, 2, 3, 4, 5))
    petals = []
    size, radius, z = np.array(PETAL[0]) * u, PETAL[1] * u, PETAL[2] * u
    for clock in (0, 90, 180, 270):
        across, outward = clock_frame(clock)
        basis = np.stack([across, outward, np.array([0.0, 0.0, 1.0])], axis=1)
        petals.append(box(size, metal).transformed(basis, radius * outward + np.array([0.0, 0.0, z])))
    lip = (PETAL[1] + 0.5 * PETAL[0][1]) * u
    bell_shape = col.Shape.hull("engine_bell", col.prism_points((0, 0, 0), (0, 0, 1), [(z1, 1.2 * u), (ENGINE_PROFILE[2][0] * u, lip), (spec.length_m, lip)], 8))
    return [
        Built(cv.Piece(part("engine_mount", "core", mount)), (mount_shape,)),
        Built(cv.Piece(part("tanks", "core", Mesh.concatenate(tanks))), tuple(tank_shapes)),
        Built(cv.Piece(part("engine", "core", Mesh.concatenate([bell, *petals]))), (bell_shape,)),
    ]


# --- a box hull --------------------------------------------------------------------------------------------------------
def _outline(points: Sequence[tuple[float, float]]) -> np.ndarray:
    """A closed side-view outline from its top half: the bottom half mirrors it."""
    top = [(z, y) for z, y in points]
    return np.array([(z, -y) for z, y in top] + [(z, y) for z, y in reversed(top)])


def box_hull(spec: CarrierSpec, style: Style) -> Built:
    """The starboard box: nose block and body in one skin, the decks plated, five hangar slats sunk into the outer flank."""
    u = spec.u
    flank, deck, recess, glow = style.material("hull"), style.material("hull_panel"), style.material("hull_dark"), style.material("hazard")
    x0, x1, xs = BOX_X[0] * u, BOX_X[1] * u, SLOT_X * u
    body = _outline(BOX_BODY) * u
    nose = _outline(BOX_NOSE) * u
    # The whole outline, bow face first; the decks (the sloped top and bottom of the body) take the plating.
    whole = np.array([*[(z, -y) for z, y in (*BOX_NOSE, *BOX_BODY[1:])], *[(z, y) for z, y in reversed((*BOX_NOSE, *BOX_BODY[1:]))]]) * u
    decks = {2: deck, 6: deck}
    walls = extrude_x(whole, x0, x1, flank, (None, None), decks)
    inside = (0.5 * (x0 + x1), 0.0, 65.0 * u)
    inner = [flat([(x0, y, z) for z, y in poly], flank, inside) for poly in (nose, body)]
    # The outer flank: the nose, then the body tiled round the five slots.
    sz0, sz1, half = SLOT_Z[0] * u, SLOT_Z[1] * u, SLOT_HALF * u
    tiles = [nose, clip(body, 0, sz0, False), clip(body, 0, sz1, True)]
    band = clip(clip(body, 0, sz0, True), 0, sz1, False)
    edges = [-math.inf, *[v for y in SLOTS_Y for v in (y * u - half, y * u + half)], math.inf]
    for lo, hi in zip(edges[0::2], edges[1::2], strict=True):
        strip = band
        if math.isfinite(lo):
            strip = clip(strip, 1, lo, True)
        if math.isfinite(hi):
            strip = clip(strip, 1, hi, False)
        tiles.append(strip)
    outer = [flat([(x1, y, z) for z, y in tile], flank, inside) for tile in tiles]
    slots = []
    for y in SLOTS_Y:
        lo, hi = y * u - half, y * u + half
        slots.append(flat([(xs, lo, sz0), (xs, hi, sz0), (xs, hi, sz1), (xs, lo, sz1)], glow, inside))
        for a, b in (((lo, sz0), (lo, sz1)), ((hi, sz0), (hi, sz1)), ((lo, sz0), (hi, sz0)), ((lo, sz1), (hi, sz1))):
            quad = np.array([(xs, a[0], a[1]), (xs, b[0], b[1]), (x1, b[0], b[1]), (x1, a[0], a[1])])
            centre = np.array([0.5 * (xs + x1), y * u, 0.5 * (sz0 + sz1)])
            slots.append(flat(quad, recess, 2.0 * quad.mean(axis=0) - centre))
        for z in SLAT_BARS_Z:
            slots.append(box((SLAT_BAR[0] * u, 2.0 * half, SLAT_BAR[1] * u), recess, (xs + 0.5 * SLAT_BAR[0] * u, y * u, z * u)))
    mesh = Mesh.concatenate([walls, *inner, *outer, *slots])
    body_points = np.array([(x, y, z) for x in (x0, x1) for z, y in body])
    nose_points = np.array([(x, y, z) for x in (x0, x1) for z, y in nose])
    shapes = (col.Shape.hull("box_body_r", body_points), col.Shape.hull("box_nose_r", nose_points))
    return Built(cv.Piece(part("box_r", "box_r", mesh), side=cv.RIGHT), shapes)


def box_fittings(spec: CarrierSpec, style: Style) -> list[Built]:
    """On the starboard box: the plate across its bow face, a knob on the top deck and one under the keel, the fitting under
    the bow slope, and the four skirt fins under the stern slope."""
    u = spec.u
    deck, dark = style.material("hull_panel"), style.material("hull_dark")
    x0, x1 = BOX_X[0] * u, BOX_X[1] * u
    za, zb, half = FRONT_PLATE[0] * u, FRONT_PLATE[1] * u, FRONT_PLATE[2] * u
    plate_size, plate_centre = (x1 - x0, 2.0 * half, zb - za), (0.5 * (x0 + x1), 0.0, 0.5 * (za + zb))
    out = [Built(cv.Piece(part("box_plate_r", "box_r", box(plate_size, dark, plate_centre)), side=cv.RIGHT),
                 (col.Shape.box("box_plate_r", plate_centre, plate_size),))]
    base, top, centre = np.array(KNOB[0]) * u, np.array(KNOB[1]) * u, np.array(KNOB[2]) * u
    up = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]])  # the taper runs up
    knob = tapered_box(base[1], (base[0], base[2]), (top[0], top[1]), deck).transformed(up, centre)
    knobs = [knob, mirrored_y(knob)]
    knob_shapes = (col.Shape.box("knob_top_r", centre, base), col.Shape.box("knob_keel_r", centre * [1, -1, 1], base))
    out.append(Built(cv.Piece(part("box_knobs_r", "box_r", Mesh.concatenate(knobs)), side=cv.RIGHT), knob_shapes))
    size, at = np.array(GADGET[0]) * u, np.array(GADGET[1]) * u
    out.append(Built(cv.Piece(part("box_gadget_r", "box_r", box(size, dark, at)), side=cv.RIGHT), (col.Shape.box("box_gadget_r", at, size),)))
    profile = np.array(FIN_PROFILE) * u
    fins, fin_shapes = [], []
    for k, (a, b) in enumerate(FIN_X):
        fins.append(extrude_x(profile, a * u, b * u, dark, (dark, dark)))
        fin_shapes.append(col.Shape.hull(f"fin_{k}_r", np.array([(x * u, y, z) for x in (a, b) for z, y in profile])))
    out.append(Built(cv.Piece(part("box_fins_r", "box_r", Mesh.concatenate(fins)), side=cv.RIGHT), tuple(fin_shapes)))
    return out


# --- the whole ship ----------------------------------------------------------------------------------------------------
RING_SECTORS = {"ring_mid": 12, "ring_outer": 16}
CRADLE_GROUP = {"outer": "ring_outer", "mid": "ring_mid", "drum": "drum"}


def assemble(spec: CarrierSpec, style: Style) -> list[Built]:
    """Every piece in the authored frame, centre-line pieces and the starboard one of each pair."""
    built = [drum(spec, style), bow_fittings(spec, style), *spikes(spec, style)]
    for name, dims in (("ring_mid", RING_MID), ("ring_outer", RING_OUTER)):
        built += [ring(spec, style, name, dims, RING_SECTORS[name]), spoke(spec, style, f"spoke_{name[5:]}", name, dims)]
    built += [cradle(spec, style, c, CRADLE_GROUP[c.ring]) for c in cradles(spec, both_sides=False)]
    built += [spine(spec, style), *centre_section(spec, style), *elbows(spec, style), *engine(spec, style)]
    built += [box_hull(spec, style), *box_fittings(spec, style)]
    return built


__all__ = ["Built", "CarrierSpec", "Cradle", "assemble", "clock_frame", "cradle_name", "cradles"]
