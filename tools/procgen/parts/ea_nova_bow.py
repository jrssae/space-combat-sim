"""The Nova's open-frame bow (M10-T67; Q61, Q62): what the reference shows through the armour's open front, built so the face
matches the STL's (``tools/refview/fidelity.py`` sweeps and the front depth map, ``parts/ea_nova_fidelity.FACE_MEAN_IOU`` and ``FACE_DEPTH``).

Frame and numbers as ``parts/ea_nova.py``'s. Seen from ahead, top to bottom:

* **decks**: three deck plates standing forward (y 76, 48 and 20) with the deck blocks between them set back to the
  reference's depths, the roof block with the bridge's window over the top plate;
* **the launch bay**: the octagonal hall (Babylon 5's grey bay metal lit red from inside, no glowing rim and no door, Q64) in
  a proud octagonal frame whose lower corners stand forward, a thin wedge fin from each side of the frame back to the
  vertical armour plate;
* **under the bay**: a deck block, the backing behind the tanks, the retro thrusters' radial struts;
* **the keel**: the wall behind the retro thrusters, a block under them and the keel's sloping face with its fittings.

The bay's hall and the deck blocks are the bow's open interior: T72 (Q68) gives them the interior layer, which is not built
here (:data:`INTERIOR_MODULES`).
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
from .ea_omega import DARK, DECKED, PANEL, _put

# The bay: its octagonal mouth (width, height, the corners' legs) at the frame's face, the hall back to the reference's wall.
BAY_MOUTH, BAY_CORNER = (62.0, 27.0), 6.5
BAY_MOUTH_Z, BAY_Y, BAY_WALL = 190.0, 0.5, 2.0
BAY_DEPTH = 139.0
BAY_BACK_Z = BAY_MOUTH_Z + BAY_DEPTH + BAY_WALL
# The frame: a flat lip standing proud of the mouth, bevelled back to the mouth inside and to the outer octagon outside (each
# octagon's half width and height, centre's y and corners).
LIP_IN, LIP_OUT, LIP_Y, LIP_Z = ((33.0, 15.0), (7.0, 7.0)), ((35.0, 17.0), (7.5, 7.5)), 1.0, 182.6
FRAME_HALF, FRAME_Y, FRAME_CUT = (37.0, 18.5), 1.5, (8.0, 8.0)
FRAME_BEVEL_Z, FRAME_BACK_Z = 189.5, 196.0
# The four thin probes standing forward from the lip's corners: x, the top and bottom one's y, their tips' z and radius.
PROBE_X, PROBE_YS, PROBE_TIP_Z, PROBE_R = 25.0, (17.15, -15.0), 136.5, 0.52
FINS = (("top", (3.5, 6.5)), ("low", (-6.0, -2.5)))  # the wedge fins' heights at the frame
METAL = HullRoles(side="bay_metal", deck="bay_metal", keel="bay_metal", cap="bay_metal")
# The deck blocks seen through the open front: name, x from and to, y from and to, the face's z and the back's (read off the
# reference's depth and its cuts: the blocks beside the side plates are shallow, the middle runs back into the spine).
DECKS: tuple[tuple[str, float, float, float, float, float, float], ...] = (
    ("deck_plate_top", -41.0, 41.0, 74.5, 77.5, 195.0, 320.0),
    ("deck_upper_port", -43.0, -14.0, 58.0, 74.5, 215.0, 315.0),
    ("deck_upper_mid_l", -14.0, -2.0, 58.0, 74.5, 209.0, 315.0),
    ("deck_upper_mid", -2.0, 30.0, 58.0, 74.5, 201.0, 320.0),
    ("deck_upper_mid_r", 30.0, 38.0, 58.0, 74.5, 210.0, 315.0),
    ("deck_upper_stbd", 38.0, 43.0, 58.0, 74.5, 216.0, 315.0),
    ("deck_upper_low", -52.0, 52.0, 49.5, 58.0, 216.0, 380.0),
    ("deck_plate_mid", -52.0, 52.0, 46.5, 49.5, 212.0, 380.0),
    ("deck_lower_port_edge", -54.0, -42.0, 21.5, 46.5, 214.0, 366.0),
    ("deck_lower_port", -42.0, -14.0, 21.5, 46.5, 201.0, 380.0),
    ("deck_lower_mid", -14.0, -2.0, 21.5, 46.5, 208.0, 380.0),
    ("deck_lower_stbd", -2.0, 42.0, 21.5, 46.5, 218.0, 380.0),
    ("deck_lower_stbd_edge", 42.0, 54.0, 21.5, 46.5, 219.0, 230.0),
    ("deck_plate_low", -40.0, 40.0, 18.5, 21.5, 196.0, 380.0),
    ("deck_sill", -36.0, 36.0, -21.0, -19.0, 212.0, 380.0),
    ("deck_plate_under", -38.0, 38.0, -23.0, -21.0, 193.0, 380.0),
    ("deck_under_port_edge", -54.0, -42.0, -34.0, -22.0, 217.0, 366.0),
    ("deck_under_port_in", -42.0, -30.0, -34.0, -22.0, 203.0, 380.0),
    ("deck_under_mid_l", -30.0, -26.0, -34.0, -22.0, 217.0, 380.0),
    ("deck_under_mid", -26.0, -18.0, -34.0, -22.0, 206.0, 380.0),
    ("deck_under_stbd_l", -18.0, -12.0, -34.0, -22.0, 203.0, 380.0),
    ("deck_under_stbd", -12.0, 20.0, -34.0, -22.0, 217.0, 380.0),
    ("deck_under_stbd_in", 20.0, 32.0, -34.0, -22.0, 205.0, 380.0),
    ("deck_under_stbd_out", 32.0, 42.0, -34.0, -22.0, 217.0, 380.0),
    ("deck_under_stbd_edge", 42.0, 54.0, -34.0, -22.0, 217.0, 230.0),
    ("tank_backing_port_edge", -54.0, -42.0, -52.0, -34.0, 219.0, 366.0),
    ("tank_backing", -42.0, 42.0, -52.0, -34.0, 219.0, 375.0),
    ("tank_backing_stbd_edge", 42.0, 54.0, -52.0, -34.0, 219.0, 243.0),
)
# The deck plates' ends beside the frame, sloping back to the armour: name, y from and to, x from and to, the face's z at each.
PLATE_WINGS = (("deck_plate_low_wing", (18.5, 21.5), (40.0, 54.0), (196.0, 216.0)), ("deck_plate_under_wing", (-23.0, -21.0), (38.0, 54.0), (197.0, 216.0)))
# The bulkhead beside the hall, seen past the strake (x from and to, y from and to, z from and to).
SIDE_BULKHEAD = ((36.0, 54.0), (-19.0, 19.0), (331.0, 336.0))
# The upper side blocks narrow with the upper armour plate leaning in: their outer edge at the plate's root and at the deck plate.
UPPER_EDGE = ((52.0, 62.5), (43.0, 74.5))
ROOF_BLOCK = ([(-36.0, 77.5), (36.0, 77.5), (33.0, 85.0), (-33.0, 85.0)], (223.0, 320.0))
ROOF_HUMP = ((14.0, 28.0), (84.5, 90.0))  # a raised hump each side of the roof block: x from and to, y from and to
# Small fittings: the boxes either side under the bay's frame and the keel block; name, low corner, high corner.
FITTINGS: tuple[tuple[str, tuple[float, float, float], tuple[float, float, float]], ...] = ()
KEEL_BLOCK = ((-17.0, -150.0, 210.0), (-1.0, -128.0, 240.0))
KEEL_SPHERES = ((4.0, -144.0), (20.0, -144.0))  # x, y; their fronts at the reference's 176 m
SPHERE_R, SPHERE_FRONT_Z = 5.0, 176.0
# The keel below the retro thrusters: the wall behind them, the block under them, the sloping face (y, its face's z).
KEEL_WALL = ((-52.0, -106.0), 257.0)
KEEL_BOX = ((-106.0, -128.0), 218.0)
KEEL_SLOPE = ((-128.0, 219.0), (-171.0, 262.0))
KEEL_BACK_Z = 283.0
KEEL_KNEE_Y = -59.3  # where the lower plates start leaning in
# The pipes running up and aft from the keel's block towards the spine: their x, their ends (y, z) and radius.
KEEL_PIPES_X, KEEL_PIPE_R = (5.5, 27.0), 2.5
KEEL_PIPE_PATH = ((-118.0, 283.0), (-112.0, 323.0), (-58.0, 370.0))  # (y, z): up out of the block, then up and aft
# The retro thrusters' radial struts on each side: y, and the strut's inner and outer x with its z at each.
STRUTS = (-60.0, -68.0, -92.0, -100.0)
STRUT_X, STRUT_Z, STRUT_R = (26.0, 37.0), (184.0, 190.0), 1.1
RETRO_LIP_BACK, RETRO_RIM = 8.0, 1.5  # the retro thrusters' rounded lips: how far back of the mouth their outer edge stands, the flat rim's width
INTERIOR_MODULES = ("bay_fore", *(name for name, *_ in DECKS))  # T72's interior layer (Q68): the bow's open interior


def _octagon(half: tuple[float, float], cut: tuple[float, float], y: float) -> list[tuple[float, float]]:
    w, h = half
    cx, cy = cut
    return [(w, y - h + cy), (w, y + h - cy), (w - cx, y + h), (-w + cx, y + h), (-w, y + h - cy), (-w, y - h + cy), (-w + cx, y - h), (w - cx, y - h)]


def bay(s: Style) -> list[cp.Module]:
    """The launch bay: its hall lined in grey metal and lit red (``launch_bay(metal=True)``, no rim, no door), the fillets that make
    the mouth an octagon, the octagonal frame round it (a lip at the mouth bevelled back) and a wedge fin each side, and the thin probes standing forward from its corners."""
    hall = bays.launch_bay("bay_fore", BAY_MOUTH, BAY_DEPTH, s, BAY_WALL, lit=True, rim=False, metal=True)
    out = [_put("bow", hall.transformed(np.eye(3), (0.0, BAY_Y, BAY_MOUTH_Z)))]
    w, h, c = 0.5 * BAY_MOUTH[0], 0.5 * BAY_MOUTH[1], BAY_CORNER
    for tag, sy in (("top", 1.0), ("low", -1.0)):
        fillet = cs.prism(f"bay_fore_fillet_{tag}_r", [(w, BAY_Y + sy * h), (w - c, BAY_Y + sy * h), (w, BAY_Y + sy * (h - c))],
                          BAY_MOUTH_Z, BAY_MOUTH_Z + BAY_DEPTH, s, METAL)
        out.append(_put("bow", fillet, cp.RIGHT))
    outer, inner = _octagon(FRAME_HALF, FRAME_CUT, FRAME_Y), _octagon((w, h), (c, c), BAY_Y)
    lip_in, lip_out = _octagon(*LIP_IN, LIP_Y), _octagon(*LIP_OUT, LIP_Y)
    ring = []
    for k in range(8):
        a, b = (k, (k + 1) % 8)
        pts = [(*p, z) for p, z in ((inner[a], BAY_MOUTH_Z), (inner[b], BAY_MOUTH_Z), (lip_in[a], LIP_Z), (lip_in[b], LIP_Z), (lip_out[a], LIP_Z),
                                    (lip_out[b], LIP_Z), (outer[a], FRAME_BEVEL_Z), (outer[b], FRAME_BEVEL_Z))]
        # The frame's back slants out from the mouth's edge, so the hall's walls alone line the mouth (no faces shared, no flicker).
        pts += [(*p, FRAME_BACK_Z) for p in (outer[a], outer[b])]
        ring.append(cs.convex(f"frame_{k}", pts, s, PANEL))
    out.append(_put("bridge", cs.compound("bay_fore_frame", ring)))
    for tag, y in zip(("top", "low"), PROBE_YS, strict=True):
        out.append(_put("bridge", cs.rod(f"bay_fore_probe_{tag}_r", (PROBE_X, y, LIP_Z), (PROBE_X, y, PROBE_TIP_Z), PROBE_R, s), cp.RIGHT))
    for tag, (y0, y1) in FINS:
        fin = cs.convex(f"bay_fin_{tag}_r", [(x, y, z) for x, ys, zs in ((FRAME_HALF[0] - 0.5, (y0, y1), (185.0, 214.0)), (54.0, (y0 + 0.5, y1 - 0.5), (199.0, 214.0)))
                                            for y in ys for z in zs], s, DARK)
        out.append(_put("bridge", fin, cp.RIGHT))
    return out


def decks(s: Style) -> list[cp.Module]:
    """The decks seen through the open front, each block from its face back to the spine; the roof block with the bridge's
    window in its face."""
    out = []
    for name, x0, x1, y0, y1, z, back in DECKS:
        roles = PANEL if "plate" in name else DECKED
        section = "bow" if name.startswith("tank_backing") else "bridge"
        if name == "deck_upper_stbd":  # its outer edge follows the leaning plate
            (ax, ay), (bx, by) = UPPER_EDGE
            m = cs.prism(name, [(x0, y0), (ax, y0), (ax, ay), (bx, by), (x0, y1)], z, back, s, roles)
        elif name == "deck_upper_port":
            (ax, ay), (bx, by) = UPPER_EDGE
            m = cs.prism(name, [(-ax, y0), (x1, y0), (x1, y1), (-bx, by), (-ax, ay)], z, back, s, roles)
        else:
            m = cs.box(name, (x0, y0, z), (x1, y1, back), s, roles)
        out.append(_put(section, m, cp.LONE if x0 != -x1 else cp.CENTRE))
    outline, (z0, z1) = ROOF_BLOCK
    roof = cs.prism("bridge_roof", outline, z0, z1, s, PANEL)
    frame = cs.prism("bridge_window_frame", _octagon((26.0, 4.5), (2.5, 2.5), 83.8), z0 - 1.3, z0 + 0.2, s, DARK, skin=cp.SKIN_NONE)
    glass = cs.prism("bridge_window", _octagon((24.0, 3.2), (2.0, 2.0), 83.8), z0 - 1.7, z0 - 1.0, s,
                     HullRoles(side="canopy_glass", deck="canopy_glass", keel="canopy_glass"), skin=cp.SKIN_NONE)
    (hx0, hx1), (hy0, hy1) = ROOF_HUMP
    hump = cs.box("bridge_roof_hump_r", (hx0, hy0, z0 + 1.0), (hx1, hy1, z1 - 10.0), s, PANEL)
    out += [_put("bridge", m) for m in (roof, frame, glass)] + [_put("bridge", hump, cp.RIGHT)]
    for name, lo, hi in FITTINGS:
        out.append(_put("bow", cs.box(name, lo, hi, s, DARK), cp.RIGHT))
    back = 380.0
    for name, (y0, y1), (x0, x1), (z0, z1) in PLATE_WINGS:
        wing = cs.convex(name + "_r", [(x, y, z) for x, zf in ((x0, z0), (x1, z1)) for y in (y0, y1) for z in (zf, back)], s, PANEL)
        out.append(_put("bridge", wing, cp.RIGHT))
    (bx0, bx1), (by0, by1), (bz0, bz1) = SIDE_BULKHEAD
    out.append(_put("bridge", cs.box("side_bulkhead_r", (bx0, by0, bz0), (bx1, by1, bz1), s, DECKED), cp.RIGHT))
    return out


def struts(s: Style) -> list[cp.Module]:
    """The retro thrusters' radial struts out to the armour, either side of the pair."""
    (x0, x1), (z0, z1) = STRUT_X, STRUT_Z
    return [_put("fuel", cs.rod(f"bow_strut_{k + 1}_r", (x0, y, z0), (x1, y, z1), STRUT_R, s), cp.RIGHT) for k, y in enumerate(STRUTS)]


def retro_lip(name: str, x: float, y: float, z: float, half: tuple[float, float], wall: float, s: Style) -> cp.Module:
    """A retro thruster's lip, rounded off from the mouth at ``z`` back to the nozzle's outer wall (the reference's), so the
    nozzle behind it starts ``RETRO_LIP_BACK`` further aft. ``half`` and ``wall`` as ``ea_omega.retro_nozzle``'s."""
    half_w, half_h = half

    def outline(r: float) -> list[tuple[float, float]]:
        arc = np.linspace(0.0, np.pi, 7)  # every other corner of the nozzle's, so the two meet
        top, low = y + half_h - half_w, y - half_h + half_w
        return [(x + r * np.cos(a), top + r * np.sin(a)) for a in arc] + [(x - r * np.cos(a), low - r * np.sin(a)) for a in arc]

    outer, rim, mouth, n = outline(half_w), outline(half_w - wall + RETRO_RIM), outline(half_w - wall), 14
    back = z + RETRO_LIP_BACK
    ring = [cs.convex(f"{name}_{k}", [(*mouth[k], z), (*mouth[(k + 1) % n], z), (*rim[k], z), (*rim[(k + 1) % n], z), (*mouth[k], back),
                                      (*mouth[(k + 1) % n], back), (*outer[k], back), (*outer[(k + 1) % n], back)], s, PANEL) for k in range(n)]
    return cs.compound(name, ring)


def keel(s: Style, inner) -> list[cp.Module]:  # noqa: ANN001 - inner(y): the lower plates' inner face's x at height y
    """The keel between the lower plates: the wall behind the retro thrusters, the block under them and the sloping face
    down to the keel, with a block and two small domes on it, and the pipes from the block up to the spine."""
    (ya, yb), wall_z = KEEL_WALL
    (yc, yd), box_z = KEEL_BOX
    (ye, ze), (yf, zf) = KEEL_SLOPE

    def across(y: float, z: float, trim: float = 0.5) -> list[tuple[float, float, float]]:
        x = inner(y) - trim
        return [(x, y, z), (-x, y, z)]

    wall = cs.convex("keel_wall", [p for y in (ya, KEEL_KNEE_Y, yb) for z in (wall_z, KEEL_BACK_Z) for p in across(y, z)], s, DECKED)
    pipes = [_put("bow", cs.rod(f"keel_pipe_{k + 1}{'ab'[j]}_r", (x, *a), (x, *b), KEEL_PIPE_R, s, "hull_dark"), cp.RIGHT)
             for k, x in enumerate(KEEL_PIPES_X) for j, (a, b) in enumerate(zip(KEEL_PIPE_PATH, KEEL_PIPE_PATH[1:]))]
    block = cs.convex("keel_box", [p for y in (yc, yd) for z in (box_z, KEEL_BACK_Z) for p in across(y, z)], s, DECKED)
    slope = cs.convex("keel_wedge", [*across(ye, ze), *across(yf, zf), *across(ye, KEEL_BACK_Z), *across(yf, KEEL_BACK_Z)], s, DECKED)
    lump = cs.box("keel_block", *KEEL_BLOCK, s, DARK)
    half = [(SPHERE_R * np.sin(a), SPHERE_R * (1.0 - np.cos(a))) for a in np.linspace(0.0, np.pi, 9)]
    domes = [cs.round_body(f"keel_dome_{k + 1}", (x, y, SPHERE_FRONT_Z), (x, y, SPHERE_FRONT_Z + 2.0 * SPHERE_R),
                           [(d, r) for r, d in half], s, s.material("hull_dark"), sides=12, skin=cp.SKIN_FITTING)
             for k, (x, y) in enumerate(KEEL_SPHERES)]
    # One hull a dome, so the bow's shapes stay within the section's budget unmerged.
    domes = [dataclasses.replace(d, shapes=(col.hull(d.name, d.part.mesh.vertices),)) for d in domes]
    return [_put("bow", m) for m in (wall, block, slope)] + [_put("bow", m, cp.LONE) for m in (lump, *domes)] + pipes


__all__ = ["BAY_BACK_Z", "BAY_CORNER", "BAY_DEPTH", "BAY_MOUTH", "BAY_MOUTH_Z", "BAY_WALL", "BAY_Y", "DECKS", "INTERIOR_MODULES", "bay", "decks",
           "keel", "retro_lip", "struts"]
