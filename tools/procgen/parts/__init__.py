"""Reusable parametric parts (docs/architecture.md sections 9.1 and 14.8).

A part function takes a spec (plain dataclass of dimensions) and a :class:`Style` and returns
a :class:`Part`: tessellated geometry, named :class:`Anchor` points (with an optional
direction, e.g. a nozzle's exhaust), collision primitives and a mass. Parts are built in their
own local frame; the asset module places them with ``transformed`` / ``mirrored`` and only then
reads the anchors, so hardpoints, meshes and splats can never disagree.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any

import numpy as np

from ..core.geometry import Mesh, mirror_matrix


def _vec(v: Sequence[float]) -> np.ndarray:
    out = np.asarray(v, dtype=np.float64).reshape(3)
    if not np.all(np.isfinite(out)):
        raise ValueError("non-finite vector")
    return out


@dataclass(frozen=True)
class Anchor:
    """A named point on a part, optionally with a unit direction (exhaust, muzzle, look)."""

    position: np.ndarray
    direction: np.ndarray | None = None

    def __post_init__(self) -> None:
        object.__setattr__(self, "position", _vec(self.position))
        if self.direction is not None:
            d = _vec(self.direction)
            norm = np.linalg.norm(d)
            if norm == 0.0:
                raise ValueError("anchor direction must not be zero")
            object.__setattr__(self, "direction", d / norm)

    def transformed(self, rotation: np.ndarray, translation: Sequence[float] = (0.0, 0.0, 0.0)) -> Anchor:
        r = np.asarray(rotation, dtype=float)
        pos = r @ self.position + _vec(translation)
        direction = None if self.direction is None else r @ self.direction
        return Anchor(pos, direction)


@dataclass(frozen=True)
class Collision:
    """A collision primitive: ``box`` (``size`` = full extents along the local axes) or
    ``capsule`` (``radius``, ``height`` = total length along the local Z axis). ``basis``
    columns are the local axes in the part frame (a proper rotation)."""

    kind: str
    center: np.ndarray
    basis: np.ndarray = field(default_factory=lambda: np.eye(3))
    size: np.ndarray | None = None
    radius: float | None = None
    height: float | None = None
    name: str = ""

    def __post_init__(self) -> None:
        if self.kind not in ("box", "capsule"):
            raise ValueError(f"unknown collision kind {self.kind!r}")
        object.__setattr__(self, "center", _vec(self.center))
        object.__setattr__(self, "basis", np.asarray(self.basis, dtype=float).reshape(3, 3))
        if self.kind == "box":
            if self.size is None:
                raise ValueError("a box needs a size")
            object.__setattr__(self, "size", _vec(self.size))
        elif self.radius is None or self.height is None:
            raise ValueError("a capsule needs radius and height")

    def transformed(self, rotation: np.ndarray, translation: Sequence[float] = (0.0, 0.0, 0.0)) -> Collision:
        r = np.asarray(rotation, dtype=float)
        basis = r @ self.basis
        if np.linalg.det(basis) < 0.0:
            # A mirror makes the basis improper; boxes and capsules are symmetric under
            # negating one local axis, so flip local X to get a rotation again.
            basis = basis @ np.diag([-1.0, 1.0, 1.0])
        return Collision(
            self.kind, r @ self.center + _vec(translation), basis, self.size, self.radius, self.height, self.name
        )

    def to_json(self, offset: Sequence[float] = (0.0, 0.0, 0.0), digits: int = 5) -> dict[str, Any]:
        """JSON-ready dict in the hardpoints schema (``position`` = center - offset)."""

        def r3(v: np.ndarray) -> list[float]:
            return [round(float(x), digits) + 0.0 for x in v]

        out: dict[str, Any] = {"name": self.name, "type": self.kind, "position": r3(self.center - _vec(offset))}
        if self.kind == "box":
            out["size"] = r3(self.size)
        else:
            out["radius"] = round(float(self.radius), digits)
            out["height"] = round(float(self.height), digits)
            out["axis"] = "z"
        out["basis"] = {"x": r3(self.basis[:, 0]), "y": r3(self.basis[:, 1]), "z": r3(self.basis[:, 2])}
        return out


@dataclass
class Part:
    """Geometry plus the named points other systems need, in one frame."""

    name: str
    mesh: Mesh
    anchors: dict[str, Anchor] = field(default_factory=dict)
    collision: list[Collision] = field(default_factory=list)
    mass_kg: float = 0.0
    group: str = ""  # symmetry group used by the asset when it mirrors samples

    def anchor(self, name: str) -> Anchor:
        try:
            return self.anchors[name]
        except KeyError as exc:
            raise KeyError(f"part {self.name!r} has no anchor {name!r}; has {sorted(self.anchors)}") from exc

    def transformed(self, rotation: np.ndarray, translation: Sequence[float] = (0.0, 0.0, 0.0)) -> Part:
        return Part(
            self.name,
            self.mesh.transformed(rotation, translation),
            {k: a.transformed(rotation, translation) for k, a in self.anchors.items()},
            [c.transformed(rotation, translation) for c in self.collision],
            self.mass_kg,
            self.group,
        )

    def translated(self, offset: Sequence[float]) -> Part:
        return self.transformed(np.eye(3), offset)

    def mirrored(self, axis: str) -> Part:
        return self.transformed(mirror_matrix(axis))

    def renamed(self, name: str, group: str | None = None) -> Part:
        return Part(name, self.mesh, dict(self.anchors), list(self.collision), self.mass_kg, self.group if group is None else group)

    def with_anchors(self, extra: Mapping[str, Anchor]) -> Part:
        return Part(self.name, self.mesh, {**self.anchors, **extra}, list(self.collision), self.mass_kg, self.group)

    def area_centroid(self) -> np.ndarray:
        return self.mesh.area_centroid()


def merge_meshes(parts: Iterable[Part]) -> Mesh:
    return Mesh.concatenate(p.mesh for p in parts)


def total_mass(parts: Iterable[Part]) -> float:
    return float(sum(p.mass_kg for p in parts))


def mass_centroid(parts: Iterable[Part]) -> np.ndarray:
    """Mass-weighted mean of the parts' surface centroids (a shell approximation of the CoM)."""
    parts = list(parts)
    mass = total_mass(parts)
    if mass <= 0.0:
        raise ValueError("parts have no mass")
    return sum(p.mass_kg * p.area_centroid() for p in parts) / mass
