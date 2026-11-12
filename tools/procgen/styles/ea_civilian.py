"""Earth Alliance civilian design language (docs/assets-civilian.md "Styles", docs/design-references.md "Saturn family"):
cool grey plating, grey cargo pods with darker patches, red and off-white bands on the tubular sections, a rust-red ring
and dark fins on the command disc's top, warm-white rim windows, dark nozzles.

Hex values are the sRGB colours read off the screen captures; materials store them as linear albedo. A hull that wears
the same language in other paint (the Skylark's khaki plating) builds its own copy with :func:`ea_civilian`.

The texture pack (M5-T27; docs/design-references.md, "Saturn family", texture): working freighters in clean industrial
paint, as Achilles.jpg, Red Star 9.jpg and Epsilon.JPG show them. Long plates with fine dark seams and a few hatches, a
light patchwork of tints from plate to plate, edges worn to dark primer rather than bare metal, faint grime and short
streaks aft of the seams, flat paint. The rim windows glow warm white and the engine throats the blue-white of
Valjean.JPG; the Skylark's throats take its warm white.
"""

from __future__ import annotations

from collections.abc import Mapping

import numpy as np

from ..core.color import capture_albedo, srgb_to_linear
from ..core.geometry import Material
from . import Style

PREFIX = "eac"

# role: (sRGB, paneled, metallic, transmittance)
SCHEME: dict[str, tuple[int, bool, float, float]] = {
    "hull": (0xA4A7AA, True, 0.0, 0.0),
    "hull_panel": (0x8A8D90, True, 0.0, 0.0),
    "hull_patch": (0x72757A, True, 0.0, 0.0),
    "hull_dark": (0x4F5256, True, 0.0, 0.0),
    "stripe": (0xA8322C, True, 0.0, 0.0),
    "band_light": (0xDADCDE, True, 0.0, 0.0),
    "hazard": (0xD6AE2A, False, 0.0, 0.0),
    "hazard_dark": (0x262626, False, 0.0, 0.0),
    "disc_ring": (0x9A5248, True, 0.0, 0.0),
    "disc_fin": (0x3B3735, False, 0.0, 0.0),
    "disc_hub": (0xE2E3E4, True, 0.0, 0.0),
    "window": (0xF2E6C8, False, 0.0, 0.0),
    "canopy_glass": (0x10161C, False, 0.0, 0.0),
    "canopy_frame": (0x4F5256, False, 0.5, 0.0),
    "nozzle": (0x4A4946, False, 0.8, 0.0),
    "nozzle_throat": (0x1C1B1A, False, 0.8, 0.0),
    "rcs": (0x6E6C68, False, 0.6, 0.0),
    "barrel": (0x5A5955, False, 0.7, 0.0),
    "bore": (0x101010, False, 0.0, 0.0),
    "interior": (0x2E2C2A, False, 0.0, 0.0),
}
# The lit roles: role -> emission strength; the colour is the role's own (windows) or the engine glow (throats).
WINDOW_STRENGTH = 2.0
ENGINE_STRENGTH = 3.0
ENGINE_GLOW = 0xDCE8FF  # blue-white, Valjean.JPG


def lin(hex_rgb: int) -> tuple[float, float, float]:
    """Linear RGB of an sRGB ``0xRRGGBB`` value."""
    srgb = np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255], dtype=float) / 255.0
    r, g, b = (float(v) for v in srgb_to_linear(srgb))
    return (r, g, b)


def ea_civilian(overrides: Mapping[str, int] | None = None, engine_glow: int = ENGINE_GLOW) -> Style:
    """The style, with any role repainted to another sRGB value (per-hull trim) and its own engine glow. A repainted role
    gets its own material name, so two hulls' meshes never share a name with different colours."""
    overrides = dict(overrides or {})
    unknown = set(overrides) - set(SCHEME)
    if unknown:
        raise ValueError(f"ea_civilian has no roles {sorted(unknown)}")
    materials = {}
    for role, (hex_rgb, paneled, metallic, transmittance) in SCHEME.items():
        colour = overrides.get(role, hex_rgb)
        name = f"{PREFIX}_{role}" if colour == hex_rgb else f"{PREFIX}_{role}_{colour:06x}"
        glow, strength = (0.0, 0.0, 0.0), 0.0
        if role == "window":
            glow, strength = lin(colour), WINDOW_STRENGTH
        elif role == "nozzle_throat":
            glow, strength = lin(engine_glow), ENGINE_STRENGTH
            name = name if engine_glow == ENGINE_GLOW else f"{name}_glow_{engine_glow:06x}"
        materials[role] = Material(name, capture_albedo(colour), transmittance=transmittance, paneled=paneled, metallic=metallic,
                                   emissive=glow, emissive_strength=strength)
    return Style(
        name="ea_civilian",
        materials=materials,
        panel_size_m=3.6,
        panel_line_width_m=0.4,
        **TEXTURE_PACK,
    )


# The texture pack at a fighter's scale (``core/civilian.py``'s ``at_texel`` scales it to the hull's texel).
TEXTURE_PACK = {
    "panel_line_darkness": 0.72,
    "panel_tint_jitter": 0.05,
    "hatch_fraction": 0.14,
    "edge_wear": 0.35,
    "streaks": 0.14,
    "grime": 0.07,
    "extra": {"bare_metal": 0.0, "smudge": 0.12, "speckle": 0.03, "paint_roughness": 0.72, "rivets": 0.4},
}


EA_CIVILIAN = ea_civilian()
