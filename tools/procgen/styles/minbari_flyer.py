"""The Minbari Flyer's looks (M10-T58; docs/design-references.md, "Minbari Flyer").

Semi-organic (Q47) under the Minbari's hexagonal grid (Q45), kept subtle: fine seams on regular hexagons, each cell a shade
of its own, on a low-gloss paint so the pale hull keeps its colour in full light. Over it the pattern the maintainer set
(2026-11-25, M10 Q90), read off the fan orthos, the painted miniature and the show stills in
``references/show/m10/minbari_flyer/`` (gitignored): a pale body; on the main lobes a dark blue line running lengthwise
(the small ones go without), with
thick curved bands branching from it towards the lobe's edges, tapering and fading out, each a purple core inside a blue
outline that fades into the body; no straight edge or corner anywhere. The blades and spindles are a darker blue with the
same bands, their outboard faces a clear bright blue. A soft, mottled blue glow lights the panel under the crossbar; the
spindles' tails glow, the Flyer's drive.

One look, ``p1``: the bluer of the three the maintainer was shown (2026-11-25).
"""

from __future__ import annotations

from dataclasses import dataclass

from ..core.color import capture_albedo
from ..core.geometry import Material
from . import Style
from .ea_civilian import lin

OPTIONS: tuple[str, ...] = ("p1",)
DEFAULT_OPTION = "p1"
GLOW_SRGB = 0xA8C8FF  # a cold blue-white


@dataclass(frozen=True)
class Look:
    """One surface option: the style (the pale body), the hexagons' size and shade, the dark blue of the lines, the purple of
    the bands' cores, the blue of their outlines, the darker blue of the fins and the bright blue of their outboard faces, and
    the under-panel's glow (sRGB) and strength."""

    name: str
    title: str
    style: Style
    hex_m: float
    hex_tone: float
    dark: int
    purple: int
    band_blue: int
    fins: int
    fin_outer: int
    panel_glow: int = 0x52B4FF
    glow_strength: float = 10.0


def _style(name: str, hull: int, panel: int, dark: int, metallic: float) -> Style:
    """The Flyer's paint: the body, the flatter webs and strakes a shade apart, the intakes and tube mouths dark."""
    mats = {
        "hull": Material(f"{name}_hull", capture_albedo(hull), paneled=True, metallic=metallic),
        "hull_panel": Material(f"{name}_hull_panel", capture_albedo(panel), paneled=True, metallic=metallic),
        "hull_dark": Material(f"{name}_hull_dark", capture_albedo(dark), metallic=0.4),
        "stripe": Material(f"{name}_stripe", capture_albedo(panel), paneled=True, metallic=metallic),
        "hazard": Material(f"{name}_hazard", capture_albedo(panel)),
        "hazard_dark": Material(f"{name}_hazard_dark", capture_albedo(dark)),
        "canopy_glass": Material(f"{name}_canopy", capture_albedo(dark), metallic=0.3),
        "canopy_frame": Material(f"{name}_canopy_frame", capture_albedo(dark), metallic=0.5),
        "nozzle": Material(f"{name}_nozzle", capture_albedo(dark), metallic=0.6),
        "nozzle_throat": Material(f"{name}_drive", capture_albedo(0x6C7CB0), metallic=0.3, emissive=lin(GLOW_SRGB), emissive_strength=2.5),
        "barrel": Material(f"{name}_barrel", capture_albedo(dark), metallic=0.6),
        "bore": Material(f"{name}_bore", capture_albedo(0x10101A)),
        "interior": Material(f"{name}_interior", capture_albedo(0x10101A)),
        "rcs": Material(f"{name}_rcs", capture_albedo(dark), metallic=0.5),
    }
    return Style(name=name, materials=mats, panel_size_m=1.2, hatch_fraction=0.0, panel_tint_jitter=0.0, edge_wear=0.0, streaks=0.0,
                 grime=0.03, extra={"bare_metal": 0.0, "smudge": 0.0, "speckle": 0.02, "paint_roughness": 0.6, "rivets": 0.0})


def looks() -> dict[str, Look]:
    """The Flyer's look."""
    return {"p1": Look("p1", "P1", _style("minbari_flyer_p1", 0xA4C4F2, 0x94B6EA, 0x1E2C66, 0.12), 1.2, 0.04, 0x24389E, 0x7A3CB6,
                       0x3668EC, 0x2A3CA0, 0x3E6EE0)}  # fmt: skip
