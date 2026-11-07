"""``centauri_brezebel``: the Centauri Brezebel transport (M5-T15, D59; docs/assets-civilian.md and
docs/design-references.md, "Centauri Brezebel transport").

Composition only, like ``narn_transport``: parts from ``parts/centauri.py`` placed with the ``centauri`` style, and every
output (the textured mesh, fallback mesh, hardpoints, chunks, the turret model) derived from the placed parts so they
agree by construction.

Layout (authored Godot frame, metres, before re-centring; -Z is forward, the nose at z = 0, the arm tips at z = 60, x and
y centred on the reference model's box, the hull's centre plane at y = ``CENTRE_Y``):

* one lens hull, elliptical in every section: the round bow (widest, 39.1 m, at z 17) with a pale band round its rim,
  and two arms tapering straight aft from it to z 60, their inner walls 21.3 m apart;
* the engine bay against the bow's rear face between the arms: a machinery block, the twelve RCS blocks and the main
  engine's drum and nozzle reaching to z 31.4;
* the dorsal fitting on the bow's top with five windows across its raked front and the turret ring on its top;
* on each arm a fairing bulging above and below its root, the inner rail, the hooked tip fins above and below (gold
  caps, a light on each upper hook) and the main nozzle in the arm's flat tip face.

Every part belongs to a group (``CHUNK_ORDER``); the hull is one textured mesh (``core/civilian.py``; Godot's importer
builds its levels of detail) and each group a cut of it, the break-up chunks. The body origin is the visible surface's
centroid, exactly on the centre plane: right-hand parts are sampled once and mirrored, centre-line parts symmetrised,
surface buried inside another part left out. The turret (D61, Q19: one, on top) is its own small textured mesh.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

import numpy as np

from ..core import civilian as cv
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh
from ..core.manifest import build_manifest, write_manifest
from ..core.sampling import SurfaceSamples, sample_mesh
from ..parts import Part, mass_centroid, total_mass
from ..parts.centauri import (
    CENTRE,
    CENTRE_Y,
    RIGHT,
    BaySpec,
    CentauriTurretSpec,
    DorsalSpec,
    FairingSpec,
    FinSpec,
    LensSpec,
    Piece,
    RailSpec,
    RetroSpec,
    TipNozzleSpec,
    arm,
    bow,
    centauri_turret,
    dorsal_fitting,
    engine_bay,
    fairing,
    tip_fin,
)
from ..parts.propulsion import pilot_tags
from ..styles import Style
from ..styles.centauri import CENTAURI

ASSET_ID = "centauri_brezebel"
GENERATOR_VERSION = 2  # 2: textured meshes (M5-T27)
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"

DEFAULT_SPACING_M = 0.26  # the surface samples' spacing: the body origin and the chunks' offsets
CHUNK_ORDER = ("bow", "arm_l", "arm_r")

# The turret (D61, Q19): its own panel size and seam (the hull's plates are about its size); arc and barrel from
# docs/assets-civilian.md.
TURRET_STEM = f"{ASSET_ID}_turret"
TURRET_PANEL_M = (0.65, 0.06)
TURRET_ARC_DEG = 200.0  # a dorsal mount: a hemisphere plus 10 degrees below its base

BURIED_MARGIN_M = 0.03
JSON_DIGITS = 5
EYE = (0.0, 3.5, 2.5)  # behind the window row (authored frame)
CHASE_ANCHOR_SHARE = (0.3, 1.2)  # above and behind the centroid, in lengths
NAV_LIGHT_CLEARANCE_M = 0.15
NAV_LAMP_HEIGHT_M = 6.0
NAV_LAMP_RANGE_SHARE = 0.3
NAV_CABIN_RANGE_SHARE = 0.05


@dataclass(frozen=True)
class BrezebelSpec:
    lens: LensSpec = LensSpec()
    tip: TipNozzleSpec = TipNozzleSpec()
    retro: RetroSpec = RetroSpec()
    rail: RailSpec = RailSpec()
    fairing: FairingSpec = FairingSpec()
    fin: FinSpec = FinSpec()
    bay: BaySpec = BaySpec()
    dorsal: DorsalSpec = DorsalSpec()
    turret: CentauriTurretSpec = CentauriTurretSpec()


DEFAULT_SPEC = BrezebelSpec()


# --- assembly --------------------------------------------------------------------------------------------------------
def _grouped(pieces: list[Piece], group: str) -> list[Piece]:
    return [Piece(p.part.renamed(p.part.name, group=group), p.solid, p.side) for p in pieces]


def assemble(spec: BrezebelSpec, style: Style) -> list[Piece]:
    """Every centre and right piece of the ship in the authored frame, each in its chunk."""
    front = [bow(spec.lens, style), *engine_bay(spec.bay, style), *dorsal_fitting(spec.dorsal, style)]
    arm_r = [*arm(spec.lens, spec.tip, spec.retro, spec.rail, style), fairing(spec.fairing, style),
             tip_fin(spec.fin, style, upper=True), tip_fin(spec.fin, style, upper=False)]  # fmt: skip
    return _grouped(front, "bow") + _grouped(arm_r, "arm_r")


def _left(name: str) -> str:
    return name[:-2] + "_l"


def _mirror(p: Piece) -> Piece:
    """A right piece's left twin."""
    part = p.part.mirrored("x").renamed(_left(p.part.name), group="arm_l")
    return Piece(part, None if p.solid is None else p.solid.mirrored("x"), RIGHT)


def with_twins(pieces: list[Piece]) -> list[Piece]:
    """The pieces plus each right piece's left twin."""
    out = []
    for p in pieces:
        out.append(p)
        if p.side == RIGHT:
            out.append(_mirror(p))
    return out


# --- the visible surface --------------------------------------------------------------------------------------------------
@dataclass
class Sampled:
    part: Part
    samples: SurfaceSamples
    spacing: float
    paint_name: str  # the right twin's name: both twins get the same panel phase


def _right_half_first(mesh: Mesh) -> Mesh:
    """The same faces with the right half's first, so systematic rounding gives a centre piece's halves equal shares."""
    right = mesh.face_centroids()[:, 0] > 0.0
    order = np.concatenate([np.flatnonzero(right), np.flatnonzero(~right)])
    return Mesh(mesh.vertices, mesh.faces[order], mesh.face_material[order], mesh.materials)


def build_parts(style: Style, ctx: BuildContext, spacing: float, suffix: tuple[str, ...] = (),
                spec: BrezebelSpec = DEFAULT_SPEC) -> list[Sampled]:  # fmt: skip
    """Every piece's visible surface: hidden samples dropped, centre pieces symmetrised and right pieces mirrored, in
    placement order."""
    pieces = assemble(spec, style)
    solids = [(p.part.name, p.solid, p.solid.bounds()) for p in with_twins(pieces) if p.solid is not None]
    out: list[Sampled] = []
    for p in pieces:
        mesh = p.part.mesh if p.side == RIGHT else _right_half_first(p.part.mesh)
        s = sample_mesh(mesh, spacing, ctx.rng("surface", p.part.name, *suffix), systematic=True)
        if len(s):
            lo, hi = s.positions.min(axis=0), s.positions.max(axis=0)
            hidden = np.zeros(len(s), dtype=bool)
            for name, solid, (slo, shi) in solids:
                if name == p.part.name or np.any(shi < lo) or np.any(slo > hi):
                    continue
                hidden |= solid.contains(s.positions, BURIED_MARGIN_M)
            s = s.subset(~hidden)
        if p.side == CENTRE:
            out.append(Sampled(p.part, s.symmetrized("x"), spacing, p.part.name))
        else:
            out.append(Sampled(p.part, s, spacing, p.part.name))
            out.append(Sampled(_mirror(p).part, s.mirrored("x"), spacing, p.part.name))
    return out


def centre(sampled: list[Sampled]) -> np.ndarray:
    """The visible surface's centroid (x is zero by symmetry): the authored position of the body origin."""
    total = sum(len(s.samples) for s in sampled)
    mean = sum(s.samples.positions.sum(axis=0) for s in sampled) / total
    return np.array([0.0, float(mean[1]), float(mean[2])])


def hull_parts(sampled: list[Sampled], offset: np.ndarray) -> list[cv.HullPart]:
    """The sampled parts as the textured mesh takes them, in the body frame."""
    return [cv.HullPart(s.part.name, s.part.group, s.part.mesh.translated(-offset), s.samples.positions - offset, s.paint_name)
            for s in sampled]  # fmt: skip


# --- hardpoints --------------------------------------------------------------------------------------------------------
def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def rcs_ports(spec: BrezebelSpec, by_name: dict[str, Part]) -> list[tuple[str, np.ndarray, np.ndarray]]:
    """Cosmetic RCS ports of the right side (authored frame): the six bay blocks' outer faces (up or down), and each
    fin's port by its hook's tip (outboard)."""
    ports = []
    for name, centre_, size in spec.bay.rcs_blocks():
        up = 1.0 if centre_[1] > CENTRE_Y else -1.0
        ports.append((f"block_{name[4:]}", centre_ + np.array([0.0, up * 0.5 * size[1], 0.0]), np.array([0.0, up, 0.0])))
    for name in ("fin_top", "fin_bot"):
        port = by_name[f"{name}_r"].anchor("rcs")
        ports.append((name, port.position, port.direction))
    return ports


def chunk_joints(spec: BrezebelSpec, offset: np.ndarray) -> dict[str, list[float]]:
    """Where each chunk breaks away: an arm at its root on the bow's rear face, the bow between the two."""
    lens = spec.lens
    root = np.array([0.5 * (lens.inner_x + float(lens.half_width(lens.rear_z))), CENTRE_Y, lens.rear_z])
    joints = {"arm_r": root, "arm_l": root * np.array([-1.0, 1.0, 1.0]), "bow": np.array([0.0, CENTRE_Y, lens.rear_z])}
    return {name: _r(point - offset) for name, point in joints.items()}


def nav_lights(spec: BrezebelSpec, by_name: dict[str, Part], offset: np.ndarray, length: float) -> dict[str, Any]:
    """Running lights: red and green just past the bow's widest points, white on its top behind the fitting with a lamp
    standing over it, the cabin glow at the window row."""
    lens = spec.lens
    side = np.array([lens.plan_a + NAV_LIGHT_CLEARANCE_M, CENTRE_Y, lens.plan_b])
    top = np.array([0.0, float(lens.top(0.0, lens.plan_b)) + NAV_LIGHT_CLEARANCE_M, lens.plan_b])
    return {
        "port": _r(side * np.array([-1.0, 1.0, 1.0]) - offset),
        "starboard": _r(side - offset),
        "top": _r(top - offset),
        "top_lamp": _r(top + np.array([0.0, NAV_LAMP_HEIGHT_M, 0.0]) - offset),
        "top_lamp_range_m": round(NAV_LAMP_RANGE_SHARE * length, 2),
        "cabin": _r(by_name["dorsal"].anchor("windows").position - offset),
        "cabin_range_m": round(NAV_CABIN_RANGE_SHARE * length, 2),
    }


def hardpoints(spec: BrezebelSpec, style: Style, chunks: list[dict[str, Any]], offset: np.ndarray) -> dict[str, Any]:
    """The hardpoints document in the centred frame (authored positions minus ``offset``); ``chunks`` are the
    ``write_chunks`` entries."""
    parts = [p.part for p in with_twins(assemble(spec, style))]
    by_name = {p.name: p for p in parts}
    lo, hi = Mesh.concatenate(p.mesh for p in parts).bounds()
    length = float(hi[2] - lo[2])
    com = np.array([0.0, CENTRE_Y, float(mass_centroid(parts)[2])])  # on the thrust line: main thrust makes no pitch torque
    inertia = np.zeros(3)
    for part in parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array([d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2])

    pods = []
    for name, side in (("l", "left"), ("r", "right")):
        main, retro = by_name[f"arm_{name}"].anchor("main"), by_name[f"arm_{name}"].anchor("retro")
        pods.append({
            "name": name,
            "side": side,
            "center": _r(0.5 * (main.position + retro.position) - offset),
            "main": {"position": _r(main.position - offset), "exhaust": _r(main.direction), "radius": spec.tip.nozzle.exit_r},
            "retro": {"position": _r(retro.position - offset), "exhaust": _r(retro.direction), "radius": spec.retro.radius},
        })  # fmt: skip

    rcs = []
    for prefix, flip in (("r", 1.0), ("l", -1.0)):
        for name, position, exhaust in rcs_ports(spec, by_name):
            p = position * np.array([flip, 1.0, 1.0])
            e = exhaust * np.array([flip, 1.0, 1.0])
            rcs.append({"name": f"{prefix}_{name}", "pod": prefix, "position": _r(p - offset), "exhaust": _r(e),
                        "tags": pilot_tags(p, e, com)})  # fmt: skip

    collision = []
    for part in parts:
        for shape in part.collision:
            collision.append({**shape.to_json(offset=offset, digits=JSON_DIGITS),
                              "name": f"{part.name}_{shape.name}" if shape.name else part.name})  # fmt: skip

    mount = by_name["dorsal"].anchor("turret")
    turrets = [{"name": "dorsal", "position": _r(mount.position - offset), "up": _r(mount.direction),
                "arc_deg": TURRET_ARC_DEG, "barrel_m": spec.turret.barrel_m}]  # fmt: skip

    joints = chunk_joints(spec, offset)
    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(length, 3),
        "span_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "mass_kg": round(total_mass(parts), 1),
        "inertia_estimate_kg_m2": _r(inertia),
        "center_of_mass": _r(com - offset),
        "cockpit_camera": {"position": _r(np.array(EYE) - offset), "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": _r((0.0, CHASE_ANCHOR_SHARE[0] * length, CHASE_ANCHOR_SHARE[1] * length))},
        "muzzles": [],
        "pods": pods,
        "rcs": rcs,
        "collision": collision,
        "nav_lights": nav_lights(spec, by_name, offset, length),
        "turrets": turrets,
        "chunks": [{**c, "joint": joints[c["name"]]} for c in chunks],
    }


# --- build -------------------------------------------------------------------------------------------------------------
def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the ship and its turret into ``ctx.out_dir``.

    Options: ``spacing`` (m, default 0.26; the surface samples' spacing), ``atlas_px`` (the hull's atlas, default 2 048),
    ``model_atlas_px`` (the turret's, default 1 024), ``occlusion`` (default off).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    if spacing <= 0.0:
        raise ValueError("spacing must be positive")
    spec, style = DEFAULT_SPEC, CENTAURI
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}",)

    sampled = build_parts(style, ctx, spacing, spec=spec)
    offset = centre(sampled)
    hull = cv.write_hull(out_dir, ASSET_ID, hull_parts(sampled, offset), CHUNK_ORDER, style, ctx, comments)
    files: list[Path] = list(hull.files)

    turret_part = centauri_turret(spec.turret, style)
    fine = replace(style, panel_size_m=TURRET_PANEL_M[0], panel_line_width_m=TURRET_PANEL_M[1])
    turret_files, section = cv.write_model(out_dir, TURRET_STEM, [(turret_part.name, turret_part.mesh)], fine, ctx, comments + ("turret",))
    files += turret_files
    turret_entry = cv.turret_entry(TURRET_STEM, turret_part, spec.turret.barrel_m, section)

    hp = hardpoints(spec, style, hull.chunks, offset)
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
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), ())
