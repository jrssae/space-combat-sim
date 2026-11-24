"""Keeps a capital hull's parts from sharing faces (M10-T67): where a fitting sits flush on a plate, or two blocks end in one
plane, the two faces lie in one plane facing the same way and the renderer cannot tell which is in front, so they flicker.
The part with less face in that plane is set back a little behind it (``core/coplanar.py``), the bigger face stays put."""

from __future__ import annotations

import dataclasses
from collections.abc import Sequence

import numpy as np

from ..core import coplanar
from . import capital as cp

MIRROR = np.array([-1.0, 1.0, 1.0])

ROUNDS = 8  # a fitting set back onto a plate that was itself set back meets it again; a few rounds settle a stack


def set_back_flush_parts(modules: Sequence[cp.Module]) -> list[cp.Module]:
    """``modules`` with every part that sits flush on another's face set back from it (port twins' found planes carried to
    their starboard original, which the twin mirrors)."""
    out = list(modules)
    among: set[str] | None = None
    for _ in range(ROUNDS):
        full = cp.with_twins(out)
        owner = {m.name: m.name for m in out}
        owner |= {t.name: m.name for m, t in zip(full, full[1:]) if m.side == cp.RIGHT and t.name == cp.left_name(m.name)}
        planes: dict[str, list[tuple[np.ndarray, float]]] = {}
        for name, found in coplanar.flush_planes([(m.name, m.part.mesh) for m in full], among=among).items():
            mirrored = owner[name] != name
            for n, d in found:
                n = n * MIRROR if mirrored else n
                kept = planes.setdefault(owner[name], [])
                if not any(np.allclose(n, k) and abs(d - e) < coplanar.PLANE_TOL_M for k, e in kept):
                    kept.append((n, d))
        if not planes:
            break
        out = [m if m.name not in planes else dataclasses.replace(m, part=dataclasses.replace(m.part, mesh=coplanar.set_back(m.part.mesh, planes[m.name])))
               for m in out]
        among = {m.name for m in cp.with_twins([m for m in out if m.name in planes])}
    return out


__all__ = ["set_back_flush_parts"]
