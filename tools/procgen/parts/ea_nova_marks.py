"""The Nova's paint and lamps (M10-T67), placed as the show's stills (``references/show/m10/ea_nova/``, and the Omega's, which
wears them alike) place them on the command block's armour:

* **name**: the ship's own name in black block print on a light grey board ringed in black, high on each vertical plate under
  its top edge and toward its aft end (the stills' SCHWARZKOPF, PATTON and AGAMEMNON);
* **emblem**: the Earth Alliance emblem (``core/hull_decals.py``) low on each vertical plate, under the pod and aft;
* **floods**: a lamp on a short bracket under each, shining up the plate, their pools baked into the plate's maps;
* **beacons**: red lamps at the top mast's tip, the keel mast's tip and the sensor boom's tip (the stills' red points);
* **edge band**: a darker grey band round the edges of the big plates (``parts/capital_paint.py``);
* **red fittings**: rows of small red-lit fittings along the shelf edges either side of the spine's gun-deck bays;
* **running lights**: small red lamps along the tips of the spine's fins, glowing paint only (no light of their own);
* **bow lamp**: a soft red lamp on the bow's face beside the bay.

The letter on the lower plate stays in ``parts/ea_nova.py``. Frame and numbers as ``parts/ea_nova.py``'s.
"""

from __future__ import annotations

import numpy as np

from ..core import collision as col
from ..core import hull_decals
from ..core.color import srgb_to_linear
from ..core.geometry import Material, Mesh, box
from ..core.textures import Marking
from ..styles import Style
from . import capital as cp
from . import capital_fittings as fittings
from . import capital_solids as cs
from .capital_paint import EdgeBand, edge_band
from .ea_hyperion import Flood
from .ea_nova import PLATE_X
from .ea_omega import PANEL

RIGHT = (1.0, 0.0, 0.0)
NAME_INK = (0.04, 0.04, 0.04)  # the stills' black print
NAME_BOARD = ((0.8, 0.81, 0.8), (0.03, 0.03, 0.03))  # the board's light grey and the black line round it
# Both end ahead of 330 m, where the spine's fins come through the plate (a 3 m ledge above and below the pod).
NAME_HEIGHT_M, NAME_AT = 10.0, (51.0, 284.0)  # its height; its centre's y and z (the board's top just under the plate's)
EMBLEM_WIDTH_M, EMBLEM_AT = 56.0, (-42.0, 298.0)  # its width; its centre's y and z (under the pod)
EMBLEM_HEIGHT_M = EMBLEM_WIDTH_M * hull_decals.DESIGN_H / hull_decals.DESIGN_W
FLOOD_LAMP = (1.0, 0.92, 0.82)  # the Hyperion's warm white
FLOOD_RGB = (244, 240, 232)
BEACON_RED = (1.0, 0.22, 0.05)  # the show's red-orange (the Omega's running red)
# The beacons (name, at, section): beside each tip, facing out, so they add nothing to the hull's size.
BEACONS = (("light_mast_top", (-8.8, 177.0, 238.3), "bridge"), ("light_mast_keel", (-8.0, -263.5, 249.7), "bow"),
           ("light_boom", (-21.5, -117.8, 1.5), "bow"))
# The plates that wear the edge band (their port twins too): the armour, the hangar block's roof and keel, the collars, the housing.
BANDED = ("armour_side", "armour_upper", "armour_lower", "hangar_roof", "hangar_keel", "collar_fore", "collar_aft", "housing_fore", "housing_aft")
BAND = EdgeBand(width_m=4.5, inset_m=0.5)
BAND_SHADE = 0.36  # the band's albedo against the hull's (linear)


RED_GLOW = (1.0, 0.12, 0.04)
# The red fittings on the shelves' edges (the stills' rows beside the gun decks): each row's z from and to, and the shelf edge's x.
RED_ROWS = ((430.0, 520.0, 62.0), (780.0, 850.0, 50.0), (940.0, 1000.0, 50.0))
RED_PITCH_M, RED_SIZE = 5.0, (0.8, 2.0, 2.2)  # their spacing; their depth off the edge, height and length
SHELF_Y = (15.0, 18.0)  # the shelf's edge, as ``parts/ea_nova.spine``'s
# The running lights along the fins' tips (``parts/ea_nova.spine``'s fin: its tip at x 61, y 43): each stretch's z from and to,
# and its section.
FIN_TIP = (61.0, 43.0)
RUNNING_STRETCHES = ((336.0, 520.0, "spine_fore"), (780.0, 900.0, "spine_mid"), (906.0, 1098.0, "spine_aft"))
RUNNING_PITCH_M, RUNNING_SIZE_M = 18.0, 1.0
# Where the girder's rings and collars stand over the fins and shelves: no fittings or lights there.
COVERED = ((448.8, 481.2), (523.2, 776.2), (819.2, 851.8), (928.2, 960.2))
BOW_LAMP_AT = (30.0, 34.0, 218.0)  # on the face of the starboard lower deck, beside and above the bay (the stills' lamp)


def _clear(z: float, half: float) -> bool:
    return not any(a - half <= z <= b + half for a, b in COVERED)


def _glow_row(name: str, centres: list[tuple[float, float, float]], size: tuple[float, float, float], strength: float) -> cp.Module:
    """Small red-lit boxes at ``centres`` (along one row) as one glowing part, a thin box round the row its collision."""
    glow = Material(f"glow_{name}", tuple(0.4 * c for c in RED_GLOW), emissive=RED_GLOW, emissive_strength=strength)
    mesh = Mesh.concatenate(box(size, glow, c) for c in centres)
    return cp.module(name, mesh, [col.box_around(name, mesh.vertices)], skin=cp.SKIN_NONE)


def red_fittings() -> list[cp.Module]:
    """The rows of red fittings on the starboard shelves' edges above and below the axis, one part a stretch of spine."""
    out: list[cp.Module] = []
    depth, height, length = RED_SIZE
    for k, (z0, z1, x) in enumerate(RED_ROWS):
        zs = [z for z in np.arange(z0, z1 + 1e-6, RED_PITCH_M) if _clear(float(z), 0.5 * length)]
        section = ("spine_fore", "spine_mid", "spine_aft")[k]
        for tag, sign in (("top", 1.0), ("low", -1.0)):
            centres = [(x + 0.5 * depth, sign * 0.5 * sum(SHELF_Y), float(z)) for z in zs]
            out.append(_glow_row(f"red_fittings_{k + 1}_{tag}_r", centres, (depth, height, length), 1.2).in_section(section).on_side(cp.RIGHT))
    return out


def running_lights() -> list[cp.Module]:
    """The red running lights along the starboard fins' tips above and below the axis, one part a stretch of spine."""
    out: list[cp.Module] = []
    x, y = FIN_TIP
    for k, (z0, z1, section) in enumerate(RUNNING_STRETCHES):
        zs = [z for z in np.arange(z0, z1 + 1e-6, RUNNING_PITCH_M) if _clear(float(z), RUNNING_SIZE_M)]
        for tag, sign in (("top", 1.0), ("low", -1.0)):
            centres = [(x, sign * y, float(z)) for z in zs]
            out.append(_glow_row(f"running_lights_{k + 1}_{tag}_r", centres, (RUNNING_SIZE_M,) * 3, 4.0).in_section(section).on_side(cp.RIGHT))
    return out


def bow_lamp() -> cp.Module:
    """The soft red lamp on the bow's face, a little light of its own round it."""
    return fittings.lamp("light_bow", "beacon", BEACON_RED, 40.0, 1.6).mounted(BOW_LAMP_AT, (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)).in_section("bridge").on_side(cp.LONE)


def _flood(name: str, target_y: float, z: float, below: float, outer: float, inner: float, range_m: float) -> Flood:
    """A lamp ``below`` m under ``target_y`` on a short bracket off the vertical plate, shining up the plate."""
    y = target_y - below
    return Flood(name, (PLATE_X + 3.0, y, z), (PLATE_X, target_y, z), outer, inner, range_m, FLOOD_RGB, 0.9, parts=("armour_side",),
                 bracket=((PLATE_X - 0.5, y - 1.4, z - 1.4), (PLATE_X + 2.4, y - 0.6, z + 1.4)), section="bow")


FLOODS = (_flood("flood_name", NAME_AT[0] + 5.0, NAME_AT[1], 16.0, 60.0, 22.0, 45.0),
          _flood("flood_emblem", EMBLEM_AT[0] + 6.0, EMBLEM_AT[1], 20.0, 55.0, 20.0, 45.0))


def _linear(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    return tuple(float(c) for c in srgb_to_linear(np.asarray(rgb, dtype=float) / 255.0))  # type: ignore[return-value]


def name_mark() -> cp.Hardpoint:
    """The ship's name on the starboard vertical plate, reading toward the bow (its port twin, toward the stern)."""
    y, z = NAME_AT
    return fittings.hull_mark("mark_name_r", (PLATE_X + 0.05, y, z), RIGHT, (0.0, 1.0, 0.0), NAME_HEIGHT_M, colour=NAME_INK, text="name",
                              placard=NAME_BOARD)


def emblem_mark() -> cp.Hardpoint:
    """The emblem on the starboard vertical plate, lit by the flood under it (its light given in the emblem's own frame: right,
    up, out; the lamp stands square under it, so the port twin's is the same)."""
    y, z = EMBLEM_AT
    at = np.array([PLATE_X + 0.05, y, z])
    flood = FLOODS[1]
    frame = np.stack([np.cross((0.0, 1.0, 0.0), RIGHT), (0.0, 1.0, 0.0), RIGHT])
    glow = {"lamp": [round(float(v), 4) for v in frame @ (np.asarray(flood.lamp) - at)],
            "direction": [round(float(v), 5) for v in frame @ flood.direction()], "outer_deg": flood.outer_deg, "inner_deg": flood.inner_deg,
            "range_m": flood.range_m, "colour": [round(c, 5) for c in _linear(flood.colour)], "strength": flood.strength}
    return fittings.hull_image("mark_emblem_r", tuple(at), RIGHT, (0.0, 1.0, 0.0), hull_decals.EMBLEM, EMBLEM_WIDTH_M, EMBLEM_HEIGHT_M, glow)


def lamps() -> list[cp.Module]:
    """The floods' lamps and brackets (starboard; their port twins follow) and the red beacons at the tips."""
    lamp = fittings.lamp
    out = [lamp(f"{f.name}_r", "flood", FLOOD_LAMP, f.range_m, 1.6, 6.0).mounted(f.lamp, tuple(f.direction())).in_section(f.section).on_side(cp.RIGHT)
           for f in FLOODS]
    out += [lamp(name, "beacon", BEACON_RED, 150.0, 1.0).mounted(at, RIGHT).in_section(section).on_side(cp.LONE) for name, at, section in BEACONS]
    return out


def brackets(s: Style) -> list[cp.Module]:
    """The brackets the floods' lamps stand on."""
    return [cs.box(f"{f.name}_bracket_r", *f.bracket, s, PANEL, skin=cp.SKIN_FITTING).in_section(f.section).on_side(cp.RIGHT) for f in FLOODS
            if f.bracket is not None]


def flood_pools() -> list[tuple[str, Marking]]:
    """Each flood's pool of light baked into its vertical plate, both sides."""
    return [(f"{part}_{tag}", Marking.flood("", (sx * f.lamp[0], f.lamp[1], f.lamp[2]), tuple(f.direction(sx)), f.outer_deg, f.inner_deg, f.range_m,
                                            _linear(f.colour), f.strength))
            for f in FLOODS for part in f.parts for tag, sx in (("r", 1.0), ("l", -1.0))]


def edge_bands(modules: list[cp.Module], hull_albedo: tuple[float, float, float], banded: tuple[str, ...] = BANDED,
               band: EdgeBand = BAND, shade: float = BAND_SHADE) -> list[tuple[str, Marking]]:
    """The edge band on each of ``banded``'s modules (by name less its side), in ``shade`` of the hull's albedo."""
    colour = tuple(shade * float(c) for c in hull_albedo)
    out: list[tuple[str, Marking]] = []
    for m in cp.with_twins(modules):
        base = m.name.removesuffix("_r").removesuffix("_l")
        mark = edge_band(m.name, m.part.mesh, colour, band) if base in banded else None  # type: ignore[arg-type]
        if mark is not None:
            out.append((m.name, mark))
    return out


__all__ = ["BANDED", "BEACONS", "BOW_LAMP_AT", "EMBLEM_AT", "EMBLEM_WIDTH_M", "FLOODS", "NAME_AT", "RED_ROWS", "RUNNING_STRETCHES", "bow_lamp",
           "brackets", "edge_bands", "emblem_mark", "flood_pools", "lamps", "name_mark", "red_fittings", "running_lights"]
