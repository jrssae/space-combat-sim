"""Saturn family parts (docs/assets-civilian.md "saturn_family", docs/design-references.md "Saturn family", Q16).

Every part has one size on every variant: the lead ship (antenna, command disc, forward truss, drum frame, engine
section) and the cargo (a transport section: hull cylinder, arms, rails and pods; a tank section: three tanks). The
variants differ only in how many sections they carry and of which kind (``assets/saturn_family.py``).

Frame: x to starboard, y up from the spine axis, z aft from the nose tip, metres (Godot's axes). Parts come as
:class:`Piece`s: a part, the volume that hides whatever other pieces push into it, and whether the piece stands on the
centre line (sampled once and symmetrised) or on the right (mirrored to the left by the asset). A piece's ``group``
says which assembly it belongs to; the asset turns that into a break-up chunk.
"""

from __future__ import annotations

import math
from collections.abc import Callable, Sequence
from dataclasses import dataclass, replace

import numpy as np

from ..core.geometry import (
    Material,
    Mesh,
    assign_material_by_predicate,
    basis_from_z,
    box,
    inset_convex_polygon,
    lathe,
    loft,
    prism,
    rotation_x,
    rotation_y,
    sweep_rect,
)
from ..styles import Style
from ..styles.ea_civilian import lin
from . import Collision, Part
from .propulsion import NozzleSpec, nozzle
from .solids import Solid, box_solid, difference, lathe_solid, prism_solid, union
from .narn import LoftSolid
from .starfury import outward, section_loft
from .wing import vent_grille

CENTRE, RIGHT = "c", "r"
_Z_TO_Y = rotation_x(-0.5 * math.pi)  # local +Z to +Y
_SECTION_STEPS = 64  # round sections of the big drums

# --- the lead ship (design references, "Lead ship") -------------------------------------------------------------
DISC_CENTRE_Z = 19.1
DISC_RADIUS = 14.13
DISC_THICKNESS = 6.0  # at the centre
DISC_RIM = 1.0  # the least thickness, at the rim (the reference's edge reads about 1.3 m 0.3 m in)
DISC_CUT_Z = 29.6  # the aft quarter is cut square here
NECK_END_Z = 32.6  # the neck's box ends here on the reference's sections
HUB_RADIUS = 2.5
HUB_TOP_Y = 3.8  # the dorsal_fwd turret stands on the hub
FIN_RADII = (2.5, 7.3)  # the reference's fins end before r 8 m (planned 8.7)
RUST_RING_RADII = (2.5, 11.0)
WINDOW_HALF_HEIGHT = 0.3
# Aft of z 22 the disc's edge is straight, not round (the reference's top silhouette): half-widths at these z.
DISC_CHAMFER = ((22.0, 13.75), (23.77, 12.0), (28.53, 10.2), (DISC_CUT_Z, 9.8))
# A wedge in each cut corner (plan x, z), 2.8 m tall: its outer face runs from the disc's edge in to the neck.
CORNER_WEDGE = ((5.97, 22.6), (12.63, 22.6), (6.6, 30.39), (5.97, 30.39))
CORNER_WEDGE_HEIGHT = 2.8  # the cut corners read 2.8 m thick on the reference's sections (T12 fix)
# The neck behind the cut, a box measured off the reference's sections: (z, half-width, half-height).
NECK_SECTIONS = ((28.4, 5.73, 2.27), (31.75, 5.73, 1.46), (32.05, 5.33, 1.33), (NECK_END_Z, 4.3, 1.0))
NECK_KEEL = ((1.3, 2.4, 1.7), (0.0, -2.5, 30.65))  # size, centre: the block under the neck's end
NECK_BRACKET = ((2.7, 2.6, 0.8), (2.7, 2.1, 31.0))  # where the upper tube and beam leave the neck (right; mirrored)
RETRO_EXIT = (9.51, 0.0, 8.56)
RETRO_RADIUS = 0.95
COCKPIT_EYE = (0.0, 0.8, 8.0)
ANTENNA_Y = -4.4
DISH_RADIUS = 3.6
TRUSS_SIDE = 6.3
LONGERON_RADIUS = 0.3
BRACE_RADIUS = 0.2
DRUM_FRAME_Z = (41.9, 50.1)
TOP_DRUM = (0.0, 5.55)
LOWER_DRUM = (9.27, -10.55)
TRUSS_DRUM = (0.0, -5.18)
DRUM_RADIUS = 1.6
TRUSS_DRUM_RADIUS = 2.0
TRUSS_DRUM_NECK_R = 1.2
ENGINE_LENGTH = 22.6
COLLAR_RADIUS = 4.8
COLLAR_LENGTH = 6.5
ENGINE_RCS_Z = 3.0  # behind the collar's front
ENGINE_RCS_RADIUS = 4.78
BELL = NozzleSpec(throat_r=1.55, exit_r=3.15, length=6.4, wall=0.15, segments=48, profile_steps=8)
MAIN_RADIUS = 2.2  # each half of the split bell

# --- cargo (z from the section's start) ---------------------------------------------------------------------------
SECTION_LENGTH = 100.0
CYLINDER_Z = (12.35, 87.83)
CYLINDER_RADIUS = 17.53 / 2.0
DOME_DEPTH = 5.9
POD_Z = ((3.49, 46.51), (53.49, 96.51))
POD_INBOARD_X = 22.03
POD_CENTRE_Y = -7.29
ARM_X = (9.52, 22.52)
ARM_Y = (-10.43, -5.96)
ARM_Z = ((22.06, 28.02), (72.06, 78.02))
LOWER_TANK = (16.51, -13.53)


@dataclass
class Piece:
    """One sampled component. ``side`` is :data:`CENTRE` or :data:`RIGHT`; ``fine`` scales the sampling spacing (small
    parts at the extremes, like the antenna, are sampled finer so they still show)."""

    part: Part
    solid: Solid | None = None
    side: str = CENTRE
    fine: float = 1.0

    @property
    def name(self) -> str:
        return self.part.name

    @property
    def group(self) -> str:
        return self.part.group

    def transformed(self, rotation: np.ndarray, translation: Sequence[float] = (0.0, 0.0, 0.0)) -> Piece:
        solid = None if self.solid is None else self.solid.transformed(rotation, translation)
        return Piece(self.part.transformed(rotation, translation), solid, self.side, self.fine)

    def translated(self, offset: Sequence[float]) -> Piece:
        return self.transformed(np.eye(3), offset)

    def mirrored(self, name: str, group: str) -> Piece:
        """The left twin of a right piece."""
        solid = None if self.solid is None else self.solid.mirrored("x")
        return Piece(self.part.mirrored("x").renamed(name, group=group), solid, self.side, self.fine)



def _piece(
    name: str,
    mesh: Mesh,
    solid: Solid | None = None,
    side: str = CENTRE,
    group: str = "",
    mass_kg: float = 0.0,
    collision: list[Collision] | None = None,
    fine: float = 1.0,
) -> Piece:
    return Piece(Part(name, mesh, {}, list(collision or []), mass_kg, group), solid, side, fine)


# --- small geometry helpers -----------------------------------------------------------------------------------------
def tube(a: Sequence[float], b: Sequence[float], radius: float, material: Material, segments: int = 10) -> Mesh:
    """A capped round bar from ``a`` to ``b``."""
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    length = float(np.linalg.norm(b - a))
    mesh = lathe([(0.0, 0.0), (0.0, radius), (length, radius), (length, 0.0)], segments, material, creases={1, 2})
    return mesh.transformed(basis_from_z(b - a), a)


def bar(path: Sequence[Sequence[float]], width_axis: Sequence[float], width: float, thickness: float, material: Material) -> Mesh:
    """A square-cut bar along a polyline (``width_axis`` must be perpendicular to the whole path)."""
    p = np.asarray(path, dtype=float)
    return sweep_rect(p, width_axis, [width] * len(p), [thickness] * len(p), material)


def lathe_y(profile: Sequence[tuple[float, float]], segments: int, materials: Material | Sequence[Material], creases=()) -> Mesh:
    """A lathe about +Y (``profile`` is ``(y, r)``)."""
    return lathe(profile, segments, materials, creases=creases).transformed(_Z_TO_Y)


def _cells(length: float, cell: float) -> list[float]:
    n = max(1, round(length / cell))
    return list(np.linspace(0.0, 1.0, n + 1))


def walls(
    loop: np.ndarray,
    ws: Sequence[float],
    material: Callable[[int, int, int, float, float], Material],
    breaks: Callable[[int, float], Sequence[float]] | None = None,
    inward: bool = False,
) -> Mesh:
    """The side walls of a convex counter-clockwise outline (local X/Y) swept along local Z through the stations ``ws``.

    Each wall is a grid of cells so paint can follow it: ``breaks(edge, length)`` gives the cuts along an edge (0 to 1)
    and ``material(edge, i, j, t, w)`` paints cell ``i`` along the edge and ``j`` along Z (``t``, ``w`` its middle).
    Walls face out of the outline, or into it with ``inward`` (a recess)."""
    loop = np.asarray(loop, dtype=float)
    verts: list[np.ndarray] = []
    faces: list[list[int]] = []
    mats: list[Material] = []
    for e in range(len(loop)):
        a, b = loop[e], loop[(e + 1) % len(loop)]
        length = float(np.linalg.norm(b - a))
        ts = list(breaks(e, length)) if breaks else _cells(length, 3.6)
        start = sum(len(v) for v in verts)
        grid = np.array([[[*(a + t * (b - a)), w] for w in ws] for t in ts])  # (nt, nw, 3)
        verts.append(grid.reshape(-1, 3))
        nw = len(ws)
        for i in range(len(ts) - 1):
            for j in range(nw - 1):
                p00, p10 = start + i * nw + j, start + (i + 1) * nw + j
                p11, p01 = p10 + 1, p00 + 1
                tris = [[p00, p10, p11], [p00, p11, p01]]
                faces += [t[::-1] for t in tris] if inward else tris
                m = material(e, i, j, 0.5 * (ts[i] + ts[i + 1]), 0.5 * (ws[j] + ws[j + 1]))
                mats += [m, m]
    return _mesh(np.concatenate(verts), faces, mats)


def ring_face(outer: np.ndarray, inner: np.ndarray, w: float, facing: float, material: Material) -> Mesh:
    """The flat band between two outlines with matching corners, at ``z = w``, facing +Z or -Z."""
    n = len(outer)
    verts = np.array([[*p, w] for p in outer] + [[*p, w] for p in inner])
    faces = []
    for i in range(n):
        j = (i + 1) % n
        tris = [[i, j, n + j], [i, n + j, n + i]]
        faces += tris if facing > 0 else [t[::-1] for t in tris]
    return Mesh(verts, faces, np.zeros(len(faces), dtype=np.int64), (material,))


def polygon_face(poly: np.ndarray, w: float, facing: float, material: Material) -> Mesh:
    """A convex outline filled at ``z = w``, facing +Z or -Z."""
    n = len(poly)
    verts = np.array([[*p, w] for p in poly] + [[*np.mean(poly, axis=0), w]])
    faces = []
    for i in range(n):
        tri = [n, i, (i + 1) % n]
        faces.append(tri if facing > 0 else tri[::-1])
    return Mesh(verts, faces, np.zeros(len(faces), dtype=np.int64), (material,))


def _mesh(verts: np.ndarray, faces: list[list[int]], mats: list[Material]) -> Mesh:
    table: list[Material] = []
    index = []
    for m in mats:
        if m not in table:
            table.append(m)
        index.append(table.index(m))
    return Mesh(verts, np.array(faces), np.array(index), tuple(table))


def _hash01(*ints: int) -> float:
    h = 2166136261
    for v in ints:
        h = ((h ^ (v & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    return h / 4294967296.0


def hexagon(width: float, height: float) -> np.ndarray:
    """A hexagon with flat top and bottom and points at the sides, counter-clockwise."""
    hw, hh = 0.5 * width, 0.5 * height
    top = hw - hh * math.tan(math.radians(30.0))
    return np.array([(hw, 0.0), (top, hh), (-top, hh), (-hw, 0.0), (-top, -hh), (top, -hh)])


def hex_module(
    width: float, height: float, length: float, style: Style, recessed: bool = False
) -> tuple[Mesh, Solid]:
    """A hexagonal prism along local Z from 0 to ``length``; ``recessed`` paints two dark panels on each face."""
    outline = hexagon(width, height)
    hull, dark = style.material("hull"), style.material("hull_dark")
    if recessed:
        ws = [0.0, 0.07 * length, 0.46 * length, 0.54 * length, 0.93 * length, length]

        def paint(e: int, i: int, j: int, t: float, w: float) -> Material:
            return dark if i == 1 and j in (1, 3) else hull

        mesh = walls(outline, ws, paint, breaks=lambda e, n: [0.0, 0.15, 0.85, 1.0])
    else:
        ws = list(np.linspace(0.0, length, max(2, round(length / 3.6)) + 1))
        mesh = walls(outline, ws, lambda *_: hull)
    ends = [polygon_face(outline, 0.0, -1.0, hull), polygon_face(outline, length, 1.0, hull)]
    return Mesh.concatenate([mesh, *ends]), prism_solid(outline, 0.0, length)


# --- antenna ----------------------------------------------------------------------------------------------------------
def antenna(style: Style) -> list[Piece]:
    """A dish facing forward with a spike in front, held to the disc's underside by a steep strut and a wider shallow bar
    that meet a mounting plate (the reference's sections)."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    r = DISH_RADIUS
    profile = [(5.0, 0.0), (4.85, 1.3), (4.4, 2.5), (3.8, r), (3.8, r + 0.15), (4.4, 2.9), (5.0, 1.8), (5.5, 0.0)]
    dish = outward(lathe(profile, 40, [hull, hull, hull, dark, dark, dark, dark], creases={3, 4})).translated((0.0, ANTENNA_Y, 0.0))
    spike = outward(lathe([(0.0, 0.0), (0.0, 0.1), (5.1, 0.36), (5.1, 0.0)], 16, dark, creases={1, 2})).translated((0.0, ANTENNA_Y, 0.0))
    boom = Mesh.concatenate([
        bar([(0.0, -4.3, 6.2), (0.0, -2.2, 8.9)], (1.0, 0.0, 0.0), 0.54, 0.6, hull),
        bar([(0.0, -4.4, 6.0), (0.0, -3.45, 10.5)], (1.0, 0.0, 0.0), 1.6, 0.8, hull),
        box((5.2, 1.15, 3.3), hull, center=(0.0, -2.4, 10.4)),
    ])  # fmt: skip
    box_size = (2.0 * r + 0.3, 2.0 * r + 0.3, 5.5)
    hit = Collision("box", (0.0, ANTENNA_Y, 2.75), size=box_size)
    return [
        _piece("antenna_dish", dish, mass_kg=12_000.0, collision=[hit], fine=0.5),
        _piece("antenna_spike", spike, fine=0.25),  # the nose: thin, and the ship's forward extreme on every level
        _piece("antenna_boom", boom, fine=0.5),
    ]


# --- command disc -----------------------------------------------------------------------------------------------------
def lens_thickness(r: np.ndarray | float) -> np.ndarray:
    """The disc's full thickness at radius ``r`` from its centre: an elliptic section, 6.0 m in the middle, as the
    reference's sections read (4.6 m at r 9, 3.7 m at r 11), kept ``DISC_RIM`` thick at the rim for its window band."""
    q = np.clip(1.0 - (np.asarray(r, dtype=float) / DISC_RADIUS) ** 2, 0.0, 1.0)
    return np.maximum(DISC_RIM, DISC_THICKNESS * np.sqrt(q))


def disc_half_width(z: np.ndarray | float) -> np.ndarray:
    """The disc's plan: a circle 28.3 m across, its aft quarter chamfered (``DISC_CHAMFER``)."""
    z = np.asarray(z, dtype=float)
    circle = np.sqrt(np.clip(DISC_RADIUS**2 - (z - DISC_CENTRE_Z) ** 2, 0.0, None))
    zs, ws = zip(*DISC_CHAMFER, strict=True)
    chamfer = np.where(z >= zs[0], np.interp(z, zs, ws), np.inf)
    return np.minimum(circle, chamfer)


def _lens_ring(theta: float, across: int) -> np.ndarray:
    """One section of the lens at the angle ``theta`` round its plan circle from the nose (counter-clockwise from +Z)."""
    z = DISC_CENTRE_Z - DISC_RADIUS * math.cos(theta)
    w = float(disc_half_width(z))
    d = z - DISC_CENTRE_Z
    phi = np.linspace(0.0, math.pi, across + 1)
    x_top = w * np.cos(phi)
    y_top = 0.5 * lens_thickness(np.hypot(x_top, d))
    h = WINDOW_HALF_HEIGHT
    top = np.column_stack([x_top, y_top])
    bottom = np.column_stack([x_top[::-1], -y_top[::-1]])
    ring = np.concatenate([top, [(-w, h), (-w, -h)], bottom, [(w, -h), (w, h)]])
    return np.column_stack([ring, np.full(len(ring), z)])


def lens_solid() -> Solid:
    """Inside the lens: within the plan circle ahead of the cut and within its thickness."""

    def test(p: np.ndarray, margin: float) -> np.ndarray:
        d = p[:, 2] - DISC_CENTRE_Z
        r = np.hypot(p[:, 0], d)
        inside_plan = np.abs(p[:, 0]) < disc_half_width(p[:, 2]) - margin
        return inside_plan & (p[:, 2] < DISC_CUT_Z - margin) & (np.abs(p[:, 1]) < 0.5 * lens_thickness(r) - margin)

    c, R = DISC_CENTRE_Z, DISC_RADIUS
    return Solid(test, ((-R, -0.5 * DISC_THICKNESS, c - R), (R, 0.5 * DISC_THICKNESS, DISC_CUT_Z)))


def command_disc(style: Style) -> list[Piece]:
    """The control section: a lens 28.3 m across centred at z 19.1, its aft quarter chamfered and cut square at z 29.6
    with a neck tapering to the frames, a white hub and 12 dark radial fins on each face, a rust-red ring on the top, rim
    windows and a wedge in each cut corner; its two retro nozzles sit on the front rim."""
    hull = style.material("hull")
    theta_cut = math.acos((DISC_CENTRE_Z - DISC_CUT_Z) / DISC_RADIUS)
    rings = 96
    across = 64
    thetas = np.linspace(0.0, theta_cut, rings + 1)
    sections = [_lens_ring(float(t), across) for t in thetas]
    lens = outward(loft(sections, hull, cap_start=False, cap_end=True))
    # Paint: the rim's window band (two windows to every frame), the rust ring round the top hub.
    per_ring = 2 * len(sections[0])
    ring_index = np.arange(lens.face_count) // per_ring
    cent, normal = lens.face_centroids(), lens.face_normals()
    on_rim = (np.abs(cent[:, 1]) < WINDOW_HALF_HEIGHT + 1e-6) & (np.abs(normal[:, 1]) < 0.5) & (ring_index < rings)
    lens = assign_material_by_predicate(lens, style.material("window"), on_rim & (ring_index % 3 != 0))
    radial = np.hypot(cent[:, 0], cent[:, 2] - DISC_CENTRE_Z)
    on_top = normal[:, 1] > 0.5
    rust = on_top & (radial > RUST_RING_RADII[0]) & (radial < RUST_RING_RADII[1])
    lens = assign_material_by_predicate(lens, style.material("disc_ring"), rust)
    hit = Collision("box", (0.0, 0.0, 0.5 * (DISC_CENTRE_Z - DISC_RADIUS + NECK_END_Z)),
                    size=(2.0 * DISC_RADIUS, 2.0 * HUB_TOP_Y, NECK_END_Z - DISC_CENTRE_Z + DISC_RADIUS))
    pieces = [_piece("disc", lens, lens_solid(), mass_kg=1_400_000.0, collision=[hit])]

    rings = [np.array([(-w, -h, z), (w, -h, z), (w, h, z), (-w, h, z)]) for z, w, h in NECK_SECTIONS]
    neck = section_loft(rings, [hull] * 4, hull)
    neck_loft = LoftSolid(2, tuple(z for z, _w, _h in NECK_SECTIONS), tuple(r[:, :2] for r in rings))
    w0, h0 = NECK_SECTIONS[0][1], NECK_SECTIONS[0][2]
    neck_solid = Solid(lambda q, m: neck_loft.contains(q, m), ((-w0, -h0, NECK_SECTIONS[0][0]), (w0, h0, NECK_END_Z)))
    pieces.append(_piece("disc_neck", neck, neck_solid, mass_kg=60_000.0))
    for name, (size, centre) in (("neck_keel", NECK_KEEL), ("neck_bracket", NECK_BRACKET)):
        side = RIGHT if centre[0] > 0.0 else CENTRE
        pieces.append(_piece(name if side == CENTRE else f"{name}_r", box(size, hull, center=centre), box_solid(size, centre),
                             side=side, mass_kg=8_000.0))  # fmt: skip

    # Hubs: the top one is white and carries the forward dorsal turret.
    top_hub = lathe_y([(2.6, 0.0), (2.6, HUB_RADIUS), (HUB_TOP_Y - 0.2, HUB_RADIUS), (HUB_TOP_Y, HUB_RADIUS - 0.2), (HUB_TOP_Y, 0.0)],
                      40, style.material("disc_hub"), creases={1, 2, 3})
    bottom_hub = lathe_y([(-3.9, 0.0), (-3.9, HUB_RADIUS - 0.2), (-3.7, HUB_RADIUS), (-2.6, HUB_RADIUS), (-2.6, 0.0)], 40, hull, creases={1, 2, 3})
    for name, mesh, (y0, y1) in (("disc_hub_top", top_hub, (2.6, HUB_TOP_Y)), ("disc_hub_bottom", bottom_hub, (-3.9, -2.6))):
        solid = lathe_solid([(y0, HUB_RADIUS), (y1, HUB_RADIUS)]).transformed(_Z_TO_Y)
        pieces.append(_piece(name, mesh.translated((0.0, 0.0, DISC_CENTRE_Z)), solid.translated((0.0, 0.0, DISC_CENTRE_Z)), mass_kg=15_000.0))

    fin = style.material("disc_fin")
    for name, sign in (("disc_fins_top", 1.0), ("disc_fins_bottom", -1.0)):
        fins = []
        for k in range(12):
            a = math.radians(30.0 * k)
            radial_dir = np.array([math.sin(a), 0.0, math.cos(a)])
            # The reference's top fins stand taller near the hub; the bottom ones a little lower off the lens throughout.
            lifts = (0.7, 0.45, 0.25) if sign > 0.0 else (0.2, 0.2, 0.2)
            path = [radial_dir * rho + (0.0, sign * (0.5 * float(lens_thickness(rho)) + lift), DISC_CENTRE_Z)
                    for rho, lift in zip((FIN_RADII[0] - 0.1, 0.5 * sum(FIN_RADII), FIN_RADII[1]), lifts, strict=True)]
            fins.append(bar(path, (math.cos(a), 0.0, -math.sin(a)), 0.55, 1.6, fin))
        pieces.append(_piece(name, Mesh.concatenate(fins), mass_kg=10_000.0))

    # The wedge is a prism in the plan (x, -z), its thickness standing along y.
    plan = np.array([(x, -z) for x, z in CORNER_WEDGE])
    turn = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]])
    wedge = prism([(plan, hull)], [(plan, hull)], CORNER_WEDGE_HEIGHT).transformed(turn)
    wedge_solid = prism_solid(plan, -0.5 * CORNER_WEDGE_HEIGHT, 0.5 * CORNER_WEDGE_HEIGHT).transformed(turn)
    pieces.append(_piece("corner_wedge", wedge, wedge_solid, side=RIGHT, mass_kg=40_000.0))
    retro_spec = NozzleSpec(throat_r=0.5, exit_r=RETRO_RADIUS, length=1.4, wall=0.1, segments=24, profile_steps=4)
    retro = nozzle(retro_spec, style).transformed(rotation_y(math.pi), (RETRO_EXIT[0], RETRO_EXIT[1], RETRO_EXIT[2] + retro_spec.length))
    pieces.append(_piece("retro", retro.mesh, side=RIGHT, mass_kg=2_000.0))
    return pieces


# --- truss ------------------------------------------------------------------------------------------------------------
def _longerons() -> tuple[np.ndarray, np.ndarray]:
    """The bottom and the right-top longeron's (x, y): a triangle 6.3 m across, apex down, centred on the spine axis."""
    circum = TRUSS_SIDE / math.sqrt(3.0)
    return np.array([0.0, -circum]), np.array([0.5 * TRUSS_SIDE, 0.5 * circum])


def truss(stations: Sequence[float], style: Style, name: str = "truss") -> list[Piece]:
    """Three longerons with V braces on the sides and X braces across the top, one bay between each pair of
    ``stations`` (z). Its hit box rides on the bottom longeron."""
    hull = style.material("hull")
    (bx, by), (rx, ry) = _longerons()
    z0, z1 = stations[0], stations[-1]
    bottom = tube((bx, by, z0), (bx, by, z1), LONGERON_RADIUS, hull)
    side = [tube((rx, ry, z0), (rx, ry, z1), LONGERON_RADIUS, hull)]
    top = []
    for a, b in zip(stations[:-1], stations[1:], strict=True):
        m = 0.5 * (a + b)
        side += [tube((bx, by, a), (rx, ry, m), BRACE_RADIUS, hull), tube((rx, ry, m), (bx, by, b), BRACE_RADIUS, hull)]
        top += [tube((-rx, ry, a), (rx, ry, b), BRACE_RADIUS, hull), tube((rx, ry, a), (-rx, ry, b), BRACE_RADIUS, hull)]
    reach = LONGERON_RADIUS
    lo = (-rx - reach, by - reach)
    hi = (rx + reach, ry + reach)
    hit = Collision("box", (0.0, 0.5 * (lo[1] + hi[1]), 0.5 * (z0 + z1)), size=(hi[0] - lo[0], hi[1] - lo[1], z1 - z0))
    return [
        _piece(f"{name}_bottom", bottom, mass_kg=25_000.0, collision=[hit]),
        _piece(f"{name}_side", Mesh.concatenate(side), side=RIGHT, mass_kg=30_000.0),
        _piece(f"{name}_top", Mesh.concatenate(top), mass_kg=15_000.0),
    ]


# The forward frame, traced member by member off the reference's sections (x from the centre line, y from the spine axis):
# an upper tube on each side rising to the top drum; an upper beam on each side that forks at z 37 into two bars falling
# to the drum frame's middle; a centre beam that forks into two bars rising to the same place; a lower bar falling to
# the truss drum. Beam sections are (width across x, height).
FWD_TUBE = ((2.95, 2.9, 31.6), (2.95, 5.35, 40.6), 0.42)  # from, to, radius
FWD_UPPER_BEAM = ((3.06, 2.1, 31.4), (3.06, 2.45, 37.0))  # the trunk; then the two branches
FWD_UPPER_BRANCHES = (((2.09, 1.97, 38.0), (2.09, 0.81, 40.0), (2.09, 0.1, 42.2)), ((4.18, 1.97, 38.0), (4.18, 0.81, 40.0), (4.18, 0.1, 42.2)))
FWD_CENTRE_BEAM = ((0.0, -2.1, 31.8), (0.0, -2.45, 37.0))
FWD_CENTRE_BRANCH = ((0.98, -1.9, 38.0), (1.0, -0.65, 40.0), (1.0, 0.1, 42.2))
FWD_LOWER_BAR = ((0.0, -3.05, 31.8), (0.0, -4.75, 41.4))
BEAM_SECTION = (0.95, 1.15)
LOWER_BAR_SECTION = (1.1, 1.2)
# Beside the top drum, fore and aft of the drum frame: a box and an upright plate on each side, and a cross plate in front.
SIDE_BOX = ((2.58, 1.98), (3.46, 5.16))  # (width, height), (x, y)
SIDE_BOX_Z = ((39.0, 41.7), (50.5, 52.9))
SIDE_PLATE = ((0.99, 5.37), (5.25, 2.28))
SIDE_PLATE_Z = ((41.0, 41.7), (50.5, 51.2))
CROSS_PLATE = ((10.34, 1.0, 0.4), (0.0, 5.25, 41.9))  # size, centre
# Two thin plates crossed ahead of the top drum (upright on the centre line and level through its axis), z 39.8 to 42.
DRUM_CROSS = (((0.12, 3.2, 2.2), (0.0, 5.55, 40.9)), ((3.8, 0.12, 2.2), (0.0, 5.54, 40.9)))


def _beam(points: Sequence[Sequence[float]], section: tuple[float, float], material: Material) -> Mesh:
    """A bar of rectangular section along a polyline in a vertical plane (its width across x)."""
    w, h = section
    meshes = []
    for a, b in zip(points[:-1], points[1:], strict=True):
        across = np.cross((0.0, 1.0, 0.0), np.subtract(b, a))
        meshes.append(bar([a, b], across / np.linalg.norm(across), w, h, material))
    return Mesh.concatenate(meshes)


def _frame_members(style: Style, name: str, mirror_z: float | None = None) -> list[Piece]:
    """The forward frame's members; with ``mirror_z`` the same members reflected to z' = mirror_z - z (the aft frame, which
    the reference builds as the forward one's mirror image about the drum frame's middle), their neck ends carried on to
    the first cylinder's dome brackets (``AFT_FRAME_END_Z``), where the reference's aft members land."""
    hull = style.material("hull")

    def mirrored(z: float) -> float:
        return AFT_FRAME_END_Z if z < NECK_END_Z else mirror_z - z

    def at(points: Sequence[Sequence[float]]) -> list[tuple[float, float, float]]:
        out = [(float(x), float(y), float(z) if mirror_z is None else mirrored(float(z))) for x, y, z in points]
        return out if mirror_z is None else out[::-1]

    a, b, r = FWD_TUBE
    upper = [tube(*at([a, b]), r, hull), _beam(at(FWD_UPPER_BEAM), BEAM_SECTION, hull)]
    for branch in FWD_UPPER_BRANCHES:
        upper.append(_beam(at([FWD_UPPER_BEAM[1], *branch]), BEAM_SECTION, hull))
    upper.append(_beam(at([FWD_CENTRE_BEAM[1], *FWD_CENTRE_BRANCH]), BEAM_SECTION, hull))
    centre = [_beam(at(FWD_CENTRE_BEAM), BEAM_SECTION, hull), _beam(at(FWD_LOWER_BAR), LOWER_BAR_SECTION, hull)]
    pts = np.array(at([a, b, *FWD_UPPER_BEAM, *(q for br in FWD_UPPER_BRANCHES for q in br), *FWD_CENTRE_BEAM, *FWD_LOWER_BAR]))
    lo, hi = pts.min(axis=0) - 0.6, pts.max(axis=0) + 0.6
    lo[0] = -hi[0]
    hit = Collision("box", 0.5 * (lo + hi), size=hi - lo)
    return [
        _piece(f"{name}_centre", Mesh.concatenate(centre), mass_kg=20_000.0, collision=[hit]),
        _piece(f"{name}_upper", Mesh.concatenate(upper), side=RIGHT, mass_kg=25_000.0),
    ]


def forward_frame(style: Style) -> list[Piece]:
    """From the neck's end to the drum frame, member by member, with the plates and boxes ahead of the top drum."""
    hull = style.material("hull")
    pieces = _frame_members(style, "frame_fwd")
    size, centre_pt = CROSS_PLATE
    plates = [box(size, hull, center=centre_pt)] + [box(sz, hull, center=c) for sz, c in DRUM_CROSS]
    pieces.append(_piece("cross_plate", Mesh.concatenate(plates), box_solid(size, centre_pt), mass_kg=4_000.0))
    pieces += side_boxes(style, 0, "fwd")
    return pieces


def side_boxes(style: Style, k: int, name: str) -> list[Piece]:
    """The box and upright plate beside the top drum on the right, ahead of the drum frame (``k`` 0) or behind it (1)."""
    hull = style.material("hull")
    (bw, bh), (bx, by) = SIDE_BOX
    (pw, ph), (px, py) = SIDE_PLATE
    z0, z1 = SIDE_BOX_Z[k]
    q0, q1 = SIDE_PLATE_Z[k]
    meshes = [box((bw, bh, z1 - z0), hull, center=(bx, by, 0.5 * (z0 + z1))), box((pw, ph, q1 - q0), hull, center=(px, py, 0.5 * (q0 + q1)))]
    solid = box_solid((bw, bh, z1 - z0), (bx, by, 0.5 * (z0 + z1)))
    lo = np.array([bx - 0.5 * bw, py - 0.5 * ph, min(z0, q0)])
    hi = np.array([px + 0.5 * pw, by + 0.5 * bh, max(z1, q1)])
    hit = Collision("box", 0.5 * (lo + hi), size=hi - lo)
    return [_piece(f"side_box_{name}", Mesh.concatenate(meshes), solid, side=RIGHT, mass_kg=6_000.0, collision=[hit])]


AFT_FRAME_END_Z = 61.3  # inside the first dome's bracket ring (z 61.05 on): the aft members' landing
FRAME_MIRROR_Z = 92.1  # the plane the reference reflects its frames in (branches, posts, lower bar): about the drum frame's middle


def aft_frame(style: Style) -> list[Piece]:
    """From the drum frame's back to the first cylinder's front dome: the forward frame's mirror image, with the boxes
    behind the top drum."""
    return _frame_members(style, "frame_aft", FRAME_MIRROR_Z) + side_boxes(style, 1, "aft")


# --- drum frame -------------------------------------------------------------------------------------------------------
def _drum(radius: float, length: float, style: Style) -> tuple[Mesh, Solid]:
    """A drum along z from 0 to ``length`` whose end faces are RCS clusters."""
    hull, rcs = style.material("hull"), style.material("rcs")
    c = 0.2 * radius
    profile = [(0.0, 0.0), (0.0, radius - c), (c, radius), (length - c, radius), (length, radius - c), (length, 0.0)]
    mesh = lathe(profile, 32, [rcs, hull, hull, hull, rcs], creases={1, 2, 3, 4})
    return mesh, lathe_solid([(0.0, radius - c), (c, radius), (length - c, radius), (length, radius - c)])


DRUM_POSTS_Z = (43.9, 48.25)  # the frames round the drums, where the reference's sections have them (1.0 m thick)
DRUM_POST_THICKNESS = 1.0
DRUM_POST_WIDTH = 3.2  # the upright plate from the truss drum to the top drum
SPOKE = ((1.0, -5.4), (8.6, -10.2), 1.4)  # from, to (x, y), width: the band from the truss drum to each lower drum


def drum_frame(style: Style) -> list[Piece]:
    """Three drums round the truss (one on top, two low and outboard) and a larger drum on the truss, held by frames."""
    z0, z1 = DRUM_FRAME_Z
    length = z1 - z0
    hull = style.material("hull")
    pieces = []
    for name, (x, y), radius, side in (
        ("drum_top", TOP_DRUM, DRUM_RADIUS, CENTRE),
        ("drum_low", LOWER_DRUM, DRUM_RADIUS, RIGHT),
        ("drum_truss", TRUSS_DRUM, TRUSS_DRUM_RADIUS, CENTRE),
    ):
        mesh, solid = _drum(radius, length, style)
        pieces.append(_piece(name, mesh.translated((x, y, z0)), solid.translated((x, y, z0)), side=side, mass_kg=60_000.0))
    posts, spokes = [], []
    (sx0, sy0), (sx1, sy1), sw = SPOKE
    t = DRUM_POST_THICKNESS
    for z in DRUM_POSTS_Z:
        posts.append(box((DRUM_POST_WIDTH, TOP_DRUM[1] - TRUSS_DRUM[1], t), hull, center=(0.0, 0.5 * (TOP_DRUM[1] + TRUSS_DRUM[1]), z)))
        spokes.append(bar([(sx0, sy0, z), (sx1, sy1, z)], (0.0, 0.0, 1.0), t, sw, hull))
    pieces.append(_piece("drum_posts", Mesh.concatenate(posts), mass_kg=12_000.0))
    # The truss drum's narrower necks reach out to meet the lower bars, ahead of the drum and (mirrored) behind it.
    necks = []
    for a, b in ((41.1, z0 + 0.4), (z1 - 0.4, FRAME_MIRROR_Z - 41.1)):
        necks.append(lathe([(a, 0.0), (a, TRUSS_DRUM_NECK_R), (b, TRUSS_DRUM_NECK_R), (b, 0.0)], 20, hull, creases={1, 2}))
    pieces.append(_piece("drum_truss_neck", Mesh.concatenate(necks).translated((TRUSS_DRUM[0], TRUSS_DRUM[1], 0.0)), mass_kg=3_000.0))
    pieces.append(_piece("drum_spokes", Mesh.concatenate(spokes), side=RIGHT, mass_kg=12_000.0))
    lo_y = LOWER_DRUM[1] - DRUM_RADIUS
    hi_y = TOP_DRUM[1] + DRUM_RADIUS
    width = 2.0 * (LOWER_DRUM[0] + DRUM_RADIUS)
    hit = Collision("box", (0.0, 0.5 * (lo_y + hi_y), 0.5 * (z0 + z1)), size=(width, hi_y - lo_y, length))
    pieces[2].part.collision.append(hit)
    return pieces


# --- engine section ---------------------------------------------------------------------------------------------------
def engine_section(style: Style, k: float = 1.0) -> list[Piece]:
    """22.6 m from the collar's front (z = 0): a 9.6 m collar, four propellant tanks round a central one, U-shaped feed
    pipes to the throat and a bell with a 6.3 m exit on the axis. ``k`` scales all of it (the Saturn 3's slim engine,
    Q20); masses scale with the volume."""
    if k <= 0.0:
        raise ValueError("the engine's scale must be positive")
    hull, dark = style.material("hull"), style.material("hull_dark")
    R, L, length = k * COLLAR_RADIUS, k * COLLAR_LENGTH, k * ENGINE_LENGTH
    m = k**3
    collar_profile = [(0.0, 0.0), (0.0, R - 0.5 * k), (0.4 * k, R), (L - 0.4 * k, R), (L, R - 0.4 * k), (L, 0.0)]
    collar = lathe(collar_profile, _SECTION_STEPS, [dark, hull, hull, hull, dark], creases={1, 2, 3, 4})
    hit = Collision("capsule", (0.0, 0.0, 0.5 * length), radius=R, height=length)
    pieces = [_piece("engine_collar", collar, lathe_solid(collar_profile[1:-1]), mass_kg=300_000.0 * m, collision=[hit])]

    def capsule_tank(radius: float, z0: float, z1: float) -> tuple[Mesh, Solid]:
        radius, z0, z1 = k * radius, k * z0, k * z1
        steps = 5
        front = [(z0 + radius * 0.6 * (1.0 - math.sin(a)), radius * math.cos(a)) for a in np.linspace(0.5 * math.pi, 0.0, steps)]
        back = [(z1 - radius * 0.6 * (1.0 - math.sin(a)), radius * math.cos(a)) for a in np.linspace(0.0, 0.5 * math.pi, steps)]
        profile = [(z0, 0.0)] + front[1:] + back[:-1] + [(z1, 0.0)]
        return lathe(profile, 32, hull), lathe_solid(profile)

    core, core_solid = capsule_tank(2.55, 1.7, 14.63)
    pieces.append(_piece("engine_core_tank", core, core_solid, mass_kg=200_000.0 * m))
    tank, tank_solid = capsule_tank(1.9, 6.2, 13.4)
    for name, (x, y), side in (("engine_tank_side", (3.0, 0.0), RIGHT), ("engine_tank_top", (0.0, 3.0), CENTRE), ("engine_tank_bottom", (0.0, -3.0), CENTRE)):
        at = (k * x, k * y, 0.0)
        pieces.append(_piece(name, tank.translated(at), tank_solid.translated(at), side=side, mass_kg=60_000.0 * m))
    # U-shaped pipes in each tank's radial plane: aft out of the tank, over and back into the throat.
    for name, direction, side in (("engine_pipe_side", (1.0, 0.0), RIGHT), ("engine_pipe_top", (0.0, 1.0), CENTRE), ("engine_pipe_bottom", (0.0, -1.0), CENTRE)):
        d = np.array([*direction, 0.0])
        rho_z = [(3.1, 12.9), (3.1, 15.4), (2.85, 16.2), (2.3, 16.55), (1.65, 16.35)]
        path = [k * (d * rho + (0.0, 0.0, z)) for rho, z in rho_z]
        width_axis = (-direction[1], direction[0], 0.0)
        pieces.append(_piece(name, bar(path, width_axis, 0.9 * k, 0.9 * k, dark), side=side, mass_kg=5_000.0 * m))
    throat_profile = [(14.0 * k, 0.0), (14.0 * k, 2.2 * k), (16.25 * k, 2.2 * k), (16.25 * k, 0.0)]
    throat = lathe(throat_profile, 40, dark, creases={1, 2})
    pieces.append(_piece("engine_throat", throat, lathe_solid(throat_profile[1:-1]), mass_kg=40_000.0 * m))
    bell_spec = replace(BELL, throat_r=k * BELL.throat_r, exit_r=k * BELL.exit_r, length=k * BELL.length, wall=k * BELL.wall)
    bell = nozzle(bell_spec, style).translated((0.0, 0.0, length - bell_spec.length))
    pieces.append(_piece("engine_bell", bell.mesh, mass_kg=80_000.0 * m))
    return pieces


def truss_end_plate(style: Style, z: float) -> Piece:
    """Where a truss wider than its engine's collar lands on the collar's front (the Saturn 3's slim engine)."""
    (bx, by), (rx, ry) = _longerons()
    size = (2.0 * rx + 1.2, ry - by + 1.2, 0.8)
    centre = (0.0, 0.5 * (ry + by), z)
    return _piece("truss_end_plate", box(size, style.material("hull_dark"), center=centre), box_solid(size, centre), mass_kg=15_000.0)


# --- hull cylinders and tanks -----------------------------------------------------------------------------------------
def cylinder_profile(steps: int = 8) -> list[tuple[float, float]]:
    """The hull cylinder's outline ``(z, r)`` from the front dome's tip (z = 0): shallow elliptic domes at both ends."""
    length = CYLINDER_Z[1] - CYLINDER_Z[0]
    R, D = CYLINDER_RADIUS, DOME_DEPTH
    front = [(D * (1.0 - math.cos(a)), R * math.sin(a)) for a in np.linspace(0.0, 0.5 * math.pi, steps + 1)]
    back = [(length - z, r) for z, r in reversed(front)]
    return front + back


def hull_cylinder(bands: Sequence[str], style: Style, name: str = "cylinder", mass_kg: float = 600_000.0) -> Piece:
    """The hull cylinder (also every tank): 17.53 m across and 75.5 m long from z = 0, painted in alternating bands
    (``bands[0]`` the front dome, ``bands[-1]`` the aft dome, the barrel split evenly between the rest)."""
    if len(bands) < 3:
        raise ValueError("a cylinder needs a band for each dome and at least one for the barrel")
    outline = cylinder_profile()
    steps = (len(outline) - 2) // 2
    front, back = outline[: steps + 1], outline[steps + 1 :]
    barrel_z0, barrel_z1 = front[-1][0], back[0][0]
    cuts = np.linspace(barrel_z0, barrel_z1, len(bands) - 1)
    profile = front + [(float(z), CYLINDER_RADIUS) for z in cuts[1:-1]] + back
    materials = [style.material(bands[0])] * steps
    materials += [style.material(b) for b in bands[1:-1]]
    materials += [style.material(bands[-1])] * steps
    mesh = lathe(profile, _SECTION_STEPS, materials)
    length = profile[-1][0]
    # The caps' centres sit at the barrel's ends: a half sphere of the cylinder's radius then covers the shallower dome.
    reach = CYLINDER_RADIUS - DOME_DEPTH
    hit = Collision("capsule", (0.0, 0.0, 0.5 * length), radius=CYLINDER_RADIUS, height=length + 2.0 * reach)
    return _piece(name, mesh, lathe_solid(profile), mass_kg=mass_kg, collision=[hit])


def dome_surface_z(rho: float) -> float:
    """How far behind a front dome's tip its surface is at radius ``rho``."""
    q = min(rho / CYLINDER_RADIUS, 1.0)
    return DOME_DEPTH * (1.0 - math.sqrt(1.0 - q * q))


def dome_brackets(style: Style, name: str = "dome_brackets") -> Piece:
    """A flange at a front dome's tip (z = 0) and a ring of 12 radial brackets where a truss or struts land; mirror it
    in z for an aft dome."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    flange_profile = [(-0.6, 0.0), (-0.6, 1.8), (-0.3, 2.2), (0.7, 2.2), (0.7, 0.0)]
    meshes = [lathe(flange_profile, 32, hull, creases={1, 2, 3})]
    for k in range(12):
        a = math.radians(30.0 * k)
        u = np.array([math.cos(a), math.sin(a), 0.0])
        path = [u * rho + (0.0, 0.0, dome_surface_z(rho) - 0.25) for rho in (1.9, 3.4, 4.86)]
        meshes.append(bar(path, (-math.sin(a), math.cos(a), 0.0), 0.5, 0.9, dark))
    return _piece(name, Mesh.concatenate(meshes), lathe_solid(flange_profile[1:-1]), mass_kg=8_000.0)


# --- pods ----------------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class PodTrim:
    """Per-hull pod paint: a stripe of ``stripe_role`` along the top ridge, a hazard band along the outboard flank, or
    the whole top in ``top_paint`` (an sRGB value)."""

    stripe_role: str | None = None
    stripe_m: float = 1.6
    hazard_flank: bool = False
    top_paint: int | None = None


@dataclass(frozen=True)
class PodSpec:
    """The shared transport pod in its own frame: ``u`` outboard from the inboard face, ``v`` up from its middle, ``w``
    along its length from the front. A flat hexagonal prism with a kite section."""

    # The outline is the raised end band's (the widest); the body between the bands is it stepped in by ``band_step``
    # (the reference's sections: band 7.74 / 17.22 / 4.73 m tall at the inboard face, ridge and outboard face, body 6.1 /
    # 15.6 / 3.8 m).
    width: float = 31.06
    height: float = 17.22
    length: float = 43.03
    ridge_u: float = 9.84
    inboard_face: float = 7.74
    outboard_face: float = 4.73
    frame: float = 1.58  # the end frames round the recess
    recess: float = 1.4
    band: float = 3.65  # the raised band round each end
    band_step: float = 0.8
    rail_uv: tuple[float, float] = (-1.78, -0.63)
    rail_radius: float = 1.37
    rail_w: tuple[float, float] = (0.82, 42.21)  # centred along the pod (0.82 m from each end)
    rail_block: tuple[float, float, float] = (4.47, 5.75, 2.38)
    rail_block_uv: tuple[float, float] = (-1.93, 0.04)
    rail_block_w: tuple[float, float] = (0.29, 42.74)  # centred too
    mass_kg: float = 2_500_000.0

    def outline(self) -> np.ndarray:
        h_in, h_mid, h_out = 0.5 * self.inboard_face, 0.5 * self.height, 0.5 * self.outboard_face
        return np.array([(0.0, -h_in), (self.ridge_u, -h_mid), (self.width, -h_out), (self.width, h_out), (self.ridge_u, h_mid), (0.0, h_in)])


POD = PodSpec()


def _pod_paint(spec: PodSpec, trim: PodTrim, style: Style, body: np.ndarray) -> tuple[Callable, Callable]:
    """Cuts and paint for the pod body's walls: the top stripe or top paint, the hazard band, darker patches."""
    panel, patch = style.material("hull_panel"), style.material("hull_patch")
    lengths = [float(np.linalg.norm(body[(e + 1) % 6] - body[e])) for e in range(6)]
    top_paint = None
    if trim.top_paint is not None:
        top_paint = Material(f"eac_pod_top_{trim.top_paint:06x}", lin(trim.top_paint), paneled=True)

    def breaks(e: int, length: float) -> list[float]:
        ts = set(_cells(length, 3.6))
        if trim.stripe_role and e == 3:
            ts.add(1.0 - trim.stripe_m / length)
        if trim.stripe_role and e == 4:
            ts.add(trim.stripe_m / length)
        if trim.hazard_flank and e == 2:
            ts |= {0.2, 0.8}
        return sorted(ts)

    def paint(e: int, i: int, j: int, t: float, w: float) -> Material:
        if trim.stripe_role and ((e == 3 and t > 1.0 - trim.stripe_m / lengths[3]) or (e == 4 and t < trim.stripe_m / lengths[4])):
            return style.material(trim.stripe_role)
        if top_paint is not None and e in (3, 4):
            return top_paint
        if trim.hazard_flank and e == 2 and 0.2 < t < 0.8:
            return style.material("hazard" if j % 2 == 0 else "hazard_dark")
        return patch if _hash01(e, i, j // 2) < 0.2 else panel

    return breaks, paint


def transport_pod(trim: PodTrim, style: Style, spec: PodSpec = POD) -> list[Piece]:
    """The pod with its recessed, ribbed ends and its rail, in the pod frame (see :class:`PodSpec`)."""
    outer = spec.outline()
    body = inset_convex_polygon(outer, spec.band_step)
    recess = inset_convex_polygon(outer, spec.frame)
    L, band, depth = spec.length, spec.band, spec.recess
    panel, dark, back = style.material("hull_panel"), style.material("hull_dark"), style.material("interior")
    breaks, paint = _pod_paint(spec, trim, style, body)
    n_cells = max(2, round((L - 2.0 * band) / 1.8))
    shell = [
        walls(outer, [0.0, band], lambda *_: panel),
        walls(outer, [L - band, L], lambda *_: panel),
        walls(body, list(np.linspace(band, L - band, n_cells + 1)), paint, breaks),
        ring_face(outer, body, band, 1.0, panel),
        ring_face(outer, body, L - band, -1.0, panel),
        ring_face(outer, recess, 0.0, -1.0, dark),
        ring_face(outer, recess, L, 1.0, dark),
        walls(recess, [0.0, depth], lambda *_: dark, inward=True),
        walls(recess, [L - depth, L], lambda *_: dark, inward=True),
        polygon_face(recess, depth, -1.0, back),
        polygon_face(recess, L - depth, 1.0, back),
    ]
    solid = difference(
        union(prism_solid(outer, 0.0, band), prism_solid(body, band - 0.01, L - band + 0.01), prism_solid(outer, L - band, L)),
        prism_solid(recess, -1.0, depth),
        prism_solid(recess, L - depth, L + 1.0),
    )
    # Ladder ribs in each recess: uprights across it and one rib along its middle.
    u_lo, u_hi = float(recess[:, 0].min()), float(recess[:, 0].max())
    ribs, rib_solids = [], []
    for u in np.linspace(u_lo + 1.2, u_hi - 1.2, 7):
        v_lo, v_hi = _vertical_extent(recess, float(u))
        for w_mid in (0.5 * (0.25 + depth + 0.06), L - 0.5 * (0.25 + depth + 0.06)):
            size, centre = (0.5, v_hi - v_lo + 0.3, depth - 0.19), (float(u), 0.5 * (v_lo + v_hi), w_mid)
            ribs.append(box(size, dark, center=centre))
            rib_solids.append(box_solid(size, centre))
    for w_mid in (0.5 * (0.25 + depth + 0.06), L - 0.5 * (0.25 + depth + 0.06)):
        size, centre = (u_hi - u_lo + 0.3, 1.19, depth - 0.19), (0.5 * (u_lo + u_hi), 0.0, w_mid)
        ribs.append(box(size, dark, center=centre))
        rib_solids.append(box_solid(size, centre))
    # The rail along the inboard edge, a block at each end.
    hull = style.material("hull")
    (ru, rv), (w0, w1) = spec.rail_uv, spec.rail_w
    rod_profile = [(w0, 0.0), (w0, spec.rail_radius), (w1, spec.rail_radius), (w1, 0.0)]
    rod = lathe(rod_profile, 24, hull, creases={1, 2}).translated((ru, rv, 0.0))
    blocks = [box(spec.rail_block, hull, center=(*spec.rail_block_uv, w)) for w in spec.rail_block_w]
    rail_solid = union(
        lathe_solid(rod_profile[1:-1]).translated((ru, rv, 0.0)),
        *(box_solid(spec.rail_block, (*spec.rail_block_uv, w)) for w in spec.rail_block_w),
    )
    lo = (min(spec.rail_block_uv[0] - 0.5 * spec.rail_block[0], ru - spec.rail_radius), -0.5 * spec.height,
          spec.rail_block_w[0] - 0.5 * spec.rail_block[2])
    hi = (spec.width, 0.5 * spec.height, spec.rail_block_w[1] + 0.5 * spec.rail_block[2])
    hit = Collision("box", 0.5 * (np.array(lo) + np.array(hi)), size=np.array(hi) - np.array(lo))
    return [
        _piece("pod", Mesh.concatenate(shell), solid, mass_kg=spec.mass_kg, collision=[hit]),
        _piece("pod_ribs", Mesh.concatenate(ribs), union(*rib_solids), mass_kg=10_000.0),
        _piece("pod_rail", Mesh.concatenate([rod, *blocks]), rail_solid, mass_kg=40_000.0),
    ]


def _vertical_extent(poly: np.ndarray, u: float) -> tuple[float, float]:
    """Where a vertical line at ``u`` enters and leaves a convex outline."""
    vs = []
    for e in range(len(poly)):
        a, b = poly[e], poly[(e + 1) % len(poly)]
        if (a[0] - u) * (b[0] - u) <= 0.0 and a[0] != b[0]:
            t = (u - a[0]) / (b[0] - a[0])
            vs.append(a[1] + t * (b[1] - a[1]))
    return min(vs), max(vs)


# --- the transport section's arms -----------------------------------------------------------------------------------------
ARM_PEDESTAL = ((12.8, 17.6), (ARM_Y[1] - 0.2, -2.3))  # x, y: the block on each arm the reference's front view shows


def cargo_arm(style: Style, z0: float, z1: float) -> list[Piece]:
    """One arm under a pod's middle (right side, section frame): a pedestal on it, a brace from the pedestal up to the
    cylinder's flank and a leg from the arm's root, as the reference's front view shows."""
    hull = style.material("hull")
    size = (ARM_X[1] - ARM_X[0], ARM_Y[1] - ARM_Y[0], z1 - z0)
    centre = (0.5 * sum(ARM_X), 0.5 * sum(ARM_Y), 0.5 * (z0 + z1))
    (px0, px1), (py0, py1) = ARM_PEDESTAL
    ped_size = (px1 - px0, py1 - py0, z1 - z0 - 1.6)
    ped_centre = (0.5 * (px0 + px1), 0.5 * (py0 + py1), centre[2])
    struts = []
    for zh in (z0 + 0.9, z1 - 0.9):
        struts.append(bar([(px0 + 0.3, py1 - 0.3, zh), (8.2, 2.6, zh)], (0.0, 0.0, 1.0), 0.8, 0.7, hull))
        struts.append(bar([(ARM_X[0] + 0.3, ARM_Y[1] - 0.2, zh), (8.5, 0.4, zh)], (0.0, 0.0, 1.0), 0.8, 0.7, hull))
    lo = np.array([8.2, ARM_Y[1] - 0.2, z0 + 0.5])
    hi = np.array([px0 + 0.6, 3.0, z1 - 0.5])
    hit = Collision("box", centre, size=size)
    brace_hit = Collision("box", 0.5 * (lo + hi), size=hi - lo, name="braces")
    return [
        _piece("arm", box(size, hull, center=centre), box_solid(size, centre), side=RIGHT, mass_kg=60_000.0, collision=[hit]),
        _piece("arm_pedestal", box(ped_size, hull, center=ped_centre), box_solid(ped_size, ped_centre), side=RIGHT, mass_kg=10_000.0,
               collision=[Collision("box", ped_centre, size=ped_size)]),
        _piece("arm_braces", Mesh.concatenate(struts), side=RIGHT, mass_kg=8_000.0, collision=[brace_hit]),
    ]


# --- tank section ---------------------------------------------------------------------------------------------------------
# The A-frames between each lower tank and the spine tank, traced off the tanker model's sections (section frame, right
# side): two stations near the section's ends, each a pedestal on the lower tank, a block on the spine tank's flank,
# two slanted plates 3.5 m apart between them and a joint block at their top.
TANK_BRACE_Z = (25.7, 74.2)  # section-local stations
TANK_BRACE_LENGTH = 5.0
TANK_PEDESTAL = ((11.0, 16.5), (-6.9, -4.3))  # x, y
TANK_BRACE_BLOCKS = (((14.1, 15.9), (-4.3, -2.6)), ((7.7, 9.8), (-1.8, 3.3)))  # on the pedestal; on the spine tank's flank
TANK_BRACE_PLATE = ((15.4, -3.6), (10.3, 3.0), 0.6, 0.3)  # from, to (x, y), in-plane width, thickness along z
TANK_BRACE_PLATE_DZ = 1.75  # the two plates either side of the station
TANK_BRACE_JOINT = ((9.5, 10.7), (2.2, 3.4))


def tank_braces(style: Style) -> Mesh:
    """The A-frames at their two stations (section frame, right side), as the tanker model's sections show."""
    hull = style.material("hull")
    meshes = []
    for z in TANK_BRACE_Z:
        for (x0, x1), (y0, y1) in (TANK_PEDESTAL, *TANK_BRACE_BLOCKS):
            meshes.append(box((x1 - x0, y1 - y0, TANK_BRACE_LENGTH), hull, center=(0.5 * (x0 + x1), 0.5 * (y0 + y1), z)))
        (ax, ay), (bx, by), w, t = TANK_BRACE_PLATE
        (jx0, jx1), (jy0, jy1) = TANK_BRACE_JOINT
        for dz in (-TANK_BRACE_PLATE_DZ, TANK_BRACE_PLATE_DZ):
            meshes.append(bar([(ax, ay, z + dz), (bx, by, z + dz)], (0.0, 0.0, 1.0), t, w, hull))
            meshes.append(box((jx1 - jx0, jy1 - jy0, 0.6), hull, center=(0.5 * (jx0 + jx1), 0.5 * (jy0 + jy1), z + dz)))
    return Mesh.concatenate(meshes)


def tank_brace_collision() -> list[Collision]:
    """One box round each A-frame of :func:`tank_braces` (section frame, right side)."""
    lo = np.array([TANK_BRACE_BLOCKS[1][0][0], TANK_PEDESTAL[1][0], -0.5 * TANK_BRACE_LENGTH])
    hi = np.array([TANK_PEDESTAL[0][1], TANK_BRACE_BLOCKS[1][1][1] + 0.1, 0.5 * TANK_BRACE_LENGTH])
    return [Collision("box", 0.5 * (lo + hi) + (0.0, 0.0, z), size=hi - lo, name=f"z{int(z)}") for z in TANK_BRACE_Z]


# --- junctions ------------------------------------------------------------------------------------------------------------
def transport_junction(style: Style, centre_z: float, dome_aft_z: float, dome_front_z: float) -> list[Piece]:
    """The Saturn 8 transport's hexagonal module (13.3 m across, 10.6 m long) on the axis, held by struts from the aft
    dome before it and the front dome after it."""
    width, height, length = 13.3 / math.cos(math.radians(30.0)), 13.3, 10.6
    module, solid = hex_module(width, height, length, style)
    z0 = centre_z - 0.5 * length
    hit = Collision("box", (0.0, 0.0, 0.5 * (dome_aft_z + dome_front_z)), size=(width, height, dome_front_z - dome_aft_z))
    pieces = [_piece("junction_module", module.translated((0.0, 0.0, z0)), solid.translated((0.0, 0.0, z0)), mass_kg=300_000.0,
                     collision=[hit])]
    hull = style.material("hull")
    struts = []
    for a in (math.radians(40.0), math.radians(-40.0)):
        u = np.array([math.cos(a), math.sin(a), 0.0])
        w_axis = (-math.sin(a), math.cos(a), 0.0)
        struts.append(bar([u * 5.0 + (0, 0, dome_aft_z - dome_surface_z(5.0) - 0.3), u * 3.6 + (0, 0, z0 + 0.4)], w_axis, 0.8, 0.8, hull))
        struts.append(bar([u * 3.6 + (0, 0, z0 + length - 0.4), u * 5.0 + (0, 0, dome_front_z + dome_surface_z(5.0) + 0.3)], w_axis, 0.8, 0.8, hull))
    pieces.append(_piece("junction_struts", Mesh.concatenate(struts), side=RIGHT, mass_kg=20_000.0))
    return pieces


def tanker_junction(style: Style, centre_z: float, dome_aft_z: float, dome_front_z: float) -> list[Piece]:
    """The Saturn 8 tanker's three hexagonal modules (18.3 x 16.8 x 19.1 m, two recessed panels a face), one on each
    tank's axis with a 9.0 m neck to the tank on either side, joined by plates."""
    width, height, length = 18.3, 16.8, 19.1
    z0 = centre_z - 0.5 * length
    module, solid = hex_module(width, height, length, style, recessed=True)
    neck_r = 4.5
    neck_profile_front = [(dome_aft_z - dome_surface_z(neck_r) - 0.4, neck_r), (z0 + 0.4, neck_r)]
    neck_profile_back = [(z0 + length - 0.4, neck_r), (dome_front_z + dome_surface_z(neck_r) + 0.4, neck_r)]
    hull, dark = style.material("hull"), style.material("hull_dark")
    necks, neck_solids = [], []
    for (za, r), (zb, _) in (neck_profile_front, neck_profile_back):
        profile = [(za, 0.0), (za, r), (zb, r), (zb, 0.0)]
        necks.append(lathe(profile, 40, dark, creases={1, 2}))
        neck_solids.append(lathe_solid(profile[1:-1]))
    pieces = []
    for name, (x, y), side in (("junction_spine", (0.0, 0.0), CENTRE), ("junction_low", LOWER_TANK, RIGHT)):
        hit = Collision("box", (x, y, centre_z), size=(width, height, length))
        mesh = Mesh.concatenate([module.translated((x, y, z0)), *(n.translated((x, y, 0.0)) for n in necks)])
        piece_solid = union(solid.translated((x, y, z0)), *(s.translated((x, y, 0.0)) for s in neck_solids))
        pieces.append(_piece(name, mesh, piece_solid, side=side, mass_kg=400_000.0, collision=[hit]))
    plate = bar([(5.0, -6.0, centre_z), (11.5, -8.0, centre_z)], (0.0, 0.0, 1.0), 12.0, 1.2, hull)
    pieces.append(_piece("junction_plate", plate, side=RIGHT, mass_kg=30_000.0))
    return pieces


# --- the Saturn 3's pod stack ---------------------------------------------------------------------------------------------
STACK_FRONT_Z = 64.24  # the pods' front faces (their inboard faces, turned forward)
STACK_EXHAUST_CLEARANCE = 1.5  # Q20: the slim engine's bell exit behind the pods' aft faces
SLIM_ENGINE_SCALE = 2.8 / COLLAR_RADIUS  # Q20: a 5.6 m collar in the 7.0 m gap between the lower pods
LOWER_POD_CENTRE = (25.015, -5.46)  # x of the pod's middle
TOP_POD_CENTRE = (0.0, 13.16)
CROSS_BEAM = ((56.4, 4.4, 1.6), (0.0, -6.9, 49.3))  # size, centre
POD_BLOCK = (6.3, 4.4, 13.4)
POD_BLOCK_Z = (51.0, 64.4)


def stack_pod_rotation() -> np.ndarray:
    """Turns the pod frame for the Saturn 3: its section points fore and aft (u along +z), its length runs across (w
    along -x)."""
    return np.array([[0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]])


def stack_pod_origin(centre_x: float, centre_y: float) -> np.ndarray:
    """Where the turned pod frame's origin goes for a pod centred at ``centre_x`` across the ship."""
    return np.array([centre_x + 0.5 * POD.length, centre_y, STACK_FRONT_Z])


def stack_mounts(style: Style) -> list[Piece]:
    """The cross-beam behind the drum frame, a block on each pod's front face (with vent grilles) and the strut from
    the top drum to the top pod's block."""
    hull = style.material("hull")
    (size, centre) = CROSS_BEAM
    pieces = [_piece("cross_beam", box(size, hull, center=centre), box_solid(size, centre), mass_kg=80_000.0,
                     collision=[Collision("box", centre, size=size)])]
    zc = 0.5 * sum(POD_BLOCK_Z)
    for name, (x, y), side in (("pod_block_low", LOWER_POD_CENTRE, RIGHT), ("pod_block_top", TOP_POD_CENTRE, CENTRE)):
        centre_b = (x, y, zc)
        top = y + 0.5 * POD_BLOCK[1]
        grille = vent_grille(4.2, 9.0, 7, style, slat_height=0.35, slat_fill=0.5).translated((x, top, zc))
        grille_solid = box_solid((4.2, 0.45, 9.0), (x, top + 0.1, zc))
        pieces.append(_piece(name, box(POD_BLOCK, hull, center=centre_b), box_solid(POD_BLOCK, centre_b), side=side,
                             mass_kg=40_000.0, collision=[Collision("box", centre_b, size=POD_BLOCK)]))
        pieces.append(_piece(name.replace("block", "grille"), grille, grille_solid, side=side, mass_kg=2_000.0))
    link_size = (2.0, 2.0, POD_BLOCK_Z[0] - (centre[2] + 0.5 * size[2]) + 0.6)
    link_centre = (LOWER_POD_CENTRE[0], -6.4, 0.5 * (centre[2] + 0.5 * size[2] + POD_BLOCK_Z[0]))
    pieces.append(_piece("pod_block_link", box(link_size, hull, center=link_centre), box_solid(link_size, link_centre), side=RIGHT,
                         mass_kg=4_000.0))
    strut = bar([(0.0, TOP_DRUM[1] + 0.9, 47.5), (0.0, TOP_POD_CENTRE[1] - 1.6, 53.0)], (1.0, 0.0, 0.0), 1.4, 1.0, hull)
    pieces.append(_piece("pod_strut", strut, mass_kg=6_000.0))
    return pieces


# --- turret pads --------------------------------------------------------------------------------------------------------------
def turret_pad(position: Sequence[float], up: Sequence[float], depth: float, style: Style, radius: float = 1.6) -> tuple[Mesh, Solid]:
    """The mount a turret stands on: a short drum from ``depth`` inside the host to ``position``, its top dark."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    profile = [(-depth, 0.0), (-depth, radius), (-0.15, radius), (0.0, radius - 0.15), (0.0, 0.0)]
    mesh = lathe(profile, 32, [hull, hull, hull, dark], creases={1, 2, 3})
    rotation = basis_from_z(up, x_hint=(1.0, 0.0, 0.0))
    solid = lathe_solid([(-depth, radius), (0.0, radius)])
    return mesh.transformed(rotation, position), solid.transformed(rotation, position)

