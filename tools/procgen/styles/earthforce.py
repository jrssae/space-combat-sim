"""Earthforce design language: light grey panelled hull, mid-grey inset panels and ribbing, dark
gunmetal detail, yellow/black hazard stripes on structural members, green-tinted cockpit glass in a
grey frame, a muted orange-red marker stripe (buoys), dark nozzles. The nozzle throats glow hot and
the glass carries a faint cabin glow in the textured mesh's emissive map (M4-T30a).

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
            "ef_canopy_glass", (0.012, 0.06, 0.027), transmittance=0.7, roughness=0.08,
            emissive=(0.06, 0.45, 0.24), emissive_strength=0.12
        ),
        "canopy_frame": Material("ef_canopy_frame", (0.19, 0.195, 0.21), metallic=0.5),
        "nozzle": Material("ef_nozzle", (0.14, 0.13, 0.125), metallic=0.8),
        "nozzle_throat": Material(
            "ef_nozzle_throat", (0.03, 0.03, 0.03), metallic=0.8, roughness=0.45, emissive=(1.0, 0.42, 0.12), emissive_strength=4.0
        ),
        "barrel": Material("ef_barrel", (0.17, 0.17, 0.18), metallic=0.7),
        "bore": Material("ef_bore", (0.02, 0.02, 0.02)),
        "interior": Material("ef_interior", (0.035, 0.035, 0.04)),
        "rcs": Material("ef_rcs", (0.12, 0.12, 0.125), metallic=0.6),
        # The cockpit interior, from inside only (M3-T29): near black but for the struts' red faces. Glow is `MeshMaterials.cockpit`'s.
        "cockpit_red": Material("ef_cockpit_red", (0.62, 0.012, 0.008)),
        "cockpit_red_dim": Material("ef_cockpit_red_dim", (0.20, 0.006, 0.005)),
        "cockpit_dark": Material("ef_cockpit_dark", (0.009, 0.005, 0.005)),
        "cockpit_sill": Material("ef_cockpit_sill", (0.010, 0.005, 0.005)),
        "cockpit_metal": Material("ef_cockpit_metal", (0.016, 0.009, 0.009)),
        "cockpit_lamp": Material("ef_cockpit_lamp", (1.0, 1.0, 1.0)),
        "cockpit_rim": Material("ef_cockpit_rim", (1.0, 0.45, 0.42)),
        "cockpit_ind_assist": Material("ef_cockpit_ind_assist", (0.05, 0.05, 0.05)),
        "cockpit_ind_guns": Material("ef_cockpit_ind_guns", (0.05, 0.05, 0.05)),
        "cockpit_ind_lights": Material("ef_cockpit_ind_lights", (0.05, 0.05, 0.05)),
        "cockpit_ind_track": Material("ef_cockpit_ind_track", (0.05, 0.05, 0.05)),
    },
    panel_size_m=0.6,
    panel_line_width_m=0.04,
    panel_line_darkness=0.55,
    panel_tint_jitter=0.05,
    stripe_fraction=0.68,
    stripe_width_m=0.3,
)
