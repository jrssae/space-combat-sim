"""The Earth Alliance shuttles' looks (M10-T57; docs/assets-civilian.md, "EA shuttle and EA atmospheric shuttle").

Both craft wear the ``ea_civilian`` language (``styles/ea_civilian.py``) at a small craft's scale: fine seams, plates of
mixed size, edges worn to primer. A :class:`Look` adds what the show paints on top: the bands round the hull and a hull
number. The maintainer chose both from A/B/C sheets (2026-11-20); colours are sRGB read off the stills in
``references/show/m10/`` (gitignored).

EA shuttle: a worn, darker grey with a green nose band, the craft numbered 03.
EA atmospheric shuttle: the fleet's cool grey with one red band between two thin off-white ones.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

from . import Style
from .ea_civilian import ea_civilian

ENGINE_GLOW_SPACE = 0xFFB89A  # the warm red-white of the shuttle's stern panels
ENGINE_GLOW_ATMO = 0xFFB060  # the orange of the atmospheric shuttle's exhaust


@dataclass(frozen=True)
class Look:
    """A craft's surface: the style, then the paint over it. ``bands`` are ``(z, width, sRGB)`` rings round the hull from
    ``z`` aft; ``plate_tone`` is how far plate to plate the paint's value wanders, ``plate_grime`` the dirt at plate edges."""

    style: Style
    bands: tuple[tuple[float, float, int], ...] = ()
    number: str = ""
    number_colour: int = 0xE8E8E8
    plate_tone: float = 0.07
    plate_grime: float = 0.08


def _style(name: str, paint: dict[str, int], glow: int, smudge: float | None = None, **wear: float) -> Style:
    """The EA civilian pack at a small craft's scale, repainted."""
    base = ea_civilian(paint, glow)
    extra = dict(base.extra) if smudge is None else {**base.extra, "smudge": smudge}
    return replace(base, name=name, panel_size_m=0.9, panel_line_width_m=0.03, extra=extra, **wear)


SHUTTLE_LOOK = Look(
    _style("ea_shuttle", {"hull": 0x8D8F8A, "hull_panel": 0x73756F, "hull_dark": 0x3F4144, "stripe": 0x2E8B4E}, ENGINE_GLOW_SPACE,
           smudge=0.22, edge_wear=0.55, grime=0.13, streaks=0.26),
    bands=((1.35, 0.9, 0x2E8B4E),), number="03", number_colour=0x62D0BE, plate_tone=0.12, plate_grime=0.16,
)  # fmt: skip
ATMO_LOOK = Look(
    _style("ea_atmo_shuttle", {"hull": 0xA4A7AA, "hull_panel": 0x8A8D90, "hull_dark": 0x4F5256, "stripe": 0xA8322C}, ENGINE_GLOW_ATMO,
           edge_wear=0.35, grime=0.07, streaks=0.14),
    bands=((4.6, 0.25, 0xDADCDE), (5.2, 0.9, 0xA8322C), (5.8, 0.25, 0xDADCDE)), plate_tone=0.06,
)  # fmt: skip
