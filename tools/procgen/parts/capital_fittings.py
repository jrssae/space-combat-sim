"""Capital fittings (M10-T05, D12.1): rotating sections, antennae and lamps.

* A rotating section is built about the z axis with its middle at the origin: a collar round the hull and arms carrying
  habitat blocks. It turns as a piece of its own (``core/capital.py``, ``PieceSpec``: a pivot on the axis and a spin), so
  the generator puts it in a section of that piece and the game drives it as an ``AnimatableBody3D`` (the station's drum).
* An antenna and a lamp are built on a mount (+y the normal, -z the front); stand them with ``Module.mounted``. A lamp's
  light hardpoint (``hardpoints.lights[]``) has ``forward`` the way it shines and ``params``: ``role`` (``port``,
  ``starboard``, ``top``, ``beacon`` or ``flood``), ``colour`` (linear RGB) and ``range_m``.
"""

from __future__ import annotations

import math
from collections.abc import Sequence

import numpy as np

from ..core import collision as col
from ..core.geometry import Material, Mesh, box, lathe, rotation_x, rotation_z, tapered_box
from ..styles import Style
from .capital import LIGHT, MARK, SKIN_FITTING, SKIN_HULL, SKIN_NONE, Hardpoint, Module, module
from .raider_carrier import tube

LIGHT_ROLES = ("port", "starboard", "top", "beacon", "flood")
COLLAR_SIDES = 16


def rotating_section(name: str, collar_m: tuple[float, float, float], arm_m: tuple[float, float], block_m: tuple[float, float, float],
                     style: Style, arms: int = 2) -> Module:
    """A rotating section: a collar (inner radius, outer radius, length) round the axis, ``arms`` arms (width, reach from
    the axis to the block's inner face) and a habitat block (width, height along the arm, length along the axis) on each.
    The collar's bore is left open for the hull that runs through it."""
    r_in, r_out, length = collar_m
    arm_w, reach = arm_m
    bw, bh, bl = block_m
    if not 0.0 < r_in < r_out or length <= 0.0 or reach <= r_out or arms < 1 or min(arm_w, bw, bh, bl) <= 0.0:
        raise ValueError(f"rotating section {name!r}: the collar, the arms and the blocks need sizes, the arms reaching past the collar")
    hull, dark = style.material("hull"), style.material("hull_dark")
    half = 0.5 * length
    collar = lathe([(-half, r_in), (-half, r_out), (half, r_out), (half, r_in), (-half, r_in)], COLLAR_SIDES, [dark, hull, dark, dark],
                   creases={1, 2, 3})
    grow = 1.0 / math.cos(math.pi / COLLAR_SIDES)
    meshes = [collar]
    shapes = col.ring_sectors(f"{name}_collar", (0.0, 0.0, 0.0), (0.0, 0.0, 1.0), r_in, r_out * grow, -half, half, 12)
    for k in range(arms):
        turn = rotation_z(2.0 * math.pi * k / arms)
        arm_len = reach - r_out + 0.3 * (r_out - r_in)
        arm_mid = (0.0, reach - 0.5 * arm_len, 0.0)
        arm = box((arm_w, arm_len, 0.6 * min(length, bl)), dark, arm_mid).transformed(turn)
        block = tapered_box(bl, (bw, bh), (bw, bh), hull, center=(0.0, reach + 0.5 * bh, 0.0),
                            materials_by_face={"top": style.material("hull_panel")}).transformed(turn)
        meshes += [arm, block]
        shapes += [col.box(f"{name}_arm_{k + 1}", arm_mid, (arm_w, arm_len, 0.6 * min(length, bl))).transformed(turn),
                   col.box(f"{name}_block_{k + 1}", (0.0, reach + 0.5 * bh, 0.0), (bw, bh, bl)).transformed(turn)]
    return module(name, Mesh.concatenate(meshes), shapes, skin=SKIN_HULL)


def antenna(name: str, height_m: float, style: Style, dish_m: float = 0.0, spars: int = 2) -> Module:
    """An antenna: a mast ``height_m`` tall with ``spars`` cross spars, and a dish ``dish_m`` across at its top when given."""
    if height_m <= 0.0 or dish_m < 0.0 or spars < 0:
        raise ValueError(f"antenna {name!r} needs a height")
    r = max(0.012 * height_m, 0.08)
    metal = style.material("rcs")
    meshes = [tube((0.0, 0.0, 0.0), (0.0, height_m, 0.0), [(0.0, 1.6 * r), (0.3 * height_m, r), (height_m, 0.6 * r)], 6, metal)]
    shapes = [col.capsule_between(name, (0.0, r, 0.0), (0.0, height_m - r, 0.0), 1.6 * r)]
    for k in range(spars):
        y = height_m * (0.45 + 0.4 * k / max(spars, 1))
        span = 0.22 * height_m * (1.0 - 0.35 * k)
        meshes.append(tube((-span, y, 0.0), (span, y, 0.0), [(0.0, 0.5 * r), (2.0 * span, 0.5 * r)], 5, metal))
        shapes.append(col.capsule_between(f"{name}_spar_{k + 1}", (-span, y, 0.0), (span, y, 0.0), 0.6 * r))
    if dish_m > 0.0:
        d = 0.5 * dish_m
        bowl = lathe([(0.0, 0.0), (0.12 * d, 0.6 * d), (0.35 * d, d), (0.3 * d, d), (0.06 * d, 0.55 * d), (0.04 * d, 0.0)], 12, style.material("hull_panel"))
        meshes.append(bowl.transformed(rotation_x(math.pi), (0.0, height_m, -0.3 * d)))
        shapes.append(col.box(f"{name}_dish", (0.0, height_m, -0.5 * d), (dish_m, dish_m, 0.4 * d)))
    return module(name, Mesh.concatenate(meshes), shapes, skin=SKIN_NONE, fine=0.5)


def lamp(name: str, role: str, colour: tuple[float, float, float], range_m: float, size_m: float = 0.8, strength: float = 4.0) -> Module:
    """A running light: a small glowing housing and its light hardpoint, shining along the mount's normal."""
    if role not in LIGHT_ROLES:
        raise ValueError(f"lamp {name!r}: role must be one of {LIGHT_ROLES}")
    if range_m <= 0.0 or size_m <= 0.0:
        raise ValueError(f"lamp {name!r} needs a range and a size")
    albedo = tuple(0.5 * float(c) for c in colour)
    glow = Material(f"lamp_{role}", albedo, emissive=tuple(float(c) for c in colour), emissive_strength=strength)
    mesh = tapered_box(size_m, (size_m, 0.5 * size_m), (size_m, 0.5 * size_m), glow, center=(0.0, 0.25 * size_m, 0.0))
    point = Hardpoint(name, LIGHT, (0.0, 0.5 * size_m + 0.1, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0),
                      {"role": role, "colour": [round(float(c), 4) for c in colour], "range_m": round(range_m, 2)})
    return module(name, mesh, [col.box(name, (0.0, 0.25 * size_m, 0.0), (size_m, 0.5 * size_m, size_m))], [point], skin=SKIN_NONE)


def hull_mark(name: str, at: Sequence[float], normal: Sequence[float], up: Sequence[float], height_m: float,
              colour: tuple[float, float, float] = (0.84, 0.85, 0.87), text: str = "initial") -> Hardpoint:
    """A place for painted lettering on a hull (``core/glyphs.py``): ``at`` is the letter's centre on the face, ``normal`` the
    face's outward direction and ``up`` the way the letters stand. ``text`` is what the ship wears, chosen when it is spawned:
    ``initial`` the first letter of its name (the EA destroyers' bows), or a fixed string. The game draws it; no geometry is made here."""
    if height_m <= 0.0:
        raise ValueError(f"mark {name!r} needs a height")
    return Hardpoint(name, MARK, tuple(at), tuple(normal), tuple(up),
                     {"text": text, "height_m": round(height_m, 2), "colour": [round(float(c), 4) for c in colour]})


__all__ = ["LIGHT_ROLES", "antenna", "hull_mark", "lamp", "rotating_section"]
