"""The Hyperion-class heavy cruiser's structure (M10-T22): the parts measured off the reference model, on the capital library.

Authored frame: x to starboard from the hull's axis, y up from the middle of the reference's box, z aft from the bow guns'
muzzles; 1 025.39 m long (docs/assets-capital.md, "M10 lengths (T01)"). Numbers are the reference's own
(``references/EA Hyperion Class Heavy Cruiser.stl`` at that length, cut with ``tools/refview/sections.py``);
docs/design-references.md describes the ship. The build is symmetric about the hull's axis (the maintainer): the reference's
parts stand up to 3.4 m off it and its starboard flank toes in aft, modelling slop the show's ship does not have
(``ea_hyperion_fidelity.py`` holds the numbers).

Bow to stern:

* **forward hull** (91 to 437.5 m): a wedge widening to 128 m, flat roofed, its keel deepening aft; a raised deck on the roof
  from 157 m, sloping up to the dome turret's deck; a keel strake under it; a pair of gun clusters and torpedo tubes in the bow
  face; a dome turret on each flank;
* **hangar sponsons** (376 to 437.5 m): a box on each lower flank, a launch bay for Starfuries and one for a shuttle in its face,
  a thruster bell on its aft face;
* **command tower** (391 to 479 m): a fin to 100 m above the axis with a turret on a drum; a blade through the hull behind it;
  the ventral fin to 100 m below with two turret pods under it;
* **truss** (479 to 677 m): a neck, a dorsal girder, a lower chord rising aft, the side web's diagonals and a lattice of
  horizontal struts;
* **reactor module** (677 to 746 m): a 119 m box with a dome turret;
* **aft spine** (746 to 889 m): a girder, a chord falling to the engine block and its diagonals;
* **fuel tanks** (838 to 890 m): four capsules in front of the block's corners, in a frame;
* **engine block** (889 to 952 m) and three bells (952 to 1 025 m).

Every function returns modules already named for their damage section and side; ``assets/ea_hyperion.py`` adds the weapons,
bays, lights and the section table. The show's royal-blue bands are parts painted in the ``stripe`` role.
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

LENGTH_M = 1025.39
BOW_Z, FORE_END_Z = 91.0, 437.5  # the forward hull and the sponsons end square
FORE_BANDS = ((172.0, 192.0), (318.0, 338.0))  # the show's two bands round the forward hull, ahead of and behind the flank turrets
DECK_Z = (157.0, 441.0)  # aft, under the tower to the blade
DECK_W, DECK_H = 28.0, 52.5  # the raised deck's half width and its roof
TOWER_Z = (391.0, 479.0)
TOWER_TOP = 100.0
TOWER_DRUM_Y = 118.0  # the top of the drum the tower's turret stands on
FIN_BOTTOM = -100.0
NECK_END_Z = 513.5
MODULE_Z = (677.0, 746.0)
MODULE_W, MODULE_Y = 58.5, (-4.4, 57.0)
BLOCK_Z = (889.0, 952.0)
BLOCK_W, BLOCK_Y = 123.0, (-32.2, 57.0)
ENGINE_Y = 12.3
NOZZLE_XS = (-65.0, 0.0, 65.0)  # the port bell is the starboard one's twin
NOZZLE_R = 27.0
TANKS, TANK_Z = (("top", 65.0, 36.0, 13.5), ("low", 66.5, -14.4, 14.0)), (838.0, 890.0)  # x, y, radius
SPONSON_Z = (376.0, FORE_END_Z)
SPONSON_X = 85.75
SPONSON_Y = (-5.0, -39.5)
THRUSTER_X, THRUSTER_Y = 70.9, -16.0
BAY_Z = (408.0, 430.0)  # the bays' stretch of the sponson's face, walls included
BAY_DEPTH, BAY_WALL = 26.0, 2.0
FURY_BAY_MOUTH, SHUTTLE_BAY_MOUTH = (18.0, 12.0), (18.0, 9.0)  # a Starfury is 11 m across and 7 m tall; the shuttle 18.6 m long
STARFURIES_PER_BAY, SHUTTLES_PER_BAY = 3, 1
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


def _mirror(outline_r: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """A symmetric outline from its starboard half (top to bottom)."""
    return outline_r + [(-x, y) for x, y in reversed(outline_r)]


# --- the forward hull ----------------------------------------------------------------------------------------------------
# Half width, the bottom's outer edge, the keel flat and the flat's half width along the hull (the reference's cuts).
HALF_W = [(BOW_Z, 37.5), (100.0, 42.0), (240.0, 62.7), (250.0, 64.0), (280.0, 63.4), (330.0, 62.5), (376.0, 61.7), (FORE_END_Z, 60.6)]
EDGE_Y = [(BOW_Z, -1.0), (100.0, -7.0), (240.0, -26.0), (370.0, -37.5), (FORE_END_Z, -37.5)]
FLAT_Y = [(BOW_Z, -3.0), (100.0, -14.0), (240.0, -35.8), (370.0, -39.0), (FORE_END_Z, -39.0)]
FLAT_W = [(BOW_Z, 30.0), (100.0, 32.0), (240.0, 36.0), (370.0, 58.0), (FORE_END_Z, 58.0)]
ROOF_Y = [(BOW_Z, 26.0), (100.0, 29.0), (FORE_END_Z, 29.0)]
BEVEL = 4.0



def fore_outline(z: float) -> list[tuple[float, float]]:
    """The forward hull's cross-section at ``z``: flat roof with bevelled edges, upright flanks, a chamfered bottom."""
    w, top = _lerp(z, HALF_W), _lerp(z, ROOF_Y)
    return _mirror([(w - BEVEL, top), (w, top - BEVEL), (w, _lerp(z, EDGE_Y)), (_lerp(z, FLAT_W), _lerp(z, FLAT_Y))])


def fore_hull(s: Style) -> list[cp.Module]:
    """The forward hull in lengths between its stations, the two bands painted; ahead of 250 m the bow, aft the magazine."""
    stations = sorted({BOW_Z, 100.0, 240.0, 250.0, 280.0, 330.0, 376.0, FORE_END_Z, *(z for band in FORE_BANDS for z in band)})
    out = []
    for k, (a, b) in enumerate(zip(stations, stations[1:], strict=False)):
        band = next((i for i, (lo, hi) in enumerate(FORE_BANDS) if lo <= a and b <= hi), None)  # a band may hold a table station
        roles = HULL if band is None else BAND
        name = f"fore_hull_{k + 1}" if band is None else f"fore_band_{band + 1}_{k + 1}"
        m = cs.convex(name, _ring(fore_outline(a), a) + _ring(fore_outline(b), b), s, roles)
        if a <= 118.0 < b:
            m = dataclasses.replace(m, hardpoints=(renegade_xs()["roof"], name_marks()["roof"]))
        if a <= NUMBER_Z < b:
            m = dataclasses.replace(m, hardpoints=(*m.hardpoints, *hull_numbers()))
        out.append(_put("bow" if b <= 250.0 else "magazine", m))
    return out


def deck(s: Style) -> list[cp.Module]:
    """The raised deck on the roof: a wedge sloping up from 157 m to the turret deck, its edges chamfered; from 270 m its flanks
    lean in all the way up, flat to the tower, the aft band painted across it."""
    z0, z1 = DECK_Z
    ring = _mirror([(DECK_W - 8.0, DECK_H), (DECK_W, DECK_H - 6.0), (DECK_W, 28.0)])
    leaning = _mirror([(DECK_W - 8.0, DECK_H), (DECK_W, 29.0), (DECK_W, 28.0)])
    nose = [(x, 28.0, z0) for x in (-DECK_W, DECK_W)] + [(x, 29.5, z0) for x in (-DECK_W + 6.0, DECK_W - 6.0)]
    wedge = cs.convex("deck_wedge", nose + _ring(ring, 250.0), s, HULL)
    a, b = FORE_BANDS[1]
    flat = cs.convex("deck_flat", _ring(ring, 250.0) + _ring(leaning, 270.0), s, HULL)
    mid = cs.prism("deck_mid", leaning, 270.0, a, s, HULL)
    band = cs.prism("deck_band", leaning, a, b, s, BAND)
    aft = cs.prism("deck_aft", leaning, b, z1, s, HULL)
    return [_put("bow", wedge), _put("magazine", flat), _put("magazine", mid), _put("magazine", band), _put("magazine", aft)]


def keel(s: Style) -> list[cp.Module]:
    """The keel strake under the forward hull, deepest under the turret deck, cut at the two hull bands so each ring is painted
    across the belly too."""
    bottom = [(186.0, -28.0), (200.0, -41.0), (240.0, -47.0), (270.0, -50.5), (320.0, -50.5), (345.0, -46.0), (362.0, -40.0), (365.0, -39.0)]

    def ring(z: float) -> list[tuple[float, float, float]]:
        yb = _lerp(z, bottom)
        return [(x, y, z) for x in (-24.5, 24.5) for y in (-25.0, yb + 3.0)] + [(x, yb, z) for x in (-21.0, 21.0)]
    cuts = sorted({*(z for z, _ in bottom), *(z for band in FORE_BANDS for z in band if 186.0 <= z <= 365.0)})
    out = []
    for a, b in zip(cuts, cuts[1:], strict=False):
        painted = any(lo <= a and b <= hi for lo, hi in FORE_BANDS)
        out.append(_put("magazine", cs.convex(f"keel_{len(out) + 1}", ring(a) + ring(b), s, BAND if painted else HULL)))
    return out


def sponson(s: Style) -> list[cp.Module]:
    """The starboard hangar sponson: a box on the lower flank, rounded aft, its flank bulging a little at mid height, its face
    open for the two bays (a Starfury bay over a shuttle bay) and solid round them."""
    top, bottom = SPONSON_Y
    plan = [(376.0, 63.0), (380.0, 74.0), (388.0, 79.25), (395.0, 82.75), (402.0, 84.25), (BAY_Z[0], SPONSON_X), (BAY_Z[1], SPONSON_X),
            (FORE_END_Z, SPONSON_X)]  # the flank's half width at mid height

    def piece(name: str, za: float, zb: float) -> cp.Module:
        rows = [(z, x) for z, x in plan if za <= z <= zb]
        pts = [(x, y, z) for z, x in rows for y in (top - 4.0, bottom + 4.5)] + [(x - 2.5, top, z) for z, x in rows]
        pts += [(x - 3.5, bottom, z) for z, x in rows]
        pts += [(40.0, y, z) for z in (za, zb) for y in (top, bottom)]
        return cs.convex(name, pts, s, HULL)

    back = BAY_Z[0], BAY_Z[1]
    inner = SPONSON_X - BAY_DEPTH - BAY_WALL
    out = [piece("sponson_fore_r", 376.0, BAY_Z[0]), piece("sponson_aft_r", BAY_Z[1], FORE_END_Z),
           cs.box("sponson_back_r", (40.0, bottom, back[0]), (inner, top, back[1]), s, HULL),
           cs.convex("sponson_sill_r", [(x, y, z) for z in back for x, y in ((inner, -34.0), (SPONSON_X, -34.0), (SPONSON_X, bottom + 3.5),
                                                                              (SPONSON_X - 3.5, bottom), (inner, bottom))], s, HULL)]
    outward = np.array([[0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]])  # a bay's way out (-z) turned to +x, its width along z
    zc = 0.5 * (BAY_Z[0] + BAY_Z[1])
    fury_y = top - 0.5 * FURY_BAY_MOUTH[1] - BAY_WALL
    shuttle_y = top - FURY_BAY_MOUTH[1] - 2.0 * BAY_WALL - 0.5 * SHUTTLE_BAY_MOUTH[1] - BAY_WALL
    for name, mouth, y, craft, capacity in (("bay_fury_r", FURY_BAY_MOUTH, fury_y, FURY, STARFURIES_PER_BAY),
                                            ("bay_shuttle_r", SHUTTLE_BAY_MOUTH, shuttle_y, SHUTTLE, SHUTTLES_PER_BAY)):
        bay = bays.launch_bay(name, mouth, BAY_DEPTH, s, BAY_WALL, lit=True).transformed(outward, (SPONSON_X, y, zc))
        out.append(bay.with_params(cp.BAY, craft=craft, capacity=capacity))
    out.append(cs.round_body("sponson_thruster_r", (THRUSTER_X, THRUSTER_Y, FORE_END_Z - 1.0), (THRUSTER_X, THRUSTER_Y, FORE_END_Z + 15.5),
                             [(0.0, 0.0), (0.0, 3.0), (4.0, 3.5), (14.0, 6.2), (16.5, 6.4), (16.5, 0.0)], s, s.material("hull_dark"), sides=12,
                             creases={1, 2, 4}, skin=cp.SKIN_FITTING))  # a bell flaring aft from the sponson's aft face
    return [_put("hangar_r", m, cp.RIGHT) for m in out]


def bow_guns(s: Style) -> cp.Module:
    """The starboard heavy plasma cannon: a cluster of long barrels from the bow face, fixed forward (it aims by the hull)."""
    barrels = (((20.75, 22.5), 1.4, 0.0), ((29.75, 8.5), 1.3, 2.0), ((20.5, 2.0), 1.2, 8.0), ((12.0, 12.5), 2.0, 18.0))
    parts = []
    bar, bore = s.material("barrel"), s.material("bore")
    for k, ((x, y), r, z0) in enumerate(barrels):
        profile = [(0.0, 0.0), (0.0, 0.55 * r), (0.6, r), (BOW_Z + 2.0 - z0, r), (BOW_Z + 2.0 - z0, 0.0)]
        parts.append(cs.round_body(f"gun_barrel_{k + 1}", (x, y, BOW_Z + 2.0), (x, y, z0), profile, s, [bore, bar, bar, bar], sides=8,
                                   creases={1, 2, 3}, skin=cp.SKIN_NONE))
    gun = cs.compound("plasma_heavy_r", parts)
    point = cp.Hardpoint("plasma_heavy_r", cp.TURRET, (22.0, 12.0, 6.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0),
                         {"traverse_deg": 3.0, "elevation_deg": [-3.0, 3.0], "barrel_m": round(BOW_Z - 6.0, 3), "barrels": len(barrels)})
    return dataclasses.replace(gun, hardpoints=(point,))


def particle_cannon(name: str, root: tuple[float, float, float], muzzle: tuple[float, float, float], s: Style, spread: float = 7.0,
                    rows: tuple[float, ...] = (0.0, -6.5), normal: tuple[float, float, float] = (0.0, 1.0, 0.0)) -> cp.Module:
    """A phased particle cannon: long barrels in pairs (one pair per ``rows`` offset in height) from a housing at ``root`` to
    ``muzzle`` (the deck's guns raised over the bow, the keel's lowered under it), its beam leaving along the barrels; ``normal``
    is the hull's outward normal where it stands."""
    a, b = np.asarray(root, dtype=float), np.asarray(muzzle, dtype=float)
    axis = (b - a) / np.linalg.norm(b - a)
    length = float(np.linalg.norm(b - a))
    bar, bore, dark = s.material("barrel"), s.material("bore"), s.material("hull_dark")
    parts = [cs.box(f"{name}_housing", (a[0] - spread - 3.0, a[1] + min(rows) - 3.5, a[2] - 4.0), (a[0] + spread + 3.0, a[1] + max(rows) + 3.5, a[2] + 10.0), s, DARK,
                    skin=cp.SKIN_FITTING)]
    for k, (dx, dy) in enumerate((x, y) for y in rows for x in (-spread, spread)):
        off = np.array([dx, dy, 0.0])
        profile = [(0.0, 0.0), (0.0, 2.6), (0.35 * length, 2.6), (0.35 * length, 1.9), (length, 1.9), (length, 0.0)]
        parts.append(cs.round_body(f"{name}_barrel_{k + 1}", a + off, b + off, profile, s, [dark, bar, bar, bar, bore], sides=10,
                                   creases={1, 2, 3, 4}, skin=cp.SKIN_NONE))
    gun = cs.compound(name, parts)
    up = np.asarray(normal, dtype=float) - float(np.dot(normal, axis)) * axis  # the hull's normal, square to the barrels
    point = cp.Hardpoint(name, cp.BEAM, tuple(float(v) for v in b), tuple(float(v) for v in axis), tuple(float(v) for v in up),
                         {"arc_deg": 45.0, "aperture_m": 3.8})
    return dataclasses.replace(gun, hardpoints=(point,))


def dome_turret(name: str, radius: float, s: Style, collar_m: float = 3.0, barrels: int = 2) -> cp.Module:
    """A dome turret (the Hyperion's pulse cannons): a collar, a hemisphere and twin barrels from its face, built on a mount
    (+y its normal, -z its front)."""
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
                          s, [bar, bar, bar, bar, bore], sides=8, creases={1, 2, 3, 4}, skin=cp.SKIN_NONE)
            for k, x in enumerate(np.linspace(-0.3 * r, 0.3 * r, barrels))]
    turret = cs.compound(name, [dome, *guns])
    point = cp.Hardpoint(name, cp.TURRET, tuple(pivot), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0),
                         {"traverse_deg": 180.0, "elevation_deg": [-5.0, 85.0], "barrel_m": round(length, 3), "barrels": barrels})
    return dataclasses.replace(turret, hardpoints=(point,))


# --- the command tower -----------------------------------------------------------------------------------------------------
TOWER_BAND = (68.0, 82.0)  # the show's band round the tower


def tower(s: Style) -> list[cp.Module]:
    """The command tower above the roof in three heights (the middle one the band), the drum its turret stands on and a mast;
    the blade through the hull behind it, the ventral body and fin, and the two turret pods under the fin."""
    def ring(y: float) -> list[tuple[float, float, float]]:
        t = (y - 52.0) / (TOWER_TOP - 52.0)
        front, w_front, w_aft = TOWER_Z[0] + 25.0 * t, 21.0 - 1.0 * t, 24.5 - 3.5 * t
        return [(-w_front, y, front), (w_front, y, front), (w_aft, y, TOWER_Z[1]), (-w_aft, y, TOWER_Z[1])]

    heights = (52.0, TOWER_BAND[0], TOWER_BAND[1], TOWER_TOP)
    out = [cs.convex(f"tower_{k + 1}" if k != 1 else "tower_band", ring(a) + ring(b), s, BAND if k == 1 else HULL)
           for k, (a, b) in enumerate(zip(heights, heights[1:], strict=False))]
    xs, names = renegade_xs(), name_marks()
    out[0] = dataclasses.replace(out[0], hardpoints=(names["tower_r"], names["tower_l"]))
    out[2] = dataclasses.replace(out[2], hardpoints=(xs["tower_r"], xs["tower_l"]))
    out.append(cs.round_body("tower_drum", (0.0, TOWER_TOP - 1.0, 462.0), (0.0, TOWER_DRUM_Y, 462.0), [(0.0, 0.0), (0.0, 12.75), (TOWER_DRUM_Y - TOWER_TOP + 1.0, 12.75), (TOWER_DRUM_Y - TOWER_TOP + 1.0, 0.0)],
                             s, s.material("hull"), sides=20, creases={1, 2}))
    out.append(cs.rod("tower_mast", (0.0, TOWER_TOP - 1.0, 410.0), (0.0, 104.0, 410.0), 1.5, s))
    out.append(cs.round_body("tower_dish", (0.0, 103.5, 408.0), (0.0, 110.5, 408.0), [(0.0, 0.0), (0.0, 4.0), (5.0, 16.0), (7.0, 16.0), (7.0, 0.0)], s,
                             s.material("hull_panel"), sides=16, creases={1, 2, 3}, skin=cp.SKIN_FITTING))
    z0, z1 = FORE_END_Z - 1.0, TOWER_Z[1]
    blade = [(x, y, z) for z in (z0, z1) for x, y in ((26.3, 52.0), (27.9, 25.0), (27.9, -30.0), (25.5, -64.0))]
    out.append(cs.convex("tower_blade", blade + [(-x, y, z) for x, y, z in blade], s, HULL))
    body = [(22.5, -38.0, 384.0), (22.5, -64.0, 398.0), (24.5, -38.0, z1), (24.5, -64.0, z1), (14.0, -64.0, 511.0), (14.0, -38.0, NECK_END_Z)]
    out.append(cs.convex("ventral_body", body + [(-x, y, z) for x, y, z in body], s, HULL))
    fin = [(22.5, -64.0, 398.0), (22.5, FIN_BOTTOM, 419.0), (25.0, FIN_BOTTOM, z1), (24.5, -64.0, z1), (13.5, -88.0, 482.0), (13.5, -64.0, 511.0)]
    out.append(cs.convex("ventral_fin", fin + [(-x, y, z) for x, y, z in fin], s, HULL))
    r = 13.5
    arc = [(20.0 + r * np.sin(a), r * np.cos(a)) for a in np.linspace(0.0, 0.5 * np.pi, 7)[1:-1]]
    for k, z in enumerate((437.0, 465.5)):
        profile = [(0.0, 0.0), (0.0, r), (20.0, r), *arc, (20.0 + r, 0.0)]
        out.append(cs.round_body(f"ventral_pod_{k + 1}", (0.0, FIN_BOTTOM + 1.0, z), (0.0, FIN_BOTTOM - 20.0 - r, z), profile, s,
                                 s.material("hull"), sides=20, creases={1, 2}))
    return [_put("bridge", m) for m in out]


# --- the truss, the reactor module and the aft spine ---------------------------------------------------------------------
def _member(name: str, a: tuple[float, float], b: tuple[float, float], half_x: float, half_z: float, s: Style) -> cp.Module:
    """A diagonal of a side web from (z, y) ``a`` to ``b``: ``half_x`` thick either side of the axis, ``2 * half_z`` along z."""
    return cs.convex(name, [(x, y, z + dz) for z, y in (a, b) for x in (-half_x, half_x) for dz in (-half_z, half_z)], s, DARK)


def lower_chord_fore(z: float) -> float:
    """The forward truss's lower chord: its underside at ``z``, rising aft."""
    return _lerp(z, [(NECK_END_Z, -37.0), (MODULE_Z[0], 6.2)])


def lower_chord_aft(z: float) -> float:
    """The aft spine's lower chord: its top at ``z``, falling to the engine block."""
    return _lerp(z, [(MODULE_Z[1], 11.1), (BLOCK_Z[0], -22.9)])


def truss(s: Style) -> list[cp.Module]:
    """The neck behind the tower, the dorsal girder, the lower chord, the side web's diagonals and the lattice of struts round
    the girder ahead of the reactor module."""
    z0, z1 = NECK_END_Z, MODULE_Z[0]
    neck = [(16.0, 56.0, TOWER_Z[1]), (16.0, 56.0, 487.0), (14.0, 48.0, 507.0), (13.5, 46.5, z0), (16.0, -40.0, TOWER_Z[1]), (13.5, -36.0, z0)]
    out = [cs.convex("neck", neck + [(-x, y, z) for x, y, z in neck], s, HULL)]
    girder = [(13.5, 32.0, z0), (13.5, 46.5, z0), (13.5, 55.5, 545.0), (13.5, 55.5, 645.0), (13.5, 32.0, 645.0)]
    out.append(cs.convex("girder", girder + [(-x, y, z) for x, y, z in girder], s, HULL))
    root = [(13.5, 32.0, 644.0), (13.5, 55.5, 644.0), (13.5, 44.0, 660.0), (13.5, 44.0, z1 + 1.0), (13.5, 32.0, z1 + 1.0)]
    out.append(cs.convex("girder_root", root + [(-x, y, z) for x, y, z in root], s, HULL))
    out.append(cs.box("girder_keel", (-10.0, 26.0, z0), (10.0, 32.5, z1 + 1.0), s, DARK))
    out.append(cs.box("girder_flange", (-3.0, 21.0, z0), (3.0, 26.5, 632.0), s, DARK))
    out.append(cs.box("girder_sides", (-14.6, 31.5, 550.0), (14.6, 52.0, 636.0), s, HULL))  # the girder's plated middle, a little wider
    out.append(cs.box("girder_deck", (-15.6, 25.5, 575.0), (15.6, 28.5, z1 + 1.0), s, DARK))  # the plate the lattice hangs from
    chord = [(x, y, z) for z in (z0 - 1.0, z1 + 1.0) for x in (-13.5, 13.5) for y in (lower_chord_fore(z), lower_chord_fore(z) + 6.0)]
    out.append(cs.convex("chord_fore", chord, s, HULL))
    top = 26.0
    for k, (a, b) in enumerate(((518.0, 553.0), (583.0, 553.0), (588.0, 608.0), (630.0, 608.0))):
        out.append(_member(f"web_fore_{k + 1}", (a, top), (b, lower_chord_fore(b) + 6.0), 3.0, 4.5, s))
    return [_put("truss", m) for m in out] + [_put("truss", m, cp.RIGHT) for m in lattice(s)]


def lattice(s: Style) -> list[cp.Module]:
    """The starboard half of the horizontal struts round the girder: a long strut out from the girder and a box frame of
    rails and zigzag diagonals ahead of the module, all in one plane."""
    y0, y1 = 25.5, 28.5

    def strut(name: str, a: tuple[float, float], b: tuple[float, float], half: float = 1.5) -> cp.Module:
        (za, xa), (zb, xb) = a, b
        d = np.array([xb - xa, zb - za]) / np.hypot(xb - xa, zb - za)
        nx, nz = -d[1] * half, d[0] * half
        return cs.convex(name, [(x + sx * nx, y, z + sx * nz) for z, x in (a, b) for sx in (-1.0, 1.0) for y in (y0, y1)], s, DARK)

    z0, z1 = 624.0, MODULE_Z[0]
    inner, outer, half = 38.1, 53.85, 1.85
    out = [strut("strut_long_r", (555.0, 13.0), (622.0, 37.0), 3.0), strut("strut_short_r", (626.0, 14.0), (604.0, 33.0), 1.6),
           strut("pipe_fore_r", (566.0, 16.65), (626.0, 16.65), 0.95), strut("pipe_aft_r", (627.0, 16.3), (z1, 16.3), 0.9),
           cs.box("lattice_outer_r", (outer - half, y0, z0), (outer + half, y1, z1), s, DARK),
           cs.box("lattice_inner_r", (inner - half, y0, z0 + 3.0), (inner + half, y1, z1), s, DARK),
           cs.box("lattice_front_r", (12.0, y0, z0), (outer + half, y1, z0 + 3.5), s, DARK)]
    # The zigzag between the rails: inner nodes at 627.5, 646 and 667 m, outer ones between them.
    nodes = [(627.5, inner), (636.0, outer - half), (646.0, inner), (656.0, outer - half), (667.0, inner), (676.0, outer - half)]
    for k, (a, b) in enumerate(zip(nodes, nodes[1:], strict=False)):
        out.append(strut(f"lattice_diag_{k + 1}_r", a, b, 1.25))
    return out


def module(s: Style) -> list[cp.Module]:
    """The reactor module on the truss: a box with chamfered edges and louvred panels on its flanks."""
    z0, z1 = MODULE_Z
    lo, hi = MODULE_Y
    c = 5.0
    box = cs.prism("module", _mirror([(MODULE_W - c, hi), (MODULE_W, hi - c), (MODULE_W, lo + c), (MODULE_W - c, lo)]), z0, z1, s, HULL)
    louvre = cs.box("module_louvre_r", (MODULE_W - 0.5, 4.0, z0 + 10.0), (MODULE_W + 1.0, 46.0, z1 - 10.0), s, DARK, skin=cp.SKIN_FITTING)
    return [_put("reactor", box), _put("reactor", louvre, cp.RIGHT)]


def aft_spine(s: Style) -> list[cp.Module]:
    """The aft spine: the dorsal girder, the lower chord falling to the engine block and the web's diagonals."""
    z0, z1 = MODULE_Z[1] - 1.0, BLOCK_Z[0] + 1.0
    girder = cs.prism("spine_girder", _mirror([(5.5, 45.0), (14.5, 42.0), (14.5, 31.0), (12.5, 23.5)]), z0, z1, s, HULL)
    collar = cs.prism("spine_collar", _mirror([(12.0, 45.5), (17.5, 42.5), (17.5, 23.5)]), z0, 765.0, s, PANEL)
    chord = cs.convex("chord_aft", [(x, y, z) for z in (z0, z1) for x in (-13.0, 13.0) for y in (lower_chord_aft(z), lower_chord_aft(z) - 9.6)], s, HULL)
    out = [collar, chord]
    for k, (a, b) in enumerate(((782.0, 800.0), (823.0, 805.0), (832.0, 851.0), (887.0, 862.0))):
        out.append(_member(f"web_aft_{k + 1}", (a, 23.5), (b, lower_chord_aft(b)), 5.5, 4.5, s))
    return [_put("spine_aft", m) for m in (girder, *out)]


# --- the tanks and the engines -------------------------------------------------------------------------------------------
def tanks(s: Style) -> list[cp.Module]:
    """The starboard fuel tanks, two capsules ahead of the block's corner, and the frame round them."""
    z0, z1 = TANK_Z
    out = []
    for tag, x, y, r in TANKS:
        nose = [(6.0 * (1.0 - np.cos(a)), r * np.sin(a)) for a in np.linspace(0.0, 0.5 * np.pi, 6)[1:]]  # a blunt cap, 6 m deep
        profile = [(0.0, 0.0), *nose, (z1 - z0, r), (z1 - z0, 0.0)]
        out.append(cs.round_body(f"tank_{tag}_r", (x, y, z0), (x, y, z1), profile, s, s.material("hull_panel"), sides=16, creases={len(nose)}))
    frame_z = 854.5  # the frame's forward cross members
    for k, (x, y) in enumerate(((43.5, 52.5), (43.5, -31.0), (96.0, 52.5), (96.0, -31.0))):
        out.append(cs.rod(f"tank_rail_{k + 1}_r", (x, y, z1), (x, y, frame_z - 1.0), 1.3, s))
    for k, x in enumerate((43.5, 96.0)):
        out.append(cs.rod(f"tank_post_{k + 1}_r", (x, -31.0, frame_z), (x, 52.5, frame_z), 1.3, s))
    for k, y in enumerate((52.5, -31.0)):
        out.append(cs.rod(f"tank_cross_{k + 1}_r", (16.0, y, frame_z), (96.0, y, frame_z), 1.2, s))
    out.append(cs.rod("tank_nose_frame_r", (62.0, 11.0, 829.5), (82.0, 11.0, 829.5), 1.2, s))
    out.append(cs.rod("tank_nose_brace_r", (82.0, 11.0, 829.5), (88.0, 11.0, 851.0), 1.2, s))
    out.append(cs.rod("tank_outrigger_r", (96.0, 28.5, frame_z), (118.0, 28.5, frame_z), 1.2, s))
    out.append(cs.rod("tank_outrigger_knee_r", (118.0, 28.5, frame_z), (123.5, 28.5, 864.0), 1.2, s))
    out.append(cs.rod("tank_outrigger_rail_r", (123.5, 28.5, z1), (123.5, 28.5, 864.0), 1.2, s))
    return [_put("fuel_r", m, cp.RIGHT) for m in out]


def engines(s: Style) -> list[cp.Module]:
    """The engine block (its aft rim the show's band) and the three bells, each with its engine hardpoint."""
    z0, z1 = BLOCK_Z
    lo, hi = BLOCK_Y
    c = 9.0
    outline = _mirror([(BLOCK_W - c, hi), (BLOCK_W, hi - c), (BLOCK_W, lo + c), (BLOCK_W - c, lo)])
    rim = 6.0
    face = _mirror([(BLOCK_W - c - 5.0, hi - 5.0), (BLOCK_W - 5.0, hi - c - 5.0), (BLOCK_W - 5.0, lo + c + 5.0), (BLOCK_W - c - 5.0, lo + 5.0)])
    out = [cs.prism("engine_block", outline, z0, z1 - rim, s, HULL), cs.prism("engine_block_rim", outline, z1 - rim, z1, s, BAND),
           cs.prism("engine_block_face", face, z1 - 1.0, z1 + 0.4, s, HULL)]  # the aft face inside the band: only its rim is blue
    ear = cs.box("engine_ear_r", (BLOCK_W - 7.0, lo + c, 879.5), (BLOCK_W, hi - c, z0 + 1.0), s, HULL)  # the block's outer corners reach forward
    hull, dark, metal, glow = s.material("hull"), s.material("hull_dark"), s.material("nozzle"), s.material("nozzle_throat")
    at = lambda z: z - (z1 - 2.0)  # noqa: E731 - the profile is written at the ship's z
    profile = [(0.0, 0.0), (0.0, 16.0), (at(958.0), 15.0), (at(976.0), 22.0), (at(1000.0), 25.8), (at(LENGTH_M), NOZZLE_R),
               (at(LENGTH_M), NOZZLE_R - 2.0), (at(LENGTH_M) - 12.0, NOZZLE_R - 3.5), (at(LENGTH_M) - 12.0, 0.0)]  # a shallow bore, its wall thin
    mats = [dark, dark, metal, metal, metal, glow, glow, glow]
    bells = []
    for name, part, x, side in (("engine_centre", "engine_bell", NOZZLE_XS[1], cp.CENTRE), ("engine_r", "engine_bell_r", NOZZLE_XS[2], cp.RIGHT)):
        bell = cs.round_body(part, (x, ENGINE_Y, z1 - 2.0), (x, ENGINE_Y, LENGTH_M), profile, s, mats, sides=24,
                             creases={1, 2, 3, 4, 5, 6, 7}, skin=cp.SKIN_FITTING, hollow_from=6)
        point = cp.Hardpoint(name, cp.ENGINE, (x, ENGINE_Y, LENGTH_M), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), {"share": 1.0 / 3.0, "radius_m": NOZZLE_R - 2.0})
        bells.append(_put("engines", dataclasses.replace(bell, hardpoints=(point,)), side))
    return [_put("engines", m) for m in out] + bells + [_put("engines", ear, cp.RIGHT)]


# --- marks -----------------------------------------------------------------------------------------------------------------
RENEGADE_RED = (0.78, 0.09, 0.07)
X_HEIGHT_M = 26.0


def renegade_xs() -> dict[str, cp.Hardpoint]:
    """The renegades' small red X paint marks (M10-T02), shown only on a renegade ship: one on each flank of the tower and one
    on the forward roof. Keyed by where they go."""
    def x(name: str, at: tuple[float, float, float], normal: tuple[float, float, float], up: tuple[float, float, float]) -> cp.Hardpoint:
        return fittings.hull_mark(name, at, normal, up, X_HEIGHT_M, colour=RENEGADE_RED, text="X", only_faction="renegades")
    return {"tower_r": x("mark_x_r", (20.6, 90.0, 452.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
            "tower_l": x("mark_x_l", (-20.6, 90.0, 452.0), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
            "roof": x("mark_x_roof", (0.0, 29.05, 118.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0))}


NAME_BLUE = (0.141, 0.322, 0.706)  # the bands' royal blue (sRGB), as the show's lettering
NAME_HEIGHT_M = {"roof": 9.0, "tower": 7.0}
NAME_TOWER_Y = 60.0  # under the tower's band


def name_marks() -> dict[str, cp.Hardpoint]:
    """The ship's own name in royal-blue block print, as the show paints HYPERION: across the forward roof ahead of the deck
    (reading from above with the bow below) and along each flank of the tower under its band. Keyed by where they go."""
    def mark(name: str, at: tuple[float, float, float], normal: tuple[float, float, float], up: tuple[float, float, float], where: str) -> cp.Hardpoint:
        return fittings.hull_mark(name, at, normal, up, NAME_HEIGHT_M[where], colour=NAME_BLUE, text="name")
    # The tower's flank leans out aft: its outward normal and the point halfway along it at the name's height.
    t = (NAME_TOWER_Y - 52.0) / (TOWER_TOP - 52.0)
    (x0, z0), (x1, z1) = (21.0 - 1.0 * t, TOWER_Z[0] + 25.0 * t), (24.5 - 3.5 * t, TOWER_Z[1])
    n = np.array([z1 - z0, 0.0, -(x1 - x0)]) / np.hypot(z1 - z0, x1 - x0)
    mid = (0.5 * (x0 + x1) + 0.05, NAME_TOWER_Y, 0.5 * (z0 + z1))
    normal = (round(float(n[0]), 4), 0.0, round(float(n[2]), 4))
    return {"roof": mark("mark_name_roof", (0.0, 29.05, 146.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), "roof"),
            "tower_r": mark("mark_name_r", mid, normal, (0.0, 1.0, 0.0), "tower"),
            "tower_l": mark("mark_name_l", (-mid[0], mid[1], mid[2]), (-normal[0], 0.0, normal[2]), (0.0, 1.0, 0.0), "tower")}


NUMBER_INK = (0.07, 0.10, 0.24)  # the show's hull number is dark slate blue, darker than the bands
NUMBER_HEIGHT_M = 24.0
NUMBER_Z = 230.0  # between the bow band and the flank dome turret (273 m on), as the show paints it


def hull_numbers() -> tuple[cp.Hardpoint, cp.Hardpoint]:
    """The ship's hull number (the show's "21") painted low on each flank of the forward hull between the bands; the game picks the
    digits from the ship's name (``data/ships/names.json``, ``hull_numbers``)."""
    y, w = 4.0, _lerp(NUMBER_Z, HALF_W)
    return tuple(fittings.hull_mark(name, (sx * w, y, NUMBER_Z), (float(sx), 0.0, 0.0), (0.0, 1.0, 0.0), NUMBER_HEIGHT_M,
                                    colour=NUMBER_INK, text="number") for name, sx in (("mark_number_r", 1), ("mark_number_l", -1)))  # type: ignore[return-value]


__all__ = ["BAY_Z", "BLOCK_Y", "BLOCK_Z", "BOW_Z", "DECK_Z", "ENGINE_Y", "FIN_BOTTOM", "FORE_BANDS", "FORE_END_Z", "FURY", "LENGTH_M",
           "MODULE_Y", "MODULE_Z", "NOZZLE_XS", "SHUTTLE", "SHUTTLES_PER_BAY", "SPONSON_X", "STARFURIES_PER_BAY", "TOWER_TOP", "TOWER_Z", "aft_spine",
           "bow_guns", "deck", "dome_turret", "engines", "fore_hull", "fore_outline", "hull_numbers", "keel", "lattice", "module", "name_marks", "renegade_xs", "sponson",
           "tanks", "tower", "truss"]
