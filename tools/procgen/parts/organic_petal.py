"""Petals: the Vorlons' opening shells (M10-T06, D12.2; the measurements are M10-T01's, docs/design-references.md,
"Vorlon destroyer").

A petal is a thin leaf-shaped shell hinged at its narrow root. Closed, it is curled across its width and bowed along its
length, so several wrap a ship's head; open, it flattens and stands out from the axis. A :class:`PetalPose` is one such
state, and :func:`petal` builds the shell at any ``opening`` between a closed and an open pose. The mesh has the same
triangles at every opening, only its vertices move, so a hull task can write the two ends as poses of one mesh.

The petal's own frame: its root at the origin, its length towards -z (the bow), its outer face towards +y (away from the
ship's axis), its width along x. ``Module.mounted`` stands it on the hull.
"""

from __future__ import annotations

import dataclasses
import math
from dataclasses import dataclass

import numpy as np

from ..core import organic
from ..core.geometry import Material, Mesh, rotation_x
from . import capital as cp

EDGE_SHARE = 0.06  # of the length: over this much at the root and the tip the shell thins to its edge


@dataclass(frozen=True)
class PetalPose:
    """One state of a petal. ``length_m`` and ``width_m`` are measured along the shell's skin (its fullest width);
    ``curl_radius_m`` is the radius it is curled to across its width and ``bow_radius_m`` along its length (``inf``: flat
    that way); ``hinge_deg`` is how far it stands out from the ship's axis at its root."""

    length_m: float
    width_m: float
    curl_radius_m: float = math.inf
    bow_radius_m: float = math.inf
    hinge_deg: float = 0.0

    def towards(self, other: PetalPose, share: float) -> PetalPose:
        """The pose ``share`` of the way to ``other``; curls are mixed by their curvature, so flat is an end like any."""
        mix = lambda a, b: a + (b - a) * share  # noqa: E731
        bend = lambda a, b: 1.0 / max(mix(1.0 / a, 1.0 / b), 1e-12) if mix(1.0 / a, 1.0 / b) > 1e-12 else math.inf  # noqa: E731
        return PetalPose(mix(self.length_m, other.length_m), mix(self.width_m, other.width_m), bend(self.curl_radius_m, other.curl_radius_m),
                         bend(self.bow_radius_m, other.bow_radius_m), mix(self.hinge_deg, other.hinge_deg))

    @property
    def chord_m(self) -> float:
        """The straight width across the curled shell at its fullest."""
        r = self.curl_radius_m
        return self.width_m if math.isinf(r) else 2.0 * r * math.sin(min(0.5 * self.width_m / r, math.pi))

    @property
    def depth_m(self) -> float:
        """How deep the curl is at the shell's fullest width."""
        r = self.curl_radius_m
        return 0.0 if math.isinf(r) else r * (1.0 - math.cos(min(0.5 * self.width_m / r, math.pi)))


def _bend(arc: np.ndarray, radius: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """A length ``arc`` along a curve of ``radius``: how far it gets straight on, how far it falls inward, and its turn."""
    if math.isinf(radius):
        return arc, np.zeros_like(arc), np.zeros_like(arc)
    turn = arc / radius
    return radius * np.sin(turn), radius * (1.0 - np.cos(turn)), turn


def outline(v: np.ndarray, stub: float = 0.18, fullest: float = 0.55) -> np.ndarray:
    """A leaf's half width at ``v`` along it (0 the root, 1 the tip), as a share of its fullest: a narrow stub at the hinge,
    widest past the middle, drawn in to a point."""
    v = np.asarray(v, dtype=float)
    rise = stub + (1.0 - stub) * np.sin(0.5 * math.pi * np.clip(v / fullest, 0.0, 1.0)) ** 1.5
    fall = np.cos(0.5 * math.pi * np.clip((v - fullest) / (1.0 - fullest), 0.0, 1.0)) ** 0.7
    return np.where(v <= fullest, rise, fall)


def _grid_faces(rows: int, columns: int) -> np.ndarray:
    """Two triangles for every cell of a grid of ``rows`` by ``columns`` cells, its vertices numbered row by row."""
    i, j = (g.reshape(-1) for g in np.meshgrid(np.arange(rows), np.arange(columns), indexing="ij"))
    a = i * (columns + 1) + j
    b, c, d = a + 1, a + columns + 2, a + columns + 1
    return np.concatenate([np.stack([a, b, c], axis=1), np.stack([a, c, d], axis=1)])


def petal_mesh(pose: PetalPose, thickness_m: float, material: Material, across: int = 12, along: int = 24) -> Mesh:
    """The shell in ``pose``: an outer and an inner face that meet at the rim, the root and the tip, so it is closed. Each
    face is its own UV chart, laid flat (the skin's own lengths)."""
    u = np.linspace(-1.0, 1.0, across + 1)
    v = np.linspace(0.0, 1.0, along + 1)
    uu, vv = np.meshgrid(u, v, indexing="xy")  # rows along, columns across
    half = 0.5 * pose.width_m * outline(vv)
    a, s = uu * half, vv * pose.length_m
    # Along the length the centre line bows in towards the axis; across it each section curls in round the same side.
    forward, fall, pitch = _bend(s, pose.bow_radius_m)
    x, sag, roll = _bend(a, pose.curl_radius_m)
    centre = np.stack([np.zeros_like(s), -fall, -forward], axis=-1)
    normal = np.stack([np.zeros_like(s), np.cos(pitch), -np.sin(pitch)], axis=-1)  # the centre line's outward
    mid = centre + np.stack([x, np.zeros_like(x), np.zeros_like(x)], axis=-1) - sag[..., None] * normal
    out = np.cos(roll)[..., None] * normal + np.stack([np.sin(roll), np.zeros_like(roll), np.zeros_like(roll)], axis=-1)
    ends = np.clip(np.minimum(vv, 1.0 - vv) / EDGE_SHARE, 0.0, 1.0)
    thick = 0.5 * thickness_m * np.sqrt(np.clip(1.0 - uu * uu, 0.0, 1.0)) * np.sin(0.5 * math.pi * ends)
    tilt = rotation_x(math.radians(pose.hinge_deg))  # the hinge lifts the tip away from the axis
    count = (across + 1) * (along + 1)
    vertices = np.concatenate([(mid + thick[..., None] * out).reshape(-1, 3), (mid - thick[..., None] * out).reshape(-1, 3)]) @ tilt.T
    outer = _grid_faces(along, across)
    faces = np.concatenate([outer, count + outer[:, ::-1]])
    flat = np.stack([a, s], axis=-1).reshape(-1, 2)
    uv = np.concatenate([flat, flat * np.array([-1.0, 1.0])])[faces]
    chart = np.repeat([0, 1], len(faces) // 2)
    # The two faces share their rim, their root row and their tip: there the inner face's vertices are the outer face's. Named
    # by their place in the grid, not by where they are, so the triangles are the same in every pose.
    row, column = (g.reshape(-1) for g in np.meshgrid(np.arange(along + 1), np.arange(across + 1), indexing="ij"))
    own = np.arange(count)
    own[row == along] = along * (across + 1)  # the tip is one point
    edge = (column == 0) | (column == across) | (row == 0) | (row == along)
    weld = np.concatenate([own, np.where(edge, own, count + own)])
    faces = weld[faces]
    keep = (faces[:, 0] != faces[:, 1]) & (faces[:, 1] != faces[:, 2]) & (faces[:, 2] != faces[:, 0])
    # Where the shell has no thickness an outer triangle and its inner twin are the same three points: a flap, not skin.
    _, twin, uses = np.unique(np.sort(faces, axis=1), axis=0, return_inverse=True, return_counts=True)
    keep &= uses[twin.reshape(-1)] == 1
    used, compact = np.unique(faces[keep], return_inverse=True)
    return Mesh(vertices[used], compact.reshape(-1, 3), np.zeros(int(keep.sum()), dtype=np.int64), (material,), chart[keep], uv[keep])


def petal(name: str, closed: PetalPose, opened: PetalPose, opening: float, thickness_m: float, material: Material, across: int = 12,
          along: int = 24, pieces: int = 8, skin: str = cp.SKIN_NONE) -> cp.Module:
    """A petal ``opening`` of the way from ``closed`` (0) to ``opened`` (1) as a module, its collision ``pieces`` hulls
    fitted to the curled shell."""
    if not 0.0 <= opening <= 1.0:
        raise ValueError("a petal's opening is from 0 (closed) to 1 (open)")
    pose = closed.towards(opened, opening)
    mesh = petal_mesh(pose, thickness_m, material, across, along)
    # A hull may bridge a sixth of the curl's depth, and no less than the leaf's own outline wanders.
    tolerance = max(0.5 * thickness_m, 0.15 * pose.depth_m, 0.04 * pose.width_m)
    return organic.module(name, mesh, tolerance, max_pieces=pieces, skin=skin)


def ring_of(module: cp.Module, count: int, radius_m: float, z: float, phase_deg: float = 0.0) -> list[cp.Module]:
    """``count`` copies of a petal (built in its own frame) hinged evenly round the ship's axis at ``radius_m`` and station
    ``z``, each named ``<name>_<k>``."""
    out = []
    for k in range(count):
        angle = math.radians(phase_deg) + 2.0 * math.pi * k / count
        up = (math.sin(angle), math.cos(angle), 0.0)
        placed = module.mounted((radius_m * up[0], radius_m * up[1], z), up)
        out.append(dataclasses.replace(placed, part=placed.part.renamed(f"{module.name}_{k}"),
                                       shapes=tuple(s.renamed(f"{module.name}_{k}_{s.name.rsplit('_', 1)[-1]}") for s in placed.shapes)))
    return out


__all__ = ["PetalPose", "outline", "petal", "petal_mesh", "ring_of"]
