"""``brakiri_bokmai``: the Brakiri Bokmai transport, 80 m, with removable cargo pods (M5-T22, D59, Q17, Q22;
docs/assets-civilian.md and docs/design-references.md, "Brakiri Bokmai transport").

Composition only: the pieces of ``parts/brakiri.py`` in the ``brakiri`` style, through the shared civilian pipeline
(``core/civilian.py``), every output derived from the placed pieces so they agree by construction.

Layout (authored frame, metres, before re-centring; -Z is forward, the prow at z = 0, x and y centred on the reference
model's box): the tall bow blade (its flank insets carry the two turrets, Q22), the dorsal spine to the fork, the fork
struts and posts, the lower arms from the keel, and at the stern the necks, nacelles with their cups and engine domes,
and the tall fins. The spindle runs from the bow to the joints; up to three pods ride on it.

The hull is written without its pods, as one textured mesh (Godot's importer builds its levels of detail) cut into its
chunks. The pod is one textured model (``<id>_pod.glb`` and ``<id>_pod.obj``) whose origin is its mount;
``hardpoints.json`` names the three mounts in ``cargo_pods[]`` and the manifest's ``pod`` entry has its mesh, collision
and mass. A destroyed Bokmai sheds each mounted pod whole, apart from its chunks.
"""

from __future__ import annotations

import json
from dataclasses import replace
from pathlib import Path
from typing import Any

import numpy as np

from ..core import civilian as cv
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh
from ..core.manifest import build_manifest, write_manifest
from ..parts import mass_centroid, total_mass
from ..parts import brakiri as bp
from ..parts.propulsion import pilot_tags
from ..styles.brakiri import BRAKIRI, BRAKIRI_POD

ASSET_ID = "brakiri_bokmai"
GENERATOR_VERSION = 2  # 2: textured meshes (M5-T27)
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"

DEFAULT_SPACING_M = 0.30  # the surface samples' spacing: the body origin and the chunks' offsets
CHUNK_ORDER = ("bow", "arm_l", "arm_r", "engine_l", "engine_r")

POD_STEM = f"{ASSET_ID}_pod"
POD_MOUNTS = (("pod_fwd", 24.63), ("pod_mid", 39.07), ("pod_aft", 53.57))  # name, mount z on the spindle's axis

TURRET_STEM = f"{ASSET_ID}_turret"
TURRET_PANEL_M = (0.65, 0.06)  # the turret's own panel size and seam
TURRET_ARC_DEG = 200.0  # a hemisphere plus 10 degrees below the mount's base (outboard on the bow's flank, Q22)
TURRET = bp.BrakiriTurretSpec()

BURIED_MARGIN_M = 0.03
CHASE_ANCHOR_SHARE = (0.3, 1.2)
NAV_CLEARANCE_M = 0.15
NAV_SIDE_Z = 40.0  # the arms' outer faces at mid-length
NAV_LAMP_HEIGHT_M = 6.2
NAV_LAMP_Z = 40.0
NAV_LAMP_RANGE_SHARE = 0.3
NAV_CABIN_RANGE_SHARE = 0.05


# --- hardpoints --------------------------------------------------------------------------------------------------------
def rcs_ports(by_name: dict[str, Any]) -> list[tuple[str, np.ndarray, np.ndarray]]:
    """Cosmetic RCS (authored frame): the right fins' tips, the bow's right flank low down and the right nacelle's
    outboard flank (``r_`` names, mirrored by the caller), and the prow on the centre line."""
    top, bottom = by_name["fin_top_r"].anchor("tip"), by_name["fin_bot_r"].anchor("tip")
    prow = by_name["bow"].anchor("prow")
    flank_y, flank_z = 4.0, 7.0
    flank = np.array([bp.bow_half_width(flank_y, flank_z), flank_y, flank_z])
    nacelle = np.array([15.8, bp.CUP[1], 74.0])
    return [
        ("r_fin_top", top.position, top.direction),
        ("r_fin_bot", bottom.position, bottom.direction),
        ("r_bow", flank, np.array([1.0, 0.0, 0.0])),
        ("r_nacelle", nacelle, np.array([1.0, 0.0, 0.0])),
        ("prow", prow.position, prow.direction),
    ]


def chunk_joints() -> dict[str, np.ndarray]:
    """Where each chunk breaks away (authored frame): an arm at its root on the keel, an engine where its strut leaves
    the spine, the bow where the spine leaves the crown (on the structure, not in a pod's space)."""
    arm = np.array(bp.ARM_PATH[2])
    engine = np.array([3.0, 11.0, 48.0])
    flip = np.array([-1.0, 1.0, 1.0])
    return {"bow": np.array([0.0, 11.0, 15.0]), "arm_r": arm, "arm_l": arm * flip, "engine_r": engine, "engine_l": engine * flip}


def nav_lights(by_name: dict[str, Any], offset: np.ndarray, length: float) -> dict[str, Any]:
    """Running lights: red and green on the arms' outer faces at mid-length, white on the spine's crown with a lamp over
    the pods, the cabin glow in the bow."""
    path = np.array(bp.ARM_PATH)
    k = int(np.argmin(np.abs(path[:, 2] - NAV_SIDE_Z)))
    arm = path[k] + np.array([0.5 * bp.ARM_WIDTH + NAV_CLEARANCE_M, 0.0, 0.0])
    top = np.array(by_name["spine"].anchor("top").position) + np.array([0.0, NAV_CLEARANCE_M, 0.0])
    spine_top = float(np.interp(NAV_LAMP_Z, [row[0] for row in bp.SPINE_ROWS], [row[2] for row in bp.SPINE_ROWS]))
    lamp = np.array([0.0, spine_top + NAV_LAMP_HEIGHT_M, NAV_LAMP_Z])
    return {
        "port": cv.r(arm * np.array([-1.0, 1.0, 1.0]) - offset),
        "starboard": cv.r(arm - offset),
        "top": cv.r(top - offset),
        "top_lamp": cv.r(lamp - offset),
        "top_lamp_range_m": round(NAV_LAMP_RANGE_SHARE * length, 2),
        "cabin": cv.r(np.array(bp.EYE) - offset),
        "cabin_range_m": round(NAV_CABIN_RANGE_SHARE * length, 2),
    }


def hardpoints(pieces: list[cv.Piece], chunks: list[dict[str, Any]], offset: np.ndarray) -> dict[str, Any]:
    """The hardpoints document in the body frame (authored positions minus ``offset``); ``chunks`` are the
    ``write_chunks`` entries. Mass, centre of mass and inertia are the hull's without pods; each pod's mass is
    in the manifest's ``pod`` entry."""
    parts = [p.part for p in cv.with_twins(pieces)]
    by_name = {p.name: p for p in parts}
    lo, hi = Mesh.concatenate(p.mesh for p in parts).bounds()
    length = float(hi[2] - lo[2])
    axis_y = bp.CUP[1]
    com = np.array([0.0, axis_y, float(mass_centroid(parts)[2])])  # on the thrust line (the nacelles' axis)

    pods = []
    for name, side in (("l", "left"), ("r", "right")):
        nacelle = by_name[f"nacelle_{name}"]
        main, retro = nacelle.anchor("main"), nacelle.anchor("retro")
        pods.append({
            "name": name,
            "side": side,
            "center": cv.r(nacelle.anchor("centre").position - offset),
            "main": {"position": cv.r(main.position - offset), "exhaust": cv.r(main.direction), "radius": 1.0},
            "retro": {"position": cv.r(retro.position - offset), "exhaust": cv.r(retro.direction), "radius": 0.6},
        })  # fmt: skip

    rcs = []
    flip = np.array([-1.0, 1.0, 1.0])
    for name, position, exhaust in rcs_ports(by_name):
        twins = [(name, np.asarray(position), np.asarray(exhaust))]
        if name.startswith("r_"):
            twins.append(("l_" + name[2:], np.asarray(position) * flip, np.asarray(exhaust) * flip))
        for n, p, e in twins:
            pod = "l" if p[0] < -1e-6 else "r"
            rcs.append({"name": n, "pod": pod, "position": cv.r(p - offset), "exhaust": cv.r(e), "tags": pilot_tags(p, e, com)})

    turrets = []
    for name in ("inset_l", "inset_r"):
        seat = by_name[name].anchor("turret")
        turrets.append({"name": "flank_" + name[-1], "position": cv.r(seat.position - offset), "up": cv.r(seat.direction),
                        "arc_deg": TURRET_ARC_DEG, "barrel_m": TURRET.barrel_m})  # fmt: skip

    cargo = [{"name": name, "position": cv.r(np.array([0.0, bp.SPINDLE[0], z]) - offset), "up": [0.0, 1.0, 0.0],
              "forward": [0.0, 0.0, -1.0]} for name, z in POD_MOUNTS]  # fmt: skip
    joints = chunk_joints()
    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(length, 3),
        "span_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "mass_kg": round(total_mass(parts), 1),
        "inertia_estimate_kg_m2": cv.r(cv.inertia_estimate(parts, com)),
        "center_of_mass": cv.r(com - offset),
        "cockpit_camera": {"position": cv.r(np.array(bp.EYE) - offset), "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": cv.r((0.0, CHASE_ANCHOR_SHARE[0] * length, CHASE_ANCHOR_SHARE[1] * length))},
        "muzzles": [],
        "pods": pods,
        "rcs": rcs,
        "collision": cv.collision_json(parts, offset),
        "nav_lights": nav_lights(by_name, offset, length),
        "turrets": turrets,
        "cargo_pods": cargo,
        "chunks": [{**c, "joint": cv.r(joints[c["name"]] - offset)} for c in chunks],
    }


# --- build -------------------------------------------------------------------------------------------------------------
def hull_pieces() -> list[cv.Piece]:
    return bp.assemble(BRAKIRI)


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the hull, the pod model and the turret into ``ctx.out_dir``.

    Options: ``spacing`` (m, default 0.30; the surface samples' spacing), ``atlas_px`` (the hull's atlas, default 2 048),
    ``model_atlas_px`` (the pod's and the turret's, default 1 024), ``occlusion`` (default off).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")
    style = BRAKIRI
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)
    pieces = hull_pieces()

    # The hull without its pods; each chunk group a cut of its textured mesh.
    sampled = cv.sample_pieces(pieces, ctx, spacing, buried_margin=BURIED_MARGIN_M)
    offset = cv.centroid(sampled)
    hull = cv.write_hull(out_dir, ASSET_ID, cv.hull_parts(sampled, offset), CHUNK_ORDER, style, ctx, comments)
    files: list[Path] = list(hull.files)

    # The pod: one model, its origin the mount.
    pod = bp.cargo_pod(style)
    pod_files, pod_mesh = cv.write_model(out_dir, POD_STEM, [("pod", pod.part.mesh)], BRAKIRI_POD, ctx, comments + ("pod",))
    files += pod_files
    pod_entry = {
        "obj": f"{POD_STEM}.obj",
        "mesh": pod_mesh,
        "mass_kg": pod.part.mass_kg,
        "collision": [c.to_json(digits=cv.JSON_DIGITS) for c in pod.part.collision],
        "size_m": cv.r(bp.POD_SIZE),
    }

    turret_part = bp.brakiri_turret(TURRET, style)
    fine = replace(style, panel_size_m=TURRET_PANEL_M[0], panel_line_width_m=TURRET_PANEL_M[1])
    turret_files, section = cv.write_model(out_dir, TURRET_STEM, [("turret", turret_part.mesh)], fine, ctx, comments + ("turret",))
    files += turret_files
    turret_entry = cv.turret_entry(TURRET_STEM, turret_part, TURRET.barrel_m, section)

    hp = hardpoints(pieces, hull.chunks, offset)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=hull.aabb_min,
        aabb_max=hull.aabb_max,
        centroid_offset=offset,
        files={"obj": OBJ_NAME, "mesh": hull.mesh_section["file"], "hardpoints": HARDPOINTS_NAME},
        extra={
            "mesh": hull.mesh_section,
            "chunks": [c["name"] for c in hull.chunks],
            "surface_spacing_m": spacing,
            "dimensions_m": {"length": hp["length_m"], "span": hp["span_m"], "height": hp["height_m"]},
            "turret": turret_entry,
            "pod": pod_entry,
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
