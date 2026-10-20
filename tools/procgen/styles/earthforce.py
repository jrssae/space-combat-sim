"""Earthforce design language: light grey panelled hull, mid-grey inset panels and ribbing, dark
gunmetal detail, yellow/black hazard stripes on structural members, green-tinted cockpit glass in a
grey frame, a muted orange-red marker stripe (buoys), dark nozzles.

Albedos are linear RGB (the sRGB look is roughly: hull #CACACE, panels #8C8E92, dark #5A5C60,
hazard #D8B21E / #2A2A2C, marker stripe #C0522E, glass #0E2A18, frame #7A7C80).
"""

from __future__ import annotations

from ..core.geometry import Material
from . import Style

EARTHFORCE = Style(
    name="earthforce",
    materials={
        "hull": Material("ef_hull", (0.60, 0.60, 0.63), paneled=True),
        "hull_dark": Material("ef_hull_dark", (0.10, 0.105, 0.115), paneled=True),
        "hull_panel": Material("ef_hull_panel", (0.26, 0.27, 0.285), paneled=True),
        "stripe": Material("ef_stripe", (0.52, 0.085, 0.03), paneled=True),
        "hazard": Material("ef_hazard", (0.69, 0.45, 0.012), paneled=True),
        "hazard_dark": Material("ef_hazard_dark", (0.023, 0.023, 0.025)),
        "canopy_glass": Material(
            "ef_canopy_glass", (0.012, 0.06, 0.027), transmittance=0.7
        ),
        "canopy_frame": Material("ef_canopy_frame", (0.19, 0.195, 0.21), metallic=0.5),
        "nozzle": Material("ef_nozzle", (0.14, 0.13, 0.125), metallic=0.8),
        "nozzle_throat": Material("ef_nozzle_throat", (0.03, 0.03, 0.03), metallic=0.8),
        "barrel": Material("ef_barrel", (0.17, 0.17, 0.18), metallic=0.7),
        "bore": Material("ef_bore", (0.02, 0.02, 0.02)),
        "interior": Material("ef_interior", (0.035, 0.035, 0.04)),
        "rcs": Material("ef_rcs", (0.12, 0.12, 0.125), metallic=0.6),
    },
    panel_size_m=0.6,
    panel_line_width_m=0.04,
    panel_line_darkness=0.55,
    panel_tint_jitter=0.05,
    stripe_fraction=0.68,
    stripe_width_m=0.3,
)
