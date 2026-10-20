"""Triangle meshes for hard-surface parts: primitives, transforms and per-face/per-vertex queries.

Everything is authored in the Godot frame (+X right, +Y up, -Z forward, metres). Faces are
counter-clockwise seen from outside, so ``face_normals`` point outwards. Vertex sharing is
deliberate: vertices shared between faces are smooth-shaded by ``vertex_normals``, duplicated
vertices make a hard edge. Builders pass ``creases`` where a lathe profile should break.

Each face carries a material index into ``Mesh.materials``; materials are plain data
(:class:`Material`) chosen by a style (``styles/``), so the same primitive serves every faction.
"""

from __future__ import annotations

import math
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from itertools import pairwise

import numpy as np

Vec3 = tuple[float, float, float]


@dataclass(frozen=True)
class Material:
    """A surface finish: linear-RGB albedo plus how the sampler should treat it.

    ``transmittance`` is the fraction of light that should pass through the whole surface
    (0 = opaque hull, 0.7 = tinted glass); the sampler turns it into per-splat alpha.
    ``paneled`` surfaces get the style's panel-line shading. ``metallic`` darkens the ambient
    term a little so bare metal reads differently from paint.
    """

    name: str
    albedo: Vec3
    transmittance: float = 0.0
    paneled: bool = False
    metallic: float = 0.0

    def __post_init__(self) -> None:
        if not self.name:
            raise ValueError("material needs a name")
        if len(self.albedo) != 3 or any(c < 0.0 for c in self.albedo):
            raise ValueError(f"material {self.name!r}: albedo must be 3 non-negative values")
        if not 0.0 <= self.transmittance < 1.0:
            raise ValueError(f"material {self.name!r}: transmittance must be in [0, 1)")


def unit(v: np.ndarray) -> np.ndarray:
    """Normalise along the last axis (zero vectors stay zero)."""
    v = np.asarray(v, dtype=float)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.where(n == 0.0, 1.0, n)


def tangent_basis(n: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Two unit vectors orthogonal to each unit vector in ``n`` (shape ``(..., 3)``), right-handed
    with it: ``cross(e1, e2) == n``."""
    n = np.asarray(n, dtype=float)
    helper = np.where(
        np.abs(n[..., 1:2]) > 0.95, np.array([1.0, 0.0, 0.0]), np.array([0.0, 1.0, 0.0])
    )
    e1 = unit(np.cross(helper, n))
    e2 = np.cross(n, e1)
    return e1, e2


# --- rotations -------------------------------------------------------------------------------
def rotation_x(angle_rad: float) -> np.ndarray:
    c, s = math.cos(angle_rad), math.sin(angle_rad)
    return np.array([[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]])


def rotation_y(angle_rad: float) -> np.ndarray:
    c, s = math.cos(angle_rad), math.sin(angle_rad)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def rotation_z(angle_rad: float) -> np.ndarray:
    c, s = math.cos(angle_rad), math.sin(angle_rad)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def basis_from_z(z_axis: Sequence[float], x_hint: Sequence[float] | None = None) -> np.ndarray:
    """Rotation matrix whose third column is ``z_axis`` and whose first column is as close to
    ``x_hint`` as possible (columns are the local axes in world space)."""
    z = unit(np.asarray(z_axis, dtype=float))
    if x_hint is None:
        x, _ = tangent_basis(z)
    else:
        hint = np.asarray(x_hint, dtype=float)
        x = unit(hint - z * float(hint @ z))
        if np.linalg.norm(x) == 0.0:
            x, _ = tangent_basis(z)
    y = np.cross(z, x)
    return np.stack([x, y, z], axis=1)


MIRROR_AXES = {"x": 0, "y": 1, "z": 2}


def mirror_matrix(axis: str) -> np.ndarray:
    m = np.eye(3)
    m[MIRROR_AXES[axis], MIRROR_AXES[axis]] = -1.0
    return m


# --- mesh ------------------------------------------------------------------------------------
@dataclass
class Mesh:
    """Indexed triangle mesh with one material index per face."""

    vertices: np.ndarray
    faces: np.ndarray
    face_material: np.ndarray
    materials: tuple[Material, ...]

    def __post_init__(self) -> None:
        self.vertices = np.asarray(self.vertices, dtype=np.float64).reshape(-1, 3)
        self.faces = np.asarray(self.faces, dtype=np.int64).reshape(-1, 3)
        self.face_material = np.asarray(self.face_material, dtype=np.int64).reshape(-1)
        self.materials = tuple(self.materials)
        self.validate()

    # -- queries --
    @property
    def vertex_count(self) -> int:
        return int(self.vertices.shape[0])

    @property
    def face_count(self) -> int:
        return int(self.faces.shape[0])

    def validate(self) -> None:
        if self.face_material.shape[0] != self.face_count:
            raise ValueError("one material index per face is required")
        if self.face_count and (self.faces.min() < 0 or self.faces.max() >= self.vertex_count):
            raise ValueError("face index out of range")
        if self.face_count and (
            self.face_material.min() < 0 or self.face_material.max() >= len(self.materials)
        ):
            raise ValueError("material index out of range")
        if not np.all(np.isfinite(self.vertices)):
            raise ValueError("non-finite vertex")

    def corners(self) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        v = self.vertices
        return v[self.faces[:, 0]], v[self.faces[:, 1]], v[self.faces[:, 2]]

    def face_normals(self) -> np.ndarray:
        a, b, c = self.corners()
        return unit(np.cross(b - a, c - a))

    def face_areas(self) -> np.ndarray:
        a, b, c = self.corners()
        return 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)

    def face_centroids(self) -> np.ndarray:
        a, b, c = self.corners()
        return (a + b + c) / 3.0

    def area(self) -> float:
        return float(self.face_areas().sum())

    def area_centroid(self) -> np.ndarray:
        """Surface-area weighted centroid: the expected mean of uniform surface samples."""
        areas = self.face_areas()
        total = areas.sum()
        if total == 0.0:
            return self.vertices.mean(axis=0)
        return (self.face_centroids() * areas[:, None]).sum(axis=0) / total

    def vertex_normals(self) -> np.ndarray:
        """Area-weighted normals per vertex; shared vertices smooth, duplicated ones stay hard."""
        a, b, c = self.corners()
        weighted = np.cross(b - a, c - a)  # 2 * area * normal
        acc = np.zeros_like(self.vertices)
        for k in range(3):
            np.add.at(acc, self.faces[:, k], weighted)
        normals = unit(acc)
        degenerate = np.linalg.norm(acc, axis=1) == 0.0
        if degenerate.any():
            normals[degenerate] = np.array([0.0, 1.0, 0.0])
        return normals

    def bounds(self) -> tuple[np.ndarray, np.ndarray]:
        return self.vertices.min(axis=0), self.vertices.max(axis=0)

    def material_index(self, name: str) -> int:
        for i, m in enumerate(self.materials):
            if m.name == name:
                return i
        raise KeyError(name)

    # -- transforms (all return new meshes) --
    def transformed(self, rotation: np.ndarray, translation: Sequence[float] = (0.0, 0.0, 0.0)) -> Mesh:
        """Apply ``p' = R p + t``. A reflecting ``R`` (det < 0) flips the winding to keep normals outward."""
        r = np.asarray(rotation, dtype=float)
        t = np.asarray(translation, dtype=float)
        verts = self.vertices @ r.T + t
        faces = self.faces if np.linalg.det(r) > 0 else self.faces[:, ::-1]
        return Mesh(verts, faces.copy(), self.face_material.copy(), self.materials)

    def translated(self, offset: Sequence[float]) -> Mesh:
        return self.transformed(np.eye(3), offset)

    def mirrored(self, axis: str) -> Mesh:
        return self.transformed(mirror_matrix(axis))

    def flipped(self) -> Mesh:
        """Reverse every face so normals point the other way (interior surfaces)."""
        return Mesh(self.vertices.copy(), self.faces[:, ::-1].copy(), self.face_material.copy(), self.materials)

    def with_material(self, material: Material) -> Mesh:
        return Mesh(self.vertices.copy(), self.faces.copy(), np.zeros(self.face_count, dtype=np.int64), (material,))

    @staticmethod
    def empty() -> Mesh:
        return Mesh(np.zeros((0, 3)), np.zeros((0, 3), dtype=np.int64), np.zeros(0, dtype=np.int64), ())

    @staticmethod
    def concatenate(meshes: Iterable[Mesh]) -> Mesh:
        """Merge meshes; materials are shared by name (same name must mean the same material)."""
        meshes = list(meshes)
        materials: list[Material] = []
        by_name: dict[str, int] = {}
        verts, faces, face_mat = [], [], []
        offset = 0
        for mesh in meshes:
            remap = np.zeros(max(len(mesh.materials), 1), dtype=np.int64)
            for i, m in enumerate(mesh.materials):
                if m.name not in by_name:
                    by_name[m.name] = len(materials)
                    materials.append(m)
                elif materials[by_name[m.name]] != m:
                    raise ValueError(f"material {m.name!r} defined twice with different values")
                remap[i] = by_name[m.name]
            verts.append(mesh.vertices)
            faces.append(mesh.faces + offset)
            face_mat.append(remap[mesh.face_material] if mesh.face_count else mesh.face_material)
            offset += mesh.vertex_count
        if not meshes:
            return Mesh.empty()
        return Mesh(np.concatenate(verts), np.concatenate(faces), np.concatenate(face_mat), tuple(materials))


# --- primitives ------------------------------------------------------------------------------
def _quad_faces(ring_a: np.ndarray, ring_b: np.ndarray, closed: bool) -> np.ndarray:
    """Triangles between two index rings (``a`` then ``b`` further along the build direction)."""
    n = len(ring_a)
    count = n if closed else n - 1
    i = np.arange(count)
    j = (i + 1) % n
    tri1 = np.stack([ring_a[i], ring_b[j], ring_b[i]], axis=1)
    tri2 = np.stack([ring_a[i], ring_a[j], ring_b[j]], axis=1)
    return np.concatenate([tri1, tri2])


def _fan_faces(ring: np.ndarray, apex: int, closed: bool, apex_first: bool) -> np.ndarray:
    n = len(ring)
    count = n if closed else n - 1
    i = np.arange(count)
    j = (i + 1) % n
    if apex_first:  # apex before the ring along the build direction: normal faces backwards
        return np.stack([np.full(count, apex), ring[j], ring[i]], axis=1)
    return np.stack([np.full(count, apex), ring[i], ring[j]], axis=1)


def box(size: Sequence[float], material: Material, center: Sequence[float] = (0.0, 0.0, 0.0)) -> Mesh:
    """Axis-aligned box with hard edges (24 vertices)."""
    return tapered_box(size[2], (size[0], size[1]), (size[0], size[1]), material, center=center)


def tapered_box(
    length: float,
    size_a: Sequence[float],
    size_b: Sequence[float],
    material: Material,
    center: Sequence[float] = (0.0, 0.0, 0.0),
    offset_b: Sequence[float] = (0.0, 0.0),
    materials_by_face: dict[str, Material] | None = None,
) -> Mesh:
    """Box along local Z from ``-length/2`` (section ``size_a``) to ``+length/2`` (section ``size_b``,
    shifted by ``offset_b`` in X/Y). ``materials_by_face`` overrides materials for ``"front"``
    (-Z), ``"back"`` (+Z), ``"left"``, ``"right"``, ``"top"``, ``"bottom"``."""
    hx_a, hy_a = size_a[0] / 2.0, size_a[1] / 2.0
    hx_b, hy_b = size_b[0] / 2.0, size_b[1] / 2.0
    ox, oy = offset_b
    za, zb = -length / 2.0, length / 2.0
    # Corner order: (-x,-y), (+x,-y), (+x,+y), (-x,+y)
    ring_a = np.array([[-hx_a, -hy_a, za], [hx_a, -hy_a, za], [hx_a, hy_a, za], [-hx_a, hy_a, za]])
    ring_b = np.array(
        [[-hx_b + ox, -hy_b + oy, zb], [hx_b + ox, -hy_b + oy, zb], [hx_b + ox, hy_b + oy, zb], [-hx_b + ox, hy_b + oy, zb]]
    )
    sides = {
        "bottom": (ring_a[0], ring_a[1], ring_b[1], ring_b[0]),
        "right": (ring_a[1], ring_a[2], ring_b[2], ring_b[1]),
        "top": (ring_a[2], ring_a[3], ring_b[3], ring_b[2]),
        "left": (ring_a[3], ring_a[0], ring_b[0], ring_b[3]),
        "front": (ring_a[3], ring_a[2], ring_a[1], ring_a[0]),
        "back": (ring_b[0], ring_b[1], ring_b[2], ring_b[3]),
    }
    overrides = materials_by_face or {}
    verts, faces, mats, table = [], [], [], [material]
    for name, quad in sides.items():
        mat = overrides.get(name, material)
        if mat not in table:
            table.append(mat)
        base = len(verts)
        verts.extend(quad)
        faces.append([base, base + 1, base + 2])
        faces.append([base, base + 2, base + 3])
        mats.extend([table.index(mat)] * 2)
    mesh = Mesh(np.array(verts), np.array(faces), np.array(mats), tuple(table))
    return mesh.translated(center)


def lathe(
    profile: Sequence[tuple[float, float]],
    segments: int,
    materials: Material | Sequence[Material],
    creases: Iterable[int] = (),
    phase: float = 0.0,
) -> Mesh:
    """Revolve a ``(z, r)`` polyline around local Z into a surface of revolution.

    The profile runs front (-Z) to back (+Z) along the outside of the solid; winding is chosen
    so normals point outwards for such a profile (a profile that runs back along an inner wall,
    as in a nozzle bell, keeps consistent outward normals for the solid it encloses).
    ``materials`` is one material or one per profile segment. ``r == 0`` points become poles.
    Rings are shared between neighbouring segments (smooth shading) except at profile indices
    in ``creases``, which get a duplicated ring (hard edge). ``phase`` rotates the first vertex.
    """
    profile = [(float(z), float(r)) for z, r in profile]
    if len(profile) < 2:
        raise ValueError("a lathe profile needs at least two points")
    if segments < 3:
        raise ValueError("a lathe needs at least three segments")
    n_seg = len(profile) - 1
    mats = [materials] * n_seg if isinstance(materials, Material) else list(materials)
    if len(mats) != n_seg:
        raise ValueError(f"expected {n_seg} segment materials, got {len(mats)}")
    table: list[Material] = []
    for m in mats:
        if m not in table:
            table.append(m)
    crease_set = set(creases)

    theta = phase + 2.0 * math.pi * np.arange(segments) / segments
    cos_t, sin_t = np.cos(theta), np.sin(theta)
    verts: list[np.ndarray] = []
    faces: list[np.ndarray] = []
    face_mats: list[np.ndarray] = []

    def ring(index: int) -> np.ndarray:
        z, r = profile[index]
        start = sum(len(v) for v in verts)
        if r == 0.0:
            verts.append(np.array([[0.0, 0.0, z]]))
            return np.array([start])
        verts.append(np.stack([r * cos_t, r * sin_t, np.full(segments, z)], axis=1))
        return start + np.arange(segments)

    current = ring(0)
    for i in range(n_seg):
        nxt = ring(i + 1)
        if len(current) == 1 and len(nxt) == 1:
            raise ValueError("two consecutive poles in a lathe profile")
        if len(current) == 1:
            f = _fan_faces(nxt, int(current[0]), closed=True, apex_first=True)
        elif len(nxt) == 1:
            f = _fan_faces(current, int(nxt[0]), closed=True, apex_first=False)
        else:
            f = _quad_faces(current, nxt, closed=True)
        faces.append(f)
        face_mats.append(np.full(len(f), table.index(mats[i])))
        # Share the ring with the next segment unless a hard edge was requested there.
        current = ring(i + 1) if (i + 1) in crease_set and i + 1 < n_seg else nxt
    return Mesh(np.concatenate(verts), np.concatenate(faces), np.concatenate(face_mats), tuple(table))


def superellipse_ring(width: float, height: float, points: int, exponent: float = 4.0) -> np.ndarray:
    """``(points, 2)`` closed outline of a rounded rectangle (``|x/a|^n + |y/b|^n = 1``), CCW."""
    t = 2.0 * math.pi * (np.arange(points) + 0.5) / points
    c, s = np.cos(t), np.sin(t)
    k = 2.0 / exponent
    x = 0.5 * width * np.sign(c) * np.abs(c) ** k
    y = 0.5 * height * np.sign(s) * np.abs(s) ** k
    return np.stack([x, y], axis=1)


def loft(
    sections: Sequence[np.ndarray],
    material: Material,
    cap_start: bool = True,
    cap_end: bool = True,
    cap_material: Material | None = None,
) -> Mesh:
    """Skin a sequence of closed ``(n, 3)`` rings (same ``n``, ordered front to back, CCW seen
    from the back/+Z side) into a smooth tube; a ``(1, 3)`` section is a pole. Caps are flat fans
    with hard edges."""
    if len(sections) < 2:
        raise ValueError("a loft needs at least two sections")
    cap_material = cap_material or material
    table = [material] if cap_material == material else [material, cap_material]
    verts: list[np.ndarray] = []
    faces: list[np.ndarray] = []
    mats: list[np.ndarray] = []
    rings: list[np.ndarray] = []
    for sec in sections:
        sec = np.asarray(sec, dtype=float).reshape(-1, 3)
        start = sum(len(v) for v in verts)
        verts.append(sec)
        rings.append(start + np.arange(len(sec)))
    for a, b in pairwise(rings):
        if len(a) == 1 and len(b) == 1:
            raise ValueError("two consecutive poles in a loft")
        if len(a) == 1:
            f = _fan_faces(b, int(a[0]), closed=True, apex_first=True)
        elif len(b) == 1:
            f = _fan_faces(a, int(b[0]), closed=True, apex_first=False)
        else:
            f = _quad_faces(a, b, closed=True)
        faces.append(f)
        mats.append(np.zeros(len(f), dtype=np.int64))

    def cap(ring_idx: int, forward: bool) -> None:
        ring = rings[ring_idx]
        if len(ring) == 1:
            return
        sec = verts[ring_idx]
        start = sum(len(v) for v in verts)
        verts.append(sec.copy())  # duplicate ring: hard edge
        verts.append(sec.mean(axis=0, keepdims=True))
        dup = start + np.arange(len(sec))
        apex = start + len(sec)
        f = _fan_faces(dup, apex, closed=True, apex_first=forward)
        faces.append(f)
        mats.append(np.full(len(f), table.index(cap_material)))

    if cap_start:
        cap(0, forward=True)
    if cap_end:
        cap(len(rings) - 1, forward=False)
    return Mesh(np.concatenate(verts), np.concatenate(faces), np.concatenate(mats), tuple(table))


def ellipsoid_cap(
    radii: Sequence[float],
    base_height: float,
    material: Material,
    rings: int = 10,
    segments: int = 36,
    axis_up: int = 1,
) -> Mesh:
    """The part of an ellipsoid (semi-axes ``radii``) above the plane ``axis_up = base_height``
    (``-r <= base_height < r``), open at the base. Rings share vertices (smooth)."""
    rx, ry, rz = (float(r) for r in radii)
    r_up = (rx, ry, rz)[axis_up]
    if not -r_up <= base_height < r_up:
        raise ValueError("base_height must be inside the ellipsoid")
    lat0 = math.asin(base_height / r_up)
    lats = np.linspace(lat0, math.pi / 2.0, rings + 1)
    theta = 2.0 * math.pi * np.arange(segments) / segments
    verts: list[np.ndarray] = []
    idx_rings: list[np.ndarray] = []
    for k, lat in enumerate(lats):
        start = sum(len(v) for v in verts)
        if k == rings:
            p = np.zeros((1, 3))
            p[0, axis_up] = r_up
            verts.append(p)
            idx_rings.append(np.array([start]))
            continue
        c = math.cos(lat)
        u, v = np.cos(theta) * c, np.sin(theta) * c
        p = np.zeros((segments, 3))
        others = [i for i in range(3) if i != axis_up]
        p[:, others[0]] = u * (rx, ry, rz)[others[0]]
        p[:, others[1]] = v * (rx, ry, rz)[others[1]]
        p[:, axis_up] = math.sin(lat) * r_up
        verts.append(p)
        idx_rings.append(start + np.arange(segments))
    faces: list[np.ndarray] = []
    for a, b in pairwise(idx_rings):
        if len(b) == 1:
            faces.append(_fan_faces(a, int(b[0]), closed=True, apex_first=False))
        else:
            faces.append(_quad_faces(a, b, closed=True))
    mesh = Mesh(np.concatenate(verts), np.concatenate(faces), np.zeros(sum(len(f) for f in faces), dtype=np.int64), (material,))
    # Winding: fix orientation so normals point away from the ellipsoid centre.
    outward = np.einsum("ij,ij->i", mesh.face_normals(), mesh.face_centroids())
    if outward.mean() < 0:
        mesh = mesh.flipped()
    return mesh


def assign_material_by_predicate(mesh: Mesh, material: Material, mask: np.ndarray) -> Mesh:
    """Return a copy where faces selected by ``mask`` (per face) use ``material``."""
    table = list(mesh.materials)
    if material not in table:
        table.append(material)
    face_mat = mesh.face_material.copy()
    face_mat[np.asarray(mask, dtype=bool)] = table.index(material)
    return Mesh(mesh.vertices.copy(), mesh.faces.copy(), face_mat, tuple(table))


@dataclass
class MeshStats:
    vertices: int
    faces: int
    area: float
    bounds_min: np.ndarray
    bounds_max: np.ndarray


def stats(mesh: Mesh) -> MeshStats:
    lo, hi = mesh.bounds()
    return MeshStats(mesh.vertex_count, mesh.face_count, mesh.area(), lo, hi)


__all__ = [
    "Material",
    "Mesh",
    "MeshStats",
    "assign_material_by_predicate",
    "basis_from_z",
    "box",
    "ellipsoid_cap",
    "lathe",
    "loft",
    "mirror_matrix",
    "rotation_x",
    "rotation_y",
    "rotation_z",
    "stats",
    "superellipse_ring",
    "tangent_basis",
    "tapered_box",
    "unit",
]

