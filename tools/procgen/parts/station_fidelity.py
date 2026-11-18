"""The station's per-part section check (M7-T21, CLAUDE.md "STL fidelity"): the planes each part seen up close is cut at, against the
reference STL, with ``tools/refview/sections.py``. Station frame (z aft from the bow tip, x starboard, y up); a window (u0, u1, v0,
v1) in the plane's (u, v) round the part, clear of other parts where it can be (a Cobra arm's window starts over the drum's skin).
Each Cobra arm is cut in its own frame: turned onto the top before the cut, so one set of windows serves all four.

Exemptions: planes a part may fail for a reason the maintainer accepted, with that reason.

The main docking bay (M7-T25) is compared as the bow sees it (relief planes: the STL's bow is overlapping shells with mixed winding,
which the nonzero fill reads as a solid mouth) against the STL **locally scaled**: its frame block and mouth, and what stands on the
block, scaled by ``station_detail.BAY_SCALE`` (80/45) about the axis and the block's face, the ring and the cross housing at the STL's
size. The maintainer signed this (2026-11-14): the mouth is 80 m wide so T10's inbound civilians fit, the STL's is 45 m.
"""

from __future__ import annotations

import numpy as np

from tools.refview.sections import SectionPlane

from . import station as st
from . import station_detail as sd

ARM_PLANES = (  # (name, z, window: x from, x to, y from, y to, outline) on an arm standing on top
    # The head's planes compare outlines: the STL's circular hatch is a recess in the peak.
    ("head_760", 760.0, (-90.0, 90.0, 265.0, 335.0), True),
    ("head_800", 800.0, (-90.0, 90.0, 280.0, 335.0), True),
    ("neck_900", 900.0, (-70.0, 70.0, 265.0, 300.0), False),
    ("neck_960", 960.0, (-70.0, 70.0, 229.0, 275.0), False),
    ("root_1030", 1030.0, (-55.0, 55.0, 194.0, 246.0), False),
    # Through the launch halls (T05, approved: the hall seen through an open door, the second row inside), which the STL leaves
    # solid round its door shafts: the outline is compared, so the section's shape still counts.
    ("root_1060", 1060.0, (-55.0, 55.0, 194.0, 246.0), True),
    ("root_1101", 1101.5, (-55.0, 55.0, 194.0, 246.0), True),
    ("root_1240", 1240.0, (-55.0, 55.0, 194.0, 246.0), False),
)
WINGS = ("alpha", "beta", "delta", "zeta")


def arm_planes() -> list[SectionPlane]:
    """Each arm's planes, the arm turned onto the top (alpha is already there)."""
    out = []
    for wing, angle in zip(WINGS, st.ARM_ANGLES_DEG, strict=True):
        for name, z, window, outline in ARM_PLANES:
            out.append(SectionPlane(f"arm_{wing}_{name}", 2, z, window, turn_deg=90.0 - angle, outline=outline))
    return out


PLANES: dict[str, list[SectionPlane]] = {
    "cobra_arms": arm_planes(),
    "main_docking_bay": [  # the whole face (the ring, the housing, the block and its fans), then the block round the mouth, deeper
        *(SectionPlane(f"main_docking_bay_z{z:.0f}", 2, z, (-140.0, 140.0, -140.0, 140.0), relief=True)
          for z in (455.0, 472.0, 478.0, 483.0, 494.0, 508.0)),
        *(SectionPlane(f"main_docking_bay_mouth_z{z:.0f}", 2, z, (-90.0, 90.0, -50.0, 50.0), relief=True) for z in (500.0, 530.0, 550.0)),
    ],
    "cargo_bay": [
        SectionPlane("cargo_bay_z430", 2, 430.0, (-110.0, 110.0, 300.0, 380.0), outline=True),
        SectionPlane("cargo_bay_z465", 2, 465.0, (-110.0, 110.0, 300.0, 380.0), outline=True),
        SectionPlane("cargo_bay_side", 0, 0.0, (400.0, 500.0, 300.0, 380.0), outline=True),
        SectionPlane("cargo_bay_top", 1, 340.0, (-110.0, 110.0, 400.0, 500.0), outline=True),
    ],
    "dorsal_spine": [
        SectionPlane("spine_z1500", 2, 1500.0, (-200.0, 200.0, 400.0, 600.0)),
        SectionPlane("spine_z2000", 2, 2000.0, (-200.0, 200.0, 425.0, 600.0)),
        SectionPlane("spine_z2650", 2, 2650.0, (-200.0, 200.0, 340.0, 600.0)),
        SectionPlane("spine_z4520", 2, 4520.0, (-145.0, 145.0, 340.0, 600.0)),
        SectionPlane("spine_z5650", 2, 5650.0, (-200.0, 200.0, 350.0, 600.0)),
    ],
    # The heavy cannons' recesses beside the bow tower (M7-T43): across each pit, the spine round it, the tower left out (the STL
    # has none).
    "bow_recesses": [SectionPlane(f"recess_{side}_z{z:.0f}", 2, z, window) for side, window in (("port", (-110.0, -22.0, 330.0, 400.0)),
                                                                                              ("starboard", (22.0, 110.0, 330.0, 400.0)))
                     for z in (505.0, 515.0, 525.0)],
    # The rook tower between the heavy cannons (M7-T43), round its leaning axis; the STL's neck is narrower and lies aft.
    "bow_tower": [
        SectionPlane("tower_z520", 2, 520.0, (-40.0, 40.0, 370.0, 445.0)),
        SectionPlane("tower_x0", 0, 0.0, (480.0, 560.0, 370.0, 445.0)),
        SectionPlane("tower_y400", 1, 400.0, (-40.0, 40.0, 480.0, 560.0)),
    ],
    "command_section": [
        SectionPlane("bow_z200", 2, 200.0, (-200.0, 200.0, 290.0, 400.0)),
        SectionPlane("bow_z400", 2, 400.0, (-200.0, 200.0, 290.0, 400.0)),
        SectionPlane("command_z600", 2, 600.0, (-200.0, 200.0, 300.0, 480.0)),
        SectionPlane("command_z1000", 2, 1000.0, (-200.0, 200.0, 300.0, 480.0)),
        SectionPlane("command_z1150", 2, 1150.0, (-200.0, 200.0, 300.0, 480.0)),
        SectionPlane("command_z1250", 2, 1250.0, (-200.0, 200.0, 300.0, 480.0)),
    ],
}

# Plane name -> the accepted reason it may score under 0.90.
_ROOK = ("rook shape by the maintainer's request 2026-11-15, leaned aft like the STL: an 18 m round shaft on a flared base with a "
         "round top for I5, narrow so the heavy cannons cover each other; the STL's neck is about 12 m wide with a head")
EXEMPTIONS: dict[str, str] = {
    "tower_z520": f"{_ROOK} (0.340; the 40 x 50 m block it replaced 0.373)",
    "tower_x0": f"{_ROOK} (0.389; the block 0.544)",
    "tower_y400": f"{_ROOK} (0.446; the block 0.264)",
    "cargo_bay_side": "the throat and compartment are open for the pods (Q8 as refined; the maintainer: 'open only where the pods "
                      "enter'); the STL shuts the throat with a door plate",
}


# What the maintainer had scaled (M7-T25), in the STL's frame at the 8 km scale: the frame block and its mouth back to behind its door (|x|, |y|, z),
# and the fans and rails standing in front of the housing's face beside it (|x|, |y|, and in front of z). The housing keeps its size.
STL_BAY_REGION = (47.6, 25.7, 440.0, 570.0)
STL_FAN_REGION = (58.5, 11.5, 480.0)


def _split(poly: np.ndarray, axis: int, at: float) -> tuple[np.ndarray, np.ndarray]:
    """A convex polygon cut by the plane ``p[axis] = at``: the part below it and the part above (either may be empty)."""
    lo, hi = [], []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        da, db = a[axis] - at, b[axis] - at
        (lo if da <= 0.0 else hi).append(a)
        if da * db < 0.0:
            q = a + (b - a) * (da / (da - db))
            lo.append(q)
            hi.append(q)
    return np.array(lo), np.array(hi)


def _clip_box(tri: np.ndarray, hx: float, hy: float) -> tuple[list[np.ndarray], list[np.ndarray]]:
    """A triangle's pieces inside the box |x| <= hx, |y| <= hy, and outside it, as convex polygons."""
    inside, outside = tri, []
    for axis, at, keep_below in ((0, hx, True), (0, -hx, False), (1, hy, True), (1, -hy, False)):
        if len(inside) < 3:
            break
        below, above = _split(inside, axis, at)
        kept, cut = (below, above) if keep_below else (above, below)
        if len(cut) >= 3:
            outside.append(cut)
        inside = kept
    return ([inside] if len(inside) >= 3 else []), outside


def _fan(polys: list[np.ndarray]) -> np.ndarray:
    tris = [np.array([p[0], p[i], p[i + 1]]) for p in polys for i in range(1, len(p) - 1)]
    return np.array(tris).reshape(-1, 3, 3)


def _region(t: np.ndarray, hx: float, hy: float) -> tuple[np.ndarray, np.ndarray]:
    """The triangles' parts inside a box about the axis (|x| <= hx, |y| <= hy) and the rest, triangles cut where they cross it."""
    ax, ay = np.abs(t[:, :, 0]), np.abs(t[:, :, 1])
    inside = (ax <= hx).all(axis=1) & (ay <= hy).all(axis=1)
    outside = (t[:, :, 0].min(axis=1) >= hx) | (t[:, :, 0].max(axis=1) <= -hx) | (t[:, :, 1].min(axis=1) >= hy) | (t[:, :, 1].max(axis=1) <= -hy)
    crossing = ~inside & ~outside
    ins, outs = [], []
    for tri in t[crossing]:
        a, b = _clip_box(tri, hx, hy)
        ins += a
        outs += b
    return np.concatenate([t[inside], _fan(ins)]), np.concatenate([t[outside], _fan(outs)])


def scaled_reference(stl: np.ndarray) -> np.ndarray:
    """The STL with its frame block, mouth and fans scaled as the build's (``sd.BAY_SCALE`` about the axis and the block's face),
    triangles cut where they cross the scaled region."""
    t = np.asarray(stl, dtype=float).reshape(-1, 3, 3)
    hx, hy, z0, z1 = STL_BAY_REGION
    near = (t[:, :, 2] >= z0).all(axis=1) & (t[:, :, 2] <= z1).all(axis=1)
    block, rest = _region(t[near], hx, hy)
    fx, fy, fz = STL_FAN_REGION
    front = (rest[:, :, 2] < fz).all(axis=1)
    fans, beside = _region(rest[front], fx, fy)
    moved = np.concatenate([block, fans])
    moved[:, :, :2] *= sd.BAY_SCALE
    moved[:, :, 2] = sd.FACE_Z + (moved[:, :, 2] - sd.FACE_Z) * sd.BAY_SCALE
    return np.concatenate([t[~near], rest[~front], beside, moved])


# Part -> how its reference is made from the STL (the identity for every part but the main docking bay).
REFERENCES = {"main_docking_bay": scaled_reference}


def reference_for(part: str, stl: np.ndarray) -> np.ndarray:
    return REFERENCES.get(part, lambda t: t)(stl)


def all_planes() -> list[SectionPlane]:
    return [p for planes in PLANES.values() for p in planes]


__all__ = ["ARM_PLANES", "EXEMPTIONS", "PLANES", "REFERENCES", "STL_BAY_REGION", "STL_FAN_REGION", "all_planes", "arm_planes", "reference_for", "scaled_reference"]
