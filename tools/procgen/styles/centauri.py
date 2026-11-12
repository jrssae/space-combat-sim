"""Centauri design language (docs/design-references.md, "Centauri Brezebel transport"; docs/assets-civilian.md,
"centauri"): deep violet plating, gold caps on the tip fins and gold turret collars, a
pale lavender band round the bow's rim, white windows, dark violet-grey nozzles.

Albedos are linear RGB from the written sRGB scheme, painted as written (Q19). No panel grid is painted (the maintainer,
2026-11-04): panel layout comes with the texture pack at the rebase. Roles the design does not name (canopy, barrels,
interior) are our choice.

The texture pack (M5-T27; docs/design-references.md, "Centauri Brezebel transport", texture): the liner's polished
violet paint in Centauri Liner.jpg. Fine seams barely darker than the paint, an even tint, glossy paint,
little wear or grime. The five windows glow white and the engine throat the pink-white of the fin-tip lights.
"""

from __future__ import annotations

import numpy as np

from ..core.color import capture_albedo, srgb_to_linear
from ..core.geometry import Material
from . import Style

GLOW_SRGB = 0xFFB8E0  # engine and fin-tip glow, pink-white: the throats' glow and a ShipSpec tint for T16


def _lin(hex_rgb: int) -> tuple[float, float, float]:
    """Linear RGB of an sRGB ``0xRRGGBB`` value."""
    srgb = np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255], dtype=float) / 255.0
    r, g, b = (float(v) for v in srgb_to_linear(srgb))
    return (r, g, b)


HULL_SRGB, HULL_DARK_SRGB = 0x4C3C8E, 0x2B2257

CENTAURI = Style(
    name="centauri",
    materials={
        "hull": Material("cn_hull", capture_albedo(HULL_SRGB), paneled=True),  # everything but the trim
        "hull_dark": Material("cn_hull_dark", capture_albedo(HULL_DARK_SRGB)),  # the engine bay's walls and machinery
        "hull_panel": Material("cn_hull_panel", capture_albedo(HULL_SRGB), paneled=True),
        "stripe": Material("cn_stripe", capture_albedo(0xD9B23A), metallic=0.6),  # gold: fin caps, turret collars
        "trim_light": Material("cn_trim_light", capture_albedo(0xD7D2E6)),  # the band round the bow's rim
        "window": Material("cn_window", capture_albedo(0xF3F1FF), emissive=_lin(0xF3F1FF), emissive_strength=2.0),  # the five windows
        "hazard": Material("cn_hazard", capture_albedo(0xD9B23A)),
        "hazard_dark": Material("cn_hazard_dark", capture_albedo(HULL_DARK_SRGB)),
        "canopy_glass": Material("cn_canopy", capture_albedo(0x1A1530)),  # opaque: there is no cockpit inside
        "canopy_frame": Material("cn_canopy_frame", capture_albedo(HULL_DARK_SRGB), metallic=0.5),
        "nozzle": Material("cn_nozzle", capture_albedo(0x3A3448), metallic=0.8),
        "nozzle_throat": Material("cn_nozzle_throat", capture_albedo(0x141218), metallic=0.8, emissive=_lin(GLOW_SRGB), emissive_strength=3.0),
        "barrel": Material("cn_barrel", capture_albedo(0x3A3448), metallic=0.7),
        "bore": Material("cn_bore", capture_albedo(0x141218)),
        "interior": Material("cn_interior", capture_albedo(0x141218)),
        "rcs": Material("cn_rcs", capture_albedo(0x3A3448), metallic=0.6),
    },
    panel_size_m=2.4,
    panel_line_width_m=0.25,
    panel_line_darkness=0.82,
    panel_tint_jitter=0.03,
    hatch_fraction=0.1,
    edge_wear=0.15,
    streaks=0.04,
    grime=0.03,
    extra={"bare_metal": 0.0, "smudge": 0.04, "speckle": 0.02, "paint_roughness": 0.42, "rivets": 0.0},
)
