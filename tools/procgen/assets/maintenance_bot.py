"""``maintenance_bot``: the station's maintenance drone (M7-T11, Q11, D78; docs/assets-station.md "Maintenance bot").

Shape only, built from primitives after the maintainer's four-view sheet (gitignored, never traced; rebuilt to its top, side and
front silhouettes in M7-T36): two shells, each a quarter of a long egg (flat inside and underneath, pointed at the nose), side by
side with a gap down the middle, blue with two gold bands and a painted "9"; a grey truss between and under them; a sensor stalk
under the middle with a green lens; two jointed arms hanging outboard of the shells, folding aft to the elbow and forward to a
claw; small thrusters on the truss. A utility drone 4.65 m long, 3.5 m across the arms, no weapons, no cockpit.

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
from ..core.color import capture_albedo
from ..core.geometry import Material, Mesh, assign_material_by_predicate, basis_from_z, box, lathe, rotation_y, tapered_box
from ..core.manifest import build_manifest, write_manifest
from ..core.obj import write_obj
from ..core.textured_mesh import TexturedPart, phase_steps, write_textured_mesh
from ..core.textures import Marking
from ..styles import Style
from ..styles.maintenance_bot import MAINTENANCE_BOT

ASSET_ID = "maintenance_bot"
GENERATOR_VERSION = 2
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"
JSON_DIGITS = 4
# The textured mesh: about 40 m² of surface on a 1 024 px atlas at 1.2 cm a texel.
ATLAS_PX = 1024
TEXEL_M = 0.012

# The glowing parts (linear RGB): the sensor lens, the lamps along the truss and the pods' tails.
LENS = Material("mb_lens", (0.01, 0.05, 0.015), roughness=0.1, emissive=(0.2, 1.0, 0.3), emissive_strength=1.2)
LAMP = Material("mb_lamp", (0.05, 0.035, 0.015), roughness=0.2, emissive=(1.0, 0.66, 0.26), emissive_strength=3.0)
NUMBER = capture_albedo(0xB79F62)  # the painted number, the bands' gold (M7-T36, read off the sheet)

# Authored with z from the shells' pointed tips (the nose) aft and y up from the shells' flat undersides; ``centre`` moves the
# origin. Every size below is measured off the maintainer's four-view sheet (M7-T36) at the bot's 4.65 m length.
#
# The shells: each a quarter of a long egg, flat on its inner side and underneath, so the pair is a low dome split down the
# middle. ``SHELL_PLAN`` is the outer edge's distance from the centreline along z (the tip and the tail meet the inner wall),
# ``SHELL_RISE`` the height of the crest along the inner wall.
SHELL_INNER_X_M = 0.585
SHELL_PLAN = ((0.0, 0.585), (0.17, 0.76), (0.35, 0.85), (0.52, 0.95), (0.69, 1.02), (0.86, 1.09), (1.04, 1.135), (1.21, 1.185),
              (1.38, 1.24), (1.73, 1.305), (2.08, 1.36), (2.42, 1.39), (2.77, 1.41), (3.11, 1.4), (3.46, 1.36), (3.63, 1.32),
              (3.80, 1.265), (3.98, 1.185), (4.15, 1.09), (4.32, 0.97), (4.45, 0.85), (4.53, 0.76), (4.58, 0.585))
SHELL_RISE = ((0.0, 0.0), (0.11, 0.07), (0.32, 0.15), (0.65, 0.235), (1.0, 0.30), (1.4, 0.385), (1.75, 0.45), (1.9, 0.52),
              (2.2, 0.575), (2.5, 0.60), (3.2, 0.62), (3.8, 0.64), (4.1, 0.625), (4.3, 0.47), (4.45, 0.33), (4.58, 0.0))
SHELL_END_M = 4.58
# The section's curve from the outer edge up to the crest: a superellipse a little flatter than a quarter ellipse.
SHELL_EXPONENT = 1.7
BANDS_M = ((1.6, 1.9), (3.04, 3.47))  # the two gold bands round each shell, z from the tip
NUMBER_AT = (0.94, 0.55, 2.5)  # the number's centre on the starboard shell; it reads upright from outboard
ARC_SEGMENTS = 10

# The truss between and under the shells.
SPINE_Z_M = (1.05, 4.58)  # the truss under the shells, from the bow frame to the thruster housing's face
SPINE_HALF_W_M = 0.42
TAIL_BLOCK_Z_M = 3.6
TAIL_Z_M = 4.2
DECK_Z_M = 1.66  # the deck fills the gap between the shells aft of here; ahead of it the bow is narrower
TOP_Y_M = 0.09  # the spine's top, seen from above between the shells
BEAM_Y_M = (-0.43, -0.13)
BEAM_ROOT_X_M = 0.75  # the cross beams out to the arms' shoulders, and the spine's waist
BELLY_Y_M = -0.35  # below this the truss narrows to the stalk's width
KEEL_Y_M = -0.63

# The arms hang outboard of the shells and fold fore and aft; the claws close below the middle of the bot.
ARM_X_M = 1.62
SHOULDER = (-0.31, 1.83)  # (y, z)
ELBOW = (-0.89, 3.73)
WRIST = (-1.8, 2.49)

# The sensor stalk under the middle, its lens box looking forward.
STALK_Z_M = (2.33, 2.59)
LENS_BOX_Y_M = (-1.78, -1.23)


def _strut(p0: Any, p1: Any, width: float, height: float, material: Material) -> Mesh:
    """A square bar from ``p0`` to ``p1`` (a link of an arm, a brace); ``width`` lies along X."""
    a, b = np.asarray(p0, dtype=float), np.asarray(p1, dtype=float)
    d = b - a
    return tapered_box(float(np.linalg.norm(d)), (width, height), (width, height), material).transformed(basis_from_z(d, (1.0, 0.0, 0.0)),
                                                                                                         0.5 * (a + b))


def _joint(at: Any, radius: float, length: float, material: Material) -> Mesh:
    """A short cylinder along X: an arm's joint."""
    cyl = lathe([(-0.5 * length, 0.0), (-0.5 * length, radius), (0.5 * length, radius), (0.5 * length, 0.0)], 16, material, creases=(1, 2))
    return cyl.transformed(rotation_y(0.5 * math.pi), at)


def _cone(at: Any, radius: float, length: float, aim: float, outer: Material, throat: Material) -> Mesh:
    """A little thruster: a short bell opening toward +Z (``aim`` 1) or -Z, its throat glowing."""
    s = 1.0 if aim >= 0 else -1.0
    bell = lathe([(0.0, 0.5 * radius), (0.7 * length, radius), (length, 1.1 * radius), (length, 0.8 * radius), (0.9 * length, 0.0)], 12,
                 [outer, outer, throat, throat], creases=(1, 2))
    rot = np.diag([1.0, 1.0, s]) if s < 0 else np.eye(3)
    return bell.transformed(rot, at)


def _shell_stations() -> np.ndarray:
    """Where the shell's sections sit along z: close at the tip and tail, and on each band's edges so the paint lines are crisp."""
    base = np.concatenate([np.linspace(0.0, 0.6, 7), np.linspace(0.75, 4.1, 17), np.linspace(4.2, SHELL_END_M, 5)])
    return np.unique(np.round(np.concatenate([base, np.ravel(BANDS_M)]), 4))


def _surface(rings: list[np.ndarray], material: Material, chart: int) -> Mesh:
    """One smooth face of the shell skinned over open rings (front to back), its first and last rings allowed to be single points.
    UVs are metres: along the ring and along z."""
    verts, uvs, faces, idx = [], [], [], []
    for ring in rings:
        ring = np.asarray(ring, dtype=float).reshape(-1, 3)
        s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(ring, axis=0), axis=1))])
        idx.append(len(verts) + np.arange(len(ring)))
        verts.extend(ring)
        uvs.extend(np.stack([s, ring[:, 2]], axis=1))
    for a, b in zip(idx[:-1], idx[1:]):
        if len(a) == 1:
            faces.append(np.stack([np.full(len(b) - 1, a[0]), b[1:], b[:-1]], axis=1))
        elif len(b) == 1:
            faces.append(np.stack([np.full(len(a) - 1, b[0]), a[:-1], a[1:]], axis=1))
        else:
            i = np.arange(len(a) - 1)
            faces.append(np.concatenate([np.stack([a[i], b[i + 1], b[i]], axis=1), np.stack([a[i], a[i + 1], b[i + 1]], axis=1)]))
    f = np.concatenate(faces)
    uv = np.asarray(uvs)[f]
    return Mesh(np.asarray(verts), f, np.zeros(len(f), dtype=np.int64), (material,), np.full(len(f), chart, dtype=np.int64), uv)


def _shell(style: Style) -> Mesh:
    """The starboard shell: a quarter egg with a hard crease along its flat inner wall and underside, and its two gold bands."""
    shell, band = style.material("hull"), style.material("stripe")
    plan_z, plan_x = np.array(SHELL_PLAN).T
    rise_z, rise_y = np.array(SHELL_RISE).T
    dome, wall, under = [], [], []
    for k, z in enumerate(_shell_stations()):
        w = float(np.interp(z, plan_z, plan_x)) - SHELL_INNER_X_M
        h = float(np.interp(z, rise_z, rise_y))
        root = (SHELL_INNER_X_M, 0.0, z)
        if k == 0 or z >= SHELL_END_M:  # the tip and the tail: every face closes on one point on the inner wall's foot
            dome.append([root]), wall.append([root]), under.append([root])
            continue
        t = np.linspace(0.0, 0.5 * math.pi, ARC_SEGMENTS + 1)
        c, s = np.cos(t) ** (2.0 / SHELL_EXPONENT), np.sin(t) ** (2.0 / SHELL_EXPONENT)
        # The ring runs counter-clockwise seen from aft: along the underside outboard, up over the crest, down the inner wall.
        dome.append(np.stack([SHELL_INNER_X_M + w * c, h * s, np.full_like(t, z)], axis=1))
        wall.append(np.array([(SHELL_INNER_X_M, h, z), root]))
        under.append(np.array([root, (SHELL_INNER_X_M + w, 0.0, z)]))
    mesh = Mesh.concatenate([_surface(dome, shell, 0), _surface(wall, shell, 1), _surface(under, shell, 2)])
    zc = mesh.face_centroids()[:, 2]
    painted = np.zeros(len(zc), dtype=bool)
    for lo, hi in BANDS_M:
        painted |= (zc > lo) & (zc < hi)
    return assign_material_by_predicate(mesh, band, painted)


def _arm(style: Style, side: float) -> list[Mesh]:
    """One manipulator arm on the ``side`` (+1 starboard, -1 port), outboard of the shell: a post down from the shell's underside to
    the shoulder, the upper arm aft to the elbow, the forearm forward and down to the wrist, and a claw of two prongs."""
    truss, dark = style.material("hull_panel"), style.material("hull_dark")
    x = ARM_X_M * side
    shoulder, elbow, wrist = (np.array([x, y, z]) for y, z in (SHOULDER, ELBOW, WRIST))
    out = [box((0.12, 0.33, 0.2), truss, (x, -0.12, SHOULDER[1])),
           _joint(shoulder, 0.21, 0.16, dark), _strut(shoulder, elbow, 0.14, 0.34, truss), _joint(elbow, 0.24, 0.16, truss),
           _strut(elbow, wrist, 0.14, 0.28, truss), _joint(wrist, 0.11, 0.26, dark)]
    # The claw: two hooked prongs, one reaching forward and one down, their tips bent toward each other.
    for knuckle, tip in (((-0.04, -0.3), (-0.23, -0.43)), ((-0.4, -0.09), (-0.44, -0.3))):
        k = wrist + np.array([0.0, knuckle[0], knuckle[1]])
        out.append(_strut(wrist, k, 0.06, 0.07, dark))
        out.append(_strut(k, wrist + np.array([0.0, tip[0], tip[1]]), 0.06, 0.07, dark))
    return out


def build_parts(style: Style = MAINTENANCE_BOT) -> list[TexturedPart]:
    """Every part of the bot in the authored frame, before the centring."""
    truss, plate, dark = style.material("hull_panel"), style.material("hazard"), style.material("hull_dark")
    nozzle, throat = style.material("nozzle"), style.material("nozzle_throat")
    pod_r = _shell(style)
    pod_l = pod_r.mirrored("x")

    # The truss: the spine between the shells (narrowing below their undersides to the stalk), the keel, the cross beams out to the
    # shoulders, the T-shaped mast on the spine's top aft, the tail block with the main thrusters, and teeth along the shells' walls.
    down = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]])  # a tapered box's start up, its end down
    z0, z1 = SPINE_Z_M
    beam_h, beam_y = BEAM_Y_M[1] - BEAM_Y_M[0], 0.5 * sum(BEAM_Y_M)
    frame: list[Mesh] = [
        box((2.0 * SHELL_INNER_X_M, TOP_Y_M, TAIL_Z_M - DECK_Z_M), truss, (0.0, 0.5 * TOP_Y_M, 0.5 * (DECK_Z_M + TAIL_Z_M))),  # the deck
        box((0.68, TOP_Y_M, DECK_Z_M - 0.88), truss, (0.0, 0.5 * TOP_Y_M, 0.5 * (0.88 + DECK_Z_M))),  # its narrower bow
        tapered_box(0.43, (1.24, 0.25), (0.84, 0.25), plate).transformed(down, (0.0, -0.215, z0 + 0.125)),  # the bow frame
        # The keel beam, and under it a narrower box and the keel, as narrow as the sensor stalk so they hide behind it from ahead.
        box((2.0 * SPINE_HALF_W_M, BEAM_Y_M[1] - BELLY_Y_M, TAIL_BLOCK_Z_M - z0), truss,
            (0.0, 0.5 * (BEAM_Y_M[1] + BELLY_Y_M), 0.5 * (z0 + TAIL_BLOCK_Z_M))),
        box((0.4, BELLY_Y_M - BEAM_Y_M[0], 3.44 - z0), dark, (0.0, 0.5 * (BELLY_Y_M + BEAM_Y_M[0]), 0.5 * (z0 + 3.44))),
        box((0.4, BEAM_Y_M[0] - KEEL_Y_M, 1.25), dark, (0.0, 0.5 * (BEAM_Y_M[0] + KEEL_Y_M), 2.225)),
        # The tail block: under the deck, its underside rising aft, and a narrow wedge under it; the thruster housing behind it.
        tapered_box(TAIL_Z_M - TAIL_BLOCK_Z_M, (2.0 * SPINE_HALF_W_M, 0.44), (2.0 * SPINE_HALF_W_M, 0.22), truss,
                    (0.0, -0.13, 0.5 * (TAIL_BLOCK_Z_M + TAIL_Z_M)), offset_b=(0.0, 0.11)),
        tapered_box(0.78, (0.4, 0.5), (0.4, 0.1), dark, (0.0, -0.38, 3.83), offset_b=(0.0, 0.23)),
        box((0.6, 0.28, z1 - TAIL_Z_M), plate, (0.0, 0.06, 0.5 * (TAIL_Z_M + z1))),
    ]
    for side in (-1.0, 1.0):
        # The beam hangs from the shell's underside on a bracket at its root and the shoulder post at its end, clear of the bow frame.
        beam_end = ARM_X_M - 0.2
        frame.append(box((beam_end - BEAM_ROOT_X_M, beam_h, 0.55), plate, (side * 0.5 * (beam_end + BEAM_ROOT_X_M), beam_y, 1.375)))
        frame.append(box((0.06, -BEAM_Y_M[1], 0.15), dark, (side * (BEAM_ROOT_X_M + 0.05), 0.5 * BEAM_Y_M[1], 1.225)))
        frame.append(box((0.24, beam_h, 0.24), truss, (side * (ARM_X_M - 0.14), beam_y, 1.73)))
        for z in (0.72, 0.9, 1.08, 1.26):
            frame.append(box((0.1, 0.1, 0.12), dark, (side * 0.53, 0.06, z)))
    frame.append(box((0.72, 0.2, 0.6), plate, (0.0, 0.53, 3.55)))  # the T's bar
    frame.append(box((0.2, 0.36, 0.5), truss, (0.0, 0.26, 3.55)))  # its stem
    for z in (1.2, 2.0, 2.8):  # the lamps along the spine's top
        frame.append(box((0.07, 0.05, 0.07), LAMP, (0.2, TOP_Y_M + 0.025, z)))

    # The sensor stalk under the middle and the lens box at its foot, its green lens looking forward.
    head = [box((0.4, BEAM_Y_M[0] - LENS_BOX_Y_M[1], STALK_Z_M[1] - STALK_Z_M[0]), dark,
                (0.0, 0.5 * (BEAM_Y_M[0] + LENS_BOX_Y_M[1]), 0.5 * sum(STALK_Z_M))),
            box((0.8, LENS_BOX_Y_M[1] - LENS_BOX_Y_M[0], 0.28), plate, (0.0, 0.5 * sum(LENS_BOX_Y_M), 2.47))]
    lens = lathe([(0.0, 0.0), (0.0, 0.14), (-0.06, 0.11), (-0.08, 0.0)], 16, LENS)
    head.append(lens.transformed(np.eye(3), (-0.1, -1.55, 2.33)))

    arms = _arm(style, -1.0) + _arm(style, 1.0)
    # The thrusters: two main bells on the tail block, RCS cones at the spine's nose, on the beams' ends and on the tail block.
    thrusters = [_cone((side * 0.15, 0.11, 4.58), 0.08, 0.068, 1.0, nozzle, throat) for side in (-1.0, 1.0)]
    thrusters += [_cone((side * 0.3, -0.05, SPINE_Z_M[0]), 0.05, 0.1, -1.0, nozzle, throat) for side in (-1.0, 1.0)]
    thrusters += [_cone((side * 1.4, -0.3, 1.1), 0.05, 0.1, -1.0, nozzle, throat) for side in (-1.0, 1.0)]
    thrusters += [_cone((side * 0.36, -0.03, 4.58), 0.05, 0.068, 1.0, nozzle, throat) for side in (-1.0, 1.0)]

    def part(name: str, meshes: list[Mesh], markings: tuple[Marking, ...] = ()) -> TexturedPart:
        return TexturedPart(Mesh.concatenate(meshes), phase_steps(name, False), markings, name)

    # The number on each shell's back, upright read from outboard: "9" from above on one, "6" on the other, as on the sheet.
    nx, ny, nz = NUMBER_AT
    marks = tuple(Marking.text(name, "9", (side * nx, ny, nz), (0.0, 0.0, side), (side, 0.0, 0.0), (0.0, 1.0, 0.0), 0.48, NUMBER)
                  for name, side in (("shell_r", 1.0), ("shell_l", -1.0)))
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
