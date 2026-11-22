"""The Omega-class destroyer's structure (M10-T21): the parts measured off the reference model, on the capital library.

Authored frame: x to starboard, y up from the spine's axis, z aft from the tip of the sensor boom; 1 714.3 m long
(docs/assets-capital.md, "M10 lengths (T01)"). Numbers are the reference's own (``references/EA Omega Destroyer.stl`` at
that length, its sections cut with ``tools/refview/sections.py``); docs/design-references.md describes the ship.

Bow to stern:

* **bow** (0 to 358 m): the sensor boom (port and low, one side only), the command block (the spine's octagon, the
  bridge's window in its fore face), the launch bay through it (its housing standing out of the fore face as the
  reference's tube, the hall reaching back 136 m), two armour shields standing off its flanks in three leaning
  panels, a beam pod on each shield, the reactant spheres slung under the block and the two oval retro thrusters below
  them, masts;
* **spines** (358 to 512 m and 918 to 1 242 m): a girder, not a tube: a core, a waist, side rails and four ears;
* **collars** (r 84 m) either side of the rotating section, on an axle through it;
* **rotating section** (555 to 879 m): two arms on a hub, each a body, a neck and a rim cap, a panelled band round the
  rim's outer face. It is built square (arms to port and starboard) in its own piece; the reference has it turned 45
  degrees;
* **engine housing** (1 242 to 1 408 m): a solid core flaring in width, a skirt of stand-off plates flaring in height,
  three ribs and a strake on each flank;
* **engines**: four nacelles in a square, a boom between each side's pair ending in a blade, tail plates above and below.

Every function returns modules already named for their damage section and side; ``assets/ea_omega.py`` adds the weapons,
bays, lights and the section table.
"""

from __future__ import annotations

import dataclasses

import numpy as np

from ..styles import Style
from . import capital as cp
from . import capital_bays as bays
from . import capital_fittings as fittings
from . import capital_solids as cs
from .capital_hull import HullRoles

LENGTH_M = 1714.3
# The spine's cross-section, the octagon the command block and the housing's front share: half width, half height, and the
# shallow cut of its corners (across, up).
SPINE_W, SPINE_H, SPINE_CUT = 62.75, 61.6, (29.25, 11.6)
COMMAND_Z = (207.0, 358.0)
NOTCH_Z = 334.0
TANK_END_Z = 290.0  # the reactant tanks run aft under the command block to here  # from here aft the command block's roof and keel carry the spine's channel
FORE_SPINE_Z = (356.0, 508.0)
AFT_SPINE_Z = (920.0, 1225.0)
RAILS_END_Z = 1085.0  # the aft spine's side rails stop here
COLLAR_R, AXLE_R = 84.0, 44.8
FORE_COLLAR_Z, AFT_COLLAR_Z = (506.0, 552.0), (884.0, 924.0)
DRUM_Z = (555.2, 879.0)
DRUM_PIVOT = (0.0, 0.0, 717.1)
DRUM_REACH = 310.0  # the rim's outer face, from the axis
HOUSING_Z = (1242.0, 1408.0)
HOUSING_W, HOUSING_H = 102.0, 101.0  # the skirt's half width and half height at its stern edge
CORE_END_Z = 1385.0
CORE_BULGE = (1300.0, 70.0, 66.0)  # where the core is tallest: z, its half height there and at its end
ENGINE_START_Z = 1310.0
ENGINE_XY = (52.0, 45.5)
ENGINE_MOUTH_Z = 1660.0
LUG_Z = (1409.0, 1452.0)
# The one launch bay, in the command block's fore face above the retro thrusters (the maintainer, 2026-11-21): the
# reference's octagonal hall, open from 182 to about 320 m, its housing standing out of the head as the reference's tube.
# A Starfury is 11 m across and 7 m tall.
BAY_MOUTH, BAY_DEPTH, BAY_WALL = (74.0, 34.0), 134.0, 2.0
BAY_MOUTH_Z, BAY_Y = 182.0, 0.0
BAY_BACK_Z = BAY_MOUTH_Z + BAY_DEPTH + BAY_WALL
BAY_CORNER = 7.0  # the fillets in the hall's corners that make its mouth the reference's octagon
STARFURIES = 32
CRAFT = "starfury_ally"  # the catalogue's pooled Starfury (data/capitals/loadouts.json, launches)
# The retro thrusters' oval nozzles: open from their mouths to the throat, as the reference's.
RETRO_Z, RETRO_THROAT_Z, RETRO_WALL, RETRO_NARROW = 168.0, 258.0, 6.0, 1.0

DECKED = HullRoles()
PLAIN = HullRoles(deck="hull", keel="hull")  # a part with no deck: its top and bottom wear the side's paint
DARK = HullRoles(side="hull_dark", deck="hull_dark", keel="hull_dark")
PANEL = HullRoles(side="hull_panel", deck="hull_panel", keel="hull_panel")


def _octagon(w: float, h: float, cut: tuple[float, float] = SPINE_CUT) -> list[tuple[float, float]]:
    cx, cy = cut
    return [(w, -h + cy), (w, h - cy), (w - cx, h), (-w + cx, h), (-w, h - cy), (-w, -h + cy), (-w + cx, -h), (w - cx, -h)]


def _ring(outline: list[tuple[float, float]], z: float) -> list[tuple[float, float, float]]:
    return [(x, y, z) for x, y in outline]


def _flip_y(m: cp.Module, name: str) -> cp.Module:
    """A part's mirror image below the axis, under a new name."""
    turned = m.transformed(np.diag([1.0, -1.0, 1.0]))
    return dataclasses.replace(turned, part=turned.part.renamed(name), shapes=tuple(q.renamed(f"{name}_{k}" if len(turned.shapes) > 1 else name) for k, q in enumerate(turned.shapes)))


def _put(section: str, m: cp.Module, side: str = cp.CENTRE) -> cp.Module:
    return m.in_section(section).on_side(side)


def _clip(outline: list[tuple[float, float]], keep) -> list[tuple[float, float]]:
    """The part of a convex outline where ``keep(p)`` is not negative (``keep`` linear in p)."""
    out: list[tuple[float, float]] = []
    for a, b in zip(outline, outline[1:] + outline[:1], strict=True):
        fa, fb = keep(a), keep(b)
        if fa >= 0.0:
            out.append(a)
        if (fa >= 0.0) != (fb >= 0.0):
            t = fa / (fa - fb)
            out.append((a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])))
    return out


def around_hole(name: str, outline: list[tuple[float, float]], half_w: float, ys: tuple[float, float], z: tuple[float, float], s: Style,
                roles: HullRoles, section: str) -> list[cp.Module]:
    """A convex block from ``z[0]`` to ``z[1]`` with a rectangular hole through it (``half_w`` either side of the axis, from
    ``ys[0]`` to ``ys[1]``) for a bay's housing: the part above the hole, below it and the starboard part beside it (each
    only where the block reaches past the hole)."""
    y0, y1 = ys
    top = _clip(outline, lambda p: p[1] - y1)
    low = _clip(outline, lambda p: y0 - p[1])
    side = _clip(_clip(_clip(outline, lambda p: p[0] - half_w), lambda p: y1 - p[1]), lambda p: p[1] - y0)

    def area(pts: list[tuple[float, float]]) -> float:
        return 0.5 * abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1], strict=True))) if len(pts) > 2 else 0.0

    pieces = ((f"{name}_top", top, cp.CENTRE), (f"{name}_low", low, cp.CENTRE), (f"{name}_side_r", side, cp.RIGHT))
    return [_put(section, cs.prism(n, pts, *z, s, roles), side_of) for n, pts, side_of in pieces if area(pts) > 0.01]


def fore_bay(s: Style, mouth: tuple[float, float], depth: float, corner: float, at: tuple[float, float, float], section: str = "bow") -> list[cp.Module]:
    """The one forward-facing launch bay, its mouth at ``at`` facing the bow, in the hull's paint and lit red (the
    maintainer, 2026-11-21), and the fillets (legs ``corner``) that make its mouth an octagon. Its hardpoint is the first."""
    x, y, z = at
    bay = bays.launch_bay("bay_fore", mouth, depth, s, BAY_WALL, lit=True).transformed(np.eye(3), at)
    w, h = 0.5 * mouth[0], 0.5 * mouth[1]
    out = [_put(section, bay)]
    for tag, sy in (("top", 1.0), ("low", -1.0)):
        fillet = cs.prism(f"bay_fore_fillet_{tag}_r", [(x + w, y + sy * h), (x + w - corner, y + sy * h), (x + w, y + sy * (h - corner))], z, z + depth, s, PLAIN)
        out.append(_put(section, fillet, cp.RIGHT))
    return out


def retro_nozzle(name: str, x: float, y: float, z: tuple[float, float], half: tuple[float, float], wall: float, s: Style, narrow: float = 0.0) -> cp.Module:
    """An oval retro thruster's nozzle (the reference's): a racetrack wall open at its mouth (``z[0]``), its opening
    ``narrow`` metres shorter at each end by the throat, and a dark throat plate closing it at ``z[1]``. ``half`` is the
    outline's half width and half height."""
    half_w, half_h = half

    def outline(r: float, inset: float = 0.0) -> list[tuple[float, float]]:
        arc = np.linspace(0.0, np.pi, 13)
        top, low = y + half_h - half_w - inset, y - half_h + half_w + inset  # the end arcs' centres
        return [(x + r * np.cos(a), top + r * np.sin(a)) for a in arc] + [(x - r * np.cos(a), low - r * np.sin(a)) for a in arc]

    outer, mouth, throat = outline(half_w), outline(half_w - wall), outline(half_w - wall, narrow)
    n = len(outer)
    ring = [cs.convex(f"{name}_{k}", [(*p, zz) for zz in z for p in (outer[k], outer[(k + 1) % n])]
                      + [(*mouth[k], z[0]), (*mouth[(k + 1) % n], z[0]), (*throat[k], z[1]), (*throat[(k + 1) % n], z[1])], s, PANEL) for k in range(n)]
    plate = cs.prism(f"{name}_throat", throat, z[1] - 2.0, z[1], s, HullRoles(side="nozzle", deck="nozzle", keel="nozzle", cap="nozzle"),
                     skin=cp.SKIN_FITTING)
    return cs.compound(name, [*ring, plate])


# --- the bow -------------------------------------------------------------------------------------------------------------
MARK_HEIGHT_M = 40.0  # the show's letter stands about a sixth of the shield's height
MARK_AT = 0.2  # how far up the lower panel the letter's centre sits, from its bottom edge


def shield_mark(x: float, top: tuple[float, float, float], bottom: tuple[float, float, float]) -> cp.Hardpoint:
    """The name letter in large white block print at the bottom of the shield (the show's), on the lower panel's outer face:
    ``top`` and ``bottom`` are the panel's two edges at the shield's face (y, and z from, z to, with the bottom edge leaning in)."""
    (ty, tz0, tz1), (by, bz0, bz1) = top, bottom
    x_bottom = 26.0
    along = np.array([x - x_bottom, ty - by, 0.5 * (tz0 + tz1) - 0.5 * (bz0 + bz1)])  # bottom edge to top edge, mid to mid
    normal = np.cross([0.0, 0.0, 1.0], np.array([x_bottom - x, by - ty, bz0 - tz0]))  # an edge of the panel with the along-z edge
    normal = normal / np.linalg.norm(normal) * (1.0 if normal[0] > 0.0 else -1.0)
    up = np.array([0.0, 1.0, 0.0]) - normal[1] * normal
    at = np.array([x_bottom, by, 0.5 * (bz0 + bz1)]) + MARK_AT * along
    return fittings.hull_mark("mark_initial_r", at, normal, up / np.linalg.norm(up), MARK_HEIGHT_M)


RENEGADE_RED = (0.78, 0.09, 0.07)
X_HEIGHT_M = 34.0


def renegade_xs() -> dict[str, cp.Hardpoint]:
    """The renegades' small red X paint marks (M10-T02), shown only on a renegade ship: one on each shield's vertical panel and
    one on the command block's roof. Keyed by the module that carries them."""
    def x(name: str, at: tuple[float, float, float], normal: tuple[float, float, float], up: tuple[float, float, float]) -> cp.Hardpoint:
        return fittings.hull_mark(name, at, normal, up, X_HEIGHT_M, colour=RENEGADE_RED, text="X", only_faction="renegades")
    return {"shield_mid_r": x("mark_x_r", (68.0, 0.0, 275.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
            "command_roof": x("mark_x_roof", (0.0, 62.5, 238.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0))}


def shields(s: Style) -> list[cp.Module]:
    """The starboard armour shield: a vertical panel and two leaning in above and below it, 5 m thick."""
    thick, x = 4.0, 68.0
    inward = (-1.0, 0.0, 0.0)
    mid = cs.slab("shield_mid_r", [(x, 57.4, 193.0), (x, 57.4, 358.0), (x, -55.6, 358.0), (x, -55.6, 193.0)], thick, inward, s, PLAIN)
    upper = cs.slab("shield_upper_r", [(x, 57.4, 193.0), (x, 57.4, 358.0), (43.5, 95.4, 307.0), (43.5, 95.4, 214.0)], thick, inward, s, PLAIN)
    lower = cs.slab("shield_lower_r", [(x, -55.6, 193.0), (x, -55.6, 358.0), (26.0, -195.6, 270.0), (26.0, -195.6, 214.0)], thick, inward, s, PLAIN)
    mid = dataclasses.replace(mid, hardpoints=(renegade_xs()["shield_mid_r"],))
    lower = dataclasses.replace(lower, hardpoints=(shield_mark(x, (-55.6, 193.0, 358.0), (-195.6, 214.0, 270.0)),))
    pod = cs.convex("beam_pod_r", [(px, py, pz) for px, c in ((68.0, 0.0), (88.0, 4.0)) for py in (-22.0 + c, 22.0 - c) for pz in (205.0 + c, 247.0 - c)],
                    s, DARK, skin=cp.SKIN_FITTING)
    return [_put("bow", m, cp.RIGHT) for m in (mid, upper, lower, pod)]


def command_block(s: Style) -> list[cp.Module]:
    """The command section between the shields: the octagon, its roof slab, the head with the bridge's window, the launch
    bay through them in its tube (:func:`fore_bay`) and a strake along each flank."""
    z0, z1 = COMMAND_Z
    hw, hh = 0.5 * BAY_MOUTH[0] + BAY_WALL, 0.5 * BAY_MOUTH[1] + BAY_WALL
    ys = (BAY_Y - hh, BAY_Y + hh)
    block = cs.prism("command_block", _octagon(SPINE_W, SPINE_H), BAY_BACK_Z - 0.5, NOTCH_Z, s, DECKED)
    fore = around_hole("command_block_fore", _octagon(SPINE_W, SPINE_H), hw, ys, (z0, BAY_BACK_Z), s, DECKED, "bridge")
    stripe = HullRoles(side="stripe", deck="stripe", keel="stripe", cap="stripe")
    head = around_hole("command_head", [(57.0, -45.0), (57.0, 50.0), (-57.0, 50.0), (-57.0, -45.0)], hw, ys, (195.0, z0 + 1.0), s, stripe, "bridge")
    waist = cs.box("command_aft", (-SPINE_W, -47.0, NOTCH_Z - 1.0), (SPINE_W, 47.0, z1), s, PLAIN)
    shoulder = cs.prism("command_shoulder_top_r", [(20.0, 46.0), (SPINE_W, 46.0), (SPINE_W, SPINE_H - SPINE_CUT[1]), (SPINE_W - SPINE_CUT[0], SPINE_H),
                                                   (26.0, SPINE_H)], NOTCH_Z - 1.0, z1, s, DECKED)
    roof = cs.box("command_roof", (-57.0, 55.5, 214.0), (57.0, 62.5, 262.0), s, PANEL)
    # The bridge's window in the head's face, above the bay's tube.
    frame = cs.prism("bridge_window_frame", _octagon(27.0, 10.0, (6.0, 6.0)), 194.2, 195.5, s, DARK, skin=cp.SKIN_NONE)
    glass = cs.prism("bridge_window", _octagon(24.0, 7.5, (5.0, 5.0)), 193.8, 194.5, s,
                     HullRoles(side="canopy_glass", deck="canopy_glass", keel="canopy_glass"), skin=cp.SKIN_NONE)
    frame, glass = (m.transformed(np.eye(3), (0.0, 35.0, 0.0)) for m in (frame, glass))
    strake = cs.prism("command_strake_r", [(SPINE_W - 1.0, 8.0), (72.0, 3.5), (72.0, -3.5), (SPINE_W - 1.0, -8.0)], 200.0, 372.0, s, DARK)
    sided = (strake, shoulder, _flip_y(shoulder, "command_shoulder_low_r"))
    roof = dataclasses.replace(roof, hardpoints=(renegade_xs()["command_roof"],))
    bay, *fillets = fore_bay(s, BAY_MOUTH, BAY_DEPTH, BAY_CORNER, (0.0, BAY_Y, BAY_MOUTH_Z))
    bay = bay.with_params(cp.BAY, craft=CRAFT, capacity=STARFURIES)
    return ([_put("bridge", m) for m in (block, waist, roof, frame, glass)] + fore + head + [bay, *fillets]
            + [_put("bridge", m, cp.RIGHT) for m in sided])


def tankage(s: Style) -> list[cp.Module]:
    """Under the command block: three reactant spheres at its lower front edge, the two oval retro thrusters below them
    (each an open nozzle ahead of its tank), the cross beam that carries them and the keel pod where the shields meet."""
    def sphere(name: str, centre: tuple[float, float, float], r: float) -> cp.Module:
        arc = [(r - r * np.cos(a), r * np.sin(a)) for a in np.linspace(0.0, np.pi, 9)]
        arc[0], arc[-1] = (0.0, 0.0), (2.0 * r, 0.0)
        return cs.round_body(name, (centre[0], centre[1], centre[2] - r), (centre[0], centre[1], centre[2] + r), arc, s,
                             s.material("hull_panel"), sides=12, skin=cp.SKIN_FITTING)

    racetrack = [(14.0 * np.cos(a), 17.0 * np.sign(np.sin(a)) + 14.0 * np.sin(a)) for a in np.radians(np.arange(15.0, 360.0, 30.0))]
    outline = [(18.5 + x, -95.0 + y) for x, y in racetrack]
    tip = [(18.5 + dx, y, TANK_END_Z + 20.0) for dx in (-3.0, 3.0) for y in (-104.0, -120.0)]  # the aft end slopes back to a low point
    tank = cs.convex("tank_r", _ring(outline, RETRO_THROAT_Z - 0.5) + _ring(outline, TANK_END_Z) + tip, s, PANEL)
    retro = retro_nozzle("retro_r", 18.5, -95.0, (RETRO_Z, RETRO_THROAT_Z), (14.0, 31.0), RETRO_WALL, s, RETRO_NARROW)
    beam = cs.box("tank_beam", (-40.0, -146.0, 214.0), (40.0, -128.0, TANK_END_Z), s, DARK)
    keel = cs.box("keel_pod", (-12.0, -207.0, 200.0), (12.0, -194.0, 278.0), s, DARK)
    return [_put("fuel", sphere("sphere_r", (42.0, -47.6, 190.0), 14.0), cp.RIGHT), _put("fuel", sphere("sphere_mid", (0.0, -50.0, 190.0), 11.0)),
            _put("fuel", tank, cp.RIGHT), _put("fuel", retro, cp.RIGHT), _put("fuel", beam), _put("bow", keel)]


def aerials(s: Style) -> list[cp.Module]:
    """The sensor boom (port and low: the reference has one) and the masts."""
    boom_at = (-28.7, -137.3)
    profile = [(0.0, 0.0), (0.0, 1.0), (50.0, 1.0), (52.0, 2.2), (84.0, 2.2), (90.0, 8.0), (108.0, 8.0), (112.0, 5.0), (145.0, 5.0), (162.0, 8.6),
               (207.0, 8.6), (207.0, 0.0)]
    boom = cs.round_body("sensor_boom", (*boom_at, 0.0), (*boom_at, 207.0), profile, s, s.material("hull_dark"), sides=10,
                         creases={2, 3, 4, 5, 6, 7, 8, 9, 10}, skin=cp.SKIN_FITTING)
    out = [_put("bow", boom, cp.LONE),
           _put("bridge", cs.rod("mast_dorsal", (0.0, 62.0, 240.0), (0.0, 170.0, 240.0), 1.7, s)),
           _put("bow", cs.rod("mast_ventral_a", (0.0, -205.0, 229.0), (0.0, -308.0, 229.0), 1.2, s)),
           _put("bow", cs.rod("mast_ventral_b", (0.0, -205.0, 252.0), (0.0, -261.0, 252.0), 1.2, s)),
           _put("bow", cs.rod("keel_rod", (0.0, -199.0, 200.0), (0.0, -199.0, 88.0), 1.2, s)),
           _put("bow", cs.rod("yard_r", (66.0, 0.0, 357.0), (103.0, 0.0, 357.0), 0.9, s), cp.RIGHT),
           _put("bow", cs.rod("aerial_high", (42.0, 90.0, 205.0), (42.0, 90.0, 100.0), 1.0, s), cp.LONE),
           _put("bow", cs.rod("aerial_low", (42.0, 83.0, 205.0), (42.0, 83.0, 113.0), 1.0, s), cp.LONE)]
    return out


# --- the spines and the collars ------------------------------------------------------------------------------------------
def spine(s: Style, name: str, section: str, z: tuple[float, float], rails: bool = True, strake: tuple[float, float] | None = None) -> list[cp.Module]:
    """A spine's girder from ``z[0]`` to ``z[1]``: the core, the waist, an ear at each corner (a post and a fin) and, with
    ``rails``, a rail above and below the waist on each side. ``strake`` (z from, to) adds a short strake on each flank."""
    z0, z1 = z
    core = cs.box(f"{name}_core", (-39.0, -45.5, z0), (39.0, 45.5, z1), s, DECKED)
    waist = cs.box(f"{name}_waist", (-50.0, -18.0, z0), (50.0, 18.0, z1), s, DARK)
    rail = cs.box(f"{name}_rail_top_r", (44.0, 18.0, z0), (50.0, 46.0, z1), s, PLAIN)
    post = cs.prism("post", [(18.0, 45.0), (39.0, 45.0), (39.0, 62.0), (25.0, 62.0)], z0, z1, s, DECKED)
    fin = cs.prism("fin", [(34.0, 62.0), (39.0, 50.0), (63.0, 50.5)], z0, z1, s, DECKED)
    ear = cs.compound(f"{name}_ear_top_r", [post, fin])
    out = [_put(section, core), _put(section, waist)]
    for m, low in ((ear, f"{name}_ear_low_r"), *(((rail, f"{name}_rail_low_r"),) if rails else ())):
        out += [_put(section, m, cp.RIGHT), _put(section, _flip_y(m, low), cp.RIGHT)]
    if strake is not None:
        out.append(_put(section, cs.prism(f"{name}_strake_r", [(49.0, 12.0), (72.0, 3.5), (72.0, -3.5), (49.0, -12.0)], *strake, s, DARK), cp.RIGHT))
    return out


def collar(s: Style, name: str, section: str, z: tuple[float, float]) -> cp.Module:
    """A bearing collar: a disc of the collar's radius, its edges bevelled."""
    z0, z1 = z
    bevel = 8.0
    profile = [(0.0, 0.0), (0.0, COLLAR_R - bevel), (bevel, COLLAR_R), (z1 - z0 - bevel, COLLAR_R), (z1 - z0, COLLAR_R - bevel), (z1 - z0, 0.0)]
    dark, hull = s.material("hull_dark"), s.material("hull")
    return _put(section, cs.round_body(name, (0.0, 0.0, z0), (0.0, 0.0, z1), profile, s, [dark, hull, hull, hull, dark], sides=24,
                                       creases={1, 2, 3, 4}))


def axle(s: Style, section: str) -> cp.Module:
    """The fixed axle the rotating section turns on, seen in the gaps beside the collars."""
    z0, z1 = FORE_COLLAR_Z[1] - 2.0, AFT_COLLAR_Z[0] + 2.0
    return _put(section, cs.round_body("axle", (0.0, 0.0, z0), (0.0, 0.0, z1), [(0.0, AXLE_R), (z1 - z0, AXLE_R)], s, s.material("hull_dark")))


# --- the rotating section ------------------------------------------------------------------------------------------------
def drum_arm(s: Style, section: str) -> list[cp.Module]:
    """The starboard arm at rest (it reaches along +x): the body, the neck, the cap's bar and slope, and the rim, a panelled
    band round its outer face (no bays: the ship launches from its bow, the maintainer, 2026-11-21)."""
    z0, z1 = DRUM_Z
    body = cs.prism("arm_body_r", [(79.0, -81.0), (79.0, 81.0), (111.0, 101.0), (139.0, 101.0), (186.0, 55.0), (186.0, -55.0), (139.0, -101.0),
                                   (111.0, -101.0)], z0, z1, s, DECKED)
    neck = cs.box("arm_neck_r", (185.0, -25.0, z0), (212.0, 25.0, z1), s, DARK)
    bar = cs.prism("arm_bar_r", [(211.0, -55.0), (211.0, 55.0), (226.0, 74.0), (248.0, 74.0), (248.0, -74.0), (226.0, -74.0)], z0, z1, s, DECKED)
    slope = cs.prism("arm_slope_r", [(247.0, 54.0), (272.5, 41.0), (272.5, -41.0), (247.0, -54.0)], z0, z1, s, PANEL)
    half = 10.0  # the band through the rim, above and below the axis plane
    rim_top = cs.prism("arm_rim_top_r", [(272.0, half), (272.0, 41.0), (294.6, 41.0), (DRUM_REACH, 25.0), (DRUM_REACH, half)], z0, z1, s, DECKED)
    band = cs.box("arm_rim_band_r", (272.0, -half - 0.5, z0), (DRUM_REACH, half + 0.5, z1), s, PANEL)
    return [_put(section, m, cp.RIGHT) for m in (body, neck, bar, slope, rim_top, _flip_y(rim_top, "arm_rim_low_r"), band)]


def drum_hub(s: Style, section: str) -> list[cp.Module]:
    """The hub between the arms: a block through the axis and a shoulder above and below it."""
    z0, z1 = DRUM_Z
    block = cs.box("hub_block", (-80.0, -46.0, z0), (80.0, 46.0, z1), s, DARK)
    top = cs.prism("hub_shoulder_top", [(-53.0, 45.0), (53.0, 45.0), (31.0, 64.0), (-31.0, 64.0)], z0, z1, s, DECKED)
    return [_put(section, block), _put(section, top), _put(section, _flip_y(top, "hub_shoulder_low"))]


# --- the engine housing and the engines ----------------------------------------------------------------------------------
def _side_x(z: float) -> float:
    """The housing's flank: its half width at ``z``."""
    z0, z1 = HOUSING_Z
    return SPINE_W + (HOUSING_W - SPINE_W) * (z - z0) / (z1 - z0)


def housing(s: Style, section: str) -> list[cp.Module]:
    """The engine housing: the solid core flaring sideways, the skirt's stand-off plates above, below and at the corners, a
    short skirt plate on each flank past the core's end, three ribs and a strake on each flank."""
    z0, z1 = HOUSING_Z
    bulge_z, bulge_h, end_h = CORE_BULGE
    mid_ring = _ring(_octagon(_side_x(bulge_z), bulge_h, (24.0, 7.0)), bulge_z)
    front = cs.prism("housing_front", _octagon(SPINE_W, SPINE_H), AFT_SPINE_Z[1], z0 + 1.0, s, DECKED)
    core_a = cs.convex("housing_core_fore", _ring(_octagon(SPINE_W, SPINE_H), z0) + mid_ring, s, DECKED)
    core_b = cs.convex("housing_core_aft", mid_ring + _ring(_octagon(_side_x(CORE_END_Z), end_h, (24.0, 5.0)), CORE_END_Z), s, DECKED)
    thick = 2.5
    top = cs.slab("skirt_top", [(-33.5, 64.0, z0), (33.5, 64.0, z0), (40.0, HOUSING_H, z1), (-40.0, HOUSING_H, z1)], thick, (0.0, -1.0, 0.0), s, PANEL)
    corner = cs.slab("skirt_corner_top_r", [(33.5, 64.0, z0), (SPINE_W, 52.0, z0), (HOUSING_W, 75.0, z1), (40.0, HOUSING_H, z1)], thick,
                     (-1.0, -1.5, 0.0), s, PANEL)
    side = cs.slab("skirt_side_r", [(_side_x(1372.0) + 0.5, 72.0, 1372.0), (HOUSING_W, 75.0, z1), (HOUSING_W, -75.0, z1), (_side_x(1372.0) + 0.5, -72.0, 1372.0)],
                   thick, (-1.0, 0.0, 0.0), s, PLAIN)
    out = [_put(section, front), _put(section, core_a), _put(section, core_b), _put(section, top), _put(section, _flip_y(top, "skirt_low")), _put(section, corner, cp.RIGHT),
           _put(section, _flip_y(corner, "skirt_corner_low_r"), cp.RIGHT), _put(section, side, cp.RIGHT)]
    for k, (a, b) in enumerate(((1280.0, 1298.0), (1307.0, 1325.0), (1335.0, 1352.0))):
        rib = cs.convex(f"housing_rib_{k + 1}_r", [(_side_x(z) + dx, y, z) for z in (a, b) for dx in (-2.0, 6.0) for y in (-56.0, 55.0)], s, DARK,
                        skin=cp.SKIN_FITTING)
        out.append(_put(section, rib, cp.RIGHT))
    # The strake along the flank's middle: from the aft spine's side, thinning to its edge, running inside the skirt to the stern.
    for name, (a, b), (tip_a, tip_b), root in (("strake_fore_r", (1182.0, z0), (70.0, 80.0), (49.0, 49.0)),
                                               ("strake_aft_r", (z0, z1), (80.0, 108.0), (SPINE_W - 1.0, 60.0))):
        pts = [(x, y, z) for z, tip, base in ((a, tip_a, root[0]), (b, tip_b, root[1])) for x, y in ((base, 8.0), (base, -8.0), (tip, 3.5), (tip, -3.5))]
        out.append(_put(section, cs.convex(name, pts, s, DARK), cp.RIGHT))
    return out


def engine(s: Style, name: str, section: str, up: float) -> cp.Module:
    """One starboard nacelle (``up`` +1 the upper, -1 the lower): a drum, a waist, a flared bell and its glowing bore, with
    the engine's hardpoint at the mouth."""
    z0 = ENGINE_START_Z
    x, y = ENGINE_XY[0], up * ENGINE_XY[1]
    length = ENGINE_MOUTH_Z - z0
    at = lambda z: z - z0  # noqa: E731 - the profile is written at the ship's z
    profile = [(0.0, 0.0), (0.0, 28.0), (at(1445.0), 28.0), (at(1452.0), 37.0), (at(1478.0), 37.0), (at(1500.0), 22.0), (at(1520.0), 22.0),
               (at(1522.0), 31.0), (at(1565.0), 24.0), (length, 19.5), (length, 16.5), (length - 15.0, 11.0), (length - 15.0, 0.0)]
    hull, dark, metal, glow = s.material("hull"), s.material("hull_dark"), s.material("nozzle"), s.material("nozzle_throat")
    mats = [dark, hull, dark, hull, dark, dark, metal, metal, metal, metal, glow, glow]
    body = cs.round_body(f"{name}_body", (x, y, z0), (x, y, ENGINE_MOUTH_Z), profile, s, mats, sides=20, creases={1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11},
                         skin=cp.SKIN_FITTING, hollow_from=10)
    # The mounting lugs either side of the drum, ahead of the flange: the band the reference carries at the nacelle's height.
    lug = cs.box(f"{name}_lugs", (x - 37.0, y - 6.5, LUG_Z[0]), (x + 38.0, y + 6.5, LUG_Z[1]), s, DARK, skin=cp.SKIN_FITTING)
    point = cp.Hardpoint(name, cp.ENGINE, (x, y, ENGINE_MOUTH_Z), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), {"share": 0.25, "radius_m": 16.5})
    return _put(section, dataclasses.replace(cs.compound(name, [body, lug]), hardpoints=(point,)), cp.RIGHT)


def engine_frame(s: Style, section: str) -> list[cp.Module]:
    """What holds a side's two nacelles: the boom between them, ending in a blade at the stern."""
    boom = cs.box("engine_boom_r", (32.0, -17.5, 1548.0), (72.0, 17.5, ENGINE_MOUTH_Z), s, DARK)
    blade = cs.convex("engine_blade_r", [(x, y, z) for z, h in ((ENGINE_MOUTH_Z - 1.0, 17.5), (LENGTH_M, 1.5)) for x in (32.0, 72.0) for y in (-h, h)], s, PLAIN)
    return [_put(section, boom, cp.RIGHT), _put(section, blade, cp.RIGHT)]


def tail(s: Style, section: str) -> list[cp.Module]:
    """Between the engines: the thrust frame behind the core and the thin tail plates above and below, from the skirt's
    edge down to the nacelles' backs."""
    frame = cs.box("thrust_frame", (-76.0, -14.0, CORE_END_Z - 2.0), (76.0, 14.0, 1470.0), s, DARK)
    link = cs.box("thrust_link", (-37.0, -4.0, 1469.0), (37.0, 4.0, 1523.0), s, DARK)
    cross = cs.box("cross_beam", (-86.0, -12.0, 1522.0), (86.0, 12.0, 1549.0), s, DARK)
    runs = ((HOUSING_Z[1] - 2.0, HOUSING_H, 40.0), (1490.0, 99.0, 34.0), (1565.0, 72.0, 30.0), (1650.0, 70.0, 25.0))
    fin = cs.prism("thrust_fin_r", [(75.0, -8.0), (86.0, -8.0), (99.0, -5.0), (99.0, 5.0), (86.0, 8.0), (75.0, 8.0)], CORE_END_Z - 2.0, 1456.0, s, DARK)
    post = cs.box("tail_post_top_r", (74.0, 75.0, HOUSING_Z[1] - 1.0), (84.0, 84.0, 1465.0), s, DARK)  # the skirt's corner strut aft
    out = [_put(section, m) for m in (frame, link, cross)] + [_put(section, m, cp.RIGHT) for m in (fin, post, _flip_y(post, "tail_post_low_r"))]
    for k, ((za, ya, wa), (zb, yb, wb)) in enumerate(zip(runs, runs[1:], strict=False)):
        plate = cs.slab(f"tail_plate_top_{k + 1}", [(-wa, ya, za), (wa, ya, za), (wb, yb, zb), (-wb, yb, zb)], 2.5, (0.0, -1.0, 0.0), s, PANEL)
        out += [_put(section, plate), _put(section, _flip_y(plate, f"tail_plate_low_{k + 1}"))]
    return out


__all__ = ["AFT_COLLAR_Z", "AFT_SPINE_Z", "AXLE_R", "BAY_BACK_Z", "BAY_CORNER", "BAY_DEPTH", "BAY_MOUTH", "BAY_MOUTH_Z", "BAY_Y", "COLLAR_R", "COMMAND_Z", "CORE_END_Z", "DRUM_PIVOT", "ENGINE_START_Z", "NOTCH_Z", "RAILS_END_Z",
           "DRUM_REACH", "DRUM_Z", "ENGINE_MOUTH_Z", "ENGINE_XY", "FORE_COLLAR_Z", "FORE_SPINE_Z", "HOUSING_H", "HOUSING_W", "HOUSING_Z", "LENGTH_M",
           "SPINE_H", "SPINE_W", "STARFURIES", "aerials", "around_hole", "axle", "collar", "command_block", "drum_arm", "drum_hub", "engine",
           "engine_frame", "fore_bay", "housing", "retro_nozzle", "shields", "spine", "tail", "tankage"]
