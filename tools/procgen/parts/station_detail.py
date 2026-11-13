"""The station's near-field detail (M7-T05): the main docking bay at the bow, the cargo bay (zero-gravity) between the bow's forks and the
defence grid's mount plinths.

The main docking bay (``references/docking bay references/``, described in docs/milestones/m7-babylon-5-station.md, M7-T05; nothing from
them is traced) is the drum's door, turning with it: a plate across the docking sphere's front opening with a toothed rim, a long
housing across it and a bar up and down it (a cross), a vented central block carrying the stepped, cross-shaped mouth, a funnel of
frames stepping in, a straight tunnel lined with machinery and ringed by frames that glow red, deeper ones dimmer, and the inner
airlock's two doors closed on a sawtooth seam at its end. Grilles, marked panels and a lower hatch dress the block and the bar.

Every outline here is rectilinear (the mouth is a stepped cross), so faces are rectangles cut in strips and walls run along the
outline's edges. Numbers are metres in the station frame of ``station.py`` (z aft from the bow tip).
"""

from __future__ import annotations

import math
from collections.abc import Sequence

import numpy as np

from ..core.geometry import Material, Mesh, basis_from_z, lathe, planar_uv, unit
from . import station as st

Steps = tuple[tuple[float, float], ...]  # a stepped cross: (half width, half height) from the widest step to the tallest

# The door plate across the sphere's front opening, and what stands on it (half sizes, and the z of the front face).
PLATE_Z = st.DOOR_Z
BLOCK = (70.0, 56.0, 450.0)  # the vented central block carrying the mouth
HOUSING = (128.0, 30.0, 460.0)  # the long housing across the plate (each arm from the block's side to x 128)
BAR_UP = (16.0, 124.0, 466.0)  # the bar up the plate (from the block's top)
BAR_DOWN = (28.0, 122.0, 462.0)  # and down it, wider, carrying the lower hatch
HATCH = (20.0, 62.0, 112.0)  # the lower hatch: half width, top and bottom (|y|)
# The mouth: the outer frame's stepped cross, then frames each stepping in by MOUTH_INSET and back by MOUTH_LAYER_M.
MOUTH: Steps = ((58.0, 28.0), (40.0, 36.0), (26.0, 44.0))
MOUTH_LAYERS = 4
MOUTH_INSET = 3.0
MOUTH_LAYER_M = 6.0
# The tunnel from the last frame to the inner airlock, ringed by frames that stand in from its walls.
AIRLOCK_Z = 640.0  # the doors' faces
TUNNEL_BACK_Z = 646.0  # the dark wall behind the doors' seam
RIB_Z = (490.0, 514.0, 538.0, 562.0, 586.0, 610.0)
RIB_INSET = 2.0
RIB_DEPTH = 3.0
EDGE_STRIP_M = 0.8  # the lit strip round each frame's inner edge
EDGE_LIFT_M = 0.05  # how far a strip stands off its face
# The airlock's sawtooth seam: the teeth's height, the period, and the gap between the doors.
SAW = (10.0, 22.0, 2.4)
PLATE_TEETH = (40, 112.0, 124.0, 5.0)  # the toothed rim: count, the tips' and the bases' radius, how far they stand out
# The block's grilles: slats standing 1.5 m off its face, every 4 m.
GRILLE = (1.6, 4.0, 1.5)


def mouth(layer: int) -> Steps:
    """The stepped cross of frame ``layer`` (0 the outer one at the block's face)."""
    return tuple((x - layer * MOUTH_INSET, y - layer * MOUTH_INSET) for x, y in MOUTH)


def tunnel() -> Steps:
    """The tunnel's walls: the last frame's outline."""
    return mouth(MOUTH_LAYERS - 1)


def clear_passage() -> tuple[float, float]:
    """The clear passage's half width and half height through the whole bay: the tunnel's widest step inside its frames."""
    x, y = tunnel()[0]
    return x - RIB_INSET, y - RIB_INSET


def layer_z(layer: int) -> float:
    return BLOCK[2] + layer * MOUTH_LAYER_M


def half_height(steps: Steps, x: float) -> float:
    """How high a stepped cross reaches at ``|x|`` (0 outside it)."""
    return max((y for sx, y in steps if abs(x) < sx - 1e-9), default=0.0)


def shrunk(steps: Steps, d: float) -> Steps:
    return tuple((x - d, y - d) for x, y in steps)


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


def annulus(outer: Steps, inner: Steps, z: float, facing: float, material: Material) -> list:
    """The face between two stepped crosses (``inner`` may be empty: the whole of ``outer``) in the plane ``z``, in strips."""
    xs = sorted({0.0} | {x for x, _ in outer} | {x for x, _ in inner})
    out = []
    for a, b in zip(xs[:-1], xs[1:], strict=True):
        mid = 0.5 * (a + b)
        ho, hi = half_height(outer, mid), half_height(inner, mid)
        if ho <= hi + 1e-9:
            continue
        for sx in (-1.0, 1.0):
            x0, x1 = sorted((sx * a, sx * b))
            for y0, y1 in ((hi, ho), (-ho, -hi)) if hi > 0.0 else ((-ho, ho),):
                out.append((rect_z(x0, x1, y0, y1, z), (0.0, 0.0, facing), material))
    return out


def walls(steps: Steps, z0: float, z1: float, material: Material, first: Material | None = None) -> list:
    """The walls along a stepped cross's edges from ``z0`` to ``z1``, facing in toward the axis; ``first`` paints the outermost
    step's upright sides."""
    out = []

    def wall(a: Sequence[float], b: Sequence[float], normal: Sequence[float], m: Material) -> None:
        out.append((np.array([[a[0], a[1], z0], [b[0], b[1], z0], [b[0], b[1], z1], [a[0], a[1], z1]]), normal, m))

    n = len(steps)
    for i, (x, y) in enumerate(steps):
        y_lo = -y if i == 0 else steps[i - 1][1]
        for sx in (-1.0, 1.0):
            m = first if (i == 0 and first is not None) else material
            if i == 0:
                wall((sx * x, -y), (sx * x, y), (-sx, 0.0, 0.0), m)
            else:
                for sy in (-1.0, 1.0):
                    wall((sx * x, sy * y_lo), (sx * x, sy * y), (-sx, 0.0, 0.0), m)
        x_in = steps[i + 1][0] if i + 1 < n else 0.0
        for sy in (-1.0, 1.0):
            if i + 1 < n:
                for sx in (-1.0, 1.0):
                    wall((sx * x_in, sy * y), (sx * x, sy * y), (0.0, -sy, 0.0), material)
            else:
                wall((-x, sy * y), (x, sy * y), (0.0, -sy, 0.0), material)
    return out


def box_faces(lo: Sequence[float], hi: Sequence[float], material: Material, skip_back: bool = True) -> list:
    """A box's faces (the aft face left out when ``skip_back``: it lies on the plate and is never seen)."""
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


# --- the bay ---------------------------------------------------------------------------------------------------------
def _plate(m: Material) -> list:
    """The plate across the sphere's opening, from the block's footprint out to the rim, in rays from the axis."""
    hw, hh, _ = BLOCK
    corners = [math.atan2(sy * hh, sx * hw) % (2.0 * math.pi) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
    angles = sorted(set(np.round(np.linspace(0.0, 2.0 * math.pi, 64, endpoint=False), 9)) | set(np.round(corners, 9)))
    out = []
    for a0, a1 in zip(angles, angles[1:] + [angles[0] + 2.0 * math.pi], strict=True):
        pts = []
        for a in (a0, a1):
            c, s = math.cos(a), math.sin(a)
            t = min(hw / abs(c) if abs(c) > 1e-9 else math.inf, hh / abs(s) if abs(s) > 1e-9 else math.inf)
            pts.append(((t * c, t * s), (st.DOOR_R * c, st.DOOR_R * s)))
        (i0, o0), (i1, o1) = pts
        quad = np.array([[*i0, PLATE_Z], [*i1, PLATE_Z], [*o1, PLATE_Z], [*o0, PLATE_Z]])
        out.append((quad, (0.0, 0.0, -1.0), m))
    return out


def _tooth(a: float, m: Material) -> list:
    """One of the plate rim's sawtooth teeth: a triangle standing off the plate, its tip toward the axis."""
    count, r_tip, r_base, height = PLATE_TEETH
    half = 0.3 * math.pi / count
    base = [np.array([r_base * math.cos(a + d), r_base * math.sin(a + d)]) for d in (-half, half)]
    tip = np.array([r_tip * math.cos(a), r_tip * math.sin(a)])
    z0, z1 = PLATE_Z - height, PLATE_Z
    tri = [base[0], base[1], tip]
    out = [(np.array([[*p, z0] for p in tri]), (0.0, 0.0, -1.0), m)]
    for p, q in ((base[0], tip), (tip, base[1]), (base[1], base[0])):
        mid = 0.5 * (p + q)
        normal = np.array([q[1] - p[1], p[0] - q[0], 0.0])
        if float(normal[:2] @ (mid - (base[0] + base[1] + tip) / 3.0)) < 0.0:
            normal = -normal
        out.append((np.array([[*p, z0], [*q, z0], [*q, z1], [*p, z1]]), normal, m))
    return out


def _teeth(m: Material) -> list:
    count = PLATE_TEETH[0]
    out = []
    for k in range(count):
        a = 2.0 * math.pi * (k + 0.5) / count
        deg = math.degrees(a) % 180.0
        if min(deg, 180.0 - deg) < 17.0 or abs(deg - 90.0) < 15.0:
            continue  # under the housing or the bar
        out += _tooth(a, m)
    return out


def _block(mats: dict[str, Material]) -> list:
    """The central block: its face round the mouth, its sides, the grilles, the marked panels and the red lamps."""
    hw, hh, z = BLOCK
    frame, recess, grey = mats["bay_frame"], mats["recess"], mats["drum_grey"]
    out = annulus(((hw, hh),), mouth(0), z, -1.0, frame)
    for sx in (-1.0, 1.0):
        out.append((np.array([[sx * hw, -hh, z], [sx * hw, hh, z], [sx * hw, hh, PLATE_Z], [sx * hw, -hh, PLATE_Z]]), (sx, 0.0, 0.0), frame))
    for sy in (-1.0, 1.0):
        out.append((np.array([[-hw, sy * hh, z], [hw, sy * hh, z], [hw, sy * hh, PLATE_Z], [-hw, sy * hh, PLATE_Z]]), (0.0, sy, 0.0), frame))
    width, pitch, stand = GRILLE
    for sy in (-1.0, 1.0):  # above and below the mouth
        for x in np.arange(-44.0 + 0.5 * pitch, 44.0, pitch):
            y0, y1 = sorted((sy * 47.0, sy * 54.0))
            out += box_faces((x - 0.5 * width, y0, z - stand), (x + 0.5 * width, y1, z), recess)
    for sx in (-1.0, 1.0):  # beside it
        for y in np.arange(-24.0 + 0.5 * pitch, 24.0, pitch):
            x0, x1 = sorted((sx * 61.0, sx * 68.0))
            out += box_faces((x0, y - 0.5 * width, z - stand), (x1, y + 0.5 * width, z), recess)
    for sx in (-1.0, 1.0):  # the marked panels at the block's corners: a dark plate with pale bars
        for sy in (-1.0, 1.0):
            x0, x1 = sorted((sx * 48.0, sx * 66.0))
            y0, y1 = sorted((sy * 42.0, sy * 54.0))
            out += box_faces((x0, y0, z - 1.0), (x1, y1, z), recess)
            for k in range(2):
                yb = y0 + 3.0 + 4.0 * k
                out += box_faces((x0 + 2.0, yb, z - 1.5), (x0 + 2.0 + (11.0 if k == 0 else 6.0), yb + 1.6, z - 1.0), grey)
    lamp = mats["lamp"]
    for k in range(1, MOUTH_LAYERS):  # small red lamps on the frames' steps
        (x, y), _, _ = mouth(k)
        zl = layer_z(k)
        for sx in (-1.0, 1.0):
            for sy in (-1.0, 1.0):
                cx, cy = sx * (x + 0.5 * MOUTH_INSET), sy * 0.5 * y
                out += box_faces((cx - 0.7, cy - 0.7, zl - 1.2), (cx + 0.7, cy + 0.7, zl), lamp)
    return out


def _edge_strip(steps: Steps, width: float, z: float, facing: float, m: Material) -> list:
    """A lit strip ``width`` wide round a stepped cross's edge, just off a face in the plane ``z``."""
    return annulus(shrunk(steps, -width), steps, z + facing * EDGE_LIFT_M, facing, m)


def _mouth(mats: dict[str, Material]) -> list:
    """The funnel of frames stepping in from the block's face: dark machinery, pink-lit at its outer sides, each frame's inner edge
    lit red."""
    out = []
    for k in range(MOUTH_LAYERS - 1):
        z0, z1 = layer_z(k), layer_z(k + 1)
        out += walls(mouth(k), z0, z1, mats["bay_wall"], mats["bay_pink"] if k == 0 else None)
        out += annulus(mouth(k), mouth(k + 1), z1, -1.0, mats["bay_wall"])
        out += _edge_strip(mouth(k + 1), EDGE_STRIP_M, z1, -1.0, mats["bay_red_0"])
    return out


def _tunnel(mats: dict[str, Material]) -> list:
    """The tunnel to the airlock: dark machinery walls, the frames ringing it with their inner edges lit red (dimmer the deeper),
    and the machinery between them, a red lamp on every other block; deep shadow everywhere else."""
    t = tunnel()
    out = walls(t, layer_z(MOUTH_LAYERS - 1), TUNNEL_BACK_Z, mats["bay_wall"])
    inner = shrunk(t, RIB_INSET)
    for k, z in enumerate(RIB_Z):
        glow = mats[f"bay_red_{min(k + 1, 5)}"]
        out += annulus(t, inner, z, -1.0, mats["bay_wall"])
        out += _edge_strip(inner, EDGE_STRIP_M, z, -1.0, glow)
        out += walls(inner, z, z + RIB_DEPTH, glow)
        out += annulus(t, inner, z + RIB_DEPTH, 1.0, mats["bay_wall"])
    # Machinery between the frames: boxes on the side walls and on the main step's top and bottom, standing in less than a frame.
    (x0, y0), (x1, _), _ = t
    stand = RIB_INSET - 0.6
    starts = [layer_z(MOUTH_LAYERS - 1)] + [z + RIB_DEPTH for z in RIB_Z[:-1]]
    lamp = mats["bay_red_2"]
    for k, (za, zb) in enumerate(zip(starts, RIB_Z, strict=True)):
        za, zb = za + 2.0, zb - 2.0
        if zb - za < 4.0:
            continue
        zm = 0.5 * (za + zb)
        m = mats["recess"] if k % 2 else mats["bay_wall"]
        for sx in (-1.0, 1.0):
            xa, xb = sorted((sx * x0, sx * (x0 - stand)))
            out += box_faces((xa, -12.0, za), (xb, -3.0, zm - 1.0), m, skip_back=False)
            out += box_faces((xa, 3.0, zm + 1.0), (xb, 14.0, zb), m, skip_back=False)
            face = sx * (x0 - stand)  # a small red lamp on the face of the upper block
            out += box_faces((min(face, face - sx * 0.5), 7.0, zm + 3.0), (max(face, face - sx * 0.5), 8.2, zm + 4.2), lamp, skip_back=False)
            xa, xb = sorted((sx * (x1 + 3.0), sx * (x0 - 3.0)))
            for sy, (z0, z1) in ((1.0, (za, zm - 1.0)), (-1.0, (zm + 1.0, zb))):
                ya, yb = sorted((sy * y0, sy * (y0 - stand)))
                out += box_faces((xa, ya, z0), (xb, yb, z1), m, skip_back=False)
    return out


def saw_edge(x: np.ndarray | float) -> np.ndarray:
    """The upper airlock door's lower edge: a trapezoid wave of teeth across the tunnel."""
    height, period, _ = SAW
    t = np.mod(np.asarray(x, dtype=float) + 0.5 * period, period) / period
    rise = np.clip((t - 3.0 / 14.0) / (4.0 / 14.0), 0.0, 1.0) - np.clip((t - 10.0 / 14.0) / (4.0 / 14.0), 0.0, 1.0)
    return -0.5 * height + height * rise


def saw_breaks(x0: float, x1: float) -> list[float]:
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


def _airlock(mats: dict[str, Material]) -> list:
    """The inner airlock's two doors, dark, closed on an interlocking sawtooth seam whose edges glow red, and the dark wall seen
    through the seam."""
    t = tunnel()
    width = t[0][0]
    _, _, gap = SAW
    xs = sorted({-width, width} | {sx * x for x, _ in t for sx in (-1.0, 1.0)} | set(saw_breaks(-width, width)))
    door, dark = mats["bay_door"], mats["bay_dark"]
    out = []
    for a, b in zip(xs[:-1], xs[1:], strict=True):
        h = half_height(t, 0.5 * (a + b))
        ya, yb = float(saw_edge(a)), float(saw_edge(b))
        z = AIRLOCK_Z
        out.append((np.array([[a, ya, z], [b, yb, z], [b, h, z], [a, h, z]]), (0.0, 0.0, -1.0), door))
        out.append((np.array([[a, -h, z], [b, -h, z], [b, yb - gap, z], [a, ya - gap, z]]), (0.0, 0.0, -1.0), door))
        # The doors' edges along the seam, seen through it: the upper door's facing down, the lower's up.
        dx, dy = b - a, yb - ya
        for y_a, y_b, sign in ((ya, yb, 1.0), (ya - gap, yb - gap, -1.0)):
            normal = (sign * dy, -sign * dx, 0.0)
            out.append((np.array([[a, y_a, z], [b, y_b, z], [b, y_b, z + 4.0], [a, y_a, z + 4.0]]), normal, mats["bay_red_3"]))
    h = SAW[0]
    out.append((rect_z(-width, width, -h - gap - 1.0, h + 1.0, TUNNEL_BACK_Z), (0.0, 0.0, -1.0), dark))
    # Ribs across each door, clear of the teeth.
    main = t[0][1]
    for y in np.arange(0.5 * h + 4.0, main - 1.0, 4.0):
        for sy in (-1.0, 1.0):
            y0, y1 = sorted((sy * y, sy * (y + 1.2)))
            out += box_faces((-width + 1.0, y0, AIRLOCK_Z - 0.8), (width - 1.0, y1, AIRLOCK_Z), mats["bay_wall"])
    return out


def _housing(mats: dict[str, Material]) -> list:
    """The long housing across the plate, the bar up and down it, and the lower hatch on the bar."""
    frame, recess, machinery = mats["bay_frame"], mats["recess"], mats["machinery"]
    bw, bh, _ = BLOCK
    hw, hh, hz = HOUSING
    out = []
    for sx in (-1.0, 1.0):
        x0, x1 = sorted((sx * bw, sx * hw))
        out += box_faces((x0, -hh, hz), (x1, hh, PLATE_Z), frame)
        for k in range(5):  # ribs across each arm
            xr = sx * (bw + 10.0 + 11.0 * k)
            out += box_faces((xr - 1.5, -hh - 1.0, hz - 1.5), (xr + 1.5, hh + 1.0, hz + 6.0), recess)
    uw, uh, uz = BAR_UP
    out += box_faces((-uw, bh, uz), (uw, uh, PLATE_Z), frame)
    dw, dh, dz = BAR_DOWN
    out += box_faces((-dw, -dh, dz), (dw, -bh, PLATE_Z), frame)
    xw, ytop, ybot = HATCH
    out += box_faces((-xw - 3.0, -ybot - 3.0, dz - 2.0), (xw + 3.0, -ybot, dz), frame)  # the hatch's frame
    out += box_faces((-xw - 3.0, -ytop, dz - 2.0), (xw + 3.0, -ytop + 3.0, dz), frame)
    for sx in (-1.0, 1.0):
        x0, x1 = sorted((sx * xw, sx * (xw + 3.0)))
        out += box_faces((x0, -ybot, dz - 2.0), (x1, -ytop, dz), frame)
    out.append((rect_z(-xw, xw, -ybot, -ytop, dz - 0.4), (0.0, 0.0, -1.0), recess))  # its leaf, dark, just off the bar
    for x in (-12.0, 0.0, 12.0):  # machinery behind its grating
        out += box_faces((x - 2.0, -ybot + 4.0, dz - 1.6), (x + 2.0, -ytop - 4.0, dz - 0.4), machinery)
    return out


def main_docking_bay(mats: dict[str, Material]) -> Mesh:
    """The main docking bay at the bow (turns with the drum)."""
    plate = mats["drum_grey"]
    faces = _plate(plate) + _teeth(mats["recess"]) + _block(mats) + _mouth(mats) + _tunnel(mats) + _airlock(mats) + _housing(mats)
    return polys(faces)


# --- the cargo bay (zero-gravity) ----------------------------------------------------------------------------------------
# Between the bow's two forks, cut into the spine's front where the slot ends (the STL's stepped recess at the fork's root; the look
# from the maintainer's show capture, ``references/zero g cargo bay references/``): an open box, open to the slot ahead and to space
# above, with a thick greebled rim and stepped machinery on its floor, dark with red and pink on its edges and lamps. Saturn
# freighters hold outside and their cargo pods (31.1 x 17.2 x 43.0 m, ``saturn.POD``) fly in by themselves (Q8 as refined).
ZG_FRONT_Z = 420.0  # the spine's front, the slot's end
ZG_BACK_Z = 490.0  # deep enough to take a whole pod (43 m) with room to spare
ZG_HALF_X = 30.0  # the bay's inner half width: a pod square-on with 14 m to spare each side, inside the slot (x +-45)
ZG_FLOOR_Y = 322.0  # 11 m over the spine's underside at its front
ZG_MACHINE_M = 4.0  # the floor's machinery stands up to this
ZG_RIM = (8.0, 4.0, 8.0)  # the rim's width, how far it stands over the spine's top, and its posts' depth at the front
ZG_CENTRE_Y = 346.0  # the pods' path: over the machinery, under the spine's top (368 to 374 here)


def zg_top(z: float) -> float:
    """The spine's top over the bay at ``z``."""
    from . import station as st_  # noqa: PLC0415

    return st_.spine_row_at(z)[3]


def cargo_bay_walls(m: Material) -> Mesh:
    """The spine's front from the slot's end to the bay's back round the open bay: under its floor and beside it (the spine itself
    starts at its back)."""
    from . import station as st_  # noqa: PLC0415

    hx, floor = ZG_HALF_X, ZG_FLOOR_Y
    rows = [st_.spine_row_at(ZG_FRONT_Z), st_.spine_row_at(ZG_BACK_Z)]
    return Mesh.concatenate([
        st_.slab([(z, -w, w, under, floor) for z, w, under, _ in rows], m),
        st_.slab([(z, -w, -hx, floor, top) for z, w, _, top in rows], m),
        st_.slab([(z, hx, w, floor, top) for z, w, _, top in rows], m),
    ])


def _rim(mats: dict[str, Material]) -> list:
    """The thick rim round the bay's open sides: posts and a sill round its front, beams along its top edges and across its back,
    greebles along them."""
    frame, recess = mats["bay_frame"], mats["recess"]
    hx, floor = ZG_HALF_X, ZG_FLOOR_Y
    rw, rise, depth = ZG_RIM
    front, back = ZG_FRONT_Z, ZG_BACK_Z
    top0, top1 = zg_top(front), zg_top(back)
    out = []
    for sx in (-1.0, 1.0):  # the front posts
        x0, x1 = sorted((sx * hx, sx * (hx + rw)))
        out += box_faces((x0, floor - 6.0, front - depth), (x1, top0 + rise, front), frame, skip_back=False)
    out += box_faces((-hx - rw, floor - 6.0, front - depth), (hx + rw, floor + 1.0, front), frame, skip_back=False)  # the sill
    for sx in (-1.0, 1.0):  # the beams along the top edges, following the spine's slope
        x0, x1 = sorted((sx * hx, sx * (hx + rw)))
        q = [np.array(v) for v in ((x0, top0, front), (x1, top0, front), (x1, top1, back), (x0, top1, back))]
        lid = [p + [0.0, rise, 0.0] for p in q]
        out.append((np.array(lid), (0.0, 1.0, 0.0), frame))
        for a, b, normal in ((0, 3, (-1.0, 0.0, 0.0)), (1, 2, (1.0, 0.0, 0.0))):
            out.append((np.array([q[a], q[b], lid[b], lid[a]]), normal, frame))
        for z in np.arange(front + 6.0, back - 4.0, 8.0):  # greebles along the beam
            t = float(np.interp(z, [front, back], [top0, top1])) + rise
            out += box_faces((min(x0, x1) + 2.0, t, z - 1.2), (max(x0, x1) - 2.0, t + 1.6, z + 1.2), recess, skip_back=False)
    out += box_faces((-hx - rw, top1 - 2.0, back - 4.0), (hx + rw, top1 + rise, back + 4.0), frame, skip_back=False)  # across the back
    return out


def _zg_machinery(mats: dict[str, Material]) -> list:
    """The stepped machinery on the bay's floor and its walls: dark blocks in tiers, a red strip on each block's front edge, pink
    and red lamps among them, ribs up the walls with red edges."""
    dark, wall, recess = mats["bay_wall"], mats["bay_wall"], mats["recess"]
    red, pink = mats["bay_red_2"], mats["bay_pink"]
    hx, floor = ZG_HALF_X, ZG_FLOOR_Y
    out = []
    xs = np.linspace(-hx + 1.0, hx - 1.0, 7)
    zs = np.arange(ZG_FRONT_Z + 4.0, ZG_BACK_Z - 2.0, 8.0)
    for i, (xa, xb) in enumerate(zip(xs[:-1], xs[1:], strict=True)):
        for k, za in enumerate(zs[:-1]):
            h = 1.0 + 3.0 * (0.5 + 0.5 * math.sin(1.7 * i + 2.3 * k)) * min(1.0, (k + 1) / 3.0)  # tiers stepping up toward the back
            lo, hi = (xa + 0.4, floor, za + 0.4), (xb - 0.4, floor + h, za + 7.6)
            out += box_faces(lo, hi, dark if (i + k) % 3 else recess, skip_back=False)
            out += box_faces((lo[0], hi[1] - 0.3, lo[2] - 0.05), (hi[0], hi[1], lo[2] + 0.4), red, skip_back=False)
            if (i * 3 + k) % 7 == 2:
                cx, cz = 0.5 * (xa + xb), za + 4.0
                out += box_faces((cx - 0.8, hi[1], cz - 0.8), (cx + 0.8, hi[1] + 0.8, cz + 0.8), pink, skip_back=False)
    for sx in (-1.0, 1.0):
        x0, x1 = sorted((sx * hx, sx * (hx - 1.2)))
        for z in np.arange(ZG_FRONT_Z + 10.0, ZG_BACK_Z - 4.0, 12.0):
            top = zg_top(z)
            out += box_faces((x0, floor + ZG_MACHINE_M, z - 1.0), (x1, top - 2.0, z + 1.0), wall, skip_back=False)
            edge = sx * (hx - 1.2)
            out += box_faces((min(edge, edge - sx * 0.3), floor + ZG_MACHINE_M, z - 1.0), (max(edge, edge - sx * 0.3), top - 2.0, z - 0.6),
                             red, skip_back=False)
    for x in (-18.0, -6.0, 6.0, 18.0):  # red lamps along the back wall
        out += box_faces((x - 1.0, floor + 14.0, ZG_BACK_Z - 0.6), (x + 1.0, floor + 16.0, ZG_BACK_Z), mats["lamp"], skip_back=False)
    return out


def cargo_bay(mats: dict[str, Material]) -> Mesh:
    """The bay's rim and the machinery inside it."""
    return polys(_rim(mats) + _zg_machinery(mats))


# --- the command section ----------------------------------------------------------------------------------------------
# The bow spine over the docking sphere (Q2: it holds from 50 m): open machinery compartments along its top (the STL's recesses, the
# Mallacore render's lit bays of tanks and coils) and serrated lower edges along the forks.
COMPARTMENTS = ((0.0, 610.0, 22.0, 15.0), (0.0, 780.0, 30.0, 22.0), (0.0, 905.0, 30.0, 20.0))  # x, z, half width, half length
COMPARTMENT_RIM = (3.0, 4.0)  # the rim's thickness and height
FORK_TEETH = (14.0, 8.0, 5.0)  # pitch, base, how far each tooth hangs below the fork's outer lower edge


def _compartment(x: float, z: float, hw: float, hl: float, mats: dict[str, Material]) -> list:
    """An open compartment on the spine's top: a rim round a dark floor, tanks and a coil housing inside, a red lamp."""
    from . import station as st_  # noqa: PLC0415

    top = max(st_.spine_row_at(z - hl)[3], st_.spine_row_at(z + hl)[3])
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
        out += box_faces((tx - 3.4, top + 0.3, z - 0.1 * hl - 1.0), (tx + 3.4, top + 6.0, z - 0.1 * hl + 1.0), recess, skip_back=False)
    out += box_faces((x + hw - 2.0, top + 0.3, z + hl - 2.0), (x + hw - 0.5, top + 1.8, z + hl - 0.5), mats["lamp"], skip_back=False)
    return out


def _fork_teeth(m: Material) -> list:
    """Sawtooth teeth hanging along each fork's outer lower edge."""
    pitch, base, drop = FORK_TEETH
    rows = [(0.0, 62.0, 312.0), (200.0, 115.0, 311.0), (430.0, 172.0, 311.0)]  # z, the outer edge's x, the underside (bow_mesh)
    out = []
    for z in np.arange(20.0, 420.0, pitch):
        xe = float(np.interp(z, [r[0] for r in rows], [r[1] for r in rows]))
        y = float(np.interp(z, [r[0] for r in rows], [r[2] for r in rows]))
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


__all__ = ["AIRLOCK_Z", "BLOCK", "MOUTH", "ZG_HALF_X", "cargo_bay", "cargo_bay_walls", "clear_passage", "command_detail", "half_height", "main_docking_bay", "mouth",
           "plinth", "saw_edge", "tunnel"]
