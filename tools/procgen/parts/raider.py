"""The raider's hull parts, measured off its reference model (M7-T16, ``docs/assets-raider.md``).

Three shapes make the ship, all in the authored Godot frame (+X right, +Y up, -Z forward, the nose at z = 0, the wing's
mid-plane at y = 0); each builds the **right-hand** half where it has one, and the asset mirrors it:

* :class:`RaiderWing`: the flying wing. One straight leading edge from the nose to the tip, cut by a notch where the guns
  sit, a straight trailing edge chamfered in at the root; a thin section that thickens aft and closes at the trailing edge.
* :class:`RaiderRidge`: the narrow centre body along the whole length: the canopy ridge on top, the keel under it.
* :class:`RaiderLobe`: one engine housing beside the ridge, flat on top and below with a rounded outer side, a grilled
  intake in front and its nozzle at the back.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Mesh, box, lathe, loft
from ..styles import Style
from . import Anchor, Collision, Part


def _tri(verts: list, faces: list, mats: list, a, b, c, material_index: int, outward: np.ndarray) -> None:
    """One triangle wound so its normal points along ``outward`` (own vertices: hard edges)."""
    a, b, c = (np.asarray(v, dtype=float) for v in (a, b, c))
    if float(np.dot(np.cross(b - a, c - a), outward)) < 0.0:
        b, c = c, b
    base = len(verts)
    verts.extend([a, b, c])
    faces.append([base, base + 1, base + 2])
    mats.append(material_index)


def _quad(verts, faces, mats, a, b, c, d, material_index: int, outward: np.ndarray) -> None:
    _tri(verts, faces, mats, a, b, c, material_index, outward)
    _tri(verts, faces, mats, a, c, d, material_index, outward)


# --- the wing ------------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class RaiderWing:
    """The right half's planform and section. The leading edge runs ``le_ratio`` metres out per metre aft; the notch takes the
    corner between ``notch_x`` (its inner wall) and the leading edge back to ``notch_z`` (its back wall)."""

    half_span: float = 8.0
    le_ratio: float = 1.104  # x per z along the leading edge (47.8 degrees from the centre line)
    trailing_z: float = 7.374
    notch_x: float = 2.68
    notch_z: float = 3.10
    root_te_z: float = 6.80  # the trailing edge inboard of the chamfer
    chamfer_x: tuple[float, float] = (2.10, 2.65)  # the chamfer runs out from the root trailing edge to the main one
    tip_round_x: float = 7.80  # outboard of this the leading edge curls back into the tip
    tip_le_z: float = 7.32
    # Section: sharp at the leading edge, thick aft, closing at the trailing edge; thinner out at the tip.
    max_thickness: float = 0.34
    nose_thickness: float = 0.18  # reached ``nose_depth`` behind the leading edge
    nose_depth: float = 0.2
    growth: float = 0.09  # per metre further aft
    te_thickness: float = 0.10
    te_growth: float = 0.8  # per metre ahead of the trailing edge
    taper_x: float = 6.4  # outboard of this the section thins towards the tip
    tip_thickness: float = 0.07
    edge_thickness: float = 0.02  # the leading edge's own wall
    mass_kg: float = 4_400.0

    @property
    def sweep_deg(self) -> float:
        return math.degrees(math.atan(self.le_ratio))

    @property
    def tip_leading_z(self) -> float:
        return self.tip_le_z

    @property
    def tip_trailing_z(self) -> float:
        return self.trailing_z

    def line_z(self, x: np.ndarray | float) -> np.ndarray | float:
        """The leading edge's straight line (the notch and the tip aside)."""
        return np.abs(x) / self.le_ratio

    def leading_z(self, x: np.ndarray | float) -> np.ndarray | float:
        ax = np.abs(np.asarray(x, dtype=float))
        z = ax / self.le_ratio
        z = np.where((ax > self.notch_x) & (z < self.notch_z), self.notch_z, z)
        round_z = self.tip_round_x / self.le_ratio
        t = np.clip((ax - self.tip_round_x) / (self.half_span - self.tip_round_x), 0.0, 1.0)
        z = np.where(ax > self.tip_round_x, round_z + (self.tip_le_z - round_z) * t, z)
        return float(z) if np.ndim(x) == 0 else z

    def trailing_z_at(self, x: np.ndarray | float) -> np.ndarray | float:
        ax = np.abs(np.asarray(x, dtype=float))
        x0, x1 = self.chamfer_x
        t = np.clip((ax - x0) / (x1 - x0), 0.0, 1.0)
        z = self.root_te_z + (self.trailing_z - self.root_te_z) * t
        return float(z) if np.ndim(x) == 0 else z

    def thickness(self, x: np.ndarray | float, z: np.ndarray | float) -> np.ndarray:
        """Full thickness at a point of the planform; the depth behind the leading edge is taken from its straight line, so the
        notch's walls cut through the thick wing."""
        ax, z = np.abs(np.asarray(x, dtype=float)), np.asarray(z, dtype=float)
        d = np.maximum(z - ax / self.le_ratio, 0.0)
        e = np.maximum(self.trailing_z_at(ax) - z, 0.0)
        nose = np.where(d < self.nose_depth, self.nose_thickness * d / self.nose_depth,
                        self.nose_thickness + self.growth * (d - self.nose_depth))
        tail = self.te_thickness + self.te_growth * e
        out = np.clip((ax - self.taper_x) / (self.half_span - self.taper_x), 0.0, 1.0)
        cap = self.max_thickness + (self.tip_thickness - self.max_thickness) * out
        return np.maximum(np.minimum(np.minimum(nose, tail), cap), self.edge_thickness)

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        """Points inside the slab by at least ``margin`` (either half)."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        x, y, z = np.abs(p[:, 0]), p[:, 1], p[:, 2]
        return ((x < self.half_span - margin) & (z > self.leading_z(x) + margin) & (z < self.trailing_z_at(x) - margin)
                & (np.abs(y) < 0.5 * self.thickness(x, z) - margin))

    def stations(self) -> np.ndarray:
        """The spanwise stations of the mesh: about 0.25 m apart, with the notch's walls, the chamfer, the taper and the tip."""
        eps = 1e-3
        keys = [0.0, *self.chamfer_x, self.notch_x - eps, self.notch_x + eps, self.notch_z * self.le_ratio, self.taper_x,
                self.tip_round_x, self.half_span]
        xs = set(keys)
        for a, b in zip(sorted(keys)[:-1], sorted(keys)[1:]):
            n = max(1, round((b - a) / 0.25))
            xs.update(a + (b - a) * k / n for k in range(1, n))
        return np.array(sorted(xs))


CHORD_U = (0.0, 0.006, 0.015, 0.03, 0.06, 0.1, 0.16, 0.24, 0.33, 0.43, 0.53, 0.63, 0.72, 0.8, 0.87, 0.92, 0.955, 0.98, 0.993, 1.0)


def wing_mesh(spec: RaiderWing, style: Style) -> Mesh:
    """The right half: top and bottom skins over the planform in ``hull``, the leading edge, notch, tip and trailing edge walls in
    ``hull_panel`` (the plated edge band)."""
    hull, edge = style.material("hull"), style.material("hull_panel")
    xs = spec.stations()
    u = np.array(CHORD_U)
    grid = []  # per station: (len(u), 3) points on the mid-plane, and their half thickness
    for x in xs:
        z0, z1 = float(spec.leading_z(x)), float(spec.trailing_z_at(x))
        zs = z0 + (z1 - z0) * u
        half = 0.5 * spec.thickness(np.full_like(zs, x), zs)
        grid.append((np.column_stack([np.full_like(zs, x), np.zeros_like(zs), zs]), half))
    verts: list = []
    faces: list = []
    mats: list = []
    up, down = np.array([0.0, 1.0, 0.0]), np.array([0.0, -1.0, 0.0])
    lift = np.array([0.0, 1.0, 0.0])
    for (pa, ha), (pb, hb) in zip(grid[:-1], grid[1:]):
        for j in range(len(u) - 1):
            a, b, c, d = pa[j], pa[j + 1], pb[j + 1], pb[j]
            _quad(verts, faces, mats, a + lift * ha[j], b + lift * ha[j + 1], c + lift * hb[j + 1], d + lift * hb[j], 0, up)
            _quad(verts, faces, mats, a - lift * ha[j], b - lift * ha[j + 1], c - lift * hb[j + 1], d - lift * hb[j], 0, down)
        # Leading edge (and the notch's walls): faces forward and out; trailing edge: aft.
        a, b = pa[0], pb[0]
        out = np.cross(b - a, lift)
        out = out if out[2] < 0.0 or (abs(out[2]) < 1e-9 and out[0] > 0.0) else -out
        _quad(verts, faces, mats, a + lift * ha[0], b + lift * hb[0], b - lift * hb[0], a - lift * ha[0], 1, out)
        a, b = pa[-1], pb[-1]
        back = -np.cross(b - a, lift)
        back = back if back[2] > 0.0 else -back
        _quad(verts, faces, mats, a + lift * ha[-1], b + lift * hb[-1], b - lift * hb[-1], a - lift * ha[-1], 1, back)
    tip, half = grid[-1]
    for j in range(len(u) - 1):
        a, b = tip[j], tip[j + 1]
        _quad(verts, faces, mats, a + lift * half[j], b + lift * half[j + 1], b - lift * half[j + 1], a - lift * half[j], 1,
              np.array([1.0, 0.0, 0.0]))
    return Mesh(np.array(verts), np.array(faces), np.array(mats), (hull, edge))


def raider_wing(spec: RaiderWing, style: Style, steps: int = 5) -> Part:
    """The right half with ``steps`` stepped collision boxes, each wrapping its strip of the span from the leading edge at its inner
    edge to the trailing edge."""
    collision = []
    for k in range(steps):
        x0, x1 = spec.half_span * k / steps, spec.half_span * (k + 1) / steps
        z0 = float(spec.line_z(x0))
        z1 = float(max(spec.trailing_z_at(x0), spec.trailing_z_at(x1)))
        zs = np.linspace(z0, z1, 64)
        thick = float(spec.thickness(np.full_like(zs, x0), zs).max())
        collision.append(Collision("box", (0.5 * (x0 + x1), 0.0, 0.5 * (z0 + z1)), size=(x1 - x0, thick, z1 - z0), name=f"step_{k}"))
    anchors = {
        "tip": Anchor((spec.half_span, 0.0, spec.trailing_z)),
        "notch": Anchor((spec.notch_x, 0.0, spec.notch_z)),
    }
    return Part("wing", wing_mesh(spec, style), anchors, collision, spec.mass_kg, group="wing")


# --- the centre ridge ---------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class RidgeStation:
    z: float
    half_width: float
    top: float
    bottom: float


@dataclass(frozen=True)
class RaiderRidge:
    """Superellipse sections, front to back: the canopy ridge over the nose and the hump, the keel below."""

    stations: tuple[RidgeStation, ...]
    exponent: float = 2.5
    segments: int = 28
    mass_kg: float = 4_000.0

    def at(self, z: np.ndarray | float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """Half width, top and bottom at ``z`` (linear between stations)."""
        zs = [s.z for s in self.stations]
        return tuple(np.interp(z, zs, [getattr(s, k) for s in self.stations]) for k in ("half_width", "top", "bottom"))

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        w, top, bottom = self.at(p[:, 2])
        a, b, c = w, 0.5 * (top - bottom), 0.5 * (top + bottom)
        n = self.exponent
        r = (np.abs(p[:, 0] / np.maximum(a, 1e-9)) ** n + np.abs((p[:, 1] - c) / np.maximum(b, 1e-9)) ** n) ** (1.0 / n)
        inside_z = (p[:, 2] > self.stations[0].z + margin) & (p[:, 2] < self.stations[-1].z - margin)
        return inside_z & (r < 1.0 - margin / np.maximum(np.minimum(a, b), 1e-9))


def raider_ridge(spec: RaiderRidge, style: Style) -> Part:
    """The ridge as one lofted solid; one box is its hit volume."""
    from ..core.geometry import superellipse_ring

    rings = []
    for s in spec.stations:
        xy = superellipse_ring(2.0 * s.half_width, s.top - s.bottom, spec.segments, spec.exponent)
        rings.append(np.column_stack([xy[:, 0], xy[:, 1] + 0.5 * (s.top + s.bottom), np.full(len(xy), s.z)]))
    mesh = loft(rings, style.material("hull"), cap_start=True, cap_end=True, cap_material=style.material("hull_dark"))
    first, last = spec.stations[0], spec.stations[-1]
    top, bottom = max(s.top for s in spec.stations), min(s.bottom for s in spec.stations)
    width = 2.0 * max(s.half_width for s in spec.stations)
    collision = [Collision("box", (0.0, 0.5 * (top + bottom), 0.5 * (first.z + last.z)), size=(width, top - bottom, last.z - first.z))]
    return Part("hump", mesh, {"centre": Anchor((0.0, 0.5 * (top + bottom), 0.5 * (first.z + last.z)))}, collision, spec.mass_kg,
                group="hump")


# --- the engine lobes ---------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class LobeStation:
    z: float
    x_out: float
    top: float
    bottom: float


@dataclass(frozen=True)
class RaiderLobe:
    """The right engine housing: sections flat on top and below between the ridge (``x_in``, buried in it) and the outer side,
    which rounds over ``round_x`` metres into the wing's plane. The top and bottom rise ``pinch`` metres towards the ridge."""

    stations: tuple[LobeStation, ...]
    x_in: float = 0.2
    round_x: float = 0.8
    exponent: float = 1.8
    pinch: float = 0.06
    segments: int = 17  # points round the outer side; the flats take four each
    axis_x: float = 1.07  # the nozzle's axis
    nozzle_exit_r: float = 0.17
    nozzle_length: float = 0.12
    tail_pod: tuple[float, float, float, float] = (1.87, 0.11, 6.55, 6.97)  # x, radius, z from, z to: the small pod by the nozzle
    grille_z: float = 3.15  # the intake grille's front, ahead of the first station
    grille_pitch: float = 0.1
    retro_radius: float = 0.15
    mass_kg: float = 3_000.0

    def at(self, z: np.ndarray | float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        zs = [s.z for s in self.stations]
        return tuple(np.interp(z, zs, [getattr(s, k) for s in self.stations]) for k in ("x_out", "top", "bottom"))

    def profile(self, x: np.ndarray, x_out: np.ndarray, top: np.ndarray, bottom: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Top and bottom of the section at ``x`` (NaN outside it)."""
        x = np.asarray(x, dtype=float)
        cx = x_out - self.round_x
        flat = np.clip((cx - x) / np.maximum(cx - self.x_in, 1e-9), 0.0, 1.0)
        u = np.clip((x - cx) / self.round_x, 0.0, 1.0)
        k = (1.0 - u**self.exponent) ** (1.0 / self.exponent)
        lo, hi = bottom * k - self.pinch * flat, top * k + self.pinch * flat
        outside = (x < self.x_in) | (x > x_out)
        return np.where(outside, np.nan, hi), np.where(outside, np.nan, lo)

    def ring(self, s: LobeStation) -> np.ndarray:
        """The closed section, counter-clockwise seen from behind (+Z)."""
        cx = s.x_out - self.round_x
        k2 = 2.0 / self.exponent
        t = np.linspace(-0.5 * math.pi, 0.5 * math.pi, self.segments)
        c, sn = np.cos(t), np.sin(t)
        arc_x = cx + self.round_x * np.abs(c) ** k2
        arc_y = np.where(sn > 0.0, s.top, -s.bottom) * np.sign(sn) * np.abs(sn) ** k2
        flats = np.linspace(0.0, 1.0, 5)[1:-1]
        top_x = cx + (self.x_in - cx) * flats
        top_y = s.top + self.pinch * flats
        bottom_x = self.x_in + (cx - self.x_in) * flats
        bottom_y = s.bottom - self.pinch * (1.0 - flats)
        xs = np.concatenate([arc_x, top_x, [self.x_in, self.x_in], bottom_x])
        ys = np.concatenate([arc_y, top_y, [s.top + self.pinch, s.bottom - self.pinch], bottom_y])
        return np.column_stack([xs, ys, np.full(len(xs), s.z)])

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        """Points inside the right lobe by roughly ``margin``."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        x_out, top, bottom = self.at(p[:, 2])
        hi, lo = self.profile(p[:, 0], x_out, top, bottom)
        with np.errstate(invalid="ignore"):
            inside = (p[:, 1] < hi - margin) & (p[:, 1] > lo + margin)
        return (inside & (p[:, 0] > self.x_in + margin) & (p[:, 0] < x_out - margin)
                & (p[:, 2] > self.stations[0].z + margin) & (p[:, 2] < self.stations[-1].z - margin))


def raider_lobe(spec: RaiderLobe, style: Style) -> Part:
    """The right lobe: the lofted housing in the style's bare ``hull_metal`` with dark end faces, the intake grille's vanes ahead of it and the main nozzle on its back.
    Anchors ``main`` (the nozzle's exit, exhaust +Z), ``retro`` (the grille's front, exhaust -Z) and ``axis_centre``; one box is
    its hit volume."""
    from .propulsion import NozzleSpec, nozzle

    hull, dark = style.material("hull_metal"), style.material("hull_dark")
    housing = loft([spec.ring(s) for s in spec.stations], hull, cap_start=True, cap_end=True, cap_material=dark)
    first, last = spec.stations[0], spec.stations[-1]
    vanes = []
    for x in np.arange(spec.x_in + 0.25, first.x_out - 0.2, spec.grille_pitch):
        hi, lo = spec.profile(np.array([x]), first.x_out, first.top, first.bottom)
        if np.isnan(hi[0]):
            continue
        h0, h1 = float(lo[0]) + 0.05, float(hi[0]) - 0.05
        length = first.z - spec.grille_z + 0.03
        vanes.append(box((0.035, h1 - h0, length), dark, center=(float(x), 0.5 * (h0 + h1), spec.grille_z + 0.5 * length)))
    n_spec = NozzleSpec(throat_r=spec.nozzle_exit_r * 0.8, exit_r=spec.nozzle_exit_r, length=spec.nozzle_length + 0.04, wall=0.03,
                        segments=24)
    bell = nozzle(n_spec, style).translated((spec.axis_x, 0.0, last.z - 0.04))
    px, pr, pz0, pz1 = spec.tail_pod
    pod = lathe([(0.0, 0.0), (0.0, pr), (pz1 - pz0 - 0.04, pr), (pz1 - pz0, 0.6 * pr), (pz1 - pz0, 0.0)], 16, dark,
                creases={1, 2, 3}).translated((px, 0.0, pz0))
    mesh = Mesh.concatenate([housing, *vanes, bell.mesh, pod])
    exit_z = last.z + spec.nozzle_length
    anchors = {
        "main": Anchor((spec.axis_x, 0.0, exit_z), (0.0, 0.0, 1.0)),
        "retro": Anchor((spec.axis_x, 0.0, spec.grille_z), (0.0, 0.0, -1.0)),
        "axis_centre": Anchor((spec.axis_x, 0.0, 0.5 * (spec.grille_z + exit_z))),
    }
    x_out = max(s.x_out for s in spec.stations)
    top = max(s.top for s in spec.stations) + spec.pinch
    bottom = min(s.bottom for s in spec.stations) - spec.pinch
    collision = [Collision("box", (0.5 * (spec.x_in + x_out), 0.5 * (top + bottom), 0.5 * (spec.grille_z + exit_z)),
                           size=(x_out - spec.x_in, top - bottom, exit_z - spec.grille_z))]
    return Part("nacelle", mesh, anchors, collision, spec.mass_kg, group="nacelle")


__all__ = ["LobeStation", "RaiderLobe", "RaiderRidge", "RaiderWing", "RidgeStation", "raider_lobe", "raider_ridge", "raider_wing",
           "wing_mesh"]
