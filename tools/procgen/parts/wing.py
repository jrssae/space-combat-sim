"""Delta wing part (docs/architecture.md section 15.11; the raider's flying wing).

The wing is a thin slab whose planform is a delta: a leading edge swept ``sweep_deg`` from the centre line, a
square-cut tip and a trailing edge running from the tip back to the root. Thickness tapers linearly from the root
to the tip, so each half's top and bottom are exactly planar and the two halves meet in a shallow ridge. The edge
walls carry a darker ``hull_panel`` band (the leading-edge plating of the reference).

Local frame = the authored Godot frame: +X right, +Y up, -Z forward, the apex (nose) at the origin and the wing
spreading back along +Z. :func:`delta_wing` builds the **right half** (x >= 0); the asset mirrors it. Detail meshes
(vent grilles, accent plates) are separate boxes so they carry real depth in the splats.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Material, Mesh, box
from ..styles import Style
from . import Anchor, Collision, Part


@dataclass(frozen=True)
class WingSpec:
    half_span: float = 8.5
    sweep_deg: float = 60.0  # leading edge, measured from the centre line
    root_chord: float = 5.4  # trailing edge at the centre line (the apex is at z = 0)
    tip_chord: float = 0.9
    root_thickness: float = 0.35
    tip_thickness: float = 0.10
    mass_kg: float = 3_000.0

    @property
    def tip_leading_z(self) -> float:
        return self.half_span / math.tan(math.radians(self.sweep_deg))

    @property
    def tip_trailing_z(self) -> float:
        return self.tip_leading_z + self.tip_chord

    def leading_z(self, x: np.ndarray | float) -> np.ndarray | float:
        return np.abs(x) / math.tan(math.radians(self.sweep_deg))

    def trailing_z(self, x: np.ndarray | float) -> np.ndarray | float:
        t = np.abs(x) / self.half_span
        return self.root_chord + (self.tip_trailing_z - self.root_chord) * t

    def thickness(self, x: np.ndarray | float) -> np.ndarray | float:
        t = np.abs(x) / self.half_span
        return self.root_thickness + (self.tip_thickness - self.root_thickness) * t

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        """Points strictly inside the slab by at least ``margin`` (either half)."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        x, y, z = p[:, 0], p[:, 1], p[:, 2]
        return (
            (np.abs(x) < self.half_span - margin)
            & (z > self.leading_z(x) + margin)
            & (z < self.trailing_z(x) - margin)
            & (np.abs(y) < 0.5 * self.thickness(x) - margin)
        )


def _tri(mesh_verts: list, mesh_faces: list, mats: list, a, b, c, material_index: int, outward: np.ndarray) -> None:
    """Append one triangle, wound so its normal points along ``outward`` (hard edges: own vertices)."""
    a, b, c = (np.asarray(v, dtype=float) for v in (a, b, c))
    if float(np.dot(np.cross(b - a, c - a), outward)) < 0.0:
        b, c = c, b
    base = len(mesh_verts)
    mesh_verts.extend([a, b, c])
    mesh_faces.append([base, base + 1, base + 2])
    mats.append(material_index)


def _quad(mesh_verts, mesh_faces, mats, a, b, c, d, material_index: int, outward: np.ndarray) -> None:
    _tri(mesh_verts, mesh_faces, mats, a, b, c, material_index, outward)
    _tri(mesh_verts, mesh_faces, mats, a, c, d, material_index, outward)


def wing_mesh(spec: WingSpec, style: Style) -> Mesh:
    """The right half's slab: top and bottom planes in ``hull``, the leading edge, tip and trailing-edge walls in
    ``hull_panel``."""
    hull, edge = style.material("hull"), style.material("hull_panel")
    h = spec.half_span
    t_root, t_tip = 0.5 * spec.root_thickness, 0.5 * spec.tip_thickness
    apex = np.array([0.0, 0.0, 0.0])
    root_te = np.array([0.0, 0.0, spec.root_chord])
    tip_le = np.array([h, 0.0, spec.tip_leading_z])
    tip_te = np.array([h, 0.0, spec.tip_trailing_z])

    def up(p: np.ndarray, half: float) -> np.ndarray:
        return p + np.array([0.0, half, 0.0])

    verts: list = []
    faces: list = []
    mats: list = []
    # Apex and root trailing edge sit at the root thickness, the tip corners at the tip thickness.
    top = [up(apex, t_root), up(tip_le, t_tip), up(tip_te, t_tip), up(root_te, t_root)]
    bottom = [up(apex, -t_root), up(tip_le, -t_tip), up(tip_te, -t_tip), up(root_te, -t_root)]
    _quad(verts, faces, mats, *top, 0, np.array([0.0, 1.0, 0.0]))
    _quad(verts, faces, mats, *bottom, 0, np.array([0.0, -1.0, 0.0]))
    le_out = np.array([math.cos(math.radians(spec.sweep_deg)), 0.0, -math.sin(math.radians(spec.sweep_deg))])  # forward and out
    _quad(verts, faces, mats, top[0], top[1], bottom[1], bottom[0], 1, le_out)  # leading edge
    _quad(verts, faces, mats, top[1], top[2], bottom[2], bottom[1], 1, np.array([1.0, 0.0, 0.0]))  # tip
    _quad(verts, faces, mats, top[2], top[3], bottom[3], bottom[2], 1, np.array([0.0, 0.0, 1.0]))  # trailing edge
    return Mesh(np.array(verts), np.array(faces), np.array(mats), (hull, edge))


def vent_grille(
    width: float,
    length: float,
    slats: int,
    style: Style,
    slat_height: float = 0.05,
    slat_fill: float = 0.55,
    along: str = "z",
) -> Mesh:
    """A raised louvre grille: ``slats`` dark bars across ``width`` (x) spaced along ``length`` (z), on a dark
    backing plate. Centred at the origin, its base on y = 0 and its slats rising to ``slat_height``. With
    ``along="x"`` the bars run along z and are spaced across x instead."""
    dark, plate = style.material("hull_dark"), style.material("hull_panel")
    pitch = length / slats
    pieces = [box((width, 0.012, length), plate, center=(0.0, 0.006, 0.0))]
    for k in range(slats):
        z = -0.5 * length + (k + 0.5) * pitch
        pieces.append(box((width * 0.96, slat_height, pitch * slat_fill), dark, center=(0.0, 0.5 * slat_height, z)))
    mesh = Mesh.concatenate(pieces)
    if along == "x":
        mesh = mesh.transformed(np.array([[0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [-1.0, 0.0, 0.0]]))
    return mesh


def delta_wing(spec: WingSpec, style: Style, steps: int = 5) -> Part:
    """The right half of the wing: the slab plus ``steps`` stepped collision boxes (each wraps its strip of the
    span from the leading edge at its inner edge to the trailing edge at its outer edge)."""
    mesh = wing_mesh(spec, style)
    collision = []
    for k in range(steps):
        x0, x1 = spec.half_span * k / steps, spec.half_span * (k + 1) / steps
        z0, z1 = float(spec.leading_z(x0)), float(max(spec.trailing_z(x0), spec.trailing_z(x1)))
        thick = float(spec.thickness(x0))
        collision.append(
            Collision(
                "box",
                (0.5 * (x0 + x1), 0.0, 0.5 * (z0 + z1)),
                size=(x1 - x0, thick, z1 - z0),
                name=f"step_{k}",
            )
        )
    anchors = {
        "tip_le": Anchor((spec.half_span, 0.0, spec.tip_leading_z)),
        "tip_te": Anchor((spec.half_span, 0.0, spec.tip_trailing_z)),
        "root_te": Anchor((0.0, 0.0, spec.root_chord)),
    }
    return Part("wing", mesh, anchors, collision, spec.mass_kg, group="wing")


__all__ = ["WingSpec", "delta_wing", "vent_grille", "wing_mesh", "Material"]
