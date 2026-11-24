"""The Nova's paint and lamps (M10-T67), placed as the show's stills (``references/show/m10/ea_nova/``, and the Omega's, which
wears them alike) place them on the command block's armour:

* **name**: the ship's own name in block print high on each vertical plate, above the gun pod and toward its aft end (the
  stills' SCHWARZKOPF and PATTON), light and outlined in black like the Hyperion's;
* **emblem**: the Earth Alliance emblem (``core/hull_decals.py``) low on each vertical plate, under the pod and aft;
* **floods**: a lamp on a short bracket under each, shining up the plate, their pools baked into the plate's maps;
* **beacons**: red lamps at the top mast's tip, the keel mast's tip and the sensor boom's tip (the stills' red points);
* **edge band**: a darker grey band round the edges of the big plates (``parts/capital_paint.py``).

The letter on the lower plate stays in ``parts/ea_nova.py``. Frame and numbers as ``parts/ea_nova.py``'s.
"""

from __future__ import annotations

import numpy as np

from ..core import hull_decals
from ..core.color import srgb_to_linear
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
NAME_INK = (0.86, 0.87, 0.88)  # the Hyperion's light lettering
NAME_HEIGHT_M, NAME_AT = 10.0, (45.0, 300.0)  # its height; its centre's y and z (above the pod, toward the plate's aft end)
EMBLEM_WIDTH_M, EMBLEM_AT = 56.0, (-40.0, 322.0)  # its width; its centre's y and z (under the pod's tail)
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
BAND_SHADE = 0.45  # the band's albedo against the hull's (linear)


def _flood(name: str, target_y: float, z: float, below: float, outer: float, inner: float, range_m: float) -> Flood:
    """A lamp ``below`` m under ``target_y`` on a short bracket off the vertical plate, shining up the plate."""
    y = target_y - below
    return Flood(name, (PLATE_X + 3.0, y, z), (PLATE_X, target_y, z), outer, inner, range_m, FLOOD_RGB, 0.9, parts=("armour_side",),
                 bracket=((PLATE_X - 0.5, y - 1.4, z - 1.4), (PLATE_X + 2.4, y - 0.6, z + 1.4)), section="bow")


FLOODS = (_flood("flood_name", NAME_AT[0] + 5.0, NAME_AT[1], 16.0, 60.0, 22.0, 45.0),
          _flood("flood_emblem", EMBLEM_AT[0] + 6.0, EMBLEM_AT[1], 23.0, 55.0, 20.0, 45.0))


def _linear(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    return tuple(float(c) for c in srgb_to_linear(np.asarray(rgb, dtype=float) / 255.0))  # type: ignore[return-value]


def name_mark() -> cp.Hardpoint:
    """The ship's name on the starboard vertical plate, reading toward the bow (its port twin, toward the stern)."""
    y, z = NAME_AT
    return fittings.hull_mark("mark_name_r", (PLATE_X + 0.05, y, z), RIGHT, (0.0, 1.0, 0.0), NAME_HEIGHT_M, colour=NAME_INK, text="name", outline=True)


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


__all__ = ["BANDED", "BEACONS", "EMBLEM_AT", "EMBLEM_WIDTH_M", "FLOODS", "NAME_AT", "brackets", "edge_bands", "emblem_mark", "flood_pools", "lamps",
           "name_mark"]
