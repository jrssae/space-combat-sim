"""The Minbari Flyer's looks (M10-T58; docs/design-references.md, "Minbari Flyer").

Semi-organic (Q47) under the Minbari's hexagonal grid (Q45): fine seams on regular hexagons, each cell its own shade and
sheen, over a lightly metallic, glossy paint that reads as iridescent. On top of it the show's mottling: long soft streaks
running along the hull, paler or deeper than the base. The tails of the crossbar's spindles glow, the Flyer's drive.

Three looks (``a``, ``b``, ``c``): ``a`` the show's blue-violet with pale lavender streaks, ``b`` pale lavender-white with
violet streaks (the docked Flyer in the first still), ``c`` a deep blue with bright azure streaks. Colours are sRGB read
off the stills in ``references/show/m10/minbari_flyer/`` (gitignored), lifted out of the stills' shadow.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..core.color import capture_albedo
from ..core.geometry import Material
from . import Style
from .ea_civilian import lin

OPTIONS: tuple[str, ...] = ("a", "b", "c")
DEFAULT_OPTION = "a"
GLOW_SRGB = 0xA8C8FF  # a cold blue-white


@dataclass(frozen=True)
class Look:
    """One surface option: the style, the hexagons' size and shade, and the streak colours with the share each covers."""

    name: str
    title: str
    style: Style
    hex_m: float
    hex_tone: float
    streaks: tuple[tuple[int, float], ...]


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
                 grime=0.03, extra={"bare_metal": 0.0, "smudge": 0.0, "speckle": 0.02, "paint_roughness": 0.3, "rivets": 0.0})


def looks() -> dict[str, Look]:
    """The Flyer's three options."""
    return {
        "a": Look("a", "A: show blue-violet, pale lavender streaks", _style("minbari_flyer_a", 0x6A68AE, 0x5E5AA0, 0x2A2448, 0.35),
                  1.2, 0.08, ((0xC4C2EC, 0.36), (0x3E3270, 0.26))),
        "b": Look("b", "B: pale lavender, violet streaks", _style("minbari_flyer_b", 0xB0ACD8, 0x9E99CC, 0x3A3060, 0.3),
                  1.2, 0.07, ((0x6250A8, 0.38), (0xE4E2F8, 0.2))),
        "c": Look("c", "C: deep blue, azure streaks", _style("minbari_flyer_c", 0x3C4496, 0x343A86, 0x1A1C40, 0.45),
                  1.0, 0.09, ((0x5FA6F0, 0.32), (0x8A84D8, 0.24))),
    }  # fmt: skip
