"""The Nova's eighteen twin plasma cannons (M10-T67), as the reference with guns has them
(``references/EA_Nova_Dreadnought_(with_guns).stl``, thing:6820713): one pod shape, a faceted housing round two long barrels
with a mast through it, stood on the hull in four ways. A pod beside the command block and one on each flank wing's tip, one on
each flank of the hangar block, and four on each ring lug's outrigger plates (above and below, either side): the fore and
middle lugs' face the bow, the aft lug's face the stern.

A pod is built in its own frame (x across, y out from the hull, z aft from the barrels' muzzles, the barrels' axis on
y = 0) and stood with :meth:`capital.Module.mounted`. Numbers are the reference's at 1 502.1 m.
"""

from __future__ import annotations

import dataclasses
from typing import NamedTuple

import numpy as np

from ..core import collision as col
from ..styles import Style
from . import capital as cp
from . import capital_solids as cs
from .ea_omega import DARK, PANEL

BARREL_X, BARREL_R, BARREL_M, BORE_M = 12.0, 8.9, 70.0, 3.0  # each barrel's offset across, its radius, length and bore's depth
MUZZLE_R = (9.6, 5.0)  # the muzzle sleeve's radius and the bore's
HOUSING_Z = ((58.0, 94.0), (94.0, 118.0))  # the housing's nose and body, from and to, behind the muzzles
HOUSING_W, HOUSING_IN, HOUSING_OUT = 29.0, -14.0, 14.0  # half width across; its inner face and its top, out from the barrels' axis
TAIL_Z, POD_M = 141.0, 141.0  # the narrow tail behind the housing ends the pod
MAST_R, MAST_IN = 1.6, -3.0  # the mast's radius and where it starts, out from the barrels' axis
# A ring lug's pod arm, behind the muzzles: its z; the plate's x and y (out from the axis), the brace's.
ARM_Z, ARM_X, ARM_Y, BRACE_X = (65.0, 102.0), (56.5, 113.5), (56.0, 53.5), (48.0, 85.0)
# The brace's y at its root and its tip: the upper one deepens to its root, the lower one sits lower (the reference's are not mirrored).
BRACE_Y = {1.0: ((33.0, 38.5), (36.5, 38.5)), -1.0: ((42.5, 44.5), (42.5, 44.5))}
TURRET_ARC = (-10.0, 90.0)  # as the Omega's turrets: a 200 degree cone round the mount's up
PLASMA = "ea_plasma_medium"


class Gun(NamedTuple):
    """One starboard pod: its name and section, the barrels' axis at the muzzles (x, y, z), its outward normal, which way it
    faces along the ship (-1 the bow, +1 the stern), its bracket's reach in to the hull and its mast (distance behind the
    muzzles, length out from the axis)."""

    name: str
    section: str
    muzzle: tuple[float, float, float]
    out: tuple[float, float, float]
    faces: float
    bracket: float
    mast: tuple[float, float]


RIGHT, UP, DOWN = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, -1.0, 0.0)
GUNS = (
    Gun("plasma_bow_r", "bow", (77.5, 0.8, 179.2), RIGHT, -1.0, 20.0, (102.5, 12.6)),
    Gun("plasma_wing_r", "bow", (105.5, 0.8, 286.6), RIGHT, -1.0, 17.5, (102.5, 85.5)),
    Gun("plasma_fore_top_r", "spine_fore", (95.0, 75.5, 380.0), UP, -1.0, 24.5, (102.5, 86.0)),
    Gun("plasma_fore_low_r", "spine_fore", (95.0, -75.5, 380.0), DOWN, -1.0, 24.5, (102.5, 86.0)),
    Gun("plasma_hangar_r", "hangar", (91.5, 0.8, 540.1), RIGHT, -1.0, 24.5, (102.5, 85.5)),
    Gun("plasma_mid_top_r", "spine_mid", (95.0, 75.5, 745.7), UP, -1.0, 24.5, (102.5, 86.0)),
    Gun("plasma_mid_low_r", "spine_mid", (95.0, -75.5, 745.7), DOWN, -1.0, 24.5, (102.5, 86.0)),
    Gun("plasma_aft_top_r", "spine_aft", (95.0, 75.5, 1041.7), UP, 1.0, 24.5, (108.0, 86.0)),
    Gun("plasma_aft_low_r", "spine_aft", (95.0, -75.5, 1041.7), DOWN, 1.0, 24.5, (108.0, 86.0)),
)


def _barrel(name: str, x: float, s: Style) -> cp.Module:
    """A long barrel from the housing to the muzzle: a thicker sleeve over its last stretch, a ring round that, and a dark bore.
    One twelve-sided hull collides for it: eighteen pods' worth of round steps would overrun a section's shape budget."""
    r, m, bore_m = BARREL_R, BARREL_M, BORE_M
    sleeve, bore_r = MUZZLE_R
    profile = [(0.0, 0.0), (0.0, r), (m - 26.0, r), (m - 26.0, sleeve), (m - 20.0, sleeve), (m - 20.0, sleeve + 0.8), (m - 16.0, sleeve + 0.8),
               (m - 16.0, sleeve), (m, sleeve), (m, bore_r), (m - bore_m, 0.0)]
    bar, bore = s.material("barrel"), s.material("bore")
    body = cs.round_body(name, (x, 0.0, m), (x, 0.0, 0.0), profile, s, [bar] * 9 + [bore], sides=16, creases=set(range(1, 10)), skin=cp.SKIN_NONE)
    reach = sleeve + 0.9
    ring = [(x + reach * np.cos(a), reach * np.sin(a)) for a in np.linspace(0.0, 2.0 * np.pi, 12, endpoint=False)]
    return dataclasses.replace(body, shapes=(col.hull(name, np.array([(u, v, z) for z in (0.0, m) for u, v in ring])),))


def _housing(name: str, s: Style) -> cp.Module:
    """The faceted housing round the barrels' roots: a low nose whose top rises aft to the full body, bevelled edges and a
    sloped back. Two pieces, so the nose's top can rise more steeply than a single hull would allow."""
    lo = HOUSING_IN

    def ring(z: float, half: float, hi: float, bottom: float = lo) -> list[tuple[float, float, float]]:
        return [(sx * x, y, z) for sx in (-1.0, 1.0) for x, y in ((half, bottom + 3.0), (half, hi - 3.0), (half - 4.0, bottom), (half - 4.0, hi))]

    (n0, n1), (b0, b1) = HOUSING_Z[0], HOUSING_Z[1]
    w = HOUSING_W
    nose = cs.convex(f"{name}_nose", [*ring(n0, w - 3.0, 2.0, lo + 4.0), *ring(n0 + 10.0, w, 3.0), *ring(n1, w, 7.0)], s, DARK, skin=cp.SKIN_FITTING)
    body = cs.convex(f"{name}_body", [*ring(b0, w, HOUSING_OUT), *ring(b1 - 7.0, w, HOUSING_OUT), *ring(b1, w - 6.0, HOUSING_OUT - 8.0, lo + 3.0)], s, DARK,
                     skin=cp.SKIN_FITTING)
    return cs.compound(name, [nose, body])


def _tail(name: str, s: Style) -> cp.Module:
    """The narrow tail behind the housing and the fin standing out of its top."""
    z0, z1 = HOUSING_Z[1][1], TAIL_Z
    tail = cs.convex(f"{name}_body", [(sx * w, y, z) for z, w, ys in ((z0, 24.0, (-8.0, 3.0)), (z1, 6.0, (-4.0, 1.5))) for sx in (-1.0, 1.0) for y in ys],
                     s, DARK, skin=cp.SKIN_FITTING)
    fin = cs.box(f"{name}_fin", (-7.0, 1.0, 123.5), (7.0, 21.0, 129.5), s, PANEL, skin=cp.SKIN_FITTING)
    return cs.compound(name, [tail, fin])


def pod(gun: Gun, s: Style) -> cp.Module:
    """One twin cannon pod in the ship's frame, with its turret hardpoint at the barrels' roots in the housing's nose."""
    n = gun.name
    parts = [_barrel(f"{n}_barrel_1", -BARREL_X, s), _barrel(f"{n}_barrel_2", BARREL_X, s), _housing(f"{n}_housing", s), _tail(f"{n}_tail", s),
             cs.box(f"{n}_bracket", (-11.0, -gun.bracket, 72.0), (11.0, HOUSING_IN + 1.0, 100.0), s, DARK, skin=cp.SKIN_FITTING),
             cs.rod(f"{n}_mast", (0.0, MAST_IN, gun.mast[0]), (0.0, gun.mast[1], gun.mast[0]), MAST_R, s)]
    root = HOUSING_Z[0][0]
    point = cp.Hardpoint(n, cp.TURRET, np.array([0.0, 0.0, root]), np.array([0.0, 0.0, -1.0]), np.array([0.0, 1.0, 0.0]),
                         {"traverse_deg": 180.0, "elevation_deg": list(TURRET_ARC), "barrel_m": root, "barrels": 2})
    body = dataclasses.replace(cs.compound(n, parts), hardpoints=(point,))
    # Built facing the bow (-z); a stern pod is turned end for end, its muzzles then the pod's aft end.
    return body.mounted(gun.muzzle, gun.out, (0.0, 0.0, gun.faces)).with_params(weapon=PLASMA)


def arm(gun: Gun, s: Style) -> cp.Module:
    """What carries a pod on a ring lug: the outrigger plate out under its housing and the brace below it from the lug's flank."""
    sign = gun.out[1]
    a, b = ARM_Z
    z0, z1 = (gun.muzzle[2] + a, gun.muzzle[2] + b) if gun.faces < 0.0 else (gun.muzzle[2] - b, gun.muzzle[2] - a)
    parts = [cs.box(f"{gun.name}_plate", (ARM_X[0], sign * ARM_Y[0], z0), (ARM_X[1], sign * ARM_Y[1], z1), s, PANEL),
             cs.convex(f"{gun.name}_brace", [(x, sign * y, z) for x, ys in zip(BRACE_X, BRACE_Y[sign], strict=True) for y in ys for z in (z0 + 4.0, z1 - 4.0)], s, DARK)]
    return cs.compound(gun.name.replace("plasma_", "gun_arm_"), parts)


def guns(s: Style) -> list[cp.Module]:
    """Every starboard pod in its section, and the arms of those on the ring lugs (each gets a port twin)."""
    out = [pod(g, s).in_section(g.section).on_side(cp.RIGHT) for g in GUNS]
    return out + [arm(g, s).in_section(g.section).on_side(cp.RIGHT) for g in GUNS if g.out != RIGHT]


__all__ = ["GUNS", "PLASMA", "Gun", "arm", "guns", "pod"]
