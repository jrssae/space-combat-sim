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
from . import station_detail as sd

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
    return {
        "sphere": SeamLayout.of([*_barrel(560.0, 945.0, 270.0, 46.0, 36, 3, (700.0, 800.0, 900.0)),
                                 Cut(axis=2, at=540.0, level=1, width=1.4)]),
        # The narrow stretches' plates run along the axis in columns lined up with the paint's (M7-T24: the station from below).
        "fwd_body": SeamLayout.of(_barrel(1330.0, 1692.0, 320.0, 120.0, 32, 5)),
        "fwd_band": SeamLayout.of(_barrel(1790.0, 2340.0, st.BAND_R, 61.25, 48, 7, band_joints)),
        "green": SeamLayout.of(_barrel(2348.0, 4782.0, st.GREEN_R, 160.0, 32, 11, (st.GREEN_BAND[0], st.GREEN_BAND[1]))),
        "aft_band": SeamLayout.of(_barrel(4782.0, 5500.0, st.BAND_R, 70.0, 48, 13, aft_joints)),
        "arms": SeamLayout.of(_faceted((30.0, 16.0), 17)),
        "aperture": SeamLayout.of([Plates(level=2, wrap="polar", axis=2, radius=105.0, around=32, cell=(19.0, 0.0), offset=(88.0, 0.0),
                                          splits=0, min_m=6.0, tone=0.06, sheen=PLATE_SHEEN, depth=0.9, dark=0.75, seed=83,
                                          lo=(-math.inf, -math.inf, sd.FACE_Z - 1.0), hi=(math.inf, math.inf, sd.FACE_Z + 1.0))]),
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


SPHERE_STRIPS = (8, 9.0)  # grey strips from pole to pole: how many, how wide
SPHERE_GIRTHS = ((700.0, 10.0), (830.0, 10.0))  # grey strips round the sphere: where along the axis, how wide
SPHERE_CHECKER = (870.0, 940.0, 48, 23.0)  # the small grey and blue checker toward its aft end: from z, to z, cells round, cell along


def sphere_blue(min_r: float) -> Cover:
    """The docking sphere (M7-T24, the side reference): blue panels between grey strips from pole to pole and round its girth, and a
    band of small grey and blue checker toward the aft end."""
    count, strip = SPHERE_STRIPS
    z0, z1, around, cell = SPHERE_CHECKER

    def cover(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        r = np.hypot(p[:, 0], p[:, 1])
        turn = _turn(p)
        meridian = np.abs(np.mod(turn * r, 2.0 * math.pi * r / count) - 0.5 * 2.0 * math.pi * r / count) > 0.5 * 2.0 * math.pi * r / count - 0.5 * strip
        girth = np.zeros(len(p), dtype=bool)
        for at, width in SPHERE_GIRTHS:
            girth |= np.abs(p[:, 2] - at) < 0.5 * width
        band = (p[:, 2] > z0) & (p[:, 2] < z1)
        a = np.floor(turn / (2.0 * math.pi / around)).astype(np.int64)
        b = np.floor((p[:, 2] - z0) / cell).astype(np.int64)
        checker_grey = band & ((a + b) % 2 == 1)
        on = (r > min_r) & (_radial(p, n) > -0.2)
        return (on & ~meridian & ~girth & ~checker_grey).astype(float)

    return cover



def _collar_place(angle: float, z: float) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """A point on the sphere's skin at ``angle`` round the axis and ``z`` along it: the point, the girth's direction, the meridian's
    (aft along the skin) and the outward normal (station frame)."""
    zs = np.array([z_ for z_, _ in st.SPHERE_PROFILE if z_ >= 560.0])
    rs = np.array([r for z_, r in st.SPHERE_PROFILE if z_ >= 560.0])
    r = float(np.interp(z, zs, rs))
    slope = float(np.interp(z + 5.0, zs, rs) - np.interp(z - 5.0, zs, rs)) / 10.0
    radial = np.array([math.cos(angle), math.sin(angle), 0.0])
    along = radial * slope + np.array([0.0, 0.0, 1.0])
    normal = radial - slope * np.array([0.0, 0.0, 1.0])
    return (radial * r + np.array([0.0, 0.0, z]), np.array([-math.sin(angle), math.cos(angle), 0.0]), along / np.linalg.norm(along),
            normal / np.linalg.norm(normal))


def collar_panels() -> list[tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]]:
    """The sphere's window panels (M7-T24, the from-below reference): one broken ring just aft of the grey collar, each panel long
    round the girth: (middle, girth, meridian, normal)."""
    count, z = COLLAR_RING
    return [_collar_place(2.0 * math.pi * (k + 0.5) / count, z) for k in range(count)]


def collar_strips() -> list[tuple[float, float]]:
    """The unlit tech strips out from the collar along the meridians, in the gaps between panels that hold no grey strip: (angle,
    z from)."""
    count, z = COLLAR_RING
    meridian = 2.0 * math.pi / SPHERE_STRIPS[0]
    out = []
    for k in range(count):
        a = 2.0 * math.pi * k / count
        if abs((a + 0.5 * meridian) % meridian - 0.5 * meridian) > 1e-6:
            out.append((a, z))
    return out


def collar_dark(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """The panels' and the tech strips' dark paint."""
    length, width = COLLAR_PANEL
    out = np.zeros(len(p), dtype=bool)
    for centre, girth, along, normal in collar_panels():
        d = p - centre
        out |= (np.abs(d @ girth) < 0.5 * length) & (np.abs(d @ along) < 0.5 * width) & (n @ normal > 0.5) & (np.abs(d @ normal) < 6.0)
    r = np.hypot(p[:, 0], p[:, 1])
    turn = _turn(p)
    for a, z0 in collar_strips():
        across = np.abs((turn - a + math.pi) % (2.0 * math.pi) - math.pi) * r
        out |= (across < 0.5 * STRIP_W_M) & (p[:, 2] > z0 - 2.0) & (p[:, 2] < z0 + STRIP_LEN_Z) & (_radial(p, n) > -0.2) & (r > 160.0)
    return out.astype(float)


def collar_greebles(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """The small grey marks along the tech strips."""
    r = np.hypot(p[:, 0], p[:, 1])
    turn = _turn(p)
    out = np.zeros(len(p), dtype=bool)
    for a, z0 in collar_strips():
        across = (turn - a + math.pi) % (2.0 * math.pi) - math.pi
        along = p[:, 2] - z0
        beat = np.mod(along, GREEBLE_PITCH_M) < GREEBLE_PITCH_M * 0.45
        side = np.abs(across * r - np.where(np.mod(np.floor(along / GREEBLE_PITCH_M), 2) == 0, -1.0, 1.0)) < 1.0
        out |= side & beat & (along > 4.0) & (along < STRIP_LEN_Z - 4.0) & (np.abs(across * r) < 0.5 * STRIP_W_M) & (r > 160.0)
    return out.astype(float)


# --- the drum's main body (M7-T24, read off "B5 - Station from below", the schematic and the STL) ----------------------------
# The narrow stretches (the forward body, the green zone either side of its middle band) are deep blue with large grey plates in
# staggered columns along the axis; dark bars carrying a row of lights run lengthwise on the eight stringers, in staggered segments.
# The wide bands are grey rims panelled round the girth with a blue middle; small white lights are scattered sparsely over all.
NARROW_SECTORS = 8  # the stringers' sectors (every 45 degrees, from the side)
NARROW_COLUMNS = 2  # columns of grey plates in a sector
PLATE_LEN_M = (100.0, 210.0)
PLATE_GAP_M = 24.0
PLATE_MARGIN_M = 16.0  # blue each side of a plate, across its column
PLATE_SKIP = 0.28  # the share of plates left blue
DASH_SHARE = 0.25  # plates with a thin blue dashed line down their middle
DASH_M = (12.0, 8.0, 2.5)  # a dash, the gap, the line's width
NARROW_STRETCHES = ((1350.0, 1688.0), (2352.0, st.GREEN_BAND[0]), (st.GREEN_BAND[1], 4778.0))
MIDDLE_RIM_M = 32.0  # the grey rims at the ends of the green zone's middle band
BAND_RIM_SHARE = 0.24  # how much of a wide band each grey rim takes
BAND_NOTCH_M = (52.0, 13.0)  # the rim's inner edge steps: across, along
BAND_LINE_M = (30.0, 8.0)  # the blue line round each rim: in from the band's edge, wide


def _plate_runs(z0: float, z1: float, column: int, seed: int) -> tuple[np.ndarray, np.ndarray]:
    """One column's grey plates along a stretch, staggered against its neighbours: their starts and ends."""
    starts, ends = [], []
    z = z0 + PLATE_GAP_M + 0.5 * PLATE_LEN_M[0] * float(_hash01(np.array([column]), np.array([seed]))[0])
    k = 0
    while z < z1 - PLATE_GAP_M - 30.0:
        h = float(_hash01(np.array([column]), np.array([k]), np.array([seed + 3]))[0])
        length = PLATE_LEN_M[0] + (PLATE_LEN_M[1] - PLATE_LEN_M[0]) * h
        end = min(z + length, z1 - PLATE_GAP_M)
        if float(_hash01(np.array([column]), np.array([k]), np.array([seed + 5]))[0]) >= PLATE_SKIP:
            starts.append(z)
            ends.append(end)
        z = end + PLATE_GAP_M
        k += 1
    return np.array(starts), np.array(ends)


def narrow_blue(radius: float, seed: int, stretches: tuple[tuple[float, float], ...] = NARROW_STRETCHES) -> Cover:
    """A narrow stretch's blue: all of it but its grey plates, with a thin blue dashed line down some plates."""
    columns = NARROW_SECTORS * NARROW_COLUMNS
    width = 2.0 * math.pi * radius / columns
    runs = {(i, c): _plate_runs(z0, z1, c, seed + 17 * i) for i, (z0, z1) in enumerate(stretches) for c in range(columns)}

    def cover(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        s = _turn(p) * radius
        col = np.mod(np.floor(s / width).astype(np.int64), columns)
        across = np.mod(s, width)
        z = p[:, 2]
        plate = np.zeros(len(p), dtype=bool)
        dash = np.zeros(len(p), dtype=bool)
        on = np.zeros(len(p), dtype=bool)
        for i, (z0, z1) in enumerate(stretches):
            inside = (z >= z0) & (z <= z1)
            on |= inside
            for c in range(columns):
                sel = np.flatnonzero(inside & (col == c))
                if len(sel) == 0:
                    continue
                starts, ends = runs[(i, c)]
                if len(starts) == 0:  # a column left all blue
                    continue
                k = np.searchsorted(starts, z[sel], side="right") - 1
                ok = (k >= 0) & (z[sel] <= ends[np.maximum(k, 0)])
                plate[sel] = ok & (across[sel] > PLATE_MARGIN_M) & (across[sel] < width - PLATE_MARGIN_M)
                dashed = _hash01(np.full(len(sel), c), np.maximum(k, 0), np.full(len(sel), seed + 29 * i)) < DASH_SHARE
                line = np.abs(across[sel] - 0.5 * width) < 0.5 * DASH_M[2]
                beat = np.mod(z[sel] - starts[np.maximum(k, 0)], DASH_M[0] + DASH_M[1]) < DASH_M[0]
                dash[sel] = plate[sel] & dashed & line & beat
        outward = (_radial(p, n) > 0.6) & (np.hypot(p[:, 0], p[:, 1]) < radius + 4.0)
        return (on & outward & (~plate | dash)).astype(float)

    return cover


def middle_band_blue(z0: float, z1: float, radius: float) -> Cover:
    """The green zone's middle band: blue between two grey rims."""
    def cover(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        z = p[:, 2]
        on = (z > z0 + MIDDLE_RIM_M) & (z < z1 - MIDDLE_RIM_M) & (np.hypot(p[:, 0], p[:, 1]) > radius - 4.0)
        return (on & (_radial(p, n) > 0.6)).astype(float)

    return cover


def wide_band_blue(z0: float, z1: float, radius: float) -> Cover:
    """A wide band's blue middle between its grey rims, the rims' inner edges stepping in and out so they interlock with it, and a
    blue line round each rim."""
    rim = BAND_RIM_SHARE * (z1 - z0)
    steps = np.asarray(STEPS) * BAND_NOTCH_M[1]

    def cover(p: np.ndarray, n: np.ndarray) -> np.ndarray:
        s = _turn(p) * radius
        z = p[:, 2]
        step = steps[np.mod(np.floor(s / BAND_NOTCH_M[0]).astype(np.int64), len(steps))]
        middle = (z > z0 + rim + step) & (z < z1 - rim - step)
        edge = np.minimum(z - z0, z1 - z)
        line = np.abs(edge - BAND_LINE_M[0]) < 0.5 * BAND_LINE_M[1]
        on = (z >= z0) & (z <= z1) & (_radial(p, n) > 0.6) & (np.hypot(p[:, 0], p[:, 1]) > radius - 6.0)
        return (on & (middle | line)).astype(float)

    return cover


BAR_END_M = 6.0  # where a bar stops short of its stringer's ends
# A light (along, across) and its pitch along and across the bar: about one every 1.7 stringer widths, as the references. Across, the
# cells are narrower than a light, so one unbroken row lies on the bar's centreline whatever the cells' phase; the bar's region (4 m
# across) sets the row's width.
BAR_LIGHT = ((4.0, 8.0), (26.0, 4.0))
BAR_ROW_M = 4.0


def stringer_bars() -> list[tuple[float, float, float]]:
    """The dark lit bars on the stringers: (angle in degrees, from z, to z), one unbroken straight line of windows down each
    stringer the length of each green-zone run (the maintainer, M7-T24: the side and from-below references)."""
    runs = ((2360.0, st.GREEN_BAND[0] - 12.0), (st.GREEN_BAND[1] + 12.0, 4770.0))
    return [(angle, z0 + BAR_END_M, z1 - BAR_END_M) for angle in st.STRINGER_ANGLES_DEG for z0, z1 in runs]

def stringer_dark(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """The bars' dark paint on the stringers."""
    angle = np.degrees(np.arctan2(p[:, 1], p[:, 0])) % 360.0
    out = np.zeros(len(p), dtype=bool)
    for a, z0, z1 in stringer_bars():
        near = np.abs((angle - a + 180.0) % 360.0 - 180.0) < 4.0
        out |= near & (p[:, 2] >= z0) & (p[:, 2] <= z1)
    return out.astype(float)


BAR_HULL_HALF_M = 12.0  # each bar's dark band on the hull beside its stringer, half across


def bar_band(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """The dark band each lit bar lays on the green zone's hull either side of its stringer, so the bars read from afar."""
    angle = np.arctan2(p[:, 1], p[:, 0])
    r = np.hypot(p[:, 0], p[:, 1])
    out = np.zeros(len(p), dtype=bool)
    for a, z0, z1 in stringer_bars():
        arc = np.abs((angle - math.radians(a) + math.pi) % (2.0 * math.pi) - math.pi) * r
        out |= (arc < BAR_HULL_HALF_M) & (p[:, 2] >= z0) & (p[:, 2] <= z1)
    return (out & (_radial(p, n) > 0.6)).astype(float)


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


def arm_outside(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """All of a Cobra arm: its own darker grey (the halls, strips and trim are painted over it)."""
    return np.ones(len(p))


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


# --- inside or outside ---------------------------------------------------------------------------------------------------
# No light in the game casts shadows, so the sun would light a hall's walls as it does the hull. The faces inside the station's
# closed spaces are told apart here and drawn out of the sun's light (the game's interior layer): lit by lamps, glow and ambient.
INSIDE_EPS_M = 0.05


def drum_interior(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """Which of the drum's faces (centroids ``p`` and normals ``n``, station frame) lie inside: the Cobra arms' launch halls, the
    doors' wells with their lit sills, the halls' end walls, and the main docking bay from its mouth through the doors' slab to the
    void's back wall."""
    e = INSIDE_EPS_M
    q, m = _arm_local(p, n)
    top = st.ARM_HATCH[4]
    floor = top - st.DOOR_DEPTH
    _, _, z0, z1 = st.LAUNCH_HALL
    cx, (dx, dz) = st.LAUNCH_STRIP_X, st.LAUNCH_DOOR_HALF
    in_door = np.zeros(len(q), dtype=bool)
    for c in st.launch_door_centres():
        in_door |= np.abs(q[:, 2] - c) < dz + e
    well = in_door & (np.abs(q[:, 0] - cx) < dx + e) & (q[:, 1] > floor - e) & (q[:, 1] < top - e)
    # The root's sections fore and aft end on the halls: those faces are the halls' end walls, or hidden against the next part.
    ends = ((np.abs(q[:, 2] - z0) < e) | (np.abs(q[:, 2] - z1) < e)) & (np.abs(m[:, 2]) > 0.9)
    ends &= (np.abs(q[:, 0]) < st.ARM_HATCH[2] + e) & (q[:, 1] > st.HALL_CEILING_R - e) & (q[:, 1] < top - e)
    return (hall_dark(p, n) > 0.0) | well | ends | bay_interior(p)


def bay_interior(p: np.ndarray) -> np.ndarray:
    """Which points lie inside the main docking bay: within the mouth's set-back walls from just inside the face to the doors, and
    within the void behind them."""
    e = INSIDE_EPS_M
    grown = sd.offset(sd.opening(), sd.RECESS_M + e)
    mouth = (p[:, 2] > sd.FACE_Z + e) & (p[:, 2] < sd.DOORS_Z + sd.DOOR_SLAB_M + e)
    for i in np.flatnonzero(mouth):
        mouth[i] = sd.contains(grown, float(p[i, 0]), float(p[i, 1]))
    hx, hy = sd.VOID_HALF
    void = (np.abs(p[:, 0]) < hx + e) & (np.abs(p[:, 1]) < hy + e) & (p[:, 2] > sd.DOORS_Z + sd.DOOR_SLAB_M - e) & (p[:, 2] < sd.VOID_BACK_Z + e)
    return mouth | void


def frame_interior(p: np.ndarray, n: np.ndarray) -> np.ndarray:
    """Which of the frame's faces lie inside: the cargo bay's throat and compartment, and the walls across their ends."""
    e = INSIDE_EPS_M
    throat = (p[:, 2] > sd.ZG_FRONT_Z + e) & (p[:, 2] < sd.ZG_COMPARTMENT_Z + e) & (np.abs(p[:, 0]) < sd.ZG_THROAT[0] + e)
    throat &= (p[:, 1] > sd.ZG_THROAT_Y[0] - e) & (p[:, 1] < sd.ZG_THROAT_Y[1] + e)
    room = (p[:, 2] > sd.ZG_COMPARTMENT_Z - e) & (p[:, 2] < sd.ZG_BACK_Z + e) & (np.abs(p[:, 0]) < sd.ZG_HALF_X + e)
    room &= (p[:, 1] > sd.ZG_FLOOR_Y - e) & (p[:, 1] < sd.ZG_ROOF_Y + e)
    ends = ((np.abs(p[:, 2] - sd.ZG_COMPARTMENT_Z) < e) | (np.abs(p[:, 2] - sd.ZG_BACK_Z) < e)) & (np.abs(n[:, 2]) > 0.9)
    ends &= (np.abs(p[:, 0]) < sd.ZG_HALF_X + 12.0) & (p[:, 1] > sd.ZG_FLOOR_Y - 40.0) & (p[:, 1] < sd.ZG_ROOF_Y + 40.0)
    return throat | room | ends


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


def paint() -> dict[str, list[tuple[str, Cover]]]:
    """Each shape's base coats by name: (the colour's role, where it covers)."""
    return {
        "sphere": [("drum_blue", sphere_blue(160.0)), ("recess", collar_dark), ("drum_grey", collar_greebles)],
        "fwd_body": [("drum_blue", narrow_blue(320.0, 61, NARROW_STRETCHES[:1]))],
        "fwd_band": [("drum_blue", wide_band_blue(1800.0, 2290.0, st.BAND_R))],
        "green": [("drum_blue", narrow_blue(st.GREEN_R, 73, NARROW_STRETCHES[1:])),
                  ("drum_blue", middle_band_blue(st.GREEN_BAND[0], st.GREEN_BAND[1], st.GREEN_BAND[2])), ("recess", bar_band)],
        "aft_band": [("drum_blue", wide_band_blue(4840.0, 5400.0, st.BAND_R))],
        "stringers": [("recess", stringer_dark)],
        "arms": [("arm_grey", arm_outside), ("trim", arm_trim), ("recess", hall_dark), ("recess", door_strip), ("trim", door_frame_red), ("trim", clamp_caps), ("recess", cross_frame), ("trim", red_cross)],
        "bow": [("spine_top", top_faces)],
        "spine": [("spine_top", top_faces)],
        "hub": [("spine_top", top_faces)],
        "fins": [("spine_top", top_faces)],
        # The blades are plain blue in a grey frame: no dark marks (the maintainer, M7-T24: the show has none).
        "vanes": [("vane_frame", vane_frame)],
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
WINDOW_ROWS: dict[str, tuple[tuple[float, float], ...]] = {}  # part: (centre along the axis, row height) of each ring of windows
# The sphere's windows (M7-T24, the from-below reference): one broken ring of dark panels just aft of the grey collar, each long round
# the girth and densely studded with small lights in two rows; between them, unlit tech strips run aft along the meridians.
COLLAR_RING = (16, 594.0)  # panels round, z of their middles (just aft of the collar's edge)
COLLAR_PANEL = (44.0, 9.0)  # a panel's length round the girth, its width
COLLAR_LIGHT = ((0.8, 0.8), (2.6, 2.6), 5.2)  # a light, its pitch (round, across) and the rows' band: two rows of small points
COLLAR_STRENGTH = 0.8  # of the bars' glow: many small points, not a lit strip
STRIP_W_M = 6.0
STRIP_LEN_Z = 110.0  # how far aft a tech strip runs from the collar
GREEBLE_PITCH_M = 8.0
# The main body has no window rings (M7-T24): its lights run along the axis, one regular row down each stringer's bar, and the wide
# bands' blue carries short rows of dark windows. Nothing is scattered at random (the maintainer: it read as polka dots).
POINT_GLOW = 0xF4F6FF
BODY_SPANS = {"sphere": (575.0, 935.0), "fwd_body": (1350.0, 1688.0), "fwd_band": (1800.0, 2290.0), "green": (2352.0, 4778.0),
              "aft_band": (4840.0, 5400.0)}
BAND_DASHES = (24, 0.5, (6.0, 2.5), (10.0, 9.0), (4, 7), 0.0)  # places round, share used, a window, the pitch, windows a row, lit (dark)
BAR_STRENGTH = 1.4


def _lengthwise_windows(part: str, shift: np.ndarray, glow: tuple[float, float, float]) -> list[Marking]:
    """The main body's lights along the axis: an unbroken, evenly spaced row down each stringer's bar, short rows of dark windows on
    the wide bands' blue, and the sphere's ring of densely lit panels round its collar."""
    out: list[Marking] = []
    if part == "stringers":
        r = st.STRINGER[2]
        (lw, pitch) = BAR_LIGHT
        for a, z0, z1 in stringer_bars():
            c, s_ = math.cos(math.radians(a)), math.sin(math.radians(a))
            centre = np.array([r * c, r * s_, 0.5 * (z0 + z1)]) - shift
            out.append(Marking.windows(part, tuple(centre), (0.0, 0.0, 1.0), (-s_, c, 0.0), (c, s_, 0.0), (z1 - z0 - 6.0, BAR_ROW_M), pitch, lw,
                                       lin(POINT_GLOW), BAR_STRENGTH * WINDOW_STRENGTH, lit=1.0))
    if part in ("fwd_band", "aft_band"):
        z0, z1 = BODY_SPANS[part]
        places, used, window, pitch, (lo, hi), lit = BAND_DASHES
        rim = BAND_RIM_SHARE * (z1 - z0)
        for k in range(places):
            h = _hash01(np.array([k]), np.array([len(part)]), np.array([211]))
            if float(h[0]) >= used:
                continue
            a = 2.0 * math.pi * (k + 0.5) / places
            count = lo + int(float(_hash01(np.array([k]), np.array([223]))[0]) * (hi - lo + 1))
            length = count * pitch[0]
            zc = z0 + rim + 30.0 + 0.5 * length + float(_hash01(np.array([k]), np.array([227]))[0]) * max(z1 - z0 - 2.0 * rim - 60.0 - length, 0.0)
            c, s_ = math.cos(a), math.sin(a)
            centre = np.array([st.BAND_R * c, st.BAND_R * s_, zc]) - shift
            out.append(Marking.windows(part, tuple(centre), (0.0, 0.0, 1.0), (-s_, c, 0.0), (c, s_, 0.0), (length, 3.0), pitch, window,
                                       glow, WINDOW_STRENGTH, lit=lit))
    if part == "sphere":
        light, pitch, band = COLLAR_LIGHT
        for centre, girth, along, normal in collar_panels():
            out.append(Marking.windows(part, tuple(centre - shift), tuple(girth), tuple(along), tuple(normal), (COLLAR_PANEL[0] - 3.0, band),
                                       pitch, light, lin(POINT_GLOW), COLLAR_STRENGTH * BAR_STRENGTH * WINDOW_STRENGTH, lit=1.0))
    return out


def window_markings(part: str, shift: np.ndarray) -> tuple[Marking, ...]:
    """The shape's lit windows, in its piece's frame (the doors' numbers are on their leaves, near-field props). The spine and the
    command section have none: grey metal (the maintainer, M7-T24)."""
    glow = lin(WINDOW_GLOW)
    out = [Marking.window_rings(part, tuple(-shift), (0.0, 0.0, 1.0), z, h, WINDOW_PITCH, WINDOW, glow, WINDOW_STRENGTH, lit=0.55)
           for z, h in WINDOW_ROWS.get(part, ())]
    out += _lengthwise_windows(part, shift, glow)
    return tuple(out)


__all__ = ["layouts", "paint", "paint_markings", "window_markings"]
