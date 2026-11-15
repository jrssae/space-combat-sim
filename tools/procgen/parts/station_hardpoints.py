"""The station's hardpoints (M7-T05, D72): where the game launches fighters, sends traffic in, mounts the defence grid, hangs its
lights, points the tour's camera and counts damage. Data only, from the shapes' own numbers (``station.py``, ``station_detail.py``)
and D75's approved mount table; written into the manifest's ``hardpoints``.

Everything is built in the station frame (metres, x to starboard, y up, z aft from the bow tip) and written in the frame of the
piece that carries it (``body``): the drum's frame (on its axis at the drum's centre; it turns, so a drum hardpoint turns with it)
or the frame's (the asset's frame). Neither flips an axis: the game's -Z is the bow, as the station frame's low z.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from . import station as st
from . import station_detail as sd
from . import station_props as sp

DRUM, FRAME = "drum", "frame"
LIGHT, HEAVY, INTERCEPTOR = "light_pulse", "heavy_cannon", "interceptor"
# D75's mounts as the maintainer approved them on the marker sheet (2026-11-13): name, kind, body, position, up (station frame).
# The drum's are at the arms' angles as modelled. L1 to L8 sit on the side facets of each Cobra arm's forward head, where it reaches the
# docking sphere, flush on the skin, facing out and about 17 degrees toward the bow (M7-T24: the fork's posts they stood on were neither in
# the references nor the STL as built; half the facet's own tilt, so they still cover the raids that form over the spine).
GRID_MOUNTS: tuple[tuple[str, str, str, tuple[float, float, float], tuple[float, float, float]], ...] = (
    ("L1", LIGHT, DRUM, (-40.4, 300.8, 745.5), (-0.451, 0.846, -0.283)),
    ("L2", LIGHT, DRUM, (40.4, 300.8, 745.5), (0.451, 0.846, -0.283)),
    ("L3", LIGHT, DRUM, (300.8, 40.4, 745.5), (0.846, 0.451, -0.283)),
    ("L4", LIGHT, DRUM, (300.8, -40.4, 745.5), (0.846, -0.451, -0.283)),
    ("L5", LIGHT, DRUM, (40.4, -300.8, 745.5), (0.451, -0.846, -0.283)),
    ("L6", LIGHT, DRUM, (-40.4, -300.8, 745.5), (-0.451, -0.846, -0.283)),
    ("L7", LIGHT, DRUM, (-300.8, -40.4, 745.5), (-0.846, -0.451, -0.283)),
    ("L8", LIGHT, DRUM, (-300.8, 40.4, 745.5), (-0.846, 0.451, -0.283)),
    ("L9", LIGHT, FRAME, (0.0, 507.0, 1500.0), (0.0, 0.98, -0.21)),
    ("L10", LIGHT, FRAME, (0.0, 537.0, 2650.0), (0.0, 1.0, 0.0)),
    ("L11", LIGHT, FRAME, (0.0, 537.0, 4500.0), (0.0, 1.0, 0.0)),
    ("L12", LIGHT, FRAME, (0.0, 472.0, 5650.0), (0.0, 1.0, 0.0)),
    ("H1", HEAVY, FRAME, (-45.0, 375.0, 515.0), (0.0, 0.99, -0.13)),
    ("H2", HEAVY, FRAME, (45.0, 375.0, 515.0), (0.0, 0.99, -0.13)),
    ("I1", INTERCEPTOR, DRUM, (0.0, 324.0, 800.0), (0.0, 1.0, 0.0)),
    ("I2", INTERCEPTOR, DRUM, (324.0, 0.0, 800.0), (1.0, 0.0, 0.0)),
    ("I3", INTERCEPTOR, DRUM, (0.0, -324.0, 800.0), (0.0, -1.0, 0.0)),
    ("I4", INTERCEPTOR, DRUM, (-324.0, 0.0, 800.0), (-1.0, 0.0, 0.0)),
    ("I5", INTERCEPTOR, FRAME, (0.0, 438.0, 520.0), (0.0, 1.0, -0.02)),
    ("I6", INTERCEPTOR, FRAME, (40.0, 459.0, 1500.0), (0.0, 1.0, -0.05)),
    ("I7", INTERCEPTOR, FRAME, (-40.0, 537.0, 2650.0), (0.0, 1.0, 0.0)),
    ("I8", INTERCEPTOR, FRAME, (40.0, 537.0, 4500.0), (0.0, 1.0, 0.0)),
    ("I9", INTERCEPTOR, FRAME, (-40.0, 472.0, 5650.0), (0.0, 1.0, 0.0)),
)
ARM_NAMES = ("top", "starboard", "bottom", "port")  # st.ARM_ANGLES_DEG in order
# Each arm's wing (the maintainer, 2026-11-13), seen from the bow: Alpha top (0 degrees), Beta starboard (90), Delta bottom (180),
# Zeta port (270).
WINGS = ("alpha", "beta", "delta", "zeta")
BOW_VIEW_DEG = (0.0, 90.0, 180.0, 270.0)
# Kept for M7-T20's hangar, which reads it: the second row no longer lifts to cross over (M7-T21: it waits lower, crosses under its
# rack and rises straight onto it; ``cobra_arm`` gives ``staging_r`` and each bay its ``staging_path``).
STAGING_LIFT_M = 0.0
APPROACH_M = (1500.0, 300.0)  # the docking approach's far and near points, ahead of the mouth along the axis
DRUM_SPIN_RAD_S = 0.148  # the generator's spin (babylon5_station.DRUM_SPIN_RAD_S, Q9)

WHITE, RED, GREEN, PINK, AMBER = "#FFF4E0", "#FF2A1A", "#30FF60", "#FF6A8A", "#FFA860"


@dataclass(frozen=True)
class Frames:
    """Where each piece's origin sits in the station frame."""

    drum: np.ndarray
    frame: np.ndarray

    def to(self, body: str, p: Sequence[float]) -> list[float]:
        shift = self.drum if body == DRUM else self.frame
        return _r(np.asarray(p, dtype=float) - shift)


def _r(v: Sequence[float]) -> list[float]:
    return [round(float(c), 4) for c in v]


def _arm_turn(angle_deg: float) -> np.ndarray:
    """The turn that carries an arm built on top (+y) to its angle round the axis."""
    a = math.radians(angle_deg - 90.0)
    return np.array([[math.cos(a), -math.sin(a), 0.0], [math.sin(a), math.cos(a), 0.0], [0.0, 0.0, 1.0]])


def surface_velocity(p: Sequence[float]) -> list[float]:
    """The drum's surface velocity at ``p`` (drum frame, the axis +z): the spin's ``w x r``, constant in the turning frame."""
    return _r(DRUM_SPIN_RAD_S * np.cross([0.0, 0.0, 1.0], [p[0], p[1], 0.0]))


def cobra_bays(f: Frames) -> list[dict]:
    """The 24 launch doors, four arms of six, named by the arm's wing and the door from the bow: ``cobra_bay_alpha_1`` to ``_6`` on
    the top arm, then Beta (starboard), Delta (bottom) and Zeta (port). Each: the door (its middle on the doors' plane, outward
    normal, half size: 20 m across the arm, 14 m along it, one Starfury), its two leaves' hinges (outer edges, along the arm), the
    fighter racked over it in the launch hall (the rail from where it hangs to the door, the release point past the door, the
    drop's direction, radially out, the drum's surface velocity there, Q3: released with it, and its pose: nose to the bow, its back
    to the drum's axis, span across the arm), and the second row's staging point in the lower hall with the path onto the rack (the
    second wave: across under the rack, then out onto it)."""
    floor = st.ARM_HATCH[4] - st.DOOR_DEPTH
    cx = st.LAUNCH_STRIP_X
    out = []
    for arm, (name, angle) in enumerate(zip(ARM_NAMES, st.ARM_ANGLES_DEG, strict=True)):
        turn = _arm_turn(angle)
        radial = turn @ np.array([0.0, 1.0, 0.0])
        wing = WINGS[arm]
        for door, z in enumerate(st.launch_door_centres()):
            hang = turn @ np.array([cx, floor - sp.HANG_DEPTH_M, z])
            stage = np.array([cx + st.STAGING_OFFSET_X, st.STAGING_R, z])
            # Across the lower hall under the rack, then straight out onto it between the rack's clamp arms.
            staging_path = [stage, np.array([cx, st.STAGING_R, z]), np.array([cx, floor - sp.HANG_DEPTH_M, z])]
            release = turn @ np.array([cx, floor + sp.RELEASE_M, z])
            hinges = [{"leaf": side, "point": f.to(DRUM, turn @ np.array([cx + sx * sp.LEAF[1], floor, z])), "axis": [0.0, 0.0, 1.0]}
                      for side, sx in (("r", 1.0), ("l", -1.0))]
            out.append({
                "name": f"cobra_bay_{wing}_{door + 1}",
                "wing": wing,
                "arm": name,
                "door_number": door + 1,
                "body": DRUM,
                "door": f.to(DRUM, turn @ np.array([cx, floor, z])),
                "door_half_m": [st.LAUNCH_DOOR_HALF[0], st.LAUNCH_DOOR_HALF[1]],
                "normal": _r(radial),
                "across": _r(turn @ np.array([1.0, 0.0, 0.0])),
                "leaves": hinges,
                "rail_start": f.to(DRUM, hang),
                "rail_end": f.to(DRUM, turn @ np.array([cx, floor, z])),
                "release": f.to(DRUM, release),
                "release_direction": _r(radial),
                "surface_velocity": surface_velocity(release),
                "forward": [0.0, 0.0, -1.0],
                "up": _r(-radial),
                "staging": f.to(DRUM, turn @ stage),
                "staging_path": [f.to(DRUM, turn @ p) for p in staging_path],
            })
    return out


CLEAR_DISTANCE_M = 240.0  # the frame's farthest part over the door strip (the dome's lamp on the beam, r 471) is 234 m out
CLEAR_MARGIN_DEG = 10.0  # 1.2 s of the drum's turn: the drop from the rack through the release point, while the arm keeps turning
SHIP_CLEARANCE_M = 2.0  # how close the dropping fighter's box may pass the frame
FURY_HALF = (7.7, 4.9)  # a Starfury's half span (across the arm) and half length (along it)


def launch_clearance(step_deg: float = 0.5) -> dict:
    """Where a launch must wait (M7-T08's rule: a Starfury does not launch while its arm points at the stationary frame). The arm
    angles, about the drum's axis in the frame's coordinates, at which a Starfury's box dropping radially out of any of the arm's six
    doors would come within ``SHIP_CLEARANCE_M`` of the frame (its collision shapes) within ``CLEAR_DISTANCE_M``: the drop is clear
    beyond that, since nothing of the frame lies farther out over the door strip. Once for the strip (the six doors together),
    widened by ``CLEAR_MARGIN_DEG`` each side."""
    from ..core import collision as col  # noqa: PLC0415
    from . import station_collision as sc  # noqa: PLC0415

    z_lo = st.LAUNCH_ROW[0] - FURY_HALF[1] - SHIP_CLEARANCE_M
    z_hi = st.LAUNCH_ROW[1] + FURY_HALF[1] + SHIP_CLEARANCE_M
    shapes = []
    for name, pts in sc.frame_pieces(()):
        pts = np.asarray(pts, dtype=float)
        if pts[:, 2].max() >= z_lo and pts[:, 2].min() <= z_hi:
            shapes.append(col.hull(name, pts, col.Budget().max_hull_points))
    floor = st.ARM_HATCH[4] - st.DOOR_DEPTH
    t = np.arange(0.0, CLEAR_DISTANCE_M + 1e-6, 4.0)
    across = np.array([-FURY_HALF[0], 0.0, FURY_HALF[0]])
    zs = np.array([z + d for z in st.launch_door_centres() for d in (-FURY_HALF[1], FURY_HALF[1])])
    angles = np.arange(0.0, 360.0, step_deg)
    blocked = np.zeros(len(angles), dtype=bool)
    for k, a in enumerate(angles):
        th = math.radians(a)
        n = np.array([math.cos(th), math.sin(th)])
        tangent = np.array([math.sin(th), -math.cos(th)])  # the arm's own +x (built on top, turned by its angle less 90)
        base = st.LAUNCH_STRIP_X * tangent + floor * n
        xy = base[None, None, :] + t[:, None, None] * n[None, None, :] + across[None, :, None] * tangent[None, None, :]
        xy = xy.reshape(-1, 2)
        pts = np.concatenate([np.column_stack([xy, np.full(len(xy), z)]) for z in zs])
        blocked[k] = any(float(sh.distance(pts).min()) < SHIP_CLEARANCE_M for sh in shapes)
    sectors = []
    for k in np.flatnonzero(blocked & ~np.roll(blocked, 1)):  # each run of blocked angles, wrapping round 360
        end = k
        while blocked[(end + 1) % len(angles)] and (end + 1) % len(angles) != k:
            end += 1
        a0, a1 = angles[k] - CLEAR_MARGIN_DEG, angles[end % len(angles)] + step_deg + CLEAR_MARGIN_DEG
        sectors.append([round(float(a0) % 360.0, 2), round(float(a1) % 360.0, 2)])
    return {
        "blocked_sectors_deg": sectors,
        "clear_distance_m": CLEAR_DISTANCE_M,
        "margin_deg": CLEAR_MARGIN_DEG,
        "ship_clearance_m": SHIP_CLEARANCE_M,
        "angle": "an arm's outward normal about the drum's axis, from +x toward +y in the frame's coordinates: its cobra_arm.arms[]"
                 ".angle_deg plus the drum's turn (pieces.drum.spin_rad_s x time, about +z); a sector runs from its first angle to its"
                 " second, counter-clockwise, wrapping at 360",
        "applies_to": "every door of the arm (the strip, z %.0f to %.0f)" % st.LAUNCH_ROW,
    }


def cobra_arm_layout() -> dict:
    """The launch doors' layout on one arm as it stands on top of the drum (station frame, +y outward, z aft), for the hangar behind
    the menu (T20 refits M7-T09's hall to it with its ``to_arm``): the doors' plane and depth, each door's middle (x, z), its half
    size, the pitch, the halls under them (the upper hall between the chamfers, the wider lower hall), the root's section and its
    creases, where a fighter hangs and is released (radius) and where the second row is staged (x and radius);
    and each arm's wing and bays. The other arms are this one turned by their ``angle_deg`` - 90 about the axis (``angle_deg`` from
    +x toward +y in the station frame; ``bow_view_deg`` as the maintainer names them, seen from the bow)."""
    x0, x1, z0, z1 = st.LAUNCH_HALL
    floor = st.ARM_HATCH[4] - st.DOOR_DEPTH
    return {
        "frame": "a Cobra arm standing on top of the drum: station frame, x across, y out from the axis, z aft from the bow tip",
        "doors": st.LAUNCH_DOORS,
        "door_floor_r": floor,
        "door_depth_m": st.DOOR_DEPTH,
        "door_half_m": [st.LAUNCH_DOOR_HALF[0], st.LAUNCH_DOOR_HALF[1]],
        "pitch_m": round((st.LAUNCH_ROW[1] - st.LAUNCH_ROW[0]) / st.LAUNCH_DOORS, 4),
        "row_z": [st.LAUNCH_ROW[0], st.LAUNCH_ROW[1]],
        "strip_x": st.LAUNCH_STRIP_X,
        "centres": [[st.LAUNCH_STRIP_X, round(z, 4)] for z in st.launch_door_centres()],
        "hall": {"x": [x0, x1], "z": [z0, z1], "floor_r": floor, "ceiling_r": st.HALL_UPPER_R},
        "lower_hall": {"x": [-st.HALL_LOWER_HALF, st.HALL_LOWER_HALF], "z": [z0, z1], "floor_r": st.HALL_UPPER_R,
                       "ceiling_r": st.HALL_CEILING_R},
        "section": [[round(x, 4), round(r, 4)] for x, r in st.arm_section(st.ARM_HATCH[2], st.ARM_HATCH[3], st.ARM_HATCH[4])],
        "creases_x": [round(-(1.0 - st.ARM_CHAMFER) * st.ARM_HATCH[2], 4), round((1.0 - st.ARM_CHAMFER) * st.ARM_HATCH[2], 4)],
        "hang_r": floor - sp.HANG_DEPTH_M,
        "release_r": floor + sp.RELEASE_M,
        "staging_x": st.LAUNCH_STRIP_X + st.STAGING_OFFSET_X,
        "staging_r": st.STAGING_R,
        "arms": [{"name": n, "wing": w, "angle_deg": a, "bow_view_deg": b, "bays": [f"cobra_bay_{w}_{k}" for k in range(1, st.LAUNCH_DOORS + 1)]}
                 for n, w, a, b in zip(ARM_NAMES, WINGS, st.ARM_ANGLES_DEG, BOW_VIEW_DEG, strict=True)],
    }


def main_docking_bay(f: Frames) -> dict:
    """The main docking bay (in the turning drum), for the traffic that fits its mouth (M7-T25): the approach from far ahead along
    the axis to the mouth, down it through the inner doors into the black void, and the mouth's clear outline about the axis (its
    half width across the band, half height up the core, and the outline itself). ``main_docking_bay_airlock`` is the void's back
    wall, where a docking lane measures its end from; ``_doors`` the inner doors' plane, ``_doors_open_m`` how far each leaf slides.
    In the drum's frame: a ship flying in matches the drum's roll, so the bay's spin (axis, rate, and where the drum's pivot sits)
    is given with it; the same numbers are the manifest's ``pieces.drum`` ``axis``, ``spin_rad_s`` and ``pivot``."""
    mouth_z, airlock_z = sd.FACE_Z, sd.VOID_BACK_Z
    far, near = APPROACH_M
    clear = sd.opening_half()
    return {
        "name": "main_docking_bay",
        "body": DRUM,
        "main_docking_bay_approach": [f.to(DRUM, (0.0, 0.0, mouth_z - far)), f.to(DRUM, (0.0, 0.0, mouth_z - near))],
        "main_docking_bay_mouth": f.to(DRUM, (0.0, 0.0, mouth_z)),
        "main_docking_bay_doors": f.to(DRUM, (0.0, 0.0, sd.DOORS_Z)),
        "main_docking_bay_doors_open_m": sd.DOOR_OPEN_M,
        "main_docking_bay_airlock": f.to(DRUM, (0.0, 0.0, airlock_z)),
        "main_docking_bay_path": [f.to(DRUM, (0.0, 0.0, mouth_z - far)), f.to(DRUM, (0.0, 0.0, mouth_z - near)),
                                  f.to(DRUM, (0.0, 0.0, mouth_z)), f.to(DRUM, (0.0, 0.0, airlock_z))],
        "main_docking_bay_clear_half_m": [round(clear[0], 4), round(clear[1], 4)],
        "main_docking_bay_opening": [_r(p) for p in sd.opening()],
        "main_docking_bay_void_half_m": list(sd.VOID_HALF),
        "axis": [0.0, 0.0, 1.0],
        "up": [0.0, 1.0, 0.0],
        "spin_axis": [0.0, 0.0, 1.0],
        "spin_rad_s": DRUM_SPIN_RAD_S,
        "pivot": _r(f.drum - f.frame),
        "spin_source": "pieces.drum: axis, spin_rad_s, pivot",
    }


ZG_HOLD_Z = -700.0  # where a Saturn waits, ahead of the bow tip on the slot's line (its 158 m clear of the prongs and the aperture's path)
ZG_APPROACH_Z = -1800.0
ZG_RELEASE_Z = -640.0  # where its pods are let go, just ahead of where it holds
ZG_SLOT_Z = -60.0  # the slot's mouth, just ahead of the prongs' tips


def cargo_bay(f: Frames) -> dict:
    """The cargo bay (zero-gravity) on the stationary spine between the bow's forks (Q8 as refined; no loader ships): a Saturn freighter
    flies the approach to the hold point and waits there facing the station; its cargo pods are released at the release point and
    fly the path by themselves, down the slot between the forks into the open bay, to the entry point inside it, where they leave
    the world. The bay is open ahead and above; the clear box is the room over its machinery. All on the frame."""
    y, front = sd.ZG_CENTRE_Y, sd.ZG_FRONT_Z
    hold = (0.0, y, ZG_HOLD_Z)
    entry = (0.0, y, 0.5 * (sd.ZG_COMPARTMENT_Z + sd.ZG_BACK_Z))  # a pod's middle with the whole pod in the compartment
    return {
        "name": "cargo_bay",
        "body": FRAME,
        "cargo_bay_approach": [f.to(FRAME, (0.0, y, ZG_APPROACH_Z)), f.to(FRAME, hold)],
        "cargo_bay_hold": f.to(FRAME, hold),
        "cargo_bay_hold_forward": [0.0, 0.0, 1.0],
        "cargo_bay_release": f.to(FRAME, (0.0, y, ZG_RELEASE_Z)),
        "cargo_bay_path": [f.to(FRAME, (0.0, y, ZG_RELEASE_Z)), f.to(FRAME, (0.0, y, ZG_SLOT_Z)), f.to(FRAME, (0.0, y, front - 40.0)),
                            f.to(FRAME, (0.0, y, front)), f.to(FRAME, entry)],
        "cargo_bay_entry": f.to(FRAME, entry),
        "cargo_bay_clear_min": f.to(FRAME, (-sd.ZG_THROAT[0] + 2.0, sd.ZG_FLOOR_Y + sd.ZG_MACHINE_M + 0.5, front)),
        "cargo_bay_clear_max": f.to(FRAME, (sd.ZG_THROAT[0] - 2.0, sd.ZG_THROAT_Y[1] - 0.5, sd.ZG_BACK_Z - 2.0)),
        "axis": [0.0, 0.0, 1.0],
        "up": [0.0, 1.0, 0.0],
    }


def grid_mounts(f: Frames) -> list[dict]:
    """D75's 23 mounts: name, kind, body, the pivot and its base's up, in the body's frame."""
    return [{"name": n, "kind": k, "body": b, "position": f.to(b, p), "up": _r(np.asarray(u) / np.linalg.norm(u))}
            for n, k, b, p, u in GRID_MOUNTS]


def _light(name: str, kind: str, body: str, p: Sequence[float], colour: str, f: Frames, **extra: object) -> dict:
    return {"name": name, "kind": kind, "body": body, "position": f.to(body, p), "colour": colour, **extra}


# The station's lights as the maintainer approved them (M7-T18): blinking red beacons on the extremities, the pink-red navigation ring
# round the forward body's flare and the red-pink navigation lights on the Cobra arms' aft parts (the Cobra arms capture), the bays'
# red lamps, and the floods that light the hull in pools from fixed fixtures (the bow and arms captures). A drawn light carries a
# `marker`: its radius on the hull and its colour as the marker shader takes it (linear, before its gain); a flood its fixture
# (`position`), `direction`, cone, throw and colour times `energy`.
BLINK_PERIOD_S, BLINK_ON_S = 3.0, 0.8  # a slow beat, as the maintainer flew it (2026-11-15)
FLOOD_WARM, FLOOD_PINK = "#FFE2C2", "#FF9A88"
NAV_RED = (0.42, 0.012, 0.040)  # red-pink (hue about 350) that the bloom and the tone mapper leave red-pink
E_DOCK, E_ARMS, E_ARMS_AFT, E_SPINE, E_RING, E_FACE = 11.0, 4.5, 3.0, 2.0, 4.5, 4.5
ARM_DEG = (90.0, 0.0, 270.0, 180.0)


def _rgb(colour: str | Sequence[float]) -> list[float]:
    if isinstance(colour, str):
        return [round(int(colour[i:i + 2], 16) / 255.0, 4) for i in (1, 3, 5)]
    return [round(float(c), 4) for c in colour]


def _marker(radius_m: float, colour: str | Sequence[float]) -> dict:
    return {"radius_m": radius_m, "rgb": _rgb(colour)}


def _ring(r: float, deg: float, z: float) -> np.ndarray:
    a = math.radians(deg)
    return np.array([r * math.cos(a), r * math.sin(a), z])


def _arm_axes(deg: float) -> tuple[np.ndarray, np.ndarray]:
    """An arm's outward and across directions (its flank normals are +-across)."""
    a = math.radians(deg)
    return np.array([math.cos(a), math.sin(a), 0.0]), np.array([-math.sin(a), math.cos(a), 0.0])


def floods(f: Frames) -> list[dict]:
    """The floods, built in the station frame and written in their body's frame. A flood casts no shadow, so each is aimed to end on
    the hull it lights: the docking ring's from well ahead of it, the arms' sideways or along them, and none forward across the
    sphere's rear face, which the arms capture shows dark."""
    out: list[dict] = []

    def flood(name: str, body: str, at, aim, outer_deg: float, inner_deg: float, range_m: float, colour: str, energy: float) -> None:
        at, aim = np.asarray(at, dtype=float), np.asarray(aim, dtype=float)
        d = (aim - at) / np.linalg.norm(aim - at)
        out.append({"name": name, "kind": "flood", "body": body, "position": f.to(body, at), "direction": _r(d),
                    "outer_deg": outer_deg, "inner_deg": inner_deg, "range_m": range_m, "rgb": _rgb(colour), "energy": energy})

    # The docking ring: eight narrow pools on its rim with dark gaps between, unevenly spaced as the bow capture's are, from under the
    # bow's prongs well ahead of the ring, each fixture and its pool set the same way toward the mouth.
    for k in range(8):
        deg = 22.5 + 45.0 * k + (8.0 if k % 2 == 0 else -8.0)
        sx = 1.0 if math.cos(math.radians(deg)) >= 0.0 else -1.0
        at = np.array([sx * 51.0, 312.0, 150.0 + 25.0 * k]) - _ring(10.0, deg, 0.0)
        flood(f"flood_ring_{k + 1}", FRAME, at, _ring(113.0, deg, 484.0), 3.6, 2.2, 620.0, FLOOD_WARM, E_DOCK)
    for deg in ARM_DEG:
        u, t = _arm_axes(deg)
        arm = int(deg)
        for side, sign in (("a", -1.0), ("b", 1.0)):
            # The arms from the forward body's flare, either side of each arm, thrown no further than the arms.
            flood(f"flood_arm_{arm}_flare_{side}", DRUM, _ring(282.0, deg + sign * 16.0, 1350.0), _ring(236.0, deg, 1080.0), 26.0, 12.0,
                  380.0, FLOOD_PINK, E_ARMS)
            # The aft part and the hull round its root, from the core between the arms: off the waist's aft step forward onto the flank,
            # underside and crease; off the core's front aft onto the taper and the step where it leaves the body.
            flood(f"flood_arm_{arm}_aft_step_{side}", DRUM, _ring(190.0, deg + sign * 45.0, 1318.0), u * 212.0 + t * sign * 44.0
                  + [0.0, 0.0, 1290.0], 44.0, 24.0, 380.0, FLOOD_PINK, E_ARMS_AFT)
            flood(f"flood_arm_{arm}_aft_core_{side}", DRUM, _ring(137.0, deg + sign * 45.0, 1030.0), u * 214.0 + t * sign * 44.0
                  + [0.0, 0.0, 1200.0], 32.0, 16.0, 480.0, FLOOD_PINK, E_ARMS_AFT)
            # The fore part, lit as the aft: that set mirrored about the arms' middle (z 1020), each fixture on the hull at its new place;
            # the core pair's mirror turned outward onto the neck and narrowed, clear of the sphere's rear face.
            flood(f"flood_arm_{arm}_fore_sphere_{side}", DRUM, _ring(269.0, deg + sign * 45.0, 722.0), u * 265.0 + t * sign * 50.0
                  + [0.0, 0.0, 750.0], 44.0, 24.0, 380.0, FLOOD_PINK, E_ARMS_AFT)
            flood(f"flood_arm_{arm}_fore_core_{side}", DRUM, _ring(163.0, deg + sign * 45.0, 1010.0), u * 250.0 + t * sign * 50.0
                  + [0.0, 0.0, 985.0], 16.0, 9.0, 480.0, FLOOD_PINK, E_ARMS_AFT)
            # The head where it meets the sphere: from the sphere just ahead of it, aft onto its nose and flanks.
            flood(f"flood_arm_{arm}_head_{side}", DRUM, _ring(247.0, deg + sign * 28.0, 660.0), u * 280.0 + t * sign * 45.0
                  + [0.0, 0.0, 770.0], 36.0, 20.0, 260.0, FLOOD_PINK, E_ARMS_AFT * 0.8)
    # Along the spine, from the beam's edges aft and up across its flanks and the modules.
    for z in (1300.0, 2700.0, 4100.0):
        for sx, side in ((-1.0, "port"), (1.0, "starboard")):
            flood(f"flood_spine_{int(z)}_{side}", FRAME, (sx * 174.0, 396.0, z), (sx * 110.0, 480.0, z + 420.0), 32.0, 16.0, 900.0,
                  FLOOD_WARM, E_SPINE)
    # The ring in front of the vanes (the aft band's fore slope), from the green zone ahead of it.
    for deg in (45.0, 135.0, 225.0, 315.0):
        flood(f"flood_aft_band_{int(deg)}", DRUM, _ring(338.0, deg, 4560.0), _ring(400.0, deg, 4830.0), 35.0, 18.0, 420.0, FLOOD_WARM,
              E_RING)
    # The biggest band's forward face and the hull ahead of it: from the forward body aft onto the face, and from the face forward.
    for k in range(4):
        deg = 45.0 + 90.0 * k
        flood(f"flood_band_face_{k + 1}", DRUM, _ring(332.0, deg, 1560.0), _ring(392.0, deg, 1795.0), 40.0, 20.0, 380.0, FLOOD_WARM,
              E_FACE)
        flood(f"flood_band_ahead_{k + 1}", DRUM, _ring(405.0, deg + 45.0, 1794.0), _ring(318.0, deg + 45.0, 1560.0), 40.0, 20.0, 380.0,
              FLOOD_WARM, E_FACE)
    return out


def lights(f: Frames) -> list[dict]:
    """The light hardpoints: beacons (blinking red) on the bow spike's two tips, every vane's tip and the reactor's aft tip; the
    navigation lights (the ring round the flare, eight on each Cobra arm's aft part); a light in each Cobra bay; the main docking
    bay's red lamps down its mouth and round it; the cargo bay's red lamps in it and at its mouth; and the floods (``floods``)."""
    out = []
    beacon = {"blink": True, "blink_period_s": BLINK_PERIOD_S, "blink_on_s": BLINK_ON_S, "marker": _marker(4.5, RED)}
    for sx, side in ((-1.0, "port"), (1.0, "starboard")):
        out.append(_light(f"beacon_bow_{side}", "beacon", FRAME, (sx * 51.0, 322.0, 0.5), RED, f, **beacon))
    for sx, side in ((-1.0, "port"), (1.0, "starboard")):
        for k, zc in enumerate(st.VANE_Z):
            for up, end in ((1.0, "top"), (-1.0, "bottom")):
                tip = (sx * st.VANE_X, up * st.VANE_TIP_Y, zc - 0.5 * (st.VANE_NOTCH[0] + st.VANE_CHORD[-1][1]))
                out.append(_light(f"beacon_vane_{side}_{k + 1}_{end}", "beacon", FRAME, tip, RED, f, **beacon))
    out.append(_light("beacon_reactor", "beacon", FRAME, (0.0, 0.0, 8001.0), RED, f, **beacon))
    # The navigation ring on the forward body's flare beside the arms, between them (the arms capture's pink ring round the band's edge).
    for k in range(36):
        deg = 5.0 + 10.0 * k
        if math.fmod(deg + 10.0, 90.0) < 20.0:
            continue
        out.append(_light(f"nav_ring_{int(deg)}", "nav", DRUM, _ring(305.0, deg, 1400.0), PINK, f, marker=_marker(3.6, PINK)))
    # Each arm's aft part: two along it at its crease and its lower edge, on both flanks (four a flank, as the capture); the aft pair at
    # the root section's end (z 1290), where its edges still stand (aft of z 1300 the arm tapers into the flare).
    for deg in ARM_DEG:
        u, t = _arm_axes(deg)
        for sign, side in ((-1.0, "a"), (1.0, "b")):
            for z in (1150.0, 1290.0):
                for p, edge in ((u * 241.6 + t * sign * 24.8, "crease"), (u * 202.2 + t * sign * 47.9, "lower")):
                    out.append(_light(f"nav_arm_{int(deg)}_{side}_{edge}_{int(z)}", "nav", DRUM, p + [0.0, 0.0, z], "#FF2A4A", f,
                                      marker=_marker(4.2, NAV_RED)))
    for bay in cobra_bays(f):
        inside = 0.5 * (np.asarray(bay["rail_start"]) + np.asarray(bay["rail_end"])) + f.drum
        out.append(_light(f"bay_light_{bay['wing']}_{bay['door_number']}", "bay", DRUM, inside, AMBER, f))
    # Down the mouth, one near the face and one near the doors (the game lights these two, M7-T25; the void stays black).
    for k, z in enumerate((sd.FRAME_Z[0] + sd.FRAME_M + 5.0, sd.FRAME_Z[3] + sd.FRAME_M + 5.0)):
        out.append(_light(f"main_docking_bay_red_{k + 1}", "main_docking_bay", DRUM, (0.0, 0.0, z), "#E0281A", f))
    for k, (x, y) in enumerate(sd.entrance_lamps()):  # the red lamps round the mouth on the block's face
        out.append(_light(f"main_docking_bay_entrance_{k + 1}", "main_docking_bay", DRUM, (x, y, sd.FACE_Z - 1.5), "#E0281A", f,
                          marker=_marker(2.4, RED)))
    for k, z in enumerate((452.0, 478.0)):
        out.append(_light(f"cargo_bay_red_{k + 1}", "cargo_bay", FRAME, (0.0, sd.ZG_CENTRE_Y, z), "#E0281A", f))  # in the compartment
    for k, (sx, y) in enumerate((sx, y) for sx in (-1.0, 1.0) for y in (325.8, 352.2)):  # a lamp at each corner of its mouth
        out.append(_light(f"cargo_bay_mouth_{k + 1}", "cargo_bay", FRAME, (sx * 31.5, y, 418.8), RED, f, marker=_marker(2.4, RED)))
    return out + floods(f)


def tour_points(f: Frames) -> list[dict]:
    """The exterior tour's stops (T12, M8): a name, the camera's position and the point it looks at, and the view direction. All on
    the frame (the camera does not spin) except the Cobra arm's, which rides the drum with its arm, inside the radius of everything
    on the frame over the docking sphere (the command section's strut, r 310) so it stays clear through a whole turn."""
    stops = (
        ("bow", FRAME, (260.0, 520.0, -700.0), (0.0, 250.0, 450.0)),
        ("main_docking_bay", FRAME, (60.0, -40.0, 120.0), (0.0, 0.0, 470.0)),
        ("cargo_bay", FRAME, (120.0, 420.0, 250.0), (0.0, 345.0, 450.0)),
        ("cobra_arm", DRUM, (160.0, 215.0, 1010.0), (0.0, 243.0, 1160.0)),
        ("grid_tower", FRAME, (180.0, 520.0, 330.0), (0.0, 410.0, 520.0)),
        ("drum", FRAME, (1100.0, -350.0, 2300.0), (0.0, 0.0, 3200.0)),
        ("vanes", FRAME, (1500.0, 700.0, 3900.0), (535.0, 600.0, 4800.0)),
        ("reactor", FRAME, (420.0, 260.0, 8450.0), (0.0, 0.0, 7700.0)),
    )
    out = []
    for name, body, at, aim in stops:
        d = np.asarray(aim) - np.asarray(at)
        out.append({"name": name, "body": body, "position": f.to(body, at), "look_at": f.to(body, aim),
                    "direction": _r(d / np.linalg.norm(d))})
    return out


# The damage sections (Q5): what a hit counts against, each a run of the render sections (T19) of one piece, bow to stern.
DAMAGE_SECTIONS = (
    ("command", FRAME, ("bow", "bow_ring", "spine_sphere")),
    ("docking_sphere", DRUM, ("aperture", "sphere_fore", "sphere_aft")),
    ("cobra_bays", DRUM, ("waist",)),
    ("forward_drum", DRUM, ("fwd_body", "fwd_band")),
    ("green_zone", DRUM, ("green_1", "green_2", "green_band", "green_3", "green_4")),
    ("aft_drum", DRUM, ("aft_band",)),
    ("spine", FRAME, ("ramp", "radiators")),
    ("cargo", FRAME, ("cargo_1", "cargo_2", "cargo_3")),
    ("vanes", FRAME, ("vanes_1", "vanes_2", "vanes_3")),
    ("hub", FRAME, ("hub", "cone")),
    ("reactor", FRAME, ("truss", "torus_shaft", "reactor")),
)


def damage_sections(section_boxes: dict[str, dict[str, tuple[list[float], list[float]]]]) -> list[dict]:
    """Each damage section with its render sections and their box in the piece's frame (``section_boxes``: piece -> name -> box)."""
    out = []
    for name, body, sections in DAMAGE_SECTIONS:
        lo = np.min([section_boxes[body][s][0] for s in sections], axis=0)
        hi = np.max([section_boxes[body][s][1] for s in sections], axis=0)
        out.append({"name": name, "body": body, "sections": list(sections), "aabb_min": _r(lo), "aabb_max": _r(hi)})
    return out


def section(f: Frames, section_boxes: dict[str, dict[str, tuple[list[float], list[float]]]]) -> dict:
    """The manifest's ``hardpoints``."""
    return {
        "frames": {"drum": "the drum's frame: on the axis at the drum's pivot, turning with it", "frame": "the asset's frame"},
        "spin_rad_s": DRUM_SPIN_RAD_S,
        "cobra_bays": cobra_bays(f),
        "cobra_arm": cobra_arm_layout(),
        "launch_clearance": launch_clearance(),
        "main_docking_bay": main_docking_bay(f),
        "cargo_bay": cargo_bay(f),
        "grid_mounts": grid_mounts(f),
        "lights": lights(f),
        "tour_points": tour_points(f),
        "damage_sections": damage_sections(section_boxes),
    }


__all__ = ["GRID_MOUNTS", "WINGS", "Frames", "cobra_arm_layout", "launch_clearance", "cobra_bays", "cargo_bay", "damage_sections", "main_docking_bay", "grid_mounts", "lights", "floods", "section",
           "tour_points"]
