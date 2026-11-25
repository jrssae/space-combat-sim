"""``centauri_shuttle``: the Centauri shuttle, 36 m long and 52 m across (M10-T58; docs/assets-civilian.md and
docs/design-references.md, "Centauri shuttle").

Composition only: the pieces of ``parts/centauri_shuttle.py`` in one of the looks of ``styles/centauri_shuttle.py``, through
the shuttles' shared build (``assets/ea_shuttles.py``, ``build_craft``): one textured mesh with a full and a low texture
set, the break-up chunks, ``hardpoints.json`` and the manifest. A small craft by the class budgets (M10 Q38), unarmed.

Option ``look`` (``a``, ``b`` or ``c``) picks the surface option.
"""

from __future__ import annotations

from dataclasses import replace

import numpy as np

from ..core import civilian as cv
from ..core.context import AssetOutputs, BuildContext
from ..core.seams import FULL, MAJOR, PLATING, PatchPlates, SeamLayout
from ..parts import Part
from ..parts import centauri_shuttle as cp
from ..styles.centauri_shuttle import DEFAULT_OPTION, Look, looks
from .ea_shuttles import NAV_CLEARANCE_M, Craft, Port, build_craft, no_docks

ASSET_ID = "centauri_shuttle"
UP, DOWN, OUT = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0)


def dress(pieces: list[cv.Piece], look: Look) -> tuple[list[cv.Piece], dict]:
    """No seams: the solid paint with its darker patches at each of the look's sizes (Q83), the largest kept in the low set."""
    features = []
    for k, layer in enumerate(look.patches):
        level = MAJOR if k == 0 else (FULL if k == 1 else PLATING)
        features.append(PatchPlates(level=level, wrap="sides", cell=layer.cell, splits=3, min_m=0.25 * min(layer.cell), keep=0.3,
                                    scatter=layer.scatter, inset_m=0.0, tiers=layer.tiers, seed=811 + 37 * k))
    layout = SeamLayout.of(features)
    return [cv.Piece(p.part.with_seams(layout), p.solid, p.side, p.fine) for p in pieces], {}


def ports(by_name: dict[str, Part]) -> list[Port]:
    """Cosmetic RCS (authored frame; ``r_`` names are mirrored): at the nose, the body's aft corners and the wing tips."""
    tip = by_name["wing_r"].anchor("tip").position
    return [
        ("r_nose", (2.0, -2.25, 2.0), OUT),
        ("nose_up", (0.0, cp.deck_y(0.0, 4.0), 4.0), UP),
        ("nose_down", (0.0, -2.9, 4.0), DOWN),
        ("r_corner", (14.9, -2.0, 32.5), OUT),
        ("r_tip_up", tip + np.array([-0.2, 0.15, 0.0]), UP),
        ("r_tip_down", tip + np.array([-0.2, -0.15, 0.0]), DOWN),
    ]


def lights(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Running lights at the wing tips, white on the spine's crown aft, the cabin glow behind the canopy."""
    top = by_name["spine"].anchor("top").position
    return {"starboard": by_name["wing_r"].anchor("tip").position + np.array([NAV_CLEARANCE_M, 0.0, 0.0]),
            "top": top + np.array([0.0, NAV_CLEARANCE_M, 0.0]), "top_lamp": top + np.array([0.0, 2.0, 0.0]), "cabin": np.array(cp.EYE)}


def joints(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Where each chunk breaks away: the body at its middle, the stern at the louvres, a wing at its root."""
    wing = by_name["wing_r"].anchor("joint").position
    return {"body": np.array([0.0, -1.5, 18.0]), "stern": np.array([0.0, -2.3, 32.0]), "wing_r": wing, "wing_l": wing * np.array([-1.0, 1.0, 1.0])}


CRAFT = Craft(ASSET_ID, 0.25, ("body", "stern", "wing_l", "wing_r"), looks()[DEFAULT_OPTION], cp.assemble, dress, cp.NOZZLE_Y,
              (("l", "left", "engine_l", cp.NOZZLE_EXIT_R), ("r", "right", "engine_r", cp.NOZZLE_EXIT_R)), 0.0,
              (1.2, cp.NOSE_Y, 1.0, 0.3), ports, lights, joints, no_docks)  # fmt: skip


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the shuttle into ``ctx.out_dir``; option ``look`` picks the surface option, the rest as ``build_craft``."""
    options = looks()
    option = str(ctx.option("look", DEFAULT_OPTION))
    if option not in options:
        raise ValueError(f"{ASSET_ID} has no look {option!r} (one of {sorted(options)})")
    return build_craft(replace(CRAFT, look=options[option]), ctx)
