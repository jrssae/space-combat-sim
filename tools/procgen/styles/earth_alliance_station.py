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
from . import LEGACY_SEAMS, Style

PREFIX = "eas"

# role: (lit capture sRGB, paneled, metallic, roughness)
SCHEME: dict[str, tuple[int, bool, float, float]] = {
    "drum_grey": (0xA2A5AE, True, 0.45, 0.42),  # M7-T24: neutral to cool, as the station from below
    "drum_blue": (0x8075BE, True, 0.45, 0.46),  # M7-T24: a lavender-violet, lighter and greyer in sunlight (the side reference)
    "arm_grey": (0x8C8F97, True, 0.45, 0.44),  # M7-T24: the Cobra arms a darker grey than the drum (Passaro, the station from below)
    "recess": (0x333438, True, 0.50, 0.66),
    "spine": (0x6C6E74, True, 0.50, 0.48),  # M7-T24: dark neutral grey, no brown cast (the station from below)
    "spine_top": (0x45474D, True, 0.50, 0.56),
    "cargo": (0x974C4C, True, 0.40, 0.50),
    "vane": (0x2A3A7E, True, 0.55, 0.34),  # M7-T24: a deep blue leaning violet, as the drum's
    "vane_dark": (0x10244C, True, 0.55, 0.55),
    "vane_frame": (0x8C8E93, True, 0.75, 0.32),
    "reactor": (0x4A4746, True, 0.75, 0.38),
    "trim": (0x915555, True, 0.45, 0.46),
    "hatch": (0xCAA75F, True, 0.45, 0.50),
    "door": (0x7A4A3A, True, 0.55, 0.44),
    "machinery": (0x5A5856, True, 0.85, 0.28),
    "dome": (0x3A3A40, False, 0.90, 0.12),
    "window": (0x141618, False, 0.0, 0.15),
    "bay_frame": (0x8A8770, True, 0.45, 0.50),
}
# The bare metals' reflectance (sRGB), in place of a painted colour: steel for the trim and machinery, a bronze cast for the reactor.
BARE_METAL: dict[str, int] = {"vane_frame": 0x9A9DA4, "reactor": 0x65625F, "machinery": 0x8A8D93, "dome": 0x6E7078}
# Epsilon Eridani's light is warm (about 5 100 K), which turns a neutral grey brown: the station's paints are balanced against it
# (M7-T24), part of the way, so its greys read neutral to cool in the star's light and its blues stay blue-violet.
STAR_BALANCE = (0.92, 1.0, 1.13)
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
# The main docking bay's mouth (M7-T25): metallic grey plating lit red, as in the show. Its red lamps light it up close (two of
# `LightRig`'s slots); this faint red glow is what it keeps at range, where the lamps lose their slots.
BAY_TUNNEL = 0xA8AAAE  # sRGB; taken as the metal's own colour, not a lit capture
BAY_TUNNEL_STRENGTH = 0.04


def lin(hex_rgb: int) -> tuple[float, float, float]:
    """Linear RGB of an sRGB ``0xRRGGBB`` value."""
    r, g, b = (float(v) for v in srgb_to_linear([((hex_rgb >> s) & 255) / 255.0 for s in (16, 8, 0)]))
    return (r, g, b)


def colour(role: str) -> tuple[float, float, float]:
    """The albedo a role paints with (also for the paint markings that change a part's base coat): a bare metal's reflectance,
    else the capture's colour raised for what the paint's metal takes from its diffuse light."""
    hex_rgb, _, metallic, _ = SCHEME[role]
    if role in BARE_METAL:
        r, g, b = (min(0.95, c * k) for c, k in zip(lin(BARE_METAL[role]), STAR_BALANCE, strict=True))
        return (r, g, b)
    gain = 1.0 / (1.0 - DIFFUSE_KEEP * metallic)
    r, g, b = (min(0.85, c * gain * k) for c, k in zip(capture_albedo(hex_rgb), STAR_BALANCE, strict=True))
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
    out["bay_tunnel"] = Material(f"{PREFIX}_bay_tunnel", lin(BAY_TUNNEL), paneled=True, metallic=0.7, roughness=0.32,
                                 emissive=red, emissive_strength=BAY_TUNNEL_STRENGTH)
    # The black void behind the main docking bay's inner doors (M7-T25): a docking ship flies into it out of sight.
    out["bay_void"] = Material(f"{PREFIX}_bay_void", capture_albedo(0x020202), metallic=0.0, roughness=1.0)
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
    streaks=0.0,  # M7-T24: no long streaks or smudges (they read as smears up close); the detail tile carries the joints' grime
    grime=0.07,
    extra={"wear_scale": 100.0, "rivets": 0.0, "bare_metal": 0.35, "smudge": 0.0, "smudge_scale_m": 1.2, "speckle": 0.03,
           # The Cobra arms' slanted facets take the detail tile flat in their own plane (M7-T24), not sheared across two axes.
           "planar_detail": {"parts": ["arms"], "max_axis": 0.9},
           "streak_length_m": 0.3,
           # Roughness steps from panel to panel (40 m cells) and drifts within them; dirt is rougher and duller.
           "metal_finish": {"panel_m": 40.0, "panel_rough": 0.08, "noise_m": 30.0, "noise_rough": 0.05, "dirt_rough": 0.28,
                            "dirt_metal": 0.5, "grime_dirt": 0.6}},
    **LEGACY_SEAMS,  # the seams before Q69, pinned until T74
)

__all__ = ["BAY_RED", "BAY_TUNNEL", "BAY_TUNNEL_STRENGTH", "EARTH_ALLIANCE_STATION", "LAMP_GLOW", "SCHEME", "WINDOW_GLOW", "WINDOW_STRENGTH", "colour", "lin"]
