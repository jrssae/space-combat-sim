"""The sheen layer's parameters (M10-T06, D12.2; docs/assets-capital.md, "Sheen layer").

The sheen is a layer the game's shader lays over a hull's four maps (``assets/shaders/hull_sheen_layer.gdshaderinc``), as
the liveries are a layer: nothing is baked, a style only names numbers. A :class:`Sheen` is those numbers; a capital style
hands them over as ``CapitalStyle.surface = {"sheen": sheen.to_json()}`` and the framework writes them on every opaque
surface of the manifest, where ``HullSheenMaterial`` reads them.

Three effects, each off at zero:

* **iridescence**: a colour that depends on where the surface is seen from, mixed into the paint towards the rim. The
  colour over all directions is a spherical-harmonic function (nine RGB coefficients, :func:`sh_from_lobes`), so it shifts
  smoothly as the ship or the camera turns;
* **pattern**: mottling or scales in the hull's own space, which may drift (the Shadows' moving skin). It darkens the
  paint, shifts its roughness and breaks the iridescence up;
* **glow**: a faint light of the hull's own (the Vorlons' bioluminescence), even or gathered in the pattern's veins,
  slowly pulsing.
"""

from __future__ import annotations

import dataclasses
import math
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

import numpy as np

RGB = tuple[float, float, float]
SH_COUNT = 9
FIT_DIRECTIONS = 2048


def sh_basis(directions: np.ndarray) -> np.ndarray:
    """The nine real spherical harmonics up to band 2 at unit ``directions``, ``(n, 9)``; the shader's order."""
    d = np.asarray(directions, dtype=float).reshape(-1, 3)
    x, y, z = d[:, 0], d[:, 1], d[:, 2]
    return np.stack([np.full(len(d), 0.282095), 0.488603 * y, 0.488603 * z, 0.488603 * x, 1.092548 * x * y, 1.092548 * y * z,
                     0.315392 * (3.0 * z * z - 1.0), 1.092548 * x * z, 0.546274 * (x * x - y * y)], axis=1)


def sphere_directions(count: int = FIT_DIRECTIONS) -> np.ndarray:
    """``count`` directions spread evenly over the sphere (a Fibonacci spiral)."""
    k = np.arange(count) + 0.5
    z = 1.0 - 2.0 * k / count
    turn = k * math.pi * (3.0 - math.sqrt(5.0))
    r = np.sqrt(1.0 - z * z)
    return np.stack([r * np.cos(turn), r * np.sin(turn), z], axis=1)


def sh_from_lobes(ambient: RGB, lobes: Sequence[tuple[Sequence[float], RGB, float]]) -> tuple[RGB, ...]:
    """The coefficients of a colour over directions: ``ambient`` everywhere plus, for each lobe ``(direction, colour,
    width)``, its colour round its direction, fading to nothing ``width`` degrees away. Nine coefficients cannot draw a
    lobe narrower than about 50 degrees; the fit is the closest they come."""
    d = sphere_directions()
    target = np.tile(np.asarray(ambient, dtype=float), (len(d), 1))
    for direction, colour, width_deg in lobes:
        axis = np.asarray(direction, dtype=float)
        axis = axis / float(np.linalg.norm(axis))
        away = np.degrees(np.arccos(np.clip(d @ axis, -1.0, 1.0)))
        weight = np.clip(1.0 - away / width_deg, 0.0, 1.0)
        target += (weight * weight * (3.0 - 2.0 * weight))[:, None] * np.asarray(colour, dtype=float)
    coefficients = np.linalg.lstsq(sh_basis(d), target, rcond=None)[0]
    return tuple(tuple(round(float(c), 5) for c in row) for row in coefficients)


def sh_colour(coefficients: Sequence[RGB], directions: np.ndarray) -> np.ndarray:
    """The colour the coefficients give at ``directions``, as the shader works it out (never below zero)."""
    return np.maximum(sh_basis(directions) @ np.asarray(coefficients, dtype=float), 0.0)


@dataclass(frozen=True)
class Sheen:
    """A style's sheen layer. Colours are linear RGB; every strength is 0 for off.

    Iridescence: ``iri_sh`` the colour by direction; ``iri_strength`` how much of the paint it replaces at the rim and
    ``iri_base`` face on; ``iri_power`` how late it rises towards the rim; ``iri_view`` whether the direction is the
    surface's own facing (0: the colours are fixed on the hull) or the mirrored view (1: they slide as the camera moves);
    ``iri_metal`` how much the lit iridescence mirrors its colour (a metallic lustre) instead of scattering it.

    Pattern: ``pattern_scale_m`` the size of a blotch; ``pattern_cells`` 0 for soft mottling, 1 for scales;
    ``pattern_edge`` how hard the blotches' edges are; ``pattern_cover`` the share of the skin they take;
    ``pattern_dark`` how much they darken the paint; ``pattern_tint`` the colour they pull the paint towards (by
    ``pattern_dark``); ``pattern_iri`` how much they dim the iridescence; ``pattern_rough`` the roughness they add;
    ``pattern_speed_mps`` how fast the pattern drifts over the hull.

    Glow: ``glow_colour`` times ``glow_energy`` is the hull's own light; ``glow_veins`` 0 for an even glow, 1 for the
    seams between blotches alone; ``glow_rim`` the extra at the rim; ``glow_pulse_s`` its breathing period (0: steady)
    and ``glow_pulse`` how deep it breathes.

    ``coat`` is the share of the game's clear coat (``settings.hull_sheen``, the painted hulls' gloss) this skin takes: a
    black skin with the whole coat reads grey under the sun."""

    iri_sh: tuple[RGB, ...] = ((0.0, 0.0, 0.0),) * SH_COUNT
    iri_strength: float = 0.0
    iri_base: float = 0.0
    iri_power: float = 3.0
    iri_view: float = 0.5
    iri_metal: float = 0.0
    pattern_scale_m: float = 1.0
    pattern_cells: float = 0.0
    pattern_edge: float = 0.5
    pattern_cover: float = 0.5
    pattern_dark: float = 0.0
    pattern_tint: RGB = (0.0, 0.0, 0.0)
    pattern_iri: float = 0.0
    pattern_rough: float = 0.0
    pattern_speed_mps: float = 0.0
    glow_colour: RGB = (0.0, 0.0, 0.0)
    glow_energy: float = 0.0
    glow_veins: float = 0.0
    glow_rim: float = 0.0
    glow_pulse_s: float = 0.0
    glow_pulse: float = 0.0
    coat: float = 1.0

    def __post_init__(self) -> None:
        if len(self.iri_sh) != SH_COUNT or any(len(c) != 3 for c in self.iri_sh):
            raise ValueError(f"a sheen's iridescence is {SH_COUNT} RGB coefficients")
        if self.pattern_scale_m <= 0.0:
            raise ValueError("a sheen's pattern needs a size")
        for name in ("iri_strength", "iri_base", "iri_view", "iri_metal", "pattern_cells", "pattern_edge", "pattern_cover", "pattern_dark",
                     "pattern_iri", "glow_veins", "glow_pulse", "coat"):
            if not 0.0 <= float(getattr(self, name)) <= 1.0:
                raise ValueError(f"a sheen's {name} is a share, 0 to 1")

    def but(self, **changes: Any) -> Sheen:
        """This sheen with some numbers changed (an option of a look sheet)."""
        return dataclasses.replace(self, **changes)

    def to_json(self) -> dict[str, Any]:
        """The manifest's ``sheen`` entry: every number by the name the shader's uniform has."""
        out: dict[str, Any] = {}
        for f in dataclasses.fields(self):
            value = getattr(self, f.name)
            if f.name == "iri_sh":
                out[f.name] = [[float(c) for c in row] for row in value]
            elif isinstance(value, tuple):
                out[f.name] = [float(c) for c in value]
            else:
                out[f.name] = float(value)
        return out


__all__ = ["SH_COUNT", "Sheen", "sh_basis", "sh_colour", "sh_from_lobes", "sphere_directions"]
