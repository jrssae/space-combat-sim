"""Hull parts: lofted fuselage, cockpit canopy (exterior dome) and the cockpit interior mesh.

Local frames: the fuselage runs along Z (nose at -Z); its cross-sections are rounded rectangles
(superellipses). The canopy sits with its base plane at ``y = 0``, nose end at ``-length/2``.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from itertools import pairwise

import numpy as np

from ..core.geometry import (
    Material,
    Mesh,
    _fan_faces,
    _quad_faces,
    box,
    inset_convex_polygon,
    lathe,
    loft,
    superellipse_ring,
    sweep_rect,
    unit,
)
from ..styles import Style
from . import Anchor, Collision, Part


@dataclass(frozen=True)
class FuselageSection:
    z: float
    width: float
    height: float
    y_offset: float = 0.0


@dataclass(frozen=True)
class FuselageSpec:
    """Sections front to back; a section with zero width/height is a pole (pointed end)."""

    sections: tuple[FuselageSection, ...]
    ring_points: int = 40
    exponent: float = 4.0
    mass_kg: float = 16_600.0

    def __post_init__(self) -> None:
        zs = [s.z for s in self.sections]
        if len(zs) < 2 or any(b <= a for a, b in pairwise(zs)):
            raise ValueError("fuselage sections must increase in z")

    @property
    def nose_z(self) -> float:
        return self.sections[0].z

    @property
    def tail_z(self) -> float:
        return self.sections[-1].z

    @property
    def length(self) -> float:
        return self.tail_z - self.nose_z

    def section_at(self, z: float) -> FuselageSection:
        """Linear interpolation of width/height/offset at ``z`` (clamped to the ends)."""
        zs = np.array([s.z for s in self.sections])
        z = float(np.clip(z, zs[0], zs[-1]))
        w = float(np.interp(z, zs, [s.width for s in self.sections]))
        h = float(np.interp(z, zs, [s.height for s in self.sections]))
        yo = float(np.interp(z, zs, [s.y_offset for s in self.sections]))
        return FuselageSection(z, w, h, yo)

    def top_y(self, z: float, x: float = 0.0) -> float:
        s = self.section_at(z)
        return s.y_offset + 0.5 * s.height * self._lateral(s, x)

    def bottom_y(self, z: float, x: float = 0.0) -> float:
        s = self.section_at(z)
        return s.y_offset - 0.5 * s.height * self._lateral(s, x)

    def half_width(self, z: float) -> float:
        return 0.5 * self.section_at(z).width

    def _lateral(self, s: FuselageSection, x: float) -> float:
        if s.width == 0.0:
            return 0.0
        t = min(abs(x) / (0.5 * s.width), 1.0)
        return (1.0 - t**self.exponent) ** (1.0 / self.exponent)

    def max_width(self) -> float:
        return max(s.width for s in self.sections)

    def max_height(self) -> float:
        return max(s.height for s in self.sections)


def fuselage(spec: FuselageSpec, style: Style) -> Part:
    """Smooth lofted fuselage; the tail is a flat dark cap, a zero-size nose section is a point."""
    rings = []
    for s in spec.sections:
        if s.width == 0.0 or s.height == 0.0:
            rings.append(np.array([[0.0, s.y_offset, s.z]]))
            continue
        xy = superellipse_ring(s.width, s.height, spec.ring_points, spec.exponent)
        rings.append(np.column_stack([xy[:, 0], xy[:, 1] + s.y_offset, np.full(len(xy), s.z)]))
    pole_front = rings[0].shape[0] == 1
    pole_back = rings[-1].shape[0] == 1
    mesh = loft(
        rings,
        style.material("hull"),
        cap_start=not pole_front,
        cap_end=not pole_back,
        cap_material=style.material("hull_dark"),
    )
    mid = spec.section_at(0.5 * (spec.nose_z + spec.tail_z))
    center = np.array([0.0, mid.y_offset, 0.5 * (spec.nose_z + spec.tail_z)])
    return Part(
        "fuselage",
        mesh,
        anchors={
            "nose": Anchor([0.0, spec.sections[0].y_offset, spec.nose_z], [0.0, 0.0, -1.0]),
            "tail": Anchor([0.0, spec.sections[-1].y_offset, spec.tail_z], [0.0, 0.0, 1.0]),
            "center": Anchor(center),
        },
        collision=[
            Collision("box", center, size=[spec.max_width(), spec.max_height(), spec.length], name="fuselage")
        ],
        mass_kg=spec.mass_kg,
    )


# --- canopy ----------------------------------------------------------------------------------
@dataclass(frozen=True)
class CanopySpec:
    """Half-ellipsoid bubble on a base plane (``y = 0``), long axis along Z.

    ``sink`` is how far the ellipsoid centre sits below the base plane, so the dome meets the
    hull with a near-vertical wall rather than a tangent. ``hoops`` are transverse frame bars
    at fractions of the length (0 = front); the base rim is a frame too.
    """

    length: float = 2.2
    width: float = 0.9
    height: float = 0.55
    sink: float = 0.08
    frame_width: float = 0.07
    rim_height: float = 0.06
    hoops: tuple[float, ...] = (0.24, 0.78)
    eye_fraction: float = 0.62
    eye_height: float = 0.3
    arc_points: int = 25
    z_rings: int = 26
    mass_kg: float = 400.0
    dash_height: float = 0.2
    dash_depth: float = 0.3
    dash_width: float = 0.7
    dash_ahead: float = 0.55  # from the eye, forward
    frame_depth: float = 0.05  # interior frame bars, radial

    @property
    def semi_axes(self) -> tuple[float, float, float]:
        return 0.5 * self.width, self.height + self.sink, 0.5 * self.length

    @property
    def footprint_scale(self) -> float:
        """Scale of the base-plane ellipse relative to the ellipsoid's equator."""
        _, c, _ = self.semi_axes
        return math.sqrt(max(1.0 - (self.sink / c) ** 2, 0.0))

    @property
    def eye(self) -> np.ndarray:
        return np.array([0.0, self.eye_height, -0.5 * self.length + self.eye_fraction * self.length])

    def hoop_z(self, fraction: float) -> float:
        return -0.5 * self.length + fraction * self.length

    def arc(self, z: float, inset: float = 0.0, y_min: float = 0.0, points: int | None = None) -> np.ndarray:
        """Points ``(n, 3)`` of the dome cross-section at ``z`` from right (+X) over the top to
        left, starting/ending at ``y = y_min``; ``inset`` shrinks the ellipse (interior parts).
        Returns an empty array where the dome does not reach ``y_min``."""
        a, c, b = self.semi_axes
        s = math.sqrt(max(1.0 - (z / b) ** 2, 0.0))
        az, cz = a * s - inset, c * s - inset
        if cz <= 0.0 or az <= 0.0 or cz - self.sink <= y_min:
            return np.zeros((0, 3))
        phi0 = math.asin(min((y_min + self.sink) / cz, 1.0))
        n = points or self.arc_points
        phi_rim = math.asin(min((self.rim_height + self.sink) / cz, 1.0))
        inner = np.linspace(phi_rim, math.pi - phi_rim, max(n - 2, 2))
        phis = np.concatenate([[phi0], inner, [math.pi - phi0]])
        return np.column_stack([az * np.cos(phis), cz * np.sin(phis) - self.sink, np.full(len(phis), z)])


def _canopy_z_grid(spec: CanopySpec) -> np.ndarray:
    """Z stations for the dome loft: cosine spaced plus exact hoop band edges."""
    _, _, b = spec.semi_axes
    z_end = b * spec.footprint_scale
    t = np.linspace(0.0, math.pi, spec.z_rings + 1)
    stations = {float(z) for z in -z_end * np.cos(t)}
    for h in spec.hoops:
        for edge in (spec.hoop_z(h) - 0.5 * spec.frame_width, spec.hoop_z(h) + 0.5 * spec.frame_width):
            if -z_end < edge < z_end:
                stations.add(edge)
    grid = np.array(sorted(stations))
    # Drop stations closer than 1 cm to a neighbour (keep the exact hoop edges).
    keep = [grid[0]]
    for z in grid[1:]:
        if z - keep[-1] > 0.01 or z == grid[-1]:
            keep.append(z)
    return np.array(keep)


def canopy(spec: CanopySpec, style: Style) -> Part:
    """Exterior canopy dome: tinted glass panes between dark frame hoops and a base rim."""
    glass, frame = style.material("canopy_glass"), style.material("canopy_frame")
    zs = _canopy_z_grid(spec)
    verts: list[np.ndarray] = []
    idx: list[np.ndarray] = []
    for k, z in enumerate(zs):
        start = sum(len(v) for v in verts)
        if k in (0, len(zs) - 1):
            verts.append(np.array([[0.0, 0.0, z]]))
            idx.append(np.array([start]))
            continue
        arc = spec.arc(z)
        if len(arc) == 0:
            raise ValueError("canopy arc vanished inside the footprint")
        verts.append(arc)
        idx.append(start + np.arange(len(arc)))
    faces: list[np.ndarray] = []
    face_z: list[np.ndarray] = []
    face_rim: list[np.ndarray] = []
    for k in range(len(zs) - 1):
        a, b = idx[k], idx[k + 1]
        if len(a) == 1:
            f = _fan_faces(b, int(a[0]), closed=False, apex_first=True)
            rim = np.zeros(len(f), dtype=bool)
            rim[[0, len(f) - 1]] = True
        elif len(b) == 1:
            f = _fan_faces(a, int(b[0]), closed=False, apex_first=False)
            rim = np.zeros(len(f), dtype=bool)
            rim[[0, len(f) - 1]] = True
        else:
            f = _quad_faces(a, b, closed=False)
            n = len(a) - 1
            rim = np.zeros(len(f), dtype=bool)
            rim[[0, n - 1, n, 2 * n - 1]] = True  # first/last quad of the strip touch the rim
        faces.append(f)
        face_z.append(np.full(len(f), 0.5 * (zs[k] + zs[k + 1])))
        face_rim.append(rim)
    faces_arr = np.concatenate(faces)
    fz = np.concatenate(face_z)
    is_frame = np.concatenate(face_rim)
    for h in spec.hoops:
        is_frame |= np.abs(fz - spec.hoop_z(h)) < 0.5 * spec.frame_width
    mesh = Mesh(
        np.concatenate(verts), faces_arr, np.where(is_frame, 1, 0).astype(np.int64), (glass, frame)
    )
    return Part(
        "canopy",
        mesh,
        anchors={
            "eye": Anchor(spec.eye, [0.0, 0.0, -1.0]),
            "base_center": Anchor([0.0, 0.0, 0.0]),
            "front": Anchor([0.0, 0.0, zs[0]]),
            "rear": Anchor([0.0, 0.0, zs[-1]]),
            "top": Anchor([0.0, spec.height, 0.0], [0.0, 1.0, 0.0]),
        },
        mass_kg=spec.mass_kg,
    )


def _sweep_bar(
    path: np.ndarray, outward: np.ndarray, width_dir: np.ndarray, width: float, depth: float, material_index: int
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """A rectangular bar along ``path`` (open polyline): ``depth`` inward from the path along
    ``-outward``, ``width`` across ``width_dir``. Returns (vertices, faces, face materials)."""
    n = len(path)
    w = unit(width_dir) * (0.5 * width)
    d = unit(outward) * depth
    rails = [path + w, path + w - d, path - w - d, path - w]
    verts = np.concatenate(rails)
    rings = [np.arange(n) + k * n for k in range(4)]
    i = np.arange(n - 1)
    faces = []
    for k in range(4):
        r0, r1 = rings[k], rings[(k + 1) % 4]
        faces.append(np.stack([r0[i], r1[i], r1[i + 1]], axis=1))
        faces.append(np.stack([r0[i], r1[i + 1], r0[i + 1]], axis=1))
    for end, forward in ((0, False), (n - 1, True)):
        quad = np.array([rings[k][end] for k in range(4)])
        tri = np.array([[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]])
        faces.append(tri if forward else tri[:, ::-1])
    faces_arr = np.concatenate(faces)
    return verts, faces_arr, np.full(len(faces_arr), material_index, dtype=np.int64)


def cockpit_interior(spec: CanopySpec, style: Style) -> Mesh:
    """Frame ring at the base, one bar per hoop inside the dome, and a dash slab ahead of the
    eye. Surfaces face the pilot (ring band normals point inwards; bars and dash are solids)."""
    interior = style.material("interior")
    frame = style.material("canopy_frame")
    materials = (interior, frame)
    verts: list[np.ndarray] = []
    faces: list[np.ndarray] = []
    mats: list[np.ndarray] = []

    def add(v: np.ndarray, f: np.ndarray, m: np.ndarray) -> None:
        offset = sum(len(x) for x in verts)
        verts.append(v)
        faces.append(f + offset)
        mats.append(m)

    # Base ring: a band just inside the footprint, from the base plane up to the rim height.
    a, _, b = spec.semi_axes
    q = spec.footprint_scale
    inset = 0.02
    t = 2.0 * math.pi * np.arange(48) / 48
    ring_lo = np.column_stack([(a * q - inset) * np.cos(t), np.zeros(48), (b * q - inset) * np.sin(t)])
    ring_hi = ring_lo + np.array([0.0, spec.rim_height, 0.0])
    lo, hi = np.arange(48), 48 + np.arange(48)
    band = _quad_faces(lo, hi, closed=True)  # this ring order gives normals facing the axis
    add(np.concatenate([ring_lo, ring_hi]), band, np.ones(len(band), dtype=np.int64))

    # Hoop bars: follow the dome cross-section, set slightly inside it.
    for h in spec.hoops:
        path = spec.arc(spec.hoop_z(h), inset=inset, y_min=spec.rim_height, points=19)
        if len(path) < 2:
            continue
        centre = np.array([0.0, -spec.sink, spec.hoop_z(h)])
        outward = unit(path - centre)
        v, f, m = _sweep_bar(path, outward, np.array([0.0, 0.0, 1.0]), spec.frame_width, spec.frame_depth, 1)
        add(v, f, m)

    # Dash slab: a box ahead of and below the eye line.
    eye = spec.eye
    dash = box(
        [spec.dash_width, spec.dash_height, spec.dash_depth],
        interior,
        center=[0.0, 0.5 * spec.dash_height, eye[2] - spec.dash_ahead],
    )
    add(dash.vertices, dash.faces, np.zeros(dash.face_count, dtype=np.int64))

    return Mesh(np.concatenate(verts), np.concatenate(faces), np.concatenate(mats), materials)


# Rotation taking local +Z to +Y (and +Y to -Z), for parts built as lathes along Z.
_Z_TO_Y = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]])


def cockpit_tub(spec: CanopySpec, style: Style, depth: float = 0.35, lip: float = 0.03) -> Part:
    """Dark elliptical well under the canopy. Its top face sits ``lip`` above the base plane, so
    what shows through the glass panes is a dark cockpit floor rather than the hull top; the
    sides are hidden inside the fuselage. Same local frame as :func:`canopy`."""
    a, _, b = spec.semi_axes
    q = spec.footprint_scale
    inset = 0.04
    profile = [(-depth, 0.0), (-depth, 1.0), (lip, 1.0), (lip, 0.0)]
    mesh = lathe(profile, 48, style.material("interior"), creases={1, 2})
    mesh = mesh.transformed(_Z_TO_Y).transformed(np.diag([a * q - inset, 1.0, b * q - inset]))
    return Part(
        "cockpit_tub",
        mesh,
        anchors={"floor": Anchor([0.0, lip, 0.0], [0.0, 1.0, 0.0])},
    )


# --- upright cylinder hull (buoys; later beacons, cargo pods) --------------------------------
@dataclass(frozen=True)
class CylinderHullSpec:
    """An upright drum along local +Y, centred on the origin: a straight barrel of ``barrel_height``
    with a conical shoulder of ``cap_height`` at each end, narrowing to a flat end plate of
    ``end_radius`` (where masts mount). ``bands`` paint fractions of the barrel (0 = bottom,
    1 = top) with a style role, e.g. ``((0.1, 0.18, "stripe"),)`` for a hazard stripe; the rest of
    the barrel is ``body_role`` and the shoulders and plates are ``cap_role``."""

    barrel_height: float = 2.4
    radius: float = 0.4
    cap_height: float = 0.3
    end_radius: float = 0.16
    segments: int = 36
    bands: tuple[tuple[float, float, str], ...] = ()
    body_role: str = "hull"
    cap_role: str = "hull_dark"
    mass_kg: float = 0.0

    def __post_init__(self) -> None:
        if min(self.barrel_height, self.radius, self.cap_height, self.end_radius) <= 0.0:
            raise ValueError("cylinder hull dimensions must be positive")
        if self.end_radius >= self.radius:
            raise ValueError("the end plate must be narrower than the barrel")
        for lo, hi, _ in self.bands:
            if not 0.0 <= lo < hi <= 1.0:
                raise ValueError(f"band ({lo}, {hi}) must satisfy 0 <= lo < hi <= 1")

    @property
    def total_height(self) -> float:
        return self.barrel_height + 2.0 * self.cap_height

    def role_at(self, fraction: float) -> str:
        """Material role of the barrel at a height fraction (the first band containing it wins)."""
        for lo, hi, role in self.bands:
            if lo <= fraction <= hi:
                return role
        return self.body_role


def cylinder_hull(spec: CylinderHullSpec, style: Style) -> Part:
    """Upright drum (see :class:`CylinderHullSpec`). Anchors: ``top``/``bottom`` (end plate
    centres, pointing out along +-Y), ``center``, ``side_right``/``side_left`` (barrel surface at
    mid height, pointing out along +-X). One capsule collision primitive along Y."""
    half_total = 0.5 * spec.total_height
    half_barrel = 0.5 * spec.barrel_height
    # A barrel station at every band edge, so each band is an exact ring of faces.
    fractions = {0.0, 1.0}
    for lo, hi, _ in spec.bands:
        fractions.update((lo, hi))
    barrel = sorted(fractions)
    profile = [(-half_total, 0.0), (-half_total, spec.end_radius)]
    profile += [(-half_barrel + f * spec.barrel_height, spec.radius) for f in barrel]
    profile += [(half_total, spec.end_radius), (half_total, 0.0)]
    cap = style.material(spec.cap_role)
    materials = [cap, cap]  # bottom plate, bottom shoulder
    materials += [style.material(spec.role_at(0.5 * (a + b))) for a, b in pairwise(barrel)]
    materials += [cap, cap]  # top shoulder, top plate
    n = len(profile)
    creases = {1, 2, n - 3, n - 2}  # hard edges at the plates and the shoulders
    # Built along Z (bottom at -Z), then stood up: _Z_TO_Y takes +Z to +Y.
    mesh = lathe(profile, spec.segments, materials, creases=creases).transformed(_Z_TO_Y)
    return Part(
        "cylinder_hull",
        mesh,
        anchors={
            "top": Anchor([0.0, half_total, 0.0], [0.0, 1.0, 0.0]),
            "bottom": Anchor([0.0, -half_total, 0.0], [0.0, -1.0, 0.0]),
            "center": Anchor([0.0, 0.0, 0.0]),
            "side_right": Anchor([spec.radius, 0.0, 0.0], [1.0, 0.0, 0.0]),
            "side_left": Anchor([-spec.radius, 0.0, 0.0], [-1.0, 0.0, 0.0]),
        },
        collision=[
            Collision("capsule", [0.0, 0.0, 0.0], _Z_TO_Y, radius=spec.radius, height=spec.total_height, name="hull")
        ],
        mass_kg=spec.mass_kg,
    )


# --- wedge fuselage with a faceted cockpit window (Starfury-style) ---------------------------
# Facet kinds around a wedge station ring, starting at the keel centre and running counter-
# clockwise seen from behind (+Z): right half up to the top centre, then the left half down.
WEDGE_FACETS: tuple[str, ...] = (
    "keel", "keel_chamfer", "lower", "shoulder_chamfer", "upper", "top_chamfer", "top",
    "top", "top_chamfer", "upper", "shoulder_chamfer", "lower", "keel_chamfer", "keel",
)  # fmt: skip
# The two facets each chamfer runs between.
CHAMFER_NEIGHBOURS: dict[str, tuple[str, str]] = {
    "keel_chamfer": ("keel", "lower"),
    "shoulder_chamfer": ("lower", "upper"),
    "top_chamfer": ("upper", "top"),
}


@dataclass(frozen=True)
class WedgeStation:
    """One cross-section of a wedge fuselage, symmetric about x = 0: a heater-shield outline
    with a flat top, upper sides slanting out to the shoulder (the widest point) and lower sides
    slanting in to a narrower flat keel. The fuselage spec chamfers every corner.

    ``rake`` (radians) leans the station back: a point ``h`` above the keel sits at
    ``z + h * tan(rake)``. The first station of a fuselage with a window is the front pane, so a
    raked first station gives a pane that faces forward and up."""

    z: float
    top: float
    top_half_width: float
    shoulder_half_width: float
    shoulder_y: float
    keel_half_width: float
    keel: float
    rake: float = 0.0

    def __post_init__(self) -> None:
        if not self.keel < self.shoulder_y < self.top:
            raise ValueError("wedge station needs keel < shoulder_y < top")
        if min(self.top_half_width, self.keel_half_width) <= 0.0:
            raise ValueError("wedge station half-widths must be positive")
        if self.shoulder_half_width <= max(self.top_half_width, self.keel_half_width):
            raise ValueError("the shoulder must be the widest point of a wedge station")

    def corners(self) -> np.ndarray:
        """Right-half outline without chamfers: keel centre, keel corner, shoulder, top corner, top centre."""
        return np.array(
            [
                [0.0, self.keel],
                [self.keel_half_width, self.keel],
                [self.shoulder_half_width, self.shoulder_y],
                [self.top_half_width, self.top],
                [0.0, self.top],
            ]
        )

    def ring_2d(self, chamfer: float) -> np.ndarray:
        """The full chamfered outline ``(14, 2)``, counter-clockwise seen from +Z; facet ``j`` runs
        from point ``j`` to point ``j + 1`` and has kind ``WEDGE_FACETS[j]``."""
        c = self.corners()
        half = [c[0]]
        for k in (1, 2, 3):
            prev_edge, next_edge = c[k - 1] - c[k], c[k + 1] - c[k]
            limit = 0.45 * min(
                float(np.linalg.norm(prev_edge)), float(np.linalg.norm(next_edge))
            )
            if chamfer >= limit:
                raise ValueError(
                    f"chamfer {chamfer} is too wide for this station (max {limit:.3f})"
                )
            half.append(c[k] + chamfer * prev_edge / np.linalg.norm(prev_edge))
            half.append(c[k] + chamfer * next_edge / np.linalg.norm(next_edge))
        half.append(c[4])
        right = np.array(half)  # K0, K1a, K1b, Sa, Sb, Ta, Tb, T0
        left = right[1:7][::-1] * np.array([-1.0, 1.0])
        return np.concatenate([right, left])

    def lift(self, xy: np.ndarray) -> np.ndarray:
        """2D outline points of this station to 3D (applies the rake)."""
        xy = np.asarray(xy, dtype=float).reshape(-1, 2)
        z = self.z + (xy[:, 1] - self.keel) * math.tan(self.rake)
        return np.column_stack([xy, z])

    @staticmethod
    def lerp(a: WedgeStation, b: WedgeStation, t: float) -> WedgeStation:
        names = (
            "z",
            "top",
            "top_half_width",
            "shoulder_half_width",
            "shoulder_y",
            "keel_half_width",
            "keel",
            "rake",
        )
        return WedgeStation(
            *((1.0 - t) * getattr(a, n) + t * getattr(b, n) for n in names)
        )


@dataclass(frozen=True)
class WedgeFuselageSpec:
    """A faceted fuselage lofted through ``stations`` (nose first): an arrowhead from above when
    the stations widen aft, a wedge from the side when they deepen aft.

    With ``window_end > 0`` the segment from station 0 to station ``window_end`` is the cockpit:
    the first station's face is the front pane, the segment's ``glass_facets`` are side and roof
    panes, every chamfer next to a pane is a frame bar, and a ``frame_width`` band frames the
    front pane and the rear edge of the panes. The pilot's ``eye`` must lie inside that segment.
    A dark lining just inside the segment's other facets (the sill) and a bulkhead at the rear
    station make the cockpit read as an interior through the glass.

    A front pane that is wider at the top than at the keel (shoulder just under the top), with
    ``lower`` side panes, gives the Starfury view: a broad trapezoid ahead, framed by struts that
    run from the upper corners inwards and down, side panes beyond them, a bar across the top
    and the sill below."""

    stations: tuple[WedgeStation, ...]
    chamfer: float = 0.05
    window_end: int = 1
    frame_width: float = 0.07
    lining_inset: float = 0.03
    eye: tuple[float, float, float] = (0.0, 0.0, 0.0)
    glass_facets: tuple[str, ...] = ("upper", "top")
    mass_kg: float = 16_000.0

    def __post_init__(self) -> None:
        zs = [s.z for s in self.stations]
        if len(zs) < 2 or any(b <= a for a, b in pairwise(zs)):
            raise ValueError("wedge stations must increase in z")
        if not 0 <= self.window_end < len(self.stations):
            raise ValueError("window_end must index a station")
        if not set(self.glass_facets) <= {"keel", "lower", "upper", "top"}:
            raise ValueError(
                "glass_facets must be keel, lower, upper or top (chamfers are frames)"
            )
        for s in self.stations:
            s.ring_2d(self.chamfer)  # validates the chamfer
        if self.window_end:
            ex, _, ez = self.eye
            if (
                ex != 0.0
                or not self.stations[0].z < ez < self.stations[self.window_end].z
            ):
                raise ValueError(
                    "the eye must be on the centre line inside the window segment"
                )
            if not self.contains(np.array([self.eye]), margin=0.05)[0]:
                raise ValueError("the eye must be inside the fuselage")
            outer, inner = _window_cap_rings(self)
            e_out = np.roll(outer[:, :2], -1, axis=0) - outer[:, :2]
            e_in = np.roll(inner[:, :2], -1, axis=0) - inner[:, :2]
            if np.any(
                np.einsum("ij,ij->i", e_out, e_in) <= 0.0
            ):  # an inset edge flipped over
                raise ValueError(
                    "frame_width is too wide for the front pane's chamfers"
                )

    @property
    def glass(self) -> frozenset[str]:
        """Facet kinds that are panes in the window segment."""
        return frozenset(self.glass_facets)

    @property
    def frames(self) -> frozenset[str]:
        """Chamfer kinds that are frame bars in the window segment: those next to a pane."""
        return frozenset(
            c
            for c, (a, b) in CHAMFER_NEIGHBOURS.items()
            if a in self.glass or b in self.glass
        )

    @property
    def lined(self) -> frozenset[str]:
        """Facet kinds of the window segment that are neither pane nor frame: the lined sill."""
        return frozenset(WEDGE_FACETS) - self.glass - self.frames

    @property
    def nose_z(self) -> float:
        return self.stations[0].z

    @property
    def tail_z(self) -> float:
        return self.stations[-1].z

    def station_at(self, z: float) -> WedgeStation:
        """The interpolated station at ``z`` (clamped to the ends)."""
        zs = [s.z for s in self.stations]
        z = float(np.clip(z, zs[0], zs[-1]))
        i = min(int(np.searchsorted(zs, z, side="right")) - 1, len(zs) - 2)
        a, b = self.stations[i], self.stations[i + 1]
        return WedgeStation.lerp(a, b, (z - a.z) / (b.z - a.z))

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        """True for points at least ``margin`` inside the hull, chamfers included (the loft is
        treated as linear between stations, exact to millimetres)."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        first = self.stations[0]
        zs = [s.z for s in self.stations]

        def param(name: str) -> np.ndarray:
            return np.interp(p[:, 2], zs, [getattr(s, name) for s in self.stations])

        keel, top = param("keel"), param("top")
        zeros = np.zeros(len(p))
        corners = np.stack(
            [
                np.stack([zeros, keel], axis=1),
                np.stack([param("keel_half_width"), keel], axis=1),
                np.stack([param("shoulder_half_width"), param("shoulder_y")], axis=1),
                np.stack([param("top_half_width"), top], axis=1),
                np.stack([zeros, top], axis=1),
            ],
            axis=1,
        )  # (N, 5, 2)
        half = [corners[:, 0]]
        for k in (1, 2, 3):
            for other in (k - 1, k + 1):
                half.append(
                    corners[:, k]
                    + self.chamfer * unit(corners[:, other] - corners[:, k])
                )
        half.append(corners[:, 4])
        right = np.stack(half, axis=1)  # (N, 8, 2)
        ring = np.concatenate(
            [right, right[:, 1:7][:, ::-1] * np.array([-1.0, 1.0])], axis=1
        )  # (N, 14, 2)
        edges = np.roll(ring, -1, axis=1) - ring
        rel = p[:, None, :2] - ring
        cross = (
            edges[..., 0] * rel[..., 1] - edges[..., 1] * rel[..., 0]
        ) / np.linalg.norm(edges, axis=2)
        inside = np.all(
            cross > margin, axis=1
        )  # left of every edge (counter-clockwise ring)
        inside &= (p[:, 2] >= self.nose_z) & (p[:, 2] <= self.tail_z - margin)
        inside &= (
            p[:, 2] >= first.z + (p[:, 1] - first.keel) * math.tan(first.rake) + margin
        )
        return inside


def _wedge_rings(spec: WedgeFuselageSpec) -> tuple[list[WedgeStation], list[str]]:
    """Stations with the window's rear frame band inserted, and per segment its role:
    ``window``, ``window_frame`` (the rear band) or ``hull``."""
    stations = list(spec.stations)
    roles = ["hull"] * (len(stations) - 1)
    if spec.window_end:
        end, prev = spec.stations[spec.window_end], spec.stations[spec.window_end - 1]
        z_band = end.z - spec.frame_width
        if z_band <= prev.z:
            raise ValueError("the window's last segment is shorter than the frame band")
        stations.insert(
            spec.window_end,
            WedgeStation.lerp(prev, end, (z_band - prev.z) / (end.z - prev.z)),
        )
        roles = (
            ["window"] * spec.window_end
            + ["window_frame"]
            + ["hull"] * (len(spec.stations) - 1 - spec.window_end)
        )
    return stations, roles


def _window_cap_rings(spec: WedgeFuselageSpec) -> tuple[np.ndarray, np.ndarray]:
    """Outer and inner (inset by ``frame_width`` in the pane's plane) rings of the front pane, 3D."""
    first = spec.stations[0]
    ring2d = first.ring_2d(spec.chamfer)
    cos_r = math.cos(first.rake)
    uv = np.column_stack(
        [ring2d[:, 0], (ring2d[:, 1] - first.keel) / cos_r]
    )  # in-plane coordinates
    inner = inset_convex_polygon(uv, spec.frame_width)
    inner_xy = np.column_stack([inner[:, 0], first.keel + inner[:, 1] * cos_r])
    return first.lift(ring2d), first.lift(inner_xy)


class _FlatMeshBuilder:
    """Collects flat (unshared-vertex) polygons, one material each."""

    def __init__(self) -> None:
        self.verts: list[np.ndarray] = []
        self.faces: list[list[int]] = []
        self.mats: list[int] = []
        self.table: list[Material] = []

    def _material(self, material: Material) -> int:
        if material not in self.table:
            self.table.append(material)
        return self.table.index(material)

    def poly(self, points: np.ndarray, material: Material, facing: np.ndarray) -> None:
        """Fan-triangulate a convex polygon, wound to face along ``facing``."""
        pts = np.asarray(points, dtype=float).reshape(-1, 3)
        normal = sum(
            np.cross(pts[k] - pts[0], pts[k + 1] - pts[0])
            for k in range(1, len(pts) - 1)
        )
        if float(normal @ np.asarray(facing, dtype=float)) < 0.0:
            pts = pts[::-1]
        start = sum(len(v) for v in self.verts)
        self.verts.append(pts)
        m = self._material(material)
        for k in range(1, len(pts) - 1):
            self.faces.append([start, start + k, start + k + 1])
            self.mats.append(m)

    def quad(
        self,
        a0: np.ndarray,
        a1: np.ndarray,
        b1: np.ndarray,
        b0: np.ndarray,
        material: Material,
    ) -> None:
        """Quad between the edge ``a0 -> a1`` of a front ring and ``b0 -> b1`` of the next ring, wound
        like ``loft`` (outwards for counter-clockwise rings ordered front to back)."""
        start = sum(len(v) for v in self.verts)
        self.verts.append(np.array([a0, a1, b1, b0]))
        m = self._material(material)
        self.faces += [[start, start + 2, start + 3], [start, start + 1, start + 2]]
        self.mats += [m, m]

    def mesh(self) -> Mesh:
        if not self.faces:
            return Mesh.empty()
        return Mesh(
            np.concatenate(self.verts),
            np.array(self.faces),
            np.array(self.mats),
            tuple(self.table),
        )


def _lined_rings(spec: WedgeFuselageSpec, inset: float) -> list[np.ndarray]:
    """The window segment's station rings shrunk by ``inset`` (cockpit lining), 3D."""
    return [
        s.lift(inset_convex_polygon(s.ring_2d(spec.chamfer), inset))
        for s in spec.stations[: spec.window_end + 1]
    ]


def wedge_fuselage(spec: WedgeFuselageSpec, style: Style) -> Part:
    """Faceted fuselage (see :class:`WedgeFuselageSpec`), flat facets with hard edges: window
    panes ``canopy_glass``, frames ``canopy_frame``, hull ``hull``, tail cap ``hull_dark``,
    cockpit lining and bulkhead ``interior``. Anchors: ``nose`` (front face centre, forward),
    ``tail``, ``center`` and, with a window, ``eye`` (looking along -Z). One box collision
    primitive: the hull's bounds."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    glass, frame, interior = (
        style.material("canopy_glass"),
        style.material("canopy_frame"),
        style.material("interior"),
    )
    stations, roles = _wedge_rings(spec)
    rings = [s.lift(s.ring_2d(spec.chamfer)) for s in stations]
    n = len(WEDGE_FACETS)
    b = _FlatMeshBuilder()
    for seg, role in enumerate(roles):
        front, back = rings[seg], rings[seg + 1]
        for j, kind in enumerate(WEDGE_FACETS):
            if role == "window" and kind in spec.glass:
                material = glass
            elif role != "hull" and kind in spec.glass | spec.frames:
                material = frame
            else:
                material = hull
            b.quad(front[j], front[(j + 1) % n], back[(j + 1) % n], back[j], material)
    forward = np.array([0.0, 0.0, -1.0])
    if spec.window_end:  # framed front pane
        outer, inner = _window_cap_rings(spec)
        for j in range(n):
            b.poly(
                np.array([outer[j], outer[(j + 1) % n], inner[(j + 1) % n], inner[j]]),
                frame,
                forward,
            )
        b.poly(inner, glass, forward)
    else:
        b.poly(rings[0], hull, forward)
    b.poly(rings[-1], dark, -forward)
    hull_mesh = b.mesh()
    lo, hi = hull_mesh.bounds()

    if (
        spec.window_end
    ):  # cockpit lining (facing inwards) and bulkhead (facing the pilot)
        lined = _lined_rings(spec, spec.lining_inset)
        for seg in range(spec.window_end):
            for j, kind in enumerate(WEDGE_FACETS):
                if kind in spec.lined:
                    a0, a1 = lined[seg][j], lined[seg][(j + 1) % n]
                    b0, b1 = lined[seg + 1][j], lined[seg + 1][(j + 1) % n]
                    b.quad(
                        a1, a0, b0, b1, interior
                    )  # mirrored winding: normals point inwards
        wall = lined[-1].copy()
        wall[:, 2] -= 2.0 * spec.lining_inset
        b.poly(wall, interior, forward)
    mesh = b.mesh()

    first, last = spec.stations[0], spec.stations[-1]
    center = 0.5 * (lo + hi)
    anchors = {
        "nose": Anchor(
            first.lift(np.array([[0.0, 0.5 * (first.keel + first.top)]]))[0],
            [0.0, 0.0, -1.0],
        ),
        "tail": Anchor([0.0, 0.5 * (last.keel + last.top), last.z], [0.0, 0.0, 1.0]),
        "center": Anchor(center),
    }
    if spec.window_end:
        anchors["eye"] = Anchor(spec.eye, [0.0, 0.0, -1.0])
    return Part(
        "fuselage",
        mesh,
        anchors=anchors,
        collision=[Collision("box", center, size=hi - lo, name="fuselage")],
        mass_kg=spec.mass_kg,
    )


def wedge_cockpit_faces(
    spec: WedgeFuselageSpec, mesh: Mesh, style: Style
) -> np.ndarray:
    """Per-face mask of what the pilot sees up close: every non-glass face of the window
    segment (frames, chin, lining), but not the bulkhead behind the eye. Assets sample these
    finer, because a splat's soft edge (2.5 sigma) that close to the eye spans degrees."""
    if not spec.window_end:
        return np.zeros(mesh.face_count, dtype=bool)
    glass = mesh.face_material == mesh.material_index(
        style.material("canopy_glass").name
    )
    z_end = spec.stations[spec.window_end].z
    return (mesh.face_centroids()[:, 2] < z_end - 3.0 * spec.lining_inset) & ~glass


def wedge_cockpit_interior(
    spec: WedgeFuselageSpec,
    style: Style,
    bar_width: float | None = None,
    bar_depth: float = 0.05,
    gap: float = 0.03,
    sill_depth: float = 0.4,
) -> Mesh:
    """First-person cockpit mesh for a wedge fuselage window (not splatted): the window frame
    seen from inside and the sill, nothing else. Dark bars run just inside every frame: around
    the front pane (the bar across the top, the struts down its sides, the sill edge) and along
    each frame chamfer to the window's rear; a sill strip lines the non-glass facets
    ``sill_depth`` back from the front pane. Nothing crosses a pane, so the forward view stays
    clear. Bars are ``bar_width`` wide (default ``frame_width + 2 cm``; wider reads as a heavier
    frame) and sit ``gap`` behind the frame, hiding its splats from the eye; the sill sits 1 cm
    inside the splatted lining."""
    if not spec.window_end:
        raise ValueError("this fuselage has no window")
    interior = style.material("interior")
    width = spec.frame_width + 0.02 if bar_width is None else bar_width
    meshes: list[Mesh] = []

    def bar(p: np.ndarray, q: np.ndarray, outward: np.ndarray, extend: float) -> None:
        along = unit(q - p)
        w_axis = unit(np.cross(outward, along))
        inward = -np.cross(
            along, w_axis
        )  # unit, perpendicular to the bar, towards the cockpit
        if float(inward @ outward) > 0.0:
            inward = -inward
        ends = np.array([p - extend * along, q + extend * along]) + inward * (
            gap + 0.5 * bar_depth
        )
        meshes.append(
            sweep_rect(ends, w_axis, [width, width], [bar_depth, bar_depth], interior)
        )

    first = spec.stations[0]
    outer, inner = _window_cap_rings(spec)
    mid = 0.5 * (outer + inner)
    pane_out = np.array([0.0, math.sin(first.rake), -math.cos(first.rake)])
    for j in range(len(mid)):
        bar(mid[j], mid[(j + 1) % len(mid)], pane_out, 0.5 * width)
    stations, roles = _wedge_rings(spec)
    rings = [s.lift(s.ring_2d(spec.chamfer)) for s in stations]
    rear = roles.index("window_frame") + 1  # the window's rear station
    n = len(WEDGE_FACETS)
    for j, kind in enumerate(WEDGE_FACETS):
        if kind in spec.frames:
            p = 0.5 * (rings[0][j] + rings[0][(j + 1) % n])
            q = 0.5 * (rings[rear][j] + rings[rear][(j + 1) % n])
            outward = np.cross(
                rings[0][(j + 1) % n] - rings[0][j], rings[1][j] - rings[0][j]
            )
            if float(outward @ np.array([p[0], 0.0, 0.0])) < 0.0 and abs(p[0]) > 1e-9:
                outward = -outward
            bar(p, q, unit(outward), 0.0)
    # Sill: the lining of the non-glass facets from the front pane back by ``sill_depth``.
    s0, s1 = spec.stations[0], spec.stations[1]
    back = WedgeStation.lerp(s0, s1, min(sill_depth / (s1.z - s0.z), 1.0))
    inset = spec.lining_inset + 0.01
    front_ring, back_ring = (
        s.lift(inset_convex_polygon(s.ring_2d(spec.chamfer), inset)) for s in (s0, back)
    )
    sill = _FlatMeshBuilder()
    for j, kind in enumerate(WEDGE_FACETS):
        if kind in spec.lined:
            a0, a1 = front_ring[j], front_ring[(j + 1) % n]
            b0, b1 = back_ring[j], back_ring[(j + 1) % n]
            sill.quad(a1, a0, b0, b1, interior)  # mirrored winding: faces the cockpit
    meshes.append(sill.mesh())
    return Mesh.concatenate(meshes)


# --- hump (the raider's raised central fuselage) -----------------------------------------------
@dataclass(frozen=True)
class HumpStation:
    z: float
    width: float
    height: float


@dataclass(frozen=True)
class HumpSpec:
    """A lofted body of superellipse sections whose underside lies on ``y = bottom_y`` (so the part below the
    wing's top surface is buried in the wing). Stations run front (smallest z) to back."""

    stations: tuple[HumpStation, ...]
    bottom_y: float = 0.0
    exponent: float = 3.0
    points: int = 28
    mass_kg: float = 3_500.0

    def section(self, z: float) -> tuple[float, float]:
        """Width and height at ``z`` (linear between stations)."""
        zs = [s.z for s in self.stations]
        return (
            float(np.interp(z, zs, [s.width for s in self.stations])),
            float(np.interp(z, zs, [s.height for s in self.stations])),
        )

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        """Points inside the hump by roughly ``margin`` (a normalised-radius test)."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        zs = np.array([s.z for s in self.stations])
        w = np.interp(p[:, 2], zs, [s.width for s in self.stations])
        h = np.interp(p[:, 2], zs, [s.height for s in self.stations])
        inside_z = (p[:, 2] > zs[0]) & (p[:, 2] < zs[-1])
        a, b = 0.5 * w, 0.5 * h
        n = self.exponent
        r = (np.abs(p[:, 0] / np.maximum(a, 1e-9)) ** n + np.abs((p[:, 1] - self.bottom_y - b) / np.maximum(b, 1e-9)) ** n) ** (1.0 / n)
        slack = margin / np.maximum(np.minimum(a, b), 1e-9)
        return inside_z & (r < 1.0 - slack)


def hump(spec: HumpSpec, style: Style) -> Part:
    """The hump as one lofted solid with flat end caps (the rear cap is hidden by the nacelles)."""
    material = style.material("hull")
    rings = []
    for s in spec.stations:
        xy = superellipse_ring(s.width, s.height, spec.points, spec.exponent)
        rings.append(np.column_stack([xy[:, 0], xy[:, 1] + spec.bottom_y + 0.5 * s.height, np.full(len(xy), s.z)]))
    mesh = loft(rings, material, cap_start=True, cap_end=True)
    first, last = spec.stations[0], spec.stations[-1]
    centre_y = spec.bottom_y + 0.5 * max(s.height for s in spec.stations)
    length = last.z - first.z
    width = max(s.width for s in spec.stations)
    height = max(s.height for s in spec.stations)
    collision = [
        Collision("box", (0.0, spec.bottom_y + 0.5 * height, 0.5 * (first.z + last.z)), size=(width, height, length))
    ]
    return Part("hump", mesh, {"centre": Anchor((0.0, centre_y, 0.5 * (first.z + last.z)))}, collision, spec.mass_kg, group="hump")


def canopy_panel(
    spec: HumpSpec, style: Style, z_front: float, z_back: float, front_width: float, back_width: float, lift: float = 0.05
) -> Mesh:
    """A flat dark opaque canopy panel lying on the hump's top, from ``z_front`` to ``z_back``, ``lift`` metres
    above the hump's top line at its front, following the slope. Frame bars are not modelled: the surrounding
    plating's panel lines frame it."""
    glass = style.material("canopy_glass")
    front_h, back_h = (spec.bottom_y + spec.section(z)[1] for z in (z_front, z_back))
    slope = (back_h - front_h) / (z_back - z_front)
    length = z_back - z_front
    thickness = 0.12
    sloped = tapered_wedge(length, (front_width, thickness), (back_width, thickness), glass, slope)
    return sloped.translated((0.0, front_h + 0.5 * (back_h - front_h) + lift - 0.5 * thickness + 0.04, 0.5 * (z_front + z_back)))


def tapered_wedge(length: float, size_a: tuple[float, float], size_b: tuple[float, float], material: Material, slope: float) -> Mesh:
    """A box along Z (front section ``size_a`` at -length/2, back ``size_b`` at +length/2) whose centre line
    climbs ``slope`` metres per metre towards the back."""
    from ..core.geometry import tapered_box  # local: keeps the import list above untouched

    return tapered_box(length, size_a, size_b, material, offset_b=(0.0, slope * length)).translated((0.0, -0.5 * slope * length, 0.0))
