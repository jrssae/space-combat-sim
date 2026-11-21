"""The looks of the Earth Alliance's working ships: the Panama-class transport and the construction tender (M10-T51 and
M10-T55; docs/assets-civilian.md, "`ea_panama` and `ea_construction_tender`").

Both wear the ``ea_civilian`` language (``styles/ea_civilian.py``): plates of mixed size with fine seams, edges worn to
primer. A :class:`WorkLook` adds the paint over it. Each hull has three surface options (``a``, ``b``, ``c``) for the
maintainer to choose from; colours are sRGB read off the stills in ``references/show/m10/`` (gitignored).

Panama: the stills show a dark grey hull with a lighter roof and tan tanks (in the docking bay), a brown-grey patchwork
(in space) and a near-black hull edged in red (docked).
Construction tender: the still shows work pods in yellow ochre with grey machinery; the claws take hazard stripes.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

from . import Style
from .ea_civilian import ea_civilian
from .ea_shuttle import Look

OPTIONS: tuple[str, ...] = ("a", "b", "c")
DEFAULT_OPTION = "a"
ENGINE_GLOW_PANAMA = 0xFFC8A0  # the warm white of the transport's two bells
ENGINE_GLOW_TENDER = 0xBFD8FF  # the cold blue-white of the work pods' thrusters
STRIPE_DARK = 0x1E1E1E


@dataclass(frozen=True)
class WorkLook(Look):
    """A working ship's surface: the style and its bands (:class:`Look`), then ``stripes``, the colour of the hazard stripes
    across the tender's claws and round its pods (``None``: none), and ``trim``, the colour of the Panama's thin lines along
    its tubes and edge (``None``: none)."""

    name: str = ""
    stripes: int | None = None
    trim: int | None = None


def _style(name: str, paint: dict[str, int], glow: int, panel_m: float, **wear: float) -> Style:
    """The EA civilian pack repainted, its panels sized for the hull."""
    return replace(ea_civilian(paint, glow), name=name, panel_size_m=panel_m, **wear)


def panama_looks() -> dict[str, WorkLook]:
    """The Panama's three options."""
    return {
        # The docking-bay stills: dark grey, a lighter roof slab, tan tanks, small red and white lights.
        "a": WorkLook(_style("ea_panama_a", {"hull": 0x6B6E72, "hull_panel": 0x54575B, "hull_patch": 0x9A9C99, "hull_dark": 0x35373A, "hazard": 0xB08A5A},
                             ENGINE_GLOW_PANAMA, 1.6, edge_wear=0.4, grime=0.1, streaks=0.2),
                      name="a", plate_tone=0.09, plate_grime=0.12),
        # The still in open space: a warm brown-grey patchwork, strong from plate to plate, with pale panels and dark tanks.
        "b": WorkLook(_style("ea_panama_b", {"hull": 0x8A7F72, "hull_panel": 0x6E655C, "hull_patch": 0xB5AB9B, "hull_dark": 0x3D3835, "hazard": 0x5C5650},
                             ENGINE_GLOW_PANAMA, 1.6, edge_wear=0.5, grime=0.14, streaks=0.26),
                      name="b", plate_tone=0.17, plate_grime=0.16),
        # The docked stills: near-black plating edged in red, grey tanks, a red band at each end of the hold.
        "c": WorkLook(_style("ea_panama_c", {"hull": 0x4A4C50, "hull_panel": 0x3A3C40, "hull_patch": 0x5E6064, "hull_dark": 0x26272A, "hazard": 0x8C8F92},
                             ENGINE_GLOW_PANAMA, 1.6, edge_wear=0.45, grime=0.08, streaks=0.16),
                      name="c", plate_tone=0.07, plate_grime=0.1, bands=((45.5, 2.2, 0xA8241E), (149.0, 2.2, 0xA8241E)), trim=0xB0281F),
    }  # fmt: skip


def tender_looks() -> dict[str, WorkLook]:
    """The construction tender's three options."""
    return {
        # The still: yellow ochre all over, grey machinery, yellow claws striped black.
        "a": WorkLook(_style("ea_tender_a", {"hull": 0xC29A2C, "hull_panel": 0xA5852A, "hull_dark": 0x45464A, "hazard": 0xD6AE2A, "band_light": 0xB9BBB8},
                             ENGINE_GLOW_TENDER, 0.9, edge_wear=0.55, grime=0.14, streaks=0.22),
                      name="a", plate_tone=0.1, plate_grime=0.16, stripes=STRIPE_DARK),
        # The fleet's grey with yellow tools: grey body and pods, yellow claws and grabs striped black, pale tanks.
        "b": WorkLook(_style("ea_tender_b", {"hull": 0x9A9C9E, "hull_panel": 0x808386, "hull_dark": 0x4F5256, "hazard": 0xD6AE2A, "band_light": 0xD8D9D6},
                             ENGINE_GLOW_TENDER, 0.9, edge_wear=0.4, grime=0.09, streaks=0.16),
                      name="b", plate_tone=0.07, plate_grime=0.1, stripes=STRIPE_DARK),
        # A worn orange work craft: rust orange body, dark machinery and claws, white tanks, no stripes.
        "c": WorkLook(_style("ea_tender_c", {"hull": 0xB5672A, "hull_panel": 0x8C5226, "hull_dark": 0x3A3B3E, "hazard": 0x4A4B4E, "band_light": 0xD8D8D2},
                             ENGINE_GLOW_TENDER, 0.9, edge_wear=0.65, grime=0.18, streaks=0.3),
                      name="c", plate_tone=0.13, plate_grime=0.2),
    }  # fmt: skip
