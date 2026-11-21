"""Thunderbolt parts after the reference model (docs/design-references.md, "EA Thunderbolt"): the long two-seat
fuselage with its canopy spine and chin box, the nose guns, the wing plates, the centre trunk and tail block, the
faceted engine pod and the tail behind it (engine, two blades, the swept fin).

Every builder here is our own geometry: flat-faceted lofts through stations measured off the reference's silhouettes and
sections (metres; +X starboard, +Y up, +Z aft, the nose at z = 0, which is Godot's -Z forward). The pod and its tail are
authored in the pod frame (the pod's axis on z, the same z as the ship's); everything else in the ship frame, the starboard
side where a part has two.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass
from itertools import pairwise

import numpy as np

from ..core.geometry import Material, Mesh, basis_from_z, box, lathe, unit
from ..styles import Style
from . import Anchor, Collision, Part
from .propulsion import NozzleSpec, RcsSpec, nozzle, rcs_nozzle
from .starfury import BladeSpec, section_loft
from .weapons import BarrelSpec, gun_barrel

Ring2 = tuple[tuple[float, float], ...]
EdgeMaterials = Sequence[Material] | Callable[[int, int], Material]


# --- helpers ----------------------------------------------------------------------------------------------------------
def faceted(rings: Sequence[np.ndarray], materials: EdgeMaterials, front: Material | None, back: Material | None) -> Mesh:
    """A loft with flat facets and hard edges through ``rings`` (each ``(n, 3)``, convex or star-shaped), wound outwards
    whatever the rings' order. ``materials`` paints edge ``j`` (point ``j`` to ``j + 1``) of every segment, or is asked per
    ``(segment, edge)``; ``front`` and ``back`` close the first and last ring (``None`` leaves an end open, where it meets its
    mirror image)."""
    rings = [np.asarray(r, dtype=float).reshape(-1, 3) for r in rings]
    n = len(rings[0])
    pick = materials if callable(materials) else (lambda _s, j: materials[j])
    table: list[Material] = []

    def index(material: Material) -> int:
        if material not in table:
            table.append(material)
        return table.index(material)

    quads: list[tuple[np.ndarray, int]] = []
    outwards = 0.0
    for s, (a, c) in enumerate(pairwise(rings)):
        middle = 0.5 * (a.mean(axis=0) + c.mean(axis=0))
        for j in range(n):
            q = np.array([a[j], a[(j + 1) % n], c[(j + 1) % n], c[j]])
            normal = np.cross(q[1] - q[0], q[2] - q[0]) + np.cross(q[2] - q[0], q[3] - q[0])
            outwards += float(normal @ (q.mean(axis=0) - middle))
            quads.append((q, index(pick(s, j))))
    verts: list[np.ndarray] = []
    faces: list[list[int]] = []
    mats: list[int] = []
    for q, m in quads:
        start = sum(len(v) for v in verts)
        verts.append(q if outwards >= 0.0 else q[::-1])
        for tri in ((0, 1, 2), (0, 2, 3)):
            a, b, c = (verts[-1][k] for k in tri)
            if float(np.linalg.norm(np.cross(b - a, c - a))) > 1e-10:  # a ring point shared with the next ring
                faces.append([start + k for k in tri])
                mats.append(m)
    for ring, neighbour, material in ((rings[0], rings[1], front), (rings[-1], rings[-2], back)):
        if material is None:
            continue
        start = sum(len(v) for v in verts)
        centre = ring.mean(axis=0)
        verts.append(np.concatenate([ring, centre[None]]))
        away = centre - neighbour.mean(axis=0)
        m = index(material)
        for j in range(n):
            a, b = ring[j], ring[(j + 1) % n]
            flip = float(np.cross(a - centre, b - centre) @ away) < 0.0
            faces.append([start + n, start + (j + 1) % n, start + j] if flip else [start + n, start + j, start + (j + 1) % n])
            mats.append(m)
    return Mesh(np.concatenate(verts), np.array(faces), np.array(mats), tuple(table))


def _inside_convex(rings: np.ndarray, points: np.ndarray, margin: float) -> np.ndarray:
    """Whether each 2D point is at least ``margin`` inside its own convex outline (``rings``: ``(N, k, 2)``, either winding)."""
    edges = np.roll(rings, -1, axis=1) - rings
    rel = points[:, None, :] - rings
    cross = (edges[..., 0] * rel[..., 1] - edges[..., 1] * rel[..., 0]) / np.maximum(np.linalg.norm(edges, axis=2), 1e-12)
    area = 0.5 * np.sum(rings[..., 0] * np.roll(rings[..., 1], -1, axis=1) - np.roll(rings[..., 0], -1, axis=1) * rings[..., 1], axis=1)
    return np.all(cross * np.sign(area)[:, None] > margin, axis=1)


def _stations_at(zs: Sequence[float], rings: Sequence[np.ndarray], z: np.ndarray) -> np.ndarray:
    """The outline at each ``z`` between the stations' outlines (``(len(z), k, 2)``, clamped at the ends)."""
    stack = np.asarray(rings, dtype=float)
    zs = np.asarray(zs, dtype=float)
    i = np.clip(np.searchsorted(zs, z, side="right") - 1, 0, len(zs) - 2)
    t = np.clip((z - zs[i]) / (zs[i + 1] - zs[i]), 0.0, 1.0)
    return stack[i] * (1.0 - t)[:, None, None] + stack[i + 1] * t[:, None, None]


def _mirror_x(mesh: Mesh) -> Mesh:
    return Mesh.concatenate([mesh, mesh.mirrored("x")])


def _box(points: Sequence[np.ndarray] | np.ndarray, name: str, along: Sequence[float] = (0.0, 0.0, 1.0),
         normal: Sequence[float] = (0.0, 1.0, 0.0)) -> Collision:
    """The tightest box round ``points`` whose length lies ``along`` and whose thickness is as near ``normal`` as that
    allows: a plate's box follows the plate, not the ship's axes."""
    pts = np.asarray(points, dtype=float).reshape(-1, 3)
    x_axis = unit(np.asarray(along, dtype=float))
    hint = np.asarray(normal, dtype=float)
    y_axis = unit(hint - float(hint @ x_axis) * x_axis)
    basis = np.column_stack([x_axis, y_axis, np.cross(x_axis, y_axis)])
    local = pts @ basis
    lo, hi = local.min(axis=0), local.max(axis=0)
    return Collision("box", basis @ (0.5 * (lo + hi)), basis, size=np.maximum(hi - lo, 0.02), name=name)


def _bands(rings: Sequence[np.ndarray], cuts: Sequence[float], name: str, axis: int = 2) -> list[Collision]:
    """A loft's rings boxed in bands along ``axis``: one box from each cut to the next, so a body that widens or drops along
    its length is followed in steps."""
    out = []
    for k, (a, b) in enumerate(pairwise(cuts)):
        inside = [r for r in rings if a - 1e-6 <= float(r[0, axis]) <= b + 1e-6]
        if len(inside) >= 2:
            out.append(_box(np.concatenate(inside), f"{name}_{k}"))
    return out


def _mirrored_boxes(boxes: Sequence[Collision]) -> list[Collision]:
    """Starboard boxes and their port twins, named ``..._r`` and ``..._l``."""
    flip = np.diag([-1.0, 1.0, 1.0])
    out = []
    for box_ in boxes:
        twin = box_.transformed(flip)
        out += [Collision(box_.kind, box_.center, box_.basis, box_.size, name=f"{box_.name}_r"),
                Collision(twin.kind, twin.center, twin.basis, twin.size, name=f"{box_.name}_l")]
    return out


# --- the fuselage -----------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class BoltStation:
    """One fuselage section, symmetric about x = 0: a narrow keel, the shoulder (the widest point) and a flat deck."""

    z: float
    keel_y: float
    keel_w: float
    shoulder_y: float
    shoulder_w: float
    deck_y: float
    deck_w: float

    def ring(self) -> np.ndarray:
        right = [(self.keel_w, self.keel_y), (self.shoulder_w, self.shoulder_y), (self.deck_w, self.deck_y)]
        return np.array(right + [(-x, y) for x, y in reversed(right)])


@dataclass(frozen=True)
class BoltFuselageSpec:
    """The fuselage from the nose face to where its keel rises into the centre body. Between ``cabin_z`` the deck under the
    canopy is the cabin's floor."""

    stations: tuple[BoltStation, ...]
    cabin_z: tuple[float, float]
    collision_cuts: tuple[float, ...] = (2.0, 5.2)  # where its collision boxes step, between the nose and the tail
    mass_kg: float = 9_000.0

    def station_at(self, z: float) -> BoltStation:
        zs = [s.z for s in self.stations]
        names = ("keel_y", "keel_w", "shoulder_y", "shoulder_w", "deck_y", "deck_w")
        return BoltStation(z, *(float(np.interp(z, zs, [getattr(s, n) for s in self.stations])) for n in names))

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        zs = [s.z for s in self.stations]
        rings = _stations_at(zs, [s.ring() for s in self.stations], p[:, 2])
        return _inside_convex(rings, p[:, :2], margin) & (p[:, 2] >= zs[0] + margin) & (p[:, 2] <= zs[-1] - margin)


def bolt_fuselage(spec: BoltFuselageSpec, style: Style) -> Part:
    """The faceted hull: flanks and keel ``hull``, the cabin floor ``interior``, the end faces dark. Anchors ``nose``, ``tail``."""
    hull, dark, floor = style.material("hull"), style.material("hull_dark"), style.material("interior")
    zs = sorted({s.z for s in spec.stations} | set(spec.cabin_z))
    stations = [spec.station_at(z) for z in zs]
    rings = [np.column_stack([s.ring(), np.full(6, s.z)]) for s in stations]

    def material(segment: int, edge: int) -> Material:
        in_cabin = spec.cabin_z[0] <= 0.5 * (zs[segment] + zs[segment + 1]) <= spec.cabin_z[1]
        return floor if edge == 2 and in_cabin else hull

    mesh = faceted(rings, material, dark, dark)
    first, last = spec.stations[0], spec.stations[-1]
    anchors = {
        "nose": Anchor([0.0, 0.5 * (first.keel_y + first.deck_y), first.z], [0.0, 0.0, -1.0]),
        "tail": Anchor([0.0, 0.5 * (last.keel_y + last.deck_y), last.z], [0.0, 0.0, 1.0]),
    }
    dense = [np.column_stack([spec.station_at(z).ring(), np.full(6, z)]) for z in sorted(set(zs) | set(spec.collision_cuts))]
    return Part("fuselage", mesh, anchors, _bands(dense, (first.z, *spec.collision_cuts, last.z), "band"), spec.mass_kg)


@dataclass(frozen=True)
class SpineStation:
    """One section of the canopy spine on the deck: a trapezoid from its base to its narrower top."""

    z: float
    base_y: float
    base_w: float
    top_y: float
    top_w: float

    def ring(self) -> np.ndarray:
        return np.array([(self.base_w, self.base_y), (self.top_w, self.top_y), (-self.top_w, self.top_y), (-self.base_w, self.base_y)])


@dataclass(frozen=True)
class BoltCanopySpec:
    """The spine along the fuselage's top: glazed in ``panes`` (z ranges, the windscreen first), ``frames`` the bars at
    their ends, plain hull elsewhere. ``eye`` is the front seat's."""

    stations: tuple[SpineStation, ...]
    panes: tuple[tuple[float, float], ...]
    frames: tuple[tuple[float, float], ...]
    eye: tuple[float, float, float]

    def station_at(self, z: float) -> SpineStation:
        zs = [s.z for s in self.stations]
        names = ("base_y", "base_w", "top_y", "top_w")
        return SpineStation(z, *(float(np.interp(z, zs, [getattr(s, n) for s in self.stations])) for n in names))


def bolt_canopy(spec: BoltCanopySpec, style: Style) -> Part:
    """The spine with its panes: sides and roof ``canopy_glass`` in a pane, ``canopy_frame`` in a frame. Anchor ``eye``."""
    hull, glass, frame, dark = (style.material(r) for r in ("hull", "canopy_glass", "canopy_frame", "hull_dark"))
    cuts = {z for span in (*spec.panes, *spec.frames) for z in span}
    zs = sorted({s.z for s in spec.stations} | cuts)
    rings = [np.column_stack([spec.station_at(z).ring(), np.full(4, z)]) for z in zs]

    def material(segment: int, edge: int) -> Material:
        z = 0.5 * (zs[segment] + zs[segment + 1])
        if edge == 3:  # the base lies on the deck
            return hull
        if any(a <= z <= b for a, b in spec.panes):
            return glass
        return frame if any(a <= z <= b for a, b in spec.frames) else hull

    mesh = faceted(rings, material, dark, dark)
    collision = [_box(np.concatenate([r for r in rings if r[0, 2] >= spec.panes[0][0] - 0.2]), "")]  # ahead of the glass it is a low ridge
    return Part("canopy", mesh, {"eye": Anchor(spec.eye, [0.0, 0.0, -1.0])}, collision)


@dataclass(frozen=True)
class ChinSpec:
    """The box under the forward fuselage: ``(z, top y, bottom y, half width)`` stations, its long edges bevelled."""

    stations: tuple[tuple[float, float, float, float], ...]
    bevel: float = 0.12
    mass_kg: float = 1_500.0

    def ring(self, top: float, bottom: float, half: float) -> np.ndarray:
        b = self.bevel
        right = [(half - b, bottom), (half, bottom + b), (half, top - b), (half - b, top)]
        return np.array(right + [(-x, y) for x, y in reversed(right)])

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        zs = [s[0] for s in self.stations]
        rings = _stations_at(zs, [self.ring(*s[1:]) for s in self.stations], p[:, 2])
        return _inside_convex(rings, p[:, :2], margin) & (p[:, 2] >= zs[0] + margin) & (p[:, 2] <= zs[-1] - margin)


def bolt_chin(spec: ChinSpec, style: Style) -> Part:
    rings = [np.column_stack([spec.ring(*s[1:]), np.full(8, s[0])]) for s in spec.stations]
    mesh = faceted(rings, [style.material("hull")] * 8, style.material("hull_panel"), style.material("hull_panel"))
    lo, hi = mesh.bounds()
    return Part("chin", mesh, collision=[Collision("box", 0.5 * (lo + hi), size=hi - lo)], mass_kg=spec.mass_kg)


# --- guns and stores --------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class BoltGunSpec:
    """The nose battery under the chin: one centre cannon, a gun either side and the long store behind each side gun.
    Profiles are ``(z, radius)`` about each body's own axis, muzzle first."""

    centre_at: tuple[float, float] = (0.0, -1.20)
    centre: Ring2 = ((0.0, 0.14), (0.28, 0.16), (0.31, 0.28), (0.83, 0.28), (1.0, 0.22))
    side_at: tuple[float, float] = (0.53, -1.52)
    side: Ring2 = ((0.15, 0.15), (0.46, 0.16), (0.50, 0.22), (1.05, 0.22))
    store_at: tuple[float, float] = (0.46, -1.61)
    store: Ring2 = ((1.05, 0.20), (1.70, 0.28), (3.30, 0.25), (3.59, 0.09))
    bore: float = 0.07
    segments: int = 14
    mass_kg: float = 900.0


def _gun_body(profile: Ring2, bore: float, segments: int, skin: Material, dark: Material) -> Mesh:
    (z0, r0), (z1, r1) = profile[0], profile[-1]
    points = [(z0 + 0.05, 0.0), (z0 + 0.05, bore), (z0, bore), *profile, (z1, 0.0)] if bore > 0.0 else [(z0, 0.0), *profile, (z1, 0.0)]
    materials = [skin] * (len(points) - 1)
    if bore > 0.0:
        materials[0] = materials[1] = dark
    return lathe(points, segments, materials, creases=set(range(1, len(points) - 1)))


def bolt_guns(spec: BoltGunSpec, style: Style) -> Part:
    """The nose battery. Anchors ``muzzle_nose``, ``muzzle_left`` and ``muzzle_right`` (firing along -Z)."""
    barrel, bore, panel = style.material("barrel"), style.material("bore"), style.material("hull_panel")
    cx, cy = spec.centre_at
    meshes = [_gun_body(spec.centre, spec.bore, spec.segments, barrel, bore).translated((cx, cy, 0.0))]
    anchors = {"muzzle_nose": Anchor([cx, cy, spec.centre[0][0]], [0.0, 0.0, -1.0])}
    side = _gun_body(spec.side, 0.6 * spec.bore, spec.segments, barrel, bore).translated((*spec.side_at, 0.0))
    store = _gun_body(spec.store, 0.0, spec.segments, panel, bore).translated((*spec.store_at, 0.0))
    meshes.append(_mirror_x(Mesh.concatenate([side, store])))
    for name, sx in (("right", 1.0), ("left", -1.0)):
        anchors[f"muzzle_{name}"] = Anchor([sx * spec.side_at[0], spec.side_at[1], spec.side[0][0]], [0.0, 0.0, -1.0])
    mesh = Mesh.concatenate(meshes)
    return Part("gun_mount", mesh, anchors, [_box(mesh.vertices, "")], spec.mass_kg)


@dataclass(frozen=True)
class BoltFittingsSpec:
    """What hangs on the centre body, starboard side (mirrored to port): the cannon housing in the wing root, its barrel,
    and the store on its rail under the lower wing."""

    # (z, inner x, outer x, bottom y at the inner side, bottom y at the outer side, top y at the outer side, top y)
    housing: tuple[tuple[float, float, float, float, float, float, float], ...] = (
        (6.50, 0.42, 1.06, 0.04, 0.10, 0.36, 0.44),
        (7.40, 0.42, 1.14, -0.10, 0.12, 0.52, 0.70),
        (8.60, 0.42, 1.23, -0.28, 0.19, 0.58, 0.95),
        (9.25, 0.42, 1.20, 0.10, 0.24, 0.42, 0.50),
    )
    barrel: BarrelSpec = BarrelSpec(length=0.45, radius=0.07, base_radius=0.10, base_length=0.2, bore_radius=0.04, bore_depth=0.05,
                                    segments=12, mass_kg=150.0)
    barrel_at: tuple[float, float] = (0.80, 0.24)
    store_at: tuple[float, float] = (1.10, -1.61)
    store: Ring2 = ((7.89, 0.06), (8.30, 0.17), (10.05, 0.17), (10.51, 0.07))
    store_widen: float = 1.3  # its fins make it wider than tall
    rail: tuple[float, float, float] = (8.5, 10.0, 0.03)  # from z, to z, width
    rail_top_y: float = -1.12
    segments: int = 10
    mass_kg: float = 700.0


def bolt_fittings(spec: BoltFittingsSpec, style: Style) -> Part:
    """Housings, barrels, stores and rails on both sides. Anchors ``muzzle_root_right`` and ``muzzle_root_left``."""
    hull, panel, dark = style.material("hull"), style.material("hull_panel"), style.material("hull_dark")
    rings = [np.array([(xi, yi, z), (xo, yo, z), (xo, yt, z), (xi + 0.25, top, z), (xi, top, z)])
             for z, xi, xo, yi, yo, yt, top in spec.housing]
    meshes = [faceted(rings, [hull] * 5, dark, panel)]
    z_face = spec.housing[0][0]
    gun = gun_barrel(spec.barrel, style).translated((*spec.barrel_at, z_face + 0.05))
    meshes.append(gun.mesh)
    store = _gun_body(spec.store, 0.0, spec.segments, panel, dark).transformed(np.diag([spec.store_widen, 1.0, 1.0]), (*spec.store_at, 0.0))
    z0, z1, width = spec.rail
    top = spec.rail_top_y
    bottom = spec.store_at[1] + 0.9 * max(r for _, r in spec.store)
    meshes += [store, box((width, top - bottom, z1 - z0), dark, center=(spec.store_at[0], 0.5 * (top + bottom), 0.5 * (z0 + z1)))]
    collision = _mirrored_boxes([_box(np.concatenate(rings), "housing"), _box(store.vertices, "store")])
    muzzle = gun.anchor("muzzle").position
    anchors = {
        "muzzle_root_right": Anchor(muzzle, [0.0, 0.0, -1.0]),
        "muzzle_root_left": Anchor(muzzle * np.array([-1.0, 1.0, 1.0]), [0.0, 0.0, -1.0]),
    }
    return Part("fittings", _mirror_x(Mesh.concatenate(meshes)), anchors, collision, spec.mass_kg)


# --- wings ------------------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class ChordStation:
    """One section of a wing plate at ``x``: a flat face at ``flat_y`` and, opposite it, a ridge through ``(z, y)`` points
    from the leading edge to the trailing edge (the same count at every station)."""

    x: float
    flat_y: float
    ridge: tuple[tuple[float, float], ...]

    @property
    def z_le(self) -> float:
        return self.ridge[0][0]

    @property
    def z_te(self) -> float:
        return self.ridge[-1][0]

    def ring(self) -> np.ndarray:
        top = [(self.x, y, z) for z, y in self.ridge]
        flat = [(self.x, self.flat_y, z) for z, _ in reversed(self.ridge)]
        return np.array(top + flat)

    def mid_y(self) -> float:
        return 0.5 * (self.flat_y + float(np.mean([y for _, y in self.ridge])))


@dataclass(frozen=True)
class BoltWingSpec:
    """One wing plate from the centre line to the pod (starboard, the upper one or the lower one): the stations inboard of
    ``split_x`` are the centre body's deck, the rest the arm's wing. ``blister`` is the small pod on the wing near its
    kink: ``(z, x from, x to, y from, y to)`` stations."""

    stations: tuple[ChordStation, ...]
    split_x: float
    blister: tuple[tuple[float, float, float, float, float], ...] = ()
    blister_shear: float = 0.0  # its y climbs this much a metre outboard, as the wing does there
    mass_kg: float = 900.0

    def at(self, x: float) -> ChordStation:
        xs = [s.x for s in self.stations]
        count = len(self.stations[0].ridge)
        ridge = tuple((float(np.interp(x, xs, [s.ridge[k][0] for s in self.stations])),
                       float(np.interp(x, xs, [s.ridge[k][1] for s in self.stations]))) for k in range(count))
        return ChordStation(x, float(np.interp(x, xs, [s.flat_y for s in self.stations])), ridge)

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        """Inside the plate (a point's section is taken between its neighbouring stations)."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        xs = [s.x for s in self.stations]
        rings = _stations_at(xs, [s.ring()[:, [2, 1]] for s in self.stations], np.abs(p[:, 0]))
        return _inside_convex(rings, p[:, [2, 1]], margin) & (np.abs(p[:, 0]) <= xs[-1])


DECK_STEPS = 2  # collision boxes along the centre body's deck: the narrow delta, then the full width
WING_PANELS = ((0, 4), (4, 8))  # the wing's stations (outboard of the split) boxed together, panel by panel


def _dense_ring(station: ChordStation, steps: int = 12) -> np.ndarray:
    """A station's outline with points all along its chord, for boxing the plate in bands."""
    z = np.linspace(station.z_le, station.z_te, steps)
    top = np.interp(z, [p[0] for p in station.ridge], [p[1] for p in station.ridge])
    x = np.full(steps, station.x)
    return np.concatenate([np.column_stack([x, top, z]), np.column_stack([x, np.full(steps, station.flat_y), z])])


def _plate(stations: Sequence[ChordStation], style: Style, root_cap: bool, tip_cap: bool) -> Mesh:
    hull, panel, dark = style.material("hull"), style.material("hull_panel"), style.material("hull_dark")
    n = len(stations[0].ridge)
    edges = [hull] * (2 * n)
    edges[n - 1] = edges[2 * n - 1] = panel  # the blunt trailing and leading edges
    return faceted([s.ring() for s in stations], edges, dark if root_cap else None, dark if tip_cap else None)


def bolt_deck(spec: BoltWingSpec, style: Style) -> Part:
    """The plate's centre part, both sides of the centre line as one mesh."""
    inboard = [s for s in spec.stations if s.x < spec.split_x] + [spec.at(spec.split_x)]
    mesh = _mirror_x(_plate(inboard, style, False, True))
    # Boxes across both sides in steps along the length: the delta widens aft, so each step is as wide as the plate is there.
    xs = np.linspace(0.0, spec.split_x, 19)
    surface = np.concatenate([_dense_ring(spec.at(float(x))) for x in xs])
    z0, z1 = float(surface[:, 2].min()), float(surface[:, 2].max())
    collision = []
    for k, (a, b) in enumerate(pairwise(np.linspace(z0, z1, DECK_STEPS + 1))):
        band = surface[(surface[:, 2] >= a - 1e-9) & (surface[:, 2] <= b + 1e-9)]
        if len(band):
            collision.append(_box(np.concatenate([band, band * np.array([-1.0, 1.0, 1.0])]), f"step_{k}"))
    return Part("deck", mesh, collision=collision, mass_kg=spec.mass_kg)


def bolt_wing(spec: BoltWingSpec, style: Style) -> Part:
    """The plate from ``split_x`` out to the pod, with its blister. Anchors ``root`` and ``tip``; one box along it."""
    outboard = [spec.at(spec.split_x)] + [s for s in spec.stations if s.x > spec.split_x]
    meshes = [_plate(outboard, style, True, True)]
    collision = []
    for k, (a, b) in enumerate(WING_PANELS):
        panel_stations = outboard[a : b + 1]
        first_s, last_s = panel_stations[0], panel_stations[-1]
        # Along the panel's mid-chord line, so the box sweeps with the plate instead of squaring off the space ahead of it.
        along = np.array([last_s.x - first_s.x, last_s.mid_y() - first_s.mid_y(), 0.5 * (last_s.z_le + last_s.z_te - first_s.z_le - first_s.z_te)])
        collision.append(_box(np.concatenate([s.ring() for s in panel_stations]), f"panel_{k}", along))
    if spec.blister:
        panel, dark = style.material("hull_panel"), style.material("hull_dark")
        rings = []
        for z, x0, x1, y0, y1 in spec.blister:
            b = 0.25 * min(x1 - x0, y1 - y0)
            ring = np.array([(x0 + b, y0, z), (x1 - b, y0, z), (x1, y0 + b, z), (x1, y1 - b, z), (x1 - b, y1, z), (x0 + b, y1, z),
                             (x0, y1 - b, z), (x0, y0 + b, z)])
            ring[:, 1] += spec.blister_shear * (ring[:, 0] - 0.5 * (x0 + x1))
            rings.append(ring)
        meshes.append(faceted(rings, [panel] * 8, dark, dark))
    mesh = Mesh.concatenate(meshes)
    first, last = outboard[0], outboard[-1]
    root = np.array([first.x, first.mid_y(), 0.5 * (first.z_le + first.z_te)])
    tip = np.array([last.x, last.mid_y(), 0.5 * (last.z_le + last.z_te)])
    return Part("wing", mesh, {"root": Anchor(root), "tip": Anchor(tip)}, collision, spec.mass_kg)


# --- the centre body --------------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class TrunkSpec:
    """The box between the wings behind the fuselage's shoulders, and the diamond-shaped block on the deck's rear.
    ``trunk``: ``(z, waist half width, waist y, flank half width, flank y, top y)``; ``block``: ``(z, bottom half width,
    bottom y, widest half width, its y, top half width, top y)``."""

    trunk: tuple[tuple[float, float, float, float, float, float], ...] = (
        (8.75, 0.50, -0.40, 1.00, 0.04, 0.70),
        (9.00, 0.50, -0.42, 1.25, 0.14, 0.72),
        (10.45, 0.50, -0.42, 1.25, 0.14, 0.72),
        (10.60, 0.50, -0.30, 1.15, 0.20, 0.72),
    )
    block: tuple[tuple[float, float, float, float, float, float, float], ...] = (
        (10.30, 0.30, 0.30, 0.40, 0.80, 0.36, 0.98),
        (11.10, 0.50, 0.36, 0.70, 0.72, 0.63, 1.03),
        (12.15, 0.40, 0.60, 0.60, 0.76, 0.50, 0.92),
    )
    mass_kg: float = 4_000.0

    def trunk_ring(self, row: tuple[float, ...]) -> np.ndarray:
        _, waist_w, waist_y, flank_w, flank_y, top_y = row
        right = [(waist_w, waist_y), (flank_w, flank_y), (flank_w, top_y)]
        return np.array(right + [(-x, y) for x, y in reversed(right)])

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        zs = [row[0] for row in self.trunk]
        rings = _stations_at(zs, [self.trunk_ring(row) for row in self.trunk], p[:, 2])
        return _inside_convex(rings, p[:, :2], margin) & (p[:, 2] >= zs[0] + margin) & (p[:, 2] <= zs[-1] - margin)


def bolt_trunk(spec: TrunkSpec, style: Style) -> Part:
    hull, panel, dark = style.material("hull"), style.material("hull_panel"), style.material("hull_dark")
    trunk = faceted([np.column_stack([spec.trunk_ring(row), np.full(6, row[0])]) for row in spec.trunk], [hull] * 6, panel, dark)
    rings = []
    for z, bottom_w, bottom_y, wide_w, wide_y, top_w, top_y in spec.block:
        right = [(bottom_w, bottom_y), (wide_w, wide_y), (top_w, top_y)]
        rings.append(np.array([(x, y, z) for x, y in right + [(-x, y) for x, y in reversed(right)]]))
    block = faceted(rings, [hull, hull, panel, hull, hull, hull], dark, dark)
    collision = [_box(trunk.vertices, ""), _box(np.concatenate(rings), "block")]
    return Part("trunk", Mesh.concatenate([trunk, block]), collision=collision, mass_kg=spec.mass_kg)


# --- the engine pod ---------------------------------------------------------------------------------------------------
POD_FACES = ("inner_lower", "bottom", "outer_lower", "outer", "outer_upper", "top", "inner_upper", "inner")


@dataclass(frozen=True)
class BoltPodSpec:
    """A pod in its own frame (its axis on z): an eight-sided body through ``stations`` (``(z, outline)``, the outline's
    points in the order of ``POD_FACES``' edges, from the inner lower corner), a recessed ``collar`` between the nose block
    and the body, a lip under the nose, the retro bell in the nose face and three thruster ports at ``rcs_z``."""

    stations: tuple[tuple[float, Ring2], ...]
    collar: tuple[float, float] = (8.40, 8.65)
    collar_scale: float = 0.88
    lip: tuple[float, float, float, float, float] = (6.78, 7.25, 0.27, -0.76, -0.52)  # from z, to z, half width, y from, y to
    retro: NozzleSpec = NozzleSpec(throat_r=0.13, exit_r=0.22, length=0.20, wall=0.03, segments=14, profile_steps=3)
    retro_at: tuple[float, float] = (-0.05, -0.22)
    neck: tuple[float, float, float] = (12.38, 12.85, 0.12)  # from z, to z, radius: the shaft the engine hangs on
    ring: tuple[float, float, float] = (12.70, 12.85, 0.60)
    rcs: RcsSpec = RcsSpec(base_r=0.16, exit_r=0.07, length=0.09, segments=10)
    rcs_z: float = 9.45
    segments: int = 14
    mass_kg: float = 3_200.0

    @property
    def front_z(self) -> float:
        return self.stations[0][0]

    @property
    def rear_z(self) -> float:
        return self.stations[-1][0]

    def outline_at(self, z: float) -> np.ndarray:
        zs = [s[0] for s in self.stations]
        return _stations_at(zs, [np.array(s[1]) for s in self.stations], np.array([z]))[0]

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        zs = [s[0] for s in self.stations]
        rings = _stations_at(zs, [np.array(s[1]) for s in self.stations], p[:, 2])
        return _inside_convex(rings, p[:, :2], margin) & (p[:, 2] >= zs[0] + margin) & (p[:, 2] <= zs[-1] - margin)


def bolt_pod(spec: BoltPodSpec, style: Style) -> Part:
    """Nose block, collar, body, lip, retro bell, neck and ring, thruster ports. Anchors ``center``, ``front``, ``rear``,
    ``retro`` and ``rcs_px``, ``rcs_py``, ``rcs_ny`` (outboard, up, down); a box on the body and one on the nose block."""
    hull, panel, dark = style.material("hull"), style.material("hull_panel"), style.material("hull_dark")
    c0, c1 = spec.collar
    zs = sorted({z for z, _ in spec.stations} | {c0, c0 + 0.04, c1 - 0.04, c1})
    rings = []
    for z in zs:
        outline = spec.outline_at(z)
        if c0 < z < c1:
            outline = outline.mean(axis=0) + spec.collar_scale * (outline - outline.mean(axis=0))
        rings.append(np.column_stack([outline, np.full(len(outline), z)]))

    def material(segment: int, _edge: int) -> Material:
        z = 0.5 * (zs[segment] + zs[segment + 1])
        return dark if c0 < z < c1 else (panel if z < c0 else hull)

    meshes = [faceted(rings, material, panel, dark)]
    z0, z1, half, y0, y1 = spec.lip
    cx = float(np.mean([p[0] for p in spec.stations[0][1][1:3]]))
    lip_rings = [np.array([(cx - w, y0, z), (cx + w, y0, z), (cx + w, y, z), (cx - w, y, z)]) for z, w, y in ((z0, 0.8 * half, y0 + 0.5 * (y1 - y0)), (z1, half, y1))]
    meshes.append(faceted(lip_rings, [panel] * 4, dark, dark))
    retro = nozzle(spec.retro, style).transformed(np.diag([1.0, -1.0, -1.0]), [*spec.retro_at, spec.front_z + 0.9 * spec.retro.length])
    meshes.append(retro.mesh)
    nz0, nz1, nr = spec.neck
    meshes.append(lathe([(nz0, nr), (nz1, nr)], spec.segments, dark))
    rz0, rz1, rr = spec.ring
    meshes.append(lathe([(rz0, 0.0), (rz0, rr), (rz1, rr), (rz1, 0.0)], spec.segments, [panel, panel, dark], creases={1, 2}))
    anchors = {
        "center": Anchor([0.0, 0.0, 0.5 * (spec.front_z + spec.rear_z)]),
        "front": Anchor([0.0, 0.0, spec.front_z], [0.0, 0.0, -1.0]),
        "rear": Anchor([0.0, 0.0, spec.rear_z], [0.0, 0.0, 1.0]),
        "retro": retro.anchor("exit"),
    }
    outline = spec.outline_at(spec.rcs_z)
    for name, direction, edge in (("px", (1.0, 0.0, 0.0), 3), ("py", (0.0, 1.0, 0.0), 5), ("ny", (0.0, -1.0, 0.0), 1)):
        mid = 0.5 * (outline[edge] + outline[(edge + 1) % len(outline)])
        d = np.array(direction)
        cone = rcs_nozzle(spec.rcs, style).transformed(basis_from_z(d), [mid[0] - 0.01 * d[0], mid[1] - 0.01 * d[1], spec.rcs_z])
        meshes.append(cone.mesh)
        anchors[f"rcs_{name}"] = cone.anchor("exit")
    # One box: the pod's faces are flat, and a capsule would stand off its flanks and miss its corners.
    body = _box(np.concatenate([r for r in rings if r[0, 2] >= c1]), "")
    nose = _box(np.concatenate([*lip_rings, *[r for r in rings if r[0, 2] <= c0]]), "nose")
    return Part("pod", Mesh.concatenate(meshes), anchors, [body, nose], spec.mass_kg)


# --- the tail behind a pod ----------------------------------------------------------------------------------------------
@dataclass(frozen=True)
class BoltTailSpec:
    """What hangs behind a pod, in the pod's frame (the upper starboard one): the engine (a cone from the ring to the bell,
    ``(z, radius)``, on an axis ``engine_at`` off the pod's), the bell, the two blades beside it and the fin swept inboard.
    ``fin`` is the fin's outline, ``(x, y, z)`` points in its plane."""

    engine_at: tuple[float, float] = (0.0, 0.10)
    engine: Ring2 = ((12.85, 0.52), (13.20, 0.63), (13.90, 0.58), (14.32, 0.42))
    bell: NozzleSpec = NozzleSpec(throat_r=0.22, exit_r=0.30, length=0.22, wall=0.04, segments=16, profile_steps=3)
    blades: tuple[BladeSpec, ...] = ()
    fin: tuple[tuple[float, float, float], ...] = ()
    fin_thickness: float = 0.085
    segments: int = 16
    mass_kg: float = 900.0


PRONG_FROM_Z = 15.5  # a plate that ends behind this is a prong with a collision box of its own


def bolt_tail(spec: BoltTailSpec, style: Style) -> Part:
    """Engine, bell, blades and fin. Anchor ``main`` (the bell's exit, exhaust along +Z); a capsule on the engine and its
    plates, a box on each prong and on the fin."""
    hull, dark, metal = style.material("hull"), style.material("hull_dark"), style.material("nozzle")
    ex, ey = spec.engine_at
    z_end = spec.engine[-1][0]
    cone = lathe([(spec.engine[0][0], 0.0), *spec.engine, (z_end, 0.0)], spec.segments, [dark, *[metal] * (len(spec.engine) - 1), dark],
                 creases=set(range(1, len(spec.engine) + 1)))
    bell = nozzle(spec.bell, style).translated([ex, ey, z_end - 0.04])
    meshes = [cone.translated((ex, ey, 0.0)), bell.mesh]
    # The capsule holds the engine and the short plates round it, so it is as wide and as long as they are.
    short = [np.concatenate(b.rings()) for b in spec.blades if b.stations[-1][0] <= PRONG_FROM_Z]
    reach = max([max(r for _, r in spec.engine), *[float(np.percentile(np.linalg.norm(v[:, :2] - [ex, ey], axis=1), 80)) for v in short]])
    z_far = max([z_end + spec.bell.length, *[float(v[:, 2].max()) for v in short]])
    z_near = spec.engine[0][0] - 0.5 * reach  # its cap reaches forward over the ring and the shaft
    collision = [Collision("capsule", [ex, ey, 0.5 * (z_near + z_far)], radius=reach, height=max(z_far - z_near, 2.0 * reach), name="engine")]
    for k, blade in enumerate(spec.blades):
        rings = blade.rings()
        n = len(rings[0])
        edges = [hull] * n
        edges[n // 2 - 1] = edges[n - 1] = dark
        meshes.append(section_loft(rings, edges, dark, strip_caps=True))
        if blade.stations[-1][0] > PRONG_FROM_Z:  # the short plates lie inside the engine's capsule; the prongs reach past it
            across = np.array(blade.stations[0][1][-1]) - np.array(blade.stations[0][1][0])  # the plate's width, in its section
            collision.append(_box(np.concatenate(rings), f"prong_{k}", normal=(-across[1], across[0], 0.0)))
    if spec.fin:
        outline = np.array(spec.fin, dtype=float)
        normal = unit(np.cross(outline[1] - outline[0], outline[-1] - outline[0]))
        half = 0.5 * spec.fin_thickness * normal
        fin = faceted([outline - half, outline + half], [dark] * len(outline), hull, hull)
        meshes.append(fin)
        tip = outline[int(np.argmin(outline[:, 0]))]
        collision.append(_box(fin.vertices, "fin", tip - outline[0], normal))
    return Part("tail", Mesh.concatenate(meshes), {"main": bell.anchor("exit")}, collision, spec.mass_kg)

