"""The heavy cannons' recesses in the bow spine (M7-T43, D75's H1 and H2): a rectangular bay sunk into the spine's top beside the
bow tower, each gun's turntable on its floor, so the gun lies in it at rest and swings up out of it. The maintainer's clip: a
rectangular opening with a hazard-striped rim, machinery on its walls.

Station frame (z aft from the bow tip, y up, x starboard). The spine's top (``station.SPINE``) is a plane between its rows, so the
top is rebuilt here as plates round the openings, each opening walled down to its floor: the spine stays one closed solid with two
pits in it, which is what the section check (``station_fidelity``), the collision and the hit volumes read.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from ..core.geometry import Material, Mesh
from . import station as st

HALF_WIDTH_M = 9.0  # across (x) from the pivot
AHEAD_M = 26.0  # ahead of the pivot (toward the bow), where the barrel lies at rest
BEHIND_M = 10.0  # behind it
STRIPE_BAND_M = 1.6  # the hazard band down the top of each wall
STRIPE_M = 1.4  # each stripe's width along the wall
STRIPE_LEAN_M = 1.0  # how far a stripe leans along the wall over the band's height
LIP = (1.0, 0.35, 0.3)  # the raised frame round the opening: width, height over the deck, overhang into the opening


@dataclass(frozen=True)
class Recess:
    """One gun's pit: its pivot (on the floor) and its opening."""

    name: str
    pivot: tuple[float, float, float]

    @property
    def x0(self) -> float:
        return self.pivot[0] - HALF_WIDTH_M

    @property
    def x1(self) -> float:
        return self.pivot[0] + HALF_WIDTH_M

    @property
    def z0(self) -> float:
        return self.pivot[2] - AHEAD_M

    @property
    def z1(self) -> float:
        return self.pivot[2] + BEHIND_M

    @property
    def floor(self) -> float:
        return self.pivot[1]


def recesses() -> list[Recess]:
    """A pit under each heavy cannon of D75's table."""
    from . import station_hardpoints as sh  # noqa: PLC0415 - the hardpoints build on the station's shapes

    return [Recess(name, tuple(p)) for name, kind, _, p, _ in sh.GRID_MOUNTS if kind == sh.HEAVY]


def top_at(z: float) -> float:
    return st.spine_row_at(z)[3]


def half_width_at(z: float) -> float:
    return st.spine_row_at(z)[1]


def _breaks(rows: Sequence[tuple[float, float, float, float]], pits: Sequence[Recess]) -> list[float]:
    zs = {r[0] for r in rows} | {p.z0 for p in pits} | {p.z1 for p in pits}
    return sorted(z for z in zs if rows[0][0] - 1e-6 <= z <= rows[-1][0] + 1e-6)


def deck(rows: Sequence[tuple[float, float, float, float]], pits: Sequence[Recess], material: Material) -> Mesh:
    """The spine's top from its first row to its last, as plates round the openings."""
    corners, insides = [], []
    zs = _breaks(rows, pits)
    for za, zb in zip(zs[:-1], zs[1:], strict=True):
        zm = 0.5 * (za + zb)
        cut = [p for p in pits if p.z0 - 1e-6 <= za and zb <= p.z1 + 1e-6]
        xs = sorted({x for p in cut for x in (p.x0, p.x1)})
        cells = [None, *xs, None]  # None: the spine's own edge at that z
        for k, (xa, xb) in enumerate(zip(cells[:-1], cells[1:], strict=True)):
            if k % 2 == 1:  # between a pit's two walls: open
                continue

            def at(x: float | None, z: float, side: float) -> np.ndarray:
                return np.array([side * half_width_at(z) if x is None else x, top_at(z), z])

            q = np.array([at(xa, za, -1.0), at(xb, za, 1.0), at(xb, zb, 1.0), at(xa, zb, -1.0)])
            corners.append(q)
            insides.append(np.array([q[:, 0].mean(), top_at(zm) - 5.0, zm]))
    return st.quads(corners, insides, material)


def _wall_ends(p: Recess) -> list[tuple[np.ndarray, np.ndarray, np.ndarray]]:
    """Each wall as (start, end, the direction into the pit) along the deck, the long walls split where the deck bends."""
    bends = sorted({p.z0, p.z1} | {r[0] for r in st.SPINE if p.z0 < r[0] < p.z1})
    out = []
    for x, into in ((p.x0, 1.0), (p.x1, -1.0)):
        for za, zb in zip(bends[:-1], bends[1:], strict=True):
            out.append((np.array([x, 0.0, za]), np.array([x, 0.0, zb]), np.array([into, 0.0, 0.0])))
    out.append((np.array([p.x0, 0.0, p.z0]), np.array([p.x1, 0.0, p.z0]), np.array([0.0, 0.0, 1.0])))
    out.append((np.array([p.x0, 0.0, p.z1]), np.array([p.x1, 0.0, p.z1]), np.array([0.0, 0.0, -1.0])))
    return out


def _up(v: np.ndarray, y: float) -> np.ndarray:
    return np.array([v[0], y, v[2]])


def pit(p: Recess, mats: dict[str, Material]) -> Mesh:
    """One pit: its walls (dark plating under a hazard band of diagonal stripes at the top), its floor, slatted machinery down the
    long walls, rails on the floor, the raised frame round the opening and a red warning lamp in each corner."""
    wall_m, hazard, dark, steel, mach, lamp = (mats[k] for k in ("recess", "hatch", "spine_top", "vane_frame", "machinery", "lamp"))
    walls, stripes_light, stripes_dark = [], [], []
    w_in, s_in, d_in = [], [], []
    for a, b, into in _wall_ends(p):
        out_pt = 0.5 * (a + b) - 3.0 * into
        ta, tb = top_at(a[2]), top_at(b[2])
        band_a, band_b = ta - STRIPE_BAND_M, tb - STRIPE_BAND_M
        walls.append(np.array([_up(a, p.floor), _up(b, p.floor), _up(b, band_b), _up(a, band_a)]))
        w_in.append(_up(out_pt, p.floor + 1.0))
        # The band: stripes leaning along the wall, cut square at its ends.
        length = float(np.linalg.norm(b - a))
        axis = (b - a) / length
        u = -STRIPE_LEAN_M
        k = int(round((a[0] + a[2]) / STRIPE_M))  # a phase from the wall's place, so neighbouring walls' stripes don't line up
        while u < length:
            lo0, lo1 = np.clip([u, u + STRIPE_M], 0.0, length)
            hi0, hi1 = np.clip([u + STRIPE_LEAN_M, u + STRIPE_LEAN_M + STRIPE_M], 0.0, length)
            if hi1 > hi0 + 1e-6 or lo1 > lo0 + 1e-6:
                def pt(s: float, top: bool) -> np.ndarray:
                    q = a + s * axis
                    t = top_at(q[2])
                    return _up(q, t if top else t - STRIPE_BAND_M)

                quad = np.array([pt(lo0, False), pt(lo1, False), pt(hi1, True), pt(hi0, True)])
                if np.linalg.norm(np.cross(quad[1] - quad[0], quad[2] - quad[0])) + np.linalg.norm(np.cross(quad[2] - quad[0], quad[3] - quad[0])) > 1e-6:
                    (stripes_light if k % 2 == 0 else stripes_dark).append(quad)
                    (s_in if k % 2 == 0 else d_in).append(_up(out_pt, quad[:, 1].mean()))
            u += STRIPE_M
            k += 1
    floor = np.array([[p.x0, p.floor, p.z0], [p.x1, p.floor, p.z0], [p.x1, p.floor, p.z1], [p.x0, p.floor, p.z1]])
    meshes = [st.quads(walls, w_in, wall_m), st.quads([floor], [np.array([p.pivot[0], p.floor - 5.0, p.pivot[2]])], wall_m),
              st.quads(stripes_light, s_in, hazard), st.quads(stripes_dark, d_in, dark)]
    # Slatted machinery down each long wall, clear of the gun's turntable.
    for x, into in ((p.x0, 1.0), (p.x1, -1.0)):
        for z in np.arange(p.z0 + 2.0, p.z1 - 1.0, 1.25):
            if abs(z - p.pivot[2]) < 7.5:
                continue
            x_in = x + into * 0.6
            meshes.append(st.block((min(x, x_in), p.floor + 1.0, z - 0.25), (max(x, x_in), p.floor + 4.2, z + 0.25), mach))
    # Rails along the floor ahead of the turntable.
    for dx in (-3.0, 3.0):
        meshes.append(st.block((p.pivot[0] + dx - 0.4, p.floor, p.z0 + 1.0), (p.pivot[0] + dx + 0.4, p.floor + 0.4, p.pivot[2] - 7.0), steel))
    # The raised frame round the opening, on the deck, its inner edge a little over the opening so no face lies in a wall's plane;
    # the long sides fit between the ends.
    w, h, over = LIP
    for z, side in ((p.z0, -1.0), (p.z1, 1.0)):
        t = top_at(z)
        meshes.append(st.block((p.x0 - w, t - 0.5, min(z + side * w, z - side * over)), (p.x1 + w, t + h, max(z + side * w, z - side * over)),
                               steel))
    for x, side in ((p.x0, -1.0), (p.x1, 1.0)):
        t_lo, t_hi = min(top_at(p.z0), top_at(p.z1)), max(top_at(p.z0), top_at(p.z1))
        meshes.append(st.block((min(x + side * w, x - side * over), t_lo - 0.5, p.z0 + over),
                               (max(x + side * w, x - side * over), t_hi + h, p.z1 - over), steel))
    # A red warning lamp in each corner, under the band (the spine carries no white lights, M7-T24).
    for x in (p.x0 + 0.4, p.x1 - 0.4):
        for z in (p.z0 + 0.4, p.z1 - 0.4):
            t = top_at(z) - STRIPE_BAND_M - 0.8
            meshes.append(st.block((x - 0.4, t - 0.4, z - 0.4), (x + 0.4, t + 0.4, z + 0.4), lamp))
    return Mesh.concatenate(meshes)


def spine_with_recesses(rows: Sequence[tuple[float, float, float, float]], mats: dict[str, Material]) -> Mesh:
    """The spine's slab from ``rows`` with the heavy cannons' pits sunk into its top."""
    pits = [p for p in recesses() if rows[0][0] < p.z0 and p.z1 < rows[-1][0]]
    body = st.spine_slab(rows, mats["spine"], top=False)
    return Mesh.concatenate([body, deck(rows, pits, mats["spine"]), *(pit(p, mats) for p in pits)])


__all__ = ["Recess", "deck", "pit", "recesses", "spine_with_recesses"]
