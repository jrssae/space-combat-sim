"""Narn design language (docs/design-references.md, "Narn transport"; docs/assets-civilian.md, "narn"): dark green
plating with darker panel lines, a red band on each side of the crescent (no emblem), a light grey cargo box with a green
panel and yellow and black hazard marks, dark green glass, dark metal nozzles.

Albedos are linear RGB from the written sRGB scheme, except two lifted values. The reference green #2E4A3B is about a third
as bright as the raider's first paint (#77706A), which already read as a black silhouette on the RX 6950 XT, and
civilians are often seen on their dark side. So ``hull`` and ``hull_dark`` keep the hue and saturation of #2E4A3B and
#1E2E25 at about twice the value (#5F997A, #3E5F4C), and the box's ``cargo_panel`` (#4E7552) is lifted to #66996B so it
still reads green against the grey. ``REFERENCE_SRGB`` keeps the written values. T16's GPU check judges the result.
"""

from __future__ import annotations

import numpy as np

from ..core.color import srgb_to_linear
from ..core.geometry import Material
from . import Style

# The written scheme for the lifted roles (sRGB), so the lift stays traceable.
REFERENCE_SRGB: dict[str, int] = {"hull": 0x2E4A3B, "hull_dark": 0x1E2E25, "cargo_panel": 0x4E7552}


def _lin(hex_rgb: int) -> tuple[float, float, float]:
    """Linear RGB of an sRGB ``0xRRGGBB`` value."""
    srgb = np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255], dtype=float) / 255.0
    r, g, b = (float(v) for v in srgb_to_linear(srgb))
    return (r, g, b)


NARN = Style(
    name="narn",
    materials={
        "hull": Material("nr_hull", _lin(0x5F997A), paneled=True),  # crescent, cockpit, fins, towers
        "hull_dark": Material("nr_hull_dark", _lin(0x3E5F4C), paneled=True),  # recesses, vent slats
        "hull_panel": Material("nr_hull_panel", _lin(0xB7BAB5), paneled=True),  # the cargo box
        "cargo_panel": Material("nr_cargo_panel", _lin(0x66996B), paneled=True),  # the green panel on each side of the box
        "stripe": Material("nr_stripe", _lin(0xA3241C), paneled=True),  # the red band on each side of the crescent
        "hazard": Material("nr_hazard", _lin(0xD2B032)),
        "hazard_dark": Material("nr_hazard_dark", _lin(0x262626)),
        "canopy_glass": Material("nr_canopy", _lin(0x10201A)),  # opaque: there is no cockpit inside
        "canopy_frame": Material("nr_canopy_frame", _lin(0x3E5F4C), metallic=0.5),
        "nozzle": Material("nr_nozzle", _lin(0x3A3A36), metallic=0.8),
        "nozzle_throat": Material("nr_nozzle_throat", _lin(0x141413), metallic=0.8),
        "barrel": Material("nr_barrel", _lin(0x4A4A44), metallic=0.7),
        "bore": Material("nr_bore", (0.01, 0.01, 0.01)),
        "interior": Material("nr_interior", (0.02, 0.022, 0.02)),
        "rcs": Material("nr_rcs", _lin(0x4A4A44), metallic=0.6),
    },
    panel_size_m=2.4,
    panel_line_width_m=0.25,
    panel_line_darkness=0.6,
    panel_tint_jitter=0.08,
)
