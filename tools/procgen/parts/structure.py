"""Structural parts: struts (wing-like beams), blocks/fairings, flat panels and masts.

Local frames: a strut runs along local +X from ``root`` (x = 0) to ``tip`` (x = length), is
``thickness`` thick along Y and ``chord`` wide along Z; the asset rotates it into place. A block
is a (tapered) box along Z. A panel is a thin plate in the X/Z plane. A mast is a thin
cylinder along +Y.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Material, lathe, rotation_y, tapered_box
from ..styles import Style
from . import Anchor, Collision, Part


@dataclass(frozen=True)
class StrutSpec:
    length: float = 3.3
    thickness: float = 0.16
    chord_root: float = 1.3
    chord_tip: float = 1.0
    sweep: float = 0.6  # tip centre shifted along +Z (backwards) relative to the root
    mass_kg: float = 1_400.0


def strut(spec: StrutSpec, style: Style) -> Part:
    """A tapered, swept flat beam; the thin top/bottom faces are hull, the edges dark."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    # tapered_box builds along Z with (x, y) sections; rotating +90 deg about Y maps box +Z to
    # strut +X and box +X to strut -Z, so the chord lands on Z and the sweep offset is negated.
    mesh = tapered_box(
        spec.length,
        (spec.chord_root, spec.thickness),
        (spec.chord_tip, spec.thickness),
        hull,
        center=[0.0, 0.0, 0.5 * spec.length],
        offset_b=(-spec.sweep, 0.0),
        materials_by_face={"left": dark, "right": dark, "front": dark, "back": dark},
    ).transformed(rotation_y(0.5 * math.pi))
    root = np.array([0.0, 0.0, 0.0])
    tip = np.array([spec.length, 0.0, spec.sweep])
    center = 0.5 * (root + tip)
    basis = np.column_stack([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]])
    size = [spec.length, spec.thickness, max(spec.chord_root, spec.chord_tip)]
    return Part(
        "strut",
        mesh,
        anchors={"root": Anchor(root, [-1.0, 0.0, 0.0]), "tip": Anchor(tip, [1.0, 0.0, 0.0]), "center": Anchor(center)},
        collision=[Collision("box", center, basis, size=size, name="strut")],
        mass_kg=spec.mass_kg,
    )


@dataclass(frozen=True)
class BlockSpec:
    """Tapered box along Z; ``size_front``/``size_back`` are (width, height)."""

    length: float
    size_front: tuple[float, float]
    size_back: tuple[float, float]
    offset_back: tuple[float, float] = (0.0, 0.0)
    material: str = "hull"
    end_material: str = "hull_dark"
    mass_kg: float = 0.0
    collide: bool = False


def block(spec: BlockSpec, style: Style, name: str = "block") -> Part:
    mesh = tapered_box(
        spec.length,
        spec.size_front,
        spec.size_back,
        style.material(spec.material),
        offset_b=spec.offset_back,
        materials_by_face={"front": style.material(spec.end_material), "back": style.material(spec.end_material)},
    )
    collision = []
    if spec.collide:
        w = max(spec.size_front[0], spec.size_back[0])
        h = max(spec.size_front[1], spec.size_back[1])
        collision.append(Collision("box", [0.0, 0.0, 0.0], size=[w, h, spec.length], name=name))
    return Part(
        name,
        mesh,
        anchors={
            "front": Anchor([0.0, 0.0, -0.5 * spec.length], [0.0, 0.0, -1.0]),
            "back": Anchor([spec.offset_back[0], spec.offset_back[1], 0.5 * spec.length], [0.0, 0.0, 1.0]),
            "center": Anchor([0.0, 0.0, 0.0]),
        },
        collision=collision,
        mass_kg=spec.mass_kg,
    )


@dataclass(frozen=True)
class PanelSpec:
    width: float = 1.0  # along X
    length: float = 1.0  # along Z
    thickness: float = 0.04
    material: str = "hull"
    mass_kg: float = 0.0


def panel(spec: PanelSpec, style: Style) -> Part:
    mesh = tapered_box(
        spec.length,
        (spec.width, spec.thickness),
        (spec.width, spec.thickness),
        style.material(spec.material),
        materials_by_face={"left": style.material("hull_dark"), "right": style.material("hull_dark")},
    )
    return Part(
        "panel",
        mesh,
        anchors={"center": Anchor([0.0, 0.0, 0.0], [0.0, 1.0, 0.0]), "edge_right": Anchor([0.5 * spec.width, 0.0, 0.0], [1.0, 0.0, 0.0])},
        mass_kg=spec.mass_kg,
    )


@dataclass(frozen=True)
class MastSpec:
    height: float = 1.5
    radius: float = 0.04
    segments: int = 10
    material: str = "hull_dark"
    mass_kg: float = 0.0


def mast(spec: MastSpec, style: Style) -> Part:
    """Thin cylinder from the origin up along +Y with a small tip."""
    m: Material = style.material(spec.material)
    profile = [(0.0, 0.0), (0.0, spec.radius), (spec.height - 0.05, spec.radius), (spec.height, 0.0)]
    mesh = lathe(profile, spec.segments, m, creases={1}).transformed(_z_to_y())
    return Part("mast", mesh, anchors={"base": Anchor([0.0, 0.0, 0.0]), "tip": Anchor([0.0, spec.height, 0.0], [0.0, 1.0, 0.0])}, mass_kg=spec.mass_kg)


def _z_to_y() -> np.ndarray:
    """Rotation taking local +Z to +Y (and +Y to -Z)."""
    return np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]])
