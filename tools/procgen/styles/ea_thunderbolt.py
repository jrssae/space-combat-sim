"""The Thunderbolt's looks (M10-T50): the Starfury's Earthforce fighter finish, repainted from the show's stills.

Stage 1 offers three for the maintainer's choice (``--option look=a|b|c``):

* ``a`` show white: the pale grey-white hull of the show's Thunderbolts, dark seams, red bands across the wings, the pods
  and the fins, a black anti-glare strip ahead of the windscreen;
* ``b`` fleet grey: the Starfury's weathered blue-grey, unmarked, so a wing's livery is all the colour it carries;
* ``c`` squadron art: the white hull two-toned with grey panels, the red bands, a red nose cap and a shark's mouth on the
  chin, as the still of the Thunderbolt with nose art shows.

Colours are sRGB as the stills show them lit; ``capture_albedo`` turns them into the paint that shows them in the game.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

from ..core.color import capture_albedo
from . import Style
from .earthforce import EARTHFORCE_FIGHTER

RED = 0xB42A20
BLACK = 0x1B1C1F
TEETH = 0xE6E4DC
MOUTH = 0x7A1612


@dataclass(frozen=True)
class Look:
    """A look: the style, then what is painted over it. ``band`` is the colour of the bands across wings, pods and fins
    (``None``: none), ``plate_tone`` how far plate to plate the paint's value wanders."""

    key: str
    title: str
    style: Style
    band: int | None = None
    anti_glare: bool = False
    nose_cap: bool = False
    nose_art: bool = False
    plate_tone: float = 0.06


CABIN_GLOW = 0.012  # the long canopy shows far more glass than the Starfury's window, so its red cabin light is dimmer


def _repainted(name: str, paint: dict[str, int], **wear: float) -> Style:
    """The Earthforce fighter finish with other paint: names and finishes stay, so the maps, the bare metal and a wing's
    livery work as on the Starfury."""
    materials = dict(EARTHFORCE_FIGHTER.materials)
    materials["canopy_glass"] = replace(materials["canopy_glass"], emissive_strength=CABIN_GLOW)
    materials["interior"] = replace(materials["interior"], emissive_strength=CABIN_GLOW)
    for role, colour in paint.items():
        materials[role] = replace(materials[role], albedo=capture_albedo(colour))
    for role, source in (("bare", "hull"), ("bare_trim", "hull_panel")):
        materials[role] = replace(materials[role], albedo=EARTHFORCE_FIGHTER.materials[source].albedo)
    return replace(EARTHFORCE_FIGHTER, name=name, materials=materials, **wear)


LOOKS: dict[str, Look] = {
    "a": Look("a", "A: show white, red bands",
              _repainted("ea_thunderbolt_white", {"hull": 0xC6CACE, "hull_panel": 0xA4A9B0, "hull_dark": 0x50545A, "stripe": RED},
                         panel_line_darkness=0.45, streaks=0.3, grime=0.08, edge_wear=0.4),
              band=RED, anti_glare=True),
    "b": Look("b", "B: fleet grey, as the Starfury", _repainted("ea_thunderbolt_grey", {})),
    "c": Look("c", "C: two-tone white, nose art",
              _repainted("ea_thunderbolt_art", {"hull": 0xD0D2D4, "hull_panel": 0x7F868F, "hull_dark": 0x45484E, "stripe": RED},
                         panel_line_darkness=0.4, streaks=0.36, grime=0.1, edge_wear=0.5),
              band=RED, anti_glare=True, nose_cap=True, nose_art=True, plate_tone=0.1),
}  # fmt: skip
DEFAULT_LOOK = "a"
