"""``ea_shuttle`` and ``ea_atmo_shuttle``: the Earth Alliance's two small shuttles (M10-T57; docs/assets-civilian.md and
docs/design-references.md, "EA shuttle" and "EA atmospheric shuttle").

Both are small craft by the class budgets (M10 Q38): one 2 048 px atlas, the low texture set a mip level down.

Composition only: the pieces of ``parts/ea_shuttle.py`` (modelled at 18.64 m, a blunt octagonal box hull) and
``parts/ea_atmo_shuttle.py`` (modelled at 25.59 m long, 45.6 m across its swept wings, a lifting body), built at the
maintainer's lengths (M10 Q65, T69: 38 m and 29 m), each in its look from
``styles/ea_shuttle.py``, through the shared civilian pipeline (``core/civilian.py``): one textured mesh with a full and
a low texture set, the fallback mesh, the break-up chunks as cuts of the hull, ``hardpoints.json`` and the manifest,
every output derived from the placed pieces so they agree by construction. Neither craft carries a turret.
``hardpoints.json`` adds ``docking_ports[]`` to the civilians' contract: where another hull's lock meets this one (the
shuttle's stern hatch; the atmospheric shuttle has none).
"""

from __future__ import annotations

import json
import math
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core import civilian as cv
from ..core.budgets import LOW_SHRINK, low_set_mb, texture_mb
from ..core.color import capture_albedo
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh
from ..core.manifest import build_manifest, write_manifest
from ..core.seams import Cut, Feature, Hatch, Plates, SeamLayout
from ..core.textures import Marking
from ..parts import Part, mass_centroid, total_mass
from ..parts import ea_atmo_shuttle as ap
from ..parts import ea_shuttle as sp
from ..parts.propulsion import pilot_tags
from ..styles.ea_shuttle import ATMO_LOOK, SHUTTLE_LOOK, Look

SHUTTLE_ID = "ea_shuttle"
ATMO_ID = "ea_atmo_shuttle"
GENERATOR_VERSION = 1
SHUTTLE_LENGTH_M = 38.0  # the maintainer's lengths (M10 Q65): the parts are modelled at T01's, then grown
ATMO_LENGTH_M = 29.0
SHIP_CLASS = "small_craft"  # the class budget both are held to (docs/assets-capital.md, "Class budgets")
HARDPOINTS_NAME = "hardpoints.json"
BURIED_MARGIN_M = 0.02
CHASE_ANCHOR_SHARE = (0.3, 1.2)  # above and behind the centroid, in lengths
NAV_CLEARANCE_M = 0.1
NAV_LAMP_RANGE_SHARE = 0.3
NAV_CABIN_RANGE_SHARE = 0.05
GLASS_SRGB = 0x10161C
INF = float("inf")
FLIP = np.array([-1.0, 1.0, 1.0])
Port = tuple[str, Sequence[float], Sequence[float]]  # an RCS port: name, position, exhaust


@dataclass(frozen=True)
class Craft:
    """What tells one craft from another for the shared build: its pieces, chunks, paint and hardpoints. The Panama and the
    construction tender (``assets/ea_work_ships.py``) are built through it too."""

    asset_id: str
    spacing_m: float  # the surface samples' spacing at the authored size: the body origin and the chunks' offsets
    chunk_order: tuple[str, ...]
    look: Look
    assemble: Callable[[Any], list[cv.Piece]]
    dress: Callable[[list[cv.Piece], Look], tuple[list[cv.Piece], dict[str, tuple[Marking, ...]]]]
    thrust_y: float
    engines: tuple[tuple[str, str, str, float], ...]  # pod name, side, the piece whose anchors it reads, main radius
    engine_split_m: float  # a centre engine is two pods this far either side of its axis
    retros: tuple[float, float, float, float]  # x (mirrored), y, z, radius of the braking ports at the bow
    ports: Callable[[dict[str, Part]], list[Port]]
    lights: Callable[[dict[str, Part]], dict[str, np.ndarray]]
    joints: Callable[[dict[str, Part]], dict[str, np.ndarray]]
    docks: Callable[[dict[str, Part]], list[tuple[str, np.ndarray, np.ndarray]]]  # name, position, the way out of the hull
    ship_class: str = SHIP_CLASS  # the class budget it is held to
    atlas_px: int = cv.HULL_ATLAS_PX
    scale: float = 1.0  # built this many times the authored size (M10-T69, Q65); every authored number above is at 1


# --- surfaces ------------------------------------------------------------------------------------------------------------------
def plating(look: Look, cell: tuple[float, float], seed: int, long_axis: int = 2) -> list[Feature]:
    """The show's patchwork: plates of mixed size, each with its own tone, and a scatter of small proud hatches over them."""
    return [
        Plates(level=3, wrap="sides", long_axis=long_axis, cell=cell, splits=3, min_m=0.22, keep=0.25, tone=look.plate_tone, sheen=0.07,
               grime=look.plate_grime, grime_m=0.12, depth=0.5, dark=0.5, width=0.8, seed=seed),
        Plates(level=3, wrap="sides", long_axis=long_axis, cell=(0.5 * cell[0], 0.6 * cell[1]), splits=1, min_m=0.15, scatter=0.08, inset_m=0.05,
               tone=look.plate_tone, dark=0.7, depth=0.7, seed=seed + 6),
    ]  # fmt: skip


def _bands(part: str, look: Look) -> tuple[Marking, ...]:
    return tuple(Marking.band(part, (0.0, 0.0, 0.0), sp.Z_AXIS, z + 0.5 * width, width, capture_albedo(colour)) for z, width, colour in look.bands)


def dress_shuttle(pieces: list[cv.Piece], look: Look) -> tuple[list[cv.Piece], dict[str, tuple[Marking, ...]]]:
    """The shuttle's seams and paint: frames along the hull, hatches on roof and keel, the patchwork, the nose band with its
    number, and the dark slots along each upper chine."""
    roof, keel = sp.CABIN[0], sp.CABIN[5]
    up, down = {"facing": sp.Y_AXIS, "min_dot": 0.8}, {"facing": (0.0, -1.0, 0.0), "min_dot": 0.8}
    major: list[Feature] = [Cut(axis=2, at=z, level=1, width=1.4) for z in (2.0, sp.CABIN_Z[0], sp.CABIN_Z[1])]
    major += [Cut(axis=0, at=0.0, level=1, lo=(-INF, 0.0, 5.6), **up)]
    full: list[Feature] = [Cut(axis=2, at=z, level=2) for z in (1.17, 3.6, 7.3, 9.15, 11.0, 14.6, 16.4)]
    full += [Cut(axis=1, at=y, level=2, lo=(-INF, -INF, sp.CABIN_Z[0])) for y in (sp.CABIN[3], sp.CABIN[4])]
    full += [
        Hatch(centre=(0.0, roof, 6.9), right=sp.X_AXIS, up=sp.Z_AXIS, size=(1.3, 0.9), corner_m=0.06, sunk=0.6, tone=0.9, level=2, **up),
        Hatch(centre=(0.0, keel, 10.5), right=sp.X_AXIS, up=sp.Z_AXIS, size=(2.2, 3.0), corner_m=0.1, sunk=0.6, tone=0.92, level=2, **down),
        Hatch(centre=(0.0, keel, 15.6), right=sp.X_AXIS, up=sp.Z_AXIS, size=(1.6, 1.4), corner_m=0.08, sunk=0.6, tone=0.88, level=2, slats=5, **down),
        Hatch(centre=(1.1, sp.roof_y(3.4), 3.4), right=sp.X_AXIS, up=sp.Z_AXIS, size=(0.7, 0.5), corner_m=0.04, sunk=0.6, tone=0.9, level=2, **up),
    ]
    layout = SeamLayout.of(major + full + plating(look, (1.6, 1.0), 571)).mirrored_too()
    dressed = [cv.Piece(p.part.with_seams(layout), p.solid, p.side, p.fine) for p in pieces]

    marks: dict[str, list[Marking]] = {"hull_bow": list(_bands("hull_bow", look)), "nose_pipes_r": list(_bands("nose_pipes_r", look)),
                                       "nose_pipes_l": list(_bands("nose_pipes_l", look))}
    if look.number:
        band_z, band_w, _ = look.bands[0]
        at = band_z + 0.5 * band_w
        marks["hull_bow"].append(Marking.text("hull_bow", look.number, (0.0, sp.roof_y(at), at), (-1.0, 0.0, 0.0), sp.Z_AXIS, sp.Y_AXIS,
                                              0.6 * band_w, capture_albedo(look.number_colour)))
    # Five dark slots on each upper chine, as the reference's cabin has them.
    glass = capture_albedo(GLASS_SRGB)
    nx, ny = sp.CHINE_NORMAL
    for side in (1.0, -1.0):
        for z in (6.96, 7.90, 8.84, 9.775, 10.715):
            marks.setdefault("hull_cabin", []).append(Marking.rect("hull_cabin", (side * 2.97, 1.035, z), sp.Z_AXIS, (-side * ny, nx, 0.0),
                                                                    (side * nx, ny, 0.0), (0.62, 1.1), glass))
    return dressed, {name: tuple(m) for name, m in marks.items()}


def dress_atmo(pieces: list[cv.Piece], look: Look) -> tuple[list[cv.Piece], dict[str, tuple[Marking, ...]]]:
    """The atmospheric shuttle's seams and paint: frames across the body, spars along the wings, the patchwork, then the
    look's bands across the body's back."""
    major: list[Feature] = [Cut(axis=2, at=z, level=1, width=1.4) for z in (2.0, 9.2, 14.6)]
    major += [Cut(axis=0, at=x, level=1, lo=(-INF, -INF, 14.0)) for x in (ap.WING_STATIONS[1][0], 13.2)]
    full: list[Feature] = [Cut(axis=2, at=z, level=2) for z in (4.0, 6.5, 11.8, 16.6, 19.5, 22.0)]
    full += [Cut(axis=0, at=x, level=2) for x in (2.2, 4.0, 6.2, 8.3, 15.4, 17.7, 20.2)]
    full += [
        Hatch(centre=(2.9, 1.0, 6.4), right=sp.X_AXIS, up=sp.Z_AXIS, size=(1.2, 1.6), corner_m=0.08, sunk=0.6, tone=0.92, level=2, facing=sp.Y_AXIS, min_dot=0.6),
        Hatch(centre=(0.0, -1.9, 12.5), right=sp.X_AXIS, up=sp.Z_AXIS, size=(3.0, 4.0), corner_m=0.12, sunk=0.6, tone=0.9, level=2, facing=(0.0, -1.0, 0.0), min_dot=0.6),
        Hatch(centre=(5.2, -1.4, 9.0), right=sp.X_AXIS, up=sp.Z_AXIS, size=(1.6, 2.6), corner_m=0.1, sunk=0.6, tone=0.88, level=2, facing=(0.0, -1.0, 0.0), min_dot=0.6),
    ]
    layout = SeamLayout.of(major + full + plating(look, (2.4, 1.5), 613)).mirrored_too()
    dressed = [cv.Piece(p.part.with_seams(layout), p.solid, p.side, p.fine) for p in pieces]

    marks = {name: _bands(name, look) for name in ("body", "spine", "intake_r", "intake_l")}
    return dressed, marks


# --- hardpoints ----------------------------------------------------------------------------------------------------------------
def shuttle_ports(by_name: dict[str, Part]) -> list[Port]:
    """Cosmetic RCS (authored frame; ``r_`` names are mirrored): on the bow's and the stern's flank, the roof and the keel."""
    bow_w, stern_w = sp.flank_half_width(3.2), sp.CABIN[2] + 0.42
    return [
        ("r_bow", (bow_w + 0.17, sp.AXIS_Y, 3.2), sp.X_AXIS),
        ("r_stern", (stern_w, sp.AXIS_Y, 15.5), sp.X_AXIS),
        ("r_bow_up", (1.4, sp.roof_y(1.8), 1.8), sp.Y_AXIS),
        ("r_bow_down", (1.4, 2.0 * sp.AXIS_Y - sp.roof_y(1.8), 1.8), (0.0, -1.0, 0.0)),
        ("r_stern_up", (1.53, sp.CABIN[0] + 0.34, 14.5), sp.Y_AXIS),
        ("r_stern_down", (1.53, sp.CABIN[5] - 0.33, 14.5), (0.0, -1.0, 0.0)),
    ]


def shuttle_lights(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Running lights: red and green on the flank blocks amidships, white on the stern's crown, the cabin glow behind the hood."""
    top = by_name["roof_fins"].anchor("top").position
    return {"starboard": np.array([sp.CABIN[2] + 0.42 + NAV_CLEARANCE_M, sp.AXIS_Y, sp.FLANK_BLOCK_Z[2] + 0.5 * sp.FLANK_BLOCK_LENGTH]),
            "top": top + np.array([0.0, NAV_CLEARANCE_M, 0.0]), "top_lamp": top + np.array([0.0, 1.5, 0.0]), "cabin": np.array(sp.EYE)}


def shuttle_joints(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Where each chunk breaks away: on the hull's axis at the two cuts, the cabin between them."""
    bow, stern = np.array([0.0, sp.AXIS_Y, sp.CABIN_Z[0]]), np.array([0.0, sp.AXIS_Y, sp.CABIN_Z[1]])
    return {"bow": bow, "cabin": 0.5 * (bow + stern), "stern": stern}


def shuttle_docks(by_name: dict[str, Part]) -> list[tuple[str, np.ndarray, np.ndarray]]:
    """The stern hatch: the one way in."""
    hatch = by_name["stern_plate"].anchor("hatch")
    return [("stern_hatch", hatch.position, hatch.direction)]


def atmo_ports(by_name: dict[str, Part]) -> list[Port]:
    """Cosmetic RCS (authored frame; ``r_`` names are mirrored): at the wing tips, on the nose and at the stern's corners."""
    tip = by_name["wing_r"].anchor("tip").position
    return [
        ("r_tip_up", tip + np.array([-0.3, 0.1, 0.0]), sp.Y_AXIS),
        ("r_tip_down", tip + np.array([-0.3, -0.1, 0.0]), (0.0, -1.0, 0.0)),
        ("r_nose", (2.25, ap.EDGE_Y, 1.0), sp.X_AXIS),
        ("r_stern", (10.27, ap.EDGE_Y, 17.0), sp.X_AXIS),
        ("nose_up", (0.0, ap.body_top(0.0, 1.0), 1.0), sp.Y_AXIS),
        ("nose_down", (0.0, -0.65, 1.0), (0.0, -1.0, 0.0)),
    ]


def atmo_lights(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Running lights: red and green at the wing tips, white on the tailplane's crest, the cabin glow behind the windshield."""
    top = by_name["tailplane"].anchor("top").position
    return {"starboard": by_name["wing_r"].anchor("tip").position + np.array([NAV_CLEARANCE_M, 0.0, 0.0]),
            "top": top + np.array([0.0, NAV_CLEARANCE_M, 0.0]), "top_lamp": top + np.array([0.0, 2.0, 0.0]), "cabin": np.array(ap.EYE)}


def atmo_joints(by_name: dict[str, Part]) -> dict[str, np.ndarray]:
    """Where each chunk breaks away: a wing at its root, the tail at the fin's foot, the engines at the stern face."""
    wing = by_name["wing_r"].anchor("joint").position
    engines = np.array([0.0, ap.ENGINE_Y, ap.BODY_END_Z])
    return {"wing_r": wing, "wing_l": wing * FLIP, "tail": by_name["fin"].anchor("joint").position, "engines": engines,
            "body": np.array([0.0, ap.EDGE_Y, 14.0])}


def no_docks(by_name: dict[str, Part]) -> list[tuple[str, np.ndarray, np.ndarray]]:
    return []


SHUTTLE = Craft(SHUTTLE_ID, 0.2, ("bow", "cabin", "stern"), SHUTTLE_LOOK, sp.assemble, dress_shuttle, sp.AXIS_Y,
                (("l", "left", "engine_l", 0.6), ("r", "right", "engine_r", 0.6)), 0.0, (1.5, sp.AXIS_Y, sp.HULL_STATIONS[0][0], 0.25),
                shuttle_ports, shuttle_lights, shuttle_joints, shuttle_docks, scale=SHUTTLE_LENGTH_M / sp.LENGTH_M)  # fmt: skip
ATMO = Craft(ATMO_ID, 0.25, ("body", "wing_l", "wing_r", "tail", "engines"), ATMO_LOOK, ap.assemble, dress_atmo, ap.ENGINE_Y,
             (("l", "left", "engine_l", ap.ENGINE_EXIT_R), ("cl", "left", "engine_c", 0.5 * ap.ENGINE_EXIT_R),
              ("cr", "right", "engine_c", 0.5 * ap.ENGINE_EXIT_R), ("r", "right", "engine_r", ap.ENGINE_EXIT_R)), 0.3,
             (2.0, ap.EDGE_Y, 0.8, 0.3), atmo_ports, atmo_lights, atmo_joints, no_docks, scale=ATMO_LENGTH_M / ap.LENGTH_M)  # fmt: skip


def hardpoints(craft: Craft, pieces: list[cv.Piece], chunks: list[dict[str, Any]], offset: np.ndarray) -> dict[str, Any]:
    """The hardpoints document in the body frame (authored positions at the craft's scale, minus ``offset``); ``pieces`` are
    the authored ones, ``chunks`` the ``write_chunks`` entries. No turrets and no muzzles: the shuttles are unarmed."""
    k = craft.scale
    authored = [p.part for p in cv.with_twins(pieces)]
    by_name = {p.name: p for p in authored}  # the craft's hardpoint helpers read authored numbers
    parts = [cv.scaled_part(p, k) for p in authored] if k != 1.0 else authored
    lo, hi = Mesh.concatenate(p.mesh for p in parts).bounds()
    length = float(hi[2] - lo[2])
    com = k * np.array([0.0, craft.thrust_y, float(mass_centroid(authored)[2])])  # on the thrust line, so main thrust makes no pitch torque

    def at(v: Any) -> list[float]:
        return cv.r(k * np.asarray(v, dtype=float) - offset)

    retro_x, retro_y, retro_z, retro_r = craft.retros
    pods = []
    for name, side, piece_name, radius in craft.engines:
        engine = by_name[piece_name]
        sign = -1.0 if side == "left" else 1.0
        shift = np.array([sign * craft.engine_split_m, 0.0, 0.0]) if piece_name.endswith("_c") else np.zeros(3)
        main = engine.anchor("main")
        retro = np.array([sign * retro_x, retro_y, retro_z])
        pods.append({
            "name": name,
            "side": side,
            "center": at(engine.anchor("centre").position + shift),
            "main": {"position": at(main.position + shift), "exhaust": cv.r(main.direction), "radius": round(k * radius, 3)},
            "retro": {"position": at(retro), "exhaust": [0.0, 0.0, -1.0], "radius": round(k * retro_r, 3)},
        })  # fmt: skip

    rcs = []
    for name, position, exhaust in craft.ports(by_name):
        p, e = np.asarray(position, dtype=float), np.asarray(exhaust, dtype=float)
        twins = [(name, p, e)] + ([("l_" + name[2:], p * FLIP, e * FLIP)] if name.startswith("r_") else [])
        for n, spot, out in twins:
            rcs.append({"name": n, "pod": "l" if spot[0] < -1e-6 else "r", "position": at(spot), "exhaust": cv.r(out),
                        "tags": pilot_tags(k * spot, out, com)})  # fmt: skip

    lights = craft.lights(by_name)
    joints = craft.joints(by_name)
    eye = lights["cabin"]
    return {
        "asset_id": craft.asset_id,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(length, 3),
        "span_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "mass_kg": round(total_mass(parts), 1),
        "inertia_estimate_kg_m2": cv.r(cv.inertia_estimate(parts, com)),
        "center_of_mass": cv.r(com - offset),
        "cockpit_camera": {"position": at(eye), "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": cv.r((0.0, CHASE_ANCHOR_SHARE[0] * length, CHASE_ANCHOR_SHARE[1] * length))},
        "muzzles": [],
        "pods": pods,
        "rcs": rcs,
        "collision": cv.collision_json(parts, offset),
        "nav_lights": {
            "port": at(lights.get("port", lights["starboard"] * FLIP)),
            "starboard": at(lights["starboard"]),
            "top": at(lights["top"]),
            "top_lamp": at(lights["top_lamp"]),
            "top_lamp_range_m": round(NAV_LAMP_RANGE_SHARE * length, 2),
            "cabin": at(eye),
            "cabin_range_m": round(max(NAV_CABIN_RANGE_SHARE * length, 1.0), 2),
        },
        "turrets": [],
        "docking_ports": [{"name": name, "position": at(spot), "out": cv.r(out), "up": [0.0, 1.0, 0.0]}
                          for name, spot, out in craft.docks(by_name)],
        "chunks": [{**c, "joint": at(joints[c["name"]])} for c in chunks],
    }


# --- build -------------------------------------------------------------------------------------------------------------------
def build_craft(craft: Craft, ctx: BuildContext) -> AssetOutputs:
    """Generate one craft into ``ctx.out_dir``.

    Options: ``spacing`` (m at the built size, the surface samples' spacing), ``atlas_px`` (the hull's atlas, default 2 048), ``occlusion``
    (default off).
    """
    spacing = float(ctx.option("spacing", craft.spacing_m * craft.scale))
    if spacing <= 0.0 or not math.isfinite(spacing):
        raise ValueError("spacing must be positive")
    ctx = BuildContext(ctx.out_dir, ctx.seed, {"atlas_px": craft.atlas_px, **ctx.options})
    look = craft.look
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{craft.asset_id} generator v{GENERATOR_VERSION} seed {ctx.seed}",)

    pieces, markings = craft.dress(craft.assemble(look.style), look)
    built, markings = cv.scaled_pieces(pieces, craft.scale), cv.scaled_markings(markings, craft.scale)
    sampled = cv.sample_pieces(built, ctx, spacing, buried_margin=BURIED_MARGIN_M * craft.scale)
    offset = cv.centroid(sampled)
    hull = cv.write_hull(out_dir, craft.asset_id, cv.hull_parts(sampled, offset, markings), craft.chunk_order, look.style, ctx, comments,
                         low_shrink=LOW_SHRINK)
    atlas = [int(hull.mesh_section["atlas_px"])]
    files: list[Path] = list(hull.files)

    hp = hardpoints(craft, pieces, hull.chunks, offset)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    manifest = build_manifest(
        asset_id=craft.asset_id,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        aabb_min=hull.aabb_min,
        aabb_max=hull.aabb_max,
        centroid_offset=offset,
        files={"obj": f"{craft.asset_id}.obj", "mesh": hull.mesh_section["file"], "hardpoints": HARDPOINTS_NAME},
        extra={
            "mesh": hull.mesh_section,
            "chunks": [c["name"] for c in hull.chunks],
            "surface_spacing_m": spacing,
            "dimensions_m": {"length": hp["length_m"], "span": hp["span_m"], "height": hp["height_m"]},
            "budget": {"class": craft.ship_class, "triangles": hull.mesh_section["triangles"], "texture_mb": round(texture_mb(atlas), 2),
                       "texture_mb_low": round(low_set_mb(atlas), 2)},
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(craft.asset_id, out_dir, manifest, tuple(files), ())


def build_shuttle(ctx: BuildContext) -> AssetOutputs:
    return build_craft(SHUTTLE, ctx)


def build_atmo(ctx: BuildContext) -> AssetOutputs:
    return build_craft(ATMO, ctx)
