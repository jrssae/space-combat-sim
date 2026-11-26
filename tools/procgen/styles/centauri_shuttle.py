"""The Centauri shuttle's looks (M10-T58; docs/design-references.md, "Centauri shuttle").

The skin is the maintainer's (2026-11-25, M10 Q83): no panel mosaic but one solid violet with darker patches, in the
manner of the Agamemnon model's textures (a style reference only; nothing is taken from those files), here a soft mottle
of darker clouds at three sizes. Gold as the stills show it: lines and small panels over the upper hull, a narrow brass
strip down the violet spine, a Centauri-style crest either side of it (drawn here, no copied logo), the louvres' tops and
the wings' leading edges; round red lamps along the wings' trailing edges; the nozzles glow the pink-white of Centauri
drives.

The maintainer chose option D2 (2026-11-25): a violet (#7540B0) between the earlier, too dark "Centauri violet" (#5A3A86)
and the too bright #8A44D0, with a touch of the stills' magenta; machinery #3A1F60, gold #DEBA60. Colours are sRGB read off
the stills in ``references/show/m10/centauri_shuttle/`` (gitignored), lifted out of the stills' shadow.
"""

from __future__ import annotations

from dataclasses import dataclass, replace

from ..core.color import capture_albedo
from ..core.geometry import Material
from . import Style
from .ea_civilian import lin

GLOW_SRGB = 0xFFB8E0  # the pink-white of the Centauri drives (styles/centauri.py)
WINDOW_SRGB = 0x1A1530
RUNNING_LIGHT_SRGB = 0xFF3418  # the lamps along the trailing edges in the stills: red with an orange tinge
BRASS_SRGB = 0xB8913E  # the strip down the spine


@dataclass(frozen=True)
class Look:
    """One surface option: the style and its ``mottle``, soft darker clouds ``(size m, how much of the hull, how much
    darker)``. Every look carries the gold (lines, panels, crests, the spine's ``spine_strip_m`` wide brass strip) and, through
    the style's ``running_light`` finish, the lamps along each wing's trailing edge."""

    name: str
    title: str
    style: Style
    mottle: tuple[tuple[float, float, float], ...]
    spine_strip_m: float = 0.5


def _style(name: str, hull: int, dark: int, gold: int) -> Style:
    """A Centauri small craft in one purple: the hull's paint, the darker machinery and the gold trim."""
    mats = {
        "hull": Material(f"{name}_hull", capture_albedo(hull), paneled=True),
        "hull_panel": Material(f"{name}_hull_panel", capture_albedo(hull), paneled=True),
        "hull_dark": Material(f"{name}_hull_dark", capture_albedo(dark), paneled=True),
        "stripe": Material(f"{name}_gold", capture_albedo(gold), metallic=0.7),
        "hazard": Material(f"{name}_hazard", capture_albedo(gold)),
        "hazard_dark": Material(f"{name}_hazard_dark", capture_albedo(dark)),
        "canopy_glass": Material(f"{name}_canopy", capture_albedo(WINDOW_SRGB), metallic=0.3),
        "canopy_frame": Material(f"{name}_canopy_frame", capture_albedo(dark), metallic=0.5),
        "nozzle": Material(f"{name}_nozzle", capture_albedo(0x3A3448), metallic=0.8),
        "nozzle_throat": Material(f"{name}_throat", capture_albedo(0x141218), metallic=0.8, emissive=lin(GLOW_SRGB), emissive_strength=3.0),
        "barrel": Material(f"{name}_barrel", capture_albedo(0x3A3448), metallic=0.7),
        "bore": Material(f"{name}_bore", capture_albedo(0x141218)),
        "interior": Material(f"{name}_interior", capture_albedo(0x141218)),
        "rcs": Material(f"{name}_rcs", capture_albedo(0x3A3448), metallic=0.6),
    }
    # Smooth paint: no generated hatches, little wear; the patches and a fine speckle carry the surface.
    return Style(name=name, materials=mats, panel_size_m=1.2, hatch_fraction=0.0, panel_tint_jitter=0.0, edge_wear=0.12,
                 streaks=0.03, grime=0.04, extra={"bare_metal": 0.0, "smudge": 0.05, "speckle": 0.05, "paint_roughness": 0.5, "rivets": 0.0})


def _lit(style: Style, colour: int) -> Style:
    """The style with a ``running_light`` finish: a lamp glowing ``colour``, bright enough to read at a hundred metres."""
    lamp = Material(f"{style.name}_running_light", capture_albedo(colour), emissive=lin(colour), emissive_strength=8.0)
    return replace(style, materials={**style.materials, "running_light": lamp})


MOTTLE = ((6.0, 0.45, 0.1), (2.4, 0.4, 0.12), (0.9, 0.3, 0.07))


SHUTTLE_LOOK = Look("d2", "D2: violet #7540B0", _lit(_style("centauri_shuttle", 0x7540B0, 0x3A1F60, 0xDEBA60), RUNNING_LIGHT_SRGB), MOTTLE)
