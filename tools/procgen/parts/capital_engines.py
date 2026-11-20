"""Engine blocks (M10-T05, D12.1): a housing with a grid of nozzle bells, one engine hardpoint a bell.

Built on its own frame: the housing's bow face at z = 0, the bells at its stern (+z), centred on x and y. An engine
hardpoint's ``position`` is the bell's mouth, ``forward`` the push it gives the ship (-z here; its exhaust leaves the other
way), ``params`` its ``share`` of the ship's thrust and its ``radius_m``. The shares of every engine of a hull add up to one
(``core/capital.py`` checks it), so an engine section lost takes its share with it (D12.5).
"""

from __future__ import annotations

import numpy as np

from ..core import collision as col
from ..core.geometry import Mesh, lathe, tapered_box
from ..styles import Style
from .capital import ENGINE, SKIN_FITTING, Hardpoint, Module, module
from .solids import box_solid

BELL_SIDES = 12


def _bell(radius: float, length: float, style: Style) -> Mesh:
    """A nozzle bell from its throat at z = 0 to its mouth at ``length``, the inside glowing."""
    metal, glow = style.material("nozzle"), style.material("nozzle_throat")
    profile = [(0.0, 0.45 * radius), (0.5 * length, 0.8 * radius), (length, radius), (length, 0.9 * radius), (0.15 * length, 0.4 * radius),
               (0.15 * length, 0.0)]
    return lathe(profile, BELL_SIDES, [metal, metal, metal, glow, glow], creases={2, 3, 4})


def engine_block(name: str, size_m: tuple[float, float, float], nozzles: tuple[int, int], style: Style, share: float = 1.0,
                 taper: float = 0.8) -> Module:
    """An engine block ``size_m`` (width, height, length) with ``nozzles`` (across, up) bells, together giving ``share`` of
    the ship's thrust. The housing narrows to ``taper`` at its stern."""
    w, h, length = size_m
    cols, rows = nozzles
    if min(w, h, length) <= 0.0 or cols < 1 or rows < 1 or not 0.0 < share <= 1.0:
        raise ValueError(f"engine block {name!r} needs a size, nozzles and a share in (0, 1]")
    housing = tapered_box(length, (w, h), (taper * w, taper * h), style.material("hull_dark"), center=(0.0, 0.0, 0.5 * length))
    pitch_x, pitch_y = taper * w / cols, taper * h / rows
    radius = 0.42 * min(pitch_x, pitch_y)
    bell_m = 1.6 * radius
    meshes, shapes, points = [housing], [col.hull(name, tapered_box(length, (w, h), (taper * w, taper * h), style.material("hull_dark"),
                                                                    center=(0.0, 0.0, 0.5 * length)).vertices)], []
    count = cols * rows
    for i in range(cols):
        for j in range(rows):
            x, y = (i - 0.5 * (cols - 1)) * pitch_x, (j - 0.5 * (rows - 1)) * pitch_y
            tag = f"{name}_{i * rows + j + 1}" if count > 1 else name
            meshes.append(_bell(radius, bell_m, style).translated((x, y, length - 0.1 * bell_m)))
            mouth = np.array([x, y, length + 0.9 * bell_m])
            shapes.append(col.hull(f"{tag}_bell", col.prism_points((x, y, length), (0.0, 0.0, 1.0), [(0.0, 0.5 * radius), (0.9 * bell_m, radius)],
                                                                  BELL_SIDES)))
            points.append(Hardpoint(tag, ENGINE, mouth, (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), {"share": share / count, "radius_m": round(radius, 3)}))
    return module(name, Mesh.concatenate(meshes), shapes, points, solid=box_solid((taper * w, taper * h, length), (0.0, 0.0, 0.5 * length)),
                  skin=SKIN_FITTING)


__all__ = ["engine_block"]
