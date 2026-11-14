"""The station's surfaces (M7-T04), from docs/assets-station.md "Colour scheme" and "Surface and panels": per shape, its drawn seams
(``core/seams.py``), its paint patterns and its lit windows, in the station frame (z aft from the bow tip).

No generic brick grid: the drum wears long plates along its axis between seam rings, the blue-violet panel blocks of the show
(stepped, interlocking blocks on the wide bands, a finer checkerboard on the docking sphere and forward body, blue blocks between
grey strips on the green zone); the spine and bow wear faceted plates in mixed sizes, darker on their top faces; the vanes are
deep blue in a grey frame with small dark recesses; the Cobra arms carry red edge trim and a row of yellow-orange hatches.
The small plating under 4 m is not here: the shared detail layer (``core/detail_layer.py``) carries it.
"""

from __future__ import annotations

import math
from collections.abc import Callable

import numpy as np

from ..core.seams import Cut, Feature, Plates, SeamLayout, every, rings
from ..core.textures import Marking
from ..styles import _hash01
from ..styles.earth_alliance_station import WINDOW_GLOW, WINDOW_STRENGTH, colour, lin
from . import station as st

Cover = Callable[[np.ndarray, np.ndarray], np.ndarray]


def _smooth(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _turn(p: np.ndarray) -> np.ndarray:
    """Each point's angle round the axis, 0 to 2 pi from +x toward +y."""
    return np.mod(np.arctan2(p[:, 1], p[:, 0]), 2.0 * math.pi)


def _radial(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """How squarely each surface point faces out from the axis (1 on a barrel, 0 on a ring's face)."""
    r = np.maximum(np.hypot(p[:, 0], p[:, 1]), 1e-6)
    return (n[:, 0] * p[:, 0] + n[:, 1] * p[:, 1]) / r


GREEN_JOINTS = tuple(every(2348.0, 4782.0, 304.0))  # the green zone's section joints (the wide band's edges fall near two)


PLATE_SHEEN = 0.14  # each plate's roughness off its paint's, +-: the highlight breaks up plate by plate (metal, not plastic)


# --- seams -----------------------------------------------------------------------------------------------------------
def _barrel(z0: float, z1: float, radius: float, course_m: float, around: int, seed: int, majors: tuple[float, ...] = ()) -> list[Feature]:
    """A drum section's plating: rings at its section joints, long plates along the axis in courses round it, each plate its own
    tone. ``majors`` are the structural joints (the low set's lines)."""
    box = {"lo": (-math.inf, -math.inf, z0), "hi": (math.inf, math.inf, z1)}
    return [
        *rings(2, majors, level=1, width=1.6),
        Plates(level=2, wrap="barrel", axis=2, radius=radius, around=around, cell=(course_m, 0.0), offset=(z0, 0.0), splits=1,
               min_m=18.0, keep=0.45, tone=0.0, sheen=0.0, depth=0.8, dark=0.7, symmetric=False, seed=seed, **box),
        Plates(level=3, wrap="barrel", axis=2, radius=radius, around=around, cell=(course_m, 0.0), offset=(z0, 0.0), splits=1,
               min_m=18.0, keep=0.45, tone=0.06, sheen=PLATE_SHEEN, grime=0.08, grime_m=4.0, depth=0.0, dark=0.0, symmetric=False,
               seed=seed, **box),
    ]


def _faceted(cell: tuple[float, float], seed: int, long_axis: int = 2) -> list[Feature]:
    """Plate-built structure (the spine, bow, hub, booms): mixed rectangles laid on whichever pair of axes each face spans."""
    return [
        Plates(level=2, wrap="sides", long_axis=long_axis, cell=cell, splits=2, min_m=8.0, keep=0.3, tone=0.0, sheen=0.0, depth=0.8,
               dark=0.7, seed=seed),
        Plates(level=3, wrap="sides", long_axis=long_axis, cell=cell, splits=2, min_m=8.0, keep=0.3, tone=0.07, sheen=PLATE_SHEEN, grime=0.1,
               grime_m=3.0, depth=0.0, dark=0.0, seed=seed),
    ]


def layouts() -> dict[str, SeamLayout]:
    """Each shape's seams by name, in the station frame."""
    band_joints = tuple(every(1800.0, 2290.0, 122.5))
    aft_joints = tuple(every(4840.0, 5400.0, 140.0))
    green_joints = GREEN_JOINTS
    return {
        "sphere": SeamLayout.of([*_barrel(560.0, 945.0, 270.0, 46.0, 36, 3, (700.0, 800.0, 900.0)),
                                 Cut(axis=2, at=st.DOOR_Z + 30.0, level=1, width=1.4)]),
        "fwd_body": SeamLayout.of(_barrel(1330.0, 1692.0, 320.0, 60.0, 40, 5, (1400.0, 1540.0, 1640.0))),
        "fwd_band": SeamLayout.of(_barrel(1790.0, 2340.0, st.BAND_R, 61.25, 48, 7, band_joints)),
        "green": SeamLayout.of(_barrel(2348.0, 4782.0, st.GREEN_R, 76.0, 40, 11, green_joints)),
        "aft_band": SeamLayout.of(_barrel(4782.0, 5500.0, st.BAND_R, 70.0, 48, 13, aft_joints)),
        "arms": SeamLayout.of(_faceted((30.0, 16.0), 17)),
        "aperture": SeamLayout.of([Plates(level=2, wrap="polar", axis=2, radius=105.0, around=32, cell=(19.0, 0.0), offset=(88.0, 0.0),
                                          splits=0, min_m=6.0, tone=0.06, sheen=PLATE_SHEEN, depth=0.9, dark=0.75, seed=83,
                                          lo=(-math.inf, -math.inf, st.DOOR_Z - 1.0), hi=(math.inf, math.inf, st.DOOR_Z + 1.0))]),
        "pods": SeamLayout.of(_faceted((20.0, 12.0), 19)),
        "stringers": SeamLayout.of([Cut(axis=2, at=z, level=2) for z in every(2360.0, 4770.0, 60.0)]),
        "bow": SeamLayout.of(_faceted((40.0, 22.0), 23)),
        "spine": SeamLayout.of(_faceted((48.0, 24.0), 29)),
        "hub": SeamLayout.of([*_barrel(5560.0, 5790.0, 347.0, 57.5, 40, 31, (5675.0,)),
                              Plates(level=2, wrap="polar", axis=2, radius=200.0, around=24, cell=(40.0, 0.0), splits=1, min_m=12.0,
                                     tone=0.05, depth=0.7, dark=0.6, seed=37, lo=(-math.inf, -math.inf, 5790.0))]),
        "fins": SeamLayout.of(_faceted((44.0, 26.0), 41, long_axis=0)),
        "booms": SeamLayout.of(_faceted((36.0, 14.0), 43)),
        "cargo": SeamLayout.of(_faceted((36.5, 20.0), 47)),
        "aft": SeamLayout.of([*rings(2, (7160.0, 7280.0, 7400.0, 7500.0, 7600.0, 7790.0, 7870.0, 7950.0), level=1, width=1.4),
                              Plates(level=2, wrap="polar", axis=2, radius=200.0, around=36, cell=(30.0, 0.0), splits=0, min_m=10.0,
                                     tone=0.05, depth=0.8, dark=0.7, seed=53, lo=(-math.inf, -math.inf, 7100.0),
                                     hi=(math.inf, math.inf, 7300.0)),
                              Plates(level=2, wrap="barrel", axis=2, radius=170.0, around=32, cell=(40.0, 0.0), splits=0, min_m=10.0,
                                     tone=0.06, depth=0.8, dark=0.7, symmetric=False, seed=59, lo=(-math.inf, -math.inf, 7700.0))]),
    }


# --- paint -----------------------------------------------------------------------------------------------------------
STEPS = (0.0, 1.0, 2.0, 1.0)  # a block edge's notches, in panels: a stair out and back, so neighbouring blocks interlock


def band_blocks(z0: float, z1: float, radius: float, around: int, rows: int, notch_m: float, margin_m: float, seed: int) -> Cover:
    """The wide bands' blue-violet blocks: a checker of blocks round the band whose edges step out and back in panel-sized
    notches, so the blocks interlock; a grey frame inside each, and a few cells turned to the other colour."""
    block_s = 2.0 * math.pi * radius / around
    block_z = (z1 - z0) / rows
    steps = np.asarray(STEPS) * notch_m

    def cover(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        s = _turn(p) * radius
        z = p[:, 2] - z0
        row, col = np.floor(z / notch_m).astype(np.int64), np.floor(s / notch_m).astype(np.int64)
        ds, dz = steps[np.mod(row, len(steps))], steps[np.mod(col, len(steps))]
        bs = np.mod(np.floor((s + ds) / block_s), around).astype(np.int64)
        bz = np.floor((z + dz) / block_z).astype(np.int64)
        blue = ((bs + bz) % 2 == 0) ^ (_hash01(bs, bz, np.full(len(p), seed, dtype=np.int64)) < 0.12)
        fs, fz = np.mod(s + ds, block_s), np.mod(z + dz, block_z)
        inside = (fs > margin_m) & (fs < block_s - margin_m) & (fz > margin_m) & (fz < block_z - margin_m)
        on = (z >= 0.0) & (z <= z1 - z0) & (_radial(p, n) > 0.6)
        return (blue & inside & on).astype(float)

    return cover


def checker(z0: float, z1: float, around: int, cell_z: float, min_r: float) -> Cover:
    """The docking sphere's and forward body's finer blue and grey checkerboard, square-ish cells round the axis."""

    def cover(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        a = np.floor(_turn(p) / (2.0 * math.pi / around)).astype(np.int64)
        b = np.floor((p[:, 2] - z0) / cell_z).astype(np.int64)
        on = (p[:, 2] >= z0) & (p[:, 2] <= z1) & (np.hypot(p[:, 0], p[:, 1]) > min_r)
        return (((a + b) % 2 == 0) & on).astype(float)

    return cover


def green_blocks(joints: tuple[float, ...], radius: float, around: int, seed: int) -> Cover:
    """The green zone: grey strips along the axis with blue blocks between them, two blocks to each section between the seam
    rings, lined up round the girth so they read as rings of panels; a few left grey."""
    sector = 2.0 * math.pi * radius / around
    half_across = 0.33 * sector
    edges = np.asarray(joints, dtype=float)
    gap = 12.0

    def cover(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        s = _turn(p) * radius
        k = np.floor(s / sector).astype(np.int64)
        across = np.abs(np.mod(s, sector) - 0.5 * sector)
        z = p[:, 2]
        j = np.clip(np.searchsorted(edges, z) - 1, 0, len(edges) - 2)
        z0, z1 = edges[j], edges[j + 1]
        mid = 0.5 * (z0 + z1)
        half = np.where(z < mid, 0, 1)
        in_block = ((z > z0 + gap) & (z < mid - 0.5 * gap)) | ((z > mid + 0.5 * gap) & (z < z1 - gap))
        keep = _hash01(np.mod(k, around), 2 * j + half, np.full(len(p), seed, dtype=np.int64)) < 0.85
        on = (z > edges[0]) & (z < edges[-1]) & (_radial(p, n) > 0.6) & (np.hypot(p[:, 0], p[:, 1]) < radius + 4.0)
        return ((across < half_across) & in_block & keep & on).astype(float)

    return cover


def _arm_local(p: np.ndarray, n: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Points and normals turned into the frame of the nearest Cobra arm, as if it stood on top (+y)."""
    turn = np.round((_turn(p) - 0.5 * math.pi) / (0.5 * math.pi))
    a = -turn * 0.5 * math.pi
    c, s = np.cos(a), np.sin(a)
    q = np.column_stack([c * p[:, 0] - s * p[:, 1], s * p[:, 0] + c * p[:, 1], p[:, 2]])
    m = np.column_stack([c * n[:, 0] - s * n[:, 1], s * n[:, 0] + c * n[:, 1], n[:, 2]])
    return q, m


def _arm_half_width(z: np.ndarray) -> np.ndarray:
    zs = [r[0] for r in st.ARM_HEAD] + [st.ARM_HATCH[1]]
    ws = [r[1] for r in st.ARM_HEAD] + [st.ARM_HATCH[2]]
    return np.interp(z, zs, ws)


ARM_TRIM_M = 9.0


def arm_trim(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """Red stripes along both edges of each Cobra arm's head."""
    q, m = _arm_local(p, n)
    outer = m[:, 1] > 0.6
    edge = np.abs(q[:, 0]) > _arm_half_width(q[:, 2]) - ARM_TRIM_M
    return (outer & edge & (q[:, 2] > 640.0) & (q[:, 2] < st.ARM_HATCH[0])).astype(float)


def hall_dark(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """The launch halls under the doors, dark inside (M7-T05): the upper hall between the chamfers and the lower hall under it."""
    q, m = _arm_local(p, n)
    floor, upper, ceiling = st.ARM_HATCH[4] - st.DOOR_DEPTH, st.HALL_UPPER_R, st.HALL_CEILING_R
    x0, x1, z0, z1 = st.LAUNCH_HALL
    along = (q[:, 2] > z0 - 0.05) & (q[:, 2] < z1 + 0.05)
    upper_hall = (q[:, 0] > x0 - 0.05) & (q[:, 0] < x1 + 0.05) & (q[:, 1] > upper - 0.05) & (q[:, 1] < floor + 0.05)
    lower_hall = (np.abs(q[:, 0]) < st.HALL_LOWER_HALF + 0.05) & (q[:, 1] > ceiling - 0.05) & (q[:, 1] < upper + 0.05)
    return (along & (upper_hall | lower_hall)).astype(float)


DOOR_BORDER_M = 2.0  # the red border round each door on the deck
STRIP_FRAME_M = 4.0  # the darker strip framing the row of doors, beyond their borders


def _door_gap(q: np.ndarray) -> np.ndarray:
    """How far each point lies outside the nearest launch door's outline, across the deck."""
    centres = np.asarray(st.launch_door_centres())
    along = np.abs(q[:, 2][:, None] - centres[None, :]).min(axis=1) - st.LAUNCH_DOOR_HALF[1]
    across = np.abs(q[:, 0] - st.LAUNCH_STRIP_X) - st.LAUNCH_DOOR_HALF[0]
    return np.hypot(np.maximum(along, 0.0), np.maximum(across, 0.0))


def door_strip(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """The framed strip the doors sit in, darker than the deck round it (the arm model's strip)."""
    q, m = _arm_local(p, n)
    top = st.ARM_HATCH[4]
    z0, z1 = st.LAUNCH_ROW
    on = (np.abs(q[:, 0] - st.LAUNCH_STRIP_X) < st.LAUNCH_DOOR_HALF[0] + DOOR_BORDER_M + STRIP_FRAME_M) & (q[:, 2] > z0 - STRIP_FRAME_M) \
        & (q[:, 2] < z1 + STRIP_FRAME_M)
    return ((m[:, 1] > 0.6) & (q[:, 1] > top - 0.6) & on).astype(float)


def door_frame_red(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """A red border round each door on the deck."""
    q, m = _arm_local(p, n)
    top = st.ARM_HATCH[4]
    return ((m[:, 1] > 0.6) & (q[:, 1] > top - 0.6) & (_door_gap(q) < DOOR_BORDER_M)).astype(float)


def clamp_caps(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """Each door clamp's red cap seen from afar: painted on the deck under it, since the clamps are near-only props (M7-T19)."""
    q, m = _arm_local(p, n)
    top, edge = st.ARM_HATCH[4], st.LAUNCH_STRIP_X + st.LAUNCH_DOOR_HALF[0]
    centres = np.asarray(st.launch_door_centres())
    along = np.abs(q[:, 2][:, None] - centres[None, :]).min(axis=1)
    return ((m[:, 1] > 0.6) & (q[:, 1] > top - 0.6) & (q[:, 0] > edge + 1.5) & (q[:, 0] < edge + 5.0) & (along < 1.5)).astype(float)


RED_CROSS = (906.0, 984.0, 5.0)  # the framed panel on the neck's top: z from, z to, the cross's half width


def red_cross(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """The red cross on the panel along the top of each arm's ribbed neck."""
    q, m = _arm_local(p, n)
    z0, z1, half = RED_CROSS
    hw = (1.0 - st.ARM_CHAMFER) * _arm_half_width(q[:, 2]) - 3.0  # on the neck's top, between its creases
    on = (m[:, 1] > 0.5) & (q[:, 2] > z0) & (q[:, 2] < z1) & (np.abs(q[:, 0]) < hw) & (q[:, 1] > 250.0)
    return (on & ((np.abs(q[:, 0]) < half) | (np.abs(q[:, 2] - 0.5 * (z0 + z1)) < half))).astype(float)


def cross_frame(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """... and the darker frame round that panel."""
    q, m = _arm_local(p, n)
    z0, z1, _ = RED_CROSS
    hw = (1.0 - st.ARM_CHAMFER) * _arm_half_width(q[:, 2]) - 3.0
    inside = (q[:, 2] > z0) & (q[:, 2] < z1) & (np.abs(q[:, 0]) < hw)
    edge = (q[:, 2] < z0 + 4.0) | (q[:, 2] > z1 - 4.0) | (np.abs(q[:, 0]) > hw - 4.0)
    return ((m[:, 1] > 0.5) & (q[:, 1] > 250.0) & inside & edge).astype(float)


def top_faces(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """The darker paint on the spine's and bow's upward faces."""
    return _smooth((n[:, 1] - 0.55) / 0.3)


def _vane_local(p: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    centres = np.asarray(st.VANE_Z)
    k = np.argmin(np.abs(p[:, 2][:, None] - centres[None, :]), axis=1)
    return p[:, 2] - centres[k], np.abs(p[:, 1])


VANE_FRAME_M = 24.0


def vane_frame(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """The grey edge frame round each blade."""
    u, v = _vane_local(p)
    ys = [y for y, _ in st.VANE_CHORD]
    cs = [c for _, c in st.VANE_CHORD]
    half = np.interp(v, ys, cs)
    return ((np.abs(u) > half - VANE_FRAME_M) | (v > st.VANE_TIP_Y - st.VANE_NOTCH[1] - VANE_FRAME_M) | (v < 160.0)).astype(float)


def vane_recesses(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """The pattern of small dark rectangles over the blades' blue."""
    u, v = _vane_local(p)
    cu, cv = 26.0, 18.0
    i, j = np.floor(u / cu).astype(np.int64), np.floor(v / cv).astype(np.int64)
    side = np.full(len(p), 61, dtype=np.int64) + (p[:, 0] > 0).astype(np.int64)
    pick = _hash01(i, j, side) < 0.45
    fu, fv = np.mod(u, cu) - 0.5 * cu, np.mod(v, cv) - 0.5 * cv
    w = 6.0 + 8.0 * _hash01(i, j, side + 5)
    return (pick & (np.abs(fu) < 0.5 * w) & (np.abs(fv) < 4.0)).astype(float)


def paint() -> dict[str, list[tuple[str, Cover]]]:
    """Each shape's base coats by name: (the colour's role, where it covers)."""
    return {
        "sphere": [("drum_blue", checker(575.0, 935.0, 32, 52.0, 160.0))],
        "fwd_body": [("drum_blue", checker(1340.0, 1680.0, 36, 56.0, 250.0))],
        "fwd_band": [("drum_blue", band_blocks(1800.0, 2290.0, st.BAND_R, 12, 3, 26.0, 7.0, 71))],
        "green": [("drum_blue", green_blocks(GREEN_JOINTS, st.GREEN_R, 20, 73))],
        "aft_band": [("drum_blue", band_blocks(4840.0, 5400.0, st.BAND_R, 12, 3, 26.0, 7.0, 79))],
        "arms": [("trim", arm_trim), ("recess", hall_dark), ("recess", door_strip), ("trim", door_frame_red), ("trim", clamp_caps), ("recess", cross_frame), ("trim", red_cross)],
        "bow": [("spine_top", top_faces)],
        "spine": [("spine_top", top_faces)],
        "hub": [("spine_top", top_faces)],
        "fins": [("spine_top", top_faces)],
        "vanes": [("vane_frame", vane_frame), ("vane_dark", vane_recesses)],
    }


def paint_markings(part: str, shift: np.ndarray) -> tuple[Marking, ...]:
    """The shape's paint as markings in its piece's frame (``shift``: where the piece's origin sits in the station frame)."""
    out = []
    for role, cover in paint().get(part, []):
        out.append(Marking.paint(part, colour(role), (lambda f: lambda p, n: f(np.asarray(p) + shift, n))(cover)))
    return tuple(out)


# --- windows (Q10) ---------------------------------------------------------------------------------------------------
WINDOW = (7.0, 3.5)  # round, along
WINDOW_PITCH = (14.0, 9.0)
WINDOW_ROWS: dict[str, tuple[tuple[float, float], ...]] = {  # part: (centre along the axis, row height) of each ring of windows
    "sphere": ((660.0, 9.0), (735.0, 9.0), (860.0, 9.0)),
    "fwd_body": ((1440.0, 9.0), (1600.0, 9.0)),
    "fwd_band": ((1860.0, 18.0), (2045.0, 18.0), (2230.0, 18.0)),
    "green": tuple((z, 9.0) for z in every(2420.0, 4700.0, 380.0)),
    "aft_band": ((4900.0, 18.0), (5120.0, 18.0), (5340.0, 18.0)),
}


def window_markings(part: str, shift: np.ndarray) -> tuple[Marking, ...]:
    """The shape's lit windows, in its piece's frame (the doors' numbers are on their leaves, near-field props)."""
    glow = lin(WINDOW_GLOW)
    out = [Marking.window_rings(part, tuple(-shift), (0.0, 0.0, 1.0), z, h, WINDOW_PITCH, WINDOW, glow, WINDOW_STRENGTH, lit=0.55)
           for z, h in WINDOW_ROWS.get(part, ())]
    if part == "spine":  # the command section's windows: on both sloped flanks of its beam and along the body's sides before it
        from . import station_spine as ssp  # noqa: PLC0415

        (xt, yt), (xe, ye) = (ssp.BEAM_TOP_X, ssp.BEAM_TOP), ssp.BEAM_EDGE
        for sx in (-1.0, 1.0):
            centre = np.array([sx * 0.5 * (xt + xe), 0.5 * (yt + ye), 1140.0]) - shift
            up, facing = (sx * (xt - xe), yt - ye, 0.0), (sx * (yt - ye), xe - xt, 0.0)
            out.append(Marking.windows(part, tuple(centre), (0.0, 0.0, 1.0), up, facing, (280.0, 80.0), (11.0, 9.0), (6.0, 3.0), glow,
                                       WINDOW_STRENGTH, lit=0.6))
            centre = np.array([sx * 97.0, 382.0, 790.0]) - shift
            out.append(Marking.windows(part, tuple(centre), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (sx, 0.0, 0.0), (180.0, 20.0),
                                       (11.0, 9.0), (6.0, 3.0), glow, WINDOW_STRENGTH, lit=0.6))
    return tuple(out)


__all__ = ["layouts", "paint", "paint_markings", "window_markings"]
