"""The Omega's open-frame bow (M10-T68; Q62, Q63): what the four-part kit shows ahead of the command block, measured off the
assembled kit (``tools/refview/kit.py``, ``references/EA Omega kit assembled.npy`` at 16.876 m a millimetre).

Frame and numbers as ``parts/ea_omega.py``'s. Seen from ahead, between the two armour shields:

* **the launch bay**: the octagonal hall (Babylon 5's grey bay metal lit red from inside, no glowing rim and no door, Q64) in a
  proud octagonal frame, a thin wedge fin from each side of the frame back to the vertical shield;
* **decks**: two thin deck plates standing forward from the command block above the bay, the deck block between them set
  back, the hump on the roof with the bridge's window and two thin frames standing up between the upper shields;
* **under the bay**: three reactant tanks (domes on drums), the two oval retro thrusters (shallow nozzles closed by their throats) in their
  housings, small struts from each nozzle out to the shield, two cross beams and the keel block.

The bay's hall and the deck blocks are the bow's open interior (T72, Q68: :data:`INTERIOR_MODULES`).
"""

from __future__ import annotations

import dataclasses

import numpy as np

from ..core import collision as col
from ..styles import Style
from . import capital as cp
from . import capital_bays as bays
from . import capital_solids as cs
from .capital_hull import HullRoles
from .ea_omega import BAY_CORNER, BAY_DEPTH, BAY_MOUTH, BAY_MOUTH_Z, BAY_WALL, BAY_Y, COMMAND_Z, CRAFT, DARK, DECKED, PANEL, PLAIN, RETRO_NARROW
from .ea_omega import RETRO_THROAT_Z, RETRO_WALL, RETRO_Z, STARFURIES, _put, paired_hulls, retro_nozzle

METAL = HullRoles(side="bay_metal", deck="bay_metal", keel="bay_metal", cap="bay_metal")
GLASS = HullRoles(side="canopy_glass", deck="canopy_glass", keel="canopy_glass")
# The frame round the mouth: its outer octagon (half width and height, centre's y, corners), a lip at its face bevelled back.
FRAME_HALF, FRAME_Y, FRAME_CUT = (42.0, 22.5), -3.2, (11.0, 12.0)
FRAME_FACE_Z, FRAME_BEVEL_Z, FRAME_BACK_Z = 184.0, 200.0, COMMAND_Z[0] + 1.0
FINS = (("top", (2.5, 6.0)), ("low", (-15.0, -9.0)))  # the wedge fins' heights at the frame (the kit's)
FIN_X, FIN_Z = (FRAME_HALF[0] - 0.5, 62.5), ((194.0, COMMAND_Z[0]), (206.0, COMMAND_Z[0]))  # root and tip: x; their z from, to
# The deck plates standing forward (y from, to; face z) and the deck blocks set back between them (y from, to; face z).
DECK_PLATES = (("deck_plate_top", (49.8, 52.0), 209.0), ("deck_plate_mid", (22.6, 24.8), 204.0))
DECK_BLOCKS = (("deck_block_top", (27.0, 49.8), 217.0),)
DECK_X = 62.5  # out to the shields' inner face
DECK_BACK_Z = COMMAND_Z[0] + 1.0
# The roof over the command block: the deck, the hump with the bridge's window, the two thin frames between the upper shields.
ROOF_HUMP = ((-26.0, 63.5), (26.0, 72.0), (248.0, 292.0))
ROOF_FRAMES = ((236.0, 240.0), (300.0, 305.0))  # z from, to; each from the roof deck up between the upper shields
ROOF_FRAME_TOP = 87.0
SHIELD_INNER = ((62.0, 57.0), (46.0, 95.0))  # the upper shield's inner face: (x, y) at its root and at its top edge
# Under the bay: the reactant tanks (x, y, radius, the dome's tip's z; each a dome on a drum back to the command block), the
# retro thrusters' housing, the struts and the beams.
TANKS = (("sphere_r", 42.5, -46.0, 12.5, 168.0), ("sphere_mid", 0.0, -50.0, 10.5, 174.0))
UNDER_BAY_BLOCK = ((-30.0, -40.0, 212.0), (30.0, -33.0, COMMAND_Z[0] + 1.0))
LOWER_BLOCK = ((-62.0, -64.0, 218.0), (62.0, -29.0, COMMAND_Z[0] + 1.0))  # the command block's lower part stands a little forward
RETRO_X, RETRO_Y, RETRO_HALF = 17.5, -99.8, (13.5, 29.5)
TANK_BACK_Z = (322.0, 300.0)  # the housing's back, at its top and its bottom (it slopes)
STRUT_YS, STRUT_X, STRUT_Z = (-79.0, -86.0, -115.0, -122.0), (RETRO_X + RETRO_HALF[0] - 1.0, 40.0), (180.0, 280.0)
BEAMS = (("beam_upper", (-138.0, -134.0), 44.0, (212.0, 298.0)), ("beam_lower", (-154.0, -150.0), 40.0, (212.0, 292.0)))
KEEL_BLOCK = ((-16.0, -168.0, 204.0), (16.0, -155.0, 222.0))
KEEL_DOMES, KEEL_DOME_R, KEEL_DOME_Z = ((8.5, -160.5), (23.0, -160.5)), 5.5, (184.0, 205.0)  # x, y; radius; front and back
TANK_WEB = ((-5.0, -133.0, 262.0), (5.0, -63.0, 300.0))  # the web joining the two retro housings, aft
TANK_CAP = ((-10.0, -133.0, 222.0), (10.0, -63.0, 226.0))  # the bulkhead across the gap between them
KEEL_FRONT = ((-40.0, -150.0, 216.0), (40.0, -127.0, 222.0))  # the plate across the keel under the retro thrusters
BEAM_POSTS = ((26.0, -150.0, 280.0), (43.0, -137.0, 293.0))  # between the beams, each side
KEEL_PLATE = [(37.0, -65.0), (47.0, -60.5), (58.0, -56.0), (-58.0, -56.0), (-47.0, -60.5), (-37.0, -65.0)]  # under the command block
KEEL_POST = ((-4.0, -192.0, 220.0), (4.0, -154.0, 290.0))
INTERIOR_MODULES = ("bay_fore", "deck_block_top")  # T72's interior layer (Q68): the bow's open interior


def _octagon(half: tuple[float, float], cut: tuple[float, float], y: float) -> list[tuple[float, float]]:
    w, h = half
    cx, cy = cut
    return [(w, y - h + cy), (w, y + h - cy), (w - cx, y + h), (-w + cx, y + h), (-w, y + h - cy), (-w, y - h + cy), (-w + cx, y - h), (w - cx, y - h)]


def bay(s: Style) -> list[cp.Module]:
    """The launch bay: its hall lined in grey metal and lit red (no rim, no door: Q64), the fillets that make the mouth an octagon,
    the frame round it (bevelled back from a lip at its face) and a wedge fin each side out to the shield. The hall's hardpoint
    is the bow's launch point."""
    hall = bays.launch_bay("bay_fore", BAY_MOUTH, BAY_DEPTH, s, BAY_WALL, lit=True, rim=False, metal=True)
    hall = hall.transformed(np.eye(3), (0.0, BAY_Y, BAY_MOUTH_Z)).with_params(cp.BAY, craft=CRAFT, capacity=STARFURIES)
    out = [_put("bow", hall)]
    w, h, c = 0.5 * BAY_MOUTH[0], 0.5 * BAY_MOUTH[1], BAY_CORNER
    for tag, sy in (("top", 1.0), ("low", -1.0)):
        fillet = cs.prism(f"bay_fore_fillet_{tag}_r", [(w, BAY_Y + sy * h), (w - c, BAY_Y + sy * h), (w, BAY_Y + sy * (h - c))],
                          BAY_MOUTH_Z, BAY_MOUTH_Z + BAY_DEPTH, s, METAL)
        out.append(_put("bow", fillet, cp.RIGHT))
    outer, inner = _octagon(FRAME_HALF, FRAME_CUT, FRAME_Y), _octagon((w, h), (c, c), BAY_Y)
    lip = _octagon((w + 2.0, h + 2.0), (c + 1.0, c + 1.0), BAY_Y)
    ring = []
    for k in range(8):
        a, b = k, (k + 1) % 8
        pts = [(*p, z) for p, z in ((inner[a], BAY_MOUTH_Z), (inner[b], BAY_MOUTH_Z), (inner[a], FRAME_FACE_Z), (inner[b], FRAME_FACE_Z),
                                    (lip[a], FRAME_FACE_Z), (lip[b], FRAME_FACE_Z), (outer[a], FRAME_BEVEL_Z), (outer[b], FRAME_BEVEL_Z),
                                    (outer[a], FRAME_BACK_Z), (outer[b], FRAME_BACK_Z))]
        ring.append(cs.convex(f"frame_{k}", pts, s, PANEL))
    out.append(_put("bridge", cs.compound("bay_fore_frame", ring)))
    z_root, z_tip = FIN_Z
    for tag, (y0, y1) in FINS:
        pts = [(x, y, z) for x, ys, zs in ((FIN_X[0], (y0, y1), z_root), (FIN_X[1], (y0 + 0.5, y1 - 0.5), z_tip)) for y in ys for z in zs]
        out.append(_put("bridge", cs.convex(f"bay_fin_{tag}_r", pts, s, DARK), cp.RIGHT))
    return out


def decks(s: Style) -> list[cp.Module]:
    """The deck plates and blocks above the bay, the roof's hump with the bridge's window and the frames between the upper shields."""
    out = []
    for name, (y0, y1), z in DECK_PLATES:
        out.append(_put("bridge", cs.box(name, (-DECK_X, y0, z), (DECK_X, y1, DECK_BACK_Z), s, PANEL)))
    for name, (y0, y1), z in DECK_BLOCKS:
        out.append(_put("bridge", cs.box(name, (-DECK_X + 4.0, y0, z), (DECK_X - 4.0, y1, DECK_BACK_Z), s, DECKED)))
    (hx0, hy0), (hx1, hy1), (hz0, hz1) = ROOF_HUMP
    out.append(_put("bridge", cs.box("roof_hump", (hx0, hy0, hz0), (hx1, hy1, hz1), s, PANEL)))
    window = _octagon((18.0, 2.6), (1.8, 1.8), 68.0)
    out.append(_put("bridge", cs.prism("bridge_window_frame", _octagon((20.0, 3.8), (2.4, 2.4), 68.0), hz0 - 1.3, hz0 + 0.2, s, DARK, skin=cp.SKIN_NONE)))
    out.append(_put("bridge", cs.prism("bridge_window", window, hz0 - 1.7, hz0 - 1.0, s, GLASS, skin=cp.SKIN_NONE)))
    (rx, ry), (tx, ty) = SHIELD_INNER
    lean = lambda y: rx + (tx - rx) * (y - ry) / (ty - ry) - 0.5  # noqa: E731 - the upper shield's inner face at height y
    for k, (z0, z1) in enumerate(ROOF_FRAMES):
        outline = [(lean(y1), y1), (lean(ROOF_FRAME_TOP), ROOF_FRAME_TOP), (-lean(ROOF_FRAME_TOP), ROOF_FRAME_TOP), (-lean(y1), y1)]
        out.append(_put("bridge", cs.prism(f"roof_frame_{k + 1}", outline, z0, z1, s, PANEL)))
    return out


def _tank(name: str, x: float, y: float, r: float, tip_z: float, s: Style) -> cp.Module:
    """A reactant tank: a dome facing the bow on a drum running back into the command block."""
    back = COMMAND_Z[0] + 1.0
    dome = [(r - r * np.cos(a), r * np.sin(a)) for a in np.linspace(0.0, 0.5 * np.pi, 3)]
    profile = [(0.0, 0.0), *dome[1:], (back - tip_z, r), (back - tip_z, 0.0)]
    return cs.round_body(name, (x, y, tip_z), (x, y, back), profile, s, s.material("hull_panel"), sides=12, skin=cp.SKIN_FITTING)


def under_bay(s: Style) -> list[cp.Module]:
    """Under the bay: the tanks, the retro thrusters in their housings with their struts, the cross beams and the keel."""
    out = []
    for name, x, y, r, tip in TANKS:
        out.append(_put("fuel", _tank(name, x, y, r, tip, s), cp.RIGHT if x > 0.0 else cp.CENTRE))
    out.append(_put("fuel", cs.box("under_bay_block", *UNDER_BAY_BLOCK, s, DECKED)))
    out.append(_put("bridge", cs.box("command_block_lower_face", *LOWER_BLOCK, s, DECKED)))
    half_w, half_h = RETRO_HALF
    track = [(half_w * np.cos(a), (half_h - half_w) * np.sign(np.sin(a)) + half_w * np.sin(a)) for a in np.radians(np.arange(15.0, 360.0, 30.0))]
    top_back, low_back = TANK_BACK_Z
    pts = [(RETRO_X + x, RETRO_Y + y, z) for x, y in track for z in (RETRO_THROAT_Z - 0.5, top_back + (low_back - top_back) * (half_h - y) / (2.0 * half_h))]
    out.append(_put("fuel", cs.convex("tank_r", pts, s, PANEL), cp.RIGHT))
    retro = paired_hulls(retro_nozzle("retro_r", RETRO_X, RETRO_Y, (RETRO_Z, RETRO_THROAT_Z), RETRO_HALF, RETRO_WALL, s, RETRO_NARROW))
    out.append(_put("fuel", retro, cp.RIGHT))
    (x0, x1), (z0, z1) = STRUT_X, STRUT_Z
    for k, y in enumerate(STRUT_YS):
        out.append(_put("fuel", cs.box(f"nozzle_strut_{k + 1}_r", (x0, y - 1.5, z0), (x1, y + 1.5, z1), s, DARK), cp.RIGHT))
    for name, (y0, y1), x, (z0, z1) in BEAMS:
        out.append(_put("fuel", cs.box(name, (-x, y0, z0), (x, y1, z1), s, DARK)))
    out.append(_put("fuel", cs.box("tank_web", *TANK_WEB, s, PANEL)))
    out.append(_put("fuel", cs.box("tank_cap", *TANK_CAP, s, PANEL)))
    out.append(_put("fuel", cs.box("keel_front", *KEEL_FRONT, s, DARK)))
    out.append(_put("fuel", cs.box("beam_post_r", *BEAM_POSTS, s, DARK), cp.RIGHT))
    out.append(_put("bridge", cs.prism("command_keel_plate", KEEL_PLATE, COMMAND_Z[0] + 2.0, 334.0, s, DECKED)))
    r, (z0, z1) = KEEL_DOME_R, KEEL_DOME_Z
    cap = [(r * (1.0 - np.cos(a)), r * np.sin(a)) for a in np.linspace(0.0, 0.5 * np.pi, 5)]
    domes = [cs.round_body(f"keel_dome_{k + 1}", (x, y, z0), (x, y, z1), [(0.0, 0.0), *cap[1:], (z1 - z0, r), (z1 - z0, 0.0)], s, s.material("hull_dark"),
                           sides=10, skin=cp.SKIN_FITTING) for k, (x, y) in enumerate(KEEL_DOMES)]  # the kit has them on the starboard side only
    pair = cs.compound("keel_domes", domes)
    out.append(_put("bow", dataclasses.replace(pair, shapes=(col.hull(pair.name, pair.part.mesh.vertices),)), cp.LONE))
    keel = cs.box("keel_block", *KEEL_BLOCK, s, DARK)
    post = cs.box("keel_post", *KEEL_POST, s, DARK)
    # One hull each, so the bow's shapes stay inside the section's budget.
    keel, post = (dataclasses.replace(m, shapes=(col.hull(m.name, m.part.mesh.vertices),)) for m in (keel, post))
    return out + [_put("bow", keel), _put("bow", post)]


__all__ = ["INTERIOR_MODULES", "bay", "decks", "under_bay"]
