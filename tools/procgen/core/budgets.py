"""Class budgets for hulls (M10 Q38): what a hull of each class may cost in triangles and texture memory.

PROPOSED by M10-T05 from a GPU test with fleets in view (docs/assets-capital.md, "Class budgets"); the maintainer approves
the table before any hull task is held to it. A hull's class is the generator's to name.

Texture memory is what one texture set's maps take on the card as the game imports them (``textured_mesh.import_sidecar``):
block compressed with mipmaps, a colour, ORM or glow map half a byte a texel, a normal map one byte. Only one set (low or
high) is loaded at a time.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

MIP_CHAIN = 4.0 / 3.0
# Bytes a texel as imported: the albedo, ORM and emissive maps in BC1, the normal map in BC5.
ATLAS_BYTES_PER_TEXEL = 0.5 + 1.0 + 0.5 + 0.5
# The shared detail tile: its albedo carries alpha (BC3), its normal map is BC5.
DETAIL_BYTES_PER_TEXEL = 1.0 + 1.0
MIB = 1024.0 * 1024.0


@dataclass(frozen=True)
class ClassBudget:
    """One class's ceiling: the triangles of the whole hull (every piece, without its fitted turrets' own models), the
    atlases it may have and the texture memory of one texture set."""

    name: str
    triangles: int
    atlas_px: int
    atlases: int
    texture_mb: float


def texture_mb(atlas_px: Sequence[int], detail_px: int = 0) -> float:
    """The card memory of one texture set: an atlas of each size in ``atlas_px`` with its four maps, and the detail tile."""
    texels = sum(int(px) ** 2 for px in atlas_px) * ATLAS_BYTES_PER_TEXEL + int(detail_px) ** 2 * DETAIL_BYTES_PER_TEXEL
    return texels * MIP_CHAIN / MIB


def _budget(name: str, triangles: int, atlas_px: int, atlases: int, normal_px: int = 0) -> ClassBudget:
    """A class's row; ``normal_px`` is a normal map bigger than the atlas (the Starfury's, twice its atlas)."""
    extra = (normal_px ** 2 - atlas_px ** 2) * MIP_CHAIN / MIB if normal_px else 0.0
    return ClassBudget(name, triangles, atlas_px, atlases, round(texture_mb([atlas_px] * atlases, 1024) + extra, 1))


# The proposal (M10-T05 stage 1; not yet approved). On the RX 6950 XT at 1920x1080 a fleet of 96 hulls at these ceilings (2
# dreadnoughts, 6 capitals, 12 cruisers, 16 small craft, 60 fighters; 18 hull types) drew in 0.6 to 0.8 ms of GPU time with the
# importer's levels of detail and 1.9 ms with none (4.5 million triangles); its textures took 1 069 MB. Texture memory is what
# binds, not triangles.
CLASS_BUDGETS: dict[str, ClassBudget] = {b.name: b for b in (
    _budget("fighter", 40_000, 2048, 1, normal_px=4096),
    _budget("small_craft", 30_000, 2048, 1),
    _budget("cruiser", 60_000, 4096, 1),
    _budget("capital", 100_000, 4096, 2),
    _budget("dreadnought", 150_000, 4096, 4),
)}


def over_budget(ship_class: str, triangles: int, texture_set_mb: float) -> list[str]:
    """What a hull of ``ship_class`` is over its budget by, in words; empty when it is inside."""
    if ship_class not in CLASS_BUDGETS:
        return [f"unknown class {ship_class!r}"]
    budget = CLASS_BUDGETS[ship_class]
    out = []
    if triangles > budget.triangles:
        out.append(f"{triangles} triangles, the {ship_class} budget is {budget.triangles}")
    if texture_set_mb > budget.texture_mb + 1e-6:
        out.append(f"{texture_set_mb:.1f} MB of textures, the {ship_class} budget is {budget.texture_mb}")
    return out


__all__ = ["CLASS_BUDGETS", "ClassBudget", "over_budget", "texture_mb"]
