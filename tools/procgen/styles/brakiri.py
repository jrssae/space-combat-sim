"""Brakiri design language (docs/design-references.md, "Brakiri Bokmai transport"; docs/assets-civilian.md, "brakiri"):
olive green frame, pale putty green cargo pods, Brakiri yellow on the fins, neck bands,
pod straps and turret trim, cream engine domes in dark metal cups.

Albedos are linear RGB from the written sRGB scheme, confirmed by the maintainer (Q19, Q22, 2026-11-03). Roles the
design leaves open (canopy, barrels, interior) are our choice. The pods use their own role, ``pod``. No panel grid is
painted (the maintainer, 2026-11-04): panel layout comes with the texture pack at the rebase. The turret bolts' green
is a gameplay colour for T21 and T16, not paint.
"""

from __future__ import annotations

import numpy as np

from ..core.color import srgb_to_linear
from ..core.geometry import Material
from . import Style

GLOW_SRGB = 0xFFF0B0  # engine glow, yellow-white: a ShipSpec tint for T16, not paint
BOLT_SRGB = 0x7CFF4F  # the turrets' bright green pulse (Q22, the maintainer chose the value): T21 and T16


def _lin(hex_rgb: int) -> tuple[float, float, float]:
    """Linear RGB of an sRGB ``0xRRGGBB`` value."""
    srgb = np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255], dtype=float) / 255.0
    rr, g, b = (float(v) for v in srgb_to_linear(srgb))
    return (rr, g, b)


HULL_SRGB, HULL_DARK_SRGB = 0x5A6B59, 0x3A4538
POD_SRGB = 0xABAE9A
YELLOW_SRGB = 0xD8B840


BRAKIRI = Style(
    name="brakiri",
    materials={
        "hull": Material("bk_hull", _lin(HULL_SRGB), paneled=True),  # the frame
        "hull_dark": Material("bk_hull_dark", _lin(HULL_DARK_SRGB)),  # recesses, the spindle, sleeves, rails, insets
        "hull_panel": Material("bk_hull_panel", _lin(HULL_SRGB), paneled=True),
        "frame_plain": Material("bk_frame_plain", _lin(HULL_SRGB)),  # the frame's green on the pods (top plate, saddles)
        "pod": Material("bk_pod", _lin(POD_SRGB), paneled=True),  # the cargo pods' plating
        "stripe": Material("bk_stripe", _lin(YELLOW_SRGB)),  # the yellow
        "window": Material("bk_window", _lin(0xE8F0DC)),
        "window_strip": Material("bk_window_strip", _lin(0x1E2620)),
        "engine_dome": Material("bk_engine_dome", _lin(0xF2EDC4)),
        "hazard": Material("bk_hazard", _lin(YELLOW_SRGB)),
        "hazard_dark": Material("bk_hazard_dark", _lin(HULL_DARK_SRGB)),
        "canopy_glass": Material("bk_canopy", _lin(0x1E2620)),
        "canopy_frame": Material("bk_canopy_frame", _lin(HULL_DARK_SRGB), metallic=0.5),
        "nozzle": Material("bk_nozzle", _lin(0x2E3530), metallic=0.8),  # the nacelle cups
        "nozzle_throat": Material("bk_nozzle_throat", _lin(0x121512), metallic=0.8),
        "barrel": Material("bk_barrel", _lin(0x2E3530), metallic=0.7),
        "bore": Material("bk_bore", _lin(0x101210)),
        "interior": Material("bk_interior", _lin(0x101210)),
        "rcs": Material("bk_rcs", _lin(HULL_DARK_SRGB), metallic=0.6),
    },
    panel_size_m=2.4,
    panel_line_width_m=0.25,
    panel_line_darkness=1.0,  # no painted grid (the maintainer, 2026-11-04): panels come with the texture pack
    panel_tint_jitter=0.0,
)

# The pods' own style over the same roles (its grid size stays for the texture pack's panel scale).
BRAKIRI_POD = Style(
    name="brakiri_pod",
    materials=BRAKIRI.materials,
    panel_size_m=2.0,
    panel_line_width_m=0.25,
    panel_line_darkness=1.0,
    panel_tint_jitter=0.0,
)
