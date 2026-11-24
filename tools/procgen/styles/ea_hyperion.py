"""The Earth Alliance Hyperion-class heavy cruiser's style (M10-T22): a different class from the Omega, so its own paint and
plating on the fleet's machinery (``ea_capital.capital_style``: the same roles, lit red bays, blue-white engines).

The show (``references/show/m10/ea_hyperion/``, gitignored) paints it light grey with broad royal-blue bands round the forward
hull and the command tower. The ``stripe`` role is the band.

Look A is the maintainer's (2026-11-21): the show's light grey and royal blue, plated in the fleet's plate sizes
(:func:`hyperion_mosaic`) rather than the show's long planks, its subtle seams and patches the default finish since Q69; its colours re-read from the stills in
``references/ships/Hyperion/`` (Q58): a neutral light grey and a saturated royal blue, since the game's warm key light turns
a warm grey beige and a violet-leaning blue dull. B and C stay from the option sheet, each with its own plating (:data:`PLATING`). ``livery`` repaints roles as ``ea_capital``'s does.
"""

from __future__ import annotations

import dataclasses
from collections.abc import Mapping
from dataclasses import dataclass

from ..core.geometry import Material
from ..core.seams import PatchPlates
from .capital import CapitalStyle, PanelMosaic, pinned
from .ea_capital import FLEET_LINE_DARKNESS, Look, bay_metal_materials, capital_style

PREFIX = "eah"
SMOOTH_ROLES = ("barrel", "bore")


@dataclass(frozen=True)
class Plating:
    """A look's panel treatment: the plates' size (along the hull, across), how often they split, the frames' pitch."""

    plate_m: tuple[float, float]
    splits: int
    frames_m: float


LOOKS: dict[str, Look] = {
    "a": Look("a", "A: show livery, light grey with dark patches, bright royal-blue bands, shallow seams",
              {"hull": 0xD0D3D6, "hull_panel": 0xC0C4C8, "hull_dark": 0x60646C, "stripe": 0x3464EA},
              plate_tone=0.04, plate_grime=0.05, metallic=0.3, edge_wear=0.25, streaks=0.1, grime=0.05),
    "b": Look("b", "B: fleet white, navy bands, square plates",
              {"hull": 0xD0D2D4, "hull_panel": 0xBDC0C4, "hull_dark": 0x585C64, "stripe": 0x1A2C66},
              plate_tone=0.1, plate_grime=0.08, metallic=0.25, edge_wear=0.3, streaks=0.15, grime=0.08),
    "c": Look("c", "C: warm grey, cobalt bands, broad smooth panels",
              {"hull": 0x9C9A92, "hull_panel": 0x8C8A82, "hull_dark": 0x3E3D3A, "stripe": 0x2E6CD6},
              plate_tone=0.05, plate_grime=0.1, metallic=0.4, edge_wear=0.35, streaks=0.2, grime=0.1),
}
PLATING: dict[str, Plating] = {  # the looks not on the fleet's mosaic
    "b": Plating((10.0, 10.0), 2, 20.0),
    "c": Plating((40.0, 16.0), 1, 60.0),
}
DEFAULT_LOOK = "a"


def hyperion_mosaic(chosen: Look) -> PanelMosaic:
    """The fleet's plate sizes in the Hyperion's softer, patched finish (the default skin since Q69)."""
    return PanelMosaic(plate_m=(18.0, 9.0), splits=2, tone=chosen.plate_tone, grime=chosen.plate_grime, frames_m=30.0, major_every=4)


def ea_hyperion(look: str = DEFAULT_LOOK, livery: Mapping[str, int] | None = None) -> CapitalStyle:
    """The Hyperion's style in one of the looks, any role repainted by ``livery``."""
    if look not in LOOKS:
        raise ValueError(f"ea_hyperion has no look {look!r}; it has {sorted(LOOKS)}")
    chosen, plating = LOOKS[look], PLATING.get(look)
    skin = hyperion_mosaic(chosen) if plating is None else PanelMosaic(plate_m=plating.plate_m, splits=plating.splits, tone=chosen.plate_tone,
                                                                    grime=chosen.plate_grime, frames_m=plating.frames_m, major_every=4)
    style = capital_style(chosen, f"ea_hyperion_{look}", PREFIX, skin, livery)
    materials = {**smooth_barrels(style.style.materials), **bay_metal_materials(style.style.materials["hull"].name.removesuffix("_hull"))}
    style = dataclasses.replace(style, style=dataclasses.replace(style.style, materials=materials))
    # Looks B and C keep the option sheet's fleet seams, pinned until T74; look A wears the default (Q69: the Hyperion's).
    return pinned(style, FLEET_LINE_DARKNESS) if plating is not None else style


def smooth_barrels(materials: Mapping[str, Material]) -> dict[str, Material]:
    """The maintainer's call (M10-T22): the guns' barrels and bores are plain smooth metal, no weathering on them."""
    return {role: dataclasses.replace(m, smooth=True) if role in SMOOTH_ROLES else m for role, m in materials.items()}


__all__ = ["DEFAULT_LOOK", "LOOKS", "PLATING", "PatchPlates", "Plating", "SMOOTH_ROLES", "ea_hyperion", "hyperion_mosaic", "smooth_barrels"]
