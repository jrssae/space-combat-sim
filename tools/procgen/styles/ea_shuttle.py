"""The Earth Alliance shuttles' looks (M10-T57; docs/design-references.md, "EA shuttle" and "EA atmospheric shuttle").

Both craft wear the ``ea_civilian`` language (``styles/ea_civilian.py``) at a small craft's scale: fine seams, plates of
mixed size, edges worn to primer. A :class:`Look` adds what the show paints on top: the bands, a hull number, a
camouflage, the tail's colour. Three looks per craft (``a``, ``b``, ``c``) are kept as the surface options the
maintainer chooses from; colours are sRGB read off the stills in ``references/show/m10/`` (gitignored).

EA shuttle: ``a`` pale grey-white patchwork with a red-orange nose band (the craft numbered 25), ``b`` the fleet's cool
grey with a blue band, ``c`` a darker, grimier grey with a green band.
EA atmospheric shuttle: ``a`` pale grey, heavily stained, two orange-red bands across the back, ``b`` grey and olive
camouflage with a cream tail and orange-red marks, ``c`` the fleet's cool grey with one red band.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

from . import Style
from .ea_civilian import ea_civilian

OPTIONS: tuple[str, ...] = ("a", "b", "c")
DEFAULT_OPTION = "a"
ENGINE_GLOW_SPACE = 0xFFB89A  # the warm red-white of the shuttle's stern panels
ENGINE_GLOW_ATMO = 0xFFB060  # the orange of the atmospheric shuttle's exhaust


@dataclass(frozen=True)
class Look:
    """One surface option: the style, then the paint over it. ``bands`` are ``(z, width, sRGB)`` rings round the hull;
    ``camo`` the colours of the camouflage's blotches; ``tail`` the tail's own colour with ``tail_marks`` on it;
    ``plate_tone`` how far plate to plate the paint's value wanders."""

    name: str
    title: str
    style: Style
    bands: tuple[tuple[float, float, int], ...] = ()
    number: str = ""
    number_colour: int = 0xE8E8E8
    camo: tuple[int, ...] = ()
    tail: int | None = None
    tail_marks: int | None = None
    plate_tone: float = 0.07
    plate_grime: float = 0.08


def _style(name: str, paint: dict[str, int], glow: int, **wear: float) -> Style:
    """The EA civilian pack at a small craft's scale, repainted."""
    base = ea_civilian(paint, glow)
    extra = {**base.extra, **{k: v for k, v in wear.items() if k in ("smudge", "speckle")}}
    fields = {k: v for k, v in wear.items() if k not in ("smudge", "speckle")}
    return replace(base, name=name, panel_size_m=0.9, panel_line_width_m=0.03, extra=extra, **fields)


def shuttle_looks() -> dict[str, Look]:
    """The EA shuttle's three options."""
    return {
        "a": Look("a", "A: show white, red-orange band 25",
                  _style("ea_shuttle_a", {"hull": 0xC6C8C8, "hull_panel": 0xAFB2B4, "hull_dark": 0x5A5D61, "stripe": 0xC2432B},
                         ENGINE_GLOW_SPACE, edge_wear=0.4, grime=0.08, streaks=0.16),
                  bands=((1.35, 0.9, 0xC2432B),), number="25", number_colour=0x52C2BA, plate_tone=0.11),
        "b": Look("b", "B: fleet grey, blue band 18",
                  _style("ea_shuttle_b", {"hull": 0xA4A7AA, "hull_panel": 0x8A8D90, "hull_dark": 0x4F5256, "stripe": 0x2F62C4},
                         ENGINE_GLOW_SPACE, edge_wear=0.35, grime=0.07, streaks=0.14),
                  bands=((1.35, 0.9, 0x2F62C4),), number="18", number_colour=0x9FDCEC, plate_tone=0.06),
        "c": Look("c", "C: worn dark grey, green band 03",
                  _style("ea_shuttle_c", {"hull": 0x8D8F8A, "hull_panel": 0x73756F, "hull_dark": 0x3F4144, "stripe": 0x2E8B4E},
                         ENGINE_GLOW_SPACE, edge_wear=0.55, grime=0.13, streaks=0.26, smudge=0.22),
                  bands=((1.35, 0.9, 0x2E8B4E),), number="03", number_colour=0x62D0BE, plate_tone=0.12, plate_grime=0.16),
    }  # fmt: skip


def atmo_looks() -> dict[str, Look]:
    """The EA atmospheric shuttle's three options."""
    return {
        "a": Look("a", "A: stained pale grey, two orange-red bands",
                  _style("ea_atmo_shuttle_a", {"hull": 0xC0C2C0, "hull_panel": 0xA6A9A8, "hull_dark": 0x3E4044, "stripe": 0xC84B26},
                         ENGINE_GLOW_ATMO, edge_wear=0.45, grime=0.14, streaks=0.3, smudge=0.25),
                  bands=((4.2, 0.8, 0xC84B26), (5.5, 0.8, 0xC84B26)), plate_tone=0.09, plate_grime=0.18),
        "b": Look("b", "B: grey and olive camouflage, cream tail",
                  _style("ea_atmo_shuttle_b", {"hull": 0x7E8582, "hull_panel": 0x6D746F, "hull_dark": 0x35373A, "stripe": 0xC8552A},
                         ENGINE_GLOW_ATMO, edge_wear=0.4, grime=0.1, streaks=0.2),
                  camo=(0x56614A, 0x9A9F99), tail=0xCFC8A6, tail_marks=0xC8552A, plate_tone=0.06, plate_grime=0.1),
        "c": Look("c", "C: fleet grey, one red band",
                  _style("ea_atmo_shuttle_c", {"hull": 0xA4A7AA, "hull_panel": 0x8A8D90, "hull_dark": 0x4F5256, "stripe": 0xA8322C},
                         ENGINE_GLOW_ATMO, edge_wear=0.35, grime=0.07, streaks=0.14),
                  bands=((4.6, 0.25, 0xDADCDE), (5.2, 0.9, 0xA8322C), (5.8, 0.25, 0xDADCDE)), plate_tone=0.06),
    }  # fmt: skip
