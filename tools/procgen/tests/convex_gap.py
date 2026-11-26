"""How far apart two bodies made of convex pieces are, for the clearance sweeps that are not along one axis (M10-T53: the
Asimov's shuttle bay, whose lanes fan through its mouth).

The gap is the largest separation found on the pieces' face normals and the cross products of their edges (the separating
axis test). It is never more than the true distance, so a sweep that passes on it is clear by at least that much; where the
nearest features are two corners it reads low, which keeps the check on the safe side.
"""

from __future__ import annotations

import itertools
import json
import math
from collections.abc import Sequence
from pathlib import Path

import numpy as np

from tools.procgen.core import collision as col

MAX_EDGE_AXES = 8  # edge directions kept a piece: boxes have three, a sector of a ring a few more
SIGNS = np.array(list(itertools.product((-1.0, 1.0), repeat=3)))


def _padded(rows: Sequence[np.ndarray], fill: np.ndarray | None = None) -> np.ndarray:
    """The rows as one array, short ones filled with their first entry (or ``fill``): a repeat changes no minimum."""
    size = max(len(r) for r in rows)
    return np.array([np.concatenate([r, np.repeat(r[:1] if fill is None else fill, size - len(r), axis=0)]) for r in rows])


class Body:
    """Convex pieces: their corners, their faces' outward planes and their edges' directions."""

    def __init__(self, names: Sequence[str], point_sets: Sequence[np.ndarray]) -> None:
        self.names = list(names)
        hulls = [col.convex_points(np.asarray(p, dtype=float))[0] for p in point_sets]
        faces = [col.hull_faces(h) for h in hulls]
        self.corners = _padded(hulls)
        self.normals = _padded([f.normals for f in faces])
        self.offsets = _padded([f.offsets for f in faces])
        edges = []
        for h, f in zip(hulls, faces, strict=True):
            e = h[f.edges[:, 1]] - h[f.edges[:, 0]]
            e /= np.linalg.norm(e, axis=1)[:, None]
            e *= np.sign(e[np.arange(len(e)), np.argmax(np.abs(e), axis=1)])[:, None]
            edges.append(np.unique(np.round(e, 4), axis=0)[:MAX_EDGE_AXES])
        self.edges = _padded(edges, np.zeros((1, 3)))

    def moved(self, rotation: np.ndarray, origin: Sequence[float]) -> Body:
        """The body turned by ``rotation`` (columns its axes) and set down at ``origin``."""
        out = object.__new__(Body)
        out.names = self.names
        out.corners = self.corners @ rotation.T + np.asarray(origin, dtype=float)
        out.normals = self.normals @ rotation.T
        out.offsets = self.offsets + out.normals @ np.asarray(origin, dtype=float)
        out.edges = self.edges @ rotation.T
        return out

    def near(self, lo: np.ndarray, hi: np.ndarray) -> Body:
        """The pieces that reach into the box ``lo`` to ``hi``."""
        keep = np.flatnonzero(np.all(self.corners.max(axis=1) >= lo, axis=1) & np.all(self.corners.min(axis=1) <= hi, axis=1))
        out = object.__new__(Body)
        out.names = [self.names[k] for k in keep]
        out.corners, out.normals, out.offsets, out.edges = self.corners[keep], self.normals[keep], self.offsets[keep], self.edges[keep]
        return out

    def bounds(self) -> tuple[np.ndarray, np.ndarray]:
        return self.corners.min(axis=(0, 1)), self.corners.max(axis=(0, 1))


def gap(a: Body, b: Body) -> tuple[float, str]:
    """The least gap (m) between any piece of ``a`` and any of ``b`` (negative: no axis tried parts them) and which two."""
    if not a.names or not b.names:
        return math.inf, ""
    on_a = (np.einsum("pfk,qvk->pqfv", a.normals, b.corners) - a.offsets[:, None, :, None]).min(axis=3).max(axis=2)
    on_b = (np.einsum("qfk,pvk->pqfv", b.normals, a.corners) - b.offsets[None, :, :, None]).min(axis=3).max(axis=2)
    axes = np.cross(a.edges[:, None, :, None, :], b.edges[None, :, None, :, :])
    length = np.linalg.norm(axes, axis=-1)
    real = length > 1e-6
    axes = axes / np.where(real, length, 1.0)[..., None]
    along_a = np.einsum("pqxyk,pvk->pqxyv", axes, a.corners)
    along_b = np.einsum("pqxyk,qvk->pqxyv", axes, b.corners)
    apart = np.maximum(along_b.min(axis=-1) - along_a.max(axis=-1), along_a.min(axis=-1) - along_b.max(axis=-1))
    found = np.maximum(np.maximum(on_a, on_b), np.where(real, apart, -np.inf).max(axis=(2, 3)))
    i, j = np.unravel_index(int(np.argmin(found)), found.shape)
    return float(found[i, j]), f"{a.names[i]} / {b.names[j]}"


def shape_points(shape: dict) -> np.ndarray:
    """Points whose convex hull holds a collision shape of a ``hardpoints.json`` or a manifest: a hull's own, a box's corners,
    and for a capsule the corners of a cube round each end's sphere (a little outside it)."""
    if shape["type"] == "hull":
        return np.array(shape["points"])
    basis = np.array([shape["basis"]["x"], shape["basis"]["y"], shape["basis"]["z"]]).T
    centre = np.array(shape["position"])
    if shape["type"] == "box":
        return centre + (SIGNS * (np.array(shape["size"]) / 2.0)) @ basis.T
    if shape["type"] == "capsule":
        along = basis[:, "xyz".index(shape["axis"])] * (shape["height"] / 2.0 - shape["radius"])
        return np.concatenate([centre + end + SIGNS * shape["radius"] for end in (along, -along)])
    raise AssertionError(f"{shape['name']}: {shape['type']} is not handled")


def craft_body(hardpoints: Path, fold_joint: tuple[float, float] | None = None) -> Body:
    """A small craft's collision as a body in its own frame. ``fold_joint`` (x, y of the starboard wing's root) turns its wings
    up a quarter turn about their roots, as a Kestrel flies into a bay (Q73)."""
    names, sets = [], []
    for shape in json.loads(hardpoints.read_text(encoding="utf-8"))["collision"]:
        pts = shape_points(shape)
        if fold_joint is not None and shape["name"].startswith("wing_"):
            side = 1.0 if shape["name"].startswith("wing_r") else -1.0
            joint = np.array([side * fold_joint[0], fold_joint[1]])
            rel = pts[:, :2] - joint
            pts = np.column_stack([joint[0] - side * rel[:, 1], joint[1] + side * rel[:, 0], pts[:, 2]])
        names.append(shape["name"])
        sets.append(pts)
    return Body(names, sets)


def nose_along(out: Sequence[float], up: Sequence[float] = (0.0, 1.0, 0.0)) -> np.ndarray:
    """A craft's axes (columns: right, up, back) with its nose along ``out``."""
    back = -np.asarray(out, dtype=float) / np.linalg.norm(out)
    right = np.cross(up, back)
    right /= np.linalg.norm(right)
    return np.column_stack([right, np.cross(back, right), back])


def rolled(axes: np.ndarray, roll_deg: float) -> np.ndarray:
    r = math.radians(roll_deg)
    return axes @ np.array([[math.cos(r), -math.sin(r), 0.0], [math.sin(r), math.cos(r), 0.0], [0.0, 0.0, 1.0]])


__all__ = ["Body", "craft_body", "gap", "nose_along", "rolled", "shape_points"]
