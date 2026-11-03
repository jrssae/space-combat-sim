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
from dataclasses import dataclass

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
    tapered_box,
)
from ..styles import Style
from ..styles.ea_civilian import lin
from . import Collision, Part
from .propulsion import NozzleSpec, nozzle
from .solids import Solid, box_solid, difference, lathe_solid, prism_solid, union
from .starfury import outward
from .wing import vent_grille

CENTRE, RIGHT = "c", "r"
_Z_TO_Y = rotation_x(-0.5 * math.pi)  # local +Z to +Y
_SECTION_STEPS = 64  # round sections of the big drums

# --- the lead ship (design references, "Lead ship") -------------------------------------------------------------
DISC_CENTRE_Z = 19.1
DISC_RADIUS = 14.13
DISC_THICKNESS = 6.0  # at the centre
DISC_RIM = 1.6  # thickness at the rim
DISC_CUT_Z = 29.6  # the aft quarter is cut square here
NECK_WIDTH = 12.7
NECK_END_Z = 33.2
HUB_RADIUS = 2.5
HUB_TOP_Y = 3.8  # the dorsal_fwd turret stands on the hub
FIN_RADII = (2.5, 8.7)
RUST_RING_RADII = (2.5, 11.0)
WINDOW_HALF_HEIGHT = 0.3
# Aft of z 22 the disc's edge is straight, not round (the reference's top silhouette): half-widths at these z.
DISC_CHAMFER = ((22.0, 13.75), (23.77, 12.0), (28.53, 10.2), (DISC_CUT_Z, 9.8))
# A wedge in each cut corner (plan x, z), 4.3 m tall: its outer face runs from the disc's edge in to the neck.
CORNER_WEDGE = ((5.97, 22.6), (12.63, 22.6), (6.6, 30.39), (5.97, 30.39))
CORNER_WEDGE_HEIGHT = 4.3
NECK_END_WIDTH = 7.0
RETRO_EXIT = (9.51, 0.0, 8.56)
RETRO_RADIUS = 0.95
COCKPIT_EYE = (0.0, 0.8, 8.0)
ANTENNA_Y = -4.4
DISH_RADIUS = 3.6
TRUSS_START_Z = 33.6  # inside the plate behind the neck (33.2)
TRUSS_SIDE = 6.3
LONGERON_RADIUS = 0.3
BRACE_RADIUS = 0.2
DRUM_FRAME_Z = (41.9, 50.1)
TOP_DRUM = (0.0, 5.55)
LOWER_DRUM = (9.27, -10.55)
TRUSS_DRUM = (0.0, -5.18)
DRUM_RADIUS = 1.6
TRUSS_DRUM_RADIUS = 2.0
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

    def regrouped(self, group: str, name: str | None = None) -> Piece:
        return Piece(self.part.renamed(name or self.part.name, group=group), self.solid, self.side, self.fine)


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
    """A dish facing forward with a spike in front, on a boom to the disc's underside (z 0 to 5.5)."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    r = DISH_RADIUS
    profile = [(5.0, 0.0), (4.85, 1.3), (4.4, 2.5), (3.8, r), (3.8, r + 0.15), (4.4, 2.9), (5.0, 1.8), (5.5, 0.0)]
    dish = outward(lathe(profile, 40, [hull, hull, hull, dark, dark, dark, dark], creases={3, 4})).translated((0.0, ANTENNA_Y, 0.0))
    spike = outward(lathe([(0.0, 0.0), (0.0, 0.1), (5.1, 0.36), (5.1, 0.0)], 16, dark, creases={1, 2})).translated((0.0, ANTENNA_Y, 0.0))
    boom = bar([(0.0, ANTENNA_Y, 5.3), (0.0, -1.7, 10.8)], (1.0, 0.0, 0.0), 0.9, 0.7, hull)
    box_size = (2.0 * r + 0.3, 2.0 * r + 0.3, 5.5)
    hit = Collision("box", (0.0, ANTENNA_Y, 2.75), size=box_size)
    return [
        _piece("antenna_dish", dish, mass_kg=12_000.0, collision=[hit], fine=0.5),
        _piece("antenna_spike", spike, fine=0.25),  # the nose: thin, and the ship's forward extreme on every level
        _piece("antenna_boom", boom, fine=0.5),
    ]


# --- command disc -----------------------------------------------------------------------------------------------------
def lens_thickness(r: np.ndarray | float) -> np.ndarray:
    """The disc's full thickness at radius ``r`` from its centre: 6.0 m in the middle, 1.6 m at the rim."""
    q = np.clip(1.0 - (np.asarray(r, dtype=float) / DISC_RADIUS) ** 2, 0.0, 1.0)
    return DISC_RIM + (DISC_THICKNESS - DISC_RIM) * q


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
    hull, dark = style.material("hull"), style.material("hull_dark")
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

    neck_z0 = DISC_CUT_Z - 0.3
    neck_centre = (0.0, 0.0, 0.5 * (neck_z0 + NECK_END_Z))
    neck = tapered_box(NECK_END_Z - neck_z0, (NECK_WIDTH + 0.9, 3.4), (NECK_END_WIDTH, 3.4), hull, center=neck_centre)
    pieces.append(_piece("disc_neck", neck, box_solid((NECK_END_WIDTH, 3.2, NECK_END_Z - neck_z0), neck_centre), mass_kg=60_000.0))
    plate_size, plate_centre = (7.4, 7.6, 0.9), (0.0, -0.4, NECK_END_Z + 0.4)
    pieces.append(_piece("truss_plate", box(plate_size, hull, center=plate_centre), box_solid(plate_size, plate_centre), mass_kg=20_000.0))

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
            path = [radial_dir * rho + (0.0, sign * (0.5 * float(lens_thickness(rho)) + 0.35), DISC_CENTRE_Z)
                    for rho in (FIN_RADII[0] - 0.1, 0.5 * sum(FIN_RADII), FIN_RADII[1])]
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


def _frame(style: Style, name: str, upper: tuple, lower: tuple, k_bars: Sequence[tuple]) -> list[Piece]:
    """Tubes from the neck or a dome to the drum frame (the upper pair on the right and mirrored, the lower one on the
    centre line) and flat K braces between them on each side, as the reference's side view shows."""
    hull = style.material("hull")
    up = tube(upper[0], upper[1], 0.42, hull)
    low = tube(lower[0], lower[1], 0.45, hull)
    braces = Mesh.concatenate([bar([a, b], (1.0, 0.0, 0.0), 0.35, 0.9, hull) for a, b in k_bars])
    pts = np.array([*upper, *lower, *(q for ab in k_bars for q in ab)])
    lo, hi = pts.min(axis=0) - 0.45, pts.max(axis=0) + 0.45
    lo[0] = -hi[0]
    hit = Collision("box", 0.5 * (lo + hi), size=hi - lo)
    return [
        _piece(f"{name}_lower", low, mass_kg=20_000.0, collision=[hit]),
        _piece(f"{name}_upper", Mesh.concatenate([up, braces]), side=RIGHT, mass_kg=25_000.0),
    ]


def forward_frame(style: Style) -> list[Piece]:
    """From the neck's end plate to the drum frame's front."""
    z0, z1, joint = TRUSS_START_Z, DRUM_FRAME_Z[0] + 0.3, (2.4, -0.6, 38.0)
    upper = ((3.0, 2.0, z0), (1.0, TOP_DRUM[1] - 0.3, z1))
    lower = ((0.0, -3.3, z0), (0.0, TRUSS_DRUM[1] - 0.2, z1))
    k = [((2.4, 1.8, z0 + 0.4), joint), ((2.4, -3.0, z0 + 0.4), joint), (joint, (2.4, 2.4, z1 - 0.3))]
    return _frame(style, "frame_fwd", upper, lower, k)


def aft_frame(style: Style, dome_tip_z: float) -> list[Piece]:
    """From the drum frame's back to the first cylinder's front dome (its tip at ``dome_tip_z``)."""
    z0, joint = DRUM_FRAME_Z[1] - 0.3, (2.4, -0.6, 54.5)
    top_end = dome_tip_z + dome_surface_z(math.hypot(3.0, 2.8)) + 0.3
    low_end = dome_tip_z + dome_surface_z(3.6) + 0.3
    upper = ((1.0, TOP_DRUM[1] - 0.3, z0), (3.0, 2.8, top_end))
    lower = ((0.0, TRUSS_DRUM[1] - 0.2, z0), (0.0, -3.6, low_end))
    k = [((2.4, 2.4, z0 + 0.3), joint), (joint, (2.4, 2.4, dome_tip_z - 0.4)), (joint, (2.4, -3.2, dome_tip_z - 0.4))]
    return _frame(style, "frame_aft", upper, lower, k)


# --- drum frame -------------------------------------------------------------------------------------------------------
def _drum(radius: float, length: float, style: Style) -> tuple[Mesh, Solid]:
    """A drum along z from 0 to ``length`` whose end faces are RCS clusters."""
    hull, rcs = style.material("hull"), style.material("rcs")
    c = 0.2 * radius
    profile = [(0.0, 0.0), (0.0, radius - c), (c, radius), (length - c, radius), (length, radius - c), (length, 0.0)]
    mesh = lathe(profile, 32, [rcs, hull, hull, hull, rcs], creases={1, 2, 3, 4})
    return mesh, lathe_solid([(0.0, radius - c), (c, radius), (length - c, radius), (length, radius - c)])


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
    (bx, by), (rx, ry) = _longerons()
    frames = []
    for z in (z0 + 0.8, z1 - 0.8):
        frames.append(bar([(1.1, ry, z), (1.1, TOP_DRUM[1] - 1.2, z)], (0.0, 0.0, 1.0), 0.8, 0.8, hull))
        frames.append(bar([(1.2, TRUSS_DRUM[1] - 1.0, z), (LOWER_DRUM[0] - 0.9, LOWER_DRUM[1] + 0.6, z)], (0.0, 0.0, 1.0), 0.9, 0.9, hull))
        frames.append(bar([(rx, ry, z), (LOWER_DRUM[0] - 0.4, LOWER_DRUM[1] + 1.0, z)], (0.0, 0.0, 1.0), 0.7, 0.7, hull))
    pieces.append(_piece("drum_frames", Mesh.concatenate(frames), side=RIGHT, mass_kg=20_000.0))
    lo_y = LOWER_DRUM[1] - DRUM_RADIUS
    hi_y = TOP_DRUM[1] + DRUM_RADIUS
    width = 2.0 * (LOWER_DRUM[0] + DRUM_RADIUS)
    hit = Collision("box", (0.0, 0.5 * (lo_y + hi_y), 0.5 * (z0 + z1)), size=(width, hi_y - lo_y, length))
    pieces[2].part.collision.append(hit)
    return pieces


# --- engine section ---------------------------------------------------------------------------------------------------
def engine_section(style: Style) -> list[Piece]:
    """22.6 m from the collar's front (z = 0): a 9.6 m collar, four propellant tanks round a central one, U-shaped feed
    pipes to the throat and a bell with a 6.3 m exit on the axis."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    R, L = COLLAR_RADIUS, COLLAR_LENGTH
    collar_profile = [(0.0, 0.0), (0.0, R - 0.5), (0.4, R), (L - 0.4, R), (L, R - 0.4), (L, 0.0)]
    collar = lathe(collar_profile, _SECTION_STEPS, [dark, hull, hull, hull, dark], creases={1, 2, 3, 4})
    hit = Collision("capsule", (0.0, 0.0, 0.5 * ENGINE_LENGTH), radius=R, height=ENGINE_LENGTH)
    pieces = [_piece("engine_collar", collar, lathe_solid(collar_profile[1:-1]), mass_kg=300_000.0, collision=[hit])]

    def capsule_tank(radius: float, z0: float, z1: float) -> tuple[Mesh, Solid]:
        steps = 5
        front = [(z0 + radius * 0.6 * (1.0 - math.sin(a)), radius * math.cos(a)) for a in np.linspace(0.5 * math.pi, 0.0, steps)]
        back = [(z1 - radius * 0.6 * (1.0 - math.sin(a)), radius * math.cos(a)) for a in np.linspace(0.0, 0.5 * math.pi, steps)]
        profile = [(z0, 0.0)] + front[1:] + back[:-1] + [(z1, 0.0)]
        return lathe(profile, 32, hull), lathe_solid(profile)

    core, core_solid = capsule_tank(2.55, 1.7, 14.63)
    pieces.append(_piece("engine_core_tank", core, core_solid, mass_kg=200_000.0))
    tank, tank_solid = capsule_tank(1.9, 6.2, 13.4)
    for name, (x, y), side in (("engine_tank_side", (3.0, 0.0), RIGHT), ("engine_tank_top", (0.0, 3.0), CENTRE), ("engine_tank_bottom", (0.0, -3.0), CENTRE)):
        pieces.append(_piece(name, tank.translated((x, y, 0.0)), tank_solid.translated((x, y, 0.0)), side=side, mass_kg=60_000.0))
    # U-shaped pipes in each tank's radial plane: aft out of the tank, over and back into the throat.
    for name, direction, side in (("engine_pipe_side", (1.0, 0.0), RIGHT), ("engine_pipe_top", (0.0, 1.0), CENTRE), ("engine_pipe_bottom", (0.0, -1.0), CENTRE)):
        d = np.array([*direction, 0.0])
        rho_z = [(3.1, 12.9), (3.1, 15.4), (2.85, 16.2), (2.3, 16.55), (1.65, 16.35)]
        path = [d * rho + (0.0, 0.0, z) for rho, z in rho_z]
        width_axis = (-direction[1], direction[0], 0.0)
        pieces.append(_piece(name, bar(path, width_axis, 0.9, 0.9, dark), side=side, mass_kg=5_000.0))
    throat_profile = [(14.0, 0.0), (14.0, 2.2), (16.25, 2.2), (16.25, 0.0)]
    throat = lathe(throat_profile, 40, dark, creases={1, 2})
    pieces.append(_piece("engine_throat", throat, lathe_solid(throat_profile[1:-1]), mass_kg=40_000.0))
    bell = nozzle(BELL, style).translated((0.0, 0.0, ENGINE_LENGTH - BELL.length))
    pieces.append(_piece("engine_bell", bell.mesh, mass_kg=80_000.0))
    return pieces


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

    width: float = 31.06
    height: float = 17.27
    length: float = 43.03
    ridge_u: float = 9.67
    inboard_face: float = 6.02
    outboard_face: float = 3.80
    frame: float = 1.58  # the end frames round the recess
    recess: float = 1.4
    band: float = 3.65  # the raised band round each end
    band_step: float = 0.3
    rail_uv: tuple[float, float] = (-1.78, -0.63)
    rail_radius: float = 1.37
    rail_w: tuple[float, float] = (0.85, 42.23)
    rail_block: tuple[float, float, float] = (4.47, 5.75, 2.38)
    rail_block_uv: tuple[float, float] = (-1.93, 0.04)
    rail_block_w: tuple[float, float] = (0.35, 42.81)
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
def cargo_arm(style: Style, z0: float, z1: float) -> list[Piece]:
    """One arm under a pod's middle (right side, section frame), hung from two brackets on the cylinder's upper flank."""
    hull = style.material("hull")
    size = (ARM_X[1] - ARM_X[0], ARM_Y[1] - ARM_Y[0], z1 - z0)
    centre = (0.5 * sum(ARM_X), 0.5 * sum(ARM_Y), 0.5 * (z0 + z1))
    hangers = []
    top = 4.7
    for zh in (z0 + 0.6, z1 - 0.6):
        path = [(7.1, top, zh), (9.2, top, zh), (ARM_X[0] + 0.6, ARM_Y[1] - 0.2, zh)]
        hangers.append(bar(path, (0.0, 0.0, 1.0), 0.7, 0.6, hull))
    hanger_lo = np.array([7.1, ARM_Y[1] - 0.2, z0 + 0.25])
    hanger_hi = np.array([ARM_X[0] + 1.0, top + 0.35, z1 - 0.25])
    hit = Collision("box", centre, size=size)
    hanger_hit = Collision("box", 0.5 * (hanger_lo + hanger_hi), size=hanger_hi - hanger_lo, name="hangers")
    return [
        _piece("arm", box(size, hull, center=centre), box_solid(size, centre), side=RIGHT, mass_kg=60_000.0, collision=[hit]),
        _piece("arm_hangers", Mesh.concatenate(hangers), side=RIGHT, mass_kg=12_000.0, collision=[hanger_hit]),
    ]


# --- tank section ---------------------------------------------------------------------------------------------------------
def tank_braces(style: Style) -> Mesh:
    """Bars from the spine tank to the right lower tank at three stations along the section (section frame)."""
    hull = style.material("hull")
    d = np.array([LOWER_TANK[0], LOWER_TANK[1]])
    d /= np.linalg.norm(d)
    a = d * 7.6
    b = np.array(LOWER_TANK) - d * 7.6
    meshes = []
    for z in (25.0, 50.0, 75.0):
        meshes.append(bar([(a[0], a[1], z), (b[0], b[1], z)], (0.0, 0.0, 1.0), 1.6, 1.0, hull))
    return Mesh.concatenate(meshes)


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
STACK_GAP_TO_ENGINE = 1.56
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

