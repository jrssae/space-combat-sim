"""``skylark_transport``: the Earth Alliance "Delta Gamma 9" type transport, 60 m (M5-T13, D59; docs/assets-civilian.md and
docs/design-references.md, "Skylark transport").

Composition only, like ``narn_transport``: the pieces of ``parts/skylark.py`` in the ``ea_civilian`` style with the
Skylark's own paint, and every output (splats, fallback mesh, hardpoints, chunks, the turret model) derived from the
placed pieces so they agree by construction.

Layout (authored frame, metres, before re-centring; -Z is forward, the nose vanes' tips at z = 0, x and y centred on the
reference model's box, as ``tools/refview`` draws it):

* a capsule 7.46 m across (z 1.7 to 20.5) with a dark nose face, four splayed vanes, a raised bridge plate with a glazed
  front, two red-orange bands and two thin fins under it; behind it the spine and the collar with a ring of vanes at
  each end, and beside them the side tanks (a band each) with a dumbbell tank ahead of each;
* the faceted body (z 32.1 to 51.6), 23.9 m wide, with swept fins at its aft corners, the dorsal fin, the centre
  engine's drum and exhaust cone, and the dorsal turret seated on the body's ridge (Q19, the only turret);
* the nacelles against the body's flanks on a thrust line 0.26 m below the box centre: a ribbed intake, two pods
  pointing up and down outboard, a ribbed dark bell, and two forked claws on short pylons reaching aft to z 60.

LOD0 is written chunk group by chunk group (``manifest.counts``), LOD1 to LOD3 are resampled coarser from their own
streams, and LOD1's groups are the break-up chunks (``chunk_lod`` 1). Right-hand pieces are sampled once and mirrored and
centre-line pieces symmetrised, so every level is exactly mirror-symmetric; samples buried in another piece are dropped.
The turret (D61) is ``parts/turret.py``'s EA turret at two thirds of its size, written like a chunk.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

import numpy as np

from ..core import frames, lighting
from ..core.chunks import ChunkSource, write_chunks
from ..core.context import AssetOutputs, BuildContext
from ..core.geometry import Mesh
from ..core.manifest import build_manifest, lod_entry, write_manifest
from ..core.obj import write_obj
from ..core.ply import SplatData, write_ply
from ..core.sampling import DEFAULT_OVERLAP, DEFAULT_THICKNESS, SurfaceSamples, sample_mesh, to_splats
from ..parts import Part, mass_centroid, total_mass
from ..parts import skylark as sp
from ..parts.propulsion import pilot_tags
from ..parts.skylark import CENTRE, RIGHT, Piece
from ..parts.turret import TurretSpec, write_turret
from ..styles import Style
from ..styles.ea_civilian import ea_civilian

ASSET_ID = "skylark_transport"
GENERATOR_VERSION = 1
PLY_NAME = f"{ASSET_ID}.ply"
OBJ_NAME = f"{ASSET_ID}.obj"
HARDPOINTS_NAME = "hardpoints.json"

# docs/assets-civilian.md: LOD0 60 000 (48 000 to 72 000). The built surface is about half the reference's (no inner
# faces), so the spacing is finer than the planned 0.33 m start.
DEFAULT_SPACING_M = 0.26
SPLAT_BUDGET = (48_000, 72_000)
LODS = {
    1: (f"{ASSET_ID}_lod1.ply", 2.0, "lod1"),  # level: file, spacing factor, RNG stream
    2: (f"{ASSET_ID}_lod2.ply", 4.0, "lod2"),
    3: (f"{ASSET_ID}_lod3.ply", 8.0, "lod3"),
}
LOD_SHARES = {1: (0.20, 0.30), 2: (0.04, 0.09), 3: (0.01, 0.025)}
CHUNK_LOD = 1
CHUNK_ORDER = ("capsule", "body", "nacelle_l", "nacelle_r")

# Q19, colours confirmed: the ea_civilian style with the Skylark's sand plating, red-orange bands and dark bells.
SKYLARK_PAINT = {"hull": 0xB3A982, "hull_panel": 0x7E7552, "hull_dark": 0x4A4536, "stripe": 0xB8452B, "nozzle": 0x4A4A46}
STYLE = replace(ea_civilian(SKYLARK_PAINT), panel_size_m=2.4, panel_line_width_m=0.25)
ENGINE_GLOW_SRGB = 0xFFE9C2  # warm white; a ShipSpec tint (T16), not in the splats

TURRET = TurretSpec().scaled(2.0 / 3.0)  # the EA turret at two thirds: barrel_m 3.0
TURRET_SPACING_M = 0.08
TURRET_SPLATS = (1_500, 3_500)
TURRET_ARC_DEG = 200.0  # a hemisphere plus 10 degrees below the mount's base

BURIED_MARGIN_M = 0.01
JSON_DIGITS = 5
CHASE_ANCHOR_SHARE = (0.3, 1.2)  # above and behind the centroid, in lengths
NAV_CLEARANCE_M = 0.15
NAV_SIDE_Z = 46.5  # the nacelles' outboard flank between the pods and the bell ribs
NAV_LAMP_HEIGHT_M = 4.0
NAV_LAMP_RANGE_SHARE = 0.3
NAV_CABIN_RANGE_SHARE = 0.05


# --- sampling ----------------------------------------------------------------------------------------------------------
def _left(name: str) -> str:
    return name[:-2] + "_l" if name.endswith("_r") else name + "_l"


def mirror_group(group: str) -> str:
    """The chunk of a right piece's left twin: ``nacelle_r`` -> ``nacelle_l``; centre chunks stay."""
    return group[:-2] + "_l" if group.endswith("_r") else group


def with_twins(pieces: list[Piece]) -> list[Piece]:
    """The pieces plus each right piece's mirrored left twin, twin after original."""
    out = []
    for p in pieces:
        out.append(p)
        if p.side == RIGHT:
            out.append(p.mirrored(_left(p.name), mirror_group(p.group)))
    return out


@dataclass
class Sampled:
    piece: Piece
    samples: SurfaceSamples
    spacing: float
    paint_name: str  # the right twin's name: both twins get the same panel pattern


def _right_half_first(mesh: Mesh) -> Mesh:
    """The same faces with the right half's first, so systematic rounding gives a centre piece's kept half its exact
    share of samples and a coarse level keeps LOD0's centroid."""
    right = mesh.face_centroids()[:, 0] > 0.0
    order = np.concatenate([np.flatnonzero(right), np.flatnonzero(~right)])
    return Mesh(mesh.vertices, mesh.faces[order], mesh.face_material[order], mesh.materials)


def sample_hull(pieces: list[Piece], ctx: BuildContext, spacing: float, suffix: tuple[str, ...] = ()) -> list[Sampled]:
    """Every piece of the hull with its samples: hidden samples dropped, centre pieces symmetrised, right pieces
    mirrored; ``suffix`` keeps another level's random draws apart from LOD0's."""
    solids = [(p.name, p.solid, p.solid.bounds()) for p in with_twins(pieces) if p.solid is not None]
    out: list[Sampled] = []
    for p in pieces:
        step = spacing * p.fine
        mesh = p.part.mesh if p.side == RIGHT else _right_half_first(p.part.mesh)
        s = sample_mesh(mesh, step, ctx.rng("splats", p.name, *suffix), systematic=True)
        if len(s):
            lo, hi = s.positions.min(axis=0), s.positions.max(axis=0)
            hidden = np.zeros(len(s), dtype=bool)
            for name, solid, (slo, shi) in solids:
                if name == p.name or np.any(shi < lo) or np.any(slo > hi):
                    continue
                hidden |= solid.contains(s.positions, BURIED_MARGIN_M)
            s = s.subset(~hidden)
        if p.side == CENTRE:
            out.append(Sampled(p, s.symmetrized("x"), step, p.name))
        else:
            out.append(Sampled(p, s, step, p.name))
            out.append(Sampled(p.mirrored(_left(p.name), mirror_group(p.group)), s.mirrored("x"), step, p.name))
    return out


def centre(sampled: list[Sampled]) -> np.ndarray:
    """The splat centroid (x is zero by symmetry): the authored position of the body origin."""
    total = sum(len(s.samples) for s in sampled)
    mean = sum(s.samples.positions.sum(axis=0) for s in sampled) / total
    return np.array([0.0, float(mean[1]), float(mean[2])])


def _phase(name: str, style: Style) -> tuple[float, float, float]:
    h = sum((i + 1) * ord(c) for i, c in enumerate(name))
    return tuple(((h * k) % 97) / 97.0 * style.panel_size_m for k in (7, 11, 13))


def splats_of(s: Sampled, style: Style, offset: np.ndarray, overlap: float, thickness: float) -> SplatData:
    """Paint only (panel lines mirrored across the centre line) and flat splats, in the centred frame: the scene's
    lights do the shading in the game."""
    smp = s.samples.translated(-offset)
    painted_at = s.samples.positions.copy()
    painted_at[:, 0] = np.abs(painted_at[:, 0])
    rgb = style.shade_panels(smp.albedo(), painted_at, smp.normals, smp.material_flag("paneled") > 0.5, _phase(s.paint_name, style))
    return to_splats(smp, rgb, s.spacing, overlap, thickness)


def chunked(sampled: list[Sampled], style: Style, offset: np.ndarray, overlap: float, thickness: float) -> list[ChunkSource]:
    """One source per chunk in ``CHUNK_ORDER``: its pieces' splats and fallback mesh, centred frame."""
    sources = []
    for chunk in CHUNK_ORDER:
        members = [s for s in sampled if s.piece.group == chunk]
        splats = SplatData.concatenate([splats_of(s, style, offset, overlap, thickness) for s in members])
        mesh = Mesh.concatenate(s.piece.part.mesh.translated(-offset) for s in members)
        sources.append(ChunkSource(chunk, splats, mesh))
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


# --- hardpoints --------------------------------------------------------------------------------------------------------
def _r(v: Any) -> list[float]:
    return [round(float(x), JSON_DIGITS) + 0.0 for x in np.asarray(v, dtype=float).reshape(-1)]


def rcs_ports(by_name: dict[str, Part]) -> list[tuple[str, np.ndarray, np.ndarray]]:
    """Cosmetic RCS (authored frame): the right side's nose vane, nacelle pods and corner fin (``r_`` names, mirrored by
    the caller) and, on the centre line, the top and bottom nose vanes, the dorsal fin's crest and the keel aft."""
    vanes = by_name["vanes"]
    keel_z = 50.5
    keel_y = float(sp.BodySpec().at(keel_z)[8])
    ports = [
        ("r_vane", by_name["vane_r"].anchor("vane")),
        ("r_pod_up", by_name["cone_up_r"].anchor("tip")),
        ("r_pod_down", by_name["cone_down_r"].anchor("tip")),
        ("r_corner", by_name["corner_fin_r"].anchor("tip")),
        ("vane_top", vanes.anchor("vane_top")),
        ("vane_bottom", vanes.anchor("vane_bottom")),
        ("fin_top", by_name["dorsal_fin"].anchor("top")),
    ]
    out = [(name, a.position, a.direction) for name, a in ports]
    out.append(("keel", np.array([0.0, keel_y, keel_z]), np.array([0.0, -1.0, 0.0])))
    return out


def chunk_joints() -> dict[str, np.ndarray]:
    """Where each chunk breaks away (authored frame): the capsule where the collar meets the body, a nacelle along its
    seam with the body's flank, the body at the middle of the three."""
    nacelle = np.array([sp.NACELLE_AXIS[0] - 2.4, sp.NACELLE_AXIS[1], 45.5])
    joints = {
        "capsule": np.array([0.0, sp.CAPSULE_AXIS[1], sp.BodySpec().stations[0][0]]),
        "nacelle_r": nacelle,
        "nacelle_l": nacelle * np.array([-1.0, 1.0, 1.0]),
    }
    joints["body"] = np.mean(list(joints.values()), axis=0)
    return joints


def nav_lights(by_name: dict[str, Part], offset: np.ndarray, length: float) -> dict[str, Any]:
    """Running lights: red and green just outboard of the nacelles' flanks, white on the dorsal fin's crest with a lamp
    standing over it, the cabin glow in the bridge."""
    ax, ay = sp.NACELLE_AXIS
    side = np.array([ax + sp.nacelle_radius(NAV_SIDE_Z) + NAV_CLEARANCE_M, ay, NAV_SIDE_Z])
    crest = by_name["dorsal_fin"].anchor("top").position
    top = crest + np.array([0.0, NAV_CLEARANCE_M, 0.0])
    return {
        "port": _r(side * np.array([-1.0, 1.0, 1.0]) - offset),
        "starboard": _r(side - offset),
        "top": _r(top - offset),
        "top_lamp": _r(crest + np.array([0.0, NAV_LAMP_HEIGHT_M, 0.0]) - offset),
        "top_lamp_range_m": round(NAV_LAMP_RANGE_SHARE * length, 2),
        "cabin": _r(by_name["bridge"].anchor("eye").position - offset),
        "cabin_range_m": round(NAV_CABIN_RANGE_SHARE * length, 2),
    }


def hardpoints(everything: list[Piece], chunks: list[dict[str, Any]], offset: np.ndarray) -> dict[str, Any]:
    """The hardpoints document in the centred frame (authored positions minus ``offset``); ``chunks`` are the
    ``write_chunks`` entries (from LOD1)."""
    parts = [p.part for p in everything]
    by_name = {p.name: p for p in parts}
    lo, hi = Mesh.concatenate(p.mesh for p in parts).bounds()
    length = float(hi[2] - lo[2])
    # On the thrust line (the nacelles' axis), so main thrust makes no pitch torque.
    com = np.array([0.0, sp.NACELLE_AXIS[1], float(mass_centroid(parts)[2])])
    inertia = np.zeros(3)
    for part in parts:
        d = part.area_centroid() - com
        inertia += part.mass_kg * np.array([d[1] ** 2 + d[2] ** 2, d[0] ** 2 + d[2] ** 2, d[0] ** 2 + d[1] ** 2])

    pods = []
    for name, side in (("l", "left"), ("r", "right")):
        nacelle = by_name[f"nacelle_{name}"]
        main, retro = nacelle.anchor("main"), nacelle.anchor("retro")
        pods.append({
            "name": name,
            "side": side,
            "center": _r(nacelle.anchor("centre").position - offset),
            "main": {"position": _r(main.position - offset), "exhaust": _r(main.direction), "radius": sp.NACELLE_EXIT_R},
            "retro": {"position": _r(retro.position - offset), "exhaust": _r(retro.direction), "radius": sp.NACELLE_INTAKE_R},
        })  # fmt: skip

    rcs = []
    flip = np.array([-1.0, 1.0, 1.0])
    for name, position, exhaust in rcs_ports(by_name):
        twins = [(name, position, exhaust)]
        if name.startswith("r_"):
            twins.append(("l_" + name[2:], position * flip, exhaust * flip))
        for n, p, e in twins:
            rcs.append({"name": n, "pod": "l" if p[0] < -1e-6 else "r", "position": _r(p - offset), "exhaust": _r(e),
                        "tags": pilot_tags(p, e, com)})  # fmt: skip

    collision = []
    for part in parts:
        for shape in part.collision:
            collision.append({**shape.to_json(offset=offset, digits=JSON_DIGITS), "name": f"{part.name}_{shape.name}" if shape.name else part.name})

    mount = by_name["body"].anchor("turret")
    turrets = [{"name": "dorsal", "position": _r(mount.position - offset), "up": _r(mount.direction), "arc_deg": TURRET_ARC_DEG,
                "barrel_m": round(TURRET.barrel_m, JSON_DIGITS)}]  # fmt: skip
    joints = chunk_joints()
    eye = by_name["bridge"].anchor("eye").position
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
        "cockpit_camera": {"position": _r(eye - offset), "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
        "chase_anchor": {"position": _r((0.0, CHASE_ANCHOR_SHARE[0] * length, CHASE_ANCHOR_SHARE[1] * length))},
        "muzzles": [],
        "pods": pods,
        "rcs": rcs,
        "collision": collision,
        "nav_lights": nav_lights(by_name, offset, length),
        "turrets": turrets,
        "chunks": [{**c, "joint": _r(joints[c["name"]] - offset)} for c in chunks],
    }


# --- build -------------------------------------------------------------------------------------------------------------
def lod_file(level: int) -> str:
    return PLY_NAME if level == 0 else LODS[level][0]


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the ship and its turret into ``ctx.out_dir``.

    Options: ``spacing`` (m, default 0.26; the CLI's ``--spacing``), ``overlap`` (sigma / spacing, default 1.0),
    ``thickness`` (normal sigma / spacing, default 0.08), ``turret_spacing`` (m, default 0.08).
    """
    spacing = float(ctx.option("spacing", DEFAULT_SPACING_M))
    overlap = float(ctx.option("overlap", DEFAULT_OVERLAP))
    thickness = float(ctx.option("thickness", DEFAULT_THICKNESS))
    turret_spacing = float(ctx.option("turret_spacing", TURRET_SPACING_M))
    if min(spacing, overlap, thickness, turret_spacing) <= 0.0:
        raise ValueError("spacing, overlap, thickness and turret_spacing must be positive")
    style = STYLE
    out_dir = ctx.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    comments = (f"{ASSET_ID} generator v{GENERATOR_VERSION} seed {ctx.seed}", "frame: 3dgs (Rz180 of godot)")
    light = {level: lighting.lod_file_name(ASSET_ID, level) for level in (0, *LODS)}

    pieces = sp.assemble(style)
    everything = with_twins(pieces)
    unknown = {p.group for p in everything} - set(CHUNK_ORDER)
    if unknown:
        raise ValueError(f"pieces in unlisted chunks {sorted(unknown)}")

    # LOD0: the chunk groups concatenated (manifest ``counts`` order).
    lod0 = sample_hull(pieces, ctx, spacing)
    offset = centre(lod0)
    groups = chunked(lod0, style, offset, overlap, thickness)
    authored = SplatData.concatenate([g.splats for g in groups])
    xyz32 = authored.xyz.astype(np.float32)
    aabb_min, aabb_max = xyz32.min(axis=0), xyz32.max(axis=0)
    files: list[Path] = _write_level(out_dir, PLY_NAME, light[0], authored, comments)
    files += write_obj(out_dir / OBJ_NAME, Mesh.concatenate(p.part.mesh.translated(-offset) for p in everything), ASSET_ID, comments[:1])

    # LOD1 to LOD3: resampled coarser from their own streams, each centred on its own centroid; LOD1's groups are the chunks.
    counts: dict[int, int] = {}
    chunk_entries: list[dict[str, Any]] = []
    for level, (name, factor, stream) in LODS.items():
        sampled = sample_hull(pieces, ctx, factor * spacing, (stream,))
        lod_groups = chunked(sampled, style, centre(sampled), overlap, thickness)
        lod = SplatData.concatenate([g.splats for g in lod_groups])
        counts[level] = len(lod)
        level_comments = comments + (f"lod {level}",)
        files += _write_level(out_dir, name, light[level], lod, level_comments)
        if level == CHUNK_LOD:
            chunk_files, chunk_entries = write_chunks(out_dir, ASSET_ID, lod_groups, level_comments)
            files += chunk_files

    turret_files, turret_entry = write_turret(out_dir, ASSET_ID, TURRET, style, ctx, turret_spacing, overlap, thickness, comments)
    files += turret_files

    hp = hardpoints(everything, chunk_entries, offset)
    hp_path = out_dir / HARDPOINTS_NAME
    hp_path.write_text(json.dumps(hp, indent=2) + "\n", encoding="utf-8", newline="\n")
    files.append(hp_path)

    total = len(authored)
    warnings: list[str] = []
    if abs(spacing - DEFAULT_SPACING_M) < 1e-12:
        if not SPLAT_BUDGET[0] <= total <= SPLAT_BUDGET[1]:
            warnings.append(f"{total} splats is outside the budget {SPLAT_BUDGET} at the default spacing")
        for level, share in LOD_SHARES.items():
            if not share[0] <= counts[level] / total <= share[1]:
                warnings.append(f"LOD{level} has {counts[level] / total:.1%} of LOD0's splats, outside {share}")
    if abs(turret_spacing - TURRET_SPACING_M) < 1e-12 and not TURRET_SPLATS[0] <= turret_entry["splats"] <= TURRET_SPLATS[1]:
        warnings.append(f"the turret has {turret_entry['splats']} splats, outside {TURRET_SPLATS}")
    manifest = build_manifest(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        seed=ctx.seed,
        lods=[lod_entry(0, PLY_NAME, total, spacing, light[0])]
        + [lod_entry(level, lod_file(level), counts[level], LODS[level][1] * spacing, light[level]) for level in LODS],
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
        },
    )
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files), tuple(warnings))
