"""The Earth Alliance Hyperion-class heavy cruiser's style (M10-T22): a different class from the Omega, so its own paint and
plating on the fleet's machinery (``ea_capital.capital_style``: the same roles, lit red bays, blue-white engines).

The show (``references/show/m10/ea_hyperion/``, gitignored) paints it light grey with broad royal-blue bands round the forward
hull and the command tower. The ``stripe`` role is the band.

Look A is the maintainer's (2026-11-21): the show's light grey and royal blue, plated in the fleet's standard mosaic
(``ea_capital.fleet_mosaic``) rather than the show's long planks. B and C stay from the option sheet, each with its own plating
(:data:`PLATING`). ``livery`` repaints roles as ``ea_capital``'s does.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

from .capital import CapitalStyle, PanelMosaic
from .ea_capital import Look, capital_style, fleet_mosaic

PREFIX = "eah"


@dataclass(frozen=True)
class Plating:
    """A look's panel treatment: the plates' size (along the hull, across), how often they split, the frames' pitch."""

    plate_m: tuple[float, float]
    splits: int
    frames_m: float


LOOKS: dict[str, Look] = {
    "a": Look("a", "A: show livery, light grey and royal-blue bands, the fleet's mosaic",
              {"hull": 0xB2B6BC, "hull_panel": 0xA2A7AF, "hull_dark": 0x4A4E56, "stripe": 0x2452B4},
              plate_tone=0.08, plate_grime=0.06, metallic=0.3, edge_wear=0.25, streaks=0.12, grime=0.06),
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


def ea_hyperion(look: str = DEFAULT_LOOK, livery: Mapping[str, int] | None = None) -> CapitalStyle:
    """The Hyperion's style in one of the looks, any role repainted by ``livery``."""
    if look not in LOOKS:
        raise ValueError(f"ea_hyperion has no look {look!r}; it has {sorted(LOOKS)}")
    chosen, plating = LOOKS[look], PLATING.get(look)
    skin = fleet_mosaic(chosen) if plating is None else PanelMosaic(plate_m=plating.plate_m, splits=plating.splits, tone=chosen.plate_tone,
                                                                    grime=chosen.plate_grime, frames_m=plating.frames_m, major_every=4)
    return capital_style(chosen, f"ea_hyperion_{look}", PREFIX, skin, livery)


__all__ = ["DEFAULT_LOOK", "LOOKS", "PLATING", "Plating", "ea_hyperion"]
