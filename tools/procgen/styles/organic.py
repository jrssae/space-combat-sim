"""Organic styles (M10-T06, D12.2): the skins and sheen layers the organic hulls wear.

Three looks of the framework's own, for the organic test hull and as the start of the factions' styles (a hull task copies
one into ``styles/<faction>_capital.py`` and sets its pattern's size for its hull):

* ``vorlon``: seamless (Q46), yellow-green mottled with black, deep blue petals, iridescent, a faint glow of its own, the
  mottling alive as a cuttlefish's skin; a fifth of the hulls red-based (the look's second colouring);
* ``shadow``: seamless, the blackest skin: big slow cells, their seams raised ridges with a faint violet in them, each
  cell between the ridges a pool of glossy black liquid drawn up at its edges;
* the hexagonal looks: semi-organic (Q47), an organic shape plated with the hexagonal grid (Q45), a hint of sheen and soft
  mottling. Their colours are a set a hull (:class:`HexColours`, :func:`hex_style`): ``minbari`` blue to dark blue,
  ``white_star`` silver veined with violet, ``victory`` charcoal with dull red markings. A hull task hands its own set.

The sheens are the maintainer's picks from the stage 1 look sheet (2026-11-21). Colours are linear RGB, from the show's
stills (docs/design-references.md).
"""

from __future__ import annotations

from dataclasses import dataclass

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
VORLON_RED: RGB = (0.17, 0.062, 0.03)  # the red-based hulls' copper-brown (the show's heavy cruiser, still 01)
_VORLON_IRI = sh_from_lobes((0.30, 0.42, 0.10), [((0.0, 1.0, 0.0), (0.35, 0.20, -0.05), 100.0), ((0.0, -1.0, 0.2), (-0.20, -0.10, 0.55), 110.0),
                                                 ((1.0, 0.0, -0.4), (0.25, -0.25, 0.35), 90.0), ((-1.0, 0.0, -0.4), (-0.15, 0.20, 0.30), 90.0)])
_VORLON_RED_IRI = sh_from_lobes((0.30, 0.13, 0.065), [((0.0, 1.0, 0.0), (0.22, 0.12, 0.02), 100.0), ((0.0, -1.0, 0.2), (-0.06, -0.05, 0.14), 110.0),
                                                      ((1.0, 0.0, -0.4), (0.10, -0.02, 0.08), 90.0), ((-1.0, 0.0, -0.4), (0.06, 0.07, 0.0), 90.0)])
# Bold dark mottling with soft edges that swells and fades patch by patch, small spots opening and closing between the
# blotches, a green-gold to violet iridescence that wanders in slow waves, a faint breathing glow in the blotches' veins.
# A fifth of the hulls are red-based (Q: the maintainer, 2026-11-21), with the same mottling.
VORLON = Sheen(iri_sh=_VORLON_IRI, iri_strength=0.6, iri_base=0.08, iri_power=2.5, iri_view=0.7, iri_metal=0.5, iri_wave=0.6, iri_wave_s=28.0,
               pattern_scale_m=5.0, pattern_cells=0.0, pattern_edge=0.7, pattern_cover=0.45, pattern_dark=0.93, pattern_tint=(0.006, 0.008, 0.005),
               pattern_iri=1.0, pattern_rough=0.15, pattern_spots=0.85, pattern_pulse=0.8, pattern_pulse_s=16.0,
               glow_colour=(0.55, 1.0, 0.35), glow_energy=0.035, glow_veins=0.7, glow_rim=0.5, glow_pulse_s=9.0, glow_pulse=0.35, coat=0.6,
               variant_share=0.2, variant_tint=_gain(VORLON_RED, VORLON_SKIN), variant_sh=_VORLON_RED_IRI, variant_glow=(0.9, 0.45, 0.2))

# --- the Shadows: the blackest skin, big slow cells; the seams are ridges, each cell a dished pool of black liquid -------------
_SHADOW_IRI = sh_from_lobes((0.16, 0.05, 0.34), [((0.0, 1.0, 0.0), (-0.06, 0.03, 0.14), 110.0), ((0.0, -1.0, 0.0), (0.12, -0.02, -0.05), 110.0)])
# The seams (the pattern's ink) are matt ridges, a shade off black, with a faint violet glow and a little of the sheen's violet.
SHADOW = Sheen(iri_sh=_SHADOW_IRI, iri_strength=0.14, iri_base=0.0, iri_power=4.0, iri_view=0.8, iri_metal=0.3,
               pattern_scale_m=4.0, pattern_cells=1.0, pattern_edge=0.6, pattern_cover=0.22, pattern_dark=0.5, pattern_tint=(0.012, 0.01, 0.02),
               pattern_iri=0.0, pattern_rough=0.25, pattern_speed_mps=0.15, pattern_relief=0.55,
               liquid=1.0, liquid_flow_mps=0.4, liquid_dish=0.8, liquid_tint=(0.0, 0.0, 0.0),
               glow_colour=(0.45, 0.2, 1.0), glow_energy=0.008, glow_veins=1.0, coat=0.0)


# --- semi-organic, hexagonal plating: a hint of sheen at the rim and soft mottling, in each hull's own colours -----------------
@dataclass(frozen=True)
class HexColours:
    """A hexagon-plated hull's colour set (linear RGB): ``skin`` the body's paint, ``limbs`` and ``accent`` its darker
    parts' (roles ``hull_dark`` and ``hull_panel``); ``mottle`` the colour of its soft mottling, ``mottle_cover`` the share
    of the skin it takes, ``mottle_m`` a blotch's size and ``mottle_edge`` how hard its edge is; ``sheen``, ``sheen_up``
    and ``sheen_down`` the rim sheen's colour, and what it adds seen from above and from below."""

    name: str
    skin: RGB
    limbs: RGB
    accent: RGB
    mottle: RGB
    sheen: RGB
    sheen_up: RGB
    sheen_down: RGB
    mottle_cover: float = 0.45
    mottle_dark: float = 0.75
    mottle_m: float = 9.0
    mottle_edge: float = 0.4
    metallic: float = 0.5
    roughness: float = 0.4


# The Minbari: blue to dark blue (the Sharlin's, the Nial's and the flyer's stills).
MINBARI = HexColours("minbari", skin=(0.07, 0.17, 0.45), limbs=(0.045, 0.11, 0.33), accent=(0.035, 0.09, 0.30), mottle=(0.008, 0.025, 0.12),
                     sheen=(0.10, 0.28, 0.70), sheen_up=(0.06, 0.26, 0.20), sheen_down=(-0.05, -0.12, 0.05), mottle_dark=0.8)
# The White Star: silver, veined with violet-blue (references/show/m10/isa_whitestar).
WHITE_STAR = HexColours("white_star", skin=(0.42, 0.42, 0.47), limbs=(0.32, 0.32, 0.38), accent=(0.30, 0.28, 0.42), mottle=(0.10, 0.05, 0.40),
                        sheen=(0.42, 0.40, 0.72), sheen_up=(0.15, 0.18, 0.10), sheen_down=(0.05, -0.12, 0.10), mottle_cover=0.5, mottle_dark=0.85,
                        mottle_m=6.0, mottle_edge=0.6, metallic=0.7, roughness=0.35)
# The Victory class: charcoal, with dull red markings (references/show/m10/isa_victory).
VICTORY = HexColours("victory", skin=(0.035, 0.037, 0.043), limbs=(0.028, 0.029, 0.034), accent=(0.05, 0.05, 0.058), mottle=(0.085, 0.018, 0.012),
                     sheen=(0.16, 0.20, 0.28), sheen_up=(0.06, 0.08, 0.10), sheen_down=(0.04, -0.02, -0.03), mottle_cover=0.3, mottle_dark=0.7,
                     mottle_m=12.0, mottle_edge=0.5, metallic=0.6, roughness=0.45)
HEX_COLOURS = {c.name: c for c in (MINBARI, WHITE_STAR, VICTORY)}


def hex_sheen(colours: HexColours) -> Sheen:
    """The hexagonal look's sheen in a hull's colours: a hint of iridescence at the rim only, and soft mottling."""
    return Sheen(iri_sh=sh_from_lobes(colours.sheen, [((0.0, 1.0, 0.0), colours.sheen_up, 110.0), ((0.0, -1.0, 0.0), colours.sheen_down, 110.0)]),
                 iri_strength=0.25, iri_base=0.0, iri_power=4.0, iri_view=0.3, iri_metal=0.6, pattern_scale_m=colours.mottle_m,
                 pattern_cover=colours.mottle_cover, pattern_edge=colours.mottle_edge, pattern_dark=colours.mottle_dark, pattern_tint=colours.mottle)


def hex_style(colours: HexColours, cell_m: float = 5.0) -> CapitalStyle:
    """A hexagon-plated hull's capital style in its own colour set (Q45, Q47): what a Minbari or an Interstellar Alliance
    hull task hands the framework, with hexagons ``cell_m`` across."""
    style = organic_style(f"organic_{colours.name}", colours.skin, colours.limbs, colours.accent, colours.metallic, colours.roughness, paneled=True)
    return CapitalStyle(f"organic_{colours.name}", style, HexGrid(cell_m=cell_m, frames_m=12.0 * cell_m), {"sheen": hex_sheen(colours).to_json()})


_SEAMLESS = {
    "vorlon": (organic_style("organic_vorlon", VORLON_SKIN, (0.24, 0.22, 0.03), (0.02, 0.06, 0.36), 0.35, 0.42), VORLON),
    # The ridges are matt: the gloss is the liquid's, on the cells between them.
    "shadow": (organic_style("organic_shadow", (0.012, 0.012, 0.016), (0.010, 0.010, 0.013), (0.012, 0.012, 0.016), 0.4, 0.72), SHADOW),
}
LOOKS = (*_SEAMLESS, *HEX_COLOURS)


def organic(look: str, variant: bool = False) -> CapitalStyle:
    """The capital style of a look: ``vorlon`` or ``shadow``, or a hexagonal one by its colour set's name (``minbari``,
    ``white_star``, ``victory``). ``variant`` puts every ship in the look's second colouring (the red-based Vorlons), for
    a look sheet; in the game a ship's own name decides."""
    if look not in LOOKS:
        raise ValueError(f"an organic look is one of {LOOKS}")
    if look in HEX_COLOURS:
        if variant:
            raise ValueError(f"the {look} look has no second colouring")
        return hex_style(HEX_COLOURS[look])
    style, sheen = _SEAMLESS[look]
    if variant and sheen.variant_share <= 0.0:
        raise ValueError(f"the {look} look has no second colouring")
    worn = sheen.but(variant_all=1.0) if variant else sheen
    return CapitalStyle(f"organic_{look}" + ("_variant" if variant else ""), style, Seamless(), {"sheen": worn.to_json()})


__all__ = ["HEX_COLOURS", "LOOKS", "MINBARI", "SHADOW", "VICTORY", "VORLON", "WHITE_STAR", "HexColours", "hex_sheen", "hex_style", "organic",
           "organic_style"]
