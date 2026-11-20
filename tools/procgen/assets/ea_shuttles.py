"""``ea_shuttle`` and ``ea_atmo_shuttle``: the Earth Alliance's two small shuttles (M10-T57; docs/assets-civilian.md and
docs/design-references.md, "EA shuttle" and "EA atmospheric shuttle").

Composition only: the pieces of ``parts/ea_shuttle.py`` (18.64 m, a blunt octagonal box hull) and
``parts/ea_atmo_shuttle.py`` (25.59 m long, 45.6 m across its swept wings, a lifting body), each in one of the looks of
``styles/ea_shuttle.py``, through the shared civilian pipeline (``core/civilian.py``): one textured mesh with a full and
a low texture set, the fallback mesh, the break-up chunks as cuts of the hull, ``hardpoints.json`` and the manifest,
every output derived from the placed pieces so they agree by construction. Neither craft carries a turret.

Option ``look`` (``a``, ``b`` or ``c``) picks the surface option; the default is the one the maintainer chose.
"""

from __future__ import annotations

import functools
import json
import math
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core import civilian as cv
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
from ..styles.ea_shuttle import DEFAULT_OPTION, Look, atmo_looks, shuttle_looks

SHUTTLE_ID = "ea_shuttle"
ATMO_ID = "ea_atmo_shuttle"
GENERATOR_VERSION = 1
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
    """What tells the two shuttles apart for the shared build: their pieces, chunks, paint and hardpoints."""

    asset_id: str
    spacing_m: float  # the surface samples' spacing: the body origin and the chunks' offsets
    chunk_order: tuple[str, ...]
    looks: Callable[[], dict[str, Look]]
    assemble: Callable[[Any], list[cv.Piece]]
    dress: Callable[[list[cv.Piece], Look], tuple[list[cv.Piece], dict[str, tuple[Marking, ...]]]]
    thrust_y: float
    engines: tuple[tuple[str, str, str, float], ...]  # pod name, side, the piece whose anchors it reads, main radius
    engine_split_m: float  # a centre engine is two pods this far either side of its axis
    retros: tuple[float, float, float, float]  # x (mirrored), y, z, radius of the braking ports at the bow
    ports: Callable[[dict[str, Part]], list[Port]]
    lights: Callable[[dict[str, Part]], dict[str, np.ndarray]]
    joints: Callable[[dict[str, Part]], dict[str, np.ndarray]]


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


def _blotches(points: np.ndarray, normals: np.ndarray, phase: float, share: float) -> np.ndarray:
    """Where one colour of the camouflage lies: soft-edged blotches a few metres across, on every face but the belly's."""
    p = np.asarray(points, dtype=float)
    wave = (np.sin(0.61 * p[:, 0] + 0.23 * p[:, 2] + phase) * np.sin(0.19 * p[:, 0] - 0.47 * p[:, 2] + 1.7 * phase)
            + 0.5 * np.sin(1.13 * p[:, 0] + 0.83 * p[:, 2] + 2.3 * phase))  # fmt: skip
    cover = np.clip((wave - (1.0 - 2.0 * share)) / 0.12, 0.0, 1.0)
    return cover * (np.asarray(normals, dtype=float)[:, 1] > -0.3)


def _everywhere(points: np.ndarray, normals: np.ndarray) -> np.ndarray:
    return np.ones(len(points))


def dress_atmo(pieces: list[cv.Piece], look: Look) -> tuple[list[cv.Piece], dict[str, tuple[Marking, ...]]]:
    """The atmospheric shuttle's seams and paint: frames across the body, spars along the wings, the patchwork, then the look's
    bands, camouflage and tail colour."""
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

    names = [p.name for p in cv.with_twins(pieces)]
    marks: dict[str, list[Marking]] = {name: [] for name in names}
    for k, colour in enumerate(look.camo):
        cover = functools.partial(_blotches, phase=1.9 + 2.6 * k, share=0.42 - 0.16 * k)
        for name in ("body", "spine", "intake_r", "intake_l", "wing_r", "wing_l"):
            marks[name].append(Marking.paint(name, capture_albedo(colour), cover))
    for name in ("body", "spine", "intake_r", "intake_l"):
        marks[name] += _bands(name, look)
    if look.tail is not None:
        for name in ("fin", "tailplane"):
            marks[name].append(Marking.paint(name, capture_albedo(look.tail), _everywhere))
    if look.tail_marks is not None:
        mark = capture_albedo(look.tail_marks)
        for side in (1.0, -1.0):
            marks["fin"].append(Marking.rect("fin", (side * 0.11, 2.75, 19.3), sp.Z_AXIS, sp.Y_AXIS, (side, 0.0, 0.0), (1.9, 0.28), mark))
        for z in (23.0, 23.7):
            marks["tailplane"] += [Marking.rect("tailplane", (side * 6.6, 4.25, z), sp.X_AXIS, sp.Z_AXIS, sp.Y_AXIS, (0.9, 0.3), mark) for side in (1.0, -1.0)]
    return dressed, {name: tuple(m) for name, m in marks.items() if m}


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


SHUTTLE = Craft(SHUTTLE_ID, 0.12, ("bow", "cabin", "stern"), shuttle_looks, sp.assemble, dress_shuttle, sp.AXIS_Y,
                (("l", "left", "engine_l", 0.6), ("r", "right", "engine_r", 0.6)), 0.0, (1.5, sp.AXIS_Y, sp.HULL_STATIONS[0][0], 0.25),
                shuttle_ports, shuttle_lights, shuttle_joints)  # fmt: skip
ATMO = Craft(ATMO_ID, 0.16, ("body", "wing_l", "wing_r", "tail", "engines"), atmo_looks, ap.assemble, dress_atmo, ap.ENGINE_Y,
             (("l", "left", "engine_l", ap.ENGINE_EXIT_R), ("cl", "left", "engine_c", 0.5 * ap.ENGINE_EXIT_R),
              ("cr", "right", "engine_c", 0.5 * ap.ENGINE_EXIT_R), ("r", "right", "engine_r", ap.ENGINE_EXIT_R)), 0.3,
             (2.0, ap.EDGE_Y, 0.8, 0.3), atmo_ports, atmo_lights, atmo_joints)  # fmt: skip


def hardpoints(craft: Craft, pieces: list[cv.Piece], chunks: list[dict[str, Any]], offset: np.ndarray) -> dict[str, Any]:
    """The hardpoints document in the body frame (authored positions minus ``offset``); ``chunks`` are the ``write_chunks``
    entries. No turrets and no muzzles: the shuttles are unarmed."""
    parts = [p.part for p in cv.with_twins(pieces)]
    by_name = {p.name: p for p in parts}
    lo, hi = Mesh.concatenate(p.mesh for p in parts).bounds()
    length = float(hi[2] - lo[2])
    com = np.array([0.0, craft.thrust_y, float(mass_centroid(parts)[2])])  # on the thrust line, so main thrust makes no pitch torque

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
            "center": cv.r(engine.anchor("centre").position + shift - offset),
            "main": {"position": cv.r(main.position + shift - offset), "exhaust": cv.r(main.direction), "radius": round(radius, 3)},
            "retro": {"position": cv.r(retro - offset), "exhaust": [0.0, 0.0, -1.0], "radius": retro_r},
        })  # fmt: skip

    rcs = []
    for name, position, exhaust in craft.ports(by_name):
        p, e = np.asarray(position, dtype=float), np.asarray(exhaust, dtype=float)
        twins = [(name, p, e)] + ([("l_" + name[2:], p * FLIP, e * FLIP)] if name.startswith("r_") else [])
        for n, at, out in twins:
            rcs.append({"name": n, "pod": "l" if at[0] < -1e-6 else "r", "position": cv.r(at - offset), "exhaust": cv.r(out),
                        "tags": pilot_tags(at, out, com)})  # fmt: skip

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
        "cockpit_camera": {"position": cv.r(eye - offset), "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": cv.r((0.0, CHASE_ANCHOR_SHARE[0] * length, CHASE_ANCHOR_SHARE[1] * length))},
        "muzzles": [],
        "pods": pods,
        "rcs": rcs,
        "collision": cv.collision_json(parts, offset),
        "nav_lights": {
            "port": cv.r(lights["starboard"] * FLIP - offset),
            "starboard": cv.r(lights["starboard"] - offset),
            "top": cv.r(lights["top"] - offset),
            "top_lamp": cv.r(lights["top_lamp"] - offset),
            "top_lamp_range_m": round(NAV_LAMP_RANGE_SHARE * length, 2),
            "cabin": cv.r(eye - offset),
            "cabin_range_m": round(max(NAV_CABIN_RANGE_SHARE * length, 1.0), 2),
        },
        "turrets": [],
        "chunks": [{**c, "joint": cv.r(joints[c["name"]] - offset)} for c in chunks],
    }


# --- build -------------------------------------------------------------------------------------------------------------------
def build_craft(craft: Craft, ctx: BuildContext) -> AssetOutputs:
    """Generate one shuttle into ``ctx.out_dir``.

    Options: ``look`` (the surface option, ``a``, ``b`` or ``c``), ``spacing`` (m, the surface samples' spacing), ``atlas_px``
    (the hull's atlas, default 2 048), ``occlusion`` (default off).
    """
    spacing = float(ctx.option("spacing", craft.spacing_m))
    if spacing <= 0.0 or not math.isfinite(spacing):
        raise ValueError("spacing must be positive")
    looks = craft.looks()
    option = str(ctx.option("look", DEFAULT_OPTION))
    if option not in looks:
        raise ValueError(f"{craft.asset_id} has no look {option!r} (one of {sorted(looks)})")
    look = looks[option]
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{craft.asset_id} generator v{GENERATOR_VERSION} seed {ctx.seed}",)

    pieces, markings = craft.dress(craft.assemble(look.style), look)
    sampled = cv.sample_pieces(pieces, ctx, spacing, buried_margin=BURIED_MARGIN_M)
    offset = cv.centroid(sampled)
    hull = cv.write_hull(out_dir, craft.asset_id, cv.hull_parts(sampled, offset, markings), craft.chunk_order, look.style, ctx, comments)
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
            "look": look.name,
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(craft.asset_id, out_dir, manifest, tuple(files), ())


def build_shuttle(ctx: BuildContext) -> AssetOutputs:
    return build_craft(SHUTTLE, ctx)


def build_atmo(ctx: BuildContext) -> AssetOutputs:
    return build_craft(ATMO, ctx)
