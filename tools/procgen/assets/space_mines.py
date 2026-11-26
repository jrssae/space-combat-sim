"""``space_mines``: the three mine kinds' meshes (M10-T15, Q20, docs/assets-capital.md "Mines").

One small textured mesh per kind, drawn by a MultiMesh in the game (a field of hundreds is a draw call a kind):

* ``mine_prox``: a dark red ball, 2.4 m across, with eight spikes and a blinking-red eye band round its waist.
* ``mine_energy``: a squat pod, 5 m long, a glowing amber ring round its middle and four short fins; what a G'Quan launches.
* ``mine_guided``: a slim body, 3.6 m long, a nose cone, four tail fins and a cold blue motor ring; what a Vorchan drops.

Composition only, like ``nav_buoy``: ``core.geometry`` lathes, one textured mesh per kind (``core.textured_mesh``), the three
kinds' ``mesh`` sections in the manifest's ``mines``. The game falls back on a plain sphere when this is not generated.
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Any

import numpy as np

from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Material, Mesh, box, lathe, rotation_x, rotation_y
from ..core.manifest import build_manifest, write_manifest
from ..core.textured_mesh import TexturedPart, phase_steps, write_textured_mesh
from ..styles.earthforce import EARTHFORCE

ASSET_ID = "space_mines"
GENERATOR_VERSION = 1
KINDS: tuple[str, ...] = ("mine_prox", "mine_energy", "mine_guided")
ATLAS_PX = 256
TEXEL_M = 0.02
SEGMENTS = 14
JSON_DIGITS = 4

BODY = Material("mine_body", (0.11, 0.045, 0.04), paneled=True, metallic=0.6, roughness=0.5)
PLATE = Material("mine_plate", (0.07, 0.07, 0.075), paneled=True, metallic=0.7, roughness=0.45)
SPIKE = Material("mine_spike", (0.05, 0.05, 0.05), metallic=0.8, roughness=0.4)
EYE = Material("mine_eye", (0.25, 0.02, 0.01), emissive=(1.0, 0.1, 0.05), emissive_strength=4.0)
AMBER = Material("mine_amber", (0.3, 0.14, 0.02), emissive=(1.0, 0.6, 0.15), emissive_strength=4.0)
MOTOR = Material("mine_motor", (0.04, 0.12, 0.25), emissive=(0.25, 0.6, 1.0), emissive_strength=4.0)


def _ball(radius: float, material: Material) -> Mesh:
    """A sphere as a lathe of a half circle (poles on local z)."""
    steps = 9
    profile = [(-radius * math.cos(math.pi * k / steps), radius * math.sin(math.pi * k / steps)) for k in range(steps + 1)]
    return lathe(profile, SEGMENTS, material)


def _cone(length: float, radius: float, material: Material) -> Mesh:
    """A cone from its base at z = 0 to its point at z = -length."""
    return lathe([(-length, 0.0), (0.0, radius)], 8, material)


def _slab(length: float, depth: float, material: Material) -> Mesh:
    """A thin fin along z, `depth` out from its root on the axis."""
    return box((0.05, depth, length), material, (0.0, 0.5 * depth, 0.0))


def _around_z(mesh: Mesh, count: int, tilt: float = 0.0) -> list[Mesh]:
    """`count` copies turned about z (x then the rest), each optionally pushed out by turning about x first."""
    out = []
    for k in range(count):
        angle = 2.0 * math.pi * k / count
        c, s = math.cos(angle), math.sin(angle)
        spin = np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])
        out.append(mesh.transformed(spin @ (rotation_x(tilt) if tilt else np.eye(3))))
    return out


def prox() -> list[TexturedPart]:
    ball = _ball(1.2, BODY)
    spike = _cone(0.8, 0.16, SPIKE).transformed(rotation_y(-0.5 * math.pi), (1.15, 0.0, 0.0))  # points out along +x
    spikes: list[Mesh] = []
    for k in range(8):
        spikes += [spike.transformed(_axis_turn(k))]
    eye = lathe([(-0.25, 0.0), (-0.25, 1.22), (0.25, 1.22), (0.25, 0.0)], SEGMENTS, EYE, creases=(1, 2))
    return [TexturedPart(ball, phase_steps("ball", False), (), "ball"),
            TexturedPart(Mesh.concatenate(spikes), phase_steps("spikes", False), (), "spikes"),
            TexturedPart(eye, (0, 0, 0), (), "eye")]


def _axis_turn(k: int) -> np.ndarray:
    """The eight spikes' turns: four round the waist, then four tilted 45 degrees up and down alternately."""
    yaw = 0.5 * math.pi * (k % 4)
    pitch = 0.0 if k < 4 else (0.25 * math.pi if k % 2 == 0 else -0.25 * math.pi)
    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    about_z = np.array([[cy, -sy, 0.0], [sy, cy, 0.0], [0.0, 0.0, 1.0]])
    about_y = np.array([[cp, 0.0, sp], [0.0, 1.0, 0.0], [-sp, 0.0, cp]])
    return about_z @ about_y


def energy() -> list[TexturedPart]:
    body = lathe([(-2.5, 0.0), (-2.1, 1.0), (-1.2, 1.5), (1.2, 1.5), (2.1, 1.0), (2.5, 0.0)], SEGMENTS, BODY, creases=(2, 3))
    ring = lathe([(-0.3, 0.0), (-0.3, 1.58), (0.3, 1.58), (0.3, 0.0)], SEGMENTS, AMBER, creases=(1, 2))
    fins = Mesh.concatenate(_around_z(_slab(1.4, 0.9, PLATE).translated((0.0, 1.4, 1.1)), 4))
    return [TexturedPart(body, phase_steps("pod", False), (), "pod"),
            TexturedPart(fins, phase_steps("fins", False), (), "fins"),
            TexturedPart(ring, (0, 0, 0), (), "ring")]


def guided() -> list[TexturedPart]:
    body = lathe([(-1.8, 0.0), (-1.1, 0.5), (-0.4, 0.62), (1.4, 0.62), (1.8, 0.45)], SEGMENTS, BODY, creases=(2, 3))
    tail = lathe([(1.4, 0.0), (1.4, 0.45), (1.9, 0.5), (1.9, 0.0)], SEGMENTS, MOTOR, creases=(1, 2))
    fins = Mesh.concatenate(_around_z(_slab(1.2, 0.8, PLATE).translated((0.0, 0.6, 1.0)), 4))
    return [TexturedPart(body, phase_steps("body", False), (), "body"),
            TexturedPart(fins, phase_steps("fins", False), (), "fins"),
            TexturedPart(tail, (0, 0, 0), (), "motor")]


BUILDERS = {"mine_prox": prox, "mine_energy": energy, "mine_guided": guided}


def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the three meshes into ``ctx.out_dir``."""
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    mines: dict[str, Any] = {}
    lows, highs = [], []
    for kind in KINDS:
        parts = BUILDERS[kind]()
        paths, entry = write_textured_mesh(out_dir, f"{ASSET_ID}_{kind}", parts, EARTHFORCE, atlas_px=ATLAS_PX, texel_m=TEXEL_M,
                                           seed=ctx.seed, occlusion=False, normal_scale=1)
        files += paths
        mines[kind] = entry
        lo, hi = Mesh.concatenate([p.mesh for p in parts]).bounds()
        lows.append(lo)
        highs.append(hi)
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=np.min(lows, axis=0),
        aabb_max=np.max(highs, axis=0),
        centroid_offset=np.zeros(3),
        files={},
        extra={"mines": mines, "radius_m": {k: _r(max(np.linalg.norm(h) for h in (hi, lo)))[0] for k, lo, hi in zip(KINDS, lows, highs)}},
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
