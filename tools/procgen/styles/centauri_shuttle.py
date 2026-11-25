"""The Centauri shuttle's looks (M10-T58; docs/design-references.md, "Centauri shuttle").

The skin is the maintainer's choice for this hull (2026-11-25, M10 Q83): no panel mosaic, but one solid paint with small
patches a few shades darker scattered over it, at two or three sizes and overlapping, in the manner of the Agamemnon
model's textures, shifted into the Centauri's purple. The pattern is generated here; nothing is taken from those files.
Gold picks out the spine's crown, the louvres and the wings' leading edges, as on the show's craft; the nozzles glow
the pink-white of Centauri drives.

Three looks (``a``, ``b``, ``c``) vary within that one style: the purple's hue and depth, how many patches there are and
how dark, and the gold. Colours are sRGB read off the stills in ``references/show/m10/centauri_shuttle/`` (gitignored),
lifted out of the stills' shadow.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..core.color import capture_albedo
from ..core.geometry import Material
from . import Style
from .ea_civilian import lin

OPTIONS: tuple[str, ...] = ("a", "b", "c")
DEFAULT_OPTION = "a"
GLOW_SRGB = 0xFFB8E0  # the pink-white of the Centauri drives (styles/centauri.py)
WINDOW_SRGB = 0x1A1530


@dataclass(frozen=True)
class PatchLayer:
    """One size of patch: the field it is cut from (m), how many of the cut plates are painted, and the shades
    ``(share, how much darker)`` they take."""

    cell: tuple[float, float]
    scatter: float
    tiers: tuple[tuple[float, float], ...]


@dataclass(frozen=True)
class Look:
    """One surface option: the style and the patches painted over its solid colour."""

    name: str
    title: str
    style: Style
    patches: tuple[PatchLayer, ...]


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


def looks() -> dict[str, Look]:
    """The shuttle's three options."""
    return {
        "a": Look("a", "A: show plum, sparse patches, warm gold",
                  _style("centauri_shuttle_a", 0x6E3466, 0x3A1C36, 0xB8954E),
                  (PatchLayer((3.2, 2.0), 0.35, ((0.7, 0.1), (0.3, 0.18))), PatchLayer((1.1, 0.7), 0.3, ((0.8, 0.08), (0.2, 0.15))))),
        "b": Look("b", "B: Centauri violet, denser patches, pale gold",
                  _style("centauri_shuttle_b", 0x5A3A86, 0x2E2050, 0xD2B470),
                  (PatchLayer((3.2, 2.0), 0.5, ((0.6, 0.11), (0.4, 0.2))), PatchLayer((1.1, 0.7), 0.45, ((0.7, 0.09), (0.3, 0.17))),
                   PatchLayer((0.5, 0.35), 0.3, ((1.0, 0.1),)))),
        "c": Look("c", "C: deep maroon, heavy dark patches, bright gold",
                  _style("centauri_shuttle_c", 0x5A2346, 0x2C1022, 0xD9A93A),
                  (PatchLayer((3.6, 2.2), 0.55, ((0.5, 0.14), (0.5, 0.26))), PatchLayer((1.2, 0.8), 0.5, ((0.6, 0.12), (0.4, 0.22))),
                   PatchLayer((0.5, 0.35), 0.35, ((1.0, 0.1),)))),
    }  # fmt: skip
