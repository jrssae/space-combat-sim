"""The Earth Alliance Asimov-class liner's style (M10-T53): a civilian liner in the fleet's capital machinery
(``ea_capital.capital_style``: the same roles, blue-white engines), in its own paint.

The show (``references/show/m10/ea_asimov/``, gitignored) paints its sphere white with a green ring round the forward face, as wide as a bar, and
green bars running aft from it, a dark grey band of blue window rows near its aft edge, and its command spine, face and engines
in grey. Roles: ``hull`` the sphere's white,
``stripe`` the band colour, ``hull_panel`` the grey of the spine, the face and the engines, ``hull_dark`` the window band and the
darker fittings; ``window`` the lit windows' blue.

**Skin** (the maintainer, Q87): no panel mosaic and no seam lines, but the Agamemnon model's manner, made here in code: the paint
wanders in tone over big plates, small darker patches at three sizes overlap on it, a few low plates stand proud of it, and fine
scratches run over everything (:class:`PatchSkin`). The Agamemnon files are a style reference only; nothing is taken from them.

**Liveries** (Q86): the ring is baked in the green and the game recolours it per ship (``band_tint`` in the manifest's surface
entries; ``BandTintMaterial`` in the game picks the livery from the ship's name, ``data/ships/names.json``), so every liner shares
one atlas. :data:`LIVERIES` lists them; the green is the first and the default.

**Bars** (Q95): a liner has six or eight, by its name and apart from its colour. They are in no atlas: the band (and the skin ahead of it, back from the ring) is baked white and
the game's shader draws the ship's bars on it (``band_bars`` in the band's surface entries says where).

The look (:data:`LOOK`) is the maintainer's choice from the A/B/C sheet (Q95): B's warmer white and denser, darker patches with
C's window rows on the band.
"""

from __future__ import annotations

import dataclasses
import math
from collections.abc import Mapping
from dataclasses import dataclass

import numpy as np

from ..core.color import capture_albedo
from ..core.geometry import Material
from ..core.seams import Feature, PatchPlates, Plates, Relief, SeamLayout, _keyed_hash, _smooth
from ..parts import ea_asimov as asi
from ..parts.ea_asimov import Pattern
from .capital import CapitalStyle
from .ea_capital import Look, bay_metal_materials, capital_style
from .ea_civilian import lin

PREFIX = "eaa"
WINDOW_BLUE = 0x7FB8FF  # the show's pale blue window light
WINDOW_STRENGTH = 2.2
NAMES_TYPE = "ea_asimov"  # the names list a liner's livery is read from


@dataclass(frozen=True)
class Livery:
    """One band colour (sRGB) a liner may wear."""

    key: str
    title: str
    band: int


# The show's green first (the default and the first ship's), then colours that stay apart from it and from each other on the white
# and in shadow.
LIVERIES: tuple[Livery, ...] = (
    Livery("green", "the show's green", 0x2FA03A),
    Livery("blue", "deep blue", 0x2450B8),
    Livery("maroon", "maroon", 0x8C2232),
    Livery("amber", "amber", 0xD89A1E),
    Livery("teal", "teal", 0x14918C),
)


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


PATTERN = Pattern()
PAINT = {"hull": 0xD4D1C8, "hull_panel": 0x84878A, "hull_dark": 0x3E4044, "stripe": LIVERIES[0].band}
SKIN = PatchSkin(tone=0.06, patches=(Patches((14.0, 9.0), 0.35, ((0.6, 0.08), (0.4, 0.16))), Patches((5.0, 3.2), 0.32, ((0.7, 0.07), (0.3, 0.14))),
                                     Patches((1.8, 1.2), 0.25, ((1.0, 0.07),))), proud=0.18, scratches=0.35)
LOOK = Look("liner", "warm white, dense darker patches, window rows on the band", PAINT, plate_tone=SKIN.tone, plate_grime=0.03, metallic=0.2,
            edge_wear=0.15, streaks=0.06, grime=0.04)


def _linear(srgb: int) -> list[float]:
    return [round(float(c), 5) for c in capture_albedo(srgb)]


def band_tint() -> dict:
    """The manifest's ``band_tint`` entry: the baked band colour, every livery's and the white the bars are drawn over (linear),
    how many bars a ship may have, and the names list the game picks a ship's livery and bar count from."""
    return {"base": _linear(PAINT["stripe"]), "liveries": [livery.key for livery in LIVERIES], "colours": [_linear(livery.band) for livery in LIVERIES],
            "white": _linear(PAINT["hull"]), "bar_counts": list(PATTERN.bar_counts), "names_type": NAMES_TYPE}


def band_bars() -> dict:
    """The band's ``band_bars`` entry: where the game's shader draws the bars, in the band's own frame (its pivot, the sphere's
    centre): the sphere's radius, the span along the axis from the ring to the aft groove, and a bar's half width."""
    span = (PATTERN.ring_end_z - asi.SPHERE_Z, asi.AFT_SEAM_Z - asi.SEAM_WIDTH - asi.SPHERE_Z)
    return {"radius_m": asi.SPHERE_R, "span_m": [round(z, 3) for z in span], "half_width_m": PATTERN.bar_half_m}


def ea_asimov(livery: Mapping[str, int] | None = None) -> CapitalStyle:
    """The liner's style, any role repainted by ``livery`` (a build in one fixed band colour)."""
    style = capital_style(LOOK, "ea_asimov", PREFIX, SKIN, livery)
    window = Material(f"{PREFIX}_window", capture_albedo(0x1A2A40), emissive=lin(WINDOW_BLUE), emissive_strength=WINDOW_STRENGTH)
    materials = {**style.style.materials, "window": window, **bay_metal_materials(PREFIX)}  # the shuttle bay's hall, as the fleet's
    extra = {**style.style.extra, "speckle": 0.06, "smudge": 0.1, "bare_metal": 0.05}
    return dataclasses.replace(style, style=dataclasses.replace(style.style, materials=materials, extra=extra), surface={"band_tint": band_tint()})


__all__ = ["LIVERIES", "LOOK", "NAMES_TYPE", "PAINT", "PATTERN", "SKIN", "Livery", "PatchSkin", "Patches", "Scratches", "band_bars", "band_tint", "ea_asimov"]
