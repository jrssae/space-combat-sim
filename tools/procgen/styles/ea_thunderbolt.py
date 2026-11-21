"""The Thunderbolt's look (M10-T50): the Starfury's Earthforce fighter finish, repainted from the show's stills.

The maintainer chose it from three (2026-11-20): the pale grey-white hull of the show's Thunderbolts with dark seams, red
bands across the wings, the pods and the fin tips, and a black anti-glare strip ahead of the windscreen. A wing's livery
(``core/livery.py``) paints over it as it does over the Starfury. Colours are sRGB as the stills show them lit;
``capture_albedo`` turns them into the paint that shows them in the game.
"""

from __future__ import annotations

from dataclasses import replace

from ..core.color import capture_albedo
from . import Style
from .earthforce import EARTHFORCE_FIGHTER

BAND = 0xB42A20  # the red of the bands
ANTI_GLARE = 0x1B1C1F
PAINT = {"hull": 0xC6CACE, "hull_panel": 0xA4A9B0, "hull_dark": 0x50545A, "stripe": BAND}
PLATE_TONE = 0.06  # how far plate to plate the paint's value wanders
CABIN_GLOW = 0.012  # the long canopy shows far more glass than the Starfury's window, so its red cabin light is dimmer


def _repainted() -> Style:
    """The Earthforce fighter finish in the Thunderbolt's paint: names and finishes stay, so the maps, the bare metal and
    a wing's livery work as on the Starfury."""
    materials = dict(EARTHFORCE_FIGHTER.materials)
    for role in ("canopy_glass", "interior"):
        materials[role] = replace(materials[role], emissive_strength=CABIN_GLOW)
    for role, colour in PAINT.items():
        materials[role] = replace(materials[role], albedo=capture_albedo(colour))
    return replace(EARTHFORCE_FIGHTER, name="ea_thunderbolt", materials=materials, panel_line_darkness=0.45, streaks=0.3, grime=0.08,
                   edge_wear=0.4)


THUNDERBOLT = _repainted()
