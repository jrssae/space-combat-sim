"""Charts and the atlas packer (M4-T30a): one 0..1 texture space for a hull's parts at one texel size.

A chart is a set of faces with 2D coordinates in metres. Primitives that know their parametrisation wrote theirs (``Mesh.face_uv``,
``Mesh.face_chart``); every other face is unwrapped here by growing regions of nearly parallel faces and projecting each onto its
mean plane, which keeps the stretch small on curved hand-built hulls. The packer puts every chart on a shelf row at the asked texel
size, with a gutter so filtering never reads a neighbour, and grows the texel until the atlas holds them all.
"""

from __future__ import annotations

import math
from collections import deque
from dataclasses import dataclass, field

import numpy as np

from .geometry import NO_CHART, Mesh, tangent_basis, unit

DEFAULT_ANGLE_DEG = 40.0
GROW = 1.04  # texel growth per packing attempt
MAX_ATTEMPTS = 400


def uv_area(uv: np.ndarray) -> np.ndarray:
    """Signed area of each UV triangle in ``(..., 3, 2)``."""
    uv = np.asarray(uv, dtype=float)
    a, b, c = uv[..., 0, :], uv[..., 1, :], uv[..., 2, :]
    return 0.5 * ((b[..., 0] - a[..., 0]) * (c[..., 1] - a[..., 1]) - (c[..., 0] - a[..., 0]) * (b[..., 1] - a[..., 1]))


@dataclass
class Chart:
    """Faces of one mesh with their corner coordinates in metres, the chart's minimum at the origin."""

    faces: np.ndarray
    uv_m: np.ndarray
    size_m: np.ndarray = field(init=False)

    def __post_init__(self) -> None:
        self.faces = np.asarray(self.faces, dtype=np.int64).reshape(-1)
        self.uv_m = np.asarray(self.uv_m, dtype=np.float64).reshape(-1, 3, 2)
        if len(self.faces):
            self.uv_m = self.uv_m - self.uv_m.reshape(-1, 2).min(axis=0)
        self.size_m = self.uv_m.reshape(-1, 2).max(axis=0) if len(self.faces) else np.zeros(2)


def _face_adjacency(mesh: Mesh) -> list[list[int]]:
    """Faces sharing an edge (by vertex index, so a duplicated-vertex crease separates them)."""
    f = mesh.faces
    edges = np.stack([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]], axis=1).reshape(-1, 2)
    edges.sort(axis=1)
    keys = edges[:, 0] * (mesh.vertex_count + 1) + edges[:, 1]
    order = np.argsort(keys, kind="stable")
    sorted_keys = keys[order]
    faces_of_edge = order // 3
    neighbours: list[list[int]] = [[] for _ in range(mesh.face_count)]
    boundaries = np.flatnonzero(np.diff(sorted_keys)) + 1
    starts = np.concatenate([[0], boundaries])
    ends = np.concatenate([boundaries, [len(sorted_keys)]])
    for s, e in zip(starts, ends, strict=True):
        if e - s < 2:
            continue
        group = faces_of_edge[s:e]
        for a in group:
            for b in group:
                if a != b:
                    neighbours[int(a)].append(int(b))
    return neighbours


def auto_charts(mesh: Mesh, face_mask: np.ndarray, angle_deg: float = DEFAULT_ANGLE_DEG) -> list[Chart]:
    """Unwrap the faces in ``face_mask``: regions of faces within ``angle_deg`` of their seed, each projected onto its mean plane."""
    face_mask = np.asarray(face_mask, dtype=bool)
    normals = mesh.face_normals()
    areas = mesh.face_areas()
    corners = mesh.vertices[mesh.faces]
    neighbours = _face_adjacency(mesh)
    cos_limit = math.cos(math.radians(angle_deg))
    visited = ~face_mask
    charts: list[Chart] = []
    for seed in range(mesh.face_count):
        if visited[seed]:
            continue
        visited[seed] = True
        members = [seed]
        queue = deque([seed])
        seed_normal = normals[seed]
        while queue:
            current = queue.popleft()
            for other in neighbours[current]:
                if not visited[other] and float(normals[other] @ seed_normal) >= cos_limit:
                    visited[other] = True
                    members.append(other)
                    queue.append(other)
        faces = np.array(members, dtype=np.int64)
        mean_normal = unit((normals[faces] * areas[faces, None]).sum(axis=0))
        if np.linalg.norm(mean_normal) == 0.0:
            mean_normal = seed_normal
        e1, e2 = tangent_basis(mean_normal)
        p = corners[faces]
        charts.append(Chart(faces, np.stack([p @ e1, p @ e2], axis=-1)))
    return charts


def charts_of(mesh: Mesh, angle_deg: float = DEFAULT_ANGLE_DEG) -> list[Chart]:
    """Every chart of ``mesh``: the primitives' own first, then the unwrapper's for the faces without one."""
    charts: list[Chart] = []
    natural = mesh.face_chart >= 0
    if natural.any():
        for chart_id in np.unique(mesh.face_chart[natural]):
            faces = np.flatnonzero(mesh.face_chart == chart_id)
            charts.append(Chart(faces, mesh.face_uv[faces]))
    if (~natural).any():
        charts += auto_charts(mesh, ~natural, angle_deg)
    return [c for c in charts if len(c.faces)]


@dataclass
class Placement:
    chart: Chart
    origin_px: tuple[int, int]  # the chart's inner (gutter-free) corner
    rotated: bool


@dataclass
class Packed:
    """Where every chart landed: the texel size that fitted, the fill and the UVs in 0..1 per face corner."""

    atlas_px: int
    texel_m: float
    gutter_px: int
    placements: list[Placement]
    fill: float

    def _chart_uv_px(self, placement: Placement) -> np.ndarray:
        uv = placement.chart.uv_m / self.texel_m
        if placement.rotated:
            w = placement.chart.size_m[0] / self.texel_m
            uv = np.stack([uv[..., 1], w - uv[..., 0]], axis=-1)
        return uv + np.asarray(placement.origin_px, dtype=float)

    def face_uv01(self, face_count: int) -> np.ndarray:
        """Corner UVs in 0..1, ``(face_count, 3, 2)``; faces of no chart stay at 0."""
        out = np.zeros((face_count, 3, 2), dtype=np.float64)
        for placement in self.placements:
            out[placement.chart.faces] = self._chart_uv_px(placement) / float(self.atlas_px)
        return np.clip(out, 0.0, 1.0)

    def face_chart(self, face_count: int) -> np.ndarray:
        out = np.full(face_count, NO_CHART, dtype=np.int64)
        for k, placement in enumerate(self.placements):
            out[placement.chart.faces] = k
        return out


def _try_pack(charts: list[Chart], texel_m: float, atlas_px: int, gutter_px: int) -> Packed | None:
    sizes = []
    for chart in charts:
        w, h = (int(math.ceil(s / texel_m)) + 1 for s in chart.size_m)
        rotated = h > w
        if rotated:
            w, h = h, w
        sizes.append((w, h, rotated))
    order = sorted(range(len(charts)), key=lambda i: (-sizes[i][1], -sizes[i][0], i))
    placements: list[Placement | None] = [None] * len(charts)
    x = y = row_h = 0
    inner_area = 0
    for i in order:
        w, h, rotated = sizes[i]
        full_w, full_h = w + 2 * gutter_px, h + 2 * gutter_px
        if full_w > atlas_px or full_h > atlas_px:
            return None
        if x + full_w > atlas_px:
            x, y, row_h = 0, y + row_h, 0
        if y + full_h > atlas_px:
            return None
        placements[i] = Placement(charts[i], (x + gutter_px, y + gutter_px), rotated)
        x += full_w
        row_h = max(row_h, full_h)
        inner_area += w * h
    return Packed(atlas_px, texel_m, gutter_px, [p for p in placements if p is not None], inner_area / float(atlas_px * atlas_px))


def pack(charts: list[Chart], texel_m: float, atlas_px: int, gutter_px: int = 2) -> Packed:
    """Shelf-pack ``charts`` into one square atlas at ``texel_m`` a texel, or the smallest coarser texel that fits."""
    if texel_m <= 0.0 or atlas_px <= 0:
        raise ValueError("texel_m and atlas_px must be positive")
    size = texel_m
    for _ in range(MAX_ATTEMPTS):
        packed = _try_pack(charts, size, atlas_px, gutter_px)
        if packed is not None:
            return packed
        size *= GROW
    raise ValueError(f"could not pack {len(charts)} charts into {atlas_px} px")


__all__ = ["Chart", "Packed", "Placement", "auto_charts", "charts_of", "pack", "uv_area"]
