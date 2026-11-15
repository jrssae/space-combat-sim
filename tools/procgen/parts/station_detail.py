"""The station's near-field detail (M7-T05): the main docking bay at the bow, the cargo bay (zero-gravity) between the bow's forks and the
defence grid's mount plinths.

The main docking bay (M7-T25) is the STL's (``references/EA Babylon 5 Station.stl``, docs/assets-station.md) with its frame block and
mouth scaled up so the mouth is 80 m wide (the maintainer's estimate, so T10's civilians fit), and the show's look
(``references/docking bay references/``; nothing traced). It turns with the drum: the cross housing over the disc at the STL's size,
the octagonal frame block with its grilles and marked panels, the fan-shaped grille housings beside it, the mouth (the STL's band
across a taller core) running straight back to the inner airlock, its grey walls set back between frames and lit red by lamps, and the sawtooth doors
(``station_props.py``, opened by the game) onto a black void where a docking ship leaves the world. The toothed ring round it stands
still (``station.py``).

Numbers are metres in the station frame of ``station.py`` (z aft from the bow tip). Outlines are lists of (x, y), counter-clockwise.
"""

from __future__ import annotations

import math
from collections.abc import Sequence

import numpy as np

from ..core.geometry import Material, Mesh, basis_from_z, lathe, planar_uv, unit
from . import station as st

Outline = list[tuple[float, float]]

# --- the main docking bay --------------------------------------------------------------------------------------------
# The STL's frame block and mouth, scaled about the axis and about the block's face so the mouth is 80 m wide (the STL's is 45 m at the
# 8 km scale): the maintainer's choice, so the tunnel hulls fit (the ring and the cross housing keep the STL's size).
BAY_SCALE = 80.0 / 45.0
FACE_Z = 480.4  # the block's and the housing's face (the STL's)
STL_OCTAGON = ((47.5, 0.0), (47.5, 13.4), (31.25, 25.5), (0.0, 25.5))  # the block's outline, first quadrant, STL size
STL_OPENING = ((20.6, 0.0), (19.25, 4.7), (12.8, 4.7), (11.2, 8.45), (0.0, 8.45))  # the mouth's clear outline, STL size
STL_DEPTH_M = 40.5  # the block's face to the STL's back wall (the inner airlock)
DOORS_Z = FACE_Z + STL_DEPTH_M * BAY_SCALE  # the inner airlock's doors
BLOCK_BACK_Z = 516.0  # the block's walls end inside the drum
RIM = (2.8, 0.9)  # the raised rim round the block's face: width, height
# The mouth: a lip at the face, then walls set back round the clear outline, with frames standing in to it (lit red, dimmer deeper).
LIP_M = 3.0
RECESS_M = 2.0
FRAME_M = 2.5
FRAME_Z = tuple(FACE_Z + LIP_M + 9.0 + 12.5 * k for k in range(5))
RIB = (0.35, 0.8)  # the ribs round the set-back walls between the frames: how far they stand in, how long along the axis
# The inner airlock: the doors slide up and down into a slab between the mouth's back wall and the void's front wall.
DOOR_SLAB_M = 2.0
DOOR_LEAF = (0.5, 1.5, 1.5, 2.0)  # a leaf's front and back behind the doors' plane, how far it reaches past the outline across and up
DOOR_OPEN_M = 21.0  # how far each leaf slides to clear the opening
SAW = (10.0, 20.5, 0.3)  # the seam's teeth: height, period, the gap between the leaves
# The void behind the doors: black, sealed, deep enough for the longest tunnel hull to lie wholly behind the doors with room ahead of
# it for one that brakes late (the docking lane ends 145 m short of the back wall, ``DockingPlan``).
VOID_HALF = (42.0, 22.0)
VOID_BACK_Z = 740.0
# The cross housing at the STL's size: the bar across (half height, its end) and the bars up and down, their ends 5 m inside the
# ring's bore so the drum turns clear (``station.DRUM_FRONT_R``; the STL's reach the ring).
HOUSING = (13.25, 102.5)
BAR = ((45.3, 18.3, 488.5), (102.3, 14.6, 492.0))  # (|y|, half width, face z) at the block's top and at the bar's end
BAR_BACK_Z = 515.0
BAR_BOXES = (52.0, 68.0, 84.0, 98.0)  # the boxes along each bar's sides
# The fan-shaped grille housings beside the block (STL: x 37 to 58.2, half height 11.3 to 5.6, front z 449 to 471), scaled with it.
# Its sections as scaled (x, half height, front z), read off the scaled STL: chamfered at the inner end, tallest just out from it,
# narrowing and standing further forward to the outer end.
FAN = ((65.8, 13.0, 471.5), (70.0, 19.7, 465.7), (90.0, 11.3, 440.5), (102.5, 8.9, 424.0))
STL_FAN_RAILS = (24.3, 37.0, 1.6, 2.7, 477.4)  # two rails from the mouth's side to the fan: x from, x to, |y| from, to, front z
HOUSING_POSTS = (98.0, 100.4, 17.2, 23.8, 481.0)  # posts beside the bar across, near its ends: x from, to, |y| from, to, front z
# The block's face (STL size): the slats over and under the mouth, the short ones beside it, the marked panels at its corners and the
# notches at its top and bottom.
STL_SLATS = (11.6, 9.2, 14.0, 12)  # half span, y from, y to, count
STL_SIDE_SLATS = (21.0, 23.5, 5.0, 7.6)  # x from, x to, y from, y to
STL_PANEL = (13.25, 21.4, 10.75, 14.5)
STL_NOTCH = (5.0, 22.6)  # half width, y from (to the rim)


def scaled(points: Sequence[tuple[float, float]]) -> Outline:
    return [(BAY_SCALE * x, BAY_SCALE * y) for x, y in points]


def scaled_z(z: float) -> float:
    """An STL depth moved by the block's scale about its face."""
    return FACE_Z + (z - FACE_Z) * BAY_SCALE


def full_outline(first_quadrant: Sequence[tuple[float, float]]) -> Outline:
    """A shape symmetric about both axes from its first quadrant (from the +x axis round to the +y axis), counter-clockwise."""
    q1 = list(first_quadrant)
    q2 = [(-x, y) for x, y in reversed(q1)]
    q3 = [(-x, -y) for x, y in q1]
    q4 = [(x, -y) for x, y in reversed(q1)]
    out = q1 + q2[1:] + q3[1:] + q4[1:-1]
    return [p for i, p in enumerate(out) if i == 0 or (abs(p[0] - out[i - 1][0]) + abs(p[1] - out[i - 1][1])) > 1e-9]


def octagon() -> Outline:
    return full_outline(scaled(STL_OCTAGON))


def opening() -> Outline:
    """The mouth's clear outline: the passage traffic flies through, from the face to the doors."""
    return full_outline(scaled(STL_OPENING))


def opening_half() -> tuple[float, float]:
    """The clear outline's half width (the band) and half height (the core)."""
    q = scaled(STL_OPENING)
    return q[0][0], q[-1][1]


def offset(outline: Sequence[tuple[float, float]], d: float) -> Outline:
    """An outline moved out by ``d`` (in for a negative ``d``), its corners mitred."""
    p = np.asarray(outline, dtype=float)
    out = []
    for i in range(len(p)):
        a, b, c = p[i - 1], p[i], p[(i + 1) % len(p)]
        n1, n2 = _out_normal(b - a), _out_normal(c - b)
        out.append(tuple(b + d * (n1 + n2) / (1.0 + float(n1 @ n2))))
    return out


def _out_normal(edge: np.ndarray) -> np.ndarray:
    return np.array([edge[1], -edge[0]]) / float(np.hypot(edge[0], edge[1]))


def contains(outline: Sequence[tuple[float, float]], x: float, y: float) -> bool:
    """Whether a point lies inside an outline (even-odd)."""
    p = np.asarray(outline, dtype=float)
    inside = False
    for (x0, y0), (x1, y1) in zip(p, np.roll(p, -1, axis=0), strict=True):
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            inside = not inside
    return inside


def rect(hx: float, hy: float) -> Outline:
    return [(hx, -hy), (hx, hy), (-hx, hy), (-hx, -hy)]


# --- flat faces ------------------------------------------------------------------------------------------------------
def polys(faces: Sequence[tuple[np.ndarray, Sequence[float], Material]]) -> Mesh:
    """Flat convex polygons (``points``, outward ``normal``, material), each fanned, its own chart, planar UVs."""
    if not faces:
        return Mesh.empty()
    table: list[Material] = []
    verts, tris, mats, charts, uvs = [], [], [], [], []
    base = 0
    for k, (points, normal, material) in enumerate(faces):
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        n = np.asarray(normal, dtype=float)
        if float(np.cross(p[1] - p[0], p[2] - p[0]) @ n) < 0.0:
            p = p[::-1]
        if material not in table:
            table.append(material)
        uv = planar_uv(p)
        for i in range(1, len(p) - 1):
            tris.append([base, base + i, base + i + 1])
            uvs.append(uv[[0, i, i + 1]])
            mats.append(table.index(material))
            charts.append(k)
        verts.append(p)
        base += len(p)
    return Mesh(np.concatenate(verts), np.array(tris), np.array(mats), tuple(table), np.array(charts), np.array(uvs))


def rect_z(x0: float, x1: float, y0: float, y1: float, z: float) -> np.ndarray:
    """A rectangle in the plane ``z`` (the normal passed to ``polys`` orients it)."""
    return np.array([[x0, y0, z], [x1, y0, z], [x1, y1, z], [x0, y1, z]])


def _ray(outline: Sequence[tuple[float, float]], angle: float) -> np.ndarray:
    """Where a ray from the axis at ``angle`` leaves a shape that is star-shaped about the axis."""
    d = np.array([math.cos(angle), math.sin(angle)])
    p = np.asarray(outline, dtype=float)
    best = math.inf
    for a, b in zip(p, np.roll(p, -1, axis=0), strict=True):
        e = b - a
        den = d[0] * -e[1] - d[1] * -e[0]
        if abs(den) < 1e-12:
            continue
        t = (a[0] * -e[1] - a[1] * -e[0]) / den
        s = (d[0] * a[1] - d[1] * a[0]) / den
        if t > 1e-9 and -1e-9 <= s <= 1.0 + 1e-9:
            best = min(best, t)
    return d * best


def ring_face(outer: Sequence[tuple[float, float]], inner: Sequence[tuple[float, float]], z: float, facing: float,
              material: Material) -> list:
    """The face between two outlines star-shaped about the axis (``inner`` inside ``outer``) in the plane ``z``, in quads between
    rays through every corner of either."""
    angles = sorted({round(math.atan2(y, x) % (2.0 * math.pi), 9) for x, y in [*outer, *inner]})
    out = []
    for a0, a1 in zip(angles, angles[1:] + [angles[0] + 2.0 * math.pi], strict=True):
        i0, i1, o0, o1 = _ray(inner, a0), _ray(inner, a1), _ray(outer, a0), _ray(outer, a1)
        quad = np.array([[*i0, z], [*i1, z], [*o1, z], [*o0, z]])
        out.append((quad, (0.0, 0.0, facing), material))
    return out


def outline_walls(outline: Sequence[tuple[float, float]], z0: float, z1: float, inward: bool, material: Material,
                  pick=None) -> list:
    """The walls along an outline's edges from ``z0`` to ``z1``, facing in toward the axis (a hole) or out (a solid); ``pick(a, b)``
    may choose an edge's material."""
    p = np.asarray(outline, dtype=float)
    out = []
    for a, b in zip(p, np.roll(p, -1, axis=0), strict=True):
        n = _out_normal(b - a) * (-1.0 if inward else 1.0)
        m = pick(a, b) if pick is not None else None
        out.append((np.array([[a[0], a[1], z0], [b[0], b[1], z0], [b[0], b[1], z1], [a[0], a[1], z1]]), (n[0], n[1], 0.0),
                    m or material))
    return out


def box_faces(lo: Sequence[float], hi: Sequence[float], material: Material, skip_back: bool = True) -> list:
    """A box's faces (the aft face left out when ``skip_back``: it lies on what it stands on and is never seen)."""
    lo, hi = np.asarray(lo, dtype=float), np.asarray(hi, dtype=float)
    out = []
    for axis in range(3):
        a, b = [i for i in range(3) if i != axis]
        for side, w in ((-1.0, lo[axis]), (1.0, hi[axis])):
            if skip_back and axis == 2 and side > 0.0:
                continue
            q = []
            for ca, cb in ((0, 0), (1, 0), (1, 1), (0, 1)):
                p = np.zeros(3)
                p[axis], p[a], p[b] = w, (hi[a] if ca else lo[a]), (hi[b] if cb else lo[b])
                q.append(p)
            normal = np.zeros(3)
            normal[axis] = side
            out.append((np.array(q), normal, material))
    return out


def hexahedron(corners: np.ndarray, material: Material, skip: Sequence[str] = ()) -> list:
    """A convex six-faced solid from its eight corners (``corners[i]`` for i = x + 2 y + 4 z, each 0 or 1 at the low or high side),
    its faces turned outward; ``skip`` names faces left out (``-x``, ``+x``, ``-y``, ``+y``, ``-z``, ``+z``)."""
    c = np.asarray(corners, dtype=float)
    centre = c.mean(axis=0)
    out = []
    for axis, name in ((0, "x"), (1, "y"), (2, "z")):
        for side in (0, 1):
            if f"{'+' if side else '-'}{name}" in skip:
                continue
            idx = [i for i in range(8) if (i >> axis) & 1 == side]
            q = c[[idx[0], idx[1], idx[3], idx[2]]]
            normal = np.cross(q[1] - q[0], q[2] - q[0])
            if float(normal @ (q.mean(axis=0) - centre)) < 0.0:
                normal = -normal
            out.append((q, normal, material))
    return out


# --- the bay ---------------------------------------------------------------------------------------------------------
def _block(mats: dict[str, Material]) -> list:
    """The frame block: its rim and face round the mouth, its walls back into the drum, the slats, side grilles, marked panels,
    notches and the red lamps round the mouth."""
    frame, recess, grey, lamp = mats["bay_frame"], mats["recess"], mats["drum_grey"], mats["lamp"]
    outer, mouth = octagon(), opening()
    inner = offset(outer, -RIM[0])
    rim_z = FACE_Z - RIM[1]
    out = ring_face(outer, inner, rim_z, -1.0, frame) + outline_walls(inner, rim_z, FACE_Z, True, frame)
    out += outline_walls(outer, rim_z, BLOCK_BACK_Z, False, frame)
    out += ring_face(inner, mouth, FACE_Z, -1.0, frame)
    s = BAY_SCALE
    stand = 0.8 * s
    half, y0, y1, count = STL_SLATS
    for sy in (-1.0, 1.0):  # the slats over and under the mouth
        for x in np.linspace(-half, half, count):
            ya, yb = sorted((sy * y0 * s, sy * y1 * s))
            out += box_faces((x * s - 0.8, ya, FACE_Z - stand), (x * s + 0.8, yb, FACE_Z), recess)
    xa, xb, ya, yb = STL_SIDE_SLATS
    for sx in (-1.0, 1.0):  # the short grilles beside it
        for sy in (-1.0, 1.0):
            for y in np.linspace(ya, yb, 3):
                x0, x1 = sorted((sx * xa * s, sx * xb * s))
                out += box_faces((x0, sy * y * s - 0.6, FACE_Z - stand), (x1, sy * y * s + 0.6, FACE_Z), recess)
    px0, px1, py0, py1 = STL_PANEL
    for sx in (-1.0, 1.0):  # the marked panels: a dark plate with pale bars
        for sy in (-1.0, 1.0):
            x0, x1 = sorted((sx * px0 * s, sx * px1 * s))
            y0_, y1_ = sorted((sy * py0 * s, sy * py1 * s))
            out += box_faces((x0, y0_, FACE_Z - 0.6), (x1, y1_, FACE_Z), recess)
            for k in range(3):
                yb_ = y0_ + 1.5 + 3.5 * k
                out += box_faces((x0 + 1.5, yb_, FACE_Z - 1.0), (x0 + 1.5 + (12.0 if k != 1 else 7.0), yb_ + 1.4, FACE_Z - 0.6), grey)
    nx, ny = STL_NOTCH
    top = STL_OCTAGON[-1][1] * s - RIM[0]
    for sy in (-1.0, 1.0):  # the notches at the top and bottom, a lamp in each
        y0_, y1_ = sorted((sy * ny * s, sy * top))
        out += box_faces((-nx * s, y0_, FACE_Z - 1.0), (nx * s, y1_, FACE_Z), recess)
        yl = sy * 0.5 * (ny * s + top)
        out += box_faces((-1.0, yl - 1.0, FACE_Z - 2.2), (1.0, yl + 1.0, FACE_Z - 1.0), lamp)
    for x, y in entrance_lamps():
        out += box_faces((x - 0.8, y - 0.8, FACE_Z - 1.4), (x + 0.8, y + 0.8, FACE_Z), lamp)
    return out


def entrance_lamps() -> list[tuple[float, float]]:
    """The red lamps round the mouth on the block's face (T18 lights them)."""
    hw, hh = opening_half()
    return [(sx * (hw + 3.0), 0.0) for sx in (-1.0, 1.0)] + [(sx * 28.0, sy * (hh + 2.4)) for sx in (-1.0, 1.0) for sy in (-1.0, 1.0)]


def _mouth(mats: dict[str, Material]) -> list:
    """The mouth from the face to the doors, in the show's metallic grey lit red by its lamps (``BayLights``): the lip, the walls set
    back round the clear outline with ribs round them, the frames standing in to the outline, machinery on the set-back walls, and
    the back wall round the doors. Nothing in it glows but its small lamps and the plating's faint tint (the maintainer: no self-lit
    rings or bands)."""
    wall, mouth = mats["bay_tunnel"], opening()
    grown = offset(mouth, RECESS_M)
    lip_z = FACE_Z + LIP_M
    out = outline_walls(mouth, FACE_Z, lip_z, True, wall)
    out += ring_face(grown, mouth, lip_z, 1.0, wall)
    edges = [lip_z, *[z for k in FRAME_Z for z in (k, k + FRAME_M)], DOORS_Z]
    for z0, z1 in zip(edges[0::2], edges[1::2], strict=True):
        out += outline_walls(grown, z0, z1, True, wall)
    for z in FRAME_Z:  # plain grey metal: the red on them is the lamps' light (the maintainer: no self-lit rings)
        out += ring_face(grown, mouth, z, -1.0, wall)
        out += ring_face(grown, mouth, z + FRAME_M, 1.0, wall)
        out += outline_walls(mouth, z, z + FRAME_M, True, wall)
    out += _machinery(mats, grown, edges)
    out += _ribs(wall, grown, edges)
    out += ring_face(grown, mouth, DOORS_Z, -1.0, wall)
    return out


def _ribs(wall: Material, grown: Outline, edges: Sequence[float]) -> list:
    """Two ribs round the set-back walls in each gap between the frames, clear of the machinery's ends: the show's ribbed plating."""
    stand, length = RIB
    inner = offset(grown, -stand)
    out = []
    for za, zb in zip(edges[0::2], edges[1::2], strict=True):
        if zb - za < 6.0:
            continue
        for z0 in (za + 0.5, zb - 0.5 - length):
            out += outline_walls(inner, z0, z0 + length, True, wall)
            out += ring_face(grown, inner, z0, -1.0, wall)
            out += ring_face(grown, inner, z0 + length, 1.0, wall)
    return out


def _machinery(mats: dict[str, Material], grown: Outline, edges: Sequence[float]) -> list:
    """Boxes on the set-back walls between the frames (the core's roof and floor, the band's), standing in less than the set-back,
    a red lamp on every other one."""
    out = []
    hw, hh = opening_half()
    band_top = scaled(STL_OPENING)[1][1] + RECESS_M
    core_top = hh + RECESS_M
    stand = RECESS_M - 0.5
    gaps = list(zip(edges[0::2], edges[1::2], strict=True))  # between the frames
    for k, (za, zb) in enumerate(gaps):
        za, zb = za + 1.5, zb - 1.5
        if zb - za < 3.0:
            continue
        m = mats["machinery"] if k % 2 else mats["bay_tunnel"]
        for sy in (-1.0, 1.0):
            for x0, x1, wall_y in ((-16.0, -4.0, core_top), (4.0, 16.0, core_top), (26.0, 31.0, band_top), (-31.0, -26.0, band_top)):
                y0, y1 = sorted((sy * (wall_y - stand), sy * (wall_y + 0.1)))
                out += box_faces((x0, y0, za), (x1, y1, zb), m, skip_back=False)
            if k % 2 == 0:
                face = sy * (core_top - stand)
                y0, y1 = sorted((face, face - sy * 0.4))
                out += box_faces((-1.0, y0, 0.5 * (za + zb) - 1.0), (1.0, y1, 0.5 * (za + zb) + 1.0), mats["bay_red_2"], skip_back=False)
    return out


def _void(mats: dict[str, Material]) -> list:
    """The doorway through the doors' slab, and the black void behind it: sealed, unlit, where a docking ship leaves the world."""
    void, mouth = mats["bay_void"], opening()
    front = DOORS_Z + DOOR_SLAB_M
    hold = rect(*VOID_HALF)
    out = outline_walls(mouth, DOORS_Z, front, True, mats["bay_tunnel"])  # the doorway's lip: the tunnel's metal
    out += ring_face(hold, mouth, front, 1.0, void)
    out += outline_walls(hold, front, VOID_BACK_Z, True, void)
    out.append((rect_z(-VOID_HALF[0], VOID_HALF[0], -VOID_HALF[1], VOID_HALF[1], VOID_BACK_Z), (0.0, 0.0, -1.0), void))
    return out


def bar_at(y: float) -> tuple[float, float]:
    """A bar's half width and face z at ``|y|``."""
    (y0, w0, z0), (y1, w1, z1) = BAR
    t = (abs(y) - y0) / (y1 - y0)
    return w0 + (w1 - w0) * t, z0 + (z1 - z0) * t


def _housing(mats: dict[str, Material]) -> list:
    """The cross housing at the STL's size: the bar across from the block's sides, the bars up and down from its top and bottom with
    boxes along their sides, and the lower hatch."""
    machinery, recess, frame = mats["machinery"], mats["recess"], mats["bay_frame"]
    hh, end = HOUSING
    side = STL_OCTAGON[0][0] * BAY_SCALE
    out = []
    for sx in (-1.0, 1.0):
        x0, x1 = sorted((sx * side, sx * end))
        out += box_faces((x0, -hh, FACE_Z), (x1, hh, BAR_BACK_Z), machinery)
    (y0, _, _), (y1, _, _) = BAR
    for sy in (-1.0, 1.0):
        corners = []
        for z_side in (0, 1):
            for y_side in (0, 1):
                y = y1 if y_side else y0
                w, zf = bar_at(y)
                for x_side in (0, 1):
                    corners.append((w if x_side else -w, sy * y, BAR_BACK_Z if z_side else zf))
        out += hexahedron(np.array(corners), machinery, skip=("-y", "+z"))
        for y in BAR_BOXES:
            w, zf = bar_at(y)
            for sx in (-1.0, 1.0):
                xa, xb = sorted((sx * (w - 0.5), sx * (w + 5.0)))
                ya, yb = sorted((sy * (y - 3.0), sy * (y + 3.0)))
                out += box_faces((xa, ya, zf + 2.0), (xb, yb, BAR_BACK_Z), recess)
    px0, px1, py0, py1, pz = HOUSING_POSTS
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            xa, xb = sorted((sx * px0, sx * px1))
            ya, yb = sorted((sy * py0, sy * py1))
            out += box_faces((xa, ya, pz), (xb, yb, BAR_BACK_Z), recess)
    # The lower hatch on the bar below: a dark leaf in a pale frame just off its sloping face.
    for (ya, yb, inset, m) in ((-92.0, -60.0, 0.4, frame), (-89.0, -63.0, 0.7, recess)):
        corners = []
        for y in (ya, yb):
            w, zf = bar_at(y)
            corners.append((y, w - (3.0 if m is frame else 5.5), zf - inset))
        quad = np.array([[-corners[0][1], ya, corners[0][2]], [corners[0][1], ya, corners[0][2]],
                         [corners[1][1], yb, corners[1][2]], [-corners[1][1], yb, corners[1][2]]])
        out.append((quad, (0.0, 0.0, -1.0), m))
    return out


def _fans(mats: dict[str, Material]) -> list:
    """The fan-shaped grille housings beside the block (scaled with it), lofted through ``FAN``, their sloping faces striped with
    dark slats, two rails from the mouth's side to each."""
    machinery, recess = mats["machinery"], mats["recess"]
    s = BAY_SCALE
    rx0, rx1, ry0, ry1, rz = STL_FAN_RAILS
    out = []
    for sx in (-1.0, 1.0):
        def p(x: float, y: float, z: float) -> list[float]:
            return [sx * x, y, z]
        for (x0, h0, z0), (x1, h1, z1) in zip(FAN[:-1], FAN[1:], strict=True):
            front = np.array([p(x0, -h0, z0), p(x1, -h1, z1), p(x1, h1, z1), p(x0, h0, z0)])
            normal = np.cross(front[1] - front[0], front[2] - front[0])
            normal *= -1.0 if normal[2] > 0.0 else 1.0
            out.append((front, normal, machinery))
            for sy in (-1.0, 1.0):
                q = np.array([p(x0, sy * h0, z0), p(x1, sy * h1, z1), p(x1, sy * h1, FACE_Z), p(x0, sy * h0, FACE_Z)])
                n = np.cross(q[1] - q[0], q[2] - q[0])
                if float(n[1]) * sy < 0.0:
                    n = -n
                out.append((q, n, machinery))
            out.append((np.array([p(x0, -h0, FACE_Z), p(x1, -h1, FACE_Z), p(x1, h1, FACE_Z), p(x0, h0, FACE_Z)]), (0.0, 0.0, 1.0), machinery))
            lift = unit(normal) * 0.3
            for t in np.linspace(0.15, 0.85, max(1, int(round((x1 - x0) / 4.0)))):  # the slats across the sloping face
                ta, tb = t - 0.6 / (x1 - x0), t + 0.6 / (x1 - x0)
                xa, ha, za = x0 + (x1 - x0) * ta, h0 + (h1 - h0) * ta, z0 + (z1 - z0) * ta
                xb, hb, zb = x0 + (x1 - x0) * tb, h0 + (h1 - h0) * tb, z0 + (z1 - z0) * tb
                slat = np.array([p(xa, -ha + 1.0, za), p(xb, -hb + 1.0, zb), p(xb, hb - 1.0, zb), p(xa, ha - 1.0, za)]) + lift
                out.append((slat, normal, recess))
        for (x, h, z), facing in ((FAN[0], -sx), (FAN[-1], sx)):
            out.append((np.array([p(x, -h, z), p(x, h, z), p(x, h, FACE_Z), p(x, -h, FACE_Z)]), (facing, 0.0, 0.0), machinery))
        xa, xb = sorted((sx * rx0 * s, sx * rx1 * s))
        for sy in (-1.0, 1.0):
            ya, yb = sorted((sy * ry0 * s, sy * ry1 * s))
            out += box_faces((xa, ya, scaled_z(rz)), (xb, yb, FACE_Z), machinery)
    return out


def main_docking_bay(mats: dict[str, Material]) -> Mesh:
    """The main docking bay at the bow (turns with the drum)."""
    return polys(_block(mats) + _mouth(mats) + _void(mats) + _housing(mats) + _fans(mats))


def saw_edge(x: np.ndarray | float) -> np.ndarray:
    """The upper door's lower edge: a trapezoid wave of teeth across the doorway."""
    height, period, _ = SAW
    t = np.mod(np.asarray(x, dtype=float) + 0.5 * period, period) / period
    rise = np.clip((t - 3.0 / 14.0) / (4.0 / 14.0), 0.0, 1.0) - np.clip((t - 10.0 / 14.0) / (4.0 / 14.0), 0.0, 1.0)
    return -0.5 * height + height * rise


def saw_breaks(x0: float, x1: float) -> list[float]:
    """The seam's corners between ``x0`` and ``x1``."""
    _, period, _ = SAW
    out = []
    k = math.floor((x0 + 0.5 * period) / period) - 1
    while True:
        base = k * period - 0.5 * period
        for f in (3.0, 7.0, 10.0, 14.0):
            x = base + f / 14.0 * period
            if x0 < x < x1:
                out.append(x)
        if base > x1:
            break
        k += 1
    return out


def door_leaf_outline(upper: bool) -> list[tuple[float, float, float]]:
    """A leaf's strips across the doorway, closed: (x0, x1, its seam edge's y at x0, at x1, its far edge's y), in the station frame."""
    hw, hh = opening_half()
    _, _, past_x, past_y = DOOR_LEAF
    w, top = hw + past_x, hh + past_y
    _, _, gap = SAW
    xs = sorted({-w, w, *saw_breaks(-w, w)})
    out = []
    for a, b in zip(xs[:-1], xs[1:], strict=True):
        ya, yb = float(saw_edge(a)), float(saw_edge(b))
        if upper:
            out.append((a, b, ya, yb, top))
        else:
            out.append((a, b, ya - gap, yb - gap, -top))
    return out


# --- the cargo bay (zero-gravity) ----------------------------------------------------------------------------------------
# Inside the spine where the slot between the bow's forks ends (M7-T21, read off the STL): a closed rectangular compartment, roofed,
# reached only through an octagonal throat facing down the slot. Inside it is the main docking bay's red-lit grey metal (M7-T32):
# the walls, roof and floor lined with ``bay_tunnel``, grey machinery and ribs, small lamps, lit red by two lamps through the light
# rig's slots (``BayLights``); nothing self-lit but the lamps. Saturn freighters hold outside and the station's maintenance bots
# carry their cargo pods (31.1 x 17.2 x 43.0 m, ``saturn.POD``) in and out (M7-T30).
ZG_FRONT_Z = 420.0  # the spine's front, the slot's end: the throat's mouth
ZG_COMPARTMENT_Z = 442.0  # the throat gives onto the compartment here (the STL's)
ZG_BACK_Z = 490.0  # 8 m deeper than the STL's, so a whole pod (43 m) lies in it lengthwise
ZG_HALF_X = 94.0  # the compartment's inner half width (the STL's +-96 less its walls): pods side by side
ZG_FLOOR_Y = 323.0
ZG_ROOF_Y = 357.0
ZG_THROAT = (34.1, 7.6)  # the throat's half width and the cut off each of its corners (the STL's octagon)
ZG_THROAT_Y = (323.3, 354.7)  # its floor and roof (the STL's)
ZG_MACHINE_M = 4.0  # the compartment's floor machinery stands up to this
ZG_RING = (2.9, 2.0)  # the frame round the throat's mouth: its width (out to the STL's x +-37) and how far it stands proud
ZG_CENTRE_Y = 339.0  # the pods' path: the throat's middle


def throat_outline(grow: float = 0.0) -> list[tuple[float, float]]:
    """The throat's octagon (x, y), counter-clockwise, grown by ``grow``."""
    hx, cut = ZG_THROAT[0] + grow, ZG_THROAT[1]
    y0, y1 = ZG_THROAT_Y[0] - grow, ZG_THROAT_Y[1] + grow
    return [(-hx + cut, y0), (hx - cut, y0), (hx, y0 + cut), (hx, y1 - cut), (hx - cut, y1), (-hx + cut, y1), (-hx, y1 - cut),
            (-hx, y0 + cut)]


def cargo_bay_walls(m: Material) -> Mesh:
    """The spine's front from the slot's end to the bay's back round the throat and the compartment (the spine itself starts at
    the compartment's back): roof, floor and sides of each, and the throat's four cut corners."""
    from . import station as st_  # noqa: PLC0415

    hx = ZG_THROAT[0]
    parts = []
    for (za, zb), half, (lo, hi) in (((ZG_FRONT_Z, ZG_COMPARTMENT_Z), hx, ZG_THROAT_Y), ((ZG_COMPARTMENT_Z, ZG_BACK_Z), ZG_HALF_X,
                                                                                       (ZG_FLOOR_Y, ZG_ROOF_Y))):
        rows = [st_.spine_row_at(za), st_.spine_row_at(zb)]
        parts += [
            st_.slab([(z, -w, w, hi, top) for z, w, _, top in rows], m),
            st_.slab([(z, -w, w, under, lo) for z, w, under, _ in rows], m),
            st_.slab([(z, -w, -half, lo, hi) for z, w, _, _ in rows], m),
            st_.slab([(z, half, w, lo, hi) for z, w, _, _ in rows], m),
        ]
    # The keel under the bay down to the bow's pylon, and the ridge along its roof (the STL's, x +-10).
    parts.append(st_.block((-10.0, 290.0, ZG_COMPARTMENT_Z + 6.0), (10.0, 316.0, 494.0), m))
    parts.append(st_.slab([(445.0, -10.0, 10.0, 360.0, 372.0), (495.0, -10.0, 10.0, 370.0, 386.0)], m))
    cut = ZG_THROAT[1]
    lo, hi = ZG_THROAT_Y
    for sx in (-1.0, 1.0):
        for sy, y in ((1.0, hi), (-1.0, lo)):
            corner = [(sx * hx, y), (sx * hx, y - sy * cut), (sx * (hx - cut), y)]
            parts.append(st_.prism_xr(corner, ZG_FRONT_Z, ZG_COMPARTMENT_Z, m))
    return Mesh.concatenate(parts)


def lined(mesh: Mesh, lining: Material) -> Mesh:
    """``mesh`` (the frame, in the station frame) with its faces inside the cargo bay, the faces the game draws out of the sun (its
    walls, roof, floor and back wall), in ``lining`` (M7-T32)."""
    from .station_layouts import frame_interior  # noqa: PLC0415 - the layouts build on this module

    tris = mesh.vertices[mesh.faces]
    inside = frame_interior(tris.mean(axis=1), mesh.face_normals())
    table = list(mesh.materials)
    if lining not in table:
        table.append(lining)
    material = np.where(inside, table.index(lining), mesh.face_material)
    return Mesh(mesh.vertices, mesh.faces, material, tuple(table), mesh.face_chart, mesh.face_uv)


def _ring(mats: dict[str, Material]) -> Mesh:
    """The frame round the throat's mouth, standing proud of the spine's front."""
    from . import station as st_  # noqa: PLC0415

    width, proud = ZG_RING
    inner, outer = throat_outline(), throat_outline(width)
    parts = []
    for k in range(len(inner)):
        quad = [inner[k], inner[(k + 1) % len(inner)], outer[(k + 1) % len(inner)], outer[k]]
        parts.append(st_.prism_xr(quad, ZG_FRONT_Z - proud, ZG_FRONT_Z, mats["bay_frame"]))
    return Mesh.concatenate(parts)


def _zg_machinery(mats: dict[str, Material]) -> list:
    """The compartment's floor: grey machinery blocks in tiers; ribs up the walls; small red lamps on the back wall and under the roof.
    No red strips or pink lamps (the maintainer: the red is the lamps' light on grey metal, M7-T32)."""
    plating, machinery = mats["bay_tunnel"], mats["machinery"]
    hx, floor, roof = ZG_HALF_X, ZG_FLOOR_Y, ZG_ROOF_Y
    out = []
    xs = np.linspace(-hx + 1.0, hx - 1.0, 13)
    zs = np.arange(ZG_COMPARTMENT_Z + 2.0, ZG_BACK_Z - 2.0, 8.0)
    for i, (xa, xb) in enumerate(zip(xs[:-1], xs[1:], strict=True)):
        for k, za in enumerate(zs[:-1]):
            h = 1.0 + 3.0 * (0.5 + 0.5 * math.sin(1.7 * i + 2.3 * k)) * min(1.0, (k + 1) / 3.0)  # tiers stepping up toward the back
            lo, hi = (xa + 0.4, floor, za + 0.4), (xb - 0.4, floor + h, za + 7.6)
            out += box_faces(lo, hi, plating if (i + k) % 3 else machinery, skip_back=False)
    for sx in (-1.0, 1.0):
        x0, x1 = sorted((sx * hx, sx * (hx - 1.2)))
        for z in np.arange(ZG_COMPARTMENT_Z + 8.0, ZG_BACK_Z - 4.0, 12.0):
            out += box_faces((x0, floor + ZG_MACHINE_M, z - 1.0), (x1, roof - 1.0, z + 1.0), plating, skip_back=False)
    for x in np.linspace(-80.0, 80.0, 9):  # red lamps along the back wall, and a row under the roof
        out += box_faces((x - 1.0, floor + 14.0, ZG_BACK_Z - 0.6), (x + 1.0, floor + 16.0, ZG_BACK_Z), mats["lamp"], skip_back=False)
        out += box_faces((x - 0.8, roof - 0.6, 465.0 - 0.8), (x + 0.8, roof, 465.0 + 0.8), mats["lamp"], skip_back=False)
    return out


def cargo_bay(mats: dict[str, Material]) -> Mesh:
    """The bay's dressing: the frame round the throat's mouth and the compartment's machinery and lamps."""
    return Mesh.concatenate([_ring(mats), polys(_zg_machinery(mats))])


# --- the command section ----------------------------------------------------------------------------------------------
# The bow spine over the docking sphere (Q2: it holds from 50 m): open machinery compartments along its top (the STL's recesses, the
# Mallacore render's lit bays of tanks and coils) and serrated lower edges along the forks.
COMPARTMENTS = ((0.0, 635.0, 22.0, 12.0), (0.0, 780.0, 30.0, 22.0), (0.0, 905.0, 30.0, 20.0))  # x, z, half width, half length
COMPARTMENT_RIM = (3.0, 4.0)  # the rim's thickness and height
FORK_TEETH = (14.0, 8.0, 5.0)  # pitch, base, how far each tooth hangs below the fork's outer lower edge


def _compartment(x: float, z: float, hw: float, hl: float, mats: dict[str, Material]) -> list:
    """An open compartment on the spine's top: a rim round a dark floor, tanks and a coil housing inside, a red lamp."""
    from . import station_spine as ssp  # noqa: PLC0415

    top = max(ssp.top_at(z - hl, x), ssp.top_at(z + hl, x))
    t, h = COMPARTMENT_RIM
    frame, recess, machinery = mats["bay_frame"], mats["recess"], mats["machinery"]
    out = []
    for sx in (-1.0, 1.0):
        out += box_faces((x + min(sx * hw, sx * (hw + t)), top - 2.0, z - hl - t), (x + max(sx * hw, sx * (hw + t)), top + h, z + hl + t),
                         frame, skip_back=False)
    for sz in (-1.0, 1.0):
        out += box_faces((x - hw, top - 2.0, z + min(sz * hl, sz * (hl + t))), (x + hw, top + h, z + max(sz * hl, sz * (hl + t))), frame,
                         skip_back=False)
    out += box_faces((x - hw, top - 2.0, z - hl), (x + hw, top + 0.3, z + hl), recess, skip_back=False)  # the floor, dark
    for k, tx in enumerate(np.linspace(x - hw + 6.0, x + hw - 6.0, 3)):  # tanks lying along the spine, and a coil housing
        if k == 1:
            out += box_faces((tx - 4.0, top + 0.3, z - 0.6 * hl), (tx + 4.0, top + 6.0, z + 0.2 * hl), machinery, skip_back=False)
            continue
        out += box_faces((tx - 3.0, top + 0.3, z - 0.8 * hl), (tx + 3.0, top + 5.5, z + 0.8 * hl), machinery, skip_back=False)
        out += box_faces((tx - 3.4, top + 0.2, z - 0.1 * hl - 1.0), (tx + 3.4, top + 6.0, z - 0.1 * hl + 1.0), recess, skip_back=False)
    out += box_faces((x + hw - 2.0, top + 0.3, z + hl - 2.0), (x + hw - 0.5, top + 1.8, z + hl - 0.5), mats["lamp"], skip_back=False)
    return out


def _fork_teeth(m: Material) -> list:
    """Sawtooth teeth hanging along each fork's outer lower edge."""
    from . import station_spine as ssp  # noqa: PLC0415

    pitch, base, drop = FORK_TEETH
    out = []
    for z in np.arange(20.0, 420.0, pitch):
        xe, y = ssp.prong_edge(z)
        for sx in (-1.0, 1.0):
            a, b, tip = np.array([sx * xe, y, z - 0.5 * base]), np.array([sx * xe, y, z + 0.5 * base]), np.array([sx * xe, y - drop, z])
            inner = np.array([-sx * 4.0, 0.0, 0.0])
            out.append((np.array([a, b, tip]), (sx, 0.0, 0.0), m))
            out.append((np.array([a + inner, b + inner, tip + inner]), (-sx, 0.0, 0.0), m))
            out.append((np.array([a, b, b + inner, a + inner]), (0.0, 1.0, 0.0), m))  # its base, against the fork
            for p, q in ((a, tip), (tip, b)):
                d = q - p
                normal = np.cross(d, inner)
                if float(normal @ (0.5 * (p + q) - 0.5 * (a + b))) < 0.0:
                    normal = -normal
                out.append((np.array([p, q, q + inner, p + inner]), tuple(normal), m))
    return out


def command_detail(mats: dict[str, Material]) -> Mesh:
    """The command section's near-field detail on the bow spine: its open compartments and the forks' serrated edges."""
    faces = []
    for x, z, hw, hl in COMPARTMENTS:
        faces += _compartment(x, z, hw, hl, mats)
    return polys(faces + _fork_teeth(mats["spine"]))


# --- the defence grid's plinths ---------------------------------------------------------------------------------------
PLINTH_R = {"light_pulse": 5.0, "heavy_cannon": 9.0, "interceptor": 6.5}
PLINTH_TOP_M = 0.4  # the plinth's face stands this far over the pivot, so it never shares the hull's plane
PLINTH_DEPTH_M = 6.0  # and reaches this far below the pivot, into the hull under a mount raised off it


def plinth(position: Sequence[float], up: Sequence[float], radius: float, m: Material) -> Mesh:
    """A round plinth along ``up`` under a mount's pivot, from inside the hull to just over the pivot."""
    z0, z1 = -PLINTH_DEPTH_M, PLINTH_TOP_M
    rim = 0.8
    mesh = lathe([(z0, 0.0), (z0, radius), (z1 - rim, radius), (z1, radius - rim), (z1, 0.0)], 16, m, creases=(1, 2, 3))
    # The lathe's front is its -z end: turn it so its +z runs along ``up``.
    return mesh.transformed(basis_from_z(unit(np.asarray(up, dtype=float))), position)


__all__ = ["BAY_SCALE", "DOORS_Z", "FACE_Z", "VOID_BACK_Z", "VOID_HALF", "ZG_HALF_X", "cargo_bay", "cargo_bay_walls", "command_detail",
           "door_leaf_outline", "entrance_lamps", "main_docking_bay", "octagon", "offset", "opening", "opening_half", "plinth", "saw_edge"]
