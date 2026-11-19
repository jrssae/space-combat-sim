"""The raider capitals' paint (M12-T19; docs/assets-capital.md, "Surface"): the strike carrier's surface, a style and the numbers
its plating is drawn with. The maintainer chose it from three candidates on 2026-11-15 ("show green").

Read off the show's still of the strike carrier, the raiders' Delta-V and the fan render of the raider base (all in the
untracked ``references/``; nothing of them is copied): the still's dark green flanks under grey plated decks, lit pale slats,
dark olive structure, the raiders' ochre on the cradle pads. Big plates, clean paint, light wear.

Albedos are linear RGB from sRGB values, kept in the Starfury's and the Delta-V's range: the raider's first paint read black on
the GPU (docs/assets-raider.md).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ..core.color import srgb_to_linear
from ..core.geometry import Material
from . import Style


def _lin(hex_rgb: int) -> tuple[float, float, float]:
    """Linear RGB of an sRGB ``0xRRGGBB`` value."""
    srgb = np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255], dtype=float) / 255.0
    r, g, b = (float(v) for v in srgb_to_linear(srgb))
    return (r, g, b)


@dataclass(frozen=True)
class Surface:
    """A surface: its paint and how its plating is drawn (``parts/layouts.py``, ``raider_carrier``). ``plate_m`` is the
    field the plates are cut from, ``splits`` how often it is cut, ``tone`` the plate to plate value change, ``frames_m`` the
    pitch of the full set's frame lines."""

    key: str
    title: str
    style: Style
    plate_m: tuple[float, float]
    splits: int
    tone: float
    grime: float
    sheen: float
    hatches: float
    frames_m: float


def _style(name: str, hull: int, deck: int, dark: int, pad: int, clamp: int, slat: int, slat_glow: float, wear: dict[str, float],
           **kw: float) -> Style:
    prefix = f"rc{name}"
    glow = _lin(slat)
    return Style(
        name=f"raider_capital_{name}",
        materials={
            "hull": Material(f"{prefix}_hull", _lin(hull), paneled=True),  # the boxes' flanks, the drum, the rings' bands
            "hull_panel": Material(f"{prefix}_deck", _lin(deck), paneled=True),  # the decks, the slab, the pads, the tanks
            "hull_dark": Material(f"{prefix}_dark", _lin(dark), paneled=True),  # structure: rings, arms, beams, recess walls
            "stripe": Material(f"{prefix}_stripe", _lin(pad), paneled=True),
            "hazard": Material(f"{prefix}_slat", _lin(slat), emissive=glow, emissive_strength=slat_glow),  # the lit slats' floors
            "hazard_dark": Material(f"{prefix}_hazard_dark", _lin(0x1C1A18)),
            "canopy_glass": Material(f"{prefix}_canopy", (0.006, 0.007, 0.009)),
            "canopy_frame": Material(f"{prefix}_canopy_frame", _lin(dark), metallic=0.5),
            "nozzle": Material(f"{prefix}_nozzle", _lin(0x46413D), metallic=0.8),
            "nozzle_throat": Material(f"{prefix}_nozzle_throat", _lin(0x0E0D0C), metallic=0.8, roughness=0.45, emissive=(1.0, 0.86, 0.58),
                                      emissive_strength=4.0),  # the raiders' yellow-white engine glow
            "barrel": Material(f"{prefix}_barrel", _lin(0x57534D), metallic=0.7),  # the bow spikes
            "bore": Material(f"{prefix}_bore", (0.01, 0.01, 0.01)),
            "interior": Material(f"{prefix}_interior", (0.012, 0.013, 0.012)),  # the hangar mouth
            "rcs": Material(f"{prefix}_clamp", _lin(clamp), metallic=0.6),  # clamp pins, pipes
        },
        panel_size_m=0.5,
        panel_line_width_m=0.035,
        extra=wear,
        **kw,
    )


# The lit slats are a soft pale green, weak enough that the bloom keeps their posts visible; the decks are a dark grey so a
# square-on sun does not wash them out (both tuned on the first look sheet, docs/assets-capital.md).
SURFACE = Surface(
    "a", "show green",
    _style("a", hull=0x3E5647, deck=0x4A504B, dark=0x3B4239, pad=0x8C6A32, clamp=0x4E4B45, slat=0x9CA894, slat_glow=0.35,
           wear={"bare_metal": 0.25, "smudge": 0.15, "smudge_scale_m": 0.6, "speckle": 0.04, "paint_roughness": 0.72, "streak_length_m": 0.35},
           panel_line_darkness=0.6, panel_tint_jitter=0.06, edge_wear=0.3, streaks=0.14, grime=0.06),
    plate_m=(9.0, 6.0), splits=2, tone=0.07, grime=0.05, sheen=0.06, hatches=0.06, frames_m=7.5,
)

__all__ = ["SURFACE", "Surface"]
