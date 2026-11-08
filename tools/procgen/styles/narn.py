"""Narn design language (docs/design-references.md, "Narn transport"; docs/assets-civilian.md, "narn"): green
plating with darker recesses, a red band on each side of the crescent (no emblem), a light grey cargo box with a green
panel and yellow and black hazard marks, dark green glass, dark metal nozzles.

Albedos are linear RGB from the written sRGB scheme (Q19); the green was lifted when the maintainer judged it too dark
(2026-11-04, docs/assets-civilian.md "Colour round").

The texture pack (M5-T27; docs/design-references.md, "Narn transport", texture): the hard-used green plating of
Tal'Quith.JPG and Na'Tan.JPG. Big plates with dark seams and a strong plate-to-plate tint, chipped edges with some bare
metal, grime and long streaks aft; the light grey cargo box takes the same wear. The engine throats glow orange-white.
"""

from __future__ import annotations

import numpy as np

from ..core.color import capture_albedo, srgb_to_linear
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
        "hull": Material("nr_hull", capture_albedo(0x3A5A48), paneled=True),  # crescent, cockpit, fins, towers
        "hull_dark": Material("nr_hull_dark", capture_albedo(0x26392F), paneled=True),  # recesses, vanes, vent slats
        "hull_panel": Material("nr_hull_panel", capture_albedo(0xB7BAB5), paneled=True),  # the cargo box
        "cargo_panel": Material("nr_cargo_panel", capture_albedo(0x4E7552), paneled=True),  # the green panel on each side of the box
        "stripe": Material("nr_stripe", capture_albedo(0xA3241C), paneled=True),  # the red band on each side of the crescent
        "hazard": Material("nr_hazard", capture_albedo(0xD2B032)),
        "hazard_dark": Material("nr_hazard_dark", capture_albedo(0x262626)),
        "canopy_glass": Material("nr_canopy", capture_albedo(0x10201A)),  # opaque: there is no cockpit inside
        "canopy_frame": Material("nr_canopy_frame", capture_albedo(0x26392F), metallic=0.5),
        "nozzle": Material("nr_nozzle", capture_albedo(0x3A3A36), metallic=0.8),
        "nozzle_throat": Material("nr_nozzle_throat", capture_albedo(0x141413), metallic=0.8, emissive=_lin(0xFFB070), emissive_strength=3.0),
        "barrel": Material("nr_barrel", capture_albedo(0x4A4A44), metallic=0.7),
        "bore": Material("nr_bore", (0.01, 0.01, 0.01)),
        "interior": Material("nr_interior", (0.02, 0.022, 0.02)),
        "rcs": Material("nr_rcs", capture_albedo(0x4A4A44), metallic=0.6),
    },
    panel_size_m=2.4,
    panel_line_width_m=0.25,
    panel_line_darkness=0.62,
    panel_tint_jitter=0.09,
    hatch_fraction=0.16,
    edge_wear=0.5,
    streaks=0.22,
    grime=0.11,
    extra={"bare_metal": 0.25, "smudge": 0.22, "speckle": 0.05, "paint_roughness": 0.8, "streak_length_m": 0.35, "rivets": 0.6, "panel_grid": 0.0},
)
