"""``raider_strike_carrier``: the raiders' strike carrier, 144 m, the first capital hull (M12-T19, Q25 to Q30; docs/assets-capital.md
and docs/design-references.md, "Raider strike carrier").

Composition only: the pieces of ``parts/raider_carrier.py`` in one of the ``raider_capital`` surfaces, through the shared hull
pipeline (``core/civilian.py``), with compound collision from ``core/collision.py`` (M7's D73).

Layout (authored frame, metres, before re-centring; -Z is forward, the bow spikes' tips at z = 0, x and y on the ship's axis):
the drum with the hangar mouth in its face, the two rings round it, eighteen cradle arms on the drum and the rings, the spine,
the centre section with a box hull on each side, and the engine cluster behind it. No weapons: its fighters are its weapons.

``hardpoints.json`` adds to the ships' contract: ``cradles[]`` (where a Delta-V docks: the pad's centre, the docked fighter's
forward and up, and the directions it comes in and leaves along) and ``jump_point`` (where the carrier opens its own point,
ahead of the bow). The manifest's ``collision`` section holds the convex shapes per break-up chunk and their coverage.

Options: ``surface`` (``a``, ``b`` or ``c``: the candidates of ``styles/raider_capital.py``, for the maintainer's option sheet),
``spacing`` (m, the surface samples'), ``atlas_px`` (the hull's atlas).
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
from ..parts import raider_carrier as rc
from ..styles.raider_capital import DEFAULT_SURFACE, SURFACES, Surface

ASSET_ID = "raider_strike_carrier"
GENERATOR_VERSION = 1
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"
SPEC = rc.CarrierSpec()

DEFAULT_SPACING_M = 0.5  # the surface samples' spacing: the body origin, the chunks' offsets, the collision's coverage
DEFAULT_ATLAS_PX = 4096  # about 8 cm a texel on 144 m
CHUNK_ORDER = ("drum", "ring_mid", "ring_outer", "core", "box_l", "box_r")

# Collision (docs/assets-capital.md, "Collision"): what one body may carry, and how close the shapes must sit to the hull.
BUDGET = col.Budget(max_pieces=64, max_hull_points=32)
COVER_TOLERANCE_M = 1.0  # every point of the hull is this near a shape (thin fittings stand a little proud)
COVER_REACH_M = 2.5  # no shape stands further than this from the hull (a ring's hole and a cradle's approach stay open)

# Docking: a fighter comes in along a cradle's ``approach`` from this far out, and leaves along ``release``.
APPROACH_M = 60.0
# The carrier's own jump point: its mouth clears the hull's 77 m half diagonal, and opens this far ahead of the bow.
JUMP_MOUTH_RADIUS_M = 120.0
JUMP_AHEAD_M = 300.0

CHASE_ANCHOR_SHARE = (0.3, 1.2)
NAV_CLEARANCE_M = 0.15
NAV_LAMP_RANGE_SHARE = 0.3
NAV_CABIN_RANGE_SHARE = 0.08
FLIP = np.array([-1.0, 1.0, 1.0])


def surface_of(ctx: BuildContext) -> Surface:
    key = str(ctx.option("surface", DEFAULT_SURFACE)).lower()
    if key not in SURFACES:
        raise ValueError(f"surface must be one of {sorted(SURFACES)}, not {key!r}")
    return SURFACES[key]


def built_pieces(surface: Surface) -> list[rc.Built]:
    """Every piece with its collision shapes, dressed in the surface's plating (centre pieces and the starboard of each pair)."""
    built = rc.assemble(SPEC, surface.style)
    layouts.dress((b.piece.part for b in built), layouts.raider_carrier(SPEC.u, surface))
    return built


def hull_pieces(surface: Surface | None = None) -> list[cv.Piece]:
    return [b.piece for b in built_pieces(surface or SURFACES[DEFAULT_SURFACE])]


def collision_shapes(built: list[rc.Built]) -> dict[str, list[col.Shape]]:
    """The convex shapes per break-up chunk, in the authored frame: each piece's own, and a starboard piece's mirrored to port."""
    out: dict[str, list[col.Shape]] = {group: [] for group in CHUNK_ORDER}
    for b in built:
        out[b.piece.group] += list(b.shapes)
        if b.piece.side == cv.RIGHT:
            out[cv.left_name(b.piece.group)] += [s.mirrored("x").renamed(cv.left_name(s.name)) for s in b.shapes]
    return out


def compound(built: list[rc.Built]) -> col.Compound:
    return col.build(collision_shapes(built), BUDGET)


# --- hardpoints --------------------------------------------------------------------------------------------------------
def cradle_entries(offset: np.ndarray) -> list[dict[str, Any]]:
    """Each cradle as a docking hardpoint (body frame): the docked fighter rests its belly on ``position`` with its nose along
    ``forward`` and its back along ``up``; it comes in from ``approach_from`` along ``approach`` and leaves along ``release``."""
    out = []
    for c in rc.cradles(SPEC):
        out.append({
            "name": c.name,
            "ring": c.ring,
            "clock_deg": c.clock_deg,
            "position": cv.r(c.pad_centre - offset),
            "forward": [0.0, 0.0, -1.0],
            "up": cv.r(c.out),
            "approach_from": cv.r(c.pad_centre + APPROACH_M * c.out - offset),
            "approach": cv.r(-c.out),
            "release": cv.r(c.out),
        })  # fmt: skip
    return out


def chunk_joints() -> dict[str, np.ndarray]:
    """Where each chunk breaks away (authored frame): the drum and the rings at the spine's bow end, a box at the centre
    section's flank, the core at its own middle."""
    u = SPEC.u
    box = np.array([rc.BOX_X[0] * u, 0.0, 62.0 * u])
    return {"drum": np.array([0.0, 0.0, rc.DRUM_AFT_Z * u]), "ring_mid": np.array([0.0, 0.0, rc.RING_MID[0] * u]),
            "ring_outer": np.array([0.0, 0.0, rc.RING_OUTER[0] * u]), "core": np.array([0.0, 0.0, 62.0 * u]), "box_r": box, "box_l": box * FLIP}


def nav_lights(offset: np.ndarray, length: float) -> dict[str, Any]:
    """Running lights: red and green on the boxes' outer flanks, white on the slab's top with a lamp over the spine, and the
    hangar mouth's glow."""
    u = SPEC.u
    flank = np.array([rc.BOX_X[1] * u + NAV_CLEARANCE_M, 20.0 * u, 62.0 * u])
    top = np.array([0.0, rc.SLAB_HALF[1] * u + NAV_CLEARANCE_M, 62.0 * u])
    lamp = np.array([0.0, 8.0 * u, 38.0 * u])
    mouth = np.array([0.0, 0.0, rc.FRAME_Z * u - 1.0])
    return {
        "port": cv.r(flank * FLIP - offset),
        "starboard": cv.r(flank - offset),
        "top": cv.r(top - offset),
        "top_lamp": cv.r(lamp - offset),
        "top_lamp_range_m": round(NAV_LAMP_RANGE_SHARE * length, 2),
        "cabin": cv.r(mouth - offset),
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
    bell_z, bell_r = rc.ENGINE_PROFILE[3][0] * u, rc.ENGINE_PROFILE[3][1] * u
    engine = {
        "name": "main",
        "side": "centre",
        "center": cv.r(np.array([0.0, 0.0, 0.5 * (rc.MOUNT[1] * u + bell_z)]) - offset),
        "main": {"position": cv.r(np.array([0.0, 0.0, bell_z]) - offset), "exhaust": [0.0, 0.0, 1.0], "radius": round(bell_r, 3)},
    }
    bridge = np.array(rc.DISH[1]) * u - np.array([0.0, 0.0, 0.5 * rc.DISH[0][2] * u])  # the sensor housing's bow face
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
        "cockpit_camera": {"position": cv.r(bridge - offset), "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": cv.r((0.0, CHASE_ANCHOR_SHARE[0] * length, CHASE_ANCHOR_SHARE[1] * length))},
        "muzzles": [],
        "pods": [engine],
        "rcs": [],
        "collision": [],
        "nav_lights": nav_lights(offset, length),
        "turrets": [],
        "cradles": cradle_entries(offset),
        "jump_point": {
            "position": cv.r(np.array([0.0, 0.0, -JUMP_AHEAD_M]) - offset),
            "forward": [0.0, 0.0, -1.0],
            "mouth_radius_m": JUMP_MOUTH_RADIUS_M,
        },
        "chunks": [{**c, "joint": cv.r(joints[c["name"]] - offset)} for c in chunks],
    }


# --- build -------------------------------------------------------------------------------------------------------------
def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the hull, its chunks, its hardpoints and its collision into ``ctx.out_dir``."""
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")
    surface = surface_of(ctx)
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)
    built = built_pieces(surface)
    pieces = [b.piece for b in built]

    sampled = cv.sample_pieces(pieces, ctx, spacing)
    offset = cv.centroid(sampled)
    hull_ctx = dataclasses.replace(ctx, options={"atlas_px": DEFAULT_ATLAS_PX, **ctx.options})
    hull = cv.write_hull(out_dir, ASSET_ID, cv.hull_parts(sampled, offset), CHUNK_ORDER, surface.style, hull_ctx, comments)
    files: list[Path] = list(hull.files)

    shapes = compound(built)
    skin = np.concatenate([s.samples.positions for s in sampled])
    cover = col.coverage(shapes.shapes, skin, COVER_TOLERANCE_M, COVER_REACH_M, spacing)

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
            "surface": surface.key,
            "cradle_count": len(hp["cradles"]),
            "collision": shapes.to_json(offset, cover),
        },
    )
    files.append(write_manifest(out_dir, manifest))
    warnings = () if cover.ok else (f"collision coverage: {cover.to_json()}",)
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), warnings)
