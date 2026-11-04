"""Brakiri Bokmai transport parts (docs/design-references.md "Brakiri Bokmai transport", docs/assets-civilian.md
"brakiri_bokmai").

The frame: the tall bow blade with its flank insets (the turret mounts, Q22) and a window row, the dorsal spine to the
fork, the fork struts and posts, the lower arms, the joints, necks and nacelles with their cups and engine domes, the
upper and lower fins, and the spindle the pods ride on. Then the cargo pod model (its own frame, origin at the mount)
and the Brakiri turret model.

Frame of the design references: x to starboard, y up from the reference model's box centre, z aft from the prow,
metres (Godot's axes). Every shape is our own loft through station tables measured off the reference's sections and
views (rounded, a handful of numbers per station); no reference geometry is copied.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np

from ..core.civilian import CENTRE, RIGHT, Piece
from ..core.geometry import Mesh, assign_material_by_predicate, box, ellipsoid_cap, lathe, rotation_x, sweep_rect
from ..styles import Style
from . import Anchor, Collision, Part
from .narn import LoftSolid
from .solids import Solid, lathe_solid
from .starfury import section_loft
from .weapons import BarrelSpec, gun_barrel

_Z_TO_Y = rotation_x(-0.5 * math.pi)  # takes local +Z to +Y

# --- the bow ---------------------------------------------------------------------------------------------------------
# Horizontal sections of the blade, bottom to top: (y, z front, z rear, half-widths at 2, 10, 25, 50, 75, 90 and 98 %
# of the way from front to rear). The rear is concave in side view (the socket under the spine); from y 9.9 up the blade
# runs on into the spine, which takes over behind z 16. The keel rows keep the blade only (the lower arms leave it).
BOW_FRACTIONS = (0.02, 0.10, 0.25, 0.50, 0.75, 0.90, 0.98)
BOW_ROWS = (
    (-0.33, 6.94, 8.25, 0.03, 0.17, 0.37, 0.44, 0.43, 0.26, 0.10),
    (-0.20, 5.72, 9.49, 0.41, 0.57, 0.77, 0.84, 0.88, 0.76, 0.62),
    (0.10, 4.77, 13.16, 0.65, 1.03, 1.15, 1.40, 1.50, 1.30, 0.90),
    (0.80, 3.82, 14.50, 0.94, 1.32, 1.43, 1.55, 1.60, 1.40, 1.00),
    (1.50, 3.27, 14.55, 1.00, 1.41, 1.55, 1.65, 1.65, 1.45, 1.00),
    (2.20, 2.87, 14.53, 1.02, 1.45, 1.60, 1.68, 1.70, 1.50, 1.05),
    (2.90, 2.52, 14.28, 1.03, 1.49, 1.64, 1.67, 1.85, 1.71, 1.30),
    (3.60, 2.19, 13.99, 1.02, 1.52, 1.67, 1.65, 1.66, 1.50, 1.17),
    (4.30, 1.86, 13.74, 1.03, 1.56, 1.71, 1.66, 1.62, 1.45, 1.06),
    (5.00, 1.52, 13.55, 1.06, 1.64, 1.77, 1.68, 1.62, 1.44, 1.02),
    (5.70, 1.16, 13.45, 1.10, 1.73, 1.84, 1.72, 1.62, 1.44, 1.01),
    (6.40, 0.81, 13.40, 1.16, 1.84, 1.96, 1.78, 1.63, 1.45, 1.01),
    (7.10, 0.49, 13.42, 1.24, 1.95, 2.06, 1.83, 1.65, 1.47, 1.01),
    (7.80, 0.22, 13.57, 1.33, 2.09, 2.19, 1.89, 1.69, 1.50, 1.02),
    (8.50, 0.07, 13.88, 1.45, 2.25, 2.32, 1.96, 1.73, 1.52, 0.99),
    (9.20, 0.06, 14.62, 1.63, 2.45, 2.44, 2.03, 1.80, 1.54, 0.89),
    (9.90, 0.25, 16.00, 1.97, 2.59, 2.54, 2.09, 1.87, 1.56, 1.31),
    (10.60, 0.65, 16.00, 2.27, 2.73, 2.65, 2.25, 2.07, 1.92, 1.88),
    (11.30, 1.28, 16.00, 2.45, 2.82, 2.74, 2.41, 2.29, 2.25, 2.22),
    (12.00, 2.42, 16.00, 2.56, 2.80, 2.76, 2.56, 2.50, 2.49, 2.49),
    (12.70, 4.90, 16.00, 2.33, 2.64, 2.64, 2.61, 2.60, 2.61, 2.61),
    (12.90, 6.36, 16.00, 2.29, 2.45, 2.60, 2.59, 2.59, 2.59, 2.59),
    (13.05, 7.97, 16.00, 2.25, 2.33, 2.44, 2.53, 2.56, 2.57, 2.57),
    (13.15, 9.46, 16.00, 2.22, 2.27, 2.32, 2.38, 2.41, 2.41, 2.41),
)  # fmt: skip

# The stepped inset high on each flank (Q22: the turret mounts), in side view: two strips 1.2 m tall, the upper one
# further forward, (z from, z to, y bottom, y top). The turret's seat is the middle of the full-height step.
INSET_STRIPS = ((4.1, 7.35, 8.4, 9.6), (5.8, 8.95, 7.25, 8.45))
_UP, _LOW = INSET_STRIPS
INSET_OUTLINE = ((_UP[0], _UP[3]), (_UP[1], _UP[3]), (_UP[1], _LOW[3]), (_LOW[1], _LOW[3]), (_LOW[1], _LOW[2]), (_LOW[0], _LOW[2]),
                 (_LOW[0], _UP[2]), (_UP[0], _UP[2]))  # fmt: skip
TURRET_SEAT = (2.04, 8.45, 6.58)  # flank_r on the inset (the maintainer's sheet, 2026-11-03); up +x, outboard
WINDOW_ROW = (10.9, (4.0, 5.2, 6.4, 7.6, 8.8, 10.0))  # y, window centres z: a row on each flank above the inset
WINDOW_SIZE = (0.36, 0.5)  # height, length
EYE = (0.0, 8.5, 6.5)  # inside the bow behind the insets


def bow_half_width(y: float, z: float) -> float:
    """The blade's half-width at height ``y`` and station ``z`` (0 outside it): the burial and placement rule."""
    ys = [row[0] for row in BOW_ROWS]
    if not ys[0] <= y <= ys[-1]:
        return 0.0
    k = min(int(np.searchsorted(ys, y, side="right")) - 1, len(ys) - 2)
    t = (y - ys[k]) / (ys[k + 1] - ys[k])
    row = (1.0 - t) * np.array(BOW_ROWS[k]) + t * np.array(BOW_ROWS[k + 1])
    zf, zr, hws = row[1], row[2], row[3:]
    if not zf <= z <= zr:
        return 0.0
    f = (z - zf) / (zr - zf)
    return float(np.interp(f, (0.0, *BOW_FRACTIONS, 1.0), (0.0, *hws, 0.0)))


def _bow_ring(row: Sequence[float]) -> np.ndarray:
    y, zf, zr = row[:3]
    right = [(hw, y, zf + f * (zr - zf)) for f, hw in zip(BOW_FRACTIONS, row[3:])]
    left = [(-x, yy, zz) for x, yy, zz in reversed(right)]
    return np.array([(0.0, y, zf), *right, (0.0, y, zr), *left])


def _loft_solid(axis: int, levels: Sequence[float], rings: Sequence[np.ndarray]) -> Solid:
    """The burial volume of a loft whose convex sections stand across ``axis`` at ``levels``."""
    others = [i for i in range(3) if i != axis]
    loft = LoftSolid(axis, tuple(float(v) for v in levels), tuple(np.asarray(r)[:, others] for r in rings))
    pts = np.concatenate([np.asarray(r) for r in rings])
    return Solid(lambda p, m: loft.contains(p, m), (pts.min(axis=0), pts.max(axis=0)))


def _box_of(points: np.ndarray, basis: np.ndarray | None = None, name: str = "") -> Collision:
    """The smallest box with the given axes (columns of ``basis``) round some points."""
    b = np.eye(3) if basis is None else np.asarray(basis, dtype=float)
    local = np.asarray(points, dtype=float).reshape(-1, 3) @ b
    lo, hi = local.min(axis=0), local.max(axis=0)
    return Collision("box", b @ (0.5 * (lo + hi)), size=tuple(hi - lo), basis=b, name=name)


def _basis_along(direction: Sequence[float]) -> np.ndarray:
    """An orthonormal basis whose z column is ``direction`` and whose x column stays horizontal."""
    d = np.asarray(direction, dtype=float)
    d = d / np.linalg.norm(d)
    x = np.cross((0.0, 1.0, 0.0), d)
    if np.linalg.norm(x) < 1e-6:
        x = np.array([1.0, 0.0, 0.0])
    x /= np.linalg.norm(x)
    return np.column_stack([x, np.cross(d, x), d])


def _boxes_along(rings: Sequence[np.ndarray], spans: Sequence[tuple[int, int]], name: str) -> list[Collision]:
    """Oriented boxes round runs of a loft's rings, each aligned with its run."""
    out = []
    for k, (a, b) in enumerate(spans):
        pts = np.concatenate([np.asarray(rr) for rr in rings[a : b + 1]])
        axis = np.asarray(rings[b]).mean(axis=0) - np.asarray(rings[a]).mean(axis=0)
        out.append(_box_of(pts, _basis_along(axis), f"{name}{k}"))
    return out


def bow(style: Style) -> Piece:
    """The blade, lofted up through its horizontal sections. Anchors: ``eye`` (the cockpit camera), ``prow``."""
    hull = style.material("hull")
    rings = [_bow_ring(row) for row in BOW_ROWS]
    mesh = section_loft(rings, [hull] * len(rings[0]), hull, creases=())
    solid = _loft_solid(1, [row[0] for row in BOW_ROWS], rings)
    pts = np.concatenate(rings)
    low = np.concatenate([r for r, row in zip(rings, BOW_ROWS) if row[0] <= 9.9])
    high = np.concatenate([r for r, row in zip(rings, BOW_ROWS) if row[0] >= 9.9])
    collision = [_box_of(low, name="blade"), _box_of(high, name="crown")]
    prow = pts[np.argmin(pts[:, 2])]
    return Piece(Part("bow", mesh, {"eye": Anchor(EYE), "prow": Anchor(prow, (0.0, 0.0, -1.0))}, collision, 260_000.0, "bow"), solid)


def _on_flank(z: float, y: float, proud: float) -> np.ndarray:
    return np.array([bow_half_width(y, z) + proud, y, z])


def flank_inset(style: Style) -> Piece:
    """The stepped inset on the right flank, a dark panel on the blade's skin; the turret sits in its middle. Anchors:
    ``turret`` (the seat, up outboard)."""
    dark = style.material("hull_dark")
    verts = np.array([_on_flank(z, y, 0.03) for z, y in INSET_OUTLINE])
    # The outline's two steps as triangles: the upper strip (points 0, 1, 2, 6, 7) and the lower one (2, 3, 4, 5, 6).
    faces_arr = np.array([(0, 1, 2), (0, 2, 6), (0, 6, 7), (6, 2, 3), (6, 3, 5), (3, 4, 5)])
    normals = np.cross(verts[faces_arr[:, 1]] - verts[faces_arr[:, 0]], verts[faces_arr[:, 2]] - verts[faces_arr[:, 0]])
    faces_arr[normals[:, 0] < 0.0] = faces_arr[normals[:, 0] < 0.0][:, ::-1]  # facing outboard
    mesh = Mesh(verts, faces_arr, np.zeros(len(faces_arr), dtype=np.int64), (dark,))
    seat = Anchor(TURRET_SEAT, (1.0, 0.0, 0.0))
    return Piece(Part("inset_r", mesh, {"turret": seat}, [], 0.0, "bow"), None, RIGHT, fine=0.5)


def window_row(style: Style) -> Piece:
    """A dark strip with a row of small windows on the right flank above the inset."""
    strip, window = style.material("window_strip"), style.material("window")
    y, zs = WINDOW_ROW
    h, length = WINDOW_SIZE
    meshes = []
    z0, z1 = zs[0] - 0.5, zs[-1] + 0.5
    for za, zb in zip(np.linspace(z0, z1, 8)[:-1], np.linspace(z0, z1, 8)[1:]):
        zc = 0.5 * (za + zb)
        x = bow_half_width(y, zc)
        meshes.append(box((0.04, h + 0.24, zb - za), strip, center=(x + 0.01, y, zc)))
    for zc in zs:
        x = bow_half_width(y, zc)
        meshes.append(box((0.04, h, length), window, center=(x + 0.04, y, zc)))
    return Piece(Part("windows_r", Mesh.concatenate(meshes), {}, [], 0.0, "bow"), None, RIGHT, fine=0.4)


# --- the spine ---------------------------------------------------------------------------------------------------------
# (z, bottom y, top y, half-widths at 3, 12.5, 25, 37.5, 50, 62.5, 75, 87.5 and 97 % of the way up): a rounded section
# widest near its top, from inside the bow's crown to the fork, where it widens and ends between the struts.
SPINE_FRACTIONS = (0.03, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 0.97)
SPINE_ROWS = (
    (12.0, 9.59, 13.30, 0.91, 1.42, 1.80, 2.08, 2.28, 2.47, 2.59, 2.59, 2.36),
    (16.0, 9.59, 13.30, 0.91, 1.42, 1.80, 2.08, 2.28, 2.47, 2.59, 2.59, 2.36),
    (20.0, 9.75, 13.26, 0.91, 1.44, 1.82, 2.10, 2.31, 2.48, 2.60, 2.59, 2.35),
    (25.0, 9.75, 13.17, 0.91, 1.44, 1.81, 2.10, 2.31, 2.48, 2.59, 2.59, 2.36),
    (30.0, 9.75, 13.06, 0.97, 1.49, 1.86, 2.14, 2.34, 2.51, 2.63, 2.63, 2.41),
    (35.0, 9.77, 12.93, 1.13, 1.65, 2.00, 2.27, 2.46, 2.62, 2.74, 2.74, 2.54),
    (40.0, 9.79, 12.77, 1.54, 2.01, 2.32, 2.57, 2.75, 2.89, 2.99, 2.99, 2.81),
    (44.0, 9.81, 12.58, 2.18, 2.59, 2.88, 3.08, 3.23, 3.36, 3.44, 3.43, 3.26),
    (46.0, 9.81, 12.46, 2.62, 3.05, 3.31, 3.52, 3.66, 3.76, 3.83, 3.81, 3.63),
    (47.0, 9.81, 12.39, 2.97, 3.37, 3.63, 3.82, 3.95, 4.04, 4.09, 4.07, 3.90),
    (48.0, 9.81, 12.31, 3.31, 3.70, 3.94, 4.14, 4.26, 4.35, 4.39, 4.34, 4.17),
)  # fmt: skip


def _spine_ring(row: Sequence[float]) -> np.ndarray:
    z, y0, y1 = row[:3]
    right = [(hw, y0 + f * (y1 - y0), z) for f, hw in zip(SPINE_FRACTIONS, row[3:])]
    left = [(-x, y, zz) for x, y, zz in reversed(right)]
    return np.array([(0.0, y0, z), *right, (0.0, y1, z), *left])


def spine(style: Style) -> Piece:
    """The dorsal spine from inside the crown to the fork."""
    hull = style.material("hull")
    rings = [_spine_ring(row) for row in SPINE_ROWS]
    mesh = section_loft(rings, [hull] * len(rings[0]), hull, creases=())
    solid = _loft_solid(2, [row[0] for row in SPINE_ROWS], rings)
    collision = [_box_of(np.concatenate(rings[1:6]), name="fore"), _box_of(np.concatenate(rings[5:]), name="fork")]
    return Piece(Part("spine", mesh, {"top": Anchor((0.0, 13.3, 15.0), (0.0, 1.0, 0.0))}, collision, 160_000.0, "bow"), solid)


# --- sweeps ------------------------------------------------------------------------------------------------------------
def _ellipse(width: float, height: float, points: int, exponent: float) -> np.ndarray:
    t = 2.0 * math.pi * np.arange(points) / points
    c, s = np.cos(t), np.sin(t)
    k = 2.0 / exponent
    return np.stack([0.5 * width * np.sign(c) * np.abs(c) ** k, 0.5 * height * np.sign(s) * np.abs(s) ** k], axis=1)


def sweep_rings(path: Sequence[Sequence[float]], widths: Sequence[float], heights: Sequence[float], exponent: float = 3.0,
                points: int = 16) -> list[np.ndarray]:  # fmt: skip
    """Rounded sections along a path: ``widths`` across it horizontally, ``heights`` across it in the vertical plane
    through it."""
    p = np.asarray(path, dtype=float)
    seg = np.diff(p, axis=0)
    tangents = np.vstack([seg[:1], seg[:-1] + seg[1:], seg[-1:]])
    rings = []
    for i, pt in enumerate(p):
        b = _basis_along(tangents[i])
        ring2 = _ellipse(widths[i], heights[i], points, exponent)
        rings.append(pt + ring2[:, :1] * b[:, 0] + ring2[:, 1:] * b[:, 1])
    return rings


# The right lower arm's centre line (x, y, z), from inside the keel out along the measured leading edge (moved half the
# arm's width inboard) and straight aft, rising, into the joint.
ARM_PATH = (
    (1.20, 0.30, 9.80), (2.60, 0.20, 10.79), (3.92, 0.05, 11.81), (5.47, -0.15, 12.83), (6.96, -0.40, 13.82),
    (8.28, -0.65, 14.79), (9.40, -0.95, 15.73), (10.31, -1.12, 16.66), (10.98, -1.29, 17.55), (11.48, -1.38, 18.45),
    (11.90, -1.43, 19.38), (12.22, -1.45, 20.29), (12.45, -1.45, 21.22), (12.64, -1.45, 22.14), (12.84, -1.43, 24.07),
    (12.90, -1.33, 26.01), (12.92, -1.04, 30.01), (12.95, -0.60, 35.00), (12.97, -0.15, 40.00), (12.99, 0.34, 45.00),
    (13.01, 0.86, 50.00), (13.03, 1.31, 54.01), (13.06, 1.94, 58.01), (13.09, 2.30, 59.50),
)  # fmt: skip
ARM_WIDTH, ARM_HEIGHT = 2.0, 1.3
ARM_ROOT = ((2.6, 1.4), (2.5, 1.4), (2.4, 1.35), (2.3, 1.3), (2.2, 1.3), (2.1, 1.3))  # the first stations, thicker at the keel


def lower_arm(style: Style) -> Piece:
    """The right lower arm, from the keel out and aft to the joint."""
    hull = style.material("hull")
    n = len(ARM_PATH)
    widths = [ARM_ROOT[i][0] if i < len(ARM_ROOT) else ARM_WIDTH for i in range(n)]
    heights = [ARM_ROOT[i][1] if i < len(ARM_ROOT) else ARM_HEIGHT for i in range(n)]
    heights[-2:] = [1.8, 2.4]  # thickening into the joint
    rings = sweep_rings(ARM_PATH, widths, heights)
    mesh = section_loft(rings, [hull] * len(rings[0]), hull, creases=())
    collision = _boxes_along(rings, [(0, 6), (6, 13), (13, 17), (17, 20), (20, n - 1)], "run")
    return Piece(Part("arm_r", mesh, {}, collision, 40_000.0, "arm_r"), None, RIGHT)


# The fillet between the keel and the right arm's root, under the spindle's socket: sections across x (x, z front, z
# rear, y bottom, y top), from inside the keel out to where the arm runs on alone.
WEB_STATIONS = ((0.5, 9.0, 14.0, -0.2, 1.3), (2.0, 9.3, 14.4, -0.1, 1.3), (3.0, 10.1, 14.9, -0.2, 1.3),
                (4.0, 10.7, 15.2, -0.3, 1.1), (5.0, 11.4, 15.3, -0.4, 0.9), (6.0, 12.2, 15.4, -0.7, 0.5),
                (7.0, 13.0, 15.6, -1.0, 0.3))  # fmt: skip


def keel_web(style: Style) -> Piece:
    """The fillet joining the keel to the right arm's root, as the keel flares into the two arms (8.7 m across at
    z 10.9)."""
    hull = style.material("hull")
    rings = []
    for x, z0, z1, y0, y1 in WEB_STATIONS:
        e = _ellipse(z1 - z0, y1 - y0, 16, 3.0)
        rings.append(np.column_stack([np.full(16, x), 0.5 * (y0 + y1) + e[:, 1], 0.5 * (z0 + z1) + e[:, 0]]))
    mesh = section_loft(rings, [hull] * 16, hull, creases=())
    solid = _loft_solid(0, [st[0] for st in WEB_STATIONS], rings)
    return Piece(Part("web_r", mesh, {}, [_box_of(np.concatenate(rings), name="")], 10_000.0, "arm_r"), solid, RIGHT)


# The right fork strut's centre line, from the fork to the post's top, and its section (horizontal width, height).
STRUT_PATH = ((2.0, 11.07, 46.8), (3.36, 11.00, 49.0), (4.61, 10.92, 51.0), (5.93, 10.82, 53.0), (7.36, 10.70, 55.0),
              (9.08, 10.55, 57.0), (11.20, 10.30, 59.0), (12.60, 10.10, 60.4))  # fmt: skip
STRUT_SECTION = ((2.4, 2.5), (2.3, 2.35), (2.2, 2.15), (2.2, 1.95), (2.2, 1.8), (2.2, 1.75), (2.1, 1.9), (1.9, 2.0))


def fork_strut(style: Style) -> Piece:
    """The right fork strut from the spine's end out and aft to the post."""
    hull = style.material("hull")
    rings = sweep_rings(STRUT_PATH, [w for w, _ in STRUT_SECTION], [h for _, h in STRUT_SECTION])
    mesh = section_loft(rings, [hull] * len(rings[0]), hull, creases=())
    collision = _boxes_along(rings, [(0, 3), (3, len(rings) - 1)], "run")
    return Piece(Part("strut_r", mesh, {}, collision, 20_000.0, "engine_r"), None, RIGHT)


POST = (12.9, 60.45, 1.6, 2.5, 3.4, 11.2)  # x, z, width, depth, bottom y, top y


def post(style: Style) -> Piece:
    """The right post from the strut down into the joint."""
    hull = style.material("hull")
    x, z, w, d, y0, y1 = POST
    rings = [np.column_stack([x + e[:, 0], np.full(len(e), y), z + e[:, 1]]) for y in np.linspace(y0, y1, 6)
             for e in [_ellipse(w, d, 16, 4.0)]]  # fmt: skip
    mesh = section_loft(rings, [hull] * 16, hull, creases=())
    solid = _loft_solid(1, np.linspace(y0, y1, 6), rings)
    return Piece(Part("post_r", mesh, {}, [_box_of(np.concatenate(rings), name="")], 15_000.0, "engine_r"), solid, RIGHT)


# --- the joint, neck, nacelle, cup and dome ---------------------------------------------------------------------------
# Stations (z, centre x, centre y, width, height, exponent) of the right engine run from the arm's joint aft: the joint
# (with the post's foot), the neck (an upright oval), the nacelle swelling round the fin roots, and the tail closing to
# the cup's rim. Then the cup's inner wall back to its floor.
ENGINE_STATIONS = (
    (59.0, 13.12, 2.20, 2.05, 4.4, 2.6), (60.0, 13.12, 2.10, 2.10, 4.9, 2.6), (61.5, 13.12, 2.10, 2.10, 4.9, 2.6),
    (62.0, 13.08, 2.15, 2.00, 4.4, 2.4), (63.0, 13.08, 2.15, 1.96, 4.0, 2.4), (63.5, 13.08, 2.15, 1.96, 4.0, 2.4),
    (65.5, 13.08, 2.15, 2.00, 4.0, 2.4), (66.0, 13.09, 2.16, 2.15, 4.0, 2.4), (67.0, 13.13, 2.15, 2.58, 4.05, 2.4),
    (68.0, 13.24, 2.13, 3.25, 4.16, 2.4), (68.5, 13.31, 2.10, 3.64, 4.25, 2.5), (69.0, 13.37, 2.09, 3.94, 4.40, 2.5),
    (69.5, 13.40, 2.10, 4.12, 4.75, 2.3), (70.0, 13.44, 2.05, 4.29, 5.10, 2.3), (71.0, 13.46, 2.02, 4.45, 5.90, 2.3),
    (72.0, 13.48, 2.00, 4.57, 6.50, 2.3), (74.0, 13.48, 2.00, 4.64, 6.60, 2.3), (76.0, 13.46, 1.95, 4.51, 6.50, 2.3),
    (77.0, 13.43, 2.05, 4.35, 6.10, 2.3), (78.0, 13.32, 2.08, 3.86, 5.50, 2.3), (78.5, 13.25, 2.09, 3.29, 5.30, 2.4),
    (78.9, 13.16, 2.09, 2.70, 4.80, 2.3),
)  # fmt: skip
CUP = (13.16, 2.09, 2.0, 4.0, 78.9, 76.0)  # axis x, y; opening width, height; rim z, floor z
NECK_BAND = (63.5, 65.5)
DOME = (13.16, 2.09, 78.06, 1.70, 2.83, 3.89)  # centre x, y, z; width, height, length
RETRO = (14.5, 2.09, 67.1)  # on the nacelle's front shoulder, outboard of the neck, firing forward clear of the skin


def _engine_ring(st: Sequence[float], points: int = 20) -> np.ndarray:
    z, cx, cy, w, h, n = st
    e = _ellipse(w, h, points, n)
    return np.column_stack([cx + e[:, 0], cy + e[:, 1], np.full(points, z)])


def engine(style: Style) -> list[Piece]:
    """The right joint, neck and nacelle with its open cup (yellow band round the neck), and the engine dome in the cup.
    Anchors on the nacelle: ``main`` (the cup's mouth, aft), ``retro`` (the front shoulder, forward), ``centre``."""
    hull, yellow, cup_mat = style.material("hull"), style.material("stripe"), style.material("nozzle")
    rings = [_engine_ring(st) for st in ENGINE_STATIONS]
    cx, cy, cw, ch, rim_z, floor_z = CUP
    e = _ellipse(cw, ch, 20, 2.3)
    inner = [np.column_stack([cx + e[:, 0], cy + e[:, 1], np.full(20, z)]) for z in (rim_z - 0.05, floor_z)]
    mesh = section_loft(rings + inner, [hull] * 20, cup_mat, creases=())
    cent = mesh.face_centroids()
    in_cup = np.hypot((cent[:, 0] - cx) / (0.5 * cw + 0.05), (cent[:, 1] - cy) / (0.5 * ch + 0.05)) <= 1.0
    mesh = assign_material_by_predicate(mesh, cup_mat, in_cup & (cent[:, 2] > floor_z - 0.01))
    band = (cent[:, 2] > NECK_BAND[0]) & (cent[:, 2] < NECK_BAND[1])
    mesh = assign_material_by_predicate(mesh, yellow, band & ~in_cup)
    solid = _loft_solid(2, [st[0] for st in ENGINE_STATIONS], rings)
    collision = [
        _box_of(np.concatenate(rings[:3]), name="joint"),
        Collision("capsule", (13.3, 2.1, 0.5 * (60.5 + 80.3)), radius=2.3, height=80.3 - 60.5, name="nacelle"),
        _box_of(np.concatenate(rings[12:]), name="body"),
    ]
    main = Anchor((cx, cy, DOME[2] + 0.5 * DOME[5] + 0.05), (0.0, 0.0, 1.0))  # just behind the dome, so the plume shows
    retro = Anchor(RETRO, (0.0, 0.0, -1.0))
    nacelle = Part("nacelle_r", mesh, {"main": main, "retro": retro, "centre": Anchor((cx, cy, 72.0))}, collision, 90_000.0, "engine_r")
    dx, dy, dz, dw, dh, dl = DOME
    dome_mesh = ellipsoid_cap((0.5 * dw, 0.5 * dh, 0.5 * dl), -0.5 * dl + 0.02, style.material("engine_dome"), rings=10,
                              segments=24, axis_up=2).translated((dx, dy, dz))  # fmt: skip
    dome = Part("dome_r", dome_mesh, {}, [_box_of(dome_mesh.vertices, name="")], 2_000.0, "engine_r")
    return [Piece(nacelle, solid, RIGHT), Piece(dome, None, RIGHT, fine=0.7)]


# --- the fins ----------------------------------------------------------------------------------------------------------
# (y, leading edge z, trailing edge z, inboard x, outboard x), root (inside the nacelle) to tip, upper and lower.
UPPER_FIN = (
    (3.0, 69.50, 78.90, 12.15, 13.75), (5.5, 69.63, 79.30, 12.09, 13.91), (6.0, 69.69, 79.00, 12.15, 13.78),
    (7.0, 69.78, 78.32, 12.22, 13.64), (8.0, 69.83, 77.61, 12.24, 13.60), (9.0, 69.85, 76.91, 12.26, 13.58),
    (10.0, 69.85, 76.25, 12.27, 13.57), (11.0, 69.82, 75.64, 12.28, 13.55), (12.0, 69.79, 75.09, 12.31, 13.53),
    (13.0, 69.75, 74.61, 12.35, 13.48), (14.0, 69.71, 74.24, 12.43, 13.41), (14.5, 69.73, 74.07, 12.50, 13.34),
    (15.0, 69.93, 73.79, 12.61, 13.23), (15.3, 70.51, 73.21, 12.73, 13.10), (15.45, 71.40, 72.50, 12.86, 12.97),
)  # fmt: skip
LOWER_FIN = (
    (1.0, 69.80, 78.90, 11.95, 14.10), (-1.0, 70.01, 78.75, 11.95, 14.10), (-2.0, 70.36, 78.39, 11.98, 14.00),
    (-3.0, 70.58, 77.99, 12.04, 13.87), (-4.0, 70.76, 77.60, 12.07, 13.81), (-6.0, 71.03, 76.91, 12.11, 13.75),
    (-8.0, 71.25, 76.37, 12.16, 13.69), (-10.0, 71.43, 75.95, 12.24, 13.61), (-12.0, 71.59, 75.61, 12.33, 13.51),
    (-13.0, 71.67, 75.43, 12.38, 13.46), (-14.0, 71.77, 75.21, 12.42, 13.42), (-14.8, 71.94, 74.88, 12.47, 13.36),
    (-15.2, 72.25, 74.46, 12.57, 13.27), (-15.43, 72.85, 73.80, 12.86, 12.97),
)  # fmt: skip
FIN_INSET = (8.2, 12.8, 69.9, 77.0)  # the upper fins' yellow insets: y and z ranges, inside the outline
FIN_CAP_M = 1.5  # every fin's yellow top (or bottom) 1.5 m
FIN_STEP_M = 0.5


def _fin_ring(y: float, le: float, te: float, x0: float, x1: float) -> np.ndarray:
    """A chamfered plate section: sharp-ish leading and trailing edges, flat faces between."""
    c = te - le
    xm = 0.5 * (x0 + x1)
    pts = [(xm, le), (x1, le + 0.15 * c), (x1, te - 0.2 * c), (xm, te), (x0, te - 0.2 * c), (x0, le + 0.15 * c)]
    return np.array([(x, y, z) for x, z in pts])


def _fin_rows(table: Sequence[Sequence[float]]) -> list[np.ndarray]:
    """The table resampled every ``FIN_STEP_M`` so the yellow bands have crisp edges."""
    ys = [row[0] for row in table]
    order = np.argsort(ys)
    ys_sorted = np.array(ys)[order]
    cols = np.array(table)[order]
    sample = sorted(set(np.round(np.arange(ys_sorted[0], ys_sorted[-1], FIN_STEP_M), 3)) | set(np.round(ys_sorted, 3)))
    if ys[0] > ys[-1]:
        sample = sample[::-1]
    return [_fin_ring(y, *(np.interp(y, ys_sorted, cols[:, k]) for k in range(1, 5))) for y in sample]


def fin(style: Style, upper: bool) -> Piece:
    """The right upper or lower fin through the nacelle: thin chamfered sections stacked along y, yellow on its top (or
    bottom) 1.5 m and, on the upper fin, the inset on each face. Anchors: ``tip`` (outwards)."""
    hull, yellow = style.material("hull"), style.material("stripe")
    table = UPPER_FIN if upper else LOWER_FIN
    rings = _fin_rows(table)
    mesh = section_loft(rings, [hull] * 6, hull, creases=[0, 1, 2, 3, 4, 5])
    cent = mesh.face_centroids()
    tip_y = table[-1][0]
    cap = cent[:, 1] > tip_y - FIN_CAP_M if upper else cent[:, 1] < tip_y + FIN_CAP_M
    mesh = assign_material_by_predicate(mesh, yellow, cap)
    if upper:
        y0, y1, z0, z1 = FIN_INSET
        te = np.interp(cent[:, 1], [r[0] for r in table], [r[2] for r in table])
        inset = (cent[:, 1] > y0) & (cent[:, 1] < y1) & (cent[:, 2] > z0 + 0.4) & (cent[:, 2] < np.minimum(z1, te - 0.6))
        mesh = assign_material_by_predicate(mesh, yellow, inset)
    levels = [float(r[0, 1]) for r in rings]
    if levels[0] > levels[-1]:
        rings_s, levels_s = rings[::-1], levels[::-1]
    else:
        rings_s, levels_s = rings, levels
    solid = _loft_solid(1, levels_s, rings_s)
    tip = table[-1]
    anchor = Anchor((0.5 * (tip[3] + tip[4]), tip[0], 0.5 * (tip[1] + tip[2])), (0.0, 1.0 if upper else -1.0, 0.0))
    name = "fin_top_r" if upper else "fin_bot_r"
    collision = _boxes_along(rings, [(0, len(rings) // 2), (len(rings) // 2, len(rings) - 1)], "")
    return Piece(Part(name, mesh, {"tip": anchor}, collision, 12_000.0, "engine_r"), solid, RIGHT)


# --- the spindle -------------------------------------------------------------------------------------------------------
SPINDLE = (1.70, 0.965, 12.5, 58.0)  # axis y, radius, z from, z to
DRUM = (1.215, 15.35, 17.22)  # radius, z from, z to
SLEEVE_R = 1.48  # the pods' sleeves: the bore the hull's no-splats test leaves out round the spindle


def spindle(style: Style) -> Piece:
    """The rod the pods slide onto, anchored in the bow, with its coupling drum behind the bow."""
    dark = style.material("hull_dark")
    y, rr, z0, z1 = SPINDLE
    dr, d0, d1 = DRUM
    profile = [(z0, 0.0), (z0, rr), (d0, rr), (d0, dr), (d1, dr), (d1, rr), (z1, rr), (z1, 0.0)]
    mesh = lathe(profile, 24, dark, creases={1, 2, 3, 4, 5, 6}).translated((0.0, y, 0.0))
    solid = lathe_solid([(z0, rr), (d0, rr), (d0, dr), (d1, dr), (d1, rr), (z1, rr)]).translated((0.0, y, 0.0))
    collision = [Collision("box", (0.0, y, 0.5 * (z0 + z1)), size=(2.0 * dr, 2.0 * dr, z1 - z0), name="")]
    return Piece(Part("spindle", mesh, {}, collision, 30_000.0, "bow"), solid, CENTRE)


def assemble(style: Style) -> list[Piece]:
    """Every centre and right piece of the hull (no pods), authored frame (the asset mirrors the right ones)."""
    pieces = [bow(style), flank_inset(style), window_row(style), spine(style), spindle(style)]
    pieces += [keel_web(style), lower_arm(style), fork_strut(style), post(style), *engine(style), fin(style, True), fin(style, False)]
    names = [p.name for p in pieces]
    if len(names) != len(set(names)):
        raise ValueError("piece names repeat")
    return pieces


# --- the cargo pod (its own frame: origin at the mount on the spindle's axis, +y up, -z forward) ------------------------
POD_SIZE = (17.81, 11.74, 13.39)
# (distance in from an end face, width, height, exponent): the domed ends reach the full section 4 m in.
POD_STATIONS = ((0.0, 9.15, 3.08, 2.2), (0.05, 9.91, 3.84, 2.4), (0.2, 11.64, 5.57, 2.6), (0.4, 12.61, 6.53, 2.8),
                (0.7, 13.79, 7.72, 3.0), (1.0, 14.57, 8.50, 3.2), (1.5, 15.62, 9.55, 3.4), (2.0, 16.39, 10.32, 3.6),
                (2.5, 16.92, 10.85, 3.75), (3.0, 17.34, 11.27, 3.85), (3.5, 17.59, 11.52, 3.95), (4.0, 17.72, 11.65, 4.0),
                (6.695, 17.81, 11.74, 4.0))  # fmt: skip
POD_SLEEVE = (1.48, 0.35)  # radius, how far it stands out of each end
POD_STRAPS = (3.47, 0.49, 0.15)  # x, width, how far proud
POD_TOP_PLATE = (2.25, 0.25, 4.13)
POD_SIDE_PLATE = (0.24, 1.84, 3.65)
POD_RAILS = ((8.32, 4.44), (7.48, 5.28))  # (x, y) of the two rods along each upper corner
POD_RAIL_R = 0.19
POD_MASS_KG = 120_000.0


def _pod_ring(st: Sequence[float], z: float, points: int = 32) -> np.ndarray:
    _d, w, h, n = st
    e = _ellipse(w, h, points, n)
    return np.column_stack([e, np.full(points, z)])


def pod_rings() -> list[np.ndarray]:
    half = 0.5 * POD_SIZE[2]
    front = [_pod_ring(st, -half + st[0]) for st in POD_STATIONS]
    back = [_pod_ring(st, half - st[0]) for st in reversed(POD_STATIONS[:-1])]
    return front + back


def pod_half_height(x: float, z: float) -> float:
    """The pod's top above its axis at ``x`` and ``z`` (0 outside it)."""
    half = 0.5 * POD_SIZE[2]
    d = half - abs(z)
    if d < 0.0:
        return 0.0
    ds = [st[0] for st in POD_STATIONS]
    w, h, n = (float(np.interp(d, ds, [st[k] for st in POD_STATIONS])) for k in (1, 2, 3))
    u = abs(x) / (0.5 * w)
    return 0.0 if u >= 1.0 else 0.5 * h * (1.0 - u**n) ** (1.0 / n)


def _strap_loop(x: float, proud: float) -> np.ndarray:
    """The strap's path in the plane at ``x``: over the top, down the aft end, under the bottom and up the front."""
    half = 0.5 * POD_SIZE[2]
    zs = np.linspace(-half + 0.02, half - 0.02, 27)
    top = [(x, pod_half_height(x, z) + proud, z) for z in zs]
    bottom = [(x, -pod_half_height(x, z) - proud, z) for z in zs[::-1]]
    end = pod_half_height(x, half - 0.02)
    aft = [(x, y, half + proud) for y in np.linspace(end, -end, 5)[1:-1]]
    fore = [(x, y, -half - proud) for y in np.linspace(-end, end, 5)[1:-1]]
    return np.array(top + aft + bottom + fore + top[:1])


@dataclass(frozen=True)
class PodModel:
    part: Part
    solids: tuple[Solid, ...]


def cargo_pod(style: Style) -> PodModel:
    """The cargo pod in its own frame: a rounded box with domed ends, its sleeve round the spindle, two yellow straps,
    a top plate with two blocks, a plate on each side, saddles on the upper corners and the corner rails."""
    pod, dark, hull, yellow, hazard = (style.material(k) for k in ("pod", "hull_dark", "hull", "stripe", "hazard"))
    rings = pod_rings()
    body = section_loft(rings, [pod] * len(rings[0]), pod, creases=())
    half = 0.5 * POD_SIZE[2]
    sr, out = POD_SLEEVE
    sleeve = lathe([(-half - out, SPINDLE[1]), (-half - out, sr), (half + out, sr), (half + out, SPINDLE[1])], 24, dark,
                   creases={1, 2})  # fmt: skip
    meshes = [body, sleeve]
    sx, sw, proud = POD_STRAPS
    for x in (sx, -sx):
        loop = _strap_loop(x, 0.5 * proud)  # half buried, ``proud`` standing out
        meshes.append(sweep_rect(loop, (1.0, 0.0, 0.0), np.full(len(loop), sw), np.full(len(loop), proud + 0.12), yellow))
    pw, ph, pl = POD_TOP_PLATE
    top = pod_half_height(0.0, 0.0)
    trim = style.material("frame_plain")  # the frame's green without the pod's panel grid
    meshes.append(box((pw, ph + 0.1, pl), trim, center=(0.0, top + 0.5 * ph - 0.05, 0.0)))
    for z in (-0.9, 0.9):
        meshes.append(box((0.7, 0.3, 0.8), dark, center=(0.0, top + ph + 0.1, z)))
    tw, th, tl = POD_SIDE_PLATE
    for x in (1.0, -1.0):
        meshes.append(box((tw + 0.1, th, tl), hazard, center=(x * (0.5 * POD_SIZE[0] + 0.5 * tw - 0.05), 0.0, 0.0)))
    for (rx, ry), sgn in ((POD_RAILS[0], 1.0), (POD_RAILS[1], 1.0), (POD_RAILS[0], -1.0), (POD_RAILS[1], -1.0)):
        rod = lathe([(-half, 0.0), (-half, POD_RAIL_R), (half, POD_RAIL_R), (half, 0.0)], 10, dark, creases={1, 2})
        meshes.append(rod.translated((sgn * rx, ry, 0.0)))
    for sgn in (1.0, -1.0):
        cx, cy = 0.5 * (POD_RAILS[0][0] + POD_RAILS[1][0]), 0.5 * (POD_RAILS[0][1] + POD_RAILS[1][1])
        saddle = ellipsoid_cap((0.75, 0.75, 1.45), -0.74, trim, rings=6, segments=16, axis_up=1)
        meshes.append(saddle.translated((sgn * cx, cy, 0.0)))
    mesh = Mesh.concatenate(meshes)
    body_solid = _loft_solid(2, [float(r[0, 2]) for r in rings], rings)
    sleeve_solid = lathe_solid([(-half - out, sr), (half + out, sr)])
    lo, hi = mesh.bounds()
    collision = [Collision("box", 0.5 * (lo + hi), size=tuple(hi - lo), name="body")]
    anchors = {"mount": Anchor((0.0, 0.0, 0.0), (0.0, 1.0, 0.0))}
    return PodModel(Part("pod", mesh, anchors, collision, POD_MASS_KG, "pod"), (body_solid, sleeve_solid))


# --- the turret (its own frame: pivot at the origin on the mount, +y up, barrels along -z) -------------------------------
@dataclass(frozen=True)
class BrakiriTurretSpec:
    """A turning ring, a flattened lens housing with a yellow band round its rim, twin barrels with yellow muzzle
    rings (the maintainer's sheet, 2026-11-03)."""

    ring: tuple[float, float, float] = (0.8, -0.05, 0.35)  # radius, bottom, top
    housing: tuple[float, float, float] = (1.0, 0.45, 1.2)  # half-width, half-height, half-length
    housing_y: float = 0.8  # the housing's centre: the barrels' trunnion
    band: float = 0.08  # half-height of the yellow band round the housing's rim
    barrel: BarrelSpec = BarrelSpec(length=2.2, radius=0.12, base_radius=0.17, base_length=0.4, bore_radius=0.07,
                                    bore_depth=0.06, segments=14, mass_kg=0.0)  # fmt: skip
    barrel_x: float = 0.3
    barrel_m: float = 3.0
    muzzle_ring: tuple[float, float, float] = (0.2, 0.17)  # length from the muzzle, radius
    mass_kg: float = 3_000.0

    def solids(self) -> list[Solid]:
        rr, y0, y1 = self.ring
        hx, hy, hz = self.housing
        housing = Solid(lambda p, m: ((p[:, 0] / (hx - m)) ** 2 + (p[:, 1] / (hy - m)) ** 2 + (p[:, 2] / (hz - m)) ** 2) < 1.0,
                        ((-hx, -hy, -hz), (hx, hy, hz)), origin=(0.0, self.housing_y, 0.0))  # fmt: skip
        return [lathe_solid([(y0, rr), (y1, rr)]).transformed(_Z_TO_Y), housing]


def brakiri_turret(spec: BrakiriTurretSpec, style: Style) -> Part:
    """The turret model in its own frame. Anchors: ``pivot`` (up), ``trunnion`` (where the barrels elevate, on the
    turning axis), ``muzzle_l`` and ``muzzle_r`` (forward)."""
    hull, dark, yellow = style.material("hull"), style.material("hull_dark"), style.material("stripe")
    rr, y0, y1 = spec.ring
    ring = lathe([(y0, 0.0), (y0, rr), (y1, rr), (y1, 0.0)], 28, dark, creases={1, 2}).transformed(_Z_TO_Y)
    hx, hy, hz = spec.housing
    housing = ellipsoid_cap((hx, hy, hz), -hy + 0.01, hull, rings=12, segments=32).translated((0.0, spec.housing_y, 0.0))
    cent = housing.face_centroids()
    housing = assign_material_by_predicate(housing, yellow, np.abs(cent[:, 1] - spec.housing_y) < spec.band)
    meshes = [ring, housing]
    mount_z = spec.barrel.length - spec.barrel_m
    anchors = {"pivot": Anchor((0.0, 0.0, 0.0), (0.0, 1.0, 0.0)), "trunnion": Anchor((0.0, spec.housing_y, 0.0))}
    length, radius = spec.muzzle_ring
    for name, x in (("muzzle_r", spec.barrel_x), ("muzzle_l", -spec.barrel_x)):
        b = gun_barrel(spec.barrel, style).translated((x, spec.housing_y, mount_z))
        meshes.append(b.mesh)
        anchors[name] = b.anchor("muzzle")
        z0 = -spec.barrel_m
        collar = lathe([(z0 + 0.02, 0.0), (z0 + 0.02, radius), (z0 + length, radius), (z0 + length, 0.0)], 14, yellow, creases={1, 2})
        meshes.append(collar.translated((x, spec.housing_y, 0.0)))
    return Part("turret", Mesh.concatenate(meshes), anchors=anchors, mass_kg=spec.mass_kg)


__all__ = [
    "BOW_ROWS",
    "BrakiriTurretSpec",
    "ENGINE_STATIONS",
    "EYE",
    "INSET_OUTLINE",
    "INSET_STRIPS",
    "POD_SIZE",
    "PodModel",
    "SLEEVE_R",
    "SPINDLE",
    "TURRET_SEAT",
    "assemble",
    "bow_half_width",
    "brakiri_turret",
    "cargo_pod",
    "pod_half_height",
]
