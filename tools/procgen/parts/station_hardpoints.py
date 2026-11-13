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
# The drum's are at the arms' angles as modelled.
GRID_MOUNTS: tuple[tuple[str, str, str, tuple[float, float, float], tuple[float, float, float]], ...] = (
    ("L1", LIGHT, DRUM, (-41.0, 292.0, 690.0), (0.0, 1.0, 0.0)),
    ("L2", LIGHT, DRUM, (41.0, 292.0, 690.0), (0.0, 1.0, 0.0)),
    ("L3", LIGHT, DRUM, (292.0, 41.0, 690.0), (1.0, 0.0, 0.0)),
    ("L4", LIGHT, DRUM, (292.0, -41.0, 690.0), (1.0, 0.0, 0.0)),
    ("L5", LIGHT, DRUM, (41.0, -292.0, 690.0), (0.0, -1.0, 0.0)),
    ("L6", LIGHT, DRUM, (-41.0, -292.0, 690.0), (0.0, -1.0, 0.0)),
    ("L7", LIGHT, DRUM, (-292.0, -41.0, 690.0), (-1.0, 0.0, 0.0)),
    ("L8", LIGHT, DRUM, (-292.0, 41.0, 690.0), (-1.0, 0.0, 0.0)),
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
STAGING_LIFT_M = 3.0  # a second-row fighter rises this far toward the axis to cross the hall onto its rack
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
    to the drum's axis, span across the arm), and the second row's staging point across the hall with the path onto the rack (the
    second wave)."""
    floor = st.ARM_HATCH[4] - st.DOOR_DEPTH
    cx = st.LAUNCH_STRIP_X
    out = []
    for arm, (name, angle) in enumerate(zip(ARM_NAMES, st.ARM_ANGLES_DEG, strict=True)):
        turn = _arm_turn(angle)
        radial = turn @ np.array([0.0, 1.0, 0.0])
        wing = WINGS[arm]
        for door, z in enumerate(st.launch_door_centres()):
            hang = turn @ np.array([cx, floor - sp.HANG_DEPTH_M, z])
            stage = np.array([cx + st.STAGING_OFFSET_X, floor - sp.HANG_DEPTH_M, z])
            lift = np.array([0.0, -STAGING_LIFT_M, 0.0])
            staging_path = [stage, stage + lift, np.array([cx, floor - sp.HANG_DEPTH_M, z]) + lift,
                            np.array([cx, floor - sp.HANG_DEPTH_M, z])]
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


CLEAR_DISTANCE_M = 250.0  # the frame's farthest part over the door strip (the spine's top, the dome: r 462 to 465) is 226 m out
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
    size, the pitch, the hall under them, where a fighter hangs and is released (radius) and where the second row is staged (x);
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
        "hall": {"x": [x0, x1], "z": [z0, z1], "floor_r": floor, "ceiling_r": st.HALL_CEILING_R},
        "hang_r": floor - sp.HANG_DEPTH_M,
        "release_r": floor + sp.RELEASE_M,
        "staging_x": st.LAUNCH_STRIP_X + st.STAGING_OFFSET_X,
        "arms": [{"name": n, "wing": w, "angle_deg": a, "bow_view_deg": b, "bays": [f"cobra_bay_{w}_{k}" for k in range(1, st.LAUNCH_DOORS + 1)]}
                 for n, w, a, b in zip(ARM_NAMES, WINGS, st.ARM_ANGLES_DEG, BOW_VIEW_DEG, strict=True)],
    }


def main_docking_bay(f: Frames) -> dict:
    """The main docking bay (through the aperture, in the turning drum), for Q8's traffic that fits its tunnel: the
    approach from far ahead along the axis to the mouth, down the tunnel to the inner airlock, and the clear passage's half size
    about the axis. In the drum's frame: a ship flying in matches the drum's roll, so the bay's spin (axis, rate, and where the
    drum's pivot sits) is given with it; the same numbers are the manifest's ``pieces.drum`` ``axis``, ``spin_rad_s`` and ``pivot``."""
    mouth_z, airlock_z = sd.BLOCK[2], sd.AIRLOCK_Z
    far, near = APPROACH_M
    clear = sd.clear_passage()
    return {
        "name": "main_docking_bay",
        "body": DRUM,
        "main_docking_bay_approach": [f.to(DRUM, (0.0, 0.0, mouth_z - far)), f.to(DRUM, (0.0, 0.0, mouth_z - near))],
        "main_docking_bay_mouth": f.to(DRUM, (0.0, 0.0, mouth_z)),
        "main_docking_bay_airlock": f.to(DRUM, (0.0, 0.0, airlock_z)),
        "main_docking_bay_path": [f.to(DRUM, (0.0, 0.0, mouth_z - far)), f.to(DRUM, (0.0, 0.0, mouth_z - near)),
                             f.to(DRUM, (0.0, 0.0, mouth_z)), f.to(DRUM, (0.0, 0.0, airlock_z))],
        "main_docking_bay_clear_half_m": [clear[0], clear[1]],
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
ZG_ENTRY_IN_M = 45.0  # how far in from the bay's front a pod comes to rest and leaves the world: the whole pod inside


def cargo_bay(f: Frames) -> dict:
    """The cargo bay (zero-gravity) on the stationary spine between the bow's forks (Q8 as refined; no loader ships): a Saturn freighter
    flies the approach to the hold point and waits there facing the station; its cargo pods are released at the release point and
    fly the path by themselves, down the slot between the forks into the open bay, to the entry point inside it, where they leave
    the world. The bay is open ahead and above; the clear box is the room over its machinery. All on the frame."""
    y, front = sd.ZG_CENTRE_Y, sd.ZG_FRONT_Z
    hold = (0.0, y, ZG_HOLD_Z)
    entry = (0.0, y, front + ZG_ENTRY_IN_M)
    top = st.spine_row_at(front)[3]
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
        "cargo_bay_clear_min": f.to(FRAME, (-sd.ZG_HALF_X + 2.0, sd.ZG_FLOOR_Y + sd.ZG_MACHINE_M + 0.5, front)),
        "cargo_bay_clear_max": f.to(FRAME, (sd.ZG_HALF_X - 2.0, top, sd.ZG_BACK_Z - 2.0)),
        "axis": [0.0, 0.0, 1.0],
        "up": [0.0, 1.0, 0.0],
    }


def grid_mounts(f: Frames) -> list[dict]:
    """D75's 23 mounts: name, kind, body, the pivot and its base's up, in the body's frame."""
    return [{"name": n, "kind": k, "body": b, "position": f.to(b, p), "up": _r(np.asarray(u) / np.linalg.norm(u))}
            for n, k, b, p, u in GRID_MOUNTS]


def _light(name: str, kind: str, body: str, p: Sequence[float], colour: str, f: Frames, **extra: object) -> dict:
    return {"name": name, "kind": kind, "body": body, "position": f.to(body, p), "colour": colour, **extra}


# The dashed ring lights (T18's references): z, radius and the colour of each ring round the drum, on the band edges and sphere rims.
RINGS = (("sphere_fore_rim", 575.0, 178.0, WHITE), ("sphere_aft_rim", 935.0, 248.0, WHITE), ("arms_nav_ring", 1400.0, 303.0, PINK),
         ("fwd_band_fore", 1800.0, st.BAND_R, WHITE), ("fwd_band_aft", 2290.0, st.BAND_R, WHITE),
         ("aft_band_fore", 4840.0, st.BAND_R, WHITE), ("aft_band_aft", 5400.0, st.BAND_R, WHITE))
RING_DASHES = 48


def lights(f: Frames) -> list[dict]:
    """The light hardpoints T18 lights: beacons (blinking, red) on the bow spike's two tips and every vane's tip; running lights on
    the fins' tips, the booms' fore ends and the reactor's aft face; the dashed rings round the drum (``radius``, ``axis``,
    ``dashes``); a light in each Cobra bay; the main docking bay's red lights down its tunnel; the cargo bay's red lights."""
    out = []
    for sx, side in ((-1.0, "port"), (1.0, "starboard")):
        out.append(_light(f"beacon_bow_{side}", "beacon", FRAME, (sx * 53.5, 329.0, 0.5), RED, f, blink=True))
    for sx, side in ((-1.0, "port"), (1.0, "starboard")):
        for k, zc in enumerate(st.VANE_Z):
            for up, end in ((1.0, "top"), (-1.0, "bottom")):
                tip = (sx * st.VANE_X, up * st.VANE_TIP_Y, zc - 0.5 * (st.VANE_NOTCH[0] + st.VANE_CHORD[-1][1]))
                out.append(_light(f"beacon_vane_{side}_{k + 1}_{end}", "beacon", FRAME, tip, RED, f, blink=True))
    (tip_x, tip_z0), (_, tip_z1) = st.FIN[0][1], st.FIN[0][2]  # the fin's tip edge
    for sx, side, colour in ((-1.0, "port", RED), (1.0, "starboard", GREEN)):
        out.append(_light(f"running_fin_{side}", "running", FRAME, (sx * (tip_x + 1.0), 0.0, 0.5 * (tip_z0 + tip_z1)), colour, f))
        out.append(_light(f"running_boom_{side}", "running", FRAME, (sx * 485.0, 0.0, st.BOOM[0][0] - 1.0), colour, f))
    for k in range(4):
        a = math.radians(45.0 + 90.0 * k)
        out.append(_light(f"running_reactor_{k + 1}", "running", FRAME, (80.0 * math.cos(a), 80.0 * math.sin(a), 8000.5), WHITE, f))
    for name, z, r, colour in RINGS:
        out.append(_light(f"ring_{name}", "ring", DRUM, (0.0, r + 0.5, z), colour, f, radius=r + 0.5, axis=[0.0, 0.0, 1.0],
                          dashes=RING_DASHES))
    for bay in cobra_bays(f):
        inside = 0.5 * (np.asarray(bay["rail_start"]) + np.asarray(bay["rail_end"])) + f.drum
        out.append(_light(f"bay_light_{bay['wing']}_{bay['door_number']}", "bay", DRUM, inside, AMBER, f))
    for k, z in enumerate((sd.RIB_Z[1] - 10.0, sd.RIB_Z[4] - 10.0)):
        out.append(_light(f"main_docking_bay_red_{k + 1}", "main_docking_bay", DRUM, (0.0, 0.0, z), "#E0281A", f))
    for k, z in enumerate((440.0, 470.0)):
        out.append(_light(f"cargo_bay_red_{k + 1}", "cargo_bay", FRAME, (0.0, sd.ZG_CENTRE_Y, z), "#E0281A", f))
    return out


def tour_points(f: Frames) -> list[dict]:
    """The exterior tour's stops (T12, M8): a name, the camera's position and the point it looks at, and the view direction. All on
    the frame (the camera does not spin) except the Cobra arm's, which rides the drum with its arm."""
    stops = (
        ("bow", FRAME, (260.0, 520.0, -700.0), (0.0, 250.0, 450.0)),
        ("main_docking_bay", FRAME, (60.0, -40.0, 120.0), (0.0, 0.0, 470.0)),
        ("cargo_bay", FRAME, (120.0, 420.0, 250.0), (0.0, 345.0, 450.0)),
        ("cobra_arm", DRUM, (150.0, 340.0, 1010.0), (0.0, 243.0, 1160.0)),
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


__all__ = ["GRID_MOUNTS", "WINGS", "Frames", "cobra_arm_layout", "launch_clearance", "cobra_bays", "cargo_bay", "damage_sections", "main_docking_bay", "grid_mounts", "lights", "section",
           "tour_points"]
