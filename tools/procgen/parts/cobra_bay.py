"""The Cobra-bay hangar's shapes (M7-T09, M7-T20; D77): the inside of one Cobra arm's launch halls, for the front end's backdrop.

The hall frame (Godot, metres): +y up, toward the drum's axis (the spin's gravity pulls outward, so the floor is the arm's outer
skin and the launch doors are in it); z along the arm, the arm's head (and the station's bow) toward -z; x across; the origin on
the floor in the middle of the upper hall. Everything is read from the station's ``hardpoints.cobra_arm``
(``station_hardpoints.cobra_arm_layout``, M7-T20): the six doors (about 20 by 14 m, one Starfury each, two leaves meeting along the
arm) and their pitch; the upper hall over the doors (between the arm's creases) and the wider lower hall above it, toward the axis
(without a ``lower_hall`` the hall is one level); where a fighter hangs and is released; where the second row is staged.

What drives each choice (references in ``references/``, inspiration only):

* The show's Cobra-bay capture (most weight): a dark, industrial hall; the fighters held from above by gantry machinery and clamp
  arms; red and white lamps among the gantries; hazard striping on floor edges and rails; orange and yellow striped canisters
  along the side. So every fighter is held from above by its own clamp, and the hall is lit low, red and white. Twelve to the
  hall (the maintainer, 2026-11-13): six on the racks over the doors, launching first, held by clamp arms off the upper hall's
  walls (the station's arm, M7-T21: the rack's middle stays open), and the second row of six staged in the lower hall, each on a
  crane's clamp that carries it across and down onto its rack for the second wave.
* The fan render of numbered bays (a suggestion): each bay framed by a red portal with cut corners, big red bay numbers on the
  walls, yellow railings, ladders and catwalks, hazard bands at the bay edges.
* The fan diorama (a suggestion): the "01" bay number; its cradle under the fighter is left out, the show holds them from above.
* The docking-bay captures: machinery walls and pink-lit panels; the bay's warm orange glow leaking round the closed doors.

One launch position (``slice_shapes``) is built once and drawn six times; the two end walls with the hall's ends and the
numbers are pieces of their own (``end_shapes``, ``sign_shapes``).
"""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Material, Mesh, basis_from_z, box, lathe, rotation_x
from . import station as st
from . import station_props as sp
from .station_hardpoints import cobra_arm_layout

# --- the halls, from the arm's layout (the station's ``hardpoints.cobra_arm``) --------------------------------------------------
ARM = cobra_arm_layout()
BAYS = int(ARM["doors"])
PITCH_M = float(ARM["pitch_m"])
HALF_PITCH = 0.5 * PITCH_M
DOOR_FLOOR_R = float(ARM["hall"]["floor_r"])  # where the doors lie, as radius from the drum's axis: the hall's y 0
_UPPER = ARM["hall"]
_LOWER = ARM.get("lower_hall") or _UPPER
ARM_X = 0.5 * (float(_UPPER["x"][0]) + float(_UPPER["x"][1]))  # the arm's x and z at the hall's origin
ARM_Z = 0.5 * (float(_UPPER["z"][0]) + float(_UPPER["z"][1]))
HALF_W = 0.5 * (float(_UPPER["x"][1]) - float(_UPPER["x"][0]))  # the upper hall's half width
LOW_W = 0.5 * (float(_LOWER["x"][1]) - float(_LOWER["x"][0]))  # the lower hall's
TWO_LEVELS = LOW_W > HALF_W + 1e-6
UP_H = DOOR_FLOOR_R - float(_UPPER["ceiling_r"])  # where the upper hall gives onto the lower one
HEIGHT = DOOR_FLOOR_R - float(_LOWER["ceiling_r"])  # floor to the lower hall's ceiling
END_Z = 0.5 * (float(_UPPER["z"][1]) - float(_UPPER["z"][0]))  # the end walls
ROW_HALF = BAYS * HALF_PITCH  # the launch positions run to +-ROW_HALF; the ends' bays fill the rest to the end walls
LEDGE_T = 0.6  # the lower hall's floor beside the upper hall
if abs(0.5 * (float(_LOWER["x"][0]) + float(_LOWER["x"][1])) - ARM_X) > 1e-6:
    raise ValueError("the hangar expects the lower hall centred over the upper one")

# --- the launch door, as T05 built it, seen from inside --------------------------------------------------------------------
DOOR_X, DOOR_Z = (float(v) for v in ARM["door_half_m"])  # half across, half along
LEAF_IN, LEAF_OUT, LEAF_HALF_Z = sp.LEAF  # the leaves' inner and outer edge across, half length along
COAMING_M = 0.6  # the raised, striped lip round the door's well
WELL_DEPTH = 1.2
LEAF_TOP = -0.75
SLATS = 6

# --- the fighters: the racked row over the doors and the second row staged in the lower hall ---------------------------------
RACK_X = ARM_X - float(ARM["strip_x"])  # the doors' and the racked fighters' middle across the hall
HANG_Y = DOOR_FLOOR_R - float(ARM["hang_r"])  # the racked fighters' origin above the floor
STAGE_X = ARM_X - float(ARM["staging_x"])  # the second row's (the hall frame is the arm's turned half a turn: x flips)
STAGE_Y = DOOR_FLOOR_R - float(ARM.get("staging_r", ARM["hang_r"]))
RELEASE_Y = DOOR_FLOOR_R - float(ARM["release_r"])  # where a launch lets go: below the door, clear of the deck outside
WAVE_GAP_S = 10.0  # the second wave drops this long after the first (Q3)
# The Starfury's envelope in its own frame (starfury_aurora, M7-T17 geometry): the fuselage's top and the upper pods' tops, where
# the clamp's pads sit. The Python tests check these against the real hull.
FURY_TOP_Y = 1.5
FURY_POD = (5.53, 3.21, 0.77)  # |x|, top y, z of the upper pods' middles
FURY_POD_R = 0.82  # the pods' radius: where the rack's heads grip their outboard sides
FURY_LOW_Y = -3.64
FURY_HALF_SPAN = 7.7
PAD_Z = (-2.4, 0.4)  # the clamp's pad along the fuselage's back, clear of the canopy's front and the struts behind

# --- the crane: a bridge across under the ceiling on rails along the walls, a clamp for each row's fighter -----------------------
TROLLEY_H = 0.8
TROLLEY_Y = STAGE_Y + FURY_POD[1] + 1.45  # the trolleys' undersides, clear of the second row's clamp arms
BRIDGE_Y = (TROLLEY_Y + TROLLEY_H, TROLLEY_Y + TROLLEY_H + 1.2)
BRIDGE_HALF_Z = 1.2
RAIL_X = (LOW_W - 1.4, LOW_W - 0.2)  # |x| of the crane rails, on the top walls
if BRIDGE_Y[1] > HEIGHT - 0.1:
    raise ValueError("the hall is too low for the crane over the second row")
# The pipe runs along the upper hall's walls above the catwalk (in from the wall, height, radius, paint), kept under the ledge.
_PIPE_TOP = (UP_H - LEDGE_T if TWO_LEVELS else 18.0) - 0.3
PIPE_RUNS = tuple((x, min(y, _PIPE_TOP - r - (3 - k) * 1.0), r, role)
                  for k, (x, y, r, role) in enumerate(((0.55, 14.0, 0.3, "machinery"), (0.55, 14.8, 0.3, "machinery"),
                                                       (0.8, 16.0, 0.5, "trim"), (0.45, 17.4, 0.22, "machinery"))))

# --- the camera's rail for the backdrop: beside the racks on the far side from the second row, looking toward the arm's head (the
# racks and the second row then sit right of the menu); it turns back while the first rack is still ahead ------------------------
_AWAY = -1.0 if STAGE_X >= RACK_X else 1.0  # from the racks, away from the second row
_RAIL_X = RACK_X + _AWAY * 0.5 * (FURY_HALF_SPAN + HALF_W - 2.4)
_FIRST_DOOR_Z = float(ARM["centres"][0][1]) - ARM_Z
CAMERA_RAIL = {"x": round(_RAIL_X, 4), "y": 7.5, "z_from": round(_FIRST_DOOR_Z + 14.0, 4), "z_to": round(END_Z - 6.0, 4),
               "look_x": round(0.5 * (_RAIL_X + RACK_X), 4), "look_dir": -1.0}
# Each bay's work light (its one light-rig emitter): a lamp hung from the ceiling between the two rows, toward the racks, so it
# lights the racked fighter's back and the second row alike; between the doors along the hall, out of the second row's crossing.
LAMP_AT = (RACK_X + 0.35 * (STAGE_X - RACK_X), min(UP_H + 3.0, BRIDGE_Y[0] - 3.0) if TWO_LEVELS else BRIDGE_Y[0] - 3.0,
           HALF_PITCH - 2.0)


def camera_views() -> dict[str, dict[str, list[float]]]:
    """The look sheets' fixed views (``at`` and ``look``, hall frame): the whole hall from high at the root end; one racked fighter
    close from the camera's side; the racks receding from the catwalks' height; the second row from a little above it, beside
    it."""
    centres = bay_centres()
    door = centres[BAYS // 2 - 1]

    def v(at: tuple[float, float, float], look: tuple[float, float, float]) -> dict[str, list[float]]:
        return {"at": [round(c, 4) for c in at], "look": [round(c, 4) for c in look]}

    return {
        "wide": v((0.5 * (RACK_X + _RAIL_X), HEIGHT - 4.0, END_Z - 3.0), (0.5 * (RACK_X + STAGE_X), HANG_Y + 2.0, -10.0)),
        "close": v((_RAIL_X + 2.0 * -_AWAY, HANG_Y + 1.5, door + 11.0), (RACK_X, HANG_Y, door)),
        "rack": v((RACK_X + _AWAY * (HALF_W - 5.0), 13.0, centres[-1] + 10.0), (RACK_X, HANG_Y, centres[1])),
        "second": v((STAGE_X - 18.0 * (1.0 if STAGE_X >= RACK_X else -1.0), STAGE_Y + 2.0, door + 17.0), (STAGE_X, STAGE_Y, door - 8.0)),
    }


@dataclass(frozen=True)
class Shape:
    """A named mesh in its piece's frame, with the paint laid on it (``(colour, cover)`` pairs, see ``Marking.paint``)."""

    name: str
    mesh: Mesh
    paint: tuple[tuple[tuple[float, float, float], object], ...] = ()


def bay_centres() -> list[float]:
    """Each launch position's middle along the hall (z, hall frame): under the arm's doors."""
    return [float(z) - ARM_Z for _, z in ARM["centres"]]


def to_arm() -> dict[str, list]:
    """The hall frame in the frame of a Cobra arm standing on top of the drum (``cobra_arm``'s frame: +y outward): turned half a
    turn about z (the hall's up is toward the axis), its floor on the doors' plane, its origin in the middle of the upper hall."""
    return {"basis": [[-1.0, 0.0, 0.0], [0.0, -1.0, 0.0], [0.0, 0.0, 1.0]], "origin": [ARM_X, DOOR_FLOOR_R, ARM_Z]}


# --- primitives --------------------------------------------------------------------------------------------------------
def block(lo: Sequence[float], hi: Sequence[float], m: Material) -> Mesh:
    return st.block(lo, hi, m)


def bar(p0: Sequence[float], p1: Sequence[float], width: float, m: Material) -> Mesh:
    """A square bar ``width`` across from ``p0`` to ``p1``: lattice members, braces and hoses."""
    a, b = np.asarray(p0, dtype=float), np.asarray(p1, dtype=float)
    length = float(np.linalg.norm(b - a))
    one = box((width, width, length), m)
    return one.transformed(basis_from_z(b - a), 0.5 * (a + b))


def mirror_x(mesh: Mesh) -> Mesh:
    """A mesh and its mirror across x = 0."""
    return Mesh.concatenate([mesh, mesh.mirrored("x")])


def pipe(axis: str, at: Sequence[float], span: tuple[float, float], radius: float, m: Material, segments: int = 12) -> Mesh:
    """A pipe of ``radius`` along ``axis`` ("z" or "y") from ``span[0]`` to ``span[1]``, its axis through ``at`` (the other two
    coordinates)."""
    a, b = span
    tube = lathe([(0.0, 0.0), (0.0, radius), (b - a, radius), (b - a, 0.0)], segments, m, creases=(1, 2))
    if axis == "z":
        return tube.translated((at[0], at[1], a))
    return tube.transformed(rotation_x(-0.5 * math.pi), (at[0], a, at[1]))  # local z onto +y; ``at`` is (x, z)


def gusset(corner: Sequence[float], dx: float, dy: float, z: tuple[float, float], m: Material) -> Mesh:
    """A triangular fill in the x-y corner at ``corner``, legs ``dx`` and ``dy`` (signed), along z: the bay portals' cut corners."""
    cx, cy = corner
    outline = [(cx, cy), (cx + dx, cy), (cx, cy + dy)]
    if dx * dy < 0.0:
        outline = outline[::-1]
    return st.flat_plate(outline, [outline], z[1] - z[0], np.eye(3), (0.0, 0.0, 0.5 * (z[0] + z[1])), m)


def stripes(pitch: float = 1.2, axis: tuple[float, float, float] = (1.0, 0.0, 1.0)) -> object:
    """A hazard band's dark stripes, diagonal across x and z (or as ``axis`` weighs them)."""
    w = np.asarray(axis, dtype=float)

    def cover(p: np.ndarray, _n: np.ndarray) -> np.ndarray:
        return (np.mod(p @ w, pitch) < 0.5 * pitch).astype(float)

    return cover


DARK = (0.03, 0.03, 0.03)


# --- one launch position ------------------------------------------------------------------------------------------------
def _at_door(mesh: Mesh) -> Mesh:
    """A mesh built about the door's middle, moved under the strip."""
    return mesh.translated((RACK_X, 0.0, 0.0))


def _deck(m: Mapping[str, Material]) -> list[Shape]:
    h, wx, wz = HALF_PITCH, DOOR_X + COAMING_M, DOOR_Z + COAMING_M
    x0, x1 = RACK_X - wx, RACK_X + wx
    deck = Mesh.concatenate([
        block((-HALF_W, -0.6, -h), (HALF_W, 0.0, -wz), m["deck"]), block((-HALF_W, -0.6, wz), (HALF_W, 0.0, h), m["deck"]),
        block((-HALF_W, -0.6, -wz), (x0, 0.0, wz), m["deck"]), block((x1, -0.6, -wz), (HALF_W, 0.0, wz), m["deck"]),
    ])
    # Yellow walk lines along both sides of the door, as the fan render's floor.
    def walk_line(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        return ((np.abs(np.abs(p[:, 0] - RACK_X) - (wx + 1.2)) < 0.1) & (n[:, 1] > 0.5)).astype(float)

    coaming = _at_door(Mesh.concatenate([
        block((-wx, 0.0, -wz), (wx, 0.25, -DOOR_Z), m["hatch"]), block((-wx, 0.0, DOOR_Z), (wx, 0.25, wz), m["hatch"]),
        mirror_x(block((DOOR_X, 0.0, -DOOR_Z), (wx, 0.25, DOOR_Z), m["hatch"])),
    ]))
    well = _at_door(Mesh.concatenate([
        block((-DOOR_X, -WELL_DEPTH, -wz), (DOOR_X, 0.0, -DOOR_Z), m["recess"]),
        block((-DOOR_X, -WELL_DEPTH, DOOR_Z), (DOOR_X, 0.0, wz), m["recess"]),
        mirror_x(block((DOOR_X, -WELL_DEPTH, -wz), (wx, 0.0, wz), m["recess"])),
    ]))
    # The bay's light round the closed leaves and down their seam: what shows outside as the doors' lit edges.
    glow = _at_door(Mesh.concatenate([
        mirror_x(block((LEAF_OUT, -WELL_DEPTH, -DOOR_Z), (DOOR_X, -WELL_DEPTH + 0.1, DOOR_Z), m["bay_light"])),
        block((-LEAF_OUT, -WELL_DEPTH, -DOOR_Z), (LEAF_OUT, -WELL_DEPTH + 0.1, -LEAF_HALF_Z), m["bay_light"]),
        block((-LEAF_OUT, -WELL_DEPTH, LEAF_HALF_Z), (LEAF_OUT, -WELL_DEPTH + 0.1, DOOR_Z), m["bay_light"]),
        block((-0.15, -WELL_DEPTH, -LEAF_HALF_Z), (0.15, -WELL_DEPTH + 0.1, LEAF_HALF_Z), m["bay_light"]),
    ]))
    latches = _at_door(Mesh.concatenate(mirror_x(block((DOOR_X - 0.2, 0.25, z - 0.8), (DOOR_X + 0.5, 0.75, z + 0.8), m["trim"]))
                                        for z in (-4.0, 4.0)))
    return [Shape("deck", deck, ((m["hatch"].albedo, walk_line),)), Shape("coaming", coaming, ((DARK, stripes()),)),
            Shape("well", well), Shape("door_glow", glow), Shape("latches", latches)]


def _leaves(m: Mapping[str, Material]) -> list[Shape]:
    # Seen from inside the leaves are bare structure: grey plating with the door's red-brown on the slats.
    leaf = [block((LEAF_IN, LEAF_TOP - 0.35, -LEAF_HALF_Z), (LEAF_OUT, LEAF_TOP, LEAF_HALF_Z), m["deck"])]
    pitch = 2.0 * LEAF_HALF_Z / SLATS
    leaf += [block((LEAF_IN + 0.3, LEAF_TOP, -LEAF_HALF_Z + k * pitch - 0.12), (LEAF_OUT - 0.6, LEAF_TOP + 0.12,
                   -LEAF_HALF_Z + k * pitch + 0.12), m["door"]) for k in range(1, SLATS)]
    hinge = pipe("z", (LEAF_OUT - 0.3, LEAF_TOP + 0.1), (-LEAF_HALF_Z + 0.4, LEAF_HALF_Z - 0.4), 0.3, m["machinery"])
    # The rams that swing each leaf down: a cylinder and its rod from the well's side to the leaf.
    rams = Mesh.concatenate(block((LEAF_OUT - 2.2, LEAF_TOP, z - 0.3), (LEAF_OUT - 0.5, LEAF_TOP + 0.45, z + 0.3), m["machinery"])
                            for z in (-3.5, 3.5))
    seam = block((-LEAF_IN, LEAF_TOP - 0.2, -LEAF_HALF_Z), (LEAF_IN, LEAF_TOP - 0.05, LEAF_HALF_Z), m["hatch"])
    # A hazard band down the seam where the leaves meet, as the leaves' faces show outside.
    def seam_band(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        return (np.abs(p[:, 0] - RACK_X) < LEAF_IN + 1.0).astype(float) * (n[:, 1] > 0.5)

    def seam_dark(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        return seam_band(p, n) * stripes(1.2)(p, n)

    return [Shape("leaves", _at_door(mirror_x(Mesh.concatenate(leaf + [hinge, rams]))), ((m["hatch"].albedo, seam_band), (DARK, seam_dark))),
            Shape("seam", _at_door(seam), ((DARK, stripes(1.2)),))]


def _wall_side(m: Mapping[str, Material]) -> dict[str, list[Mesh]]:
    """One side (+x): the upper hall's wall and what stands on it, then the lower hall's floor beside it (a ledge) and its wall,
    by part."""
    h, w, lw = HALF_PITCH, HALF_W, LOW_W
    out: dict[str, list[Mesh]] = {k: [] for k in ("wall", "cabinets", "panels", "canisters", "ladder", "catwalk", "railing", "pipes",
                                                  "wall_lamps", "wall_glow", "pilasters", "ledge")}
    out["wall"].append(block((w, 0.0, -h), (w + 1.0, UP_H - LEDGE_T if TWO_LEVELS else HEIGHT, h), m["wall"]))
    # The machinery bank along the floor: cabinets of different depths with pink-lit panels (the docking-bay captures).
    for z0, z1, depth, ctop, lit in ((-h + 1.2, -h + 5.4, 1.6, 6.5, ((3.5, 5.0),)), (h - 6.4, h - 1.2, 1.8, 8.0, ((2.2, 3.4), (5.2, 6.6)))):
        out["cabinets"].append(block((w - depth, 0.0, z0), (w, ctop, z1), m["wall"]))
        out["cabinets"].append(block((w - depth - 0.25, ctop - 0.4, z0 - 0.2), (w, ctop, z1 + 0.2), m["frame"]))  # a lip on top
        for y0, y1 in lit:
            out["panels"].append(block((w - depth - 0.03, y0, z0 + 0.5), (w - depth, y1, z1 - 0.5), m["panel_light"]))
    # Vertical pipes up to the catwalk, and a ladder (the fan render's ladders).
    out["pipes"] += [pipe("y", (w - 0.5, z), (0.0, 11.8), 0.22, m["machinery"]) for z in (-2.6, -2.0)]
    lz = 0.0
    out["ladder"] += [block((w - 0.8, 0.0, lz + s - 0.05), (w - 0.7, 13.0, lz + s + 0.05), m["hatch"]) for s in (-0.3, 0.3)]
    out["ladder"] += [block((w - 0.8, y - 0.03, lz - 0.3), (w - 0.7, y + 0.03, lz + 0.3), m["hatch"])
                      for y in np.arange(0.4, 12.0, 0.4)]
    out["ladder"] += [block((w - 0.7, y - 0.05, lz - 0.35), (w, y + 0.05, lz - 0.25), m["hatch"]) for y in (2.0, 6.0, 10.0)]
    # The catwalk at 12 m, its brackets and its yellow railing.
    out["catwalk"].append(block((w - 3.0, 11.8, -h), (w, 12.0, h), m["deck"]))
    out["catwalk"] += [block((w - 3.0, 10.9, z - 0.08), (w, 11.8, z + 0.08), m["frame"]) for z in (-h + 3.0, h - 3.0)]
    out["railing"] += [block((w - 3.0, 12.0, z - 0.05), (w - 2.9, 13.1, z + 0.05), m["hatch"])
                       for z in np.arange(-h + 1.6, h, 3.2) if abs(z - lz) > 1.0]
    out["railing"] += [block((w - 3.0, y - 0.05, -h), (w - 2.9, y + 0.05, h), m["hatch"]) for y in (12.55, 13.1)]
    # The red lamps under the catwalk and the bay's warm light along the wall.
    out["wall_lamps"] += [block((w - 0.45, 10.2, z - 0.5), (w, 10.6, z + 0.5), m["lamp"]) for z in (-h * 0.5, h * 0.5)]
    out["wall_glow"].append(block((w - 0.25, 10.85, -h + 1.0), (w, 11.0, h - 1.0), m["bay_light"]))
    # Pipe runs along the hall above the catwalk, on brackets.
    for x, y, r, role in PIPE_RUNS:
        out["pipes"].append(pipe("z", (w - x, y), (-h, h), r, m[role]))
    top = max(y + r for _, y, r, _ in PIPE_RUNS) + 0.2
    out["pipes"] += [block((w - 1.45, PIPE_RUNS[0][1] - 0.6, z - 0.15), (w, top, z + 0.15), m["frame"]) for z in (-h * 0.5, h * 0.5)]
    if TWO_LEVELS:
        # The lower hall's floor beside the upper hall: a ledge with a striped edge and a yellow railing; its wall with pilasters,
        # vents, a cabinet and the show's striped canisters.
        out["ledge"].append(block((w, UP_H - LEDGE_T, -h), (lw, UP_H, h), m["deck"]))
        out["ledge"].append(block((w - 0.3, UP_H - 1.4, -h), (w, UP_H, h), m["hatch"]))  # the striped fascia
        out["railing"] += [block((w + 0.2, UP_H, z - 0.05), (w + 0.3, UP_H + 1.1, z + 0.05), m["hatch"]) for z in np.arange(-h + 1.6, h, 3.2)]
        out["railing"] += [block((w + 0.2, UP_H + y - 0.05, -h), (w + 0.3, UP_H + y + 0.05, h), m["hatch"]) for y in (0.55, 1.1)]
        out["wall"].append(block((lw, UP_H - LEDGE_T, -h), (lw + 1.0, HEIGHT, h), m["wall"]))
        out["pilasters"] += [block((lw - 0.6, UP_H, z - 0.4), (lw, HEIGHT, z + 0.4), m["frame"]) for z in (-h * 0.5, h * 0.5)]
        out["pilasters"] += [block((lw - 0.12, HEIGHT - 3.0, z0), (lw, HEIGHT - 2.2, z1), m["recess"])
                             for z0, z1 in ((-h + 1.0, -h * 0.5 - 1.0), (h * 0.5 + 1.0, h - 1.0))]
        out["cabinets"].append(block((lw - 2.0, UP_H, -h * 0.5 + 0.8), (lw, UP_H + 5.0, h * 0.5 - 0.8), m["wall"]))
        out["panels"].append(block((lw - 2.03, UP_H + 2.0, -h * 0.5 + 1.4), (lw - 2.0, UP_H + 3.2, h * 0.5 - 1.4), m["panel_light"]))
        for z in (-h + 1.5, h - 1.5):
            out["canisters"].append(pipe("y", (lw - 1.3, z), (UP_H, UP_H + 3.4), 0.9, m["canister"], 16))
        out["wall_lamps"] += [block((lw - 0.45, UP_H + 6.0, z - 0.5), (lw, UP_H + 6.4, z + 0.5), m["lamp"]) for z in (-h + 2.0, h - 2.0)]
        out["wall_glow"].append(block((lw - 0.25, UP_H + 6.6, -h + 1.0), (lw, UP_H + 6.75, h - 1.0), m["bay_light"]))
    else:
        out["pilasters"] += [block((w - 0.6, 18.0, z - 0.4), (w, HEIGHT, z + 0.4), m["frame"]) for z in (-h * 0.5, h * 0.5)]
        for z in (-h + 1.5, h - 1.5):
            out["canisters"].append(pipe("y", (w - 1.3, z), (0.0, 3.4), 0.9, m["canister"], 16))
    return out


def _walls(m: Mapping[str, Material]) -> list[Shape]:
    side = _wall_side(m)
    shapes = []
    for name, meshes in side.items():
        if not meshes:
            continue
        mesh = mirror_x(Mesh.concatenate(meshes))
        paint = ()
        if name == "canisters":
            base = UP_H if TWO_LEVELS else 0.0

            def bands(p: np.ndarray, _n: np.ndarray) -> np.ndarray:  # yellow bands at the top and bottom of each canister
                y = p[:, 1] - base
                return (((y > 0.4) & (y < 0.9)) | ((y > 2.5) & (y < 3.0))).astype(float)

            def dark(p: np.ndarray, n: np.ndarray) -> np.ndarray:
                return bands(p, n) * (np.mod(p[:, 1] * 4.0 + np.arctan2(p[:, 2], p[:, 0]) * 2.0, 2.0) < 1.0)

            paint = ((m["hatch"].albedo, bands), (DARK, dark))
        elif name == "ledge":
            def fascia(p: np.ndarray, n: np.ndarray) -> np.ndarray:  # the ledge's edge striped where it drops to the upper hall
                return (np.abs(np.abs(p[:, 0]) - HALF_W) < 0.31).astype(float) * stripes(1.2, (0.0, 1.0, 1.0))(p, n)

            paint = ((DARK, fascia),)
        shapes.append(Shape(name, mesh, paint))
    return shapes


def _portal(m: Mapping[str, Material]) -> list[Shape]:
    """The red frame round each launch position at its two ends (half a frame at each, the next position's half meets it): the
    fan render's red bay portals with cut corners, round the upper hall and the lower one, and a striped sill across the floor."""
    parts, gussets = [], []
    for sz in (-1.0, 1.0):
        z = (-HALF_PITCH, -HALF_PITCH + 0.7) if sz < 0 else (HALF_PITCH - 0.7, HALF_PITCH)
        parts.append(mirror_x(block((HALF_W - 1.2, 0.0, z[0]), (HALF_W, UP_H if TWO_LEVELS else HEIGHT, z[1]), m["trim"])))
        gussets.append(mirror_x(gusset((HALF_W - 1.2, 0.3), -1.6, 1.6, z, m["trim"])))
        if TWO_LEVELS:
            parts.append(mirror_x(block((LOW_W - 1.2, UP_H, z[0]), (LOW_W, HEIGHT, z[1]), m["trim"])))
            gussets.append(mirror_x(gusset((HALF_W - 1.2, UP_H - 1.4), -2.0, -2.0, z, m["trim"])))
        parts.append(block((-LOW_W, HEIGHT - 1.2, z[0]), (LOW_W, HEIGHT, z[1]), m["trim"]))
        gussets.append(mirror_x(gusset((LOW_W - 1.2, HEIGHT - 1.2), -2.4, -2.4, z, m["trim"])))
    sill = Mesh.concatenate([block((-HALF_W + 1.2, 0.0, -HALF_PITCH), (HALF_W - 1.2, 0.3, -HALF_PITCH + 0.7), m["hatch"]),
                             block((-HALF_W + 1.2, 0.0, HALF_PITCH - 0.7), (HALF_W - 1.2, 0.3, HALF_PITCH), m["hatch"])])
    return [Shape("portal", Mesh.concatenate(parts + gussets)), Shape("sill", sill, ((DARK, stripes()),))]


def _ceiling(m: Mapping[str, Material]) -> list[Shape]:
    h = HALF_PITCH
    ceiling = [block((-LOW_W, HEIGHT, -h), (LOW_W, HEIGHT + 1.0, h), m["recess"])]
    beams = [mirror_x(block((x - 0.4, HEIGHT - 0.9, -h), (x + 0.4, HEIGHT, h), m["frame"])) for x in (0.45 * LOW_W,)]
    beams += [mirror_x(block((x - 0.8, HEIGHT - 0.25, -h), (x + 0.8, HEIGHT - 0.1, h), m["frame"])) for x in (0.2 * LOW_W, 0.75 * LOW_W)]
    beams += [block((-LOW_W, HEIGHT - 0.6, z - 0.3), (LOW_W, HEIGHT, z + 0.3), m["frame"]) for z in (-h * 0.5, h * 0.5)]
    fx = 0.6 * LOW_W
    floods = [mirror_x(block((fx - 1.2, HEIGHT - 0.7, z - 0.6), (fx + 1.2, HEIGHT - 0.6, z + 0.6), m["work_light"])) for z in (-h * 0.5, h * 0.5)]
    housings = [mirror_x(block((fx - 1.4, HEIGHT - 0.6, z - 0.8), (fx + 1.4, HEIGHT - 0.1, z + 0.8), m["frame"])) for z in (-h * 0.5, h * 0.5)]
    return [Shape("ceiling", Mesh.concatenate(ceiling)), Shape("beams", Mesh.concatenate(beams + housings)),
            Shape("floods", Mesh.concatenate(floods))]


def _gantry(m: Mapping[str, Material]) -> list[Shape]:
    """The crane over the door: rails along the top walls, the bridge across under the ceiling and, under it, the second row's
    clamp holding its fighter by its back and its upper pods (the show's overhead clamps; the fan render's red and white cranes);
    its trolley carries the fighter across and down onto the rack. The racked fighter is held by clamp arms from the upper hall's
    walls over its pods, so the rack's middle stays open for that (the station's T21 arm)."""
    h = HALF_PITCH
    r0, r1 = RAIL_X
    rails = mirror_x(Mesh.concatenate([block((r0, BRIDGE_Y[0] - 0.6, -h), (r1, BRIDGE_Y[0], h), m["machinery"]),
                                       block((r1, BRIDGE_Y[0] - 1.6, -h), (LOW_W, BRIDGE_Y[0], h), m["frame"])]))
    bridge = Mesh.concatenate([block((-r1, BRIDGE_Y[0], -BRIDGE_HALF_Z), (r1, BRIDGE_Y[1], BRIDGE_HALF_Z), m["frame"]),
                               mirror_x(block((r0 - 1.0, BRIDGE_Y[0], -1.8), (r1, BRIDGE_Y[1], 1.8), m["trim"]))])
    # A column against each upper wall with a yellow lattice (the fan render's braced columns), under the ledge.
    top = UP_H - LEDGE_T if TWO_LEVELS else BRIDGE_Y[0] - 1.6
    lattice = [block((HALF_W - 1.2, 0.0, h - 2.2), (HALF_W, top, h - 1.0), m["frame"])]
    for k in range(int((top - 2.0) // 2.4)):
        y0, y1 = 1.8 + 2.4 * k, 1.8 + 2.4 * (k + 1)
        za, zb = (h - 2.0, h - 1.2) if k % 2 else (h - 1.2, h - 2.0)
        lattice.append(bar((HALF_W - 1.35, y0, za), (HALF_W - 1.35, y1, zb), 0.14, m["hatch"]))
    lattice = [mirror_x(Mesh.concatenate(lattice))]
    lx, ly, lz = LAMP_AT
    lamps = Mesh.concatenate([block((lx - 0.15, ly + 0.5, lz - 0.15), (lx + 0.15, HEIGHT, lz + 0.15), m["machinery"]),
                              block((lx - 0.9, ly, lz - 0.7), (lx + 0.9, ly + 0.5, lz + 0.7), m["frame"]),
                              block((lx - 0.75, ly - 0.05, lz - 0.55), (lx + 0.75, ly, lz + 0.55), m["work_light"])])
    beacons = Mesh.concatenate([mirror_x(block((r0, BRIDGE_Y[0] - 1.2, 1.4), (r1, BRIDGE_Y[0] - 0.7, 1.8), m["lamp"])),
                                mirror_x(block((0.5 * LOW_W, BRIDGE_Y[0] - 0.4, -0.3), (0.5 * LOW_W + 1.0, BRIDGE_Y[0], 0.3), m["lamp"]))])
    staged, racked = _clamp(m, STAGE_Y), _rack_arms(m)
    joined = {name: Mesh.concatenate([staged[name].translated((STAGE_X, 0.0, 0.0)), racked.get(name, Mesh.empty())])
              for name in staged}
    return [Shape("rails", rails), Shape("bridge", bridge), Shape("drop_arm", joined["drop_arm"]),
            Shape("clamp_arms", joined["clamp_arms"]), Shape("pads", joined["pads"]), Shape("work_lamps", lamps),
            Shape("beacons", Mesh.concatenate([beacons, joined["red"]])), Shape("lattice", Mesh.concatenate(lattice)),
            Shape("hoses", joined["hoses"])]


def _clamp(m: Mapping[str, Material], hang_y: float) -> dict[str, Mesh]:
    """One fighter's clamp, hung from the bridge over x = 0 for a fighter hanging at ``hang_y``: the trolley, the drop arm (a
    sleeve and its ram, as long as the drop needs), the yoke on the fuselage's back, the arms out to the upper pods, the pads, its
    hoses and red lamps."""
    pz0, pz1 = PAD_Z
    cz = 0.5 * (pz0 + pz1)
    pad_y = hang_y + FURY_TOP_Y
    px, pod_top, pod_z = FURY_POD
    pod_y = hang_y + pod_top
    sleeve = max(pad_y + 2.0, TROLLEY_Y - 7.4)  # where the ram leaves its sleeve
    arm = Mesh.concatenate([
        block((-2.0, TROLLEY_Y, cz - 1.8), (2.0, BRIDGE_Y[0], cz + 1.8), m["trim"]),  # the trolley
        block((-0.8, sleeve, cz - 0.8), (0.8, TROLLEY_Y, cz + 0.8), m["frame"]),  # the drop arm's sleeve
        block((-0.55, pad_y + 0.6, cz - 0.55), (0.55, sleeve, cz + 0.55), m["machinery"]),  # its ram
        block((-0.6, pad_y + 0.12, pz0), (0.6, pad_y + 0.6, pz1), m["frame"]),  # the yoke over the fuselage's back
        block((-0.4, pod_y + 0.8, cz - 0.4), (0.4, pod_y + 1.4, pod_z + 0.5), m["frame"]),  # the spine out to the pod clamps
    ])
    clamp_arms = Mesh.concatenate([
        block((-px - 0.8, pod_y + 0.8, pod_z - 0.5), (px + 0.8, pod_y + 1.4, pod_z + 0.5), m["trim"]),  # across, over the pods
        mirror_x(block((px - 0.3, pod_y + 0.06, pod_z - 0.3), (px + 0.3, pod_y + 0.8, pod_z + 0.3), m["frame"])),  # the links down
    ])
    pads = Mesh.concatenate([block((-0.55, pad_y + 0.01, pz0 + 0.1), (0.55, pad_y + 0.12, pz1 - 0.1), m["rubber"]),
                             mirror_x(block((px - 0.3, pod_y + 0.01, pod_z - 0.3), (px + 0.3, pod_y + 0.06, pod_z + 0.3), m["rubber"]))])
    hoses = []
    if TROLLEY_Y - pad_y > 6.0:  # a long drop: hoses from the trolley down the arm to the clamp
        hoses = [bar((2.0, TROLLEY_Y, cz + 1.0), (0.9, pad_y + 3.5, cz + 0.6), 0.22, m["rubber"]),
                 bar((0.9, pad_y + 3.5, cz + 0.6), (0.5, pad_y + 0.7, cz + 0.3), 0.18, m["rubber"]),
                 bar((-2.0, TROLLEY_Y, cz - 1.0), (-0.9, TROLLEY_Y - 6.0, cz - 0.9), 0.3, m["rubber"])]
    red = Mesh.concatenate([mirror_x(block((2.0, TROLLEY_Y + 0.1, cz - 0.4), (2.3, TROLLEY_Y + 0.6, cz + 0.4), m["lamp"])),
                            mirror_x(block((px + 0.8, pod_y + 0.9, pod_z - 0.3), (px + 1.1, pod_y + 1.3, pod_z + 0.3), m["lamp"]))])
    return {"drop_arm": arm, "clamp_arms": clamp_arms, "pads": pads, "hoses": Mesh.concatenate(hoses) if hoses else Mesh.empty(),
            "red": red}


def _rack_arms(m: Mapping[str, Material]) -> dict[str, Mesh]:
    """The racked fighter's clamp: an arm from each upper wall reaching down and in to its upper pod, gripping it from outboard (a
    head and pad against the pod's side), and a red lamp on each wall bracket. Nothing over the fighter, so the second row drops
    straight onto the rack between the heads."""
    px, pod_mid, pod_z = FURY_POD[0], FURY_POD[1] - FURY_POD_R, FURY_POD[2]
    pod_y = HANG_Y + pod_mid
    arms, clamp_arms, pads, red = [], [], [], []
    for sx in (-1.0, 1.0):
        wall, side = sx * HALF_W, RACK_X + sx * (px + FURY_POD_R)  # the wall and the pod's outboard side
        lo, hi = sorted((wall, wall - sx * 1.0))
        arms.append(block((lo, pod_y + 1.6, pod_z - 0.9), (hi, pod_y + 3.6, pod_z + 0.9), m["frame"]))  # the wall bracket
        arms.append(bar((wall - sx * 0.9, pod_y + 2.6, pod_z), (side + sx * 0.9, pod_y + 0.5, pod_z), 0.6, m["trim"]))  # the arm
        a, b = sorted((side + sx * 0.12, side + sx * 0.72))
        clamp_arms.append(block((a, pod_y - 0.5, pod_z - 0.5), (b, pod_y + 0.5, pod_z + 0.5), m["trim"]))  # the head at the pod's side
        a, b = sorted((side + sx * 0.02, side + sx * 0.12))
        pads.append(block((a, pod_y - 0.35, pod_z - 0.35), (b, pod_y + 0.35, pod_z + 0.35), m["rubber"]))
        a, b = sorted((wall - sx * 1.0, wall - sx * 1.3))
        red.append(block((a, pod_y + 2.4, pod_z - 0.4), (b, pod_y + 2.9, pod_z + 0.4), m["lamp"]))
    return {"drop_arm": Mesh.concatenate(arms), "clamp_arms": Mesh.concatenate(clamp_arms), "pads": Mesh.concatenate(pads),
            "red": Mesh.concatenate(red)}


def hide_backs(shapes: list[Shape], half_z: float, inner_z: float | None = None) -> list[Shape]:
    """The shapes less the faces nobody in the hall can see (the slabs' backs, the faces lying on the floor, the ledges, the walls
    or the ceiling, or on the box's ends at +-``half_z``; with ``inner_z``, also the faces against the launch positions at
    +-``inner_z``), so the atlas spends no texels on them."""
    eps = 1e-3
    out = []
    for shape in shapes:
        mesh = shape.mesh
        if mesh.face_count == 0:
            continue
        n, c = mesh.face_normals(), mesh.face_centroids()
        ax = np.abs(c[:, 0])
        outward = n[:, 0] * np.sign(c[:, 0]) > 0.9
        over_well = (np.abs(c[:, 0] - RACK_X) < DOOR_X + COAMING_M - eps) & (np.abs(c[:, 2]) < DOOR_Z + COAMING_M - eps)
        down, up = n[:, 1] < -0.9, n[:, 1] > 0.9
        hidden = (down & (c[:, 1] < -0.59)) | (down & (np.abs(c[:, 1]) < eps) & ~over_well)
        hidden |= up & (c[:, 1] > HEIGHT - eps)
        hidden |= outward & ((ax > LOW_W - eps) | ((ax > HALF_W - eps) & (c[:, 1] < UP_H - LEDGE_T + eps)))
        hidden |= (n[:, 2] * np.sign(c[:, 2]) > 0.9) & (np.abs(c[:, 2]) > half_z - eps)
        if TWO_LEVELS:
            beside = ax > HALF_W + eps
            hidden |= down & beside & (np.abs(c[:, 1] - UP_H) < eps)  # the feet of what stands on the ledges
            hidden |= down & beside & (np.abs(c[:, 1] - (UP_H - LEDGE_T)) < eps)  # the ledges' undersides
            hidden |= up & (ax > HALF_W - eps) & (np.abs(c[:, 1] - (UP_H - LEDGE_T)) < eps)  # the upper walls' tops
        if inner_z is not None:
            hidden |= (np.abs(n[:, 2]) > 0.9) & (np.abs(np.abs(c[:, 2]) - inner_z) < eps)
        out.append(Shape(shape.name, mesh.face_subset(~hidden), shape.paint))
    return [s for s in out if s.mesh.face_count > 0]


def slice_shapes(m: Mapping[str, Material]) -> list[Shape]:
    """One launch position, its door's row at the origin: the floor and its door, the walls and ledges, the portal, the ceiling and
    the crane."""
    return hide_backs(_deck(m) + _leaves(m) + _walls(m) + _portal(m) + _ceiling(m) + _gantry(m), HALF_PITCH)


# --- the two end walls ----------------------------------------------------------------------------------------------------
def _end_wall(m: Mapping[str, Material], sz: float) -> list[Shape]:
    """The wall at ``sz * END_Z`` facing into the hall: a pressure door with toothed leaves (the docking bay's inner airlock),
    hazard bands round it, machinery either side and a lit launch-control booth above it."""
    z_face = sz * END_Z
    thick = (z_face, z_face + sz * 1.5)
    zs = (min(thick), max(thick))
    tag = "head" if sz < 0 else "root"
    inward = -sz  # +z for the head wall

    def zin(depth: float) -> tuple[float, float]:  # a slab from the wall's face ``depth`` into the hall
        a, b = z_face, z_face + inward * depth
        return (min(a, b), max(a, b))

    wall = [block((-LOW_W, 0.0, zs[0]), (LOW_W, HEIGHT + 1.0, zs[1]), m["wall"])]
    dw, dh = min(7.0, HALF_W - 6.0), min(12.0, UP_H - 6.0)
    frame = [block((-dw - 2.0, 0.0, zin(0.8)[0]), (-dw, dh + 2.0, zin(0.8)[1]), m["frame"]),
             block((dw, 0.0, zin(0.8)[0]), (dw + 2.0, dh + 2.0, zin(0.8)[1]), m["frame"]),
             block((-dw - 2.0, dh, zin(0.8)[0]), (dw + 2.0, dh + 2.0, zin(0.8)[1]), m["frame"])]
    # The leaves meet along a sawtooth: each tooth belongs to the left or right leaf in turn.
    leaves = [block((-dw, 0.0, zin(0.3)[0]), (-1.0, dh, zin(0.3)[1]), m["door"]), block((1.0, 0.0, zin(0.3)[0]), (dw, dh, zin(0.3)[1]), m["door"])]
    for k in range(8):
        y0, y1 = k * dh / 8.0, (k + 1) * dh / 8.0
        leaves.append(block((-1.0, y0, zin(0.3)[0]), (1.0, y1, zin(0.3)[1]), m["door"] if k % 2 else m["frame"]))
    band = [block((-dw - 3.2, 0.0, zin(0.4)[0]), (-dw - 2.0, dh + 3.2, zin(0.4)[1]), m["hatch"]),
            block((dw + 2.0, 0.0, zin(0.4)[0]), (dw + 3.2, dh + 3.2, zin(0.4)[1]), m["hatch"]),
            block((-dw - 2.0, dh + 2.0, zin(0.4)[0]), (dw + 2.0, dh + 3.2, zin(0.4)[1]), m["hatch"])]
    by = float(booth_windows(tag)["centre"][1])
    booth = [block((-8.0, by - 2.4, zin(2.5)[0]), (8.0, by + 2.6, zin(2.5)[1]), m["frame"])]
    glass = [block((-7.0, by - 1.4, zin(2.55)[0]), (7.0, by + 1.4, zin(2.55)[1]), m["recess"])]
    machinery = []
    for sx in (-1.0, 1.0):
        for x0, x1, top, depth in ((dw + 4.0, dw + 7.0, 9.0, 2.0), (dw + 7.5, HALF_W - 0.5, min(13.0, UP_H - 2.0), 1.4)):
            if x1 - x0 < 1.5:
                continue
            a, b = sorted((sx * x0, sx * x1))
            machinery.append(block((a, 0.0, zin(depth)[0]), (b, top, zin(depth)[1]), m["wall"]))
            machinery.append(block((a + 0.5, top * 0.45, zin(depth + 0.03)[0]), (b - 0.5, top * 0.45 + 1.2, zin(depth + 0.03)[1]),
                                   m["panel_light"]))
    lamps = [block((x - 0.5, dh + 3.4, zin(0.6)[0]), (x + 0.5, dh + 3.9, zin(0.6)[1]), m["lamp"]) for x in (-5.0, 0.0, 5.0)]

    def band_dark(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        return stripes(1.6, (1.0, 1.0, 0.0))(p, n)

    return [Shape(f"{tag}_wall", Mesh.concatenate(wall)), Shape(f"{tag}_door_frame", Mesh.concatenate(frame)),
            Shape(f"{tag}_leaves", Mesh.concatenate(leaves)), Shape(f"{tag}_band", Mesh.concatenate(band), ((DARK, band_dark),)),
            Shape(f"{tag}_booth", Mesh.concatenate(booth)), Shape(f"{tag}_glass", Mesh.concatenate(glass)),
            Shape(f"{tag}_machinery", Mesh.concatenate(machinery)), Shape(f"{tag}_lamps", Mesh.concatenate(lamps))]


def booth_windows(tag: str) -> dict[str, object]:
    """Where the launch-control booth's lit windows are on the ``<tag>_glass`` part: centre, facing, size. In the lower hall, under
    the crane, when there is one."""
    sz = -1.0 if tag == "head" else 1.0
    z = sz * END_Z - sz * 2.55
    y = 0.5 * (UP_H + BRIDGE_Y[0] - 2.0) if TWO_LEVELS else 19.4
    return {"centre": (0.0, round(y, 4), z), "facing": (0.0, 0.0, -sz), "size": (14.0, 2.8)}


def _end_bay(m: Mapping[str, Material], sz: float) -> list[Shape]:
    """The hall between the last launch position and the end wall at ``sz * END_Z``: floor, walls, ledges, ceiling, catwalks, the
    crane rails and the pipe runs carried on to the wall."""
    z = (min(sz * ROW_HALF, sz * END_Z), max(sz * ROW_HALF, sz * END_Z))
    if z[1] - z[0] < 1e-6:
        return []
    tag = "head" if sz < 0 else "root"
    w, lw = HALF_W, LOW_W
    r0, r1 = RAIL_X
    side = [block((w, 0.0, z[0]), (w + 1.0, UP_H - LEDGE_T if TWO_LEVELS else HEIGHT, z[1]), m["wall"]),
            block((w - 3.0, 11.8, z[0]), (w, 12.0, z[1]), m["deck"]),
            block((r0, BRIDGE_Y[0] - 0.6, z[0]), (r1, BRIDGE_Y[0], z[1]), m["machinery"]),
            block((r1, BRIDGE_Y[0] - 1.6, z[0]), (lw, BRIDGE_Y[0], z[1]), m["frame"]),
            block((w - 0.25, 10.85, z[0]), (w, 11.0, z[1]), m["bay_light"])]
    side += [block((w - 3.0, y - 0.05, z[0]), (w - 2.9, y + 0.05, z[1]), m["hatch"]) for y in (12.55, 13.1)]
    if TWO_LEVELS:
        side += [block((w, UP_H - LEDGE_T, z[0]), (lw, UP_H, z[1]), m["deck"]), block((w - 0.3, UP_H - 1.4, z[0]), (w, UP_H, z[1]), m["hatch"]),
                 block((lw, UP_H - LEDGE_T, z[0]), (lw + 1.0, HEIGHT, z[1]), m["wall"])]
        side += [block((w + 0.2, UP_H + y - 0.05, z[0]), (w + 0.3, UP_H + y + 0.05, z[1]), m["hatch"]) for y in (0.55, 1.1)]
    pipes = [pipe("z", (w - x, y), z, r, m[role]) for x, y, r, role in PIPE_RUNS]
    shell = [block((-w, -0.6, z[0]), (w, 0.0, z[1]), m["deck"]), block((-lw, HEIGHT, z[0]), (lw, HEIGHT + 1.0, z[1]), m["recess"])]
    return [Shape(f"{tag}_bay_shell", Mesh.concatenate(shell)), Shape(f"{tag}_bay_sides", mirror_x(Mesh.concatenate(side))),
            Shape(f"{tag}_bay_pipes", mirror_x(Mesh.concatenate(pipes)))]


def end_shapes(m: Mapping[str, Material]) -> list[Shape]:
    """Both end walls and the hall's ends between them and the launch positions, in the hall frame."""
    shapes = [s for sz in (-1.0, 1.0) for s in _end_wall(m, sz) + _end_bay(m, sz) if s.mesh.face_count > 0]
    return hide_backs(shapes, END_Z, ROW_HALF)


# --- the bay numbers --------------------------------------------------------------------------------------------------------
NUMBER_RED = (0.42, 0.045, 0.035)  # the fan render's red stencil, linear
PLATE_WHITE = (0.62, 0.62, 0.6)


def number_panel() -> tuple[float, float, float, float]:
    """The bay numbers' panels: |x| of their faces, half length along the wall, bottom and top: on the lower hall's walls (on the
    upper hall's, above its pipes, when there is one level)."""
    if TWO_LEVELS:
        y0 = UP_H + 1.4
        return (LOW_W - 0.3, min(4.2, HALF_PITCH - 1.6), y0, min(y0 + 5.4, BRIDGE_Y[0] - 2.0))
    return (HALF_W - 0.3, min(4.2, HALF_PITCH - 1.6), 18.4, 23.8)


def plate() -> tuple[float, float, float, float]:
    """The bridge's number plates: their middle across (beside the racked fighter's trolley, on the camera's side), half width,
    bottom and top."""
    return (RACK_X + _AWAY * 4.5, 1.8, BRIDGE_Y[0] + 0.1, BRIDGE_Y[1] - 0.1)


def sign_shapes(m: Mapping[str, Material]) -> list[Shape]:
    """The big red bay numbers on both walls, and a plate on each crane's bridge, in the hall frame. The numbers themselves are text
    markings laid by the asset (``b5_interior.sign_parts``)."""
    shapes = []
    face, half, y0, y1 = number_panel()
    px, pw, py0, py1 = plate()
    for k, z in enumerate(bay_centres(), start=1):
        shapes.append(Shape(f"number_panels_{k}", mirror_x(block((face, y0, z - half), (face + 0.28, y1, z + half), m["wall"]))))
        # A part per bay, so each plate's number paints its own plate only.
        shapes.append(Shape(f"bridge_plates_{k}", Mesh.concatenate([
            block((px - pw, py0, z - BRIDGE_HALF_Z - 0.1), (px + pw, py1, z - BRIDGE_HALF_Z), m["frame"]),
            block((px - pw, py0, z + BRIDGE_HALF_Z), (px + pw, py1, z + BRIDGE_HALF_Z + 0.1), m["frame"])])))
    return hide_backs(shapes, END_Z)


def number_text(k: int) -> tuple[str, str]:
    """Bay ``k``'s number (from 1) as the wall shows it and as the bridge's plate shows it."""
    return str(k), f"{k:02d}"


__all__ = ["ARM", "BAYS", "camera_views", "BRIDGE_Y", "CAMERA_RAIL", "END_Z", "HALF_PITCH", "HALF_W", "HANG_Y", "HEIGHT", "LAMP_AT", "LOW_W", "PITCH_M",
           "RACK_X", "RELEASE_Y", "STAGE_X", "STAGE_Y", "Shape", "TWO_LEVELS", "UP_H", "WAVE_GAP_S", "bay_centres", "booth_windows",
           "end_shapes", "number_panel", "number_text", "plate", "sign_shapes", "slice_shapes", "to_arm"]
