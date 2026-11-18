"""``cargo_pod_craft``: the Earth Alliance cargo pod, a 6 m cargo-handling craft (M7-T33; docs/design-references.md "Cargo pod").

Built in code from the written description of the maintainer's reference model (``references/EA_cargo_pod.stl``, gitignored):
a faceted blue cab, a wedge forward of a taller cabin, with a black window across its nose and two small humps on its roof;
beside it two arms, each a block on the cab's flank, a pair of stacked barrels telescoping forward, a wrist with a pivot and a
tapered forearm ending in a hand of two jaws that close top to bottom. The game calls it a cargo pod; the code name keeps it apart
from the freighters' own cargo pods (``FreighterCargo``, ``FerryPod``).

Frame (authored Godot frame, metres, before re-centring): -Z is forward, the jaws' tips at z = 0, +Y up, +X starboard, x and y
centred on the reference model's box, as ``tools/refview`` draws it (``--right=+y --up=+z --aft=+x``). The written mesh is
centred on its box, as the maintenance bot's is (``centroid_offset``).

Outputs: the textured mesh (``cargo_pod_craft.glb``, its full and low texture sets), the OBJ, ``hardpoints.json`` (size, mass,
the grips a cargo block is held by, the thrusters, the running lights, the collision primitives) and the manifest with its
compound ``collision`` section (the arms at rest). Godot's importer builds the levels of detail.

The arms move (for T34): the glb is skinned, each moving part bound whole to a joint (the reach, the wrist, each jaw), so the game
poses them without another draw call; the manifest's ``rig`` names the joints and their ranges, and the rest pose is the
reference model's.
"""

from __future__ import annotations

import functools
import json
import math
from collections.abc import Sequence
from pathlib import Path
from typing import Any

import numpy as np

from ..core import civilian as cv
from ..core import collision as col
from ..core.context import AssetOutputs, BuildContext
from ..core.glb import GlbJoint
from ..core.geometry import Material, Mesh, basis_from_z, box, lathe, rotation_y, tapered_box
from ..core.manifest import build_manifest, write_manifest
from ..core.obj import write_obj
from ..core.seams import Cut, Feature, Hatch, Plates, SeamLayout, Spoke
from ..core.textured_mesh import TexturedPart, phase_steps, write_textured_mesh
from ..core.textures import Marking
from ..parts.propulsion import pilot_tags
from ..styles import Style
from ..styles.cargo_pod_craft import CARGO_POD_CRAFT

ASSET_ID = "cargo_pod_craft"
GENERATOR_VERSION = 1
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"
ATLAS_PX = 1024  # about 50 m² of surface: under a centimetre a texel
LENGTH_M = 6.0
MASS_KG = 4200.0  # a loaded work craft of this size; the game's mover takes its own figures
UP, DOWN, AFT, FORE = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0), (0.0, 0.0, -1.0)
X, Y, Z = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)
INF = float("inf")

# The cab's hexagonal sections: z, then top (y, half width), chine (y, half width), keel (y, half width). The wedge rises and
# widens from the nose to the cabin, which runs level and closes in a ridge at the stern on the chine line.
FORE_SECTIONS = (
    (1.02, 0.12, 0.27, -0.21, 0.43, -0.50, 0.31),
    (2.00, 0.33, 0.48, -0.18, 0.69, -0.69, 0.50),
    (3.00, 0.60, 0.66, -0.15, 0.93, -0.86, 0.68),
    (3.60, 0.80, 0.80, -0.15, 1.06, -0.97, 0.80),
)
AFT_SECTIONS = (
    (3.60, 0.80, 0.80, -0.15, 1.06, -0.97, 0.80),
    (4.10, 0.95, 0.83, -0.20, 1.13, -1.04, 0.85),
    (5.62, 0.95, 0.83, -0.20, 1.13, -1.04, 0.85),
)
# The stern: the cabin's slopes close outboard of x = +-0.6 in a ridge on the chine line at z 6.0; between them the slopes stop at
# the flat engine face.
STERN_Z = 6.0
STERN_RIDGE = (-0.17, 1.00, -0.22, 1.13, -0.27, 1.00)  # top (y, half width), chine, keel at the ridge
ENGINE_HALF_W = 0.6
ENGINE_FACE_Z = 5.75
ENGINE_FACE_Y = (0.55, -0.77)  # where the slopes meet the engine face, top and bottom
NOSE_FACE_Z = 0.93  # the bezel's face at its foot
NOSE_FACE_Y = (-0.33, 0.13)
NOSE_LEAN = 0.27  # metres aft per metre up
NOSE_HALF_W = 0.42
HUMPS = ((0.40, 4.06),)  # x (mirrored), z of the two roof humps

# The right arm (the left mirrors it): the axis of each pair of barrels and the parts along it, nose to stern.
ARM_X = 1.32
BARREL_Y = (-0.19, -0.61)  # upper, lower
OUTER_BARREL = (2.92, 4.62, 0.19, 0.215)  # z0, z1, radius across, radius up (the barrels are a little oval)
INNER_BARREL = (1.86, 2.94, 0.14, 0.18)
HAND_Y = -0.40  # the jaws' gap and the wrist's axis
JAWS_Y = (-0.17, -0.63)
JAW_LENGTH = 0.60
# The moving parts (M7-T33, for T34): the inner barrels slide out of the outer ones by up to EXTEND_M (they reach that far back
# inside them at rest), the hand turns on the wrist's pivot, and each jaw turns on its root at the crossbar to close on the other.
EXTEND_M = 1.0
WRIST_PIVOT = (HAND_Y + 0.02, 1.69)  # y, z of the pivot drum's axis
WRIST_LIMIT_DEG = 45.0
JAW_ROOT_Z = 0.60
JAW_CLOSE_DEG = 15.5  # the turn that brings the jaws' tips together
BANDS = ((3.30, 0.10, "stripe"), (3.40, 0.10, "hazard"), (3.50, 0.10, "stripe"))  # z, width, role on the outer barrels
CHEQUER = (3.62, 0.08, 0.055)  # z, band width, square size
BLOCK_SECTION = ((1.03, 0.12), (1.55, 0.12), (1.64, 0.02), (1.64, -0.84), (1.56, -0.94), (1.03, -0.94))
BLOCK_Z = (4.62, 5.37, 5.47)

NAV_CLEARANCE_M = 0.03


# --- geometry helpers ----------------------------------------------------------------------------------------------------
def hex_ring(section: Sequence[float]) -> np.ndarray:
    """A cab section's six corners, counter-clockwise seen from astern: chine right, top right, top left, chine left, keel
    left, keel right."""
    z, yt, wt, yc, wc, yb, wb = section
    return np.array([[wc, yc, z], [wt, yt, z], [-wt, yt, z], [-wc, yc, z], [-wb, yb, z], [wb, yb, z]])


def faceted_loft(rings: Sequence[np.ndarray], materials: Sequence[Material], cap_start: bool = True, cap_end: bool = True,
                 cap_material: Material | None = None) -> Mesh:
    """A solid skinned through closed rings of equal size (counter-clockwise seen from astern), every face flat with its own
    corners so its edges stay hard; ``materials`` holds one per ring edge (edge k runs from corner k to k + 1)."""
    table: list[Material] = []
    verts: list[np.ndarray] = []
    faces: list[list[int]] = []
    mats: list[int] = []

    def index(m: Material) -> int:
        if m not in table:
            table.append(m)
        return table.index(m)

    def add(poly: Sequence[np.ndarray], m: Material) -> None:
        base = sum(len(v) for v in verts)
        verts.append(np.asarray(poly, dtype=float))
        for k in range(1, len(poly) - 1):
            faces.append([base, base + k, base + k + 1])
            mats.append(index(m))

    n = len(rings[0])
    for a, b in zip(rings[:-1], rings[1:], strict=True):
        for k in range(n):
            j = (k + 1) % n
            add([a[k], a[j], b[j], b[k]], materials[k])
    cap = cap_material or materials[0]
    if cap_start:
        add(list(rings[0][::-1]), cap)
    if cap_end:
        add(list(rings[-1]), cap)
    mesh = Mesh(np.concatenate(verts), np.array(faces), np.array(mats), tuple(table))
    area = mesh.face_areas() > 1e-9
    return mesh.face_subset(area)


def upright_box(size_bottom: Sequence[float], size_top: Sequence[float], height: float, base: Sequence[float], material: Material) -> Mesh:
    """A box standing on ``base`` (its bottom face's centre), ``size_*`` its footprint (x, z) at the bottom and the top."""
    lift = basis_from_z(UP, X)  # local z up, local x along x
    mesh = tapered_box(height, (size_bottom[0], size_bottom[1]), (size_top[0], size_top[1]), material)
    return mesh.transformed(lift, np.asarray(base, dtype=float) + np.array([0.0, 0.5 * height, 0.0]))


def oval_barrel(z0: float, z1: float, rx: float, ry: float, at: Sequence[float], material: Material, segments: int = 20) -> Mesh:
    """A closed barrel along z from ``z0`` to ``z1`` with an oval section, its axis through ``at`` (x, y)."""
    r = max(rx, ry)
    tube = lathe([(0.0, 0.0), (0.0, r), (z1 - z0, r), (z1 - z0, 0.0)], segments, material, creases=(1, 2))
    return tube.transformed(np.diag([rx / r, ry / r, 1.0]), (at[0], at[1], z0))


def along_x_disc(centre: Sequence[float], radius: float, half_width: float, material: Material, segments: int = 18) -> Mesh:
    """A short cylinder along x: the wrist's pivot."""
    cyl = lathe([(-half_width, 0.0), (-half_width, radius), (half_width, radius), (half_width, 0.0)], segments, material, creases=(1, 2))
    return cyl.transformed(rotation_y(0.5 * math.pi), centre)


def cone(at: Sequence[float], direction: Sequence[float], radius: float, length: float, outer: Material, throat: Material) -> Mesh:
    """A small thruster bell opening along ``direction`` from ``at``, its throat glowing."""
    bell = lathe([(0.0, 0.5 * radius), (0.7 * length, radius), (length, 1.1 * radius), (length, 0.8 * radius), (0.9 * length, 0.0)], 10,
                 [outer, outer, throat, throat], creases=(1, 2))
    return bell.transformed(basis_from_z(direction), at)


def nose_meshes(frame: Material, glass: Material) -> list[Mesh]:
    """The bezel round the nose window, its face leaning back about 15 degrees, with the window and a sensor slot under it."""
    bottom, top = NOSE_FACE_Y
    lean = NOSE_LEAN

    def face_z(y: float) -> float:
        return NOSE_FACE_Z + (y - bottom) * lean

    w = NOSE_HALF_W
    front = np.array([[w, bottom, face_z(bottom)], [w, top, face_z(top)], [-w, top, face_z(top)], [-w, bottom, face_z(bottom)]])
    back = np.array([[w + 0.02, bottom - 0.03, 1.12], [w + 0.02, top + 0.02, 1.12], [-w - 0.02, top + 0.02, 1.12], [-w - 0.02, bottom - 0.03, 1.12]])
    bezel = faceted_loft([front, back], [frame] * 4, cap_end=False)
    tilt = np.array([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, lean, 1.0]])  # shears z by y, so a flat pane follows the face
    window = box((0.70, 0.26, 0.01), glass, (0.0, 0.0, 0.0)).transformed(tilt, (0.0, -0.06, face_z(-0.06) - 0.006))
    sensor = box((0.24, 0.05, 0.01), glass, (0.0, 0.0, 0.0)).transformed(tilt, (0.0, -0.27, face_z(-0.27) - 0.006))
    return [bezel, window, sensor]


def stern_meshes(style: Style) -> list[Mesh]:
    """The stern: two ridged wedges outboard and the engine face between them, under the cabin's last section."""
    blue, pale, dark = style.material("hull"), style.material("hull_panel"), style.material("canopy_frame")
    z, yt, wt, yc, wc, yb, wb = AFT_SECTIONS[-1]
    ryt, rwt, ryc, rwc, ryb, rwb = STERN_RIDGE
    w = ENGINE_HALF_W
    # The right wedge, counter-clockwise from astern: chine, top corner, top at the engine's edge, keel at its edge, keel corner.
    wedge = [np.array([[wc, yc, z], [wt, yt, z], [w, yt, z], [w, yb, z], [wb, yb, z]]),
             np.array([[rwc, ryc, STERN_Z], [rwt, ryt, STERN_Z], [w, ryt, STERN_Z], [w, ryb, STERN_Z], [rwb, ryb, STERN_Z]])]
    right = faceted_loft(wedge, [blue, pale, blue, blue, blue], cap_start=False)
    top, bottom = ENGINE_FACE_Y
    face = [np.array([[w, yt, z], [-w, yt, z], [-w, yb, z], [w, yb, z]]),
            np.array([[w, top, ENGINE_FACE_Z], [-w, top, ENGINE_FACE_Z], [-w, bottom, ENGINE_FACE_Z], [w, bottom, ENGINE_FACE_Z]])]
    centre = faceted_loft(face, [pale, blue, blue, blue], cap_start=False, cap_material=dark)
    return [right, right.transformed(np.diag([-1.0, 1.0, 1.0])), centre]


# --- the parts -------------------------------------------------------------------------------------------------------------
def cab_meshes(style: Style) -> dict[str, Mesh]:
    """The cab: the wedge, the cabin, the nose bezel with its window, the roof humps and the engine face at the stern."""
    blue, pale, dark = style.material("hull"), style.material("hull_panel"), style.material("canopy_frame")
    glass, nozzle, throat = style.material("canopy_glass"), style.material("nozzle"), style.material("nozzle_throat")
    # Edge order (``hex_ring``): upper right, top, upper left, lower left, keel, lower right.
    edges = [blue, pale, blue, blue, blue, blue]
    fore = faceted_loft([hex_ring(s) for s in FORE_SECTIONS], edges, cap_start=True, cap_end=False, cap_material=blue)
    aft = faceted_loft([hex_ring(s) for s in AFT_SECTIONS], edges, cap_start=False, cap_end=False)
    stern = stern_meshes(style)
    nose = nose_meshes(dark, glass)
    humps = [upright_box((0.42, 0.38), (0.30, 0.24), 0.10, (sx * x, 0.945, z), blue) for x, z in HUMPS for sx in (1.0, -1.0)]
    engine = [box((0.36, 0.11, 0.02), throat, (sx * 0.25, y, ENGINE_FACE_Z + 0.025)) for sx in (1.0, -1.0) for y in (0.06, -0.34)]
    engine += [box((0.44, 0.17, 0.03), nozzle, (sx * 0.25, y, ENGINE_FACE_Z + 0.015)) for sx in (1.0, -1.0) for y in (0.06, -0.34)]
    return {"cab_fore": Mesh.concatenate([fore, *nose]), "cab_aft": Mesh.concatenate([aft, *stern, *humps]), "engine": Mesh.concatenate(engine)}


def arm_meshes(style: Style) -> dict[str, Mesh]:
    """The right arm: its root block on the cab's flank, the barrels, the wrist and the hand."""
    gun, clamp = style.material("hull_dark"), style.material("clamp")
    blue = style.material("hull")
    ring = [np.array([[x, y, z] for x, y in BLOCK_SECTION[::-1]]) for z in BLOCK_Z]  # reversed: counter-clockwise from astern
    ring[-1][:, 0] = 1.03 + (ring[-1][:, 0] - 1.03) * 0.12
    root = faceted_loft(ring, [blue] * len(BLOCK_SECTION))
    outer = [oval_barrel(*OUTER_BARREL[:2], *OUTER_BARREL[2:], (ARM_X, y), gun) for y in BARREL_Y]
    reach = [oval_barrel(INNER_BARREL[0], INNER_BARREL[1] + EXTEND_M, *INNER_BARREL[2:], (ARM_X, y), clamp) for y in BARREL_Y]
    reach.append(box((0.30, 0.98, 0.06), clamp, (ARM_X, -0.39, 1.85)))
    wrist = [tapered_box(0.25, (0.26, 0.46), (0.26, 0.82), clamp, center=(ARM_X, -0.39, 1.695)),
             along_x_disc((ARM_X, *WRIST_PIVOT), 0.12, 0.23, gun),
             tapered_box(0.80, (0.15, 0.22), (0.27, 0.42), clamp, center=(ARM_X, HAND_Y + 0.01, 1.17)),
             box((0.29, 0.90, 0.17), clamp, (ARM_X, HAND_Y, 0.685))]
    jaws = []
    for y in JAWS_Y:
        jaw = [tapered_box(JAW_LENGTH, (0.13, 0.14), (0.27, 0.27), clamp, center=(ARM_X, y, 0.5 * JAW_LENGTH))]
        face = HAND_Y + (0.13 if y > HAND_Y else -0.13)  # the jaw's inner face, towards the gap
        jaw += [box((0.035, 0.035, 0.035), gun, (ARM_X, face + (-0.017 if y > HAND_Y else 0.017), z)) for z in (0.08, 0.17, 0.26, 0.35, 0.44)]
        jaws.append(Mesh.concatenate(jaw))
    return {"arm_root_r": root, "arm_r": Mesh.concatenate(outer), "reach_r": Mesh.concatenate(reach), "wrist_r": Mesh.concatenate(wrist),
            "jaw_up_r": jaws[0], "jaw_lo_r": jaws[1]}


def rig_joints() -> list[GlbJoint]:
    """The skin's joints in the authored frame: the craft's root, then per arm the reach (the sliding barrels), the wrist on its
    pivot and the two jaws on their roots."""
    out = [GlbJoint("root", -1, (0.0, 0.0, 0.0))]
    for side, tag in ((1.0, "r"), (-1.0, "l")):
        base = len(out)
        out += [GlbJoint(f"reach_{tag}", 0, (side * ARM_X, HAND_Y, INNER_BARREL[1])),
                GlbJoint(f"wrist_{tag}", base, (side * ARM_X, *WRIST_PIVOT)),
                GlbJoint(f"jaw_up_{tag}", base + 1, (side * ARM_X, JAWS_Y[0], JAW_ROOT_Z)),
                GlbJoint(f"jaw_lo_{tag}", base + 1, (side * ARM_X, JAWS_Y[1], JAW_ROOT_Z))]
    return out


def joint_index(name: str) -> int:
    return [j.name for j in rig_joints()].index(name)


def thruster_meshes(style: Style) -> tuple[Mesh, list[tuple[str, np.ndarray, np.ndarray]]]:
    """The small white thrusters (right side; the caller mirrors the ``r_`` ones) and where each points: four at the nose
    corners pointing ahead, one on each root block's outer face and two on the roof and the keel."""
    outer, throat = style.material("rcs"), style.material("nozzle_throat")
    ports = [
        ("r_nose_up", np.array([0.42, 0.12, 1.20]), np.array([0.0, 0.0, -1.0])),
        ("r_nose_down", np.array([0.36, -0.46, 1.20]), np.array([0.0, 0.0, -1.0])),
        ("r_side", np.array([1.64, -0.41, 5.0]), np.array([1.0, 0.0, 0.0])),
        ("r_roof", np.array([0.55, 0.95, 5.3]), np.array([0.0, 1.0, 0.0])),
        ("r_keel", np.array([0.55, -1.04, 5.3]), np.array([0.0, -1.0, 0.0])),
    ]
    meshes = [cone(p - 0.06 * d, d, 0.035, 0.07, outer, throat) for _, p, d in ports]
    return Mesh.concatenate(meshes), ports


# --- surfaces ------------------------------------------------------------------------------------------------------------------
def cab_layout() -> SeamLayout:
    """The cab: the joint between wedge and cabin, frames across the roof and flanks, access hatches, then plating."""
    roof = {"facing": UP, "min_dot": 0.8}
    flank = {"lo": (0.3, -INF, -INF)}
    major: list[Feature] = [Cut(axis=2, at=3.6, level=1, width=1.4), Cut(axis=2, at=5.62, level=1, width=1.2),
                            Cut(axis=2, at=1.6, level=1), Cut(axis=0, at=0.0, level=1, lo=(-INF, 0.5, 3.6), **{"facing": UP})]
    full: list[Feature] = [
        *[Cut(axis=2, at=z, level=2) for z in (2.3, 3.0, 4.35, 5.0)],
        Cut(axis=1, at=0.35, level=2, lo=(-INF, -INF, 3.7), hi=(INF, INF, 5.6)),
        Cut(axis=1, at=-0.62, level=2, lo=(-INF, -INF, 2.0), hi=(INF, INF, 5.6)),
        Hatch(centre=(0.0, 0.95, 4.85), right=X, up=Z, size=(0.9, 0.6), corner_m=0.04, sunk=0.6, tone=0.9, level=2, **roof),
        Hatch(centre=(0.0, 0.5, 2.7), right=X, up=Z, size=(0.5, 0.5), corner_m=0.04, sunk=0.6, tone=0.9, level=2, **roof),
        Hatch(centre=(1.0, 0.2, 4.4), right=Z, up=Y, size=(0.4, 0.3), corner_m=0.03, sunk=0.8, tone=0.85, level=2, slats=4,
              facing=(1.0, 0.0, 0.0), min_dot=0.5),
        Hatch(centre=(0.0, -1.04, 4.6), right=X, up=Z, size=(1.0, 0.8), corner_m=0.05, sunk=0.6, tone=0.9, level=2, facing=DOWN, min_dot=0.8),
        Hatch(centre=(0.7, -0.5, 2.6), right=Z, up=Y, size=(0.5, 0.22), corner_m=0.03, sunk=0.8, tone=0.85, level=2,
              facing=(1.0, -0.4, 0.0), min_dot=0.5, **flank),
    ]
    plating: list[Feature] = [
        Plates(level=3, wrap="sides", long_axis=2, cell=(0.75, 0.45), splits=2, min_m=0.16, keep=0.3, tone=0.05, sheen=0.08,
               grime=0.08, grime_m=0.08, depth=0.5, dark=0.45, width=0.8, seed=331),
        Plates(level=3, wrap="sides", long_axis=2, cell=(0.4, 0.3), splits=1, min_m=0.12, scatter=0.1, inset_m=0.04, tone=0.05,
               dark=0.7, depth=0.7, seed=337),
    ]
    return SeamLayout.of(major + full + plating)


def arm_layout() -> SeamLayout:
    """The right arm: the barrels' joints and courses, seams along them, the root block's frames and hatches."""
    major: list[Feature] = [Cut(axis=2, at=OUTER_BARREL[0] + 0.02, level=1, width=1.4), Cut(axis=2, at=4.0, level=1),
                            Cut(axis=2, at=5.0, level=1, lo=(1.0, -INF, 4.6))]
    full: list[Feature] = [Cut(axis=2, at=z, level=2, hi=(INF, INF, 4.6)) for z in (2.4, 3.15, 3.85, 4.3)]
    full += [Spoke(axis=2, centre=(ARM_X, y, 0.0), angle_deg=a, span=(1.9, 4.6), level=2) for y in BARREL_Y for a in (0.0, 180.0)]
    full += [Hatch(centre=(1.64, -0.4, 5.0), right=Z, up=Y, size=(0.4, 0.5), corner_m=0.03, sunk=0.6, tone=0.88, level=2,
                   facing=(1.0, 0.0, 0.0), min_dot=0.8),
             Hatch(centre=(1.3, 0.12, 5.0), right=X, up=Z, size=(0.32, 0.4), corner_m=0.03, sunk=0.6, tone=0.88, level=2, facing=UP, min_dot=0.8)]
    plating: list[Feature] = [Plates(level=3, wrap="sides", long_axis=2, cell=(0.45, 0.3), splits=2, min_m=0.1, keep=0.3, tone=0.05,
                                     sheen=0.08, grime=0.08, grime_m=0.06, depth=0.5, dark=0.45, width=0.8, seed=347)]
    return SeamLayout.of(major + full + plating)


def _chequer(points: np.ndarray, normals: np.ndarray, colour_white: bool, side: float) -> np.ndarray:
    """Where the chequer band round the outer barrels takes one of its two colours (the arm's ``side``, 1 starboard)."""
    z0, width, square = CHEQUER
    p = np.asarray(points, dtype=float)
    on = np.abs(p[:, 2] - z0) < 0.5 * width
    out = np.zeros(len(p))
    for y in BARREL_Y:
        dx, dy = side * p[:, 0] - ARM_X, p[:, 1] - y
        near = on & (np.hypot(dx, dy) < 0.3)
        around = np.floor((np.arctan2(dy, dx) + math.pi) * OUTER_BARREL[2] / square)
        along = np.floor((p[:, 2] - z0 + 0.5 * width) / (0.5 * width))
        white = (around + along) % 2 == 0
        out = np.maximum(out, near & (white == colour_white))
    return out


def arm_markings(name: str, side: float, style: Style) -> tuple[Marking, ...]:
    """The bands and the chequer round both outer barrels of one arm."""
    marks = [Marking.band(name, (side * ARM_X, 0.0, 0.0), Z, z, w, style.material(role).albedo) for z, w, role in BANDS]
    for white, role in ((True, "hazard_light"), (False, "hazard_dark")):
        marks.append(Marking.paint(name, style.material(role).albedo, functools.partial(_chequer, colour_white=white, side=side)))
    return tuple(marks)


def build_parts(style: Style = CARGO_POD_CRAFT) -> list[TexturedPart]:
    """Every part in the authored frame, before the centring; the left arm mirrors the right."""
    cab = cab_meshes(style)
    arm = arm_meshes(style)
    thrusters, _ = thruster_meshes(style)
    flip = np.diag([-1.0, 1.0, 1.0])
    cab_seams, arm_seams = cab_layout(), arm_layout()

    def part(name: str, mesh: Mesh, seams: SeamLayout = SeamLayout(), markings: tuple[Marking, ...] = (), phase: str = "",
             joint: str = "root") -> TexturedPart:
        return TexturedPart(mesh, phase_steps(phase or name, False), markings, name, seams=seams, joint=joint_index(joint))

    out = [
        part("cab_fore", cab["cab_fore"], cab_seams),
        part("cab_aft", cab["cab_aft"], cab_seams),
        part("engine", cab["engine"]),
        part("thrusters", Mesh.concatenate([thrusters, thrusters.transformed(flip)])),
    ]
    for tag, turn in (("r", np.eye(3)), ("l", flip)):
        seams = arm_seams.transformed(turn)
        out += [part(f"arm_root_{tag}", arm["arm_root_r"].transformed(turn), seams, phase="arm_root"),
                part(f"arm_{tag}", arm["arm_r"].transformed(turn), seams, arm_markings(f"arm_{tag}", float(turn[0, 0]), style), phase="arm")]
        out += [part(f"{name}_{tag}", arm[f"{name}_r"].transformed(turn), seams, phase=name, joint=f"{name}_{tag}")
                for name in ("reach", "wrist", "jaw_up", "jaw_lo")]
    return out


def centre(parts: list[TexturedPart]) -> tuple[list[TexturedPart], np.ndarray]:
    """Move the parts so their box is centred on the origin; returns them and the subtracted offset (``centroid_offset``)."""
    verts = np.concatenate([p.mesh.vertices for p in parts])
    lo, hi = verts.min(axis=0), verts.max(axis=0)
    offset = np.array([0.0, 0.5 * (lo[1] + hi[1]), 0.5 * (lo[2] + hi[2])])
    return [TexturedPart(p.mesh.translated(-offset), p.phase, tuple(cv.moved_marking(m, -offset) for m in p.markings), p.name,
                         seams=p.seams.transformed(np.eye(3), -offset), joint=p.joint) for p in parts], offset


def rig_section(offset: np.ndarray) -> dict[str, Any]:
    """The manifest's ``rig``: each joint (body frame) and the arms' ranges, for the game's pose of the arms (``CargoPodPose``).
    The rest pose is the reference model's: barrels in, wrist straight, jaws open."""
    return {
        "bones": [{"name": j.name, "parent": j.parent, "position": cv.r(np.array(j.position) - offset)} for j in rig_joints()],
        "extend_m": EXTEND_M,
        "wrist_limit_deg": WRIST_LIMIT_DEG,
        "jaw_close_deg": JAW_CLOSE_DEG,
        "rest": {"extend": 0.0, "wrist_deg": 0.0, "jaw_open": 1.0},
    }


# --- hardpoints and collision ------------------------------------------------------------------------------------------------
def collision_shapes(offset: np.ndarray) -> list[col.Shape]:
    """The craft's convex pieces in the body frame: the cab's hull, each root block, each pair of barrels and each hand."""
    ridge = (STERN_Z, *STERN_RIDGE)
    _, ports = thruster_meshes(CARGO_POD_CRAFT)
    nose = [p for _, p, _ in ports if p[2] < 2.0]
    bezel = [(sx * NOSE_HALF_W, y, NOSE_FACE_Z + (y - NOSE_FACE_Y[0]) * NOSE_LEAN) for sx in (1.0, -1.0) for y in NOSE_FACE_Y]
    humps = [(sx * (x + dx * 0.21), 1.045, z + dz * 0.19) for x, z in HUMPS for sx in (1.0, -1.0) for dx in (-1.0, 1.0) for dz in (-1.0, 1.0)]
    extra = np.array([*humps, *bezel, *nose, *(p * np.array([-1.0, 1.0, 1.0]) for p in nose)])
    cab = np.concatenate([hex_ring(s) for s in FORE_SECTIONS + AFT_SECTIONS + (ridge,)] + [extra]) - offset
    shapes = [col.hull("cab", cab)]
    for side, tag in ((1.0, "r"), (-1.0, "l")):
        def at(x: float, y: float, z: float) -> np.ndarray:
            return np.array([side * x, y, z]) - offset
        shapes.append(col.box(f"root_{tag}", at(1.335, -0.41, 5.045), (0.61, 1.06, 0.85)))
        for k, y in enumerate(BARREL_Y):
            shapes.append(col.capsule(f"barrel_{tag}{k}", at(ARM_X, y, 0.5 * (INNER_BARREL[0] + OUTER_BARREL[1])), 0.2,
                                      OUTER_BARREL[1] - INNER_BARREL[0]))
        shapes.append(col.box(f"hand_{tag}", at(ARM_X, HAND_Y, 0.385), (0.3, 0.92, 0.77)))
        shapes.append(col.box(f"forearm_{tag}", at(ARM_X, HAND_Y, 1.17), (0.27, 0.42, 0.8)))
        shapes.append(col.box(f"wrist_{tag}", at(ARM_X, -0.39, 1.735), (0.3, 0.98, 0.29)))
        across = np.array([[0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [-1.0, 0.0, 0.0]])  # the pivot's capsule lies along x
        shapes.append(col.capsule(f"pivot_{tag}", at(ARM_X, HAND_Y + 0.02, 1.69), 0.12, 0.46, across))
    return shapes


def hardpoints(parts: list[TexturedPart], offset: np.ndarray, shapes: list[col.Shape]) -> dict[str, Any]:
    """The hardpoints document in the body frame: size, mass, where a cargo block is held, the thrusters, the running lights and
    the collision primitives (boxes and capsules, the hit volumes)."""
    body = Mesh.concatenate(p.mesh for p in parts)
    lo, hi = body.bounds()
    com = np.array([0.0, -0.1, 4.2]) - offset  # the cab's mass sits aft, between the root blocks
    _, ports = thruster_meshes(CARGO_POD_CRAFT)
    flip = np.array([-1.0, 1.0, 1.0])
    rcs = []
    for name, p, d in ports:
        for n, pos, ex in ((name, p, d), ("l_" + name[2:], p * flip, d * flip)):
            rcs.append({"name": n, "position": cv.r(pos - offset), "exhaust": cv.r(ex), "tags": pilot_tags(pos - offset, ex, com)})
    grips = []
    for side, tag in ((1.0, "r"), (-1.0, "l")):
        grips.append({"name": f"grip_{tag}", "position": cv.r(np.array([side * ARM_X, HAND_Y, 0.30]) - offset), "closing": [0.0, 1.0, 0.0], "bone": f"wrist_{tag}",
                      "jaw_gap_m": round(2.0 * (JAWS_Y[0] - HAND_Y) - 0.27, 3)})
    hold = np.array([0.0, HAND_Y, 0.0]) - offset
    main = {"position": cv.r(np.array([0.0, -0.14, ENGINE_FACE_Z + 0.02]) - offset), "exhaust": [0.0, 0.0, 1.0], "size_m": [0.94, 0.62]}
    side_light = np.array([1.64 + NAV_CLEARANCE_M, -0.41, 5.2])
    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(float(hi[2] - lo[2]), 3),
        "width_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "bound_radius_m": round(float(np.linalg.norm(body.vertices, axis=1).max()), 3),
        "nose": [0.0, 0.0, -1.0],
        "mass_kg": MASS_KG,
        "center_of_mass": cv.r(com),
        "cargo_hold": {"position": cv.r(hold), "forward": [0.0, 0.0, -1.0], "span_m": round(2.0 * ARM_X, 3)},
        "grips": grips,
        "main_thruster": main,
        "rcs": rcs,
        "nav_lights": {"port": cv.r(side_light * flip - offset), "starboard": cv.r(side_light - offset),
                       "top": cv.r(np.array([0.0, 0.95 + NAV_CLEARANCE_M, 5.4]) - offset)},
        "cockpit": cv.r(np.array([0.0, -0.05, 1.6]) - offset),
        "collision": [s.hit_volume().to_json() for s in shapes],
    }


# --- build ---------------------------------------------------------------------------------------------------------------------
def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the cargo pod into ``ctx.out_dir``. Option: ``atlas_px`` (default 1 024)."""
    atlas_px = int(ctx.option("atlas_px", ATLAS_PX))
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    parts, offset = centre(build_parts())
    body = Mesh.concatenate(p.mesh for p in parts)
    aabb_min, aabb_max = body.bounds()
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)
    files: list[Path] = write_obj(out_dir / OBJ_NAME, body, ASSET_ID, comments)
    texel = cv.texel_of(parts, atlas_px)
    textured_paths, mesh_entry = write_textured_mesh(out_dir, ASSET_ID, parts, cv.at_texel(CARGO_POD_CRAFT, texel), atlas_px=atlas_px,
                                                     texel_m=texel, seed=ctx.seed, occlusion=True, normal_scale=1, grid=False,
                                                     detail_levels=cv.DETAIL_LEVELS,
                                                     joints=[GlbJoint(j.name, j.parent, tuple(np.array(j.position) - offset)) for j in rig_joints()])
    files += textured_paths
    shapes = collision_shapes(offset)
    hp = hardpoints(parts, offset, shapes)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=offset,
        files={"obj": OBJ_NAME, "mesh": mesh_entry["file"], "hardpoints": HARDPOINTS_NAME},
        extra={"dimensions_m": {"length": hp["length_m"], "width": hp["width_m"], "height": hp["height_m"]}, "mesh": mesh_entry,
               "collision": col.section({"craft": shapes}), "rig": rig_section(offset)},
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
