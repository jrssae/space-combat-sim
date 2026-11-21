"""Organic styles (M10-T06, D12.2): the skins and sheen layers the organic hulls wear.

Three looks of the framework's own, for the organic test hull and as the start of the factions' styles (a hull task copies
one into ``styles/<faction>_capital.py`` and sets its pattern's size for its hull):

* ``vorlon``: seamless (Q46), yellow-green mottled with black, deep blue petals, iridescent, a faint glow of its own;
* ``shadow``: seamless, black, a faint purple sheen and scales that crawl over the skin;
* ``hex``: semi-organic (Q47), an organic shape plated with the hexagonal grid (Q45), a quiet blue to violet sheen.

Each look has sheen options ``a``, ``b`` and ``c`` for the look sheet (stage 1); the maintainer's pick becomes the style's
one sheen. Colours are linear RGB, from the show's stills (docs/design-references.md).
"""

from __future__ import annotations

from ..core.geometry import Material
from ..core.sheen import Sheen, sh_from_lobes
from . import Style
from .capital import CapitalStyle, HexGrid, Seamless

RGB = tuple[float, float, float]


def organic_style(name: str, skin: RGB, limbs: RGB, petals: RGB, metallic: float, roughness: float, paneled: bool = False) -> Style:
    """A style whose every role is living skin: ``skin`` the body's, ``limbs`` the spines' and claws' (role ``hull_dark``),
    ``petals`` the shells' (role ``hull_panel``). No wear: nothing chips, streaks or rusts."""
    body = Material(f"{name}_skin", skin, paneled=paneled, metallic=metallic, roughness=roughness)
    limb = Material(f"{name}_limb", limbs, paneled=paneled, metallic=metallic, roughness=roughness)
    shell = Material(f"{name}_petal", petals, paneled=paneled, metallic=metallic, roughness=roughness)
    roles = {role: body for role in ("hull", "stripe", "hazard", "hazard_dark", "canopy_glass", "canopy_frame", "nozzle", "nozzle_throat",
                                     "barrel", "bore", "interior", "rcs")}
    # No edge is worn either: the bake's chipping is switched off by an edge of no width and no bare metal under the paint.
    return Style(name=name, materials={**roles, "hull_dark": limb, "hull_panel": shell}, panel_line_darkness=0.7, panel_tint_jitter=0.0,
                 groove_depth_m=0.006, hatch_fraction=0.0, edge_wear=0.0, edge_wear_width_m=1e-9, streaks=0.0, grime=0.0, soot=0.0,
                 extra={"bare_metal": 0.0, "rivets": 0.0})


# --- the Vorlons ----------------------------------------------------------------------------------------------------------
_VORLON_IRI = sh_from_lobes((0.30, 0.42, 0.10), [((0.0, 1.0, 0.0), (0.35, 0.20, -0.05), 100.0), ((0.0, -1.0, 0.2), (-0.20, -0.10, 0.55), 110.0),
                                                 ((1.0, 0.0, -0.4), (0.25, -0.25, 0.35), 90.0), ((-1.0, 0.0, -0.4), (-0.15, 0.20, 0.30), 90.0)])
_VORLON = Sheen(iri_sh=_VORLON_IRI, iri_strength=0.6, iri_base=0.08, iri_power=2.5, iri_view=0.7, iri_metal=0.5,
                pattern_scale_m=5.0, pattern_cells=0.0, pattern_edge=0.8, pattern_cover=0.45, pattern_dark=0.93, pattern_tint=(0.006, 0.008, 0.005),
                pattern_iri=1.0, pattern_rough=0.15, glow_colour=(0.55, 1.0, 0.35), glow_energy=0.035, glow_veins=0.7, glow_rim=0.5,
                glow_pulse_s=9.0, glow_pulse=0.35, coat=0.6)
VORLON_SHEENS = {
    "a": _VORLON,  # the show's leopard skin: bold dark mottling, a green-gold to violet travel, a faint breathing glow
    "b": _VORLON.but(iri_strength=0.95, iri_base=0.3, iri_view=1.0, iri_metal=0.8, pattern_scale_m=3.2, pattern_cover=0.33, pattern_iri=0.8,
                     glow_veins=0.0, glow_energy=0.02),  # an opal: the colours slide with the camera, finer mottling, an even glow
    "c": _VORLON.but(iri_strength=0.4, iri_base=0.0, iri_power=4.0, iri_metal=0.2, pattern_dark=0.6, pattern_edge=0.45, pattern_cover=0.5,
                     glow_colour=(0.3, 0.6, 1.0), glow_energy=0.1, glow_veins=1.0, glow_pulse=0.6),  # quiet: soft mottling, blue veins that pulse
}

# --- the Shadows ----------------------------------------------------------------------------------------------------------
_SHADOW_IRI = sh_from_lobes((0.16, 0.05, 0.34), [((0.0, 1.0, 0.0), (-0.06, 0.03, 0.14), 110.0), ((0.0, -1.0, 0.0), (0.12, -0.02, -0.05), 110.0)])
_SHADOW = Sheen(iri_sh=_SHADOW_IRI, iri_strength=0.5, iri_base=0.0, iri_power=3.5, iri_view=0.8, iri_metal=0.9,
                pattern_scale_m=2.6, pattern_cells=1.0, pattern_edge=0.6, pattern_cover=0.5, pattern_dark=0.6, pattern_tint=(0.0, 0.0, 0.0),
                pattern_iri=0.85, pattern_rough=0.3, pattern_speed_mps=0.35, glow_colour=(0.45, 0.2, 1.0), glow_energy=0.0, coat=0.25)
SHADOW_SHEENS = {
    "a": _SHADOW,  # the show's: fine scales that crawl, a purple sheen at the rim only
    "b": _SHADOW.but(pattern_cells=0.25, pattern_scale_m=6.0, pattern_speed_mps=0.9, pattern_edge=0.3, iri_strength=0.85, iri_base=0.04,
                     iri_power=2.0, coat=0.5),  # an oil film: soft patches that flow, a wider, bluer sheen
    "c": _SHADOW.but(iri_strength=0.25, iri_power=5.0, pattern_scale_m=4.0, pattern_speed_mps=0.15, pattern_rough=0.4, glow_energy=0.012,
                     glow_veins=1.0, coat=0.1),  # the blackest: a hint of sheen, big slow scales, the faintest violet in their seams
}

# --- semi-organic, hexagonal plating ------------------------------------------------------------------------------------------
_HEX_IRI = sh_from_lobes((0.16, 0.24, 0.62), [((0.0, 1.0, 0.0), (0.02, 0.22, 0.25), 110.0), ((0.0, -1.0, 0.0), (0.38, -0.10, 0.10), 110.0)])
_HEX = Sheen(iri_sh=_HEX_IRI, iri_strength=0.5, iri_base=0.05, iri_power=3.0, iri_view=0.3, iri_metal=0.6)
HEX_SHEENS = {
    "a": _HEX,  # a blue hull that turns violet below and at the rim
    "b": _HEX.but(iri_strength=0.95, iri_base=0.45, iri_power=1.5, iri_view=1.0, iri_metal=0.9),  # a strong travel from cyan to violet as the view turns
    "c": _HEX.but(iri_strength=0.2, iri_base=0.0, iri_power=4.0, pattern_scale_m=9.0, pattern_cover=0.45, pattern_edge=0.4, pattern_dark=0.6,
                  pattern_tint=(0.07, 0.03, 0.2)),  # a hint at the rim, and soft violet mottling as the White Star has
}

_STYLES = {
    "vorlon": (organic_style("organic_vorlon", (0.30, 0.27, 0.035), (0.24, 0.22, 0.03), (0.02, 0.06, 0.36), 0.35, 0.42), Seamless(), VORLON_SHEENS),
    "shadow": (organic_style("organic_shadow", (0.012, 0.012, 0.016), (0.010, 0.010, 0.013), (0.012, 0.012, 0.016), 0.6, 0.32), Seamless(),
               SHADOW_SHEENS),
    "hex": (organic_style("organic_hex", (0.09, 0.14, 0.30), (0.07, 0.10, 0.24), (0.15, 0.11, 0.32), 0.5, 0.4, paneled=True),
            HexGrid(cell_m=5.0, frames_m=60.0), HEX_SHEENS),
}
LOOKS = tuple(_STYLES)
OPTIONS = ("a", "b", "c")


def organic(look: str, option: str = "a") -> CapitalStyle:
    """The capital style of a look (``vorlon``, ``shadow``, ``hex``) with one of its sheen options."""
    if look not in _STYLES or option not in OPTIONS:
        raise ValueError(f"an organic look is one of {LOOKS} with an option of {OPTIONS}")
    style, skin, sheens = _STYLES[look]
    return CapitalStyle(f"organic_{look}_{option}", style, skin, {"sheen": sheens[option].to_json()})


__all__ = ["HEX_SHEENS", "LOOKS", "OPTIONS", "SHADOW_SHEENS", "VORLON_SHEENS", "organic", "organic_style"]
