"""Earthforce design language: medium blue-grey panelled hull, weathered (Q37), darker inset panels and ribbing, dark
gunmetal detail, yellow/black hazard stripes on structural members, dark neutral cockpit glass in a grey frame, a muted orange-red
marker stripe (buoys), dark nozzles. The nozzle throats glow hot; the cabin is grey, lit by a dark red glow that shows through the
glass (Q36, M4-T30b), and the wing's livery is painted over the hull by the shader (``core/livery.py``).

Albedos are linear RGB (the sRGB look is roughly: hull #5A616F (Q41: a medium weathered blue-grey), panels #464C5A, dark #5A5C60,
hazard #D8B21E / #2A2A2C, marker stripe #C0522E, glass #191A1C, frame #7A7C80, cabin grey #4A4A4C).
"""

from __future__ import annotations

from ..core.geometry import Material
from . import Style

EARTHFORCE = Style(
    name="earthforce",
    materials={
        "hull": Material("ef_hull", (0.1022, 0.1195, 0.159), paneled=True),
        "hull_dark": Material("ef_hull_dark", (0.10, 0.105, 0.115), paneled=True),
        "hull_panel": Material("ef_hull_panel", (0.0612, 0.0723, 0.1022), paneled=True),
        "stripe": Material("ef_stripe", (0.52, 0.085, 0.03), paneled=True),
        "hazard": Material("ef_hazard", (0.69, 0.45, 0.012), paneled=True),
        "hazard_dark": Material("ef_hazard_dark", (0.023, 0.023, 0.025)),
        "canopy_glass": Material(
            "ef_canopy_glass", (0.010, 0.0105, 0.011), transmittance=0.7, roughness=0.08,
            emissive=(0.40, 0.03, 0.02), emissive_strength=0.05
        ),
        "canopy_frame": Material("ef_canopy_frame", (0.19, 0.195, 0.21), metallic=0.5),
        "nozzle": Material("ef_nozzle", (0.14, 0.13, 0.125), metallic=0.8),
        "nozzle_throat": Material(
            "ef_nozzle_throat", (0.03, 0.03, 0.03), metallic=0.8, roughness=0.45, emissive=(1.0, 0.42, 0.12), emissive_strength=4.0
        ),
        "barrel": Material("ef_barrel", (0.17, 0.17, 0.18), metallic=0.7),
        "bore": Material("ef_bore", (0.02, 0.02, 0.02)),
        "interior": Material("ef_interior", (0.068, 0.068, 0.072), emissive=(0.55, 0.05, 0.035), emissive_strength=0.04),
        "rcs": Material("ef_rcs", (0.12, 0.12, 0.125), metallic=0.6),
        # The cockpit interior, from inside only (M3-T29): grey surfaces; the dark red glow that lights them is `MeshMaterials.cockpit`'s
        # and the cabin lamp's (Q36). The struts' inner faces are the lightest grey, so they catch the most red.
        "cockpit_red": Material("ef_cockpit_red", (0.20, 0.20, 0.205)),
        "cockpit_red_dim": Material("ef_cockpit_red_dim", (0.12, 0.12, 0.125)),
        "cockpit_dark": Material("ef_cockpit_dark", (0.03, 0.03, 0.032)),
        "cockpit_sill": Material("ef_cockpit_sill", (0.045, 0.045, 0.048)),
        "cockpit_metal": Material("ef_cockpit_metal", (0.07, 0.07, 0.075)),
        "cockpit_lamp": Material("ef_cockpit_lamp", (1.0, 1.0, 1.0)),
        "cockpit_rim": Material("ef_cockpit_rim", (1.0, 0.45, 0.42)),
        "cockpit_ind_assist": Material("ef_cockpit_ind_assist", (0.05, 0.05, 0.05)),
        "cockpit_ind_guns": Material("ef_cockpit_ind_guns", (0.05, 0.05, 0.05)),
        "cockpit_ind_lights": Material("ef_cockpit_ind_lights", (0.05, 0.05, 0.05)),
        "cockpit_ind_track": Material("ef_cockpit_ind_track", (0.05, 0.05, 0.05)),
    },
    panel_size_m=0.6,
    panel_line_width_m=0.03,
    panel_line_darkness=0.72,
    panel_tint_jitter=0.05,
    stripe_fraction=0.68,
    stripe_width_m=0.3,
    # Weathered field grey (Q37): dark streaks aft of the seams, smudges and grime, worn edges that show primer, not metal; matte.
    streaks=0.38,
    grime=0.1,
    edge_wear=0.5,
    extra={"bare_metal": 0.0, "smudge": 0.38, "smudge_scale_m": 0.45, "speckle": 0.07, "paint_roughness": 0.86,
           "streak_length_m": 0.32},
)
