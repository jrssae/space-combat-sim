"""Capital hull parts (M10-T05, D12.1): hull sections lofted through stations, prows and armour plating.

Authored frame: x to starboard, y up, z aft. A hull section runs along z through :class:`Station` cross-sections, each a
rectangle with its corners cut (an octagon), flat faced and hard edged as the Earth Alliance's and the Narn's hulls are;
faces looking up take the deck paint, faces looking down the keel's. Its collision is one convex hull per span between two
stations, so a tapering or stepped section is followed closely.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass
from itertools import pairwise

import numpy as np

from ..core import collision as col
from ..core.geometry import Material, Mesh, box
from ..styles import Style
from .capital import SKIN_FITTING, Module, module
from .raider_carrier import flat
from .solids import Solid

DECK_DOT = 0.6  # a face whose normal is this much up (or down) is deck (or keel)


@dataclass(frozen=True)
class Station:
    """One cross-section of a hull section at ``z``: half its width and height, the cut of its corners (m, along each side)
    and how far its centre sits above the section's axis."""

    z: float
    half_width: float
    half_height: float
    chamfer: float
    y: float = 0.0

    def __post_init__(self) -> None:
        if self.half_width <= 0.0 or self.half_height <= 0.0:
            raise ValueError("a station needs a width and a height")
        if not 0.0 < self.chamfer < min(self.half_width, self.half_height):
            raise ValueError("a station's chamfer must be above zero and under its half width and half height")

    def outline(self) -> np.ndarray:
        """The octagon's corners ``(8, 3)``, counter-clockwise seen from aft."""
        w, h, c = self.half_width, self.half_height, self.chamfer
        xy = [(w, -h + c), (w, h - c), (w - c, h), (-w + c, h), (-w, h - c), (-w, -h + c), (-w + c, -h), (w - c, -h)]
        return np.array([(x, y + self.y, self.z) for x, y in xy])


@dataclass(frozen=True)
class HullRoles:
    """The style's material roles a hull section is painted in."""

    side: str = "hull"
    deck: str = "hull_panel"
    keel: str = "hull_dark"
    cap: str = "hull_dark"


def _role_of(normal: np.ndarray, roles: HullRoles) -> str:
    if normal[1] > DECK_DOT:
        return roles.deck
    return roles.keel if normal[1] < -DECK_DOT else roles.side


def _loft_solid(stations: Sequence[Station]) -> Solid:
    """The section's volume: at each z the octagon between its two stations."""
    zs = np.array([s.z for s in stations])
    w, h, c, y0 = (np.array([getattr(s, k) for s in stations]) for k in ("half_width", "half_height", "chamfer", "y"))

    def test(p: np.ndarray, margin: float) -> np.ndarray:
        z = p[:, 2]
        wi, hi, ci = np.interp(z, zs, w), np.interp(z, zs, h), np.interp(z, zs, c)
        x, y = np.abs(p[:, 0]), np.abs(p[:, 1] - np.interp(z, zs, y0))
        inside = (x < wi - margin) & (y < hi - margin) & (x + y < wi + hi - ci - margin * math.sqrt(2.0))
        return inside & (z > zs[0] + margin) & (z < zs[-1] - margin)

    reach_y = float(np.max(np.abs(y0) + h))
    return Solid(test, ((-float(w.max()), -reach_y, float(zs[0])), (float(w.max()), reach_y, float(zs[-1]))))


def hull_section(name: str, stations: Sequence[Station], style: Style, roles: HullRoles = HullRoles(),
                 caps: tuple[bool, bool] = (True, True)) -> Module:
    """A hull section through ``stations`` (bow to stern, z rising). ``caps`` closes its bow and stern ends; an end left
    open is where the next section, a launch bay or an engine block joins it."""
    if len(stations) < 2 or any(b.z <= a.z for a, b in pairwise(stations)):
        raise ValueError(f"hull section {name!r} needs two stations or more, z rising")
    rings = [s.outline() for s in stations]
    inside = np.mean([r.mean(axis=0) for r in rings], axis=0)
    faces: list[Mesh] = []
    for a, b in pairwise(rings):
        mid = 0.5 * (a.mean(axis=0) + b.mean(axis=0))
        for k in range(8):
            quad = np.array([a[k], a[(k + 1) % 8], b[(k + 1) % 8], b[k]])
            normal = np.cross(quad[1] - quad[0], quad[3] - quad[0])
            if float(normal @ (quad.mean(axis=0) - mid)) < 0.0:
                normal = -normal
            faces.append(flat(quad, style.material(_role_of(normal / np.linalg.norm(normal), roles)), mid))
    for ring, closed in zip((rings[0], rings[-1]), caps, strict=True):
        if closed:
            faces.append(flat(ring, style.material(roles.cap), inside))
    shapes = [col.hull(f"{name}_{k:02d}", np.concatenate([a, b])) for k, (a, b) in enumerate(pairwise(rings))]
    return module(name, Mesh.concatenate(faces), shapes, solid=_loft_solid(stations))


def prow(name: str, base: Station, length: float, style: Style, nose: tuple[float, float] = (0.25, 0.4), drop: float = 0.0,
         roles: HullRoles = HullRoles()) -> Module:
    """A bow tapering forward from ``base`` over ``length`` to a blunt nose ``nose`` times the base's width and height,
    its centre ``drop`` metres lower at the tip. The stern end is left open for the hull behind it."""
    k = min(nose)
    tip = Station(base.z - length, base.half_width * nose[0], base.half_height * nose[1], base.chamfer * k, base.y - drop)
    mid = Station(base.z - 0.45 * length, base.half_width * (0.45 + 0.55 * nose[0]), base.half_height * (0.45 + 0.55 * nose[1]),
                  base.chamfer * (0.45 + 0.55 * k), base.y - 0.55 * drop)
    return hull_section(name, (tip, mid, base), style, roles, caps=(True, False))


def armour_plates(name: str, size: tuple[float, float], grid: tuple[int, int], thickness: float, style: Style, gap: float = 0.4,
                  role: str = "hull_panel") -> Module:
    """Armour standing proud of a hull face: ``grid`` slabs (across, along) over ``size`` metres, ``gap`` between them. Built
    on a mount (the face's normal +y, the slabs' rows along z); stand it with ``mounted``."""
    cols, rows = grid
    if cols < 1 or rows < 1 or thickness <= 0.0:
        raise ValueError(f"armour {name!r} needs a grid and a thickness")
    w, d = (size[0] - gap * (cols - 1)) / cols, (size[1] - gap * (rows - 1)) / rows
    if w <= 0.0 or d <= 0.0:
        raise ValueError(f"armour {name!r}: the gaps leave no slab")
    material: Material = style.material(role)
    slabs = [box((w, thickness, d), material, ((i - 0.5 * (cols - 1)) * (w + gap), 0.5 * thickness, (j - 0.5 * (rows - 1)) * (d + gap)))
             for i in range(cols) for j in range(rows)]
    shape = col.box(name, (0.0, 0.5 * thickness, 0.0), (size[0], thickness, size[1]))
    return module(name, Mesh.concatenate(slabs), [shape], skin=SKIN_FITTING)


__all__ = ["HullRoles", "Station", "armour_plates", "hull_section", "prow"]
