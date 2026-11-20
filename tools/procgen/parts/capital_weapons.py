"""Capital weapon mounts (M10-T05, D12.1): one module per weapon kind, each with its hardpoint.

Every mount is built on its own frame: the origin on the hull's skin, +y the mount's normal, -z its front. Stand it on the
hull with ``Module.mounted(position, up, forward)``. The hardpoint's ``position`` is where the weapon turns or fires from,
``forward`` its boresight at rest and ``up`` the mount's normal. Its ``params`` (written into ``hardpoints.weapons[]``):

* turret: ``traverse_deg`` (half the arc it turns through, 180 all round), ``elevation_deg`` (lowest, highest),
  ``barrel_m``, ``barrels``;
* beam: ``arc_deg`` (the cone it can steer its beam in, half angle), ``aperture_m``;
* interceptor: ``traverse_deg``, ``elevation_deg``, ``radius_m`` (the dome's);
* missile: ``cells`` (across, along), ``cell_m``;
* mine: ``mouth_m`` (width, height).

Which weapon stands on a mount, and its numbers in a fight, are the hull task's and M10-T03's.
"""

from __future__ import annotations

import math

import numpy as np

from ..core import collision as col
from ..core.geometry import Mesh, box, lathe, rotation_x, tapered_box
from ..styles import Style
from .capital import BEAM, INTERCEPTOR, MINE, MISSILE, SKIN_FITTING, TURRET, Hardpoint, Module, module

UP = (0.0, 1.0, 0.0)
FORWARD = (0.0, 0.0, -1.0)
ROUND = 12  # sides of a mount's round parts


def _upright(mesh: Mesh, y0: float = 0.0) -> Mesh:
    """A lathe (about z) stood on the mount: its axis along +y, its first ring at ``y0``."""
    return mesh.transformed(rotation_x(-0.5 * math.pi), (0.0, y0, 0.0))


def _barrel(length: float, radius: float, style: Style, at: tuple[float, float, float]) -> Mesh:
    """A gun barrel along -z from ``at``, its bore dark."""
    profile = [(0.0, 1.25 * radius), (0.3 * length, 1.25 * radius), (0.3 * length, radius), (length, radius), (length, 0.5 * radius),
               (length - radius, 0.0)]
    bar, bore = style.material("barrel"), style.material("bore")
    return lathe(profile, 8, [bar, bar, bar, bar, bore], creases={1, 2, 3, 4}).transformed(rotation_x(math.pi), at)


def turret_mount(name: str, size_m: float, style: Style, barrels: int = 2, traverse_deg: float = 180.0,
                 elevation_deg: tuple[float, float] = (-5.0, 85.0)) -> Module:
    """A gun turret: a barbette, a gun house ``size_m`` wide and ``barrels`` guns."""
    if size_m <= 0.0 or barrels < 1:
        raise ValueError(f"turret {name!r} needs a size and a barrel")
    s = size_m
    base_h, house_h, barrel_m, bore_r = 0.22 * s, 0.42 * s, 1.5 * s, 0.07 * s
    dark, hull = style.material("hull_dark"), style.material("hull")
    barbette = _upright(lathe([(0.0, 0.62 * s), (base_h, 0.55 * s), (base_h, 0.0)], ROUND, dark, creases={1}))
    house = tapered_box(1.1 * s, (s, house_h), (0.8 * s, 0.8 * house_h), hull, center=(0.0, base_h + 0.5 * house_h, 0.1 * s))
    trunnion = np.array([0.0, base_h + 0.5 * house_h, -0.45 * s])
    spread = 0.5 * s / barrels
    guns = [_barrel(barrel_m, bore_r, style, (float((k - 0.5 * (barrels - 1)) * 2.0 * spread), float(trunnion[1]), float(trunnion[2])))
            for k in range(barrels)]
    shapes = [col.hull(name, np.concatenate([barbette.vertices, house.vertices])),
              col.box(f"{name}_guns", trunnion + (0.0, 0.0, -0.5 * barrel_m), (2.0 * spread * (barrels - 1) + 2.5 * bore_r, 2.5 * bore_r, barrel_m))]
    point = Hardpoint(name, TURRET, trunnion, FORWARD, UP, {"traverse_deg": traverse_deg, "elevation_deg": list(elevation_deg),
                                                           "barrel_m": round(barrel_m, 3), "barrels": barrels})
    return module(name, Mesh.concatenate([barbette, house, *guns]), shapes, [point], skin=SKIN_FITTING)


def beam_emitter(name: str, length_m: float, style: Style, arc_deg: float = 30.0) -> Module:
    """A beam weapon's housing: a long tapering block lying along the hull, its lens glowing at the front."""
    if length_m <= 0.0:
        raise ValueError(f"beam emitter {name!r} needs a length")
    w, h = 0.22 * length_m, 0.16 * length_m
    lens_r = 0.3 * h
    housing = tapered_box(length_m, (0.6 * w, 0.7 * h), (w, h), style.material("hull_dark"), center=(0.0, 0.5 * h, 0.0))
    front = np.array([0.0, 0.5 * h, -0.5 * length_m])
    lens = lathe([(0.0, 0.0), (0.0, lens_r), (0.4 * lens_r, 1.15 * lens_r), (0.4 * lens_r, 0.0)], ROUND,
                 [style.material("nozzle_throat"), style.material("barrel"), style.material("barrel")],
                 creases={1, 2}).transformed(rotation_x(math.pi), front + (0.0, 0.0, 0.4 * lens_r))
    shapes = [col.box(name, (0.0, 0.5 * h, -0.2 * lens_r), (w, h, length_m + 0.4 * lens_r))]
    point = Hardpoint(name, BEAM, front + (0.0, 0.0, -0.4 * lens_r), FORWARD, UP, {"arc_deg": arc_deg, "aperture_m": round(2.0 * lens_r, 3)})
    return module(name, Mesh.concatenate([housing, lens]), shapes, [point], skin=SKIN_FITTING)


def interceptor_dome(name: str, radius_m: float, style: Style, elevation_deg: tuple[float, float] = (0.0, 90.0)) -> Module:
    """An interceptor: a dome on a collar with a short twin gun, covering the half sphere over its mount."""
    if radius_m <= 0.0:
        raise ValueError(f"interceptor {name!r} needs a radius")
    r = radius_m
    collar_h = 0.3 * r
    arc = [(collar_h + r * math.sin(a), r * math.cos(a)) for a in np.linspace(0.0, 0.5 * math.pi, 5)[:-1]] + [(collar_h + r, 0.0)]
    dome = _upright(lathe([(0.0, 1.15 * r), (collar_h, 1.15 * r), *arc], ROUND, [style.material("hull_dark"), style.material("hull_dark"),
                                                                              *([style.material("hull")] * 4)], creases={1, 2}))
    pivot = np.array([0.0, collar_h + 0.45 * r, 0.0])
    guns = [_barrel(1.6 * r, 0.09 * r, style, (x, float(pivot[1]), -0.7 * r)) for x in (-0.3 * r, 0.3 * r)]
    shapes = [col.hull(name, col.prism_points((0.0, 0.0, 0.0), UP, [(0.0, 1.15 * r), (collar_h + 0.55 * r, 1.0 * r), (collar_h + r, 0.45 * r)], ROUND)),
              col.box(f"{name}_guns", pivot + (0.0, 0.0, -1.5 * r), (0.85 * r, 0.25 * r, 1.6 * r))]
    point = Hardpoint(name, INTERCEPTOR, pivot, FORWARD, UP, {"traverse_deg": 180.0, "elevation_deg": list(elevation_deg),
                                                             "radius_m": round(r, 3)})
    return module(name, Mesh.concatenate([dome, *guns]), shapes, [point], skin=SKIN_FITTING)


def missile_launcher(name: str, cells: tuple[int, int], cell_m: float, style: Style) -> Module:
    """A missile battery: a low block with ``cells`` (across, along) launch cells in its top, each a dark mouth. Missiles
    leave along the mount's normal."""
    cols, rows = cells
    if cols < 1 or rows < 1 or cell_m <= 0.0:
        raise ValueError(f"missile launcher {name!r} needs cells")
    pitch, h = 1.35 * cell_m, 0.8 * cell_m
    size = (cols * pitch + 0.35 * cell_m, h, rows * pitch + 0.35 * cell_m)
    block = tapered_box(size[2], (size[0], h), (size[0], h), style.material("hull_dark"), center=(0.0, 0.5 * h, 0.0))
    lid, bore = style.material("hazard_dark"), style.material("bore")
    mouths = [tapered_box(0.06 * cell_m, (cell_m, cell_m), (0.8 * cell_m, 0.8 * cell_m), lid, materials_by_face={"back": bore})
              .transformed(rotation_x(-0.5 * math.pi), ((i - 0.5 * (cols - 1)) * pitch, h + 0.03 * cell_m, (j - 0.5 * (rows - 1)) * pitch))
              for i in range(cols) for j in range(rows)]
    shapes = [col.box(name, (0.0, 0.5 * h + 0.03 * cell_m, 0.0), (size[0], h + 0.06 * cell_m, size[2]))]
    point = Hardpoint(name, MISSILE, (0.0, h + 0.06 * cell_m, 0.0), UP, FORWARD, {"cells": [cols, rows], "cell_m": round(cell_m, 3)})
    return module(name, Mesh.concatenate([block, *mouths]), shapes, [point], skin=SKIN_FITTING)


def mine_layer(name: str, mouth_m: tuple[float, float], depth_m: float, style: Style) -> Module:
    """A mine layer: a chute housing whose dark mouth faces the mount's back (+z); mines leave that way."""
    w, h = mouth_m
    if w <= 0.0 or h <= 0.0 or depth_m <= 0.0:
        raise ValueError(f"mine layer {name!r} needs a mouth and a depth")
    wall = 0.15 * min(w, h)
    housing = tapered_box(depth_m, (w + 2.0 * wall, h + 2.0 * wall), (w + 2.0 * wall, h + 2.0 * wall), style.material("hull_dark"),
                          center=(0.0, 0.5 * h + wall, 0.0))
    mouth_z = 0.5 * depth_m
    mouth = box((w, h, 0.05 * depth_m), style.material("bore"), (0.0, 0.5 * h + wall, mouth_z + 0.02 * depth_m))
    shapes = [col.box(name, (0.0, 0.5 * h + wall, 0.02 * depth_m), (w + 2.0 * wall, h + 2.0 * wall, 1.05 * depth_m))]
    point = Hardpoint(name, MINE, (0.0, 0.5 * h + wall, mouth_z + 0.05 * depth_m), (0.0, 0.0, 1.0), UP, {"mouth_m": [round(w, 3), round(h, 3)]})
    return module(name, Mesh.concatenate([housing, mouth]), shapes, [point], skin=SKIN_FITTING)


__all__ = ["beam_emitter", "interceptor_dome", "mine_layer", "missile_launcher", "turret_mount"]
