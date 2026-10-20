"""Weapon parts: gun barrels.

Local frame: a barrel runs along -Z from its ``mount`` (z = 0) to the ``muzzle`` (z = -length),
so it points forward when placed unrotated on a ship.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from ..core.geometry import lathe, rotation_x
from ..styles import Style
from . import Anchor, Part


@dataclass(frozen=True)
class BarrelSpec:
    length: float = 1.9
    radius: float = 0.11
    base_radius: float = 0.16
    base_length: float = 0.55
    bore_radius: float = 0.06
    bore_depth: float = 0.06
    segments: int = 20
    mass_kg: float = 700.0


def gun_barrel(spec: BarrelSpec, style: Style) -> Part:
    """Stepped barrel with a recessed dark bore at the muzzle."""
    barrel, bore = style.material("barrel"), style.material("bore")
    # Built along +Z (lathe convention: profile runs front to back), then turned to point -Z.
    # Profile from the mount end (z = 0, thick base) to the muzzle (z = length); the last two
    # segments run back inside the tube: a 6 cm deep dark bore.
    profile = [
        (0.0, 0.0),
        (0.0, spec.base_radius),
        (spec.base_length, spec.base_radius),
        (spec.base_length, spec.radius),
        (spec.length, spec.radius),
        (spec.length, spec.bore_radius),
        (spec.length - spec.bore_depth, spec.bore_radius),
        (spec.length - spec.bore_depth, 0.0),
    ]
    materials = [barrel, barrel, barrel, barrel, barrel, bore, bore]
    mesh = lathe(profile, spec.segments, materials, creases={1, 2, 3, 4, 5, 6})
    mesh = mesh.transformed(rotation_x(math.pi))  # +Z -> -Z (muzzle forward), keeps handedness
    return Part(
        "gun_barrel",
        mesh,
        anchors={
            "muzzle": Anchor([0.0, 0.0, -spec.length], [0.0, 0.0, -1.0]),
            "mount": Anchor([0.0, 0.0, 0.0], [0.0, 0.0, 1.0]),
        },
        mass_kg=spec.mass_kg,
    )
