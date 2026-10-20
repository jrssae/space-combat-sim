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
    Mesh,
    assign_material_by_predicate,
    lathe,
    rotation_x,
    rotation_y,
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
