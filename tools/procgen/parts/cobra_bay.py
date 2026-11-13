"""The Cobra-bay hangar's shapes (M7-T09, D77): the inside of one Cobra arm's launch bay, for the front end's backdrop.

The hall frame (Godot, metres): +y up, toward the drum's axis (the spin's gravity pulls outward, so the floor is the arm's outer
skin and the launch doors are in it); z along the arm, the arm's head (and the station's bow) toward -z; x across; the origin on
the floor in the middle of the row of doors. The hall matches the arm outside (``parts/station.py``): seven launch positions at the
doors' pitch, each door 64 by 28 m with the two grated leaves meeting along the arm, as T04 built them from outside.

What drives each choice (references in ``references/``, inspiration only):

* The show's Cobra-bay capture (most weight): a dark, industrial hall; the fighters held from above by gantry machinery and clamp
  arms; red and white lamps among the gantries; hazard striping on floor edges and rails; orange and yellow striped canisters
  along the side. So the fighters hang from a gantry crane over each door, each from its own clamp, and the hall is lit low,
  red and white. Three a door, side by side, at the arm's true scale (the maintainer, 2026-11-13), so the hall feels full.
* The fan render of numbered bays (a suggestion): each bay framed by a red portal with cut corners, big red bay numbers on the
  walls, yellow railings, ladders and catwalks, hazard bands at the bay edges.
* The fan diorama (a suggestion): the "01" bay number; its cradle under the fighter is left out, the show holds them from above.
* The docking-bay captures: machinery walls and pink-lit panels; the bay's warm orange glow leaking round the closed doors.

One launch position (``slice_shapes``) is built once and drawn seven times; the two end walls and the numbers are pieces of
their own (``end_shapes``, ``sign_shapes``).
"""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Material, Mesh, basis_from_z, box, lathe, rotation_x
from . import station as st

# --- the hall, from the arm outside -------------------------------------------------------------------------------
BAYS = st.COBRA_DOORS
PITCH_M = (st.DOOR_ROW[1] - st.DOOR_ROW[0]) / BAYS  # 38.57 m between launch positions
HALF_PITCH = 0.5 * PITCH_M
ROW_MID_Z = 0.5 * sum(st.DOOR_ROW)  # the arm's z (station frame) at the hall's origin
HALF_W = 42.0  # the hall's inner half width: the arm's 47 m less its wall
HEIGHT = 30.0  # floor to ceiling: the doors' plane (r 239) to r 209
END_Z = BAYS * HALF_PITCH  # the end walls stand at +-END_Z, on the outer launch positions' edges
DOOR_FLOOR_R = st.ARM_HATCH[4] - st.DOOR_DEPTH  # where the doors lie, as radius from the drum's axis: the hall's y 0

# --- the launch door, as T04 built it, seen from inside -------------------------------------------------------------
DOOR_X, DOOR_Z = st.DOOR_HALF  # 32 by 14 half
LEAF_IN, LEAF_OUT, LEAF_HALF_Z = 0.75, 31.25, 13.0  # the leaves' inner and outer edge across, half length along (station_props.LEAF)
COAMING_M = 0.8  # the raised, striped lip round the door's well
WELL_DEPTH = 1.2
LEAF_TOP = -0.75
SLATS = 6

# --- the rack: a gantry crane over each door holding three Starfuries side by side, each from its own clamp ----------------------
HANG_Y = 9.0  # the held fighters' origin above the floor (their belly pods clear the door by about 5 m)
# Where each fighter hangs across its door (the maintainer, 2026-11-13: several per door at the arm's true scale). 20 m apart, so
# the 15.4 m Starfuries keep 4.6 m between their pods and all three drop through the 62.5 m between the leaves' outer edges.
SLOT_X = (-20.0, 0.0, 20.0)
RELEASE_Y = -8.0  # where a fighter is let go: below the door, clear of the frame round the doors outside (4 m) by 4 m
# The Starfury's envelope in its own frame (starfury_aurora, M7-T17 geometry): the fuselage's top and the upper pods' tops, where
# the clamp's pads sit. The Python tests check these against the real hull.
FURY_TOP_Y = 1.5
FURY_POD = (5.53, 3.21, 0.77)  # |x|, top y, z of the upper pods' middles
FURY_LOW_Y = -3.64
PAD_Z = (-2.4, 0.4)  # the clamp's pad along the fuselage's back, clear of the canopy's front and the struts behind
COLUMN_X = (34.5, 37.5)
RAIL_Y = (24.0, 25.2)  # the crane rails along the hall, on the columns
BRIDGE_Y = (25.2, 27.2)
BRIDGE_HALF_Z = 1.6
WORK_LAMP = (33.55, 19.6)  # |x| of the column lamps' faces, their height: aimed across at the fighter
BRIDGE_LAMP = (8.0, BRIDGE_Y[0] - 0.25)  # |x| and height of the white work lamps under each bridge, over the fighter's pods

# --- the camera's rail for the backdrop: the +x walkway, between the outer fighters and the columns (looking aft, the racks
# then sit right of the menu) ---------------------------------------------------------------------------------------------------
CAMERA_RAIL = {"x": 31.0, "y": 7.5, "z_from": -112.0, "z_to": 96.0}


@dataclass(frozen=True)
class Shape:
    """A named mesh in its piece's frame, with the paint laid on it (``(colour, cover)`` pairs, see ``Marking.paint``)."""

    name: str
    mesh: Mesh
    paint: tuple[tuple[tuple[float, float, float], object], ...] = ()


def bay_centres() -> list[float]:
    """Each launch position's middle along the hall (z, hall frame): under the arm's doors."""
    return [c - ROW_MID_Z for c in st.door_centres()]


def to_arm() -> dict[str, list]:
    """The hall frame in the frame of a Cobra arm standing on top of the drum (``parts/station.py``: +y outward): turned half
    a turn about z (the hall's up is toward the axis), its floor on the doors' plane, its origin under the row's middle."""
    return {"basis": [[-1.0, 0.0, 0.0], [0.0, -1.0, 0.0], [0.0, 0.0, 1.0]], "origin": [0.0, DOOR_FLOOR_R, ROW_MID_Z]}


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
def _deck(m: Mapping[str, Material]) -> list[Shape]:
    h, wx, wz = HALF_PITCH, DOOR_X + COAMING_M, DOOR_Z + COAMING_M
    deck = Mesh.concatenate([
        block((-HALF_W, -0.6, -h), (HALF_W, 0.0, -wz), m["deck"]), block((-HALF_W, -0.6, wz), (HALF_W, 0.0, h), m["deck"]),
        mirror_x(block((wx, -0.6, -wz), (HALF_W, 0.0, wz), m["deck"])),
    ])
    # Yellow walk lines along both sides of the door, as the fan render's floor.
    def walk_line(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        return ((np.abs(np.abs(p[:, 0]) - 33.6) < 0.12) & (n[:, 1] > 0.5)).astype(float)

    coaming = Mesh.concatenate([
        block((-wx, 0.0, -wz), (wx, 0.25, -DOOR_Z), m["hatch"]), block((-wx, 0.0, DOOR_Z), (wx, 0.25, wz), m["hatch"]),
        mirror_x(block((DOOR_X, 0.0, -DOOR_Z), (wx, 0.25, DOOR_Z), m["hatch"])),
    ])
    well = Mesh.concatenate([
        block((-DOOR_X, -WELL_DEPTH, -wz), (DOOR_X, 0.0, -DOOR_Z), m["recess"]),
        block((-DOOR_X, -WELL_DEPTH, DOOR_Z), (DOOR_X, 0.0, wz), m["recess"]),
        mirror_x(block((DOOR_X, -WELL_DEPTH, -wz), (wx, 0.0, wz), m["recess"])),
    ])
    # The bay's light round the closed leaves and down their seam: what shows outside as the doors' lit edges.
    glow = Mesh.concatenate([
        mirror_x(block((LEAF_OUT, -WELL_DEPTH, -DOOR_Z), (DOOR_X, -WELL_DEPTH + 0.1, DOOR_Z), m["bay_light"])),
        block((-LEAF_OUT, -WELL_DEPTH, -DOOR_Z), (LEAF_OUT, -WELL_DEPTH + 0.1, -LEAF_HALF_Z), m["bay_light"]),
        block((-LEAF_OUT, -WELL_DEPTH, LEAF_HALF_Z), (LEAF_OUT, -WELL_DEPTH + 0.1, DOOR_Z), m["bay_light"]),
        block((-0.2, -WELL_DEPTH, -LEAF_HALF_Z), (0.2, -WELL_DEPTH + 0.1, LEAF_HALF_Z), m["bay_light"]),
    ])
    latches = Mesh.concatenate(mirror_x(block((DOOR_X - 0.2, 0.25, z - 1.2), (DOOR_X + 0.7, 0.85, z + 1.2), m["trim"]))
                               for z in (-9.0, 9.0))
    return [Shape("deck", deck, ((m["hatch"].albedo, walk_line),)), Shape("coaming", coaming, ((DARK, stripes()),)),
            Shape("well", well), Shape("door_glow", glow), Shape("latches", latches)]


def _leaves(m: Mapping[str, Material]) -> list[Shape]:
    # Seen from inside the leaves are bare structure: grey plating with the door's red-brown on the slats.
    leaf = [block((LEAF_IN, LEAF_TOP - 0.35, -LEAF_HALF_Z), (LEAF_OUT, LEAF_TOP, LEAF_HALF_Z), m["deck"])]
    pitch = 2.0 * LEAF_HALF_Z / SLATS
    leaf += [block((LEAF_IN + 0.3, LEAF_TOP, -LEAF_HALF_Z + k * pitch - 0.15), (LEAF_OUT - 0.3, LEAF_TOP + 0.15,
                   -LEAF_HALF_Z + k * pitch + 0.15), m["door"]) for k in range(1, SLATS)]
    hinge = pipe("z", (LEAF_OUT - 0.4, LEAF_TOP + 0.1), (-LEAF_HALF_Z + 0.5, LEAF_HALF_Z - 0.5), 0.4, m["machinery"])
    # The rams that swing each leaf down: a cylinder and its rod from the well's side to the leaf.
    rams = Mesh.concatenate(block((LEAF_OUT - 3.0, LEAF_TOP, z - 0.35), (LEAF_OUT - 0.6, LEAF_TOP + 0.5, z + 0.35), m["machinery"])
                            for z in (-7.0, 7.0))
    seam = block((-LEAF_IN, LEAF_TOP - 0.2, -LEAF_HALF_Z), (LEAF_IN, LEAF_TOP - 0.05, LEAF_HALF_Z), m["hatch"])
    # A hazard band down the seam where the leaves meet, as the leaves' faces show outside.
    def seam_band(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        return (np.abs(p[:, 0]) < LEAF_IN + 1.6).astype(float) * (n[:, 1] > 0.5)

    def seam_dark(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        return seam_band(p, n) * stripes(1.6)(p, n)

    return [Shape("leaves", mirror_x(Mesh.concatenate(leaf + [hinge, rams])), ((m["hatch"].albedo, seam_band), (DARK, seam_dark))),
            Shape("seam", seam, ((DARK, stripes(1.6)),))]


def _wall_side(m: Mapping[str, Material]) -> dict[str, list[Mesh]]:
    """One side wall (+x) and what stands on it, by part."""
    h, w = HALF_PITCH, HALF_W
    out: dict[str, list[Mesh]] = {k: [] for k in ("wall", "cabinets", "panels", "canisters", "ladder", "catwalk", "railing", "pipes",
                                                  "wall_lamps", "wall_glow", "pilasters")}
    out["wall"].append(block((w, 0.0, -h), (w + 1.0, HEIGHT, h), m["wall"]))
    # The machinery bank along the floor: cabinets of different depths with pink-lit panels (the docking-bay captures).
    for z0, z1, depth, top, lit in ((-17.5, -11.0, 1.6, 6.5, ((3.5, 5.5),)), (-7.8, -2.2, 2.4, 4.2, ((2.4, 3.4),)),
                                     (6.8, 13.2, 1.8, 8.0, ((2.2, 3.4), (5.2, 6.6)))):
        out["cabinets"].append(block((w - depth, 0.0, z0), (w, top, z1), m["wall"]))
        out["cabinets"].append(block((w - depth - 0.25, top - 0.4, z0 - 0.2), (w, top, z1 + 0.2), m["frame"]))  # a lip on top
        for y0, y1 in lit:
            out["panels"].append(block((w - depth - 0.03, y0, z0 + 0.8), (w - depth, y1, z1 - 0.8), m["panel_light"]))
    # Orange canisters with yellow and dark bands (the show's striped canisters at the side).
    for z in (0.6, 2.7, 4.8):
        out["canisters"].append(pipe("y", (w - 1.3, z), (0.0, 3.4), 0.9, m["canister"], 16))
    # Vertical pipes up to the catwalk, and a ladder (the fan render's ladders).
    out["pipes"] += [pipe("y", (w - 0.5, z), (0.0, 11.8), 0.22, m["machinery"]) for z in (-10.2, -9.5)]
    lz = 16.0
    out["ladder"] += [block((w - 0.8, 0.0, lz + s - 0.05), (w - 0.7, 13.0, lz + s + 0.05), m["hatch"]) for s in (-0.3, 0.3)]
    out["ladder"] += [block((w - 0.8, y - 0.03, lz - 0.3), (w - 0.7, y + 0.03, lz + 0.3), m["hatch"])
                      for y in np.arange(0.4, 12.0, 0.4)]
    out["ladder"] += [block((w - 0.7, y - 0.05, lz - 0.35), (w, y + 0.05, lz - 0.25), m["hatch"]) for y in (2.0, 6.0, 10.0)]
    # The catwalk at 12 m, its brackets and its yellow railing.
    out["catwalk"].append(block((w - 3.0, 11.8, -h), (w, 12.0, h), m["deck"]))
    out["catwalk"] += [block((w - 3.0, 10.9, z - 0.08), (w, 11.8, z + 0.08), m["frame"]) for z in (-h + 3.2, -6.4, 6.4, h - 3.2)]
    out["railing"] += [block((w - 3.0, 12.0, z - 0.05), (w - 2.9, 13.1, z + 0.05), m["hatch"])
                       for z in np.arange(-h + 1.6, h, 3.2) if abs(z - lz) > 1.0]
    out["railing"] += [block((w - 3.0, y - 0.05, -h), (w - 2.9, y + 0.05, h), m["hatch"]) for y in (12.55, 13.1)]
    # The red lamps under the catwalk and the bay's warm light along the wall.
    out["wall_lamps"] += [block((w - 0.45, 10.2, z - 0.5), (w, 10.6, z + 0.5), m["lamp"]) for z in (-12.0, 0.0, 12.0)]
    out["wall_glow"].append(block((w - 0.25, 10.85, -h + 1.0), (w, 11.0, h - 1.0), m["bay_light"]))
    # Pipe runs along the hall above the catwalk, on brackets.
    for x, y, r, role in ((w - 0.55, 14.0, 0.35, "machinery"), (w - 0.55, 14.9, 0.35, "machinery"), (w - 0.8, 16.15, 0.55, "trim"),
                          (w - 0.45, 17.4, 0.25, "machinery")):
        out["pipes"].append(pipe("z", (x, y), (-h, h), r, m[role]))
    out["pipes"] += [block((w - 1.45, 13.4, z - 0.15), (w, 17.8, z + 0.15), m["frame"]) for z in (-12.0, 0.0, 12.0)]
    # The upper wall: pilasters and recessed vents.
    out["pilasters"] += [block((w - 0.6, 18.0, z - 0.4), (w, HEIGHT, z + 0.4), m["frame"]) for z in (-12.0, 12.0)]
    out["pilasters"] += [block((w - 0.12, 18.6, z0), (w, 19.4, z1), m["recess"]) for z0, z1 in ((-18.0, -13.0), (13.0, 18.0))]
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
            def bands(p: np.ndarray, _n: np.ndarray) -> np.ndarray:  # yellow bands at the top and bottom of each canister
                y = p[:, 1]
                return (((y > 0.4) & (y < 0.9)) | ((y > 2.5) & (y < 3.0))).astype(float)

            def dark(p: np.ndarray, n: np.ndarray) -> np.ndarray:
                return bands(p, n) * (np.mod(p[:, 1] * 4.0 + np.arctan2(p[:, 2], p[:, 0]) * 2.0, 2.0) < 1.0)

            paint = ((m["hatch"].albedo, bands), (DARK, dark))
        shapes.append(Shape(name, mesh, paint))
    return shapes


def _portal(m: Mapping[str, Material]) -> list[Shape]:
    """The red frame round each launch position at its two ends (half a frame at each, the next position's half meets it): the
    fan render's red bay portals with cut corners, and a striped sill across the floor."""
    parts, gussets = [], []
    for sz in (-1.0, 1.0):
        z = (sz * HALF_PITCH - sz * 0.7, sz * HALF_PITCH) if sz > 0 else (-HALF_PITCH, -HALF_PITCH + 0.7)
        z = (min(z), max(z))
        parts.append(mirror_x(block((HALF_W - 1.6, 0.0, z[0]), (HALF_W, HEIGHT, z[1]), m["trim"])))
        parts.append(block((-HALF_W, HEIGHT - 1.6, z[0]), (HALF_W, HEIGHT, z[1]), m["trim"]))
        gussets.append(mirror_x(gusset((HALF_W - 1.6, HEIGHT - 1.6), -3.0, -3.0, z, m["trim"])))
        gussets.append(mirror_x(gusset((HALF_W - 1.6, 0.3), -2.0, 2.0, z, m["trim"])))
    sill = Mesh.concatenate([block((-HALF_W + 1.6, 0.0, -HALF_PITCH), (HALF_W - 1.6, 0.3, -HALF_PITCH + 0.7), m["hatch"]),
                             block((-HALF_W + 1.6, 0.0, HALF_PITCH - 0.7), (HALF_W - 1.6, 0.3, HALF_PITCH), m["hatch"])])
    return [Shape("portal", Mesh.concatenate(parts + gussets)), Shape("sill", sill, ((DARK, stripes()),))]


def _ceiling(m: Mapping[str, Material]) -> list[Shape]:
    h = HALF_PITCH
    ceiling = [block((-HALF_W, HEIGHT, -h), (HALF_W, HEIGHT + 1.0, h), m["recess"])]
    beams = [mirror_x(block((x - 0.4, HEIGHT - 1.2, -h), (x + 0.4, HEIGHT, h), m["frame"])) for x in (18.0,)]
    beams += [mirror_x(block((x - 0.8, HEIGHT - 0.25, -h), (x + 0.8, HEIGHT - 0.1, h), m["frame"])) for x in (9.0, 27.0)]  # cable trays
    beams += [block((-HALF_W, HEIGHT - 0.8, z - 0.3), (HALF_W, HEIGHT, z + 0.3), m["frame"]) for z in (-h * 0.5, h * 0.5)]
    floods = [mirror_x(block((x - 1.2, HEIGHT - 0.9, z - 0.6), (x + 1.2, HEIGHT - 0.8, z + 0.6), m["work_light"]))
              for x in (12.0,) for z in (-h * 0.5, h * 0.5)]
    housings = [mirror_x(block((x - 1.4, HEIGHT - 0.8, z - 0.8), (x + 1.4, HEIGHT - 0.2, z + 0.8), m["frame"]))
                for x in (12.0,) for z in (-h * 0.5, h * 0.5)]
    return [Shape("ceiling", Mesh.concatenate(ceiling)), Shape("beams", Mesh.concatenate(beams + housings)),
            Shape("floods", Mesh.concatenate(floods))]


def _gantry(m: Mapping[str, Material]) -> list[Shape]:
    """The crane over the door: columns, the rails along the hall, the bridge across it and, under it, a clamp for each of the
    three fighters holding it by its back and its upper pods (the show's overhead clamps; the fan render's red and white cranes)."""
    h = HALF_PITCH
    c0, c1 = COLUMN_X
    columns = mirror_x(block((c0, 0.0, -1.5), (c1, RAIL_Y[0], 1.5), m["frame"]))
    rails = mirror_x(Mesh.concatenate([block((c0 + 0.5, RAIL_Y[0], -h), (c1 - 0.5, RAIL_Y[1], h), m["machinery"]),
                                       block((c0, RAIL_Y[0] - 0.3, -h), (c1, RAIL_Y[0], h), m["frame"])]))
    bridge = Mesh.concatenate([block((-c1, BRIDGE_Y[0], -BRIDGE_HALF_Z), (c1, BRIDGE_Y[1], BRIDGE_HALF_Z), m["frame"]),
                               mirror_x(block((c0 - 0.5, BRIDGE_Y[0], -2.6), (c1 + 0.5, BRIDGE_Y[0] + 1.6, 2.6), m["trim"]))])
    lamp_x, lamp_y = WORK_LAMP
    lamps = mirror_x(Mesh.concatenate([block((lamp_x + 0.05, lamp_y - 0.8, -0.7), (c0, lamp_y + 0.8, 0.7), m["frame"]),
                                       block((lamp_x, lamp_y - 0.6, -0.5), (lamp_x + 0.05, lamp_y + 0.6, 0.5), m["work_light"])]))
    # A yellow lattice up each column's inner face (the fan render's braced columns), and hoses hanging from the bridge to the
    # trolley and the clamp.
    lattice = []
    for k in range(9):
        y0, y1 = 1.8 + 2.4 * k, 1.8 + 2.4 * (k + 1)
        za, zb = (-1.2, 1.2) if k % 2 else (1.2, -1.2)
        lattice.append(bar((c0 - 0.15, y0, za), (c0 - 0.15, y1, zb), 0.16, m["hatch"]))
    lattice += [block((c0 - 0.3, 1.6, -1.4), (c0, 1.8, 1.4), m["hatch"]), block((c0 - 0.3, 23.4, -1.4), (c0, 23.6, 1.4), m["hatch"])]
    lattice = [mirror_x(Mesh.concatenate(lattice))]
    red = mirror_x(block((c0 - 0.35, 12.0, -0.4), (c0, 12.6, 0.4), m["lamp"]))
    bx, by = BRIDGE_LAMP
    lamps = Mesh.concatenate([lamps, mirror_x(block((bx - 1.0, by - 0.4, -1.2), (bx + 1.0, BRIDGE_Y[0], 1.2), m["frame"])),
                              mirror_x(block((bx - 0.8, by - 0.45, -1.0), (bx + 0.8, by - 0.4, 1.0), m["work_light"]))])
    beacons = Mesh.concatenate([mirror_x(block((c0 + 1.0, RAIL_Y[0] - 1.2, 1.5), (c1 - 1.0, RAIL_Y[0] - 0.6, 1.8), m["lamp"])),
                                mirror_x(block((9.5, BRIDGE_Y[1], -0.3), (10.5, BRIDGE_Y[1] + 0.4, 0.3), m["lamp"]))])

    def column_band(p: np.ndarray, n: np.ndarray) -> np.ndarray:  # hazard stripes round each column's foot
        return (p[:, 1] < 1.6).astype(float)

    def column_dark(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        return column_band(p, n) * stripes(1.0, (0.0, 1.0, 1.0))(p, n)

    clamp = _clamp(m)
    held = {name: Mesh.concatenate(mesh.translated((x, 0.0, 0.0)) for x in SLOT_X) for name, mesh in clamp.items()}
    return [Shape("columns", columns, ((m["hatch"].albedo, column_band), (DARK, column_dark))), Shape("rails", rails),
            Shape("bridge", bridge), Shape("drop_arm", held["drop_arm"]), Shape("clamp_arms", held["clamp_arms"]),
            Shape("pads", held["pads"]), Shape("work_lamps", lamps),
            Shape("beacons", Mesh.concatenate([beacons, red, held["red"]])), Shape("lattice", Mesh.concatenate(lattice)),
            Shape("hoses", held["hoses"])]


def _clamp(m: Mapping[str, Material]) -> dict[str, Mesh]:
    """One fighter's clamp, hung from the bridge over x = 0: the trolley, the drop arm, the yoke on the fuselage's back, the arms
    out to the upper pods, the pads, its hoses and red lamps."""
    pz0, pz1 = PAD_Z
    cz = 0.5 * (pz0 + pz1)
    pad_y = HANG_Y + FURY_TOP_Y
    px, pod_top, pod_z = FURY_POD
    pod_y = HANG_Y + pod_top
    arm = Mesh.concatenate([
        block((-2.2, 23.4, cz - 2.2), (2.2, BRIDGE_Y[0], cz + 2.2), m["trim"]),  # the trolley
        block((-0.8, 16.0, cz - 0.8), (0.8, 23.4, cz + 0.8), m["frame"]),  # the drop arm's sleeve
        block((-0.55, pad_y + 0.6, cz - 0.55), (0.55, 16.0, cz + 0.55), m["machinery"]),  # its ram
        block((-0.6, pad_y + 0.12, pz0), (0.6, pad_y + 0.6, pz1), m["frame"]),  # the yoke over the fuselage's back
        block((-0.4, pod_y + 0.8, cz - 0.4), (0.4, pod_y + 1.4, pod_z + 0.5), m["frame"]),  # the spine out to the pod clamps
    ])
    clamp_arms = Mesh.concatenate([
        block((-px - 0.8, pod_y + 0.8, pod_z - 0.5), (px + 0.8, pod_y + 1.4, pod_z + 0.5), m["trim"]),  # across, over the pods
        mirror_x(block((px - 0.3, pod_y + 0.06, pod_z - 0.3), (px + 0.3, pod_y + 0.8, pod_z + 0.3), m["frame"])),  # the links down
    ])
    pads = Mesh.concatenate([block((-0.55, pad_y + 0.01, pz0 + 0.1), (0.55, pad_y + 0.12, pz1 - 0.1), m["rubber"]),
                             mirror_x(block((px - 0.3, pod_y + 0.01, pod_z - 0.3), (px + 0.3, pod_y + 0.06, pod_z + 0.3), m["rubber"]))])
    hoses = Mesh.concatenate([bar((2.4, BRIDGE_Y[0], cz + 1.0), (0.9, pad_y + 3.5, cz + 0.6), 0.22, m["rubber"]),
                              bar((-2.4, BRIDGE_Y[0], cz - 1.2), (-0.9, 17.0, cz - 0.9), 0.3, m["rubber"]),
                              bar((0.9, pad_y + 3.5, cz + 0.6), (0.5, pad_y + 0.7, cz + 0.3), 0.18, m["rubber"])])
    red = Mesh.concatenate([mirror_x(block((2.2, 24.0, cz - 0.4), (2.5, 24.6, cz + 0.4), m["lamp"])),
                            mirror_x(block((px + 0.8, pod_y + 0.9, pod_z - 0.3), (px + 1.1, pod_y + 1.3, pod_z + 0.3), m["lamp"]))])
    return {"drop_arm": arm, "clamp_arms": clamp_arms, "pads": pads, "hoses": hoses, "red": red}


def hide_backs(shapes: list[Shape], half_z: float) -> list[Shape]:
    """The shapes less the faces nobody in the hall can see (the slabs' backs and the faces lying on the floor, the walls or the
    ceiling, or on the box's ends at +-``half_z``), so the atlas spends no texels on them."""
    eps = 1e-3
    out = []
    for shape in shapes:
        mesh = shape.mesh
        n, c = mesh.face_normals(), mesh.face_centroids()
        over_well = (np.abs(c[:, 0]) < DOOR_X + COAMING_M - eps) & (np.abs(c[:, 2]) < DOOR_Z + COAMING_M - eps)
        hidden = ((n[:, 1] < -0.9) & (c[:, 1] < -0.59)) | ((n[:, 1] < -0.9) & (np.abs(c[:, 1]) < eps) & ~over_well)
        hidden |= (n[:, 1] > 0.9) & (c[:, 1] > HEIGHT - eps)
        hidden |= (n[:, 0] * np.sign(c[:, 0]) > 0.9) & (np.abs(c[:, 0]) > HALF_W - eps)
        hidden |= (n[:, 2] * np.sign(c[:, 2]) > 0.9) & (np.abs(c[:, 2]) > half_z - eps)
        out.append(Shape(shape.name, mesh.face_subset(~hidden), shape.paint))
    return [s for s in out if s.mesh.face_count > 0]


def slice_shapes(m: Mapping[str, Material]) -> list[Shape]:
    """One launch position, its door at the origin: the floor and its door, the walls, the portal, the ceiling and the crane."""
    return hide_backs(_deck(m) + _leaves(m) + _walls(m) + _portal(m) + _ceiling(m) + _gantry(m), HALF_PITCH)


# --- the two end walls ----------------------------------------------------------------------------------------------------
def _end_wall(m: Mapping[str, Material], sz: float) -> list[Shape]:
    """The wall at ``sz * END_Z`` facing into the hall: a big pressure door with toothed leaves (the docking bay's inner airlock),
    hazard bands round it, machinery either side and a lit launch-control booth above it."""
    z_face = sz * END_Z
    thick = (z_face, z_face + sz * 1.5)
    zs = (min(thick), max(thick))
    tag = "head" if sz < 0 else "root"
    inward = -sz  # +z for the head wall
    def zin(depth: float) -> tuple[float, float]:  # a slab from the wall's face ``depth`` into the hall
        a, b = z_face, z_face + inward * depth
        return (min(a, b), max(a, b))

    wall = [block((-HALF_W, 0.0, zs[0]), (HALF_W, HEIGHT + 1.0, zs[1]), m["wall"])]
    dw, dh = 14.0, 16.0
    frame = [block((-dw - 2.0, 0.0, zin(0.8)[0]), (-dw, dh + 2.0, zin(0.8)[1]), m["frame"]),
             block((dw, 0.0, zin(0.8)[0]), (dw + 2.0, dh + 2.0, zin(0.8)[1]), m["frame"]),
             block((-dw - 2.0, dh, zin(0.8)[0]), (dw + 2.0, dh + 2.0, zin(0.8)[1]), m["frame"])]
    # The leaves meet along a sawtooth: each tooth belongs to the left or right leaf in turn.
    leaves = [block((-dw, 0.0, zin(0.3)[0]), (-1.0, dh, zin(0.3)[1]), m["door"]), block((1.0, 0.0, zin(0.3)[0]), (dw, dh, zin(0.3)[1]), m["door"])]
    for k in range(10):
        y0, y1 = k * dh / 10.0, (k + 1) * dh / 10.0
        leaves.append(block((-1.0, y0, zin(0.3)[0]), (1.0, y1, zin(0.3)[1]), m["door"] if k % 2 else m["frame"]))
    band = [block((-dw - 3.2, 0.0, zin(0.4)[0]), (-dw - 2.0, dh + 3.2, zin(0.4)[1]), m["hatch"]),
            block((dw + 2.0, 0.0, zin(0.4)[0]), (dw + 3.2, dh + 3.2, zin(0.4)[1]), m["hatch"]),
            block((-dw - 2.0, dh + 2.0, zin(0.4)[0]), (dw + 2.0, dh + 3.2, zin(0.4)[1]), m["hatch"])]
    booth = [block((-11.0, 20.0, zin(2.5)[0]), (11.0, 25.0, zin(2.5)[1]), m["frame"])]
    glass = [block((-10.0, 21.0, zin(2.55)[0]), (10.0, 23.8, zin(2.55)[1]), m["recess"])]
    machinery = []
    for sx in (-1.0, 1.0):
        for x0, x1, top, depth in ((19.0, 25.0, 9.0, 2.0), (27.0, 31.0, 14.0, 1.4), (33.0, 39.0, 6.0, 2.6)):
            a, b = sorted((sx * x0, sx * x1))
            machinery.append(block((a, 0.0, zin(depth)[0]), (b, top, zin(depth)[1]), m["wall"]))
            machinery.append(block((a + 0.6, top * 0.45, zin(depth + 0.03)[0]), (b - 0.6, top * 0.45 + 1.2, zin(depth + 0.03)[1]),
                                   m["panel_light"]))
    lamps = [block((x - 0.5, dh + 3.4, zin(0.6)[0]), (x + 0.5, dh + 3.9, zin(0.6)[1]), m["lamp"]) for x in (-8.0, 0.0, 8.0)]

    def band_dark(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        return stripes(1.6, (1.0, 1.0, 0.0))(p, n)

    return [Shape(f"{tag}_wall", Mesh.concatenate(wall)), Shape(f"{tag}_door_frame", Mesh.concatenate(frame)),
            Shape(f"{tag}_leaves", Mesh.concatenate(leaves)), Shape(f"{tag}_band", Mesh.concatenate(band), ((DARK, band_dark),)),
            Shape(f"{tag}_booth", Mesh.concatenate(booth)), Shape(f"{tag}_glass", Mesh.concatenate(glass)),
            Shape(f"{tag}_machinery", Mesh.concatenate(machinery)), Shape(f"{tag}_lamps", Mesh.concatenate(lamps))]


def booth_windows(tag: str) -> dict[str, object]:
    """Where the launch-control booth's lit windows are on the ``<tag>_glass`` part: centre, facing, size."""
    sz = -1.0 if tag == "head" else 1.0
    z = sz * END_Z - sz * 2.55
    return {"centre": (0.0, 22.4, z), "facing": (0.0, 0.0, -sz), "size": (20.0, 2.8)}


def end_shapes(m: Mapping[str, Material]) -> list[Shape]:
    """Both end walls, in the hall frame."""
    return hide_backs([s for sz in (-1.0, 1.0) for s in _end_wall(m, sz) if s.mesh.face_count > 0], END_Z)


# --- the bay numbers --------------------------------------------------------------------------------------------------------
NUMBER_PANEL = (4.2, 18.4, 23.8)  # half length along the wall, bottom, top
NUMBER_RED = (0.42, 0.045, 0.035)  # the fan render's red stencil, linear
PLATE = (3.0, 25.45, 26.95)  # the bridge's plate: half width, bottom, top
PLATE_WHITE = (0.62, 0.62, 0.6)


def sign_shapes(m: Mapping[str, Material]) -> list[Shape]:
    """The big red bay numbers on both walls above the pipes, and a plate on each crane's bridge, in the hall frame. The numbers
    themselves are text markings laid by the asset (``b5_interior.sign_parts``)."""
    shapes = []
    for k, z in enumerate(bay_centres(), start=1):
        half, y0, y1 = NUMBER_PANEL
        shapes.append(Shape(f"number_panels_{k}", mirror_x(block((HALF_W - 0.3, y0, z - half), (HALF_W - 0.02, y1, z + half), m["wall"]))))
        pw, py0, py1 = PLATE
        # A part per bay, so each plate's number paints its own plate only.
        shapes.append(Shape(f"bridge_plates_{k}", Mesh.concatenate([
            block((-pw, py0, z - BRIDGE_HALF_Z - 0.1), (pw, py1, z - BRIDGE_HALF_Z), m["frame"]),
            block((-pw, py0, z + BRIDGE_HALF_Z), (pw, py1, z + BRIDGE_HALF_Z + 0.1), m["frame"])])))
    return hide_backs(shapes, END_Z)


def number_text(k: int) -> tuple[str, str]:
    """Bay ``k``'s number (from 1) as the wall shows it and as the bridge's plate shows it."""
    return str(k), f"{k:02d}"


__all__ = ["BAYS", "BRIDGE_LAMP", "RELEASE_Y", "SLOT_X", "CAMERA_RAIL", "END_Z", "HALF_PITCH", "HALF_W", "HANG_Y", "HEIGHT", "PITCH_M", "Shape", "bay_centres", "booth_windows", "end_shapes",
           "number_text", "sign_shapes", "slice_shapes", "to_arm"]
