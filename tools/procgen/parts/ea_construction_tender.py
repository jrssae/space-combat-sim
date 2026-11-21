"""Parts of the Earth Alliance construction tender, 50 m (M10-T55; docs/design-references.md, "EA construction tender").

Built in code from the written description and the measurements of the maintainer's reference model
(``references/EA_construction_tender.stl``, gitignored): a hexagonal work body with a glazed pyramid nose, four tubes
along its corners, two grab arms on the centre line (above and below the nose), four three-bladed claws on ball joints
at its shoulders, a lattice boom across its after end with a thruster pod at each tip, and four landing feet.

Frame (authored, metres): x to starboard, y up, z aft from the grabs' tips (z = 0), x and y centred on the reference
model's box. The body is a centre piece, the boom and pods are right pieces mirrored by the pipeline, and the claws
are ``LONE``: each stands at its own angle, port and starboard posed differently, as the reference has them.
"""

from __future__ import annotations

import math
from collections.abc import Sequence

import numpy as np

from ..core.civilian import LONE, RIGHT, Piece
from ..core.geometry import Material, Mesh, basis_from_z, lathe, prism, unit
from ..styles import Style
from . import Anchor, Collision
from .ea_panama import at_z, bar, drum_y, ellipsoid
from .ea_shuttle import block, box_of, faceted, loft_solid, piece

LENGTH_M = 50.0
X_AXIS, Y_AXIS, Z_AXIS = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)

# The body: a hexagon standing on its flat (x half width at the waist, the waist's height, the flats' half width, top, bottom).
HEX = (5.7, 0.6, 2.9, 7.1, -5.9)
STERN_HEX = (5.95, 1.2, 3.05, 7.6, -7.2)
NOSE_TIP = (0.0, 0.9, 9.7)
# The glazed nose's hexagons between its tip and the body: z, then a hexagon as HEX.
NOSE = ((12.0, (2.6, 0.7, 1.5, 3.1, -1.7)), (14.8, (5.5, 0.6, 2.6, 4.7, -4.5)))
BODY_Z = (14.8, 36.5, 46.3)  # the nose's base, the cut between the body and stern chunks, the stern face
TUBE_AT = ((2.55, 6.1), (2.55, -4.6))  # the corner tubes' axes (x mirrored), their radius below
TUBE_R = 2.05
TUBE_Z = (17.3, 32.0)
# The blocks the claws hang from, above and below: (low, high) to starboard, then to port.
SHOULDERS = (((4.2, 9.3), (4.2, 8.9)), ((-7.05, -2.3), (-7.5, -2.3)))
ARM_Y = (7.1, -5.6)  # the two grab arms' axes, on the centre line
EYE = (0.0, 0.7, 13.6)  # the pilot's eye behind the nose's glass

# The boom: a box lattice from the body out to each pod, drooping a little outboard.
BOOM_X = (4.0, 27.2)  # its chords' ends: inside the body, at the pod
BOOM_Z = (38.47, 43.33)  # its forward and after chords
BOOM_FALL = -0.035  # the chords fall this much a metre outboard
BOOM_TOP, BOOM_BOTTOM = 7.37, 3.0  # the upper and lower chords' height at x = 15
BOOM_NODES = tuple(5.3 + 3.85 * k for k in range(6))  # where the uprights meet the upper chords
BOOM_LEAN = 1.4  # an upright's foot stands this far outboard of its head
CHORD_R, BRACE_R = 0.31, 0.2
POD_AT = (29.92, 4.646)  # each pod's axis
POD_R = 3.165
POD_Z = (32.2, 50.0)
JET_REACH = 4.93  # the pod's small thrusters end this far off its axis
GEAR_X = -0.95  # the landing gear stands off the centre line
FEET = ((7.65, 14.25), (7.65, 29.4))  # the landing feet: x either side of the gear's own centre line, and z

# A claw: three flat sickle blades round an axis. Stations along a blade: the outer edge (along the axis, off it), then the inner.
BLADE = (
    ((0.0, 1.75), (0.0, 1.0)), ((1.0, 2.05), (1.0, 0.3)), ((2.0, 2.8), (2.4, 0.35)), ((3.3, 3.6), (3.7, 0.4)), ((3.4, 4.35), (3.7, 1.3)), ((4.6, 4.45), (4.2, 1.7)),
    ((6.0, 4.5), (4.9, 2.6)), ((7.5, 4.45), (5.7, 2.95)), ((9.5, 4.2), (8.0, 3.0)), ((11.5, 3.75), (10.5, 2.7)), ((13.5, 3.1), (12.9, 2.05)),
    ((15.2, 2.4), (13.0, 1.75)), ((16.6, 1.8), (16.6, 1.72)),
)  # fmt: skip
BLADE_THICK = 0.28
BLADE_ROLL_DEG = (97.5, -22.5, -142.5)
# Each claw: name, chunk, the hub (where its blades' stations start), its axis, how far its arm reaches back to the joint.
CLAWS = (
    ("claw_up_r", "claws_r", (8.35, 7.09, 26.46), (0.415, 0.067, -0.907), 2.2),
    ("claw_down_r", "claws_r", (8.37, -4.39, 26.48), (0.41, 0.069, -0.91), 2.2),
    ("claw_up_l", "claws_l", (-9.12, 6.53, 25.48), (-0.506, -0.068, -0.86), 3.8),
    ("claw_down_l", "claws_l", (-8.48, -4.78, 26.89), (-0.5, -0.074, -0.863), 2.2),
)


def hexagon(shape: Sequence[float], z: float, scale: float = 1.0, about: Sequence[float] = (0.0, 0.0)) -> np.ndarray:
    """The body's hexagon at ``z``, counter-clockwise seen from astern from its starboard waist; ``scale`` shrinks it towards
    ``about``."""
    w, mid, flat, top, bottom = shape
    ring = np.array([[w, mid], [flat, top], [-flat, top], [-w, mid], [-flat, bottom], [flat, bottom]])
    ring = np.asarray(about) + scale * (ring - np.asarray(about))
    return at_z(ring, z)


def tube_z(x: float, y: float, profile: Sequence[tuple[float, float]], materials: Material | Sequence[Material], segments: int = 16,
           creases: Sequence[int] | None = None) -> Mesh:
    """A solid of revolution along z through ``(x, y)``, every profile corner a hard edge unless ``creases`` names them."""
    hard = range(1, len(profile) - 1) if creases is None else creases
    return lathe(list(profile), segments, materials, creases=hard).translated((x, y, 0.0))


# --- the body ----------------------------------------------------------------------------------------------------------------
def body_pieces(style: Style) -> list[Piece]:
    """The work body: the glazed nose, the hexagon with its box and corner tubes, the housings at its bow corners with their
    canted drums, the shoulder blocks the claws hang from, and the stern block with its tanks and fan panel."""
    hull, panel, dark, glass, frame, inside = (style.material(r) for r in ("hull", "hull_panel", "hull_dark", "canopy_glass", "canopy_frame", "interior"))
    nozzle, tank = style.material("nozzle"), style.material("band_light")
    z0, cut, z1 = BODY_Z
    tip = np.array(NOSE_TIP)
    nose_rings = [hexagon(NOSE[0][1], tip[2] + 0.1, 0.04, tip[:2]), *(hexagon(shape, z) for z, shape in NOSE)]
    nose = faceted(nose_rings, glass, cap_start=frame, cap_end=inside)
    ribs = [bar(a, b, 0.16, frame, 6) for one, two in zip(nose_rings[:-1], nose_rings[1:], strict=True) for a, b in zip(one, two, strict=True)]
    ribs += [bar(a, b, 0.16, frame, 6) for ring in nose_rings[1:] for a, b in zip(ring, np.roll(ring, -1, axis=0), strict=True)]
    ribs.append(ellipsoid(tip - np.array([0.0, 0.0, 0.25]), (0.45, 0.45, 0.45), frame, segments=10, rings=6))
    mid = [hexagon(NOSE[-1][1], z0), hexagon(HEX, 16.6), hexagon(HEX, cut)]
    case = block((-5.3, -5.6, 17.0), (5.3, 7.3, 32.0), panel)
    tubes = [tube_z(sx * x, y, [(TUBE_Z[0], 0.0), (TUBE_Z[0], TUBE_R - 0.3), (TUBE_Z[0] + 0.3, TUBE_R), (TUBE_Z[1], TUBE_R), (TUBE_Z[1], 0.0)], hull, 18,
                    creases=(1, 2, 3)) for x, y in TUBE_AT for sx in (1.0, -1.0)]
    # The housings at the bow corners, each with a drum canted outboard and forward.
    housings, drums = [], []
    for y0, y1 in ((4.2, 8.8), (-7.5, -3.0)):
        for sx in (1.0, -1.0):
            housings.append(block((min(sx * 0.3, sx * 4.3), y0, 14.7), (max(sx * 0.3, sx * 4.3), y1, 18.0), panel))
            aim = unit(np.array([sx * 0.72, 0.0, -0.69]))
            centre = np.array([sx * 4.9, 0.5 * (y0 + y1), 14.9])
            drum = lathe([(-1.2, 0.0), (-1.2, 1.6), (1.5, 1.8), (2.2, 1.25), (2.2, 0.0)], 14, [dark, nozzle, nozzle, dark], creases=(1, 2, 3))
            drums.append(drum.transformed(basis_from_z(aim), centre))
    shoulder_boxes = [np.array([[min(sx * 4.6, sx * 8.9), y0, 26.9], [max(sx * 4.6, sx * 8.9), y1, 32.0]])
                      for sides in SHOULDERS for sx, (y0, y1) in zip((1.0, -1.0), sides, strict=True)]
    # Webs from each block towards the hexagon's waist.
    shoulder_boxes += [np.array([[min(sx * 4.6, sx * 6.6), y0, 26.9], [max(sx * 4.6, sx * 6.6), y1, 32.0]])
                       for y0, y1 in ((2.4, 4.2), (-2.3, -0.9)) for sx in (1.0, -1.0)]
    shoulders = [block(b[0], b[1], panel) for b in shoulder_boxes]
    stern = [hexagon((*STERN_HEX[:4], HEX[4]), cut), hexagon(STERN_HEX, cut + 1.0), hexagon(STERN_HEX, z1)]
    roof_box = block((-2.6, 7.4, 38.0), (2.6, 8.45, 43.6), panel)
    fan = faceted([hexagon(STERN_HEX, z1 - 0.05, 0.8, (0.0, 0.2)), hexagon(STERN_HEX, z1 + 0.25, 0.74, (0.0, 0.2))], frame, cap_end=dark)
    domes = [ellipsoid((sx * 1.3, 7.75, 40.9), (0.95, 1.15, 0.95), dark, segments=12, rings=6) for sx in (1.0, -1.0)]
    side_tanks, brackets, balls = [], [], []
    for sx in (1.0, -1.0):
        side_tanks.append(tube_z(sx * 7.75, -1.5, [(31.9, 0.0), (31.9, 0.95), (32.4, 1.12), (36.0, 1.12), (38.0, 0.4), (38.0, 0.0)], tank, 12, creases=(1, 4)))
        brackets.append(block((min(sx * 5.6, sx * 9.4), 0.9, 39.4), (max(sx * 5.6, sx * 9.4), 2.2, 42.4), dark))
        brackets.append(block((min(sx * 5.7, sx * 9.3), 3.3, 39.0), (max(sx * 5.7, sx * 9.3), 4.3, 42.9), dark))
        brackets.append(block((min(sx * 6.4, sx * 9.3), -0.6, 36.6), (max(sx * 6.4, sx * 9.3), 0.9, 38.0), dark))
        balls.append(ellipsoid((sx * 5.6, 5.9, 40.9), (1.05, 1.15, 1.8), tank, segments=12, rings=6))
    hexbox = lambda shape, a, b: box_of(np.array([[-shape[2], shape[4], a], [shape[2], shape[3], b]]), "core")  # noqa: E731
    waist = lambda shape, a, b: box_of(np.array([[-shape[0], shape[1] - 2.6, a], [shape[0], shape[1] + 2.6, b]]), "waist")  # noqa: E731
    return [
        piece("nose", "body", [nose, *ribs], 2_000.0, solid=loft_solid(2, nose_rings),
              collision=[box_of(np.array([[-2.9, -2.6, 12.4], [2.9, 4.0, z0]]), "nose"), box_of(np.array([[-1.2, -0.5, tip[2]], [1.2, 1.9, 12.4]]), "tip")],
              anchors={"eye": Anchor(EYE, (0.0, 0.0, -1.0))}),
        piece("hull_body", "body", [faceted(mid, hull, cap_start=inside, cap_end=inside), case, *tubes], 60_000.0, solid=loft_solid(2, mid),
              collision=[hexbox(HEX, z0, cut), waist(HEX, z0, cut), box_of(np.array([[-5.3, -6.65, TUBE_Z[0]], [5.3, 8.15, TUBE_Z[1]]]), "case")]),
        piece("housings", "body", [*housings, *drums], 6_000.0,
              collision=[box_of(np.array([[-5.6, 4.2, 13.6], [5.6, 8.8, 18.0]]), "up"), box_of(np.array([[-5.6, -7.5, 13.6], [5.6, -3.0, 18.0]]), "down")]),
        piece("shoulders", "body", shoulders, 8_000.0, LONE,  # the reference's two sides differ in height
              collision=[box_of(b, f"s{k}") for k, b in enumerate(shoulder_boxes)]),
        piece("hull_stern", "stern", [faceted(stern, hull, cap_start=hull, cap_end=panel), fan, roof_box, *domes], 40_000.0, solid=loft_solid(2, stern),
              collision=[hexbox(STERN_HEX, cut, z1), waist(STERN_HEX, cut, z1)], anchors={"top": Anchor((0.0, 8.9, 40.9), Y_AXIS)}),
        piece("stern_fittings", "stern", [*side_tanks, *brackets, *balls], 5_000.0,
              collision=[box_of(np.array([[sx * 5.6, -2.75, 31.9], [sx * 9.4, 4.3, 42.9]]), f"side{k}") for k, sx in enumerate((1.0, -1.0))]),
    ]


def _grab(y: float, material: Material) -> list[Mesh]:
    """A grab: two flat fingers bowed apart and nearly meeting at their tips, standing in the centre plane."""
    out = []
    for sign in (1.0, -1.0):
        t = np.linspace(0.0, 1.0, 9)
        z = 4.4 - 4.4 * t
        bow = y + sign * (0.3 + 0.95 * np.sin(math.pi * np.clip(t * 1.06, 0.0, 1.0)) ** 0.8)
        outline = [(-zz, yy - sign * 0.24) for zz, yy in zip(z, bow, strict=True)] + [(-zz, yy + sign * 0.24) for zz, yy in zip(z[::-1], bow[::-1], strict=True)]
        tiles = [(np.array([outline[k], outline[k + 1], outline[-k - 2], outline[-k - 1]]), material) for k in range(len(z) - 1)]
        finger = prism(tiles, [(np.array(outline), material)], 0.4)
        # the prism lies in its local x/y plane: local x runs forward (-z), local y up, its thickness across the hull
        out.append(finger.transformed(np.array([[0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [-1.0, 0.0, 0.0]])))
    return out


def arm_pieces(style: Style) -> list[Piece]:
    """The two grab arms on the centre line: a stout tube out of the body, a thin wrist and the grab."""
    panel, dark, hazard = style.material("hull_panel"), style.material("hull_dark"), style.material("hazard")
    out = []
    for name, y in zip(("arm_up", "arm_down"), ARM_Y, strict=True):
        tube = tube_z(0.0, y, [(4.2, 0.0), (4.2, 0.85), (5.0, 0.85), (5.0, 0.7), (6.4, 0.7), (6.4, 1.0), (10.0, 1.0), (10.0, 1.12), (13.6, 1.12), (13.6, 0.9),
                               (15.0, 0.9), (15.0, 0.0)], [dark, dark, dark, dark, dark, panel, panel, panel, panel, panel, panel], 14)
        out.append(piece(name, "body", [tube, *_grab(y, hazard)], 1_500.0, fine=0.5,
                         collision=[Collision("capsule", (0.0, y, 9.8), radius=1.1, height=10.4, name="arm"),
                                    box_of(np.array([[-0.25, y - 1.55, 0.0], [0.25, y + 1.55, 4.6]]), "grab")],
                         anchors={"tip": Anchor((0.0, y, 0.0), (0.0, 0.0, -1.0))}))
    return out


def gear_pieces(style: Style) -> list[Piece]:
    """The landing gear, standing a little to port of the centre line: a mount under the body, four splayed legs and their feet."""
    panel, dark = style.material("hull_panel"), style.material("hull_dark")
    mount = np.array([[GEAR_X - 2.9, -8.9, 19.7], [GEAR_X + 2.9, -7.2, 24.2]])
    meshes = [block(mount[0], mount[1], panel)]
    boxes = [box_of(mount, "mount")]
    for k, (x, z) in enumerate(FEET):
        for sx in (1.0, -1.0):
            at = GEAR_X + sx * x
            inward = 0.25 if z < 22.0 else -0.25  # each foot's drum sits a little nearer the mount than its pad
            root = (GEAR_X + sx * 1.2, -8.6, 21.0 if z < 22.0 else 22.9)
            meshes.append(bar(root, (at, -10.15, z + inward), 0.5, dark, 6))
            meshes.append(drum_y((at, -10.45, z + inward), 0.92, 1.7, panel, 0.15, 12))
            meshes.append(drum_y((at, -11.55, z), 0.35, 0.5, dark, 0.05, 8))
            meshes.append(drum_y((at, -11.82, z), 1.2, 0.36, dark, 0.08, 12))
            boxes.append(box_of(np.array([[at - 1.0, -12.0, z - 1.0], [at + 1.0, -9.6, z + 1.0]]), f"foot{2 * k + (sx < 0)}"))
    return [piece("gear", "body", meshes, 3_000.0, LONE, collision=boxes, fine=0.6)]


# --- the boom and its pods ---------------------------------------------------------------------------------------------------
def boom_y(x: float, at_15: float) -> float:
    """A chord's height at ``x``."""
    return at_15 + BOOM_FALL * (x - 15.0)


def boom_pieces(style: Style) -> list[Piece]:
    """The starboard boom: four chords, leaning uprights fore and aft, cross bars and a zigzag of diagonals over and under
    it, and the two tanks slung inside it."""
    dark, tank = style.material("hull_dark"), style.material("band_light")
    x0, x1 = BOOM_X
    zf, za = BOOM_Z
    bars = [bar((x0, boom_y(x0, y), z), (x1, boom_y(x1, y), z), CHORD_R, dark) for z in BOOM_Z for y in (BOOM_TOP, BOOM_BOTTOM)]
    for k, head in enumerate(BOOM_NODES):
        foot = head + BOOM_LEAN
        top, bottom = boom_y(head, BOOM_TOP), boom_y(foot, BOOM_BOTTOM)
        bars += [bar((foot, bottom, z), (head, top, z), BRACE_R, dark, 6) for z in BOOM_Z]
        bars += [bar((head, top, zf), (head, top, za), BRACE_R, dark, 6), bar((foot, bottom, zf), (foot, bottom, za), BRACE_R, dark, 6)]
        if k + 1 < len(BOOM_NODES):
            nxt = BOOM_NODES[k + 1]
            a, b = (za, zf) if k % 2 == 0 else (zf, za)
            bars.append(bar((head, top, a), (nxt, boom_y(nxt, BOOM_TOP), b), BRACE_R, dark, 6))
            bars.append(bar((foot, bottom, a), (nxt + BOOM_LEAN, boom_y(nxt + BOOM_LEAN, BOOM_BOTTOM), b), BRACE_R, dark, 6))
    tanks = []
    for z in (40.02, 42.02):
        a, b = np.array([14.2, 4.05, z]), np.array([25.25, 3.7, z])
        length = float(np.linalg.norm(b - a))
        profile = [(0.0, 0.0), (0.25, 0.62), (0.9, 0.98), (length - 0.9, 0.98), (length - 0.25, 0.62), (length, 0.0)]
        tanks.append(lathe(profile, 12, tank).transformed(basis_from_z(b - a, Y_AXIS), a))
    mid_y = 0.5 * (boom_y(15.0, BOOM_TOP) + boom_y(15.0, BOOM_BOTTOM))
    return [piece("boom_r", "boom_r", [*bars, *tanks], 9_000.0, RIGHT, fine=0.4,
                  collision=[box_of(np.array([[5.7, mid_y - 2.7, zf - CHORD_R], [x1, mid_y + 2.7, za + CHORD_R]]), "truss")],
                  anchors={"joint": Anchor((5.9, mid_y, 0.5 * (zf + za)))})]


def pod_pieces(style: Style) -> list[Piece]:
    """The starboard thruster pod: a drum between two collars with a bell at each end (the after one drives, the forward one
    brakes) and three small thrusters round its middle."""
    hull, panel, dark, nozzle, throat, inside = (style.material(r) for r in ("hull", "hull_panel", "hull_dark", "nozzle", "nozzle_throat", "interior"))
    x, y = POD_AT
    z0, z1 = POD_Z
    lip = POD_R + 0.05
    profile = [(z0 + 1.3, 0.0), (z0 + 1.3, 1.4), (z0, 2.0), (z0 + 0.8, 2.41), (z0 + 1.8, 2.6), (z0 + 2.8, 2.7), (z0 + 2.8, lip), (z0 + 4.2, lip), (z0 + 4.2, POD_R),
               (z1 - 4.3, POD_R), (z1 - 4.3, lip), (z1 - 3.2, lip), (z1 - 3.2, 2.95), (z1 - 1.5, 2.54), (z1, 2.05), (z1 - 1.4, 1.4), (z1 - 1.4, 0.0)]
    paints = [inside, nozzle, nozzle, nozzle, nozzle, dark, dark, dark, hull, dark, dark, dark, nozzle, nozzle, nozzle, throat]  # only the after bell is lit
    body = tube_z(x, y, profile, paints, 24)
    jets = []
    for aim in ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, -1.0, 0.0)):
        jet = lathe([(POD_R - 0.3, 0.0), (POD_R - 0.3, 0.95), (POD_R + 0.8, 0.95), (POD_R + 0.8, 1.2), (JET_REACH - 0.2, 1.2), (JET_REACH, 0.9), (JET_REACH, 0.0)],
                    12, [dark, panel, dark, nozzle, nozzle, dark], creases=(1, 2, 3, 4, 5))
        jets.append(jet.transformed(basis_from_z(aim), (x, y, 41.15)))
    return [piece("pod_r", "boom_r", [body, *jets], 12_000.0, RIGHT, fine=0.7,
                  collision=[Collision("capsule", (x, y, 0.5 * (z0 + z1)), radius=POD_R, height=z1 - z0, name="pod"),
                             box_of(np.array([[x - 1.2, y - JET_REACH, 39.95], [x + JET_REACH, y + JET_REACH, 42.35]]), "jets")],
                  anchors={"main": Anchor((x, y, z1 - 1.4), Z_AXIS), "retro": Anchor((x, y, z0 + 1.3), (0.0, 0.0, -1.0)), "centre": Anchor((x, y, 41.0)),
                           "side": Anchor((x + JET_REACH, y, 41.15), X_AXIS), "top": Anchor((x, y + JET_REACH, 41.15), Y_AXIS)})]


# --- the claws ---------------------------------------------------------------------------------------------------------------
def claw_frame(axis: Sequence[float]) -> np.ndarray:
    """A claw's own axes as columns: along its axis, then across it level, then across it upwards."""
    u = unit(np.asarray(axis, dtype=float))
    up = unit(np.array(Y_AXIS) - u[1] * u)
    return np.column_stack([u, np.cross(u, up), up])


def claw_piece(style: Style, name: str, group: str, hub: Sequence[float], axis: Sequence[float], reach_back: float) -> Piece:
    """One claw where it stands: the arm from its joint, the hub, three sickle blades and the spike down its axis."""
    blade_paint, dark, panel = style.material("hazard"), style.material("hull_dark"), style.material("hull_panel")
    frame = claw_frame(axis)
    hub = np.asarray(hub, dtype=float)
    outer = [np.array(o) for o, _ in BLADE]
    inner = [np.array(i) for _, i in BLADE]
    tiles = [(np.array([outer[k], outer[k + 1], inner[k + 1], inner[k]]), blade_paint) for k in range(len(BLADE) - 1)]
    flat = prism(tiles, [(np.array(outer + inner[::-1]), blade_paint)], BLADE_THICK)
    meshes, boxes = [], []
    for k, roll in enumerate(BLADE_ROLL_DEG):
        a = math.radians(roll)
        out = math.cos(a) * frame[:, 1] + math.sin(a) * frame[:, 2]
        turn = np.column_stack([frame[:, 0], out, np.cross(frame[:, 0], out)])  # the blade's plane: along the axis and out from it
        meshes.append(flat.transformed(turn, hub))
        boxes.append(Collision("box", hub + turn @ np.array([8.3, 2.4, 0.0]), basis=turn, size=(16.6, 4.3, 0.5), name=f"blade{k}"))
    along = lambda d: hub + d * frame[:, 0]  # noqa: E731
    meshes.append(bar(along(-reach_back), along(1.4), 0.8, panel, 12))
    meshes.append(bar(along(-0.2), along(1.5), 1.05, dark, 12))
    meshes.append(ellipsoid(along(1.6), (1.1, 1.1, 1.1), panel, segments=14, rings=8))
    meshes.append(ellipsoid(along(-reach_back), (1.3, 1.3, 1.3), dark, segments=12, rings=6))
    boxes.append(Collision("capsule", along(0.5 * (2.6 - reach_back)), basis=basis_from_z(frame[:, 0]), radius=1.3, height=reach_back + 3.4, name="arm"))
    return piece(name, group, meshes, 2_500.0, LONE, collision=boxes, fine=0.5,
                 anchors={"joint": Anchor(along(-reach_back)), "tip": Anchor(along(16.6), frame[:, 0])})


def assemble(style: Style) -> list[Piece]:
    """Every piece of the tender in the authored frame (centre pieces, the starboard boom and pod, and the four claws)."""
    claws = [claw_piece(style, *spec) for spec in CLAWS]
    return [*body_pieces(style), *arm_pieces(style), *gear_pieces(style), *boom_pieces(style), *pod_pieces(style), *claws]

