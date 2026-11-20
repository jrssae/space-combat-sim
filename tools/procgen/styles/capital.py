"""Capital ship styles (M10-T05, D12.1): a faction's paint and the skin its hulls are plated with.

A :class:`CapitalStyle` is what a capital generator hands the framework (``core/capital.py``): the faction's :class:`Style`
(materials by role, wear) and a skin. The skin is the hook the factions differ by:

* :class:`PanelMosaic`, the default: frame lines and plating of mixed sizes as the Earth Alliance, Narn and Centauri hulls
  wear, with ``core/detail_layer.py``'s fine mosaic as the shared near-field tile;
* :class:`HexGrid` (Q45): a hexagonal grid for the Minbari and the Interstellar Alliance, with a hexagonal near-field tile;
* :class:`Seamless` (Q46): no seams and no tile, for the Shadows' and the Vorlons' organic hulls (M10-T06 lays its sheen
  over it through ``CapitalStyle.surface``).

A skin draws two layouts, each in the module's own frame inside its box: ``hull_layout`` for hull sections and
``fitting_layout`` for what stands on them (turrets, housings). Level 1 features are the low texture set, the rest the high
one (``core/seams.py``). ``detail_tile`` gives the shared tile's maps (``albedo`` RGBA and ``normal``), or ``None`` for none.

A hull task adds ``styles/<faction>_capital.py`` with its own ``CapitalStyle``; ``FRAMEWORK_GREY`` is the framework's
neutral one, for the test hull.
"""

from __future__ import annotations

import math
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any, Protocol

import numpy as np

from ..core import detail_layer
from ..core.color import linear_to_srgb
from ..core.geometry import Material
from ..core.seams import EMPTY, Cut, Feature, Hexes, Plates, SeamLayout
from . import Style

Vec3 = tuple[float, float, float]


class Skin(Protocol):
    """How a faction's hulls are plated."""

    name: str
    tile_m: float

    def hull_layout(self, lo: Vec3, hi: Vec3, seed: int) -> SeamLayout: ...

    def fitting_layout(self, lo: Vec3, hi: Vec3, seed: int) -> SeamLayout: ...

    def detail_tile(self, px: int, seed: int) -> dict[str, np.ndarray] | None: ...


def _frames(lo: Vec3, hi: Vec3, pitch_m: float, major_every: int) -> list[Feature]:
    """Frame lines across the hull's long axis at whole multiples of the pitch, so neighbouring sections' frames meet;
    every ``major_every``-th is a major break (the low texture set keeps those)."""
    first, last = math.ceil(lo[2] / pitch_m), math.floor(hi[2] / pitch_m)
    return [Cut(axis=2, at=k * pitch_m, level=1 if k % major_every == 0 else 2, width=1.0 if k % major_every == 0 else 0.8)
            for k in range(first, last + 1)]


@dataclass(frozen=True)
class PanelMosaic:
    """Plating of mixed sizes cut from ``plate_m`` fields ``splits`` times, frame lines every ``frames_m``, a few proud hatches."""

    name: str = "panel_mosaic"
    plate_m: tuple[float, float] = (9.0, 6.0)
    splits: int = 2
    tone: float = 0.07
    sheen: float = 0.06
    grime: float = 0.05
    hatches: float = 0.06
    frames_m: float = 7.5
    major_every: int = 4
    tile_m: float = detail_layer.DEFAULT_TILE_M

    def _plating(self, cell: tuple[float, float], seed: int) -> list[Feature]:
        base = dict(wrap="sides", long_axis=2, cell=cell, splits=self.splits, min_m=1.2, keep=0.3, seed=seed)
        return [Plates(level=2, tone=0.0, sheen=0.0, **base),
                Plates(level=3, tone=self.tone, sheen=self.sheen, grime=self.grime, grime_m=0.5, depth=0.0, dark=0.0, **base),
                Plates(level=3, wrap="sides", long_axis=2, cell=(2.4, 1.5), splits=1, min_m=0.5, scatter=self.hatches, inset_m=0.24,
                       tone=0.05, dark=0.7, depth=0.7, seed=seed + 2)]

    def hull_layout(self, lo: Vec3, hi: Vec3, seed: int) -> SeamLayout:
        return SeamLayout.of([*_frames(lo, hi, self.frames_m, self.major_every), *self._plating(self.plate_m, seed)])

    def fitting_layout(self, lo: Vec3, hi: Vec3, seed: int) -> SeamLayout:
        size = min(b - a for a, b in zip(lo, hi, strict=True))
        cell = (max(0.6, min(0.6 * self.plate_m[0], 0.5 * size)), max(0.4, min(0.6 * self.plate_m[1], 0.35 * size)))
        return SeamLayout.of(self._plating(cell, seed))

    def detail_tile(self, px: int, seed: int) -> dict[str, np.ndarray] | None:
        return detail_layer.detail_tile(px, self.tile_m, seed)


# The hexagonal tile wraps with 7 cells across and 4 double rows up: 7 against 4 * sqrt(3) = 6.93, so its cells are squeezed 1 %.
HEX_TILE_CELLS = (7, 4)


@dataclass(frozen=True)
class HexGrid:
    """A hexagonal grid (Q45): cells ``cell_m`` across their flats on the hull, ``tile_m / 7`` in the near-field tile."""

    name: str = "hex_grid"
    cell_m: float = 6.0
    tone: float = 0.05
    sheen: float = 0.05
    frames_m: float = 30.0
    tile_m: float = detail_layer.DEFAULT_TILE_M
    line_m: float = 0.07
    groove_m: float = 0.02

    def hull_layout(self, lo: Vec3, hi: Vec3, seed: int) -> SeamLayout:
        return SeamLayout.of([*_frames(lo, hi, self.frames_m, 1),
                              Hexes(level=2, cell_m=self.cell_m, tone=0.0, sheen=0.0, seed=seed),
                              Hexes(level=3, cell_m=self.cell_m, tone=self.tone, sheen=self.sheen, depth=0.0, dark=0.0, seed=seed)])

    def fitting_layout(self, lo: Vec3, hi: Vec3, seed: int) -> SeamLayout:
        size = min(b - a for a, b in zip(lo, hi, strict=True))
        return SeamLayout.of([Hexes(level=2, cell_m=max(0.5, min(0.5 * self.cell_m, 0.4 * size)), tone=self.tone, sheen=self.sheen, seed=seed)])

    def detail_tile(self, px: int, seed: int) -> dict[str, np.ndarray] | None:
        """The near-field tile: small hexagons, a groove on every edge, each cell a shade of its own; it wraps on all sides."""
        nx, ny = HEX_TILE_CELLS
        cell = self.tile_m / nx
        grid = Hexes(cell_m=cell, stretch=(1.0, self.tile_m / (ny * math.sqrt(3.0) * cell)), seed=seed)
        texel = self.tile_m / px
        centres = (np.arange(px) + 0.5) * texel
        u, v = np.meshgrid(centres, centres)
        _, edge = grid.cells(u.reshape(-1), v.reshape(-1))
        edge = edge.reshape(px, px)
        line = np.clip(1.0 - edge / (0.5 * self.line_m), 0.0, 1.0)
        line = line * line * (3.0 - 2.0 * line)
        height = -self.groove_m * line
        alpha = np.maximum(detail_layer.FACE_ALPHA, line)
        factor = 1.0 - (1.0 - detail_layer.LINE_DARK) * line
        rgb = np.clip(linear_to_srgb(np.clip(factor, 0.0, 1.0)), 0.0, 1.0)
        albedo = np.concatenate([np.repeat(rgb[..., None], 3, axis=-1), alpha[..., None]], axis=-1)
        dhdu = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) / (2.0 * texel)
        dhdv = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / (2.0 * texel)
        n = np.stack([-dhdu, dhdv, np.ones_like(height)], axis=-1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        to8 = lambda a: np.clip(np.rint(a * 255.0), 0, 255).astype(np.uint8)  # noqa: E731
        return {"albedo": to8(albedo), "normal": to8(n * 0.5 + 0.5)}


@dataclass(frozen=True)
class Seamless:
    """No seams, no panels, no tile (Q46): the Shadows' and the Vorlons' hulls."""

    name: str = "seamless"
    tile_m: float = 0.0

    def hull_layout(self, lo: Vec3, hi: Vec3, seed: int) -> SeamLayout:
        return EMPTY

    def fitting_layout(self, lo: Vec3, hi: Vec3, seed: int) -> SeamLayout:
        return EMPTY

    def detail_tile(self, px: int, seed: int) -> dict[str, np.ndarray] | None:
        return None


@dataclass(frozen=True)
class CapitalStyle:
    """A faction's capital look: its paint, its skin, and ``surface``: keys added to every opaque surface entry of the
    manifest's meshes (M10-T06 names its sheen layer's parameters here)."""

    name: str
    style: Style
    skin: Skin = field(default_factory=PanelMosaic)
    surface: Mapping[str, Any] = field(default_factory=dict)


def _grey() -> Style:
    hull = Material("cap_hull", (0.105, 0.11, 0.125), paneled=True, metallic=0.45, roughness=0.5)
    deck = Material("cap_deck", (0.085, 0.09, 0.1), paneled=True, metallic=0.4, roughness=0.55)
    dark = Material("cap_dark", (0.05, 0.052, 0.058), paneled=True, metallic=0.55, roughness=0.5)
    return Style(
        name="capital_framework_grey",
        materials={
            "hull": hull, "hull_panel": deck, "hull_dark": dark,
            "stripe": Material("cap_stripe", (0.3, 0.06, 0.03), paneled=True),
            "hazard": Material("cap_deck_lit", (0.5, 0.5, 0.46), emissive=(1.0, 0.92, 0.75), emissive_strength=0.5),
            "hazard_dark": Material("cap_frame", (0.03, 0.03, 0.032), metallic=0.5),
            "canopy_glass": Material("cap_glass", (0.006, 0.007, 0.009)),
            "canopy_frame": Material("cap_glass_frame", (0.05, 0.052, 0.058), metallic=0.5),
            "nozzle": Material("cap_nozzle", (0.07, 0.065, 0.06), metallic=0.85, roughness=0.3),
            "nozzle_throat": Material("cap_nozzle_throat", (0.02, 0.02, 0.02), metallic=0.8, roughness=0.45, emissive=(0.55, 0.75, 1.0),
                                      emissive_strength=4.0),
            "barrel": Material("cap_barrel", (0.09, 0.09, 0.095), metallic=0.8, roughness=0.3),
            "bore": Material("cap_bore", (0.01, 0.01, 0.01)),
            "interior": Material("cap_interior", (0.02, 0.02, 0.022)),
            "rcs": Material("cap_fitting", (0.08, 0.08, 0.085), metallic=0.7, roughness=0.35),
        },
        panel_size_m=0.5,
        panel_line_width_m=0.035,
        panel_line_darkness=0.6,
        panel_tint_jitter=0.06,
        edge_wear=0.3,
        streaks=0.14,
        grime=0.06,
        extra={"bare_metal": 0.25, "smudge": 0.15, "smudge_scale_m": 0.6, "speckle": 0.04, "streak_length_m": 0.35},
    )


FRAMEWORK_GREY = CapitalStyle("framework_grey", _grey())

__all__ = ["FRAMEWORK_GREY", "HEX_TILE_CELLS", "CapitalStyle", "HexGrid", "PanelMosaic", "Seamless", "Skin"]
