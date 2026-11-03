"""Earth Alliance civilian design language (docs/assets-civilian.md "Styles", docs/design-references.md "Saturn family"):
warm grey plating, grey cargo pods with darker patches, red and off-white bands on the tubular sections, a rust-red ring
and dark fins on the command disc's top, warm-white rim windows, dark nozzles.

Hex values are the sRGB colours read off the screen captures; materials store them as linear albedo. A hull that wears
the same language in other paint (the Skylark's sand plating) builds its own copy with :func:`ea_civilian`.
"""

from __future__ import annotations

from collections.abc import Mapping

import numpy as np

from ..core.color import srgb_to_linear
from ..core.geometry import Material
from . import Style

PREFIX = "eac"

# role: (sRGB, paneled, metallic, transmittance)
SCHEME: dict[str, tuple[int, bool, float, float]] = {
    "hull": (0xA7A49E, True, 0.0, 0.0),
    "hull_panel": (0x8C8B86, True, 0.0, 0.0),
    "hull_patch": (0x75736E, True, 0.0, 0.0),
    "hull_dark": (0x55534F, True, 0.0, 0.0),
    "stripe": (0xA33A2E, True, 0.0, 0.0),
    "band_light": (0xD9D5CC, True, 0.0, 0.0),
    "hazard": (0xD6AE2A, False, 0.0, 0.0),
    "hazard_dark": (0x262626, False, 0.0, 0.0),
    "disc_ring": (0x9C4A3C, True, 0.0, 0.0),
    "disc_fin": (0x3B3735, False, 0.0, 0.0),
    "disc_hub": (0xE2DED6, True, 0.0, 0.0),
    "window": (0xF2E6C8, False, 0.0, 0.0),
    "canopy_glass": (0x10161C, False, 0.0, 0.0),
    "canopy_frame": (0x55534F, False, 0.5, 0.0),
    "nozzle": (0x4A4946, False, 0.8, 0.0),
    "nozzle_throat": (0x1C1B1A, False, 0.8, 0.0),
    "rcs": (0x6E6C68, False, 0.6, 0.0),
    "barrel": (0x5A5955, False, 0.7, 0.0),
    "bore": (0x101010, False, 0.0, 0.0),
    "interior": (0x2E2C2A, False, 0.0, 0.0),
}


def lin(hex_rgb: int) -> tuple[float, float, float]:
    """Linear RGB of an sRGB ``0xRRGGBB`` value."""
    srgb = np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255], dtype=float) / 255.0
    r, g, b = (float(v) for v in srgb_to_linear(srgb))
    return (r, g, b)


def ea_civilian(overrides: Mapping[str, int] | None = None) -> Style:
    """The style, with any role repainted to another sRGB value (per-hull trim). A repainted role gets its own material
    name, so two hulls' meshes never share a name with different colours."""
    overrides = dict(overrides or {})
    unknown = set(overrides) - set(SCHEME)
    if unknown:
        raise ValueError(f"ea_civilian has no roles {sorted(unknown)}")
    materials = {}
    for role, (hex_rgb, paneled, metallic, transmittance) in SCHEME.items():
        colour = overrides.get(role, hex_rgb)
        name = f"{PREFIX}_{role}" if colour == hex_rgb else f"{PREFIX}_{role}_{colour:06x}"
        materials[role] = Material(name, lin(colour), transmittance=transmittance, paneled=paneled, metallic=metallic)
    return Style(
        name="ea_civilian",
        materials=materials,
        panel_size_m=3.6,
        panel_line_width_m=0.4,
        panel_line_darkness=0.6,
        panel_tint_jitter=0.06,
    )


EA_CIVILIAN = ea_civilian()
