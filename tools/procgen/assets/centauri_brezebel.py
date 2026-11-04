"""``centauri_brezebel``: the Centauri Brezebel transport (M5-T15, D59; docs/assets-civilian.md and
docs/design-references.md, "Centauri Brezebel transport").

Composition only, like ``narn_transport``: parts from ``parts/centauri.py`` placed with the ``centauri`` style, and every
output (splats, fallback mesh, hardpoints, chunks, the turret model) derived from the placed parts so they agree by
construction.

Layout (authored Godot frame, metres, before re-centring; -Z is forward, the nose at z = 0, the arm tips at z = 60, x and
y centred on the reference model's box, the hull's centre plane at y = ``CENTRE_Y``):

* one lens hull, elliptical in every section: the round bow (widest, 39.1 m, at z 17) with a pale band round its rim,
  and two arms tapering straight aft from it to z 60, their inner walls 21.3 m apart;
* the engine bay against the bow's rear face between the arms: a machinery block, the twelve RCS blocks and the main
  engine's drum and nozzle reaching to z 31.4;
* the dorsal fitting on the bow's top with five windows across its raked front and the turret ring on its top;
* on each arm a fairing bulging above and below its root, the inner rail, the hooked tip fins above and below (gold
  caps, a light on each upper hook) and the main nozzle in the arm's flat tip face.

Every part belongs to a group (``CHUNK_ORDER``). LOD0 is written group by group (``manifest.counts``), LOD1 chunk by chunk
and its chunks are the break-up chunks (``chunk_lod`` 1); LOD2 and LOD3 are whole-ship files. The sample set is exactly
mirror-symmetric in x: right-hand parts are sampled once and mirrored, centre-line parts symmetrised. Samples buried
inside another part are dropped. The turret (D61, Q19: one, on top) is its own small model written like a chunk.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ..core import frames, lighting
from ..core import civilian as cv
from ..core.chunks import ChunkSource, write_chunks
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh
from ..core.manifest import build_manifest, lod_entry, write_manifest
from ..core.obj import write_obj
from ..core.ply import SplatData, write_ply
from ..core.sampling import DEFAULT_OVERLAP, DEFAULT_THICKNESS, SurfaceSamples, sample_mesh, to_splats
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
GENERATOR_VERSION = 1
PLY_NAME = f"{ASSET_ID}.ply"
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"

# docs/assets-civilian.md: LOD0 70 000 (55 000 to 85 000) from a 0.34 m start; the generated surface is smaller than the
# reference's (no inner faces), so the spacing is tuned to land near the target.
DEFAULT_SPACING_M = 0.26
SPLAT_BUDGET = (55_000, 85_000)
# The levels for the LOD switcher, at 2x, 4x and 8x the spacing, from their own RNG streams; LOD1's chunks break up.
LODS = {
    1: (f"{ASSET_ID}_lod1.ply", 2.0, "lod1", (0.20, 0.30)),  # level: file, spacing factor, stream, share of LOD0
    2: (f"{ASSET_ID}_lod2.ply", 4.0, "lod2", (0.04, 0.09)),
    3: (f"{ASSET_ID}_lod3.ply", 8.0, "lod3", (0.01, 0.025)),
}
CHUNK_LOD = 1
CHUNK_ORDER = ("bow", "arm_l", "arm_r")
LOD_AABB_SPACINGS = 1.25  # a coarse level's box matches LOD0's within this many of its spacings (test_splat_import.gd)

# The turret (D61, Q19): sampled finer than the hull, about 2 000 splats; arc and barrel from docs/assets-civilian.md.
TURRET_PLY_NAME = f"{ASSET_ID}_turret.ply"
TURRET_OBJ_NAME = f"{ASSET_ID}_turret.obj"
TURRET_LIGHT_NAME = f"{ASSET_ID}_turret{lighting.SUFFIX}"
TURRET_SPACING_M = 0.11
TURRET_SPLATS = (1_500, 2_600)
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


# --- sampling, colour --------------------------------------------------------------------------------------------------
@dataclass
class Sampled:
    part: Part
    samples: SurfaceSamples
    spacing: float
    paint_name: str  # the right twin's name: both twins get the same panel pattern


def _right_half_first(mesh: Mesh) -> Mesh:
    """The same faces with the right half's first, so systematic rounding gives a centre piece's halves equal shares and a
    coarse level keeps LOD0's centroid."""
    right = mesh.face_centroids()[:, 0] > 0.0
    order = np.concatenate([np.flatnonzero(right), np.flatnonzero(~right)])
    return Mesh(mesh.vertices, mesh.faces[order], mesh.face_material[order], mesh.materials)


def build_parts(style: Style, ctx: BuildContext, spacing: float, suffix: tuple[str, ...] = (),
                spec: BrezebelSpec = DEFAULT_SPEC) -> list[Sampled]:  # fmt: skip
    """Every piece sampled, the hidden samples dropped, centre pieces symmetrised and right pieces mirrored, in placement
    order. ``suffix`` keeps another LOD's random draws apart from LOD0's."""
    pieces = assemble(spec, style)
    solids = [(p.part.name, p.solid, p.solid.bounds()) for p in with_twins(pieces) if p.solid is not None]
    out: list[Sampled] = []
    for p in pieces:
        mesh = p.part.mesh if p.side == RIGHT else _right_half_first(p.part.mesh)
        s = sample_mesh(mesh, spacing, ctx.rng("splats", p.part.name, *suffix), systematic=True)
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
    """The splat centroid (x is zero by symmetry): the authored position of the body origin."""
    total = sum(len(s.samples) for s in sampled)
    mean = sum(s.samples.positions.sum(axis=0) for s in sampled) / total
    return np.array([0.0, float(mean[1]), float(mean[2])])


def _phase(name: str, style: Style) -> tuple[float, float, float]:
    h = sum((i + 1) * ord(c) for i, c in enumerate(name))
    return tuple(((h * k) % 97) / 97.0 * style.panel_size_m for k in (7, 11, 13))


def colour_samples(s: Sampled, style: Style) -> np.ndarray:
    """Paint only (paint, panel lines mirrored across the centre line, tint): the scene's lights shade it in the game."""
    at = s.samples.positions.copy()
    at[:, 0] = np.abs(at[:, 0])
    paneled = s.samples.material_flag("paneled") > 0.5
    return style.shade_panels(s.samples.albedo(), at, s.samples.normals, paneled, _phase(s.paint_name, style))


def group_splats(sampled: list[Sampled], style: Style, offset: np.ndarray, overlap: float, thickness: float) -> list[ChunkSource]:
    """One source per ``CHUNK_ORDER`` group: its splats and fallback mesh in the centred frame."""
    sources = []
    for group in CHUNK_ORDER:
        members = [s for s in sampled if s.part.group == group]
        splats = SplatData.concatenate(
            [to_splats(s.samples.translated(-offset), colour_samples(s, style), s.spacing, overlap, thickness) for s in members]
        )
        sources.append(ChunkSource(group, splats, Mesh.concatenate(s.part.mesh.translated(-offset) for s in members)))
    return sources


def _to_3dgs(splats: SplatData) -> SplatData:
    """Rz(180 deg) of the Godot frame: what the PLY stores, so the splat node stays at identity."""
    return SplatData(
        xyz=frames.godot_to_3dgs_positions(splats.xyz), rgb=splats.rgb, alpha=splats.alpha, scale=splats.scale,
        rot=frames.godot_to_3dgs_quats(splats.rot), normals=frames.flip_xy(splats.normals),
    )  # fmt: skip


def _write_level(out_dir: Path, ply_name: str, light_name: str, splats: SplatData, comments: tuple[str, ...]) -> list[Path]:
    written = _to_3dgs(splats)
    return [write_ply(out_dir / ply_name, written, comments), lighting.write_lighting(out_dir / light_name, written)]


# --- the turret --------------------------------------------------------------------------------------------------------
def turret_splats(spec: CentauriTurretSpec, style: Style, ctx: BuildContext, spacing: float, overlap: float,
                  thickness: float) -> tuple[Part, SplatData]:  # fmt: skip
    """The turret model and its splats in the turret's own frame (pivot at the origin, +Y up, barrels along -Z)."""
    part = centauri_turret(spec, style)
    s = sample_mesh(_right_half_first(part.mesh), spacing, ctx.rng("splats", "turret"), systematic=True)
    hidden = np.zeros(len(s), dtype=bool)
    for solid in spec.solids():
        hidden |= solid.contains(s.positions, BURIED_MARGIN_M)
    sampled = Sampled(part, s.subset(~hidden).symmetrized("x"), spacing, "turret")
    return part, to_splats(sampled.samples, colour_samples(sampled, style), spacing, overlap, thickness)


def write_turret(out_dir: Path, part: Part, splats: SplatData, spacing: float, barrel_m: float,
                 comments: tuple[str, ...]) -> tuple[list[Path], dict[str, Any]]:  # fmt: skip
    """The turret written like a chunk: PLY and records centred on its own splat centroid, the fallback mesh with them.
    The manifest entry has the keys of ``parts/turret.py``'s; ``offset`` is that centroid in the turret's frame."""
    centroid = splats.xyz.mean(axis=0)
    centred = SplatData(splats.xyz - centroid, splats.rgb, splats.alpha, splats.scale, splats.rot, splats.normals)
    files = _write_level(out_dir, TURRET_PLY_NAME, TURRET_LIGHT_NAME, centred, comments + ("turret",))
    files += write_obj(out_dir / TURRET_OBJ_NAME, part.mesh.translated(-centroid), f"{ASSET_ID}_turret", comments[:1])
    entry = {
        "ply": TURRET_PLY_NAME,
        "lighting": TURRET_LIGHT_NAME,
        "obj": TURRET_OBJ_NAME,
        "splats": len(splats),
        "spacing_m": spacing,
        "offset": _r(centroid),
        "barrel_m": round(barrel_m, JSON_DIGITS),
        "trunnion": _r(part.anchor("trunnion").position),
        "muzzles": [_r(part.anchor("muzzle_l").position), _r(part.anchor("muzzle_r").position)],
    }
    return files, entry


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
    ``write_chunks`` entries (from LOD1)."""
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

    Options: ``spacing`` (m, default 0.26; the CLI's ``--spacing``), ``overlap`` (sigma / spacing, default 1.0),
    ``thickness`` (normal sigma / spacing, default 0.08), ``turret_spacing`` (m, default 0.11).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    overlap = float(ctx.option("overlap", DEFAULT_OVERLAP))
    thickness = float(ctx.option("thickness", DEFAULT_THICKNESS))
    turret_spacing = float(ctx.option("turret_spacing", TURRET_SPACING_M))
    if min(spacing, overlap, thickness, turret_spacing) <= 0.0:
        raise ValueError("spacing, overlap, thickness and turret_spacing must be positive")
    spec, style = DEFAULT_SPEC, CENTAURI
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}", "frame: 3dgs (Rz180 of godot)")
    light = {level: lighting.lod_file_name(ASSET_ID, level) for level in (0, *LODS)}

    # LOD0: the full-detail hull, group by group (manifest ``counts`` order).
    lod0 = build_parts(style, ctx, spacing, spec=spec)
    offset = centre(lod0)
    groups = group_splats(lod0, style, offset, overlap, thickness)
    authored = SplatData.concatenate([g.splats for g in groups])
    xyz32 = authored.xyz.astype(np.float32)
    aabb_min, aabb_max = xyz32.min(axis=0), xyz32.max(axis=0)
    files: list[Path] = _write_level(out_dir, PLY_NAME, light[0], authored, comments)
    files += write_obj(out_dir / OBJ_NAME, Mesh.concatenate(g.mesh for g in groups), ASSET_ID, comments[:1])
    # The painted mesh: the ship as the game draws it from the 2026-11-04 directive (meshes, not splats).
    mesh_path, mesh_entry = cv.write_mesh(out_dir, ASSET_ID, [(s.paint_name, s.part.mesh.translated(-offset)) for s in lod0], style)
    files.append(mesh_path)

    # LOD1 to LOD3: resampled coarser from their own streams, each centred on its own centroid; LOD1's groups are the chunks.
    counts: dict[int, int] = {}
    chunk_entries: list[dict[str, Any]] = []
    for level, (name, factor, stream, _share) in LODS.items():
        sampled = build_parts(style, ctx, factor * spacing, (stream,), spec)
        lod_groups = group_splats(sampled, style, centre(sampled), overlap, thickness)
        lod = SplatData.concatenate([g.splats for g in lod_groups])
        counts[level] = len(lod)
        level_comments = comments + (f"lod {level}",)
        files += _write_level(out_dir, name, light[level], lod, level_comments)
        if level == CHUNK_LOD:
            chunk_files, chunk_entries = write_chunks(out_dir, ASSET_ID, lod_groups, level_comments)
            files += chunk_files

    turret_part, turret = turret_splats(spec.turret, style, ctx, turret_spacing, overlap, thickness)
    turret_files, turret_entry = write_turret(out_dir, turret_part, turret, turret_spacing, spec.turret.barrel_m, comments)
    files += turret_files
    named = [("turret", turret_part.mesh.translated(-turret.xyz.mean(axis=0)))]  # the turret files' frame
    mesh_path, turret_entry["paint_mesh"] = cv.write_mesh(out_dir, f"{ASSET_ID}_turret", named, style)
    files.append(mesh_path)

    hp = hardpoints(spec, style, chunk_entries, offset)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    total = len(authored)
    warnings: list[str] = []
    if abs(spacing - DEFAULT_SPACING_M) < 1e-12:
        if not SPLAT_BUDGET[0] <= total <= SPLAT_BUDGET[1]:
            warnings.append(f"{total} splats is outside the budget {SPLAT_BUDGET} at the default spacing")
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
        files={"fallback_mesh": OBJ_NAME, "paint_mesh": mesh_entry["file"], "hardpoints": HARDPOINTS_NAME},
        extra={
            "paint_mesh": mesh_entry,
            "counts": {g.name: len(g.splats) for g in groups},
            "chunks": [c["name"] for c in chunk_entries],
            "chunk_lod": CHUNK_LOD,
            "sampling": {"spacing_m": spacing, "overlap": overlap, "thickness": thickness, "turret_spacing_m": turret_spacing},
            "dimensions_m": {"length": hp["length_m"], "span": hp["span_m"], "height": hp["height_m"]},
            "turret": turret_entry,
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), tuple(warnings))
