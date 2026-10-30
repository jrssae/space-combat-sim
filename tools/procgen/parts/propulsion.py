"""Propulsion parts: nozzle bells, cosmetic RCS thrusters and the complete engine pod.

Local frames: a nozzle exhausts along its local +Z (anchor ``exit``); a pod runs along Z with
its main nozzle at +Z (rear) and the retro nozzle at -Z (front). The pod's RCS nozzles sit on
its surface at mid-length, exhausting along +-X and +-Y.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from itertools import pairwise

import numpy as np

from ..core.geometry import (
    Material,
    Mesh,
    assign_material_by_predicate,
    basis_from_z,
    box,
    lathe,
    rotation_x,
    rotation_y,
    sweep_rect,
    unit,
)
from ..styles import Style
from . import Anchor, Collision, Part


@dataclass(frozen=True)
class NozzleSpec:
    """A bell: throat radius ``throat_r`` at z = 0 widening to ``exit_r`` at z = ``length``.
    ``recess`` is how much of the bell is tucked inside its mount (anchors ignore it)."""

    throat_r: float = 0.30
    exit_r: float = 0.50
    length: float = 0.60
    wall: float = 0.04
    segments: int = 40
    profile_steps: int = 6
    mass_kg: float = 0.0

    def radius_at(self, z: float) -> float:
        """Parabolic bell: fast expansion near the throat, flatter towards the exit."""
        t = min(max(z / self.length, 0.0), 1.0)
        return self.throat_r + (self.exit_r - self.throat_r) * math.sqrt(t)


def nozzle(spec: NozzleSpec, style: Style) -> Part:
    """Closed solid: outer bell, lip, inner bell back to a throat plate."""
    outer, inner = style.material("nozzle"), style.material("nozzle_throat")
    zs = [spec.length * k / spec.profile_steps for k in range(spec.profile_steps + 1)]
    outer_profile = [(z, spec.radius_at(z) + spec.wall) for z in zs]
    inner_profile = [(z, spec.radius_at(z)) for z in reversed(zs)]
    profile = [(0.0, 0.0), *outer_profile, *inner_profile, (0.08, spec.throat_r * 0.6), (0.08, 0.0)]
    n_outer = len(outer_profile)
    materials = [outer] * (n_outer) + [outer] + [inner] * (len(inner_profile) - 1) + [inner, inner]
    materials = materials[: len(profile) - 1]
    creases = {1, n_outer, n_outer + 1, len(profile) - 2}
    mesh = lathe(profile, spec.segments, materials, creases=creases)
    exit_pos = [0.0, 0.0, spec.length]
    return Part(
        "nozzle",
        mesh,
        anchors={
            "exit": Anchor(exit_pos, [0.0, 0.0, 1.0]),
            "throat": Anchor([0.0, 0.0, 0.0], [0.0, 0.0, 1.0]),
        },
        mass_kg=spec.mass_kg,
    )


@dataclass(frozen=True)
class RcsSpec:
    base_r: float = 0.05
    exit_r: float = 0.08
    length: float = 0.08
    segments: int = 12


def rcs_nozzle(spec: RcsSpec, style: Style) -> Part:
    """A small cone exhausting along +Z, base at z = 0 (sits on a surface)."""
    m = style.material("rcs")
    profile = [(0.0, 0.0), (0.0, spec.base_r), (spec.length, spec.exit_r), (spec.length, spec.exit_r * 0.55), (spec.length, 0.0)]
    mesh = lathe(profile, spec.segments, [m, m, style.material("nozzle_throat"), style.material("nozzle_throat")], creases={1, 2})
    return Part("rcs_nozzle", mesh, anchors={"exit": Anchor([0.0, 0.0, spec.length], [0.0, 0.0, 1.0])})


@dataclass(frozen=True)
class PodSpec:
    """Engine pod body (section 9.1: 3.2 m long, 1.1 m diameter) with main and retro bells."""

    length: float = 3.2
    radius: float = 0.55
    nose_length: float = 0.55  # rounded front
    tail_length: float = 0.45  # boat-tail at the rear
    tail_radius: float = 0.44
    segments: int = 48
    main: NozzleSpec = NozzleSpec(throat_r=0.30, exit_r=0.50, length=0.60)
    retro: NozzleSpec = NozzleSpec(throat_r=0.14, exit_r=0.25, length=0.32, segments=28)
    main_recess: float = 0.15  # how far the main bell starts inside the body
    retro_recess: float = 0.10
    rcs: RcsSpec = RcsSpec()
    rcs_fraction: float = 0.42  # along the length from the front
    dark_band: tuple[float, float] = (0.86, 1.0)  # fractions of the body that are dark panels
    mass_kg: float = 6_000.0

    @property
    def front_z(self) -> float:
        return -0.5 * self.length

    @property
    def rear_z(self) -> float:
        return 0.5 * self.length


def _pod_body(spec: PodSpec, style: Style) -> Mesh:
    hull, dark, stripe = style.material("hull"), style.material("hull_dark"), style.material("stripe")
    z0, z1 = spec.front_z, spec.rear_z
    r = spec.radius
    # Front: an elliptical nose cap from the front plate (retro nozzle mount) to full radius.
    front_plate_r = spec.retro.exit_r + 0.06
    nose = []
    steps = 5
    for k in range(steps + 1):
        t = k / steps
        zz = z0 + spec.nose_length * (1.0 - math.cos(0.5 * math.pi * t))
        rr = front_plate_r + (r - front_plate_r) * math.sin(0.5 * math.pi * t)
        nose.append((zz, rr))
    # Cylinder with stripe edges and the dark rear band as explicit stations.
    stripe_c = z0 + style.stripe_fraction * spec.length
    half = 0.5 * style.stripe_width_m
    band0 = z0 + spec.dark_band[0] * spec.length
    cyl_z = sorted({nose[-1][0], stripe_c - half, stripe_c + half, band0, z1 - spec.tail_length})
    cyl = [(zz, r) for zz in cyl_z if zz > nose[-1][0]]
    tail = [(z1, spec.tail_radius), (z1, spec.main.throat_r + spec.main.wall + 0.03), (z1, 0.0)]
    profile = [(z0, 0.0), (z0, front_plate_r), *nose, *cyl, *tail]
    # Segment materials by the segment's mid z.
    materials = []
    for (za, _), (zb, _) in pairwise(profile):
        zm = 0.5 * (za + zb)
        if stripe_c - half <= zm <= stripe_c + half:
            materials.append(stripe)
        elif zm >= band0 or zb == z1 and za == z1:
            materials.append(dark)
        else:
            materials.append(hull)
    creases = {1, len(profile) - 3, len(profile) - 2}
    return lathe(profile, spec.segments, materials, creases=creases)


def engine_pod(spec: PodSpec, style: Style) -> Part:
    """Pod body plus main bell (+Z), retro bell (-Z) and four RCS cones; anchors ``center``,
    ``main``, ``retro`` (exhaust directions) and ``rcs_px/nx/py/ny``."""
    body = _pod_body(spec, style)
    main = nozzle(spec.main, style).translated([0.0, 0.0, spec.rear_z - spec.main_recess])
    retro = nozzle(spec.retro, style).transformed(rotation_x(math.pi), [0.0, 0.0, spec.front_z + spec.retro_recess])
    rcs_z = spec.front_z + spec.rcs_fraction * spec.length
    rcs_parts = {
        "rcs_px": rcs_nozzle(spec.rcs, style).transformed(rotation_y(0.5 * math.pi), [spec.radius - 0.01, 0.0, rcs_z]),
        "rcs_nx": rcs_nozzle(spec.rcs, style).transformed(rotation_y(-0.5 * math.pi), [-spec.radius + 0.01, 0.0, rcs_z]),
        "rcs_py": rcs_nozzle(spec.rcs, style).transformed(rotation_x(-0.5 * math.pi), [0.0, spec.radius - 0.01, rcs_z]),
        "rcs_ny": rcs_nozzle(spec.rcs, style).transformed(rotation_x(0.5 * math.pi), [0.0, -spec.radius + 0.01, rcs_z]),
    }
    mesh = Mesh.concatenate([body, main.mesh, retro.mesh, *(p.mesh for p in rcs_parts.values())])
    anchors = {
        "center": Anchor([0.0, 0.0, 0.0]),
        "front": Anchor([0.0, 0.0, spec.front_z], [0.0, 0.0, -1.0]),
        "rear": Anchor([0.0, 0.0, spec.rear_z], [0.0, 0.0, 1.0]),
        "main": main.anchor("exit"),
        "retro": retro.anchor("exit"),
    }
    for name, part in rcs_parts.items():
        anchors[name] = part.anchor("exit")
    collision = [Collision("capsule", [0.0, 0.0, 0.0], radius=spec.radius, height=spec.length, name="pod")]
    return Part("engine_pod", mesh, anchors, collision, spec.mass_kg)


# --- ring-faced engine pod (Starfury) ----------------------------------------------------------
@dataclass(frozen=True)
class RingPodSpec:
    """A chunky engine pod along Z, centred on the origin (front at ``-length/2``).

    Front to back: a ribbed intake housing (``front_radius``) whose face is a light ring frame
    around a recessed dark disc holding the retro bell; a rounded shoulder out to the body
    ``radius``; the body; a short taper; a ribbed rear housing (``rear_radius``) ending in a flat
    face around the main bell. The bells protrude slightly so their exits (the hardpoints) are
    clearly visible. ``bosses`` are cosmetic round ports on the body, given as roll angles
    (degrees from +X towards +Y) at ``boss_z``. A ``knuckle_radius`` above ``radius`` swells the
    body into a rounded knuckle ``knuckle_length`` long centred on ``knuckle_z`` (where the strut
    meets the pod); it must lie inside the plain body section."""

    length: float = 5.0
    radius: float = 0.82
    front_radius: float = 0.64
    front_length: float = 0.6
    shoulder_length: float = 0.55
    taper_length: float = 0.5
    rear_radius: float = 0.74
    rear_length: float = 1.1
    ring_inner_radius: float = 0.44
    face_recess: float = 0.1
    ribs_front: int = 2
    ribs_rear: int = 3
    main: NozzleSpec = NozzleSpec(throat_r=0.36, exit_r=0.55, length=0.75)
    main_protrusion: float = 0.12
    retro: NozzleSpec = NozzleSpec(throat_r=0.16, exit_r=0.28, length=0.35, segments=32)
    retro_protrusion: float = 0.05
    bosses: tuple[float, ...] = ()
    boss_z: float = -0.4
    boss_radius: float = 0.26
    boss_height: float = 0.16
    knuckle_radius: float = 0.0
    knuckle_z: float = 0.0
    knuckle_length: float = 0.0
    segments: int = 48
    mass_kg: float = 5_000.0

    def __post_init__(self) -> None:
        if (
            not self.retro.exit_r + self.retro.wall
            < self.ring_inner_radius
            < self.front_radius
            < self.radius
        ):
            raise ValueError(
                "pod radii must grow: retro bell < ring frame < intake housing < body"
            )
        if self.main.exit_r + self.main.wall >= self.rear_radius:
            raise ValueError("the main bell must fit inside the rear housing")
        body = (
            self.length
            - self.front_length
            - self.shoulder_length
            - self.taper_length
            - self.rear_length
        )
        if body <= 0.0:
            raise ValueError("pod sections are longer than the pod")
        if self.knuckle_radius > self.radius:
            zb = self.front_z + self.front_length + self.shoulder_length
            zt = self.rear_z - self.rear_length - self.taper_length
            half = 0.5 * self.knuckle_length
            if not zb <= self.knuckle_z - half < self.knuckle_z + half <= zt:
                raise ValueError("the knuckle must lie inside the pod's plain body section")

    def body_points(self) -> list[tuple[float, float]]:
        """``(z, r)`` of the knuckle swelling (empty without one): a half-sine bump on ``radius``."""
        if self.knuckle_radius <= self.radius:
            return []
        z0 = self.knuckle_z - 0.5 * self.knuckle_length
        return [
            (
                z0 + self.knuckle_length * k / 10,
                self.radius
                + (self.knuckle_radius - self.radius) * math.sin(math.pi * k / 10) ** 0.6,
            )
            for k in range(11)
        ]

    def radius_at(self, z: float) -> float:
        """The outer radius at ``z`` (pod frame)."""
        zs, rs = self.outer_profile()
        return float(np.interp(z, zs, rs))

    @property
    def front_z(self) -> float:
        return -0.5 * self.length

    @property
    def rear_z(self) -> float:
        return 0.5 * self.length

    @property
    def collision_radius(self) -> float:
        """Radius of the collision capsule: the body's, or the knuckle's where it swells wider."""
        return max(self.radius, self.knuckle_radius)

    @property
    def capsule_height(self) -> float:
        """Total length of a ``collision_radius`` capsule that still wraps the flat end faces:
        its hemispherical caps reach ``r - sqrt(r^2 - r_end^2)`` past each face."""
        r, r_end = self.collision_radius, max(self.front_radius, self.rear_radius)
        return self.length + 2.0 * (r - math.sqrt(r**2 - r_end**2))

    def outer_profile(self) -> tuple[np.ndarray, np.ndarray]:
        """``(z, r)`` of the outer surface from the front face to the rear face (for queries)."""
        z0, z1 = self.front_z, self.rear_z
        zf = z0 + self.front_length
        zr = z1 - self.rear_length
        zt = zr - self.taper_length
        t = np.linspace(0.0, 1.0, 6)
        shoulder_z = zf + self.shoulder_length * t
        shoulder_r = self.front_radius + (self.radius - self.front_radius) * np.sin(
            0.5 * math.pi * t
        )
        bump = self.body_points()
        z = np.concatenate(
            [[z0, zf], shoulder_z[1:], [p[0] for p in bump], [zt, zr, z1]]
        )
        r = np.concatenate(
            [
                [self.front_radius, self.front_radius],
                shoulder_r[1:],
                [p[1] for p in bump],
                [self.radius, self.rear_radius, self.rear_radius],
            ]
        )
        return z, r

    def contains(self, points: np.ndarray, margin: float = 0.0) -> np.ndarray:
        """True for points at least ``margin`` inside the pod body (pod frame)."""
        p = np.asarray(points, dtype=float).reshape(-1, 3)
        z, r = self.outer_profile()
        radius = np.interp(p[:, 2], z, r)
        inside = np.hypot(p[:, 0], p[:, 1]) < radius - margin
        return (
            inside
            & (p[:, 2] > self.front_z + self.face_recess + margin)
            & (p[:, 2] < self.rear_z - margin)
        )


def _ribbed(
    z0: float, z1: float, r: float, ribs: int, a: Material, b: Material
) -> list[tuple[float, float, Material]]:
    """Profile points ``(z, r, material of the segment ending here)`` for a housing with
    ``ribs`` dark bands: ``2 ribs + 1`` equal bands alternating ``a`` and ``b``."""
    n = 2 * ribs + 1
    return [(z0 + (z1 - z0) * (k + 1) / n, r, a if k % 2 == 0 else b) for k in range(n)]


def _pod_shell(spec: RingPodSpec, style: Style) -> Mesh:
    hull, dark, panel = (
        style.material("hull"),
        style.material("hull_dark"),
        style.material("hull_panel"),
    )
    z0, z1 = spec.front_z, spec.rear_z
    zf = z0 + spec.front_length
    zr = z1 - spec.rear_length
    zt = zr - spec.taper_length
    # (z, r, material of the segment that ends at this point); the first point has no segment.
    pts: list[tuple[float, float, Material | None]] = [
        (z0 + spec.face_recess, 0.0, None),
        (z0 + spec.face_recess, spec.ring_inner_radius, dark),  # recessed dark face
        (z0, spec.ring_inner_radius, dark),  # recess wall (faces the axis)
        (z0, spec.front_radius, hull),  # the ring frame
    ]
    pts += _ribbed(z0, zf, spec.front_radius, spec.ribs_front, panel, dark)
    for k in range(1, 6):
        t = k / 5
        r = spec.front_radius + (spec.radius - spec.front_radius) * math.sin(
            0.5 * math.pi * t
        )
        pts.append((zf + spec.shoulder_length * t, r, hull))
    for k, (z, r) in enumerate(spec.body_points()):
        # The knuckle's flanks are hull; a dark band rides its crown.
        pts.append((z, r, dark if 4 <= k <= 6 else hull))
    pts.append((zt, spec.radius, hull))
    pts.append((zr, spec.rear_radius, hull))
    pts += _ribbed(zr, z1, spec.rear_radius, spec.ribs_rear, panel, dark)
    pts.append(
        (z1, spec.main.exit_r + spec.main.wall + 0.005, dark)
    )  # rear face, open inside the bell
    profile = [(z, r) for z, r, _ in pts]
    materials = [m for _, _, m in pts[1:]]
    # Hard edges wherever the profile turns by more than 30 degrees (frame, recess, housings, face).
    xy = np.array(profile)
    d = np.diff(xy, axis=0)
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    turns = np.einsum("ij,ij->i", d[:-1], d[1:])
    creases = {i + 1 for i, c in enumerate(turns) if c < math.cos(math.radians(30.0))}
    return lathe(profile, spec.segments, materials, creases=creases)


def _boss(spec: RingPodSpec, style: Style, roll_deg: float) -> tuple[Mesh, Anchor]:
    """A round port standing out of the body at ``roll_deg``: short drum, light rim, dark centre."""
    r, h = spec.boss_radius, spec.boss_height + 0.06  # 6 cm sunk into the body
    hull, dark = style.material("hull"), style.material("hull_dark")
    profile = [
        (0.0, 0.0),
        (0.0, r),
        (h, r),
        (h, 0.6 * r),
        (h - 0.04, 0.6 * r),
        (h - 0.04, 0.0),
    ]
    mesh = lathe(
        profile,
        24,
        [dark, hull, hull, dark, style.material("nozzle_throat")],
        creases={1, 2, 3, 4},
    )
    a = math.radians(roll_deg)
    radial = np.array([math.cos(a), math.sin(a), 0.0])
    base = radial * (spec.radius_at(spec.boss_z) - 0.06) + np.array(
        [0.0, 0.0, spec.boss_z]
    )
    return mesh.transformed(basis_from_z(radial, [0.0, 0.0, 1.0]), base), Anchor(
        base + radial * h, radial
    )


def ring_pod(spec: RingPodSpec, style: Style) -> Part:
    """Pod shell, main bell (+Z), retro bell (-Z) and bosses. Anchors: ``center``, ``front``,
    ``rear``, ``main`` and ``retro`` (bell exit centres, exhaust directions), ``boss_<i>``. One
    capsule collision primitive along Z."""
    main = nozzle(spec.main, style).translated(
        [0.0, 0.0, spec.rear_z + spec.main_protrusion - spec.main.length]
    )
    retro = nozzle(spec.retro, style).transformed(
        rotation_x(math.pi),
        [0.0, 0.0, spec.front_z - spec.retro_protrusion + spec.retro.length],
    )
    meshes = [_pod_shell(spec, style), main.mesh, retro.mesh]
    anchors = {
        "center": Anchor([0.0, 0.0, 0.0]),
        "front": Anchor([0.0, 0.0, spec.front_z], [0.0, 0.0, -1.0]),
        "rear": Anchor([0.0, 0.0, spec.rear_z], [0.0, 0.0, 1.0]),
        "main": main.anchor("exit"),
        "retro": retro.anchor("exit"),
    }
    for i, roll in enumerate(spec.bosses):
        mesh, anchor = _boss(spec, style, roll)
        meshes.append(mesh)
        anchors[f"boss_{i}"] = anchor
    collision = [
        Collision(
            "capsule",
            [0.0, 0.0, 0.0],
            radius=spec.collision_radius,
            height=spec.capsule_height,
            name="pod",
        )
    ]
    return Part("ring_pod", Mesh.concatenate(meshes), anchors, collision, spec.mass_kg)


# --- claw: the splayed manoeuvring-thruster vanes behind a pod --------------------------------
@dataclass(frozen=True)
class VaneSpec:
    """One angular vane, in the pod frame (pod axis = Z). It lies in the plane through the pod
    axis at ``roll_deg`` (degrees from +X towards +Y): the root sits ``root_radius`` out from
    the axis at ``root_z`` (shifted ``offset`` sideways, for paired prongs), then each
    ``(length, splay_deg)`` segment runs aft and outwards at ``splay_deg`` from the pod axis.
    ``chord`` is the width across the plane and ``thickness`` the depth in it, root to tip."""

    roll_deg: float
    root_radius: float
    root_z: float
    segments: tuple[tuple[float, float], ...]
    chord: tuple[float, float] = (0.3, 0.12)
    thickness: tuple[float, float] = (0.22, 0.08)
    offset: float = 0.0

    def path(self) -> np.ndarray:
        a = math.radians(self.roll_deg)
        radial = np.array([math.cos(a), math.sin(a), 0.0])
        side = np.array([-math.sin(a), math.cos(a), 0.0])
        pts = [
            radial * self.root_radius
            + side * self.offset
            + np.array([0.0, 0.0, self.root_z])
        ]
        for length, splay in self.segments:
            s = math.radians(splay)
            pts.append(
                pts[-1]
                + length * (math.sin(s) * radial + np.array([0.0, 0.0, math.cos(s)]))
            )
        return np.array(pts)

    def side_axis(self) -> np.ndarray:
        a = math.radians(self.roll_deg)
        return np.array([-math.sin(a), math.cos(a), 0.0])


@dataclass(frozen=True)
class RcsBlockSpec:
    """A thruster block on a claw: an axis-aligned box (pod frame) centred ``radius`` out from
    the pod axis at ``roll_deg`` and ``z``; each face named in ``nozzles`` (``px``, ``nx``,
    ``py``, ``ny``) carries an RCS cone exhausting along that face's normal."""

    roll_deg: float
    radius: float
    z: float
    size: tuple[float, float, float] = (0.5, 0.5, 0.8)
    nozzles: tuple[str, ...] = ()

    def center(self) -> np.ndarray:
        a = math.radians(self.roll_deg)
        return np.array([self.radius * math.cos(a), self.radius * math.sin(a), self.z])


_FACE_AXES = {"px": (0, 1.0), "nx": (0, -1.0), "py": (1, 1.0), "ny": (1, -1.0)}


@dataclass(frozen=True)
class ClawSpec:
    """The claw cluster of one pod: angular ``vanes`` splaying aft and outwards, rooted in
    thruster ``blocks`` that carry the RCS cones."""

    vanes: tuple[VaneSpec, ...]
    blocks: tuple[RcsBlockSpec, ...] = ()
    rcs: RcsSpec = RcsSpec(base_r=0.07, exit_r=0.11, length=0.1, segments=14)
    mass_kg: float = 1_000.0


def claw_cluster(spec: ClawSpec, style: Style) -> Part:
    """Vanes (``hull``, dark tips), blocks (``hull_panel``) and RCS cones. Anchors:
    ``rcs_<face>`` (cone exits, exhaust directions) and ``vane_<i>`` (tips, pointing along the
    last segment). One box collision primitive along the first vane, wide enough for every vane
    rooted at the same roll angle (paired prongs)."""
    hull, dark, panel = (
        style.material("hull"),
        style.material("hull_dark"),
        style.material("hull_panel"),
    )
    meshes: list[Mesh] = []
    anchors: dict[str, Anchor] = {}
    for i, vane in enumerate(spec.vanes):
        path = vane.path()
        arc = np.concatenate(
            [[0.0], np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))]
        )
        t = arc / arc[-1]
        widths = vane.chord[0] + (vane.chord[1] - vane.chord[0]) * t
        thick = vane.thickness[0] + (vane.thickness[1] - vane.thickness[0]) * t
        meshes.append(
            sweep_rect(path, vane.side_axis(), widths, thick, hull, end_material=dark)
        )
        anchors[f"vane_{i}"] = Anchor(path[-1], path[-1] - path[-2])
    for block in spec.blocks:
        c = block.center()
        meshes.append(box(block.size, panel, center=c))
        for face in block.nozzles:
            axis, sign = _FACE_AXES[face]
            direction = np.zeros(3)
            direction[axis] = sign
            base = c + direction * (0.5 * block.size[axis] - 0.01)
            cone = rcs_nozzle(spec.rcs, style).transformed(
                basis_from_z(direction), base
            )
            meshes.append(cone.mesh)
            anchors[f"rcs_{face}"] = cone.anchor("exit")
    collision = []
    if spec.vanes:
        lead = spec.vanes[0]
        path = lead.path()
        root, tip = path[0], path[-1]
        x_axis = unit(tip - root)
        y_axis = lead.side_axis()
        group = [v for v in spec.vanes if v.roll_deg == lead.roll_deg]
        width = max(abs(v.offset) for v in group) * 2.0 + max(v.chord[0] for v in group)
        bend = float(
            np.linalg.norm(np.cross(path - root, x_axis), axis=1).max()
        )  # path off the root-tip line
        depth = max(v.thickness[0] for v in group) + 2.0 * bend
        basis = np.column_stack([x_axis, y_axis, np.cross(x_axis, y_axis)])
        collision.append(
            Collision(
                "box",
                0.5 * (root + tip),
                basis,
                size=[float(np.linalg.norm(tip - root)), width, depth],
                name="claw",
            )
        )
    return Part("claw", Mesh.concatenate(meshes), anchors, collision, spec.mass_kg)


def mark_band(mesh: Mesh, material_name: str, axis: int, lo: float, hi: float, style: Style) -> Mesh:
    """Utility for callers: recolour faces whose centroid lies in ``[lo, hi]`` along ``axis``."""
    c = mesh.face_centroids()[:, axis]
    return assign_material_by_predicate(mesh, style.material(material_name), (c >= lo) & (c <= hi))


def pilot_tags(
    position: np.ndarray, exhaust: np.ndarray, center_of_mass: np.ndarray, lever_min: float = 0.3
) -> list[str]:
    """Pilot-term effect tags for a cosmetic RCS nozzle (docs/milestones M1-T04).

    Thrust is opposite to ``exhaust``. Translation tags come from the thrust direction (no
    fore/aft terms: axial thrust is the pods' job), rotation tags from the sign of
    ``r x F`` about the centre of mass (Godot frame: +x pitches the nose up, +y yaws it left,
    +z rolls left), ignoring levers shorter than ``lever_min`` metres.
    """
    f = -np.asarray(exhaust, dtype=float)
    f = f / np.linalg.norm(f)
    r = np.asarray(position, dtype=float) - np.asarray(center_of_mass, dtype=float)
    torque = np.cross(r, f)
    tags: list[str] = []
    if f[0] > 0.5:
        tags.append("sway_right")
    elif f[0] < -0.5:
        tags.append("sway_left")
    if f[1] > 0.5:
        tags.append("heave_up")
    elif f[1] < -0.5:
        tags.append("heave_down")
    names = (("pitch_up", "pitch_down"), ("yaw_left", "yaw_right"), ("roll_left", "roll_right"))
    for axis, (pos, neg) in enumerate(names):
        if torque[axis] > lever_min:
            tags.append(pos)
        elif torque[axis] < -lever_min:
            tags.append(neg)
    return tags


# --- nacelle (the raider's side-by-side engine drums) ---------------------------------------------
@dataclass(frozen=True)
class NacelleSpec:
    """A cylindrical drum along Z (front at z = 0, nozzle exit at z = ``length`` + the nozzle), a dark intake port
    in its rounded nose (the retro nozzle), a raised collar ring and a bell nozzle at the back (the main)."""

    body_length: float = 5.7
    radius: float = 0.55
    nose_length: float = 0.9
    intake_radius: float = 0.15
    retro_radius: float = 0.12
    collar_radius: float = 0.62
    collar_z: tuple[float, float] = (-1.1, -0.6)  # from the end of the body, (start, end)
    nozzle: NozzleSpec = NozzleSpec(throat_r=0.34, exit_r=0.45, length=0.7, wall=0.04)
    segments: int = 36
    mass_kg: float = 2_500.0

    @property
    def total_length(self) -> float:
        return self.body_length + self.nozzle.length

    def radius_at(self, z: float) -> float:
        """Body radius at ``z`` along the drum (the nose rounds up to ``radius``)."""
        if z < self.nose_length:
            t = max(z, 0.0) / self.nose_length
            return self.intake_radius + (self.radius - self.intake_radius) * math.sin(0.5 * math.pi * t)
        return self.radius


def nacelle(spec: NacelleSpec, style: Style) -> Part:
    """The drum plus its nozzle in one part; anchors ``main`` (exit plane, exhaust +Z) and ``retro`` (nose, exhaust -Z)."""
    hull, dark = style.material("hull"), style.material("hull_dark")
    port = style.material("nozzle_throat")
    nose_steps = 5
    profile: list[tuple[float, float]] = [(0.0, 0.0), (0.0, spec.intake_radius)]
    materials = [port]
    for k in range(1, nose_steps + 1):
        z = spec.nose_length * k / nose_steps
        profile.append((z, spec.radius_at(z)))
        materials.append(hull)
    end = spec.body_length
    c0, c1 = end + spec.collar_z[0], end + spec.collar_z[1]
    profile += [(c0, spec.radius), (c0, spec.collar_radius), (c1, spec.collar_radius), (c1, spec.radius), (end, spec.radius)]
    materials += [hull, dark, dark, hull, hull]
    profile += [(end, spec.nozzle.throat_r + spec.nozzle.wall), (end, 0.0)]
    materials += [dark, dark]
    crease = set(range(1, len(profile) - 1)) - set(range(2, nose_steps + 1))
    body = lathe(profile, spec.segments, materials, creases=crease)
    nozzle_part = nozzle(spec.nozzle, style).translated((0.0, 0.0, end))
    mesh = Mesh.concatenate([body, nozzle_part.mesh])
    anchors = {
        "main": Anchor((0.0, 0.0, end + spec.nozzle.length), (0.0, 0.0, 1.0)),
        "retro": Anchor((0.0, 0.0, 0.0), (0.0, 0.0, -1.0)),
        "axis_centre": Anchor((0.0, 0.0, 0.5 * spec.total_length)),
    }
    cap_height = spec.total_length
    collision = [Collision("capsule", (0.0, 0.0, 0.5 * spec.total_length), radius=spec.collar_radius, height=cap_height)]
    return Part("nacelle", mesh, anchors, collision, spec.mass_kg, group="nacelle")
