"""Capital ship parts, the base (M10-T05, D12.1; docs/assets-capital.md, "Capital framework").

A :class:`Module` is what every part of the capital library returns: a part (mesh, mass, drawn layout), the convex collision
shapes that stand for it and the hardpoints it carries, all in one frame. Placing, turning or mirroring a module moves the
three together, so a turret's mount, its collision and its mesh can never disagree. The generator names the damage section
each module belongs to (``in_section``); ``core/capital.py`` writes the hull from the modules.

The library, one file per family, all in the authored frame (x to starboard, y up, z aft; metres):

* ``capital_hull.py``: hull sections lofted through stations, prows, armour plating;
* ``capital_weapons.py``: turret mounts, beam emitters, interceptor domes, missile launchers, mine layers;
* ``capital_bays.py``: launch bays and launch tubes;
* ``capital_engines.py``: engine blocks;
* ``capital_fittings.py``: rotating sections, antennae, lights.

Organic parts (M10-T06) join the same way: any mesh, from a signed distance field or a sweep, wrapped by :func:`module` with
its shapes. A module's ``skin`` says which of the style's layouts dresses it (``styles/capital.py``); ``SKIN_NONE`` leaves a
part bare, as seamless organic hulls are.
"""

from __future__ import annotations

import dataclasses
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any

import numpy as np

from ..core import collision as col
from ..core.geometry import Mesh, mirror_matrix
from . import Part
from .solids import Solid

CENTRE, RIGHT = "c", "r"  # as ``core/civilian.py``: on the centre line, or starboard with a port twin
LONE = "a"  # as ``core/civilian.py``: a part one side has and the other has not (a single aerial), built as authored
AREAL_DENSITY_KG_M2 = 260.0  # the strike carrier's: a skin's mass by its area (informational; the ShipSpec rules)

TURRET, BEAM, INTERCEPTOR, MISSILE, MINE = "turret", "beam", "interceptor", "missile", "mine"
BAY, TUBE, ENGINE, LIGHT, MARK, DOOR = "bay", "tube", "engine", "light", "mark", "door"
WEAPON_KINDS = (TURRET, BEAM, INTERCEPTOR, MISSILE, MINE)
LAUNCH_KINDS = (BAY, TUBE)
HARDPOINT_KINDS = (*WEAPON_KINDS, *LAUNCH_KINDS, ENGINE, LIGHT, MARK, DOOR)

# Hardpoint parameters that are points in the module's frame: they move with it (a bay's mouth, its lift).
POINT_PARAMS = ("exit", "elevator")

SKIN_HULL, SKIN_FITTING, SKIN_NONE = "hull", "fitting", "none"
SKINS = (SKIN_HULL, SKIN_FITTING, SKIN_NONE)


def _unit(v: Sequence[float]) -> np.ndarray:
    out = np.asarray(v, dtype=float).reshape(3)
    norm = float(np.linalg.norm(out))
    if norm == 0.0:
        raise ValueError("a hardpoint's direction must not be zero")
    return out / norm


@dataclass(frozen=True)
class Hardpoint:
    """A named place on a module. ``forward`` is what the kind points with: a weapon's boresight at rest, the way a
    launched craft leaves a bay or a tube, the push an engine gives the ship, the way a light shines. ``up`` is the mount's
    normal (a launched craft's up). ``params`` are the kind's own numbers (``capital_weapons.py`` and the others say which)."""

    name: str
    kind: str
    position: np.ndarray
    forward: np.ndarray
    up: np.ndarray
    params: Mapping[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.kind not in HARDPOINT_KINDS:
            raise ValueError(f"hardpoint {self.name!r}: unknown kind {self.kind!r}")
        object.__setattr__(self, "position", np.asarray(self.position, dtype=float).reshape(3))
        object.__setattr__(self, "forward", _unit(self.forward))
        object.__setattr__(self, "up", _unit(self.up))

    def transformed(self, rotation: np.ndarray, translation: Sequence[float] = (0.0, 0.0, 0.0)) -> Hardpoint:
        r, t = np.asarray(rotation, dtype=float), np.asarray(translation, dtype=float)
        params = {k: tuple(float(c) for c in r @ np.asarray(v, dtype=float) + t) if k in POINT_PARAMS else v for k, v in self.params.items()}
        return dataclasses.replace(self, position=r @ self.position + t, forward=r @ self.forward, up=r @ self.up, params=params)

    def renamed(self, name: str) -> Hardpoint:
        return dataclasses.replace(self, name=name)


def left_name(name: str) -> str:
    """``turret_2_r`` -> ``turret_2_l``; a name without the suffix is a centre name and stays (modules and sections)."""
    return name[:-2] + "_l" if name.endswith("_r") else name


def port_name(name: str) -> str:
    """A starboard module's shape or hardpoint named for the port twin: the last ``r`` between underscores becomes ``l``
    (``engine_r_2`` -> ``engine_l_2``, ``turret_2_r_guns`` -> ``turret_2_l_guns``); a name without one stays."""
    tokens = name.split("_")
    for k in range(len(tokens) - 1, 0, -1):
        if tokens[k] == "r":
            tokens[k] = "l"
            break
    return "_".join(tokens)


@dataclass(frozen=True)
class Module:
    """One part of a capital hull with its collision and hardpoints. ``solid`` is the volume it buries (other modules'
    surface inside it does not count as skin), ``side`` :data:`CENTRE`, :data:`RIGHT` (a port twin follows) or :data:`LONE`, ``fine``
    scales its surface sampling, ``section`` the damage section it belongs to and ``skin`` the layout that dresses it."""

    part: Part
    shapes: tuple[col.Shape, ...]
    hardpoints: tuple[Hardpoint, ...] = ()
    solid: Solid | None = None
    side: str = CENTRE
    fine: float = 1.0
    section: str = ""
    skin: str = SKIN_HULL

    def __post_init__(self) -> None:
        if self.side not in (CENTRE, RIGHT, LONE):
            raise ValueError(f"module {self.name!r}: side must be {CENTRE!r}, {RIGHT!r} or {LONE!r}")
        if self.skin not in SKINS:
            raise ValueError(f"module {self.name!r}: unknown skin {self.skin!r}")
        if not self.shapes:
            raise ValueError(f"module {self.name!r} has no collision shape")

    @property
    def name(self) -> str:
        return self.part.name

    def transformed(self, rotation: np.ndarray, translation: Sequence[float] = (0.0, 0.0, 0.0)) -> Module:
        return dataclasses.replace(
            self,
            part=self.part.transformed(rotation, translation),
            shapes=tuple(s.transformed(rotation, translation) for s in self.shapes),
            hardpoints=tuple(h.transformed(rotation, translation) for h in self.hardpoints),
            solid=None if self.solid is None else self.solid.transformed(rotation, translation),
        )

    def translated(self, offset: Sequence[float]) -> Module:
        return self.transformed(np.eye(3), offset)

    def in_section(self, section: str) -> Module:
        return dataclasses.replace(self, section=section)

    def on_side(self, side: str) -> Module:
        return dataclasses.replace(self, side=side)

    def with_params(self, only: str | None = None, **params: Any) -> Module:
        """The module with ``params`` added to every hardpoint it carries (or only to those of kind ``only``): the weapon that
        stands on a mount (``weapon``), the craft a bay launches and how many it holds (``craft``, ``capacity``)."""
        return dataclasses.replace(self, hardpoints=tuple(dataclasses.replace(h, params={**h.params, **params}) if only in (None, h.kind) else h
                                                          for h in self.hardpoints))

    def mounted(self, position: Sequence[float], up: Sequence[float] = (0.0, 1.0, 0.0),
                forward: Sequence[float] = (0.0, 0.0, -1.0)) -> Module:
        """A module built on a mount (+y its normal, -z its front, the origin on the hull) stood at ``position``."""
        return self.transformed(mount_basis(up, forward), position)

    def twin(self) -> Module:
        """The port twin of a starboard module: mirrored in x, its own and its section's ``_r`` ending turned to ``_l``,
        and the ``r`` in its shapes' and hardpoints' names (:func:`port_name`)."""
        flip = mirror_matrix("x")
        return dataclasses.replace(
            self,
            part=self.part.mirrored("x").renamed(left_name(self.name)),
            shapes=tuple(s.mirrored("x").renamed(port_name(s.name)) for s in self.shapes),
            hardpoints=tuple(h.transformed(flip).renamed(port_name(h.name)) for h in self.hardpoints),
            solid=None if self.solid is None else self.solid.mirrored("x"),
            section=left_name(self.section),
        )


def module(name: str, mesh: Mesh, shapes: Sequence[col.Shape], hardpoints: Sequence[Hardpoint] = (), solid: Solid | None = None,
           skin: str = SKIN_HULL, fine: float = 1.0) -> Module:
    """A mesh as a module: its mass from its skin's area, its shapes and hardpoints as given. The way in for any mesh the
    library does not make (an organic body from M10-T06's fields)."""
    part = Part(name, mesh, {}, [], round(mesh.area() * AREAL_DENSITY_KG_M2, 1), "")
    return Module(part, tuple(shapes), tuple(hardpoints), solid, CENTRE, fine, "", skin)


def with_twins(modules: Sequence[Module]) -> list[Module]:
    """The modules plus each starboard module's port twin, twin after original."""
    out: list[Module] = []
    for m in modules:
        out.append(m)
        if m.side == RIGHT:
            out.append(m.twin())
    return out


def mount_basis(up: Sequence[float], forward: Sequence[float]) -> np.ndarray:
    """The turn that stands a part built with +y up and -z forward on a mount: columns are the mount's right, ``up`` and
    back (``forward`` squared up against ``up``)."""
    y = _unit(up)
    f = np.asarray(forward, dtype=float).reshape(3)
    f = f - (f @ y) * y
    if float(np.linalg.norm(f)) < 1e-9:
        raise ValueError("a mount's forward must not lie along its up")
    z = -_unit(f)
    return np.stack([np.cross(y, z), y, z], axis=1)


__all__ = ["AREAL_DENSITY_KG_M2", "BAY", "BEAM", "CENTRE", "ENGINE", "HARDPOINT_KINDS", "INTERCEPTOR", "LAUNCH_KINDS", "LIGHT", "LONE", "MARK", "MINE",
           "MISSILE", "POINT_PARAMS", "RIGHT", "SKINS", "SKIN_FITTING", "SKIN_HULL", "SKIN_NONE", "TUBE", "TURRET", "WEAPON_KINDS", "Hardpoint", "Module",
           "left_name", "module", "mount_basis", "port_name", "with_twins"]
