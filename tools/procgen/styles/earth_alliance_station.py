"""The Earth Alliance station's paint (M7-T04, docs/assets-station.md "Colour scheme" and "Metal and reflection"): light grey drum
plating with blue-violet panel blocks, a warm grey-brown support spine, red cargo modules, deep blue vanes, a dark bronze reactor,
red trim and yellow-orange hatch bands on the Cobra arms, warm-white windows.

The hex values were read off lit show captures, so each becomes the albedo that shows it under the game's light
(``capture_albedo``, as the civilians' colours did in M5-T39). The station is texelled at about a metre, so the wear and grime
that a fighter's centimetre texel carries are scaled up (``wear_scale``).

Metal, not plastic (the maintainer, 2026-11-13): the plating is painted metal (moderately metallic, a satin roughness that
steps from plate to plate and panel to panel), the trim of rails, booms, truss, radiators and reactor is bare metal (more
metallic, smoother), and dirt and worn paint are rougher and duller (``metal_finish``, shared with the raider's M7-T16 finish);
worn edges show metal. A metallic paint loses diffuse light, so its albedo is raised to keep the colour the capture shows in
diffuse light; a bare metal's albedo is its reflectance.
"""

from __future__ import annotations

from ..core.color import capture_albedo, srgb_to_linear
from ..core.geometry import Material
from . import Style

PREFIX = "eas"

# role: (lit capture sRGB, paneled, metallic, roughness)
SCHEME: dict[str, tuple[int, bool, float, float]] = {
    "drum_grey": (0xAEAEAD, True, 0.45, 0.42),
    "drum_blue": (0x9191CB, True, 0.45, 0.46),
    "recess": (0x353432, True, 0.50, 0.66),
    "spine": (0x736B63, True, 0.50, 0.48),
    "spine_top": (0x4A4440, True, 0.50, 0.56),
    "cargo": (0x974C4C, True, 0.40, 0.50),
    "vane": (0x20487A, True, 0.55, 0.34),
    "vane_dark": (0x10244C, True, 0.55, 0.55),
    "vane_frame": (0x8C8C8B, True, 0.75, 0.32),
    "reactor": (0x4A433C, True, 0.75, 0.38),
    "trim": (0x915555, True, 0.45, 0.46),
    "hatch": (0xCAA75F, True, 0.45, 0.50),
    "door": (0x7A4A3A, True, 0.55, 0.44),
    "machinery": (0x5A5856, True, 0.85, 0.28),
    "dome": (0x3A3A40, False, 0.90, 0.12),
    "window": (0x141618, False, 0.0, 0.15),
    "bay_frame": (0x8A8770, True, 0.45, 0.50),
}
# The bare metals' reflectance (sRGB), in place of a painted colour: steel for the trim and machinery, a bronze cast for the reactor.
BARE_METAL: dict[str, int] = {"vane_frame": 0x9C9B99, "reactor": 0x7A6E62, "machinery": 0x8E8B87, "dome": 0x6E7078}
# How much of a metallic paint's lost diffuse light its albedo makes up (1: all of it).
DIFFUSE_KEEP = 0.7
# Where each required role of a style points: the shared parts code asks for these names.
ALIASES = {
    "hull": "drum_grey", "hull_dark": "recess", "hull_panel": "spine", "stripe": "drum_blue", "hazard": "cargo",
    "hazard_dark": "vane", "canopy_glass": "window", "canopy_frame": "dome", "nozzle": "reactor", "nozzle_throat": "recess",
    "barrel": "machinery", "bore": "recess", "interior": "recess", "rcs": "machinery",
}
WINDOW_GLOW = 0xFFE7C2  # warm white, as the civilians' windows
WINDOW_STRENGTH = 2.2
LAMP_GLOW = 0xFF3A2A  # the red lamp on the observation dome and the bow spine's red panels
LAMP_STRENGTH = 3.0
BAY_GLOW = 0xFFA860  # warm orange: the Cobra bays' light round the doors (the show capture) and the docking aperture's lit interior
BAY_STRENGTH = 3.5
# The docking bay (M7-T05): dark machinery in deep shadow, red only on the frames' edges, the lamps and the airlock's seam, brightest
# at the mouth and dimmer the deeper; pink panels at the mouth's sides. T18 adds the real red lights.
BAY_RED = 0xE0281A
BAY_RED_STRENGTHS = (1.6, 1.35, 1.15, 0.95, 0.8, 0.65)  # the edges: the mouth's frames, then the tunnel's inward  # the mouth's frames, then the tunnel's frames from the mouth inward
BAY_WALL_STRENGTH = 0.0
BAY_DOOR_STRENGTH = 0.08
BAY_PINK = 0xFF7A9A
BAY_PINK_STRENGTH = 0.8


def lin(hex_rgb: int) -> tuple[float, float, float]:
    """Linear RGB of an sRGB ``0xRRGGBB`` value."""
    r, g, b = (float(v) for v in srgb_to_linear([((hex_rgb >> s) & 255) / 255.0 for s in (16, 8, 0)]))
    return (r, g, b)


def colour(role: str) -> tuple[float, float, float]:
    """The albedo a role paints with (also for the paint markings that change a part's base coat): a bare metal's reflectance,
    else the capture's colour raised for what the paint's metal takes from its diffuse light."""
    hex_rgb, _, metallic, _ = SCHEME[role]
    if role in BARE_METAL:
        return lin(BARE_METAL[role])
    gain = 1.0 / (1.0 - DIFFUSE_KEEP * metallic)
    r, g, b = (min(0.85, c * gain) for c in capture_albedo(hex_rgb))
    return (r, g, b)


def _materials() -> dict[str, Material]:
    out = {role: Material(f"{PREFIX}_{role}", colour(role), paneled=paneled, metallic=metallic, roughness=roughness)
           for role, (_, paneled, metallic, roughness) in SCHEME.items()}
    out["lamp"] = Material(f"{PREFIX}_lamp", capture_albedo(0x7A2A24), emissive=lin(LAMP_GLOW), emissive_strength=LAMP_STRENGTH)
    out["bay_light"] = Material(f"{PREFIX}_bay_light", capture_albedo(0xD8D0C0), emissive=lin(BAY_GLOW), emissive_strength=BAY_STRENGTH)
    red = lin(BAY_RED)
    for k, strength in enumerate(BAY_RED_STRENGTHS):
        out[f"bay_red_{k}"] = Material(f"{PREFIX}_bay_red_{k}", capture_albedo(0x5A2420), metallic=0.5, roughness=0.5, emissive=red,
                                       emissive_strength=strength)
    out["bay_wall"] = Material(f"{PREFIX}_bay_wall", capture_albedo(0x231C1A), paneled=True, metallic=0.6, roughness=0.55, emissive=red,
                               emissive_strength=BAY_WALL_STRENGTH)
    out["bay_door"] = Material(f"{PREFIX}_bay_door", capture_albedo(0x2E1A16), metallic=0.6, roughness=0.5, emissive=red,
                               emissive_strength=BAY_DOOR_STRENGTH)
    out["bay_pink"] = Material(f"{PREFIX}_bay_pink", capture_albedo(0xC8A0A8), emissive=lin(BAY_PINK), emissive_strength=BAY_PINK_STRENGTH)
    out["bay_dark"] = Material(f"{PREFIX}_bay_dark", capture_albedo(0x0A0A0A), metallic=0.3, roughness=0.8)
    for role, target in ALIASES.items():
        out[role] = out[target]
    return out


EARTH_ALLIANCE_STATION = Style(
    name="earth_alliance_station",
    materials=_materials(),
    panel_size_m=40.0,
    panel_line_width_m=3.0,
    panel_line_darkness=0.6,
    panel_tint_jitter=0.05,
    groove_depth_m=0.6,
    hatch_depth_m=0.3,
    edge_wear=0.35,
    edge_wear_width_m=3.0,
    grime_scale_m=160.0,
    streaks=0.12,
    grime=0.07,
    extra={"wear_scale": 100.0, "rivets": 0.0, "bare_metal": 0.35, "smudge": 0.04, "smudge_scale_m": 1.2, "speckle": 0.03,
           "streak_length_m": 0.3,
           # Roughness steps from panel to panel (40 m cells) and drifts within them; dirt is rougher and duller.
           "metal_finish": {"panel_m": 40.0, "panel_rough": 0.08, "noise_m": 30.0, "noise_rough": 0.05, "dirt_rough": 0.28,
                            "dirt_metal": 0.5, "grime_dirt": 0.6}},
)

__all__ = ["BAY_RED", "EARTH_ALLIANCE_STATION", "LAMP_GLOW", "SCHEME", "WINDOW_GLOW", "WINDOW_STRENGTH", "colour", "lin"]
