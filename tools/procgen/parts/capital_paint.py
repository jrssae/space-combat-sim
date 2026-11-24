"""Paint laid along a capital hull's plates (M10-T67): the darker grey band the Nova's and the Omega's stills show round the
edges of their big plates. Baked into the hull's maps under the seams and the wear (``Marking.paint``)."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Mesh
from ..core.textures import Marking

ON_FACE_M = 0.05  # how near a texel lies to a face's plane to count as on it
FACING = 0.9  # how closely a texel's normal follows the face's
CHUNK = 20000  # texels measured against the edges at a time


@dataclass(frozen=True)
class EdgeBand:
    """A band ``width_m`` wide, ``inset_m`` in from a flat face's edges, its edges softened over ``soft_m``; only on faces at
    least ``min_face_m`` across (twice their area over their perimeter), so a plate's thin edges stay plain."""

    width_m: float = 3.0
    inset_m: float = 0.5
    soft_m: float = 0.3
    min_face_m: float = 12.0


@dataclass(frozen=True)
class _Face:
    normal: np.ndarray
    offset: float
    edges: np.ndarray  # (k, 2, 3): the face's outline as segments


def flat_faces(mesh: Mesh, min_face_m: float) -> list[_Face]:
    """The mesh's flat faces (its triangles grouped by plane) wide enough to carry a band, each with its outline."""
    corners = mesh.vertices[mesh.faces]
    normals, areas = mesh.face_normals(), mesh.face_areas()
    groups: dict[tuple, list[int]] = defaultdict(list)
    for i, (n, t) in enumerate(zip(normals, corners, strict=True)):
        if areas[i] > 1e-9:
            groups[(*np.round(n, 3), round(float(n @ t[0]), 2))].append(i)
    out: list[_Face] = []
    for key, members in groups.items():
        count: dict[tuple, int] = defaultdict(int)
        ends: dict[tuple, tuple[np.ndarray, np.ndarray]] = {}
        for i in members:
            for a, b in ((0, 1), (1, 2), (2, 0)):
                pa, pb = corners[i][a], corners[i][b]
                k = tuple(sorted((tuple(np.round(pa, 3)), tuple(np.round(pb, 3)))))
                count[k] += 1
                ends[k] = (pa, pb)
        outline = [ends[k] for k, c in count.items() if c == 1]
        perimeter = sum(float(np.linalg.norm(b - a)) for a, b in outline)
        area = float(areas[members].sum())
        if outline and 2.0 * area / perimeter >= min_face_m:
            out.append(_Face(np.asarray(key[:3], dtype=float), float(key[3]), np.asarray(outline, dtype=float)))
    return out


def _edge_distance(points: np.ndarray, edges: np.ndarray) -> np.ndarray:
    """Each point's distance to the nearest of ``edges``."""
    a, b = edges[:, 0], edges[:, 1]
    ab = b - a
    length2 = np.maximum(np.einsum("kj,kj->k", ab, ab), 1e-12)
    out = np.empty(len(points))
    for s in range(0, len(points), CHUNK):  # in chunks, so a big plate's texels by its edges stay small in memory
        rel = points[s:s + CHUNK, None, :] - a[None]
        t = np.clip(np.einsum("pkj,kj->pk", rel, ab) / length2, 0.0, 1.0)
        out[s:s + CHUNK] = np.linalg.norm(rel - t[..., None] * ab[None], axis=2).min(axis=1)
    return out


def _smooth(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def band_cover(faces: list[_Face], band: EdgeBand):  # noqa: ANN201
    """How much of the band each texel wears (0..1), in the frame the faces were found in."""
    def cover(points: np.ndarray, normals: np.ndarray) -> np.ndarray:
        out = np.zeros(len(points))
        for f in faces:
            on = (np.abs(points @ f.normal - f.offset) < ON_FACE_M) & (normals @ f.normal > FACING)
            if not on.any():
                continue
            d = _edge_distance(points[on], f.edges)
            inner = _smooth((d - band.inset_m) / band.soft_m)
            outer = 1.0 - _smooth((d - band.inset_m - band.width_m + band.soft_m) / band.soft_m)
            out[on] = np.maximum(out[on], inner * outer)
        return out
    return cover


def edge_band(name: str, mesh: Mesh, colour: tuple[float, float, float], band: EdgeBand = EdgeBand()) -> Marking | None:
    """The band round the edges of part ``name``'s big flat faces in ``colour`` (linear), or none when it has no such face."""
    faces = flat_faces(mesh, band.min_face_m)
    return Marking.paint(name, colour, band_cover(faces, band), placed=True) if faces else None


__all__ = ["EdgeBand", "band_cover", "edge_band", "flat_faces"]
