"""The Earth Alliance maintenance bot's design language (M7-T11, docs/assets-station.md "Maintenance bot"): two long blue-violet
shell halves with a pale ochre band round each, a grey truss body, dark joints, a green sensor lens and small thrusters.

Colours are the sRGB values read off the model sheet's lit render (docs/assets-station.md), taken to albedo by ``capture_albedo``.
The maintainer wants metal, not plastic (M7-T16's finish): the shells are painted metal whose roughness steps from plate to
plate, and the truss and joints are bare, smooth metal. The bot is a few metres across, so the panels, seams and wear are
centimetres.
"""

from __future__ import annotations

from ..core.color import capture_albedo
from ..core.geometry import Material
from . import Style

PREFIX = "mb"

# role: (sRGB, paneled, metallic, roughness)
SCHEME: dict[str, tuple[int, bool, float, float]] = {
    "hull": (0x6662B5, True, 0.5, 0.42),  # the shells
    "hull_dark": (0x33312F, False, 0.7, 0.4),  # the joints
    "hull_panel": (0x83807D, True, 0.8, 0.36),  # the truss, painted grey
    "stripe": (0xC0A866, True, 0.5, 0.45),  # the bands
    "hazard": (0xA29E9B, True, 0.8, 0.34),  # the pale truss plates
    "hazard_dark": (0x262523, False, 0.5, 0.5),
    "canopy_glass": (0x10161C, False, 0.0, 0.1),
    "canopy_frame": (0x4A4846, False, 0.8, 0.3),
    "nozzle": (0x55534F, False, 0.9, 0.28),
    "nozzle_throat": (0x1C1B1A, False, 0.8, 0.45),
    "barrel": (0x5A5955, False, 0.85, 0.26),
    "bore": (0x101010, False, 0.0, 0.7),
    "interior": (0x2E2C2A, False, 0.0, 0.7),
    "rcs": (0x6E6C68, False, 0.8, 0.32),
}
# The lit roles (emission colour, strength): the thrusters' throats glow a faint blue-white, as the Starfury's; the sensor lens
# is green, the lamps amber.
THROAT_GLOW = (0.55, 0.7, 1.0)
THROAT_STRENGTH = 1.5


def _materials() -> dict[str, Material]:
    out: dict[str, Material] = {}
    for role, (hex_rgb, paneled, metallic, rough) in SCHEME.items():
        glow = THROAT_GLOW if role == "nozzle_throat" else (0.0, 0.0, 0.0)
        strength = THROAT_STRENGTH if role == "nozzle_throat" else 0.0
        out[role] = Material(f"{PREFIX}_{role}", capture_albedo(hex_rgb), paneled=paneled, metallic=metallic, roughness=rough,
                             emissive=glow, emissive_strength=strength)
    return out


MAINTENANCE_BOT = Style(
    name="maintenance_bot",
    materials=_materials(),
    panel_size_m=0.4,
    panel_line_width_m=0.012,
    panel_line_darkness=0.6,
    panel_tint_jitter=0.05,
    groove_depth_m=0.006,
    hatch_depth_m=0.003,
    edge_wear=0.4,
    edge_wear_width_m=0.012,
    streaks=0.12,
    grime=0.06,
    grime_scale_m=0.6,
    extra={"bare_metal": 0.0, "smudge": 0.2, "smudge_scale_m": 0.3, "speckle": 0.04, "streak_length_m": 0.2,
           "metal_finish": {"panel_m": 0.45, "panel_rough": 0.08, "noise_m": 0.5, "noise_rough": 0.05, "dirt_rough": 0.25,
                            "dirt_metal": 0.5, "grime_dirt": 0.6, "chip_dirt": 1.0, "seam_dirt": 0.5, "dirt_on_paint_only": 1.0}},
)
