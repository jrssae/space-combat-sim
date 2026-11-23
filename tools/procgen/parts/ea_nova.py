"""The Nova-class dreadnought's structure (M10-T23): the parts measured off the reference model, built from the Omega's
vocabulary (``parts/ea_omega.py``: its slab armour, girder spine, collars, nacelles, retro nozzles and lit bay) on the capital
library.

Authored frame: x to starboard, y up from the spine's axis, z aft from the tip of the sensor boom; 1 502.1 m long
(docs/assets-capital.md, "M10 lengths (T01)"). Numbers are the reference's own (``references/EA Nova class destroyer.STL``
at that length, its sections cut with ``tools/refview/sections.py``); docs/design-references.md describes the ship.

Bow to stern:

* **command block** (197 to 377 m): an armoured hexagon of plates, as the Omega's shields closed round the block: a
  vertical plate each side, a plate leaning in above to the roof and a long one leaning in below to the keel; inside, the
  bridge tube with the launch bay through it (the reference's octagonal hall, open from 198 to 328 m), a deck, the roof
  block with the bridge's window and a solid lower wedge; a diamond strake along each flank ending in a wing;
* **tankage** under the bridge tube: a long capsule each side and a short one on the centre line, and the two oval retro
  thrusters below them;
* **aerials**: the long sensor boom (port and low, one side only), lesser spikes and the masts above and below;
* **spine** (330 to 1 103 m): the Omega's girder (core, waist, posts and fins) in three bays, split by two ring lugs
  with outrigger plates in the fore bay, two more in the aft bay, and the hangar block between two collars;
* **hangar block** (559 to 741 m): an octagonal block, its flanks framed round recessed panels;
* **engine housing** (1 103 to 1 235 m): a flaring octagonal frustum with a strake along each flank;
* **engines**: four nacelles in a square, the cross beam between them, plates above and below, and a tail blade
  between each side's pair.

Every function returns modules already named for their damage section and side; ``assets/ea_nova.py`` adds the weapons,
bay's params, lights and the section table.
"""

from __future__ import annotations

import dataclasses

import numpy as np

from ..styles import Style
from . import capital as cp
from . import capital_fittings as fittings
from . import capital_solids as cs
from .capital_hull import HullRoles
from . import ea_nova_bow as bow
from .ea_omega import DARK, DECKED, MARK_AT, PANEL, PLAIN, RENEGADE_RED, _flip_y, _octagon, _put, _ring, around_hole, retro_nozzle

LENGTH_M = 1502.1
# The command block's armour: the outer face of the side plate (x, its bottom and top edge's y, its z), the roof edge and
# the keel edge where the leaning plates end (x, y), and the plates' thickness.
PLATE_X, PLATE_Y, PLATE_Z = 57.8, (-59.3, 62.5), (196.8, 376.8)
ROOF_EDGE, KEEL_EDGE = (33.2, 92.0), (16.9, -172.0)
ROOF_Z, KEEL_Z = (219.0, 312.0), (227.0, 280.0)  # the leaning plates' edges at the roof and the keel, z from and to
PLATE_THICK = 3.6
PLATE_ROOT_X = PLATE_X - 2.2  # where the leaning plates stand on the vertical one's inner edge
SPINE_Z = (330.0, 1103.0)
# The girder's core: half width and half height.
CORE_W, CORE_H = 39.5, 45.0
RINGS_Z = ((450.8, 479.2), (821.2, 849.8), (930.2, 958.2))
RING_W, RING_H = 57.5, 56.0
OUTRIGGER_X = 91.0
COLLARS_Z = ((525.2, 559.0), (741.0, 774.2))
COLLAR_W, COLLAR_H, COLLAR_CUT = 56.0, 57.0, (30.0, 12.0)
HANGAR_Z = (558.8, 740.8)
HANGAR_W, HANGAR_H, HANGAR_CUT = 67.5, 69.5, (31.5, 16.0)
RECESS_X, RECESS_Y, PILLAR_M = 59.0, 45.0, 11.0  # the flank's recessed panels: their face, their top edge; the pillars' length
BOX_X, BOX_Z = 73.0, (620.0, 655.0)  # the box standing out of the launch strip: its face and its length
STRIP_H, STRIP_DEPTH = 16.0, 32.0  # the launch strip through the axis: its height and how deep it is set into the flank
HOUSING_Z = (1103.0, 1234.8)
HOUSING_RINGS = ((1103.0, 56.0, 56.8, (11.0, 10.0)), (1180.0, 86.5, 81.0, (33.0, 22.0)), (1234.8, 97.0, 97.8, (52.0, 22.0)))
ENGINE_XY = 40.8
ENGINE_START_Z, ENGINE_MOUTH_Z = 1234.0, 1456.0
# The one launch bay, through the bridge tube above the retro thrusters (the maintainer, 2026-11-21): the reference's
# octagonal hall, its mouth at the tube's front. A Starfury is 11 m across and 7 m tall.
BAY_MOUTH, BAY_DEPTH, BAY_WALL, BAY_CORNER = bow.BAY_MOUTH, bow.BAY_DEPTH, bow.BAY_WALL, bow.BAY_CORNER
BAY_MOUTH_Z, BAY_Y, BAY_BACK_Z = bow.BAY_MOUTH_Z, bow.BAY_Y, bow.BAY_BACK_Z
ROOF_TOP_Y = 85.0  # the roof block's top, between its humps
TUBE_OUTLINE = [(36.0, -13.0), (36.0, 14.0), (32.0, 18.0), (-32.0, 18.0), (-36.0, 14.0), (-36.0, -13.0), (-32.0, -17.0), (32.0, -17.0)]
STARFURIES = 24
# The flank's wing behind the armour: (x, its y from and to, its z from and to) at its root, its middle and its tip.
WING = ((40.0, (-21.0, 25.0), (359.0, 401.0)), (75.0, (-19.0, 23.0), (360.0, 399.0)), (88.5, (-11.8, 16.8), (365.2, 393.8)))
# The fore spine's flank plates (name, low corner, high corner, roles), each mirrored below the axis.
FORE_PLATES = (("fore_fin", (CORE_W - 1.0, 18.0, 401.0), (63.0, 22.0, 418.0), "dark"), ("fore_ledge", (CORE_W - 1.0, 36.0, 398.0), (58.0, 42.0, 406.0), "panel"),
               ("fore_block", (CORE_W - 1.0, 28.0, 430.0), (44.0, 38.0, 452.0), "decked"))
CRAFT = "starfury_ally"  # the catalogue's pooled Starfury (data/capitals/loadouts.json, launches)
# The two oval retro thrusters under the bridge tube (the reference's): centre, mouth and throat z, half width and height.
RETRO_XY, RETRO_Z, RETRO_HALF, RETRO_WALL = (14.2, -79.55), (165.0, 236.0), (12.0, 26.2), 4.8
ROLES = {"dark": DARK, "panel": PANEL, "decked": DECKED}
MARK_HEIGHT_M = 36.0  # the Omega's letter in the Nova's measure (its share of the armour's height)
X_HEIGHT_M = 30.0


def _slab_at(name: str, outline: list[tuple[float, float, float]], s: Style, roles: HullRoles = PLAIN) -> cp.Module:
    """An armour plate whose outer face is ``outline``, its thickness inward along -x."""
    return cs.slab(name, outline, PLATE_THICK, (-1.0, 0.0, 0.0), s, roles)


def _plane_basis(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """A plate's outward normal (away from the axis) and its up within the plate, from three corners of its face."""
    normal = np.cross(b - a, c - a)
    normal = normal / np.linalg.norm(normal) * (1.0 if normal[0] > 0.0 else -1.0)
    up = np.array([0.0, 1.0, 0.0]) - normal[1] * normal
    return normal, up / np.linalg.norm(up)


# --- the command block ---------------------------------------------------------------------------------------------------
def armour(s: Style) -> list[cp.Module]:
    """The starboard armour round the command block: the vertical plate, the plate leaning in above it to the roof and the
    long one leaning in below it to the keel. The lower plate wears the name letter where the Omega wears it, the vertical one
    the renegades' X."""
    (y0, y1), (z0, z1) = PLATE_Y, PLATE_Z
    side = _slab_at("armour_side_r", [(PLATE_X, y0, z0), (PLATE_X, y1, z0), (PLATE_X, y1, z1), (PLATE_X, y0, z1)], s)
    root = PLATE_ROOT_X
    upper = _slab_at("armour_upper_r", [(root, y1, z0), (root, y1, z1), (*ROOF_EDGE, ROOF_Z[1]), (*ROOF_EDGE, ROOF_Z[0])], s, DECKED)
    lower = _slab_at("armour_lower_r", [(root, y0, z0), (root, y0, z1), (*KEEL_EDGE, KEEL_Z[1]), (*KEEL_EDGE, KEEL_Z[0])], s)
    # The letter in the Omega's place (Q61, Q62): on the lower plate's face, MARK_AT of the way up from its keel edge, mid to mid.
    top, keel = np.array([root, y0, 0.5 * (z0 + z1)]), np.array([*KEEL_EDGE, 0.5 * sum(KEEL_Z)])
    normal, up = _plane_basis(np.array([root, y0, z0]), np.array([root, y0, z1]), np.array([*KEEL_EDGE, KEEL_Z[0]]))
    at = keel + MARK_AT * (top - keel) + 0.001 * normal
    letter = fittings.hull_mark("mark_initial_r", at, normal, up, MARK_HEIGHT_M)
    cross = fittings.hull_mark("mark_x_r", (PLATE_X, 30.0, 330.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), X_HEIGHT_M, colour=RENEGADE_RED, text="X",
                               only_faction="renegades")
    side = dataclasses.replace(side, hardpoints=(cross,))
    lower = dataclasses.replace(lower, hardpoints=(letter,))
    return [_put("bow", m, cp.RIGHT) for m in (side, upper, lower)]


def command_block(s: Style) -> list[cp.Module]:
    """Inside the armour: the bridge tube (the spine's way forward) round the launch bay's hall, the deck over it, and the open
    front's decks, bay, struts and keel (``parts/ea_nova_bow.py``), the renegades' X on the roof block."""
    hw, hh = 0.5 * BAY_MOUTH[0] + BAY_WALL, 0.5 * BAY_MOUTH[1] + BAY_WALL
    tube = around_hole("bridge_tube_fore", TUBE_OUTLINE, hw, (BAY_Y - hh, BAY_Y + hh), (bow.FRAME_BACK_Z - 0.5, BAY_BACK_Z), s, DECKED, "bridge")
    back = cs.prism("bridge_tube", TUBE_OUTLINE, BAY_BACK_Z - 0.5, SPINE_Z[0] + 5.0, s, DECKED)
    hall, *bay = bow.bay(s)
    hall = hall.with_params(cp.BAY, craft=CRAFT, capacity=STARFURIES)
    decks = bow.decks(s)
    cross = fittings.hull_mark("mark_x_roof", (0.0, ROOF_TOP_Y, 260.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0), X_HEIGHT_M, colour=RENEGADE_RED, text="X",
                               only_faction="renegades")
    decks = [dataclasses.replace(m, hardpoints=(cross,)) if m.name == "bridge_roof" else m for m in decks]
    lean = (PLATE_ROOT_X - KEEL_EDGE[0]) / (PLATE_Y[0] - KEEL_EDGE[1])  # x lost a metre down
    inner = lambda y: min(PLATE_ROOT_X - PLATE_THICK, PLATE_ROOT_X - PLATE_THICK - (PLATE_Y[0] - y) * lean)  # noqa: E731
    return [_put("bridge", back)] + tube + [hall, *bay] + decks + bow.struts(s) + bow.keel(s, inner)


def flank_strake(s: Style) -> list[cp.Module]:
    """The diamond strake along the starboard flank through the vertical plate, ending in a thick wing beside the spine."""
    pts = [(x, y, z) for z in (257.8, 400.0) for x, y in ((34.0, 15.0), (34.0, -15.0), (62.0, 0.0))]
    strake = cs.convex("flank_strake_r", pts, s, DARK)
    wing = cs.convex("flank_wing_r", [(x, y, z) for x, (ya, yb), (za, zb) in WING for y in (ya, yb) for z in (za, zb)], s, DECKED)
    return [_put("bow", strake, cp.RIGHT), _put("spine_fore", wing, cp.RIGHT)]


def fore_plates(s: Style) -> list[cp.Module]:
    """Behind the armour, on the fore spine's starboard flank: the fin plates above and below the axis, the ledge over them and
    the blocks round the first gun deck (the reference's), each with its mirror below."""
    out: list[cp.Module] = []
    for name, lo, hi, roles in FORE_PLATES:
        out += _pair("spine_fore", cs.box(f"{name}_top_r", lo, hi, s, ROLES[roles]), f"{name}_low_r")
    return out


def tankage(s: Style) -> list[cp.Module]:
    """Under the bridge tube: a long reactant capsule each side and a short one on the centre line, and below them the two
    oval retro thrusters, open nozzles closed by their throats (the reference's)."""
    def capsule(name: str, x: float, y: float, z: tuple[float, float], r: float) -> cp.Module:
        cap = [(r - r * np.cos(a), r * np.sin(a)) for a in np.linspace(0.0, 0.5 * np.pi, 5)]
        length = z[1] - z[0]
        profile = [(0.0, 0.0), *cap[1:], *[(length - d, rr) for d, rr in reversed(cap[1:])], (length, 0.0)]
        return cs.round_body(name, (x, y, z[0]), (x, y, z[1]), profile, s, s.material("hull_panel"), sides=20, skin=cp.SKIN_FITTING)

    beam = cs.box("tank_beam", (-52.0, -50.0, 197.0), (52.0, -47.6, 236.0), s, DARK)
    retro = retro_nozzle("retro_r", *RETRO_XY, RETRO_Z, RETRO_HALF, RETRO_WALL, s)
    return [_put("fuel", capsule("tank_r", 39.5, -44.0, (176.0, 229.0), 12.8), cp.RIGHT), _put("fuel", capsule("tank_mid", 0.0, -47.8, (190.0, 230.0), 10.0)),
            _put("fuel", retro, cp.RIGHT), _put("fuel", beam)]


def aerials(s: Style) -> list[cp.Module]:
    """The sensor boom (port and low: the reference has one), the lesser spikes ahead of the block and the masts above
    the roof and below the keel."""
    boom_at = (-22.3, -117.8)
    profile = [(0.0, 0.0), (0.0, 0.8), (98.0, 0.8), (100.0, 5.5), (116.0, 5.5), (118.0, 3.7), (156.5, 3.7), (160.0, 7.0), (161.5, 7.5), (215.0, 7.5), (215.0, 0.0)]
    boom = cs.round_body("sensor_boom", (*boom_at, 0.0), (*boom_at, 215.0), profile, s, s.material("hull_dark"), sides=10,
                         creases={2, 3, 4, 5, 6, 7, 8, 9}, skin=cp.SKIN_FITTING)
    rod = cs.rod
    return [_put("bow", boom, cp.LONE),
            _put("bow", rod("spike_high", (27.2, 79.6, 218.0), (27.2, 79.6, 104.0), 0.8, s), cp.LONE),
            _put("bow", rod("spike_roof", (21.1, 87.0, 220.0), (21.1, 87.0, 129.5), 0.7, s), cp.LONE),
            _put("bow", rod("spike_keel", (0.4, -165.8, 228.0), (0.4, -165.8, 95.0), 1.6, s)),
            _put("bridge", rod("mast_top_fore", (-10.3, 74.0, 238.3), (-10.3, 178.7, 238.3), 1.5, s), cp.LONE),
            _put("bridge", rod("mast_top_aft", (7.7, 74.0, 280.3), (7.7, 178.7, 280.3), 1.5, s), cp.LONE),
            _put("bow", rod("mast_keel_fore", (-8.8, -171.0, 249.7), (-8.8, -265.0, 249.7), 0.8, s), cp.LONE),
            _put("bow", rod("mast_keel_aft", (-8.8, -171.0, 261.4), (-8.8, -228.0, 261.4), 0.8, s), cp.LONE)]


# --- the spine -----------------------------------------------------------------------------------------------------------
def spine(s: Style, name: str, section: str, z: tuple[float, float], shelf_x: float = 50.0, shelf_from: float | None = None) -> list[cp.Module]:
    """A stretch of the girder from ``z[0]`` to ``z[1]``, the Omega's in the Nova's measure: the core, an ear at each corner
    (a post and a fin off it) and a thin shelf along each flank above and below the axis. The waist, gun decks and flank
    pods stand on it where they are (:func:`flank_fittings`). ``shelf_from`` starts the shelves further aft."""
    z0, z1 = z
    core = cs.box(f"{name}_core", (-CORE_W, -CORE_H, z0), (CORE_W, CORE_H, z1), s, DECKED)
    post = cs.prism("post", [(20.5, CORE_H - 1.0), (CORE_W, CORE_H - 1.0), (CORE_W, 52.5), (30.0, 56.0), (20.5, 56.0)], z0, z1, s, DECKED)
    fin = cs.prism("fin", [(CORE_W - 1.0, 42.0), (61.0, 43.0), (CORE_W - 1.0, 52.0)], z0, z1, s, DECKED)
    ear = cs.compound(f"{name}_ear_top_r", [post, fin])
    shelf = cs.box(f"{name}_shelf_top_r", (CORE_W - 1.0, 15.0, z0 if shelf_from is None else shelf_from), (shelf_x, 18.0, z1), s, DARK)
    out = [_put(section, core)]
    for m, low in ((ear, f"{name}_ear_low_r"), (shelf, f"{name}_shelf_low_r")):
        out += [_put(section, m, cp.RIGHT), _put(section, _flip_y(m, low), cp.RIGHT)]
    return out


def _pair(section: str, m: cp.Module, low: str) -> list[cp.Module]:
    """A starboard part above the axis and its mirror below."""
    return [_put(section, m, cp.RIGHT), _put(section, _flip_y(m, low), cp.RIGHT)]


def flank_fittings(s: Style, section: str, name: str, waists: tuple = (), decks: tuple = (), strips: tuple = (), pods: tuple = ()) -> list[cp.Module]:
    """What stands on the girder's starboard flank, each a list of (z from, z to): the waist through the axis, the gun decks
    (the rows of twin cannon ports above and below it), the strips along the core and the flank pods: a panel above and
    below the axis standing off the core, stepped in two."""
    out: list[cp.Module] = []
    for k, (z0, z1) in enumerate(waists):
        out.append(_put(section, cs.box(f"{name}_waist_{k + 1}_r", (CORE_W - 1.0, -12.0, z0), (46.0, 12.0, z1), s, DARK), cp.RIGHT))
    for k, (z0, z1) in enumerate(decks):
        out += _pair(section, cs.box(f"{name}_deck_{k + 1}_top_r", (CORE_W - 1.0, 2.0, z0), (44.0, 12.5, z1), s, DARK), f"{name}_deck_{k + 1}_low_r")
    for k, (z0, z1) in enumerate(strips):
        out += _pair(section, cs.box(f"{name}_strip_{k + 1}_top_r", (CORE_W - 1.0, 16.0, z0), (45.5, 42.0, z1), s, PANEL), f"{name}_strip_{k + 1}_low_r")
    for k, (z0, z1) in enumerate(pods):
        pod = cs.compound(f"{name}_pod_{k + 1}_top_r", [cs.box("inner", (CORE_W - 1.0, 15.0, z0), (50.0, 46.0, z1), s, DECKED),
                                                        cs.box("outer", (49.5, 22.0, z0), (55.5, 39.0, z1), s, PANEL)])
        out += _pair(section, pod, f"{name}_pod_{k + 1}_low_r")
    return out


def ring(s: Style, name: str, section: str, z: tuple[float, float]) -> list[cp.Module]:
    """A ring lug round the girder: a slab over the roof and under the keel as wide as the ring, an outrigger plate off
    each of their corners and a block on each flank above and below the axis."""
    z0, z1 = z
    roof = cs.box(f"{name}_roof", (-RING_W, CORE_H - 1.0, z0), (RING_W, RING_H, z1), s, DECKED)
    plate = cs.box(f"{name}_outrigger_top_r", (RING_W - 1.0, RING_H - 1.5, z0 + 1.0), (OUTRIGGER_X, RING_H + 0.5, z1 - 1.0), s, PANEL)
    flank = cs.box(f"{name}_flank_top_r", (CORE_W - 1.0, 15.0, z0), (49.0, CORE_H, z1), s, DECKED)
    return [_put(section, roof), _put(section, _flip_y(roof, f"{name}_keel")), *_pair(section, plate, f"{name}_outrigger_low_r"),
            *_pair(section, flank, f"{name}_flank_low_r")]


def collar(s: Style, name: str, section: str, z: tuple[float, float]) -> cp.Module:
    """A collar either side of the hangar block: an octagon a little wider than the girder."""
    return _put(section, cs.prism(name, _octagon(COLLAR_W, COLLAR_H, COLLAR_CUT), *z, s, DECKED))


def hangar_block(s: Style, section: str) -> list[cp.Module]:
    """The hangar block: an octagon round the girder, each flank a frame (a pillar fore and aft, the roof's and keel's
    edges) round two recessed panels, the launch strip between them through the axis and a box standing out of it."""
    z0, z1 = HANGAR_Z
    strip = 0.5 * STRIP_H
    back = HANGAR_W - STRIP_DEPTH
    cut_y = HANGAR_H - HANGAR_CUT[1]
    top = cs.prism("hangar_roof", [(HANGAR_W, RECESS_Y), (HANGAR_W, cut_y), (HANGAR_W - HANGAR_CUT[0], HANGAR_H), (-HANGAR_W + HANGAR_CUT[0], HANGAR_H),
                                   (-HANGAR_W, cut_y), (-HANGAR_W, RECESS_Y)], z0, z1, s, DECKED)
    middle = cs.box("hangar_middle", (-back, -RECESS_Y - 0.5, z0), (back, RECESS_Y + 0.5, z1), s, DECKED)
    out = [_put(section, top), _put(section, _flip_y(top, "hangar_keel")), _put(section, middle)]
    panel = cs.box("hangar_panel_top_r", (back - 0.5, strip - 0.5, z0), (RECESS_X, RECESS_Y + 0.5, z1), s, PANEL)
    out += _pair(section, panel, "hangar_panel_low_r")
    for tag, (a, b) in (("fore", (z0, z0 + PILLAR_M)), ("aft", (z1 - PILLAR_M, z1))):
        out.append(_put(section, cs.box(f"hangar_pillar_{tag}_r", (RECESS_X - 0.5, -RECESS_Y - 0.5, a), (HANGAR_W, RECESS_Y + 0.5, b), s, DECKED), cp.RIGHT))
    # The box standing out of the strip at the block's middle.
    upper = cs.prism("hangar_box_top_r", [(RECESS_X - 0.5, strip), (BOX_X, strip), (BOX_X, 12.0), (64.0, 20.0), (RECESS_X - 0.5, 20.0)], *BOX_Z, s, DECKED)
    out += _pair(section, upper, "hangar_box_low_r")
    out.append(_put(section, cs.box("hangar_box_r", (RECESS_X - 0.5, -strip - 0.5, BOX_Z[0]), (BOX_X, strip + 0.5, BOX_Z[1]), s, DECKED), cp.RIGHT))
    bump = cs.box("hangar_bump", (-11.0, HANGAR_H - 1.0, 640.0), (11.0, 75.0, 662.0), s, DARK)
    out += [_put(section, bump), _put(section, _flip_y(bump, "hangar_bump_low"))]
    out.append(_put(section, cs.box("hangar_strip_r", (back - 0.5, -strip, z0 + PILLAR_M - 0.5), (HANGAR_W, strip, z1 - PILLAR_M + 0.5), s, DARK), cp.RIGHT))
    return out


# --- the engine housing and the engines ----------------------------------------------------------------------------------
def housing(s: Style, section: str) -> list[cp.Module]:
    """The engine housing: an octagonal frustum flaring from the girder to the engines, in two convex stretches, with a
    strake along each flank's middle."""
    rings = [_ring(_octagon(w, h, cut), z) for z, w, h, cut in HOUSING_RINGS]
    fore = cs.convex("housing_fore", rings[0] + rings[1], s, DECKED)
    aft = cs.convex("housing_aft", rings[1] + rings[2], s, DECKED)
    pts = [(x, y, z) for z, root, tip, h in ((1040.0, 44.0, 62.0, 13.0), (1103.0, 55.0, 79.0, 13.0), (1225.0, 96.0, 104.0, 13.0), (1292.0, 60.0, 92.0, 8.0))
           for x, y in ((root, h), (root, -h), (tip, 3.0), (tip, -3.0))]
    strake = cs.convex("housing_strake_r", pts, s, DARK)
    return [_put(section, fore), _put(section, aft), _put(section, strake, cp.RIGHT)]


def engine(s: Style, name: str, section: str, up: float) -> cp.Module:
    """One starboard nacelle (``up`` +1 the upper, -1 the lower): the Omega's in the Nova's measure: a drum with two
    flanges, a tapering bell and its glowing bore, with the engine's hardpoint at the mouth."""
    z0 = ENGINE_START_Z
    x, y = ENGINE_XY, up * ENGINE_XY
    at = lambda z: z - z0  # noqa: E731 - the profile is written at the ship's z
    length = ENGINE_MOUTH_Z - z0
    profile = [(0.0, 0.0), (0.0, 26.0), (at(1290.0), 26.0), (at(1300.0), 28.5), (at(1310.0), 33.0), (at(1315.0), 34.0), (at(1322.0), 34.0),
               (at(1322.0), 26.0), (at(1338.5), 26.0), (at(1340.0), 33.5), (at(1370.0), 26.0), (at(1442.0), 22.0), (length, 21.3), (length, 18.0), (length - 14.0, 14.0), (length - 14.0, 0.0)]
    hull, dark, metal, glow = s.material("hull"), s.material("hull_dark"), s.material("nozzle"), s.material("nozzle_throat")
    mats = [dark, hull, hull, hull, hull, dark, dark, hull, dark, hull, metal, metal, glow, glow, glow]
    body = cs.round_body(name, (x, y, z0), (x, y, ENGINE_MOUTH_Z), profile, s, mats, sides=20, creases=set(range(1, 15)), skin=cp.SKIN_FITTING,
                         hollow_from=13)
    point = cp.Hardpoint(name, cp.ENGINE, (x, y, ENGINE_MOUTH_Z), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), {"share": 0.25, "radius_m": 18.0})
    return _put(section, dataclasses.replace(body, hardpoints=(point,)), cp.RIGHT)


def engine_frame(s: Style, section: str) -> list[cp.Module]:
    """What holds the nacelles: the cross beam behind the housing, the blocks between each pair and on their backs, the
    plates above and below the engines with a fin on each, a pod on each outer corner, and the tail blade between each
    side's pair, running out past the bells to the stern."""
    beam = cs.convex("engine_beam", [(x, y, z) for z, w in ((1234.0, 76.0), (1292.0, 70.5)) for x in (-w, w) for y in (-14.8, 11.2)], s, DARK)
    tip = cs.convex("engine_beam_tip_r", [(x, y, z) for z, w in ((1234.0, 92.0), (1272.0, 90.0)) for x in (70.0, w) for y in (-6.0, 6.0)], s, DARK)
    # The plate over the engines thins aft as its underside rises: two convex stretches.
    plate = cs.compound("engine_plate_top", [
        cs.convex("fore", [(x, y, z) for z, w, ys in ((1234.0, 54.5, (86.0, 98.5)), (1262.0, 44.0, (94.0, 99.5))) for x in (-w, w) for y in ys], s, PANEL),
        cs.convex("aft", [(x, y, z) for z, w, ys in ((1262.0, 44.0, (94.0, 99.5)), (1302.0, 29.5, (97.0, 101.5))) for x in (-w, w) for y in ys], s, PANEL)])
    fin = cs.box("engine_fin_top", (-3.0, 98.0, 1252.0), (3.0, 105.0, 1303.0), s, DARK)
    middle = cs.box("engine_link_top", (-7.5, 35.0, 1234.0), (7.5, 45.0, 1290.0), s, DARK)
    # The tail plates: down from the plate's back edge to the bells' height, then on to the stern, with a block on the second.
    tail_a = cs.slab("tail_plate_top_1", [(-27.0, 99.5, 1306.0), (27.0, 99.5, 1306.0), (25.0, 78.5, 1365.0), (-25.0, 78.5, 1365.0)], 2.5, (0.0, -1.0, 0.0), s, PANEL)
    tail_b = cs.slab("tail_plate_top_2", [(-25.0, 78.5, 1365.0), (25.0, 78.5, 1365.0), (12.0, 74.0, 1435.0), (-12.0, 74.0, 1435.0)], 2.5, (0.0, -1.0, 0.0), s, PANEL)
    tail_block = cs.box("tail_block_top", (-6.0, 72.0, 1395.0), (6.0, 81.0, 1430.0), s, DARK)
    cross = cs.box("engine_cross", (-32.5, -13.0, 1355.0), (32.5, 13.0, 1386.0), s, DARK)
    out = [_put(section, beam), _put(section, cross), _put(section, tip, cp.RIGHT)]
    for m, low in ((plate, "engine_plate_low"), (fin, "engine_fin_low"), (middle, "engine_link_low"), (tail_a, "tail_plate_low_1"),
                   (tail_b, "tail_plate_low_2"), (tail_block, "tail_block_low")):
        out += [_put(section, m), _put(section, _flip_y(m, low))]
    pod_profile = [(0.0, 10.5), (26.0, 9.2), (40.0, 9.2), (66.0, 11.2), (72.0, 11.2), (80.0, 5.0), (80.0, 0.0)]
    pod = cs.round_body("engine_pod_top_r", (75.3, 68.8, 1234.0), (75.3, 68.8, 1314.0), pod_profile, s, s.material("hull_dark"), sides=12, skin=cp.SKIN_FITTING)
    saddle = cs.box("engine_saddle_top_r", (35.0, 64.0, 1240.0), (47.5, 77.5, 1290.0), s, DARK)
    blade = cs.convex("tail_blade_r", [(x, y, z) for z, h in ((1380.0, 11.0), (1455.0, 11.0), (LENGTH_M, 4.0)) for x in (24.5, 56.5) for y in (-h, h)], s, PLAIN)
    lug = cs.box("engine_lug_r", (47.5, -8.0, 1334.0), (80.0, 8.0, 1404.0), s, DARK)
    small = [cs.round_body(f"engine_pod_{k}_top_r", (x, y, 1234.0), (x, y, 1268.0), [(0.0, 4.4), (30.0, 4.4), (34.0, 2.0), (34.0, 0.0)], s,
                           s.material("hull_dark"), sides=8, skin=cp.SKIN_FITTING) for k, (x, y) in (("b", (60.0, 74.8)), ("c", (89.2, 60.0)))]
    out += [_put("engine_r", saddle, cp.RIGHT)]
    out += [m for p, low in ((pod, "engine_pod_low_r"), (small[0], "engine_pod_b_low_r"), (small[1], "engine_pod_c_low_r")) for m in _pair("engine_r", p, low)]
    return out + [_put("engine_r", m, cp.RIGHT) for m in (blade, lug)]


__all__ = ["BAY_BACK_Z", "BAY_DEPTH", "BAY_MOUTH", "BAY_MOUTH_Z", "BAY_Y", "COLLARS_Z", "CORE_H", "ENGINE_MOUTH_Z", "ENGINE_START_Z", "ENGINE_XY",
           "HANGAR_W", "HANGAR_Z", "HOUSING_Z", "LENGTH_M", "MARK_HEIGHT_M", "PLATE_X", "PLATE_Z", "RINGS_Z", "SPINE_Z", "STARFURIES", "aerials",
           "armour", "collar", "command_block", "engine", "engine_frame", "flank_fittings", "flank_strake", "fore_plates", "hangar_block", "housing", "ring", "spine",
           "tankage"]
