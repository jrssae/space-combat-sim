"""Parts of the Earth Alliance atmospheric shuttle, 25.59 m long and 45.6 m across the wings (M10-T57;
docs/design-references.md, "EA atmospheric shuttle").

Built in code from the written description and the measurements of the maintainer's reference model
(``references/EA_Atmospheric_Shuttle.stl``, gitignored): a lens-shaped lifting body with a parabolic planform, a canopy
spine along its back, an intake hump on each shoulder, swept wings with dihedral from the body's aft corners, three
engine nacelles at the flat stern, each with a forked vane above and below it, and a T-tail on a thin fin.

Frame (authored, metres): x to starboard, y up, z aft from the nose tip (z = 0), x and y centred on the reference
model's box. Right pieces are mirrored by the pipeline; the reference's vanes sit 0.15 m off their engines' axes, here
they are centred.
"""

from __future__ import annotations

import math
from collections.abc import Sequence

import numpy as np

from ..core.civilian import CENTRE, RIGHT, Piece
from ..core.geometry import Material, Mesh, lathe, loft, prism
from ..styles import Style
from . import Anchor, Collision
from .ea_shuttle import Y_AXIS, Z_AXIS, box_of, faceted, loft_solid, piece
from .solids import lathe_solid

LENGTH_M = 25.59
EDGE_Y = -0.22  # the height of the body's rim
BODY_END_Z = 17.95  # the flat stern face
# The lifting body: z, half width, crown (y on the centre line), keel (y on the centre line).
BODY_STATIONS = (
    (0.05, 0.35, -0.15, -0.28), (0.25, 1.06, -0.02, -0.42), (0.5, 1.56, 0.08, -0.51), (1.0, 2.25, 0.21, -0.65), (2.0, 3.26, 0.40, -0.84),
    (3.0, 4.08, 0.56, -1.00), (4.0, 4.80, 0.70, -1.13), (6.0, 6.05, 0.94, -1.37), (8.0, 7.11, 1.14, -1.57), (10.0, 8.02, 1.31, -1.75),
    (12.0, 8.80, 1.46, -1.89), (14.0, 9.44, 1.58, -2.02), (16.0, 9.94, 1.67, -2.11), (17.0, 10.12, 1.71, -2.14), (BODY_END_Z, 10.27, 1.74, -2.17),
)  # fmt: skip
BODY_RING_POINTS = 44
RIM_HALF_M = 0.19  # the rim is blunt: this far above and below its height
BODY_RUNS = ((2, 6), (6, 10), (10, 14))  # the runs of stations a hit volume spans
BODY_SLAB = 0.35  # how far towards the body's middle its hit volumes reach, as a share

# The canopy spine: z, half width, top.
SPINE_STATIONS = ((1.78, 1.45, 0.68), (2.75, 1.72, 0.99), (4.64, 1.72, 1.14), (5.59, 1.71, 1.21), (6.54, 1.60, 1.26), (7.48, 1.46, 1.33),
                  (8.43, 1.35, 1.36), (10.32, 1.34, 1.47), (12.22, 1.34, 1.53), (14.11, 1.34, 1.58), (BODY_END_Z, 1.34, 1.61))  # fmt: skip
WINDSHIELD_SEGMENTS = 1  # the spine's first run is the windshield

# The wing's sections out along the span: x, leading edge z, where the flat of the section starts and ends, trailing edge z,
# the section's height, its half thickness and how far the trailing edge droops below it.
WING_STATIONS = (
    (8.60, 14.64, 14.81, 15.87, 17.86, -0.58, 0.21, 0.13),
    (9.50, 14.64, 14.81, 15.87, 17.86, -0.34, 0.21, 0.13),
    (12.60, 16.56, 16.59, 17.51, 19.23, 0.495, 0.195, 0.125),
    (13.20, 16.98, 17.00, 17.89, 21.73, 0.65, 0.19, 0.12),
    (17.70, 20.14, 20.16, 20.79, 23.54, 1.855, 0.145, 0.085),
    (20.20, 21.92, 21.94, 22.43, 24.57, 2.535, 0.115, 0.075),
    (22.75, 23.71, 23.72, 24.07, LENGTH_M, 3.22, 0.09, 0.06),
)
# The tailplane: x, then the section as (z, y) corners from the leading edge's foot round over the top.
TAIL_ROOT = ((18.87, 3.50), (18.87, 3.59), (18.97, 3.67), (19.48, 3.68), (21.18, 3.62), (22.11, 3.50), (19.48, 3.42), (18.97, 3.42))
TAIL_TIP = ((22.92, 4.21), (22.92, 4.24), (22.98, 4.27), (23.24, 4.28), (23.73, 4.25), (24.22, 4.21), (23.24, 4.18), (22.98, 4.18))
TAIL_ROOT_X, TAIL_TIP_X = 0.73, 7.29
# The fin's side view (z, y), cut into convex quads from its foot up.
FIN_QUADS = (
    ((12.75, 1.36), (15.25, 1.47), (17.19, 1.55), (15.68, 2.30)),
    ((15.68, 2.30), (17.19, 1.55), (19.13, 1.55), (20.05, 2.30)),
    ((15.68, 2.30), (20.05, 2.30), (21.36, 3.16), (19.05, 3.16)),
    ((19.05, 3.16), (21.36, 3.16), (21.88, 3.50), (18.95, 3.50)),
)
FIN_OUTLINE = ((12.75, 1.36), (15.25, 1.47), (17.19, 1.55), (19.13, 1.55), (20.05, 2.30), (21.36, 3.16), (21.88, 3.50), (18.95, 3.50),
               (19.05, 3.16), (15.68, 2.30))  # fmt: skip
FIN_THICKNESS = 0.22

ENGINE_X = 4.43  # the outer engines' axes; the third is on the centre line
ENGINE_Y = -0.47
ENGINE_PROFILE = ((17.30, 1.27), (17.69, 1.27), (18.40, 1.56), (21.33, 0.985), (21.67, 0.74))  # z, radius: the nacelle's outside
ENGINE_THROAT = ((21.67, 0.60), (21.03, 0.57))  # the nozzle's inner wall, back to its floor
ENGINE_EXIT_Z = 21.67
ENGINE_EXIT_R = 0.60

# The vanes: forked plates over and under each engine. Half widths (z, dx) of the planform, where the fork's slot starts and
# its half width; the plate's height on its centre line (z, y) and its thickness there; and how far its edges bend towards the
# engine's axis per metre off the centre line.
UPPER_VANE = {"outline": ((18.30, 0.80), (19.50, 1.24), (21.00, 1.45), (21.70, 1.46), (25.38, 0.58)), "slot": (21.70, 0.27),
              "line": ((18.29, 0.99), (24.70, 3.68), (25.08, 3.83), (25.38, 3.83)), "thick": (0.20, 0.11), "bend": -0.31, "side": 1.0}
LOWER_VANE = {"outline": ((18.10, 0.50), (19.00, 1.05), (19.90, 1.21), (20.60, 1.16), (22.54, 0.48)), "slot": (20.60, 0.25),
              "line": ((18.08, -2.00), (22.32, -4.28), (22.54, -4.28)), "thick": (0.17, 0.10), "bend": 0.40, "side": -1.0}
UPPER_STRUT = ((18.60, 0.50), (19.95, 0.40), (19.32, 1.26), (18.77, 1.12))  # the plate between nacelle and vane, side view (z, y)
LOWER_STRUT = ((18.30, -1.60), (19.60, -1.45), (19.11, -2.33), (18.47, -2.10))
STRUT_THICKNESS = 0.24

EYE = (0.0, 0.72, 2.6)  # the pilot's eye behind the windshield


# --- the body -----------------------------------------------------------------------------------------------------------
def body_ring(z: float, half_width: float, crown: float, keel: float, points: int = BODY_RING_POINTS) -> np.ndarray:
    """The body's section at ``z``: a half ellipse over the rim and a deeper one under it, the rim itself a blunt band.
    Counter-clockwise seen from astern, from the starboard rim's upper edge."""
    rim = min(RIM_HALF_M, 0.4 * (crown - EDGE_Y), 0.4 * (EDGE_Y - keel))
    half = points // 2
    arcs = []
    for semi, sign in ((crown - EDGE_Y, 1.0), (EDGE_Y - keel, -1.0)):
        t0 = math.asin(rim / semi)
        a = half_width / math.cos(t0)  # the ellipse is widened so the cut-off rim still reaches the half width
        t = np.linspace(t0, math.pi - t0, half)
        arcs.append(np.column_stack([sign * a * np.cos(t), EDGE_Y + sign * semi * np.sin(t), np.full(half, z)]))
    return np.concatenate(arcs)


def body_top(x: float, z: float) -> float:
    """The body's upper surface over ``(x, z)``; its rim's height outside the planform."""
    zs = [s[0] for s in BODY_STATIONS]
    half_width = float(np.interp(z, zs, [s[1] for s in BODY_STATIONS]))
    crown = float(np.interp(z, zs, [s[2] for s in BODY_STATIONS]))
    if abs(x) >= half_width:
        return EDGE_Y
    return EDGE_Y + (crown - EDGE_Y) * math.sqrt(1.0 - (x / half_width) ** 2)


def _body_collision() -> list[Collision]:
    """The lens as hit volumes: its skin cut into patches, three across each side of the crown and of the keel per run of
    stations, each a box lying on its patch and reaching in towards the body's middle; a box behind the nose tip and one
    inside the flat stern close them."""
    out = [box_of(np.array([[-1.56, -0.51, 0.0], [1.56, 0.08, 0.5]]), "nose"),
           box_of(np.array([[-6.6, -1.3, BODY_END_Z - 0.65], [6.6, 0.9, BODY_END_Z]]), "stern")]
    half = BODY_RING_POINTS // 2
    cuts = (0, 4, 8, half // 2)  # ring corners from the rim to the centre line; the port side mirrors them
    for k, (a, b) in enumerate(BODY_RUNS):
        rings = [body_ring(*station) for station in BODY_STATIONS[a : b + 1]]
        core = np.array([0.0, EDGE_Y, 0.0])
        for face, start in (("top", 0), ("keel", half)):
            for c, (i, j) in enumerate(zip(cuts[:-1], cuts[1:], strict=True)):
                # The starboard patch counts from the rim on the crown and towards it on the keel.
                span = slice(start + i, start + j + 1) if face == "top" else slice(start + half - 1 - j, start + half - i)
                patch = np.concatenate([ring[span] for ring in rings])
                inner = patch + BODY_SLAB * (core - patch) * np.array([1.0, 1.0, 0.0])
                along = rings[-1][span].mean(axis=0) - rings[0][span].mean(axis=0)
                u = along / np.linalg.norm(along)
                across = rings[-1][span][-1] - rings[-1][span][0]
                normal = np.cross(u, across)
                normal /= np.linalg.norm(normal)
                basis = np.column_stack([u, normal, np.cross(u, normal)])
                for tag, flip in (("r", 1.0), ("l", -1.0)):
                    turn = np.diag([flip, 1.0, 1.0])
                    mirrored = turn @ basis @ np.diag([1.0, 1.0, flip])  # mirrored, and still a rotation
                    out.append(box_of(np.concatenate([patch, inner]) * np.array([flip, 1.0, 1.0]), f"{face}{k}{c}_{tag}", mirrored))
    return out


def body_pieces(style: Style) -> list[Piece]:
    """The lifting body, the canopy spine with its windshield, the intake humps and the fairing under the fin."""
    hull, panel, dark, glass, inside = (style.material(r) for r in ("hull", "hull_panel", "hull_dark", "canopy_glass", "interior"))
    rings = [np.array([[0.0, EDGE_Y, 0.0]])] + [body_ring(*s) for s in BODY_STATIONS]
    body = loft(rings, hull, cap_end=True, cap_material=dark)
    solid_rings = [body_ring(*s, points=16) for s in BODY_STATIONS[2:]]

    def spine_ring(z: float, w: float, top: float) -> np.ndarray:
        foot = top - 0.75
        right = [(w, foot), (w, top - 0.45), (0.97 * w, top - 0.22), (0.90 * w, top - 0.07), (0.78 * w, top)]
        return np.array([[x, y, z] for x, y in right] + [[-x, y, z] for x, y in right[::-1]])

    spine_rings = [spine_ring(*s) for s in SPINE_STATIONS]
    paints = [[*[hull] * 9, None] for _ in SPINE_STATIONS[1:]]  # the foot is buried in the body
    for k in range(WINDSHIELD_SEGMENTS):
        paints[k] = [hull, *[glass] * 7, hull, None]
    spine = faceted(spine_rings, paints, cap_start=glass)

    # The intake hump on the starboard shoulder: a flat-topped ridge standing proud at its mouth and sinking into the body aft.
    def intake_ring(z: float, inner: float, outer: float) -> np.ndarray:
        span = outer - inner
        pts = [(outer, -0.15), (outer - 0.01 * span, 0.72), (outer - 0.15 * span, 1.02), (inner + 0.45 * span, 1.28), (inner + 0.16 * span, 1.41),
               (inner + 0.02 * span, 1.17), (inner, 0.30)]
        return np.array([[x, y, z] for x, y in pts])

    intake_rings = [intake_ring(9.22, 3.99, 7.01), intake_ring(13.07, 4.24, 7.83), intake_ring(17.60, 4.36, 8.25)]
    intake = faceted(intake_rings, [hull, hull, panel, panel, hull, hull, None], cap_start=inside)
    fairing = faceted([np.array([[0.8, 1.45, BODY_END_Z - 0.4], [0.8, 1.74, BODY_END_Z - 0.4], [-0.8, 1.74, BODY_END_Z - 0.4], [-0.8, 1.45, BODY_END_Z - 0.4]]),
                       np.array([[0.2, 1.50, 19.18], [0.2, 1.74, 19.18], [-0.2, 1.74, 19.18], [-0.2, 1.50, 19.18]])], hull, cap_end=hull)
    return [
        piece("body", "body", body, 52000.0, solid=loft_solid(2, solid_rings), collision=_body_collision(),
              anchors={"nose": Anchor((0.0, EDGE_Y, 0.0), (0.0, 0.0, -1.0)), "belly": Anchor((0.0, -1.89, 12.0), (0.0, -1.0, 0.0))}),
        piece("spine", "body", [spine, fairing], 2500.0, solid=loft_solid(2, spine_rings),
              collision=[*[box_of(np.concatenate(spine_rings[a : b + 1]), f"run{k}") for k, (a, b) in enumerate(((0, 1), (1, 4), (4, 7), (7, 10)))],
                         box_of(np.array([[-0.8, 1.45, BODY_END_Z - 0.4], [0.8, 1.74, 19.18]]), "fairing")],
              anchors={"eye": Anchor(EYE, (0.0, 0.0, -1.0))}),
        piece("intake_r", "body", intake, 1500.0, RIGHT, solid=loft_solid(2, intake_rings),
              collision=[box_of(np.concatenate([ring[1:6] for ring in intake_rings[:2]]), "mouth"), box_of(np.concatenate([ring[1:6] for ring in intake_rings[1:]]), "aft")]),
    ]


# --- wings and tail -------------------------------------------------------------------------------------------------------
def wing_ring(x: float, lead: float, flat0: float, flat1: float, trail: float, y: float, half: float, droop: float) -> np.ndarray:
    """A wing section at span ``x``: a blunt leading edge, flat upper and lower faces and a sharp, drooped trailing edge."""
    nose = 0.25 * half
    return np.array([[x, y - nose, lead], [x, y - half, flat0], [x, y - half, flat1], [x, y - droop, trail], [x, y + half, flat1],
                     [x, y + half, flat0], [x, y + nose, lead]])


def swept_box(rings: Sequence[np.ndarray], name: str, swept: bool = True) -> Collision:
    """A box round a run of a swept surface's sections, lying along the run so it follows the sweep and the dihedral;
    not ``swept``, it follows the dihedral alone (a tip, where a swept box would reach past the surface's own box)."""
    along = rings[-1].mean(axis=0) - rings[0].mean(axis=0)
    if not swept:
        along[2] = 0.0
    u = along / np.linalg.norm(along)
    n = np.cross(u, Z_AXIS)
    n /= np.linalg.norm(n)
    return box_of(np.concatenate(rings), name, np.column_stack([u, n, np.cross(u, n)]))


def wing_pieces(style: Style) -> list[Piece]:
    """The starboard wing, in a box per run of sections for the hit volumes."""
    hull, panel = style.material("hull"), style.material("hull_panel")
    rings = [wing_ring(*s) for s in WING_STATIONS]
    mesh = faceted(rings, [panel, hull, hull, hull, hull, panel, panel], cap_end=panel)
    boxes = [swept_box(rings[a : b + 1], f"span{k}", swept=b < 6) for k, (a, b) in enumerate(((1, 2), (3, 4), (4, 5), (5, 6)))]
    tip = WING_STATIONS[-1]
    return [piece("wing_r", "wing_r", mesh, 4200.0, RIGHT, collision=boxes, fine=0.7,
                  anchors={"tip": Anchor((tip[0], tip[5], 0.5 * (tip[1] + tip[4])), (1.0, 0.0, 0.0)),
                           "joint": Anchor((WING_STATIONS[1][0], WING_STATIONS[1][5], 16.2))})]


def tail_pieces(style: Style) -> list[Piece]:
    """The fin on the centre line and the swept tailplane across its top."""
    hull, panel = style.material("hull"), style.material("hull_panel")

    def section(x: float, corners: Sequence[tuple[float, float]]) -> np.ndarray:
        return np.array([[x, y, z] for z, y in corners])

    plane_rings = [section(-TAIL_TIP_X, TAIL_TIP), section(-TAIL_ROOT_X, TAIL_ROOT), section(TAIL_ROOT_X, TAIL_ROOT), section(TAIL_TIP_X, TAIL_TIP)]
    plane = faceted(plane_rings, hull, cap_start=panel, cap_end=panel)
    # The fin is a flat plate in the centre plane: the prism's face (local x, y) is the side view (z, y), its thickness along x.
    upright = np.array([[0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]])
    fin = prism([(np.array(q), panel) for q in FIN_QUADS], [(np.array(FIN_OUTLINE), hull)], FIN_THICKNESS).transformed(upright)
    half = 0.5 * FIN_THICKNESS
    fin_boxes = [box_of(np.array([[sx * half, y, z] for z, y in quad for sx in (1.0, -1.0)]), f"fin{k}") for k, quad in enumerate(FIN_QUADS)]
    plane_boxes = [swept_box(plane_rings[k : k + 2], name) for k, name in enumerate(("half_l", "root", "half_r"))]
    return [
        piece("fin", "tail", fin, 900.0, collision=fin_boxes, fine=0.6, anchors={"joint": Anchor((0.0, 1.9, 17.0))}),
        piece("tailplane", "tail", plane, 1300.0, collision=plane_boxes, fine=0.6,
              anchors={"top": Anchor((0.0, 3.68, 19.6), Y_AXIS), "tip_r": Anchor((TAIL_TIP_X, 4.23, 23.5), (1.0, 0.0, 0.0))}),
    ]


# --- engines ----------------------------------------------------------------------------------------------------------------
def vane_mesh(spec: dict, x: float, material: Material, edge: Material) -> Mesh:
    """A forked vane: a thin plate whose planform is ``spec["outline"]`` with a slot cut into its aft end, lying along the
    centre line ``spec["line"]`` and bent towards the engine's axis off it."""
    outline = [(dx, z) for z, dx in spec["outline"]]
    slot_z, slot_w = spec["slot"]
    tip_z, tip_w = spec["outline"][-1]
    fore = [(0.0, outline[0][1]), *outline[:-1], (0.0, slot_z)]  # the solid forward half, one side
    prong = [(slot_w, slot_z), outline[-2], (tip_w, tip_z), (slot_w, tip_z)]
    tiles = [np.array(t) * np.array([sx, 1.0]) for t in (fore, prong) for sx in (1.0, -1.0)]
    right = [*outline, (slot_w, tip_z), (slot_w, slot_z)]
    loop = np.array(right + [(-dx, z) for dx, z in right[::-1]])
    flat = prism([(t, material) for t in tiles], [(loop, edge)], 1.0)
    # The prism's face (local x, y) is the planform (dx, z) and its thickness (local z) becomes the plate's, up and down.
    line_z, line_y = [p[0] for p in spec["line"]], [p[1] for p in spec["line"]]
    v = flat.vertices
    thick = np.interp(v[:, 1], [line_z[0], line_z[-1]], spec["thick"])
    y = np.interp(v[:, 1], line_z, line_y) - spec["side"] * 0.5 * thick + spec["bend"] * np.abs(v[:, 0]) + v[:, 2] * thick
    placed = Mesh(np.column_stack([x + v[:, 0], y, v[:, 1]]), flat.faces, flat.face_material, flat.materials)
    return placed.flipped()  # swapping two axes turned every face inside out


def strut_mesh(side_view: Sequence[tuple[float, float]], x: float, material: Material) -> Mesh:
    upright = np.array([[0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]])
    quad = np.array(side_view)
    return prism([(quad, material)], [(quad, material)], STRUT_THICKNESS).transformed(upright, (x, 0.0, 0.0))


def _vane_collision(spec: dict, x: float, name: str) -> Collision:
    """One box along the vane's slope, as wide as its widest and as thick as its bent edges make it."""
    (z0, y0), (z1, y1) = spec["line"][0], spec["line"][1]
    widest = max(dx for _, dx in spec["outline"])
    end_z = spec["outline"][-1][0]
    end_y = float(np.interp(end_z, [p[0] for p in spec["line"]], [p[1] for p in spec["line"]]))
    slope = np.array([0.0, y1 - y0, z1 - z0]) / math.hypot(y1 - y0, z1 - z0)
    basis = np.column_stack([(1.0, 0.0, 0.0), np.cross(slope, (1.0, 0.0, 0.0)), slope])
    edge = spec["bend"] * widest - spec["side"] * spec["thick"][0]
    pts = np.array([[x + sx * widest, y + dy, z] for z, y in ((z0, y0), (end_z, end_y)) for sx in (1.0, -1.0) for dy in (0.0, edge)])
    return box_of(pts, name, basis)


def engine_piece(style: Style, x: float, name: str, side: str) -> Piece:
    """One engine: the nacelle with its nozzle, the forked vanes above and below it and the plates that carry them."""
    dark, nozzle, throat = (style.material(r) for r in ("hull_dark", "nozzle", "nozzle_throat"))
    outer, inner = list(ENGINE_PROFILE), list(ENGINE_THROAT)
    profile = [(outer[0][0], 0.0), *outer, *inner, (inner[-1][0], 0.0)]
    paints = [dark, dark, dark, nozzle, nozzle, nozzle, throat, throat]
    nacelle = lathe(profile, 20, paints, creases=(1, 2, 3, 4, 5, 6, 7)).translated((x, ENGINE_Y, 0.0))
    meshes = [nacelle, vane_mesh(UPPER_VANE, x, dark, nozzle), vane_mesh(LOWER_VANE, x, dark, nozzle),
              strut_mesh(UPPER_STRUT, x, dark), strut_mesh(LOWER_STRUT, x, dark)]
    solid = lathe_solid(outer).translated((x, ENGINE_Y, 0.0))
    barrel = Collision("capsule", (x, ENGINE_Y, 19.6), radius=1.5, height=5.0, name="nacelle")
    anchors = {"main": Anchor((x, ENGINE_Y, ENGINE_EXIT_Z), Z_AXIS), "centre": Anchor((x, ENGINE_Y, 19.6)),
               "vane_top": Anchor((x, 3.83, 25.2), Y_AXIS), "vane_bottom": Anchor((x, -4.28, 22.4), (0.0, -1.0, 0.0))}
    return piece(name, "engines", meshes, 3800.0, side, solid=solid, fine=0.6, anchors=anchors,
                 collision=[barrel, _vane_collision(UPPER_VANE, x, "vane_up"), _vane_collision(LOWER_VANE, x, "vane_down")])


def assemble(style: Style) -> list[Piece]:
    """Every piece of the shuttle in the authored frame (centre pieces and the starboard of each pair)."""
    return [*body_pieces(style), *wing_pieces(style), *tail_pieces(style), engine_piece(style, 0.0, "engine_c", CENTRE),
            engine_piece(style, ENGINE_X, "engine_r", RIGHT)]
