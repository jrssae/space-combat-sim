"""Weapon parts: gun barrels.

Local frame: a barrel runs along -Z from its ``mount`` (z = 0) to the ``muzzle`` (z = -length),
so it points forward when placed unrotated on a ship.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from ..core.geometry import Mesh, lathe, rotation_x, tapered_box
from ..styles import Style
from . import Anchor, Collision, Part


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


@dataclass(frozen=True)
class GunMountSpec:
    """A ventral gun pod: a tapered housing along Z (centred on the origin, front section
    ``size_front`` = (width, height) at ``-length/2``, back section ``size_back`` shifted by
    ``offset_back``) with a pair of barrels at ``x = +-barrel_x``, ``y = barrel_y``, mounted at
    ``barrel_mount_z`` inside the housing and pointing forward (-Z). ``mass_kg`` is the total."""

    length: float = 2.2
    size_front: tuple[float, float] = (1.3, 0.55)
    size_back: tuple[float, float] = (1.6, 0.6)
    offset_back: tuple[float, float] = (0.0, -0.5)
    barrel: BarrelSpec = BarrelSpec(
        length=1.75, radius=0.1, base_radius=0.15, base_length=0.5
    )
    barrel_x: float = 0.45
    barrel_y: float = -0.08
    barrel_mount_z: float = 0.6
    mass_kg: float = 2_000.0

    def __post_init__(self) -> None:
        if self.barrel_x <= self.barrel.base_radius:
            raise ValueError("the barrels would overlap")
        if self.barrel_mount_z - self.barrel.length >= -0.5 * self.length:
            raise ValueError("the barrels must reach out of the housing's front")


def gun_mount(spec: GunMountSpec, style: Style) -> Part:
    """Housing (``hull_panel``, dark ends) plus two barrels. Anchors: ``muzzle_left`` (x < 0),
    ``muzzle_right``, ``center``, ``front``. One box collision primitive (the bounds)."""
    housing = tapered_box(
        spec.length,
        spec.size_front,
        spec.size_back,
        style.material("hull_panel"),
        offset_b=spec.offset_back,
        materials_by_face={
            "front": style.material("hull_dark"),
            "back": style.material("hull_dark"),
        },
    )
    meshes = [housing]
    anchors = {
        "center": Anchor([0.0, 0.0, 0.0]),
        "front": Anchor([0.0, 0.0, -0.5 * spec.length], [0.0, 0.0, -1.0]),
    }
    for name, x in (("right", spec.barrel_x), ("left", -spec.barrel_x)):
        b = gun_barrel(spec.barrel, style).translated(
            [x, spec.barrel_y, spec.barrel_mount_z]
        )
        meshes.append(b.mesh)
        anchors[f"muzzle_{name}"] = b.anchor("muzzle")
    mesh = Mesh.concatenate(meshes)
    lo, hi = mesh.bounds()
    return Part(
        "gun_mount",
        mesh,
        anchors=anchors,
        collision=[Collision("box", 0.5 * (lo + hi), size=hi - lo, name="gun_mount")],
        mass_kg=spec.mass_kg,
    )
