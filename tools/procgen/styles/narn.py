"""Narn design language (docs/design-references.md, "Narn transport"; docs/assets-civilian.md, "narn"): green
plating with darker recesses, a red band on each side of the crescent (no emblem), a light grey cargo box with a green
panel and yellow and black hazard marks, dark green glass, dark metal nozzles.

Albedos are linear RGB from the written sRGB scheme (Q19); the green was lifted when the maintainer judged it too dark
(2026-11-04, docs/assets-civilian.md "Colour round").
"""

from __future__ import annotations

import numpy as np

from ..core.color import srgb_to_linear
from ..core.geometry import Material
from . import Style


def _lin(hex_rgb: int) -> tuple[float, float, float]:
    """Linear RGB of an sRGB ``0xRRGGBB`` value."""
    srgb = np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255], dtype=float) / 255.0
    r, g, b = (float(v) for v in srgb_to_linear(srgb))
    return (r, g, b)


NARN = Style(
    name="narn",
    materials={
        "hull": Material("nr_hull", _lin(0x3A5A48), paneled=True),  # crescent, cockpit, fins, towers
        "hull_dark": Material("nr_hull_dark", _lin(0x26392F), paneled=True),  # recesses, vanes, vent slats
        "hull_panel": Material("nr_hull_panel", _lin(0xB7BAB5), paneled=True),  # the cargo box
        "cargo_panel": Material("nr_cargo_panel", _lin(0x4E7552), paneled=True),  # the green panel on each side of the box
        "stripe": Material("nr_stripe", _lin(0xA3241C), paneled=True),  # the red band on each side of the crescent
        "hazard": Material("nr_hazard", _lin(0xD2B032)),
        "hazard_dark": Material("nr_hazard_dark", _lin(0x262626)),
        "canopy_glass": Material("nr_canopy", _lin(0x10201A)),  # opaque: there is no cockpit inside
        "canopy_frame": Material("nr_canopy_frame", _lin(0x26392F), metallic=0.5),
        "nozzle": Material("nr_nozzle", _lin(0x3A3A36), metallic=0.8),
        "nozzle_throat": Material("nr_nozzle_throat", _lin(0x141413), metallic=0.8),
        "barrel": Material("nr_barrel", _lin(0x4A4A44), metallic=0.7),
        "bore": Material("nr_bore", (0.01, 0.01, 0.01)),
        "interior": Material("nr_interior", (0.02, 0.022, 0.02)),
        "rcs": Material("nr_rcs", _lin(0x4A4A44), metallic=0.6),
    },
    panel_size_m=2.4,
    panel_line_width_m=0.25,
    panel_line_darkness=1.0,  # no painted grid (the maintainer, 2026-11-04): panels come with the texture pack
    panel_tint_jitter=0.0,
)
