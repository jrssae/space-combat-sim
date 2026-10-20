"""``starfury_aurora``: the player's Starfury-inspired fighter (docs/architecture.md section 9.1).

Composition only: this module places parts from ``parts/`` with the ``earthforce`` style and
derives every output from the placed parts, so the splats (``.ply``), the fallback mesh
(``.obj``), the cockpit interior mesh and ``hardpoints.json`` agree by construction.

Layout (authored Godot frame, metres, before re-centring; -Z is forward):

* fuselage 7.5 m, nose at z = -3.9, flat dark tail at z = +3.6; superellipse sections
* canopy dome on the forward top, 2.2 m long, eye point 0.3 m above its base, over a dark
  cockpit well
* dorsal spine block behind the canopy, ventral gun fairing under the nose
* two gun barrels under the nose at x = +-0.6, muzzles 0.9 m ahead of the nose tip
* four struts at +-45 deg in the X/Y plane, swept back, from the rear fuselage to the pods
* four engine pods (3.2 m x 1.1 m) centred at (+-3.18, +-3.18, 2.8): main bell aft, retro bell
  forward, four cosmetic RCS cones each

Frames: see ``docs/assets-starfury.md``. The sample set is made *exactly* mirror-symmetric
(samples on the x > 0 side are mirrored, the pod/strut cross is mirrored four ways), the
fuselage group is shifted so the splat centroid's y is exactly 0, and the z centroid is
subtracted, so the splat centroid is (0, 0, 0): GDGS's import centring is a no-op and the
hardpoints frame equals the rendered frame.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core import frames
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh, rotation_z
from ..core.lighting import STUDIO_DEFAULT, StudioRig
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
    CanopySpec,
    FuselageSection,
    FuselageSpec,
    canopy,
    cockpit_interior,
    cockpit_tub,
    fuselage,
)
from ..parts.propulsion import PodSpec, engine_pod, pilot_tags
from ..parts.structure import BlockSpec, StrutSpec, block, strut
from ..parts.weapons import BarrelSpec, gun_barrel
from ..styles import Style
from ..styles.earthforce import EARTHFORCE

ASSET_ID = "starfury_aurora"
GENERATOR_VERSION = 1
PLY_NAME = "starfury_aurora.ply"
OBJ_NAME = "starfury_aurora.obj"
COCKPIT_NAME = "cockpit_interior.obj"
HARDPOINTS_NAME = "hardpoints.json"

DEFAULT_SPACING_M = 0.035
SPLAT_BUDGET = (100_000, 250_000)  # AC3, at the default spacing
CHASE_ANCHOR = (0.0, 2.5, 9.0)  # docs/architecture.md section 8
JSON_DIGITS = 5


# --- the parametric description --------------------------------------------------------------
# Module-level part specs (frozen dataclasses) so StarfurySpec can use them as plain defaults.
STARFURY_FUSELAGE = FuselageSpec(
    sections=(
        FuselageSection(-3.90, 0.00, 0.00),
        FuselageSection(-3.75, 0.50, 0.42),
        FuselageSection(-3.30, 0.95, 0.80),
        FuselageSection(-2.70, 1.30, 1.10),
        FuselageSection(-1.90, 1.55, 1.32),
        FuselageSection(-0.80, 1.60, 1.40),
        FuselageSection(0.60, 1.60, 1.40),
        FuselageSection(1.80, 1.50, 1.30),
        FuselageSection(2.90, 1.30, 1.10),
        FuselageSection(3.60, 1.10, 0.95),
    ),
    mass_kg=15_800.0,
)
STARFURY_CANOPY = CanopySpec(length=2.2, width=0.9, height=0.55, mass_kg=400.0)
STARFURY_SPINE = BlockSpec(2.6, (0.7, 0.32), (0.5, 0.26), mass_kg=300.0)
STARFURY_FAIRING = BlockSpec(2.4, (1.1, 0.3), (1.5, 0.4), mass_kg=500.0)
STARFURY_BARREL = BarrelSpec(length=1.9, mass_kg=700.0)
STARFURY_POD = PodSpec(mass_kg=6_000.0)
STARFURY_STRUT = StrutSpec(length=3.35, sweep=0.6, mass_kg=1_400.0)


@dataclass(frozen=True)
class StarfurySpec:
    fuselage: FuselageSpec = STARFURY_FUSELAGE
    canopy: CanopySpec = STARFURY_CANOPY
    canopy_z: float = -1.8
    canopy_sink_into_hull: float = 0.02
    spine: BlockSpec = STARFURY_SPINE
    spine_z: float = 2.0
    fairing: BlockSpec = STARFURY_FAIRING
    fairing_z: float = -2.2
    barrel: BarrelSpec = STARFURY_BARREL
    barrel_x: float = 0.6
    barrel_mount_z: float = -2.9
    barrel_drop: float = 0.2  # muzzle axis above the fairing's bottom face
    pod: PodSpec = STARFURY_POD
    pod_radius_m: float = 4.5  # distance of a pod axis from the ship axis
    pod_angle_deg: float = 45.0
    pod_z: float = 2.8
    strut: StrutSpec = STARFURY_STRUT
    strut_root_radius: float = 0.65
    strut_root_z: float = 2.2


DEFAULT_SPEC = StarfurySpec()


@dataclass
class Placed:
    """A placed part with its surface samples (``None`` for meshes that are not splatted)."""

    part: Part
    samples: SurfaceSamples | None
    hull: bool = True  # part of the fallback mesh and the splats

    def translated(self, offset: np.ndarray) -> Placed:
        return Placed(
            self.part.translated(offset),
            None if self.samples is None else self.samples.translated(offset),
            self.hull,
        )


def _mirrors(base: Placed, axes: str, names: dict[str, str]) -> list[Placed]:
    """The base placement plus its mirror images: ``names`` maps a mirror key (``""``, ``"x"``,
    ``"y"``, ``"xy"``) to the part name; samples are mirrored with the mesh, so the set is
    exactly symmetric."""
    out = []
    for key, name in names.items():
        part, samples = base.part, base.samples
        for axis in key:
            part = part.mirrored(axis)
            samples = None if samples is None else samples.mirrored(axis)
        out.append(Placed(part.renamed(name, group=base.part.group), samples, base.hull))
    del axes
    return out


def build_parts(spec: StarfurySpec, style: Style, ctx: BuildContext, spacing: float) -> list[Placed]:
    """Place every part in the authored frame and sample it (symmetric by construction)."""

    def sample(part: Part, stream: str) -> SurfaceSamples:
        return sample_mesh(part.mesh, spacing, ctx.rng("splats", stream))

    placed: list[Placed] = []

    # Centre-line parts: sampled, then made exactly x-symmetric.
    fus = fuselage(spec.fuselage, style).renamed("fuselage", group="body")
    placed.append(Placed(fus, sample(fus, "fuselage").symmetrized("x")))

    y_base = spec.fuselage.top_y(spec.canopy_z) - spec.canopy_sink_into_hull
    can = canopy(spec.canopy, style).translated([0.0, y_base, spec.canopy_z]).renamed("canopy", group="body")
    placed.append(Placed(can, sample(can, "canopy").symmetrized("x")))
    tub = cockpit_tub(spec.canopy, style).translated([0.0, y_base, spec.canopy_z]).renamed("cockpit_tub", group="body")
    placed.append(Placed(tub, sample(tub, "cockpit_tub").symmetrized("x")))
    interior = Part("cockpit_interior", cockpit_interior(spec.canopy, style), group="body").translated(
        [0.0, y_base, spec.canopy_z]
    )
    placed.append(Placed(interior, None, hull=False))

    spine_top = spec.fuselage.top_y(spec.spine_z)
    spine_h = max(spec.spine.size_front[1], spec.spine.size_back[1])
    spn = block(spec.spine, style, "spine").translated([0.0, spine_top - 0.08 + 0.5 * spine_h, spec.spine_z])
    spn = spn.renamed("spine", group="body")
    placed.append(Placed(spn, sample(spn, "spine").symmetrized("x")))

    fairing_bottom = spec.fuselage.bottom_y(spec.fairing_z)
    fairing_h = max(spec.fairing.size_front[1], spec.fairing.size_back[1])
    fair = block(spec.fairing, style, "fairing").translated(
        [0.0, fairing_bottom + 0.06 - 0.5 * fairing_h, spec.fairing_z]
    )
    fair = fair.renamed("fairing", group="body")
    placed.append(Placed(fair, sample(fair, "fairing").symmetrized("x")))

    # Right-side parts, mirrored to the left.
    barrel_y = fair.mesh.bounds()[0][1] + spec.barrel_drop
    bar = gun_barrel(spec.barrel, style).translated([spec.barrel_x, barrel_y, spec.barrel_mount_z])
    bar = bar.renamed("barrel_r", group="body")
    placed += _mirrors(Placed(bar, sample(bar, "barrel")), "x", {"": "barrel_r", "x": "barrel_l"})

    # Upper-right quadrant parts, mirrored four ways (names: ur, lr, ul, ll).
    ang = math.radians(spec.pod_angle_deg)
    radial = np.array([math.cos(ang), math.sin(ang), 0.0])
    pod_pos = radial * spec.pod_radius_m + np.array([0.0, 0.0, spec.pod_z])
    pod = engine_pod(spec.pod, style).translated(pod_pos).renamed("pod_ur", group="cross")
    placed += _mirrors(
        Placed(pod, sample(pod, "pod")), "xy", {"": "pod_ur", "y": "pod_lr", "x": "pod_ul", "xy": "pod_ll"}
    )
    root = radial * spec.strut_root_radius + np.array([0.0, 0.0, spec.strut_root_z])
    st = strut(spec.strut, style).transformed(rotation_z(ang), root).renamed("strut_ur", group="cross")
    placed += _mirrors(
        Placed(st, sample(st, "strut")), "xy", {"": "strut_ur", "y": "strut_lr", "x": "strut_ul", "xy": "strut_ll"}
    )
    return placed


# --- centring ---------------------------------------------------------------------------------
def balance_and_centre(placed: list[Placed]) -> tuple[list[Placed], np.ndarray]:
    """Shift the ``body`` group so the splat centroid's y is exactly zero, then subtract the z
    centroid from everything. Returns the placements and the total offset (Godot frame) that
    was subtracted from the authored positions (``manifest.centroid_offset``)."""
    body = [p for p in placed if p.samples is not None and p.part.group == "body"]
    cross = [p for p in placed if p.samples is not None and p.part.group != "body"]
    n_body = sum(len(p.samples) for p in body)
    n_cross = sum(len(p.samples) for p in cross)
    y_body = sum(float(p.samples.positions[:, 1].sum()) for p in body) / n_body
    y_cross = sum(float(p.samples.positions[:, 1].sum()) for p in cross) / max(n_cross, 1)
    # The cross is mirrored in y, so its mean y is zero (to round-off); the body carries it all.
    shift = -(y_body + y_cross * n_cross / n_body)
    placed = [p.translated(np.array([0.0, shift, 0.0])) if p.part.group == "body" else p for p in placed]

    total = sum(len(p.samples) for p in placed if p.samples is not None)
    z_mean = sum(float(p.samples.positions[:, 2].sum()) for p in placed if p.samples is not None) / total
    offset = np.array([0.0, 0.0, z_mean])
    placed = [p.translated(-offset) for p in placed]
    return placed, offset


# --- colour -----------------------------------------------------------------------------------
def _phase(name: str, style: Style) -> tuple[float, float, float]:
    base = name.split("_")[0]
    h = sum((i + 1) * ord(c) for i, c in enumerate(base))
    return tuple(((h * k) % 97) / 97.0 * style.panel_size_m for k in (7, 11, 13))


def colour_samples(placed: Placed, style: Style, rig: StudioRig) -> np.ndarray:
    s = placed.samples
    albedo = style.shade_panels(s.albedo(), s.positions, s.normals, s.material_flag("paneled") > 0.5, _phase(placed.part.name, style))
    return rig.shade(s.normals, albedo, s.material_flag("metallic"))


# --- hardpoints -------------------------------------------------------------------------------
def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def _anchor_json(a: Anchor, direction_key: str | None = None) -> dict[str, Any]:
    out: dict[str, Any] = {"position": _r(a.position)}
    if direction_key and a.direction is not None:
        out[direction_key] = _r(a.direction)
    return out


def hardpoints(placed: list[Placed], spec: StarfurySpec) -> dict[str, Any]:
    """The hardpoints document (centred Godot frame) from the placed parts."""
    by_name = {p.part.name: p.part for p in placed}
    hull_parts = [p.part for p in placed if p.hull]
    hull_mesh = Mesh.concatenate(p.mesh for p in hull_parts)
    lo, hi = hull_mesh.bounds()

    com = mass_centroid(hull_parts)
    com = np.array([0.0, 0.0, com[2]])  # trimmed to the thrust axis by design (ballast), see docs
    mass = total_mass(hull_parts)
    inertia = np.zeros(3)
    for part in hull_parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array([d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2])

    pods = []
    rcs = []
    for name, side in (("ur", "right"), ("lr", "right"), ("ul", "left"), ("ll", "left")):
        pod = by_name[f"pod_{name}"]
        pods.append(
            {
                "name": name,
                "side": side,
                "center": _r(pod.anchor("center").position),
                "main": {**_anchor_json(pod.anchor("main"), "exhaust"), "radius": spec.pod.main.exit_r},
                "retro": {**_anchor_json(pod.anchor("retro"), "exhaust"), "radius": spec.pod.retro.exit_r},
            }
        )
        for key in ("rcs_px", "rcs_nx", "rcs_py", "rcs_ny"):
            a = pod.anchor(key)
            axis = int(np.argmax(np.abs(a.direction)))
            label = ("px" if a.direction[axis] > 0 else "nx") if axis == 0 else ("py" if a.direction[axis] > 0 else "ny")
            rcs.append(
                {
                    "name": f"{name}_{label}",
                    "pod": name,
                    "position": _r(a.position),
                    "exhaust": _r(a.direction),
                    "tags": pilot_tags(a.position, a.direction, com),
                }
            )

    muzzles = [
        {"name": n, **_anchor_json(by_name[p].anchor("muzzle"), "direction")}
        for n, p in (("left", "barrel_l"), ("right", "barrel_r"))
    ]
    eye = by_name["canopy"].anchor("eye")
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
        "cockpit_camera": {"position": _r(eye.position), "forward": _r(eye.direction), "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": list(CHASE_ANCHOR)},
        "muzzles": muzzles,
        "pods": pods,
        "rcs": rcs,
        "collision": collision,
    }


# --- build ------------------------------------------------------------------------------------
def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the ship into ``ctx.out_dir``.

    Options: ``spacing`` (m, default 0.06; the CLI's ``--spacing``), ``overlap`` (sigma /
    spacing, default 1.4), ``thickness`` (normal sigma / spacing, default 0.03).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    overlap = float(ctx.option("overlap", DEFAULT_OVERLAP))
    thickness = float(ctx.option("thickness", DEFAULT_THICKNESS))
    if spacing <= 0.0 or overlap <= 0.0 or thickness <= 0.0:
        raise ValueError("spacing, overlap and thickness must be positive")
    spec, style, rig = DEFAULT_SPEC, EARTHFORCE, STUDIO_DEFAULT

    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    placed, offset = balance_and_centre(build_parts(spec, style, ctx, spacing))
    sampled = [p for p in placed if p.samples is not None]
    samples = SurfaceSamples.concatenate([p.samples for p in sampled])
    rgb = np.concatenate([colour_samples(p, style, rig) for p in sampled])
    authored = to_splats(samples, rgb, spacing, overlap, thickness)

    # Splats are already centred (balance_and_centre); the manifest AABB is theirs, Godot frame.
    xyz32 = authored.xyz.astype(np.float32)
    aabb_min, aabb_max = xyz32.min(axis=0), xyz32.max(axis=0)
    written = SplatData(
        xyz=frames.godot_to_3dgs_positions(authored.xyz),
        rgb=authored.rgb,
        alpha=authored.alpha,
        scale=authored.scale,
        rot=frames.godot_to_3dgs_quats(authored.rot),
        normals=frames.flip_xy(authored.normals),
    )
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}", "frame: 3dgs (Rz180 of godot)")
    files: list[Path] = [write_ply(out_dir / PLY_NAME, written, comments)]

    hull_mesh = Mesh.concatenate(p.part.mesh for p in placed if p.hull)
    files += write_obj(out_dir / OBJ_NAME, hull_mesh, ASSET_ID, comments[:1])
    interior = next(p.part.mesh for p in placed if p.part.name == "cockpit_interior")
    files += write_obj(out_dir / COCKPIT_NAME, interior, "cockpit_interior", comments[:1])

    hp = hardpoints(placed, spec)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    total = len(authored)
    warnings: list[str] = []
    if abs(spacing - DEFAULT_SPACING_M) < 1e-12 and not SPLAT_BUDGET[0] <= total <= SPLAT_BUDGET[1]:
        warnings.append(f"{total} splats is outside the AC3 budget {SPLAT_BUDGET} at the default spacing")
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        lods=[lod_entry(0, PLY_NAME, total, spacing)],
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=offset,
        files={"fallback_mesh": OBJ_NAME, "cockpit_mesh": COCKPIT_NAME, "hardpoints": HARDPOINTS_NAME},
        extra={
            "counts": {p.part.name: len(p.samples) for p in sampled},
            "sampling": {"spacing_m": spacing, "overlap": overlap, "thickness": thickness},
            "dimensions_m": {"length": hp["length_m"], "span": hp["span_m"], "height": hp["height_m"]},
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), tuple(warnings))
