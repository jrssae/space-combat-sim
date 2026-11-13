"""The Cobra-bay hangar's paint (M7-T09, docs/assets-station.md "Interior (M7-T09)"): the inside of a launch arm, dark, lit red and
white.

The mood is the show's Cobra-bay capture's (``references/cobra bay interior references/``, most weight): grimy and low-key, the
red mostly from the light, as in the show's bay interiors (``references/docking bay references/``). The walls and
machinery are grey painted metal and bare steel, the red trim and the yellow-orange hazard bands are the station's own (the same
roles as ``earth_alliance_station``), and the glow is the station's bay light, its red lamp colour and a warm white for the work
lamps. Lit pink panels in the machinery walls stand for the show's pink-lit control panels.

Metal, not plastic (D72, the maintainer 2026-11-13): painted metal steps its roughness from plate to plate and drifts within a
plate, bare steel is smoother and more metallic, dirt is rougher and duller (``metal_finish``, shared with the station and the
raider). The atlases are texelled at 5 to 10 cm, so the panels are big and the wear is scaled up (``wear_scale``); the station's
detail tile carries the small plating near the camera.
"""

from __future__ import annotations

from ..core.color import capture_albedo
from ..core.geometry import Material
from . import Style
from .earth_alliance_station import BAY_GLOW, LAMP_GLOW, lin

PREFIX = "cb"

# role: (lit capture sRGB, paneled, metallic, roughness)
SCHEME: dict[str, tuple[int, bool, float, float]] = {
    "deck": (0x48484A, True, 0.70, 0.48),  # the floor's plating, dark grey as the show capture (the maintainer, 2026-11-13)
    "wall": (0x6E6A66, True, 0.55, 0.42),  # the machinery walls' plating
    "frame": (0x9A9998, True, 0.50, 0.40),  # the gantries, ribs and beams: the drum's grey
    "recess": (0x2E2D2B, True, 0.50, 0.66),  # wells, gaps and the backs of the machinery
    "trim": (0x915555, True, 0.45, 0.46),  # the station's red trim
    "hatch": (0xCAA75F, True, 0.45, 0.50),  # the yellow-orange hazard bands
    "door": (0x7A4A3A, True, 0.55, 0.44),  # the launch doors' leaves, as outside
    "canister": (0xC2662E, True, 0.45, 0.48),  # the show's orange canisters
    "machinery": (0x5A5856, False, 0.90, 0.30),  # bare steel: pipes, rails, hinges, rams
    "rubber": (0x1E1E1E, False, 0.0, 0.85),  # the clamps' pads and the cable runs
}
# The bare metals' reflectance (sRGB), in place of a painted colour.
BARE_METAL: dict[str, int] = {"machinery": 0x8E8B87}
DIFFUSE_KEEP = 0.7  # as the station: how much of a metallic paint's lost diffuse light its albedo makes up
# The glows: the bay's warm orange (the station's), its red lamps, the work lamps' warm white and the pink-lit panels.
WORK_GLOW = 0xFFE2B8
WORK_STRENGTH = 6.0
BAY_STRENGTH = 3.0
LAMP_STRENGTH = 3.0
PANEL_GLOW = 0xFF8C9A
PANEL_STRENGTH = 1.4
ALIASES = {
    "hull": "frame", "hull_dark": "recess", "hull_panel": "wall", "stripe": "hatch", "hazard": "hatch", "hazard_dark": "recess",
    "canopy_glass": "recess", "canopy_frame": "frame", "nozzle": "machinery", "nozzle_throat": "recess", "barrel": "machinery",
    "bore": "recess", "interior": "recess", "rcs": "machinery",
}


def colour(role: str) -> tuple[float, float, float]:
    """The albedo a role paints with: a bare metal's reflectance, else the capture's colour raised for the paint's metal."""
    hex_rgb, _, metallic, _ = SCHEME[role]
    if role in BARE_METAL:
        return lin(BARE_METAL[role])
    gain = 1.0 / (1.0 - DIFFUSE_KEEP * metallic)
    r, g, b = (min(0.85, c * gain) for c in capture_albedo(hex_rgb))
    return (r, g, b)


def _glow(name: str, hex_rgb: int, strength: float) -> Material:
    return Material(f"{PREFIX}_{name}", capture_albedo(0xD8D0C0), emissive=lin(hex_rgb), emissive_strength=strength)


def _materials() -> dict[str, Material]:
    out = {role: Material(f"{PREFIX}_{role}", colour(role), paneled=paneled, metallic=metallic, roughness=roughness)
           for role, (_, paneled, metallic, roughness) in SCHEME.items()}
    out["bay_light"] = _glow("bay_light", BAY_GLOW, BAY_STRENGTH)
    out["lamp"] = _glow("lamp", LAMP_GLOW, LAMP_STRENGTH)
    out["work_light"] = _glow("work_light", WORK_GLOW, WORK_STRENGTH)
    out["panel_light"] = _glow("panel_light", PANEL_GLOW, PANEL_STRENGTH)
    for role, target in ALIASES.items():
        out[role] = out[target]
    return out


COBRA_BAY = Style(
    name="cobra_bay",
    materials=_materials(),
    panel_size_m=4.8,
    panel_line_width_m=0.16,
    panel_line_darkness=0.6,
    panel_tint_jitter=0.06,
    groove_depth_m=0.03,
    hatch_depth_m=0.02,
    edge_wear=0.45,
    edge_wear_width_m=0.12,
    grime_scale_m=6.0,
    streaks=0.14,
    grime=0.08,
    extra={"wear_scale": 4.0, "rivets": 0.6, "bare_metal": 0.5, "smudge": 0.06, "smudge_scale_m": 0.6, "speckle": 0.04,
           "streak_length_m": 0.4,
           # Roughness steps from plate to plate and drifts within a plate; dirt is rougher and duller.
           "metal_finish": {"panel_m": 4.8, "panel_rough": 0.08, "noise_m": 1.5, "noise_rough": 0.05, "dirt_rough": 0.25,
                            "dirt_metal": 0.45, "grime_dirt": 0.5}},
)

__all__ = ["COBRA_BAY", "PANEL_GLOW", "SCHEME", "WORK_GLOW", "colour"]
