"""The Omega's paint and lamps (M10-T68), placed as the show's stills (``references/show/m10/ea_omega/``) and the Agamemnon model's
layout (Chris Kuhn's, a style reference only: nothing copied or sampled) place them:

* **name**: the ship's own name in black block print on a light grey board ringed in black, high on each shield's vertical panel,
  toward its aft end (the stills' AGAMEMNON, ZEUS and TALOS);
* **emblem**: the Earth Alliance emblem (``core/hull_decals.py``) on each vertical panel under the name, aft of the beam pod;
* **floods**: a lamp on a short bracket under each, shining up the panel, their pools baked into the panel's maps;
* **beacons**: red lamps beside the dorsal mast's tip, the keel mast's tip and the probe's tip;
* **edge band**: a darker grey band round the edges of the big plates (``parts/capital_paint.py``);
* **red fittings**: rows of small red-lit fittings along the spines' flanges;
* **warning stickers**: black and yellow stripes on the spine blocks beside the collars and the housing.

The letter on the lower panel stays in ``parts/ea_omega.py``. Frame and numbers as ``parts/ea_omega.py``'s.
"""

from __future__ import annotations

import dataclasses

import numpy as np

from ..core import collision as col

from ..core import hull_decals
from ..core.textures import Marking
from ..styles import Style
from . import capital as cp
from . import capital_fittings as fittings
from . import capital_solids as cs
from .ea_hyperion import Flood
from .ea_nova_marks import BAND, BAND_SHADE, BEACON_RED, FLOOD_LAMP, FLOOD_RGB, NAME_BOARD, NAME_INK, _glow_row, _linear, edge_bands
from .ea_omega import PANEL, SPINE_EAR, SPINE_FLANGE

RIGHT = (1.0, 0.0, 0.0)
PLATE_X = 68.0  # the shield's vertical panel's outer face
NAME_HEIGHT_M, NAME_AT = 10.0, (47.0, 300.0)  # its height; its centre's y and z (the board just under the panel's top edge)
EMBLEM_WIDTH_M, EMBLEM_AT = 48.0, (-26.0, 312.0)  # its width; its centre's y and z (under the name, aft of the beam pod)
EMBLEM_HEIGHT_M = EMBLEM_WIDTH_M * hull_decals.DESIGN_H / hull_decals.DESIGN_W
# The beacons (name, at, section): beside each tip, facing out, so they add nothing to the hull's size.
BEACONS = (("light_mast_top", (2.0, 168.5, 240.0), "bridge"), ("light_mast_keel", (1.5, -306.0, 229.0), "bow"),
           ("light_probe", (-17.5, -145.0, 1.5), "bow"))
# The plates that wear the edge band (their port twins too): the shields, the collars, the reactor cage's plates, the roof.
BANDED = ("shield_mid", "shield_upper", "shield_lower", "collar_fore", "collar_aft", "skirt_top", "skirt_low", "skirt_corner_top",
          "skirt_corner_low", "skirt_side", "command_roof")
# The red fittings on the flanges' edges: each row's z from and to, and its section.
RED_ROWS = ((365.0, 470.0, "spine_fore"), (935.0, 1040.0, "magazine"), (1110.0, 1190.0, "spine_aft"))
RED_PITCH_M, RED_SIZE = 5.0, (0.8, 2.0, 2.2)  # their spacing; their depth off the edge, height and length
# The warning stickers (each a strip four times as long as it is high): the block's flank x, the sticker's centre z, its section.
STICKERS = (("sticker_fore", 55.0, 511.0, "spine_fore"), ("sticker_aft", 62.0, 1218.0, "spine_aft"))
STICKER_SIZE_M, STICKER_Y = (16.0, 4.0), 36.0


def red_fittings() -> list[cp.Module]:
    """The rows of red fittings on the starboard flanges' edges above and below the axis, one part a stretch of spine."""
    out: list[cp.Module] = []
    depth, height, length = RED_SIZE
    x, y = SPINE_FLANGE[1][0], 0.5 * (SPINE_FLANGE[0][1] + SPINE_FLANGE[1][1])
    for k, (z0, z1, section) in enumerate(RED_ROWS):
        zs = np.arange(z0, z1 + 1e-6, RED_PITCH_M)
        for tag, sign in (("top", 1.0), ("low", -1.0)):
            centres = [(x + 0.5 * depth, sign * y, float(z)) for z in zs]
            out.append(_glow_row(f"red_fittings_{k + 1}_{tag}_r", centres, (depth, height, length), 1.2).in_section(section).on_side(cp.RIGHT))
    return out


def _flood(name: str, target_y: float, z: float, below: float, outer: float, inner: float, range_m: float) -> Flood:
    """A lamp ``below`` m under ``target_y`` on a short bracket off the vertical panel, shining up the panel."""
    y = target_y - below
    return Flood(name, (PLATE_X + 3.0, y, z), (PLATE_X, target_y, z), outer, inner, range_m, FLOOD_RGB, 0.9, parts=("shield_mid",),
                 bracket=((PLATE_X - 0.5, y - 1.4, z - 1.4), (PLATE_X + 2.4, y - 0.6, z + 1.4)), section="bow")


FLOODS = (_flood("flood_name", NAME_AT[0] + 5.0, NAME_AT[1], 16.0, 60.0, 22.0, 45.0),
          _flood("flood_emblem", EMBLEM_AT[0] + 6.0, EMBLEM_AT[1], 20.0, 55.0, 20.0, 45.0))


def name_mark() -> cp.Hardpoint:
    """The ship's name on the starboard vertical panel, reading toward the bow (its port twin, toward the stern)."""
    y, z = NAME_AT
    return fittings.hull_mark("mark_name_r", (PLATE_X + 0.05, y, z), RIGHT, (0.0, 1.0, 0.0), NAME_HEIGHT_M, colour=NAME_INK, text="name",
                              placard=NAME_BOARD)


def emblem_mark() -> cp.Hardpoint:
    """The emblem on the starboard vertical panel, lit by the flood under it (its light in the emblem's own frame: right, up, out)."""
    y, z = EMBLEM_AT
    at = np.array([PLATE_X + 0.05, y, z])
    flood = FLOODS[1]
    frame = np.stack([np.cross((0.0, 1.0, 0.0), RIGHT), (0.0, 1.0, 0.0), RIGHT])
    glow = {"lamp": [round(float(v), 4) for v in frame @ (np.asarray(flood.lamp) - at)],
            "direction": [round(float(v), 5) for v in frame @ flood.direction()], "outer_deg": flood.outer_deg, "inner_deg": flood.inner_deg,
            "range_m": flood.range_m, "colour": [round(c, 5) for c in _linear(flood.colour)], "strength": flood.strength}
    return fittings.hull_image("mark_emblem_r", tuple(at), RIGHT, (0.0, 1.0, 0.0), hull_decals.EMBLEM, EMBLEM_WIDTH_M, EMBLEM_HEIGHT_M, glow)


def stickers(name: str, x: float, z: float) -> tuple[cp.Hardpoint, ...]:
    """A block's warning stickers: one on each flank above and below the axis (the block is one part on the axis, so both
    sides are its own)."""
    w, h = STICKER_SIZE_M
    return tuple(fittings.hull_image(f"mark_{name}_{tag}_{side}", (sx * (x + 0.05), sy * STICKER_Y, z), (sx, 0.0, 0.0), (0.0, 1.0, 0.0),
                                     hull_decals.HAZARD, w, h)
                 for side, sx in (("r", 1.0), ("l", -1.0)) for tag, sy in (("top", 1.0), ("low", -1.0)))


def lamps(s: Style) -> list[cp.Module]:
    """The floods' lamps each on its bracket, one part with one hull (starboard; their port twins follow), and the red beacons at
    the tips."""
    lamp = fittings.lamp
    out = []
    for f in FLOODS:
        light = lamp(f"{f.name}_r", "flood", FLOOD_LAMP, f.range_m, 1.6, 6.0).mounted(f.lamp, tuple(f.direction()))
        bracket = cs.box(f"{f.name}_bracket_r", *f.bracket, s, PANEL, skin=cp.SKIN_FITTING)
        both = cs.compound(f"{f.name}_r", [light, bracket])
        both = dataclasses.replace(both, shapes=(col.hull(both.name, both.part.mesh.vertices),))
        out.append(both.in_section(f.section).on_side(cp.RIGHT))
    out += [lamp(name, "beacon", BEACON_RED, 150.0, 1.0).mounted(at, RIGHT).in_section(section).on_side(cp.LONE) for name, at, section in BEACONS]
    return out


def flood_pools() -> list[tuple[str, Marking]]:
    """Each flood's pool of light baked into its vertical panel, both sides."""
    return [(f"{part}_{tag}", Marking.flood("", (sx * f.lamp[0], f.lamp[1], f.lamp[2]), tuple(f.direction(sx)), f.outer_deg, f.inner_deg, f.range_m,
                                            _linear(f.colour), f.strength))
            for f in FLOODS for part in f.parts for tag, sx in (("r", 1.0), ("l", -1.0))]


def bands(modules: list[cp.Module], hull_albedo: tuple[float, float, float]) -> list[tuple[str, Marking]]:
    """The edge band on the Omega's big plates."""
    return edge_bands(modules, hull_albedo, BANDED, BAND, BAND_SHADE)


__all__ = ["BANDED", "BEACONS", "EMBLEM_AT", "EMBLEM_WIDTH_M", "FLOODS", "NAME_AT", "RED_ROWS", "STICKERS", "bands", "emblem_mark", "flood_pools",
           "lamps", "name_mark", "red_fittings", "stickers"]
