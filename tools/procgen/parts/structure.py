"""Structural parts: struts (wing-like beams), blocks/fairings, flat panels and masts.

Local frames: a strut runs along local +X from ``root`` (x = 0) to ``tip`` (x = length), is
``thickness`` thick along Y and ``chord`` wide along Z; the asset rotates it into place. A block
is a (tapered) box along Z. A panel is a thin plate in the X/Z plane. A mast is a thin
cylinder along +Y.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from itertools import pairwise

import numpy as np

from ..core.geometry import Material, Mesh, lathe, prism, rotation_y, tapered_box, unit
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


# --- trussed strut -----------------------------------------------------------------------------
# prism() builds in (u, v) and extrudes along w; the plate maps u -> +X (span), v -> -Z, w -> +Y.
_PLATE_FRAME = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]])


@dataclass(frozen=True)
class TrussStrutSpec:
    """A swept, tapered wing-like strut: a flat plate plus two ladder webs (rails and rungs with
    rectangular cut-outs) hanging under its leading and trailing edges.

    Local frame: the span runs along +X from the root (x = 0) to the tip (x = ``length``); the
    plate lies in the X/Z plane, ``thickness`` thick about y = 0; the leading edge is at
    ``z = sweep * x / length`` (so the tip's leading edge is ``sweep`` aft of the root's) and the
    chord tapers linearly from ``chord_root`` to ``chord_tip``. The webs hang towards -Y,
    ``web_depth_root`` -> ``web_depth_tip`` below the plate, ``web_inset`` in from the edges;
    their cut-outs (``cutouts`` of them, separated by ``rung`` wide posts) fill the
    ``cutout_span`` fraction of the span, so the strut reads as an open truss from the front.
    ``bands`` paint spans of the plate: ``(x0, x1, role)``, e.g. hazard stripes."""

    length: float = 5.0
    chord_root: float = 3.6
    chord_tip: float = 1.8
    sweep: float = 3.0
    thickness: float = 0.18
    web_depth_root: float = 0.55
    web_depth_tip: float = 0.35
    web_thickness: float = 0.08
    web_inset: float = 0.15
    rail: float = 0.1
    rung: float = 0.14
    cutouts: int = 6
    cutout_span: tuple[float, float] = (0.25, 0.8)
    bands: tuple[tuple[float, float, str], ...] = ()
    mass_kg: float = 1_500.0

    def __post_init__(self) -> None:
        if min(self.length, self.chord_root, self.chord_tip, self.thickness) <= 0.0:
            raise ValueError("strut dimensions must be positive")
        if not 0.0 <= self.cutout_span[0] < self.cutout_span[1] <= 1.0:
            raise ValueError("cutout_span must be increasing fractions of the length")
        if min(self.web_depth_root, self.web_depth_tip) <= 2.0 * self.rail:
            raise ValueError("the webs must be deeper than their two rails")
        for x0, x1, _ in self.bands:
            if not 0.0 <= x0 < x1 <= self.length:
                raise ValueError(f"band ({x0}, {x1}) must lie on the span")

    def leading_edge(self, x: float) -> float:
        return self.sweep * x / self.length

    def chord(self, x: float) -> float:
        return self.chord_root + (self.chord_tip - self.chord_root) * x / self.length

    def trailing_edge(self, x: float) -> float:
        return self.leading_edge(x) + self.chord(x)

    def web_depth(self, x: float) -> float:
        return (
            self.web_depth_root
            + (self.web_depth_tip - self.web_depth_root) * x / self.length
        )

    def role_at(self, x: float) -> str:
        for x0, x1, role in self.bands:
            if x0 <= x <= x1:
                return role
        return "hull"


def _ladder_web(
    spec: TrussStrutSpec, z_root: float, z_tip: float, style: Style
) -> Mesh:
    """One ladder web under the plate, along the line from ``(0, 0, z_root)`` to
    ``(length, 0, z_tip)``: rails top and bottom, posts between rectangular cut-outs."""
    d = np.array([spec.length, 0.0, z_tip - z_root])
    span = float(np.linalg.norm(d))
    d /= span
    down = np.array([0.0, -1.0, 0.0])
    frame = np.column_stack([d, down, np.cross(d, down)])  # (u, v, w) -> strut frame
    top = (
        0.5 * spec.thickness + spec.rail
    )  # v of the top rail's lower edge (v grows downwards)

    def bottom(u: float) -> float:  # v of the web's lower edge
        return 0.5 * spec.thickness + spec.web_depth(u * d[0])

    ua, ub = (f * span for f in spec.cutout_span)
    hole = (ub - ua - (spec.cutouts - 1) * spec.rung) / spec.cutouts
    if hole <= 0.0:
        raise ValueError("cut-outs do not fit: fewer cut-outs or narrower rungs")
    holes = [
        (ua + k * (hole + spec.rung), ua + k * (hole + spec.rung) + hole)
        for k in range(spec.cutouts)
    ]
    solid = (
        [0.0] + [e for h in holes for e in h] + [span]
    )  # post intervals: pairs (solid[2i], solid[2i+1])
    hull, dark = style.material("hull"), style.material("hull_dark")
    polys = [
        (np.array([[0.0, 0.0], [span, 0.0], [span, top], [0.0, top]]), hull),
        (
            np.array(
                [
                    [0.0, bottom(0.0) - spec.rail],
                    [span, bottom(span) - spec.rail],
                    [span, bottom(span)],
                    [0.0, bottom(0.0)],
                ]
            ),
            hull,
        ),
    ]
    for k in range(0, len(solid), 2):
        a, b = solid[k], solid[k + 1]
        polys.append(
            (
                np.array(
                    [
                        [a, top],
                        [b, top],
                        [b, bottom(b) - spec.rail],
                        [a, bottom(a) - spec.rail],
                    ]
                ),
                hull,
            )
        )
    loops = [
        (
            np.array(
                [[0.0, 0.0], [span, 0.0], [span, bottom(span)], [0.0, bottom(0.0)]]
            ),
            dark,
        )
    ]
    for a, b in holes:
        loops.append(
            (
                np.array(
                    [
                        [a, top],
                        [b, top],
                        [b, bottom(b) - spec.rail],
                        [a, bottom(a) - spec.rail],
                    ]
                ),
                dark,
            )
        )
    # v grows downwards, so the (u, v) polygons are mirrored; prism() fixes the winding itself.
    return prism(polys, loops, spec.web_thickness).transformed(
        frame, [0.0, 0.0, z_root]
    )


def truss_strut(spec: TrussStrutSpec, style: Style) -> Part:
    """The strut of :class:`TrussStrutSpec`. Plate faces ``hull`` (or a band's role), plate edges
    and cut-out walls ``hull_dark``. Anchors: ``root``/``tip`` (mid-chord, pointing out along
    -X/+X), ``root_le``/``tip_le`` (leading edge), ``center``. One box collision primitive along
    the swept mid-chord line, its ``basis`` the box's axes."""
    stations = sorted({0.0, spec.length, *(x for b in spec.bands for x in b[:2])})
    polys = []
    for xa, xb in pairwise(stations):
        poly = np.array(
            [
                [xa, -spec.leading_edge(xa)],
                [xb, -spec.leading_edge(xb)],
                [xb, -spec.trailing_edge(xb)],
                [xa, -spec.trailing_edge(xa)],
            ]
        )
        polys.append((poly, style.material(spec.role_at(0.5 * (xa + xb)))))
    outline = [[x, -spec.leading_edge(x)] for x in stations] + [
        [x, -spec.trailing_edge(x)] for x in reversed(stations)
    ]
    plate = prism(
        polys, [(np.array(outline), style.material("hull_dark"))], spec.thickness
    ).transformed(_PLATE_FRAME)
    le_web = _ladder_web(
        spec, spec.web_inset, spec.leading_edge(spec.length) + spec.web_inset, style
    )
    te_web = _ladder_web(
        spec,
        spec.trailing_edge(0.0) - spec.web_inset,
        spec.trailing_edge(spec.length) - spec.web_inset,
        style,
    )
    mesh = Mesh.concatenate([plate, le_web, te_web])

    root = np.array([0.0, 0.0, 0.5 * spec.chord_root])
    tip = np.array(
        [spec.length, 0.0, spec.leading_edge(spec.length) + 0.5 * spec.chord_tip]
    )
    # The tightest box with one axis along the swept mid-chord line and one along the plate normal.
    x_axis = unit(tip - root)
    y_axis = np.array([0.0, 1.0, 0.0])
    basis = np.column_stack([x_axis, y_axis, np.cross(x_axis, y_axis)])
    local = mesh.vertices @ basis
    lo, hi = local.min(axis=0), local.max(axis=0)
    box_center = basis @ (0.5 * (lo + hi))
    size = hi - lo
    return Part(
        "truss_strut",
        mesh,
        anchors={
            "root": Anchor(root, [-1.0, 0.0, 0.0]),
            "tip": Anchor(tip, [1.0, 0.0, 0.0]),
            "root_le": Anchor([0.0, 0.0, 0.0]),
            "tip_le": Anchor([spec.length, 0.0, spec.leading_edge(spec.length)]),
            "center": Anchor(0.5 * (root + tip)),
        },
        collision=[Collision("box", box_center, basis, size=size, name="strut")],
        mass_kg=spec.mass_kg,
    )
