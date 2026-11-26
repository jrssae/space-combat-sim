"""The Omega-class destroyer's style (M10-T68): the fleet's capital machinery and colours (``styles/ea_capital.py``: the looks' roles,
blue-white engines, lit bays in Babylon 5's grey bay metal), in the Agamemnon pattern instead of a panel mosaic (the maintainer,
2026-11-26, Q98): the Omega's greys wander in tone over big plates, darker patches at three sizes overlap on them, a few low plates
stand proud and fine scratches run over everything (``styles/patch_skin.PatchSkin``). The Agamemnon model's textures (Chris Kuhn's)
are a style reference only; nothing is taken from them.
"""

from __future__ import annotations

import dataclasses
from collections.abc import Mapping

from .capital import CapitalStyle
from .ea_capital import DEFAULT_LOOK, LOOKS, SOFT_PAINT, bay_metal_materials, capital_style
from .patch_skin import Patches, PatchSkin

PREFIX = "eao"
# The Agamemnon's manner in the stills' plating: big plates a little apart in tone, then patches a shade or two darker at three sizes
# (the textures' large blocks, their mid tiles and the small chips), a few proud plates and light scratches.
SKIN = PatchSkin(tone=0.05, patches=(Patches((18.0, 11.0), 0.35, ((0.65, 0.07), (0.35, 0.15))), Patches((6.5, 4.0), 0.3, ((0.7, 0.07), (0.3, 0.14))),
                                     Patches((2.2, 1.4), 0.22, ((1.0, 0.08),))), proud=0.15, scratches=0.3)


def ea_omega(look: str = DEFAULT_LOOK, livery: Mapping[str, int] | None = None) -> CapitalStyle:
    """The Omega's style in one of the fleet's looks (the soft finish's greys where the look has them), any role repainted by
    ``livery``."""
    if look not in LOOKS:
        raise ValueError(f"the Omega has no look {look!r}; it has {sorted(LOOKS)}")
    chosen = LOOKS[look]
    chosen = dataclasses.replace(chosen, paint={**chosen.paint, **SOFT_PAINT.get(look, {})}, plate_tone=SKIN.tone, plate_grime=0.04)
    style = capital_style(chosen, f"ea_omega_{look}", PREFIX, SKIN, livery)
    materials = {**style.style.materials, **bay_metal_materials(PREFIX)}
    extra = {**style.style.extra, "speckle": 0.05, "smudge": 0.08, "bare_metal": 0.04}  # the Asimov's wear, a little less
    return dataclasses.replace(style, style=dataclasses.replace(style.style, materials=materials, extra=extra))


__all__ = ["PREFIX", "SKIN", "ea_omega"]
