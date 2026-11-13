"""The station's collision shapes (M7-T19, D73): convex pieces from the same numbers as the shapes in ``station.py``, cut at the
same section planes as the render sections, so each shape belongs to one section (its name starts with the section's).

Round bodies are frusta between their profile's points (a 16-sided ring drawn round the circle, so the hull holds the mesh), slabs
are hulls between consecutive rows, boxes are boxes. Small parts (ribs, rails' clamps, stringers, the doors' wells) are left to
the gap tolerance. A piece over the budget has its sections' neighbouring shapes merged, inside each section. T05 refines the
bays and the aperture (a tunnel open to traffic).
"""

from __future__ import annotations

import math
from collections.abc import Sequence

import numpy as np

from ..core import collision as col
from ..core.geometry import rotation_z
from ..core.sections import SectionCut
from . import station as st

RING_SIDES = 16
RING_SECTORS = 8  # the aperture's ring


def _ring(z: float, r: float, sides: int = RING_SIDES, a0: float = 0.0, a1: float = 2.0 * math.pi) -> np.ndarray:
    """Points round the axis at ``z``: a polygon drawn round the circle of radius ``r`` (so it holds the round surface)."""
    full = abs(a1 - a0 - 2.0 * math.pi) < 1e-9
    if r <= 0.0:
        return np.array([[0.0, 0.0, z]])
    if full:
        a = a0 + np.arange(sides) * (a1 - a0) / sides
        rr = r / math.cos(math.pi / sides)
    else:
        a = np.linspace(a0, a1, sides)
        rr = r / math.cos(0.5 * (a1 - a0) / (sides - 1))
    return np.column_stack([rr * np.cos(a), rr * np.sin(a), np.full(len(a), z)])


def _split(z0: float, z1: float, planes: Sequence[float]) -> list[tuple[float, float]]:
    """A span along z cut at the planes inside it."""
    edges = [z0] + [p for p in planes if z0 + 1e-6 < p < z1 - 1e-6] + [z1]
    return list(zip(edges[:-1], edges[1:], strict=True))


def _lerp_rows(rows: Sequence[Sequence[float]], z: float) -> list[float]:
    zs = [r[0] for r in rows]
    return [z] + [float(np.interp(z, zs, [r[k] for r in rows])) for k in range(1, len(rows[0]))]


def frusta(name: str, profile: Sequence[tuple[float, float]], planes: Sequence[float]) -> list[tuple[str, np.ndarray]]:
    """A lathed body's convex pieces: one per profile segment and section."""
    out = []
    for (za, ra), (zb, rb) in zip(profile[:-1], profile[1:], strict=True):
        if zb - za < 1e-6 or max(ra, rb) <= 0.0:
            continue
        for z0, z1 in _split(za, zb, planes):
            r0, r1 = float(np.interp(z0, [za, zb], [ra, rb])), float(np.interp(z1, [za, zb], [ra, rb]))
            out.append((name, np.concatenate([_ring(z0, r0), _ring(z1, r1)])))
    return out


def slab_pieces(name: str, rows: Sequence[tuple[float, ...]], planes: Sequence[float], to_box, tol: float = 0.0,
                max_rows: int = 8) -> list[tuple[str, np.ndarray]]:
    """A slab's convex pieces between consecutive rows (cut again at the section planes); ``to_box`` turns a row into its four
    corners. With ``tol``, a run of rows that stays within ``tol`` of the straight line between its ends is one piece (at most
    ``max_rows`` rows, so a hull keeps every corner)."""
    zs = sorted({float(r[0]) for r in rows} | {float(p) for p in planes if rows[0][0] < p < rows[-1][0]})
    dense: list[list[float]] = []
    for z in zs:
        exact = [list(r) for r in rows if abs(r[0] - z) < 1e-9]
        dense += exact if exact else [_lerp_rows(rows, z)]
    out = []
    a = 0
    while a < len(dense) - 1:
        b = a + 1
        while b + 1 < len(dense) and b + 1 - a < max_rows and _straight(dense[a: b + 2], tol) and not _on_plane(dense[b][0], planes) \
                and dense[b + 1][0] - dense[b][0] > 1e-6:
            b += 1
        if dense[b][0] - dense[a][0] > 1e-6:
            out.append((name, np.concatenate([to_box(r) for r in dense[a: b + 1]])))
        a = b
    return out


def _on_plane(z: float, planes: Sequence[float]) -> bool:
    return any(abs(z - p) < 1e-6 for p in planes)


def _straight(run: Sequence[Sequence[float]], tol: float) -> bool:
    """Whether every row of a run lies within ``tol`` of the line between its first and last (each value against z)."""
    if tol <= 0.0:
        return False
    z = np.array([r[0] for r in run])
    if z[-1] - z[0] < 1e-9:
        return False
    t = (z - z[0]) / (z[-1] - z[0])
    v = np.array([r[1:] for r in run])
    line = v[0] + t[:, None] * (v[-1] - v[0])
    return bool(np.abs(v - line).max() <= tol)


def _sym(row: Sequence[float]) -> np.ndarray:
    z, w, y0, y1 = row
    return np.array([[-w, y0, z], [w, y0, z], [w, y1, z], [-w, y1, z]])


def _sec(row: Sequence[float]) -> np.ndarray:
    z, x0, x1, y0, y1 = row
    return np.array([[x0, y0, z], [x1, y0, z], [x1, y1, z], [x0, y1, z]])


def _block(lo: Sequence[float], hi: Sequence[float]) -> np.ndarray:
    lo, hi = np.asarray(lo, dtype=float), np.asarray(hi, dtype=float)
    return np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])


def _blocks(name: str, lo: Sequence[float], hi: Sequence[float], planes: Sequence[float]) -> list[tuple[str, np.ndarray]]:
    return [(name, _block((lo[0], lo[1], z0), (hi[0], hi[1], z1))) for z0, z1 in _split(lo[2], hi[2], planes)]


def _turned(pieces: list[tuple[str, np.ndarray]], angles_deg: Sequence[float]) -> list[tuple[str, np.ndarray]]:
    return [(f"{name}{k}", pts @ rotation_z(math.radians(a - 90.0)).T) for k, a in enumerate(angles_deg) for name, pts in pieces]


def drum_pieces(planes: Sequence[float]) -> list[tuple[str, np.ndarray]]:
    """What turns, in the station frame."""
    out = []
    for name, profile in (("sphere", st.SPHERE_PROFILE), ("body", st.BODY_PROFILE), ("fwd_band", st.FWD_BAND_PROFILE),
                          ("green", st.GREEN_PROFILE), ("aft_band", st.AFT_BAND_PROFILE)):
        out += frusta(name, profile, planes)
    # The aperture's door: its front ring and well closed for now (T05 opens the tunnel).
    out += frusta("aperture", [(st.APERTURE_HUB[1], st.DOOR_R), (st.DOOR_Z, st.DOOR_R)], planes)
    arm = slab_pieces("arm_head", [(z, -w, w, r0, r1) for z, w, r0, r1 in st.ARM_HEAD], planes, _sec)
    z0, z1, w, r0, r1 = st.ARM_HATCH
    arm += slab_pieces("arm_hatch", [(z0, -w, w, r0, r1), (z1, -w, w, r0, r1), (z1 + 40.0, -0.8 * w, 0.8 * w, r0 + 10.0, r1 - 5.0)], planes,
                       _sec)
    pz0, pz1, half, under, top = st.ARM_PRONG
    for x in st.ARM_PRONGS_X:
        arm += _blocks("arm_prong", (x - half, under, pz0), (x + half, top, pz1), planes)
    kz, kr, semi = st.ARM_KNOB
    arm.append(("arm_knob", _knob_points(kz, kr, semi)))
    out += _turned(arm, st.ARM_ANGLES_DEG)
    pod = slab_pieces("pod", [(1450.0, -30.0, 30.0, 300.0, 350.0), (1550.0, -35.0, 35.0, 300.0, 368.0), (1650.0, -30.0, 30.0, 290.0, 350.0)],
                      planes, _sec)
    out += _turned(pod, st.ARM_ANGLES_DEG)
    out += frusta("ring_teeth", [(st.RING_Z[0] + 6.0, 404.0), (st.RING_Z[1] - 4.0, 404.0)], planes)
    out += frusta("rim_fwd", [(2292.0, 414.0), (2338.0, 414.0)], planes)
    out += frusta("rim_aft", [(4792.0, 414.0), (4838.0, 414.0)], planes)
    out += frusta("waist_teeth", [(1010.0, 165.0), (1310.0, 165.0)], planes)
    out += frusta("body_teeth", [(1325.0, 262.0), (1338.0, 262.0)], planes)
    return out


def _knob_points(kz: float, kr: float, semi: Sequence[float]) -> np.ndarray:
    """The knob's ellipsoid, as points on a box of rings round it."""
    a, b, c = semi
    pts = []
    for t in np.linspace(-1.0, 1.0, 5):
        s = math.sqrt(max(0.0, 1.0 - t * t)) * 1.1 + 0.05
        for ang in np.linspace(0.0, 2.0 * math.pi, 6, endpoint=False):
            pts.append([a * s * math.cos(ang), kr + b * s * math.sin(ang), kz + c * t])
    return np.array(pts)


def frame_pieces(planes: Sequence[float]) -> list[tuple[str, np.ndarray]]:
    """What stands still, in the station frame."""
    out: list[tuple[str, np.ndarray]] = []
    prong = [(0.0, 45.0, 62.0, 312.0, 328.0), (200.0, 47.0, 115.0, 311.0, 336.0), (430.0, 50.0, 172.0, 311.0, 368.0)]
    out += slab_pieces("bow", prong, planes, _sec)
    out += slab_pieces("bow", [(z, -x1, -x0, y0, y1) for z, x0, x1, y0, y1 in prong], planes, _sec)
    rz0, rz1, ri, ro = st.RING_FRAME
    for k in range(RING_SECTORS):  # the aperture's ring in sectors, so its hole stays open
        a0, a1 = 2.0 * math.pi * k / RING_SECTORS, 2.0 * math.pi * (k + 1) / RING_SECTORS
        for z0, z1 in _split(rz0, rz1, planes):
            pts = np.concatenate([_ring(z, r, 3, a0, a1) for z in (z0, z1) for r in (ri, ro + 6.0)])
            out.append(("ring", pts))
    out += _blocks("pylon", (-25.0, ro - 4.0, 494.0), (25.0, 330.0, 542.0), planes)
    out += _blocks("tower", (-20.0, 370.0, 495.0), (20.0, st.BOW_TOWER_TOP, 545.0), planes)
    out += slab_pieces("spine", st.SPINE, planes, _sym, tol=10.0)
    out += slab_pieces("ramp", st.RAMP, planes, _sym, tol=6.0)
    hz0, hz1, hw, hy0, hy1 = st.HANGING_BOX
    out += _blocks("hanging_box", (-hw, hy0, hz0), (hw, 400.0, hz1), planes)  # up to the spine, over its struts
    for z0, z1, w, top in st.RADIATORS:
        out += _blocks("radiator", (-w, 470.0, z0), (w, top, z1), planes)
    for z in st.CARGO_Z:
        out += _blocks("cargo", (-st.CARGO[1], st.CARGO[2], z), (st.CARGO[1], st.CARGO[3], z + st.CARGO[0]), planes)
    dz, dy, dr = st.DOME
    out += _blocks("dome", (-dr, dy, dz - dr), (dr, dy + dr + 6.0, dz + dr), planes)
    out += frusta("hub", st.HUB_PROFILE, planes)
    outline, thick = st.FIN
    fin = np.array([[x, y, z] for x, z in outline for y in (-0.5 * thick, 0.5 * thick)])
    for sx in (1.0, -1.0):
        out.append(("fin", fin * np.array([sx, 1.0, 1.0])))
    for sx in (1.0, -1.0):
        out += [(n, p * np.array([sx, 1.0, 1.0])) for n, p in slab_pieces("boom", st.BOOM, planes, _sec, tol=6.0)]
        x0, x1, hy, hz = st.VANE_MOUNT
        for zc in st.VANE_Z:
            out += [(n, p * np.array([sx, 1.0, 1.0])) for n, p in _blocks("vane_mount", (x0, -hy, zc - hz), (x1, hy, zc + hz), planes)]
    rim, _ = st.vane_outline()
    for sx in (1.0, -1.0):
        for zc in st.VANE_Z:  # each pair of blades, up and down, as one plate
            pts = np.array([[sx * st.VANE_X + d, up * v, zc + u] for up in (1.0, -1.0) for u, v in rim[::3]
                            for d in (-0.5 * st.VANE_THICK_M, 0.5 * st.VANE_THICK_M)])
            out.append(("vane", pts))
    z0, z1, core, outer = st.TRUSS
    out += _blocks("truss", (-outer - 14.0, -outer - 14.0, z0), (outer + 14.0, outer + 14.0, z1), planes)
    for name, profile in (("torus", st.TORUS_PROFILE), ("shaft", st.SHAFT_PROFILE), ("reactor", st.REACTOR_PROFILE)):
        out += frusta(name, profile, planes)
    out += frusta("torus_teeth", [(7170.0, 264.0), (7270.0, 264.0)], planes)
    return out


def section_shapes(pieces: list[tuple[str, np.ndarray]], cuts: Sequence[SectionCut], shift: np.ndarray, budget: col.Budget
                   ) -> tuple[list[col.Shape], dict[str, list[int]]]:
    """The pieces moved by ``-shift`` into their piece's frame, as hulls named ``<section>/<part>.<n>``, merged inside their
    sections until the piece fits ``budget``; and each section's span of the list (first index, count)."""
    planes = np.array([c.z0 for c in cuts[1:]])
    by_section: list[list[col.Shape]] = [[] for _ in cuts]
    for k, (name, pts) in enumerate(pieces):
        p = np.asarray(pts, dtype=float) - shift
        s = int(np.searchsorted(planes, 0.5 * (p[:, 2].min() + p[:, 2].max()), side="right"))
        by_section[s].append(col.hull(f"{cuts[s].name}/{name}.{k}", p, budget.max_hull_points))
    shapes = [s for group in by_section for s in group]
    home = np.array([k for k, group in enumerate(by_section) for _ in group])
    while len(shapes) > budget.max_shapes:
        # Join the pair, inside one section, whose common box adds the least empty space (``col.merge_to_budget``'s rule).
        lo = np.array([s.bounds()[0] for s in shapes])
        hi = np.array([s.bounds()[1] for s in shapes])
        own = np.prod(hi - lo, axis=1)
        added = np.prod(np.maximum(hi[:, None], hi[None]) - np.minimum(lo[:, None], lo[None]), axis=2) - own[:, None] - own[None]
        added[np.tril_indices(len(shapes))] = np.inf
        added[home[:, None] != home[None]] = np.inf
        i, j = (int(k) for k in np.unravel_index(int(np.argmin(added)), added.shape))
        shapes[i] = col.hull(shapes[i].name, np.concatenate([shapes[i].corners(), shapes[j].corners()]), budget.max_hull_points)
        del shapes[j]
        home = np.delete(home, j)
    spans = {cut.name: [int(np.searchsorted(home, k)), int((home == k).sum())] for k, cut in enumerate(cuts)}
    return shapes, spans


__all__ = ["drum_pieces", "frame_pieces", "section_shapes"]
