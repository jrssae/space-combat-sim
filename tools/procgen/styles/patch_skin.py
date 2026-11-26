"""The Agamemnon pattern as a capital skin (Q83, Q87; shared since M10-T68, Q98): no panel mosaic and no seam lines, but the paint
wandering in tone over big plates, small darker patches at two or three sizes overlapping on it, a few low plates standing proud and
fine scratches over everything, made in code in the manner of the Agamemnon model's textures (Chris Kuhn's; a style reference only,
nothing taken from them). The Asimov liner (``styles/ea_asimov.py``) and the Omega (``styles/ea_omega.py``) wear it in their own
colours; it is the default skin for every new hull (Q98).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from ..core.seams import Feature, PatchPlates, Plates, Relief, SeamLayout, _keyed_hash, _smooth


@dataclass(frozen=True)
class Patches:
    """One size of darker patch: the field its plates are cut from (m), the share painted, and the shades ``(share, darker)``."""

    cell: tuple[float, float]
    scatter: float
    tiers: tuple[tuple[float, float], ...]


@dataclass(frozen=True)
class Scratches(Feature):
    """Fine scratches over the paint: in some of the ``cell_m`` squares one short straight stroke at its own angle, a little lighter
    or darker than the paint (``tone``), ``width_m`` wide."""

    cell_m: float = 2.5
    share: float = 0.25
    tone: float = 0.08
    width_m: float = 0.05
    seed: int = 0

    def _paint_all(self, p: np.ndarray, n: np.ndarray, line_m: float, depth_m: float, out: Relief, ok: np.ndarray) -> None:
        grid = Plates(cell=(self.cell_m, self.cell_m), splits=0, seed=self.seed, symmetric=False)
        key, u0, _, v0, _, u, v = grid.cells(p, n)
        chosen = _keyed_hash(key, self.seed + 11) < self.share
        a = math.pi * _keyed_hash(key, self.seed + 13)
        cu = u0 + self.cell_m * (0.25 + 0.5 * _keyed_hash(key, self.seed + 17))
        cv = v0 + self.cell_m * (0.25 + 0.5 * _keyed_hash(key, self.seed + 19))
        half = 0.5 * self.cell_m * (0.3 + 0.5 * _keyed_hash(key, self.seed + 23))
        du, dv = u - cu, v - cv
        along = du * np.cos(a) + dv * np.sin(a)
        across = np.abs(-du * np.sin(a) + dv * np.cos(a))
        stroke = _smooth(1.0 - across / self.width_m) * (np.abs(along) < half) * chosen * ok
        sign = np.where(_keyed_hash(key, self.seed + 29) < 0.6, 1.0, -1.0)
        out.tint *= 1.0 + self.tone * sign * stroke


@dataclass(frozen=True)
class PatchSkin:
    """The Agamemnon manner (Q87): big plates wandering in tone (``tone``), darker patches at several sizes (``patches``), a few low
    plates standing proud (``proud``: share of the ``proud_cell`` plates) and scratches; no seam lines and no near tile."""

    name: str = "patch_plates"
    tile_m: float = 0.0
    tone: float = 0.05
    patches: tuple[Patches, ...] = ()
    proud: float = 0.12
    proud_cell: tuple[float, float] = (7.0, 4.5)
    scratches: float = 0.25

    def _layers(self, scale: float, seed: int) -> list[Feature]:
        base = dict(level=3, wrap="sides", long_axis=2, keep=0.3, dark=0.0, depth=0.0)
        out: list[Feature] = [Plates(cell=(26.0 * scale, 16.0 * scale), splits=2, min_m=3.0 * scale, tone=self.tone, sheen=0.03, seed=seed, **base)]
        for k, layer in enumerate(self.patches):
            cell = (layer.cell[0] * scale, layer.cell[1] * scale)
            out.append(PatchPlates(cell=cell, splits=2, min_m=0.25 * min(cell), scatter=layer.scatter, inset_m=0.0, tiers=layer.tiers,
                                   seed=seed + 31 * (k + 1), **base))
        if self.proud > 0.0:
            out.append(Plates(level=3, wrap="sides", long_axis=2, cell=(self.proud_cell[0] * scale, self.proud_cell[1] * scale), splits=1,
                              min_m=1.0 * scale, scatter=self.proud, inset_m=0.3 * scale, tone=0.03, dark=0.0, depth=-0.35, seed=seed + 97))
        if self.scratches > 0.0:
            out.append(Scratches(level=3, dark=0.0, depth=0.0, cell_m=2.5 * scale, share=self.scratches, seed=seed + 131))
        return out

    def hull_layout(self, lo, hi, seed: int) -> SeamLayout:  # noqa: ANN001 - the Skin protocol's corners
        return SeamLayout.of(self._layers(1.0, seed))

    def fitting_layout(self, lo, hi, seed: int) -> SeamLayout:  # noqa: ANN001
        size = min(b - a for a, b in zip(lo, hi, strict=True))
        return SeamLayout.of(self._layers(max(0.08, min(0.4, size / 30.0)), seed))

    def detail_tile(self, px: int, seed: int) -> None:
        return None


__all__ = ["PatchSkin", "Patches", "Scratches"]
