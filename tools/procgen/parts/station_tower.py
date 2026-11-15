"""The bow spine's tower between the heavy cannons (M7-T43, the maintainer: "more of a rook chess piece shape and narrow enough that the
cannons can support each other around it"; a smooth round top, no battlements): a round shaft on a flared base, flaring out to a
cylindrical top that mounts D75's interceptor I5. Station frame (z aft from the bow tip, y up, x starboard).

The old tower was a 40 x 50 m block that hid each heavy cannon from the other's side; the rook's shaft is 18 m across, its top 25 m.
It leans aft like the STL's neck (the maintainer, 2026-11-15: "lean it like the STL"): each level is the same circle, shifted aft the
lower it lies, so the top stays round and level under I5 and the foot sits aft of it.
"""

from __future__ import annotations

import math

import numpy as np

from ..core.geometry import Material, Mesh, lathe, rotation_x

CENTRE_Z = 520.0  # under I5
FOOT_Y = 370.0  # inside the spine, whose top is at 375 here
CROWN_Y = 436.0  # the top, under I5's plinth
LEAN = 0.36  # m aft per metre below the top: the STL's neck runs from z 535 at y 400 to z 523 at y 430
# The outline from the foot up, (y, radius): a stepped, flared base, the shaft, a corbel out to the cylindrical top.
PROFILE = [(FOOT_Y, 0.0), (FOOT_Y, 14.5), (376.5, 14.5), (378.0, 13.2), (381.0, 10.8), (384.0, 9.4), (386.0, 9.0), (420.0, 9.0),
           (423.0, 10.6), (426.0, 12.5), (CROWN_Y, 12.5), (CROWN_Y, 0.0)]
SIDES = 32


def _profile_z() -> list[tuple[float, float]]:
    return [(y, r) for y, r in PROFILE]


def axis_z(y: float | np.ndarray) -> float | np.ndarray:
    """Where the leaning axis is at height ``y``."""
    return CENTRE_Z + (CROWN_Y - np.asarray(y, dtype=float)) * LEAN


def _leaned(points: np.ndarray) -> np.ndarray:
    """Points of the upright rook (round ``CENTRE_Z``) moved onto the leaning axis."""
    out = np.array(points, dtype=float)
    out[:, 2] += axis_z(out[:, 1]) - CENTRE_Z
    return out


def tower_mesh(wall: Material) -> Mesh:
    """The rook, lathed round its axis, then leaned."""
    body = lathe(_profile_z(), SIDES, wall, creases=set(range(1, len(PROFILE) - 1)), phase=math.pi / SIDES)
    body = body.transformed(rotation_x(-0.5 * math.pi), (0.0, 0.0, CENTRE_Z))  # the lathe's +z up the tower
    return Mesh(_leaned(body.vertices), body.faces, body.face_material, body.materials, body.face_chart, body.face_uv)


def collision_pieces(sides: int = 8) -> list[tuple[str, np.ndarray]]:
    """The rook's convex pieces: each band of its outline as the hull of the rings drawn round it (leaning keeps them convex)."""
    bands = [(0, 3), (3, 6), (6, 8), (8, 11)]  # foot and base, flare, shaft, corbel and top (indices into PROFILE)
    grow = 1.0 / math.cos(math.pi / sides)  # a polygon round the circle, so the hull holds the mesh
    out = []
    for a, b in bands:
        pts = []
        for y, rad in PROFILE[a + 1: b + 1] if a == 0 else PROFILE[a: b + 1]:
            for k in range(sides):
                t = 2.0 * math.pi * k / sides
                pts.append([rad * grow * math.cos(t), y, CENTRE_Z + rad * grow * math.sin(t)])
        out.append(("tower", _leaned(np.asarray(pts))))
    return out


def max_radius() -> float:
    return max(r for _, r in PROFILE)


def ramp_end(z0: float, y0: float, slope: float) -> tuple[float, float]:
    """Where a ramp rising ``slope`` m a metre aft from (``z0``, ``y0``) along the centreline meets the leaning axis: (z, y)."""
    # y = y0 + slope (z - z0) and z = CENTRE_Z + (CROWN_Y - y) LEAN, solved together.
    z = (CENTRE_Z + LEAN * (CROWN_Y - y0 + slope * z0)) / (1.0 + slope * LEAN)
    return z, y0 + slope * (z - z0)


__all__ = ["CENTRE_Z", "CROWN_Y", "LEAN", "PROFILE", "axis_z", "collision_pieces", "max_radius", "ramp_end", "tower_mesh"]
