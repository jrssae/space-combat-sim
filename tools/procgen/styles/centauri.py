"""Centauri design language (docs/design-references.md, "Centauri Brezebel transport"; docs/assets-civilian.md,
"centauri"): deep violet plating with darker violet panel lines, gold caps on the tip fins and gold turret collars, a
pale lavender band round the bow's rim, white windows, dark violet-grey nozzles.

Albedos are linear RGB from the written sRGB scheme, painted as written (Q19). The panel lines are the written hull_dark
(#2B2257): ``panel_line_darkness`` is that colour's share of the hull violet. If the violet reads black in T16's GPU
check, a lift goes to the maintainer first. Roles the design does not name (canopy, barrels, interior) are our choice.
"""

from __future__ import annotations

import numpy as np

from ..core.color import srgb_to_linear
from ..core.geometry import Material
from . import Style

GLOW_SRGB = 0xFFB8E0  # engine and fin-tip glow, pink-white: a ShipSpec tint for T16, not paint


def _lin(hex_rgb: int) -> tuple[float, float, float]:
    """Linear RGB of an sRGB ``0xRRGGBB`` value."""
    srgb = np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255], dtype=float) / 255.0
    r, g, b = (float(v) for v in srgb_to_linear(srgb))
    return (r, g, b)


HULL_SRGB, HULL_DARK_SRGB = 0x4C3C8E, 0x2B2257
# The panel lines' albedo over the hull's, averaged over the channels: lines on the violet read as the written dark violet.
LINE_DARKNESS = float(np.mean(np.array(_lin(HULL_DARK_SRGB)) / np.array(_lin(HULL_SRGB))))

CENTAURI = Style(
    name="centauri",
    materials={
        "hull": Material("cn_hull", _lin(HULL_SRGB), paneled=True),  # everything but the trim
        "hull_dark": Material("cn_hull_dark", _lin(HULL_DARK_SRGB)),  # the engine bay's walls and machinery
        "hull_panel": Material("cn_hull_panel", _lin(HULL_SRGB), paneled=True),
        "stripe": Material("cn_stripe", _lin(0xD9B23A), metallic=0.6),  # gold: fin caps, turret collars
        "trim_light": Material("cn_trim_light", _lin(0xD7D2E6)),  # the band round the bow's rim
        "window": Material("cn_window", _lin(0xF3F1FF)),  # the five windows
        "hazard": Material("cn_hazard", _lin(0xD9B23A)),
        "hazard_dark": Material("cn_hazard_dark", _lin(HULL_DARK_SRGB)),
        "canopy_glass": Material("cn_canopy", _lin(0x1A1530)),  # opaque: there is no cockpit inside
        "canopy_frame": Material("cn_canopy_frame", _lin(HULL_DARK_SRGB), metallic=0.5),
        "nozzle": Material("cn_nozzle", _lin(0x3A3448), metallic=0.8),
        "nozzle_throat": Material("cn_nozzle_throat", _lin(0x141218), metallic=0.8),
        "barrel": Material("cn_barrel", _lin(0x3A3448), metallic=0.7),
        "bore": Material("cn_bore", _lin(0x141218)),
        "interior": Material("cn_interior", _lin(0x141218)),
        "rcs": Material("cn_rcs", _lin(0x3A3448), metallic=0.6),
    },
    panel_size_m=2.4,
    panel_line_width_m=0.25,
    panel_line_darkness=LINE_DARKNESS,
    panel_tint_jitter=0.04,
)
