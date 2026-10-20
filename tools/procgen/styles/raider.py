"""Raider design language (docs/design-references.md, "Raider fighter Delta-V"): worn grey-brown plating
with darker recessed panels, vent grilles and nozzle metal, faded ochre accent bands, a near-black opaque
canopy. No insignia, no logos.

Albedos are linear RGB; the sRGB look is hull #77706A, panels #3A3632, ochre #8A6A2C. The panel grid is a
little finer and the per-panel tint jitter much stronger than on the Earthforce ships, so the plating reads as
patched and weathered rather than freshly painted.
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


RAIDER = Style(
    name="raider",
    materials={
        "hull": Material("rd_hull", _lin(0x77706A), paneled=True),
        "hull_dark": Material("rd_hull_dark", _lin(0x24211F), paneled=True),
        "hull_panel": Material("rd_hull_panel", _lin(0x3A3632), paneled=True),
        "stripe": Material("rd_stripe", _lin(0x8A6A2C), paneled=True),
        "hazard": Material("rd_hazard", _lin(0x8A6A2C), paneled=True),
        "hazard_dark": Material("rd_hazard_dark", _lin(0x1C1A18)),
        "canopy_glass": Material("rd_canopy", (0.006, 0.007, 0.009)),
        "canopy_frame": Material("rd_canopy_frame", _lin(0x2E2B29), metallic=0.5),
        "nozzle": Material("rd_nozzle", _lin(0x3A3633), metallic=0.8),
        "nozzle_throat": Material("rd_nozzle_throat", _lin(0x0E0D0C), metallic=0.8),
        "barrel": Material("rd_barrel", _lin(0x45413D), metallic=0.7),
        "bore": Material("rd_bore", (0.01, 0.01, 0.01)),
        "interior": Material("rd_interior", (0.02, 0.02, 0.022)),
        "rcs": Material("rd_rcs", _lin(0x35322F), metallic=0.6),
    },
    panel_size_m=0.5,
    panel_line_width_m=0.035,
    panel_line_darkness=0.5,
    panel_tint_jitter=0.12,
    stripe_fraction=0.68,
    stripe_width_m=0.3,
)
