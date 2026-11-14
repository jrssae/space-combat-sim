"""``maintenance_bot``: the station's maintenance drone (M7-T11, Q11, D78; docs/assets-station.md "Maintenance bot").

Shape only, built from primitives after the maintainer's model sheet (gitignored, never traced): two long egg-shaped shell halves
side by side, each with two pale bands and a painted number, joined by a grey truss body; under it a sensor head with a green lens
and two jointed manipulator arms of three segments ending in claws; small thrusters at the shells' tails and on the truss. A
utility drone about 4.6 m long, no weapons, no cockpit.

Frame (authored Godot frame, metres): the nose is -Z, +Y is up (the arms hang to -Y), +X is starboard. The origin is the centroid
of the surface, as every asset's is. The game moves the bot along its loops with its nose along the way.

Outputs: the textured mesh (``maintenance_bot.glb``, its four maps), the OBJ, ``hardpoints.json`` (size, the bound the mover keeps
clear of the hull, the lamps) and the manifest. No collision: the bot is ambient (Q11) and takes no hit.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

import numpy as np

from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Material, Mesh, basis_from_z, box, lathe, rotation_y, tapered_box
from ..core.manifest import build_manifest, write_manifest
from ..core.obj import write_obj
from ..core.textured_mesh import TexturedPart, phase_steps, write_textured_mesh
from ..core.textures import Marking
from ..styles import Style
from ..styles.maintenance_bot import MAINTENANCE_BOT

ASSET_ID = "maintenance_bot"
GENERATOR_VERSION = 1
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"
JSON_DIGITS = 4
# The textured mesh: about 40 m² of surface on a 1 024 px atlas at 1.2 cm a texel.
ATLAS_PX = 1024
TEXEL_M = 0.012

# The glowing parts (linear RGB): the sensor lens, the lamps along the truss and the pods' tails.
LENS = Material("mb_lens", (0.01, 0.05, 0.015), roughness=0.1, emissive=(0.2, 1.0, 0.3), emissive_strength=3.0)
LAMP = Material("mb_lamp", (0.05, 0.035, 0.015), roughness=0.2, emissive=(1.0, 0.66, 0.26), emissive_strength=3.0)
NUMBER = (0.18, 0.14, 0.05)  # the painted number, a dark ochre, linear

# The shells: a long egg, pointed at the nose (-Z) and rounder at the tail, flattened (x, y squash) so the pair reads as a split egg.
SHELL_LENGTH_M = 4.4
SHELL_PROFILE = ((-2.2, 0.0), (-2.05, 0.2), (-1.7, 0.4), (-1.2, 0.54), (-0.7, 0.6), (0.5, 0.62), (1.0, 0.6), (1.6, 0.5), (2.0, 0.33),
                 (2.2, 0.0))
BAND_SEGMENTS = (3, 6)  # profile segments painted as bands (segment i runs from point i to point i + 1)
SHELL_SQUASH = (0.85, 0.7, 1.0)
SHELL_CENTRE_X_M = 0.95
SHELL_CENTRE_Y_M = 0.28
SHELL_SEGMENTS = 28

# The truss body between the shells and what hangs from it.
BEAM = (0.5, 0.4, 3.9)  # width, height, length
BEAM_Y_M = 0.12
NOSE_Z_M = -1.85
HEAD_Z_M = -1.2
THRUSTER_Z_M = 2.2


def _strut(p0: Any, p1: Any, width: float, height: float, material: Material) -> Mesh:
    """A square bar from ``p0`` to ``p1`` (a link of an arm, a brace)."""
    a, b = np.asarray(p0, dtype=float), np.asarray(p1, dtype=float)
    d = b - a
    return tapered_box(float(np.linalg.norm(d)), (width, height), (width, height), material).transformed(basis_from_z(d), 0.5 * (a + b))


def _joint(at: Any, radius: float, length: float, material: Material) -> Mesh:
    """A short dark cylinder along X: an arm's joint."""
    cyl = lathe([(-0.5 * length, 0.0), (-0.5 * length, radius), (0.5 * length, radius), (0.5 * length, 0.0)], 14, material, creases=(1, 2))
    return cyl.transformed(rotation_y(0.5 * math.pi), at)


def _cone(at: Any, radius: float, length: float, aim: float, outer: Material, throat: Material) -> Mesh:
    """A little thruster: a short bell opening toward +Z (``aim`` 1) or -Z, its throat glowing."""
    s = 1.0 if aim >= 0 else -1.0
    bell = lathe([(0.0, 0.5 * radius), (0.7 * length, radius), (length, 1.1 * radius), (length, 0.8 * radius), (0.9 * length, 0.0)], 12,
                 [outer, outer, throat, throat], creases=(1, 2))
    rot = np.diag([1.0, 1.0, s]) if s < 0 else np.eye(3)
    return bell.transformed(rot, at)


def _shell(style: Style) -> Mesh:
    """One shell half, centred at its own origin: the egg with its two bands."""
    shell, band = style.material("hull"), style.material("stripe")
    mats = [band if i in BAND_SEGMENTS else shell for i in range(len(SHELL_PROFILE) - 1)]
    egg = lathe(SHELL_PROFILE, SHELL_SEGMENTS, mats)
    return egg.transformed(np.diag(SHELL_SQUASH))


def _arm(style: Style, side: float, z: float, reach: float) -> list[Mesh]:
    """A manipulator arm of three segments with a claw, hanging from the truss at ``z`` on the ``side`` (+1 or -1) of it. ``reach``
    leans the arm fore (-1) or aft (+1)."""
    truss, dark, plate = style.material("hull_panel"), style.material("hull_dark"), style.material("hazard")
    x = 0.27 * side
    shoulder = np.array([x, BEAM_Y_M - 0.25, z])
    elbow = shoulder + np.array([0.12 * side, -0.9, 0.25 * reach])
    wrist = elbow + np.array([0.0, -0.65, 0.6 * reach])
    tip = wrist + np.array([0.0, -0.35, 0.15 * reach])
    out = [_joint(shoulder, 0.13, 0.26, dark), _strut(shoulder, elbow, 0.13, 0.13, truss), _joint(elbow, 0.11, 0.24, dark),
           _strut(elbow, wrist, 0.1, 0.1, plate), _joint(wrist, 0.09, 0.2, dark), _strut(wrist, tip, 0.1, 0.12, dark)]
    # The claw: two prongs closing on a point below the wrist.
    for sign in (-1.0, 1.0):
        out.append(_strut(tip + np.array([0.0, 0.0, 0.0]), tip + np.array([0.0, -0.32, 0.12 * sign]), 0.04, 0.06, dark))
    return out


def build_parts(style: Style = MAINTENANCE_BOT) -> list[TexturedPart]:
    """Every part of the bot in the authored frame, before the centring."""
    truss, plate, dark = style.material("hull_panel"), style.material("hazard"), style.material("hull_dark")
    nozzle, throat = style.material("nozzle"), style.material("nozzle_throat")
    shell = _shell(style)
    pod_r = shell.translated((SHELL_CENTRE_X_M, SHELL_CENTRE_Y_M, 0.0))
    pod_l = shell.mirrored("x").translated((-SHELL_CENTRE_X_M, SHELL_CENTRE_Y_M, 0.0))

    # The truss: a central beam, cross braces to the shells, plates and greebles on it.
    frame: list[Mesh] = [box(BEAM, truss, (0.0, BEAM_Y_M, 0.1))]
    for z in (-1.5, -0.4, 0.7, 1.7):
        frame.append(box((2.0, 0.14, 0.16), plate, (0.0, BEAM_Y_M + 0.13, z)))
        frame.append(box((2.0, 0.14, 0.16), plate, (0.0, BEAM_Y_M - 0.1, z)))
    frame.append(box((0.34, 0.2, 1.2), plate, (0.0, BEAM_Y_M + 0.3, -0.3)))
    frame.append(box((0.3, 0.16, 0.7), dark, (0.0, BEAM_Y_M + 0.28, 1.2)))
    for z in (-1.0, 0.1, 1.2):  # the lamps along the beam's top
        frame.append(box((0.07, 0.05, 0.07), LAMP, (0.12, BEAM_Y_M + 0.42, z)))
    # A short mast with a dish on the truss's top aft.
    frame.append(_strut((0.0, BEAM_Y_M + 0.35, 1.7), (0.0, BEAM_Y_M + 0.85, 1.75), 0.06, 0.06, dark))
    frame.append(lathe([(0.0, 0.0), (0.0, 0.16), (0.06, 0.12), (0.08, 0.0)], 14, plate).transformed(np.eye(3), (0.0, BEAM_Y_M + 0.88, 1.75)))

    # The sensor head under the front centre, its lens looking forward.
    head = [box((0.5, 0.42, 0.55), dark, (0.0, -0.38, HEAD_Z_M)), box((0.28, 0.22, 0.3), plate, (0.0, -0.18, HEAD_Z_M + 0.05))]
    lens = lathe([(0.0, 0.0), (0.0, 0.13), (-0.08, 0.1), (-0.1, 0.0)], 16, LENS)
    head.append(lens.transformed(np.eye(3), (0.0, -0.4, HEAD_Z_M - 0.27)))

    arms = _arm(style, -1.0, -0.9, -1.0) + _arm(style, 1.0, 1.3, 1.0)
    # The thrusters: a bell on the tail of each shell, two RCS cones at the beam's nose and four round the shells' sides.
    thrusters = [_cone((side * SHELL_CENTRE_X_M, SHELL_CENTRE_Y_M, THRUSTER_Z_M), 0.1, 0.2, 1.0, nozzle, throat) for side in (-1.0, 1.0)]
    thrusters += [_cone((side * 0.48, 0.05, NOSE_Z_M), 0.05, 0.1, -1.0, nozzle, throat) for side in (-1.0, 1.0)]
    thrusters += [_cone((side * 1.5, SHELL_CENTRE_Y_M + 0.2, z), 0.05, 0.1, 1.0, nozzle, throat) for side in (-1.0, 1.0) for z in (-1.4, 1.4)]

    def part(name: str, meshes: list[Mesh], markings: tuple[Marking, ...] = ()) -> TexturedPart:
        return TexturedPart(Mesh.concatenate(meshes), phase_steps(name, False), markings, name)

    # The number on each shell's back, upright when the bot is seen from above with its nose up the page.
    marks = tuple(Marking.text(name, "9", (side * SHELL_CENTRE_X_M, SHELL_CENTRE_Y_M + 0.5, 0.15), (1.0, 0.0, 0.0),
                               (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), 0.5, NUMBER) for name, side in (("shell_r", 1.0), ("shell_l", -1.0)))
    return [part("shell_r", [pod_r], (marks[0],)), part("shell_l", [pod_l], (marks[1],)), part("truss", frame), part("head", head),
            part("arms", arms), part("thrusters", thrusters)]


def centre(parts: list[TexturedPart]) -> tuple[list[TexturedPart], np.ndarray]:
    """Move the parts so the vertex mean is the origin (the bot is left-right symmetric, so only y and z move a little);
    returns them and the subtracted offset (``centroid_offset``)."""
    verts = np.concatenate([p.mesh.vertices for p in parts])
    lo, hi = verts.min(axis=0), verts.max(axis=0)
    offset = np.array([0.0, 0.5 * (lo[1] + hi[1]), 0.5 * (lo[2] + hi[2])])
    return [TexturedPart(p.mesh.translated(-offset), p.phase, tuple(_shifted(m, offset) for m in p.markings), p.name) for p in parts], offset


def _shifted(marking: Marking, offset: np.ndarray) -> Marking:
    """A marking moved with its part."""
    params = dict(marking.params)
    if "centre" in params:
        params["centre"] = tuple(np.asarray(params["centre"], dtype=float) - offset)
    return Marking(marking.kind, marking.part, marking.colour, params)


def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def hardpoints(parts: list[TexturedPart], body: Mesh) -> dict[str, Any]:
    """The hardpoints document: size, the radius the mover keeps clear of the hull, the lamps and the lens."""
    lo, hi = body.bounds()
    radius = float(np.linalg.norm(body.vertices, axis=1).max())
    lamps = [_r(v) for v in _lamp_centres(parts)]
    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(float(hi[2] - lo[2]), 3),
        "width_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "bound_radius_m": round(radius, 3),
        "nose": [0.0, 0.0, -1.0],
        "lamps": lamps,
    }


def _lamp_centres(parts: list[TexturedPart]) -> list[np.ndarray]:
    """Where the amber lamps sit: the centres of the faces of the lamp material."""
    out: list[np.ndarray] = []
    for p in parts:
        if LAMP not in p.mesh.materials:
            continue
        index = p.mesh.materials.index(LAMP)
        tris = p.mesh.vertices[p.mesh.faces[p.mesh.face_material == index]]
        if len(tris):
            # One lamp per box (12 faces), so the centres of 12-face groups.
            for group in np.array_split(tris, max(len(tris) // 12, 1)):
                out.append(group.reshape(-1, 3).mean(axis=0))
    return out


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the bot into ``ctx.out_dir``. Option: ``atlas_px`` (default 1 024)."""
    atlas_px = int(ctx.option("atlas_px", ATLAS_PX))
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    parts, offset = centre(build_parts())
    body = Mesh.concatenate(p.mesh for p in parts)
    aabb_min, aabb_max = body.bounds()
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)
    files: list[Path] = write_obj(out_dir / OBJ_NAME, body, ASSET_ID, comments)
    textured_paths, mesh_entry = write_textured_mesh(out_dir, ASSET_ID, parts, MAINTENANCE_BOT, atlas_px=atlas_px,
                                                     texel_m=TEXEL_M * ATLAS_PX / atlas_px, seed=ctx.seed, occlusion=True, normal_scale=1)
    files += textured_paths
    hp = hardpoints(parts, body)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=offset,
        files={"obj": OBJ_NAME, "mesh": mesh_entry["file"], "hardpoints": HARDPOINTS_NAME},
        extra={"dimensions_m": {"length": hp["length_m"], "width": hp["width_m"], "height": hp["height_m"]}, "mesh": mesh_entry},
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
