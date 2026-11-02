"""Starfury parts after the reference model (docs/design-references.md): the engine pod with its
knuckle, the claw, the two-plate strut, the chin guns and the hull fittings.

Every builder here is our own geometry: lofts and lathes through stations measured off the
reference's silhouettes and sections (metres, Godot frame: +X right, +Y up, -Z forward). The pod
and claw are authored in the pod frame (pod axis = Z, centre at the origin); the strut, guns and
fittings in the ship frame of ``assets/starfury_aurora.py`` (upper-right arm; the asset mirrors
it to the other corners).
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass, field

import numpy as np

from ..core.geometry import Material, Mesh, basis_from_z, box, lathe, loft, unit
from ..styles import Style
from . import Anchor, Collision, Part
from .propulsion import NozzleSpec, RcsSpec, nozzle, rcs_nozzle
from .weapons import BarrelSpec, gun_barrel

Profile = tuple[tuple[float, float], ...]


# --- helpers ----------------------------------------------------------------------------------
def signed_volume(mesh: Mesh) -> float:
    """Volume enclosed by a closed mesh, positive when its faces wind outwards."""
    a, b, c = mesh.corners()
    return float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0)


def outward(mesh: Mesh) -> Mesh:
    """``mesh`` with its faces wound outwards (a closed loft's winding depends on its rings)."""
    return mesh if signed_volume(mesh) >= 0.0 else mesh.flipped()


def closed_loft(rings: Sequence[np.ndarray], material: Material, cap: Material | None = None) -> Mesh:
    """A capped loft through ``rings`` (same point count), normals outwards whatever the ring order."""
    return outward(loft([np.asarray(r, dtype=float) for r in rings], material, cap_material=cap))


def strip_loft(rings: Sequence[np.ndarray], material: Material, cap: Material) -> Mesh:
    """A loft of thickened-polyline rings (``2n`` points: one side out, the other back) whose end
    caps are triangulated as strips across the section, so a bent section's cap stays inside its
    outline (a centroid fan would bridge the bend). Faces wind outwards."""
    rings = [np.asarray(r, dtype=float) for r in rings]
    n = len(rings[0])
    tube = closed_loft(rings, material, cap)
    tube = tube.face_subset(np.arange(tube.face_count) < n * (len(rings) - 1) * 2)
    half = n // 2
    caps = []
    for ring, neighbour in ((rings[0], rings[1]), (rings[-1], rings[-2])):
        away = ring.mean(axis=0) - neighbour.mean(axis=0)
        tris = []
        for i in range(half - 1):
            a, b = ring[i], ring[i + 1]
            c, d = ring[n - 2 - i], ring[n - 1 - i]
            tris += [(a, b, c), (a, c, d)]
        v = np.array([p for tri in tris for p in tri])
        f = np.arange(len(v)).reshape(-1, 3)
        normals = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
        flip = normals @ away < 0.0
        f[flip] = f[flip][:, ::-1]
        caps.append(Mesh(v, f, np.zeros(len(f), dtype=np.int64), (cap,)))
    return Mesh.concatenate([tube, *caps])


def section_loft(
    rings: Sequence[np.ndarray],
    edge_materials: Sequence[Material],
    cap: Material,
    creases: Sequence[int] | None = None,
    strip_caps: bool = False,
) -> Mesh:
    """A closed loft through ``rings`` (each ``(n, 3)``, the same ``n``) where edge ``j`` of the
    section (point ``j`` to ``j + 1``) has material ``edge_materials[j]`` and the surface breaks
    into a hard edge along every point index in ``creases`` (all of them when ``None``: flat
    facets). Caps are centroid fans (star-shaped sections) or, with ``strip_caps``, strips
    across a thickened polyline (``2m`` points, one side out and the other back). Faces wind
    outwards."""
    rings = [np.asarray(r, dtype=float) for r in rings]
    n = len(rings[0])
    crease = set(range(n)) if creases is None else set(creases)
    table: list[Material] = []
    for m in [*edge_materials, cap]:
        if m not in table:
            table.append(m)
    # Vertex columns: a smooth point is one column shared by its two edges, a crease point two.
    cols_in, cols_out, k = [0] * n, [0] * n, 0
    for j in range(n):
        cols_in[j] = k
        cols_out[j] = k + 1 if j in crease else k
        k = cols_out[j] + 1
    verts = np.zeros((len(rings), k, 3))
    for r, ring in enumerate(rings):
        for j in range(n):
            verts[r, cols_in[j]] = ring[j]
            verts[r, cols_out[j]] = ring[j]
    faces, mats = [], []
    for r in range(len(rings) - 1):
        for j in range(n):
            a, b = cols_out[j], cols_in[(j + 1) % n]
            v00, v01, v10, v11 = r * k + a, r * k + b, (r + 1) * k + a, (r + 1) * k + b
            faces += [[v00, v01, v11], [v00, v11, v10]]
            mats += [table.index(edge_materials[j])] * 2
    v = verts.reshape(-1, 3)
    extra, extra_f = [], []
    base = len(v)
    for ring, neighbour in ((rings[0], rings[1]), (rings[-1], rings[-2])):
        start = base + sum(len(e) for e in extra)
        if strip_caps:
            half = n // 2
            pts = ring.copy()
            tris = []
            for i in range(half - 1):
                tris += [(i, i + 1, n - 2 - i), (i, n - 2 - i, n - 1 - i)]
        else:
            pts = np.concatenate([ring, ring.mean(axis=0, keepdims=True)])
            tris = [(n, j, (j + 1) % n) for j in range(n)]
        away = ring.mean(axis=0) - neighbour.mean(axis=0)
        for a, b, c in tris:
            nrm = np.cross(pts[b] - pts[a], pts[c] - pts[a])
            extra_f.append([start + a, start + b, start + c] if nrm @ away >= 0.0 else [start + a, start + c, start + b])
        extra.append(pts)
    v = np.concatenate([v, *extra])
    tube = np.array(faces)
    # Orient the tube outwards: on balance its normals point away from their rings' centres
    # (the caps already face away from the tube).
    ring_c = np.repeat([ring.mean(axis=0) for ring in rings[:-1]], 2 * n, axis=0)
    ring_c = 0.5 * (ring_c + np.repeat([ring.mean(axis=0) for ring in rings[1:]], 2 * n, axis=0))
    p0, p1, p2 = v[tube[:, 0]], v[tube[:, 1]], v[tube[:, 2]]
    nrm = np.cross(p1 - p0, p2 - p0)
    if float(np.einsum("ij,ij->i", nrm, (p0 + p1 + p2) / 3.0 - ring_c).sum()) < 0.0:
        tube = tube[:, ::-1]
    caps = np.array(extra_f)
    mesh = Mesh(v, np.concatenate([tube, caps]), np.array(mats + [table.index(cap)] * len(caps)), tuple(table))
    return mesh


def plate_ring(z_le: float, z_te: float, thickness: float, points: int = 10, chamfer: float = 0.6) -> np.ndarray:
    """``(2 * points, 2)`` outline ``(z, h)`` of a plate section: flat faces ``thickness`` apart
    from the leading edge ``z_le`` to the trailing edge ``z_te``, both edges chamfered to a blunt
    chisel ``chamfer * thickness`` deep. The top face runs leading to trailing edge, the bottom
    back; points 0, 1, ``points - 2`` and ``points - 1`` of each face are the chamfer corners."""
    c = chamfer * thickness / abs(z_te - z_le)
    s = np.concatenate([[0.0, c], np.linspace(c, 1.0 - c, points - 2)[1:-1], [1.0 - c, 1.0]])
    half = np.full(points, 0.5 * thickness)
    half[[0, -1]] = 0.12 * thickness
    z = z_le + (z_te - z_le) * s
    top = np.column_stack([z, half])
    bottom = np.column_stack([z[::-1], -half[::-1]])
    return np.concatenate([top, bottom])


def plate_creases(points: int) -> list[int]:
    """The hard-edged point indices of a ``plate_ring(points=points)`` outline."""
    face = [0, 1, points - 2, points - 1]
    return face + [points + k for k in face]


def thick_polyline(points: np.ndarray, thickness: float) -> np.ndarray:
    """Closed outline ``(2n, 2)`` of a polyline ``(n, 2)`` thickened by ``thickness`` (mitred)."""
    p = np.asarray(points, dtype=float).reshape(-1, 2)
    seg = p[1:] - p[:-1]
    seg /= np.linalg.norm(seg, axis=1, keepdims=True)
    normals_seg = np.column_stack([-seg[:, 1], seg[:, 0]])
    normals = np.empty_like(p)
    normals[0], normals[-1] = normals_seg[0], normals_seg[-1]
    for i in range(1, len(p) - 1):
        m = normals_seg[i - 1] + normals_seg[i]
        m /= np.linalg.norm(m)
        normals[i] = m / max(float(m @ normals_seg[i]), 0.3)
    h = 0.5 * thickness
    return np.concatenate([p + h * normals, (p - h * normals)[::-1]])


# --- the engine pod ---------------------------------------------------------------------------
@dataclass(frozen=True)
class KnuckleSpec:
    """A flared cone standing out of the pod at its knuckle, along ``roll_deg`` (degrees from +X
    towards +Y) at ``z``: ``profile`` is ``(height from the pod axis, radius)`` from inside the
    body out to the tip; the cone is ``stretch`` times longer along Z than across at its base,
    easing to round at ``round_from`` (a height)."""

    roll_deg: float
    z: float
    profile: Profile
    stretch: float = 1.8
    round_from: float = 1.1


@dataclass(frozen=True)
class FuryPodSpec:
    """The Starfury's engine pod along Z, centred on the origin: ``profile`` is the outer surface
    ``(z, r)`` from the front face (the retro intake: a light ring around a recessed dark disc
    holding the retro bell) to the rear face (round the main bell). ``clamps`` are rings of eight
    brackets ``(z_front, z_back, height)``; ``knuckles`` stand out where the strut meets the pod."""

    profile: Profile
    face_ring_r: float = 0.26
    face_recess: float = 0.08
    main: NozzleSpec = NozzleSpec(throat_r=0.3, exit_r=0.43, length=0.55, wall=0.04)
    retro: NozzleSpec = NozzleSpec(throat_r=0.1, exit_r=0.19, length=0.25, wall=0.03, segments=32)
    clamps: tuple[tuple[float, float, float], ...] = ()
    clamp_width: float = 0.1
    rails: tuple[float, float] = (0.0, 0.0)  # z span of eight thin rails on the rear housing
    knuckles: tuple[KnuckleSpec, ...] = ()
    grooves: tuple[float, ...] = ()  # z of the dark groove rings (panel colour)
    segments: int = 48
    mass_kg: float = 5_000.0

    def __post_init__(self) -> None:
        z = [p[0] for p in self.profile]
        if any(b < a for a, b in zip(z, z[1:])):
            raise ValueError("the pod profile must run front to back")
        if not self.retro.exit_r + self.retro.wall < self.face_ring_r < self.profile[0][1]:
            raise ValueError("the retro bell must fit inside the front ring")
        if self.main.exit_r + self.main.wall >= self.rear_radius:
            raise ValueError("the main bell must fit inside the rear face")

    @property
    def front_z(self) -> float:
        return self.profile[0][0]

    @property
    def rear_z(self) -> float:
        return self.profile[-1][0]

    @property
    def length(self) -> float:
        return self.rear_z - self.front_z

    @property
    def radius(self) -> float:
        """The widest radius of the body."""
        return max(r for _, r in self.profile)

    @property
    def rear_radius(self) -> float:
        return self.profile[-1][1]

    @property
    def front_radius(self) -> float:
        return self.profile[0][1]

    @property
    def collision_radius(self) -> float:
        return self.radius

    @property
    def capsule_height(self) -> float:
        """Length of a ``collision_radius`` capsule whose hemispherical caps still wrap the end faces."""
        r, r_end = self.collision_radius, max(self.front_radius, self.rear_radius)
        return self.length + 2.0 * (r - math.sqrt(r**2 - r_end**2))

    def radius_at(self, z: float | np.ndarray) -> np.ndarray:
        zs, rs = zip(*self.profile)
        return np.interp(z, zs, rs)

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        """True for points at least ``margin`` inside the pod body (pod frame)."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        inside = np.hypot(p[:, 0], p[:, 1]) < self.radius_at(p[:, 2]) - margin
        return inside & (p[:, 2] > self.front_z + self.face_recess + margin) & (p[:, 2] < self.rear_z - margin)


def _pod_shell(spec: FuryPodSpec, style: Style) -> Mesh:
    hull, dark, panel = style.material("hull"), style.material("hull_dark"), style.material("hull_panel")
    z0 = spec.front_z
    pts: list[tuple[float, float, Material | None]] = [
        (z0 + spec.face_recess, 0.0, None),
        (z0 + spec.face_recess, spec.face_ring_r, dark),  # the recessed dark disc
        (z0, spec.face_ring_r, dark),  # recess wall
        (z0, spec.front_radius, hull),  # the light ring frame
    ]
    groove_half = 0.06
    for z, r in spec.profile[1:]:
        near = any(abs(z - g) <= groove_half + 1e-9 for g in spec.grooves)
        pts.append((z, r, panel if near else hull))
    pts.append((spec.rear_z, spec.main.exit_r + spec.main.wall + 0.005, dark))  # rear face round the bell
    profile = [(z, r) for z, r, _ in pts]
    materials = [m for _, _, m in pts[1:]]
    xy = np.array(profile)
    d = np.diff(xy, axis=0)
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    turns = np.einsum("ij,ij->i", d[:-1], d[1:])
    creases = {i + 1 for i, c in enumerate(turns) if c < math.cos(math.radians(25.0))}
    return lathe(profile, spec.segments, materials, creases=creases)


def _knuckle(spec: KnuckleSpec, style: Style) -> Mesh:
    """A flared cone along local +Z (lathe), stretched along the pod axis near its base, turned
    out along ``roll_deg``; the tip is a dark-centred cap."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    prof = list(spec.profile)
    materials = [hull] * (len(prof) - 2) + [dark]
    mesh = lathe([(h, r) for h, r in prof] + [(prof[-1][0], 0.0)], 32, materials + [dark], creases={len(prof) - 2, len(prof) - 1})
    v = mesh.vertices.copy()
    # Stretch along the pod axis (local Y after the turn below) where the cone is low.
    h = v[:, 2]
    k = 1.0 + (spec.stretch - 1.0) * np.clip((spec.round_from - h) / (spec.round_from - prof[0][0]), 0.0, 1.0)
    v[:, 1] *= k
    a = math.radians(spec.roll_deg)
    radial = np.array([math.cos(a), math.sin(a), 0.0])
    basis = np.column_stack([np.cross([0.0, 0.0, 1.0], radial), [0.0, 0.0, 1.0], radial])  # local x, y (pod z), z (out)
    mesh = Mesh(v, mesh.faces, mesh.face_material, mesh.materials)
    return mesh.transformed(basis, [0.0, 0.0, spec.z])


def fury_pod(spec: FuryPodSpec, style: Style) -> Part:
    """Shell, main bell (+Z), retro bell (-Z), clamp rings, rails and knuckle cones. Anchors:
    ``center``, ``front``, ``rear``, ``main`` and ``retro`` (bell exits, exhaust directions). The
    main exit is the rearmost point and the retro exit the foremost. One capsule along Z."""
    panel, dark = style.material("hull_panel"), style.material("hull_dark")
    main = nozzle(spec.main, style).translated([0.0, 0.0, spec.rear_z - spec.main.length])
    retro = nozzle(spec.retro, style).transformed(
        np.diag([1.0, -1.0, -1.0]), [0.0, 0.0, spec.front_z + spec.retro.length]
    )
    meshes = [_pod_shell(spec, style), main.mesh, retro.mesh]
    for z_front, z_back, height in spec.clamps:
        zc = 0.5 * (z_front + z_back)
        r = float(np.max(spec.radius_at(np.linspace(z_front, z_back, 5))))
        for k in range(8):
            a = math.radians(45.0 * k)
            radial = np.array([math.cos(a), math.sin(a), 0.0])
            side = np.array([-math.sin(a), math.cos(a), 0.0])
            centre = radial * (r + 0.5 * height - 0.04) + np.array([0.0, 0.0, zc])
            basis = np.column_stack([radial, side, [0.0, 0.0, 1.0]])
            meshes.append(box((height + 0.08, spec.clamp_width, z_back - z_front), panel).transformed(basis, centre))
    if spec.rails[1] > spec.rails[0]:
        z_a, z_b = spec.rails
        for k in range(8):
            a = math.radians(45.0 * k + 22.5)
            radial = np.array([math.cos(a), math.sin(a), 0.0])
            ra, rb = float(spec.radius_at(z_a)), float(spec.radius_at(z_b))
            ring = []
            for z, r in ((z_a, ra), (z_b, rb)):
                c = radial * (r + 0.01) + np.array([0.0, 0.0, z])
                side = np.array([-math.sin(a), math.cos(a), 0.0]) * 0.025
                ring.append(np.array([c - side, c + side, c + side + radial * 0.04, c - side + radial * 0.04]))
            meshes.append(closed_loft(ring, dark))
    for knuckle in spec.knuckles:
        meshes.append(_knuckle(knuckle, style))
    anchors = {
        "center": Anchor([0.0, 0.0, 0.0]),
        "front": Anchor([0.0, 0.0, spec.front_z], [0.0, 0.0, -1.0]),
        "rear": Anchor([0.0, 0.0, spec.rear_z], [0.0, 0.0, 1.0]),
        "main": main.anchor("exit"),
        "retro": retro.anchor("exit"),
    }
    collision = [Collision("capsule", [0.0, 0.0, 0.0], radius=spec.collision_radius, height=spec.capsule_height, name="pod")]
    return Part("pod", Mesh.concatenate(meshes), anchors, collision, spec.mass_kg)


# --- the claw ---------------------------------------------------------------------------------
@dataclass(frozen=True)
class BladeSpec:
    """A bent blade behind the pod (pod frame): at each ``(z, ((x, y), ...))`` station the blade's
    section is that polyline thickened by ``thickness``; consecutive stations are lofted."""

    stations: tuple[tuple[float, tuple[tuple[float, float], ...]], ...]
    thickness: float = 0.1

    def rings(self) -> list[np.ndarray]:
        out = []
        for z, pts in self.stations:
            outline = thick_polyline(np.array(pts, dtype=float), self.thickness)
            out.append(np.column_stack([outline, np.full(len(outline), z)]))
        return out


@dataclass(frozen=True)
class ThrusterBlockSpec:
    """An axis-aligned bracket box (pod frame) joining a claw root to the pod; each face named in
    ``nozzles`` (``px``, ``nx``, ``py``, ``ny``) carries an RCS cone."""

    center: tuple[float, float, float]
    size: tuple[float, float, float]
    nozzles: tuple[str, ...]


_FACE_AXES = {"px": (0, 1.0), "nx": (0, -1.0), "py": (1, 1.0), "ny": (1, -1.0)}


@dataclass(frozen=True)
class FuryClawSpec:
    """The claw behind one pod: ``blades`` (the outboard pincer first) and the thruster blocks."""

    blades: tuple[BladeSpec, ...]
    blocks: tuple[ThrusterBlockSpec, ...] = ()
    rcs: RcsSpec = RcsSpec(base_r=0.07, exit_r=0.1, length=0.09, segments=14)
    collision_blades: int = 1  # the collision box wraps this many leading blades (the pincer)
    mass_kg: float = 1_000.0


def fury_claw(spec: FuryClawSpec, style: Style) -> Part:
    """Blades (``hull``, dark end caps), bracket blocks (``hull_panel``) and RCS cones. Anchors
    ``rcs_<face>``. One box collision primitive along the leading ``collision_blades`` blades
    (their root to their tip)."""
    hull, dark, panel = style.material("hull"), style.material("hull_dark"), style.material("hull_panel")
    meshes: list[Mesh] = []
    anchors: dict[str, Anchor] = {}
    for blade in spec.blades:
        rings = blade.rings()
        n = len(rings[0])
        edges = [hull] * n
        edges[n // 2 - 1] = dark  # the blade's far edge
        edges[n - 1] = dark  # and its near edge
        meshes.append(section_loft(rings, edges, dark, strip_caps=True))
    for block in spec.blocks:
        c = np.array(block.center, dtype=float)
        meshes.append(box(block.size, panel, center=c))
        for face in block.nozzles:
            axis, sign = _FACE_AXES[face]
            direction = np.zeros(3)
            direction[axis] = sign
            base = c + direction * (0.5 * block.size[axis] - 0.01)
            cone = rcs_nozzle(spec.rcs, style).transformed(basis_from_z(direction), base)
            meshes.append(cone.mesh)
            anchors[f"rcs_{face}"] = cone.anchor("exit")
    mesh = Mesh.concatenate(meshes)
    collision = []
    if spec.blades:
        verts = np.concatenate([r for b in spec.blades[: spec.collision_blades] for r in b.rings()])
        root = verts[np.argmin(verts[:, 2])]
        tip = verts[np.argmax(verts[:, 2])]
        x_axis = unit(tip - root)
        y_axis = unit(np.cross([0.0, 1.0, 0.0], x_axis))
        z_axis = np.cross(x_axis, y_axis)
        basis = np.column_stack([x_axis, y_axis, z_axis])
        local = (verts - 0.5 * (root + tip)) @ basis
        lo, hi = local.min(axis=0), local.max(axis=0)
        centre = 0.5 * (root + tip) + basis @ (0.5 * (lo + hi))
        collision.append(Collision("box", centre, basis, size=hi - lo, name="claw"))
    return Part("claw", mesh, anchors, collision, spec.mass_kg)


# --- the strut --------------------------------------------------------------------------------
@dataclass(frozen=True)
class PlateStation:
    """One section of a strut plate at ``x``: the plate's centre height ``y``, ``thickness`` and
    chord from ``z_le`` to ``z_te``."""

    x: float
    y: float
    thickness: float
    z_le: float
    z_te: float


@dataclass(frozen=True)
class FuryStrutSpec:
    """One arm's strut (ship frame, upper right): the ``deck`` plate runs from the centre line
    over the fuselage's top out to the pod; the ``brace`` plate climbs from the fuselage's
    shoulder to meet it. From ``merge_x`` out the two are one beam (the deck's top, the brace's
    underside) with a ``slot_depth`` deep dark slot between them along both edges, crossed by
    ``rungs`` every ``rung_pitch`` metres (ladder bays). ``bands`` are hazard stripes on the
    top just behind the leading edge: ``(x_from, x_to, material)``."""

    deck: tuple[PlateStation, ...]
    brace: tuple[PlateStation, ...]
    merge_x: float = 2.9
    slot_depth: float = 0.22
    rung_pitch: float = 0.3
    bands: tuple[tuple[float, float, str], ...] = ()
    band_depth: float = 0.5  # chord depth of the hazard band behind the leading edge
    mass_kg: float = 1_500.0


PLATE_POINTS = 10  # points along each face of a plate section


def _plate(stations: Sequence[PlateStation], material: Material, cap: Material) -> Mesh:
    rings = []
    for s in stations:
        outline = plate_ring(s.z_le, s.z_te, s.thickness, PLATE_POINTS)
        rings.append(np.column_stack([np.full(len(outline), s.x), s.y + outline[:, 1], outline[:, 0]]))
    return section_loft(rings, [material] * len(rings[0]), cap, creases=plate_creases(PLATE_POINTS))


def _interp_station(stations: Sequence[PlateStation], x: float) -> PlateStation:
    xs = [s.x for s in stations]
    return PlateStation(
        x,
        *(float(np.interp(x, xs, [getattr(s, n) for s in stations])) for n in ("y", "thickness", "z_le", "z_te")),
    )


def _beam_ring(d: PlateStation, b: PlateStation, depth: float) -> np.ndarray:
    """The merged section at ``d.x``: the deck's top face, the trailing slot, the brace's
    underside, the leading slot (``(n, 3)``, see ``_beam_materials`` for the edges)."""
    top = plate_ring(d.z_le, d.z_te, d.thickness, PLATE_POINTS)[:PLATE_POINTS]
    bottom = plate_ring(b.z_le, b.z_te, b.thickness, PLATE_POINTS)[PLATE_POINTS:]
    yd, yb = d.y - 0.5 * d.thickness, b.y + 0.5 * b.thickness
    zy = [(z, d.y + h) for z, h in top]
    zy += [(d.z_te - 0.05, yd), (d.z_te - depth, yd), (b.z_te - depth, yb), (b.z_te - 0.05, yb)]
    zy += [(z, b.y + h) for z, h in bottom]
    zy += [(b.z_le + 0.05, yb), (b.z_le + depth, yb), (d.z_le + depth, yd), (d.z_le + 0.05, yd)]
    return np.array([[d.x, y, z] for z, y in zy])


def fury_strut(spec: FuryStrutSpec, style: Style) -> Part:
    """Deck and brace plates inboard of ``merge_x``, the slotted beam outboard of it, ladder
    rungs in the slots and hazard bands on top. Anchors ``root`` and ``tip``; one box collision
    primitive along the beam (brace root to tip)."""
    hull, dark, panel = style.material("hull"), style.material("hull_dark"), style.material("hull_panel")
    xm = spec.merge_x
    inboard = [s for s in spec.deck if s.x < xm] + [_interp_station(spec.deck, xm + 0.02)]
    brace_in = [s for s in spec.brace if s.x < xm] + [_interp_station(spec.brace, xm + 0.02)]
    deck = _plate(inboard, hull, dark)
    brace = _plate(brace_in, hull, dark)
    xs = [xm] + [s.x for s in spec.deck if s.x > xm]
    rings = [_beam_ring(_interp_station(spec.deck, x), _interp_station(spec.brace, x), spec.slot_depth) for x in xs]
    p = PLATE_POINTS
    # Edge materials: deck top, slot wall, slot floor (dark), slot wall, brace underside, slot wall, floor, wall.
    edges = [hull] * (p - 1) + [hull, panel, dark, panel, hull] + [hull] * (p - 1) + [hull, panel, dark, panel, hull]
    creases = [0, 1, p - 2, p - 1, p, p + 1, p + 2, p + 3, p + 4, p + 5, p + 6, 2 * p + 2, 2 * p + 3]
    creases += [2 * p + 4, 2 * p + 5, 2 * p + 6, 2 * p + 7]
    beam = section_loft(rings, edges, dark, creases=creases)
    # Hazard bands: faces on top of the deck and the beam, in a band's x span, just behind the leading edge.
    top_meshes = []
    for mesh in (deck, beam):
        if spec.bands:
            c, n = mesh.face_centroids(), mesh.face_normals()
            mats, fm = list(mesh.materials), mesh.face_material.copy()
            le = np.interp(c[:, 0], [s.x for s in spec.deck], [s.z_le for s in spec.deck])
            for x0, x1, name in spec.bands:
                m = style.material(name)
                if m not in mats:
                    mats.append(m)
                sel = (c[:, 0] >= x0) & (c[:, 0] <= x1) & (n[:, 1] > 0.5) & (c[:, 2] - le < spec.band_depth)
                fm[sel] = mats.index(m)
            mesh = Mesh(mesh.vertices, mesh.faces, fm, tuple(mats))
        top_meshes.append(mesh)
    meshes = [*top_meshes, brace]
    # Rungs across both slots.
    for x in np.arange(xm + 0.15, spec.deck[-1].x - 0.4, spec.rung_pitch):
        d, b = _interp_station(spec.deck, float(x)), _interp_station(spec.brace, float(x))
        y0, y1 = b.y + 0.5 * b.thickness, d.y - 0.5 * d.thickness
        for z in (0.5 * (d.z_le + b.z_le) + 0.5 * spec.slot_depth, 0.5 * (d.z_te + b.z_te) - 0.5 * spec.slot_depth):
            meshes.append(box((0.07, y1 - y0 + 0.04, spec.slot_depth), panel, center=(x, 0.5 * (y0 + y1), z)))
    mesh = Mesh.concatenate(meshes)
    root = np.array([spec.brace[0].x, spec.brace[0].y, 0.5 * (spec.brace[0].z_le + spec.brace[0].z_te)])
    tip_s = spec.deck[-1]
    tip = np.array([tip_s.x, 0.5 * (tip_s.y + spec.brace[-1].y), 0.5 * (tip_s.z_le + tip_s.z_te)])
    x_axis = unit(tip - root)
    y_axis = unit(np.cross([0.0, 0.0, 1.0], x_axis))
    z_axis = np.cross(x_axis, y_axis)
    basis = np.column_stack([x_axis, y_axis, z_axis])
    local = (mesh.vertices - root) @ basis
    lo, hi = local.min(axis=0), local.max(axis=0)
    centre = root + basis @ (0.5 * (lo + hi))
    return Part(
        "strut",
        mesh,
        anchors={"root": Anchor(root), "tip": Anchor(tip)},
        collision=[Collision("box", centre, basis, size=hi - lo, name="strut")],
        mass_kg=spec.mass_kg,
    )


# --- the chin guns ----------------------------------------------------------------------------
@dataclass(frozen=True)
class FuryGunSpec:
    """The chin (ship frame): a keel box along the centre line, and per side a long gun fairing
    ending in a gun block that carries the main barrel (the muzzle) above a second, shorter one.
    ``barrel_x``/``barrel_y`` place the main barrels (mirrored in x), their muzzles at ``muzzle_z``."""

    keel: tuple[float, float, float, float, float] = (0.25, -1.25, -1.78, -4.72, 0.25)  # half-width, top, bottom, z front, z back
    fairing: tuple[float, float, float, float, float, float] = (0.78, -1.5, 0.46, 0.45, -3.2, -0.55)  # x, y, width, height, z front, z back
    block: tuple[float, float, float, float, float, float] = (0.52, 1.05, -1.18, -1.95, -4.25, -3.2)  # x0, x1, y_top, y_bottom, z front, z back
    barrel: BarrelSpec = BarrelSpec(length=1.05, radius=0.12, base_radius=0.16, base_length=0.35, bore_radius=0.07)
    barrel_x: float = 0.72
    barrel_y: float = -1.38
    muzzle_z: float = -4.65
    second: tuple[float, float, float, float] = (0.92, -1.77, 0.11, 0.65)  # x, y, radius, length
    mass_kg: float = 2_000.0

    def __post_init__(self) -> None:
        if self.barrel_x <= self.barrel.base_radius:
            raise ValueError("the barrels would overlap")


def _rounded_rect(cx: float, cy: float, w: float, h: float, z: float, points: int = 16) -> np.ndarray:
    t = 2.0 * math.pi * (np.arange(points) + 0.5) / points
    c, s = np.cos(t), np.sin(t)
    x = cx + 0.5 * w * np.sign(c) * np.abs(c) ** 0.5
    y = cy + 0.5 * h * np.sign(s) * np.abs(s) ** 0.5
    return np.column_stack([x, y, np.full(points, z)])


def fury_guns(spec: FuryGunSpec, style: Style) -> Part:
    """Keel box (``hull_panel``), fairings and blocks (``hull``) and the barrels. Anchors
    ``muzzle_left`` / ``muzzle_right``, ``center``; one box collision primitive (the bounds)."""
    hull, panel, dark = style.material("hull"), style.material("hull_panel"), style.material("hull_dark")
    hw, top, bottom, zf, zb = spec.keel
    ch = 0.07
    sec = [(-hw + ch, bottom), (hw - ch, bottom), (hw, bottom + ch), (hw, top), (-hw, top), (-hw, bottom + ch)]

    def keel_ring(z: float, scale: float) -> np.ndarray:
        return np.array([[x * scale, y, z] for x, y in sec])

    meshes = [closed_loft([keel_ring(zf, 0.35), keel_ring(zf + 0.4, 1.0), keel_ring(zb - 0.1, 1.0), keel_ring(zb, 0.8)], panel, dark)]
    anchors = {"center": Anchor([0.0, 0.5 * (top + bottom), 0.5 * (zf + zb)])}
    fx, fy, fw, fh, fzf, fzb = spec.fairing
    x0, x1, by0, by1, bzf, bzb = spec.block
    for name, sx in (("right", 1.0), ("left", -1.0)):
        rings = [
            _rounded_rect(sx * fx, fy, fw, fh, fzf),
            _rounded_rect(sx * fx, fy, fw, fh, fzf + 0.6),
            _rounded_rect(sx * fx, fy, 0.92 * fw, 0.92 * fh, fzb - 0.6),
            _rounded_rect(sx * fx, fy, 0.5 * fw, 0.5 * fh, fzb),
        ]
        meshes.append(closed_loft(rings, hull, dark))
        xa, xb = sorted((sx * x0, sx * x1))
        meshes.append(box((xb - xa, by0 - by1, bzb - bzf), hull, center=(0.5 * (xa + xb), 0.5 * (by0 + by1), 0.5 * (bzf + bzb))))
        barrel = gun_barrel(spec.barrel, style).translated([sx * spec.barrel_x, spec.barrel_y, spec.muzzle_z + spec.barrel.length])
        meshes.append(barrel.mesh)
        anchors[f"muzzle_{name}"] = barrel.anchor("muzzle")
        x2, y2, r2, length2 = spec.second
        second = BarrelSpec(length=length2, radius=r2, base_radius=r2 + 0.03, base_length=0.2, bore_radius=0.06)
        meshes.append(gun_barrel(second, style).translated([sx * x2, y2, bzf - 0.0 + length2 - 0.3]).mesh)
    mesh = Mesh.concatenate(meshes)
    lo, hi = mesh.bounds()
    return Part(
        "gun_mount",
        mesh,
        anchors=anchors,
        collision=[Collision("box", 0.5 * (lo + hi), size=hi - lo, name="gun_mount")],
        mass_kg=spec.mass_kg,
    )


# --- hull fittings ----------------------------------------------------------------------------
@dataclass(frozen=True)
class FittingsSpec:
    """What hugs the fuselage (ship frame, mirrored in x): thruster ``blocks`` on the flanks
    beside the canopy ``(x, y, z, width, height, length)``, each with forward-facing ``ports``
    ``(x, y, radius)``; pointed ``teardrops`` along the lower flanks ``(x, y, z_tip, z_end,
    radius)``; and ``wedges``, the fairings that fill the corner between the flank and the
    deck, a triangle ``((x, y), (x, y), (x, y))`` lofted from ``z_front`` to ``z_back``."""

    blocks: tuple[tuple[float, float, float, float, float, float], ...] = ((1.0, 0.55, -3.6, 0.45, 0.65, 1.0),)
    ports: tuple[tuple[float, float, float], ...] = ((1.07, 0.66, 0.14), (0.9, 0.36, 0.12))
    port_length: float = 0.22
    teardrops: tuple[tuple[float, float, float, float, float], ...] = ((1.05, -0.42, -3.6, -0.5, 0.4),)
    wedges: tuple[tuple[tuple[tuple[float, float], ...], float, float], ...] = (
        (((0.55, 0.98), (0.95, 0.0), (1.3, 0.98)), -3.3, -0.6),
    )


def fury_fittings(spec: FittingsSpec, style: Style) -> Part:
    """Blocks with ports, teardrops and wedges (no mass, no collision: they hug the hull)."""
    hull, panel, dark = style.material("hull"), style.material("hull_panel"), style.material("hull_dark")
    meshes = []
    for sx in (1.0, -1.0):
        for x, y, z, w, h, length in spec.blocks:
            meshes.append(box((w, h, length), panel, center=(sx * x, y, z)))
            z_front = z - 0.5 * length
            for px, py, r in spec.ports:
                prof = [(0.0, 0.0), (0.0, r), (spec.port_length, r), (spec.port_length, 0.6 * r),
                        (spec.port_length - 0.05, 0.6 * r), (spec.port_length - 0.05, 0.0)]  # fmt: skip
                port = lathe(prof, 20, [panel, panel, panel, dark, dark], creases={1, 2, 3, 4})
                meshes.append(port.transformed(np.diag([1.0, -1.0, -1.0]), [sx * px, py, z_front + 0.04]))
        for x, y, z_tip, z_end, r in spec.teardrops:
            length = z_end - z_tip
            prof = [(0.0, 0.0)]
            for k in range(1, 7):
                u = k / 6
                prof.append((0.28 * length * u, r * math.sin(0.5 * math.pi * u) ** 0.8))
            prof += [(0.85 * length, r), (length, 0.55 * r), (length, 0.0)]
            mesh = lathe(prof, 28, hull, creases={len(prof) - 2})
            meshes.append(mesh.translated([sx * x, y, z_tip]))
        for tri, z0, z1 in spec.wedges:
            # Only the exposed outer face (second edge) and the end caps: the others lie on the
            # fuselage's flank and under the deck.
            a, b, c = (np.array(v, dtype=float) for v in tri)
            front, back = [np.array([*v, z0]) for v in (a, b, c)], [np.array([*v, z1]) for v in (a, b, c)]
            verts = np.array([front[1], front[2], back[2], back[1], *front, *back])
            faces = np.array([[0, 1, 2], [0, 2, 3], [4, 6, 5], [7, 8, 9]])
            wedge = Mesh(verts, faces, np.zeros(len(faces), dtype=np.int64), (hull,))
            out = np.array([b[1] - c[1], c[0] - b[0], 0.0]) * np.sign(c[0] - b[0] + 1e-9)
            normals = wedge.face_normals()
            flip = [normals[0] @ out < 0.0, normals[1] @ out < 0.0, normals[2, 2] > 0.0, normals[3, 2] < 0.0]
            faces = np.array([f[::-1] if fl else f for f, fl in zip(faces, flip)])
            wedge = Mesh(verts, faces, np.zeros(len(faces), dtype=np.int64), (hull,))
            meshes.append(wedge if sx > 0.0 else wedge.mirrored("x"))
    return Part("fittings", Mesh.concatenate(meshes))
