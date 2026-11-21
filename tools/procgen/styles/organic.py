"""Organic styles (M10-T06, D12.2): the skins and sheen layers the organic hulls wear.

Three looks of the framework's own, for the organic test hull and as the start of the factions' styles (a hull task copies
one into ``styles/<faction>_capital.py`` and sets its pattern's size for its hull):

* ``vorlon``: seamless (Q46), yellow-green mottled with black, deep blue petals, iridescent, a faint glow of its own, the
  mottling alive as a cuttlefish's skin; a fifth of the hulls red-based (the look's second colouring);
* ``shadow``: seamless, the blackest skin, big slow scales with a glossy black liquid running in the gaps between them;
* ``hex``: semi-organic (Q47), an organic shape plated with the hexagonal grid (Q45), a hint of sheen and soft mottling.

The sheens are the maintainer's picks from the stage 1 look sheet (2026-11-21). Colours are linear RGB, from the show's
stills (docs/design-references.md).
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


def _gain(colour: RGB, paint: RGB) -> RGB:
    """What ``paint``'s brightness is multiplied by to give ``colour``: a variant's tint (``Sheen.variant_tint``)."""
    luma = 0.2126 * paint[0] + 0.7152 * paint[1] + 0.0722 * paint[2]
    return tuple(round(c / luma, 4) for c in colour)


# --- the Vorlons: yellow-green mottled with black as a leopard, the skin alive as a cuttlefish's -------------------------------
VORLON_SKIN: RGB = (0.30, 0.27, 0.035)
VORLON_RED: RGB = (0.33, 0.06, 0.018)  # the red-based hulls' copper (the show's heavy cruiser, still 01)
_VORLON_IRI = sh_from_lobes((0.30, 0.42, 0.10), [((0.0, 1.0, 0.0), (0.35, 0.20, -0.05), 100.0), ((0.0, -1.0, 0.2), (-0.20, -0.10, 0.55), 110.0),
                                                 ((1.0, 0.0, -0.4), (0.25, -0.25, 0.35), 90.0), ((-1.0, 0.0, -0.4), (-0.15, 0.20, 0.30), 90.0)])
_VORLON_RED_IRI = sh_from_lobes((0.50, 0.13, 0.06), [((0.0, 1.0, 0.0), (0.30, 0.25, -0.03), 100.0), ((0.0, -1.0, 0.2), (0.05, -0.12, 0.45), 110.0),
                                                     ((1.0, 0.0, -0.4), (0.20, -0.10, 0.30), 90.0), ((-1.0, 0.0, -0.4), (0.10, 0.18, 0.02), 90.0)])
# Bold dark mottling with soft edges that swells and fades patch by patch, small spots opening and closing between the
# blotches, a green-gold to violet iridescence that wanders in slow waves, a faint breathing glow in the blotches' veins.
# A fifth of the hulls are red-based (Q: the maintainer, 2026-11-21), with the same mottling.
VORLON = Sheen(iri_sh=_VORLON_IRI, iri_strength=0.6, iri_base=0.08, iri_power=2.5, iri_view=0.7, iri_metal=0.5, iri_wave=0.6, iri_wave_s=28.0,
               pattern_scale_m=5.0, pattern_cells=0.0, pattern_edge=0.7, pattern_cover=0.45, pattern_dark=0.93, pattern_tint=(0.006, 0.008, 0.005),
               pattern_iri=1.0, pattern_rough=0.15, pattern_spots=0.85, pattern_pulse=0.8, pattern_pulse_s=16.0,
               glow_colour=(0.55, 1.0, 0.35), glow_energy=0.035, glow_veins=0.7, glow_rim=0.5, glow_pulse_s=9.0, glow_pulse=0.35, coat=0.6,
               variant_share=0.2, variant_tint=_gain(VORLON_RED, VORLON_SKIN), variant_sh=_VORLON_RED_IRI, variant_glow=(1.0, 0.55, 0.25))

# --- the Shadows: the blackest skin, big slow scales, a black liquid running in the gaps between them -------------------------
_SHADOW_IRI = sh_from_lobes((0.16, 0.05, 0.34), [((0.0, 1.0, 0.0), (-0.06, 0.03, 0.14), 110.0), ((0.0, -1.0, 0.0), (0.12, -0.02, -0.05), 110.0)])
SHADOW = Sheen(iri_sh=_SHADOW_IRI, iri_strength=0.25, iri_base=0.0, iri_power=5.0, iri_view=0.8, iri_metal=0.9,
               pattern_scale_m=4.0, pattern_cells=1.0, pattern_edge=0.6, pattern_cover=0.78, pattern_dark=0.97, pattern_tint=(0.0, 0.0, 0.0),
               pattern_iri=1.0, pattern_rough=0.0, pattern_speed_mps=0.15, pattern_relief=0.6, liquid=1.0, liquid_flow_mps=0.5,
               glow_colour=(0.45, 0.2, 1.0), glow_energy=0.006, glow_veins=1.0, coat=0.0)

# --- semi-organic, hexagonal plating (the Minbari and the Interstellar Alliance): a hint of sheen at the rim, soft violet mottling
_HEX_IRI = sh_from_lobes((0.16, 0.24, 0.62), [((0.0, 1.0, 0.0), (0.02, 0.22, 0.25), 110.0), ((0.0, -1.0, 0.0), (0.38, -0.10, 0.10), 110.0)])
HEX = Sheen(iri_sh=_HEX_IRI, iri_strength=0.2, iri_base=0.0, iri_power=4.0, iri_view=0.3, iri_metal=0.6,
            pattern_scale_m=9.0, pattern_cover=0.45, pattern_edge=0.4, pattern_dark=0.6, pattern_tint=(0.07, 0.03, 0.2))

_STYLES = {
    "vorlon": (organic_style("organic_vorlon", VORLON_SKIN, (0.24, 0.22, 0.03), (0.02, 0.06, 0.36), 0.35, 0.42), Seamless(), VORLON),
    # The scales themselves are matt: the gloss is the liquid's, in the gaps.
    "shadow": (organic_style("organic_shadow", (0.012, 0.012, 0.016), (0.010, 0.010, 0.013), (0.012, 0.012, 0.016), 0.4, 0.72), Seamless(), SHADOW),
    "hex": (organic_style("organic_hex", (0.09, 0.14, 0.30), (0.07, 0.10, 0.24), (0.15, 0.11, 0.32), 0.5, 0.4, paneled=True),
            HexGrid(cell_m=5.0, frames_m=60.0), HEX),
}
LOOKS = tuple(_STYLES)


def organic(look: str, variant: bool = False) -> CapitalStyle:
    """The capital style of a look (``vorlon``, ``shadow``, ``hex``). ``variant`` puts every ship in the look's second
    colouring (the red-based Vorlons), for a look sheet; in the game a ship's own name decides."""
    if look not in _STYLES:
        raise ValueError(f"an organic look is one of {LOOKS}")
    style, skin, sheen = _STYLES[look]
    if variant and sheen.variant_share <= 0.0:
        raise ValueError(f"the {look} look has no second colouring")
    worn = sheen.but(variant_all=1.0) if variant else sheen
    return CapitalStyle(f"organic_{look}" + ("_variant" if variant else ""), style, skin, {"sheen": worn.to_json()})


__all__ = ["HEX", "LOOKS", "SHADOW", "VORLON", "organic", "organic_style"]
