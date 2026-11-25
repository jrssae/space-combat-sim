"""``minbari_flyer``: the Minbari Flyer, a diplomatic transport 40 m long (M10-T58, Q67; docs/assets-civilian.md and
docs/design-references.md, "Minbari Flyer").

Composition only: the pieces of ``parts/minbari_flyer.py`` in one of the looks of ``styles/minbari_flyer.py``, through the
shuttles' shared build (``assets/ea_shuttles.py``, ``build_craft``). The skin is the Minbari's hexagonal grid (Q45) under
the show's long streaks. A small craft by the class budgets (M10 Q38), unarmed.

Option ``look`` (``a``, ``b`` or ``c``) picks the surface option.
"""

from __future__ import annotations

import functools
from dataclasses import replace

import numpy as np

from ..core import civilian as cv
from ..core.color import capture_albedo
from ..core.context import AssetOutputs, BuildContext
from ..core.seams import FULL, MAJOR, Hexes, SeamLayout
from ..core.textures import Marking
from ..parts import Part
from ..parts import minbari_flyer as mp
from ..styles.minbari_flyer import DEFAULT_OPTION, Look, looks
from .ea_shuttles import NAV_CLEARANCE_M, Craft, Port, build_craft, no_docks

ASSET_ID = "minbari_flyer"
UP, DOWN, OUT = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0)
PAINTED = ("body", "pod_r", "pod_l", "blade_r", "blade_l", "spindle_r", "spindle_l", "waist_r", "waist_l")


def _streaks(points: np.ndarray, normals: np.ndarray, phase: float, share: float) -> np.ndarray:
    """Where one streak colour lies: soft bands drawn out along the hull, a few metres long and a hand's width across."""
    p = np.asarray(points, dtype=float)
    across = np.arctan2(p[:, 1], np.abs(p[:, 0]) + 0.5)
    wave = (np.sin(2.3 * across * 3.0 + 0.9 * np.abs(p[:, 0]) + phase) * np.sin(0.35 * p[:, 2] + 1.3 * phase)
            + 0.4 * np.sin(0.17 * p[:, 2] - 4.1 * across + 2.1 * phase))  # fmt: skip
    return np.clip((wave - (1.0 - 2.0 * share)) / 0.15, 0.0, 1.0)


def dress(pieces: list[cv.Piece], look: Look) -> tuple[list[cv.Piece], dict[str, tuple[Marking, ...]]]:
    """The hexagonal grid (Q45): each cell's shade kept in the low set, its seams in the full one; then the look's streaks."""
    layout = SeamLayout.of([Hexes(level=MAJOR, cell_m=look.hex_m, tone=look.hex_tone, sheen=0.06, depth=0.0, dark=0.0, seed=907),
                            Hexes(level=FULL, cell_m=look.hex_m, tone=0.0, sheen=0.0, width=1.5, seed=907)])
    dressed = [cv.Piece(p.part.with_seams(layout), p.solid, p.side, p.fine) for p in pieces]
    marks: dict[str, list[Marking]] = {name: [] for name in PAINTED}
    for k, (colour, share) in enumerate(look.streaks):
        cover = functools.partial(_streaks, phase=0.7 + 2.3 * k, share=share)
        for name in PAINTED:
            marks[name].append(Marking.paint(name, capture_albedo(colour), cover))
    return dressed, {name: tuple(m) for name, m in marks.items()}


def ports(by_name: dict[str, Part]) -> list[Port]:
    """Cosmetic RCS (authored frame; ``r_`` names are mirrored): on the bow blades, the spindles and the fuselage's crown."""
    return [
        ("r_blade", (8.45, 0.0, 9.0), OUT),
        ("r_spindle", (mp.SPINDLE_X + 0.93, 0.0, 32.5), OUT),
        ("r_blade_up", (8.15, 4.0, 4.0), UP),
        ("r_blade_down", (8.15, -4.0, 4.0), DOWN),
        ("r_spindle_up", (mp.SPINDLE_X, 3.6, 32.0), UP),
        ("r_spindle_down", (mp.SPINDLE_X, -3.6, 32.0), DOWN),
    ]


def lights(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Running lights on the spindles' flanks, white on the fuselage's crown, the cabin glow in the bow."""
    top = by_name["body"].anchor("top").position
    return {"starboard": by_name["spindle_r"].anchor("tip").position + np.array([NAV_CLEARANCE_M, 0.0, 0.0]),
            "top": top + np.array([0.0, NAV_CLEARANCE_M, 0.0]), "top_lamp": top + np.array([0.0, 2.0, 0.0]), "cabin": np.array(mp.EYE)}


def joints(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Where each chunk breaks away: the bow's pods and blades at their webs, the tail at the waist, the crossbar at the
    fuselage, a spindle at its root."""
    spindle = np.array([mp.SPINDLE_X, 0.0, 32.0])
    return {"body": np.array([0.0, 0.0, 10.0]), "bow": np.array([0.0, 0.0, 8.0]), "tail": np.array([0.0, 0.0, 26.0]),
            "crossbar": np.array([0.0, 0.0, 32.4]), "spindle_r": spindle, "spindle_l": spindle * np.array([-1.0, 1.0, 1.0])}


CRAFT = Craft(ASSET_ID, 0.25, ("body", "bow", "tail", "crossbar", "spindle_l", "spindle_r"), looks()[DEFAULT_OPTION], mp.assemble, dress,
              0.0, (("l", "left", "spindle_l", 0.3), ("r", "right", "spindle_r", 0.3)), 0.0, (1.0, 0.0, 1.0, 0.3), ports, lights, joints,
              no_docks)  # fmt: skip


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the Flyer into ``ctx.out_dir``; option ``look`` picks the surface option, the rest as ``build_craft``."""
    options = looks()
    option = str(ctx.option("look", DEFAULT_OPTION))
    if option not in options:
        raise ValueError(f"{ASSET_ID} has no look {option!r} (one of {sorted(options)})")
    return build_craft(replace(CRAFT, look=options[option]), ctx)
