"""Design languages as parameter sets (docs/architecture.md section 14.8).

A :class:`Style` names materials by *role* (``hull``, ``stripe``, ``canopy_glass`` ...) so parts
never hard-code a colour, and carries the surface-detail parameters (panel grid, line width,
per-panel tint jitter) that ``shade_panels`` bakes into the albedo of ``paneled`` materials, plus
the wear, groove and hatch parameters the texture maps use (M4-T30a, ``core/textures.py``).
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
    # The texture maps (M4-T30a): panel grooves and hatches in the normal map, chipped edges, streaks and grime in the colour.
    groove_depth_m: float = 0.012
    hatch_fraction: float = 0.18  # share of panels that carry an inset hatch
    hatch_depth_m: float = 0.004
    edge_wear: float = 0.55  # how much of the sharp edges show bare metal, 0..1
    edge_wear_width_m: float = 0.035
    streaks: float = 0.12  # darkening of the streaks trailing aft from the panel lines, 0..1
    grime: float = 0.04  # +- relative albedo of the low-frequency grime
    grime_scale_m: float = 0.9
    soot: float = 0.85  # how black the soot behind a nozzle gets, 0..1
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
        lattice = self.panel_lattice(np.asarray(positions, dtype=float)[mask], np.asarray(normals, dtype=float)[mask], phase)
        factor = np.where(lattice["on_line"], self.panel_line_darkness, lattice["tint"])
        albedo[mask] *= factor[:, None]
        return albedo

    def panel_lattice(
        self, positions: np.ndarray, normals: np.ndarray, phase: tuple[float, float, float] = (0.0, 0.0, 0.0)
    ) -> dict[str, np.ndarray]:
        """Where each point falls in the panel lattice ``shade_panels`` paints: its cell (``cu``, ``cv``, ``drop``), its
        place in the cell (``fu``, ``fv`` in 0..1, ``edge_m`` the distance to the nearest line centre), the line and tint
        ``shade_panels`` applies, and the hatch some cells carry (``hatch``, ``hatch_edge_m`` the distance to its border)."""
        p = np.asarray(positions, dtype=float) + np.asarray(phase, dtype=float)
        n = np.abs(np.asarray(normals, dtype=float))
        drop = np.argmax(n, axis=1)  # axis closest to the normal
        axes = np.array([[1, 2], [0, 2], [0, 1]])[drop]  # the two tangent-ish axes
        u = np.take_along_axis(p, axes[:, 0:1], axis=1)[:, 0] / self.panel_size_m
        v = np.take_along_axis(p, axes[:, 1:2], axis=1)[:, 0] / self.panel_size_m
        cu, cv = np.floor(u), np.floor(v)
        fu, fv = u - cu, v - cv
        du = np.minimum(fu, 1.0 - fu) * self.panel_size_m
        dv = np.minimum(fv, 1.0 - fv) * self.panel_size_m
        edge_m = np.minimum(du, dv)
        on_line = edge_m < 0.5 * self.panel_line_width_m
        cell_u, cell_v = cu.astype(np.int64), cv.astype(np.int64)
        tint = 1.0 + self.panel_tint_jitter * (2.0 * _hash01(cell_u, cell_v, drop) - 1.0)
        # An inset hatch in some cells: a rounded-off rectangle well inside the lines.
        has_hatch = _hash01(cell_u + 977, cell_v - 331, drop + 7) < self.hatch_fraction
        hx = (np.abs(fu - 0.5) - 0.3) * self.panel_size_m
        hy = (np.abs(fv - 0.5) - 0.2) * self.panel_size_m
        outside = np.hypot(np.maximum(hx, 0.0), np.maximum(hy, 0.0)) + np.minimum(np.maximum(hx, hy), 0.0)
        hatch = has_hatch & (outside < 0.0)
        return {
            "drop": drop, "cu": cell_u, "cv": cell_v, "fu": fu, "fv": fv, "u": u, "v": v,
            "edge_m": edge_m, "on_line": on_line, "tint": tint,
            "hatch": hatch, "hatch_edge_m": np.where(has_hatch, np.abs(outside), np.inf),
        }
