"""Raider design language (docs/design-references.md, "Raider fighter Delta-V"): worn grey-brown plating
with darker recessed panels, vent grilles and nozzle metal, faded ochre accent bands, a near-black opaque
canopy. No insignia, no logos. On the textured mesh (M4-T30d) the plating is worn hard: chipped edges down to bare metal, dark streaks
aft of the seams, grime and smudges, and the main nozzles' throats glow yellow-white (the reference's two engine glows).

Albedos are linear RGB; the sRGB look is hull #A89F96, panels #544E48, ochre #B88A3A. The milestone's "about #77706A"
rendered nearly black on the real GPU in the first capture, far darker than the Starfury's light grey hull: a raider is
mostly seen from behind or below, on its dark side. The brighter hull keeps the worn grey-brown hue and reads against the
dark sky at fighting range. The panel
grid is a little finer and the per-panel tint jitter much stronger than on the Earthforce ships, so the plating reads
as patched and weathered rather than freshly painted.
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


# The textured mesh's paint (M4-T30d): lit by the renderer's PBR and ambient, the M3 hull's brighter paint reads near white, so the maps
# take a darker worn grey-brown (sRGB about #6B635A, panels #4A443E, dark #2C2724, ochre #8C6A32), in the Starfury's range.
TEXTURED_ALBEDO: dict[str, tuple[float, float, float]] = {
    "rd_hull": _lin(0x6B635A),
    "rd_hull_panel": _lin(0x4A443E),
    "rd_hull_dark": _lin(0x2C2724),
    "rd_stripe": _lin(0x8C6A32),
    "rd_hazard": _lin(0x8C6A32),
    "rd_canopy_frame": _lin(0x3A3633),
    "rd_nozzle": _lin(0x46413D),
    "rd_barrel": _lin(0x524D48),
    "rd_rcs": _lin(0x3E3A37),
}

RAIDER = Style(
    name="raider",
    materials={
        "hull": Material("rd_hull", _lin(0xA89F96), paneled=True),
        "hull_dark": Material("rd_hull_dark", _lin(0x37312D), paneled=True),
        "hull_panel": Material("rd_hull_panel", _lin(0x544E48), paneled=True),
        "stripe": Material("rd_stripe", _lin(0xB88A3A), paneled=True),
        "hazard": Material("rd_hazard", _lin(0xB88A3A), paneled=True),
        "hazard_dark": Material("rd_hazard_dark", _lin(0x1C1A18)),
        "canopy_glass": Material("rd_canopy", (0.006, 0.007, 0.009)),
        "canopy_frame": Material("rd_canopy_frame", _lin(0x4A4541), metallic=0.5),
        "nozzle": Material("rd_nozzle", _lin(0x5A5450), metallic=0.8),
        "nozzle_throat": Material(
            "rd_nozzle_throat", _lin(0x0E0D0C), metallic=0.8, roughness=0.45, emissive=(1.0, 0.86, 0.58), emissive_strength=4.0
        ),
        "barrel": Material("rd_barrel", _lin(0x6A645E), metallic=0.7),
        "bore": Material("rd_bore", (0.01, 0.01, 0.01)),
        "interior": Material("rd_interior", (0.02, 0.02, 0.022)),
        "rcs": Material("rd_rcs", _lin(0x504B47), metallic=0.6),
    },
    panel_size_m=0.5,
    panel_line_width_m=0.035,
    panel_line_darkness=0.5,
    panel_tint_jitter=0.12,
    stripe_fraction=0.68,
    stripe_width_m=0.3,
    # Worn hard (M4-T30d): bare metal at the chipped edges, streaks, grime and smudges; the paint is flat.
    edge_wear=0.6,
    streaks=0.3,
    grime=0.14,
    extra={"bare_metal": 0.8, "smudge": 0.3, "smudge_scale_m": 0.6, "speckle": 0.08, "paint_roughness": 0.82, "streak_length_m": 0.4},
)
