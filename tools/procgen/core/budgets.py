"""Class budgets for hulls (M10 Q38): what a hull of each class may cost in triangles and texture memory.

The table is docs/assets-capital.md, "Class budgets", approved by the maintainer on 2026-11-20; ``CLASS_BUDGETS`` repeats it
for the generators and ``test_budgets.py`` holds the two together. A hull's class is the generator's to name.

Texture memory is what one texture set's maps take on the card as the game imports them (``textured_mesh.import_sidecar``):
block compressed with mipmaps, a colour, ORM or glow map half a byte a texel, a normal map one byte. Only one set is loaded
at a time: the **high** set at the atlas's size, the **low** set one mip level down (every map half as wide,
``LOW_SHRINK``), so about a quarter of the memory. Triangles are the same in both.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

MIP_CHAIN = 4.0 / 3.0
# Bytes a texel as imported: the albedo, ORM and emissive maps in BC1, the normal map in BC5.
ATLAS_BYTES_PER_TEXEL = 0.5 + 1.0 + 0.5 + 0.5
NORMAL_BYTES_PER_TEXEL = 1.0
# The shared detail tile, the same in both sets: its albedo carries alpha (BC3), its normal map is BC5.
DETAIL_BYTES_PER_TEXEL = 1.0 + 1.0
DETAIL_PX = 1024
MIB = 1024.0 * 1024.0
LOW_SHRINK = 2  # the low set's maps are this many times smaller than the high set's


@dataclass(frozen=True)
class ClassBudget:
    """One class's ceiling: the triangles of the whole hull (every piece, without its fitted turrets' own models), the
    atlases it may have, a normal map bigger than the atlas where the class allows one (0: none), and the texture memory
    of the high and of the low texture set, MB."""

    name: str
    triangles: int
    atlas_px: int
    atlases: int
    normal_px: int
    texture_mb: float
    texture_mb_low: float


def texture_mb(atlas_px: Sequence[int], detail_px: int = 0, normal_px: int = 0) -> float:
    """The card memory of one texture set, MB: an atlas of each size in ``atlas_px`` with its four maps, the detail tile, and
    what a normal map of ``normal_px`` adds over the first atlas's own."""
    texels = sum(int(px) ** 2 for px in atlas_px) * ATLAS_BYTES_PER_TEXEL + int(detail_px) ** 2 * DETAIL_BYTES_PER_TEXEL
    if normal_px:
        texels += (int(normal_px) ** 2 - int(atlas_px[0]) ** 2) * NORMAL_BYTES_PER_TEXEL
    return texels * MIP_CHAIN / MIB


def low_set_mb(atlas_px: Sequence[int], detail_px: int = 0, normal_px: int = 0) -> float:
    """The same hull's low set: every atlas map ``LOW_SHRINK`` times smaller, the detail tile as it is."""
    return texture_mb([int(px) // LOW_SHRINK for px in atlas_px], detail_px, int(normal_px) // LOW_SHRINK)


def _budget(name: str, triangles: int, atlas_px: int, atlases: int, normal_px: int = 0) -> ClassBudget:
    sizes = [atlas_px] * atlases
    return ClassBudget(name, triangles, atlas_px, atlases, normal_px, round(texture_mb(sizes, DETAIL_PX, normal_px), 1),
                       round(low_set_mb(sizes, DETAIL_PX, normal_px), 1))


CLASS_BUDGETS: dict[str, ClassBudget] = {b.name: b for b in (
    _budget("fighter", 40_000, 2048, 1, normal_px=4096),  # the Starfury's normal map is twice its atlas
    _budget("small_craft", 30_000, 2048, 1),
    _budget("cruiser", 60_000, 4096, 1),
    _budget("capital", 100_000, 4096, 2),
    _budget("dreadnought", 150_000, 4096, 4),
)}


def over_budget(ship_class: str, triangles: int, high_mb: float, low_mb: float) -> list[str]:
    """What a hull of ``ship_class`` is over its budget by, in words; empty when it is inside. ``high_mb`` and ``low_mb``
    are its two texture sets' memory."""
    if ship_class not in CLASS_BUDGETS:
        return [f"unknown class {ship_class!r}"]
    budget = CLASS_BUDGETS[ship_class]
    out = []
    if triangles > budget.triangles:
        out.append(f"{triangles} triangles, the {ship_class} budget is {budget.triangles}")
    for label, used, limit in (("high", high_mb, budget.texture_mb), ("low", low_mb, budget.texture_mb_low)):
        if round(used, 1) > limit + 1e-6:  # the table is to a tenth of a MB: a hull at the ceiling rounds to it
            out.append(f"{used:.1f} MB in the {label} texture set, the {ship_class} budget is {limit}")
    return out


__all__ = ["CLASS_BUDGETS", "DETAIL_PX", "LOW_SHRINK", "ClassBudget", "low_set_mb", "over_budget", "texture_mb"]
