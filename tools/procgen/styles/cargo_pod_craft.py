"""The Earth Alliance cargo pod's design language (M7-T33, docs/design-references.md "Cargo pod"): a blue cab with a pale top
panel and a black window across its nose, gunmetal arms whose outer barrels carry yellow, orange and yellow bands and a black and
white chequer, dark clamps, small white thrusters.

Colours are read off the show's zero-g cargo bay capture (``references/zero g cargo bay references``), white-balanced against
the cab's pale panel (the bay's light is blue), and taken to albedo by ``capture_albedo``. The maintainer wants metal, not
plastic: the cab is painted metal whose roughness steps from plate to plate, the arms and clamps worn grey metal, half metallic so the key light, not the black sky, shows them. The craft is 6 m
long, so the panels, seams and wear are centimetres.
"""

from __future__ import annotations

from ..core.color import capture_albedo
from ..core.geometry import Material
from . import LEGACY_SEAMS, Style

PREFIX = "cpc"

# role: (sRGB, paneled, metallic, roughness)
SCHEME: dict[str, tuple[int, bool, float, float]] = {
    "hull": (0x1F4C9E, True, 0.55, 0.4),  # the cab's blue
    "hull_panel": (0xC4C8CC, True, 0.5, 0.42),  # the pale top panel
    "hull_dark": (0x7A8189, True, 0.55, 0.36),  # the arms' barrels, gunmetal
    "stripe": (0xD8BE38, True, 0.5, 0.45),  # the barrels' yellow bands
    "hazard": (0xD2601E, True, 0.5, 0.45),  # the orange band between them
    "hazard_dark": (0x1E1E1E, False, 0.5, 0.5),  # the chequer's black
    "hazard_light": (0xE4E4E2, False, 0.5, 0.45),  # the chequer's white
    "clamp": (0x6A717C, True, 0.6, 0.34),  # the wrists, forearms and jaws
    "canopy_glass": (0x0C1014, False, 0.0, 0.08),
    "canopy_frame": (0x2A2D33, False, 0.8, 0.3),
    "nozzle": (0x55534F, False, 0.9, 0.28),
    "nozzle_throat": (0x1C1B1A, False, 0.8, 0.45),
    "barrel": (0x5A5955, False, 0.85, 0.26),
    "bore": (0x101010, False, 0.0, 0.7),
    "interior": (0x2E2C2A, False, 0.0, 0.7),
    "rcs": (0xD8DADC, False, 0.6, 0.35),  # the white thruster cones the capture shows at the nose
}
# The throats glow the blue-white of the EA craft's engines.
THROAT_GLOW = (0.55, 0.7, 1.0)
THROAT_STRENGTH = 2.0


def _materials() -> dict[str, Material]:
    out: dict[str, Material] = {}
    for role, (hex_rgb, paneled, metallic, rough) in SCHEME.items():
        glow = THROAT_GLOW if role == "nozzle_throat" else (0.0, 0.0, 0.0)
        strength = THROAT_STRENGTH if role == "nozzle_throat" else 0.0
        out[role] = Material(f"{PREFIX}_{role}", capture_albedo(hex_rgb), paneled=paneled, metallic=metallic, roughness=rough,
                             emissive=glow, emissive_strength=strength)
    return out


CARGO_POD_CRAFT = Style(
    name="cargo_pod_craft",
    materials=_materials(),
    panel_size_m=0.5,
    panel_line_width_m=0.012,
    panel_line_darkness=0.6,
    panel_tint_jitter=0.05,
    groove_depth_m=0.006,
    hatch_depth_m=0.003,
    edge_wear=0.4,
    edge_wear_width_m=0.012,
    streaks=0.1,
    grime=0.06,
    grime_scale_m=0.6,
    extra={"bare_metal": 0.0, "smudge": 0.18, "smudge_scale_m": 0.3, "speckle": 0.04, "streak_length_m": 0.2,
           "metal_finish": {"panel_m": 0.45, "panel_rough": 0.08, "noise_m": 0.5, "noise_rough": 0.05, "dirt_rough": 0.25,
                            "dirt_metal": 0.5, "grime_dirt": 0.6, "chip_dirt": 1.0, "seam_dirt": 0.5, "dirt_on_paint_only": 1.0}},
    **LEGACY_SEAMS,  # the seams before Q69, pinned until T74
)
