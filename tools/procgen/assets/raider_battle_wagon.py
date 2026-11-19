"""``raider_battle_wagon``: the raiders' Battle Wagon, 275 m, their heavy carrier (M8-T09, D83; docs/assets-capital.md and
docs/design-references.md, "Raider Battle Wagon").

Composition only: the pieces of ``parts/raider_wagon.py`` in a ``raider_capital`` surface, through the shared hull pipeline
(``core/civilian.py``), with compound collision from ``core/collision.py`` (M7's D73) and the raiders' plasma turret
(``parts/turret.py``).

Layout (authored frame, metres, before re-centring; -Z is forward, the antenna spikes' tips at z = 0, x and y on the ship's
axis): the eye frame and the bow cone, the eight-sided core, a launch tube above and below it, a deck arm on each side before
and behind the ring, the ring with its lattice, and the engine block's eight nozzles.

``hardpoints.json`` adds to the ships' contract: ``tubes[]`` (each launch tube: its mouths, the way through and its two
lanes), ``cradles[]`` (the twenty berths a Delta-V waits on in the tubes, as the strike carrier's cradles with two more keys:
it leaves ahead to ``release_to`` and comes home from ``approach_from`` behind the stern mouth), ``turrets[]`` (the plasma
turrets on the arms), ``missile_racks[]`` (in the ring's bow face) and ``jump_point``. The manifest's ``collision`` section
holds the convex shapes per break-up chunk and their coverage.

Options: ``spacing`` (m, the surface samples'), ``atlas_scale`` (shrinks every chunk's atlas, for the tests).
"""

from __future__ import annotations

import dataclasses
import json
from pathlib import Path
from typing import Any

import numpy as np

from ..core import civilian as cv
from ..core import collision as col
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh
from ..core.manifest import build_manifest, write_manifest
from ..parts import layouts, mass_centroid, total_mass
from ..parts import raider_wagon as rw
from ..parts.turret import TurretSpec, write_turret
from ..styles.raider_capital import WAGON_SURFACE as SURFACE

ASSET_ID = "raider_battle_wagon"
GENERATOR_VERSION = 1
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"
SPEC = rw.WagonSpec()

DEFAULT_SPACING_M = 1.0  # the surface samples' spacing: the body origin, the chunks' offsets, the collision's coverage
# An atlas per chunk (``civilian.write_hull_atlases``): one 4 096 px atlas for the whole hull takes about 10 GB to bake and gives
# 20 cm a texel; these bake one after another in about 2.6 GB and give the small chunks a finer texel.
ATLAS_PX = {"bow": 1024, "core": 2048, "ring": 2048, "tube_upper": 2048, "tube_lower": 2048, "engines": 1024}
CHUNK_ORDER = ("bow", "core", "ring", "tube_upper", "tube_lower", "engines")

# Collision (docs/assets-capital.md, "Collision"): what one body may carry, and how close the shapes must sit to the hull.
BUDGET = col.Budget(max_shapes=64, max_hull_points=32)
COVER_TOLERANCE_M = 2.0  # every point of the hull is this near a shape (the ring's fittings stand a little proud)
COVER_REACH_M = 5.0  # no shape stands further than this from the hull (the tubes and the ring's openings stay open)

# The plasma turrets: the shared turret at two and a half times its size, on the arms' decks above and below.
TURRET = TurretSpec().scaled(2.5)
TURRET_ARC_DEG = 200.0  # a hemisphere plus 10 degrees below the mount's base
RACK_CELLS = 6

# The launch tubes: two lanes abreast in each, a Delta-V (17 m across) to a lane, five berths deep from the bow mouth.
LANE_X_M = 9.7
BERTH_ROWS = 5
BERTH_FIRST_M = 14.0  # the first berth, behind the bow mouth
BERTH_PITCH_M = 12.0
BERTH_BELLY_M = 1.0  # a berthed fighter floats in the middle of the tube: its belly this far under the tube's axis
TUBE_EXIT_M = 20.0  # a launched fighter is let go this far ahead of the bow mouth
TUBE_ENTRY_M = 40.0  # a returning one lines up this far behind the stern mouth

# The ship's own jump point: its mouth clears the ring (80 m from the axis), and opens this far ahead of the bow.
JUMP_MOUTH_RADIUS_M = 130.0
JUMP_AHEAD_M = 450.0

CHASE_ANCHOR_SHARE = (0.3, 1.2)
NAV_CLEARANCE_M = 0.3
NAV_LAMP_RANGE_SHARE = 0.3
NAV_CABIN_RANGE_SHARE = 0.08


def built_pieces() -> list[rw.Built]:
    """Every piece with its collision shapes, dressed in the surface's plating (centre pieces and the starboard of each pair)."""
    built = rw.assemble(SPEC, SURFACE.style)
    layouts.dress((b.piece.part for b in built), layouts.raider_wagon(SPEC.u, SURFACE))
    return built


def hull_pieces() -> list[cv.Piece]:
    return [b.piece for b in built_pieces()]


def collision_shapes(built: list[rw.Built]) -> dict[str, list[col.Shape]]:
    """The convex shapes per break-up chunk, in the authored frame: each piece's own, and a starboard piece's mirrored to port."""
    out: dict[str, list[col.Shape]] = {group: [] for group in CHUNK_ORDER}
    for b in built:
        out[b.piece.group] += list(b.shapes)
        if b.piece.side == cv.RIGHT:
            out[cv.left_name(b.piece.group)] += [s.mirrored("x").renamed(cv.left_name(s.name)) for s in b.shapes]
    return out


def compound(built: list[rw.Built]) -> dict[str, list[col.Shape]]:
    """Each chunk's shapes merged down to the budget (authored frame)."""
    return {name: col.merge_to_budget(shapes, BUDGET) for name, shapes in collision_shapes(built).items()}


def collision_section(pieces: dict[str, list[col.Shape]], offset: np.ndarray, cover: col.SkinCoverage) -> dict[str, Any]:
    """The manifest's ``collision`` in the body frame (authored positions minus ``offset``), with the skin's coverage."""
    out = col.section({name: [s.translated(-offset) for s in shapes] for name, shapes in pieces.items()}, BUDGET)
    out["coverage"] = cover.to_json()
    return out


# --- hardpoints --------------------------------------------------------------------------------------------------------
TUBES = (("upper", 1.0), ("lower", -1.0))
LANES = (("r", LANE_X_M), ("l", -LANE_X_M))


def berth_name(tube: str, side: str, row: int) -> str:
    return f"{tube}_{side}_{row + 1}"


def tube_entries(offset: np.ndarray) -> list[dict[str, Any]]:
    """Each launch tube (body frame): the middle of its bow and stern mouths, the clear way through (half width and half
    height at the tube's axis level), and its lanes: where a launched fighter is let go (``exit``), where one coming home
    lines up (``approach_from``), and its berths' names from the bow mouth back."""
    u = SPEC.u
    z0, z1 = rw.TUBE_Z[0] * u, rw.TUBE_Z[1] * u
    half, cut = np.array(rw.TUBE_INNER[0]) * u, np.array(rw.TUBE_INNER[1]) * u
    out = []
    for name, sign in TUBES:
        y = sign * rw.TUBE_Y * u
        lanes = []
        for side, x in LANES:
            lanes.append({
                "name": f"{name}_{side}",
                "exit": cv.r(np.array([x, y, z0 - TUBE_EXIT_M]) - offset),
                "approach_from": cv.r(np.array([x, y, z1 + TUBE_ENTRY_M]) - offset),
                "berths": [berth_name(name, side, row) for row in range(BERTH_ROWS)],
            })  # fmt: skip
        out.append({
            "name": name,
            "mouth_fore": cv.r(np.array([0.0, y, z0]) - offset),
            "mouth_aft": cv.r(np.array([0.0, y, z1]) - offset),
            "clear_half_m": [round(float(half[0]), 3), round(float(half[1] - cut[1]), 3)],
            "forward": [0.0, 0.0, -1.0],
            "up": [0.0, 1.0, 0.0],
            "approach": [0.0, 0.0, -1.0],
            "release": [0.0, 0.0, -1.0],
            "lanes": lanes,
        })  # fmt: skip
    return out


def cradle_entries(offset: np.ndarray) -> list[dict[str, Any]]:
    """The berths as docking hardpoints (body frame), row by row from the bow mouths back, so the first fighters aboard take
    the front of every lane. A fighter floats on its berth with its belly on ``position``, its nose to the bow; it is pushed
    ahead along its lane to ``release_to`` and drawn in from ``approach_from`` behind the stern mouth."""
    u = SPEC.u
    z0, z1 = rw.TUBE_Z[0] * u, rw.TUBE_Z[1] * u
    out = []
    for row in range(BERTH_ROWS):
        for tube, sign in TUBES:
            for side, x in LANES:
                y = sign * rw.TUBE_Y * u - BERTH_BELLY_M
                out.append({
                    "name": berth_name(tube, side, row),
                    "tube": tube,
                    "lane": f"{tube}_{side}",
                    "row": row + 1,
                    "position": cv.r(np.array([x, y, z0 + BERTH_FIRST_M + row * BERTH_PITCH_M]) - offset),
                    "forward": [0.0, 0.0, -1.0],
                    "up": [0.0, 1.0, 0.0],
                    "approach_from": cv.r(np.array([x, y, z1 + TUBE_ENTRY_M]) - offset),
                    "release_to": cv.r(np.array([x, y, z0 - TUBE_EXIT_M]) - offset),
                })  # fmt: skip
    return out


def turret_entries(offset: np.ndarray) -> list[dict[str, Any]]:
    """The eight plasma turret mounts (body frame): on each arm's deck above and below, before the ring and behind it."""
    u = SPEC.u
    out = []
    for where, (x, z) in zip(("fore", "aft"), rw.TURRETS, strict=True):
        for face, sign in (("dorsal", 1.0), ("ventral", -1.0)):
            for side, sx in (("r", 1.0), ("l", -1.0)):
                at = np.array([sx * x * u, sign * rw.ARM_HALF * u, z * u])
                out.append({"name": f"{where}_{face}_{side}", "position": cv.r(at - offset), "up": [0.0, sign, 0.0], "arc_deg": TURRET_ARC_DEG,
                            "barrel_m": TURRET.barrel_m})  # fmt: skip
    return out


def rack_entries(offset: np.ndarray) -> list[dict[str, Any]]:
    """The missile racks in the diagonal bays of the ring's bow face (body frame): the middle of the rack's face, the way its
    missiles leave (``forward``: ahead and outward) and the face's up."""
    u = SPEC.u
    centre = np.array([0.0, 0.0, rw.RING_Z * u])
    out = []
    for clock in rw.rack_clocks():
        basis, middle = rw.slope_frame(clock, u)
        at = centre + middle + basis @ np.array([0.0, rw.RACK[1] * u, 0.0])
        out.append({"name": f"rack_{clock:03d}", "position": cv.r(at - offset), "forward": cv.r(basis[:, 1]), "up": cv.r(basis[:, 2]),
                    "cells": RACK_CELLS})  # fmt: skip
    return out


def chunk_joints() -> dict[str, np.ndarray]:
    """Where each chunk breaks away (authored frame): the bow at the cone's shoulders, the ring and the tubes at the ring's
    station, the engine block at the core's stern, the core at its own middle."""
    u = SPEC.u
    tube = np.array([0.0, (rw.TUBE_Y - rw.TUBE_OUTER[0][1]) * u, rw.RING_Z * u])
    return {"bow": np.array([0.0, 0.0, rw.CONE[1] * u]), "core": np.array([0.0, 0.0, 0.5 * sum(rw.CORE_Z) * u]),
            "ring": np.array([0.0, 0.0, rw.RING_Z * u]), "tube_upper": tube, "tube_lower": tube * [1.0, -1.0, 1.0],
            "engines": np.array([0.0, 0.0, rw.CORE_Z[1] * u])}


def nav_lights(offset: np.ndarray, length: float) -> dict[str, Any]:
    """Running lights: red and green on the ring's rim at nine and three o'clock, white on its top with a lamp over the upper
    tube's bow mouth, and the eye's glow."""
    u = SPEC.u
    rim = rw.RING_R[1] * u + NAV_CLEARANCE_M
    flank = np.array([rim, 0.0, rw.RING_Z * u])
    lamp = np.array([0.0, (rw.TUBE_Y + rw.TUBE_OUTER[0][1] + rw.TUBE_COLLAR) * u + NAV_CLEARANCE_M, (rw.TUBE_Z[0] + 2.0) * u])
    return {
        "port": cv.r(flank * [-1.0, 1.0, 1.0] - offset),
        "starboard": cv.r(flank - offset),
        "top": cv.r(np.array([0.0, rim, rw.RING_Z * u]) - offset),
        "top_lamp": cv.r(lamp - offset),
        "top_lamp_range_m": round(NAV_LAMP_RANGE_SHARE * length, 2),
        "cabin": cv.r(np.array([0.0, 0.0, rw.EYE_Z[0] * u - 1.0]) - offset),
        "cabin_range_m": round(NAV_CABIN_RANGE_SHARE * length, 2),
    }


def hardpoints(pieces: list[cv.Piece], chunks: list[dict[str, Any]], offset: np.ndarray) -> dict[str, Any]:
    """The hardpoints document in the body frame (authored positions minus ``offset``); ``chunks`` are the ``write_chunks``
    entries. Collision is the manifest's ``collision`` section, so the legacy primitive list is empty."""
    u = SPEC.u
    parts = [p.part for p in cv.with_twins(pieces)]
    lo, hi = Mesh.concatenate(p.mesh for p in parts).bounds()
    length = float(hi[2] - lo[2])
    com = np.array([0.0, 0.0, float(mass_centroid(parts)[2])])  # on the thrust line
    pods = []
    for name, mouth, radius in rw.nozzles(SPEC):
        pods.append({
            "name": name,
            "side": "left" if mouth[0] < 0 else "right",
            "center": cv.r(mouth - np.array([0.0, 0.0, 6.0 * u]) - offset),
            "main": {"position": cv.r(mouth - offset), "exhaust": [0.0, 0.0, 1.0], "radius": round(radius, 3)},
        })  # fmt: skip
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
        "cockpit_camera": {"position": cv.r(np.array([0.0, 0.0, rw.EYE_Z[0] * u - 0.5]) - offset), "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": cv.r((0.0, CHASE_ANCHOR_SHARE[0] * length, CHASE_ANCHOR_SHARE[1] * length))},
        "muzzles": [],
        "pods": pods,
        "rcs": [],
        "collision": [],
        "nav_lights": nav_lights(offset, length),
        "turrets": turret_entries(offset),
        "missile_racks": rack_entries(offset),
        "cradles": cradle_entries(offset),
        "tubes": tube_entries(offset),
        "jump_point": {
            "position": cv.r(np.array([0.0, 0.0, -JUMP_AHEAD_M]) - offset),
            "forward": [0.0, 0.0, -1.0],
            "mouth_radius_m": JUMP_MOUTH_RADIUS_M,
        },
        "chunks": [{**c, "joint": cv.r(joints[c["name"]] - offset)} for c in chunks],
    }


# --- build -------------------------------------------------------------------------------------------------------------
def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the hull, its chunks, its turret, its hardpoints and its collision into ``ctx.out_dir``."""
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)
    built = built_pieces()
    pieces = [b.piece for b in built]

    sampled = cv.sample_pieces(pieces, ctx, spacing)
    offset = cv.centroid(sampled)
    hull = cv.write_hull_atlases(out_dir, ASSET_ID, cv.hull_parts(sampled, offset), CHUNK_ORDER, SURFACE.style, ctx, ATLAS_PX, comments)
    files: list[Path] = list(hull.files)

    turret_style = dataclasses.replace(SURFACE.style, materials={**SURFACE.style.materials, "hazard": SURFACE.style.material("stripe")})
    turret_files, turret_entry = write_turret(out_dir, ASSET_ID, TURRET, turret_style, ctx, comments)
    files += turret_files

    shapes = compound(built)
    skin = np.concatenate([s.samples.positions for s in sampled])
    cover = col.skin_coverage([s for piece in shapes.values() for s in piece], skin, COVER_TOLERANCE_M, COVER_REACH_M, spacing)

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
            "turret": turret_entry,
            "chunks": [c["name"] for c in hull.chunks],
            "surface_spacing_m": spacing,
            "dimensions_m": {"length": hp["length_m"], "span": hp["span_m"], "height": hp["height_m"]},
            "tube_count": len(hp["tubes"]),
            "lane_count": sum(len(tube["lanes"]) for tube in hp["tubes"]),
            "cradle_count": len(hp["cradles"]),
            "collision": collision_section(shapes, offset, cover),
        },
    )
    files.append(write_manifest(out_dir, manifest))
    warnings = () if cover.ok else (f"collision coverage: {cover.to_json()}",)
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), warnings)
