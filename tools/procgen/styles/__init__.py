"""Design languages as parameter sets (docs/architecture.md section 14.8).

A :class:`Style` names materials by *role* (``hull``, ``stripe``, ``canopy_glass`` ...) so parts
never hard-code a colour, and carries the surface-detail parameters (panel grid, line width,
per-panel tint jitter) that ``shade_panels`` bakes into the albedo of ``paneled`` materials.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field

import numpy as np

from ..core.geometry import Material

REQUIRED_ROLES: tuple[str, ...] = (
    "hull",
    "hull_dark",
    "hull_panel",
    "stripe",
    "hazard",
    "hazard_dark",
    "canopy_glass",
    "canopy_frame",
    "nozzle",
    "nozzle_throat",
    "barrel",
    "bore",
    "interior",
    "rcs",
)


def _hash01(*ints: np.ndarray) -> np.ndarray:
    """Deterministic per-cell pseudo-random number in [0, 1) from integer coordinates."""
    h = np.zeros_like(np.asarray(ints[0], dtype=np.uint64))
    for k, value in enumerate(ints):
        v = np.asarray(value, dtype=np.int64).astype(np.uint64)
        h ^= v * np.uint64((73856093, 19349663, 83492791, 49979687)[k % 4])
        h = (h ^ (h >> np.uint64(13))) * np.uint64(0x5BD1E995)
        h ^= h >> np.uint64(15)
    return (h & np.uint64(0xFFFFFF)).astype(float) / float(0x1000000)


@dataclass(frozen=True)
class Style:
    name: str
    materials: Mapping[str, Material]
    panel_size_m: float = 0.6
    panel_line_width_m: float = 0.03
    panel_line_darkness: float = 0.55  # albedo multiplier on a panel line
    panel_tint_jitter: float = 0.05  # +- relative albedo per panel
    stripe_fraction: float = 0.68  # along a pod, 0 = front, 1 = rear
    stripe_width_m: float = 0.3
    extra: Mapping[str, float] = field(default_factory=dict)

    def __post_init__(self) -> None:
        missing = [role for role in REQUIRED_ROLES if role not in self.materials]
        if missing:
            raise ValueError(f"style {self.name!r} lacks material roles {missing}")

    def material(self, role: str) -> Material:
        return self.materials[role]

    def shade_panels(
        self,
        albedo: np.ndarray,
        positions: np.ndarray,
        normals: np.ndarray,
        paneled: np.ndarray,
        phase: tuple[float, float, float] = (0.0, 0.0, 0.0),
    ) -> np.ndarray:
        """Bake panel lines and per-panel tint into ``albedo`` where ``paneled`` is true.

        The panel grid is the world-aligned lattice of ``panel_size_m`` cells, projected along
        the axis closest to the normal (so a cylinder's grid follows its axis and the hull's
        grid follows the hull). ``phase`` shifts the lattice so neighbouring parts do not line
        up. Fully deterministic (cell hashes, no rng).
        """
        albedo = np.array(albedo, dtype=float, copy=True)
        mask = np.asarray(paneled, dtype=bool)
        if not mask.any():
            return albedo
        p = np.asarray(positions, dtype=float)[mask] + np.asarray(phase, dtype=float)
        n = np.abs(np.asarray(normals, dtype=float)[mask])
        drop = np.argmax(n, axis=1)  # axis closest to the normal
        axes = np.array([[1, 2], [0, 2], [0, 1]])[drop]  # the two tangent-ish axes
        u = np.take_along_axis(p, axes[:, 0:1], axis=1)[:, 0] / self.panel_size_m
        v = np.take_along_axis(p, axes[:, 1:2], axis=1)[:, 0] / self.panel_size_m
        cu, cv = np.floor(u), np.floor(v)
        du = np.minimum(u - cu, 1.0 - (u - cu)) * self.panel_size_m
        dv = np.minimum(v - cv, 1.0 - (v - cv)) * self.panel_size_m
        on_line = np.minimum(du, dv) < 0.5 * self.panel_line_width_m
        tint = 1.0 + self.panel_tint_jitter * (2.0 * _hash01(cu.astype(np.int64), cv.astype(np.int64), drop) - 1.0)
        factor = np.where(on_line, self.panel_line_darkness, tint)
        albedo[mask] *= factor[:, None]
        return albedo
