"""Centauri Brezebel parts (docs/design-references.md, "Centauri Brezebel transport"; docs/assets-civilian.md,
"centauri_brezebel"): the lens hull's bow and arms, the engine bay, the dorsal fitting, the arm fairings, the hooked tip
fins and the Centauri turret.

Authored frame of the design references: x to starboard, y up, z aft from the nose tip, metres, x and y centred on the
reference model's box. The hull is mirror-symmetric about its own centre plane ``CENTRE_Y`` (0.1 m below the box centre,
since only the upper fins carry lights). Right-hand parts are built for x > 0 and the asset mirrors them. Every shape is
our own geometry through the sizes measured off the reference views and sections: no reference geometry is copied.

Each part comes as a :class:`Piece`: the part, the solid that hides what other parts push into it, and its side.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Material, Mesh, box, lathe, rotation_x
from ..styles import Style
from . import Anchor, Collision, Part
from .narn import LoftSolid, stations
from .propulsion import NozzleSpec, nozzle
from .solids import Solid, box_solid, lathe_solid
from .starfury import section_loft
from .weapons import BarrelSpec, gun_barrel

CENTRE_Y = -0.105  # the hull's centre plane in the box-centred authored frame
CENTRE, RIGHT = "centre", "right"
_Z_TO_Y = rotation_x(-0.5 * math.pi)  # takes local +Z to +Y
_MIRROR_Y = np.diag([1.0, -1.0, 1.0])


@dataclass
class Piece:
    """A part with its burial volume (``None``: it hides nothing) and its side (centre line or right, mirrored)."""

    part: Part
    solid: Solid | None
    side: str


# --- helpers --------------------------------------------------------------------------------------------------------
def _without_caps(mesh: Mesh, rings: int, ring_points: int, keep_start: bool, keep_end: bool) -> Mesh:
    """A ``section_loft`` with its start or end cap dropped, where a neighbouring part closes the end."""
    tube = 2 * ring_points * (rings - 1)
    keep = np.zeros(mesh.face_count, dtype=bool)
    keep[:tube] = True
    keep[tube : tube + ring_points] = keep_start
    keep[tube + ring_points :] = keep_end
    return mesh.face_subset(keep)


def _fan(points: np.ndarray, material: Material, facing: Sequence[float]) -> Mesh:
    """A flat convex panel through ``points`` whose faces look along ``facing``."""
    p = np.asarray(points, dtype=float)
    verts = np.vstack([p, p.mean(axis=0, keepdims=True)])
    n = len(p)
    faces = np.array([[n, j, (j + 1) % n] for j in range(n)])
    normal = np.cross(verts[faces[0, 1]] - verts[n], verts[faces[0, 2]] - verts[n])
    if float(normal @ np.asarray(facing, dtype=float)) < 0.0:
        faces = faces[:, ::-1]
    return Mesh(verts, faces, np.zeros(n, dtype=np.int64), (material,))


def _loft_solid(axis: int, levels: Sequence[float], rings: Sequence[np.ndarray]) -> Solid:
    """A burial solid through convex sections stacked along ``axis`` (two other coordinates per ring point)."""
    loft = LoftSolid(axis, tuple(levels), tuple(np.asarray(r, dtype=float) for r in rings))
    others = [i for i in range(3) if i != axis]
    pts = np.concatenate(loft.rings)
    lo, hi = np.zeros(3), np.zeros(3)
    lo[axis], hi[axis] = min(levels), max(levels)
    lo[others], hi[others] = pts.min(axis=0), pts.max(axis=0)
    return Solid(lambda p, margin: loft.contains(p, margin), (lo, hi))


def stretch_boxes(mesh: Mesh, cuts: Sequence[float], name: str) -> list[Collision]:
    """One box per z stretch, the boxes meeting at the cuts: hit volumes that follow a tapering part. Each box's width
    and height take in the sections just outside its stretch, so the part between two sections stays inside."""
    v = mesh.vertices
    zs = np.unique(v[:, 2])
    z_lo, z_hi = float(zs[0]), float(zs[-1])
    out = []
    for k, (z0, z1) in enumerate(zip(cuts[:-1], cuts[1:], strict=True)):
        a, b = max(z0, z_lo), min(z1, z_hi)
        if b <= a:
            continue
        below, above = zs[zs <= a + 1e-9], zs[zs >= b - 1e-9]
        sel = v[(v[:, 2] >= below[-1] - 1e-9) & (v[:, 2] <= above[0] + 1e-9)]
        lo, hi = sel.min(axis=0), sel.max(axis=0)
        lo[2], hi[2] = a, b
        out.append(Collision("box", 0.5 * (lo + hi), size=hi - lo, name=f"{name}{k}"))
    return out


def _bounds_box(mesh: Mesh, name: str = "") -> Collision:
    lo, hi = mesh.bounds()
    return Collision("box", 0.5 * (lo + hi), size=hi - lo, name=name)


# --- the lens hull --------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class LensSpec:
    """The hull's one law: every section of bow and arms is an ellipse about the centre line, half-width ``W(z)`` and
    half-height ``H(z)``. Ahead of ``plan_b`` both follow a quarter ellipse from the nose (the bow's round plan and
    side profile); behind it they taper straight to the arm tips. The arms are that ellipse outboard of ``inner_x``;
    their tips round off from ``tip_z[0]`` and end in a flat face at ``tip_z[1]`` that holds the main nozzle."""

    plan_a: float = 19.56  # the bow's half-width at its widest
    plan_b: float = 17.0  # where it is widest, from the nose
    height: float = 4.375  # half-height on the centre line there
    width_taper: float = 0.1402  # half-width lost per metre aft of plan_b
    height_taper: float = 0.0389
    nose_z: float = 0.02
    rear_z: float = 19.0  # the bow's rear face between the arms
    inner_x: float = 10.67  # the arms' inner walls
    bay_end_z: float = 25.4  # the inner walls are the engine bay's dark walls up to here
    tip_z: tuple[float, float] = (58.3, 59.4)
    tip_length: float = 1.7  # the rounding's reach (the reference's tip ends at z 60)
    tip_exponent: float = 2.5
    band_deg: float = 9.0  # the pale band either side of the bow's rim
    ring_points: int = 64
    arm_points: int = 33
    bow_mass_kg: float = 300_000.0
    arm_mass_kg: float = 110_000.0

    def half_width(self, z: np.ndarray | float) -> np.ndarray:
        z = np.asarray(z, dtype=float)
        u = np.clip((self.plan_b - z) / self.plan_b, 0.0, 1.0)
        return np.where(z < self.plan_b, self.plan_a * np.sqrt(1.0 - u * u), self.plan_a - self.width_taper * (z - self.plan_b))

    def half_height(self, z: np.ndarray | float) -> np.ndarray:
        z = np.asarray(z, dtype=float)
        u = np.clip((self.plan_b - z) / self.plan_b, 0.0, 1.0)
        return np.where(z < self.plan_b, self.height * np.sqrt(1.0 - u * u), self.height - self.height_taper * (z - self.plan_b))

    def rim_z(self, x: float) -> float:
        """Where the bow's rim, on the centre plane, is ``x`` out from the centre line."""
        return self.plan_b * (1.0 - math.sqrt(1.0 - (x / self.plan_a) ** 2))

    def tip_scale(self, z: np.ndarray | float) -> np.ndarray:
        """How far the arm's section has shrunk towards its inner edge at ``z``: 1 ahead of the tip."""
        t = np.clip((np.asarray(z, dtype=float) - self.tip_z[0]) / self.tip_length, 0.0, 1.0)
        n = self.tip_exponent
        return (1.0 - t**n) ** (1.0 / n)

    def top(self, x: np.ndarray | float, z: np.ndarray | float) -> np.ndarray:
        """The hull's top at ``(x, z)`` (bow or arm, before the tip rounding)."""
        w = self.half_width(z)
        return CENTRE_Y + self.half_height(z) * np.sqrt(np.clip(1.0 - (np.asarray(x) / w) ** 2, 0.0, None))

    def bow_ring(self, z: float) -> tuple[np.ndarray, list[bool]]:
        """The bow's section at ``z``: points counter-clockwise from the starboard rim, and per edge whether it is rim band."""
        b = math.radians(self.band_deg)
        uniform = list(np.linspace(0.0, 2.0 * math.pi, self.ring_points, endpoint=False))
        angles = sorted({round(a, 9) for a in uniform + [b, math.pi - b, math.pi + b, 2.0 * math.pi - b]})
        w, h = float(self.half_width(z)), float(self.half_height(z))
        ring = np.array([[w * math.cos(a), CENTRE_Y + h * math.sin(a), z] for a in angles])
        mids = [0.5 * (a0 + a1) for a0, a1 in zip(angles, angles[1:] + [2.0 * math.pi], strict=True)]
        band = [min(abs(math.sin(m)), 1.0) < math.sin(b) - 1e-9 for m in mids]
        return ring, band

    def arm_ring(self, z: float) -> np.ndarray:
        """The right arm's section at ``z``: the ellipse from the inner wall's foot round the rim to its top; the closing
        edge (the last) is the inner wall."""
        w, h = float(self.half_width(z)), float(self.half_height(z))
        edge = math.acos(min(self.inner_x / w, 1.0))
        a = np.linspace(-edge, edge, self.arm_points)
        x, y = w * np.cos(a), h * np.sin(a)
        x[[0, -1]] = self.inner_x
        s = float(self.tip_scale(z))
        return np.column_stack([self.inner_x + s * (x - self.inner_x), CENTRE_Y + s * y, np.full(len(a), z)])

    def bow_solid(self) -> Solid:
        def test(p: np.ndarray, margin: float) -> np.ndarray:
            z = p[:, 2]
            w, h = self.half_width(z), self.half_height(z)
            ok = (z > self.nose_z + margin) & (z < self.rear_z - margin) & (w > margin)
            q = np.clip(1.0 - (p[:, 0] / np.maximum(w, 1e-9)) ** 2, 0.0, None)
            return ok & (np.abs(p[:, 0]) < w - margin) & (np.abs(p[:, 1] - CENTRE_Y) < h * np.sqrt(q) - margin)

        a, h = self.plan_a, self.height
        return Solid(test, ((-a, CENTRE_Y - h, 0.0), (a, CENTRE_Y + h, self.rear_z)))

    def arm_solid(self) -> Solid:
        def test(p: np.ndarray, margin: float) -> np.ndarray:
            z = p[:, 2]
            s = np.maximum(self.tip_scale(z), 1e-6)
            w, h = self.half_width(z), self.half_height(z)
            x0 = self.inner_x + (p[:, 0] - self.inner_x) / s
            yr = (p[:, 1] - CENTRE_Y) / s
            q = np.clip(1.0 - (x0 / w) ** 2, 0.0, None)
            ok = (z > self.rear_z + margin) & (z < self.tip_z[1] - margin) & (p[:, 0] > self.inner_x + margin)
            return ok & (x0 < w - margin / s) & (np.abs(yr) < h * np.sqrt(q) - margin / s)

        w0, h0 = float(self.half_width(self.rear_z)), float(self.half_height(self.rear_z))
        return Solid(test, ((self.inner_x, CENTRE_Y - h0, self.rear_z), (w0, CENTRE_Y + h0, self.tip_z[1])))

    def bow_stations(self) -> list[float]:
        """Dense near the round nose (equal steps of the plan's angle), then on to the rear face."""
        phis = np.linspace(math.acos(1.0 - self.nose_z / self.plan_b), 0.5 * math.pi, 30)
        front = [self.plan_b * (1.0 - math.cos(p)) for p in phis]
        front[0] = self.nose_z
        return front + list(np.linspace(self.plan_b, self.rear_z, 4)[1:])

    def arm_stations(self) -> list[float]:
        body = stations([self.rear_z, self.bay_end_z, self.tip_z[0]], 1.0)
        tip = list(np.linspace(self.tip_z[0], self.tip_z[1], 7)[1:])
        return body + tip


def bow(spec: LensSpec, style: Style) -> Piece:
    """The round bow from the nose to its rear face, the pale band round its rim; the rear face between the arms is
    the engine bay's dark back wall (the arms close the rest)."""
    hull, trim, dark = style.material("hull"), style.material("trim_light"), style.material("hull_dark")
    zs = spec.bow_stations()
    rings, band = zip(*(spec.bow_ring(z) for z in zs), strict=True)
    edges = [trim if b else hull for b in band[0]]
    creases = [j for j in range(len(edges)) if edges[j] != edges[j - 1]]
    shell = _without_caps(section_loft(list(rings), edges, hull, creases), len(zs), len(edges), True, False)
    # The back wall: the bow's last section between the two inner walls.
    w, h = float(spec.half_width(spec.rear_z)), float(spec.half_height(spec.rear_z))
    edge = math.acos(spec.inner_x / w)
    top = [(w * math.cos(a), h * math.sin(a)) for a in np.linspace(edge, math.pi - edge, 24)]
    wall = np.array([[x, CENTRE_Y + y, spec.rear_z] for x, y in top + [(-x, -y) for x, y in top]])
    mesh = Mesh.concatenate([shell, _fan(wall, dark, (0.0, 0.0, 1.0))])
    collision = stretch_boxes(shell, [0.0, 4.0, 10.0, spec.rear_z], "s")
    return Piece(Part("bow", mesh, collision=collision, mass_kg=spec.bow_mass_kg), spec.bow_solid(), CENTRE)


@dataclass(frozen=True)
class TipNozzleSpec:
    """The main nozzle set into an arm's flat tip face, its exit on the reference's tip (z 60)."""

    x: float = 12.0  # the tip face's middle
    nozzle: NozzleSpec = NozzleSpec(throat_r=0.85, exit_r=1.2, length=0.6, wall=0.05, segments=32, mass_kg=3_000.0)


@dataclass(frozen=True)
class RetroSpec:
    """The retro on the fairing's axis: it fires forward from where that line leaves the bow's skin, on the centre plane."""

    x: float = 14.6
    radius: float = 1.0


@dataclass(frozen=True)
class RailSpec:
    """The bar along each arm's inner wall."""

    x: tuple[float, float] = (10.39, 10.75)  # into the wall, so the wall behind it is hidden
    y: tuple[float, float] = (-0.64, 0.0)
    z: tuple[float, float] = (18.6, 58.8)


def arm(spec: LensSpec, tip: TipNozzleSpec, retro: RetroSpec, rail: RailSpec, style: Style) -> list[Piece]:
    """The right arm with its rail and tip nozzle. The arm's anchors: ``main`` (the nozzle's exit, aft) and ``retro``
    (on the bow's rim, forward)."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    zs = spec.arm_stations()
    split = zs.index(spec.bay_end_z)
    n = spec.arm_points
    creases = [0, n - 1]
    pieces = []
    for k, (z_run, wall) in enumerate(((zs[: split + 1], dark), (zs[split:], hull))):
        rings = [spec.arm_ring(z) for z in z_run]
        edges = [hull] * (n - 1) + [wall]
        pieces.append(_without_caps(section_loft(rings, edges, hull, creases), len(rings), n, False, k == 1))
    shell = Mesh.concatenate(pieces)
    bell = nozzle(tip.nozzle, style).translated((tip.x, CENTRE_Y, spec.tip_z[1]))
    collision = stretch_boxes(Mesh.concatenate([shell, bell.mesh]), [spec.rear_z, 26.0, 34.0, 42.0, 50.0, 61.0], "s")
    anchors = {"main": bell.anchor("exit"), "retro": Anchor((retro.x, CENTRE_Y, spec.rim_z(retro.x)), (0.0, 0.0, -1.0))}
    arm_part = Part("arm_r", Mesh.concatenate([shell, bell.mesh]), anchors=anchors, collision=collision,
                    mass_kg=spec.arm_mass_kg + tip.nozzle.mass_kg)  # fmt: skip
    (x0, x1), (y0, y1), (z0, z1) = rail.x, rail.y, rail.z
    size, centre = (x1 - x0, y1 - y0, z1 - z0), (0.5 * (x0 + x1), 0.5 * (y0 + y1), 0.5 * (z0 + z1))
    rail_part = Part("rail_r", box(size, dark, center=centre), collision=[Collision("box", centre, size=size)], mass_kg=4_000.0)
    return [Piece(arm_part, spec.arm_solid(), RIGHT), Piece(rail_part, box_solid(size, centre), RIGHT)]


# --- the arm fairings -----------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class FairingSpec:
    """The bulge on each arm's root, upper and lower halves alike: per station ``(z, x_in, x_out, peak)``, its top
    ``peak * profile(u)`` above the centre plane at ``u`` of the way from ``x_in`` to ``x_out``. Only the part above
    and below the arm shows; its blunt front face is the lip."""

    stations: tuple[tuple[float, float, float, float], ...] = (
        (22.1, 11.13, 18.48, 3.865), (24.0, 11.04, 18.32, 3.765), (27.0, 10.86, 18.00, 3.565),
        (30.0, 10.83, 17.58, 3.305), (33.0, 10.85, 17.10, 3.015), (36.0, 11.01, 16.43, 2.645),
        (38.0, 11.25, 15.89, 2.335), (40.0, 11.56, 15.25, 1.995), (41.5, 12.06, 14.49, 1.585),
        (42.6, 12.70, 13.60, 1.0),
    )  # fmt: skip
    profile: tuple[tuple[float, float], ...] = (
        (0.0, 0.80), (0.03, 0.885), (0.1, 0.964), (0.2, 1.0), (0.3, 0.997), (0.4, 0.972), (0.5, 0.927),
        (0.6, 0.868), (0.7, 0.792), (0.8, 0.686), (0.9, 0.548), (0.97, 0.40), (1.0, 0.0),
    )  # fmt: skip
    mass_kg: float = 15_000.0

    def ring(self, z: float, x_in: float, x_out: float, peak: float) -> np.ndarray:
        """Counter-clockwise from the inner foot: the lower curve out to the edge, the upper curve back, the inner wall."""
        u = np.array([p[0] for p in self.profile])
        f = np.array([p[1] for p in self.profile])
        x = x_in + u * (x_out - x_in)
        lower = np.column_stack([x[:-1], CENTRE_Y - peak * f[:-1]])
        upper = np.column_stack([x[::-1], CENTRE_Y + peak * f[::-1]])
        pts = np.vstack([lower, upper])
        return np.column_stack([pts, np.full(len(pts), z)])


def fairing(spec: FairingSpec, style: Style) -> Piece:
    hull = style.material("hull")
    rings = [spec.ring(*s) for s in spec.stations]
    n = len(rings[0])
    mesh = section_loft(rings, [hull] * n, hull, creases=[0, n - 1])
    solid = _loft_solid(2, [s[0] for s in spec.stations], [r[:, :2] for r in rings])
    part = Part("fairing_r", mesh, collision=[_bounds_box(mesh)], mass_kg=spec.mass_kg)
    return Piece(part, solid, RIGHT)


# --- the tip fins ---------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class FinSpec:
    """A hooked fin standing on the arm's tip, the upper one (the lower is its mirror in the centre plane): per height
    ``h`` above the centre plane its leading and trailing edges ``(h, z_front, z_back)``. The plate thins from 1.45 m at
    the root to 0.47 m at the top and leans inboard (inner face ``inner``, outer face ``outer``: x at h, as (x at
    ``h_ref``, change per metre)). The top ``cap_m`` is the gold cap; a light stands on the hook's tip (upper fins)."""

    edges: tuple[tuple[float, float, float], ...] = (
        (1.0, 44.40, 57.15), (2.1, 44.38, 56.22), (2.6, 44.92, 55.78), (3.1, 45.52, 55.32), (4.1, 46.68, 54.72),
        (5.1, 47.58, 54.08), (6.1, 48.12, 53.48), (7.1, 48.28, 52.88), (8.1, 48.12, 52.22), (9.1, 47.72, 51.62),
        (9.6, 47.42, 51.32), (10.1, 46.88, 50.98), (10.6, 46.02, 50.68), (10.9, 44.42, 50.48), (11.1, 43.18, 50.38),
        (11.3, 42.18, 50.28), (11.5, 41.62, 50.12), (11.9, 41.42, 49.88), (12.3, 41.48, 49.62), (12.4, 41.58, 49.48),
        (12.53, 42.0, 49.2),
    )  # fmt: skip
    h_ref: float = 3.105
    inner: tuple[float, float] = (10.785, -0.178)  # the mean of the reference's port and starboard fins
    outer: tuple[float, float] = (12.145, -0.272)
    bevel: float = 0.4  # of the thickness: the edges' chamfers
    cap_m: float = 0.65
    finger_h: float = 10.6  # where the blade's hit box gives way to the hook's
    light_radius: float = 0.14
    light_at: tuple[float, float] = (12.58, 41.95)  # (h, z) of the light on the hook's tip
    rcs_at: tuple[float, float] = (12.1, 42.5)  # (h, z) of the cosmetic RCS port on the outer face, by the hook's tip
    mass_kg: float = 6_000.0

    def faces_x(self, h: float) -> tuple[float, float]:
        return (self.inner[0] + self.inner[1] * (h - self.h_ref), self.outer[0] + self.outer[1] * (h - self.h_ref))

    def ring(self, h: float, z0: float, z1: float) -> np.ndarray:
        """The horizontal section at ``h``: a thin plate from ``z0`` to ``z1`` with chamfered edges, ``(6, 3)``."""
        xi, xo = self.faces_x(h)
        xm, e = 0.5 * (xi + xo), self.bevel * (xo - xi)
        y = CENTRE_Y + h
        return np.array([[xm, y, z0], [xo, y, z0 + e], [xo, y, z1 - e], [xm, y, z1], [xi, y, z1 - e], [xi, y, z0 + e]])

    def lean_basis(self) -> np.ndarray:
        """The plate's frame: columns its outward normal, its up along the lean, and aft."""
        xi0, xo0 = self.faces_x(0.0)
        xi1, xo1 = self.faces_x(1.0)
        lean = math.atan(-0.5 * ((xi1 + xo1) - (xi0 + xo0)))
        c, s = math.cos(lean), math.sin(lean)
        return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def tip_fin(spec: FinSpec, style: Style, upper: bool) -> Piece:
    """The right arm's upper (or lower) fin: hit boxes along its lean for the blade and the hook. Anchor: ``rcs`` (the
    port by the hook's tip, outboard)."""
    hull, gold = style.material("hull"), style.material("stripe")
    rings = [spec.ring(*e) for e in spec.edges]
    top_h = spec.edges[-1][0]
    paints = [[gold if 0.5 * (a[0] + b[0]) > top_h - spec.cap_m else hull] * 6 for a, b in zip(spec.edges, spec.edges[1:])]
    pieces = []
    start = 0
    while start < len(paints):  # one loft per run of paint, so the cap's edge is a hard line
        end = start
        while end + 1 < len(paints) and paints[end + 1] == paints[start]:
            end += 1
        last = end == len(paints) - 1
        run = rings[start : end + 2]
        loft = section_loft(run, paints[start], gold if last else hull)
        pieces.append(_without_caps(loft, len(run), 6, start == 0, last))
        start = end + 1
    meshes = pieces
    if upper:
        h, z = spec.light_at
        xm = 0.5 * sum(spec.faces_x(h))
        r = spec.light_radius
        knob = lathe([(-r, 0.0), (-0.7 * r, 0.71 * r), (0.0, r), (0.7 * r, 0.71 * r), (r, 0.0)], 12, gold)
        meshes = meshes + [knob.translated((xm, CENTRE_Y + h, z))]
    mesh = Mesh.concatenate(meshes)
    basis = spec.lean_basis()
    collision = []
    for name, keep in (("blade", lambda hh: hh <= spec.finger_h + 1e-9), ("hook", lambda hh: hh >= spec.finger_h - 0.3)):
        pts = np.concatenate([r for (hh, _a, _b), r in zip(spec.edges, rings, strict=True) if keep(hh)])
        local = pts @ basis
        lo, hi = local.min(axis=0), local.max(axis=0)
        collision.append(Collision("box", basis @ (0.5 * (lo + hi)), basis=basis, size=hi - lo, name=name))
    solid = _loft_solid(1, [CENTRE_Y + e[0] for e in spec.edges], [r[:, [0, 2]] for r in rings])
    h, z = spec.rcs_at
    port = Anchor((spec.faces_x(h)[1], CENTRE_Y + h, z), (1.0, 0.0, 0.0))
    part = Part("fin_top_r", mesh, anchors={"rcs": port}, collision=collision, mass_kg=spec.mass_kg)
    if upper:
        return Piece(part, solid, RIGHT)
    flip = (0.0, 2.0 * CENTRE_Y, 0.0)
    return Piece(part.transformed(_MIRROR_Y, flip).renamed("fin_bot_r"), solid.transformed(_MIRROR_Y, flip), RIGHT)


# --- the engine bay and main engine ---------------------------------------------------------------------------------
@dataclass(frozen=True)
class BaySpec:
    """The machinery against the bow's rear face between the arms: a central block, a low box on each side reaching the
    arm's wall, the twelve RCS blocks above and below those, two engine mounts and the main engine's drum and nozzle.
    Heights are half-heights about the centre plane."""

    block: tuple[float, float, float, float] = (7.40, 2.89, 18.8, 25.43)  # half-width, half-height, z0, z1
    side: tuple[float, float, float, float, float] = (7.40, 10.75, 0.90, 19.0, 25.28)  # x0, x1, half-height, z0, z1
    rcs_x: tuple[float, float] = (7.43, 9.34)
    rcs_y: tuple[float, float] = (0.635, 1.955)  # above the centre plane (and mirrored below)
    rcs_z: tuple[float, ...] = (20.11, 22.0, 23.85)
    rcs_size_z: float = 1.29
    mount: tuple[float, float, float, float, float] = (2.2, 5.6, 1.53, 25.3, 28.7)  # x0, x1, half-height, z0, z1
    drum: tuple[tuple[float, float], ...] = (
        (25.3, 1.2), (26.2, 1.2), (26.4, 1.58), (29.5, 1.58), (29.6, 1.3), (29.8, 1.62), (30.1, 1.62), (30.2, 1.25),
        (30.47, 1.25),
    )  # fmt: skip
    nozzle: NozzleSpec = NozzleSpec(throat_r=0.85, exit_r=1.2, length=0.9, wall=0.05, segments=36, mass_kg=5_000.0)
    mass_kg: float = 60_000.0
    engine_mass_kg: float = 25_000.0

    def rcs_blocks(self) -> list[tuple[str, np.ndarray, np.ndarray]]:
        """The right side's blocks: name, centre and size (the upper three, then the lower three)."""
        (x0, x1), (y0, y1) = self.rcs_x, self.rcs_y
        size = np.array([x1 - x0, y1 - y0, self.rcs_size_z])
        out = []
        for level, sign in (("up", 1.0), ("down", -1.0)):
            for k, z in enumerate(self.rcs_z):
                out.append((f"rcs_{level}{k}", np.array([0.5 * (x0 + x1), CENTRE_Y + sign * 0.5 * (y0 + y1), z]), size))
        return out


def engine_bay(spec: BaySpec, style: Style) -> list[Piece]:
    """The bay's machinery and the main engine (centre pieces, both sides built)."""
    dark, rcs, metal = style.material("hull_dark"), style.material("rcs"), style.material("nozzle")
    cy = CENTRE_Y
    boxes: list[tuple[tuple[float, float, float], tuple[float, float, float], Material]] = []
    w, h, z0, z1 = spec.block
    boxes.append(((2 * w, 2 * h, z1 - z0), (0.0, cy, 0.5 * (z0 + z1)), dark))
    for sx in (1.0, -1.0):
        x0, x1, hh, s0, s1 = spec.side
        boxes.append(((x1 - x0, 2 * hh, s1 - s0), (sx * 0.5 * (x0 + x1), cy, 0.5 * (s0 + s1)), dark))
        m0, m1, mh, q0, q1 = spec.mount
        boxes.append(((m1 - m0, 2 * mh, q1 - q0), (sx * 0.5 * (m0 + m1), cy, 0.5 * (q0 + q1)), dark))
        for _name, centre, size in spec.rcs_blocks():
            boxes.append((tuple(size), (sx * centre[0], centre[1], centre[2]), rcs))
    meshes = [box(size, mat, center=c) for size, c, mat in boxes]
    solids = [box_solid(size, c) for size, c, _ in boxes]
    bay = Part("bay", Mesh.concatenate(meshes), collision=[
        Collision("box", (0.0, cy, 0.5 * (z0 + z1)), size=(2 * w, 2 * h, z1 - z0), name="block"),
        Collision("box", (0.0, cy, 0.5 * (spec.side[3] + spec.side[4])),
                  size=(2 * spec.side[1], 2 * spec.rcs_y[1], spec.side[4] - spec.side[3]), name="sides"),
        Collision("box", (0.0, cy, 0.5 * (spec.mount[3] + spec.mount[4])),
                  size=(2 * spec.mount[1], 2 * spec.mount[2], spec.mount[4] - spec.mount[3]), name="mounts"),
    ], mass_kg=spec.mass_kg)  # fmt: skip
    bay_solid = Solid(lambda p, m: np.any([s.contains(p, m) for s in solids], axis=0),
                      (np.array([-spec.side[1], cy - h, z0]), np.array([spec.side[1], cy + h, spec.mount[4]])))  # fmt: skip
    profile = list(spec.drum)
    mats = [metal if r > 1.5 else dark for (_z, r) in profile[:-1]]
    drum = lathe([(profile[0][0], 0.0), *profile], 36, [dark, *mats], creases=set(range(1, len(profile))))
    drum = drum.translated((0.0, cy, 0.0))
    bell = nozzle(spec.nozzle, style).translated((0.0, cy, profile[-1][0]))
    exit_z = profile[-1][0] + spec.nozzle.length
    r_max = max(r for _z, r in profile)
    engine = Part("engine", Mesh.concatenate([drum, bell.mesh]), anchors={"exit": bell.anchor("exit")},
                  collision=[Collision("box", (0.0, cy, 0.5 * (profile[0][0] + exit_z)),
                                       size=(2 * r_max, 2 * r_max, exit_z - profile[0][0]))],
                  mass_kg=spec.engine_mass_kg + spec.nozzle.mass_kg)  # fmt: skip
    engine_solid = lathe_solid(profile).translated((0.0, cy, 0.0))
    return [Piece(bay, bay_solid, CENTRE), Piece(engine, engine_solid, CENTRE)]


# --- the dorsal fitting -----------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class DorsalSpec:
    """The raised panel on the bow's top: horizontal sections ``(y, half-width, z_front, z_back)`` from its buried foot
    to its flat top, the front raked back with five windows across it, and a low ring where the turret stands."""

    sections: tuple[tuple[float, float, float, float], ...] = (
        (0.9, 4.90, 1.30, 10.88), (3.95, 3.86, 2.30, 11.58), (4.2, 2.80, 2.42, 11.45),
    )
    windows: int = 5
    window_size: tuple[float, float] = (0.6, 1.2)  # across, up the face
    window_pitch: float = 0.95
    window_y: float = 2.95  # the row's middle
    window_depth: float = 0.16  # half of it stands proud of the face
    turret_at: tuple[float, float] = (0.0, 7.0)  # (x, z)
    turret_ring: tuple[float, float, float] = (1.2, 4.12, 4.3)  # radius, foot, top (the turret mount's height)
    mass_kg: float = 12_000.0

    def rect(self, y: float, w: float, z0: float, z1: float) -> np.ndarray:
        """A horizontal rectangle: front, right, back and left edges."""
        return np.array([[-w, y, z0], [w, y, z0], [w, y, z1], [-w, y, z1]])

    def front_z(self, y: float) -> float:
        ys = [s[0] for s in self.sections]
        return float(np.interp(y, ys, [s[2] for s in self.sections]))


def dorsal_fitting(spec: DorsalSpec, style: Style) -> list[Piece]:
    """The fitting, its windows and turret ring. Anchors: ``turret`` (the ring's top, up), ``windows`` (the row's
    middle on the face, forward)."""
    hull, dark, glass = style.material("hull"), style.material("hull_dark"), style.material("window")
    rings = [spec.rect(*s) for s in spec.sections]
    body = section_loft(rings, [hull] * 4, hull)
    (y0, _w0, f0, _b0), (y1, _w1, f1, _b1) = spec.sections[0], spec.sections[1]
    up = np.array([0.0, y1 - y0, f1 - f0]) / math.hypot(y1 - y0, f1 - f0)
    out = np.array([0.0, up[2], -up[1]])  # the face's outward normal: forward and a little up
    basis = np.column_stack([[1.0, 0.0, 0.0], up, -out])
    wy = spec.window_y
    face = np.array([0.0, wy, spec.front_z(wy)])
    size = (spec.window_size[0], spec.window_size[1], spec.window_depth)
    windows, window_solids = [], []
    for k in range(spec.windows):
        c = face + np.array([(k - 0.5 * (spec.windows - 1)) * spec.window_pitch, 0.0, 0.0])
        windows.append(box(size, glass).transformed(basis, c))
        window_solids.append(box_solid(size).transformed(basis, c))
    r, foot, top = spec.turret_ring
    tx, tz = spec.turret_at
    ring = lathe([(0.0, 0.0), (0.0, r), (top - foot, r), (top - foot, 0.0)], 32, dark, creases={1, 2})
    ring = ring.transformed(_Z_TO_Y, (tx, foot, tz))
    ring_solid = lathe_solid([(0.0, r), (top - foot, r)]).transformed(_Z_TO_Y, (tx, foot, tz))
    fitting = Part(
        "dorsal",
        Mesh.concatenate([body, ring]),
        anchors={"turret": Anchor((tx, top, tz), (0.0, 1.0, 0.0)), "windows": Anchor(face, -out)},
        collision=[_bounds_box(body)],
        mass_kg=spec.mass_kg,
    )
    body_solid = _loft_solid(1, [s[0] for s in spec.sections], [r_[:, [0, 2]] for r_ in rings])
    (blo, bhi), (rlo, rhi) = body_solid.bounds(), ring_solid.bounds()
    fitting_solid = Solid(lambda p, m: body_solid.contains(p, m) | ring_solid.contains(p, m),
                          (np.minimum(blo, rlo), np.maximum(bhi, rhi)))  # fmt: skip
    glass_part = Part("windows", Mesh.concatenate(windows))
    glass_solid = Solid(lambda p, m: np.any([s.contains(p, m) for s in window_solids], axis=0), body_solid.bounds())
    return [Piece(fitting, fitting_solid, CENTRE), Piece(glass_part, glass_solid, CENTRE)]


# --- the turret -----------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class CentauriTurretSpec:
    """A teardrop pod lying fore and aft on a short stalk, twin barrels with gold collars. Turret frame: the pivot at
    the origin on the mount, +Y up, the barrels along -Z, their muzzles ``barrel_m`` ahead of the turning axis."""

    flange: tuple[float, float] = (0.75, 0.15)  # radius, height
    stalk: tuple[float, float] = (0.32, 0.8)  # radius, top
    pod_radius: float = 1.1  # 2.2 m across
    pod_nose: float = -1.2  # the round front's tip (z)
    pod_tail: float = 1.9  # the tapered back's point (z)
    pod_y: float = 1.75  # the pod's axis: the barrels' trunnion
    barrel: BarrelSpec = BarrelSpec(length=2.0, radius=0.09, base_radius=0.15, base_length=0.4, bore_radius=0.05,
                                    bore_depth=0.06, segments=14, mass_kg=0.0)  # fmt: skip
    barrel_x: float = 0.45
    barrel_m: float = 2.6
    collars: tuple[tuple[float, float, float], ...] = ((-1.28, -1.02, 0.2), (-2.42, -2.28, 0.14))  # z0, z1, radius
    mass_kg: float = 3_000.0

    def pod_profile(self, steps: int = 14) -> list[tuple[float, float]]:
        """The pod's outline ``(z, r)``: a round front to its widest, then a smooth taper to the tail's point."""
        r = self.pod_radius
        mid = self.pod_nose + r
        front = [(mid - r * math.cos(a), r * math.sin(a)) for a in np.linspace(0.0, 0.5 * math.pi, steps)]
        back = [(mid + (self.pod_tail - mid) * t, r * math.cos(0.5 * math.pi * t)) for t in np.linspace(0.0, 1.0, steps)[1:]]
        return [(float(z), float(max(rr, 0.0))) for z, rr in front + back]

    def solids(self) -> list[Solid]:
        fr, fh = self.flange
        sr, st = self.stalk
        pod = [(z, r) for z, r in self.pod_profile() if r > 0.0]
        return [
            lathe_solid([(0.0, fr), (fh, fr)]).transformed(_Z_TO_Y),
            lathe_solid([(0.0, sr), (st, sr)]).transformed(_Z_TO_Y),
            lathe_solid(pod).translated((0.0, self.pod_y, 0.0)),
        ]


def centauri_turret(spec: CentauriTurretSpec, style: Style) -> Part:
    """The turret model in its own frame. Anchors: ``pivot`` (up), ``trunnion`` (where the barrels elevate, on the
    turning axis), ``muzzle_l`` and ``muzzle_r`` (forward)."""
    hull, dark, gold = style.material("hull"), style.material("hull_dark"), style.material("stripe")
    fr, fh = spec.flange
    sr, st = spec.stalk
    flange = lathe([(0.0, 0.0), (0.0, fr), (fh, fr), (fh, 0.0)], 32, dark, creases={1, 2}).transformed(_Z_TO_Y)
    stalk = lathe([(0.0, sr), (st, sr)], 24, hull).transformed(_Z_TO_Y)
    pod = lathe(spec.pod_profile(), 36, hull).translated((0.0, spec.pod_y, 0.0))
    mount_z = spec.barrel.length - spec.barrel_m
    anchors = {"pivot": Anchor((0.0, 0.0, 0.0), (0.0, 1.0, 0.0)), "trunnion": Anchor((0.0, spec.pod_y, 0.0))}
    meshes = [flange, stalk, pod]
    for name, x in (("muzzle_r", spec.barrel_x), ("muzzle_l", -spec.barrel_x)):
        b = gun_barrel(spec.barrel, style).translated((x, spec.pod_y, mount_z))
        meshes.append(b.mesh)
        anchors[name] = b.anchor("muzzle")
        for z0, z1, r in spec.collars:
            collar = lathe([(z0, 0.0), (z0, r), (z1, r), (z1, 0.0)], 14, gold, creases={1, 2})
            meshes.append(collar.translated((x, spec.pod_y, 0.0)))
    return Part("turret", Mesh.concatenate(meshes), anchors=anchors, mass_kg=spec.mass_kg)


__all__ = [
    "BaySpec",
    "CENTRE",
    "CENTRE_Y",
    "CentauriTurretSpec",
    "DorsalSpec",
    "FairingSpec",
    "FinSpec",
    "LensSpec",
    "Piece",
    "RIGHT",
    "RailSpec",
    "RetroSpec",
    "TipNozzleSpec",
    "arm",
    "bow",
    "centauri_turret",
    "dorsal_fitting",
    "engine_bay",
    "fairing",
    "stretch_boxes",
    "tip_fin",
]
