"""``narn_transport``: the Narn freighter (M5-T14, D59; docs/assets-civilian.md and docs/design-references.md, "Narn
transport").

Composition only, like ``raider_fighter``: parts from ``parts/narn.py`` placed with the ``narn`` style, and every output
(splats, fallback mesh, hardpoints, chunks, the turret model) derived from the placed parts so they agree by construction.

Layout (authored Godot frame, metres, before re-centring; -Z is forward, the prong tips at z = 0, the box's aft face at
z = 70, y = 0 the crescent's centre plane; the design references' measurements):

* a flat crescent 46 m across, 7.8 m thick on the centre line and thinning to a beveled edge at the rim, two thinner
  prongs reaching forward round a notch, a red band on each half's top;
* the cockpit in the notch (z 2.8 to 15.8): a hexagonal nose with a framed canopy on its flat top and a windscreen block
  behind it; the dorsal block on the crescent and the bar running aft from it into the box;
* two upright fins at x +-17.1 and, inboard of them, the flank towers with three bent vanes in front, a slotted crown
  (the turret mounts) and the main nozzles on their aft faces, on a thrust line 5 m above the centre plane;
* the light grey cargo box (25.5 x 14 m, z 31.2 to 70) with a wedge front, the aft lower edge cut back, a green panel and
  hazard checkers on each side and two vent grilles on top.

Every part belongs to a group (``CHUNK_ORDER``). LOD0 is written group by group (``manifest.counts``), LOD1 chunk by chunk
and its chunks are the break-up chunks (``chunk_lod`` 1, as the Starfury); LOD2 and LOD3 are whole-ship files. The sample
set is exactly mirror-symmetric in x: right-hand parts are sampled once and mirrored, centre-line parts symmetrised.
Samples buried inside another part are dropped. The turret (D61) is its own small model written like a chunk.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, replace
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
from ..parts.narn import (
    CargoBoxSpec,
    CrescentSpec,
    DorsalSpec,
    FinSpec,
    NarnCockpitSpec,
    NarnTurretSpec,
    TowerSpec,
    box_grilles,
    cargo_box,
    crescent_centre,
    crescent_half,
    dorsal,
    fin,
    flank_tower,
    narn_cockpit,
    narn_turret,
)
from ..parts.propulsion import pilot_tags
from ..styles import Style
from ..styles.narn import NARN

ASSET_ID = "narn_transport"
GENERATOR_VERSION = 1
PLY_NAME = f"{ASSET_ID}.ply"
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"

# docs/assets-civilian.md: LOD0 75 000 (60 000 to 90 000) from a 0.35 m start; the generated surface is smaller than the
# reference's (no inner faces), so the spacing is tuned to land near the target.
DEFAULT_SPACING_M = 0.31
SPLAT_BUDGET = (60_000, 90_000)
# The levels for the LOD switcher, at 2x, 4x and 8x the spacing, from their own RNG streams; LOD1's chunks break up.
LODS = {
    1: (f"{ASSET_ID}_lod1.ply", 2.0, "lod1", (0.20, 0.30)),  # level: file, spacing factor, stream, share of LOD0
    2: (f"{ASSET_ID}_lod2.ply", 4.0, "lod2", (0.04, 0.09)),
    3: (f"{ASSET_ID}_lod3.ply", 8.0, "lod3", (0.01, 0.025)),
}
CHUNK_LOD = 1
CHUNK_ORDER = ("cockpit", "wing_l", "wing_r", "box")

# The turret (D61): sampled finer than the hull, about 2 000 splats; arcs and barrel length from docs/assets-civilian.md.
TURRET_PLY_NAME = f"{ASSET_ID}_turret.ply"
TURRET_OBJ_NAME = f"{ASSET_ID}_turret.obj"
TURRET_LIGHT_NAME = f"{ASSET_ID}_turret{lighting.SUFFIX}"
TURRET_SPACING_M = 0.11
TURRET_PANEL_M = (0.65, 0.06)  # the turret's own panel grid and line width: the hull's 2.4 m grid is about its size
TURRET_SPLATS = (1_500, 2_600)
TURRET_ARC_DEG = 220.0  # the tower tops: a hemisphere and then some, to fire down past the crescent's edge

BURIED_MARGIN_M = 0.05
JSON_DIGITS = 5
EYE = (0.0, 1.2, 11.3)  # inside the windscreen block, looking out over the canopy (authored frame)
CHASE_ANCHOR_SHARE = (0.3, 1.2)  # above and behind the centroid, in lengths
NAV_LIGHT_CLEARANCE_M = 0.15
NAV_SIDE = (23.0, 0.0, 27.0)  # the crescent's widest point, right side
NAV_TOP_Z = 50.0  # the white light on the box's top, the highest point on the centre line
NAV_LAMP_HEIGHT_M = 7.0
NAV_LAMP_RANGE_SHARE = 0.3
NAV_CABIN_RANGE_SHARE = 0.05


@dataclass(frozen=True)
class NarnSpec:
    crescent: CrescentSpec = CrescentSpec()
    cockpit: NarnCockpitSpec = NarnCockpitSpec()
    dorsal: DorsalSpec = DorsalSpec()
    fin: FinSpec = FinSpec()
    tower: TowerSpec = TowerSpec()
    box: CargoBoxSpec = CargoBoxSpec()
    turret: NarnTurretSpec = NarnTurretSpec()


DEFAULT_SPEC = NarnSpec()


@dataclass
class Placed:
    """A placed part with its surface samples (``None`` for meshes that are not splatted)."""

    part: Part
    samples: SurfaceSamples | None
    spacing: float = 0.0
    hull: bool = True

    def translated(self, offset: np.ndarray) -> Placed:
        return Placed(self.part.translated(offset), None if self.samples is None else self.samples.translated(offset), self.spacing, self.hull)

    def mirrored(self, name: str, group: str) -> Placed:
        return Placed(
            self.part.mirrored("x").renamed(name, group=group),
            None if self.samples is None else self.samples.mirrored("x"),
            self.spacing,
            self.hull,
        )


def _unburied(samples: SurfaceSamples, solids: tuple[Any, ...], extra: np.ndarray | None = None) -> SurfaceSamples:
    """The samples not hidden inside any of ``solids`` (nor flagged by ``extra``)."""
    buried = np.zeros(len(samples), dtype=bool) if extra is None else np.asarray(extra, dtype=bool).copy()
    for solid in solids:
        buried |= solid.contains(samples.positions, BURIED_MARGIN_M)
    return samples.subset(~buried)


def _under_grilles(spec: CargoBoxSpec, samples: SurfaceSamples) -> np.ndarray:
    """The box's top samples under a grille's plate."""
    p = samples.positions
    covered = np.zeros(len(p), dtype=bool)
    for x0, x1, z0, z1 in spec.grille_footprints():
        covered |= (p[:, 0] > x0) & (p[:, 0] < x1) & (p[:, 2] > z0) & (p[:, 2] < z1)
    return covered & (p[:, 1] > spec.top_y - 0.05)


def build_parts(
    spec: NarnSpec, style: Style, ctx: BuildContext, spacing: float, stream_suffix: tuple[str, ...] = (), systematic: bool = False
) -> list[Placed]:
    """Every part in the authored frame, sampled, with the hidden samples dropped; right-hand groups mirrored to the left.
    ``stream_suffix`` keeps another LOD's random draws apart from LOD0's; ``systematic`` as ``sample_mesh``'s."""

    def sample(mesh: Mesh, stream: str) -> SurfaceSamples:
        return sample_mesh(mesh, spacing, ctx.rng("splats", stream, *stream_suffix), systematic=systematic)

    crescent = spec.crescent
    cockpit_body, hump = spec.cockpit.body_solid(), spec.cockpit.hump.solid()
    block, rod = spec.dorsal.block.solid(), spec.dorsal.rod_solid()
    fin_body, tower_body, box_body = spec.fin.solid(), spec.tower.body.solid(), spec.box.solid()

    def place(part: Part, group: str, buried_by: tuple[Any, ...], symmetric: bool = False, extra=None) -> Placed:
        part = part.renamed(part.name, group=group)
        samples = sample(part.mesh, part.name)
        samples = _unburied(samples, buried_by, None if extra is None else extra(samples))
        return Placed(part, samples.symmetrized("x") if symmetric else samples, spacing)

    placed = [
        place(crescent_centre(crescent, style), "cockpit", (cockpit_body, hump, block, rod, box_body), symmetric=True),
        place(narn_cockpit(spec.cockpit, style), "cockpit", (crescent, cockpit_body, hump), symmetric=True),
        place(dorsal(spec.dorsal, style), "cockpit", (crescent, block, rod, box_body), symmetric=True),
    ]
    right = [
        place(crescent_half(crescent, style), "wing_r", (box_body, fin_body, tower_body)),
        place(fin(spec.fin, style), "wing_r", (crescent, tower_body)),
        place(flank_tower(spec.tower, style), "wing_r", (crescent, fin_body, tower_body)),
    ]
    placed += [p.mirrored(p.part.name[:-2] + "_l", "wing_l") for p in right] + right
    placed += [
        place(cargo_box(spec.box, style), "box", (crescent, block, rod), symmetric=True, extra=lambda s: _under_grilles(spec.box, s)),
        place(box_grilles(spec.box, style), "box", (box_body,), symmetric=True),
    ]
    return placed


# --- centring, colour ------------------------------------------------------------------------------------------------
def centre(placed: list[Placed]) -> tuple[list[Placed], np.ndarray]:
    """Moves the splat centroid to the origin. x is zero by symmetry; the offset (Godot frame) is the authored position
    of the new origin (``manifest.centroid_offset``)."""
    sampled = [p.samples for p in placed if p.samples is not None]
    total = sum(len(s) for s in sampled)
    mean = sum(s.positions.sum(axis=0) for s in sampled) / total
    offset = np.array([0.0, float(mean[1]), float(mean[2])])
    return [p.translated(-offset) for p in placed], offset


def level_parts(spec: NarnSpec, style: Style, ctx: BuildContext, spacing: float, level: int) -> tuple[list[Placed], np.ndarray]:
    """A coarse level's parts (LOD1 to LOD3) and its centroid offset: resampled from the level's own streams, and
    systematically, so its centroid stays on LOD0's (every level is drawn in LOD0's frame)."""
    _name, factor, stream, _share = LODS[level]
    return centre(build_parts(spec, style, ctx, factor * spacing, (stream,), systematic=True))


def _phase(name: str, style: Style) -> tuple[float, float, float]:
    h = sum((i + 1) * ord(c) for i, c in enumerate(name))
    return tuple(((h * k) % 97) / 97.0 * style.panel_size_m for k in (7, 11, 13))


def colour_samples(placed: Placed, style: Style) -> np.ndarray:
    """Paint only (paint, panel lines, tint): the scene's lights do the shading in the game."""
    s = placed.samples
    return style.shade_panels(s.albedo(), s.positions, s.normals, s.material_flag("paneled") > 0.5, _phase(placed.part.name, style))


def group_splats(placed: list[Placed], style: Style, overlap: float, thickness: float) -> list[ChunkSource]:
    """One source per ``CHUNK_ORDER`` group: its splats (placement order) and its fallback mesh."""
    sources = []
    for group in CHUNK_ORDER:
        members = [p for p in placed if p.part.group == group]
        splats = SplatData.concatenate(
            [to_splats(p.samples, colour_samples(p, style), p.spacing, overlap, thickness) for p in members if p.samples is not None]
        )
        sources.append(ChunkSource(group, splats, Mesh.concatenate(p.part.mesh for p in members if p.hull)))
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
def turret_splats(spec: NarnTurretSpec, style: Style, ctx: BuildContext, spacing: float, overlap: float, thickness: float) -> tuple[Part, SplatData]:
    """The turret model and its splats in the turret's own frame (pivot at the origin, +Y up, barrels along -Z)."""
    part = narn_turret(spec, style)
    samples = _unburied(sample_mesh(part.mesh, spacing, ctx.rng("splats", "turret")), tuple(spec.solids())).symmetrized("x")
    fine = replace(style, panel_size_m=TURRET_PANEL_M[0], panel_line_width_m=TURRET_PANEL_M[1])
    return part, to_splats(samples, colour_samples(Placed(part, samples, spacing), fine), spacing, overlap, thickness)


def write_turret(
    out_dir: Path, part: Part, splats: SplatData, spacing: float, barrel_m: float, comments: tuple[str, ...]
) -> tuple[list[Path], dict[str, Any]]:
    """The turret written like a chunk: PLY and records centred on its own splat centroid, the fallback mesh with them.
    The manifest entry has the keys of ``parts/turret.py``'s: ``offset`` is that centroid in the turret's frame (where the
    game puts the model relative to the mount), ``trunnion`` and ``muzzles`` (left, right) are in the same frame."""
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


def rcs_ports(spec: NarnSpec) -> list[tuple[str, tuple[float, float, float], tuple[float, float, float]]]:
    """Cosmetic RCS ports of the right side (authored frame): the prong tip forward and outboard, the fin tips up and
    down, the box's aft corner up, outboard and down."""
    c, f, b = spec.crescent, spec.fin, spec.box
    tip_x = c.outer[0][1]
    out_z = 2.0
    corner_x = b.chamfer_x - 0.2
    return [
        ("prong_fwd", (tip_x + 0.2, 0.0, 0.3), (0.0, 0.0, -1.0)),
        ("prong_out", (float(c.half_width(out_z)), 0.0, out_z), (1.0, 0.0, 0.0)),
        ("fin_up", (f.x, f.outline[1][1], 33.0), (0.0, 1.0, 0.0)),
        ("fin_down", (f.x, f.outline[-1][1], 33.0), (0.0, -1.0, 0.0)),
        ("box_aft_up", (corner_x, b.top_y, b.rear_chamfer_z - 0.2), (0.0, 1.0, 0.0)),
        ("box_aft_out", (b.half_width, 2.0, b.rear_z - 0.5), (1.0, 0.0, 0.0)),
        ("box_aft_down", (corner_x, b.bottom_y, b.aft_cut_z - 0.4), (0.0, -1.0, 0.0)),
    ]


def chunk_joints(spec: NarnSpec, offset: np.ndarray) -> dict[str, list[float]]:
    """Where each chunk detaches: a wing along its seam with the crescent's centre, the box where it hangs under the
    centre, the cockpit chunk (the crescent's centre) at the middle of the three."""
    c, b = spec.crescent, spec.box
    wing = np.array([c.seam_x, 0.0, 0.5 * (c.notch_back_z + c.seam_end_z)])
    joints = {
        "wing_r": wing,
        "wing_l": wing * np.array([-1.0, 1.0, 1.0]),
        "box": np.array([0.0, 0.0, 0.5 * (b.front_z + c.rear_z)]),
    }
    joints["cockpit"] = np.mean(list(joints.values()), axis=0)
    return {name: _r(point - offset) for name, point in joints.items()}


def nav_lights(spec: NarnSpec, by_name: dict[str, Part], offset: np.ndarray, length: float) -> dict[str, Any]:
    """Running lights: red and green just past the crescent's widest points, white on the box's top, a lamp standing over it,
    the cabin glow at the windscreen."""
    side = np.array(NAV_SIDE) + np.array([NAV_LIGHT_CLEARANCE_M, 0.0, 0.0])
    top_y = spec.box.top_y
    return {
        "port": _r(side * np.array([-1.0, 1.0, 1.0]) - offset),
        "starboard": _r(side - offset),
        "top": _r(np.array([0.0, top_y + NAV_LIGHT_CLEARANCE_M, NAV_TOP_Z]) - offset),
        "top_lamp": _r(np.array([0.0, top_y + NAV_LAMP_HEIGHT_M, NAV_TOP_Z]) - offset),
        "top_lamp_range_m": round(NAV_LAMP_RANGE_SHARE * length, 2),
        "cabin": _r(by_name["cockpit"].anchor("windscreen").position),
        "cabin_range_m": round(NAV_CABIN_RANGE_SHARE * length, 2),
    }


def hardpoints(placed: list[Placed], spec: NarnSpec, chunks: list[dict[str, Any]], offset: np.ndarray) -> dict[str, Any]:
    """The hardpoints document (centred Godot frame) from the placed (already centred) LOD0 parts; ``chunks`` are the
    ``write_chunks`` entries (from LOD1)."""
    by_name = {p.part.name: p.part for p in placed}
    hull_parts = [p.part for p in placed if p.hull]
    lo, hi = Mesh.concatenate(p.mesh for p in hull_parts).bounds()
    length = float(hi[2] - lo[2])

    thrust_y = spec.tower.thrust[1] - float(offset[1])
    com = np.array([0.0, thrust_y, float(mass_centroid(hull_parts)[2])])  # on the thrust line: main thrust makes no pitch torque
    inertia = np.zeros(3)
    for part in hull_parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array([d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2])

    pods = []
    for name, side in (("l", "left"), ("r", "right")):
        tower = by_name[f"tower_{name}"]
        main, retro = tower.anchor("main"), tower.anchor("retro")
        pods.append({
            "name": name,
            "side": side,
            "center": _r(tower.anchor("centre").position),
            "main": {"position": _r(main.position), "exhaust": _r(main.direction), "radius": spec.tower.nozzle.exit_r},
            "retro": {"position": _r(retro.position), "exhaust": _r(retro.direction), "radius": spec.tower.retro_radius},
        })  # fmt: skip

    rcs = []
    for prefix, flip in (("r", 1.0), ("l", -1.0)):
        for name, position, exhaust in rcs_ports(spec):
            p = np.array(position) * np.array([flip, 1.0, 1.0]) - offset
            e = np.array(exhaust) * np.array([flip, 1.0, 1.0])
            rcs.append({"name": f"{prefix}_{name}", "pod": prefix, "position": _r(p), "exhaust": _r(e), "tags": pilot_tags(p, e, com)})

    collision = []
    for part in hull_parts:
        for shape in part.collision:
            collision.append({**shape.to_json(digits=JSON_DIGITS), "name": f"{part.name}_{shape.name}" if shape.name else part.name})

    turrets = []
    for name, side in (("tower_l", "l"), ("tower_r", "r")):
        mount = by_name[f"tower_{side}"].anchor("turret")
        turrets.append({"name": name, "position": _r(mount.position), "up": _r(mount.direction), "arc_deg": TURRET_ARC_DEG,
                        "barrel_m": spec.turret.barrel_m})  # fmt: skip

    joints = chunk_joints(spec, offset)
    return {
        "asset_id": ASSET_ID,
        "generator_version": GENERATOR_VERSION,
        "frame": "godot",
        "units": "m",
        "length_m": round(length, 3),
        "span_m": round(float(hi[0] - lo[0]), 3),
        "height_m": round(float(hi[1] - lo[1]), 3),
        "mass_kg": round(total_mass(hull_parts), 1),
        "inertia_estimate_kg_m2": _r(inertia),
        "center_of_mass": _r(com),
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

    Options: ``spacing`` (m, default 0.31; the CLI's ``--spacing``), ``overlap`` (sigma / spacing, default 1.0),
    ``thickness`` (normal sigma / spacing, default 0.08), ``turret_spacing`` (m, default 0.11).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    overlap = float(ctx.option("overlap", DEFAULT_OVERLAP))
    thickness = float(ctx.option("thickness", DEFAULT_THICKNESS))
    turret_spacing = float(ctx.option("turret_spacing", TURRET_SPACING_M))
    if min(spacing, overlap, thickness, turret_spacing) <= 0.0:
        raise ValueError("spacing, overlap, thickness and turret_spacing must be positive")
    spec, style = DEFAULT_SPEC, NARN
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}", "frame: 3dgs (Rz180 of godot)")
    light = {level: lighting.lod_file_name(ASSET_ID, level) for level in (0, *LODS)}

    # LOD0: the full-detail hull, group by group (manifest ``counts`` order).
    placed, offset = centre(build_parts(spec, style, ctx, spacing))
    groups = group_splats(placed, style, overlap, thickness)
    authored = SplatData.concatenate([g.splats for g in groups])
    xyz32 = authored.xyz.astype(np.float32)
    aabb_min, aabb_max = xyz32.min(axis=0), xyz32.max(axis=0)
    files: list[Path] = _write_level(out_dir, PLY_NAME, light[0], authored, comments)
    files += write_obj(out_dir / OBJ_NAME, Mesh.concatenate(p.part.mesh for p in placed if p.hull), ASSET_ID, comments[:1])
    # The painted mesh: the ship as the game draws it from the 2026-11-04 directive (meshes, not splats).
    mesh_path, mesh_entry = cv.write_mesh(out_dir, ASSET_ID, [(p.part.name, p.part.mesh) for p in placed if p.hull], style)
    files.append(mesh_path)

    # LOD1 to LOD3: resampled coarser from their own streams, each centred on its own centroid; LOD1's groups are the chunks.
    counts: dict[int, int] = {}
    chunk_entries: list[dict[str, Any]] = []
    for level, (name, _factor, _stream, _share) in LODS.items():
        lod_placed, _ = level_parts(spec, style, ctx, spacing, level)
        lod_groups = group_splats(lod_placed, style, overlap, thickness)
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
    fine = replace(style, panel_size_m=TURRET_PANEL_M[0], panel_line_width_m=TURRET_PANEL_M[1])
    named = [(turret_part.name, turret_part.mesh.translated(-turret.xyz.mean(axis=0)))]  # the turret files' frame
    mesh_path, turret_entry["paint_mesh"] = cv.write_mesh(out_dir, f"{ASSET_ID}_turret", named, fine)
    files.append(mesh_path)

    hp = hardpoints(placed, spec, chunk_entries, offset)
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
