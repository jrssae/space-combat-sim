"""Parts of the Earth Alliance Panama-class transport, 180 m (M10-T51; docs/design-references.md, "EA Panama-class
transport").

Built in code from the written description and the measurements of the maintainer's reference model (``references/EA
Panama class.STL``, gitignored). The hull is **lopsided**: a wedge in section, tall on the port side (two tubes along
its upper and lower edge) and thinning to a rounded edge to starboard, with the bow spine on the port side and a tube
along the starboard edge of the fore body. Aft, a core between two engines carries flattened tanks above and below it,
two drums by the port engine and a disc tank on the port side.

Frame (authored, metres): x to starboard, y up, z aft from the bow spine's tip (z = 0), x and y centred on the reference
model's box. Every piece is authored where it sits (``LONE``): nothing is mirrored.

The helpers at the top (outlines with round corners, skins with chosen hard edges, bars and ellipsoids) are shared with
``parts/ea_construction_tender.py``.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from itertools import pairwise

import numpy as np

from ..core.civilian import LONE, Piece
from ..core.geometry import Material, Mesh, basis_from_z, lathe, loft, rotation_x, rotation_z
from ..styles import Style
from . import Anchor, Collision
from .ea_shuttle import _ring_normal, block, box_of, faceted, loft_solid, piece, rect_ring
from .solids import box_solid

LENGTH_M = 180.0
AXIS_Y = -0.175  # the height the hull's section is mirrored about: the engines' thrust line
X_AXIS, Y_AXIS, Z_AXIS = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)

# Stations along the hull.
BOW_ROOT_Z = 8.0  # where the nose's taper ends
FORE_Z = (21.6, 43.3)  # the fore body
HOLD_Z = (43.3, 98.0, 153.9)  # the hold's start, the cut between its two chunks, its stern face
STERN_WALL_Z = 149.5  # the wall the engines and the core come out of, set into the hold's open end
ROOF_SLOPE = -0.215  # the roof falls this much a metre to starboard; the keel rises as much
ROOF_AT_0 = 7.025  # the roof's height above the mirror line at x = 0
SLOPE_DEG = math.degrees(math.atan(ROOF_SLOPE))

# The hold's section.
PORT_X = -20.85  # the port face
TUBE_X, TUBE_OFF, TUBE_R = -17.5, 9.85, 3.3  # the tubes along the port face's upper and lower edge
TUBE_END_DEG = 4.0  # where a tube's round meets the roof
EDGE_X, EDGE_R = 17.5, 1.8  # the blunt starboard edge's two round corners: their centre's x and radius
# The fore body's section.
FORE_PORT_X, FORE_CORNER = -19.8, (-17.7, 2.1)  # port face; the round corners' centre (x) and radius
FORE_ROOF_AT_0 = 3.945
FORE_TUBE_X = 8.2  # the starboard tube's axis
# The tube's upper half where it stands out of the fore body, from the roof round to its starboard face (x, height above the axis).
FORE_TUBE = ((5.5, 3.25), (6.6, 3.62), (9.8, 3.62), (10.9, 3.0), (11.5, 1.9), (11.7, 0.6))
# The stern.
ENGINE_X = (-11.7, 11.5)
CORE_HALF = 4.12  # the core's octagon, across flats
CORE_END_Z = 169.0
ENGINE_PROFILE = ((STERN_WALL_Z, 2.7), (157.6, 2.7), (159.3, 1.6), (163.0, 1.6), (164.8, 2.0), (169.4, 2.0), (LENGTH_M, 3.95))
ENGINE_THROAT = (175.0, 1.55)
RAIL_R = 4.2  # the four rails round each engine stand this far off its axis
EYE = (-15.0, 0.0, 9.5)  # the pilot's eye in the bow spine


# --- shared helpers ----------------------------------------------------------------------------------------------------------
def arc(centre: Sequence[float], radius: float, deg0: float, deg1: float, steps: int) -> np.ndarray:
    """Points of an arc in a plane from ``deg0`` to ``deg1`` (both included)."""
    t = np.radians(np.linspace(deg0, deg1, steps + 1))
    return np.stack([centre[0] + radius * np.cos(t), centre[1] + radius * np.sin(t)], axis=1)


def at_z(outline: np.ndarray, z: float) -> np.ndarray:
    """A plane outline (x, y) stood across the hull at ``z``."""
    return np.column_stack([outline, np.full(len(outline), z)])


def skin(rings: Sequence[np.ndarray], runs: Sequence[tuple[int, int]], paints: Material | Sequence[Material | None],
         cap_start: Material | None = None, cap_end: Material | None = None) -> Mesh:
    """A solid skinned through closed rings of equal size whose edges are hard only where asked: each run ``(first, last)``
    of ring corners is one smooth face (an arc) or, with two corners, a flat one, and runs meet in hard edges. ``last``
    may pass the ring's end to close it. ``paints`` is one material or one per run (``None``: no faces). A cap is a fan
    about the ring's middle, so the outline need not be convex, only open to its middle."""
    rings = [np.asarray(ring, dtype=float).reshape(-1, 3) for ring in rings]
    n = len(rings[0])
    per_run = [paints] * len(runs) if isinstance(paints, Material) else list(paints)
    turned = float(_ring_normal(rings[0]) @ (rings[-1].mean(axis=0) - rings[0].mean(axis=0))) < 0.0
    table: list[Material] = []
    verts: list[np.ndarray] = []
    faces: list[list[int]] = []
    mats: list[int] = []
    count = 0

    def index(material: Material) -> int:
        if material not in table:
            table.append(material)
        return table.index(material)

    for a, b in pairwise(rings):
        for (first, last), material in zip(runs, per_run, strict=True):
            if material is None:
                continue
            corners = [k % n for k in range(first, last + 1)]
            m = len(corners)
            verts += [a[corners], b[corners]]
            for k in range(m - 1):
                quad = [count + k, count + k + 1, count + m + k + 1, count + m + k]
                quad = quad[::-1] if turned else quad
                faces += [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]
                mats += [index(material)] * 2
            count += 2 * m
    for ring, material, forward in ((rings[0], cap_start, False), (rings[-1], cap_end, True)):
        if material is None:
            continue
        verts += [ring, ring.mean(axis=0, keepdims=True)]
        for k in range(n):
            tri = [count + k, count + (k + 1) % n, count + n]
            faces.append(tri if forward != turned else tri[::-1])
            mats.append(index(material))
        count += n + 1
    mesh = Mesh(np.concatenate(verts), np.array(faces), np.array(mats), tuple(table))
    return mesh.face_subset(mesh.face_areas() > 1e-9)


def bar(a: Sequence[float], b: Sequence[float], radius: float, material: Material, segments: int = 8) -> Mesh:
    """A round bar between two points."""
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    length = float(np.linalg.norm(b - a))
    tube = lathe([(0.0, 0.0), (0.0, radius), (length, radius), (length, 0.0)], segments, material, creases=(1, 2))
    return tube.transformed(basis_from_z(b - a), a)


def ellipsoid(centre: Sequence[float], radii: Sequence[float], material: Material, roll_deg: float = 0.0, segments: int = 20,
              rings: int = 10) -> Mesh:
    """An ellipsoid with the given half axes along x, y and z, then rolled about z."""
    t = np.linspace(0.0, math.pi, rings + 1)
    ball = lathe([(-math.cos(v), math.sin(v) if 0 < k < rings else 0.0) for k, v in enumerate(t)], segments, material)
    return ball.transformed(rotation_z(math.radians(roll_deg)) @ np.diag(radii), centre)


def drum_y(centre: Sequence[float], radius: float, height: float, material: Material, bevel: float = 0.3, segments: int = 20) -> Mesh:
    """A short drum standing on the y axis, its rims bevelled."""
    h = 0.5 * height
    profile = [(-h, 0.0), (-h, radius - bevel), (-h + bevel, radius), (h - bevel, radius), (h, radius - bevel), (h, 0.0)]
    return lathe(profile, segments, material, creases=(1, 2, 3, 4)).transformed(rotation_x(-0.5 * math.pi), centre)


def slab_on_slope(centre: Sequence[float], width: float, thick: float, z0: float, z1: float, slope_deg: float, material: Material,
                  chamfer: float = 0.4) -> tuple[Mesh, Collision]:
    """A flat box lying on a face that slopes ``slope_deg`` about z, its long edges chamfered; ``centre`` is its middle in x
    and y. Returns the mesh and its hit volume."""
    w, t, c = 0.5 * width, 0.5 * thick, chamfer
    section = np.array([[-w, -t + c], [-w + c, -t], [w - c, -t], [w, -t + c], [w, t - c], [w - c, t], [-w + c, t], [-w, t - c]])
    turn = rotation_z(math.radians(slope_deg))
    rings = [at_z(section, z) @ turn.T + np.array([centre[0], centre[1], 0.0]) for z in (z0, z1)]
    hit = Collision("box", (centre[0], centre[1], 0.5 * (z0 + z1)), basis=turn, size=(width, thick, z1 - z0), name="slab")
    return faceted(rings, material, cap_start=material, cap_end=material), hit


def lone(name: str, group: str, meshes: Mesh | Sequence[Mesh], mass_kg: float, **more) -> Piece:
    """A piece authored where it sits, with no twin."""
    return piece(name, group, meshes, mass_kg, LONE, **more)


# --- sections ----------------------------------------------------------------------------------------------------------------
def roof_y(x: float, at_0: float = ROOF_AT_0) -> float:
    """The roof's height at ``x`` (the keel is its mirror image about :data:`AXIS_Y`)."""
    return AXIS_Y + at_0 + ROOF_SLOPE * x


def _mirrored_outline(upper: np.ndarray) -> np.ndarray:
    """A closed outline from its upper half (running to starboard): the lower half is the upper's mirror about the axis."""
    lower = upper[::-1] * np.array([1.0, -1.0]) + np.array([0.0, 2.0 * AXIS_Y])
    return np.concatenate([upper, lower])


ARC_STEPS = 8
Runs = list[tuple[int, int]]


def _faces(port: int, round_: int, far: int) -> Runs:
    """The faces of a mirrored outline that starts at the port face's middle: ``round_`` corners in the port round, ``far``
    in the starboard one. In order: port face, upper round, roof, upper starboard round, starboard end, lower starboard
    round, keel, lower round."""
    half = port + round_ + far
    n = 2 * half - 1
    a, e = round_, far
    return [(n - 1, n + 1), (1, a), (a, a + 1), (a + 1, a + e), (a + e, a + e + 1), (half, half + e - 1), (half + e - 1, half + e),
            (half + e, half + e + a - 1)]


def _round_under(x: float, radius: float, at_0: float) -> np.ndarray:
    """A round corner that runs from straight up into the roof's slope, placed so it ends on the roof: centred at ``x``."""
    turn = math.radians(90.0 + SLOPE_DEG)
    touch = x + radius * math.cos(turn)
    return np.array([x, roof_y(touch, at_0) - radius * math.sin(turn)])


def hold_outline() -> tuple[np.ndarray, Runs]:
    """The hold's section and its faces (:func:`_faces`)."""
    tube = arc((TUBE_X, AXIS_Y + TUBE_OFF), TUBE_R, 180.0, TUBE_END_DEG, ARC_STEPS)
    tube[-1, 1] = roof_y(tube[-1, 0])
    edge = arc(_round_under(EDGE_X, EDGE_R, ROOF_AT_0), EDGE_R, 90.0 + SLOPE_DEG, 0.0, ARC_STEPS // 2)
    upper = np.concatenate([[[PORT_X, AXIS_Y]], tube, edge])
    return _mirrored_outline(upper)[:-1], _faces(1, len(tube), len(edge))


def fore_outline() -> tuple[np.ndarray, Runs]:
    """The fore body's section and its faces (:func:`_faces`; its starboard round is the tube)."""
    cx, r = FORE_CORNER
    corner = arc(_round_under(cx, r, FORE_ROOF_AT_0), r, 180.0, 90.0 + SLOPE_DEG, ARC_STEPS // 2)
    tube = np.array(FORE_TUBE) + np.array([0.0, AXIS_Y])
    upper = np.concatenate([[[FORE_PORT_X, AXIS_Y]], corner, [[4.9, roof_y(4.9, FORE_ROOF_AT_0)]], tube])
    return _mirrored_outline(upper)[:-1], _faces(1, len(corner), 1 + len(tube))


# --- the hull ----------------------------------------------------------------------------------------------------------------
def _wedge_boxes(z0: float, z1: float, port_x: float, top: float, steps: Sequence[tuple[float, float, float]]) -> list[Collision]:
    """Hit volumes of a wedge section between two stations: the tall port column, then boxes stepping down to starboard
    (``steps``: x from, x to, half height)."""
    out = [box_of(np.array([[port_x, AXIS_Y - top, z0], [steps[0][0], AXIS_Y + top, z1]]), "port")]
    out += [box_of(np.array([[x0, AXIS_Y - h, z0], [x1, AXIS_Y + h, z1]]), f"step{k}") for k, (x0, x1, h) in enumerate(steps)]
    return out


HOLD_STEPS = ((-14.2, -7.0, 8.4), (-7.0, 0.0, 6.9), (0.0, 7.0, 5.4), (7.0, 13.0, 4.0), (13.0, 19.3, 2.7))
FORE_STEPS = ((-15.6, -9.0, 5.9), (-9.0, -2.0, 4.4), (-2.0, 4.7, 3.1), (4.7, 11.7, 3.6))


def hold_pieces(style: Style) -> list[Piece]:
    """The hold in its two chunks, the stern one open aft with the wall set into it; the raised band along the port face and
    the plate over its after end; the slabs on the roof and the keel aft."""
    hull, panel, patch, dark, inside = (style.material(r) for r in ("hull", "hull_panel", "hull_patch", "hull_dark", "interior"))
    outline, runs = hold_outline()
    paints = [hull, panel, patch, hull, hull, hull, patch, panel]  # the roof and the keel wear the lighter plating
    inner = np.array([0.0, AXIS_Y]) + (outline - np.array([0.0, AXIS_Y])) * np.array([0.965, 0.94])  # the open end's rim
    z0, cut, z1 = HOLD_Z
    fore = skin([at_z(outline, z0), at_z(outline, cut)], runs, paints, cap_start=hull, cap_end=inside)
    aft = [skin([at_z(outline, cut), at_z(outline, z1)], runs, paints, cap_start=inside),
           skin([at_z(outline, z1), at_z(inner, z1)], runs, dark),  # the open end's rim
           skin([at_z(inner, z1), at_z(inner, STERN_WALL_Z)], runs, dark, cap_end=dark).flipped()]
    quad = np.array([[PORT_X, roof_y(PORT_X)], [EDGE_X, roof_y(EDGE_X)], [EDGE_X, 2 * AXIS_Y - roof_y(EDGE_X)], [PORT_X, 2 * AXIS_Y - roof_y(PORT_X)]])
    top = TUBE_OFF + TUBE_R

    plate_rings = [rect_ring(2, 131.2, (PORT_X - 0.1, AXIS_Y - 7.6), (PORT_X + 0.1, AXIS_Y + 7.6)),
                   rect_ring(2, 133.6, (-22.4, AXIS_Y - 7.6), (PORT_X + 0.1, AXIS_Y + 7.6)),
                   rect_ring(2, 154.2, (-22.4, AXIS_Y - 7.6), (PORT_X + 0.1, AXIS_Y + 7.6))]
    pieces = [
        lone("hold_fore", "hold_fore", fore, 900_000.0, solid=loft_solid(2, [at_z(quad, z0), at_z(quad, cut)]),
             collision=_wedge_boxes(z0, cut, PORT_X, top, HOLD_STEPS)),
        lone("hold_aft", "hold_aft", aft, 900_000.0, solid=loft_solid(2, [at_z(quad, cut), at_z(quad, STERN_WALL_Z)]),
             collision=_wedge_boxes(cut, z1, PORT_X, top, HOLD_STEPS)),
        lone("port_band_fore", "hold_fore", block((-21.4, AXIS_Y - 5.25, 47.5), (PORT_X + 0.05, AXIS_Y + 5.25, cut), dark), 20_000.0,
             collision=[box_of(np.array([[-21.4, AXIS_Y - 5.25, 47.5], [PORT_X, AXIS_Y + 5.25, cut]]), "band")]),
        lone("port_band_aft", "hold_aft", block((-21.4, AXIS_Y - 5.25, cut), (PORT_X + 0.05, AXIS_Y + 5.25, 131.0), dark), 14_000.0,
             collision=[box_of(np.array([[-21.4, AXIS_Y - 5.25, cut], [PORT_X, AXIS_Y + 5.25, 131.0]]), "band")]),
        lone("port_plate", "hold_aft", faceted(plate_rings, patch, cap_start=patch, cap_end=patch), 30_000.0,
             collision=[box_of(np.array([[-22.4, AXIS_Y - 7.6, 131.2], [PORT_X, AXIS_Y + 7.6, 154.2]]), "plate")]),
    ]
    # The slabs: a broad one over the hold's after end and a small one by the starboard edge, on the roof and under the keel.
    for name, sign in (("roof", 1.0), ("keel", -1.0)):
        for tag, x, width, thick, proud, za, zb, mass in (("slab", -1.7, 18.8, 2.6, 1.55, 131.0, 154.9, 60_000.0),
                                                         ("hatch", 12.45, 7.6, 2.6, 1.65, 142.7, 153.5, 15_000.0)):
            y = AXIS_Y + sign * (roof_y(x) - AXIS_Y + proud - 0.5 * thick)
            mesh, hit = slab_on_slope((x, y), width, thick, za, zb, sign * SLOPE_DEG, panel if tag == "slab" else patch)
            pieces.append(lone(f"{name}_{tag}", "hold_aft", mesh, mass, collision=[hit]))
    return pieces


def fore_pieces(style: Style) -> list[Piece]:
    """The fore body with its starboard tube's nose, and the box on its roof."""
    hull, panel, patch, dark = (style.material(r) for r in ("hull", "hull_panel", "hull_patch", "hull_dark"))
    outline, runs = fore_outline()
    z0, z1 = FORE_Z
    body = skin([at_z(outline, z0), at_z(outline, z1)], runs, [hull, hull, patch, panel, panel, panel, patch, hull], cap_start=hull, cap_end=hull)
    tx, tr = FORE_TUBE_X, FORE_TUBE[1][1]
    nose = lathe([(17.3, 0.0), (17.3, 2.0), (18.0, 2.55), (z0 + 0.1, 2.55)], 16, panel, creases=(1, 2)).translated((tx - 0.15, AXIS_Y, 0.0))
    top = roof_y(FORE_PORT_X, FORE_ROOF_AT_0) - AXIS_Y
    quad = np.array([[FORE_PORT_X, AXIS_Y + top - 0.6], [tx, AXIS_Y + tr], [tx, AXIS_Y - tr], [FORE_PORT_X, AXIS_Y - top + 0.6]])
    return [
        lone("fore_body", "bow", [body, nose], 250_000.0, solid=loft_solid(2, [at_z(quad, z0), at_z(quad, z1)]),
             collision=[*_wedge_boxes(z0, z1, FORE_PORT_X, top - 0.4, FORE_STEPS),
                        box_of(np.array([[tx - 2.7, AXIS_Y - 2.55, 17.3], [tx + 2.4, AXIS_Y + 2.55, z0]]), "tube_nose")]),
        lone("fore_box", "bow", block((-15.6, 6.3, 40.0), (-12.6, 9.3, z1 + 0.2), dark), 4_000.0,
             collision=[box_of(np.array([[-15.6, 6.3, 40.0], [-12.6, 9.3, z1]]), "box")]),
    ]


BOW_X = -14.95  # the bow spine's axis
BOW_SECTION = np.array([[-2.65, 4.1], [-3.75, 2.2], [-3.95, -0.9], [-3.45, -3.6], [-2.45, -4.4], [2.45, -4.4], [3.45, -3.6], [3.95, -0.9],
                        [3.75, 2.2], [2.65, 4.1]])  # about the spine's axis, counter-clockwise seen from astern
# The nose's taper: z, the section's scale in x and y, its lift.
BOW_STATIONS = ((0.0, 0.56, 0.34, -0.95), (1.0, 0.68, 0.48, -0.9), (4.0, 0.88, 0.70, -0.7), (6.5, 0.97, 0.90, -0.35), (BOW_ROOT_Z, 1.0, 1.0, 0.0),
                (FORE_Z[0] + 0.2, 1.0, 1.0, 0.0))


def bow_pieces(style: Style) -> list[Piece]:
    """The bow spine on the port side: its tapered nose, the fairing at its root and the rods along it."""
    hull, panel, dark = (style.material(r) for r in ("hull", "hull_panel", "hull_dark"))
    rings = [np.column_stack([BOW_X + sx * BOW_SECTION[:, 0], lift + sy * BOW_SECTION[:, 1], np.full(len(BOW_SECTION), z)])
             for z, sx, sy, lift in BOW_STATIONS]
    spine = loft(rings, hull)
    fairing = faceted([np.array([[-11.2, -3.0, 17.5], [-11.0, -3.0, 17.5], [-11.0, 3.0, 17.5], [-11.2, 3.0, 17.5]]),
                       np.array([[-11.2, -3.0, FORE_Z[0]], [-8.8, -3.0, FORE_Z[0]], [-8.8, 3.0, FORE_Z[0]], [-11.2, 3.0, FORE_Z[0]]])],
                      panel, cap_start=panel, cap_end=panel)
    rods = [bar((x, y, 13.0), (x, y, FORE_Z[0] + 0.1), 0.33, dark) for x in (-16.6, -15.0) for y in (5.25, -5.6)]
    rods += [bar((-10.65, y, 9.8), (-10.65, y, FORE_Z[0] + 0.1), 0.25, dark) for y in (4.0, -4.3)]
    return [
        lone("bow_spine", "bow", spine, 120_000.0, solid=box_solid((7.0, 7.6, FORE_Z[0] - BOW_ROOT_Z), (BOW_X, -0.15, 0.5 * (FORE_Z[0] + BOW_ROOT_Z))),
             collision=[box_of(np.array([[BOW_X - 3.95, -4.4, BOW_ROOT_Z], [BOW_X + 3.95, 4.1, FORE_Z[0]]]), "spine"),
                        box_of(np.array([[BOW_X - 3.3, -3.7, 3.0], [BOW_X + 3.3, 2.6, BOW_ROOT_Z]]), "nose"),
                        box_of(np.array([[BOW_X - 2.4, -2.6, 0.0], [BOW_X + 2.4, 0.9, 3.0]]), "tip")],
             anchors={"eye": Anchor(EYE, (0.0, 0.0, -1.0)), "tip": Anchor((BOW_X, -1.0, 0.0), (0.0, 0.0, -1.0))}),
        lone("bow_fairing", "bow", fairing, 3_000.0, collision=[box_of(np.array([[-11.2, -3.0, 18.8], [-9.4, 3.0, FORE_Z[0]]]), "fairing")]),
        lone("bow_rods", "bow", rods, 2_000.0, fine=0.5,
             collision=[box_of(np.array([[-16.95, 4.9, 13.0], [-14.65, 5.6, FORE_Z[0]]]), "up"), box_of(np.array([[-16.95, -5.95, 13.0], [-14.65, -5.25, FORE_Z[0]]]), "down")]),
    ]


# --- the stern ---------------------------------------------------------------------------------------------------------------
def engine_mesh(style: Style, x: float) -> list[Mesh]:
    """One engine: a drum in the hold's open end, a waist, a long bell, and four rails round it held by a ring at the bell."""
    nozzle, throat, dark = style.material("nozzle"), style.material("nozzle_throat"), style.material("hull_dark")
    outer = [(ENGINE_PROFILE[0][0], 0.0), *ENGINE_PROFILE]
    bell = lathe([*outer, ENGINE_THROAT, (ENGINE_THROAT[0], 0.0)], 24, [dark, dark, dark, dark, dark, nozzle, nozzle, throat, throat],
                 creases=(1, 2, 3, 4, 5, 6, 7, 8)).translated((x, AXIS_Y, 0.0))
    fittings = []
    for a in (0.0, 0.5 * math.pi, math.pi, 1.5 * math.pi):
        rx, ry = x + RAIL_R * math.cos(a), AXIS_Y + RAIL_R * math.sin(a)
        fittings.append(bar((rx, ry, STERN_WALL_Z), (rx, ry, 178.6), 0.28, dark))
        fittings.append(block((rx - 0.45, ry - 0.45, 176.2), (rx + 0.45, ry + 0.45, 178.8), dark))
    return [bell, *fittings]


def stern_pieces(style: Style) -> list[Piece]:
    """Aft of the hold: the core, the two engines, the flattened tanks above and below the core, the two drums by the port
    engine and the disc tank on the port side."""
    panel, dark, tank, patch = (style.material(r) for r in ("hull_panel", "hull_dark", "hazard", "hull_patch"))
    k = CORE_HALF * math.tan(math.pi / 8.0)
    octagon = np.array([[CORE_HALF, -k], [CORE_HALF, k], [k, CORE_HALF], [-k, CORE_HALF], [-CORE_HALF, k], [-CORE_HALF, -k], [-k, -CORE_HALF], [k, -CORE_HALF]])
    octagon = octagon + np.array([0.0, AXIS_Y - 0.05])
    core = faceted([at_z(octagon, STERN_WALL_Z), at_z(octagon, CORE_END_Z)], panel, cap_end=dark)
    out = [lone("core", "stern", core, 80_000.0, solid=loft_solid(2, [at_z(octagon, STERN_WALL_Z), at_z(octagon, CORE_END_Z)]),
                collision=[box_of(np.array([[-CORE_HALF, AXIS_Y - CORE_HALF, STERN_WALL_Z], [CORE_HALF, AXIS_Y + CORE_HALF, CORE_END_Z]]), "core")])]
    for name, x in zip(("engine_l", "engine_r"), ENGINE_X, strict=True):
        out.append(lone(name, "stern", engine_mesh(style, x), 60_000.0, fine=0.6,
                        collision=[Collision("capsule", (x, AXIS_Y, 166.0), radius=3.0, height=27.0, name="engine")],
                        anchors={"main": Anchor((x, AXIS_Y, ENGINE_THROAT[0]), Z_AXIS), "centre": Anchor((x, AXIS_Y, 160.0)),
                                 "side": Anchor((x + math.copysign(RAIL_R + 0.3, x), AXIS_Y, 170.0), (math.copysign(1.0, x), 0.0, 0.0))}))
    for name, sign in (("tank_up", 1.0), ("tank_down", -1.0)):
        centre = (-1.1, AXIS_Y + sign * 7.35, 162.3)
        strut = block((-0.9, AXIS_Y + sign * 3.9 - 0.5, 156.0), (-0.3, AXIS_Y + sign * 3.9 + 0.5, 166.5), dark)
        out.append(lone(name, "stern", [ellipsoid(centre, (6.6, 2.25, 6.7), tank, sign * SLOPE_DEG), strut], 25_000.0,
                        collision=[Collision("box", centre, basis=rotation_z(math.radians(sign * SLOPE_DEG)), size=(11.0, 3.6, 11.0), name="tank")],
                        anchors={"top": Anchor((centre[0], centre[1] + sign * 2.3, centre[2]), (0.0, sign, 0.0))}))
        drum = (-12.7, AXIS_Y + sign * 7.5, 158.7)
        post = block((-12.2, AXIS_Y + sign * 2.6, 157.2), (-11.2, AXIS_Y + sign * 5.7, 158.4), dark)
        out.append(lone(f"drum_{name[5:]}", "stern", [drum_y(drum, 3.9, 3.8, patch), post], 12_000.0,
                        collision=[box_of(np.array([[drum[0] - 2.8, drum[1] - 1.9, drum[2] - 2.8], [drum[0] + 2.8, drum[1] + 1.9, drum[2] + 2.8]]), "drum")]))
    disc = (-19.25, AXIS_Y + 0.1, 162.3)
    arm = block((-19.0, AXIS_Y - 0.25, 149.6), (-16.3, AXIS_Y + 0.25, 169.0), dark)
    out.append(lone("tank_port", "stern", [ellipsoid(disc, (2.25, 6.7, 6.7), tank), arm], 20_000.0,
                    collision=[box_of(np.array([[disc[0] - 1.6, disc[1] - 5.2, disc[2] - 5.2], [disc[0] + 1.6, disc[1] + 5.2, disc[2] + 5.2]]), "tank")],
                    anchors={"side": Anchor((disc[0] - 2.25, disc[1], disc[2]), (-1.0, 0.0, 0.0))}))
    return out


def whisker_pieces(style: Style) -> list[Piece]:
    """The thin aerials standing off the hold at two stations: one from each tube and one from the starboard edge."""
    dark = style.material("hull_dark")
    out = []
    for group, z in (("hold_fore", 64.3), ("hold_aft", 148.5)):
        rods = [bar((19.2, AXIS_Y, z), (22.43, AXIS_Y, z), 0.14, dark, 6)]
        rods += [bar((-19.6, s * 12.5, z), (-21.7, s * 14.72, z), 0.14, dark, 6) for s in (1.0, -1.0)]
        out.append(lone(f"aerials_{group[5:]}", group, rods, 150.0, fine=0.3))
    return out


def assemble(style: Style) -> list[Piece]:
    """Every piece of the Panama in the authored frame."""
    return [*bow_pieces(style), *fore_pieces(style), *hold_pieces(style), *stern_pieces(style), *whisker_pieces(style)]
