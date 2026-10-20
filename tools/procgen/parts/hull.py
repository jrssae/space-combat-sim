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
    Mesh,
    _fan_faces,
    _quad_faces,
    box,
    lathe,
    loft,
    superellipse_ring,
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
