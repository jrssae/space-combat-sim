"""The Hyperion-class heavy cruiser's structure (M10-T22): the parts measured off the reference model, on the capital library.

Authored frame: x to starboard from the hull's axis, y up from the middle of the reference's box, z aft from the bow's
prongs; 1 025.39 m long (docs/assets-capital.md, "M10 lengths (T01)"). Numbers are the reference's own
(``references/EA-Hyperion-V5c.stl`` at that length, cut with ``tools/refview/sections.py`` and ``tools/refview/fidelity.py``);
the reference is symmetric. Its groove round the hull marks where the paint lines go: the ship is built without it, the
bands painted there instead (``ea_hyperion_fidelity.py`` cuts clear of it).

Bow to stern:

* **forward hull** (50 to 411.5 m): a box with rounded edges widening to 127 m, its floor deepening aft; a raised deck on
  the roof sloping up from 104 m to the tower; a keel strake under it; the bow's antenna array and torpedo tubes in its face;
  a dome turret on each flank and one on the deck;
* **sponsons** (346 to 416.5 m): the lower hull swelling out to 179 m across ahead of the tower, two thruster bells in
  each aft face;
* **command tower** (346 to 468 m): from 127 m below the axis to 105 m above, its front sloping back top and bottom; a drum
  and turret on its roof, a dish on a mast ahead of it, two pods under it; the shuttle bay in its aft face;
* **truss** (468 to 675 m): a neck, the girder with the hangar bump (three Starfury bays a side in the V5c's proud frames, Q58), the lower box, the
  lower chord rising aft, the web's diagonals and the frame ahead of the module;
* **reactor module** (675 to 725.5 m), **aft spine** (725 to 907 m) with its chord falling to the engine block;
* **fuel tanks** (817.5 to 907 m): two big capsules and six small ones each side, in a frame;
* **engine block** (907 to 964.5 m), three bells (to 1 025.39 m) and the rails over and under them.

Every function returns modules already named for their damage section and side; ``assets/ea_hyperion.py`` adds the weapons,
lights and the section table. The show's royal-blue bands are parts painted in the ``stripe`` role.
"""

from __future__ import annotations

import dataclasses

import numpy as np

from ..core import hull_decals
from ..core.color import srgb_to_linear
from ..core.textures import Marking
from ..styles import Style
from . import capital as cp
from . import capital_bays as bays
from . import capital_fittings as fittings
from . import capital_solids as cs
from .capital_hull import HullRoles

LENGTH_M = 1025.39
BOW_Z, FORE_END_Z = 50.0, 411.5  # the forward hull's face and its square aft end
FORE_BANDS = ((95.0, 137.0), (336.0, 367.0))  # the bow band and the aft band, at the reference's grooves
NOSE_RING = (50.3, 58.0)  # the blue ring round the nose, just behind its grey face (the stills)
# The face's centre is set back inside a lip round its edge, as the V5c's is (its recess 3.26 m deep). Its lip is 7 to 11.5 m wide;
# ours is narrower so the array's outer rods, out to 32.1 m from the axis, still root inside the recess (the maintainer's call).
NOSE_RECESS_M, NOSE_LIP_M = 3.25, 3.0
NOSE_FLOOR_Z = BOW_Z + NOSE_RECESS_M
ROOF_Y = 17.2
DECK_W, DECK_H = 29.0, 46.2  # the raised deck's half width and its top
DECK_Z = (104.0, 188.0, 352.0)  # its slope's foot and top, and its end inside the tower
TOWER_Z = (346.0, 468.0)  # the tower's front at the hull and its flat aft face
TOWER_TOP, TOWER_BOTTOM = 105.0, -127.0
TOWER_BANDS = ((50.0, 78.0), (-98.0, -75.0))
TOWER_DRUM_Y, TOWER_DRUM_Z = 142.0, 438.0  # the top of the drum the tower's turret stands on, and its axis
FIN_BOTTOM = -161.0  # the big pod's foot
NECK_END_Z = 492.0
MODULE_Z = (669.0, 725.5)
MODULE_W, MODULE_Y = 66.0, (-19.8, 52.5)
BLOCK_Z = (907.3, 964.5)
BLOCK_W, BLOCK_Y = 127.2, (-82.0, 60.5)
ENGINE_Y = -12.9
NOZZLE_XS = (-76.2, 0.0, 76.2)  # the port bell is the starboard one's twin
NOZZLE_R = 38.0
SPONSON_Z = (346.0, 416.5)
SPONSON_X = 89.5
SPONSON_Y = (-25.0, -69.2)
GIRDER_W, GIRDER_Y = 13.0, (21.5, 39.5)  # the spine's girder: half width, foot and top
BOX_W, BOX_Y = 19.8, (4.5, 21.5)  # the spine's lower box
BUMP_Z, BUMP_TOP = (510.0, 532.0, 645.0, 668.0), 51.2  # the hangar bump: its slopes' feet and tops
# Q58: three single-Starfury bays in each flank of the bump, one Starfury each, opening outward. Their doors sit in the V5c's
# three proud frames (28.5 x 18.5 m, standing out to x = 16.5), sized for the maintainer's 17.9 x 8.1 m Starfury with 2 m clear;
# the halls are 15.5 m deep, their backs either side of a 1 m wall on the axis (M10-T22, option c).
FURY_BAY_ZS = (555.25, 590.25, 625.75)
FURY_BAY_Y, FURY_BAY_MOUTH, FURY_BAY_DEPTH, FURY_BAY_WALL = 35.0, (21.9, 12.1), 15.5, 0.5  # the in-game Starfury is 15.4 m across, 7.5 m tall, 9.8 m long
FURY_FRAME, FURY_FRAME_X = (28.5, 18.5), 16.5  # each frame's size (along z, up) and its face, where the door is
# Q58: the shuttle bay in the tower's aft face, launching aft over the Starfury bays. One shuttle at a time in its 42 m hall
# (M10-T22): the 38 m crew shuttle backs in tail first so it launches nose first; the Kestrel docks with its wings folded up.
SHUTTLE_BAY_Y, SHUTTLE_BAY_MOUTH, SHUTTLE_BAY_DEPTH, SHUTTLE_BAY_WALL = 82.0, (28.0, 24.0), 42.0, 2.0
STARFURIES_PER_BAY, SHUTTLES_PER_BAY = 1, 2
# How each craft sits in the shuttle bay, for the docking and launch code (T17): which way in; how far behind the bay's craft
# point its origin goes so its length sits mid-hall (both origins are well aft of mid-length); and the Kestrel's folded wings,
# each turned up 90 degrees about its root joint (in its own frame), leaving it 22.9 m across, 19.4 m tall, clear of deck and roof.
SHUTTLE_POSES = {
    "ea_shuttle": {"entry": "tail_first", "inset_m": 4.5},
    "ea_atmo_shuttle": {"entry": "tail_first", "inset_m": 5.62, "wings": "folded_up", "fold_deg": 90.0, "fold_joint_m": [10.766, -1.104],
                        "folded_size_m": [22.9, 19.4, 29.0], "folded_y_m": [-5.46, 13.91]},
}
FURY, SHUTTLE = "starfury_ally", "ea_shuttle"

HULL = HullRoles(side="hull", deck="hull_panel", keel="hull")  # the show's ship is light all over, its keel too
DARK = HullRoles(side="hull_dark", deck="hull_dark", keel="hull_dark")
PANEL = HullRoles(side="hull_panel", deck="hull_panel", keel="hull_panel")
BAND = HullRoles(side="stripe", deck="stripe", keel="stripe", cap="stripe")


def _put(section: str, m: cp.Module, side: str = cp.CENTRE) -> cp.Module:
    return m.in_section(section).on_side(side)


def _lerp(z: float, table: list[tuple[float, float]]) -> float:
    return float(np.interp(z, [a for a, _ in table], [b for _, b in table]))


def _ring(outline: list[tuple[float, float]], z: float) -> list[tuple[float, float, float]]:
    return [(x, y, z) for x, y in outline]


def _rounded(w: float, top: float, bottom: float, r: float, r_low: float | None = None, n: int = 3) -> list[tuple[float, float]]:
    """A rectangle ``w`` either side of the axis from ``bottom`` to ``top`` with its corners rounded (``r`` above, ``r_low`` below)."""
    rl = r if r_low is None else r_low
    out = []
    for cx, cy, rad, a0 in ((w - r, top - r, r, 0.0), (-w + r, top - r, r, 90.0), (-w + rl, bottom + rl, rl, 180.0), (w - rl, bottom + rl, rl, 270.0)):
        out += [(cx + rad * np.cos(np.radians(a)), cy + rad * np.sin(np.radians(a))) for a in np.linspace(a0, a0 + 90.0, n + 1)]
    return out


def _clip(outline: list[tuple[float, float]], keep) -> list[tuple[float, float]]:  # noqa: ANN001 - a linear function of a point
    """The part of a convex outline where ``keep(p)`` is not negative."""
    out: list[tuple[float, float]] = []
    for a, b in zip(outline, outline[1:] + outline[:1], strict=True):
        fa, fb = keep(a), keep(b)
        if fa >= 0.0:
            out.append(a)
        if (fa >= 0.0) != (fb >= 0.0):
            t = fa / (fa - fb)
            out.append((a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])))
    return out


def _painted(z0: float, z1: float, bands: tuple[tuple[float, float], ...]) -> bool:
    return any(lo <= z0 and z1 <= hi for lo, hi in bands)


# --- the forward hull ----------------------------------------------------------------------------------------------------
# Half width, the floor and the edges' radius along the hull (the reference's cuts, clear of its grooves).
HALF_W = [(BOW_Z, 35.6), (60.0, 37.0), (75.0, 39.5), (90.0, 42.2), (105.0, 45.0), (120.0, 47.8), (135.0, 50.5), (150.0, 53.3), (165.0, 55.5),
          (180.0, 57.2), (195.0, 58.5), (210.0, 59.5), (240.0, 61.0), (262.0, 61.8), (300.0, 62.8), (340.0, 63.2), (FORE_END_Z, 63.5)]
FLOOR_Y = [(BOW_Z, -27.8), (60.0, -29.0), (75.0, -32.2), (90.0, -35.2), (105.0, -38.5), (120.0, -41.8), (135.0, -45.2), (150.0, -48.2),
           (165.0, -51.0), (180.0, -53.2), (195.0, -54.8), (210.0, -56.0), (225.0, -57.0), (240.0, -57.8), (255.0, -58.5), (270.0, -59.0),
           (300.0, -59.8), (345.0, -60.5), (FORE_END_Z, -60.5)]
EDGE_R = [(BOW_Z, 9.5), (60.0, 10.0), (150.0, 13.0), (250.0, 15.5), (300.0, 16.0), (FORE_END_Z, 16.0)]


def fore_outline(z: float) -> list[tuple[float, float]]:
    """The forward hull's cross-section at ``z``: a box with rounded edges."""
    return _rounded(_lerp(z, HALF_W), ROOF_Y, _lerp(z, FLOOR_Y), _lerp(z, EDGE_R))


def nose_recess() -> list[tuple[float, float]]:
    """The outline of the recess in the bow's face: the face's own, inset by the lip."""
    w, floor, r = _lerp(BOW_Z, HALF_W), _lerp(BOW_Z, FLOOR_Y), _lerp(BOW_Z, EDGE_R)
    return _rounded(w - NOSE_LIP_M, ROOF_Y - NOSE_LIP_M, floor + NOSE_LIP_M, r - NOSE_LIP_M)


def fore_pieces() -> list[tuple[str, float, float]]:
    """The forward hull's lengths between its stations, each named for its paint: the nose ring (its lip round the recess, then the
    rest), a band, or hull grey."""
    stations = sorted({*(z for z, _ in HALF_W), *(z for z, _ in FLOOR_Y if z >= BOW_Z), *NOSE_RING, NOSE_FLOOR_Z,
                       *(z for band in FORE_BANDS for z in band)})
    out = []
    for k, (a, b) in enumerate(zip(stations, stations[1:], strict=False)):
        if NOSE_RING[0] <= a and b <= NOSE_RING[1]:
            name = "nose_ring_lip" if b <= NOSE_FLOOR_Z else "nose_ring"
        else:
            name = f"fore_band_{k + 1}" if _painted(a, b, FORE_BANDS) else f"fore_hull_{k + 1}"
        out.append((name, a, b))
    return out


def _nose_rim(name: str, z0: float, z1: float, s: Style, roles: HullRoles) -> cp.Module:
    """A length of the lip round the nose's recess: convex pieces between the hull's outline and the recess's, one per edge of the
    outline, its outer half in ``roles`` and its inner half grey, so the recess's walls stay the face's grey under the ring. It
    collides as the solid length it replaces (the recess is too shallow to matter to a hit)."""
    inner, outer = nose_recess(), (fore_outline(z0), fore_outline(z1))
    middle = [tuple(0.5 * (np.asarray(a) + np.asarray(b))) for a, b in zip(fore_outline(z0), inner, strict=True)]
    pieces = []
    for i in range(len(inner)):
        k = (i, (i + 1) % len(inner))
        for half, (out_rings, in_ring, paint) in enumerate(((outer, middle, roles), ((middle, middle), inner, HULL))):
            pts = [(*o[j], z) for z, o in zip((z0, z1), out_rings, strict=True) for j in k] + [(*in_ring[j], z) for z in (z0, z1) for j in k]
            pieces.append(cs.convex(f"{name}_{i + 1}_{half + 1}", pts, s, paint))
    rim = cs.compound(name, pieces)
    return dataclasses.replace(rim, shapes=cs.convex(name, _ring(outer[0], z0) + _ring(outer[1], z1), s, roles).shapes)


def fore_hull(s: Style) -> list[cp.Module]:
    """The forward hull in lengths between its stations, the two bands and the nose ring painted (the face itself is hull grey: a
    thin grey lip ahead of the ring, and the recess inside the lip); ahead of 250 m the bow, aft the magazine."""
    out = [_put("bow", cs.convex("nose_face", _ring(nose_recess(), NOSE_FLOOR_Z - 0.1) + _ring(nose_recess(), NOSE_FLOOR_Z), s, HULL))]
    for name, a, b in fore_pieces():
        roles = HULL if name.startswith("fore_hull") else BAND
        if b <= NOSE_FLOOR_Z:
            out.append(_put("bow", _nose_rim(name, a, b, s, roles)))
            continue
        m = cs.convex(name, _ring(fore_outline(a), a) + _ring(fore_outline(b), b), s, roles)
        if a <= NAME_ROOF_Z < b:
            m = dataclasses.replace(m, hardpoints=(name_marks()["roof"],))
        if a <= NUMBER_Z < b:
            m = dataclasses.replace(m, hardpoints=(*m.hardpoints, *hull_numbers()))
        out.append(_put("bow" if b <= 250.0 else "magazine", m))
    return out


def deck(s: Style) -> list[cp.Module]:
    """The raised deck on the roof: a wedge sloping up from 104 m, flat from 188 m into the tower, the bow band painted over
    its foot; and the two thin blue stripes along the roof beside it, from band to band (the stills)."""
    z0, z1, z2 = DECK_Z
    lo = ROOF_Y - 0.5

    def ring(z: float, top: float) -> list[tuple[float, float, float]]:
        return [(x, y, z) for x in (-DECK_W, DECK_W) for y in (lo, top)]

    def top_at(z: float) -> float:
        return _lerp(z, [(z0, ROOF_Y), (z1, DECK_H)])
    band_end = FORE_BANDS[0][1]
    out = [_put("bow", cs.convex("deck_nose", ring(z0, top_at(z0) + 0.3) + ring(band_end, top_at(band_end)), s, BAND)),
           _put("bow", cs.convex("deck_slope", ring(band_end, top_at(band_end)) + ring(z1, DECK_H), s, HULL)),
           _put("magazine", cs.box("deck_flat", (-DECK_W, lo, z1), (DECK_W, DECK_H, z2), s, HULL))]
    out[2] = dataclasses.replace(out[2], hardpoints=(renegade_xs()["roof"],))
    stripe = cs.box("roof_stripe_r", (DECK_W + 2.0, ROOF_Y - 0.2, band_end), (DECK_W + 5.0, ROOF_Y + 0.25, FORE_BANDS[1][0]), s, BAND, skin=cp.SKIN_FITTING)
    return [*out, _put("magazine", stripe, cp.RIGHT)]


def keel(s: Style) -> list[cp.Module]:
    """The keel strake under the forward hull, deepest under the deck, cut at the bow band so the ring is painted across it."""
    bottom = [(113.0, -48.0), (127.0, -66.5), (160.0, -70.0), (200.0, -69.8), (250.0, -66.5), (300.0, -59.8)]

    def ring(z: float) -> list[tuple[float, float, float]]:
        yb = _lerp(z, bottom)
        return [(x, y, z) for x in (-25.5, 25.5) for y in (-40.0, yb + 5.0)] + [(x, yb, z) for x in (-19.0, 19.0)]
    cuts = sorted({*(z for z, _ in bottom), FORE_BANDS[0][1]})
    out = []
    for a, b in zip(cuts, cuts[1:], strict=False):
        painted = _painted(a, b, FORE_BANDS)
        out.append(_put("bow" if b <= 250.0 else "magazine", cs.convex(f"keel_{len(out) + 1}", ring(a) + ring(b), s, BAND if painted else HULL)))
    return out


SPONSON_PLAN = [(346.0, 63.2), (350.0, 69.2), (354.0, 73.0), (358.0, 75.8), (362.0, 78.0), (370.0, 81.5), (380.0, 84.7), (390.0, 86.8),
                (400.0, 88.2), (SPONSON_Z[1], SPONSON_X)]  # the flank's half width at mid height
THRUSTER_X, THRUSTER_YS = 80.5, (-39.5, -55.5)


def sponson(s: Style) -> list[cp.Module]:
    """The sponsons: the lower hull swelling out ahead of the tower, rounded, the aft band painted across their front; two
    thruster bells flaring aft from each aft face."""
    top, bottom = SPONSON_Y

    def ring(z: float) -> list[tuple[float, float, float]]:
        return _ring(_rounded(_lerp(z, SPONSON_PLAN), top, bottom, 8.0, n=2), z)
    band_mid, band_end, mid = 358.0, FORE_BANDS[1][1], 390.0
    rows = [z for z, _ in SPONSON_PLAN]
    # In four lengths, so each collision hull keeps the rounded corners it covers.
    out = [cs.convex("sponson_band", [p for z in rows if z <= band_mid for p in ring(z)], s, BAND),
           cs.convex("sponson_band_aft", [p for z in (*[z for z in rows if band_mid <= z < band_end], band_end) for p in ring(z)], s, BAND),
           cs.convex("sponson", [p for z in (band_end, *[z for z in rows if band_end < z <= mid]) for p in ring(z)], s, HULL),
           cs.convex("sponson_aft", [p for z in rows if z >= mid for p in ring(z)], s, HULL)]
    out = [_put("magazine", m) for m in out]
    z1 = SPONSON_Z[1]
    for k, y in enumerate(THRUSTER_YS):
        bell = cs.round_body(f"sponson_thruster_{k + 1}_r", (THRUSTER_X, y, z1 - 1.0), (THRUSTER_X, y, z1 + 13.0),
                             [(0.0, 0.0), (0.0, 4.0), (3.0, 4.5), (12.0, 6.8), (14.0, 7.0), (14.0, 0.0)], s, s.material("hull_dark"), sides=12,
                             creases={1, 2, 4}, skin=cp.SKIN_FITTING)
        out.append(_put("magazine", bell, cp.RIGHT))
    return out


# The front antenna array, read off the first reference STL (``EA Hyperion Class Heavy Cruiser.stl``, its face aligned to ours):
# 12 stepped rods of staggered length, up to 94 m ahead of the bow and not symmetric, as that model has them.
# Each is (x, y, stages); a stage is (where it starts, in that STL's metres from its nose; its radius) and runs to the next.
ARRAY_SHIFT = 43.8  # that STL's nose-measured z less ours: the two bow faces then meet at BOW_Z
ARRAY_LOWER_M = 2.5  # the maintainer's call: the rods a little lower on the face than the first STL sets them
ARRAY_DROP = ROOF_Y - 29.2 - ARRAY_LOWER_M  # that STL's roof is 12 m higher than ours: dropped by as much, and lowered
ARRAY_RODS = (
    (-28.65, 7.8, ((0.5, 0.6), (3.0, 0.95), (37.3, 1.25))),
    (-19.25, 22.3, ((3.5, 0.8), (4.8, 1.15))),
    (-19.15, 1.9, ((3.5, 0.8), (4.8, 1.15))),
    (-11.65, 12.3, ((0.0, 0.4), (1.3, 0.75), (26.4, 1.15), (50.9, 2.05))),
    (4.45, 12.25, ((54.9, 1.05), (79.6, 1.6))),
    (10.45, 18.5, ((39.2, 1.45),)),
    (13.9, 2.7, ((39.2, 0.6), (57.7, 1.1))),
    (14.0, 10.2, ((59.9, 0.65), (76.1, 1.05))),
    (22.75, 22.75, ((3.8, 0.85), (4.8, 1.15))),
    (24.95, 2.1, ((3.8, 0.85), (4.8, 1.15))),
    (31.05, 6.65, ((39.2, 0.35), (61.7, 0.95))),
    (31.3, 12.85, ((29.9, 0.4), (58.9, 0.8))),
)
ARRAY_CANNONS = {"plasma_heavy_l": 0, "plasma_heavy_r": 9}  # the rods whose tips are the heavy plasma cannons' muzzles


def front_array(s: Style) -> cp.Module:
    """The bow's antenna array: thin stepped rods rooted in the face's recess, the heavy plasma cannons' muzzles at two of their
    tips (fixed forward, they aim by the hull)."""
    bar = s.material("barrel")
    parts, hit = [], []
    for k, (x, y_old, stages) in enumerate(ARRAY_RODS):
        y, z0 = y_old + ARRAY_DROP, stages[0][0]
        length = NOSE_FLOOR_Z + 1.0 - (z0 - ARRAY_SHIFT)
        profile = [(0.0, 0.0), (0.0, stages[0][1])]
        for (_, r_prev), (z1, r1) in zip(stages, stages[1:], strict=False):
            profile += [(z1 - z0, r_prev), (z1 - z0, r1)]
        profile += [(length, stages[-1][1]), (length, 0.0)]
        parts.append(cs.round_body(f"antenna_{k + 1}", (x, y, z0 - ARRAY_SHIFT), (x, y, NOSE_FLOOR_Z + 1.0), profile, s, bar, sides=12,
                                   creases=set(range(1, len(profile) - 1)), skin=cp.SKIN_NONE))
        # One tapered convex shape a rod: the bow's collision budget (64) cannot hold every step of every rod.
        taper = [(0.0, 0.0), (0.0, stages[0][1]), (length, stages[-1][1]), (length, 0.0)]
        hit += cs.round_body(f"antenna_{k + 1}_hit", (x, y, z0 - ARRAY_SHIFT), (x, y, NOSE_FLOOR_Z + 1.0), taper, s, bar, sides=6).shapes
    array = dataclasses.replace(cs.compound("front_array", parts), shapes=tuple(hit), fine=0.3)  # fine: the thin rods need dense skin samples
    points = []
    for name, k in ARRAY_CANNONS.items():
        x, y_old, stages = ARRAY_RODS[k]
        y, tip = y_old + ARRAY_DROP, stages[0][0] - ARRAY_SHIFT
        points.append(cp.Hardpoint(name, cp.TURRET, (x, y, tip), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0),
                                   {"traverse_deg": 3.0, "elevation_deg": [-3.0, 3.0], "barrel_m": round(NOSE_FLOOR_Z - tip, 3), "barrels": 1}))
    return dataclasses.replace(array, hardpoints=tuple(points))


def particle_cannon(name: str, root: tuple[float, float, float], muzzle: tuple[float, float, float], s: Style, spread: float = 7.0,
                    rows: tuple[float, ...] = (0.0, -6.5), normal: tuple[float, float, float] = (0.0, 1.0, 0.0)) -> cp.Module:
    """A phased particle cannon: long barrels in pairs (one pair per ``rows`` offset in height) from a housing at ``root`` to
    ``muzzle`` (the deck's guns raised over the bow, the keel's lowered under it), its beam leaving along the barrels; ``normal``
    is the hull's outward normal where it stands."""
    a, b = np.asarray(root, dtype=float), np.asarray(muzzle, dtype=float)
    axis = (b - a) / np.linalg.norm(b - a)
    length = float(np.linalg.norm(b - a))
    bar, bore = s.material("barrel"), s.material("bore")
    parts = [cs.box(f"{name}_housing", (a[0] - spread - 3.0, a[1] + min(rows) - 3.5, a[2] - 4.0), (a[0] + spread + 3.0, a[1] + max(rows) + 3.5, a[2] + 10.0), s, DARK,
                    skin=cp.SKIN_FITTING)]
    for k, (dx, dy) in enumerate((x, y) for y in rows for x in (-spread, spread)):
        off = np.array([dx, dy, 0.0])
        profile = [(0.0, 0.0), (0.0, 2.6), (0.35 * length, 2.6), (0.35 * length, 1.9), (length, 1.9), (length, 0.0)]
        parts.append(cs.round_body(f"{name}_barrel_{k + 1}", a + off, b + off, profile, s, [bar, bar, bar, bar, bore], sides=16,
                                   creases={1, 2, 3, 4}, skin=cp.SKIN_NONE))
    gun = cs.compound(name, parts)
    up = np.asarray(normal, dtype=float) - float(np.dot(normal, axis)) * axis  # the hull's normal, square to the barrels
    point = cp.Hardpoint(name, cp.BEAM, tuple(float(v) for v in b), tuple(float(v) for v in axis), tuple(float(v) for v in up),
                         {"arc_deg": 45.0, "aperture_m": 3.8})
    return dataclasses.replace(gun, hardpoints=(point,))


def dome_turret(name: str, radius: float, s: Style, collar_m: float = 3.0, barrels: int = 2) -> cp.Module:
    """A dome turret (the Hyperion's pulse cannons): a collar, a hemisphere and twin barrels from its face, built on a mount
    (+y its normal, -z its front). Twin barrels, as the first reference has them (Q58: the new one's single barrels are wrong)."""
    r = radius
    arc = [(collar_m + r * np.sin(a), r * np.cos(a)) for a in np.linspace(0.0, 0.5 * np.pi, 7)[1:-1]]
    profile = [(0.0, 0.0), (0.0, 1.08 * r), (collar_m, 1.08 * r), (collar_m, r), *arc, (collar_m + r, 0.0)]
    dark, hull = s.material("hull_dark"), s.material("hull_panel")
    dome = cs.round_body(f"{name}_dome", (0.0, 0.0, 0.0), (0.0, collar_m + r, 0.0), profile, s, [dark, dark, dark, *([hull] * 6)],
                         sides=20, creases={1, 2, 3}, skin=cp.SKIN_FITTING)
    pivot = np.array([0.0, collar_m + 0.4 * r, -0.75 * r])
    length, br = 1.3 * r, max(0.09 * r, 1.4)
    bar, bore = s.material("barrel"), s.material("bore")
    guns = [cs.round_body(f"{name}_gun_{k + 1}", (x, pivot[1], pivot[2] + 0.2 * r), (x, pivot[1], pivot[2] - length),
                          [(0.0, 0.0), (0.0, 1.3 * br), (0.3 * length, 1.3 * br), (0.3 * length, br), (length + 0.2 * r, br), (length + 0.2 * r, 0.0)],
                          s, [bar, bar, bar, bar, bore], sides=16, creases={1, 2, 3, 4}, skin=cp.SKIN_NONE)
            for k, x in enumerate(np.linspace(-0.3 * r, 0.3 * r, barrels))]
    turret = cs.compound(name, [dome, *guns])
    point = cp.Hardpoint(name, cp.TURRET, tuple(pivot), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0),
                         {"traverse_deg": 180.0, "elevation_deg": [-5.0, 85.0], "barrel_m": round(length, 3), "barrels": barrels})
    return dataclasses.replace(turret, hardpoints=(point,))


# --- the command tower -----------------------------------------------------------------------------------------------------
TOWER_W = [(-127.0, 23.2), (-120.0, 25.0), (-110.0, 27.25), (-90.0, 30.75), (-80.0, 32.25), (-70.0, 33.5), (-60.0, 34.5), (-40.0, 35.8),
           (-20.0, 36.5), (0.0, 36.8), (20.0, 36.0), (40.0, 34.8), (52.0, 33.5), (60.0, 32.5), (70.0, 31.25), (82.0, 29.0), (90.0, 27.5),
           (100.0, 25.0), (105.0, 23.5)]  # half width by height
TOWER_FRONT = [(-127.0, 383.0), (-120.0, 379.0), (-110.0, 373.0), (-95.0, 365.0), (-80.0, 359.0), (-70.0, 356.0), (-60.0, 352.0),
               (20.0, 350.0), (40.0, 352.0), (52.0, 356.0), (60.0, 358.0), (70.0, 362.0), (82.0, 368.0), (90.0, 373.0), (100.0, 380.0),
               (105.0, 383.0)]  # the front face by height (inside the hull from 60 m below the axis to the roof)


def tower_plan(y: float) -> list[tuple[float, float]]:
    """The tower's plan (x, z) at height ``y``: its front corners chamfered 5 m, its aft ones 2 m."""
    w, zf, za = _lerp(y, TOWER_W), _lerp(y, TOWER_FRONT), TOWER_Z[1]
    return [(-w + 5.0, zf), (w - 5.0, zf), (w, zf + 5.0), (w, za - 2.0), (w - 2.0, za), (-w + 2.0, za), (-w, za - 2.0), (-w, zf + 5.0)]


def _tower_piece(name: str, y0: float, y1: float, s: Style, roles: HullRoles, keeps: tuple = ()) -> cp.Module:
    """The tower between two heights, cut to where every keeps function of (x, z) is not negative."""
    def plan(y: float) -> list[tuple[float, float]]:
        out = tower_plan(y)
        for keep in keeps:
            out = _clip(out, keep)
        return out
    plans = [(y, plan(y)) for y in (y0, y1)]
    return cs.convex(name, [(x, y, z) for y, plan in plans for x, z in plan], s, roles)


# The forward dish under the crown's saucer, as both STLs have it. The V5c's (whose frame this is): a flat face 11.3 m in radius at
# 346.1 m, square to the bow (no tilt), its centre 115.7 m up; a 1.5 m rim, its back tapering to a hub 8.7 m behind the face, a feed
# 9.3 m ahead of it, and a rounded boom back to a post under the saucer. The first STL's is smaller (about 7 m) and tipped a few degrees up.
DISH_FWD_Y, DISH_FWD_Z, DISH_FWD_R = 115.7, 346.1, 11.3


def forward_dish(s: Style) -> list[cp.Module]:
    """The forward-facing dish under the saucer: the dish, its feed, the boom behind it and the post up into the saucer."""
    y, z, r = DISH_FWD_Y, DISH_FWD_Z, DISH_FWD_R
    panel, dark = s.material("hull_panel"), s.material("hull_dark")
    return [cs.round_body("tower_dish_fwd", (0.0, y, z), (0.0, y, z + 8.7), [(0.0, 0.0), (0.0, r), (1.5, r), (6.4, 5.4), (8.7, 3.0), (8.7, 0.0)],
                          s, panel, sides=24, creases={1, 2, 3, 4}, skin=cp.SKIN_FITTING),
            cs.round_body("tower_dish_feed", (0.0, y, z), (0.0, y, z - 9.3), [(0.0, 0.0), (0.0, 1.9), (9.3, 1.4), (9.3, 0.0)], s, dark, sides=12,
                          creases={1, 2}, skin=cp.SKIN_FITTING),
            cs.round_body("tower_dish_boom", (0.0, y, z + 8.0), (0.0, y, z + 19.0), [(0.0, 0.0), (0.0, 5.5), (6.0, 5.5), (9.0, 3.8), (11.0, 0.0)],
                          s, panel, sides=16, creases={1, 2}, skin=cp.SKIN_FITTING),
            cs.rod("tower_dish_post", (0.0, y, z + 15.0), (0.0, 129.5, z + 15.0), 2.0, s)]


def tower(s: Style) -> list[cp.Module]:
    """The command tower in heights (its two bands painted), the shuttle bay in its aft face with the tower built round it, the
    pedestal, drum and dish on its roof, and the two pods under it."""
    (b0, b1), (l0, l1) = TOWER_BANDS
    w, h, wall = SHUTTLE_BAY_MOUTH[0] / 2 + SHUTTLE_BAY_WALL, SHUTTLE_BAY_MOUTH[1] / 2 + SHUTTLE_BAY_WALL, SHUTTLE_BAY_WALL
    slot = (SHUTTLE_BAY_Y - h, SHUTTLE_BAY_Y + h)
    back = TOWER_Z[1] - SHUTTLE_BAY_DEPTH - wall
    levels = [TOWER_BOTTOM, -110.0, l0, l1, -60.0, ROOF_Y, b0, min(b1, slot[0])]
    out = [_tower_piece(f"tower_{k + 1}", a, b, s, BAND if (a, b) in ((l0, l1), (b0, b1)) or a == b0 else HULL) for k, (a, b) in enumerate(zip(levels, levels[1:], strict=False))]
    xs, names = renegade_xs(), name_marks()
    out[5] = dataclasses.replace(out[5], hardpoints=(names["tower_r"], names["tower_l"], *emblem_marks()))
    # The tower round the bay, in heights so the band carries on past the bay's foot.
    cuts = sorted({slot[0], slot[1], *(b for b in (b1,) if slot[0] < b < slot[1])})
    sides = []
    for k, (a, b) in enumerate(zip(cuts, cuts[1:], strict=False)):
        roles = BAND if b <= b1 else HULL
        out.append(_tower_piece(f"tower_slot_fore_{k + 1}", a, b, s, roles, keeps=(lambda p: back - p[1],)))
        sides.append(_tower_piece(f"tower_slot_side_{k + 1}_r", a, b, s, roles, keeps=(lambda p: p[0] - w, lambda p: p[1] - back)))
    out.append(_tower_piece("tower_top", slot[1], TOWER_TOP, s, HULL))
    out[-1] = dataclasses.replace(out[-1], hardpoints=(xs["tower_r"], xs["tower_l"]))
    bay = bays.launch_bay("bay_shuttle", SHUTTLE_BAY_MOUTH, SHUTTLE_BAY_DEPTH, s, SHUTTLE_BAY_WALL, lit=True, rim=False, door=True, metal=True)
    out.append(bay.transformed(np.diag([-1.0, 1.0, -1.0]), (0.0, SHUTTLE_BAY_Y, TOWER_Z[1]))
               .with_params(cp.BAY, craft=SHUTTLE, capacity=SHUTTLES_PER_BAY, berths=1, poses=SHUTTLE_POSES))
    hull = s.material("hull")
    out.append(cs.round_body("tower_pedestal", (0.0, TOWER_TOP - 1.0, TOWER_DRUM_Z), (0.0, 125.0, TOWER_DRUM_Z), [(0.0, 0.0), (0.0, 14.5), (21.0, 14.5), (21.0, 0.0)],
                             s, hull, sides=20, creases={1, 2}))
    out.append(cs.round_body("tower_drum", (0.0, 125.0, TOWER_DRUM_Z), (0.0, TOWER_DRUM_Y, TOWER_DRUM_Z), [(0.0, 0.0), (0.0, 15.2), (17.0, 15.2), (17.0, 0.0)],
                             s, hull, sides=20, creases={1, 2}))
    out.append(cs.box("tower_mast_block", (-9.2, TOWER_TOP - 1.0, 400.0), (9.2, 128.0, 415.0), s, PANEL, skin=cp.SKIN_FITTING))
    out.append(cs.rod("tower_mast", (0.0, TOWER_TOP - 1.0, 392.0), (0.0, 129.0, 373.0), 1.8, s))
    out += forward_dish(s)
    out.append(cs.round_body("tower_dish", (0.0, 128.0, 372.0), (0.0, 140.0, 372.0), [(0.0, 0.0), (0.0, 8.0), (3.0, 22.5), (7.0, 22.5), (12.0, 8.0), (12.0, 0.0)],
                             s, s.material("hull_panel"), sides=20, creases={1, 2, 3, 4}, skin=cp.SKIN_FITTING))
    for k, (z, r, foot) in enumerate(((407.5, 10.0, -150.0), (444.0, 21.0, FIN_BOTTOM))):
        cap, length = 3.0, TOWER_BOTTOM + 1.0 - foot
        profile = [(0.0, 0.0), (0.0, r), (length - cap, r), (length - 0.3 * cap, 0.7 * r), (length, 0.0)]
        out.append(cs.round_body(f"tower_pod_{k + 1}", (0.0, TOWER_BOTTOM + 1.0, z), (0.0, foot, z), profile, s, hull, sides=20, creases={1, 2}))
    return [_put("bridge", m) for m in out] + [_put("bridge", m, cp.RIGHT) for m in sides]


# --- the truss, the hangar bump, the reactor module and the aft spine -------------------------------------------------------
def _member(name: str, a: tuple[float, float], b: tuple[float, float], half_x: float, half_z: float, s: Style) -> cp.Module:
    """A diagonal of a side web from (z, y) ``a`` to ``b``: ``half_x`` thick either side of the axis, ``2 * half_z`` along z."""
    return cs.convex(name, [(x, y, z + dz) for z, y in (a, b) for x in (-half_x, half_x) for dz in (-half_z, half_z)], s, DARK)


def lower_chord_fore(z: float) -> float:
    """The forward truss's lower chord: its underside at ``z``, rising aft from the tower's foot."""
    return _lerp(z, [(470.0, -79.6), (MODULE_Z[0], -13.2)])


def lower_chord_aft(z: float) -> float:
    """The aft spine's lower chord: its underside at ``z``, falling to the engine block."""
    return _lerp(z, [(MODULE_Z[1], -15.0), (BLOCK_Z[0], -75.0)])


CHORD_W, CHORD_H = 6.5, 17.5


def _spine(prefix: str, z0: float, z1: float, s: Style, top: float = GIRDER_Y[1]) -> list[cp.Module]:
    """The girder and the lower box from ``z0`` to ``z1``."""
    shoulder = [(-BOX_W, BOX_Y[1] - 2.0), (BOX_W, BOX_Y[1] - 2.0), (GIRDER_W, 26.5), (-GIRDER_W, 26.5)]  # the box's top edges lean in to the girder
    return [cs.box(f"{prefix}_girder", (-GIRDER_W, GIRDER_Y[0], z0), (GIRDER_W, top, z1), s, HULL),
            cs.box(f"{prefix}_box", (-BOX_W, BOX_Y[0], z0), (BOX_W, BOX_Y[1], z1), s, PANEL),
            cs.prism(f"{prefix}_shoulder", shoulder, z0, z1, s, PANEL)]


def truss(s: Style) -> list[cp.Module]:
    """The neck behind the tower, the girder and lower box, the lower chord rising aft, the web's diagonals and the frame of
    struts ahead of the module."""
    z0, z1 = NECK_END_Z, MODULE_Z[0]
    neck = [(x, y, z) for x in (-18.0, 18.0) for z, ys in ((TOWER_Z[1] - 2.0, (66.0, -94.0)), (488.0, (51.5, -78.5)), (z0, (GIRDER_Y[1], -75.0))) for y in ys]
    out = [cs.convex("neck", neck, s, HULL), *(_spine("truss", z0 - 1.0, z1 + 1.0, s)[1:])]
    out.append(cs.box("girder_foot", (-GIRDER_W, GIRDER_Y[0], z0 - 1.0), (GIRDER_W, FURY_BAY_Y - FURY_BAY_MOUTH[1] / 2 - FURY_BAY_WALL, z1 + 1.0), s, HULL))
    chord = [(x, y, z) for z in (TOWER_Z[1] + 2.0, z1 + 1.0) for x in (-CHORD_W, CHORD_W) for y in (lower_chord_fore(z), lower_chord_fore(z) + CHORD_H)]
    out.append(cs.convex("chord_fore", chord, s, DARK))
    for k, (a, b) in enumerate(((502.5, 531.0), (556.0, 541.0), (580.0, 595.0), (622.5, 611.0))):
        out.append(_member(f"web_fore_{k + 1}", (a, BOX_Y[0] + 1.0), (b, lower_chord_fore(b) + CHORD_H), 4.5, 5.0, s))
    return [_put("truss", m) for m in out] + [_put("truss", m, cp.RIGHT) for m in lattice(s)] + hangar(s)


def hangar(s: Style) -> list[cp.Module]:
    """The hangar bump on the girder (Q58): solid between and round the Starfury bays, a cap over them, the wall between
    their backs, and the three starboard bays, each opening outward through its proud frame and holding one Starfury (the port
    ones are their twins)."""
    f0, f1, a1, a0 = BUMP_Z
    half = FURY_BAY_MOUTH[0] / 2 + FURY_BAY_WALL
    lo = FURY_BAY_Y - FURY_BAY_MOUTH[1] / 2 - FURY_BAY_WALL
    hi = FURY_BAY_Y + FURY_BAY_MOUTH[1] / 2 + FURY_BAY_WALL
    first, last = FURY_BAY_ZS[0] - half, FURY_BAY_ZS[-1] + half
    w = GIRDER_W

    def slab(name: str, za: float, zb: float, top_a: float, top_b: float, bottom: float = lo) -> cp.Module:
        return cs.convex(name, [(x, y, z) for z, t in ((za, top_a), (zb, top_b)) for x in (-w, w) for y in (bottom, t)], s, HULL)
    out = [slab("bump_fore", NECK_END_Z - 1.0, f0, GIRDER_Y[1], GIRDER_Y[1]), slab("bump_rise", f0, f1, GIRDER_Y[1], BUMP_TOP),
           slab("bump_front", f1, first, BUMP_TOP, BUMP_TOP), slab("bump_back", last, a1, BUMP_TOP, BUMP_TOP),
           slab("bump_fall", a1, a0, BUMP_TOP, GIRDER_Y[1]), slab("bump_aft", a0, MODULE_Z[0] + 1.0, GIRDER_Y[1], GIRDER_Y[1]),
           slab("bump_cap", first, last, BUMP_TOP, BUMP_TOP, hi)]
    for k, (za, zb) in enumerate(zip(FURY_BAY_ZS, FURY_BAY_ZS[1:], strict=False)):
        out.append(slab(f"bump_web_{k + 1}", za + half, zb - half, BUMP_TOP, BUMP_TOP))
    back = FURY_FRAME_X - FURY_BAY_DEPTH - FURY_BAY_WALL
    out.append(cs.box("bump_core", (-back, lo, first), (back, hi, last), s, HULL))
    out = [_put("truss", m) for m in out]
    outward = np.array([[0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]])  # a bay's way out (-z) turned to +x, its width along z
    fz, fy = FURY_FRAME[0] / 2, FURY_FRAME[1] / 2
    for k, z in enumerate(FURY_BAY_ZS):
        bay = bays.launch_bay(f"bay_fury_{k + 1}_r", FURY_BAY_MOUTH, FURY_BAY_DEPTH, s, FURY_BAY_WALL, lit=True, rim=False, door=True, metal=True)
        out.append(_put("hangar_r", bay.transformed(outward, (FURY_FRAME_X, FURY_BAY_Y, z)).with_params(cp.BAY, craft=FURY, capacity=STARFURIES_PER_BAY), cp.RIGHT))
        # The proud frame round the bay's housing, from the bump's flank out to the door's face.
        y0, y1 = FURY_BAY_Y - fy, FURY_BAY_Y + fy
        for name, a, b in (("fore", (y0, z - fz), (y1, z - half)), ("aft", (y0, z + half), (y1, z + fz)),
                           ("top", (hi, z - half), (y1, z + half)), ("foot", (y0, z - half), (lo, z + half))):
            out.append(_put("hangar_r", cs.box(f"bay_frame_{k + 1}_{name}_r", (w, a[0], a[1]), (FURY_FRAME_X, b[0], b[1]), s, HULL), cp.RIGHT))
    return out


def lattice(s: Style) -> list[cp.Module]:
    """The starboard half of the frame of struts in the lower box's plane ahead of the module: two struts out from the box and
    a rail and cross member at the frame's edge."""
    y0, y1 = 6.5, 15.5

    def strut(name: str, a: tuple[float, float], b: tuple[float, float], half: float = 1.5) -> cp.Module:
        (za, xa), (zb, xb) = a, b
        d = np.array([xb - xa, zb - za]) / np.hypot(xb - xa, zb - za)
        nx, nz = -d[1] * half, d[0] * half
        return cs.convex(name, [(x + sx * nx, y, z + sx * nz) for z, x in (a, b) for sx in (-1.0, 1.0) for y in (y0, y1)], s, DARK)
    z1 = MODULE_Z[0] + 1.0
    # Under the frame's front a drop leads down to a lower rail running aft to the module.
    drop = cs.convex("lattice_drop_r", [(x, y, z) for x in (37.0, 46.0) for z, y in ((625.5, y0), (633.0, y0), (640.0, -7.0), (640.0, -13.0), (633.5, -13.0))], s, DARK)
    return [strut("strut_long_r", (560.0, BOX_W - 1.0), (625.0, 39.0), 5.0), strut("strut_short_r", (600.0, BOX_W - 1.0), (626.0, 30.0), 1.6),
            cs.box("lattice_rail_r", (49.5, y0, 625.0), (59.5, y1, z1), s, DARK), cs.box("lattice_front_r", (BOX_W - 1.0, y0, 625.0), (61.0, y1, 634.0), s, DARK),
            drop, cs.box("lattice_rail_low_r", (37.0, -13.0, 639.0), (46.0, -7.0, z1), s, DARK)]


def module(s: Style) -> list[cp.Module]:
    """The reactor module on the spine: a box with rounded edges, chamfered aft, and louvred panels on its flanks."""
    z0, z1 = MODULE_Z
    lo, hi = MODULE_Y
    rings = _ring(_rounded(MODULE_W, hi, lo, 6.0), z0) + _ring(_rounded(MODULE_W, hi, lo, 6.0), z1 - 3.5) + _ring(_rounded(MODULE_W - 3.5, hi - 2.5, lo + 2.5, 5.0), z1)
    box = cs.convex("module", rings, s, HULL)
    louvre = cs.box("module_louvre_r", (MODULE_W - 0.5, 2.0, z0 + 8.0), (MODULE_W + 0.8, 30.0, z1 - 8.0), s, DARK, skin=cp.SKIN_FITTING)
    return [_put("reactor", box), _put("reactor", louvre, cp.RIGHT)]


def aft_spine(s: Style) -> list[cp.Module]:
    """The aft spine: the girder and lower box, the lower chord falling to the engine block and the web's diagonals."""
    z0, z1 = MODULE_Z[1] - 1.0, BLOCK_Z[0] + 1.0
    out = _spine("spine", z0, z1, s)
    out.append(cs.convex("chord_aft", [(x, y, z) for z in (z0, z1) for x in (-CHORD_W, CHORD_W) for y in (lower_chord_aft(z), lower_chord_aft(z) + CHORD_H)], s, DARK))
    for k, (a, b) in enumerate(((776.0, 786.0), (817.5, 803.0), (834.0, 850.0), (894.5, 865.0))):
        out.append(_member(f"web_aft_{k + 1}", (a, BOX_Y[0] + 1.0), (b, lower_chord_aft(b) + CHORD_H), 4.5, 5.0, s))
    # The struts out from the lower box to the tanks' frame, and its cross member.
    y0, y1 = 6.0, 18.0
    strut = cs.convex("spine_strut_r", [(x, y, z) for x, z in ((BOX_W - 1.0, 767.0), (BOX_W - 1.0, 794.0), (45.0, 824.0), (45.0, 851.0)) for y in (y0, y1)], s, DARK)
    return [_put("spine_aft", m) for m in out] + [_put("spine_aft", strut, cp.RIGHT)]


# --- the tanks and the engines -------------------------------------------------------------------------------------------
BIG_TANKS = (("top", 70.5, 37.75, 13.75), ("low", 70.5, -60.25, 13.75))  # x, y, radius; painted blue (the stills)
FRAME_Z = (842.5, 854.5)
SMALL_TANKS = tuple((f"{k + 1}{tag}", x, y) for k, x in enumerate((33.3, 63.2, 93.1)) for tag, y in (("a", 0.5), ("b", -23.5)))


def tanks(s: Style) -> list[cp.Module]:
    """The starboard fuel tanks: two big blue capsules and six small ones ahead of the block, the plates the big ones lie in,
    the frame post ahead of them and the outrigger rail."""
    z1 = BLOCK_Z[0] + 1.0
    out = []
    z0 = 828.0  # a long pointed nose, as the reference's
    for tag, x, y, r in BIG_TANKS:
        nose = [(dz, r * k) for dz, k in ((0.0, 0.25), (2.0, 0.38), (8.0, 0.45), (10.0, 0.67), (12.0, 0.8), (14.0, 0.89), (16.0, 0.96), (19.0, 1.0))]
        out.append(cs.round_body(f"tank_{tag}_r", (x, y, z0), (x, y, z1), [(0.0, 0.0), *nose, (z1 - z0, r), (z1 - z0, 0.0)], s, s.material("stripe"),
                                 sides=16, creases={len(nose)}))
    z0 = 854.0  # the small tanks: a slim neck ahead of the full barrel
    for tag, x, y in SMALL_TANKS:
        profile = [(0.0, 0.0), (0.0, 4.0), (1.5, 6.0), (17.0, 6.0), (19.0, 9.4), (z1 - z0, 9.4), (z1 - z0, 0.0)]
        out.append(cs.round_body(f"tank_{tag}_r", (x, y, z0), (x, y, z1), profile, s, s.material("hull_panel"), sides=16, creases={1, 2, 3, 4, 5}))
        if tag.endswith("a"):  # each pair joined by a web along its necks
            out.append(cs.box(f"tank_web_{tag[:-1]}_r", (x - 3.0, SMALL_TANKS[1][2], z0 + 1.0), (x + 3.0, y, z0 + 12.0), s, DARK))
    # Each plate thickens toward the tanks' middle at its front, where it meets the frame.
    for tag, (inner, outer, foot) in (("top", (39.0, 48.0, 28.5)), ("low", (-61.5, -71.0, -52.0))):
        lip = [(x, y, z) for x in (39.5, 101.5) for z, y in ((FRAME_Z[1], outer), (FRAME_Z[1], foot), (868.0, inner), (868.0, outer))]
        out.append(cs.convex(f"tank_plate_lip_{tag}_r", lip, s, DARK))
        out.append(cs.box(f"tank_plate_{tag}_r", (39.5, min(inner, outer), 867.5), (101.5, max(inner, outer), z1), s, DARK))
    out.append(cs.box("tank_post_r", (75.0, -61.0, 817.5), (82.5, 39.5, 826.5), s, DARK))
    # The frame across the tanks' noses: two posts and a bar out from the spine's lower box.
    for k, (xa, xb) in enumerate(((39.5, 57.0), (84.0, 101.5))):
        out.append(cs.box(f"tank_frame_post_{k + 1}_r", (xa, -57.5, FRAME_Z[0]), (xb, 38.5, FRAME_Z[1]), s, DARK))
    out.append(cs.box("tank_frame_bar_r", (BOX_W - 1.0, 6.5, 848.0), (112.0, 19.5, 858.5), s, DARK))
    brace = [(x, y, z) for z, xs, ys in ((FRAME_Z[1], (98.0, 114.0), (0.5, 18.5)), (866.0, (106.5, 122.0), (6.0, 18.5))) for x in xs for y in ys]
    out.append(cs.convex("tank_outrigger_brace_r", brace, s, DARK))
    out.append(cs.box("tank_outrigger_r", (112.0, 6.0, 865.0), (122.0, 18.5, z1), s, DARK))
    return [_put("fuel_r", m, cp.RIGHT) for m in out]


def engines(s: Style) -> list[cp.Module]:
    """The engine block (solid to 953.5 m, an open frame of side walls and plates aft of it round the bells' throats), the
    three bells, each with its engine hardpoint and a pipe over and under it, and the rails over and under the bells."""
    z0, z1 = BLOCK_Z
    lo, hi = BLOCK_Y
    face = 953.5
    rings = _ring(_rounded(BLOCK_W, hi, lo, 10.0), z0) + _ring(_rounded(BLOCK_W, hi, lo, 10.0), face)
    out = [_put("engines", cs.convex("engine_block", rings, s, HULL)),
           _put("engines", cs.box("engine_frame_top", (-118.8, 52.0, face - 1.0), (118.8, 58.5, z1), s, HULL)),
           _put("engines", cs.box("engine_frame_low", (-118.2, -80.0, face - 1.0), (118.2, -73.5, z1), s, HULL))]
    wall = [(105.5, hi - 6.0), (BLOCK_W - 10.0, hi), (BLOCK_W, hi - 10.0), (BLOCK_W, lo + 10.0), (BLOCK_W - 10.0, lo), (105.5, lo + 6.0)]
    out.append(_put("engines", cs.prism("engine_frame_side_r", wall, face - 1.0, z1, s, HULL), cp.RIGHT))
    for tag, (y0, y1) in (("top", (27.5, 44.0)), ("low", (-69.0, -53.5))):
        ym, r = 0.5 * (y0 + y1), 0.5 * (y1 - y0)
        pts = [(sx * (82.0 - r + r * np.cos(a)), ym + r * np.sin(a), z) for sx in (-1.0, 1.0) for a in np.linspace(-0.5 * np.pi, 0.5 * np.pi, 5)
               for z in (z1 - 2.0, 987.0)]
        out.append(_put("engines", cs.convex(f"engine_rail_{tag}", pts, s, PANEL)))
    dark, metal, glow = s.material("hull_dark"), s.material("nozzle"), s.material("nozzle_throat")
    at = lambda z: z - (face - 1.0)  # noqa: E731 - the profile is written at the ship's z
    profile = [(0.0, 0.0), (0.0, 20.5), (at(975.0), 27.8), (at(990.0), 31.5), (at(1005.0), 35.0), (at(LENGTH_M), NOZZLE_R),
               (at(LENGTH_M), 25.3), (at(1013.0), 22.5), (at(1013.0), 0.0)]  # a shallow bore: a deeper one costs more collision than the budget
    mats = [dark, metal, metal, metal, metal, glow, glow, glow]
    for name, part, x, side, pipes in (("engine_centre", "engine_bell", NOZZLE_XS[1], cp.CENTRE, ((16.0, 6.0), (-38.0, 6.0))),
                                       ("engine_r", "engine_bell_r", NOZZLE_XS[2], cp.RIGHT, ((33.5, 7.5), (-59.0, 7.5)))):
        bell = cs.round_body(part, (x, ENGINE_Y, face - 1.0), (x, ENGINE_Y, LENGTH_M), profile, s, mats, sides=24,
                             creases={1, 2, 3, 4, 5, 6, 7}, skin=cp.SKIN_FITTING, hollow_from=6)
        point = cp.Hardpoint(name, cp.ENGINE, (x, ENGINE_Y, LENGTH_M), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), {"share": 1.0 / 3.0, "radius_m": 24.0})
        out.append(_put("engines", dataclasses.replace(bell, hardpoints=(point,)), side))
        for k, (y, r) in enumerate(pipes):
            pipe = cs.round_body(f"engine_pipe_{k + 1}" + ("_r" if side == cp.RIGHT else "_c"), (x, y, face - 1.0), (x, y, 970.0), [(0.0, 0.0), (0.0, r), (17.0, r), (17.0, 0.0)], s, dark,
                                 sides=12, creases={1, 2}, skin=cp.SKIN_FITTING)
            out.append(_put("engines", pipe, side))
    return out


# --- marks -----------------------------------------------------------------------------------------------------------------
RENEGADE_RED = (0.78, 0.09, 0.07)
X_HEIGHT_M = 26.0
X_TOWER_Y = 92.0  # above the tower's band, beside the shuttle bay


def _tower_flank(y: float, z: float) -> tuple[float, float, float]:
    """A point on the tower's starboard flank at height ``y``, a hair proud of it."""
    return (round(_lerp(y, TOWER_W) + 0.05, 3), y, z)


def renegade_xs() -> dict[str, cp.Hardpoint]:
    """The renegades' small red X paint marks (M10-T02), shown only on a renegade ship: one on each flank of the tower and one
    on the deck. Keyed by where they go."""
    def x(name: str, at: tuple[float, float, float], normal: tuple[float, float, float], up: tuple[float, float, float]) -> cp.Hardpoint:
        return fittings.hull_mark(name, at, normal, up, X_HEIGHT_M, colour=RENEGADE_RED, text="X", only_faction="renegades")
    at = _tower_flank(X_TOWER_Y, 412.0)
    return {"tower_r": x("mark_x_r", at, (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
            "tower_l": x("mark_x_l", (-at[0], at[1], at[2]), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
            "roof": x("mark_x_roof", (0.0, DECK_H + 0.05, 230.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0))}


NAME_BLUE = (0.141, 0.322, 0.706)  # the bands' royal blue (sRGB), as the show's lettering on the tower
NAME_LIGHT = (0.86, 0.87, 0.88)  # the stills' light lettering across the bow's roof
NAME_HEIGHT_M = {"roof": 8.0, "tower": 8.0}
NAME_ROOF_STRETCH = 1.2  # the bow's name is printed wider than the tower's (the stills)
NAME_TOWER_Y = 40.0  # just under the tower's upper band
NAME_ROOF_Z = 63.0  # between the nose ring and the top particle cannon's muzzles (70 m), which hide the roof aft of them from above


def name_marks() -> dict[str, cp.Hardpoint]:
    """The ship's own name in block print, as the stills paint HYPERION: light across the bow's roof between the rim and the
    bow band (reading from above with the bow below, outlined in black as the stills print it), royal blue along each flank of
    the tower under its upper band. Keyed by where they go."""
    def mark(name: str, at: tuple[float, float, float], normal: tuple[float, float, float], up: tuple[float, float, float], where: str,
             colour: tuple[float, float, float], stretch: float = 1.0) -> cp.Hardpoint:
        return fittings.hull_mark(name, at, normal, up, NAME_HEIGHT_M[where], colour=colour, text="name", stretch=stretch, outline=where == "roof")
    at = _tower_flank(NAME_TOWER_Y, EMBLEM_Z)
    return {"roof": mark("mark_name_roof", (0.0, ROOF_Y + 0.05, NAME_ROOF_Z), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), "roof", NAME_LIGHT, NAME_ROOF_STRETCH),
            "tower_r": mark("mark_name_r", at, (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), "tower", NAME_BLUE),
            "tower_l": mark("mark_name_l", (-at[0], at[1], at[2]), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), "tower", NAME_BLUE)}


# The Earth Alliance emblem (Q64, ``core/hull_decals.py``) on each flank of the tower under the name, as the side still
# (``references/ships/Hyperion/Pasted image.png``) sets it: centred under HYPERION, as wide as the name is long, on the smooth flank
# aft of where the forward hull and the sponson meet the tower. The game draws it as a sharp decal (M10-T22: baked into the hull it
# was as blurred as the plating's texels), lit by the lamp under it.
EMBLEM_WIDTH_M = 42.0
EMBLEM_Z = 0.5 * (SPONSON_Z[1] + TOWER_Z[1] - 2.0)  # mid-way along the smooth flank, from the sponson's end to the aft chamfer
EMBLEM_HEIGHT_M = EMBLEM_WIDTH_M * hull_decals.DESIGN_H / hull_decals.DESIGN_W
EMBLEM_Y = NAME_TOWER_Y - 0.5 * NAME_HEIGHT_M["tower"] - 2.0 - 0.5 * EMBLEM_HEIGHT_M


def _linear(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    return tuple(float(c) for c in srgb_to_linear(np.asarray(rgb, dtype=float) / 255.0))  # type: ignore[return-value]


def emblem_marks() -> tuple[cp.Hardpoint, cp.Hardpoint]:
    """The emblem on each flank of the tower, reading with the name (toward the bow on the starboard flank, the stern on the port),
    leaning with the flank, which narrows upward; its lamp's light is given in the emblem's own frame (right, up, out)."""
    slope = (_lerp(EMBLEM_Y + 1.0, TOWER_W) - _lerp(EMBLEM_Y - 1.0, TOWER_W)) / 2.0  # the flank's run across per metre up
    normal, up = np.array([1.0, -slope, 0.0]), np.array([slope, 1.0, 0.0])
    normal, up = normal / np.linalg.norm(normal), up / np.linalg.norm(up)
    right = np.cross(up, normal)
    at = np.array([_lerp(EMBLEM_Y, TOWER_W) + 0.05, EMBLEM_Y, EMBLEM_Z])
    flood = _emblem_flood()
    frame = np.stack([right, up, normal])
    glow = {"lamp": [round(float(v), 4) for v in frame @ (np.asarray(flood.lamp) - at)],
            "direction": [round(float(v), 5) for v in frame @ flood.direction()], "outer_deg": flood.outer_deg, "inner_deg": flood.inner_deg,
            "range_m": flood.range_m, "colour": [round(c, 5) for c in _linear(flood.colour)], "strength": flood.strength}
    flip = np.array([-1.0, 1.0, 1.0])
    return tuple(fittings.hull_image(name, tuple(at * (flip if sx < 0 else 1.0)), tuple(normal * (flip if sx < 0 else 1.0)), tuple(up * (flip if sx < 0 else 1.0)),
                                     hull_decals.EMBLEM, EMBLEM_WIDTH_M, EMBLEM_HEIGHT_M, glow)
                 for name, sx in (("mark_emblem_r", 1), ("mark_emblem_l", -1)))  # type: ignore[return-value]


@dataclasses.dataclass(frozen=True)
class Flood:
    """A hull-mounted flood lamp (starboard, the port one its mirror; or one on the axis when ``centre``), the pool it throws on
    ``parts``, and the bracket it stands on (``bracket``: a box's corners, or none): the warm lamps on the tower's roof that light
    the bridge's pedestal and drum (the show's stills light the tower's crown warm), the lamps under the emblems shining up onto
    them, and the lamp at the front of the bow's roof lighting the name (the stills)."""

    name: str
    lamp: tuple[float, float, float]
    aim: tuple[float, float, float]
    outer_deg: float
    inner_deg: float
    range_m: float
    colour: tuple[int, int, int]
    strength: float
    parts: tuple[str, ...] = ("tower_6",)
    centre: bool = False
    bracket: tuple[tuple[float, float, float], tuple[float, float, float]] | None = None
    section: str = "bridge"

    @property
    def sides(self) -> tuple[float, ...]:
        return (1.0,) if self.centre else (1.0, -1.0)

    def direction(self, sx: float = 1.0) -> np.ndarray:
        d = np.subtract(self.aim, self.lamp) * (sx, 1.0, 1.0)
        return d / np.linalg.norm(d)


def _emblem_flood() -> Flood:
    """The lamp under the emblem, on a short bracket off the flank, shining up the flank onto it."""
    y = EMBLEM_Y - 0.5 * EMBLEM_HEIGHT_M - 7.0
    x = _lerp(y, TOWER_W)
    return Flood("flood_emblem", (x + 3.0, y, EMBLEM_Z), (x, EMBLEM_Y + 3.0, EMBLEM_Z), 42.0, 16.0, 40.0, (244, 240, 232), 0.9,
                 parts=("tower_5", "tower_6", "tower_7"), bracket=((x - 0.5, y - 1.4, EMBLEM_Z - 1.4), (x + 2.4, y - 0.6, EMBLEM_Z + 1.4)))


def _name_flood() -> Flood:
    """The lamp at the front of the bow's roof, on a short post, shining aft over the name."""
    lamp = (0.0, ROOF_Y + 4.2, BOW_Z + 3.0)
    return Flood("flood_name_roof", lamp, (0.0, ROOF_Y, NAME_ROOF_Z + 6.0), 40.0, 16.0, 50.0, (244, 240, 232), 0.85,
                 parts=tuple(name for name, a, _ in fore_pieces() if a < FORE_BANDS[0][0] + 10.0), centre=True,
                 bracket=((-1.0, ROOF_Y - 0.5, lamp[2] - 1.0), (1.0, lamp[1] - 0.7, lamp[2] + 1.0)), section="bow")


FLOODS = (
    Flood("flood_crown", (17.0, TOWER_TOP + 0.5, 390.0), (0.0, 130.0, TOWER_DRUM_Z), 24.0, 10.0, 95.0, (255, 226, 194), 0.9),
    _emblem_flood(),
    _name_flood(),
)

BOW_LAMP = (27.0, 10.0, NOSE_FLOOR_Z)  # the white flood lamp in the bow's recess, between the array's rods (no pool: it lights the rods)


def flood_pools() -> list[tuple[str, Marking]]:
    """Each flood's pool of light baked into the hull's glow, on each of its parts, both sides."""
    return [(part, Marking.flood("", (sx * f.lamp[0], f.lamp[1], f.lamp[2]), tuple(f.direction(sx)), f.outer_deg, f.inner_deg, f.range_m,
                                 _linear(f.colour), f.strength)) for f in FLOODS for sx in f.sides for part in f.parts]


def flood_brackets(s: Style) -> list[cp.Module]:
    """The brackets and posts the floods' lamps stand on."""
    return [cs.box(f"{f.name}_bracket" if f.centre else f"{f.name}_bracket_r", *f.bracket, s, PANEL, skin=cp.SKIN_FITTING)
            .in_section(f.section).on_side(cp.CENTRE if f.centre else cp.RIGHT) for f in FLOODS if f.bracket is not None]


NUMBER_INK = NAME_LIGHT  # white with a black outline, like the bow's name (Q65)
NUMBER_HEIGHT_M = 26.0
NUMBER_Z = 168.0  # just aft of the bow band, ahead of the flank dome turret (263 m on), as the stills paint it
NUMBER_Y = -16.0  # mid-way down the flank's flat


def hull_numbers() -> tuple[cp.Hardpoint, cp.Hardpoint]:
    """The ship's hull number (the show's "21") painted on each flank of the forward hull aft of the bow band; the game picks the
    digits from the ship's name (``data/ships/names.json``, ``hull_numbers``), white outlined in black like the bow's name (Q65). The flank widens aft, so the mark leans with it: a
    flat mark square to the beam would sink its aft digit into the hull."""
    span = 0.5 * NUMBER_HEIGHT_M
    w, slope = _lerp(NUMBER_Z, HALF_W), (_lerp(NUMBER_Z + span, HALF_W) - _lerp(NUMBER_Z - span, HALF_W)) / (2.0 * span)
    n = np.array([1.0, 0.0, -slope]) / np.hypot(1.0, slope)
    return tuple(fittings.hull_mark(name, (sx * w, NUMBER_Y, NUMBER_Z), (sx * round(float(n[0]), 5), 0.0, round(float(n[2]), 5)), (0.0, 1.0, 0.0),
                                    NUMBER_HEIGHT_M, colour=NUMBER_INK, text="number", outline=True) for name, sx in (("mark_number_r", 1), ("mark_number_l", -1)))  # type: ignore[return-value]


__all__ = ["BLOCK_Y", "BLOCK_Z", "BOW_Z", "ROOF_Y", "DECK_H", "DECK_Z", "ENGINE_Y", "FIN_BOTTOM", "FORE_BANDS", "FORE_END_Z", "FURY", "FURY_BAY_DEPTH", "FURY_BAY_WALL", "FURY_BAY_ZS", "FURY_FRAME", "FURY_FRAME_X", "GIRDER_W",
           "LENGTH_M", "MODULE_Y", "MODULE_Z", "NOZZLE_XS", "NUMBER_Z", "SHUTTLE", "SHUTTLE_BAY_Y", "SHUTTLE_POSES", "SHUTTLES_PER_BAY", "SPONSON_X", "SPONSON_Z", "STARFURIES_PER_BAY",
           "TOWER_DRUM_Y", "TOWER_DRUM_Z", "TOWER_TOP", "TOWER_Z", "aft_spine", "front_array", "deck", "dome_turret", "engines", "fore_hull", "fore_outline",
           "BOW_LAMP", "EMBLEM_Z", "FLOODS", "Flood", "NOSE_FLOOR_Z", "NOSE_LIP_M", "NOSE_RECESS_M", "NOSE_RING", "DISH_FWD_R", "DISH_FWD_Y", "DISH_FWD_Z", "emblem_marks", "forward_dish", "nose_recess", "flood_brackets", "flood_pools", "fore_pieces", "hangar", "hull_numbers", "keel", "lattice", "module", "name_marks", "particle_cannon", "renegade_xs", "sponson", "tanks", "tower",
           "tower_plan", "truss"]
