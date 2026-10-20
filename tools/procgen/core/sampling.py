"""Surface -> splats: area-weighted, stratified, low-discrepancy sampling of a mesh.

Why it is done this way (the "dotty hull" risk, docs/architecture.md section 7.4):

* **Area weighting.** Every face gets ``area / spacing**2`` samples in expectation, so density
  is the same on a 3 m panel and a 3 cm greeble. The fractional part is rounded
  stochastically (``floor(expected + u)``), which keeps the expectation exact and spreads tiny
  faces' samples across neighbours instead of dropping them all.
* **Low discrepancy inside a face.** Points come from the R2 sequence (Roberts 2018) mapped to
  the triangle with Heitz's low-distortion square-to-triangle map, with a random offset per
  face. The result is close to a blue-noise pattern: no clumps, no holes, so the Gaussian
  overlap needed to close the surface is small and predictable.
* **Oriented, flat Gaussians.** Each splat is a disc in the local tangent plane (rotation from
  the interpolated vertex normal), ``overlap * spacing`` wide and ``thickness * spacing``
  thin along the normal, so neighbours blend into a continuous sheet rather than a cloud.

Positions are exactly on the mesh (barycentric), so the splats, the OBJ and hardpoints derived
from the same parts agree by construction.
"""

from __future__ import annotations

import math
from collections.abc import Iterable, Sequence
from dataclasses import dataclass

import numpy as np

from . import frames
from .geometry import MIRROR_AXES, Material, Mesh, tangent_basis, unit
from .ply import SplatData

# Plastic number: the R2 quasi-random sequence generator.
_R2_G = 1.32471795724474602596
_R2_ALPHA = np.array([1.0 / _R2_G, 1.0 / _R2_G**2])

DEFAULT_OVERLAP = 1.4  # in-plane sigma / spacing (architecture section 9.1: k = 1.4)
DEFAULT_THICKNESS = 0.03  # sigma along the normal / spacing
DEFAULT_OPAQUE_ALPHA = 0.98


@dataclass
class SurfaceSamples:
    """Points on a mesh with their (interpolated) normals, source face and material index."""

    positions: np.ndarray
    normals: np.ndarray
    face: np.ndarray
    material: np.ndarray
    materials: tuple[Material, ...]

    def __post_init__(self) -> None:
        self.positions = np.asarray(self.positions, dtype=np.float64).reshape(-1, 3)
        self.normals = np.asarray(self.normals, dtype=np.float64).reshape(-1, 3)
        self.face = np.asarray(self.face, dtype=np.int64).reshape(-1)
        self.material = np.asarray(self.material, dtype=np.int64).reshape(-1)
        self.materials = tuple(self.materials)
        n = len(self)
        if not (self.normals.shape[0] == self.face.shape[0] == self.material.shape[0] == n):
            raise ValueError("SurfaceSamples arrays disagree in length")
        if n and (self.material.min() < 0 or self.material.max() >= len(self.materials)):
            raise ValueError("material index out of range")

    def __len__(self) -> int:
        return int(self.positions.shape[0])

    def albedo(self) -> np.ndarray:
        table = np.array([m.albedo for m in self.materials], dtype=float).reshape(-1, 3)
        return table[self.material]

    def transmittance(self) -> np.ndarray:
        table = np.array([m.transmittance for m in self.materials], dtype=float)
        return table[self.material]

    def material_flag(self, name: str) -> np.ndarray:
        table = np.array([float(getattr(m, name)) for m in self.materials], dtype=float)
        return table[self.material]

    def transformed(self, rotation: np.ndarray, translation: Sequence[float] = (0.0, 0.0, 0.0)) -> SurfaceSamples:
        r = np.asarray(rotation, dtype=float)
        t = np.asarray(translation, dtype=float)
        return SurfaceSamples(
            self.positions @ r.T + t, unit(self.normals @ r.T), self.face.copy(), self.material.copy(), self.materials
        )

    def translated(self, offset: Sequence[float]) -> SurfaceSamples:
        return self.transformed(np.eye(3), offset)

    def mirrored(self, axis: str) -> SurfaceSamples:
        m = np.eye(3)
        m[MIRROR_AXES[axis], MIRROR_AXES[axis]] = -1.0
        return self.transformed(m)

    def subset(self, mask: np.ndarray) -> SurfaceSamples:
        mask = np.asarray(mask, dtype=bool)
        return SurfaceSamples(
            self.positions[mask], self.normals[mask], self.face[mask], self.material[mask], self.materials
        )

    def symmetrized(self, axes: str) -> SurfaceSamples:
        """Keep the samples on the positive side of each axis in ``axes`` and mirror them, so the
        set is exactly mirror-symmetric (and its mean is exactly zero along those axes)."""
        out = self
        for axis in axes:
            k = MIRROR_AXES[axis]
            positive = out.subset(out.positions[:, k] > 0.0)
            on_plane = out.subset(out.positions[:, k] == 0.0)
            out = SurfaceSamples.concatenate([positive, positive.mirrored(axis), on_plane])
        return out

    @staticmethod
    def concatenate(parts: Iterable[SurfaceSamples]) -> SurfaceSamples:
        parts = list(parts)
        materials: list[Material] = []
        by_name: dict[str, int] = {}
        mats_remapped = []
        for p in parts:
            remap = np.zeros(max(len(p.materials), 1), dtype=np.int64)
            for i, m in enumerate(p.materials):
                if m.name not in by_name:
                    by_name[m.name] = len(materials)
                    materials.append(m)
                elif materials[by_name[m.name]] != m:
                    raise ValueError(f"material {m.name!r} defined twice with different values")
                remap[i] = by_name[m.name]
            mats_remapped.append(remap[p.material] if len(p) else p.material)
        if not parts:
            return SurfaceSamples(np.zeros((0, 3)), np.zeros((0, 3)), np.zeros(0), np.zeros(0), ())
        return SurfaceSamples(
            np.concatenate([p.positions for p in parts]),
            np.concatenate([p.normals for p in parts]),
            np.concatenate([p.face for p in parts]),
            np.concatenate(mats_remapped),
            tuple(materials),
        )


def r2_points(count: int, offset: np.ndarray | Sequence[float] = (0.0, 0.0)) -> np.ndarray:
    """``count`` points of the 2D R2 low-discrepancy sequence in [0, 1)^2, shifted by ``offset``."""
    k = np.arange(1, count + 1, dtype=float)[:, None]
    return np.mod(np.asarray(offset, dtype=float) + k * _R2_ALPHA, 1.0)


def square_to_triangle(uv: np.ndarray) -> np.ndarray:
    """Heitz (2019) low-distortion map from the unit square to barycentrics ``(b0, b1, b2)``."""
    u, v = np.asarray(uv, dtype=float).T.copy()
    swap = v > u
    u2 = np.where(swap, u * 0.5, u - v * 0.5)
    v2 = np.where(swap, v - u * 0.5, v * 0.5)
    return np.stack([1.0 - u2 - v2, u2, v2], axis=1)


def face_sample_counts(areas: np.ndarray, spacing: float, rng: np.random.Generator) -> np.ndarray:
    """Stratified rounding of ``area / spacing**2`` per face (expectation preserved exactly)."""
    expected = np.asarray(areas, dtype=float) / (spacing * spacing)
    return np.floor(expected + rng.random(len(expected))).astype(np.int64)


def sample_mesh(mesh: Mesh, spacing: float, rng: np.random.Generator, smooth: bool = True) -> SurfaceSamples:
    """Uniform surface samples at mean spacing ``spacing`` (about ``area / spacing**2`` of them)."""
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")
    areas = mesh.face_areas()
    counts = face_sample_counts(areas, spacing, rng)
    offsets = rng.random((mesh.face_count, 2))
    total = int(counts.sum())
    if total == 0:
        return SurfaceSamples(np.zeros((0, 3)), np.zeros((0, 3)), np.zeros(0), np.zeros(0), mesh.materials)

    face = np.repeat(np.arange(mesh.face_count), counts)
    first = np.repeat(np.cumsum(counts) - counts, counts)
    k = (np.arange(total) - first + 1).astype(float)[:, None]
    uv = np.mod(offsets[face] + k * _R2_ALPHA, 1.0)
    bary = square_to_triangle(uv)

    a, b, c = mesh.corners()
    positions = bary[:, 0:1] * a[face] + bary[:, 1:2] * b[face] + bary[:, 2:3] * c[face]
    if smooth:
        vn = mesh.vertex_normals()
        f = mesh.faces[face]
        normals = unit(bary[:, 0:1] * vn[f[:, 0]] + bary[:, 1:2] * vn[f[:, 1]] + bary[:, 2:3] * vn[f[:, 2]])
    else:
        normals = mesh.face_normals()[face]
    return SurfaceSamples(positions, normals, face, mesh.face_material[face], mesh.materials)


def effective_layers(overlap: float) -> float:
    """How many splats a ray through a sampled surface crosses, weighted by their Gaussian
    falloff: the integral of ``exp(-r^2 / 2 sigma^2)`` over the plane divided by the area per
    splat, ``2 pi sigma^2 / s^2``."""
    return 2.0 * math.pi * overlap * overlap


def alpha_for_transmittance(transmittance: np.ndarray, overlap: float, opaque_alpha: float = DEFAULT_OPAQUE_ALPHA) -> np.ndarray:
    """Per-splat alpha so that a surface of overlapping splats lets ``transmittance`` through
    (0 means the opaque default)."""
    t = np.asarray(transmittance, dtype=float)
    layers = effective_layers(overlap)
    with np.errstate(divide="ignore"):
        tinted = 1.0 - np.power(np.clip(t, 1e-9, 1.0), 1.0 / layers)
    return np.where(t > 0.0, tinted, opaque_alpha)


def splat_rotations(normals: np.ndarray) -> np.ndarray:
    """Quaternions ``(w, x, y, z)`` whose local Z is the normal (local X/Y span the tangent plane)."""
    n = unit(normals)
    t1, t2 = tangent_basis(n)
    return frames.matrix_to_quat(np.stack([t1, t2, n], axis=-1))


def to_splats(
    samples: SurfaceSamples,
    rgb: np.ndarray,
    spacing: float,
    overlap: float = DEFAULT_OVERLAP,
    thickness: float = DEFAULT_THICKNESS,
    opaque_alpha: float = DEFAULT_OPAQUE_ALPHA,
) -> SplatData:
    """Flat oriented Gaussians for every sample: sigma ``(overlap s, overlap s, thickness s)``."""
    n = len(samples)
    rgb = np.asarray(rgb, dtype=float).reshape(n, 3)
    scale = np.tile(np.array([overlap * spacing, overlap * spacing, thickness * spacing]), (n, 1))
    return SplatData(
        xyz=samples.positions.copy(),
        rgb=rgb,
        alpha=alpha_for_transmittance(samples.transmittance(), overlap, opaque_alpha),
        scale=scale,
        rot=splat_rotations(samples.normals),
        normals=samples.normals.copy(),
    )


def nearest_neighbour_distances(points: np.ndarray, cell: float) -> np.ndarray:
    """Exact nearest-neighbour distance per point using a uniform grid (``cell`` >= the largest
    distance you care about; farther neighbours are reported as ``inf``). For tests and tuning."""
    p = np.asarray(points, dtype=float)
    n = len(p)
    if n < 2:
        return np.full(n, np.inf)
    keys = np.floor(p / cell).astype(np.int64)
    order = np.lexsort((keys[:, 2], keys[:, 1], keys[:, 0]))
    keys_sorted = keys[order]
    best = np.full(n, np.inf)
    # Group points by cell, then compare each cell against its 27 neighbours.
    _, starts, counts = np.unique(keys_sorted, axis=0, return_index=True, return_counts=True)
    cell_index = {tuple(k): i for i, k in enumerate(keys_sorted[starts])}
    for i, (s, c) in enumerate(zip(starts, counts, strict=True)):
        idx = order[s : s + c]
        key = keys_sorted[s]
        neighbours = [idx]
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    if dx == dy == dz == 0:
                        continue
                    j = cell_index.get((key[0] + dx, key[1] + dy, key[2] + dz))
                    if j is not None:
                        neighbours.append(order[starts[j] : starts[j] + counts[j]])
        cand = np.concatenate(neighbours)
        d = np.linalg.norm(p[idx][:, None, :] - p[cand][None, :, :], axis=2)
        d[np.arange(c), np.arange(c)] = np.inf  # self
        best[idx] = d.min(axis=1)
    return best
