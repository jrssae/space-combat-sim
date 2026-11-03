"""Narn transport parts (docs/design-references.md, "Narn transport"; docs/assets-civilian.md, "narn_transport"): the
crescent, the cockpit, the dorsal block and rod, the fins, the flank towers, the cargo box and the Narn turret.

Authored frame of the design references: x to starboard, y up from the crescent's centre plane, z aft from the prong
tips, metres. Right-hand parts are built for x > 0 and the asset mirrors them. Every shape is our own geometry: faceted
lofts, frustums and prisms through the sizes written in the design references.

Painted regions (the crescent's red band, the canopy, the box's green panel and hazard corners) are facets of their
lofts, so the splats and the fallback mesh carry the same paint. Each solid also has a burial test, so the asset can drop
the samples one part hides inside another.
"""

from __future__ import annotations

import math
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from itertools import pairwise

import numpy as np

from ..core.geometry import Material, Mesh, polygon_area_2d, prism, sweep_rect
from ..styles import Style
from . import Anchor, Collision, Part
from .propulsion import NozzleSpec, nozzle
from .starfury import section_loft
from .weapons import BarrelSpec, gun_barrel
from .wing import vent_grille

Table = tuple[tuple[float, float], ...]
_SEAM = Material("_seam", (0.0, 0.0, 0.0))  # marks faces that are never built: joints closed by a neighbouring part


# --- helpers --------------------------------------------------------------------------------------------------------
def stations(knots: Iterable[float], max_step: float = math.inf) -> list[float]:
    """Loft stations through every knot, with extra ones so no two are more than ``max_step`` apart."""
    ks = sorted({round(float(k), 6) for k in knots})
    out = [ks[0]]
    for a, b in pairwise(ks):
        n = max(1, math.ceil((b - a) / max_step - 1e-9))
        out += [a + (b - a) * i / n for i in range(1, n + 1)]
    return out


def lerp_table(table: Table, at: np.ndarray | float) -> np.ndarray:
    """Piecewise-linear value of a ``(key, value)`` table."""
    return np.interp(at, [k for k, _ in table], [v for _, v in table])


def _compact(mesh: Mesh, keep: np.ndarray) -> Mesh:
    """The kept faces, with only the vertices and materials they use."""
    keep = np.asarray(keep, dtype=bool) & np.array([mesh.materials[i] != _SEAM for i in mesh.face_material], dtype=bool)
    faces, face_mat = mesh.faces[keep], mesh.face_material[keep]
    used_v, used_m = np.unique(faces), np.unique(face_mat)
    remap_v = np.zeros(mesh.vertex_count, dtype=np.int64)
    remap_v[used_v] = np.arange(len(used_v))
    remap_m = np.zeros(len(mesh.materials), dtype=np.int64)
    remap_m[used_m] = np.arange(len(used_m))
    return Mesh(mesh.vertices[used_v], remap_v[faces], remap_m[face_mat], tuple(mesh.materials[i] for i in used_m))


def painted_loft(rings: Sequence[np.ndarray], paints: Sequence[Sequence[Material | None]], cap: Material | None) -> Mesh:
    """A faceted loft through ``rings`` where each segment (ring ``i`` to ``i + 1``) has its own edge materials, so painted
    regions follow the facets. An edge painted ``None`` gets no faces (a seam another part closes); a ``None`` cap leaves
    the ends open."""
    rings = [np.asarray(r, dtype=float) for r in rings]
    n, segments = len(rings[0]), len(rings) - 1
    if len(paints) != segments:
        raise ValueError(f"expected {segments} segment paints, got {len(paints)}")
    pieces = []
    start = 0
    while start < segments:
        end = start
        while end + 1 < segments and tuple(paints[end + 1]) == tuple(paints[start]):
            end += 1
        edge = [_SEAM if m is None else m for m in paints[start]]
        mesh = section_loft(rings[start : end + 2], edge, cap or _SEAM)
        tube = 2 * n * (end - start + 1)
        keep = np.zeros(mesh.face_count, dtype=bool)
        keep[:tube] = True
        keep[tube : tube + n] = start == 0  # the start cap, only at the loft's front
        keep[tube + n :] = end == segments - 1  # the end cap, only at its back
        pieces.append(_compact(mesh, keep))
        start = end + 1
    return Mesh.concatenate(pieces)


def _rect_ring(x0: float, x1: float, z0: float, z1: float, y: float) -> np.ndarray:
    """A horizontal rectangle; its edges are the front (-z), right, back and left sides."""
    return np.array([[x0, y, z0], [x1, y, z0], [x1, y, z1], [x0, y, z1]])


@dataclass(frozen=True)
class Frustum:
    """A block whose horizontal section runs linearly from ``low`` at ``y0`` to ``high`` at ``y1``; each section is
    ``(x0, x1, z0, z1)``."""

    low: tuple[float, float, float, float]
    high: tuple[float, float, float, float]
    y0: float
    y1: float

    def mesh(self, sides: Sequence[Material], cap: Material) -> Mesh:
        """``sides`` paint the front, right, back and left faces."""
        rings = [_rect_ring(*self.low, self.y0), _rect_ring(*self.high, self.y1)]
        return painted_loft(rings, [list(sides)], cap)

    def solid(self) -> LoftSolid:
        rings = [_rect_ring(*self.low, self.y0)[:, [0, 2]], _rect_ring(*self.high, self.y1)[:, [0, 2]]]
        return LoftSolid(1, (self.y0, self.y1), tuple(rings))

    def bounds(self) -> tuple[np.ndarray, np.ndarray]:
        lo = np.array([min(self.low[0], self.high[0]), self.y0, min(self.low[2], self.high[2])])
        hi = np.array([max(self.low[1], self.high[1]), self.y1, max(self.low[3], self.high[3])])
        return lo, hi


@dataclass(frozen=True)
class LoftSolid:
    """A solid swept along ``axis`` through convex polygons (linear between ``levels``): the burial test of a lofted part.
    Polygons are ``(n, 2)`` in the other two axes in ascending order; all share one winding."""

    axis: int
    levels: tuple[float, ...]
    rings: tuple[np.ndarray, ...]

    def __post_init__(self) -> None:
        rings = [np.asarray(r, dtype=float).reshape(-1, 2) for r in self.rings]
        widest = max(rings, key=lambda r: abs(polygon_area_2d(r)))
        if polygon_area_2d(widest) < 0.0:
            rings = [r[::-1] for r in rings]
        object.__setattr__(self, "rings", tuple(rings))

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        """Points deeper than ``margin`` inside (measured across and along the axis)."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        others = [i for i in range(3) if i != self.axis]
        t, uv = p[:, self.axis], p[:, others]
        lv = self.levels
        out = np.zeros(len(p), dtype=bool)
        within = (t > lv[0] + margin) & (t < lv[-1] - margin)
        for k in range(len(lv) - 1):
            if lv[k + 1] <= lv[k]:
                continue
            sel = np.nonzero(within & (t >= lv[k]) & (t <= lv[k + 1]))[0]
            if len(sel) == 0:
                continue
            f = ((t[sel] - lv[k]) / (lv[k + 1] - lv[k]))[:, None, None]
            ring = (1.0 - f) * self.rings[k][None] + f * self.rings[k + 1][None]
            edge = np.roll(ring, -1, axis=1) - ring
            length = np.linalg.norm(edge, axis=2)
            normal = np.stack([edge[..., 1], -edge[..., 0]], axis=2) / np.where(length > 1e-9, length, 1.0)[..., None]
            depth = np.einsum("mnk,mnk->mn", uv[sel][:, None, :] - ring, normal)
            out[sel] |= np.where(length > 1e-9, depth < -margin, True).all(axis=1)
        return out


def _y_up() -> np.ndarray:
    """Turns a prism's thickness (local Z) onto +Y, its outline's local X and Y onto x and -z."""
    return np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]])


def _x_across() -> np.ndarray:
    """Turns a prism's thickness (local Z) onto -X, its outline's local X and Y onto z and y."""
    return np.array([[0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]])


# --- the crescent ---------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class CrescentSpec:
    """The flat crescent plate: a centre body behind the notch and two halves that run forward into the prongs.

    In section the plate thins from the centre line out to the rim (``outer``: half-width by z): its top is
    ``rim_top[0] + rim_top[1] * d`` above the centre plane and its bottom as far below by ``rim_bottom``, ``d`` the
    distance in from the rim, beveled over the last ``bevel_m`` to an edge at ``rim_y``. The centre body is capped by
    ``centre_top``/``centre_bottom`` (7.8 m thick on the centre line at z 27), the prongs ahead of the notch's back by
    the thinner ``prong_top``/``prong_bottom``, so the plate steps up behind them. The notch's inner edges (``inner``) and
    its back wall at ``notch_back_z`` are blunt walls; the halves meet the centre body at ``seam_x``."""

    outer: Table = ((0.0, 10.0), (3.6, 15.3), (15.3, 22.0), (27.0, 23.0), (38.8, 19.1), (45.0, 15.5), (51.3, 6.7))
    inner: Table = ((0.0, 10.0), (6.3, 10.0), (9.4, 13.2), (15.0, 13.2))
    centre_top: Table = ((15.0, 2.5), (27.0, 3.76), (45.0, 2.2), (51.3, 1.0))
    centre_bottom: Table = ((15.0, -2.85), (27.0, -4.04), (45.0, -2.4), (51.3, -1.2))
    prong_top: Table = ((0.0, -0.15), (0.3, 0.02), (1.5, 0.43), (2.5, 0.77), (4.5, 0.88), (6.0, 1.04), (8.0, 1.13),
                        (12.0, 1.2), (15.0, 1.33))  # fmt: skip
    prong_bottom: Table = ((0.0, -0.15), (0.3, -0.28), (1.5, -0.7), (2.5, -1.05), (4.5, -1.16), (6.0, -1.32), (8.0, -1.41),
                           (12.0, -1.48), (15.0, -1.61))  # fmt: skip
    rim_top: tuple[float, float] = (0.62, 0.137)  # y at the bevel's inner edge's extrapolation to d = 0, rise per metre
    rim_bottom: tuple[float, float] = (0.89, 0.135)
    bevel_m: float = 1.2
    rim_y: float = -0.15
    seam_x: float = 13.2
    notch_back_z: float = 15.0
    band_z: tuple[float, float] = (18.5, 22.5)  # the red band on each half's top, where the capture has the emblem
    band_u: tuple[float, float] = (0.15, 0.85)  # its share of the top between the cap and the bevel
    max_step: float = 1.5
    centre_mass_kg: float = 150_000.0
    half_mass_kg: float = 80_000.0

    @property
    def rear_z(self) -> float:
        return self.outer[-1][0]

    @property
    def seam_end_z(self) -> float:
        """Where the trailing edge sweeps in to ``seam_x``: the halves end there."""
        for (z0, w0), (z1, w1) in pairwise(self.outer):
            if w0 >= self.seam_x > w1:
                return z0 + (w0 - self.seam_x) / (w0 - w1) * (z1 - z0)
        raise ValueError("the outline never comes inside seam_x")

    def half_width(self, z: np.ndarray | float) -> np.ndarray:
        return lerp_table(self.outer, z)

    def inner_x(self, z: np.ndarray | float) -> np.ndarray:
        """The halves' inner edge: the notch's side wall ahead of its back, the seam behind it."""
        return np.where(np.asarray(z) < self.notch_back_z, lerp_table(self.inner, np.minimum(z, self.notch_back_z)), self.seam_x)

    def caps(self, z: np.ndarray | float, prong: np.ndarray | bool | None = None) -> tuple[np.ndarray, np.ndarray]:
        """The thickest the plate gets at ``z``: the prongs' caps ahead of the notch's back, the centre body's behind it."""
        prong = np.asarray(z) < self.notch_back_z if prong is None else prong
        top = np.where(prong, lerp_table(self.prong_top, z), lerp_table(self.centre_top, z))
        bottom = np.where(prong, lerp_table(self.prong_bottom, z), lerp_table(self.centre_bottom, z))
        return top, bottom

    def surface(self, x: np.ndarray | float, z: np.ndarray | float, prong: np.ndarray | bool | None = None) -> tuple[np.ndarray, np.ndarray]:
        """Top and bottom y at ``(x, z)``: thinning towards the rim, beveled at it, never thicker than the caps."""
        d = np.maximum(self.half_width(z) - np.abs(x), 0.0)
        b = self.bevel_m
        (at, kt), (ab, kb) = self.rim_top, self.rim_bottom
        bevel = np.minimum(d / b, 1.0)
        top = np.where(d >= b, at + kt * d, self.rim_y + (at + kt * b - self.rim_y) * bevel)
        bottom = np.where(d >= b, -(ab + kb * d), self.rim_y - (ab + kb * b + self.rim_y) * bevel)
        cap_top, cap_bottom = self.caps(z, prong)
        return np.minimum(top, cap_top), np.maximum(bottom, cap_bottom)

    def breaks(self, z: float, prong: bool, x_from: float) -> tuple[float, float, float]:
        """Where the section's top meets its cap, its bottom meets its cap, and the bevel starts, outboard of
        ``x_from``: the corners a ring needs to follow the section exactly."""
        w = float(self.half_width(z))
        bevel = max(x_from, w - self.bevel_m)
        cap_top, cap_bottom = (float(v) for v in self.caps(z, prong))
        (at, kt), (ab, kb) = self.rim_top, self.rim_bottom
        top = min(max(x_from, w - (cap_top - at) / kt), bevel)
        bottom = min(max(x_from, w - (-cap_bottom - ab) / kb), bevel)
        return top, bottom, bevel

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        x, y, z = np.abs(p[:, 0]), p[:, 1], p[:, 2]
        notch = (z < self.notch_back_z + margin) & (x < lerp_table(self.inner, np.minimum(z, self.notch_back_z)) + margin)
        top, bottom = self.surface(x, z)
        return (
            (z > margin) & (z < self.rear_z - margin) & (x < self.half_width(z) - margin) & ~notch
            & (y < top - margin) & (y > bottom + margin)
        )  # fmt: skip


def crescent_centre(spec: CrescentSpec, style: Style) -> Part:
    """The centre body from the notch's back wall to the rear edge; its sides at ``seam_x`` are seams."""
    hull = style.material("hull")
    zs = stations([spec.notch_back_z, spec.seam_end_z, spec.rear_z, *(z for z, _ in spec.outer if z > spec.notch_back_z),
                   *(z for z, _ in spec.centre_top)], spec.max_step)  # fmt: skip
    rings = []
    for z in zs:
        w = float(spec.half_width(z))
        xc = min(spec.seam_x, w)
        kt, kb, xb = spec.breaks(z, False, 0.0)
        kt, kb, xb = min(kt, xc), min(kb, xc), min(xb, xc)
        top = {x: float(spec.surface(x, z, False)[0]) for x in (xc, xb, kt)}
        bottom = {x: float(spec.surface(x, z, False)[1]) for x in (xc, xb, kb)}
        right_top = [[xc, top[xc]], [xb, top[xb]], [kt, top[kt]]]
        right_bottom = [[kb, bottom[kb]], [xb, bottom[xb]], [xc, bottom[xc]]]
        ring = [[xc, bottom[xc]], *right_top, *([-x, y] for x, y in reversed(right_top)),
                *([-x, y] for x, y in reversed(right_bottom)), *right_bottom[:-1]]  # fmt: skip
        rings.append(np.column_stack([np.array(ring), np.full(len(ring), z)]))
    # Edges: the right seam, the top from the seam over the flat to the left seam, the left seam, the bottom back.
    paints = [[None, hull, hull, hull, hull, hull, None, hull, hull, hull, hull, hull]] * (len(zs) - 1)
    mesh = painted_loft(rings, paints, hull)
    lo, hi = mesh.bounds()
    box = Collision("box", 0.5 * (lo + hi), size=hi - lo)
    return Part("crescent_centre", mesh, collision=[box], mass_kg=spec.centre_mass_kg)


def _half_ring(spec: CrescentSpec, z: float, prong: bool) -> np.ndarray:
    """The right half's section: the inner wall, the top out over the cap, the band and the bevel to the rim, the bottom
    back. The band's points sit between the cap's corner and the bevel at fixed shares, so every ring has nine points."""
    xi, w = float(spec.inner_x(z)), float(spec.half_width(z))
    kt, kb, xb = spec.breaks(z, prong, xi)
    u0, u1 = spec.band_u
    s0, s1 = kt + u0 * (xb - kt), kt + u1 * (xb - kt)

    def top(x: float) -> float:
        return float(spec.surface(x, z, prong)[0])

    def bottom(x: float) -> float:
        return float(spec.surface(x, z, prong)[1])

    ring = [[xi, bottom(xi)], [xi, top(xi)], [kt, top(kt)], [s0, top(s0)], [s1, top(s1)], [xb, top(xb)], [w, spec.rim_y],
            [xb, bottom(xb)], [kb, bottom(kb)]]  # fmt: skip
    return np.column_stack([np.array(ring), np.full(9, z)])


def crescent_half(spec: CrescentSpec, style: Style) -> Part:
    """The right half: the prong from its tip, a step up onto the plate behind the notch's back, then the plate outboard
    of the seam to where the trailing edge meets it. The notch's inner wall is built; the seam behind it is not.
    Collision: one box per stretch of the outline."""
    hull, stripe = style.material("hull"), style.material("stripe")
    end, back = spec.seam_end_z, spec.notch_back_z
    knots = [0.0, end, back, *spec.band_z, *(z for z, _ in spec.outer + spec.inner + spec.prong_top + spec.centre_top if z < end)]
    zs = stations(knots, spec.max_step)
    rings, mids = [], []
    for z in zs:
        if z == back:  # the step: the prong's section, then the plate's at the same z
            rings.append(_half_ring(spec, z, True))
            mids.append(z - 1e-6)
        rings.append(_half_ring(spec, z, z < back))
        mids.append(z)
    paints = []
    for (z0, _), (z1, _) in pairwise(zip(mids, rings)):
        mid = 0.5 * (z0 + z1)
        wall = hull if mid < back else None
        band = stripe if spec.band_z[0] <= mid <= spec.band_z[1] else hull
        paints.append([wall, hull, hull, band, hull, hull, hull, hull, hull])
    mesh = painted_loft(rings, paints, hull)
    collision = []
    cuts = [0.0, 6.3, back, 27.0, 38.8, end]
    for k, (z0, z1) in enumerate(pairwise(cuts)):
        z = np.linspace(z0, z1, 41)
        xi, w = spec.inner_x(z), spec.half_width(z)
        top, bottom = spec.surface(xi, z)
        lo = np.array([float(xi.min()), float(min(bottom.min(), spec.rim_y)), z0])
        hi = np.array([float(w.max()), float(top.max()), z1])
        collision.append(Collision("box", 0.5 * (lo + hi), size=hi - lo, name=f"step_{k}"))
    return Part("crescent_r", mesh, collision=collision, mass_kg=spec.half_mass_kg)


# --- the cockpit ----------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class CockpitStation:
    """A hexagonal section: widest (``mid``) at ``mid_y``, a flat top ``top`` wide at ``top_y``, a flat keel."""

    z: float
    mid: float
    top: float
    top_y: float
    keel: float
    keel_y: float


@dataclass(frozen=True)
class NarnCockpitSpec:
    """The blunt hexagonal nose in the notch, with a flat top, a raised block at its back (``hump``, its front face the
    windscreen) and a framed canopy on the top in front of it."""

    stations: tuple[CockpitStation, ...] = (
        CockpitStation(2.8, 4.5, 1.5, -1.43, 1.5, -1.43),  # the nose: a sharp horizontal edge
        CockpitStation(5.85, 6.75, 3.76, -0.16, 2.1, -2.05),
        CockpitStation(6.9, 7.5, 4.4, -0.16, 2.3, -2.27),
        CockpitStation(8.75, 8.1, 5.65, -0.16, 2.6, -2.6),
        CockpitStation(9.8, 8.3, 5.85, -0.16, 2.87, -2.85),
        CockpitStation(11.7, 8.52, 6.29, -0.16, 2.87, -2.85),
        CockpitStation(15.8, 8.52, 6.29, -0.16, 2.87, -2.85),
    )
    mid_y: float = -1.43
    canopy_z: tuple[float, float] = (6.2, 13.3)
    canopy_share: float = 0.84  # of the top's half-width; the frame runs on to ``frame_share``
    frame_share: float = 0.92
    frame_m: float = 0.4
    hump: Frustum = Frustum((-4.48, 4.48, 10.06, 15.8), (-2.45, 2.45, 11.1, 15.8), -0.5, 2.0)
    mass_kg: float = 50_000.0

    def ring(self, s: CockpitStation) -> np.ndarray:
        a, b = self.frame_share * s.top, self.canopy_share * s.top
        return np.array([[s.mid, self.mid_y], [s.top, s.top_y], [a, s.top_y], [b, s.top_y], [-b, s.top_y],
                         [-a, s.top_y], [-s.top, s.top_y], [-s.mid, self.mid_y], [-s.keel, s.keel_y],
                         [s.keel, s.keel_y]])  # fmt: skip

    def at(self, z: float) -> CockpitStation:
        zs = [s.z for s in self.stations]
        fields = ("mid", "top", "top_y", "keel", "keel_y")
        return CockpitStation(z, *(float(np.interp(z, zs, [getattr(s, f) for s in self.stations])) for f in fields))

    def body_solid(self) -> LoftSolid:
        rings = [self.ring(s)[[0, 1, 6, 7, 8, 9]] for s in self.stations]
        return LoftSolid(2, tuple(s.z for s in self.stations), tuple(rings))


def narn_cockpit(spec: NarnCockpitSpec, style: Style) -> Part:
    """The cockpit block and its windscreen hump. Anchors: ``windscreen`` (its middle, facing forward)."""
    hull, glass, frame = style.material("hull"), style.material("canopy_glass"), style.material("canopy_frame")
    c0, c1 = spec.canopy_z
    f = spec.frame_m
    zs = stations([*(s.z for s in spec.stations), c0, c0 + f, c1 - f, c1])
    rings = [np.column_stack([spec.ring(spec.at(z)), np.full(10, z)]) for z in zs]
    paints = []
    for z0, z1 in pairwise(zs):
        mid = 0.5 * (z0 + z1)
        if c0 + f <= mid <= c1 - f:
            centre, side = glass, frame
        elif c0 <= mid <= c1:
            centre, side = frame, frame
        else:
            centre, side = hull, hull
        paints.append([hull, hull, side, centre, side, hull, hull, hull, hull, hull])
    body = painted_loft(rings, paints, hull)
    hump = spec.hump.mesh([glass, hull, hull, hull], hull)
    mesh = Mesh.concatenate([body, hump])
    lo, hi = mesh.bounds()
    plateau_y = spec.stations[-1].top_y
    glass_mid = np.array([0.0, 0.5 * (plateau_y + spec.hump.y1), 0.5 * (spec.hump.low[2] + spec.hump.high[2])])
    return Part(
        "cockpit",
        mesh,
        anchors={"windscreen": Anchor(glass_mid, (0.0, 0.0, -1.0))},
        collision=[Collision("box", 0.5 * (lo + hi), size=hi - lo)],
        mass_kg=spec.mass_kg,
    )


# --- the dorsal block, rod and fairings -------------------------------------------------------------------------------
@dataclass(frozen=True)
class DorsalSpec:
    """The block on the crescent's top, the bar running aft from it into the box, and the two small plates beside the
    bar's end."""

    block: Frustum = Frustum((-3.4, 3.4, 20.32, 26.46), (-2.01, 2.01, 21.49, 25.30), 2.25, 4.78)
    rod_z: tuple[float, float] = (25.44, 35.28)
    rod_low: tuple[float, float] = (1.25, 2.52)  # half-width, y of the bar's lower edge
    rod_high: tuple[float, float] = (0.84, 4.21)
    plate: tuple[tuple[float, float], ...] = ((0.9, 30.86), (2.95, 33.4), (2.95, 35.29), (0.9, 35.29))  # (x, z)
    plate_y: float = 4.36
    plate_thickness: float = 0.44
    mass_kg: float = 12_000.0

    def rod_ring(self, z: float) -> np.ndarray:
        (wl, yl), (wh, yh) = self.rod_low, self.rod_high
        return np.array([[wl, yl, z], [wh, yh, z], [-wh, yh, z], [-wl, yl, z]])

    def rod_solid(self) -> LoftSolid:
        return LoftSolid(2, self.rod_z, tuple(self.rod_ring(z)[:, :2] for z in self.rod_z))


def dorsal(spec: DorsalSpec, style: Style) -> Part:
    hull = style.material("hull")
    block = spec.block.mesh([hull] * 4, hull)
    rod = painted_loft([spec.rod_ring(z) for z in spec.rod_z], [[hull] * 4], hull)
    outline = np.array(spec.plate)[:, [0, 1]] * np.array([1.0, -1.0])  # local (x, -z): the prism turns it back
    plate = prism([(outline, hull)], [(outline, hull)], spec.plate_thickness).transformed(_y_up(), (0.0, spec.plate_y, 0.0))
    meshes = [block, rod, plate, plate.mirrored("x")]
    b_lo, b_hi = spec.block.bounds()
    bar_x = max(spec.rod_low[0], *(x for x, _ in spec.plate))  # the bar and the plates beside its end
    r_lo = np.array([-bar_x, spec.rod_low[1], spec.rod_z[0]])
    r_hi = np.array([bar_x, spec.plate_y + 0.5 * spec.plate_thickness, spec.rod_z[1]])
    collision = [Collision("box", 0.5 * (b_lo + b_hi), size=b_hi - b_lo, name="block"),
                 Collision("box", 0.5 * (r_lo + r_hi), size=r_hi - r_lo, name="bar")]  # fmt: skip
    return Part("dorsal", Mesh.concatenate(meshes), collision=collision, mass_kg=spec.mass_kg)


# --- the fins -------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class FinSpec:
    """An upright plate at ``x``: a near-upright leading edge, a trailing edge sweeping forward to the tips."""

    outline: tuple[tuple[float, float], ...] = ((28.4, 0.0), (28.7, 8.1), (38.0, 8.1), (44.1, 0.0), (38.0, -8.6), (28.7, -8.6))  # (z, y)
    x: float = 17.1
    thickness: float = 0.5
    mass_kg: float = 12_000.0

    def solid(self) -> LoftSolid:
        ring = np.array(self.outline)[:, [1, 0]]  # (y, z)
        half = 0.5 * self.thickness
        return LoftSolid(0, (self.x - half, self.x + half), (ring, ring))


def fin(spec: FinSpec, style: Style) -> Part:
    hull = style.material("hull")
    outline = np.array(spec.outline)
    mesh = prism([(outline, hull)], [(outline, hull)], spec.thickness).transformed(_x_across(), (spec.x, 0.0, 0.0))
    lo, hi = mesh.bounds()
    return Part("fin_r", mesh, collision=[Collision("box", 0.5 * (lo + hi), size=hi - lo)], mass_kg=spec.mass_kg)


# --- the flank towers -----------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class TowerSpec:
    """A tapered tower on the crescent's top, its front sloping back. Three bent vanes stand in front of it and run aft
    into it at the top; a slotted block crowns it (the turret's mount); the main nozzle sits on its aft face. The thrust
    line runs through ``thrust`` (x, y)."""

    body: Frustum = Frustum((12.98, 16.96, 34.82, 43.82), (13.36, 16.58, 39.03, 43.90), 0.0, 7.93)
    crown_x: tuple[float, float] = (14.15, 15.54)
    crown_z: tuple[float, float] = (40.36, 43.07)
    crown_y: tuple[float, float] = (7.8, 9.0)
    slot_x: tuple[float, float] = (14.61, 15.08)
    slot_floor_y: float = 8.55
    vane_x: tuple[float, float, float] = (14.09, 15.04, 15.99)
    vane_size: float = 0.67
    vane_path: tuple[tuple[float, float], ...] = (
        (34.0, 0.3), (35.75, 4.4), (36.1, 5.05), (36.6, 5.5), (37.3, 5.75), (38.2, 5.87), (39.2, 5.87),
    )  # (z, y)  # fmt: skip
    nozzle: NozzleSpec = NozzleSpec(throat_r=0.95, exit_r=1.4, length=0.9, wall=0.08, segments=32, mass_kg=4_000.0)
    nozzle_inset: float = 0.05  # the bell's foot sits this far inside the aft face
    thrust: tuple[float, float] = (15.0, 5.0)
    retro_radius: float = 1.0
    mass_kg: float = 45_000.0

    def vane_front_z(self, y: float) -> float:
        """Where the vanes' front face crosses height ``y``: the tower's front on the thrust line."""
        p = np.array(self.vane_path)  # (z, y)
        for a, b in pairwise(p):
            d = (b - a) / np.linalg.norm(b - a)
            ahead = 0.5 * self.vane_size * np.array([-d[1], d[0]])  # sweep_rect's thickness side that faces forward
            fa, fb = a + ahead, b + ahead
            if fa[1] <= y <= fb[1]:
                return float(fa[0] + (y - fa[1]) / (fb[1] - fa[1]) * (fb[0] - fa[0]))
        raise ValueError(f"the vanes' front never reaches y = {y}")


def flank_tower(spec: TowerSpec, style: Style) -> Part:
    """The right tower with its vanes, crown and nozzle. Anchors: ``main`` (the nozzle's exit), ``retro`` (the vanes'
    front on the thrust line), ``centre`` (between them) and ``turret`` (the crown's top, up)."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    body = spec.body.mesh([hull] * 4, hull)
    (cx0, cx1), (cz0, cz1), (cy0, cy1) = spec.crown_x, spec.crown_z, spec.crown_y
    sx0, sx1 = spec.slot_x
    crown = [
        Frustum((cx0, cx1, cz0, cz1), (cx0, cx1, cz0, cz1), cy0, spec.slot_floor_y).mesh([hull] * 4, hull),
        Frustum((cx0, sx0, cz0, cz1), (cx0, sx0, cz0, cz1), spec.slot_floor_y - 0.05, cy1).mesh([hull, hull, hull, hull], hull),
        Frustum((sx1, cx1, cz0, cz1), (sx1, cx1, cz0, cz1), spec.slot_floor_y - 0.05, cy1).mesh([hull, hull, hull, hull], hull),
    ]
    path = np.array([[0.0, y, z] for z, y in spec.vane_path])
    n = len(path)
    vanes = [
        sweep_rect(path + np.array([x, 0.0, 0.0]), (1.0, 0.0, 0.0), np.full(n, spec.vane_size), np.full(n, spec.vane_size), dark)
        for x in spec.vane_x
    ]
    tx, ty = spec.thrust
    aft_z = spec.body.low[3] + (spec.body.high[3] - spec.body.low[3]) * (ty - spec.body.y0) / (spec.body.y1 - spec.body.y0)
    bell = nozzle(spec.nozzle, style).translated((tx, ty, aft_z - spec.nozzle_inset))
    retro = np.array([tx, ty, spec.vane_front_z(ty)])
    main = bell.anchor("exit")
    mesh = Mesh.concatenate([body, *crown, *vanes, bell.mesh])
    lo, hi = mesh.bounds()
    return Part(
        "tower_r",
        mesh,
        anchors={
            "main": main,
            "retro": Anchor(retro, (0.0, 0.0, -1.0)),
            "centre": Anchor(0.5 * (retro + main.position)),
            "turret": Anchor((0.5 * (cx0 + cx1), cy1, 0.5 * (cz0 + cz1)), (0.0, 1.0, 0.0)),
        },
        collision=[Collision("box", 0.5 * (lo + hi), size=hi - lo)],
        mass_kg=spec.mass_kg + spec.nozzle.mass_kg,
    )


# --- the cargo box --------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class CargoBoxSpec:
    """The box hanging under and behind the crescent: a chamfered section, its front a wedge whose edge is at
    ``(front_z, apex_y)``, its aft lower edge cut back, a green panel on each side, hazard checkers at its lower corners
    and two vent grilles on top."""

    half_width: float = 12.75
    top_y: float = 5.0
    bottom_y: float = -9.0
    chamfer_x: float = 11.6  # where the top and bottom faces turn into their chamfers
    top_chamfer_y: float = 4.35
    bottom_chamfer_y: float = -8.5
    front_z: float = 31.2
    apex_y: float = 0.52
    front_top_slope: float = 1.158  # y per z, up and down from the wedge's edge
    front_bottom_slope: float = 2.70
    rear_z: float = 70.0
    rear_chamfer_z: float = 69.2
    aft_cut_z: float = 66.4  # the bottom turns up here to (rear_z, aft_cut_top_y)
    aft_cut_top_y: float = 0.55
    panel_z: tuple[float, float] = (41.0, 61.0)
    panel_y: tuple[float, float] = (-6.5, 2.5)
    hazard_z: tuple[tuple[float, float], ...] = ((35.2, 40.0), (61.4, 66.2))
    hazard_y: tuple[float, float] = (-8.3, -7.1)
    hazard_square: float = 1.2
    grille_x: float = 8.88  # centres at +-grille_x
    grille_z: float = 65.09
    grille_size: tuple[float, float] = (4.58, 5.55)  # across x, along z
    grille_slats: int = 5
    grille_sink: float = 0.03
    mass_kg: float = 450_000.0

    def y_top(self, z: float) -> float:
        rear = self.top_y - max(0.0, z - self.rear_chamfer_z) * (self.top_y - self.top_chamfer_y) / (self.rear_z - self.rear_chamfer_z)
        return min(self.top_y, self.apex_y + self.front_top_slope * (z - self.front_z), rear)

    def y_bottom(self, z: float) -> float:
        aft = self.bottom_y + max(0.0, z - self.aft_cut_z) * (self.aft_cut_top_y - self.bottom_y) / (self.rear_z - self.aft_cut_z)
        return max(self.bottom_y, self.apex_y - self.front_bottom_slope * (z - self.front_z), aft)

    def section(self) -> np.ndarray:
        """The full section ``(16, 2)``, before the wedge and the cuts clip it; its side walls break at the paint's edges."""
        w, c = self.half_width, self.chamfer_x
        side = [self.top_chamfer_y, self.panel_y[1], self.panel_y[0], self.hazard_y[1], self.hazard_y[0], self.bottom_chamfer_y]
        right = [[c, self.top_y], *([w, y] for y in side), [c, self.bottom_y]]
        left = [[-x, y] for x, y in reversed(right)]
        return np.array(right + left)

    def ring(self, z: float) -> np.ndarray:
        s = self.section()
        s[:, 1] = np.clip(s[:, 1], self.y_bottom(z), self.y_top(z))
        return s

    def stations(self) -> list[float]:
        """Every z where the clipped section changes how it moves, and every paint edge."""
        knots = [self.front_z, self.rear_z, self.rear_chamfer_z, self.aft_cut_z, *self.panel_z]
        for y in self.section()[:, 1]:
            if y > self.apex_y:
                knots.append(self.front_z + (y - self.apex_y) / self.front_top_slope)
            else:
                knots.append(self.front_z + (self.apex_y - y) / self.front_bottom_slope)
                aft = self.aft_cut_z + (y - self.bottom_y) * (self.rear_z - self.aft_cut_z) / (self.aft_cut_top_y - self.bottom_y)
                knots.append(aft)
        knots.append(self.front_z + (self.top_y - self.apex_y) / self.front_top_slope)
        for z0, z1 in self.hazard_z:
            knots += list(np.arange(z0, z1 + 1e-6, self.hazard_square))
        return stations(k for k in knots if self.front_z <= k <= self.rear_z)

    def solid(self) -> LoftSolid:
        zs = self.stations()
        return LoftSolid(2, tuple(zs), tuple(self.ring(z) for z in zs))

    def grille_footprints(self) -> list[tuple[float, float, float, float]]:
        gx, gz = self.grille_size
        return [(s * self.grille_x - 0.5 * gx, s * self.grille_x + 0.5 * gx, self.grille_z - 0.5 * gz, self.grille_z + 0.5 * gz)
                for s in (1.0, -1.0)]  # fmt: skip


def cargo_box(spec: CargoBoxSpec, style: Style) -> Part:
    """The box with its paint; its front wedge's edge and the cut's ends are degenerate facets (no area, no samples)."""
    grey, green = style.material("hull_panel"), style.material("cargo_panel")
    yellow, black = style.material("hazard"), style.material("hazard_dark")
    zs = spec.stations()
    rings = [np.column_stack([spec.ring(z), np.full(16, z)]) for z in zs]
    paints = []
    for z0, z1 in pairwise(zs):
        mid = 0.5 * (z0 + z1)
        edges: list[Material] = [grey] * 16
        if spec.panel_z[0] <= mid <= spec.panel_z[1]:
            edges[2] = edges[12] = green
        for h0, h1 in spec.hazard_z:
            if h0 <= mid <= h1:
                edges[4] = edges[10] = yellow if int((mid - h0) // spec.hazard_square) % 2 == 0 else black
        paints.append(edges)
    mesh = painted_loft(rings, paints, grey)
    lo, hi = mesh.bounds()
    return Part("box", mesh, collision=[Collision("box", 0.5 * (lo + hi), size=hi - lo)], mass_kg=spec.mass_kg)


def box_grilles(spec: CargoBoxSpec, style: Style) -> Part:
    """The two five-slat vent grilles on the box's top near its aft end, sunk a little so their plates' undersides are
    inside the box."""
    gx, gz = spec.grille_size
    grille = vent_grille(gz, gx, spec.grille_slats, style, slat_height=0.15, slat_fill=0.82, along="x")
    y = spec.top_y - spec.grille_sink
    meshes = [grille.translated((s * spec.grille_x, y, spec.grille_z)) for s in (1.0, -1.0)]
    return Part("grilles", Mesh.concatenate(meshes))


# --- the turret -----------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class NarnTurretSpec:
    """A six-sided base, a wedge-shaped housing (low in front, tall behind) with a red band, and twin barrels. Turret
    frame: the pivot at the origin on the mount, +Y up, the barrels along -Z, their muzzles ``barrel_m`` ahead."""

    base_radius: float = 1.3  # to the corners: 2.6 m across
    base_height: float = 0.5
    housing_front: tuple[float, float, float, float] = (-1.0, 0.7, 0.4, 0.95)  # z, half-width, y0, y1
    housing_back: tuple[float, float, float, float] = (1.1, 0.95, 0.4, 1.7)
    band_z: tuple[float, float] = (0.15, 0.45)
    barrel: BarrelSpec = BarrelSpec(length=2.6, radius=0.09, base_radius=0.16, base_length=0.45, bore_radius=0.05,
                                    bore_depth=0.06, segments=14, mass_kg=0.0)  # fmt: skip
    barrel_x: float = 0.42
    barrel_y: float = 0.7
    barrel_m: float = 3.0

    def housing_ring(self, z: float) -> np.ndarray:
        z0, w0, a0, b0 = self.housing_front
        z1, w1, a1, b1 = self.housing_back
        f = (z - z0) / (z1 - z0)
        w, a, b = (u + f * (v - u) for u, v in ((w0, w1), (a0, a1), (b0, b1)))
        return np.array([[-w, a, z], [w, a, z], [w, b, z], [-w, b, z]])

    def base_polygon(self) -> np.ndarray:
        angles = np.radians(np.arange(6) * 60.0)
        return self.base_radius * np.column_stack([np.cos(angles), np.sin(angles)])  # (x, z)

    def solids(self) -> list[LoftSolid]:
        base = self.base_polygon()
        zs = (self.housing_front[0], self.housing_back[0])
        return [LoftSolid(1, (0.0, self.base_height), (base, base)),
                LoftSolid(2, zs, tuple(self.housing_ring(z)[:, :2] for z in zs))]  # fmt: skip


def narn_turret(spec: NarnTurretSpec, style: Style) -> Part:
    """The turret model in its own frame. Anchors: ``pivot`` (up), ``trunnion`` (where the barrels elevate, on the turning
    axis), ``muzzle_l`` and ``muzzle_r`` (forward)."""
    hull, stripe = style.material("hull"), style.material("stripe")
    base_outline = spec.base_polygon() * np.array([1.0, -1.0])  # local (x, -z): the prism turns it back
    base = prism([(base_outline, hull)], [(base_outline, hull)], spec.base_height).transformed(_y_up(), (0.0, 0.5 * spec.base_height, 0.0))
    z0, z1 = spec.housing_front[0], spec.housing_back[0]
    zs = stations([z0, *spec.band_z, z1])
    paints = [[stripe if spec.band_z[0] <= 0.5 * (a + b) <= spec.band_z[1] else hull] * 4 for a, b in pairwise(zs)]
    housing = painted_loft([spec.housing_ring(z) for z in zs], paints, hull)
    mount_z = spec.barrel.length - spec.barrel_m
    anchors = {"pivot": Anchor((0.0, 0.0, 0.0), (0.0, 1.0, 0.0)), "trunnion": Anchor((0.0, spec.barrel_y, 0.0))}
    barrels = []
    for name, x in (("muzzle_r", spec.barrel_x), ("muzzle_l", -spec.barrel_x)):
        b = gun_barrel(spec.barrel, style).translated((x, spec.barrel_y, mount_z))
        barrels.append(b.mesh)
        anchors[name] = b.anchor("muzzle")
    return Part("turret", Mesh.concatenate([base, housing, *barrels]), anchors=anchors)


__all__ = [
    "CargoBoxSpec",
    "CockpitStation",
    "CrescentSpec",
    "DorsalSpec",
    "FinSpec",
    "Frustum",
    "LoftSolid",
    "NarnCockpitSpec",
    "NarnTurretSpec",
    "TowerSpec",
    "box_grilles",
    "cargo_box",
    "crescent_centre",
    "crescent_half",
    "dorsal",
    "fin",
    "flank_tower",
    "lerp_table",
    "narn_cockpit",
    "narn_turret",
    "painted_loft",
    "stations",
]
