"""``brakiri_bokmai``: the Brakiri Bokmai transport, 80 m, with removable cargo pods (M5-T22, D59, Q17, Q22;
docs/assets-civilian.md and docs/design-references.md, "Brakiri Bokmai transport").

Composition only: the pieces of ``parts/brakiri.py`` in the ``brakiri`` style, through the shared civilian pipeline
(``core/civilian.py``), every output derived from the placed pieces so they agree by construction.

Layout (authored frame, metres, before re-centring; -Z is forward, the prow at z = 0, x and y centred on the reference
model's box): the tall bow blade (its flank insets carry the two turrets, Q22), the dorsal spine to the fork, the fork
struts and posts, the lower arms from the keel, and at the stern the necks, nacelles with their cups and engine domes,
and the tall fins. The spindle runs from the bow to the joints; up to three pods ride on it.

The hull is written without its pods. The pod is one model (``<id>_pod*``, LOD0 to LOD3 at the hull's spacings) whose
origin is its mount; ``hardpoints.json`` names the three mounts in ``cargo_pods[]`` and the manifest's ``pod`` entry
has its files, counts, collision and mass. A destroyed Bokmai sheds each mounted pod whole, apart from its chunks.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np

from ..core import civilian as cv
from ..core import lighting
from ..core.chunks import write_chunks
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh
from ..core.manifest import build_manifest, lod_entry, write_manifest
from ..core.obj import write_obj
from ..core.ply import SplatData
from ..core.sampling import DEFAULT_OVERLAP, DEFAULT_THICKNESS
from ..parts import mass_centroid, total_mass
from ..parts import brakiri as bp
from ..parts.propulsion import pilot_tags
from ..styles.brakiri import BRAKIRI, BRAKIRI_POD

ASSET_ID = "brakiri_bokmai"
GENERATOR_VERSION = 1
PLY_NAME = f"{ASSET_ID}.ply"
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"

# docs/assets-civilian.md: the hull 40 500 (32 000 to 49 000), each pod 11 500 (9 000 to 14 000), from a 0.30 m start.
DEFAULT_SPACING_M = 0.30
SPLAT_BUDGET = (32_000, 49_000)
POD_BUDGET = (9_000, 14_000)
LODS = {
    1: (f"{ASSET_ID}_lod1.ply", 2.0, "lod1", (0.20, 0.30)),  # level: file, spacing factor, stream, share of LOD0
    2: (f"{ASSET_ID}_lod2.ply", 4.0, "lod2", (0.04, 0.09)),
    3: (f"{ASSET_ID}_lod3.ply", 8.0, "lod3", (0.01, 0.025)),
}
CHUNK_LOD = 1
CHUNK_ORDER = ("bow", "arm_l", "arm_r", "engine_l", "engine_r")

POD_STEM = f"{ASSET_ID}_pod"
POD_MOUNTS = (("pod_fwd", 24.63), ("pod_mid", 39.07), ("pod_aft", 53.57))  # name, mount z on the spindle's axis

TURRET_STEM = f"{ASSET_ID}_turret"
TURRET_SPACING_M = 0.11
TURRET_SPLATS = (1_500, 3_000)
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


def pod_level_name(level: int) -> str:
    return f"{POD_STEM}.ply" if level == 0 else f"{POD_STEM}_lod{level}.ply"


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
    ``write_chunks`` entries (from LOD1). Mass, centre of mass and inertia are the hull's without pods; each pod's mass is
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

    Options: ``spacing`` (m, default 0.30; the CLI's ``--spacing``), ``overlap`` (sigma / spacing, default 1.0),
    ``thickness`` (normal sigma / spacing, default 0.08), ``turret_spacing`` (m, default 0.11).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    overlap = float(ctx.option("overlap", DEFAULT_OVERLAP))
    thickness = float(ctx.option("thickness", DEFAULT_THICKNESS))
    turret_spacing = float(ctx.option("turret_spacing", TURRET_SPACING_M))
    if min(spacing, overlap, thickness, turret_spacing) <= 0.0:
        raise ValueError("spacing, overlap, thickness and turret_spacing must be positive")
    style = BRAKIRI
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}", "frame: 3dgs (Rz180 of godot)")
    light = {level: lighting.lod_file_name(ASSET_ID, level) for level in (0, *LODS)}
    pieces = hull_pieces()

    # LOD0: the hull without its pods, chunk group by chunk group (manifest ``counts`` order).
    lod0 = cv.sample_pieces(pieces, ctx, spacing, buried_margin=BURIED_MARGIN_M)
    offset = cv.centroid(lod0)
    groups = cv.chunk_sources(lod0, CHUNK_ORDER, style, offset, overlap, thickness)
    authored = SplatData.concatenate([g.splats for g in groups])
    xyz32 = authored.xyz.astype(np.float32)
    aabb_min, aabb_max = xyz32.min(axis=0), xyz32.max(axis=0)
    files: list[Path] = cv.write_level(out_dir, PLY_NAME, light[0], authored, comments)
    files += write_obj(out_dir / OBJ_NAME, Mesh.concatenate(g.mesh for g in groups), ASSET_ID, comments[:1])

    # LOD1 to LOD3, each centred on its own centroid; LOD1's groups are the break-up chunks.
    counts: dict[int, int] = {}
    chunk_entries: list[dict[str, Any]] = []
    for level, (name, factor, stream, _share) in LODS.items():
        sampled = cv.sample_pieces(pieces, ctx, factor * spacing, (stream,), BURIED_MARGIN_M)
        lod_groups = cv.chunk_sources(sampled, CHUNK_ORDER, style, cv.centroid(sampled), overlap, thickness)
        lod = SplatData.concatenate([g.splats for g in lod_groups])
        counts[level] = len(lod)
        level_comments = comments + (f"lod {level}",)
        files += cv.write_level(out_dir, name, light[level], lod, level_comments)
        if level == CHUNK_LOD:
            chunk_files, chunk_entries = write_chunks(out_dir, ASSET_ID, lod_groups, level_comments)
            files += chunk_files

    # The pod: one model, its origin the mount, at the hull's spacings so it switches with the hull.
    pod = bp.cargo_pod(style)
    pod_levels: list[dict[str, Any]] = []
    for level in (0, *LODS):
        factor = 1.0 if level == 0 else LODS[level][1]
        stream = "pod" if level == 0 else f"pod_lod{level}"
        splats = cv.sample_model(pod.part, pod.solids, BRAKIRI_POD, ctx, stream, factor * spacing, overlap, thickness, BURIED_MARGIN_M)
        stem = pod_level_name(level)[:-4]
        level_files, mean = cv.write_model(out_dir, stem, pod.part, splats, comments + ("pod", f"lod {level}"), centred=False,
                                           with_obj=level == 0)  # fmt: skip
        files += level_files
        # GDGS centres each import on its own mean: ``offset`` is where that mean sits in the pod's frame, per level.
        pod_levels.append({"level": level, "file": pod_level_name(level), "lighting": f"{stem}{lighting.SUFFIX}",
                           "splats": len(splats), "spacing_m": factor * spacing, "offset": cv.r(mean)})  # fmt: skip
    pod_entry = {
        "obj": f"{POD_STEM}.obj",
        "lods": pod_levels,
        "mass_kg": pod.part.mass_kg,
        "collision": [c.to_json(digits=cv.JSON_DIGITS) for c in pod.part.collision],
        "size_m": cv.r(bp.POD_SIZE),
    }

    turret_part = bp.brakiri_turret(TURRET, style)
    turret = cv.sample_model(turret_part, TURRET.solids(), style, ctx, "turret", turret_spacing, overlap, thickness, BURIED_MARGIN_M)
    turret_files, turret_centroid = cv.write_model(out_dir, TURRET_STEM, turret_part, turret, comments + ("turret",))
    files += turret_files
    turret_entry = cv.turret_entry(TURRET_STEM, turret_part, turret, turret_spacing, TURRET.barrel_m, turret_centroid)

    hp = hardpoints(pieces, chunk_entries, offset)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    total = len(authored)
    warnings: list[str] = []
    if abs(spacing - DEFAULT_SPACING_M) < 1e-12:
        if not SPLAT_BUDGET[0] <= total <= SPLAT_BUDGET[1]:
            warnings.append(f"{total} splats is outside the budget {SPLAT_BUDGET} at the default spacing")
        if not POD_BUDGET[0] <= pod_levels[0]["splats"] <= POD_BUDGET[1]:
            warnings.append(f"the pod has {pod_levels[0]['splats']} splats, outside {POD_BUDGET}")
        for level, (_name, _factor, _stream, share) in LODS.items():
            if not share[0] <= counts[level] / total <= share[1]:
                warnings.append(f"LOD{level} has {counts[level] / total:.1%} of LOD0's splats, outside {share}")
    if abs(turret_spacing - TURRET_SPACING_M) < 1e-12 and not TURRET_SPLATS[0] <= len(turret) <= TURRET_SPLATS[1]:
        warnings.append(f"the turret has {len(turret)} splats, outside {TURRET_SPLATS}")
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        lods=[lod_entry(0, PLY_NAME, total, spacing, light[0])]
        + [lod_entry(level, LODS[level][0], counts[level], LODS[level][1] * spacing, light[level]) for level in LODS],
        aabb_min=aabb_min,
        aabb_max=aabb_max,
        centroid_offset=offset,
        files={"fallback_mesh": OBJ_NAME, "hardpoints": HARDPOINTS_NAME},
        extra={
            "counts": {g.name: len(g.splats) for g in groups},
            "chunks": [c["name"] for c in chunk_entries],
            "chunk_lod": CHUNK_LOD,
            "sampling": {"spacing_m": spacing, "overlap": overlap, "thickness": thickness, "turret_spacing_m": turret_spacing},
            "dimensions_m": {"length": hp["length_m"], "span": hp["span_m"], "height": hp["height_m"]},
            "turret": turret_entry,
            "pod": pod_entry,
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), tuple(warnings))
