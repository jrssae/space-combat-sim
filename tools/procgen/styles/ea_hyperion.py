"""The Earth Alliance Hyperion-class heavy cruiser's style (M10-T22): a different class from the Omega, so its own paint and
plating on the fleet's machinery (``ea_capital.capital_style``: the same roles, lit red bays, blue-white engines).

The show (``references/show/m10/ea_hyperion/``, gitignored) paints it light grey with broad royal-blue bands round the forward
hull and the command tower. The ``stripe`` role is the band.

Look A is the maintainer's (2026-11-21): the show's light grey and royal blue, plated in the fleet's standard mosaic
(``ea_capital.fleet_mosaic``) rather than the show's long planks; its colours re-read from the stills in
``references/ships/Hyperion/`` (Q58): a neutral light grey and a saturated royal blue, since the game's warm key light turns
a warm grey beige and a violet-leaning blue dull. B and C stay from the option sheet, each with its own plating (:data:`PLATING`). ``livery`` repaints roles as ``ea_capital``'s does.
"""

from __future__ import annotations

import dataclasses
from collections.abc import Mapping
from dataclasses import dataclass

import numpy as np

from ..core import detail_layer
from ..core.geometry import Material
from ..core.seams import Feature, Plates, SeamLayout, _keyed_hash
from .capital import CapitalStyle, PanelMosaic, _frames
from .ea_capital import Look, bay_metal_materials, capital_style, fleet_mosaic

PREFIX = "eah"
SMOOTH_ROLES = ("barrel", "bore")


@dataclass(frozen=True)
class Plating:
    """A look's panel treatment: the plates' size (along the hull, across), how often they split, the frames' pitch."""

    plate_m: tuple[float, float]
    splits: int
    frames_m: float


@dataclass(frozen=True)
class PatchPlates(Plates):
    """Scattered plates painted a darker grey (down to ``darkest`` of the hull's value), flush with the hull: the patches of
    medium and dark panels on the Hyperion's light grey."""

    darkest: float = 0.5

    def _paint_all(self, p: np.ndarray, n: np.ndarray, line_m: float, depth_m: float, out, ok: np.ndarray) -> None:  # noqa: ANN001
        key, u0, u1, v0, v1, u, v = self.cells(p, n)
        chosen = ok & (self._hash(key, 503) < self.scatter) & (np.minimum(u1 - u0, v1 - v0) > 2.5 * self.inset_m)
        inside = np.minimum(np.minimum(u - u0, u1 - u), np.minimum(v - v0, v1 - v)) > self.inset_m
        out.tint *= 1.0 - self.darkest * self._hash(key, 401) * (chosen & inside)

    def _hash(self, key: np.ndarray, salt: int) -> np.ndarray:
        return _keyed_hash(key, self.seed + salt)


@dataclass(frozen=True)
class HyperionMosaic(PanelMosaic):
    """The fleet's plating with subtler seams (``seam_depth`` of the groove depth, ``seam_width`` of the line) and small dark
    patches (``patches``, the share of plates) over a light grey base; the plates' own tone wander stays small. Its near-field
    tile's seams are softened alike."""

    seam_depth: float = 0.22
    seam_width: float = 0.6
    tile_soft: float = 0.5
    patches: float = 0.2
    darkest: float = 0.5

    def _soft(self, features: list[Feature]) -> list[Feature]:
        return [dataclasses.replace(f, depth=f.depth * self.seam_depth, width=f.width * self.seam_width) if f.depth > 0.0 else f
                for f in features]

    def _plating(self, cell: tuple[float, float], seed: int) -> list[Feature]:
        base = dict(wrap="sides", long_axis=2, cell=cell, splits=self.splits, min_m=1.2, keep=0.3, seed=seed)
        return [*self._soft(super()._plating(cell, seed)),
                PatchPlates(level=3, scatter=self.patches, inset_m=0.1, darkest=self.darkest, dark=0.0, depth=0.0, **base)]

    def hull_layout(self, lo, hi, seed: int) -> SeamLayout:  # noqa: ANN001
        return SeamLayout.of([*self._soft(_frames(lo, hi, self.frames_m, self.major_every)), *self._plating(self.plate_m, seed)])

    def detail_tile(self, px: int, seed: int) -> dict[str, np.ndarray] | None:
        """The fleet's near-field mosaic with its seams as soft as the hull's: narrower, ``tile_soft`` as deep and as dark."""
        dark = 1.0 - (1.0 - detail_layer.LINE_DARK) * self.tile_soft
        return detail_layer.detail_tile(px, self.tile_m, seed, line_m=detail_layer.LINE_M * self.seam_width,
                                        groove_m=detail_layer.GROOVE_M * self.tile_soft, line_dark=dark)


LOOKS: dict[str, Look] = {
    "a": Look("a", "A: show livery, light grey with dark patches, bright royal-blue bands, shallow seams",
              {"hull": 0xD0D3D6, "hull_panel": 0xC0C4C8, "hull_dark": 0x60646C, "stripe": 0x3464EA},
              plate_tone=0.04, plate_grime=0.05, metallic=0.3, edge_wear=0.25, streaks=0.1, grime=0.05),
    "b": Look("b", "B: fleet white, navy bands, square plates",
              {"hull": 0xD0D2D4, "hull_panel": 0xBDC0C4, "hull_dark": 0x585C64, "stripe": 0x1A2C66},
              plate_tone=0.1, plate_grime=0.08, metallic=0.25, edge_wear=0.3, streaks=0.15, grime=0.08),
    "c": Look("c", "C: warm grey, cobalt bands, broad smooth panels",
              {"hull": 0x9C9A92, "hull_panel": 0x8C8A82, "hull_dark": 0x3E3D3A, "stripe": 0x2E6CD6},
              plate_tone=0.05, plate_grime=0.1, metallic=0.4, edge_wear=0.35, streaks=0.2, grime=0.1),
}
PLATING: dict[str, Plating] = {  # the looks not on the fleet's mosaic
    "b": Plating((10.0, 10.0), 2, 20.0),
    "c": Plating((40.0, 16.0), 1, 60.0),
}
DEFAULT_LOOK = "a"


def hyperion_mosaic(chosen: Look) -> HyperionMosaic:
    """The fleet's plate sizes in the Hyperion's softer, patched finish."""
    return HyperionMosaic(plate_m=(18.0, 9.0), splits=2, tone=chosen.plate_tone, grime=chosen.plate_grime, frames_m=30.0, major_every=4)


def ea_hyperion(look: str = DEFAULT_LOOK, livery: Mapping[str, int] | None = None) -> CapitalStyle:
    """The Hyperion's style in one of the looks, any role repainted by ``livery``."""
    if look not in LOOKS:
        raise ValueError(f"ea_hyperion has no look {look!r}; it has {sorted(LOOKS)}")
    chosen, plating = LOOKS[look], PLATING.get(look)
    skin = hyperion_mosaic(chosen) if plating is None else PanelMosaic(plate_m=plating.plate_m, splits=plating.splits, tone=chosen.plate_tone,
                                                                    grime=chosen.plate_grime, frames_m=plating.frames_m, major_every=4)
    style = capital_style(chosen, f"ea_hyperion_{look}", PREFIX, skin, livery)
    materials = {**smooth_barrels(style.style.materials), **bay_metal_materials(style.style.materials["hull"].name.removesuffix("_hull"))}
    style = dataclasses.replace(style, style=dataclasses.replace(style.style, materials=materials))
    if plating is not None:
        return style
    return dataclasses.replace(style, style=dataclasses.replace(style.style, panel_line_darkness=0.89, groove_depth_m=0.003))


def smooth_barrels(materials: Mapping[str, Material]) -> dict[str, Material]:
    """The maintainer's call (M10-T22): the guns' barrels and bores are plain smooth metal, no weathering on them."""
    return {role: dataclasses.replace(m, smooth=True) if role in SMOOTH_ROLES else m for role, m in materials.items()}


__all__ = ["DEFAULT_LOOK", "LOOKS", "PLATING", "HyperionMosaic", "PatchPlates", "Plating", "SMOOTH_ROLES", "ea_hyperion", "hyperion_mosaic", "smooth_barrels"]
