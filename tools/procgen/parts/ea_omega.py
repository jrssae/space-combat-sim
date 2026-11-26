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

from ..core import collision as col
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
COMMAND_Z = (221.0, 358.0)  # the command block behind the open-frame bow (the kit's, M10-T68)
BROW_Y, BROW_Z = 53.0, 229.0  # above this height the block's face stands further back
NOTCH_Z = 334.0

FORE_SPINE_Z = (356.0, 528.0)
AFT_SPINE_Z = (904.0, 1240.0)
MAGAZINE_END_Z = 1085.0  # the magazine (the aft spine's forward part) ends here
COLLAR_R, AXLE_R = 77.5, 44.8
FORE_COLLAR_Z, AFT_COLLAR_Z = (526.0, 561.0), (875.0, 906.0)
DRUM_Z = (562.0, 875.0)
DRUM_PIVOT = (0.0, 0.0, 718.5)
DRUM_REACH = 308.0  # the rim's outer face, from the axis
HOUSING_Z = (1242.0, 1408.0)
HOUSING_W, HOUSING_H = 98.0, 100.0  # the cage's half width and half height at its stern edge
CORE_END_Z = 1385.0  # the thrust frame starts here, inside the reactor cage
CAGE_Z = 1326.0  # where the housing's solid core ends and the reactor cage round the nacelles begins (the kit's)
ENGINE_START_Z = 1310.0
ENGINE_XY = (40.0, 44.5)
ENGINE_MOUTH_Z = 1660.0
LUG_Z = (1405.0, 1468.0)
# The one launch bay, facing the bow above the retro thrusters (the maintainer, 2026-11-21): the kit's octagonal mouth in its
# frame at the open bow's face (M10-T68), the hall reaching back through the command block. A Starfury is 11 m across and 7 m
# tall; the kit's hall is a print's shallow 58 m, the build's keeps room for its 32 Starfuries.
BAY_MOUTH, BAY_DEPTH, BAY_WALL = (72.0, 35.0), 134.0, 2.0
BAY_MOUTH_Z, BAY_Y = 188.0, -3.0
BAY_BACK_Z = BAY_MOUTH_Z + BAY_DEPTH + BAY_WALL
BAY_CORNER = 7.0  # the fillets in the hall's corners that make its mouth the reference's octagon
STARFURIES = 32
CRAFT = "starfury_ally"  # the catalogue's pooled Starfury (data/capitals/loadouts.json, launches)
# The retro thrusters' oval nozzles: open from their mouths to the throat, as the reference's.
RETRO_Z, RETRO_THROAT_Z, RETRO_WALL, RETRO_NARROW = 168.0, 196.0, 6.5, 1.0

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


def paired_hulls(m: cp.Module, group: int = 3) -> cp.Module:
    """``m`` (a ring of hull pieces with one closing part last, as :func:`retro_nozzle`) with each ``group`` neighbouring pieces
    joined in one hull: the ring in fewer shapes, its hole still open."""
    *ring, last = m.shapes
    joined = [col.hull(f"{m.name}_{k}", np.concatenate([q.points for q in ring[i:i + group]])) for k, i in enumerate(range(0, len(ring), group))]
    return dataclasses.replace(m, shapes=(*joined, last.renamed(f"{m.name}_plate")))


# --- the bow -------------------------------------------------------------------------------------------------------------
MARK_HEIGHT_M = 40.0  # the show's letter stands about a sixth of the shield's height
MARK_AT = 0.2  # how far up the lower panel the letter's centre sits, from its bottom edge


def shield_mark(x: float, top: tuple[float, float, float], bottom: tuple[float, float, float]) -> cp.Hardpoint:
    """The name letter in large white block print at the bottom of the shield (the show's), on the lower panel's outer face:
    ``top`` and ``bottom`` are the panel's two edges at the shield's face (y, and z from, z to, with the bottom edge leaning in)."""
    (ty, tz0, tz1), (by, bz0, bz1) = top, bottom
    x_bottom = 29.0
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
            "command_roof": x("mark_x_roof", (0.0, 64.0, 310.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0))}


def shields(s: Style) -> list[cp.Module]:
    """The starboard armour shield: a vertical panel and two leaning in above and below it, 5 m thick."""
    thick, x = 6.0, 68.0  # the kit's plates, 6 m
    inward = (-1.0, 0.0, 0.0)
    mid = cs.slab("shield_mid_r", [(x, 57.4, 193.0), (x, 57.4, 358.0), (x, -55.6, 358.0), (x, -55.6, 193.0)], thick, inward, s, PLAIN)
    upper = cs.slab("shield_upper_r", [(x, 57.4, 193.0), (x, 57.4, 358.0), (43.5, 95.4, 307.0), (43.5, 95.4, 214.0)], thick, inward, s, PLAIN)
    lower = cs.slab("shield_lower_r", [(x, -55.6, 193.0), (x, -55.6, 358.0), (29.0, -195.6, 270.0), (29.0, -195.6, 214.0)], thick, inward, s, PLAIN)
    mid = dataclasses.replace(mid, hardpoints=(renegade_xs()["shield_mid_r"],))
    lower = dataclasses.replace(lower, hardpoints=(shield_mark(x, (-55.6, 193.0, 358.0), (-195.6, 214.0, 270.0)),))
    pod = cs.convex("beam_pod_r", [(px, py, pz) for px, c in ((68.0, 0.0), (88.0, 4.0)) for py in (-22.0 + c, 22.0 - c) for pz in (205.0 + c, 247.0 - c)],
                    s, DARK, skin=cp.SKIN_FITTING)
    return [_put("bow", m, cp.RIGHT) for m in (mid, upper, lower, pod)]


def command_block(s: Style) -> list[cp.Module]:
    """The command section behind the open-frame bow (``parts/ea_omega_bow.py`` builds what stands ahead of it): the octagon with
    the launch bay's hall through it, the roof deck, the waist behind the notch and a strake along each flank."""
    z0, z1 = COMMAND_Z
    hw, hh = 0.5 * BAY_MOUTH[0] + BAY_WALL, 0.5 * BAY_MOUTH[1] + BAY_WALL
    ys = (BAY_Y - hh, BAY_Y + hh)
    block = cs.prism("command_block", _octagon(SPINE_W, SPINE_H), BAY_BACK_Z - 0.5, NOTCH_Z, s, DECKED)
    fore = around_hole("command_block_fore", _clip(_octagon(SPINE_W, SPINE_H), lambda p: BROW_Y - p[1]), hw, ys, (z0, BAY_BACK_Z), s, DECKED, "bridge")
    brow = cs.prism("command_brow", _clip(_octagon(SPINE_W, SPINE_H), lambda p: p[1] - BROW_Y), BROW_Z, BAY_BACK_Z, s, DECKED)
    waist = cs.box("command_aft", (-SPINE_W, -47.0, NOTCH_Z - 1.0), (SPINE_W, 47.0, z1), s, PLAIN)
    shoulder = cs.prism("command_shoulder_top_r", [(20.0, 46.0), (SPINE_W, 46.0), (SPINE_W, SPINE_H - SPINE_CUT[1]), (SPINE_W - SPINE_CUT[0], SPINE_H),
                                                   (26.0, SPINE_H)], NOTCH_Z - 1.0, z1, s, DECKED)
    roof = cs.box("command_roof", (-57.0, 55.5, 238.0), (57.0, 64.0, 325.0), s, PANEL)
    strake = cs.prism("command_strake_r", [(SPINE_W - 1.0, 8.0), (72.0, 3.5), (72.0, -3.5), (SPINE_W - 1.0, -8.0)], 222.0, 372.0, s, DARK)
    sided = (strake, shoulder, _flip_y(shoulder, "command_shoulder_low_r"))
    roof = dataclasses.replace(roof, hardpoints=(renegade_xs()["command_roof"],))
    return [_put("bridge", m) for m in (block, waist, roof, brow)] + fore + [_put("bridge", m, cp.RIGHT) for m in sided]


def aerials(s: Style) -> list[cp.Module]:
    """The sensor boom (port and low: the reference has one) and the masts."""
    boom_at = (-19.0, -145.0)  # the kit's probe, run forward to the bow's tip (its print is short, M10-T68)
    profile = [(0.0, 0.0), (0.0, 1.0), (50.0, 1.0), (52.0, 2.0), (93.0, 2.0), (96.0, 7.5), (111.0, 7.5), (113.0, 4.5), (154.0, 4.5), (157.0, 7.0),
               (207.0, 7.0), (207.0, 0.0)]
    boom = cs.round_body("sensor_boom", (*boom_at, 0.0), (*boom_at, 207.0), profile, s, s.material("hull_dark"), sides=10,
                         creases={2, 3, 4, 5, 6, 7, 8, 9, 10}, skin=cp.SKIN_FITTING)
    # The probe's thin front as one hull; the bulbs and the thick root a hull each.
    start, axis = np.array([*boom_at, 0.0]), np.array([0.0, 0.0, 1.0])
    steps = [((0.0, 2.0), (93.0, 2.0)), *zip(profile[4:10], profile[5:11], strict=False)]
    boom = dataclasses.replace(boom, shapes=tuple(col.hull(f"sensor_boom_{k}", col.prism_points(start, axis, [a, b], 10)) for k, (a, b) in enumerate(steps)))
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
# The spines' girder, the kit's section (top half; the lower is its mirror): the core, the deck plate over it reaching past the
# core's sides, an ear on each corner and a flange down each flank (the kit's shallow side panels are left to the plating).
SPINE_CORE = (41.0, 54.0)
SPINE_DECK = [(61.0, 54.0), (56.0, 57.0), (-56.0, 57.0), (-61.0, 54.0)]
SPINE_EAR = [(22.0, 56.5), (54.0, 56.5), (48.0, 61.0), (38.0, 64.5), (25.0, 65.0)]
SPINE_FLANGE = ((SPINE_CORE[0] - 0.5, 17.5), (52.0, 20.0))
SPINE_STRAKE = [(SPINE_CORE[0] - 0.5, 10.0), (70.0, 2.5), (70.0, -2.5), (SPINE_CORE[0] - 0.5, -10.0)]


def spine(s: Style, name: str, section: str, z: tuple[float, float], strakes: tuple[tuple[float, float], ...] = ()) -> list[cp.Module]:
    """A spine's girder from ``z[0]`` to ``z[1]`` (the kit's section): the core, the deck plates above and below, an ear on each
    corner, a flange on each flank, and a strake along the flank's middle over each of ``strakes`` (z from, to)."""
    z0, z1 = z
    w, h = SPINE_CORE
    core = cs.box(f"{name}_core", (-w, -h, z0), (w, h, z1), s, DECKED)
    deck = cs.prism(f"{name}_deck_top", SPINE_DECK, z0, z1, s, DECKED)
    ear = cs.prism(f"{name}_ear_top_r", SPINE_EAR, z0, z1, s, DECKED)
    flange = cs.box(f"{name}_flange_top_r", (*SPINE_FLANGE[0], z0), (*SPINE_FLANGE[1], z1), s, DARK)
    out = [_put(section, core), _put(section, deck), _put(section, _flip_y(deck, f"{name}_deck_low"))]
    for m in (ear, flange):
        out += [_put(section, m, cp.RIGHT), _put(section, _flip_y(m, m.name.replace("_top_", "_low_")), cp.RIGHT)]
    for k, (a, b) in enumerate(strakes):
        out.append(_put(section, cs.prism(f"{name}_strake_{k + 1}_r", SPINE_STRAKE, a, b, s, DARK), cp.RIGHT))
    return out


def spine_block(s: Style, name: str, section: str, z: tuple[float, float], half_w: float) -> cp.Module:
    """A solid block where a spine meets a collar or the engine housing (the kit's): the channel between the ears filled, the
    sides out to ``half_w``."""
    w = half_w
    top = [(w, 52.0), (w - 6.0, 57.0), (40.0, 63.0), (-40.0, 63.0), (-(w - 6.0), 57.0), (-w, 52.0)]
    outline = top + [(x, -y) for x, y in reversed(top)]
    return _put(section, cs.prism(name, outline, *z, s, DECKED))


def collar(s: Style, name: str, section: str, z: tuple[float, float]) -> cp.Module:
    """A bearing collar: a disc of the collar's radius, its edges bevelled."""
    z0, z1 = z
    bevel = 8.0
    profile = [(0.0, 0.0), (0.0, COLLAR_R - bevel), (bevel, COLLAR_R), (z1 - z0 - bevel, COLLAR_R), (z1 - z0, COLLAR_R - bevel), (z1 - z0, 0.0)]
    dark, hull = s.material("hull_dark"), s.material("hull")
    ring = cs.round_body(name, (0.0, 0.0, z0), (0.0, 0.0, z1), profile, s, [dark, hull, hull, hull, dark], sides=24, creases={1, 2, 3, 4})
    start, axis = np.array([0.0, 0.0, z0]), np.array([0.0, 0.0, 1.0])
    steps = list(zip(profile[1:-1], profile[2:-1], strict=False))  # the bevels and the band between: one hull each
    shapes = tuple(col.hull(f"{name}_{k}", col.prism_points(start, axis, [a, b], 12)) for k, (a, b) in enumerate(steps))
    return _put(section, dataclasses.replace(ring, shapes=shapes))


def axle(s: Style, section: str) -> cp.Module:
    """The fixed axle the rotating section turns on, seen in the gaps beside the collars."""
    z0, z1 = FORE_COLLAR_Z[1] - 2.0, AFT_COLLAR_Z[0] + 2.0
    return _put(section, cs.round_body("axle", (0.0, 0.0, z0), (0.0, 0.0, z1), [(0.0, AXLE_R), (z1 - z0, AXLE_R)], s, s.material("hull_dark")))


# --- the rotating section ------------------------------------------------------------------------------------------------
# The truss on each flank of an arm's inner lobe (the kit's lattice panels): rails along the arm at the flank's edges, posts
# between bays and an X in each bay, standing proud of the flank.
TRUSS_R, TRUSS_BAYS, TRUSS_BAR, TRUSS_PROUD = (104.0, 134.0), 10, 2.2, 2.0


def _bar(name: str, a: tuple[float, float], b: tuple[float, float], y: float, s: Style) -> cp.Module:
    """A square bar from ``a`` to ``b`` (radial, z) on the flank plane at ``y`` (tangential), ``TRUSS_BAR`` thick."""
    d = np.array([b[0] - a[0], b[1] - a[1]])
    n = np.array([-d[1], d[0]]) / np.linalg.norm(d) * 0.5 * TRUSS_BAR
    pts = [(p[0] + sx * n[0], yy, p[1] + sx * n[1]) for p in (a, b) for sx in (-1.0, 1.0) for yy in (y, y + TRUSS_PROUD)]
    return cs.convex(name, pts, s, DARK, skin=cp.SKIN_FITTING)


def arm_truss(s: Style, name: str, y: float) -> cp.Module:
    """The truss on the flank face at ``y`` (the starboard arm's frame: x radial, y tangential): one part with one hull."""
    (r0, r1), (z0, z1) = TRUSS_R, DRUM_Z
    zs = np.linspace(z0 + 6.0, z1 - 6.0, TRUSS_BAYS + 1)
    bars = [_bar(f"{name}_rail_in", (r0, zs[0]), (r0, zs[-1]), y, s), _bar(f"{name}_rail_out", (r1, zs[0]), (r1, zs[-1]), y, s)]
    for k, z in enumerate(zs):
        bars.append(_bar(f"{name}_post_{k}", (r0, z), (r1, z), y, s))
    for k, (za, zb) in enumerate(zip(zs, zs[1:], strict=False)):
        bars += [_bar(f"{name}_x_{k}a", (r0, za), (r1, zb), y, s), _bar(f"{name}_x_{k}b", (r1, za), (r0, zb), y, s)]
    truss = cs.compound(name, bars)
    return dataclasses.replace(truss, shapes=(col.hull(name, truss.part.mesh.vertices),))


def drum_arm(s: Style, section: str) -> list[cp.Module]:
    """The starboard arm at rest in its own frame (it reaches along +x; the asset turns the rotating section so the arms stand
    up and down, the kit's pose): the inner lobe with a truss on each flank, the neck, the outer lobe, its cap and the rim, a
    panelled band round its outer face (no bays: the ship launches from its bow, the maintainer, 2026-11-21)."""
    z0, z1 = DRUM_Z
    body = cs.prism("arm_body_r", [(77.0, -90.0), (77.0, 90.0), (100.0, 101.0), (138.0, 101.0), (181.0, 64.0), (181.0, -64.0), (138.0, -101.0),
                                   (100.0, -101.0)], z0, z1, s, DECKED)
    neck = cs.box("arm_neck_r", (180.0, -25.0, z0), (206.0, 25.0, z1), s, DARK)
    bar = cs.prism("arm_bar_r", [(205.0, -55.0), (205.0, 55.0), (222.0, 78.0), (240.0, 78.0), (240.0, -78.0), (222.0, -78.0)], z0, z1, s, DECKED)
    slope = cs.prism("arm_slope_r", [(239.5, -78.0), (239.5, 78.0), (250.0, 52.0), (262.0, 42.0), (262.0, -42.0), (250.0, -52.0)], z0, z1, s, PANEL)
    half = 10.0  # the band through the rim, either side of the arm's middle
    rim_top = cs.prism("arm_rim_top_r", [(261.5, half), (261.5, 41.0), (288.0, 40.0), (300.0, 30.0), (DRUM_REACH, 18.0), (DRUM_REACH, half)], z0, z1, s, DECKED)
    band = cs.box("arm_rim_band_r", (261.5, -half - 0.5, z0), (DRUM_REACH, half + 0.5, z1), s, PANEL)
    truss = arm_truss(s, "arm_truss_top_r", 101.0 - 0.2)
    parts = (body, neck, bar, slope, rim_top, _flip_y(rim_top, "arm_rim_low_r"), band, truss, _flip_y(truss, "arm_truss_low_r"))
    return [_put(section, m, cp.RIGHT) for m in parts]


def drum_hub(s: Style, section: str) -> list[cp.Module]:
    """The hub between the arms: a block through the axis and a shoulder above and below it."""
    z0, z1 = DRUM_Z
    block = cs.box("hub_block", (-80.0, -46.0, z0), (80.0, 46.0, z1), s, DARK)
    top = cs.prism("hub_shoulder_top", [(-53.0, 45.0), (53.0, 45.0), (31.0, 64.0), (-31.0, 64.0)], z0, z1, s, DECKED)
    return [_put(section, block), _put(section, top), _put(section, _flip_y(top, "hub_shoulder_low"))]


# --- the engine housing and the engines ----------------------------------------------------------------------------------
# The housing's core (the kit's): its outline at the front and where it ends, each as (half width, shoulder's height, roof's
# half width, roof's height); the reactor cage behind it is the skirt's roof, corner and side plates round the nacelles.
CORE_RINGS = ((HOUSING_Z[0], (62.0, 54.0, 37.0, 66.0)), (CAGE_Z, (79.0, 66.0, 20.0, 88.0)))
SKIRT_FRONT = ((40.0, 88.0), (79.0, 66.0))  # the roof's and the corner's front edge, at the core's end: (x, y)
SKIRT_BACK = ((50.0, 100.0), (98.0, 75.0))  # the same at the stern edge
SIDE_WALL = ((88.0, 73.0, 1362.0), (98.0, 75.0, HOUSING_Z[1] + 4.0))  # the side plate's front and back: x, half height, z


def _side_x(z: float) -> float:
    """The housing's flank: its half width at ``z`` (the core's, then the cage's side wall)."""
    (z0, (w0, *_)), (z1, (w1, *_)) = CORE_RINGS
    return w0 + (w1 - w0) * (min(z, z1) - z0) / (z1 - z0)


def _core_ring(z: float, w: float, shoulder: float, roof_w: float, roof_h: float) -> list[tuple[float, float, float]]:
    top = [(w, shoulder), (roof_w, roof_h), (-roof_w, roof_h), (-w, shoulder)]
    return [(x, y, z) for x, y in top + [(x, -y) for x, y in reversed(top)]]


def housing(s: Style, section: str) -> list[cp.Module]:
    """The engine housing (the kit's): the core flaring from the spine to its pitched roof, then the reactor cage round the
    nacelles' roots: the roof plate rising aft, a corner plate down to each side wall, the side walls, three ribs and a strake
    on each flank."""
    z0, z1 = HOUSING_Z
    (za, ra), (zb, rb) = CORE_RINGS
    front = cs.prism("housing_front", _octagon(SPINE_W, SPINE_H), AFT_SPINE_Z[1], z0 + 1.0, s, DECKED)
    core = cs.convex("housing_core", _core_ring(za, *ra) + _core_ring(zb, *rb), s, DECKED)
    thick = 8.0
    (rx0, ry0), (cx0, cy0) = SKIRT_FRONT
    (rx1, ry1), (cx1, cy1) = SKIRT_BACK
    roof = cs.slab("skirt_top", [(-rx0, ry0, zb - 6.0), (rx0, ry0, zb - 6.0), (rx1, ry1, z1), (-rx1, ry1, z1)], thick, (0.0, -1.0, 0.0), s, PANEL)
    corner = cs.slab("skirt_corner_top_r", [(rx0, ry0, zb - 6.0), (cx0, cy0, zb - 6.0), (cx1, cy1, z1), (rx1, ry1, z1)], thick, (-1.0, -1.6, 0.0), s, PANEL)
    (wx0, wh0, wz0), (wx1, wh1, wz1) = SIDE_WALL
    side = cs.slab("skirt_side_r", [(wx0, wh0, wz0), (wx1, wh1, wz1), (wx1, -wh1, wz1), (wx0, -wh0, wz0)], thick, (-1.0, 0.0, 0.0), s, PLAIN)
    out = [_put(section, front), _put(section, core), _put(section, roof), _put(section, _flip_y(roof, "skirt_low")), _put(section, corner, cp.RIGHT),
           _put(section, _flip_y(corner, "skirt_corner_low_r"), cp.RIGHT), _put(section, side, cp.RIGHT)]
    for k, (a, b) in enumerate(((1272.0, 1290.0), (1300.0, 1318.0), (1343.0, 1353.0))):
        rib = cs.convex(f"housing_rib_{k + 1}_r", [(_side_x(z) + dx, y, z) for z in (a, b) for dx in (-2.0, 5.0) for y in (-56.0, 55.0)], s, DARK,
                        skin=cp.SKIN_FITTING)
        out.append(_put(section, rib, cp.RIGHT))
    # The strake along the flank's middle: from the aft spine's side, thinning to its edge, running to the stern.
    for name, (a, b), (tip_a, tip_b), root in (("strake_fore_r", (1182.0, z0), (70.0, 72.0), (49.0, 49.0)),
                                               ("strake_aft_r", (z0, z1), (72.0, 102.0), (SPINE_W - 1.0, 75.0))):
        pts = [(x, y, z) for z, tip, base in ((a, tip_a, root[0]), (b, tip_b, root[1])) for x, y in ((base, 8.0), (base, -8.0), (tip, 3.5), (tip, -3.5))]
        out.append(_put(section, cs.convex(name, pts, s, DARK), cp.RIGHT))
    return out


def engine(s: Style, name: str, section: str, up: float) -> cp.Module:
    """One starboard nacelle (``up`` +1 the upper, -1 the lower), the kit's: a drum out of the housing, a ring, a waist and a
    second ring, tapering to the bell and its glowing bore, with the engine's hardpoint at the mouth."""
    z0 = ENGINE_START_Z
    x, y = ENGINE_XY[0], up * ENGINE_XY[1]
    length = ENGINE_MOUTH_Z - z0
    at = lambda z: z - z0  # noqa: E731 - the profile is written at the ship's z
    profile = [(0.0, 0.0), (0.0, 26.0), (at(1470.0), 26.0), (at(1490.0), 32.5), (at(1504.0), 33.0), (at(1506.0), 27.5), (at(1522.0), 27.5),
               (at(1526.0), 32.0), (at(1546.0), 28.0), (at(1566.0), 23.0), (at(1584.0), 22.0), (at(1588.0), 21.0), (length, 19.5), (length, 16.5),
               (length - 24.0, 11.0), (length - 24.0, 0.0)]
    hull, dark, metal, glow, rust = (s.material(r) for r in ("hull", "hull_dark", "nozzle", "nozzle_throat", "stripe"))
    mats = [dark, hull, hull, rust, dark, dark, hull, rust, hull, metal, metal, metal, metal, glow, glow]  # the rings in the face's rust paint
    body = cs.round_body(f"{name}_body", (x, y, z0), (x, y, ENGINE_MOUTH_Z), profile, s, mats, sides=20, creases=set(range(1, 15)),
                         skin=cp.SKIN_FITTING, hollow_from=13)
    # A few hulls follow the nacelle (the drum, the rings, the waist, the taper, the bell; the bore an open ring), so a side's
    # two nacelles stay well inside the section's shape budget without merging over their waists.
    start, axis = np.array([x, y, z0]), np.array([0.0, 0.0, 1.0])
    deep = length - 24.0  # where the bore starts
    bell_r = 21.0 + (19.5 - 21.0) * (deep - at(1588.0)) / (length - at(1588.0))
    outside = [(0.0, 26.0), *(p for p in profile[2:12] if p[0] not in (at(1566.0), at(1584.0), at(1588.0))), (deep, bell_r)]  # the taper as one step
    shapes = [col.hull(f"{name}_body_{k}", col.prism_points(start, axis, [(d0, r0), (d1, r1)], 12))
              for k, ((d0, r0), (d1, r1)) in enumerate(zip(outside, outside[1:], strict=False)) if d1 - d0 > 1e-6]
    for k, (a_, b_) in enumerate(zip(np.linspace(deep, length, 3)[:-1], np.linspace(deep, length, 3)[1:], strict=False)):
        r_in = 11.0 + (16.5 - 11.0) * (a_ - deep) / (length - deep)  # the bore's wall at the step's inner end
        shapes += col.ring_sectors(f"{name}_bore_{k}", start, axis, r_in, bell_r, a_, b_, 5)
    body = dataclasses.replace(body, shapes=tuple(q.renamed(f"{name}_body_{k}") for k, q in enumerate(shapes)))
    # The mounting lugs either side of the drum, the band the kit carries at the nacelle's height.
    lug_y = y - up * 2.0  # a little inboard of the nacelle's axis, the kit's
    lug = cs.box(f"{name}_lugs", (x - 38.0, lug_y - 6.0, LUG_Z[0]), (x + 38.0, lug_y + 6.0, LUG_Z[1]), s, DARK, skin=cp.SKIN_FITTING)
    point = cp.Hardpoint(name, cp.ENGINE, (x, y, ENGINE_MOUTH_Z), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), {"share": 0.25, "radius_m": 17.0})
    return _put(section, dataclasses.replace(cs.compound(name, [body, lug]), hardpoints=(point,)), cp.RIGHT)


def engine_frame(s: Style, section: str) -> list[cp.Module]:
    """Between a side's two nacelles: the blade that runs out past the mouths to the stern, thinning to its edge."""
    root = cs.convex("engine_blade_root_r", [(x, y, z) for z, h in ((1609.0, 9.5), (1666.0, 9.5)) for x in (20.0, 60.0) for y in (-h, h)], s, PLAIN)
    blade = cs.convex("engine_blade_r", [(x, y, z) for z, h in ((1665.0, 9.5), (LENGTH_M, 2.5)) for x in (20.0, 60.0) for y in (-h, h)], s, PLAIN)
    return [_put(section, root, cp.RIGHT), _put(section, blade, cp.RIGHT)]


def tail(s: Style, section: str) -> list[cp.Module]:
    """Between the engines: the thrust frame behind the core, the cross beam, the thrust plate between the nacelles and the
    thick tail plates above and below, stepping down from the skirt's edge to the nacelles' backs (the kit's)."""
    frame = cs.box("thrust_frame", (-76.0, -13.0, CORE_END_Z - 2.0), (76.0, 13.0, 1470.0), s, DARK)
    cross = cs.box("cross_beam", (-98.0, -4.0, 1430.0), (98.0, 4.0, 1462.0), s, DARK)
    plate = cs.box("thrust_plate", (-66.0, -13.0, 1469.0), (66.0, 13.0, 1553.0), s, DARK)
    # The cap over the cage's stern, out to the nacelles' backs: the roof plate's run aft with its chamfers and the ridge along it.
    cap = cs.prism("tail_cap_top", [(54.0, 90.0), (55.0, 96.0), (34.0, 109.0), (-34.0, 109.0), (-55.0, 96.0), (-54.0, 90.0)], HOUSING_Z[1] - 2.0, 1462.0, s, PANEL)
    plate_aft = cs.box("thrust_plate_aft", (-76.0, -9.5, 1552.0), (76.0, 9.5, 1610.0), s, DARK)
    runs = ((1461.0, 106.0, 33.0), (1500.0, 106.0, 33.0), (1540.0, 91.0, 33.0), (1585.0, 79.0, 32.0), (1650.0, 76.0, 26.0))
    post = cs.box("tail_post_top_r", (73.0, 64.0, HOUSING_Z[1] - 1.0), (86.0, 75.0, 1502.0), s, DARK)  # the skirt's corner strut aft
    # Under each nacelle a cradle off the thrust frame, and between each side's nacelles a block ahead of the bells (the kit's).
    cradle = cs.prism("engine_cradle_top_r", [(3.0, 12.5), (76.0, 12.5), (76.0, 24.0), (68.0, 35.0), (12.0, 35.0), (3.0, 24.0)], 1400.0, 1470.0, s, DARK)
    block = cs.prism("engine_block_top_r", [(5.0, 8.0), (76.0, 8.0), (74.0, 25.0), (69.0, 34.0), (12.0, 34.0), (6.0, 25.0)], 1552.0, 1606.0, s, DECKED)
    sided = (post, _flip_y(post, "tail_post_low_r"), cradle, _flip_y(cradle, "engine_cradle_low_r"), block, _flip_y(block, "engine_block_low_r"))
    out = [_put(section, m) for m in (frame, cross, plate, plate_aft, cap, _flip_y(cap, "tail_cap_low"))] + [_put(section, m, cp.RIGHT) for m in sided]
    for k, ((za, ya, wa), (zb, yb, wb)) in enumerate(zip(runs, runs[1:], strict=False)):
        top = cs.slab(f"tail_plate_top_{k + 1}", [(-wa, ya, za), (wa, ya, za), (wb, yb, zb), (-wb, yb, zb)], 10.0, (0.0, -1.0, 0.0), s, PANEL)
        out += [_put(section, top), _put(section, _flip_y(top, f"tail_plate_low_{k + 1}"))]
    return out


__all__ = ["AFT_COLLAR_Z", "AFT_SPINE_Z", "AXLE_R", "BAY_BACK_Z", "BAY_CORNER", "BAY_DEPTH", "BAY_MOUTH", "BAY_MOUTH_Z", "BAY_WALL", "BAY_Y", "CRAFT", "COLLAR_R", "COMMAND_Z", "CORE_END_Z", "DRUM_PIVOT", "ENGINE_START_Z", "NOTCH_Z", "MAGAZINE_END_Z",
           "DRUM_REACH", "DRUM_Z", "ENGINE_MOUTH_Z", "ENGINE_XY", "FORE_COLLAR_Z", "FORE_SPINE_Z", "HOUSING_H", "HOUSING_W", "HOUSING_Z", "LENGTH_M",
           "SPINE_H", "SPINE_W", "STARFURIES", "aerials", "around_hole", "axle", "collar", "command_block", "drum_arm", "drum_hub", "engine",
           "engine_frame", "housing", "retro_nozzle", "shields", "paired_hulls", "spine", "spine_block", "tail"]
