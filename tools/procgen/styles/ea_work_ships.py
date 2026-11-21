"""The looks of the Earth Alliance's working ships: the Panama-class transport and the construction tender (M10-T51 and
M10-T55; docs/assets-civilian.md, "`ea_panama` and `ea_construction_tender`").

Both wear the ``ea_civilian`` language (``styles/ea_civilian.py``): plates of mixed size with fine seams, edges worn to
primer. A :class:`WorkLook` adds the paint over it. The maintainer chose both from A/B/C sheets (2026-11-21); colours are
sRGB read off the stills in ``references/show/m10/`` (gitignored).

Panama: the still in open space, a warm brown-grey patchwork that wanders strongly from plate to plate, a pale roof and
keel, dark tanks.
Construction tender: the still's work pods, yellow ochre all over with grey machinery, the claws yellow striped black.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

from . import Style
from .ea_civilian import ea_civilian
from .ea_shuttle import Look

ENGINE_GLOW_PANAMA = 0xFFC8A0  # the warm white of the transport's two bells
ENGINE_GLOW_TENDER = 0xBFD8FF  # the cold blue-white of the work pods' thrusters
STRIPE_DARK = 0x1E1E1E


@dataclass(frozen=True)
class WorkLook(Look):
    """A working ship's surface: the style and its bands (:class:`Look`), then ``stripes``, the colour of the hazard stripes
    across the tender's claws and round its pods (``None``: none)."""

    stripes: int | None = None


def _style(name: str, paint: dict[str, int], glow: int, panel_m: float, **wear: float) -> Style:
    """The EA civilian pack repainted, its panels sized for the hull."""
    return replace(ea_civilian(paint, glow), name=name, panel_size_m=panel_m, **wear)


PANAMA_LOOK = WorkLook(
    _style("ea_panama", {"hull": 0x8A7F72, "hull_panel": 0x6E655C, "hull_patch": 0xB5AB9B, "hull_dark": 0x3D3835, "hazard": 0x5C5650},
           ENGINE_GLOW_PANAMA, 1.6, edge_wear=0.5, grime=0.14, streaks=0.26),
    plate_tone=0.17, plate_grime=0.16,
)  # fmt: skip
TENDER_LOOK = WorkLook(
    _style("ea_construction_tender", {"hull": 0xC29A2C, "hull_panel": 0xA5852A, "hull_dark": 0x45464A, "hazard": 0xD6AE2A, "band_light": 0xB9BBB8},
           ENGINE_GLOW_TENDER, 0.9, edge_wear=0.55, grime=0.14, streaks=0.22),
    plate_tone=0.1, plate_grime=0.16, stripes=STRIPE_DARK,
)  # fmt: skip
