"""``starfury_aurora``: the player's SA-23E-style Starfury (docs/architecture.md section 9.1).

Composition only: this module places parts from ``parts/`` with the ``earthforce`` style and
derives every output from the placed parts, so the splats (``.ply``), the fallback mesh
(``.obj``), the cockpit interior mesh and ``hardpoints.json`` agree by construction.

Layout (authored Godot frame, metres, before re-centring; -Z is forward, the nose at z = 0,
the X of struts centred on x = y = 0). Silhouette and proportions follow the written reference
in ``docs/design-references.md``:

* wedge fuselage 5.2 m long: arrowhead from above (1.8 m nose -> 3.1 m), wedge from the side
  (1.1 m deep at the nose -> 2.5 m), heater-shield section from the front
* faceted cockpit window at the nose: a raked front pane, roof and side panes, frame bars only
  along the facet edges; the pilot's eye 1 m behind the front pane
* ventral gun pod under the chin, twin barrels at x = +-0.45
* four trussed struts from the fuselage flanks to the pods, 18 deg above/below horizontal,
  leading edge swept 57 deg from the centre line, hazard stripes, ladder webs with cut-outs
* four ring-faced pods (5 m x 1.64 m) centred at (+-5.5, +-2.2, 5.0): retro bell in the front
  ring, main bell at the rear
* a claw behind each pod: two outboard prongs and one inboard vane splaying aft, rooted in
  thruster blocks that carry the four RCS cones per pod

Frames: see ``docs/assets-starfury.md``. The sample set is made *exactly* mirror-symmetric
(centre-line parts are symmetrised in x, the pod/strut/claw cross is sampled once and mirrored
four ways), the body group is shifted so the splat centroid's y is exactly 0, and the z
centroid is subtracted, so the splat centroid is (0, 0, 0): GDGS's import centring is a no-op
and the hardpoints frame equals the rendered frame. Samples buried inside another part (strut
roots in the fuselage, strut tips and claw roots in the pods, the gun pod's top) are dropped.

LOD1 (``starfury_aurora_lod1.ply``, architecture section 16 D35) is the same build resampled at
``LOD1_SPACING_FACTOR`` times every spacing from RNG streams suffixed ``lod1`` (so LOD0 never
changes), balanced and centred the same way; its splats are written chunk by chunk (``cabin``
and the four ``arm_<pod>``), and each chunk is also written as a break-up chunk
(``core/chunks.py``), so the chunks partition LOD1 exactly.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core import frames
from ..core.chunks import ChunkSource, write_chunks
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh, rotation_z
from ..core.lighting import STUDIO_DEFAULT, StudioRig

# The baked light of the hull. The studio default left the shadow sides (undersides of the struts, the fuselage's flanks) nearly black
# against the black sky, and the play test kept finding "weird shading" there; the ambient is lifted, as the raider's was.
STARFURY_RIG = StudioRig(
    sky=(0.46, 0.47, 0.50),
    ground=(0.24, 0.24, 0.26),
    lights=STUDIO_DEFAULT.lights,
    exposure=1.05,
)
from ..core.manifest import build_manifest, lod_entry, write_manifest
from ..core.obj import write_obj
from ..core.ply import SplatData, write_ply
from ..core.sampling import (
    DEFAULT_OVERLAP,
    DEFAULT_THICKNESS,
    SurfaceSamples,
    sample_mesh,
    to_splats,
)
from ..parts import Anchor, Part, mass_centroid, total_mass
from ..parts.hull import (
    WedgeFuselageSpec,
    WedgeStation,
    wedge_cockpit_faces,
    wedge_cockpit_interior,
    wedge_fuselage,
)
from ..parts.propulsion import (
    ClawSpec,
    RcsBlockSpec,
    RingPodSpec,
    VaneSpec,
    claw_cluster,
    pilot_tags,
    ring_pod,
)
from ..parts.structure import TrussStrutSpec, truss_strut
from ..parts.weapons import GunMountSpec, gun_mount
from ..styles import Style
from ..styles.earthforce import EARTHFORCE

ASSET_ID = "starfury_aurora"
GENERATOR_VERSION = 2
PLY_NAME = "starfury_aurora.ply"
OBJ_NAME = "starfury_aurora.obj"
COCKPIT_NAME = "cockpit_interior.obj"
HARDPOINTS_NAME = "hardpoints.json"

DEFAULT_SPACING_M = 0.04
COCKPIT_SPACING_FACTOR = (
    0.55  # the window segment's frames, chin and lining, seen from 0.6-1 m
)
SPLAT_BUDGET = (100_000, 250_000)  # AC3, at the default spacing
CHASE_ANCHOR = (
    0.0,
    4.0,
    17.0,
)  # behind and above the centroid; frames the 15 m claw span at 70 deg FOV
JSON_DIGITS = 5
BURIED_MARGIN_M = 0.01  # samples deeper than this inside another part are dropped
POD_NAMES = {"": "ur", "y": "lr", "x": "ul", "xy": "ll"}  # mirror key -> pod name
POD_SIDES = (("ur", "right"), ("lr", "right"), ("ul", "left"), ("ll", "left"))

# LOD1 (allies and all Starfury debris, architecture section 16 D35): every spacing (the cockpit
# faces' too) times this factor; the splat scales grow with the spacing, so the sheet closes as
# LOD0's does. 2.0 lands at about 25 % of LOD0's splats.
LOD1_PLY_NAME = "starfury_aurora_lod1.ply"
LOD1_SPACING_FACTOR = 2.0
LOD1_STREAM = "lod1"  # suffix of every LOD1 RNG stream: ctx.rng("splats", <part>, "lod1")
LOD1_SHARE = (0.20, 0.30)  # AC6: LOD1 splats / LOD0 splats, at the default spacing and factor
CHUNK_LOD = 1  # the chunks partition this LOD's splats
# Break-up chunks, in LOD1 file order: the cabin (fuselage, cockpit faces, gun mount) and one arm
# (pod, strut, claw) per corner, named after the pods (DamageZones' X-fighter cabin and arms).
CHUNK_ORDER = ("cabin",) + tuple(f"arm_{pod}" for pod, _ in POD_SIDES)
ARM_PARTS = ("pod", "strut", "claw")


# --- the parametric description --------------------------------------------------------------
STARFURY_FUSELAGE = WedgeFuselageSpec(
    stations=(
        # Front pane, seen from the eye (0, 0.35, 1.0): a trapezoid raked 15 deg, its sill 20 deg
        # below the line of sight (corners +-26 deg), its top 38 deg above (corners +-42 deg).
        WedgeStation(
            0.00, 0.933, 0.672, 0.76, 0.80, 0.49, -0.015, rake=math.radians(15.0)
        ),
        # Rear edge of the panes; its shoulder lies on the plane through the eye and the front
        # pane's shoulder (30 deg up), so the frame over the side panes continues the top bar.
        WedgeStation(1.35, 1.12, 0.88, 1.32, 0.15, 0.64, -0.80),
        WedgeStation(2.60, 1.28, 1.00, 1.45, 0.08, 0.70, -1.05),
        WedgeStation(4.40, 1.32, 1.08, 1.55, 0.10, 0.75, -1.15),
        WedgeStation(5.20, 1.20, 1.00, 1.45, 0.10, 0.70, -1.05),
    ),
    chamfer=0.045,
    window_end=1,
    frame_width=0.07,
    eye=(0.0, 0.35, 1.0),
    glass_facets=("lower", "upper", "top"),  # side panes, roof-side panes, roof
    mass_kg=16_000.0,
)
# The heavy dark frame of the reference view, from inside: 9 cm bars (about 5 deg), a 45 cm sill.
COCKPIT_BARS = {"bar_width": 0.09, "bar_depth": 0.06, "sill_depth": 0.45}
STARFURY_GUN_MOUNT = GunMountSpec(barrel_mount_z=-0.6, mass_kg=2_000.0)
STARFURY_POD = RingPodSpec(
    bosses=(0.0, 90.0), boss_radius=0.2, boss_height=0.12, mass_kg=5_000.0
)
HAZARD = tuple(
    (1.6 + 0.35 * k, 1.95 + 0.35 * k, "hazard" if k % 2 == 0 else "hazard_dark")
    for k in range(5)
)
STARFURY_STRUT = TrussStrutSpec(
    length=5.155,
    chord_root=3.5,
    chord_tip=1.65,
    sweep=3.2,
    web_depth_root=0.5,
    web_depth_tip=0.34,
    rail=0.09,
    rung=0.12,
    cutouts=7,
    cutout_span=(0.2, 0.84),
    bands=HAZARD,
    mass_kg=1_500.0,
)
STARFURY_CLAW = ClawSpec(
    vanes=(
        VaneSpec(35.0, 0.85, 1.4, ((1.7, 42.0), (1.9, 14.0)), offset=0.2),
        VaneSpec(35.0, 0.85, 1.4, ((1.7, 42.0), (1.9, 14.0)), offset=-0.2),
        VaneSpec(
            215.0,
            0.82,
            1.7,
            ((1.0, 38.0), (1.1, 12.0)),
            chord=(0.28, 0.12),
            thickness=(0.2, 0.08),
        ),
    ),
    blocks=(
        RcsBlockSpec(35.0, 0.84, 1.55, (0.46, 0.46, 0.8), ("px", "py")),
        RcsBlockSpec(215.0, 0.82, 1.75, (0.42, 0.42, 0.65), ("nx", "ny")),
    ),
    mass_kg=1_000.0,
)


@dataclass(frozen=True)
class StarfurySpec:
    fuselage: WedgeFuselageSpec = STARFURY_FUSELAGE
    gun_mount: GunMountSpec = STARFURY_GUN_MOUNT
    gun_mount_center: tuple[float, float, float] = (
        0.0,
        -0.72,
        1.7,
    )  # housing front at z = 0.6, under the chin
    pod: RingPodSpec = STARFURY_POD
    pod_center: tuple[float, float, float] = (
        5.5,
        2.2,
        5.0,
    )  # upper right; mirrored to the others
    strut: TrussStrutSpec = STARFURY_STRUT
    strut_root: tuple[float, float, float] = (
        0.6,
        0.6,
        1.2,
    )  # root leading edge, inside the fuselage
    claw: ClawSpec = STARFURY_CLAW

    def strut_rotation(self) -> np.ndarray:
        """Rotation about Z that lays the strut's span from its root towards the pod centre."""
        dx, dy = (
            self.pod_center[0] - self.strut_root[0],
            self.pod_center[1] - self.strut_root[1],
        )
        return rotation_z(math.atan2(dy, dx))


DEFAULT_SPEC = StarfurySpec()


@dataclass
class Placed:
    """A placed part with its surface samples (``None`` for meshes that are not splatted)."""

    part: Part
    samples: SurfaceSamples | None
    hull: bool = True  # part of the fallback mesh, the mass and the collision shapes
    spacing: float = 0.0  # sample spacing of ``samples`` (m)

    def translated(self, offset: np.ndarray) -> Placed:
        return Placed(
            self.part.translated(offset),
            None if self.samples is None else self.samples.translated(offset),
            self.hull,
            self.spacing,
        )


def _mirrors(base: Placed, prefix: str) -> list[Placed]:
    """The upper-right placement plus its mirror images ``<prefix>_ur/lr/ul/ll``; samples are
    mirrored with the mesh, so the set is exactly symmetric."""
    out = []
    for key, pod in POD_NAMES.items():
        part, samples = base.part, base.samples
        for axis in key:
            part = part.mirrored(axis)
            samples = None if samples is None else samples.mirrored(axis)
        out.append(
            Placed(
                part.renamed(f"{prefix}_{pod}", group=base.part.group),
                samples,
                base.hull,
                base.spacing,
            )
        )
    return out


def _unburied(samples: SurfaceSamples, *inside: np.ndarray) -> SurfaceSamples:
    """Drop the samples flagged by any of the ``inside`` masks."""
    buried = np.zeros(len(samples), dtype=bool)
    for mask in inside:
        buried |= mask
    return samples.subset(~buried)


def build_parts(
    spec: StarfurySpec,
    style: Style,
    ctx: BuildContext,
    spacing: float,
    cockpit_spacing: float,
    stream_suffix: tuple[str, ...] = (),
) -> list[Placed]:
    """Place every part in the authored frame and sample it (symmetric by construction). The
    body group is already shifted so its sample centroid's y is zero (the cross is symmetric).
    The faces the pilot sees up close (``wedge_cockpit_faces``) are a separate ``cockpit``
    placement sampled at ``cockpit_spacing``; its mesh stays part of the fuselage's.
    ``stream_suffix`` is appended to every RNG stream (``("lod1",)`` for LOD1), so another LOD's
    samples never disturb LOD0's."""

    def sample(mesh: Mesh, stream: str, step: float = spacing) -> SurfaceSamples:
        return sample_mesh(mesh, step, ctx.rng("splats", stream, *stream_suffix))

    # Body: centre-line parts, sampled and made exactly x-symmetric.
    fus = wedge_fuselage(spec.fuselage, style).renamed("fuselage", group="body")
    near = wedge_cockpit_faces(spec.fuselage, fus.mesh, style)
    fus_samples = sample(fus.mesh.face_subset(~near), "fuselage").symmetrized("x")
    cockpit = Part("cockpit", fus.mesh.face_subset(near), group="body")
    cockpit_samples = sample(cockpit.mesh, "cockpit", cockpit_spacing).symmetrized("x")
    gun = (
        gun_mount(spec.gun_mount, style)
        .translated(spec.gun_mount_center)
        .renamed("gun_mount", group="body")
    )
    gun_samples = sample(gun.mesh, "gun_mount")
    gun_samples = _unburied(
        gun_samples, spec.fuselage.contains(gun_samples.positions, BURIED_MARGIN_M)
    ).symmetrized("x")
    interior = Part(
        "cockpit_interior",
        wedge_cockpit_interior(spec.fuselage, style, **COCKPIT_BARS),
        group="body",
    )
    body = [
        Placed(fus, fus_samples, spacing=spacing),
        Placed(cockpit, cockpit_samples, hull=False, spacing=cockpit_spacing),
        Placed(gun, gun_samples, spacing=spacing),
        Placed(interior, None, hull=False),
    ]
    body_samples = [p.samples for p in body if p.samples is not None]
    y_shift = -sum(float(s.positions[:, 1].sum()) for s in body_samples) / sum(
        len(s) for s in body_samples
    )
    body = [p.translated(np.array([0.0, y_shift, 0.0])) for p in body]

    # Cross: the upper-right pod, strut and claw, minus what is buried in the (shifted)
    # fuselage or the pod, then mirrored four ways. The fuselage is not symmetric in y, so a
    # strut sample is only dropped when it is inside the fuselage *and* its y mirror image.
    def in_fuselage(points: np.ndarray) -> np.ndarray:
        local = points - np.array([0.0, y_shift, 0.0])
        flipped = local * np.array([1.0, -1.0, 1.0])
        return spec.fuselage.contains(local, BURIED_MARGIN_M) & spec.fuselage.contains(
            flipped, BURIED_MARGIN_M
        )

    pod_c = np.asarray(spec.pod_center, dtype=float)

    def in_pod(points: np.ndarray) -> np.ndarray:
        return spec.pod.contains(points - pod_c, BURIED_MARGIN_M)

    pod = ring_pod(spec.pod, style).translated(pod_c).renamed("pod_ur", group="cross")
    strut = (
        truss_strut(spec.strut, style)
        .transformed(spec.strut_rotation(), spec.strut_root)
        .renamed("strut_ur", group="cross")
    )
    claw = (
        claw_cluster(spec.claw, style)
        .translated(pod_c)
        .renamed("claw_ur", group="cross")
    )
    s_pod = sample(pod.mesh, "pod")
    # The bells' outer walls and the bosses' bases are inside the shell; the bells' inner walls
    # (facing the axis) are what shows through the exits and stay.
    radial = s_pod.positions[:, :2] - pod_c[:2]
    facing_out = np.einsum(
        "ij,ij->i", s_pod.normals[:, :2], radial
    ) > 0.2 * np.linalg.norm(radial, axis=1)
    s_pod = _unburied(s_pod, in_pod(s_pod.positions) & facing_out)
    s_strut = sample(strut.mesh, "strut")
    s_strut = _unburied(
        s_strut, in_fuselage(s_strut.positions), in_pod(s_strut.positions)
    )
    s_claw = sample(claw.mesh, "claw")
    s_claw = _unburied(s_claw, in_pod(s_claw.positions))
    cross = (
        _mirrors(Placed(pod, s_pod, spacing=spacing), "pod")
        + _mirrors(Placed(strut, s_strut, spacing=spacing), "strut")
        + _mirrors(Placed(claw, s_claw, spacing=spacing), "claw")
    )
    return body + cross


# --- centring ---------------------------------------------------------------------------------
def centre(placed: list[Placed]) -> tuple[list[Placed], np.ndarray]:
    """Subtract the splat centroid's z from everything (x and y are already zero by symmetry
    and the body shift). Returns the placements and the offset (Godot frame) that was
    subtracted from the authored positions (``manifest.centroid_offset``)."""
    sampled = [p.samples for p in placed if p.samples is not None]
    total = sum(len(s) for s in sampled)
    z_mean = sum(float(s.positions[:, 2].sum()) for s in sampled) / total
    offset = np.array([0.0, 0.0, z_mean])
    return [p.translated(-offset) for p in placed], offset


def chunk_of(part_name: str) -> str:
    """The break-up chunk a part belongs to: a corner's pod, strut and claw are ``arm_<pod>``,
    everything else (fuselage, cockpit faces, gun mount, cockpit interior) is the ``cabin``."""
    kind, _, pod = part_name.rpartition("_")
    if kind in ARM_PARTS and pod in POD_NAMES.values():
        return f"arm_{pod}"
    return "cabin"


# --- colour -----------------------------------------------------------------------------------
def _phase(name: str, style: Style) -> tuple[float, float, float]:
    base = name.split("_")[0]
    h = sum((i + 1) * ord(c) for i, c in enumerate(base))
    return tuple(((h * k) % 97) / 97.0 * style.panel_size_m for k in (7, 11, 13))


def colour_samples(placed: Placed, style: Style, rig: StudioRig) -> np.ndarray:
    s = placed.samples
    albedo = style.shade_panels(
        s.albedo(),
        s.positions,
        s.normals,
        s.material_flag("paneled") > 0.5,
        _phase(placed.part.name, style),
    )
    return rig.shade(s.normals, albedo, s.material_flag("metallic"))


# --- hardpoints -------------------------------------------------------------------------------
def _r(v: Any) -> list[float]:
    return [
        round(float(x), JSON_DIGITS) + 0.0
        for x in np.asarray(v, dtype=float).reshape(-1)
    ]


def _anchor_json(a: Anchor, direction_key: str | None = None) -> dict[str, Any]:
    out: dict[str, Any] = {"position": _r(a.position)}
    if direction_key and a.direction is not None:
        out[direction_key] = _r(a.direction)
    return out


def _axis_label(direction: np.ndarray) -> str:
    axis = int(np.argmax(np.abs(direction)))
    return ("p" if direction[axis] > 0 else "n") + "xyz"[axis]


def hardpoints(
    placed: list[Placed], spec: StarfurySpec, chunks: list[dict[str, Any]]
) -> dict[str, Any]:
    """The hardpoints document (centred Godot frame) from the placed LOD0 parts; ``chunks`` are
    the ``write_chunks`` entries (from LOD1)."""
    by_name = {p.part.name: p.part for p in placed}
    hull_parts = [p.part for p in placed if p.hull]
    hull_mesh = Mesh.concatenate(p.mesh for p in hull_parts)
    lo, hi = hull_mesh.bounds()

    com = mass_centroid(hull_parts)
    com = np.array(
        [0.0, 0.0, com[2]]
    )  # trimmed to the thrust axis by design (ballast), see docs
    mass = total_mass(hull_parts)
    inertia = np.zeros(3)
    for part in hull_parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array(
            [d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2]
        )

    pods = []
    rcs = []
    for name, side in POD_SIDES:
        pod = by_name[f"pod_{name}"]
        pods.append(
            {
                "name": name,
                "side": side,
                "center": _r(pod.anchor("center").position),
                "main": {
                    **_anchor_json(pod.anchor("main"), "exhaust"),
                    "radius": spec.pod.main.exit_r,
                },
                "retro": {
                    **_anchor_json(pod.anchor("retro"), "exhaust"),
                    "radius": spec.pod.retro.exit_r,
                },
            }
        )
        claw = by_name[f"claw_{name}"]
        for key in ("rcs_px", "rcs_nx", "rcs_py", "rcs_ny"):
            a = claw.anchor(key)
            rcs.append(
                {
                    "name": f"{name}_{_axis_label(a.direction)}",
                    "pod": name,
                    "position": _r(a.position),
                    "exhaust": _r(a.direction),
                    "tags": pilot_tags(a.position, a.direction, com),
                }
            )

    gun = by_name["gun_mount"]
    muzzles = [
        {"name": n, **_anchor_json(gun.anchor(f"muzzle_{n}"), "direction")}
        for n in ("left", "right")
    ]
    eye = by_name["fuselage"].anchor("eye")
    collision = []
    for part in hull_parts:
        for shape in part.collision:
            collision.append({**shape.to_json(digits=JSON_DIGITS), "name": part.name})

    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(float(hi[2] - lo[2]), 3),
        "span_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "mass_kg": round(mass, 1),
        "inertia_estimate_kg_m2": _r(inertia),
        "center_of_mass": _r(com),
        "cockpit_camera": {
            "position": _r(eye.position),
            "forward": _r(eye.direction),
            "up": [0.0, 1.0, 0.0],
        },
        "chase_anchor": {"position": list(CHASE_ANCHOR)},
        "muzzles": muzzles,
        "pods": pods,
        "rcs": rcs,
        "collision": collision,
        "chunks": chunks,
    }


# --- build ------------------------------------------------------------------------------------
def part_splats(
    placed: list[Placed], style: Style, rig: StudioRig, overlap: float, thickness: float
) -> SplatData:
    """The splats of every sampled placement, in order (body frame, Godot axes)."""
    return SplatData.concatenate(
        [
            to_splats(
                p.samples, colour_samples(p, style, rig), p.spacing, overlap, thickness
            )
            for p in placed
            if p.samples is not None
        ]
    )


def _to_3dgs(splats: SplatData) -> SplatData:
    """Rz(180 deg) of the Godot frame: what the PLY stores, so the splat node stays at identity."""
    return SplatData(
        xyz=frames.godot_to_3dgs_positions(splats.xyz),
        rgb=splats.rgb,
        alpha=splats.alpha,
        scale=splats.scale,
        rot=frames.godot_to_3dgs_quats(splats.rot),
        normals=frames.flip_xy(splats.normals),
    )


def build_chunks(
    placed: list[Placed], style: Style, rig: StudioRig, overlap: float, thickness: float
) -> list[ChunkSource]:
    """One ``ChunkSource`` per ``CHUNK_ORDER`` entry: its parts' splats (placement order) and
    their fallback mesh. The cockpit faces' mesh is already in the fuselage's, and the cockpit
    interior is neither splatted nor hull, so neither adds to a chunk mesh."""
    sources = []
    for name in CHUNK_ORDER:
        members = [p for p in placed if chunk_of(p.part.name) == name]
        mesh = Mesh.concatenate(p.part.mesh for p in members if p.hull)
        sources.append(
            ChunkSource(name, part_splats(members, style, rig, overlap, thickness), mesh)
        )
    return sources


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the ship into ``ctx.out_dir``.

    Options: ``spacing`` (m, default 0.04; the CLI's ``--spacing``), ``cockpit_spacing`` (m,
    default 0.55 x the spacing: the window segment's frames, chin and lining), ``overlap``
    (sigma / spacing, default 1.0), ``thickness`` (normal sigma / spacing, default 0.08),
    ``lod1_factor`` (LOD1 spacing / LOD0 spacing, default 2.0).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    cockpit_spacing = float(
        ctx.option("cockpit_spacing", COCKPIT_SPACING_FACTOR * spacing)
    )
    overlap = float(ctx.option("overlap", DEFAULT_OVERLAP))
    thickness = float(ctx.option("thickness", DEFAULT_THICKNESS))
    lod1_factor = float(ctx.option("lod1_factor", LOD1_SPACING_FACTOR))
    if min(spacing, cockpit_spacing, overlap, thickness, lod1_factor) <= 0.0:
        raise ValueError(
            "spacing, cockpit_spacing, overlap, thickness and lod1_factor must be positive"
        )
    spec, style, rig = DEFAULT_SPEC, EARTHFORCE, STARFURY_RIG

    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    # LOD0: the full-detail hull, part by part (manifest ``counts`` order).
    placed, offset = centre(build_parts(spec, style, ctx, spacing, cockpit_spacing))
    sampled = [p for p in placed if p.samples is not None]
    authored = part_splats(placed, style, rig, overlap, thickness)

    # Splats are already centred; the manifest AABB is theirs, Godot frame.
    xyz32 = authored.xyz.astype(np.float32)
    aabb_min, aabb_max = xyz32.min(axis=0), xyz32.max(axis=0)
    comments = (
        f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",
        "frame: 3dgs (Rz180 of godot)",
    )
    files: list[Path] = [write_ply(out_dir / PLY_NAME, _to_3dgs(authored), comments)]

    hull_mesh = Mesh.concatenate(p.part.mesh for p in placed if p.hull)
    files += write_obj(out_dir / OBJ_NAME, hull_mesh, ASSET_ID, comments[:1])
    interior = next(p.part.mesh for p in placed if p.part.name == "cockpit_interior")
    files += write_obj(
        out_dir / COCKPIT_NAME, interior, "cockpit_interior", comments[:1]
    )

    # LOD1: the same parts resampled coarser from their own streams, balanced and centred
    # like LOD0 (its splat centroid is the origin too), written chunk by chunk.
    lod1_spacing = lod1_factor * spacing
    lod1_placed, _ = centre(
        build_parts(
            spec,
            style,
            ctx,
            lod1_spacing,
            lod1_factor * cockpit_spacing,
            (LOD1_STREAM,),
        )
    )
    chunk_sources = build_chunks(lod1_placed, style, rig, overlap, thickness)
    lod1 = SplatData.concatenate([c.splats for c in chunk_sources])
    lod1_comments = comments + (f"lod {CHUNK_LOD}",)
    files.append(write_ply(out_dir / LOD1_PLY_NAME, _to_3dgs(lod1), lod1_comments))
    chunk_files, chunk_entries = write_chunks(
        out_dir, ASSET_ID, chunk_sources, lod1_comments
    )
    files += chunk_files

    hp = hardpoints(placed, spec, chunk_entries)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    total = len(authored)
    warnings: list[str] = []
    if abs(spacing - DEFAULT_SPACING_M) < 1e-12:
        if not SPLAT_BUDGET[0] <= total <= SPLAT_BUDGET[1]:
            warnings.append(
                f"{total} splats is outside the AC3 budget {SPLAT_BUDGET} at the default spacing"
            )
        share = len(lod1) / total
        if (
            abs(lod1_factor - LOD1_SPACING_FACTOR) < 1e-12
            and not LOD1_SHARE[0] <= share <= LOD1_SHARE[1]
        ):
            warnings.append(
                f"LOD1 has {share:.1%} of LOD0's splats, outside the AC6 share {LOD1_SHARE}"
            )
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        lods=[
            lod_entry(0, PLY_NAME, total, spacing),
            lod_entry(CHUNK_LOD, LOD1_PLY_NAME, len(lod1), lod1_spacing),
        ],
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=offset,
        files={
            "fallback_mesh": OBJ_NAME,
            "cockpit_mesh": COCKPIT_NAME,
            "hardpoints": HARDPOINTS_NAME,
        },
        extra={
            "counts": {p.part.name: len(p.samples) for p in sampled},
            "sampling": {
                "spacing_m": spacing,
                "cockpit_spacing_m": cockpit_spacing,
                "overlap": overlap,
                "thickness": thickness,
            },
            "dimensions_m": {
                "length": hp["length_m"],
                "span": hp["span_m"],
                "height": hp["height_m"],
            },
            "chunks": [c["name"] for c in chunk_entries],
            "chunk_lod": CHUNK_LOD,
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), tuple(warnings))
